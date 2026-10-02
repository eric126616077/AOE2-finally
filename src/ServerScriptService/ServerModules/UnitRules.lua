-- Engine-independent limits used by the authority, including repeated target changes.
local UnitRules = {}
local actions = {attack=true, gather=true, repair=true, workFeedback=true}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function UnitRules.takeAction(clocks, unit, action, now, interval)
 if type(clocks)~="table" or unit==nil or not actions[action] or not finite(now)
  or not finite(interval) or interval<0 then return false end
 local clock=clocks[unit]
 local previous=clock and clock[action]
 if previous~=nil and now-previous<interval then return false end
 clock=clock or {}
 clock[action]=now
 clocks[unit]=clock
 return true
end

function UnitRules.canCompletePopulation(liveUnits, capacity)
 return finite(liveUnits) and finite(capacity) and liveUnits>=0 and capacity>=0
  and liveUnits%1==0 and capacity%1==0 and liveUnits<capacity
end

return UnitRules
