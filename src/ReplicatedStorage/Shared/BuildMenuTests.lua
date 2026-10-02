-- Explicit Studio CLIENT rendering checks on a fresh Play match.
-- Temporarily changes local Age/resources/selection; restores them even when an assertion fails.
-- Local attribute snapshots exercise the live PlayerGui, not server age advancement or payments.
-- Command Bar require has a separate cache: use the live game's probes, never a new GUI instance.
local Tests={}
local categories={
 {key="economy",name="經濟",buildings={"House","Mill","LumberCamp","MiningCamp","Farm","Market","TownCenter"}},
 {key="military",name="軍事",buildings={"Barracks","ArcheryRange","Stable","Blacksmith","SiegeWorkshop"}},
 {key="defense",name="防禦",buildings={"Tower","Wall","Castle","Monastery","University","Wonder"}},
}
-- Independent expected menus catch regressions in both the rules and the rendered categories.
local expectedByAge={
 [1]={
  {"House","Mill","LumberCamp","MiningCamp","Farm","Market"},
  {"Barracks","ArcheryRange","Stable","Blacksmith"},
  {"Tower","Wall"},
 },
 [2]={
  {"House","Mill","LumberCamp","MiningCamp","Farm","Market","TownCenter"},
  {"Barracks","ArcheryRange","Stable","Blacksmith","SiegeWorkshop"},
  {"Tower","Wall","Castle","Monastery","University"},
 },
 [3]={categories[1].buildings,categories[2].buildings,categories[3].buildings},
 [4]={categories[1].buildings,categories[2].buildings,categories[3].buildings},
}
local function gray(color)
 return math.max(color.R,color.G,color.B)-math.min(color.R,color.G,color.B)<=2/255
end
function Tests.Run()
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"只能在 Studio Play 客戶端執行")
 local player=game.Players.LocalPlayer
 assert(workspace:GetAttribute("MatchPhase")=="Playing","先開始新的測試戰局")
 local RS=game:GetService("ReplicatedStorage")
 local Config=require(RS.GameData.GameConfig)
 local Rules=require(RS.Shared.BuildMenuRules)
 local screen=player.PlayerGui:WaitForChild("AOE2_MainGUI",5)
 assert(screen,"實際 PlayerGui HUD 未初始化")
 local selection=screen:WaitForChild("RTSSelectionProbe",5)
 local hud=screen:WaitForChild("RTSHUDProbe",5)
 assert(selection and hud,"實際客戶端測試探針未初始化")
 local touch=game:GetService("UserInputService").TouchEnabled
 local checks=0
 local function check(ok,message)
  assert(ok,"[BUILD_MENU_TEST FAIL] "..message); checks+=1; print("[BUILD_MENU_TEST PASS] "..message)
 end
 local function find(name) return screen:FindFirstChild(name,true) end
 local function settle() RunService.Heartbeat:Wait(); RunService.Heartbeat:Wait() end
 local function choose(models)
  assert(selection:Invoke(models)==true,"無法變更實際遊戲選取")
  settle()
 end
 local function page(index)
  assert(hud:Invoke("buildPage",index)==true,"無法切換建造分類")
  settle()
 end
 local function checkChooser(message)
  local state=hud:Invoke()
  check(state.tab=="build" and state.buildCategory==nil and state.pageCount==1,message)
  local commands=find("Commands")
  local count=0
  for _,button in ipairs(commands:GetChildren()) do
   if button:IsA("GuiButton") and button.Name:sub(1,8)=="Command_" then count+=1 end
  end
  check(count==0,"分類入口先不顯示任何建築指令")
  for _,category in ipairs(categories) do
   local button=find("BuildPage_"..category.key)
   check(button and button:IsA("GuiButton") and button.Visible,"分類入口顯示按鈕："..category.name)
  end
  check(not find("BackBuildCategories").Visible,"分類入口隱藏返回按鈕")
 end
 local function categoriesMenu()
  assert(hud:Invoke("buildCategories")==true,"無法返回建造分類")
  settle()
  checkChooser("返回三個分類按鈕")
 end
 local initial={selection=selection:Invoke(),hud=hud:Invoke(),attributes={}}
 local attributeKeys={"Age","wood","food","gold","stone"}
 for _,key in ipairs(attributeKeys) do initial.attributes[key]=player:GetAttribute(key) end
 assert(type(initial.hud)=="table" and not initial.hud.modal,"請先關閉選單與確認視窗")
 local base,worker
 for _,model in ipairs(workspace.Buildings:GetChildren()) do
  if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType")=="TownCenter" then base=model; break end
 end
 for _,model in ipairs(workspace.Units:GetChildren()) do
  if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("UnitType")=="villager" then worker=model; break end
 end
 assert(base and worker,"需要己方市鎮中心與村民")
 local ok,err=xpcall(function()
  check(type(Config.BuildPages)=="table" and #Config.BuildPages==3,"共用設定包含三個建造分類")
  local classified={}
  for index,category in ipairs(categories) do
   local actual=Config.BuildPages[index]
   check(actual and actual.key==category.key and actual.name==category.name,"分類順序與文字："..category.name)
   check(#actual.buildings==#category.buildings,"分類項目數："..category.name)
   for item,kind in ipairs(category.buildings) do
    check(actual.buildings[item]==kind and not classified[kind],"建築只屬於指定分類："..kind)
    classified[kind]=true
   end
  end
  local total=0
  for _,kind in ipairs(Config.BuildOrder) do total+=1; check(classified[kind],"每種可建建築都有分類："..kind) end
  check(total==18,"三頁包含目前十八種建築")
  for _,key in ipairs({"wood","food","gold","stone"}) do player:SetAttribute(key,10000) end
  player:SetAttribute("Age",1)
  choose({base}); choose({worker})
  checkChooser("首次選取村民先顯示三個分類按鈕")
  page(2)
  player:SetAttribute("Age",2)
  local ageRefreshDeadline=os.clock()+2
  repeat RunService.Heartbeat:Wait() until find("Command_SiegeWorkshop")~=nil or os.clock()>=ageRefreshDeadline
  check(hud:Invoke().buildCategory==2 and hud:Invoke().page==2 and find("Command_SiegeWorkshop")~=nil,"時代更新保留所選軍事分類並更新可見建築")
  categoriesMenu()
  for age=1,4 do
   player:SetAttribute("Age",age)
   choose({worker})
   checkChooser("時代 "..age.." 分類入口保持三個選擇")
   for index,category in ipairs(categories) do
    page(index)
    local state=hud:Invoke()
    check(state.tab=="build" and state.buildCategory==index and state.page==index and state.pageCount==3,"時代 "..age.." 正確切到"..category.name.."頁")
    for _,entry in ipairs(categories) do
     local categoryButton=find("BuildPage_"..entry.key)
     check(categoryButton and categoryButton:IsA("GuiButton") and not categoryButton.Visible,"建築頁隱藏分類入口按鈕："..entry.name)
    end
    check(find("BackBuildCategories").Visible,"建築頁顯示返回分類按鈕")
    for _,name in ipairs({"Tab_build","Tab_train","Tab_research"}) do
     local oldTab=find(name)
     check(oldTab and not oldTab.Visible,"村民隱藏通用分頁："..name)
    end
    local expected=expectedByAge[age][index]
    local expectedSet={}; for _,kind in ipairs(expected) do expectedSet[kind]=true end
    local items=Rules.items(Config,index,age)
    check(#items==#expected,"時代 "..age.." 分類規則項目數："..category.name)
    local commands=find("Commands")
    check(commands and commands:IsA("ScrollingFrame") and commands.ClipsDescendants,"指令容器裁切捲動內容")
    local actualCount=0
    for _,button in ipairs(commands:GetChildren()) do
     if button:IsA("GuiButton") and button.Name:sub(1,8)=="Command_" then
      actualCount+=1
      check(expectedSet[button.Name:sub(9)]==true,"實際指令沒有混入其他分類或過遠時代："..button.Name)
     end
    end
    check(actualCount==#expected,"時代 "..age.." 實際指令數："..category.name)
    for item,kind in ipairs(expected) do
     local button=find("Command_"..kind)
     check(button and button:IsA("GuiButton") and button.Visible,"實際 PlayerGui 顯示："..kind)
     local locked=(Config.Buildings[kind].minAge or 1)>age
     check(items[item].kind==kind and items[item].locked==locked,"規則保留分類順序與時代狀態："..kind)
     check(button:GetAttribute("AgeLocked")==locked,"時代鎖定標記："..kind)
     if not locked then check(button:GetAttribute("Unavailable")==false,"資源充足時本時代建築可以使用："..kind) end
     if locked then
      local title,cost,icon=button:FindFirstChild("CommandTitle"),button:FindFirstChild("CommandCost"),button:FindFirstChild("CommandIcon")
      check(button:GetAttribute("Unavailable")==true,"下一時代建築不可使用："..kind)
      check(title and cost and gray(button.BackgroundColor3) and gray(title.TextColor3) and gray(cost.TextColor3),"下一時代背景、名稱與需求文字呈灰色："..kind)
      check(cost.Text:find(Config.Ages[age+1].name,1,true)~=nil,"灰色建築顯示下一時代需求："..kind)
      check(icon and (icon:IsA("ViewportFrame") and gray(icon.ImageColor3) or icon:IsA("TextLabel") and gray(icon.TextColor3)),"下一時代圖示呈灰色："..kind)
      if icon:IsA("ViewportFrame") then
       local parts=0; local allGray=true
       for _,part in ipairs(icon:GetDescendants()) do
        if part:IsA("BasePart") then parts+=1; if not gray(part.Color) then allGray=false end end
       end
       check(parts>0 and allGray,"下一時代的立體建築預覽已轉為灰階："..kind)
      end
     end
    end
    for _,kind in ipairs(Config.BuildOrder) do
     if not expectedSet[kind] then check(find("Command_"..kind)==nil,"此頁先不顯示："..kind) end
    end
    if touch then
     check(commands.ScrollingDirection==Enum.ScrollingDirection.X,"手機建造分類使用橫向捲動")
     local first=find("Command_"..expected[1])
     for item=2,#expected do
      local button=find("Command_"..expected[item])
      check(math.abs(button.AbsolutePosition.Y-first.AbsolutePosition.Y)<1,"手機同一分類維持單列："..expected[item])
     end
     if #expected>4 then
      check(commands.ScrollingEnabled and commands.CanvasSize.X.Offset>commands.Size.X.Offset,"手機較長分類啟用橫向捲動")
      commands.CanvasPosition=Vector2.new(math.max(0,commands.AbsoluteCanvasSize.X-commands.AbsoluteSize.X),0); settle()
      local last=find("Command_"..expected[#expected])
      check(last.AbsolutePosition.X>=commands.AbsolutePosition.X-1
       and last.AbsolutePosition.X+last.AbsoluteSize.X<=commands.AbsolutePosition.X+commands.AbsoluteSize.X+1,"手機捲至末端後最後一項完整可見")
      commands.CanvasPosition=Vector2.zero
     end
    elseif #expected>6 then
     local first,last=find("Command_"..expected[1]),find("Command_"..expected[7])
     check(last.AbsolutePosition.Y>first.AbsolutePosition.Y,"桌面第七項位於同頁第二列")
    end
    categoriesMenu()
   end
  end
  player:SetAttribute("Age",1)
  choose({worker}); page(1)
  player:SetAttribute("wood",0); page(1)
  local house=find("Command_House")
  local cost=house and house:FindFirstChild("CommandCost")
  check(house and house:GetAttribute("AgeLocked")==false,"資源不足仍保留本時代的房屋")
  check(house:GetAttribute("Unavailable")==true,"資源不足的本時代建築不可使用")
  check(cost and cost.TextColor3.R>cost.TextColor3.G and cost.TextColor3.R>cost.TextColor3.B,"資源不足以紅色價格標示")
  page(2)
  check(hud:Invoke("page",1)==true,"下一頁操作可切換建造分類"); settle()
  check(hud:Invoke().page==3 and find("Command_Tower")~=nil,"下一頁切至防禦分類")
  check(hud:Invoke("page",-1)==true,"上一頁操作可切換建造分類"); settle()
  check(hud:Invoke().page==2 and find("Command_Barracks")~=nil,"上一頁切至軍事分類")
  categoriesMenu()
  page(3)
  check(hud:Invoke().buildCategory==3 and find("Command_Tower")~=nil,"返回入口後可重新選防禦分類")
  choose({base})
  check(find("Command_villager")~=nil and find("Tab_train").Visible,"選市鎮中心恢復生產頁")
  for _,category in ipairs(categories) do check(not find("BuildPage_"..category.key).Visible,"生產建築隱藏村民分類："..category.name) end
  choose({worker})
  checkChooser("從建築切回村民重設為分類選擇")
  choose({})
  check(find("Command_House")==nil,"清除選取後隱藏建造指令")
  for _,category in ipairs(categories) do check(not find("BuildPage_"..category.key).Visible,"空選取隱藏村民分類："..category.name) end
 end,debug.traceback)
 for _,key in ipairs(attributeKeys) do player:SetAttribute(key,initial.attributes[key]) end
 selection:Invoke(initial.selection)
 if initial.hud.tab=="build" then
  if initial.hud.buildCategory then hud:Invoke("buildPage",initial.hud.buildCategory)
  else hud:Invoke("buildCategories") end
 elseif initial.hud.tab=="train" or initial.hud.tab=="research" then
  hud:Invoke("tab",initial.hud.tab)
  hud:Invoke("page",initial.hud.page-1)
 end
 settle()
 if not ok then error(err,0) end
 print(string.format("[BUILD_MENU_TEST COMPLETE] %d rendering checks; local attributes/selection restored",checks))
 return checks
end
return Tests
