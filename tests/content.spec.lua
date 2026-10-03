-- 兵種升級、新兵種與狩獵的設定完整性與純規則檢查（不代替 Studio Play）。
local Production=require("../src/ServerScriptService/ServerModules/ProductionRules")
local Combat=require("../src/ServerScriptService/ServerModules/CombatRules")
local Gathering=require("../src/ServerScriptService/ServerModules/GatheringRules")
local RelicTrade=require("../src/ServerScriptService/ServerModules/RelicTradeRules")
local checks=0
local function expect(ok,message)
 checks+=1
 assert(ok,message)
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local classes={villager=true,infantry=true,archer=true,cavalry=true,siege=true,monk=true}

-- 科技順序與定義一一對應，名稱不重複。
local ordered,names={},{}
for _,key in ipairs(Config.TechnologyOrder) do
 expect(Config.Technologies[key]~=nil,"technology order lists unknown key "..key)
 expect(not ordered[key],"technology listed twice "..key)
 ordered[key]=true
end
for key,data in pairs(Config.Technologies) do
 expect(ordered[key],"technology missing from TechnologyOrder "..key)
 expect(not names[data.name],"duplicate technology name "..data.name)
 names[data.name]=true
 expect(Config.Buildings[data.building]~=nil,"technology researched at unknown building "..key)
 -- 開局就有市鎮中心，它的 minAge 只限制增建。
 local buildingAge=data.building=="TownCenter" and 1 or (Config.Buildings[data.building].minAge or 1)
 expect(Config.Ages[data.minAge]~=nil and data.minAge>=buildingAge,"technology age earlier than its building "..key)
 for _,cost in pairs(data.cost) do expect(finite(cost) and cost>0,"invalid technology cost "..key) end
 if data.requires then
  local before=Config.Technologies[data.requires]
  expect(before~=nil,"unknown prerequisite for "..key)
  expect(before.minAge<=data.minAge,"prerequisite unlocks after "..key)
 end
end

-- 兵種升級：目標兵種存在、在研究建築訓練、數值有效；同一條升級線的前置科技升級同一兵種。
local upgrades=0
for key,data in pairs(Config.Technologies) do
 local upgrade=data.upgrade
 if upgrade then
  upgrades+=1
  local unit=Config.Units[upgrade.unit]
  expect(unit~=nil,"upgrade targets unknown unit "..key)
  expect(table.find(Config.Buildings[data.building].trains,upgrade.unit)~=nil,"upgrade researched where the unit is not trained "..key)
  expect(data.minAge>unit.minAge or (data.minAge==unit.minAge and data.minAge==4),"upgrade available before its unit "..key)
  expect(type(upgrade.name)=="string" and upgrade.name~="" and upgrade.name~=unit.name,"upgrade lacks a new unit name "..key)
  expect(data.effect==nil and data.unitClass==nil,"upgrade also changes a whole class "..key)
  for _,stat in ipairs({"hp","attack","armor","range"}) do
   if upgrade[stat]~=nil then expect(finite(upgrade[stat]) and upgrade[stat]>0,"invalid upgrade "..stat.." "..key) end
  end
  for _,stat in ipairs({"speed","interval"}) do
   if upgrade[stat]~=nil then expect(finite(upgrade[stat]) and upgrade[stat]>0 and upgrade[stat]<0.5,"invalid upgrade ratio "..stat.." "..key) end
  end
  for class,amount in pairs(upgrade.bonus or {}) do
   expect((classes[class] or class=="building") and finite(amount) and amount>0,"invalid upgrade bonus "..key)
  end
  if data.requires then
   local before=Config.Technologies[data.requires]
   expect(before.upgrade and before.upgrade.unit==upgrade.unit,"chained upgrade changes a different unit "..key)
  end
 end
end
expect(upgrades==12,"expected 12 unit upgrade technologies, got "..upgrades)

-- 新兵種：訓練建築雙向一致；騎乘單位屬於騎兵；雙重類別有效；遠程單位都有投射物速度。
for kind,data in pairs(Config.Units) do
 for _,building in ipairs(data.trainsAt) do
  expect(Config.Buildings[building]~=nil and table.find(Config.Buildings[building].trains,kind)~=nil,"unit not trained at its listed building "..kind)
 end
 if data.mounted then expect(data.class=="cavalry","mounted unit is not cavalry "..kind) end
 if data.alsoClass then
  expect(classes[data.alsoClass] and data.alsoClass~=data.class,"invalid second class "..kind)
 end
 expect(Config.UnitCollision.profiles[data.class]~=nil,"unit class lacks collision profile "..kind)
 if data.range>20 then
  local projectile=Config.Combat.projectileKinds[kind] or "arrow"
  expect(finite(Config.Combat.projectile[projectile]) and Config.Combat.projectile[projectile]>0,"ranged unit has no projectile speed "..kind)
 end
end
for building,data in pairs(Config.Buildings) do
 for _,kind in ipairs(data.trains) do
  expect(table.find(Config.Units[kind].trainsAt,building)~=nil,"building trains a unit that does not list it "..building.."/"..kind)
 end
end
expect(Config.Units.cavalryArcher.class=="cavalry" and Config.Units.cavalryArcher.alsoClass=="archer","cavalry archer lost its dual class")
expect(Config.Units.camel.bonus.cavalry>0,"camel lost its anti-cavalry bonus")
expect(Config.Units.handCannoneer.minAge==4 and Config.Units.handCannoneer.bonus.infantry>0,"hand cannoneer is not an imperial anti-infantry unit")

-- 升級套用：累加、改名、無效輸入不改狀態。
local modifiers,unitNames={},{}
expect(Production.applyUpgrade(modifiers,unitNames,Config.Technologies.LongSwordsman.upgrade,Config.Units)=="長劍兵","long swordsman name")
expect(modifiers.infantry.hp==20 and modifiers.infantry.attack==3,"long swordsman stats")
expect(Production.applyUpgrade(modifiers,unitNames,Config.Technologies.Champion.upgrade,Config.Units)=="冠軍劍士","champion name")
expect(modifiers.infantry.hp==30 and modifiers.infantry.attack==5 and modifiers.infantry.armor==1,"chained upgrades must add up")
expect(Production.applyUpgrade(modifiers,unitNames,Config.Technologies.Pikeman.upgrade,Config.Units)=="長戟兵","pikeman name")
expect(modifiers.spearman.bonus.cavalry==10,"pikeman bonus")
expect(modifiers.archer==nil and unitNames.archer==nil,"upgrade leaked into another unit")
local snapshot=modifiers.infantry.hp
for _,bad in ipairs({
 {unit="nobody",hp=5},{unit="infantry",hp=0/0},{unit="infantry",attack=math.huge},
 {unit="infantry",bonus={cavalry="10"}},{hp=5},"infantry",false,
}) do
 expect(Production.applyUpgrade(modifiers,unitNames,bad,Config.Units)==nil,"invalid upgrade accepted")
end
expect(modifiers.infantry.hp==snapshot and unitNames.infantry=="冠軍劍士","rejected upgrade changed state")
expect(Production.applyUpgrade(nil,unitNames,Config.Technologies.Crossbowman.upgrade,Config.Units)==nil,"missing modifier table accepted")

-- 剋制加成：雙重類別取較高者，不疊加；升級加成相加；無效值忽略。
local spear,skirm,camel=Config.Units.spearman.bonus,Config.Units.skirmisher.bonus,Config.Units.camel.bonus
expect(Combat.counterBonus(spear,nil,"cavalry","archer")==spear.cavalry,"spearman bonus vs cavalry archer")
expect(Combat.counterBonus(skirm,nil,"cavalry","archer")==skirm.archer,"skirmisher bonus vs cavalry archer")
expect(Combat.counterBonus(spear,{cavalry=10},"cavalry","archer")==spear.cavalry+10,"upgrade bonus not added")
expect(Combat.counterBonus({cavalry=5,archer=7},nil,"cavalry","archer")==7,"dual class must take the higher bonus, not the sum")
expect(Combat.counterBonus(camel,nil,"cavalry",nil)==camel.cavalry,"camel vs cavalry")
expect(Combat.counterBonus(camel,nil,"infantry",nil)==0,"camel bonus leaked to infantry")
expect(Combat.counterBonus({building=40},{building=15},"building",nil)==55,"capped ram building bonus")
expect(Combat.counterBonus({cavalry=0/0},{cavalry=math.huge},"cavalry",nil)==0,"invalid bonus values accepted")
expect(Combat.counterBonus(nil,nil,nil,nil)==0,"missing data must give no bonus")

-- 狩獵：鹿出現在每個出生區的開局資源，採集倍率有效。
local deer=Config.Resources.Deer
expect(deer and deer.resource=="food" and deer.hunt==true,"deer resource definition")
expect(finite(deer.gatherMultiplier) and deer.gatherMultiplier>1 and deer.gatherMultiplier<=4,"deer gather multiplier")
local opening=false
for _,patch in ipairs(Config.Map.ResourceLayout.OpeningClusters) do if patch.kind=="Deer" then opening=patch.count>=2 end end
expect(opening,"every base must receive a deer herd")
expect(Config.Map.ResourceVisualFootprints.Deer~=nil,"deer has no visual footprint")
expect(Gathering.gatherRate(3,deer.gatherMultiplier)==3*deer.gatherMultiplier,"hunting is not faster")
expect(Gathering.gatherRate(3,nil)==3 and Gathering.gatherRate(3,0)==3 and Gathering.gatherRate(3,9)==3 and Gathering.gatherRate(3,0/0)==3,"invalid multiplier changed rate")
expect(Gathering.gatherRate(-1,2)==0 and Gathering.gatherRate(math.huge,2)==0,"invalid base rate accepted")

-- 聖物位置：每種地圖尺寸的數量都能排出；每件聖物到四個出生點的距離集合相同（公平）；不在基地保留區或地圖外。
local layout=Config.Map.ResourceLayout
for sizeName,size in pairs(Config.Map.Sizes) do
 local count=Config.Relics.counts[sizeName]
 local points=RelicTrade.relicPoints(size,count,Config.Relics.axisRadii[sizeName])
 expect(points~=nil and #points==count,"relic layout cannot place configured count: "..sizeName)
 local half,base=size/2,size/2-168
 local spawns={{-base,-base},{base,base},{base,-base},{-base,base}}
 local perSpawn={}
 for index,spawn in ipairs(spawns) do
  local distances={}
  for _,point in ipairs(points) do
   expect(math.abs(point.X)<=half-layout.BorderMargin and math.abs(point.Z)<=half-layout.BorderMargin,"relic outside map: "..sizeName)
   local d=math.sqrt((point.X-spawn[1])^2+(point.Z-spawn[2])^2)
   expect(d>=layout.BaseClearance,"relic inside a base reservation: "..sizeName)
   table.insert(distances,math.floor(d*1000+0.5))
  end
  table.sort(distances)
  perSpawn[index]=table.concat(distances,",")
 end
 for index=2,4 do expect(perSpawn[index]==perSpawn[1],"relic distances differ between bases: "..sizeName) end
 for i=1,#points do for j=i+1,#points do
  expect((points[i].X-points[j].X)^2+(points[i].Z-points[j].Z)^2>=60^2,"relics placed too close together: "..sizeName)
 end end
end
expect(RelicTrade.relicPoints(1024,6,{0.5})==nil,"invalid relic count accepted")
expect(RelicTrade.relicPoints(1024,4,{1.2})==nil and RelicTrade.relicPoints(0/0,4,{0.5})==nil,"invalid relic layout accepted")
expect(#RelicTrade.relicPoints(1024,1,{})==1,"single center relic")
-- 讓位：原點可用就不動；被占時找最近的可用點；完全找不到時回傳 nil。
local kept=RelicTrade.nudge({X=10,Z=20},function() return true end)
expect(kept.X==10 and kept.Z==20,"clear relic spot moved")
local moved=RelicTrade.nudge({X=0,Z=0},function(x,z) return x*x+z*z>=100 end,6,10)
expect(moved and moved.X*moved.X+moved.Z*moved.Z>=100 and moved.X*moved.X+moved.Z*moved.Z<=13^2,"relic not nudged to the nearest clear ring")
expect(RelicTrade.nudge({X=0,Z=0},function() return false end,6,3)==nil,"blocked relic spot invented a position")
-- 聖物收入：累積小數，只入帳整數；無效輸入不入帳。
local total,acc=0,0
for _=1,100 do local gold; gold,acc=RelicTrade.relicIncome(acc,3,Config.Relics.goldPerSecond,0.1); total+=gold end
expect(total==math.floor(3*Config.Relics.goldPerSecond*10+1e-9) or total==math.floor(3*Config.Relics.goldPerSecond*10)-1,"relic income lost or invented gold")
expect(total+acc>=14.99 and total+acc<=15.01,"relic income accumulation drifted")
for _,bad in ipairs({{0,0.5,1},{2,0/0,1},{2,0.5,-1},{2,0.5,math.huge},{-1,0.5,1}}) do
 local gold=RelicTrade.relicIncome(0,bad[1],bad[2],bad[3])
 expect(gold==0,"invalid relic income credited gold")
end
-- 貿易：距離不足為 0、越遠越多（遞增）、盟友加成、無效輸入為 0。
local trade=Config.Trade
expect(RelicTrade.tradeGold(trade.minDistance-1,trade,false)==0,"short trade route paid gold")
local previous=-1
for distance=trade.minDistance,1500,25 do
 local gold=RelicTrade.tradeGold(distance,trade,false)
 expect(gold>=previous and gold>0,"trade gold does not grow with distance")
 previous=gold
end
expect(RelicTrade.tradeGold(800,trade,true)>RelicTrade.tradeGold(800,trade,false),"ally trade bonus missing")
expect(RelicTrade.tradeGold(0/0,trade,false)==0 and RelicTrade.tradeGold(800,nil,false)==0 and RelicTrade.tradeGold(-5,trade,false)==0,"invalid trade input paid gold")
expect(RelicTrade.tradeArrival(true,40)=="deliver" and RelicTrade.tradeArrival(false,0)=="load" and RelicTrade.tradeArrival(true,0)=="load","trade arrival actions")
expect(RelicTrade.tradeArrival(false,40)==nil,"loaded cart delivered gold to a foreign market")
-- 聖物勝利：只有存放全部聖物的隊伍成立；總數為 0 或資料無效時沒有持有者。
expect(RelicTrade.relicHolder({[1]=5,[2]=0},5)==1,"relic holder not found")
expect(RelicTrade.relicHolder({[1]=3,[2]=2},5)==nil,"split relics produced a holder")
expect(RelicTrade.relicHolder({},0)==nil and RelicTrade.relicHolder({[1]=0},0)==nil,"zero relics produced a holder")
expect(RelicTrade.relicHolder({[1]=0/0},5)==nil and RelicTrade.relicHolder(nil,5)==nil and RelicTrade.relicHolder({[1]=5},0/0)==nil,"invalid relic totals produced a holder")
expect(Config.MatchModes.Relic~=nil and Config.Relics.victoryTime>0,"relic victory mode config")
-- 電腦分派聖物：一件聖物只派一位、取全體最近；僧侶或聖物不足時只分派能配對的數量。
local assigned=RelicTrade.assignRelics({{X=0,Z=0},{X=100,Z=0},{X=50,Z=50}},{{X=95,Z=0},{X=5,Z=0}})
expect(assigned[1]==2 and assigned[2]==1 and assigned[3]==nil,"relic assignment is not nearest-unique")
local count=0; for _ in pairs(RelicTrade.assignRelics({{X=0,Z=0}},{{X=1,Z=1},{X=2,Z=2}})) do count+=1 end
expect(count==1,"one monk assigned to several relics")
expect(next(RelicTrade.assignRelics({{X=0/0,Z=0}},{{X=1,Z=1}}))==nil and next(RelicTrade.assignRelics(nil,{}))==nil,"invalid seekers assigned")
-- 電腦貿易路線：起點必須是己方；收益最高（含盟友加成）；距離不足時沒有路線。
local home,destination,gold=RelicTrade.tradeRoute({{X=0,Z=0,own=true},{X=300,Z=0,own=true},{X=0,Z=500,own=false}},Config.Trade)
expect(home==2 and destination==3 and gold==RelicTrade.tradeGold(math.sqrt(300^2+500^2),Config.Trade,true),"trade route did not pick the most profitable market")
home,destination=RelicTrade.tradeRoute({{X=0,Z=0,own=false},{X=900,Z=0,own=false}},Config.Trade)
expect(home==nil,"trade route started from an allied market")
home=RelicTrade.tradeRoute({{X=0,Z=0,own=true},{X=50,Z=0,own=true}},Config.Trade)
expect(home==nil,"too-short trade route accepted")
-- 第二座市集候選：只留距離足夠的位置，由遠到近。
local spots=RelicTrade.farSpots({{X=10,Z=0},{X=300,Z=0},{X=0,Z=200},{X=0/0,Z=0}},{X=0,Z=0},176)
expect(#spots==2 and spots[1].X==300 and spots[2].Z==200,"far market spots not filtered and ranked")
-- 貿易車與商隊設定。
local cart=Config.Units.tradeCart
expect(cart.class=="trade" and cart.damage==0 and table.find(Config.Buildings.Market.trains,"tradeCart"),"trade cart definition")
expect(Config.Garrison.blocked.trade==true,"trade carts can garrison")
expect(Config.Technologies.Caravan.unitClass=="trade" and Config.Technologies.Caravan.effect.speed>0,"caravan tech")
print(string.format("PASS: %d unit upgrade / new unit / hunting / relic / trade content checks",checks))
