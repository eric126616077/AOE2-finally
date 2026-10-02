-- Client-only cosmetic audio. Commands, resources and damage never depend on it.
local RunService=game:GetService("RunService")
local SoundService=game:GetService("SoundService")
local TweenService=game:GetService("TweenService")
local ContentProvider=game:GetService("ContentProvider")
local Rules=require(script.Parent.FeedbackRules)
local Config=require(script.Parent.Parent.GameData.GameConfig)
local Audio={}
local state=Rules.new()
local voices={}
local generation=0
local played=0
local fallbackPlays=0
local preloadStarted,preloadFinished,preloadError=false,false,false
local assets,loadedAssets,failedAssets={},{},{}
local interfaceGroup,worldGroup
local duckRevision=0
local worldTween
local unavailable=0
local volumeScale=1
local rotation={}
local orderIntent,orderIntentTime=nil,-math.huge
local WORLD_MIX=.85
local function groups()
 if interfaceGroup then return end
 interfaceGroup=Instance.new("SoundGroup")
 interfaceGroup.Name,interfaceGroup.Volume="RTSInterfaceAudio",volumeScale
 interfaceGroup.Parent=SoundService
 worldGroup=Instance.new("SoundGroup")
 worldGroup.Name,worldGroup.Volume="RTSWorldAudio",WORLD_MIX*volumeScale
 worldGroup.Parent=SoundService
end
local function duckWorld(cue)
 groups()
 duckRevision+=1
 local revision=duckRevision
 -- Orders and completion cues remain intelligible in a busy economy. A single
 -- bounded group tween avoids rewriting every playing worker's Sound volume.
 if worldTween then worldTween:Cancel() end
 local important=Rules.Cues[cue].priority==true
 worldTween=TweenService:Create(worldGroup,TweenInfo.new(.035),{Volume=(important and .32 or .52)*volumeScale})
 worldTween:Play()
 task.delay(important and .45 or .22,function()
  if revision==duckRevision and worldGroup.Parent then
   worldTween=TweenService:Create(worldGroup,TweenInfo.new(.12),{Volume=WORLD_MIX*volumeScale})
   worldTween:Play()
  end
 end)
end
do
 local known={}
 local function add(id)
  if not known[id] then known[id]=true; table.insert(assets,id) end
 end
 for _,data in pairs(Rules.Cues) do
  for _,variant in ipairs(data.variants) do add(Rules.AssetId(variant.id)) end
  add(Rules.FallbackId(data))
 end
end
local function emitterPart(source)
 if typeof(source)~="Instance" or not source:IsDescendantOf(workspace) then return nil end
 if source:IsA("BasePart") then return source end
 if source:IsA("Model") then
  local primary=source.PrimaryPart
  if primary and primary:IsDescendantOf(source) then return primary end
  return source:FindFirstChildWhichIsA("BasePart",true)
 end
 return nil
end
local function release(voice)
 if voice.closed then return end
 voice.closed=true
 voices[voice]=nil
 for _,connection in ipairs(voice.connections) do connection:Disconnect() end
 if voice.generation==generation then Rules.Release(state,voice.world) end
 voice.sound:Destroy()
 if voice.attachment then voice.attachment:Destroy() end
end
-- Selections answer with the selected kind's identity sound; accepted orders
-- with the intent the player just issued (the server still confirms success).
local function resolveCue(cue,source)
 if cue=="Select" and typeof(source)=="Instance" then
  local unit=Config.Units[source:GetAttribute("UnitType")]
  return Rules.SelectCue(unit and unit.class,source:GetAttribute("BuildingType"),source:GetAttribute("ResourceType"))
 elseif cue=="Order" and os.clock()-orderIntentTime<=Rules.OrderIntentLifetime then
  return Rules.OrderCue(orderIntent)
 end
 return cue
end
function Audio:SetOrderIntent(intent)
 if intent~="attack" and intent~="military" and intent~="gather" and intent~="move" then return end
 orderIntent,orderIntentTime=intent,os.clock()
end
-- `source` is a world Instance, or a Vector3 for something that no longer exists
-- (a collapsed building or a fallen unit).
function Audio:Play(cue, source)
 if not RunService:IsClient() then return false end
 cue=type(cue)=="string" and resolveCue(cue,source) or cue
 local data=type(cue)=="string" and Rules.Cues[cue]
 if not data then return false end
 rotation[cue]=(rotation[cue] or 0)+1
 local variant=Rules.Variant(data,rotation[cue])
 local assetId,start,duration,variantVolume=Rules.AssetId(variant.id),variant.start,data.duration,variant.volume
 -- A licensed asset can be unavailable (offline Studio, moderation). Use the
 -- bundled placeholder instead of silence; skip only when both are unusable.
 if preloadFinished and failedAssets[assetId] then
  assetId,start,variantVolume=Rules.FallbackId(data),0,math.min(.3,data.volume*.6)
  if not data.stinger then duration=math.min(duration,.6) end
  if failedAssets[assetId] then unavailable+=1; return false end
  fallbackPlays+=1
 end
 local part,position
 local gain=1
 if data.world then
  -- The RTS has no character. Gate and attenuate from the active RTS camera.
  if typeof(source)=="Vector3" then position=source else part=emitterPart(source); position=part and part.Position end
  local camera=workspace.CurrentCamera
  if not position or not camera then return false end
  local point,visible=camera:WorldToViewportPoint(position)
  local distance=(camera.CFrame.Position-position).Magnitude
  if not Rules.WorldAudible(visible,point.Z,distance) then return false end
  gain=Rules.CameraGain(distance)
 end
 local now=os.clock()
 -- A vanished emitter has no identity to throttle against; give it its own key.
 local key=typeof(source)=="Vector3" and {} or source
 local reserved,reason=Rules.Reserve(state,cue,now,key)
 if not reserved and reason=="capacity" and data.priority==true then
  local oldest
  for voice in pairs(voices) do if voice.world and (not oldest or voice.created<oldest.created) then oldest=voice end end
  if oldest then
   release(oldest)
   reserved=Rules.Reserve(state,cue,now,key)
  end
 end
 if not reserved then return false end
 groups()
 local sound=Instance.new("Sound")
 sound.Name="RTS_"..cue
 sound.SoundId=assetId
 local speed=data.speed
 local volume=variantVolume*gain
 if data.world then speed*=1+(played%5-2)*.015 end
 sound.Volume,sound.PlaybackSpeed=0,speed
 sound.SoundGroup=data.world and worldGroup or interfaceGroup
 sound.Looped=false
 sound.TimePosition=start
 local voice={sound=sound,world=data.world==true,generation=generation,connections={},closed=false,created=os.clock()}
 voices[voice]=true
 if position then
  local attachment=Instance.new("Attachment")
  attachment.Name="RTSAudioEmitter"
  if part then attachment.Parent=part
  else attachment.WorldPosition=position; attachment.Parent=workspace.Terrain end
  voice.attachment=attachment
  sound.RollOffMode=Enum.RollOffMode.Linear
  sound.RollOffMinDistance,sound.RollOffMaxDistance=120,Rules.MaxDistance
  sound.Parent=attachment
  table.insert(voice.connections,attachment.Destroying:Connect(function() release(voice) end))
 else sound.Parent=SoundService end
 table.insert(voice.connections,sound.Ended:Connect(function() release(voice) end))
 table.insert(voice.connections,sound.Stopped:Connect(function() release(voice) end))
 sound:Play()
 TweenService:Create(sound,TweenInfo.new(.012),{Volume=volume}):Play()
 if not data.world then duckWorld(cue) end
 if data.stinger and self.OnStinger then task.spawn(self.OnStinger,duration) end
 played+=1
 -- Cut stock samples into short cues; fade their tails to avoid a hard cut.
 -- The fallback expiry also bounds voices when an asset never loads or ends.
 local fade=data.stinger and .6 or .06
 local length=duration/speed
 task.delay(math.max(0.02,length-fade),function()
  if not voice.closed then TweenService:Create(sound,TweenInfo.new(fade),{Volume=0}):Play() end
 end)
 task.delay(length,function() release(voice) end)
 return true
end
function Audio:StopAll()
 generation+=1
 duckRevision+=1
 if worldTween then worldTween:Cancel(); worldTween=nil end
 if worldGroup then worldGroup.Volume=WORLD_MIX*volumeScale end
 for voice in pairs(voices) do release(voice) end
 Rules.Reset(state)
end
function Audio:SetEnabled(enabled)
 if type(enabled)~="boolean" then return end
 state.enabled=enabled
 if not enabled then self:StopAll() end
end
function Audio:SetVolume(value)
 volumeScale=Rules.VolumeSetting(value)
 if interfaceGroup then
  if worldTween then worldTween:Cancel(); worldTween=nil end
  interfaceGroup.Volume=volumeScale
  worldGroup.Volume=WORLD_MIX*volumeScale
 end
end
function Audio:IsAssetUsable(id)
 return not (preloadFinished and failedAssets[id])
end
function Audio:GetStats()
 local loaded,failed=0,0
 for _ in pairs(loadedAssets) do loaded+=1 end
 for _ in pairs(failedAssets) do failed+=1 end
 return {enabled=state.enabled,active=state.total,world=state.world,played=played,
  maxVoices=Rules.MaxVoices,maxWorldVoices=Rules.MaxWorldVoices,
  preloadFinished=preloadFinished,preloadError=preloadError,
  assetCount=#assets,loadedAssets=loaded,failedAssets=failed,skippedUnavailable=unavailable,
  fallbackPlays=fallbackPlays,volume=volumeScale,
  worldMixVolume=worldGroup and worldGroup.Volume or WORLD_MIX*volumeScale}
end
function Audio:Preload()
 if preloadStarted or not RunService:IsClient() then return end
 preloadStarted=true
 -- Cosmetic loading runs alongside UI startup and never waits for a character.
 task.spawn(function()
  -- String content IDs are inferred as images by PreloadAsync. Give it Sound
  -- instances so audio files are fetched with the correct asset type.
  local folder=Instance.new("Folder")
  folder.Name="RTSAudioPreload"
  folder.Parent=SoundService
  local sounds={}
  for _,id in ipairs(assets) do
   local sound=Instance.new("Sound")
   sound.SoundId,sound.Volume=id,0
   sound.Parent=folder
   table.insert(sounds,sound)
  end
  local ok=pcall(function()
   ContentProvider:PreloadAsync(sounds,function(id,status)
    if table.find(assets,id) then
     if status==Enum.AssetFetchStatus.Success then loadedAssets[id]=true
     else failedAssets[id]=true end
    end
   end)
  end)
  -- IsLoaded also confirms the actual audio decoder accepted each file.
  for _,sound in ipairs(sounds) do
   local id=sound.SoundId
   if sound.IsLoaded then loadedAssets[id]=true; failedAssets[id]=nil
   else loadedAssets[id]=nil; failedAssets[id]=true end
  end
  folder:Destroy()
  preloadError=not ok
  preloadFinished=true
  local failed={}
  for id in pairs(failedAssets) do table.insert(failed,id) end
  if #failed>0 then warn("[RTS] 部分音效素材無法載入，改用 Studio 內建替代音："..table.concat(failed,", ")) end
 end)
end
return Audio
