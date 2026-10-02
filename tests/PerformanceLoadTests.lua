-- Optional Studio CLIENT ModuleScript, never mapped by default.project.json.
-- Explicit Prepare() uses normal Build/Train/Order/Stop only. Measure() samples
-- actual roots and the existing read-only PerformanceObserver, without a camera
-- RenderStep writer, resource grants, direct spawning or property teleports.
local Tests={running=false,lastReport=nil}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function context()
 local run=game:GetService("RunService")
 assert(run:IsStudio() and run:IsClient() and run:IsRunning(),"僅限 Studio CLIENT 新 Play")
 local RS=game:GetService("ReplicatedStorage")
 local player=game.Players.LocalPlayer
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true
  and workspace:GetAttribute("FactionCount")==1 and workspace:GetAttribute("AICount")==0,"須正常開單人、無 AI 沙盒新局")
 local Config=require(RS.GameData.GameConfig)
 local generation=workspace:GetAttribute("MatchGeneration")
 local mapSize=workspace:GetAttribute("MapSize")
 local deadline=os.clock()
 local c={RS=RS,run=run,player=player,Config=Config,generation=generation,mapSize=mapSize,
  home=player:GetAttribute("HomePosition"),units=workspace:FindFirstChild("Units"),buildings=workspace:FindFirstChild("Buildings"),
  command=RS.RTSRemotes.Command,lastCommand=-math.huge}
 assert(typeof(c.home)=="Vector3" and c.units and c.buildings and finite(mapSize),"對局實例尚未複製")
 function c:valid()
  return run:IsRunning() and player.Parent==game.Players and workspace:GetAttribute("MatchPhase")=="Playing"
   and workspace:GetAttribute("MatchGeneration")==generation and workspace:GetAttribute("MapSize")==mapSize
   and player:GetAttribute("Defeated")~=true and player:GetAttribute("Spectator")~=true
 end
 function c:owned(folder,kind)
  local list={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==player.UserId
    and model.PrimaryPart and model.PrimaryPart:IsDescendantOf(model) and (model:GetAttribute("HP") or 0)>0
    and (not kind or model:GetAttribute("UnitType")==kind or model:GetAttribute("BuildingType")==kind) then table.insert(list,model) end
  end
  return list
 end
 function c:send(action,a,b,d)
  assert(self:valid(),"對局已改變，不對新局發送指令")
  local remaining=.25-(os.clock()-self.lastCommand)
  if remaining>0 then task.wait(remaining) end
  assert(self:valid(),"指令等待期間對局已改變")
  self.lastCommand=os.clock()
  self.command:FireServer(action,a,b,d)
 end
 function c:waitFor(predicate,seconds,message)
  local untilTime=math.min(deadline,os.clock()+seconds)
  repeat
   assert(self:valid(),"測試局已結束或玩家已退出")
   if predicate() then return end
   task.wait(.1)
  until os.clock()>=untilTime
  error(message.."；等待逾時",0)
 end
 function c:setDeadline(seconds) deadline=os.clock()+seconds end
 function c:flat(model)
  local p=model.PrimaryPart.Position
  return Vector3.new(p.X,Config.Map.GroundY,p.Z)
 end
 function c:emit(kind,data)
  local row={probe="ClientLoad",kind=kind,generation=generation,data=data}
  local ok,json=pcall(function() return game:GetService("HttpService"):JSONEncode(row) end)
  if not ok or #json>700 then json=game:GetService("HttpService"):JSONEncode({probe="ClientLoad",kind=kind,missing="record exceeds 700 bytes; full table in lastReport"}) end
  print(json)
 end
 return c
end
local function flat(pos) return Vector3.new(pos.X,0,pos.Z) end
local function routes(c)
 local inward=Vector3.new(c.home.X>0 and -1 or 1,0,c.home.Z>0 and -1 or 1)
 return {flat(c.home)+inward*48,flat(c.home)+inward*76}
end
local function routeClear(c,selection,point)
 local overlap=OverlapParams.new()
 overlap.FilterType=Enum.RaycastFilterType.Exclude
 local excluded={c.units}
 local ground=workspace:FindFirstChild("AOE2_Ground")
 if ground then table.insert(excluded,ground) end
 for _,folder in ipairs(workspace:GetChildren()) do
  if folder:GetAttribute("RTSManagedScenery")==true then table.insert(excluded,folder) end
 end
 overlap.FilterDescendantsInstances=excluded
 local columns=math.ceil(math.sqrt(#selection))
 for index,unit in ipairs(selection) do
  local goal=point+Vector3.new(((index-1)%columns-(columns-1)/2)*4,0,math.floor((index-1)/columns)*4)
  assert(math.abs(goal.X)<c.mapSize/2-8 and math.abs(goal.Z)<c.mapSize/2-8,"編隊目標超出地圖安全範圍")
  local start=c:flat(unit)
  local difference=goal-start
  local root=unit.PrimaryPart
  local width=math.max(root.Size.X,root.Size.Z)+2
  local frame=difference.Magnitude>.01 and CFrame.lookAt((start+goal)/2+Vector3.new(0,3,0),goal+Vector3.new(0,3,0))
   or CFrame.new(start+Vector3.new(0,3,0))
  for _,part in ipairs(workspace:GetPartBoundsInBox(frame,Vector3.new(width,6,difference.Magnitude+width),overlap)) do
   if part.CanCollide then return false,part.Name end
  end
 end
 return true
end
local function stop(c)
 if not c:valid() then return end
 local selection=c:owned(c.units)
 if #selection>0 then c:send("Stop",selection) end
end
local function guard(c,body)
 assert(not Tests.running,"漸增負載 helper 已在執行")
 Tests.running=true
 local ok,result=xpcall(body,debug.traceback)
 if not ok then
  pcall(function() stop(c) end)
  c:emit("INCOMPLETE",{error=string.sub(tostring(result),1,220),actualUnits=#c:owned(c.units),
   cleanup="停止本人單位；正常建築、已生成單位與未完生產保留"})
 end
 Tests.running=false
 if not ok then error(result,0) end
 return result
end
function Tests.Prepare(options)
 options=options or {}
 local target,timeout=options.targetUnits or 10,options.timeoutSeconds or 300
 assert(target==10 or target==20,"本輪只准備 10 或 20 個實際單位")
 assert(finite(timeout) and timeout>=60 and timeout<=600,"準備期限須為60–600秒")
 local c=context()
 c:setDeadline(timeout)
 return guard(c,function()
  local Observer=require(c.RS.Shared.PerformanceObserver)
  assert(not Observer.running,"先完成目前的唯讀觀察")
  local owned=c:owned(c.units)
  assert(#owned>=4 and #owned<=target,"實際單位數不適合本階段；不刪除單位以湊數")
  local center
  for _,building in ipairs(c:owned(c.buildings,"TownCenter")) do
   if building:GetAttribute("Complete")==true then center=building; break end
  end
  assert(center and (center:GetAttribute("QueueCount") or 0)==0 and center:GetAttribute("Research")==nil,"需要空佇列且完工的市鎮中心")
  assert((c.player:GetAttribute("food") or 0)>=(target-#owned)*c.Config.Units.villager.cost.food,"正常食物不足；不增發測試資源")
  stop(c)
  local built,trained=0,0
  local Grid=require(c.RS.Shared.Grid)
  local function buildHouse()
   local workers=c:owned(c.units,"villager")
   assert(#workers>=2 and (c.player:GetAttribute("wood") or 0)>=c.Config.Buildings.House.cost.wood,"房屋缺少正常工人或木材")
   local data=c.Config.Buildings.House
   local box=OverlapParams.new()
   box.FilterType=Enum.RaycastFilterType.Exclude
   local excluded={}
   local ground=workspace:FindFirstChild("AOE2_Ground")
   if ground then table.insert(excluded,ground) end
   for _,folder in ipairs(workspace:GetChildren()) do if folder:GetAttribute("RTSManagedScenery")==true then table.insert(excluded,folder) end end
   box.FilterDescendantsInstances=excluded
   local position
   local inward=Vector3.new(c.home.X>0 and -1 or 1,0,c.home.Z>0 and -1 or 1)
   for radius=64,104,8 do
    if position then break end
    for index=0,31 do
     local candidate=c.home+Vector3.new(math.cos(index*math.pi/16)*radius,0,math.sin(index*math.pi/16)*radius)
     -- Reserve a broad corridor for the entire global X/Z formation, not just its anchor.
     local delta=candidate-c.home
     if not (delta.X*inward.X>28 and delta.X*inward.X<100 and delta.Z*inward.Z>28 and delta.Z*inward.Z<104) then
      local p=Grid.snap(candidate,data.size)
      if math.abs(p.X)+data.size.X*c.Config.Map.GridSize/2<c.mapSize/2 and math.abs(p.Z)+data.size.Y*c.Config.Map.GridSize/2<c.mapSize/2 then
       local clear=true
       for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,data.height/2,0)),
        Vector3.new(data.size.X*c.Config.Map.GridSize-.2,data.height,data.size.Y*c.Config.Map.GridSize-.2),box)) do
        if part.CanCollide or part:IsDescendantOf(c.units) then clear=false; break end
       end
       if clear then position=p; break end
      end
     end
    end
   end
   assert(position,"沒有不阻塞出口與測試走廊的合法房屋位置")
   local before,previous=c.player:GetAttribute("wood"),{}
   for _,building in ipairs(c:owned(c.buildings)) do previous[building]=true end
   c:send("Build","House",position,{workers[1],workers[2]})
   local site
   c:waitFor(function()
    for _,building in ipairs(c:owned(c.buildings,"House")) do if not previous[building] then site=building; return true end end
    return false
   end,8,"伺服器未建立正常房屋")
   c:waitFor(function() return c.player:GetAttribute("wood")==before-data.cost.wood end,5,"房屋未扣正常木材")
   c:waitFor(function() return site.Parent==c.buildings and site:GetAttribute("Complete")==true end,45,"村民未完成房屋")
   built+=1
   c:emit("HOUSE",{paidWood=data.cost.wood,actualUnits=#c:owned(c.units),populationCap=c.player:GetAttribute("PopulationCap"),complete=true})
   stop(c)
  end
  while (c.player:GetAttribute("PopulationCap") or 0)<target do buildHouse() end
  while #c:owned(c.units)<target do
   local beforeUnits={}
   for _,unit in ipairs(c:owned(c.units)) do beforeUnits[unit]=true end
   assert((center:GetAttribute("QueueCount") or 0)==0,"不要覆蓋外來生產佇列")
   local food=c.player:GetAttribute("food")
   local revision=center:GetAttribute("QueueRevision")
   c:send("Train",center,"villager")
   c:waitFor(function()
    return c.player:GetAttribute("food")==food-c.Config.Units.villager.cost.food
     and (center:GetAttribute("QueueCount") or 0)==1 and center:GetAttribute("QueueRevision")~=revision
   end,5,"正常訓練未接受或扣款")
   c:waitFor(function()
    for _,unit in ipairs(c:owned(c.units)) do if not beforeUnits[unit] and unit:GetAttribute("UnitType")=="villager" then return true end end
    return false
   end,c.Config.Units.villager.trainTime+25,"村民實際生成逾時，可能出口阻塞")
   trained+=1
   local selection=c:owned(c.units)
   local points=routes(c)
   local clear,obstacle=routeClear(c,selection,points[1])
   assert(clear,"集結路線被障礙阻擋："..tostring(obstacle))
   c:send("Order",selection,points[1])
   c:waitFor(function()
    local columns=math.ceil(math.sqrt(#selection))
    for index,unit in ipairs(selection) do
     local goal=points[1]+Vector3.new(((index-1)%columns-(columns-1)/2)*4,0,math.floor((index-1)/columns)*4)
     if unit.Parent~=c.units or unit:GetAttribute("Order")~="待命" or (c:flat(unit)-goal).Magnitude>2.1 then return false end
    end
    return true
   end,15,"單位未完成出口外的正常集結")
  end
  stop(c)
  c:waitFor(function() return (center:GetAttribute("QueueCount") or 0)==0 end,5,"末次訓練佇列未清空")
  local report={actualUnits=#c:owned(c.units),targetUnits=target,builtHouses=built,trainedVillagers=trained,
   food=c.player:GetAttribute("food"),wood=c.player:GetAttribute("wood"),populationCap=c.player:GetAttribute("PopulationCap"),
   evidence="正常扣款、村民施工、伺服器生產與集結；未直接生成"}
  Tests.lastReport=report; c:emit("PREPARED",report)
  return report
 end)
end
function Tests.Measure(options)
 options=options or {}
 local mode,seconds=options.mode or "idle",options.seconds or 30
 local expected=options.expectedUnits
 assert(mode=="idle" or mode=="move" or mode=="stop","量測模式須為idle/move/stop")
 assert(finite(seconds) and seconds>=30 and seconds<=120,"量測期限須30–120秒")
 assert(expected==4 or expected==10 or expected==20,"須明確指定4、10或20個實際單位")
 local c=context()
 c:setDeadline(seconds+15)
 return guard(c,function()
  local selection=c:owned(c.units)
  assert(#selection==expected,"實際單位數不符；不以人口或佇列湊數")
  for _,building in ipairs(c:owned(c.buildings)) do assert((building:GetAttribute("QueueCount") or 0)==0,"量測前需完成所有生產") end
  local camera=workspace.CurrentCamera
  assert(camera and camera.CameraType==Enum.CameraType.Scriptable,"相機尚未就緒")
  local cameraFrame,fov,viewport=camera.CFrame,camera.FieldOfView,camera.ViewportSize
  local reduced=c.player:GetAttribute("ReducedMotion")==true
  local points=routes(c)
  if mode=="move" then
   for _,point in ipairs(points) do
    local clear,obstacle=routeClear(c,selection,point)
    assert(clear,"移動量測路線有障礙："..tostring(obstacle))
   end
   local warmupIndex,warmupDistance=1,-math.huge
   local columns=math.ceil(math.sqrt(#selection))
   for pointIndex,point in ipairs(points) do
    local minimum=math.huge
    for index,unit in ipairs(selection) do
     local goal=point+Vector3.new(((index-1)%columns-(columns-1)/2)*4,0,math.floor((index-1)/columns)*4)
     minimum=math.min(minimum,(c:flat(unit)-goal).Magnitude)
    end
    if minimum>warmupDistance then warmupIndex,warmupDistance=pointIndex,minimum end
   end
   assert(warmupDistance>=8,"沒有可讓全體單位移動的暖身端點")
   local initial={}
   for _,unit in ipairs(selection) do initial[unit]=unit.PrimaryPart.Position end
   c:send("Order",selection,points[warmupIndex])
   c:waitFor(function()
    for _,unit in ipairs(selection) do
     if (unit.PrimaryPart.Position-initial[unit]).Magnitude<4 or unit:GetAttribute("Animation")~="Walk" then return false end
    end
    return true
   end,10,"選取單位沒有全部實際移動")
  else
   local previousStop={}
   for _,unit in ipairs(selection) do previousStop[unit]=unit.PrimaryPart.Position end
   local stableSince
   stop(c)
   c:waitFor(function()
    local stable=true
    for _,unit in ipairs(selection) do
     local p=unit.PrimaryPart.Position
     if unit:GetAttribute("Order")~="待命" or (p-previousStop[unit]).Magnitude>.05 then stable=false end
     previousStop[unit]=p
    end
    if not stable then stableSince=nil; return false end
    stableSince=stableSince or os.clock()
    return os.clock()-stableSince>=.3
   end,5,"停止指令未完成")
  end
  local Observer=require(c.RS.Shared.PerformanceObserver)
  local handle=Observer.Start({seconds=seconds,sampleInterval=2,context="單人漸增負載 "..expected.." "..mode,includeSamples=false})
  local seen,previous={},{}
  local samples,visibleMinimum,movingMinimum,movingSamples=0,expected,expected,0
  local nextOrder,pointIndex=os.clock()+2,1
  local endTime=os.clock()+seconds
  local success,result=xpcall(function()
   while os.clock()<endTime do
    assert(c:valid(),"觀察期間對局改變")
    assert(#c:owned(c.units)==expected,"觀察期間實際單位數改變")
    assert(camera==workspace.CurrentCamera and (camera.CFrame.Position-cameraFrame.Position).Magnitude<.5
     and camera.CFrame.LookVector:Dot(cameraFrame.LookVector)>.99999 and camera.FieldOfView==fov and camera.ViewportSize==viewport,"相機或視窗改變，配對樣本無效")
    assert((c.player:GetAttribute("ReducedMotion")==true)==reduced,"ReducedMotion設定改變")
    local visible,moving=0,0
    for _,unit in ipairs(selection) do
     assert(unit.Parent==c.units and unit.PrimaryPart and unit:GetAttribute("OwnerId")==c.player.UserId,"單位退出或所有權改變")
     local p=unit.PrimaryPart.Position
     local screen,onScreen=camera:WorldToViewportPoint(p)
     if onScreen and screen.Z>0 then visible+=1; seen[unit]=true end
     if previous[unit] and (p-previous[unit]).Magnitude>1 and unit:GetAttribute("Animation")=="Walk" then moving+=1 end
     previous[unit]=p
    end
    samples+=1; visibleMinimum=math.min(visibleMinimum,visible)
    if samples>1 then movingMinimum=math.min(movingMinimum,moving); if moving>0 then movingSamples+=1 end end
    if mode=="move" and os.clock()>=nextOrder then
     c:send("Order",selection,points[pointIndex])
     pointIndex=3-pointIndex; nextOrder=os.clock()+2
    end
    task.wait(.5)
   end
   return handle:Finish("stage-complete")
  end,debug.traceback)
  if not success then handle:Finish("stage-incomplete"); error(result,0) end
  local everVisible=0; for _ in pairs(seen) do everVisible+=1 end
  local report={mode=mode,expectedUnits=expected,actualUnits=#c:owned(c.units),frames=result.frames,
   framesByFocus=result.framesByFocus,focusCoverage=result.focusCoverage,metrics=result.metrics,missing=result.missing,
   load={samples=samples,everVisible=everVisible,minimumVisible=visibleMinimum,minimumMoving=samples>1 and movingMinimum or false,
    movingSampleFraction=samples>1 and movingSamples/(samples-1) or false,sampleIntervalSeconds=.5,
    continuousAllMovingProven=false},camera={position={cameraFrame.X,cameraFrame.Y,cameraFrame.Z},fov=fov,viewport={viewport.X,viewport.Y}},
   performanceAccepted=false,serverCPUMeasured=false,baselineImprovementProven=false}
  Tests.lastReport=report
  c:emit("FRAMES",{mode=mode,actualUnits=report.actualUnits,frames=report.frames})
  for _,focus in ipairs({"Focused","Background","Unknown"}) do c:emit("FOCUS_FRAMES",{mode=mode,focus=focus,frames=report.framesByFocus[focus]}) end
  c:emit("FOCUS",report.focusCoverage)
  c:emit("LOAD",{mode=mode,actualUnits=report.actualUnits,load=report.load,camera=report.camera})
  for name,metric in pairs(report.metrics) do c:emit("METRIC",{mode=mode,name=name,value=metric}) end
  c:emit("COMPLETE",{mode=mode,actualUnits=report.actualUnits,seconds=result.elapsedSeconds,
   performanceAccepted=false,serverCPUMeasured=false,baselineImprovementProven=false})
  stop(c)
  return report
 end)
end
return Tests
