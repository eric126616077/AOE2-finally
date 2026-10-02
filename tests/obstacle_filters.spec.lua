-- Requires actual filter source sections between this spec and obstacle_filters.mocks.lua.
-- No duplicated implementation: exercise query outcomes, cache identities, and invalidation.
updateObstacleFilters()
expect(rayParams.RespectCanCollide==true and attackOverlap.RespectCanCollide==true,
 "movement/attack probes stopped respecting gameplay collisions")
expect(overlap.RespectCanCollide==false,"placement stopped considering queryable unit/resource geometry")
expect(contains(query(rayParams),userWall),"user wall in an unknown RTSScenery folder escaped movement collision")
expect(contains(query(attackOverlap),userWall),"same-name user scenery escaped interaction collision")
expect(contains(query(overlap),userWall),"same-name user scenery escaped server building occupancy")
expect(not contains(query(rayParams),unitCollider),"movement query began blocking against the excluded Units folder")
expect(not contains(query(attackOverlap),unitCollider),"interaction query began blocking against Units")
expect(contains(query(overlap),unitCollider),"placement excluded units and allowed building through them")
expect(not contains(query(rayParams),generatedRoad) and not contains(query(overlap),generatedRoad),
 "non-queryable, non-collidable generated scenery became an obstacle")
expect(not contains(query(rayParams),originalGround) and not contains(query(overlap),originalGround),
 "ground became a movement or placement obstacle")
expect(not contains(query(rayParams),visualOnly),"movement began treating non-collidable decoration as a wall")

local moveFilter,attackFilter,placementFilter=rayParams.FilterDescendantsInstances,attackOverlap.FilterDescendantsInstances,overlap.FilterDescendantsInstances
for _=1,100 do updateObstacleFilters() end
expect(rayParams.FilterDescendantsInstances==moveFilter and attackOverlap.FilterDescendantsInstances==attackFilter
 and overlap.FilterDescendantsInstances==placementFilter,"unchanged scene rebuilt cached filter arrays")
expect(rayParams.filterWrites==1 and attackOverlap.filterWrites==1 and overlap.filterWrites==1,
 "unchanged scene repeatedly wrote engine filter properties")

-- Adding or replacing unrelated user scenery must affect queries immediately without cache churn.
local replacementScenery=node("RTSScenery",workspace)
workspace.children.RTSScenery=replacementScenery
local replacementWall=node("ReplacementWall",replacementScenery,true,true)
table.insert(testParts,replacementWall)
updateObstacleFilters()
expect(contains(query(rayParams),replacementWall) and contains(query(overlap),replacementWall),
 "new unknown same-name scenery failed to block movement/placement")
expect(rayParams.filterWrites==1 and attackOverlap.filterWrites==1 and overlap.filterWrites==1,
 "unrelated same-name scenery replacement invalidated ground-only filter cache")

-- A replaced ground must exclude the new object and stop hiding the old one.
local nextGround=node("AOE2_Ground",workspace,true,true)
workspace.children.AOE2_Ground=nextGround
table.insert(testParts,nextGround)
updateObstacleFilters()
expect(rayParams.filterWrites==2 and attackOverlap.filterWrites==2 and overlap.filterWrites==2,
 "replacing the actual ground did not rebuild all query filters once")
expect(not contains(query(rayParams),nextGround) and not contains(query(overlap),nextGround),
 "replacement ground was not excluded")
expect(contains(query(rayParams),originalGround) and contains(query(overlap),originalGround),
 "old ground reference remained hidden after replacement")
expect(contains(query(rayParams),userWall) and contains(query(overlap),unitCollider),
 "ground replacement changed unknown scenery or placement unit policy")
updateObstacleFilters()
expect(rayParams.filterWrites==2 and overlap.filterWrites==2,"stable replacement ground churned filters")

workspace.children.AOE2_Ground=nil
updateObstacleFilters()
expect(rayParams.filterWrites==3 and attackOverlap.filterWrites==3 and overlap.filterWrites==3,
 "ground removal did not invalidate all query filters")
expect(contains(query(rayParams),nextGround) and contains(query(overlap),nextGround),
 "removed ground remained accidentally excluded")
expect(#rayParams.FilterDescendantsInstances==1 and rayParams.FilterDescendantsInstances[1]==units
 and #overlap.FilterDescendantsInstances==0,"no-ground fallback lost movement Units or placement occupancy policy")
updateObstacleFilters()
expect(rayParams.filterWrites==3 and overlap.filterWrites==3,"missing ground recreated filters every tick")

-- The actual preview section must match server obstacle policy while hiding its local ghosts.
workspace.children.AOE2_Ground=nextGround
local previewParams=previewObstacleFilters(preview,ghost)
expect(not contains(query(previewParams),preview) and not contains(query(previewParams),ghostPart),
 "client preview obstructed itself with preview geometry")
expect(not contains(query(previewParams),nextGround),"client preview treated actual ground as occupied")
expect(contains(query(previewParams),userWall) and contains(query(previewParams),replacementWall),
 "client preview hid walls in unknown same-name scenery folders")
expect(contains(query(previewParams),unitCollider),"client preview stopped considering units as occupied")
expect(not contains(query(previewParams),generatedRoad),"client preview treated generated scenery as occupied")
print(string.format("PASS: %d actual server/preview obstacle-filter collision and cache checks",checks))
