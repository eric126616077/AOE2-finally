-- Explicit Studio CLIENT test. Requiring this module does not issue commands.
-- Run() builds a House and Barracks, trains/cancels units and changes resources
-- through the same validated commands as the HUD. Use a fresh rich solo sandbox.
local RunService=game:GetService("RunService")
local Tests={running=false}
function Tests.Run()
 assert(RunService:IsStudio() and RunService:IsClient(),"只能在 Studio Play 客戶端明確呼叫")
 assert(not Tests.running,"生產驗證已在執行")
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true,"請先開新的豐富資源單人沙盒")
 Tests.running=true
 local RS=game:GetService("ReplicatedStorage")
 local player=game.Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local command=RS.RTSRemotes.Command
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local checks=0
 local messages={}
 local connection=RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message) table.insert(messages,message) end)
 local function check(condition,message)
  assert(condition,"[RTS_PRODUCTION FAIL] "..message)
  checks+=1; print("[RTS_PRODUCTION PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=os.clock()+seconds
  repeat if predicate() then check(true,message); return end; task.wait(.05) until os.clock()>=untilTime
  check(false,message.."；等待逾時")
 end
 local function own(folder,attribute,kind)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and (not kind or model:GetAttribute(attribute)==kind) then table.insert(result,model) end
  end
  return result
 end
 local function flat(model)
  local p=model:GetPivot().Position; return Vector3.new(p.X,Config.Map.GroundY,p.Z)
 end
 local function clearLocation(kind,anchor)
  Config.Map.MapSize=workspace:GetAttribute("MapSize") or Config.Map.MapSize
  local data=Config.Buildings[kind]
  local overlap=OverlapParams.new()
  overlap.FilterType=Enum.RaycastFilterType.Exclude
  local excluded={workspace.AOE2_Ground}
  for _,model in ipairs(workspace:GetChildren()) do
   if model:GetAttribute("RTSManagedScenery")==true then table.insert(excluded,model) end
  end
  overlap.FilterDescendantsInstances=excluded
  for radius=48,136,8 do
   for index=0,31 do
    local angle=index*math.pi/16
    local p=Grid.snap(anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
    if Grid.inBounds(p,data.size) then
     local clear=true
     for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,data.height/2,0)),
      Vector3.new(data.size.X*Config.Map.GridSize-.2,math.max(4,data.height),data.size.Y*Config.Map.GridSize-.2),overlap)) do
      if part.CanCollide or part:IsDescendantOf(workspace.Buildings) or part:IsDescendantOf(workspace.Resources) or part:IsDescendantOf(workspace.Units) then clear=false; break end
     end
     if clear then return p end
    end
   end
  end
  error("找不到生產測試建造位置")
 end
 local function build(kind,center,workers)
  local existing={}; for _,model in ipairs(own(workspace.Buildings)) do existing[model]=true end
  command:FireServer("Build",kind,clearLocation(kind,flat(center)),workers)
  local building
  waitFor(function()
   for _,model in ipairs(own(workspace.Buildings,"BuildingType",kind)) do if not existing[model] then building=model; return true end end
   return false
  end,5,Config.Buildings[kind].name.."由伺服器建立")
  waitFor(function() return building:GetAttribute("Complete")==true end,35,Config.Buildings[kind].name.."由村民完工")
  return building
 end
 local function newlyTrained(building,kind)
  local existing={}; for _,model in ipairs(own(workspace.Units)) do existing[model]=true end
  command:FireServer("Train",building,kind)
  local model
  waitFor(function()
   for _,unit in ipairs(own(workspace.Units,"UnitType",kind)) do if not existing[unit] then model=unit; return true end end
   return false
  end,Config.Units[kind].trainTime+8,Config.Units[kind].name.."由伺服器完成訓練")
  return model
 end
 local function canceled(building,index)
  local revision=building:GetAttribute("QueueRevision")
  command:FireServer("CancelTraining",building,index,revision)
  waitFor(function() return building:GetAttribute("QueueRevision")==revision+1 end,5,"取消訓練推進佇列版本")
 end
 local function rejectCancel(building,index,revision,label)
  local before=#messages
  local food=player:GetAttribute("food")
  local count=building:GetAttribute("QueueCount") or 0
  local current=building:GetAttribute("QueueRevision")
  command:FireServer("CancelTraining",building,index,revision)
  waitFor(function()
   for i=before+1,#messages do if type(messages[i])=="string" and string.find(messages[i],"訓練佇列已更新",1,true) then return true end end
   return false
  end,5,label.."收到拒絕回覆")
  check(player:GetAttribute("food")==food and (building:GetAttribute("QueueCount") or 0)==count and building:GetAttribute("QueueRevision")==current,label.."不多退資源、不取消其他單位")
 end
 local function rejectRally(building,target,label)
  local before=#messages
  local position=building:GetAttribute("RallyPosition")
  local food,wood=player:GetAttribute("food"),player:GetAttribute("wood")
  command:FireServer("Rally",building,target)
  waitFor(function()
   for i=before+1,#messages do if type(messages[i])=="string" and string.find(messages[i],"集合點必須位於地圖內",1,true) then return true end end
   return false
  end,5,label.."收到拒絕回覆")
  check(building:GetAttribute("RallyPosition")==position and player:GetAttribute("food")==food and player:GetAttribute("wood")==wood,label.."保留原集合點且不扣資源")
 end
 local ok,result=xpcall(function()
  local center=own(workspace.Buildings,"BuildingType","TownCenter")[1]
  local workers=own(workspace.Units,"UnitType","villager")
  assert(center and #workers==3 and player:GetAttribute("food")>=300 and player:GetAttribute("wood")>=300,"請使用未修改的豐富資源新沙盒")
  command:FireServer("Stop",workers)
  waitFor(function() for _,unit in ipairs(workers) do if unit:GetAttribute("Order")~="待命" then return false end end; return true end,5,"初始村民停止，隔離訓練退款的資源變化")
  local house=build("House",center,workers)
  local beforeFood=player:GetAttribute("food")
  local beforePopulation=player:GetAttribute("Population")
  for _=1,3 do command:FireServer("Train",center,"villager") end
  waitFor(function() return center:GetAttribute("QueueCount")==3 end,5,"三名村民進入同一生產佇列")
  check(player:GetAttribute("food")==beforeFood-150 and player:GetAttribute("Population")==beforePopulation+3,"佇列由伺服器扣款並預留人口")
  check(center:GetAttribute("QueueKind_1")=="villager" and center:GetAttribute("QueueKind_3")=="villager","HUD 可讀取逐格佇列種類")
  local staleRevision=center:GetAttribute("QueueRevision")
  canceled(center,2)
  check(center:GetAttribute("QueueCount")==2 and center:GetAttribute("QueueKind_3")==nil and player:GetAttribute("food")==beforeFood-100,"取消中間項退回全部成本並移除尾部卡片")
  canceled(center,1)
  check(center:GetAttribute("QueueCount")==1 and player:GetAttribute("food")==beforeFood-50,"取消正在訓練項後下一項繼續")
  rejectCancel(center,1,staleRevision,"舊版按鈕")
  canceled(center,1)
  check(center:GetAttribute("QueueCount")==0 and center:GetAttribute("Training")==nil and player:GetAttribute("food")==beforeFood,"取消最後項清空進度、退回全部訓練成本")
  check(player:GetAttribute("Population")==beforePopulation,"退款同步釋放預留人口")
  rejectCancel(center,1,staleRevision,"重複退款請求")
  rejectCancel(center,0,center:GetAttribute("QueueRevision"),"非法佇列索引")
  local resource,distance=nil,math.huge
  for _,model in ipairs(workspace.Resources:GetChildren()) do
   if model:GetAttribute("ResourceType")=="wood" and (model:GetAttribute("Amount") or 0)>0 then
    local d=(flat(model)-flat(center)).Magnitude
    if d<distance then resource,distance=model,d end
   end
  end
  assert(resource,"地圖需要可採集的樹木")
  command:FireServer("Rally",center,resource)
  waitFor(function() return center:GetAttribute("RallyType")=="gather" end,5,"市鎮中心可設定樹木集合點")
  check(center:GetAttribute("RallyPosition")==flat(resource) and type(center:GetAttribute("RallyTargetName"))=="string","集合點位置與資源名稱可供 HUD 顯示")
  command:FireServer("Rally",house,resource)
  local worker=newlyTrained(center,"villager")
  check(house:GetAttribute("RallyPosition")==nil,"非生產建築不能設定集合點")
  waitFor(function() return worker:GetAttribute("Order")=="採集" or worker:GetAttribute("Order")=="交貨" end,5,"新村民自動接到採集指令")
  local delivered=player:GetAttribute("DeliveredResources") or 0
  waitFor(function() return (worker:GetAttribute("Carrying") or 0)>0 or (player:GetAttribute("DeliveredResources") or 0)>delivered end,35,"集合點村民實際採到資源")
  command:FireServer("Stop",{worker})
  command:FireServer("Rally",center)
  waitFor(function() return center:GetAttribute("RallyPosition")==nil and center:GetAttribute("RallyType")==nil end,5,"清除集合點同步清除 HUD 狀態")
  local goal=clearLocation("House",flat(center))
  command:FireServer("Rally",center,goal)
  waitFor(function() return center:GetAttribute("RallyPosition")==goal and center:GetAttribute("RallyType")=="move" end,5,"地面集合點由伺服器保存")
  local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
  rejectRally(center,Vector3.new(half+8,0,0),"地圖邊界外集合點")
  rejectRally(center,"invalid","錯誤集合點型別")
  local moving=newlyTrained(center,"villager")
  waitFor(function() return (flat(moving)-goal).Magnitude<=8 end,20,"新單位實際走到地面集合點")
  check(center:GetAttribute("QueueCount")==0 and center:GetAttribute("QueueKind_1")==nil,"訓練完成清除佇列卡片")
  rejectCancel(center,1,center:GetAttribute("QueueRevision")-1,"已完成訓練的舊按鈕")
  local barracks=build("Barracks",center,workers)
  local militaryGoal=clearLocation("House",flat(barracks))
  command:FireServer("Rally",barracks,militaryGoal)
  waitFor(function() return barracks:GetAttribute("RallyPosition")==militaryGoal end,5,"兵營可設定地面集合點")
  local soldier=newlyTrained(barracks,"infantry")
  waitFor(function() return (flat(soldier)-militaryGoal).Magnitude<=8 end,20,"新軍隊實際走到生產建築集合點")
 end,debug.traceback)
 connection:Disconnect(); Tests.running=false
 if not ok then error(result) end
 print(string.format("[RTS_PRODUCTION COMPLETE] %d 項訓練退款／集合點檢查通過。",checks))
 return checks
end
return Tests
