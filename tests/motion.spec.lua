local Rules=require("../src/ReplicatedStorage/Shared/MotionRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function value(timeline,now)
 local a,b,t,settled=Rules.Sample(timeline,now)
 return a+(b-a)*t,settled
end
local path=Rules.New(0,0)
-- A real 10 Hz snapshot stream displayed at 60 Hz must advance between packets.
local previous,between=0,0
for index=1,180 do
 local now=index/60
 if index%6==0 then Rules.Push(path,now,now*20,false) end
 local displayed=value(path,now)
 expect(displayed>=previous-1e-9,"forward samples moved the visible unit backwards")
 expect(displayed<=math.floor(index/6)/10*20+1e-9,"interpolation extrapolated beyond authority")
 if index>18 and index%6~=0 and displayed>previous then between+=1 end
 previous=displayed
 expect(#path.samples<=Rules.MaxSamples,"timeline grew with match duration")
end
expect(between>=120,"unit still only moved when a server packet arrived")
local stopped,settled=value(path,3+Rules.Delay+.01)
expect(stopped==60 and settled,"stopped unit did not settle exactly at authority")
expect(value(path,9)==60,"missing packets caused predicted movement through an obstacle")
expect(Rules.Push(path,10,62,false),"movement after long idle rejected")
expect(#path.samples==2 and math.abs(path.samples[1].time-9.9)<1e-9,"idle interval stretched a single movement step")
expect(value(path,10)==60,"first post-idle sample jumped immediately to its target")
expect(math.abs(value(path,10.07)-61)<1e-8,"post-idle interpolation did not preserve a continuous step")
expect(value(path,10.3)==62,"post-idle sample never settled")
local before=#path.samples
expect(not Rules.Push(path,9,999,false) and #path.samples==before,"stale sample rewound the timeline")
expect(Rules.Push(path,10,63,false) and #path.samples==before,"same-batch sample added a zero-duration segment")
expect(value(path,11)==63,"same-batch sample lost its final authoritative frame")
for _,invalid in ipairs({math.huge,-math.huge,0/0,"time",false}) do
 expect(not Rules.Push(path,invalid,0,false),"nonfinite sample clock accepted")
end
expect(Rules.IsDiscontinuity(100,20) and not Rules.IsDiscontinuity(2,20),"teleport and normal server step confused")
expect(Rules.IsDiscontinuity(math.huge,20) and Rules.IsDiscontinuity(-1,20),"invalid displacement was interpolated")
expect(Rules.Push(path,12,100,true),"teleport reset rejected")
expect(#path.samples==1 and value(path,12)==100,"teleport swept the unit across unrelated map space")
-- Gait is paid for in ground covered: the same road gives the same steps at any speed or frame rate.
local function steps(kind,speed,fps,seconds)
 local phase=0
 for _=1,fps*seconds do phase+=Rules.GaitAdvance(kind,speed/fps) end
 return phase/(math.pi*2)
end
expect(math.abs(steps("villager",14,60,1)-14/Rules.FootCycle)<1e-6,"walker cycles did not match ground covered")
expect(math.abs(steps("villager",14,60,2)-steps("villager",28,144,1))<1e-6,"gait depended on speed or frame rate, feet slide")
expect(math.abs(steps("cavalry",24,60,1)-24/Rules.MountedCycle)<1e-6,"horse cycles did not match ground covered")
expect(math.abs(Rules.GaitAdvance("ram",Rules.WheelRadius)-1)<1e-9,"wheel did not roll one radian per radius travelled")
expect(Rules.GaitAdvance("villager",0)==0,"standing unit kept stepping")
for _,invalid in ipairs({-1,0/0,math.huge,Rules.MaxGaitStep+1,"far"}) do
 expect(Rules.GaitAdvance("villager",invalid)==0,"teleport or invalid travel spun the legs")
end
local weight=0
for _=1,60 do
 local nextWeight=Rules.GaitBlend(weight,true,1/60)
 expect(nextWeight>=weight and nextWeight<=1,"stride weight left 0..1 while easing in")
 weight=nextWeight
end
expect(weight==1 and Rules.GaitBlend(0,true,1/60)<1,"stride snapped instead of easing in")
for _=1,60 do weight=Rules.GaitBlend(weight,false,1/60) end
expect(weight==0 and Rules.GaitBlend(0/0,false,0)==0,"stride weight did not settle at rest")
-- 新單位出場：時間有上下限，異常距離不播放，位移單調收斂到出生點。
expect(Rules.SpawnDuration(0,10)==0 and Rules.SpawnDuration(0/0,10)==0 and Rules.SpawnDuration(Rules.SpawnMaxDistance+1,10)==0,"invalid spawn walk still animated")
expect(Rules.SpawnDuration(1,100)==Rules.SpawnMin and Rules.SpawnDuration(29,1)==Rules.SpawnMax,"spawn walk time not bounded")
expect(Rules.SpawnDuration(8,10)>0 and math.abs(Rules.SpawnDuration(8,10)-.8)<1e-9,"spawn walk ignored unit speed")
expect(Rules.SpawnDuration(8,0/0)==8/Rules.SpawnDefaultSpeed,"invalid speed did not fall back")
local remaining=1
for step=0,60 do
 local value=Rules.SpawnRemaining(step/60,.8)
 expect(value<=remaining+1e-12 and value>=0 and value<=1,"spawn walk moved back toward the building")
 remaining=value
end
expect(Rules.SpawnRemaining(0,.8)==1 and Rules.SpawnRemaining(.8,.8)==0 and Rules.SpawnRemaining(5,.8)==0,"spawn walk did not start at the door or end at the spawn point")
expect(Rules.SpawnRemaining(.1,0)==0 and Rules.SpawnRemaining(0/0,1)==0,"invalid spawn walk displaced the unit")
print("PASS: "..checks.." bounded motion timeline / 10 Hz to 60 Hz / no extrapolation / idle / teleport checks")
