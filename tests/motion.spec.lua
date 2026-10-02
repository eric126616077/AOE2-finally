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
print("PASS: "..checks.." bounded motion timeline / 10 Hz to 60 Hz / no extrapolation / idle / teleport checks")
