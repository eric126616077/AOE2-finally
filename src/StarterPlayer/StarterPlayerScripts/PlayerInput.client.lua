local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
local player=Players.LocalPlayer
local focus=Vector3.zero
local height,targetHeight=160,160
local keys={}
local function home()
 local spawn=player:GetAttribute("HomePosition")
 if spawn then
  focus=spawn+Vector3.new(spawn.X>0 and -28 or 28,0,spawn.Z>0 and -38 or 38)
 else focus=Vector3.zero end
end
home()
player:GetAttributeChangedSignal("HomePosition"):Connect(home)
player:GetAttributeChangedSignal("CameraFocus"):Connect(function()
 local value=player:GetAttribute("CameraFocus")
 if typeof(value)=="Vector3" then focus=value end
end)
UIS.InputBegan:Connect(function(input,processed)
 if processed or UIS:GetFocusedTextBox() then return end
 keys[input.KeyCode]=true
 if input.KeyCode==Enum.KeyCode.Home then home() end
end)
UIS.InputEnded:Connect(function(input) keys[input.KeyCode]=nil end)
UIS.WindowFocusReleased:Connect(function() table.clear(keys) end)
UIS.InputChanged:Connect(function(input,processed)
 if not processed and input.UserInputType==Enum.UserInputType.MouseWheel then
  targetHeight=math.clamp(targetHeight-input.Position.Z*12,50,220)
 end
end)
RunService:BindToRenderStep("RTSCamera",Enum.RenderPriority.Camera.Value+1,function(dt)
 local camera=workspace.CurrentCamera
 if not camera then return end
 local x,z=0,0
 if not UIS:GetFocusedTextBox() then
  if keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up] then z-=1 end
  if keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down] then z+=1 end
  if keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left] then x-=1 end
  if keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right] then x+=1 end
 end
 local direction=Vector3.new(x,0,z)
 if direction.Magnitude>0 then focus+=direction.Unit*(keys[Enum.KeyCode.LeftShift] and 140 or 75)*math.min(dt,0.1) end
 local half=Config.Map.MapSize/2
 focus=Vector3.new(math.clamp(focus.X,-half,half),0,math.clamp(focus.Z,-half,half))
 height+=(targetHeight-height)*(1-math.exp(-12*dt))
 camera.CameraType=Enum.CameraType.Scriptable
 camera.FieldOfView=50
 camera.CFrame=CFrame.lookAt(focus+Vector3.new(0,height,height*0.75),focus)
end)
