local Rules=require(script.Parent.ProfileRules)
local Store={}
Store.__index=Store
local SAVE_DELAY=15 -- Debounce rapid lobby choices; completed results and departures flush immediately.
local MAX_RETRIES=3
function Store.new(config,options)
 options=options or {}
 local enabled=options.enabled
 if enabled==nil then enabled=not game:GetService("RunService"):IsStudio() and game.PlaceId>0 end
 local self=setmetatable({config=config,enabled=enabled,entries={},pendingWrites=0},Store)
 self.defer=options.defer or task.defer
 self.delay=options.delay or task.delay
 self.wait=options.wait or task.wait
 self.now=options.now or function() return DateTime.now().UnixTimestampMillis end
 self.guid=options.guid or function() return game:GetService("HttpService"):GenerateGUID(false) end
 self.log=options.log or warn
 if enabled then
  if options.store then self.store=options.store
  else
   local ok,value=pcall(function() return game:GetService("DataStoreService"):GetDataStore("RTS_Profile_v1") end)
   if ok then self.store=value else self.log("[RTS Profile] 雲端資料服務無法初始化。") end
  end
 end
 return self
end
function Store:_publish(entry)
 local view=Rules.merge(entry.base,{preference=entry.preference,results=entry.results},self.config) or Rules.empty(self.config)
 entry.player:SetAttribute("ProfileStatus",entry.status)
 entry.player:SetAttribute("ProfileLoaded",entry.status=="Ready" or entry.status=="SaveFailed")
 entry.player:SetAttribute("PvPWins",view.pvpWins)
 entry.player:SetAttribute("PvPLosses",view.pvpLosses)
end
function Store:Open(player,onLoaded)
 if self.entries[player] then return end
 local entry={player=player,base=Rules.empty(self.config),status=self.enabled and "Loading" or "Disabled",results={},attempts=0}
 self.entries[player]=entry
 self:_publish(entry)
 if not self.enabled then return end
 self.defer(function()
  local ok,raw=pcall(function() if not self.store then error("store unavailable") end; return self.store:GetAsync("u_"..player.UserId) end)
  local loaded=ok and Rules.read(raw,self.config)
  if not loaded then
   entry.status="LoadFailed"
   self:_publish(entry)
   self.log("[RTS Profile] 個人檔案讀取失敗，本工作階段不會覆寫雲端資料。")
   if entry.closed then self.entries[player]=nil end
   return
  end
  entry.base,entry.status=loaded,"Ready"
  -- Loading observes stored state; it must never give an earlier local choice a new timestamp.
  self:_publish(entry)
  if not entry.closed and onLoaded then
   local applied=pcall(onLoaded,loaded)
   if not applied then self.log("[RTS Profile] 已讀取檔案，但大廳偏好未能套用。") end
  end
  if entry.closed or entry.preference or next(entry.results) then self:Save(player) end
 end)
end
function Store:_schedule(entry,seconds)
 if entry.scheduled then return end
 entry.scheduled=true
 self.delay(seconds,function()
  entry.scheduled=false
  if self.entries[entry.player]==entry then self:Save(entry.player) end
 end)
end
function Store:SelectCivilization(player,id)
 local entry=self.entries[player]
 local data=self.config.Civilizations[id]
 if not entry or not self.enabled or not data or not data.public then return false end
 local previous=entry.preference and entry.preference.stamp or entry.base.preferenceStamp
 entry.preference={civilization=id,stamp=math.max(self.now(),previous+1),token=self.guid()}
 entry.attempts=0
 if entry.status=="Ready" or entry.status=="SaveFailed" then self:_schedule(entry,SAVE_DELAY) end
 return true
end
function Store:RecordResult(player,matchId,outcome,endedAt)
 local entry=self.entries[player]
 local result={outcome=outcome,endedAt=endedAt}
 if not self.enabled or not entry or entry.closed or not Rules.result(result) or not Rules.validMatchId(matchId) then return false end
 if entry.results[matchId] or entry.base.resultJournal[matchId] then return false end
 entry.results[matchId]=result
 entry.attempts=0
 self:_publish(entry)
 self:Save(player)
 return true
end
function Store:Save(player)
 local entry=self.entries[player]
 if not entry or not self.enabled or entry.status=="Loading" or entry.status=="LoadFailed" then return false end
 if entry.saving then entry.saveAgain=true; return false end
 if not entry.preference and not next(entry.results) then if entry.closed then self.entries[player]=nil end; return true end
 local snapshot={preference=entry.preference and table.clone(entry.preference),results={}}
 for id,result in pairs(entry.results) do snapshot.results[id]=table.clone(result) end
 entry.saving=true
 self.pendingWrites+=1
 self.defer(function()
  local ok,updated=pcall(function()
   return self.store:UpdateAsync("u_"..player.UserId,function(current)
    return Rules.merge(current,snapshot,self.config) -- nil cancels corrupt / unsupported profiles; callback never yields.
   end)
  end)
  local loaded=ok and updated~=nil and Rules.read(updated,self.config)
  if loaded then
   entry.base,entry.status,entry.attempts=loaded,"Ready",0
   for id in pairs(snapshot.results) do entry.results[id]=nil end
   if snapshot.preference and entry.preference and snapshot.preference.token==entry.preference.token then entry.preference=nil end
  else
   entry.status="SaveFailed"
   entry.attempts+=1
   self.log("[RTS Profile] 個人檔案儲存失敗，保留本工作階段增量供重試。")
  end
  entry.saving=false
  self.pendingWrites-=1
  self:_publish(entry)
  local again=entry.saveAgain
  entry.saveAgain=false
  if loaded and (again or entry.preference or next(entry.results)) then self:Save(player)
  elseif not loaded and entry.attempts<MAX_RETRIES then self:_schedule(entry,5*entry.attempts)
  elseif entry.closed then self.entries[player]=nil end
 end)
 return true
end
function Store:Close(player)
 local entry=self.entries[player]
 if not entry then return end
 entry.closed=true
 if not self.enabled or entry.status=="LoadFailed" then self.entries[player]=nil; return end
 self:Save(player)
end
function Store:FlushAll()
 if not self.enabled then return end
 for player in pairs(self.entries) do self:Close(player) end
 local deadline=os.clock()+25
 while next(self.entries) and os.clock()<deadline do self.wait(0.1) end
end
return Store
