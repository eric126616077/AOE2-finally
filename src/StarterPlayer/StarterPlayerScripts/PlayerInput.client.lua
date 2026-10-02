local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local GuiService=game:GetService("GuiService")
local player=Players.LocalPlayer
local initialTouchControlsEnabled=GuiService.TouchControlsEnabled
local defaultControls,initialControlsEnabled
local loadingControlModule
local controlsConnection
local controlProbe
local lobbyCharacterReady=false
local characterReadinessReason="notObserved"
local controlsDisposed=false
-- CharacterAdded precedes client replication of its Humanoid/root and Workspace parent.
-- Observe those facts without yielding the RTS camera or UI, and detach each old avatar.
local function observeCharacterReadiness(onChanged)
 local stopped=false
 local watchedCharacter,watchedHumanoid
 local revision=0
 local deferredRevision
 local heartbeatConnection
 local playerConnections,characterConnections,humanoidConnections={},{},{}
 local function disconnect(list)
  for _,connection in ipairs(list) do connection:Disconnect() end
  table.clear(list)
 end
 local function cancelHeartbeat()
  if heartbeatConnection then heartbeatConnection:Disconnect(); heartbeatConnection=nil end
 end
 local function stop()
  if stopped then return end
  stopped=true; revision+=1
  cancelHeartbeat()
  disconnect(playerConnections); disconnect(characterConnections); disconnect(humanoidConnections)
  watchedCharacter=nil; watchedHumanoid=nil
 end
 local function ready(character)
  if not character then return false,"missingCharacter" end
  if player.Character~=character then return false,"characterPropertyPending" end
  if not character:IsDescendantOf(workspace) then return false,"workspaceParentPending" end
  local humanoid=character:FindFirstChildOfClass("Humanoid")
  local root=character:FindFirstChild("HumanoidRootPart")
  if not humanoid then return false,"missingHumanoid" end
  if humanoid.Health<=0 then return false,"humanoidNotAlive" end
  if not root or not root:IsA("BasePart") then return false,"missingRootPart" end
  if humanoid.RootPart~=root then return false,"humanoidRootPending" end
  return true,"ready"
 end
 local refresh
 local function observeHumanoid()
  local character=watchedCharacter
  local humanoid=character and character:FindFirstChildOfClass("Humanoid")
  if watchedHumanoid~=humanoid then
   disconnect(humanoidConnections)
   watchedHumanoid=humanoid
   if humanoid then
    table.insert(humanoidConnections,humanoid:GetPropertyChangedSignal("RootPart"):Connect(refresh))
    table.insert(humanoidConnections,humanoid.HealthChanged:Connect(refresh))
    table.insert(humanoidConnections,humanoid.AncestryChanged:Connect(refresh))
   end
  end
 end
 local function publish()
  if stopped then return end
  observeHumanoid()
  if onChanged(ready(watchedCharacter)) then stop() end
 end
 refresh=function()
  if stopped then return end
  observeHumanoid()
  local isReady,reason=ready(watchedCharacter)
  if not isReady and onChanged(false,reason) then stop(); return end
  local capturedRevision=revision
  -- Replication events may run before their properties are committed. Always recheck.
  if deferredRevision~=capturedRevision then
   deferredRevision=capturedRevision
   task.defer(function()
    if stopped or revision~=capturedRevision then return end
    deferredRevision=nil
    publish()
   end)
  end
  -- One assembly synchronization point per real event batch; never a polling loop.
  if watchedCharacter and not heartbeatConnection then
   heartbeatConnection=RunService.Heartbeat:Connect(function()
    cancelHeartbeat()
    if stopped or revision~=capturedRevision then return end
    publish()
   end)
  end
 end
 local function bind(character)
  if stopped then return end
  revision+=1; deferredRevision=nil
  cancelHeartbeat()
  disconnect(characterConnections); disconnect(humanoidConnections)
  watchedCharacter=character; watchedHumanoid=nil
  if character then
   local function childChanged(child)
    if child:IsA("Humanoid") or child.Name=="HumanoidRootPart" then refresh() end
   end
   table.insert(characterConnections,character.ChildAdded:Connect(childChanged))
   table.insert(characterConnections,character.ChildRemoved:Connect(childChanged))
   table.insert(characterConnections,character.AncestryChanged:Connect(refresh))
  end
  refresh()
 end
 table.insert(playerConnections,player.CharacterAdded:Connect(bind))
 table.insert(playerConnections,player:GetPropertyChangedSignal("Character"):Connect(function()
  if player.Character~=watchedCharacter then bind(player.Character) else refresh() end
 end))
 table.insert(playerConnections,player.CharacterRemoving:Connect(function(character)
  if watchedCharacter==character then bind(nil) end
 end))
 table.insert(playerConnections,player.Destroying:Connect(stop))
 bind(player.Character)
 return stop
end
if RunService:IsStudio() then
 controlProbe=Instance.new("BindableFunction")
 controlProbe.Name="RTSControlProbe"
 controlProbe.OnInvoke=function()
  local active=defaultControls and defaultControls.activeController
  return {
   ready=defaultControls~=nil and player:GetAttribute("RTSDefaultControlsReady")==true,
   initial=initialControlsEnabled,
   lobbyCharacterReady=lobbyCharacterReady,
   characterReadinessReason=characterReadinessReason,
   controlsEnabled=defaultControls and defaultControls.controlsEnabled,
   hasActive=active~=nil,
   activeEnabled=active and active.enabled,
  }
 end
 controlProbe.Parent=script.Parent
end
local function updateDefaultControls()
 if controlsDisposed then return end
 local phase=workspace:GetAttribute("MatchPhase")
 local roomId=player:GetAttribute("LobbyRoomId")
 local roomStarting=roomId~=nil and workspace:GetAttribute("LobbyRoom_"..roomId.."_Status")=="Starting"
 local rtsPhase=roomStarting or (player:GetAttribute("InLobby")~=true and (phase=="Starting" or phase=="Playing" or phase=="Ended"))
 GuiService.TouchControlsEnabled=not rtsPhase and lobbyCharacterReady and initialTouchControlsEnabled
 if defaultControls then
  local enabled=not rtsPhase and lobbyCharacterReady and initialControlsEnabled
  local ok,err=pcall(function()
   if defaultControls.controlsEnabled~=enabled then defaultControls:Enable(enabled) end
  end)
  player:SetAttribute("RTSDefaultControlsReady",ok)
  player:SetAttribute("RTSDefaultControlsEnabled",defaultControls.controlsEnabled)
  if not ok then warn("[RTS] 無法切換預設角色控制："..tostring(err)) end
 end
end
-- Hide native touch UI immediately; Disable/Enable controls all legacy movement devices.
-- Loading PlayerModule may yield internally, so it must never hold up our RTS camera or UI.
local phaseControlsConnection=workspace:GetAttributeChangedSignal("MatchPhase"):Connect(updateDefaultControls)
local lobbyControlsConnection=player:GetAttributeChangedSignal("InLobby"):Connect(updateDefaultControls)
local roomControlsConnection=player:GetAttributeChangedSignal("LobbyRoomId"):Connect(updateDefaultControls)
local roomStatusControlsConnection=workspace.AttributeChanged:Connect(function(name)
 local roomId=player:GetAttribute("LobbyRoomId")
 if roomId and name=="LobbyRoom_"..roomId.."_Status" then updateDefaultControls() end
end)
-- Returning to Lobby can precede a complete client avatar. Restore only when usable.
local stopCharacterReadiness=observeCharacterReadiness(function(ready,reason)
 lobbyCharacterReady=ready
 characterReadinessReason=reason
 updateDefaultControls()
end)
updateDefaultControls()
local function attachDefaultControls(module)
 if defaultControls or loadingControlModule or not module:IsA("ModuleScript") or module.Name~="PlayerModule" then return end
 loadingControlModule=module
 task.spawn(function()
  local ok,controls=pcall(function()
   local api=require(module)
   assert(type(api)=="table" and type(api.GetControls)=="function","PlayerModule 未提供相容的控制介面")
   return api:GetControls()
  end)
  if controlsDisposed or not script.Parent then return end
  if not ok or type(controls)~="table" or type(controls.Enable)~="function" or type(controls.controlsEnabled)~="boolean" then
   warn("[RTS] 預設角色控制尚未接管，RTS/UI 繼續初始化："..tostring(controls))
   return
  end
  defaultControls=controls
  initialControlsEnabled=controls.controlsEnabled
  player:SetAttribute("RTSDefaultControlsInitialEnabled",initialControlsEnabled)
  updateDefaultControls()
  if controlsConnection then controlsConnection:Disconnect(); controlsConnection=nil end
 end)
end
-- PlayerInput already runs inside PlayerScripts; do not wait for CharacterAdded or PlayerModule.
controlsConnection=script.Parent.ChildAdded:Connect(attachDefaultControls)
local suppliedModule=script.Parent:FindFirstChild("PlayerModule")
if suppliedModule then attachDefaultControls(suppliedModule) end
script.Destroying:Connect(function()
 controlsDisposed=true
 if controlsConnection then controlsConnection:Disconnect() end
 phaseControlsConnection:Disconnect()
 lobbyControlsConnection:Disconnect()
 roomControlsConnection:Disconnect()
 roomStatusControlsConnection:Disconnect()
 stopCharacterReadiness()
 if controlProbe then controlProbe:Destroy() end
 local function restore()
  GuiService.TouchControlsEnabled=initialTouchControlsEnabled
  if defaultControls then pcall(function() defaultControls:Enable(initialControlsEnabled) end) end
 end
 -- Restore the original values when the next complete avatar is usable, then detach.
 -- This observer does not hold up teardown or reuse the removed RTS phase listener.
 GuiService.TouchControlsEnabled=false
 if defaultControls and defaultControls.controlsEnabled~=false then pcall(function() defaultControls:Enable(false) end) end
 observeCharacterReadiness(function(ready)
  if not ready then return end
  restore()
  return true
 end)
end)
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
local TouchRules=require(game.ReplicatedStorage.Shared.TouchRules)
local CameraFocus=require(game.ReplicatedStorage.Shared.CameraFocus)
local UI=require(game:GetService("StarterGui"):WaitForChild("GameUI"):WaitForChild("GUIManager"))
local focus=Vector3.zero
local height,targetHeight=160,160
local keys={}
local touches=TouchRules.new()
local lastGesture
local lastFocusRevision=0
local function isRTS()
 local phase=workspace:GetAttribute("MatchPhase")
 return player:GetAttribute("InLobby")~=true and (phase=="Playing" or phase=="Ended")
end
local function home()
 local spawn=player:GetAttribute("HomePosition")
 if spawn then
  focus=spawn+Vector3.new(spawn.X>0 and -28 or 28,0,spawn.Z>0 and -38 or 38)
 else focus=Vector3.zero end
end
local function blocked(point,processed)
 return not isRTS() or processed or UIS:GetFocusedTextBox()~=nil or player:GetAttribute("RTSModalOpen")==true
  or not UI.hitAreas or UI:IsModalOpen() or UI:BlocksPointer(point)
end
local function clearTouches()
 TouchRules.reset(touches); lastGesture=nil
 player:SetAttribute("RTSTouchGesture",false)
end
local function screenGround(camera,x,y)
 local inset=GuiService:GetGuiInset()
 local ray=camera:ScreenPointToRay(x-inset.X,y-inset.Y)
 if ray.Direction.Y>=-0.001 then return nil end
 local distance=-ray.Origin.Y/ray.Direction.Y
 return distance>=0 and ray.Origin+ray.Direction*distance or nil
end
home()
player:GetAttributeChangedSignal("HomePosition"):Connect(home)
local function applyFocusRequest()
 local revision=player:GetAttribute("CameraFocusRevision")
 if not CameraFocus.IsNew(revision,lastFocusRevision) then return end
 local value=player:GetAttribute("CameraFocus")
 if typeof(value)=="Vector3" then focus=value; lastFocusRevision=revision end
end
player:GetAttributeChangedSignal("CameraFocusRevision"):Connect(applyFocusRequest)
-- A request can arrive before this camera script binds its listener.
applyFocusRequest()
UIS.InputBegan:Connect(function(input,processed)
 if input.UserInputType==Enum.UserInputType.Touch then
  TouchRules.begin(touches,input,input.Position.X,input.Position.Y,os.clock(),blocked(Vector2.new(input.Position.X,input.Position.Y),processed))
  return
 end
 if not isRTS() or processed or UIS:GetFocusedTextBox() or player:GetAttribute("RTSModalOpen")==true or UI:IsModalOpen() then return end
 keys[input.KeyCode]=true
 if input.KeyCode==Enum.KeyCode.Home then home() end
end)
UIS.InputEnded:Connect(function(input)
 keys[input.KeyCode]=nil
 if input.UserInputType==Enum.UserInputType.Touch then
  TouchRules.finish(touches,input,input.Position.X,input.Position.Y,os.clock(),false)
 end
end)
UIS.WindowFocusReleased:Connect(function() table.clear(keys); clearTouches() end)
player:GetAttributeChangedSignal("RTSModalOpen"):Connect(function()
 if player:GetAttribute("RTSModalOpen")==true then table.clear(keys); clearTouches() end
end)
local function resetCameraInput()
 table.clear(keys); clearTouches()
 if isRTS() then home() end
end
workspace:GetAttributeChangedSignal("MatchPhase"):Connect(resetCameraInput)
player:GetAttributeChangedSignal("InLobby"):Connect(resetCameraInput)
UIS.InputChanged:Connect(function(input,processed)
 if input.UserInputType==Enum.UserInputType.Touch then
  TouchRules.move(touches,input,input.Position.X,input.Position.Y,blocked(Vector2.new(input.Position.X,input.Position.Y),processed))
  return
 end
 if isRTS() and not processed and player:GetAttribute("RTSModalOpen")~=true and not UI:IsModalOpen() and input.UserInputType==Enum.UserInputType.MouseWheel then
  player:SetAttribute("RTSInputMode","Mouse")
  targetHeight=math.clamp(targetHeight-input.Position.Z*16,65,360)
 end
end)
RunService:BindToRenderStep("RTSCamera",Enum.RenderPriority.Camera.Value+1,function(dt)
 local camera=workspace.CurrentCamera
 if not camera then return end
 if not isRTS() then
  local character=player.Character
  local humanoid=character and character:FindFirstChildOfClass("Humanoid")
  camera.FieldOfView=70
  if humanoid and humanoid.Health>0 then
   camera.CameraType=Enum.CameraType.Custom
   if camera.CameraSubject~=humanoid then camera.CameraSubject=humanoid end
  else
   -- Show the castle while a lobby avatar is being loaded. UI never waits for a character.
   local origin=Config.Lobby.origin
   camera.CameraType=Enum.CameraType.Scriptable
   camera.CFrame=CFrame.lookAt(origin+Vector3.new(52,58,82),origin+Vector3.new(0,12,-22))
  end
  return
 end
 local x,z=0,0
 if not UIS:GetFocusedTextBox() and player:GetAttribute("RTSModalOpen")~=true and not UI:IsModalOpen() then
  -- Re-check moving HUD boundaries; crossing UI stays blocked for the sequence.
  for _,id in ipairs(touches.order) do
   local point=touches.points[id]
   if blocked(Vector2.new(point.x,point.y),false) then point.blocked=true end
  end
  local pair=TouchRules.pair(touches)
  if pair and lastGesture and pair.a==lastGesture.a and pair.b==lastGesture.b then
   local previous=screenGround(camera,lastGesture.x,lastGesture.y)
   local current=screenGround(camera,pair.x,pair.y)
   if previous and current then focus+=previous-current end
   targetHeight=TouchRules.zoom(targetHeight,lastGesture.distance,pair.distance)
  end
  lastGesture=pair
  if player:GetAttribute("RTSTouchGesture")~=(pair~=nil) then player:SetAttribute("RTSTouchGesture",pair~=nil) end
  if keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up] then z-=1 end
  if keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down] then z+=1 end
  if keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left] then x-=1 end
  if keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right] then x+=1 end
  -- Edge scrolling is opt-in: Studio docks and command bar can sit beside the viewport.
  if player:GetAttribute("EdgeScroll")==true and player:GetAttribute("RTSInputMode")~="Touch" and workspace:GetAttribute("MatchPhase")=="Playing" then
   -- This Rect and GuiObject coordinates share the CoreUISafeInsets origin.
   -- Camera.ViewportSize uses a different origin that includes the top bar.
   local safeRect=GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
   local inset=GuiService:GetGuiInset()+safeRect.Min
   local size=safeRect.Max-safeRect.Min
   local raw=UIS:GetMouseLocation()
   local edgeX,edgeZ=TouchRules.edgeDirection(raw.X,raw.Y,inset.X,inset.Y,size.X,size.Y)
   x+=edgeX; z+=edgeZ
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
player:SetAttribute("RTSTouchCameraReady",true)
