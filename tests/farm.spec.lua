local Rules=require("../src/ServerScriptService/ServerModules/FarmRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local farm,other,villager,second={name="farm"},{name="other"},{name="villager"},{name="second"}

-- One worker per field: gathering there or returning from a delivery keeps the claim.
expect(Rules.holds("gather",farm,nil,farm),"gathering villager lost its field")
expect(Rules.holds("deliver",{name="mill"},farm,farm),"delivering villager lost the field it returns to")
expect(not Rules.holds("gather",other,nil,farm),"villager on another field held this one")
expect(not Rules.holds("deliver",{name="mill"},other,farm),"delivery to another field held this one")
expect(not Rules.holds("move",farm,farm,farm) and not Rules.holds("attack",farm,nil,farm),"non-farming order held a field")
expect(not Rules.holds(nil,nil,nil,farm) and not Rules.holds("gather",nil,nil,nil),"missing order or field produced a claim")
expect(Rules.free(nil,villager) and Rules.free(villager,villager),"free field or own field rejected")
expect(not Rules.free(villager,second) and not Rules.free(villager,nil),"occupied field accepted a second villager")

-- Mill prepaid queue bounds.
expect(Rules.canQueue(0,40) and Rules.canQueue(39,40) and not Rules.canQueue(40,40) and not Rules.canQueue(41,40),"queue limit incorrect")
expect(Rules.canUnqueue(1) and not Rules.canUnqueue(0),"unqueue bounds incorrect")
for _,invalid in ipairs({-1,1.5,math.huge,-math.huge,0/0,"1",false}) do
 expect(not Rules.canQueue(invalid,40) and not Rules.canQueue(0,invalid),"invalid queue value accepted")
 expect(not Rules.canUnqueue(invalid),"invalid unqueue value accepted")
 expect(Rules.reseedSource(invalid,false,false)==nil,"invalid queue value reseeded a field")
end

-- Reseeding: prepaid farms first, wood only for explicit orders or allowed automatic reseeding.
expect(Rules.reseedSource(2,false,false)=="queue" and Rules.reseedSource(1,true,true)=="queue","prepaid farm not used first")
expect(Rules.reseedSource(0,true,false)=="wood","explicit reseed order did not charge wood")
expect(Rules.reseedSource(0,false,true)=="wood","automatic reseed did not charge wood")
expect(Rules.reseedSource(0,false,false)==nil and Rules.reseedSource(0,nil,nil)==nil,"field reseeded without payment source")
print("PASS: "..checks.." farm single-worker / prepaid queue / reseed source checks (pure rules; not Studio Play)")
