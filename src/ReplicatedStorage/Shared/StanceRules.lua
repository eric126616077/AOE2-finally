-- 單位姿態的純規則（AOE2 式）：攻擊、防守、堅守、不攻擊。伺服器決定索敵與追擊，客戶端只顯示。
local StanceRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function StanceRules.valid(config,key)
 return type(config)=="table" and type(config.types)=="table" and type(key)=="string" and config.types[key]~=nil
end

-- 無效或缺少的姿態一律視為預設（攻擊姿態），舊單位與駐紮紀錄不受影響。
function StanceRules.resolve(config,key)
 if StanceRules.valid(config,key) then return key end
 return config and config.default or "Aggressive"
end

-- 會不會自動找敵人：只有「不攻擊」不會。
function StanceRules.acquires(stance)
 return stance~="NoAttack"
end

-- 被攻擊時是否反擊。堅守姿態仍會反擊，但之後的步驟不允許它離開原位。
function StanceRules.retaliates(stance)
 return stance~="NoAttack"
end

-- 自動索敵的半徑：堅守只看武器射程（加上一點容許值），其他姿態用一般索敵半徑。
function StanceRules.acquisitionRadius(stance,baseRadius,range)
 if not finite(baseRadius) or baseRadius<=0 or not finite(range) or range<0 then return nil end
 if stance=="StandGround" then return math.min(baseRadius,range+2) end
 return baseRadius
end

-- 自動追擊最遠能離開原位多少：堅守為 0（不移動），防守為短距離，攻擊沿用一般上限。
function StanceRules.leash(stance,defaultLeash,defensiveLeash)
 if stance=="StandGround" then return 0 end
 if stance=="Defensive" then return math.min(defaultLeash,defensiveLeash) end
 return defaultLeash
end

-- 自動接戰時是否可以移動去追打目標。
function StanceRules.mayChase(stance)
 return stance~="StandGround"
end

return StanceRules
