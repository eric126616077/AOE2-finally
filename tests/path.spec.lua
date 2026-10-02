local Rules=require("../src/ServerScriptService/ServerModules/PathRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function same(a,b)
 if type(a)~="table" or #a~=#b then return false end
 for index,value in ipairs(b) do if a[index]~=value then return false end end
 return true
end
expect(same(Rules.candidateRadii(2),{2,3,4}),"villager must try original radius before the two square-body margins")
expect(same(Rules.candidateRadii(3),{3,5,6}),"mounted paths must cover the full collision radius")
expect(same(Rules.candidateRadii(4),{4,6,8}),"siege radius candidates changed")
expect(same(Rules.candidateRadii(0.1),{1}),"rounded duplicate radii must not trigger repeated engine work")
expect(same(Rules.candidateRadii(1),{1,2}),"two equal rounded fallback radii were not deduplicated")
for step=1,1000 do
 local radius=step/100
 local radii=Rules.candidateRadii(radius)
 expect(#radii>=1 and #radii<=3,"retry count is not bounded to three")
 expect(radii[1]==math.ceil(radius),"a narrow passage lost the smallest original radius")
 for index,value in ipairs(radii) do
  expect(value%1==0 and value>0 and (index==1 or value>radii[index-1]),"radii are not positive unique ascending integers")
 end
end
for _,value in ipairs({0,-1,math.huge,-math.huge,0/0,"2",false,1e308,9007199254740991}) do
 expect(Rules.candidateRadii(value)==nil,"invalid or overflowing radius reached the engine")
end
expect(Rules.candidateRadii(nil)==nil,"missing radius reached the engine")

-- Independent slab intersection against the recorded House footprint expanded
-- by the movement square's half-width. This is geometry, not engine evidence.
local function point(x,z) return {X=x,Z=z} end
local start=point(-190.0693,-174.1521)
local goal=point(-197.7,-197.7)
local function clearHouse(from,to)
 local entering,leaving=0,1
 for _,axis in ipairs({"X","Z"}) do
  local origin,delta=from[axis],to[axis]-from[axis]
  local low,high=-192-1.8,-176+1.8
  if math.abs(delta)<1e-12 then
   if origin<low or origin>high then return true end
  else
   local a,b=(low-origin)/delta,(high-origin)/delta
   if a>b then a,b=b,a end
   entering,leaving=math.max(entering,a),math.min(leaving,b)
   if entering>leaving then return true end
  end
 end
 return false
end
local function project(waypoint) return waypoint.Position end
local function path(second,last)
 return {{Position=start},{Position=second},{Position=last or goal}}
end
local radius2=path(point(-194.1544,-174.7317))
local radius3=path(point(-195.0161,-174.2243))
local radius4=path(point(-195.8779,-173.7170))
expect(not clearHouse(start,radius2[2].Position),"recorded radius2 first segment did not reproduce House collision")
expect(not clearHouse(start,radius3[2].Position),"recorded radius3 first segment did not reproduce House collision")
expect(clearHouse(start,radius4[2].Position),"recorded radius4 first segment is no longer clear")
expect(not Rules.clearPath(radius2,start,project,clearHouse),"a computed Success with colliding radius2 movement was accepted")
expect(not Rules.clearPath(radius3,start,project,clearHouse),"a computed Success with colliding radius3 movement was accepted")
expect(Rules.clearPath(radius4,start,project,clearHouse),"the clear radius4 geometry was rejected")
local smallest
for index,candidate in ipairs({radius2,radius3,radius4}) do
 if Rules.clearPath(candidate,start,project,clearHouse) then smallest=({2,3,4})[index]; break end
end
expect(smallest==4,"fallback did not retain the smallest genuinely clear candidate")
local firstPassed=path(point(-196,-172),point(-184,-184))
expect(clearHouse(start,firstPassed[2].Position),"late-blockage fixture starts blocked")
expect(not Rules.clearPath(firstPassed,start,project,clearHouse),"checking only the first segment let a later House collision through")

local visited,segments={},{}
expect(Rules.clearPath(radius4,start,function(waypoint)
 table.insert(visited,waypoint)
 return waypoint.Position
end,function(from,to)
 table.insert(segments,{from=from,to=to})
 return clearHouse(from,to)
end),"clear path traversal failed")
expect(#visited==3 and visited[1]==radius4[1] and visited[2]==radius4[2] and visited[3]==radius4[3],"validation skipped a computed waypoint")
expect(#segments==3 and segments[1].from==start and segments[1].to==start and segments[2].from==start and segments[2].to==radius4[2].Position
 and segments[3].from==radius4[2].Position and segments[3].to==goal,"validation did not use the live origin and all contiguous segments")
local visitedBeforeReject=0
expect(not Rules.clearPath(radius2,start,project,function(from,to)
 visitedBeforeReject+=1
 return clearHouse(from,to)
end) and visitedBeforeReject==2,"unsafe first movement segment did not immediately reject the route")
for _,value in ipairs({true,"clear",1,false}) do
 expect(Rules.clearPath(radius4,start,project,function() return value end)==(value==true),"nonboolean collision result was accepted")
end
expect(not Rules.clearPath(radius4,start,project,function() return nil end),"missing collision verdict was accepted")
expect(not Rules.clearPath(radius4,start,project,function() error("engine check failed") end),"engine collision failure did not reject the route")
expect(not Rules.clearPath(radius4,start,function() error("invalid waypoint") end,clearHouse),"waypoint projection failure did not reject the route")
expect(not Rules.clearPath(radius4,start,function() return nil end,clearHouse),"missing projected waypoint was accepted")
expect(not Rules.clearPath(radius4,start,function() return false end,clearHouse),"false projected waypoint was accepted")
for _,value in ipairs({false,"path",{},{radius4[1]}}) do expect(not Rules.clearPath(value,start,project,clearHouse),"invalid or vacuous route was accepted") end
expect(not Rules.clearPath(nil,start,project,clearHouse),"missing route was accepted")
expect(not Rules.clearPath(radius4,nil,project,clearHouse),"missing live unit position was accepted")
expect(not Rules.clearPath(radius4,false,project,clearHouse),"false live unit position was accepted")
expect(not Rules.clearPath(radius4,start,nil,clearHouse),"missing projection callback was accepted")
expect(not Rules.clearPath(radius4,start,project,nil),"missing movement collision callback was accepted")
expect(radius4[1].Position==start and radius4[2].Position.X==-195.8779 and start.X==-190.0693,"path acceptance mutated source geometry")

-- Recorded 19:45 live start and raw waypoint2: no roof projection, but all
-- radii cut into the touching House staircase on the first ground segment.
local woodStart=point(-253.794921875,-173.57557678222656)
local houses={{X=-248,Z=-160},{X=-264,Z=-168},{X=-272,Z=-184}}
local function clearRect(from,to,rect)
 local enter,leave=0,1
 for _,axis in ipairs({"X","Z"}) do
  local origin,delta=from[axis],to[axis]-from[axis]
  local low,high=rect[axis]-9.8,rect[axis]+9.8
  if math.abs(delta)<1e-12 then
   if origin<low or origin>high then return true end
  else
   local first,last=(low-origin)/delta,(high-origin)/delta
   if first>last then first,last=last,first end
   enter,leave=math.max(enter,first),math.min(leave,last)
   if enter>leave then return true end
  end
 end
 return false
end
local function clearHouses(from,to)
 for _,house in ipairs(houses) do if not clearRect(from,to,house) then return false end end
 return true
end
for _,wp2 in ipairs({point(-256.98138427734375,-180.91360473632812),point(-256.7217712402344,-181.0209503173828),point(-256.47235107421875,-181.11424255371094)}) do
 local clear,index=Rules.clearPath({{Position=woodStart},{Position=wp2}},woodStart,project,clearHouses)
 expect(not clear and index==2,"recorded raw radius2/3/4 first movement did not reproduce House collision")
end
for _,offset in ipairs({point(0,-8),point(3,-5),point(8,0),point(8,-8)}) do
 local escape=point(woodStart.X+offset.X,woodStart.Z+offset.Z)
 expect(clearHouses(woodStart,escape) and clearHouses(escape,escape),"recorded safe escape prefix or endpoint intersected a House")
end
for _,offset in ipairs({point(0,8),point(8,8),point(-8,0),point(-8,-8)}) do
 expect(not clearHouses(woodStart,point(woodStart.X+offset.X,woodStart.Z+offset.Z)),"unsafe direction through touching Houses was accepted")
end
local toward=point(-256.98138427734375,-180.91360473632812)
local candidates=Rules.escapeCandidates(woodStart.X,woodStart.Z,toward.X,toward.Z)
expect(#candidates==8,"local escape candidates are not bounded to eight")
local unique={}
for index,candidate in ipairs(candidates) do
 expect(math.max(math.abs(candidate.X-woodStart.X),math.abs(candidate.Z-woodStart.Z))==8,"escape candidate changed the observed eight-stud step")
 expect(not unique[candidate.index] and (index==1 or candidate.distance>=candidates[index-1].distance),"escape candidates duplicate or ignore blocked-waypoint priority")
 unique[candidate.index]=true
end
local escapes=Rules.selectEscapes(candidates,function(candidate) return clearHouses(woodStart,candidate) and clearHouses(candidate,candidate) end)
expect(#escapes==2 and escapes[1].index==7 and escapes[2].index==8,"actual start did not select the closest safe south / southeast origins")
expect(same(Rules.escapeRadii(2),{3,4}) and same(Rules.escapeRadii(3),{5,6}) and same(Rules.escapeRadii(4),{6,8}),"escape path did not prefer full-body diagonal clearance")
expect(same(Rules.escapeRadii(0.1),{1}),"duplicate escape radii wasted the bounded engine budget")
local attempts=0
for _=1,10 do local nextCall=Rules.nextComputeCall(attempts); if nextCall then attempts=nextCall end end
expect(attempts==7 and Rules.nextComputeCall(attempts)==nil,"engine calls exceeded the hard seven-call budget")
for _,invalid in ipairs({-1,0.5,7,8,math.huge,0/0,"0",false}) do expect(Rules.nextComputeCall(invalid)==nil,"invalid compute budget bypassed the hard limit") end
expect(Rules.nextComputeCall(nil)==nil,"missing compute budget bypassed the hard limit")
local escape=escapes[1]
local after={{Position=escape},{Position=point(escape.X,-196)},{Position=point(-284,-196)}}
local combined=Rules.prepend(after,escape)
expect(#combined==#after+1 and combined[1].Position==escape and combined[2]==after[1],"prefix assembly skipped the computed waypoint1 or copied over it")
local movement={}
expect(Rules.clearPath(combined,woodStart,project,function(from,to) table.insert(movement,{from=from,to=to}); return clearHouses(from,to) end),"safe prefix did not join the clear external detour")
expect(#movement==4 and movement[1].from==woodStart and movement[1].to==escape and movement[2].from==escape and movement[2].to==after[1].Position,"accepted route did not start with normal live-to-prefix movement and validate waypoint1")
local shiftedFirst={{Position=point(-264,-168)},{Position=point(-284,-196)}}
local unsafePrefix=Rules.prepend(shiftedFirst,escape)
local clear,index=Rules.clearPath(unsafePrefix,woodStart,project,clearHouses)
expect(not clear and index==2,"a safe prefix concealed an unsafe origin-to-computed-waypoint1 segment")
expect(not Rules.clearPath(combined,point(-264,-168),project,clearHouses),"validation reused stale live origin after ComputeAsync")
expect(#after==3 and after[1].Position==escape and combined[2]==after[1],"prefix assembly mutated engine waypoint source")
local calls=0
local firstTwo=Rules.selectEscapes(candidates,function() calls+=1; return true end)
expect(#firstTwo==2 and calls==2,"selector computed or evaluated a third safe escaping origin")
local duplicate={candidates[1],candidates[1],candidates[2],candidates[3]}
calls=0
expect(#Rules.selectEscapes(duplicate,function() calls+=1; return true end)==2 and calls==2,"duplicate origins consumed the safe-origin budget")
expect(#Rules.selectEscapes(candidates,function() return "safe" end)==0,"nonboolean prefix safety was accepted")
expect(#Rules.selectEscapes(candidates,function() error("collision query failure") end)==0,"failed prefix collision query was accepted")
for _,invalid in ipairs({0,-1,math.huge,0/0,"2",false,1e308}) do expect(Rules.escapeRadii(invalid)==nil,"invalid escape radius reached engine") end
expect(Rules.escapeRadii(nil)==nil,"missing escape radius reached engine")
expect(Rules.escapeCandidates(0/0,0,0,0)==nil and Rules.escapeCandidates(0,0,math.huge,0)==nil and Rules.escapeCandidates(1e308,1e308,0,0)==nil,"invalid or overflowing escape geometry was accepted")
expect(Rules.selectEscapes(nil,function() return true end)==nil and Rules.selectEscapes(candidates,nil)==nil,"invalid selector accepted")
expect(Rules.prepend({},escape)==nil and Rules.prepend(after,nil)==nil and Rules.prepend(after,false)==nil,"vacuous prefix route accepted")

expect(Rules.waypointReached(0) and Rules.waypointReached(0.05),"actual waypoint arrival was rejected")
expect(not Rules.waypointReached(0.050001) and not Rules.waypointReached(0.5) and not Rules.waypointReached(0.999),"early turning still skips a waypoint within one stud")
for _,value in ipairs({-0.01,math.huge,-math.huge,0/0,"0",false}) do expect(not Rules.waypointReached(value),"invalid waypoint distance was accepted") end
expect(not Rules.waypointReached(nil),"missing waypoint distance was accepted")
print(string.format("PASS: %d bounded path radii / recorded House collision / full live-segment / exact-waypoint checks (pure, not engine)",checks))
