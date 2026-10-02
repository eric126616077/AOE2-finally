local Observer=require("../src/ReplicatedStorage/Shared/PerformanceObserver")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function near(a,b) return type(a)=="number" and math.abs(a-b)<1e-9 end
local empty=Observer.FrameSummary(Observer.NewFrames())
expect(empty.validFrames==0 and empty.effectiveFPS==nil and empty.missing~=nil,"empty render signal reported real FPS")
local frames=Observer.NewFrames()
for _=1,600 do Observer.AddFrame(frames,1/60) end
local stable=Observer.FrameSummary(frames)
expect(stable.validFrames==600 and near(stable.effectiveFPS,60),"actual delta ratio differs from 60Hz")
expect(near(stable.meanDeltaMs,1000/60) and stable.p95UpperBoundMs==17,"histogram bound lost 0.5ms resolution")
expect(stable.below30Fraction==0 and stable.below15Fraction==0,"60Hz frames marked slow")
for _,delta in ipairs({0,-1,math.huge,-math.huge,0/0,"bad",false,1e308}) do Observer.AddFrame(frames,delta) end
expect(Observer.FrameSummary(frames).invalidFrames==8 and frames.count==600,"invalid timing affected frame denominator")
local stalls=Observer.NewFrames()
for _=1,19 do Observer.AddFrame(stalls,.01) end
Observer.AddFrame(stalls,2)
local stall=Observer.FrameSummary(stalls)
expect(stall.p95UpperBoundMs==10 and stall.worstDeltaMs==2000,"rare stall was discarded or p95 replaced by worst")
expect(near(stall.effectiveFPS,20/2.19) and stall.below15Fraction==.05,"stalled frames not included in effective FPS")
Observer.AddFrame(stalls,2)
local overflow=Observer.FrameSummary(stalls)
expect(overflow.p95UpperBoundMs==false and overflow.missing~=nil and overflow.worstDeltaMs==2000,"overflow p95 invented an exact percentile")
local threshold=Observer.NewFrames()
Observer.AddFrame(threshold,1/30); Observer.AddFrame(threshold,1/15); Observer.AddFrame(threshold,1/10)
local at=Observer.FrameSummary(threshold)
expect(near(at.below30Fraction,2/3) and near(at.below15Fraction,1/3),"strict slow-frame thresholds changed")
-- Compare histogram output with an independently sorted real delta distribution.
for count=1,81 do
 local distribution,record={},Observer.NewFrames()
 for index=1,count do local delta=((index*37)%173+1)/1000; table.insert(distribution,delta); Observer.AddFrame(record,delta) end
 table.sort(distribution)
 local exact=distribution[math.ceil(count*.95)]*1000
 local reported=Observer.FrameSummary(record).p95UpperBoundMs
 expect(reported>=exact-1e-9 and reported-exact<.5+1e-9,"histogram failed nearest-rank upper-bound contract")
end
local series=Observer.NumericSummary({10,100,20,30},2)
expect(series.samples==4 and series.missingSamples==2 and series.mean==40 and series.p95==100,"numeric Stats mean or p95 incorrect")
expect(series.first==10 and series.last==30 and series.lastMinusFirst==20 and series.minimum==10,"numeric original sample order was lost")
expect(Observer.NumericSummary({},3).missing~=nil and Observer.NumericSummary({},3).mean==nil,"missing Stats became zero MB")
local invalid=Observer.NumericSummary({4,math.huge,0/0,"bad",6},1)
expect(invalid.samples==2 and invalid.invalidInputs==3 and invalid.mean==5,"nonfinite values poisoned metric summary")
expect(Observer.NumericSummary({1e308,1e308}).mean==1e308,"finite large inputs overflowed their mean")
local extreme=Observer.NumericSummary({-1e308,1e308})
expect(extreme.lastMinusFirst==nil and extreme.differenceMissing~=nil,"nonfinite difference was serialized as a metric")
expect(Observer.IsRestart(10,11,"Lobby",true),"real ended-to-cleared-lobby boundary missing")
for _,phase in ipairs({"Playing","Starting","Ended","Unknown"}) do expect(not Observer.IsRestart(10,11,phase,true),"normal start or end counted as restart") end
expect(not Observer.IsRestart(nil,11,"Lobby",true) and not Observer.IsRestart(10,10,"Lobby",true),"no ended baseline counted as restart")
expect(not Observer.IsRestart(10,11,"Lobby",false),"phase raced ahead of managed cleanup")
expect(not Observer.IsRestart(math.huge,11,"Lobby",true) and not Observer.IsRestart(10,11.2,"Lobby",true),"invalid generation counted as restart")
local config={phase="Playing",size="Large",factions=4,populationLimit=200}
local actors={{id=1,active=true,units=200},{id=2,active=true,units=200},{id=-100001,active=true,units=200},{id=-100002,active=true,units=200}}
expect(Observer.IsFullLoad(config,actors),"four actual distinct actors at 200 not observed")
actors[4].units=199; actors[4].population=200; actors[4].queue=1
expect(not Observer.IsFullLoad(config,actors),"reserved population or queued model counted as actual unit")
actors[4].units=200; actors[4].active=false
expect(not Observer.IsFullLoad(config,actors),"defeated or spectator roster counted as full load")
actors[4].active=true; actors[4].id=actors[3].id
expect(not Observer.IsFullLoad(config,actors),"duplicate actor inflated four-faction roster")
actors[4].id=-100002
for _,field in ipairs({"phase","size","factions","populationLimit"}) do
 local broken=table.clone(config); broken[field]=false
 expect(not Observer.IsFullLoad(broken,actors),"configuration prerequisite ignored")
end
expect(not Observer.IsFullLoad(config,{actors[1],actors[2],actors[3]}),"three actual factions counted as four")
expect(not Observer.IsFullLoad(config,{actors[1],actors[2],actors[3],actors[4],actors[1]}),"extra spectator roster counted as four")
expect(not Observer.IsFullLoad(nil,actors) and not Observer.IsFullLoad(config,nil),"invalid observation table accepted")
local focus=Observer.NewFocus()
local initiallyUnknown=Observer.FocusCoverage(focus,10)
expect(initiallyUnknown.initialState=="Unknown" and initiallyUnknown.currentState=="Unknown" and initiallyUnknown.eventCount==0,"Start invented initial foreground focus")
expect(initiallyUnknown.secondsByState.Unknown==10 and initiallyUnknown.knownTimeFraction==0,"unknown time was counted as known focus")
expect(initiallyUnknown.firstEventAtSeconds==false and initiallyUnknown.visibilityMeasured==false and initiallyUnknown.throttlingCauseProven==false,"focus inferred visibility or throttle causality")
expect(focus.durations.Unknown==0 and focus.since==0,"Snapshot advanced or mutated focus accumulator")
expect(Observer.FocusTransition(focus,"Focused",5),"first actual WindowFocused event rejected")
expect(Observer.FocusTransition(focus,"Background",10),"actual WindowFocusReleased event rejected")
expect(Observer.FocusTransition(focus,"Focused",15),"foreground return rejected")
local coverage=Observer.FocusCoverage(focus,20)
expect(coverage.secondsByState.Unknown==5 and coverage.secondsByState.Focused==10 and coverage.secondsByState.Background==5,"focus event durations mixed foreground and background")
expect(coverage.knownTimeFraction==.75 and coverage.firstEventAtSeconds==5 and coverage.eventCount==3,"focus coverage lost unknown first interval")
expect(Observer.FocusTransition(focus,"Focused",17),"duplicate event was not observed")
local duplicate=Observer.FocusCoverage(focus,20)
expect(duplicate.secondsByState.Focused==10 and duplicate.secondsByState.Background==5 and duplicate.secondsByState.Unknown==5,"duplicate focus event double-counted time")
expect(duplicate.eventCount==4 and duplicate.firstEventAtSeconds==5,"duplicate event reset first-known timestamp")
for _,invalidAt in ipairs({16,-1,math.huge,0/0,"bad"}) do
 expect(not Observer.FocusTransition(focus,"Background",invalidAt),"invalid or reordered focus timestamp accepted")
end
expect(not Observer.FocusTransition(focus,"Unknown",19) and not Observer.FocusTransition(nil,"Focused",19),"unknown state can be fabricated by a focus event")
local afterInvalid=Observer.FocusCoverage(focus,20)
expect(afterInvalid.eventCount==4 and afterInvalid.secondsByState.Focused==10,"invalid focus input changed prior event evidence")
expect(Observer.FocusCoverage(Observer.NewFocus(),0).knownTimeFraction==false,"zero-time coverage divided by zero")
print("PASS: "..checks.." render timing / missing Stats / p95 bounds / restart boundary / actual-unit stress / event-only focus coverage checks")
