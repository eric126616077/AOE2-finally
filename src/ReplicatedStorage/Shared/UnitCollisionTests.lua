-- 明確呼叫的 Studio CLIENT 整合測試；僅在新的單人沙盒執行。
-- 透過正常 Order / Stop 遠端移動起始單位，不寫入單位位置或屬性。
-- Root 樣本仍是客戶端收到的伺服器複製資料，不能取代伺服器逐步稽核。
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local Config=require(RS.GameData.GameConfig)
local CameraFocus=require(RS.Shared.CameraFocus)
local FormationRules=require(RS.Shared.FormationRules)
local Tests={running=false}
local TOTAL_TIMEOUT,STAGE_TIMEOUT,REPLICATION_TOLERANCE=90,20,.25

local function horizontal(point) return Vector3.new(point.X,0,point.Z) end
local function ground(point) return Vector3.new(point.X,Config.Map.GroundY,point.Z) end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function previousCameraFocus()
 local camera=workspace.CurrentCamera
 if not camera or camera.CFrame.LookVector.Y>=-.001 then return nil end
 local distance=(Config.Map.GroundY-camera.CFrame.Position.Y)/camera.CFrame.LookVector.Y
 return distance>=0 and camera.CFrame.Position+camera.CFrame.LookVector*distance or nil
end
local function printJSONSegments(value)
 local json=HttpService:JSONEncode(value)
 local chunks,start={},1
 -- Keep the complete line below Studio's output truncation boundary, including
 -- its prefix. Never split inside a multi-byte UTF-8 character.
 while start<=#json do
  local finish=math.min(#json,start+559)
  if finish<#json then finish=utf8.offset(json,0,finish+1)-1 end
  table.insert(chunks,json:sub(start,finish))
  start=finish+1
 end
 for index,chunk in ipairs(chunks) do
  local prefix=string.format("[UNIT_COLLISION JSON %d/%d] ",index,#chunks)
  assert(#prefix+#chunk<=600,"碰撞測試 JSON 分段超出 600 bytes")
  print(prefix..chunk)
 end
 return #chunks
end

function Tests.Run()
 assert(RunService:IsStudio() and RunService:IsClient(),"只能在 Studio Play 客戶端明確呼叫")
 assert(not Tests.running,"單位碰撞整合測試已在執行")
 Tests.running=true
 local started=os.clock()
 local deadline=started+TOTAL_TIMEOUT
 local player=Players.LocalPlayer
 local originalFocus=previousCameraFocus()
 local summary={checks=0,samples=0,stages={},units={},replicationTolerance=REPLICATION_TOLERANCE,
  scope="新的單人沙盒起始 3 村民與 1 斥候；客戶端收到的伺服器 Root 複製樣本",
  minClearance=nil,maxStableColliderOffsetError=0,maxStableColliderAngleError=0,
  stableColliderSamples={0,0,0,0},
  movingStableColliderSamples={0,0,0,0},
  movementOnly=true,work={gathered=false,delivered=false}}
 local tested,workers={},{}
 local scout,base,units,command,generation,arena
 local colliderFrames,previousFrames={},{}
 local sampleConnection,sampleError,stage,stageGoals
 local function check(condition,message)
  assert(condition,"[UNIT_COLLISION FAIL] "..message)
  summary.checks+=1
  print("[UNIT_COLLISION PASS] "..message)
 end
 local function live()
  assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true
   and workspace:GetAttribute("MatchGeneration")==generation,"對局已改變或離開沙盒")
  for _,unit in ipairs(tested) do
   assert(unit.Parent==units and unit.PrimaryPart and (unit:GetAttribute("HP") or 0)>0,"測試單位失效")
  end
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=math.min(deadline,os.clock()+math.min(seconds,STAGE_TIMEOUT))
  if stage then untilTime=math.min(untilTime,started+stage.started+STAGE_TIMEOUT) end
  repeat
   if sampleError then error(sampleError,0) end
   if predicate() then return end
   assert(os.clock()<untilTime,"[UNIT_COLLISION FAIL] "..message.."；等待逾時")
   RunService.Heartbeat:Wait()
  until false
 end
 local function beginStage(name)
  assert(os.clock()<deadline,"[UNIT_COLLISION FAIL] 90 秒總期限已到")
  stage={name=name,started=os.clock()-started,samples=0,rootChanges=0,
   rootChangesByUnit={0,0,0,0},minClearance=nil,maxLateral=0}
  stageGoals=nil
  table.insert(summary.stages,stage)
 end
 local function unitSnapshot(goals)
  local result={}
  for index,unit in ipairs(tested) do
   local root=unit.PrimaryPart
   local point=root and root.Position
   local goal=goals and goals[index]
   local slot=unit:GetAttribute("FormationSlot")
   local hasSlot=typeof(slot)=="Vector3"
   table.insert(result,{index=index,kind=unit:GetAttribute("UnitType"),
    X=point and point.X,Z=point and point.Z,order=unit:GetAttribute("Order"),animation=unit:GetAttribute("Animation"),
    formation=unit:GetAttribute("Formation"),slotX=hasSlot and slot.X or nil,slotZ=hasSlot and slot.Z or nil,
    goalX=goal and goal.X,goalZ=goal and goal.Z,
    goalDistance=point and goal and (horizontal(point)-horizontal(goal)).Magnitude})
  end
  return result
 end
 local function finishStage()
  stage.elapsed=os.clock()-started-stage.started
  stage.complete=true
  stage.finalUnits=unitSnapshot(stageGoals)
  check(stage.samples>0,stage.name.." 有實際 Root 採樣")
  stage=nil
 end
 local function relativeCollider(unit)
  local volume=unit:FindFirstChild("CollisionVolume")
  assert(volume and volume:IsA("BasePart"),"缺少碰撞體積")
  return unit.PrimaryPart.CFrame:ToObjectSpace(volume.CFrame),volume
 end
 local function verifyCollider(unit)
  local kind=unit:GetAttribute("UnitType")
  local data=Config.Units[kind]
  local profile=data and (Config.UnitCollision.profiles[data.class] or Config.UnitCollision.default)
  local root=unit.PrimaryPart
  local relative,volume=relativeCollider(unit)
  check(profile and finite(unit:GetAttribute("Radius")) and unit:GetAttribute("Radius")==profile.radius
   and unit:GetAttribute("CollisionHeight")==profile.height,kind.." 碰撞半徑與高度使用共用設定")
  check(volume.Shape==Enum.PartType.Cylinder and volume.Anchored and volume.CanCollide and volume.CanQuery
   and not volume.CanTouch and volume.Transparency==1,kind.." 有不可見、可碰撞、可查詢的圓柱")
  check(math.abs(volume.Size.X-profile.height)<.001 and math.abs(volume.Size.Y-profile.radius*2)<.001
   and math.abs(volume.Size.Z-profile.radius*2)<.001 and math.abs(volume.CFrame.RightVector.Y)>.999,
   kind.." 圓柱軸線朝上且尺寸正確")
  check((volume.Position-(ground(root.Position)+Vector3.new(0,profile.height/2,0))).Magnitude<.08,
   kind.." 碰撞體積從地面開始並與 Root 水平對齊")
  local modifier=volume:FindFirstChildWhichIsA("PathfindingModifier")
  check(modifier and modifier.PassThrough,kind.." 動態碰撞體積不阻擋靜態尋路網格")
  local initial=colliderFrames[unit]
  if initial then
   local delta=initial:ToObjectSpace(relative)
   local _,angle=delta:ToAxisAngle()
   check(delta.Position.Magnitude<.08 and math.abs(angle)<.02,kind.." 移動後體積與 Root 相對位置、旋轉不變")
  else colliderFrames[unit]=relative end
 end
 local function sample()
  live()
  summary.samples+=1
  if stage then stage.samples+=1 end
  local points={}
  for index,unit in ipairs(tested) do
   local root=unit.PrimaryPart.CFrame
   local relative,volume=relativeCollider(unit)
   points[index]=horizontal(root.Position)
   local before=previousFrames[unit]
   if stage and before and (root.Position-before.root.Position).Magnitude>.002 then
    stage.rootChanges+=1
    stage.rootChangesByUnit[index]+=1
   end
   -- Part replication can arrive separately. Compare authority-relative offsets
   -- only after both parts have remained unchanged across consecutive frames.
   if before and root==before.root and volume.CFrame==before.volume then
    summary.stableColliderSamples[index]+=1
    if unit:GetAttribute("Animation")=="Walk" then summary.movingStableColliderSamples[index]+=1 end
    local delta=colliderFrames[unit]:ToObjectSpace(relative)
    local _,angle=delta:ToAxisAngle()
    local error=delta.Position.Magnitude
    summary.maxStableColliderOffsetError=math.max(summary.maxStableColliderOffsetError,error)
    summary.maxStableColliderAngleError=math.max(summary.maxStableColliderAngleError,math.abs(angle))
    assert(error<.08 and math.abs(angle)<.02,"[UNIT_COLLISION FAIL] 客戶端呈現改動了碰撞體積與 Root 的相對位置")
   end
   previousFrames[unit]={root=root,volume=volume.CFrame}
   if stage and stage.lineZ and (unit==workers[1] or stage.bothWorkers and unit==workers[2]) then
    stage.maxLateral=math.max(stage.maxLateral,math.abs(points[index].Z-stage.lineZ))
   end
  end
  for first=1,#tested-1 do
   for second=first+1,#tested do
    local distance=(points[first]-points[second]).Magnitude
    local required=tested[first]:GetAttribute("Radius")+tested[second]:GetAttribute("Radius")
    local clearance=distance-required
    summary.minClearance=summary.minClearance and math.min(summary.minClearance,clearance) or clearance
    if stage then stage.minClearance=stage.minClearance and math.min(stage.minClearance,clearance) or clearance end
    assert(clearance>=-REPLICATION_TOLERANCE,"[UNIT_COLLISION FAIL] "..tested[first]:GetAttribute("UnitType")
     .."／"..tested[second]:GetAttribute("UnitType").." Root 體積重疊：間距 "..string.format("%.3f / %.3f",distance,required))
   end
  end
 end
 local function idle(unit) return unit:GetAttribute("Order")=="待命" and unit:GetAttribute("Animation")~="Walk" end
 local function reached(unit,destination,tolerance)
  return (horizontal(unit.PrimaryPart.Position)-horizontal(destination)).Magnitude<=(tolerance or 1.6) and idle(unit)
 end
 local function allIdle()
  for _,unit in ipairs(tested) do if not unit.Parent or not idle(unit) then return false end end
  return true
 end
 local function orderSingle(unit,destination) command:FireServer("Order",{unit},destination,Config.Formations.default) end

 local ok,failure=xpcall(function()
  waitFor(function()
   return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true
  end,5,"新的單人沙盒對局就緒")
  generation=workspace:GetAttribute("MatchGeneration")
  units=workspace:FindFirstChild("Units")
  local buildings,resources=workspace:FindFirstChild("Buildings"),workspace:FindFirstChild("Resources")
  local remotes=RS:FindFirstChild("RTSRemotes")
  command=remotes and remotes:FindFirstChild("Command")
  check(units and buildings and resources and command,"正式單位、建築、資源與 Command 遠端存在")
  for _,unit in ipairs(units:GetChildren()) do
   if unit:IsA("Model") and unit:GetAttribute("RTSManaged")==true and unit:GetAttribute("OwnerId")==player.UserId then
    table.insert(tested,unit)
    if unit:GetAttribute("UnitType")=="villager" then table.insert(workers,unit)
    elseif unit:GetAttribute("UnitType")=="scout" then scout=unit end
   end
  end
  check(#tested==4 and #workers==3 and scout,"只使用新局的 3 村民與 1 斥候")
  table.sort(workers,function(left,right) return left.PrimaryPart.Position.X<right.PrimaryPart.Position.X end)
  tested={workers[1],workers[2],workers[3],scout}
  for _,unit in ipairs(tested) do
   check(idle(unit) and (unit:GetAttribute("Carrying") or 0)==0,"起始 "..unit:GetAttribute("UnitType").." 閒置且沒有攜帶資源")
   verifyCollider(unit)
   table.insert(summary.units,{kind=unit:GetAttribute("UnitType"),radius=unit:GetAttribute("Radius"),height=unit:GetAttribute("CollisionHeight")})
  end
  for _,building in ipairs(buildings:GetChildren()) do
   if building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")=="TownCenter"
    and building:GetAttribute("Complete")==true then base=building; break end
  end
  check(base and base.PrimaryPart,"己方完工市鎮中心存在")
  local home=ground(base.PrimaryPart.Position)
  local inward=home.Z>0 and -1 or 1
  local excluded={units}
  local floor=workspace:FindFirstChild("AOE2_Ground")
  if floor then table.insert(excluded,floor) end
  local overlap=OverlapParams.new()
  overlap.FilterType=Enum.RaycastFilterType.Exclude
  overlap.FilterDescendantsInstances=excluded
  overlap.RespectCanCollide=true
  local rays=RaycastParams.new()
  rays.FilterType=Enum.RaycastFilterType.Exclude
  rays.FilterDescendantsInstances=excluded
  rays.RespectCanCollide=true
  local mapHalf=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
  for _,distance in ipairs({72,80,88}) do
   for _,side in ipairs({0,24,-24}) do
    local candidate=home+Vector3.new(side,0,inward*distance)
    if math.abs(candidate.X)+38<mapHalf and math.abs(candidate.Z)+32<mapHalf
     and #workspace:GetPartBoundsInBox(CFrame.new(candidate+Vector3.new(0,4,0)),Vector3.new(76,8,64),overlap)==0 then
     local from,to=candidate+Vector3.new(-24,2.5,0),candidate+Vector3.new(24,2.5,0)
     if workspace:Blockcast(CFrame.new(from),Vector3.new(4,5,4),to-from,rays)==nil then arena=candidate; break end
    end
   end
   if arena then break end
  end
  check(arena,"找到基地清空區附近界內、沒有靜態障礙的共同測試區")
  summary.arena={X=arena.X,Z=arena.Z,width=76,depth=64}
  CameraFocus.Request(player,arena)
  sampleConnection=RunService.Heartbeat:Connect(function()
   if sampleError then return end
   local observed,message=xpcall(sample,debug.traceback)
   if not observed then sampleError=message end
  end)

  beginStage("分散就位")
  local locations={arena+Vector3.new(-24,0,0),arena,arena+Vector3.new(18,0,18),arena+Vector3.new(-20,0,-18)}
  stageGoals=locations
  for index,unit in ipairs(tested) do orderSingle(unit,locations[index]) end
  waitFor(function()
   for index,unit in ipairs(tested) do if not reached(unit,locations[index]) then return false end end
   return true
  end,STAGE_TIMEOUT,"四單位使用正常指令分散就位")
  local eachMoved=true
  for _,changes in ipairs(stage.rootChangesByUnit) do if changes<4 then eachMoved=false end end
  check(eachMoved,"四單位各有至少四次 Root 位移並到達分散位置")
  finishStage()

  beginStage("繞過閒置村民")
  local blockerStart=horizontal(workers[2].PrimaryPart.Position)
  stage.lineZ=arena.Z
  local crossingGoal=arena+Vector3.new(24,0,0)
  stageGoals={[1]=crossingGoal}
  orderSingle(workers[1],crossingGoal)
  waitFor(function() return reached(workers[1],crossingGoal) end,STAGE_TIMEOUT,"村民繞過閒置村民後到達另一側")
  check((horizontal(workers[2].PrimaryPart.Position)-blockerStart).Magnitude<.1,"閒置村民不被推移")
  check(stage.maxLateral>1 and stage.rootChanges>=4,"直線目標產生實際側向繞行且沒有重疊")
  finishStage()

  beginStage("迎面交換位置")
  stage.lineZ=arena.Z
  stage.bothWorkers=true
  local firstGoal=ground(workers[2].PrimaryPart.Position)
  local secondGoal=ground(workers[1].PrimaryPart.Position)
  stageGoals={firstGoal,secondGoal}
  -- 正式單選陣形會替被未選取單位占用的端點讓位。先跨過對方
  -- 起點，兩人都通過中線後再回到已空出的交換端點。
  local middleX=(firstGoal.X+secondGoal.X)/2
  local firstPast=firstGoal+Vector3.new(-6,0,0)
  local secondPast=secondGoal+Vector3.new(6,0,0)
  stage.crossingTargets={{X=firstPast.X,Z=firstPast.Z},{X=secondPast.X,Z=secondPast.Z}}
  orderSingle(workers[1],firstPast)
  orderSingle(workers[2],secondPast)
  waitFor(function()
   return workers[1].PrimaryPart.Position.X<middleX-.5 and workers[2].PrimaryPart.Position.X>middleX+.5
  end,STAGE_TIMEOUT,"兩村民迎面繞行並通過中線")
  orderSingle(workers[1],firstGoal)
  orderSingle(workers[2],secondGoal)
  waitFor(function()
   local authorityArrival=Config.Formations.arrivalTolerance+.01
   return reached(workers[1],firstGoal,authorityArrival) and reached(workers[2],secondGoal,authorityArrival)
  end,
   STAGE_TIMEOUT,"兩村民迎面交換位置")
  check(stage.maxLateral>.8 and stage.rootChanges>=4,"兩村民迎面時繞行並完成交換")
  finishStage()

  beginStage("混合群體移動")
  local groupGoal=arena+Vector3.new(0,0,-12)
  local formationKey=Config.Formations.default
  local records,previousSlots={},{}
  for index,unit in ipairs(tested) do
   local point=unit.PrimaryPart.Position
   records[index]={X=point.X,Z=point.Z,radius=unit:GetAttribute("Radius")}
   previousSlots[index]=unit:GetAttribute("FormationSlot")
  end
  local facing={X=tested[1]:GetAttribute("FormationForwardX") or 0,Z=tested[1]:GetAttribute("FormationForwardZ") or -1}
  local plan=FormationRules.plan(Config.Formations,formationKey,records,{X=groupGoal.X,Z=groupGoal.Z},mapHalf-3,facing)
  check(plan,"混合編隊使用正式 FormationRules.plan 產生每單位目的地")
  local groupLocations={}
  for index=1,#tested do
   local slot=plan.slots[plan.assignment[index]]
   groupLocations[index]=Vector3.new(slot.X,Config.Map.GroundY,slot.Z)
  end
  stage.formation={key=formationKey,spacing=plan.spacing,forwardX=plan.forwardX,forwardZ=plan.forwardZ,
   assignment=plan.assignment}
  stageGoals=groupLocations
  command:FireServer("Order",tested,groupGoal,formationKey)
  waitFor(function()
   for index,unit in ipairs(tested) do
    local slot=unit:GetAttribute("FormationSlot")
    if unit:GetAttribute("Formation")~=formationKey or typeof(slot)~="Vector3"
     or typeof(previousSlots[index])=="Vector3" and (slot-previousSlots[index]).Magnitude<.08 then return false end
   end
   return true
  end,STAGE_TIMEOUT,"伺服器公開新的每單位 FormationSlot")
  for index,unit in ipairs(tested) do
   local slot=unit:GetAttribute("FormationSlot")
   check((slot-groupLocations[index]).Magnitude<.08,"第 "..index.." 個單位的伺服器目的地與正式陣形計算一致")
   groupLocations[index]=slot
  end
  waitFor(function()
   local endpointTolerance=Config.Formations.arrivalTolerance+REPLICATION_TOLERANCE
   for index,unit in ipairs(tested) do if not reached(unit,groupLocations[index],endpointTolerance) then return false end end
   return true
  end,STAGE_TIMEOUT,"斥候與村民混合編隊移動完成")
  check(stage.rootChanges>=4 and stage.minClearance>=-REPLICATION_TOLERANCE,
   "混合單位全程最小間距至少為半徑和，含 0.25 studs 複製容差")
  finishStage()
  for _,unit in ipairs(tested) do verifyCollider(unit) end
  local eachStable=true
  for _,samples in ipairs(summary.stableColliderSamples) do if samples<5 then eachStable=false end end
  check(eachStable,"每個單位至少五次穩定幀的碰撞體積與 Root 相對位置核對")
  local eachMovingStable=true
  for _,samples in ipairs(summary.movingStableColliderSamples) do if samples<2 then eachMovingStable=false end end
  check(eachMovingStable,"每個單位在 Walk 期間也有至少兩次穩定碰撞體積核對")
  check(summary.samples>=10,"移動前後及途中持續取得 Root 與碰撞體積樣本")

  local resource,bestDistance
  for _,candidate in ipairs(resources:GetChildren()) do
   if candidate:IsA("Model") and candidate.PrimaryPart and candidate:GetAttribute("ResourceType")
    and (candidate:GetAttribute("Amount") or 0)>0 and not candidate:GetAttribute("OwnerId") then
    local distance=(horizontal(candidate.PrimaryPart.Position)-horizontal(workers[1].PrimaryPart.Position)).Magnitude
    if not bestDistance or distance<bestDistance then resource,bestDistance=candidate,distance end
   end
  end
  local speed=workers[1]:GetAttribute("Speed") or Config.Units.villager.speed
  local estimatedWork=resource and (bestDistance+(horizontal(resource.PrimaryPart.Position)-horizontal(base.PrimaryPart.Position)).Magnitude)/speed+4
  if resource and estimatedWork<deadline-os.clock()-5 and bestDistance/speed+2<STAGE_TIMEOUT then
   beginStage("正常採集")
   stageGoals={[1]=ground(resource.PrimaryPart.Position)}
   orderSingle(workers[1],resource)
   waitFor(function() return (workers[1]:GetAttribute("Carrying") or 0)>0 end,STAGE_TIMEOUT,"正常採集指令產生攜帶資源")
   summary.work.gathered=true
   summary.work.kind=resource:GetAttribute("ResourceType")
   summary.work.carried=workers[1]:GetAttribute("Carrying")
   summary.movementOnly=false
   check(true,"正常工作指令能在新碰撞體積下採集資源")
   finishStage()
   beginStage("正常交貨")
   stageGoals={[1]=ground(base.PrimaryPart.Position)}
   local delivered=player:GetAttribute("DeliveredResources") or 0
   orderSingle(workers[1],base)
   waitFor(function()
    return (player:GetAttribute("DeliveredResources") or 0)>delivered and (workers[1]:GetAttribute("Carrying") or 0)==0
   end,STAGE_TIMEOUT,"採集後正常交貨完成")
   summary.work.delivered=true
   summary.work.deliveredAmount=(player:GetAttribute("DeliveredResources") or 0)-delivered
   check(true,"正常交貨增加伺服器交回資源數量並清空攜帶量")
   finishStage()
  else summary.work.omittedReason="剩餘時間不足以在 90 秒內完成正常採集與交貨；本次只驗證碰撞移動" end
  if sampleError then error(sampleError,0) end
  check(summary.minClearance>=-REPLICATION_TOLERANCE,"所有已採樣階段的 Root 體積沒有重疊")
 end,debug.traceback)

 if stage then
  stage.elapsed=os.clock()-started-stage.started
  stage.complete=false
  stage.finalUnits=unitSnapshot(stageGoals)
 end
 summary.finalUnits=unitSnapshot(stageGoals)
 stage=nil
 if sampleConnection then sampleConnection:Disconnect() end
 if command and #tested>0 and workspace:GetAttribute("MatchPhase")=="Playing"
  and workspace:GetAttribute("MatchGeneration")==generation then
  command:FireServer("Stop",tested)
  summary.cleanupStopRequested=true
  local cleanupDeadline=math.min(deadline,os.clock()+3)
  while not allIdle() and os.clock()<cleanupDeadline do RunService.Heartbeat:Wait() end
  summary.cleanupStopped=allIdle()
 end
 if originalFocus then CameraFocus.Request(player,originalFocus) end
 Tests.running=false
 summary.elapsedSeconds=os.clock()-started
 summary.complete=ok and summary.cleanupStopped==true and summary.elapsedSeconds<=TOTAL_TIMEOUT
 if not ok then summary.error=tostring(failure)
 elseif not summary.complete then summary.error="Stop 清理未確認完成或超出 90 秒總期限" end
 local label=summary.complete and "COMPLETE" or "INCOMPLETE"
 local segments=printJSONSegments(summary)
 local rootChanges=0
 for _,item in ipairs(summary.stages) do rootChanges+=item.rootChanges end
 print(string.format("[UNIT_COLLISION %s] checks=%d samples=%d rootChanges=%d elapsed=%.3f work=%s/%s segments=%d",
  label,summary.checks,summary.samples,rootChanges,summary.elapsedSeconds,
  tostring(summary.work.gathered),tostring(summary.work.delivered),segments))
 return summary
end
return Tests
