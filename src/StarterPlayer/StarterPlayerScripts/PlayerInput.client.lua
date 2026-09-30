local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
local GuiService=game:GetService("GuiService")
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
 if processed or UIS:GetFocusedTextBox() or player:GetAttribute("RTSModalOpen")==true then return end
 keys[input.KeyCode]=true
 if input.KeyCode==Enum.KeyCode.Home then home() end
end)
UIS.InputEnded:Connect(function(input) keys[input.KeyCode]=nil end)
UIS.WindowFocusReleased:Connect(function() table.clear(keys) end)
player:GetAttributeChangedSignal("RTSModalOpen"):Connect(function()
 if player:GetAttribute("RTSModalOpen")==true then table.clear(keys) end
end)
UIS.InputChanged:Connect(function(input,processed)
 if not processed and player:GetAttribute("RTSModalOpen")~=true and input.UserInputType==Enum.UserInputType.MouseWheel then
  targetHeight=math.clamp(targetHeight-input.Position.Z*16,65,360)
 end
end)
RunService:BindToRenderStep("RTSCamera",Enum.RenderPriority.Camera.Value+1,function(dt)
 local camera=workspace.CurrentCamera
 if not camera then return end
 local x,z=0,0
 if not UIS:GetFocusedTextBox() and player:GetAttribute("RTSModalOpen")~=true then
  if keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up] then z-=1 end
  if keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down] then z+=1 end
  if keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left] then x-=1 end
  if keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right] then x+=1 end
  -- Edge scrolling is opt-in: Studio docks and command bar can sit beside the viewport.
  if player:GetAttribute("EdgeScroll")==true and workspace:GetAttribute("MatchPhase")=="Playing" then
   local inset=GuiService:GetGuiInset()
   local cursor=UIS:GetMouseLocation()-inset
   local viewport=camera.ViewportSize
   if cursor.X>=0 and cursor.Y>=0 and cursor.X<=viewport.X and cursor.Y<=viewport.Y then
    if cursor.X<10 then x-=1 elseif cursor.X>viewport.X-10 then x+=1 end
    if cursor.Y<10 then z-=1 elseif cursor.Y>viewport.Y-10 then z+=1 end
   end
  end
 end
 local direction=Vector3.new(x,0,z)
 if direction.Magnitude>0 then focus+=direction.Unit*(keys[Enum.KeyCode.LeftShift] and 220 or 110)*math.min(dt,0.1) end
 local half=(workspace:GetAttribute("MatchSize") or Config.Map.MapSize)/2
 focus=Vector3.new(math.clamp(focus.X,-half,half),0,math.clamp(focus.Z,-half,half))
 height+=(targetHeight-height)*(1-math.exp(-12*dt))
 camera.CameraType=Enum.CameraType.Scriptable
 camera.FieldOfView=50
 camera.CFrame=CFrame.lookAt(focus+Vector3.new(0,height,height*0.75),focus)
end)
