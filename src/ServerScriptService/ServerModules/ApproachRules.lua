-- Pure selection over the actual perimeter candidates; collision/path checks stay on the server.
local ApproachRules = {}
local workOrders={build=true,gather=true,deliver=true,repair=true,garrison=true,relic=true,relicStore=true,trade=true}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function ApproachRules.isWork(kind)
 return type(kind)=="string" and workOrders[kind]==true
end
function ApproachRules.nearest(candidates,currentX,currentZ,blacklist,isUsable)
 if type(candidates)~="table" or not finite(currentX) or not finite(currentZ)
  or (blacklist~=nil and type(blacklist)~="table") or type(isUsable)~="function" then return nil end
 local best,bestDistance,seen=nil,math.huge,{}
 for _,point in ipairs(candidates) do
  if type(point)~="table" or not finite(point.X) or not finite(point.Z)
   or not finite(point.index) or point.index%1~=0 or point.index<1 or point.index>16 or seen[point.index] then return nil end
  seen[point.index]=true
  if not (blacklist and blacklist[point.index]) and isUsable(point)==true then
   local dx,dz=point.X-currentX,point.Z-currentZ
   local distance=dx*dx+dz*dz
   if finite(distance) and (distance<bestDistance or distance==bestDistance and point.index<best.index) then
    best,bestDistance=point,distance
   end
  end
 end
 return best
end
return ApproachRules
