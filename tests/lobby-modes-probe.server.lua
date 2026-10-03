-- Opt-in only through lobby-modes-validation.project.json; never mapped by the normal project.
-- Studio-only shortcut for a chapter victory: remove every server AI model so the normal
-- elimination sweep defeats the AI and the real endMatch / story progress code runs.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local probe=Instance.new("RemoteEvent")
probe.Name="LobbyModesProbe"
probe.Parent=RS
-- Server AI IDs start at -10001; Studio test players are small negative IDs.
local function isAI(id) return type(id)=="number" and id<=-10000 end
probe.OnServerEvent:Connect(function(player,action)
 if action~="DefeatAI" or workspace:GetAttribute("MatchPhase")~="Playing" then return end
 local removed=0
 for _,name in ipairs({"Units","Buildings"}) do
  local folder=workspace:FindFirstChild(name)
  for _,model in ipairs(folder and folder:GetChildren() or {}) do
   if isAI(model:GetAttribute("OwnerId")) then model:Destroy(); removed+=1 end
  end
 end
 print("[LOBBY_MODES probe] "..player.Name.." removed "..removed.." AI models")
end)
