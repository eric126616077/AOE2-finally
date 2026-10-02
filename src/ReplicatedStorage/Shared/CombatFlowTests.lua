-- Explicit Studio CLIENT integration tests. require() performs no actions.
-- Two human FFA clients, no AI, no other tests/manual orders during the run.
-- Walk both lobby avatars into the real portal. On the host call RunHost();
-- on the other client call RunPeer(). Each call should run inside task.spawn.
-- Default fresh Large/Rich development plus battle can take 40-70 minutes.
-- {prepareOnly=true,victory="Conquest"|"Regicide"|"Wonder"} returns actual army/
-- actor/parking references after normal development without combat or surrender.
-- Both clients must supply the same victory option in a fresh lobby.
-- {existing=true} accepts an already Playing two-human FFA fixture and develops
-- missing prerequisites normally. A solo Advanced sandbox is not a battle fixture.
-- No HP/resource/age/unit writes, teleports, Destroy(), or administrative remotes.
-- Failure preserves the actual match. Coverage is printed only after real evidence.
local Tests={running=false}
local kinds={"villager","infantry","spearman","archer","scout","skirmisher","cavalry","ram","mangonel","trebuchet"}
local keys={"food","wood","gold","stone"}
local sessions={}

local function run(role,options)
 local RS=game:GetService("ReplicatedStorage")
 local Players=game:GetService("Players")
 local RunService=game:GetService("RunService")
 local Http=game:GetService("HttpService")
 assert(RunService:IsStudio() and RunService:IsClient(),"[COMBAT_FLOW FAIL] 僅限 Studio Play 客戶端明確呼叫")
 options=options or {}
 local duration=options.deadlineSeconds or 5400
 assert(type(duration)=="number" and duration==duration and duration>=1200 and duration<=7200,"期限須為 1200–7200 秒")
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local remotes=assert(RS:WaitForChild("RTSRemotes",10),"缺少正式遠端")
 local command=assert(remotes:WaitForChild("Command",10),"缺少正式 Command")
 local player=Players.LocalPlayer
 local started,deadline=os.clock(),os.clock()+duration
 local checks,lastSend,lastManage,lastProgress=0,0,0,started
 local connections,busy,assignments={},{},{}
 local coverage={house={},counters={},defense={},splash=false,unitDeath=false,buildingDeath=false,reports=false}
 local uiChecks=0
 local ledger={friendly=0,enemy=0}
 local desired={food=1100,wood=500,gold=400,stone=300}
 local folders,home,parking,other,center
 local paused,playing=true,false
 local fresh=options.existing~=true
 local victory=options.victory or "Conquest"
 assert(Config.MatchModes[victory],"未知正常勝利模式")
 local function check(ok,message)
  assert(ok,"[COMBAT_FLOW FAIL] "..message)
  checks+=1; print("[COMBAT_FLOW PASS] "..message)
 end
 local function same(a,b) return type(a)=="number" and type(b)=="number" and math.abs(a-b)<0.0001 end
 local function flat(model)
  local p=model:GetPivot().Position; return Vector3.new(p.X,Config.Map.GroundY,p.Z)
 end
 local function send(action,...)
  local delay=0.3-(os.clock()-lastSend)
  if delay>0 then task.wait(delay) end
  assert(os.clock()<deadline,"[COMBAT_FLOW FAIL] 總期限已到")
  command:FireServer(action,...); lastSend=os.clock()
 end
 local function owned(folder,id,kind,attribute)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id
    and (not kind or model:GetAttribute(attribute)==kind) then table.insert(result,model) end
  end
  table.sort(result,function(a,b) return tostring(a:GetAttribute("ReportSubjectId") or a.Name)<tostring(b:GetAttribute("ReportSubjectId") or b.Name) end)
  return result
 end
 local function workers() return folders and owned(folders.units,player.UserId,"villager","UnitType") or {} end
 local function balances()
  local result={}; for _,key in ipairs(keys) do result[key]=player:GetAttribute(key) or 0 end; return result
 end
 local function balancesEqual(a,b)
  for _,key in ipairs(keys) do if not same(a[key],b[key]) then return false end end; return true
 end
 local function resource(kind,position)
  local best,distance
  for _,model in ipairs(folders.resources:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("RTSManagedResource")==true
    and model:GetAttribute("ResourceType")==kind and (model:GetAttribute("Amount") or 0)>0 then
    local d=(flat(model)-position).Magnitude; if not distance or d<distance then best,distance=model,d end
   end
  end
  if kind=="food" then
   for _,model in ipairs(owned(folders.buildings,player.UserId,"Farm","BuildingType")) do
    if model:GetAttribute("Complete")==true and (model:GetAttribute("Amount") or 0)>0 then
     local d=(flat(model)-position).Magnitude; if not distance or d<distance then best,distance=model,d end
    end
   end
  end
  return best
 end
 local function manage()
  if paused or not folders or os.clock()-lastManage<4 then return end
  lastManage=os.clock()
  local missing,groups={},{ }
  for _,key in ipairs(keys) do if (player:GetAttribute(key) or 0)<desired[key] then table.insert(missing,key) end end
  local available={}; for _,worker in ipairs(workers()) do if worker.PrimaryPart and not busy[worker] then table.insert(available,worker) end end
  for index,worker in ipairs(available) do
   local key=assignments[worker]
   if #missing==0 then
    if worker:GetAttribute("Order")~="待命" then groups.stop=groups.stop or {}; table.insert(groups.stop,worker) end
    assignments[worker]=nil
   else
    if not key or not table.find(missing,key) then key=missing[(index-1)%#missing+1] end
    if assignments[worker]~=key or worker:GetAttribute("Order")=="待命" then
     groups[key]=groups[key] or {}; table.insert(groups[key],worker); assignments[worker]=key
    end
   end
  end
  for key,selection in pairs(groups) do
   if key=="stop" then send("Stop",selection)
   else
    local target=resource(key,flat(selection[1]))
    assert(target,"[COMBAT_FLOW FAIL] 無剩餘 "..key.." 節點；不補資源或偽造農田")
    send("Order",selection,target)
   end
  end
 end
 local function waitFor(predicate,seconds,label,allowEnd)
  local limit=math.min(deadline,os.clock()+seconds)
  repeat
   if predicate() then return end
   if playing and not allowEnd then
    assert(workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("Defeated")==false,"[COMBAT_FLOW FAIL] 測試途中對局或己方勢力結束")
    manage()
   end
   if os.clock()-lastProgress>=30 then
    print(string.format("[COMBAT_FLOW PROGRESS] %s；%s；時代 %s；已用 %.1f 秒",role,label,tostring(player:GetAttribute("Age")),os.clock()-started)); lastProgress=os.clock()
   end
   task.wait(0.05)
  until os.clock()>=limit
  error("[COMBAT_FLOW FAIL] "..label.."等待逾時；保留真實對局",0)
 end
 local function resume() paused=false; lastManage=0; table.clear(assignments) end
 local function pause()
  paused=true
  local selection=workers(); if #selection>0 then send("Stop",selection) end
  waitFor(function() for _,worker in ipairs(selection) do if worker.Parent and worker:GetAttribute("Order")~="待命" then return false end end; return true end,8,"停止經濟指令")
  local before,stableAt=balances(),os.clock()
  waitFor(function()
   local now=balances(); if not balancesEqual(before,now) then before,stableAt=now,os.clock() end
   return os.clock()-stableAt>=0.6
  end,8,"隔離扣款前的真實餘額穩定")
 end
 local function afford(cost,label)
  for key,amount in pairs(cost) do desired[key]=math.max(desired[key],amount+100) end
  resume()
  waitFor(function() for key,amount in pairs(cost) do if (player:GetAttribute(key) or 0)<amount then return false end end; return true end,600,"真實採集交貨補足 "..label)
  pause()
 end
 local function paid(before,cost)
  local expected=table.clone(before); for key,amount in pairs(cost) do expected[key]-=amount end
  return balancesEqual(expected,balances())
 end
 local function placement(kind,anchor)
  local data,g=Config.Buildings[kind],Config.Map.GridSize
  anchor=anchor or home
  local half=(workspace:GetAttribute("MatchSize") or Config.Map.MapSize)/2
  local params=OverlapParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
  local excluded={}; for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local object=workspace:FindFirstChild(name); if object then table.insert(excluded,object) end end
  params.FilterDescendantsInstances=excluded
  local first=anchor==home and 64 or 0
  for radius=first,first+128,8 do
   for index=0,31 do
    local angle=math.pi/4+index*math.pi/16
    local p=Grid.snap(anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
    if math.abs(p.X)+data.size.X*g/2<=half-3 and math.abs(p.Z)+data.size.Y*g/2<=half-3 then
     local clear=true
     for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*g-0.2,math.max(4,data.height),data.size.Y*g-0.2),params)) do
      if part.CanCollide or part:IsDescendantOf(folders.buildings) or part:IsDescendantOf(folders.resources) or part:IsDescendantOf(folders.units) then clear=false; break end
     end
     if clear then return p end
    end
   end
  end
  error("[COMBAT_FLOW FAIL] 無合法施工位置："..kind.."；不挪走未知模型",0)
 end
 local function building(kind)
  for _,model in ipairs(owned(folders.buildings,player.UserId,kind,"BuildingType")) do if model:GetAttribute("Complete")==true then return model end end
 end
 local function build(kind,anchor,always)
  if not always and building(kind) then return building(kind) end
  local data=Config.Buildings[kind]
  afford(data.cost,data.name)
  local before,existing=balances(),{}; for _,model in ipairs(owned(folders.buildings,player.UserId)) do existing[model]=true end
  local selection={}; for _,worker in ipairs(workers()) do if not busy[worker] then table.insert(selection,worker) end end
  assert(#selection>=2,"至少需要兩名未保留為戰場靶的真實村民施工")
  selection={selection[1],selection[2]}; for _,worker in ipairs(selection) do busy[worker]=true end
  local began=os.clock()
  send("Build",kind,placement(kind,anchor),selection)
  local site
  waitFor(function() for _,model in ipairs(owned(folders.buildings,player.UserId,kind,"BuildingType")) do if not existing[model] and model.PrimaryPart then site=model; return true end end; return false end,8,data.name.."正常工地建立")
  waitFor(function() return paid(before,data.cost) end,8,data.name.."正常成本複製")
  check(site:GetAttribute("Complete")==false and site:GetAttribute("UnderConstruction")==true,data.name.."真實扣款，先建立工地")
  local observed=false
  local function sample()
   local progress=site:GetAttribute("ConstructionProgress") or 0
   if progress>0 and progress<1 and (site:GetAttribute("BuilderCount") or 0)>0 then observed=true end
  end
  local connection=site:GetAttributeChangedSignal("ConstructionProgress"):Connect(sample); table.insert(connections,connection)
  resume()
  waitFor(function() sample(); return site.Parent==folders.buildings and site:GetAttribute("Complete")==true end,data.buildTime+240,data.name.."正常走路與施工計時")
  connection:Disconnect()
  send("Stop",selection)
  for _,worker in ipairs(selection) do busy[worker]=nil; assignments[worker]=nil end
  check(observed and os.clock()-began>=data.buildTime/(1+Config.Construction.extraWorkerRate)-0.5,data.name.."由村民按真實施工進度完工")
  return site
 end
 local function train(kind)
  local data=Config.Units[kind]
  local producer=assert(building(data.trainsAt[1]),"缺少正式訓練建築："..kind)
  afford(data.cost,data.name)
  local before,existing=balances(),{}; for _,model in ipairs(owned(folders.units,player.UserId,kind,"UnitType")) do existing[model]=true end
  assert((producer:GetAttribute("QueueCount") or 0)==0 and producer:GetAttribute("Research")==nil,"需空的正式生產佇列")
  local began=os.clock(); send("Train",producer,kind)
  waitFor(function() return paid(before,data.cost) and producer:GetAttribute("QueueCount")==1 end,8,data.name.."扣款並入列")
  local duration=data.trainTime
  if player:GetAttribute("Tech_Conscription")==true then duration*=1-Config.Technologies.Conscription.effect.trainSpeed end
  local unit; resume()
  waitFor(function() for _,model in ipairs(owned(folders.units,player.UserId,kind,"UnitType")) do if not existing[model] and model.PrimaryPart then unit=model; return true end end; return false end,duration+45,data.name.."真實生產")
  check(os.clock()-began>=duration-1 and unit:GetAttribute("HP")>0,data.name.."完成正常成本與訓練計時")
  return unit
 end
 local function research(key)
  if player:GetAttribute("Tech_"..key)==true then return end
  local data=Config.Technologies[key]
  local producer=assert(building(data.building),"缺少研究建築："..key)
  afford(data.cost,data.name)
  local before,began=balances(),os.clock(); send("Research",producer,key)
  waitFor(function() return paid(before,data.cost) and producer:GetAttribute("Research")==data.name end,8,data.name.."正常研究與成本")
  check(player:GetAttribute("Tech_"..key)~=true,data.name.."在等待期間沒有提前生效")
  resume(); waitFor(function() return player:GetAttribute("Tech_"..key)==true and producer:GetAttribute("Research")==nil end,data.time+15,data.name.."真實研究計時")
  check(os.clock()-began>=data.time-1,data.name.."完成原始研究時間")
 end
 local function advance(age)
  if player:GetAttribute("Age")>=age then return end
  local data=Config.Ages[age]; afford(data.cost,data.name)
  local before,began=balances(),os.clock(); send("AdvanceAge",center)
  waitFor(function() return paid(before,data.cost) and center:GetAttribute("Research")==data.name end,8,data.name.."真實成本與開始")
  check(player:GetAttribute("Age")==age-1,data.name.."不能提前改時代")
  resume(); waitFor(function() return player:GetAttribute("Age")==age and center:GetAttribute("Research")==nil end,data.time+15,data.name.."原始時代研究時間")
  check(os.clock()-began>=data.time-1,data.name.."正常完成時代研究")
 end
 local function move(selection,point,label)
  -- The normal group command assigns per-index formation goals, not one shared point.
  local goals={}; local columns=math.ceil(math.sqrt(#selection))
  for index,unit in ipairs(selection) do
   goals[unit]=point+Vector3.new(((index-1)%columns-(columns-1)/2)*4,0,math.floor((index-1)/columns)*4)
   local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
   assert(math.abs(goals[unit].X)<=half and math.abs(goals[unit].Z)<=half,"正常隊形超出地圖")
  end
  send("Order",selection,point)
  local slow=math.huge; local far=0
  for _,unit in ipairs(selection) do slow=math.min(slow,unit:GetAttribute("Speed") or 8); far=math.max(far,(flat(unit)-point).Magnitude) end
  waitFor(function()
   for _,unit in ipairs(selection) do if unit.Parent~=folders.units or (flat(unit)-goals[unit]).Magnitude>4 or unit:GetAttribute("Order")~="待命" then return false end end
   return true
  end,far/math.max(1,slow)+100,label.."沿正常路徑移動到位")
 end
 local function deployment(anchor)
  local params=OverlapParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
  local excluded={}; for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local object=workspace:FindFirstChild(name); if object then table.insert(excluded,object) end end
  params.FilterDescendantsInstances=excluded
  for radius=0,20,4 do
   for index=0,15 do
    local angle=index*math.pi/8; local point=anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
    local clear=true
    for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(point+Vector3.new(0,3,0)),Vector3.new(12,5,12),params)) do
     if part.CanCollide or part:IsDescendantOf(folders.buildings) or part:IsDescendantOf(folders.resources) then clear=false; break end
    end
    if clear then return point end
   end
  end
  error("[COMBAT_FLOW FAIL] 戰場部署點被真實障礙阻擋；不移走資源或模型",0)
 end
 local function watchHP(model)
  if not model:IsA("Model") or model:GetAttribute("RTSManaged")~=true then return end
  local id=model:GetAttribute("OwnerId")
  if id~=player.UserId and (not other or id~=other.UserId) then return end
  local previous=model:GetAttribute("HP")
  local connection=model:GetAttributeChangedSignal("HP"):Connect(function()
   local hp=model:GetAttribute("HP")
   if type(previous)=="number" and type(hp)=="number" and hp<previous then
    local category=id==player.UserId and "friendly" or "enemy"
    ledger[category]+=previous-hp
   end
   previous=hp
  end)
  table.insert(connections,connection)
 end
 local readyRevision,lastReadyCommand=nil,0
 local function maintainReady()
  if workspace:GetAttribute("MatchPhase")~="Lobby" or player:GetAttribute("LobbyQueued")~=true then return end
  local revision=workspace:GetAttribute("LobbySettingsRevision")
  if type(revision)=="number" and (readyRevision~=revision or os.clock()-lastReadyCommand>=1) then
   send("LobbyReady",true,revision)
   readyRevision,lastReadyCommand=revision,os.clock()
  end
 end
 local function joinQueue(count,label)
  local previous=workspace:GetAttribute("LobbySettingsRevision")
  local wasQueued=player:GetAttribute("LobbyQueued")==true
  send("QueueJoin")
  waitFor(function()
   return player:GetAttribute("LobbyQueued")==true and (wasQueued or workspace:GetAttribute("LobbySettingsRevision")~=previous
    or (workspace:GetAttribute("LobbyPlayers") or 0)>=count)
  end,12,label)
 end
 local function start()
  if fresh then
   check(workspace:GetAttribute("MatchPhase")=="Lobby" and #Players:GetPlayers()==2,"兩名真實玩家從新大廳開始")
   if role=="host" then
    joinQueue(1,"房主實際走入傳送門集合，等待集合資訊提交")
    waitFor(function() return workspace:GetAttribute("HostUserId")==player.UserId end,8,"正式房主資訊完成複製")
    local revision=workspace:GetAttribute("LobbySettingsRevision")
    send("LobbySettings",{expectedPlayers=2,size="Large",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory=victory,teamMode="FFA"})
    waitFor(function() return workspace:GetAttribute("LobbySettingsRevision")~=revision and workspace:GetAttribute("LobbyExpectedPlayers")==2 end,8,"正常大廳配置")
    waitFor(function() return workspace:GetAttribute("LobbyPlayers")==2 end,180,"第二端正常 QueueJoin")
    maintainReady()
    waitFor(function() maintainReady(); return player:GetAttribute("LobbyReady")==true end,20,"房主正式準備 ACK")
    local lastStart=0
    waitFor(function()
     local phase=workspace:GetAttribute("MatchPhase")
     if phase=="Starting" or phase=="Playing" then return true end
     maintainReady()
     for _,actor in ipairs(Players:GetPlayers()) do if actor:GetAttribute("LobbyReady")~=true then return false end end
     if os.clock()-lastStart>=1 then send("StartMatch"); lastStart=os.clock() end
     return false
    end,180,"雙方真正準備與正常開始；過期版本只重送最新合法準備")
   else
    waitFor(function() return workspace:GetAttribute("LobbyExpectedPlayers")==2 and workspace:GetAttribute("LobbySetting_teamMode")=="FFA"
     and workspace:GetAttribute("LobbySetting_size")=="Large" and workspace:GetAttribute("LobbySetting_victory")==victory end,180,"房主正常配置兩人 FFA")
    joinQueue(2,"第二端走入傳送門並等待集合資訊提交")
    maintainReady()
    waitFor(function()
     if workspace:GetAttribute("MatchPhase")=="Starting" or workspace:GetAttribute("MatchPhase")=="Playing" then return true end
     maintainReady(); return player:GetAttribute("LobbyReady")==true
    end,20,"第二端正式準備 ACK")
    waitFor(function()
     local phase=workspace:GetAttribute("MatchPhase")
     if phase=="Starting" or phase=="Playing" then return true end
     maintainReady(); return false
    end,180,"維持最新合法準備直至房主正常開局")
   end
  end
  for _,actor in ipairs(Players:GetPlayers()) do if actor~=player then other=actor end end
  waitFor(function()
   if workspace:GetAttribute("MatchPhase")~="Playing" or #Players:GetPlayers()~=2 or not other or other.Parent~=Players
    or workspace:GetAttribute("AICount")~=0 or workspace:GetAttribute("FactionCount")~=2 or workspace:GetAttribute("TeamMode")~="FFA" then return false end
   local first,second=player:GetAttribute("TeamId"),other:GetAttribute("TeamId")
   local function validTeam(id) return type(id)=="number" and id==id and id>0 and id<math.huge and id%1==0 end
   if not validTeam(first) or not validTeam(second) or first==second then return false end
   for _,actor in ipairs({player,other}) do
    if typeof(actor:GetAttribute("HomePosition"))~="Vector3" or actor:GetAttribute("Defeated")~=false
     or actor:GetAttribute("Forfeited")~=false or actor:GetAttribute("Spectator")~=false then return false end
    if fresh and actor:GetAttribute("MatchReportJSON")~=nil then return false end
   end
   return true
  end,25,"兩方正式開局的地圖／隊伍／參戰狀態完成複製")
  check(#Players:GetPlayers()==2 and workspace:GetAttribute("AICount")==0 and workspace:GetAttribute("FactionCount")==2 and workspace:GetAttribute("TeamMode")=="FFA","精確戰鬥矩陣使用兩真人 FFA，不混入 AI／第三方")
  for _,actor in ipairs(Players:GetPlayers()) do if actor~=player then other=actor end end
  check(other and player:GetAttribute("TeamId")~=other:GetAttribute("TeamId") and not player:GetAttribute("Spectator") and not other:GetAttribute("Spectator"),"雙方為真正敵對參戰者")
  check((workspace:GetAttribute("MatchSize") or 0)>=Config.Map.Sizes.Large,"精確矩陣需要大型地圖來隔離其他目標與行軍走廊")
  folders={units=workspace:WaitForChild("Units",8),buildings=workspace:WaitForChild("Buildings",8),resources=workspace:WaitForChild("Resources",8)}
  home=player:GetAttribute("HomePosition"); playing=true
  waitFor(function() center=building("TownCenter"); return center and #workers()>=3 end,12,"正式基地與村民複製")
  for _,folder in ipairs({folders.units,folders.buildings}) do
   for _,model in ipairs(folder:GetChildren()) do watchHP(model) end
   table.insert(connections,folder.ChildAdded:Connect(watchHP))
  end
  if not fresh then print("[COMBAT_FLOW LIMIT] 接續既有真人雙方 fixture；先前生產／戰損不可由本次觀察重建，覆盤僅驗本次事實下界。") end
 end
 local function develop()
  build("House",nil,true); build("House",nil,true)
  build("Mill"); build("LumberCamp"); build("MiningCamp"); build("Barracks")
  research("Loom")
  while #workers()<10 do train("villager") end
  for _=1,4 do build("Farm",nil,true) end
  advance(2)
  build("ArcheryRange"); build("Stable"); build("Blacksmith")
  research("Wheelbarrow"); research("Forging"); research("Armor")
  advance(3); build("Castle"); build("SiegeWorkshop"); advance(4)
  local army={}
  for _,kind in ipairs(kinds) do army[kind]=train(kind) end
  pause()
  -- HomePosition is the solid TownCenter footprint, not a legal movement goal.
  parking=placement("House",home)
  check(player:GetAttribute("Age")==4 and (player:GetAttribute("TrainedUnits") or 0)>0,"四時代與十種真實訓練完成，不改寫時代或單位")
  return army
 end
 local function actorArmy(id,kind)
  local values=owned(folders.units,id,kind,"UnitType")
  assert(#values>0,"缺少實際單位："..kind); return values
 end
 local function foreignNear(kind,attribute,point,radius)
  local folder=attribute=="BuildingType" and folders.buildings or folders.units
  local best,distance
  for _,model in ipairs(owned(folder,other.UserId,kind,attribute)) do
   if model.PrimaryPart and (attribute~="BuildingType" or model:GetAttribute("Complete")==true) then
    local d=(flat(model)-point).Magnitude
    if d<=radius and (not distance or d<distance) then best,distance=model,d end
   end
  end
  return best
 end
 local function report(actor)
  local raw=actor:GetAttribute("MatchReportJSON")
  if type(raw)~="string" then return nil end
  local ok,value=pcall(Http.JSONDecode,Http,raw)
  return ok and type(value)=="table" and value.finished==true and value or nil
 end
 local function expected(attacker,target)
  local data=Config.Units[attacker:GetAttribute("UnitType")]
  local victim=Config.Units[target:GetAttribute("UnitType")]
  local class=target.Parent==folders.buildings and "building" or assert(victim,"未知敵方單位類別").class
  return math.max(1,assert(attacker:GetAttribute("Attack"),"缺少伺服器 Attack")+((data.bonus or {})[class] or 0)-(target:GetAttribute("Armor") or 0))
 end
 local function firstHit(attacker,target,label,retreat)
  check(attacker.Parent==folders.units and attacker:GetAttribute("OwnerId")==player.UserId and target:GetAttribute("OwnerId")==other.UserId,"只以真正己方單位攻擊敵方："..label)
  local before=target:GetAttribute("HP"); local hit=expected(attacker,target)
  assert(type(before)=="number" and before>hit,"第一擊靶的實際 HP 不足，不能隔離傷害")
  local after,observedPosition,attackClock
  local previousAttack=attacker:GetAttribute("LastAttack")
  local connection=target:GetAttributeChangedSignal("HP"):Connect(function()
   local hp=target:GetAttribute("HP")
   if not after and type(hp)=="number" and hp<before then after=hp; observedPosition=flat(attacker); attackClock=attacker:GetAttribute("LastAttack") end
  end)
  table.insert(connections,connection)
  send("Order",{attacker},target)
  waitFor(function() return after~=nil end,(flat(attacker)-flat(target)).Magnitude/math.max(1,attacker:GetAttribute("Speed") or 8)+100,label.."真實第一擊 HP 變化")
  if retreat~=false then send("Order",{attacker},parking) end
  connection:Disconnect()
  check(same(before-after,hit),label.."實際 HP 差 = Attack＋剋制－Armor（"..tostring(hit).."）")
  waitFor(function() local value=attacker:GetAttribute("LastAttack"); return type(value)=="number" and value~=previousAttack end,3,label.."實際 LastAttack")
  check(observedPosition~=nil and (type(attackClock)=="number" or type(attacker:GetAttribute("LastAttack"))=="number"),label.."具有伺服器攻擊事實與實際位置")
  if retreat~=false then move({attacker},parking,label.."退回己方基地") end
  return hit,observedPosition
 end
 local counterPlan={
  {key="長槍對騎兵",attacker="spearman",victim="cavalry",point=Vector3.new(0,0,320)},
  {key="矛兵對弓兵",attacker="skirmisher",victim="archer",point=Vector3.new(192,0,192)},
  {key="騎士對弓兵",attacker="cavalry",victim="archer",point=Vector3.new(192,0,-192)},
  {key="斥候對村民",attacker="scout",victim="villager",point=Vector3.new(-192,0,-192)},
  {key="弓兵對步兵",attacker="archer",victim="infantry",point=Vector3.new(-192,0,192)},
 }
 local splashPoint=Vector3.new(320,0,0)
 local deathPoint=Vector3.new(0,0,-160)
 local towerPoint=Vector3.new(-320,0,0)
 local castlePoint=Vector3.new(0,0,-320)
 local function makeFixture()
  local house=build("House",Vector3.zero,true)
  pause(); move(workers(),parking,"工人撤離戰場")
  local housePosition=flat(house)
  -- Leave military targets at their distant base until all ten house strikes were
  -- actually observed; pre-deployment could intercept the attacking march corridor.
  waitFor(function()
   local seen={}
   for _,unit in ipairs(owned(folders.units,other.UserId)) do
    local position=unit:GetAttribute("AttackPosition")
    if type(unit:GetAttribute("LastAttack"))=="number" and typeof(position)=="Vector3"
     and (Vector3.new(position.X,0,position.Z)-housePosition).Magnitude<2 then seen[unit:GetAttribute("UnitType")]=true end
   end
   for _,kind in ipairs(kinds) do if not seen[kind] then return false end end
   return true
  end,1800,"十種軍隊皆已真正對房屋攻擊，才部署克制靶")
  local targets={}; local used={}
  for _,item in ipairs(counterPlan) do
   local unit
   for _,candidate in ipairs(actorArmy(player.UserId,item.victim)) do if not used[candidate] then unit=candidate; break end end
   if not unit then unit=train(item.victim); pause() end
   used[unit]=true; busy[unit]=true; move({unit},deployment(item.point),item.key.."靶正常部署"); table.insert(targets,unit)
  end
  local splash={}; local splashAnchor=deployment(splashPoint)
  for index=1,3 do
   local unit
   for _,candidate in ipairs(workers()) do if not used[candidate] then unit=candidate; break end end
   assert(unit,"缺少真實投石範圍靶村民"); used[unit]=true; busy[unit]=true; table.insert(splash,unit)
   move({unit},splashAnchor+Vector3.new((index-2)*3,0,0),"投石範圍靶 "..index)
  end
  local death
  for _,candidate in ipairs(workers()) do if not used[candidate] then death=candidate; break end end
  assert(death,"缺少真實死亡靶村民"); busy[death]=true; move({death},deployment(deathPoint),"村民死亡靶")
  -- One normal retreat after actual HP falls avoids later target pursuit. The
  -- intentionally lethal village target is excluded and retains normal retaliation.
  local counterHit={}
  for _,unit in ipairs(targets) do
   local before=unit:GetAttribute("HP"); local triggered=false
   table.insert(connections,unit:GetAttributeChangedSignal("HP"):Connect(function()
    if not triggered and (unit:GetAttribute("HP") or before)<before then
     triggered=true; counterHit[unit]=true; task.spawn(function() if unit.Parent==folders.units then send("Order",{unit},parking) end end)
    end
   end))
  end
  local splashStarted=false
  for _,unit in ipairs(splash) do
   local before=unit:GetAttribute("HP")
   table.insert(connections,unit:GetAttributeChangedSignal("HP"):Connect(function()
    if not splashStarted and (unit:GetAttribute("HP") or before)<before then
     splashStarted=true; task.spawn(function() send("Order",splash,parking) end)
    end
   end))
  end
  waitFor(function()
   for _,unit in ipairs(targets) do if not counterHit[unit] then return false end end
   return splashStarted
  end,1800,"五種剋制與投石範圍已真正發生，才施工防禦靶")
  -- Tower/Castle construction is delayed until the march corridors have served
  -- every unit/counter/splash sample. Their automatic fire cannot contaminate it.
  local tower=build("Tower",towerPoint,true)
  local castle=build("Castle",castlePoint,true)
  pause()
  local builders={}; for _,worker in ipairs(workers()) do if not busy[worker] then table.insert(builders,worker) end end
  move(builders,parking,"防禦靶施工工人撤離戰場")
  print("[COMBAT_FLOW PEER FIXTURE] House",flat(house),"Tower",flat(tower),"Castle",flat(castle),"真實靶已部署；沒有寫入標記或戰損")
  return house,tower,castle,death
 end
 local function validateReport(value,outcome,enemyDamage)
  check(value.version==1 and value.outcome==outcome and type(value.matchId)=="string","正式 finished 覆盤結果："..outcome)
  check(type(value.damageDealt)=="number" and value.damageDealt>=enemyDamage-0.001,"正式傷害至少包含所有已複製到客戶端的實際 HP 減少")
  print("[COMBAT_FLOW LIMIT] HP=0 與 Destroy 可在同一複製批次；覆盤傷害採實際可觀測下界，不假稱取得所有最後一擊 HP 樣本。")
 end
 local function battle(army)
  local house,tower,castle,death
  waitFor(function()
   house=foreignNear("House","BuildingType",Vector3.zero,130)
   if not house or other:GetAttribute("Age")~=4 then return false end
   for _,unit in ipairs(owned(folders.units,other.UserId)) do if (flat(unit)-flat(house)).Magnitude<=100 then return false end end
   return true
  end,1800,"第二端正常發展、房屋完工與施工人員撤離")
  -- Refuse contaminants near the house rather than pretending its HP delta came
  -- from the selected unit. Each test army waits at home outside acquisition range.
  for _,unit in ipairs(owned(folders.units,other.UserId)) do check((flat(unit)-flat(house)).Magnitude>100,"普通房屋周圍沒有其他敵方單位干擾") end
  move(owned(folders.units,player.UserId),parking,"己方全軍正式集中等待")
  for _,kind in ipairs(kinds) do
   firstHit(army[kind],house,Config.Units[kind].name.."對普通房屋")
   coverage.house[kind]=true
  end
  waitFor(function()
   death=foreignNear("villager","UnitType",deathPoint,25)
   if not death then return false end
   for _,item in ipairs(counterPlan) do if not foreignNear(item.victim,"UnitType",item.point,25) then return false end end
   local count=0
   for _,unit in ipairs(owned(folders.units,other.UserId,"villager","UnitType")) do if (flat(unit)-splashPoint).Magnitude<26 then count+=1 end end
   return count==3
  end,600,"第二端以真實移動部署克制、投石與死亡靶")
  for _,item in ipairs(counterPlan) do
   local target=assert(foreignNear(item.victim,"UnitType",item.point,25),"剋制靶未在正式位置："..item.key)
   local raw=army[item.attacker]:GetAttribute("Attack")
   local expectedHit=expected(army[item.attacker],target)
   check(expectedHit>math.max(1,raw-(target:GetAttribute("Armor") or 0)),item.key.."傷害 oracle 含設定剋制加成")
   firstHit(army[item.attacker],target,item.key); coverage.counters[item.key]=true
  end
  local splash={}
  for _,unit in ipairs(owned(folders.units,other.UserId,"villager","UnitType")) do if (flat(unit)-splashPoint).Magnitude<26 then table.insert(splash,unit) end end
  check(#splash==3,"三個真實村民靶在投石範圍內，沒有額外旁觀者")
  local main=splash[1]; local before={}; for _,unit in ipairs(splash) do before[unit]=unit:GetAttribute("HP") end
  firstHit(army.mangonel,main,"投石車主要靶")
  for _,unit in ipairs(splash) do
   if unit~=main then
    local expectedSplash=math.max(1,army.mangonel:GetAttribute("Attack")*0.5-(unit:GetAttribute("Armor") or 0))
    check(same(before[unit]-(unit:GetAttribute("HP") or before[unit]),expectedSplash),"投石車次要村民真實 HP 差 = 一半攻擊－護甲")
   end
  end
  coverage.splash=true
  waitFor(function()
   tower=foreignNear("Tower","BuildingType",towerPoint,130); castle=foreignNear("Castle","BuildingType",castlePoint,130)
   return tower and castle
  end,900,"剋制與投石後，第二端正常經濟及施工完成兩種防禦靶")
  for _,defense in ipairs({tower,castle}) do
   local kind=defense:GetAttribute("BuildingType"); local data=Config.Buildings[kind]
   local modifier=(other:GetAttribute("Tech_Forging")==true and Config.Technologies.Forging.effect.attack or 0)+(other:GetAttribute("Tech_Chemistry")==true and Config.Technologies.Chemistry.effect.attack or 0)
   local expectedDamage=math.max(1,data.damage+modifier-(army.ram:GetAttribute("Armor") or 0))
   local before=army.ram:GetAttribute("HP"); local first,clock
   local connection=army.ram:GetAttributeChangedSignal("HP"):Connect(function()
    local hp=army.ram:GetAttribute("HP"); if not first and type(hp)=="number" and hp<before then first=hp; clock=defense:GetAttribute("LastAttack") end
   end); table.insert(connections,connection)
   send("Order",{army.ram},defense)
   waitFor(function() return first~=nil end,(flat(army.ram)-flat(defense)).Magnitude/9+100,kind.."真正自動射擊")
   send("Order",{army.ram},parking); connection:Disconnect()
   check(same(before-first,expectedDamage) and type(clock)=="number",kind.."自動攻擊的實際 HP 差／LastAttack 符合設定")
   move({army.ram},parking,kind.."首擊後正常撤退")
   coverage.defense[kind]=true
  end
  local victimBefore=death:GetAttribute("HP")
  check(death.Parent==folders.units and victimBefore>0 and other:GetAttribute("Defeated")==false,"死亡前對手村民真的存在且勢力仍存活")
  send("Order",{army.archer},death)
  waitFor(function() return death.Parent~=folders.units end,(flat(army.archer)-flat(death)).Magnitude/15+100,"弓兵正常攻擊致村民移除")
  send("Order",{army.archer},parking)
  check(other:GetAttribute("Defeated")==false and workspace:GetAttribute("MatchPhase")=="Playing","村民移除發生於戰鬥中，不是投降／終局清場")
  coverage.unitDeath=true; move({army.archer},parking,"死亡驗證後弓兵撤離")
  local houseBefore=house:GetAttribute("HP")
  check(house.Parent==folders.buildings and houseBefore>0,"房屋死亡前具有真實剩餘 HP")
  send("Order",{army.ram},house)
  waitFor(function() return house.Parent~=folders.buildings end,(flat(army.ram)-flat(house)).Magnitude/9+150,"衝車正常攻擊摧毀房屋")
  send("Order",{army.ram},parking)
  check(other:GetAttribute("Defeated")==false and workspace:GetAttribute("MatchPhase")=="Playing","房屋移除由真正攻擊發生，不是整局清場")
  coverage.buildingDeath=true
  -- The peer checks the two actual removals before issuing its ordinary surrender.
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" and report(player) and report(other) end,45,"第二端正常投降與雙方正式覆盤",true)
  local mine,theirs=report(player),report(other)
  validateReport(mine,"win",ledger.enemy); validateReport(theirs,"loss",ledger.friendly)
  check(mine.matchId==theirs.matchId and mine.unitsKilled>=1 and mine.buildingsKilled>=1 and theirs.unitsLost>=1 and theirs.buildingsLost>=1,"同局雙方正式覆盤確認真實單位與建築擊殺／損失")
  if fresh then check(mine.unitsKilled==1 and mine.buildingsKilled==1 and theirs.unitsLost==1 and theirs.buildingsLost==1,"受控新局僅一名村民與一座房屋死亡，投降清場不刷戰損") end
  coverage.reports=true
  uiChecks=require(RS.Shared.MatchReportTests).Run()
  print("[COMBAT_FLOW LIMIT] 本模組未驗證箭羽前後實際射程、拇指環攻擊間隔、外部摧毀研究取消、勝利三模式或完整 2v2；這些不計入本次 G07。")
 end
 local ok,result=xpcall(function()
  start(); local army=develop()
  if options.prepareOnly==true then
   print("[COMBAT_FLOW PREPARED] 正常發展完成，未執行戰鬥／投降；供獨立 G07 階段使用")
   return {role=role,checks=checks,prepared=true,army=army,player=player,opponent=other,parking=parking,home=home,victory=workspace:GetAttribute("VictoryMode"),elapsedSeconds=os.clock()-started}
  end
  if role=="host" then battle(army)
  else
   local house,tower,castle,death=makeFixture()
   local housePosition=flat(house)
   -- No fake completion token: wait for real shooting and attack destruction.
   waitFor(function()
    return house.Parent~=folders.buildings and death.Parent~=folders.units
     and type(tower:GetAttribute("LastAttack"))=="number" and type(castle:GetAttribute("LastAttack"))=="number"
   end,3000,"第一端完成真實炮塔射擊與村民／房屋死亡")
   -- Ordinary movement is the acknowledgement. Let the attacker leave the impact
   -- area before surrender so its client can distinguish combat removal from cleanup.
   waitFor(function()
    for _,unit in ipairs(owned(folders.units,other.UserId,"ram","UnitType")) do
     local position=unit:GetAttribute("AttackPosition")
     if typeof(position)=="Vector3" and (Vector3.new(position.X,0,position.Z)-housePosition).Magnitude<2
      and unit:GetAttribute("Order")=="移動" and (flat(unit)-housePosition).Magnitude>60 then return true end
    end
    return false
   end,30,"房屋摧毀後衝車以正常移動撤離，雙端已觀察真實戰損")
   check(player:GetAttribute("Defeated")==false and workspace:GetAttribute("MatchPhase")=="Playing","正常投降前已實際觀察到戰場兩種死亡")
   send("Surrender")
   waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" and report(player) end,15,"第二端正常投降產生正式報告",true)
   validateReport(report(player),"loss",ledger.enemy)
   coverage.reports=true
   uiChecks=require(RS.Shared.MatchReportTests).Run()
  end
  print(string.format("[COMBAT_FLOW COMPLETE] %s；%d 檢查；%.1f 秒；coverage 僅代表本端實際完成項目",role,checks,os.clock()-started))
  return {role=role,checks=checks,uiChecks=uiChecks,elapsedSeconds=os.clock()-started,coverage=coverage,fresh=fresh,cloudVerified=false}
 end,debug.traceback)
 paused=true
 for _,connection in ipairs(connections) do connection:Disconnect() end
 if not ok then warn("[COMBAT_FLOW FAIL] 保留失敗戰局；不投降、不重開、不強制清場"); error(result,0) end
 return result
end

local function invoke(role,options)
 assert(not Tests.running,"[COMBAT_FLOW FAIL] 此客戶端已有 CombatFlow 正在執行")
 Tests.running=true
 local ok,result=pcall(run,role,options)
 Tests.running=false
 if not ok then error(result,0) end
 sessions[role]=result
 return result
end
function Tests.RunHost(options) return invoke("host",options) end
function Tests.RunPeer(options) return invoke("peer",options) end
function Tests.Results() return sessions end
return Tests
