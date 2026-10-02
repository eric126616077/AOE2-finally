-- Pure, bounded presentation timeline. Samples always come from the authoritative Root.
-- Rendering waits one server step; it never predicts a position beyond the latest sample.
local Rules={Delay=.12,ServerStep=.1,MaxSamples=6,VisibilityInterval=.125,PoseInterval=1/30,MaxDetailedUnits=96}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Rules.New(now,frame)
 assert(finite(now) and frame~=nil,"invalid initial motion sample")
 return {samples={{time=now,frame=frame}}}
end
function Rules.IsDiscontinuity(distance,speed)
 if not finite(distance) or distance<0 then return true end
 local maximum=finite(speed) and math.max(24,math.max(0,speed)*.6) or 24
 return distance>maximum
end
function Rules.Push(timeline,now,frame,reset)
 if type(timeline)~="table" or not finite(now) or frame==nil then return false end
 local samples=timeline.samples
 if type(samples)~="table" or #samples==0 or now<samples[#samples].time then return false end
 local last=samples[#samples]
 if reset then
  table.clear(samples)
  samples[1]={time=now,frame=frame}
  return true
 end
 if now==last.time then last.frame=frame; return true end
 -- Starting after an idle/stalled period must not stretch one step across the whole pause.
 if now-last.time>Rules.ServerStep*2.5 then
  table.clear(samples)
  samples[1]={time=now-Rules.ServerStep,frame=last.frame}
 end
 table.insert(samples,{time=now,frame=frame})
 if #samples>Rules.MaxSamples then table.remove(samples,1) end
 return true
end
function Rules.Sample(timeline,now)
 local samples=timeline.samples
 local latest=samples[#samples]
 local target=now-Rules.Delay
 if #samples==1 or target>=latest.time then return latest.frame,latest.frame,1,true end
 local first=samples[1]
 if target<=first.time then return first.frame,first.frame,1,false end
 for index=2,#samples do
  local after=samples[index]
  if target<=after.time then
   local before=samples[index-1]
   return before.frame,after.frame,math.clamp((target-before.time)/(after.time-before.time),0,1),false
  end
 end
 return latest.frame,latest.frame,1,true
end
return Rules
