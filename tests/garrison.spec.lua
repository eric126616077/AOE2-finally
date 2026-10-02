local GarrisonRules=require("../src/ServerScriptService/ServerModules/GarrisonRules")
local checks=0
local function expect(ok,message)
 checks+=1
 assert(ok,message)
end
local bad={0/0,math.huge,-math.huge,"1",false}
local config={arrows={villager=1,archer=1,infantry=0.5},blocked={siege=true}}
local townCenter={garrison={capacity=15,maxArrows=10}}
local tower={garrison={capacity=5,maxArrows=5,blocked={cavalry=true}}}
local house={}

-- 容量
expect(GarrisonRules.capacity(townCenter)==15,"town center capacity lost")
expect(GarrisonRules.capacity(house)==0 and GarrisonRules.capacity(nil)==0,"building without garrison had capacity")
for _,value in ipairs(bad) do expect(GarrisonRules.capacity({garrison={capacity=value}})==0,"invalid capacity accepted") end
expect(GarrisonRules.capacity({garrison={capacity=0}})==0 and GarrisonRules.capacity({garrison={capacity=2.5}})==0,"non-positive or fractional capacity accepted")

-- 進入條件
expect(GarrisonRules.canEnter(config,townCenter,true,0,"villager",40),"villager could not enter the town center")
expect(GarrisonRules.canEnter(config,townCenter,true,14,"cavalry",125),"cavalry could not take the last town center slot")
expect(not GarrisonRules.canEnter(config,townCenter,true,15,"villager",40),"full building accepted another unit")
expect(not GarrisonRules.canEnter(config,townCenter,false,0,"villager",40),"unfinished building accepted a unit")
expect(not GarrisonRules.canEnter(config,townCenter,nil,0,"villager",40),"unknown completion accepted a unit")
expect(not GarrisonRules.canEnter(config,house,true,0,"villager",40),"house accepted a garrison")
expect(not GarrisonRules.canEnter(config,townCenter,true,0,"siege",280),"siege entered a building")
expect(not GarrisonRules.canEnter(config,tower,true,0,"cavalry",125),"cavalry entered a tower")
expect(GarrisonRules.canEnter(config,tower,true,4,"archer",40),"archer could not enter a tower")
expect(not GarrisonRules.canEnter(config,townCenter,true,0,"villager",0),"dead unit entered a building")
expect(not GarrisonRules.canEnter(config,townCenter,true,0,nil,40),"unknown class entered a building")
expect(not GarrisonRules.canEnter(nil,townCenter,true,0,"villager",40),"missing config accepted a unit")
for _,value in ipairs(bad) do
 expect(not GarrisonRules.canEnter(config,townCenter,true,value,"villager",40),"invalid count accepted")
 expect(not GarrisonRules.canEnter(config,townCenter,true,0,"villager",value),"invalid HP accepted")
end
expect(not GarrisonRules.canEnter(config,townCenter,true,-1,"villager",40),"negative count accepted")
expect(select(2,GarrisonRules.canEnter(config,townCenter,true,15,"villager",40))~=nil,"rejection had no reason")

-- 額外箭數
expect(GarrisonRules.arrows(config.arrows,{},10)==0,"empty building fired extra arrows")
expect(GarrisonRules.arrows(config.arrows,{villager=3},10)==3,"villagers did not add one arrow each")
expect(GarrisonRules.arrows(config.arrows,{villager=2,archer=2},10)==4,"archers and villagers did not stack")
expect(GarrisonRules.arrows(config.arrows,{infantry=1},10)==0,"a single infantry added a full arrow")
expect(GarrisonRules.arrows(config.arrows,{infantry=3},10)==1,"infantry did not add half an arrow each")
expect(GarrisonRules.arrows(config.arrows,{infantry=1,villager=1},10)==1,"fractional arrows were rounded up")
expect(GarrisonRules.arrows(config.arrows,{cavalry=5,monk=3},10)==0,"non-shooting classes added arrows")
expect(GarrisonRules.arrows(config.arrows,{villager=15},10)==10,"arrow cap ignored")
expect(GarrisonRules.arrows(config.arrows,{villager=5},nil)==0,"missing cap fired extra arrows")
expect(GarrisonRules.arrows(nil,{villager=5},10)==0 and GarrisonRules.arrows(config.arrows,nil,10)==0,"invalid tables fired arrows")
for _,value in ipairs(bad) do
 expect(GarrisonRules.arrows(config.arrows,{villager=value},10)==0,"invalid count fired arrows")
 expect(GarrisonRules.arrows({villager=value},{villager=3},10)==0,"invalid weight fired arrows")
 expect(GarrisonRules.arrows(config.arrows,{villager=3},value)==0,"invalid cap fired arrows")
end
for count=0,20 do
 local arrows=GarrisonRules.arrows(config.arrows,{villager=count},10)
 expect(arrows==math.min(count,10) and arrows%1==0,"arrow count was not a capped integer")
end

-- 回復與離開
expect(GarrisonRules.heal(10,40,1,1)==11,"garrisoned unit did not heal")
expect(GarrisonRules.heal(39.5,40,1,1)==40,"healing exceeded max HP")
expect(GarrisonRules.heal(55,40,1,1)==55,"healing reduced HP above the current maximum")
expect(GarrisonRules.heal(0,40,1,1)==0,"dead unit healed")
for _,value in ipairs(bad) do
 expect(GarrisonRules.heal(10,40,value,1)==10 and GarrisonRules.heal(10,40,1,value)==10,"invalid heal input changed HP")
end
expect(GarrisonRules.heal(10,40,-1,1)==10,"negative heal rate changed HP")
expect(GarrisonRules.restoreHP(25,40)==25,"stored HP lost on exit")
expect(GarrisonRules.restoreHP(55,40)==40,"stored HP exceeded the new maximum")
expect(GarrisonRules.restoreHP(0,40)==1,"unit left the building dead")
expect(GarrisonRules.restoreHP(nil,40)==40 and GarrisonRules.restoreHP(0/0,40)==40,"invalid stored HP did not fall back to full")
expect(GarrisonRules.restoreHP(10,0/0)==1,"invalid maximum produced invalid HP")

print(string.format("PASS: %d garrison capacity / entry / extra-arrow / heal checks",checks))
