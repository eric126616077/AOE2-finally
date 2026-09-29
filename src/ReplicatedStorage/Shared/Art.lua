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
 elseif kind=="TownCenter" or kind=="House" or kind=="Barracks" then
  local large=kind~="House"
  local width,depth=large and 24 or 13,large and 19 or 12
  block(model,"Foundation",Vector3.new(width+3,1,depth+3),Vector3.new(0,0.5,0),stone,Enum.Material.Cobblestone)
  block(model,"Walls",Vector3.new(width,11,depth),Vector3.new(0,6,0),plaster)
  roofAt(model,Vector3.new(0,14,0),width+3,depth+3,7,kind=="Barracks" and Color3.fromRGB(145,70,51) or roof)
  for _,x in ipairs({-width/2,width/2}) do
   block(model,"Beam",Vector3.new(0.8,11,depth+0.3),Vector3.new(x,6,0),timber,Enum.Material.Wood)
  end
  block(model,"Door",Vector3.new(3,6,0.4),Vector3.new(0,3.5,depth/2+0.3),timber,Enum.Material.WoodPlanks)
  for _,x in ipairs({-width/3,width/3}) do block(model,"Window",Vector3.new(2.8,3,0.5),Vector3.new(x,7,depth/2+0.3),Color3.fromRGB(58,73,70)) end
  block(model,"Chimney",Vector3.new(2.6,8,2.6),Vector3.new(width/3,16,-depth/4),stone,Enum.Material.Brick)
  if large then banner(model,Vector3.new(width/2+2,0,depth/2),team) end
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
 elseif kind=="villager" or kind=="infantry" then
  block(model,"BootL",Vector3.new(0.85,1.5,1.1),Vector3.new(-0.6,0.85,0),timber)
  block(model,"BootR",Vector3.new(0.85,1.5,1.1),Vector3.new(0.6,0.85,0),timber)
  block(model,"Body",Vector3.new(2.5,2.5,1.6),Vector3.new(0,2.7,0),kind=="villager" and Color3.fromRGB(216,184,121) or Color3.fromRGB(145,158,164))
  block(model,"Belt",Vector3.new(2.6,0.35,1.7),Vector3.new(0,1.8,0),timber)
  block(model,"Tabard",Vector3.new(1.6,1.8,0.2),Vector3.new(0,2.8,-0.9),team)
  block(model,"Head",Vector3.new(1.7,1.7,1.7),Vector3.new(0,4.6,0),Color3.fromRGB(228,190,145)).Shape=Enum.PartType.Ball
  block(model,"Hat",Vector3.new(2.2,0.5,2.2),Vector3.new(0,5.3,0),kind=="villager" and Color3.fromRGB(164,127,67) or stone)
  for _,side in ipairs({-1,1}) do block(model,"Arm",Vector3.new(0.7,2.4,0.8),Vector3.new(side*1.7,2.6,0),plaster) end
  if kind=="infantry" then
   block(model,"Sword",Vector3.new(0.4,4,0.3),Vector3.new(2.1,3.6,-0.5),stone,Enum.Material.Metal)
   block(model,"Shield",Vector3.new(0.5,2.8,2),Vector3.new(-2.2,2.8,-0.2),team,Enum.Material.WoodPlanks)
  else
   block(model,"Tool",Vector3.new(0.25,4,0.25),Vector3.new(2,2,0),timber)
   block(model,"ToolHead",Vector3.new(1.5,0.4,0.5),Vector3.new(2,3.8,0),stone)
  end
 end
 return model
end
return Art
