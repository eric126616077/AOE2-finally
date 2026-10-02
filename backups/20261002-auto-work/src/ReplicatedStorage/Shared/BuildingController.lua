local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(RS.GameData.GameConfig)
local Grid = require(RS.Shared.Grid)
local Art = require(RS.Shared.Art)
local player = Players.LocalPlayer
local Controller = {kind = nil, position = nil, valid = false, reason = nil, builders = {}}
local preview, ghost, ghostHeight, lastPosition, lastCheck
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
function Controller:GetBuilders()
 local result={}
 for _,unit in ipairs(self.builders) do if canBuild(unit) then table.insert(result,unit) end end
 return result
end
function Controller:Cancel()
 self.kind, self.position, self.valid, self.reason = nil, nil, false, nil
 self.builders={}
 if preview then preview:Destroy(); preview = nil end
 if ghost then ghost:Destroy(); ghost = nil end
 lastPosition, lastCheck = nil, nil
end
function Controller:Begin(kind,selection)
 self:Cancel()
 local data = Config.Buildings[kind]
 if not data or not table.find(Config.BuildOrder, kind) then return false, "未知的建築類型。" end
 if workspace:GetAttribute("MatchPhase") ~= "Playing" or player:GetAttribute("Defeated") or player:GetAttribute("Spectator") then return false, "目前無法建造。" end
 local builders=self:GetSelectionBuilders(selection)
 if #builders==0 then return false,"先選取自己的村民，再選擇建築。" end
 if #builders>Config.Construction.maxSelectedWorkers then return false,"選取的施工村民太多，請減少村民數量。" end
 if (player:GetAttribute("Age") or 1) < (data.minAge or 1) then return false, "尚未達到這座建築所需的時代。" end
 self.builders=builders
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
function Controller:Update(worldPosition)
 if not preview then return end
 if not worldPosition then
  self.position, self.valid = nil, false
  self.reason = "請在地面選擇建築位置。"
  preview.Transparency = 1; preview.Outline.Visible = false; ghost.Parent = nil
  lastPosition = nil
  return
 end
 local data = Config.Buildings[self.kind]
 -- Config is a separate module instance on the client; the server publishes map dimensions.
 Config.Map.MapSize = workspace:GetAttribute("MapSize") or workspace:GetAttribute("MatchSize") or Config.Map.MapSize
 local position = Grid.snap(worldPosition, data.size)
 preview.Transparency = 0.86; preview.Outline.Visible = true
 preview.Position = position + Vector3.new(0, data.height / 2, 0)
 ghost.Parent = workspace; ghost:PivotTo(CFrame.new(position + Vector3.new(0, ghostHeight / 2, 0)))
 self.position = position
 -- Expensive occupancy checks run at most ten times a second at the same grid cell.
 if lastPosition == position and lastCheck and os.clock() - lastCheck < 0.1 then return end
 lastPosition, lastCheck = position, os.clock()
 local hasBuilder, affordable = #self:GetBuilders()>0, true
 for key, cost in pairs(data.cost) do if (player:GetAttribute(key) or 0) < cost then affordable = false end end
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
 local inBounds = Grid.inBounds(position, data.size)
 local clear = true
 local checkSize = Vector3.new(preview.Size.X-0.2, math.max(4, data.height), preview.Size.Z-0.2)
 for _, part in ipairs(workspace:GetPartBoundsInBox(preview.CFrame, checkSize, params)) do
  local obstacle = part.CanCollide
  for _, folder in ipairs(folders) do
   if part:IsDescendantOf(folder) then obstacle = true; break end
  end
  if obstacle then clear = false; break end
 end
 local ageAllowed = (player:GetAttribute("Age") or 1) >= (data.minAge or 1)
 self.valid = hasBuilder and affordable and inBounds and clear and ageAllowed
 self.reason = not ageAllowed and "尚未達到建築所需的時代。" or not inBounds and "建築占地超出地圖邊界。"
  or not affordable and "資源不足，請先採集或交換資源。" or not hasBuilder and "選中的村民已無法施工，請重新選取村民。"
  or not clear and "建築占地有單位、建築、自然資源或障礙物。" or nil
 preview.Color = self.valid and Color3.fromRGB(91,218,139) or Color3.fromRGB(231,97,88)
 preview.Outline.Color3 = preview.Color
end
return Controller
