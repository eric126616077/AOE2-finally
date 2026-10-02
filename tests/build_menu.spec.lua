-- scripts/verify.ps1 injects the actual Config and BuildMenuRules module.
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local function signature(items)
 local parts={}
 for _,item in ipairs(items) do table.insert(parts,item.kind..(item.locked and "*" or "")) end
 return table.concat(parts,",")
end
local function expectItems(config,page,age,expected,message)
 local items=BuildMenuRules.items(config,page,age)
 expect(signature(items)==expected,message..": "..signature(items))
 return items
end

local fixture={
 BuildOrder={"Old","Current","Next","Later","Default","BadAge","BadData","Missing"},
 Buildings={Old={minAge=1},Current={minAge=2},Next={minAge=3},Later={minAge=4},Default={},
  Unlisted={minAge=1},BadAge={minAge="2"},BadData="invalid"},
 BuildPages={{buildings={"Old","Current","Next","Later","Default","Old","Unlisted","BadAge","BadData","Missing","Unknown",false}},
  {buildings={}},{}},
}
expectItems(fixture,1,1,"Old,Current*,Default","dark age shows current and only next age")
expectItems(fixture,1,2,"Old,Current,Next*,Default","feudal age reveals castle age")
expectItems(fixture,1,3,"Old,Current,Next,Later*,Default","castle age reveals imperial age")
expectItems(fixture,1,4,"Old,Current,Next,Later,Default","imperial age unlocks all listed items")
expectItems(fixture,2,1,"","empty classification remains empty")
expectItems(fixture,3,1,"","malformed classification does not expose all builds")
for _,bad in ipairs({0,-1,1.5,math.huge,-math.huge,0/0,"1",true,{}}) do
 expect(#BuildMenuRules.items(fixture,bad,1)==0,"invalid page accepted")
 expect(#BuildMenuRules.items(fixture,1,bad)==0,"invalid age accepted")
end
expect(#BuildMenuRules.items(fixture,nil,1)==0 and #BuildMenuRules.items(fixture,1,nil)==0,"missing page or age accepted")
expect(#BuildMenuRules.items(fixture,4,1)==0,"unknown page accepted")
expect(#BuildMenuRules.items(nil,1,1)==0 and #BuildMenuRules.items({},1,1)==0,"missing configuration accepted")
for _,bad in ipairs({0,-1,1.5,math.huge,-math.huge,0/0,true,{}}) do
 local invalid={BuildOrder={"Invalid"},Buildings={Invalid={minAge=bad}},BuildPages={{buildings={"Invalid"}}}}
 expect(#BuildMenuRules.items(invalid,1,4)==0,"invalid building age was displayed")
end
local first=BuildMenuRules.items(fixture,1,2)
first[1].kind="Changed"; first[1].locked=true
expectItems(fixture,1,2,"Old,Current,Next*,Default","callers cannot mutate later menu results")

expect(#Config.BuildPages==3,"villager construction requires exactly three classifications")
local pageKeys={"economy","military","defense"}
local pageNames={"經濟","軍事","防禦"}
local expected={
 [1]={"House,Mill,LumberCamp,MiningCamp,Farm,Market*","Barracks,ArcheryRange*,Stable*,Blacksmith*","Tower*,Wall*"},
 [2]={"House,Mill,LumberCamp,MiningCamp,Farm,Market,TownCenter*","Barracks,ArcheryRange,Stable,Blacksmith,SiegeWorkshop*","Tower,Wall,Castle*,Monastery*,University*"},
 [3]={"House,Mill,LumberCamp,MiningCamp,Farm,Market,TownCenter","Barracks,ArcheryRange,Stable,Blacksmith,SiegeWorkshop","Tower,Wall,Castle,Monastery,University,Wonder*"},
 [4]={"House,Mill,LumberCamp,MiningCamp,Farm,Market,TownCenter","Barracks,ArcheryRange,Stable,Blacksmith,SiegeWorkshop","Tower,Wall,Castle,Monastery,University,Wonder"},
}
for age=1,4 do
 local visible={}
 for page=1,3 do
  expect(Config.BuildPages[page].key==pageKeys[page] and Config.BuildPages[page].name==pageNames[page],"classification identity changed")
  for _,item in ipairs(expectItems(Config,page,age,expected[age][page],"actual classification visibility at age "..age)) do
   expect(not visible[item.kind],"building is shown on more than one classification: "..item.kind)
   visible[item.kind]=true
  end
 end
end
local classified,allowed={},{}
for _,kind in ipairs(Config.BuildOrder) do
 expect(not allowed[kind],"BuildOrder contains duplicate: "..kind)
 allowed[kind]=true
end
for page=1,3 do
 for _,kind in ipairs(Config.BuildPages[page].buildings) do
  expect(allowed[kind] and Config.Buildings[kind]~=nil,"classification contains unsupported construction: "..kind)
  expect(not classified[kind],"classification contains duplicate construction: "..kind)
  classified[kind]=true
 end
end
for _,kind in ipairs(Config.BuildOrder) do expect(classified[kind],"supported construction missing from all pages: "..kind) end
print(string.format("PASS: %d villager build classification / age visibility / lock checks",checks))
