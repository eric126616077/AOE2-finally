-- Pure cosmetic playback limits, shared by the audio client and CLI tests.
local Rules = {}
Rules.MaxVoices = 8
Rules.MaxWorldVoices = 5 -- Leave room for a command or error while workers are busy.
Rules.GlobalInterval = 0.035
Rules.WorldInterval = 0.09
Rules.MaxDistance = 460

-- Roblox-licensed Creator Store audio (ProSoundEffects SFX and APM Music, which
-- Roblox licenses for use in any experience). Each variant names its asset, the
-- TimePosition where the useful hit starts, and a volume matched from the
-- measured short-term loudness of that excerpt. `fallback` is a Studio-bundled
-- rbxasset sound, used only when the licensed asset fails to load.
Rules.Cues = {
 Click={variants={{id=9120918417,start=0.2,volume=0.243}}, volume=0.243, speed=1.35, duration=0.16, interval=0.05, fallback="volume_slider.ogg"},
 Select={variants={{id=9116254990,start=0.3,volume=0.707}}, volume=0.707, speed=1.0, duration=0.45, interval=0.09, fallback="volume_slider.ogg"},
 SelectSword={variants={{id=9119742750,start=0,volume=0.384},{id=9119743392,start=0,volume=0.409}}, volume=0.397, speed=1.0, duration=0.38, interval=0.09, fallback="volume_slider.ogg"},
 SelectBow={variants={{id=9125405163,start=0.06,volume=0.569},{id=9125407239,start=0.08,volume=0.646}}, volume=0.608, speed=1.05, duration=0.6, interval=0.09, fallback="volume_slider.ogg"},
 SelectHooves={variants={{id=9120987618,start=0.1,volume=1.289}}, volume=1.289, speed=1.1, duration=0.75, interval=0.09, fallback="action_footsteps_plastic.mp3"},
 SelectSiege={variants={{id=9120839010,start=0.15,volume=1.675}}, volume=1.675, speed=1.0, duration=0.8, interval=0.09, fallback="volume_slider.ogg"},
 SelectBell={variants={{id=9113804401,start=0,volume=0.552}}, volume=0.552, speed=1.0, duration=1.1, interval=0.09, fallback="volume_slider.ogg"},
 SelectAnvil={variants={{id=9113133597,start=0,volume=0.227},{id=9125362690,start=0,volume=0.312}}, volume=0.269, speed=1.0, duration=0.35, interval=0.09, fallback="volume_slider.ogg"},
 SelectCoins={variants={{id=9125444889,start=0,volume=0.250}}, volume=0.250, speed=1.0, duration=0.4, interval=0.09, fallback="volume_slider.ogg"},
 SelectChop={variants={{id=9120808574,start=0,volume=0.285},{id=9120807255,start=0,volume=0.303}}, volume=0.294, speed=1.0, duration=0.35, interval=0.09, fallback="action_jump_land.mp3"},
 SelectChisel={variants={{id=9119596406,start=0,volume=0.156}}, volume=0.156, speed=1.0, duration=0.25, interval=0.09, fallback="volume_slider.ogg"},
 SelectDoor={variants={{id=9120918417,start=0.2,volume=0.344}}, volume=0.344, speed=1.0, duration=0.42, interval=0.09, fallback="volume_slider.ogg"},
 SelectStone={variants={{id=9118612665,start=0.08,volume=0.061}}, volume=0.061, speed=1.0, duration=0.45, interval=0.09, fallback="action_jump_land.mp3"},
 SelectHorn={variants={{id=9114823494,start=0.42,volume=0.536}}, volume=0.536, speed=1.0, duration=1.3, interval=0.09, fallback="volume_slider.ogg"},
 SelectPages={variants={{id=9113550272,start=1.92,volume=2.414}}, volume=2.414, speed=1.0, duration=0.5, interval=0.09, fallback="volume_slider.ogg"},
 SelectFoliage={variants={{id=9114518245,start=0.14,volume=0.315}}, volume=0.315, speed=1.0, duration=0.45, interval=0.09, fallback="action_footsteps_plastic.mp3"},
 SelectHammer={variants={{id=9114753510,start=0.84,volume=0.121}}, volume=0.121, speed=1.0, duration=0.45, interval=0.09, fallback="action_jump_land.mp3"},
 Order={variants={{id=9113731508,start=0,volume=0.562}}, volume=0.562, speed=1.0, duration=0.25, interval=0.12, fallback="action_get_up.mp3"},
 OrderMilitary={variants={{id=9113156860,start=0.32,volume=0.649}}, volume=0.649, speed=1.0, duration=0.35, interval=0.12, fallback="action_get_up.mp3"},
 OrderAttack={variants={{id=9119742466,start=0.03,volume=1.637}}, volume=1.637, speed=1.0, duration=0.42, interval=0.12, fallback="action_get_up.mp3"},
 OrderGather={variants={{id=9114083746,start=0.26,volume=0.498}}, volume=0.498, speed=1.0, duration=0.2, interval=0.12, fallback="action_get_up.mp3"},
 Error={variants={{id=9126267420,start=0,volume=0.634}}, volume=0.634, speed=0.9, duration=0.34, interval=0.35, priority=true, fallback="volume_slider.ogg"},
 Build={variants={{id=9114753510,start=0.24,volume=0.255}}, volume=0.255, speed=1.0, duration=0.5, interval=0.18, priority=true, fallback="action_jump_land.mp3"},
 ConstructionComplete={variants={{id=9113584010,start=0.03,volume=0.258}}, volume=0.258, speed=0.92, duration=1.25, interval=0.45, priority=true, fallback="action_jump.mp3"},
 Train={variants={{id=9113421646,start=0,volume=0.834}}, volume=0.834, speed=0.85, duration=0.6, interval=0.4, priority=true, fallback="action_get_up.mp3"},
 Research={variants={{id=9113804436,start=0.06,volume=1.414}}, volume=1.414, speed=1.0, duration=1.2, interval=0.5, priority=true, fallback="volume_slider.ogg"},
 Age={variants={{id=9045868304,start=0,volume=0.376}}, volume=0.376, speed=1.0, duration=7.6, interval=1, priority=true, stinger=true, fallback="action_jump.mp3"},
 MatchStart={variants={{id=9045868459,start=0,volume=0.372}}, volume=0.372, speed=1.0, duration=6.0, interval=1, priority=true, stinger=true, fallback="action_jump.mp3"},
 Victory={variants={{id=1836473422,start=0.2,volume=0.368}}, volume=0.368, speed=1.0, duration=4.6, interval=1, priority=true, stinger=true, fallback="action_jump.mp3"},
 Defeat={variants={{id=1836392645,start=0.38,volume=0.260}}, volume=0.260, speed=1.0, duration=6.0, interval=1, priority=true, stinger=true, fallback="volume_slider.ogg"},
 MatchEnd={variants={{id=9045868459,start=0,volume=0.296}}, volume=0.296, speed=1.0, duration=6.0, interval=1, stinger=true, fallback="volume_slider.ogg"},
 UnderAttack={variants={{id=9114820307,start=0.28,volume=0.439}}, volume=0.439, speed=1.0, duration=2.2, interval=1.5, priority=true, fallback="impact_explosion_03.mp3"},
 GatherFood={variants={{id=9114518245,start=0.15,volume=0.313},{id=9114083746,start=0.26,volume=0.352}}, volume=0.333, speed=1.0, duration=0.24, interval=0.18, sourceInterval=0.85, world=true, fallback="action_footsteps_plastic.mp3"},
 GatherWood={variants={{id=9120808574,start=0,volume=0.452},{id=9120807255,start=0,volume=0.481},{id=9120808946,start=0,volume=0.401},{id=9120811299,start=0,volume=0.507}}, volume=0.460, speed=1.0, duration=0.32, interval=0.16, sourceInterval=0.65, world=true, fallback="action_jump_land.mp3"},
 GatherGold={variants={{id=9119596406,start=0,volume=0.175},{id=9125362690,start=0,volume=0.350}}, volume=0.262, speed=1.0, duration=0.2, interval=0.18, sourceInterval=0.75, world=true, fallback="volume_slider.ogg"},
 GatherStone={variants={{id=9118579978,start=0.2,volume=0.220},{id=9119603662,start=0,volume=0.480}}, volume=0.350, speed=1.0, duration=0.16, interval=0.18, sourceInterval=0.75, world=true, fallback="action_jump_land.mp3"},
 BuildWork={variants={{id=9114756156,start=0.27,volume=0.527},{id=9114756337,start=0.31,volume=0.435}}, volume=0.481, speed=1.0, duration=0.17, interval=0.18, sourceInterval=0.8, world=true, fallback="action_jump_land.mp3"},
 Repair={variants={{id=9114756004,start=0.23,volume=0.371}}, volume=0.371, speed=1.12, duration=0.17, interval=0.18, sourceInterval=0.8, world=true, fallback="volume_slider.ogg"},
 Delivery={variants={{id=9113731508,start=0,volume=0.398}}, volume=0.398, speed=0.95, duration=0.22, interval=0.24, sourceInterval=1, world=true, fallback="action_get_up.mp3"},
 DeliveryWood={variants={{id=9120871244,start=0.28,volume=0.084}}, volume=0.084, speed=1.0, duration=0.3, interval=0.24, sourceInterval=1, world=true, fallback="action_get_up.mp3"},
 DeliveryGold={variants={{id=9125444889,start=0,volume=0.223}}, volume=0.223, speed=1.0, duration=0.32, interval=0.24, sourceInterval=1, world=true, fallback="action_get_up.mp3"},
 DeliveryStone={variants={{id=9118587701,start=0.25,volume=0.323}}, volume=0.323, speed=1.0, duration=0.35, interval=0.24, sourceInterval=1, world=true, fallback="action_get_up.mp3"},
 Melee={variants={{id=9119746751,start=0,volume=0.166},{id=9119072660,start=0,volume=0.113},{id=9119747138,start=0.05,volume=0.231}}, volume=0.170, speed=1.0, duration=0.3, interval=0.12, sourceInterval=0.5, world=true, fallback="action_jump_land.mp3"},
 Ranged={variants={{id=9113166206,start=0.88,volume=0.882}}, volume=0.882, speed=1.15, duration=0.4, interval=0.12, sourceInterval=0.6, world=true, fallback="action_jump.mp3"},
 Siege={variants={{id=17283613561,start=0,volume=0.179}}, volume=0.179, speed=1.0, duration=0.9, interval=0.3, sourceInterval=1, world=true, fallback="impact_explosion_03.mp3"},
 Ram={variants={{id=9120885468,start=0,volume=0.292}}, volume=0.292, speed=0.9, duration=0.34, interval=0.3, sourceInterval=1, world=true, fallback="impact_explosion_03.mp3"},
 UnitDeath={variants={{id=9113480915,start=0.06,volume=0.244},{id=9113477342,start=0.18,volume=0.232}}, volume=0.238, speed=1.0, duration=0.42, interval=0.15, sourceInterval=0.5, world=true, fallback="action_jump_land.mp3"},
 BuildingDestroyed={variants={{id=9120828793,start=0.15,volume=0.193}}, volume=0.193, speed=1.0, duration=1.6, interval=0.4, sourceInterval=1, world=true, priority=true, fallback="impact_explosion_03.mp3"},
}
-- Soundtrack from the same licensed library. Volumes match the measured RMS
-- loudness of each track, so playlist changes stay level.
Rules.Music = {
 Lobby={
  {id=1838166075,name="Royal Court 2",volume=0.575,length=112.78},
  {id=1847223700,name="Prelude For 2 Lutes",volume=0.776,length=76.42},
  {id=1840391643,name="Royal Court",volume=1.122,length=104.61},
 },
 Peace={
  {id=1846123957,name="Saltarello (Italy ca.1400)",volume=0.741,length=178.1},
  {id=1846009879,name="Galliard For A Queen",volume=0.457,length=89.2},
  {id=1847224039,name="Pavane For Crumhorn And Drum",volume=0.794,length=84.51},
  {id=9048663710,name="Court Minstrel",volume=0.417,length=114.97},
  {id=1836394191,name="The Gay Galliard",volume=0.55,length=54.85},
  {id=1843273614,name="Troubadour",volume=0.422,length=128.13},
  {id=1843052494,name="Branle",volume=0.422,length=112.12},
  {id=1846301991,name="Minstrel Medley",volume=0.617,length=102.47},
  {id=1835241859,name="Travelling Troubadour",volume=0.359,length=128.33},
  {id=1840245435,name="Galliard",volume=0.631,length=96.92},
  {id=1839906422,name="Medieval Castle",volume=0.316,length=90.11},
 },
 Battle={
  {id=1846664364,name="Siege And Conquest",volume=0.254,length=144.39},
  {id=1846662404,name="Strength And Honor",volume=0.288,length=178.87},
  {id=1838617399,name="Drums Of War",volume=0.245,length=102.27},
  {id=91600780422428,name="Clash of Swords",volume=0.398,length=138.34},
  {id=1840866101,name="Battleground",volume=0.38,length=116.67},
  {id=1843083411,name="March To War",volume=0.248,length=100.61},
 },
}
Rules.Ambience = {
 {id=9112748214,name="Birds Exterior Ambience",volume=0.53},
 {id=9116258071,name="Leaves Rustle Wind",volume=1.2},
}
-- Combat must be sustained before the soundtrack turns martial, and it calms
-- down only after a quiet spell, so single arrows never flip playlists.
Rules.BattleEvents = 3
Rules.BattleWindow = 12
Rules.BattleCooldown = 28
Rules.AlertCooldown = 18
Rules.AlertMinimumGap = 5
Rules.AlertRadius = 90
Rules.OrderIntentLifetime = 1.5

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Rules.AssetId(id)
 return "rbxassetid://"..tostring(id)
end
function Rules.FallbackId(data)
 return "rbxasset://sounds/"..data.fallback
end
-- Rotating variants keeps repeated chops and clashes from sounding mechanical.
function Rules.Variant(data, index)
 local variants=data.variants
 if not finite(index) then index=1 end
 return variants[(math.floor(index)-1)%#variants+1]
end
local unitSelect={villager="Select",infantry="SelectSword",archer="SelectBow",cavalry="SelectHooves",siege="SelectSiege",monk="SelectBell"}
local buildingSelect={
 TownCenter="SelectBell",House="SelectDoor",Barracks="SelectSword",ArcheryRange="SelectBow",Stable="SelectHooves",
 SiegeWorkshop="SelectHammer",Blacksmith="SelectAnvil",Market="SelectCoins",LumberCamp="SelectChop",
 MiningCamp="SelectChisel",Mill="SelectFoliage",Farm="SelectFoliage",Monastery="SelectBell",University="SelectPages",
 Tower="SelectStone",Wall="SelectStone",Gate="SelectStone",Castle="SelectHorn",Wonder="SelectHorn",
}
local resourceSelect={Tree="SelectChop",Gold="SelectChisel",Stone="SelectChisel",Berries="SelectFoliage"}
-- AOE-style identity sounds: every selectable kind answers with its own sound.
function Rules.SelectCue(unitClass, buildingType, resourceType)
 return unitSelect[unitClass] or buildingSelect[buildingType] or resourceSelect[resourceType] or "Select"
end
function Rules.OrderCue(intent)
 return intent=="attack" and "OrderAttack" or intent=="military" and "OrderMilitary" or intent=="gather" and "OrderGather" or "Order"
end
function Rules.DeliveryCue(carryType)
 return carryType=="wood" and "DeliveryWood" or carryType=="gold" and "DeliveryGold" or carryType=="stone" and "DeliveryStone" or "Delivery"
end
function Rules.AttackCue(unitType, data)
 if type(data)~="table" then return nil end
 if unitType=="ram" then return "Ram" end
 if data.class=="siege" then return "Siege" end
 return type(data.range)=="number" and data.range>20 and "Ranged" or "Melee"
end
function Rules.IsNewPulse(value, previous)
 return finite(value) and value>0 and (previous==nil or (finite(previous) and value>previous))
end
function Rules.WorldAudible(visible, depth, distance)
 return visible==true and finite(depth) and depth>0 and finite(distance) and distance>=0 and distance<=Rules.MaxDistance
end
function Rules.CameraGain(distance)
 if not finite(distance) or distance<0 or distance>Rules.MaxDistance then return 0 end
 -- No avatar listener exists in RTS play. Nearby work remains intelligible from
 -- the overhead camera while distant crowds blend quietly into the background.
 return math.clamp(1-(distance-100)/(Rules.MaxDistance-100),.12,1)
end
-- Settings are replicated player attributes; anything malformed means full volume.
function Rules.VolumeSetting(value)
 if not finite(value) then return 1 end
 return math.clamp(value,0,1)
end
function Rules.new()
 return {enabled=true, total=0, world=0, last=-math.huge, lastWorld=-math.huge,lastWasWorld=false,
  cues={}, sources=setmetatable({}, {__mode="k"})}
end
function Rules.Reset(state)
 state.total, state.world = 0, 0
 state.last, state.lastWorld = -math.huge, -math.huge
 state.lastWasWorld=false
 table.clear(state.cues)
 table.clear(state.sources)
end
function Rules.Reserve(state, cue, now, source)
 local data=type(cue)=="string" and Rules.Cues[cue]
 if not data or not finite(now) or not state.enabled then return false end
 -- A just-arrived worker pulse must not swallow completion/error cues. Keep
 -- interface-to-interface throttling, each cue's cooldown, and all voice limits.
 local bypassWorld=data.priority==true and state.lastWasWorld==true and now>=state.last
 if now-state.last<Rules.GlobalInterval and not bypassWorld then return false end
 if now-(state.cues[cue] or -math.huge)<data.interval then return false end
 if data.world then
  if source==nil or now-state.lastWorld<Rules.WorldInterval then return false end
  local previous=state.sources[source]
  if previous and now-previous<(data.sourceInterval or 0.6) then return false end
 end
 -- Report capacity only after every other check succeeds. A priority caller
 -- may then replace one world voice without silencing it for a rejected cue.
 if state.total>=Rules.MaxVoices or (data.world and state.world>=Rules.MaxWorldVoices) then return false,"capacity" end
 state.total+=1
 state.last, state.cues[cue]=now, now
 state.lastWasWorld=data.world==true
 if data.world then
  state.world+=1
  state.lastWorld, state.sources[source]=now, now
 end
 return true
end
function Rules.Release(state, world)
 state.total=math.max(0,state.total-1)
 if world then state.world=math.max(0,state.world-1) end
end
-- Under-attack alerts: one horn per battlefield area, never a horn on every hit.
function Rules.newAlerts()
 return {last=-math.huge, spots={}}
end
function Rules.Alert(alerts, now, x, z)
 if not finite(now) or not finite(x) or not finite(z) then return false end
 local radius=Rules.AlertRadius*Rules.AlertRadius
 local kept,nearby={},false
 for _,spot in ipairs(alerts.spots) do
  if now-spot.time<Rules.AlertCooldown then
   table.insert(kept,spot)
   local dx,dz=spot.x-x,spot.z-z
   if dx*dx+dz*dz<=radius then
    -- Continued fighting refreshes its area, so a long battle stays one alert.
    spot.time=now; nearby=true
   end
  end
 end
 alerts.spots=kept
 if nearby or now-alerts.last<Rules.AlertMinimumGap then return false end
 alerts.last=now
 table.insert(alerts.spots,{x=x,z=z,time=now})
 return true
end
-- Soundtrack mood: Peace by default, Battle while combat stays dense.
function Rules.newMood()
 return {mood="Peace", events={}, lastCombat=-math.huge}
end
function Rules.ReportCombat(mood, now)
 if not finite(now) then return mood.mood end
 local kept={}
 for _,time in ipairs(mood.events) do if now-time<Rules.BattleWindow then table.insert(kept,time) end end
 table.insert(kept,now)
 mood.events,mood.lastCombat=kept,now
 if #kept>=Rules.BattleEvents then mood.mood="Battle" end
 return mood.mood
end
function Rules.UpdateMood(mood, now)
 if finite(now) and mood.mood=="Battle" and now-mood.lastCombat>=Rules.BattleCooldown then
  mood.mood="Peace"
  table.clear(mood.events)
 end
 return mood.mood
end
-- Shuffle without replaying the track that just finished.
function Rules.NextTrack(count, previous, roll)
 if type(count)~="number" or count<1 then return nil end
 if count==1 then return 1 end
 if not finite(roll) then roll=0 end
 local pick=math.floor(math.clamp(roll,0,0.999999)*(count-1))+1
 if previous and pick>=previous then pick+=1 end
 return pick
end
return Rules
