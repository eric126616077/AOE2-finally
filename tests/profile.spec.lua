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

-- 教程旗標：單向、冪等、不被其他伺服器的舊增量還原，也不接受 true 以外的值。
local taught=ProfileRules.merge(empty,{tutorialDone=true},Config)
expect(taught.tutorialDone==true and empty.tutorialDone==nil,"tutorial completion not merged or mutated stored input")
expect(ProfileRules.merge(taught,{results={after_tutorial={outcome="win",endedAt=300}}},Config).tutorialDone==true,"later delta cleared tutorial completion")
expect(ProfileRules.merge(taught,{tutorialDone=false},Config).tutorialDone==true and ProfileRules.merge(empty,{tutorialDone=false},Config).tutorialDone==nil,"tutorial flag could be reverted or set by a false value")
local badTutorial=table.clone(empty); badTutorial.tutorialDone="yes"
expect(not ProfileRules.read(badTutorial,Config),"malformed tutorial flag accepted")
local tutorialRuntime=harness(first)
local tutorialStore=ProfileStore.new(Config,tutorialRuntime.options)
local tutorialPlayer=tutorialRuntime:player(30)
tutorialStore:Open(tutorialPlayer)
expect(tutorialStore:CompleteTutorial(tutorialPlayer) and tutorialPlayer.attributes.TutorialDone==true,"completion before load was not shown to this session")
tutorialRuntime:drain()
expect(tutorialRuntime.raw.tutorialDone==true and sameStats(tutorialRuntime.raw,1,0) and tutorialRuntime.writes==1,"pending completion not saved after load or erased statistics")
expect(not tutorialStore:CompleteTutorial(tutorialPlayer),"repeated completion wrote again")
tutorialRuntime:drain()
expect(tutorialRuntime.writes==1 and tutorialStore.entries[tutorialPlayer].tutorialDone==nil,"saved completion kept a pending write")
tutorialStore:Close(tutorialPlayer)
expect(next(tutorialStore.entries)==nil,"tutorial session leaked a closed profile entry")
local returning=ProfileStore.new(Config,tutorialRuntime.options)
local returningPlayer=tutorialRuntime:player(30)
returning:Open(returningPlayer)
expect(returningPlayer.attributes.TutorialDone==false and returningPlayer.attributes.ProfileStatus=="Loading","unloaded profile claimed a tutorial state")
tutorialRuntime:drain()
expect(returningPlayer.attributes.TutorialDone==true and tutorialRuntime.writes==1,"returning player not recognised or needlessly rewritten")
local studioTutorial=ProfileStore.new(Config,disabledRuntime.options)
local studioPlayer=disabledRuntime:player(31)
studioTutorial:Open(studioPlayer)
expect(studioPlayer.attributes.TutorialDone==false and studioTutorial:CompleteTutorial(studioPlayer) and studioPlayer.attributes.TutorialDone==true,"Studio session cannot finish the tutorial")
studioTutorial:Close(studioPlayer)
expect(disabledRuntime.writes==0 and next(studioTutorial.entries)==nil,"Studio tutorial completion reached the cloud or leaked")
local failedTutorial=ProfileStore.new(Config,failedRuntime.options)
local failedTutorialPlayer=failedRuntime:player(32)
failedTutorial:Open(failedTutorialPlayer); failedRuntime:drain()
failedTutorial:CompleteTutorial(failedTutorialPlayer); failedRuntime:drain()
expect(failedRuntime.writes==0 and failedTutorialPlayer.attributes.TutorialDone==true,"failed-load session wrote the tutorial flag or kept nagging")

-- 熱鍵偏好：只接受格式正確的字串，跨場次保存，不影響戰績與教程旗標。
local keyText="build=Q;stop=B"
local keyed=ProfileRules.merge(taught,{hotkeys=keyText},Config)
expect(keyed.hotkeys==keyText and keyed.tutorialDone==true and taught.hotkeys==nil,"hotkeys not merged, erased other fields or mutated stored input")
expect(ProfileRules.merge(keyed,{results={after_keys={outcome="win",endedAt=400}}},Config).hotkeys==keyText,"later delta cleared saved hotkeys")
for _,bad in ipairs({"",42,true,{},"build=Q stop=B","build=1","<script>",string.rep("a",513)}) do
 expect(not ProfileRules.hotkeys(bad) and ProfileRules.merge(keyed,{hotkeys=bad},Config).hotkeys==keyText,"malformed hotkeys replaced the saved value")
end
local badKeys=table.clone(empty); badKeys.hotkeys=42
expect(not ProfileRules.read(badKeys,Config),"malformed stored hotkeys accepted")
local keyRuntime=harness(first)
local keyStore=ProfileStore.new(Config,keyRuntime.options)
local keyPlayer=keyRuntime:player(40)
keyStore:Open(keyPlayer)
expect(keyPlayer.attributes.SavedHotkeys==nil,"unloaded profile claimed saved hotkeys")
expect(keyStore:SetHotkeys(keyPlayer,keyText) and keyPlayer.attributes.SavedHotkeys==keyText,"change before load was not accepted")
keyRuntime:drain()
expect(keyRuntime.raw.hotkeys==keyText and sameStats(keyRuntime.raw,1,0) and keyRuntime.writes==1,"pending hotkeys not saved after load or erased statistics")
expect(not keyStore:SetHotkeys(keyPlayer,keyText) and not keyStore:SetHotkeys(keyPlayer,"bad value") and not keyStore:SetHotkeys(keyPlayer,nil),"unchanged or malformed hotkeys scheduled a write")
expect(keyStore:SetHotkeys(keyPlayer,"build=Z") and keyStore:SetHotkeys(keyPlayer,"build=Y"),"later change rejected")
keyRuntime:drain()
expect(keyRuntime.writes==1 and #keyRuntime.timers==1,"rapid rebinding was not debounced into one pending write")
keyRuntime:timersOnce()
expect(keyRuntime.raw.hotkeys=="build=Y" and keyRuntime.writes==2 and keyStore.entries[keyPlayer].hotkeys==nil,"debounced hotkeys not saved or kept pending")
expect(keyStore:SetHotkeys(keyPlayer,"build=X"),"change before leaving rejected")
keyStore:Close(keyPlayer); keyRuntime:drain()
expect(keyRuntime.raw.hotkeys=="build=X" and next(keyStore.entries)==nil,"leaving did not flush hotkeys or leaked the entry")
expect(not keyStore:SetHotkeys(keyPlayer,"build=W"),"closed profile accepted hotkeys")
local keyReturning=ProfileStore.new(Config,keyRuntime.options)
local keyReturningPlayer=keyRuntime:player(40)
local keyWrites=keyRuntime.writes
keyReturning:Open(keyReturningPlayer); keyRuntime:drain()
expect(keyReturningPlayer.attributes.SavedHotkeys=="build=X" and keyRuntime.writes==keyWrites,"returning player did not receive saved hotkeys or was rewritten")
local studioKeys=ProfileStore.new(Config,disabledRuntime.options)
local studioKeyPlayer=disabledRuntime:player(41)
studioKeys:Open(studioKeyPlayer)
expect(not studioKeys:SetHotkeys(studioKeyPlayer,keyText) and disabledRuntime.writes==0,"Studio session saved hotkeys to the cloud")
studioKeys:Close(studioKeyPlayer)
local failedKeys=ProfileStore.new(Config,failedRuntime.options)
local failedKeyPlayer=failedRuntime:player(42)
failedKeys:Open(failedKeyPlayer); failedRuntime:drain()
failedKeys:SetHotkeys(failedKeyPlayer,keyText); failedKeys:Close(failedKeyPlayer); failedRuntime:drain()
expect(failedRuntime.writes==0,"failed-load session overwrote the profile with hotkeys")

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
-- 劇情進度：只往前、取較大值，格式錯誤的存檔不被接受；載入前通關也會在之後寫入。
local cleared=ProfileRules.merge(empty,{storyCleared=2},Config)
expect(cleared.storyCleared==2 and empty.storyCleared==nil,"story progress not merged or mutated stored input")
expect(ProfileRules.merge(cleared,{storyCleared=1},Config).storyCleared==2,"older story progress rolled the profile back")
expect(ProfileRules.merge(cleared,{storyCleared=3},Config).storyCleared==3,"later story progress ignored")
for _,bad in ipairs({-1,1.5,"2",true,0/0,100}) do
 expect(ProfileRules.merge(cleared,{storyCleared=bad},Config).storyCleared==2,"malformed story progress merged")
 local stored=table.clone(empty); stored.storyCleared=bad
 expect(not ProfileRules.read(stored,Config),"malformed stored story progress accepted")
end
local storyRuntime=harness(first)
local storyStore=ProfileStore.new(Config,storyRuntime.options)
local storyPlayer=storyRuntime:player(31)
storyStore:Open(storyPlayer)
expect(storyStore:CompleteStory(storyPlayer,1) and storyPlayer.attributes.StoryCleared==1,"story clear before load not shown")
expect(not storyStore:CompleteStory(storyPlayer,1) and not storyStore:CompleteStory(storyPlayer,"2"),"repeated or malformed story clear accepted")
storyRuntime:drain()
expect(storyRuntime.raw.storyCleared==1 and sameStats(storyRuntime.raw,1,0),"story clear not saved after load or erased statistics")
expect(storyStore:CompleteStory(storyPlayer,2) and storyPlayer.attributes.StoryCleared==2,"next chapter clear rejected")
storyRuntime:drain()
expect(storyRuntime.raw.storyCleared==2 and storyStore.entries[storyPlayer].storyCleared==nil,"saved story clear kept a pending write")
storyStore:Close(storyPlayer)
storyRuntime:drain()
expect(next(storyStore.entries)==nil,"story session leaked a closed profile entry")
print(string.format("PASS: %d profile concurrency / load-safety / PvP eligibility / analytics checks",count))
