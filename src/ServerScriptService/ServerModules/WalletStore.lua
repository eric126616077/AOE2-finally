-- 錢包儲存：每次異動都是一次 UpdateAsync 交易，轉換函式以雲端目前資料重算（WalletRules.apply）。
-- 失敗時不改變任何資料：不扣金冠、不發外觀；Robux 收據回傳 NotProcessedYet 讓 Roblox 稍後重送。
-- Studio 或未發布的 place 使用本工作階段的記憶體儲存：流程相同，但離開後不保留。
local Rules = require(script.Parent.WalletRules)
local Store = {}
Store.__index = Store
local EQUIP_DELAY = 4 -- 連續切換外觀合併成一次寫入；離開時立即寫入。
local ATTEMPTS = 3

local function deepCopy(value)
 if type(value)~="table" then return value end
 local copy = {}
 for k,v in pairs(value) do copy[k] = deepCopy(v) end
 return copy
end
local Memory = {}
Memory.__index = Memory
function Memory.new() return setmetatable({data={}},Memory) end
function Memory:GetAsync(key) return deepCopy(self.data[key]) end
function Memory:UpdateAsync(key,transform)
 local value = transform(deepCopy(self.data[key]))
 if value~=nil then self.data[key] = deepCopy(value) end
 return deepCopy(self.data[key])
end
Store.Memory = Memory

function Store.new(catalog,options)
 options = options or {}
 local persistent = options.persistent
 if persistent==nil then persistent = not game:GetService("RunService"):IsStudio() and game.PlaceId>0 end
 local self = setmetatable({catalog=catalog,persistent=persistent,entries={},pending=0},Store)
 self.defer = options.defer or task.defer
 self.delay = options.delay or task.delay
 self.wait = options.wait or task.wait
 self.log = options.log or warn
 if options.store then self.store = options.store
 elseif persistent then
  local ok,value = pcall(function() return game:GetService("DataStoreService"):GetDataStore("RTS_Wallet_v1") end)
  if ok then self.store = value else self.log("[RTS Wallet] 雲端資料服務無法初始化。") end
 else self.store = Memory.new() end
 return self
end

local function keyOf(userId) return "w_"..userId end

function Store:Open(player,onChange)
 if self.entries[player] then return self.entries[player] end
 local entry = {player=player,status="Loading",data=nil,onChange=onChange}
 self.entries[player] = entry
 self.defer(function()
  local ok,raw = pcall(function() if not self.store then error("store unavailable") end; return self.store:GetAsync(keyOf(player.UserId)) end)
  local data = ok and Rules.read(raw)
  if self.entries[player]~=entry then return end
  if not data then
   entry.status = "LoadFailed"
   self.log("[RTS Wallet] 錢包讀取失敗；本工作階段只在交易成功後更新顯示。")
  else
   entry.status,entry.data = "Ready",data
  end
  if entry.onChange then entry.onChange(entry) end
 end)
 return entry
end

-- 只對記憶體儲存有效（Studio 測試用）：沒有資料時建立含起始金冠的錢包。
function Store:Seed(player,crowns)
 if self.persistent or getmetatable(self.store)~=Memory or self.store.data[keyOf(player.UserId)]~=nil then return false end
 local data = Rules.empty()
 data.crowns = crowns
 self.store.data[keyOf(player.UserId)] = data
 return true
end

function Store:Entry(player) return self.entries[player] end

-- 會 yield。回傳 (成功, 結果說明)。成功代表資料已寫入雲端（或記憶體）；取消（例如餘額不足）回傳 false。
function Store:Transact(player,op)
 if not self.store then return false,{ok=false,reason="雲端資料暫時無法使用，請稍後再試。"} end
 self.pending += 1
 local outcome,written,updated
 for attempt=1,ATTEMPTS do
  local ok,result = pcall(function()
   return self.store:UpdateAsync(keyOf(player.UserId),function(current)
    local value,info = Rules.apply(current,op,self.catalog)
    outcome,written = info,value~=nil
    return value
   end)
  end)
  if ok then updated = result; break end
  outcome,written = {ok=false,reason="雲端資料暫時無法使用，請稍後再試。"},false
  if attempt<ATTEMPTS then self.wait(attempt) end
 end
 self.pending -= 1
 local entry = self.entries[player]
 if written then
  local data = Rules.read(updated)
  -- 交易可能並行完成：只接受版本較新的結果。
  if entry and data and (not entry.data or data.rev>entry.data.rev) then
   entry.data,entry.status = data,"Ready"
   if entry.pendingEquip then for slot,id in pairs(entry.pendingEquip) do entry.data.equipped[slot] = id end end
   if entry.onChange then entry.onChange(entry) end
  end
  return true,outcome
 end
 return false,outcome or {ok=false,reason="交易未完成。"}
end

-- 裝備是外觀偏好：先更新本工作階段顯示，稍後合併寫入。
function Store:Equip(player,slot,id,vip)
 local entry = self.entries[player]
 if not entry or entry.status~="Ready" then return false end
 entry.pendingEquip = entry.pendingEquip or {}
 entry.pendingEquip[slot] = id
 entry.data.equipped[slot] = id
 entry.vip = vip
 if not entry.equipScheduled then
  entry.equipScheduled = true
  self.delay(EQUIP_DELAY,function()
   entry.equipScheduled = false
   self:FlushEquip(player)
  end)
 end
 return true
end

function Store:FlushEquip(player)
 local entry = self.entries[player]
 if not entry or not entry.pendingEquip then return end
 local choices = entry.pendingEquip
 entry.pendingEquip = nil
 local ok,outcome = self:Transact(player,{kind="equip",equipped=choices,vip=entry.vip==true})
 if not ok and not (outcome and outcome.unchanged) then self.log("[RTS Wallet] 外觀選擇未能儲存。") end
end

function Store:Close(player)
 local entry = self.entries[player]
 if not entry then return end
 self.entries[player] = nil
 if entry.pendingEquip then
  self.entries[player] = entry -- 寫入完成前保留，讓 Transact 找得到裝備暫存。
  entry.onChange = nil
  self.defer(function()
   self:FlushEquip(player)
   if self.entries[player]==entry then self.entries[player] = nil end
  end)
 end
end

function Store:FlushAll()
 for player,entry in pairs(self.entries) do
  if entry.pendingEquip then self.defer(function() self:FlushEquip(player) end) end
 end
 local deadline = os.clock()+20
 self.wait(0.1)
 while self.pending>0 and os.clock()<deadline do self.wait(0.1) end
end

return Store
