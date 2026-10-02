local Spatial=require("../src/ServerScriptService/ServerModules/SpatialRules")
local Production=require("../src/ServerScriptService/ServerModules/ProductionRules")
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local margin=Spatial.maxHalfFootprint(Config.Buildings,Config.Map.GridSize)
expect(margin==32,"configured castle half-footprint not included in target search")
local cells=Spatial.searchCells(60,margin,64)
expect(cells==2,"tower range search did not include large target center across cell boundary")
local towerX,castleX=56,144
expect(castleX-margin-towerX<60 and math.abs(math.floor(castleX/64)-math.floor(towerX/64))<=cells,"nearby castle edge missed despite being inside tower range")
for source=-256,256,8 do
 for target=-256,256,8 do
  for _,half in ipairs({4,8,16,32}) do
   for _,radius in ipairs({0,5,60,72,75,115}) do
    local edgeDistance=math.max(0,math.abs(target-source)-half)
    if edgeDistance<=radius then
     expect(math.abs(math.floor(target/64)-math.floor(source/64))<=Spatial.searchCells(radius,margin,64),"in-range target footprint escaped center search")
    end
   end
  end
 end
end
for _,invalid in ipairs({-1,math.huge,-math.huge,0/0,"60",false}) do
 expect(not Spatial.searchCells(invalid,32,64),"invalid radius accepted")
 expect(not Spatial.searchCells(60,invalid,64),"invalid target margin accepted")
 expect(not Spatial.searchCells(60,32,invalid),"invalid cell width accepted")
end
expect(not Spatial.searchCells(1e308,1e308,64),"overflowing finite search radius accepted")
expect(not Spatial.searchCells(60,32,0),"zero cell width accepted")
expect(not Spatial.maxHalfFootprint({Bad={size={X=math.huge,Y=2}}},8),"invalid building dimensions accepted")
expect(not Spatial.maxHalfFootprint(Config.Buildings,0/0),"non-finite grid dimensions accepted")

local source,replacement,otherSource={},{},{}
local state={technologies={},pendingTech={Forging=true,Armor=true},advancing=nil}
local jobs={[source]={key="Forging",state=state},[otherSource]={key="Armor",state=state}}
expect(not Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"pending research could queue twice")
expect(not Production.cancelResearch(state,source,jobs),"ordinary technology cancellation claimed an age transition")
expect(jobs[source]==nil and not state.pendingTech.Forging,"lost source left technology permanently pending")
expect(Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"technology could not restart in replacement building after source loss")
expect(jobs[otherSource]~=nil and state.pendingTech.Armor==true,"canceling one source erased other building research")
expect(not state.technologies.Forging,"canceled research was incorrectly completed")
Production.cancelResearch(state,source,jobs)
expect(Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"one-second cleanup following production cancellation relocked technology")
jobs[replacement]={key="Forging",state=state}; state.pendingTech.Forging=true
expect(not Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"restarted research lost its reservation")
Production.cancelResearch(state,replacement,jobs)
state.advancing={building=source,age=3,remaining=20}
expect(not Production.cancelResearch(state,otherSource,jobs) and state.advancing~=nil,"wrong source canceled age advancement")
expect(Production.cancelResearch(state,source,jobs) and state.advancing==nil,"missing advancement source did not request clearing progress / remaining")
expect(not Production.cancelResearch(state,source,jobs),"duplicate age cleanup was not idempotent")
expect(not Production.canResearch({Forging=true},{},"Forging",2,2),"completed technology could be researched twice")
expect(not Production.canResearch({}, {},"Forging",1,2),"age prerequisite ignored")
expect(not Production.canResearch({}, {},"Forging",math.huge,2),"invalid research age accepted")
expect(Production.canResearch({}, {},"Forging",2,2),"normal research blocked")
-- 近戰射程必須留出站位：自己碰撞半徑 + 1.5 以上，否則走不到攻擊位置。
for kind,data in pairs(Config.Units) do
 if data.range<=20 then
  local profile=Config.UnitCollision.profiles[data.class] or Config.UnitCollision.default
  expect(data.range>=profile.radius+1.5,kind.." melee range leaves no room to stand next to the target")
  expect(data.range<=profile.radius+4,kind.." melee range strikes from farther than the weapon reaches")
 else
  expect(Config.Combat.projectile[Config.Combat.projectileKinds[kind] or "arrow"]>0,kind.." has no projectile speed")
 end
end
expect(Config.Combat.corpseSeconds==20,"corpses no longer stay for 20 seconds")
-- 防禦建築：只有城堡在射程內沒有敵方單位時改射建築；可駐紮建築的箭數上限不超過容量。
local Garrison=require("../src/ServerScriptService/ServerModules/GarrisonRules")
local Combat=require("../src/ServerScriptService/ServerModules/CombatRules")
expect(Config.Buildings.Castle.attacksBuildings==true,"castle no longer attacks enemy buildings")
for kind,data in pairs(Config.Buildings) do
 if kind~="Castle" then expect(data.attacksBuildings==nil,kind.." attacks buildings without a user decision") end
 if data.attacksBuildings then expect(type(data.damage)=="number" and data.damage>0 and data.range>0,kind.." attacks buildings without a weapon") end
 local capacity=Garrison.capacity(data)
 if data.garrison then
  expect(capacity>0 and data.damage~=nil,kind.." garrison has no capacity or no weapon to add arrows to")
  expect(data.garrison.maxArrows>=1 and data.garrison.maxArrows<=capacity,kind.." arrow cap exceeds what a full garrison can add")
 else expect(capacity==0,kind.." accepts a garrison without configuration") end
end
expect(Garrison.capacity(Config.Buildings.TownCenter)==15 and Garrison.capacity(Config.Buildings.Tower)==5 and Garrison.capacity(Config.Buildings.Castle)==20,"garrison capacities changed")
expect(not Garrison.canEnter(Config.Garrison,Config.Buildings.Tower,true,0,"cavalry",125),"cavalry enters a tower")
expect(Garrison.canEnter(Config.Garrison,Config.Buildings.Castle,true,0,"cavalry",125),"cavalry cannot enter a castle")
for _,kind in ipairs({"TownCenter","Tower","Castle"}) do expect(not Garrison.canEnter(Config.Garrison,Config.Buildings[kind],true,0,"siege",280),"siege enters "..kind) end
-- 建築目標的評分：城堡找建築時用 buildings 偏好，建築類別必須有有效分數且優於同距離的單位。
local buildingScore=Combat.targetScore(40,"building",Config.Combat.tierDistance,"buildings")
expect(buildingScore~=nil and Combat.targetScore(40,"defense",Config.Combat.tierDistance,"buildings")==buildingScore,"building targets have no score for a building-preferring attacker")
expect(buildingScore<Combat.targetScore(40,"military",Config.Combat.tierDistance,"buildings"),"building preference does not rank buildings first")
print(string.format("PASS: %d server footprint-search / production-cancellation checks",count))
