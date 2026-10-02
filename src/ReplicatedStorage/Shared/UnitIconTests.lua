-- Explicit Studio CLIENT integration checks. Run on a fresh, active sandbox match.
-- Run once on desktop and once in the Studio touch emulator to verify both layouts.
-- Only local fixtures, Age and selection change; no server remote is fired.
-- Inspect the live PlayerGui probes: Command Bar require has a separate GUI cache.
local Tests={}
local kinds={"villager","infantry","spearman","archer","skirmisher","scout","cavalry","ram","mangonel","trebuchet"}
local buildingKinds={"TownCenter","House","Mill","LumberCamp","MiningCamp","Barracks","Farm","ArcheryRange","Stable",
 "Blacksmith","Market","Tower","Wall","Gate","Castle","SiegeWorkshop","Monastery","University","Wonder"}
local landmarks={villager="PickShaft",infantry="SwordBlade",spearman="LongSpear",archer="Bowstring",skirmisher="Javelin",
 scout="HorseHead",cavalry="HorseFaceplate",ram="RamLog",mangonel="ThrowingArm",trebuchet="Counterweight"}
local coreFields={
 {name="SelectedUnitAttack",attribute="Attack",prefix="攻擊 ",icon="attack"},
 {name="SelectedUnitArmor",attribute="Armor",prefix="護甲 ",icon="armor"},
 {name="SelectedUnitRange",attribute="Range",prefix="射程 ",icon="range"},
 {name="SelectedUnitAttackInterval",attribute="AttackInterval",prefix="間隔 ",suffix=" 秒",icon="interval"},
 {name="SelectedUnitSpeed",attribute="Speed",prefix="移速 ",icon="speed"},
 {name="SelectedUnitPopulation",icon="population"},
}
function Tests.Run()
 local Run=game:GetService("RunService")
 assert(Run:IsStudio() and Run:IsClient(),"只能在 Studio Play 客戶端執行")
 assert(workspace:GetAttribute("MatchPhase")=="Playing","先在新的 Play 工作階段開始自由建設測試局")
 local RS=game:GetService("ReplicatedStorage")
 local Config=require(RS.GameData.GameConfig)
 local Art=require(RS.Shared.Art)
 local Icons=require(RS.Shared.UnitIcons)
 local player=game.Players.LocalPlayer
 local screen=player.PlayerGui:WaitForChild("AOE2_MainGUI",5)
 assert(screen,"實際 PlayerGui HUD 未初始化")
 local selection=screen:WaitForChild("RTSSelectionProbe",5)
 local hud=screen:WaitForChild("RTSHUDProbe",5)
 local input=screen:WaitForChild("RTSInputProbe",5)
 assert(selection and hud and input,"實際客戶端測試探針未初始化")
 local unitFolder,buildingFolder=workspace:FindFirstChild("Units"),workspace:FindFirstChild("Buildings")
 assert(unitFolder and buildingFolder,"單位與建築容器未初始化")
 local touch=game:GetService("UserInputService").TouchEnabled
 local initial={selection=selection:Invoke(),hud=hud:Invoke(),age=player:GetAttribute("Age")}
 assert(type(initial.hud)=="table" and not initial.hud.modal,"請先關閉選單與確認視窗")
 local checks,fixtures=0,{}
 local fixtureIcons
 local function check(ok,message)
  assert(ok,"[UNIT_ICON_TEST FAIL] "..message)
  checks+=1; print("[UNIT_ICON_TEST PASS] "..message)
 end
 local function settle() Run.Heartbeat:Wait(); Run.Heartbeat:Wait() end
 local function waitFor(predicate,message)
  local deadline=os.clock()+3
  repeat if predicate() then check(true,message); return end; Run.Heartbeat:Wait() until os.clock()>=deadline
  check(false,message)
 end
 local function find(name) return screen:FindFirstChild(name,true) end
 local function choose(models)
  assert(selection:Invoke(models)==true,"無法變更實際遊戲選取")
  settle()
 end
 local function inspect(point)
  local result=input:Invoke(point+game:GetService("GuiService"):GetGuiInset())
  assert(type(result)=="table" and type(result.blocked)=="boolean","UI 命中探針回傳不合法")
  return result
 end
 local function visible(object)
  while object do
   if object:IsA("GuiObject") and not object.Visible then return false end
   if object:IsA("ScreenGui") and not object.Enabled then return false end
   object=object.Parent
  end
  return true
 end
 local function core(model,isUnit)
  local kind=model:GetAttribute(isUnit and "UnitType" or "BuildingType")
  local data=isUnit and Config.Units[kind] or Config.Buildings[kind]
  for _,field in ipairs(coreFields) do
   local label=find(field.name)
   check(label and label:IsA("TextLabel"),"核心資訊使用獨立數值欄："..kind.." / "..field.name)
   if field.attribute=="Speed" and not isUnit then
    check(not label.Parent.Visible and not visible(label),"建築隱藏移速欄："..kind)
   else
    local expected=field.attribute and (field.prefix..string.format("%g",model:GetAttribute(field.attribute))..(field.suffix or ""))
     or isUnit and ("人口 "..(data.population or 1)) or ("人口上限 +"..(data.population or 0))
    check(visible(label) and label.Text==expected,"核心資訊使用實際數值："..kind.." / "..field.name)
    local shape=label.Parent:FindFirstChild("SelectionIcon")
    check(shape and shape:IsA("Frame") and shape:GetAttribute("IconKind")==field.icon and visible(shape),"核心資訊有可見數值圖示："..kind.." / "..field.name)
   end
  end
 end
 local function supplementalText()
  return find("SelectedUnitStatus").Text.."\n"..find("SelectedUnitStats").Text
 end
 local function icon(frame,kind,message)
  check(frame and frame:IsA("Frame") and frame:GetAttribute("UnitType")==kind,message)
  local shapes=0
  for _,object in ipairs(frame:GetDescendants()) do
   if object:IsA("GuiObject") and object.Visible and object.BackgroundTransparency<1 then shapes+=1 end
  end
  check(shapes>=3,"圖示有可見造型內容："..kind)
  check(frame:FindFirstChild(landmarks[kind],true)~=nil,"圖示有此兵種的辨識造型："..kind)
 end
 local function fixture(kind,isUnit)
  local data=isUnit and Config.Units[kind] or Config.Buildings[kind]
  local model=Art.Create(kind,player:GetAttribute("TeamColor"))
  table.insert(fixtures,model)
  model.Name="_UnitIconTest_"..kind.."_"..#fixtures
  model.PrimaryPart=model:FindFirstChildWhichIsA("BasePart",true)
  -- Inert artwork below the map cannot intercept terrain clicks or affect the match.
  for _,part in ipairs(model:GetDescendants()) do
   if part:IsA("BasePart") then part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false end
  end
  model:PivotTo(CFrame.new(0,-1000,0))
  model:SetAttribute("RTSManaged",true)
  model:SetAttribute(isUnit and "UnitType" or "BuildingType",kind)
  model:SetAttribute("DisplayName",data.name)
  model:SetAttribute("OwnerId",player.UserId)
  model:SetAttribute("OwnerName","圖示測試勢力")
  model:SetAttribute("TeamId",player:GetAttribute("TeamId"))
  model:SetAttribute("TeamColor",player:GetAttribute("TeamColor"))
  model:SetAttribute("MaxHP",data.hp+20)
  model:SetAttribute("HP",math.floor((data.hp+20)*.6))
  if isUnit then
   model:SetAttribute("Attack",data.damage+7)
   model:SetAttribute("Armor",(data.armor or 0)+2)
   model:SetAttribute("Speed",data.speed+1)
   model:SetAttribute("Range",data.range+3)
   model:SetAttribute("AttackInterval",.75)
   model:SetAttribute("Order","圖示測試待命")
   model:SetAttribute("Formation",Config.Formations.default)
   model:SetAttribute("Carrying",kind=="villager" and 7 or 0)
   model:SetAttribute("CarryType",kind=="villager" and "wood" or "")
   model:SetAttribute("CarryCapacity",25)
   for index,key in ipairs({"food","wood","gold","stone"}) do model:SetAttribute("GatherRate_"..key,index+4) end
  else
   model:SetAttribute("Attack",(data.damage or 0)+7)
   model:SetAttribute("Armor",4)
   model:SetAttribute("Range",(data.range or 0)+3)
   model:SetAttribute("AttackInterval",.75)
   model:SetAttribute("Complete",true)
   model:SetAttribute("UnderConstruction",false)
   model:SetAttribute("ConstructionProgress",1)
   model:SetAttribute("ConstructionStatus","已完工")
   model:SetAttribute("BuilderCount",0)
   model:SetAttribute("QueueRevision",0)
   model:SetAttribute("QueueCount",0)
   if kind=="Farm" then
    model:SetAttribute("ResourceType","food")
    model:SetAttribute("Amount",543)
    model:SetAttribute("MaxAmount",900)
   end
  end
  model.Parent=isUnit and unitFolder or buildingFolder
  return model
 end
 local function hpText(object,current,maximum,spaced)
  return object and object:IsA("TextLabel") and object.Text==string.format(spaced and "%d / %d" or "%d/%d",math.ceil(current),maximum)
 end
 local function restore()
  local restored,restoreError=xpcall(function()
   player:SetAttribute("Age",initial.age)
   local surviving={}
   for _,model in ipairs(initial.selection) do if model.Parent then table.insert(surviving,model) end end
   assert(selection:Invoke(surviving)==true,"無法還原原本選取")
   if initial.hud.tab=="build" then
    if initial.hud.buildCategory then hud:Invoke("buildPage",initial.hud.buildCategory) else hud:Invoke("buildCategories") end
   elseif initial.hud.tab=="train" or initial.hud.tab=="research" or initial.hud.tab=="formation" then
    hud:Invoke("tab",initial.hud.tab)
    for _=1,math.max(0,initial.hud.page-1) do
     local before=hud:Invoke().page
     hud:Invoke("page",1)
     if hud:Invoke().page==before then break end
    end
   end
  end,debug.traceback)
  if fixtureIcons then fixtureIcons:Destroy() end
  for _,model in ipairs(fixtures) do model:Destroy() end
  settle()
  if not restored then error(restoreError,0) end
 end
 local ok,err=xpcall(function()
  local count=0; for _ in pairs(Config.Units) do count+=1 end
  check(count==#kinds,"目前十種單位都納入圖示驗收")
  fixtureIcons=Instance.new("Frame")
  fixtureIcons.Name="UnitIconTestFixtures"; fixtureIcons.Visible=false; fixtureIcons.Parent=screen
  local units,byKind={},{}
  for _,kind in ipairs(kinds) do
   check(Config.Units[kind]~=nil,"單位設定存在："..kind)
   local created=Icons.Create(fixtureIcons,kind,UDim2.fromOffset(48,48),UDim2.fromOffset(0,0),Color3.fromRGB(81,158,199))
   icon(created,kind,"共用圖示可獨立建立："..kind)
   byKind[kind]=fixture(kind,true); table.insert(units,byKind[kind])
  end
  local panel=find("UnitSelectionPanel")
  check(panel and panel:IsA("Frame"),"實際 PlayerGui 包含單位資訊面板")
  check(find("UnitSelectionTitle") and find("UnitSelectionSummary"),"資訊面板包含名稱與選取摘要")
  choose({})
  check(not panel.Visible,"空選取隱藏單位資訊面板")
  for _,kind in ipairs(kinds) do
   local unit,data=byKind[kind],Config.Units[kind]
   choose({unit})
   check(panel.Visible and find("SingleUnitDetails").Visible and not find("UnitSelectionGrid").Visible,"單選顯示完整單位資訊："..kind)
   icon(find("SelectedUnitIcon"),kind,"單選顯示對應單位圖示："..kind)
   check(find("UnitSelectionTitle").Text==data.name and find("SelectedUnitName").Text==data.name,"單選名稱正確："..kind)
   check(hpText(find("SelectedUnitHP"),unit:GetAttribute("HP"),unit:GetAttribute("MaxHP"),true),"單選生命值正確："..kind)
   core(unit,true)
   local stats=find("SelectedUnitStats")
   check(stats and stats:IsA("TextLabel") and stats.Text:find(data.description,1,true)
    and stats.Text:find("類型",1,true) and stats.Text:find("訓練成本",1,true)
    and stats.Text:find("基礎訓練時間",1,true),"補充資訊顯示描述、類型、成本與訓練時間："..kind)
   check(not stats.Text:find("攻擊 "..(data.damage+7),1,true)
    and not stats.Text:find("攻擊間隔",1,true) and not stats.Text:find("攜帶：",1,true),"補充文字不重複核心資訊或持有物卡："..kind)
   check(find("SelectedUnitStatus").Text:find("圖示測試待命",1,true),"單選顯示目前指令："..kind)
   if kind=="villager" then
    local card,carryingText,carryingIcon=find("CarryingCard"),find("CarryingText"),find("CarryingIcon")
    check(card and visible(card) and carryingText and carryingText.Text=="木材 7 / 25","村民以獨立持有物卡顯示資源與容量")
    check(carryingIcon and carryingIcon:IsA("Frame") and carryingIcon:GetAttribute("IconKind")=="wood" and visible(carryingIcon),"村民持有物卡顯示木材圖示")
    for index,name in ipairs({"食物","木材","黃金","石材"}) do
     check(stats.Text:find("採集"..name.."："..(index+4),1,true),"村民顯示實際採集速率："..name)
    end
   else
    check(find("CarryingCard") and not visible(find("CarryingCard")),"軍隊隱藏村民持有物卡："..kind)
   end
  end
  local worker=byKind.villager
  choose({worker})
  local statsScroll=find("UnitStatsScroll")
  check(statsScroll and statsScroll:IsA("ScrollingFrame") and statsScroll.ScrollingEnabled
   and statsScroll.AbsoluteCanvasSize.Y>=find("SelectedUnitStats").AbsoluteSize.Y-1,"完整單位資訊保留在可捲動容器內")
  worker:SetAttribute("HP",9)
  waitFor(function() return hpText(find("SelectedUnitHP"),9,worker:GetAttribute("MaxHP"),true) end,"選取中的單位生命值即時更新")
  local singleFill=find("SelectedUnitHealth"):FindFirstChild("Fill")
  check(singleFill and math.abs(singleFill.Size.X.Scale-9/worker:GetAttribute("MaxHP"))<.001,"單選血條按真實生命比例縮放")
  check(singleFill.BackgroundColor3.R>singleFill.BackgroundColor3.G,"低生命值血條顯示紅色")
  worker:SetAttribute("Attack",31)
  waitFor(function() return find("SelectedUnitAttack").Text=="攻擊 31" end,"選取中的核心攻擊力即時更新")
  local resourceKeys={"food","wood","gold","stone"}
  local resourceNames={"食物","木材","黃金","石材"}
  for index,key in ipairs(resourceKeys) do
   worker:SetAttribute("CarryType",key); worker:SetAttribute("Carrying",7)
   waitFor(function()
    return find("CarryingText").Text==resourceNames[index].." 7 / 25" and find("CarryingIcon"):GetAttribute("IconKind")==key
   end,"村民持有物卡即時切換資源與圖示："..resourceNames[index])
  end
  -- The server can retain CarryType after delivery; zero amount must still read as empty hands.
  worker:SetAttribute("CarryType","wood"); worker:SetAttribute("Carrying",0)
  waitFor(function() return find("CarryingText").Text=="空手 · 0 / 25" end,"交貨後即使保留資源種類也顯示空手")
  worker:SetAttribute("OrderKind","gather")
  worker:SetAttribute("OrderTargetBuildingType","Farm")
  worker:SetAttribute("Order","採集 食物")
  waitFor(function() return find("SelectedUnitStatus").Text:find("採集農田",1,true) end,"村民採集農田顯示實際工作目標")
  worker:SetAttribute("OrderKind",nil); worker:SetAttribute("OrderTargetBuildingType",nil)
  worker:SetAttribute("Order","圖示測試移動")
  waitFor(function() return find("SelectedUnitStatus").Text:find("圖示測試移動",1,true) end,"選取中的單位指令即時更新")
  choose(units)
  local grid=find("UnitSelectionGrid")
  check(grid and grid:IsA("ScrollingFrame") and grid.Visible and not find("SingleUnitDetails").Visible,"框選顯示可捲動單位圖示清單")
  local total,maximum=0,0
  for index,unit in ipairs(units) do
   local tile=grid:FindFirstChild("SelectionUnit_"..index)
   check(tile and tile:IsA("GuiButton") and tile:GetAttribute("UnitType")==kinds[index],"框選保留每種單位的獨立圖示："..kinds[index])
   icon(tile:FindFirstChild("UnitIcon"),kinds[index],"框選圖示種類正確："..kinds[index])
   local hp,limit=unit:GetAttribute("HP"),unit:GetAttribute("MaxHP")
   check(tile:GetAttribute("HP")==hp and tile:GetAttribute("MaxHP")==limit and hpText(tile:FindFirstChild("UnitHealthText"),hp,limit,false),"每個圖示有獨立生命值："..kinds[index])
   local fill=tile:FindFirstChild("UnitHealthTrack"):FindFirstChild("Fill")
   check(fill and math.abs(fill.Size.X.Scale-hp/limit)<.001,"每個圖示有獨立血條："..kinds[index])
   total+=hp; maximum+=limit
  end
  check(find("UnitSelectionTitle").Text:find(tostring(#units),1,true)
   and find("UnitSelectionSummary").Text:find(string.format("%d / %d",total,maximum),1,true),"框選摘要顯示實際數量與總生命值")
  byKind.archer:SetAttribute("HP",11)
  waitFor(function() return grid.SelectionUnit_4:GetAttribute("HP")==11 and hpText(grid.SelectionUnit_4.UnitHealthText,11,byKind.archer:GetAttribute("MaxHP"),false) end,"框選中個別單位生命值即時更新")
  check(hud:Invoke("selectUnit",4)==true,"圖示探針呼叫與真實按鈕相同的選取 callback")
  settle()
  local selected=selection:Invoke()
  check(#selected==1 and selected[1]==byKind.archer and find("SelectedUnitName").Text==Config.Units.archer.name,"點選圖示 callback 變更實際遊戲選取")
  -- Exercise the supported selection maximum, including the final offscreen portrait.
  local large=table.clone(units)
  while #large<200 do table.insert(large,fixture("villager",true)) end
  choose(large)
  local tiles=0
  for _,object in ipairs(grid:GetChildren()) do if object:IsA("GuiButton") then tiles+=1 end end
  check(tiles==200 and grid:FindFirstChild("SelectionUnit_200")~=nil,"200 個框選單位全部有圖示，沒有截斷")
  settle()
  local horizontal=touch
  check(grid.ScrollingDirection==(horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y),"依真實裝置使用正確捲動方向")
  local overflow=horizontal and grid.AbsoluteCanvasSize.X-grid.AbsoluteSize.X or grid.AbsoluteCanvasSize.Y-grid.AbsoluteSize.Y
  check(grid.ScrollingEnabled and overflow>0,"大量框選可捲到清單末端")
  grid.CanvasPosition=horizontal and Vector2.new(overflow,0) or Vector2.new(0,overflow)
  settle()
  local last=grid.SelectionUnit_200
  check(last.AbsolutePosition.X>=grid.AbsolutePosition.X-1 and last.AbsolutePosition.Y>=grid.AbsolutePosition.Y-1
   and last.AbsolutePosition.X+last.AbsoluteSize.X<=grid.AbsolutePosition.X+grid.AbsoluteSize.X+1
   and last.AbsolutePosition.Y+last.AbsoluteSize.Y<=grid.AbsolutePosition.Y+grid.AbsoluteSize.Y+1,"捲至末端可完整看到最後一個圖示與生命值")
  grid.CanvasPosition=Vector2.zero
  -- Age affects only this client's menus. Do not activate training/queue buttons.
  player:SetAttribute("Age",4)
  local buildings={}
  local buildingCount=0; for _ in pairs(Config.Buildings) do buildingCount+=1 end
  check(buildingCount==#buildingKinds,"目前十八種建築都納入選取資訊驗收")
  for _,kind in ipairs(buildingKinds) do
   local data=Config.Buildings[kind]
   check(data~=nil,"建築設定存在："..kind)
   local building=fixture(kind,false); buildings[kind]=building
   choose({building})
   check(panel.Visible and find("SingleUnitDetails").Visible and not grid.Visible,"選取建築顯示完整獨立資訊："..kind)
   local portrait=find("SelectedBuildingIcon")
   check(portrait and portrait:IsA("ViewportFrame") and portrait:GetAttribute("BuildingType")==kind
    and portrait.Parent==find("PortraitHolder") and visible(portrait),"建築顯示對應圖像："..kind)
   check(portrait.CurrentCamera and portrait:FindFirstChildWhichIsA("WorldModel")
    and portrait:FindFirstChildWhichIsA("BasePart",true),"建築圖像包含模型與攝影機："..kind)
   check(find("SelectedUnitName").Text==data.name and visible(find("SelectedUnitName")),"建築名稱正確且可見："..kind)
   check(hpText(find("SelectedUnitHP"),building:GetAttribute("HP"),building:GetAttribute("MaxHP"),true),"建築生命值正確："..kind)
   local fill=find("SelectedUnitHealth"):FindFirstChild("Fill")
   check(fill and math.abs(fill.Size.X.Scale-building:GetAttribute("HP")/building:GetAttribute("MaxHP"))<.001,"建築血條使用實際比例："..kind)
   core(building,false)
   check(not visible(find("CarryingCard")),"建築不顯示村民持有物卡："..kind)
   local stats=find("SelectedUnitStats")
   check(stats and stats.Text:find(data.description,1,true) and stats.Text:find("建造成本",1,true)
    and stats.Text:find("建造時間",1,true),"建築補充資訊包含描述、成本與建造時間："..kind)
  end
  local tower=buildings.Tower
  choose({tower})
  tower:SetAttribute("HP",73); tower:SetAttribute("Attack",42)
  waitFor(function()
   return hpText(find("SelectedUnitHP"),73,tower:GetAttribute("MaxHP"),true) and find("SelectedUnitAttack").Text=="攻擊 42"
  end,"選取中的建築生命值與攻擊力即時更新")
  local towerFill=find("SelectedUnitHealth"):FindFirstChild("Fill")
  check(towerFill and math.abs(towerFill.Size.X.Scale-73/tower:GetAttribute("MaxHP"))<.001,"建築生命更新同步血條比例")
  local house=buildings.House
  choose({house})
  house:SetAttribute("Complete",false); house:SetAttribute("UnderConstruction",true)
  house:SetAttribute("ConstructionProgress",.42); house:SetAttribute("BuilderCount",3)
  house:SetAttribute("ConstructionStatus","圖示測試施工"); house:SetAttribute("ConstructionRemaining",12)
  waitFor(function()
   local details=supplementalText()
   return details:find("42%",1,true) and details:find("圖示測試施工",1,true)
    and (details:match("村民[^\n]*3") or details:match("3[^\n]*村民"))
  end,"施工中的建築顯示進度、狀態與施工村民數")
  house:SetAttribute("Complete",true); house:SetAttribute("UnderConstruction",false)
  house:SetAttribute("ConstructionProgress",1); house:SetAttribute("BuilderCount",0); house:SetAttribute("ConstructionStatus","已完工")
  waitFor(function() return supplementalText():find("完工",1,true) and not supplementalText():find("42%",1,true) end,"建築完工後清除過期施工資訊")
  local base=buildings.TownCenter
  choose({base})
  base:SetAttribute("Training",Config.Units.villager.name); base:SetAttribute("QueueCount",3)
  base:SetAttribute("TrainingRemaining",17); base:SetAttribute("TrainingProgress",.4)
  waitFor(function()
   local details=supplementalText()
   return details:find("訓練",1,true) and details:find(Config.Units.villager.name,1,true)
    and details:find("佇列",1,true) and details:find("3",1,true) and details:find("17",1,true)
  end,"生產建築顯示訓練內容、佇列與剩餘時間")
  base:SetAttribute("Training",nil); base:SetAttribute("QueueCount",0); base:SetAttribute("TrainingRemaining",nil)
  base:SetAttribute("Research",Config.Technologies.Loom.name); base:SetAttribute("ResearchRemaining",13)
  base:SetAttribute("ResearchProgress",.5)
  waitFor(function()
   local details=supplementalText()
   return details:find("研究",1,true) and details:find(Config.Technologies.Loom.name,1,true) and details:find("13",1,true)
  end,"生產建築即時切換為科技研究資訊")
  base:SetAttribute("Research",nil); base:SetAttribute("ResearchRemaining",nil); base:SetAttribute("ResearchProgress",nil)
  local farm=buildings.Farm
  choose({farm})
  check(supplementalText():find("543",1,true) and supplementalText():find("900",1,true)
   and supplementalText():find("食物",1,true),"農田顯示剩餘食物與總容量")
  farm:SetAttribute("Amount",123)
  waitFor(function() local details=supplementalText(); return details:find("123",1,true) and not details:find("543",1,true) end,"農田剩餘食物即時更新")
  for _,kind in ipairs(kinds) do
   local buildingKind=Config.Units[kind].trainsAt[1]
   local building=buildings[buildingKind]
   if not building then building=fixture(buildingKind,false); buildings[buildingKind]=building end
   choose({building}); hud:Invoke("tab","train"); settle()
   local command=find("Command_"..kind)
   check(command and command:IsA("GuiButton"),"訓練頁保留單位按鈕："..kind)
   icon(command:FindFirstChild("CommandIcon"),kind,(touch and "手機" or "桌面").."訓練按鈕顯示單位圖示："..kind)
   if touch then check(command.AbsoluteSize.X>=44 and command.AbsoluteSize.Y>=44,"手機訓練按鈕保留可點擊尺寸："..kind) end
   building:SetAttribute("QueueCount",1)
   building:SetAttribute("QueueKind_1",kind)
   building:SetAttribute("QueueRevision",building:GetAttribute("QueueRevision")+1)
   building:SetAttribute("TrainingProgress",.4)
   waitFor(function() local slot=find("QueueSlot_1"); local queueIcon=slot and slot:FindFirstChild("QueueIcon"); return queueIcon and queueIcon:GetAttribute("UnitType")==kind end,"訓練佇列即時顯示單位圖示："..kind)
   icon(find("QueueSlot_1"):FindFirstChild("QueueIcon"),kind,"佇列圖示種類正確："..kind)
   check(panel.Visible and find("SelectedBuildingIcon")~=nil,"選取生產建築仍顯示建築圖像與資訊："..kind)
  end
  choose(units)
  local notice=find("Notice"); local deadline=os.clock()+6
  while notice and notice.Visible and os.clock()<deadline do Run.Heartbeat:Wait() end
  check(not notice or not notice.Visible,"短暫通知關閉後驗收地面命中")
  check(inspect(panel.AbsolutePosition+panel.AbsoluteSize/2).blocked,"單位資訊面板攔截輸入，不向地面穿透")
  check(not inspect(panel.AbsolutePosition+Vector2.new(panel.AbsoluteSize.X/2,-8)).blocked,"單位資訊面板緊鄰上緣地面仍可點擊")
  check(screen.IgnoreGuiInset==false and screen.Canvas:FindFirstChildOfClass("UIScale")~=nil,"新增面板沿用安全區域與 UIScale")
  choose({})
  check(not panel.Visible and not grid.Visible,"清除框選後隱藏單位圖示與資訊")
 end,debug.traceback)
 local restored,restoreError=pcall(restore)
 if not restored then error("[UNIT_ICON_TEST CLEANUP FAIL] "..tostring(restoreError)..(ok and "" or "\n"..err),0) end
 if not ok then error(err,0) end
 print(string.format("[UNIT_ICON_TEST COMPLETE] %d checks; %s; fixtures/Age/selection restored; physical clicks require separate UI verification",checks,touch and "touch" or "desktop"))
 return checks
end
return Tests
