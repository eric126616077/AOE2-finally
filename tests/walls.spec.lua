local Rules=require("../src/ReplicatedStorage/Shared/WallRules")
local checks=0
local function expect(condition,message)
 checks+=1
 assert(condition,message)
end
local function keys(cells)
 local list={}
 for _,cell in ipairs(cells) do table.insert(list,cell.x..":"..cell.z) end
 return table.concat(list," ")
end

-- Footprint rotation.
do
 local x,y=Rules.footprint(3,1,false)
 expect(x==3 and y==1,"unrotated footprint changed")
 x,y=Rules.footprint(3,1,true)
 expect(x==1 and y==3,"quarter turn must swap the footprint")
 x,y=Rules.footprint(3,1,"yes")
 expect(x==3 and y==1,"only a boolean true rotates")
end

-- Lines: a single cell, straight rows in all four directions, and sealed diagonals.
expect(keys(Rules.line(4,7,4,7,40))=="4:7","a click without dragging is one segment")
expect(keys(Rules.line(0,0,4,0,40))=="0:0 1:0 2:0 3:0 4:0","row along +X")
expect(keys(Rules.line(4,0,0,0,40))=="4:0 3:0 2:0 1:0 0:0","row along -X starts at the first cell")
expect(keys(Rules.line(2,1,2,4,40))=="2:1 2:2 2:3 2:4","row along +Z")
expect(keys(Rules.line(2,4,2,1,40))=="2:4 2:3 2:2 2:1","row along -Z")
for _,goal in ipairs({{9,4},{-7,3},{5,-11},{-6,-6},{1,13},{12,12},{-3,0},{0,-8}}) do
 local cells,truncated=Rules.line(0,0,goal[1],goal[2],200)
 expect(not truncated,"an untruncated line reported truncation")
 expect(#cells==math.abs(goal[1])+math.abs(goal[2])+1,"edge-connected line has the wrong length")
 expect(cells[1].x==0 and cells[1].z==0 and cells[#cells].x==goal[1] and cells[#cells].z==goal[2],"line must join both ends")
 local seen={}
 for index,cell in ipairs(cells) do
  expect(not seen[cell.x..":"..cell.z],"line repeated a cell")
  seen[cell.x..":"..cell.z]=true
  if index>1 then
   local previous=cells[index-1]
   expect(math.abs(cell.x-previous.x)+math.abs(cell.z-previous.z)==1,"diagonal gap: neighbours must share an edge")
  end
  -- Stays within one cell of the ideal straight line.
  local length=math.sqrt(goal[1]^2+goal[2]^2)
  expect(math.abs(cell.x*goal[2]-cell.z*goal[1])/length<=1,"line strayed from the dragged direction")
 end
end
do
 local cells,truncated=Rules.line(0,0,100,0,40)
 expect(#cells==40 and truncated and cells[40].x==39,"long drags must stop at the segment limit")
 cells,truncated=Rules.line(0,0,39,0,40)
 expect(#cells==40 and not truncated,"exact limit is not a truncation")
 cells,truncated=Rules.line(3,3,9,9,1)
 expect(#cells==1 and truncated,"limit of one keeps only the start")
end
for _,bad in ipairs({0.5,0/0,math.huge,-math.huge,"1",false}) do
 expect(Rules.line(bad,0,1,1,40)==nil and Rules.line(0,bad,1,1,40)==nil
  and Rules.line(0,0,bad,1,40)==nil and Rules.line(0,0,1,bad,40)==nil,"invalid cell accepted")
end
expect(Rules.line(0,0,1,1,nil)==nil,"missing limit accepted")
for _,bad in ipairs({0,-1,1.5,0/0,math.huge,"40"}) do
 expect(Rules.line(0,0,1,1,bad)==nil,"invalid limit accepted")
end

-- Affordable segments.
expect(Rules.affordableCount({stone=150},{stone=15},40)==10,"150 stone pays for ten segments")
expect(Rules.affordableCount({stone=150},{stone=15},4)==4,"never more than requested")
expect(Rules.affordableCount({stone=14},{stone=15},4)==0,"cannot afford a single segment")
expect(Rules.affordableCount({stone=100,wood=10},{stone=15,wood=5},9)==2,"scarcest resource limits the row")
expect(Rules.affordableCount({},{stone=15},4)==0,"missing balance counts as nothing")
expect(Rules.affordableCount({stone=0},{},7)==7,"free segments are all affordable")
expect(Rules.affordableCount({stone=-5},{stone=15},4)==0 and Rules.affordableCount({stone=0/0},{stone=15},4)==0,"invalid balance accepted")
expect(Rules.affordableCount({stone=50},{stone=-1},4)==0 and Rules.affordableCount({stone=50},{stone=0/0},4)==0,"invalid cost accepted")
expect(Rules.affordableCount(nil,{stone=15},4)==0 and Rules.affordableCount({stone=50},nil,4)==0
 and Rules.affordableCount({stone=50},{stone=15},-1)==0 and Rules.affordableCount({stone=50},{stone=15},1.5)==0,"invalid arguments accepted")

-- Distance from a unit to a gate footprint (12 x 4 half extents: a gate along X).
expect(Rules.boxDistanceSquared(0,0,0,0,12,4)==0 and Rules.boxDistanceSquared(11,-3,0,0,12,4)==0,"inside the footprint is distance zero")
expect(Rules.boxDistanceSquared(15,0,0,0,12,4)==9,"distance past the end")
expect(Rules.boxDistanceSquared(0,-10,0,0,12,4)==36,"distance in front")
expect(Rules.boxDistanceSquared(15,8,0,0,12,4)==25,"corner distance")
expect(Rules.boxDistanceSquared(115,58,100,50,12,4)==25,"offset gate")

-- Segment / rectangle.
expect(Rules.segmentHitsBox(-20,0,20,0,0,0,12,4),"crossing along the length")
expect(Rules.segmentHitsBox(0,-20,0,20,0,0,12,4),"crossing through the passage")
expect(Rules.segmentHitsBox(-20,-10,20,10,0,0,12,4),"diagonal crossing")
expect(not Rules.segmentHitsBox(-20,5,20,5,0,0,12,4),"passing beside the gate")
expect(not Rules.segmentHitsBox(-20,4,20,4,0,0,12,4),"sliding exactly along the face does not enter")
expect(not Rules.segmentHitsBox(0,-20,0,-5,0,0,12,4),"stopping short")
expect(Rules.segmentHitsBox(0,-20,0,-3.9,0,0,12,4),"ending just inside")
expect(Rules.segmentHitsBox(0,0,0,0,0,0,12,4),"point inside")
expect(not Rules.segmentHitsBox(13,0,13,0,0,0,12,4),"point outside")
expect(not Rules.segmentHitsBox(13,-20,13,20,0,0,12,4),"parallel miss past the end")
expect(not Rules.segmentHitsBox(-20,-20,-13,20,0,0,12,4),"steep miss")
expect(not Rules.segmentHitsBox(0/0,0,1,1,0,0,12,4) and not Rules.segmentHitsBox(0,0,1,1,0,0,0,4),"invalid geometry must not block")

-- Hostile movement bodies (radius 2) against a gate along X at the origin.
expect(Rules.gateBlocks(0,-20,0,20,2,0,0,12,4),"enemy cannot walk through the passage")
expect(Rules.gateBlocks(0,-20,0,-5,2,0,0,12,4),"enemy body may not overlap the gate face")
expect(not Rules.gateBlocks(0,-20,0,-6,2,0,0,12,4),"enemy may stand touching the gate to attack it")
expect(not Rules.gateBlocks(-20,-6,20,-6,2,0,0,12,4),"enemy may walk along the outside of the gate")
expect(Rules.gateBlocks(-20,-5,20,-5,2,0,0,12,4),"enemy may not scrape through the face")
expect(not Rules.gateBlocks(14,-20,14,20,2,0,0,12,4),"enemy may pass beyond the end of the gate")
expect(Rules.gateBlocks(13,-20,13,20,2,0,0,12,4),"enemy body may not clip the end of the gate")
expect(Rules.gateBlocks(3,1,3,1,2,0,0,12,4),"a spot inside a gate is not a standing position")
expect(not Rules.gateBlocks(30,30,30,30,2,0,0,12,4),"a spot away from the gate is free")
expect(not Rules.gateBlocks(3,1,3,20,2,0,0,12,4),"a body already inside may leave")
expect(Rules.gateBlocks(0,-20,0,20,4,0,0,12,4) and not Rules.gateBlocks(0,-20,0,-8,4,0,0,12,4)
 and Rules.gateBlocks(0,-20,0,-7,4,0,0,12,4),"siege radius uses its own body size")
-- A quarter-turned gate swaps its half extents.
expect(Rules.gateBlocks(-20,0,20,0,2,0,0,4,12) and not Rules.gateBlocks(-20,14,20,14,2,0,0,4,12),"rotated gate")
for _,bad in ipairs({0,-1,0/0,math.huge,"2"}) do
 expect(not Rules.gateBlocks(0,-20,0,20,bad,0,0,12,4),"invalid radius must not block")
end
print(string.format("PASS: %d wall line / segment budget / gate passage geometry checks",checks))
