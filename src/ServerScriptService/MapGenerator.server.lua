local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
Players.CharacterAutoLoads=false
local ground=workspace:FindFirstChild("AOE2_Ground") or Instance.new("Part")
ground.Name="AOE2_Ground"
ground.Position=Vector3.new(0,-0.5,0)
ground.Anchored,ground.CanCollide,ground.CanQuery=true,true,true
ground.CanTouch,ground.CastShadow=false,false
ground.Transparency=0
ground.Material=Enum.Material.Grass
ground.Color=Color3.fromRGB(110,150,84)
ground.Parent=workspace
-- Bright early-afternoon sun with warm fill: the storybook palette stays saturated and
-- shadows are short enough not to bury units at RTS zoom.
Lighting.ClockTime=14.2
Lighting.Brightness=2.6
Lighting.Ambient=Color3.fromRGB(126,122,114)
Lighting.OutdoorAmbient=Color3.fromRGB(162,160,146)
Lighting.FogEnd=10000
Lighting.GlobalShadows=true
local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
 atmosphere=Instance.new("Atmosphere")
 atmosphere.Name="RTSAtmosphere"
 atmosphere.Parent=Lighting
end
atmosphere.Density=0.1
atmosphere.Haze=0.3
atmosphere.Color=Color3.fromRGB(232,232,210)
-- Reuse only our own grading effect; leave imported effects and the user's sky intact.
local grading
for _,effect in ipairs(Lighting:GetChildren()) do
 if effect:IsA("ColorCorrectionEffect") and effect:GetAttribute("RTSManagedColorGrade")==true then grading=effect; break end
end
if not grading then
 grading=Instance.new("ColorCorrectionEffect")
 grading.Name="RTSDaylightGrade"
 grading:SetAttribute("RTSManagedColorGrade",true)
 grading.Parent=Lighting
end
grading.Brightness=0.02
grading.Contrast=0.08
grading.Saturation=0.1
grading.TintColor=Color3.fromRGB(255,251,240)
local function buildScenery()
 local size=workspace:GetAttribute("MapSize") or Config.Map.MapSize
 if type(size)~="number" or size~=size or size<256 or size>2048 then return end
 ground.Size=Vector3.new(size,1,size)
 -- Only folders explicitly marked as ours may be replaced. Unknown scenery survives.
 for _,old in ipairs(workspace:GetChildren()) do
  if old:IsA("Folder") and old:GetAttribute("RTSManagedScenery")==true then old:Destroy() end
 end
 local scenery=Instance.new("Folder")
 scenery.Name=workspace:FindFirstChild("RTSScenery") and "RTSManagedScenery" or "RTSScenery"
 scenery:SetAttribute("RTSManagedScenery",true)
 scenery.Parent=workspace
 local function decor(name,dimensions,pos,color,material)
  local part=Instance.new("Part")
  part.Name,part.Size,part.Position=name,dimensions,pos
  part.Anchored,part.CanCollide,part.CanQuery,part.CanTouch=true,false,false,false
  part.CastShadow=false
  part.Color,part.Material=color,material
  part.Parent=scenery
  return part
 end
 decor("SurroundingWater",Vector3.new(size+1024,1,size+1024),Vector3.new(0,-6,0),Color3.fromRGB(72,128,148),Enum.Material.SmoothPlastic)
 local half,base=size/2,size/2-168
 local spawns={Vector3.new(-base,0,-base),Vector3.new(base,0,base),Vector3.new(base,0,-base),Vector3.new(-base,0,base)}
 for _,spawn in ipairs(spawns) do
  decor("BaseCourtyard",Vector3.new(83,0.08,83),spawn+Vector3.new(0,0.03,0),Color3.fromRGB(186,170,132),Enum.Material.Ground)
  -- One opaque strip per avenue instead of overlapping transparent tiles.
  -- Leave the courtyard and crossroads on top of each end of the strip.
  local distance=spawn.Magnitude
  local length=math.max(1,distance-88)
  local center=spawn.Unit*(44+length/2)
  local path=decor("TradePath",Vector3.new(Config.Map.RoadWidth,0.05,length),center+Vector3.new(0,0.03,0),Color3.fromRGB(178,162,126),Enum.Material.Ground)
  path.CFrame=CFrame.lookAt(path.Position,Vector3.new(0,path.Position.Y,0))
 end
 decor("CentralCrossroads",Vector3.new(72,0.08,72),Vector3.new(0,0.035,0),Color3.fromRGB(182,166,130),Enum.Material.Ground)
 local random=Random.new(workspace:GetAttribute("MapSeed") or Config.Map.Seed)
 for index=1,math.floor(size/32) do
  local p=decor("Meadow",Vector3.new(random:NextInteger(24,54),0.05,random:NextInteger(24,54)),Vector3.new(random:NextInteger(-half+40,half-40),0.026,random:NextInteger(-half+40,half-40)),Color3.fromRGB(100+random:NextInteger(0,10),142+random:NextInteger(0,12),76+random:NextInteger(0,8)),Enum.Material.Grass)
  p.Shape=Enum.PartType.Ball
  p.CFrame*=CFrame.Angles(0,random:NextNumber(0,math.pi),0)
 end
 for _,side in ipairs({-1,1}) do
  decor("RockyShore",Vector3.new(size+20,5,8),Vector3.new(0,-2,side*(half+4)),Color3.fromRGB(116,110,90),Enum.Material.Rock)
  decor("RockyShore",Vector3.new(8,5,size+20),Vector3.new(side*(half+4),-2,0),Color3.fromRGB(116,110,90),Enum.Material.Rock)
 end
 workspace:SetAttribute("SceneryPartCount",#scenery:GetChildren())
 workspace:SetAttribute("MapReady",true)
end
buildScenery()
workspace:GetAttributeChangedSignal("MapSize"):Connect(buildScenery)
workspace:GetAttributeChangedSignal("MapSeed"):Connect(buildScenery)
if workspace.StreamingEnabled then warn("[RTS] 無角色 RTS 必須停用 StreamingEnabled；請重新同步 Rojo 並重啟 Play。") end
