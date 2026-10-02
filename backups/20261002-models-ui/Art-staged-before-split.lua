-- Original, self-contained geometry for fallback models and HUD previews.
-- Building silhouettes carry their purpose; dense resources stay deliberately cheap.
local Art={}
local stone=Color3.fromRGB(170,163,142)
local paleStone=Color3.fromRGB(210,199,173)
local timber=Color3.fromRGB(81,58,39)
local cutWood=Color3.fromRGB(145,108,66)
local plaster=Color3.fromRGB(226,207,166)
local roof=Color3.fromRGB(90,101,102)
local iron=Color3.fromRGB(77,87,91)
local dark=Color3.fromRGB(43,47,43)
local straw=Color3.fromRGB(190,158,76)
local gold=Color3.fromRGB(205,168,76)
local buildingKinds={Castle=true,TownCenter=true,House=true,Barracks=true,ArcheryRange=true,Stable=true,
 SiegeWorkshop=true,Blacksmith=true,Market=true,University=true,Monastery=true,Mill=true,LumberCamp=true,
 MiningCamp=true,Tower=true,Wall=true,Wonder=true,Farm=true}
local unitKinds={villager=true,infantry=true,spearman=true,archer=true,skirmisher=true,scout=true,
 cavalry=true,monk=true,ram=true,mangonel=true,trebuchet=true}
local teamColorNames={Roof=true,Banner=true,Flag=true,Tabard=true,Shield=true,Saddle=true,Ridge=true,
 Awning=true,CanvasSail=true,TeamTrim=true,Cuff=true,TeamPatch=true,Bullseye=true,Shutter=true,
 Sling=true,HatBand=true,HorseCloth=true,SiegeBanner=true}
-- Imported templates can opt individual parts in/out with TeamColorPart.
function Art.ApplyPlayerColor(model,team)
 if typeof(team)~="Color3" then return 0 end
 model:SetAttribute("TeamColor",team)
 local colored=0
 for _,item in ipairs(model:GetDescendants()) do
  if item:IsA("BasePart") and item.Transparency<1 then
   local marked=item:GetAttribute("TeamColorPart")
   if marked==true or (marked==nil and teamColorNames[item.Name]) then
    item:SetAttribute("TeamColorPart",true)
    item.Color=team
    if item:IsA("UnionOperation") then item.UsePartColor=true end
    colored+=1
   end
  end
 end
 return colored
end
local foundationNames={Foundation=true,Courtyard=true,Soil=true,Step=true,StonePlinth=true,Paddock=true}
local wallNames={Walls=true,Keep=true,Tower=true,StoneWall=true,Storehouse=true,Temple=true,WindmillTower=true,
 Post=true,StoneColumn=true,Beam=true,TimberBrace=true,GatePier=true,BellTower=true,Chimney=true}
local roofNames={Roof=true,Ridge=true,Spire=true,GildedCap=true,CanvasSail=true,Banner=true,Eave=true,
 RoofFascia=true,RoofShadow=true,Awning=true,CanopyStripe=true,Finial=true}
local fabricNames={Body=true,Tabard=true,Robe=true,Awning=true,CanvasSail=true,Banner=true,CanopyStripe=true}
local function block(model,name,size,pos,color,material,class)
 local p=Instance.new(class or "Part")
 p.Name,p.Size,p.CFrame=name,size,CFrame.new(pos)
 p.Color,p.Material=color,material or (fabricNames[name] and Enum.Material.Fabric) or
  ((color==plaster or color==paleStone) and Enum.Material.Concrete) or
  ((color==timber or color==cutWood) and Enum.Material.Wood) or Enum.Material.SmoothPlastic
 p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,false,false,true
 p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
 if teamColorNames[name] then p:SetAttribute("TeamColorPart",true) end
 if buildingKinds[model.Name] then
  p:SetAttribute("ConstructionStage",foundationNames[name] and 0 or wallNames[name] and 1 or roofNames[name] and 3 or 2)
 end
 p.Parent=model
 return p
end
local function beam(model,name,a,b,thickness,color,material)
 local p=block(model,name,Vector3.new(thickness,(b-a).Magnitude,thickness),(a+b)/2,color,material)
 p.CFrame=CFrame.lookAt((a+b)/2,b)*CFrame.Angles(math.pi/2,0,0)
 return p
end
local function round(model,name,diameter,height,pos,color,material)
 local p=block(model,name,Vector3.new(height,diameter,diameter),pos,color,material)
 p.Shape=Enum.PartType.Cylinder
 p.CFrame*=CFrame.Angles(0,0,math.pi/2)
 return p
end
local function disc(model,name,diameter,thickness,pos,color,material)
 local p=block(model,name,Vector3.new(thickness,diameter,diameter),pos,color,material)
 p.Shape=Enum.PartType.Cylinder
 p.CFrame*=CFrame.Angles(0,math.pi/2,0)
 return p
end
-- Roblox renders a Ball at one diameter, so every ball is created uniform.
local function ball(model,name,diameter,pos,color,material)
 local p=block(model,name,Vector3.new(diameter,diameter,diameter),pos,color,material)
 p.Shape=Enum.PartType.Ball
 return p
end
-- A box stretched from a to b: length on Z, width on X, height on Y.
local function segment(model,name,a,b,width,height,color,material)
 local p=block(model,name,Vector3.new(width,height,(b-a).Magnitude),(a+b)/2,color,material)
 p.CFrame=CFrame.lookAt((a+b)/2,b)
 return p
end
-- Round plate whose faces point along X (shields worn on the side).
local function plate(model,name,diameter,thickness,pos,color,material)
 local p=block(model,name,Vector3.new(thickness,diameter,diameter),pos,color,material)
 p.Shape=Enum.PartType.Cylinder
 return p
end
-- Two mirrored wedges form a symmetric blade tip or shield point in the YZ plane.
local function point(model,name,base,width,height,thickness,color,material,down)
 local parts={}
 for _,side in ipairs({-1,1}) do
  local p=block(model,name,Vector3.new(thickness,height,width/2),base+Vector3.new(0,(down and -1 or 1)*height/2,side*width/4),color,material,"WedgePart")
  if down then p.CFrame*=side<0 and CFrame.Angles(0,0,math.pi) or CFrame.Angles(math.pi,0,0)
  elseif side>0 then p.CFrame*=CFrame.Angles(0,math.pi,0) end
  table.insert(parts,p)
 end
 return parts
end
-- Swing already placed parts around a pivot (yaw shields toward the camera, tilt tools).
local function turn(parts,pivot,rotation)
 for _,p in ipairs(parts) do p.CFrame=CFrame.new(pivot)*rotation*CFrame.new(-pivot)*p.CFrame end
end
function Art.AddPlayerMarker(model,team)
 if typeof(team)~="Color3" then return end
 -- Add only after fitting an imported copy, without affecting its scale/footprint.
 local box,bounds=model:GetBoundingBox()
 local marker=block(model,"Banner",Vector3.new(math.min(bounds.X*.24,4),math.min(bounds.Y*.2,3),.12),box.Position,team,Enum.Material.Fabric)
 marker.CFrame=box*CFrame.new(0,bounds.Y*.18,bounds.Z/2+.08)
 marker:SetAttribute("ConstructionStage",3)
 marker.CanQuery=false
end
local function roofAt(model,center,width,depth,height,color,wallColor)
 local angle=math.atan(height/(depth/2))
 local slope=math.sqrt((depth/2)^2+height^2)
 local eaveY=center.Y-height/2
 local siege=unitKinds[model.Name]
 for _,side in ipairs({-1,1}) do
  -- Thin roof planes make a real ridge and readable overhanging eaves.
  local p=block(model,"Roof",Vector3.new(width,.5,slope+.25),center+Vector3.new(0,0,side*depth/4),color,Enum.Material.Slate)
  p.CFrame*=CFrame.Angles(side*angle,0,0)
  block(model,siege and "Chassis" or "Eave",Vector3.new(width+.15,.45,.55),Vector3.new(center.X,eaveY,center.Z+side*depth/2),timber,Enum.Material.Wood)
 end
 block(model,"Ridge",Vector3.new(width+.5,.55,.6),center+Vector3.new(0,height/2+.15,0),color,Enum.Material.Slate)
 if siege then return end
 for _,side in ipairs({-1,1}) do
  local x=center.X+side*(width/2-.6)
  if wallColor then
   for _,zside in ipairs({-1,1}) do
    local p=block(model,"Gable",Vector3.new(.25,height,depth/2-.7),Vector3.new(x,center.Y,center.Z+zside*(depth/4-.175)),wallColor,Enum.Material.Concrete,"WedgePart")
    if zside>0 then p.CFrame*=CFrame.Angles(0,math.pi,0) end
   end
  end
  for _,zside in ipairs({-1,1}) do
   beam(model,"RoofFascia",Vector3.new(x,eaveY,center.Z+zside*depth/2),Vector3.new(x,center.Y+height/2,center.Z),.43,timber,Enum.Material.Wood)
  end
 end
end
local function foundation(model,width,depth)
 block(model,"Foundation",Vector3.new(width,.8,depth),Vector3.new(0,.4,0),stone,Enum.Material.Cobblestone)
end
local function hall(model,base,width,depth,height,roofHeight,color)
 color=color or plaster
 block(model,"StonePlinth",Vector3.new(width+.65,1.25,depth+.65),base+Vector3.new(0,.6,0),stone,Enum.Material.Cobblestone)
 block(model,"Walls",Vector3.new(width,height,depth),base+Vector3.new(0,height/2,0),color,Enum.Material.Concrete)
 for _,x in ipairs({-width/2,width/2}) do for _,z in ipairs({-depth/2,depth/2}) do
  block(model,"Beam",Vector3.new(.65,height+.35,.65),base+Vector3.new(x,height/2,z),timber,Enum.Material.Wood)
 end end
 for _,z in ipairs({-depth/2,depth/2}) do block(model,"Beam",Vector3.new(width+.4,.65,.5),base+Vector3.new(0,height-.2,z),timber,Enum.Material.Wood) end
 roofAt(model,base+Vector3.new(0,height+roofHeight/2,0),width+2,depth+2,roofHeight,roof,color)
end
local function door(model,pos,width,height)
 block(model,"DoorRecess",Vector3.new(width+.65,height+.5,.2),pos+Vector3.new(0,height/2+.1,0),dark)
 block(model,"Door",Vector3.new(width,height,.27),pos+Vector3.new(0,height/2,.14),cutWood,Enum.Material.WoodPlanks)
 for _,side in ipairs({-1,1}) do block(model,"DoorJamb",Vector3.new(.5,height+.7,.65),pos+Vector3.new(side*(width/2+.3),height/2,0),paleStone,Enum.Material.Concrete) end
 block(model,"Lintel",Vector3.new(width+1.1,.65,.7),pos+Vector3.new(0,height+.15,0),paleStone,Enum.Material.Concrete)
 for _,y in ipairs({height*.28,height*.72}) do block(model,"DoorBrace",Vector3.new(width+.05,.2,.12),pos+Vector3.new(0,y,.33),iron,Enum.Material.Metal) end
end
local function window(model,pos,width,height,arched)
 if arched then
  block(model,"Window",Vector3.new(width,height-width/2,.22),pos+Vector3.new(0,-width/4,0),dark)
  disc(model,"Window",width,.24,pos+Vector3.new(0,height/2-width/2,0),dark)
 else block(model,"Window",Vector3.new(width,height,.22),pos,dark) end
 block(model,"WindowMullion",Vector3.new(.18,height,.35),pos+Vector3.new(0,0,.12),cutWood,Enum.Material.Wood)
 block(model,"WindowSill",Vector3.new(width+.5,.3,.65),pos+Vector3.new(0,-height/2-.1,.05),paleStone,Enum.Material.Concrete)
end
local function banner(model,pos,team,height)
 height=height or 8
 block(model,"Flagpole",Vector3.new(.25,height,.25),pos+Vector3.new(0,height/2,0),timber)
 block(model,"Banner",Vector3.new(2.8,2.3,.14),pos+Vector3.new(1.4,height-1.5,0),team,Enum.Material.Fabric)
 ball(model,"Finial",.55,pos+Vector3.new(0,height+.1,0),gold,Enum.Material.Metal)
end
local function stairs(model,pos,width,count)
 for i=1,count do block(model,"Step",Vector3.new(width,.45*i,1.7),pos+Vector3.new(0,.225*i,-1.4*(i-1)),paleStone,Enum.Material.Concrete) end
end
local function fence(model,a,b,height)
 for _,p in ipairs({a,b}) do block(model,"FencePost",Vector3.new(.55,height,.55),p+Vector3.new(0,height/2,0),timber) end
 for _,y in ipairs({height*.35,height*.75}) do beam(model,"FenceRail",a+Vector3.new(0,y,0),b+Vector3.new(0,y,0),.35,cutWood,Enum.Material.Wood) end
end
local function barrel(model,pos)
 round(model,"Barrel",2.2,2.8,pos+Vector3.new(0,1.4,0),cutWood,Enum.Material.WoodPlanks)
 for _,y in ipairs({.55,2.25}) do round(model,"BarrelHoop",2.3,.18,pos+Vector3.new(0,y,0),iron,Enum.Material.Metal) end
end
local function chimney(model,pos,height)
 block(model,"Chimney",Vector3.new(2.3,height,2.5),pos+Vector3.new(0,height/2,0),stone,Enum.Material.Brick)
 block(model,"ChimneyCap",Vector3.new(3,.55,3.2),pos+Vector3.new(0,height+.1,0),paleStone,Enum.Material.Concrete)
 block(model,"ChimneyOpening",Vector3.new(1.6,.1,1.8),pos+Vector3.new(0,height+.4,0),dark)
end
local function tower(model,pos,diameter,height)
 round(model,"Tower",diameter,height,pos+Vector3.new(0,height/2,0),stone,Enum.Material.Brick)
 round(model,"StoneCourse",diameter+.4,.65,pos+Vector3.new(0,height*.55,0),paleStone,Enum.Material.Concrete)
 round(model,"Parapet",diameter+1.8,1.6,pos+Vector3.new(0,height+.5,0),paleStone,Enum.Material.Concrete)
 round(model,"TowerDeck",diameter-.9,.18,pos+Vector3.new(0,height+1.4,0),dark,Enum.Material.Slate)
 for i=0,5 do
  local a=i*math.pi/3
  local p=block(model,"Battlement",Vector3.new(diameter*.23,2.3,1.5),pos+Vector3.new(math.sin(a)*diameter/2,height+2.1,math.cos(a)*diameter/2),stone,Enum.Material.Brick)
  p.CFrame*=CFrame.Angles(0,a,0)
 end
 block(model,"ArrowSlit",Vector3.new(.45,3,.2),pos+Vector3.new(0,height*.74,diameter/2+.02),dark)
end
local function horse(model,team,armored)
 -- Capsule barrel (cylinder plus chest / rump balls) reads as a horse from above.
 local hide=armored and Color3.fromRGB(92,68,50) or Color3.fromRGB(134,90,54)
 local mane=Color3.fromRGB(46,34,26)
 local barrel=block(model,"HorseBody",Vector3.new(3.6,2.6,2.6),Vector3.new(0,3.35,.1),hide)
 barrel.Shape=Enum.PartType.Cylinder
 barrel.CFrame*=CFrame.Angles(0,math.pi/2,0)
 ball(model,"HorseBody",2.6,Vector3.new(0,3.35,-1.7),hide)
 ball(model,"HorseBody",2.7,Vector3.new(0,3.42,1.9),hide)
 for _,x in ipairs({-.72,.72}) do for _,z in ipairs({-1.75,1.95}) do
  block(model,"HorseLeg",Vector3.new(.55,2.6,.62),Vector3.new(x,1.3,z),hide)
 end end
 segment(model,"HorseNeck",Vector3.new(0,3.9,-2.25),Vector3.new(0,5.55,-3.15),1,1.45,hide)
 segment(model,"Mane",Vector3.new(0,4.65,-1.95),Vector3.new(0,6.25,-2.95),.32,.45,mane)
 local brow,muzzle=Vector3.new(0,5.95,-3.1),Vector3.new(0,5,-4.55)
 local face=(muzzle-brow).Unit
 segment(model,"HorseHead",brow,muzzle,.86,.95,hide)
 segment(model,"HorseHead",muzzle-face*.5,muzzle+face*.12,.92,.9,Color3.fromRGB(88,62,44))
 for _,side in ipairs({-1,1}) do
  local ear=block(model,"HorseHead",Vector3.new(.2,.6,.36),brow+Vector3.new(side*.27,.45,.12),hide,nil,"WedgePart")
  ear.CFrame*=CFrame.Angles(0,0,side*-.12)
  ball(model,"HorseHead",.2,brow+face*.55+Vector3.new(side*.43,.12,0),dark)
 end
 segment(model,"Mane",Vector3.new(0,4.2,3.2),Vector3.new(0,2.1,3.85),.45,.55,mane)
 block(model,"Saddle",Vector3.new(1.9,.42,2),Vector3.new(0,4.78,.25),team,Enum.Material.Fabric)
 block(model,"HorseBody",Vector3.new(1.3,.55,.35),Vector3.new(0,5.05,1.2),timber,Enum.Material.Wood)
 if armored then
  -- Knight caparison and chanfron; the scout keeps a light saddle cloth.
  for _,side in ipairs({-1,1}) do block(model,"HorseCloth",Vector3.new(.12,1.8,5.2),Vector3.new(side*1.4,3.3,.1),team,Enum.Material.Fabric) end
  block(model,"HorseCloth",Vector3.new(2.6,1.7,.12),Vector3.new(0,3.25,-3.06),team,Enum.Material.Fabric)
  block(model,"HorseCloth",Vector3.new(2.6,1.6,.12),Vector3.new(0,3.35,3.3),team,Enum.Material.Fabric)
  segment(model,"HorseHead",brow+Vector3.new(0,.2,.05),muzzle+Vector3.new(0,.22,.2),.94,.62,Color3.fromRGB(150,163,168),Enum.Material.Metal)
 else
  for _,side in ipairs({-1,1}) do block(model,"HorseCloth",Vector3.new(.12,1.2,2.2),Vector3.new(side*1.34,3.95,.25),team,Enum.Material.Fabric) end
 end
end
-- Villager hand tools follow the job. Every piece keeps the Tool / ToolHead names
-- of the right-arm animation group and is held in the right hand, head toward -Z.
local toolKinds={axe=true,pick=true,hoe=true,hammer=true,basket=true}
local function villagerTool(model,tool)
 local blade=Color3.fromRGB(200,212,214)
 local parts={}
 local function add(part) table.insert(parts,part); return part end
 if tool=="pick" then
  add(block(model,"Tool",Vector3.new(.18,3.4,.18),Vector3.new(1.38,2.2,-.35),cutWood))
  add(block(model,"ToolHead",Vector3.new(.24,.32,1.5),Vector3.new(1.38,3.8,-.35),iron,Enum.Material.Metal))
  for _,side in ipairs({-1,1}) do
   add(block(model,"ToolHead",Vector3.new(.16,.22,.8),Vector3.new(1.38,3.62,-.35+side*1.05),blade,Enum.Material.Metal)).CFrame*=CFrame.Angles(side*.5,0,0)
  end
 elseif tool=="hoe" then
  add(block(model,"Tool",Vector3.new(.16,3.9,.16),Vector3.new(1.38,2.45,-.35),cutWood))
  add(block(model,"ToolHead",Vector3.new(.14,.14,.55),Vector3.new(1.38,4.3,-.6),iron,Enum.Material.Metal))
  add(block(model,"ToolHead",Vector3.new(.62,.58,.1),Vector3.new(1.38,4.05,-.86),blade,Enum.Material.Metal))
 elseif tool=="hammer" then
  add(block(model,"Tool",Vector3.new(.18,2.6,.18),Vector3.new(1.38,2.1,-.35),cutWood))
  add(block(model,"ToolHead",Vector3.new(.52,.52,1.15),Vector3.new(1.38,3.4,-.35),iron,Enum.Material.Metal))
 elseif tool=="basket" then
  add(round(model,"Tool",1.3,.85,Vector3.new(1.38,1.1,-.55),straw,Enum.Material.Fabric))
  add(round(model,"Tool",1.42,.14,Vector3.new(1.38,1.55,-.55),cutWood,Enum.Material.Wood))
  add(ball(model,"ToolHead",.5,Vector3.new(1.2,1.68,-.62),Color3.fromRGB(184,54,72)))
  add(ball(model,"ToolHead",.46,Vector3.new(1.58,1.66,-.45),Color3.fromRGB(148,38,62)))
 else
  add(block(model,"Tool",Vector3.new(.18,3.4,.18),Vector3.new(1.38,2.2,-.35),cutWood))
  add(block(model,"ToolHead",Vector3.new(.2,.62,.6),Vector3.new(1.38,3.55,-.7),iron,Enum.Material.Metal))
  add(block(model,"ToolHead",Vector3.new(.12,1,.25),Vector3.new(1.38,3.55,-1.08),blade,Enum.Material.Metal))
 end
 return parts
end
-- Goods on the back show what a villager is hauling to the drop-off.
local carryKinds={food=true,wood=true,gold=true,stone=true}
local function carryLoad(model,kind)
 local parts={}
 local function add(part) table.insert(parts,part); return part end
 if kind=="wood" then
  for i,y in ipairs({2.35,2.95,3.55}) do
   add(block(model,"Carry",Vector3.new(2.3,.58,.58),Vector3.new(0,y,i==2 and 1.12 or .98),i==2 and timber or cutWood,Enum.Material.Wood)).Shape=Enum.PartType.Cylinder
  end
 elseif kind=="food" then
  add(ball(model,"Carry",1.45,Vector3.new(0,2.65,1.2),Color3.fromRGB(196,170,120),Enum.Material.Fabric))
  add(block(model,"Carry",Vector3.new(.5,.4,.5),Vector3.new(0,3.45,1.2),straw,Enum.Material.Fabric))
 else
  add(block(model,"Carry",Vector3.new(1.5,1.1,.9),Vector3.new(0,2.6,1.13),cutWood,Enum.Material.WoodPlanks))
  if kind=="gold" then
   add(ball(model,"Carry",.72,Vector3.new(-.3,3.3,1.13),Color3.fromRGB(236,190,72),Enum.Material.Metal))
   add(ball(model,"Carry",.6,Vector3.new(.35,3.25,1.1),Color3.fromRGB(236,190,72),Enum.Material.Metal))
  else
   add(block(model,"Carry",Vector3.new(1.1,.55,.7),Vector3.new(0,3.35,1.13),Color3.fromRGB(136,146,150),Enum.Material.Slate)).CFrame*=CFrame.Angles(0,.3,.12)
  end
 end
 return parts
end
-- Placed units carry a Root 2.5 studs above the art origin (ModelFactory.unit); previews have none.
local function place(model,parts)
 local root=model.PrimaryPart
 local origin=root and root.CFrame*CFrame.new(0,-2.5,0) or CFrame.identity
 for _,part in ipairs(parts) do
  part.CFrame=origin*part.CFrame
  part.CanCollide,part.CanTouch=false,false
 end
end
function Art.SetTool(model,tool)
 if not toolKinds[tool] or model:GetAttribute("ToolKind")==tool then return false end
 for _,part in ipairs(model:GetChildren()) do
  if part.Name=="Tool" or part.Name=="ToolHead" then part:Destroy() end
 end
 place(model,villagerTool(model,tool))
 model:SetAttribute("ToolKind",tool)
 return true
end
function Art.SetCarry(model,kind)
 kind=carryKinds[kind] and kind or ""
 if (model:GetAttribute("CarryVisual") or "")==kind then return false end
 model:SetAttribute("CarryVisual",kind)
 if kind~="" and model:GetAttribute("CarryBuilt")~=kind then
  for _,part in ipairs(model:GetChildren()) do if part.Name=="Carry" then part:Destroy() end end
  place(model,carryLoad(model,kind))
  model:SetAttribute("CarryBuilt",kind)
 else
  -- Same goods as the last trip: keep the parts and only show / hide them.
  for _,part in ipairs(model:GetChildren()) do if part.Name=="Carry" then part.Transparency=kind=="" and 1 or 0 end end
 end
 return true
end
-- 0 full, 1 two thirds or less, 2 one third or less, 3 empty (fallow farm).
function Art.ResourceStage(amount,maximum)
 if type(amount)~="number" or type(maximum)~="number" or amount~=amount or maximum~=maximum or maximum<=0 then return 0 end
 local ratio=amount/maximum
 return ratio<=0 and 3 or ratio<=1/3 and 2 or ratio<=2/3 and 1 or 0
end
local function person(model,kind,team)
 local mounted=kind=="cavalry" or kind=="scout"
 local armored=kind=="infantry" or kind=="cavalry" or kind=="spearman"
 local skin=Color3.fromRGB(229,190,145)
 local leather=Color3.fromRGB(78,56,38)
 local steel=Color3.fromRGB(150,163,168)
 local blade=Color3.fromRGB(200,212,214)
 local cloth=({villager=team,archer=Color3.fromRGB(98,112,66),skirmisher=Color3.fromRGB(170,134,88),
  scout=Color3.fromRGB(170,134,88),monk=Color3.fromRGB(150,104,64)})[kind] or Color3.fromRGB(128,142,150)
 for _,side in ipairs({-1,1}) do block(model,side<0 and "BootL" or "BootR",Vector3.new(.72,1.5,.92),Vector3.new(side*.5,.75,-.04),leather) end
 local body=block(model,"Body",Vector3.new(2.1,2.2,1.35),Vector3.new(0,2.65,0),cloth,armored and Enum.Material.Metal or Enum.Material.Fabric)
 if kind=="villager" then body:SetAttribute("TeamColorPart",true) end
 block(model,"Belt",Vector3.new(2.2,.32,1.45),Vector3.new(0,1.68,0),timber,Enum.Material.Fabric)
 block(model,"Belt",Vector3.new(.42,.4,.12),Vector3.new(0,1.68,-.76),gold,Enum.Material.Metal)
 if kind=="villager" then
  block(model,"Belt",Vector3.new(1.45,1.45,.1),Vector3.new(0,2.15,-.72),Color3.fromRGB(196,170,120),Enum.Material.Fabric)
 elseif kind=="monk" then
  block(model,"Tabard",Vector3.new(.45,2.7,.1),Vector3.new(0,2.35,-.86),team,Enum.Material.Fabric)
 else
  block(model,"Tabard",Vector3.new(1.5,1.95,.12),Vector3.new(0,2.5,-.73),team,Enum.Material.Fabric)
 end
 for _,side in ipairs({-1,1}) do
  local name=side<0 and "ArmL" or "ArmR"
  block(model,name,Vector3.new(.6,1.9,.7),Vector3.new(side*1.38,2.75,0),armored and steel or kind=="villager" and plaster or cloth,armored and Enum.Material.Metal or Enum.Material.Fabric)
  block(model,name,Vector3.new(.62,.5,.72),Vector3.new(side*1.38,1.57,0),armored and leather or skin)
  if armored then ball(model,name,1.05,Vector3.new(side*1.3,3.62,0),steel,Enum.Material.Metal) end
 end
 ball(model,"Head",1.5,Vector3.new(0,4.5,0),skin)
 for _,side in ipairs({-1,1}) do block(model,"Head",Vector3.new(.15,.24,.1),Vector3.new(side*.27,4.6,-.7),dark) end
 block(model,"Head",Vector3.new(.24,.3,.24),Vector3.new(0,4.4,-.74),Color3.fromRGB(214,170,124))
 -- Headgear sits on the skull and leaves the eyes visible.
 if kind=="villager" then
  round(model,"Hat",2.5,.14,Vector3.new(0,5.02,0),straw,Enum.Material.Fabric)
  round(model,"Hat",1.4,.6,Vector3.new(0,5.36,0),straw,Enum.Material.Fabric)
  round(model,"HatBand",1.46,.18,Vector3.new(0,5.16,0),team,Enum.Material.Fabric)
 elseif armored then
  ball(model,"Hat",1.62,Vector3.new(0,4.72,.1),steel,Enum.Material.Metal)
  round(model,kind=="spearman" and "HatBand" or "Hat",1.72,.2,Vector3.new(0,4.86,.08),kind=="spearman" and team or iron,Enum.Material.Metal)
  block(model,"Hat",Vector3.new(.16,.55,.1),Vector3.new(0,4.6,-.8),iron,Enum.Material.Metal)
  if kind=="spearman" then block(model,"Hat",Vector3.new(.2,.55,.2),Vector3.new(0,5.75,.1),iron,Enum.Material.Metal)
  else block(model,"HatBand",Vector3.new(.26,.34,1.35),Vector3.new(0,5.48,.12),team,Enum.Material.Fabric) end
  if kind=="cavalry" then ball(model,"HatBand",.6,Vector3.new(0,5.62,.78),team,Enum.Material.Fabric) end
 elseif kind=="monk" then
  ball(model,"Hat",1.8,Vector3.new(0,4.6,.2),cloth,Enum.Material.Fabric)
  block(model,"Hat",Vector3.new(2,.45,1.5),Vector3.new(0,3.85,.1),cloth,Enum.Material.Fabric)
 elseif kind=="archer" then
  ball(model,"Hat",1.72,Vector3.new(0,4.62,.16),cloth,Enum.Material.Fabric)
  block(model,"Hat",Vector3.new(1.9,.42,1.45),Vector3.new(0,3.86,.12),cloth,Enum.Material.Fabric)
  local feather=block(model,"HatBand",Vector3.new(.1,1,.32),Vector3.new(.55,5.35,.45),team,Enum.Material.Fabric)
  feather.CFrame*=CFrame.Angles(-.5,0,-.35)
 else
  ball(model,"Hat",1.6,Vector3.new(0,4.72,.1),leather,Enum.Material.Fabric)
  round(model,"HatBand",1.66,.2,Vector3.new(0,4.86,.1),team,Enum.Material.Fabric)
 end
 local hand=Vector3.new(1.38,1.57,0)
 local shieldPivot=Vector3.new(-1.75,2.7,0)
 if kind=="infantry" or kind=="cavalry" or kind=="scout" then
  local grip=hand+Vector3.new(0,0,-.3)
  block(model,"Sword",Vector3.new(.2,.62,.2),grip,leather)
  block(model,"Sword",Vector3.new(.26,.18,1.05),grip+Vector3.new(0,.42,0),gold,Enum.Material.Metal)
  block(model,"Sword",Vector3.new(.12,2.3,.34),grip+Vector3.new(0,1.66,0),blade,Enum.Material.Metal)
  point(model,"Sword",grip+Vector3.new(0,2.81,0),.34,.45,.12,blade,Enum.Material.Metal)
  ball(model,"Sword",.3,grip+Vector3.new(0,-.36,0),gold,Enum.Material.Metal)
 end
 if kind=="infantry" or kind=="cavalry" then
  -- Heater shield: board plus a mirrored point, turned toward the front.
  local parts={block(model,"Shield",Vector3.new(.22,1.45,1.7),Vector3.new(-1.8,2.95,0),team,Enum.Material.WoodPlanks)}
  for _,p in ipairs(point(model,"Shield",Vector3.new(-1.8,2.225,0),1.7,.95,.22,team,Enum.Material.WoodPlanks,true)) do table.insert(parts,p) end
  table.insert(parts,block(model,"ArmL",Vector3.new(.26,.24,1.74),Vector3.new(-1.86,3.2,0),gold,Enum.Material.Metal))
  turn(parts,shieldPivot,CFrame.Angles(0,-.55,0))
 elseif kind=="spearman" or kind=="scout" or kind=="skirmisher" then
  local d=kind=="spearman" and 2.1 or 1.45
  turn({plate(model,"Shield",d,.24,Vector3.new(-1.82,2.65,0),team,Enum.Material.WoodPlanks),
   plate(model,"ArmL",d*.32,.3,Vector3.new(-1.88,2.65,0),iron,Enum.Material.Metal)},shieldPivot,CFrame.Angles(0,-.55,0))
 end
 if kind=="spearman" then
  block(model,"Spear",Vector3.new(.2,7.3,.2),Vector3.new(1.38,3.65,-.3),cutWood,Enum.Material.Wood)
  block(model,"Spearhead",Vector3.new(.28,.3,.28),Vector3.new(1.38,7.3,-.3),iron,Enum.Material.Metal)
  point(model,"Spearhead",Vector3.new(1.38,7.42,-.3),.5,1.2,.12,blade,Enum.Material.Metal)
 elseif kind=="skirmisher" then
  for i,x in ipairs({1.3,1.52}) do
   local z=-.15-i*.18
   block(model,"Spear",Vector3.new(.14,4.4,.14),Vector3.new(x,2.6+i*.15,z),cutWood,Enum.Material.Wood)
   point(model,"Spearhead",Vector3.new(x,4.8+i*.15,z),.3,.7,.1,blade,Enum.Material.Metal)
  end
 elseif kind=="archer" then
  -- Curved bow from connected limb segments; the string closes the arc.
  local grip=Vector3.new(1.85,2.4,-.4)
  local arc={}
  for i=0,4 do local t=i/2-1; table.insert(arc,grip+Vector3.new(0,t*1.85,t*t*.75)) end
  for i=1,4 do beam(model,"Bow",arc[i],arc[i+1],.2,cutWood,Enum.Material.Wood) end
  block(model,"Bow",Vector3.new(.28,.55,.28),grip,leather)
  block(model,"Bowstring",Vector3.new(.06,3.7,.06),grip+Vector3.new(0,0,.75),plaster)
  local top=Vector3.new(-.2,4.05,.95)
  beam(model,"Quiver",Vector3.new(-.62,2.05,.95),top,.62,leather)
  for _,x in ipairs({-.18,0,.18}) do beam(model,"Quiver",top+Vector3.new(x,-.1,0),top+Vector3.new(x+.05,.6,0),.12,plaster) end
 elseif kind=="monk" then
  block(model,"Robe",Vector3.new(2.3,2.9,1.6),Vector3.new(0,1.5,0),cloth,Enum.Material.Fabric)
  block(model,"Robe",Vector3.new(2.5,.4,1.78),Vector3.new(0,.22,0),cloth,Enum.Material.Fabric)
  block(model,"Staff",Vector3.new(.2,6.4,.2),Vector3.new(1.38,3.2,-.3),timber)
  round(model,"StaffHead",.9,.14,Vector3.new(1.38,6.3,-.3),gold,Enum.Material.Metal)
  ball(model,"StaffHead",.6,Vector3.new(1.38,6.65,-.3),gold,Enum.Material.Metal)
 elseif kind=="villager" then
  villagerTool(model,"axe")
  model:SetAttribute("ToolKind","axe")
 end
 if mounted then
  -- Rider sits in the saddle with legs along the horse's flanks.
  for _,p in ipairs(model:GetChildren()) do if p:IsA("BasePart") then p.CFrame+=Vector3.new(0,3.2,0) end end
  for _,p in ipairs(model:GetChildren()) do
   if p.Name=="BootL" or p.Name=="BootR" then
    p.Size=Vector3.new(.62,1.7,.9)
    p.CFrame=CFrame.new((p.Name=="BootL" and -1 or 1)*1.5,3.75,-.15)
   end
  end
  horse(model,team,kind=="cavalry")
 end
end
function Art.Create(kind,team,applyPlayerColor,stage)
 team=typeof(team)=="Color3" and team or Color3.fromRGB(81,158,199)
 stage=type(stage)=="number" and math.clamp(math.floor(stage),0,3) or 0
 local model=Instance.new("Model")
 model.Name=kind
 model:SetAttribute("OriginalArt",true)
 if kind=="TownCenter" then
  foundation(model,30,27)
  hall(model,Vector3.new(0,1,-4),23,14,12,6)
  block(model,"Beam",Vector3.new(23,.55,.45),Vector3.new(0,7,3.2),timber)
  for _,x in ipairs({-8,8}) do
   block(model,"Beam",Vector3.new(.55,11.8,.55),Vector3.new(x,6.8,3.2),timber)
   window(model,Vector3.new(x,9.2,3.35),2.5,3.2,true)
  end
  door(model,Vector3.new(0,1,3.35),4.5,7)
  -- Open civic loggia, stepped entry and a raised bell pavilion.
  for _,x in ipairs({-12,-4,4,12}) do
   block(model,"Post",Vector3.new(.8,8.5,.8),Vector3.new(x,5.1,10),timber)
   beam(model,"TimberBrace",Vector3.new(x,7,10),Vector3.new(x+(x<0 and 2 or -2),9.2,10),.45,timber)
  end
  roofAt(model,Vector3.new(0,10.6,7),27,8,3.5,roof)
  stairs(model,Vector3.new(0,0,12.2),11,3)
  block(model,"ClockTower",Vector3.new(6,8,6),Vector3.new(0,19,-4),plaster)
  for _,x in ipairs({-2.6,2.6}) do block(model,"Beam",Vector3.new(.5,8,.5),Vector3.new(x,19,-.85),timber) end
  window(model,Vector3.new(0,19.7,-.85),2.2,3.4,true)
  roofAt(model,Vector3.new(0,24.1,-4),8,8,4.8,roof,plaster)
  banner(model,Vector3.new(0,26.6,-4),team,4)
 elseif kind=="House" then
  foundation(model,16,15)
  hall(model,Vector3.new(-1.1,.85,-1),11,10,7.6,4.8)
  door(model,Vector3.new(-2.5,.85,4.2),2.25,5)
  window(model,Vector3.new(2.5,5.7,4.25),2,2.3,false)
  for _,side in ipairs({-1,1}) do block(model,"Shutter",Vector3.new(.55,2.25,.2),Vector3.new(2.5+side*1.35,5.7,4.3),team,Enum.Material.WoodPlanks) end
  beam(model,"TimberBrace",Vector3.new(-6.5,2.8,4.3),Vector3.new(-4.3,7.4,4.3),.38,timber)
  hall(model,Vector3.new(5.3,.85,-.8),3,7,4.3,1.6,Color3.fromRGB(207,189,148))
  chimney(model,Vector3.new(-4.2,7.2,-3),6)
  block(model,"FlowerBox",Vector3.new(2.5,.65,.75),Vector3.new(2.5,4.1,4.5),cutWood,Enum.Material.WoodPlanks)
  block(model,"Herbs",Vector3.new(2.2,.45,.55),Vector3.new(2.5,4.6,4.5),Color3.fromRGB(91,127,63),Enum.Material.Grass)
  stairs(model,Vector3.new(-2.5,0,5.6),3.5,2)
 elseif kind=="Barracks" then
  foundation(model,28,26)
  hall(model,Vector3.new(1,1,-5),22,11,9.8,5)
  door(model,Vector3.new(1,1,.7),4,7)
  for _,x in ipairs({-6,8}) do window(model,Vector3.new(x,7.2,.7),2.5,3.2,true) end
  tower(model,Vector3.new(-10,1,-6),6.5,14)
  roofAt(model,Vector3.new(-10,17.6,-6),8,8,4,roof,paleStone)
  block(model,"TrainingGround",Vector3.new(23,.15,9),Vector3.new(1,.9,7),Color3.fromRGB(137,115,77),Enum.Material.Ground)
  fence(model,Vector3.new(-12,.8,3),Vector3.new(-12,.8,11),3.2)
  for _,x in ipairs({-6,-3,0}) do
   block(model,"TrainingSpear",Vector3.new(.25,6,.25),Vector3.new(x,3.9,7.5),cutWood)
   block(model,"TrainingSpearhead",Vector3.new(.6,1.2,.3),Vector3.new(x,7.1,7.5),iron,Enum.Material.Metal,"WedgePart")
  end
  block(model,"WeaponRack",Vector3.new(9,.45,.6),Vector3.new(-3,3.1,7.5),timber)
  block(model,"Shield",Vector3.new(2.5,3,.3),Vector3.new(7,3,7),team,Enum.Material.WoodPlanks)
  ball(model,"ShieldBoss",.7,Vector3.new(7,3,7.15),iron,Enum.Material.Metal)
  banner(model,Vector3.new(10,1,1),team)
 elseif kind=="ArcheryRange" then
  foundation(model,27,25)
  hall(model,Vector3.new(0,.9,-6),22,9,8.5,4)
  door(model,Vector3.new(-7,.9,-1.3),2.8,5.5)
  window(model,Vector3.new(6,6.6,-1.3),4,2.6,false)
  for _,x in ipairs({-10,10}) do block(model,"Post",Vector3.new(.6,7,.6),Vector3.new(x,4.3,5),timber) end
  roofAt(model,Vector3.new(0,8.1,2),24,8,2.5,roof)
  for _,x in ipairs({-5,5}) do
   block(model,"TargetStand",Vector3.new(.5,5.4,.5),Vector3.new(x,3.5,7),cutWood)
   disc(model,"Target",4.8,.35,Vector3.new(x,5.1,7),straw,Enum.Material.Fabric)
   disc(model,"TargetRing",3.2,.38,Vector3.new(x,5.1,7.2),plaster,Enum.Material.Fabric)
   disc(model,"Bullseye",1.45,.42,Vector3.new(x,5.1,7.42),team,Enum.Material.Fabric)
  end
  fence(model,Vector3.new(-12,.8,0),Vector3.new(-12,.8,11),2.8)
  block(model,"ArrowRack",Vector3.new(3,2.5,1.6),Vector3.new(10,2.1,8),timber,Enum.Material.WoodPlanks)
  banner(model,Vector3.new(11,.8,-1),team,7)
 elseif kind=="Stable" then
  foundation(model,31,23)
  hall(model,Vector3.new(0,.9,-4.5),27,10,7.7,4.5,Color3.fromRGB(209,182,137))
  for _,x in ipairs({-9,0,9}) do
   block(model,"StallOpening",Vector3.new(6,5.8,.22),Vector3.new(x,3.9,.7),dark)
   block(model,"StallGate",Vector3.new(5.8,1.8,.32),Vector3.new(x,2,.9),cutWood,Enum.Material.WoodPlanks)
   block(model,"Beam",Vector3.new(.5,7.8,.5),Vector3.new(x-3.4,4.8,.8),timber)
  end
  block(model,"Paddock",Vector3.new(28,.12,9),Vector3.new(0,.88,6),Color3.fromRGB(143,123,76),Enum.Material.Ground)
  fence(model,Vector3.new(-14,.8,2),Vector3.new(-14,.8,10),3.4)
  fence(model,Vector3.new(14,.8,2),Vector3.new(14,.8,10),3.4)
  fence(model,Vector3.new(-14,.8,10),Vector3.new(-4,.8,10),3.4)
  block(model,"WaterTrough",Vector3.new(6,1.6,2.2),Vector3.new(8,1.8,8.5),timber,Enum.Material.WoodPlanks)
  block(model,"TroughWater",Vector3.new(5.5,.15,1.7),Vector3.new(8,2.6,8.5),Color3.fromRGB(79,128,137))
  block(model,"HayBale",Vector3.new(3,2.6,3),Vector3.new(-9,2.1,5),straw,Enum.Material.Grass)
  block(model,"HayBinding",Vector3.new(3.1,.22,3.1),Vector3.new(-9,2.1,5),timber)
  banner(model,Vector3.new(13,1,0),team,7)
 elseif kind=="Blacksmith" then
  foundation(model,25,24)
  hall(model,Vector3.new(3,.9,-4.5),16,12,8.4,4.2,Color3.fromRGB(199,183,153))
  door(model,Vector3.new(5,.9,1.7),3,6)
  chimney(model,Vector3.new(-7.5,.9,-3.5),16)
  for _,x in ipairs({-10,2}) do block(model,"Post",Vector3.new(.65,6.6,.65),Vector3.new(x,4.2,9),timber) end
  roofAt(model,Vector3.new(-4,8.4,5.5),14,9,3.2,roof)
  block(model,"Forge",Vector3.new(5,1.6,4.5),Vector3.new(-6,1.7,5),stone,Enum.Material.Brick)
  for _,x in ipairs({-8,-4}) do block(model,"ForgePier",Vector3.new(1,3.6,4.5),Vector3.new(x,3.6,5),stone,Enum.Material.Brick) end
  block(model,"ForgeHood",Vector3.new(5.4,1,4.8),Vector3.new(-6,5.5,5),iron,Enum.Material.Metal)
  block(model,"Coals",Vector3.new(2.9,.25,3),Vector3.new(-6,2.7,5),Color3.fromRGB(231,117,45),Enum.Material.Neon)
  block(model,"AnvilBase",Vector3.new(2.2,2.2,2),Vector3.new(0,2,6.8),timber)
  block(model,"Anvil",Vector3.new(3.3,.85,1.8),Vector3.new(0,3.3,6.8),iron,Enum.Material.Metal)
  block(model,"AnvilHorn",Vector3.new(1.8,.55,1.1),Vector3.new(2.3,3.4,6.8),iron,Enum.Material.Metal,"WedgePart")
  barrel(model,Vector3.new(8,.9,7))
  banner(model,Vector3.new(10,.9,1),team,7)
 elseif kind=="Market" then
  foundation(model,31,23)
  hall(model,Vector3.new(0,.9,-5.5),27,9,7.4,4)
  door(model,Vector3.new(0,.9,-.8),3.5,5.6)
  for _,x in ipairs({-9,9}) do window(model,Vector3.new(x,5.3,-.8),3.5,2.7,false) end
  for _,x in ipairs({-10,0,10}) do
   block(model,"MarketCounter",Vector3.new(8,2.5,3.5),Vector3.new(x,2.2,6),cutWood,Enum.Material.WoodPlanks)
   for _,side in ipairs({-1,1}) do block(model,"Post",Vector3.new(.4,6.4,.4),Vector3.new(x+side*3.8,4.1,8),timber) end
   local canvas=block(model,"Awning",Vector3.new(8.6,.25,8),Vector3.new(x,7.3,4.7),team,Enum.Material.Fabric)
   canvas.CFrame*=CFrame.Angles(.15,0,0)
   for _,side in ipairs({-1,1}) do
    local stripe=block(model,"CanopyStripe",Vector3.new(1.3,.28,8),Vector3.new(x+side*2.1,7.3,4.7),plaster,Enum.Material.Fabric)
    stripe.CFrame=canvas.CFrame*CFrame.new(side*2.1,.03,0)
   end
   block(model,"Awning",Vector3.new(8.6,.7,.2),Vector3.new(x,6.35,8.65),team,Enum.Material.Fabric)
   block(model,"Produce",Vector3.new(5.7,.45,2.5),Vector3.new(x,3.7,6),x<0 and straw or x>0 and Color3.fromRGB(154,77,62) or Color3.fromRGB(99,131,70),Enum.Material.Grass)
  end
  barrel(model,Vector3.new(13,.9,2))
  block(model,"Crate",Vector3.new(3,2.5,3),Vector3.new(-13,2.1,1.5),cutWood,Enum.Material.WoodPlanks)
  banner(model,Vector3.new(12,1,-1),team,7)
 elseif kind=="SiegeWorkshop" then
  foundation(model,32,24)
  hall(model,Vector3.new(0,1,-4),27,12,10.5,4.6,Color3.fromRGB(194,180,146))
  for _,x in ipairs({-7,7}) do
   block(model,"OpenWorkshop",Vector3.new(9,8,.3),Vector3.new(x,5.1,2.2),dark)
   beam(model,"TimberBrace",Vector3.new(x-4.5,8,2.5),Vector3.new(x-2,11,2.5),.55,timber)
  end
  for _,x in ipairs({-12,12}) do block(model,"Post",Vector3.new(.8,9,.8),Vector3.new(x,5.5,10),timber) end
  block(model,"Beam",Vector3.new(25,1,1),Vector3.new(0,10,10),timber)
  block(model,"HoistRope",Vector3.new(.16,6,.16),Vector3.new(0,7,10),straw)
  block(model,"HoistLoad",Vector3.new(6,1.4,1.4),Vector3.new(0,4.4,10),cutWood,Enum.Material.Wood)
  for _,z in ipairs({5,7.2,9.4}) do block(model,"TimberStack",Vector3.new(9,1.5,1.5),Vector3.new(-8,1.8,z),cutWood,Enum.Material.Wood).Shape=Enum.PartType.Cylinder end
  for _,x in ipairs({6.8,8.2}) do block(model,"SpareWheel",Vector3.new(.7,4.6,4.6),Vector3.new(x,3.1,7),timber,Enum.Material.WoodPlanks).Shape=Enum.PartType.Cylinder end
  block(model,"SpareAxle",Vector3.new(7,.5,.5),Vector3.new(6.8,3.1,7),iron,Enum.Material.Metal)
  banner(model,Vector3.new(13,1,2),team)
 elseif kind=="University" then
  foundation(model,34,31)
  hall(model,Vector3.new(0,1,-7),28,10,10.2,4.8)
  for _,side in ipairs({-1,1}) do
   hall(model,Vector3.new(side*11.5,1,2),6,14,7.2,3.5,paleStone)
   window(model,Vector3.new(side*11.5,5.6,9.2),2.3,3.3,true)
  end
  for _,x in ipairs({-7,-3.5,3.5,7}) do
   round(model,"StoneColumn",1,8.6,Vector3.new(x,5.2,1.8),paleStone,Enum.Material.Marble)
   block(model,"ColumnCapital",Vector3.new(1.6,.5,1.6),Vector3.new(x,9.5,1.8),plaster,Enum.Material.Marble)
  end
  block(model,"Portico",Vector3.new(19,1,6),Vector3.new(0,10,0),plaster,Enum.Material.Marble)
  roofAt(model,Vector3.new(0,11.9,0),20,7,3,roof,plaster)
  door(model,Vector3.new(0,1,-1.8),3.8,7)
  stairs(model,Vector3.new(0,0,6),17,4)
  round(model,"Cupola",5,4,Vector3.new(0,17,-7),plaster,Enum.Material.Marble)
  ball(model,"Roof",5.4,Vector3.new(0,19,-7),roof,Enum.Material.Slate)
  block(model,"Finial",Vector3.new(.7,1.7,.7),Vector3.new(0,21.6,-7),gold,Enum.Material.Metal)
  banner(model,Vector3.new(13,9,-2),team,5)
 elseif kind=="Monastery" then
  foundation(model,27,27)
  hall(model,Vector3.new(0,1,-2),12,21,11,6,paleStone)
  hall(model,Vector3.new(-9,1,1),5,15,6.5,3.5,plaster)
  for _,x in ipairs({-3.5,3.5}) do window(model,Vector3.new(x,8.1,8.75),1.9,4.3,true) end
  door(model,Vector3.new(0,1,8.75),3,6)
  block(model,"BellTower",Vector3.new(5.5,17,5.5),Vector3.new(6.8,9.5,-4.5),paleStone,Enum.Material.Brick)
  block(model,"BelfryOpening",Vector3.new(4,4.5,.2),Vector3.new(6.8,16.4,-1.65),dark)
  for _,x in ipairs({4.5,9.1}) do block(model,"StoneColumn",Vector3.new(.65,5,.65),Vector3.new(x,16.5,-1.3),plaster,Enum.Material.Concrete) end
  round(model,"Bell",2.4,2.6,Vector3.new(6.8,16.7,-.7),gold,Enum.Material.Metal)
  roofAt(model,Vector3.new(6.8,21,-4.5),8,8,6,roof,paleStone)
  block(model,"Finial",Vector3.new(.4,2.5,.4),Vector3.new(6.8,25.2,-4.5),gold,Enum.Material.Metal)
  stairs(model,Vector3.new(0,0,11),5.5,3)
  block(model,"GardenBed",Vector3.new(4,.4,8),Vector3.new(10,.95,7),Color3.fromRGB(98,80,49),Enum.Material.Ground)
  block(model,"Herbs",Vector3.new(3.3,.7,7),Vector3.new(10,1.5,7),Color3.fromRGB(100,135,68),Enum.Material.Grass)
  banner(model,Vector3.new(-10,6,9),team,4)
 elseif kind=="Mill" then
  foundation(model,17,17)
  hall(model,Vector3.new(3,.8,-2),8,8,6.3,3.7)
  round(model,"WindmillTower",6.5,13,Vector3.new(-3,7.3,-1),paleStone,Enum.Material.Brick)
  round(model,"StoneCourse",7,.6,Vector3.new(-3,8,-1),plaster,Enum.Material.Concrete)
  roofAt(model,Vector3.new(-3,16.2,-1),8,8,4,roof,paleStone)
  door(model,Vector3.new(3,.8,2.2),2.4,4.5)
  local hub=Vector3.new(-3,12.1,3.4)
  disc(model,"SailHub",1.5,.9,hub,gold,Enum.Material.Metal)
  for i=0,3 do
   local a=math.pi/4+i*math.pi/2
   local direction=Vector3.new(math.sin(a),math.cos(a),0)
   beam(model,i%2==0 and "SailVertical" or "SailHorizontal",hub,hub+direction*7.8,.35,timber)
   local sail=block(model,"CanvasSail",Vector3.new(1.9,4.7,.18),hub+direction*5,team,Enum.Material.Fabric)
   sail.CFrame*=CFrame.Angles(0,0,-a)
   local batten=block(model,"SailBatten",Vector3.new(.18,4.7,.25),hub+direction*5,cutWood)
   batten.CFrame=sail.CFrame*CFrame.new(.75,0,.04)
  end
  round(model,"Grindstone",3.2,.7,Vector3.new(4,1.25,5.5),stone,Enum.Material.Concrete)
  ball(model,"GrainSack",2.3,Vector3.new(7,2,4.7),straw,Enum.Material.Fabric)
 elseif kind=="LumberCamp" or kind=="MiningCamp" then
  foundation(model,17,17)
  block(model,"Storehouse",Vector3.new(13,5,.55),Vector3.new(0,3.3,-6),kind=="LumberCamp" and cutWood or stone,kind=="LumberCamp" and Enum.Material.WoodPlanks or Enum.Material.Cobblestone)
  for _,x in ipairs({-6,6}) do for _,z in ipairs({-5.5,1.5}) do block(model,"Post",Vector3.new(.7,6,.7),Vector3.new(x,3.8,z),timber) end end
  roofAt(model,Vector3.new(0,7.7,-2),15,10,3.5,roof)
  for _,x in ipairs({-6,6}) do beam(model,"TimberBrace",Vector3.new(x,4.4,1.5),Vector3.new(x+(x<0 and 2 or -2),6.8,1.5),.4,timber) end
  if kind=="LumberCamp" then
   for _,z in ipairs({3.3,5.2,7.1}) do block(model,"TimberPile",Vector3.new(12,1.7,1.7),Vector3.new(0,1.7,z),cutWood,Enum.Material.Wood).Shape=Enum.PartType.Cylinder end
   for _,z in ipairs({4.2,6.1}) do block(model,"TimberPile",Vector3.new(11,1.7,1.7),Vector3.new(0,3.2,z),timber,Enum.Material.Wood).Shape=Enum.PartType.Cylinder end
   block(model,"Sawbench",Vector3.new(6,2.5,2.5),Vector3.new(0,2.1,-1),timber,Enum.Material.WoodPlanks)
   block(model,"Saw",Vector3.new(5,.4,.15),Vector3.new(0,3.6,-1),iron,Enum.Material.Metal)
   for _,x in ipairs({-2.6,2.6}) do block(model,"SawHandle",Vector3.new(.45,1.1,.45),Vector3.new(x,3.7,-1),cutWood) end
  else
   block(model,"MineOpening",Vector3.new(5,.15,4),Vector3.new(-3,.85,-1),dark,Enum.Material.Slate)
   beam(model,"TimberBrace",Vector3.new(-5,.8,-2),Vector3.new(-3,6,-2),.65,timber)
   beam(model,"TimberBrace",Vector3.new(-1,.8,-2),Vector3.new(-3,6,-2),.65,timber)
   block(model,"WinchRope",Vector3.new(.15,4,.15),Vector3.new(-3,3.8,-2),straw)
   block(model,"OreCart",Vector3.new(4.5,2.2,3.4),Vector3.new(3,2.2,5.6),cutWood,Enum.Material.WoodPlanks)
   block(model,"Ore",Vector3.new(3.6,1.8,2.8),Vector3.new(3,3.8,5.6),stone,Enum.Material.Slate,"WedgePart")
   for _,x in ipairs({.6,5.4}) do block(model,"CartWheel",Vector3.new(.45,2,2),Vector3.new(x,1.7,5.6),timber,Enum.Material.Wood).Shape=Enum.PartType.Cylinder end
  end
  banner(model,Vector3.new(7,.8,0),team,6)
 elseif kind=="Tower" then
  foundation(model,15,15)
  tower(model,Vector3.new(0,.8,0),10,22.5)
  door(model,Vector3.new(0,.8,5.05),2.4,5.5)
  block(model,"Banner",Vector3.new(2.4,5,.15),Vector3.new(3.1,15.5,4.45),team,Enum.Material.Fabric)
  roofAt(model,Vector3.new(0,28,0),8,8,4,roof)
  banner(model,Vector3.new(0,30.2,0),team,4.5)
 elseif kind=="Wall" then
  block(model,"Foundation",Vector3.new(8,.8,6.8),Vector3.new(0,.4,0),stone,Enum.Material.Cobblestone)
  block(model,"StoneWall",Vector3.new(8,10.5,5.4),Vector3.new(0,5.65,0),stone,Enum.Material.Brick)
  block(model,"StoneCourse",Vector3.new(8,.55,5.8),Vector3.new(0,8.2,0),paleStone,Enum.Material.Concrete)
  block(model,"Parapet",Vector3.new(8,.7,6),Vector3.new(0,11,0),paleStone,Enum.Material.Concrete)
  for x=-3,3,3 do block(model,"Battlement",Vector3.new(2,1.9,6),Vector3.new(x,12.1,0),stone,Enum.Material.Brick) end
  block(model,"TeamTrim",Vector3.new(6,.6,.13),Vector3.new(0,8.2,2.98),team,Enum.Material.Fabric)
 elseif kind=="Castle" then
  foundation(model,49,45)
  block(model,"Keep",Vector3.new(23,23,22),Vector3.new(0,12.3,-3),paleStone,Enum.Material.Brick)
  block(model,"StoneCourse",Vector3.new(23.6,.8,22.6),Vector3.new(0,8,-3),stone,Enum.Material.Cobblestone)
  roofAt(model,Vector3.new(0,27.8,-3),27,26,8,roof,paleStone)
  for _,x in ipairs({-7,0,7}) do window(model,Vector3.new(x,19.2,8.2),2.4,4.4,true) end
  -- Curtain walls join the corner turrets; the gatehouse is a separate silhouette.
  for _,x in ipairs({-20,20}) do block(model,"StoneWall",Vector3.new(3,15,32),Vector3.new(x,8.3,0),stone,Enum.Material.Brick) end
  block(model,"StoneWall",Vector3.new(40,15,3),Vector3.new(0,8.3,-17),stone,Enum.Material.Brick)
  for _,x in ipairs({-13,13}) do block(model,"StoneWall",Vector3.new(13,14,3),Vector3.new(x,7.8,17),stone,Enum.Material.Brick) end
  for _,x in ipairs({-20,20}) do for _,z in ipairs({-17,17}) do tower(model,Vector3.new(x,.8,z),8,23) end end
  for _,side in ipairs({-1,1}) do
   block(model,"GatePier",Vector3.new(3.2,17,5.2),Vector3.new(side*5,9.3,17),paleStone,Enum.Material.Brick)
   block(model,"Banner",Vector3.new(2,5,.16),Vector3.new(side*5,12,19.72),team,Enum.Material.Fabric)
  end
  block(model,"GateRecess",Vector3.new(7,12,.3),Vector3.new(0,6.8,17.2),dark)
  block(model,"Gate",Vector3.new(6.6,10.5,.45),Vector3.new(0,6.1,17.5),cutWood,Enum.Material.WoodPlanks)
  block(model,"GateArch",Vector3.new(13.5,3.5,5.3),Vector3.new(0,16.2,17),paleStone,Enum.Material.Brick)
  for x=-2.5,2.5,1.25 do block(model,"Portcullis",Vector3.new(.22,10.5,.22),Vector3.new(x,6.2,17.85),iron,Enum.Material.Metal) end
  for _,y in ipairs({4,9}) do block(model,"GateBrace",Vector3.new(6.9,.3,.3),Vector3.new(0,y,17.9),iron,Enum.Material.Metal) end
  roofAt(model,Vector3.new(0,19.8,17),15,8,3.5,roof)
  for _,x in ipairs({-15,-9,9,15}) do block(model,"Battlement",Vector3.new(2.4,2.1,3.1),Vector3.new(x,15.8,17),paleStone,Enum.Material.Brick) end
  banner(model,Vector3.new(0,31.8,-3),team,7)
 elseif kind=="Wonder" then
  block(model,"Courtyard",Vector3.new(51,1.5,51),Vector3.new(0,.75,0),stone,Enum.Material.Marble)
  block(model,"Foundation",Vector3.new(39,2,36),Vector3.new(0,2,-2),paleStone,Enum.Material.Marble)
  block(model,"Temple",Vector3.new(29,20,24),Vector3.new(0,13,-4),plaster,Enum.Material.Marble)
  roofAt(model,Vector3.new(0,27,-4),34,29,8,roof,plaster)
  for _,x in ipairs({-11,-6,-2,2,6,11}) do
   round(model,"StoneColumn",1.3,15,Vector3.new(x,10.5,11),paleStone,Enum.Material.Marble)
   block(model,"ColumnCapital",Vector3.new(2,.6,2),Vector3.new(x,18.1,11),gold,Enum.Material.Metal)
  end
  block(model,"Portico",Vector3.new(29,1.2,8),Vector3.new(0,18.8,9.5),paleStone,Enum.Material.Marble)
  roofAt(model,Vector3.new(0,22.4,9.5),32,10,6,roof,plaster)
  door(model,Vector3.new(0,3,8.2),5,11)
  stairs(model,Vector3.new(0,0,23),24,5)
  for _,side in ipairs({-1,1}) do
   block(model,"Spire",Vector3.new(6,24,6),Vector3.new(side*19,13,-14),paleStone,Enum.Material.Marble)
   roofAt(model,Vector3.new(side*19,29,-14),8,8,8,roof,paleStone)
   block(model,"GildedCap",Vector3.new(.8,2.5,.8),Vector3.new(side*19,34,-14),gold,Enum.Material.Metal)
  end
  block(model,"Spire",Vector3.new(8,14,8),Vector3.new(0,34,-4),paleStone,Enum.Material.Marble)
  window(model,Vector3.new(0,36,.2),2.8,4,true)
  roofAt(model,Vector3.new(0,45,-4),11,11,9,roof,paleStone)
  block(model,"GildedCap",Vector3.new(1.4,4,1.4),Vector3.new(0,51,-4),gold,Enum.Material.Metal)
  for _,side in ipairs({-1,1}) do
   block(model,"Obelisk",Vector3.new(3,14,3),Vector3.new(side*21,8,20),paleStone,Enum.Material.Marble)
   block(model,"GildedCap",Vector3.new(3.7,2,3.7),Vector3.new(side*21,16,20),gold,Enum.Material.Metal,"WedgePart")
   block(model,"Banner",Vector3.new(2.1,6,.14),Vector3.new(side*21,11,21.57),team,Enum.Material.Fabric)
  end
 elseif kind=="Farm" then
  -- Harvest sweeps across the rows: cut rows leave pale stubble, an empty field lies fallow.
  block(model,"Soil",Vector3.new(23,.45,23),Vector3.new(0,.225,0),stage>=3 and Color3.fromRGB(96,72,44) or Color3.fromRGB(117,85,48),Enum.Material.Ground)
  local harvested=({[0]=0,2,5,7})[stage]
  for row=1,7 do
   local x=-12+row*3
   block(model,"Furrow",Vector3.new(2.7,.1,21),Vector3.new(x,.5,0),Color3.fromRGB(75,56,33),Enum.Material.Ground)
   if row>harvested then
    block(model,"CropRow",Vector3.new(1.15,.6,20),Vector3.new(x,.78,0),x%2==0 and Color3.fromRGB(176,165,72) or Color3.fromRGB(202,182,87),Enum.Material.Grass)
   elseif stage<3 then
    block(model,"Stubble",Vector3.new(.9,.16,20),Vector3.new(x,.6,0),Color3.fromRGB(150,132,84),Enum.Material.Grass)
   end
  end
  for _,side in ipairs({-1,1}) do
   block(model,"FieldBorder",Vector3.new(.35,.3,23),Vector3.new(side*11.25,.55,0),cutWood,Enum.Material.Wood)
   block(model,"FieldBorder",Vector3.new(22.5,.3,.35),Vector3.new(0,.55,side*11.25),cutWood,Enum.Material.Wood)
  end
  block(model,"TeamTrim",Vector3.new(4,.15,.6),Vector3.new(8,.75,10.5),team,Enum.Material.WoodPlanks)
 elseif kind=="Tree" then
  -- Four parts per tree across thousands of forest nodes: trunk plus three uniform crowns.
  -- The main crown spans the full width so the fitted canopy still covers forest spacing.
  -- Felling thins the canopy, cuts a pale notch and finally leaves a log by a small remnant crown.
  block(model,"Trunk",Vector3.new(1.8,8.5,1.8),Vector3.new(0,4.25,0),timber,Enum.Material.Wood)
  if stage<=0 then
   ball(model,"Crown",12,Vector3.new(0,10.2,0),Color3.fromRGB(58,100,58),Enum.Material.Grass)
   ball(model,"Crown",7,Vector3.new(2.6,12.6,1.8),Color3.fromRGB(76,121,66),Enum.Material.Grass)
   ball(model,"Crown",6.4,Vector3.new(-2.4,13,-1.9),Color3.fromRGB(98,139,74),Enum.Material.Grass)
  elseif stage==1 then
   ball(model,"Crown",9.2,Vector3.new(0,10.4,0),Color3.fromRGB(58,100,58),Enum.Material.Grass)
   ball(model,"Crown",5.4,Vector3.new(2,12.6,1.3),Color3.fromRGB(76,121,66),Enum.Material.Grass)
   block(model,"Cut",Vector3.new(2,.55,2),Vector3.new(0,1.3,0),cutWood,Enum.Material.Wood)
  else
   ball(model,"Crown",6.2,Vector3.new(0,10,0),Color3.fromRGB(76,121,66),Enum.Material.Grass)
   block(model,"Cut",Vector3.new(2,.9,2),Vector3.new(0,1.4,0),cutWood,Enum.Material.Wood)
   local log=block(model,"Log",Vector3.new(5.4,1.4,1.4),Vector3.new(2.8,.7,1.9),cutWood,Enum.Material.Wood)
   log.Shape=Enum.PartType.Cylinder
   log.CFrame*=CFrame.Angles(0,.7,0)
  end
 elseif kind=="Gold" or kind=="Stone" then
  -- A dominant boulder with smaller stones leaning on it; gold nuggets sit in the seams.
  local gold=kind=="Gold"
  local base=gold and Color3.fromRGB(128,116,98) or Color3.fromRGB(136,146,150)
  -- Mining removes the leaning stones first, then lowers the main boulder to rubble.
  local rocks=gold and ({[0]={
   {"Part",Vector3.new(5.6,4,5.2),Vector3.new(0,2,-.2),Vector3.new(.08,.35,-.06),0},
   {"Part",Vector3.new(4.2,3,3.8),Vector3.new(3,1.5,2),Vector3.new(-.1,-.5,.12),.12},
   {"WedgePart",Vector3.new(4.4,3,3.6),Vector3.new(-3,1.5,-1.6),Vector3.new(0,2.4,0),-.1},
   {"Part",Vector3.new(3,2.2,2.8),Vector3.new(.6,4.6,-.5),Vector3.new(.25,.9,.15),.2},
  },{
   {"Part",Vector3.new(5,3.3,4.6),Vector3.new(0,1.65,-.2),Vector3.new(.08,.35,-.06),0},
   {"Part",Vector3.new(3.7,2.5,3.3),Vector3.new(2.8,1.25,1.9),Vector3.new(-.1,-.5,.12),.12},
   {"WedgePart",Vector3.new(3.6,2.2,3),Vector3.new(-2.7,1.1,-1.5),Vector3.new(0,2.4,0),-.1},
  },{
   {"Part",Vector3.new(3.6,2.1,3.4),Vector3.new(0,1.05,-.2),Vector3.new(.06,.35,-.05),0},
   {"Part",Vector3.new(2.3,1.4,2.1),Vector3.new(2.3,.7,1.6),Vector3.new(-.08,-.5,.1),.12},
   {"Part",Vector3.new(1.5,.7,1.4),Vector3.new(-2.5,.35,-1.3),Vector3.new(0,.8,0),-.1},
  }})[math.min(stage,2)] or ({[0]={
   {"Part",Vector3.new(5.8,4.4,5.4),Vector3.new(0,2.2,-.3),Vector3.new(.1,.5,-.08),0},
   {"Part",Vector3.new(4.4,3.2,4),Vector3.new(2.9,1.6,2.3),Vector3.new(-.12,-.4,.16),.14},
   {"Part",Vector3.new(3.8,2.8,3.4),Vector3.new(-3.1,1.4,-1.7),Vector3.new(.08,.95,-.14),-.1},
   {"Part",Vector3.new(3.2,2.6,3),Vector3.new(-.5,4.9,-.3),Vector3.new(.45,.8,.35),.1},
  },{
   {"Part",Vector3.new(5.1,3.5,4.8),Vector3.new(0,1.75,-.3),Vector3.new(.1,.5,-.08),0},
   {"Part",Vector3.new(3.9,2.7,3.5),Vector3.new(2.7,1.35,2.1),Vector3.new(-.12,-.4,.16),.14},
   {"Part",Vector3.new(3.2,2.2,2.9),Vector3.new(-2.8,1.1,-1.6),Vector3.new(.08,.95,-.14),-.1},
  },{
   {"Part",Vector3.new(3.7,2.2,3.5),Vector3.new(0,1.1,-.2),Vector3.new(.08,.5,-.06),0},
   {"Part",Vector3.new(2.4,1.5,2.2),Vector3.new(2.3,.75,1.6),Vector3.new(-.1,-.4,.12),.14},
   {"Part",Vector3.new(1.5,.7,1.4),Vector3.new(-2.5,.35,-1.3),Vector3.new(0,.95,0),-.1},
  }})[math.min(stage,2)]
  for _,rock in ipairs(rocks) do
   local shade=rock[5]>=0 and base:Lerp(paleStone,rock[5]) or base:Lerp(dark,-rock[5])
   local p=block(model,"Rock",rock[2],rock[3],shade,Enum.Material.Slate,rock[1])
   p.CFrame*=CFrame.Angles(rock[4].X,rock[4].Y,rock[4].Z)
  end
  if gold then
   for _,nugget in ipairs(({[0]={
    {1.7,Vector3.new(-1.6,3.9,1),Vector3.new(.6,.7,.4)},
    {1.5,Vector3.new(2.3,3,2.7),Vector3.new(.4,.2,.7)},
    {1.8,Vector3.new(1.2,5.5,-1.2),Vector3.new(.7,.5,.2)},
    {1.3,Vector3.new(-2.6,2.4,-.6),Vector3.new(.3,.9,.5)},
   },{
    {1.6,Vector3.new(-1.4,3.2,.9),Vector3.new(.6,.7,.4)},
    {1.4,Vector3.new(2.2,2.5,2.5),Vector3.new(.4,.2,.7)},
    {1.2,Vector3.new(-2.4,1.9,-.6),Vector3.new(.3,.9,.5)},
   },{
    {1.3,Vector3.new(-.8,2.1,.7),Vector3.new(.6,.7,.4)},
    {1,Vector3.new(2,1.4,2),Vector3.new(.4,.2,.7)},
   }})[math.min(stage,2)]) do
    local p=block(model,"Ore",Vector3.new(nugget[1],nugget[1]*.8,nugget[1]),nugget[2],Color3.fromRGB(236,190,72),Enum.Material.Metal)
    p.CFrame*=CFrame.Angles(nugget[3].X,nugget[3].Y,nugget[3].Z)
   end
  end
 elseif kind=="Berries" then
  -- Three low leaf mounds with berry clusters set into their upper surfaces.
  -- Foraging strips the berries, then leaves two thinner, yellowing bushes.
  local picked=Color3.fromRGB(124,116,70)
  local mounds=stage>=2 and {
   {4.2,Vector3.new(-1.9,2.1,-.4),Color3.fromRGB(66,106,56):Lerp(picked,.35)},
   {3.8,Vector3.new(1.7,1.9,.7),Color3.fromRGB(88,130,66):Lerp(picked,.35)},
  } or {
   {5.2,Vector3.new(-2.5,2.6,-.6),Color3.fromRGB(66,106,56)},
   {4.8,Vector3.new(2.4,2.4,-.9),Color3.fromRGB(78,120,62)},
   {4.6,Vector3.new(.1,2.3,1.9),Color3.fromRGB(88,130,66)},
  }
  for _,mound in ipairs(mounds) do ball(model,"Bush",mound[1],mound[2],mound[3],Enum.Material.Grass) end
  local spots=({[0]={{1,Vector3.new(-.5,.6,.62)},{1,Vector3.new(-.2,.85,-.5)},{2,Vector3.new(.6,.55,.58)},
   {2,Vector3.new(.35,.8,-.5)},{3,Vector3.new(-.15,.6,.8)}},
   {{1,Vector3.new(-.5,.6,.62)},{2,Vector3.new(.35,.8,-.5)},{3,Vector3.new(-.15,.6,.8)}},
   {{1,Vector3.new(-.3,.8,.5)}}})[math.min(stage,2)]
  for i,spot in ipairs(spots) do
   local mound=mounds[spot[1]]
   ball(model,"Berry",1.3,mound[2]+spot[2].Unit*(mound[1]/2-.2),i%2==0 and Color3.fromRGB(184,54,72) or Color3.fromRGB(148,38,62))
  end
 elseif kind=="villager" or kind=="infantry" or kind=="spearman" or kind=="archer" or kind=="skirmisher" or kind=="scout" or kind=="cavalry" or kind=="monk" then
  person(model,kind,team)
 elseif kind=="ram" or kind=="mangonel" or kind=="trebuchet" then
  block(model,"Chassis",Vector3.new(5.6,.85,8),Vector3.new(0,2.3,0),cutWood,Enum.Material.WoodPlanks)
  for _,z in ipairs({-2.7,2.7}) do
   block(model,"Chassis",Vector3.new(7,.45,.45),Vector3.new(0,1.6,z),iron,Enum.Material.Metal)
   for _,x in ipairs({-3.2,3.2}) do
    block(model,"Wheel",Vector3.new(.6,3.2,3.2),Vector3.new(x,1.6,z),timber,Enum.Material.WoodPlanks).Shape=Enum.PartType.Cylinder
    block(model,"Wheel",Vector3.new(.68,1,1),Vector3.new(x,1.6,z),gold,Enum.Material.Metal).Shape=Enum.PartType.Cylinder
   end
  end
  if kind=="ram" then
   block(model,"RamLog",Vector3.new(1.8,1.8,10),Vector3.new(0,3.5,-1),cutWood,Enum.Material.Wood)
   block(model,"RamHead",Vector3.new(2.1,2.1,1.3),Vector3.new(0,3.5,-6),iron,Enum.Material.Metal)
   for _,x in ipairs({-2.4,2.4}) do for _,z in ipairs({-2.5,2.5}) do block(model,"Chassis",Vector3.new(.5,3.1,.5),Vector3.new(x,4.2,z),timber) end end
   roofAt(model,Vector3.new(0,6.3,0),6.8,8.8,2.8,roof)
   -- Hide-covered shed; the ridge and side banners carry the player color.
   for _,p in ipairs(model:GetChildren()) do
    if p.Name=="Roof" then
     p:SetAttribute("TeamColorPart",false)
     p.Color,p.Material=Color3.fromRGB(116,84,58),Enum.Material.Fabric
    end
   end
   for _,x in ipairs({-2.8,2.8}) do block(model,"SiegeBanner",Vector3.new(.13,1.7,3.6),Vector3.new(x,4.6,.4),team,Enum.Material.Fabric) end
  elseif kind=="mangonel" then
   for _,x in ipairs({-2,2}) do
    block(model,"CatapultPost",Vector3.new(.7,4.1,1),Vector3.new(x,4.1,0),timber)
    beam(model,"CatapultPost",Vector3.new(x,2.6,2.8),Vector3.new(x,5.7,0),.45,timber)
   end
   block(model,"Chassis",Vector3.new(5,.8,.8),Vector3.new(0,5.1,0),iron,Enum.Material.Metal)
   block(model,"CatapultArm",Vector3.new(.6,.7,7.4),Vector3.new(0,5.5,-1),cutWood,Enum.Material.Wood)
   block(model,"StoneBasket",Vector3.new(2.3,.7,2.3),Vector3.new(0,6,-4),timber,Enum.Material.WoodPlanks)
   ball(model,"StoneBasket",1.4,Vector3.new(0,6.8,-4),stone,Enum.Material.Slate)
   block(model,"SiegeBanner",Vector3.new(.12,1.8,2.5),Vector3.new(-2.5,4,.5),team,Enum.Material.Fabric)
  else
   -- The axle matches the client swing pivot, so arm, counterweight and sling stay joined.
   local axle=Vector3.new(0,9,0)
   for _,x in ipairs({-2,2}) do
    beam(model,"TrebuchetFrame",Vector3.new(x,2.7,-3),axle+Vector3.new(x,0,0),.7,timber)
    beam(model,"TrebuchetFrame",Vector3.new(x,2.7,3),axle+Vector3.new(x,0,0),.7,timber)
    block(model,"TrebuchetFrame",Vector3.new(.5,.5,3.8),Vector3.new(x,5.3,0),timber)
   end
   block(model,"Chassis",Vector3.new(5,.6,.6),axle,iron,Enum.Material.Metal).Shape=Enum.PartType.Cylinder
   local dir=Vector3.new(0,math.cos(.5),-math.sin(.5))
   local tip,heel=axle+dir*9,axle-dir*3
   segment(model,"TrebuchetArm",heel,tip,.6,.6,cutWood,Enum.Material.Wood)
   for _,x in ipairs({-.75,.75}) do block(model,"Counterweight",Vector3.new(.22,1.4,.22),heel+Vector3.new(x,-.6,0),iron,Enum.Material.Metal) end
   block(model,"Counterweight",Vector3.new(2.6,2.2,2.4),heel+Vector3.new(0,-2.4,0),cutWood,Enum.Material.WoodPlanks)
   block(model,"Counterweight",Vector3.new(2.2,.5,2),heel+Vector3.new(0,-1.2,0),stone,Enum.Material.Cobblestone)
   beam(model,"TrebuchetArm",tip,tip+Vector3.new(0,-3.2,-.4),.12,straw)
   block(model,"Sling",Vector3.new(1.2,.6,1.2),tip+Vector3.new(0,-3.5,-.45),team,Enum.Material.Fabric)
   block(model,"SiegeBanner",Vector3.new(.12,2,2.5),Vector3.new(-2.5,6,0),team,Enum.Material.Fabric)
  end
 end
 if applyPlayerColor~=false and (buildingKinds[kind] or unitKinds[kind]) then Art.ApplyPlayerColor(model,team) end
 return model
end
return Art
