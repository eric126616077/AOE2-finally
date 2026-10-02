local MatchRules=require("../src/ServerScriptService/ServerModules/MatchRules")
-- verify.ps1 substitutes the module require while preserving its actual validation body.
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local payload={expectedPlayers=2,size="Small",aiCount=2,difficulty="Normal",population=100,startingResources="Standard",victory="Conquest"}
local settings,expected=LobbyRules.settings(payload)
expect(settings and expected==2 and settings.aiCount==2,"valid two-human lobby rejected")
for _,value in ipairs({0,5,1.5,math.huge,0/0,false,"2"}) do
 local invalid=table.clone(payload); invalid.expectedPlayers=value
 expect(not LobbyRules.settings(invalid),"invalid player count accepted")
end
local invalid=table.clone(payload); invalid.aiCount=3
expect(not LobbyRules.settings(invalid),"lobby permitted more than four factions")
expect(not LobbyRules.settings(false),"non-table settings accepted")
expect(not LobbyRules.canStart(2,{{queued=true,ready=true}}),"started before everyone arrived")
expect(not LobbyRules.canStart(2,{{queued=true,ready=true},{queued=true,ready=false}}),"started before everyone was ready")
expect(not LobbyRules.canStart(2,{{queued=true,ready=true},{queued=false,ready=true}}),"unqueued player started match")
expect(LobbyRules.canStart(2,{{queued=true,ready=true},{queued=true,ready=true}}),"ready pair could not start")
expect(LobbyRules.canStart(1,{{queued=true,ready=true}}),"solo practice could not start")
expect(not LobbyRules.canStart(2,{{queued=true,ready=true},{queued=true,ready=true},{queued=true,ready=true}}),"overfilled lobby started")
expect(not LobbyRules.canStart(math.huge,{}),"non-finite count started")
local earlierPlayer={id=10,playing=true}
local queuedHost={id=20,playing=true}
local spectator={id=30,playing=false}
local humans={earlierPlayer,queuedHost,spectator}
expect(LobbyRules.matchHost(20,humans)==20,"spectator join replaced the online queue host")
expect(LobbyRules.matchHost(10,humans)==10,"online host was not retained")
expect(LobbyRules.matchHost(30,humans)==30,"online spectator host lost rematch authority")
expect(LobbyRules.matchHost(20,{spectator,earlierPlayer})==10,"departed host should migrate to a participant before a spectator")
expect(LobbyRules.matchHost(99,{earlierPlayer,queuedHost})==10,"host migration ignored sorted participant order")
expect(LobbyRules.matchHost(nil,{earlierPlayer,queuedHost})==10,"initial match host should choose the first participant")
expect(LobbyRules.matchHost(20,{spectator,{id=40,playing=false}})==30,"match without participants should give the first spectator rematch authority")
expect(LobbyRules.matchHost(20,{})==0,"empty server retained a departed host")
expect(LobbyRules.matchHost(20,false)==0,"invalid human list should not assign a host")
expect(humans[1]==earlierPlayer and humans[2]==queuedHost and humans[3]==spectator,"host selection reordered caller state")
local queued={{id=10,ai=false,queued=true,ready=true},{id=20,ai=false,queued=true,ready=true}}
local preview=assert(LobbyRules.teamPreview("CoopAI",2,queued,{-10001,-10002}))
expect(preview.teamById[10]==1 and preview.teamById[20]==1 and preview.teamById[-10001]==2,"server coop lobby preview has wrong alliance")
preview=assert(LobbyRules.teamPreview("Teams",2,queued,{-10001,-10002}))
expect(preview.teamById[10]~=preview.teamById[20] and #preview.teamMembers[1]==2 and #preview.teamMembers[2]==2,"mixed lobby preview has unfair teams")
expect(not LobbyRules.teamPreview("Teams",4,queued,{}),"unfilled lobby invented missing participants")
expect(not LobbyRules.teamPreview("CoopAI",2,queued,{}),"coop preview fabricated AI opponents")
expect(not LobbyRules.teamPreview("Teams",2,{queued[1],{id=20,ai=false,queued=false}},{}),"spectator joined lobby team preview")
expect(not LobbyRules.teamPreview("Teams",2,{queued[1],{id=20,ai=false,queued=true,spectator=true}},{}),"explicit spectator joined lobby team preview")
expect(not LobbyRules.teamPreview("Teams",2,{queued[1],{id=20,ai=false,queued=true,playing=true}},{}),"playing faction entered lobby preview")
expect(not LobbyRules.teamPreview("Teams",2,{queued[1],{id=20,ai=true,queued=true}},{}),"AI slot substituted for expected human")
expect(not LobbyRules.teamPreview("Teams",2,{queued[1],queued[1]},{}),"duplicate human ID acquired two lobby slots")
expect(not LobbyRules.teamPreview("Teams",2,queued,{-10001,-10001}),"duplicate AI IDs acquired separate slots")
expect(not LobbyRules.teamPreview("Teams",2,queued,{[2]=-10001}),"sparse AI preview list accepted")
expect(not LobbyRules.teamPreview("Teams",2,queued,{-10001,-10002,extra=-10003}),"dictionary AI preview accepted")
expect(not LobbyRules.teamPreview("Teams",2,queued,{0,-10002}),"invalid AI ID acquired lobby team")
expect(queued[1].id==10 and queued[1].ready and queued[1].teamId==nil,"preview changed authoritative queue state")
local teamPayload=table.clone(payload); teamPayload.teamMode="Teams"
settings,expected=LobbyRules.settings(teamPayload)
expect(settings and expected==2 and settings.teamMode=="Teams","lobby dropped canonical team mode")
teamPayload.aiCount=1
expect(not LobbyRules.settings(teamPayload),"lobby accepted unbalanced 2v1 settings")
local portals=Config.Lobby.portals
expect(type(portals)=="table" and #portals==4,"courtyard must provide four configured matching points")
local seen={}
for _,portal in ipairs(portals) do
 expect(not seen[portal.id],"duplicate portal would share another room's queue")
 seen[portal.id]=true
 expect(LobbyRules.room(portals,portal.id)==portal,"configured portal did not resolve to its own room")
 local preset,humans=LobbyRules.settings(portal.settings)
 expect(preset~=nil and humans==portal.settings.expectedPlayers,"portal default settings cannot start a valid match")
 expect(humans+preset.aiCount<=4,"portal exceeds maximum faction count")
end
expect(seen.Room1 and seen.Room2 and seen.Room3 and seen.Room4,"expected matching points missing")
expect(LobbyRules.room(portals,nil).id=="Room1","legacy omitted room must use the first portal")
expect(LobbyRules.room(portals,"Custom").id=="Room1","legacy custom caller must use the first portal")
for _,roomId in ipairs({false,12,{},"","room1","Room1 ","Practice","Duel","Teams","Room1/../../Room2",string.rep("x",25)}) do
 expect(LobbyRules.room(portals,roomId)==nil,"untrusted identifier created or aliased another room")
end
expect(LobbyRules.room(false,"Room1")==nil,"invalid portal catalog accepted")
local previousSettings
for _,portal in ipairs(portals) do
 local initial=portal.settings
 expect(initial.expectedPlayers==2 and initial.aiCount==0 and initial.teamMode=="FFA","matching points must share the same human-versus-human default")
 expect(initial.size=="Medium" and initial.startingResources=="Standard","matching point has an unexpected preset")
 expect(initial~=previousSettings,"rooms share a mutable settings table")
 previousSettings=initial
end
print(string.format("PASS: %d lobby settings / readiness / portal validation checks",count))
