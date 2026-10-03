-- 純戰鬥規則。空間格與建築占地由 SpatialRules 處理，這裡不依賴 Roblox 物件。
local CombatRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

-- 目標優先層級：數值越小越優先。一般部隊先打會反擊的軍隊；攻城武器先打建築。
local PRIORITY = {
 units={military=0,villager=1,defense=2,building=3},
 buildings={defense=0,building=0,military=2,villager=3},
}

function CombatRules.acquisitionRadius(base,attackRange)
 if not finite(base) or not finite(attackRange) or base<0 or attackRange<0 then return nil end
 -- 遠程部隊必須能找到已在自己射程內的敵人。
 return math.max(base,attackRange)
end

function CombatRules.areEnemies(firstId,secondId,firstAlive,secondAlive)
 return firstAlive==true and secondAlive==true and finite(firstId) and finite(secondId) and firstId~=secondId
end

function CombatRules.canRetaliate(currentOrderKind,attackerIsEnemy,attackerIsBuilding,victimIsVillager)
 -- 村民不會丟下工作走去攻擊射擊自己的防禦建築。
 if attackerIsBuilding==true and victimIsVillager==true then return false end
 -- 明確的移動、交貨、施工與修復指令優先；待命或採集才自動反擊。
 return attackerIsEnemy==true and (currentOrderKind==nil or currentOrderKind=="gather")
end

-- 分數越低越優先：邊緣距離加上每一優先層級的等效距離。
function CombatRules.targetScore(distance,category,tierDistance,preferred)
 local tiers=PRIORITY[preferred or "units"]
 local tier=tiers and tiers[category]
 if not finite(distance) or distance<0 or tier==nil or not finite(tierDistance) or tierDistance<0 then return nil end
 return distance+tier*tierDistance
end

function CombatRules.shouldSwitch(currentScore,candidateScore,margin)
 if not finite(candidateScore) or not finite(margin) or margin<0 then return false end
 -- 目前目標失效時立即換；否則新目標必須明顯更好，避免距離相近的敵人造成來回切換與重新尋路。
 if not finite(currentScore) then return true end
 return candidateScore<currentScore-margin
end

function CombatRules.beyondLeash(anchorX,anchorZ,x,z,leash)
 if not finite(anchorX) or not finite(anchorZ) or not finite(x) or not finite(z) or not finite(leash) or leash<0 then return false end
 local dx,dz=x-anchorX,z-anchorZ
 return dx*dx+dz*dz>leash*leash
end

-- 投射物飛行秒數：距離除以速度，夾在最短與最長之間。
function CombatRules.flightTime(distance,speed,minTime,maxTime)
 if not finite(distance) or not finite(speed) or not finite(minTime) or not finite(maxTime)
  or distance<0 or speed<=0 or minTime<0 or maxTime<minTime then return nil end
 return math.clamp(distance/speed,minTime,maxTime)
end

-- 近戰揮到的瞬間目標仍在武器長度加容許值內才算命中。
function CombatRules.connects(distance,reach,tolerance)
 return finite(distance) and finite(reach) and finite(tolerance) and distance>=0 and reach>=0 and tolerance>=0
  and distance<=reach+tolerance
end

-- 落地型投射物：建築不會移動必定命中；單位離開落點半徑就躲開。
function CombatRules.landsOn(isBuilding,distanceFromImpact,radius)
 if isBuilding==true then return true end
 return finite(distanceFromImpact) and finite(radius) and distanceFromImpact>=0 and radius>=0 and distanceFromImpact<=radius
end

-- 剋制加成：攻擊者設定加成加上兵種升級加成（extra）。雙重類別的目標（例如騎射手同時是騎兵與遠程部隊）
-- 取兩類中較高的一個，不重複疊加。
function CombatRules.counterBonus(base,extra,targetClass,alsoClass)
 base=type(base)=="table" and base or {}
 extra=type(extra)=="table" and extra or {}
 local function value(class)
  if type(class)~="string" then return 0 end
  local total=(finite(base[class]) and base[class] or 0)+(finite(extra[class]) and extra[class] or 0)
  return math.max(0,total)
 end
 return math.max(value(targetClass),value(alsoClass))
end

return CombatRules
