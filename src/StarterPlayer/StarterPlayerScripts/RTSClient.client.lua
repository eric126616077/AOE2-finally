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
local TouchRules = require(RS.Shared.TouchRules)
local CameraFocus = require(RS.Shared.CameraFocus)
local Audio = require(RS.Shared.AudioFeedback)
local TeamClient = require(RS.Shared.TeamClientRules)
local ClientUnitView = require(RS.Shared.ClientUnitView)
local Art = require(RS.Shared.Art)
local CursorRules = require(RS.Shared.CursorRules)
local CursorView = require(RS.Shared.CursorView)
local OrderMarkers = require(RS.Shared.OrderMarkers)
local SelectionRules = require(RS.Shared.SelectionRules)
local HotkeyRules = require(RS.Shared.HotkeyRules)
local remotes = RS:WaitForChild("RTSRemotes")
local command, feedback = remotes:WaitForChild("Command"), remotes:WaitForChild("Feedback")
local selected, highlights, groups = {}, {}, {}
-- Roblox draws only a limited number of Highlights at once. Larger armies rely
-- on the ground rings, so every selected unit stays visibly marked.
local HIGHLIGHT_LIMIT = 24
local rings, ringFolder = {}, nil
local ringTilt = CFrame.Angles(0,0,math.pi/2)
local function addRing(model,color)
 if not ringFolder or not ringFolder.Parent then
  ringFolder = Instance.new("Folder"); ringFolder.Name = "RTSSelectionRings"; ringFolder.Parent = workspace
 end
 local root = model.PrimaryPart
 local diameter = root and math.max(root.Size.X,root.Size.Z)+1.6 or 4.6
 local part = Instance.new("Part")
 part.Name, part.Shape, part.Size = "SelectionRing", Enum.PartType.Cylinder, Vector3.new(0.1,diameter,diameter)
 part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
 part.Material, part.Color, part.Transparency = Enum.Material.SmoothPlastic, color, 0.55
 part.Parent = ringFolder
 table.insert(rings,{model=model,part=part})
end
local dragStart, lastClick, lastClickTime, lastGroup, lastGroupTime
local idleIndex = 0
local selectIdle, selectHome, allOwned
local touches = TouchRules.new()
local lastTouchTime = -math.huge
player:SetAttribute("RTSInputMode", UIS.TouchEnabled and not UIS.MouseEnabled and "Touch" or "Mouse")
player:SetAttribute("RTSTouchMode", "select")
player:SetAttribute("RTSRallyPlacement", false)
player:SetAttribute("RTSGarrisonPlacement", false)
-- 集合點與駐紮都是「下一次點擊選目標」的模式，任何取消路徑一起清除。
local function clearRallyPlacement()
 player:SetAttribute("RTSRallyPlacement", false)
 player:SetAttribute("RTSGarrisonPlacement", false)
end
local function playable()
 return workspace:GetAttribute("MatchPhase") == "Playing" and player:GetAttribute("InLobby")~=true and not player:GetAttribute("Defeated") and not player:GetAttribute("Spectator")
end
local function relation(model)
 return TeamClient.Relation(workspace:GetAttribute("TeamMode") or "FFA",player.UserId,player:GetAttribute("TeamId"),model:GetAttribute("OwnerId"),model:GetAttribute("TeamId"))
end
-- Visual intent only; the server independently validates ownership and teams.
-- Pending replication is never guessed as hostile, including desktop right click.
local function rejectFriendlyTarget(target)
 if typeof(target)~="Instance" then return false end
 local kind=relation(target)
 if kind=="ally" then
  UI:Notify("友方不可攻擊；各自管理自己的資源與單位。")
  return true
 elseif kind=="unresolved" then
  UI:Notify("隊伍資料載入中，請稍後再下令。")
  return true
 end
 return false
end
-- 自己已完工、可駐紮的建築；是否收容仍由伺服器決定。
local function garrisonBuilding(target)
 return typeof(target)=="Instance" and target:GetAttribute("BuildingType")~=nil and target:GetAttribute("OwnerId")==player.UserId
  and target:GetAttribute("Complete")==true and (target:GetAttribute("GarrisonCapacity") or 0)>0
end
-- Immediate, local acknowledgement of an order: a ground ring or a target flash,
-- plus the intent that picks the confirmation sound. The server still decides;
-- its accepted-order cue is what actually plays the sound.
local function orderFeedback(units,target,garrison)
 local villagers,military=0,0
 for _,unit in ipairs(units) do
  if unit:GetAttribute("UnitType")=="villager" then villagers+=1 else military+=1 end
 end
 local walk=military>0 and villagers==0 and "military" or "move"
 if typeof(target)=="Vector3" then
  Audio:SetOrderIntent(walk)
  OrderMarkers:Ground(target,"move")
  return
 end
 if typeof(target)~="Instance" then return end
 local kind=relation(target)
 local ownerId=target:GetAttribute("OwnerId")
 if kind=="enemy" and (target:GetAttribute("UnitType") or target:GetAttribute("BuildingType")) then
  Audio:SetOrderIntent("attack"); OrderMarkers:Target(target,"attack")
 elseif villagers>0 and target:GetAttribute("BuildingType") and kind=="own" and target:GetAttribute("Complete")==false then
  Audio:SetOrderIntent("move"); OrderMarkers:Target(target,"build")
 elseif villagers>0 and target:GetAttribute("ResourceType") and (ownerId==nil or ownerId==player.UserId) then
  Audio:SetOrderIntent("gather"); OrderMarkers:Target(target,"gather")
 elseif (villagers>0 and target:GetAttribute("BuildingType") and kind=="own") or (garrison==true and garrisonBuilding(target)) then
  Audio:SetOrderIntent("move"); OrderMarkers:Target(target,"build")
 else
  Audio:SetOrderIntent(walk); OrderMarkers:Ground(target:GetPivot().Position,"move")
 end
end
local function ownedUnits()
 local result = {}
 for _, model in ipairs(selected) do
  if model.Parent == workspace:FindFirstChild("Units") and model:GetAttribute("OwnerId") == player.UserId then table.insert(result, model) end
 end
 return result
end
-- Pooled screen brackets marking the units a drag box would select on release.
local previewMarks = {}
local function showPreview(rects)
 for index, rect in ipairs(rects) do
  local mark = previewMarks[index]
  if not mark then
   mark = Instance.new("Frame")
   mark.Name, mark.BackgroundTransparency, mark.BorderSizePixel, mark.ZIndex = "SelectionPreview", 1, 0, 7
   local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,5); corner.Parent = mark
   local stroke = Instance.new("UIStroke"); stroke.Color, stroke.Thickness, stroke.Transparency = Color3.fromRGB(190,236,170), 1.5, 0.15; stroke.Parent = mark
   mark.Parent = UI.screen
   previewMarks[index] = mark
  end
  mark.Position = UDim2.fromOffset(rect.left,rect.top)
  mark.Size = UDim2.fromOffset(rect.right-rect.left,rect.bottom-rect.top)
  mark.Visible = true
 end
 for index = #rects+1, #previewMarks do previewMarks[index].Visible = false end
end
local function clearDrag()
 dragStart = nil
 if UI.selectionBox then UI.selectionBox.Visible = false end
 for _, mark in ipairs(previewMarks) do mark.Visible = false end
end
local function selectModels(models)
 Building:Cancel()
 clearRallyPlacement()
 if UI.CancelDelete then UI:CancelDelete() end
 player:SetAttribute("RTSTouchMode", "select")
 for _, highlight in ipairs(highlights) do highlight:Destroy() end
 for _, ring in ipairs(rings) do ring.part:Destroy() end
 highlights, selected, rings = {}, {}, {}
 local seen = {}
 for _, model in ipairs(models) do
  if model.Parent and not seen[model] then seen[model] = true; table.insert(selected, model) end
 end
 if #selected>0 then Audio:Play("Select",selected[1]) end
 for index, model in ipairs(selected) do
  local kind=relation(model)
  local color = kind=="own" and Color3.fromRGB(155,216,146) or kind=="ally" and Color3.fromRGB(118,210,211) or Color3.fromRGB(239,202,117)
  if index <= HIGHLIGHT_LIMIT then
   local highlight = Instance.new("Highlight")
   highlight.Adornee = model
   highlight.FillTransparency = 0.94
   highlight.OutlineTransparency = 0.1
   highlight.OutlineColor = color
   highlight.DepthMode = Enum.HighlightDepthMode.Occluded
   highlight.Parent = model
   table.insert(highlights, highlight)
  end
  if model:GetAttribute("UnitType") then addRing(model,color) end
 end
 local model = selected[1]
 if model and relation(model)=="ally" then UI:Notify("盟友 · 友方不可攻擊；各自管理自己的資源與單位。") end
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
local function farmQueue(add)
 local model = selected[1]
 if playable() and model and model:GetAttribute("OwnerId") == player.UserId and model:GetAttribute("BuildingType") == "Mill" then
  command:FireServer(add and "QueueFarm" or "UnqueueFarm", model)
 end
end
local function advanceAge()
 local model = selected[1]
 if playable() and model and model:GetAttribute("OwnerId") == player.UserId then command:FireServer("AdvanceAge", model) end
end
local function stop()
 if playable() then command:FireServer("Stop", ownedUnits()) end
end
local function rallyBuilding()
 local model=#selected==1 and selected[1]
 local data=model and Config.Buildings[model:GetAttribute("BuildingType")]
 return model and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("Complete")==true
  and data and data.trains and #data.trains>0 and model or nil
end
local function setTouchMode(mode)
 if not TouchRules.validMode(mode) or not playable() then return end
 clearRallyPlacement()
 clearDrag(); TouchRules.cancelCommands(touches)
 if mode ~= "build" then Building:Cancel() end
 if mode == "build" then UI:SetTab("build") end
 player:SetAttribute("RTSTouchMode", mode)
end
local function cancel()
 Building:Cancel(); clearDrag(); TouchRules.cancelCommands(touches)
 clearRallyPlacement()
 player:SetAttribute("RTSTouchMode", "select")
end
local function formation(key)
 if not playable() or not Config.Formations.types[key] then return end
 local units=ownedUnits()
 if #units==0 then UI:Notify("先選取自己的部隊，再選擇陣形。") return end
 cancel()
 command:FireServer("Formation",units,key)
end
local function ungarrison()
 local model=#selected==1 and selected[1]
 if playable() and model and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType") then command:FireServer("Ungarrison",model) end
end
-- 駐紮按鈕與 G 鍵：選取單位時進入「點建築駐紮」模式；選取有駐軍的建築時讓駐軍全部離開。
local function garrison()
 if not playable() then return end
 local model=#selected==1 and selected[1]
 if model and model:GetAttribute("BuildingType") and model:GetAttribute("OwnerId")==player.UserId then
  if (model:GetAttribute("Garrison") or 0)>0 then ungarrison() else UI:Notify("這座建築裡沒有駐軍。") end
  return
 end
 if #ownedUnits()==0 then UI:Notify("先選取自己的單位，再選擇要駐紮的建築。") return end
 if player:GetAttribute("RTSGarrisonPlacement")==true then cancel(); return end
 cancel()
 player:SetAttribute("RTSGarrisonPlacement",true)
 UI:Notify("點自己的市鎮中心、瞭望塔或城堡進駐；右鍵或 Esc 取消。")
end
UI:Init({
 build = function(kind)
  if not playable() then return end
  clearRallyPlacement()
  clearDrag(); if UI.tab~="build" then UI:SetTab("build") end
  local ok,message = Building:Begin(kind,selected)
  if not ok then UI:Notify(message,"Error") else player:SetAttribute("RTSTouchMode", "build") end
 end,
 train = train, research = research, farmQueue = farmQueue, age = advanceAge, stop = stop, formation = formation,
 rally = function()
  if not playable() or not rallyBuilding() then UI:Notify("先選取一座已完工的生產建築。") return end
  cancel()
  player:SetAttribute("RTSRallyPlacement",true)
  UI:Notify("點地面或資源設定集合點；右鍵或 Esc 取消。")
 end,
 clearRally = function()
  local model=rallyBuilding()
  if playable() and model then cancel(); command:FireServer("Rally",model) end
 end,
 garrison = garrison, ungarrison = ungarrison,
 cancelTraining = function(index,revision)
  local model=selected[1]
  if playable() and model and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType") then
   command:FireServer("CancelTraining",model,index,revision)
  end
 end,
 requestDelete = function()
  if not playable() then return end
  cancel()
  UI:RequestDelete()
 end,
 delete = function(models,generation)
  if playable() then command:FireServer("Delete",models,generation) end
 end,
 trade = function(key,direction)
  local model = selected[1]
  if playable() and model and model:GetAttribute("OwnerId") == player.UserId then command:FireServer("Trade",model,key,direction) end
 end,
 start = function() command:FireServer("StartMatch") end,
 autoWork = function(enabled) if type(enabled)=="boolean" then command:FireServer("AutoWork",enabled) end end,
 surrender = function() if playable() then command:FireServer("Surrender") end end,
 restart = function() command:FireServer("RestartMatch") end,
 touchMode = setTouchMode, cancel = cancel,
 minimapMove = function(position)
  if os.clock()-lastTouchTime<0.4 or UIS:GetFocusedTextBox() or UI:IsModalOpen() then return end
  player:SetAttribute("RTSInputMode","Mouse")
  clearDrag()
  if Building.kind or player:GetAttribute("RTSRallyPlacement")==true or player:GetAttribute("RTSGarrisonPlacement")==true then cancel(); return end
  if not playable() then return end
  local units = ownedUnits()
  if #units==0 then UI:Notify("先選取自己的村民或軍隊，再右鍵小地圖移動。") return end
  -- The authority keeps the entire chosen formation inside the boundary.
  local half = (workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2-3
  local goal = Vector3.new(math.clamp(position.X,-half,half),Config.Map.GroundY,math.clamp(position.Z,-half,half))
  orderFeedback(units,goal)
  command:FireServer("Order",units,goal)
 end,
 selectIdle = function() selectIdle() end,
 selectHome = function() selectHome() end,
 selectVillagers = function() selectModels(allOwned("villager")) end,
 selectUnit = function(unit,remove)
  if UI:IsModalOpen() or not table.find(selected,unit) or unit.Parent~=workspace:FindFirstChild("Units") or (unit:GetAttribute("HP") or 0)<=0 then return end
  clearDrag(); TouchRules.cancelCommands(touches)
  if remove then
   local remaining={}
   for _,model in ipairs(selected) do if model~=unit then table.insert(remaining,model) end end
   selectModels(remaining)
  else selectModels({unit}) end
 end,
})
if RunService:IsStudio() then
 local probe=Instance.new("BindableFunction")
 probe.Name="RTSSelectionProbe"
 probe.OnInvoke=function(models)
  if models==nil then return table.clone(selected) end
  if type(models)~="table" or #models>200 then return false end
  local unitFolder,buildingFolder,resourceFolder=workspace:FindFirstChild("Units"),workspace:FindFirstChild("Buildings"),workspace:FindFirstChild("Resources")
  for _,model in ipairs(models) do
   if typeof(model)~="Instance" or not model:IsA("Model") or not model.Parent
    or (model.Parent~=unitFolder and model.Parent~=buildingFolder and model.Parent~=resourceFolder) then return false end
  end
  selectModels(models)
  return true
 end
 probe.Parent=UI.screen
 script.Destroying:Connect(function() probe:Destroy() end)
end
feedback.OnClientEvent:Connect(function(message) UI:Notify(message) end)
pcall(function()
 StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
 StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)
local function pointer() return UIS:GetMouseLocation() - GuiService:GetGuiInset() end
local function screenRay(screenPoint)
 local camera = workspace.CurrentCamera
 if not camera then return nil end
 local point = screenPoint - GuiService:GetGuiInset()
 -- Touch positions include the core UI inset; ScreenPointToRay accepts the
 -- same core UI coordinates used by GuiObject.AbsolutePosition.
 return camera:ScreenPointToRay(point.X, point.Y)
end
local function groundPoint(screenPoint)
 local ground = workspace:FindFirstChild("AOE2_Ground")
 if not ground then return nil end
 local params = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances = {ground}
 local ray = screenPoint and screenRay(screenPoint) or mouse.UnitRay
 if not ray then return nil end
 local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
 return result and result.Position
end
local function targetModel(screenPoint)
 local target = mouse.Target
 local ray
 if screenPoint then
  ray = screenRay(screenPoint)
  local result = ray and workspace:Raycast(ray.Origin, ray.Direction * 5000)
  target = result and result.Instance
 end
 -- A unit's gameplay volume stays at the server position while its image is
 -- interpolated. Skip only hit volumes so clicks follow the visible geometry.
 -- CanQuery=false cannot hide a CanCollide=true part from spatial queries.
 local excluded, params
 while target and target:IsA("BasePart") and target.Name=="CollisionVolume"
  and target.Parent and target.Parent:IsA("Model") and target.Parent:GetAttribute("UnitType") do
  excluded=excluded or {}
  if #excluded>=32 then return nil end
  table.insert(excluded,target)
  ray=ray or mouse.UnitRay
  if not ray then return nil end
  if not params then
   params=RaycastParams.new()
   params.FilterType=Enum.RaycastFilterType.Exclude
  end
  params.FilterDescendantsInstances=excluded
  local result=workspace:Raycast(ray.Origin,ray.Direction*5000,params)
  target=result and result.Instance
 end
 while target and target ~= workspace do
  if target:IsA("Model") and (target:GetAttribute("BuildingType") or target:GetAttribute("UnitType") or target:GetAttribute("ResourceType")) then return target end
  target = target.Parent
 end
 return nil
end
local function placeRally(screenPoint)
 local building=rallyBuilding()
 if not playable() or not building then cancel(); return false end
 local target=targetModel(screenPoint)
 if target then
  local ownerId=target:GetAttribute("OwnerId")
  if not target:GetAttribute("ResourceType") or (ownerId~=nil and ownerId~=player.UserId) then
   UI:Notify("集合點請點地面、中立資源或自己的農田。")
   return false
  end
 else target=groundPoint(screenPoint) end
 if not target then return false end
 if typeof(target)=="Vector3" then OrderMarkers:Ground(target,"rally") else OrderMarkers:Target(target,"rally") end
 command:FireServer("Rally",building,target)
 clearRallyPlacement()
 return true
end
-- 駐紮模式的點擊：點到自己可駐紮的建築才送出，點錯時保留模式讓玩家重點。
local function placeGarrison(screenPoint)
 local units=ownedUnits()
 if not playable() or #units==0 then cancel(); return false end
 local target=targetModel(screenPoint)
 if not garrisonBuilding(target) then
  UI:Notify("駐紮：請點自己已完工的市鎮中心、瞭望塔或城堡。")
  return false
 end
 orderFeedback(units,target,true)
 command:FireServer("Garrison",units,target)
 clearRallyPlacement()
 return true
end
-- A local flag is shown only for the selected owner's building. Its parts cannot
-- interfere with placement, ground picking or server collision/path calculations.
local rallyMarker=Instance.new("Model")
rallyMarker.Name="RTSLocalRallyFlag"
local function markerPart(name,size,offset,color)
 local part=Instance.new("Part")
 part.Name=name; part.Size=size; part.CFrame=CFrame.new(offset)
 part.Anchored=true; part.CanCollide=false; part.CanQuery=false; part.CanTouch=false
 part.Material=Enum.Material.SmoothPlastic; part.Color=color; part.Parent=rallyMarker
 return part
end
local pole=markerPart("Pole",Vector3.new(.25,7,.25),Vector3.new(0,3.5,0),Color3.fromRGB(230,213,166))
markerPart("Flag",Vector3.new(3,1.7,.15),Vector3.new(1.4,6,0),Color3.fromRGB(174,170,145)):SetAttribute("TeamColorPart",true)
rallyMarker.PrimaryPart=pole
local rallyColor
local function updateRallyMarker()
 local building=rallyBuilding()
 local goal=building and building:GetAttribute("RallyPosition")
 if typeof(goal)=="Vector3" and workspace:GetAttribute("MatchPhase")=="Playing" then
  local color=building:GetAttribute("TeamColor") or player:GetAttribute("TeamColor")
  if typeof(color)=="Color3" and color~=rallyColor then
   Art.ApplyPlayerColor(rallyMarker,color)
   rallyColor=color
  end
  rallyMarker.Parent=workspace
  rallyMarker:PivotTo(CFrame.new(goal+Vector3.new(0,3.5,0)))
 else rallyMarker.Parent=nil end
end
script.Destroying:Connect(function() rallyMarker:Destroy() end)
allOwned = function(kind, visibleOnly)
 local models, folder = {}, workspace:FindFirstChild("Units")
 if folder then
  for _, unit in ipairs(folder:GetChildren()) do
   if unit:GetAttribute("OwnerId") == player.UserId and (not kind or unit:GetAttribute("UnitType") == kind) then
    local frame=ClientUnitView.GetFrame(unit)
    local _, visible = workspace.CurrentCamera:WorldToScreenPoint(frame.Position)
    if not visibleOnly or visible then table.insert(models, unit) end
   end
  end
 end
 return models
end
-- Screen silhouette of a unit: the drag box selects on any overlap with it,
-- not only when it happens to contain the unit's centre point.
local unitExtents = setmetatable({}, {__mode="k"})
local function unitScreenRect(camera,unit)
 -- The visible model is taller and wider than its Root; measure it once.
 local extent = unitExtents[unit]
 if not extent then
  local size = unit:GetExtentsSize()
  extent = {height=math.max(size.Y,5),radius=math.max(size.X,size.Z,3)/2}
  unitExtents[unit] = extent
 end
 local center = ClientUnitView.GetFrame(unit).Position
 local ground = center.Y-2.5 -- the unit root is centred 2.5 studs above its feet
 -- Under a tilted camera the near edge of the body draws below the feet centre
 -- and the far edge above the head centre; include that depth.
 local look = camera.CFrame.LookVector
 local flat = Vector3.new(look.X,0,look.Z)
 flat = flat.Magnitude > 1e-3 and flat.Unit*extent.radius or Vector3.zero
 local feet = camera:WorldToScreenPoint(Vector3.new(center.X,ground,center.Z)-flat)
 if feet.Z <= 0 then return nil end
 local head = camera:WorldToScreenPoint(Vector3.new(center.X,ground+extent.height,center.Z)+flat)
 local middle = camera:WorldToScreenPoint(center)
 local side = camera:WorldToScreenPoint(center+camera.CFrame.RightVector*extent.radius)
 return SelectionRules.unitRect(feet.X,feet.Y,head.X,head.Y,side.X-middle.X)
end
local function boxedUnits(start,finish)
 local camera = workspace.CurrentCamera
 local box = SelectionRules.box(start.X,start.Y,finish.X,finish.Y)
 local models, rects = {}, {}
 if camera and box then
  for _, unit in ipairs(allOwned()) do
   local rect = unitScreenRect(camera,unit)
   if SelectionRules.overlaps(box,rect) then table.insert(models,unit); table.insert(rects,rect) end
  end
 end
 return models, rects, box
end
selectIdle = function()
 local idle = {}
 for _, unit in ipairs(allOwned("villager")) do
  if not unit:GetAttribute("Order") or unit:GetAttribute("Order") == "待命" then table.insert(idle, unit) end
 end
 if #idle == 0 then UI:Notify("沒有閒置村民。") return end
 idleIndex = idleIndex % #idle + 1
 selectModels({idle[idleIndex]})
 CameraFocus.Request(player,idle[idleIndex]:GetPivot().Position)
end
selectHome = function()
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
 if best then selectModels({best}); CameraFocus.Request(player,best:GetPivot().Position) end
end
local numberKeys = {[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
 [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
 [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9}
local function touchPoint(input) return Vector2.new(input.Position.X,input.Position.Y) end
local function touchBlocked(point,processed)
 local phase = workspace:GetAttribute("MatchPhase")
 return processed or player:GetAttribute("InLobby")==true or (phase ~= "Playing" and phase ~= "Ended") or UIS:GetFocusedTextBox() ~= nil or UI:IsModalOpen() or UI:BlocksPointer(point)
end
local function placeBuilding(screenPoint)
 Building:Update(groundPoint(screenPoint))
 if Building.valid and playable() then
  command:FireServer("Build",Building.kind,Building.position,Building:GetBuilders(),Building.rotated)
  cancel()
 else UI:Notify(Building.reason or "無法建造：請確認資源、已選村民及占地。","Error") end
end
-- 整排城牆：放開時送出起訖點，牆段由伺服器計算與驗證。keep 為 true 時保留建造模式繼續放下一排。
local function placeLine(position,keep)
 Building:Update(position)
 if Building.valid and playable() and Building.lineStart and Building.lineEnd then
  command:FireServer("BuildLine",Building.kind,Building.lineStart,Building.lineEnd,Building:GetBuilders())
  if keep then Building:CancelLine() else cancel() end
 else
  UI:Notify(Building.reason or "無法建造：請確認資源、已選村民及占地。","Error")
  Building:CancelLine()
 end
end
local function touchCommand(screenPoint)
 if player:GetAttribute("RTSRallyPlacement")==true then placeRally(screenPoint); return end
 if player:GetAttribute("RTSGarrisonPlacement")==true then placeGarrison(screenPoint); return end
 local mode = player:GetAttribute("RTSTouchMode") or "select"
 local target = targetModel(screenPoint)
 if mode == "select" then
  if target and target == lastClick and os.clock() - (lastClickTime or 0) < 0.32 and target:GetAttribute("UnitType") and target:GetAttribute("OwnerId") == player.UserId then
   selectModels(allOwned(target:GetAttribute("UnitType"),true))
  else selectModels(target and {target} or {}) end
  lastClick,lastClickTime = target,os.clock()
  return
 end
 if not playable() then return end
 local units = ownedUnits()
 if #units == 0 then UI:Notify("先點選自己的村民或軍隊，再選擇指令。") return end
 if mode == "build" then
  if target and target:GetAttribute("BuildingType") and target:GetAttribute("OwnerId") == player.UserId then
   local workers={}
   for _,unit in ipairs(units) do if unit:GetAttribute("UnitType")=="villager" then table.insert(workers,unit) end end
   if #workers>0 then orderFeedback(workers,target); command:FireServer("Order",workers,target)
   else UI:Notify("先選村民，才能協助施工或修復自己的建築。") end
  else UI:Notify("挑選建築後在地面放置；點自己的工地或建築可施工、修復或交貨。") end
  return
 elseif mode == "move" then target = groundPoint(screenPoint)
 elseif mode == "gather" then
  local owner = target and target:GetAttribute("OwnerId")
  if not target or not target:GetAttribute("ResourceType") or (owner ~= nil and owner ~= player.UserId) then
   UI:Notify("採集模式：請點資源或自己的農田。") return
  end
 elseif mode == "attack" then
  if target and rejectFriendlyTarget(target) then return end
  if not target or not target:GetAttribute("OwnerId") or target:GetAttribute("OwnerId") == player.UserId
   or not (target:GetAttribute("UnitType") or target:GetAttribute("BuildingType")) then
   UI:Notify("攻擊模式：請點敵方單位或建築。") return
  end
 else return end
 if target then orderFeedback(units,target); command:FireServer("Order",units,target) end
end
UIS.InputBegan:Connect(function(input, processed)
 if input.UserInputType == Enum.UserInputType.Touch then
  lastTouchTime = os.clock(); player:SetAttribute("RTSInputMode","Touch"); clearDrag()
  local point = touchPoint(input)
  TouchRules.begin(touches,input,point.X,point.Y,lastTouchTime,touchBlocked(point,processed))
  if Building.kind then
   local position=TouchRules.single(touches) and groundPoint(point) or nil
   -- 觸控：手指按下為城牆起點，拖曳後放開為終點；第二指加入時取消這一排。
   if Building:IsLine() then
    if position then Building:StartLine(position) else Building:CancelLine() end
   end
   Building:Update(position)
  end
  return
 end
 -- Some devices synthesize mouse events for a touch. Never turn those into
 -- desktop box selection or a second command after the finger is released.
 if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2) and os.clock()-lastTouchTime<0.4 then return end
 if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
  player:SetAttribute("RTSInputMode","Mouse")
 end
 if UI:HotkeyInput(input) then return end
 if input.KeyCode == Enum.KeyCode.Escape then
  cancel()
  if UI.CancelDelete then UI:CancelDelete() end
  if UI.menuPanel.Visible then UI.menuPanel.Visible = false end
  return
 end
 if player:GetAttribute("InLobby")==true or processed or UIS:GetFocusedTextBox() or UI:IsModalOpen() then return end
 local group = numberKeys[input.KeyCode]
 -- 可改綁的指令由設定中的熱鍵決定；滑鼠輸入沒有對應的指令。
 local hotkey = input.UserInputType == Enum.UserInputType.Keyboard and HotkeyRules.actionFor(UI.hotkeys,input.KeyCode.Name) or nil
 if group then
  if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then
   groups[group] = table.clone(ownedUnits()); UI:Notify("編隊 " .. group .. "：" .. #groups[group] .. " 個單位")
  else
   local alive = {}
   for _, model in ipairs(groups[group] or {}) do if model.Parent and model:GetAttribute("OwnerId") == player.UserId then table.insert(alive, model) end end
   selectModels(alive)
   if lastGroup == group and os.clock() - (lastGroupTime or 0) < 0.4 and alive[1] then CameraFocus.Request(player,alive[1]:GetPivot().Position) end
   lastGroup, lastGroupTime = group, os.clock()
  end
 elseif hotkey == "build" then cancel(); UI:SetTab("build")
 elseif hotkey == "formation" then cancel(); UI:SetTab("formation")
 elseif hotkey == "train" then UI:SetTab("train"); UI:DefaultTrain()
 elseif hotkey == "research" then
  if Building:CanRotate() then Building:Rotate() else UI:SetTab("research") end
 elseif hotkey == "advanceAge" then advanceAge()
 elseif hotkey == "stop" then stop()
 elseif hotkey == "garrison" then garrison()
 elseif hotkey == "delete" and playable() then cancel(); UI:RequestDelete()
 elseif hotkey == "selectVillagers" then selectModels(allOwned("villager"))
 elseif hotkey == "selectHome" then selectHome()
 elseif hotkey == "selectIdle" then selectIdle()
 elseif hotkey == "gotoAlert" then
  -- AOE-style "go to last alert": the sound script records where you were attacked.
  local alert=player:GetAttribute("RTSAlertPosition")
  if typeof(alert)=="Vector3" then CameraFocus.Request(player,alert) end
 elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not UI:BlocksPointer() then
  if player:GetAttribute("RTSRallyPlacement")==true then placeRally(); return
  elseif player:GetAttribute("RTSGarrisonPlacement")==true then placeGarrison(); return
  elseif Building:IsLine() then
   -- 按住拖曳放置整排；放開滑鼠時送出。
   if not Building:StartLine(groundPoint()) then UI:Notify("請在地面選擇城牆的起點。","Error") end
  elseif Building.kind then
   Building:Update(groundPoint())
   if Building.valid and playable() then
    command:FireServer("Build", Building.kind, Building.position, Building:GetBuilders(), Building.rotated)
    if not UIS:IsKeyDown(Enum.KeyCode.LeftShift) and not UIS:IsKeyDown(Enum.KeyCode.RightShift) then Building:Cancel() end
   else UI:Notify(Building.reason or "無法建造：請確認資源、已選村民及占地。","Error") end
  else dragStart = pointer() end
 elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not UI:BlocksPointer() then
  if Building.kind or player:GetAttribute("RTSRallyPlacement")==true or player:GetAttribute("RTSGarrisonPlacement")==true then cancel(); return end
  if not playable() then return end
  local units = ownedUnits()
  if #units==0 and rallyBuilding() then placeRally(); return end
  if #units == 0 then UI:Notify("先選取自己的村民或軍隊，再按右鍵下令。") return end
  local target = targetModel() or groundPoint()
  if target and not rejectFriendlyTarget(target) then
   -- Alt+右鍵是駐紮的專用指令；一般右鍵不會駐紮。
   local garrisonOrder=garrisonBuilding(target) and (UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt))
   orderFeedback(units,target,garrisonOrder)
   if garrisonOrder then command:FireServer("Garrison",units,target)
   else command:FireServer("Order", units, target) end
  end
 end
end)
UIS.InputChanged:Connect(function(input,processed)
 if input.UserInputType ~= Enum.UserInputType.Touch then return end
 lastTouchTime = os.clock()
 local point = touchPoint(input)
 TouchRules.move(touches,input,point.X,point.Y,touchBlocked(point,processed))
end)
UIS.InputEnded:Connect(function(input,processed)
 if input.UserInputType == Enum.UserInputType.Touch then
  lastTouchTime = os.clock()
  local point = touchPoint(input)
  local released = TouchRules.finish(touches,input,point.X,point.Y,lastTouchTime,touchBlocked(point,processed))
  if not released then return end
  if Building.lineStart then
   if released.place then placeLine(groundPoint(point),false) else Building:CancelLine(); Building:Update(nil) end
  elseif Building.kind then
   if released.place then placeBuilding(point) else Building:Update(nil) end
  elseif released.tap then touchCommand(point) end
  return
 end
 if input.UserInputType == Enum.UserInputType.MouseButton1 and Building.lineStart then
  if os.clock()-lastTouchTime<0.4 then return end
  placeLine(not UI:BlocksPointer() and groundPoint() or nil,UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift))
  return
 end
 if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not dragStart then return end
 local start = dragStart; clearDrag()
 if os.clock()-lastTouchTime<0.4 then return end
 if player:GetAttribute("InLobby")==true or UI:IsModalOpen() then return end
 local finish = pointer()
 local boxed, box
 if SelectionRules.isDrag(start.X,start.Y,finish.X,finish.Y) then
  local models, _, area = boxedUnits(start,finish)
  boxed, box = models, area
 end
 -- A drag that began on the map stays valid when released over the HUD. A tiny
 -- box that caught nothing is a slipped click, not a request to deselect.
 if boxed and (#boxed > 0 or not SelectionRules.isSmall(box)) then
  local models = (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) and ownedUnits() or {}
  for _, unit in ipairs(boxed) do table.insert(models, unit) end
  selectModels(models)
 elseif UI:BlocksPointer() then return
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
UIS.WindowFocusReleased:Connect(function() clearDrag(); TouchRules.reset(touches); Building:CancelLine(); Building:Update(nil) end)
player:GetAttributeChangedSignal("RTSModalOpen"):Connect(function()
 if player:GetAttribute("RTSModalOpen") then clearDrag(); clearRallyPlacement(); TouchRules.reset(touches); Building:CancelLine(); Building:Update(nil) end
end)
workspace:GetAttributeChangedSignal("MatchPhase"):Connect(function()
 if UI.CancelDelete then UI:CancelDelete() end
 cancel(); TouchRules.reset(touches); selectModels({})
 if workspace:GetAttribute("MatchPhase") == "Lobby" then table.clear(groups) end
end)
for _,attribute in ipairs({"Defeated","Spectator","InLobby"}) do
 player:GetAttributeChangedSignal(attribute):Connect(function()
  if player:GetAttribute(attribute) then cancel(); selectModels({}); if attribute=="InLobby" then table.clear(groups) end end
 end)
end
-- Context cursor and hover outline, AOE-style: the pointer previews what a
-- right click would do. Picking runs at a bounded rate; the badge tracks per frame.
local hoverHighlight=Instance.new("Highlight")
hoverHighlight.Name="RTSHoverHighlight"
hoverHighlight.FillTransparency=1
hoverHighlight.OutlineTransparency=0.4
hoverHighlight.DepthMode=Enum.HighlightDepthMode.Occluded
local hoverColors={own=Color3.fromRGB(235,242,225),ally=Color3.fromRGB(118,210,211),enemy=Color3.fromRGB(240,86,70),
 neutral=Color3.fromRGB(246,214,104),unresolved=Color3.fromRGB(200,200,200)}
local function hover(model)
 if model and (table.find(selected,model) or not model.Parent) then model=nil end
 if hoverHighlight.Adornee==model then return end
 hoverHighlight.Adornee=model
 if model then
  hoverHighlight.OutlineColor=hoverColors[relation(model)] or hoverColors.unresolved
  -- Never parent into the server model: its removal would destroy this outline.
  hoverHighlight.Parent=workspace
 else hoverHighlight.Parent=nil end
end
local cursorKind,cursorTime="none",0
local function resolvePointer()
 local phase=workspace:GetAttribute("MatchPhase")
 local active=UIS.MouseEnabled and player:GetAttribute("RTSInputMode")~="Touch" and player:GetAttribute("InLobby")~=true
  and (phase=="Playing" or phase=="Ended")
 if not active then hover(nil); return "none" end
 local overUI=UI:IsModalOpen() or UI:BlocksPointer() or UIS:GetFocusedTextBox()~=nil
 local target=not overUI and targetModel() or nil
 hover(target)
 local context={active=true,overUI=overUI,placing=Building.kind~=nil,placementValid=Building.valid==true,
  rally=player:GetAttribute("RTSRallyPlacement")==true,garrison=player:GetAttribute("RTSGarrisonPlacement")==true,villagers=0,military=0}
 if playable() then
  for _,unit in ipairs(ownedUnits()) do
   if unit:GetAttribute("UnitType")=="villager" then context.villagers+=1 else context.military+=1 end
   if unit:GetAttribute("UnitType")=="monk" then context.monks=(context.monks or 0)+1 end
  end
 end
 if target then
  local hp,maxHP=target:GetAttribute("HP"),target:GetAttribute("MaxHP")
  context.target={relation=relation(target),unit=target:GetAttribute("UnitType")~=nil,building=target:GetAttribute("BuildingType")~=nil,
   resource=target:GetAttribute("ResourceType"),complete=target:GetAttribute("Complete"),
   damaged=type(hp)=="number" and type(maxHP)=="number" and hp<maxHP,garrison=garrisonBuilding(target)}
 end
 return CursorRules.Resolve(context)
end
script.Destroying:Connect(function()
 CursorView:Destroy(); hoverHighlight:Destroy(); OrderMarkers:Clear()
 if ringFolder then ringFolder:Destroy() end
 for _, mark in ipairs(previewMarks) do mark:Destroy() end
end)
local updateTime, mapTime = 0, 0
RunService.RenderStepped:Connect(function(dt)
 cursorTime += dt
 if cursorTime >= 1/30 then cursorTime = 0; cursorKind = resolvePointer() end
 CursorView:Set(cursorKind)
 if Building.kind then
  local position
  if not UI:IsModalOpen() then
   if player:GetAttribute("RTSInputMode") == "Touch" then
    local point = TouchRules.single(touches)
    if point then position = groundPoint(Vector2.new(point.x,point.y)) end
   elseif not UI:BlocksPointer() then position = groundPoint() end
  end
  Building:Update(position)
 end
 if dragStart then
  local finish = pointer()
  local dragging = SelectionRules.isDrag(dragStart.X,dragStart.Y,finish.X,finish.Y)
  UI.selectionBox.Visible = dragging
  UI.selectionBox.Position = UDim2.fromOffset(math.min(finish.X, dragStart.X), math.min(finish.Y, dragStart.Y))
  UI.selectionBox.Size = UDim2.fromOffset(math.abs(finish.X - dragStart.X), math.abs(finish.Y - dragStart.Y))
  if dragging then local _, rects = boxedUnits(dragStart,finish); showPreview(rects) else showPreview({}) end
 end
 for _, ring in ipairs(rings) do
  local model = ring.model
  local shown = model.Parent ~= nil and model.PrimaryPart ~= nil
  if shown then
   local position = ClientUnitView.GetFrame(model).Position
   ring.part.CFrame = CFrame.new(position.X,position.Y-2.38,position.Z)*ringTilt
  end
  ring.part.Transparency = shown and 0.55 or 1
 end
 updateTime += dt; mapTime += dt
 if updateTime >= 0.15 then
  updateTime = 0
  local alive = {}; for _, model in ipairs(selected) do if model.Parent then table.insert(alive, model) end end
  if #alive ~= #selected then selectModels(alive) end
  updateRallyMarker()
  UI:Update(selected, Building.kind)
 end
 if mapTime >= 0.6 then mapTime = 0; UI:UpdateMap() end
end)
player:SetAttribute("RTSTouchInputReady",true)
