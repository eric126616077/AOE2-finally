-- Studio CLIENT only; requiring this module performs no work.
-- Run() starts a fresh single-player sandbox if needed, then uses normal commands to
-- verify villager auto-work: empty-selection construction, follow-up work, player hold,
-- the empty-selection build menu and the menu toggle. It leaves one House in the test match.
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local Tests={running=false}
local function run()
 assert(RunService:IsStudio() and RunService:IsClient(),"[AUTO_WORK FAIL] 僅限 Studio Play 客戶端")
 assert(#Players:GetPlayers()==1,"[AUTO_WORK FAIL] 請使用新的單人沙盒工作階段")
 local player=Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
 local deadline=os.clock()+150
 local checks=0
 local function check(condition,message)
  assert(condition,"[AUTO_WORK FAIL] "..message)
  checks+=1
  print("[AUTO_WORK PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=math.min(deadline,os.clock()+seconds)
  repeat
   if predicate() then check(true,message); return end
   assert(os.clock()<untilTime,"[AUTO_WORK FAIL] "..message.."；等待逾時")
   task.wait(.05)
  until false
 end
 local function villagers()
  local result={}
  for _,model in ipairs(workspace.Units:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("UnitType")=="villager" and model.PrimaryPart and (model:GetAttribute("HP") or 0)>0 then table.insert(result,model) end
  end
  return result
 end
 local function location(origin)
  Config.Map.MapSize=workspace:GetAttribute("MapSize") or Config.Map.MapSize
  local data=Config.Buildings.House
  local params=OverlapParams.new()
  params.FilterType=Enum.RaycastFilterType.Include
  params.FilterDescendantsInstances={workspace.Buildings,workspace.Units,workspace.Resources}
  for radius=24,96,8 do
   for index=0,31 do
    local angle=index*math.pi/16
    local pos=Grid.snap(origin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
    if Grid.inBounds(pos,data.size) and #workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),
     Vector3.new(data.size.X*Config.Map.GridSize-.2,data.height,data.size.Y*Config.Map.GridSize-.2),params)==0 then return pos end
   end
  end
  error("[AUTO_WORK FAIL] 找不到合法測試工地")
 end
 local function resourceNear(unit,radius)
  local origin=unit.PrimaryPart.Position
  for _,resource in ipairs(workspace.Resources:GetDescendants()) do
   if resource:IsA("Model") and resource:GetAttribute("ResourceType") and (resource:GetAttribute("Amount") or 0)>0
    and (resource:GetPivot().Position-origin).Magnitude<=radius then return true end
  end
  return false
 end
 local function visibleInGui(object)
  local current=object
  while current and not current:IsA("PlayerGui") do
   if current:IsA("GuiObject") and not current.Visible then return false end
   if current:IsA("LayerCollector") and not current.Enabled then return false end
   current=current.Parent
  end
  return current~=nil
 end
 local saved=player:GetAttribute("AutoWork")
 local held
 local ok,result=xpcall(function()
  if workspace:GetAttribute("MatchPhase")=="Lobby" then
   require(RS.Shared.LobbyTests).Start({expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
  end
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true and player.Character==nil end,20,"正式無角色沙盒已開始")
  command:FireServer("AutoWork",true)
  waitFor(function() return player:GetAttribute("AutoWork")==true end,3,"伺服器回寫自動工作開啟")
  waitFor(function() return #villagers()>=2 end,5,"至少兩名正式村民已複製")
  local list=villagers()
  held=list[1]
  command:FireServer("Stop",{held})
  waitFor(function() return held:GetAttribute("Order")=="待命" end,3,"玩家停止的村民進入待命")
  local holdUntil=os.clock()+Config.AutoWork.idleDelay+Config.AutoWork.checkInterval*3
  repeat
   assert(held:GetAttribute("Order")=="待命","[AUTO_WORK FAIL] 玩家停止的村民被自動工作拉走")
   task.wait(.1)
  until os.clock()>=holdUntil
  check(true,"玩家停止的村民保持待命")
  local free=list[2]
  check(resourceNear(free,Config.AutoWork.gatherRadius),"主城旁村民的採集半徑內有資源（地圖資源離基地至少 BaseClearance）")
  waitFor(function() return free:GetAttribute("Order")~="待命" end,Config.AutoWork.idleDelay+Config.AutoWork.retryInterval+2,"未被保留的閒置村民自動開始工作")

  local probe=player.PlayerGui:FindFirstChild("RTSSelectionProbe",true)
  check(probe and probe:IsA("BindableFunction"),"正式選取探針可用")
  check(probe:Invoke({})==true,"清除選取")
  waitFor(function()
   local page=player.PlayerGui:FindFirstChild("BuildPage_economy",true)
   return page and visibleInGui(page)
  end,3,"未選取任何目標時直接顯示建築分類")

  local old={}
  for _,building in ipairs(workspace.Buildings:GetChildren()) do old[building]=true end
  local pos=location(held.PrimaryPart.Position)
  local wood=player:GetAttribute("wood")
  check(type(wood)=="number" and wood>=Config.Buildings.House.cost.wood,"資源足以建立房屋")
  command:FireServer("Build","House",pos,{})
  local site
  waitFor(function()
   for _,building in ipairs(workspace.Buildings:GetChildren()) do
    if not old[building] and building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")=="House" then site=building; return true end
   end
   return false
  end,5,"空選取建造仍由伺服器建立工地")
  check(player:GetAttribute("wood")==wood-Config.Buildings.House.cost.wood,"空選取建造只扣款一次")
  local builder
  waitFor(function()
   for _,unit in ipairs(villagers()) do
    if unit:GetAttribute("OrderKind")=="build" and unit:GetAttribute("OrderTargetBuildingType")=="House" then builder=unit; return true end
   end
   return false
  end,3,"伺服器自動派村民前往工地")
  waitFor(function() return site:GetAttribute("Complete")==true end,60,"自動派遣的村民完成房屋")
  if resourceNear(builder,Config.AutoWork.gatherRadius) then
   waitFor(function() return builder:GetAttribute("Order")~="待命" end,Config.AutoWork.idleDelay+Config.AutoWork.retryInterval+2,"完工村民自動接續附近工作")
  else
   print("[AUTO_WORK NOTE] 完工村民附近沒有資源，略過接續工作檢查")
  end

  command:FireServer("AutoWork",false)
  waitFor(function() return player:GetAttribute("AutoWork")==false end,3,"伺服器回寫自動工作關閉")
  waitFor(function()
   local button=player.PlayerGui:FindFirstChild("AutoWorkButton",true)
   local label=button and button:FindFirstChildWhichIsA("TextLabel",true)
   return label and string.find(label.Text,"關閉",1,true)~=nil
  end,2,"選單標籤顯示自動工作關閉")
  print(string.format("[AUTO_WORK COMPLETE] %d 項檢查；保留待命、空選取建造、自動派工、完工接續、選單開關",checks))
  return checks
 end,debug.traceback)
 if saved~=nil and workspace:GetAttribute("MatchPhase")=="Playing" then command:FireServer("AutoWork",saved) end
 if not ok then error(result,0) end
 return result
end
function Tests.Run()
 assert(not Tests.running,"[AUTO_WORK FAIL] 驗證已在執行")
 Tests.running=true
 local ok,result=xpcall(run,debug.traceback)
 Tests.running=false
 if not ok then error(result,0) end
 return result
end
return Tests
