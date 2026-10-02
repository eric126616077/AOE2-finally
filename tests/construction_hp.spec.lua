local Rules=require("../src/ServerScriptService/ServerModules/ConstructionRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function near(a,b) return math.abs(a-b)<1e-7 end
-- Actual 2026-09-30 20:58 completed castle: not a theoretical epsilon fixture.
local observed=4799.9999999999991
expect(observed<4800 and 4800-observed<1e-10,"actual castle regression decimal did not preserve its deficit")
expect(Rules.addWorkHP(observed,4800,0,45)==4800,"actual completed castle dust is still classified as damaged")
expect(Rules.addWorkHP(4800-1,4800,0,45)==4799,"one real HP hit was healed at completion")
expect(Rules.addWorkHP(4800-31,4800,0,45)==4769,"multiple real hits were healed")
expect(Rules.addWorkHP(4800-0.00001,4800,0,45)==4800-0.00001,"non-dust deficit was erased")
expect(Rules.addWorkHP(4800,4800,0,45)==4800,"exact full HP changed")
expect(Rules.addWorkHP(100,4800,0,45)==100,"paused construction healed real damage")
local function simulate(maximum,duration,workers,steps,hits)
 local work,hp,tick=0,assert(Rules.initialHP(maximum)),0
 repeat
  tick+=1
  local nextWork,gain,complete=Rules.stepWork(work,duration,workers,steps[(tick-1)%#steps+1])
  hp=assert(Rules.addWorkHP(hp,maximum,gain,duration)); work=nextWork
  if hits[tick] then hp-=hits[tick] end
  if complete then return hp,tick end
  assert(tick<20000,"simulation has no finite deadline")
 until false
end
for _,entry in ipairs({{4800,45},{2400,25},{800,12},{1300,20},{1700,4},{300,7},{4500,80},{550,8},{450,4}}) do
 for _,workers in ipairs({1,2,3,16}) do
  for _,steps in ipairs({{.1},{.13,.21,.17,.3},{.299999999,.100000001,.19}}) do
   local hp=simulate(entry[1],entry[2],workers,steps,{})
   expect(hp==entry[1],"undamaged complete construction is not exact max")
   local damaged=simulate(entry[1],entry[2],workers,steps,{[1]=1})
   expect(near(damaged,entry[1]-1) and entry[1]-damaged>.999999,"one normal hit during real work was erased")
   local repeated=simulate(entry[1],entry[2],workers,steps,{[1]=1,[2]=2,[3]=3})
   expect(near(repeated,entry[1]-6) and entry[1]-repeated>5.999999,"repeated damage during real work was erased")
   local fractional=simulate(entry[1],entry[2],workers,steps,{[1]=0.5})
   expect(near(fractional,entry[1]-0.5) and entry[1]-fractional>.499999,"real fractional combat damage was erased")
  end
 end
end
-- Initial allocation has no floor loss; finish still only adds actual work HP.
local house=simulate(550,8,2,{.13,.21,.17},{})
expect(house==550,"normal House retained its old 0.5 floor deficit")
expect(Rules.initialHP(550)==82.5 and Rules.initialHP(450)==67.5,"initial fractional 15 percent was rounded down")
expect(Rules.initialHP(.5)==.5 and Rules.initialHP(1)==1 and Rules.initialHP(5)==1,"low max HP start exceeds its own maximum")
for _,maximum in ipairs({1,55,4800,1000000,1000000000,9007199254740991}) do
 expect(Rules.addWorkHP(maximum-1,maximum,0,45)==maximum-1,"relative tolerance swallowed 1 HP at a larger scale")
end
local invalid={0/0,math.huge,-math.huge,"1",false}
for _,value in ipairs(invalid) do
 expect(Rules.initialHP(value)==nil,"invalid initial maximum accepted")
 expect(Rules.addWorkHP(value,4800,1,45)==nil,"invalid HP accepted")
 expect(Rules.addWorkHP(720,value,1,45)==nil,"invalid max accepted")
 expect(Rules.addWorkHP(720,4800,value,45)==nil,"invalid work accepted")
 expect(Rules.addWorkHP(720,4800,1,value)==nil,"invalid duration accepted")
end
expect(Rules.addWorkHP(-1,4800,1,45)==nil,"negative HP accepted")
expect(Rules.addWorkHP(4801,4800,1,45)==nil,"over-max current HP accepted")
expect(Rules.addWorkHP(720,0,1,45)==nil,"zero max accepted")
expect(Rules.addWorkHP(720,4800,-1,45)==nil,"negative work accepted")
expect(Rules.addWorkHP(720,4800,46,45)==nil,"work exceeds full duration")
expect(Rules.addWorkHP(720,4800,1,0)==nil,"zero duration accepted")
expect(Rules.addWorkHP(720,1e20,1,45)==nil,"max beyond exact integer HP range accepted")
expect(Rules.addWorkHP(720,4800,45,45)==4800,"normal full work no longer respects max clamp")
expect(Rules.initialHP(0)==nil and Rules.initialHP(-1)==nil and Rules.initialHP(1e20)==nil,"initial maximum is not bounded")
print(string.format("PASS: %d actual castle dust / bounded tolerance / work accumulation / preserved combat damage checks",checks))
