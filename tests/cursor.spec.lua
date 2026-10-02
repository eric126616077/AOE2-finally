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
print(string.format("PASS: %d context cursor checks",checks))
