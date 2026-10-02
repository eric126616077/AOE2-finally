-- A separate walkable staging courtyard. These decorations are never RTS buildings.
local Config = require(game.ReplicatedStorage.GameData.GameConfig)
local Art = require(game.ReplicatedStorage.Shared.Art)
local LobbyWorld = {}
local active
local stone = Color3.fromRGB(152, 155, 153)
local paleStone = Color3.fromRGB(198, 191, 166)
local timber = Color3.fromRGB(89, 65, 43)
local blue = Color3.fromRGB(87, 163, 216)

local function part(parent, name, size, position, color, material, collidable)
 local item = Instance.new("Part")
 item.Name, item.Size, item.Position = name, size, position
 item.Color, item.Material = color, material or Enum.Material.SmoothPlastic
 item.Anchored, item.CanCollide, item.CanTouch = true, collidable ~= false, false
 item.TopSurface, item.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
 item.Parent = parent
 return item
end

local function label(parent, name, position, size, text, textColor)
 local anchor = part(parent, name, Vector3.new(1, 1, 1), position, paleStone, nil, false)
 anchor.Transparency, anchor.CanQuery = 1, false
 local gui = Instance.new("BillboardGui")
 gui.Name, gui.Adornee, gui.Size = "Sign", anchor, UDim2.fromOffset(size.X, size.Y)
 gui.AlwaysOnTop, gui.MaxDistance, gui.LightInfluence = false, 180, 0
 gui.Parent = anchor
 local textLabel = Instance.new("TextLabel")
 textLabel.Size, textLabel.BackgroundTransparency = UDim2.fromScale(1, 1), 1
 textLabel.Font, textLabel.TextSize = Enum.Font.SourceSansBold, 25
 textLabel.TextColor3, textLabel.TextStrokeColor3 = textColor or paleStone, Color3.fromRGB(27, 35, 41)
 textLabel.TextStrokeTransparency, textLabel.TextWrapped = 0.1, true
 textLabel.Text, textLabel.Parent = text, gui
 return textLabel
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

 block("CourtyardFoundation", Vector3.new(260, 6, 240), Vector3.new(0, -3, 0), stone, Enum.Material.Slate)
 block("Courtyard", Vector3.new(254, 0.25, 234), Vector3.new(0, 0.125, 0), Color3.fromRGB(133, 137, 126), Enum.Material.Cobblestone)
 block("CastleAvenue", Vector3.new(30, 0.12, 170), Vector3.new(0, 0.31, 20), paleStone, Enum.Material.Slate)
 for _, x in ipairs({ -105, 105 }) do
  block("Garden", Vector3.new(24, 0.4, 104), Vector3.new(x, 0.45, 8), Color3.fromRGB(86, 118, 65), Enum.Material.Grass, false)
  for _, z in ipairs({ -30, 15, 60 }) do
   local tree = Art.Create("Tree")
   tree.Name = "CourtyardTree"
   tree:PivotTo(CFrame.new(origin + Vector3.new(x, 0.5, z)) * tree:GetPivot())
   tree.Parent = folder
  end
 end
 for _, x in ipairs({ -127, 127 }) do
  block("SideWall", Vector3.new(5, 17, 236), Vector3.new(x, 8.5, 0), stone, Enum.Material.Brick)
 end
 block("RearWall", Vector3.new(254, 17, 5), Vector3.new(0, 8.5, -117), stone, Enum.Material.Brick)
 for _, x in ipairs({ -73, 73 }) do
  block("FrontWall", Vector3.new(108, 17, 5), Vector3.new(x, 8.5, 117), stone, Enum.Material.Brick)
 end
 -- Crenellations and front gate give arriving avatars a recognizable castle plaza.
 for x = -122, 122, 8 do
  block("RearBattlement", Vector3.new(4, 3, 5), Vector3.new(x, 18.5, -117), paleStone, Enum.Material.Brick)
  if math.abs(x) > 20 then block("FrontBattlement", Vector3.new(4, 3, 5), Vector3.new(x, 18.5, 117), paleStone, Enum.Material.Brick) end
 end
 for z = -112, 112, 8 do
  for _, x in ipairs({ -127, 127 }) do
   block("SideBattlement", Vector3.new(5, 3, 4), Vector3.new(x, 18.5, z), paleStone, Enum.Material.Brick)
  end
 end
 for _, x in ipairs({ -23, 23 }) do
  block("GateTower", Vector3.new(12, 29, 12), Vector3.new(x, 14.5, 115), paleStone, Enum.Material.Brick)
  block("GateTowerCap", Vector3.new(15, 2, 15), Vector3.new(x, 30, 115), stone, Enum.Material.Slate)
 end
 block("GateArch", Vector3.new(36, 7, 8), Vector3.new(0, 26, 115), paleStone, Enum.Material.Brick)
 -- Close the courtyard boundary with a visible gate; travel happens through the queue portal.
 block("Gate", Vector3.new(34, 22, 1), Vector3.new(0, 11, 119), timber, Enum.Material.WoodPlanks)

 -- The lobby landmark has no player owner; retain its neutral material colors.
 local castle = Art.Create("Castle", blue, false)
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
 label(folder, "CastleTitle", origin + Vector3.new(0, 53, -55), Vector2.new(340, 65), "王國集結廣場", paleStone)

 local portals = {}
 for _, data in ipairs(Config.Lobby.portals) do
  local portal, portalRadius = origin + data.offset, Config.Lobby.portalRadius
  local model = Instance.new("Model")
  model.Name, model.Parent = "Portal_"..data.id, folder
  model:SetAttribute("PortalId",data.id)
  local dais = part(model, "PortalDais", Vector3.new(0.6, portalRadius * 2, portalRadius * 2), portal + Vector3.new(0, 0.65, 0), Color3.fromRGB(46, 68, 83), Enum.Material.Slate)
  dais.Shape = Enum.PartType.Cylinder
  dais.CFrame = CFrame.new(dais.Position) * CFrame.Angles(0, 0, math.pi / 2)
  local ring = part(model, "PortalRing", Vector3.new(0.15, portalRadius * 2 - 1, portalRadius * 2 - 1), portal + Vector3.new(0, 1.03, 0), data.color, Enum.Material.Neon, false)
  ring.Shape, ring.CanQuery = Enum.PartType.Cylinder, false
  ring.CFrame = CFrame.new(ring.Position) * CFrame.Angles(0, 0, math.pi / 2)
  for _, x in ipairs({ -portalRadius, portalRadius }) do
   part(model, "PortalPillar", Vector3.new(3, 23, 4), portal + Vector3.new(x, 11.5, -3), paleStone, Enum.Material.Marble)
   part(model, "PortalRune", Vector3.new(0.3, 15, 4.2), portal + Vector3.new(x, 13, -3), data.color, Enum.Material.Neon, false)
  end
  part(model, "PortalLintel", Vector3.new(portalRadius * 2 + 6, 4, 4), portal + Vector3.new(0, 24, -3), paleStone, Enum.Material.Marble)
  local veil = part(model, "PortalLight", Vector3.new(portalRadius * 2 - 3, 21, 0.35), portal + Vector3.new(0, 11, -3), data.color, Enum.Material.Neon, false)
  veil.Transparency, veil.CanQuery = 0.78, false
  local light = Instance.new("PointLight")
  light.Color, light.Range, light.Brightness = data.color, 30, 1.1
  light.Parent = veil
  local promptAnchor = part(model, "QueuePromptAnchor", Vector3.new(1, 1, 1), portal + Vector3.new(0, 3, 0), data.color, nil, false)
  promptAnchor.Transparency, promptAnchor.CanQuery = 1, false
  local prompt = Instance.new("ProximityPrompt")
  prompt.Name, prompt.ActionText, prompt.ObjectText = "JoinQueue", "加入匹配", data.name
  prompt.KeyboardKeyCode, prompt.HoldDuration = Enum.KeyCode.E, 0.3
  prompt.MaxActivationDistance, prompt.RequiresLineOfSight = Config.Lobby.portalUseRange, false
  prompt.Parent = promptAnchor
  local status = label(model, "PortalStatus", portal + Vector3.new(0, 32, 0), Vector2.new(320, 104), data.name.."\n走進光圈或按 E 加入", data.color)
  status.TextSize=20
  portals[data.id] = {Position=portal,Prompt=prompt,Status=status,Data=data}
 end
 local instructions = label(folder, "CourtyardInstructions", origin + Vector3.new(0, 10, 93), Vector2.new(420, 75), "選擇匹配點，準備後前往新戰場\n也可使用畫面上的模式卡片", paleStone)
 local firstPortal=portals.Room1
 local object = { Folder = folder, Portals = portals, Prompt = firstPortal.Prompt, PortalPosition = firstPortal.Position }
 function object:SpawnCFrame()
  local spawn = origin + Config.Lobby.spawnOffset
  return CFrame.lookAt(spawn, origin + Vector3.new(0,spawn.Y-origin.Y,-50))
 end
 function object:QueueCFrame(index, count, roomId)
  local entry=portals[roomId or "Room1"] or firstPortal
  local portal=entry.Position
  local angle = ((index or 1) - 1) / math.max(count or 1, 1) * math.pi * 2
  local point = portal + Vector3.new(math.sin(angle) * 5, 4, math.cos(angle) * 5)
  return CFrame.lookAt(point, Vector3.new(portal.X, point.Y, portal.Z - 20))
 end
 function object:ContainsPortal(player,roomId)
  local entry=portals[roomId or "Room1"]
  return entry~=nil and horizontalRange(player, entry.Position, Config.Lobby.portalRadius)
 end
 function object:NearPortal(player,roomId)
  local entry=portals[roomId or "Room1"]
  return entry~=nil and horizontalRange(player, entry.Position, Config.Lobby.portalUseRange)
 end
 function object:PortalAt(player)
  for _,data in ipairs(Config.Lobby.portals) do
   if self:ContainsPortal(player,data.id) then return data.id end
  end
  return nil
 end
 function object:SetStatus(count, expected, ready, phase, roomId, settings)
  local entry=portals[roomId or "Room1"]
  if not entry then return end
  local waiting = phase == "Configuring" or phase == "Waiting" or phase == "Lobby" or phase == nil
  entry.Prompt.Enabled = waiting and (count or 0)<(expected or 1)
  local stage = phase == "Starting" and "正在建立新戰場" or (phase == "Playing" and "對局進行中" or (phase == "Ended" and "等待返回大廳" or (phase == "Configuring" and ((count or 0)>0 and "房主設定中" or "等待房主設定") or "等待玩家準備")))
  local names={FFA="各自為戰",Teams="分隊對戰",CoopAI="合作對電腦"}
  local mode=settings and names[settings.teamMode] or "各自為戰"
  entry.Status.Text = string.format("%s\n%s · %s\n玩家 %d / %d　準備 %d", entry.Data.name,mode,stage,count or 0,expected or 2,ready or 0)
  instructions.Text = "進入匹配點，由房主分步設定房間\n所有玩家準備後，一起前往全新戰場"
 end
 active = object
 return object
end

return LobbyWorld
