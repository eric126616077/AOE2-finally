-- Explicit Studio CLIENT integration tests. Run on a fresh Play session; modifies the test match.
local RunService=game:GetService("RunService")
local Tests={}
function Tests.Run()
 assert(RunService:IsStudio() and RunService:IsClient(),"只能在 Studio Play 客戶端呼叫")
 local RS=game:GetService("ReplicatedStorage")
 local player=game.Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local checks=0
 local function check(ok,message)
  assert(ok,"[RTS_TEST FAIL] "..message)
  checks+=1
  print("[RTS_TEST PASS] "..message)
 end
 local function untilTrue(predicate,seconds,message)
  local deadline=os.clock()+seconds
  repeat if predicate() then check(true,message); return end; task.wait(0.15) until os.clock()>deadline
  check(false,message)
 end
 untilTrue(function() return workspace:GetAttribute("RTSReady")==true end,10,"server initializes once")
 check(not workspace.StreamingEnabled,"avatar-free map uses full replication")
 local ground=workspace:FindFirstChild("AOE2_Ground")
 check(ground and ground:IsA("BasePart") and ground.Transparency==0,"visible ground replicated on client")
 untilTrue(function() return player.PlayerGui:FindFirstChild("AOE2_MainGUI")~=nil end,5,"HUD mounted without character")
 if workspace:GetAttribute("MatchPhase")=="Lobby" then
  command:FireServer("StartMatch")
  task.wait(0.4)
  check(workspace:GetAttribute("MatchPhase")=="Lobby","unqueued player cannot start match")
  require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
 end
 untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("HomePosition")~=nil end,15,"host starts custom match")
 Config.Map.MapSize=workspace:GetAttribute("MatchSize")
 check(ground.Size.X==Config.Map.MapSize and ground.Size.Z==Config.Map.MapSize,"selected map size matches client ground")
 check(#workspace.Resources:GetChildren()>=250,"abundant resources replicated")
 local factions=RS:WaitForChild("RTSFactions")
 untilTrue(function() return #factions:GetChildren()>=1 end,8,"AI factions replicated")
 local camera=workspace.CurrentCamera
 check(camera.CameraType==Enum.CameraType.Scriptable and camera.CFrame.LookVector.Y<0,"RTS camera looks down at world")
 check(player.Character==nil,"RTS does not depend on player character")
 local function owned(folder,kind,key)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and (not kind or model:GetAttribute(key)==kind) then table.insert(result,model) end
  end
  return result
 end
 local base=owned(workspace.Buildings,"TownCenter","BuildingType")[1] or owned(workspace.Buildings,"Castle","BuildingType")[1]
 local worker=owned(workspace.Units,"villager","UnitType")[1]
 check(base and base.PrimaryPart and worker and worker.PrimaryPart,"owned base and villagers have actual geometry")
 local gui=require(game.StarterGui.GameUI.GUIManager)
 local hud=player.PlayerGui.AOE2_MainGUI:FindFirstChild("HUD",true)
 check(hud~=nil,"actual PlayerGui HUD exists inside canvas")
 local areas={}
 for _,area in ipairs(hud:GetDescendants()) do if area:IsA("Frame") and area.Active then table.insert(areas,area) end end
 local inspector={hitAreas=areas}
 local inset=game:GetService("GuiService"):GetGuiInset()
 local dock=hud:FindFirstChild("CommandDock",true)
 if dock then
  check(gui.BlocksPointer(inspector,dock.AbsolutePosition+inset+Vector2.new(20,20)),"command dock blocks ground clicks")
  check(not gui.BlocksPointer(inspector,dock.AbsolutePosition+inset+Vector2.new(80,-15)),"ground beside bottom dock remains clickable")
 end
 local params=OverlapParams.new()
 params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={workspace.Buildings,workspace.Resources,workspace.Units}
 local home=player:GetAttribute("HomePosition")
 local function location(kind)
  local data=Config.Buildings[kind]
  for radius=32,72,8 do
   for index=0,15 do
    local angle=index*math.pi/8
    local pos=Grid.snap(home+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
    if Grid.inBounds(pos,data.size) and #workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*8-.2,data.height,data.size.Y*8-.2),params)==0 then return pos end
   end
  end
  error("No clear test building location")
 end
 local buildPos=location("House")
 local wood=player:GetAttribute("wood")
 local count=#owned(workspace.Buildings)
 command:FireServer("Build","House",buildPos,{worker})
 local house
 untilTrue(function()
  for _,model in ipairs(owned(workspace.Buildings,"House","BuildingType")) do if (model:GetPivot().Position-Vector3.new(buildPos.X,model:GetPivot().Position.Y,buildPos.Z)).Magnitude<1 then house=model; return true end end
  return false
 end,5,"server creates construction site")
 check(player:GetAttribute("wood")==wood-Config.Buildings.House.cost.wood,"build cost deducted once by server")
 local paid=player:GetAttribute("wood")
 command:FireServer("Build","House",buildPos,{worker})
 task.wait(0.5)
 check(#owned(workspace.Buildings)==count+1 and player:GetAttribute("wood")==paid,"overlap rejected without payment")
 command:FireServer("Build","House",Vector3.new(0/0,0,0),{worker})
 command:FireServer("Build","House",Vector3.new(9999,0,0),{worker})
 command:FireServer("Build",{},buildPos,{worker})
 command:FireServer("Build","TownCenter",Vector3.new(Config.Map.MapSize/2,0,0),{worker})
 task.wait(0.6)
 check(player:GetAttribute("wood")==paid,"NaN, wrong type and out-of-bounds requests rejected")
 untilTrue(function() return house:GetAttribute("Complete")==true or house:GetAttribute("UnderConstruction")==false end,30,"villager construction completes")
 check(player:GetAttribute("PopulationCap")>=10,"completed house adds population capacity")
 local unitCount=#owned(workspace.Units)
 local food=player:GetAttribute("food")
 command:FireServer("Train",base,"villager")
 untilTrue(function() return #owned(workspace.Units)==unitCount+1 end,Config.Units.villager.trainTime+8,"training queue produces villager")
 check(player:GetAttribute("food")==food-Config.Units.villager.cost.food,"training deducts correct food")
 local resource,best=nil,math.huge
 for _,model in ipairs(workspace.Resources:GetChildren()) do
  if model:GetAttribute("ResourceType")=="food" then
   local distance=(model:GetPivot().Position-worker:GetPivot().Position).Magnitude
   if distance<best then resource,best=model,distance end
  end
 end
 check(resource~=nil,"nearby food source exists")
 local amount=resource:GetAttribute("Amount")
 local start=worker:GetPivot().Position
 local startingFood=player:GetAttribute("food")
 command:FireServer("Order",{worker},resource)
 untilTrue(function() return (worker:GetPivot().Position-start).Magnitude>2 end,10,"worker navigates using engine pathfinding")
 untilTrue(function() return (resource:GetAttribute("Amount") or 0)<amount end,30,"worker extracts finite resources")
 untilTrue(function() return player:GetAttribute("food")>startingFood end,45,"carried food returns to dropoff and credits player")
 command:FireServer("Stop",{worker})
 untilTrue(function() return worker:GetAttribute("Order")=="待命" end,3,"stop clears worker order")
 local position=worker:GetPivot().Position
 task.wait(0.6)
 check((worker:GetPivot().Position-position).Magnitude<0.1,"stopped worker remains stationary")
 local ai=factions:GetChildren()[1]
 untilTrue(function()
  local villagers=0
  for _,unit in ipairs(workspace.Units:GetChildren()) do
   if unit:GetAttribute("OwnerId")==ai:GetAttribute("UserId") and unit:GetAttribute("UnitType")=="villager" then villagers+=1 end
  end
  return villagers>Config.Settings.startingVillagers
 end,20,"AI trains villagers through normal economy")
 check(ai:GetAttribute("Age")~=nil and ai:GetAttribute("wood")~=nil,"AI exposes consistent faction state")
 command:FireServer("Surrender")
 untilTrue(function() return player:GetAttribute("Defeated")==true and workspace:GetAttribute("MatchPhase")=="Ended" end,5,"surrender resolves victory and defeat")
 check(#owned(workspace.Units)==0 and #owned(workspace.Buildings)==0,"defeat cleans up owned instances")
 untilTrue(function() local result=player.PlayerGui.AOE2_MainGUI:FindFirstChild("ResultOverlay",true); return result and result.Visible end,5,"result overlay displays match outcome")
 command:FireServer("RestartMatch")
 untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Lobby" end,5,"host returns to lobby for rematch")
 check(#factions:GetChildren()==0,"rematch removes AI faction state")
 print(string.format("[RTS_TEST COMPLETE] %d engine integration checks passed",checks))
 return checks
end
return Tests
