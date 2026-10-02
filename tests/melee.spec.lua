local MeleeRules=require("../src/ServerScriptService/ServerModules/MeleeRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function close(a,b) return math.abs(a-b)<0.000001 end
local function edgeDistance(point,cx,cz,hx,hz)
 local dx=math.max(0,math.abs(point.X-cx)-hx)
 local dz=math.max(0,math.abs(point.Z-cz)-hz)
 return math.sqrt(dx*dx+dz*dz)
end
local gap=2+0.5
local rectangle=MeleeRules.candidates(100,-50,32,8,2,5)
expect(rectangle and #rectangle==16,"did not generate sixteen approach options")
expect(close(rectangle[1].X,132+gap) and close(rectangle[1].Z,-50),"east point ignored target width")
expect(close(rectangle[5].X,100) and close(rectangle[5].Z,-42+gap),"north point ignored target depth")
expect(close(rectangle[9].X,68-gap) and close(rectangle[9].Z,-50),"west point ignored target width")
expect(close(rectangle[13].X,100) and close(rectangle[13].Z,-58-gap),"south point ignored target depth")
local diagonal=rectangle[3]
expect(close(diagonal.X,108+gap) and close(diagonal.Z,-42+gap),"diagonal point used a circle instead of intersecting the expanded rectangular footprint")

-- 現有近戰兵種與建築占地：候選不與移動 Blockcast 的方形占地相交，仍在近戰射程內。
local units={{radius=2,range=5},{radius=2,range=6},{radius=2,range=8},{radius=3,range=7},{radius=4,range=8}}
for _,half in ipairs({{X=1.5,Z=1.5},{X=3,Z=4},{X=8,Z=8},{X=32,Z=32},{X=32,Z=8},{X=8,Z=32}}) do
 for _,unit in ipairs(units) do
  local points=MeleeRules.candidates(-73,91,half.X,half.Z,unit.radius,unit.range)
  expect(#points==16,"configured melee unit lost valid approach options")
  for index,point in ipairs(points) do
   local outsideX=math.abs(point.X+73)-half.X
   local outsideZ=math.abs(point.Z-91)-half.Z
   expect(outsideX>unit.radius or outsideZ>unit.radius,"approach point overlaps target with the full movement collision box")
   expect(edgeDistance(point,-73,91,half.X,half.Z)<=unit.range+0.000001,"approach point lies outside the unit's melee range")
   expect(point.index==index,"unfiltered candidate lost its stable angle index")
   for earlier=1,index-1 do
    expect(not (close(point.X,points[earlier].X) and close(point.Z,points[earlier].Z)),"duplicate approach option")
   end
  end
 end
end
local translated=MeleeRules.candidates(0,0,32,8,2,5)
for index,point in ipairs(rectangle) do
 expect(close(point.X-translated[index].X,100) and close(point.Z-translated[index].Z,-50),"moving target changed relative approach geometry")
end
for _,invalid in ipairs({math.huge,-math.huge,0/0,"2",false}) do
 expect(MeleeRules.candidates(invalid,0,8,8,2,5)==nil,"invalid X coordinate accepted")
 expect(MeleeRules.candidates(0,invalid,8,8,2,5)==nil,"invalid Z coordinate accepted")
 expect(MeleeRules.candidates(0,0,invalid,8,2,5)==nil,"invalid X footprint accepted")
 expect(MeleeRules.candidates(0,0,8,invalid,2,5)==nil,"invalid Z footprint accepted")
 expect(MeleeRules.candidates(0,0,8,8,invalid,5)==nil,"invalid unit radius accepted")
 expect(MeleeRules.candidates(0,0,8,8,2,invalid)==nil,"invalid attack range accepted")
end
expect(MeleeRules.candidates(0,0,0,8,2,5)==nil,"zero X footprint accepted")
expect(MeleeRules.candidates(0,0,8,-1,2,5)==nil,"negative Z footprint accepted")
expect(MeleeRules.candidates(0,0,8,8,0,5)==nil,"zero unit radius accepted")
expect(MeleeRules.candidates(0,0,8,8,-1,5)==nil,"negative unit radius accepted")
expect(MeleeRules.candidates(nil,0,8,8,2,5)==nil,"missing coordinate accepted")
expect(MeleeRules.candidates(1e308,0,1e308,8,1e308,1e308)==nil,"overflowing world geometry accepted")
expect(MeleeRules.candidates(0,0,8,8,2,-1)==nil,"negative attack range accepted")
expect(MeleeRules.candidates(0,0,8,8,2,nil)==nil,"missing attack range accepted")
expect(#MeleeRules.candidates(0,0,8,8,2,0)==0,"zero-range unit received reachable attack positions")
local short=MeleeRules.candidates(0,0,8,8,2,gap)
expect(#short>0 and #short<16,"short attack range did not filter unreachable corners")
local seen={}
for _,point in ipairs(short) do
 expect(point.index>=1 and point.index<=16 and not seen[point.index],"filtered candidates lost unique persistent blacklist indices")
 expect(edgeDistance(point,0,0,8,8)<=gap+1e-7,"filtered candidate is outside short attack range")
 seen[point.index]=true
end
print(string.format("PASS: %d melee approach geometry checks",checks))
