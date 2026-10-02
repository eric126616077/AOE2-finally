-- Optional Studio SERVER ModuleScript. Not mapped by default.project.json.
-- Requiring it does nothing. Explicit entry:
-- require(pathToThisModule).Start({seconds=45,label="比較窗口",sourceVersion="凍結來源版本"})
-- Logs are separate JSON records <= 700 bytes; do not JSONEncode the full Snapshot.
-- Heartbeat cadence includes probe overhead. It is NOT GameServer CPU, pathfinding
-- duration, a client rendering FPS measurement, or a performance acceptance result.
local Probe={running=false}
local SAMPLE_INTERVAL,MAX_LINE_BYTES=5,700
local epochNumber=0
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function clone(value)
 if type(value)~="table" then return value end
 local result={}
 for key,item in pairs(value) do result[key]=clone(item) end
 return result
end
local function sourceFingerprint(serverScripts)
 local scriptObject=serverScripts:FindFirstChild("GameServer")
 if not scriptObject then return {available=false,missing="GameServer absent"} end
 local ok,source=pcall(function() return scriptObject.Source end)
 if not ok or type(source)~="string" then return {available=false,missing="Source unreadable"} end
 -- Read-only comparison token, not a security hash or proof of active VM code.
 local hash=5381
 for index=1,#source do hash=(hash*33+string.byte(source,index))%4294967296 end
 return {available=true,bytes=#source,djb2=string.format("%08x",hash),activeVMVersionProven=false}
end

function Probe.Start(options)
 if options==nil then options={} end
 assert(type(options)=="table","Probe options must be a table")
 local run=game:GetService("RunService")
 assert(run:IsStudio() and run:IsServer(),"PerformanceServerProbe requires Studio SERVER")
 assert(not Probe.running,"PerformanceServerProbe already running")
 local seconds=options.seconds==nil and 45 or options.seconds
 local label=options.label==nil and "未標記窗口" or options.label
 local sourceVersion=options.sourceVersion==nil and "未提供" or options.sourceVersion
 assert(finite(seconds) and seconds>=30 and seconds<=120,"Probe seconds must be 30–120")
 assert(type(label)=="string" and #label>0 and #label<=96,"Probe label must be 1–96 bytes")
 assert(type(sourceVersion)=="string" and #sourceVersion>0 and #sourceVersion<=96,"Probe sourceVersion must be 1–96 bytes")
 local RS,Stats,Http=game:GetService("ReplicatedStorage"),game:GetService("Stats"),game:GetService("HttpService")
 local shared=RS:FindFirstChild("Shared")
 local observerModule=shared and shared:FindFirstChild("PerformanceObserver")
 assert(observerModule and observerModule:IsA("ModuleScript"),"Shared.PerformanceObserver missing")
 local Observer=require(observerModule)
 local source={callerVersion=sourceVersion,gameServer=sourceFingerprint(game:GetService("ServerScriptService")),
  scope="Visible Script.Source; active VM version unproven"}
 epochNumber+=1
 local epoch=epochNumber
 local start=os.clock()
 local deadline=start+seconds
 local frames=Observer.NewFrames()
 local samples,metrics,outputMissing={},{},{}
 local connection,samplerThread,deadlineThread,finished,result
 local function elapsed() return math.max(0,os.clock()-start) end
 local function emit(kind,data,sample)
  local row={probe="ServerHeartbeat",epoch=epoch,label=label,kind=kind,sample=sample or #samples,
   atSeconds=math.floor(elapsed()*1000+.5)/1000,data=data}
  local ok,json=pcall(function() return Http:JSONEncode(row) end)
  if not ok or #json>MAX_LINE_BYTES then
   outputMissing[kind]=(outputMissing[kind] or 0)+1
   -- Keep the omission itself short and machine readable; full data is in Snapshot.
   json=Http:JSONEncode({probe="ServerHeartbeat",epoch=epoch,kind="OutputMissing",recordKind=kind,
    reason=ok and "over700bytes" or "encodeFailed",sample=sample or #samples})
  end
  assert(#json<=MAX_LINE_BYTES,"Probe JSON line limit violated")
  print(json)
 end
 local function cadence()
  local summary=Observer.FrameSummary(frames)
  summary.meanHeartbeatHz,summary.effectiveFPS=summary.effectiveFPS,nil
  summary.worstInstantHeartbeatHz,summary.worstInstantaneousFPS=summary.worstInstantaneousFPS,nil
  if frames.count==0 then summary.missing="No valid Heartbeat delta" end
  return summary
 end
 local function numberAttribute(name)
  local value=workspace:GetAttribute(name)
  return finite(value) and value or false
 end
 local function textAttribute(name)
  local value=workspace:GetAttribute(name)
  return type(value)=="string" and #value<=48 and value or false
 end
 local function context()
  return {mapSize=numberAttribute("MapSize"),mapSizeName=textAttribute("MatchSizeName"),
   generation=numberAttribute("MatchGeneration"),phase=textAttribute("MatchPhase"),
   factions=numberAttribute("FactionCount"),populationLimit=numberAttribute("PopulationLimit")}
 end
 local function modelCounts()
  local counts,missing,others={},{},{}
  for _,kind in ipairs({"Units","Buildings","Resources"}) do
   local folder=workspace:FindFirstChild(kind)
   local count,other=0,0
   if folder then
    local attribute=kind=="Resources" and "RTSManagedResource" or "RTSManaged"
    for _,model in ipairs(folder:GetChildren()) do
     if model:IsA("Model") then
      if model:GetAttribute(attribute)==true then count+=1 else other+=1 end
     end
    end
   else missing[kind]=true end
   counts[kind],others[kind]=count,other
  end
  return {managed=counts,otherModels=others,missingFolders=missing}
 end
 local function readMetric(row,name,reader,positive)
  local ok,value=pcall(reader)
  local series=metrics[name] or {values={},missing=0}
  metrics[name]=series
  if ok and finite(value) and value>=0 and (not positive or value>0) then
   row.values[name]=value
   table.insert(series.values,value)
  else
   series.missing+=1
   row.missing[name]=true
  end
 end
 local function statsSample()
  local row={values={},missing={}}
  readMetric(row,"totalMemoryMb",function() return Stats:GetTotalMemoryUsageMb() end,true)
  readMetric(row,"instanceCount",function() return Stats.InstanceCount end,true)
  readMetric(row,"dataSendKbps",function() return Stats.DataSendKbps end,false)
  readMetric(row,"dataReceiveKbps",function() return Stats.DataReceiveKbps end,false)
  local ok,tracking=pcall(function() return Stats.MemoryTrackingEnabled end)
  row.memoryTrackingEnabled=ok and tracking==true
  for _,tag in ipairs({"LuaHeap","Instances"}) do
   readMetric(row,tag.."Mb",function()
    if not row.memoryTrackingEnabled then return nil end
    return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag[tag])
   end,false)
  end
  return row
 end
 local function collect()
  -- At most initial + 23 periodic + final samples for a 120-second epoch.
  if #samples>=25 then return end
  local row={atSeconds=elapsed(),context=context(),models=modelCounts(),stats=statsSample()}
  table.insert(samples,row)
  emit("Counts",{context=row.context,models=row.models},#samples)
  emit("Stats",row.stats,#samples)
  emit("Cadence",cadence(),#samples)
 end
 local function safeCollect()
  local ok=pcall(collect)
  if not ok then outputMissing.sampling=(outputMissing.sampling or 0)+1; emit("SampleError",{missing=true}) end
 end
 local function snapshot(reason)
  local report={version=1,scope="StudioServerReadOnly",epoch=epoch,label=label,source=clone(source),
   reason=reason or "snapshot",requestedSeconds=seconds,elapsedSeconds=elapsed(),sampleIntervalSeconds=SAMPLE_INTERVAL,
   sampleCount=#samples,latest=clone(samples[#samples]),samples=clone(samples),heartbeatCadence=cadence(),metrics={},
   outputMissing=clone(outputMissing),performanceAccepted=false,configurationAcrossEntireWindowProven=false,
   limits={maxSamples=25,maxJSONLineBytes=MAX_LINE_BYTES},
   unmeasured={"GameServer CPU time","pathfinding time/concurrency","client rendering FPS","remote request count","active VM source version"}}
  for name,series in pairs(metrics) do report.metrics[name]=Observer.NumericSummary(series.values,series.missing) end
  return report
 end
 local handle={}
 function handle:Snapshot() return finished and clone(result) or snapshot() end
 function handle:Finish(reason)
  if finished then return clone(result) end
  finished=true
  if connection then connection:Disconnect(); connection=nil end
  if samplerThread then pcall(task.cancel,samplerThread); samplerThread=nil end
  if deadlineThread then pcall(task.cancel,deadlineThread); deadlineThread=nil end
  safeCollect()
  result=snapshot(type(reason)=="string" and #reason<=48 and reason or "manual")
  Probe.running=false
  emit("Finished",{reason=result.reason,samples=result.sampleCount,elapsedSeconds=result.elapsedSeconds,
   performanceAccepted=false,measurement="Heartbeat cadence; not GameServer CPU/pathfinding"})
  result.outputMissing=clone(outputMissing)
  return clone(result)
 end
 Probe.running=true
 local firstHeartbeat=true
 connection=run.Heartbeat:Connect(function(delta)
  if finished or os.clock()>=deadline then return end
  -- Exclude the first delta whose interval began before this connection existed.
  if firstHeartbeat then firstHeartbeat=false; return end
  Observer.AddFrame(frames,delta)
 end)
 local function scheduleSample()
  if finished then return end
  samplerThread=task.delay(SAMPLE_INTERVAL,function()
   samplerThread=nil
   if finished or os.clock()>=deadline then return end
   safeCollect()
   scheduleSample()
  end)
 end
 deadlineThread=task.delay(seconds,function() deadlineThread=nil; handle:Finish("deadline") end)
 emit("Source",source)
 emit("Started",{requestedSeconds=seconds,sampleIntervalSeconds=SAMPLE_INTERVAL,configuration=context(),
  measurement="Heartbeat cadence; not GameServer CPU/pathfinding"})
 safeCollect()
 scheduleSample()
 return handle
end
return Probe
