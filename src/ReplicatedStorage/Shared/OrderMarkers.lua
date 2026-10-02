-- Client-only order confirmation visuals, in the spirit of AOE's click markers:
-- a shrinking ring where units will walk, or a brief outline flash on the
-- target of an attack, gather or build order. Never queried, never collides.
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local Players=game:GetService("Players")
local Markers={}
local MAX_ACTIVE=6
local colors={
 move=Color3.fromRGB(150,232,128), attack=Color3.fromRGB(240,72,56),
 gather=Color3.fromRGB(246,214,104), build=Color3.fromRGB(246,214,104), rally=Color3.fromRGB(120,180,255),
}
local folder
local active={}
local function container()
 if folder and folder.Parent then return folder end
 folder=Instance.new("Folder")
 folder.Name="RTSOrderMarkers"
 folder.Parent=workspace
 return folder
end
local function reduced()
 return Players.LocalPlayer:GetAttribute("ReducedMotion")==true
end
local function track(object,lifetime)
 table.insert(active,object)
 while #active>MAX_ACTIVE do
  local oldest=table.remove(active,1)
  if oldest then oldest:Destroy() end
 end
 object.Destroying:Once(function()
  local index=table.find(active,object)
  if index then table.remove(active,index) end
 end)
 Debris:AddItem(object,lifetime)
end
local function ring(parent,position,radius,color,thickness)
 local part=Instance.new("Part")
 part.Name="OrderRing"
 part.Shape=Enum.PartType.Cylinder
 part.Size=Vector3.new(thickness or .12,radius*2,radius*2)
 -- A cylinder's axis is X; roll it flat onto the ground.
 part.CFrame=CFrame.new(position)*CFrame.Angles(0,0,math.rad(90))
 part.Anchored,part.CanCollide,part.CanQuery,part.CanTouch,part.CastShadow=true,false,false,false,false
 part.Material=Enum.Material.Neon
 part.Color=color
 part.Transparency=.25
 part.Parent=parent
 return part
end
function Markers:Ground(position,kind)
 if typeof(position)~="Vector3" then return end
 local color=colors[kind] or colors.move
 local marker=Instance.new("Model")
 marker.Name="OrderMarker"
 local base=position+Vector3.new(0,.15,0)
 local outer=ring(marker,base,2.6,color,.1)
 local inner=ring(marker,base+Vector3.new(0,.02,0),.7,Color3.new(1,1,1),.12)
 marker.Parent=container()
 track(marker,.9)
 if reduced() then return end
 local info=TweenInfo.new(.55,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
 TweenService:Create(outer,info,{Size=Vector3.new(.1,1.2,1.2),Transparency=1}):Play()
 TweenService:Create(inner,TweenInfo.new(.7),{Transparency=1}):Play()
end
function Markers:Target(model,kind)
 if typeof(model)~="Instance" or not model:IsA("Model") or not model.Parent then return end
 local highlight=Instance.new("Highlight")
 highlight.Name="OrderFlash"
 highlight.Adornee=model
 highlight.FillColor=colors[kind] or colors.attack
 highlight.OutlineColor=colors[kind] or colors.attack
 highlight.FillTransparency=.7
 highlight.OutlineTransparency=0
 highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
 highlight.Parent=container()
 track(highlight,.75)
 if reduced() then return end
 -- Two quick blinks read as "target acquired" without lingering on screen.
 local info=TweenInfo.new(.18,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,1,true)
 TweenService:Create(highlight,info,{OutlineTransparency=.8,FillTransparency=1}):Play()
 task.delay(.38,function()
  if highlight.Parent then TweenService:Create(highlight,TweenInfo.new(.3),{OutlineTransparency=1,FillTransparency=1}):Play() end
 end)
end
function Markers:Clear()
 for _,object in ipairs(table.clone(active)) do object:Destroy() end
 table.clear(active)
end
return Markers
