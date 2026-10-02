local Spatial=require("../src/ServerScriptService/ServerModules/SpatialRules")
local Production=require("../src/ServerScriptService/ServerModules/ProductionRules")
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local margin=Spatial.maxHalfFootprint(Config.Buildings,Config.Map.GridSize)
expect(margin==32,"configured castle half-footprint not included in target search")
local cells=Spatial.searchCells(60,margin,64)
expect(cells==2,"tower range search did not include large target center across cell boundary")
local towerX,castleX=56,144
expect(castleX-margin-towerX<60 and math.abs(math.floor(castleX/64)-math.floor(towerX/64))<=cells,"nearby castle edge missed despite being inside tower range")
for source=-256,256,8 do
 for target=-256,256,8 do
  for _,half in ipairs({4,8,16,32}) do
   for _,radius in ipairs({0,5,60,72,75,115}) do
    local edgeDistance=math.max(0,math.abs(target-source)-half)
    if edgeDistance<=radius then
     expect(math.abs(math.floor(target/64)-math.floor(source/64))<=Spatial.searchCells(radius,margin,64),"in-range target footprint escaped center search")
    end
   end
  end
 end
end
for _,invalid in ipairs({-1,math.huge,-math.huge,0/0,"60",false}) do
 expect(not Spatial.searchCells(invalid,32,64),"invalid radius accepted")
 expect(not Spatial.searchCells(60,invalid,64),"invalid target margin accepted")
 expect(not Spatial.searchCells(60,32,invalid),"invalid cell width accepted")
end
expect(not Spatial.searchCells(1e308,1e308,64),"overflowing finite search radius accepted")
expect(not Spatial.searchCells(60,32,0),"zero cell width accepted")
expect(not Spatial.maxHalfFootprint({Bad={size={X=math.huge,Y=2}}},8),"invalid building dimensions accepted")
expect(not Spatial.maxHalfFootprint(Config.Buildings,0/0),"non-finite grid dimensions accepted")

local source,replacement,otherSource={},{},{}
local state={technologies={},pendingTech={Forging=true,Armor=true},advancing=nil}
local jobs={[source]={key="Forging",state=state},[otherSource]={key="Armor",state=state}}
expect(not Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"pending research could queue twice")
expect(not Production.cancelResearch(state,source,jobs),"ordinary technology cancellation claimed an age transition")
expect(jobs[source]==nil and not state.pendingTech.Forging,"lost source left technology permanently pending")
expect(Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"technology could not restart in replacement building after source loss")
expect(jobs[otherSource]~=nil and state.pendingTech.Armor==true,"canceling one source erased other building research")
expect(not state.technologies.Forging,"canceled research was incorrectly completed")
Production.cancelResearch(state,source,jobs)
expect(Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"one-second cleanup following production cancellation relocked technology")
jobs[replacement]={key="Forging",state=state}; state.pendingTech.Forging=true
expect(not Production.canResearch(state.technologies,state.pendingTech,"Forging",2,2),"restarted research lost its reservation")
Production.cancelResearch(state,replacement,jobs)
state.advancing={building=source,age=3,remaining=20}
expect(not Production.cancelResearch(state,otherSource,jobs) and state.advancing~=nil,"wrong source canceled age advancement")
expect(Production.cancelResearch(state,source,jobs) and state.advancing==nil,"missing advancement source did not request clearing progress / remaining")
expect(not Production.cancelResearch(state,source,jobs),"duplicate age cleanup was not idempotent")
expect(not Production.canResearch({Forging=true},{},"Forging",2,2),"completed technology could be researched twice")
expect(not Production.canResearch({}, {},"Forging",1,2),"age prerequisite ignored")
expect(not Production.canResearch({}, {},"Forging",math.huge,2),"invalid research age accepted")
expect(Production.canResearch({}, {},"Forging",2,2),"normal research blocked")
print(string.format("PASS: %d server footprint-search / production-cancellation checks",count))
