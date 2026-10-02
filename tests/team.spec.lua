local Teams=require("../src/ServerScriptService/ServerModules/TeamRules")
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local function roster(humans,ais)
 local result={}
 for i=1,humans do table.insert(result,{id=i*10,ai=false}) end
 for i=1,ais do table.insert(result,{id=-10000-i,ai=true}) end
 return result
end
local function assigned(mode,humans,ais)
 local map,message=Teams.assign(mode,roster(humans,ais))
 assert(map,message)
 return map
end
local function rejected(mode,members,message)
 local map,errorMessage=Teams.assign(mode,members)
 expect(map==nil and type(errorMessage)=="string",message)
end

local ffa=assigned("FFA",4,0)
expect(#ffa.teamIds==4,"FFA must have four distinct teams")
expect(Teams.allied(ffa,10,10),"registered owner lost self alliance")
expect(not Teams.allied(ffa,10,20) and Teams.enemies(ffa,10,20),"FFA opponents became allies")
expect(not Teams.enemies(ffa,10,10),"faction can attack itself")
for _,id in ipairs({0,999,-999,math.huge,0/0,1.5,"10",false}) do
 expect(Teams.team(ffa,id)==nil,"unknown or invalid ID acquired a team")
 expect(not Teams.allied(ffa,id,id),"spectator or unknown ID allied with itself")
 expect(not Teams.allied(ffa,10,id) and not Teams.enemies(ffa,10,id),"spectator became an ally or enemy")
end
for _,fake in ipairs({{}, {teamById={[10]=0,[20]=0}}, {teamById={[10]=1.5,[20]=1.5}},table.clone(ffa)}) do
 expect(Teams.team(fake,10)==nil and not Teams.allied(fake,10,20),"forged or cloned team map accepted")
 expect(not Teams.aliveTeams(fake,{10}),"forged map reached victory authority")
end
expect(table.isfrozen(ffa) and table.isfrozen(ffa.teamById) and table.isfrozen(ffa.teamMembers[1]),"team authority can be mutated")
expect(not pcall(function() ffa.teamById[10]=2 end),"assigned membership changed after match start")
expect(not pcall(function() ffa.teamMembers[1][1]=20 end),"assigned roster changed after match start")
expect(not pcall(function() Teams.Modes.Custom=true end),"caller can add an arbitrary team mode")

local pair=assigned("Teams",4,0)
expect(Teams.allied(pair,10,30) and Teams.allied(pair,20,40),"2v2 pairs are not formed")
expect(Teams.enemies(pair,10,20) and Teams.enemies(pair,30,40),"2v2 opponents are not enemies")
expect(pair.slotById[10]==1 and pair.slotById[30]==3 and pair.slotById[20]==2 and pair.slotById[40]==4,"2v2 allies must share adjacent spawn side")
local mixed=assigned("Teams",2,2)
expect(Teams.team(mixed,10)~=Teams.team(mixed,20),"two humans unfairly placed against two AI")
expect(#mixed.teamMembers[1]==2 and #mixed.teamMembers[2]==2,"mixed teams have unequal faction slots")
local mixedTeams={}
for _,id in ipairs(mixed.memberIds) do
 local team=Teams.team(mixed,id)
 mixedTeams[team]=mixedTeams[team] or {humans=0,ais=0}
 if mixed.aiById[id] then mixedTeams[team].ais+=1 else mixedTeams[team].humans+=1 end
end
expect(mixedTeams[1].humans==1 and mixedTeams[2].humans==1 and mixedTeams[1].ais==1 and mixedTeams[2].ais==1,"mixed human/AI allocation is unbalanced")

local coop=assigned("CoopAI",2,2)
expect(Teams.allied(coop,10,20) and Teams.allied(coop,-10001,-10002),"coop roles are split across teams")
expect(Teams.enemies(coop,10,-10001),"coop humans cannot target AI opponents")
expect(coop.slotById[10]==1 and coop.slotById[20]==3,"cooperating humans did not get adjacent spawn side")
local aiSlot1,aiSlot2=coop.slotById[-10001],coop.slotById[-10002]
expect((aiSlot1==2 and aiSlot2==4) or (aiSlot1==4 and aiSlot2==2),"cooperating AI did not get opposing side")
local negativeHuman=assert(Teams.assign("CoopAI",{{id=-1,ai=false},{id=99,ai=true}}))
expect(negativeHuman.aiById[-1]==false and Teams.team(negativeHuman,-1)==1 and Teams.team(negativeHuman,99)==2,"ID sign substituted for authoritative role")

local teams=assert(Teams.aliveTeams(pair,{40,30,20,10}))
expect(#teams==2 and teams[1]==1 and teams[2]==2 and table.isfrozen(teams),"alive team list is not canonical and immutable")
local winner,ended=Teams.winner(pair,{10,30})
expect(winner==1 and ended,"two surviving allied factions failed to win together")
winner,ended=Teams.winner(pair,{20,40})
expect(winner==2 and ended,"second surviving coalition failed to win together")
winner,ended=Teams.winner(pair,{30})
expect(winner==1 and ended,"surviving ally failed to win for its eliminated teammate")
winner,ended=Teams.winner(pair,{10,20})
expect(winner==nil and not ended,"victory declared with two opposing teams alive")
winner,ended=Teams.winner(pair,{})
expect(winner==nil and ended,"mutual elimination did not end in a draw")
winner,ended=Teams.winner(assigned("FFA",1,0),{10})
expect(winner==nil and not ended,"sandbox immediately auto-won")
winner,ended=Teams.winner(coop,{10,20})
expect(winner==1 and ended,"coop humans did not win when all AI were eliminated")
winner,ended=Teams.winner(coop,{-10001,-10002})
expect(winner==2 and ended,"coop AI did not win when all humans were eliminated")

for _,invalid in ipairs({false,"10",{999},{10,999},{10,10},{math.huge},{0/0},{1.5},{[2]=10},{10,extra=20},{10,20,30,40,50}}) do
 local alive,message=Teams.aliveTeams(pair,invalid)
 local found,finished,errorMessage=Teams.winner(pair,invalid)
 expect(alive==nil and type(message)=="string","invalid alive list became a team")
 expect(found==nil and not finished and type(errorMessage)=="string","invalid alive list ended match")
end
expect(not Teams.aliveTeams(pair,nil),"nil alive list became an empty draw")

for humans=1,4 do
 for ais=0,3 do
  for _,mode in ipairs({"FFA","Teams","CoopAI"}) do
   local total=humans+ais
   local permitted=total<=4 and (mode=="FFA" or mode=="Teams" and (total==2 or total==4) or mode=="CoopAI" and ais>0)
   local map=Teams.assign(mode,roster(humans,ais))
   expect((map~=nil)==permitted,"mode accepted invalid faction counts or rejected valid counts")
   if map then
    expect(map.humanCount==humans and map.aiCount==ais and #map.memberIds==total,"assignment changed authoritative roles")
    local slots,humanByTeam={},{}
    for _,id in ipairs(map.memberIds) do
     local slot=map.slotById[id]
     expect(type(slot)=="number" and slot>=1 and slot<=4 and slot%1==0 and not slots[slot],"factions share a spawn or exceed available slots")
     slots[slot]=true
     if not map.aiById[id] then humanByTeam[Teams.team(map,id)]=(humanByTeam[Teams.team(map,id)] or 0)+1 end
     for _,other in ipairs(map.memberIds) do
      expect(Teams.allied(map,id,other)==Teams.allied(map,other,id),"alliance is asymmetric")
      expect(Teams.enemies(map,id,other)==Teams.enemies(map,other,id),"enemy relation is asymmetric")
      expect(Teams.allied(map,id,other)~=Teams.enemies(map,id,other),"registered pair is both allied and enemy or neither")
      if mode=="CoopAI" then expect(Teams.allied(map,id,other)==(map.aiById[id]==map.aiById[other]),"coop role did not determine alliance") end
     end
    end
    if mode=="Teams" then
     expect(#map.teamMembers[1]==total/2 and #map.teamMembers[2]==total/2,"Teams faction count is unbalanced")
     expect(math.abs((humanByTeam[1] or 0)-(humanByTeam[2] or 0))<=1,"Teams human count is unbalanced")
    end
    local reversed=roster(humans,ais)
    for i=1,math.floor(#reversed/2) do reversed[i],reversed[#reversed-i+1]=reversed[#reversed-i+1],reversed[i] end
    local reordered=assert(Teams.assign(mode,reversed))
    for _,id in ipairs(map.memberIds) do expect(map.teamById[id]==reordered.teamById[id] and map.slotById[id]==reordered.slotById[id],"roster arrival order changed team or spawn fairness") end
    for mask=0,2^total-1 do
     local alive,expectedTeams={},{}
     for index,id in ipairs(map.memberIds) do
      if bit32.band(mask,bit32.lshift(1,index-1))~=0 then table.insert(alive,id); expectedTeams[map.teamById[id]]=true end
     end
     local expectedCount=0
     for _ in pairs(expectedTeams) do expectedCount+=1 end
     local actual=assert(Teams.aliveTeams(map,alive))
     expect(#actual==expectedCount,"survivor coalition count wrong")
     local winningTeam,finished,errorMessage=Teams.winner(map,alive)
     local shouldFinish=expectedCount==0 or expectedCount==1 and #map.teamIds>=2
     expect(finished==shouldFinish and errorMessage==nil,"survivor subset has wrong match outcome")
     expect(winningTeam==nil or expectedTeams[winningTeam]==true and expectedCount==1,"match winner was eliminated")
    end
    for key in pairs(map) do expect(key~="resources" and key~="bonus" and key~="damage" and key~="population","team authority introduced a gameplay advantage") end
   end
  end
 end
end

for _,mode in ipairs({"", "teams", "Custom", false, 0}) do rejected(mode,roster(2,0),"unknown mode accepted") end
for _,badId in ipairs({0,math.huge,-math.huge,0/0,1.5,9007199254740992,"1",false}) do
 rejected("FFA",{{id=badId,ai=false}},"invalid participant ID accepted")
end
for _,members in ipairs({{}, false, "players", {[2]={id=10,ai=false}}, {roster(1,0)[1],extra=true},{{id=10,ai=false},{id=10,ai=true}},{{id=10,ai="false"}},{{id=10,ai=false,spectator=true}},{{id=10,ai=false,teamId=2}},{{id=10,ai=false,resources={food=999}}},{{id=10,ai=false},{id=20,ai=false},{id=30,ai=false},{id=40,ai=false},{id=50,ai=false}}}) do
 rejected("FFA",members,"invalid, spectator, duplicate, or oversized roster accepted")
end
rejected("FFA",{{ai=false}},"missing participant ID accepted")
rejected("FFA",{{id=10}},"missing authoritative AI role accepted")
rejected("FFA",nil,"nil participant list accepted")
rejected(nil,roster(2,0),"missing team mode accepted")
rejected("FFA",setmetatable(roster(2,0),{}),"metatable roster accepted")
rejected("FFA",{setmetatable({id=10,ai=false},{})},"metatable participant accepted")
for _,invalidTeam in ipairs({0,-1,5,1.5,math.huge,0/0,"1",false}) do
 rejected("Teams",{{id=10,ai=false,teamId=invalidTeam},{id=20,ai=false}},"remote-provided invalid team accepted")
end
rejected("Teams",roster(3,0),"three-way unequal team match accepted")
rejected("CoopAI",roster(2,0),"coop without opponents accepted")
rejected("FFA",roster(0,2),"AI-only match accepted")
local original=roster(2,2)
local beforeFirst,beforeLast=original[1],original[4]
assert(Teams.assign("Teams",original))
expect(original[1]==beforeFirst and original[4]==beforeLast and beforeFirst.teamId==nil,"allocation mutated caller state")

local current={mode="FFA",humanCount=2,aiCount=2}
local nextSettings,message,reset=Teams.changeSettings(current,{mode="Teams",humanCount=2,aiCount=2},10,10,"Lobby")
expect(nextSettings and nextSettings.mode=="Teams" and reset and message==nil,"host mode change did not cancel preparation")
nextSettings,message,reset=Teams.changeSettings(current,table.clone(current),10,10,"Lobby")
expect(nextSettings and not reset and message==nil,"unchanged team settings cancel preparation")
nextSettings,message,reset=Teams.changeSettings(current,{mode="FFA",humanCount=3,aiCount=1},10,10,"Lobby")
expect(nextSettings and reset,"roster role/count change left preparations valid")
nextSettings,message,reset=Teams.changeSettings(current,{mode="FFA",humanCount=2,aiCount=1},10,10,"Lobby")
expect(nextSettings and reset,"AI slot change left preparations valid")
for _,phase in ipairs({"Starting","Playing","Ended","Invalid"}) do
 nextSettings,message,reset=Teams.changeSettings(current,{mode="Teams",humanCount=2,aiCount=2},10,10,phase)
 expect(nextSettings==nil and type(message)=="string" and not reset,"team configuration changed outside lobby")
end
for _,requester in ipairs({20,0,math.huge,"10",false}) do
 nextSettings,message,reset=Teams.changeSettings(current,{mode="Teams",humanCount=2,aiCount=2},requester,10,"Lobby")
 expect(nextSettings==nil and type(message)=="string" and not reset,"nonhost changed team configuration")
end
for _,requested in ipairs({false,{}, {mode="Teams",humanCount=3,aiCount=0}, {mode="CoopAI",humanCount=1,aiCount=0}, {mode="FFA",humanCount=2.5,aiCount=0}, {mode="FFA",humanCount=1,aiCount=math.huge}, {mode="FFA",humanCount=2,aiCount=0,teamById={[10]=1}}, {mode="FFA",humanCount=2,aiCount=0,damageMultiplier=2}}) do
 nextSettings,message,reset=Teams.changeSettings(current,requested,10,10,"Lobby")
 expect(nextSettings==nil and type(message)=="string" and not reset,"invalid or manual team settings accepted")
end
expect(current.mode=="FFA" and current.humanCount==2 and current.aiCount==2,"settings validation mutated current configuration")
expect(not Teams.changeSettings({},current,10,10,"Lobby"),"invalid current settings bypassed readiness detection")
expect(not Teams.changeSettings(current,nil,10,10,"Lobby"),"missing requested settings accepted")
expect(not Teams.changeSettings(current,current,nil,10,"Lobby"),"missing requester acquired host authority")
expect(not Teams.changeSettings(current,current,10,nil,"Lobby"),"missing host granted team change authority")
expect(not Teams.changeSettings(current,current,10,10,nil),"missing phase allowed team change")
expect(not Teams.changeSettings(current,setmetatable(table.clone(current),{}),10,10,"Lobby"),"metatable settings accepted")
for _,id in ipairs(pair.memberIds) do
 expect(Teams.result(pair,id,nil,false,false)=="pending","natural elimination settled a team result before match end")
 expect(Teams.result(pair,id,nil,false,true)=="loss","forfeit did not immediately lose")
 expect(Teams.result(pair,id,nil,true,false)=="draw","draw turned into a fabricated win or loss")
 for _,winningTeam in ipairs(pair.teamIds) do
  expect(Teams.result(pair,id,winningTeam,true,false)==(pair.teamById[id]==winningTeam and "win" or "loss"),"final outcome did not follow authoritative team")
  expect(Teams.result(pair,id,winningTeam,true,true)=="loss","forfeit was overwritten by allied victory")
 end
end
for _,badTeam in ipairs({0,-1,3,5,1.5,math.huge,0/0,"1",false}) do
 local outcome,errorMessage=Teams.result(pair,10,badTeam,true,false)
 expect(outcome==nil and type(errorMessage)=="string","invalid winner team produced a result")
end
expect(not Teams.result(pair,10,1,false,false),"unsettled match had a winning team")
expect(not Teams.result(pair,10,1,false,true),"forfeit accepted an invalid unsettled winner")
expect(not Teams.result(pair,999,1,true,false),"spectator received an allied victory")
expect(not Teams.result({},10,1,true,false),"forged map settled a result")
expect(not Teams.result(pair,10,nil,nil,false),"missing ended flag settled result")
expect(not Teams.result(pair,10,nil,true,nil),"missing forfeit flag settled result")
local participant={id=10,forfeited=true}
local reconnect={id=10,forfeited=false}
local registry={[10]=participant}
expect(Teams.isParticipant(pair,registry,participant),"original authoritative state lost participation")
expect(not Teams.isParticipant(pair,registry,reconnect),"rejoining observer inherited old participant authority")
expect(not Teams.isParticipant(pair,registry,{id=999}),"unknown observer inherited participant authority")
expect(not Teams.isParticipant({},registry,participant),"forged map registered a participant")
expect(not Teams.isParticipant(pair,nil,participant),"missing registry registered a participant")
expect(not Teams.isParticipant(pair,registry,nil),"missing state registered a participant")
print(string.format("PASS: %d server team assignment / alliance / victory / readiness checks",count))
