-- Explicit Studio CLIENT observer. Requiring this module changes nothing.
-- Call Run in a fresh Lobby, then start the match separately with normal UI/remotes.
-- Does not send commands, mutate instances, or infer kills from removed models.
local Tests={running=false}
local resources={"food","wood","gold","stone"}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function amount(value)
 return finite(value) and value>=0 and value or 0
end

-- Assess only explicitly requested observation scope; no unconditional overall PASS.
function Tests.Assess(snapshot,requirements)
 requirements=requirements or {}
 local missing={}
 if type(snapshot)~="table" or snapshot.freshBaseline~=true or type(snapshot.ai)~="table" or #snapshot.ai==0 then return false,{"fresh AI baseline"} end
 for _,state in ipairs(snapshot.ai) do
  local prefix="AI "..tostring(state.id)..": "
  local villagers=requirements.newVillagers or 1
  if amount(state.newVillagers)<villagers or amount(state.trainedVillagersDelta)<villagers then table.insert(missing,prefix.."new villager instances and training facts") end
  if amount(state.completedNewBuildings)<(requirements.newBuildings or 1) then table.insert(missing,prefix.."completed new building instances") end
  if amount(state.deliveredDelta)<(requirements.delivered or 10) then table.insert(missing,prefix.."real DeliveredResources") end
  if amount(state.newMilitary)<(requirements.newMilitary or 0) then table.insert(missing,prefix.."new military instances") end
  for _,age in ipairs(requirements.ages or {1}) do
   if type(state.ages)~="table" or state.ages[age]~=true then table.insert(missing,prefix.."observed age "..tostring(age)) end
  end
  if requirements.combat==true and (amount(state.attacks)<1 or amount(state.correlatedHPDrops)<1) then table.insert(missing,prefix.."actual attack and matching enemy HP reduction") end
 end
 if requirements.ended==true and snapshot.phase~="Ended" then table.insert(missing,"real Ended phase") end
 if requirements.naturalResult==true and (snapshot.phase~="Ended" or snapshot.anyForfeit==true or snapshot.winnerTeamId==0) then table.insert(missing,"natural non-forfeit winner") end
 if requirements.winner=="AI" then
  local winnerIsAI=false
  for _,state in ipairs(snapshot.ai) do if finite(state.teamId) and state.teamId==snapshot.winnerTeamId then winnerIsAI=true end end
  if not winnerIsAI then table.insert(missing,"actual AI winner team") end
 end
 return #missing==0,missing
end

local function observe(options,connections)
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"[AI_OBSERVATION FAIL] 僅限 Studio Play 客戶端")
 options=options or {}
 local seconds=options.durationSeconds or 180
 assert(finite(seconds) and seconds>=30 and seconds<=1800,"[AI_OBSERVATION FAIL] 觀察時間須為 30–1800 秒")
 local expectedAI=options.aiCount or 1
 assert(type(expectedAI)=="number" and expectedAI%1==0 and expectedAI>=1 and expectedAI<=3,"[AI_OBSERVATION FAIL] AI 數須為 1–3")
 assert(workspace:GetAttribute("MatchPhase")=="Lobby","[AI_OBSERVATION FAIL] 須在 fresh Lobby 先啟動觀察，再正常開局")
 local Players,RS=game:GetService("Players"),game:GetService("ReplicatedStorage")
 local HttpService=game:GetService("HttpService")
 assert(#Players:GetPlayers()==1,"[AI_OBSERVATION FAIL] 此觀察器僅支援單一真人加 AI，不代替雙人同步驗收")
 local Config=require(RS.GameData.GameConfig)
 local player=Players.LocalPlayer
 local untilStart=os.clock()+60
 while workspace:GetAttribute("MatchPhase")~="Playing" do
  assert(os.clock()<untilStart,"[AI_OBSERVATION FAIL] 60 秒內未正常開局")
  task.wait(0.05)
 end
 local matchedAt,deadline=os.clock(),os.clock()+seconds
 local folders={units=workspace:WaitForChild("Units",5),buildings=workspace:WaitForChild("Buildings",5)}
 local factions=RS:WaitForChild("RTSFactions",5)
 assert(factions,"[AI_OBSERVATION FAIL] 缺少實際 AI 陣營")
 local actors,states={},{}
 local function models(folder,id,kind,key)
  local result={}
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("OwnerId")==id and (not kind or model:GetAttribute(key)==kind) then table.insert(result,model) end
  end
  return result
 end
 local function fresh()
  table.clear(actors)
  for _,actor in ipairs(factions:GetChildren()) do if actor:GetAttribute("IsAI")==true then table.insert(actors,actor) end end
  if #actors~=expectedAI then return false end
  for _,actor in ipairs(actors) do
   local id=actor:GetAttribute("UserId")
   if not finite(id) or actor:GetAttribute("Age")~=1 or actor:GetAttribute("DeliveredResources")~=0 or actor:GetAttribute("TrainedVillagers")~=0 or actor:GetAttribute("TrainedUnits")~=0
    or #models(folders.units,id,"villager","UnitType")~=Config.Settings.startingVillagers
    or #models(folders.units,id)~=Config.Settings.startingVillagers+(Config.Units.scout and 1 or 0)
    or #models(folders.buildings,id)~=1 then return false end
   local center=models(folders.buildings,id,"TownCenter","BuildingType")[1]
   if not center or center:GetAttribute("Complete")~=true then return false end
  end
  return true
 end
 local baselineUntil=math.min(deadline,matchedAt+5)
 repeat
  if fresh() then break end
  assert(os.clock()<baselineUntil,"[AI_OBSERVATION FAIL] 無法取得免費開局 baseline；不得把已生產的新模型重列為初始模型")
  task.wait(0.05)
 until false
 assert(not options.difficulty or workspace:GetAttribute("Difficulty")==options.difficulty,"[AI_OBSERVATION FAIL] 實際難度與預期不同")
 assert(not options.victory or workspace:GetAttribute("VictoryMode")==options.victory,"[AI_OBSERVATION FAIL] 實際勝利模式與預期不同")
 assert(workspace:GetAttribute("AICount")==expectedAI,"[AI_OBSERVATION FAIL] 對局 AI 數不符")
 local requirements=options.requirements or {newVillagers=1,newBuildings=1,delivered=10}
 for _,actor in ipairs(actors) do
  local id=actor:GetAttribute("UserId")
  local state={id=id,teamId=actor:GetAttribute("TeamId"),actor=actor,newVillagers=0,newMilitary=0,newBuildings=0,completedNewBuildings=0,
   trainedVillagersDelta=0,deliveredDelta=0,ages={[1]=true},attacks=0,correlatedHPDrops=0,removedModels=0,
   baselineVillagers=#models(folders.units,id,"villager","UnitType"),baselineUnits=#models(folders.units,id),baselineBuildings=#models(folders.buildings,id),baselineResources={}}
  for _,key in ipairs(resources) do state.baselineResources[key]=actor:GetAttribute(key) end
  states[id]=state
 end
 local records,pending,attackEvents,hpEvents={}, {}, {}, {}
 local eventCount,lastProgress,endedAt=0,matchedAt,nil
 local function printable(value)
  if typeof(value)=="Vector3" then return {x=value.X,y=value.Y,z=value.Z} end
  if type(value)=="table" then local copy={}; for key,item in pairs(value) do copy[key]=printable(item) end; return copy end
  return value
 end
 local function output(label,value) print(label.." "..HttpService:JSONEncode(printable(value))) end
 local function addConnection(signal,callback) table.insert(connections,signal:Connect(callback)) end
 local function point(model)
  if not model.PrimaryPart then return nil end
  local ok,value=pcall(model.GetPivot,model)
  return ok and value.Position or nil
 end
 local function samePoint(a,b)
  return typeof(a)=="Vector3" and typeof(b)=="Vector3" and (Vector2.new(a.X,a.Z)-Vector2.new(b.X,b.Z)).Magnitude<=0.2
 end
 local function log(kind,facts)
  eventCount+=1
  if eventCount<=100 or kind=="AGE" then output("[AI_OBSERVATION "..kind.."]",facts) end
 end
 local function identify(record)
  if record.identified then return end
  local model=record.model
  local id=model:GetAttribute("OwnerId")
  local kind=model:GetAttribute(record.folder==folders.units and "UnitType" or "BuildingType")
  if not finite(id) or type(kind)~="string" or not model.PrimaryPart then return end
  record.id,record.kind,record.identified=id,kind,true
  local state=states[id]
  if state and not record.baseline then
   if record.folder==folders.units then
    if kind=="villager" then state.newVillagers+=1 else state.newMilitary+=1 end
   else state.newBuildings+=1 end
   log("NEW",{ownerId=id,kind=kind,position=point(model),initial=false})
  end
 end
 local function completion(record)
  identify(record)
  local state=record.identified and states[record.id]
  if state and record.folder==folders.buildings and not record.baseline and not record.completed and record.model:GetAttribute("Complete")==true then
   record.completed=true; state.completedNewBuildings+=1
   log("COMPLETE_BUILDING",{ownerId=record.id,kind=record.kind,position=point(record.model)})
  end
 end
 local function attach(model,folder,baseline)
  if not model:IsA("Model") or records[model] then return end
  local record={model=model,folder=folder,baseline=baseline,hp=model:GetAttribute("HP"),lastAttack=model:GetAttribute("LastAttack")}
  records[model]=record; pending[model]=record
  identify(record); completion(record)
  addConnection(model:GetAttributeChangedSignal("Complete"),function() completion(record) end)
  addConnection(model:GetAttributeChangedSignal("HP"),function()
   identify(record)
   local nowHP=model:GetAttribute("HP")
   if record.identified and finite(record.hp) and finite(nowHP) and nowHP>=0 and nowHP<record.hp then
    local event={targetId=record.id,targetKind=record.kind,fromHP=record.hp,toHP=nowHP,amount=record.hp-nowHP,position=point(model),at=os.clock()}
    table.insert(hpEvents,event); if #hpEvents>128 then table.remove(hpEvents,1) end
    log("HP_DROP",event)
   end
   record.hp=nowHP
  end)
  addConnection(model:GetAttributeChangedSignal("LastAttack"),function()
   identify(record)
   local stamp=model:GetAttribute("LastAttack")
   local state=record.identified and states[record.id]
   if state and finite(stamp) and stamp~=record.lastAttack then
    state.attacks+=1
    local event={attackerId=record.id,attackerKind=record.kind,attackPosition=model:GetAttribute("AttackPosition"),stamp=stamp,at=os.clock()}
    table.insert(attackEvents,event); if #attackEvents>128 then table.remove(attackEvents,1) end
    log("ATTACK",event)
   end
   record.lastAttack=stamp
  end)
 end
 for _,folder in pairs(folders) do
  for _,model in ipairs(folder:GetChildren()) do attach(model,folder,true) end
  addConnection(folder.ChildAdded,function(model) attach(model,folder,false) end)
  addConnection(folder.ChildRemoved,function(model)
   local record=records[model]
   if record and record.identified and states[record.id] then states[record.id].removedModels+=1 end
   pending[model]=nil -- Removal can be defeat/cleanup; never recorded as a kill.
  end)
 end
 local function snapshot()
  local result={freshBaseline=true,elapsedSeconds=os.clock()-matchedAt,phase=workspace:GetAttribute("MatchPhase"),difficulty=workspace:GetAttribute("Difficulty"),
   victory=workspace:GetAttribute("VictoryMode"),teamMode=workspace:GetAttribute("TeamMode"),winnerTeamId=workspace:GetAttribute("WinnerTeamId") or 0,
   winnerId=workspace:GetAttribute("WinnerId") or 0,anyForfeit=player:GetAttribute("Forfeited")==true,ai={},eventCount=eventCount}
  for _,state in pairs(states) do
   state.trainedVillagersDelta=amount(state.actor:GetAttribute("TrainedVillagers"))
   state.deliveredDelta=amount(state.actor:GetAttribute("DeliveredResources"))
   local age=state.actor:GetAttribute("Age")
   if finite(age) and age%1==0 and age>=1 and age<=4 and not state.ages[age] then state.ages[age]=true; log("AGE",{ownerId=state.id,age=age,elapsedSeconds=result.elapsedSeconds}) end
   if state.actor:GetAttribute("Forfeited")==true then result.anyForfeit=true end
   local entry={}
   for key,value in pairs(state) do if key~="actor" then entry[key]=type(value)=="table" and table.clone(value) or value end end
   entry.defeated=state.actor:GetAttribute("Defeated")==true
   entry.currentAge=age; entry.resources={}
   for _,key in ipairs(resources) do entry.resources[key]=state.actor:GetAttribute(key) end
   table.insert(result.ai,entry)
  end
  table.sort(result.ai,function(a,b) return a.id<b.id end)
  return result
 end
 output("[AI_OBSERVATION BASELINE]",{snapshot=snapshot(),requirements=requirements})
 while true do
  for model,record in pairs(pending) do
   if model.Parent then identify(record); completion(record) end
   if record.identified or not model.Parent then pending[model]=nil end
  end
  for _,hp in ipairs(hpEvents) do
   if not hp.used and os.clock()-hp.at>=0.6 then
    local matching={}
    for _,attack in ipairs(attackEvents) do
     local state=states[attack.attackerId]
     local targetTeam
     for _,other in ipairs(Players:GetPlayers()) do if other.UserId==hp.targetId then targetTeam=other:GetAttribute("TeamId"); break end end
     if states[hp.targetId] then targetTeam=states[hp.targetId].teamId end
     if not attack.used and attack.attackerId~=hp.targetId and finite(state.teamId) and finite(targetTeam) and state.teamId~=targetTeam
      and math.abs(attack.at-hp.at)<=0.6 and samePoint(attack.attackPosition,hp.position) then table.insert(matching,attack) end
    end
    if #matching==1 then
     local attack=matching[1]; attack.used=true; states[attack.attackerId].correlatedHPDrops+=1
     log("ATTACK_TARGET_HP",{attackerId=attack.attackerId,targetId=hp.targetId,targetKind=hp.targetKind,fromHP=hp.fromHP,toHP=hp.toHP,amount=hp.amount,
      position=hp.position,correlation="唯一攻擊位置與複製時間配對；不證明精確 DPS 或全部擊殺"})
    end
    hp.used=true
   end
  end
  local result=snapshot()
  local met,missing=Tests.Assess(result,requirements)
  if met then output("[AI_OBSERVATION COMPLETE] 僅通過本次要求的範圍；未驗恢復或效能",{snapshot=result,requirements=requirements}); return result end
  if result.phase=="Ended" then endedAt=endedAt or os.clock() end
  if (result.phase~="Playing" and (result.phase~="Ended" or os.clock()-endedAt>=0.7)) or os.clock()>=deadline then
   output("[AI_OBSERVATION FINAL_UNMET]",{snapshot=result,missing=missing})
   error("[AI_OBSERVATION FAIL] 真實觀察未達要求；沒有更改對局："..table.concat(missing,"；"),0)
  end
  if os.clock()-lastProgress>=15 then output("[AI_OBSERVATION PROGRESS]",{snapshot=result,missing=missing}); lastProgress=os.clock() end
  task.wait(0.1)
 end
end

function Tests.Run(options)
 assert(not Tests.running,"[AI_OBSERVATION FAIL] 觀察器已在執行")
 Tests.running=true
 local connections={}
 local ok,result=xpcall(function() return observe(options,connections) end,debug.traceback)
 for _,connection in ipairs(connections) do connection:Disconnect() end
 Tests.running=false
 if not ok then warn("[AI_OBSERVATION FAIL] 保留真實對局；沒有發送停止、投降或重開"); error(result,0) end
 return result
end
return Tests
