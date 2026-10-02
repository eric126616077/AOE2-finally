local Rules=require("../src/ReplicatedStorage/Shared/FeedbackRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local state=Rules.new()
local a,b={},{}
expect(Rules.Reserve(state,"Select",0),"first cue rejected")
Rules.Release(state,false)
expect(not Rules.Reserve(state,"Order",0.01),"global throttle allowed immediate next cue")
expect(not Rules.Reserve(state,"Select",0.05),"same cue bypassed its throttle")
expect(Rules.Reserve(state,"Order",0.05),"distinct cue remained blocked after global interval")
Rules.Release(state,false)
expect(not Rules.Reserve(state,"GatherWood",0.2),"world cue without source allowed")
expect(Rules.Reserve(state,"GatherWood",0.2,a),"world source cue rejected")
Rules.Release(state,true)
expect(not Rules.Reserve(state,"GatherGold",0.25,b),"global world crowd throttle ignored")
expect(not Rules.Reserve(state,"GatherGold",0.4,a),"same worker emitted multiple rapid cue kinds")
expect(Rules.Reserve(state,"GatherGold",0.4,b),"another worker rejected after world interval")
Rules.Reset(state)
for index=1,Rules.MaxWorldVoices do
 expect(Rules.Reserve(state,"GatherWood",index,{}),"world capacity exhausted early")
end
expect(not Rules.Reserve(state,"GatherWood",6,{}),"world polyphony overflow")
expect(Rules.Reserve(state,"Order",6),"world sounds starved order feedback")
expect(Rules.Reserve(state,"Error",7),"world sounds starved error feedback")
expect(Rules.Reserve(state,"Select",8),"last reserved interface voice rejected")
expect(not Rules.Reserve(state,"Age",9),"total polyphony overflow")
expect(state.total==8 and state.world==5,"voice counts drifted")
Rules.Release(state,true)
expect(state.total==7 and state.world==4,"world release left stale capacity")
expect(Rules.Reserve(state,"Age",10),"released capacity could not be reused")
Rules.Reset(state)
expect(state.total==0 and state.world==0 and next(state.cues)==nil and next(state.sources)==nil,"restart retained sound state")
state.enabled=false
expect(not Rules.Reserve(state,"Select",11),"muted audio reserved a voice")
Rules.Reset(state)
expect(not state.enabled,"restart silently unmuted sound")
state.enabled=true
for _,cue in ipairs({"Unknown","",false,3}) do expect(not Rules.Reserve(state,cue,12),"unrecognised cue accepted") end
for _,now in ipairs({math.huge,-math.huge,0/0,"12",false}) do expect(not Rules.Reserve(state,"Select",now),"invalid clock accepted") end
expect(state.total==0 and next(state.cues)==nil,"rejected cue consumed cooldown or voice")
expect(Rules.IsNewPulse(1,nil) and Rules.IsNewPulse(2,1),"fresh work pulse rejected")
expect(not Rules.IsNewPulse(1,1) and not Rules.IsNewPulse(1,2),"duplicate/stale work pulse replayed")
for _,value in ipairs({0,-1,math.huge,0/0,"1",false}) do expect(not Rules.IsNewPulse(value,nil),"invalid replicated pulse accepted") end
expect(Rules.WorldAudible(true,160,160) and Rules.WorldAudible(true,360,Rules.MaxDistance),"valid RTS camera source rejected")
expect(not Rules.WorldAudible(false,160,160),"offscreen work played audio")
expect(not Rules.WorldAudible(true,-1,160),"behind-camera work played audio")
expect(not Rules.WorldAudible(true,160,Rules.MaxDistance+0.01),"distant work played audio")
expect(not Rules.WorldAudible(true,0/0,160) and not Rules.WorldAudible(true,160,math.huge),"invalid camera geometry played audio")
local function positiveInteger(value) return type(value)=="number" and value>0 and value%1==0 end
for cue,data in pairs(Rules.Cues) do
 -- Short cues stay short; only stingers (age, victory) may run for several seconds.
 local limit=data.stinger and 8 or (data.world and 1.7 or 2.3)
 expect(type(data.fallback)=="string" and data.duration>0 and data.duration<=limit and data.volume>0 and data.volume<=2.5 and data.speed>0,"invalid cue envelope: "..cue)
 expect(type(data.variants)=="table" and #data.variants>=1,"cue without licensed variants: "..cue)
 for _,variant in ipairs(data.variants) do
  expect(positiveInteger(variant.id) and type(variant.start)=="number" and variant.start>=0 and variant.volume>0 and variant.volume<=2.5,"invalid variant: "..cue)
 end
 expect(Rules.AssetId(data.variants[1].id)=="rbxassetid://"..data.variants[1].id and Rules.FallbackId(data)=="rbxasset://sounds/"..data.fallback,"asset id formatting: "..cue)
 expect(not (data.world and data.stinger),"world cue marked as stinger: "..cue)
end
Rules.Reset(state)
expect(Rules.Reserve(state,"GatherWood",20,{}),"busy economy worker pulse failed")
expect(Rules.Reserve(state,"ConstructionComplete",20.001),"world pulse swallowed completion cue")
expect(not Rules.Reserve(state,"Research",20.002),"priority bypassed interface-to-interface throttle")
Rules.Release(state,false)
Rules.Release(state,true)
expect(Rules.Reserve(state,"GatherWood",21,{}),"second work pulse failed")
expect(not Rules.Reserve(state,"Error",20.999),"priority accepted a stale clock")
expect(Rules.Reserve(state,"Error",21.001),"world pulse swallowed an error cue")
Rules.Release(state,false)
Rules.Release(state,true)
expect(Rules.Reserve(state,"GatherGold",21.2,{}),"mining pulse failed")
expect(not Rules.Reserve(state,"Error",21.201),"priority bypassed its own cue interval")
-- A full pool must distinguish a valid priority replacement from a throttled
-- request. Only a pure capacity rejection authorizes stealing a world voice.
local crowded=Rules.new()
local lastWorker
for index=1,Rules.MaxWorldVoices do
 local worker={}
 expect(Rules.Reserve(crowded,"GatherWood",index,worker),"crowded world pool could not fill")
 lastWorker=worker
end
expect(Rules.Reserve(crowded,"Error",5.1) and Rules.Reserve(crowded,"Order",5.2) and Rules.Reserve(crowded,"Select",5.3),"crowded interface pool could not fill")
local total,world,last,lastWorld=crowded.total,crowded.world,crowded.last,crowded.lastWorld
local allowed,reason=Rules.Reserve(crowded,"Research",5.31)
expect(not allowed and reason==nil,"global-throttled priority incorrectly authorized preemption")
allowed,reason=Rules.Reserve(crowded,"Error",5.4)
expect(not allowed and reason==nil,"repeat priority cue incorrectly authorized preemption inside own cooldown")
allowed,reason=Rules.Reserve(crowded,"GatherGold",5.6,lastWorker)
expect(not allowed and reason==nil,"source-throttled world cue was classified as capacity")
allowed,reason=Rules.Reserve(crowded,"GatherWood",6)
expect(not allowed and reason==nil,"invalid world source was classified as capacity")
allowed,reason=Rules.Reserve(crowded,"Error",math.huge)
expect(not allowed and reason==nil,"invalid clock authorized preemption")
crowded.enabled=false
allowed,reason=Rules.Reserve(crowded,"Error",6)
expect(not allowed and reason==nil,"muted priority cue authorized preemption")
crowded.enabled=true
expect(crowded.total==total and crowded.world==world and crowded.last==last and crowded.lastWorld==lastWorld and crowded.cues.Error==5.1,
 "rejected full-pool cues mutated voices or playback clocks")
allowed,reason=Rules.Reserve(crowded,"Error",6)
expect(not allowed and reason=="capacity","valid full-pool priority did not report pure capacity rejection")
expect(crowded.total==total and crowded.world==world and crowded.cues.Error==5.1,"capacity rejection consumed a voice or cue cooldown")
Rules.Release(crowded,true)
expect(Rules.Reserve(crowded,"Error",6),"same-clock priority retry failed after one world voice was released")
expect(crowded.total==Rules.MaxVoices and crowded.world==Rules.MaxWorldVoices-1 and crowded.cues.Error==6,"priority replacement exceeded limits or changed its requested clock")
allowed,reason=Rules.Reserve(crowded,"Error",6.05)
expect(not allowed and reason==nil and crowded.total==Rules.MaxVoices and crowded.world==Rules.MaxWorldVoices-1,
 "full-pool duplicate priority authorized another world preemption")
-- Variants rotate deterministically and tolerate bad counters.
local wood=Rules.Cues.GatherWood
expect(Rules.Variant(wood,1)==wood.variants[1] and Rules.Variant(wood,#wood.variants+1)==wood.variants[1],"variant rotation did not wrap")
expect(Rules.Variant(wood,0/0)==wood.variants[1] and Rules.Variant(wood,math.huge)==wood.variants[1],"invalid variant index not normalized")
-- Identity sounds per selected kind; every mapped cue exists.
expect(Rules.SelectCue("infantry")=="SelectSword" and Rules.SelectCue("archer")=="SelectBow" and Rules.SelectCue("cavalry")=="SelectHooves","unit select cues")
expect(Rules.SelectCue(nil,"TownCenter")=="SelectBell" and Rules.SelectCue(nil,"Blacksmith")=="SelectAnvil" and Rules.SelectCue(nil,nil,"Tree")=="SelectChop","building/resource select cues")
expect(Rules.SelectCue(nil,"Unknown")=="Select" and Rules.SelectCue()=="Select","unknown selection lost its generic cue")
for _,cue in ipairs({Rules.SelectCue("villager"),Rules.SelectCue("siege"),Rules.SelectCue(nil,"House"),Rules.SelectCue(nil,"Castle"),Rules.SelectCue(nil,"University"),
 Rules.SelectCue(nil,"Market"),Rules.SelectCue(nil,"MiningCamp"),Rules.SelectCue(nil,"Farm"),Rules.SelectCue(nil,"SiegeWorkshop"),Rules.SelectCue(nil,"Tower"),
 Rules.OrderCue("attack"),Rules.OrderCue("military"),Rules.OrderCue("gather"),Rules.OrderCue("move"),Rules.OrderCue(nil),
 Rules.DeliveryCue("wood"),Rules.DeliveryCue("gold"),Rules.DeliveryCue("stone"),Rules.DeliveryCue("food"),Rules.DeliveryCue("")}) do
 expect(Rules.Cues[cue]~=nil,"mapped cue missing: "..tostring(cue))
end
expect(Rules.OrderCue("attack")=="OrderAttack" and Rules.OrderCue("bogus")=="Order","order intent mapping")
expect(Rules.AttackCue("ram",{class="siege",range=8})=="Ram" and Rules.AttackCue("mangonel",{class="siege",range=62})=="Siege","siege attack cues")
expect(Rules.AttackCue("archer",{class="archer",range=48})=="Ranged" and Rules.AttackCue("infantry",{class="infantry",range=6})=="Melee" and Rules.AttackCue("x",nil)==nil,"attack cue mapping")
for _,value in ipairs({0/0,math.huge,"1",nil}) do expect(Rules.VolumeSetting(value)==1,"malformed volume not treated as full") end
expect(Rules.VolumeSetting(-1)==0 and Rules.VolumeSetting(2)==1 and Rules.VolumeSetting(.4)==.4,"volume clamp")
-- Under-attack alerts: one horn per area, a minimum gap, and fresh areas later.
local alerts=Rules.newAlerts()
expect(Rules.Alert(alerts,100,0,0),"first attack did not alert")
expect(not Rules.Alert(alerts,103,10,10),"same area re-alerted during cooldown")
expect(not Rules.Alert(alerts,103,400,400),"distant area ignored minimum gap")
expect(Rules.Alert(alerts,106,400,400),"distant area did not alert after gap")
expect(not Rules.Alert(alerts,100+Rules.AlertCooldown+2,5,5),"continued fighting did not keep its area quiet")
expect(Rules.Alert(alerts,103+2*Rules.AlertCooldown+20,5,5),"quiet area never alerted again")
expect(not Rules.Alert(alerts,0/0,0,0) and not Rules.Alert(alerts,500,math.huge,0),"invalid alert input accepted")
-- Soundtrack mood needs sustained combat and calms after a quiet spell.
local mood=Rules.newMood()
expect(Rules.ReportCombat(mood,10)=="Peace" and Rules.ReportCombat(mood,11)=="Peace","single skirmish switched to battle music")
expect(Rules.ReportCombat(mood,12)=="Battle","sustained combat stayed peaceful")
expect(Rules.UpdateMood(mood,12+Rules.BattleCooldown-1)=="Battle","battle music ended too early")
expect(Rules.UpdateMood(mood,12+Rules.BattleCooldown)=="Peace" and #mood.events==0,"battle music never calmed down")
local sparse=Rules.newMood()
for _,time in ipairs({0,Rules.BattleWindow,2*Rules.BattleWindow}) do Rules.ReportCombat(sparse,time) end
expect(sparse.mood=="Peace","sparse hits outside the window became battle music")
-- Shuffle never repeats the previous track and stays in range.
for count=2,12 do
 for previous=1,count do
  for _,roll in ipairs({0,.25,.5,.75,.999999,1,0/0}) do
   local pick=Rules.NextTrack(count,previous,roll)
   expect(pick>=1 and pick<=count and pick~=previous,"shuffle repeated or overflowed")
  end
 end
end
expect(Rules.NextTrack(1,1,.5)==1 and Rules.NextTrack(0,nil,.5)==nil,"degenerate playlist")
for name,list in pairs(Rules.Music) do
 expect(#list>=3,"playlist too short: "..name)
 for _,track in ipairs(list) do expect(positiveInteger(track.id) and track.volume>0 and track.volume<=1.2 and track.length>30,"invalid track in "..name) end
end
for _,entry in ipairs(Rules.Ambience) do expect(positiveInteger(entry.id) and entry.volume>0,"invalid ambience") end
print(string.format("PASS: %d feedback throttle / polyphony / mute / camera gating / music / alert checks",checks))
