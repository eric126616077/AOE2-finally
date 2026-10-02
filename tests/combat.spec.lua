local CombatRules=require("../src/ServerScriptService/ServerModules/CombatRules")
local SpatialRules=require("../src/ServerScriptService/ServerModules/SpatialRules")
local checks=0
local function expect(ok,message)
 checks+=1
 assert(ok,message)
end

expect(CombatRules.acquisitionRadius(72,5)==72,"melee unit lost its normal acquisition radius")
expect(CombatRules.acquisitionRadius(72,48)==72,"archer lost its normal acquisition radius")
expect(CombatRules.acquisitionRadius(72,115)==115,"trebuchet cannot acquire enemies already inside its attack range")
expect(CombatRules.acquisitionRadius(72,123)==123,"upgraded attack range was ignored by acquisition")
expect(CombatRules.acquisitionRadius(0,0)==0,"zero-radius query was rejected")
for _,invalid in ipairs({-1,math.huge,-math.huge,0/0,"72",false}) do
 expect(CombatRules.acquisitionRadius(invalid,115)==nil,"invalid base acquisition radius accepted")
 expect(CombatRules.acquisitionRadius(72,invalid)==nil,"invalid attack range accepted")
end
expect(CombatRules.acquisitionRadius(nil,115)==nil,"missing base radius accepted")
expect(CombatRules.acquisitionRadius(72,nil)==nil,"missing attack range accepted")

-- 接在真正的空間查詢規則上：大建築的中心可超出射程，但近側邊緣仍在射程內。
local radius=CombatRules.acquisitionRadius(72,115)
local cells=SpatialRules.searchCells(radius,32,64)
local attackerX,targetX=63,192
expect(targetX-32-attackerX<=radius,"spatial regression fixture is outside the attack range")
expect(math.abs(math.floor(targetX/64)-math.floor(attackerX/64))<=cells,"long-range acquisition missed a target footprint across three spatial cells")

expect(CombatRules.areEnemies(100,200,true,true),"living opposing players are not enemies")
expect(CombatRules.areEnemies(100,-100,true,true),"player and AI faction are not enemies")
expect(CombatRules.areEnemies(-1,-2,true,true),"Studio player IDs were rejected")
expect(not CombatRules.areEnemies(100,100,true,true),"same owner was treated as an enemy")
expect(not CombatRules.areEnemies(100,200,false,true),"defeated attacker was treated as active")
expect(not CombatRules.areEnemies(100,200,true,false),"defeated victim was treated as active")
expect(not CombatRules.areEnemies(100,200,nil,true),"missing attacker state was treated as active")
expect(not CombatRules.areEnemies(100,200,true,nil),"missing victim state was treated as active")
for _,invalid in ipairs({math.huge,-math.huge,0/0,"100",false}) do
 expect(not CombatRules.areEnemies(invalid,200,true,true),"invalid attacker ownership accepted")
 expect(not CombatRules.areEnemies(100,invalid,true,true),"invalid victim ownership accepted")
end
expect(not CombatRules.areEnemies(nil,200,true,true),"ownerless attacker was treated as an enemy")
expect(not CombatRules.areEnemies(100,nil,true,true),"ownerless target was treated as an enemy")

expect(CombatRules.canRetaliate(nil,true),"idle unit cannot counterattack a valid enemy")
expect(CombatRules.canRetaliate("gather",true),"gathering worker cannot counterattack a valid enemy")
for _,order in ipairs({"move","deliver","build","repair","attack","unknown"}) do
 expect(not CombatRules.canRetaliate(order,true),"counterattack replaced an explicit existing order: "..order)
end
expect(not CombatRules.canRetaliate(nil,false),"friendly attack caused retaliation")
expect(not CombatRules.canRetaliate("gather",nil),"invalid attacker caused worker retaliation")
expect(not CombatRules.canRetaliate("gather",true,true,true),"tower fire pulled a gathering villager off work")
expect(not CombatRules.canRetaliate(nil,true,true,true),"idle villager walked into a defensive building")
expect(CombatRules.canRetaliate(nil,true,true,false),"idle soldier ignored a building shooting it")
expect(CombatRules.canRetaliate("gather",true,false,true),"villager lost unit retaliation")

-- 目標優先：一般部隊先打軍隊，攻城武器先打建築。
local tier=40
local soldierFar=CombatRules.targetScore(70,"military",tier)
expect(soldierFar<CombatRules.targetScore(0,"building",tier),"adjacent house outranked a soldier inside acquisition range")
expect(soldierFar<CombatRules.targetScore(25,"defense",tier),"nearby tower outranked a distant soldier")
expect(CombatRules.targetScore(10,"villager",tier)<soldierFar,"adjacent villager lost to a soldier at the edge of sight")
expect(CombatRules.targetScore(5,"military",tier)<CombatRules.targetScore(5,"villager",tier),"same-distance soldier lost to a villager")
expect(CombatRules.targetScore(60,"building",tier,"buildings")<CombatRules.targetScore(5,"military",tier,"buildings"),"ram preferred a soldier over a building")
expect(CombatRules.targetScore(0,"military",0)==0,"zero tier distance changed plain distance")
for _,invalid in ipairs({-1,math.huge,0/0,"5",false}) do
 expect(CombatRules.targetScore(invalid,"military",tier)==nil,"invalid target distance accepted")
 expect(CombatRules.targetScore(5,"military",invalid)==nil,"invalid tier distance accepted")
end
expect(CombatRules.targetScore(5,"resource",tier)==nil,"unknown target category accepted")
expect(CombatRules.targetScore(5,"military",tier,"everything")==nil,"unknown preference accepted")

-- 換目標遲滯：新目標要明顯更好才換，避免兩個距離相近的敵人造成來回重新尋路。
expect(CombatRules.shouldSwitch(nil,30,12),"invalid current target was kept")
expect(CombatRules.shouldSwitch(0/0,30,12),"NaN current score was kept")
expect(not CombatRules.shouldSwitch(30,25,12),"near tie caused a retarget")
expect(not CombatRules.shouldSwitch(30,18,12),"exact margin caused a retarget")
expect(CombatRules.shouldSwitch(30,17.9,12),"clearly better target was ignored")
expect(CombatRules.shouldSwitch(200,40,12),"distant raid objective kept over an engaged enemy")
expect(not CombatRules.shouldSwitch(30,nil,12),"missing candidate caused a retarget")
expect(not CombatRules.shouldSwitch(30,10,-1),"negative margin accepted")

-- 自動追擊上限只看水平距離。
expect(not CombatRules.beyondLeash(0,0,84,84,120),"unit inside leash was recalled")
expect(CombatRules.beyondLeash(0,0,90,90,120),"unit beyond leash kept chasing")
expect(not CombatRules.beyondLeash(0,0,120,0,120),"leash boundary recalled the unit")
for _,invalid in ipairs({math.huge,0/0,"1",false}) do
 expect(not CombatRules.beyondLeash(invalid,0,500,0,120),"invalid anchor recalled the unit")
 expect(not CombatRules.beyondLeash(0,0,500,0,invalid),"invalid leash recalled the unit")
end
print(string.format("PASS: %d combat acquisition / ownership / retaliation / priority / leash checks",checks))
