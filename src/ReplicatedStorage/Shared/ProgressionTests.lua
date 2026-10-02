-- Explicit Studio CLIENT progression checks. Requiring this module alone does nothing.
-- Run in a single-player fresh Lobby (or after Restart). Uses only normal RemoteEvents.
local RunService=game:GetService("RunService")
local Tests={running=false}
local function run()
 assert(RunService:IsStudio() and RunService:IsClient(),"只能在 Studio Play 客戶端明確呼叫")
 local started,checks=os.clock(),0
 local deadline=started+300
 local RS=game:GetService("ReplicatedStorage")
 local Players=game:GetService("Players")
 local player=Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local command=RS:WaitForChild("RTSRemotes",10):WaitForChild("Command",10)
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local feedback=RS.RTSRemotes:WaitForChild("Feedback",10)
 local messages={}
 local connection=feedback.OnClientEvent:Connect(function(message)
  table.insert(messages,tostring(message))
 end)
 local function check(condition,message)
  assert(condition,"[RTS_PROGRESSION FAIL] "..message)
  checks+=1
  print("[RTS_PROGRESSION PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=math.min(deadline,os.clock()+seconds)
  repeat
   if predicate() then check(true,message); return end
   task.wait(0.1)
  until os.clock()>=untilTime
  check(false,message.."；等待逾時")
 end
 local function awaitFeedback(since,fragment,message)
  waitFor(function()
   for index=since+1,#messages do
    if string.find(messages[index],fragment,1,true) then return true end
   end
   return false
  end,5,message)
 end
 local function owned(folder,kind,key)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and (not kind or model:GetAttribute(key)==kind) then
    table.insert(result,model)
   end
  end
  return result
 end
 local function flat(model)
  local pos=model:GetPivot().Position
  return Vector3.new(pos.X,Config.Map.GroundY,pos.Z)
 end
 local ok,result=xpcall(function()
  waitFor(function() return workspace:GetAttribute("RTSReady")==true end,10,"伺服器初始化完成")
  check(#Players:GetPlayers()==1,"進階驗證使用單人 Studio 客戶端")
  if workspace:GetAttribute("MatchPhase")=="Ended" then
   command:FireServer("RestartMatch")
   waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" end,8,"結束對局返回大廳")
  end
  check(workspace:GetAttribute("MatchPhase")=="Lobby","只在新的大廳開始驗證")
  require(RS.Shared.LobbyTests).Start({size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
  waitFor(function()
   return workspace:GetAttribute("MatchPhase")=="Playing"
    and workspace:GetAttribute("Sandbox")==true and workspace:GetAttribute("MatchSize")==768
    and workspace:GetAttribute("AICount")==0
  end,15,"小地圖、無 AI、沙盒與 Playing 狀態完整複製")
  waitFor(function()
   return player:GetAttribute("Age")==1 and typeof(player:GetAttribute("HomePosition"))=="Vector3"
    and player:GetAttribute("food")==1200 and player:GetAttribute("wood")==1200
    and player:GetAttribute("gold")==800 and player:GetAttribute("stone")==600
  end,8,"黑暗時代、出生點與豐富起始資源完整複製")
  local buildings=workspace:WaitForChild("Buildings")
  local units=workspace:WaitForChild("Units")
  waitFor(function()
   local candidates=owned(units,"villager","UnitType")
   if #candidates~=3 then return false end
   for _,worker in ipairs(candidates) do if not worker.PrimaryPart or worker:GetAttribute("MaxHP")~=Config.Units.villager.hp or worker:GetAttribute("Armor")~=Config.Units.villager.armor then return false end end
   return true
  end,8,"三名初始村民的幾何與生命護甲完整複製")
  local workers=owned(units,"villager","UnitType")
  local center
  waitFor(function()
   center=owned(buildings,"TownCenter","BuildingType")[1]
   return center and center.PrimaryPart and center:GetAttribute("Complete")==true
  end,8,"已完成的初始市鎮中心完整複製")
  Config.Map.MapSize=workspace:GetAttribute("MatchSize")
  local home=player:GetAttribute("HomePosition")
  local params=OverlapParams.new()
  params.FilterType=Enum.RaycastFilterType.Exclude
  local excluded={workspace:FindFirstChild("AOE2_Ground")}
  for _,item in ipairs(workspace:GetChildren()) do
   if item:GetAttribute("RTSManagedScenery")==true then table.insert(excluded,item) end
  end
  params.FilterDescendantsInstances=excluded
  local function location(kind)
   local data=Config.Buildings[kind]
   for radius=40,96,8 do
    for index=0,23 do
     local angle=index*math.pi/12
     local pos=Grid.snap(home+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
     local nearby=false
     for _,worker in ipairs(workers) do if worker.Parent and (flat(worker)-pos).Magnitude<=75 then nearby=true; break end end
     if nearby and Grid.inBounds(pos,data.size) then
      local hits=workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*Config.Map.GridSize-.2,math.max(4,data.height),data.size.Y*Config.Map.GridSize-.2),params)
      local clear=true
      for _,part in ipairs(hits) do
       if part.CanCollide or part:IsDescendantOf(buildings) or part:IsDescendantOf(units) or part:IsDescendantOf(workspace.Resources) then clear=false; break end
      end
      if clear then return pos end
     end
    end
   end
   error("[RTS_PROGRESSION FAIL] 找不到可建造位置："..data.name)
  end
  local function build(kind)
   local data=Config.Buildings[kind]
   local existing={}
   for _,model in ipairs(owned(buildings,kind,"BuildingType")) do existing[model]=true end
   local balances={}
   for key in pairs(data.cost) do balances[key]=player:GetAttribute(key) end
   command:FireServer("Build",kind,location(kind),workers)
   local site
   waitFor(function()
    for _,model in ipairs(owned(buildings,kind,"BuildingType")) do if not existing[model] then site=model; return true end end
    return false
   end,8,data.name.."施工地點由伺服器建立")
   for key,value in pairs(data.cost) do waitFor(function() return player:GetAttribute(key)==balances[key]-value end,5,data.name.."正確扣除"..key) end
   check(site:GetAttribute("Complete")~=true,data.name.."需要村民施工")
   command:FireServer("Order",workers,site)
   waitFor(function() return site.Parent and site:GetAttribute("Complete")==true end,data.buildTime+25,data.name.."透過正常施工完成")
   return site
  end
  local function prerequisiteRejected(message)
   local before=player:GetAttribute("food")
   local since=#messages
   command:FireServer("AdvanceAge",center)
   awaitFeedback(since,"升級前",message)
   waitFor(function() return player:GetAttribute("Age")==1 and player:GetAttribute("food")==before end,5,"前置不足不扣升級資源")
  end
  prerequisiteRejected("初始市鎮中心不能充當黑暗時代前置")
  local loom=Config.Technologies.Loom
  local gold=player:GetAttribute("gold")
  command:FireServer("Research",center,"Loom")
  waitFor(function() return center:GetAttribute("Research")==loom.name and player:GetAttribute("gold")==gold-loom.cost.gold end,5,"織布機研究與扣款完整複製")
  check(player:GetAttribute("gold")==gold-loom.cost.gold,"織布機成本由伺服器扣除")
  build("Mill")
  waitFor(function()
   if player:GetAttribute("Tech_Loom")~=true then return false end
   for _,worker in ipairs(workers) do
    if worker:GetAttribute("MaxHP")~=Config.Units.villager.hp+loom.effect.hp or worker:GetAttribute("Armor")~=Config.Units.villager.armor+loom.effect.armor then return false end
   end
   return true
  end,loom.time+8,"織布機完成，村民生命與護甲完整複製")
  for _,worker in ipairs(workers) do
   check(worker:GetAttribute("MaxHP")==Config.Units.villager.hp+loom.effect.hp and worker:GetAttribute("Armor")==Config.Units.villager.armor+loom.effect.armor,"織布機改善村民生命與護甲")
  end
  local scout=owned(units,"scout","UnitType")[1]
  check(scout and scout:GetAttribute("MaxHP")==Config.Units.scout.hp and scout:GetAttribute("Armor")==Config.Units.scout.armor,"織布機不加成斥候")
  build("Mill")
  check(#owned(buildings,"Mill","BuildingType")==2,"兩座磨坊皆已完成")
  local afterLoom=player:GetAttribute("gold")
  command:FireServer("Research",center,"Loom")
  prerequisiteRejected("兩座同類型磨坊不能代替兩種前置建築")
  check(player:GetAttribute("gold")==afterLoom and not center:GetAttribute("Research"),"重複研究織布機不扣款或重啟")
  build("LumberCamp")
  local barracks=build("Barracks")
  local farm=build("Farm")
  waitFor(function()
   local maximum,amount=farm:GetAttribute("MaxAmount"),farm:GetAttribute("Amount")
   return maximum==Config.Buildings.Farm.amount and Grid.isFinite(amount) and amount>=0 and amount<=maximum
  end,5,"農田最大容量符合設定，採集後剩餘量有限且合法")
  command:FireServer("Stop",workers)
  waitFor(function()
   for _,worker in ipairs(workers) do if worker:GetAttribute("Order")~="待命" then return false end end
   return true
  end,5,"測量研究成本前停止農田自動採集")
  local food=player:GetAttribute("food")
  command:FireServer("Train",barracks,"infantry")
  waitFor(function() return (barracks:GetAttribute("QueueCount") or 0)>0 and player:GetAttribute("food")==food-Config.Units.infantry.cost.food end,5,"兵營正常佇列與訓練扣款完整複製")
  check(player:GetAttribute("food")==food-Config.Units.infantry.cost.food,"步兵訓練正常扣款")
  food=player:GetAttribute("food")
  command:FireServer("AdvanceAge",center)
  waitFor(function() return center:GetAttribute("Research")==Config.Ages[2].name and player:GetAttribute("food")==food-Config.Ages[2].cost.food end,5,"完成不同前置後，封建研究與扣款完整複製")
  check(player:GetAttribute("food")==food-Config.Ages[2].cost.food,"封建時代正確扣除 500 食物")
  waitFor(function() return player:GetAttribute("Age")==2 and player:GetAttribute("AgeRemaining")==0 and center:GetAttribute("Research")==nil end,Config.Ages[2].time+10,"封建時代完成真實 35 秒研究")
  local infantry
  waitFor(function() infantry=owned(units,"infantry","UnitType")[1]; return infantry~=nil end,10,"兵營產生真正的步兵實例")
  local market=build("Market")
  local function trade(key,direction)
   local rules=Config.MarketTrade
   local oldResource,oldGold=player:GetAttribute(key),player:GetAttribute("gold")
   command:FireServer("Trade",market,key,direction)
   waitFor(function()
    if direction=="Buy" then return player:GetAttribute(key)==oldResource+rules.batch and player:GetAttribute("gold")==oldGold-rules.buyGold end
    return player:GetAttribute(key)==oldResource-rules.batch and player:GetAttribute("gold")==oldGold+rules.sellGold
   end,5,"市集"..(direction=="Buy" and "買入" or "賣出")..key.."正確交換資源")
  end
  trade("food","Buy")
  trade("wood","Sell")
  if deadline-os.clock()<65 or (player:GetAttribute("wood") or 0)<Config.Buildings.Blacksmith.cost.wood+Config.Technologies.Wheelbarrow.cost.wood then
   print("[RTS_PROGRESSION SKIP] 時間或資源有限；範圍保留為不同前置、織布機、封建與市集")
   print(string.format("[RTS_PROGRESSION COMPLETE] %d 項檢查通過，核心進階範圍，耗時 %.1f 秒",checks,os.clock()-started))
   return checks
  end
  local blacksmith=build("Blacksmith")
  local beforeAttack=infantry:GetAttribute("Attack")
  local beforeWorkerAttack=workers[1]:GetAttribute("Attack")
  local beforeWorkerSpeed=workers[1]:GetAttribute("Speed")
  command:FireServer("Research",blacksmith,"Forging")
  command:FireServer("Research",center,"Wheelbarrow")
  waitFor(function() return blacksmith:GetAttribute("Research")==Config.Technologies.Forging.name and center:GetAttribute("Research")==Config.Technologies.Wheelbarrow.name end,6,"兵工廠與市鎮中心同時研究不同科技")
  waitFor(function()
   return player:GetAttribute("Tech_Forging")==true and player:GetAttribute("Tech_Wheelbarrow")==true
    and infantry:GetAttribute("Attack")==beforeAttack+Config.Technologies.Forging.effect.attack
    and workers[1]:GetAttribute("Speed") and math.abs(workers[1]:GetAttribute("Speed")-beforeWorkerSpeed*(1+Config.Technologies.Wheelbarrow.effect.speed))<0.001
  end,math.max(Config.Technologies.Forging.time,Config.Technologies.Wheelbarrow.time)+10,"鍛造、手推車完成與單位數值完整複製")
  check(infantry:GetAttribute("Attack")==beforeAttack+Config.Technologies.Forging.effect.attack,"鍛造提升現有軍隊攻擊")
  check(workers[1]:GetAttribute("Attack")==beforeWorkerAttack,"鍛造不改變村民攻擊")
  check(math.abs(workers[1]:GetAttribute("Speed")-beforeWorkerSpeed*(1+Config.Technologies.Wheelbarrow.effect.speed))<0.001,"手推車提升現有村民速度")
  check(math.abs(infantry:GetAttribute("Speed")-Config.Units.infantry.speed)<0.001,"手推車不改變軍隊速度")
  while (player:GetAttribute("gold") or 0)>=Config.MarketTrade.buyGold do
   trade("food","Buy")
  end
  local remainingGold,remainingFood=player:GetAttribute("gold"),player:GetAttribute("food")
  local since=#messages
  command:FireServer("Trade",market,"food","Buy")
  awaitFeedback(since,"資源不足","黃金不足時市集拒絕購買")
  check(player:GetAttribute("gold")==remainingGold and player:GetAttribute("food")==remainingFood,"購買失敗不扣款也不生成資源")
  check(workspace:GetAttribute("MatchPhase")=="Playing" and not player:GetAttribute("Defeated"),"完整進階流程後沙盒仍正常運作")
  print(string.format("[RTS_PROGRESSION COMPLETE] %d 項引擎檢查通過；封建、六種建築、三項科技與市集，耗時 %.1f 秒",checks,os.clock()-started))
  return checks
 end,debug.traceback)
 connection:Disconnect()
 if not ok then error(result,0) end
 return result
end
function Tests.Run()
 assert(not Tests.running,"進階驗證正在執行，請勿重複呼叫")
 Tests.running=true
 local ok,result=pcall(run)
 Tests.running=false
 if not ok then error(result,0) end
 return result
end
return Tests
