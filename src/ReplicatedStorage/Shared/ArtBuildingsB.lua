-- Fallback art: religious, gathering, defensive and monument buildings. Front faces +Z.
local K=require(script.Parent.ArtKit)
local stone,paleStone,timber,cutWood,plaster,roof,iron,dark,straw,gold=K.stone,K.paleStone,K.timber,K.cutWood,K.plaster,K.roof,K.iron,K.dark,K.straw,K.gold
local block,beam,round,disc,ball,segment,plate,point,turn=K.block,K.beam,K.round,K.disc,K.ball,K.segment,K.plate,K.point,K.turn
local roofAt,foundation,hall,door,window,banner,stairs,fence,barrel,chimney,tower=K.roofAt,K.foundation,K.hall,K.door,K.window,K.banner,K.stairs,K.fence,K.barrel,K.chimney,K.tower
local tile,tileDark,thatch,thatchDark,wallShade,earth,leaf,leafDark,leafLight,steel,skin,leather=K.tile,K.tileDark,K.thatch,K.thatchDark,K.wallShade,K.earth,K.leaf,K.leafDark,K.leafLight,K.steel,K.skin,K.leather
local cone=K.cone
local B={}
local V=Vector3.new
local M=Enum.Material
local sawdust=Color3.fromRGB(176,148,104)
local plank=Color3.fromRGB(132,94,58)
local flagstone=Color3.fromRGB(186,176,154)
-- Solid gable (two wedges and a team ridge unless bare) for secondary roofs.
local function gable(model,center,width,depth,height,color,axis,bare)
 local parts={}
 for _,side in ipairs({-1,1}) do
  local p=block(model,"RoofTile",V(width,height,depth/2),center+V(0,0,side*depth/4),color,K.roofMaterial(color),"WedgePart")
  if side>0 then p.CFrame*=CFrame.Angles(0,math.pi,0) end
  table.insert(parts,p)
 end
 if not bare then table.insert(parts,block(model,"Ridge",V(width+.4,.6,1.1),center+V(0,height/2+.05,0),color,M.Fabric)) end
 if axis=="z" then turn(parts,center,CFrame.Angles(0,math.pi/2,0)) end
end
local function flag(model,pos,height,team,dir)
 block(model,"Flagpole",V(.3,height,.3),pos+V(0,height/2,0),timber)
 block(model,"Flag",V(2.6,1.7,.16),pos+V((dir or 1)*1.45,height-.95,0),team,M.Fabric)
end
-- Church with a tall slate nave, a bell tower behind it and a walled cloister garden.
B.Monastery=function(model,kind,team,stage)
 foundation(model,23,23)
 local n=V(-6,.8,-1.5)
 block(model,"StonePlinth",V(9.2,1.3,17.8),n+V(0,.65,0),stone,M.Cobblestone)
 block(model,"Walls",V(8.4,10,17),n+V(0,5,0),plaster,M.Concrete)
 roofAt(model,n+V(0,12.75,0),18.8,10.4,5.5,roof,plaster,"z")
 door(model,V(-6,.8,7),2.6,5)
 disc(model,"RoseFrame",3.6,.3,V(-6,9,7.05),gold,M.Metal)
 disc(model,"Window",2.6,.3,V(-6,9,7.15),dark)
 block(model,"Finial",V(.5,3,.5),V(-6,18.3,7.6),gold,M.Metal)
 block(model,"Finial",V(1.9,.5,.5),V(-6,18.7,7.6),gold,M.Metal)
 for i=1,2 do block(model,"Step",V(4.6,.4*i,1.5),V(-6,.8+.2*i,10.1-1.3*i),paleStone,M.Concrete) end
 for _,z in ipairs({-6,-1.5,3}) do block(model,"Buttress",V(1,7.5,1.3),V(-10.6,4.5,z),stone,M.Brick) end
 -- Bell tower.
 local t=V(1.8,.8,-7)
 block(model,"BellTower",V(6.6,14,6.6),t+V(0,7,0),paleStone,M.Brick)
 block(model,"StoneCourse",V(7.2,.7,7.2),t+V(0,14.2,0),stone,M.Concrete)
 for _,x in ipairs({-2.7,2.7}) do for _,z in ipairs({-2.7,2.7}) do
  block(model,"StoneColumn",V(1.1,4,1.1),t+V(x,16.5,z),paleStone,M.Concrete)
 end end
 round(model,"Bell",2.8,2.4,t+V(0,16.9,0),gold,M.Metal)
 block(model,"BellTower",V(7.2,.9,7.2),t+V(0,18.9,0),paleStone,M.Concrete)
 -- Crossed gables make a four-sided helm roof.
 gable(model,t+V(0,22.35,0),7.6,7.6,6,roof,nil,true)
 gable(model,t+V(0,22.35,0),7.6,7.6,6,roof,"z",true)
 block(model,"Finial",V(.45,1.8,.45),t+V(0,26.3,0),gold,M.Metal)
 block(model,"Finial",V(1.5,.45,.45),t+V(0,26.5,0),gold,M.Metal)
 block(model,"Window",V(1.3,3,.2),t+V(0,10.5,3.32),dark)
 block(model,"Banner",V(2.6,4.6,.18),t+V(0,5.4,3.4),team,M.Fabric)
 -- Cloister: lean-to walks on two sides of a green garth.
 block(model,"Courtyard",V(12.6,.3,14.4),V(4.9,.95,4),leaf,M.Grass)
 block(model,"StoneWall",V(13,4.4,.8),V(4.9,3,10.9),paleStone,M.Brick)
 block(model,"StoneWall",V(.8,4.4,14.6),V(10.9,3,3.9),paleStone,M.Brick)
 local r=block(model,"RoofTile",V(13.4,.5,3.2),V(4.9,4.9,9.7),roof,M.Slate)
 r.CFrame*=CFrame.Angles(-.35,0,0)
 r=block(model,"RoofTile",V(3.2,.5,12.6),V(9.7,4.9,2.6),roof,M.Slate)
 r.CFrame*=CFrame.Angles(0,0,.35)
 for _,x in ipairs({-.6,2.2,5,7.8}) do block(model,"StoneColumn",V(.7,3.4,.7),V(x,2.5,8.3),paleStone,M.Concrete) end
 for _,z in ipairs({-2.6,.2,3,5.8}) do block(model,"StoneColumn",V(.7,3.4,.7),V(8.3,2.5,z),paleStone,M.Concrete) end
 block(model,"TeamTrim",V(13.4,.4,.9),V(4.9,5.5,10.95),team,M.Fabric)
 block(model,"GateRecess",V(2.4,3.2,.2),V(3.6,2.4,11.32),dark)
 block(model,"GardenPath",V(1.3,.12,9),V(3.6,1.15,3),paleStone,M.Concrete)
 block(model,"GardenPath",V(8.6,.12,1.3),V(3.6,1.15,3),paleStone,M.Concrete)
 round(model,"Well",2.6,1.3,V(3.6,1.7,3),stone,M.Cobblestone)
 round(model,"WellWater",1.7,.1,V(3.6,2.38,3),dark)
 for _,p in ipairs({V(.8,0,5.8),V(6.4,0,.2)}) do
  round(model,"Trunk",.6,1.2,p+V(0,1.6,0),timber)
  cone(model,"Cypress",p+V(0,2.1,0),2.3,4.4,3,leafDark,M.Grass)
 end
 block(model,"Herbs",V(2.2,.5,2.2),V(.9,1.3,.3),leafLight,M.Grass)
 block(model,"Herbs",V(2.2,.5,2.2),V(6.3,1.3,5.7),leafLight,M.Grass)
end
-- Tapered round windmill; the four big canvas sails on the front are the signature.
B.Mill=function(model,kind,team,stage)
 foundation(model,15.6,15.6)
 local c=V(-1,0,-2.6)
 round(model,"WindmillTower",8.6,5,c+V(0,3.3,0),stone,M.Cobblestone)
 round(model,"WindmillTower",7.6,4.4,c+V(0,8,0),plaster,M.Concrete)
 round(model,"WindmillTower",6.8,3.6,c+V(0,12,0),plaster,M.Concrete)
 round(model,"TimberBand",8,.5,c+V(0,5.9,0),timber)
 round(model,"TimberBand",7.1,.45,c+V(0,10.2,0),timber)
 cone(model,"RoofTile",c+V(0,13.8,0),8,4.8,4,thatch)
 ball(model,"Finial",1,c+V(0,18.8,0),timber)
 door(model,c+V(0,.8,4.25),2.2,4)
 -- Granary wing.
 block(model,"Storehouse",V(5.4,4.4,7.2),V(4.7,3,-3.6),plaster,M.Concrete)
 block(model,"Beam",V(5.7,.5,7.5),V(4.7,5,-3.6),timber)
 gable(model,V(4.7,6.6,-3.6),8.4,6.4,2.8,thatch,"z")
 block(model,"Window",V(1.6,1.6,.2),V(4.9,3.2,.02),dark)
 local hub=c+V(0,12.3,4.6)
 disc(model,"SailAxle",1.1,1.8,hub+V(0,0,-.8),timber)
 disc(model,"SailHub",1.7,.5,hub+V(0,0,.25),gold,M.Metal)
 for i=0,3 do
  local a=math.rad(24)+i*math.pi/2
  local dir=V(math.sin(a),math.cos(a),0)
  local side=V(math.cos(a),-math.sin(a),0)
  beam(model,"SailSpar",hub,hub+dir*7,.4,timber)
  local sail=block(model,"CanvasSail",V(2.6,5.2,.18),hub+dir*4.3+side*1.3,team,M.Fabric)
  sail.CFrame*=CFrame.Angles(0,0,-a)
  for _,d in ipairs({2.5,6.1}) do
   local batten=block(model,"SailBatten",V(2.9,.25,.3),hub+dir*d+side*1.25,cutWood)
   batten.CFrame*=CFrame.Angles(0,0,-a)
  end
 end
 -- Yard: millstone, flour sacks and a strip of wheat.
 round(model,"Grindstone",3.2,.8,V(4.9,1.2,4.9),paleStone,M.Concrete)
 round(model,"GrindstoneEye",.9,.1,V(4.9,1.62,4.9),dark)
 ball(model,"GrainSack",1.9,V(-5.6,1.6,4.2),straw,M.Fabric)
 ball(model,"GrainSack",1.9,V(-4.1,1.6,5.6),straw,M.Fabric)
 ball(model,"GrainSack",1.6,V(-5.9,1.5,6.1),wallShade,M.Fabric)
 for _,x in ipairs({-6.6,-5.4}) do block(model,"Wheat",V(.8,1.5,5),V(x,1.5,-3.5),straw,M.Grass) end
end
-- Plank lean-to on a sawdust yard with a log pyramid and a sawhorse.
B.LumberCamp=function(model,kind,team,stage)
 block(model,"Foundation",V(15.6,.6,15.6),V(0,.3,0),sawdust,M.Ground)
 for _,x in ipairs({-6.6,6.6}) do
  block(model,"Post",V(.7,8.6,.7),V(x,4.9,-7),timber)
  block(model,"Post",V(.7,5,.7),V(x,3.1,-.6),timber)
 end
 block(model,"Storehouse",V(13.2,5.4,.5),V(0,3.3,-7.1),cutWood,M.WoodPlanks)
 local slope=math.atan(3.6/7.2)
 local r=block(model,"RoofTile",V(15.4,.6,8.4),V(0,7.7,-3.8),plank,M.WoodPlanks)
 r.CFrame*=CFrame.Angles(slope,0,0)
 for _,x in ipairs({-5,0,5}) do
  r=block(model,"RoofFascia",V(.6,.3,8.6),V(x,8.15,-3.8),timber)
  r.CFrame*=CFrame.Angles(slope,0,0)
 end
 block(model,"Ridge",V(15.6,.7,1),V(0,9.9,-7.3),team,M.Fabric)
 block(model,"PlankStack",V(8,1.8,3.4),V(-1.6,1.5,-4.4),cutWood,M.WoodPlanks)
 block(model,"PlankStack",V(5,1,3),V(-2.6,2.9,-4.4),plank,M.WoodPlanks)
 -- Log pyramid with pale cut ends facing the camera.
 for _,l in ipairs({{-6.3,1.6},{-4.3,1.6},{-2.3,1.6},{-5.3,3.3},{-3.3,3.3},{-4.3,5}}) do
  disc(model,"TimberPile",2,6,V(l[1],l[2],4.2),timber,M.Wood)
  disc(model,"LogEnd",1.55,.2,V(l[1],l[2],7.25),cutWood,M.Wood)
 end
 -- Sawhorse with a half-cut log.
 for _,x in ipairs({2.2,6}) do
  beam(model,"Sawhorse",V(x,.6,2.2),V(x,3.2,4.4),.45,timber)
  beam(model,"Sawhorse",V(x,.6,4.4),V(x,3.2,2.2),.45,timber)
 end
 plate(model,"Log",1.7,6.6,V(4.1,3.5,3.3),cutWood,M.Wood)
 block(model,"Saw",V(.2,1.5,4.6),V(4.6,4.5,3.3),steel,M.Metal)
 for _,z in ipairs({.9,5.7}) do block(model,"SawHandle",V(.5,1.9,.4),V(4.6,4.5,z),timber) end
 round(model,"Stump",2.1,1.3,V(2,1.25,6.5),cutWood,M.Wood)
 beam(model,"AxeHandle",V(2,1.9,6.5),V(3.4,3.6,6.9),.3,timber)
 block(model,"AxeHead",V(1.1,.9,.3),V(2.1,2.2,6.5),steel,M.Metal)
 flag(model,V(7.2,.6,-.6),10.4,team,-1)
end
-- Stone hut under thatch beside a pit-head hoist, with a cart on rails and ore heaps.
B.MiningCamp=function(model,kind,team,stage)
 foundation(model,15.6,15.6)
 block(model,"StoneWall",V(7,4.4,6.4),V(-3.6,3,-3.8),stone,M.Cobblestone)
 roofAt(model,V(-3.6,6.8,-3.8),7.6,8,3.2,thatch,stone,"z")
 block(model,"DoorRecess",V(2.6,3.2,.2),V(-3.6,2.4,-.62),dark)
 -- Hoist over the shaft.
 local s=V(4.4,.8,-3.8)
 round(model,"StoneWall",5.4,1.5,s+V(0,.75,0),paleStone,M.Cobblestone)
 round(model,"Shaft",3.9,.1,s+V(0,1.52,0),dark)
 for _,x in ipairs({-2.9,2.9}) do block(model,"Post",V(.7,7.2,.7),s+V(x,3.6,0),timber) end
 block(model,"Beam",V(7,.7,.9),s+V(0,7.5,0),timber)
 plate(model,"Windlass",1.5,5,s+V(0,5.3,0),cutWood,M.Wood)
 block(model,"Rope",V(.2,2.2,.2),s+V(0,4.2,0),straw)
 round(model,"Bucket",1.5,1.3,s+V(0,2.6,0),iron,M.Metal)
 block(model,"Flag",V(2.4,1.5,.16),s+V(1.3,9.3,0),team,M.Fabric)
 block(model,"Flagpole",V(.3,2.6,.3),s+V(0,9.1,0),timber)
 -- Cart track running out of the yard.
 for _,x in ipairs({.3,2.5}) do block(model,"Rail",V(.3,.25,8.2),V(x,.92,3.6),iron,M.Metal) end
 for _,z in ipairs({1,3.6,6.2}) do block(model,"Sleeper",V(3.6,.2,.7),V(1.4,.86,z),timber) end
 block(model,"OreCart",V(2.9,1.7,3.8),V(1.4,2.5,3.4),cutWood,M.WoodPlanks)
 for _,z in ipairs({2.2,4.6}) do plate(model,"CartWheel",1.5,3.4,V(1.4,1.75,z),iron,M.Metal) end
 ball(model,"Ore",2,V(1.4,3.5,2.7),gold,M.Metal)
 ball(model,"Ore",1.7,V(1.5,3.4,4.2),gold,M.Metal)
 -- Sorted heaps: stone on the left, gold on the right.
 for i,h in ipairs({{V(3.2,1.6,2.6),V(-4.8,1.6,3.2)},{V(2.1,1.3,2),V(-4.4,3.05,3.1)},{V(2.2,1.3,2),V(-5.4,1.45,6)}}) do
  block(model,"StoneHeap",h[1],h[2],i==1 and paleStone or stone,M.Slate).CFrame*=CFrame.Angles(0,i*.5,0)
 end
 ball(model,"GoldHeap",2.2,V(5.4,1.7,3.4),gold,M.Metal)
 ball(model,"GoldHeap",1.8,V(6.1,1.5,5.2),gold,M.Metal)
 ball(model,"GoldHeap",1.5,V(4.7,1.4,5.4),gold,M.Metal)
end
-- Round watchtower: battered base, crenellated gallery and a slate cap with a flag.
B.Tower=function(model,kind,team,stage)
 foundation(model,15,15)
 round(model,"Tower",12,5.6,V(0,3.6,0),stone,M.Cobblestone)
 round(model,"Tower",10.2,11.4,V(0,12.1,0),stone,M.Brick)
 round(model,"StoneCourse",10.8,.6,V(0,6.7,0),paleStone,M.Concrete)
 round(model,"TeamTrim",10.7,.7,V(0,15.6,0),team,M.Fabric)
 round(model,"Corbel",12,1.1,V(0,18.3,0),stone,M.Brick)
 round(model,"Parapet",13.6,1.5,V(0,19.6,0),paleStone,M.Concrete)
 round(model,"TowerDeck",11.4,.2,V(0,20.4,0),dark,M.Slate)
 for i=0,7 do
  local a=i*math.pi/4
  local p=block(model,"Battlement",V(2.7,1.9,1.5),V(math.sin(a)*6,21.3,math.cos(a)*6),paleStone,M.Brick)
  p.CFrame*=CFrame.Angles(0,a,0)
 end
 round(model,"Tower",6.6,3.4,V(0,22,0),stone,M.Brick)
 cone(model,"RoofTile",V(0,23.7,0),8.8,4,4,roof)
 flag(model,V(0,27.6,0),2.4,team)
 door(model,V(0,.8,5.95),2.4,4.2)
 block(model,"Step",V(4.4,.4,1.6),V(0,1,6.7),paleStone,M.Concrete)
 block(model,"ArrowSlit",V(.5,2.6,.2),V(0,9.6,5.05),dark)
 block(model,"Banner",V(2.4,4.4,.18),V(0,12.6,5.15),team,M.Fabric)
end
-- One square cell with merlons on its corners, so rows along X or Z join into a crenellated wall.
B.Wall=function(model,kind,team,stage)
 block(model,"Foundation",V(8,1.4,8),V(0,.7,0),stone,M.Cobblestone)
 block(model,"StoneWall",V(8,6.6,8),V(0,4.7,0),stone,M.Brick)
 block(model,"TeamTrim",V(8,.5,8),V(0,8.25,0),team,M.Fabric)
 block(model,"Parapet",V(8,2.5,8),V(0,9.75,0),paleStone,M.Brick)
 block(model,"Walkway",V(8,.1,3.6),V(0,11.05,0),stone,M.Slate)
 block(model,"Walkway",V(3.6,.14,8),V(0,11.07,0),stone,M.Slate)
 for _,x in ipairs({-3,3}) do for _,z in ipairs({-3,3}) do
  block(model,"Battlement",V(2,2,2),V(x,12,z),paleStone,M.Brick)
 end end
end
-- Gatehouse over three wall cells along X: two piers, a parapet bridge and a portcullis.
-- The client raises every "GateDoor" part into the bridge while friendly units are near.
B.Gate=function(model,kind,team,stage)
 block(model,"Foundation",V(24,.5,8),V(0,.25,0),stone,M.Cobblestone)
 for _,s in ipairs({-1,1}) do
  block(model,"GatePier",V(4,14,8),V(s*10,7,0),stone,M.Brick)
  for _,x in ipairs({8.8,11.2}) do for _,z in ipairs({-3,3}) do
   block(model,"Battlement",V(1.6,2,2),V(s*x,15,z),paleStone,M.Brick)
  end end
 end
 block(model,"StoneWall",V(16,2.5,8),V(0,9.75,0),stone,M.Brick)
 block(model,"TeamTrim",V(16,.5,8),V(0,11.25,0),team,M.Fabric)
 block(model,"Parapet",V(16,2,8),V(0,12.5,0),paleStone,M.Brick)
 -- Seen from the top-down camera the passage is hidden, so the deck carries the team colour.
 block(model,"TeamTrim",V(16,.16,4),V(0,13.58,0),team,M.Fabric)
 for _,s in ipairs({-1,1}) do block(model,"TeamTrim",V(2.4,.16,4),V(s*10,14.08,0),team,M.Fabric) end
 for _,x in ipairs({-6,-2,2,6}) do for _,z in ipairs({-3,3}) do
  block(model,"Battlement",V(2,2,2),V(x,14.5,z),paleStone,M.Brick)
 end end
 block(model,"GateDoor",V(16,8,1),V(0,4.5,0),cutWood,M.WoodPlanks)
 for _,y in ipairs({2.5,6.5}) do block(model,"GateDoor",V(16,.5,1.3),V(0,y,0),iron,M.Metal) end
 for _,x in ipairs({-5.5,0,5.5}) do block(model,"GateDoor",V(.5,8,1.3),V(x,4.5,0),iron,M.Metal) end
end
-- Curtain walls, four capped corner towers, a gatehouse on +Z and a tall keep with bartizans.
B.Castle=function(model,kind,team,stage)
 local w=26
 block(model,"Foundation",V(62,1,62),V(0,.5,0),stone,M.Cobblestone)
 block(model,"Courtyard",V(50,.3,50),V(0,1.15,0),flagstone,M.Ground)
 for _,s in ipairs({-1,1}) do
  block(model,"StoneWall",V(4.5,13,52),V(s*w,7.5,0),stone,M.Brick)
  block(model,"StoneWall",V(15,13,4.5),V(s*16,7.5,w),stone,M.Brick)
  for z=-16,16,8 do block(model,"Battlement",V(1.5,2.2,3.6),V(s*(w+1.5),15.1,z),paleStone,M.Brick) end
  for _,x in ipairs({13,19}) do block(model,"Battlement",V(3.6,2.2,1.5),V(s*x,15.1,w+1.5),paleStone,M.Brick) end
 end
 block(model,"StoneWall",V(52,13,4.5),V(0,7.5,-w),stone,M.Brick)
 for x=-16,16,8 do block(model,"Battlement",V(3.6,2.2,1.5),V(x,15.1,-w-1.5),paleStone,M.Brick) end
 for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
  local p=V(sx*w,0,sz*w)
  round(model,"Tower",10.5,22,p+V(0,12,0),stone,M.Brick)
  round(model,"Parapet",12,2,p+V(0,24,0),paleStone,M.Concrete)
  cone(model,"RoofTile",p+V(0,25,0),11.4,7.5,4,roof)
  if sz>0 then flag(model,p+V(0,32.3,0),5,team,sx) else ball(model,"Finial",1.3,p+V(0,32.9,0),gold,M.Metal) end
 end end
 -- Keep.
 local k=V(0,0,-6)
 block(model,"StonePlinth",V(27,4,23),k+V(0,3,0),stone,M.Cobblestone)
 block(model,"Keep",V(23,29,19),k+V(0,15.5,0),paleStone,M.Brick)
 block(model,"StoneCourse",V(23.6,.9,19.6),k+V(0,19,0),stone,M.Concrete)
 block(model,"Parapet",V(26,2.2,22),k+V(0,31.1,0),paleStone,M.Brick)
 for _,x in ipairs({-5,0,5}) do block(model,"Battlement",V(2.8,2.2,1.6),k+V(x,33.3,10.2),paleStone,M.Brick) end
 for _,s in ipairs({-1,1}) do for _,z in ipairs({-3.5,3.5}) do
  block(model,"Battlement",V(1.6,2.2,2.8),k+V(s*12.2,33.3,z),paleStone,M.Brick)
 end end
 roofAt(model,k+V(0,36.2,0),20,16,8,roof,paleStone)
 banner(model,k+V(0,40.4,0),team,7)
 for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
  local p=k+V(sx*11.5,0,sz*9.5)
  round(model,"Tower",6.5,16,p+V(0,30,0),stone,M.Brick)
  cone(model,"RoofTile",p+V(0,38,0),7.4,6,2,roof)
 end end
 for _,x in ipairs({-6.5,0,6.5}) do block(model,"Window",V(2.2,4.6,.3),k+V(x,24.5,9.55),dark) end
 for _,x in ipairs({-6.5,6.5}) do block(model,"Banner",V(3.2,9,.2),k+V(x,12.5,9.62),team,M.Fabric) end
 block(model,"DoorRecess",V(4.4,6.5,.3),k+V(0,8.2,9.56),dark)
 block(model,"Step",V(6.5,2.2,3.6),k+V(0,2.1,13),paleStone,M.Concrete)
 -- Gatehouse.
 for _,s in ipairs({-1,1}) do
  block(model,"GatePier",V(7,21,9),V(s*7.5,11.5,w+.5),paleStone,M.Brick)
  block(model,"Banner",V(2.8,7,.2),V(s*7.5,14.5,w+5.1),team,M.Fabric)
 end
 block(model,"GateArch",V(8,9,7),V(0,17.5,w),paleStone,M.Brick)
 block(model,"GateRecess",V(8,12,.4),V(0,7,w-1),dark)
 for _,x in ipairs({-2,0,2}) do block(model,"Portcullis",V(.45,12,.45),V(x,7,w+1.6),iron,M.Metal) end
 block(model,"Portcullis",V(8,.45,.45),V(0,8,w+1.6),iron,M.Metal)
 block(model,"Parapet",V(23,1.6,10.4),V(0,22.8,w+.5),stone,M.Brick)
 for x=-10,10,5 do block(model,"Battlement",V(2.6,2.2,1.6),V(x,24.7,w+4.9),paleStone,M.Brick) end
 gable(model,V(0,25.35,w-.5),14,6,3.5,roof)
 block(model,"Drawbridge",V(7.4,.5,6),V(0,1.25,w+2.6),cutWood,M.WoodPlanks)
 -- Bailey: a tiled hall on one side, a well on the other.
 block(model,"Storehouse",V(7,5,14),V(-18.5,3.8,-6),plaster,M.Concrete)
 gable(model,V(-18.5,7.8,-6),15,8.4,3,tile,"z")
 round(model,"Well",4,1.6,V(18.5,2.1,-2),paleStone,M.Cobblestone)
 round(model,"WellWater",2.8,.1,V(18.5,2.92,-2),dark)
end
-- Domed temple on a stepped terrace: gilded dome and lantern, four minarets, columned porch.
B.Wonder=function(model,kind,team,stage)
 block(model,"Courtyard",V(54,1.4,54),V(0,.7,0),stone,M.Marble)
 block(model,"Foundation",V(46,1.8,46),V(0,2.3,-2),paleStone,M.Marble)
 for i=1,2 do block(model,"Step",V(20,.6*i,3.6-1.7*(i-1)),V(0,1.4+.3*i,22.8-.85*(i-1)),paleStone,M.Marble) end
 local c=V(0,3.2,-3)
 block(model,"Temple",V(30,20,30),c+V(0,10,0),paleStone,M.Marble)
 block(model,"Cornice",V(31.2,.8,31.2),c+V(0,20.4,0),gold,M.Metal)
 block(model,"RoofTile",V(28,1.2,28),c+V(0,21.4,0),roof,M.Slate)
 block(model,"RoofTile",V(23,1.2,23),c+V(0,22.6,0),roof,M.Slate)
 round(model,"Temple",20,8,c+V(0,27.2,0),paleStone,M.Marble)
 round(model,"TeamTrim",20.8,.9,c+V(0,23.75,0),team,M.Fabric)
 round(model,"GildedCap",20.6,.8,c+V(0,30.8,0),gold,M.Metal)
 for i=0,7 do
  local a=(i+.5)*math.pi/4
  local p=block(model,"Window",V(1.6,3.6,.3),c+V(math.sin(a)*9.95,27,math.cos(a)*9.95),dark)
  p.CFrame*=CFrame.Angles(0,a,0)
 end
 ball(model,"GildedCap",20,c+V(0,31.2,0),gold,M.Metal)
 round(model,"Spire",4.6,4,c+V(0,42.4,0),paleStone,M.Marble)
 cone(model,"GildedCap",c+V(0,44.4,0),5,6,3,gold,M.Metal)
 block(model,"Finial",V(.6,3,.6),c+V(0,51.9,0),gold,M.Metal)
 -- Small gilded cupolas on the roof corners.
 for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
  local p=c+V(sx*11.5,22,sz*11.5)
  round(model,"Cupola",3.6,3,p+V(0,1.5,0),paleStone,M.Marble)
  ball(model,"GildedCap",3.6,p+V(0,3,0),gold,M.Metal)
 end end
 -- Minarets.
 for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
  local p=c+V(sx*19.5,0,sz*19)
  round(model,"Tower",6,30,p+V(0,15,0),paleStone,M.Marble)
  round(model,"GildedCap",7.4,1.1,p+V(0,30.5,0),gold,M.Metal)
  cone(model,"RoofTile",p+V(0,31,0),7,7,4,roof)
  ball(model,"Finial",1.5,p+V(0,38.6,0),gold,M.Metal)
 end end
 -- Side apses under slate half-domes.
 for _,s in ipairs({-1,1}) do
  round(model,"Temple",14,14,c+V(s*15,7,0),paleStone,M.Marble)
  ball(model,"RoofTile",14,c+V(s*15,14,0),roof,M.Slate)
 end
 -- Porch.
 for _,x in ipairs({-10,-6,-2,2,6,10}) do
  round(model,"StoneColumn",1.7,12.4,V(x,9.4,17.5),paleStone,M.Marble)
  block(model,"ColumnCapital",V(2.3,.6,2.3),V(x,15.9,17.5),gold,M.Metal)
 end
 block(model,"Beam",V(23.4,1.4,7.4),V(0,16.9,15.4),paleStone,M.Marble)
 gable(model,V(0,20.1,15.4),7.8,24,5,roof,"z")
 block(model,"DoorRecess",V(6.4,11,.4),V(0,8.7,12.1),dark)
 block(model,"Door",V(5,9.6,.4),V(0,8,12.3),gold,M.Metal)
 block(model,"TeamTrim",V(5,.12,9),V(0,3.26,16.5),team,M.Fabric)
 -- Forecourt: bannered obelisks, gilded braziers and hedges.
 for _,s in ipairs({-1,1}) do
  block(model,"Hedge",V(2.2,1.5,34),V(s*25.2,2.15,-4),leafDark,M.Grass)
  block(model,"Window",V(1.6,7,.3),c+V(s*13.2,10,15.02),dark)
  block(model,"Obelisk",V(2.6,12,2.6),V(s*23,7.4,24.4),paleStone,M.Marble)
  block(model,"GildedCap",V(3.1,1.2,3.1),V(s*23,14,24.4),gold,M.Metal)
  block(model,"Banner",V(2,5.5,.18),V(s*23,9,25.8),team,M.Fabric)
  round(model,"Pedestal",2.6,2.2,V(s*12.5,2.5,24.2),paleStone,M.Marble)
  ball(model,"GildedCap",2.4,V(s*12.5,4.4,24.2),gold,M.Metal)
 end
end
-- Harvest sweeps across the seven rows: ripe wheat, then pale stubble, then bare fallow furrows.
B.Farm=function(model,kind,team,stage)
 local fallow=stage>=3
 block(model,"Soil",V(23.4,.4,23.4),V(0,.2,0),fallow and Color3.fromRGB(100,76,52) or Color3.fromRGB(128,96,60),M.Ground)
 local harvested=({[0]=0,2,5,7})[stage] or 0
 for row=1,7 do
  local x=-12+row*3
  if row>harvested then
   block(model,"CropRow",V(2.4,.7,21.6),V(x,.75,0),row%2==0 and Color3.fromRGB(206,170,72) or Color3.fromRGB(222,188,88),M.Grass)
   block(model,"CropEars",V(1.1,.1,21.6),V(x,1.15,0),Color3.fromRGB(230,202,110),M.Grass)
  else
   block(model,"Furrow",V(1.7,.1,21.6),V(x,.45,0),Color3.fromRGB(78,58,40),M.Ground)
   if not fallow then block(model,"Stubble",V(.6,.2,21.6),V(x,.55,0),Color3.fromRGB(190,170,116),M.Grass) end
  end
 end
 if harvested>0 and not fallow then block(model,"Sheaf",V(1.6,.7,2.6),V(-12+harvested*3,.75,7.5),straw,M.Grass) end
 for _,side in ipairs({-1,1}) do
  block(model,"FieldBorder",V(.5,.4,23.4),V(side*11.45,.6,0),cutWood,M.Wood)
  block(model,"FieldBorder",V(22.4,.4,.5),V(0,.6,side*11.45),cutWood,M.Wood)
  block(model,"TeamTrim",V(1.4,.8,1.4),V(side*11,.8,11),team,M.Fabric)
 end
end
return B
