-- 跨 place 對局：verify.ps1 先注入 Config、LobbyRules、PlaceRules 與 MatchTravel 的實際模組內容。
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end

-- 角色判定：只有兩個不同的有效 place 才分流；Studio 只能明確模擬對戰 place。
local split={lobbyPlaceId=100,matchPlaceId=200}
expect(PlaceRules.role(Config.Places,100,false)=="Combined","unconfigured default places split the server")
expect(PlaceRules.role(split,100,false)=="Lobby","lobby place not detected")
expect(PlaceRules.role(split,200,false)=="Match","match place not detected")
expect(PlaceRules.role(split,300,false)=="Combined","unknown place assumed a split role")
expect(PlaceRules.role(split,200,true)=="Combined","Studio attempted real teleports")
expect(PlaceRules.role(split,0,true,"Match")=="Match","Studio match simulation ignored")
expect(PlaceRules.role(split,0,true,"Lobby")=="Combined","Studio lobby simulation would need real teleports")
expect(PlaceRules.role({lobbyPlaceId=5,matchPlaceId=5},5,false)=="Combined","identical place ids split")
expect(PlaceRules.role({lobbyPlaceId=1.5,matchPlaceId=2},2,false)=="Combined","fractional place id accepted")
expect(PlaceRules.role({lobbyPlaceId=-1,matchPlaceId=2},2,false)=="Combined","negative place id accepted")
expect(PlaceRules.reserved("abc",0),"reserved server rejected")
expect(not PlaceRules.reserved("",0),"public server treated as reserved")
expect(not PlaceRules.reserved("abc",123),"VIP server treated as reserved")
expect(not PlaceRules.reserved(nil,0),"missing private server id accepted")

-- 票據：大廳驗證過的設定與名單完整往返；任何竄改或過期都整張拒絕。
local settings=assert(LobbyRules.settings({expectedPlayers=2,size="Small",aiCount=1,difficulty="Hard",population=150,startingResources="Rich",victory="Wonder",teamMode="FFA"}))
local ticket=PlaceRules.newTicket("match-1","Room2",settings,{{id=11,civilization="Riverland"},{id=12,tutorial=true}},1000)
expect(ticket.settings~=settings,"ticket shares the lobby settings table")
local read,message=PlaceRules.readTicket(ticket,1010,600,Config.Lobby.portals)
expect(read,"valid ticket rejected: "..tostring(message))
expect(read.roomId=="Room2" and read.expected==2 and read.matchId=="match-1","ticket identity changed")
expect(read.settings.aiCount==1 and read.settings.size=="Small" and read.settings.victory=="Wonder" and read.settings.difficulty=="Hard","ticket settings changed")
expect(read.players[1].civilization=="Riverland" and read.players[2].tutorial==true and read.players[1].tutorial==false,"ticket roster changed")
expect(PlaceRules.member(read,12)==read.players[2] and PlaceRules.member(read,99)==nil,"ticket membership lookup wrong")
expect(PlaceRules.member(nil,12)==nil,"missing ticket has members")
-- 聖物勝利模式同樣經過大廳驗證並完整寫入票據；未知的勝利模式在大廳就被拒絕。
local relicSettings=assert(LobbyRules.settings({expectedPlayers=2,size="Large",aiCount=2,difficulty="Normal",population=200,startingResources="Standard",victory="Relic",teamMode="FFA"}))
local relicRead=PlaceRules.readTicket(PlaceRules.newTicket("match-relic","Room1",relicSettings,{{id=21},{id=22}},1000),1001,600,Config.Lobby.portals)
expect(relicRead and relicRead.settings.victory=="Relic","relic victory lost in the ticket")
expect(LobbyRules.settings({expectedPlayers=2,size="Small",aiCount=0,difficulty="Normal",population=100,startingResources="Standard",victory="Relics",teamMode="FFA"})==nil,"unknown victory mode accepted")
local function rejected(mutate,label,now)
 local copy=table.clone(ticket)
 copy.settings=table.clone(ticket.settings)
 copy.players={}
 for index,entry in ipairs(ticket.players) do copy.players[index]=table.clone(entry) end
 mutate(copy)
 expect(PlaceRules.readTicket(copy,now or 1010,600,Config.Lobby.portals)==nil,label)
end
expect(PlaceRules.readTicket(nil,1010,600,Config.Lobby.portals)==nil,"missing ticket accepted")
expect(PlaceRules.readTicket("ticket",1010,600,Config.Lobby.portals)==nil,"string ticket accepted")
expect(PlaceRules.readTicket(ticket,1601,600,Config.Lobby.portals)==nil,"expired ticket accepted")
expect(PlaceRules.readTicket(ticket,900,600,Config.Lobby.portals)==nil,"ticket from the future accepted")
rejected(function(t) t.v=2 end,"unknown ticket version accepted")
rejected(function(t) t.matchId="" end,"empty match id accepted")
rejected(function(t) t.matchId=string.rep("x",65) end,"oversized match id accepted")
rejected(function(t) t.roomId="Room9" end,"unknown room accepted")
rejected(function(t) t.createdAt=0/0 end,"NaN creation time accepted")
rejected(function(t) t.expected=3 end,"expected count mismatch accepted")
rejected(function(t) t.players={} ; t.expected=0 end,"empty roster accepted")
rejected(function(t) t.players[2].userId=11 end,"duplicate player accepted")
rejected(function(t) t.players[2].userId=-4 end,"negative user id accepted")
rejected(function(t) t.players[2].userId=12.5 end,"fractional user id accepted")
rejected(function(t) t.players[2].userId="12" end,"string user id accepted")
rejected(function(t) t.players[1].civilization=string.rep("c",33) end,"oversized civilization accepted")
rejected(function(t) t.players[1].tutorial="yes" end,"non-boolean tutorial accepted")
rejected(function(t)
 for index=3,5 do t.players[index]={userId=20+index} end
 t.expected=5
end,"five-player roster accepted")
rejected(function(t) t.settings.money=999 end,"injected settings field accepted")
rejected(function(t) t.settings.expectedPlayers=4 end,"ticket overrode the roster count")
rejected(function(t) t.settings.aiCount=3 end,"more than four factions accepted")
rejected(function(t) t.settings.population=9999 end,"unsupported population accepted")
rejected(function(t) t.settings=nil end,"missing settings accepted")

-- 劇情與新手教程：大廳已檢查章節解鎖與內部模式，對戰伺服器仍要接受並保留章節規則。
local storySettings=assert(LobbyRules.settings(GameModeRules.defaults("Story",2,4),{unlocked=4}))
expect(storySettings.gameMode=="Story" and storySettings.storyChapter==4,"story defaults changed chapter")
local storyRead,storyMessage=PlaceRules.readTicket(PlaceRules.newTicket("story-1","Room1",storySettings,{{id=31},{id=32}},1000),1010,600,Config.Lobby.portals)
expect(storyRead,"unlocked story chapter rejected by the match server: "..tostring(storyMessage))
expect(storyRead.settings.gameMode=="Story" and storyRead.settings.storyChapter==4 and storyRead.settings.teamMode=="CoopAI"
 and storyRead.settings.aiCount==storySettings.aiCount and storyRead.settings.victory==storySettings.victory,"story chapter rules lost in the ticket")
local tamperedStory=PlaceRules.newTicket("story-2","Room1",storySettings,{{id=31},{id=32}},1000)
tamperedStory.settings.victory="Wonder"; tamperedStory.settings.aiCount=0
local tamperedRead=PlaceRules.readTicket(tamperedStory,1010,600,Config.Lobby.portals)
expect(tamperedRead==nil or (tamperedRead.settings.victory==storySettings.victory and tamperedRead.settings.aiCount==storySettings.aiCount),"edited story ticket bypassed chapter rules")
expect(PlaceRules.readTicket(PlaceRules.newTicket("story-3","Room1",storySettings,{{id=31},{id=32},{id=33},{id=34}},1000),1010,600,Config.Lobby.portals)==nil,"story ticket exceeded its player limit")
local sandbox=assert(LobbyRules.settings({gameMode="Sandbox",expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"},{internal=true}))
local sandboxRead,sandboxMessage=PlaceRules.readTicket(PlaceRules.newTicket("tutorial-1","Room3",sandbox,{{id=41,tutorial=true}},1000),1010,600,Config.Lobby.portals)
expect(sandboxRead and sandboxRead.settings.gameMode=="Sandbox" and sandboxRead.players[1].tutorial==true,"tutorial ticket rejected by the match server: "..tostring(sandboxMessage))
expect(LobbyRules.settings({gameMode="Sandbox",expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"})==nil,"lobby players can create the internal tutorial mode")

-- Studio 測試玩家：負數 UserId 只在伺服器判定為 Studio 時接受；票據內的旗標不能放寬檢查。
local testRoster={{id=-1},{id=-2}}
local testTicket=PlaceRules.newTicket("studio-1","Room1",settings,testRoster,1000)
expect(PlaceRules.ticketOptions(false)==nil,"live server produced relaxed ticket options")
expect(PlaceRules.ticketOptions("true")==nil and PlaceRules.ticketOptions(1)==nil and PlaceRules.ticketOptions(nil)==nil,"non-boolean Studio flag relaxed ticket checks")
expect(PlaceRules.ticketOptions(true).studioIds==true,"Studio did not relax test player ids")
expect(PlaceRules.readTicket(testTicket,1010,600,Config.Lobby.portals)==nil,"negative test ids accepted by default")
expect(PlaceRules.readTicket(testTicket,1010,600,Config.Lobby.portals,PlaceRules.ticketOptions(false))==nil,"negative test ids accepted on a live server")
local flagged=PlaceRules.newTicket("studio-2","Room1",settings,testRoster,1000)
flagged.studioIds=true; flagged.options={studioIds=true}; flagged.settings.studioIds=nil
expect(PlaceRules.readTicket(flagged,1010,600,Config.Lobby.portals,PlaceRules.ticketOptions(false))==nil,"ticket-supplied studioIds flag relaxed a live server")
expect(PlaceRules.readTicket(flagged,1010,600,Config.Lobby.portals)==nil,"ticket-supplied studioIds flag relaxed default checks")
local settingsFlagged=PlaceRules.newTicket("studio-3","Room1",settings,testRoster,1000)
settingsFlagged.settings.studioIds=true
expect(PlaceRules.readTicket(settingsFlagged,1010,600,Config.Lobby.portals,PlaceRules.ticketOptions(true))==nil,"studioIds smuggled into settings accepted")
local studioRead,studioMessage=PlaceRules.readTicket(testTicket,1010,600,Config.Lobby.portals,PlaceRules.ticketOptions(true))
expect(studioRead and studioRead.players[1].userId==-1 and studioRead.players[2].userId==-2,"Studio test ids rejected: "..tostring(studioMessage))
expect(PlaceRules.member(studioRead,-2)==studioRead.players[2],"Studio test player not found in roster")
local studio=PlaceRules.ticketOptions(true)
expect(PlaceRules.readTicket(PlaceRules.newTicket("studio-4","Room1",settings,{{id=0},{id=-2}},1000),1010,600,Config.Lobby.portals,studio)==nil,"zero user id accepted in Studio")
expect(PlaceRules.readTicket(PlaceRules.newTicket("studio-5","Room1",settings,{{id=-1.5},{id=-2}},1000),1010,600,Config.Lobby.portals,studio)==nil,"fractional test id accepted in Studio")
expect(PlaceRules.readTicket(PlaceRules.newTicket("studio-6","Room1",settings,{{id=-1},{id=-1}},1000),1010,600,Config.Lobby.portals,studio)==nil,"duplicate test id accepted in Studio")
expect(PlaceRules.readTicket(PlaceRules.newTicket("studio-7","Room1",settings,{{id=0/0},{id=-2}},1000),1010,600,Config.Lobby.portals,studio)==nil,"NaN user id accepted in Studio")
expect(PlaceRules.readTicket(PlaceRules.newTicket("studio-8","Room1",settings,{{id=-math.huge},{id=-2}},1000),1010,600,Config.Lobby.portals,studio)==nil,"infinite user id accepted in Studio")
expect(PlaceRules.readTicket(ticket,1010,600,Config.Lobby.portals,studio)~=nil,"Studio rejected ordinary positive ids")

-- 抵達：全員到齊立即開局，逾時以已到者開局，沒有人到則放棄。
expect(PlaceRules.arrival(2,2,0,45)=="start","full roster waited")
expect(PlaceRules.arrival(2,1,10,45)=="wait","partial roster started early")
expect(PlaceRules.arrival(2,1,46,45)=="start","partial roster never started")
expect(PlaceRules.arrival(2,0,0,45)=="wait","empty server aborted before timeout")
expect(PlaceRules.arrival(2,0,46,45)=="abort","empty server started a match")
expect(PlaceRules.arrival(0/0,1,0,45)=="abort","invalid expected count accepted")
expect(PlaceRules.arrival(2,1,0/0,45)=="abort","invalid elapsed time accepted")

expect(PlaceRules.retry("Flooded",1,3)=="retry","flooded teleport not retried")
expect(PlaceRules.retry("Failure",2,3)=="retry","failed teleport not retried")
expect(PlaceRules.retry("Flooded",3,3)=="fail","teleport retried forever")
expect(PlaceRules.retry("GameFull",1,3)=="fail","full server retried")
expect(PlaceRules.retry("Unauthorized",1,3)=="fail","unauthorized teleport retried")
expect(PlaceRules.retry("IsTeleporting",1,3)=="ignore","in-flight teleport resent")

-- 傳送服務：以替身驗證預留、票據、整隊傳送、重試與失敗恢復。
local Players={}
local function player(id) return {Name="Player"..id,UserId=id,Parent=Players} end
local function signal() return {Connect=function(self,callback) self.callback=callback; return {Disconnect=function() end} end} end
local function services(plan)
 plan=plan or {}
 local teleport={TeleportInitFailed=signal(),calls={},reserves=0}
 function teleport:ReserveServer(placeId)
  self.reserves+=1
  if plan.reserveFailures and self.reserves<=plan.reserveFailures then error("reserve unavailable") end
  self.reservedFor=placeId
  return "access-code","private-"..self.reserves
 end
 function teleport:TeleportAsync(placeId,players,options)
  table.insert(self.calls,{placeId=placeId,players=players,options=options})
  if plan.teleportFailures and #self.calls<=plan.teleportFailures then error("teleport unavailable") end
 end
 local tickets={values={},removed={},reads=0}
 function tickets:SetAsync(key,value,ttl)
  if plan.ticketFailures then error("memory store unavailable") end
  self.values[key]={value=value,ttl=ttl}
 end
 function tickets:GetAsync(key)
  self.reads+=1
  if plan.readFailures and self.reads<=plan.readFailures then error("read unavailable") end
  local entry=self.values[key]
  return entry and entry.value
 end
 function tickets:RemoveAsync(key) self.removed[key]=true; self.values[key]=nil end
 return teleport,tickets
end
local places={lobbyPlaceId=100,matchPlaceId=200,ticketTtl=600,ticketReadAttempts=3,teleportAttempts=3,retryPause=1}
local function travel(role,plan)
 local teleport,tickets=services(plan)
 local waits,logs={},{}
 local service=MatchTravel.new(places,role,{teleport=teleport,tickets=tickets,wait=function(seconds) table.insert(waits,seconds) end,
  log=function(message) table.insert(logs,message) end,makeOptions=function(code,data) return {code=code,data=data} end})
 return service,teleport,tickets,waits,logs
end

local combined=MatchTravel.new(places,"Combined",{})
expect(combined.connection==nil and combined.tickets==nil,"single-server mode touched teleport services")
expect(combined:Dispatch({player(1)},ticket)==false,"single-server mode dispatched a teleport")

local lobby,teleport,tickets=travel("Lobby")
local a,b=player(1),player(2)
local ok=lobby:Dispatch({a,b},ticket,function() end)
expect(ok,"healthy dispatch failed")
expect(teleport.reservedFor==200,"reserved the wrong place")
expect(tickets.values["private-1"] and tickets.values["private-1"].value==ticket and tickets.values["private-1"].ttl==600,"ticket not stored under the private server id")
expect(#teleport.calls==1 and teleport.calls[1].placeId==200 and #teleport.calls[1].players==2,"team not teleported together")
expect(teleport.calls[1].options.code=="access-code" and teleport.calls[1].options.data.matchId=="match-1","reserved access code not used")
expect(lobby.pending[a] and lobby.pending[b],"dispatched players not tracked")

-- 傳送後的暫時性失敗只重送該玩家；耗盡次數才恢復。
local failed={}
lobby.pending[a].onFailed=function(actor,name) table.insert(failed,{actor=actor,name=name}) end
teleport.TeleportInitFailed.callback(a,"Flooded","busy",200,teleport.calls[1].options)
expect(#teleport.calls==2 and teleport.calls[2].players[1]==a and #teleport.calls[2].players==1,"flooded teleport not resent for the player")
expect(teleport.calls[2].options.code=="access-code","retry lost the reserved access code")
teleport.TeleportInitFailed.callback(a,"IsTeleporting","busy",200,teleport.calls[1].options)
expect(#teleport.calls==2 and #failed==0,"in-flight teleport resent or failed")
teleport.TeleportInitFailed.callback(a,"Flooded","busy",200,teleport.calls[1].options)
teleport.TeleportInitFailed.callback(a,"Flooded","busy",200,teleport.calls[1].options)
expect(#failed==1 and failed[1].actor==a and failed[1].name=="Flooded","exhausted retries did not restore the player")
expect(lobby.pending[a]==nil,"failed player still pending")
teleport.TeleportInitFailed.callback(a,"Flooded","busy",200,teleport.calls[1].options)
expect(#failed==1,"failure reported twice")
local cancelled=false
lobby.pending[b].onFailed=function() cancelled=true end
lobby:Cancel(b)
teleport.TeleportInitFailed.callback(b,"GameFull","full",200,teleport.calls[1].options)
expect(not cancelled,"cancelled player restored after leaving")
local gone=player(3)
lobby.pending[gone]={attempts=1}
gone.Parent=nil
local before=#teleport.calls
teleport.TeleportInitFailed.callback(gone,"Flooded","busy",200,{})
expect(#teleport.calls==before,"departed player teleported again")

local retryLobby,retryTeleport,retryTickets,retryWaits=travel("Lobby",{reserveFailures=2,teleportFailures=1})
expect(retryLobby:Dispatch({player(4)},ticket),"transient reserve / teleport failures not retried")
expect(retryTeleport.reserves==3 and #retryTeleport.calls==2 and retryTickets.values["private-3"],"retry did not reach the reserved server")
expect(#retryWaits==3,"retries did not back off")

local downLobby,downTeleport,downTickets,_,downLogs=travel("Lobby",{reserveFailures=3})
local okDown,downMessage=downLobby:Dispatch({player(5)},ticket)
expect(not okDown and type(downMessage)=="string" and #downTeleport.calls==0 and next(downTickets.values)==nil,"failed reserve still teleported")
expect(#downLogs==1,"reserve failure not logged")

local storeLobby,storeTeleport=travel("Lobby",{ticketFailures=true})
expect(not storeLobby:Dispatch({player(6)},ticket) and #storeTeleport.calls==0,"teleported without a stored ticket")

local sendLobby,sendTeleport,sendTickets=travel("Lobby",{teleportFailures=3})
local sender=player(7)
expect(not sendLobby:Dispatch({sender},ticket) and #sendTeleport.calls==3,"failed teleport not retried three times")
expect(sendTickets.removed["private-1"] and sendLobby.pending[sender]==nil,"failed teleport left a ticket or pending player")

local offline=player(8)
local partialLobby,partialTeleport=travel("Lobby")
offline.Parent=nil
expect(partialLobby:Dispatch({player(9),offline},ticket) and #partialTeleport.calls[1].players==1,"departed player included in team teleport")

-- 對戰伺服器：讀取自己的票據（含重試）、清除與送回大廳。
local match,matchTeleport,matchTickets,matchWaits=travel("Match",{readFailures=2})
matchTickets.values["private-x"]={value=ticket}
expect(match:ReadTicket("private-x")==ticket and #matchWaits==2,"ticket read not retried")
expect(match:ReadTicket("missing")==nil,"missing ticket invented")
match:RemoveTicket("private-x")
expect(matchTickets.removed["private-x"],"ticket not removed after use")
expect(match:Dispatch({player(10)},ticket)==false,"match server dispatched another match")
local home={player(11),player(12)}
expect(match:Return(home),"return to lobby failed")
expect(matchTeleport.calls[1].placeId==100 and #matchTeleport.calls[1].players==2 and matchTeleport.calls[1].options.code==nil,"return did not go to the public lobby place")
expect(match:Return({})==false,"empty return teleported")
local unreadable=travel("Match",{readFailures=5})
expect(unreadable:ReadTicket("private-x")==nil,"unreadable ticket returned a value")
expect(lobby:ReadTicket("private-1")==nil and lobby:Return({player(13)})==false,"lobby server used match-only travel")

print("PASS: "..checks.." place role / match ticket / arrival / teleport retry / return checks")
