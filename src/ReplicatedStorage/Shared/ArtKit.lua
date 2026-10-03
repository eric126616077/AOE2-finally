-- Shared palette and primitives for the original fallback art (see Art.lua for the public API).
-- Every builder module draws with these so buildings, units and nature share one look.
local K={}
-- One warm storybook palette. Team color is an accent (ridges, banners, shields, awnings),
-- never the whole building, so the materials below carry each silhouette.
local stone=Color3.fromRGB(160,154,140)
local paleStone=Color3.fromRGB(208,199,180)
local timber=Color3.fromRGB(88,60,40)
local cutWood=Color3.fromRGB(164,120,72)
local plaster=Color3.fromRGB(234,218,182)
local roof=Color3.fromRGB(84,96,110)
local iron=Color3.fromRGB(77,87,91)
local dark=Color3.fromRGB(43,47,43)
local straw=Color3.fromRGB(204,172,92)
local gold=Color3.fromRGB(214,174,74)
-- Roof families: clay tile for civic / military halls, thatch for homes and work sheds,
-- slate (the `roof` color above) for stone fortifications and sacred buildings.
local tile=Color3.fromRGB(178,86,58)
local tileDark=Color3.fromRGB(140,64,46)
local thatch=Color3.fromRGB(198,168,96)
local thatchDark=Color3.fromRGB(158,128,68)
local wallShade=Color3.fromRGB(206,186,150)
local earth=Color3.fromRGB(140,116,80)
local leaf=Color3.fromRGB(84,134,66)
local leafDark=Color3.fromRGB(56,104,58)
local leafLight=Color3.fromRGB(128,168,80)
local steel=Color3.fromRGB(156,168,174)
local skin=Color3.fromRGB(230,190,146)
local leather=Color3.fromRGB(98,68,44)
local buildingKinds={Castle=true,TownCenter=true,House=true,Barracks=true,ArcheryRange=true,Stable=true,
 SiegeWorkshop=true,Blacksmith=true,Market=true,University=true,Monastery=true,Mill=true,LumberCamp=true,
 MiningCamp=true,Tower=true,Wall=true,Gate=true,Wonder=true,Farm=true,Palisade=true,Outpost=true}
local unitKinds={villager=true,infantry=true,spearman=true,archer=true,skirmisher=true,scout=true,
 cavalry=true,monk=true,ram=true,mangonel=true,trebuchet=true,cavalryArcher=true,camel=true,handCannoneer=true,tradeCart=true,scorpion=true,bombardCannon=true,sheep=true}
local teamColorNames={Roof=true,Banner=true,Flag=true,Tabard=true,Shield=true,Saddle=true,Ridge=true,
 Awning=true,CanvasSail=true,TeamTrim=true,Cuff=true,TeamPatch=true,Bullseye=true,Shutter=true,
 Sling=true,HatBand=true,HorseCloth=true,SiegeBanner=true}
-- Imported templates can opt individual parts in/out with TeamColorPart.
function K.ApplyPlayerColor(model,team)
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
local roofNames={Roof=true,RoofTile=true,Ridge=true,Spire=true,GildedCap=true,CanvasSail=true,Banner=true,Eave=true,
 RoofFascia=true,RoofShadow=true,Awning=true,CanopyStripe=true,Finial=true,Flag=true,Flagpole=true,TeamTrim=true}
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
function K.AddPlayerMarker(model,team)
 if typeof(team)~="Color3" then return end
 -- Add only after fitting an imported copy, without affecting its scale/footprint.
 local box,bounds=model:GetBoundingBox()
 local marker=block(model,"Banner",Vector3.new(math.min(bounds.X*.24,4),math.min(bounds.Y*.2,3),.12),box.Position,team,Enum.Material.Fabric)
 marker.CFrame=box*CFrame.new(0,bounds.Y*.18,bounds.Z/2+.08)
 marker:SetAttribute("ConstructionStage",3)
 marker.CanQuery=false
end
-- Gabled roof. Ridge runs along X, or along Z with axis=="z". Planes take the roof family
-- color (tile / thatch / slate) and stay neutral; only the ridge cap wears the player color,
-- so an owner still reads from the top-down camera without painting the whole building.
local function roofMaterial(color)
 return (color==thatch or color==thatchDark) and Enum.Material.Sand
  or (color==tile or color==tileDark) and Enum.Material.Brick or Enum.Material.Slate
end
local function roofAt(model,center,width,depth,height,color,wallColor,axis)
 color=color or tile
 local angle=math.atan(height/(depth/2))
 local slope=math.sqrt((depth/2)^2+height^2)
 local eaveY=center.Y-height/2
 local siege=unitKinds[model.Name]
 local material=roofMaterial(color)
 local thick=(color==thatch or color==thatchDark) and .9 or .6
 local parts={}
 local function add(part) table.insert(parts,part); return part end
 for _,side in ipairs({-1,1}) do
  -- Thin roof planes make a real ridge and readable overhanging eaves.
  local p=add(block(model,siege and "Roof" or "RoofTile",Vector3.new(width,thick,slope+.35),center+Vector3.new(0,0,side*depth/4),color,material))
  p.CFrame*=CFrame.Angles(side*angle,0,0)
  add(block(model,siege and "Chassis" or "Eave",Vector3.new(width+.15,.45,.55),Vector3.new(center.X,eaveY,center.Z+side*depth/2),timber,Enum.Material.Wood))
 end
 add(block(model,"Ridge",Vector3.new(width+.5,.7,1.1),center+Vector3.new(0,height/2+.2,0),color,Enum.Material.Fabric))
 if not siege then
  for _,side in ipairs({-1,1}) do
   local x=center.X+side*(width/2-.6)
   if wallColor then
    for _,zside in ipairs({-1,1}) do
     local p=add(block(model,"Gable",Vector3.new(.25,height,depth/2-.7),Vector3.new(x,center.Y,center.Z+zside*(depth/4-.175)),wallColor,Enum.Material.Concrete,"WedgePart"))
     if zside>0 then p.CFrame*=CFrame.Angles(0,math.pi,0) end
    end
   end
   for _,zside in ipairs({-1,1}) do
    add(beam(model,"RoofFascia",Vector3.new(x,eaveY,center.Z+zside*depth/2),Vector3.new(x,center.Y+height/2,center.Z),.43,timber,Enum.Material.Wood))
   end
  end
 end
 if axis=="z" then turn(parts,center,CFrame.Angles(0,math.pi/2,0)) end
 return parts
end
-- Stepped cone for round towers and silos: stacked discs, widest at the base.
local function cone(model,name,base,diameter,height,steps,color,material)
 steps=steps or 3
 local parts={}
 for i=1,steps do
  local t=(i-1)/steps
  table.insert(parts,round(model,name,diameter*(1-t)+.2,height/steps,base+Vector3.new(0,height*(i-.5)/steps,0),color,material or roofMaterial(color)))
 end
 return parts
end
local function foundation(model,width,depth)
 block(model,"Foundation",Vector3.new(width,.8,depth),Vector3.new(0,.4,0),stone,Enum.Material.Cobblestone)
end
-- Plinth, timber-framed walls and a gabled roof. roofColor defaults to clay tile.
local function hall(model,base,width,depth,height,roofHeight,color,roofColor,axis)
 color=color or plaster
 block(model,"StonePlinth",Vector3.new(width+.65,1.25,depth+.65),base+Vector3.new(0,.6,0),stone,Enum.Material.Cobblestone)
 block(model,"Walls",Vector3.new(width,height,depth),base+Vector3.new(0,height/2,0),color,Enum.Material.Concrete)
 for _,x in ipairs({-width/2,width/2}) do for _,z in ipairs({-depth/2,depth/2}) do
  block(model,"Beam",Vector3.new(.65,height+.35,.65),base+Vector3.new(x,height/2,z),timber,Enum.Material.Wood)
 end end
 for _,z in ipairs({-depth/2,depth/2}) do block(model,"Beam",Vector3.new(width+.4,.65,.5),base+Vector3.new(0,height-.2,z),timber,Enum.Material.Wood) end
 if axis=="z" then roofAt(model,base+Vector3.new(0,height+roofHeight/2,0),depth+2,width+2,roofHeight,roofColor,color,"z")
 else roofAt(model,base+Vector3.new(0,height+roofHeight/2,0),width+2,depth+2,roofHeight,roofColor,color) end
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
for name,value in pairs({tile=tile,tileDark=tileDark,thatch=thatch,thatchDark=thatchDark,wallShade=wallShade,earth=earth,leaf=leaf,leafDark=leafDark,leafLight=leafLight,steel=steel,skin=skin,leather=leather,cone=cone,roofMaterial=roofMaterial,stone=stone,paleStone=paleStone,timber=timber,cutWood=cutWood,plaster=plaster,roof=roof,iron=iron,dark=dark,straw=straw,gold=gold,block=block,beam=beam,round=round,disc=disc,ball=ball,segment=segment,plate=plate,point=point,turn=turn,roofAt=roofAt,foundation=foundation,hall=hall,door=door,window=window,banner=banner,stairs=stairs,fence=fence,barrel=barrel,chimney=chimney,tower=tower,buildingKinds=buildingKinds,unitKinds=unitKinds,teamColorNames=teamColorNames}) do K[name]=value end
return K
