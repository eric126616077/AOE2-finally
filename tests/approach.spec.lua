local Approach=require("../src/ServerScriptService/ServerModules/ApproachRules")
local Geometry=require("../src/ServerScriptService/ServerModules/MeleeRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function near(a,b) return math.abs(a-b)<1e-6 end
local function distanceToFarm(point)
 local dx,dz=math.max(0,math.abs(point.X+228)-12),math.max(0,math.abs(point.Z+156)-12)
 return math.sqrt(dx*dx+dz*dz)
end
local function blocksBarracks(point)
 -- Barracks at (-200,-156), footprint 24; full collision half-width is 2.
 return point.X+2>-212 and point.X-2<-188 and point.Z+2>-168 and point.Z-2<-144
end
local function usable(point)
 return math.abs(point.X)<=381 and math.abs(point.Z)<=381 and not blocksBarracks(point) and distanceToFarm(point)<=5
end
local candidates=assert(Geometry.candidates(-228,-156,12,12,2,5))
local workers={{X=-206.075,Z=-169.907},{X=-203.370,Z=-169.977}}
for _,worker in ipairs(workers) do
 -- The former nearest edge + four-stud outward goal overlaps the adjacent Barracks.
 local dx,dz=worker.X+216,worker.Z+168
 local length=math.sqrt(dx*dx+dz*dz)
 local oldGoal={X=-216+dx/length*4,Z=-168+dz/length*4}
 expect(blocksBarracks(oldGoal),"recorded Farm worker did not reproduce blocked original goal")
 local point=Approach.nearest(candidates,worker.X,worker.Z,nil,usable)
 expect(point and point.index==15,"normal Farm builder failed to choose open southeast corner")
 expect(not blocksBarracks(point) and distanceToFarm(point)<=5,"alternate work goal overlaps Barracks or changes work range")
 local blacklist={[point.index]=true}
 local alternative=Approach.nearest(candidates,worker.X,worker.Z,blacklist,usable)
 expect(alternative and alternative.index~=point.index and usable(alternative),"failed route did not advance to another legal face")
 for _,candidate in ipairs(candidates) do blacklist[candidate.index]=true end
 expect(not Approach.nearest(candidates,worker.X,worker.Z,blacklist,usable),"exhausted perimeter fabricated a route")
end
for _,kind in ipairs({"build","gather","deliver","repair","garrison"}) do expect(Approach.isWork(kind),"village interaction excluded from common approach") end
for _,kind in ipairs({"move","attack","custom","Build",false,0}) do expect(not Approach.isWork(kind),"unknown order entered worker interaction flow") end
expect(not Approach.isWork(nil),"nil order entered worker interaction flow")

local eastBlocked={[1]=true}
local farmEast=Approach.nearest(candidates,-210,-156,nil,function(point) return point.index==1 end)
expect(farmEast and farmEast.index==1,"unobstructed nearest face was not available")
expect(not Approach.nearest(candidates,-210,-156,eastBlocked,function(point) return point.index==1 end),"unreachable face remained available")
expect(Approach.nearest(candidates,-210,-156,eastBlocked,function() return true end).index~=1,"path blacklist did not affect actual selection")
local called=0
Approach.nearest(candidates,-210,-156,eastBlocked,function(point) called+=1; expect(point.index~=1,"blacklisted goal checked against engine again"); return true end)
expect(called==15,"blacklisted face was not skipped")
expect(not Approach.nearest(candidates,0,0,nil,function() return false end),"fully obstructed target received work goal")
expect(not Approach.nearest(candidates,0,0,nil,function() return nil end),"unknown engine eligibility was treated as clear")
expect(not Approach.nearest(candidates,0,0,nil,function() return "clear" end),"nonboolean collision verdict accepted")
local tie={{X=0,Z=1,index=2},{X=0,Z=-1,index=1}}
expect(Approach.nearest(tie,0,0,nil,function() return true end).index==1,"equal distances changed choice with candidate iteration order")
expect(Approach.nearest(tie,0,0,{[1]=true},function() return true end).index==2,"valid second candidate lost after tie choice failed")

-- Every configured-sized rectangle retains open south/west options despite a blocked east side.
for _,half in ipairs({4,8,12,16,32}) do
 for _,current in ipairs({{X=half+20,Z=0},{X=half+20,Z=-half-3},{X=0,Z=-half-20}}) do
  local points=assert(Geometry.candidates(0,0,half,half,2,5))
  local free=function(point) return point.X<0 or point.Z<-half-1.8 end
  local blacklist,used={},{}
  for attempt=1,16 do
   local point=Approach.nearest(points,current.X,current.Z,blacklist,free)
   if not point then break end
   expect(free(point) and not used[point.index],"candidate retry repeated a failed face or selected an obstructed side")
   used[point.index],blacklist[point.index]=true,true
   local dx,dz=math.max(0,math.abs(point.X)-half),math.max(0,math.abs(point.Z)-half)
   expect(math.sqrt(dx*dx+dz*dz)<=5+1e-7,"candidate retry expanded interaction range")
  end
  expect(next(used)~=nil,"target with open perimeter has no selectable approach")
  expect(not Approach.nearest(points,current.X,current.Z,blacklist,free),"perimeter retries do not terminate")
 end
end
for _,invalid in ipairs({math.huge,-math.huge,0/0,"0",false}) do
 expect(not Approach.nearest(candidates,invalid,0,nil,function() return true end),"invalid current X accepted")
 expect(not Approach.nearest(candidates,0,invalid,nil,function() return true end),"invalid current Z accepted")
 expect(not Approach.nearest({{X=invalid,Z=0,index=1}},0,0,nil,function() return true end),"invalid candidate X accepted")
 expect(not Approach.nearest({{X=0,Z=invalid,index=1}},0,0,nil,function() return true end),"invalid candidate Z accepted")
 expect(not Approach.nearest({{X=0,Z=0,index=invalid}},0,0,nil,function() return true end),"invalid candidate index accepted")
end
for _,index in ipairs({0,-1,17,1.5}) do expect(not Approach.nearest({{X=0,Z=0,index=index}},0,0,nil,function() return true end),"out-of-range candidate index accepted") end
expect(not Approach.nearest({{X=1,Z=0,index=1},{X=-1,Z=0,index=1}},0,0,nil,function() return true end),"duplicate stable candidate index accepted")
expect(not Approach.nearest({{X=1e308,Z=1e308,index=1}},-1e308,-1e308,nil,function() return true end),"overflowing distance selected as nearest")
expect(not Approach.nearest(false,0,0,nil,function() return true end),"invalid candidate list accepted")
expect(not Approach.nearest(candidates,0,0,false,function() return true end),"invalid path blacklist accepted")
expect(not Approach.nearest(candidates,0,0,nil,nil),"missing collision predicate accepted")
expect(not Approach.nearest({},0,0,nil,function() return true end),"empty perimeter invented a goal")
expect(candidates[1].index==1 and eastBlocked[1]==true,"selection mutated source candidates or blacklist")
print(string.format("PASS: %d blocked Farm / shared work approach / failed-face selection checks",checks))
