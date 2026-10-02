local Rules=require("../src/ServerScriptService/ServerModules/AutoWorkRules")
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end

expect(Rules.builderCount(2,2)==1,"house-sized site should recruit one villager")
expect(Rules.builderCount(3,3)==2,"barracks-sized site should recruit two villagers")
expect(Rules.builderCount(8,8)==3,"castle-sized site should recruit three villagers")
expect(Rules.builderCount(8,8,2)==2,"builder count exceeded the server maximum")
for _,bad in ipairs({0,-1,0/0,math.huge}) do expect(Rules.builderCount(bad,2)==0,"invalid footprint recruited workers") end

local near,far,busy,building={},{},{},{}
local picked=Rules.pickBuilders({
 {unit=building,distance=1,idle=false,building=true},
 {unit=busy,distance=5,idle=false},
 {unit=far,distance=30,idle=true},
 {unit=near,distance=10,idle=true},
},2,40)
expect(picked[1]==near and picked[2]==far,"idle villagers should be preferred over nearby gatherers")
for _,unit in ipairs(picked) do expect(unit~=building,"villager already constructing was pulled away") end
picked=Rules.pickBuilders({{unit=busy,distance=5,idle=false},{unit=far,distance=80,idle=true}},1,40)
expect(picked[1]==busy,"a much closer gatherer should help when idle villagers are far away")
expect(#Rules.pickBuilders({{unit=building,distance=1,building=true}},1,40)==0,"only constructing villagers fabricated a builder")
expect(#Rules.pickBuilders({{unit=near,distance=0/0,idle=true}},1,40)==0,"nonfinite distance accepted")
expect(#Rules.pickBuilders("bad",1,40)==0 and #Rules.pickBuilders({},0,40)==0,"malformed builder request accepted")

expect(not Rules.idleReady(10,11,2),"villager re-tasked before idle delay")
expect(Rules.idleReady(10,12,2),"idle villager never re-tasked")
expect(not Rules.idleReady(10,20,2,nil,true),"player-held villager was auto-tasked")
expect(not Rules.idleReady(10,20,2,25),"retry cooldown ignored")
expect(Rules.idleReady(10,25,2,25),"retry cooldown never expired")
expect(not Rules.idleReady(nil,20,2),"unknown idle start accepted")

local pref=Rules.dropoffPreference({"gold","stone"})
expect(pref and pref[1]=="gold" and pref[2]=="stone","mining camp preference lost")
expect(Rules.dropoffPreference({"food","wood","gold","stone"})==nil,"all-resource drop-off should not bias villagers")
expect(Rules.dropoffPreference(nil)==nil,"non-drop-off building produced preference")

local site,dropoff,tree,berries={},{},{},{}
local action,target=Rules.choose({site=site,carrying=10,dropoff=dropoff})
expect(action=="build" and target==site,"nearby construction should come first")
action,target=Rules.choose({carrying=10,dropoff=dropoff})
expect(action=="deliver" and target==dropoff,"carrying villager should deliver")
expect(Rules.choose({carrying=10})==nil,"full villager without drop-off should wait instead of failing repeatedly")
local key
action,target,key=Rules.choose({carrying=0,nearby={wood=tree,food=berries},priorities={"gold","wood","food"}})
expect(action=="gather" and target==tree and key=="wood","priority order not respected when nearest priority is missing")
expect(Rules.choose({carrying=0,nearby={},priorities={"food"}})==nil,"no nearby resource fabricated a gather target")
expect(Rules.choose({carrying=0,nearby={wood=tree},priorities={"bogus","wood"}})=="gather","unknown priority keys broke selection")
expect(Rules.choose(nil)==nil,"malformed context accepted")
print("PASS: "..count.." auto-work builder / idle / preference / choice checks")
