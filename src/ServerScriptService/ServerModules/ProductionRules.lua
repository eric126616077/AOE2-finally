-- Shared production state transitions; engine lifetime detection and player feedback stay in the server.
local Rules={}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function integer(value)
 return finite(value) and value>=0 and value%1==0
end
-- The visible queue revision makes a click refer to the exact queue the client saw.
-- Completion can occur while the click is travelling; never cancel its successor.
function Rules.cancelTraining(queue,index,expectedRevision,currentRevision)
 if type(queue)~="table" or #queue==0 or #queue>5 or not integer(index) or index<1 or index>#queue
  or not integer(expectedRevision) or not integer(currentRevision) or expectedRevision~=currentRevision then return nil end
 local item=queue[index]
 if type(item)~="table" or type(item.kind)~="string" or type(item.cost)~="table" then return nil end
 return table.remove(queue,index),currentRevision+1
end
function Rules.canRallyBuilding(data,owned,complete)
 return owned==true and complete==true and type(data)=="table" and type(data.trains)=="table" and #data.trains>0
end
function Rules.canRallyResource(kind,amount,ownerId,actorId,complete)
 return ({food=true,wood=true,gold=true,stone=true})[kind]==true and finite(amount) and amount>0
  and complete==true and (ownerId==nil or ownerId==actorId)
end
function Rules.canResearch(technologies,pendingTech,key,age,minAge)
 return type(technologies)=="table" and type(pendingTech)=="table" and type(key)=="string"
  and not technologies[key] and not pendingTech[key] and finite(age) and finite(minAge) and age>=minAge
end
function Rules.cancelResearch(state,source,researching)
 local research=researching[source]
 if research then state.pendingTech[research.key]=nil; researching[source]=nil end
 if state.advancing and state.advancing.building==source then
  state.advancing=nil
  return true
 end
 return false
end
-- 兵種升級（科技 upgrade 欄位）：把加值累加到該兵種自己的修正表，並記錄新名稱。
-- hp／attack／armor／range 為加值，speed／interval 為比例；bonus 為對各類別的額外傷害。
-- 未知兵種或無效數值不改變任何狀態；回傳升級後的名稱。
local upgradeStats={"hp","attack","armor","range","speed","interval"}
function Rules.applyUpgrade(unitModifiers,unitNames,upgrade,units)
 if type(unitModifiers)~="table" or type(unitNames)~="table" or type(upgrade)~="table" then return nil end
 local kind=upgrade.unit
 if type(kind)~="string" or type(units)~="table" or units[kind]==nil then return nil end
 for _,stat in ipairs(upgradeStats) do
  if upgrade[stat]~=nil and not finite(upgrade[stat]) then return nil end
 end
 for class,amount in pairs(upgrade.bonus or {}) do
  if type(class)~="string" or not finite(amount) then return nil end
 end
 local own=unitModifiers[kind] or {bonus={}}
 unitModifiers[kind]=own
 for _,stat in ipairs(upgradeStats) do
  if upgrade[stat]~=nil then own[stat]=(own[stat] or 0)+upgrade[stat] end
 end
 for class,amount in pairs(upgrade.bonus or {}) do own.bonus[class]=(own.bonus[class] or 0)+amount end
 if type(upgrade.name)=="string" and upgrade.name~="" then unitNames[kind]=upgrade.name end
 return unitNames[kind]
end
return Rules
