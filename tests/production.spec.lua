local Production=require("../src/ServerScriptService/ServerModules/ProductionRules")
local Report=require("../src/ServerScriptService/ServerModules/MatchReportRules")
local checks=0
local function expect(condition,message) checks+=1; assert(condition,message) end
local function item(kind,cost,remaining) return {kind=kind,cost=cost,remaining=remaining or 10,duration=10} end
local first,second,third=item("villager",{food=50},4),item("infantry",{food=60,gold=20}),item("archer",{wood=25,gold=45})
local queue={first,second,third}
local removed,nextRevision=Production.cancelTraining(queue,2,7,7)
expect(removed==second and nextRevision==8,"middle queue cancellation did not return exactly its item and next revision")
expect(#queue==2 and queue[1]==first and queue[2]==third,"middle cancellation corrupted queue order")
expect(first.remaining==4,"canceling waiting item restarted active training progress")
expect(removed.cost.food==60 and removed.cost.gold==20,"cancellation lost the exact server-paid resource receipt")
expect(not Production.cancelTraining(queue,1,7,8) and #queue==2,"duplicate stale click canceled or refunded another unit")
removed,nextRevision=Production.cancelTraining(queue,1,8,8)
expect(removed==first and nextRevision==9 and queue[1]==third,"active item cancellation did not move its successor to the front")
expect(removed.cost.food==50 and removed.remaining==4,"active training failed to return full cost after partial progress")
removed,nextRevision=Production.cancelTraining(queue,1,9,9)
expect(removed==third and nextRevision==10 and #queue==0,"last item cancellation did not empty queue")
expect(not Production.cancelTraining(queue,1,10,10),"empty queue produced a refund")
for _,invalid in ipairs({0,-1,1.1,math.huge,-math.huge,0/0,"1",true,{},6}) do
 local current={first,second}
 expect(not Production.cancelTraining(current,invalid,3,3) and #current==2,"invalid index mutated queue")
 expect(not Production.cancelTraining(current,1,invalid,3) and #current==2,"invalid or stale expected revision mutated queue")
end
expect(not Production.cancelTraining(nil,1,0,0),"missing queue produced a refund")
expect(not Production.cancelTraining({false},1,1,1),"malformed queue item was removed")
expect(not Production.cancelTraining({{kind="villager"}},1,1,1),"item without server-paid cost could refund")
expect(not Production.cancelTraining({first,first,first,first,first,first},1,1,1),"unbounded queue was accepted")
-- A unit finishing after a button is rendered must not turn that old click into
-- a cancellation of the next unit at the same visible index.
local progressed={second}
expect(not Production.cancelTraining(progressed,1,20,21) and progressed[1]==second,"completion race canceled successor")
local report=Report.New("production-test",0)
expect(Report.Record(report,1,"spend",{cost=first.cost,refundable=true}),"paid training did not record a refundable receipt")
expect(Report.Record(report,2,"refund",{spendId=1}),"cancellation could not reconcile paid training receipt")
expect(not Report.Record(report,3,"refund",{spendId=1}),"one receipt was refunded twice in match report")
expect(Report.Snapshot(report,1).resourcesSpent.food==0,"canceled training remained in net resource expenditure")
expect(Production.canRallyBuilding({trains={"villager"}},true,true),"completed owned production building could not set rally point")
expect(not Production.canRallyBuilding({trains={"villager"}},false,true),"foreign building could set rally point")
expect(not Production.canRallyBuilding({trains={"villager"}},true,false),"construction site could set rally point")
expect(not Production.canRallyBuilding({trains={}},true,true),"non-production building could set rally point")
expect(not Production.canRallyBuilding(nil,true,true),"unknown building could set rally point")
for _,resourceKind in ipairs({"food","wood","gold","stone"}) do
 expect(Production.canRallyResource(resourceKind,1,nil,7,true),"neutral resource rally rejected")
 expect(Production.canRallyResource(resourceKind,10,7,7,true),"owned resource rally rejected")
 expect(not Production.canRallyResource(resourceKind,10,8,7,true),"foreign resource rally accepted")
 expect(not Production.canRallyResource(resourceKind,10,7,7,false),"incomplete Farm rally accepted")
 for _,invalidAmount in ipairs({0,-1,0/0,math.huge,-math.huge,"10",false}) do
  expect(not Production.canRallyResource(resourceKind,invalidAmount,nil,7,true),"empty or invalid resource rally accepted")
 end
end
for _,invalidKind in ipairs({"fish","",false,1,{}}) do
 expect(not Production.canRallyResource(invalidKind,10,nil,7,true),"unknown resource rally accepted")
end
print(string.format("PASS: %d training refund / stale queue / rally authorization checks",checks))
