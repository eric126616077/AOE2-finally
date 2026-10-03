-- 新增的 AOE2 元素：市集浮動價格與進貢、單位姿態、羊群／野豬、戰爭迷霧，以及新建築／單位／科技的設定完整性。
-- 只是純規則檢查，不代替 Studio Play。scripts/verify.ps1 會注入實際的 Config。
local Market=require("../src/ReplicatedStorage/Shared/MarketRules")
local Stance=require("../src/ReplicatedStorage/Shared/StanceRules")
local Fog=require("../src/ReplicatedStorage/Shared/FogRules")
local Herd=require("../src/ServerScriptService/ServerModules/HerdRules")
local checks=0
local function expect(ok,message)
 checks+=1
 assert(ok,message)
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end

-- 市集 ----------------------------------------------------------------------
local trade=Config.MarketTrade
expect(Market.valid(trade),"market configuration invalid")
local buy,sell=Market.quote(trade.basePrice,trade)
expect(buy==trade.buyGold and sell==trade.sellGold,"base quote no longer matches the documented 130 / 70")
local price=trade.basePrice
for _=1,10 do price=Market.after(price,"Buy",trade) end
expect(price==trade.basePrice+10*trade.step,"buying did not raise the shared price")
local higherBuy,higherSell=Market.quote(price,trade)
expect(higherBuy>buy and higherSell>sell,"higher price did not raise both quotes")
for _=1,1000 do price=Market.after(price,"Sell",trade) end
expect(price==trade.minPrice,"price fell below the minimum")
local lowBuy,lowSell=Market.quote(price,trade)
expect(lowSell>=1 and lowBuy>lowSell,"minimum price quotes must keep buy above sell")
for _=1,1000 do price=Market.after(price,"Buy",trade) end
expect(price==trade.maxPrice,"price rose above the maximum")
expect(Market.after(150,"Hold",trade)==150,"unknown direction changed the price")
for _,bad in ipairs({0/0,math.huge,-math.huge,"100",nil}) do
 expect(Market.price(bad,trade)==trade.basePrice,"invalid stored price not reset to base")
end
expect(Market.price(5,trade)==trade.minPrice and Market.price(99999,trade)==trade.maxPrice,"stored price not clamped")
-- 進貢手續費：基本 30%，鑄幣減半，銀行業免除。
local total,fee=Market.tribute(100,Config.Tribute.fee,0)
expect(total==130 and fee==30,"tribute fee wrong")
total,fee=Market.tribute(100,Config.Tribute.fee,Config.Technologies.Coinage.effect.tributeFeeCut)
expect(total==115 and fee==15,"coinage did not halve the fee")
total,fee=Market.tribute(500,Config.Tribute.fee,Config.Technologies.Coinage.effect.tributeFeeCut+Config.Technologies.Banking.effect.tributeFeeCut)
expect(total==500 and fee==0,"banking did not remove the fee")
for _,bad in ipairs({0,-100,10.5,0/0,math.huge,"100"}) do expect(Market.tribute(bad,0.3,0)==nil,"invalid tribute amount accepted") end
expect(Market.tributeAmount(100,Config.Tribute.amounts) and Market.tributeAmount(500,Config.Tribute.amounts),"configured tribute amounts rejected")
expect(not Market.tributeAmount(250,Config.Tribute.amounts) and not Market.tributeAmount(0/0,Config.Tribute.amounts),"unlisted tribute amount accepted")

-- 姿態 ----------------------------------------------------------------------
local stances=Config.Stances
for _,key in ipairs(stances.order) do
 expect(Stance.valid(stances,key) and type(stances.types[key].name)=="string","stance missing from types "..key)
end
expect(Stance.resolve(stances,"Nope")==stances.default and Stance.resolve(stances,nil)==stances.default,"invalid stance not reset to default")
expect(Stance.resolve(stances,"StandGround")=="StandGround","valid stance changed")
expect(not Stance.acquires("NoAttack") and Stance.acquires("Aggressive") and Stance.acquires("StandGround"),"acquisition by stance wrong")
expect(not Stance.retaliates("NoAttack") and Stance.retaliates("Defensive"),"retaliation by stance wrong")
expect(Stance.acquisitionRadius("StandGround",72,48)==50 and Stance.acquisitionRadius("StandGround",72,3.5)==5.5,"stand ground looks beyond its weapon")
expect(Stance.acquisitionRadius("Aggressive",72,3.5)==72,"aggressive radius reduced")
expect(Stance.acquisitionRadius("Aggressive",0/0,3)==nil,"invalid radius accepted")
expect(Stance.leash("StandGround",120,36)==0 and Stance.leash("Defensive",120,36)==36 and Stance.leash("Aggressive",120,36)==120,"stance leash wrong")
expect(not Stance.mayChase("StandGround") and Stance.mayChase("Defensive"),"stand ground chases")

-- 羊群 ----------------------------------------------------------------------
local teams={[1]=1,[2]=1,[3]=2}
local function relation(a,b) return teams[a]==teams[b] and "ally" or "enemy" end
expect(Herd.claim(nil,{{ownerId=3,distance=9},{ownerId=1,distance=4}},relation)==1,"neutral sheep not taken by the nearest unit")
expect(Herd.claim(1,{{ownerId=3,distance=2},{ownerId=1,distance=12}},relation)==nil,"guarded sheep stolen")
expect(Herd.claim(1,{{ownerId=3,distance=2},{ownerId=2,distance=12}},relation)==nil,"ally guard ignored")
expect(Herd.claim(1,{{ownerId=3,distance=6}},relation)==3,"unguarded sheep not taken by the enemy")
expect(Herd.claim(1,{{ownerId=2,distance=6}},relation)==nil,"ally took a sheep")
expect(Herd.claim(1,{},relation)==nil and Herd.claim(nil,{},relation)==nil,"empty surroundings changed owner")
expect(Herd.claim(nil,{{ownerId=3,distance=0/0},{ownerId=3,distance=-1}},relation)==nil,"invalid distances accepted")
-- 每個出生點相對地圖中心的位置相同：四個角落得到同樣的距離分布。
local spawns={{-344,-344},{344,344},{344,-344},{-344,344}}
local reference
for _,spawn in ipairs(spawns) do
 local points=Herd.ringPoints(spawn[1],spawn[2],0,0,4,Config.Herds.sheepRing.min,Config.Herds.sheepRing.max,math.rad(40),0)
 expect(points and #points==4,"ring points missing")
 local distances={}
 for _,p in ipairs(points) do
  local fromHome=math.sqrt((p.X-spawn[1])^2+(p.Z-spawn[2])^2)
  expect(fromHome>=Config.Herds.sheepRing.min-1e-6 and fromHome<=Config.Herds.sheepRing.max+1e-6,"sheep outside its ring")
  expect(math.abs(p.X)<512 and math.abs(p.Z)<512,"sheep placed off a medium map")
  table.insert(distances,math.floor(math.sqrt(p.X^2+p.Z^2)*1000+0.5))
 end
 table.sort(distances)
 local signature=table.concat(distances,",")
 reference=reference or signature
 expect(signature==reference,"herd placement is not symmetric between spawns")
end
expect(Herd.ringPoints(0,0,0,0,-1,1,2,1)==nil and Herd.ringPoints(0,0,0,0,2,5,1,1)==nil,"invalid ring accepted")
expect(Herd.boarTarget({{key="a",distance=3,lastHit=1},{key="b",distance=2,lastHit=5}},7)=="b","boar ignored its latest attacker")
expect(Herd.boarTarget({{key="a",distance=3},{key="b",distance=9,lastHit=5}},7)=="a","boar chased an attacker beyond reach")
expect(Herd.boarTarget({{key="a",distance=9}},7)==nil,"boar hit a distant unit")
expect(Herd.boarDamage(75,3,1)==73 and Herd.boarDamage(2,30,1)==0 and Herd.boarDamage(10,1,5)==9,"boar damage wrong")
expect(Herd.boarDamage(10,0/0,1)==10,"invalid boar damage applied")

-- 戰爭迷霧 ------------------------------------------------------------------
local grid=Fog.new(256,16)
expect(grid and grid.count==16,"fog grid size wrong")
expect(Fog.cellOf(grid,-128,-128)==1 and select(2,Fog.cellOf(grid,127.9,127.9))==16 and Fog.cellOf(grid,129,0)==nil,"fog cell lookup wrong")
for row=1,16 do
 local runs=Fog.runs(grid,row)
 expect(#runs==1 and runs[1].first==1 and runs[1].last==16 and runs[1].state==0,"unexplored row not one black run")
end
local changed,discovered=Fog.update(grid,{{X=0,Z=0,radius=40}})
expect(#discovered>0,"first sight discovered nothing")
for _,index in ipairs(discovered) do
 local column,row=Fog.cellAt(grid,index)
 expect(Fog.index(grid,column,row)==index and Fog.stateAt(grid,column,row)==2,"discovered cell index round trip wrong")
end
expect(Fog.visibleAt(grid,0,0) and Fog.visibleAt(grid,30,0) and not Fog.visibleAt(grid,60,0),"vision circle wrong")
expect(changed[9] and not changed[1],"changed rows wrong")
local again,againDiscovered=Fog.update(grid,{{X=0,Z=0,radius=40}})
expect(next(again)==nil and #againDiscovered==0,"unchanged vision reported changes")
Fog.update(grid,{{X=-100,Z=-100,radius=20}})
expect(not Fog.visibleAt(grid,0,0) and Fog.exploredAt(grid,0,0),"left area did not become fog")
expect(Fog.visibleAt(grid,-100,-100),"new source not visible")
local foggy=false
for _,run in ipairs(Fog.runs(grid,9)) do if run.state==1 then foggy=true end end
expect(foggy,"explored row has no fog run")
expect(not Fog.exploredAt(grid,100,100),"unseen corner explored")
Fog.update(grid,{{X=0/0,Z=0,radius=40},{X=0,Z=0,radius=-5}})
expect(not Fog.visibleAt(grid,-100,-100),"invalid sources revealed cells")
Fog.revealAll(grid)
expect(Fog.exploredAt(grid,100,100),"reveal all missed cells")
expect(Fog.new(0,16)==nil and Fog.new(100000,1)==nil,"invalid fog grid accepted")
-- 每種單位與建築都有有效視野；前哨站看得最遠，城鎮守望增加建築視野。
for kind in pairs(Config.Units) do expect(Fog.radius(Config.Vision,kind,false,0)>0,"unit without vision "..kind) end
for kind in pairs(Config.Buildings) do expect(Fog.radius(Config.Vision,kind,true,0)>0,"building without vision "..kind) end
for kind,radius in pairs(Config.Vision.buildings) do expect(Config.Buildings[kind]~=nil and finite(radius),"vision for unknown building "..kind) end
for kind,radius in pairs(Config.Vision.units) do expect(Config.Units[kind]~=nil and finite(radius),"vision for unknown unit "..kind) end
local outpost=Fog.radius(Config.Vision,"Outpost",true,0)
for kind in pairs(Config.Buildings) do expect(Fog.radius(Config.Vision,kind,true,0)<=outpost,"outpost is not the farthest-seeing building") end
expect(Fog.radius(Config.Vision,"TownCenter",true,Config.Technologies.TownWatch.effect.buildingVision)>Fog.radius(Config.Vision,"TownCenter",true,0),"town watch has no effect")
expect(Config.Vision.cell>0 and Config.Map.Sizes.Large/Config.Vision.cell<=512,"fog grid too fine for the large map")

-- 設定完整性 ------------------------------------------------------------------
local knownEffects={hp=true,armor=true,attack=true,range=true,interval=true,speed=true,gather=true,carry=true,gatherFood=true,gatherWood=true,gatherGold=true,gatherStone=true,
 farmCapacity=true,trainSpeed=true,buildingHp=true,buildingArmor=true,buildSpeed=true,towerAttack=true,towerRange=true,buildingVision=true,garrisonHeal=true,tributeFeeCut=true}
for key,data in pairs(Config.Technologies) do
 for effect,value in pairs(data.effect or {}) do expect(knownEffects[effect] and finite(value) and value>0,"unknown or invalid effect "..key.."."..effect) end
end
for kind,data in pairs(Config.Units) do
 if data.requiresTech then expect(Config.Technologies[data.requiresTech]~=nil and Config.Technologies[data.requiresTech].minAge<=data.minAge,"unit requires an unknown or later technology "..kind) end
 if data.pierce then expect(finite(data.pierce.width) and data.pierce.width>0 and data.pierce.falloff>0 and data.pierce.falloff<=1 and data.pierce.max>=1,"invalid pierce "..kind) end
end
expect(Config.Units.sheep.population==0 and Config.Units.sheep.damage==0 and #Config.Units.sheep.trainsAt==0 and Config.Units.sheep.class=="herd","sheep must be a free, harmless, untrainable herd animal")
expect(Config.Garrison.blocked.herd==true,"sheep can garrison")
expect(Config.Resources.Sheep and Config.Resources.Sheep.resource=="food" and Config.Resources.Sheep.hunt==true,"slaughtered sheep is not food")
local boar=Config.Resources.Boar
expect(boar and boar.resource=="food" and boar.amount>Config.Resources.Deer.amount and finite(boar.boar.hp) and boar.boar.damage>0 and boar.boar.reach>0,"boar definition invalid")
expect(Config.Buildings.Palisade.line==true and Config.Buildings.Palisade.minAge==1 and Config.Buildings.Palisade.hp<Config.Buildings.Wall.hp,"palisade must be a weaker dark age line wall")
expect(Config.Buildings.Outpost.damage==nil and Config.Buildings.Outpost.minAge==1,"outpost must be an unarmed dark age building")
expect(table.find(Config.Buildings.SiegeWorkshop.trains,"scorpion") and table.find(Config.Buildings.SiegeWorkshop.trains,"bombardCannon"),"new siege units not trained at the workshop")
local herds=Config.Herds
expect(herds.startSheep>=0 and herds.claimRadius>0 and herds.sheepRing.min<=herds.sheepRing.max and herds.boarRing.min<=herds.boarRing.max,"herd configuration invalid")
print("PASS: "..checks.." market / tribute / stance / herd / boar / fog-of-war / new content checks (not Studio)")
