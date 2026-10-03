local checks=0
local function expect(value,message) checks+=1; assert(value,message) end
local function waypoint(x) return {Position=Vector3.new(x,0,0)} end
local unit=actor(0)
local order={path={waypoint(0),waypoint(8),waypoint(16)},index=1}
moveToward(unit,order,Vector3.new(20,0,0),14,.1,1)
expect(unit.moves==1 and math.abs(unit.pos.X-1.4)<1e-9,"path origin does not consume a tick")
expect(order.index==2,"reached origin skipped")
unit=actor(8)
order={path={waypoint(8),waypoint(8),waypoint(16)},index=1}
moveToward(unit,order,Vector3.new(20,0,0),14,.1,1)
expect(unit.moves==1 and math.abs(unit.pos.X-9.4)<1e-9,"coincident intermediate nodes do not stall")
expect(order.index==3,"bounded node traversal preserves next segment")
unit=actor(16)
order={path={waypoint(16)},index=1}
moveToward(unit,order,Vector3.new(20,0,0),14,.1,1)
expect(unit.moves==1 and math.abs(unit.pos.X-17.4)<1e-9 and order.path==nil,"full route end continues toward live destination")
unit=actor(16)
routes=0
order={path={waypoint(16)},index=1,partialRoute=true}
moveToward(unit,order,Vector3.new(20,0,0),14,.1,1)
expect(unit.moves==0 and routes==1,"partial route remains blocked until validated continuation")
expect(order.pendingRoute and not order.partialRoute and #order.partialHistory==1,"partial route history retained")
unit=actor(8)
blocked=true; routes=0
order={path={waypoint(8),waypoint(16)},index=1}
moveToward(unit,order,Vector3.new(20,0,0),14,.1,1)
expect(unit.moves==0 and routes==1 and order.path==nil,"live collision still prevents every movement segment")
blocked=false
unit=actor(19.5)
order={}
moveToward(unit,order,Vector3.new(20,0,0),14,.1,1)
expect(unit.moves==1 and math.abs(unit.pos.X-20)<1e-9,"last segment never overshoots goal")
local moving=actor(0)
local waiting=actor(8,0,2,true)
order={kind="move"}
local lateral=0
for tick=1,140 do
 if (moving.pos-Vector3.new(20,0,0)).Magnitude<1 then break end
 moveToward(moving,order,Vector3.new(20,0,0),14,.1,tick*.1)
 lateral=math.max(lateral,math.abs(moving.pos.Z))
 expect((moving.pos-waiting.pos).Magnitude>=4.05-1e-7,"live authority swept body never overlaps an idle unit")
end
expect((moving.pos-Vector3.new(20,0,0)).Magnitude<1 and lateral>2,"unit reaches a clear goal by steering around an idle neighbor")
expect(routes==1,"dynamic crowd avoidance does not compute static paths each tick")
local left=actor(0)
local right=actor(20,0,2,true)
local leftOrder,rightOrder={kind="move"},{kind="move"}
for tick=1,160 do
 if (left.pos-Vector3.new(20,0,0)).Magnitude>=1 then moveToward(left,leftOrder,Vector3.new(20,0,0),14,.1,tick*.1) end
 expect((left.pos-right.pos).Magnitude>=4.05-1e-7,"first head-on authority step never overlaps neighbor")
 if right.pos.Magnitude>=1 then moveToward(right,rightOrder,Vector3.new(0,0,0),14,.1,tick*.1) end
 expect((left.pos-right.pos).Magnitude>=4.05-1e-7,"second head-on step sees the immediately updated position")
 if (left.pos-Vector3.new(20,0,0)).Magnitude<1 and right.pos.Magnitude<1 then break end
end
expect((left.pos-Vector3.new(20,0,0)).Magnitude<1 and right.pos.Magnitude<1,"head-on units pass and both reach their exchanged destinations")
moving=actor(0,0,3)
waiting=actor(10,0,4,true)
order={kind="move"}
for tick=1,180 do
 if (moving.pos-Vector3.new(26,0,0)).Magnitude<1 then break end
 moveToward(moving,order,Vector3.new(26,0,0),27,.1,tick*.1)
 expect((moving.pos-waiting.pos).Magnitude>=7.05-1e-7,"cavalry respects the siege unit's larger collision volume")
end
expect((moving.pos-Vector3.new(26,0,0)).Magnitude<1,"mixed size movement reaches a clear destination")
moving=actor(0)
waiting=actor(8,0,2,true)
order={kind="move"}
for tick=1,20 do
 if moving.stopped then break end
 moveToward(moving,order,waiting.pos,14,.1,tick*.1)
 expect((moving.pos-waiting.pos).Magnitude>=4.05-1e-7,"occupied destination never stacks units")
end
expect(moving.stopped==true,"occupied destination finishes beside the blocking unit")
moving=actor(0)
waiting=actor(8,0,2,true)
orders[waiting]={kind="move"}
order={kind="move"}
moveToward(moving,order,waiting.pos,14,.1,.1)
moveToward(moving,order,waiting.pos,14,.1,.2)
moveToward(moving,order,waiting.pos,14,.1,.3)
expect(not moving.stopped,"moving teammate at a destination does not prematurely complete a group order")
expect((moving.pos-waiting.pos).Magnitude>=4.05-1e-7,"waiting for a moving teammate still respects collision volume")
moving=actor(0)
waiting=actor(8,0,2,true)
order={kind="move",path={waypoint(0),waypoint(8),waypoint(16)},index=1}
for tick=1,140 do
 if (moving.pos-Vector3.new(24,0,0)).Magnitude<1 then break end
 moveToward(moving,order,Vector3.new(24,0,0),14,.1,tick*.1)
 expect((moving.pos-waiting.pos).Magnitude>=4.05-1e-7,"occupied intermediate navigation node does not cause overlap")
end
expect((moving.pos-Vector3.new(24,0,0)).Magnitude<1,"static-safe following waypoint bypasses an occupied intermediate node")
moving=actor(0)
waiting=actor(8,0,2,true)
order={kind="move",path={waypoint(0),waypoint(8)},index=1}
for tick=1,140 do
 if (moving.pos-Vector3.new(20,0,0)).Magnitude<1 then break end
 moveToward(moving,order,Vector3.new(20,0,0),14,.1,tick*.1)
 expect((moving.pos-waiting.pos).Magnitude>=4.05-1e-7,"occupied final path node never causes collision")
end
expect((moving.pos-Vector3.new(20,0,0)).Magnitude<1,"occupied final path node continues toward the live destination when static-clear")
moving=actor(0)
waiting=actor(8,0,2,true)
order={kind="move",path={waypoint(0),waypoint(8)},index=1,partialRoute=true,partialAttempts=1}
local beforeRoutes=routes
for tick=1,20 do
 moveToward(moving,order,Vector3.new(24,0,0),14,.1,tick*.1)
 if order.pendingRoute then break end
end
expect(order.pendingRoute and not order.path and not order.partialRoute and routes==beforeRoutes+1,"occupied partial endpoint requests bounded continuation from the safe live position")
expect(order.partialAttempts==1 and #order.partialHistory==1 and (moving.pos-waiting.pos).Magnitude>=4.05-1e-7,"crowded prefix preserves retry budget and progress history without teleport")
local group={actor(0,0,2),actor(24,0,2,true),actor(-24,20,2,true),actor(24,20,3,true)}
local groupGoals={Vector3.new(-3.25,0,-12),Vector3.new(3.25,0,-12),Vector3.new(-3.25,0,-5.5),Vector3.new(3.25,0,-5.5)}
for _,member in ipairs(group) do orders[member]={kind="move"} end
local groupFinished=false
for tick=1,240 do
 groupFinished=true
 for index,member in ipairs(group) do
  if orders[member] then
   if (member.pos-groupGoals[index]).Magnitude<=1 then stop(member)
   else moveToward(member,orders[member],groupGoals[index],member.radius==3 and 27 or 14,.1,tick*.1) end
  end
  groupFinished=groupFinished and (member.pos-groupGoals[index]).Magnitude<=1
 end
 for first=1,#group do
  for second=first+1,#group do
   expect((group[first].pos-group[second].pos).Magnitude>=group[first].radius+group[second].radius+.05-1e-7,"mixed formation remains separated while passing temporary destination occupants")
  end
 end
 if groupFinished then break end
end
expect(groupFinished,"all mixed group members finish at their assigned formation positions")

do
 -- Studio 交貨卡住的實際座標：兩村民與一斥候固定不動，只讓交貨者避讓。
 local function pocketFixture()
  blocked,staticSegmentHook=false,nil
  local worker=actor(-216.21965,-153.95062,2)
  local idleA=actor(-214.39995,-160.30869,2,true)
  local idleB=actor(-211.69131,-154.39995,2,true)
  local idleC=actor(-220.30869,-157.60005,3,true)
  local group={worker,idleA,idleB,idleC}
  local idlePositions={idleA.pos,idleB.pos,idleC.pos}
  local order={kind="deliver"}
  orders[worker]=order
  return worker,group,idlePositions,order,Vector3.new(-216,0,-193)
 end
 local function pocketSafety(worker,group,idlePositions,previous)
  expect((worker.pos-previous).Magnitude<=1.4+1e-7,"delivery retreat obeys the authoritative speed budget")
  for index=2,#group do
   expect((group[index].pos-idlePositions[index-1]).Magnitude==0,"delivery retreat never moves idle blocking units")
  end
  for first=1,#group do
   for second=first+1,#group do
    local a,b=group[first],group[second]
    expect((a.pos-b.pos).Magnitude-a.radius-b.radius>=.05-1e-7,"delivery retreat preserves every pairwise clearance")
   end
  end
 end
 local function seedRetreat()
  local worker,group,idlePositions,order,goal=pocketFixture()
  local previous=worker.pos
  moveToward(worker,order,goal,14,.1,.1)
  pocketSafety(worker,group,idlePositions,previous)
  expect(order.escapeGoal and order.escapeOriginalGoal==goal and order.escapeExpires>.1,"blocked delivery starts a persistent temporary retreat")
  expect(order.escapeAttempts==1 and #order.escapeHistory==1,"temporary retreat records its first bounded attempt")
  return worker,group,idlePositions,order,goal
 end

 local worker,group,idlePositions,order,goal=pocketFixture()
 local reached=false
 for tick=1,150 do
  local previous=worker.pos
  moveToward(worker,order,goal,14,.1,tick*.1)
  pocketSafety(worker,group,idlePositions,previous)
  expect((order.escapeAttempts or 0)<=2 and #(order.escapeHistory or {})<=2,"delivery retreat attempts and point history remain bounded")
  if (worker.pos-goal).Magnitude<=1 then reached=true; break end
 end
 expect(reached,"delivery worker escapes three stationary mixed-radius neighbors within fifteen seconds")

 -- 逃出途中出現靜態障礙，不能沿先前驗證過的點繼續穿過它。
 worker,group,idlePositions,order,goal=seedRetreat()
 local before,history,attempts,beforeRoutes=worker.pos,order.escapeHistory,order.escapeAttempts,routes
 order.partialAttempts=7
 staticSegmentHook=function() return false end
 moveToward(worker,order,goal,14,.1,.2)
 pocketSafety(worker,group,idlePositions,before)
 expect((worker.pos-before).Magnitude==0 and routes==beforeRoutes+1,"new static obstacle blocks retreat and requests the original route")
 expect(not order.escapeGoal and not order.escapeOriginalGoal and not order.escapeExpires,"static obstacle clears the active retreat")
 expect(order.escapeAttempts==attempts and order.escapeHistory==history and order.partialAttempts==7,"static retreat cancellation preserves retry and partial-route budgets")
 staticSegmentHook=nil

 -- 正常 step 仍安全，但所有後退終點位於牆後；完整線段驗證須拒絕它們。
 worker,group,idlePositions,order,goal=pocketFixture()
 local barrierZ=worker.pos.Z+.1
 local rejectedRetreats=0
 staticSegmentHook=function(_,_,to)
  if to.Z>barrierZ then rejectedRetreats+=1; return false end
  return true
 end
 for tick=1,20 do
  before=worker.pos
  moveToward(worker,order,goal,14,.1,tick*.1)
  pocketSafety(worker,group,idlePositions,before)
 end
 expect(rejectedRetreats>0 and not order.escapeGoal,"temporary retreat cannot cross a static boundary")
 expect(order.escapeAttempts==2 and #(order.escapeHistory or {})==0,"unsafe retreat search cannot exceed two attempts or retain rejected points")
 staticSegmentHook=nil

 worker,group,idlePositions,order,goal=seedRetreat()
 local expiry=order.escapeExpires
 before=worker.pos
 moveToward(worker,order,goal,14,.1,.2)
 pocketSafety(worker,group,idlePositions,before)
 expect(not order.escapeGoal or order.escapeExpires==expiry,"continuing a retreat does not extend its deadline")
 order.escapeAttempts=2
 before=worker.pos
 moveToward(worker,order,goal,14,.1,expiry+.01)
 pocketSafety(worker,group,idlePositions,before)
 expect(not order.escapeGoal and not order.escapeOriginalGoal and not order.escapeExpires,"expired retreat is cleared before further movement")
 expect(order.escapeAttempts==2,"expiry cannot reset the bounded retreat attempt counter")

 -- 透過真正 refreshRouteGoal + moveToward 驗證換目的地，不以 mock 複製清理邏輯。
 worker,group,idlePositions,order,goal=seedRetreat()
 order.escapeAttempts=2
 history=order.escapeHistory
 local changedGoal=goal+Vector3.new(10,0,0)
 before=worker.pos
 moveToward(worker,order,changedGoal,14,.1,.2)
 pocketSafety(worker,group,idlePositions,before)
 expect(order.routeGoal==changedGoal and order.routeVersion==1,"actual route-goal lifecycle accepts the changed destination")
 expect(not order.escapeGoal and not order.escapeOriginalGoal and not order.escapeExpires,"changed destination clears the previous temporary retreat")
 expect(order.escapeAttempts==2 and order.escapeHistory==history,"changing destination cannot silently reset the retreat budget")

 worker,group,idlePositions,order,goal=pocketFixture()
 order.escapeAttempts=2
 order.escapeHistory={{X=worker.pos.X+8,Z=worker.pos.Z},{X=worker.pos.X-8,Z=worker.pos.Z}}
 history=order.escapeHistory
 for tick=1,20 do
  before=worker.pos
  moveToward(worker,order,goal,14,.1,tick*.1)
  pocketSafety(worker,group,idlePositions,before)
 end
 expect(not order.escapeGoal and order.escapeAttempts==2 and order.escapeHistory==history and #history==2,"exhausted retreat budget cannot create a third attempt or expand history")
end
-- 單行通道裡兩個有指令的己方單位對頭（Studio 實測：送貨村民與撿聖物的僧侶卡住數分鐘）：
-- 卡住 2 秒後可以互相穿過；敵方單位仍然擋住，且穿越前不會重疊。
do
 staticSegmentHook=function(_,from,to) return math.abs(from.Z)<0.5 and math.abs(to.Z)<0.5 end
 local a=actor(0); a.instance,a.owner=true,"P"
 local b=actor(12,0,2,true); b.instance,b.owner=true,"P"
 local aOrder,bOrder={kind="relic"},{kind="deliver"}
 local passed,overlapBefore=false,false
 for tick=1,200 do
  local now=tick*.1
  if now<1.9 and (a.pos-b.pos).Magnitude<4.05-1e-7 then overlapBefore=true end
  if (a.pos-Vector3.new(24,0,0)).Magnitude>=1 then moveToward(a,aOrder,Vector3.new(24,0,0),14,.1,now) end
  if (b.pos-Vector3.new(-12,0,0)).Magnitude>=1 then moveToward(b,bOrder,Vector3.new(-12,0,0),14,.1,now) end
  if (a.pos-Vector3.new(24,0,0)).Magnitude<1 and (b.pos-Vector3.new(-12,0,0)).Magnitude<1 then passed=true; break end
 end
 expect(not overlapBefore,"friendly units overlapped before waiting in the corridor")
 expect(passed,"friendly units in a one-lane corridor never pass each other")
 local mover=actor(0); mover.instance,mover.owner=true,"P"
 local enemy=actor(8,0,2,true); enemy.instance,enemy.owner=true,"E"
 local moverOrder={kind="move"}
 for tick=1,60 do
  moveToward(mover,moverOrder,Vector3.new(20,0,0),14,.1,tick*.1)
  expect((mover.pos-enemy.pos).Magnitude>=4.05-1e-7,"unit passed through an enemy blocker")
 end
 staticSegmentHook=nil
end
print("Actual server movement step:",checks,"checks passed; mocked collision, not Studio path verification")
