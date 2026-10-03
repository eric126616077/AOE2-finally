-- 羊群與野豬的純規則（AOE2 式）；不依賴 Roblox 物件，伺服器與 CLI 測試共用。
local HerdRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

-- 綿羊的歸屬。nearby 為 claimRadius 內其他單位的 {ownerId, distance}（不含綿羊）。
-- relation(a,b) 回傳 "same"／"ally"／"enemy"。
-- 中立羊：最近的單位的主人取得。已有主人的羊：附近有主人或盟友的單位就不變；否則由最近的敵方單位帶走。
-- 回傳新的主人 ID；不變時回傳 nil。
function HerdRules.claim(currentOwnerId,nearby,relation)
 if type(nearby)~="table" or type(relation)~="function" then return nil end
 local best,bestDistance=nil,math.huge
 for _,entry in ipairs(nearby) do
  if type(entry)=="table" and entry.ownerId~=nil and finite(entry.distance) and entry.distance>=0 then
   if currentOwnerId~=nil then
    local kind=entry.ownerId==currentOwnerId and "same" or relation(currentOwnerId,entry.ownerId)
    if kind=="same" or kind=="ally" then return nil end
    if kind=="enemy" and entry.distance<bestDistance then best,bestDistance=entry.ownerId,entry.distance end
   elseif entry.distance<bestDistance then best,bestDistance=entry.ownerId,entry.distance end
  end
 end
 if best==currentOwnerId then return nil end
 return best
end

-- 以出生點朝地圖中心的方向為基準，對稱地放置 count 個點；每個出生點得到相同的相對位置，開局公平。
-- spread 是相鄰兩點的角度（弧度），半徑在 minRadius 與 maxRadius 之間交替。
function HerdRules.ringPoints(homeX,homeZ,centerX,centerZ,count,minRadius,maxRadius,spread,phase)
 if not (finite(homeX) and finite(homeZ) and finite(centerX) and finite(centerZ) and finite(count) and finite(minRadius)
  and finite(maxRadius) and finite(spread)) or count<0 or count%1~=0 or minRadius<0 or maxRadius<minRadius then return nil end
 local dx,dz=centerX-homeX,centerZ-homeZ
 local base=(dx==0 and dz==0) and 0 or math.atan2(dz,dx)
 local points={}
 for index=1,count do
  local angle=base+(index-(count+1)/2)*spread+(finite(phase) and phase or 0)
  local radius=index%2==1 and minRadius or maxRadius
  table.insert(points,{X=homeX+math.cos(angle)*radius,Z=homeZ+math.sin(angle)*radius})
 end
 return points
end

-- 野豬要反擊誰：最近一次打牠、仍在 reach 內的單位優先；否則挑 reach 內最近的。
-- attackers：{key, distance, lastHit}。回傳 key 或 nil。
function HerdRules.boarTarget(attackers,reach)
 if type(attackers)~="table" or not finite(reach) or reach<=0 then return nil end
 local recent,recentTime,nearest,nearestDistance=nil,-math.huge,nil,math.huge
 for _,entry in ipairs(attackers) do
  if type(entry)=="table" and entry.key~=nil and finite(entry.distance) and entry.distance<=reach then
   if finite(entry.lastHit) and entry.lastHit>recentTime then recent,recentTime=entry.key,entry.lastHit end
   if entry.distance<nearestDistance then nearest,nearestDistance=entry.key,entry.distance end
  end
 end
 return recent or nearest
end

-- 野豬受到一次攻擊後的生命（扣護甲，至少 1 點）。
function HerdRules.boarDamage(hp,attack,armor)
 if not finite(hp) or not finite(attack) or attack<=0 then return hp end
 local amount=math.max(1,attack-(finite(armor) and armor or 0))
 return math.max(0,hp-amount)
end

return HerdRules
