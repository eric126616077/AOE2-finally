-- 純駐紮規則（參考 AOE2）：哪些單位能進入、建築容量、駐軍增加的箭數與駐紮中的回復。
-- 不依賴 Roblox 物件，伺服器與 CLI 測試共用。
local GarrisonRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

-- 建築設定的 garrison.capacity；沒有設定或數值無效就是不能駐紮。
function GarrisonRules.capacity(buildingData)
 local garrison=type(buildingData)=="table" and buildingData.garrison
 local capacity=type(garrison)=="table" and garrison.capacity
 if not finite(capacity) or capacity<1 or capacity%1~=0 then return 0 end
 return capacity
end

-- blocked 可設在全域（攻城器械）與個別建築（瞭望塔不收騎兵）。
function GarrisonRules.canEnter(config,buildingData,complete,count,unitClass,hp)
 local capacity=GarrisonRules.capacity(buildingData)
 if capacity==0 or type(config)~="table" then return false,"這座建築不能駐紮。" end
 if complete~=true then return false,"建築完工後才能駐紮。" end
 if type(unitClass)~="string" or not finite(hp) or hp<=0 then return false,"這個單位無法駐紮。" end
 local blocked=buildingData.garrison.blocked
 if (type(config.blocked)=="table" and config.blocked[unitClass]==true)
  or (type(blocked)=="table" and blocked[unitClass]==true) then return false,"這種單位不能進入這座建築。" end
 if not finite(count) or count<0 or count%1~=0 or count>=capacity then return false,"建築已滿，無法再駐紮。" end
 return true
end

-- classCounts：兵種類別 → 駐紮人數。每個類別依權重累加後無條件捨去，再受建築上限限制。
function GarrisonRules.arrows(weights,classCounts,maxArrows)
 if type(weights)~="table" or type(classCounts)~="table" then return 0 end
 local total=0
 for class,count in pairs(classCounts) do
  local weight=weights[class]
  if finite(weight) and weight>0 and finite(count) and count>0 then total+=weight*math.floor(count) end
 end
 local limit=finite(maxArrows) and maxArrows>=0 and math.floor(maxArrows) or 0
 return math.min(math.floor(total+1e-6),limit)
end

function GarrisonRules.heal(hp,maxHP,rate,dt)
 if not (finite(hp) and finite(maxHP) and finite(rate) and finite(dt)) or hp<=0 or rate<0 or dt<0 then return hp end
 return math.max(hp,math.min(maxHP,hp+rate*dt))
end

-- 離開建築時的生命：保留駐紮中的數值，但不超過目前上限，也不會低於 1。
function GarrisonRules.restoreHP(hp,maxHP)
 if not finite(maxHP) or maxHP<1 then return 1 end
 if not finite(hp) then return maxHP end
 return math.clamp(hp,1,maxHP)
end

return GarrisonRules
