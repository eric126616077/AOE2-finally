local CursorRules=require("../src/ReplicatedStorage/Shared/CursorRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function resolve(ctx)
 local kind=CursorRules.Resolve(ctx)
 expect(CursorRules.Kinds[kind]==true,"unknown cursor kind "..tostring(kind))
 return kind
end
local function ctx(fields)
 local value={active=true,villagers=0,military=0}
 for key,item in pairs(fields or {}) do value[key]=item end
 return value
end
local enemyUnit={relation="enemy",unit=true}
local enemyBuilding={relation="enemy",building=true}
local tree={relation="neutral",resource="wood"}
local gold={relation="neutral",resource="gold"}
local stone={relation="neutral",resource="stone"}
local berries={relation="neutral",resource="food"}
local ownSite={relation="own",building=true,complete=false}
local ownDamaged={relation="own",building=true,complete=true,damaged=true}
local ownHealthy={relation="own",building=true,complete=true,damaged=false}
local ownFarmSite={relation="own",building=true,resource="food",complete=false}
local ownFarm={relation="own",building=true,resource="food",complete=true}
local enemyFarm={relation="enemy",building=true,resource="food",complete=true}
local ally={relation="ally",unit=true}
-- Inactive, touch and malformed contexts leave the system pointer alone.
for _,value in ipairs({nil,false,"x",{},{active=false},{active=true,touch=true}}) do expect(resolve(value)=="none","inactive context changed cursor") end
-- UI always wins: buttons get the plain pointer, never an action badge.
expect(resolve(ctx({overUI=true,villagers=3,target=enemyUnit}))=="default","UI hover showed an action")
-- Placement previews mirror the build validity check.
expect(resolve(ctx({placing=true,placementValid=true}))=="build" and resolve(ctx({placing=true,placementValid=false}))=="invalid","placement cursor")
-- Rally placement: ground or neutral/own resources only.
expect(resolve(ctx({rally=true}))=="rally" and resolve(ctx({rally=true,target=tree}))=="rally" and resolve(ctx({rally=true,target=ownFarm}))=="rally","rally targets")
expect(resolve(ctx({rally=true,target=enemyUnit}))=="invalid" and resolve(ctx({rally=true,target=ally}))=="invalid" and resolve(ctx({rally=true,target=ownHealthy}))=="invalid","rally refused targets")
-- Nothing of yours selected: hovering anything is a selection.
expect(resolve(ctx({target=enemyUnit}))=="select" and resolve(ctx())=="default","no-selection cursor")
-- Villagers: AOE tool cursors per resource, build and repair on own buildings.
local v=function(target) return resolve(ctx({villagers=2,target=target})) end
expect(v(tree)=="gather_wood" and v(gold)=="gather_gold" and v(stone)=="gather_stone" and v(berries)=="gather_food","villager gather cursors")
expect(v(ownSite)=="build" and v(ownDamaged)=="repair" and v(ownHealthy)=="select","villager construction cursors")
expect(v(ownFarmSite)=="build" and v(ownFarm)=="gather_food","farm site builds before it farms")
expect(v(enemyFarm)=="attack","enemy farm is an attack target")
expect(v(enemyUnit)=="attack" and v(enemyBuilding)=="attack" and v(nil)=="move" and v(ally)=="select","villager combat/move cursors")
expect(v({relation="unresolved",unit=true})=="default","unresolved owner guessed as hostile")
-- Military only: no tool cursors, resources are just a move destination.
local m=function(target) return resolve(ctx({military=4,target=target})) end
expect(m(tree)=="move" and m(enemyUnit)=="attack" and m(ownSite)=="select" and m(ownDamaged)=="select" and m(nil)=="move","military cursors")
-- Mixed selection keeps villager work cursors.
expect(resolve(ctx({villagers=1,military=5,target=gold}))=="gather_gold","mixed selection lost gather cursor")
-- Monks: convert enemy units, heal own wounded units, cannot target enemy buildings alone.
local ownWounded={relation="own",unit=true,damaged=true}
local ownFresh={relation="own",unit=true,damaged=false}
expect(resolve(ctx({military=2,monks=2,target=enemyUnit}))=="attack","monk conversion cursor")
expect(resolve(ctx({military=2,monks=2,target=enemyBuilding}))=="invalid","monk-only selection showed attack on a building")
expect(resolve(ctx({military=3,monks=1,target=enemyBuilding}))=="attack","mixed monk army lost building attack cursor")
expect(resolve(ctx({military=1,monks=1,target=ownWounded}))=="repair","monk heal cursor")
expect(resolve(ctx({military=1,monks=1,target=ownFresh}))=="select","healthy own unit showed heal cursor")
expect(resolve(ctx({military=2,target=ownWounded}))=="select","non-monk army showed heal cursor")
expect(resolve(ctx({military=1,monks=9,target=enemyUnit}))=="attack","monk count above military was not clamped")
-- Garrison targeting: only an own finished building that accepts a garrison is valid.
local ownKeep={relation="own",building=true,complete=true,damaged=false,garrison=true}
expect(resolve(ctx({garrison=true,military=2,target=ownKeep}))=="select","garrison target cursor")
expect(resolve(ctx({garrison=true,military=2}))=="invalid" and resolve(ctx({garrison=true,villagers=1,target=ownHealthy}))=="invalid"
 and resolve(ctx({garrison=true,military=2,target=enemyBuilding}))=="invalid","garrison refused targets")
-- 聖物：只有未攜帶聖物的僧侶顯示拾取；攜帶者指向自己的修道院顯示存放。貿易車指向己方／盟友市集顯示貿易。
local relic={relation="neutral",relic=true}
local ownMonastery={relation="own",building=true,complete=true,damaged=false,monastery=true}
local allyMarket={relation="ally",building=true,complete=true,market=true}
local ownMarket={relation="own",building=true,complete=true,market=true}
local enemyMarket={relation="enemy",building=true,complete=true,market=true}
expect(resolve(ctx({military=1,monks=1,target=relic}))=="relic","monk relic pickup cursor")
expect(resolve(ctx({military=1,monks=1,relicCarriers=1,target=relic}))=="invalid","carrier shown pickup on another relic")
expect(resolve(ctx({military=2,target=relic}))=="invalid" and resolve(ctx({villagers=2,target=relic}))=="invalid","non-monks shown relic pickup")
expect(resolve(ctx({military=1,monks=1,relicCarriers=1,target=ownMonastery}))=="relic","relic store cursor")
expect(resolve(ctx({military=1,monks=1,target=ownMonastery}))=="select","monk without relic shown store cursor")
expect(resolve(ctx({military=1,traders=1,target=allyMarket}))=="trade" and resolve(ctx({military=1,traders=1,target=ownMarket}))=="trade","trade cursor")
expect(resolve(ctx({military=2,traders=1,target=enemyMarket}))=="attack","mixed army lost attack cursor on an enemy market")
expect(resolve(ctx({military=1,traders=1,target=enemyMarket}))=="invalid" and resolve(ctx({military=1,traders=1,target=enemyUnit}))=="invalid","trade-cart-only selection showed attack")
expect(resolve(ctx({military=2,target=allyMarket}))=="select","non-traders shown trade cursor")
expect(resolve(ctx({military=1,monks=1,relicCarriers=5,traders=9,target=relic}))=="invalid","counts were not clamped to the selection")
print(string.format("PASS: %d context cursor checks",checks))
