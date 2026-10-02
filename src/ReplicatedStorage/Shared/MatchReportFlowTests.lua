-- Explicit Studio CLIENT integration test. Requiring this module changes nothing.
-- Run() requires a fresh solo Lobby and uses two normal Rich/Small/AI0 matches.
-- LobbyTests.Start is the existing authorized portal-entry test. All match actions
-- use ordinary RemoteEvents; no server mutations, forced damage, or fake GUI state.
local Tests={running=false}
local resourceKeys={"food","wood","gold","stone"}
local counterKeys={"buildingsCompleted","villagersTrained","militaryTrained","damageDealt","unitsKilled","buildingsKilled","unitsLost","buildingsLost"}
local MAX=9007199254740991

local function run(options,connections)
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"[MATCH_REPORT_FLOW FAIL] 僅限 Studio Play 客戶端")
 options=options or {}
 local seconds=options.deadlineSeconds or 360
 assert(type(seconds)=="number" and seconds==seconds and seconds>=300 and seconds<=420,"[MATCH_REPORT_FLOW FAIL] 總期限須為 300–420 秒")
 local started,deadline=os.clock(),os.clock()+seconds
 local Players,RS=game:GetService("Players"),game:GetService("ReplicatedStorage")
 local HttpService=game:GetService("HttpService")
 local player=Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local LobbyTests=require(RS.Shared.LobbyTests)
 local ReportTests=require(RS.Shared.MatchReportTests)
 local command=assert(RS:WaitForChild("RTSRemotes",10),"缺少正式遠端資料夾"):WaitForChild("Command",10)
 assert(command and command:IsA("RemoteEvent"),"缺少正式遊戲指令")
 local checks,uiChecks,lastSend,lastProgress=0,0,0,started
 local folders
 local function check(ok,message)
  assert(ok,"[MATCH_REPORT_FLOW FAIL] "..message)
  checks+=1
  print("[MATCH_REPORT_FLOW PASS] "..message)
 end
 local function number(value)
  return type(value)=="number" and value==value and value>=0 and value<=MAX
 end
 local function equal(a,b)
  return type(a)=="number" and type(b)=="number" and math.abs(a-b)<0.0001
 end
 local function waitFor(predicate,limit,label)
  local untilTime=math.min(deadline,os.clock()+limit)
  repeat
   if predicate() then return end
   if os.clock()-lastProgress>=25 then
    print(string.format("[MATCH_REPORT_FLOW PROGRESS] %s；已用 %.1f 秒；階段 %s",label,os.clock()-started,tostring(workspace:GetAttribute("MatchPhase"))))
    lastProgress=os.clock()
   end
   task.wait(0.05)
  until os.clock()>=untilTime
  error("[MATCH_REPORT_FLOW FAIL] "..label.."逾時；階段 "..tostring(workspace:GetAttribute("MatchPhase")),0)
 end
 local function send(action,...)
  local remaining=0.25-(os.clock()-lastSend)
  if remaining>0 then task.wait(remaining) end
  assert(os.clock()<deadline,"[MATCH_REPORT_FLOW FAIL] 全程期限已到")
  command:FireServer(action,...)
  lastSend=os.clock()
 end
 local function owned(folder,kind,attribute)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==player.UserId
    and (not kind or model:GetAttribute(attribute)==kind) then table.insert(result,model) end
  end
  return result
 end
 local function workers()
  return owned(folders.units,"villager","UnitType")
 end
 local function flat(model)
  local p=model:GetPivot().Position
  return Vector3.new(p.X,Config.Map.GroundY,p.Z)
 end
 local function balances()
  local result={}
  for _,key in ipairs(resourceKeys) do result[key]=player:GetAttribute(key) end
  return result
 end
 local function sameBalances(a,b)
  for _,key in ipairs(resourceKeys) do if not equal(a[key],b[key]) then return false end end
  return true
 end
 local function controlState()
  local probe=player.PlayerScripts:FindFirstChild("RTSControlProbe")
  if not probe or not probe:IsA("BindableFunction") then return nil end
  local result=probe:Invoke()
  if type(result)~="table" or result.ready~=true or type(result.initial)~="boolean"
   or type(result.controlsEnabled)~="boolean" or type(result.hasActive)~="boolean" then return nil end
  return result
 end
 waitFor(function()
  local value=controlState()
  return player.PlayerGui:FindFirstChild("AOE2_MainGUI") and player.Character~=nil
   and value and value.controlsEnabled==value.initial
 end,15,"正式介面與大廳角色控制初始化")
 check(workspace:GetAttribute("MatchPhase")=="Lobby" and #Players:GetPlayers()==1,"只在新的單人大廳執行，不與其他測試共用對局")
 check(player:GetAttribute("MatchReportJSON")==nil and player:GetAttribute("Defeated")~=true,"新 Play 尚無前局報告或戰敗狀態")
 local initialControls=controlState().initial
 check(controlState().controlsEnabled==initialControls and player:GetAttribute("RTSDefaultControlsInitialEnabled")==initialControls,"從實際 PlayerInput 探針取得並保留接管前控制初值")

 local function startMatch()
  assert(os.clock()<deadline,"[MATCH_REPORT_FLOW FAIL] 開局前全程期限已到")
  local began=os.clock()
  LobbyTests.Start({expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
  lastSend=os.clock()
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" end,20,"正常準備與開局")
  folders={buildings=workspace:WaitForChild("Buildings",5),units=workspace:WaitForChild("Units",5),resources=workspace:WaitForChild("Resources",5)}
  local freeUnits=Config.Settings.startingVillagers+(Config.Units.scout and 1 or 0)
  waitFor(function()
   return #owned(folders.buildings,"TownCenter","BuildingType")==1 and #owned(folders.units)==freeUnits
    and #workers()==Config.Settings.startingVillagers and typeof(player:GetAttribute("HomePosition"))=="Vector3"
    and sameBalances(balances(),{food=1200,wood=1200,gold=800,stone=600})
  end,10,"免費開局模型與 Rich 資源複製")
  waitFor(function() local value=controlState(); return value and value.controlsEnabled==false and (not value.hasActive or value.activeEnabled==false) end,5,"RTS 實際角色控制停用")
  check(player:GetAttribute("MatchReportJSON")==nil and player:GetAttribute("Defeated")==false,"新局正式 JSON 為 nil，沒有沿用前局報告")
  check(workspace:GetAttribute("AICount")==0 and workspace:GetAttribute("FactionCount")==1 and player:GetAttribute("Spectator")==false,"正式沙盒只有一個真人陣營，沒有 AI 或旁觀者經濟")
  check(#owned(folders.buildings)==1 and #owned(folders.units)==freeUnits and #workers()==Config.Settings.startingVillagers,"初始模型只有免費市鎮中心、村民與斥候")
  check(player:GetAttribute("DeliveredResources")==0 and player:GetAttribute("TrainedUnits")==0 and player:GetAttribute("TrainedVillagers")==0,"正式交貨與訓練事實在每個新局皆為零")
  return began,owned(folders.buildings,"TownCenter","BuildingType")[1],balances()
 end
 local function readReport()
  local raw=player:GetAttribute("MatchReportJSON")
  if type(raw)~="string" or raw=="" then return nil end
  local ok,value=pcall(HttpService.JSONDecode,HttpService,raw)
  return ok and type(value)=="table" and value.finished==true and value or nil
 end
 -- Validate the actual JSON contract of server-only MatchReportRules.Snapshot.
 -- ServerScriptService is not client-replicated; no substitute report is created.
 local function schema(report,began)
  local allowed={version=true,matchId=true,finished=true,outcome=true,outcomeLabel=true,survivalSeconds=true,resourcesDelivered=true,resourcesSpent=true,labels=true}
  for _,key in ipairs(counterKeys) do allowed[key]=true end
  local exact=true
  for key in pairs(report) do if not allowed[key] then exact=false end end
  check(exact and report.version==1 and report.finished==true,"實際報告符合 Snapshot 版本與公開欄位，沒有內部事件或去重資料")
  check(type(report.matchId)=="string" and #report.matchId>0 and #report.matchId<=100 and report.matchId:match("^[%w_:%-]+$")~=nil,"報告具有有效的伺服器對局識別")
  check(report.outcome=="loss" and report.outcomeLabel=="戰敗","正常投降的報告結果為戰敗")
  check(number(report.survivalSeconds) and report.survivalSeconds>0 and report.survivalSeconds<=os.clock()-began+1,"存活時長有限、為正且不超過真實開局流程時間")
  for _,name in ipairs({"resourcesDelivered","resourcesSpent"}) do
   local values=report[name]
   local valid=type(values)=="table"
   if valid then
    for key,value in pairs(values) do if not table.find(resourceKeys,key) or not number(value) then valid=false end end
    for _,key in ipairs(resourceKeys) do if not number(values[key]) then valid=false end end
   end
   check(valid,"正式報告四資源欄位有限且非負："..name)
  end
  for _,key in ipairs(counterKeys) do
   check(number(report[key]) and (key=="damageDealt" or report[key]%1==0),"正式計數欄位型別有效："..key)
  end
  local labels=report.labels
  local labelKeys={"resourcesDelivered","resourcesSpent","survivalSeconds","outcome"}
  for _,key in ipairs(counterKeys) do table.insert(labelKeys,key) end
  for _,key in ipairs(resourceKeys) do table.insert(labelKeys,key) end
  local valid=type(labels)=="table"
  if valid then for _,key in ipairs(labelKeys) do if type(labels[key])~="string" or labels[key]=="" then valid=false end end end
  check(valid,"正式 Snapshot 包含所有計數與資源標籤")
 end
 local function finish(began,before)
  check(workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("Defeated")==false,"僅向進行中的真人陣營提出正常投降")
  send("Surrender")
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" and player:GetAttribute("Defeated")==true and readReport() end,12,"正常投降結束與正式 finished JSON")
  waitFor(function() return #owned(folders.units)==0 and #owned(folders.buildings)==0 end,8,"投降清理真實模型")
  local report=readReport()
  schema(report,began)
  check(sameBalances(before,balances()),"投降清場沒有自行花費或發放資源")
  return report
 end
 local function restart()
  send("RestartMatch")
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("MatchReportJSON")==nil end,15,"房主正常返回大廳並清除正式 JSON")
  check(ReportTests.CheckClear()==true,"唯讀檢查實際 PlayerGui 清除前局數據與欄位標記")
  waitFor(function()
   local value=controlState()
   return value and value.initial==initialControls and value.controlsEnabled==initialControls
    and (initialControls or not value.hasActive or value.activeEnabled==false)
  end,10,"大廳恢復接管前的真實預設控制初值")
  local value=controlState()
  check(value.initial==initialControls and value.controlsEnabled==initialControls and player:GetAttribute("RTSDefaultControlsReady")==true
   and player:GetAttribute("RTSDefaultControlsInitialEnabled")==initialControls,"重開後 actual 控制探針與初值一致，不重建 PlayerModule")
  check(player:GetAttribute("DeliveredResources")==0 and player:GetAttribute("TrainedUnits")==0 and player:GetAttribute("TrainedVillagers")==0,"重開將正式遊戲累計事實清零")
 end

 local began,_,initial=startMatch()
 local first=finish(began,initial)
 for _,key in ipairs(counterKeys) do check(first[key]==0,"免費開局與投降清場不算覆盤計數："..key) end
 for _,key in ipairs(resourceKeys) do check(first.resourcesDelivered[key]==0 and first.resourcesSpent[key]==0,"免費資源與清場沒有交貨或支出："..key) end
 uiChecks+=ReportTests.Run()
 restart()

 local secondBegan,center,secondInitial=startMatch()
 local initialUnitSet={}
 for _,unit in ipairs(owned(folders.units)) do initialUnitSet[unit]=true end
 local initialVillagers,initialUnits=#workers(),#owned(folders.units)
 local selection=workers()
 for _,worker in ipairs(selection) do check(worker.PrimaryPart~=nil and worker:GetAttribute("Order")=="待命","初始真實村民待命且可施工") end
 local data,g=Config.Buildings.House,Config.Map.GridSize
 local home=player:GetAttribute("HomePosition")
 local params=OverlapParams.new()
 params.FilterType=Enum.RaycastFilterType.Exclude
 local excluded={}
 for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local object=workspace:FindFirstChild(name); if object then table.insert(excluded,object) end end
 params.FilterDescendantsInstances=excluded
 local placement
 local baseAngle=math.atan2(-home.Z,-home.X)
 local half=(workspace:GetAttribute("MapSize") or workspace:GetAttribute("MatchSize") or Config.Map.MapSize)/2
 for radius=40,120,8 do
  for index=0,31 do
   local angle=baseAngle+index*math.pi/16
   local pos=Grid.snap(home+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
   if math.abs(pos.X)+data.size.X*g/2<=half-3 and math.abs(pos.Z)+data.size.Y*g/2<=half-3 then
    local clear=true
    for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*g-0.2,math.max(4,data.height),data.size.Y*g-0.2),params)) do
     if part.CanCollide or part:IsDescendantOf(folders.buildings) or part:IsDescendantOf(folders.resources) or part:IsDescendantOf(folders.units) then clear=false; break end
    end
    if clear then placement=pos; break end
   end
  end
  if placement then break end
 end
 check(placement~=nil,"在真實地圖障礙與邊界內找到合法房屋空地")
 send("Build","House",placement,selection)
 local house
 waitFor(function() house=owned(folders.buildings,"House","BuildingType")[1]; return house and house.PrimaryPart end,10,"正常建立房屋工地")
 print("[MATCH_REPORT_FLOW_GEOMETRY] House",house:GetPivot().Position,"TownCenter",center:GetPivot().Position)
 local housePaid=table.clone(secondInitial); housePaid.wood-=25
 waitFor(function() return sameBalances(housePaid,balances()) end,8,"房屋真實扣款複製")
 check(not house:GetAttribute("Complete") and house:GetAttribute("UnderConstruction")==true,"房屋先成為工地，沒有跳過施工")
 local observedWork=false
 local function observeWork()
  local progress=house:GetAttribute("ConstructionProgress") or 0
  if progress>0 and progress<1 and (house:GetAttribute("BuilderCount") or 0)>0 then observedWork=true end
 end
 table.insert(connections,house:GetAttributeChangedSignal("ConstructionProgress"):Connect(observeWork))
 waitFor(function() observeWork(); return house.Parent==folders.buildings and house:GetAttribute("Complete")==true end,100,"村民正常行走與施工完工")
 check(observedWork and house:GetAttribute("UnderConstruction")==false and house:GetAttribute("ConstructionProgress")==1,"已觀察到真實村民施工進度與完工")
 check(#owned(folders.buildings)==2 and #owned(folders.buildings,"House","BuildingType")==1 and sameBalances(housePaid,balances()),"真實完工建築新增一棟，僅扣木材 25")
 send("Train",center,"villager")
 local paid=table.clone(housePaid); paid.food-=50
 waitFor(function() return sameBalances(paid,balances()) and center:GetAttribute("QueueCount")==1 end,8,"單一村民正常入訓練佇列與扣款")
 check(#workers()==initialVillagers and #owned(folders.units)==initialUnits,"扣款與入列時尚未憑空生成村民")
 local trained
 waitFor(function()
  for _,unit in ipairs(workers()) do if not initialUnitSet[unit] and unit.PrimaryPart then trained=unit end end
  return trained and #workers()==initialVillagers+1 and #owned(folders.units)==initialUnits+1 and center:GetAttribute("QueueCount")==0
   and player:GetAttribute("TrainedUnits")==1 and player:GetAttribute("TrainedVillagers")==1
 end,45,"正常計時完成並生成一個新的真實村民")
 check(trained.Parent==folders.units and trained:GetAttribute("UnitType")=="villager" and sameBalances(paid,balances()),"新增實例、正式訓練事實與食物 50 扣款一致")

 selection=workers()
 send("Stop",selection)
 waitFor(function() for _,worker in ipairs(selection) do if worker:GetAttribute("Order")~="待命" then return false end end; return true end,8,"採集前所有工人待命")
 local gatherer=selection[1]
 local food,distance
 for _,model in ipairs(folders.resources:GetChildren()) do
  if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("RTSManagedResource")==true and model:GetAttribute("ResourceType")=="food"
   and (model:GetAttribute("Amount") or 0)>=Config.Units.villager.carryCapacity then
   local candidate=(flat(model)-flat(gatherer)).Magnitude
   if not distance or candidate<distance then food,distance=model,candidate end
  end
 end
 check(food~=nil and player:GetAttribute("DeliveredResources")==0,"僅一名村民前往最近的真實食物資源，交貨尚為零")
 print("[MATCH_REPORT_FLOW_GEOMETRY] Food",food:GetPivot().Position,"Worker",gatherer:GetPivot().Position)
 local availableBefore=food:GetAttribute("Amount")
 local peakCarry,deliveryChanges,lastDelivered=0,0,0
 table.insert(connections,gatherer:GetAttributeChangedSignal("Carrying"):Connect(function()
  if gatherer:GetAttribute("CarryType")=="food" then peakCarry=math.max(peakCarry,gatherer:GetAttribute("Carrying") or 0) end
 end))
 table.insert(connections,player:GetAttributeChangedSignal("DeliveredResources"):Connect(function()
  local value=player:GetAttribute("DeliveredResources") or 0
  if value>lastDelivered then deliveryChanges+=1 end
  lastDelivered=value
 end))
 send("Order",{gatherer},food)
 waitFor(function() return (player:GetAttribute("DeliveredResources") or 0)>0 end,130,"真實採集、攜帶、返回市鎮中心並交貨")
 send("Stop",workers())
 waitFor(function() for _,worker in ipairs(workers()) do if worker:GetAttribute("Order")~="待命" then return false end end; return true end,8,"首筆交貨後停止全部工人")
 local stable,stableAt=balances(),os.clock()
 local delivered=player:GetAttribute("DeliveredResources")
 waitFor(function()
  local now,currentDelivered=balances(),player:GetAttribute("DeliveredResources")
  if not sameBalances(stable,now) or delivered~=currentDelivered then stable,delivered,stableAt=now,currentDelivered,os.clock() end
  return os.clock()-stableAt>=0.8
 end,8,"停止後真實餘額與交貨屬性複製穩定")
 local carried=gatherer:GetAttribute("Carrying") or 0
 local expected=table.clone(paid); expected.food+=delivered
 check(deliveryChanges==1 and equal(delivered,Config.Units.villager.carryCapacity) and peakCarry>0,"已觀察到一次真實食物攜帶與交貨，數量等於原始攜帶容量")
 check(food.Parent==folders.resources and equal(availableBefore-food:GetAttribute("Amount"),delivered+carried),"真實食物堆減少量等於已交貨與尚攜帶量")
 check(sameBalances(expected,balances()) and equal(secondInitial.food+delivered-player:GetAttribute("food"),50)
  and equal(secondInitial.wood-player:GetAttribute("wood"),25),"獨立餘額證明食物淨支出 50、木材淨支出 25，沒有其他資源變動")
 check(#owned(folders.buildings)==2 and #workers()==initialVillagers+1 and #owned(folders.units)==initialUnits+1,"投降前真實模型仍只有一棟新增房屋與一個新增村民")
 local second=finish(secondBegan,balances())
 check(second.matchId~=first.matchId,"第二局使用不同報告識別，沒有沿用前局快照")
 for _,key in ipairs(resourceKeys) do
  check(equal(second.resourcesSpent[key],({food=50,wood=25,gold=0,stone=0})[key]),"覆盤淨支出與獨立真實扣款一致："..key)
  check(equal(second.resourcesDelivered[key],key=="food" and delivered or 0),"覆盤交貨與正式 DeliveredResources、實際餘額一致："..key)
 end
 check(second.buildingsCompleted==1 and second.villagersTrained==1 and second.militaryTrained==0,"覆盤生產與完工房屋、新增村民實例相符，免費初始模型不計")
 for _,key in ipairs({"damageDealt","unitsKilled","buildingsKilled","unitsLost","buildingsLost"}) do check(second[key]==0,"沒有真實戰鬥，投降清場不產生戰鬥數據："..key) end
 uiChecks+=ReportTests.Run()
 restart()
 assert(os.clock()<deadline,"[MATCH_REPORT_FLOW FAIL] 全程已超過期限")
 print(string.format("[MATCH_REPORT_FLOW COMPLETE] %d 事實／控制檢查；%d 正式 UI 檢查；兩局正常開局、投降與重開；%.1f 秒",checks,uiChecks,os.clock()-started))
 return {checks=checks,uiChecks=uiChecks,elapsedSeconds=os.clock()-started,firstMatchId=first.matchId,secondMatchId=second.matchId}
end

function Tests.Run(options)
 assert(not Tests.running,"[MATCH_REPORT_FLOW FAIL] 此測試已在執行")
 Tests.running=true
 local connections={}
 local ok,result=xpcall(function() return run(options,connections) end,debug.traceback)
 for _,connection in ipairs(connections) do connection:Disconnect() end
 Tests.running=false
 if not ok then
  warn("[MATCH_REPORT_FLOW FAIL] 保留失敗對局供檢查；沒有重開或強制清場")
  error(result,0)
 end
 return result
end
return Tests
