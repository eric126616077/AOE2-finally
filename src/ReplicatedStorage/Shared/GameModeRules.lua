-- 大廳玩法（劇情／玩家對戰／合作對電腦）的共用規則。
-- 伺服器用 apply 驗證並補齊房間設定；客戶端只用 next / label 顯示與提出下一個選項，結果仍由伺服器決定。
local Config = require(script.Parent.Parent.GameData.GameConfig)
local Rules = {}
local Modes = Config.GameModes
local Chapters = Config.Story.chapters
Rules.Order = Modes.order
Rules.ChapterCount = #Chapters
-- 每種玩法允許的分隊方式；第一個是切換玩法時的預設。
local teamModes = {Story={"CoopAI"}, PvP={"FFA","Teams"}, PvE={"CoopAI","FFA"}, Sandbox={"FFA"}}
local presetFields = {"size","difficulty","population","startingResources","victory"}
local defaults = {size="Medium",difficulty="Normal",population=100,startingResources="Standard",victory="Conquest"}

local function integer(value, minimum, maximum)
 return type(value)=="number" and value==value and value%1==0 and value>=minimum and value<=maximum
end

function Rules.mode(id)
 return type(id)=="string" and Modes[id]~=nil and id~="order" and Modes[id] or nil
end
function Rules.chapter(index)
 return integer(index,1,#Chapters) and Chapters[index] or nil
end
-- 已通關章數 → 可選的最後一章。
function Rules.unlocked(cleared)
 return math.clamp(integer(cleared,0,99) and cleared+1 or 1,1,#Chapters)
end
-- 多人劇情時電腦陣營不超過剩餘出生點，至少保留一個敵方。
function Rules.storyAI(chapter, humans)
 return math.max(1,math.min(chapter.aiCount,4-humans))
end
function Rules.allowsTeamMode(mode, teamMode)
 return table.find(teamModes[mode] or {},teamMode)~=nil
end

-- 舊的開發呼叫沒有 gameMode；只補上顯示用的玩法，不另加限制。
function Rules.infer(payload)
 local humans,ai=payload.expectedPlayers,payload.aiCount
 if ai==0 then return humans==1 and "Sandbox" or "PvP" end
 return "PvE"
end

-- 回傳補齊後的新設定表；options.internal 允許伺服器建立 Sandbox，options.unlocked 限制可選章節。
function Rules.apply(payload, options)
 if type(payload)~="table" then return nil,"集合設定無效。" end
 options = options or {}
 local result = table.clone(payload)
 local id = payload.gameMode
 if id==nil then
  result.gameMode,result.storyChapter = Rules.infer(payload),0
  return result
 end
 local mode = Rules.mode(id)
 if not mode then return nil,"不支援的遊戲模式。" end
 if mode.internal and options.internal~=true then return nil,"這個模式只能由新手教程建立。" end
 local humans = payload.expectedPlayers
 if not integer(humans,1,4) then return nil,"參戰玩家人數必須介於 1 到 4。" end
 if humans<mode.minPlayers or humans>mode.maxPlayers then
  return nil,mode.title.."需要 "..mode.minPlayers..(mode.maxPlayers>mode.minPlayers and "–"..mode.maxPlayers or "").." 位真人玩家。"
 end
 if id=="Story" then
  local index = payload.storyChapter
  local chapter = Rules.chapter(index)
  if not chapter then return nil,"劇情章節無效。" end
  if options.unlocked~=nil and index>options.unlocked then return nil,"尚未解鎖這個章節，請先完成前一章。" end
  for _,key in ipairs(presetFields) do result[key]=chapter[key] end
  result.aiCount,result.teamMode = Rules.storyAI(chapter,humans),"CoopAI"
  return result
 end
 result.storyChapter = 0
 local teamMode = payload.teamMode==nil and "FFA" or payload.teamMode
 if not Rules.allowsTeamMode(id,teamMode) then return nil,mode.title.."不支援這種分隊方式。" end
 result.teamMode = teamMode
 if id=="PvP" and payload.aiCount~=0 then return nil,"玩家對戰只有真人玩家，不加入電腦。" end
 if id=="PvE" and not integer(payload.aiCount,1,3) then return nil,"合作對電腦需要至少一位電腦對手。" end
 if id=="Sandbox" and payload.aiCount~=0 then return nil,"練習局沒有電腦對手。" end
 return result
end

-- 切換玩法時的起始設定；保留仍然合法的人數與規則，劇情從最新解鎖章節開始。
-- 離開劇情時不沿用章節規則，回到一般預設。
local function valid(settings)
 if not integer(settings.expectedPlayers,1,4) or not integer(settings.aiCount,0,3) then return false end
 local total = settings.expectedPlayers+settings.aiCount
 if total>4 then return false end
 if settings.teamMode=="Teams" and total~=2 and total~=4 then return false end
 return settings.teamMode~="CoopAI" or settings.aiCount>=1
end
function Rules.defaults(id, humans, unlocked, previous)
 local mode = Rules.mode(id)
 if not mode then return nil end
 unlocked = math.clamp(integer(unlocked,1,#Chapters) and unlocked or 1,1,#Chapters)
 local inherit = type(previous)=="table" and previous.gameMode~="Story" and previous or nil
 local result = {gameMode=id,storyChapter=0,teamMode=teamModes[id][1]}
 for key,value in pairs(defaults) do result[key]=inherit and inherit[key]~=nil and inherit[key] or value end
 result.expectedPlayers = math.clamp(integer(humans,1,4) and humans or mode.minPlayers,mode.minPlayers,mode.maxPlayers)
 if id=="Story" then
  local wanted = type(previous)=="table" and previous.storyChapter
  result.storyChapter = Rules.chapter(wanted) and wanted<=unlocked and wanted or unlocked
 end
 if id=="PvP" or id=="Sandbox" then result.aiCount=0
 else result.aiCount=math.clamp(inherit and integer(inherit.aiCount,1,3) and inherit.aiCount or (id=="PvE" and 2 or 1),1,4-result.expectedPlayers) end
 if inherit and Rules.allowsTeamMode(id,inherit.teamMode) then result.teamMode=inherit.teamMode end
 if not valid(result) then result.teamMode=teamModes[id][1] end
 return result
end

-- 客戶端提案：依序嘗試下一個值，修正成本玩法合法的組合；不會把已集合的玩家擠出房間。
function Rules.next(settings, key, values, queuedCount, unlocked)
 if type(settings)~="table" or type(key)~="string" or type(values)~="table" or #values<1 or #values>8 or not integer(queuedCount,0,4) then return nil end
 local id = settings.gameMode
 if not Rules.mode(id) then return nil end
 unlocked = integer(unlocked,1,#Chapters) and unlocked or 1
 local index = table.find(values,settings[key]) or 1
 local blocked
 for _=1,#values do
  index = index%#values+1
  local value = values[index]
  local request
  if key=="gameMode" then
   local mode = Rules.mode(value)
   if not mode or mode.internal then continue end
   if queuedCount>mode.maxPlayers then blocked=mode.title.."最多 "..mode.maxPlayers.." 位真人，目前集合人數較多。"; continue end
   request = Rules.defaults(value,math.max(queuedCount,integer(settings.expectedPlayers,1,4) and settings.expectedPlayers or 1),unlocked,settings)
  else
   if key=="storyChapter" and integer(value,1,#Chapters) and value>unlocked then blocked="完成前一章後才能選擇這一章。"; continue end
   request = table.clone(settings)
   request[key] = value
   if key=="expectedPlayers" and integer(value,1,4) and id=="PvE" then request.aiCount=math.clamp(integer(request.aiCount,1,3) and request.aiCount or 1,1,math.max(1,4-value)) end
  end
  local applied = Rules.apply(request,{unlocked=unlocked})
  if applied and valid(applied) and applied.expectedPlayers>=queuedCount then
   local changed = false
   for field,current in pairs(applied) do if settings[field]~=current then changed=true; break end end
   if changed then return applied,blocked end
  elseif applied and key=="teamMode" and value=="Teams" then blocked="分隊對戰需要 2 或 4 位玩家。" end
 end
 return nil,blocked or "目前人數沒有其他合法選項。"
end

-- 房間卡片與名單使用的簡短玩法說明。
function Rules.label(settings)
 if type(settings)~="table" then return "玩法載入中" end
 local mode = Rules.mode(settings.gameMode)
 if not mode then return "玩法載入中" end
 if settings.gameMode=="Story" then
  local chapter = Rules.chapter(settings.storyChapter)
  return chapter and ("劇情 · 第 "..settings.storyChapter.." 章 "..chapter.title) or "劇情"
 end
 if settings.gameMode=="PvP" then return mode.title..(settings.teamMode=="Teams" and " · 分隊" or " · 各自為戰") end
 if settings.gameMode=="PvE" then return mode.title..(settings.teamMode=="FFA" and " · 混戰" or "") end
 return mode.title
end

return table.freeze(Rules)
