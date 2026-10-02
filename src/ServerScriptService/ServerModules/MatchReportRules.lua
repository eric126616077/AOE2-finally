-- Session-only review of successful server facts. This module owns no game state,
-- grants no resources/power, and must never be called with a client-authored report.
local Rules={}
local MAX=9007199254740991
local tag={}
local resourceKeys={"food","wood","gold","stone"}
local resources={food=true,wood=true,gold=true,stone=true}
local outcomes={pending="等待對局結果",win="勝利",loss="戰敗",draw="無勝者"}
local labels={resourcesDelivered="資源交貨量",resourcesSpent="資源淨支出",buildingsCompleted="完工建築",
 villagersTrained="訓練村民",militaryTrained="訓練軍隊",damageDealt="造成傷害",unitsKilled="單位擊殺",
 buildingsKilled="建築摧毀",unitsLost="戰鬥單位損失",buildingsLost="戰鬥建築損失",survivalSeconds="存活時長",
 outcome="對局結果",food="食物",wood="木材",gold="黃金",stone="石材"}
local counters={"buildingsCompleted","villagersTrained","militaryTrained","damageDealt","unitsKilled","buildingsKilled","unitsLost","buildingsLost"}
local fields={
 delivery={resource=true,amount=true},spend={cost=true,refundable=true},refund={spendId=true},building={subjectId=true},
 train={subjectId=true,role=true,spendId=true},damage={beforeHP=true,afterHP=true},kill={subjectId=true,category=true},loss={subjectId=true,category=true},
}
local function amount(value)
 return type(value)=="number" and value==value and value>=0 and value<=MAX
end
local function integer(value)
 return amount(value) and value%1==0
end
local function token(value)
 return type(value)=="string" and #value>0 and #value<=100 and value:match("^[%w_:%-]+$")~=nil
end
local function subject(value)
 return token(value) or (integer(value) and value>0)
end
local function resourceTable()
 return {food=0,wood=0,gold=0,stone=0}
end
local function copy(source)
 local result={}
 for key,value in pairs(source) do result[key]=value end
 return result
end
local function cost(value)
 if type(value)~="table" then return nil end
 local result=resourceTable()
 local positive=false
 for key,valueAmount in pairs(value) do
  if not resources[key] or not amount(valueAmount) then return nil end
  result[key]=valueAmount
  positive=positive or valueAmount>0
 end
 return positive and result or nil
end
local function valid(report)
 return type(report)=="table" and report._tag==tag
end
local function add(current,value)
 local nextValue=current+value
 return amount(nextValue) and nextValue or nil
end

function Rules.New(matchId,startedAt)
 if not token(matchId) or not amount(startedAt) then return nil end
 local report={_tag=tag,_active=true,_finished=false,_lastSequence=0,_startedAt=startedAt,_spends={},
  _buildings={},_trained={},_kills={},_losses={},matchId=matchId,outcome="pending",
  resourcesDelivered=resourceTable(),resourcesSpent=resourceTable()}
 for _,key in ipairs(counters) do report[key]=0 end
 return report
end

-- sequence is a strictly increasing positive integer assigned by the server.
-- Its high-water mark rejects duplicate/old facts without retaining every hit.
-- subjectId is a stable server ID for the particular model, not an order ID.
-- Invalid facts do not consume the sequence or mutate any counters.
function Rules.Record(report,sequence,kind,facts)
 if not valid(report) or not report._active or not integer(sequence) or sequence<=report._lastSequence
  or not fields[kind] or type(facts)~="table" then return false end
 for key in pairs(facts) do if not fields[kind][key] then return false end end
 if kind=="delivery" then
  if not resources[facts.resource] or not amount(facts.amount) or facts.amount<=0 then return false end
  local nextValue=add(report.resourcesDelivered[facts.resource],facts.amount)
  if not nextValue then return false end
  report.resourcesDelivered[facts.resource]=nextValue
 elseif kind=="spend" then
  if facts.refundable~=nil and type(facts.refundable)~="boolean" then return false end
  local paid=cost(facts.cost)
  if not paid then return false end
  local nextValues={}
  for _,key in ipairs(resourceKeys) do
   nextValues[key]=add(report.resourcesSpent[key],paid[key])
   if not nextValues[key] then return false end
  end
  report.resourcesSpent=nextValues
  if facts.refundable then report._spends[sequence]=paid end
 elseif kind=="refund" then
  if not integer(facts.spendId) or facts.spendId<=0 then return false end
  local paid=report._spends[facts.spendId]
  if not paid then return false end
  local nextValues={}
  for _,key in ipairs(resourceKeys) do
   nextValues[key]=report.resourcesSpent[key]-paid[key]
   if not amount(nextValues[key]) then return false end
  end
  report.resourcesSpent=nextValues
  report._spends[facts.spendId]=nil
 elseif kind=="building" then
  if not subject(facts.subjectId) or report._buildings[facts.subjectId] then return false end
  local nextValue=add(report.buildingsCompleted,1)
  if not nextValue then return false end
  report.buildingsCompleted=nextValue
  report._buildings[facts.subjectId]=true
 elseif kind=="train" then
  if not subject(facts.subjectId) or report._trained[facts.subjectId] or (facts.role~="villager" and facts.role~="military") then return false end
  if facts.spendId~=nil and (not integer(facts.spendId) or not report._spends[facts.spendId]) then return false end
  local key=facts.role=="villager" and "villagersTrained" or "militaryTrained"
  local nextValue=add(report[key],1)
  if not nextValue then return false end
  report[key]=nextValue
  report._trained[facts.subjectId]=true
  if facts.spendId then report._spends[facts.spendId]=nil end
 elseif kind=="damage" then
  if not amount(facts.beforeHP) or not amount(facts.afterHP) or facts.beforeHP<=facts.afterHP then return false end
  local nextValue=add(report.damageDealt,facts.beforeHP-facts.afterHP)
  if not nextValue then return false end
  report.damageDealt=nextValue
 elseif kind=="kill" or kind=="loss" then
  if not subject(facts.subjectId) or (facts.category~="unit" and facts.category~="building") then return false end
  local seen=kind=="kill" and report._kills or report._losses
  if seen[facts.subjectId] then return false end
  local key=(facts.category=="unit" and "units" or "buildings")..(kind=="kill" and "Killed" or "Lost")
  local nextValue=add(report[key],1)
  if not nextValue then return false end
  report[key]=nextValue
  seen[facts.subjectId]=true
 end
 report._lastSequence=sequence
 return true
end

-- Freeze personal activity at natural elimination. Team outcome is still pending.
function Rules.FreezeActivity(report,stoppedAt)
 if not valid(report) or not report._active or report._finished or not amount(stoppedAt) or stoppedAt<report._startedAt then return false end
 report._active=false
 report._activityEndedAt=stoppedAt
 report._spends,report._buildings,report._trained,report._kills,report._losses={},{},{},{},{}
 return true
end

-- Final outcome is settled once. A frozen teammate can win later without gaining spectator activity.
function Rules.Finish(report,endedAt,outcome)
 if not valid(report) or report._finished or not amount(endedAt) or endedAt<report._startedAt
  or (report._activityEndedAt and endedAt<report._activityEndedAt)
  or (outcome~="win" and outcome~="loss" and outcome~="draw") then return false end
 if report._active and not Rules.FreezeActivity(report,endedAt) then return false end
 report._finished=true
 report._endedAt=endedAt
 report.outcome=outcome
 return true
end

-- Only this fresh, bounded-field scalar/table copy may be replicated to a player.
-- It contains no Instances, event IDs, dedup maps, live balances, or persistent data.
function Rules.Snapshot(report,now)
 if not valid(report) then return nil end
 local untilTime=report._activityEndedAt or now
 if not amount(untilTime) or untilTime<report._startedAt then return nil end
 local result={version=1,matchId=report.matchId,finished=report._finished==true,outcome=report.outcome,outcomeLabel=outcomes[report.outcome],
  survivalSeconds=untilTime-report._startedAt,resourcesDelivered=copy(report.resourcesDelivered),resourcesSpent=copy(report.resourcesSpent),labels=copy(labels)}
 for _,key in ipairs(counters) do result[key]=report[key] end
 return result
end
return Rules
