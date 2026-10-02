local Rules=require("../src/ServerScriptService/ServerModules/PathRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function point(x,z) return {X=x,Z=z} end
local function project(waypoint) return waypoint.Position end
local live=point(-335.3953857421875,-201.9433135986328)
local goal=point(-8,-144)
-- Independently intersect a segment with the measured LumberCamp footprint
-- expanded by the villager's 1.8-stud square half-width. No engine claim.
local function campClear(from,to)
 local enter,leave=0,1
 for _,axis in ipairs({"X","Z"}) do
  local center=axis=="X" and -328 or -192
  local low,high=center-9.8,center+9.8
  local origin,delta=from[axis],to[axis]-from[axis]
  if math.abs(delta)<1e-12 then if origin<low or origin>high then return true end
  else
   local a,b=(low-origin)/delta,(high-origin)/delta
   if a>b then a,b=b,a end
   enter,leave=math.max(enter,a),math.min(leave,b)
   if enter>leave then return true end
  end
 end
 return false
end
for _,rawSecond in ipairs({point(-338.47161865234375,-200.3756103515625),point(-339.46026611328125,-200.52586364746094),point(-340.44891357421875,-200.6761016845703)}) do
 local path={{Position=live},{Position=rawSecond},{Position=goal}}
 local report,index=Rules.inspectPath(path,live,project,campClear)
 expect(report and not report.full and index==2 and #report.path==1,"actual initial radius2/3/4 Camp collision was accepted")
 expect(Rules.bestPrefix({report},live.X,live.Z,goal.X,goal.Z,{})==nil,"zero-motion origin counted as a forward prefix")
end
local escape=point(-343.3953857421875,-201.9433135986328)
expect(campClear(live,escape),"actual west escape crosses measured Camp body")
-- Exact server 21:51:33 ESCAPE1/radius3 raw waypoints. Recorded collision
-- decisions are a regression fixture, not replacement physics or new Play.
local recorded={
 {-343.3953857421875,-201.9433135986328,true},
 {-341.6579284667969,-194.13426208496094,true},
 {-339.92047119140625,-186.32521057128906,true},
 {-339.00323486328125,-182.20260620117188,true},
 {-333.9128112792969,-176.0310821533203,true},
 {-328.8223876953125,-169.85955810546875,true},
 {-323.73199462890625,-163.6880340576172,true},
 {-318.6415710449219,-157.51651000976562,true},
 {-313.5511474609375,-151.34498596191406,true},
 {-308.46075439453125,-145.1734619140625,true},
 {-303.370361328125,-139.00193786621094,true},
 {-298.2799377441406,-132.83041381835938,true},
 {-293.1895446777344,-126.65888977050781,true},
 {-288.09912109375,-120.48736572265625,true},
 {-283.00872802734375,-114.31584167480469,true},
 {-277.9183044433594,-108.14431762695312,true},
 {-272.8279113769531,-101.97279357910156,true},
 {-267.7375183105469,-95.80126953125,false},
 {-262.6470947265625,-89.62974548339844,true},
}
local waypoints,decisions={},{}
for _,row in ipairs(recorded) do local p=point(row[1],row[2]); table.insert(waypoints,{Position=p}); decisions[p]=row[3] end
decisions[escape]=true
local calls=0
local function recordedClear(from,to)
 calls+=1
 if to==escape then return campClear(from,to) end
 return decisions[to]
end
local fullPath=Rules.prepend(waypoints,escape)
local report,index=Rules.inspectPath(fullPath,live,project,recordedClear)
expect(report and report.full==false and index==19 and report.blockedIndex==19,"first far Tree block index changed after prepending normal escape")
expect(#report.path==18 and calls==19,"prefix skipped a waypoint or continued past first true collision")
expect(report.endpoint.X==-272.8279113769531 and report.endpoint.Z==-101.97279357910156,"prefix endpoint included colliding Tree segment")
expect(report.path[#report.path]==waypoints[17] and report.path[#report.path]~=waypoints[18],"unsafe waypoint leaked into accepted prefix")
expect(not Rules.clearPath(fullPath,live,project,recordedClear),"whole colliding path was relabeled clear")
expect(Rules.clearPath(report.path,live,project,recordedClear),"all previously verified normal walking segments rejected")
expect(Rules.prefixProgress(live.X,live.Z,report.endpoint.X,report.endpoint.Z,goal.X,goal.Z,{})>60,"actual recorded prefix does not reduce remote goal distance")
expect(Rules.bestPrefix({report},live.X,live.Z,goal.X,goal.Z,{})==report,"actual safe Camp escape/far Tree prefix not selected")
expect(Rules.bestPrefix({report},live.X,live.Z,goal.X,goal.Z,{{X=report.endpoint.X,Z=report.endpoint.Z}})==nil,"visited endpoint allows repeated escape loop")
expect(#fullPath==20 and #waypoints==19 and waypoints[18].Position.X==recorded[18][1],"inspection mutated original raw path")
local uncertain=Rules.inspectPath(fullPath,live,project,function(from,to) if to==waypoints[17].Position then error("collision API failure") end; return recordedClear(from,to) end)
expect(uncertain==nil,"callback failure invented a usable safety prefix")
expect(Rules.inspectPath(fullPath,live,project,function() return "clear" end)==nil,"nonboolean callback invented body safety")
local farther={path={{Position=point(0,0)},{Position=point(16,0)}},endpoint=point(16,0)}
local nearer={path={{Position=point(0,0)},{Position=point(8,0)}},endpoint=point(8,0)}
expect(Rules.bestPrefix({nearer,farther},0,0,100,0,{})==farther,"selection ignores greatest verified goal progress")
expect(Rules.bestPrefix({nearer},0,0,100,0,{{X=10,Z=0}})==nil,"endpoint within four studs of history accepted")
expect(Rules.prefixProgress(0,0,8,0,100,0,{})==8,"eight-stud forward endpoint rejected")
expect(Rules.prefixProgress(0,0,7.999,0,100,0,{})==nil,"tiny movement spent another route attempt")
expect(Rules.prefixProgress(0,0,0,8,100,0,{})==nil and Rules.prefixProgress(0,0,-8,0,100,0,{})==nil,"sideways or backward loop counted as goal progress")
expect(Rules.prefixProgress(0,0,8,0,5,0,{})==nil,"insufficient remaining-distance reduction accepted")
expect(Rules.prefixProgress(nil,0,8,0,100,0,{})==nil and Rules.prefixProgress(0,0,8,0,math.huge,0,{})==nil,"nonfinite path coordinates accepted")
expect(Rules.prefixProgress(0,0,8,0,100,0,{{X=0/0,Z=0}})==nil,"invalid visit history bypassed loop guard")
expect(not Rules.goalChanged(0,0,7.999,0) and Rules.goalChanged(0,0,8,0),"static-goal reset threshold changed")
expect(not Rules.goalChanged(0,0,3,4) and Rules.goalChanged(0,0,6,6),"goal movement uses wrong coordinate metric")
expect(Rules.goalChanged(nil,0,8,0)==nil,"invalid moving goal accepted")
local attempts=0
for _=1,32 do attempts=assert(Rules.nextPartialAttempt(attempts)) end
expect(attempts==32 and Rules.nextPartialAttempt(attempts)==nil,"successful prefixes reset the 32-attempt bound")
expect(attempts*Rules.MAX_ENGINE_CALLS==224,"partial-stage compute budget is not finite 224")
for _,invalid in ipairs({-1,32,33,.5,math.huge,0/0,"0",false}) do expect(Rules.nextPartialAttempt(invalid)==nil,"invalid retry budget reached engine") end
expect(Rules.nextPartialAttempt(nil)==nil,"missing retry budget reached engine")
print("PASS: "..checks.." actual Camp/Tree recorded-prefix / collision exclusion / forward progress / visited-endpoint / bounded continuation checks (pure, not new engine)")
