local Rules=require("../src/ReplicatedStorage/Shared/AmbienceRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
-- Wind: bounded, continuous in time and travelling, so neighbours are out of phase.
local changed,previous=0,Rules.Gust(40,-70,0)
for step=1,600 do
 local value=Rules.Gust(40,-70,step/60)
 expect(value>=-1 and value<=1,"gust left -1..1")
 expect(math.abs(value-previous)<.12,"gust jumped between two 60 Hz frames")
 if value~=previous then changed+=1 end
 previous=value
end
expect(changed>=590,"wind stood still: an idle scene would look frozen")
expect(math.abs(Rules.Gust(0,0,3)-Rules.Gust(60,45,3))>.01,"distant trees swayed in unison")
for _,invalid in ipairs({0/0,math.huge,-math.huge,"x",false}) do
 expect(Rules.Gust(invalid,0,1)==0 and Rules.Gust(0,invalid,1)==0 and Rules.Gust(0,0,invalid)==0,"invalid wind input moved a part")
end
expect(math.abs(Rules.WindX^2+Rules.WindZ^2-1)<1e-9,"wind direction is not a unit vector")
-- Budgets stay bounded however far the camera zooms.
for _,height in ipairs({-5,0,20,160,400,5000,0/0,math.huge}) do
 local radius,density=Rules.ViewRadius(height),Rules.Density(height)
 expect(radius>=Rules.MinViewRadius and radius<=Rules.MaxViewRadius,"view radius unbounded")
 expect(density>0 and density<=Rules.GrassDensity,"grass density unbounded")
end
expect(Rules.Density(400)<Rules.Density(160),"zooming out did not thin the grass")
expect(Rules.WriteBudget>0 and Rules.MaxTrees>0 and Rules.MaxTufts>0 and Rules.MaxNewTufts<=Rules.MaxTufts,"budgets missing")
-- Grass layout: deterministic, inside its own cell, about the configured density.
local present,flowers,cells=0,0,0
local blocks={}
for cx=-40,40 do
 for cz=-40,40 do
  cells+=1
  local tuft=Rules.Tuft(cx,cz)
  local again=Rules.Tuft(cx,cz)
  expect((tuft==nil)==(again==nil),"grass layout changed between calls")
  if tuft then
   present+=1
   if tuft.flower>0 then flowers+=1 end
   local block=math.floor(cx/4)*4096+math.floor(cz/4)
   blocks[block]=(blocks[block] or 0)+1
   expect(tuft.x==again.x and tuft.z==again.z and tuft.rank==again.rank,"tuft moved between calls")
   expect(tuft.x>=cx*Rules.GrassCell and tuft.x<(cx+1)*Rules.GrassCell and tuft.z>=cz*Rules.GrassCell and tuft.z<(cz+1)*Rules.GrassCell,"tuft left its cell")
   -- Low and thin: grass is ground texture and must not compete with units or resources.
   expect(tuft.rank<Rules.GrassDensity and tuft.height>=.5 and tuft.height<=1.75 and tuft.width>=1.1 and tuft.width<=2,"tuft size or rank out of range")
   expect(tuft.flower>=0 and tuft.flower<=4 and tuft.flower%1==0,"flower index out of range")
  end
 end
end
expect(present/cells>.15 and present/cells<Rules.GrassDensity*.75,"grass too sparse or carpeting the whole map")
expect(flowers>0 and flowers<present*.25,"flowers missing or covering the meadow")
-- Patches, not an even sprinkle: some 4x4 cell blocks are empty while others are nearly full.
local empty,dense=0,0
for bx=-10,9 do
 for bz=-10,9 do
  local count=blocks[bx*4096+bz] or 0
  if count==0 then empty+=1 elseif count>=10 then dense+=1 end
 end
end
expect(empty>=20 and dense>=20,"grass spread evenly instead of gathering in patches")
for cx=-40,40 do
 local value=Rules.Patch(cx,cx*3,20)
 expect(value>=0 and value<=1 and math.abs(value-Rules.Patch(cx+1,cx*3,20))<.5,"patch field out of range or not smooth")
end
-- Bare ground mirrors the scenery: roads, crossroads, base courtyards and the shore.
local size,road=1024,20
expect(Rules.Bare(0,0,size,road) and Rules.Bare(30,-30,size,road),"grass grew on the central crossroads")
expect(Rules.Bare(200,200,size,road) and Rules.Bare(-150,150,size,road),"grass grew on a trade road")
expect(Rules.Bare(374,324,size,road) and Rules.Bare(-324,-374,size,road),"grass grew in a base courtyard")
expect(Rules.Bare(510,100,size,road) and Rules.Bare(100,-508,size,road),"grass grew on the shore")
expect(not Rules.Bare(100,300,size,road) and not Rules.Bare(-250,60,size,road),"open meadow was left bare")
expect(Rules.Bare(0/0,0,size,road) and Rules.Bare(10,10,"big",road),"invalid position grew grass")
print("PASS: "..checks.." ambience wind / budget / grass layout / bare ground checks")
