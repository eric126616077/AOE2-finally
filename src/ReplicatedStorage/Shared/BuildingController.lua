local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(RS.GameData.GameConfig)
local Grid = require(RS.Shared.Grid)
local Art = require(RS.Shared.Art)
local WallRules = require(RS.Shared.WallRules)
local player = Players.LocalPlayer
-- auto：未選村民時由伺服器派最近的村民施工；客戶端只送空選取，不猜測派誰。
-- rotated：可旋轉建築（城門）目前是否轉 90 度。lineStart／lineEnd／lineCount：整排城牆拖曳中的起訖點與可放置段數。
local Controller = {kind = nil, position = nil, valid = false, reason = nil, builders = {}, auto = false,
 rotated = false, lineStart = nil, lineEnd = nil, lineCount = 0}
local preview, ghost, ghostHeight, lastPosition, lastCheck
local lastRotated, manualRotation, lastAutoCell
local lineFolder, lineTarget, lineKey
local lineParts = {}
local colors = {valid = Color3.fromRGB(91,218,139), invalid = Color3.fromRGB(231,97,88), unpaid = Color3.fromRGB(232,184,84)}
local function canBuild(unit)
 return typeof(unit)=="Instance" and unit:IsA("Model") and unit.Parent==workspace:FindFirstChild("Units")
  and unit:GetAttribute("RTSManaged")==true and unit:GetAttribute("OwnerId")==player.UserId
  and unit:GetAttribute("UnitType")=="villager" and type(unit:GetAttribute("HP"))=="number"
  and Grid.isFinite(unit:GetAttribute("HP")) and unit:GetAttribute("HP")>0
end
function Controller:HasBuilders(selection)
 if type(selection)~="table" then return false end
 for _,unit in ipairs(selection) do if canBuild(unit) then return true end end
 return false
end
function Controller:GetSelectionBuilders(selection)
 local result,seen={},{}
 if type(selection)~="table" then return result end
 for _,unit in ipairs(selection) do
  if not seen[unit] and canBuild(unit) then seen[unit]=true; table.insert(result,unit) end
 end
 return result
end
-- 未選任何目標時，只要自己仍有可施工村民就能直接開啟建築選單。
function Controller:CanAutoBuild()
 if workspace:GetAttribute("MatchPhase") ~= "Playing" or player:GetAttribute("Defeated") or player:GetAttribute("Spectator") then return false end
 local folder = workspace:FindFirstChild("Units")
 if not folder then return false end
 for _,unit in ipairs(folder:GetChildren()) do if canBuild(unit) then return true end end
 return false
end
function Controller:GetBuilders()
 local result={}
 for _,unit in ipairs(self.builders) do if canBuild(unit) then table.insert(result,unit) end end
 return result
end
local function clearLine()
 if lineFolder then lineFolder:Destroy(); lineFolder = nil end
 table.clear(lineParts)
 lineTarget, lineKey = nil, nil
end
-- 放棄拖曳中的整排城牆，保留目前選擇的建築。
function Controller:CancelLine()
 self.lineStart, self.lineEnd, self.lineCount = nil, nil, 0
 clearLine()
 lastPosition, lastCheck = nil, nil
end
function Controller:Cancel()
 self.kind, self.position, self.valid, self.reason = nil, nil, false, nil
 self.builders={}; self.auto=false
 self.rotated, self.lineStart, self.lineEnd, self.lineCount = false, nil, nil, 0
 if preview then preview:Destroy(); preview = nil end
 if ghost then ghost:Destroy(); ghost = nil end
 clearLine()
 lastPosition, lastCheck = nil, nil
 lastRotated, manualRotation, lastAutoCell = nil, false, nil
end
function Controller:Begin(kind,selection)
 self:Cancel()
 local data = Config.Buildings[kind]
 if not data or not table.find(Config.BuildOrder, kind) then return false, "未知的建築類型。" end
 if workspace:GetAttribute("MatchPhase") ~= "Playing" or player:GetAttribute("Defeated") or player:GetAttribute("Spectator") then return false, "目前無法建造。" end
 local builders=self:GetSelectionBuilders(selection)
 local auto=#builders==0 and type(selection)=="table" and #selection==0
 if auto and not self:CanAutoBuild() then return false,"沒有可施工的村民，請先在主城訓練村民。" end
 if #builders==0 and not auto then return false,"先選取自己的村民，再選擇建築。" end
 if #builders>Config.Construction.maxSelectedWorkers then return false,"選取的施工村民太多，請減少村民數量。" end
 if (player:GetAttribute("Age") or 1) < (data.minAge or 1) then return false, "尚未達到這座建築所需的時代。" end
 self.builders=builders
 self.auto=auto
 self.kind = kind
 preview = Instance.new("Part")
 preview.Name = "BuildingPreview"
 preview.Anchored, preview.CanCollide, preview.CanQuery, preview.CanTouch = true, false, false, false
 preview.Size = Vector3.new(data.size.X * Config.Map.GridSize, data.height, data.size.Y * Config.Map.GridSize)
 preview.Material = Enum.Material.SmoothPlastic
 preview.Transparency = 0.86
 local outline = Instance.new("SelectionBox")
 outline.Name, outline.Adornee = "Outline", preview
 outline.LineThickness, outline.SurfaceTransparency = 0.05, 1
 outline.Parent = preview
 preview.Parent = workspace
 -- Original shared art makes the intended building legible without changing server models.
 ghost = Art.Create(kind, player:GetAttribute("TeamColor"))
 ghost.Name = "BuildingPreviewArt"
 local _, bounds = ghost:GetBoundingBox()
 ghost:ScaleTo(math.min(preview.Size.X / math.max(1, bounds.X), preview.Size.Z / math.max(1, bounds.Z), data.height / math.max(1, bounds.Y)))
 local _, scaledBounds = ghost:GetBoundingBox(); ghostHeight = scaledBounds.Y
 for _, part in ipairs(ghost:GetDescendants()) do
  if part:IsA("BasePart") then
   part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
   part.Transparency = 0.5
  end
 end
 return true
end
function Controller:IsLine()
 local data = self.kind and Config.Buildings[self.kind]
 return data~=nil and data.line==true
end
function Controller:CanRotate()
 local data = self.kind and Config.Buildings[self.kind]
 return data~=nil and data.rotatable==true
end
-- 手動旋轉後不再依鄰近建築自動轉向，直到重新選擇建築。
function Controller:Rotate()
 if not self:CanRotate() then return false end
 self.rotated = not self.rotated
 manualRotation = true
 lastPosition = nil
 return true
end
-- 整排城牆的起點；之後的 Update 以游標位置為終點。
function Controller:StartLine(worldPosition)
 if not preview or not self:IsLine() or not worldPosition then return false end
 clearLine()
 Config.Map.MapSize = workspace:GetAttribute("MapSize") or workspace:GetAttribute("MatchSize") or Config.Map.MapSize
 self.lineStart = Grid.snap(worldPosition, Config.Buildings[self.kind].size)
 self.lineEnd, self.lineCount = nil, 0
 lastPosition, lastCheck = nil, nil
 return true
end
local function obstacleQuery()
 local params = OverlapParams.new()
 params.FilterType = Enum.RaycastFilterType.Exclude
 local excluded = {preview, ghost}
 -- Generated scenery is non-queryable; never hide user obstacles by folder name.
 local ground=workspace:FindFirstChild("AOE2_Ground")
 if ground then table.insert(excluded,ground) end
 params.FilterDescendantsInstances = excluded
 local folders = {}
 for _, name in ipairs({"Buildings", "Resources", "Units"}) do
  local folder = workspace:FindFirstChild(name); if folder then table.insert(folders, folder) end
 end
 return params, folders
end
-- 城門可以直接蓋在自己的石牆上；伺服器會重新驗證並拆除被取代的牆段。
local function ownWall(part)
 local folder = workspace:FindFirstChild("Buildings")
 local model = part
 while model and model.Parent ~= folder do model = model.Parent end
 return folder ~= nil and model ~= nil and model:GetAttribute("BuildingType") == "Wall" and model:GetAttribute("OwnerId") == player.UserId
end
local function boxClear(data, cframe, size, params, folders)
 for _, part in ipairs(workspace:GetPartBoundsInBox(cframe, size, params)) do
  local obstacle = part.CanCollide
  for _, folder in ipairs(folders) do
   if part:IsDescendantOf(folder) then obstacle = true; break end
  end
  if obstacle and not (data.gate and ownWall(part)) then return false end
 end
 return true
end
-- 兩端緊鄰建築（通常是城牆）的方向勝出；無法判斷時回傳 nil，維持目前方向。
local function autoRotated(center, data)
 local folder = workspace:FindFirstChild("Buildings")
 if not folder then return nil end
 local params = OverlapParams.new()
 params.FilterType = Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances = {folder}
 local g = Config.Map.GridSize
 local reach = (data.size.X/2+0.5)*g
 local function caps(rotated)
  local count = 0
  for _, side in ipairs({-1,1}) do
   local offset = rotated and Vector3.new(0,4,side*reach) or Vector3.new(side*reach,4,0)
   if #workspace:GetPartBoundsInBox(CFrame.new(center+offset), Vector3.new(g-1,6,g-1), params)>0 then count += 1 end
  end
  return count
 end
 local flat, turned = caps(false), caps(true)
 if turned>flat then return true elseif flat>turned then return false end
 return nil
end
local function builderState(self, data)
 local hasBuilder = #self:GetBuilders()>0 or (self.auto and self:CanAutoBuild())
 local ageAllowed = (player:GetAttribute("Age") or 1) >= (data.minAge or 1)
 return hasBuilder, ageAllowed
end
local function linePart(index, data)
 local part = lineParts[index]
 if part then return part end
 if not lineFolder then
  lineFolder = Instance.new("Folder")
  lineFolder.Name = "BuildingPreviewLine"
  lineFolder.Parent = workspace
 end
 local g = Config.Map.GridSize
 part = Instance.new("Part")
 part.Name = "Segment"
 part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
 part.CastShadow = false
 part.Size = Vector3.new(data.size.X*g-0.4, data.height, data.size.Y*g-0.4)
 part.Material = Enum.Material.SmoothPlastic
 part.Transparency = 0.55
 part.Parent = lineFolder
 lineParts[index] = part
 return part
end
local function updateLine(self, data, worldPosition)
 if worldPosition then lineTarget = worldPosition end
 if not lineTarget then return end
 Config.Map.MapSize = workspace:GetAttribute("MapSize") or workspace:GetAttribute("MatchSize") or Config.Map.MapSize
 local _, fromX, fromZ = Grid.snap(self.lineStart, data.size)
 local finish, toX, toZ = Grid.snap(lineTarget, data.size)
 self.position, self.lineEnd = finish, finish
 preview.Transparency = 1; preview.Outline.Visible = false
 ghost.Parent = workspace; ghost:PivotTo(CFrame.new(finish + Vector3.new(0, ghostHeight / 2, 0)))
 -- Per-segment occupancy checks run at most four times a second at the same end cell.
 local key = toX..","..toZ
 if lineKey == key and lastCheck and os.clock() - lastCheck < 0.25 then return end
 lineKey, lastCheck = key, os.clock()
 local cells, truncated = WallRules.line(fromX, fromZ, toX, toZ, Config.Walls.maxLine)
 if not cells then self.valid, self.reason = false, "請在地面選擇城牆的終點。"; return end
 local balance = {}
 for resource in pairs(data.cost) do balance[resource] = player:GetAttribute(resource) or 0 end
 local affordable = WallRules.affordableCount(balance, data.cost, #cells)
 local params, folders = obstacleQuery()
 local g = Config.Map.GridSize
 local checkSize = Vector3.new(data.size.X*g-0.2, math.max(4, data.height), data.size.Y*g-0.2)
 local placed, clearCount = 0, 0
 for index, cell in ipairs(cells) do
  local position = Grid.cellPosition(cell.x, cell.z, data.size)
  local frame = CFrame.new(position + Vector3.new(0, data.height / 2, 0))
  local clear = Grid.inBounds(position, data.size) and boxClear(data, frame, checkSize, params, folders)
  local part = linePart(index, data)
  part.CFrame = frame
  part.Transparency = 0.55
  if clear then clearCount += 1 end
  if clear and placed < affordable then placed += 1; part.Color = colors.valid
  else part.Color = clear and colors.unpaid or colors.invalid end
 end
 for index = #cells + 1, #lineParts do lineParts[index].Transparency = 1 end
 local hasBuilder, ageAllowed = builderState(self, data)
 self.lineCount = placed
 self.valid = hasBuilder and ageAllowed and placed > 0
 self.reason = not ageAllowed and "尚未達到建築所需的時代。"
  or not hasBuilder and (self.auto and "沒有可施工的村民，請先訓練村民。" or "選中的村民已無法施工，請重新選取村民。")
  or clearCount == 0 and "這一排的占地都有單位、建築、自然資源或障礙物。"
  or placed == 0 and "資源不足，請先採集或交換資源。"
  or truncated and ("一次最多放置 " .. Config.Walls.maxLine .. " 段城牆。") or nil
end
function Controller:Update(worldPosition)
 if not preview then return end
 local data = Config.Buildings[self.kind]
 if self.lineStart then updateLine(self, data, worldPosition); return end
 if not worldPosition then
  self.position, self.valid = nil, false
  self.reason = "請在地面選擇建築位置。"
  preview.Transparency = 1; preview.Outline.Visible = false; ghost.Parent = nil
  lastPosition = nil
  return
 end
 -- Config is a separate module instance on the client; the server publishes map dimensions.
 Config.Map.MapSize = workspace:GetAttribute("MapSize") or workspace:GetAttribute("MatchSize") or Config.Map.MapSize
 if data.rotatable and not manualRotation then
  local cell = Grid.snap(worldPosition, Vector2.new(1,1))
  if cell ~= lastAutoCell then
   lastAutoCell = cell
   local turned = autoRotated(cell, data)
   if turned ~= nil then self.rotated = turned end
  end
 end
 local size = Vector2.new(WallRules.footprint(data.size.X, data.size.Y, self.rotated))
 local position = Grid.snap(worldPosition, size)
 preview.Size = Vector3.new(size.X * Config.Map.GridSize, data.height, size.Y * Config.Map.GridSize)
 preview.Transparency = 0.86; preview.Outline.Visible = true
 preview.Position = position + Vector3.new(0, data.height / 2, 0)
 ghost.Parent = workspace
 ghost:PivotTo(CFrame.new(position + Vector3.new(0, ghostHeight / 2, 0)) * CFrame.Angles(0, self.rotated and math.pi/2 or 0, 0))
 self.position = position
 -- Expensive occupancy checks run at most ten times a second at the same grid cell.
 if lastPosition == position and lastRotated == self.rotated and lastCheck and os.clock() - lastCheck < 0.1 then return end
 lastPosition, lastRotated, lastCheck = position, self.rotated, os.clock()
 local hasBuilder, ageAllowed = builderState(self, data)
 local affordable = true
 for key, cost in pairs(data.cost) do if (player:GetAttribute(key) or 0) < cost then affordable = false end end
 local params, folders = obstacleQuery()
 local inBounds = Grid.inBounds(position, size)
 local checkSize = Vector3.new(preview.Size.X-0.2, math.max(4, data.height), preview.Size.Z-0.2)
 local clear = boxClear(data, preview.CFrame, checkSize, params, folders)
 self.valid = hasBuilder and affordable and inBounds and clear and ageAllowed
 self.reason = not ageAllowed and "尚未達到建築所需的時代。" or not inBounds and "建築占地超出地圖邊界。"
  or not affordable and "資源不足，請先採集或交換資源。" or not hasBuilder and (self.auto and "沒有可施工的村民，請先訓練村民。" or "選中的村民已無法施工，請重新選取村民。")
  or not clear and "建築占地有單位、建築、自然資源或障礙物。" or nil
 preview.Color = self.valid and colors.valid or colors.invalid
 preview.Outline.Color3 = preview.Color
end
return Controller
