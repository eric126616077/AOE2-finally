-- 明確呼叫的雙人 Studio 客戶端驗證。只使用正常指令與本機設定；不改寫伺服器屬性。
-- 先用 MultiplayerTests.RunHost()/JoinLobby() 啟動真正兩名玩家。
-- 第二端先 task.spawn 呼叫 RunPeer()，房主再 task.spawn 呼叫 RunActor()。
-- 最後在存留第二端呼叫 ObserveCleanupClient()，手動關閉房主客戶端。
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Tests = {}
local Rules = require(RS.Shared.FeedbackRules)
local Focus = require(RS.Shared.CameraFocus)
local workNames = {wood="GatherWood",food="GatherFood",gold="GatherGold",stone="GatherStone"}

local function context()
 assert(RunService:IsStudio() and RunService:IsClient(), "[FEEDBACK_MULTI FAIL] 僅限真正 Studio 客戶端")
 assert(workspace:GetAttribute("MatchPhase") == "Playing" and #Players:GetPlayers() == 2,
  "[FEEDBACK_MULTI FAIL] 請先以兩名真實玩家開始對局")
 local player = Players.LocalPlayer
 local probe = player.PlayerScripts:FindFirstChild("RTSAudioProbe")
 assert(probe and probe:IsA("BindableFunction"), "[FEEDBACK_MULTI FAIL] 實際音效腳本的唯讀探針未就緒")
 assert(player:GetAttribute("RTSSoundReady") == true and player.PlayerScripts.UnitMotion:GetAttribute("RTSMotionReady") == true,
  "[FEEDBACK_MULTI FAIL] 實際音效或動作 LocalScript 未就緒")
 local other
 for _,candidate in ipairs(Players:GetPlayers()) do if candidate ~= player then other = candidate end end
 return player, other, probe, RS.RTSRemotes.Command
end
local function check(condition, message)
 assert(condition, "[FEEDBACK_MULTI FAIL] " .. message)
 print("[FEEDBACK_MULTI PASS] " .. message)
end
local function waitFor(predicate, seconds, message)
 local deadline = os.clock() + seconds
 repeat
  if predicate() then check(true, message); return end
  assert(os.clock() < deadline, "[FEEDBACK_MULTI FAIL] " .. message .. "；等待逾時")
  task.wait(.03)
 until false
end
local function owned(folder, id, kind)
 local models = {}
 for _,model in ipairs(folder:GetChildren()) do
  if model:IsA("Model") and model:GetAttribute("RTSManaged") == true and model:GetAttribute("OwnerId") == id
   and (not kind or model:GetAttribute("UnitType") == kind or model:GetAttribute("BuildingType") == kind) then
   table.insert(models,model)
  end
 end
 return models
end
local function soundLoaded(model, name)
 for _,object in ipairs(model:GetDescendants()) do
  if object:IsA("Sound") and object.Name == "RTS_" .. name and object.IsLoaded and object.TimeLength > 0 then return true end
 end
 return false
end
local function audible(model)
 local camera,root = workspace.CurrentCamera,model.PrimaryPart
 if not camera or not root then return false end
 local p,visible = camera:WorldToViewportPoint(root.Position)
 return Rules.WorldAudible(visible,p.Z,(camera.CFrame.Position-root.Position).Magnitude)
end
local function diagnostics(player,peer,scout,target,reason,elapsed)
 local function point(model)
  if not model or not model.Parent or not model.PrimaryPart then return nil end
  local p=model:GetPivot().Position
  return {x=p.X,y=p.Y,z=p.Z}
 end
 local function attrs(model)
  if not model then return {exists=false} end
  return {exists=model.Parent~=nil,parent=model.Parent and model.Parent:GetFullName() or "nil",
   name=model.Name,ownerId=model:GetAttribute("OwnerId"),teamId=model:GetAttribute("TeamId"),
   order=model:GetAttribute("Order"),animation=model:GetAttribute("Animation"),
   lastAttack=tostring(model:GetAttribute("LastAttack")),hp=model:GetAttribute("HP"),maxHP=model:GetAttribute("MaxHP"),
   position=point(model),audible=model.PrimaryPart~=nil and model.Parent~=nil and audible(model) or false}
 end
 local result={reason=reason,elapsedSeconds=elapsed,viewer=player.UserId,peerId=peer and peer.UserId,
  phase=workspace:GetAttribute("MatchPhase"),playerTeam=player:GetAttribute("TeamId"),peerTeam=peer and peer:GetAttribute("TeamId"),
  scout=attrs(scout),target=attrs(target)}
 print("[FEEDBACK_MULTI DIAGNOSTICS] " .. game:GetService("HttpService"):JSONEncode(result))
 return result
end
-- 唯讀：供 Command Bar 明確檢查當前真實斥候／另一方市鎮中心，不改寫任何實例。
function Tests.Diagnostics()
 assert(RunService:IsStudio() and RunService:IsClient(),"[FEEDBACK_MULTI FAIL] 診斷僅限 Studio 客戶端")
 local player,peer=Players.LocalPlayer,nil
 for _,candidate in ipairs(Players:GetPlayers()) do if candidate~=player then peer=candidate; break end end
 local units,buildings=workspace:FindFirstChild("Units"),workspace:FindFirstChild("Buildings")
 local scout=units and owned(units,player.UserId,"scout")[1]
 local target=buildings and peer and owned(buildings,peer.UserId,"TownCenter")[1]
 return diagnostics(player,peer,scout,target,"明確呼叫的唯讀診斷",nil)
end
local function offsets(model)
 local result = {}
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and (part.Name == "ArmR" or part.Name == "Tool" or part.Name == "ToolHead") then
   result[part] = model.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
  end
 end
 return result
end
local function poseChanged(model, rest)
 for part,offset in pairs(rest) do
  if part.Parent and model.PrimaryPart then
   local delta = offset:ToObjectSpace(model.PrimaryPart.CFrame:ToObjectSpace(part.CFrame))
   local _,angle = delta:ToAxisAngle()
   if math.abs(angle) > .02 or delta.Position.Magnitude > .02 then return true end
  end
 end
 return false
end
local function monitor(ownerId)
 local session = {work=0,delivery=0,attack=0,connections={},worker=nil,attacker=nil,mutedPulses=0}
 for _,model in ipairs(owned(workspace.Units,ownerId)) do
  for _,attribute in ipairs({"LastWork","LastDelivery","LastAttack"}) do
   local baseline = model:GetAttribute(attribute)
   table.insert(session.connections,model:GetAttributeChangedSignal(attribute):Connect(function()
    local value = model:GetAttribute(attribute)
    if not Rules.IsNewPulse(value,baseline) then baseline=value; return end
    baseline = value
    local key = attribute == "LastWork" and "work" or attribute == "LastDelivery" and "delivery" or "attack"
    session[key] += 1
    if key == "work" then session.worker=model elseif key == "attack" then session.attacker=model end
    local live=Players.LocalPlayer.PlayerScripts.RTSAudioProbe:Invoke()
    if not live.enabled then session.mutedPulses += 1 end
    print(string.format("[FEEDBACK_MULTI PULSE] viewer=%d owner=%d kind=%s attribute=%s value=%.6f audioEnabled=%s",
     Players.LocalPlayer.UserId,ownerId,tostring(model:GetAttribute("UnitType")),attribute,value,tostring(live.enabled)))
    Focus.Request(Players.LocalPlayer,model:GetPivot().Position)
   end))
  end
 end
 function session.close()
  for _,connection in ipairs(session.connections) do connection:Disconnect() end
 end
 return session
end

-- 非房主先執行。兩端日誌中的 owner/kind/attribute/value 可逐個比較真正複製的時間戳記。
function Tests.RunPeer(options)
 if options ~= nil then
  assert(type(options) == "table" and (options.onArmed == nil or type(options.onArmed) == "function"),
   "[FEEDBACK_MULTI FAIL] RunPeer 選項與 onArmed 必須是有效型別")
 end
 local player,actor,probe,command = context()
 check(workspace:GetAttribute("HostUserId") ~= player.UserId, "觀察端是非房主真實客戶端")
 local oldSound,oldMotion = player:GetAttribute("SoundEnabled"),player:GetAttribute("ReducedMotion")
 local actorSoundBefore = actor:GetAttribute("SoundEnabled")
 player:SetAttribute("SoundEnabled",true)
 player:SetAttribute("ReducedMotion",true)
 local rests = {}
 for _,worker in ipairs(owned(workspace.Units,actor.UserId,"villager")) do
  waitFor(function() return worker.PrimaryPart ~= nil end,3,"另一端村民根零件完整複製")
 end
 task.wait(.15)
 for _,worker in ipairs(owned(workspace.Units,actor.UserId,"villager")) do rests[worker]=offsets(worker) end
 player:SetAttribute("ReducedMotion",false)
 local session = monitor(actor.UserId)
 local ok,result = xpcall(function()
  -- 初始斥候本來會自動保護基地；正常指令將其移開，避免音效觀察被另一場近戰打斷。
  -- 只安排測試中的對戰雙方，不改寫位置、HP、索敵規則或跨圖進攻路徑。
  local defender=owned(workspace.Units,player.UserId,"scout")[1]
  local actorScout=owned(workspace.Units,actor.UserId,"scout")[1]
  local defendingBase=owned(workspace.Buildings,player.UserId,"TownCenter")[1]
  local home=player:GetAttribute("HomePosition")
  check(defender and actorScout and defendingBase and typeof(home)=="Vector3" and home.Z~=0,
   "正常雙人開局有斥候、基地與有效 HomePosition")
  local destination=Vector3.new(home.X,0,home.Z-math.sign(home.Z)*120)
  local startPoint=actorScout:GetPivot().Position
  local targetPoint=defendingBase:GetPivot().Position
  local half=defendingBase.PrimaryPart.Size/2
  local edge=Vector3.new(math.clamp(startPoint.X,targetPoint.X-half.X,targetPoint.X+half.X),0,
   math.clamp(startPoint.Z,targetPoint.Z-half.Z,targetPoint.Z+half.Z))
  local outward=Vector3.new(startPoint.X-edge.X,0,startPoint.Z-edge.Z).Unit
  local attackPoint=edge+outward*math.max(1,require(RS.GameData.GameConfig).Units.scout.range-1)
  local approach=Vector3.new(edge.X-startPoint.X,0,edge.Z-startPoint.Z)
  check(approach.Magnitude>0,"原進攻斥候到敵方基地的平面方向有效")
  command:FireServer("Order",{defender},destination)
  waitFor(function()
   local p=defender:GetPivot().Position
   return Vector3.new(p.X-destination.X,0,p.Z-destination.Z).Magnitude<=4
    and defender:GetAttribute("Order")=="待命" and defender:GetAttribute("Animation")=="Idle"
  end,40,"第二端斥候依正常移動指令抵達基地側方並待命")
  local p=defender:GetPivot().Position
  local relative=Vector3.new(p.X-startPoint.X,0,p.Z-startPoint.Z)
  local lineDistance=math.abs(relative.X*approach.Z-relative.Z*approach.X)/approach.Magnitude
  local attackDistance=Vector3.new(p.X-attackPoint.X,0,p.Z-attackPoint.Z).Magnitude
  check(lineDistance>80,"正常待命斥候距原進攻平面線大於 80 studs："..string.format("%.3f",lineDistance))
  check(attackDistance>72,"正常待命斥候離基地近戰位置超過自動索敵半徑："..string.format("%.3f",attackDistance))
  diagnostics(player,actor,defender,defendingBase,"正常指令移開防守初始斥候後的真實模型",nil)
  -- 僅通知明確測試包裝器本端的實際觀察器已完成；不建立任何遊戲事件或伺服器權限。
  -- 預設手動呼叫流程沒有 callback；包裝器需使用非阻塞通知。
  if options and options.onArmed then options.onArmed() end
  print("[FEEDBACK_MULTI PEER ARMED] 現在在房主客戶端執行 RunActor。")
  waitFor(function() return session.work >= 2 and session.worker end,100,"第二端收到房主村民的真實採集脈衝")
  local worker = session.worker
  waitFor(function() return audible(worker) end,3,"第二端正式相機聚焦同一採集村民")
  local cue = workNames[worker:GetAttribute("WorkKind")]
  check(cue ~= nil,"第二端收到正常採集 WorkKind")
  waitFor(function() return soundLoaded(worker,cue) end,5,"第二端正式音效腳本播放已載入的同來源採集聲音")
  check(next(rests[worker]) ~= nil,"第二端使用含工具的 fallback 村民外觀")
  waitFor(function() return poseChanged(worker,rests[worker]) end,3,"第二端同一村民出現本機工具動作")
  waitFor(function() return session.delivery >= 1 end,60,"第二端收到房主正常交貨 LastDelivery")
  waitFor(function() return session.attack >= 2 and session.attacker end,100,"第二端收到房主斥候真實 LastAttack")
  local attacker = session.attacker
  waitFor(function() return audible(attacker) end,3,"第二端正式相機可看見同一攻擊來源")
  waitFor(function() return soundLoaded(attacker,"Melee") end,5,"第二端正式音效腳本播放已載入的同來源近戰聲音")
  local beforeAttack = session.attack
  player:SetAttribute("SoundEnabled",false)
  waitFor(function()
   local s=probe:Invoke(); return s.enabled == false and s.active == 0 and s.world == 0
  end,2,"第二端本機靜音立即清空實際播放池")
  local beforePlayed = probe:Invoke().played
  print(string.format("[FEEDBACK_MULTI MUTED] viewer=%d afterAttack=%d",player.UserId,beforeAttack))
  waitFor(function() return session.attack >= beforeAttack+3 end,10,"靜音期間仍收到至少三次伺服器攻擊脈衝")
  check(probe:Invoke().played == beforePlayed and not soundLoaded(attacker,"Melee"),"靜音期間不播放新的世界音效")
  check(actor:GetAttribute("SoundEnabled") == actorSoundBefore,"第二端本機靜音沒有改寫另一玩家實例的設定")
  player:SetAttribute("SoundEnabled",true)
  waitFor(function() return probe:Invoke().enabled == true and soundLoaded(attacker,"Melee") end,5,
   "第二端解除靜音後由下一次真正攻擊恢復聲音")
  print(string.format("[FEEDBACK_MULTI PEER COMPLETE] work=%d delivery=%d attack=%d；同來源採集、工具動作、交貨、近戰與本機靜音",session.work,session.delivery,session.attack))
  return true
 end,debug.traceback)
 session.close()
 player:SetAttribute("SoundEnabled",oldSound)
 player:SetAttribute("ReducedMotion",oldMotion)
 if not ok then error(result,0) end
 return result
end

-- 房主後執行。只命令既有村民採集和斥候攻擊另一方市鎮中心；不殺光玩家、不授予資源。
function Tests.RunActor()
 local player,peer,probe,command = context()
 check(workspace:GetAttribute("HostUserId") == player.UserId,"動作端是房主真實客戶端")
 local oldSound,oldMotion = player:GetAttribute("SoundEnabled"),player:GetAttribute("ReducedMotion")
 player:SetAttribute("SoundEnabled",true)
 player:SetAttribute("ReducedMotion",false)
 local workers = owned(workspace.Units,player.UserId,"villager")
 local scout = owned(workspace.Units,player.UserId,"scout")[1]
 local target = owned(workspace.Buildings,peer.UserId,"TownCenter")[1]
 check(#workers >= 3 and scout and target,"正常開局村民、斥候與敵方市鎮中心存在")
 local session = monitor(player.UserId)
 local worker,node,nearest = nil,nil,math.huge
 local ok,result = xpcall(function()
  command:FireServer("Stop",workers)
  waitFor(function()
   for _,unit in ipairs(workers) do if unit:GetAttribute("Animation") ~= "Idle" then return false end end
   return true
  end,5,"房主停止村民，由正常指令建立採集基準")
  for _,candidate in ipairs(workspace.Resources:GetChildren()) do
   if candidate:IsA("Model") and candidate.PrimaryPart and candidate:GetAttribute("RTSManagedResource") == true and
    (candidate:GetAttribute("Amount") or 0) >= 60 then
    for _,unit in ipairs(workers) do
     local d=(candidate:GetPivot().Position-unit:GetPivot().Position).Magnitude
     if d < nearest then worker,node,nearest=unit,candidate,d end
    end
   end
  end
  check(worker and node,"房主使用正常地圖的鄰近資源")
  local key,amount = node:GetAttribute("ResourceType"),node:GetAttribute("Amount")
  local balance = player:GetAttribute(key)
  command:FireServer("Order",{worker},node)
  waitFor(function() return session.work >= 2 and node:GetAttribute("Amount") < amount end,40,"房主真實採集改變資源並發布 LastWork")
  Focus.Request(player,worker:GetPivot().Position)
  waitFor(function() return audible(worker) and soundLoaded(worker,workNames[key]) end,5,"房主正式腳本播放與第二端相同來源的採集聲音")
  waitFor(function() return session.delivery >= 1 and player:GetAttribute(key) > balance end,60,"房主實際交貨增加庫存並發布 LastDelivery")
  command:FireServer("Stop",workers)
  waitFor(function() return worker:GetAttribute("Animation") == "Idle" end,5,"交貨後正常停止採集避免影響近戰相機觀察")
  local hp=target:GetAttribute("HP")
  command:FireServer("Order",{scout},target)
  local attackStarted,nextDiagnostic=os.clock(),0
  waitFor(function()
   local now=os.clock()
   if now>=nextDiagnostic then
    diagnostics(player,peer,scout,target,"正常近戰等待中的真實模型",now-attackStarted)
    nextDiagnostic=now+10
   end
   return session.attack >= 2 and target:GetAttribute("HP") < hp
  end,100,"房主斥候正常移動至敵方並由伺服器造成傷害")
  waitFor(function() return audible(scout) and soundLoaded(scout,"Melee") end,5,"房主正式腳本播放實際近戰音效")
  waitFor(function() return session.attack >= 11 end,18,"持續真正攻擊，給另一端完成本機靜音及恢復觀察")
  check(session.mutedPulses == 0 and probe:Invoke().enabled == true and player:GetAttribute("SoundEnabled") == true,
   "另一端靜音期間房主每個真實工作／攻擊脈衝的播放池始終保持開啟")
  local home=player:GetAttribute("HomePosition")
  check(typeof(home)=="Vector3" and home.Z~=0,"近戰結束有有效的己方 HomePosition")
  local retreat=Vector3.new(home.X,0,home.Z-math.sign(home.Z)*96)
  command:FireServer("Order",{scout},retreat)
  waitFor(function()
   local p=scout:GetPivot().Position
   return Vector3.new(p.X-retreat.X,0,p.Z-retreat.Z).Magnitude<=4
    and scout:GetAttribute("Order")=="待命" and scout:GetAttribute("Animation")=="Idle"
  end,60,"近戰驗證後以正常移動指令撤回己方並待命，避免在敵方基地自動重新索敵")
  diagnostics(player,peer,scout,target,"正常撤回己方後的真實模型",nil)
  print(string.format("[FEEDBACK_MULTI ACTOR COMPLETE] work=%d delivery=%d attack=%d；正常採集、交貨與敵方損傷",session.work,session.delivery,session.attack))
  return true
 end,debug.traceback)
 if not ok then diagnostics(player,peer,scout,target,"失敗後清理指令前的真實模型",nil) end
 command:FireServer("Stop",workers)
 if scout then command:FireServer("Stop",{scout}) end
 session.close()
 player:SetAttribute("SoundEnabled",oldSound)
 player:SetAttribute("ReducedMotion",oldMotion)
 if not ok then error(result,0) end
 return result
end

-- 存留的非房主呼叫後立即返回。需實際關閉另一名玩家，不能用停止全部測試模擬退出。
function Tests.ObserveCleanupClient()
 local player,victim,probe = context()
 local sources={}
 for _,folder in ipairs({workspace.Units,workspace.Buildings}) do
  for _,source in ipairs(owned(folder,victim.UserId)) do table.insert(sources,source) end
 end
 check(#sources > 0,"退出前另一名玩家的實際回饋來源存在")
 local connection
 connection=Players.PlayerRemoving:Connect(function(leaving)
  if leaving ~= victim then return end
  connection:Disconnect()
  task.spawn(function()
   waitFor(function()
    for _,source in ipairs(sources) do if source.Parent ~= nil then return false end end
    return workspace:GetAttribute("MatchPhase") == "Ended"
   end,10,"實際玩家退出後刪除其單位、建築與下層空間音效來源")
   waitFor(function()
    local s=probe:Invoke()
    local effects=workspace:FindFirstChild("RTSClientEffects")
    return s.active == 0 and s.world == 0 and effects and #effects:GetChildren() == 0
   end,3,"退出後實際播放池及本機暫時效果全部清空")
   check(workspace:GetAttribute("WinnerId") == player.UserId and workspace:GetAttribute("HostUserId") == player.UserId,
    "另一玩家真正退出後勝利與房主轉移同步")
   print(string.format("[FEEDBACK_MULTI CLEANUP COMPLETE] %d 個離開玩家來源與本機播放／效果完成清理",#sources))
  end)
 end)
 print("[FEEDBACK_MULTI CLEANUP ARMED] 請只關閉另一個實際玩家客戶端，UserId=" .. tostring(victim.UserId))
 return connection
end
return Tests
