-- Explicit Studio CLIENT test, normal commands only. A separate require VM is
-- used to exercise the public preview module; it does not claim LocalScript state.
local Tests={running=false,lastReport=nil}
local function segmentEnters(a,b,center,half)
 local lo,hi=0,1
 for _,axis in ipairs({"X","Z"}) do
  local origin,delta=a[axis]-center[axis],b[axis]-a[axis]
  if math.abs(delta)<1e-6 then
   if math.abs(origin)>=half[axis] then return false end
  else
   local first,last=(-half[axis]-origin)/delta,(half[axis]-origin)/delta
   if first>last then first,last=last,first end
   lo,hi=math.max(lo,first),math.min(hi,last)
   if lo>=hi then return false end
  end
 end
 return hi>0 and lo<1
end
function Tests.Run()
 assert(not Tests.running,"測試已在執行")
 local run=game:GetService("RunService")
 local RS=game.ReplicatedStorage
 local player=game.Players.LocalPlayer
 assert(run:IsStudio() and run:IsClient() and player,"僅限 Studio CLIENT")
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true,"僅限新的單人沙盒")
 local generation=workspace:GetAttribute("MatchGeneration")
 local folder=workspace:FindFirstChild("RTSScenery")
 assert(folder and folder:GetAttribute("SceneryCollisionFixture")==true and folder:GetAttribute("MatchGeneration")==generation,"先從 SERVER 明確建立本局測試牆面")
 local wall=folder:FindFirstChild("測試使用者牆面")
 assert(wall and wall.CanCollide and wall.CanQuery and folder:GetAttribute("RTSManagedScenery")~=true,"需要可碰撞的未知場景資料夾")
 local command=RS.RTSRemotes.Command
 local worker
 for _,unit in ipairs(workspace.Units:GetChildren()) do
  if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("RTSManaged")==true and unit:GetAttribute("UnitType")=="villager" then worker=unit; break end
 end
 assert(worker and worker.PrimaryPart,"初始村民未就緒")
 local root=worker.PrimaryPart
 local Controller=require(RS.Shared.BuildingController)
 local checks,errors,samples,changes,maxDetour=0,0,0,0,0
 local report={generation=generation,checks=0,complete=false}
 Tests.running=true
 local feedback=RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message,cue)
  if cue=="Error" and type(message)=="string" and string.find(message,"此處有障礙物",1,true) then errors+=1 end
 end)
 local function valid()
  return run:IsRunning() and workspace:GetAttribute("MatchGeneration")==generation and workspace:GetAttribute("MatchPhase")=="Playing" and worker.Parent==workspace.Units
 end
 local function check(condition,message)
  assert(condition,"[SCENERY_COLLISION FAIL] "..message); checks+=1
  print("[SCENERY_COLLISION PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=os.clock()+seconds
  repeat assert(valid(),"測試局已改變"); if predicate() then return end; task.wait(.05) until os.clock()>=untilTime
  error(message,0)
 end
 local function countBuildings()
  local count=0
  for _,building in ipairs(workspace.Buildings:GetChildren()) do if building:GetAttribute("OwnerId")==player.UserId then count+=1 end end
  return count
 end
 local ok,failure=xpcall(function()
  command:FireServer("Stop",{worker})
  waitFor(function() return worker:GetAttribute("Order")=="待命" end,4,"村民未停止")
  check(folder:GetAttribute("RTSManagedScenery")==nil,"同名資料夾沒有生成場景標記")
  check(Controller:Begin("House",{worker}),"自己的村民可開啟建築預覽")
  Controller:Update(Vector3.new(wall.Position.X,0,wall.Position.Z))
  check(Controller.valid==false and Controller.reason and string.find(Controller.reason,"障礙物",1,true),"實際預覽模組拒絕未知資料夾牆面")
  Controller:Cancel()
  local beforeCount=countBuildings()
  local balances={}
  for _,key in ipairs({"food","wood","gold","stone"}) do balances[key]=player:GetAttribute(key) end
  task.wait(.3)
  command:FireServer("Build","House",Vector3.new(wall.Position.X,0,wall.Position.Z),{worker})
  waitFor(function() return errors>0 end,5,"正常建築請求未收到障礙拒絕")
  check(countBuildings()==beforeCount,"伺服器沒有在牆面生成工地")
  for key,balance in pairs(balances) do check(player:GetAttribute(key)==balance,"拒絕建築沒有扣 "..key) end
  check(wall.Parent==folder and wall.CanCollide,"保留未知牆面的碰撞與實例")
  local start=Vector3.new(wall.Position.X-32,0,wall.Position.Z)
  local goal=Vector3.new(wall.Position.X+48,0,wall.Position.Z)
  task.wait(.3); command:FireServer("Order",{worker},start)
  waitFor(function() return (Vector3.new(root.Position.X,0,root.Position.Z)-start).Magnitude<1.6 and worker:GetAttribute("Order")=="待命" end,15,"村民未抵達牆面前的正常起點")
  check(segmentEnters(root.Position,goal,wall.Position,wall.Size/2+Vector3.new(root.Size.X/2,0,root.Size.Z/2)),"直線目標確實被測試牆面阻擋")
  local previous=root.Position
  local half=wall.Size/2+Vector3.new(root.Size.X/2-.1,0,root.Size.Z/2-.1)
  local begun=os.clock()
  task.wait(.3); command:FireServer("Order",{worker},goal)
  repeat
   assert(valid(),"移動中測試局已改變")
   task.wait(.05)
   local current=root.Position
   samples+=1
   assert(not segmentEnters(previous,current,wall.Position,half),"[SCENERY_COLLISION FAIL] 權威 Root 移動段穿入牆面")
   if (current-previous).Magnitude>.05 then changes+=1 end
   maxDetour=math.max(maxDetour,math.abs(current.Z-wall.Position.Z))
   previous=current
   if (Vector3.new(current.X,0,current.Z)-goal).Magnitude<1.6 and worker:GetAttribute("Order")=="待命" then break end
   assert(os.clock()-begun<30,"[SCENERY_COLLISION FAIL] 村民繞行逾時")
  until false
  check(changes>=10 and samples>=10,"正常 Order 產生多次權威移動更新")
  check(maxDetour>wall.Size.Z/2,"村民走到牆邊外側繞行")
  check((Vector3.new(root.Position.X,0,root.Position.Z)-goal).Magnitude<1.6,"村民完成被牆面阻擋的正常移動命令")
  check(wall.Parent==folder and folder.Parent==workspace,"繞行完成仍保留未知模型")
  report.complete=true; report.seconds=os.clock()-begun
 end,debug.traceback)
 Controller:Cancel(); feedback:Disconnect(); Tests.running=false
 report.checks=checks; report.samples=samples; report.rootChanges=changes; report.maxDetour=maxDetour; report.failure=not ok and tostring(failure) or nil
 Tests.lastReport=report
 print("[SCENERY_COLLISION "..(ok and "COMPLETE" or "INCOMPLETE").."] "..game:GetService("HttpService"):JSONEncode(report))
 if not ok then error(failure,0) end
 return report
end
return Tests
