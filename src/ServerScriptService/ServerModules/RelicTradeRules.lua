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
-- 聖物勝利：某一隊存放的聖物等於全圖總數（總數 > 0）時回傳該隊，否則 nil。totals={[隊伍]=件數}
function Rules.relicHolder(totals,total)
 if type(totals)~="table" or not finite(total) or total<=0 then return nil end
 for team,count in pairs(totals) do
  if finite(count) and count>=total then return team end
 end
 return nil
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
-- 電腦：把空閒的僧侶分配到聖物。每次取全體中最近的一組（僧侶, 聖物），一件聖物只派一位。
-- seekers／relics 為 {X,Z} 清單；回傳 {[僧侶索引]=聖物索引}。
function Rules.assignRelics(seekers,relics)
 local result={}
 if type(seekers)~="table" or type(relics)~="table" then return result end
 local usedSeeker,usedRelic={},{}
 for _=1,math.min(#seekers,#relics) do
  local bestSeeker,bestRelic,bestDistance=nil,nil,math.huge
  for i,seeker in ipairs(seekers) do
   if not usedSeeker[i] and finite(seeker.X) and finite(seeker.Z) then
    for j,relic in ipairs(relics) do
     if not usedRelic[j] and finite(relic.X) and finite(relic.Z) then
      local d=(seeker.X-relic.X)^2+(seeker.Z-relic.Z)^2
      if d<bestDistance then bestSeeker,bestRelic,bestDistance=i,j,d end
     end
    end
   end
  end
  if not bestSeeker then break end
  usedSeeker[bestSeeker],usedRelic[bestRelic]=true,true
  result[bestSeeker]=bestRelic
 end
 return result
end
-- 電腦：在己方／盟友市集中找收益最高的路線。markets={{X,Z,own=bool,ally=bool}}，起點必須是己方。
-- 回傳（起點索引, 目的地索引, 每趟黃金）；沒有可獲利的路線時回傳 nil。
function Rules.tradeRoute(markets,config)
 if type(markets)~="table" or type(config)~="table" then return nil end
 local bestHome,bestDestination,bestGold=nil,nil,0
 for i,home in ipairs(markets) do
  if home.own==true and finite(home.X) and finite(home.Z) then
   for j,destination in ipairs(markets) do
    if i~=j and finite(destination.X) and finite(destination.Z) then
     local distance=math.sqrt((home.X-destination.X)^2+(home.Z-destination.Z)^2)
     local gold=Rules.tradeGold(distance,config,destination.own~=true)
     if gold>bestGold then bestHome,bestDestination,bestGold=i,j,gold end
    end
   end
  end
 end
 if not bestHome then return nil end
 return bestHome,bestDestination,bestGold
end
-- 電腦：第二座市集的候選位置，依離第一座市集由遠到近排序，只保留距離足夠貿易的位置。
function Rules.farSpots(candidates,from,minDistance)
 local result={}
 if type(candidates)~="table" or type(from)~="table" or not finite(from.X) or not finite(from.Z) or not finite(minDistance) then return result end
 for _,spot in ipairs(candidates) do
  if finite(spot.X) and finite(spot.Z) then
   local distance=math.sqrt((spot.X-from.X)^2+(spot.Z-from.Z)^2)
   if distance>=minDistance then table.insert(result,{X=spot.X,Z=spot.Z,distance=distance}) end
  end
 end
 table.sort(result,function(a,b) if a.distance~=b.distance then return a.distance>b.distance end; if a.X~=b.X then return a.X<b.X end; return a.Z<b.Z end)
 return result
end
return Rules
