-- 王國商店（伺服器權威）：金冠錢包、Robux 收據、通行證、外觀裝備、免費獎勵與大廳展示。
-- 商品只影響外觀；對戰中的資源、單位數值與生產完全不讀取這裡的資料。
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS = game:GetService("ReplicatedStorage")
local Catalog = require(RS.GameData.ShopCatalog)
local ShopRules = require(RS.Shared.ShopRules)
local Cosmetic = require(RS.Shared.CosmeticArt)
local WalletStore = require(script.Parent.WalletStore)

local Shop = {}
Shop.__index = Shop
local slotAttribute = {unitSkin="CosmeticUnitSkin",buildingStyle="CosmeticBuildingStyle",title="CosmeticTitle",trail="CosmeticTrail",victory="CosmeticVictory"}
Shop.SlotAttribute = slotAttribute
local icon = Catalog.currency.icon

function Shop.new(options)
 options = options or {}
 local valid,err = ShopRules.audit(Catalog)
 assert(valid,err)
 local self = setmetatable({wallets=WalletStore.new(Catalog,options.wallet),vip={},busy={},connections={},hooks={},milestonePending={}},Shop)
 self.studio = RunService:IsStudio()
 MarketplaceService.ProcessReceipt = function(info) return self:_receipt(info) end
 MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player,passId,purchased)
  local pass = Catalog.passes.vip
  if purchased and pass.gamePassId>0 and passId==pass.gamePassId and self.wallets:Entry(player) then
   self.vip[player] = true
   self:_publish(player)
   self:_notify(player,"感謝支持！已解鎖"..pass.name.."的專屬外觀。")
  end
 end)
 -- 跨過午夜時更新「每日獎勵可領取」提示。
 task.spawn(function()
  while true do
   task.wait(60)
   for player in pairs(self.connections) do self:_publishDaily(player) end
  end
 end)
 return self
end

-- hooks：notify(player,message,cue)、assets(player) → 對戰中的建築集合, 單位集合
function Shop:Bind(hooks)
 self.hooks = hooks or {}
end
function Shop:_notify(player,message,cue)
 if self.hooks.notify and player.Parent==Players then self.hooks.notify(player,message,cue) end
end

local function today() return ShopRules.day(Catalog,os.time()) end

function Shop:_equipped(player)
 local entry = self.wallets:Entry(player)
 local data = entry and entry.data
 return ShopRules.equipped(Catalog,data and data.owned,data and data.equipped,self.vip[player]==true)
end

function Shop:_publishDaily(player)
 local entry = self.wallets:Entry(player)
 local data = entry and entry.data
 if not data then player:SetAttribute("DailyClaimable",false); return end
 local amount,streak = ShopRules.daily(Catalog,{day=data.dailyDay,streak=data.dailyStreak},today(),self.vip[player]==true)
 player:SetAttribute("DailyClaimable",amount~=nil)
 player:SetAttribute("DailyNextAmount",amount or 0)
 player:SetAttribute("DailyNextStreak",streak or 0)
 player:SetAttribute("DailyStreak",data.dailyStreak)
end

function Shop:_publish(player)
 if player.Parent~=Players then return end
 local entry = self.wallets:Entry(player)
 local data = entry and entry.data
 player:SetAttribute("WalletStatus",entry and entry.status or "Closed")
 player:SetAttribute("WalletPersistent",self.wallets.persistent)
 player:SetAttribute("ShopVIP",self.vip[player]==true)
 player:SetAttribute("Crowns",data and data.crowns or 0)
 player:SetAttribute("OwnedCosmetics",data and ShopRules.encodeOwned(data.owned) or "")
 player:SetAttribute("StarterPackOwned",data and data.milestones.starter==true or false)
 -- 對戰中外觀固定：只在不在對戰時更新，對局開始時的外觀維持到結束。
 if not self.hooks.locked or not self.hooks.locked(player) or player:GetAttribute("CosmeticUnitSkin")==nil then
  for slot,id in pairs(self:_equipped(player)) do player:SetAttribute(slotAttribute[slot],id) end
 end
 self:_publishDaily(player)
end

-- 大廳角色的稱號與拖尾；對戰中沒有角色。
function Shop:_dress(player)
 local character = player.Character
 if not character then return end
 local equipped = self:_equipped(player)
 Cosmetic.Dress(character,equipped.title,equipped.trail)
end

-- 已發生的進度（教程、劇情、對戰勝場）補發一次性成就；成就本身在交易內去重。
function Shop:_checkMilestones(player)
 local entry = self.wallets:Entry(player)
 local data = entry and entry.data
 if not data or entry.status~="Ready" then return end
 local due = {}
 if player:GetAttribute("TutorialDone")==true then table.insert(due,"welcome") end
 local cleared = player:GetAttribute("StoryCleared") or 0
 for chapter=1,math.min(5,cleared) do table.insert(due,"story"..chapter) end
 if (player:GetAttribute("PvPWins") or 0)>=10 then table.insert(due,"pvp10") end
 for _,id in ipairs(due) do
  if not data.milestones[id] and not (self.milestonePending[player] and self.milestonePending[player][id]) then
   self.milestonePending[player] = self.milestonePending[player] or {}
   self.milestonePending[player][id] = true
   task.spawn(function()
    local ok,outcome = self.wallets:Transact(player,{kind="milestone",id=id})
    if self.milestonePending[player] then self.milestonePending[player][id] = nil end
    if ok then
     local milestone = Catalog.milestones[id]
     local items = {}
     for _,itemId in ipairs(milestone.items or {}) do table.insert(items,"「"..Catalog.items[itemId].name.."」") end
     self:_notify(player,"成就「"..milestone.name.."」："..(outcome.crowns>0 and (icon..outcome.crowns) or "")..(#items>0 and (" 解鎖 "..table.concat(items,"、")) or ""),"Victory")
    end
   end)
  end
 end
end

function Shop:Open(player)
 if self.connections[player] then return end
 local list = {}
 self.connections[player] = list
 local first = true
 -- Studio 測試：ServerScriptService 的 RTSTestCrowns 屬性給本工作階段的記憶體錢包起始金冠（不會寫入雲端）。
 local seed = self.studio and game:GetService("ServerScriptService"):GetAttribute("RTSTestCrowns")
 if ShopRules.integer(seed) then self.wallets:Seed(player,math.min(seed,Catalog.maxCrowns)) end
 self.wallets:Open(player,function(entry)
  self:_publish(player)
  self:_dress(player)
  if first and entry.status=="Ready" then
   first = false
   -- 錢包比對戰模型晚載入時，補套用已生成的建築與單位外觀。
   if self.hooks.assets then
    local buildingSet,unitSet = self.hooks.assets(player)
    local equipped = self:_equipped(player)
    for model in pairs(buildingSet or {}) do Cosmetic.StyleBuilding(model,equipped.buildingStyle) end
    for model in pairs(unitSet or {}) do Cosmetic.SkinUnit(model,equipped.unitSkin) end
   end
  end
  self:_checkMilestones(player)
 end)
 self:_publish(player)
 task.spawn(function()
  local pass = Catalog.passes.vip
  local owns = false
  if self.studio and game:GetService("ServerScriptService"):GetAttribute("RTSTestVIP")==true then owns = true
  elseif pass.gamePassId>0 then
   local ok,value = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId,pass.gamePassId) end)
   owns = ok and value==true
  end
  if owns and self.connections[player]==list then
   self.vip[player] = true
   self:_publish(player)
   self:_dress(player)
  end
 end)
 table.insert(list,player.CharacterAdded:Connect(function() task.defer(function() self:_dress(player) end) end))
 for _,attribute in ipairs({"TutorialDone","StoryCleared","PvPWins"}) do
  table.insert(list,player:GetAttributeChangedSignal(attribute):Connect(function() self:_checkMilestones(player) end))
 end
end

function Shop:Close(player)
 local list = self.connections[player]
 if not list then return end
 for _,connection in ipairs(list) do connection:Disconnect() end
 self.connections[player],self.vip[player],self.busy[player],self.milestonePending[player] = nil,nil,nil,nil
 self.wallets:Close(player)
end

function Shop:FlushAll() self.wallets:FlushAll() end

-- 需要往返雲端的操作一次只處理一個，避免連點重複送出。
function Shop:_exclusive(player,work)
 if self.busy[player] then self:_notify(player,"上一筆交易處理中，請稍候。"); return end
 self.busy[player] = true
 task.spawn(function()
  local ok,err = pcall(work)
  self.busy[player] = nil
  if not ok then warn("[RTS Shop] "..tostring(err)); self:_notify(player,"交易未完成，金冠沒有變動。","Error") end
 end)
end

-- 客戶端指令：只接受字串參數；在對戰中不能更換外觀。
function Shop:Command(player,sub,arg,inLobby)
 local entry = self.wallets:Entry(player)
 if type(sub)~="string" or not entry then return end
 if sub=="ClaimDaily" then
  if entry.status~="Ready" then self:_notify(player,"錢包讀取中，請稍候。"); return end
  self:_exclusive(player,function()
   local ok,outcome = self.wallets:Transact(player,{kind="daily",day=today(),vip=self.vip[player]==true})
   if ok then self:_notify(player,"每日獎勵第 "..outcome.streak.." 天："..icon..outcome.crowns,"Victory")
   else self:_notify(player,outcome.reason) end
   self:_publishDaily(player)
  end)
  return
 end
 if sub=="PromptProduct" then
  local product = type(arg)=="string" and ShopRules.productById(Catalog,arg)
  if not product then return end
  if product.productId==0 then self:_notify(player,"此商品尚未上架。"); return end
  if product.once and entry.data and entry.data.milestones[product.id] then self:_notify(player,"每個帳號限購一次，你已經擁有"..product.name.."。"); return end
  MarketplaceService:PromptProductPurchase(player,product.productId)
  return
 end
 if sub=="PromptPass" then
  local pass = Catalog.passes.vip
  if pass.gamePassId==0 then self:_notify(player,"通行證尚未上架。"); return end
  if self.vip[player] then self:_notify(player,"你已經擁有"..pass.name.."。"); return end
  MarketplaceService:PromptGamePassPurchase(player,pass.gamePassId)
  return
 end
 if not inLobby then self:_notify(player,"對戰中無法更換外觀，請回到大廳再試。"); return end
 local item = type(arg)=="string" and #arg<=64 and Catalog.items[arg]
 if not item then return end
 if entry.status~="Ready" then self:_notify(player,"錢包讀取中，請稍候。"); return end
 if sub=="Equip" then
  if not ShopRules.owns(Catalog,entry.data.owned,arg,self.vip[player]==true) then
   local hint = ShopRules.unlockHint(Catalog,arg)
   self:_notify(player,hint~="" and ("尚未擁有：需要"..hint.."。") or "尚未擁有這個外觀。")
   return
  end
  self.wallets:Equip(player,item.slot,arg,self.vip[player]==true)
  self:_publish(player)
  self:_dress(player)
  return
 end
 if sub=="Buy" then
  if item.source~="shop" then self:_notify(player,"這個外觀無法用金冠購買："..ShopRules.unlockHint(Catalog,arg).."。"); return end
  if entry.data.owned[arg] then self:_notify(player,"你已經擁有「"..item.name.."」。"); return end
  if entry.data.crowns<item.price then self:_notify(player,"金冠不足：需要 "..icon..item.price.."。","Error"); return end
  self:_exclusive(player,function()
   local ok,outcome = self.wallets:Transact(player,{kind="buy",item=arg})
   if ok then
    self.wallets:Equip(player,item.slot,arg,self.vip[player]==true)
    self:_publish(player)
    self:_dress(player)
    self:_notify(player,"已購買並裝備「"..item.name.."」。","Victory")
   else self:_notify(player,outcome.reason,"Error") end
  end)
 end
end

-- Robux 收據：寫入成功（或之前已寫入）才回報 PurchaseGranted；其他情況讓 Roblox 稍後重送，不會重複發放。
function Shop:_receipt(info)
 local product = type(info)=="table" and ShopRules.product(Catalog,info.ProductId)
 local player = type(info)=="table" and Players:GetPlayerByUserId(info.PlayerId)
 if not product or not player or not self.wallets:Entry(player) then return Enum.ProductPurchaseDecision.NotProcessedYet end
 local ok,outcome = self.wallets:Transact(player,{kind="receipt",id=tostring(info.PurchaseId),product=product.id,at=os.time()})
 if ok or (outcome and outcome.duplicate) then
  if ok then
   self:_publish(player)
   self:_dress(player)
   self:_notify(player,"感謝支持！已獲得 "..icon..product.crowns..(product.items and "與禮包外觀" or "").."。","Victory")
  end
  return Enum.ProductPurchaseDecision.PurchaseGranted
 end
 return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- 對局結束獎勵（伺服器事實：模式、結果、時長、是否投降）。每場對局每人只發一次。
function Shop:MatchReward(player,matchId,facts)
 if not self.wallets:Entry(player) or not ShopRules.token(matchId) then return end
 local amount = ShopRules.matchReward(Catalog,facts)
 if amount==0 then return end
 task.spawn(function()
  local ok,outcome = self.wallets:Transact(player,{kind="grant",id=matchId,day=today(),at=os.time(),facts=facts})
  if ok then
   self:_notify(player,"對局獎勵："..icon..outcome.crowns..(outcome.firstWin and "（含每日首勝獎勵）" or "")..(outcome.capped and "　今日對局金冠已達上限" or ""))
  elseif outcome and outcome.capped then
   self:_notify(player,"今日對局金冠已達上限，明天再來！每日登入獎勵仍可領取。")
  end
 end)
end

-- 勝利慶典：在勝利玩家的主城上方施放。
function Shop:Celebrate(player,position)
 if typeof(position)~="Vector3" then return end
 Cosmetic.Celebrate(position,player:GetAttribute("CosmeticVictory"),workspace)
end

-- 建築與單位在生成時套用擁有者目前的外觀（電腦玩家沒有外觀屬性，維持預設）。
function Shop.StyleBuilding(model,actor)
 Cosmetic.StyleBuilding(model,actor:GetAttribute("CosmeticBuildingStyle"))
end

-- 伺服器唯一的商店（ProcessReceipt 只能設定一次）。
local instance
function Shop.Get()
 if not instance then instance = Shop.new() end
 return instance
end

return Shop
