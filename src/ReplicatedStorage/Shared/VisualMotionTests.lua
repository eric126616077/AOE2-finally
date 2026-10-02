-- Studio CLIENT integration check; requiring this module never runs the test.
-- Run on a fresh solo sandbox. Two ordinary Order commands move one idle villager.
-- No real unit part, Root, resource balance, or server state is edited by this test.
-- The live LocalScript probe avoids Command Bar's separate ModuleScript cache.
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local Config=require(RS.GameData.GameConfig)
local Grid=require(RS.Shared.Grid)
local UnitView=require(RS.Shared.ClientUnitView)
local CameraFocus=require(RS.Shared.CameraFocus)
local Tests={running=false}

local function horizontal(value) return Vector3.new(value.X,0,value.Z) end
local function ground(value) return Vector3.new(value.X,Config.Map.GroundY,value.Z) end
local function finiteVector(value)
 return typeof(value)=="Vector3" and Grid.isFinite(value.X) and Grid.isFinite(value.Y) and Grid.isFinite(value.Z)
end
local function safeCameraFocus()
 local camera=workspace.CurrentCamera
 if not camera or camera.CFrame.LookVector.Y>=-.001 then return nil end
 local distance=(Config.Map.GroundY-camera.CFrame.Position.Y)/camera.CFrame.LookVector.Y
 return distance>=0 and camera.CFrame.Position+camera.CFrame.LookVector*distance or nil
end

function Tests.Run()
 assert(RunService:IsStudio() and RunService:IsClient(),"[VISUAL_MOTION FAIL] 只能在 Studio Play 客戶端明確呼叫")
 assert(not Tests.running,"[VISUAL_MOTION FAIL] 位移測試已在執行")
 local player=Players.LocalPlayer
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true,
  "[VISUAL_MOTION FAIL] 請先開啟新的單人沙盒對局")
 assert(not player:GetAttribute("Defeated") and not player:GetAttribute("Spectator"),"[VISUAL_MOTION FAIL] 觀戰者不能移動測試單位")
 Tests.running=true
 local deadline=os.clock()+42
 local previousReduced=player:GetAttribute("ReducedMotion")
 local previousFocus=safeCameraFocus()
 local generation=workspace:GetAttribute("MatchGeneration")
 local renderConnection,leg,sampleError,worker,probe
 local fixtures={}
 local summary={checks=0,renderSamples=0,rootChanges=0,visualIntermediateFrames=0,
  maxRootDeviation=0,maxBodyAnchorError=0,maxBodyRotationError=0,maxRenderDelta=0,legs={},scope="單一村民短路徑；未驗證大規模效能"}
 local function check(condition,message)
  assert(condition,"[VISUAL_MOTION FAIL] "..message)
  summary.checks+=1
  print("[VISUAL_MOTION PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=math.min(deadline,os.clock()+seconds)
  repeat
   if sampleError then error(sampleError,0) end
   if predicate() then return end
   assert(os.clock()<untilTime,"[VISUAL_MOTION FAIL] "..message.."；等待逾時")
   task.wait(.03)
  until false
 end
 local function current()
  assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("MatchGeneration")==generation,
   "[VISUAL_MOTION FAIL] 對局已改變")
  assert(worker and worker.Parent==workspace.Units and worker.PrimaryPart and (worker:GetAttribute("HP") or 0)>0,
   "[VISUAL_MOTION FAIL] 村民已失效")
  local state=probe:Invoke(worker)
  assert(type(state)=="table" and state.ready and state.tracked and state.visible and state.body and state.body.Parent
   and typeof(state.frame)=="CFrame" and typeof(state.bodyOffset)=="CFrame", "[VISUAL_MOTION FAIL] 真實呈現探針未追蹤可見的村民 Body")
  return state
 end
 local function observe(dt)
  if not leg then return end
  local state=current()
  local rootFrame=state.root.CFrame
  local root=rootFrame.Position
  local frame=state.frame.Position
  local body=state.body.Position
  local expectedFrame=state.frame*state.bodyOffset
  local expected=expectedFrame.Position
  local rootDelta=leg.lastRoot and (root-leg.lastRoot).Magnitude or 0
  local rootTurn=leg.lastRootFrame and (rootFrame.LookVector-leg.lastRootFrame.LookVector).Magnitude or 0
  local viewDelta=leg.lastFrame and (frame-leg.lastFrame).Magnitude or 0
  local bodyDelta=leg.lastBody and (body-leg.lastBody).Magnitude or 0
  local deviation=(frame-root).Magnitude
  local anchorError=(body-expected).Magnitude
  local _,angleError=state.body.CFrame:ToObjectSpace(expectedFrame):ToAxisAngle()
  leg.samples+=1; summary.renderSamples+=1
  summary.maxRenderDelta=math.max(summary.maxRenderDelta,dt)
  summary.maxRootDeviation=math.max(summary.maxRootDeviation,deviation)
  -- Replication can move the Root between rendering and this deferred observation.
  -- Require coherence on stable Root frames, where no authority update races the read.
  if leg.lastRoot and rootDelta<=.002 and rootTurn<=.002 then
   leg.stableSamples+=1
   leg.maxBodyAnchorError=math.max(leg.maxBodyAnchorError,anchorError)
   summary.maxBodyAnchorError=math.max(summary.maxBodyAnchorError,anchorError)
   leg.maxBodyRotationError=math.max(leg.maxBodyRotationError,math.abs(angleError))
   summary.maxBodyRotationError=math.max(summary.maxBodyRotationError,math.abs(angleError))
   if viewDelta>.002 and bodyDelta>.002 then leg.intermediate+=1; summary.visualIntermediateFrames+=1 end
  elseif leg.lastRoot then
   leg.rootChanges+=1; summary.rootChanges+=1; leg.lastRootChange=os.clock()
  end
  leg.maxRootDeviation=math.max(leg.maxRootDeviation,deviation)
  leg.maxSamples=math.max(leg.maxSamples,state.sampleCount or 0)
  leg.lastRoot,leg.lastFrame,leg.lastBody=root,frame,body
  leg.lastRootFrame=rootFrame
  leg.stats=state.stats
 end

 local ok,result=xpcall(function()
  waitFor(function()
   local scripts=player:FindFirstChild("PlayerScripts")
   local motion=scripts and scripts:FindFirstChild("UnitMotion")
   probe=scripts and scripts:FindFirstChild("RTSMotionProbe")
   return motion and motion:IsA("LocalScript") and motion:GetAttribute("RTSMotionReady")==true
    and probe and probe:IsA("BindableFunction")
  end,5,"實際 PlayerScripts UnitMotion 與讀取探針就緒")
  check(true,"實際 PlayerScripts UnitMotion 與讀取探針已就緒")
  local units,buildings,resources=workspace:FindFirstChild("Units"),workspace:FindFirstChild("Buildings"),workspace:FindFirstChild("Resources")
  local remotes=RS:FindFirstChild("RTSRemotes")
  local command=remotes and remotes:FindFirstChild("Command")
  check(units and buildings and resources and command,"正式單位、建築、資源與 Command 遠端存在")

  -- Only isolated, unparented fixtures are positioned to exercise fallback.
  local empty=Instance.new("Model"); table.insert(fixtures,empty)
  check(UnitView.GetFrame(empty)==empty:GetPivot(),"未追蹤且沒有 PrimaryPart 的模型使用 GetPivot fallback")
  local fixture=Instance.new("Model"); table.insert(fixtures,fixture)
  local fixtureRoot=Instance.new("Part"); fixtureRoot.Name="FixtureRoot"; fixtureRoot.Anchored=true
  fixtureRoot.CFrame=CFrame.new(3,7,-11)*CFrame.Angles(0,.4,0); fixtureRoot.Parent=fixture; fixture.PrimaryPart=fixtureRoot
  check(UnitView.GetFrame(fixture)==fixtureRoot.CFrame,"未追蹤模型使用 PrimaryPart 的位置與轉向 fallback")

  local excluded={units}
  for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local object=workspace:FindFirstChild(name); if object then table.insert(excluded,object) end end
  local rays=RaycastParams.new(); rays.FilterType=Enum.RaycastFilterType.Exclude; rays.FilterDescendantsInstances=excluded; rays.RespectCanCollide=true
  local overlaps=OverlapParams.new(); overlaps.FilterType=Enum.RaycastFilterType.Exclude; overlaps.FilterDescendantsInstances=excluded; overlaps.RespectCanCollide=true
  local half=(workspace:GetAttribute("MapSize") or workspace:GetAttribute("MatchSize") or Config.Map.MapSize)/2
  local function clearPath(from,to,radius)
   if not finiteVector(from) or not finiteVector(to) or math.abs(to.X)>half-3 or math.abs(to.Z)>half-3 then return false end
   local size=Vector3.new(radius*1.8,4,radius*1.8)
   local start=from+Vector3.new(0,2.5,0)
   local finish=to+Vector3.new(0,2.5,0)
   return #workspace:GetPartBoundsInBox(CFrame.new(start),size,overlaps)==0
    and #workspace:GetPartBoundsInBox(CFrame.new(finish),size,overlaps)==0
    and workspace:Blockcast(CFrame.new(start),size,to-from,rays)==nil
  end
  local route
  for _,candidate in ipairs(units:GetChildren()) do
   assert(os.clock()<deadline,"[VISUAL_MOTION FAIL] 尋找合法路段逾時")
   if candidate:IsA("Model") and candidate.PrimaryPart and candidate:GetAttribute("RTSManaged")==true
    and candidate:GetAttribute("OwnerId")==player.UserId and candidate:GetAttribute("UnitType")=="villager"
    and (candidate:GetAttribute("HP") or 0)>0 and (candidate:GetAttribute("Carrying") or 0)==0
    and (candidate:GetAttribute("Order")=="待命" or candidate:GetAttribute("Order")==nil) then
    local start=ground(candidate.PrimaryPart.Position)
    local radius=candidate:GetAttribute("Radius") or 2
    for _,sx in ipairs({1,-1}) do
     for _,sz in ipairs({1,-1}) do
      local first=start+Vector3.new(40*sx,0,0)
      local second=first+Vector3.new(0,0,40*sz)
      if clearPath(start,first,radius) and clearPath(first,second,radius) then worker=candidate; route={first,second}; break end
     end
     if route then break end
    end
   end
   if route then break end
  end
  check(worker and route,"找到己方閒置村民與 X、Z 各 40 studs 的無碰撞界內路段")
  local original=ground(worker.PrimaryPart.Position)
  CameraFocus.Request(player,(original+route[2])*.5)
  player:SetAttribute("ReducedMotion",true)
  waitFor(function()
   local state=probe:Invoke(worker)
   return state and state.ready and state.tracked and state.visible and state.body and state.bodyOffset
    and (state.body.Position-(state.frame*state.bodyOffset).Position).Magnitude<.05
  end,4,"相機與無肢體擺動的村民呈現就緒")
  check(true,"從真實遊戲快取讀取可見 Body、GetFrame 與原始 rest offset")
  local before=probe:Invoke(worker).stats
  summary.initialStats=before
  renderConnection=RunService.RenderStepped:Connect(function(dt)
   task.defer(function()
    if not leg or sampleError then return end
    local observed,failure=xpcall(function() observe(dt) end,debug.traceback)
    if not observed then sampleError=failure end
   end)
  end)
  for index,destination in ipairs(route) do
   local state=current()
   local start=horizontal(state.root.Position)
   leg={axis=index==1 and "X" or "Z",samples=0,rootChanges=0,intermediate=0,stableSamples=0,
    maxBodyAnchorError=0,maxBodyRotationError=0,maxRootDeviation=0,maxSamples=0,lastRootChange=os.clock(),
    lastRoot=state.root.Position,lastRootFrame=state.root.CFrame,lastFrame=state.frame.Position,lastBody=state.body.Position}
   command:FireServer("Order",{worker},destination)
   waitFor(function()
    local live=current()
    local atGoal=(horizontal(live.root.Position)-horizontal(destination)).Magnitude<=1.6
    local idle=worker:GetAttribute("Order")=="待命" and worker:GetAttribute("Animation")~="Walk"
    return leg.rootChanges>=5 and atGoal and idle and os.clock()-leg.lastRootChange>.5
     and (live.frame.Position-live.root.Position).Magnitude<.05
   end,12,leg.axis.." 軸正常指令移動完成且呈現收尾")
   local finished=current()
   check((horizontal(finished.root.Position)-start).Magnitude>=38,leg.axis.." 軸由伺服器實際移動約 40 studs")
   check(leg.rootChanges>=5 and leg.intermediate>=3,leg.axis.." 軸 Root 樣本之間有多個實際 Body 位移 render frames")
   check(leg.stableSamples>=3 and leg.maxBodyAnchorError<.08 and leg.maxBodyRotationError<.01,
    leg.axis.." 軸真實 GetFrame 與 Body rest offset 的位置、轉向一致")
   local speed=worker:GetAttribute("Speed") or Config.Units.villager.speed
   check(leg.maxRootDeviation<=math.max(4,speed*.35),leg.axis.." 軸呈現與權威 Root 偏差維持在短延遲範圍")
   check(leg.maxSamples<=finished.stats.maxSamples and (finished.frame.Position-finished.root.Position).Magnitude<.05
    and (finished.frame.LookVector-finished.root.CFrame.LookVector).Magnitude<.01
    and (finished.body.Position-(finished.root.CFrame*finished.bodyOffset).Position).Magnitude<.08,
    leg.axis.." 軸停止後對齊 Root，且呈現樣本數受限")
   table.insert(summary.legs,{axis=leg.axis,samples=leg.samples,rootChanges=leg.rootChanges,intermediateFrames=leg.intermediate,
    maxRootDeviation=leg.maxRootDeviation,maxBodyAnchorError=leg.maxBodyAnchorError,maxSamples=leg.maxSamples})
   leg=nil
  end
  summary.finalStats=probe:Invoke(worker).stats
  check(summary.finalStats.rootSamples>before.rootSamples and summary.finalStats.totalPartWrites>before.totalPartWrites,
   "真實 LocalScript 的 Root 樣本與外觀寫入診斷都有增加")
  summary.elapsedSeconds=42-(deadline-os.clock())
  check(summary.elapsedSeconds<=42,"整合檢查在 45 秒總期限內完成")
  return summary
 end,debug.traceback)
 leg=nil
 if renderConnection then renderConnection:Disconnect() end
 for _,fixture in ipairs(fixtures) do fixture:Destroy() end
 player:SetAttribute("ReducedMotion",previousReduced)
 if previousFocus then CameraFocus.Request(player,previousFocus) end
 Tests.running=false
 print("[VISUAL_MOTION OBSERVED] "..HttpService:JSONEncode(summary))
 if not ok then error(result,0) end
 print("[VISUAL_MOTION COMPLETE] "..summary.checks.." 項檢查；僅驗證短路徑呈現，大規模效能尚未驗證")
 return result
end
return Tests
