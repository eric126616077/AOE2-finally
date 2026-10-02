-- Bounded navigation retries and actual movement-segment acceptance.
-- Engine path computation/collision remain server callbacks, not pure-test claims.
local Rules={MAX_ENGINE_CALLS=7,MAX_ESCAPE_ORIGINS=2,ESCAPE_STEP=8,MAX_PARTIAL_ATTEMPTS=32}
local MAX=9007199254740991
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Rules.candidateRadii(radius)
 if not finite(radius) or radius<=0 then return nil end
 local result,seen={},{}
 for _,value in ipairs({radius,radius*math.sqrt(2),radius*2}) do
  if not finite(value) or value>MAX then return nil end
  local rounded=math.ceil(value)
  if not seen[rounded] then table.insert(result,rounded); seen[rounded]=true end
 end
 return result
end
function Rules.escapeRadii(radius)
 if not Rules.candidateRadii(radius) then return nil end
 local result,seen={},{}
 for _,value in ipairs({radius*math.sqrt(2),radius*2}) do
  local rounded=math.ceil(value)
  if not seen[rounded] then table.insert(result,rounded); seen[rounded]=true end
 end
 return result
end
function Rules.nextComputeCall(calls)
 if not finite(calls) or calls%1~=0 or calls<0 or calls>=Rules.MAX_ENGINE_CALLS then return nil end
 return calls+1
end
-- Eight local origins, ordered toward the blocked waypoint (or goal).
-- Actual endpoint overlap, bounds and prefix collision stay in server callbacks.
function Rules.escapeCandidates(x,z,towardX,towardZ)
 if not finite(x) or not finite(z) or not finite(towardX) or not finite(towardZ) then return nil end
 local candidates={}
 for index,offset in ipairs({{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}) do
  local px,pz=x+offset[1]*Rules.ESCAPE_STEP,z+offset[2]*Rules.ESCAPE_STEP
  local distance=(px-towardX)^2+(pz-towardZ)^2
  if not finite(px) or not finite(pz) or not finite(distance) then return nil end
  table.insert(candidates,{X=px,Z=pz,index=index,distance=distance})
 end
 table.sort(candidates,function(a,b) return a.distance==b.distance and a.index<b.index or a.distance<b.distance end)
 return candidates
end
function Rules.selectEscapes(candidates,isUsable)
 if type(candidates)~="table" or type(isUsable)~="function" then return nil end
 local selected,seen={},{}
 for _,candidate in ipairs(candidates) do
  if type(candidate)~="table" or not finite(candidate.X) or not finite(candidate.Z) then return nil end
  local key=tostring(candidate.X)..":"..tostring(candidate.Z)
  if not seen[key] then
   seen[key]=true
   local ok,usable=pcall(isUsable,candidate)
   if ok and usable==true then
    table.insert(selected,candidate)
    if #selected==Rules.MAX_ESCAPE_ORIGINS then break end
   end
  end
 end
 return selected
end
function Rules.prepend(waypoints,prefix)
 if type(waypoints)~="table" or #waypoints<2 or prefix==nil or prefix==false then return nil end
 local path={{Position=prefix}}
 for _,waypoint in ipairs(waypoints) do table.insert(path,waypoint) end
 return path
end
-- Every waypoint, including the computed origin, must be safe from the live unit.
-- An escape prefix is prepended and executed by the same normal movement loop.
function Rules.inspectPath(waypoints,liveStart,project,segmentClear)
 if type(waypoints)~="table" or #waypoints<2 or liveStart==nil or liveStart==false
  or type(project)~="function" or type(segmentClear)~="function" then return nil end
 local previous,prefix=liveStart,{}
 for index=1,#waypoints do
  local ok,nextPosition=pcall(project,waypoints[index])
  if not ok or nextPosition==nil or nextPosition==false then return nil,index end
  local clearOK,clear=pcall(segmentClear,previous,nextPosition)
  if not clearOK or type(clear)~="boolean" then return nil,index end
  if not clear then return {full=false,path=prefix,endpoint=previous,blockedIndex=index},index end
  table.insert(prefix,waypoints[index])
  previous=nextPosition
 end
 return {full=true,path=prefix,endpoint=previous}
end
function Rules.clearPath(waypoints,liveStart,project,segmentClear)
 local inspected,index=Rules.inspectPath(waypoints,liveStart,project,segmentClear)
 return inspected~=nil and inspected.full==true,index
end
function Rules.nextPartialAttempt(attempts)
 if not finite(attempts) or attempts%1~=0 or attempts<0 or attempts>=Rules.MAX_PARTIAL_ATTEMPTS then return nil end
 return attempts+1
end
function Rules.goalChanged(oldX,oldZ,newX,newZ)
 if not finite(oldX) or not finite(oldZ) or not finite(newX) or not finite(newZ) then return nil end
 local square=(oldX-newX)^2+(oldZ-newZ)^2
 return not finite(square) or square>=64
end
-- Prefixes are collision-verified by the caller; only forward, new endpoints
-- may continue a static goal. Budget counts all route attempts after activation.
function Rules.prefixProgress(startX,startZ,endX,endZ,goalX,goalZ,history)
 if not finite(startX) or not finite(startZ) or not finite(endX) or not finite(endZ) or not finite(goalX) or not finite(goalZ) then return nil end
 if type(history)~="table" or #history>Rules.MAX_PARTIAL_ATTEMPTS then return nil end
 local displacement=(endX-startX)^2+(endZ-startZ)^2
 local before,after=(goalX-startX)^2+(goalZ-startZ)^2,(goalX-endX)^2+(goalZ-endZ)^2
 if not finite(displacement) or not finite(before) or not finite(after) or displacement<64 then return nil end
 local reduction=math.sqrt(before)-math.sqrt(after)
 if reduction<4 then return nil end
 for _,point in ipairs(history) do
  if type(point)~="table" or not finite(point.X) or not finite(point.Z) then return nil end
  if (point.X-endX)^2+(point.Z-endZ)^2<16 then return nil end
 end
 return reduction
end
function Rules.bestPrefix(candidates,startX,startZ,goalX,goalZ,history)
 if type(candidates)~="table" or #candidates>Rules.MAX_ENGINE_CALLS then return nil end
 local best,bestReduction=nil,-math.huge
 for _,candidate in ipairs(candidates) do
  if type(candidate)=="table" and type(candidate.path)=="table" and #candidate.path>=2 and candidate.endpoint~=nil then
   local endpoint=candidate.endpoint
   local ok,reduction=pcall(function() return Rules.prefixProgress(startX,startZ,endpoint.X,endpoint.Z,goalX,goalZ,history) end)
   if ok and reduction and reduction>bestReduction then best,bestReduction=candidate,reduction end
  end
 end
 return best
end
function Rules.waypointReached(distance)
 return finite(distance) and distance>=0 and distance<=0.05
end
return Rules
