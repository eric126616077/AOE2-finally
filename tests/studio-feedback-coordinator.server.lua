-- 僅供獨立 Studio 驗證專案映射；default.project.json 不映射此檔。
-- 跨客戶端只交換測試階段，不修改遊戲資源、單位、HP、位置或對局屬性。
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local stages = {
 PeerArmed=true,
 HostReady=true,
 MultiDone=true,
 Prepared=true,
 BattleArmed=true,
 BattleDone=true,
 RepairDone=true,
 CleanupArmed=true,
 Failed=true,
 OwnershipDone=true,
}
local existing = RS:FindFirstChild("FeedbackValidationCoord")
assert(existing == nil, "Studio 回饋協調器已存在；請使用新的驗證工作階段")
local folder = Instance.new("Folder")
folder.Name = "FeedbackValidationCoord"
local stageEvent = Instance.new("RemoteEvent")
stageEvent.Name = "Stage"
stageEvent.Parent = folder
folder.Parent = RS

-- 同一玩家同一階段限制每 0.05 秒一次；不同合法階段可緊接發布，避免遺失握手。
local lastByPlayer = {}
local stageConnection = stageEvent.OnServerEvent:Connect(function(player, stage)
 if player.Parent ~= Players or typeof(stage) ~= "string" or not stages[stage] then return end
 local now = os.clock()
 local last = lastByPlayer[player]
 if last and last[stage] and now-last[stage] < 0.05 then return end
 if not last then last={}; lastByPlayer[player]=last end
 last[stage] = now
 player:SetAttribute("FV_" .. stage, true)
end)
local leaveConnection = Players.PlayerRemoving:Connect(function(player)
 lastByPlayer[player] = nil
end)
script.Destroying:Once(function()
 stageConnection:Disconnect()
 leaveConnection:Disconnect()
 table.clear(lastByPlayer)
 -- 此協調器自己建立的暫存資料才可移除。
 folder:Destroy()
end)
