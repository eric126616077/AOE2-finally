-- Studio 客戶端明確呼叫；require 不會開局或執行。
-- Run() 使用正常大廳／施工指令，會花費一棟房屋的木材並改變測試局。
-- 支援全新單人大廳，或沒有敵人的單人 Playing 沙盒；不修改伺服器資源／時間戳記。
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Tests = {running = false}

local function run()
 assert(RunService:IsStudio() and RunService:IsClient(), "[FEEDBACK_CONSTRUCTION FAIL] 僅限 Studio Play 客戶端")
 assert(#Players:GetPlayers() == 1, "[FEEDBACK_CONSTRUCTION FAIL] 此測試需要單人工作階段")
 local player = Players.LocalPlayer
 local Config = require(RS.GameData.GameConfig)
 local Grid = require(RS.Shared.Grid)
 local Rules = require(RS.Shared.FeedbackRules)
 local command = RS.RTSRemotes.Command
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local checks, deadline = 0, os.clock()+100
 local savedMotion, savedSound = player:GetAttribute("ReducedMotion"), player:GetAttribute("SoundEnabled")
 local connections, workers, sounds, loadedSounds, cues, flashes = {}, {}, {}, {}, {}, {}
 local site
 local function check(condition, message)
  assert(condition, "[FEEDBACK_CONSTRUCTION FAIL] " .. message)
  checks += 1
  print("[FEEDBACK_CONSTRUCTION PASS] " .. message)
 end
 local function waitFor(predicate, seconds, message)
  local untilTime = math.min(deadline, os.clock()+seconds)
  repeat
   if predicate() then check(true, message); return end
   assert(os.clock() < untilTime, "[FEEDBACK_CONSTRUCTION FAIL] " .. message .. "；等待逾時")
   task.wait(0.025)
  until false
 end
 local function ownModels(folder, kind, attribute)
  local result = {}
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model:GetAttribute("OwnerId") == player.UserId and
    (not kind or model:GetAttribute(attribute) == kind) then table.insert(result, model) end
  end
  return result
 end
 local function soundAdded(object)
  if not object:IsA("Sound") or not string.match(object.Name, "^RTS_") then return end
  local name = object.Name
  sounds[name] = (sounds[name] or 0)+1
  -- Sound is parented immediately before Play. Defer to inspect the actual decoder.
  task.defer(function()
   local untilTime = os.clock()+0.3
   repeat
    if object.IsLoaded and object.TimeLength > 0 then
     loadedSounds[name] = (loadedSounds[name] or 0)+1
     return
    end
    if not object.Parent then return end
    task.wait()
   until os.clock() >= untilTime
  end)
 end
 local function changed(rest, worker, tolerance)
  for part,offset in pairs(rest) do
   if not part.Parent then return false end
   local delta = offset:ToObjectSpace(worker.PrimaryPart.CFrame:ToObjectSpace(part.CFrame))
   local _,angle = delta:ToAxisAngle()
   if math.abs(angle) > tolerance or delta.Position.Magnitude > tolerance then return true end
  end
  return false
 end
 local function location(worker)
  Config.Map.MapSize = workspace:GetAttribute("MapSize") or Config.Map.MapSize
  local data, origin = Config.Buildings.House, worker:GetPivot().Position
  local params = OverlapParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  local excluded = {}
  for _,name in ipairs({"AOE2_Ground", "RTSScenery", "RTSClientEffects"}) do
   local item = workspace:FindFirstChild(name)
   if item then table.insert(excluded, item) end
  end
  params.FilterDescendantsInstances = excluded
  for radius=40,136,8 do
   for index=0,31 do
    local angle = index*math.pi/16
    local pos = Grid.snap(origin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius), data.size)
    if Grid.inBounds(pos, data.size) then
     local clear = true
     local hits = workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),
      Vector3.new(data.size.X*Config.Map.GridSize-.2, math.max(4,data.height), data.size.Y*Config.Map.GridSize-.2), params)
     for _,part in ipairs(hits) do
      if part.CanCollide or part:IsDescendantOf(workspace.Buildings) or part:IsDescendantOf(workspace.Units) or
       part:IsDescendantOf(workspace.Resources) then clear=false; break end
     end
     if clear then return pos end
    end
   end
  end
  error("[FEEDBACK_CONSTRUCTION FAIL] 找不到合法房屋工地")
 end
 local function focus(worker, building)
  require(RS.Shared.CameraFocus).Request(player, (worker.PrimaryPart.Position+building.PrimaryPart.Position)/2)
  waitFor(function()
   local camera = workspace.CurrentCamera
   if not camera or camera.CameraType ~= Enum.CameraType.Scriptable then return false end
   for _,model in ipairs({worker,building}) do
    local point,visible = camera:WorldToViewportPoint(model.PrimaryPart.Position)
    if not Rules.WorldAudible(visible,point.Z,(camera.CFrame.Position-model.PrimaryPart.Position).Magnitude) then return false end
   end
   return true
  end, 3, "正式相機同時看見施工村民與房屋並符合空間音效範圍")
 end
 local ok, result = xpcall(function()
  if workspace:GetAttribute("MatchPhase") == "Lobby" then
   require(RS.Shared.LobbyTests).Start({expectedPlayers=1, size="Small", aiCount=0,
    difficulty="Easy", population=100, startingResources="Rich", victory="Conquest"})
  end
  waitFor(function() return workspace:GetAttribute("MatchPhase") == "Playing" end, 15, "正常單人沙盒已開局")
  -- Playing is published before the lobby avatar cleanup necessarily reaches this client.
  waitFor(function() return workspace:GetAttribute("Sandbox") == true and player.Character == nil end,
   10, "無角色 RTS 沙盒可直接驗證施工回饋")
  waitFor(function()
   local units = workspace:FindFirstChild("Units")
   if not units then return false end
   workers = ownModels(units, "villager", "UnitType")
   if #workers < 3 then return false end
   for _,worker in ipairs(workers) do if not worker.PrimaryPart then return false end end
   return true
  end, 10, "正式三位村民及根零件已複製")
  local probe = player.PlayerScripts:FindFirstChild("RTSAudioProbe")
  check(probe and probe:IsA("BindableFunction"), "正式音效 LocalScript 唯讀探針存在")
  waitFor(function()
   local stats = probe:Invoke()
   return stats.preloadFinished == true and stats.preloadError == false and stats.failedAssets == 0 and
    stats.loadedAssets == stats.assetCount and stats.assetCount > 0
  end, 20, "施工回饋使用的正式音檔已全部預載")
  local effects = workspace:FindFirstChild("RTSClientEffects")
  check(effects and player.PlayerScripts.UnitMotion:GetAttribute("RTSMotionReady") == true,
   "正式動作 LocalScript 與回饋容器就緒")
  table.insert(connections, effects.ChildAdded:Connect(function(object)
   if object:IsA("Highlight") and object.Name == "CompletionFeedback" then
    table.insert(flashes, {adornee=object.Adornee, reduced=player:GetAttribute("ReducedMotion")})
   end
  end))
  table.insert(connections, workspace.Units.DescendantAdded:Connect(soundAdded))
  table.insert(connections, SoundService.ChildAdded:Connect(soundAdded))
  table.insert(connections, RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(_,cue)
   if type(cue) == "string" then cues[cue] = (cues[cue] or 0)+1 end
  end))
  command:FireServer("Stop", workers)
  waitFor(function()
   for _,worker in ipairs(workers) do
    if worker:GetAttribute("Animation") ~= "Idle" or worker:GetAttribute("Order") ~= "待命" then return false end
   end
   return true
  end, 5, "正常停止全部村民，基準姿勢沒有採集或施工")
  player:SetAttribute("ReducedMotion", true)
  player:SetAttribute("SoundEnabled", true)
  waitFor(function() return probe:Invoke().enabled == true and probe:Invoke().active == 0 end,
   2, "音效已開啟且前一次短音效已結束")
  local worker, rest = workers[1], {}
  for _,part in ipairs(worker:GetDescendants()) do
   if part:IsA("BasePart") and (part.Name == "ArmR" or part.Name == "Tool" or part.Name == "ToolHead") then
    rest[part] = worker.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
   end
  end
  check(next(rest) ~= nil, "無模型替代村民具有可驗證工具與手臂")
  local previousBuildings, wood, cap = {}, player:GetAttribute("wood"), player:GetAttribute("PopulationCap")
  for _,model in ipairs(ownModels(workspace.Buildings)) do previousBuildings[model] = true end
  check(type(wood) == "number" and wood >= Config.Buildings.House.cost.wood, "正常開局資源足以支付房屋")
  local pos = location(worker)
  player:SetAttribute("ReducedMotion", false)
  command:FireServer("Build", "House", pos, {worker})
  waitFor(function()
   for _,model in ipairs(ownModels(workspace.Buildings, "House", "BuildingType")) do
    if not previousBuildings[model] and model.PrimaryPart then site=model; return true end
   end
   return false
  end, 6, "正常建造請求產生伺服器房屋工地")
  check(player:GetAttribute("wood") == wood-Config.Buildings.House.cost.wood and site:GetAttribute("Complete") == false,
   "建立工地只扣一次成本，沒有立即完工")
  waitFor(function() return (cues.Build or 0) == 1 and (loadedSounds.RTS_Build or 0) == 1 end,
   2, "成功建立工地僅發布一次 Build 並由正式腳本播放已載入音效")
  check(player:GetAttribute("PopulationCap") == cap and (cues.ConstructionComplete or 0) == 0,
   "未完工沒有增加人口或提前發布完工音效")
  waitFor(function()
   local last = worker:GetAttribute("LastWork")
   return worker:GetAttribute("Animation") == "Work" and worker:GetAttribute("WorkKind") == "build" and
    type(last) == "number" and last > 0 and (site:GetAttribute("ConstructionProgress") or 0) > 0
  end, 35, "村民實際到場且增加施工進度才發布 build 工作時間戳記")
  focus(worker, site)
  waitFor(function() return (loadedSounds.RTS_BuildWork or 0) > 0 end,
   2, "正式腳本依 LastWork 播放已載入的村民施工空間音效")
  waitFor(function() return worker:GetAttribute("Animation") == "Work" and changed(rest,worker,.02) end,
   2, "正常施工會改變替代村民的工具或手臂姿勢")
  player:SetAttribute("ReducedMotion", true)
  waitFor(function() return not changed(rest,worker,.005) end, 2, "減少動態將正在施工的工具和手臂還原")
  command:FireServer("Stop", {worker})
  waitFor(function() return worker:GetAttribute("Animation") == "Idle" and site:GetAttribute("BuilderCount") == 0 end,
   3, "正常停止施工使正式工人與建築停止工作")
  check(site:GetAttribute("Complete") == false, "停止前只完成部分施工，保留可繼續工地")
  waitFor(function() return probe:Invoke().active == 0 end, 2, "停止施工後活動音效自然清理")
  local stoppedWork, stoppedProgress, stoppedSounds = worker:GetAttribute("LastWork"), site:GetAttribute("ConstructionProgress"), sounds.RTS_BuildWork or 0
  local observeUntil = os.clock()+1.1
  waitFor(function()
   assert(worker:GetAttribute("LastWork") == stoppedWork and site:GetAttribute("ConstructionProgress") == stoppedProgress and
    (sounds.RTS_BuildWork or 0) == stoppedSounds, "[FEEDBACK_CONSTRUCTION FAIL] 停工仍增加進度、發布時間戳記或播放施工音效")
   return os.clock() >= observeUntil
  end, 2, "跨過正常工作脈衝週期仍保持停工，沒有假施工音效")
  player:SetAttribute("SoundEnabled", false)
  waitFor(function() return probe:Invoke().enabled == false and probe:Invoke().active == 0 end,
   2, "正式靜音立即清空播放池")
  command:FireServer("Order", {worker}, site)
  waitFor(function()
   return worker:GetAttribute("WorkKind") == "build" and worker:GetAttribute("LastWork") ~= stoppedWork and
    site:GetAttribute("ConstructionProgress") > stoppedProgress
  end, 5, "靜音期間正常續建仍由伺服器增加進度與工作脈衝")
  check((sounds.RTS_BuildWork or 0) == stoppedSounds and probe:Invoke().active == 0,
   "靜音續建没有新增施工音效，且沒有影響施工邏輯")
  player:SetAttribute("SoundEnabled", true)
  waitFor(function() return (loadedSounds.RTS_BuildWork or 0) > stoppedSounds end,
   3, "解除靜音後下一個真正施工脈衝可再次播放")
  -- ReducedMotion stays true: completion's short opacity feedback remains useful.
  waitFor(function() return site:GetAttribute("Complete") == true end,
   Config.Buildings.House.buildTime+5, "正常續建使房屋真正完工")
  waitFor(function()
   return (cues.ConstructionComplete or 0) == 1 and (loadedSounds.RTS_ConstructionComplete or 0) == 1
  end, 2, "真正完工才發布一次完成 cue 並由正式腳本播放已載入音效")
  waitFor(function()
   for _,flash in ipairs(flashes) do if flash.adornee == site and flash.reduced == true then return true end end
   return false
  end, 2, "減少動態仍保留房屋真正完工的短暫輪廓回饋")
  check(site:GetAttribute("UnderConstruction") == false and site:GetAttribute("ConstructionProgress") == 1 and
   player:GetAttribute("PopulationCap") == cap+Config.Buildings.House.population,
   "完工回饋與權威進度、施工狀態及人口啟用一致")
  waitFor(function() return worker:GetAttribute("Animation") == "Idle" and worker:GetAttribute("WorkKind") == nil end,
   3, "完工村民回到待命並清除施工工作種類")
  local beforeCount, beforeWood = #ownModels(workspace.Buildings), player:GetAttribute("wood")
  local beforeBuild, beforeComplete, beforeError = cues.Build or 0, cues.ConstructionComplete or 0, cues.Error or 0
  local beforeSoundError, beforeSoundBuild = loadedSounds.RTS_Error or 0, sounds.RTS_Build or 0
  waitFor(function() return probe:Invoke().active == 0 end, 2, "完成短音效結束後準備失敗建造檢查")
  command:FireServer("Build", "House", pos, {worker})
  waitFor(function() return (cues.Error or 0) > beforeError and (loadedSounds.RTS_Error or 0) > beforeSoundError end,
   3, "重疊建造由伺服器拒絕，正式腳本播放已載入的 Error 音效")
  local errorEnd = os.clock()+Rules.Cues.Error.duration+.1
  waitFor(function() return os.clock() >= errorEnd and probe:Invoke().active == 0 end,
   2, "失敗音效到期清理，播放池沒有遺留聲音")
  check(#ownModels(workspace.Buildings) == beforeCount and player:GetAttribute("wood") == beforeWood,
   "失敗建造沒有建立新工地或扣款")
  check((cues.Build or 0) == beforeBuild and (cues.ConstructionComplete or 0) == beforeComplete and
   (sounds.RTS_Build or 0) == beforeSoundBuild, "失敗建造沒有假成功或完工音效")
  local stats = probe:Invoke()
  check(stats.active <= stats.maxVoices and stats.world <= stats.maxWorldVoices,
   "施工、完工及錯誤音效維持正式播放額度")
  print(string.format("[FEEDBACK_CONSTRUCTION COMPLETE] %d 項檢查；正常施工、停工、續建、靜音、減少動態、完工與拒絕建造回饋", checks))
  return checks
 end, debug.traceback)
 for _,connection in ipairs(connections) do connection:Disconnect() end
 if #workers > 0 and workspace:GetAttribute("MatchPhase") == "Playing" then command:FireServer("Stop", workers) end
 player:SetAttribute("ReducedMotion", savedMotion)
 player:SetAttribute("SoundEnabled", savedSound)
 if not ok then error(result, 0) end
 return result
end

function Tests.Run()
 assert(not Tests.running, "[FEEDBACK_CONSTRUCTION FAIL] 施工回饋驗證已在執行")
 Tests.running = true
 local ok, result = xpcall(run, debug.traceback)
 Tests.running = false
 if not ok then error(result, 0) end
 return result
end
return Tests
