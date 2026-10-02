-- Engine-independent authority rules for selected villagers and actual construction work.
local ConstructionRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function ConstructionRules.canBuildWorker(unitKind, hp, owned)
 return owned==true and unitKind=="villager" and finite(hp) and hp>0
end

function ConstructionRules.validateSelection(selection, canBuild, maximum)
 maximum=maximum or 200
 if type(selection)~="table" or type(canBuild)~="function" or not finite(maximum)
  or maximum<1 or maximum%1~=0 then return nil,"selection" end
 local count=0
 for key in pairs(selection) do
  count+=1
  if not finite(key) or key%1~=0 or key<1 or key>maximum or count>maximum then return nil,"selection" end
 end
 if count==0 then return nil,"selection" end
 local result,seen={},{}
 for index=1,count do
  local unit=selection[index]
  if unit==nil or not canBuild(unit) then return nil,"worker" end
  if not seen[unit] then seen[unit]=true; table.insert(result,unit) end
 end
 return result
end

function ConstructionRules.isWorking(unitKind, hp, owned, orderKind, targetsSite, distance, workRange)
 return ConstructionRules.canBuildWorker(unitKind,hp,owned) and orderKind=="build" and targetsSite==true
  and finite(distance) and distance>=0 and finite(workRange) and workRange>=0 and distance<=workRange
end

function ConstructionRules.stepWork(work, duration, workers, dt, extraWorkerRate)
 extraWorkerRate=extraWorkerRate or 0.5
 if not finite(work) or not finite(duration) or work<0 or duration<=0 or work>duration
  or not finite(workers) or workers<0 or workers%1~=0 or not finite(dt) or dt<0
  or not finite(extraWorkerRate) or extraWorkerRate<0 then return nil end
 if workers==0 or work==duration then return work,0,work==duration end
 local gained=math.min(duration-work,dt*(1+(workers-1)*extraWorkerRate))
 local nextWork=work+gained
 return nextWork,gained,nextWork>=duration
end

-- Keep accumulated combat damage. Only collapse floating-point dust near max;
-- an absolute cap ensures the relative tolerance can never consume a 1 HP hit.
function ConstructionRules.initialHP(maxHP)
 if not finite(maxHP) or maxHP<=0 or maxHP>9007199254740991 then return nil end
 return math.min(maxHP,math.max(1,maxHP*0.15))
end

function ConstructionRules.addWorkHP(hp,maxHP,work,duration)
 if not finite(hp) or not finite(maxHP) or not finite(work) or not finite(duration)
  or maxHP<=0 or maxHP>9007199254740991 or hp<0 or hp>maxHP or work<0 or duration<=0 or work>duration then return nil end
 local health=math.min(maxHP,hp+work/duration*maxHP*0.85)
 local tolerance=math.min(maxHP*1e-10,1e-7)
 return maxHP-health<=tolerance and maxHP or health
end

return ConstructionRules
