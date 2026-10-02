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
return Rules
