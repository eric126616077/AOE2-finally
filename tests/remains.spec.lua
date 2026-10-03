local Rules=require("../src/ReplicatedStorage/Shared/RemainsRules")
local count=0
local function expect(value,message) count+=1; assert(value,message) end
local function near(a,b) return math.abs(a-b)<1e-6 end
-- 倒地：起點直立、終點平躺，途中不超過 1，加速倒下。
expect(near(Rules.FallProgress(0),0),"fall did not start upright")
expect(near(Rules.FallProgress(1),1),"fall did not end lying down")
local previous,peak=0,0
for step=0,100 do
 local value=Rules.FallProgress(step/100)
 expect(value>=0 and value<=1,"fall progress left [0,1]")
 if step/100<1-Rules.FallSettle then expect(value>=previous,"fall moved back up before landing") end
 peak=math.max(peak,value)
 previous=value
end
expect(Rules.FallProgress(.2)<.2,"fall does not accelerate like gravity")
expect(near(Rules.FallProgress(1-Rules.FallSettle),1),"fall did not reach the ground before settling")
expect(Rules.FallProgress(1-Rules.FallSettle/2)<1,"landing has no settle bounce")
for _,bad in ipairs({0/0,math.huge,-math.huge,"x",nil}) do
 expect(near(Rules.FallProgress(bad),1),"invalid time did not jump to the lying pose")
end
expect(near(Rules.FallProgress(-3),0) and near(Rules.FallProgress(4),1),"fall time is not bounded")
-- 屍體淡出只發生在最後 FadeSeconds，且單調變透明、下沉。
local alpha,sink=Rules.CorpseFade(100,120)
expect(alpha==0 and sink==0,"fresh corpse already fading")
alpha,sink=Rules.CorpseFade(120-Rules.FadeSeconds,120)
expect(alpha==0 and sink==0,"fade started early")
local lastAlpha,lastSink=0,0
for step=0,30 do
 local a,s=Rules.CorpseFade(120-Rules.FadeSeconds+step*Rules.FadeSeconds/30,120)
 expect(a>=lastAlpha and s>=lastSink,"corpse fade reversed")
 lastAlpha,lastSink=a,s
end
expect(near(lastAlpha,1) and near(lastSink,Rules.SinkDepth),"expired corpse still visible")
alpha,sink=Rules.CorpseFade(500,120)
expect(near(alpha,1) and near(sink,Rules.SinkDepth),"late client did not hide an expired corpse")
alpha,sink=Rules.CorpseFade(0/0,120)
expect(alpha==0 and sink==0,"invalid clock hid a corpse")
-- 建築倒塌：完全下沉並淡出，搖晃在最後歸零，倒向依 seed 固定。
local s0,_,_,f0=Rules.Collapse(0,.3)
local s1,tilt1,shake1,f1=Rules.Collapse(1,.3)
expect(s0==0 and f0==0,"collapse started sunk or faded")
expect(near(s1,1) and near(f1,1) and near(shake1,0),"collapse did not finish sunk and hidden")
local _,tiltOther=Rules.Collapse(1,.8)
expect(tilt1<0 and tiltOther>0,"collapse direction does not follow its seed")
local lastSunk=0
for step=0,40 do
 local sunk,tilt,shake,fade=Rules.Collapse(step/40,.6)
 expect(sunk>=lastSunk and fade>=0 and fade<=1,"collapse rose or over-faded")
 expect(math.abs(tilt)<=Rules.CollapseTilt+1e-9 and math.abs(shake)<=Rules.CollapseShake+1e-9,"collapse motion unbounded")
 lastSunk=sunk
end
-- 樹倒下到 90 度後才淡出。
local angle,fade=Rules.TreeFall(0)
expect(angle==0 and fade==0,"tree started fallen")
angle,fade=Rules.TreeFall(.69)
expect(angle<math.pi/2 and fade==0,"tree faded before landing")
angle,fade=Rules.TreeFall(1)
expect(near(angle,math.pi/2) and near(fade,1),"tree did not land and fade")
local sunkResource,fadeResource=Rules.ResourceFade(1)
expect(near(sunkResource,1) and near(fadeResource,1),"resource did not finish fading")
-- 種子穩定、在範圍內、會分散。
local low,total=0,0
for x=-20,20 do for z=-20,20 do
 local value=Rules.Seed(x*3.7,z*2.9)
 expect(value>=0 and value<1 and value==Rules.Seed(x*3.7,z*2.9),"seed unstable or out of range")
 total+=1
 if value<.5 then low+=1 end
end end
expect(low/total>.3 and low/total<.7,"seed too lopsided to vary fall direction")
expect(Rules.Seed(0/0,1)==0,"invalid position corrupted seed")
expect(Rules.Admit(0,1) and not Rules.Admit(1,1) and not Rules.Admit(nil,1),"animation budget check wrong")
print(("Remains animation tests passed: %d checks"):format(count))
