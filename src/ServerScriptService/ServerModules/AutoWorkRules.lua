-- Engine-independent choices for villagers that work without micromanagement.
local Rules = {}
local resources = {food=true, wood=true, gold=true, stone=true}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

-- Small sites need one worker; larger footprints recruit a few more.
function Rules.builderCount(sizeX, sizeY, maximum)
 if not finite(sizeX) or not finite(sizeY) or sizeX<=0 or sizeY<=0 then return 0 end
 local cells=sizeX*sizeY
 local count=cells<=4 and 1 or cells<=9 and 2 or 3
 if finite(maximum) and maximum>=0 then count=math.min(count,math.floor(maximum)) end
 return count
end

-- candidates: {unit, distance, idle, building}. Workers already building are never
-- pulled away; busy gatherers are used only when idle villagers are much farther.
function Rules.pickBuilders(candidates, count, busyPenalty)
 if type(candidates)~="table" or not finite(count) or count<1 then return {} end
 busyPenalty=finite(busyPenalty) and busyPenalty>=0 and busyPenalty or 0
 local scored={}
 for index,candidate in ipairs(candidates) do
  if type(candidate)=="table" and candidate.unit~=nil and not candidate.building and finite(candidate.distance) and candidate.distance>=0 then
   table.insert(scored,{unit=candidate.unit,score=candidate.distance+(candidate.idle and 0 or busyPenalty),index=index})
  end
 end
 table.sort(scored,function(a,b) return a.score==b.score and a.index<b.index or a.score<b.score end)
 local result={}
 for index=1,math.min(math.floor(count),#scored) do result[index]=scored[index].unit end
 return result
end

function Rules.idleReady(idleSince, now, delay, nextCheck, hold)
 if hold or not finite(idleSince) or not finite(now) or not finite(delay) then return false end
 if finite(nextCheck) and now<nextCheck then return false end
 return now-idleSince>=delay
end

-- Economic buildings steer their builders to the resources they collect.
-- Buildings accepting every resource (town center, market, castle) have no preference.
function Rules.dropoffPreference(dropoff)
 if type(dropoff)~="table" then return nil end
 local list,all={},true
 for key in pairs(resources) do if not table.find(dropoff,key) then all=false end end
 if all then return nil end
 for _,key in ipairs(dropoff) do if resources[key] then table.insert(list,key) end end
 return #list>0 and list or nil
end

-- context: {site, carrying, dropoff, nearby={key=target}, priorities={keys}}.
-- Returns action, target, resource key. Nearby construction comes first.
function Rules.choose(context)
 if type(context)~="table" then return nil end
 if context.site~=nil then return "build",context.site end
 if finite(context.carrying) and context.carrying>0 then
  if context.dropoff~=nil then return "deliver",context.dropoff end
  return nil -- Without a drop-off a full villager would only retry and fail.
 end
 local nearby=type(context.nearby)=="table" and context.nearby or {}
 for _,key in ipairs(type(context.priorities)=="table" and context.priorities or {}) do
  if resources[key] and nearby[key]~=nil then return "gather",nearby[key],key end
 end
 return nil
end

return Rules
