-- 明確呼叫的 Studio 雙人客戶端測試。會使用正常指令建屋、訓練；不提供管理遠端。
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Tests = {}

local function context()
 assert(RunService:IsStudio() and RunService:IsClient(), "只能在 Studio 客戶端執行雙人測試。")
 return Players.LocalPlayer, RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
end
local function check(condition, message)
 assert(condition, "[RTS_MULTI FAIL] "..message)
 print("[RTS_MULTI PASS] "..message)
end
local function awaitCondition(predicate, seconds, message)
 local deadline = os.clock()+seconds
 repeat
  if predicate() then check(true, message); return end
  task.wait(0.1)
 until os.clock()>=deadline
 check(false, message)
end
local function owned(parent, id, kind)
 local result = {}
 for _, model in ipairs(parent:GetChildren()) do
  if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id
   and (not kind or model:GetAttribute("BuildingType")==kind or model:GetAttribute("UnitType")==kind) then
   table.insert(result, model)
  end
 end
 return result
end
local function base(id)
 return owned(workspace.Buildings, id, "TownCenter")[1]
end
local function snapshot(player)
 local result = {}
 for _, key in ipairs({"food", "wood", "gold", "stone"}) do result[key]=player:GetAttribute(key) end
 return result
end
local function sameBalances(player, balances)
 for key,value in pairs(balances) do if player:GetAttribute(key)~=value then return false end end
 return true
end
local function clearHouseLocation(player)
 local Config = require(RS.GameData.GameConfig)
 local Grid = require(RS.Shared.Grid)
 local data, home = Config.Buildings.House, player:GetAttribute("HomePosition")
 local params = OverlapParams.new()
 params.FilterType = Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances = {workspace.AOE2_Ground, workspace.RTSScenery}
 for radius=32,72,8 do
  for index=0,15 do
   local angle=index*math.pi/8
   local pos=Grid.snap(home+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius), data.size)
   local blocked=false
   for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*8-0.2,data.height,data.size.Y*8-0.2),params)) do
    if part.CanCollide or part:IsDescendantOf(workspace.Buildings) or part:IsDescendantOf(workspace.Resources) or part:IsDescendantOf(workspace.Units) then blocked=true; break end
   end
   if not blocked and Grid.inBounds(pos,data.size) then return pos end
  end
 end
 error("雙人測試找不到房屋位置。")
end

-- 先啟動兩個 Studio 玩家。在房主客戶端 Command Bar 以 task.spawn 呼叫。
-- 不等待其他玩家加入；未加入兩人時立即指出缺少的前置條件。
function Tests.RunHost()
 local player,command = context()
 check(#Players:GetPlayers()==2, "兩名真實 Studio 玩家已加入")
 check(workspace:GetAttribute("MatchPhase")=="Lobby", "雙人測試從新大廳開始")
 check(workspace:GetAttribute("HostUserId")==player.UserId, "此客戶端是房主")
 command:FireServer("StartMatch", {size="Small", aiCount=0, difficulty="Easy", population=100, startingResources="Rich", victory="Conquest"})
 awaitCondition(function()
  if workspace:GetAttribute("MatchPhase")~="Playing" then return false end
  for _,participant in ipairs(Players:GetPlayers()) do
   if not base(participant.UserId) or #owned(workspace.Units,participant.UserId)<4 then return false end
  end
  return true
 end,12,"雙方市鎮中心、三名村民與斥候完整複製")
 check(workspace:GetAttribute("AICount")==0 and #RS.RTSFactions:GetChildren()==0, "雙人局沒有額外電腦")
 check(not workspace.StreamingEnabled, "兩端使用完整場景複製")
 local pos=clearHouseLocation(player)
 local oldWood=player:GetAttribute("wood")
 command:FireServer("Build","House",pos)
 local house
 awaitCondition(function()
  for _,candidate in ipairs(owned(workspace.Buildings,player.UserId,"House")) do
   local p=candidate:GetPivot().Position
   if (Vector3.new(p.X,0,p.Z)-pos).Magnitude<1 then house=candidate; return true end
  end
  return false
 end,5,"房主的施工實例由伺服器建立")
 awaitCondition(function() return house:GetAttribute("Complete")==true end,25,"房主村民完成施工")
 check(player:GetAttribute("wood")==oldWood-25, "房主建屋僅扣款一次")
 local count=#owned(workspace.Units,player.UserId)
 local oldFood=player:GetAttribute("food")
 command:FireServer("Train",base(player.UserId),"villager")
 awaitCondition(function() return #owned(workspace.Units,player.UserId)==count+1 end,18,"房主正常訓練村民")
 check(player:GetAttribute("food")==oldFood-50, "房主訓練扣款同步")
 print("[RTS_MULTI HOST READY] 可在第二客戶端執行 RunOwnership，再於存留客戶端呼叫 ObserveCleanupClient 後關閉另一玩家。")
 return true
end

-- 大廳時驗證非房主不能開局；對局時驗證跨玩家所有權與拒絕非法請求。
function Tests.RunOwnership()
 local player,command = context()
 check(workspace:GetAttribute("HostUserId")~=player.UserId, "此客戶端是非房主")
 if workspace:GetAttribute("MatchPhase")=="Lobby" then
  command:FireServer("StartMatch",{size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
  task.wait(0.6)
  check(workspace:GetAttribute("MatchPhase")=="Lobby", "非房主無法開始對局")
  return true
 end
 awaitCondition(function() return workspace:GetAttribute("MatchPhase")=="Playing" and base(player.UserId)~=nil end,8,"第二玩家已參賽")
 local foreignPlayer
 for _,candidate in ipairs(Players:GetPlayers()) do if candidate~=player and candidate:GetAttribute("Spectator")~=true then foreignPlayer=candidate; break end end
 check(foreignPlayer~=nil, "另一位真實玩家存在")
 awaitCondition(function() return base(foreignPlayer.UserId)~=nil and #owned(workspace.Units,foreignPlayer.UserId,"villager")>=3 end,8,"另一方基地與村民在第二端可見")
 local foreignBase=base(foreignPlayer.UserId)
 local foreignWorker=owned(workspace.Units,foreignPlayer.UserId,"villager")[1]
 local myBalance,otherBalance=snapshot(player),snapshot(foreignPlayer)
 local oldPosition,oldOrder=foreignWorker:GetPivot().Position,foreignWorker:GetAttribute("Order")
 local oldQueue,oldResearch=foreignBase:GetAttribute("QueueCount"),foreignBase:GetAttribute("Research")
 local otherCount=#owned(workspace.Units,foreignPlayer.UserId)
 command:FireServer("Train",foreignBase,"villager")
 command:FireServer("Research",foreignBase,"Loom")
 command:FireServer("AdvanceAge",foreignBase)
 command:FireServer("Order",{foreignWorker},oldPosition+Vector3.new(20,0,0))
 command:FireServer("Stop",{foreignWorker})
 command:FireServer("Build","House",Vector3.new(0/0,0,0))
 command:FireServer("Order",{foreignWorker},Vector3.new(math.huge,0,0))
 for _=1,80 do command:FireServer("Train",foreignBase,"villager") end
 task.wait(1.5)
 check(foreignWorker:GetAttribute("Order")==oldOrder and (foreignWorker:GetPivot().Position-oldPosition).Magnitude<0.1, "第二玩家不能移動或停止另一方村民")
 check(foreignBase:GetAttribute("QueueCount")==oldQueue and foreignBase:GetAttribute("Research")==oldResearch, "第二玩家不能訓練或研究另一方建築")
 check(#owned(workspace.Units,foreignPlayer.UserId)==otherCount, "非法訓練與請求突發不生成單位")
 check(sameBalances(player,myBalance) and sameBalances(foreignPlayer,otherBalance), "跨玩家與非有限座標請求不扣款")
 check(#owned(workspace.Buildings,foreignPlayer.UserId,"House")>=1, "房主完成的房屋同步到第二端")
 print("[RTS_MULTI OWNERSHIP COMPLETE]")
 return true
end

-- 立即掛上觀察器並返回。之後手動關閉 victimId 所屬的另一個 Studio 客戶端。
-- 不會替使用者關閉視窗或模擬投降；實際 PlayerRemoving 必須由退出觸發。
function Tests.ObserveCleanupClient(victimId)
 local player=context()
 check(workspace:GetAttribute("MatchPhase")=="Playing", "離開清理從進行中的對局開始")
 check(#Players:GetPlayers()==2 and workspace:GetAttribute("AICount")==0, "離開驗證使用兩名玩家且沒有電腦")
 local victim
 for _,candidate in ipairs(Players:GetPlayers()) do
  if candidate~=player and (victimId==nil or candidate.UserId==victimId) then victim=candidate; break end
 end
 check(victim~=nil, "要退出的另一位玩家存在")
 local id=victim.UserId
 check(#owned(workspace.Units,id)>0 and #owned(workspace.Buildings,id)>0, "退出前另一方確實有單位與建築")
 local connection
 connection=Players.PlayerRemoving:Connect(function(leaving)
  if leaving.UserId~=id then return end
  connection:Disconnect()
  task.spawn(function()
   awaitCondition(function()
    return #owned(workspace.Units,id)==0 and #owned(workspace.Buildings,id)==0
     and workspace:GetAttribute("MatchPhase")=="Ended"
   end,10,"真正玩家退出後清除其全部單位與建築，結束雙人對局")
   check(workspace:GetAttribute("WinnerId")==player.UserId, "存留玩家獲得勝利")
   check(workspace:GetAttribute("HostUserId")==player.UserId, "房主權限交給存留玩家")
   print("[RTS_MULTI CLEANUP COMPLETE]")
  end)
 end)
 print("[RTS_MULTI CLEANUP ARMED] 等待另一個實際 Studio 玩家退出，UserId="..tostring(id))
 return connection
end
return Tests
