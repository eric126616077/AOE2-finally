local MonkRules=require("../src/ServerScriptService/ServerModules/MonkRules")
local checks=0
local function expect(ok,message)
 checks+=1
 assert(ok,message)
end
local bad={0/0,math.huge,-math.huge,"1",nil,false}

-- 招降目標
expect(MonkRules.canConvert("infantry",false,50,100,100),"full-faith monk cannot convert infantry")
expect(MonkRules.canConvert("villager",false,1,100,100),"villager cannot be converted")
expect(MonkRules.canConvert("siege",false,100,100,100),"siege cannot be converted")
expect(not MonkRules.canConvert("infantry",true,50,100,100),"buildings were convertible")
expect(not MonkRules.canConvert("monk",false,30,100,100),"enemy monks were convertible without Atonement")
expect(not MonkRules.canConvert("infantry",false,0,100,100),"dead unit was convertible")
expect(not MonkRules.canConvert("infantry",false,50,99.9,100),"monk converted before faith recharged")
expect(not MonkRules.canConvert(nil,false,50,100,100),"unknown class was convertible")
for _,value in ipairs(bad) do
 expect(not MonkRules.canConvert("infantry",false,value,100,100),"invalid target HP accepted")
 expect(not MonkRules.canConvert("infantry",false,50,value,100),"invalid faith accepted")
 expect(not MonkRules.canConvert("infantry",false,50,100,value),"invalid max faith accepted")
end

-- 招降判定：最短時間前不會成功，上限必定成功，中間依亂數。
for elapsed=0,3.9,0.1 do expect(not MonkRules.conversionSucceeds(elapsed,4,10,0.28,0),"conversion before minimum time") end
for elapsed=10,12 do expect(MonkRules.conversionSucceeds(elapsed,4,10,0.28,0.999),"conversion not guaranteed at maximum time") end
expect(MonkRules.conversionSucceeds(5,4,10,0.28,0.27),"low roll failed inside chance window")
expect(not MonkRules.conversionSucceeds(5,4,10,0.28,0.28),"roll equal to chance succeeded")
expect(not MonkRules.conversionSucceeds(5,4,10,-1,0),"negative chance succeeded")
expect(MonkRules.conversionSucceeds(5,4,10,2,0.99),"chance above one was not clamped")
expect(not MonkRules.conversionSucceeds(5,10,4,0.28,0),"inverted window accepted")
expect(not MonkRules.conversionSucceeds(-1,4,10,0.28,0),"negative elapsed accepted")
for _,value in ipairs(bad) do
 expect(not MonkRules.conversionSucceeds(value,4,10,0.28,0),"invalid elapsed accepted")
 expect(not MonkRules.conversionSucceeds(5,value,10,0.28,0),"invalid minimum accepted")
 expect(not MonkRules.conversionSucceeds(5,4,value,0.28,0),"invalid maximum accepted")
 expect(not MonkRules.conversionSucceeds(5,4,10,value,0),"invalid chance accepted")
 expect(not MonkRules.conversionSucceeds(5,4,10,0.28,value),"invalid roll accepted")
end
-- 模擬：每秒擲一次，所有結果都落在 [4,10] 秒內。
local random=Random and Random.new and Random.new(7) or nil
local seed=7
local function roll()
 if random then return random:NextNumber() end
 seed=(seed*1103515245+12345)%2147483648
 return seed/2147483648
end
local earliest,latest=math.huge,0
for _=1,2000 do
 local elapsed=0
 repeat elapsed+=1 until MonkRules.conversionSucceeds(elapsed,4,10,0.28,roll())
 earliest,latest=math.min(earliest,elapsed),math.max(latest,elapsed)
end
expect(earliest>=4 and latest<=10,"simulated conversion left the 4–10 second window")
expect(earliest<latest,"simulated conversions were not randomised")

-- 治療
expect(MonkRules.canHeal("infantry",false,true,10,75),"monk cannot heal wounded infantry")
expect(MonkRules.canHeal("monk",false,true,10,30),"monk cannot heal another monk")
expect(not MonkRules.canHeal("siege",false,true,10,280),"siege was healable")
expect(not MonkRules.canHeal("infantry",true,true,10,75),"building was healable")
expect(not MonkRules.canHeal("infantry",false,false,10,75),"enemy was healable")
expect(not MonkRules.canHeal("infantry",false,true,75,75),"full-HP unit was healable")
expect(not MonkRules.canHeal("infantry",false,true,0,75),"dead unit was healable")
for _,value in ipairs(bad) do
 expect(not MonkRules.canHeal("infantry",false,true,value,75),"invalid HP healable")
 expect(not MonkRules.canHeal("infantry",false,true,10,value),"invalid max HP healable")
end
expect(MonkRules.heal(10,75,2,1)==12,"heal rate wrong")
expect(MonkRules.heal(74,75,2,1)==75,"heal exceeded max HP")
expect(MonkRules.heal(0,75,2,1)==0,"heal revived a dead unit")
expect(MonkRules.heal(10,75,-2,1)==10,"negative heal applied")
expect(MonkRules.heal(10,75,2,0/0)==10,"NaN dt applied")

-- 信仰恢復
expect(MonkRules.regenFaith(0,100,25,5)==20,"faith regen rate wrong")
expect(MonkRules.regenFaith(99,100,25,5)==100,"faith exceeded maximum")
expect(MonkRules.regenFaith(0/0,100,25,0)==0,"NaN faith not reset")
expect(MonkRules.regenFaith(50,100,0,5)==50,"zero recharge time changed faith")
expect(MonkRules.regenFaith(50,0/0,25,5)==0,"invalid max faith accepted")
expect(MonkRules.regenFaith(150,100,25,-1)==100,"over-max faith not clamped")

print("Monk conversion / heal / faith rules:",checks,"checks passed")
