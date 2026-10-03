-- A separate walkable staging plaza in a bright, blocky Roblox style. These decorations are never RTS buildings.
local Config = require(game.ReplicatedStorage.GameData.GameConfig)
local Art = require(game.ReplicatedStorage.Shared.Art)
local GameModeRules = require(game.ReplicatedStorage.Shared.GameModeRules)
local LobbyWorld = {}
local active
-- Clean SmoothPlastic palette: white stone, candy trims and saturated grass read well at every graphics level.
local white = Color3.fromRGB(242, 243, 247)
local tile = Color3.fromRGB(206, 218, 236)
local wallColor = Color3.fromRGB(226, 230, 238)
local trim = Color3.fromRGB(0, 162, 255)
local roof = Color3.fromRGB(226, 64, 58)
local grass = Color3.fromRGB(92, 180, 74)
local hedge = Color3.fromRGB(58, 146, 62)
local timber = Color3.fromRGB(124, 84, 52)
local gold = Color3.fromRGB(255, 200, 40)
local ink = Color3.fromRGB(27, 31, 48)
local water = Color3.fromRGB(64, 176, 255)
local flowerColors = { Color3.fromRGB(255, 120, 182), Color3.fromRGB(255, 214, 64), white, Color3.fromRGB(176, 120, 255) }
local TITLE_FONT, BODY_FONT = Enum.Font.FredokaOne, Enum.Font.GothamBold

local function part(parent, name, size, position, color, material, collidable)
 local item = Instance.new("Part")
 item.Name, item.Size, item.Position = name, size, position
 item.Color, item.Material = color, material or Enum.Material.SmoothPlastic
 item.Anchored, item.CanCollide, item.CanTouch = true, collidable ~= false, false
 item.TopSurface, item.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
 item.Parent = parent
 return item
end

-- Cylinders stand upright; Roblox cylinders run along X, so the height goes first.
local function disc(parent, name, diameter, height, position, color, material, collidable)
 local item = part(parent, name, Vector3.new(height, diameter, diameter), position, color, material, collidable)
 item.Shape = Enum.PartType.Cylinder
 item.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
 return item
end

local function corner(parent, scale)
 local item = Instance.new("UICorner")
 item.CornerRadius = UDim.new(scale or 0.2, 0)
 item.Parent = parent
end

local function outline(parent, color, thickness)
 local item = Instance.new("UIStroke")
 item.Color, item.Thickness = color or ink, thickness or 2
 item.Parent = parent
 return item
end

-- Chunky white text with a dark outline: the familiar Roblox sign look.
local function signText(parent, name, text, position, size, color, font)
 local label = Instance.new("TextLabel")
 label.Name, label.Text = name, text
 label.Position, label.Size = position, size
 label.BackgroundTransparency, label.TextScaled, label.TextWrapped = 1, true, true
 label.Font, label.TextColor3 = font or TITLE_FONT, color or Color3.new(1, 1, 1)
 label.Parent = parent
 outline(label, ink, 2)
 return label
end

-- Stud-sized billboards shrink with distance, so faraway signs never crowd the screen.
local function billboard(parent, name, position, studs, maxDistance)
 local anchor = part(parent, name, Vector3.new(1, 1, 1), position, white, nil, false)
 anchor.Transparency, anchor.CanQuery = 1, false
 local gui = Instance.new("BillboardGui")
 gui.Name, gui.Adornee, gui.Size = "Sign", anchor, UDim2.fromScale(studs.X, studs.Y)
 gui.AlwaysOnTop, gui.MaxDistance, gui.LightInfluence = false, maxDistance or 220, 0
 gui.Parent = anchor
 return gui
end

local function surface(target, face, pixelsPerStud)
 local gui = Instance.new("SurfaceGui")
 gui.Name, gui.Face, gui.Adornee = "Face_" .. face.Name, face, target
 gui.SizingMode, gui.PixelsPerStud, gui.LightInfluence = Enum.SurfaceGuiSizingMode.PixelsPerStud, pixelsPerStud or 40, 0
 gui.Parent = target
 return gui
end

-- The client spins and bobs parts carrying these attributes; the server only places them.
local function floating(item, spin, bob)
 item:SetAttribute("LobbySpin", spin)
 item:SetAttribute("LobbyBob", bob)
 return item
end

local function gem(parent, name, size, position, color)
 local item = part(parent, name, Vector3.new(size, size, size), position, color, Enum.Material.Neon, false)
 item.CanQuery = false
 item.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), 0, math.rad(45))
 return floating(item, 1.4, 0.8)
end

local function sparkles(target, color, rate)
 local emitter = Instance.new("ParticleEmitter")
 emitter.Name = "Sparkles"
 emitter.Color, emitter.LightEmission = ColorSequence.new(color, Color3.new(1, 1, 1)), 0.8
 emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
 emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
 emitter.Lifetime, emitter.Rate, emitter.Speed = NumberRange.new(1.4, 2.4), rate or 6, NumberRange.new(3, 6)
 emitter.SpreadAngle, emitter.EmissionDirection = Vector2.new(12, 12), Enum.NormalId.Top
 emitter.Parent = target
 return emitter
end

local function horizontalRange(player, portal, radius)
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return false end
 local delta = root.Position - portal
 return delta.Y >= -3 and delta.Y <= 18 and delta.X * delta.X + delta.Z * delta.Z <= radius * radius
end

function LobbyWorld.Create()
 if active and active.Folder.Parent == workspace then return active end
 -- Only replace previous geometry explicitly marked as belonging to this system.
 for _, item in ipairs(workspace:GetChildren()) do
  if item:GetAttribute("RTSLobbyGenerated") == true then item:Destroy() end
 end
 local origin = Config.Lobby.origin
 local folder = Instance.new("Folder")
 folder.Name = "AOE2_LobbyWorld"
 folder:SetAttribute("RTSLobbyGenerated", true)
 folder.Parent = workspace
 local function block(name, size, offset, color, material, collidable)
  return part(folder, name, size, origin + offset, color, material, collidable)
 end
 local function round(name, diameter, height, offset, color, material, collidable)
  return disc(folder, name, diameter, height, origin + offset, color, material, collidable)
 end

 -- Grass lawn with a checkerboard plaza on top; only the lighter tiles are separate parts.
 block("CourtyardFoundation", Vector3.new(260, 6, 240), Vector3.new(0, -3, 0), grass)
 local tileSize, plazaMin, plazaMax = 12, Vector2.new(-84, -76), Vector2.new(84, 104)
 local plazaSize = plazaMax - plazaMin
 block("Courtyard", Vector3.new(plazaSize.X, 0.3, plazaSize.Y), Vector3.new(0, 0.15, (plazaMin.Y + plazaMax.Y) / 2), white)
 block("CourtyardCurb", Vector3.new(plazaSize.X + 3, 0.2, plazaSize.Y + 3), Vector3.new(0, 0.1, (plazaMin.Y + plazaMax.Y) / 2), trim)
 for column = 0, plazaSize.X / tileSize - 1 do
  for row = 0, plazaSize.Y / tileSize - 1 do
   if (column + row) % 2 == 1 then
    local x, z = plazaMin.X + (column + 0.5) * tileSize, plazaMin.Y + (row + 0.5) * tileSize
    block("PlazaTile", Vector3.new(tileSize, 0.32, tileSize), Vector3.new(x, 0.16, z), tile, nil, false).CanQuery = false
   end
  end
 end

 -- Gardens, hedges and flower beds fill the lawn between the plaza and the walls.
 local random = Random.new(2048)
 for _, x in ipairs({ -105, 105 }) do
  block("Garden", Vector3.new(24, 0.4, 104), Vector3.new(x, 0.2, 8), Color3.fromRGB(74, 160, 64), nil, false)
  for _, z in ipairs({ -30, 15, 60 }) do
   local tree = Art.Create("Tree")
   tree.Name = "CourtyardTree"
   tree:PivotTo(CFrame.new(origin + Vector3.new(x, 0.4, z)) * tree:GetPivot())
   tree.Parent = folder
  end
  for index = 1, 18 do
   local flower = part(folder, "Flower", Vector3.new(1.4, 1.4, 1.4), origin + Vector3.new(x + random:NextNumber(-10, 10), 1, random:NextNumber(-42, 58)), flowerColors[index % #flowerColors + 1], nil, false)
   flower.Shape, flower.CanQuery = Enum.PartType.Ball, false
  end
  local side = math.sign(x)
  for _, segment in ipairs({ { -70, 18 }, { 48, 104 } }) do
   local length = segment[2] - segment[1]
   block("Hedge", Vector3.new(3, 3, length), Vector3.new(side * 89, 1.5, segment[1] + length / 2), hedge)
  end
 end

 -- Bright castle walls: white blocks, a blue trim band and clean merlons.
 for _, x in ipairs({ -127, 127 }) do
  block("SideWall", Vector3.new(5, 17, 236), Vector3.new(x, 8.5, 0), wallColor)
  block("WallTrim", Vector3.new(5.4, 1.2, 236), Vector3.new(x, 16.4, 0), trim, nil, false)
 end
 block("RearWall", Vector3.new(254, 17, 5), Vector3.new(0, 8.5, -117), wallColor)
 block("WallTrim", Vector3.new(254, 1.2, 5.4), Vector3.new(0, 16.4, -117), trim, nil, false)
 for _, x in ipairs({ -73, 73 }) do
  block("FrontWall", Vector3.new(108, 17, 5), Vector3.new(x, 8.5, 117), wallColor)
  block("WallTrim", Vector3.new(108, 1.2, 5.4), Vector3.new(x, 16.4, 117), trim, nil, false)
 end
 for x = -122, 122, 8 do
  block("RearBattlement", Vector3.new(4, 3, 5), Vector3.new(x, 18.5, -117), white)
  if math.abs(x) > 20 then block("FrontBattlement", Vector3.new(4, 3, 5), Vector3.new(x, 18.5, 117), white) end
 end
 for z = -112, 112, 8 do
  for _, x in ipairs({ -127, 127 }) do
   block("SideBattlement", Vector3.new(5, 3, 4), Vector3.new(x, 18.5, z), white)
  end
 end
 -- Round corner towers with stacked red roofs.
 for _, x in ipairs({ -127, 127 }) do
  for _, z in ipairs({ -117, 117 }) do
   round("CornerTower", 14, 26, Vector3.new(x, 13, z), white)
   round("CornerTowerTrim", 15, 1.4, Vector3.new(x, 24, z), trim, nil, false)
   round("CornerTowerRoof", 16, 2, Vector3.new(x, 27, z), roof)
   round("CornerTowerRoof", 11, 3, Vector3.new(x, 29.5, z), roof)
   round("CornerTowerRoof", 6, 3, Vector3.new(x, 32.5, z), roof)
   local top = part(folder, "TowerFinial", Vector3.new(2, 2, 2), origin + Vector3.new(x, 35, z), gold, nil, false)
   top.Shape = Enum.PartType.Ball
  end
 end
 for _, x in ipairs({ -23, 23 }) do
  block("GateTower", Vector3.new(12, 29, 12), Vector3.new(x, 14.5, 115), white)
  block("GateTowerTrim", Vector3.new(12.6, 1.4, 12.6), Vector3.new(x, 26, 115), trim, nil, false)
  block("GateTowerCap", Vector3.new(15, 2, 15), Vector3.new(x, 30, 115), roof)
  block("GateTowerCap", Vector3.new(10, 3, 10), Vector3.new(x, 32.5, 115), roof)
  block("GateTowerCap", Vector3.new(5, 3, 5), Vector3.new(x, 35.5, 115), roof)
 end
 block("GateArch", Vector3.new(36, 7, 8), Vector3.new(0, 26, 115), white)
 block("GateArchTrim", Vector3.new(36.4, 1.4, 8.4), Vector3.new(0, 23, 115), trim, nil, false)
 -- Close the courtyard boundary with a visible gate; travel happens through the queue portals.
 block("Gate", Vector3.new(34, 22, 1), Vector3.new(0, 11, 119), timber, Enum.Material.WoodPlanks)

 -- The lobby landmark has no player owner; it uses the lobby trim color.
 local castle = Art.Create("Castle", trim, false)
 castle.Name = "LobbyCastle"
 castle:SetAttribute("RTSLobbyDecoration", true)
 local _, originalBounds = castle:GetBoundingBox()
 castle:ScaleTo(64 / originalBounds.X)
 local box, bounds = castle:GetBoundingBox()
 local desired = CFrame.new(origin + Vector3.new(0, bounds.Y / 2 + 0.3, -55))
 castle:PivotTo(desired * box:Inverse() * castle:GetPivot())
 for _, item in ipairs(castle:GetDescendants()) do
  if item:IsA("BasePart") then item.CanCollide = true end
 end
 castle.Parent = folder
 local titleGui = billboard(folder, "CastleTitle", origin + Vector3.new(0, bounds.Y + 9, -55), Vector2.new(46, 9), 400)
 local title = signText(titleGui, "Title", "王國集結廣場", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.72))
 title.UIStroke.Thickness = 4
 local titleShine = Instance.new("UIGradient")
 titleShine.Rotation, titleShine.Color = 90, ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 150, 30))
 titleShine.Parent = title
 signText(titleGui, "Subtitle", "選一座傳送門，和朋友一起出征！", UDim2.fromScale(0.1, 0.72), UDim2.fromScale(0.8, 0.28), Color3.new(1, 1, 1), BODY_FONT)

 -- Fountain centerpiece with a floating star between the four portals.
 local fountain = Vector3.new(0, 0, 33)
 round("FountainBasin", 24, 2.4, fountain + Vector3.new(0, 1.2, 0), white)
 round("FountainRim", 25, 0.5, fountain + Vector3.new(0, 2.5, 0), trim, nil, false)
 local pool = round("FountainWater", 21, 0.3, fountain + Vector3.new(0, 2.3, 0), water, nil, false)
 pool.Transparency, pool.CanQuery = 0.2, false
 round("FountainPillar", 4, 7, fountain + Vector3.new(0, 5.5, 0), white)
 round("FountainBowl", 9, 1, fountain + Vector3.new(0, 9.2, 0), white)
 local spray = round("FountainSpray", 7.4, 0.3, fountain + Vector3.new(0, 9.75, 0), water, nil, false)
 spray.Transparency, spray.CanQuery = 0.2, false
 local star = gem(folder, "FountainStar", 3.4, origin + fountain + Vector3.new(0, 14.5, 0), gold)
 sparkles(star, gold, 4)

 -- Classic spawn pad where every avatar arrives.
 local spawnPoint = Vector3.new(Config.Lobby.spawnOffset.X, 0, Config.Lobby.spawnOffset.Z)
 local pad = block("SpawnPad", Vector3.new(12, 1, 12), spawnPoint + Vector3.new(0, 0.5, 0), Color3.fromRGB(163, 162, 165))
 local decal = Instance.new("Decal")
 decal.Name, decal.Face, decal.Texture = "SpawnMark", Enum.NormalId.Top, "rbxasset://textures/SpawnLocation.png"
 decal.Parent = pad
 block("SpawnPadRim", Vector3.new(14, 0.6, 14), spawnPoint + Vector3.new(0, 0.3, 0), trim, nil, false)

 -- Welcome arch over the avenue; its sign faces the spawn pad.
 for _, x in ipairs({ -18, 18 }) do
  block("WelcomePost", Vector3.new(2.4, 19, 2.4), Vector3.new(x, 9.5, 74), white)
  local cap = part(folder, "WelcomePostCap", Vector3.new(2.6, 2.6, 2.6), origin + Vector3.new(x, 20, 74), gold, nil, false)
  cap.Shape = Enum.PartType.Ball
 end
 local board = block("WelcomeBoard", Vector3.new(34, 6.5, 1), Vector3.new(0, 15.5, 74), trim)
 local boardFront = surface(board, Enum.NormalId.Back)
 local boardTitle = signText(boardFront, "Welcome", "歡迎來到集結廣場", UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.48))
 boardTitle.UIStroke.Thickness = 4
 local instructions = signText(boardFront, "Instructions", "走進彩色光圈加入匹配點\n也可使用畫面下方的房間卡片", UDim2.fromScale(0.06, 0.56), UDim2.fromScale(0.88, 0.38), Color3.new(1, 1, 1), BODY_FONT)
 signText(surface(board, Enum.NormalId.Front), "Farewell", "祝你凱旋歸來！", UDim2.fromScale(0.05, 0.15), UDim2.fromScale(0.9, 0.7))

 -- Flagpoles in the four portal colors at the plaza corners.
 local portalList = Config.Lobby.portals
 for index, point in ipairs({ Vector2.new(84, 104), Vector2.new(-84, -76), Vector2.new(84, -76), Vector2.new(-84, 104) }) do
  local color = portalList[index] and portalList[index].color or trim
  block("FlagBase", Vector3.new(3, 1, 3), Vector3.new(point.X, 0.5, point.Y), white)
  round("Flagpole", 0.8, 22, Vector3.new(point.X, 11, point.Y), white)
  local knob = part(folder, "FlagKnob", Vector3.new(1.6, 1.6, 1.6), origin + Vector3.new(point.X, 22.4, point.Y), gold, nil, false)
  knob.Shape = Enum.PartType.Ball
  block("Flag", Vector3.new(7, 4.5, 0.3), Vector3.new(point.X - math.sign(point.X) * 3.9, 19, point.Y), color, nil, false)
 end

 local portals = {}
 for _, data in ipairs(Config.Lobby.portals) do
  local portal, portalRadius = origin + data.offset, Config.Lobby.portalRadius
  local light = data.color:Lerp(Color3.new(1, 1, 1), 0.55)
  local model = Instance.new("Model")
  model.Name, model.Parent = "Portal_" .. data.id, folder
  model:SetAttribute("PortalId", data.id)
  disc(model, "PortalRim", portalRadius * 2 + 2, 0.5, portal + Vector3.new(0, 0.55, 0), data.color)
  disc(model, "PortalDais", portalRadius * 2, 0.6, portal + Vector3.new(0, 0.65, 0), white)
  local ring = disc(model, "PortalRing", portalRadius * 2 - 1, 0.15, portal + Vector3.new(0, 1.03, 0), data.color, Enum.Material.Neon, false)
  ring.CanQuery = false
  local center = disc(model, "PortalCenter", portalRadius * 2 - 5, 0.15, portal + Vector3.new(0, 1.08, 0), light, nil, false)
  center.CanQuery = false
  sparkles(center, data.color, 8)
  for _, x in ipairs({ -portalRadius, portalRadius }) do
   part(model, "PortalPillarBase", Vector3.new(6, 2, 6), portal + Vector3.new(x, 2, -3), white)
   part(model, "PortalPillar", Vector3.new(4, 20, 4), portal + Vector3.new(x, 12, -3), data.color)
   part(model, "PortalRune", Vector3.new(1.2, 14, 0.3), portal + Vector3.new(x, 12, -0.9), light, Enum.Material.Neon, false)
  end
  part(model, "PortalLintel", Vector3.new(portalRadius * 2 + 8, 4.5, 5), portal + Vector3.new(0, 24, -3), data.color)
  part(model, "PortalLintelTrim", Vector3.new(portalRadius * 2 + 9, 1, 5.4), portal + Vector3.new(0, 21.6, -3), white, nil, false)
  local lintelName = part(model, "PortalNamePlate", Vector3.new(portalRadius * 2, 3.4, 0.4), portal + Vector3.new(0, 24, -0.4), data.color, nil, false)
  lintelName.CanQuery = false
  signText(surface(lintelName, Enum.NormalId.Back), "Name", data.name, UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.84))
  local veil = part(model, "PortalLight", Vector3.new(portalRadius * 2 - 4, 19, 0.35), portal + Vector3.new(0, 11.5, -3), data.color, Enum.Material.ForceField, false)
  veil.CanQuery = false
  local glow = Instance.new("PointLight")
  glow.Color, glow.Range, glow.Brightness = data.color, 30, 1.4
  glow.Parent = veil
  gem(model, "PortalGem", 3, portal + Vector3.new(0, 30, -3), data.color)
  local promptAnchor = part(model, "QueuePromptAnchor", Vector3.new(1, 1, 1), portal + Vector3.new(0, 3, 0), data.color, nil, false)
  promptAnchor.Transparency, promptAnchor.CanQuery = 1, false
  local prompt = Instance.new("ProximityPrompt")
  prompt.Name, prompt.ActionText, prompt.ObjectText = "JoinQueue", "加入匹配", data.name
  prompt.KeyboardKeyCode, prompt.HoldDuration = Enum.KeyCode.E, 0.3
  prompt.MaxActivationDistance, prompt.RequiresLineOfSight = Config.Lobby.portalUseRange, false
  prompt.Parent = promptAnchor
  -- Rounded status card: colored header, current mode and a big player counter.
  local statusGui = billboard(model, "PortalStatus", portal + Vector3.new(0, 38, -3), Vector2.new(20, 9))
  local card = Instance.new("Frame")
  card.Name, card.Size, card.BackgroundColor3, card.BackgroundTransparency = "Card", UDim2.fromScale(1, 1), ink, 0.12
  card.Parent = statusGui
  corner(card, 0.16)
  outline(card, data.color, 3)
  local header = Instance.new("Frame")
  header.Name, header.Size, header.BackgroundColor3 = "Header", UDim2.fromScale(1, 0.38), data.color
  header.Parent = card
  corner(header, 0.4)
  local headerFill = Instance.new("Frame")
  headerFill.Name, headerFill.BorderSizePixel, headerFill.BackgroundColor3 = "HeaderFill", 0, data.color
  headerFill.Position, headerFill.Size = UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5)
  headerFill.Parent = header
  signText(header, "Title", data.name, UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.8))
  local mode = signText(card, "Mode", "走進光圈或按 E 加入", UDim2.fromScale(0.06, 0.42), UDim2.fromScale(0.88, 0.25), Color3.new(1, 1, 1), BODY_FONT)
  local count = signText(card, "Count", "玩家 0 / 2　準備 0", UDim2.fromScale(0.06, 0.69), UDim2.fromScale(0.88, 0.25), gold)
  portals[data.id] = { Position = portal, Prompt = prompt, Mode = mode, Count = count, Data = data }
 end
 local firstPortal = portals.Room1
 local object = { Folder = folder, Portals = portals, Prompt = firstPortal.Prompt, PortalPosition = firstPortal.Position }
 function object:SpawnCFrame()
  local spawn = origin + Config.Lobby.spawnOffset
  return CFrame.lookAt(spawn, origin + Vector3.new(0, spawn.Y - origin.Y, -50))
 end
 function object:QueueCFrame(index, count, roomId)
  local entry = portals[roomId or "Room1"] or firstPortal
  local portal = entry.Position
  local angle = ((index or 1) - 1) / math.max(count or 1, 1) * math.pi * 2
  local point = portal + Vector3.new(math.sin(angle) * 5, 4, math.cos(angle) * 5)
  return CFrame.lookAt(point, Vector3.new(portal.X, point.Y, portal.Z - 20))
 end
 function object:ContainsPortal(player, roomId)
  local entry = portals[roomId or "Room1"]
  return entry ~= nil and horizontalRange(player, entry.Position, Config.Lobby.portalRadius)
 end
 function object:NearPortal(player, roomId)
  local entry = portals[roomId or "Room1"]
  return entry ~= nil and horizontalRange(player, entry.Position, Config.Lobby.portalUseRange)
 end
 function object:PortalAt(player)
  for _, data in ipairs(Config.Lobby.portals) do
   if self:ContainsPortal(player, data.id) then return data.id end
  end
  return nil
 end
 function object:SetStatus(count, expected, ready, phase, roomId, settings)
  local entry = portals[roomId or "Room1"]
  if not entry then return end
  local waiting = phase == "Configuring" or phase == "Waiting" or phase == "Lobby" or phase == nil
  entry.Prompt.Enabled = waiting and (count or 0) < (expected or 1)
  local stage = phase == "Starting" and "正在建立新戰場" or (phase == "Playing" and "對局進行中" or (phase == "Ended" and "等待返回大廳" or (phase == "Configuring" and ((count or 0) > 0 and "房主設定中" or "等待房主設定") or "等待玩家準備")))
  entry.Mode.Text = GameModeRules.label(settings) .. " · " .. stage
  entry.Count.Text = string.format("玩家 %d / %d　準備 %d", count or 0, expected or 2, ready or 0)
  instructions.Text = "走進光圈，由房主設定房間\n全員準備後一起前往全新戰場"
 end
 active = object
 return object
end

-- 對戰 place 沒有城堡廣場：保留相同介面，但不生成任何幾何、沒有匹配點。
function LobbyWorld.Stub()
 local object = {Portals = {}}
 function object:SpawnCFrame() return CFrame.new(Config.Lobby.origin + Config.Lobby.spawnOffset) end
 function object:QueueCFrame() return self:SpawnCFrame() end
 function object:ContainsPortal() return false end
 function object:NearPortal() return false end
 function object:PortalAt() return nil end
 function object:SetStatus() end
 return object
end

return LobbyWorld
