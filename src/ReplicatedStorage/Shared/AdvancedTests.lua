-- Explicit Studio CLIENT integration checks. Requiring this module does nothing.
-- Fresh solo Lobby only. Uses normal game commands, real gathering and real timers.
-- RunDevelopment() may take 10-20 minutes. Never run alongside another test module.
-- Range/attack cadence and destroyed-research cancellation need a separate two-side battle.
local Tests = { running = false }
local RESOURCE_KEYS = { "food", "wood", "gold", "stone" }

local function development(options)
 assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsClient(), "只能在 Studio Play 客戶端明確呼叫")
 options = options or {}
 local duration = options.deadlineSeconds or 1200
 assert(type(duration) == "number" and duration == duration and duration >= 600 and duration <= 1800, "總期限須為 600–1800 秒，預設 1200 秒")
 local RS = game:GetService("ReplicatedStorage")
 local Players = game:GetService("Players")
 local player = Players.LocalPlayer
 local Config = require(RS.GameData.GameConfig)
 local Grid = require(RS.Shared.Grid)
 local command = RS:WaitForChild("RTSRemotes", 10):WaitForChild("Command", 10)
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local feedback = RS.RTSRemotes:WaitForChild("Feedback", 10)
 local started, deadline = os.clock(), os.clock() + duration
 local checks, messages, builtKinds, researched = 0, {}, {}, {}
 local probeConnections = {}
 local folders, home, center
 local paused, playing, busy, assignment = true, false, {}, {}
 local lastSend, lastManage, lastReport = 0, 0, started
 local desired = { food = 1250, wood = 1400, gold = 1250, stone = 1150 }
 local connection = feedback.OnClientEvent:Connect(function(message)
  table.insert(messages, tostring(message))
 end)
 local function check(ok, message)
  assert(ok, "[RTS_ADVANCED FAIL] " .. message)
  checks += 1
  print("[RTS_ADVANCED PASS] " .. message)
 end
 local function approximately(a, b)
  return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.0001
 end
 local function owned(folder, kind, attribute)
  local result = {}
  for _, model in ipairs(folder:GetChildren()) do
   if model:GetAttribute("OwnerId") == player.UserId and (not kind or model:GetAttribute(attribute) == kind) then
    table.insert(result, model)
   end
  end
  return result
 end
 local function workers()
  return folders and owned(folders.units, "villager", "UnitType") or {}
 end
 local function flat(model)
  local p = model:GetPivot().Position
  return Vector3.new(p.X, Config.Map.GroundY, p.Z)
 end
 local function balances()
  local result = {}
  for _, key in ipairs(RESOURCE_KEYS) do result[key] = player:GetAttribute(key) or 0 end
  return result
 end
 local function balancesEqual(a, b)
  for _, key in ipairs(RESOURCE_KEYS) do if not approximately(a[key], b[key]) then return false end end
  return true
 end
 local function diagnostic()
  local b = balances()
  return string.format("時代 %s；資源 %.1f/%.1f/%.1f/%.1f；已用 %.1f 秒", tostring(player:GetAttribute("Age")), b.food, b.wood, b.gold, b.stone, os.clock() - started)
 end
 local function send(action, ...)
  local remaining = 0.25 - (os.clock() - lastSend)
  if remaining > 0 then task.wait(remaining) end
  assert(os.clock() < deadline, "[RTS_ADVANCED FAIL] 全程期限已到；" .. diagnostic())
  command:FireServer(action, ...)
  lastSend = os.clock()
 end
 local function nearestResource(kind, position, minimumAmount)
  local best, distance
  local function consider(model)
   if model:IsA("Model") and model.PrimaryPart and (model:GetAttribute("RTSManagedResource") == true or (model:GetAttribute("OwnerId") == player.UserId and model:GetAttribute("BuildingType") == "Farm"))
    and model:GetAttribute("ResourceType") == kind and (model:GetAttribute("Amount") or 0) >= (minimumAmount or 1) then
    local d = (flat(model) - position).Magnitude
    if not distance or d < distance then best, distance = model, d end
   end
  end
  for _, model in ipairs(folders.resources:GetChildren()) do consider(model) end
  if kind == "food" then
   for _, model in ipairs(owned(folders.buildings, "Farm", "BuildingType")) do
    if model:GetAttribute("Complete") then consider(model) end
   end
  end
  return best
 end
 local function maintainEconomy()
  if paused or not folders or os.clock() - lastManage < 5 then return end
  lastManage = os.clock()
  local available, groups = {}, {}
  local missing = {}
  for _, key in ipairs(RESOURCE_KEYS) do
   if (player:GetAttribute(key) or 0) < desired[key] then table.insert(missing, key) end
  end
  for _, worker in ipairs(workers()) do if worker.PrimaryPart and not busy[worker] then table.insert(available, worker) end end
  for index, worker in ipairs(available) do
   if #missing == 0 then
    if worker:GetAttribute("Order") ~= "待命" then groups.stop = groups.stop or {}; table.insert(groups.stop, worker) end
    assignment[worker] = nil
   else
    -- Keep existing productive routes while their resource remains needed.
    local key = assignment[worker]
    if not key or not table.find(missing, key) then key = missing[(index - 1) % #missing + 1] end
    local order = worker:GetAttribute("Order")
    if assignment[worker] ~= key or order == "待命" then
     groups[key] = groups[key] or {}
     table.insert(groups[key], worker)
     assignment[worker] = key
    end
   end
  end
  for key, selection in pairs(groups) do
   if key == "stop" then send("Stop", selection)
   else
    local target = nearestResource(key, flat(selection[1]))
    assert(target, "[RTS_ADVANCED FAIL] 無剩餘 " .. key .. " 資源；" .. diagnostic())
    send("Order", selection, target)
   end
  end
 end
 local function waitFor(predicate, seconds, label)
  local untilTime = math.min(deadline, os.clock() + seconds)
  repeat
   if predicate() then return end
   if playing then
    assert(workspace:GetAttribute("MatchPhase") == "Playing" and not player:GetAttribute("Defeated"), "[RTS_ADVANCED FAIL] 驗收對局意外結束")
    maintainEconomy()
   end
   if os.clock() - lastReport >= 30 then
    print("[RTS_ADVANCED PROGRESS] " .. label .. "；" .. diagnostic())
    lastReport = os.clock()
   end
   task.wait(0.15)
  until os.clock() >= untilTime
  error("[RTS_ADVANCED FAIL] " .. label .. "等待逾時；" .. diagnostic(), 0)
 end
 local function pauseEconomy()
  paused = true
  local selection = workers()
  if #selection > 0 then
   send("Stop", selection)
   waitFor(function()
    for _, worker in ipairs(selection) do if worker.Parent and worker:GetAttribute("Order") ~= "待命" then return false end end
    return true
   end, 8, "停止採集以隔離成本")
  end
  local before, stableAt = balances(), os.clock()
  waitFor(function()
   local now = balances()
   if not balancesEqual(before, now) then before, stableAt = now, os.clock() end
   return os.clock() - stableAt >= 0.6
  end, 8, "資源複製穩定")
 end
 local function resumeEconomy()
  paused, lastManage = false, 0
  table.clear(assignment)
 end
 local function canAfford(cost)
  for key, amount in pairs(cost) do if (player:GetAttribute(key) or 0) < amount then return false end end
  return true
 end
 local function afford(cost, label)
  for key, amount in pairs(cost) do desired[key] = math.max(desired[key], amount + 25) end
  if not canAfford(cost) then
   resumeEconomy()
   waitFor(function() return canAfford(cost) end, 420, "真實採集交貨補足 " .. label)
  end
  pauseEconomy()
 end
 local function paid(before, cost)
  local expected = table.clone(before)
  for key, amount in pairs(cost) do expected[key] -= amount end
  return balancesEqual(expected, balances())
 end
 local function placement(kind, anchor)
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
  anchor = anchor or home
  local minimum = anchor == home and 64 or 24
  for radius = minimum, minimum + 256, 8 do
   for index = 0, 31 do
    local angle = math.pi / 4 + index * math.pi / 16
    local pos = Grid.snap(anchor + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), data.size)
    if math.abs(pos.X) + data.size.X * g / 2 <= half and math.abs(pos.Z) + data.size.Y * g / 2 <= half
     and (pos - home).Magnitude > 36 + math.max(data.size.X, data.size.Y) * g / 2 then
     local clear = true
     local hits = workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, data.height / 2, 0)), Vector3.new(data.size.X * g - 0.2, math.max(4, data.height), data.size.Y * g - 0.2), params)
     for _, part in ipairs(hits) do
      if part.CanCollide or part:IsDescendantOf(folders.buildings) or part:IsDescendantOf(folders.units) or part:IsDescendantOf(folders.resources) then clear = false; break end
     end
     if clear then return pos end
    end
   end
  end
  error("[RTS_ADVANCED FAIL] 無合法建築位置：" .. data.name, 0)
 end
 local function reject(action, args, label, invariant)
  pauseEconomy()
  local before, count, since = balances(), #owned(folders.buildings), #messages
  send(action, table.unpack(args))
  -- An ordered, rejected normal Build acts as a feedback barrier for silent rejections.
  send("Build", "House", home, {})
  waitFor(function()
   for index = since + 1, #messages do if string.find(messages[index], "先選取自己的村民", 1, true) then return true end end
   return false
  end, 8, label .. "正常遠端回覆屏障")
  local observeUntil = os.clock() + 0.6
  waitFor(function() return os.clock() >= observeUntil end, 3, label .. "複製觀察")
  check(balancesEqual(before, balances()) and #owned(folders.buildings) == count and (not invariant or invariant()), label .. "被拒絕、不扣任何資源")
 end
 local function build(kind, anchor)
  local data = Config.Buildings[kind]
  afford(data.cost, data.name)
  local before, existing = balances(), {}
  for _, model in ipairs(owned(folders.buildings)) do existing[model] = true end
  local selection = workers()
  assert(#selection >= 2, "至少需要兩名真實村民施工")
  selection = { selection[1], selection[2] }
  for _, worker in ipairs(selection) do busy[worker] = true end
  local buildStarted = os.clock()
  send("Build", kind, placement(kind, anchor), selection)
  local site
  waitFor(function()
   for _, model in ipairs(owned(folders.buildings, kind, "BuildingType")) do
    if not existing[model] and model.PrimaryPart then site = model; return true end
   end
   return false
  end, 8, data.name .. "建立工地")
  print("[ADVANCED_GEOMETRY]", kind, site:GetPivot().Position, "workers", #selection)
  waitFor(function() return paid(before, data.cost) end, 8, data.name .. "成本完整複製")
  check(not site:GetAttribute("Complete") and site:GetAttribute("UnderConstruction") == true, data.name .. "建立工地且正確扣款，不能立即完工")
  local observedWork = false
  local workConnection = site:GetAttributeChangedSignal("ConstructionProgress"):Connect(function()
   local progress = site:GetAttribute("ConstructionProgress") or 0
   if (site:GetAttribute("BuilderCount") or 0) > 0 and progress > 0 and progress < 1 then observedWork = true end
  end)
  table.insert(probeConnections, workConnection)
  resumeEconomy()
  waitFor(function()
   local progress = site:GetAttribute("ConstructionProgress") or 0
   if (site:GetAttribute("BuilderCount") or 0) > 0 and progress > 0 and progress < 1 then observedWork = true end
   return site.Parent and site:GetAttribute("Complete") == true and site:GetAttribute("UnderConstruction") == false
  end, data.buildTime + 100, data.name .. "正常行走施工")
  workConnection:Disconnect()
  send("Stop", selection)
  for _, worker in ipairs(selection) do busy[worker], assignment[worker] = nil, nil end
  local minimumDuration = data.buildTime / (1 + (#selection - 1) * Config.Construction.extraWorkerRate)
  check(observedWork and os.clock() - buildStarted >= minimumDuration - 0.5 and site:GetAttribute("ConstructionProgress") == 1 and site:GetAttribute("ConstructionRemaining") == 0, data.name .. "由真實村民按正常施工計時完成")
  builtKinds[kind] = true
  return site
 end
 local function train(building, kind)
  local data = Config.Units[kind]
  afford(data.cost, data.name)
  local before, existing = balances(), {}
  for _, model in ipairs(owned(folders.units, kind, "UnitType")) do existing[model] = true end
  local oldCount = building:GetAttribute("QueueCount") or 0
  assert(oldCount == 0 and building:GetAttribute("Research") == nil, "訓練測試要求空佇列")
  local trainingStarted = os.clock()
  send("Train", building, kind)
  waitFor(function() return (building:GetAttribute("QueueCount") or 0) == oldCount + 1 and paid(before, data.cost) end, 8, data.name .. "排入佇列")
  check(paid(before, data.cost), data.name .. "訓練只扣正常成本")
  local initialRemaining = building:GetAttribute("TrainingRemaining")
  resumeEconomy()
  local unit
  waitFor(function()
   for _, model in ipairs(owned(folders.units, kind, "UnitType")) do if not existing[model] and model.PrimaryPart then unit = model; return true end end
   return false
  end, data.trainTime + 45, data.name .. "真實訓練與出口")
  check(unit:GetAttribute("UnitType") == kind and unit:GetAttribute("OwnerId") == player.UserId, data.name .. "由伺服器生成己方實例")
  return unit, os.clock() - trainingStarted, initialRemaining
 end
 local function advance(building, age)
  local data = Config.Ages[age]
  afford(data.cost, data.name)
  local before = balances()
  local ageStarted = os.clock()
  send("AdvanceAge", building)
  waitFor(function() return building:GetAttribute("Research") == data.name and paid(before, data.cost) end, 8, data.name .. "正常研究開始")
  check(player:GetAttribute("Age") == age - 1 and paid(before, data.cost), data.name .. "成本正確，研究期間時代不提前增加")
  resumeEconomy()
  waitFor(function() return player:GetAttribute("Age") == age and player:GetAttribute("AgeRemaining") == 0 and building:GetAttribute("Research") == nil end, data.time + 15, data.name .. "真實計時完成")
  check(player:GetAttribute("Age") == age and os.clock() - ageStarted >= data.time - 1, data.name .. "完成正常時代計時")
 end
 local function research(building, key)
  local data = Config.Technologies[key]
  afford(data.cost, data.name)
  local before = balances()
  local researchStarted = os.clock()
  send("Research", building, key)
  waitFor(function() return building:GetAttribute("Research") == data.name and paid(before, data.cost) end, 8, data.name .. "研究開始")
  check(player:GetAttribute("Tech_" .. key) ~= true and paid(before, data.cost), data.name .. "扣款且不提前生效")
  resumeEconomy()
  waitFor(function() return player:GetAttribute("Tech_" .. key) == true and building:GetAttribute("Research") == nil end, data.time + 15, data.name .. "真實研究完成")
  researched[key] = true
  check(player:GetAttribute("Tech_" .. key) == true and os.clock() - researchStarted >= data.time - 1, data.name .. "伺服器完成正常研究計時並複製科技狀態")
  reject("Research", { building, key }, data.name .. "重複研究", function() return building:GetAttribute("Research") == nil and player:GetAttribute("Tech_" .. key) == true end)
  resumeEconomy()
 end
 local function gatherProbe(kind, expectedRate, capacity)
  pauseEconomy()
  local worker = workers()[1]
  assert(worker and worker.PrimaryPart, "缺少採集驗收村民")
  if (worker:GetAttribute("Carrying") or 0) > 0 then
   -- Delivery automatically resumes gathering. Stop on the zero-carry transition so
   -- a short camp route cannot refill between polling and the next Stop command.
   local stoppedOnDelivery = false
   local drainConnection = worker:GetAttributeChangedSignal("Carrying"):Connect(function()
    if not stoppedOnDelivery and worker:GetAttribute("Carrying") == 0 then
     stoppedOnDelivery = true
     command:FireServer("Stop", { worker })
     lastSend = os.clock()
    end
   end)
   table.insert(probeConnections, drainConnection)
   send("Order", { worker }, center)
   waitFor(function() return stoppedOnDelivery and worker:GetAttribute("Carrying") == 0 and worker:GetAttribute("Order") == "待命" end, 75, "交回舊攜帶資源並停止採集")
   drainConnection:Disconnect()
  end
  local resource = nearestResource(kind, flat(worker), capacity * 3)
  assert(resource, "沒有足夠的 " .. kind .. " 採集測試資源")
  print("[RTS_ADVANCED_GATHER_GEOMETRY]", kind, "Worker", worker:GetPivot().Position, "Resource", resource:GetPivot().Position, "Amount", resource:GetAttribute("Amount"))
  local oldAmount, oldBalance = resource:GetAttribute("Amount"), player:GetAttribute(kind)
  local firstPositive, peak = nil, 0
  local probeConnection = worker:GetAttributeChangedSignal("Carrying"):Connect(function()
   local value = worker:GetAttribute("Carrying") or 0
   if value > 0 then firstPositive = firstPositive or value; peak = math.max(peak, value) end
  end)
  table.insert(probeConnections, probeConnection)
  send("Order", { worker }, resource)
  waitFor(function() return firstPositive ~= nil end, 75, kind .. "抵達並採集")
  check(approximately(firstPositive, expectedRate) and worker:GetAttribute("CarryType") == kind, kind .. "實際單次採集量符合科技效果")
  waitFor(function() return approximately(peak, capacity) end, 20, kind .. "實際裝滿攜帶量")
  check(resource:GetAttribute("Amount") < oldAmount, kind .. "真實節點資源減少，攜帶上限有效")
  waitFor(function() return (player:GetAttribute(kind) or 0) >= oldBalance + capacity end, 75, kind .. "交回正確資源")
  check((player:GetAttribute("DeliveredResources") or 0) > 0, kind .. "由村民正常交貨增加庫存")
  send("Stop", { worker })
  waitFor(function() return worker:GetAttribute("Order") == "待命" end, 8, "採集測試結束")
  probeConnection:Disconnect()
  resumeEconomy()
 end

 local ok, result = xpcall(function()
  waitFor(function() return workspace:GetAttribute("RTSReady") == true end, 12, "初始化")
  check(#Players:GetPlayers() == 1 and workspace:GetAttribute("MatchPhase") == "Lobby", "只在新單人 Studio 大廳開始，不挪用既有對局")
  print("[RTS_ADVANCED START] 4 時代／18 種建築／11 科技／真實四資源；期限 " .. duration .. " 秒")
  require(RS.Shared.LobbyTests).Start({ expectedPlayers = 1, size = "Small", aiCount = 0, difficulty = "Easy", population = 100, startingResources = "Rich", victory = "Conquest" })
  waitFor(function() return workspace:GetAttribute("MatchPhase") == "Playing" and workspace:GetAttribute("Sandbox") == true and player:GetAttribute("Age") == 1 and typeof(player:GetAttribute("HomePosition")) == "Vector3" end, 20, "單人練習開局")
  playing = true
  folders = { buildings = workspace:WaitForChild("Buildings", 8), units = workspace:WaitForChild("Units", 8), resources = workspace:WaitForChild("Resources", 8) }
  home = player:GetAttribute("HomePosition")
  waitFor(function()
   center = owned(folders.buildings, "TownCenter", "BuildingType")[1]
   return center and center.PrimaryPart and center:GetAttribute("Complete") == true and #workers() == 3
  end, 10, "初始建築與村民複製")
  check(workspace:GetAttribute("AICount") == 0 and player.Character == nil, "沒有 AI 干擾，使用正常無角色 RTS")
  check(player:GetAttribute("food") == 1200 and player:GetAttribute("wood") == 1200 and player:GetAttribute("gold") == 800 and player:GetAttribute("stone") == 600, "使用正式 Rich 開局，沒有增加任何測試資源")
  builtKinds.TownCenter = true
  reject("AdvanceAge", { center }, "初始主城不能代替兩種黑暗時代前置", function() return player:GetAttribute("Age") == 1 and center:GetAttribute("Research") == nil end)
  for _, kind in ipairs(Config.BuildOrder) do
   if Config.Buildings[kind].minAge > 1 then
    reject("Build", { kind, placement(kind), workers() }, Config.Buildings[kind].name .. "時代不足")
   end
  end
  reject("Research", { center, "Wheelbarrow" }, "手推車時代不足", function() return player:GetAttribute("Tech_Wheelbarrow") ~= true and center:GetAttribute("Research") == nil end)
  local mill = build("Mill")
  build("Mill")
  reject("AdvanceAge", { center }, "兩座同類磨坊不是兩種前置", function() return player:GetAttribute("Age") == 1 and center:GetAttribute("Research") == nil end)
  local woodResource = nearestResource("wood", home)
  local goldResource = nearestResource("gold", home)
  local stoneResource = nearestResource("stone", home)
  assert(woodResource and goldResource and stoneResource, "四資源地圖缺少經濟節點")
  local lumber = build("LumberCamp", flat(woodResource))
  build("MiningCamp", flat(goldResource))
  build("MiningCamp", flat(stoneResource))
  local barracks = build("Barracks")
  local farm = build("Farm")
  for _ = 1, 3 do build("House") end
  while #workers() < 16 do train(center, "villager") end
  check(#workers() == 16 and (player:GetAttribute("TrainedVillagers") or 0) >= 13, "經濟使用正常訓練的 16 村民")
  for _, key in ipairs(RESOURCE_KEYS) do gatherProbe(key, Config.Units.villager.gatherRate, Config.Units.villager.carryCapacity) end
  local oldWorker, scout = workers()[1], owned(folders.units, "scout", "UnitType")[1]
  local oldScoutArmor = scout:GetAttribute("Armor")
  research(center, "Loom")
  check(oldWorker:GetAttribute("MaxHP") == Config.Units.villager.hp + Config.Technologies.Loom.effect.hp and oldWorker:GetAttribute("Armor") == Config.Units.villager.armor + Config.Technologies.Loom.effect.armor, "織布機改善現有村民生命／護甲")
  check(scout:GetAttribute("Armor") == oldScoutArmor, "織布機不影響軍隊護甲")
  local infantry = train(barracks, "infantry")
  advance(center, 2)
  reject("AdvanceAge", { center }, "黑暗建築不能充當封建前置", function() return player:GetAttribute("Age") == 2 and center:GetAttribute("Research") == nil end)
  local blacksmith = build("Blacksmith")
  build("Blacksmith")
  reject("AdvanceAge", { center }, "兩座同類兵工廠不是兩種前置", function() return player:GetAttribute("Age") == 2 and center:GetAttribute("Research") == nil end)
  local market = build("Market")
  local archery = build("ArcheryRange")
  local stable = build("Stable")
  build("Tower")
  build("Wall")
  reject("Build", { "Castle", placement("Castle"), workers() }, "封建不能造城堡")
  reject("Train", { stable, "cavalry" }, "封建不能訓練騎士", function() return (stable:GetAttribute("QueueCount") or 0) == 0 end)
  reject("Research", { mill, "HeavyPlow" }, "重犁時代不足", function() return mill:GetAttribute("Research") == nil and player:GetAttribute("Tech_HeavyPlow") ~= true end)
  research(center, "Wheelbarrow")
  check(approximately(oldWorker:GetAttribute("Speed"), Config.Units.villager.speed * (1 + Config.Technologies.Wheelbarrow.effect.speed)), "手推車提升現有村民移速")
  gatherProbe("food", Config.Units.villager.gatherRate * (1 + Config.Technologies.Wheelbarrow.effect.gather), Config.Units.villager.carryCapacity + Config.Technologies.Wheelbarrow.effect.carry)
  research(lumber, "DoubleBitAxe")
  gatherProbe("wood", Config.Units.villager.gatherRate * (1 + Config.Technologies.Wheelbarrow.effect.gather + Config.Technologies.DoubleBitAxe.effect.gatherWood), Config.Units.villager.carryCapacity + Config.Technologies.Wheelbarrow.effect.carry)
  local beforeAttack, beforeArmor, beforeWorkerAttack = infantry:GetAttribute("Attack"), infantry:GetAttribute("Armor"), oldWorker:GetAttribute("Attack")
  research(blacksmith, "Forging")
  check(infantry:GetAttribute("Attack") == beforeAttack + Config.Technologies.Forging.effect.attack and oldWorker:GetAttribute("Attack") == beforeWorkerAttack, "鍛造改善現有軍隊，不改村民攻擊")
  research(blacksmith, "Armor")
  check(infantry:GetAttribute("Armor") == beforeArmor + Config.Technologies.Armor.effect.armor, "鎖甲改善現有軍隊護甲")
  local archer = train(archery, "archer")
  research(blacksmith, "Fletching")
  advance(center, 3)
  reject("AdvanceAge", { center }, "封建建築不能充當城堡前置", function() return player:GetAttribute("Age") == 3 and center:GetAttribute("Research") == nil end)
  reject("Research", { mill, "HeavyPlow" }, "重犁缺少馬軛前置", function() return mill:GetAttribute("Research") == nil and player:GetAttribute("Tech_HeavyPlow") ~= true end)
  pauseEconomy()
  local initialFarmMaximum = farm:GetAttribute("MaxAmount")
  research(mill, "HorseCollar")
  check(farm:GetAttribute("MaxAmount") == initialFarmMaximum + Config.Technologies.HorseCollar.effect.farmCapacity, "馬軛增加現有農田容量")
  research(mill, "HeavyPlow")
  check(farm:GetAttribute("MaxAmount") == initialFarmMaximum + Config.Technologies.HorseCollar.effect.farmCapacity + Config.Technologies.HeavyPlow.effect.farmCapacity, "重犁在前置完成後增加現有農田容量")
  local improvedFarm = build("Farm")
  check(improvedFarm:GetAttribute("MaxAmount") == farm:GetAttribute("MaxAmount"), "新農田繼承已完成的容量科技")
  research(archery, "ThumbRing")
  local university = build("University")
  reject("AdvanceAge", { center }, "一種城堡建築不足帝王前置", function() return player:GetAttribute("Age") == 3 and center:GetAttribute("Research") == nil end)
  reject("Research", { university, "Chemistry" }, "化學時代不足", function() return university:GetAttribute("Research") == nil and player:GetAttribute("Tech_Chemistry") ~= true end)
  local castle = build("Castle")
  reject("Research", { castle, "Conscription" }, "徵兵時代不足", function() return castle:GetAttribute("Research") == nil and player:GetAttribute("Tech_Conscription") ~= true end)
  advance(castle, 4)
  check(player:GetAttribute("Age") == 4, "一座城堡可替代兩種城堡時代前置並升帝王")
  for _, kind in ipairs(Config.BuildOrder) do if not builtKinds[kind] or kind == "TownCenter" then build(kind) end end
  local attackBeforeChemistry = infantry:GetAttribute("Attack")
  research(university, "Chemistry")
  check(infantry:GetAttribute("Attack") == attackBeforeChemistry + Config.Technologies.Chemistry.effect.attack and oldWorker:GetAttribute("Attack") == beforeWorkerAttack, "化學改善現有軍隊，不改村民攻擊")
  research(castle, "Conscription")
  local newInfantry, elapsed, firstRemaining = train(barracks, "infantry")
  local expectedTrainTime = Config.Units.infantry.trainTime * (1 - Config.Technologies.Conscription.effect.trainSpeed)
  check(type(firstRemaining) == "number" and firstRemaining <= math.ceil(expectedTrainTime) and firstRemaining >= math.ceil(expectedTrainTime) - 2 and elapsed >= expectedTrainTime - 2, "徵兵以正常縮短計時完成，不是即時生成")
  check(newInfantry:GetAttribute("Attack") == infantry:GetAttribute("Attack") and newInfantry:GetAttribute("Armor") == infantry:GetAttribute("Armor"), "新軍隊繼承完成的攻擊／護甲科技")
  local newWorker = train(center, "villager")
  check(newWorker:GetAttribute("MaxHP") == oldWorker:GetAttribute("MaxHP") and newWorker:GetAttribute("Armor") == oldWorker:GetAttribute("Armor") and approximately(newWorker:GetAttribute("Speed"), oldWorker:GetAttribute("Speed")), "新村民繼承織布機與手推車")
  local trainedKinds = { villager = true, infantry = true, archer = archer ~= nil }
  for _, kind in ipairs({ "scout", "spearman", "skirmisher", "cavalry", "ram", "mangonel", "trebuchet" }) do
   local buildingKind = Config.Units[kind].trainsAt[1]
   local building = owned(folders.buildings, buildingKind, "BuildingType")[1]
   train(building, kind)
   trainedKinds[kind] = true
  end
  -- 市集價格浮動且所有玩家共用：每次交易前讀伺服器發布的報價。
  local function quote(key,direction) return workspace:GetAttribute((direction=="Buy" and "MarketBuy_" or "MarketSell_")..key) or (direction=="Buy" and Config.MarketTrade.buyGold or Config.MarketTrade.sellGold) end
  afford({ wood = Config.MarketTrade.batch, gold = quote("food","Buy") }, "市集交易")
  local beforeTrade = balances()
  local sellQuote = quote("wood","Sell")
  send("Trade", market, "wood", "Sell")
  waitFor(function() local b = balances(); return approximately(b.wood, beforeTrade.wood - Config.MarketTrade.batch) and approximately(b.gold, beforeTrade.gold + sellQuote) end, 8, "市集真實賣出")
  check(approximately(player:GetAttribute("wood"), beforeTrade.wood - Config.MarketTrade.batch), "市集按正常比例賣出資源")
  local afterSell = balances()
  local buyQuote = quote("food","Buy")
  send("Trade", market, "food", "Buy")
  waitFor(function() local b = balances(); return approximately(b.food, afterSell.food + Config.MarketTrade.batch) and approximately(b.gold, afterSell.gold - buyQuote) end, 8, "市集真實買入")
  check(approximately(player:GetAttribute("food"), afterSell.food + Config.MarketTrade.batch), "市集按正常比例買入資源")
  while (player:GetAttribute("gold") or 0) >= quote("food","Buy") do
   local beforeBuy = balances()
   local price = quote("food","Buy")
   send("Trade", market, "food", "Buy")
   waitFor(function() local b = balances(); return approximately(b.food, beforeBuy.food + Config.MarketTrade.batch) and approximately(b.gold, beforeBuy.gold - price) end, 8, "正常買入以驗證資源不足")
  end
  reject("Trade", { market, "food", "Buy" }, "黃金不足的市集交易")
  for _, kind in ipairs(Config.BuildOrder) do
   local found = false
   for _, building in ipairs(owned(folders.buildings, kind, "BuildingType")) do if building:GetAttribute("Complete") then found = true end end
   check(found, Config.Buildings[kind].name .. "至少一座真正完工")
  end
  for _, key in ipairs(Config.TechnologyOrder) do check(researched[key] and player:GetAttribute("Tech_" .. key) == true, Config.Technologies[key].name .. "正常研究驗收紀錄存在") end
  for kind in pairs(Config.Units) do check(trainedKinds[kind] == true and #owned(folders.units, kind, "UnitType") > 0, Config.Units[kind].name .. "實際單位存在") end
  check(player:GetAttribute("Age") == 4 and workspace:GetAttribute("MatchPhase") == "Playing", "四時代／全建築／全科技完成後沙盒仍正常")
  print("[RTS_ADVANCED UNVERIFIED] 箭羽實際射程、拇指環實際攻擊間隔、研究建築被真實攻擊摧毀的取消／重研、傷害與三勝利規則：須另開雙方對戰，未以本次沙盒代替。")
  print(string.format("[RTS_ADVANCED COMPLETE] %d 項發展引擎檢查；4 時代、18 種建築、11 科技、10 種單位；耗時 %.1f 秒；戰鬥範圍未驗收", checks, os.clock() - started))
  return { checks = checks, elapsed = os.clock() - started, scope = "Development", battleVerified = false }
 end, debug.traceback)
 paused = true
 connection:Disconnect()
 for _, probeConnection in ipairs(probeConnections) do probeConnection:Disconnect() end
 if playing and folders then pcall(function() command:FireServer("Stop", workers()) end) end
 if not ok then error(result, 0) end
 return result
end

function Tests.RunDevelopment(options)
 assert(not Tests.running, "進階驗收正在執行，請勿重複呼叫")
 Tests.running = true
 local ok, result = pcall(development, options)
 Tests.running = false
 if not ok then error(result, 0) end
 return result
end

Tests.Run = Tests.RunDevelopment
return Tests
