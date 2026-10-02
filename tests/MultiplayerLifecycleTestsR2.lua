-- Explicit SERVER entry in an isolated Studio Server & Clients session.
-- R2 walks real lobby avatars using Humanoid:Move; it never sets their CFrame
-- or network owner. Existing Shared tests run only after SERVER queue ACK.
-- Uses two actual client LocalScripts and normal RTS commands. It kicks both
-- test players after their positive/ownership checks; do not use in solo Play.
local Tests={running=false,lastReport=nil}
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local REMOTE_NAME="LifecycleStage"
local PREFIX="[MULTIPLAYER_LIFECYCLE_R2 "

local function managed(parent,id,kind)
 local result={}
 for _,model in ipairs(parent:GetChildren()) do
  if model:IsA("Model") and model:GetAttribute("RTSManaged")==true
   and (id==nil or model:GetAttribute("OwnerId")==id)
   and (kind==nil or model:GetAttribute("BuildingType")==kind or model:GetAttribute("UnitType")==kind) then
   table.insert(result,model)
  end
 end
 return result
end
local function nodes(resources,includeParts)
 local count,parts=0,0
 for _,model in ipairs(resources:GetChildren()) do
  if model:GetAttribute("RTSManagedResource")==true then
   count+=1
   if includeParts then for _,item in ipairs(model:GetDescendants()) do if item:IsA("BasePart") then parts+=1 end end end
  end
 end
 return count,parts
end
local function census(resources,hostId,peerId)
 local count,parts=nodes(resources,true)
 return {players=#Players:GetPlayers(),phase=workspace:GetAttribute("MatchPhase"),generation=workspace:GetAttribute("MatchGeneration") or 0,
  resourceNodes=count,resourceParts=parts,resourceNodeCount=workspace:GetAttribute("ResourceNodeCount") or 0,
  managedUnits=#managed(workspace.Units),managedBuildings=#managed(workspace.Buildings),
  victimUnits=#managed(workspace.Units,hostId),victimBuildings=#managed(workspace.Buildings,hostId),
  peerUnits=#managed(workspace.Units,peerId),peerBuildings=#managed(workspace.Buildings,peerId),
  hostUserId=workspace:GetAttribute("HostUserId") or 0,winnerId=workspace:GetAttribute("WinnerId") or 0,
  winnerTeamId=workspace:GetAttribute("WinnerTeamId") or 0,aiCount=workspace:GetAttribute("AICount") or 0,
  factionCount=workspace:GetAttribute("FactionCount") or 0,lobbyPlayers=workspace:GetAttribute("LobbyPlayers") or 0,
  matchTime=workspace:GetAttribute("MatchTime") or 0}
end
local function waitFor(predicate,seconds,message,deadline,abort)
 local stopAt=math.min(os.clock()+seconds,deadline or math.huge)
 repeat
  if abort then local failure=abort(); if failure then error(failure,0) end end
  if predicate() then return end
  task.wait(.1)
 until os.clock()>=stopAt
 error(message,0)
end
local function metadata(model)
 local part=assert(model.PrimaryPart,"測試模型缺少 PrimaryPart")
 return {model=model,parent=model.Parent,part=part,partParent=part.Parent,cframe=part.CFrame,size=part.Size,material=part.Material,
  color=part.Color,anchored=part.Anchored,collide=part.CanCollide,query=part.CanQuery,touch=part.CanTouch,
  resourceFlag=model:GetAttribute("RTSManagedResource"),managedFlag=model:GetAttribute("RTSManaged"),fixture=model:GetAttribute("LifecycleFixture")}
end
local function unchanged(saved)
 local model,part=saved.model,saved.part
 return model.Parent==saved.parent and model.PrimaryPart==part and part.Parent==saved.partParent
  and part.CFrame==saved.cframe and part.Size==saved.size and part.Material==saved.material and part.Color==saved.color
  and part.Anchored==saved.anchored and part.CanCollide==saved.collide and part.CanQuery==saved.query and part.CanTouch==saved.touch
  and model:GetAttribute("RTSManagedResource")==saved.resourceFlag and model:GetAttribute("RTSManaged")==saved.managedFlag
  and model:GetAttribute("LifecycleFixture")==saved.fixture
end
local function reportChunks(encoded)
 local chunks={}
 local first=1
 while first<=#encoded do
  local last=math.min(first+319,#encoded)
  if last<#encoded then
   local boundary=last+1
   while string.byte(encoded,boundary)>=128 and string.byte(encoded,boundary)<=191 do boundary-=1 end
   last=boundary-1 -- End before a complete UTF-8 code point; never split it.
  end
  assert(last>=first,"報告 UTF-8 分段失敗")
  table.insert(chunks,encoded:sub(first,last))
  first=last+1
 end
 return chunks
end
local function printReport(stage,report)
 local encoded=Http:JSONEncode(report)
 local chunks=reportChunks(encoded)
 local reportId=Http:GenerateGUID(false)
 for index,chunk in ipairs(chunks) do
  local line=PREFIX.."REPORT_CHUNK] "..Http:JSONEncode({reportId=reportId,stage=stage,index=index,total=#chunks,text=chunk})
  assert(#line<850,"報告分段超過 Studio 日誌安全長度")
  print(line)
 end
 local summary={reportId=reportId,chunks=#chunks,bytes=#encoded,complete=report.complete,role=report.role,checks=report.checks,
  hostUserId=report.hostUserId or (report.playersUserId and report.playersUserId.host),
  peerUserId=report.peerUserId or (report.playersUserId and report.playersUserId.peer),failure=report.failure and "see complete report chunks" or nil}
 if report.afterLast then summary.afterNodes=report.afterLast.resourceNodes; summary.afterParts=report.afterLast.resourceParts; summary.generation=report.afterLast.generation end
 local line=PREFIX..stage.."] "..Http:JSONEncode(summary)
 assert(#line<700,"報告摘要超過安全長度")
 print(line) -- Accept evidence only with every matching chunk AND this summary.
end

function Tests.RunClient(role)
 local player=Players.LocalPlayer
 local report={complete=false,role=role,scope="actual client Humanoid walking, replicated instances and normal RTS commands",checks=0}
 local remote,worker,readyWorker,removing
 local walkBind,walkingHumanoid
 local deadline=os.clock()+210
 local active=true
 local function check(ok,message)
  assert(ok,"客戶端："..message); report.checks+=1
 end
 local function stopWalking()
  if walkBind then RunService:UnbindFromRenderStep(walkBind); walkBind=nil end
  if walkingHumanoid and walkingHumanoid.Parent then pcall(function() walkingHumanoid:Move(Vector3.zero,false) end) end
  walkingHumanoid=nil
 end
 local function abort()
  if not active then return "客戶端測試已停止" end
  if remote and (not remote.Parent or remote:GetAttribute("Aborted")==true) then return "伺服器已中止測試" end
 end
 local function stage(name,data)
  assert(remote and remote.Parent,"測試遠端已移除")
  remote:FireServer(remote:GetAttribute("Session"),role,name,data or {checks=report.checks})
  printReport("CLIENT_STAGE",{role=role,stage=name,checks=report.checks})
 end
 local ok,failure=xpcall(function()
  check(RunService:IsStudio() and RunService:IsClient() and player~=nil,"只允許真正 Studio CLIENT")
  check(role=="host" or role=="peer","測試角色有效")
  check(script.Parent==RS:FindFirstChild("MultiplayerLifecycleValidation"),"只允許隔離驗證專案")
  remote=assert(script.Parent:WaitForChild(REMOTE_NAME,15),"伺服器尚未建立測試遠端")
  local hostId,peerId=remote:GetAttribute("HostUserId"),remote:GetAttribute("PeerUserId")
  check(player.UserId==(role=="host" and hostId or peerId),"PlayerGui 啟動器角色與真 Player 相符")
  check(#Players:GetPlayers()==2 and workspace:GetAttribute("MatchPhase")=="Lobby","兩位真玩家的新大廳")
  local resources=workspace:WaitForChild("Resources",10)
  local unknown,container,nested
  waitFor(function()
   unknown=resources:FindFirstChild("LifecycleUnknownResource")
   container=resources:FindFirstChild("LifecycleUnknownFolder")
   nested=container and container:FindFirstChild("LifecycleNestedResource")
   return unknown and unknown.PrimaryPart and nested and nested.PrimaryPart
    and unknown:GetAttribute("LifecycleFixture")==remote:GetAttribute("Session")
  end,15,"未知資源 fixture 尚未完整複製",deadline,abort)
  local original,nestedOriginal=metadata(unknown),metadata(nested)
  local Config=require(RS.GameData.GameConfig)
  local Multiplayer=require(RS.Shared.MultiplayerTests)
  local command=RS.RTSRemotes.Command
  local target=Config.Map.ResourceNodeTargets.Small
  report.playerUserId=player.UserId; report.hostUserId=hostId; report.peerUserId=peerId
  stage("CLIENT_STARTED")
  local function walkIntoQueue()
   local portal=Config.Lobby.origin+Config.Lobby.portalOffset
   local spawn=Config.Lobby.origin+Config.Lobby.spawnOffset
   local character,root
   waitFor(function()
    character=player.Character; root=character and character:FindFirstChild("HumanoidRootPart")
    walkingHumanoid=character and character:FindFirstChildOfClass("Humanoid")
    if not root or not walkingHumanoid or walkingHumanoid.Health<=0 or walkingHumanoid.RootPart~=root then return false end
    local delta=root.Position-spawn
    return remote:GetAttribute("FixtureReady")==true and delta.X*delta.X+delta.Z*delta.Z<=64
   end,20,"本地角色尚未收到伺服器大廳定位",deadline,abort)
   local start=root.Position
   local goal=portal+Vector3.new(role=="host" and -6 or 6,0,8)
   walkBind="LifecycleWalk_"..remote:GetAttribute("Session").."_"..role
   RunService:BindToRenderStep(walkBind,Enum.RenderPriority.Input.Value+1,function()
    local direction=Vector3.zero
    if active and player.Character==character and walkingHumanoid and walkingHumanoid.Parent and walkingHumanoid.Health>0
     and workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("LobbyQueued")~=true then
     local delta=goal-root.Position
     local horizontal=Vector3.new(delta.X,0,delta.Z)
     if horizontal.Magnitude>1 then direction=horizontal.Unit end
    end
    if walkingHumanoid and walkingHumanoid.Parent then walkingHumanoid:Move(direction,false) end
   end)
   local nextRequest=0
   waitFor(function()
    assert(player.Character==character and walkingHumanoid and walkingHumanoid.Health>0,"行走期間角色已失效")
    if player:GetAttribute("LobbyQueued")==true then return true end
    if os.clock()>=nextRequest then command:FireServer("QueueJoin"); nextRequest=os.clock()+.5 end
    return false
   end,30,"正常 Humanoid 行走／QueueJoin 未取得入隊 ACK",deadline,abort)
   check((root.Position-start).Magnitude>16,"真正行走讓角色離開出生位置")
   report.walk={initial={x=start.X,y=start.Y,z=start.Z},queuedClient={x=root.Position.X,y=root.Position.Y,z=root.Position.Z},
    distanceMoved=(root.Position-start).Magnitude,priority=Enum.RenderPriority.Input.Value+1}
   stage("WALK_QUEUED",{checks=report.checks,walk=report.walk})
   waitFor(function() return remote:GetAttribute(role.."QueueConfirmed")==true end,15,"SERVER 尚未確認入隊與傳送門內真 Root 位置",deadline,abort)
   stopWalking()
   check(player:GetAttribute("LobbyQueued")==true,"SERVER 證實入隊後才交給原有多人測試")
   report.walk.serverConfirmed=true
  end
  -- Join changes the settings revision. Retry only the ordinary ready command
  -- while both participants are queued, so a replication race cannot strand it.
  local mayReady=false
  readyWorker=task.spawn(function()
   while active and workspace:GetAttribute("MatchPhase")=="Lobby" do
    if mayReady and workspace:GetAttribute("LobbyExpectedPlayers")==2 and workspace:GetAttribute("LobbyPlayers")==2
     and player:GetAttribute("LobbyQueued")==true and player:GetAttribute("LobbyReady")~=true then
     command:FireServer("LobbyReady",true,workspace:GetAttribute("LobbySettingsRevision"))
    end
    task.wait(.35)
   end
  end)
  local done,workerOk,workerFailure=false,false,nil
  worker=task.spawn(function()
   workerOk,workerFailure=xpcall(function()
    if role=="host" then
     walkIntoQueue()
     mayReady=true
     check(Multiplayer.RunHost()==true,"正常建造與訓練測試回傳完成")
     local own=managed(workspace.Units,player.UserId)
     command:FireServer("Stop",own)
     waitFor(function()
      for _,unit in ipairs(own) do if unit.Parent~=workspace.Units or unit:GetAttribute("Order")~="待命" then return false end end
      local center=managed(workspace.Buildings,player.UserId,"TownCenter")[1]
      return center and (center:GetAttribute("QueueCount") or 0)==0
     end,10,"房主正常 Stop 尚未生效或訓練尚未結束",deadline,abort)
     check(#own==5 and #managed(workspace.Units,hostId,"villager")==4,"訓練後房主有四村民與斥候")
     check(#managed(workspace.Buildings,hostId,"House")==1 and managed(workspace.Buildings,hostId,"House")[1]:GetAttribute("Complete")==true,"房屋已完工")
     waitFor(function() return nodes(resources,false)==target and workspace:GetAttribute("ResourceNodeCount")==target end,15,"房主未完整收到生成資源",deadline,abort)
     check(unchanged(original) and unchanged(nestedOriginal) and container.Parent==resources,"開局保留 fixture 外觀／旗標／層級")
     report.before=census(resources,hostId,peerId)
     report.sharedHostCompleted=true; report.normalStopConfirmed=true
     stage("HOST_READY",{checks=report.checks,sharedHostCompleted=true,normalStopConfirmed=true,census=report.before})
    else
     waitFor(function()
      local host=Players:GetPlayerByUserId(hostId)
      return host and host:GetAttribute("LobbyQueued")==true and workspace:GetAttribute("HostUserId")==hostId
       and workspace:GetAttribute("LobbyExpectedPlayers")==2
     end,55,"尚未收到房主已集合的雙人設定",deadline,abort)
     walkIntoQueue()
     mayReady=true
     check(Multiplayer.JoinLobby()==true,"第二玩家正常集合與準備")
     stage("PEER_QUEUED")
     waitFor(function() return remote:GetAttribute("HostReady")==true end,100,"房主建造／訓練尚未完成",deadline,abort)
     waitFor(function()
      local center=managed(workspace.Buildings,hostId,"TownCenter")[1]
      local house=managed(workspace.Buildings,hostId,"House")[1]
      if not center or not house or house:GetAttribute("Complete")~=true or #managed(workspace.Units,hostId)~=5 then return false end
      for _,unit in ipairs(managed(workspace.Units,hostId)) do if unit:GetAttribute("Order")~="待命" then return false end end
      return workspace:GetAttribute("MatchPhase")=="Playing" and (center:GetAttribute("QueueCount") or 0)==0
     end,15,"第二端尚未同步已完工房屋、訓練單位與停止狀態",deadline,abort)
     check(Multiplayer.RunOwnership()==true,"真正第二客戶端所有權／非法指令測試完成")
     waitFor(function() return nodes(resources,false)==target and workspace:GetAttribute("ResourceNodeCount")==target end,15,"第二端未完整收到生成資源",deadline,abort)
     check(unchanged(original) and unchanged(nestedOriginal) and container.Parent==resources,"第二端開局保留 fixture metadata")
     report.sharedOwnershipCompleted=true; report.before=census(resources,hostId,peerId)
     stage("OWNERSHIP_READY",{checks=report.checks,sharedOwnershipCompleted=true,census=report.before})
     local removed=false
     removing=Players.PlayerRemoving:Connect(function(leaving) if leaving.UserId==hostId then removed=true end end)
     stage("CLEANUP_ARMED",{checks=report.checks,victimUserId=hostId,eventArmed=true})
     waitFor(function()
      return removed and Players:GetPlayerByUserId(hostId)==nil and #managed(workspace.Units,hostId)==0 and #managed(workspace.Buildings,hostId)==0
       and workspace:GetAttribute("MatchPhase")=="Ended" and workspace:GetAttribute("WinnerId")==peerId and workspace:GetAttribute("HostUserId")==peerId
     end,35,"第二端未觀察到真 PlayerRemoving、清理、勝利或房主轉移",deadline,abort)
     report.afterHost=census(resources,hostId,peerId)
     check(report.afterHost.resourceNodes==target and report.afterHost.resourceParts==report.before.resourceParts
      and report.afterHost.resourceNodeCount==target,"Ended 保留全部生成資源供觀戰")
     check(report.afterHost.generation==report.before.generation,"第一玩家離開沒有重開 generation")
     check(report.afterHost.peerUnits==4 and report.afterHost.peerBuildings==1,"存留玩家物件沒有被誤刪")
     check(unchanged(original) and unchanged(nestedOriginal) and container.Parent==resources,"第一玩家離開仍保留未知 fixture metadata")
     report.playerRemovingSeen=true
     stage("PEER_CLEANUP",{checks=report.checks,playerRemovingSeen=true,census=report.afterHost})
    end
   end,debug.traceback)
   done=true
  end)
  waitFor(function() return done end,200,"客戶端測試超過總期限",deadline,abort)
  if not workerOk then error(workerFailure,0) end
  report.complete=true
 end,debug.traceback)
 active=false
 stopWalking()
 if worker and coroutine.status(worker)~="dead" then task.cancel(worker) end
 if readyWorker and coroutine.status(readyWorker)~="dead" then task.cancel(readyWorker) end
 if removing then removing:Disconnect() end
 report.failure=not ok and tostring(failure) or nil
 if not ok and remote and remote.Parent then
  remote:FireServer(remote:GetAttribute("Session"),role,"FAILED",{checks=report.checks,message=tostring(failure):sub(1,2000)})
 end
 Tests.lastReport=report
 printReport(ok and "CLIENT_COMPLETE" or "CLIENT_INCOMPLETE",report)
 if ok and remote and remote.Parent then stage("CLIENT_DONE",{checks=report.checks,complete=true}) end
 return report
end

function Tests.RunServer()
 local report={complete=false,checks=0,clientStages={},scope="server instances/public lifecycle attributes; no private cache, FPS or memory claim"}
 local remote,stageConnection,departureConnection,addedConnection
 local launchers={}
 local deadline=os.clock()+240
 local failures={}
 local ownsRun=false
 local function check(ok,message)
  assert(ok,"伺服器："..message); report.checks+=1
 end
 local function abort() return failures[1] end
 local ok,failure=xpcall(function()
  check(RunService:IsStudio() and RunService:IsServer(),"僅限 Studio SERVER")
  check(script.Parent==RS:FindFirstChild("MultiplayerLifecycleValidation"),"僅限隔離驗證專案")
  check(not Tests.running,"測試不能重複執行")
  check(#Players:GetPlayers()==2,"需要 Server & Clients 的兩位真 Player")
  check(workspace:GetAttribute("MatchPhase")=="Lobby" and (workspace:GetAttribute("MatchGeneration") or 0)==0
   and (workspace:GetAttribute("LobbyPlayers") or 0)==0,"需要沒有開局或集合的新大廳")
  check(not script.Parent:FindFirstChild(REMOTE_NAME),"此驗證場尚未建立測試遠端")
  Tests.running=true
  ownsRun=true
  local participants=Players:GetPlayers()
  table.sort(participants,function(a,b) return a.Name<b.Name end)
  local host,peer=participants[1],participants[2]
  check(host:IsA("Player") and peer:IsA("Player") and host.Parent==Players and peer.Parent==Players
   and host.UserId~=peer.UserId and host.UserId~=0 and peer.UserId~=0,"角色使用兩位真 Player；允許 Studio 負 UserId")
  report.playersUserId={host=host.UserId,peer=peer.UserId}; report.playerNames={host=host.Name,peer=peer.Name}
  report.session=Http:GenerateGUID(false)
  local resources=workspace:WaitForChild("Resources",10)
  local Config=require(RS.GameData.GameConfig)
  local spawn=Config.Lobby.origin+Config.Lobby.spawnOffset
  local stableSamples=0
  waitFor(function()
   if workspace:GetAttribute("RTSReady")~=true then return false end
   for _,player in ipairs({host,peer}) do
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if not player:FindFirstChildOfClass("PlayerGui") or not root or not humanoid or humanoid.Health<=0 or humanoid.RootPart~=root then stableSamples=0; return false end
    local delta=root.Position-spawn
    if delta.X*delta.X+delta.Z*delta.Z>64 or math.abs(delta.Y)>8 then stableSamples=0; return false end
   end
   stableSamples+=1
   return stableSamples>=3
  end,20,"兩位玩家的大廳／PlayerGui 尚未就緒",deadline,abort)
  report.serverSpawn={}
  for role,player in pairs({host=host,peer=peer}) do
   local pos=player.Character.HumanoidRootPart.Position
   report.serverSpawn[role]={x=pos.X,y=pos.Y,z=pos.Z}
  end
  check(nodes(resources,false)==0 and #managed(workspace.Units)==0 and #managed(workspace.Buildings)==0,"新大廳沒有上一局生成資料")
  check(host:GetAttribute("LobbyQueued")~=true and peer:GetAttribute("LobbyQueued")~=true,"兩位玩家尚未集合")
  check(not resources:FindFirstChild("LifecycleUnknownResource") and not resources:FindFirstChild("LifecycleUnknownFolder"),"測試 fixture 名稱尚未使用")
  local function fixture(name,parent,position,flag)
   local model=Instance.new("Model"); model.Name=name; model:SetAttribute("LifecycleFixture",report.session)
   if flag then model:SetAttribute("RTSManagedResource",true) end
   local part=Instance.new("Part"); part.Name="保留原有外觀"; part.Size=Vector3.new(3,4,5); part.CFrame=CFrame.new(position)*CFrame.Angles(0,.3,0)
   part.Anchored=true; part.CanCollide=false; part.CanQuery=false; part.CanTouch=false
   part.Material=Enum.Material.Marble; part.Color=Color3.fromRGB(81,189,104); part.Parent=model
   model.PrimaryPart=part; model.Parent=parent; return model
  end
  local unknown=fixture("LifecycleUnknownResource",resources,Vector3.new(3000,7,3000),false)
  local container=Instance.new("Folder"); container.Name="LifecycleUnknownFolder"; container:SetAttribute("LifecycleFixture",report.session); container.Parent=resources
  local nested=fixture("LifecycleNestedResource",container,Vector3.new(3008,7,3000),true)
  local original,nestedOriginal=metadata(unknown),metadata(nested)
  report.initial=census(resources,host.UserId,peer.UserId)
  local departures={}
  departureConnection=Players.PlayerRemoving:Connect(function(leaving)
   if leaving==host or leaving==peer then departures[leaving]=true end
  end)
  addedConnection=Players.PlayerAdded:Connect(function() table.insert(failures,"測試期間有第三位玩家加入") end)
  remote=Instance.new("RemoteEvent"); remote.Name=REMOTE_NAME
  remote:SetAttribute("Session",report.session); remote:SetAttribute("HostUserId",host.UserId); remote:SetAttribute("PeerUserId",peer.UserId)
  remote:SetAttribute("HostReady",false); remote:SetAttribute("Aborted",false)
  remote:SetAttribute("FixtureReady",true); remote:SetAttribute("hostQueueConfirmed",false); remote:SetAttribute("peerQueueConfirmed",false)
  report.serverQueue={}
  local sequences={host={"CLIENT_STARTED","WALK_QUEUED","HOST_READY","CLIENT_DONE"},peer={"CLIENT_STARTED","WALK_QUEUED","PEER_QUEUED","OWNERSHIP_READY","CLEANUP_ARMED","PEER_CLEANUP","CLIENT_DONE"}}
  local stages={host={},peer={}}
  local nextStage={host=1,peer=1}
  local function validPayload(value,depth)
   if depth>4 then return false end
   if type(value)=="number" then return value==value and value>-math.huge and value<math.huge end
   if type(value)=="boolean" then return true end
   if type(value)=="string" then return #value<=2100 end
   if type(value)~="table" then return false end
   local count=0
   for key,item in pairs(value) do
    count+=1
    if count>40 or type(key)~="string" or #key>60 or not validPayload(item,depth+1) then return false end
   end
   return true
  end
  stageConnection=remote.OnServerEvent:Connect(function(sender,session,role,name,data)
   if session~=report.session or (role~="host" and role~="peer") or sender~=(role=="host" and host or peer)
    or sender.Parent~=Players or type(name)~="string" or not validPayload(data,0) then return end
   if name=="FAILED" then
    if not stages[role].FAILED then stages[role].FAILED=true; table.insert(failures,role.." 客戶端失敗："..tostring(data.message)) end
    return
   end
   if name~=sequences[role][nextStage[role]] then return end -- Exact role/order; each stage accepted once.
   if type(data.checks)~="number" or data.checks%1~=0 or data.checks<1 or data.checks>200 then return end
   if name=="WALK_QUEUED" then
    local root=sender.Character and sender.Character:FindFirstChild("HumanoidRootPart")
    local portal=Config.Lobby.origin+Config.Lobby.portalOffset
    if workspace:GetAttribute("MatchPhase")~="Lobby" or sender:GetAttribute("LobbyQueued")~=true or not root then return end
    local delta=root.Position-portal
    if delta.X*delta.X+delta.Z*delta.Z>Config.Lobby.portalRadius^2 or delta.Y< -3 or delta.Y>18 then return end
    report.serverQueue[role]={queued=true,x=root.Position.X,y=root.Position.Y,z=root.Position.Z,anchored=root.Anchored,
     joinOrder=sender:GetAttribute("LobbyJoinOrder"),players=workspace:GetAttribute("LobbyPlayers")}
    remote:SetAttribute(role.."QueueConfirmed",true)
   end
   if name=="HOST_READY" and (data.sharedHostCompleted~=true or data.normalStopConfirmed~=true) then return end
   if name=="OWNERSHIP_READY" and (stages.host.HOST_READY~=true or data.sharedOwnershipCompleted~=true) then return end
   if name=="CLEANUP_ARMED" and (data.victimUserId~=host.UserId or data.eventArmed~=true) then return end
   if name=="PEER_CLEANUP" and (data.playerRemovingSeen~=true or not departures[host]) then return end
   if name=="CLIENT_DONE" and data.complete~=true then return end
   stages[role][name]=true; nextStage[role]+=1
   table.insert(report.clientStages,{role=role,stage=name,checks=data.checks,data=data})
   if name=="HOST_READY" then remote:SetAttribute("HostReady",true) end
   printReport("SERVER_STAGE",{role=role,stage=name,checks=data.checks})
  end)
  remote.Parent=script.Parent
  for role,player in pairs({host=host,peer=peer}) do
   local launcher=Instance.new("LocalScript"); launcher.Name="MultiplayerLifecycleClient"; launcher:SetAttribute("Role",role)
   table.insert(launchers,launcher)
   -- Source writes require Command Bar privilege. Fail explicitly before any
   -- Kick if Studio denies it; there is no client-context simulation fallback.
   local injected,reason=pcall(function()
    launcher.Source=[=[require(game:GetService("ReplicatedStorage"):WaitForChild("MultiplayerLifecycleValidation",15):WaitForChild("Tests",15)).RunClient(script:GetAttribute("Role"))]=]
   end)
   check(injected,"Command Bar 可注入真 CLIENT LocalScript："..tostring(reason or role))
   launcher.Parent=player:FindFirstChildOfClass("PlayerGui")
  end
  waitFor(function() return stages.host.CLIENT_STARTED and stages.peer.CLIENT_STARTED end,25,"兩個真 CLIENT 啟動器尚未回報",deadline,abort)
  waitFor(function() return stages.host.HOST_READY and stages.host.CLIENT_DONE end,145,"房主正常行走、建屋／訓練未回報完成",deadline,abort)
  waitFor(function() return stages.peer.OWNERSHIP_READY and stages.peer.CLEANUP_ARMED end,30,"第二端所有權檢查或離開觀察器尚未就緒",deadline,abort)
  local target=require(RS.GameData.GameConfig).Map.ResourceNodeTargets.Small
  report.before=census(resources,host.UserId,peer.UserId)
  check(report.before.players==2 and report.before.phase=="Playing" and report.before.victimUnits==5 and report.before.victimBuildings==2
   and report.before.peerUnits==4 and report.before.peerBuildings==1,"伺服器確認雙人建造／訓練的實際實例")
  check(report.before.resourceNodes==target and report.before.resourceNodeCount==target and report.before.resourceParts>0,"伺服器完整生成 Small 資源")
  check(report.before.hostUserId==host.UserId and report.before.aiCount==0,"真正房主與沒有額外電腦")
  check(unchanged(original) and unchanged(nestedOriginal) and container.Parent==resources,"開局保留未知 fixture metadata")
  local generated={}
  for _,model in ipairs(resources:GetChildren()) do if model:GetAttribute("RTSManagedResource")==true then table.insert(generated,model) end end
  local victimModels={}
  for _,folder in ipairs({workspace.Units,workspace.Buildings}) do for _,model in ipairs(managed(folder,host.UserId)) do table.insert(victimModels,model) end end
  report.firstKickIssued=true
  host:Kick("隔離雙人生命週期測試：驗證第一位玩家離開。")
  waitFor(function()
   return departures[host] and host.Parent~=Players and #Players:GetPlayers()==1 and workspace:GetAttribute("MatchPhase")=="Ended"
    and #managed(workspace.Units,host.UserId)==0 and #managed(workspace.Buildings,host.UserId)==0
    and workspace:GetAttribute("WinnerId")==peer.UserId and workspace:GetAttribute("HostUserId")==peer.UserId
  end,20,"SERVER 未完成真 PlayerRemoving 清理／勝利／房主轉移",deadline,abort)
  report.afterHost=census(resources,host.UserId,peer.UserId)
  check(report.afterHost.resourceNodes==target and report.afterHost.resourceParts==report.before.resourceParts
   and report.afterHost.resourceNodeCount==target,"SERVER Ended 保留完整資源")
  check(report.afterHost.generation==report.before.generation and report.afterHost.peerUnits==4 and report.afterHost.peerBuildings==1,"第一玩家離開保持 generation 與存留玩家物件")
  for _,model in ipairs(victimModels) do check(model.Parent==nil,"離開玩家原實例全部被移除") end
  for _,model in ipairs(generated) do assert(model.Parent==resources,"Ended 不得刪除生成資源") end
  check(unchanged(original) and unchanged(nestedOriginal) and container.Parent==resources,"第一玩家離開保留未知 fixture metadata")
  waitFor(function() return stages.peer.PEER_CLEANUP and stages.peer.CLIENT_DONE end,20,"第二端未回報真正離開清理／完整 Ended 資源／完成日誌",deadline,abort)
  report.peerCleanupAcknowledged=true
  report.clientComplete={host=stages.host.CLIENT_DONE==true,peer=stages.peer.CLIENT_DONE==true}
  printReport("BEFORE_LAST_KICK",{before=report.before,afterHost=report.afterHost,peerCleanupAcknowledged=true})
  local remainingModels={}
  for _,folder in ipairs({workspace.Units,workspace.Buildings}) do for _,model in ipairs(managed(folder,peer.UserId)) do table.insert(remainingModels,model) end end
  report.lastKickIssued=true
  peer:Kick("隔離雙人生命週期測試：驗證最後玩家離開與返回空大廳。")
  waitFor(function()
   return departures[peer] and peer.Parent~=Players and #Players:GetPlayers()==0 and workspace:GetAttribute("MatchPhase")=="Lobby"
    and #managed(workspace.Units)==0 and #managed(workspace.Buildings)==0
    and nodes(resources,false)==0 and workspace:GetAttribute("ResourceNodeCount")==0
  end,20,"最後玩家離開未完成；若 Studio 結束模擬，這次仍屬 INCOMPLETE",deadline,abort)
  report.afterLast=census(resources,host.UserId,peer.UserId)
  check(report.afterLast.resourceNodes==0 and report.afterLast.resourceParts==0,"最後離開釋放所有生成資源與其零件")
  check(report.afterLast.generation==report.before.generation+1,"最後離開只清理一次並更新 generation")
  check(report.afterLast.hostUserId==0 and report.afterLast.winnerId==0 and report.afterLast.winnerTeamId==0
   and report.afterLast.aiCount==0 and report.afterLast.factionCount==0 and report.afterLast.lobbyPlayers==0 and report.afterLast.matchTime==0,"空大廳公開生命週期狀態歸零")
  local removed=0
  for _,model in ipairs(generated) do assert(model.Parent==nil,"最後離開生成資源仍存在"); removed+=1 end
  check(removed==target,"所有開局生成資源原引用 Parent=nil")
  for _,model in ipairs(remainingModels) do check(model.Parent==nil,"最後玩家的原單位／建築已移除") end
  check(unchanged(original) and unchanged(nestedOriginal) and container.Parent==resources,"最後離開保留未知直接／巢狀模型全部 metadata")
  report.generatedReferencesRemoved=removed; report.playerRemovingSeen={host=departures[host]==true,peer=departures[peer]==true}
  report.complete=true
 end,debug.traceback)
 if remote and remote.Parent then remote:SetAttribute("Aborted",not ok) end
 for _,launcher in ipairs(launchers) do if launcher.Parent then launcher:Destroy() end end
 if stageConnection then stageConnection:Disconnect() end
 if departureConnection then departureConnection:Disconnect() end
 if addedConnection then addedConnection:Disconnect() end
 if remote then remote:Destroy() end
 report.failure=not ok and tostring(failure) or nil
 if ownsRun then Tests.running=false end
 Tests.lastReport=report
 printReport(ok and "COMPLETE" or "INCOMPLETE",report)
 return report
end
return Tests
