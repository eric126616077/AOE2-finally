-- 大廳專用動態：只轉動與上下浮動 LobbyWorld 標記 LobbySpin 的寶石，不遍歷整個 Workspace。
-- 只在玩家位於大廳時連接每幀更新；減少動態時寶石回到伺服器擺放的位置。
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local FOLDER_NAME = "AOE2_LobbyWorld"
local items = {}
local connection

local function track(item)
 if items[item] or not item:IsA("BasePart") or type(item:GetAttribute("LobbySpin")) ~= "number" then return end
 local base = item.CFrame
 items[item] = {position = base.Position, rotation = base - base.Position, spin = item:GetAttribute("LobbySpin"),
  bob = item:GetAttribute("LobbyBob") or 0, phase = base.Position.X * 0.11 + base.Position.Z * 0.07}
end

local function watch(folder)
 if folder.Name ~= FOLDER_NAME or not folder:IsA("Folder") then return end
 for _, item in ipairs(folder:GetDescendants()) do track(item) end
 folder.DescendantAdded:Connect(track)
end

local function rest()
 for item, data in pairs(items) do
  if item.Parent then item.CFrame = CFrame.new(data.position) * data.rotation else items[item] = nil end
 end
end

local function step()
 local now = os.clock()
 for item, data in pairs(items) do
  if item.Parent then
   local offset = Vector3.new(0, math.sin(now * 1.6 + data.phase) * data.bob, 0)
   item.CFrame = CFrame.new(data.position + offset) * CFrame.Angles(0, now * data.spin, 0) * data.rotation
  else
   items[item] = nil
  end
 end
end

local function refresh()
 local active = player:GetAttribute("InLobby") == true and player:GetAttribute("ReducedMotion") ~= true
 if active and not connection then
  connection = RunService.Heartbeat:Connect(step)
 elseif not active and connection then
  connection:Disconnect(); connection = nil
  rest()
 end
end

workspace.ChildAdded:Connect(watch)
local existing = workspace:FindFirstChild(FOLDER_NAME)
if existing then watch(existing) end
player:GetAttributeChangedSignal("InLobby"):Connect(refresh)
player:GetAttributeChangedSignal("ReducedMotion"):Connect(refresh)
refresh()
