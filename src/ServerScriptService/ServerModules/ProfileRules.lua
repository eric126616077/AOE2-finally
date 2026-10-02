-- Persistent data contains preferences (civilization, hotkeys), the one-way tutorial flag and completed human-vs-human results only.
local Rules = {}
Rules.JournalLimit=512
local profileFields={version=true,civilization=true,preferenceStamp=true,preferenceToken=true,pvpWins=true,pvpLosses=true,resultJournal=true,resultFloor=true,tutorialDone=true,hotkeys=true}
local function integer(value)
 return type(value)=="number" and value==value and value>=0 and value<=9007199254740991 and value%1==0
end
local function token(value)
 return type(value)=="string" and #value>0 and #value<=100 and value:match("^[%w_:%-]+$")~=nil
end
Rules.validMatchId=token
-- 熱鍵是介面偏好字串（例如 "build=B;stop=X"）；這裡只管格式與長度，按鍵是否可用由 HotkeyRules 決定。
function Rules.hotkeys(value)
 return type(value)=="string" and #value>0 and #value<=512 and value:match("^[%a=;]+$")~=nil
end
local function civilization(config,id)
 local data=type(id)=="string" and config.Civilizations[id]
 return data and data.public and id or config.DefaultCivilization
end
function Rules.empty(config)
 return {version=1,civilization=config.DefaultCivilization,preferenceStamp=0,preferenceToken="initial",pvpWins=0,pvpLosses=0,resultJournal={},resultFloor=0}
end
function Rules.result(value)
 return type(value)=="table" and (value.outcome=="win" or value.outcome=="loss") and integer(value.endedAt) and value.endedAt>0
end
function Rules.read(raw,config)
 if raw==nil then return Rules.empty(config) end
 if type(raw)~="table" or raw.version~=1 then return nil end
 for field in pairs(raw) do if not profileFields[field] then return nil end end
 if type(raw.civilization)~="string" or not integer(raw.preferenceStamp) or not token(raw.preferenceToken)
  or not integer(raw.pvpWins) or not integer(raw.pvpLosses) or not integer(raw.resultFloor) or type(raw.resultJournal)~="table"
  or (raw.tutorialDone~=nil and raw.tutorialDone~=true) or (raw.hotkeys~=nil and not Rules.hotkeys(raw.hotkeys)) then return nil end
 local result=table.clone(raw)
 result.civilization=civilization(config,raw.civilization)
 result.resultJournal={}
 local count=0
 for id,entry in pairs(raw.resultJournal) do
  if not token(id) or not Rules.result(entry) then return nil end
  for field in pairs(entry) do if field~="outcome" and field~="endedAt" then return nil end end
  count+=1
  if count>Rules.JournalLimit then return nil end
  result.resultJournal[id]=table.clone(entry)
 end
 return result
end
function Rules.merge(raw,delta,config)
 local merged=Rules.read(raw,config)
 if not merged or type(delta)~="table" or (delta.results~=nil and type(delta.results)~="table") then return nil end
 local preference=delta.preference
 if preference and type(preference)=="table" and config.Civilizations[preference.civilization]
  and config.Civilizations[preference.civilization].public and integer(preference.stamp) and token(preference.token) then
  if preference.stamp>merged.preferenceStamp or (preference.stamp==merged.preferenceStamp and preference.token>merged.preferenceToken) then
   merged.civilization,merged.preferenceStamp,merged.preferenceToken=preference.civilization,preference.stamp,preference.token
  end
 end
 -- 教程旗標只會由未完成變為完成；其他伺服器的舊增量不能把它改回去。
 if delta.tutorialDone==true then merged.tutorialDone=true end
 -- 熱鍵以最後寫入為準；格式不對的增量直接忽略，不影響其他欄位。
 if Rules.hotkeys(delta.hotkeys) then merged.hotkeys=delta.hotkeys end
 for id,entry in pairs(delta.results or {}) do
  if token(id) and Rules.result(entry) and entry.endedAt>merged.resultFloor and not merged.resultJournal[id] then
   merged.resultJournal[id]={outcome=entry.outcome,endedAt=entry.endedAt}
   if entry.outcome=="win" then merged.pvpWins=math.min(9007199254740991,merged.pvpWins+1) else merged.pvpLosses=math.min(9007199254740991,merged.pvpLosses+1) end
  end
 end
 local ordered={}
 for id,entry in pairs(merged.resultJournal) do table.insert(ordered,{id=id,endedAt=entry.endedAt}) end
 table.sort(ordered,function(a,b) return a.endedAt==b.endedAt and a.id<b.id or a.endedAt<b.endedAt end)
 -- A time floor keeps evicted results idempotent, including delayed retries from old servers.
 if #ordered>Rules.JournalLimit then
  local floor=ordered[#ordered-Rules.JournalLimit].endedAt
  merged.resultFloor=math.max(merged.resultFloor,floor)
  for id,entry in pairs(merged.resultJournal) do if entry.endedAt<=merged.resultFloor then merged.resultJournal[id]=nil end end
 end
 return merged
end
function Rules.eligible(isProduction,humanCount,aiCount,successfullyStarted)
 return isProduction==true and successfullyStarted==true and integer(humanCount) and humanCount>=2 and humanCount<=4 and aiCount==0
end
return Rules
