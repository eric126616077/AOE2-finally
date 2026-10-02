-- Explicit Studio CLIENT test. Changes only local selection/tabs/topbar visibility; never deletes objects.
-- Uses the live game's probes because Command Bar require has a separate cache.
local Tests={}
function Tests.Run()
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"只能在 Studio Play 客戶端執行")
 local player=game.Players.LocalPlayer
 assert(workspace:GetAttribute("MatchPhase")=="Playing","先開始新的測試戰局")
 local screen=player.PlayerGui:WaitForChild("AOE2_MainGUI")
 local topScreen=player.PlayerGui:WaitForChild("AOE2_TopbarGUI",5)
 assert(topScreen and topScreen:IsA("ScreenGui"),"獨立頂列未初始化")
 local GuiService=game:GetService("GuiService")
 local touch=game:GetService("UserInputService").TouchEnabled
 local selection=screen:WaitForChild("RTSSelectionProbe",5)
 local input=screen:WaitForChild("RTSInputProbe",5)
 local hudProbe=screen:WaitForChild("RTSHUDProbe",5)
 assert(selection and input and hudProbe,"實際客戶端測試探針未初始化")
 local checks=0
 local function check(ok,message)
  assert(ok,"[HUD_TEST FAIL] "..message); checks+=1; print("[HUD_TEST PASS] "..message)
 end
 local function settle() RunService.Heartbeat:Wait(); RunService.Heartbeat:Wait() end
 local function find(name) return screen:FindFirstChild(name,true) or topScreen:FindFirstChild(name,true) end
 local function choose(models) selection:Invoke(models); settle() end
 local function inspect(point)
  -- AbsolutePosition on either ScreenGui uses the same CoreUI coordinate origin.
  local result=input:Invoke(point+GuiService:GetGuiInset())
  assert(type(result)=="table" and type(result.blocked)=="boolean" and type(result.modal)=="boolean","UI 命中探針回傳不合法")
  return result
 end
 local topEnabled=topScreen.Enabled
 local topDisabledForCheck=false
 local initial=selection:Invoke()
 local initialHud=hudProbe:Invoke()
 local base,worker
 for _,model in ipairs(workspace.Buildings:GetChildren()) do
  if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType")=="TownCenter" then base=model; break end
 end
 for _,model in ipairs(workspace.Units:GetChildren()) do
  if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("UnitType")=="villager" then worker=model; break end
 end
 assert(base and worker,"需要主城與村民")
 local ok,err=xpcall(function()
  -- A startup notice legitimately covers part of short landscape terrain.
  -- Check the actual adjacent ground once this transient overlay has gone away.
  local notice=find("Notice"); local deadline=os.clock()+6
  while notice and notice.Visible and os.clock()<deadline do RunService.Heartbeat:Wait() end
  check(not notice or not notice.Visible,"短暫通知關閉後驗收可見地面")
  choose({})
  check(find("SelectionInfo")==nil,"移除整塊選取資訊面板")
  local oldEmptyTitle=false
  for _,root in ipairs({screen,topScreen}) do
   for _,object in ipairs(root:GetDescendants()) do
    if object:IsA("TextLabel") and object.Text=="建立你的帝國" then oldEmptyTitle=true end
   end
  end
  check(not oldEmptyTitle,"空選取不再顯示建立你的帝國面板文字")
  check(not find("Command_House"),"未選取村民時不顯示建築圖示")
  choose({worker})
  check(not find("Command_House") and not find("Tab_build").Visible,"選取村民先顯示分類選擇")
  local categoryButtons=0
  for _,category in ipairs({"economy","military","defense"}) do
   local categoryButton=find("BuildPage_"..category)
   check(categoryButton and categoryButton.Visible,"村民顯示建造分類："..category)
   categoryButtons+=1
  end
  local commands=find("Commands")
  local commandCount=0
  for _,command in ipairs(commands:GetChildren()) do
   if command:IsA("GuiButton") and command.Name:sub(1,8)=="Command_" then commandCount+=1 end
  end
  check(categoryButtons==3 and commandCount==0,"分類入口只有三個分類按鈕，尚未列出建築")
  check(not find("Tab_train").Visible and not find("Tab_research").Visible,"村民建造分類取代生產與科技頁")
  check(hudProbe:Invoke().buildCategory==nil and hudProbe:Invoke().pageCount==1,"村民預設停在分類選擇")
  check(not find("BackBuildCategories").Visible,"分類入口不顯示返回分類按鈕")
  check(hudProbe:Invoke("buildPage",1)==true,"選擇經濟分類"); settle()
  check(hudProbe:Invoke().buildCategory==1 and hudProbe:Invoke().page==1 and hudProbe:Invoke().pageCount==3,"選分類後進入經濟建築頁")
  for _,category in ipairs({"economy","military","defense"}) do
   check(not find("BuildPage_"..category).Visible,"建築頁隱藏分類入口："..category)
  end
  check(find("BackBuildCategories").Visible,"建築頁顯示返回分類按鈕")
  check(find("Command_Farm")~=nil and not find("Command_Barracks") and not find("Command_Tower"),"經濟頁只顯示經濟建築")
  if not touch then
   local first,last=find("Command_House"),find("Command_TownCenter")
   if last then check(last.AbsolutePosition.Y>first.AbsolutePosition.Y,"經濟頁第七項位於桌面指令格第二列") end
  end
  check(hudProbe:Invoke("buildCategories")==true,"返回分類選擇"); settle()
  check(hudProbe:Invoke().buildCategory==nil and not find("Command_House"),"返回分類後不顯示建築")
  choose({base})
  check(find("Command_villager")~=nil and not find("Command_House"),"主城顯示訓練，隱藏村民建築")
  check(find("ProductionQueue").Visible and find("RallyButton")~=nil,"生產建築顯示佇列與集合點")
  check(find("ProductionQueue").Parent==find("CommandDock"),"生產佇列搬入指令面板")
  check(find("DeleteButton").Parent==find("CommandDock"),"刪除控制搬入指令面板")
  if not touch then
   check(find("DeleteButton").Visible,"桌面己方建築顯示刪除控制")
   check(find("ConstructionState").Visible and find("ConstructionState").Text=="✓ 建築已完工","完工狀態明確顯示")
  else
   check(not find("DeleteButton").Visible and find("TouchDeleteButton")~=nil,"手機使用操作列刪除控制")
   check(find("RallyButton").AbsoluteSize.X>=44 and find("RallyButton").AbsoluteSize.Y>=44,"手機集合點保持可點擊尺寸")
  end
  hudProbe:Invoke("tab","research"); settle()
  check(find("Command_Loom")~=nil,"主城科技頁顯示織布機")
  if not touch then
   local commandCount,firstRow=0,true
   for _,command in ipairs(find("Commands"):GetChildren()) do
    if command:IsA("GuiButton") and command.Name:sub(1,8)=="Command_" then
     commandCount+=1
     if command.AbsolutePosition.Y+command.AbsoluteSize.Y>find("ConstructionState").AbsolutePosition.Y+1 then firstRow=false end
    end
   end
   check(commandCount>0 and commandCount<=6 and firstRow,"科技指令限於第一列，保留佇列與選取摘要空間")
  end
  choose({worker})
  check(not find("Command_House") and hudProbe:Invoke().tab=="build" and hudProbe:Invoke().buildCategory==nil,"從主城科技切到村民，自動返回分類選擇")
  choose({workspace.Resources:GetChildren()[1]})
  check(not find("Command_House") and not find("DeleteButton").Visible,"中立資源只顯示資訊")
  choose({worker})
  check(hudProbe:Invoke("delete")==true,"己方村民可開啟刪除確認")
  settle()
  check(find("DeleteConfirmOverlay").Visible and input:Invoke(Vector2.new(600,200)).modal,"刪除確認阻擋世界輸入")
  choose({base})
  check(not find("DeleteConfirmOverlay").Visible,"變更選取立即取消刪除快照")
  local dock=find("CommandDock")
  check(inspect(dock.AbsolutePosition+Vector2.new(20,20)).blocked,"指令面板不穿透")
  check(not inspect(dock.AbsolutePosition+Vector2.new(80,-10)).blocked,"緊鄰底部面板的地面可點擊")
  check(screen.IgnoreGuiInset==false and screen.Canvas:FindFirstChildOfClass("UIScale")~=nil,"保留安全區域與UIScale")
  for _,key in ipairs({"wood","food","gold","stone"}) do
   local card=find("Resource_"..key)
   check(card~=nil and card.AbsoluteSize.X>0,"資源 "..key.." 顯示於實際PlayerGui")
   check(inspect(card.AbsolutePosition+card.AbsoluteSize/2).blocked,"資源 "..key.." 點擊不穿透")
  end
  if not touch then
   local header=find("EmpireBar")
   local free=GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)
   local position,size=header.AbsolutePosition,header.AbsoluteSize
   check(topScreen.Enabled and header:IsDescendantOf(topScreen)
    and topScreen.ScreenInsets==Enum.ScreenInsets.TopbarSafeInsets,"桌面資源列使用 Roblox 頂列安全區域")
   check(size.X>0 and size.Y>0 and position.X>=free.Min.X-1 and position.Y>=free.Min.Y-1
    and position.X+size.X<=free.Max.X+1 and position.Y+size.Y<=free.Max.Y+1,"整條資源列位於 CoreGui 可用頂列範圍")
   check(position.Y<0,"桌面資源列與 Roblox 按鈕同一行")
   local groundCard=find("Resource_gold")
   local belowHeader=Vector2.new(groundCard.AbsolutePosition.X+groundCard.AbsoluteSize.X/2,position.Y+size.Y+8)
   check(not inspect(belowHeader).blocked,"頂列下鄰可見地面不被資源列攔截")
   check(header.AbsolutePosition.Y+header.AbsoluteSize.Y<dock.AbsolutePosition.Y,"資源列與指令面板間保留戰場")
   check(find("IdleVillagerButton"):GetAttribute("IdleCount")~=nil,"閒置村民數由真實單位更新")
   local map=find("MinimapPanel")
   local dockRight=dock.AbsolutePosition.X+dock.AbsoluteSize.X
   check(dockRight<map.AbsolutePosition.X,"指令面板與小地圖之間保留地面")
   local formerInfo=Vector2.new((dockRight+map.AbsolutePosition.X)/2,dock.AbsolutePosition.Y+dock.AbsoluteSize.Y/2)
   check(not inspect(formerInfo).blocked,"移除選取面板後原區域地面可點擊")
   local card=find("Resource_wood")
   local center=card.AbsolutePosition+card.AbsoluteSize/2
   topEnabled=topScreen.Enabled
   topDisabledForCheck=true; topScreen.Enabled=false
   check(not inspect(center).blocked,"停用頂列後原資源卡位置不攔截世界輸入")
   topScreen.Enabled=topEnabled; topDisabledForCheck=false
   check(inspect(center).blocked,"恢復頂列後資源卡重新攔截世界輸入")
  else
   local workers={}
   for _,unit in ipairs(workspace.Units:GetChildren()) do
    if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then table.insert(workers,unit) end
   end
   assert(#workers>=2,"手機多選驗收至少需要兩位村民")
   choose(workers)
   check(find("TargetContext").Text==#workers.." 個單位","手機多選顯示實際數量")
   check(find("TouchSelectionState").Visible and find("TouchSelectionState").Text:find("村民 "..#workers,1,true)~=nil,"手機多選顯示村民數與總生命值")
  end
 end,debug.traceback)
 if topDisabledForCheck then topScreen.Enabled=topEnabled end
 hudProbe:Invoke("cancelDelete"); selection:Invoke(initial)
 if initialHud.tab=="build" then
  if initialHud.buildCategory then hudProbe:Invoke("buildPage",initialHud.buildCategory)
  else hudProbe:Invoke("buildCategories") end
 elseif initialHud.tab=="train" or initialHud.tab=="research" then
  hudProbe:Invoke("tab",initialHud.tab); hudProbe:Invoke("page",initialHud.page-1)
 end
 if not ok then error(err,0) end
 print(string.format("[HUD_TEST COMPLETE] %d checks",checks))
 return checks
end
return Tests
