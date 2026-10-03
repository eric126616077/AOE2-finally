local FormationRules=require("../src/ReplicatedStorage/Shared/FormationRules")
local UnitCollisionRules=require("../src/ServerScriptService/ServerModules/UnitCollisionRules")
local checks=0
local function expect(value,message) checks+=1; assert(value,message) end
local function near(value,target) return math.abs(value-target)<1e-6 end
local config={default="Box",maxSelectedUnits=200,gap=.5,arrivalTolerance=.1,spreadMultiplier=1.8,obstacleSearchRings=4,
 types={Box={},Line={},Column={},Wedge={},Spread={}}}
local keys={"Box","Line","Column","Wedge","Spread"}
local own,other={},{}
local function owned(value) return value==own end
expect(FormationRules.selection({own},200,owned)[1]==own,"one owned unit accepted")
for _,selection in ipairs({{}, {own,own}, {own,other}, {[1]=own,[3]=other}, {[0]=own}, {named=own}, {[1]=own,extra=true}}) do
 expect(FormationRules.selection(selection,200,owned)==nil,"entire malformed / mixed-owner selection rejected")
end
expect(FormationRules.selection({own},200,function() error("deleted instance") end)==nil,"eligibility failures reject batch")
expect(FormationRules.selection({own},200,function() return 1 end)==nil,"eligibility must return true")
expect(FormationRules.selection({0/0},200,function() return true end)==nil,"NaN key fails closed")
local many={}
for i=1,200 do many[i]={} end
expect(#FormationRules.selection(many,200,function() return true end)==200,"selection cap accepted")
many[201]={}
expect(FormationRules.selection(many,200,function() return true end)==nil,"selection cap enforced")
for _,key in ipairs({"", "line", "Circle", false, {}, 0, math.huge}) do
 expect(not FormationRules.validKey(config,key),"unsupported key rejected")
end
for _,key in ipairs(keys) do
 expect(FormationRules.validKey(config,key),"supported key accepted")
 for _,count in ipairs({1,2,3,4,7,12,27,200}) do
  local slots=assert(FormationRules.layout(key,count,8.5,80))
  local sumX,sumZ=0,0
  expect(#slots==count,"one slot per unit")
  for _,slot in ipairs(slots) do sumX+=slot.X; sumZ+=slot.Z end
  expect(near(sumX,0) and near(sumZ,0),"layout centroid stays on target including partial rows")
 end
end
local function span(slots,axis)
 local low,high=math.huge,-math.huge
 for _,slot in ipairs(slots) do low=math.min(low,slot[axis]); high=math.max(high,slot[axis]) end
 return high-low
end
expect(near(span(FormationRules.layout("Line",12,8.5),"Z"),0),"line is perpendicular to facing")
expect(near(span(FormationRules.layout("Column",12,8.5),"X"),0),"column follows facing")
local wedge=FormationRules.layout("Wedge",16,8.5)
expect(wedge[1].Z>wedge[2].Z and near(wedge[1].X,0),"wedge tip leads wide rear ranks")
for _,count in ipairs({0,-1,1.5,201,math.huge,0/0}) do expect(FormationRules.layout("Box",count,8.5)==nil,"invalid slot count") end
for _,spacing in ipairs({0,-1,math.huge,0/0}) do expect(FormationRules.layout("Box",12,spacing)==nil,"invalid spacing") end

local records={}
for i=1,200 do records[i]={X=(i%15)*9-63,Z=math.floor(i/15)*9-63,radius=i%4==0 and 4 or 2} end
for _,key in ipairs(keys) do
 for _,target in ipairs({{X=370,Z=370},{X=-370,Z=370},{X=-370,Z=-370},{X=370,Z=0},{X=0,Z=-370}}) do
  local plan=assert(FormationRules.plan(config,key,records,target,381))
  expect(#plan.slots==200 and #plan.assignment==200,"full formation batch planned")
  local assigned={}
  for index,slot in ipairs(plan.slots) do
   expect(math.abs(slot.X)+4<=381+1e-6 and math.abs(slot.Z)+4<=381+1e-6,"whole rotated formation stays inside map")
   expect(not assigned[plan.assignment[index]],"assignment uses each slot once")
   assigned[plan.assignment[index]]=true
   for otherIndex=index+1,#plan.slots do
    local otherSlot=plan.slots[otherIndex]
    local dx,dz=slot.X-otherSlot.X,slot.Z-otherSlot.Z
    expect(dx*dx+dz*dz>=(8.5-1e-6)^2,"largest colliders retain gap without edge-clamp overlap")
   end
  end
 end
end
local stationary={{X=-8.5,Z=0,radius=2},{X=0,Z=0,radius=4},{X=8.5,Z=0,radius=2}}
local forward=assert(FormationRules.plan(config,"Line",stationary,{X=0,Z=0},381,{X=1,Z=0}))
expect(near(forward.forwardX,1) and near(forward.forwardZ,0),"regroup retains stored orientation")
local south=assert(FormationRules.plan(config,"Line",stationary,{X=0,Z=100},381,{X=1,Z=0}))
expect(near(south.forwardX,0) and near(south.forwardZ,1),"ground move turns formation toward target")
expect(near(span(south.slots,"Z"),0),"turned line remains perpendicular to move")
local box=assert(FormationRules.plan(config,"Box",stationary,{X=0,Z=100},381))
local spread=assert(FormationRules.plan(config,"Spread",stationary,{X=0,Z=100},381))
expect(near(spread.spacing,box.spacing*1.8),"spread uses larger max-radius spacing")
expect(config.gap-config.arrivalTolerance*2>UnitCollisionRules.MIN_GAP,"two arrived units at opposite error limits cannot overlap each other's target")
local reorder={{X=8.5,Z=0},{X=-8.5,Z=0},{X=0,Z=0}}
local destinations={{X=-8.5,Z=20},{X=0,Z=20},{X=8.5,Z=20}}
local assignment=assert(FormationRules.assign(reorder,destinations,0,1))
expect(assignment[1]==3 and assignment[2]==1 and assignment[3]==2,"reversed selection preserves lateral positions without crossing")
local again=assert(FormationRules.assign(reorder,destinations,0,1))
for i=1,3 do expect(again[i]==assignment[i],"assignment deterministic") end
for _,target in ipairs({{X=math.huge,Z=0},{X=0/0,Z=0},{X=0,Z=-math.huge}}) do
 expect(FormationRules.plan(config,"Box",stationary,target,381)==nil,"nonfinite target rejected")
end
expect(FormationRules.plan(config,"Box",{{X=0,Z=0,radius=0}}, {X=0,Z=0},381)==nil,"invalid collider rejected")
expect(FormationRules.plan(config,"Box",stationary,{X=0,Z=0},1)==nil,"unfit formation rejected")
expect(FormationRules.plan(config,"Box",stationary,{X=0,Z=0},381,{X=0/0,Z=0})==nil,"nonfinite facing rejected")

-- verify.ps1 injects the actual server handler body here, with only engine services mocked.
local Config={Formations=config,Map={GroundY=0,MapSize=768},UnitCollision={default={radius=2}}}
local MAX_UNIT_RADIUS=4
local units,buildings,construction={},{},{}
local state={id=7}
local orders,notices={},{}
local holds={}
local AutoWork={units={},hold=function(unit) holds[unit]=true end,
 isFarm=function() return false end,farmFree=function() return true end,claimFarm=function() return false end,reseed=function() return false end}
-- Monk handlers are defined inside the extracted order body; formation checks never select monks.
local Monk={}
-- 聖物與貿易的實作不在陣形指令範圍；指令分派只需要判斷「不是聖物」。
local Relic={isRelic=function() return false end,trade={}}
-- Garrison rules live outside the extracted body; these checks never target a garrisonable building.
local Garrison={order=function() return false end}
local mode,externalNeighbors="clear",{}
local function model(x,z,ownerId,radius)
 local value={X=x,Z=z,Parent=units,attributes={OwnerId=ownerId,HP=40,Radius=radius or 2,UnitType="villager",Formation="Box",FormationForwardX=0,FormationForwardZ=-1}}
 function value:GetAttribute(key) return self.attributes[key] end
 function value:SetAttribute(key,data) self.attributes[key]=data end
 return value
end
local function isOwned(_state,unit,parent) return type(unit)=="table" and unit.Parent==parent and unit:GetAttribute("OwnerId")==_state.id end
local Rules={finite=function(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end}
local function validPosition(value) return type(value)=="table" and Rules.finite(value.X) and Rules.finite(value.Z) and math.abs(value.X)<=381 and math.abs(value.Z)<=381 end
local function position(unit) return {X=unit.X,Z=unit.Z} end
local Vector3={new=function(x,y,z) return {X=x,Y=y,Z=z} end}
local workspace={GetAttribute=function() return 768 end}
local function staticUnitSegmentClear(_unit,_from,goal) return mode~="blocked" and validPosition(goal) and (mode~="centerBlocked" or math.abs(goal.X)>2 or math.abs(goal.Z)>2) end
local function unitNeighbors() return externalNeighbors end
local function notify(_actor,message,event) table.insert(notices,{message,event}) end
local function isTarget(target) return type(target)=="table" and target.targetModel==true end
local function owner(target) return target.enemy and {enemy=true} or state end
local function enemies(_state,victim) return victim and victim.enemy==true end
local function canBuildWorker(_state,unit) return unit:GetAttribute("UnitType")=="villager" end
local stop,issue
issue=function(unit,kind,target) orders[unit]={kind=kind,target=target}; unit:SetAttribute("FormationSlot",kind=="move" and target or nil) end
local function beginDelivery(_state,unit,target) issue(unit,"deliver",target) end
local function acceptsResource() return true end
local runServerChecks=false
-- Engine boundary: server appearance alignment is a ModelFactory concern.
local Factory={syncAppearance=function() return false end}
-- ACTUAL_SERVER_ORDER_STATE_BODY
-- ACTUAL_SERVER_FORMATION_BODY
if runServerChecks then
 local a,b=model(-4,0,7),model(4,0,7)
 local hostile=model(0,0,8)
 acceptFormation(state,{a,b},"Line")
 expect(a:GetAttribute("Formation")=="Line" and b:GetAttribute("Formation")=="Line","actual Formation updates all owned units")
 expect(orders[a].kind=="move" and orders[b].kind=="move","actual Formation immediately regroups")
 expect(holds[a] and holds[b],"player-directed formation move keeps villagers on hold instead of auto-working")
 local arrivedSlot=a:GetAttribute("FormationSlot")
 stop(a,true)
 expect(orders[a]==nil and a:GetAttribute("FormationSlot")==arrivedSlot,"actual arrived stop preserves destination evidence")
 stop(a)
 expect(a:GetAttribute("FormationSlot")==nil and a:GetAttribute("Formation")=="Line","actual explicit Stop clears target while retaining preference")
 acceptFormation(state,{a,b},"Line")
 local originalA,originalB=orders[a],orders[b]
 for _,selection in ipairs({{a,a},{a,hostile},{[1]=a,[3]=b},{[1]=a,extra=true},{}}) do
  acceptFormation(state,selection,"Spread")
  acceptOrder(state,selection,{X=100,Z=100},"Spread")
  expect(orders[a]==originalA and orders[b]==originalB and a:GetAttribute("Formation")=="Line","actual malformed whole batch changes no command / formation")
 end
 for _,key in ipairs({"Circle",false,{},math.huge}) do
  acceptFormation(state,{a,b},key)
  acceptOrder(state,{a,b},{X=100,Z=100},key)
  expect(orders[a]==originalA and orders[b]==originalB,"actual malformed key has no mutation")
 end
 mode="blocked"
 acceptFormation(state,{a,b},"Spread")
 expect(orders[a]==originalA and orders[b]==originalB and b:GetAttribute("Formation")=="Line","no partial commands when all nearby positions blocked")
 mode="clear"
 b:SetAttribute("Formation","Column")
 acceptOrder(state,{a,b},{X=375,Z=375})
 expect(a:GetAttribute("Formation")=="Line" and b:GetAttribute("Formation")=="Line","first selected unit chooses remembered formation")
 expect(a:GetAttribute("FormationForwardX")>0 and a:GetAttribute("FormationForwardZ")>0,"actual ground move rotates toward destination")
 for _,unit in ipairs({a,b}) do
  local goal=orders[unit].target
  expect(math.abs(goal.X)+2<=381 and math.abs(goal.Z)+2<=381,"actual entire edge formation kept within bounds")
 end
 local previousA,previousB=orders[a],orders[b]
 acceptOrder(state,{a,b},{X=0/0,Z=100},"Column")
 expect(orders[a]==previousA and orders[b]==previousB,"actual nonfinite target rejected")
 a:SetAttribute("HP",0)
 acceptFormation(state,{a,b},"Column")
 expect(orders[a]==previousA and orders[b]==previousB,"dead selected unit causes atomic rejection")
 a:SetAttribute("HP",40)
 mode="centerBlocked"
 acceptOrder(state,{a},{X=0,Z=0},"Box")
 expect(orders[a]~=previousA and (math.abs(orders[a].target.X)>2 or math.abs(orders[a].target.Z)>2),"blocked endpoint finds nearby safe slot")
 mode="clear"
 externalNeighbors={{key=hostile,X=100,Z=100,radius=2}}
 acceptOrder(state,{a},{X=100,Z=100},"Box")
 expect(not UnitCollisionRules.overlaps(orders[a].target.X,orders[a].target.Z,2,externalNeighbors),"external unit collision shifts endpoint")
 externalNeighbors={}
 local enemyTarget={targetModel=true,enemy=true,GetAttribute=function() return nil end}
 acceptOrder(state,{a,b},enemyTarget)
 expect(orders[a].kind=="attack" and orders[b].kind=="attack","target-model attack keeps existing behavior")
 expect(a:GetAttribute("FormationSlot")==nil and a:GetAttribute("Formation")=="Box","target attack clears slot while retaining formation")
 local resourceTarget={targetModel=true,GetAttribute=function(_,key) return ({ResourceType="wood",Amount=10})[key] end}
 acceptOrder(state,{a,b},resourceTarget)
 expect(orders[a].kind=="gather" and orders[b].kind=="gather","target-model gather remains available after formations")
 local buildTarget=model(0,0,7)
 buildTarget.targetModel,buildTarget.Parent=true,buildings
 buildTarget:SetAttribute("Complete",false)
 construction[buildTarget]={}
 acceptOrder(state,{a,b},buildTarget)
 expect(orders[a].kind=="build" and orders[b].kind=="build","target-model construction remains available after formations")
end
print("Formation geometry / authoritative commands:",checks,"checks passed")
