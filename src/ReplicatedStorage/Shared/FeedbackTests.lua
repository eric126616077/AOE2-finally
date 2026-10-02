-- Studio 客戶端明確呼叫；require 不會執行。
-- RunPresentation() 僅短暫改變本機音效設定，最後還原。
-- RunGameplay() 須在全新單人大廳執行，以正常指令開局、採集與交貨；會改變測試局。
-- 桌面與短橫向觸控版面須分別開啟 Studio Play 執行；本測試不假造裝置大小。
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Tests = {running = false}

local function studioClient()
 assert(RunService:IsStudio() and RunService:IsClient(), "[FEEDBACK_TEST FAIL] 僅限 Studio Play 客戶端")
 return Players.LocalPlayer
end

local function context(limit)
 local checks, deadline = 0, os.clock() + limit
 local function check(condition, message)
  assert(condition, "[FEEDBACK_TEST FAIL] " .. message)
  checks += 1
  print("[FEEDBACK_TEST PASS] " .. message)
 end
 local function waitFor(predicate, seconds, message)
  local untilTime = math.min(deadline, os.clock() + seconds)
  repeat
   if predicate() then check(true, message); return end
   assert(os.clock() < untilTime, "[FEEDBACK_TEST FAIL] " .. message .. "；等待逾時")
   task.wait(0.05)
  until false
 end
 local function complete(message)
  print(string.format("[FEEDBACK_TEST COMPLETE] %d 項檢查；%s", checks, message))
  return checks
 end
 return check, waitFor, complete
end

local function guarded(callback)
 assert(not Tests.running, "[FEEDBACK_TEST FAIL] 音效與動作驗證已在執行")
 Tests.running = true
 local ok, result = xpcall(callback, debug.traceback)
 Tests.running = false
 if not ok then error(result, 0) end
 return result
end

local function labelText(button)
 for _,object in ipairs(button:GetDescendants()) do
  if object:IsA("TextLabel") then return object.Text end
 end
 return button:IsA("TextButton") and button.Text or nil
end

local function inspectMenu(player, check, waitFor)
 local screen, menu, sound
 waitFor(function()
  screen = player.PlayerGui:FindFirstChild("AOE2_MainGUI")
  menu = screen and screen:FindFirstChild("GameMenu", true)
  sound = menu and menu:FindFirstChild("SoundButton")
  return sound and sound:IsA("GuiButton") and sound.AbsoluteSize.Y > 0
 end, 10, "實際 PlayerGui 掛載音效開關")
 check(screen.IgnoreGuiInset == false, "音效選單使用 GUI 安全區域")
 local canvas = screen:FindFirstChild("Canvas")
 check(canvas and canvas:FindFirstChildOfClass("UIScale"), "正式 HUD 使用 UIScale")
 local safeOrigin, safeSize = canvas.AbsolutePosition, screen.AbsoluteSize
 local function contained(object, origin, size)
  local pos, extent = object.AbsolutePosition, object.AbsoluteSize
  return pos.X >= origin.X-1 and pos.Y >= origin.Y-1 and
   pos.X+extent.X <= origin.X+size.X+1 and pos.Y+extent.Y <= origin.Y+size.Y+1
 end
 check(contained(menu, safeOrigin, safeSize), "選單全部位於目前實際視窗安全範圍內")
 if game:GetService("UserInputService").TouchEnabled then
  check(sound.AbsoluteSize.X >= 44 and sound.AbsoluteSize.Y >= 44, "觸控音效開關至少 44 × 44 像素")
 end
 local names = {"ContinueButton", "SurrenderButton", "AutoWorkButton", "EdgeScrollButton", "GuidanceButton", "SoundButton", "MusicButton", "MusicVolumeButton", "SoundVolumeButton", "ReducedMotionButton"}
 local buttons = {}
 for _,name in ipairs(names) do
  local button = menu:FindFirstChild(name)
  check(button and button:IsA("GuiButton"), "正式選單掛載設定按鈕：" .. name)
  table.insert(buttons, button)
 end
 local savedScroll = menu:IsA("ScrollingFrame") and menu.CanvasPosition or nil
 local scrollOk, scrollError = xpcall(function()
  for _,button in ipairs(buttons) do
   if savedScroll then
    local maximum = math.max(0, menu.CanvasSize.Y.Offset-menu.Size.Y.Offset)
    menu.CanvasPosition = Vector2.new(0, math.clamp(button.Position.Y.Offset-8, 0, maximum))
   end
   waitFor(function()
    return contained(button, menu.AbsolutePosition, menu.AbsoluteSize) and contained(button, safeOrigin, safeSize)
   end, 1, "滾動後整個設定按鈕可在安全範圍內到達：" .. button.Name)
  end
 end, debug.traceback)
 if savedScroll then menu.CanvasPosition = savedScroll end
 if not scrollOk then error(scrollError, 0) end
 for first=1,#buttons do
  for second=first+1,#buttons do
   local a,b = buttons[first],buttons[second]
   local ap,as,bp,bs = a.AbsolutePosition,a.AbsoluteSize,b.AbsolutePosition,b.AbsoluteSize
   check(math.min(ap.X+as.X,bp.X+bs.X)-math.max(ap.X,bp.X) <= 1 or
    math.min(ap.Y+as.Y,bp.Y+bs.Y)-math.max(ap.Y,bp.Y) <= 1,
    "選單按鈕不互相覆蓋：" .. a.Name .. "／" .. b.Name)
  end
 end
 check(labelText(sound) == "音效：" .. (player:GetAttribute("SoundEnabled") == false and "關閉" or "開啟"), "實際音效標籤與玩家設定一致")
 if menu.Visible and contained(sound, menu.AbsolutePosition, menu.AbsoluteSize) then
  local probe = screen:FindFirstChild("RTSInputProbe")
  check(probe and probe:IsA("BindableFunction"), "正式 HUD 提供 Studio 唯讀命中探針")
  local result = probe:Invoke(sound.AbsolutePosition+sound.AbsoluteSize/2+game:GetService("GuiService"):GetGuiInset())
  check(type(result) == "table" and result.blocked == true and result.modal == true, "音效按鈕中心攔截世界指令")
 end
 return sound
end

-- 此處以實際 PlayerGui 和 LocalScript 就緒旗標驗收；不依賴 Command Bar 的 GUI require 快取。
function Tests.RunPresentation()
 return guarded(function()
  local player = studioClient()
  local check, waitFor, complete = context(45)
  local button = inspectMenu(player, check, waitFor)
  local soundScript = player.PlayerScripts:FindFirstChild("SoundFeedback")
  local motionScript = player.PlayerScripts:FindFirstChild("UnitMotion")
  check(soundScript and soundScript:IsA("LocalScript"), "音效 LocalScript 位於實際 PlayerScripts")
  check(motionScript and motionScript:IsA("LocalScript"), "動作 LocalScript 位於實際 PlayerScripts")
  waitFor(function() return player:GetAttribute("RTSSoundReady") == true and motionScript:GetAttribute("RTSMotionReady") == true end,
   5, "正式音效與動作 LocalScript 已初始化")
  local probe = player.PlayerScripts:FindFirstChild("RTSAudioProbe")
  check(probe and probe:IsA("BindableFunction"), "實際音效 LocalScript 提供 Studio 唯讀播放探針")
  local live = probe:Invoke()
  check(type(live) == "table" and live.maxVoices == 8 and live.maxWorldVoices == 5, "正式播放池有總量與世界音效上限")
  waitFor(function() return probe:Invoke().preloadFinished == true end, 20, "正式音效非同步預載完成")
  live = probe:Invoke()
  check(live.preloadError == false and live.failedAssets == 0 and live.loadedAssets == live.assetCount and live.assetCount > 0,
   "正式音效全部授權素材與內建替代音預載成功")
  local Audio = require(RS.Shared.AudioFeedback)
  local Rules = require(RS.Shared.FeedbackRules)
  local savedSound = player:GetAttribute("SoundEnabled")
  local savedModuleEnabled = Audio:GetStats().enabled
  local samples = {}
  local ok, result = xpcall(function()
   local known = {}
   for _,data in pairs(Rules.Cues) do
    for _,variant in ipairs(data.variants) do known[Rules.AssetId(variant.id)] = true end
    known[Rules.FallbackId(data)] = true
   end
   for id in pairs(known) do
    local sound = Instance.new("Sound")
    sound.Name, sound.SoundId, sound.Volume = "RTSFeedbackAssetTest", id, 0
    sound.Parent = game:GetService("SoundService")
    table.insert(samples, sound)
    sound:Play()
   end
   waitFor(function()
    for _,sound in ipairs(samples) do if not sound.IsLoaded or sound.TimeLength <= 0 then return false end end
    return true
   end, 15, "每個實際 Sound 都有 IsLoaded 與有效 TimeLength")
   for _,sound in ipairs(samples) do sound:Destroy() end
   table.clear(samples)
   player:SetAttribute("SoundEnabled", false)
   waitFor(function()
    local stats = probe:Invoke()
    return stats.enabled == false and stats.active == 0 and stats.world == 0 and labelText(button) == "音效：關閉"
   end, 2, "玩家靜音設定同步正式播放池、清理音效與實際標籤")
   Audio:StopAll()
   Audio:SetEnabled(true)
   check(Audio:Play("Age") == true, "本機音效 API 可播放已驗證內建音檔")
   check(Audio:GetStats().active > 0, "播放後實際保留活動聲音")
   local observed = 0
   local nextAllowed = os.clock()+Rules.GlobalInterval
   for _,cue in ipairs({"Defeat", "Victory", "MatchStart", "Train", "Research", "ConstructionComplete", "MatchEnd", "Error"}) do
    waitFor(function() return os.clock() >= nextAllowed end, 0.3, "依音效節流間隔準備連續播放：" .. cue)
    Audio:Play(cue)
    local stats = Audio:GetStats()
    observed = math.max(observed, stats.active)
    check(stats.active <= stats.maxVoices and stats.world <= stats.maxWorldVoices, "連續播放遵守活動聲音上限：" .. cue)
    nextAllowed = os.clock()+Rules.GlobalInterval
   end
   check(observed >= 2, "實際播放可同時保留多個聲音")
   Audio:SetEnabled(false)
   check(Audio:GetStats().active == 0 and Audio:GetStats().world == 0, "靜音立即清空此 API 的活動播放")
   check(Audio:Play("Select") == false, "靜音期間拒絕新增播放")
   Audio:SetEnabled(true)
   check(Audio:Play("Select") == true, "解除靜音後可再次播放")
   Audio:StopAll()
   check(Audio:GetStats().active == 0 and Audio:GetStats().world == 0, "StopAll 完整釋放播放額度")
   player:SetAttribute("SoundEnabled", true)
   waitFor(function() return probe:Invoke().enabled == true and labelText(button) == "音效：開啟" end,
    2, "解除玩家靜音同步正式播放池與標籤")
   return complete("已驗收目前裝置的版面、實際資產載入、多音與靜音；聽感與真人觸控仍需手動驗收")
  end, debug.traceback)
  for _,sound in ipairs(samples) do sound:Destroy() end
  Audio:StopAll()
  Audio:SetEnabled(savedModuleEnabled)
  player:SetAttribute("SoundEnabled", savedSound)
  if not ok then error(result, 0) end
  return result
 end)
end

local function ownModels(folder, player, kind)
 local result = {}
 for _,model in ipairs(folder:GetChildren()) do
  if model:IsA("Model") and model:GetAttribute("OwnerId") == player.UserId and
   (not kind or model:GetAttribute("UnitType") == kind) then table.insert(result, model) end
 end
 return result
end

local function finitePositive(value)
 return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function Tests.RunGameplay()
 return guarded(function()
  local player = studioClient()
  assert(workspace:GetAttribute("MatchPhase") == "Lobby" and #Players:GetPlayers() == 1,
   "[FEEDBACK_TEST FAIL] 請在全新單人 Play 大廳執行")
  local check, waitFor, complete = context(100)
  local Config = require(RS.GameData.GameConfig)
  local command = RS.RTSRemotes.Command
  local savedMotion = player:GetAttribute("ReducedMotion")
  local savedSound = player:GetAttribute("SoundEnabled")
  local workers = {}
  local function cleanup()
   if #workers > 0 and workspace:GetAttribute("MatchPhase") == "Playing" then command:FireServer("Stop", workers) end
   player:SetAttribute("ReducedMotion", savedMotion)
   player:SetAttribute("SoundEnabled", savedSound)
  end
  local ok, result = xpcall(function()
   require(RS.Shared.LobbyTests).Start({expectedPlayers=1, size="Small", aiCount=0,
    difficulty="Easy", population=100, startingResources="Rich", victory="Conquest"})
   waitFor(function() return workspace:GetAttribute("MatchPhase") == "Playing" end, 15, "正常大廳流程啟動單人測試局")
   waitFor(function()
    local units = workspace:FindFirstChild("Units")
    if not units then return false end
    workers = ownModels(units, player, "villager")
    if #workers < 3 then return false end
    for _,worker in ipairs(workers) do if not worker.PrimaryPart then return false end end
    return true
   end, 10, "三位初始村民及根零件同步")
   check(workspace:GetAttribute("Sandbox") == true and player.Character == nil, "正常無角色 RTS 沙盒")
   command:FireServer("Stop", workers)
   waitFor(function()
    for _,worker in ipairs(workers) do
     if worker:GetAttribute("Order") ~= "待命" or worker:GetAttribute("Animation") ~= "Idle" then return false end
    end
    return true
   end, 5, "停止村民後由伺服器發布 Idle")
   local worker, node, nearest = workers[1], nil, math.huge
   for _,resource in ipairs(workspace.Resources:GetChildren()) do
    if resource:IsA("Model") and resource.PrimaryPart and resource:GetAttribute("RTSManagedResource") == true and
     (resource:GetAttribute("Amount") or 0) >= 60 then
     local distance = (resource:GetPivot().Position-worker:GetPivot().Position).Magnitude
     if distance < nearest then node,nearest = resource,distance end
    end
   end
   check(node ~= nil, "正常地圖有足量鄰近採集資源")
   local key = node:GetAttribute("ResourceType")
   check(({wood=true,food=true,gold=true,stone=true})[key], "使用伺服器生成的有效資源種類")
   local beforeWork = worker:GetAttribute("LastWork")
   local beforeDelivery = worker:GetAttribute("LastDelivery")
   local amount,stock = node:GetAttribute("Amount"),player:GetAttribute(key)
   local rest = {}
   player:SetAttribute("ReducedMotion", true)
   require(RS.Shared.CameraFocus).Request(player,worker:GetPivot().Position)
   waitFor(function()
    local camera = workspace.CurrentCamera
    local _, visible = camera:WorldToViewportPoint(worker.PrimaryPart.Position)
    return visible and camera.CameraType == Enum.CameraType.Scriptable
   end, 3, "正式相機可看見採集驗證村民")
   -- Idle 時記錄 root-relative rest pose；不修改單位位置或任何伺服器屬性。
   for _,part in ipairs(worker:GetDescendants()) do
    if part:IsA("BasePart") and (part.Name == "ArmR" or part.Name == "Tool" or part.Name == "ToolHead") then
     rest[part] = worker.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
    end
   end
   player:SetAttribute("ReducedMotion", false)
   player:SetAttribute("SoundEnabled", true)
   command:FireServer("Order", {worker}, node)
   waitFor(function()
    return worker:GetAttribute("Animation") == "Work" and finitePositive(worker:GetAttribute("LastWork")) and
     worker:GetAttribute("LastWork") ~= beforeWork and (worker:GetAttribute("Carrying") or 0) > 0 and
     node:GetAttribute("Amount") < amount
   end, 35, "實際採得資源後才發布 Work 與 LastWork")
   check(worker:GetAttribute("WorkKind") == key, "採集工作種類與伺服器資源一致")
   check(player:GetAttribute(key) == stock, "採集中的背包尚未增加庫存")
   check((worker:GetAttribute("Carrying") or 0) <= Config.Units.villager.carryCapacity, "動作回饋沒有改變村民攜帶上限")
   -- 短橫向視窗可在村民走到資源後將其裁出畫面；世界音效會正確忽略不可見來源。
   -- 先聚焦到實際工作位置並驗收正式相機的可聽條件，再等待下一次採集音效。
   local FeedbackRules = require(RS.Shared.FeedbackRules)
   require(RS.Shared.CameraFocus).Request(player,worker:GetPivot().Position)
   waitFor(function()
    local camera = workspace.CurrentCamera
    if not camera or not worker.PrimaryPart then return false end
    local point, visible = camera:WorldToViewportPoint(worker.PrimaryPart.Position)
    return camera.CameraType == Enum.CameraType.Scriptable and FeedbackRules.WorldAudible(visible, point.Z,
     (camera.CFrame.Position-worker.PrimaryPart.Position).Magnitude)
   end, 3, "正式相機聚焦到村民當前工作位置且符合世界音效可聽範圍")
   local gatherCue = ({food="GatherFood",wood="GatherWood",gold="GatherGold",stone="GatherStone"})[key]
   waitFor(function()
    for _,object in ipairs(worker:GetDescendants()) do
     if object:IsA("Sound") and object.Name == "RTS_" .. gatherCue and object.IsLoaded then return true end
    end
    return false
   end, 4, "正式音效腳本依實際採集發布已載入的空間音效")
   if next(rest) then
    require(RS.Shared.CameraFocus).Request(player,worker:GetPivot().Position)
    waitFor(function()
     if worker:GetAttribute("Animation") ~= "Work" then return false end
     for part,offset in pairs(rest) do
      local current = worker.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
      local delta = offset:ToObjectSpace(current)
      local _,angle = delta:ToAxisAngle()
      if math.abs(angle) > 0.02 or delta.Position.Magnitude > 0.02 then return true end
     end
     return false
    end, 3, "可見 fallback 村民隨實際工作改變工具／手臂姿勢")
    player:SetAttribute("ReducedMotion", true)
    waitFor(function()
     for part,offset in pairs(rest) do
      local delta = offset:ToObjectSpace(worker.PrimaryPart.CFrame:ToObjectSpace(part.CFrame))
      local _,angle = delta:ToAxisAngle()
      if math.abs(angle) > 0.005 or delta.Position.Magnitude > 0.005 then return false end
     end
     return true
    end, 2, "減少動態設定將正在工作的零件還原 rest pose")
   else
    print("[FEEDBACK_TEST SKIP] 此村民使用未知模型，沒有 fallback 工具／手臂；姿勢需另行實機驗收")
   end
   waitFor(function()
    return finitePositive(worker:GetAttribute("LastDelivery")) and worker:GetAttribute("LastDelivery") ~= beforeDelivery and
     (player:GetAttribute(key) or 0) > stock
   end, 35, "實際交貨增加庫存後才發布 LastDelivery")
   command:FireServer("Stop", workers)
   waitFor(function() return worker:GetAttribute("Animation") == "Idle" and worker:GetAttribute("Order") == "待命" end,
    5, "採集驗證結束可正常停止村民")
   local stoppedWork, stoppedDelivery = worker:GetAttribute("LastWork"),worker:GetAttribute("LastDelivery")
   local observationEnd = os.clock()+1.1
   waitFor(function()
    assert(worker:GetAttribute("LastWork") == stoppedWork and worker:GetAttribute("LastDelivery") == stoppedDelivery,
     "[FEEDBACK_TEST FAIL] 待命產生新的採集或交貨時間戳記")
    return os.clock() >= observationEnd
   end, 2, "跨過一次正常採集週期仍保持待命時間戳記")
   return complete("由正常指令驗收採集、交貨與減少動態；未涵蓋戰鬥、攻城、施工及雙人同步")
  end, debug.traceback)
  cleanup()
  if not ok then error(result, 0) end
  return result
 end)
end

return Tests
