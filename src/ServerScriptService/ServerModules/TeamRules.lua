-- Pure server authority: only assign() creates a valid, immutable match team map.
-- Build the roster from queued server states; never accept a roster or team ID from a remote.
local TeamRules = {}
TeamRules.Modes = table.freeze({FFA=true, Teams=true, CoopAI=true})
local issued = setmetatable({}, {__mode="k"})
local maxId = 9007199254740991

local function integer(value, minimum, maximum)
 return type(value)=="number" and value==value and value%1==0 and value>=minimum and value<=maximum
end
local function validId(id)
 -- Studio human IDs and server AI IDs can both be negative; sign is not a role check.
 return integer(id,-maxId,maxId) and id~=0
end
local function arrayLength(values, allowEmpty)
 if type(values)~="table" or getmetatable(values)~=nil then return nil end
 local length=#values
 if length>4 or (not allowEmpty and length<1) then return nil end
 local count=0
 for key in pairs(values) do
  if not integer(key,1,length) then return nil end
  count+=1
 end
 if count~=length then return nil end
 for index=1,length do if values[index]==nil then return nil end end
 return length
end

function TeamRules.validateMode(mode, humanCount, aiCount)
 if type(mode)~="string" or not TeamRules.Modes[mode] then return nil,"不支援的分隊模式。" end
 if not integer(humanCount,1,4) or not integer(aiCount,0,3) or humanCount+aiCount>4 then
  return nil,"真人與電腦合計最多四個陣營，且至少需要一名真人。"
 end
 local total=humanCount+aiCount
 if mode=="Teams" and total~=2 and total~=4 then return nil,"分隊對戰需要兩個或四個陣營。" end
 if mode=="CoopAI" and aiCount<1 then return nil,"合作對電腦需要至少一個電腦陣營。" end
 return mode
end

local function settings(value)
 if type(value)~="table" or getmetatable(value)~=nil then return nil,"分隊設定無效。" end
 for key in pairs(value) do
  if key~="mode" and key~="humanCount" and key~="aiCount" then return nil,"分隊設定包含不支援的欄位。" end
 end
 local mode,message=TeamRules.validateMode(value.mode,value.humanCount,value.aiCount)
 if not mode then return nil,message end
 return table.freeze({mode=mode,humanCount=value.humanCount,aiCount=value.aiCount})
end

-- Returns nextSettings, errorMessage, resetReady. The server applies resetReady to all queued players.
function TeamRules.changeSettings(current, requested, requesterId, hostId, phase)
 if phase~="Lobby" or not validId(requesterId) or not validId(hostId) or requesterId~=hostId then
  return nil,"只有房主能在大廳調整分隊設定。",false
 end
 local nextSettings,message=settings(requested)
 if not nextSettings then return nil,message,false end
 local previous,previousMessage=settings(current)
 if not previous then return nil,previousMessage,false end
 local changed=previous.mode~=nextSettings.mode or previous.humanCount~=nextSettings.humanCount or previous.aiCount~=nextSettings.aiCount
 return nextSettings,nil,changed
end

function TeamRules.assign(mode, participants)
 local length=arrayLength(participants,false)
 if not length then return nil,"參戰名單必須是最多四方的完整陣列。" end
 local roster,seen,humanCount,aiCount={},{},0,0
 for index=1,length do
  local member=participants[index]
  if type(member)~="table" or getmetatable(member)~=nil or not validId(member.id) or type(member.ai)~="boolean" then
   return nil,"參戰身分無效。"
  end
  for key in pairs(member) do
   if key~="id" and key~="ai" and key~="spectator" then return nil,"參戰名單不得自行指定隊伍或數值。" end
  end
  if member.spectator~=nil and member.spectator~=false then return nil,"旁觀者不能加入參戰隊伍。" end
  if seen[member.id] then return nil,"參戰身分不得重複。" end
  seen[member.id]=true
  if member.ai then aiCount+=1 else humanCount+=1 end
  table.insert(roster,{id=member.id,ai=member.ai})
 end
 local validated,message=TeamRules.validateMode(mode,humanCount,aiCount)
 if not validated then return nil,message end
 -- Stable server IDs make allocation independent of remote arrival order; alternate humans first.
 table.sort(roster,function(a,b)
  if a.ai~=b.ai then return not a.ai end
  return a.id<b.id
 end)
 local teamById,slotById,aiById,memberIds,teamMembers,teamIds={},{},{},{},{},{}
 local usedSlots,humanIndex,aiIndex={},0,0
 -- Config.Spawns 1/3 share the northern edge, while 2/4 share the southern edge.
 local humanSlots,aiSlots={1,3,4,2},{2,4,3,1}
 for index,member in ipairs(roster) do
  local team,slot
  if mode=="FFA" then team,slot=index,index
  elseif mode=="Teams" then team,slot=(index-1)%2+1,index
  else
   team=member.ai and 2 or 1
   local priority=member.ai and aiSlots or humanSlots
   local nextIndex=member.ai and aiIndex+1 or humanIndex+1
   while usedSlots[priority[nextIndex]] do nextIndex+=1 end
   slot=priority[nextIndex]
   if member.ai then aiIndex=nextIndex else humanIndex=nextIndex end
  end
  usedSlots[slot]=true
  teamById[member.id],slotById[member.id],aiById[member.id]=team,slot,member.ai
  table.insert(memberIds,member.id)
  if not teamMembers[team] then teamMembers[team]={}; table.insert(teamIds,team) end
  table.insert(teamMembers[team],member.id)
 end
 table.sort(teamIds)
 for _,members in pairs(teamMembers) do table.freeze(members) end
 local assignment=table.freeze({
  mode=mode,humanCount=humanCount,aiCount=aiCount,
  teamById=table.freeze(teamById),slotById=table.freeze(slotById),aiById=table.freeze(aiById),
  memberIds=table.freeze(memberIds),teamMembers=table.freeze(teamMembers),teamIds=table.freeze(teamIds),
 })
 issued[assignment]=true
 return assignment
end

function TeamRules.team(assignment, id)
 if type(assignment)~="table" or not issued[assignment] or not validId(id) then return nil end
 return assignment.teamById[id]
end
function TeamRules.allied(assignment, firstId, secondId)
 local first,second=TeamRules.team(assignment,firstId),TeamRules.team(assignment,secondId)
 return first~=nil and second~=nil and first==second
end
function TeamRules.enemies(assignment, firstId, secondId)
 local first,second=TeamRules.team(assignment,firstId),TeamRules.team(assignment,secondId)
 return first~=nil and second~=nil and first~=second
end

-- A reconnect can reuse an ID while observing. Authority belongs to the original server state.
function TeamRules.isParticipant(assignment,registeredStates,state)
 return type(registeredStates)=="table" and type(state)=="table"
  and TeamRules.team(assignment,state.id)~=nil and registeredStates[state.id]==state
end

-- One outcome policy shared by session reports, persistent PvP records, and feedback.
-- Natural faction elimination does not settle a coalition result; forfeits always lose.
function TeamRules.result(assignment,id,winnerTeam,ended,forfeited)
 local team=TeamRules.team(assignment,id)
 if not team then return nil,"此身分不屬於本局參戰隊伍。" end
 if type(ended)~="boolean" or type(forfeited)~="boolean" then return nil,"結算狀態無效。" end
 if winnerTeam~=nil and (not integer(winnerTeam,1,4) or not assignment.teamMembers[winnerTeam] or not ended) then
  return nil,"勝利隊伍無效。"
 end
 if forfeited then return "loss" end
 if not ended then return "pending" end
 if winnerTeam==nil then return "draw" end
 return team==winnerTeam and "win" or "loss"
end

-- aliveIds must be collected from this match's authoritative playing/nondefeated states.
function TeamRules.aliveTeams(assignment, aliveIds)
 if type(assignment)~="table" or not issued[assignment] then return nil,"對局分隊尚未建立。" end
 local length=arrayLength(aliveIds,true)
 if not length then return nil,"存活陣營名單無效。" end
 local seenIds,seenTeams,result={},{},{}
 for index=1,length do
  local id=aliveIds[index]
  local team=TeamRules.team(assignment,id)
  if not team or seenIds[id] then return nil,"存活陣營包含未知或重複的身分。" end
  seenIds[id],seenTeams[team]=true,true
 end
 for _,team in ipairs(assignment.teamIds) do if seenTeams[team] then table.insert(result,team) end end
 return table.freeze(result)
end

-- Returns winnerTeamId, ended, errorMessage. A draw has no winner; solo sandbox stays open while alive.
function TeamRules.winner(assignment, aliveIds)
 local teams,message=TeamRules.aliveTeams(assignment,aliveIds)
 if not teams then return nil,false,message end
 if #teams==0 then return nil,true end
 if #teams==1 and #assignment.teamIds>=2 then return teams[1],true end
 return nil,false
end

return table.freeze(TeamRules)
