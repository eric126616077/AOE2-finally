-- 跨 place 對局的純規則：判定伺服器角色、建立與驗證對局票據、抵達與傳送重試。
-- 票據由大廳伺服器寫入 MemoryStore，以保留伺服器的 PrivateServerId 為鍵；客戶端的 TeleportData 不被信任。
local LobbyRules = require(script.Parent.LobbyRules)
local PlaceRules = {}
PlaceRules.TICKET_VERSION = 1

local function positiveInteger(value)
 return type(value) == "number" and value == value and value % 1 == 0 and value > 0 and value < 2^53
end
local function finite(value)
 return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function shortString(value, limit)
 return type(value) == "string" and #value > 0 and #value <= limit
end

-- 兩個 place 都設定且不同時才分流；Studio 無法傳送，只能明確模擬對戰 place。
function PlaceRules.configured(places)
 return type(places) == "table" and positiveInteger(places.lobbyPlaceId) and positiveInteger(places.matchPlaceId)
  and places.lobbyPlaceId ~= places.matchPlaceId
end
function PlaceRules.role(places, placeId, isStudio, studioOverride)
 if isStudio then return studioOverride == "Match" and "Match" or "Combined" end
 if not PlaceRules.configured(places) then return "Combined" end
 if placeId == places.matchPlaceId then return "Match" end
 if placeId == places.lobbyPlaceId then return "Lobby" end
 return "Combined"
end
-- 只有 ReserveServer 建立的伺服器（有 PrivateServerId、沒有擁有者）可以讀取票據。
function PlaceRules.reserved(privateServerId, privateServerOwnerId)
 return shortString(privateServerId, 128) and privateServerOwnerId == 0
end

function PlaceRules.newTicket(matchId, roomId, settings, members, now)
 local players = {}
 for index, member in ipairs(members) do
  players[index] = {userId = member.id, civilization = member.civilization, tutorial = member.tutorial == true}
 end
 return {v = PlaceRules.TICKET_VERSION, matchId = matchId, roomId = roomId, settings = table.clone(settings),
  expected = #players, players = players, createdAt = now}
end

-- Studio 的 Server & Clients 測試玩家 UserId 為負數（Player1=-1）。放寬與否只由伺服器的 IsStudio 決定，
-- 不讀票據或任何玩家可控制的資料；正式伺服器一律要求正整數。
function PlaceRules.ticketOptions(isStudio)
 if isStudio == true then return {studioIds = true} end
 return nil
end
local function playerId(value, studioIds)
 if positiveInteger(value) then return true end
 return studioIds == true and type(value) == "number" and value % 1 == 0 and value < 0 and value > -2^53
end

-- 任何欄位不符都整張拒絕；設定再走一次與大廳相同的驗證。
function PlaceRules.readTicket(raw, now, maxAge, portals, options)
 local studioIds = type(options) == "table" and options.studioIds == true
 if type(raw) ~= "table" or raw.v ~= PlaceRules.TICKET_VERSION then return nil, "對局資料版本不符。" end
 if not shortString(raw.matchId, 64) then return nil, "對局識別無效。" end
 local portal = LobbyRules.room(portals, raw.roomId)
 if not portal then return nil, "對局房間無效。" end
 if not finite(raw.createdAt) or not finite(now) or not finite(maxAge)
  or raw.createdAt > now + 60 or now - raw.createdAt > maxAge then return nil, "對局資料已過期。" end
 if type(raw.players) ~= "table" or #raw.players < 1 or #raw.players > 4 or raw.expected ~= #raw.players then
  return nil, "參戰名單無效。"
 end
 local players, seen = {}, {}
 for index = 1, #raw.players do
  local entry = raw.players[index]
  if type(entry) ~= "table" or not playerId(entry.userId, studioIds) or seen[entry.userId]
   or (entry.civilization ~= nil and not shortString(entry.civilization, 32))
   or (entry.tutorial ~= nil and type(entry.tutorial) ~= "boolean") then return nil, "參戰名單無效。" end
  seen[entry.userId] = true
  players[index] = {userId = entry.userId, civilization = entry.civilization, tutorial = entry.tutorial == true}
 end
 if type(raw.settings) ~= "table" or raw.settings.expectedPlayers ~= nil then return nil, "對局設定無效。" end
 local payload = table.clone(raw.settings)
 payload.expectedPlayers = #players
 -- 大廳已檢查章節解鎖與內部模式（新手教程）；票據只重驗設定本身的合法性。
 local settings, message = LobbyRules.settings(payload, {internal = true})
 if not settings then return nil, message end
 return {matchId = raw.matchId, roomId = portal.id, settings = settings, expected = #players, players = players, createdAt = raw.createdAt}
end

function PlaceRules.member(ticket, userId)
 if type(ticket) ~= "table" then return nil end
 for _, entry in ipairs(ticket.players) do
  if entry.userId == userId then return entry end
 end
 return nil
end

-- 全員抵達立即開局；逾時後以已抵達者開局，沒有人抵達則放棄。
function PlaceRules.arrival(expected, present, elapsed, timeout)
 if not positiveInteger(expected) or type(present) ~= "number" or present < 0 or not finite(elapsed) or not finite(timeout) then
  return "abort"
 end
 if present >= expected then return "start" end
 if elapsed < timeout then return "wait" end
 return present > 0 and "start" or "abort"
end

-- TeleportInitFailed 的暫時性結果才重試；IsTeleporting 表示已在途中，不重送。
local retryable = {Failure = true, Flooded = true, Unknown = true}
function PlaceRules.retry(resultName, attempts, maxAttempts)
 if resultName == "IsTeleporting" then return "ignore" end
 if retryable[resultName] and type(attempts) == "number" and attempts < maxAttempts then return "retry" end
 return "fail"
end

return PlaceRules
