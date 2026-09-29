-- Explicit, opt-in Studio integration test. Call Run() on the CLIENT during Play.
-- Uses real server RemoteEvents and real pathfinding, never a production debug backdoor.
local RunService=game:GetService("RunService")
local Tests={}
function Tests.Run()
 assert(RunService:IsStudio() and RunService:IsClient(),"Run these tests on a Studio Play client only")
 local player=game.Players.LocalPlayer
 local command=game.ReplicatedStorage:WaitForChild("RTSRemotes"):WaitForChild("Command")
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
 check(not workspace.StreamingEnabled,"RTS scene streaming disabled")
 local ground=workspace:FindFirstChild("AOE2_Ground")
 check(ground and ground:IsA("BasePart") and ground.Transparency==0,"ground exists and is visible on client")
 local camera=workspace.CurrentCamera
 check(camera.CameraType==Enum.CameraType.Scriptable and camera.CFrame.LookVector.Y<0,"camera looks down toward the map")
 local ray=workspace:Raycast(camera.CFrame.Position,camera.CFrame.LookVector*2000)
 check(ray~=nil,"camera center sees world geometry")
 check(player.PlayerGui:FindFirstChild("AOE2_MainGUI")~=nil,"HUD mounted")
 local ui=require(game.StarterGui.GameUI.GUIManager)
 local inset=game:GetService("GuiService"):GetGuiInset()
 -- Command Bar has a separate require cache. Inspect the live PlayerGui, not module state.
 local hud=player.PlayerGui.AOE2_MainGUI.HUD
 local areas={}
 for _,area in ipairs(hud:GetDescendants()) do
  if area:IsA("Frame") and area.Active then table.insert(areas,area) end
 end
 local inspector={hitAreas=areas}
 local dock=hud:WaitForChild("CommandDock",5).AbsolutePosition
 check(ui.BlocksPointer(inspector,dock+inset+Vector2.new(20,20)),"HUD blocks clicks inside command dock")
 check(not ui.BlocksPointer(inspector,dock+inset+Vector2.new(80,-15)),"terrain immediately above HUD remains clickable")
 local base,worker
 for _,model in ipairs(workspace.Buildings:GetChildren()) do if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType")=="Castle" then base=model end end
 for _,model in ipairs(workspace.Units:GetChildren()) do if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("UnitType")=="villager" then worker=model; break end end
 check(base and worker,"owned castle and villagers replicated with geometry")
 local home=player:GetAttribute("HomePosition")
 local direction=Vector3.new(home.X>0 and -1 or 1,0,home.Z>0 and -1 or 1)
 local buildPos=home+Vector3.new(direction.X*48,0,direction.Z*40)
 local wood=player:GetAttribute("wood")
 local count=#workspace.Buildings:GetChildren()
 command:FireServer("Build","House",buildPos)
 untilTrue(function() return #workspace.Buildings:GetChildren()==count+1 end,5,"server creates house")
 check(player:GetAttribute("wood")==wood-25,"server deducts house cost exactly once")
 local paid=player:GetAttribute("wood")
 command:FireServer("Build","House",buildPos)
 task.wait(0.7)
 check(#workspace.Buildings:GetChildren()==count+1 and player:GetAttribute("wood")==paid,"overlapping house rejected without payment")
 command:FireServer("Build","House",Vector3.new(0/0,0,0))
 command:FireServer("Build","House",Vector3.new(9999,0,0))
 command:FireServer("Build","Castle",buildPos)
 task.wait(0.7)
 check(player:GetAttribute("wood")==paid,"invalid coordinate and castle requests rejected")
 local total=#workspace.Units:GetChildren()
 local food=player:GetAttribute("food")
 command:FireServer("Train",base,"villager")
 untilTrue(function() return #workspace.Units:GetChildren()==total+1 end,12,"villager training completes and spawns")
 check(player:GetAttribute("food")==food-50,"training food cost applied")
 local resource,best=nil,math.huge
 for _,model in ipairs(workspace.Resources:GetChildren()) do
  if model:GetAttribute("ResourceType")=="food" then
   local distance=(model:GetPivot().Position-worker:GetPivot().Position).Magnitude
   if distance<best then resource,best=model,distance end
  end
 end
 local amount=resource:GetAttribute("Amount")
 local start=worker:GetPivot().Position
 local startingFood=player:GetAttribute("food")
 command:FireServer("Order",{worker},resource)
 untilTrue(function() return (worker:GetPivot().Position-start).Magnitude>2 end,8,"villager follows real navigation path")
 untilTrue(function() return resource:GetAttribute("Amount")<amount and player:GetAttribute("food")>startingFood end,22,"resource extraction credits player food")
 command:FireServer("Stop",{worker})
 untilTrue(function() return worker:GetAttribute("Order")=="待命" end,3,"stop command clears unit order")
 local position=worker:GetPivot().Position
 task.wait(0.6)
 check((worker:GetPivot().Position-position).Magnitude<0.1,"stopped unit stays still")
 print(string.format("[RTS_TEST COMPLETE] %d engine integration checks passed",checks))
 return checks
end
return Tests
