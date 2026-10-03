-- Resource conservation and delivery compatibility used by the server authority.
local Rules = {}
local resources = {food=true, wood=true, gold=true, stone=true}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function Rules.takeAmount(available, carrying, capacity, rate)
 if not finite(available) or not finite(carrying) or not finite(capacity) or not finite(rate)
  or available<0 or carrying<0 or capacity<=0 or rate<0 then return 0 end
 return math.min(available, rate, math.max(0, capacity-carrying))
end

function Rules.accepts(buildingData, key)
 if type(buildingData)~="table" or not resources[key] then return false end
 if buildingData.dropoff==true then return true end
 if type(buildingData.dropoff)~="table" then return false end
 return table.find(buildingData.dropoff,key)~=nil
end

function Rules.returnKind(carryType, requestedType)
 if resources[requestedType] then return requestedType end
 return resources[carryType] and carryType or nil
end

-- 獵物等資源以倍率加快採集；只接受 (0,4] 的有限倍率，其餘一律視為 1。
function Rules.gatherRate(rate,multiplier)
 if not finite(rate) or rate<0 then return 0 end
 if finite(multiplier) and multiplier>0 and multiplier<=4 then return rate*multiplier end
 return rate
end

return Rules
