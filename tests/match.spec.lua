local matchChecks=0
local function expect(condition,message)
 matchChecks+=1
 assert(condition,message)
end
local settings={size="Large",aiCount=3,difficulty="Hard",population=200,startingResources="Rich",victory="Conquest"}
local result=MatchRules.settings(settings,1)
expect(result and result.size=="Large" and result.aiCount==3,"valid full match settings rejected")
expect(settings.size=="Large", "validation mutated input")
for _,invalid in ipairs({false,42,"Large"}) do
 expect(not MatchRules.settings(invalid,1),"non-table lobby request accepted")
end
for key, values in pairs({size={"huge",42},aiCount={-1,4,1.5,math.huge,0/0},difficulty={"Cheat",true},population={0,61,math.huge},startingResources={"Free"},victory={"Unknown"}}) do
 for _,value in ipairs(values) do
  local request=table.clone(settings)
  request[key]=value
  expect(not MatchRules.settings(request,1),"invalid setting accepted: "..key)
 end
end
expect(not MatchRules.settings(settings,2),"more than four factions accepted")
expect(result.teamMode=="FFA","existing settings lost FFA compatibility")
local teamsSettings=table.clone(settings); teamsSettings.aiCount=2; teamsSettings.teamMode="Teams"
expect(MatchRules.settings(teamsSettings,2).teamMode=="Teams","valid mixed 2v2 settings rejected")
teamsSettings.aiCount=0
expect(MatchRules.settings(teamsSettings,2).teamMode=="Teams","valid 1v1 settings rejected")
expect(MatchRules.settings(teamsSettings,4).teamMode=="Teams","valid human 2v2 settings rejected")
expect(not MatchRules.settings(teamsSettings,3),"unequal three-faction team settings accepted")
teamsSettings.teamMode="CoopAI"
expect(not MatchRules.settings(teamsSettings,2),"coop without AI opponents accepted")
teamsSettings.aiCount=2
expect(MatchRules.settings(teamsSettings,2).teamMode=="CoopAI","cooperating humans and AI settings rejected")
expect(not MatchRules.settings(teamsSettings,1.5),"fractional human count accepted")
for _,mode in ipairs({"", "teams", "Unknown",true,1,math.huge}) do
 local invalid=table.clone(settings); invalid.teamMode=mode
 expect(not MatchRules.settings(invalid,1),"unknown team mode accepted")
end
for key,value in pairs({teamId=1,teamById={[1]=1},roster={{id=1,ai=false}},resources={food=999},damageMultiplier=2}) do
 local invalid=table.clone(settings); invalid[key]=value
 expect(not MatchRules.settings(invalid,1),"manual team or gameplay setting accepted")
end
local sandbox=table.clone(settings)
sandbox.aiCount=0
expect(MatchRules.settings(sandbox,1)~=nil,"solo sandbox rejected")
expect(MatchRules.finite(1) and not MatchRules.finite(math.huge) and not MatchRules.finite(0/0),"finite number validation wrong")
local balance={food=49,wood=100,gold=0,stone=0}
expect(not MatchRules.canSpend(balance,{food=50,wood=25}),"insufficient mixed cost accepted")
expect(MatchRules.canSpend(balance,{food=49,wood=100}),"exact cost rejected")
expect(balance.food==49 and balance.wood==100,"affordability test mutated balance")
local faction={id=1}
local winner,ended=MatchRules.winner({faction})
expect(winner==faction and ended,"last surviving faction not victorious")
winner,ended=MatchRules.winner({faction,{id=2}})
expect(not winner and not ended,"multiple surviving factions ended match")
winner,ended=MatchRules.winner({})
expect(not winner and ended,"no survivors should produce a draw")
winner,ended=MatchRules.winner({faction},1)
expect(not winner and not ended,"single-side sandbox should keep playing with its survivor")
winner,ended=MatchRules.winner({},1)
expect(not winner and ended,"empty sandbox should end when its participant leaves")
winner,ended=MatchRules.winner({faction},2)
expect(winner==faction and ended,"two-side match should end with its last survivor")
winner,ended=MatchRules.winner({faction},4)
expect(winner==faction and ended,"four-side match should end with its last survivor")
winner,ended=MatchRules.winner({faction,{id=2}},4)
expect(not winner and not ended,"four-side match with multiple survivors should keep playing")
winner,ended=MatchRules.winner({},4)
expect(not winner and ended,"match with no survivors should end without a winner")
for _,invalid in ipairs({math.huge,-math.huge,0/0,false,"1"}) do
 winner,ended=MatchRules.winner({faction},invalid)
 expect(not winner and not ended,"invalid starting-side count should not resolve victory")
end
winner,ended=MatchRules.winner(false,2)
expect(not winner and not ended,"invalid survivor list should not resolve victory")
-- Data integrity matters because cost and counter values are accepted only from this config.
for kind,data in pairs(Config.Buildings) do
 expect(data.name~=nil and data.hp>0 and data.size.X>0 and data.size.Y>0,"invalid building definition "..kind)
 for _,cost in pairs(data.cost) do expect(MatchRules.finite(cost) and cost>=0,"invalid configured building cost") end
 for _,unit in ipairs(data.trains or {}) do expect(Config.Units[unit]~=nil,"unknown trained unit "..unit) end
end
for kind,data in pairs(Config.Units) do
 expect(data.hp>0 and data.speed>0 and data.trainTime>0,"invalid unit definition "..kind)
 for class,bonus in pairs(data.bonus or {}) do expect(type(class)=="string" and MatchRules.finite(bonus) and bonus>=0,"invalid unit counter") end
end
expect(Config.Ages[2].cost.food==500,"feudal age cost differs from rule")
expect(Config.Ages[3].cost.food==800 and Config.Ages[3].cost.gold==200,"castle age cost differs from rule")
expect(Config.Ages[4].cost.food==1000 and Config.Ages[4].cost.gold==800,"imperial age cost differs from rule")
-- Load the exact engine-independent module that GameServer uses, from this generated build bundle.
local UnitRules=require("../src/ServerScriptService/ServerModules/UnitRules")
local clocks={}
local unitA,unitB={},{}
expect(UnitRules.takeAction(clocks,unitA,"attack",10,1.5),"first attack should be allowed")
for tick=1,14 do
 expect(not UnitRules.takeAction(clocks,unitA,"attack",10+tick/10,1.5),"repeat orders or target changes bypassed attack cooldown")
end
expect(UnitRules.takeAction(clocks,unitA,"gather",10.1,1),"attack clock incorrectly delayed gathering")
expect(not UnitRules.takeAction(clocks,unitA,"gather",10.9,1),"gather orders bypassed extraction interval")
expect(UnitRules.takeAction(clocks,unitB,"attack",10.1,1.5),"one unit's cooldown blocked another unit")
expect(not UnitRules.takeAction(clocks,unitA,"attack",9,1.5),"clock rollback reset cooldown")
expect(UnitRules.takeAction(clocks,unitA,"attack",11.5,1.5),"attack did not resume at exact interval")
expect(UnitRules.takeAction(clocks,unitA,"gather",11.1,1),"gather did not resume at exact interval")
-- 連續攻擊以間隔累進：伺服器步長 0.1167 秒時，1.4 秒間隔的十次攻擊不得被量化拖慢。
do
 local carried,unitC,attacks,first,last={}, {},0,nil,nil
 for step=0,200 do
  local now=100+step*0.1167
  if UnitRules.takeAction(carried,unitC,"attack",now,1.4,0.3) then attacks+=1; first=first or now; last=now end
  if attacks==11 then break end
 end
 expect(attacks==11 and (last-first)/10<1.4+0.1167/10+1e-6,"carried attack interval drifts with the server step")
 expect(carried[unitC].attack<=last and last-carried[unitC].attack<0.1167+1e-6,"carried clock ran ahead of real time")
 -- 中斷超過容許值後重新對齊，不能補打累積的攻擊。
 expect(UnitRules.takeAction(carried,unitC,"attack",last+10,1.4,0.3) and carried[unitC].attack==last+10,"long pause did not realign the attack clock")
 expect(not UnitRules.takeAction(carried,unitC,"attack",last+10.1,1.4,0.3),"realigned clock allowed a burst attack")
end
expect(UnitRules.takeAction(clocks,unitA,"repair",11.1,1),"gather clock incorrectly delayed repair")
expect(not UnitRules.takeAction(clocks,unitA,"attack",math.huge,1.5),"non-finite attack time accepted")
expect(not UnitRules.takeAction(clocks,unitA,"attack",12,0/0),"non-finite interval accepted")
expect(not UnitRules.takeAction(clocks,unitA,"unknown",12,1),"unknown action consumed a cooldown")
clocks[unitA]=nil
expect(UnitRules.takeAction(clocks,unitA,"attack",12,1.5),"destroyed unit's released clock was retained")
clocks={}
expect(UnitRules.takeAction(clocks,unitB,"attack",0,1.5),"fresh match retained a prior match clock")
expect(UnitRules.canCompletePopulation(4,5),"available population incorrectly blocks completion")
expect(not UnitRules.canCompletePopulation(5,5),"full population permits queued completion")
expect(not UnitRules.canCompletePopulation(7,5),"lost housing permits queued completion")
expect(UnitRules.canCompletePopulation(7,10),"restored housing does not resume queued completion")
expect(not UnitRules.canCompletePopulation(0,0),"no housing permits queued completion")
expect(not UnitRules.canCompletePopulation(math.huge,100),"non-finite population accepted")
expect(not UnitRules.canCompletePopulation(0,0/0),"non-finite capacity accepted")
expect(not UnitRules.canCompletePopulation(-1,5),"negative population accepted")
expect(not UnitRules.canCompletePopulation(4.5,5),"fractional population accepted")
print(string.format("PASS: %d match settings / economy / data-integrity checks",matchChecks))
