local ConstructionRules=require("../src/ServerScriptService/ServerModules/ConstructionRules")
local UnitRules=require("../src/ServerScriptService/ServerModules/UnitRules")
local checks=0
local function expect(condition,message)
 checks+=1
 assert(condition,message)
end
local workerA={kind="villager",hp=40,owned=true}
local workerB={kind="villager",hp=40,owned=true}
local soldier={kind="infantry",hp=75,owned=true}
local enemy={kind="villager",hp=40,owned=false}
local dead={kind="villager",hp=0,owned=true}
local function canBuild(unit)
 return type(unit)=="table" and ConstructionRules.canBuildWorker(unit.kind,unit.hp,unit.owned)
end
local selected=ConstructionRules.validateSelection({workerA,workerB},canBuild)
expect(selected and #selected==2,"owned selected villagers cannot build")
expect(not ConstructionRules.validateSelection(nil,canBuild),"missing selection can create a site")
expect(not ConstructionRules.validateSelection({},canBuild),"empty selection can create a site")
expect(not ConstructionRules.validateSelection({soldier},canBuild),"military unit can create a site")
expect(not ConstructionRules.validateSelection({workerA,soldier},canBuild),"mixed military selection can create a site")
expect(not ConstructionRules.validateSelection({enemy},canBuild),"enemy villager can create a site")
expect(not ConstructionRules.validateSelection({dead},canBuild),"dead villager can create a site")
expect(not ConstructionRules.validateSelection({workerA,false},canBuild),"invalid worker entry can create a site")
expect(not ConstructionRules.validateSelection({[1]=workerA,[3]=workerB},canBuild),"sparse selection skips validation")
expect(not ConstructionRules.validateSelection({[1]=workerA,extra=workerB},canBuild),"dictionary selection skips validation")
expect(not ConstructionRules.validateSelection({[1]=workerA,[0]=workerB},canBuild),"zero index selection skips validation")
expect(not ConstructionRules.validateSelection({[201]=workerA},canBuild),"selection exceeds authority limit")
selected=ConstructionRules.validateSelection({workerA,workerA,workerB},canBuild)
expect(selected and #selected==2,"duplicate selection gives duplicate builder credit")
local oversized={}
for index=1,201 do oversized[index]=workerA end
expect(not ConstructionRules.validateSelection(oversized,canBuild),"oversized repeated selection accepted")
expect(not ConstructionRules.canBuildWorker("villager",math.huge,true),"infinite HP worker accepted")
expect(not ConstructionRules.canBuildWorker("villager",0/0,true),"NaN HP worker accepted")
expect(ConstructionRules.isWorking("villager",40,true,"build",true,5,5),"villager at edge of work range does not work")
expect(not ConstructionRules.isWorking("villager",40,true,"build",true,5.01,5),"travelling villager progresses construction")
expect(not ConstructionRules.isWorking("villager",40,true,"move",true,1,5),"moving away progresses construction")
expect(not ConstructionRules.isWorking("villager",40,true,nil,true,1,5),"stopped villager progresses construction")
expect(not ConstructionRules.isWorking("villager",40,true,"build",false,1,5),"another site's villager progresses construction")
expect(not ConstructionRules.isWorking("infantry",75,true,"build",true,1,5),"military unit progresses construction")
expect(not ConstructionRules.isWorking("villager",40,false,"build",true,1,5),"enemy worker progresses construction")
expect(not ConstructionRules.isWorking("villager",0,true,"build",true,1,5),"dead worker progresses construction")
expect(not ConstructionRules.isWorking("villager",40,true,"build",true,0/0,5),"NaN distance progresses construction")
local work,gained,complete=ConstructionRules.stepWork(0,8,0,5)
expect(work==0 and gained==0 and not complete,"empty site builds itself")
work,gained,complete=ConstructionRules.stepWork(0,8,1,3)
expect(work==3 and gained==3 and not complete,"single villager construction rate wrong")
work,gained,complete=ConstructionRules.stepWork(work,8,0,10)
expect(work==3 and gained==0 and not complete,"stopped construction loses or gains progress")
work,gained,complete=ConstructionRules.stepWork(work,8,2,2)
expect(work==6 and gained==3 and not complete,"two villagers' shared work rate wrong")
work,gained,complete=ConstructionRules.stepWork(work,8,3,5)
expect(work==8 and gained==2 and complete,"completed construction exceeds duration")
work,gained,complete=ConstructionRules.stepWork(work,8,2,10)
expect(work==8 and gained==0 and complete,"completed construction performs extra work")
for _,value in ipairs({-1,math.huge,0/0}) do
 expect(ConstructionRules.stepWork(0,8,1,value)==nil,"invalid step changes work")
end
expect(ConstructionRules.stepWork(0,8,1.5,1)==nil,"fractional builders accepted")
expect(ConstructionRules.stepWork(9,8,1,1)==nil,"invalid previous work accepted")
-- The production loop uses this exact action key after positive construction work.
-- A completed house alone cannot catch a missing cosmetic work pulse.
local clocks={}
local _,positiveWork=ConstructionRules.stepWork(0,8,1,.1)
expect(positiveWork>0 and UnitRules.takeAction(clocks,workerA,"workFeedback",10,1),"successful construction cannot publish its first work-feedback pulse")
expect(clocks[workerA].workFeedback==10,"accepted construction pulse did not commit its timestamp")
for tick=1,9 do
 expect(not UnitRules.takeAction(clocks,workerA,"workFeedback",10+tick/10,1),"repeated construction updates bypass the one-second feedback interval")
 expect(clocks[workerA].workFeedback==10,"rejected construction pulse advanced the clock")
end
expect(UnitRules.takeAction(clocks,workerA,"workFeedback",11,1),"construction pulse did not resume at the exact feedback interval")
expect(UnitRules.takeAction(clocks,workerB,"workFeedback",10.01,1),"one builder's feedback interval blocks another builder")
for _,action in ipairs({"attack","gather","repair"}) do
 expect(UnitRules.takeAction(clocks,workerA,action,11,1),"construction feedback interferes with authoritative "..action.." interval")
end
expect(not UnitRules.takeAction(clocks,workerA,"workFeedback",10.9,1),"construction feedback clock rollback resets the interval")
local unknownUnit={}
expect(not UnitRules.takeAction(clocks,unknownUnit,"unknown",12,1) and clocks[unknownUnit]==nil,"unknown feedback action creates an action clock")
for _,value in ipairs({math.huge,-math.huge,0/0,"12",false}) do
 expect(not UnitRules.takeAction(clocks,workerA,"workFeedback",value,1),"invalid construction feedback timestamp accepted")
 expect(clocks[workerA].workFeedback==11,"invalid construction feedback timestamp changed the last valid clock")
end
expect(not UnitRules.takeAction(clocks,workerA,"workFeedback",12,0/0),"invalid construction feedback interval accepted")
expect(UnitRules.takeAction(clocks,workerA,"workFeedback",12,1),"valid construction feedback remained blocked after invalid requests")
clocks[workerA]=nil
expect(UnitRules.takeAction(clocks,workerA,"workFeedback",0,1),"fresh unit/match retained its construction feedback clock")
print(string.format("PASS: %d construction selection / worker authority / pause-resume / feedback-clock checks",checks))
