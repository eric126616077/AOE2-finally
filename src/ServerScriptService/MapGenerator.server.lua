local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
Players.CharacterAutoLoads=false
local ground=workspace:FindFirstChild("AOE2_Ground") or Instance.new("Part")
ground.Name="AOE2_Ground"
ground.Size=Vector3.new(Config.Map.MapSize,1,Config.Map.MapSize)
ground.Position=Vector3.new(0,-0.5,0)
ground.Anchored,ground.CanCollide,ground.CanQuery=true,true,true
ground.Transparency=0
ground.Material=Enum.Material.Grass
ground.Color=Color3.fromRGB(120,143,86)
ground.Parent=workspace
Lighting.ClockTime=14
Lighting.Brightness=2.4
Lighting.Ambient=Color3.fromRGB(110,115,107)
Lighting.OutdoorAmbient=Color3.fromRGB(152,157,142)
Lighting.FogEnd=10000
Lighting.GlobalShadows=true
local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere then atmosphere.Density=0.18; atmosphere.Haze=0.8; atmosphere.Color=Color3.fromRGB(222,228,204) end
local old=workspace:FindFirstChild("RTSScenery")
if old then old:Destroy() end
local scenery=Instance.new("Folder")
scenery.Name="RTSScenery"
scenery.Parent=workspace
local function decor(name,size,pos,color,material)
 local p=Instance.new("Part")
 p.Name,p.Size,p.Position=name,size,pos
 p.Anchored,p.CanCollide,p.CanQuery,p.CanTouch=true,false,false,false
 p.Color,p.Material=color,material
 p.Parent=scenery
 return p
end
decor("SurroundingWater",Vector3.new(2048,1,2048),Vector3.new(0,-6,0),Color3.fromRGB(73,115,131),Enum.Material.SmoothPlastic)
-- Low relief ground detail never participates in gameplay raycasts or navigation.
for _,spawn in ipairs(Config.Spawns) do
 decor("BaseCourtyard",Vector3.new(77,0.08,77),spawn+Vector3.new(0,0.03,0),Color3.fromRGB(155,148,112),Enum.Material.Ground)
 local inward=Vector3.new(spawn.X>0 and -1 or 1,0,spawn.Z>0 and -1 or 1)
 for i=1,8 do
  decor("Path",Vector3.new(13,0.07,13),spawn+Vector3.new(inward.X*i*10,0.035,inward.Z*i*10),Color3.fromRGB(150,145,100),Enum.Material.Ground)
 end
end
local random=Random.new(871)
for i=1,70 do
 local p=decor("Meadow",Vector3.new(random:NextInteger(8,25),0.03,random:NextInteger(8,25)),Vector3.new(random:NextInteger(-248,248),0.02,random:NextInteger(-248,248)),Color3.fromRGB(111+random:NextInteger(0,12),135+random:NextInteger(0,15),79),Enum.Material.Grass)
 p.CFrame*=CFrame.Angles(0,random:NextNumber(0,math.pi),0)
 p.Transparency=0.78
end
local half=Config.Map.MapSize/2
for _,side in ipairs({-1,1}) do
 decor("Border",Vector3.new(Config.Map.MapSize+20,5,8),Vector3.new(0,-2,side*(half+4)),Color3.fromRGB(116,110,90),Enum.Material.Rock)
 decor("Border",Vector3.new(8,5,Config.Map.MapSize+20),Vector3.new(side*(half+4),-2,0),Color3.fromRGB(116,110,90),Enum.Material.Rock)
end
workspace:SetAttribute("MapReady",true)
if workspace.StreamingEnabled then warn("[RTS] StreamingEnabled must be false for the avatar-free RTS. Reconnect Rojo and restart Play.") end
