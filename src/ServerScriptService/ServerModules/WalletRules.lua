-- 錢包純規則：金冠餘額、已擁有外觀、裝備選擇與一次性紀錄。
-- 每次異動都在 DataStore UpdateAsync 的轉換函式內以目前雲端資料重新計算，所以多台伺服器同時寫入也不會重複發放或透支。
-- 轉換函式不 yield；回傳 nil 代表取消寫入（不扣款、不發放）。
local ShopRules = require(game:GetService("ReplicatedStorage").Shared.ShopRules)
local Rules = {}
Rules.ReceiptLimit = 256
Rules.GrantLimit = 128
local fields = {version=true,rev=true,crowns=true,owned=true,equipped=true,receipts=true,grants=true,milestones=true,
 dailyDay=true,dailyStreak=true,earnDay=true,earnedToday=true,winDay=true}
local integer,token = ShopRules.integer,ShopRules.token

function Rules.empty()
 return {version=1,rev=0,crowns=0,owned={},equipped={},receipts={},grants={},milestones={},dailyDay=-1,dailyStreak=0,earnDay=-1,earnedToday=0,winDay=-1}
end

local function day(value) return type(value)=="number" and value==value and value%1==0 and value>=-1 and value<=10000000 end

local function tokenMap(raw,check,limit)
 if type(raw)~="table" then return nil end
 local copy,count = {},0
 for key,value in pairs(raw) do
  if not token(key) or not check(value) then return nil end
  count += 1
  if count>limit then return nil end
  copy[key] = value
 end
 return copy
end
local function isTrue(value) return value==true end

-- 讀取時逐欄驗證；任何未知或損壞的欄位都讓整份資料失效，伺服器不會覆寫它。
function Rules.read(raw)
 if raw==nil then return Rules.empty() end
 if type(raw)~="table" or raw.version~=1 then return nil end
 for field in pairs(raw) do if not fields[field] then return nil end end
 if not integer(raw.rev) or not integer(raw.crowns) or not integer(raw.earnedToday) or not integer(raw.dailyStreak) then return nil end
 if not day(raw.dailyDay) or not day(raw.earnDay) or not day(raw.winDay) then return nil end
 local result = Rules.empty()
 result.rev,result.crowns,result.earnedToday,result.dailyStreak = raw.rev,raw.crowns,raw.earnedToday,raw.dailyStreak
 result.dailyDay,result.earnDay,result.winDay = raw.dailyDay,raw.earnDay,raw.winDay
 result.owned = tokenMap(raw.owned,isTrue,1000)
 result.equipped = tokenMap(raw.equipped,token,32)
 result.receipts = tokenMap(raw.receipts,integer,Rules.ReceiptLimit)
 result.grants = tokenMap(raw.grants,integer,Rules.GrantLimit)
 result.milestones = tokenMap(raw.milestones,isTrue,200)
 if not result.owned or not result.equipped or not result.receipts or not result.grants or not result.milestones then return nil end
 return result
end

local function addCrowns(wallet,catalog,amount)
 wallet.crowns = math.min(catalog.maxCrowns or 10000000,wallet.crowns+amount)
end
local function giveItems(wallet,catalog,items)
 for _,id in ipairs(items or {}) do if catalog.items[id] then wallet.owned[id] = true end end
end
-- 依序號淘汰最舊紀錄，讓日誌大小有上限。
local function trim(journal,limit)
 local list = {}
 for id,at in pairs(journal) do table.insert(list,{id=id,at=at}) end
 if #list<=limit then return end
 table.sort(list,function(a,b) if a.at==b.at then return a.id<b.id end return a.at<b.at end)
 for index=1,#list-limit do journal[list[index].id] = nil end
end

-- op.kind：receipt｜grant｜milestone｜daily｜buy｜equip。回傳 (新資料或 nil, 結果說明)。
function Rules.apply(raw,op,catalog)
 local wallet = Rules.read(raw)
 if not wallet then return nil,{ok=false,reason="錢包資料無法讀取，未做任何變更。"} end
 if type(op)~="table" then return nil,{ok=false,reason="指令無效。"} end
 local outcome = {ok=true,crowns=0}
 if op.kind=="receipt" then
  local product = ShopRules.productById(catalog,op.product)
  if not token(op.id) or not product or not integer(op.at) then return nil,{ok=false,reason="收據無效。"} end
  if wallet.receipts[op.id] then return nil,{ok=true,duplicate=true,crowns=0} end
  addCrowns(wallet,catalog,product.crowns)
  giveItems(wallet,catalog,product.items)
  if product.once then wallet.milestones[product.id] = true end
  wallet.receipts[op.id] = op.at
  trim(wallet.receipts,Rules.ReceiptLimit)
  outcome.crowns = product.crowns
 elseif op.kind=="grant" then
  if not token(op.id) or not day(op.day) or op.day<0 or not integer(op.at) then return nil,{ok=false,reason="獎勵無效。"} end
  if wallet.grants[op.id] then return nil,{ok=false,duplicate=true,reason="這場對局已領過獎勵。"} end
  local amount,won = ShopRules.matchReward(catalog,op.facts)
  if wallet.earnDay~=op.day then wallet.earnDay,wallet.earnedToday = op.day,0 end
  local cap = catalog.rewards.dailyMatchCap
  local granted = math.max(0,math.min(amount,cap-wallet.earnedToday))
  wallet.earnedToday += granted
  local bonus = 0
  if won and wallet.winDay~=op.day then bonus,wallet.winDay = catalog.rewards.firstWin,op.day end
  if granted+bonus==0 then return nil,{ok=false,capped=amount>0,reason=amount>0 and "今日對局金冠已達上限。" or "這場對局沒有金冠獎勵。"} end
  addCrowns(wallet,catalog,granted+bonus)
  wallet.grants[op.id] = op.at
  trim(wallet.grants,Rules.GrantLimit)
  outcome.crowns,outcome.firstWin,outcome.capped = granted+bonus,bonus>0,granted<amount
 elseif op.kind=="milestone" then
  local milestone = token(op.id) and catalog.milestones[op.id]
  if not milestone then return nil,{ok=false,reason="成就無效。"} end
  if wallet.milestones[op.id] then return nil,{ok=false,duplicate=true,reason="成就已領取。"} end
  wallet.milestones[op.id] = true
  addCrowns(wallet,catalog,milestone.crowns)
  giveItems(wallet,catalog,milestone.items)
  outcome.crowns,outcome.items = milestone.crowns,milestone.items
 elseif op.kind=="daily" then
  if not day(op.day) or op.day<0 then return nil,{ok=false,reason="日期無效。"} end
  local amount,streak = ShopRules.daily(catalog,{day=wallet.dailyDay,streak=wallet.dailyStreak},op.day,op.vip==true)
  if not amount then return nil,{ok=false,duplicate=true,reason="今天已經領過每日獎勵。"} end
  wallet.dailyDay,wallet.dailyStreak = op.day,streak
  addCrowns(wallet,catalog,amount)
  outcome.crowns,outcome.streak = amount,streak
 elseif op.kind=="buy" then
  local item = type(op.item)=="string" and catalog.items[op.item]
  if not item or item.source~="shop" or not integer(item.price) then return nil,{ok=false,reason="此商品無法用金冠購買。"} end
  if wallet.owned[op.item] then return nil,{ok=false,duplicate=true,reason="你已經擁有這個外觀。"} end
  if wallet.crowns<item.price then return nil,{ok=false,reason="金冠不足。"} end
  wallet.crowns -= item.price
  wallet.owned[op.item] = true
  outcome.crowns = -item.price
 elseif op.kind=="equip" then
  if type(op.equipped)~="table" then return nil,{ok=false,reason="裝備無效。"} end
  local resolved = ShopRules.equipped(catalog,wallet.owned,op.equipped,op.vip==true)
  local changed = false
  for slot,id in pairs(resolved) do
   if op.equipped[slot]==id and wallet.equipped[slot]~=id then wallet.equipped[slot] = id; changed = true end
  end
  if not changed then return nil,{ok=true,unchanged=true,crowns=0} end
 else
  return nil,{ok=false,reason="指令無效。"}
 end
 wallet.rev += 1
 return wallet,outcome
end

return Rules
