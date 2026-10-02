-- Test-only harness. This is never mapped by the normal project.
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local function untilTrue(predicate,seconds,message)
 local deadline=os.clock()+seconds
 repeat if predicate() then return end; Run.Heartbeat:Wait() until os.clock()>deadline
 error("[UNIT_ICON_HARNESS FAIL] "..message)
end
untilTrue(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30,"初始化逾時")
require(RS.Shared.LobbyTests).Start({size="Small",aiCount=0,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest"})
untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,30,"開始測試局逾時")
local worker
for _,unit in ipairs(workspace.Units:GetChildren()) do
 if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then worker=unit; break end
end
assert(worker,"[UNIT_ICON_HARNESS FAIL] 缺少村民")
for _,key in ipairs({"Range","AttackInterval","CarryCapacity","GatherRate_food","GatherRate_wood","GatherRate_gold","GatherRate_stone"}) do
 assert(type(worker:GetAttribute(key))=="number","[UNIT_ICON_HARNESS FAIL] 伺服器未同步 "..key)
end
print("[UNIT_ICON_HARNESS PASS] 真實伺服器同步單位射程、攻擊間隔、攜帶容量與四種採集效率")
local count=require(RS.Shared.UnitIconTests).Run()
print("[UNIT_ICON_HARNESS COMPLETE]",count,"touch",game:GetService("UserInputService").TouchEnabled)
-- Leave the real starting villagers selected for manual box selection / portrait clicks.
local selected={}
for _,unit in ipairs(workspace.Units:GetChildren()) do
 if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then table.insert(selected,unit) end
end
player.PlayerGui.AOE2_MainGUI.RTSSelectionProbe:Invoke(selected)
