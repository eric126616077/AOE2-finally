-- Explicit Studio CLIENT regression. Requires no server hook and does nothing on require.
-- RunFresh(): enter the actual lobby portal normally first. RunAttached(): idle solo sandbox.
-- Every building, age, resource and movement uses the normal Command RemoteEvent.
-- A failed fixture/probe remains intact; never teleport, damage, delete or reset the match.
local Tests={running=false}
local resourceKeys={"food","wood","gold","stone"}

local function run(options,fresh,connections)
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"[DELIVERY_FALLBACK FAIL] 僅限 Studio Play 客戶端")
 options=options or {}
 local seconds=options.deadlineSeconds or 900
 assert(type(seconds)=="number" and seconds==seconds and seconds>=300 and seconds<=1800,"[DELIVERY_FALLBACK FAIL] 總期限須為 300–1800 秒")
 local started,deadline=os.clock(),os.clock()+seconds
 local Players,RS=game:GetService("Players"),game:GetService("ReplicatedStorage")
 local player=Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local remotes=assert(RS:WaitForChild("RTSRemotes",10),"缺少正式遠端")
 local command=assert(remotes:WaitForChild("Command",10),"缺少正常 Command")
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local checks,lastSend,lastProgress=0,0,started
 local folders,center,worker,generation
 local walls,sealedCamp={},nil
 local function check(ok,label)
  assert(ok,"[DELIVERY_FALLBACK FAIL] "..label)
  checks+=1; print("[DELIVERY_FALLBACK PASS] "..label)
 end
 local function equal(a,b) return type(a)=="number" and type(b)=="number" and math.abs(a-b)<0.0001 end
 local function flat(model) local p=model:GetPivot().Position; return Vector3.new(p.X,Config.Map.GroundY,p.Z) end
 local function owned(folder,kind,attribute)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==player.UserId
    and (not kind or model:GetAttribute(attribute)==kind) then table.insert(result,model) end
  end
  return result
 end
 local function workers() return owned(folders.units,"villager","UnitType") end
 local function balances()
  local result={}; for _,key in ipairs(resourceKeys) do result[key]=player:GetAttribute(key) end; return result
 end
 local function same(a,b)
  for _,key in ipairs(resourceKeys) do if not equal(a[key],b[key]) then return false end end; return true
 end
 local function diagnostic()
  return string.format("時代 %s；村民 %s；攜帶 %s %s；位置 %s；交貨 %s；已用 %.1f 秒",tostring(player:GetAttribute("Age")),
   worker and tostring(worker:GetAttribute("Order")) or "未指定",worker and tostring(worker:GetAttribute("Carrying")) or "—",
   worker and tostring(worker:GetAttribute("CarryType")) or "—",worker and tostring(flat(worker)) or "—",
   tostring(player:GetAttribute("DeliveredResources")),os.clock()-started)
 end
 local function waitFor(predicate,limit,label)
  local untilTime=math.min(deadline,os.clock()+limit)
  repeat
   if predicate() then return end
   if generation then assert(workspace:GetAttribute("MatchGeneration")==generation and workspace:GetAttribute("MatchPhase")=="Playing"
    and player:GetAttribute("Defeated")==false,"[DELIVERY_FALLBACK FAIL] 對局在驗收期間改變") end
   if os.clock()-lastProgress>=25 then print("[DELIVERY_FALLBACK WAIT] "..label.."；"..diagnostic()); lastProgress=os.clock() end
   task.wait(0.05)
  until os.clock()>=untilTime
  error("[DELIVERY_FALLBACK FAIL] "..label.."逾時；"..diagnostic(),0)
 end
 local function send(action,...)
  local remaining=0.25-(os.clock()-lastSend); if remaining>0 then task.wait(remaining) end
  assert(os.clock()<deadline,"[DELIVERY_FALLBACK FAIL] 總期限已到")
  command:FireServer(action,...); lastSend=os.clock()
 end
 local function accepts(model,key)
  local data=Config.Buildings[model:GetAttribute("BuildingType")]
  return model:GetAttribute("Complete")==true and data and type(data.dropoff)=="table" and table.find(data.dropoff,key)~=nil
 end
 local function edgeDistance(model,p)
  local c,h=flat(model),model.PrimaryPart.Size/2
  local dx,dz=math.max(0,math.abs(p.X-c.X)-h.X),math.max(0,math.abs(p.Z-c.Z)-h.Z)
  return math.sqrt(dx*dx+dz*dz)
 end
 local function dropoff(key,p,exclude)
  local best,distance
  for _,model in ipairs(owned(folders.buildings)) do
   if model~=exclude and model.PrimaryPart and accepts(model,key) and model:GetAttribute("HP")==model:GetAttribute("MaxHP") then
    local d=edgeDistance(model,p); if not distance or d<distance then best,distance=model,d end
   end
  end
  return best,distance
 end
 local function stopAll()
  local selection=owned(folders.units)
  send("Stop",selection)
  waitFor(function() for _,unit in ipairs(selection) do if unit.Parent and unit:GetAttribute("Order")~="待命" then return false end end; return true end,10,"全部己方單位正常停止")
  local before,at=balances(),os.clock()
  waitFor(function() local current=balances(); if not same(before,current) then before,at=current,os.clock() end; return os.clock()-at>=0.6 end,10,"餘額複製穩定")
 end
 local function stopOnEmpty(unit)
  local fired=false
  local connection=unit:GetAttributeChangedSignal("Carrying"):Connect(function()
   if not fired and unit:GetAttribute("Carrying")==0 then
    fired=true; command:FireServer("Stop",{unit}); lastSend=os.clock()
   end
  end)
  table.insert(connections,connection)
  return connection,function() return fired end
 end
 local function drain(unit)
  if (unit:GetAttribute("Carrying") or 0)<=0 then return end
  local target=assert(dropoff(unit:GetAttribute("CarryType"),flat(unit)),"[DELIVERY_FALLBACK FAIL] 舊攜帶資源沒有完好合適倉庫")
  local connection,fired=stopOnEmpty(unit)
  send("Order",{unit},target)
  waitFor(function() return fired() and unit:GetAttribute("Carrying")==0 and unit:GetAttribute("Order")=="待命" end,90,"按正常指令交回舊資源並停止")
  connection:Disconnect()
 end
 local function resource(kind,p,minimum)
  local best,distance
  for _,model in ipairs(folders.resources:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("RTSManagedResource")==true
    and model:GetAttribute("ResourceType")==kind and (model:GetAttribute("Amount") or 0)>=(minimum or 1) then
    local d=(flat(model)-p).Magnitude; if not distance or d<distance then best,distance=model,d end
   end
  end
  return best
 end
 local function afford(cost)
  for _,key in ipairs(resourceKeys) do
   local needed=cost[key] or 0
   if (player:GetAttribute(key) or 0)<needed then
    drain(worker)
    local target=assert(resource(key,flat(worker),20),"[DELIVERY_FALLBACK FAIL] 缺少正常籌資資源 "..key)
    send("Order",{worker},target)
    waitFor(function() return (player:GetAttribute(key) or 0)>=needed end,360,"正常採集補足 fixture "..key)
    send("Stop",{worker}); waitFor(function() return worker:GetAttribute("Order")=="待命" end,10,"停止籌資")
    drain(worker)
   end
  end
 end
 local query=OverlapParams.new(); query.FilterType=Enum.RaycastFilterType.Exclude
 local function excluded(ignoreUnits)
  local items={}
  for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local item=workspace:FindFirstChild(name); if item then table.insert(items,item) end end
  if ignoreUnits then table.insert(items,folders.units) end
  query.FilterDescendantsInstances=items
 end
 local function clearBox(p,size,ignoreUnits)
  excluded(ignoreUnits)
  for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,size.Y/2,0)),size,query)) do
   if part.CanCollide or part:IsDescendantOf(folders.buildings) or part:IsDescendantOf(folders.resources) or part:IsDescendantOf(folders.units) then return false end
  end
  return true
 end
 local function inBounds(p,half)
  local bound=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
  return math.abs(p.X)+half<=bound-4 and math.abs(p.Z)+half<=bound-4
 end
 local function move(unit,p,label)
  local radius=unit:GetAttribute("Radius") or 2
  check(inBounds(p,radius*0.9) and clearBox(p,Vector3.new(radius*1.8,4,radius*1.8),true),label.."目的地有正常身體空間")
  send("Order",{unit},p)
  waitFor(function() return unit:GetAttribute("Order")=="待命" and (flat(unit)-p).Magnitude<=1.1 end,90,label.."正常走到指定外側位置")
 end
 local function paid(before,cost)
  local expected=table.clone(before); for key,amount in pairs(cost) do expected[key]-=amount end; return same(expected,balances())
 end
 local function build(kind,p)
  local data=Config.Buildings[kind]; afford(data.cost)
  local before,existing=balances(),{}
  for _,model in ipairs(owned(folders.buildings)) do existing[model]=true end
  send("Build",kind,p,{worker})
  local site
  waitFor(function() for _,model in ipairs(owned(folders.buildings,kind,"BuildingType")) do
   if not existing[model] and model.PrimaryPart and (flat(model)-p).Magnitude<0.1 then site=model; return true end
  end; return false end,10,kind.."建立真實工地")
  waitFor(function() return paid(before,data.cost) end,10,kind.."正常成本扣款")
  check(site:GetAttribute("Complete")==false and site:GetAttribute("UnderConstruction")==true,kind.."不是立即生成的免費完工模型")
  print("[DELIVERY_FALLBACK_GEOMETRY]",kind,site:GetPivot().Position)
  waitFor(function() return site.Parent==folders.buildings and site:GetAttribute("Complete")==true and site:GetAttribute("UnderConstruction")==false end,data.buildTime+100,kind.."真實行走施工完工")
  send("Stop",{worker}); waitFor(function() return worker:GetAttribute("Order")=="待命" end,10,"完工後正常停止")
  check(site:GetAttribute("HP")==site:GetAttribute("MaxHP"),kind.."正常滿生命值完工")
  return site
 end
 local function ordinaryPlacement(kind)
  local data=Config.Buildings[kind]
  for radius=56,160,8 do for index=0,31 do
   local angle=index*math.pi/16
   local p=Grid.snap(flat(center)+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
   local size=Vector3.new(data.size.X*8-0.2,math.max(4,data.height),data.size.Y*8-0.2)
   if inBounds(p,math.max(data.size.X,data.size.Y)*4) and clearBox(p,size,false) then return p end
  end end
  error("[DELIVERY_FALLBACK FAIL] 沒有前置建築合法空地",0)
 end
 if fresh then
  check(#Players:GetPlayers()==1 and workspace:GetAttribute("MatchPhase")=="Lobby","新單人 Studio 大廳")
  local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  assert(root and (root.Position-(Config.Lobby.origin+Config.Lobby.portalOffset)).Magnitude<=Config.Lobby.portalUseRange,"[DELIVERY_FALLBACK FAIL] 先用實際 UI 正常走入傳送門；測試不移動角色")
  if player:GetAttribute("LobbyQueued")~=true then send("QueueJoin"); waitFor(function() return player:GetAttribute("LobbyQueued")==true end,10,"正常集合") end
  check(workspace:GetAttribute("HostUserId")==player.UserId,"集合真人具有正式房主權限")
  local revision=workspace:GetAttribute("LobbySettingsRevision")
  send("LobbySettings",{expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"})
  waitFor(function() return workspace:GetAttribute("LobbySettingsRevision")~=revision end,10,"正式設定確認")
  send("LobbyReady",true,workspace:GetAttribute("LobbySettingsRevision"))
  waitFor(function() return player:GetAttribute("LobbyReady")==true end,10,"正常準備")
  send("StartMatch")
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true
   and workspace:GetAttribute("AICount")==0 and workspace:GetAttribute("StartingResources")=="Rich"
   and workspace:GetAttribute("MatchSizeName")=="Small" and player:GetAttribute("Spectator")==false
   and player:GetAttribute("Defeated")==false and player.Character==nil end,20,"正常開局事實與無角色完整複製")
 end
 check(#Players:GetPlayers()==1 and workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true
  and workspace:GetAttribute("AICount")==0 and workspace:GetAttribute("StartingResources")=="Rich" and workspace:GetAttribute("MatchSizeName")=="Small","只附加到正常單人 Rich／Small／AI0 沙盒")
 check(workspace.StreamingEnabled==false and player.Character==nil,"使用完整複製的無角色 RTS")
 generation=workspace:GetAttribute("MatchGeneration")
 folders={units=assert(workspace:WaitForChild("Units",10)),buildings=assert(workspace:WaitForChild("Buildings",10)),resources=assert(workspace:WaitForChild("Resources",10))}
 waitFor(function() center=owned(folders.buildings,"TownCenter","BuildingType")[1]; worker=workers()[1]; return center and center.PrimaryPart and center:GetAttribute("Complete")==true and worker and worker.PrimaryPart end,15,"真實村民與主城複製")
 for _,model in ipairs(owned(folders.buildings)) do
  if accepts(model,"wood") then check(model:GetAttribute("HP")==model:GetAttribute("MaxHP"),"所有既有木材倉庫均完好；自動最近倉庫與手動正控制候選一致") end
 end
 if options.requireAdvancedFixture then
  check(player:GetAttribute("Age")==4,"附加 fixture 已達四時代")
  for _,kind in ipairs(Config.BuildOrder) do local found=false; for _,model in ipairs(owned(folders.buildings,kind,"BuildingType")) do if model:GetAttribute("Complete")==true then found=true end end; check(found,"附加 fixture 有真正完工 "..kind) end
  for _,key in ipairs(Config.TechnologyOrder) do check(player:GetAttribute("Tech_"..key)==true,"附加 fixture 有正式研究 "..key) end
 end
 stopAll()
 for _,unit in ipairs(workers()) do drain(unit) end
 if (player:GetAttribute("Age") or 1)<2 then
  build("Mill",ordinaryPlacement("Mill"))
  build("LumberCamp",ordinaryPlacement("LumberCamp"))
  afford(Config.Ages[2].cost)
  local before=balances(); send("AdvanceAge",center)
  waitFor(function() return center:GetAttribute("Research")==Config.Ages[2].name and paid(before,Config.Ages[2].cost) end,10,"正常封建前置與扣款")
  waitFor(function() return player:GetAttribute("Age")==2 and player:GetAttribute("AgeRemaining")==0 and center:GetAttribute("Research")==nil end,Config.Ages[2].time+20,"按正式時間升封建")
 end
 check((player:GetAttribute("Age") or 0)>=2,"牆壁只在合法時代建造")
 for _,building in ipairs(owned(folders.buildings)) do
  check((building:GetAttribute("QueueCount") or 0)==0 and building:GetAttribute("Research")==nil and building:GetAttribute("Complete")==true,"沒有其他訓練／研究／施工污染採樣")
 end
 afford({wood=Config.Buildings.LumberCamp.cost.wood,stone=Config.Buildings.Wall.cost.stone*12})
 drain(worker); stopAll()
 local capacity=worker:GetAttribute("CarryCapacity") or (Config.Units.villager.carryCapacity+(player:GetAttribute("Tech_Wheelbarrow")==true and Config.Technologies.Wheelbarrow.effect.carry or 0))
 check(type(capacity)=="number" and capacity>=10,"使用正式攜帶容量，不修改科技")
 local trees={}
 for _,model in ipairs(folders.resources:GetChildren()) do
  if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("RTSManagedResource")==true and model:GetAttribute("ResourceType")=="wood" and (model:GetAttribute("Amount") or 0)>=capacity*4 then table.insert(trees,model) end
 end
 table.sort(trees,function(a,b) return (flat(a)-flat(worker)).Magnitude<(flat(b)-flat(worker)).Magnitude end)
 local tree,campPosition,park,far,attempts=nil,nil,nil,nil,0
 for treeIndex=1,math.min(#trees,64) do
  local candidateTree=trees[treeIndex]
  local farCandidate,farDistance=dropoff("wood",flat(candidateTree))
  if farCandidate then
   for radius=40,80,8 do for index=0,15 do
    attempts+=1
    if attempts>2048 then break end
    local angle=index*math.pi/8
    local p=Grid.snap(flat(candidateTree)+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),Config.Buildings.LumberCamp.size)
    local toTree=flat(candidateTree)-p
    local nearDistance=math.sqrt(math.max(0,math.abs(toTree.X)-8)^2+math.max(0,math.abs(toTree.Z)-8)^2)
    if inBounds(p,30) and farDistance>nearDistance+20 and clearBox(p,Vector3.new(56,16,56),true) then
     local possiblePark=p+Vector3.new(0,0,-24)
     if clearBox(possiblePark,Vector3.new(8,5,8),true) then tree,campPosition,park,far=candidateTree,p,possiblePark,farCandidate; break end
    end
   end; if tree or attempts>2048 then break end end
  end
  if tree or attempts>2048 then break end
 end
 check(tree~=nil,"有限搜尋找到可建完整石牆環且距離較近的合法營地 fixture")
 print("[DELIVERY_FALLBACK_PLAN]","Tree",flat(tree),"Camp",campPosition,"Far",flat(far),"Candidates",attempts)
 for _,unit in ipairs(owned(folders.units)) do move(unit,park,"先移出完整營地／牆壁範圍") end
 sealedCamp=build("LumberCamp",campPosition)
 local campHP=sealedCamp:GetAttribute("HP")
 local function deliveryPosition(p,exclude)
  local target,distance=dropoff("wood",p,exclude)
  return target and distance<=8 and target or nil
 end
 -- A real, full load is explicitly sent to the farther compatible building before sealing.
 -- This positive control proves that the test selected an actual reachable drop-off.
 local positiveAmount,positiveBalances,positiveDelivered=tree:GetAttribute("Amount"),balances(),player:GetAttribute("DeliveredResources") or 0
 send("Order",{worker},tree)
 waitFor(function() return worker:GetAttribute("CarryType")=="wood" and equal(worker:GetAttribute("Carrying"),capacity) end,90,"正控制正常採滿一個木材 cargo")
 send("Stop",{worker}); waitFor(function() return worker:GetAttribute("Order")=="待命" and equal(worker:GetAttribute("Carrying"),capacity) end,10,"以普通 Stop 保留完整 cargo")
 local positiveConnection,positiveStopped=stopOnEmpty(worker)
 send("Order",{worker},far)
 waitFor(function() return positiveStopped() and worker:GetAttribute("Order")=="待命" and worker:GetAttribute("Carrying")==0
  and equal(player:GetAttribute("DeliveredResources"),positiveDelivered+capacity) end,90,"正常指定遠倉庫真實交貨正控制")
 positiveConnection:Disconnect()
 local positiveExpected=table.clone(positiveBalances); positiveExpected.wood+=capacity
 check(same(positiveExpected,balances()) and equal(positiveAmount-tree:GetAttribute("Amount"),capacity),"正控制真節點／庫存／攜帶量守恆")
 check(deliveryPosition(flat(worker),sealedCamp)~=nil,"正控制在完好且合適的遠倉庫工作範圍附近完成")
 local ring={}
 for _,z in ipairs({-12,12}) do for _,x in ipairs({-12,-4,4,12}) do table.insert(ring,{offset=Vector3.new(x,0,z),outward=Vector3.new(0,0,z<0 and -1 or 1)}) end end
 for _,x in ipairs({-12,12}) do for _,z in ipairs({-4,4}) do table.insert(ring,{offset=Vector3.new(x,0,z),outward=Vector3.new(x<0 and -1 or 1,0,0)}) end end
 for index,item in ipairs(ring) do
  local outside=campPosition+item.offset+item.outward*12
  move(worker,outside,"第 "..index.." 段封牆前移出最後工地")
  check(math.max(math.abs(flat(worker).X-campPosition.X),math.abs(flat(worker).Z-campPosition.Z))>=22,"施工者在石牆環外，不被最後封口困住")
  local wall=build("Wall",campPosition+item.offset)
  table.insert(walls,{model=wall,position=campPosition+item.offset,hp=wall:GetAttribute("HP")})
 end
 move(worker,park,"封環後安全移到外側")
 local function assertSeal()
  check(sealedCamp.Parent==folders.buildings and equal(sealedCamp:GetAttribute("HP"),campHP) and sealedCamp:GetAttribute("Complete")==true
   and sealedCamp.PrimaryPart.CanCollide and sealedCamp.PrimaryPart.Size==Vector3.new(16,12,16),"被封營地仍是原來完好正式模型")
  local include=OverlapParams.new(); include.FilterType=Enum.RaycastFilterType.Include; include.RespectCanCollide=true
  local models={}
  for _,entry in ipairs(walls) do
   local wall=entry.model
   check(wall.Parent==folders.buildings and wall:GetAttribute("Complete")==true and equal(wall:GetAttribute("HP"),entry.hp)
    and wall.PrimaryPart.CanCollide and wall.PrimaryPart.Size==Vector3.new(8,13,8) and (flat(wall)-entry.position).Magnitude<0.01,
    "正式石牆維持連續封環與原始 HP："..tostring(entry.position))
   table.insert(models,wall)
  end
  include.FilterDescendantsInstances=models
  local radius=worker:GetAttribute("Radius") or 2
  local outer=8+radius*0.9+0.5
  for index=0,15 do
   local angle=index*math.pi/8; local dx,dz=math.cos(angle),math.sin(angle)
   local distance=math.min(math.abs(dx)>1e-9 and outer/math.abs(dx) or math.huge,math.abs(dz)>1e-9 and outer/math.abs(dz) or math.huge)
   local p=campPosition+Vector3.new(dx*distance,0,dz*distance)
   check(#workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,2.5,0)),Vector3.new(radius*1.8,4,radius*1.8),include)>0,
    "實際牆 collider 擋住第 "..(index+1).." 個正式工作面候選")
  end
  check(16+radius*0.9-8>5,"連續 32×32 實際占地使環外身體距營地邊緣超過交貨距離 5")
 end
 assertSeal(); stopAll()
 local nearby=dropoff("wood",flat(tree))
 check(nearby==sealedCamp,"採集點最近的真實合適倉庫就是已封營地；沒有用測試指令指定遠倉庫")
 check(tree.Parent==folders.resources and (tree:GetAttribute("Amount") or 0)>=capacity*2 and worker:GetAttribute("Carrying")==0,"兩個 cargo 有真實剩餘木材，起始空手")
 local probeAmount,probeBalances,probeDelivered=tree:GetAttribute("Amount"),balances(),player:GetAttribute("DeliveredResources") or 0
 for cycle=1,2 do
  local before,delivered,nodeAmount=balances(),player:GetAttribute("DeliveredResources") or 0,tree:GetAttribute("Amount")
  local peak,lastLocation,lastDelivery=0,nil,worker:GetAttribute("LastDelivery")
  local watch=worker:GetAttributeChangedSignal("Carrying"):Connect(function()
   if worker:GetAttribute("CarryType")=="wood" then peak=math.max(peak,worker:GetAttribute("Carrying") or 0) end
   if worker:GetAttribute("Carrying")==0 and peak>=capacity then lastLocation=flat(worker) end
  end)
  table.insert(connections,watch)
  local emptyConnection,stopped=stopOnEmpty(worker)
  send("Order",{worker},tree)
  waitFor(function()
   if peak>=capacity and worker:GetAttribute("Order")=="待命" and equal(worker:GetAttribute("Carrying"),capacity)
    and equal(player:GetAttribute("DeliveredResources"),delivered) then
    error("[DELIVERY_FALLBACK FAIL] 近倉庫全部工作面被封後停止，未改送已證實可達的遠倉庫；完整 cargo 保留；"..diagnostic(),0)
   end
   return stopped() and worker:GetAttribute("Order")=="待命" and worker:GetAttribute("Carrying")==0
    and equal(player:GetAttribute("DeliveredResources"),delivered+capacity)
  end,150,"第 "..cycle.." 個 cargo 自動改送合適遠倉庫")
  watch:Disconnect(); emptyConnection:Disconnect()
  local expected=table.clone(before); expected.wood+=capacity
  check(equal(peak,capacity) and same(expected,balances()) and equal(nodeAmount-tree:GetAttribute("Amount"),capacity),"第 "..cycle.." 個真 cargo 的節點／四資源餘額／空手守恆")
  check(worker:GetAttribute("LastDelivery")~=lastDelivery and lastLocation and deliveryPosition(lastLocation,sealedCamp)~=nil,
   "第 "..cycle.." 次有正式 LastDelivery 且實際位置在未封合適遠倉庫附近")
  assertSeal()
 end
 local expected=table.clone(probeBalances); expected.wood+=capacity*2
 check(same(expected,balances()) and equal(player:GetAttribute("DeliveredResources"),probeDelivered+capacity*2)
  and equal(probeAmount-tree:GetAttribute("Amount"),capacity*2) and worker:GetAttribute("Carrying")==0,"兩個自動改送 cargo 合計完全守恆，沒有 fixture 扣款混入交貨")
 print(string.format("[DELIVERY_FALLBACK COMPLETE] %d 真實引擎檢查；正常封環、遠倉庫正控制、兩個守恆 cargo；%.1f 秒",checks,os.clock()-started))
 return {checks=checks,elapsedSeconds=os.clock()-started,scope="SealedNearestWoodDropoff",cargoCount=2,capacity=capacity,tree=tree,sealedCamp=sealedCamp,walls=walls}
end

local function invoke(options,fresh)
 assert(not Tests.running,"[DELIVERY_FALLBACK FAIL] 此驗收已在執行")
 Tests.running=true
 local connections={}
 local ok,result=xpcall(function() return run(options,fresh,connections) end,debug.traceback)
 for _,connection in ipairs(connections) do connection:Disconnect() end
 Tests.running=false
 if not ok then warn("[DELIVERY_FALLBACK FAIL] 保留原對局、牆壁與攜帶資源供診斷；沒有清理或重開"); error(result,0) end
 return result
end
function Tests.RunFresh(options) return invoke(options,true) end
function Tests.RunAttached(options) return invoke(options,false) end
Tests.Run=Tests.RunFresh
return Tests
