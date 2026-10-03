-- 由 scripts/verify.ps1 組合實際模組（ShopCatalog、ShopRules、WalletRules、WalletStore）後執行；只模擬排程與雲端儲存。
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local Catalog=ShopCatalog

-- 稽核：正式資料通過；任何對戰欄位或付費隨機內容都被拒絕。
local ok,err=ShopRules.audit(Catalog)
expect(ok,"catalog audit failed: "..tostring(err))
local function tampered(mutate)
 local copy=table.clone(Catalog)
 copy.items=table.clone(Catalog.items)
 copy.products=table.clone(Catalog.products)
 copy.passes=table.clone(Catalog.passes)
 copy.milestones=table.clone(Catalog.milestones)
 mutate(copy)
 return ShopRules.audit(copy)
end
local function withField(source,field,value)
 local copy=table.clone(source); copy[field]=value; return copy
end
expect(not tampered(function(c) c.items.skin_gilded=withField(c.items.skin_gilded,"damage",5) end),"item with damage passed audit")
expect(not tampered(function(c) c.items.skin_gilded=withField(c.items.skin_gilded,"look",{palette={},speed=2}) end),"look with speed passed audit")
expect(not tampered(function(c) c.items.style_desert=withField(c.items.style_desert,"look",{palette={food=Color3.fromRGB(1,1,1)}}) end),"palette outside art keys passed audit")
expect(not tampered(function(c) c.products[1]=withField(c.products[1],"food",500) end),"Robux resources passed audit")
expect(not tampered(function(c) c.products[1]=withField(c.products[1],"random",true) end),"random product passed audit")
expect(not tampered(function(c) c.passes.vip=withField(c.passes.vip,"populationBonus",10) end),"pass gameplay bonus passed audit")
expect(not tampered(function(c) c.milestones.welcome=withField(c.milestones.welcome,"wood",100) end),"milestone resources passed audit")
expect(not tampered(function(c) c.items.title_none=withField(c.items.title_none,"source","shop") end),"slot default could be sold")
expect(not tampered(function(c) c.items.skin_royal=withField(c.items.skin_royal,"price",10) end),"vip item could be priced")
expect(not tampered(function(c) c.products[1]=withField(c.products[1],"items",{"skin_gilded"}) end),"bundle granted a shop item")
expect(not tampered(function(c) c.products[2]=withField(c.products[2],"productId",777); c.products[1]=withField(c.products[1],"productId",777) end),"duplicate product id passed audit")
-- 每個欄位都有預設外觀，且預設免費擁有。
for _,slot in ipairs(Catalog.slots) do
 expect(ShopRules.owns(Catalog,{},slot.default,false),"default not owned: "..slot.id)
end

-- 裝備解析：未擁有、錯欄位或王室專屬（無通行證）都退回預設。
local resolved=ShopRules.equipped(Catalog,{},{unitSkin="skin_gilded",title="skin_obsidian",trail="trail_royal"},false)
expect(resolved.unitSkin=="skin_standard" and resolved.title=="title_none" and resolved.trail=="trail_none","unowned or wrong-slot cosmetic equipped")
resolved=ShopRules.equipped(Catalog,{skin_gilded=true},{unitSkin="skin_gilded",trail="trail_royal"},true)
expect(resolved.unitSkin=="skin_gilded" and resolved.trail=="trail_royal","owned or vip cosmetic not equipped")

-- 對局獎勵：練習局、投降、過短或平手不給；PvP 勝利最高。
expect(ShopRules.matchReward(Catalog,{mode="Sandbox",outcome="win",seconds=900})==0,"sandbox rewarded")
expect(ShopRules.matchReward(Catalog,{mode="PurePvP",outcome="win",seconds=900,forfeited=true})==0,"forfeit rewarded")
expect(ShopRules.matchReward(Catalog,{mode="PurePvP",outcome="win",seconds=120})==0,"short match rewarded")
expect(ShopRules.matchReward(Catalog,{mode="PurePvP",outcome="draw",seconds=900})==0,"draw rewarded")
expect(ShopRules.matchReward(Catalog,{mode="Story",outcome="loss",seconds=900})==Catalog.rewards.matchBase,"loss participation wrong")
expect(ShopRules.matchReward(Catalog,{mode="PurePvP",outcome="win",seconds=900})==Catalog.rewards.matchBase+Catalog.rewards.matchWin+Catalog.rewards.pvpWin,"pvp win wrong")
expect(ShopRules.matchReward(Catalog,{mode="AIPractice",outcome="win",seconds=0/0})==0,"NaN duration rewarded")

-- 錢包交易
local function apply(wallet,op) return WalletRules.apply(wallet,op,Catalog) end
local empty=WalletRules.empty()
local w,o=apply(empty,{kind="buy",item="skin_gilded"})
expect(w==nil and not o.ok,"bought without crowns")
expect(empty.crowns==0 and next(empty.owned)==nil,"transform mutated stored input")
local rich=table.clone(empty); rich.crowns=1000
w,o=apply(rich,{kind="buy",item="skin_gilded"})
expect(w and w.crowns==600 and w.owned.skin_gilded and o.crowns==-400,"shop purchase wrong")
expect(rich.crowns==1000 and rich.owned.skin_gilded==nil,"purchase mutated stored input")
local again=apply(w,{kind="buy",item="skin_gilded"})
expect(again==nil,"same cosmetic bought twice")
expect(apply(w,{kind="buy",item="skin_royal"})==nil,"vip item bought with crowns")
expect(apply(w,{kind="buy",item="title_pioneer"})==nil,"bundle item bought with crowns")
expect(apply(w,{kind="buy",item="style_marble"})==nil,"overdraft purchase accepted")
expect(apply(w,{kind="buy",item={}})==nil and apply(w,{kind="buy"})==nil and apply(w,"buy")==nil,"malformed purchase accepted")

-- Robux 收據：每張只發一次；新手禮包發外觀並記錄限購。
local receipt=apply(empty,{kind="receipt",id="purchase-1",product="crowns_medium",at=10})
expect(receipt and receipt.crowns==550,"receipt not granted")
local duplicate,info=apply(receipt,{kind="receipt",id="purchase-1",product="crowns_medium",at=11})
expect(duplicate==nil and info.duplicate==true and info.ok==true,"duplicate receipt not recognized as already granted")
local starter=apply(receipt,{kind="receipt",id="purchase-2",product="starter",at=12})
expect(starter and starter.crowns==850 and starter.owned.title_pioneer and starter.owned.trail_petals and starter.milestones.starter,"starter pack wrong")
expect(apply(empty,{kind="receipt",id="purchase-3",product="no_such",at=1})==nil,"unknown product granted")
local journal=empty
for i=1,WalletRules.ReceiptLimit+5 do journal=apply(journal,{kind="receipt",id="r"..i,product="crowns_small",at=i}) end
local receipts=0; for _ in pairs(journal.receipts) do receipts+=1 end
expect(receipts<=WalletRules.ReceiptLimit and journal.receipts["r"..(WalletRules.ReceiptLimit+5)],"receipt journal unbounded or lost newest")
expect(WalletRules.read(journal)~=nil,"bounded journal failed to read back")

-- 對局金冠：每場一次、每日上限、每日首勝不受上限。
local facts={mode="PurePvP",outcome="win",seconds=900}
local g1,go=apply(empty,{kind="grant",id="m1",day=100,at=1,facts=facts})
local perWin=Catalog.rewards.matchBase+Catalog.rewards.matchWin+Catalog.rewards.pvpWin
expect(g1 and g1.crowns==perWin+Catalog.rewards.firstWin and go.firstWin,"first win bonus missing")
expect(apply(g1,{kind="grant",id="m1",day=100,at=2,facts=facts})==nil,"same match rewarded twice")
local g=g1
for i=2,30 do local nextWallet=apply(g,{kind="grant",id="m"..i,day=100,at=i,facts=facts}); if nextWallet then g=nextWallet end end
expect(g.earnedToday==Catalog.rewards.dailyMatchCap,"daily match cap not enforced")
expect(g.crowns==Catalog.rewards.dailyMatchCap+Catalog.rewards.firstWin,"crowns exceed cap")
local nextDay=apply(g,{kind="grant",id="d2",day=101,at=99,facts=facts})
expect(nextDay and nextDay.earnedToday==perWin and nextDay.crowns==g.crowns+perWin+Catalog.rewards.firstWin,"cap did not reset next day")
expect(apply(empty,{kind="grant",id="bad id!",day=100,at=1,facts=facts})==nil,"malformed match id accepted")

-- 每日登入：連續循環、斷線重來、同日不可重領、通行證加成。
local d1=apply(empty,{kind="daily",day=50})
expect(d1 and d1.crowns==Catalog.rewards.daily[1] and d1.dailyStreak==1,"day one wrong")
expect(apply(d1,{kind="daily",day=50})==nil,"daily claimed twice")
local d=d1
for day=51,56 do d=apply(d,{kind="daily",day=day}) end
expect(d.dailyStreak==#Catalog.rewards.daily,"streak did not reach the last day")
local wrap=apply(d,{kind="daily",day=57})
expect(wrap.dailyStreak==1,"streak did not cycle")
local broken=apply(d1,{kind="daily",day=53})
expect(broken.dailyStreak==1,"missed day kept the streak")
local vipDay=apply(empty,{kind="daily",day=50,vip=true})
local base=Catalog.rewards.daily[1]
expect(vipDay.crowns==base+math.floor(base*Catalog.passes.vip.dailyBonusPercent/100),"vip daily bonus wrong")

-- 成就：只發一次，附帶外觀。
local m=apply(empty,{kind="milestone",id="story5"})
expect(m and m.owned.title_hero and m.owned.style_epic and m.crowns==Catalog.milestones.story5.crowns,"milestone reward wrong")
expect(apply(m,{kind="milestone",id="story5"})==nil,"milestone granted twice")
expect(apply(empty,{kind="milestone",id="nonexistent"})==nil,"unknown milestone granted")

-- 裝備：只存擁有的外觀。
local e=apply(w,{kind="equip",equipped={unitSkin="skin_gilded",buildingStyle="style_marble",title="title_royal"}})
expect(e and e.equipped.unitSkin=="skin_gilded" and e.equipped.buildingStyle==nil and e.equipped.title==nil,"equip stored an unowned cosmetic")
local vipEquip=apply(w,{kind="equip",equipped={title="title_royal"},vip=true})
expect(vipEquip and vipEquip.equipped.title=="title_royal","vip equip rejected")

-- 讀取驗證：損壞或未知欄位整份拒絕（伺服器不會覆寫）。
expect(WalletRules.read({version=2})==nil,"future wallet accepted")
local corrupt=table.clone(rich); corrupt.food=10
expect(WalletRules.read(corrupt)==nil,"gameplay field in wallet accepted")
corrupt=table.clone(rich); corrupt.crowns=-5
expect(WalletRules.read(corrupt)==nil,"negative balance accepted")
corrupt=table.clone(rich); corrupt.crowns=0/0
expect(WalletRules.read(corrupt)==nil,"NaN balance accepted")
expect(apply(corrupt,{kind="daily",day=1})==nil,"corrupt wallet overwritten")

-- WalletStore：交易經過 UpdateAsync，取消的交易不改資料，裝備延遲合併寫入。
local scheduled={}
local store=WalletStore.new(Catalog,{persistent=false,store=WalletStore.Memory.new(),defer=function(f) f() end,
 delay=function(_,f) table.insert(scheduled,f) end,wait=function() end,log=function() end})
local fakePlayer={UserId=42}
local changes=0
store:Open(fakePlayer,function() changes+=1 end)
expect(store:Entry(fakePlayer).status=="Ready" and changes==1,"memory wallet did not open")
local okBuy,outcome=store:Transact(fakePlayer,{kind="buy",item="skin_gilded"})
expect(not okBuy and outcome.reason~=nil and store:Entry(fakePlayer).data.crowns==0,"failed purchase changed data")
expect(store:Transact(fakePlayer,{kind="receipt",id="p1",product="crowns_large",at=1}),"receipt transaction failed")
expect(store:Entry(fakePlayer).data.crowns==1200,"receipt not visible in session")
expect(store:Transact(fakePlayer,{kind="buy",item="style_marble"}),"purchase transaction failed")
expect(store:Entry(fakePlayer).data.crowns==400,"purchase balance wrong")
expect(store:Equip(fakePlayer,"buildingStyle","style_marble",false),"equip rejected")
expect(#scheduled==1,"equip not debounced")
store:Equip(fakePlayer,"title","title_lord",false)
expect(#scheduled==1,"second equip scheduled another write")
scheduled[1]()
local saved=store.store:GetAsync("w_42")
expect(saved.equipped.buildingStyle=="style_marble" and saved.equipped.title=="title_lord","debounced equip not saved")
local failing=WalletStore.new(Catalog,{persistent=false,store={UpdateAsync=function() error("throttled") end,GetAsync=function() return nil end},
 defer=function(f) f() end,delay=function() end,wait=function() end,log=function() end})
failing:Open(fakePlayer)
local okFail=failing:Transact(fakePlayer,{kind="receipt",id="p9",product="crowns_small",at=1})
expect(not okFail and failing:Entry(fakePlayer).data.crowns==0,"failed cloud write reported success")

print("PASS: "..count.." shop catalog / fair commerce / wallet transaction checks")
