-- Explicit Studio CLIENT integration tests. require() performs no actions.
-- Prepare/RunHost/RunPeer use normal player commands and original game timings.
-- No HP, resources, age, server positions or combat pulse attributes are written.
-- Local sound/reduced-motion preferences and camera focus are restored afterwards.
local Tests={running=false,session=nil}
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local Config=require(RS.GameData.GameConfig)
local Grid=require(RS.Shared.Grid)
local Focus=require(RS.Shared.CameraFocus)
local Rules=require(RS.Shared.FeedbackRules)
local armyKinds={"infantry","spearman","archer","skirmisher","scout","cavalry","ram","mangonel","trebuchet"}
local coverageKinds=table.clone(armyKinds)
table.insert(coverageKinds,"Tower"); table.insert(coverageKinds,"Castle")
local cues={infantry="Melee",spearman="Melee",archer="Ranged",skirmisher="Ranged",scout="Melee",cavalry="Melee",ram="Siege",mangonel="Siege",trebuchet="Siege",Tower="Ranged",Castle="Ranged"}
local effects={infantry="ImpactEffect",spearman="ImpactEffect",archer="ArrowEffect",skirmisher="JavelinEffect",scout="ImpactEffect",cavalry="ImpactEffect",ram="ImpactEffect",mangonel="StoneEffect",trebuchet="StoneEffect",Tower="ArrowEffect",Castle="ArrowEffect"}
local poseNames={infantry={"ArmR","Sword"},spearman={"ArmR","Spear","Spearhead"},archer={"ArmR","Bow"},skirmisher={"ArmR","Spear","Spearhead"},scout={"HorseLeg","ArmR"},cavalry={"HorseLeg","ArmR","Sword"},ram={"RamLog","RamHead"},mangonel={"CatapultArm","StoneBasket"},trebuchet={"TrebuchetArm","Counterweight","Sling"}}
local center=Vector3.new(0,0,0)
local towerPoint,castlePoint=Vector3.new(168,0,-144),Vector3.new(168,0,144)
local function client()
 assert(RunService:IsStudio() and RunService:IsClient(),"[FEEDBACK_BATTLE FAIL] 僅限 Studio Play 客戶端明確呼叫")
 return Players.LocalPlayer
end
local function owned(folder,id,kind)
 local values={}
 for _,model in ipairs(folder:GetChildren()) do
  if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id
   and (not kind or model:GetAttribute("UnitType")==kind or model:GetAttribute("BuildingType")==kind) then table.insert(values,model) end
 end
 table.sort(values,function(a,b) return a.Name<b.Name end)
 return values
end
local function flat(model) local p=model:GetPivot().Position; return Vector3.new(p.X,0,p.Z) end
local function nearby(folder,id,kind,point,radius)
 for _,model in ipairs(owned(folder,id,kind)) do if model.PrimaryPart and (flat(model)-point).Magnitude<=radius and (folder.Name~="Buildings" or model:GetAttribute("Complete")==true) then return model end end
end
local function context(options)
 options=options or {}; local duration=options.deadlineSeconds or 1200
 assert(type(duration)=="number" and duration==duration and duration>=120 and duration<=2400,"期限須為 120–2400 秒")
 local c={player=client(),deadline=os.clock()+duration,started=os.clock(),lastSend=0,lastProgress=0,checks=0,connections={}}
 c.command=RS:WaitForChild("RTSRemotes",10):WaitForChild("Command",10)
 function c.check(ok,message) assert(ok,"[FEEDBACK_BATTLE FAIL] "..message); c.checks+=1; print("[FEEDBACK_BATTLE PASS] "..message) end
 function c.send(action,...)
  local delay=.3-(os.clock()-c.lastSend); if delay>0 then task.wait(delay) end
  c.command:FireServer(action,...); c.lastSend=os.clock()
 end
 function c.wait(predicate,seconds,message,manage)
  local limit=math.min(c.deadline,os.clock()+seconds)
  repeat
   if predicate() then return end
   assert(workspace:GetAttribute("MatchPhase")=="Playing","[FEEDBACK_BATTLE FAIL] 測試局已結束："..message)
   if manage then manage() end
   if os.clock()-c.lastProgress>=30 then
    print(string.format("[FEEDBACK_BATTLE PROGRESS] %s；%s；Age %s；food %s wood %s gold %s stone %s；%.1f 秒",c.player.Name,message,tostring(c.player:GetAttribute("Age")),tostring(c.player:GetAttribute("food")),tostring(c.player:GetAttribute("wood")),tostring(c.player:GetAttribute("gold")),tostring(c.player:GetAttribute("stone")),os.clock()-c.started)); c.lastProgress=os.clock()
   end
   task.wait(.05)
  until os.clock()>=limit
  error("[FEEDBACK_BATTLE FAIL] "..message.."等待逾時；保留真實戰局",0)
 end
 function c.finish(label)
  print(string.format("[FEEDBACK_BATTLE COMPLETE] %s；%s；%d 項；%.1f 秒",c.player.Name,label,c.checks,os.clock()-c.started))
  return {checks=c.checks,elapsedSeconds=os.clock()-c.started,label=label}
 end
 function c.cleanup() for _,connection in ipairs(c.connections) do connection:Disconnect() end; table.clear(c.connections) end
 return c
end
local function placement(kind,anchor,firstRadius)
 local data=Config.Buildings[kind]; local g=Config.Map.GridSize
 local half=(workspace:GetAttribute("MatchSize") or Config.Map.MapSize)/2
 local params=OverlapParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
 local excluded={}; for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local object=workspace:FindFirstChild(name); if object then table.insert(excluded,object) end end
 params.FilterDescendantsInstances=excluded
 for radius=firstRadius or 0,(firstRadius or 0)+128,8 do
  for index=0,31 do
   local angle=index*math.pi/16
   local point=Grid.snap(anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
   if math.abs(point.X)+data.size.X*g/2<half-3 and math.abs(point.Z)+data.size.Y*g/2<half-3 then
    local clear=true
    for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(point+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*g-.2,math.max(4,data.height),data.size.Y*g-.2),params)) do
     if part.CanCollide or part:IsDescendantOf(workspace.Buildings) or part:IsDescendantOf(workspace.Resources) or part:IsDescendantOf(workspace.Units) then clear=false; break end
    end
    if clear then return point end
   end
  end
 end
 error("[FEEDBACK_BATTLE FAIL] 無合法施工位置："..kind,0)
end
local function develop(role,options)
 local c=context(options); local player=c.player
 local beginLimit=math.min(c.deadline,os.clock()+25)
 while workspace:GetAttribute("MatchPhase")~="Playing" or player.Character~=nil or typeof(player:GetAttribute("HomePosition"))~="Vector3" do
  assert(os.clock()<beginLimit and workspace:GetAttribute("MatchPhase")~="Ended","[FEEDBACK_BATTLE FAIL] 正常開局／角色移除等待逾時")
  task.wait(.05)
 end
 c.wait(function()
  local probe=player.PlayerScripts:FindFirstChild("RTSAudioProbe")
  local motion=player.PlayerScripts:FindFirstChild("UnitMotion")
  local camera=workspace.CurrentCamera
  return probe and probe:Invoke().preloadFinished and motion and motion:GetAttribute("RTSMotionReady")==true
   and camera and camera.CameraType==Enum.CameraType.Scriptable and workspace:FindFirstChild("RTSClientEffects")~=nil
 end,20,"等待正式音效、動作與 RTS 相機初始化")
 c.check(#Players:GetPlayers()==2 and workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("AICount")==0 and workspace:GetAttribute("TeamMode")=="FFA","兩名真人已由正常大廳開啟無 AI 的 FFA")
 c.check(not workspace.StreamingEnabled and player.Character==nil,"完整複製且 RTS 不依賴角色")
 local home=assert(player:GetAttribute("HomePosition")); local id=player.UserId
 local desired={food=350,wood=250,gold=150,stone=50}
 local assignments,busy={},{}; local paused,lastManage=false,0
 local function workers() return owned(workspace.Units,id,"villager") end
 local function building(kind)
  for _,model in ipairs(owned(workspace.Buildings,id,kind)) do if model:GetAttribute("Complete")==true then return model end end
 end
 local function resource(key,point)
  local best,distance
  for _,folder in ipairs({workspace.Resources,workspace.Buildings}) do
   for _,model in ipairs(folder:GetChildren()) do
    if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("ResourceType")==key and (model:GetAttribute("Amount") or 0)>0
     and (folder==workspace.Resources or model:GetAttribute("OwnerId")==id and model:GetAttribute("Complete")==true) then
     local d=(flat(model)-point).Magnitude; if not distance or d<distance then best,distance=model,d end
    end
   end
  end
  return best
 end
 local function manage()
  if paused or os.clock()-lastManage<3 then return end; lastManage=os.clock()
  local missing={}; for _,key in ipairs({"food","gold","wood","stone"}) do if (player:GetAttribute(key) or 0)<desired[key] then table.insert(missing,key) end end
  local groups={}; local index=0
  for _,worker in ipairs(workers()) do
   if not busy[worker] then
    index+=1
    local key=#missing>0 and missing[(index-1)%#missing+1] or "stop"
    if assignments[worker]~=key or worker:GetAttribute("Order")=="待命" and key~="stop" then
     assignments[worker]=key; groups[key]=groups[key] or {}; table.insert(groups[key],worker)
    end
   end
  end
  for key,selection in pairs(groups) do
   if key=="stop" then c.send("Stop",selection)
   else c.send("Order",selection,assert(resource(key,flat(selection[1])),"無剩餘正常資源："..key)) end
  end
 end
 local function pause()
  paused=true; c.send("Stop",workers())
  c.wait(function() for _,unit in ipairs(workers()) do if unit:GetAttribute("Order")~="待命" then return false end end; return true end,8,"正常停止經濟指令")
 end
 local function resume() paused=false; lastManage=0; table.clear(assignments) end
 local function afford(cost,label)
  for key,amount in pairs(cost) do desired[key]=math.max(desired[key],amount+50) end
  resume(); c.wait(function() for key,amount in pairs(cost) do if (player:GetAttribute(key) or 0)<amount then return false end end; return true end,600,"真實採集交貨補足 "..label,manage); pause()
 end
 local function build(kind,anchor,always)
  if not always and building(kind) then return building(kind) end
  local data=Config.Buildings[kind]; afford(data.cost,data.name)
  local before={}; for _,model in ipairs(owned(workspace.Buildings,id,kind)) do before[model]=true end
  local selection=workers(); assert(#selection>=2,"需至少兩名施工村民"); selection={selection[1],selection[2]}
  for _,unit in ipairs(selection) do busy[unit]=true end
  local point=placement(kind,anchor or home,anchor and 0 or 36)
  c.send("Build",kind,point,selection)
  local site
  c.wait(function() for _,model in ipairs(owned(workspace.Buildings,id,kind)) do if not before[model] and model.PrimaryPart then site=model; return true end end; return false end,8,data.name.."正式工地建立")
  c.check(site:GetAttribute("Complete")==false and site:GetAttribute("UnderConstruction")==true,data.name.."由正式 Build 建立工地")
  resume(); c.wait(function() return site.Parent==workspace.Buildings and site:GetAttribute("Complete")==true end,data.buildTime+(flat(selection[1])-point).Magnitude/10+120,data.name.."真實移動與施工完成",manage)
  c.send("Stop",selection); for _,unit in ipairs(selection) do busy[unit]=nil; assignments[unit]=nil end
  c.check(site:GetAttribute("ConstructionProgress")==1,data.name.."具有完整正式施工進度")
  return site
 end
 local function train(kind)
  local data=Config.Units[kind]; afford(data.cost,data.name)
  local producer=assert(building(data.trainsAt[1]),"缺少正式訓練建築")
  local before={}; for _,unit in ipairs(owned(workspace.Units,id,kind)) do before[unit]=true end
  local began=os.clock(); c.send("Train",producer,kind); local unit
  c.wait(function() return (producer:GetAttribute("QueueCount") or 0)>0 end,8,data.name.."正式入列")
  resume(); c.wait(function() for _,candidate in ipairs(owned(workspace.Units,id,kind)) do if not before[candidate] and candidate.PrimaryPart then unit=candidate; return true end end; return false end,data.trainTime+45,data.name.."正式生產",manage)
  c.check(os.clock()-began>=data.trainTime-1,data.name.."按原始訓練時間完成")
  return unit
 end
 local function advance(age)
  if player:GetAttribute("Age")>=age then return end
  local data=Config.Ages[age]; afford(data.cost,data.name); local tc=assert(building("TownCenter"))
  local began=os.clock(); c.send("AdvanceAge",tc)
  c.wait(function() return tc:GetAttribute("Research")==data.name end,8,data.name.."正式研究開始")
  resume(); c.wait(function() return player:GetAttribute("Age")==age and tc:GetAttribute("Research")==nil end,data.time+20,data.name.."原始升級時間",manage)
  c.check(os.clock()-began>=data.time-1,data.name.."由伺服器研究完成")
 end
 c.wait(function() return building("TownCenter") and #workers()>=3 end,10,"正式基地與村民")
 build("House",nil,true); build("House",nil,true); build("House",nil,true)
 build("Mill"); build("Barracks"); build("Farm",nil,true); build("Farm",nil,true)
 while #workers()<8 do train("villager") end
 build("MiningCamp"); build("LumberCamp")
 advance(2); build("ArcheryRange"); build("Stable")
 advance(3); build("SiegeWorkshop")
 local castle=build("Castle",role=="peer" and castlePoint or nil)
 desired.stone=role=="host" and 0 or 160
 if role=="host" then advance(4); desired.food=200; desired.gold=500; desired.wood=300 end
 local army={}
 if role=="host" then for _,kind in ipairs(armyKinds) do army[kind]=train(kind) end
 else build("Wall",center,true); build("Tower",towerPoint,true) end
 pause()
 -- A clear Castle footprint leaves room for the normal multi-unit formation.
 local session={role=role,army=army,home=home,parking=placement("Castle",home,64),castle=castle,checks=c.checks}
 Tests.session=session
 c.finish(role.." 正常發展與戰場準備")
 print("[FEEDBACK_BATTLE READY]",player.Name,role,"只使用正常 Build/Train/AdvanceAge/Order；未補資源或改寫戰損")
 return session
end
function Tests.Prepare(role,options)
 assert(role=="host" or role=="peer","role 必須為 host 或 peer")
 return develop(role,options)
end
local function restParts(model,names)
 local result={}; local root=assert(model.PrimaryPart)
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and not part.CanCollide and table.find(names or {},part.Name) then
   table.insert(result,{part=part,offset=root.CFrame:ToObjectSpace(part.CFrame)})
  end
 end
 return result
end
local function changed(parts,root)
 for _,entry in ipairs(parts) do
  if entry.part.Parent then
   local frame=root.CFrame:ToObjectSpace(entry.part.CFrame)
   if (frame.Position-entry.offset.Position).Magnitude>.015 or math.abs(frame.LookVector:Dot(entry.offset.LookVector)-1)>.001 then return true end
  end
 end
 return false
end
local function visible(model)
 local camera=workspace.CurrentCamera; if not camera or not model.PrimaryPart then return false end
 local point,onScreen=camera:WorldToViewportPoint(model.PrimaryPart.Position)
 return Rules.WorldAudible(onScreen,point.Z,(camera.CFrame.Position-model.PrimaryPart.Position).Magnitude)
end
local function settleFrames(c,label)
 local frames=0
 local connection=RunService.RenderStepped:Connect(function() frames+=1 end)
 local ok,err=pcall(function() c.wait(function() return frames>=3 end,3,label.."等待三個實際畫面更新") end)
 connection:Disconnect()
 if not ok then error(err,0) end
end
local function attackSample(c,attacker,target,label,mode,pulses)
 local player=c.player; local root=assert(attacker.PrimaryPart)
 local kind=attacker:GetAttribute("UnitType") or attacker:GetAttribute("BuildingType")
 local data=Config.Units[kind] or Config.Buildings[kind]
 local count,hits,sounds,effectCount,poseCount=0,0,0,0,0
 local previousAttack=attacker:GetAttribute("LastAttack"); local previousHP=target:GetAttribute("HP")
 player:SetAttribute("SoundEnabled",mode~="mute"); player:SetAttribute("ReducedMotion",true)
 Focus.Request(player,(flat(attacker)+flat(target))/2)
 c.wait(function() return visible(attacker) and visible(target) end,5,label.."相機確認真正可見與可聽")
 settleFrames(c,label)
 local parts=restParts(attacker,poseNames[kind])
 if poseNames[kind] then c.check(#parts>0,label.."具有可觀察的原始外觀動作部位") end
 player:SetAttribute("ReducedMotion",mode=="reduced")
 local bindings={}
 local function bind(signal,callback) local connection=signal:Connect(callback); table.insert(bindings,connection) end
 bind(attacker:GetAttributeChangedSignal("LastAttack"),function()
  local value=attacker:GetAttribute("LastAttack")
  if Rules.IsNewPulse(value,previousAttack) then count+=1; previousAttack=value end
 end)
 bind(target:GetAttributeChangedSignal("HP"),function()
  local hp=target:GetAttribute("HP"); if type(hp)=="number" and type(previousHP)=="number" and hp<previousHP then hits+=1 end; previousHP=hp
 end)
 bind(attacker.DescendantAdded,function(object)
  if object:IsA("Sound") and object.Name=="RTS_"..cues[kind] then
   task.defer(function() if object.Parent and object.IsLoaded and object.IsPlaying then sounds+=1 end end)
  end
 end)
 bind(workspace.RTSClientEffects.ChildAdded,function(object)
  if object.Name==effects[kind] then effectCount+=1 end
 end)
 bind(RunService.RenderStepped,function()
  if attacker.Parent and root.Parent and attacker:GetAttribute("Animation")=="Attack" and changed(parts,root) then poseCount+=1 end
 end)
 c.send("Order",{attacker},target)
 local ok,result=xpcall(function()
  c.wait(function() return count>=pulses and hits>=pulses end,(data.attackInterval or 2)*pulses+45,label.."新的 LastAttack 與真正敵方 HP 下降")
  if mode=="normal" then
   c.wait(function() return sounds>0 and effectCount>0 and (#parts==0 or poseCount>0) end,4,label.."實際聲音、效果與攻擊姿勢")
   c.check(sounds>0,label.."實際 Sound 已載入且播放")
   c.check(effectCount>0,label.."正式 UnitMotion 產生 "..effects[kind])
   if #parts>0 then c.check(poseCount>0,label.."原始外觀部分具有攻擊動作") end
  elseif mode=="mute" then
   local probe=assert(player.PlayerScripts:FindFirstChild("RTSAudioProbe")):Invoke()
   c.check(sounds==0 and probe.active==0 and probe.world==0,label.."靜音期間仍造成正常傷害且無活動音效")
  else
   c.check(effectCount==0 and poseCount==0,label.."減少動態期間仍造成正常傷害且無移動特效或揮動")
  end
  return {pulses=count,hits=hits,sounds=sounds,effects=effectCount,poseFrames=poseCount}
 end,debug.traceback)
 for _,connection in ipairs(bindings) do connection:Disconnect() end
 c.send("Stop",{attacker})
 if not ok then error(result,0) end
 return result
end
local function move(c,selection,point,label)
 c.send("Order",selection,point)
 local duration=20; local expected={}; local columns=math.ceil(math.sqrt(#selection))
 for index,unit in ipairs(selection) do
  local offset=Vector3.new(((index-1)%columns-(columns-1)/2)*4,0,math.floor((index-1)/columns)*4)
  local goal=point+offset; expected[unit]=goal
  duration=math.max(duration,(flat(unit)-goal).Magnitude/math.max(1,unit:GetAttribute("Speed") or 8)+90)
 end
 c.wait(function() for _,unit in ipairs(selection) do if unit.Parent~=workspace.Units or (flat(unit)-expected[unit]).Magnitude>5 or unit:GetAttribute("Order")~="待命" then return false end end; return true end,duration,label)
end
-- Short alternative for a real pre-existing army/target; does not develop them.
-- Run on its owner client while the other client calls ObserveUnit first.
function Tests.RunUnit(attacker,target,options)
 local c=context(options); local player=c.player
 c.check(typeof(attacker)=="Instance" and attacker:IsA("Model") and attacker.Parent==workspace.Units and attacker:GetAttribute("OwnerId")==player.UserId,"短測試只下令真正己方單位")
 c.check(typeof(target)=="Instance" and target:IsA("Model") and target:GetAttribute("OwnerId")~=player.UserId and (target:GetAttribute("HP") or 0)>0,"短測試靶具有真正敵方 HP")
 local savedSound,savedMotion=player:GetAttribute("SoundEnabled"),player:GetAttribute("ReducedMotion")
 local result={}; local ok,err=xpcall(function()
  local difference=flat(attacker)-flat(target)
  local away=difference.Magnitude>.1 and difference.Unit or Vector3.new(-1,0,0)
  local staging=placement("Wall",flat(target)+away*152,0)
  local walkParts=restParts(attacker,{"HorseLeg","Wheel","BootL","BootR"}); local walkChanged=false
  player:SetAttribute("ReducedMotion",false)
  local walking=RunService.RenderStepped:Connect(function()
   if attacker.PrimaryPart and attacker:GetAttribute("Animation")=="Walk" and visible(attacker) and changed(walkParts,attacker.PrimaryPart) then walkChanged=true end
  end)
  table.insert(c.connections,walking)
  Focus.Request(player,flat(attacker)); c.send("Order",{attacker},staging)
  c.wait(function() Focus.Request(player,flat(attacker)); return (flat(attacker)-staging).Magnitude<5 and attacker:GetAttribute("Order")=="待命" end,difference.Magnitude/math.max(1,attacker:GetAttribute("Speed") or 8)+90,"短測試以正常行軍走近敵方靶")
  walking:Disconnect()
  if #walkParts>0 then c.check(walkChanged,"短測試真實行軍的腿部或輪軸動作") end
  for _,mode in ipairs({"normal","mute","reduced"}) do result[mode]=attackSample(c,attacker,target,"短測試 "..attacker:GetAttribute("UnitType").." "..mode,mode,2) end
  player:SetAttribute("SoundEnabled",false); player:SetAttribute("ReducedMotion",true)
  c.wait(function() return player.PlayerScripts.RTSAudioProbe:Invoke().active==0 end,2,"短測試靜音清理全部活動聲音")
  c.finish("單一真實部隊正常／靜音／減少動態")
 end,debug.traceback)
 c.cleanup()
 player:SetAttribute("SoundEnabled",savedSound); player:SetAttribute("ReducedMotion",savedMotion)
 if not ok then error(err,0) end
 return result
end
-- Read-only battle observer: only local preferences/camera are changed.
function Tests.ObserveUnit(attacker,target,options)
 local c=context(options); local player=c.player
 c.check(typeof(attacker)=="Instance" and attacker:IsA("Model") and attacker:GetAttribute("RTSManaged")==true and attacker.PrimaryPart,"觀察的是正式伺服器管理單位")
 c.check(typeof(target)=="Instance" and target:IsA("Model") and (target:GetAttribute("HP") or 0)>0,"觀察靶具有真實 HP")
 local kind=attacker:GetAttribute("UnitType") or attacker:GetAttribute("BuildingType")
 local savedSound,savedMotion=player:GetAttribute("SoundEnabled"),player:GetAttribute("ReducedMotion")
 local parts
 local setupOK,setupError=xpcall(function()
  player:SetAttribute("SoundEnabled",true); player:SetAttribute("ReducedMotion",true)
  Focus.Request(player,(flat(attacker)+flat(target))/2); settleFrames(c,"第二端觀察 "..kind)
  parts=restParts(attacker,poseNames[kind])
  if poseNames[kind] then c.check(#parts>0,kind.."第二端具有可觀察的原始外觀動作部位") end
  player:SetAttribute("ReducedMotion",false)
 end,debug.traceback)
 if not setupOK then
  player:SetAttribute("SoundEnabled",savedSound); player:SetAttribute("ReducedMotion",savedMotion)
  error(setupError,0)
 end
 local count,hits,sounds,effectCount,poses=0,0,0,0,0
 local clock,hp=attacker:GetAttribute("LastAttack"),target:GetAttribute("HP"); local bindings={}; local lastFocus=0
 local function bind(signal,callback) table.insert(bindings,signal:Connect(callback)) end
 bind(attacker:GetAttributeChangedSignal("LastAttack"),function() local value=attacker:GetAttribute("LastAttack"); if Rules.IsNewPulse(value,clock) then count+=1; clock=value end end)
 bind(target:GetAttributeChangedSignal("HP"),function() local value=target:GetAttribute("HP"); if type(value)=="number" and value<hp then hits+=1 end; hp=value end)
 bind(attacker.DescendantAdded,function(object) if object:IsA("Sound") and object.Name=="RTS_"..cues[kind] then task.defer(function() if object.Parent and object.IsLoaded and object.IsPlaying then sounds+=1 end end) end end)
 bind(workspace.RTSClientEffects.ChildAdded,function(object) if object.Name==effects[kind] then effectCount+=1 end end)
 bind(RunService.RenderStepped,function()
  if attacker.PrimaryPart and attacker.Parent then
   if attacker:GetAttribute("Animation")=="Attack" and changed(parts,attacker.PrimaryPart) then poses+=1 end
   if os.clock()-lastFocus>.2 then Focus.Request(player,(flat(attacker)+flat(target))/2); lastFocus=os.clock() end
  end
 end)
 local ok,err=xpcall(function()
  c.wait(function() return count>=2 and hits>=2 and sounds>0 and effectCount>0 and (#parts==0 or poses>0) end,120,"另一真人客戶端真正 LastAttack、傷害、聲音、效果與姿勢")
  c.check(count>=2 and hits>=2,kind.."第二端真實攻擊與傷害同步")
  c.check(sounds>0 and effectCount>0,kind.."第二端有已載入播放的 Sound 與正式特效")
  if #parts>0 then c.check(poses>0,kind.."第二端實際外觀攻擊動作") end
  c.finish("另一真人客戶端單一部隊回饋")
 end,debug.traceback)
 for _,connection in ipairs(bindings) do connection:Disconnect() end
 player:SetAttribute("SoundEnabled",savedSound); player:SetAttribute("ReducedMotion",savedMotion)
 if not ok then error(err,0) end
 return {pulses=count,hits=hits,sounds=sounds,effects=effectCount,poseFrames=poses}
end
function Tests.RunHost(options)
 options=options or {}; local session=options.prepared and assert(Tests.session,"先 Prepare(host)") or develop("host",options)
 local c=context(options); local player=c.player; local other
 for _,actor in ipairs(Players:GetPlayers()) do if actor~=player then other=actor end end
 c.check(other and other:GetAttribute("TeamId")~=player:GetAttribute("TeamId"),"第二真人是敵對參戰者")
 local wall,tower,castle
 c.wait(function()
  wall=nearby(workspace.Buildings,other.UserId,"Wall",center,128)
  tower=nearby(workspace.Buildings,other.UserId,"Tower",towerPoint,128)
  castle=nearby(workspace.Buildings,other.UserId,"Castle",castlePoint,128)
  return wall and tower and castle
 end,900,"第二端正常施工完成中央石牆、瞭望塔與城堡")
 local savedSound,savedMotion=player:GetAttribute("SoundEnabled"),player:GetAttribute("ReducedMotion")
 local samples={}
 local ok,result=xpcall(function()
  move(c,owned(workspace.Units,player.UserId),session.parking,"先將己方所有單位撤至遠離戰場的基地")
  for _,kind in ipairs(armyKinds) do
   local unit=assert(session.army[kind]); local targetPoint=flat(wall)
   local staging=placement("Wall",targetPoint+Vector3.new(-152,0,0),0)
   player:SetAttribute("ReducedMotion",true); Focus.Request(player,flat(unit)); settleFrames(c,kind.."行軍前姿勢")
   local walkParts=restParts(unit,{"Wheel","HorseLeg","BootL","BootR"}); local walkChanged=false
   player:SetAttribute("ReducedMotion",false)
   local walk=RunService.RenderStepped:Connect(function()
    if unit.PrimaryPart and unit:GetAttribute("Animation")=="Walk" and visible(unit) and changed(walkParts,unit.PrimaryPart) then walkChanged=true end
   end)
   table.insert(c.connections,walk)
   c.send("Order",{unit},staging)
   c.wait(function()
    Focus.Request(player,flat(unit))
    return (flat(unit)-staging).Magnitude<5 and unit:GetAttribute("Order")=="待命"
   end,(flat(unit)-staging).Magnitude/math.max(1,unit:GetAttribute("Speed") or 8)+100,kind.."正常行軍到中央")
   walk:Disconnect()
   if #walkParts>0 then c.check(walkChanged,kind.."真實行軍具有腿部或輪軸轉動") end
   samples[kind]={normal=attackSample(c,unit,wall,kind.." 正常攻擊","normal",2)}
   if kind=="trebuchet" then
    samples[kind].mute=attackSample(c,unit,wall,kind.." 靜音攻擊","mute",2)
    samples[kind].reduced=attackSample(c,unit,wall,kind.." 減少動態攻擊","reduced",2)
   end
   move(c,{unit},session.parking,kind.."正常撤回，避免干擾下一類")
  end
  -- Buildings genuinely shoot a durable ram; damage is measured on the real ram.
  local ram=session.army.ram
  for _,defense in ipairs({tower,castle}) do
   local kind=defense:GetAttribute("BuildingType")
   player:SetAttribute("SoundEnabled",true); player:SetAttribute("ReducedMotion",false)
   Focus.Request(player,flat(defense)); local shots,sounds,arrows,hits=0,0,0,0
   local clock=defense:GetAttribute("LastAttack"); local hp=ram:GetAttribute("HP"); local bindings={}
   local function bind(signal,callback) local connection=signal:Connect(callback); table.insert(bindings,connection); table.insert(c.connections,connection) end
   bind(defense:GetAttributeChangedSignal("LastAttack"),function() local value=defense:GetAttribute("LastAttack"); if Rules.IsNewPulse(value,clock) then shots+=1; clock=value end end)
   bind(defense.DescendantAdded,function(object) if object:IsA("Sound") and object.Name=="RTS_Ranged" then task.defer(function() if object.Parent and object.IsLoaded and object.IsPlaying then sounds+=1 end end) end end)
   bind(workspace.RTSClientEffects.ChildAdded,function(object) if object.Name=="ArrowEffect" then arrows+=1 end end)
   bind(ram:GetAttributeChangedSignal("HP"),function() local value=ram:GetAttribute("HP"); if type(value)=="number" and value<hp then hits+=1 end; hp=value end)
   c.send("Order",{ram},defense)
   c.wait(function() return shots>=2 and hits>=2 and sounds>0 and arrows>0 end,(flat(ram)-flat(defense)).Magnitude/8+100,kind.."真正自動射擊、傷害與回饋")
   for _,connection in ipairs(bindings) do connection:Disconnect() end
   c.check(shots>=2 and hits>=2,kind.."實際 LastAttack 與衝車 HP 減少")
   c.check(sounds>0 and arrows>0,kind.."實際播放 Ranged 與 ArrowEffect")
   move(c,{ram},session.parking,kind.."射擊後衝車正常撤離")
  end
  player:SetAttribute("SoundEnabled",false); player:SetAttribute("ReducedMotion",true)
  c.wait(function() return #workspace.RTSClientEffects:GetChildren()==0 and player.PlayerScripts.RTSAudioProbe:Invoke().active==0 end,2,"停止並關閉回饋後暫存聲音與特效全部清理")
  c.check(wall.Parent==workspace.Buildings and other:GetAttribute("Defeated")==false and workspace:GetAttribute("MatchPhase")=="Playing","傷害樣本全部發生於真實對局，沒有投降或清場混淆")
  c.finish(#armyKinds.." 種單位＋兩種防禦建築的真實戰鬥／攻城回饋")
  return samples
 end,debug.traceback)
 c.cleanup()
 player:SetAttribute("SoundEnabled",savedSound); player:SetAttribute("ReducedMotion",savedMotion)
 if not ok then error(result,0) end
 return result
end
function Tests.ObservePeer(options)
 if options and options.onArmed~=nil then assert(type(options.onArmed)=="function","onArmed 必須為函式") end
 local c=context(options); local player=c.player; local host
 for _,actor in ipairs(Players:GetPlayers()) do if actor~=player then host=actor end end
 c.check(host and player:GetAttribute("TeamId")~=host:GetAttribute("TeamId"),"第二客戶端觀察真正敵方回饋")
 local savedSound,savedMotion=player:GetAttribute("SoundEnabled"),player:GetAttribute("ReducedMotion")
 player:SetAttribute("SoundEnabled",true); player:SetAttribute("ReducedMotion",false)
 local evidence,observers,hpObserved,pending={},{},{},{}; local bindings={}; local lastFocus=0
 local function bind(signal,callback) table.insert(bindings,signal:Connect(callback)) end
 local function watchDamage(model)
  if hpObserved[model] or not model:IsA("Model") or model:GetAttribute("RTSManaged")~=true then return end
  local relevant=model.Parent==workspace.Buildings and model:GetAttribute("OwnerId")==player.UserId
   or model.Parent==workspace.Units and model:GetAttribute("OwnerId")==host.UserId and model:GetAttribute("UnitType")=="ram"
  if not relevant then return end
  hpObserved[model]=true; local hp=model:GetAttribute("HP")
  bind(model:GetAttributeChangedSignal("HP"),function()
   local value=model:GetAttribute("HP"); local damaged=type(value)=="number" and type(hp)=="number" and value<hp; hp=value
   if not damaged then return end
   task.defer(function()
    for source,record in pairs(observers) do
     local target=source:GetAttribute("AttackPosition")
     if os.clock()-record.activeAt<1+Config.Combat.projectile.maxFlight and typeof(target)=="Vector3" and model.PrimaryPart
      and (Vector3.new(target.X,0,target.Z)-flat(model)).Magnitude<4 then record.hits+=1 end
    end
   end)
  end)
 end
 local track
 track=function(model)
  if not model:IsA("Model") then return end
  if not model.PrimaryPart or type(model:GetAttribute("OwnerId"))~="number" or not (model:GetAttribute("UnitType") or model:GetAttribute("BuildingType")) then
   if not pending[model] then
    pending[model]=true
    local function retry() task.defer(function() if model.Parent then track(model) end end) end
    bind(model:GetPropertyChangedSignal("PrimaryPart"),retry)
    for _,attribute in ipairs({"OwnerId","UnitType","BuildingType"}) do bind(model:GetAttributeChangedSignal(attribute),retry) end
   end
   return
  end
  watchDamage(model)
  local kind=model:GetAttribute("UnitType") or model:GetAttribute("BuildingType")
  if not cues[kind] or observers[model] then return end
  if model:GetAttribute("OwnerId")~=host.UserId and not (model:GetAttribute("OwnerId")==player.UserId and (kind=="Tower" or kind=="Castle")) then return end
  local record={kind=kind,pulses=0,sounds=0,effects=0,hits=0,poseFrames=0,clock=model:GetAttribute("LastAttack"),activeAt=-math.huge,parts=restParts(model,poseNames[kind])}
  observers[model]=record; evidence[kind]=record
  bind(model.DescendantAdded,function(object)
   if object:IsA("BasePart") and #record.parts==0 and model.PrimaryPart and (model:GetAttribute("Animation")=="Idle" or model:GetAttribute("Animation")==nil) then
    task.defer(function() if model.PrimaryPart and #record.parts==0 then record.parts=restParts(model,poseNames[kind]) end end)
   end
  end)
  bind(model:GetAttributeChangedSignal("LastAttack"),function()
   local value=model:GetAttribute("LastAttack")
   if Rules.IsNewPulse(value,record.clock) then record.pulses+=1; record.activeAt=os.clock(); record.clock=value end
  end)
  bind(model.DescendantAdded,function(object)
   if object:IsA("Sound") and object.Name=="RTS_"..cues[kind] then task.defer(function() if object.Parent and object.IsLoaded and object.IsPlaying then record.sounds+=1 end end) end
  end)
 end
 for _,folder in ipairs({workspace.Units,workspace.Buildings}) do for _,model in ipairs(folder:GetChildren()) do if model:IsA("Model") then track(model) end end; bind(folder.ChildAdded,track) end
 bind(workspace.RTSClientEffects.ChildAdded,function(object)
  for model,record in pairs(observers) do
   if record.pulses>0 and os.clock()-record.activeAt<.65 and object.Name==effects[record.kind] and model.PrimaryPart and visible(model) then record.effects+=1 end
  end
 end)
 bind(RunService.RenderStepped,function()
  local newest,newestTime
  for model,record in pairs(observers) do
   if model.PrimaryPart and model.Parent then
    if model:GetAttribute("Animation")=="Attack" and os.clock()-record.activeAt<.55 and changed(record.parts,model.PrimaryPart) then record.poseFrames+=1 end
    if model:GetAttribute("Order")=="移動" or model:GetAttribute("Animation")=="Attack" or os.clock()-record.activeAt<8 then
     local clock=record.activeAt; if not newestTime or clock>newestTime then newest,newestTime=model,clock end
    end
   end
  end
  if newest and os.clock()-lastFocus>.15 then
   local target=newest:GetAttribute("AttackPosition")
   Focus.Request(player,typeof(target)=="Vector3" and (flat(newest)+target)/2 or flat(newest)); lastFocus=os.clock()
  end
 end)
 local ok,result=xpcall(function()
  -- Explicit validation harnesses may acknowledge that every observer is bound.
  -- The default path performs no acknowledgement or extra gameplay action.
  if options and options.onArmed then options.onArmed() end
  c.wait(function()
   for _,kind in ipairs(coverageKinds) do
    local record=evidence[kind]; if not record or record.pulses<2 or record.sounds<1 or record.effects<1 or record.hits<1 or poseNames[kind] and (#record.parts==0 or record.poseFrames<1) then return false end
   end
   return true
  end,1200,"另一實際客戶端觀察 "..#armyKinds.." 種敵軍＋己方防禦的真實攻擊與回饋")
  for _,kind in ipairs(coverageKinds) do
   local record=evidence[kind]
   c.check(record.pulses>=2 and record.hits>0,kind.."第二端同步收到 LastAttack 與真實傷害")
   c.check(record.sounds>0 and record.effects>0,kind.."第二端實際播放聲音與生成效果")
   if #record.parts>0 then c.check(record.poseFrames>0,kind.."第二端有實際外觀攻擊姿勢") end
  end
  c.finish("第二個真實客戶端的 "..#armyKinds.." 種軍事單位與兩種防禦建築聲音及動作")
  return evidence
 end,debug.traceback)
 for _,connection in ipairs(bindings) do connection:Disconnect() end
 player:SetAttribute("SoundEnabled",savedSound); player:SetAttribute("ReducedMotion",savedMotion)
 if not ok then error(result,0) end
 return result
end
function Tests.RunPeer(options)
 Tests.Prepare("peer",options)
 return Tests.ObservePeer(options)
end
return Tests
