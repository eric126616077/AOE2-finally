-- scripts/verify.ps1 runs the actual configuration and pure validation modules.
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local function copyConfig()
 local result=table.clone(Config)
 result.Civilizations={}
 for id,data in pairs(Config.Civilizations) do result.Civilizations[id]=table.clone(data) end
 result.CivilizationOrder=table.clone(Config.CivilizationOrder)
 result.Commerce=table.clone(Config.Commerce)
 result.Commerce.catalog={}
 result.CivilizationBonuses={}
 for id,entry in pairs(Config.CivilizationBonuses) do
  local bonuses={}
  for index,bonus in ipairs(entry.bonuses) do bonuses[index]={text=bonus.text,unitClass=bonus.unitClass,effect=table.clone(bonus.effect)} end
  result.CivilizationBonuses[id]={uniqueUnit=entry.uniqueUnit,bonuses=bonuses}
 end
 return result
end

expect(CivilizationRules.audit(Config),"default civilization policy invalid")
expect(#Config.CivilizationOrder==3,"three original identities must be available")
local baseline=CivilizationRules.gameplay(Config,Config.DefaultCivilization)
for _,id in ipairs(Config.CivilizationOrder) do
 expect(CivilizationRules.canSelect(Config,"Lobby",id),"free civilization rejected in lobby")
 local data=CivilizationRules.gameplay(Config,id)
 -- 共用同一份兵種、建築、科技、時代與開局設定；差別只在加成與專屬兵種。
 expect(data.units==baseline.units and data.buildings==baseline.buildings,"civilization replaced the shared unit / building tables")
 expect(data.technologies==baseline.technologies and data.ages==baseline.ages and data.settings==baseline.settings,"civilization changed technology / starting economy")
 expect(#data.bonuses==Config.CivilizationBonusLimits.perCivilization,"civilizations must have the same number of bonuses: "..id)
 local unique=Config.Units[data.uniqueUnit]
 expect(unique and unique.civilization==id and table.find(unique.trainsAt,"Castle"),"unique unit must be trained at the castle by its own civilization: "..id)
 expect(CivilizationRules.canTrain(Config,id,data.uniqueUnit),"civilization cannot train its own unique unit")
 for _,other in ipairs(Config.CivilizationOrder) do
  if other~=id then expect(not CivilizationRules.canTrain(Config,other,data.uniqueUnit),"another civilization trains a unique unit: "..other) end
 end
 expect(CivilizationRules.canTrain(Config,id,"villager") and not CivilizationRules.canTrain(Config,id,"noSuchUnit"),"shared / unknown unit training wrong")
 local summary=CivilizationRules.summary(Config,id)
 expect(summary:find(unique.name,1,true)~=nil and summary:find("；",1,true)~=nil,"civilization summary missing bonuses or unique unit")
 for _,phase in ipairs({"Starting","Playing","Ended"}) do
  expect(not CivilizationRules.canSelect(Config,phase,id),"civilization switched outside lobby")
 end
end
for _,id in ipairs({"", "NoSuchCiv", "RiverHaven\0", string.rep("x",33), "../Sunspire", 1, true, {}, math.huge, 0/0}) do
 expect(not CivilizationRules.canSelect(Config,"Lobby",id),"malformed or nonexistent civilization accepted")
end
local fallback=CivilizationRules.resolve(Config,"NoSuchCiv")
expect(fallback==Config.DefaultCivilization,"bad saved identity did not safely fall back")
for _,field in ipairs({"bonus","damage","cost","population","trainTime","gatherRate","technologies","modifiers"}) do
 local invalid=copyConfig()
 invalid.Civilizations.Sunspire[field]={attack=999}
 expect(not CivilizationRules.audit(invalid),"civilization accepted gameplay override: "..field)
end
-- 加成稽核：數量一致、有上限、只用允許的效果、專屬兵種對應正確，而且有加成的文明不能被付費鎖住。
local function bonusCase(change,message)
 local invalid=copyConfig()
 change(invalid)
 expect(not CivilizationRules.audit(invalid),message)
end
bonusCase(function(c) c.CivilizationBonuses.Sunspire.bonuses[1].effect.gatherGold=0.9 end,"oversized ratio bonus accepted")
bonusCase(function(c) c.CivilizationBonuses.RiverHaven.bonuses[2].effect.carry=50 end,"oversized flat bonus accepted")
bonusCase(function(c) c.CivilizationBonuses.JadeGrove.bonuses[1].effect={attack=2} end,"disallowed attack bonus accepted")
bonusCase(function(c) c.CivilizationBonuses.JadeGrove.bonuses[1].effect={gatherWood=0/0} end,"NaN bonus accepted")
bonusCase(function(c) table.insert(c.CivilizationBonuses.Sunspire.bonuses,{text="額外",effect={speed=0.1}}) end,"extra bonus accepted")
bonusCase(function(c) c.CivilizationBonuses.Sunspire.bonuses[1].unitClass="dragon" end,"unknown bonus class accepted")
bonusCase(function(c) c.CivilizationBonuses.Sunspire.uniqueUnit="longbowman" end,"another civilization's unique unit accepted")
bonusCase(function(c) c.CivilizationBonuses.JadeGrove=nil end,"civilization without bonuses accepted")
bonusCase(function(c) c.CivilizationBonuses.Atlantis=c.CivilizationBonuses.Sunspire end,"bonus for an unlisted civilization accepted")
bonusCase(function(c) c.Civilizations.Sunspire.public=false end,"civilization with bonuses could be locked behind a purchase")
-- 付費不能換到任何數值：有加成的文明不能是付費商品，造型商品也不能夾帶效果。
for _,id in ipairs(Config.CivilizationOrder) do
 local paid=copyConfig()
 paid.Commerce.catalog.Paid={name="測試文明",category="civilization",gamePassId=12345,civilizationId=id}
 expect(not CommerceRules.audit(paid),"civilization with gameplay bonuses could be sold: "..id)
end
local unavailable=copyConfig()
unavailable.Civilizations.Sunspire.public=false
expect(not CivilizationRules.canSelect(unavailable,"Lobby","Sunspire"),"unavailable civilization selected without server access")
local duplicate=copyConfig()
table.insert(duplicate.CivilizationOrder,"Sunspire")
expect(not CivilizationRules.audit(duplicate),"duplicate civilization entry accepted")
local noFreeDefault=copyConfig()
noFreeDefault.Civilizations[Config.DefaultCivilization].public=false
expect(not CivilizationRules.audit(noFreeDefault),"default identity could be paywalled")

expect(CommerceRules.audit(Config),"default commerce policy invalid")
expect(not Config.Commerce.enabled and next(Config.Commerce.catalog)==nil,"unconfigured store must remain closed")
expect(not CommerceRules.purchase(Config,"unknown"),"unconfigured store accepted purchase")
local draft=copyConfig()
draft.Commerce.enabled=true
draft.Commerce.catalog.TestBanner={name="測試旗幟",category="cosmetic",gamePassId=0,cosmeticId="test_banner"}
expect(CommerceRules.audit(draft),"zero-id draft cosmetic configuration rejected")
expect(not CommerceRules.purchase(draft,"TestBanner"),"zero-id pass accepted as a real purchase")
for _,category in ipairs({"resource","speedup","population","attack","revive","skipAge"}) do
 local invalid=copyConfig()
 invalid.Commerce.catalog.Bad={name="測試",category=category,gamePassId=0,cosmeticId="test"}
 expect(not CommerceRules.audit(invalid),"pay-to-win category accepted: "..category)
end
for _,field in ipairs({"effect","resources","gatherMultiplier","attack","extraPopulation","trainSpeed","currencyAmount"}) do
 local invalid=copyConfig()
 invalid.Commerce.catalog.Bad={name="測試",category="cosmetic",gamePassId=0,cosmeticId="test"}
 invalid.Commerce.catalog.Bad[field]=999
 expect(not CommerceRules.audit(invalid),"cosmetic concealed paid power: "..field)
end
for _,id in ipairs({-1,1.5,math.huge,0/0,"1",true}) do
 local invalid=copyConfig()
 invalid.Commerce.catalog.Bad={name="測試",category="civilization",gamePassId=id,civilizationId="Sunspire"}
 expect(not CommerceRules.audit(invalid),"invalid marketplace id accepted")
end
local unknownCiv=copyConfig()
unknownCiv.Commerce.catalog.Bad={name="測試",category="civilization",gamePassId=0,civilizationId="Unknown"}
expect(not CommerceRules.audit(unknownCiv),"undefined paid civilization accepted")
print(string.format("PASS: %d civilization bonus audit / free civilizations / lobby lock / no paid advantage checks",count))
