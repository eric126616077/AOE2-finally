-- Fallback art: natural resources. stage 0 is full; later stages show depletion.
-- Later stages only remove or shrink pieces, so they always stay inside the stage-0 bounds
-- that ModelFactory used to fit the node.
local K=require(script.Parent.ArtKit)
local timber,cutWood,paleStone,dark=K.timber,K.cutWood,K.paleStone,K.dark
local leaf,leafDark,leafLight=K.leaf,K.leafDark,K.leafLight
local block,round,ball,disc=K.block,K.round,K.ball,K.disc
local B={}
B.Tree=function(model,kind,team,stage)
 -- Four parts per tree across thousands of forest nodes: trunk plus three uniform crowns.
 -- The main crown spans the full width so the fitted canopy still covers forest spacing.
 -- Felling thins the canopy, cuts a pale notch and finally leaves a log by a small remnant crown.
 round(model,"Trunk",2,8.5,Vector3.new(0,4.25,0),timber,Enum.Material.Wood)
 if stage<=0 then
  ball(model,"Crown",12,Vector3.new(0,10.2,0),leafDark,Enum.Material.Grass)
  ball(model,"Crown",7,Vector3.new(2.6,12.6,1.8),leaf,Enum.Material.Grass)
  ball(model,"Crown",6.4,Vector3.new(-2.4,13,-1.9),leafLight,Enum.Material.Grass)
 elseif stage==1 then
  ball(model,"Crown",9.2,Vector3.new(0,10.4,0),leafDark,Enum.Material.Grass)
  ball(model,"Crown",5.4,Vector3.new(2,12.6,1.3),leaf,Enum.Material.Grass)
  round(model,"Cut",2.3,.6,Vector3.new(0,1.3,0),cutWood,Enum.Material.Wood)
 else
  ball(model,"Crown",6.2,Vector3.new(0,10,0),leaf,Enum.Material.Grass)
  round(model,"Cut",2.3,.9,Vector3.new(0,1.4,0),cutWood,Enum.Material.Wood)
  local log=block(model,"Log",Vector3.new(5.4,1.5,1.5),Vector3.new(2.8,.75,1.9),cutWood,Enum.Material.Wood)
  log.Shape=Enum.PartType.Cylinder
  log.CFrame*=CFrame.Angles(0,.7,0)
 end
end
-- Rock piles: {class, size, position, rotation, shade}. Mining removes the leaning stones first,
-- then lowers what is left, so each stage reads shorter and smaller from above.
local keepRocks={[0]=math.huge,3,2}
local rockHeight={[0]=1,.82,.55}
local rockSpread={[0]=1,1,.72}
local function rocks(model,list,base,stage)
 local height,spread=rockHeight[stage],rockSpread[stage]
 for index,rock in ipairs(list) do
  if index>keepRocks[stage] then break end
  local shade=rock[5]>=0 and base:Lerp(paleStone,rock[5]) or base:Lerp(dark,-rock[5])
  local size,pos=rock[2],rock[3]
  local p=block(model,"Rock",Vector3.new(size.X*spread,size.Y*height,size.Z*spread),Vector3.new(pos.X*spread,pos.Y*height,pos.Z*spread),shade,Enum.Material.Slate,rock[1])
  p.CFrame*=CFrame.Angles(rock[4].X,rock[4].Y,rock[4].Z)
 end
 if stage>=2 then
  block(model,"Rock",Vector3.new(1.6,.7,1.5),Vector3.new(-2.6,.35,1.4),base:Lerp(paleStone,.2),Enum.Material.Slate).CFrame*=CFrame.Angles(0,.8,0)
 end
 return height,spread
end
B.Gold=function(model,kind,team,stage)
 -- Warm brown ore rock bristling with bright gold crystals: reads as gold even as a small dot.
 stage=math.min(stage,2)
 local height,spread=rocks(model,{
  {"Part",Vector3.new(5.4,3.8,5),Vector3.new(0,1.9,-.4),Vector3.new(.06,.4,-.05),0},
  {"Part",Vector3.new(4,2.7,3.6),Vector3.new(3,1.35,1.8),Vector3.new(-.08,-.5,.1),.14},
  {"WedgePart",Vector3.new(4,2.9,3.6),Vector3.new(-3,1.45,-1.2),Vector3.new(0,2.3,0),-.14},
  {"Part",Vector3.new(2.6,1.7,2.4),Vector3.new(-1.8,.85,2.7),Vector3.new(0,.9,0),.06},
 },Color3.fromRGB(142,120,96),stage)
 local bright,deep=Color3.fromRGB(246,200,70),Color3.fromRGB(214,160,44)
 local crystals={
  {Vector3.new(1.2,3,1.2),Vector3.new(.3,4.5,-.5),Vector3.new(.25,.6,.2)},
  {Vector3.new(1.1,2.6,1.1),Vector3.new(2.9,2.9,1.9),Vector3.new(-.2,.3,.3)},
  {Vector3.new(1,2.4,1),Vector3.new(-1.4,3.9,.7),Vector3.new(-.3,.2,-.35)},
  {Vector3.new(1,2.2,1),Vector3.new(1.7,3.8,.3),Vector3.new(.2,1,.4)},
  {Vector3.new(.95,2,.95),Vector3.new(-3.1,2.7,-1),Vector3.new(.3,.8,-.3)},
  {Vector3.new(1,.9,1),Vector3.new(-1.7,2,3),Vector3.new(.2,.5,.1)},
 }
 for index=1,({[0]=6,4,2})[stage] do
  local c=crystals[index]
  local p=block(model,"Ore",c[1]*(stage==2 and .8 or 1),Vector3.new(c[2].X*spread,c[2].Y*height,c[2].Z*spread),index%2==0 and deep or bright,Enum.Material.Metal)
  p.CFrame*=CFrame.Angles(c[3].X,c[3].Y,c[3].Z)
 end
end
B.Stone=function(model,kind,team,stage)
 -- Pale, cool grey slabs with one squared quarry block: clearly not gold from any distance.
 stage=math.min(stage,2)
 rocks(model,{
  {"Part",Vector3.new(5.6,4.2,5.2),Vector3.new(0,2.1,-.4),Vector3.new(.08,.5,-.06),.25},
  {"Part",Vector3.new(4.2,3,3.8),Vector3.new(2.9,1.5,2.1),Vector3.new(-.1,-.4,.14),.45},
  {"WedgePart",Vector3.new(4,3,3.6),Vector3.new(-3,1.5,-1.4),Vector3.new(0,2.2,0),-.12},
  {"Part",Vector3.new(3,1.5,2.8),Vector3.new(-.4,4.7,-.4),Vector3.new(.3,.8,.2),.6},
  {"Part",Vector3.new(2.4,1.6,2.2),Vector3.new(-2,.8,2.7),Vector3.new(0,.6,0),.1},
 },Color3.fromRGB(150,158,162),stage)
 if stage<2 then
  block(model,"Rock",Vector3.new(1.7,1.3,1.7),Vector3.new(1.3,.65,3.7),Color3.fromRGB(214,214,204),Enum.Material.Slate).CFrame*=CFrame.Angles(0,.25,0)
 end
end
B.Berries=function(model,kind,team,stage)
 -- Three low leaf mounds studded with berry clusters on their upper, camera-facing sides.
 -- Foraging strips the berries, then leaves two thinner, yellowing bushes.
 stage=math.min(stage,2)
 local picked=Color3.fromRGB(150,140,78)
 local mounds=stage>=2 and {
  {4.2,Vector3.new(-1.9,2.1,-.4),leafDark:Lerp(picked,.4)},
  {3.8,Vector3.new(1.7,1.9,.7),leaf:Lerp(picked,.4)},
 } or {
  {5.2,Vector3.new(-2.5,2.6,-.6),leafDark},
  {4.8,Vector3.new(2.4,2.4,-.9),leaf},
  {4.6,Vector3.new(.1,2.3,1.9),leaf:Lerp(leafLight,.5)},
 }
 for _,mound in ipairs(mounds) do ball(model,"Bush",mound[1],mound[2],mound[3],Enum.Material.Grass) end
 local spots=({[0]={{1,Vector3.new(-.5,.6,.62)},{2,Vector3.new(.35,.8,-.5)},{3,Vector3.new(-.15,.6,.8)},{1,Vector3.new(.4,.85,-.35)},
   {2,Vector3.new(.6,.55,.58)},{3,Vector3.new(.7,.7,.1)},{1,Vector3.new(-.2,.95,.2)},{2,Vector3.new(-.4,.9,.2)}},
  {{1,Vector3.new(-.5,.6,.62)},{2,Vector3.new(.35,.8,-.5)},{3,Vector3.new(-.15,.6,.8)},{2,Vector3.new(.6,.55,.58)}},
  {{1,Vector3.new(-.3,.8,.5)}}})[stage]
 for i,spot in ipairs(spots) do
  local mound=mounds[spot[1]]
  ball(model,"Berry",1.25,mound[2]+spot[2].Unit*(mound[1]/2-.25),i%2==0 and Color3.fromRGB(214,58,76) or Color3.fromRGB(170,40,66))
 end
end
B.Deer=function(model,kind,team,stage)
 -- A standing red deer with a pale rump and antlers. Once hunted (any later stage) it lies on
 -- its side as a carcass that shrinks as villagers butcher it, always inside the standing bounds.
 local coat,belly,hoof,antler=Color3.fromRGB(150,98,58),Color3.fromRGB(214,186,146),Color3.fromRGB(58,44,34),Color3.fromRGB(226,212,180)
 if stage<=0 then
  disc(model,"Body",2.1,3.6,Vector3.new(0,3.1,0),coat)
  ball(model,"Body",2.1,Vector3.new(0,3.15,-1.7),coat)
  ball(model,"Rump",1.9,Vector3.new(0,3.2,1.8),belly)
  for _,x in ipairs({-.55,.55}) do for _,z in ipairs({-1.6,1.7}) do
   block(model,"Leg",Vector3.new(.38,2.2,.42),Vector3.new(x,1.1,z),coat)
   block(model,"Hoof",Vector3.new(.42,.3,.46),Vector3.new(x,.15,z),hoof)
  end end
  local neck=block(model,"Neck",Vector3.new(.9,2,.9),Vector3.new(0,4.3,-2.3),coat)
  neck.CFrame*=CFrame.Angles(-.5,0,0)
  block(model,"Head",Vector3.new(.85,.85,1.6),Vector3.new(0,5.2,-2.95),coat)
  block(model,"Muzzle",Vector3.new(.6,.55,.5),Vector3.new(0,5.05,-3.8),hoof)
  for _,side in ipairs({-1,1}) do
   block(model,"Ear",Vector3.new(.15,.6,.35),Vector3.new(side*.5,5.7,-2.6),coat).CFrame*=CFrame.Angles(0,0,side*.5)
   local beamPart=block(model,"Antler",Vector3.new(.16,1.5,.16),Vector3.new(side*.45,6.2,-2.7),antler)
   beamPart.CFrame*=CFrame.Angles(.15,0,side*-.45)
   block(model,"Antler",Vector3.new(.14,.7,.14),Vector3.new(side*.6,6.3,-3.05),antler).CFrame*=CFrame.Angles(.7,0,side*-.2)
  end
 else
  local shrink=stage>=2 and .75 or 1
  disc(model,"Body",2*shrink,3.4*shrink,Vector3.new(0,.95*shrink,0),coat)
  ball(model,"Rump",1.7*shrink,Vector3.new(0,.9*shrink,1.7*shrink),belly)
  for _,z in ipairs({-1.4,1.5}) do
   block(model,"Leg",Vector3.new(2.2,.36,.4)*shrink,Vector3.new(1.6*shrink,.4,z*shrink),coat)
  end
  block(model,"Head",Vector3.new(.8,.8,1.5)*shrink,Vector3.new(-.3,.45,-2.7*shrink),coat).CFrame*=CFrame.Angles(0,.4,0)
  if stage<2 then block(model,"Antler",Vector3.new(1.2,.16,.16),Vector3.new(-.9,.5,-2.4),antler) end
 end
end
B.Relic=function(model,kind,team,stage)
 -- A gilded reliquary on a weathered stone plinth, with a glowing gem: reads as treasure from the top-down camera.
 local gilt,giltDark,gem=Color3.fromRGB(232,190,82),Color3.fromRGB(176,128,46),Color3.fromRGB(120,214,255)
 block(model,"Plinth",Vector3.new(3.4,.6,3.4),Vector3.new(0,.3,0),paleStone,Enum.Material.Slate)
 block(model,"Plinth",Vector3.new(2.8,.35,2.8),Vector3.new(0,.78,0),paleStone:Lerp(dark,.15),Enum.Material.Slate)
 block(model,"Reliquary",Vector3.new(2.2,1.3,1.5),Vector3.new(0,1.6,0),gilt,Enum.Material.Metal)
 block(model,"Reliquary",Vector3.new(2.4,.2,1.7),Vector3.new(0,2.3,0),giltDark,Enum.Material.Metal)
 local roof=block(model,"Reliquary",Vector3.new(2.2,.7,1.5),Vector3.new(0,2.75,0),gilt,Enum.Material.Metal,"WedgePart")
 roof.Size=Vector3.new(2.2,.7,.75); roof.CFrame=CFrame.new(0,2.75,-.375)*CFrame.Angles(0,math.pi,0)
 block(model,"Reliquary",Vector3.new(2.2,.7,.75),Vector3.new(0,2.75,.375),gilt,Enum.Material.Metal,"WedgePart")
 block(model,"Gem",Vector3.new(.5,.5,.12),Vector3.new(0,1.65,-.8),gem,Enum.Material.Neon)
 block(model,"Finial",Vector3.new(.2,.9,.2),Vector3.new(0,3.5,0),giltDark,Enum.Material.Metal)
 block(model,"Finial",Vector3.new(.7,.2,.2),Vector3.new(0,3.65,0),giltDark,Enum.Material.Metal)
end
B.Boar=function(model,kind,team,stage)
 -- A dark bristly boar with pale tusks; once killed (any later stage) it lies on its side and shrinks.
 local hide,bristle,tusk,snout=Color3.fromRGB(86,64,52),Color3.fromRGB(54,40,34),Color3.fromRGB(236,226,200),Color3.fromRGB(150,104,92)
 if stage<=0 then
  disc(model,"Body",2.6,4,Vector3.new(0,2.3,0),hide)
  ball(model,"Body",2.7,Vector3.new(0,2.4,-1.6),hide)
  ball(model,"Rump",2.3,Vector3.new(0,2.2,1.8),hide)
  block(model,"Bristle",Vector3.new(.5,.7,3.6),Vector3.new(0,3.75,-.4),bristle)
  for _,x in ipairs({-.65,.65}) do for _,z in ipairs({-1.4,1.6}) do
   block(model,"Leg",Vector3.new(.45,1.3,.5),Vector3.new(x,.65,z),bristle)
  end end
  block(model,"Head",Vector3.new(1.4,1.3,1.5),Vector3.new(0,2.3,-3),hide)
  block(model,"Snout",Vector3.new(.9,.7,.5),Vector3.new(0,2,-3.9),snout)
  for _,side in ipairs({-1,1}) do
   block(model,"Tusk",Vector3.new(.16,.6,.16),Vector3.new(side*.5,2.3,-3.8),tusk).CFrame*=CFrame.Angles(.4,0,side*.3)
   block(model,"Ear",Vector3.new(.2,.5,.4),Vector3.new(side*.55,3.1,-2.6),bristle)
  end
 else
  local shrink=stage>=2 and .75 or 1
  disc(model,"Body",2.4*shrink,3.8*shrink,Vector3.new(0,1.2*shrink,0),hide)
  ball(model,"Rump",2*shrink,Vector3.new(0,1.1*shrink,1.7*shrink),hide)
  block(model,"Head",Vector3.new(1.3,1.2,1.4)*shrink,Vector3.new(-.2,.65,-2.7*shrink),hide)
  for _,z in ipairs({-1.3,1.4}) do block(model,"Leg",Vector3.new(1.3,.4,.45)*shrink,Vector3.new(1.5*shrink,.4,z*shrink),bristle) end
  if stage<2 then block(model,"Tusk",Vector3.new(.16,.16,.6),Vector3.new(-.4,.7,-3.5),tusk) end
 end
end
B.Sheep=function(model,kind,team,stage)
 -- A neutral standing sheep (not yet claimed), or a slaughtered fleece lying on the grass.
 local wool,face=Color3.fromRGB(240,236,224),Color3.fromRGB(52,46,42)
 if stage<=0 then
  ball(model,"Body",2.6,Vector3.new(0,2.1,.3),wool,Enum.Material.Fabric)
  ball(model,"Body",2.2,Vector3.new(0,2.3,-.8),wool,Enum.Material.Fabric)
  for _,x in ipairs({-.6,.6}) do for _,z in ipairs({-.9,1}) do
   block(model,"Leg",Vector3.new(.32,1.3,.32),Vector3.new(x,.65,z),face)
  end end
  block(model,"Head",Vector3.new(.8,.9,1.1),Vector3.new(0,2.6,-2),face)
 else
  local shrink=stage>=2 and .7 or 1
  disc(model,"Body",2.4*shrink,2.8*shrink,Vector3.new(0,1*shrink,0),wool:Lerp(face,.08),Enum.Material.Fabric)
  block(model,"Head",Vector3.new(.8,.8,1)*shrink,Vector3.new(.2,.5,-1.9*shrink),face)
  for _,z in ipairs({-.8,.9}) do block(model,"Leg",Vector3.new(1.2,.3,.3)*shrink,Vector3.new(1.3*shrink,.35,z*shrink),face) end
 end
end
return B
