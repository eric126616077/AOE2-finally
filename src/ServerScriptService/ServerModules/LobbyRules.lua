-- Pure validation shared by the lobby authority and regression tests.
local MatchRules = require(script.Parent.MatchRules)
local TeamRules = require(script.Parent.TeamRules)
local LobbyRules = {}

-- Never create a room from an untrusted identifier; old callers retain access to the first station.
function LobbyRules.room(portals, roomId)
 if roomId == nil or roomId == "Custom" then roomId = "Room1" end
 if type(roomId) ~= "string" or #roomId > 24 or type(portals) ~= "table" then return nil end
 for _, portal in ipairs(portals) do
  if portal.id == roomId then return portal end
 end
 return nil
end

function LobbyRules.settings(payload)
 if type(payload) ~= "table" then return nil, "集合設定無效。" end
 local expected = payload.expectedPlayers
 if not MatchRules.finite(expected) or expected % 1 ~= 0 or expected < 1 or expected > 4 then
  return nil, "參戰玩家人數必須介於 1 到 4。"
 end
 local settings, message = MatchRules.settings(payload, expected)
 if not settings then return nil, message end
 return settings, expected
end

function LobbyRules.canStart(expected, members)
 if not MatchRules.finite(expected) or expected % 1 ~= 0 or expected < 1 or expected > 4
  or type(members) ~= "table" or #members ~= expected then
  return false, "尚未等齊設定的參戰玩家。"
 end
 for _, member in ipairs(members) do
  if member.queued ~= true or member.ready ~= true then return false, "所有參戰玩家都要確認準備。" end
 end
 return true
end

-- Preview only the complete server queue; absent players and spectators never get a team.
function LobbyRules.teamPreview(mode,expected,members,aiIds)
 if not MatchRules.finite(expected) or expected%1~=0 or expected<1 or expected>4
  or type(members)~="table" or getmetatable(members)~=nil or #members~=expected
  or type(aiIds)~="table" or getmetatable(aiIds)~=nil then return nil,"參戰名單尚未齊全。" end
 local roster={}
 local count=0
 for key in pairs(members) do
  if not MatchRules.finite(key) or key%1~=0 or key<1 or key>expected then return nil,"參戰名單無效。" end
  count+=1
 end
 if count~=expected then return nil,"參戰名單無效。" end
 for index=1,expected do
  local member=members[index]
  if type(member)~="table" or getmetatable(member)~=nil or member.queued~=true or member.ai~=false
   or member.playing==true or (member.spectator~=nil and member.spectator~=false) then return nil,"只有已集合真人能預覽隊伍。" end
  table.insert(roster,{id=member.id,ai=false})
 end
 count=0
 for key in pairs(aiIds) do
  if not MatchRules.finite(key) or key%1~=0 or key<1 or key>3 then return nil,"電腦預覽名單無效。" end
  count+=1
 end
 if count~=#aiIds then return nil,"電腦預覽名單無效。" end
 for index=1,count do
  if aiIds[index]==nil then return nil,"電腦預覽名單無效。" end
  table.insert(roster,{id=aiIds[index],ai=true})
 end
 return TeamRules.assign(mode,roster)
end

-- humanStates is already sorted by the server; preserve an online host before migration.
function LobbyRules.matchHost(currentHostId, humanStates)
 if type(humanStates) ~= "table" then return 0 end
 for _, state in ipairs(humanStates) do
  if state.id == currentHostId then return state.id end
 end
 for _, state in ipairs(humanStates) do
  if state.playing then return state.id end
 end
 return humanStates[1] and humanStates[1].id or 0
end

return LobbyRules
