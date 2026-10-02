-- Explicit Studio CLIENT integration checks for Monks. Requiring this module does nothing.
-- Fresh solo Lobby only: starts Small / Rich / one Easy AI, reaches the Castle Age with normal
-- commands and real timers (no free resources), trains two Monks, then verifies conversion,
-- conversion rejections, manual healing and idle auto-healing against real server state.
-- Easy AI with Rich resources raids within ~5 minutes, so the reliable setup is Studio Server & Clients
-- with two players: client 1 runs Run({peer=true}) first, then client 2 runs Peer(). The peer only joins,
-- readies and stays passive; its villagers and Town Center provide the conversion target and the wound.
-- Solo variant (one Easy AI): Run(). Usage: task.spawn(function() require(game.ReplicatedStorage.Shared.MonkTests).Run({peer=true}) end)
local Tests = { running = false }
local KEYS = { "food", "wood", "gold", "stone" }

local function run(options)
 local RunService = game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(), "只能在 Studio Play 客戶端明確呼叫")
 options = options or {}
 local RS = game:GetService("ReplicatedStorage")
 local Players = game:GetService("Players")
 local player = Players.LocalPlayer
 local Config = require(RS.GameData.GameConfig)
 local Grid = require(RS.Shared.Grid)
 local command = RS:WaitForChild("RTSRemotes", 10):WaitForChild("Command", 10)
 local feedback = RS.RTSRemotes:WaitForChild("Feedback", 10)
 local started = os.clock()
 local deadline = started + (options.deadlineSeconds or 1800)
 local checks, messages, lastSend = 0, {}, 0
 local folders, home, center
 local connections = {}
 table.insert(connections, feedback.OnClientEvent:Connect(function(message) table.insert(messages, tostring(message)) end))

 local function log(text) print("[RTS_MONK] " .. text) end
 local function check(ok, message)
  assert(ok, "[RTS_MONK FAIL] " .. message)
  checks += 1
  print("[RTS_MONK PASS] " .. message)
 end
 local function flat(model)
  local p = model:GetPivot().Position
  return Vector3.new(p.X, Config.Map.GroundY, p.Z)
 end
 local function balances()
  local result = {}
  for _, key in ipairs(KEYS) do result[key] = player:GetAttribute(key) or 0 end
  return result
 end
 local function diagnostic()
  local b = balances()
  return string.format("時代 %s；資源 %d/%d/%d/%d；%.1f 秒", tostring(player:GetAttribute("Age")), b.food, b.wood, b.gold, b.stone, os.clock() - started)
 end
 local function send(action, ...)
  local remaining = 0.25 - (os.clock() - lastSend)
  if remaining > 0 then task.wait(remaining) end
  command:FireServer(action, ...)
  lastSend = os.clock()
 end
 local function waitFor(predicate, seconds, label)
  local untilTime = math.min(deadline, os.clock() + seconds)
  repeat
   local value = predicate()
   if value then return value end
   if folders then
    assert(workspace:GetAttribute("MatchPhase") == "Playing" and not player:GetAttribute("Defeated"), "[RTS_MONK FAIL] 驗收對局意外結束；" .. diagnostic())
   end
   task.wait(0.1)
  until os.clock() >= untilTime
  error("[RTS_MONK FAIL] " .. label .. " 等待逾時；" .. diagnostic(), 0)
 end
 local function owned(folder, kind, attribute)
  local result = {}
  for _, model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("OwnerId") == player.UserId and (not kind or model:GetAttribute(attribute) == kind) then
    table.insert(result, model)
   end
  end
  return result
 end
 local function villagers() return owned(folders.units, "villager", "UnitType") end
 local function messageSince(since, text)
  for index = since + 1, #messages do if string.find(messages[index], text, 1, true) then return true end end
  return false
 end
 local function paid(before, cost)
  for _, key in ipairs(KEYS) do
   if math.abs((before[key] - (cost[key] or 0)) - (player:GetAttribute(key) or 0)) > 0.001 then return false end
  end
  return true
 end
 local function placement(kind)
  local data, g = Config.Buildings[kind], Config.Map.GridSize
  local half = workspace:GetAttribute("MatchSize") / 2
  local params = OverlapParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  local excluded = {}
  for _, name in ipairs({ "AOE2_Ground", "RTSScenery" }) do
   local item = workspace:FindFirstChild(name)
   if item then table.insert(excluded, item) end
  end
  params.FilterDescendantsInstances = excluded
  -- Face the map centre so the buildings do not crowd the opening resources at the map edge.
  local inward = math.atan2(-home.Z, -home.X)
  for radius = 56, 312, 8 do
   for index = 0, 31 do
    local angle = inward + ((index % 2 == 0) and 1 or -1) * math.floor((index + 1) / 2) * math.pi / 16
    local pos = Grid.snap(home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), data.size)
    if math.abs(pos.X) + data.size.X * g / 2 <= half - 8 and math.abs(pos.Z) + data.size.Y * g / 2 <= half - 8 then
     local clear = true
     local hits = workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, data.height / 2, 0)),
      Vector3.new(data.size.X * g + 6, math.max(4, data.height), data.size.Y * g + 6), params)
     for _, part in ipairs(hits) do
      if part.CanCollide or part:IsDescendantOf(folders.buildings) or part:IsDescendantOf(folders.units) or part:IsDescendantOf(folders.resources) then clear = false; break end
     end
     if clear then return pos end
    end
   end
  end
  error("[RTS_MONK FAIL] 無合法建築位置：" .. data.name, 0)
 end
 local function build(kind)
  local data = Config.Buildings[kind]
  local before, existing = balances(), {}
  for _, model in ipairs(owned(folders.buildings, kind, "BuildingType")) do existing[model] = true end
  local workers = villagers()
  assert(#workers >= 1, "缺少施工村民")
  send("Build", kind, placement(kind), workers)
  local site = waitFor(function()
   for _, model in ipairs(owned(folders.buildings, kind, "BuildingType")) do if not existing[model] then return model end end
  end, 8, data.name .. "建立工地")
  waitFor(function() return paid(before, data.cost) end, 8, data.name .. "扣款複製")
  waitFor(function() return site.Parent and site:GetAttribute("Complete") == true end, data.buildTime + 120, data.name .. "正常施工完工")
  check(true, data.name .. " 由村民正常施工完成（" .. diagnostic() .. "）")
  return site
 end
 local function advance(age)
  local data = Config.Ages[age]
  local before = balances()
  send("AdvanceAge", center)
  waitFor(function() return center:GetAttribute("Research") == data.name and paid(before, data.cost) end, 8, data.name .. "研究開始")
  waitFor(function() return player:GetAttribute("Age") == age end, data.time + 20, data.name .. "計時完成")
  check(true, "進入" .. data.name .. "（" .. diagnostic() .. "）")
 end

 local ok, failure = xpcall(function()
  local Lobby = require(RS.Shared.LobbyTests)
  if options.peer then
   check(#Players:GetPlayers() == 2 and workspace:GetAttribute("MatchPhase") == "Lobby", "兩名 Studio 玩家在新大廳開始")
   local roomId = Lobby.Join()
   check(workspace:GetAttribute("LobbyRoom_" .. roomId .. "_HostUserId") == player.UserId, "此客戶端先集合成為房主")
   log("等待第二客戶端執行 MonkTests.Peer()")
   waitFor(function() return (workspace:GetAttribute("LobbyRoom_" .. roomId .. "_Players") or 0) >= 2 end, 900, "第二玩家集合")
   Lobby.Start({ expectedPlayers = 2, size = "Small", aiCount = 0, difficulty = "Easy", population = 100, startingResources = "Rich", victory = "Conquest" })
  else
   check(#Players:GetPlayers() == 1 and workspace:GetAttribute("MatchPhase") == "Lobby", "在新的單人 Studio 大廳開始")
   Lobby.Start({ expectedPlayers = 1, size = "Small", aiCount = 1, difficulty = "Easy", population = 100, startingResources = "Rich", victory = "Conquest" })
  end
  waitFor(function() return workspace:GetAttribute("MatchPhase") == "Playing" and typeof(player:GetAttribute("HomePosition")) == "Vector3" end, 30, "開局")
  folders = { buildings = workspace:WaitForChild("Buildings", 8), units = workspace:WaitForChild("Units", 8), resources = workspace:WaitForChild("Resources", 8) }
  home = player:GetAttribute("HomePosition")
  send("AutoWork", false)
  center = waitFor(function() return owned(folders.buildings, "TownCenter", "BuildingType")[1] end, 10, "己方市鎮中心")
  check(player:GetAttribute("food") == 1200 and player:GetAttribute("gold") == 800, "使用正式 Rich 開局資源，沒有測試加值")
  check(Config.Units.monk and table.find(Config.Buildings.Monastery.trains, "monk") ~= nil, "修道院設定可訓練僧侶")

  -- 黑暗 → 封建 → 城堡：只靠開局資源與市集正常交易。
  build("Mill"); build("LumberCamp")
  advance(2)
  build("Blacksmith")
  local market = build("Market")
  local before = balances()
  send("Trade", market, "food", "Buy")
  waitFor(function() return paid(before, { gold = Config.MarketTrade.buyGold, food = -Config.MarketTrade.batch }) end, 8, "市集買入食物")
  check(true, "市集以正常價格買入食物")
  advance(3)
  build("House")
  local monastery = build("Monastery")

  -- 訓練兩名僧侶。
  before = balances()
  send("Train", monastery, "monk"); send("Train", monastery, "monk")
  waitFor(function() return paid(before, { gold = Config.Units.monk.cost.gold * 2 }) end, 8, "兩名僧侶扣款")
  local monks = waitFor(function()
   local list = owned(folders.units, "monk", "UnitType")
   return #list >= 2 and list or nil
  end, Config.Units.monk.trainTime * 2 + 40, "修道院訓練兩名僧侶")
  local monk, healer = monks[1], monks[2]
  check(monk:GetAttribute("Faith") == Config.Monk.maxFaith and monk:GetAttribute("MaxFaith") == Config.Monk.maxFaith, "新僧侶信仰全滿並複製到客戶端")
  check(monk:GetAttribute("Attack") == 0 and monk:GetAttribute("Range") == Config.Units.monk.range, "鍛造等軍事科技以外，僧侶攻擊 0、射程為招降距離")

  -- 選出遠離敵方防禦建築的敵方單位，避免僧侶被市鎮中心射擊。
  local function enemyOwner(model)
   local id = model:GetAttribute("OwnerId")
   return id ~= nil and id ~= player.UserId
  end
  local function safeEnemyUnit(from)
   local best, bestDistance
   for _, unit in ipairs(folders.units:GetChildren()) do
    local data = unit:IsA("Model") and unit.PrimaryPart and Config.Units[unit:GetAttribute("UnitType")]
    if data and enemyOwner(unit) and data.class == "villager" and (unit:GetAttribute("HP") or 0) > 0 and (not options.peer or unit:GetAttribute("Order") == "待命") then
     local safe = true
     -- 敵方軍隊會優先攻擊 30 生命的僧侶；目標附近不能有敵方軍隊。
     for _, other in ipairs(folders.units:GetChildren()) do
      local o = other:IsA("Model") and other.PrimaryPart and Config.Units[other:GetAttribute("UnitType")]
      if o and enemyOwner(other) and o.class ~= "villager" and o.class ~= "monk" and (flat(other) - flat(unit)).Magnitude < Config.Combat.acquisitionRadius + Config.Units.monk.range + 10 then safe = false; break end
     end
     for _, building in ipairs(folders.buildings:GetChildren()) do
      local b = building:IsA("Model") and building.PrimaryPart and Config.Buildings[building:GetAttribute("BuildingType")]
      if b and b.damage and enemyOwner(building) and (flat(building) - flat(unit)).Magnitude < (b.range or 64) + Config.Units.monk.range + 30 then safe = false; break end
     end
     local distance = (flat(unit) - from).Magnitude
     if safe and (not bestDistance or distance < bestDistance) then best, bestDistance = unit, distance end
    end
   end
   return best
  end

  -- 拒絕：敵方建築不能招降，且不留下指令。
  local enemyBuilding
  for _, building in ipairs(folders.buildings:GetChildren()) do
   if building:IsA("Model") and enemyOwner(building) and building:GetAttribute("BuildingType") then enemyBuilding = building; break end
  end
  check(enemyBuilding ~= nil, "找到 AI 建築作為拒絕目標")
  local since = #messages
  send("Order", { monk }, enemyBuilding)
  waitFor(function() return messageSince(since, "僧侶無法招降建築") end, 6, "建築招降拒絕訊息")
  check(monk:GetAttribute("OrderKind") ~= "convert", "右鍵敵方建築不會產生招降指令")

  -- 招降：至少 convertMin 秒、最多 convertMax 秒（加上取樣容差）。
  local target = waitFor(function() return safeEnemyUnit(flat(monk)) end, 180, "AI 單位離開防禦範圍")
  local targetKind, targetName = target:GetAttribute("UnitType"), target:GetAttribute("DisplayName") or target.Name
  log("招降目標 " .. tostring(targetKind) .. " @ " .. tostring(flat(target)))
  local ownBefore = {}
  for _, unit in ipairs(owned(folders.units, targetKind, "UnitType")) do ownBefore[unit] = true end
  send("Order", { monk }, target)
  waitFor(function() return monk:GetAttribute("OrderKind") == "convert" end, 6, "伺服器接受招降指令")
  check(monk:GetAttribute("Order") == "招降", "僧侶狀態顯示招降")
  -- 伺服器公開累計的射程內招降秒數；以成功前最後一次讀值核對 AOE2 式 4–10 秒視窗。
  local lastConversionTime, lastLog = 0, os.clock()
  local converted = waitFor(function()
   assert(monk.Parent, "[RTS_MONK FAIL] 僧侶在招降途中陣亡；" .. diagnostic())
   local t = monk:GetAttribute("ConversionTime")
   if type(t) == "number" then lastConversionTime = math.max(lastConversionTime, t) end
   if os.clock() - lastLog >= 5 then
    lastLog = os.clock()
    log(string.format("招降中：OrderKind=%s Animation=%s 距離=%.1f 累計=%.1f", tostring(monk:GetAttribute("OrderKind")), tostring(monk:GetAttribute("Animation")),
     target.Parent and (flat(target) - flat(monk)).Magnitude or -1, lastConversionTime))
   end
   if target.Parent == nil then
    for _, unit in ipairs(owned(folders.units, targetKind, "UnitType")) do if not ownBefore[unit] then return unit end end
   end
  end, 150, "招降完成")
  log(string.format("招降累計 %.2f 秒（%s）", lastConversionTime, tostring(targetName)))
  check(lastConversionTime >= Config.Monk.convertMin - 0.3 and lastConversionTime <= Config.Monk.convertMax + 1.2,
   string.format("招降在射程內累計 %d–%d 秒視窗成功（實測 %.2f 秒）", Config.Monk.convertMin, Config.Monk.convertMax, lastConversionTime))
  check(converted:GetAttribute("OwnerId") == player.UserId and converted:GetAttribute("UnitType") == targetKind, "被招降單位轉為己方並保留類型")
  check((converted:GetAttribute("HP") or 0) >= 1 and (converted:GetAttribute("HP") or 0) <= (converted:GetAttribute("MaxHP") or 0), "被招降單位生命在合法範圍")
  check((monk:GetAttribute("Faith") or 1) < 5 and monk:GetAttribute("OrderKind") == nil, "招降後信仰歸零、僧侶回到待命")

  -- 信仰不足時下令：伺服器提示恢復中。
  local second = safeEnemyUnit(flat(monk))
  if second then
   since = #messages
   send("Order", { monk }, second)
   waitFor(function() return messageSince(since, "信仰恢復中") end, 6, "信仰恢復提示")
   check(true, "信仰不足時下令會提示恢復中")
   task.wait(2)
   check(second.Parent ~= nil and second:GetAttribute("OwnerId") ~= player.UserId, "信仰不足期間不會招降")
   send("Order", { monk }, flat(monk))
  end
  local faithBefore = monk:GetAttribute("Faith") or 0
  task.wait(3.2)
  local faithAfter = monk:GetAttribute("Faith") or 0
  local expectedGain = Config.Monk.maxFaith / Config.Monk.rechargeTime * 3
  check(faithAfter > faithBefore and math.abs((faithAfter - faithBefore) - expectedGain) <= Config.Monk.maxFaith / Config.Monk.rechargeTime * 1.5,
   string.format("信仰約每秒 %.1f 恢復（3 秒 +%.1f）", Config.Monk.maxFaith / Config.Monk.rechargeTime, faithAfter - faithBefore))

  -- 招降僧侶停在地圖中段，會自動治療經過的斥候；先讓它回到治療僧侶旁待命，兩名僧侶位置一致。
  send("Order", { monk }, flat(healer) + Vector3.new(10, 0, 0))
  waitFor(function() return monk:GetAttribute("Order") ~= "待命" end, 4, "招降僧侶接受回防指令")
  -- 治療僧侶旁的點可能落在修道院占地內；以距離判定回到附近後下停止，不要求抵達精確點。
  waitFor(function()
   assert(monk.Parent, "[RTS_MONK FAIL] 招降僧侶回防途中陣亡；" .. diagnostic())
   return monk:GetAttribute("Order") == "待命" or (flat(monk) - flat(healer)).Magnitude <= 30
  end, 180, "招降僧侶回到治療僧侶旁")
  send("Stop", { monk })
  waitFor(function() return monk:GetAttribute("Order") == "待命" end, 6, "招降僧侶停止待命")
  log(string.format("招降僧侶回防，距治療僧侶 %.1f", (flat(monk) - flat(healer)).Magnitude))
  -- 治療：讓斥候進入敵方市鎮中心射程受傷，再撤回。
  local scout = owned(folders.units, "scout", "UnitType")[1]
  check(scout ~= nil, "仍有開局斥候作為治療對象")
  since = #messages
  send("Order", { healer }, scout)
  task.wait(1.5)
  check(healer:GetAttribute("OrderKind") ~= "heal", "滿血單位不能治療")
  local enemyCenter
  for _, building in ipairs(folders.buildings:GetChildren()) do
   if building:IsA("Model") and enemyOwner(building) and building:GetAttribute("BuildingType") == "TownCenter" then enemyCenter = building; break end
  end
  check(enemyCenter ~= nil, "找到 AI 市鎮中心作為傷害來源")
  local function wound(retreat, radius, allowHealed)
   local start = scout:GetAttribute("HP")
   local direction = (flat(scout) - flat(enemyCenter)).Unit
   send("Order", { scout }, flat(enemyCenter) + direction * 40)
   waitFor(function() return (scout:GetAttribute("HP") or 0) < start end, 120, "斥候受到正常射擊")
   send("Order", { scout }, retreat)
   -- 以伺服器回報的待命狀態判定抵達或無法再前進；目標點被建築或樹林擋住時停在附近。
   waitFor(function() return scout:GetAttribute("Order") ~= "待命" end, 4, "斥候接受撤退指令")
   waitFor(function()
    assert(scout.Parent, "[RTS_MONK FAIL] 斥候在撤退途中陣亡；" .. diagnostic())
    return scout:GetAttribute("Order") == "待命"
   end, 150, "斥候撤退後待命")
   local distance = (flat(scout) - flat(healer)).Magnitude
   log(string.format("斥候撤退停在距治療僧侶 %.1f（目標點偏差 %.1f）", distance, (flat(scout) - retreat).Magnitude))
   check((allowHealed or scout:GetAttribute("HP") < scout:GetAttribute("MaxHP")) and radius(distance), string.format("斥候受傷撤回（%d / %d，距僧侶 %.1f）", scout:GetAttribute("HP"), scout:GetAttribute("MaxHP"), distance))
  end
  -- 手動：撤到兩名僧侶自動治療半徑之外，再由玩家下令。
  -- 停在僧侶與敵方主城之間、自動治療半徑外，撤退路線不會經過僧侶身旁。
  local away = flat(healer) + (flat(enemyCenter) - flat(healer)).Unit * (Config.Monk.autoHealRadius + 30)
  wound(away, function(distance) return distance > Config.Monk.autoHealRadius + 1 end)
  task.wait(1.5)
  check(healer:GetAttribute("OrderKind") ~= "heal", "受傷單位在自動治療半徑外時，僧侶不會自行跑去治療")
  local healStart, healHP = os.clock(), scout:GetAttribute("HP")
  send("Order", { healer }, scout)
  waitFor(function() return healer:GetAttribute("OrderKind") == "heal" end, 6, "伺服器接受治療指令")
  check(healer:GetAttribute("Order") == "治療", "僧侶狀態顯示治療")
  waitFor(function() return scout:GetAttribute("HP") >= scout:GetAttribute("MaxHP") end, 90, "治療到滿血")
  local rate = (scout:GetAttribute("MaxHP") - healHP) / math.max(0.1, os.clock() - healStart)
  check(rate <= Config.Monk.healRate * 1.6, string.format("治療速率不超過每秒 %d（實測 %.2f）", Config.Monk.healRate, rate))
  waitFor(function() return healer:GetAttribute("OrderKind") == nil end, 4, "滿血後停止治療")
  check(true, "滿血後僧侶回到待命")

  -- 自動治療：待命僧侶自動照顧附近受傷的己方單位。
  send("Order", { healer }, flat(healer))
  waitFor(function() return healer:GetAttribute("OrderKind") == nil end, 20, "治療僧侶待命")
  -- 撤回途中進入半徑就可能已開始自動治療，因此從受傷前開始監看兩名僧侶的指令。
  local autoHealed = false
  for _, m in ipairs({ healer, monk }) do
   table.insert(connections, m:GetAttributeChangedSignal("OrderKind"):Connect(function()
    if m:GetAttribute("OrderKind") == "heal" then autoHealed = true end
   end))
  end
  -- 斥候受傷後撤到僧侶附近（不是僧侶站的位置），只要求僧侶自行開始治療，不要求斥候先停下。
  local before = scout:GetAttribute("HP")
  send("Order", { scout }, flat(enemyCenter) + (flat(scout) - flat(enemyCenter)).Unit * 40)
  waitFor(function() return (scout:GetAttribute("HP") or 0) < before end, 120, "斥候第二次受到正常射擊")
  send("Order", { scout }, flat(healer) + (flat(enemyCenter) - flat(healer)).Unit * 24)
  waitFor(function()
   assert(scout.Parent, "[RTS_MONK FAIL] 斥候在撤退途中陣亡；" .. diagnostic())
   return autoHealed
  end, 120, "待命僧侶自動治療")
  log(string.format("自動治療開始時斥候距治療僧侶 %.1f", (flat(scout) - flat(healer)).Magnitude))
  check(true, "待命僧侶自動對附近受傷單位下達治療")
  waitFor(function() return scout:GetAttribute("HP") >= scout:GetAttribute("MaxHP") end, 90, "自動治療到滿血")
  check(true, "自動治療恢復滿血")
  check(workspace:GetAttribute("MatchPhase") == "Playing", "整個僧侶流程後對局仍正常")
 end, debug.traceback)
 for _, connection in ipairs(connections) do connection:Disconnect() end
 if not ok then
  print("[RTS_MONK FAIL] " .. tostring(failure))
  error(failure, 0)
 end
 print(string.format("[RTS_MONK COMPLETE] %d checks, %.1f 秒", checks, os.clock() - started))
 return checks
end

-- Second Studio client: join the host's room, ready up and stay passive.
function Tests.Peer()
 local RS = game:GetService("ReplicatedStorage")
 local player = game:GetService("Players").LocalPlayer
 local command = RS.RTSRemotes.Command
 local roomId = require(RS.Shared.LobbyTests).Join()
 print("[RTS_MONK PEER] 已集合，等待房主設定")
 local deadline = os.clock() + 900
 while workspace:GetAttribute("MatchPhase") ~= "Playing" do
  assert(os.clock() < deadline, "[RTS_MONK PEER FAIL] 等待開局逾時")
  local revision = workspace:GetAttribute("LobbyRoom_" .. roomId .. "_SettingsRevision")
  if workspace:GetAttribute("LobbyRoom_" .. roomId .. "_Configured") == true and player:GetAttribute("LobbyReady") ~= true then
   command:FireServer("LobbyReady", true, revision)
  end
  task.wait(1)
 end
 -- 關閉自動工作，所有村民停在原地；一名村民走到市鎮中心射程外的固定點作為招降目標。
 command:FireServer("AutoWork", false)
 local Config = require(RS.GameData.GameConfig)
 local units, center = {}, nil
 local start = os.clock()
 repeat
  task.wait(0.5)
  units, center = {}, nil
  for _, unit in ipairs(workspace.Units:GetChildren()) do
   if unit:GetAttribute("OwnerId") == player.UserId and unit:GetAttribute("UnitType") == "villager" then table.insert(units, unit) end
  end
  for _, building in ipairs(workspace.Buildings:GetChildren()) do
   if building:GetAttribute("OwnerId") == player.UserId and building:GetAttribute("BuildingType") == "TownCenter" then center = building end
  end
 until (#units >= 3 and center) or os.clock() - start > 15
 assert(center and #units >= 1, "[RTS_MONK PEER FAIL] 找不到己方市鎮中心或村民")
 task.wait(0.3); command:FireServer("Stop", units)
 local origin = center:GetPivot().Position
 local inward = Vector3.new(-origin.X, 0, -origin.Z).Unit
 local spot = Vector3.new(origin.X, Config.Map.GroundY, origin.Z) + inward * (Config.Buildings.TownCenter.range + Config.Units.monk.range + 90)
 task.wait(0.3); command:FireServer("Order", { units[1] }, spot)
 if units[2] then
  -- 第二名村民停在旁邊，供「信仰不足時不能招降」檢查。
  task.wait(0.3); command:FireServer("Order", { units[2] }, spot + Vector3.new(-inward.Z, 0, inward.X) * 14)
 end
 print("[RTS_MONK PEER] 開局，保持被動；招降目標村民前往 " .. tostring(spot))
end

function Tests.Run(options)
 assert(not Tests.running, "僧侶測試已在執行")
 Tests.running = true
 local ok, result = pcall(run, options)
 Tests.running = false
 if not ok then error(result, 0) end
 return result
end

return Tests
