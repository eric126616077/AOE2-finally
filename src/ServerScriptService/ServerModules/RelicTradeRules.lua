-- 聖物與貿易的純規則；聖物實例、尋路與資源入帳留在伺服器。
local Rules={}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
Rules.finite=finite
-- 聖物位置：四條軸線（出生點在對角線上，軸線上的點到相鄰兩個出生點等距），
-- 每個半徑一圈四件；數量除以 4 餘 1 時多放一件在地圖中心。回傳 {X,Z} 清單，設定無效時回傳 nil。
function Rules.relicPoints(mapSize,count,radii)
 if not finite(mapSize) or mapSize<=0 or not finite(count) or count<0 or count%1~=0 or type(radii)~="table" then return nil end
 local rings=math.floor(count/4)
 local center=count-rings*4
 if center>1 or #radii~=rings then return nil end
 local half=mapSize/2
 local points={}
 if center==1 then table.insert(points,{X=0,Z=0}) end
 for _,ratio in ipairs(radii) do
  if not finite(ratio) or ratio<=0 or ratio>=1 then return nil end
  local r=half*ratio
  for _,axis in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do table.insert(points,{X=axis[1]*r,Z=axis[2]*r}) end
 end
 return points
end
-- 位置被資源或障礙占用時，從原點往外逐圈尋找最近的可用位置；同一圈依固定角度順序，結果可重現。
function Rules.nudge(point,isClear,step,rings)
 if type(point)~="table" or type(isClear)~="function" then return nil end
 step,rings=step or 6,rings or 10
 if isClear(point.X,point.Z) then return {X=point.X,Z=point.Z} end
 for ring=1,rings do
  local radius=ring*step
  local samples=math.max(8,ring*6)
  for index=0,samples-1 do
   local angle=index*2*math.pi/samples
   local x,z=point.X+math.cos(angle)*radius,point.Z+math.sin(angle)*radius
   if isClear(x,z) then return {X=x,Z=z} end
  end
 end
 return nil
end
-- 聖物收入：累積小數，只把整數黃金入帳。回傳（本次入帳的整數黃金, 新的累積值）。
function Rules.relicIncome(accumulated,relics,rate,dt)
 if not finite(accumulated) or accumulated<0 then accumulated=0 end
 if not finite(relics) or relics<=0 or not finite(rate) or rate<=0 or not finite(dt) or dt<=0 or dt>5 then return 0,accumulated end
 local total=accumulated+relics*rate*dt
 local whole=math.floor(total)
 return whole,total-whole
end
-- 每趟貿易的黃金：距離越遠越多（含平方項）；距離不足或設定無效時為 0。盟友市集另加比例獎勵。
function Rules.tradeGold(distance,config,ally)
 if type(config)~="table" or not finite(distance) or distance<0 then return 0 end
 if not finite(config.minDistance) or distance<config.minDistance then return 0 end
 local linear=finite(config.goldPerStud) and config.goldPerStud or 0
 local squared=finite(config.goldPerStudSquared) and config.goldPerStudSquared or 0
 local bonus=(ally==true and finite(config.allyBonus)) and config.allyBonus or 0
 return math.max(0,math.floor((distance*linear+distance*distance*squared)*(1+bonus)))
end
-- 貿易車抵達市集：抵達自己的市集且載有黃金就交貨；否則（對方或另一座市集）依路程裝貨。
-- 回傳 "deliver"、"load" 或 nil（沒有可做的事，例如空車回到自己的市集）。
function Rules.tradeArrival(ownMarket,carrying)
 if ownMarket==true and finite(carrying) and carrying>0 then return "deliver" end
 if not finite(carrying) or carrying<=0 then return "load" end
 return nil
end
return Rules
