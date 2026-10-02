-- Studio 客戶端整合測試；require 不會執行。請在全新單人大廳明確呼叫 Run()。
-- 使用正常集合、設定、準備、開局與建造／採集指令；會改變這一局的資源與建築。
-- 本測試未驗證礦脈耗盡、交貨建築被摧毀或未知 Studio 模型的採集相容性。
local RunService = game:GetService("RunService")
local Tests = {running = false}

local function run()
 assert(RunService:IsStudio() and RunService:IsClient(), "只能在 Studio Play 客戶端明確呼叫")
 assert(workspace:GetAttribute("MatchPhase") == "Lobby", "請在全新大廳開始採集驗證")
 local Players = game:GetService("Players")
 assert(#Players:GetPlayers() == 1, "採集驗證需要全新單人工作階段")
 local RS = game:GetService("ReplicatedStorage")
 local player = Players.LocalPlayer
 local Config = require(RS.GameData.GameConfig)
 local Grid = require(RS.Shared.Grid)
 local command, feedback = RS.RTSRemotes.Command, RS.RTSRemotes.Feedback
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local deadline, checks = os.clock() + 240, 0
 local workers, messages = {}, {}
 local connection = feedback.OnClientEvent:Connect(function(message)
  table.insert(messages, tostring(message))
 end)
 local function check(condition, message)
  assert(condition, "[ECONOMY_TEST FAIL] " .. message)
  checks += 1
  print("[ECONOMY_TEST PASS] " .. message)
 end
 local function waitFor(predicate, seconds, message, inspect)
  local untilTime = math.min(deadline, os.clock() + seconds)
  repeat
   assert(os.clock() < deadline, "[ECONOMY_TEST FAIL] 全程超過 240 秒")
   if inspect then inspect() end
   if predicate() then check(true, message); return end
   task.wait(0.05)
  until os.clock() >= untilTime
  check(false, message .. "；等待逾時；最近回覆：" .. (messages[#messages] or "無"))
 end
 local function flat(model)
  local pos = model:GetPivot().Position
  return Vector3.new(pos.X, Config.Map.GroundY, pos.Z)
 end
 local function edgeDistance(model, pos)
  local center = flat(model)
  local half = model.PrimaryPart and model.PrimaryPart.Size / 2 or Vector3.new(2, 2, 2)
  local nearest = Vector3.new(math.clamp(pos.X, center.X-half.X, center.X+half.X),
   Config.Map.GroundY, math.clamp(pos.Z, center.Z-half.Z, center.Z+half.Z))
  return (pos-nearest).Magnitude
 end
 local function ownModels(folder, kind, attribute)
  local result = {}
  for _,model in ipairs(folder:GetChildren()) do
   if model:GetAttribute("OwnerId") == player.UserId and
    (not kind or model:GetAttribute(attribute) == kind) then table.insert(result, model) end
  end
  return result
 end
 local function stopWorkers()
  if #workers > 0 then command:FireServer("Stop", workers) end
 end
 local ok, result = xpcall(function()
  waitFor(function()
   return player.Character and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
  end, 15, "大廳角色載入")
  player.Character:PivotTo(CFrame.new(Config.Lobby.origin+Config.Lobby.portalOffset+Vector3.new(0,4,0)))
  command:FireServer("QueueJoin")
  waitFor(function() return player:GetAttribute("LobbyQueued") == true end, 8, "走入集合傳送門")
  waitFor(function() return workspace:GetAttribute("HostUserId") == player.UserId end, 5,
   "單人集合玩家成為房主")
  local settings = {expectedPlayers=1, size="Small", aiCount=0, difficulty="Easy",
   population=100, startingResources="Rich", victory="Conquest"}
  local revision = workspace:GetAttribute("LobbySettingsRevision")
  command:FireServer("LobbySettings", settings)
  waitFor(function()
   if workspace:GetAttribute("LobbySettingsRevision") == revision then return false end
   if workspace:GetAttribute("LobbyExpectedPlayers") ~= settings.expectedPlayers then return false end
   for key,value in pairs(settings) do
    if key ~= "expectedPlayers" and workspace:GetAttribute("LobbySetting_" .. key) ~= value then return false end
   end
   return true
  end, 8, "小型、豐富資源、零 AI 與一位真人設定同步")
  command:FireServer("LobbyReady", true, workspace:GetAttribute("LobbySettingsRevision"))
  waitFor(function() return player:GetAttribute("LobbyReady") == true end, 8, "確認目前設定並準備")
  command:FireServer("StartMatch")
  waitFor(function() return workspace:GetAttribute("MatchPhase") == "Playing" end, 15, "由大廳正常開局")
  local buildings, units, resources = workspace.Buildings, workspace.Units, workspace.Resources
  local center
  local rich = Config.StartingResources and Config.StartingResources.Rich or
   {food=1200, wood=1200, gold=800, stone=600}
  waitFor(function()
   workers = ownModels(units, "villager", "UnitType")
   center = ownModels(buildings, "TownCenter", "BuildingType")[1]
   if workspace:GetAttribute("MatchSizeName") ~= "Small" or workspace:GetAttribute("Sandbox") ~= true or
    workspace:GetAttribute("StartingResources") ~= "Rich" or workspace:GetAttribute("VictoryMode") ~= "Conquest" or
    workspace:GetAttribute("FactionCount") ~= 1 or not (center and center.PrimaryPart) or #workers < 3 then return false end
   for _,worker in ipairs(workers) do if not worker.PrimaryPart then return false end end
   for key,value in pairs(rich) do if player:GetAttribute(key) ~= value then return false end end
   return true
  end, 10, "小型單人沙盒、豐富庫存、市鎮中心與三位初始村民同步")
  local capacity = Config.Units.villager.carryCapacity
  check(capacity == 10, "未研究手推車的初始村民攜帶上限為 10")
  stopWorkers()
  waitFor(function()
   for _,worker in ipairs(workers) do if worker:GetAttribute("Order") ~= "待命" then return false end end
   return true
  end, 5, "其餘村民停止以隔離資源收入")
  local function nearbyResource(key)
   local nearest, distance = nil, math.huge
   for _,node in ipairs(resources:GetChildren()) do
    if node:GetAttribute("RTSManagedResource") == true and node:GetAttribute("ResourceType") == key and
     (node:GetAttribute("Amount") or 0) >= 60 then
     local candidate = (flat(node)-flat(center)).Magnitude
     if candidate < distance then nearest, distance = node, candidate end
    end
   end
   return nearest
  end
  local gold, stone
  waitFor(function()
   gold, stone = nearbyResource("gold"), nearbyResource("stone")
   return gold and stone and gold.PrimaryPart and stone.PrimaryPart
  end, 10, "足量的金礦與石礦同步到客戶端")
  local function location(node)
   local data, anchor = Config.Buildings.MiningCamp, flat(node)
   local params = OverlapParams.new()
   params.FilterType = Enum.RaycastFilterType.Exclude
   local excluded = {}
   for _,name in ipairs({"AOE2_Ground", "RTSScenery"}) do
    local item = workspace:FindFirstChild(name)
    if item then table.insert(excluded, item) end
   end
   params.FilterDescendantsInstances = excluded
   local mapHalf = (workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
   for radius=32,72,8 do
    for index=0,31 do
     local angle = index*math.pi/16
     local pos = Grid.snap(anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius), data.size)
     if math.abs(pos.X)+data.size.X*Config.Map.GridSize/2 <= mapHalf and
      math.abs(pos.Z)+data.size.Y*Config.Map.GridSize/2 <= mapHalf and
      (pos-anchor).Magnitude+24 < edgeDistance(center, anchor) then
      local clear = true
      local hits = workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),
       Vector3.new(data.size.X*Config.Map.GridSize-.2,math.max(4,data.height),data.size.Y*Config.Map.GridSize-.2), params)
      for _,part in ipairs(hits) do
       if part.CanCollide or part:IsDescendantOf(buildings) or part:IsDescendantOf(units) or
        part:IsDescendantOf(resources) then clear = false; break end
      end
      if clear then return pos end
     end
    end
   end
   error("[ECONOMY_TEST FAIL] 找不到靠近礦脈且比市鎮中心近的合法營地位置")
  end
  local function buildCamp(node, label)
   local old = {}
   for _,model in ipairs(ownModels(buildings, "MiningCamp", "BuildingType")) do old[model] = true end
   local wood = player:GetAttribute("wood")
   command:FireServer("Build", "MiningCamp", location(node), workers)
   local camp
   waitFor(function()
    for _,model in ipairs(ownModels(buildings, "MiningCamp", "BuildingType")) do
     if not old[model] then camp = model; return true end
    end
    return false
   end, 6, label .. "採礦營地建立正常工地")
   waitFor(function()
    return player:GetAttribute("wood") == wood-Config.Buildings.MiningCamp.cost.wood and
     camp.PrimaryPart ~= nil and camp:GetAttribute("Complete") == false and
     type(camp:GetAttribute("ConstructionProgress")) == "number"
   end, 5, label .. "未完工工地與正常扣款同步")
   -- 工地與村民位置分開複製；發現工地時村民可能已抵達，不能強求當下進度為零。
   waitFor(function()
    if (camp:GetAttribute("ConstructionProgress") or 0) <= 0 or
     (camp:GetAttribute("BuilderCount") or 0) <= 0 then return false end
    for _,worker in ipairs(workers) do
     if worker:GetAttribute("Order") == "施工" and
      edgeDistance(camp, flat(worker)) <= Config.Construction.workRange+2 then return true end
    end
    return false
   end, 50, label .. "施工進度由實際到場村民推進")
   waitFor(function() return camp:GetAttribute("Complete") == true end, Config.Buildings.MiningCamp.buildTime+8,
    label .. "營地由村民完工")
   stopWorkers()
   waitFor(function()
    for _,worker in ipairs(workers) do if worker:GetAttribute("Order") ~= "待命" then return false end end
    return true
   end, 5, label .. "施工後停止所有村民")
   check(edgeDistance(camp, flat(node))+24 < edgeDistance(center, flat(node)), label .. "新營地比市鎮中心更靠近礦脈")
   return camp
  end
  local goldCamp = buildCamp(gold, "金礦")
  local stoneCamp = buildCamp(stone, "石礦")
  local function verifyCycles(worker, node, camp, key, label)
   local startStock, startAmount = player:GetAttribute(key), node:GetAttribute("Amount")
   command:FireServer("Order", {worker}, node)
   local function inspect()
    local carrying = worker:GetAttribute("Carrying") or 0
    assert(carrying >= 0 and carrying <= capacity, "[ECONOMY_TEST FAIL] " .. label .. "超過攜帶上限")
    assert((player:GetAttribute(key) or 0) >= startStock, "[ECONOMY_TEST FAIL] " .. label .. "庫存異常下降")
   end
   for cycle=1,2 do
    local stock = startStock+(cycle-1)*capacity
    waitFor(function()
     return (worker:GetAttribute("Carrying") or 0) > 0 and worker:GetAttribute("Order") == "採集" and
      worker:GetAttribute("CarryType") == key and player:GetAttribute(key) == stock
    end, 40, label .. "第 " .. cycle .. " 輪攜帶礦石、庫存尚未增加", inspect)
    waitFor(function()
     return worker:GetAttribute("Carrying") == capacity and worker:GetAttribute("Order") == "交貨" and
      worker:GetAttribute("CarryType") == key and player:GetAttribute(key) == stock
    end, 15, label .. "裝滿 10 單位後自動交貨，途中尚未增加庫存", inspect)
    waitFor(function()
     return player:GetAttribute(key) == stock+capacity and worker:GetAttribute("Carrying") == 0 and
      edgeDistance(camp, flat(worker)) <= 6
    end, 25, label .. "在新營地交貨增加 10 庫存並清空攜帶量", inspect)
   end
   waitFor(function()
    return (worker:GetAttribute("Carrying") or 0) > 0 and worker:GetAttribute("Order") == "採集" and
     worker:GetAttribute("CarryType") == key and player:GetAttribute(key) == startStock+2*capacity and
     node:GetAttribute("Amount") < startAmount-2*capacity
   end, 25, label .. "兩輪資源來自礦脈，交貨後自動繼續第三輪", inspect)
   command:FireServer("Stop", {worker})
   waitFor(function()
    return worker:GetAttribute("Order") == "待命" and worker:GetAttribute("CarryType") == key and
     (worker:GetAttribute("Carrying") or 0) > 0 and player:GetAttribute(key) == startStock+2*capacity
   end, 5, label .. "停止工人並同步剩餘攜帶量", inspect)
  end
  verifyCycles(workers[1], gold, goldCamp, "gold", "黃金")
  verifyCycles(workers[2], stone, stoneCamp, "stone", "石材")
  local switchWorker = workers[1]
  local oldCarry = switchWorker:GetAttribute("Carrying")
  local oldGold, oldStone = player:GetAttribute("gold"), player:GetAttribute("stone")
  check(oldCarry > 0 and switchWorker:GetAttribute("CarryType") == "gold", "切換測試保留實際採得的黃金")
  command:FireServer("Order", {switchWorker}, stone)
  local function inspectSwitch()
   local carrying = switchWorker:GetAttribute("Carrying") or 0
   assert(carrying >= 0 and carrying <= capacity, "[ECONOMY_TEST FAIL] 切換資源超過攜帶上限")
  end
  waitFor(function()
   return switchWorker:GetAttribute("Order") == "交貨" and switchWorker:GetAttribute("CarryType") == "gold" and
    switchWorker:GetAttribute("Carrying") == oldCarry and player:GetAttribute("gold") == oldGold and
    player:GetAttribute("stone") == oldStone
  end, 5, "金轉石保留舊黃金並先交貨，不把黃金改成石材", inspectSwitch)
  waitFor(function()
   return player:GetAttribute("gold") == oldGold+oldCarry and switchWorker:GetAttribute("Carrying") == 0 and
    player:GetAttribute("stone") == oldStone
  end, 25, "切換前的黃金按原種類交貨，石庫存不增加", inspectSwitch)
  waitFor(function()
   return switchWorker:GetAttribute("CarryType") == "stone" and (switchWorker:GetAttribute("Carrying") or 0) > 0 and
    player:GetAttribute("gold") == oldGold+oldCarry and player:GetAttribute("stone") == oldStone
  end, 40, "交回舊黃金後自動採石，維持原金庫存與攜帶上限", inspectSwitch)
  stopWorkers()
  waitFor(function()
   for _,worker in ipairs(workers) do if worker:GetAttribute("Order") ~= "待命" then return false end end
   return true
  end, 5, "測試結束停止所有村民")
  print(string.format("[ECONOMY_TEST COMPLETE] %d 項採集與交貨檢查通過；未涵蓋礦脈耗盡或營地被摧毀", checks))
  return checks
 end, debug.traceback)
 if not ok then stopWorkers() end
 connection:Disconnect()
 if not ok then error(result, 0) end
 return result
end

function Tests.Run()
 assert(not Tests.running, "採集驗證已在執行")
 Tests.running = true
 local ok, result = pcall(run)
 Tests.running = false
 if not ok then error(result, 0) end
 return result
end
return Tests
