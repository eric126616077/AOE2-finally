-- 跨 place 傳送：大廳預留對戰伺服器、寫入票據並整隊傳送；對戰伺服器讀取票據與送玩家回大廳。
-- 引擎服務可注入，CLI 測試以替身驗證重試與失敗流程；所有會等待的呼叫都要在 task.spawn 內使用。
local PlaceRules = require(script.Parent.PlaceRules)
local Travel = {}
Travel.__index = Travel
local TICKET_MAP = "RTSMatchTickets_v1"

local function retrying(attempts, pause, wait, callback)
 local ok, a, b
 for attempt = 1, attempts do
  ok, a, b = pcall(callback)
  if ok then return true, a, b end
  if attempt < attempts then wait(pause * attempt) end
 end
 return false, a
end

function Travel.new(places, role, options)
 options = options or {}
 local self = setmetatable({places = places, role = role, pending = {}}, Travel)
 self.wait = options.wait or task.wait
 self.log = options.log or warn
 self.teleport = options.teleport
 self.tickets = options.tickets
 self.makeOptions = options.makeOptions or function(accessCode, data)
  local teleportOptions = Instance.new("TeleportOptions")
  if accessCode then teleportOptions.ReservedServerAccessCode = accessCode end
  if data then teleportOptions:SetTeleportData(data) end
  return teleportOptions
 end
 if role == "Combined" then return self end
 if not self.teleport then self.teleport = game:GetService("TeleportService") end
 if not self.tickets then
  local ok, map = pcall(function() return game:GetService("MemoryStoreService"):GetHashMap(TICKET_MAP) end)
  if ok then self.tickets = map else self.log("[RTS Travel] MemoryStore 無法初始化："..tostring(map)) end
 end
 self.connection = self.teleport.TeleportInitFailed:Connect(function(player, result, message, placeId, teleportOptions)
  self:_failed(player, result, message, placeId, teleportOptions)
 end)
 return self
end

-- 傳送已送出後才失敗：暫時性錯誤重送同一組選項，最後交給呼叫者恢復玩家狀態。
function Travel:_failed(player, result, message, placeId, teleportOptions)
 local entry = self.pending[player]
 if not entry then return end
 local name = typeof(result) == "EnumItem" and result.Name or tostring(result)
 local decision = PlaceRules.retry(name, entry.attempts, self.places.teleportAttempts)
 if decision == "ignore" then return end
 if decision == "retry" then
  entry.attempts += 1
  task.spawn(function()
   self.wait(self.places.retryPause * entry.attempts)
   if self.pending[player] ~= entry or player.Parent == nil then return end
   local ok, err = pcall(function() self.teleport:TeleportAsync(placeId, {player}, teleportOptions) end)
   if not ok then self:_failed(player, "Failure", err, placeId, teleportOptions) end
  end)
  return
 end
 self.pending[player] = nil
 self.log("[RTS Travel] 傳送失敗："..player.Name.." "..name.." "..tostring(message))
 if entry.onFailed then entry.onFailed(player, name) end
end

function Travel:Cancel(player)
 self.pending[player] = nil
end

function Travel:_send(placeId, players, teleportOptions, onFailed)
 for _, player in ipairs(players) do self.pending[player] = {attempts = 1, onFailed = onFailed} end
 local ok, err = retrying(self.places.teleportAttempts, self.places.retryPause, self.wait, function()
  local online = {}
  for _, player in ipairs(players) do
   if player.Parent ~= nil and self.pending[player] then table.insert(online, player) end
  end
  if #online > 0 then self.teleport:TeleportAsync(placeId, online, teleportOptions) end
 end)
 if not ok then
  for _, player in ipairs(players) do self.pending[player] = nil end
  return false, err
 end
 return true
end

-- 大廳：預留伺服器 → 寫入票據 → 整隊傳送。任一步失敗都不留下已傳送的玩家，呼叫者恢復房間。
function Travel:Dispatch(players, ticket, onFailed)
 if self.role ~= "Lobby" or not self.tickets then return false, "對戰伺服器服務無法使用。" end
 local placeId = self.places.matchPlaceId
 local ok, accessCode, privateServerId = retrying(self.places.teleportAttempts, self.places.retryPause, self.wait, function()
  return self.teleport:ReserveServer(placeId)
 end)
 if not ok or type(accessCode) ~= "string" or type(privateServerId) ~= "string" then
  self.log("[RTS Travel] 預留對戰伺服器失敗："..tostring(accessCode))
  return false, "無法預留對戰伺服器，請稍後再試。"
 end
 local written, err = retrying(self.places.teleportAttempts, self.places.retryPause, self.wait, function()
  self.tickets:SetAsync(privateServerId, ticket, self.places.ticketTtl)
 end)
 if not written then
  self.log("[RTS Travel] 寫入對局票據失敗："..tostring(err))
  return false, "無法傳送對局設定，請稍後再試。"
 end
 local sent, sendError = self:_send(placeId, players, self.makeOptions(accessCode, {matchId = ticket.matchId}), onFailed)
 if not sent then
  self.log("[RTS Travel] 傳送到對戰伺服器失敗："..tostring(sendError))
  pcall(function() self.tickets:RemoveAsync(privateServerId) end)
  return false, "傳送到對戰伺服器失敗，請重新準備。"
 end
 return true
end

-- 對戰伺服器：以自己的 PrivateServerId 讀票據；讀不到回傳 nil。
function Travel:ReadTicket(privateServerId)
 if self.role ~= "Match" or not self.tickets then return nil end
 local ok, value = retrying(self.places.ticketReadAttempts, self.places.retryPause, self.wait, function()
  return self.tickets:GetAsync(privateServerId)
 end)
 if not ok then self.log("[RTS Travel] 讀取對局票據失敗："..tostring(value)); return nil end
 return value
end
function Travel:RemoveTicket(privateServerId)
 if self.tickets then pcall(function() self.tickets:RemoveAsync(privateServerId) end) end
end

-- 對戰伺服器：送回大廳的公開伺服器；只用 SourcePlaceId 顯示歡迎，不攜帶需要信任的資料。
function Travel:Return(players, onFailed)
 if self.role ~= "Match" or #players == 0 then return false end
 return self:_send(self.places.lobbyPlaceId, players, self.makeOptions(nil, nil), onFailed)
end

return Travel
