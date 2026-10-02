-- Explicit CLIENT integration, normal LobbyTests/Command only. Runs three
-- generations, including same-size rematches and a Large -> Small switch.
local Tests={running=false,lastReport=nil}
function Tests.Run()
 local run=game:GetService("RunService")
 local player=game.Players.LocalPlayer
 assert(run:IsStudio() and run:IsClient() and player and #game.Players:GetPlayers()==1,"僅限新 Studio CLIENT 單人工作階段")
 assert(workspace:GetAttribute("MatchPhase")=="Lobby" and not Tests.running,"請先在新大廳建立測試 fixture")
 local RS=game.ReplicatedStorage
 local resources=workspace:WaitForChild("Resources")
 local unknown=resources:FindFirstChild("使用者資源測試")
 local container=resources:FindFirstChild("使用者資料夾測試")
 local nested=container and container:FindFirstChild("巢狀標記模型保留測試")
 local scenery=workspace:FindFirstChild("RTSScenery")
 local unknownScene=scenery and scenery:FindFirstChild("使用者場景測試")
 local templates=RS:FindFirstChild("Buildings")
 local template=templates and templates:FindFirstChild("使用者模型模板測試")
 assert(unknown and nested and unknownScene and template and unknown:GetAttribute("LobbyCleanupFixture")==true,"SERVER fixture 尚未複製")
 local LobbyTests=require(RS.Shared.LobbyTests)
 local Config=require(RS.GameData.GameConfig)
 local command=RS.RTSRemotes.Command
 local checks=0
 local report={complete=false,cycles={}}
 Tests.running=true
 local function check(ok,message)
  assert(ok,"[LOBBY_CLEANUP FAIL] "..message); checks+=1
  print("[LOBBY_CLEANUP PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local deadline=os.clock()+seconds
  repeat if predicate() then return end; task.wait(.1) until os.clock()>=deadline
  error(message,0)
 end
 local function preserved()
  check(unknown.Parent==resources and unknown.PrimaryPart and unknown:GetAttribute("RTSManagedResource")==nil,"保留未知直接資源模型")
  check(container.Parent==resources and nested.Parent==container and nested:GetAttribute("RTSManagedResource")==true,"不遞迴刪除未知資料夾的巢狀模型")
  check(scenery.Parent==workspace and scenery:GetAttribute("RTSManagedScenery")==nil and unknownScene.Parent==scenery,"保留同名未知場景")
  check(template.Parent==templates and template.PrimaryPart,"保留 ReplicatedStorage 原有模型模板")
 end
 local function census()
  local count,parts=0,0
  for _,model in ipairs(resources:GetChildren()) do
   if model:GetAttribute("RTSManagedResource")==true then
    count+=1
    for _,item in ipairs(model:GetDescendants()) do if item:IsA("BasePart") then parts+=1 end end
   end
  end
  return count,parts
 end
 local function managedSceneryCount()
  local count=0
  for _,item in ipairs(workspace:GetChildren()) do if item:IsA("Folder") and item:GetAttribute("RTSManagedScenery")==true then count+=1 end end
  return count
 end
 local function minimapDots()
  local map=player.PlayerGui:FindFirstChild("Minimap",true)
  if not map then return nil end
  local count=0
  for _,item in ipairs(map:GetChildren()) do if item.Name=="MinimapDot" and item:IsA("Frame") then count+=1 end end
  return count
 end
 local ok,failure=xpcall(function()
  preserved()
  local previousGeneration=workspace:GetAttribute("MatchGeneration") or 0
  for cycleIndex,size in ipairs({"Small","Small","Large","Large","Small"}) do
   LobbyTests.Start({expectedPlayers=1,size=size,aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
   local target=Config.Map.ResourceNodeTargets[size]
   waitFor(function()
    return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("MatchSizeName")==size
     and workspace:GetAttribute("ResourceNodeCount")==target and census()==target
     and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>=4
     and workspace:FindFirstChild("Buildings") and #workspace.Buildings:GetChildren()>=1
     and not player.Character and workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable
   end,20,"新局模型／角色／相機未就緒")
   local generation=workspace:GetAttribute("MatchGeneration")
   check(generation>previousGeneration,"正常新局取得新 generation")
   check(workspace:GetAttribute("MapSize")==Config.Map.Sizes[size] and workspace.AOE2_Ground.Size.X==Config.Map.Sizes[size],"地面尺寸正確")
   check(managedSceneryCount()==1 and workspace:GetAttribute("MapReady")==true,"同尺寸或不同尺寸新局皆有一份生成場景")
   preserved()
   local mapCensus=require(RS.Shared.MapTests).Run()
   local mapChecks=mapCensus.checks
   check(mapChecks>0 and mapCensus.nodes==target,"新局資源正常完整計數與道路／占地規則")
   local beforeNodes,beforeParts=census()
   waitFor(function() return (minimapDots() or 0)>=target end,5,"實際 PlayerGui 小地圖節點未更新")
   local beforeDots=minimapDots()
   check(beforeDots>=target,"讀實際 PlayerGui 的生成小地圖節點")
   local old=resources:GetChildren()
   local balance=player:GetAttribute("wood")
   check(balance==1200 and player:GetAttribute("Population")==4,"正常初始資源與人口沒有改寫")
   if cycleIndex==4 then
    local worker
    for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then worker=unit; break end end
    local Grid=require(RS.Shared.Grid)
    local home=player:GetAttribute("HomePosition")
    local location=Grid.snap(home+Vector3.new(64,0,48),Config.Buildings.House.size)
    command:FireServer("Build","House",location,{worker})
    local house
    waitFor(function()
     for _,building in ipairs(workspace.Buildings:GetChildren()) do
      if building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")=="House" and building:GetAttribute("Complete")==true then house=building; return true end
     end
     return false
    end,25,"Large 同尺寸重開後正常房屋未完工")
    check(house and player:GetAttribute("wood")==balance-25,"Large 同尺寸重開後正常建造與扣款")
    local tree,distance=nil,math.huge
    for _,resource in ipairs(resources:GetChildren()) do
     if resource:GetAttribute("RTSManagedResource")==true and resource:GetAttribute("ResourceType")=="wood" and resource.PrimaryPart then
      local d=(resource.PrimaryPart.Position-worker.PrimaryPart.Position).Magnitude
      if d<distance then tree,distance=resource,d end
     end
    end
    assert(tree,"沒有生成樹木可採集")
    task.wait(.3); command:FireServer("Order",{worker},tree)
    waitFor(function() return (worker:GetAttribute("Carrying") or 0)>0 and worker:GetAttribute("CarryType")=="wood" end,30,"Large 同尺寸重開後正常採集未取得木材")
    check(worker:GetAttribute("Order")=="採集","重新生成資源可正常指派並實際採集")
    task.wait(.3); command:FireServer("Stop",{worker})
   end
   command:FireServer("Surrender")
   waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,5,"正常投降未結束")
   check(census()==beforeNodes,"結果畫面仍保留戰場資源以便觀戰")
   task.wait(.3); command:FireServer("RestartMatch")
   waitFor(function()
    return workspace:GetAttribute("MatchPhase")=="Lobby" and census()==0 and workspace:GetAttribute("ResourceNodeCount")==0
     and #workspace.Units:GetChildren()==0 and #workspace.Buildings:GetChildren()==0 and player.Character
     and player.Character:FindFirstChild("HumanoidRootPart") and workspace.CurrentCamera.CameraType==Enum.CameraType.Custom and minimapDots()==0
   end,20,"返回大廳未完成生成資源／玩家物件清理")
   local remainingNodes,remainingParts=census()
   check(remainingNodes==0 and remainingParts==0,"大廳不保留上一局生成資源零件")
   check(minimapDots()==0,"實際 PlayerGui 回大廳清除隱藏小地圖節點")
   local removed=0
   for _,model in ipairs(old) do if model:GetAttribute("RTSManagedResource")==true then assert(model.Parent==nil,"上一局生成資源模型仍存在"); removed+=1 end end
   check(removed==beforeNodes,"上一局所有生成資源模型皆移除")
   for _,key in ipairs({"food","wood","gold","stone","Population"}) do check(player:GetAttribute(key)==0,"大廳清空玩家 "..key) end
   preserved()
   check(managedSceneryCount()==1,"低數量場景保留供同尺寸新局使用")
   previousGeneration=workspace:GetAttribute("MatchGeneration")
   local cycle={size=size,generation=generation,beforeNodes=beforeNodes,beforeParts=beforeParts,afterNodes=remainingNodes,afterParts=remainingParts,mapChecks=mapChecks,beforeDots=beforeDots,afterDots=minimapDots()}
   table.insert(report.cycles,cycle)
   print("[LOBBY_CLEANUP CYCLE] "..game:GetService("HttpService"):JSONEncode(cycle))
  end
  report.complete=true
 end,debug.traceback)
 report.checks=checks; report.failure=not ok and tostring(failure) or nil
 Tests.running=false; Tests.lastReport=report
 print("[LOBBY_CLEANUP "..(ok and "COMPLETE" or "INCOMPLETE").."] "..game:GetService("HttpService"):JSONEncode(report))
 if not ok then error(failure,0) end
 return report
end
return Tests
