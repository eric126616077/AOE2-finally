-- Studio 雙人客戶端明確呼叫；require 不會觀察、開局或操作。
-- 非房主在真戰鬥前 Arm()，房主軍隊正常撤離後 Run()。
-- 只以正常 Stop／Order 修復真正戰損；不修改 HP、資源、位置或伺服器時間戳記。
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Config = require(RS.GameData.GameConfig)
local Rules = require(RS.Shared.FeedbackRules)
local Focus = require(RS.Shared.CameraFocus)
local Tests = {running=false, armed=nil}

local function client()
 assert(RunService:IsStudio() and RunService:IsClient(), "[FEEDBACK_REPAIR FAIL] 僅限 Studio Play 客戶端")
 assert(#Players:GetPlayers() == 2 and workspace:GetAttribute("MatchPhase") == "Playing",
  "[FEEDBACK_REPAIR FAIL] 需要真正兩名玩家的 Playing 對局")
 return Players.LocalPlayer
end
local function finite(value)
 return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function position(model)
 local p = model:GetPivot().Position
 return {x=p.X,y=p.Y,z=p.Z}
end
local function attrs(model)
 if not model then return {exists=false} end
 return {exists=model.Parent ~= nil, name=model.Name, position=position(model),
  ownerId=model:GetAttribute("OwnerId"), kind=model:GetAttribute("UnitType") or model:GetAttribute("BuildingType"),
  hp=model:GetAttribute("HP"), maxHP=model:GetAttribute("MaxHP"), complete=model:GetAttribute("Complete"),
  constructionProgress=model:GetAttribute("ConstructionProgress"), order=model:GetAttribute("Order"),
  animation=model:GetAttribute("Animation"), workKind=model:GetAttribute("WorkKind"),
  lastWork=tostring(model:GetAttribute("LastWork")), lastAttack=tostring(model:GetAttribute("LastAttack"))}
end
local function closeArm(session)
 if not session or session.closed then return end
 session.closed = true
 for _,connection in ipairs(session.connections) do connection:Disconnect() end
 table.clear(session.connections)
end
function Tests.Close()
 closeArm(Tests.armed)
 Tests.armed = nil
end
local function matchesTarget(point, building)
 if typeof(point) ~= "Vector3" or not building.PrimaryPart then return false end
 local p,half = building:GetPivot().Position,building.PrimaryPart.Size/2
 return math.abs(point.X-p.X) <= half.X+.25 and math.abs(point.Z-p.Z) <= half.Z+.25
end

-- 記錄 Complete 建築真正的 HP 下降，並要求同批附近真正敵軍 LastAttack 脈衝與 AttackPosition。
function Tests.Arm()
 local player = client()
 assert(not Tests.running, "[FEEDBACK_REPAIR FAIL] 修復驗證正在執行")
 Tests.Close()
 local peer
 for _,actor in ipairs(Players:GetPlayers()) do if actor ~= player then peer=actor end end
 assert(peer and finite(player:GetAttribute("TeamId")) and finite(peer:GetAttribute("TeamId")) and
  peer:GetAttribute("TeamId") ~= player:GetAttribute("TeamId"), "[FEEDBACK_REPAIR FAIL] 真戰損觀察需要另一名敵對真人")
 local session = {owner=player.UserId, peer=peer.UserId, generation=workspace:GetAttribute("MatchGeneration"), closed=false,
  connections={}, attacks={}, evidence={}, buildings={}, units={}}
 Tests.armed = session
 local function bind(signal, callback)
  table.insert(session.connections, signal:Connect(callback))
 end
 local function watchUnit(model)
  if not model:IsA("Model") or session.units[model] or model:GetAttribute("OwnerId") ~= peer.UserId or
   model:GetAttribute("RTSManaged") ~= true or not Config.Units[model:GetAttribute("UnitType")] then return end
  session.units[model] = true
  local baseline = model:GetAttribute("LastAttack")
  bind(model:GetAttributeChangedSignal("LastAttack"), function()
   local value,previous = model:GetAttribute("LastAttack"),baseline
   baseline = value
   if not Rules.IsNewPulse(value,previous) then return end
   task.defer(function()
    if session.closed or model.Parent ~= workspace.Units or model:GetAttribute("LastAttack") ~= value then return end
    session.attacks[model] = {clock=value, at=os.clock(), target=model:GetAttribute("AttackPosition")}
   end)
  end)
 end
 local function watchBuilding(model)
  if not model:IsA("Model") or session.buildings[model] or model:GetAttribute("OwnerId") ~= player.UserId or
   model:GetAttribute("RTSManaged") ~= true then return end
  session.buildings[model] = true
  local hp = model:GetAttribute("HP")
  bind(model:GetAttributeChangedSignal("HP"), function()
   local value,before = model:GetAttribute("HP"),hp
   hp = value
   if session.closed or model:GetAttribute("Complete") ~= true or not finite(before) or not finite(value) or value >= before then return end
   local droppedAt = os.clock()
   task.spawn(function()
    -- HP and attacker attributes can arrive in either order in the replication batch.
    local limit = os.clock()+.75
    repeat
     if session.closed or model.Parent ~= workspace.Buildings then return end
     for source,attack in pairs(session.attacks) do
      if source.Parent == workspace.Units and math.abs(attack.at-droppedAt) <= .75 and
       matchesTarget(attack.target,model) then
       local evidence = session.evidence[model]
       if not evidence then evidence={hits=0, damage=0, firstHP=before, attackers={}}; session.evidence[model]=evidence end
       evidence.hits += 1
       evidence.damage += before-value
       evidence.lastHP, evidence.lastAt = value,os.clock()
       evidence.attackers[source] = attack.clock
       print(string.format("[FEEDBACK_REPAIR DAMAGE] owner=%d target=%s attacker=%s pulse=%.6f HP=%.3f->%.3f",
        player.UserId,model.Name,source:GetAttribute("UnitType"),attack.clock,before,value))
       return
      end
     end
     RunService.RenderStepped:Wait()
    until os.clock() >= limit
   end)
  end)
 end
 for _,model in ipairs(workspace.Units:GetChildren()) do watchUnit(model) end
 for _,model in ipairs(workspace.Buildings:GetChildren()) do watchBuilding(model) end
 bind(workspace.Units.ChildAdded, function(model) task.defer(function() if not session.closed then watchUnit(model) end end) end)
 bind(workspace.Buildings.ChildAdded, function(model) task.defer(function() if not session.closed then watchBuilding(model) end end) end)
 bind(Players.PlayerRemoving, function() closeArm(session) end)
 bind(workspace:GetAttributeChangedSignal("MatchPhase"), function()
  if workspace:GetAttribute("MatchPhase") ~= "Playing" then closeArm(session) end
 end)
 bind(workspace:GetAttributeChangedSignal("MatchGeneration"), function() closeArm(session) end)
 for _,actor in ipairs(Players:GetPlayers()) do
  bind(actor:GetAttributeChangedSignal("FV_Failed"), function()
   if actor:GetAttribute("FV_Failed") == true then closeArm(session) end
  end)
 end
 print("[FEEDBACK_REPAIR ARMED] 已開始唯讀觀察真正兩人戰損；未修改任何遊戲屬性")
 return true
end

local function run()
 local player = client()
 local session = Tests.armed
 assert(session and not session.closed and session.owner == player.UserId and
  session.generation == workspace:GetAttribute("MatchGeneration"),
  "[FEEDBACK_REPAIR FAIL] 先在此真正戰鬥前明確 Arm()；不能把既有缺血當成傷害證據")
 local command = RS.RTSRemotes.Command
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local savedSound,savedMotion = player:GetAttribute("SoundEnabled"),player:GetAttribute("ReducedMotion")
 local started,deadline,checks = os.clock(),os.clock()+170,0
 local workers,connections,worker,target,probe = {},{},nil,nil,nil
 local soundCount,loadedCount = 0,0
 local function diagnostic(reason)
  local observed = {}
  for model,evidence in pairs(session.evidence) do
   table.insert(observed,{building=attrs(model),hits=evidence.hits,damage=evidence.damage})
  end
  local live = probe and probe:Invoke() or nil
  print("[FEEDBACK_REPAIR DIAGNOSTICS] " .. HttpService:JSONEncode({reason=reason,elapsed=os.clock()-started,
   phase=workspace:GetAttribute("MatchPhase"),players=#Players:GetPlayers(),wood=player:GetAttribute("wood"),
   worker=attrs(worker),target=attrs(target),observedBattleDamage=observed,sounds=soundCount,loadedSounds=loadedCount,audio=live}))
 end
 local function check(condition,message)
  assert(condition,"[FEEDBACK_REPAIR FAIL] " .. message)
  checks += 1
  print("[FEEDBACK_REPAIR PASS] " .. message)
 end
 local function waitFor(predicate,seconds,message)
  local limit = math.min(deadline,os.clock()+seconds)
  repeat
   assert(#Players:GetPlayers() == 2 and workspace:GetAttribute("MatchPhase") == "Playing",
    "[FEEDBACK_REPAIR FAIL] 真正雙人測試局中途結束：" .. message)
   if predicate() then check(true,message); return end
   assert(os.clock() < limit,"[FEEDBACK_REPAIR FAIL] " .. message .. "；等待逾時")
   task.wait(.025)
  until false
 end
 local function settleFrames(message)
  local frames = 0
  local connection = RunService.RenderStepped:Connect(function() frames+=1 end)
  table.insert(connections,connection)
  waitFor(function() return frames >= 3 end,3,message)
  connection:Disconnect()
 end
 local function poseChanged(rest,tolerance)
  for part,offset in pairs(rest) do
   if not part.Parent or not worker.PrimaryPart then return true end
   local delta = offset:ToObjectSpace(worker.PrimaryPart.CFrame:ToObjectSpace(part.CFrame))
   local _,angle = delta:ToAxisAngle()
   if math.abs(angle) > tolerance or delta.Position.Magnitude > tolerance then return true end
  end
  return false
 end
 local function sample()
  return {last=worker:GetAttribute("LastWork"), hp=target:GetAttribute("HP"), wood=player:GetAttribute("wood")}
 end
 local function repairPulse(before,seconds,message)
  waitFor(function()
   return worker:GetAttribute("Animation") == "Work" and worker:GetAttribute("WorkKind") == "repair" and
    Rules.IsNewPulse(worker:GetAttribute("LastWork"),before.last) and target:GetAttribute("HP") > before.hp and
    player:GetAttribute("wood") < before.wood
  end,seconds,message)
  local after = sample()
  check(after.hp == math.min(target:GetAttribute("MaxHP"),before.hp+15) and after.wood == before.wood-1,
   message .. "：每個真正脈衝增加 15 HP 並扣除 1 木材")
  print(string.format("[FEEDBACK_REPAIR PULSE] value=%.6f HP=%.3f->%.3f wood=%.3f->%.3f audioEnabled=%s",
   after.last,before.hp,after.hp,before.wood,after.wood,tostring(probe:Invoke().enabled)))
  return after
 end
 local ok,result = xpcall(function()
  check(player.Character == nil and workspace.StreamingEnabled == false,"真正雙人 RTS 無角色且使用完整複製")
  probe = player.PlayerScripts:FindFirstChild("RTSAudioProbe")
  check(probe and probe:IsA("BindableFunction") and player:GetAttribute("RTSSoundReady") == true and
   player.PlayerScripts.UnitMotion:GetAttribute("RTSMotionReady") == true,"正式音效探針與動作 LocalScript 已就緒")
  waitFor(function()
   local stats = probe:Invoke()
   return stats.preloadFinished and not stats.preloadError and stats.assetCount > 0 and stats.failedAssets == 0 and stats.loadedAssets == stats.assetCount
  end,10,"正式修復音效資產已預載")
  local bestScore = math.huge
  for _,model in ipairs(workspace.Units:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("OwnerId") == player.UserId and
    model:GetAttribute("UnitType") == "villager" and model:GetAttribute("RTSManaged") == true and (model:GetAttribute("HP") or 0) > 0 then
    table.insert(workers,model)
   end
  end
  check(#workers > 0,"本方有可正常指揮修復的真正村民")
  for building,evidence in pairs(session.evidence) do
   if building.Parent == workspace.Buildings and building.PrimaryPart and building:GetAttribute("OwnerId") == player.UserId and
    building:GetAttribute("Complete") == true and (building:GetAttribute("HP") or 0) > 0 and
    (building:GetAttribute("MaxHP") or 0)-(building:GetAttribute("HP") or 0) >= 75 and evidence.hits >= 2 and evidence.damage >= 75 then
    for _,candidate in ipairs(workers) do
     local score = (candidate:GetPivot().Position-building:GetPivot().Position).Magnitude+
      (building:GetAttribute("BuildingType") == "Wall" and 0 or 10000)
     if score < bestScore then target,worker,bestScore=building,candidate,score end
    end
   end
  end
  check(target and worker,"優先選取由明確 Arm 記錄至少兩次真戰損、缺口足夠的己方完工石牆及最近村民")
  local evidence = session.evidence[target]
  check(evidence.hits >= 2 and evidence.damage >= 75,"修復目標具有敵軍真 LastAttack／AttackPosition 對應的 HP 下降，排除初始化缺血")
  for source in pairs(evidence.attackers) do
   if source.Parent == workspace.Units and source.PrimaryPart then
    local data = Config.Units[source:GetAttribute("UnitType")]
    local p,center,half = source:GetPivot().Position,target:GetPivot().Position,target.PrimaryPart.Size/2
    local distance = Vector2.new(math.max(0,math.abs(p.X-center.X)-half.X),math.max(0,math.abs(p.Z-center.Z)-half.Z)).Magnitude
    check(data and distance > (data.range or 0)+8 and source:GetAttribute("Animation") ~= "Attack",
     "造成此目標戰損的敵軍已正常撤離射程：" .. tostring(source:GetAttribute("UnitType")))
   end
  end
  check((player:GetAttribute("wood") or 0) >= 6,"真實庫存足以支付修復，測試不補木材")
  command:FireServer("Stop",workers)
  waitFor(function()
   for _,unit in ipairs(workers) do
    if unit:GetAttribute("Order") ~= "待命" or unit:GetAttribute("Animation") ~= "Idle" then return false end
   end
   return true
  end,5,"正常停止全部己方村民，避免採集交貨干擾修復帳目")
  player:SetAttribute("ReducedMotion",true)
  player:SetAttribute("SoundEnabled",true)
  settleFrames("減少動態基準等待三個真正 RenderStepped 畫格")
  local rest = {}
  for _,part in ipairs(worker:GetDescendants()) do
   if part:IsA("BasePart") and not part.CanCollide and (part.Name == "ArmR" or part.Name == "Tool" or part.Name == "ToolHead") then
    rest[part] = worker.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
   end
  end
  check(next(rest) ~= nil,"替代村民具備可驗證的修復工具或手臂基準")
  local quietHP,quietUntil = target:GetAttribute("HP"),os.clock()+1.1
  waitFor(function()
   assert(target:GetAttribute("HP") == quietHP,"[FEEDBACK_REPAIR FAIL] 敵軍未停止傷害或有其他工人正在修復目標")
   return os.clock() >= quietUntil and probe:Invoke().active == 0
  end,3,"戰後跨一秒保持真正受損 HP，且先前音效已清理")
  local connection = worker.DescendantAdded:Connect(function(object)
   if not object:IsA("Sound") or object.Name ~= "RTS_Repair" then return end
   soundCount += 1
   task.defer(function()
    if object.Parent and object.IsLoaded and object.TimeLength > 0 and object.IsPlaying then loadedCount+=1 end
   end)
  end)
  table.insert(connections,connection)
  local function focus()
   Focus.Request(player,worker:GetPivot().Position)
  end
  focus()
  player:SetAttribute("ReducedMotion",false)
  local first = sample()
  command:FireServer("Order",{worker},target)
  local focusAt = -math.huge
  waitFor(function()
   if os.clock()-focusAt > .2 then focus(); focusAt=os.clock() end
   local camera = workspace.CurrentCamera
   local point,visible = camera:WorldToViewportPoint(worker.PrimaryPart.Position)
   return Rules.WorldAudible(visible,point.Z,(camera.CFrame.Position-worker.PrimaryPart.Position).Magnitude) and
    worker:GetAttribute("Animation") == "Work" and worker:GetAttribute("WorkKind") == "repair" and
    Rules.IsNewPulse(worker:GetAttribute("LastWork"),first.last) and target:GetAttribute("HP") > first.hp and
    player:GetAttribute("wood") < first.wood
  end,120,"最近村民正常走到戰損目標，正式相機可聽時開始真正修復")
  local second = sample()
  check(second.hp == first.hp+15 and second.wood == first.wood-1,"第一次真正修復增加 15 HP、扣除 1 木材")
  print(string.format("[FEEDBACK_REPAIR PULSE] value=%.6f HP=%.3f->%.3f wood=%.3f->%.3f audioEnabled=true",
   second.last,first.hp,second.hp,first.wood,second.wood))
  repairPulse(second,5,"第二次正常修復發布新 LastWork 與真實 HP／木材變更")
  waitFor(function() return loadedCount > 0 end,2,"正式 LocalScript 播放已載入且真正 Playing 的 RTS_Repair 空間音效")
  waitFor(function() return worker:GetAttribute("Animation") == "Work" and poseChanged(rest,.02) end,
   2,"真正修復脈衝使工具或手臂姿態改變")
  player:SetAttribute("ReducedMotion",true)
  settleFrames("修復中減少動態等待三個真正 RenderStepped 畫格")
  check(not poseChanged(rest,.005),"減少動態將正在修復的工具或手臂還原至基準")
  player:SetAttribute("SoundEnabled",false)
  waitFor(function() local stats=probe:Invoke(); return not stats.enabled and stats.active == 0 and stats.world == 0 end,
   2,"本機靜音立即清空正式播放池")
  local mutedBefore,mutedSounds = sample(),soundCount
  repairPulse(mutedBefore,5,"靜音下下一次真正修復仍增加 HP 並支付木材")
  check(soundCount == mutedSounds and probe:Invoke().active == 0 and probe:Invoke().world == 0,
   "靜音修復沒有建立音效，總播放與世界播放均為零")
  player:SetAttribute("SoundEnabled",true)
  local unmutedBefore,unmutedLoaded = sample(),loadedCount
  repairPulse(unmutedBefore,5,"解除靜音後下一次真正修復仍遵守 HP 與扣款規則")
  waitFor(function() return loadedCount > unmutedLoaded end,2,"解除靜音後下一個真修復脈衝恢復已載入播放的空間音效")
  command:FireServer("Stop",{worker})
  waitFor(function() return worker:GetAttribute("Order") == "待命" and worker:GetAttribute("Animation") == "Idle" and
   worker:GetAttribute("WorkKind") == nil end,5,"正常停止修復，工人回到 Idle 並清除 repair 工作種類")
  waitFor(function() local stats=probe:Invoke(); return stats.active == 0 and stats.world == 0 end,
   2,"停止修復後短音效與播放池全部清理")
  local stopped,stoppedSounds = sample(),soundCount
  local observationEnd = os.clock()+1.1
  waitFor(function()
   assert(target:GetAttribute("HP") == stopped.hp and worker:GetAttribute("LastWork") == stopped.last and
    player:GetAttribute("wood") == stopped.wood and soundCount == stoppedSounds,
    "[FEEDBACK_REPAIR FAIL] 停止後仍增加 HP、扣木材、發布工作脈衝或建立修復音效")
   return os.clock() >= observationEnd
  end,2,"停止後跨越一秒修復週期仍保持 HP、LastWork、木材與音效不變")
  print(string.format("[FEEDBACK_REPAIR COMPLETE] %d 項；真正雙人戰損正常修復、兩次工作脈衝、音效、工具、減少動態、靜音及停止；%.1f 秒",
   checks,os.clock()-started))
  return {checks=checks,elapsedSeconds=os.clock()-started,damageHits=evidence.hits,damageAmount=evidence.damage}
 end,debug.traceback)
 if not ok then diagnostic(result) end
 for _,connection in ipairs(connections) do connection:Disconnect() end
 if worker and worker.Parent == workspace.Units and workspace:GetAttribute("MatchPhase") == "Playing" then command:FireServer("Stop",{worker}) end
 player:SetAttribute("SoundEnabled",savedSound)
 player:SetAttribute("ReducedMotion",savedMotion)
 Tests.Close()
 if not ok then error(result,0) end
 return result
end
function Tests.Run()
 assert(not Tests.running,"[FEEDBACK_REPAIR FAIL] 修復回饋驗證已在執行")
 Tests.running = true
 local ok,result = xpcall(run,debug.traceback)
 Tests.running = false
 Tests.Close()
 if not ok then error(result,0) end
 return result
end
script.Destroying:Once(Tests.Close)
return Tests
