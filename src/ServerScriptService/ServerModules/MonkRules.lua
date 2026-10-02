-- 純僧侶規則：招降、治療與信仰恢復。參考 AOE2：招降至少持續數秒，之後每秒有機率成功，
-- 到上限必定成功；成功後信仰歸零需恢復。不依賴 Roblox 物件，伺服器與 CLI 測試共用。
local MonkRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
MonkRules.finite = finite

-- 不能招降：建築、僧侶（AOE2 需要贖罪科技）與已陣亡的單位。
function MonkRules.canConvert(targetClass,targetIsBuilding,targetHP,faith,maxFaith)
 if targetIsBuilding==true then return false,"僧侶無法招降建築。" end
 if type(targetClass)~="string" then return false,"只能招降敵方單位。" end
 if targetClass=="monk" then return false,"僧侶無法招降敵方僧侶。" end
 if not finite(targetHP) or targetHP<=0 then return false,"目標已無法招降。" end
 if not finite(faith) or not finite(maxFaith) or maxFaith<=0 or faith<maxFaith then return false,"信仰尚未恢復，暫時無法招降。" end
 return true
end

-- elapsed：已在射程內持續招降的秒數；roll：0–1 的亂數，由伺服器產生。
function MonkRules.conversionSucceeds(elapsed,minTime,maxTime,chance,roll)
 if not (finite(elapsed) and finite(minTime) and finite(maxTime) and finite(chance) and finite(roll)) then return false end
 if elapsed<0 or minTime<0 or maxTime<minTime then return false end
 if elapsed>=maxTime then return true end
 if elapsed<minTime then return false end
 return roll<math.clamp(chance,0,1)
end

-- 治療自己或同盟的受傷單位；攻城器械與建築不能由僧侶治療。
function MonkRules.canHeal(targetClass,targetIsBuilding,friendly,hp,maxHP)
 if targetIsBuilding==true or friendly~=true or type(targetClass)~="string" or targetClass=="siege" then return false end
 return finite(hp) and finite(maxHP) and hp>0 and hp<maxHP
end

function MonkRules.heal(hp,maxHP,rate,dt)
 if not (finite(hp) and finite(maxHP) and finite(rate) and finite(dt)) or hp<=0 or rate<0 or dt<0 then return hp end
 return math.min(maxHP,hp+rate*dt)
end

function MonkRules.regenFaith(faith,maxFaith,rechargeTime,dt)
 if not (finite(maxFaith) and maxFaith>0) then return 0 end
 if not finite(faith) then faith=0 end
 if not (finite(rechargeTime) and rechargeTime>0 and finite(dt) and dt>=0) then return math.clamp(faith,0,maxFaith) end
 return math.clamp(faith+maxFaith*dt/rechargeTime,0,maxFaith)
end

return MonkRules
