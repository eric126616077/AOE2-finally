-- 僅映射於 battle-validation.project.json；正式專案不會自動執行。
-- Studio SERVER：透過 GameServer 的 Studio 專用 RTSBattleProbe 直接生成雙方部隊（不經訓練、不扣資源、
-- 不受人口上限），讓正式的索敵／移動／攻擊邏輯自行交戰，記錄伺服器每步耗時、Heartbeat 節奏與交戰狀態。
-- 這是 Studio 單機 Play 的量測，不是正式伺服器或真手機的效能驗收。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local Stats=game:GetService("Stats")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local Observer=require(RS:WaitForChild("Shared"):WaitForChild("PerformanceObserver"))
-- 固定地圖種子：優化前後在同一片戰場比較（必須在開局生成地圖前設定）。
Config.Map.RandomizeSeed=false
local SPACING,FRONT_GAP,MAX_ROWS=6.5,40,18
local SCENARIOS={
 {name="50v50",perSide=50,seconds=75},
 {name="100v100",perSide=100,seconds=90,siege=4},
 {name="200v200",perSide=200,seconds=100,siege=6},
 {name="march100v100",perSide=100,seconds=100,march=260},
}
-- 前排近戰、後排遠程；每十人：步兵 4、弓箭手 3、長槍兵 1、騎士 1、矛兵 1。
local MELEE={"infantry","infantry","cavalry","infantry","spearman","infantry"}
local RANGED={"archer","archer","skirmisher","archer"}

local function round(value,digits)
 if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false end
 local scale=10^(digits or 2)
 return math.floor(value*scale+0.5)/scale
end
local function emit(kind,data)
 local ok,json=pcall(function() return Http:JSONEncode({kind=kind,data=data}) end)
 print("[BATTLE_STRESS] "..(ok and json or Http:JSONEncode({kind=kind,missing="encode failed"})))
end
local function milliseconds(entry)
 if type(entry)~="table" or (entry.count or 0)==0 then return {count=0} end
 return {count=entry.count,meanMs=round(entry.sum/entry.count*1000,3),worstMs=round(entry.worst*1000,3),totalMs=round(entry.sum*1000,1)}
end
local function frames(record)
 local summary=Observer.FrameSummary(record)
 return {count=summary.validFrames,meanMs=round(summary.meanDeltaMs,2),hz=round(summary.effectiveFPS,1),
  p95Ms=summary.p95UpperBoundMs,worstMs=round(summary.worstDeltaMs,1),
  below30=round(summary.below30Fraction,4),below15=round(summary.below15Fraction,4)}
end

local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
if not probe then emit("ABORT",{reason="RTSBattleProbe missing"}); return end
repeat task.wait(0.5) until workspace:GetAttribute("MatchPhase")=="Playing" and (workspace:GetAttribute("FactionCount") or 0)>=2
task.wait(4)
local player=Players:GetPlayers()[1]
local factions=RS:WaitForChild("RTSFactions")
local aiActor=factions:FindFirstChildWhichIsA("Folder")
if not player or not aiActor then emit("ABORT",{reason="need one human and one AI faction"}); return end
local sides={{id=player.UserId,name="human"},{id=aiActor:GetAttribute("OwnerId"),name="ai"}}
local home=player:GetAttribute("HomePosition")
local unitFolder=workspace:WaitForChild("Units")
local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2

local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Exclude
do
 local excluded={}
 local ground=workspace:FindFirstChild("AOE2_Ground")
 if ground then table.insert(excluded,ground) end
 overlap.FilterDescendantsInstances=excluded
end
local function blockers(center,size)
 local count=0
 for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(center),size,overlap)) do
  if part.CanCollide then count+=1 end
 end
 return count
end
-- 人類陣營排在靠主城的一側；挑選占地內障礙最少的中心，避免把部隊生在森林裡。
local inward=Vector3.new(home.X>0 and -1 or 1,0,home.Z>0 and -1 or 1)
local function pickCenter(spanX,spanZ)
 local best,bestCount=nil,math.huge
 local candidates={}
 for _,distance in ipairs({70,85,100,120,145,175}) do table.insert(candidates,home+inward*distance) end
 table.insert(candidates,Vector3.zero)
 for _,candidate in ipairs(candidates) do
  if math.abs(candidate.X)+spanX/2<half-12 and math.abs(candidate.Z)+spanZ/2<half-12 then
   local count=blockers(candidate+Vector3.new(0,4,0),Vector3.new(spanX,8,spanZ))
   if count<bestCount then best,bestCount=candidate,count end
  end
 end
 return best,bestCount
end

local function runScenario(scenario)
 if workspace:GetAttribute("MatchPhase")~="Playing" then emit("SKIP",{name=scenario.name,reason="match not playing"}); return false end
 local perSide=scenario.perSide
 local rows=math.min(MAX_ROWS,math.max(4,math.ceil(math.sqrt(perSide*1.5))))
 local columns=math.ceil(perSide/rows)
 local gap=scenario.march or FRONT_GAP
 local spanX=gap+(columns+3)*SPACING*2+30
 local spanZ=rows*SPACING+16
 local center,obstacles=pickCenter(spanX,spanZ)
 if not center then emit("SKIP",{name=scenario.name,reason="no in-bounds battlefield"}); return false end
 workspace:SetAttribute("BattleStressCenter",center)
 workspace:SetAttribute("BattleStressStage","spawn:"..scenario.name)
 local spawned,alive,sideOf,kindOf,attacked,lastAttack={},{},{},{},{},{}
 local intervals={}
 local connections={}
 local skipped,spawnSeconds=0,0
 local meleeCount=math.ceil(perSide*0.6)
 local function place(sideIndex,kind,position)
  local profile=Config.UnitCollision.profiles[Config.Units[kind].class] or Config.UnitCollision.default
  local size=Vector3.new(profile.radius*2+0.6,profile.height,profile.radius*2+0.6)
  if math.abs(position.X)+profile.radius>half-4 or math.abs(position.Z)+profile.radius>half-4
   or blockers(position+Vector3.new(0,profile.height/2+0.2,0),size)>0 then skipped+=1; return nil end
  local started=os.clock()
  local unit=probe:Invoke("spawn",sides[sideIndex].id,kind,position)
  spawnSeconds+=os.clock()-started
  if not unit then skipped+=1; return nil end
  table.insert(spawned,unit)
  alive[unit],sideOf[unit],kindOf[unit]=true,sideIndex,kind
  local data=Config.Units[kind]
  table.insert(connections,unit:GetAttributeChangedSignal("LastAttack"):Connect(function()
   local value=unit:GetAttribute("LastAttack")
   if type(value)~="number" then return end
   local previous=lastAttack[unit]
   lastAttack[unit],attacked[unit]=value,true
   local configured=unit:GetAttribute("AttackInterval") or data.attackInterval or 1
   if previous and value-previous<configured*2.5 then
    local entry=intervals[kind] or {count=0,sum=0,configured=configured}
    entry.count+=1; entry.sum+=value-previous
    intervals[kind]=entry
   end
  end))
  return unit
 end
 -- 人類陣營固定在靠主城的 X 側。
 local humanSign=home.X>center.X and 1 or -1
 local spawnStarted=os.clock()
 local batch=0
 for index=1,perSide do
  local melee=index<=meleeCount
  local kind=melee and MELEE[(index-1)%#MELEE+1] or RANGED[(index-meleeCount-1)%#RANGED+1]
  local column,row=math.floor((index-1)/rows),(index-1)%rows
  for sideIndex=1,2 do
   local sign=sideIndex==1 and humanSign or -humanSign
   place(sideIndex,kind,center+Vector3.new(sign*(gap/2+column*SPACING),0,(row-(rows-1)/2)*SPACING))
  end
  batch+=2
  if batch>=40 then batch=0; task.wait() end
 end
 for index=1,scenario.siege or 0 do
  for sideIndex=1,2 do
   local sign=sideIndex==1 and humanSign or -humanSign
   place(sideIndex,"mangonel",center+Vector3.new(sign*(gap/2+(columns+1.5)*SPACING+6),0,(index-((scenario.siege or 0)+1)/2)*14))
  end
 end
 local spawnWall=os.clock()-spawnStarted
 local counts={0,0}
 for unit in pairs(alive) do counts[sideOf[unit]]+=1 end
 if scenario.march then
  -- 兩軍相距超過自動索敵半徑：各自以「進攻目標」行軍到對方陣地，考驗大批尋路與行進中接戰。
  local targets={{},{}}
  for _,unit in ipairs(spawned) do table.insert(targets[3-sideOf[unit]],unit) end
  for index,unit in ipairs(spawned) do
   local list=targets[sideOf[unit]]
   if #list>0 then probe:Invoke("attack",unit,list[(index-1)%#list+1]) end
  end
 end
 probe:Invoke("timings")
 emit("SPAWNED",{name=scenario.name,requestedPerSide=perSide+(scenario.siege or 0),human=counts[1],ai=counts[2],skippedSlots=skipped,
  obstaclesInField=obstacles,center={round(center.X,0),round(center.Z,0)},spawnWallMs=round(spawnWall*1000,0),
  makeUnitMeanMs=round(spawnSeconds/math.max(1,#spawned)*1000,3)})
 workspace:SetAttribute("BattleStressStage","run:"..scenario.name)
 local heartbeat=Observer.NewFrames()
 local first=true
 local heartbeatConnection=Run.Heartbeat:Connect(function(delta)
  if first then first=false; return end
  Observer.AddFrame(heartbeat,delta)
 end)
 local started=os.clock()
 local firstKill,lastLine=nil,0
 local worst={blocked=0,standby=0}
 local standbySeconds=0
 local outcome="timeout"
 while os.clock()-started<scenario.seconds do
  task.wait(1)
  if workspace:GetAttribute("MatchPhase")~="Playing" then outcome="match ended"; break end
  local living={0,0}
  local attackAnimation,walking,blocked,standby=0,0,0,0
  for unit in pairs(alive) do
   if unit.Parent~=unitFolder then alive[unit]=nil
   else
    living[sideOf[unit]]+=1
    local order,animation=unit:GetAttribute("OrderKind"),unit:GetAttribute("Animation")
    if animation=="Attack" then attackAnimation+=1
    elseif animation=="Walk" then walking+=1
    elseif order=="attack" then blocked+=1
    else standby+=1 end
   end
  end
  local elapsed=os.clock()-started
  if not firstKill and living[1]+living[2]<counts[1]+counts[2] then firstKill=elapsed end
  if living[1]>0 and living[2]>0 then
   worst.blocked=math.max(worst.blocked,blocked)
   worst.standby=math.max(worst.standby,standby)
   standbySeconds+=standby
  end
  if elapsed-lastLine>=5 or living[1]==0 or living[2]==0 then
   lastLine=elapsed
   emit("SAMPLE",{name=scenario.name,t=round(elapsed,1),human=living[1],ai=living[2],attacking=attackAnimation,walking=walking,
    attackOrderNotActing=blocked,standby=standby})
  end
  if living[1]==0 or living[2]==0 then outcome=living[1]>0 and "human wins" or living[2]>0 and "ai wins" or "both dead"; break end
 end
 local elapsed=os.clock()-started
 heartbeatConnection:Disconnect()
 local timings=probe:Invoke("timings") or {}
 workspace:SetAttribute("BattleStressStage","end:"..scenario.name)
 local survivors,neverAttacked={0,0},{}
 local neverTotal=0
 for unit in pairs(alive) do
  if unit.Parent==unitFolder then
   survivors[sideOf[unit]]+=1
   if not attacked[unit] then neverAttacked[kindOf[unit]]=(neverAttacked[kindOf[unit]] or 0)+1; neverTotal+=1 end
  end
 end
 local intervalRatios={}
 for kind,entry in pairs(intervals) do
  intervalRatios[kind]={samples=entry.count,configured=round(entry.configured,2),actualMean=round(entry.sum/entry.count,3),
   ratio=round(entry.sum/entry.count/entry.configured,3)}
 end
 local memoryOK,memory=pcall(function() return Stats:GetTotalMemoryUsageMb() end)
 emit("RESULT",{name=scenario.name,outcome=outcome,seconds=round(elapsed,1),units={human=counts[1],ai=counts[2]},
  survivors={human=survivors[1],ai=survivors[2]},firstKillSeconds=round(firstKill,1),
  heartbeat=frames(heartbeat),order=milliseconds(timings.order),combat=milliseconds(timings.combat),step=milliseconds(timings.step),
  profile=timings.profile and {moveMs=round(timings.profile.move*1000,0),moves=timings.profile.moves,flankMs=round(timings.profile.flank*1000,0),flanks=timings.profile.flanks,
   pivotMs=round(timings.profile.pivot*1000,0),pivots=timings.profile.pivots,neighborMs=round(timings.profile.neighbor*1000,0),neighbors=timings.profile.neighbors} or false,
  ordersAtEnd=timings.orders,pathTasksAtEnd=timings.pathTasks,memoryMb=memoryOK and round(memory,0) or false})
 emit("LOGIC",{name=scenario.name,worstAttackOrderNotActing=worst.blocked,worstStandbyWhileEnemyAlive=worst.standby,
  standbyUnitSeconds=standbySeconds,survivorsNeverAttacked=neverAttacked,survivorsNeverAttackedTotal=neverTotal,attackIntervals=intervalRatios})
 for _,connection in ipairs(connections) do connection:Disconnect() end
 for _,unit in ipairs(spawned) do if unit.Parent==unitFolder then probe:Invoke("remove",unit) end end
 task.wait(4)
 return true
end

emit("START",{scenarios=#SCENARIOS,mapSize=half*2,home={round(home.X,0),round(home.Z,0)},
 note="Studio 單機 Play；直接生成部隊；不是正式伺服器／真機效能驗收"})
for _,scenario in ipairs(SCENARIOS) do
 local ok,message=pcall(runScenario,scenario)
 if not ok then emit("ERROR",{name=scenario.name,message=string.sub(tostring(message),1,300)}) end
 if workspace:GetAttribute("MatchPhase")~="Playing" then break end
end
workspace:SetAttribute("BattleStressStage","done")
emit("DONE",{phase=workspace:GetAttribute("MatchPhase")})
