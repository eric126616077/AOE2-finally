-- Fallback art: civic, economic and military production buildings. Front faces +Z.
local K=require(script.Parent.ArtKit)
local stone,paleStone,timber,cutWood,plaster,roof,iron,dark,straw,gold=K.stone,K.paleStone,K.timber,K.cutWood,K.plaster,K.roof,K.iron,K.dark,K.straw,K.gold
local block,beam,round,disc,ball,segment,plate,point,turn=K.block,K.beam,K.round,K.disc,K.ball,K.segment,K.plate,K.point,K.turn
local roofAt,foundation,hall,door,window,banner,stairs,fence,barrel,chimney,tower=K.roofAt,K.foundation,K.hall,K.door,K.window,K.banner,K.stairs,K.fence,K.barrel,K.chimney,K.tower
local tile,tileDark,thatch,thatchDark,wallShade,earth,leaf,leafDark,leafLight,steel,skin,leather=K.tile,K.tileDark,K.thatch,K.thatchDark,K.wallShade,K.earth,K.leaf,K.leafDark,K.leafLight,K.steel,K.skin,K.leather
local cone=K.cone
local V,A,pi,M=Vector3.new,CFrame.Angles,math.pi,Enum.Material
-- Local accents, kept in the same warm low-saturation range as the kit palette.
local water=Color3.fromRGB(96,140,150)
local sand=Color3.fromRGB(196,170,120)
local soil=Color3.fromRGB(104,82,58)
local hide=Color3.fromRGB(128,88,58)
local ember=Color3.fromRGB(232,120,48)
local verdigris=Color3.fromRGB(112,146,134)
local bloom=Color3.fromRGB(196,110,96)
local plank=Color3.fromRGB(150,108,70)
-- Solid toy-block roofs: two wedges meet at the ridge, so a whole gable costs a handful of parts.
-- c is the middle of the eave line; w runs along the ridge, d across it.
local function wedges(model,name,c,w,d,h,color,material,axis)
 local parts={}
 for _,s in ipairs({-1,1}) do
  local p=block(model,name,V(w,h,d/2),c+V(0,h/2,s*d/4),color,material,"WedgePart")
  if s>0 then p.CFrame*=A(0,pi,0) end
  parts[#parts+1]=p
 end
 if axis=="z" then turn(parts,c,A(0,pi/2,0)) end
 return parts
end
-- cap: nil gives the team-colored "Ridge", false none, or a neutral part name with capColor.
local function gable(model,c,w,d,h,color,axis,cap,capColor)
 local z=axis=="z"
 wedges(model,"RoofTile",c,w,d,h,color,K.roofMaterial(color),axis)
 block(model,"Eave",z and V(d+.4,.4,w+.3) or V(w+.3,.4,d+.4),c-V(0,.2,0),timber,M.Wood)
 if cap~=false then block(model,cap or "Ridge",z and V(1.2,.6,w+.5) or V(w+.5,.6,1.2),c+V(0,h+.05,0),capColor or tileDark,M.Fabric) end
end
local function crossGable(model,c,s,h,color)
 gable(model,c,s,s,h,color)
 wedges(model,"RoofTile",c,s,s,h,color,K.roofMaterial(color),"z")
end
-- Painted triangle on the camera-facing end of a ridge-along-Z roof; the tile shows as a border.
local function gableFace(model,x,y,z,span,h,color)
 local inner=span-2
 wedges(model,"Gable",V(x,y,z-.05),.3,inner,h*inner/span,color or plaster,M.Concrete,"z")
end
-- Single slope. yaw pi falls toward the camera, -pi/2 falls toward +X.
local function lean(model,name,c,size,color,yaw,material)
 local p=block(model,name,size,c,color,material or K.roofMaterial(color),"WedgePart")
 p.CFrame*=A(0,yaw or pi,0)
 return p
end
-- Round-headed panel on a +Z wall; p is its bottom center.
local function arch(model,name,p,w,h,color,thick,material)
 block(model,name,V(w,h-w/2,thick or .3),p+V(0,(h-w/2)/2,0),color,material)
 disc(model,name,w,thick or .3,p+V(0,h-w/2,0),color,material)
end
local function gate(model,p,w,h)
 arch(model,"DoorFrame",p,w+1,h+.5,paleStone,.3)
 arch(model,"Door",p+V(0,0,.1),w,h,cutWood,.4,M.WoodPlanks)
end
local function win(model,p,w,h,shutter)
 block(model,"Window",V(w,h,.25),p,dark)
 block(model,"WindowSill",V(w+.6,.35,.6),p+V(0,-h/2-.15,.1),paleStone)
 if shutter then for _,s in ipairs({-1,1}) do block(model,"Shutter",V(.7,h,.3),p+V(s*(w/2+.4),0,.05),shutter,M.WoodPlanks) end end
end
local function flag(model,p,h,team)
 block(model,"Flagpole",V(.3,h,.3),p+V(0,h/2,0),timber)
 block(model,"Flag",V(2.6,1.6,.15),p+V(1.45,h-.9,0),team,M.Fabric)
end
local function fenceRun(model,points,h)
 for i,p in ipairs(points) do
  block(model,"FencePost",V(.55,h,.55),p+V(0,h/2,0),timber)
  local q=points[i+1]
  if q then for _,y in ipairs({h*.4,h*.8}) do beam(model,"FenceRail",p+V(0,y,0),q+V(0,y,0),.35,cutWood,M.Wood) end end
 end
end
local function shield(model,p,d,team)
 disc(model,"Shield",d,.4,p,team,M.WoodPlanks)
 disc(model,"ShieldBoss",d*.32,.5,p+V(0,0,.1),gold,M.Metal)
end
local B={}
-- Bell tower over the gate, a great hall behind and two open market loggias around a plaza.
B.TownCenter=function(model,kind,team,stage)
 foundation(model,32,32)
 block(model,"Courtyard",V(13.4,.3,19),V(0,.9,6.2),paleStone,M.Cobblestone)
 block(model,"StonePlinth",V(29,2.2,10.6),V(0,1.9,-9.5),stone,M.Brick)
 block(model,"Walls",V(28,10,10),V(0,7.8,-9.5),plaster)
 gable(model,V(0,13,-9.5),30,12.6,5.5,tile)
 for _,s in ipairs({-1,1}) do
  block(model,"Chimney",V(2,5,2),V(s*10.5,16.6,-12),stone,M.Brick)
  -- Dormers break up the long front slope.
  block(model,"Walls",V(2.6,3.4,3),V(s*7.6,14.9,-5.3),plaster)
  gable(model,V(s*7.6,16.6,-5.6),4,3.4,1.6,tile,"z",false)
  block(model,"Window",V(1.4,1.6,.2),V(s*7.6,15.4,-3.75),dark)
  local x=s*11.25
  block(model,"Walls",V(7.5,7.6,6.5),V(x,4.6,-1.25),wallShade)
  gable(model,V(x,8.5,3.5),16,9,4,tile,"z")
  gableFace(model,x,8.5,11.5,9,4)
  for _,dx in ipairs({-3.3,3.3}) do block(model,"Post",V(.8,7.7,.8),V(x+dx,4.65,10.6),timber) end
  block(model,"Beam",V(7.6,.7,.6),V(x,8,10.6),timber)
  block(model,"Banner",V(2.2,3.2,.15),V(x,6,10.95),team,M.Fabric)
  ball(model,"Shrub",3,V(s*8.6,2.1,13.8),leafDark,M.Grass)
 end
 barrel(model,V(-11.6,.8,7.6))
 block(model,"Crate",V(2.6,2.2,2.6),V(10.2,1.9,7.4),cutWood,M.WoodPlanks)
 ball(model,"Sack",2.1,V(12.7,1.8,8),straw,M.Fabric)
 block(model,"Tower",V(7.5,14.8,7.5),V(0,8.2,-1),stone,M.Brick)
 block(model,"StoneCourse",V(8.4,.8,8.4),V(0,15.6,-1),paleStone)
 for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
  block(model,"Post",V(1.1,3.4,1.1),V(sx*3.1,17.7,-1+sz*3.1),paleStone)
 end end
 ball(model,"Bell",2.6,V(0,17.6,-1),gold,M.Metal)
 block(model,"Beam",V(7.4,.5,.5),V(0,19.15,-1),timber)
 crossGable(model,V(0,19.6,-1),9,4.2,tile)
 flag(model,V(0,23.6,-1),2.4,team)
 disc(model,"ClockRim",4.2,.2,V(0,11.6,2.8),timber)
 disc(model,"Clock",3.5,.3,V(0,11.6,2.85),plaster)
 disc(model,"ClockBoss",1,.4,V(0,11.6,2.9),gold,M.Metal)
 gate(model,V(0,.8,2.75),3.6,5.4)
 round(model,"Well",4.2,1.8,V(0,1.7,10.5),stone,M.Brick)
 round(model,"Water",3,.2,V(0,2.55,10.5),water)
 for _,s in ipairs({-1,1}) do block(model,"WellPost",V(.45,3.8,.45),V(s*1.8,3.3,10.5),timber) end
 gable(model,V(0,5.2,10.5),5,3.6,1.5,tile,nil,false)
end
-- Thatched L-shaped cottage with a fat chimney and a fenced cabbage patch.
B.House=function(model,kind,team,stage)
 block(model,"Foundation",V(16,.6,16),V(0,.3,0),earth,M.Ground)
 block(model,"StonePlinth",V(13.4,1.2,8.4),V(-.3,1.2,-3),stone,M.Cobblestone)
 block(model,"Walls",V(13,5.6,8),V(-.3,4.4,-3),plaster)
 gable(model,V(-.3,7.3,-3),14.6,9.6,4.8,thatch,nil,"RoofFascia",thatchDark)
 block(model,"Chimney",V(2.4,12.8,2.8),V(6.3,7,-3),stone,M.Brick)
 block(model,"ChimneyCap",V(3,.5,3.4),V(6.3,13.6,-3),paleStone)
 block(model,"ChimneyOpening",V(1.4,.1,1.8),V(6.3,13.9,-3),dark)
 block(model,"Walls",V(6,6.4,6),V(-3.6,3.8,3.6),plaster)
 gable(model,V(-3.6,7.1,2),10.6,7.6,4,thatch,"z","RoofFascia",thatchDark)
 gableFace(model,-3.6,7.1,7.3,7.6,4)
 disc(model,"Window",1.5,.2,V(-3.6,8.5,7.4),dark)
 block(model,"DoorFrame",V(2.7,4,.2),V(-3.6,2.6,6.62),timber)
 block(model,"Door",V(2,3.6,.3),V(-3.6,2.4,6.65),cutWood,M.WoodPlanks)
 lean(model,"Awning",V(-3.6,5.1,7.2),V(3.4,1,1.5),team,pi,M.Fabric)
 block(model,"Step",V(3,.4,1.2),V(-3.6,.8,7.3),paleStone)
 block(model,"Window",V(2.2,2,.25),V(3,4.8,1),dark)
 for _,s in ipairs({-1,1}) do block(model,"Shutter",V(.8,2,.3),V(3+s*1.5,4.8,1.05),team,M.WoodPlanks) end
 block(model,"FlowerBox",V(2.8,.6,.8),V(3,3.4,1.4),cutWood,M.WoodPlanks)
 block(model,"Flowers",V(2.5,.4,.6),V(3,3.85,1.4),bloom,M.Grass)
 block(model,"Soil",V(5.6,.3,4.4),V(3.6,.7,4.7),soil,M.Ground)
 for _,x in ipairs({1.9,3.6,5.3}) do for _,z in ipairs({3.7,5.7}) do
  ball(model,"Crop",1.2,V(x,1.25,z),leafLight,M.Grass)
 end end
 fenceRun(model,{V(.2,.6,7.6),V(7.6,.6,7.6),V(7.6,.6,1.8)},2)
 ball(model,"Shrub",1.7,V(-7.1,1.3,5.2),leafDark,M.Grass)
 ball(model,"Shrub",1.3,V(-7.2,1.1,3.7),leaf,M.Grass)
end
-- Stone-footed hall, crenellated corner tower and a sand drill yard with dummies.
B.Barracks=function(model,kind,team,stage)
 foundation(model,24,24)
 block(model,"Courtyard",V(15.6,.25,13.4),V(4,.9,5.1),sand,M.Ground)
 block(model,"StoneWall",V(22,4.4,9),V(0,3,-6.5),stone,M.Brick)
 block(model,"Walls",V(21.6,4.8,8.6),V(0,7.5,-6.5),plaster)
 block(model,"Beam",V(22.2,.5,.5),V(0,5.3,-2),timber)
 gable(model,V(0,10,-6.5),23.4,10.6,5,tile)
 block(model,"Tower",V(7,15.6,7),V(-8,8.6,1.2),stone,M.Brick)
 block(model,"StoneCourse",V(8,1,8),V(-8,16.4,1.2),paleStone)
 block(model,"TowerDeck",V(6,.2,6),V(-8,17,1.2),dark,M.Slate)
 for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
  block(model,"Battlement",V(1.8,1.7,1.8),V(-8+sx*3.1,17.75,1.2+sz*3.1),stone,M.Brick)
 end end
 flag(model,V(-8,17,1.2),3,team)
 block(model,"ArrowSlit",V(.6,2.6,.2),V(-8,12.6,4.72),dark)
 shield(model,V(-8,7.6,4.85),3.2,team)
 arch(model,"Door",V(-8,.8,4.72),2,3.6,cutWood,.3,M.WoodPlanks)
 gate(model,V(4,.8,-2),3.2,4.6)
 for _,x in ipairs({-.6,8.6}) do shield(model,V(x,7.5,-2.05),2.4,team) end
 for _,x in ipairs({1,7.2}) do
  block(model,"DummyPost",V(.5,4.6,.5),V(x,3.2,5.4),timber)
  block(model,"DummyArm",V(3.4,.45,.45),V(x,4.3,5.4),timber)
  round(model,"DummyBody",1.8,2.2,V(x,3.5,5.4),straw,M.Fabric)
  ball(model,"DummyHead",1.3,V(x,5.3,5.4),straw,M.Fabric)
  disc(model,"Shield",1.7,.3,V(x-1.5,4.2,5.75),team,M.WoodPlanks)
 end
 for _,x in ipairs({8.2,11}) do block(model,"RackPost",V(.4,3,.4),V(x,2.4,.2),timber) end
 block(model,"WeaponRack",V(3.6,.35,.35),V(9.6,3.7,.2),timber)
 for _,x in ipairs({8.8,9.6,10.4}) do beam(model,"TrainingSpear",V(x,1,1.2),V(x,6.4,0),.35,cutWood,M.Wood) end
 fenceRun(model,{V(-3.6,.8,11.6),V(1.2,.8,11.6)},2.6)
 fenceRun(model,{V(6.8,.8,11.6),V(11.6,.8,11.6),V(11.6,.8,-1)},2.6)
end
-- Timber lodge with a lookout loft, three grass lanes and tilted targets against hay butts.
local function target(model,p,team)
 local c=p+V(0,2.3,0)
 local parts={disc(model,"Target",4.6,.6,c,straw,M.Fabric),disc(model,"TargetRing",3.3,.4,c+V(0,0,.2),plaster,M.Fabric),
  disc(model,"Bullseye",1.7,.4,c+V(0,0,.3),team,M.Fabric)}
 turn(parts,c,A(-math.rad(24),0,0))
 beam(model,"TargetStand",p+V(0,0,-1.5),c+V(0,.6,-.3),.4,timber,M.Wood)
end
B.ArcheryRange=function(model,kind,team,stage)
 block(model,"Foundation",V(24,.6,24),V(0,.3,0),earth,M.Ground)
 block(model,"StonePlinth",V(18.4,1.4,7.4),V(-2.4,1.3,-7.6),stone,M.Cobblestone)
 block(model,"Walls",V(18,5.6,7),V(-2.4,4.6,-7.6),plaster)
 gable(model,V(-2.4,7.5,-7.6),18.6,8.4,4.2,tile)
 block(model,"StonePlinth",V(5.5,3,5.9),V(8.9,2.1,-8.2),stone,M.Cobblestone)
 block(model,"Tower",V(5,13.4,5.4),V(8.9,7.3,-8.2),plaster)
 gable(model,V(8.9,14.1,-8.2),6.6,5.6,3.4,tile,"z")
 gableFace(model,8.9,14.1,-4.9,5.6,3.4)
 flag(model,V(8.9,17.3,-8.2),2.6,team)
 arch(model,"Window",V(8.9,10,-5.45),1.8,2.8,dark,.25)
 block(model,"Banner",V(1.8,4,.15),V(8.9,6.6,-5.4),team,M.Fabric)
 block(model,"DoorFrame",V(2.8,4.2,.2),V(-5.4,2.9,-4.08),timber)
 block(model,"Door",V(2.2,3.8,.3),V(-5.4,2.7,-4.05),cutWood,M.WoodPlanks)
 win(model,V(.6,5.2,-4.1),2,1.8)
 for _,x in ipairs({-8.4,-2.4,3.6}) do
  block(model,"Courtyard",V(5,.2,13.6),V(x,.7,4.6),leafLight,M.Grass)
  block(model,"HayBale",V(5,3,1.5),V(x,2.1,-3.2),straw,M.Grass)
  target(model,V(x,.8,-1.3),team)
  round(model,"Quiver",1.3,2,V(x+1.7,1.8,10.2),leather)
  round(model,"Arrows",1,.5,V(x+1.7,3,10.2),paleStone)
 end
 for _,x in ipairs({-5.4,.6}) do
  block(model,"FenceRail",V(.35,.35,12),V(x,1.7,4.5),cutWood)
  for _,z in ipairs({-1.5,10.5}) do block(model,"FencePost",V(.5,1.5,.5),V(x,1.35,z),timber) end
 end
 block(model,"Counter",V(4.2,2,2.2),V(9.4,1.6,4.7),cutWood,M.WoodPlanks)
 for _,x in ipairs({7.5,11.3}) do
  block(model,"Post",V(.4,4.4,.4),V(x,2.8,6.2),timber)
  block(model,"Post",V(.4,4.4,.4),V(x,2.8,2.4),timber)
 end
 lean(model,"Awning",V(9.4,5.8,4.3),V(4.8,1.8,4.6),team,pi,M.Fabric)
 barrel(model,V(9.4,.6,9.6))
end
-- Long stall barn with a tall hay-loft gable, a fenced paddock and a saddled horse.
B.Stable=function(model,kind,team,stage)
 block(model,"Foundation",V(32,.6,24),V(0,.3,0),earth,M.Ground)
 block(model,"Paddock",V(30.4,.2,13.4),V(0,.7,4.9),sand,M.Ground)
 block(model,"Walls",V(29,6.2,8.4),V(0,3.7,-7.2),wallShade)
 gable(model,V(0,6.9,-7.2),30.6,9.2,4.6,tile)
 block(model,"Walls",V(7.4,9.4,8),V(0,5.3,-5),plaster)
 gable(model,V(0,10.1,-5.1),8.4,8.4,4.4,tile,"z")
 gableFace(model,0,10.1,-.9,8.4,4.4)
 block(model,"LoftDoor",V(2.6,2.6,.2),V(0,8.4,-.95),dark)
 block(model,"Hay",V(2.2,1.2,.9),V(0,7.7,-.7),straw,M.Grass)
 block(model,"Beam",V(.5,.5,2.8),V(0,12.4,.3),timber)
 block(model,"Rope",V(.2,2.4,.2),V(0,11.1,1.3),straw)
 block(model,"HayBale",V(1.7,1.4,1.4),V(0,9.5,1.3),straw,M.Grass)
 block(model,"DoorFrame",V(5.2,5.4,.2),V(0,3.3,-.98),timber)
 block(model,"Door",V(4.4,4.8,.3),V(0,3,-.9),cutWood,M.WoodPlanks)
 for _,x in ipairs({-11.6,-6.6,6.6,11.6}) do
  block(model,"StallOpening",V(3.8,4.4,.2),V(x,2.8,-2.95),dark)
  block(model,"StallGate",V(3.8,2,.3),V(x,1.6,-2.85),cutWood,M.WoodPlanks)
 end
 for _,x in ipairs({-14.1,-9.1,-4.1,4.1,9.1,14.1}) do block(model,"Post",V(.6,6.2,.5),V(x,3.7,-2.9),timber) end
 block(model,"Beam",V(29,.5,.4),V(0,5.4,-2.9),timber)
 for _,x in ipairs({-6.6,11.6}) do block(model,"HorseHead",V(.9,1.1,2),V(x,3.6,-2.1),hide) end
 fenceRun(model,{V(-15.4,.6,-2.4),V(-15.4,.6,11.4),V(-4,.6,11.4)},2.8)
 fenceRun(model,{V(4,.6,11.4),V(15.4,.6,11.4),V(15.4,.6,-2.4)},2.8)
 for _,x in ipairs({8.6,12}) do block(model,"TeamTrim",V(1.8,1.3,.7),V(x,2.5,11.4),team,M.Fabric) end
 block(model,"Horse",V(4,1.8,1.6),V(8,3.4,5.5),hide)
 for _,x in ipairs({6.5,9.5}) do block(model,"HorseLegs",V(.6,1.9,1.4),V(x,1.65,5.5),hide) end
 beam(model,"HorseNeck",V(6.5,3.8,5.5),V(5.3,5.4,5.5),1,hide)
 block(model,"HorseHead",V(1.8,.9,.9),V(4.7,5.5,5.5),hide)
 block(model,"HorseTail",V(.4,1.7,.5),V(10.1,3.4,5.5),dark)
 block(model,"Saddle",V(1.6,.35,1.8),V(8.2,4.4,5.5),team,M.Fabric)
 for _,p in ipairs({V(-9.5,2.1,2.4),V(-9.5,2.1,5.2),V(-9.5,4.3,3.8)}) do plate(model,"HayBale",2.7,3.2,p,straw,M.Grass) end
 block(model,"Trough",V(5,1.4,1.8),V(-9.5,1.4,9.2),timber,M.WoodPlanks)
 block(model,"Water",V(4.4,.2,1.2),V(-9.5,2.05,9.2),water)
end
-- Slate workshop beside a giant stepped forge stack with a glowing hearth; anvil out front.
B.Blacksmith=function(model,kind,team,stage)
 foundation(model,24,24)
 block(model,"Courtyard",V(23.2,.2,13),V(0,.9,5.1),earth,M.Ground)
 block(model,"StonePlinth",V(14.4,3,9.8),V(4,2.3,-6.5),stone,M.Brick)
 block(model,"Walls",V(14,5,9.4),V(4,6,-6.5),plaster)
 gable(model,V(4,8.6,-6.5),15.2,10.6,4.6,roof)
 -- Gabled entrance bay makes the slate roof a T.
 block(model,"Walls",V(5,7.8,3),V(8.2,4.7,-.8),plaster)
 gable(model,V(8.2,8.6,-3),8,6.4,3.2,roof,"z")
 gableFace(model,8.2,8.6,1,6.4,3.2)
 block(model,"DoorFrame",V(3.4,4.8,.2),V(8.2,3.2,.72),paleStone)
 block(model,"Door",V(2.6,4.4,.3),V(8.2,3,.8),cutWood,M.WoodPlanks)
 block(model,"Banner",V(2,2.2,.15),V(8.2,7,.8),team,M.Fabric)
 win(model,V(1.6,6,-1.8),2.6,2)
 block(model,"Chimney",V(7.6,7,7),V(-7.8,4.3,-5),stone,M.Brick)
 block(model,"Chimney",V(5.4,5,5),V(-7.8,10.3,-5.4),stone,M.Brick)
 block(model,"Chimney",V(3.6,5,3.6),V(-7.8,15.3,-5.4),stone,M.Brick)
 block(model,"ChimneyCap",V(4.4,.6,4.4),V(-7.8,18,-5.4),paleStone)
 block(model,"Ember",V(2.4,.3,2.4),V(-7.8,18.4,-5.4),ember,M.Neon)
 arch(model,"ForgeMouth",V(-7.8,1.8,-1.45),4,4.4,dark,.3)
 block(model,"Forge",V(5.4,1.2,2),V(-7.8,1.4,-.6),stone,M.Brick)
 block(model,"Coals",V(3.4,.5,1.3),V(-7.8,2.2,-.7),ember,M.Neon)
 lean(model,"Bellows",V(-10.8,1.7,1.8),V(1.6,1.6,3),leather,pi)
 ball(model,"Coal",2.4,V(-3.4,1.6,.2),dark)
 ball(model,"Coal",1.7,V(-2,1.4,1.5),dark)
 round(model,"AnvilStump",3.2,1.6,V(-6.4,1.7,5.8),timber)
 block(model,"Anvil",V(2.4,.7,1.7),V(-6.4,2.85,5.8),iron,M.Metal)
 block(model,"Anvil",V(4.4,1.2,2),V(-6.4,3.8,5.8),iron,M.Metal)
 block(model,"AnvilHorn",V(1.7,.6,1.1),V(-3.4,4,5.8),iron,M.Metal)
 block(model,"Ingots",V(2.6,.8,1.5),V(-9.8,1.4,9),steel,M.Metal)
 barrel(model,V(-1.2,.9,8.6))
 round(model,"Water",1.8,.15,V(-1.2,3.75,8.6),water)
 -- Finished arms on a rack tilted up at the camera.
 local rack={block(model,"Rack",V(6.6,3.8,.4),V(6.4,2.9,8.8),cutWood,M.WoodPlanks),
  block(model,"Sword",V(.5,3.2,.2),V(6.4,3,9.1),steel,M.Metal),block(model,"SwordHilt",V(1.5,.4,.3),V(6.4,1.9,9.1),gold,M.Metal)}
 for _,x in ipairs({4.4,8.4}) do
  rack[#rack+1]=disc(model,"Shield",2.4,.4,V(x,3,9.15),team,M.WoodPlanks)
  rack[#rack+1]=disc(model,"ShieldBoss",.8,.5,V(x,3,9.25),gold,M.Metal)
 end
 turn(rack,V(6.4,1,8.8),A(-math.rad(28),0,0))
 beam(model,"RackLeg",V(6.4,1,6.4),V(6.4,3.6,7.5),.45,timber,M.Wood)
 disc(model,"Grindstone",3,.7,V(10.3,2.8,4.2),paleStone,M.Slate)
 for _,s in ipairs({-1,1}) do block(model,"GrindFrame",V(.5,2.3,.5),V(10.3,2.05,4.2+s*.8),timber) end
end
-- Arcaded trade hall with a coin-fronted turret and four striped stalls around a cart.
local function stall(model,p,w,team,goods)
 block(model,"Counter",V(w,2.2,2.6),p+V(0,1.1,1.2),cutWood,M.WoodPlanks)
 block(model,"Produce",V(w-.8,.6,2),p+V(0,2.4,1.3),goods,M.Grass)
 for _,s in ipairs({-1,1}) do
  block(model,"Post",V(.4,4.9,.4),p+V(s*(w/2+.1),2.45,2),timber)
  block(model,"Post",V(.4,6,.4),p+V(s*(w/2+.1),3,-2.4),timber)
 end
 local a=block(model,"Awning",V(w+.8,.3,5.2),p+V(0,5.6,-.3),team,M.Fabric)
 a.CFrame*=A(.3,0,0)
 for _,s in ipairs({-1,1}) do
  block(model,"CanopyStripe",V(w*.16,.34,5.2),p,plaster,M.Fabric).CFrame=a.CFrame*CFrame.new(s*w*.27,.03,0)
 end
end
B.Market=function(model,kind,team,stage)
 foundation(model,32,24)
 block(model,"Courtyard",V(7,.25,15),V(0,.9,4.3),paleStone,M.Cobblestone)
 block(model,"Walls",V(18,6.4,7),V(0,4,-7.5),plaster)
 for _,x in ipairs({-5.6,0,5.6}) do arch(model,"Arcade",V(x,.8,-4.05),3.6,5,dark,.3) end
 gable(model,V(0,7.3,-7.5),19.6,8.6,4.4,tile)
 block(model,"Tower",V(3.8,5.6,3.8),V(0,11.6,-7.5),plaster)
 crossGable(model,V(0,14.5,-7.5),5.2,3,tile)
 ball(model,"Finial",.9,V(0,18.2,-7.5),gold,M.Metal)
 disc(model,"Coin",2.2,.3,V(0,12.3,-5.55),gold,M.Metal)
 stall(model,V(-12.4,.8,-7),5.6,team,straw)
 stall(model,V(12.4,.8,-7),5.6,team,leaf)
 stall(model,V(-9.8,.8,3.6),9,team,Color3.fromRGB(170,84,62))
 stall(model,V(9.8,.8,3.6),9,team,Color3.fromRGB(204,140,80))
 block(model,"Cart",V(3.6,1,5.2),V(0,2.5,5.6),cutWood,M.WoodPlanks)
 for _,s in ipairs({-1,1}) do
  plate(model,"CartWheel",3,.5,V(s*2.1,2.4,6),timber)
  beam(model,"CartShaft",V(s*1.2,2.4,8.2),V(s*1.2,1.1,11),.35,timber,M.Wood)
 end
 ball(model,"Sack",2,V(-.5,3.8,4.6),straw,M.Fabric)
 ball(model,"Sack",1.7,V(.6,3.7,6.4),paleStone,M.Fabric)
 barrel(model,V(-14,.8,10))
 block(model,"Crate",V(2.6,2.2,2.6),V(13.8,1.9,9.8),cutWood,M.WoodPlanks)
end
-- Front-gabled barn with open doors, a ram rolling out, a side lean-to and a yard crane.
B.SiegeWorkshop=function(model,kind,team,stage)
 foundation(model,32,24)
 block(model,"Courtyard",V(12.6,.2,23),V(9.6,.9,0),sand,M.Ground)
 block(model,"StoneWall",V(18,4.2,13.4),V(-6,2.9,-4.7),stone,M.Brick)
 block(model,"Walls",V(17.6,5.6,13),V(-6,7.7,-4.7),plank,M.WoodPlanks)
 gable(model,V(-6,10.6,-4.7),14,19.6,6.2,tile,"z")
 gableFace(model,-6,10.6,2.3,19.6,6.2)
 arch(model,"Doorway",V(-6,.8,2.05),8.4,9,dark,.3)
 for _,s in ipairs({-1,1}) do
  block(model,"Post",V(1,9.6,1),V(-6+s*4.9,5.6,2.2),timber)
  block(model,"Door",V(.4,7.6,3.8),V(-6+s*5.2,4.6,4.4),cutWood,M.WoodPlanks)
  shield(model,V(-6+s*7.4,6.6,2.1),2.2,team)
 end
 block(model,"Banner",V(2.4,3.2,.15),V(-6,13.6,2.52),team,M.Fabric)
 -- Ram under construction, nose out of the door.
 block(model,"RamFrame",V(3.4,.7,6.6),V(-6,2.3,5.4),timber)
 for _,s in ipairs({-1,1}) do for _,z in ipairs({3.6,7.2}) do plate(model,"RamWheel",2.6,.5,V(-6+s*2,2.1,z),timber) end end
 for _,z in ipairs({4,7.4}) do for _,s in ipairs({-1,1}) do beam(model,"RamBrace",V(-6+s*1.5,2.6,z),V(-6,6.4,z),.45,cutWood,M.Wood) end end
 block(model,"RamRidge",V(.5,.5,4.4),V(-6,6.4,5.7),cutWood)
 disc(model,"RamLog",1.8,7.6,V(-6,4.2,5.6),cutWood,M.Wood)
 disc(model,"RamHead",2.2,1.2,V(-6,4.2,9.9),iron,M.Metal)
 lean(model,"RoofTile",V(6.4,8.6,-6.5),V(9.6,2.6,6),tile,-pi/2)
 for _,z in ipairs({-2.2,-10.8}) do block(model,"Post",V(.7,6.6,.7),V(9,4.1,z),timber) end
 block(model,"Eave",V(.5,.5,9.8),V(9,7.4,-6.5),timber)
 for _,p in ipairs({V(10.6,1.8,7.6),V(10.6,1.8,9.3),V(10.6,3.2,8.45)}) do plate(model,"Timber",1.6,8,p,cutWood,M.Wood) end
 block(model,"CraneBase",V(3.2,.8,3.2),V(11.6,1.3,0),timber)
 block(model,"Post",V(.9,15,.9),V(11.6,9.2,0),timber)
 beam(model,"CraneJib",V(11.6,12.5,0),V(7.6,19.8,4.6),.8,timber,M.Wood)
 beam(model,"CraneStay",V(11.6,16.6,0),V(7.8,19.6,4.4),.3,straw)
 beam(model,"TimberBrace",V(14.4,1.6,0),V(11.6,8,0),.6,timber,M.Wood)
 block(model,"Rope",V(.25,9,.25),V(7.6,15.3,4.6),straw)
 block(model,"HoistLoad",V(4,1.3,1.3),V(7.6,10.2,4.6),cutWood,M.Wood)
 block(model,"Flag",V(2.4,1.5,.15),V(13,15.6,0),team,M.Fabric)
 for _,p in ipairs({V(14,1.6,4),V(15,1.6,5.2),V(13.8,1.6,5.5)}) do ball(model,"Shot",1.5,p,stone,M.Slate) end
 block(model,"Crate",V(3,3,3),V(13.8,2.3,-5.2),cutWood,M.WoodPlanks)
 disc(model,"SpareWheel",3.6,.5,V(13.8,2.7,-3.4),timber)
 disc(model,"WheelHub",1.1,.6,V(13.8,2.7,-3.35),iron,M.Metal)
end
-- Pale stone college: domed rotunda with a lantern, columned portico and two gabled wings.
B.University=function(model,kind,team,stage)
 foundation(model,32,32)
 block(model,"Courtyard",V(30,.2,5.6),V(0,.9,13),paleStone,M.Cobblestone)
 block(model,"Walls",V(30,9,8),V(0,5.3,-11.4),paleStone)
 gable(model,V(0,9.9,-11.4),31,8.8,4,tile)
 for _,s in ipairs({-1,1}) do
  local x=s*11.4
  block(model,"Walls",V(7.6,8,16.4),V(x,4.8,.8),paleStone)
  gable(model,V(x,8.9,-.8),21.2,8.8,3.6,tile,"z")
  gableFace(model,x,8.9,9.8,8.8,3.6,plaster)
  arch(model,"Window",V(x,3,9.05),2.4,4.6,dark,.25)
  for _,dx in ipairs({-2.6,2.6}) do block(model,"Banner",V(1.2,4.2,.15),V(x+dx,5.6,9.1),team,M.Fabric) end
  local a=s*.78
  block(model,"Window",V(1.5,3,.3),V(math.sin(a)*6.5,12.2,-2.5+math.cos(a)*6.5),dark).CFrame*=A(0,a,0)
  block(model,"Banner",V(1.6,4,.15),V(s*3.4,7.4,10.2),team,M.Fabric)
  block(model,"Hedge",V(1.5,1.5,4.2),V(s*6,1.6,13.4),leafDark,M.Grass)
 end
 round(model,"Tower",13,14,V(0,7.8,-2.5),paleStone,M.Concrete)
 round(model,"StoneCourse",14,.8,V(0,14.9,-2.5),stone)
 ball(model,"RoofTile",12.6,V(0,15.3,-2.5),verdigris,M.Metal)
 round(model,"Lantern",3.2,2.6,V(0,22.4,-2.5),paleStone,M.Concrete)
 cone(model,"Spire",V(0,23.7,-2.5),3.8,1.5,2,verdigris,M.Metal)
 ball(model,"Finial",.8,V(0,25.5,-2.5),gold,M.Metal)
 block(model,"Step",V(13,1.8,7.6),V(0,1.7,7.4),paleStone)
 for _,x in ipairs({-5,-1.8,1.8,5}) do round(model,"StoneColumn",1.3,7,V(x,6.1,10.2),plaster,M.Marble) end
 block(model,"Beam",V(13,1,6.4),V(0,10.1,7.8),paleStone)
 gable(model,V(0,10.7,7.8),6.8,13,3,tile,"z")
 gableFace(model,0,10.7,11.2,13,3,paleStone)
 disc(model,"Emblem",1.6,.3,V(0,11.6,11.35),gold,M.Metal)
 arch(model,"Door",V(0,2.6,4.1),3,5,dark,.3)
 stairs(model,V(0,.8,14),9,3)
 block(model,"Pedestal",V(2,1.6,2),V(-11.4,1.6,13),paleStone)
 ball(model,"Armillary",1.6,V(-11.4,4,13),gold,M.Metal)
 disc(model,"ArmillaryRing",3.2,.25,V(-11.4,4,13),gold,M.Metal)
 plate(model,"ArmillaryRing",3.2,.25,V(-11.4,4,13),gold,M.Metal)
 round(model,"ArmillaryRing",3.2,.25,V(-11.4,4,13),gold,M.Metal)
 round(model,"Trunk",.9,3,V(11.4,2.3,13),timber)
 ball(model,"Canopy",4.2,V(11.4,5.2,13),leaf,M.Grass)
 ball(model,"Canopy",2.8,V(12.6,6.4,12.4),leafLight,M.Grass)
end
return B
