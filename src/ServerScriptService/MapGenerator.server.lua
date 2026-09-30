local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
Players.CharacterAutoLoads=false
local ground=workspace:FindFirstChild("AOE2_Ground") or Instance.new("Part")
ground.Name="AOE2_Ground"
ground.Position=Vector3.new(0,-0.5,0)
ground.Anchored,ground.CanCollide,ground.CanQuery=true,true,true
ground.Transparency=0
ground.Material=Enum.Material.Grass
ground.Color=Color3.fromRGB(121,144,88)
ground.Parent=workspace
Lighting.ClockTime=14.5
Lighting.Brightness=2.4
Lighting.Ambient=Color3.fromRGB(110,115,107)
Lighting.OutdoorAmbient=Color3.fromRGB(152,157,142)
Lighting.FogEnd=10000
Lighting.GlobalShadows=true
local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
 atmosphere=Instance.new("Atmosphere")
 atmosphere.Name="RTSAtmosphere"
 atmosphere.Parent=Lighting
end
atmosphere.Density=0.16
atmosphere.Haze=0.6
atmosphere.Color=Color3.fromRGB(222,228,204)
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
  part.Color,part.Material=color,material
  part.Parent=scenery
  return part
 end
 decor("SurroundingWater",Vector3.new(size+1024,1,size+1024),Vector3.new(0,-6,0),Color3.fromRGB(73,115,131),Enum.Material.SmoothPlastic)
 local half,base=size/2,size/2-168
 local spawns={Vector3.new(-base,0,-base),Vector3.new(base,0,base),Vector3.new(base,0,-base),Vector3.new(-base,0,base)}
 for _,spawn in ipairs(spawns) do
  decor("BaseCourtyard",Vector3.new(83,0.08,83),spawn+Vector3.new(0,0.03,0),Color3.fromRGB(155,148,112),Enum.Material.Ground)
  local inward=Vector3.new(spawn.X>0 and -1 or 1,0,spawn.Z>0 and -1 or 1)
  for index=1,math.floor(base/22) do
   decor("TradePath",Vector3.new(29,0.05,29),spawn+Vector3.new(inward.X*index*22,0.035,inward.Z*index*22),Color3.fromRGB(151,146,108),Enum.Material.Ground).Transparency=0.35
  end
 end
 decor("CentralCrossroads",Vector3.new(72,0.08,72),Vector3.new(0,0.035,0),Color3.fromRGB(153,148,112),Enum.Material.Ground).Transparency=0.25
 local random=Random.new(Config.Map.Seed)
 for index=1,math.floor(size/5) do
  local p=decor("Meadow",Vector3.new(random:NextInteger(12,38),0.03,random:NextInteger(12,38)),Vector3.new(random:NextInteger(-half+10,half-10),0.02,random:NextInteger(-half+10,half-10)),Color3.fromRGB(111+random:NextInteger(0,12),135+random:NextInteger(0,15),79),Enum.Material.Grass)
  p.CFrame*=CFrame.Angles(0,random:NextNumber(0,math.pi),0)
  p.Transparency=0.65
 end
 for _,side in ipairs({-1,1}) do
  decor("RockyShore",Vector3.new(size+20,5,8),Vector3.new(0,-2,side*(half+4)),Color3.fromRGB(116,110,90),Enum.Material.Rock)
  decor("RockyShore",Vector3.new(8,5,size+20),Vector3.new(side*(half+4),-2,0),Color3.fromRGB(116,110,90),Enum.Material.Rock)
 end
 workspace:SetAttribute("MapReady",true)
end
buildScenery()
workspace:GetAttributeChangedSignal("MapSize"):Connect(buildScenery)
if workspace.StreamingEnabled then warn("[RTS] 無角色 RTS 必須停用 StreamingEnabled；請重新同步 Rojo 並重啟 Play。") end
