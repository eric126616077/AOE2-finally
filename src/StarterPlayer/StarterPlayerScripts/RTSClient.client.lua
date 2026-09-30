local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local UI = require(StarterGui:WaitForChild("GameUI"):WaitForChild("GUIManager"))
local Building = require(RS.Shared.BuildingController)
local Config = require(RS.GameData.GameConfig)
local remotes = RS:WaitForChild("RTSRemotes")
local command, feedback = remotes:WaitForChild("Command"), remotes:WaitForChild("Feedback")
local selected, highlights, groups = {}, {}, {}
local dragStart, lastClick, lastClickTime, lastGroup, lastGroupTime
local idleIndex = 0
local function playable()
 return workspace:GetAttribute("MatchPhase") == "Playing" and not player:GetAttribute("Defeated") and not player:GetAttribute("Spectator")
end
local function ownedUnits()
 local result = {}
 for _, model in ipairs(selected) do
  if model.Parent == workspace:FindFirstChild("Units") and model:GetAttribute("OwnerId") == player.UserId then table.insert(result, model) end
 end
 return result
end
local function clearDrag()
 dragStart = nil
 if UI.selectionBox then UI.selectionBox.Visible = false end
end
local function selectModels(models)
 for _, highlight in ipairs(highlights) do highlight:Destroy() end
 highlights, selected = {}, {}
 local seen = {}
 for _, model in ipairs(models) do
  if model.Parent and not seen[model] then seen[model] = true; table.insert(selected, model) end
 end
 for _, model in ipairs(selected) do
  local highlight = Instance.new("Highlight")
  highlight.Adornee = model
  highlight.FillTransparency = 0.94
  highlight.OutlineTransparency = 0.1
  highlight.OutlineColor = model:GetAttribute("OwnerId") == player.UserId and Color3.fromRGB(155,216,146) or Color3.fromRGB(239,202,117)
  highlight.DepthMode = Enum.HighlightDepthMode.Occluded
  highlight.Parent = model
  table.insert(highlights, highlight)
 end
 local model = selected[1]
 local kind = model and model:GetAttribute("BuildingType")
 if model and model:GetAttribute("OwnerId") == player.UserId and kind then
  local data = Config.Buildings[kind]
  UI:SetTab(data and data.trains and #data.trains > 0 and "train" or "research")
 elseif not model or model:GetAttribute("UnitType") then UI:SetTab("build") end
 UI:Update(selected, Building.kind)
end
local function train(kind)
 local model = selected[1]
 if playable() and model and model:GetAttribute("OwnerId") == player.UserId and model:GetAttribute("BuildingType") then
  command:FireServer("Train", model, kind)
 end
end
local function research(key)
 local model = selected[1]
 if playable() and model and model:GetAttribute("OwnerId") == player.UserId then command:FireServer("Research", model, key) end
end
local function advanceAge()
 local model = selected[1]
 if playable() and model and model:GetAttribute("OwnerId") == player.UserId then command:FireServer("AdvanceAge", model) end
end
local function stop()
 if playable() then command:FireServer("Stop", ownedUnits()) end
end
UI:Init({
 build = function(kind)
  if not playable() then return end
  clearDrag(); UI:SetTab("build")
  local ok,message = Building:Begin(kind)
  if not ok then UI:Notify(message) end
 end,
 train = train, research = research, age = advanceAge, stop = stop,
 trade = function(key,direction)
  local model = selected[1]
  if playable() and model and model:GetAttribute("OwnerId") == player.UserId then command:FireServer("Trade",model,key,direction) end
 end,
 start = function(settings) command:FireServer("StartMatch", settings) end,
 surrender = function() if playable() then command:FireServer("Surrender") end end,
 restart = function() command:FireServer("RestartMatch") end,
})
feedback.OnClientEvent:Connect(function(message) UI:Notify(message) end)
pcall(function()
 StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
 StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)
local function pointer() return UIS:GetMouseLocation() - GuiService:GetGuiInset() end
local function groundPoint()
 local ground = workspace:FindFirstChild("AOE2_Ground")
 if not ground then return nil end
 local params = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances = {ground}
 local ray = mouse.UnitRay
 local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
 return result and result.Position
end
local function targetModel()
 local target = mouse.Target
 while target and target ~= workspace do
  if target:IsA("Model") and (target:GetAttribute("BuildingType") or target:GetAttribute("UnitType") or target:GetAttribute("ResourceType")) then return target end
  target = target.Parent
 end
 return nil
end
local function allOwned(kind, visibleOnly)
 local models, folder = {}, workspace:FindFirstChild("Units")
 if folder then
  for _, unit in ipairs(folder:GetChildren()) do
   if unit:GetAttribute("OwnerId") == player.UserId and (not kind or unit:GetAttribute("UnitType") == kind) then
    local _, visible = workspace.CurrentCamera:WorldToScreenPoint(unit:GetPivot().Position)
    if not visibleOnly or visible then table.insert(models, unit) end
   end
  end
 end
 return models
end
local function selectIdle()
 local idle = {}
 for _, unit in ipairs(allOwned("villager")) do
  if not unit:GetAttribute("Order") or unit:GetAttribute("Order") == "待命" then table.insert(idle, unit) end
 end
 if #idle == 0 then UI:Notify("沒有閒置村民。") return end
 idleIndex = idleIndex % #idle + 1
 selectModels({idle[idleIndex]})
 player:SetAttribute("CameraFocus", idle[idleIndex]:GetPivot().Position)
end
local function selectHome()
 local folder = workspace:FindFirstChild("Buildings")
 local home = player:GetAttribute("HomePosition") or Vector3.zero
 local best, distance = nil, math.huge
 if folder then
  for _, model in ipairs(folder:GetChildren()) do
   if model:GetAttribute("OwnerId") == player.UserId and model:GetAttribute("BuildingType") == "TownCenter" then
    local value = (model:GetPivot().Position - home).Magnitude
    if value < distance then best, distance = model, value end
   end
  end
 end
 if best then selectModels({best}); player:SetAttribute("CameraFocus", best:GetPivot().Position) end
end
local numberKeys = {[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
 [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
 [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9}
UIS.InputBegan:Connect(function(input, processed)
 if input.KeyCode == Enum.KeyCode.Escape then
  Building:Cancel(); clearDrag()
  if UI.menuPanel.Visible then UI.menuPanel.Visible = false end
  return
 end
 if processed or UIS:GetFocusedTextBox() or UI:IsModalOpen() then return end
 local group = numberKeys[input.KeyCode]
 if group then
  if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then
   groups[group] = table.clone(ownedUnits()); UI:Notify("編隊 " .. group .. "：" .. #groups[group] .. " 個單位")
  else
   local alive = {}
   for _, model in ipairs(groups[group] or {}) do if model.Parent and model:GetAttribute("OwnerId") == player.UserId then table.insert(alive, model) end end
   selectModels(alive)
   if lastGroup == group and os.clock() - (lastGroupTime or 0) < 0.4 and alive[1] then player:SetAttribute("CameraFocus", alive[1]:GetPivot().Position) end
   lastGroup, lastGroupTime = group, os.clock()
  end
 elseif input.KeyCode == Enum.KeyCode.B then Building:Cancel(); UI:SetTab("build")
 elseif input.KeyCode == Enum.KeyCode.T then UI:SetTab("train"); UI:DefaultTrain()
 elseif input.KeyCode == Enum.KeyCode.R then UI:SetTab("research")
 elseif input.KeyCode == Enum.KeyCode.U then advanceAge()
 elseif input.KeyCode == Enum.KeyCode.X then stop()
 elseif input.KeyCode == Enum.KeyCode.V then selectModels(allOwned("villager"))
 elseif input.KeyCode == Enum.KeyCode.H then selectHome()
 elseif input.KeyCode == Enum.KeyCode.Period then selectIdle()
 elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not UI:BlocksPointer() then
  if Building.kind then
   Building:Update(groundPoint())
   if Building.valid and playable() then
    command:FireServer("Build", Building.kind, Building.position)
    if not UIS:IsKeyDown(Enum.KeyCode.LeftShift) and not UIS:IsKeyDown(Enum.KeyCode.RightShift) then Building:Cancel() end
   else UI:Notify(Building.reason or "無法建造：請確認資源、村民距離及占地。") end
  else dragStart = pointer() end
 elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not UI:BlocksPointer() then
  if Building.kind then Building:Cancel(); return end
  if not playable() then return end
  local units = ownedUnits()
  if #units == 0 then UI:Notify("先選取自己的村民或軍隊，再按右鍵下令。") return end
  local target = targetModel() or groundPoint()
  if target then command:FireServer("Order", units, target) end
 end
end)
UIS.InputEnded:Connect(function(input)
 if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not dragStart then return end
 local start = dragStart; clearDrag()
 if UI:BlocksPointer() or UI:IsModalOpen() then return end
 local finish = pointer()
 if (finish - start).Magnitude > 8 then
  local models = (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) and ownedUnits() or {}
  for _, unit in ipairs(allOwned(nil, true)) do
   local point = workspace.CurrentCamera:WorldToScreenPoint(unit:GetPivot().Position)
   if point.X >= math.min(start.X, finish.X) and point.X <= math.max(start.X, finish.X)
    and point.Y >= math.min(start.Y, finish.Y) and point.Y <= math.max(start.Y, finish.Y) then table.insert(models, unit) end
  end
  selectModels(models)
 else
  local target = targetModel()
  if (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) and target and target:GetAttribute("UnitType") and target:GetAttribute("OwnerId") == player.UserId then
   local models = ownedUnits(); local index = table.find(models, target)
   if index then table.remove(models, index) else table.insert(models, target) end
   selectModels(models)
  elseif target and target == lastClick and os.clock() - (lastClickTime or 0) < 0.32 and target:GetAttribute("UnitType") and target:GetAttribute("OwnerId") == player.UserId then
   selectModels(allOwned(target:GetAttribute("UnitType"), true))
  else selectModels(target and {target} or {}) end
  lastClick, lastClickTime = target, os.clock()
 end
end)
UIS.WindowFocusReleased:Connect(clearDrag)
workspace:GetAttributeChangedSignal("MatchPhase"):Connect(function()
 Building:Cancel(); clearDrag(); selectModels({})
 if workspace:GetAttribute("MatchPhase") == "Lobby" then table.clear(groups) end
end)
for _,attribute in ipairs({"Defeated","Spectator"}) do
 player:GetAttributeChangedSignal(attribute):Connect(function()
  if player:GetAttribute(attribute) then Building:Cancel(); clearDrag(); selectModels({}) end
 end)
end
local updateTime, mapTime = 0, 0
RunService.RenderStepped:Connect(function(dt)
 if Building.kind then Building:Update(not UI:BlocksPointer() and groundPoint() or nil) end
 if dragStart then
  local finish = pointer()
  UI.selectionBox.Visible = (finish - dragStart).Magnitude > 8
  UI.selectionBox.Position = UDim2.fromOffset(math.min(finish.X, dragStart.X), math.min(finish.Y, dragStart.Y))
  UI.selectionBox.Size = UDim2.fromOffset(math.abs(finish.X - dragStart.X), math.abs(finish.Y - dragStart.Y))
 end
 updateTime += dt; mapTime += dt
 if updateTime >= 0.15 then
  updateTime = 0
  local alive = {}; for _, model in ipairs(selected) do if model.Parent then table.insert(alive, model) end end
  if #alive ~= #selected then selectModels(alive) end
  UI:Update(selected, Building.kind)
 end
 if mapTime >= 0.6 then mapTime = 0; UI:UpdateMap() end
end)
