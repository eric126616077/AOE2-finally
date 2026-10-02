-- Client-only soundtrack and ambience. Purely cosmetic: nothing waits for it,
-- and an asset that cannot load is skipped instead of retried forever.
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local TweenService=game:GetService("TweenService")
local Rules=require(script.Parent.FeedbackRules)
local Music={}
local MUSIC_MIX=.55
local AMBIENCE_MIX=.5
local CROSSFADE=2.5
local LOAD_TIMEOUT=10
local started=false
local musicGroup,ambienceGroup
local slots={}
local active -- slot currently audible
local mood="Silent"
local enabled,musicVolume,ambienceOn,soundVolume=true,1,false,1
local duckUntil,ducked=0,false
local groupTween
local history={}
local failed={}
local revision=0
local ambience={}
local trackName
local function groupVolume()
 local value=enabled and MUSIC_MIX*musicVolume or 0
 return ducked and value*.22 or value
end
local function applyGroup(time)
 if not musicGroup then return end
 if groupTween then groupTween:Cancel() end
 groupTween=TweenService:Create(musicGroup,TweenInfo.new(time or .4),{Volume=groupVolume()})
 groupTween:Play()
end
local function makeSlot(name)
 local sound=Instance.new("Sound")
 sound.Name=name
 sound.Looped=false
 sound.Volume=0
 sound.SoundGroup=musicGroup
 sound.Parent=SoundService
 return {sound=sound,track=nil,tween=nil,token=0}
end
local function fade(slot,volume,time,stopAfter)
 if slot.tween then slot.tween:Cancel() end
 slot.tween=TweenService:Create(slot.sound,TweenInfo.new(time),{Volume=volume})
 slot.tween:Play()
 if stopAfter then
  local token=slot.token
  task.delay(time,function()
   if slot.token==token and slot~=active then slot.sound:Stop() end
  end)
 end
end
local playNext
local function playlistFor(value)
 return Rules.Music[value]
end
-- Starts one track in the idle slot and crossfades the previous one out.
local function start(list,index)
 local track=list[index]
 local slot=active==slots[1] and slots[2] or slots[1]
 local previous=active
 slot.token+=1
 local token=slot.token
 slot.track=track
 slot.sound:Stop()
 slot.sound.SoundId=Rules.AssetId(track.id)
 slot.sound.TimePosition=0
 slot.sound.Volume=0
 active=slot
 trackName=track.name
 slot.sound:Play()
 fade(slot,track.volume,previous and previous.sound.IsPlaying and CROSSFADE or 1.2)
 if previous and previous~=slot then previous.token+=1; fade(previous,0,CROSSFADE,true) end
 -- Licensed tracks stream on demand; skip one that never decodes.
 local current=revision
 task.delay(LOAD_TIMEOUT,function()
  if slot.token==token and current==revision and active==slot and not slot.sound.IsLoaded then
   failed[track.id]=true
   warn("[RTS] 背景音樂無法載入，略過："..track.name)
   playNext()
  end
 end)
end
playNext=function()
 local list=playlistFor(mood)
 if not list or not enabled then return end
 local candidates={}
 for index,track in ipairs(list) do if not failed[track.id] then table.insert(candidates,index) end end
 if #candidates==0 then return end
 local previousPosition=history[mood] and table.find(candidates,history[mood])
 local pick=candidates[Rules.NextTrack(#candidates,previousPosition,math.random())]
 history[mood]=pick
 start(list,pick)
end
local function ensure()
 if started then return end
 started=true
 musicGroup=Instance.new("SoundGroup")
 musicGroup.Name,musicGroup.Volume="RTSMusic",groupVolume()
 musicGroup.Parent=SoundService
 ambienceGroup=Instance.new("SoundGroup")
 ambienceGroup.Name,ambienceGroup.Volume="RTSAmbience",0
 ambienceGroup.Parent=SoundService
 slots={makeSlot("RTSMusicA"),makeSlot("RTSMusicB")}
 for _,slot in ipairs(slots) do
  slot.sound.Ended:Connect(function()
   if slot==active and mood~="Silent" then playNext() end
  end)
 end
 for _,entry in ipairs(Rules.Ambience) do
  local sound=Instance.new("Sound")
  sound.Name="RTSAmbience"
  sound.SoundId=Rules.AssetId(entry.id)
  sound.Looped=true
  sound.Volume=entry.volume
  sound.SoundGroup=ambienceGroup
  sound.Parent=SoundService
  table.insert(ambience,sound)
 end
end
local function applyAmbience()
 if not ambienceGroup then return end
 local target=ambienceOn and AMBIENCE_MIX*soundVolume or 0
 for _,sound in ipairs(ambience) do
  if target>0 and not sound.IsPlaying then sound:Play() end
 end
 local tween=TweenService:Create(ambienceGroup,TweenInfo.new(2),{Volume=target})
 tween:Play()
 if target==0 then
  tween.Completed:Once(function(status)
   if status==Enum.TweenStatus.Completed and not ambienceOn then for _,sound in ipairs(ambience) do sound:Stop() end end
  end)
 end
end
-- Lobby, Peace, Battle, or Silent. Re-requesting the current mood is a no-op.
function Music:SetMood(value)
 if not RunService:IsClient() or not (value=="Silent" or playlistFor(value)) then return end
 ensure()
 if value==mood then return end
 mood=value
 revision+=1
 if value=="Silent" or not enabled then
  if active then active.token+=1; fade(active,0,CROSSFADE,true); active=nil end
  trackName=nil
  return
 end
 playNext()
end
function Music:SetAmbience(on)
 ensure()
 ambienceOn=on==true
 applyAmbience()
end
function Music:SetEnabled(value)
 if type(value)~="boolean" or value==enabled then return end
 ensure()
 enabled=value
 applyGroup(.6)
 if not enabled then
  revision+=1
  if active then active.token+=1; fade(active,0,.6,true); active=nil end
  trackName=nil
 elseif mood~="Silent" then playNext() end
end
function Music:SetVolume(value)
 ensure()
 musicVolume=Rules.VolumeSetting(value)
 applyGroup(.25)
end
function Music:SetSoundVolume(value)
 soundVolume=Rules.VolumeSetting(value)
 applyAmbience()
end
-- Stingers (age up, victory) briefly sit above the soundtrack, as in AOE.
function Music:Duck(duration)
 if type(duration)~="number" or duration~=duration or duration<=0 then return end
 ensure()
 duckUntil=math.max(duckUntil,os.clock()+math.min(duration,12))
 if not ducked then ducked=true; applyGroup(.35) end
 local deadline=duckUntil
 task.delay(math.min(duration,12),function()
  if duckUntil==deadline and ducked then ducked=false; applyGroup(1.5) end
 end)
end
function Music:GetStats()
 local failures=0
 for _ in pairs(failed) do failures+=1 end
 return {mood=mood,enabled=enabled,volume=musicVolume,track=trackName,
  playing=active~=nil and active.sound.IsPlaying,loaded=active~=nil and active.sound.IsLoaded,
  failedTracks=failures,ducked=ducked,ambience=ambienceOn,
  groupVolume=musicGroup and musicGroup.Volume or 0}
end
function Music:Destroy()
 revision+=1
 for _,slot in ipairs(slots) do slot.sound:Destroy() end
 for _,sound in ipairs(ambience) do sound:Destroy() end
 if musicGroup then musicGroup:Destroy() end
 if ambienceGroup then ambienceGroup:Destroy() end
 slots,ambience,active,started,mood={}, {}, nil,false,"Silent"
end
return Music
