-- Explicit Studio CLIENT checks. Start a fresh solo sandbox with rich resources first.
-- Run() changes that test match through normal commands; requiring the module does nothing.
local RunService=game:GetService("RunService")
local Tests={running=false}
local function run()
 assert(RunService:IsStudio() and RunService:IsClient(),"只能在 Studio Play 客戶端明確呼叫")
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true,"請先由城堡大廳開始新的單人沙盒對局")
 local RS=game:GetService("ReplicatedStorage")
 local player=game.Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local buildings,units=workspace.Buildings,workspace.Units
 local command,feedback=RS.RTSRemotes.Command,RS.RTSRemotes.Feedback
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local checks,messages=0,{}
 local connection=feedback.OnClientEvent:Connect(function(message) table.insert(messages,tostring(message)) end)
 local function check(condition,message)
  assert(condition,"[RTS_CONSTRUCTION FAIL] "..message)
  checks+=1
  print("[RTS_CONSTRUCTION PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local deadline=os.clock()+seconds
  repeat if predicate() then check(true,message); return end; task.wait(0.1) until os.clock()>=deadline
  check(false,message.."；等待逾時")
 end
 local function ownModels(folder,kind,attribute)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and (not kind or model:GetAttribute(attribute)==kind) then table.insert(result,model) end
  end
  return result
 end
 local workers=ownModels(units,"villager","UnitType")
 local soldier=ownModels(units,"scout","UnitType")[1]
 local worker=workers[1]
 assert(worker and soldier,"新沙盒需要初始村民與斥候")
 assert((player:GetAttribute("wood") or 0)>=300 and (player:GetAttribute("food") or 0)>=60,"請使用豐富開局資源進行施工驗證")
 local function flat(model)
  local position=model:GetPivot().Position
  return Vector3.new(position.X,Config.Map.GroundY,position.Z)
 end
 local function location(kind,anchor,minimum)
  Config.Map.MapSize=workspace:GetAttribute("MapSize") or Config.Map.MapSize
  local data=Config.Buildings[kind]
  local params=OverlapParams.new()
  params.FilterType=Enum.RaycastFilterType.Exclude
  local excluded={}
  for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local item=workspace:FindFirstChild(name); if item then table.insert(excluded,item) end end
  params.FilterDescendantsInstances=excluded
  for radius=minimum,minimum+120,8 do
   for index=0,31 do
    local angle=index*math.pi/16
    local pos=Grid.snap(anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
    if Grid.inBounds(pos,data.size) and (pos-flat(worker)).Magnitude>=minimum then
     local clear=true
     local hits=workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*Config.Map.GridSize-.2,math.max(4,data.height),data.size.Y*Config.Map.GridSize-.2),params)
     for _,part in ipairs(hits) do
      if part.CanCollide or part:IsDescendantOf(buildings) or part:IsDescendantOf(units) or part:IsDescendantOf(workspace.Resources) then clear=false; break end
     end
     if clear then return pos end
    end
   end
  end
  error("找不到合法施工測試位置："..data.name)
 end
 local function rejectedBuild(selection,pos,label)
  local count,wood,since=#ownModels(buildings),player:GetAttribute("wood"),#messages
  command:FireServer("Build","House",pos,selection)
  waitFor(function()
   for index=since+1,#messages do if string.find(messages[index],"村民",1,true) then return true end end
   return false
  end,5,label.."收到村民限制回覆")
  check(#ownModels(buildings)==count and player:GetAttribute("wood")==wood,label.."不建立工地、不扣資源")
 end
 local function build(kind,pos,selection)
  local old={}
  for _,model in ipairs(ownModels(buildings)) do old[model]=true end
  command:FireServer("Build",kind,pos,selection)
  local site
  waitFor(function()
   for _,model in ipairs(ownModels(buildings,kind,"BuildingType")) do if not old[model] then site=model; return true end end
   return false
  end,6,Config.Buildings[kind].name.."由伺服器建立工地")
  return site
 end
 local function stopAndCheckPause(site,label)
  command:FireServer("Stop",workers)
  waitFor(function() return worker:GetAttribute("Order")=="待命" and site:GetAttribute("BuilderCount")==0 end,5,label.."施工村民停止")
  local progress=site:GetAttribute("ConstructionProgress")
  local untilTime=os.clock()+0.8
  waitFor(function() return os.clock()>=untilTime end,2,label.."觀察停工期間")
  check(site:GetAttribute("ConstructionProgress")==progress and not site:GetAttribute("Complete"),label.."停止後保留進度且不自行完工")
 end
 local ok,result=xpcall(function()
  local pos=location("House",flat(worker),112)
  rejectedBuild(nil,pos,"沒有選中村民")
  rejectedBuild({soldier},pos,"只選軍隊")
  rejectedBuild({worker,soldier},pos,"村民與軍隊混選")
  local cap=player:GetAttribute("PopulationCap")
  local wood=player:GetAttribute("wood")
  local house=build("House",pos,{worker,worker})
  check(player:GetAttribute("wood")==wood-Config.Buildings.House.cost.wood,"重複村民只扣一次建造成本")
  check((pos-flat(worker)).Magnitude>80,"指定遠於舊 80 studs 限制的工地仍可建立")
  check(not house:GetAttribute("Complete") and player:GetAttribute("PopulationCap")==cap,"未完工房屋不增加人口")
  stopAndCheckPause(house,"到場前")
  check(house:GetAttribute("ConstructionProgress")==0,"遠距村民尚未到場時沒有施工進度")
  command:FireServer("Order",{soldier},house)
  command:FireServer("Order",{worker},house)
  waitFor(function() return (house:GetAttribute("ConstructionProgress") or 0)>0.05 end,45,"村民實際走到遠方工地後才開始施工")
  check(house:GetAttribute("BuilderCount")==1 and soldier:GetAttribute("Order")~="施工","軍隊不能協助施工、重複村民不重算")
  stopAndCheckPause(house,"到場後")
  command:FireServer("Order",{worker},house)
  waitFor(function() return house:GetAttribute("Complete")==true end,Config.Buildings.House.buildTime+8,"村民可繼續完成停工房屋")
  check(house:GetAttribute("UnderConstruction")==false and player:GetAttribute("PopulationCap")==cap+Config.Buildings.House.population,"房屋完工才啟用人口")
  local barracks=build("Barracks",location("Barracks",flat(worker),112),{worker})
  stopAndCheckPause(barracks,"兵營到場前")
  local food,gold,since=player:GetAttribute("food"),player:GetAttribute("gold"),#messages
  command:FireServer("Train",barracks,"infantry")
  waitFor(function()
   for index=since+1,#messages do if string.find(messages[index],"尚未完工",1,true) then return true end end
   return false
  end,5,"未完工兵營拒絕訓練")
  check(player:GetAttribute("food")==food and player:GetAttribute("gold")==gold and (barracks:GetAttribute("QueueCount") or 0)==0,"未完工訓練請求不扣款、不排入佇列")
  command:FireServer("Order",workers,barracks)
  waitFor(function() return barracks:GetAttribute("Complete")==true end,55,"多名村民前往並完成兵營")
  command:FireServer("Train",barracks,"infantry")
  waitFor(function() return (barracks:GetAttribute("QueueCount") or 0)==1 end,5,"兵營完工後才可訓練")
  local farm=build("Farm",location("Farm",flat(worker),112),{worker})
  stopAndCheckPause(farm,"農田到場前")
  check(farm:GetAttribute("Amount")==0 and farm:GetAttribute("MaxAmount")==Config.Buildings.Farm.amount,"未完工農田不提供可採集資源")
  command:FireServer("Order",workers,farm)
  waitFor(function() return farm:GetAttribute("Complete")==true end,55,"村民完成農田")
  check((farm:GetAttribute("Amount") or 0)>0 and farm:GetAttribute("Amount")<=farm:GetAttribute("MaxAmount"),"農田完工才啟用食物")
  print(string.format("[RTS_CONSTRUCTION COMPLETE] %d 項施工引擎檢查通過",checks))
  return checks
 end,debug.traceback)
 connection:Disconnect()
 if not ok then error(result,0) end
 return result
end
function Tests.Run()
 assert(not Tests.running,"施工驗證已在執行")
 Tests.running=true
 local ok,result=pcall(run)
 Tests.running=false
 if not ok then error(result,0) end
 return result
end
return Tests
