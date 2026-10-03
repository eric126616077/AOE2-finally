-- Test-only LocalScript, mapped only by battle-validation.project.json.
-- 以正常大廳指令開一局（1 真人＋1 簡單電腦），把鏡頭移到伺服器壓力測試的戰場，
-- 記錄每個階段的 RenderStepped 幀時間、接收流量與 UnitMotion 探針數字。只觀察，不下戰鬥指令。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local Stats=game:GetService("Stats")
local UIS=game:GetService("UserInputService")
local player=game.Players.LocalPlayer
local function emit(kind,data)
 print("[BATTLE_STRESS_CLIENT] "..Http:JSONEncode({kind=kind,data=data}))
end
local function round(value,digits)
 if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false end
 local scale=10^(digits or 2)
 return math.floor(value*scale+0.5)/scale
end
local function untilTrue(predicate,seconds,message)
 local deadline=os.clock()+seconds
 repeat if predicate() then return end; Run.Heartbeat:Wait() until os.clock()>deadline
 error("[BATTLE_STRESS_CLIENT FAIL] "..message)
end
untilTrue(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30,"初始化逾時")
require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"})
untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,40,"開始測試局逾時")
local Observer=require(RS.Shared.PerformanceObserver)
local Focus=require(RS.Shared.CameraFocus)
local focused="Unknown"
UIS.WindowFocused:Connect(function() focused="Focused" end)
UIS.WindowFocusReleased:Connect(function() focused="Background" end)
local record,stage,started
local receive,focusSeen={}, {}
local motionWrites={}
local appearance={checked=0,detached=0,worst=0}
local lastSecond=0
local function motion()
 local probe=script.Parent:FindFirstChild("RTSMotionProbe")
 local ok,result=pcall(function() return probe and probe:Invoke() end)
 return ok and result and result.stats or nil
end
Run.RenderStepped:Connect(function(delta)
 if not record then return end
 Observer.AddFrame(record,delta)
 local now=os.clock()
 if now-lastSecond>=1 then
  lastSecond=now
  local ok,kbps=pcall(function() return Stats.DataReceiveKbps end)
  if ok and type(kbps)=="number" then table.insert(receive,kbps) end
  focusSeen[focused]=(focusSeen[focused] or 0)+1
  local stats=motion()
  if stats then table.insert(motionWrites,stats.partWrites) end
  -- 伺服器只搬 Root：檢查畫面上每個單位的身體零件是否跟著 Root（超過 6 studs 視為外觀脫離）。
  local camera=workspace.CurrentCamera
  local folder=workspace:FindFirstChild("Units")
  if camera and folder then
   for _,unit in ipairs(folder:GetChildren()) do
    local root=unit.PrimaryPart
    local body=unit:FindFirstChild("Body") or unit:FindFirstChild("HorseBody") or unit:FindFirstChild("Chassis")
    if root and body and body:IsA("BasePart") then
     local _,visible=camera:WorldToViewportPoint(root.Position)
     if visible then
      appearance.checked+=1
      local offset=body.Position-root.Position
      local flat=Vector3.new(offset.X,0,offset.Z).Magnitude
      appearance.worst=math.max(appearance.worst,flat)
      if flat>6 then appearance.detached+=1 end
     end
    end
   end
  end
 end
end)
local function finish()
 if not record then return end
 local summary=Observer.FrameSummary(record)
 local network=Observer.NumericSummary(receive,0)
 local writes=Observer.NumericSummary(motionWrites,0)
 local stats=motion()
 local camera=workspace.CurrentCamera
 local qualityOK,quality=pcall(function() return tostring(UserSettings():GetService("UserGameSettings").SavedQualityLevel) end)
 emit("FRAMES",{stage=stage,seconds=round(os.clock()-started,1),frames=summary.validFrames,fps=round(summary.effectiveFPS,1),
  meanMs=round(summary.meanDeltaMs,2),p95Ms=summary.p95UpperBoundMs,worstMs=round(summary.worstDeltaMs,1),
  below30=round(summary.below30Fraction,4),below15=round(summary.below15Fraction,4),
  receiveKbps={mean=round(network.mean,1),worst=round(network.worst,1)},
  partWritesPerFrame={mean=round(writes.mean,0),worst=round(writes.worst,0)},
  motion=stats and {tracked=stats.tracked,visible=stats.visible,detailed=stats.detailed} or false,
  focusSeconds=focusSeen,viewport=camera and {camera.ViewportSize.X,camera.ViewportSize.Y} or false,
  qualityLevel=qualityOK and quality or false,
  appearance={checked=appearance.checked,detached=appearance.detached,worstOffset=round(appearance.worst,2)}})
 record=nil
end
local function changed()
 local value=workspace:GetAttribute("BattleStressStage")
 if type(value)~="string" then return end
 finish()
 local center=workspace:GetAttribute("BattleStressCenter")
 if typeof(center)=="Vector3" then Focus.Request(player,center) end
 if string.sub(value,1,4)=="run:" then
  stage,started,record=string.sub(value,5),os.clock(),Observer.NewFrames()
  receive,focusSeen,motionWrites={}, {}, {}
  appearance={checked=0,detached=0,worst=0}
 elseif value=="done" then emit("DONE",{}) end
end
workspace:GetAttributeChangedSignal("BattleStressStage"):Connect(changed)
changed()
-- 無戰鬥基準：開局後、第一批部隊生成前的幀時間。
if not record and workspace:GetAttribute("BattleStressStage")==nil then
 stage,started,record="baseline",os.clock(),Observer.NewFrames()
end
emit("READY",{touch=UIS.TouchEnabled})
