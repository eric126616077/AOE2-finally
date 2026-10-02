-- Actual modules are bundled by scripts/verify.ps1; network and scheduling alone are mocked.
local PreferenceRules=require("../src/ServerScriptService/ServerModules/CivilizationPreferenceRules")
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local function sameStats(a,wins,losses) return a and a.pvpWins==wins and a.pvpLosses==losses end
local empty=ProfileRules.empty(Config)
local first=ProfileRules.merge(empty,{results={match_a={outcome="win",endedAt=100}}},Config)
expect(sameStats(first,1,0),"first server result not counted")
expect(sameStats(empty,0,0) and next(empty.resultJournal)==nil,"transform mutated stored input")
local duplicate=ProfileRules.merge(first,{results={match_a={outcome="loss",endedAt=101}}},Config)
expect(sameStats(duplicate,1,0),"duplicate match counted or changed winner")
local second=ProfileRules.merge(first,{results={match_b={outcome="loss",endedAt=102}}},Config)
expect(sameStats(second,1,1),"second server overwrote prior server results")
local pref=ProfileRules.merge(second,{preference={civilization="Sunspire",stamp=200,token="later"}},Config)
local stale=ProfileRules.merge(pref,{preference={civilization="JadeGrove",stamp=199,token="stale"}},Config)
expect(stale.civilization=="Sunspire","late older server selection overwrote newer choice")
for _,bad in ipairs({true,{}, {version=2}, {version=1,pvpWins=math.huge}, {version=1,pvpWins=-1}}) do
 expect(not ProfileRules.read(bad,Config),"invalid or future profile accepted")
end
local corrupt=table.clone(empty); corrupt.food=9000
expect(not ProfileRules.read(corrupt,Config),"gameplay resources allowed into persistent profile")
expect(not ProfileRules.merge(corrupt,{results={}},Config),"corrupt profile could be overwritten")
expect(not ProfileRules.merge(empty,{results=true},Config),"malformed result delta accepted")
local many={}
for i=1,ProfileRules.JournalLimit+3 do many["history_"..i]={outcome="win",endedAt=i} end
local compact=ProfileRules.merge(empty,{results=many},Config)
local journalCount=0; for _ in pairs(compact.resultJournal) do journalCount+=1 end
expect(journalCount<=ProfileRules.JournalLimit and compact.resultFloor>0,"match journal grew without a bound")
local replay=ProfileRules.merge(compact,{results={history_1={outcome="win",endedAt=1}}},Config)
expect(replay.pvpWins==compact.pvpWins,"evicted result replay could double count")
expect(ProfileRules.eligible(true,2,0,true),"valid production pure PvP rejected")
for _,case in ipairs({{false,2,0,true},{true,1,0,true},{true,2,1,true},{true,2,0,false},{true,math.huge,0,true},{true,5,0,true}}) do
 expect(not ProfileRules.eligible(table.unpack(case)),"Studio / practice / unstarted match could create PvP results")
end

local function harness(raw,loadFails,writeFails)
 local runtime={jobs={},timers={},raw=raw,writes=0,reads=0,logs={}}
 function runtime:drain()
  while #self.jobs>0 do local fn=table.remove(self.jobs,1); fn() end
 end
 function runtime:timersOnce()
  local timers=self.timers; self.timers={}
  for _,fn in ipairs(timers) do fn() end
  self:drain()
 end
 local database={}
 function database:GetAsync()
  runtime.reads+=1
  if loadFails then error("simulated read failure") end
  return runtime.raw
 end
 function database:UpdateAsync(_,transform)
  runtime.writes+=1
  if writeFails then error("simulated write failure") end
  -- Roblox may reevaluate a transform; both evaluations must be free of side effects.
  local old=runtime.raw
  local one=transform(old)
  local two=transform(old)
  expect((one==nil and two==nil) or sameStats(two,one.pvpWins,one.pvpLosses),"transform retry changed its own outcome")
  runtime.raw=two or old
  return two
 end
 runtime.options={enabled=true,store=database,defer=function(fn) table.insert(runtime.jobs,fn) end,
  delay=function(_,fn) table.insert(runtime.timers,fn) end,wait=function() end,now=function() return 1000 end,
  guid=function() runtime.token=(runtime.token or 0)+1; return "session_"..runtime.token end,
  log=function(message) table.insert(runtime.logs,message) end}
 function runtime:player(id)
  return {UserId=id,attributes={},SetAttribute=function(self,key,value) self.attributes[key]=value end}
 end
 return runtime
end
local disabledRuntime=harness(nil)
disabledRuntime.options.enabled=false
local disabled=ProfileStore.new(Config,disabledRuntime.options)
local offlinePlayer=disabledRuntime:player(10)
disabled:Open(offlinePlayer)
expect(offlinePlayer.attributes.ProfileStatus=="Disabled" and disabledRuntime.reads==0,"Studio default could read cloud")
expect(not disabled:RecordResult(offlinePlayer,"studio","win",2000),"disabled profile recorded PvP")
disabled:Close(offlinePlayer)
expect(disabledRuntime.writes==0 and next(disabled.entries)==nil,"disabled profile wrote data or leaked player")

local failedRuntime=harness(first,true)
local failed=ProfileStore.new(Config,failedRuntime.options)
local failedPlayer=failedRuntime:player(11)
failed:Open(failedPlayer)
failedRuntime:drain()
failed:SelectCivilization(failedPlayer,"JadeGrove")
failed:RecordResult(failedPlayer,"after_bad_read","win",2000)
failed:Close(failedPlayer)
failedRuntime:drain()
expect(failedPlayer.attributes.ProfileStatus=="LoadFailed" and failedRuntime.writes==0,"read failure overwrote historical profile")
expect(failedRuntime.raw==first and first.pvpWins==1,"failed-load session modified old data")

local concurrentRuntime=harness(first)
local serverA=ProfileStore.new(Config,concurrentRuntime.options)
local serverB=ProfileStore.new(Config,concurrentRuntime.options)
local playerA=concurrentRuntime:player(12)
local playerB=concurrentRuntime:player(12)
serverA:Open(playerA); serverB:Open(playerB); concurrentRuntime:drain()
serverA:RecordResult(playerA,"concurrent_a","win",2000)
serverB:RecordResult(playerB,"concurrent_b","loss",2001)
concurrentRuntime:drain()
expect(sameStats(concurrentRuntime.raw,2,1),"two servers lost each other's session deltas")
serverB:RecordResult(playerB,"concurrent_a","win",2000)
concurrentRuntime:drain()
expect(sameStats(concurrentRuntime.raw,2,1),"cross-server duplicate match awarded twice")
expect(not serverA:RecordResult(playerA,"bad id!","win",2000),"invalid match identifier accepted")

local lateRuntime=harness(ProfileRules.merge(empty,{preference={civilization="Sunspire",stamp=500,token="saved"}},Config))
local late=ProfileStore.new(Config,lateRuntime.options)
local latePlayer=lateRuntime:player(13)
local selectedState={civilization="RiverHaven",civilizationRevision=0}
late:Open(latePlayer,function(profile)
 local choice=PreferenceRules.receive(selectedState,profile.civilization,"Lobby")
 if choice then selectedState.civilization=choice end
end)
PreferenceRules.select(selectedState); selectedState.civilization="JadeGrove"; late:SelectCivilization(latePlayer,"JadeGrove")
lateRuntime:drain()
expect(selectedState.civilization=="JadeGrove" and lateRuntime.raw.civilization=="JadeGrove","late load overwrote explicit selection")
late:SelectCivilization(latePlayer,"Sunspire")
late:SelectCivilization(latePlayer,"RiverHaven")
lateRuntime:timersOnce()
expect(lateRuntime.raw.civilization=="RiverHaven","two same-millisecond selections saved earlier choice")

for index,loadPhase in ipairs({"Starting","Playing","Ended"}) do
 local stagedRuntime=harness(ProfileRules.merge(empty,{preference={civilization="Sunspire",stamp=500,token="saved_stage"}},Config))
 local stagedStore=ProfileStore.new(Config,stagedRuntime.options)
 local stagedPlayer=stagedRuntime:player(20+index)
 local stagedState={civilization="RiverHaven",civilizationRevision=0}
 stagedStore:Open(stagedPlayer,function(profile)
  local choice=PreferenceRules.receive(stagedState,profile.civilization,loadPhase)
  if choice then stagedState.civilization=choice end
 end)
 stagedRuntime:drain()
 expect(stagedState.civilization=="RiverHaven" and stagedState.pendingCivilization=="Sunspire","non-lobby load changed this match or discarded saved choice")
 expect(not PreferenceRules.takeLobby(stagedState,loadPhase),"pending preference applied during match")
 local choice=PreferenceRules.takeLobby(stagedState,"Lobby")
 if choice then stagedState.civilization=choice end
 expect(stagedState.civilization=="Sunspire" and stagedState.pendingCivilization==nil,"return to lobby did not apply delayed saved preference")
 expect(not PreferenceRules.takeLobby(stagedState,"Lobby"),"saved pending preference reapplied twice")
 expect(stagedRuntime.writes==0,"restoring a saved preference needlessly wrote cloud data")
end

local defaultRuntime=harness(ProfileRules.merge(empty,{preference={civilization="Sunspire",stamp=500,token="saved_default_case"}},Config))
local defaultStore=ProfileStore.new(Config,defaultRuntime.options)
local defaultPlayer=defaultRuntime:player(24)
local defaultState={civilization=Config.DefaultCivilization,civilizationRevision=0,pendingCivilization="JadeGrove"}
defaultStore:Open(defaultPlayer,function(profile)
 local choice=PreferenceRules.receive(defaultState,profile.civilization,"Lobby")
 if choice then defaultState.civilization=choice end
end)
PreferenceRules.select(defaultState)
defaultStore:SelectCivilization(defaultPlayer,Config.DefaultCivilization)
expect(defaultState.pendingCivilization==nil,"explicit default choice did not clear pending saved preference")
defaultRuntime:drain()
expect(defaultState.civilization==Config.DefaultCivilization and defaultState.pendingCivilization==nil,"late load overrode an explicit default choice")
expect(defaultRuntime.raw.civilization==Config.DefaultCivilization,"explicit default preference was not persisted")
expect(not PreferenceRules.takeLobby(defaultState,"Lobby"),"explicit choice allowed stale pending preference on a later lobby")

local departedRuntime=harness(nil)
local departedStore=ProfileStore.new(Config,departedRuntime.options)
local departedPlayer=departedRuntime:player(25)
departedStore:Open(departedPlayer,function() error("closed session must not invoke live preference callback") end)
departedStore:SelectCivilization(departedPlayer,"Sunspire") -- Time 1000; its original load is still pending.
departedStore:RecordResult(departedPlayer,"old_server_loss","loss",1500)
departedStore:Close(departedPlayer)
departedRuntime.raw=ProfileRules.merge(empty,{preference={civilization="JadeGrove",stamp=2000,token="newer_server"},
 results={new_server_win={outcome="win",endedAt=2100}}},Config)
departedRuntime:drain() -- Delayed old-server read now sees the new server's preference and statistics.
expect(departedRuntime.raw.civilization=="JadeGrove" and departedRuntime.raw.preferenceStamp==2000,"closed late load promoted an old selection over newer server preference")
expect(sameStats(departedRuntime.raw,1,1),"closed old server did not merge its own result without erasing newer server result")
expect(next(departedStore.entries)==nil,"departed delayed-load profile was not released")

local activeRuntime=harness(nil)
local activeStore=ProfileStore.new(Config,activeRuntime.options)
local activePlayer=activeRuntime:player(26)
local activeState={civilization=Config.DefaultCivilization,civilizationRevision=0}
activeStore:Open(activePlayer,function(profile)
 local choice=PreferenceRules.receive(activeState,profile.civilization,"Lobby")
 if choice then activeState.civilization=choice end
end)
PreferenceRules.select(activeState); activeState.civilization="Sunspire"
activeStore:SelectCivilization(activePlayer,"Sunspire") -- Actual choice time 1000; remain active while read waits.
activeStore:RecordResult(activePlayer,"active_server_loss","loss",1500)
activeRuntime.raw=ProfileRules.merge(empty,{preference={civilization="JadeGrove",stamp=2000,token="active_newer_server"},
 results={active_new_server_win={outcome="win",endedAt=2100}}},Config)
activeRuntime:drain()
expect(activeRuntime.raw.civilization=="JadeGrove" and activeRuntime.raw.preferenceStamp==2000,"active late load fabricated a newer timestamp and overrode later external choice")
expect(activeState.civilization=="Sunspire" and activeState.pendingCivilization==nil,"newer external stored choice overwrote this session's explicit UI selection")
expect(sameStats(activeRuntime.raw,1,1),"active older session erased newer server results or failed to merge its own result")
expect(activeStore.entries[activePlayer].preference==nil and activePlayer.attributes.ProfileStatus=="Ready","active merge retained stale preference for repeated writes")
activeStore:Close(activePlayer)
expect(next(activeStore.entries)==nil,"active cross-server regression left a closed profile entry")

local writeFailureRuntime=harness(first,false,true)
local writeFailure=ProfileStore.new(Config,writeFailureRuntime.options)
local writeFailurePlayer=writeFailureRuntime:player(14)
writeFailure:Open(writeFailurePlayer); writeFailureRuntime:drain()
writeFailure:RecordResult(writeFailurePlayer,"pending_loss","loss",2000)
writeFailureRuntime:drain()
expect(writeFailure.entries[writeFailurePlayer].results.pending_loss~=nil,"failed save discarded pending result")
writeFailure:Close(writeFailurePlayer)
writeFailureRuntime:drain()
writeFailureRuntime:timersOnce(); writeFailureRuntime:timersOnce()
expect(writeFailureRuntime.raw==first and next(writeFailure.entries)==nil,"bounded failure cleanup corrupted data or leaked player")

local emitted={}
local analytics={LogFunnelStepEvent=function(_,player,name,id,step,stepName)
 table.insert(emitted,{kind="funnel",step=step,name=name,id=id,stepName=stepName})
end,LogCustomEvent=function(_,player,name,value,fields)
 table.insert(emitted,{kind="custom",name=name,value=value,fields=fields})
end}
local analyticsOptions={enabled=true,service=analytics,guid=function() return "funnel-session" end,defer=function(fn) fn() end,log=function() end}
local telemetry=Telemetry.new(analyticsOptions)
telemetry:Join(playerA); telemetry:Join(playerA)
telemetry:Fact(playerA,"queue"); telemetry:Fact(playerA,"start")
telemetry:Fact(playerA,"firsttrain"); telemetry:Fact(playerA,"firsthouse")
expect(#emitted==3,"out-of-order facts fabricated skipped funnel steps")
telemetry:Fact(playerA,"firstdeliver")
expect(#emitted==6,"confirmed delayed facts did not complete funnel")
for i=1,6 do expect(emitted[i].step==i and emitted[i].id=="funnel-session","funnel signature / session / order changed") end
telemetry:Fact(playerA,"firstdeliver"); telemetry:Fact(playerA,"firsthouse")
expect(#emitted==6,"repeated server action duplicated onboarding event")
telemetry:Match(playerA,"Completed",42.9,{mode="PurePvP",civilization="Sunspire",size="Small"})
expect(emitted[7].name=="RTSMatchCompleted" and emitted[7].value==42 and emitted[7].fields.CustomField01=="Mode=PurePvP","custom event signature / value / fields incorrect")
telemetry:Leave(playerA); telemetry:Fact(playerA,"queue")
expect(next(telemetry.sessions)==nil and #emitted==7,"telemetry leaked leaving player")
local offlineTelemetry=Telemetry.new({enabled=false,service=analytics,defer=function(fn) fn() end,guid=function() return "offline" end})
offlineTelemetry:Join(playerB); offlineTelemetry:Match(playerB,"Started",0)
expect(#emitted==7,"Studio analytics reached live service")
print(string.format("PASS: %d profile concurrency / load-safety / PvP eligibility / analytics checks",count))
