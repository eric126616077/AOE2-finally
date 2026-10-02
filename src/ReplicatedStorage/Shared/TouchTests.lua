-- Explicit, read-only Studio CLIENT checks. Run after joining a new Play session.
-- Reads the live PlayerGui rather than assuming Command Bar shares GUI module state.
local Tests={}
local function studioClient()
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"僅限 Studio Play 客戶端")
 return game.Players.LocalPlayer
end
local function visibleInTree(object)
 local current=object
 while current do
  if current:IsA("GuiObject") and not current.Visible then return false end
  if current:IsA("ScreenGui") and not current.Enabled then return false end
  current=current.Parent
 end
 return object.Parent~=nil
end
local function painted(object)
 if not object:IsA("GuiObject") or object.AbsoluteSize.X<=0 or object.AbsoluteSize.Y<=0 then return false end
 if object.BackgroundTransparency<1 then return true end
 if (object:IsA("ImageLabel") or object:IsA("ImageButton")) and object.Image~="" and object.ImageTransparency<1 then return true end
 if (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) and object.Text~="" and object.TextTransparency<1 then return true end
 return false
end
local function visibleNativeControl(player)
 local touchGui=player.PlayerGui:FindFirstChild("TouchGui")
 if not touchGui then return nil end
 for _,object in ipairs(touchGui:GetDescendants()) do
  if painted(object) and visibleInTree(object) then return object end
 end
 return nil
end
local function overlapAt(screen,point,ignore,Rules)
 for _,object in ipairs(screen:GetDescendants()) do
  if object~=ignore and not (ignore and object:IsDescendantOf(ignore)) and painted(object) and visibleInTree(object) then
   local pos,size=object.AbsolutePosition,object.AbsoluteSize
   if Rules.inRect(point.X,point.Y,pos.X,pos.Y,size.X,size.Y) then return object end
  end
 end
 return nil
end
function Tests.Run()
 local player=studioClient()
 local UIS=game:GetService("UserInputService")
 local GuiService=game:GetService("GuiService")
 local Rules=require(game.ReplicatedStorage.Shared.TouchRules)
 local checks=0
 local function check(ok,message)
  assert(ok,"[TOUCH_TEST FAIL] "..message); checks+=1
  print("[TOUCH_TEST PASS] "..message)
 end
 local deadline=os.clock()+10
 while not (player:GetAttribute("RTSTouchInputReady") and player:GetAttribute("RTSTouchCameraReady") and player.PlayerGui:FindFirstChild("AOE2_MainGUI")) do
  assert(os.clock()<deadline,"觸控輸入與相機未初始化"); task.wait(0.1)
 end
 check(true,"觸控輸入與相機初始化，不依賴 CharacterAdded")
 local controlsDeadline=os.clock()+5
 while player:GetAttribute("RTSDefaultControlsReady")~=true do
  assert(os.clock()<controlsDeadline,"[TOUCH_TEST FAIL] 非同步預設角色控制未完成接管；相機／UI 就緒不能代替控制停用")
  task.wait(0.05)
 end
 local controlProbe=player.PlayerScripts:FindFirstChild("RTSControlProbe")
 check(controlProbe and controlProbe:IsA("BindableFunction"),"實際 PlayerInput 提供 Studio 唯讀控制探針")
 local defaultControls=controlProbe:Invoke()
 assert(type(defaultControls)=="table" and defaultControls.ready==true and type(defaultControls.initial)=="boolean" and type(defaultControls.controlsEnabled)=="boolean" and type(defaultControls.hasActive)=="boolean","[TOUCH_TEST FAIL] 實際 PlayerInput 控制探針未就緒或回傳不合法")
 local phase=workspace:GetAttribute("MatchPhase")
 if phase=="Starting" or phase=="Playing" or phase=="Ended" then
  check(defaultControls.controlsEnabled==false,"實際 ControlModule.controlsEnabled=false，全部預設角色移動控制停用")
  check(not defaultControls.hasActive or defaultControls.activeEnabled==false,"實際作用中的預設控制器未啟用")
  -- PlayerModule can finish its TouchGui update after the MatchPhase signal.
  -- Wait only for the documented control flag and actual painted controls to settle.
  local controlsDeadline=os.clock()+3
  while GuiService.TouchControlsEnabled or visibleNativeControl(player) do
   assert(os.clock()<controlsDeadline,"[TOUCH_TEST FAIL] RTS 階段仍啟用預設觸控控制或顯示原生控制")
   task.wait(0.05)
  end
  check(not GuiService.TouchControlsEnabled,"RTS 階段明確關閉 GuiService.TouchControlsEnabled")
  check(visibleNativeControl(player)==nil,"實際 PlayerGui 沒有可見的原生搖桿／跳躍控制")
 elseif phase=="Lobby" then
  check(defaultControls.controlsEnabled==defaultControls.initial and defaultControls.initial==player:GetAttribute("RTSDefaultControlsInitialEnabled"),"大廳恢復接管前的預設控制初值")
 end
 check(Rules.validMode(player:GetAttribute("RTSTouchMode")),"正式客戶端使用有效命令模式")
 local screen=player.PlayerGui.AOE2_MainGUI
 check(not screen.IgnoreGuiInset,"HUD 使用安全區域")
 local dock=screen:FindFirstChild("TouchDock",true)
 check(dock and dock:IsA("GuiObject"),"實際 PlayerGui 存在觸控操作列")
 local probe=screen:WaitForChild("RTSInputProbe",3)
 check(probe and probe:IsA("BindableFunction"),"正式 UI 實例提供 Studio 唯讀命中探針")
 local function inspect(point)
  local result=probe:Invoke(point+GuiService:GetGuiInset())
  assert(type(result)=="table" and type(result.blocked)=="boolean" and type(result.modal)=="boolean","[TOUCH_TEST FAIL] UI 命中探針回傳不合法")
  return result
 end
 if visibleInTree(dock) then
  local pos,size=dock.AbsolutePosition,dock.AbsoluteSize
  check(inspect(pos+size/2).blocked,"實際觸控操作列中心攔截世界指令")
  local ground
  for _,fraction in ipairs({0.5,0.15,0.85}) do
   local point=Vector2.new(pos.X+size.X*fraction,pos.Y-1)
   if not overlapAt(screen,point,nil,Rules) then ground=point; break end
  end
  if ground then check(not inspect(ground).blocked,"實際操作列上鄰可見地面不被 UI 攔截")
  else print("[TOUCH_TEST SKIP] 操作列上緣樣本被其他可見介面覆蓋，未驗收相鄰地面") end
 end
 local hint=screen:FindFirstChild("GuidanceHint",true)
 if hint and visibleInTree(hint) then
  local center=hint.AbsolutePosition+hint.AbsoluteSize/2
  local overlap=overlapAt(screen,center,hint,Rules)
  if overlap then print("[TOUCH_TEST SKIP] 新手提示中心被其他介面覆蓋："..overlap:GetFullName())
  else check(inspect(center).blocked,"實際新手提示按鈕中心攔截世界指令") end
 else print("[TOUCH_TEST SKIP] 此版面未顯示折疊新手提示") end
 for _,name in ipairs({"Select","Move","Gather","Attack","Build","Home","Idle","Villagers","Cancel"}) do
  local button=dock:FindFirstChild("Touch"..name.."Button")
  check(button and button:IsA("GuiButton"),"觸控按鈕已掛載："..name)
  if UIS.TouchEnabled then check(button.AbsoluteSize.X>=44 and button.AbsoluteSize.Y>=44,"觸控按鈕可點擊尺寸："..name) end
 end
 if UIS.TouchEnabled then
  local canvas=screen:FindFirstChild("Canvas")
  local scale=canvas and canvas:FindFirstChildOfClass("UIScale")
  check(scale and scale.Scale==1,"手機 HUD 不縮小觸控目標")
  local pos,size=dock.AbsolutePosition,dock.AbsoluteSize
  local inset=GuiService:GetGuiInset()
  local raw=pos+size/2+inset
  local viewport=raw-inset
  check(Rules.inRect(viewport.X,viewport.Y,pos.X,pos.Y,size.X,size.Y),"原始手指座標扣 GuiInset 後命中操作列")
  check(not Rules.inRect(pos.X+size.X/2,pos.Y-1,pos.X,pos.Y,size.X,size.Y),"緊鄰操作列上緣的地面不被操作列攔截")
  local phase=workspace:GetAttribute("MatchPhase")
  if phase=="Playing" and not player:GetAttribute("Defeated") and not player:GetAttribute("Spectator") then
   check(dock.Visible,"對局中顯示觸控操作列")
  end
 end
 local state=Rules.new()
 Rules.begin(state,"world",100,100,0,false)
 Rules.begin(state,"second",200,100,0.1,false)
 check(Rules.pair(state)~=nil,"雙指可產生相機手勢")
 local first=Rules.finish(state,"world",100,100,0.2,false)
 local second=Rules.finish(state,"second",200,100,0.3,false)
 check(not first.tap and not first.place and not second.tap and not second.place,"雙指放開不選取、不下令、不建造")
 Rules.begin(state,"UI",100,100,1,true)
 local uiRelease=Rules.finish(state,"UI",180,180,1.2,false)
 check(not uiRelease.tap and not uiRelease.place,"UI 上起始的手指移到地面也不能建造")
 Rules.begin(state,"modal",100,100,2,false); Rules.reset(state)
 check(Rules.finish(state,"modal",100,100,2.2,false)==nil,"模態／失焦清理後，舊手指放開不下令")
 check(Rules.zoom(160,100,200)==80 and Rules.zoom(160,100,50)==320,"雙指張開放大、收攏縮小")
 if workspace:GetAttribute("MatchPhase")=="Playing" then
  local camera=workspace.CurrentCamera
  check(player.Character==nil and camera.CameraType==Enum.CameraType.Scriptable,"RTS 觸控不需要角色或預設角色相機")
  local center=camera.ViewportSize/2-GuiService:GetGuiInset()
  local ray=camera:ScreenPointToRay(center.X,center.Y)
  local distance=-ray.Origin.Y/ray.Direction.Y
  local projected=camera:WorldToScreenPoint(ray.Origin+ray.Direction*distance)
  check(math.abs(projected.X-center.X)<1 and math.abs(projected.Y-center.Y)<1,"相機地面射線與扣除 GuiInset 的輸入座標一致")
 end
 print(string.format("[TOUCH_TEST COMPLETE] %d checks; 裝置實際手勢仍需手動驗收",checks))
 return checks
end
-- Observe real UI/H requests and keyboard/touch panning. This test never writes
-- player attributes, moves the camera, calls GUI callbacks, or sends remotes.
function Tests.ObserveRepeatFocus(timeoutSeconds)
 local player=studioClient()
 local CameraFocus=require(game.ReplicatedStorage.Shared.CameraFocus)
 timeoutSeconds=timeoutSeconds or 120
 assert(type(timeoutSeconds)=="number" and timeoutSeconds>=15 and timeoutSeconds<=180,"觀察時間須介於 15 至 180 秒")
 assert(workspace:GetAttribute("MatchPhase")=="Playing","請在正式對局中觀察相機")
 assert(player:GetAttribute("RTSTouchCameraReady"),"正式相機尚未初始化")
 local deadline=os.clock()+timeoutSeconds
 local checks=0
 local function check(ok,message)
  assert(ok,"[TOUCH_FOCUS FAIL] "..message); checks+=1
  print("[TOUCH_FOCUS PASS] "..message)
 end
 local function waitFor(predicate,message,limit)
  local untilTime=limit and math.min(deadline,os.clock()+limit) or deadline
  repeat
   assert(workspace:GetAttribute("MatchPhase")=="Playing","[TOUCH_FOCUS FAIL] 觀察期間對局階段改變")
   if predicate() then return end
   assert(os.clock()<untilTime,"[TOUCH_FOCUS FAIL] "..message)
   task.wait(0.05)
  until false
 end
 local function cameraGround()
  local camera=workspace.CurrentCamera
  if not camera or camera.CameraType~=Enum.CameraType.Scriptable then return nil end
  local position,direction=camera.CFrame.Position,camera.CFrame.LookVector
  if direction.Y>=-0.001 then return nil end
  local distance=-position.Y/direction.Y
  return distance>=0 and position+direction*distance or nil
 end
 local function planarDistance(a,b)
  return Vector2.new(a.X-b.X,a.Z-b.Z).Magnitude
 end
 local baseline=player:GetAttribute("CameraFocusRevision") or 0
 print("[TOUCH_FOCUS OBSERVE] 請點主城或按 H；看到首次置中 PASS 後，以持續 WASD／方向鍵、雙指或開啟邊緣移動後的滑鼠邊緣平移至少 15 studs，再點同一主城或按 H。")
 waitFor(function() return CameraFocus.IsNew(player:GetAttribute("CameraFocusRevision"),baseline) end,"未收到首次真人重聚焦操作")
 local firstRevision=player:GetAttribute("CameraFocusRevision")
 local destination=player:GetAttribute("CameraFocus")
 check(typeof(destination)=="Vector3","收到真人操作的首個聚焦目的地與序號")
 waitFor(function()
  local ground=cameraGround()
  return ground and planarDistance(ground,destination)<=1.5
 end,"首次真人重聚焦未使實際相機置中",3)
 check(true,"首次真人重聚焦使實際相機置中")
 waitFor(function()
  assert(player:GetAttribute("CameraFocusRevision")==firstRevision and player:GetAttribute("CameraFocus")==destination,"[TOUCH_FOCUS FAIL] 平移階段收到另一個聚焦請求，不能替代真人平移")
  local ground=cameraGround()
  return ground and planarDistance(ground,destination)>=15
 end,"未觀察到相同聚焦屬性下的真人相機平移")
 check(true,"相同目的地與序號保持不變，實際相機已平移至少 15 studs")
 print("[TOUCH_FOCUS OBSERVE] 已觀察到平移，請再次點同一主城或按 H。")
 waitFor(function() return CameraFocus.IsNew(player:GetAttribute("CameraFocusRevision"),firstRevision) end,"未收到第二次真人重聚焦操作")
 check(player:GetAttribute("CameraFocus")==destination,"相同目的地的第二次真人請求提交新序號")
 waitFor(function()
  local ground=cameraGround()
  return ground and planarDistance(ground,destination)<=1.5
 end,"相同目的地第二次重聚焦未使實際相機置中",3)
 check(true,"相同目的地第二次重聚焦使實際相機再次置中")
 print(string.format("[TOUCH_FOCUS COMPLETE] %d checks; 只觀察實際操作與相機，不產生測試輸入",checks))
 return checks
end
return Tests
