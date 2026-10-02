-- Explicit opt-in test place only. Never mapped by default.project.json.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local coord = RS:WaitForChild("FeedbackValidationCoord", 20)
assert(coord, "[FEEDBACK_VALIDATION FAIL] 測試協調器未就緒")
local stage = coord:WaitForChild("Stage", 10)
local RUN_ID = "feedback-real-clients-20260930-r2"
local host, peer, role
local function mark(name)
 stage:FireServer(name)
end
local function waitFor(predicate, seconds, message)
 local deadline = os.clock() + seconds
 repeat
  assert(not host or not host:GetAttribute("FV_Failed"), "[FEEDBACK_VALIDATION FAIL] 房主測試已失敗：" .. message)
  assert(not peer or not peer:GetAttribute("FV_Failed"), "[FEEDBACK_VALIDATION FAIL] 第二端測試已失敗：" .. message)
  if predicate() then return end
  assert(os.clock() < deadline, "[FEEDBACK_VALIDATION FAIL] " .. message .. "等待逾時")
  task.wait(.1)
 until false
end
local function both(name)
 waitFor(function() return host:GetAttribute("FV_" .. name) and peer:GetAttribute("FV_" .. name) end, 1500, "等待兩端 " .. name)
end
task.spawn(function()
 local ok, err = xpcall(function()
  waitFor(function() return #Players:GetPlayers() == 2 and workspace:GetAttribute("MatchPhase") == "Lobby" end, 90, "新大廳與兩名真實玩家")
  local participants = Players:GetPlayers()
  table.sort(participants, function(a,b) return a.UserId < b.UserId end)
  host, peer = participants[1], participants[2]
  role = player == host and "host" or "peer"
  print(string.format("[FEEDBACK_VALIDATION START] run=%s role=%s viewer=%d host=%d peer=%d", RUN_ID, role, player.UserId, host.UserId, peer.UserId))
  local multi = require(RS.Shared.MultiplayerTests)
  local feedback = require(RS.Shared.FeedbackMultiplayerTests)
  local battle = require(RS.Shared.FeedbackBattleTests)
  if role == "host" then
   multi.RunHost()
   mark("HostReady")
   waitFor(function() return peer:GetAttribute("FV_PeerArmed") end, 90, "另一端所有權驗證与回饋觀察器")
   feedback.RunActor()
  else
   waitFor(function() return workspace:GetAttribute("HostUserId") == host.UserId and workspace:GetAttribute("LobbyExpectedPlayers") == 2 end, 30, "房主設定雙人集合")
   multi.JoinLobby()
   waitFor(function() return host:GetAttribute("FV_HostReady") end, 90, "房主正常施工與訓練完成")
   multi.RunOwnership()
   mark("OwnershipDone")
   feedback.RunPeer({onArmed=function() mark("PeerArmed") end})
  end
  mark("MultiDone")
  both("MultiDone")
  battle.Prepare(role, {deadlineSeconds=1500})
  mark("Prepared")
  both("Prepared")
  if role == "host" then
   waitFor(function() return peer:GetAttribute("FV_BattleArmed") end, 30, "第二端戰鬥觀察器")
   battle.RunHost({prepared=true, deadlineSeconds=1500})
  else
   require(RS.Shared.FeedbackRepairTests).Arm()
   battle.ObservePeer({deadlineSeconds=1500, onArmed=function() mark("BattleArmed") end})
  end
  mark("BattleDone")
  both("BattleDone")
  if role == "peer" then
   require(RS.Shared.FeedbackRepairTests).Run()
   mark("RepairDone")
  else
   waitFor(function() return peer:GetAttribute("FV_RepairDone") end, 240, "另一端真正受損建築的正常修復回饋")
  end
  print(string.format("[FEEDBACK_VALIDATION COMPLETE] run=%s role=%s viewer=%d；雙人採集、交貨、靜音、真實戰鬥與修復流程完成", RUN_ID, role, player.UserId))
  if role == "peer" then
   feedback.ObserveCleanupClient()
   multi.ObserveCleanupClient(host.UserId)
   mark("CleanupArmed")
  end
 end, debug.traceback)
 if not ok then
  mark("Failed")
  warn(string.format("[FEEDBACK_VALIDATION FAIL] run=%s role=%s viewer=%d\n%s", RUN_ID, tostring(role), player.UserId, tostring(err)))
 end
end)

