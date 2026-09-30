-- All geometry is local, original, and self-contained. Used for fallback models and HUD previews.
local Art={}
local stone=Color3.fromRGB(174,170,145)
local timber=Color3.fromRGB(90,65,46)
local plaster=Color3.fromRGB(220,202,160)
local roof=Color3.fromRGB(66,96,109)
local function block(model,name,size,pos,color,material,class)
 local p=Instance.new(class or "Part")
 p.Name,p.Size,p.CFrame=name,size,CFrame.new(pos)
 p.Color,p.Material=color,material or Enum.Material.SmoothPlastic
 p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,false,false,true
 p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
 p.Parent=model
 return p
end
local function roofAt(model,center,width,depth,height,color)
 for _,side in ipairs({-1,1}) do
  local p=block(model,"Roof",Vector3.new(width,height,depth/2),center+Vector3.new(0,0,side*depth/4),color,Enum.Material.Slate,"WedgePart")
  if side<0 then p.CFrame*=CFrame.Angles(0,math.pi,0) end
 end
end
local function banner(model,pos,team)
 block(model,"Flagpole",Vector3.new(0.3,9,0.3),pos+Vector3.new(0,4.5,0),timber)
 block(model,"Banner",Vector3.new(4,2.8,0.18),pos+Vector3.new(2,7,0),team)
end
function Art.Create(kind,team)
 team=team or Color3.fromRGB(81,158,199)
 local model=Instance.new("Model")
 model.Name=kind
 if kind=="Castle" then
  block(model,"Foundation",Vector3.new(46,2,40),Vector3.new(0,1,0),stone,Enum.Material.Cobblestone)
  block(model,"Keep",Vector3.new(24,22,22),Vector3.new(0,13,0),plaster,Enum.Material.Brick)
  roofAt(model,Vector3.new(0,28,0),28,26,10,roof)
  for _,x in ipairs({-19,19}) do
   for _,z in ipairs({-16,16}) do
    block(model,"Tower",Vector3.new(9,25,9),Vector3.new(x,14,z),stone,Enum.Material.Brick)
    block(model,"Parapet",Vector3.new(11,2,11),Vector3.new(x,27,z),plaster)
    for _,dx in ipairs({-4,4}) do for _,dz in ipairs({-4,4}) do block(model,"Battlement",Vector3.new(3,3,3),Vector3.new(x+dx,29,z+dz),stone) end end
   end
  end
  block(model,"Gate",Vector3.new(8,11,0.7),Vector3.new(0,7,11.5),timber,Enum.Material.WoodPlanks)
  banner(model,Vector3.new(0,33,0),team)
 elseif kind=="TownCenter" or kind=="House" or kind=="Barracks" or kind=="ArcheryRange" or kind=="Stable" or kind=="SiegeWorkshop" or kind=="Blacksmith" or kind=="Market" or kind=="University" or kind=="Monastery" then
  local large=kind~="House"
  local width,depth=large and 24 or 13,large and 19 or 12
  block(model,"Foundation",Vector3.new(width+3,1,depth+3),Vector3.new(0,0.5,0),stone,Enum.Material.Cobblestone)
  block(model,"Walls",Vector3.new(width,11,depth),Vector3.new(0,6,0),plaster)
  local roofColor=kind=="Barracks" and Color3.fromRGB(145,70,51) or roof
  if kind=="ArcheryRange" then roofColor=Color3.fromRGB(92,124,67)
  elseif kind=="Market" then roofColor=Color3.fromRGB(167,120,57)
  elseif kind=="University" or kind=="Monastery" then roofColor=Color3.fromRGB(117,119,150) end
  roofAt(model,Vector3.new(0,14,0),width+3,depth+3,7,roofColor)
  for _,x in ipairs({-width/2,width/2}) do
   block(model,"Beam",Vector3.new(0.8,11,depth+0.3),Vector3.new(x,6,0),timber,Enum.Material.Wood)
  end
  block(model,"Door",Vector3.new(3,6,0.4),Vector3.new(0,3.5,depth/2+0.3),timber,Enum.Material.WoodPlanks)
  for _,x in ipairs({-width/3,width/3}) do block(model,"Window",Vector3.new(2.8,3,0.5),Vector3.new(x,7,depth/2+0.3),Color3.fromRGB(58,73,70)) end
  block(model,"Chimney",Vector3.new(2.6,8,2.6),Vector3.new(width/3,16,-depth/4),stone,Enum.Material.Brick)
  if large then banner(model,Vector3.new(width/2+2,0,depth/2),team) end
  if kind=="TownCenter" then
   block(model,"ClockTower",Vector3.new(6,12,6),Vector3.new(-width/3,18,-depth/4),plaster)
   roofAt(model,Vector3.new(-width/3,25,-depth/4),8,8,5,roof)
   block(model,"Clock",Vector3.new(2.5,2.5,0.3),Vector3.new(-width/3,20,-depth/4+3.2),stone)
  elseif kind=="Barracks" then
   for _,x in ipairs({-5,5}) do
    block(model,"TrainingSword",Vector3.new(0.6,6,0.4),Vector3.new(x,4,depth/2+2),stone,Enum.Material.Metal)
    block(model,"SwordGuard",Vector3.new(3,0.5,0.5),Vector3.new(x,2.5,depth/2+2),timber)
   end
  elseif kind=="ArcheryRange" then
   for _,x in ipairs({-6,6}) do
    block(model,"TargetStand",Vector3.new(0.6,7,0.6),Vector3.new(x,3.5,depth/2+3),timber)
    block(model,"Target",Vector3.new(5,5,0.45),Vector3.new(x,6,depth/2+3),plaster)
    block(model,"Bullseye",Vector3.new(1.6,1.6,0.55),Vector3.new(x,6,depth/2+3.4),team)
   end
  elseif kind=="Stable" then
   block(model,"Paddock",Vector3.new(20,0.1,7),Vector3.new(0,0.65,depth/2+4),Color3.fromRGB(138,116,76),Enum.Material.Ground)
   for _,x in ipairs({-9,0,9}) do block(model,"FencePost",Vector3.new(0.6,5,0.6),Vector3.new(x,2.5,depth/2+7),timber) end
   block(model,"Fence",Vector3.new(20,0.6,0.6),Vector3.new(0,3.2,depth/2+7),timber)
  elseif kind=="Blacksmith" then
   block(model,"Forge",Vector3.new(5,4,4),Vector3.new(-7,2.5,depth/2+3),stone,Enum.Material.Brick)
   block(model,"Coals",Vector3.new(3,0.4,2),Vector3.new(-7,4.7,depth/2+3),Color3.fromRGB(231,132,54),Enum.Material.Neon)
   block(model,"Anvil",Vector3.new(5,1,2.6),Vector3.new(4,3.5,depth/2+3),Color3.fromRGB(83,88,91),Enum.Material.Metal)
   block(model,"AnvilBase",Vector3.new(2.5,3,2),Vector3.new(4,1.8,depth/2+3),timber)
  elseif kind=="Market" then
   for _,x in ipairs({-8,0,8}) do
    block(model,"MarketTable",Vector3.new(6,3,4),Vector3.new(x,1.8,depth/2+4),timber)
    block(model,"Awning",Vector3.new(7,0.35,5),Vector3.new(x,7,depth/2+4),x==0 and plaster or team)
    block(model,"AwningPost",Vector3.new(0.4,7,0.4),Vector3.new(x-3,3.5,depth/2+6),timber)
   end
  elseif kind=="SiegeWorkshop" then
   block(model,"OpenWorkshop",Vector3.new(10,8,0.5),Vector3.new(0,4.5,depth/2+0.5),Color3.fromRGB(65,61,51))
   block(model,"TimberStack",Vector3.new(6,3,6),Vector3.new(-9,2,depth/2+4),timber,Enum.Material.Wood)
   for _,x in ipairs({-2,2}) do block(model,"SpareWheel",Vector3.new(1,5,5),Vector3.new(x,3,depth/2+3),Color3.fromRGB(118,88,56),Enum.Material.Wood).Shape=Enum.PartType.Cylinder end
  elseif kind=="Monastery" then
   block(model,"BellTower",Vector3.new(6,16,6),Vector3.new(0,21,0),plaster)
   roofAt(model,Vector3.new(0,31,0),8,8,5,roofColor)
   block(model,"Bell",Vector3.new(2,3,2),Vector3.new(0,26,3.2),Color3.fromRGB(183,151,74),Enum.Material.Metal)
  elseif kind=="University" then
   for _,x in ipairs({-8,-4,4,8}) do block(model,"StoneColumn",Vector3.new(1.2,10,1.2),Vector3.new(x,5.5,depth/2+2),stone,Enum.Material.Marble) end
   block(model,"Portico",Vector3.new(23,1.5,6),Vector3.new(0,11,depth/2+2),plaster)
  end
 elseif kind=="Mill" or kind=="LumberCamp" or kind=="MiningCamp" then
  block(model,"Foundation",Vector3.new(15,0.7,15),Vector3.new(0,0.35,0),stone,Enum.Material.Cobblestone)
  block(model,"Storehouse",Vector3.new(10,8,9),Vector3.new(1,4.5,-1),plaster)
  roofAt(model,Vector3.new(1,10,-1),13,12,5,roof)
  if kind=="Mill" then
   block(model,"WindmillTower",Vector3.new(5,10,5),Vector3.new(-3,12,0),plaster)
   block(model,"SailVertical",Vector3.new(1.5,14,0.5),Vector3.new(-3,13,3.5),timber)
   block(model,"SailHorizontal",Vector3.new(14,1.5,0.5),Vector3.new(-3,13,3.5),timber)
   for _,side in ipairs({-1,1}) do
    block(model,"CanvasSail",Vector3.new(3,5,0.25),Vector3.new(-3+side,13+side*4,3.8),plaster)
   end
  elseif kind=="LumberCamp" then
   for index=1,3 do block(model,"TimberPile",Vector3.new(13,1.7,1.7),Vector3.new(0,1.5,3+index),timber,Enum.Material.Wood) end
   block(model,"Saw",Vector3.new(5,0.5,0.3),Vector3.new(2,4,6),stone,Enum.Material.Metal)
  else
   block(model,"OreCart",Vector3.new(5,3,4),Vector3.new(-4,2.2,5),timber,Enum.Material.WoodPlanks)
   block(model,"Ore",Vector3.new(3,2,3),Vector3.new(-4,4,5),stone,Enum.Material.Slate)
  end
 elseif kind=="Tower" then
  block(model,"Foundation",Vector3.new(14,2,14),Vector3.new(0,1,0),stone,Enum.Material.Cobblestone)
  block(model,"Tower",Vector3.new(10,23,10),Vector3.new(0,13,0),stone,Enum.Material.Brick)
  block(model,"Parapet",Vector3.new(14,2,14),Vector3.new(0,25,0),plaster)
  for _,x in ipairs({-5,5}) do for _,z in ipairs({-5,5}) do block(model,"Battlement",Vector3.new(3,3,3),Vector3.new(x,27,z),stone) end end
  block(model,"ArrowSlit",Vector3.new(0.7,4,0.4),Vector3.new(0,19,5.1),Color3.fromRGB(67,71,67))
  banner(model,Vector3.new(0,27,0),team)
 elseif kind=="Wall" then
  block(model,"StoneWall",Vector3.new(8,11,6),Vector3.new(0,5.5,0),stone,Enum.Material.Brick)
  for x=-3,3,3 do block(model,"Battlement",Vector3.new(2,2,6),Vector3.new(x,12,0),plaster) end
 elseif kind=="Wonder" then
  block(model,"Courtyard",Vector3.new(51,2,51),Vector3.new(0,1,0),stone,Enum.Material.Marble)
  block(model,"Temple",Vector3.new(30,22,28),Vector3.new(0,13,0),plaster,Enum.Material.Marble)
  roofAt(model,Vector3.new(0,28,0),36,34,8,roof)
  block(model,"Spire",Vector3.new(9,22,9),Vector3.new(0,38,0),plaster,Enum.Material.Marble)
  roofAt(model,Vector3.new(0,52,0),12,12,9,Color3.fromRGB(183,145,60))
  for _,x in ipairs({-22,22}) do for _,z in ipairs({-22,22}) do
   block(model,"Obelisk",Vector3.new(5,26,5),Vector3.new(x,15,z),stone,Enum.Material.Marble)
   block(model,"GildedCap",Vector3.new(6,3,6),Vector3.new(x,30,z),Color3.fromRGB(204,169,72),Enum.Material.Metal)
  end end
  for step=1,4 do block(model,"TempleStair",Vector3.new(18,step*0.6,3),Vector3.new(0,step*0.3,22-step*2),stone) end
  banner(model,Vector3.new(18,25,0),team)
 elseif kind=="Farm" then
  block(model,"Soil",Vector3.new(23,0.6,23),Vector3.new(0,0.3,0),Color3.fromRGB(111,80,45),Enum.Material.Ground)
  for x=-9,9,3 do
   block(model,"CropRow",Vector3.new(1.3,1.2,20),Vector3.new(x,0.8,0),Color3.fromRGB(190,174,78),Enum.Material.Grass)
  end
 elseif kind=="Tree" then
  block(model,"Trunk",Vector3.new(2,9,2),Vector3.new(0,4.5,0),timber,Enum.Material.Wood)
  for i=0,2 do
   local p=block(model,"Crown",Vector3.new(10-i*2,8-i,10-i*2),Vector3.new(0,10+i*3,0),Color3.fromRGB(62+i*9,104+i*9,66+i*4),Enum.Material.Grass)
   p.Shape=Enum.PartType.Ball
  end
 elseif kind=="Gold" or kind=="Stone" then
  for i=1,4 do
   local p=block(model,"Rock",Vector3.new(4,3+i%2,4),Vector3.new((i%2)*4-2,2,math.floor((i-1)/2)*3-1.5),stone,Enum.Material.Slate)
   p.CFrame*=CFrame.Angles(0,i*0.8,i*0.12)
   if kind=="Gold" then block(model,"Ore",Vector3.new(1.5,0.5,2),p.Position+Vector3.new(0,2,0),Color3.fromRGB(222,181,72),Enum.Material.Metal) end
  end
 elseif kind=="Berries" then
  local bush=block(model,"Bush",Vector3.new(8,4,8),Vector3.new(0,2,0),Color3.fromRGB(69,112,62),Enum.Material.Grass)
  bush.Shape=Enum.PartType.Ball
  for i=1,7 do
   local a=i*2.4
   block(model,"Berry",Vector3.new(1.1,1.1,1.1),Vector3.new(math.sin(a)*2.8,3,math.cos(a)*2.8),Color3.fromRGB(173,60,61)).Shape=Enum.PartType.Ball
  end
 elseif kind=="villager" or kind=="infantry" or kind=="spearman" or kind=="archer" or kind=="skirmisher" or kind=="scout" or kind=="cavalry" or kind=="monk" then
  block(model,"BootL",Vector3.new(0.85,1.5,1.1),Vector3.new(-0.6,0.85,0),timber)
  block(model,"BootR",Vector3.new(0.85,1.5,1.1),Vector3.new(0.6,0.85,0),timber)
  block(model,"Body",Vector3.new(2.5,2.5,1.6),Vector3.new(0,2.7,0),kind=="villager" and Color3.fromRGB(216,184,121) or Color3.fromRGB(145,158,164))
  block(model,"Belt",Vector3.new(2.6,0.35,1.7),Vector3.new(0,1.8,0),timber)
  block(model,"Tabard",Vector3.new(1.6,1.8,0.2),Vector3.new(0,2.8,-0.9),team)
  block(model,"Head",Vector3.new(1.7,1.7,1.7),Vector3.new(0,4.6,0),Color3.fromRGB(228,190,145)).Shape=Enum.PartType.Ball
  block(model,"Hat",Vector3.new(2.2,0.5,2.2),Vector3.new(0,5.3,0),kind=="villager" and Color3.fromRGB(164,127,67) or stone)
  for _,side in ipairs({-1,1}) do block(model,side<0 and "ArmL" or "ArmR",Vector3.new(0.7,2.4,0.8),Vector3.new(side*1.7,2.6,0),plaster) end
  if kind=="infantry" or kind=="cavalry" or kind=="scout" then
   block(model,"Sword",Vector3.new(0.4,4,0.3),Vector3.new(2.1,3.6,-0.5),stone,Enum.Material.Metal)
   block(model,"Shield",Vector3.new(0.5,2.8,2),Vector3.new(-2.2,2.8,-0.2),team,Enum.Material.WoodPlanks)
  elseif kind=="spearman" or kind=="skirmisher" then
   block(model,"Spear",Vector3.new(0.3,7,0.3),Vector3.new(2,4,0),timber)
   block(model,"Spearhead",Vector3.new(0.65,1.4,0.3),Vector3.new(2,8,0),stone,Enum.Material.Metal)
   block(model,"Shield",Vector3.new(0.4,2.8,2),Vector3.new(-2.2,2.8,0),team,Enum.Material.WoodPlanks)
  elseif kind=="archer" then
   for index=-1,1 do
    local p=block(model,"Bow",Vector3.new(0.35,1.8,0.35),Vector3.new(2,3+index*1.3,-0.5-math.abs(index)*0.5),timber)
    p.CFrame*=CFrame.Angles(index*0.4,0,0)
   end
   block(model,"Bowstring",Vector3.new(0.08,3.9,0.08),Vector3.new(2,3,-1),plaster)
   block(model,"Quiver",Vector3.new(0.8,2.5,0.8),Vector3.new(-0.8,3,1),timber)
  elseif kind=="monk" then
   block(model,"Robe",Vector3.new(2.9,3,2),Vector3.new(0,1.9,0),Color3.fromRGB(217,212,188))
   block(model,"Staff",Vector3.new(0.25,6.5,0.25),Vector3.new(2,3.5,0),timber)
   block(model,"StaffHead",Vector3.new(1.1,1.1,0.4),Vector3.new(2,6.9,0),Color3.fromRGB(200,172,85),Enum.Material.Metal)
  else
   block(model,"Tool",Vector3.new(0.25,4,0.25),Vector3.new(2,2,0),timber)
   block(model,"ToolHead",Vector3.new(1.5,0.4,0.5),Vector3.new(2,3.8,0),stone)
  end
  if kind=="cavalry" or kind=="scout" then
   for _,part in ipairs(model:GetChildren()) do if part:IsA("BasePart") then part.CFrame+=Vector3.new(0,3.1,0) end end
   local hide=Color3.fromRGB(123,82,50)
   block(model,"HorseBody",Vector3.new(2.5,2.5,5.5),Vector3.new(0,3.1,0),hide)
   block(model,"Saddle",Vector3.new(2.8,0.5,2.4),Vector3.new(0,4.5,0),team)
   block(model,"HorseNeck",Vector3.new(1.6,3,1.7),Vector3.new(0,4.2,-2.5),hide)
   block(model,"HorseHead",Vector3.new(1.6,1.5,2.6),Vector3.new(0,5.7,-3.1),hide)
   block(model,"Mane",Vector3.new(0.5,2.8,0.5),Vector3.new(0,4.8,-1.8),timber)
   for _,x in ipairs({-0.85,0.85}) do for _,z in ipairs({-1.8,1.8}) do
    block(model,"HorseLeg",Vector3.new(0.5,2.4,0.6),Vector3.new(x,1.2,z),hide)
   end end
  end
 elseif kind=="ram" or kind=="mangonel" or kind=="trebuchet" then
  block(model,"Chassis",Vector3.new(6,1,8),Vector3.new(0,2.5,0),timber,Enum.Material.WoodPlanks)
  for _,x in ipairs({-3.2,3.2}) do for _,z in ipairs({-2.7,2.7}) do
   block(model,"Wheel",Vector3.new(1,3.2,3.2),Vector3.new(x,1.6,z),Color3.fromRGB(116,88,55),Enum.Material.Wood).Shape=Enum.PartType.Cylinder
  end end
  if kind=="ram" then
   block(model,"RamLog",Vector3.new(2,2,10),Vector3.new(0,3.5,-1),timber,Enum.Material.Wood)
   block(model,"RamHead",Vector3.new(2.3,2.3,1.5),Vector3.new(0,3.5,-6),stone,Enum.Material.Metal)
   roofAt(model,Vector3.new(0,6,0),7,9,3,team)
  elseif kind=="mangonel" then
   block(model,"CatapultPost",Vector3.new(0.8,4,1),Vector3.new(-2,4,0),timber)
   block(model,"CatapultPost",Vector3.new(0.8,4,1),Vector3.new(2,4,0),timber)
   block(model,"CatapultArm",Vector3.new(0.7,1,8),Vector3.new(0,5.5,-1),timber)
   block(model,"StoneBasket",Vector3.new(2.5,1.4,2.5),Vector3.new(0,6,-4),stone,Enum.Material.Slate)
  else
   for _,x in ipairs({-2,2}) do block(model,"TrebuchetFrame",Vector3.new(1,9,1),Vector3.new(x,6,0),timber) end
   local arm=block(model,"TrebuchetArm",Vector3.new(0.7,13,0.7),Vector3.new(0,10,-1),timber)
   arm.CFrame*=CFrame.Angles(-0.5,0,0)
   block(model,"Counterweight",Vector3.new(3,3,3),Vector3.new(0,6,2),stone)
   block(model,"Sling",Vector3.new(1.7,0.7,1.7),Vector3.new(0,15.5,-4),team)
  end
 end
 return model
end
return Art
