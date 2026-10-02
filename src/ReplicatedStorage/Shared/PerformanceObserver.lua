-- Explicit, read-only Studio CLIENT observer. Requiring this module does nothing.
-- No remotes, game mutations, forced population, camera movement or performance PASS.
local Observer={running=false}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function integer(n) return finite(n) and n%1==0 end
local function clone(value)
 if type(value)~="table" then return value end
 local result={}; for key,item in pairs(value) do result[key]=clone(item) end; return result
end
function Observer.NewFrames() return {count=0,invalid=0,sum=0,worst=0,below30=0,below15=0,bins={}} end
function Observer.AddFrame(frames,delta)
 if not finite(delta) or delta<=0 or not finite(delta*1000) or not finite(frames.sum+delta) then frames.invalid+=1; return end
 frames.count+=1; frames.sum+=delta; frames.worst=math.max(frames.worst,delta)
 if delta>1/30 then frames.below30+=1 end; if delta>1/15 then frames.below15+=1 end
 local bin=math.min(2001,math.ceil(delta*2000)); frames.bins[bin]=(frames.bins[bin] or 0)+1
end
function Observer.FrameSummary(frames)
 local result={validFrames=frames.count,invalidFrames=frames.invalid,p95ResolutionMs=0.5,p95UpperBoundMs=false}
 if frames.count==0 then result.missing="沒有有效 RenderStepped delta"; return result end
 result.meanDeltaMs=frames.sum/frames.count*1000; result.effectiveFPS=frames.count/frames.sum
 result.worstDeltaMs=frames.worst*1000; result.worstInstantaneousFPS=1/frames.worst
 result.below30Fraction=frames.below30/frames.count; result.below15Fraction=frames.below15/frames.count
 local rank,count=math.ceil(frames.count*0.95),0
 for bin=1,2001 do count+=frames.bins[bin] or 0; if count>=rank then
  if bin<=2000 then result.p95UpperBoundMs=bin*0.5 else result.missing="p95 超過直方圖上界 1000ms；均值／最差仍包含卡頓" end
  break
 end end
 return result
end
function Observer.NumericSummary(values,missing)
 local valid,invalid={},0
 for _,value in ipairs(type(values)=="table" and values or {}) do if finite(value) then table.insert(valid,value) else invalid+=1 end end
 local result={samples=#valid,missingSamples=missing or 0,invalidInputs=invalid}
 if #valid==0 then result.missing="沒有有效樣本"; return result end
 local sorted,mean=table.clone(valid),0; table.sort(sorted)
 for index,value in ipairs(valid) do mean=mean*((index-1)/index)+value/index end
 result.mean=mean; result.p95=sorted[math.ceil(#valid*0.95)]; result.worst=sorted[#sorted]
 result.minimum=sorted[1]; result.first=valid[1]; result.last=valid[#valid]
 local difference=result.last-result.first
 if finite(difference) then result.lastMinusFirst=difference else result.differenceMissing="首尾差超出有限數值範圍" end
 return result
end
function Observer.IsRestart(endedGeneration,generation,phase,cleared)
 return integer(endedGeneration) and integer(generation) and endedGeneration~=generation and phase=="Lobby" and cleared==true
end
function Observer.IsFullLoad(configuration,actors)
 if type(configuration)~="table" or type(actors)~="table" then return false end
 if configuration.phase~="Playing" or configuration.size~="Large" or configuration.factions~=4 or configuration.populationLimit~=200 or #actors~=4 then return false end
 local seen={}
 for index=1,4 do
  local actor=actors[index]
  if type(actor)~="table" or not integer(actor.id) or seen[actor.id] or actor.active~=true or not integer(actor.units) or actor.units<200 then return false end
  seen[actor.id]=true
 end
 return true
end
function Observer.NewFocus()
 return {state="Unknown",since=0,eventCount=0,firstEventAt=false,durations={Unknown=0,Focused=0,Background=0}}
end
function Observer.FocusTransition(focus,nextState,atSeconds)
 if type(focus)~="table" or type(focus.durations)~="table" or (nextState~="Focused" and nextState~="Background")
  or not finite(atSeconds) or atSeconds<focus.since then return false end
 focus.durations[focus.state]+=atSeconds-focus.since
 focus.state,focus.since=nextState,atSeconds
 focus.eventCount+=1; focus.firstEventAt=focus.firstEventAt or atSeconds
 return true
end
function Observer.FocusCoverage(focus,atSeconds)
 local durations=clone(focus.durations)
 durations[focus.state]+=math.max(0,atSeconds-focus.since)
 local total=durations.Unknown+durations.Focused+durations.Background
 return {initialState="Unknown",currentState=focus.state,eventCount=focus.eventCount,firstEventAtSeconds=focus.firstEventAt,
  secondsByState=durations,knownTimeFraction=total>0 and (durations.Focused+durations.Background)/total or false,
  stateSource="UserInputService.WindowFocused/WindowFocusReleased；首個事件前未知",
  visibilityMeasured=false,throttlingCauseProven=false}
end

function Observer.Start(options)
 local run=game:GetService("RunService")
 assert(run:IsStudio() and run:IsClient(),"[PERF_OBSERVATION FAIL] 僅限 Studio CLIENT")
 assert(not Observer.running,"[PERF_OBSERVATION FAIL] 觀察器已在執行")
 options=options or {}
 local seconds,interval=options.seconds or 120,options.sampleInterval or 2
 local expectedRestarts,expectedLeaves=options.expectedRestarts or 0,options.expectedLeaves or 0
 assert(finite(seconds) and seconds>=30 and seconds<=1800,"採樣期限須為 30–1800 秒")
 assert(finite(interval) and interval>=2 and interval<=10,"頂層模型取樣間隔須為 2–10 秒")
 assert(integer(expectedRestarts) and expectedRestarts>=0 and expectedRestarts<=5,"重開觀察要求須為 0–5 次")
 assert(integer(expectedLeaves) and expectedLeaves>=0 and expectedLeaves<=4,"離開觀察要求須為 0–4 次")
 assert(options.context==nil or type(options.context)=="string" and #options.context<=500,"環境備註須為最多 500 bytes 的文字")
 local Players,RS,Stats,Http=game:GetService("Players"),game:GetService("ReplicatedStorage"),game:GetService("Stats"),game:GetService("HttpService")
 local UIS=game:GetService("UserInputService")
 local start,deadline=os.clock(),os.clock()+seconds
 local total,segments,rows,connections=Observer.NewFrames(),{},{},{}
 local metrics,leaves,restarts,seenPlaying={},{},{},{}
 local activeSegment,lastPhase,lastGeneration,pendingEnded,latest,finished,result
 local fullSamples,fullSince,longestFullSpan,lastLog,segmentOverflow=0,nil,0,0,0
 local fullGeneration,firstFullLoad
 local focus=Observer.NewFocus()
 local focusFrames={Unknown=Observer.NewFrames(),Focused=Observer.NewFrames(),Background=Observer.NewFrames()}
 local lastFocus,focusChangedSinceRender,focusBoundaryFrames=nil,false,0
 local reasons={}
 local function elapsed() return os.clock()-start end
 local function state() return workspace:GetAttribute("MatchPhase"),workspace:GetAttribute("MatchGeneration") end
 local function changed()
  local phase,generation=state()
  if phase==lastPhase and generation==lastGeneration and focus.state==lastFocus then return end
  if phase=="Playing" and integer(generation) then
   seenPlaying[generation]=true
   if pendingEnded and pendingEnded~=generation then reasons.missedResetBoundary=true; pendingEnded=nil end
  elseif phase=="Ended" and seenPlaying[generation] then pendingEnded=generation end
  lastPhase,lastGeneration,lastFocus=phase,generation,focus.state
  if #segments<64 then
   activeSegment={phase=type(phase)=="string" and phase or "Unknown",generation=generation or false,focus=focus.state,atSeconds=elapsed(),frames=Observer.NewFrames()}
   table.insert(segments,activeSegment)
  else segmentOverflow+=1; activeSegment=nil end
 end
 local function metric(row,name,reader,positive)
  local ok,value=pcall(reader)
  local series=metrics[name] or {values={},missing=0}; metrics[name]=series
  if ok and finite(value) and value>=0 and (not positive or value>0) then row.stats[name]=value; table.insert(series.values,value)
  else series.missing+=1; row.missing[name]=ok and "不可用或無效數值" or tostring(value); series.lastMissingReason=row.missing[name] end
 end
 local function collect()
  changed()
  if #rows>=902 then reasons.sampleLimitReached=true; return end
  local phase,generation=state()
  local row={atSeconds=elapsed(),generation=generation or false,phase=phase or "Unknown",focus=focus.state,stats={},missing={},actors={},owners={},managed={units=0,buildings=0,resources=0,unattributedUnits=0,unattributedBuildings=0},orders={}}
  row.configuration={phase=row.phase,size=workspace:GetAttribute("MatchSizeName") or false,factions=workspace:GetAttribute("FactionCount") or false,
   populationLimit=workspace:GetAttribute("PopulationLimit") or false,aiCount=workspace:GetAttribute("AICount") or false,teamMode=workspace:GetAttribute("TeamMode") or false}
  row.configuredFourBy200=row.configuration.factions==4 and row.configuration.populationLimit==200 and row.configuration.size=="Large" and phase=="Playing"
  local folders={units=workspace:FindFirstChild("Units"),buildings=workspace:FindFirstChild("Buildings"),resources=workspace:FindFirstChild("Resources")}
  for _,kind in ipairs({"units","buildings","resources"}) do
   local folder=folders[kind]
   if not folder then row.missing[kind.."Folder"]="尚未複製" else
    for _,model in ipairs(folder:GetChildren()) do
     local flag=kind=="resources" and "RTSManagedResource" or "RTSManaged"
     if model:IsA("Model") and model:GetAttribute(flag)==true then
      row.managed[kind]+=1
      if kind~="resources" then
       local id=model:GetAttribute("OwnerId")
       if not integer(id) then row.managed[kind=="units" and "unattributedUnits" or "unattributedBuildings"]+=1 else
        local key=tostring(id); local owner=row.owners[key] or {units=0,buildings=0,queue=0}; row.owners[key]=owner; owner[kind]+=1
        if kind=="buildings" then local count=model:GetAttribute("QueueCount"); if integer(count) and count>=0 then owner.queue+=count end
        else local order=model:GetAttribute("Order"); if type(order)=="string" then row.orders[order]=(row.orders[order] or 0)+1 end end
       end
      end
     end
    end
   end
  end
  local factions=RS:FindFirstChild("RTSFactions")
  local function actor(item,id,ai)
   if not integer(id) or item:GetAttribute("TeamId")==nil then return end
   local counts=row.owners[tostring(id)] or {units=0,buildings=0,queue=0}
   table.insert(row.actors,{id=id,ai=ai,active=item:GetAttribute("Defeated")==false and item:GetAttribute("Spectator")==false,
    units=counts.units,buildings=counts.buildings,queue=counts.queue,population=item:GetAttribute("Population") or false,populationCap=item:GetAttribute("PopulationCap") or false})
  end
  for _,player in ipairs(Players:GetPlayers()) do actor(player,player.UserId,false) end
  if factions then for _,item in ipairs(factions:GetChildren()) do if item:IsA("Folder") then actor(item,item:GetAttribute("OwnerId"),true) end end else row.missing.factionsFolder="尚未複製" end
  row.observedFourBy200=row.managed.unattributedUnits==0 and Observer.IsFullLoad(row.configuration,row.actors)
  if row.observedFourBy200 then
   fullSamples+=1
   if fullGeneration~=generation then fullSince=nil end
   fullGeneration=generation; fullSince=fullSince or row.atSeconds
   longestFullSpan=math.max(longestFullSpan,row.atSeconds-fullSince)
   firstFullLoad=firstFullLoad or {atSeconds=row.atSeconds,generation=row.generation,configuration=clone(row.configuration),actors=clone(row.actors),managed=clone(row.managed)}
  else fullSince,fullGeneration=nil,nil end
  metric(row,"totalMemoryMb",function() return Stats:GetTotalMemoryUsageMb() end,true)
  metric(row,"instanceCount",function() return Stats.InstanceCount end,true)
  metric(row,"frameTimeSeconds",function() return Stats.FrameTime end,true)
  metric(row,"sceneDrawcalls",function() return Stats.SceneDrawcallCount end,false)
  metric(row,"sceneTriangles",function() return Stats.SceneTriangleCount end,false)
  metric(row,"dataSendKbps",function() return Stats.DataSendKbps end,false)
  metric(row,"dataReceiveKbps",function() return Stats.DataReceiveKbps end,false)
  local trackingOK,tracking=pcall(function() return Stats.MemoryTrackingEnabled end)
  row.memoryTrackingEnabled=trackingOK and type(tracking)=="boolean" and tracking or false
  for _,tag in ipairs({"LuaHeap","Instances"}) do
   if trackingOK and tracking==true then metric(row,tag.."Mb",function() return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag[tag]) end,false)
   else local name=tag.."Mb"; metrics[name]=metrics[name] or {values={},missing=0}; metrics[name].missing+=1; row.missing[name]="MemoryTrackingEnabled 停用或不可讀；沒有把 API 回傳0當量測"; metrics[name].lastMissingReason=row.missing[name] end
  end
  local camera=workspace.CurrentCamera
  if camera then local p,v=camera.CFrame.Position,camera.ViewportSize; row.camera={position={p.X,p.Y,p.Z},viewport={v.X,v.Y}} else row.missing.camera="缺少 CurrentCamera" end
  local cleared=folders.units and folders.buildings and factions and row.managed.units==0 and row.managed.buildings==0 and #factions:GetChildren()==0
  for _,player in ipairs(Players:GetPlayers()) do
   if player:GetAttribute("MatchReportJSON")~=nil or player:GetAttribute("TeamId")~=nil or player:GetAttribute("TeamName")~=nil
    or player:GetAttribute("Forfeited")~=false or player:GetAttribute("Defeated")~=false then cleared=false end
  end
  row.restartClearFacts=cleared==true
  if Observer.IsRestart(pendingEnded,generation,phase,row.restartClearFacts) then
   table.insert(restarts,{fromGeneration=pendingEnded,toGeneration=generation,atSeconds=row.atSeconds,stats=clone(row.stats),managed=clone(row.managed)})
   pendingEnded=nil
  end
  for _,leave in ipairs(leaves) do if not leave.cleanupObservedAt then
   local counts=row.owners[tostring(leave.userId)] or {units=0,buildings=0}
   if folders.units and folders.buildings and not Players:GetPlayerByUserId(leave.userId) and counts.units==0 and counts.buildings==0
    and row.managed.unattributedUnits==0 and row.managed.unattributedBuildings==0 then leave.cleanupObservedAt=row.atSeconds; leave.cleanupObservedDelaySeconds=row.atSeconds-leave.atSeconds end
  end end
  latest=row; table.insert(rows,row)
  if elapsed()-lastLog>=30 then print("[PERF_OBSERVATION SAMPLE]",Http:JSONEncode({elapsed=row.atSeconds,phase=row.phase,generation=row.generation,focus=row.focus,actualUnits=row.managed.units,actors=row.actors,configuredFourBy200=row.configuredFourBy200,observedFourBy200=row.observedFourBy200,restarts=#restarts,frames=Observer.FrameSummary(total),stats=row.stats,missing=row.missing})); lastLog=elapsed() end
 end
 local function snapshot(reason)
  local report={version=1,scope="ClientReadOnlyObservation",performanceAccepted=false,reason=reason or "snapshot",context=options.context or "未提供硬體／圖形品質／視窗焦點資料",
   requestedSeconds=seconds,elapsedSeconds=elapsed(),sampleIntervalSeconds=interval,sampleCount=#rows,frames=Observer.FrameSummary(total),metrics={},segments={},leaves=clone(leaves),restarts=clone(restarts),firstSample=clone(rows[1]),latest=clone(latest),
   fullLoad={samples=fullSamples,longestConsecutiveSampleSpanSeconds=longestFullSpan,firstObserved=clone(firstFullLoad),continuousFullLoadNotProven=true},missing={},limits={maxSamples=902,maxSegments=64,segmentOverflow=segmentOverflow},
   framesScope="全段含未知／前景／背景與多視窗節流；不能當裝置或真手機效能",
   focusCoverage=Observer.FocusCoverage(focus,elapsed()),framesByFocus={}}
  report.focusCoverage.unattributedTransitionFrames=focusBoundaryFrames
  for name,record in pairs(focusFrames) do report.framesByFocus[name]=Observer.FrameSummary(record) end
  for name,series in pairs(metrics) do report.metrics[name]=Observer.NumericSummary(series.values,series.missing); if series.missing>0 then report.missing[name]={samples=series.missing,lastReason=series.lastMissingReason} end end
  for _,segment in ipairs(segments) do table.insert(report.segments,{phase=segment.phase,generation=segment.generation,focus=segment.focus,atSeconds=segment.atSeconds,frames=Observer.FrameSummary(segment.frames)}) end
  if total.count==0 then report.missing.renderFrames=true end
  if fullSamples==0 then report.missing.actualFourBy200=true end
  if #restarts<expectedRestarts then report.missing.expectedRestarts={expected=expectedRestarts,observed=#restarts} end
  if #leaves<expectedLeaves then report.missing.expectedLeaves={expected=expectedLeaves,observed=#leaves} end
  for _,leave in ipairs(leaves) do if not leave.cleanupObservedAt then report.missing.leaveCleanup=true end end
  for key,value in pairs(reasons) do report.missing[key]=value end
  if focus.eventCount==0 then report.missing.initialWindowFocus="尚未收到焦點事件；整段焦點未知" end
  report.unmeasured={"真手機與熱降頻","伺服器CPU／尋路併發","RTS RemoteEvent 次數","初始視窗焦點／遮蔽比例／背景節流因果","正式存檔與跨服恢復","所有800單位同時可見／每幀滿載"}
  if options.includeSamples==true then report.samples=clone(rows) end
  return report
 end
 local handle={}
 function handle:Snapshot() return finished and clone(result) or snapshot() end
 function handle:Finish(reason)
  if finished then return clone(result) end
  finished=true
  for _,connection in ipairs(connections) do connection:Disconnect() end
  local ok,message=pcall(collect); if not ok then reasons.finalSampleError=tostring(message) end
  Observer.running=false
  result=snapshot(reason or "manual")
  print("[PERF_OBSERVATION FINISHED] 只完成限定時間觀測；不是壓力／真機效能PASS",Http:JSONEncode(result))
  return clone(result)
 end
 function handle:Wait()
  while not finished do task.wait(0.1) end
  return clone(result)
 end
 Observer.running=true
 changed()
 table.insert(connections,workspace:GetAttributeChangedSignal("MatchPhase"):Connect(changed))
 table.insert(connections,workspace:GetAttributeChangedSignal("MatchGeneration"):Connect(changed))
 local function focusChanged(nextState)
  if finished then return end
  if Observer.FocusTransition(focus,nextState,elapsed()) then focusChangedSinceRender=true; changed() end
 end
 table.insert(connections,UIS.WindowFocused:Connect(function() focusChanged("Focused") end))
 table.insert(connections,UIS.WindowFocusReleased:Connect(function() focusChanged("Background") end))
 local firstRender=true
 table.insert(connections,run.RenderStepped:Connect(function(delta)
  if finished or os.clock()>=deadline then return end
  if firstRender then firstRender=false; focusChangedSinceRender=false; return end
  Observer.AddFrame(total,delta)
  if focusChangedSinceRender then focusBoundaryFrames+=1; focusChangedSinceRender=false
  else Observer.AddFrame(focusFrames[focus.state],delta); if activeSegment then Observer.AddFrame(activeSegment.frames,delta) end end
 end))
 table.insert(connections,Players.PlayerRemoving:Connect(function(player)
  if #leaves>=16 then reasons.leaveLimitReached=true; return end
  local before=latest and latest.owners[tostring(player.UserId)] or nil
  table.insert(leaves,{userId=player.UserId,atSeconds=elapsed(),lastSampleCounts=clone(before or {})})
 end))
 local initialOK,initialError=pcall(collect)
 if not initialOK then reasons.initialSampleError=tostring(initialError) end
 task.spawn(function()
  local ok,message=xpcall(function()
   while not finished and os.clock()<deadline do
    task.wait(math.min(interval,math.max(0,deadline-os.clock())))
    if not finished and os.clock()<deadline then collect() end
   end
  end,debug.traceback)
  if not ok then reasons.samplingError=tostring(message) end
  if not finished then handle:Finish(ok and "deadline" or "error") end
 end)
 print("[PERF_OBSERVATION ARMED] 唯讀、有總期限；單位由正常玩法產生；重開／退出由真人正常執行。")
 return handle
end
function Observer.Run(options) return Observer.Start(options):Wait() end
return Observer
