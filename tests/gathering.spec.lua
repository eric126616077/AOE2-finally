local Gathering=require("../src/ServerScriptService/ServerModules/GatheringRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
for _,key in ipairs({"food","wood","gold","stone"}) do
 expect(Gathering.accepts(Config.Buildings.TownCenter,key),"main base rejected "..key)
 expect(Gathering.accepts(Config.Buildings.Market,key),"market rejected "..key)
 expect(Gathering.accepts(Config.Buildings.Castle,key),"castle rejected "..key)
 expect(not Gathering.accepts(Config.Buildings.House,key),"housing accepted resources")
 expect(Gathering.returnKind(key,nil)==key,"delivery lost exhausted resource kind")
end
expect(Gathering.accepts(Config.Buildings.MiningCamp,"gold") and Gathering.accepts(Config.Buildings.MiningCamp,"stone"),"mining camp rejected mined resources")
expect(not Gathering.accepts(Config.Buildings.MiningCamp,"food") and not Gathering.accepts(Config.Buildings.MiningCamp,"wood"),"mining camp accepted other resources")
expect(Gathering.accepts(Config.Buildings.Mill,"food") and not Gathering.accepts(Config.Buildings.Mill,"gold"),"mill compatibility incorrect")
expect(Gathering.accepts(Config.Buildings.LumberCamp,"wood") and not Gathering.accepts(Config.Buildings.LumberCamp,"stone"),"lumber camp compatibility incorrect")
expect(not Gathering.accepts(Config.Buildings.MiningCamp,"unknown"),"invalid carry type accepted")
expect(Gathering.returnKind("gold","stone")=="stone","switching from gold to exhausted stone resumed wrong resource")
expect(Gathering.returnKind("gold","unknown")=="gold","invalid new work type replaced carried resource")
expect(Gathering.returnKind("",nil)==nil,"empty worker fabricated resource kind")
for _,capacity in ipairs({Config.Units.villager.carryCapacity,Config.Units.villager.carryCapacity+Config.Technologies.Wheelbarrow.effect.carry}) do
 for _,rate in ipairs({3,3.75,3.6}) do
  for _,initial in ipairs({1,9,10,11,650,800}) do
   local available,carrying,delivered=initial,0,0
   repeat
    local taken=Gathering.takeAmount(available,carrying,capacity,rate)
    available-=taken; carrying+=taken
    expect(carrying<=capacity and carrying>=0 and available>=0,"worker exceeded capacity or depleted below zero")
    expect(math.abs(available+carrying+delivered-initial)<0.000001,"gathering created or lost resource")
    if carrying>=capacity or available<=0 then delivered+=carrying; carrying=0 end
   until available<=0
   expect(math.abs(delivered-initial)<0.000001 and carrying==0,"last partial load lost during depletion")
  end
 end
end
expect(Gathering.takeAmount(800,10,10,3)==0,"full worker extracted more ore")
expect(Gathering.takeAmount(800,15,10,3)==0,"capacity loss erased carried ore")
for _,invalid in ipairs({-1,math.huge,-math.huge,0/0,"10",false}) do
 expect(Gathering.takeAmount(invalid,0,10,3)==0,"invalid amount extracted ore")
 expect(Gathering.takeAmount(800,invalid,10,3)==0,"invalid carrying extracted ore")
 expect(Gathering.takeAmount(800,0,invalid,3)==0,"invalid capacity extracted ore")
 expect(Gathering.takeAmount(800,0,10,invalid)==0,"invalid rate extracted ore")
end
print(string.format("PASS: %d gathering conservation / delivery checks",checks))
