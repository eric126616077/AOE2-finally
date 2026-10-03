-- 商店純規則：伺服器驗證與客戶端顯示共用。不讀寫任何 Instance，方便在 verify.ps1 直接測試。
local Rules = {}

local MAX_INT = 9007199254740991
local function integer(value)
 return type(value)=="number" and value==value and value>=0 and value<=MAX_INT and value%1==0
end
Rules.integer = integer
function Rules.token(value)
 return type(value)=="string" and #value>0 and #value<=100 and value:match("^[%w_:%-]+$")~=nil
end

-- 白名單：任何其他欄位（例如 damage、food、speed、population）都會讓稽核失敗。
local itemFields = {slot=true,name=true,source=true,price=true,description=true,look=true}
local lookFields = {
 unitSkin = {palette=true,material=true},
 buildingStyle = {palette=true,material=true},
 title = {text=true,color=true,crown=true},
 trail = {colors=true,light=true},
 victory = {kind=true,colors=true},
}
local paletteKeys = {
 unitSkin = {steel=true,iron=true,gold=true,leather=true},
 buildingStyle = {plaster=true,wallShade=true,stone=true,paleStone=true,tile=true,tileDark=true,thatch=true,thatchDark=true,roof=true,timber=true},
}
local materials = {Foil=true,Metal=true,CorrodedMetal=true,Sandstone=true,Marble=true,Slate=true,Concrete=true,Wood=true,SmoothPlastic=true}
local victoryKinds = {none=true,fireworks=true,coins=true,flame=true}
local sources = {default=true,shop=true,vip=true,milestone=true,bundle=true}
local productFields = {id=true,name=true,crowns=true,bonus=true,items=true,once=true,productId=true,suggestedRobux=true,description=true}
local passFields = {name=true,gamePassId=true,suggestedRobux=true,dailyBonusPercent=true,items=true,description=true}
local milestoneFields = {name=true,crowns=true,items=true}
local rewardFields = {daily=true,matchBase=true,matchWin=true,pvpWin=true,firstWin=true,minMatchSeconds=true,dailyMatchCap=true,modes=true}
Rules.Materials = materials
Rules.PaletteKeys = paletteKeys

local function text(value,limit) return type(value)=="string" and #value<=(limit or 200) end
local function isColor(value)
 -- 真正的 Color3 在 Roblox；純邏輯測試以表格替代。
 return typeof(value)=="Color3" or type(value)=="table"
end

function Rules.audit(catalog)
 if type(catalog)~="table" or type(catalog.items)~="table" or type(catalog.slots)~="table" then return false,"商店資料無效。" end
 local slots = {}
 for _,slot in ipairs(catalog.slots) do
  if not lookFields[slot.id] or slots[slot.id] then return false,"外觀欄位無效。" end
  local default = catalog.items[slot.default]
  if not default or default.slot~=slot.id or default.source~="default" then return false,"外觀欄位缺少預設值："..tostring(slot.id) end
  slots[slot.id] = true
 end
 for id,item in pairs(catalog.items) do
  if not Rules.token(id) or type(item)~="table" then return false,"商品編號無效。" end
  for field in pairs(item) do if not itemFields[field] then return false,"商品不得授予對戰優勢："..id.."."..tostring(field) end end
  if not slots[item.slot] or not sources[item.source] or not text(item.name,60) or #item.name==0 or not text(item.description) then return false,"商品設定無效："..id end
  if item.source=="shop" then
   if not integer(item.price) or item.price<1 or item.price>100000 then return false,"商品價格無效："..id end
  elseif item.price~=nil then return false,"只有商店商品可以標價："..id end
  local look = item.look
  if type(look)~="table" then return false,"商品外觀無效："..id end
  for field in pairs(look) do if not lookFields[item.slot][field] then return false,"外觀欄位不允許："..id.."."..tostring(field) end end
  if look.palette~=nil then
   if type(look.palette)~="table" then return false,"配色無效："..id end
   for key,color in pairs(look.palette) do if not paletteKeys[item.slot][key] or not isColor(color) then return false,"配色無效："..id end end
  end
  if look.material~=nil then
   if type(look.material)~="table" then return false,"材質無效："..id end
   for key,name in pairs(look.material) do if not paletteKeys[item.slot][key] or not materials[name] then return false,"材質無效："..id end end
  end
  if item.slot=="title" and (not text(look.text,24) or not isColor(look.color) or (look.crown~=nil and look.crown~=true)) then return false,"稱號無效："..id end
  if item.slot=="trail" or item.slot=="victory" then
   if type(look.colors)~="table" or #look.colors>4 then return false,"特效顏色無效："..id end
   for _,color in ipairs(look.colors) do if not isColor(color) then return false,"特效顏色無效："..id end end
  end
  if item.slot=="trail" and look.light~=nil and (type(look.light)~="number" or look.light<0 or look.light>1) then return false,"拖尾亮度無效："..id end
  if item.slot=="victory" and not victoryKinds[look.kind] then return false,"勝利特效無效："..id end
 end
 local function itemList(list,source,owner)
  if list==nil then return true end
  if type(list)~="table" or #list>8 then return false end
  for _,itemId in ipairs(list) do
   local item = catalog.items[itemId]
   if not item or item.source~=source then return false,"獎勵物品無效："..owner end
  end
  return true
 end
 local productIds,keys = {},{}
 for _,product in ipairs(catalog.products or {}) do
  for field in pairs(product) do if not productFields[field] then return false,"Robux 商品不得授予對戰優勢："..tostring(product.id).."."..tostring(field) end end
  if not Rules.token(product.id) or keys[product.id] or not integer(product.crowns) or not integer(product.productId) or not text(product.name,60) then return false,"Robux 商品設定無效："..tostring(product.id) end
  if product.productId>0 then
   if productIds[product.productId] then return false,"開發者商品編號重複。" end
   productIds[product.productId] = true
  end
  if product.once~=nil and product.once~=true then return false,"限購設定無效。" end
  if product.once and not (catalog.milestones and catalog.milestones[product.id]) then return false,"限購商品需要對應的成就紀錄："..product.id end
  local ok,err = itemList(product.items,"bundle",product.id)
  if not ok then return false,err or "禮包內容無效。" end
  keys[product.id] = true
 end
 for key,pass in pairs(catalog.passes or {}) do
  for field in pairs(pass) do if not passFields[field] then return false,"通行證不得授予對戰優勢："..key.."."..tostring(field) end end
  if not integer(pass.gamePassId) or not integer(pass.dailyBonusPercent) or pass.dailyBonusPercent>100 then return false,"通行證設定無效。" end
  local ok,err = itemList(pass.items,"vip",key)
  if not ok then return false,err or "通行證內容無效。" end
 end
 for key,milestone in pairs(catalog.milestones or {}) do
  for field in pairs(milestone) do if not milestoneFields[field] then return false,"成就設定無效："..key end end
  if not Rules.token(key) or not integer(milestone.crowns) then return false,"成就設定無效："..key end
  local ok,err = itemList(milestone.items,"milestone",key)
  if not ok then return false,err or "成就獎勵無效。" end
 end
 local rewards = catalog.rewards
 if type(rewards)~="table" or type(rewards.daily)~="table" or #rewards.daily==0 then return false,"獎勵設定無效。" end
 for field in pairs(rewards) do if not rewardFields[field] then return false,"獎勵設定無效："..tostring(field) end end
 for _,amount in ipairs(rewards.daily) do if not integer(amount) then return false,"每日獎勵無效。" end end
 for _,field in ipairs({"matchBase","matchWin","pvpWin","firstWin","minMatchSeconds","dailyMatchCap"}) do
  if not integer(rewards[field]) then return false,"獎勵設定無效："..field end
 end
 return true
end

function Rules.slot(catalog,id)
 for _,slot in ipairs(catalog.slots) do if slot.id==id then return slot end end
 return nil
end

-- 目前擁有：預設外觀、錢包紀錄或有效通行證。
function Rules.owns(catalog,owned,itemId,vip)
 local item = type(itemId)=="string" and catalog.items[itemId]
 if not item then return false end
 if item.source=="default" then return true end
 if item.source=="vip" then return vip==true end
 return type(owned)=="table" and owned[itemId]==true
end

-- 解析裝備：不合法或未擁有的選擇退回該欄預設值。
function Rules.equipped(catalog,owned,equipped,vip)
 local result = {}
 for _,slot in ipairs(catalog.slots) do
  local choice = type(equipped)=="table" and equipped[slot.id]
  local item = type(choice)=="string" and catalog.items[choice]
  result[slot.id] = (item and item.slot==slot.id and Rules.owns(catalog,owned,choice,vip)) and choice or slot.default
 end
 return result
end

function Rules.day(catalog,unixSeconds)
 return math.floor((unixSeconds+(catalog.dayOffsetHours or 0)*3600)/86400)
end

-- 每日登入：連續天數循環；斷一天從第 1 天開始。
function Rules.daily(catalog,daily,day,vip)
 local last = type(daily)=="table" and daily.day or -1
 local streak = type(daily)=="table" and daily.streak or 0
 if last==day then return nil end
 local ladder = catalog.rewards.daily
 local nextStreak = last==day-1 and streak%#ladder+1 or 1
 local amount = ladder[nextStreak]
 if vip then
  local bonus = catalog.passes and catalog.passes.vip and catalog.passes.vip.dailyBonusPercent or 0
  amount = amount+math.floor(amount*bonus/100)
 end
 return amount,nextStreak
end

-- 單場對局的金冠（套用每日上限前）。facts={mode,outcome,seconds,forfeited}
function Rules.matchReward(catalog,facts)
 local rewards = catalog.rewards
 if type(facts)~="table" or not rewards.modes[facts.mode] or facts.forfeited==true then return 0,false end
 if type(facts.seconds)~="number" or facts.seconds~=facts.seconds or facts.seconds<rewards.minMatchSeconds then return 0,false end
 if facts.outcome~="win" and facts.outcome~="loss" then return 0,false end
 local amount = rewards.matchBase
 local won = facts.outcome=="win"
 if won then amount += rewards.matchWin end
 if won and facts.mode=="PurePvP" then amount += rewards.pvpWin end
 return amount,won
end

function Rules.product(catalog,productId)
 if not integer(productId) or productId==0 then return nil end
 for _,product in ipairs(catalog.products) do if product.productId==productId then return product end end
 return nil
end

function Rules.productById(catalog,id)
 for _,product in ipairs(catalog.products) do if product.id==id then return product end end
 return nil
end

-- 解鎖方式的玩家說明，供商店卡片顯示。
function Rules.unlockHint(catalog,itemId)
 local item = catalog.items[itemId]
 if not item then return "" end
 if item.source=="vip" then return "王室通行證" end
 if item.source=="bundle" then
  for _,product in ipairs(catalog.products) do
   if product.items and table.find(product.items,itemId) then return product.name.."限定" end
  end
  return "禮包限定"
 end
 if item.source=="milestone" then
  for _,milestone in pairs(catalog.milestones) do
   if milestone.items and table.find(milestone.items,itemId) then return milestone.name.."解鎖" end
  end
  return "成就解鎖"
 end
 return ""
end

-- 擁有清單的屬性字串（逗號分隔、排序），客戶端只拿來顯示。
function Rules.encodeOwned(owned)
 local list = {}
 for id,value in pairs(owned or {}) do if value==true and Rules.token(id) then table.insert(list,id) end end
 table.sort(list)
 return table.concat(list,",")
end
function Rules.decodeOwned(text)
 local owned = {}
 if type(text)=="string" then for id in text:gmatch("[^,]+") do if Rules.token(id) then owned[id] = true end end end
 return owned
end

return Rules
