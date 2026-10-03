local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local Config = require(RS.GameData.GameConfig)
local Grid = require(RS.Shared.Grid)
local FormationRules = require(RS.Shared.FormationRules)
local Factory = require(script.Parent.ServerModules.ModelFactory)
local Economy = require(script.Parent.ServerModules.Economy)
local Rules = require(script.Parent.ServerModules.MatchRules)
local TeamRules = require(script.Parent.ServerModules.TeamRules)
local UnitRules = require(script.Parent.ServerModules.UnitRules)
local UnitCollisionRules = require(script.Parent.ServerModules.UnitCollisionRules)
local CombatRules = require(script.Parent.ServerModules.CombatRules)
local MeleeRules = require(script.Parent.ServerModules.MeleeRules)
local ApproachRules = require(script.Parent.ServerModules.ApproachRules)
local PathRules = require(script.Parent.ServerModules.PathRules)
local GatheringRules = require(script.Parent.ServerModules.GatheringRules)
local ConstructionRules = require(script.Parent.ServerModules.ConstructionRules)
local World = require(script.Parent.ServerModules.WorldGenerator)
local LobbyRules = require(script.Parent.ServerModules.LobbyRules)
local LobbyWorld = require(script.Parent.ServerModules.LobbyWorld)
local CivilizationRules = require(script.Parent.ServerModules.CivilizationRules)
local CivilizationPreferenceRules = require(script.Parent.ServerModules.CivilizationPreferenceRules)
local ProfileRules = require(script.Parent.ServerModules.ProfileRules)
local ProfileStore = require(script.Parent.ServerModules.ProfileStore)
local Telemetry = require(script.Parent.ServerModules.Telemetry)
local AIWorkerRules = require(script.Parent.ServerModules.AIWorkerRules)
local AutoWorkRules = require(script.Parent.ServerModules.AutoWorkRules)
local SpatialRules = require(script.Parent.ServerModules.SpatialRules)
local ProductionRules = require(script.Parent.ServerModules.ProductionRules)
local MatchReportRules = require(script.Parent.ServerModules.MatchReportRules)
local CommandRules = require(script.Parent.ServerModules.CommandRules)
local profiles=ProfileStore.new(Config)
local telemetry=Telemetry.new()
local currentMatch
local matchTeams
assert(CivilizationRules.audit(Config))
-- 商店規則只在啟動時稽核一次；不佔用主腳本的區域變數。
assert(require(script.Parent.ServerModules.CommerceRules).audit(Config))
Players.CharacterAutoLoads = false

local buildings,resources,units,factions,remotes,command,feedback
do
local function folder(parent, name)
 local item = parent:FindFirstChild(name)
 if item and item:IsA("Folder") then return item end
 item = Instance.new("Folder")
 item.Name, item.Parent = name, parent
 return item
end
local function remote(parent, name)
 local event = parent:FindFirstChild(name)
 if event and event:IsA("RemoteEvent") then return event end
 event = Instance.new("RemoteEvent")
 event.Name, event.Parent = name, parent
 return event
end
buildings = folder(workspace, "Buildings")
resources = folder(workspace, "Resources")
units = folder(workspace, "Units")
factions = folder(RS, "RTSFactions")
remotes = folder(RS, "RTSRemotes")
command, feedback = remote(remotes, "Command"), remote(remotes, "Feedback")
end
local states, byId, orders, training, construction, researching = {}, {}, {}, {}, {}, {}
local managedResources = {}
local actionClocks = {}
local reportSequence, reportSubjectSequence = 0, 0
local reportSubjects = setmetatable({}, {__mode="k"})
local colors = {Color3.fromRGB(80,151,224), Color3.fromRGB(209,83,75), Color3.fromRGB(218,177,70), Color3.fromRGB(136,101,190)}
local settings = {size="Medium", aiCount=1, difficulty="Normal", population=100, startingResources="Standard", victory="Conquest",teamMode="FFA"}
local phase, matchStart, matchGeneration, startingSides = "Lobby", 0, 0, 0
local joinSequence, pathTasks = 0, 0
local GRID_SIZE = Config.Map.GridSize
local TARGET_HALF_EXTENT=assert(SpatialRules.maxHalfFootprint(Config.Buildings,GRID_SIZE))
local COMBAT = Config.Combat
local MAX_UNIT_RADIUS=Config.UnitCollision.default.radius
for _,profile in pairs(Config.UnitCollision.profiles) do MAX_UNIT_RADIUS=math.max(MAX_UNIT_RADIUS,profile.radius) end
local unitCollisionIndex=assert(UnitCollisionRules.newIndex(16,MAX_UNIT_RADIUS))
-- 僧侶規則、設定與函式集中在一個表，避免超過 Studio 的 200 個區域變數上限。
local Monk={rules=require(script.Parent.ServerModules.MonkRules),config=Config.Monk,random=Random.new()}
-- 聖物與貿易車的規則、設定與函式（同樣集中在表內；主程式區塊已接近 200 個區域變數上限）。Relic.trade.home[貿易車]=出發市集。
local Relic={rules=require(script.Parent.ServerModules.RelicTradeRules),config=Config.Relics,accumulated=setmetatable({},{__mode="k"}),ground=setmetatable({},{__mode="k"}),
 trade={home=setmetatable({},{__mode="k"}),config=Config.Trade}}
local stop, issue, destroyModel, defeat, checkVictory, finishAttack, acquireTarget
-- 自動工作的每單位狀態（閒置起點、玩家保留待命、暫時略過的目標）與延後定義的函式。
local AutoWork={units=setmetatable({},{__mode="k"}),farmClaims=setmetatable({},{__mode="k"}),farmRules=require(script.Parent.ServerModules.FarmRules)}
-- 城牆與城門：已完工的城門（gates[model]={state,X,Z,halfX,halfZ,open}）不擋己方與同盟，敵方由伺服器逐段擋下。
local Walls={gates=setmetatable({},{__mode="k"}),rules=require(RS.Shared.WallRules),config=Config.Walls}
-- 農田一次只給一位村民：正在耕作、或交貨後會回來的村民保有該田；其餘村民改派其他食物來源。
AutoWork.isFarm=function(target)
 return typeof(target)=="Instance" and target.Parent==buildings and target:GetAttribute("BuildingType")=="Farm"
end
AutoWork.farmHolder=function(farm)
 local unit=AutoWork.farmClaims[farm]
 local order=unit and unit.Parent==units and orders[unit]
 if order and AutoWork.farmRules.holds(order.kind,order.target,order.returnTarget,farm) then return unit end
 AutoWork.farmClaims[farm]=nil
 return nil
end
AutoWork.farmFree=function(farm,unit)
 return AutoWork.farmRules.free(AutoWork.farmHolder(farm),unit)
end
AutoWork.claimFarm=function(farm,unit)
 if not AutoWork.isFarm(farm) or not AutoWork.farmFree(farm,unit) then return false end
 AutoWork.farmClaims[farm]=unit
 return true
end
-- 駐紮：進入建築的單位移除模型，只留下紀錄（兵種、生命、攜帶資源、信仰），離開時依紀錄重新生成。
-- inside[建築] = 紀錄陣列，另帶 arrows 欄位（每次射擊多出的箭數）。規則與函式集中在一個表。
local Garrison={rules=require(script.Parent.ServerModules.GarrisonRules),config=Config.Garrison,inside=setmetatable({},{__mode="k"})}
Garrison.count=function(state)
 local total=0
 for building in pairs(state.buildings) do
  local held=building.Parent==buildings and Garrison.inside[building]
  if held then total+=#held end
 end
 return total
end
Garrison.publish=function(model)
 local held=Garrison.inside[model]
 local data=Config.Buildings[model:GetAttribute("BuildingType")]
 if held then
  local classes={}
  for _,record in ipairs(held) do
   local class=Config.Units[record.kind].class
   classes[class]=(classes[class] or 0)+1
  end
  held.arrows=Garrison.rules.arrows(Garrison.config.arrows,classes,data and data.damage and data.garrison and data.garrison.maxArrows)
 end
 model:SetAttribute("GarrisonCapacity",Garrison.rules.capacity(data))
 model:SetAttribute("Garrison",held and #held or 0)
 model:SetAttribute("GarrisonArrows",held and held.arrows or 0)
end
-- 跨 place 對局：Combined＝單一伺服器（Studio／未設定 place）；Lobby 只集合並傳送；Match 只跑一場對局。
-- Studio 可在 ServerScriptService 設屬性 RTSPlaceRole="Match" 模擬對戰 place（以先進入的玩家組成名單）。
local Travel={rules=require(script.Parent.ServerModules.PlaceRules),places=Config.Places}
Travel.role=Travel.rules.role(Config.Places,game.PlaceId,RunService:IsStudio(),script.Parent:GetAttribute("RTSPlaceRole"))
Travel.service=require(script.Parent.ServerModules.MatchTravel).new(Config.Places,Travel.role)
local lobbyWorld = Travel.role=="Match" and LobbyWorld.Stub() or LobbyWorld.Create()
local rooms, activeRoomId = {}, nil
for _,portal in ipairs(Config.Lobby.portals) do
 local roomSettings,count=LobbyRules.settings(portal.settings)
 assert(roomSettings,count)
 rooms[portal.id]={id=portal.id,settings=roomSettings,expected=count,revision=0,configured=false,hadMembers=false}
end
local queueJoin, queueLeave, spawnLobby, startMatch, autoStartLobby

local function actorName(actor)
 return actor:IsA("Player") and actor.DisplayName or actor:GetAttribute("DisplayName") or actor.Name
end
local function teamName(team)
 if not team then return nil end
 if settings.teamMode=="CoopAI" then
  local chapter=LobbyRules.story(settings)
  return team==1 and "玩家聯軍" or (chapter and chapter.enemy or "電腦聯軍")
 end
 return "第 "..team.." 隊"
end
local function publishTeam(state,instance)
 local team=TeamRules.team(matchTeams,state.id)
 instance:SetAttribute("TeamId",team)
 instance:SetAttribute("TeamName",teamName(team))
end
local function plannedAIIds(count)
 local result,used={},{}
 for index=1,count do
  local id=-10000-index
  while byId[id] or used[id] do id-=100 end
  result[index],used[id]=id,true
 end
 return result
end
local function publishCivilization(state,instance)
 local id,data=CivilizationRules.resolve(Config,state.civilization)
 instance:SetAttribute("Civilization",id)
 instance:SetAttribute("CivilizationName",data.name)
 instance:SetAttribute("CivilizationEmblem",data.emblem)
 instance:SetAttribute("CivilizationAccent",data.accent)
end
local function civilizationMark(state,model,height)
 if not model.PrimaryPart then return end
 local _,data=CivilizationRules.resolve(Config,state.civilization)
 local mark=Instance.new("BillboardGui")
 mark.Name="CivilizationMark"
 mark.Adornee=model.PrimaryPart
 mark.Size=UDim2.fromOffset(38,38)
 mark.StudsOffset=Vector3.new(0,height/2+4,0)
 mark.MaxDistance=450
 mark.AlwaysOnTop=false
 local emblem=Instance.new("TextLabel")
 emblem.Size=UDim2.fromScale(1,1)
 emblem.BackgroundTransparency=1
 emblem.Text=data.emblem
 emblem.TextColor3=data.accent
 emblem.TextStrokeColor3=Color3.fromRGB(24,30,30)
 emblem.TextStrokeTransparency=0.15
 emblem.TextScaled=true
 emblem.Font=Enum.Font.GothamBold
 emblem.Parent=mark
 mark.Parent=model.PrimaryPart
end
local function notify(actor, message, cue)
 if actor and actor:IsA("Player") and actor.Parent == Players then feedback:FireClient(actor, message, cue) end
end
local function announce(message,cue)
 for _, player in ipairs(Players:GetPlayers()) do notify(player, message,cue) end
end
local function matchContext(state)
 return {mode=currentMatch and currentMatch.mode or "Lobby",civilization=state.civilization,size=settings.size}
end
local function recordMatchResult(state,outcome)
 if outcome~="win" and outcome~="loss" then return end -- A draw has no win/loss delta.
 if not currentMatch or not currentMatch.eligible or not TeamRules.isParticipant(matchTeams,currentMatch.participants,state)
  or currentMatch.results[state.id] then return end
 currentMatch.results[state.id]=outcome
 profiles:RecordResult(state.actor,currentMatch.id,outcome,DateTime.now().UnixTimestampMillis)
end
-- Only successful server facts enter this session report; balance changes alone
-- cannot distinguish delivery, trade proceeds, refunds, or initial free assets.
local function recordReport(state,kind,facts)
 if not state or not state.report then return nil end
 reportSequence+=1
 if MatchReportRules.Record(state.report,reportSequence,kind,facts) then return reportSequence end
 return nil
end
local function reportSubject(model)
 local id=reportSubjects[model]
 if not id then
  reportSubjectSequence+=1
  id=reportSubjectSequence
  reportSubjects[model]=id
 end
 return id
end
local function clearReport(state)
 state.report=nil
 state.actor:SetAttribute("MatchReportJSON",nil)
end
local function publishReport(state)
 if not state.report then return end
 if state.actor:IsA("Player") and state.actor.Parent==Players then
  local snapshot=MatchReportRules.Snapshot(state.report)
  local ok,encoded=pcall(HttpService.JSONEncode,HttpService,snapshot)
  if ok then state.actor:SetAttribute("MatchReportJSON",encoded)
  else warn("[RTS] 對局覆盤編碼失敗："..tostring(encoded)) end
 end
end
local function freezeReport(state,now)
 if state.report and MatchReportRules.FreezeActivity(state.report,now) then publishReport(state) end
end
local function finishReport(state,outcome,now)
 if state.report and MatchReportRules.Finish(state.report,now,outcome) then publishReport(state) end
end
local function setPhase(value)
 phase = value
 workspace:SetAttribute("MatchPhase", value)
 workspace:SetAttribute("MatchEnded", value == "Ended")
end
local function position(model)
 local p = model:GetPivot().Position
 return Vector3.new(p.X, Config.Map.GroundY, p.Z)
end
local function validPosition(pos)
 local half = (workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2-3
 return typeof(pos)=="Vector3" and Rules.finite(pos.X) and Rules.finite(pos.Y) and Rules.finite(pos.Z)
  and math.abs(pos.X)<=half and math.abs(pos.Z)<=half and math.abs(pos.Y)<=1000
end
local function alive(state)
 return state and state.playing and not state.defeated and state.actor.Parent~=nil
end
local function owner(model)
 return byId[model:GetAttribute("OwnerId")]
end
local function isOwned(state, model, parent)
 return typeof(model)=="Instance" and model:IsA("Model") and model.Parent==parent
  and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==state.id
  and ((parent==units and state.units[model]==true) or (parent==buildings and state.buildings[model]==true))
end
local function canBuildWorker(state,unit)
 return isOwned(state,unit,units) and ConstructionRules.canBuildWorker(unit:GetAttribute("UnitType"),unit:GetAttribute("HP"),true)
end
local function isTarget(model)
 return typeof(model)=="Instance" and model:IsA("Model")
  and (model.Parent==buildings or model.Parent==units or model.Parent==resources)
  and (model:GetAttribute("RTSManaged")==true or model:GetAttribute("RTSManagedResource")==true)
  and (model:GetAttribute("HP")~=nil or model:GetAttribute("Amount")~=nil or model:GetAttribute("Relic")==true)
end
local function enemies(a,b)
 return alive(a)==true and alive(b)==true and currentMatch~=nil
  and TeamRules.isParticipant(matchTeams,currentMatch.factions,a) and TeamRules.isParticipant(matchTeams,currentMatch.factions,b)
  and TeamRules.enemies(matchTeams,a.id,b.id)
end
local function affordable(actor,cost)
 local balance={}
 for _,key in ipairs({"food","wood","gold","stone"}) do balance[key]=actor:GetAttribute(key) or 0 end
 return Rules.canSpend(balance,cost or {})
end
local function refund(actor,cost)
 for key,value in pairs(cost or {}) do actor:SetAttribute(key,(actor:GetAttribute(key) or 0)+value) end
end
local function population(state)
 local count,cap=Garrison.count(state),0
 for unit in pairs(state.units) do if unit.Parent==units then count+=1 end end
 for building in pairs(state.buildings) do
  if building.Parent==buildings then
   local data=Config.Buildings[building:GetAttribute("BuildingType")]
   if building:GetAttribute("Complete") then cap+=data and data.population or 0 end
   if training[building] then count+=#training[building] end
  end
 end
 cap=math.min(cap,settings.population)
 state.actor:SetAttribute("Population",count)
 state.actor:SetAttribute("PopulationCap",cap)
 return count,cap
end
-- 每個陣營依兵種／採集資源快取；科技完成或重置陣營時清空（state.statsCache=nil）。回傳的表為共用，呼叫端不得修改。
local function unitStats(state,kind,resourceKind)
 local cache=state.statsCache
 if not cache then cache={}; state.statsCache=cache end
 local byKind=cache[kind]
 if not byKind then byKind={}; cache[kind]=byKind end
 local cached=byKind[resourceKind or ""]
 if cached then return cached end
 local data,m=Config.Units[kind],state.modifiers
 local c=state.classModifiers[data.class] or {}
 local also=data.alsoClass and state.classModifiers[data.alsoClass] or {}
 local u=state.unitModifiers[kind] or {}
 local function value(key) return (m[key] or 0)+(c[key] or 0)+(also[key] or 0)+(u[key] or 0) end
 local specific=({food="gatherFood",wood="gatherWood",gold="gatherGold",stone="gatherStone"})[resourceKind]
 local military=data.class~="villager" and data.class~="monk" and data.class~="trade"
 cached={
  speed=data.speed*(1+value("speed")), damage=data.damage+(military and m.attack or 0)+(c.attack or 0)+(also.attack or 0)+(u.attack or 0),
  armor=(data.armor or 0)+(military and m.armor or 0)+(c.armor or 0)+(also.armor or 0)+(u.armor or 0),
  hp=data.hp+value("hp"),
  range=data.range+((military and data.range>20) and value("range") or 0), interval=(data.attackInterval or 1)*math.max(0.4,1-value("interval")),
  carry=(data.carryCapacity or 15)+value("carry"),
  gather=(data.gatherRate or 4)*(1+value("gather")+(specific and value(specific) or 0)),
 }
 byKind[resourceKind or ""]=cached
 return cached
end
local function refreshUnit(state,unit)
 local stats=unitStats(state,unit:GetAttribute("UnitType"))
 -- 兵種升級後的名稱與剋制加成；沒有升級時回到設定值。
 local kind=unit:GetAttribute("UnitType")
 unit:SetAttribute("DisplayName",state.unitNames[kind] or Config.Units[kind].name)
 local extra=(state.unitModifiers[kind] or {}).bonus or {}
 for class,amount in pairs(extra) do unit:SetAttribute("Bonus_"..class,(Config.Units[kind].bonus[class] or 0)+amount) end
 local oldMax=unit:GetAttribute("MaxHP") or stats.hp
 unit:SetAttribute("MaxHP",stats.hp)
 unit:SetAttribute("HP",math.min(stats.hp,(unit:GetAttribute("HP") or 0)+math.max(0,stats.hp-oldMax)))
 unit:SetAttribute("Attack",stats.damage)
 unit:SetAttribute("Armor",stats.armor)
 unit:SetAttribute("Speed",stats.speed)
 unit:SetAttribute("Range",stats.range)
 unit:SetAttribute("AttackInterval",stats.interval)
 if Config.Units[unit:GetAttribute("UnitType")].class=="villager" then
  unit:SetAttribute("CarryCapacity",stats.carry)
  for _,resourceKind in ipairs({"food","wood","gold","stone"}) do
   unit:SetAttribute("GatherRate_"..resourceKind,unitStats(state,unit:GetAttribute("UnitType"),resourceKind).gather)
  end
 end
end
-- Publish the same defensive weapon values used by the authoritative attack step.
local function buildingAttack(state,data)
 if not data or not data.damage then return 0 end
 return data.damage+state.modifiers.attack
end
local function refreshBuildingStats(state,model)
 local data=Config.Buildings[model:GetAttribute("BuildingType")]
 local armed=data and data.damage~=nil
 local armor=model:GetAttribute("Armor")
 model:SetAttribute("Attack",buildingAttack(state,data))
 model:SetAttribute("Range",armed and (data.range or 64) or 0)
 model:SetAttribute("AttackInterval",armed and (data.attackInterval or 1.5) or 0)
 -- Imported models can already carry authoritative armor; keep every finite value.
 model:SetAttribute("Armor",Rules.finite(armor) and armor or 0)
 Garrison.publish(model)
end
local function makeBuilding(state,kind,pos,complete,rotated)
 local data=Config.Buildings[kind]
 rotated=data.rotatable==true and rotated==true
 local sizeX,sizeY=Walls.rules.footprint(data.size.X,data.size.Y,rotated)
 local model=Factory.model(kind,pos,Vector3.new(sizeX*GRID_SIZE,data.height,sizeY*GRID_SIZE),data.color,"Buildings",state.actor:GetAttribute("TeamColor"),rotated)
 model:SetAttribute("RTSManaged",true)
 if data.rotatable then model:SetAttribute("Rotated",rotated) end
 if data.gate then model:SetAttribute("GateOpen",false) end
 model:SetAttribute("BuildingType",kind)
 model:SetAttribute("DisplayName",data.name)
 model:SetAttribute("HP",complete and data.hp or ConstructionRules.initialHP(data.hp))
 model:SetAttribute("MaxHP",data.hp)
 model:SetAttribute("OwnerId",state.id)
 model:SetAttribute("OwnerName",actorName(state.actor))
 publishCivilization(state,model)
 publishTeam(state,model)
 if kind=="TownCenter" then civilizationMark(state,model,data.height) end
 model:SetAttribute("Complete",complete==true)
 model:SetAttribute("UnderConstruction",complete~=true)
 model:SetAttribute("BuilderCount",0)
 model:SetAttribute("ConstructionStatus",complete and "已完工" or "等待村民")
 model:SetAttribute("ConstructionProgress",complete and 1 or 0)
 model:SetAttribute("ConstructionRemaining",complete and 0 or data.buildTime or 12)
 model:SetAttribute("QueueRevision",0)
 if kind=="Farm" then
  local amount=(data.amount or 600)+state.modifiers.farmCapacity
  model:SetAttribute("ResourceType","food")
  model:SetAttribute("Amount",complete and amount or 0)
  model:SetAttribute("MaxAmount",amount)
  Factory.watchFarm(model)
 end
 refreshBuildingStats(state,model)
 model.Parent=buildings
 state.buildings[model]=true
 if data.gate and complete then Walls.activate(state,model) end
 population(state)
 return model
end
local function makeUnit(state,kind,pos)
 local model=Factory.unit(kind,pos,Config.Units[kind],state.actor)
 model:SetAttribute("RTSManaged",true)
 model:SetAttribute("Carrying",0)
 model:SetAttribute("CarryType","")
 model:SetAttribute("Animation","Idle")
 model:SetAttribute("Formation",Config.Formations.default)
 model:SetAttribute("FormationForwardX",0)
 model:SetAttribute("FormationForwardZ",-1)
 if kind=="monk" then model:SetAttribute("Faith",Monk.config.maxFaith); model:SetAttribute("MaxFaith",Monk.config.maxFaith) end
 if kind=="villager" then Factory.watchCarry(model) end
 publishCivilization(state,model)
 publishTeam(state,model)
 model.Parent=units
 state.units[model]=true
 unitCollisionIndex:Update(model,pos.X,pos.Z,model:GetAttribute("Radius"))
 refreshUnit(state,model)
 population(state)
 return model
end
local function makeResource(kind,pos)
 local data=Config.Resources[kind]
 local footprint=Config.Map.ResourceFootprint or 8
 local model=Factory.model(kind,pos,Vector3.new(footprint,data.height,footprint),data.color,"Resource")
 model:SetAttribute("RTSManagedResource",true)
 model:SetAttribute("ResourceType",data.resource)
 model:SetAttribute("DisplayName",data.name)
 model:SetAttribute("Amount",data.amount)
 model:SetAttribute("MaxAmount",data.amount)
 if data.gatherMultiplier then model:SetAttribute("GatherMultiplier",data.gatherMultiplier) end
 if data.hunt then model:SetAttribute("Hunt",true) end
 model.Parent=resources
 managedResources[model]=true
 return model
end
local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Exclude
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide=true
local attackOverlap=OverlapParams.new()
attackOverlap.FilterType=Enum.RaycastFilterType.Exclude
attackOverlap.RespectCanCollide=true
-- The filter cache lives in a block so it does not hold a top-level register (Studio limit 200).
local updateObstacleFilters
do
local lastFilterGround,filtersInitialized
updateObstacleFilters=function()
 local ground=workspace:FindFirstChild("AOE2_Ground")
 if filtersInitialized and ground==lastFilterGround then return end
 lastFilterGround,filtersInitialized=ground,true
 -- Generated scenery is non-queryable; a user's same-name folder may block movement.
 local excluded={units}
 if ground then table.insert(excluded,ground) end
 rayParams.FilterDescendantsInstances=excluded
 attackOverlap.FilterDescendantsInstances=excluded
 local placementExcluded={}
 if ground then table.insert(placementExcluded,ground) end
 overlap.FilterDescendantsInstances=placementExcluded
end
end
local function obstacleParts(pos,size)
 updateObstacleFilters()
 local hits=workspace:GetPartBoundsInBox(CFrame.new(pos),size,overlap)
 local obstacles={}
 for _,part in ipairs(hits) do
  -- 單位只以碰撞體積佔位：移動中的外觀零件在伺服器端不即時跟隨 Root。
  if part.CanCollide or part:IsDescendantOf(buildings) or part:IsDescendantOf(resources) or (part.Name=="CollisionVolume" and part:IsDescendantOf(units)) then table.insert(obstacles,part) end
 end
 return obstacles
end
local function placementClear(pos,data,size)
 size=size or data.size
 return #obstacleParts(pos+Vector3.new(0,data.height/2,0),
  Vector3.new(size.X*GRID_SIZE-0.2,math.max(4,data.height),size.Y*GRID_SIZE-0.2))==0
end
-- 城門可以直接蓋在自己的石牆上：占地內只有己方石牆時回傳要拆除的牆段，其餘障礙一律拒絕。
Walls.replaceable=function(state,pos,data,size)
 local walls,seen={},{}
 for _,part in ipairs(obstacleParts(pos+Vector3.new(0,data.height/2,0),
  Vector3.new(size.X*GRID_SIZE-0.2,math.max(4,data.height),size.Y*GRID_SIZE-0.2))) do
  local model=part
  while model and model.Parent~=buildings do model=model.Parent end
  if not model or not model:IsA("Model") or model:GetAttribute("BuildingType")~="Wall"
   or model:GetAttribute("RTSManaged")~=true or state.buildings[model]~=true then return nil end
  if not seen[model] then seen[model]=true; table.insert(walls,model) end
 end
 return walls
end
-- 完工後占地不再碰撞；導航以標籤區域表示，敵方尋路時把該標籤設為不可通行。
Walls.label=function(state) return "RTSGate"..tostring(state.id) end
Walls.activate=function(state,model)
 local root=model.PrimaryPart
 if not root then return end
 local center=root.Position
 root.CanCollide=false
 local modifier=Instance.new("PathfindingModifier")
 modifier.Label=Walls.label(state)
 modifier.Parent=root
 Walls.gates[model]={state=state,X=center.X,Z=center.Z,halfX=root.Size.X/2,halfZ=root.Size.Z/2,open=false}
end
-- Static scenery stays in engine queries; moving units use a live spatial index.
-- PivotTo bypasses physics, so every server movement segment checks both.
units.ChildRemoved:Connect(function(unit) unitCollisionIndex:Remove(unit) end)
-- 靜態淨空快取：單位周圍一個方框內沒有任何可碰撞的靜態物件時，框內的移動段不必逐段做引擎查詢。
-- 大型戰鬥多在空地，原本每個單位每步 2–16 次 Blockcast／範圍查詢是主要耗時。
-- 建築或資源新增時整批失效；其餘（例如使用者模型變動）靠短壽命重新探測。
-- 掛在碰撞索引表上，不占主程式區塊的 local 暫存器（Studio 上限 200）。
unitCollisionIndex.staticClear={zones=setmetatable({},{__mode="k"}),epoch=0,half=16,life=0.5}
buildings.ChildAdded:Connect(function() unitCollisionIndex.staticClear.epoch+=1 end)
resources.ChildAdded:Connect(function() unitCollisionIndex.staticClear.epoch+=1 end)
local function unitInBounds(pos,radius)
 local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
 return validPosition(pos) and math.abs(pos.X)+radius<=half and math.abs(pos.Z)+radius<=half
end
local function unitBody(unit)
 local radius=unit:GetAttribute("Radius") or Config.UnitCollision.default.radius
 local height=unit:GetAttribute("CollisionHeight") or Config.UnitCollision.default.height
 return radius,height,Vector3.new(radius*2,height-0.1,radius*2)
end
local function staticUnitSegmentClear(unit,from,to)
 local radius,height,size=unitBody(unit)
 if not unitInBounds(to,radius) then return false end
 if next(Walls.gates)~=nil and Walls.blocks(unit,from,to,radius) then return false end
 updateObstacleFilters()
 local offset=Vector3.new(0,height/2,0)
 local staticClear=unitCollisionIndex.staticClear
 local zone=staticClear.zones[unit]
 local clock=os.clock()
 if not zone or zone.epoch~=staticClear.epoch or clock>=zone.expires then
  -- 以單位實際位置為中心探測；from／to 可能是尋路時的假設點。
  local center=unit:GetPivot().Position
  local parts=workspace:GetPartBoundsInBox(CFrame.new(center.X,height/2,center.Z),Vector3.new(staticClear.half*2,height+1,staticClear.half*2),attackOverlap)
  zone={X=center.X,Z=center.Z,clear=#parts==0,epoch=staticClear.epoch,expires=clock+staticClear.life}
  staticClear.zones[unit]=zone
 end
 if zone.clear then
  local reach=staticClear.half-radius
  if math.abs(from.X-zone.X)<=reach and math.abs(from.Z-zone.Z)<=reach and math.abs(to.X-zone.X)<=reach and math.abs(to.Z-zone.Z)<=reach then return true end
 end
 local delta=to-from
 return (delta.Magnitude==0 or workspace:Blockcast(CFrame.new(from+offset),size,delta,rayParams)==nil)
  and #workspace:GetPartBoundsInBox(CFrame.new(to+offset),size,attackOverlap)==0
end
Walls.blocks=function(unit,from,to,radius)
 local mine
 for gate,entry in pairs(Walls.gates) do
  if gate.Parent~=buildings then Walls.gates[gate]=nil
  elseif Walls.rules.gateBlocks(from.X,from.Z,to.X,to.Z,radius,entry.X,entry.Z,entry.halfX,entry.halfZ) then
   mine=mine or owner(unit)
   if mine and enemies(mine,entry.state) then return true end
  end
 end
 return false
end
-- 敵方城門的導航標籤成本為無限大；沒有城門或沒有敵方城門時不帶成本表。
Walls.costs=function(unit)
 local mine,costs=nil,nil
 for gate,entry in pairs(Walls.gates) do
  if gate.Parent==buildings then
   mine=mine or owner(unit)
   if mine and enemies(mine,entry.state) then costs=costs or {}; costs[Walls.label(entry.state)]=math.huge end
  end
 end
 return costs
end
-- 閘門外觀：己方或同盟單位靠近時升起。只發布 GateOpen 屬性，通行與否不依賴它。
Walls.step=function()
 if next(Walls.gates)==nil then return end
 local reach=Walls.config.gateOpenRadius*Walls.config.gateOpenRadius
 for gate,entry in pairs(Walls.gates) do
  if gate.Parent~=buildings then Walls.gates[gate]=nil else entry.near=false end
 end
 for unit,record in pairs(unitCollisionIndex:Records()) do
  for _,entry in pairs(Walls.gates) do
   if not entry.near and Walls.rules.boxDistanceSquared(record.X,record.Z,entry.X,entry.Z,entry.halfX,entry.halfZ)<=reach then
    local other=owner(unit)
    if other and (other==entry.state or (alive(other) and not enemies(other,entry.state))) then entry.near=true end
   end
  end
 end
 for gate,entry in pairs(Walls.gates) do
  if entry.near~=entry.open then entry.open=entry.near; gate:SetAttribute("GateOpen",entry.open) end
 end
end
-- 同一個單位在同一步內會對多個避讓候選各查一次鄰居；先取一次涵蓋所有候選的鄰居清單共用，
-- 任何單位移動（索引 version 改變）或查詢點超出涵蓋範圍就重取。多出來的遠處鄰居不影響碰撞判定。
local function unitNeighbors(unit,from,to,radius)
 local index=unitCollisionIndex
 local profile=index.profile
 local started=profile and os.clock()
 local reach=radius+MAX_UNIT_RADIUS+UnitCollisionRules.MIN_GAP
 local scan=index.scan
 local fx,fz=scan and from.X-scan.X or 0,scan and from.Z-scan.Z or 0
 if not (scan and scan.unit==unit and scan.version==index.version and math.sqrt(fx*fx+fz*fz)+reach<=scan.limit) then
  -- 掃描半徑依這一步的位移決定（避讓候選與直行同距離）；只留圓內的紀錄，擁擠時每個候選要比對的鄰居少很多。
  local sx,sz=to.X-from.X,to.Z-from.Z
  local limit=math.sqrt(sx*sx+sz*sz)+reach+0.5
  local cells=index:Around(from.X,from.Z,limit,unit)
  scan=nil
  if cells then
   local records={}
   for _,record in ipairs(cells) do
    local dx,dz=record.X-from.X,record.Z-from.Z
    if dx*dx+dz*dz<=limit*limit then table.insert(records,record) end
   end
   scan={unit=unit,version=index.version,X=from.X,Z=from.Z,limit=limit,records=records}
  end
  index.scan=scan
 end
 local result
 local tx,tz=scan and to.X-scan.X or 0,scan and to.Z-scan.Z or 0
 if scan and math.sqrt(tx*tx+tz*tz)+reach<=scan.limit then result=scan.records
 else result=index:Nearby(from.X,from.Z,to.X,to.Z,radius,unit) end
 if profile then profile.neighbor+=os.clock()-started; profile.neighbors+=1 end
 return result
end
local function unitPositionClear(unit,pos,radius)
 return not UnitCollisionRules.overlaps(pos.X,pos.Z,radius,unitNeighbors(unit,pos,pos,radius))
end
local function stationaryUnitAt(unit,pos,radius)
 for _,neighbor in ipairs(unitNeighbors(unit,pos,pos,radius) or {}) do
  if UnitCollisionRules.overlaps(pos.X,pos.Z,radius,{neighbor}) then
   local other=neighbor.key
   local animation=other:GetAttribute("Animation")
   if not orders[other] or animation=="Work" or animation=="Attack" then return true end
  end
 end
 return false
end
local function edgePosition(target,current)
 local center=position(target)
 if target.Parent==units then
  local delta=current-center
  local radius=target:GetAttribute("Radius") or Config.UnitCollision.default.radius
  return delta.Magnitude>radius and center+delta.Unit*radius or current
 end
 local half=target.PrimaryPart and target.PrimaryPart.Size/2 or Vector3.new(2,2,2)
 return Vector3.new(math.clamp(current.X,center.X-half.X,center.X+half.X),Config.Map.GroundY,
  math.clamp(current.Z,center.Z-half.Z,center.Z+half.Z))
end
local function distanceTo(target,current)
 return (edgePosition(target,current)-current).Magnitude
end
local function interactionLineClear(target,current)
 local offset=edgePosition(target,current)-current
 if offset.Magnitude<0.01 then return true end
 local hit=workspace:Raycast(current+Vector3.new(0,2.5,0),offset,rayParams)
 return not hit or hit.Instance:IsDescendantOf(target)
end
local function interactionApproach(unit,order,target,current,range,now)
 local center=position(target)
 if (order.blacklistCenter and (center-order.blacklistCenter).Magnitude>8)
  or (order.approachCenter and (center-order.approachCenter).Magnitude>8) then
  order.approachBlacklist=nil
  order.blacklistCenter=nil
  order.approachGoal,order.path=nil,nil
  order.nextApproach=0
 end
 if order.approachGoal and now<(order.nextApproach or 0) then return order.approachGoal end
 local half=target.PrimaryPart and target.PrimaryPart.Size/2 or Vector3.new(2,2,2)
 local radius=unit:GetAttribute("Radius") or 2
 if target.Parent==units then half=Vector3.new(target:GetAttribute("Radius") or 2,half.Y,target:GetAttribute("Radius") or 2) end
 local candidates=MeleeRules.candidates(center.X,center.Z,half.X,half.Z,radius,range) or {}
 local function usable(candidatePoint,ignoreUnits)
  local candidate=Vector3.new(candidatePoint.X,Config.Map.GroundY,candidatePoint.Z)
  return staticUnitSegmentClear(unit,candidate,candidate) and distanceTo(target,candidate)<=range
   and (ignoreUnits or unitPositionClear(unit,candidate,radius))
   and interactionLineClear(target,candidate)
 end
 local point=ApproachRules.nearest(candidates,current.X,current.Z,order.approachBlacklist,function(candidate) return usable(candidate,false) end)
 -- A temporary crowd can vacate a work position; it is not an unreachable wall.
 if not point then point=ApproachRules.nearest(candidates,current.X,current.Z,order.approachBlacklist,function(candidate) return usable(candidate,true) end) end
 local best=point and Vector3.new(point.X,Config.Map.GroundY,point.Z) or nil
 if best~=order.approachGoal then order.path=nil end
 order.approachGoal,order.approachIndex,order.approachCenter=best,point and point.index or nil,center
 order.nextApproach=now+1.5
 return best
end
-- 重新播種的判斷：磨坊預置優先，其次是允許自動播種且木材足夠。
AutoWork.autoReseed=function(state)
 return Config.AutoWork.reseedFarms==true and (state.ai==true or state.autoWork~=false)
end
AutoWork.canReseed=function(state)
 local source=AutoWork.farmRules.reseedSource(state.actor:GetAttribute("FarmQueue") or 0,false,AutoWork.autoReseed(state))
 return source=="queue" or (source=="wood" and affordable(state.actor,Config.Buildings.Farm.cost))
end
-- 可指派的農田：已完工、沒有其他村民，且仍有食物或能立即重新播種。
AutoWork.farmUsable=function(state,farm,unit)
 return farm.Parent==buildings and farm:GetAttribute("BuildingType")=="Farm" and farm:GetAttribute("Complete")==true
  and AutoWork.farmFree(farm,unit) and ((farm:GetAttribute("Amount") or 0)>0 or AutoWork.canReseed(state))
end
-- 耗盡的農田收起作物；使用者自訂模型沒有 CropRow 時維持原樣。
AutoWork.farmLook=function(farm)
 local exhausted=(farm:GetAttribute("Amount") or 0)<=0 and farm:GetAttribute("Complete")==true
 farm:SetAttribute("Exhausted",exhausted)
 for _,part in ipairs(farm:GetDescendants()) do
  if part:IsA("BasePart") and part.Name=="CropRow" then part.Transparency=exhausted and 1 or 0 end
 end
end
stop=function(unit,preserveFormationSlot)
 orders[unit]=nil
 if not preserveFormationSlot and unit.Parent then unit:SetAttribute("FormationSlot",nil) end
 if unit.Parent then
  -- 停下時把伺服器端的外觀零件對齊 Root（移動中只搬 Root）。
  Factory.syncAppearance(unit)
  unit:SetAttribute("Order","待命"); unit:SetAttribute("Animation","Idle"); unit:SetAttribute("WorkKind",nil)
  unit:SetAttribute("OrderKind",nil)
  unit:SetAttribute("OrderTargetName",nil)
  unit:SetAttribute("OrderTargetBuildingType",nil)
  unit:SetAttribute("OrderTargetResourceType",nil)
 end
end
issue=function(unit,kind,target,automatic)
 orders[unit]={kind=kind,target=target,lastPath=0,automatic=automatic==true}
 if kind=="gather" then AutoWork.claimFarm(target,unit) end
 local autoEntry=AutoWork.units[unit]
 if autoEntry then autoEntry.idleSince=nil; if kind~="move" then autoEntry.hold=nil end end
 unit:SetAttribute("FormationSlot",kind=="move" and target or nil)
 unit:SetAttribute("Animation","Idle")
 unit:SetAttribute("WorkKind",nil)
 unit:SetAttribute("Order",({move="移動",gather="採集",deliver="交貨",attack="攻擊",build="施工",repair="修復",convert="招降",heal="治療",garrison="駐紮",relic="拾取聖物",relicStore="存放聖物",trade="貿易"})[kind] or "移動")
 local targetModel=typeof(target)=="Instance" and target:IsA("Model") and target or nil
 unit:SetAttribute("OrderKind",kind)
 unit:SetAttribute("OrderTargetName",targetModel and (targetModel:GetAttribute("DisplayName") or targetModel.Name) or nil)
 unit:SetAttribute("OrderTargetBuildingType",targetModel and targetModel:GetAttribute("BuildingType") or nil)
 unit:SetAttribute("OrderTargetResourceType",targetModel and targetModel:GetAttribute("ResourceType") or nil)
end
local function unreachable(unit,order,message)
 local state=owner(unit)
 if state and state.ai and order.kind=="build" then
  local retries=state.buildRetryAfter[order.target] or {}
  retries[unit]=os.clock()+8
  state.buildRetryAfter[order.target]=retries
 end
 if order.kind=="attack" and state then
  -- 這個目標暫時不再自動選取，讓索敵改挑其他走得到的敵人。
  local clock=actionClocks[unit] or {}
  clock.skipTarget,clock.skipUntil=order.target,os.clock()+8
  actionClocks[unit]=clock
  finishAttack(state,unit,order)
 else stop(unit) end
 -- 自動接戰（索敵、反擊、電腦進攻波）找不到路不是玩家下的指令，不跳提示。
 if order.kind=="attack" and order.automatic then return end
 if order.autoWork then
  -- 自動指派失敗時不打擾玩家，暫時略過該目標改找其他工作。
  local entry=AutoWork.units[unit] or {}
  entry.blocked=entry.blocked or {}
  entry.blocked[order.target]=os.clock()+Config.AutoWork.blockedTime
  AutoWork.units[unit]=entry
  return
 end
 if state then notify(state.actor,message or "無法抵達目標，請選擇其他位置。") end
end
local function refreshRouteGoal(order,goal)
 local changed=false
 if not order.routeGoal then order.routeGoal=goal
 elseif PathRules.goalChanged(order.routeGoal.X,order.routeGoal.Z,goal.X,goal.Z) then changed=true end
 if order.kind=="attack" then
  local target=position(order.target)
  if not order.attackPathTarget then order.attackPathTarget=target
  elseif PathRules.goalChanged(order.attackPathTarget.X,order.attackPathTarget.Z,target.X,target.Z) then changed=true end
  if changed then order.attackPathTarget=target end
 end
 if changed then
  order.routeGoal=goal
  order.routeVersion=(order.routeVersion or 0)+1
  order.path,order.partialRoute,order.pendingRoute=nil,nil,nil
  order.partialHistory,order.partialAttempts=nil,nil
 end
end
local function route(unit,order,goal,now)
 if order.computing or pathTasks>=8 or now-order.lastPath<1.5 then return end
 if order.partialAttempts then
  local nextAttempt=PathRules.nextPartialAttempt(order.partialAttempts)
  if not nextAttempt then unreachable(unit,order,"安全續路次數已達上限，請調整目標後重試。"); return end
  order.partialAttempts=nextAttempt
 end
 order.computing,order.lastPath=true,now
 pathTasks+=1
 local generation=matchGeneration
 local approachGoal=order.approachGoal
 local approachIndex=order.approachIndex
 local approachCenter=order.approachCenter
 local routeVersion=order.routeVersion or 0
 task.spawn(function()
  local radius=unit:GetAttribute("Radius") or 2
  local radii=PathRules.candidateRadii(radius)
  local accepted,blockedToward,partial
  local prefixes={}
  if radii then
   local engineCalls=0
   local function currentOrder()
    return generation==matchGeneration and orders[unit]==order and unit.Parent==units and approachGoal==order.approachGoal
     and routeVersion==(order.routeVersion or 0)
   end
   local function project(waypoint)
    local p=waypoint.Position
    if typeof(p)~="Vector3" then return nil end
    local projected=Vector3.new(p.X,Config.Map.GroundY,p.Z)
    return unitInBounds(projected,radius) and projected or nil
   end
   local function segmentClear(from,to)
    return staticUnitSegmentClear(unit,from,to)
   end
   local function compute(origin,agentRadius)
    local nextCall=PathRules.nextComputeCall(engineCalls)
    if not currentOrder() or not nextCall then return nil end
    engineCalls=nextCall
    local ok,waypoints=pcall(function()
     local path=PathfindingService:CreatePath({AgentRadius=agentRadius,AgentHeight=unit:GetAttribute("CollisionHeight") or 5,AgentCanJump=false,WaypointSpacing=8,Costs=Walls.costs(unit)})
     path:ComputeAsync(origin+Vector3.new(0,2,0),goal+Vector3.new(0,2,0))
     return path.Status==Enum.PathStatus.Success and path:GetWaypoints() or nil
    end)
    return ok and currentOrder() and waypoints or nil
   end
   -- A navigation Success is insufficient: its turns can intersect our square
   -- movement body. Keep the smallest radius whose whole live route is clear.
   for _,agentRadius in ipairs(radii) do
    local waypoints=compute(position(unit),agentRadius)
    if not currentOrder() then break end
    local inspected,index=PathRules.inspectPath(waypoints,position(unit),project,segmentClear)
    if inspected and inspected.full then accepted=waypoints; break end
    if inspected and #inspected.path>=2 then table.insert(prefixes,inspected) end
    if not blockedToward and index and index<=2 then blockedToward=project(waypoints[index]) end
   end
   if not accepted and currentOrder() then
    local live,toward=position(unit),blockedToward or goal
    local function safeOrigin(candidate,from)
     return segmentClear(from,candidate)
    end
    local escapes=PathRules.selectEscapes(PathRules.escapeCandidates(live.X,live.Z,toward.X,toward.Z),function(candidate)
     return safeOrigin(Vector3.new(candidate.X,Config.Map.GroundY,candidate.Z),live)
    end) or {}
    for _,candidate in ipairs(escapes) do
     local origin=Vector3.new(candidate.X,Config.Map.GroundY,candidate.Z)
     for _,agentRadius in ipairs(PathRules.escapeRadii(radius) or {}) do
      if not currentOrder() then break end
      local waypoints=compute(origin,agentRadius)
      if not currentOrder() then break end
      local path=PathRules.prepend(waypoints,origin)
      -- Revalidate from the live position after ComputeAsync; never teleport.
      if safeOrigin(origin,position(unit)) then
       local inspected=PathRules.inspectPath(path,position(unit),project,segmentClear)
       if inspected and inspected.full then accepted=path; break end
       if inspected and #inspected.path>=2 then table.insert(prefixes,inspected) end
      end
     end
     if accepted or not currentOrder() then break end
    end
   end
   if not accepted and currentOrder() then
    local live=position(unit)
    local safe={}
    for _,candidate in ipairs(prefixes) do
     if PathRules.clearPath(candidate.path,live,project,segmentClear) then table.insert(safe,candidate) end
    end
    local candidate=PathRules.bestPrefix(safe,live.X,live.Z,goal.X,goal.Z,order.partialHistory or {})
    if candidate then
     accepted,partial=candidate.path,true
     order.partialAttempts=order.partialAttempts or 1
    end
   end
  end
  pathTasks=math.max(0,pathTasks-1)
  if generation~=matchGeneration or orders[unit]~=order or unit.Parent~=units then return end
  order.computing=false
  if approachGoal~=order.approachGoal or routeVersion~=(order.routeVersion or 0) then return end
  if accepted then
   order.path,order.index,order.failures=accepted,1,0
   order.partialRoute,order.pendingRoute=partial==true,false
  elseif order.approachGoal and approachIndex then
   order.approachBlacklist=order.approachBlacklist or {}
   order.blacklistCenter=order.blacklistCenter or approachCenter
   order.approachBlacklist[approachIndex]=true
   order.approachGoal,order.path=nil,nil
   order.nextApproach=0
  else
   order.failures=(order.failures or 0)+1
   if order.failures>=3 then
    unreachable(unit,order)
   end
  end
 end)
end
local function moveToward(unit,order,destination,speed,dt,now)
 if order.crowdedRetry then
  if now<order.crowdedRetry then return end
  order.crowdedRetry=nil
 end
 refreshRouteGoal(order,destination)
 if order.escapeGoal and (not order.escapeOriginalGoal or (destination-order.escapeOriginalGoal).Magnitude>.05) then
  order.escapeGoal,order.escapeOriginalGoal,order.escapeExpires=nil,nil,nil
 end
 if order.pendingRoute then route(unit,order,destination,now); return end
 local current,goal=position(unit),destination
 -- Skip coincident/reached waypoints in this same tick. Returning once for
 -- every 8-stud path node previously added a visible 0.1-second pause.
 while order.path and order.path[order.index] do
  local p=order.path[order.index].Position
  goal=Vector3.new(p.X,Config.Map.GroundY,p.Z)
  local following=order.path[order.index+1]
  if not following and order.partialRoute and (goal-current).Magnitude<=(unit:GetAttribute("Radius") or 2)+MAX_UNIT_RADIUS+1
   and not unitPositionClear(unit,goal,unit:GetAttribute("Radius") or 2) then
   -- A crowded prefix endpoint cannot be reached exactly. Continue from the
   -- last safe live position using the existing bounded partial-route budget.
   order.partialHistory=order.partialHistory or {}
   table.insert(order.partialHistory,{X=current.X,Z=current.Z})
   order.path,order.partialRoute,order.pendingRoute=nil,false,true
   route(unit,order,destination,now)
   return
  end
  if (following or not order.partialRoute) and not unitPositionClear(unit,goal,unit:GetAttribute("Radius") or 2) then
   local nextPoint=following and following.Position or destination
   local after=Vector3.new(nextPoint.X,Config.Map.GroundY,nextPoint.Z)
   -- A unit can occupy a navigation node permanently. Advance only when the
   -- live segment to the following node clears static scenery; crowd steering
   -- still validates every actual step around the occupying unit.
   if staticUnitSegmentClear(unit,current,after) then
    if following then order.index+=1; continue end
    order.path=nil; goal=destination; break
   end
  end
  if not PathRules.waypointReached((goal-current).Magnitude) then break end
  order.index+=1
  if not order.path[order.index] then
   order.path=nil
   if order.partialRoute then
    order.partialHistory=order.partialHistory or {}
    table.insert(order.partialHistory,{X=current.X,Z=current.Z})
    order.partialRoute,order.pendingRoute=false,true
    route(unit,order,destination,now)
    return
   end
   goal=destination
  end
 end
 if order.path and not order.path[order.index] then order.path=nil; goal=destination end
 local radius=unit:GetAttribute("Radius") or 2
 if order.escapeGoal then
  local directClear=staticUnitSegmentClear(unit,current,goal)
   and UnitCollisionRules.segmentClear(current.X,current.Z,goal.X,goal.Z,radius,unitNeighbors(unit,current,goal,radius))
  if now>=order.escapeExpires or PathRules.waypointReached((order.escapeGoal-current).Magnitude) or directClear then
   order.escapeGoal,order.escapeOriginalGoal,order.escapeExpires=nil,nil,nil
  elseif not staticUnitSegmentClear(unit,current,order.escapeGoal) then
   order.escapeGoal,order.escapeOriginalGoal,order.escapeExpires=nil,nil,nil
   order.path=nil; route(unit,order,destination,now); return
  else goal=order.escapeGoal end
 end
 local delta=goal-current
 if delta.Magnitude<0.05 then return end
 local nextPos=current+delta.Unit*math.min(delta.Magnitude,speed*dt)
 if not staticUnitSegmentClear(unit,current,nextPos) then
  order.escapeGoal,order.escapeOriginalGoal,order.escapeExpires=nil,nil,nil
  order.path=nil; route(unit,order,destination,now); return
 end
 local neighbors=unitNeighbors(unit,current,nextPos,radius)
 if not UnitCollisionRules.segmentClear(current.X,current.Z,nextPos.X,nextPos.Z,radius,neighbors) then
  if order.kind=="move" and (destination-current).Magnitude<=radius+MAX_UNIT_RADIUS+1
   and stationaryUnitAt(unit,destination,radius) then stop(unit); return end
  local step=math.min(delta.Magnitude,speed*dt)
  local accepted
  for _,candidate in ipairs(UnitCollisionRules.steeringCandidates(current.X,current.Z,goal.X,goal.Z,step,order.avoidSide) or {}) do
   local point=Vector3.new(candidate.X,Config.Map.GroundY,candidate.Z)
   -- 先做純 Lua 的單位碰撞檢查；擁擠時多數候選在這裡就被排除，不必進引擎查詢。
   if UnitCollisionRules.segmentClear(current.X,current.Z,point.X,point.Z,radius,unitNeighbors(unit,current,point,radius))
    and staticUnitSegmentClear(unit,current,point) then
    accepted=point
    if candidate.side then order.avoidSide=candidate.side end
    break
   end
  end
  if not accepted and not order.escapeGoal and (order.escapeAttempts or 0)<UnitCollisionRules.MAX_RETREAT_ATTEMPTS then
   -- A delivery worker may be trapped behind its own idle formation. Only
   -- after all normal steering fails, retain one short, fully checked retreat.
   -- Attempts/history remain bounded even if no safe retreat point exists.
   order.escapeAttempts=(order.escapeAttempts or 0)+1
   local retreatDistance=MAX_UNIT_RADIUS*2
   local duration=UnitCollisionRules.retreatDuration(retreatDistance,speed,.1)
   for _,candidate in ipairs(duration and UnitCollisionRules.retreatCandidates(current.X,current.Z,goal.X,goal.Z,retreatDistance,order.avoidSide) or {}) do
    local point=Vector3.new(candidate.X,Config.Map.GroundY,candidate.Z)
    local visited=false
    for _,previous in ipairs(order.escapeHistory or {}) do
     if (point-Vector3.new(previous.X,Config.Map.GroundY,previous.Z)).Magnitude<radius then visited=true; break end
    end
    local advance=current+(point-current).Unit*math.min((point-current).Magnitude,speed*dt)
    if not visited
     and UnitCollisionRules.segmentClear(current.X,current.Z,point.X,point.Z,radius,unitNeighbors(unit,current,point,radius))
     and UnitCollisionRules.segmentClear(current.X,current.Z,advance.X,advance.Z,radius,unitNeighbors(unit,current,advance,radius))
     and staticUnitSegmentClear(unit,current,point)
     and staticUnitSegmentClear(unit,current,advance) then
     order.escapeGoal,order.escapeOriginalGoal,order.escapeExpires=point,destination,now+duration
     order.escapeHistory=order.escapeHistory or {}
     table.insert(order.escapeHistory,{X=point.X,Z=point.Z})
     order.avoidSide=candidate.side
     accepted=advance
     break
    end
   end
  end
  if not accepted then
   order.crowdedSince=order.crowdedSince or now
   -- 四周都被擋住：隔 0.2–0.4 秒再試，不必每一步重算全部避讓候選（錯開時間避免同一步集中重試）。
   order.crowdedRetry=now+0.2+math.random()*0.2
   unit:SetAttribute("Animation","Idle")
   -- A filled move destination is reached beside the occupying unit.
   if order.kind=="move" and now-order.crowdedSince>=1
    and (destination-current).Magnitude<=radius+MAX_UNIT_RADIUS+1
    and stationaryUnitAt(unit,destination,radius) then stop(unit) end
   return
  end
  nextPos=accepted
 elseif not order.escapeGoal then order.avoidSide=nil end
 order.crowdedSince=nil
 local facing=nextPos-current
 unit:SetAttribute("Animation","Walk")
 local profile=unitCollisionIndex.profile
 local pivotStarted=profile and os.clock()
 Factory.moveUnit(unit,CFrame.lookAt(nextPos+Vector3.new(0,2.5,0),nextPos+facing.Unit+Vector3.new(0,2.5,0)))
 if profile then profile.pivot+=os.clock()-pivotStarted; profile.pivots+=1 end
 unitCollisionIndex:Update(unit,nextPos.X,nextPos.Z,radius)
end
local function nearestResource(state,pos,kind,unit)
 local nearest,distance=nil,math.huge
 for resource in pairs(managedResources) do
  if resource.Parent~=resources then managedResources[resource]=nil
  elseif (resource:GetAttribute("Amount") or 0)>0 and (not kind or resource:GetAttribute("ResourceType")==kind) then
   local d=(position(resource)-pos).Magnitude
   if d<distance then nearest,distance=resource,d end
  end
 end
 if not kind or kind=="food" then
  for b in pairs(state.buildings) do
   if AutoWork.farmUsable(state,b,unit) then
    local d=distanceTo(b,pos)
    if d<distance then nearest,distance=b,d end
   end
  end
 end
 return nearest
end
local function acceptsResource(building,key)
 local data=Config.Buildings[building:GetAttribute("BuildingType")]
 return GatheringRules.accepts(data,key)
end
local function nearestDropoff(state,pos,key)
 local nearest,distance=nil,math.huge
 for b in pairs(state.buildings) do
  if b.Parent==buildings and b:GetAttribute("Complete") and acceptsResource(b,key) then
   local d=distanceTo(b,pos)
   if d<distance then nearest,distance=b,d end
  end
 end
 return nearest
end
local function beginDelivery(state,unit,returnTarget,preferredDropoff,returnKind)
 local key=unit:GetAttribute("CarryType")
 local dropoff=preferredDropoff or nearestDropoff(state,position(unit),key)
 if dropoff and isOwned(state,dropoff,buildings) and dropoff:GetAttribute("Complete") and acceptsResource(dropoff,key) then
  issue(unit,"deliver",dropoff)
  orders[unit].returnTarget=returnTarget
  orders[unit].returnKind=GatheringRules.returnKind(key,returnKind or (returnTarget and returnTarget:GetAttribute("ResourceType")))
  AutoWork.claimFarm(returnTarget,unit)
 else stop(unit); notify(state.actor,"需要合適的經濟建築才能交回資源。") end
end
finishAttack=function(state,unit,order)
 -- 進攻波途中的遭遇戰結束後回到原本的進攻目標；目標本身無法抵達時不再重試。
 local objective=order.objective
 if objective and objective~=order.target and objective.Parent and enemies(state,owner(objective)) then
  issue(unit,"attack",objective,true)
  orders[unit].objective=objective
  return
 end
 if not order.resumeGather then stop(unit); return end
 local target=order.resumeGather
 local key=order.resumeKind
 if not target.Parent or (target:GetAttribute("Amount") or 0)<=0 then target=nearestResource(state,position(unit),key,unit) end
 if (unit:GetAttribute("Carrying") or 0)>0 and (not target or unit:GetAttribute("CarryType")~=key) then
  beginDelivery(state,unit,target,nil,key)
 elseif target then issue(unit,"gather",target)
 else stop(unit) end
end
-- 建造請求共用：驗證選取的村民；AI 取最近的村民；玩家空選取時由伺服器派最近的村民。
Walls.builders=function(state,rawPosition,selection,count,quiet)
 local builders=ConstructionRules.validateSelection(selection,function(unit) return canBuildWorker(state,unit) end,Config.Construction.maxSelectedWorkers)
 if not builders and state.ai then
  local nearest,distance=nil,math.huge
  for unit in pairs(state.units) do
   local order=orders[unit]
   if canBuildWorker(state,unit) and (not order or order.kind~="build") then
    local candidate=(position(unit)-rawPosition).Magnitude
    if candidate<distance then nearest,distance=unit,candidate end
   end
  end
  builders=nearest and {nearest} or nil
 end
 -- 未選村民時（空選取）由伺服器派最近的村民；正在施工的村民不會被拉走。
 local autoAssigned=false
 if not builders and not state.ai and type(selection)=="table" and next(selection)==nil then
  local candidates={}
  for unit in pairs(state.units) do
   if unit.Parent==units and canBuildWorker(state,unit) then
    local order=orders[unit]
    table.insert(candidates,{unit=unit,distance=(position(unit)-rawPosition).Magnitude,idle=order==nil,building=order~=nil and order.kind=="build"})
   end
  end
  local picked=AutoWorkRules.pickBuilders(candidates,count,Config.AutoWork.busyPenalty)
  if #picked>0 then builders,autoAssigned=picked,true end
 end
 if not builders and not quiet then notify(state.actor,"先選取自己的村民才能建造；軍隊不能施工。") end
 return builders,autoAssigned
end
-- 扣款並建立一個工地；失敗不扣款。回傳模型，或 nil 與原因（"blocked"／"cost"／"model"）。
Walls.site=function(state,kind,data,pos,size,rotated)
 if not Grid.inBounds(pos,size) then return nil,"blocked" end
 local replaced
 if data.gate then
  replaced=Walls.replaceable(state,pos,data,size)
  if not replaced then return nil,"blocked" end
 elseif not placementClear(pos,data,size) then return nil,"blocked" end
 if not Economy.spend(state.actor,data.cost) then return nil,"cost" end
 -- 先拆除被城門取代的牆段，城門才不會與它們重疊；不退還牆段的資源。
 for _,wall in ipairs(replaced or {}) do destroyModel(wall) end
 local ok,model=pcall(makeBuilding,state,kind,pos,false,rotated)
 if not ok then
  refund(state.actor,data.cost)
  warn("[RTS] 建築生成失敗："..tostring(model))
  return nil,"model"
 end
 construction[model]={state=state,duration=data.buildTime or 12,work=0}
 recordReport(state,"spend",{cost=data.cost})
 return model
end
local function buildRequest(state,kind,rawPosition,selection,quiet,rotated)
 local data=type(kind)=="string" and Config.Buildings[kind]
 if not data or not validPosition(rawPosition) or not alive(state) then return false end
 rotated=data.rotatable==true and rotated==true
 local size=Vector2.new(Walls.rules.footprint(data.size.X,data.size.Y,rotated))
 local builders,autoAssigned=Walls.builders(state,rawPosition,selection,AutoWorkRules.builderCount(size.X,size.Y,Config.Construction.maxSelectedWorkers),quiet)
 if not builders then return false end
 if (state.actor:GetAttribute("Age") or 1)<(data.minAge or 1) then if not quiet then notify(state.actor,"需先升級時代才能建造"..data.name.."。") end; return false end
 local model,reason=Walls.site(state,kind,data,Grid.snap(rawPosition,size),size,rotated)
 if not model then
  if not quiet then
   if reason=="cost" then notify(state.actor,"資源不足："..Grid.costText(data.cost),"Error")
   elseif reason=="model" then notify(state.actor,"建築模型載入失敗，已退還資源。")
   else notify(state.actor,"此處有障礙物或超出地圖。","Error") end
  end
  return false
 end
 for _,builder in ipairs(builders) do issue(builder,"build",model) end
 if not quiet then notify(state.actor,data.name..(autoAssigned and (" 工地已建立；已派最近的 "..#builders.." 位村民前往施工。") or " 工地已建立；選中的村民正前往施工。"),"Build") end
 return true,model
end
-- 整排城牆：伺服器自行由起訖格算出牆段，逐段驗證占地與扣款；被擋住的格子跳過，資源用完即停。
Walls.lineRequest=function(state,kind,rawFrom,rawTo,selection)
 local data=type(kind)=="string" and Config.Buildings[kind]
 if not data or data.line~=true or not validPosition(rawFrom) or not validPosition(rawTo) or not alive(state) then return false end
 local _,fromX,fromZ=Grid.snap(rawFrom,data.size)
 local _,toX,toZ=Grid.snap(rawTo,data.size)
 local cells=Walls.rules.line(fromX,fromZ,toX,toZ,Walls.config.maxLine)
 if not cells then return false end
 local builders,autoAssigned=Walls.builders(state,rawFrom,selection,math.clamp(math.ceil(#cells/6),1,3),false)
 if not builders then return false end
 if (state.actor:GetAttribute("Age") or 1)<(data.minAge or 1) then notify(state.actor,"需先升級時代才能建造"..data.name.."。"); return false end
 local sites,short={},false
 for _,cell in ipairs(cells) do
  local model,reason=Walls.site(state,kind,data,Grid.cellPosition(cell.x,cell.z,data.size),data.size,false)
  if model then table.insert(sites,model)
  elseif reason~="blocked" then short=reason=="cost"; break end
 end
 if #sites==0 then
  notify(state.actor,short and ("資源不足："..Grid.costText(data.cost)) or "此處有障礙物或超出地圖。","Error")
  return false
 end
 -- 村民從不同牆段開始，完工後依 buildQueue 接續同一排中最近的未完工牆段。
 for index,builder in ipairs(builders) do
  issue(builder,"build",sites[math.floor((index-1)*#sites/#builders)+1])
  orders[builder].buildQueue=sites
 end
 notify(state.actor,data.name.." × "..#sites.." 工地已建立"..(short and "（資源不足，其餘未放置）" or "")
  ..(autoAssigned and ("；已派最近的 "..#builders.." 位村民前往施工。") or "；選中的村民正前往施工。"),"Build")
 return true,sites
end
-- 同一排中離村民最近、仍在施工的牆段。
Walls.nextSite=function(unit,queue)
 local nearest,distance=nil,math.huge
 local current=position(unit)
 for _,site in ipairs(queue or {}) do
  if site.Parent==buildings and construction[site] and not site:GetAttribute("Complete") then
   local d=(position(site)-current).Magnitude
   if d<distance then nearest,distance=site,d end
  end
 end
 return nearest
end
local function canTrain(buildingKind,unitKind)
 local data=Config.Buildings[buildingKind]
 for _,kind in ipairs(data and data.trains or {}) do if kind==unitKind then return true end end
 return false
end
local function queueAttributes(building)
 local queue=training[building]
 local names={}
 -- 佇列名稱沿用該陣營的兵種升級名稱。
 for _,item in ipairs(queue or {}) do table.insert(names,item.state and item.state.unitNames[item.kind] or Config.Units[item.kind].name) end
 for index=1,5 do building:SetAttribute("QueueKind_"..index,queue and queue[index] and queue[index].kind or nil) end
 building:SetAttribute("QueueCount",#names)
 building:SetAttribute("Queue",table.concat(names,"、"))
 local item=queue and queue[1]
 building:SetAttribute("Training",item and names[1] or nil)
 building:SetAttribute("TrainingRemaining",item and math.ceil(math.max(0,item.remaining)) or nil)
 building:SetAttribute("TrainingProgress",item and math.clamp(1-item.remaining/item.duration,0,1) or nil)
end
local function trainRequest(state,building,kind,quiet)
 if not alive(state) or not isOwned(state,building,buildings) or type(kind)~="string" then return false end
 local data=Config.Units[kind]
 if not data or not canTrain(building:GetAttribute("BuildingType"),kind) then return false end
 if not building:GetAttribute("Complete") then if not quiet then notify(state.actor,"建築尚未完工。") end; return false end
 if (state.actor:GetAttribute("Age") or 1)<(data.minAge or 1) then if not quiet then notify(state.actor,"此單位尚未解鎖，請先升級時代。") end; return false end
 if researching[building] or (state.advancing and state.advancing.building==building) then if not quiet then notify(state.actor,"此建築正在研究。") end; return false end
 local queue=training[building] or {}
 if #queue>=5 then if not quiet then notify(state.actor,"訓練佇列最多五個單位。") end; return false end
 local count,cap=population(state)
 if count>=cap then if not quiet then notify(state.actor,"人口已滿，請建造房屋。","Error") end; return false end
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"訓練所需資源不足。","Error") end; return false end
 local duration=data.trainTime*math.max(0.4,1-state.modifiers.trainSpeed)
 local item={kind=kind,state=state,remaining=duration,duration=duration,cost=table.clone(data.cost)}
 table.insert(queue,item)
 training[building]=queue
 building:SetAttribute("QueueRevision",(building:GetAttribute("QueueRevision") or 0)+1)
 item.reportReceipt=recordReport(state,"spend",{cost=data.cost,refundable=true})
 queueAttributes(building)
 population(state)
 return true
end
local function cancelTrainingRequest(state,building,index,revision)
 if not alive(state) or not isOwned(state,building,buildings) then return false end
 local item,nextRevision=ProductionRules.cancelTraining(training[building],index,revision,building:GetAttribute("QueueRevision"))
 if not item then notify(state.actor,"訓練佇列已更新，請重新點選要取消的單位。"); return false end
 if #training[building]==0 then training[building]=nil end
 building:SetAttribute("QueueRevision",nextRevision)
 refund(state.actor,item.cost)
 if item.reportReceipt then recordReport(state,"refund",{spendId=item.reportReceipt}) end
 queueAttributes(building)
 population(state)
 notify(state.actor,"已取消"..(state.unitNames[item.kind] or Config.Units[item.kind].name).."訓練，退回全部資源。")
 return true
end
local function rallyResource(state,target)
 if not isTarget(target) or (target.Parent~=resources and not isOwned(state,target,buildings)) then return false end
 return ProductionRules.canRallyResource(target:GetAttribute("ResourceType"),target:GetAttribute("Amount"),target:GetAttribute("OwnerId"),state.id,
  target.Parent==resources or target:GetAttribute("Complete")==true)
end
local function rallyRequest(state,building,target)
 if not alive(state) or not isOwned(state,building,buildings) then return false end
 local data=Config.Buildings[building:GetAttribute("BuildingType")]
 if not ProductionRules.canRallyBuilding(data,true,building:GetAttribute("Complete")) then return false end
 if target==nil then
  state.rallies[building]=nil
  building:SetAttribute("RallyPosition",nil)
  building:SetAttribute("RallyType",nil)
  building:SetAttribute("RallyTargetName",nil)
  notify(state.actor,"已清除集合點。")
  return true
 end
 local isResource=rallyResource(state,target)
 local goal=isResource and position(target) or target
 if not validPosition(goal) then notify(state.actor,"集合點必須位於地圖內，或指向仍可採集的中立／自己資源。"); return false end
 goal=Vector3.new(goal.X,Config.Map.GroundY,goal.Z)
 state.rallies[building]={position=goal,target=isResource and target or nil,resourceType=isResource and target:GetAttribute("ResourceType") or nil}
 building:SetAttribute("RallyPosition",goal)
 building:SetAttribute("RallyType",isResource and "gather" or "move")
 building:SetAttribute("RallyTargetName",isResource and target:GetAttribute("DisplayName") or "地面")
 notify(state.actor,isResource and "已設定資源集合點；新村民會前往採集。" or "已設定集合點；新單位會前往集合。","Order")
 return true
end
local function completedBuilding(state,kind)
 for b in pairs(state.buildings) do if b.Parent==buildings and b:GetAttribute("BuildingType")==kind and b:GetAttribute("Complete") then return b end end
 return nil
end
local function ageRequirements(state,data)
 local requirements=data.requirements or {}
 if requirements.castleAlternative and completedBuilding(state,requirements.castleAlternative) then return true end
 if requirements.castleOrBuildings and completedBuilding(state,"Castle") then return true end
 if requirements.types then for _,kind in ipairs(requirements.types) do if not completedBuilding(state,kind) then return false end end end
 if requirements.buildings then
  local kinds,count={},0
  local age=state.actor:GetAttribute("Age") or 1
  for b in pairs(state.buildings) do
   local kind=b:GetAttribute("BuildingType")
   local info=Config.Buildings[kind]
   if b.Parent==buildings and b:GetAttribute("Complete") and info and kind~="TownCenter" and kind~="House" and kind~="Farm" and kind~="Wall" and kind~="Gate" and kind~="Tower" and kind~="Castle" and (info.minAge or 1)==age and not kinds[kind] then kinds[kind],count=true,count+1 end
  end
  if count<requirements.buildings then return false end
 end
 return true
end
local function advanceRequest(state,building,quiet)
 if not alive(state) or not isOwned(state,building,buildings) or not building:GetAttribute("Complete") then return false end
 local kind,age=building:GetAttribute("BuildingType"),state.actor:GetAttribute("Age") or 1
 if kind~="TownCenter" and kind~="Castle" then return false end
 local data=Config.Ages[age+1]
 if not data or state.advancing then return false end
 if researching[building] or (training[building] and #training[building]>0) then if not quiet then notify(state.actor,"請先完成此建築的訓練或研究。") end; return false end
 if not ageRequirements(state,data) then if not quiet then notify(state.actor,"升級前需完成目前時代的兩種經濟或軍事建築；帝王時代也可使用城堡。") end; return false end
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"升級時代所需資源不足："..Grid.costText(data.cost),"Error") end; return false end
 state.advancing={building=building,age=age+1,remaining=data.time,duration=data.time,cost=data.cost}
 recordReport(state,"spend",{cost=data.cost})
 state.actor:SetAttribute("AgeProgress",0)
 state.actor:SetAttribute("AgeRemaining",data.time)
 building:SetAttribute("Research",data.name)
 building:SetAttribute("ResearchProgress",0)
 building:SetAttribute("ResearchRemaining",data.time)
 if not quiet then notify(state.actor,"開始升級至"..data.name.."。") end
 return true
end
local function techBuilding(data,kind)
 if type(data.building)=="table" then for _,candidate in ipairs(data.building) do if candidate==kind then return true end end; return false end
 return data.building==kind
end
local function researchRequest(state,building,key,quiet)
 local data=type(key)=="string" and Config.Technologies[key]
 if not data or not alive(state) or not isOwned(state,building,buildings) or not building:GetAttribute("Complete") then return false end
 if not techBuilding(data,building:GetAttribute("BuildingType")) then return false end
 if not ProductionRules.canResearch(state.technologies,state.pendingTech,key,state.actor:GetAttribute("Age") or 1,data.minAge or 1) then return false end
 if researching[building] or (training[building] and #training[building]>0) or (state.advancing and state.advancing.building==building) then if not quiet then notify(state.actor,"此建築的佇列尚未完成。") end; return false end
 if data.requires and not state.technologies[data.requires] then if not quiet then notify(state.actor,"需先研究前置科技。") end; return false end
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"研究所需資源不足。","Error") end; return false end
 researching[building]={state=state,key=key,remaining=data.time,duration=data.time}
 state.pendingTech[key]=true
 recordReport(state,"spend",{cost=data.cost})
 building:SetAttribute("Research",data.name)
 building:SetAttribute("ResearchProgress",0)
 building:SetAttribute("ResearchRemaining",data.time)
 return true
end
local function cancelResearch(building,state)
 if ProductionRules.cancelResearch(state,building,researching) then
  state.actor:SetAttribute("AgeProgress",0)
  state.actor:SetAttribute("AgeRemaining",0)
 end
end
destroyModel=function(model)
 actionClocks[model]=nil
 unitCollisionIndex:Remove(model)
 local state=owner(model)
 if state then
  state.buildRetryAfter[model]=nil
  for _,retries in pairs(state.buildRetryAfter) do retries[model]=nil end
 end
 if model.Parent==units then orders[model]=nil; if state then state.units[model]=nil end
 elseif model.Parent==buildings then training[model],construction[model],Garrison.inside[model]=nil,nil,nil; if state then state.buildings[model]=nil; cancelResearch(model,state); state.defenseLast[model]=nil end end
 if state and state.rallies then state.rallies[model]=nil end
 -- 聖物不會消失：攜帶的僧侶或存放的修道院被移除時掉落在原地。
 if phase=="Playing" then Relic.release(model) end
 model:Destroy()
 if state then population(state) end
end
local function endMatch(winnerTeam)
 if phase~="Playing" then return end
 if not matchTeams or not TeamRules.result(matchTeams,matchTeams.memberIds[1],winnerTeam,true,false) then return end
 setPhase("Ended")
 if activeRoomId then
  workspace:SetAttribute("LobbyRoom_"..activeRoomId.."_Status","Ended")
  local room=rooms[activeRoomId]
  lobbyWorld:SetStatus(0,room.expected,0,"Ended",activeRoomId,room.settings)
 end
 local endedAt=os.clock()
 if currentMatch then
  for _,state in pairs(currentMatch.factions) do
   local outcome=TeamRules.result(matchTeams,state.id,winnerTeam,true,state.forfeited==true)
   finishReport(state,outcome,endedAt)
   recordMatchResult(state,outcome)
   -- 劇情勝利記錄通關章節；投降或淘汰的玩家不算。
   if outcome=="win" and not state.ai and settings.gameMode=="Story" and state.actor.Parent==Players
    and profiles:CompleteStory(state.actor,settings.storyChapter) then
    local nextChapter=LobbyRules.GameModes.chapter(settings.storyChapter+1)
    notify(state.actor,nextChapter and ("已解鎖第 "..(settings.storyChapter+1).." 章「"..nextChapter.title.."」。") or "恭喜完成全部劇情章節！")
   end
  end
  for _,state in pairs(currentMatch.participants) do
   if state.actor.Parent==Players then telemetry:Match(state.actor,"Completed",os.clock()-matchStart,matchContext(state)) end
  end
 end
 local winnerId,winnerName=0,"無"
 if winnerTeam then
  winnerName=teamName(winnerTeam)
  if settings.teamMode=="FFA" then
   winnerId=matchTeams.teamMembers[winnerTeam][1]
   local winner=currentMatch and currentMatch.factions[winnerId]
   winnerName=winner and actorName(winner.actor) or winnerName
  end
 end
 workspace:SetAttribute("Winner",winnerName)
 workspace:SetAttribute("WinnerId",winnerId)
 workspace:SetAttribute("WinnerTeamId",winnerTeam or 0)
 for unit in pairs(orders) do stop(unit) end
 if Travel.role=="Match" then
  -- 每場對局獨佔一台伺服器：結束後送回大廳，空伺服器由 Roblox 自動關閉。
  local delay=Config.Places.returnDelay
  announce((winnerTeam and (winnerName.." 獲得勝利！") or "對局結束。").."可按「返回大廳」，"..delay.." 秒後自動返回。")
  local generation=matchGeneration
  task.delay(delay,function() if matchGeneration==generation then Travel.returnAll("對局已結束，正在返回大廳…") end end)
 else
  announce(winnerTeam and (winnerName.." 獲得勝利！房主可返回大廳開始新局。") or "對局結束。房主可返回大廳。")
 end
 for actor,state in pairs(states) do
  if actor:IsA("Player") and not state.inLobby then
   local outcome=currentMatch and TeamRules.isParticipant(matchTeams,currentMatch.factions,state)
    and TeamRules.result(matchTeams,state.id,winnerTeam,true,state.forfeited==true) or nil
   notify(actor,nil,outcome=="win" and "Victory" or outcome=="loss" and "Defeat" or "MatchEnd")
  end
 end
end
checkVictory=function()
 if phase~="Playing" then return end
 local survivors={}
 for _,state in pairs(states) do
  if alive(state) and currentMatch and TeamRules.isParticipant(matchTeams,currentMatch.factions,state) then table.insert(survivors,state.id) end
 end
 local winnerTeam,ended=TeamRules.winner(matchTeams,survivors)
 if ended then endMatch(winnerTeam) end
end
defeat=function(state,reason,forfeit)
 if phase~="Playing" or not state or not state.playing or not currentMatch
  or not TeamRules.isParticipant(matchTeams,currentMatch.factions,state) then return end
 local now=os.clock()
 -- A naturally eliminated observer can still leave; settle before ProfileStore.Close.
 if forfeit==true and not state.forfeited then
  state.forfeited=true
  state.actor:SetAttribute("Forfeited",true)
  local outcome=TeamRules.result(matchTeams,state.id,nil,false,true)
  finishReport(state,outcome,now)
  recordMatchResult(state,outcome)
 end
 if not alive(state) then return end
 if not state.forfeited then freezeReport(state,now) end
 state.defeated=true
 state.actor:SetAttribute("Defeated",true)
 state.actor:SetAttribute("AgeRemaining",0)
 for unit in pairs(state.units) do destroyModel(unit) end
 for building in pairs(state.buildings) do destroyModel(building) end
 state.units,state.buildings={},{}
 state.pendingTech,state.wonderTimes={},{}
 population(state)
 state.advancing=nil
 notify(state.actor,reason or "你的勢力已被淘汰，可繼續觀戰並等待對局結果。",state.forfeited and "Defeat" or nil)
 announce(actorName(state.actor)..(state.forfeited and " 已投降。" or " 的勢力已被淘汰。"))
 checkVictory()
end
local function eliminationCheck(state)
 if not alive(state) then return end
 if settings.victory=="Regicide" then
  local main=false
  for b in pairs(state.buildings) do if b.Parent==buildings and b:GetAttribute("MainBase") then main=true; break end end
  if not main then defeat(state,"主城被摧毀，你的勢力已淘汰，可觀戰並等待對局結果。") end
 elseif next(state.units)==nil and next(state.buildings)==nil then defeat(state,"全部單位與建築已被摧毀，你的勢力已淘汰，可觀戰並等待對局結果。") end
end
local function damage(target,raw,attacker,now)
 if phase~="Playing" then return end
 local victim=owner(target)
 if not victim or not target.Parent or not attacker or not attacker.Parent then return end
 local source=owner(attacker)
 if not enemies(source,victim) then return end
 local amount=math.max(1,raw-(target:GetAttribute("Armor") or 0))
 local beforeHP=target:GetAttribute("HP") or 0
 target:SetAttribute("HP",math.max(0,beforeHP-amount))
 local afterHP=target:GetAttribute("HP") or 0
 if afterHP<beforeHP then recordReport(source,"damage",{beforeHP=beforeHP,afterHP=afterHP}) end
 if afterHP<=0 then
  if beforeHP>0 then
   local category=target.Parent==units and "unit" or "building"
   local subjectId=reportSubject(target)
   recordReport(source,"kill",{subjectId=subjectId,category=category})
   recordReport(victim,"loss",{subjectId=subjectId,category=category})
  end
  -- 戰死的單位留下屍體；投降、刪除與清場不留。
  if target.Parent==units then Factory.corpse(target,COMBAT.corpseSeconds,COMBAT.maxCorpses) end
  -- 被摧毀的建築先放出駐軍，再判定淘汰。
  Garrison.release(target)
  eliminationCheck(victim)
 elseif target.Parent==units and ((Config.Units[target:GetAttribute("UnitType")] or {}).damage or 0)>0 and CombatRules.canRetaliate(orders[target] and orders[target].kind,enemies(victim,owner(attacker)),
  attacker.Parent==buildings,target:GetAttribute("UnitType")=="villager") then
  local previous=orders[target]
  issue(target,"attack",attacker,true)
  -- 反擊從受擊位置起算追擊距離，避免被風箏到地圖另一端。
  orders[target].anchor=position(target)
  if previous and previous.kind=="gather" then
   orders[target].resumeGather=previous.target
   orders[target].resumeKind=previous.target:GetAttribute("ResourceType")
  end
 end
end
-- 命中結算集中在一個表，避免超過 Studio 的 200 個區域變數上限。
local Strike={}
Strike.amount=function(state,unit,target)
 local data=Config.Units[unit:GetAttribute("UnitType")]
 local targetKind=target:GetAttribute("UnitType")
 local targetData=target.Parent~=buildings and Config.Units[targetKind]
 local class=target.Parent==buildings and "building" or (targetData and targetData.class or targetKind)
 local extra=(state.unitModifiers[unit:GetAttribute("UnitType")] or {}).bonus
 return unitStats(state,unit:GetAttribute("UnitType")).damage+CombatRules.counterBonus(data.bonus,extra,class,targetData and targetData.alsoClass)
end
-- 傷害在武器揮到或投射物飛抵時才結算；期間攻擊者消失、換局或對局結束就不再命中。
Strike.land=function(attacker,delay,resolve)
 local generation=matchGeneration
 task.delay(delay,function()
  if phase~="Playing" or generation~=matchGeneration or not attacker.Parent then return end
  resolve(os.clock())
 end)
end
Strike.flight=function(kind,distance)
 local settings=COMBAT.projectile
 return CombatRules.flightTime(distance,settings[COMBAT.projectileKinds[kind] or "arrow"],settings.minFlight,settings.maxFlight) or settings.minFlight
end
local function freeSpawn(building,kind)
 local origin=position(building)
 local half=building.PrimaryPart and building.PrimaryPart.Size/2 or Vector3.new(16,8,16)
 local profile=Config.UnitCollision.profiles[Config.Units[kind].class] or Config.UnitCollision.default
 local radius,height=profile.radius,profile.height
 for ring=1,3 do
  for index=0,15 do
   local angle=index*math.pi/8
   local spawnRadius=math.max(half.X,half.Z)+radius+2+ring*4
   local candidate=origin+Vector3.new(math.cos(angle)*spawnRadius,0,math.sin(angle)*spawnRadius)
   if unitInBounds(candidate,radius) and unitPositionClear(nil,candidate,radius)
    and #obstacleParts(candidate+Vector3.new(0,height/2,0),Vector3.new(radius*2,height,radius*2))==0 then return candidate end
  end
 end
 return nil
end
local function applyRally(state,building,unit,kind)
 local rally=state.rallies[building]
 if not rally then return end
 local target=rally.target
 if rally.resourceType and not rallyResource(state,target) then
  target=nearestResource(state,rally.position,rally.resourceType,unit)
 end
 if kind=="villager" and rallyResource(state,target) then
  issue(unit,"gather",target)
 elseif rallyResource(state,target) then
  -- Military can gather beside a resource; never route them into its collision box.
  local goal=freeSpawn(target,kind)
  if goal then issue(unit,"move",goal) end
 elseif validPosition(rally.position) then
  issue(unit,"move",rally.position)
 end
end
-- 同一批單位被拒絕時只通知一次。
Garrison.notice=function(state,message)
 -- 依訊息分開節流：不同原因不會互相蓋掉。
 local now=os.clock()
 local sent=state.garrisonNotice or {}
 state.garrisonNotice=sent
 if now-(sent[message] or -math.huge)<1 then return end
 sent[message]=now
 notify(state.actor,message,"Error")
end
Garrison.check=function(building,unit)
 local held=Garrison.inside[building]
 local data=Config.Units[unit:GetAttribute("UnitType")]
 -- 駐軍紀錄不保存聖物；攜帶者必須先把聖物存放到修道院。
 if unit:GetAttribute("CarryingRelic")==true then return false,"攜帶聖物的僧侶不能駐紮；先把聖物存放到修道院。" end
 return Garrison.rules.canEnter(Garrison.config,Config.Buildings[building:GetAttribute("BuildingType")],building:GetAttribute("Complete"),
  held and #held or 0,data and data.class,unit:GetAttribute("HP"))
end
-- 駐紮指令：只收自己已完工、仍有空位的建築。quiet 供一般右鍵使用，不能駐紮時不打擾玩家。
Garrison.order=function(state,unit,building,quiet)
 if not isOwned(state,building,buildings) then return false end
 local ok,reason=Garrison.check(building,unit)
 if not ok then
  if not quiet then Garrison.notice(state,reason) end
  return false
 end
 issue(unit,"garrison",building)
 return true
end
-- 單位走到建築旁時呼叫：途中建築可能已滿，再檢查一次。
Garrison.enter=function(state,unit,building)
 local ok,reason=Garrison.check(building,unit)
 if not ok then stop(unit); Garrison.notice(state,reason); return end
 local held=Garrison.inside[building] or {arrows=0}
 table.insert(held,{kind=unit:GetAttribute("UnitType"),hp=unit:GetAttribute("HP"),carrying=unit:GetAttribute("Carrying") or 0,
  carryType=unit:GetAttribute("CarryType") or "",faith=unit:GetAttribute("Faith"),formation=unit:GetAttribute("Formation")})
 Garrison.inside[building]=held
 AutoWork.units[unit]=nil
 destroyModel(unit)
 Garrison.publish(building)
end
Garrison.spawn=function(state,record,pos)
 local ok,model=pcall(makeUnit,state,record.kind,pos)
 if not ok then warn("[RTS] 駐軍離開時單位生成失敗："..tostring(model)); return nil end
 model:SetAttribute("HP",Garrison.rules.restoreHP(record.hp,model:GetAttribute("MaxHP")))
 if record.carrying>0 then model:SetAttribute("CarryType",record.carryType); model:SetAttribute("Carrying",record.carrying) end
 if record.faith then model:SetAttribute("Faith",record.faith) end
 if record.formation then model:SetAttribute("Formation",record.formation) end
 return model
end
-- 玩家下令全部離開：逐一找建築周圍的空位，沒有空位的留在裡面。回傳離開的人數。
Garrison.eject=function(state,building)
 local held=Garrison.inside[building]
 if not held then return 0 end
 local left=0
 while #held>0 do
  local record=held[#held]
  local spot=freeSpawn(building,record.kind)
  if not spot then break end
  -- 先移出紀錄再生成，人口不會短暫重複計算。
  held[#held]=nil
  local model=Garrison.spawn(state,record,spot)
  if not model then table.insert(held,record); break end
  left+=1
  applyRally(state,building,model,record.kind)
 end
 if #held==0 then Garrison.inside[building]=nil end
 Garrison.publish(building)
 population(state)
 return left
end
-- 建築被摧毀或拆除：先移除建築，駐軍出現在原本的占地內；沒有駐軍時等同 destroyModel。
Garrison.release=function(building)
 local held=building.Parent==buildings and Garrison.inside[building]
 local state=owner(building)
 if not held or #held==0 or not alive(state) then destroyModel(building); return end
 local origin=position(building)
 local half=building.PrimaryPart and building.PrimaryPart.Size/2 or Vector3.new(8,8,8)
 destroyModel(building)
 -- 候選位置：先排滿原占地，小建築（瞭望塔）放不下時再往外三圈；每個位置只用一次。
 local spots,used={},{}
 local margin=Config.UnitCollision.default.radius
 for x=-half.X+margin,half.X-margin,5 do
  for z=-half.Z+margin,half.Z-margin,5 do table.insert(spots,origin+Vector3.new(x,0,z)) end
 end
 for ring=1,3 do
  local radius=math.max(half.X,half.Z)+margin+ring*6
  local count=math.max(8,math.floor(radius*2*math.pi/6))
  for index=0,count-1 do
   local angle=index*2*math.pi/count
   table.insert(spots,origin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
  end
 end
 for _,record in ipairs(held) do
  local profile=Config.UnitCollision.profiles[Config.Units[record.kind].class] or Config.UnitCollision.default
  local radius,height=profile.radius,profile.height
  local spot=origin
  for index,candidate in ipairs(spots) do
   if not used[index] and unitInBounds(candidate,radius) and unitPositionClear(nil,candidate,radius)
    and #obstacleParts(candidate+Vector3.new(0,height/2,0),Vector3.new(radius*2,height,radius*2))==0 then
    used[index]=true
    spot=candidate
    break
   end
  end
  Garrison.spawn(state,record,spot)
 end
end
Garrison.heal=function(state,dt)
 for building in pairs(state.buildings) do
  local held=Garrison.inside[building]
  if held then
   for _,record in ipairs(held) do record.hp=Garrison.rules.heal(record.hp,unitStats(state,record.kind).hp,Garrison.config.healRate,dt) end
  end
 end
end
local function resetActor(state)
 clearReport(state)
 state.civilization=CivilizationRules.resolve(Config,state.civilization)
 publishCivilization(state,state.actor)
 state.units,state.buildings,state.technologies,state.pendingTech,state.defenseLast={},{},{},{},{}
 state.modifiers={attack=0,armor=0,hp=0,gather=0,carry=0,speed=0,gatherFood=0,gatherWood=0,gatherGold=0,gatherStone=0,farmCapacity=0,range=0,interval=0,trainSpeed=0}
 state.classModifiers={}
 state.unitModifiers,state.unitNames={},{}
 Relic.accumulated[state]=nil
 for _,key in ipairs({"Relics","RelicGold","TradeIncome"}) do state.actor:SetAttribute(key,0) end
 state.actor:SetAttribute("RelicRemaining",nil)
 for kind in pairs(Config.Units) do state.actor:SetAttribute("UnitName_"..kind,nil) end
 state.statsCache=nil
 state.buildRetryAfter={}
 state.rallies={}
 state.playing,state.defeated,state.advancing,state.forfeited=false,false,nil,false
 state.actor:SetAttribute("Forfeited",false)
 state.actor:SetAttribute("TeamId",nil)
 state.actor:SetAttribute("TeamName",nil)
 state.actor:SetAttribute("LobbyTeamId",nil)
 state.wonderTimes={}
 state.actor:SetAttribute("WonderRemaining",nil)
 state.actor:SetAttribute("Defeated",false)
 state.actor:SetAttribute("Age",1)
 state.actor:SetAttribute("AgeProgress",0)
 state.actor:SetAttribute("AgeRemaining",0)
 state.actor:SetAttribute("Population",0)
 state.actor:SetAttribute("PopulationCap",0)
 state.actor:SetAttribute("DeliveredResources",0)
 state.actor:SetAttribute("TrainedUnits",0)
 state.actor:SetAttribute("TrainedVillagers",0)
 for key in pairs(Config.Technologies) do state.actor:SetAttribute("Tech_"..key,nil) end
 for _,key in ipairs({"food","wood","gold","stone"}) do state.actor:SetAttribute(key,0) end
 state.actor:SetAttribute("FarmQueue",0)
 state.farmReceipts={}
end
local function humanStates()
 local humans={}
 for actor,state in pairs(states) do if actor:IsA("Player") and actor.Parent==Players then table.insert(humans,state) end end
 table.sort(humans,function(a,b) return a.joined<b.joined end)
 return humans
end
local function queuedStates(roomId)
 local members={}
 for _,state in ipairs(humanStates()) do
  if state.queued and state.roomId==(roomId or "Room1") and not state.playing then table.insert(members,state) end
 end
 table.sort(members,function(a,b) return a.queueOrder<b.queueOrder end)
 return members
end
local function roomPrefix(room,key)
 return "LobbyRoom_"..room.id.."_"..key
end
local function publishLobbySettings(room)
 if not room then for _,entry in pairs(rooms) do publishLobbySettings(entry) end; return end
 workspace:SetAttribute(roomPrefix(room,"ExpectedPlayers"),room.expected)
 workspace:SetAttribute(roomPrefix(room,"SettingsRevision"),room.revision)
 workspace:SetAttribute(roomPrefix(room,"Configured"),room.configured==true)
 for key,value in pairs(room.settings) do workspace:SetAttribute(roomPrefix(room,"Setting_"..key),value) end
 if room.id=="Room1" then
  workspace:SetAttribute("LobbyExpectedPlayers",room.expected)
  for key,value in pairs(room.settings) do workspace:SetAttribute("LobbySetting_"..key,value) end
  workspace:SetAttribute("LobbySettingsRevision",room.revision)
 end
end
local function resetRoomDefaults(room)
 local portal=LobbyRules.room(Config.Lobby.portals,room.id)
 local defaults,count=LobbyRules.settings(portal.settings)
 room.settings,room.expected,room.configured,room.hadMembers=defaults,count,false,false
 room.revision+=1
 publishLobbySettings(room)
end
local function invalidateReady(room)
 if not room then return end
 room.revision+=1
 for _,state in ipairs(humanStates()) do
  if state.roomId==room.id then
   state.ready=false
   state.actor:SetAttribute("LobbyReady",false)
  end
 end
 publishLobbySettings(room)
end
local function positionLobby(state,index,count)
 local character=state.actor.Character
 local root=character and character:FindFirstChild("HumanoidRootPart")
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 if not root or not humanoid then return end
 root.Anchored=state.queued==true
 humanoid.WalkSpeed=state.queued and 0 or 16
 humanoid.AutoRotate=not state.queued
 if state.queued then character:PivotTo(lobbyWorld:QueueCFrame(index,count,state.roomId)) end
end
local function publishLobbyTeamPreview(room,members)
 workspace:SetAttribute(roomPrefix(room,"TeamPreviewReady"),false)
 for _,state in ipairs(members) do state.actor:SetAttribute("LobbyTeamId",nil) end
 for index=1,3 do workspace:SetAttribute(roomPrefix(room,"AITeam_"..index),nil) end
 if room.id=="Room1" then
  workspace:SetAttribute("LobbyTeamPreviewReady",false)
  for index=1,3 do workspace:SetAttribute("LobbyAITeam_"..index,nil) end
 end
 local aiIds=plannedAIIds(room.settings.aiCount)
 local preview=LobbyRules.teamPreview(room.settings.teamMode,room.expected,members,aiIds)
 if not preview then return end
 for _,state in ipairs(members) do state.actor:SetAttribute("LobbyTeamId",TeamRules.team(preview,state.id)) end
 for index,id in ipairs(aiIds) do
  workspace:SetAttribute(roomPrefix(room,"AITeam_"..index),TeamRules.team(preview,id))
  if room.id=="Room1" then workspace:SetAttribute("LobbyAITeam_"..index,TeamRules.team(preview,id)) end
 end
 workspace:SetAttribute(roomPrefix(room,"TeamPreviewReady"),true)
 if room.id=="Room1" then workspace:SetAttribute("LobbyTeamPreviewReady",true) end
end
local function updateHost()
 local humans=humanStates()
 for _,data in ipairs(Config.Lobby.portals) do
  local room=rooms[data.id]
  local members=queuedStates(room.id)
  if room.travel then
   -- 出發中的房間在最後一位成員離開伺服器（傳送成功）或全部恢復後解鎖。
   local travelling=false
   for _,state in ipairs(members) do if state.teleporting==room.travel.id then travelling=true; break end end
   if not travelling then room.travel=nil; workspace:SetAttribute(roomPrefix(room,"TravelStage"),nil) end
  end
  if #members==0 and room.hadMembers and activeRoomId~=room.id then resetRoomDefaults(room) end
  if #members>0 then room.hadMembers=true end
  local ready=0
  local host=members[1] and members[1].id or 0
  local status=activeRoomId==room.id and phase or (room.travel and "Starting") or (room.configured and "Waiting" or "Configuring")
  workspace:SetAttribute(roomPrefix(room,"HostUserId"),host)
  workspace:SetAttribute(roomPrefix(room,"Players"),#members)
  workspace:SetAttribute(roomPrefix(room,"Status"),status)
  for index,state in ipairs(members) do
   state.actor:SetAttribute("TeamColor",colors[index])
   state.actor:SetAttribute("LobbyJoinOrder",state.queueOrder)
   positionLobby(state,index,#members)
   if state.ready then ready+=1 end
  end
  workspace:SetAttribute(roomPrefix(room,"ReadyPlayers"),ready)
  publishLobbyTeamPreview(room,members)
  lobbyWorld:SetStatus(#members,room.expected,ready,status,room.id,room.settings)
  if room.id=="Room1" then
   workspace:SetAttribute("LobbyPlayers",#members)
   if phase=="Lobby" then workspace:SetAttribute("HostUserId",host) end
  end
 end
 if phase~="Lobby" then
  workspace:SetAttribute("HostUserId",LobbyRules.matchHost(workspace:GetAttribute("HostUserId"),humans))
 end
 if phase=="Lobby" and autoStartLobby then task.defer(autoStartLobby) end
end
local function clearLobbyCharacter(state)
 state.characterGeneration=(state.characterGeneration or 0)+1
 if state.deathConnection then state.deathConnection:Disconnect(); state.deathConnection=nil end
 local character=state.actor.Character
 if character then character:Destroy(); state.actor.Character=nil end
end
spawnLobby=function(state)
 if not state.inLobby or state.playing or state.actor.Parent~=Players or state.loadingCharacter then return end
 clearLobbyCharacter(state)
 state.loadingCharacter=true
 local generation=state.characterGeneration
 task.spawn(function()
  local ok,err=pcall(function() state.actor:LoadCharacterAsync() end)
  state.loadingCharacter=false
  if state.actor.Parent~=Players or not state.inLobby or state.playing or generation~=state.characterGeneration then
   if state.actor.Character then state.actor.Character:Destroy(); state.actor.Character=nil end
   if state.inLobby and not state.playing and state.actor.Parent==Players then spawnLobby(state) end
   return
  end
  if not ok then warn("[RTS] 大廳角色載入失敗："..tostring(err)); notify(state.actor,"大廳角色載入失敗，請重新加入。"); return end
  local character=state.actor.Character
  local humanoid=character and character:FindFirstChildOfClass("Humanoid")
  if character and humanoid then
   character:PivotTo(lobbyWorld:SpawnCFrame())
   state.deathConnection=humanoid.Died:Connect(function()
    if state.inLobby and not state.playing then queueLeave(state); task.defer(spawnLobby,state) end
   end)
   updateHost()
  end
 end)
end
queueJoin=function(state,roomId,quiet,fromUI)
 if not state.inLobby or state.playing or os.clock()<(state.queueCooldown or 0) then return end
 local portal=LobbyRules.room(Config.Lobby.portals,roomId)
 if not portal then if not quiet then notify(state.actor,"這個匹配點不存在。") end; return end
 local room=rooms[portal.id]
 if activeRoomId==room.id then if not quiet then notify(state.actor,"這個匹配點正在對局，請先選其他匹配點。") end; return end
 if state.teleporting then return end
 if room.travel then if not quiet then notify(state.actor,"這個匹配點的隊伍正在出發，請稍候或選其他匹配點。") end; return end
 if state.queued and state.roomId==room.id then return end
 local character=state.actor.Character
 local root=character and character:FindFirstChild("HumanoidRootPart")
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 if not root or not humanoid or humanoid.Health<=0 then if not quiet then notify(state.actor,"大廳角色尚未準備好，請稍候再試。") end; return end
 if not fromUI and not lobbyWorld:NearPortal(state.actor,room.id) then if not quiet then notify(state.actor,"請走到所選匹配點，或使用房間卡片加入。") end; return end
 if #queuedStates(room.id)>=room.expected then if not quiet then notify(state.actor,"這個匹配點人數已滿，請選其他匹配點。") end; return end
 local previous=state.roomId and rooms[state.roomId]
 joinSequence+=1
 state.queued,state.ready,state.queueOrder,state.roomId=true,false,joinSequence,room.id
 state.actor:SetAttribute("LobbyQueued",true)
 state.actor:SetAttribute("LobbyRoomId",room.id)
 telemetry:Fact(state.actor,"queue")
 if previous then invalidateReady(previous) end
 invalidateReady(room)
 updateHost()
end
queueLeave=function(state)
 if not state.inLobby or state.playing or not state.queued or state.teleporting then return end
 local room=rooms[state.roomId]
 state.queued,state.ready,state.roomId=false,false,nil
 state.queueCooldown=os.clock()+2
 state.actor:SetAttribute("LobbyQueued",false)
 state.actor:SetAttribute("LobbyReady",false)
 state.actor:SetAttribute("LobbyRoomId",nil)
 state.actor:SetAttribute("LobbyTeamId",nil)
 state.actor:SetAttribute("TutorialMatch",nil)
 positionLobby(state)
 if state.actor.Character then state.actor.Character:PivotTo(lobbyWorld:SpawnCFrame()) end
 invalidateReady(room)
 updateHost()
end
local function configureLobby(player,payload)
 local state=states[player]
 local room=state and state.roomId and rooms[state.roomId]
 if not room or not state.inLobby or state.playing or not state.queued or activeRoomId==room.id or room.travel
  or workspace:GetAttribute(roomPrefix(room,"HostUserId"))~=player.UserId then return end
 -- 劇情章節依房主的通關進度解鎖；StoryCleared 只由伺服器的個人檔案寫入。
 local validated,count=LobbyRules.settings(payload,{unlocked=LobbyRules.GameModes.unlocked(player:GetAttribute("StoryCleared"))})
 if not validated then notify(player,count); return end
 if count<#queuedStates(room.id) then notify(player,"參戰人數不能少於目前已集合的玩家。"); return end
 local nextTeams,message=TeamRules.changeSettings(
  {mode=room.settings.teamMode,humanCount=room.expected,aiCount=room.settings.aiCount},
  {mode=validated.teamMode,humanCount=count,aiCount=validated.aiCount},
  player.UserId,workspace:GetAttribute(roomPrefix(room,"HostUserId")),"Lobby")
 if not nextTeams then notify(player,message); return end
 room.settings,room.expected=validated,count
 room.configured=false
 invalidateReady(room)
 updateHost()
end
local function configureLobbyComplete(player,revision,rateRejected)
 local state=states[player]
 if not state then return end
 state.configureRejected=false
 local room=state.roomId and rooms[state.roomId]
 local accepted=false
 if room and state.inLobby and not state.playing and state.queued and activeRoomId~=room.id and not room.travel
  and workspace:GetAttribute(roomPrefix(room,"HostUserId"))==player.UserId
  and Rules.finite(revision) and revision%1==0 and revision==room.revision then
  local validated=Rules.settings(room.settings,room.expected)
  if validated and #queuedStates(room.id)<=room.expected then
   room.configured=true
   publishLobbySettings(room)
   updateHost()
   accepted=true
  end
 end
 state.configureAck=(state.configureAck or 0)+1
 player:SetAttribute("LobbyConfigureAccepted",accepted)
 player:SetAttribute("LobbyConfigureRoomId",room and room.id or nil)
 player:SetAttribute("LobbyConfigureAck",state.configureAck)
 if not accepted then notify(player,rateRejected and "設定操作太快，請稍候再按完成設定。" or "房間設定已更新或房主已變更，請確認最新設定後再完成。"); end
end
local function clearBattlefieldResources()
 -- Generated nodes can contain thousands of parts. Release them between matches,
 -- while retaining unmarked resource folders and all other user/world geometry.
 for _,resource in ipairs(resources:GetChildren()) do
  if resource:GetAttribute("RTSManagedResource")==true then resource:Destroy() end
 end
 table.clear(managedResources)
 workspace:SetAttribute("ResourceNodeCount",0)
 workspace:SetAttribute("RelicTotal",0)
end
local function clearMatch()
 Factory.clearCorpses()
 currentMatch=nil
 matchTeams=nil
 matchGeneration+=1
 workspace:SetAttribute("MatchGeneration",matchGeneration)
 for unit in pairs(orders) do stop(unit) end
 for _,state in pairs(states) do
  clearReport(state)
  for unit in pairs(state.units) do destroyModel(unit) end
  for b in pairs(state.buildings) do destroyModel(b) end
 end
 for actor,state in pairs(states) do
  if not actor:IsA("Player") then byId[state.id],states[actor]=nil,nil; actor:Destroy()
  elseif not state.inLobby then resetActor(state) end
 end
 training,construction,researching,orders={},{},{},{}
 table.clear(AutoWork.units)
 clearBattlefieldResources()
 actionClocks={}
 reportSequence,reportSubjectSequence=0,0
 reportSubjects=setmetatable({}, {__mode="k"})
 startingSides=0
 workspace:SetAttribute("AICount",0)
 workspace:SetAttribute("FactionCount",0)
 workspace:SetAttribute("Winner","")
 workspace:SetAttribute("WinnerId",0)
 workspace:SetAttribute("WinnerTeamId",0)
 workspace:SetAttribute("TeamMode","")
 workspace:SetAttribute("LobbyTeamPreviewReady",false)
 for index=1,3 do workspace:SetAttribute("LobbyAITeam_"..index,nil) end
 workspace:SetAttribute("MatchTime",0)
end
local function lobbyReset()
 -- 對戰 place 沒有大廳：結束或無法開局時把仍在伺服器的玩家送回大廳 place。
 if Travel.role=="Match" then Travel.returnAll("正在返回大廳…"); return end
 local departingRoom=activeRoomId and rooms[activeRoomId]
 activeRoomId=nil
 workspace:SetAttribute("ActiveBattleRoomId",nil)
 workspace:SetAttribute("MatchLoadStage",nil)
 setPhase("Lobby")
 clearMatch()
 for _,state in ipairs(humanStates()) do
  local preference=CivilizationPreferenceRules.takeLobby(state,phase)
  if preference then state.civilization=preference; publishCivilization(state,state.actor) end
  if departingRoom and state.roomId==departingRoom.id then
   state.queued,state.ready,state.roomId=false,false,nil
   state.actor:SetAttribute("LobbyQueued",false)
   state.actor:SetAttribute("LobbyReady",false)
   state.actor:SetAttribute("LobbyRoomId",nil)
  end
  state.inLobby=true
  state.actor:SetAttribute("InLobby",true)
  state.actor:SetAttribute("Spectator",false)
  if not state.queued then state.actor:SetAttribute("TutorialMatch",nil) end
  if not state.actor.Character then spawnLobby(state) else positionLobby(state) end
 end
 if departingRoom then invalidateReady(departingRoom) end
 updateHost()
 announce("已返回匹配大廳，選擇匹配點後可準備新局。")
end
startMatch=function(player)
 local requester=states[player]
 local room=requester and requester.roomId and rooms[requester.roomId]
 if phase~="Lobby" or not room or not room.configured or room.travel or not requester.inLobby or requester.playing
  or workspace:GetAttribute(roomPrefix(room,"HostUserId"))~=player.UserId then return end
 local humans=queuedStates(room.id)
 local ready,message=LobbyRules.canStart(room.expected,humans)
 if not ready then notify(player,message); return end
 for _,state in ipairs(humans) do
  if not lobbyWorld:ContainsPortal(state.actor,room.id) then notify(player,"集合玩家已離開匹配點，請重新集合。"); queueLeave(state); return end
 end
 local validated
 validated,message=Rules.settings(room.settings,#humans)
 if not validated then notify(player,message); return end
 -- 大廳 place 不在本伺服器開局：預留對戰伺服器並整隊傳送，其他房間可同時出發。
 if Travel.role=="Lobby" then Travel.dispatch(room,humans,validated); return end
 Travel.launch(room,humans,validated,player)
end
-- 在本伺服器建立戰場；單一伺服器模式由大廳呼叫，對戰 place 在名單抵達後呼叫。
-- 放在 Travel 表內：主腳本已接近 Studio 的 200 個區域變數上限。
Travel.launch=function(room,humans,validated,player)
 local message
 activeRoomId=room.id
 workspace:SetAttribute("ActiveBattleRoomId",room.id)
 workspace:SetAttribute("HostUserId",player.UserId)
 workspace:SetAttribute("MatchLoadStage","正在建立全新戰場…")
 for _,state in ipairs(humans) do
  state.inLobby=false
  state.actor:SetAttribute("InLobby",false)
 end
 setPhase("Starting")
 updateHost()
 clearMatch()
 settings=validated
 local generation=matchGeneration
 -- Yield one engine frame so the selected room sees its travel state before generating the map.
 -- The roster is frozen; a departed participant aborts rather than creating an incomplete match.
 RunService.Heartbeat:Wait()
 if phase~="Starting" or activeRoomId~=room.id or matchGeneration~=generation then return end
 for _,state in ipairs(humans) do
  if states[state.actor]~=state or state.actor.Parent~=Players then lobbyReset(); return end
 end
 local ok,spawns=pcall(World.Generate,settings.size,makeResource)
 if not ok then lobbyReset(); warn("[RTS] 地圖生成失敗："..tostring(spawns)); notify(player,"地圖生成失敗，請查看 Studio 輸出後重試。"); return end
 local relicsOk,relicError=pcall(Relic.spawnAll,settings.size)
 if not relicsOk then warn("[RTS] 聖物放置失敗："..tostring(relicError)) end
 Config.Spawns=spawns or Config.Spawns
 for model in pairs(managedResources) do if model.Parent~=resources then managedResources[model]=nil end end
 workspace:SetAttribute("Difficulty",settings.difficulty)
 workspace:SetAttribute("VictoryMode",settings.victory)
 workspace:SetAttribute("PopulationLimit",settings.population)
 workspace:SetAttribute("StartingResources",settings.startingResources)
 workspace:SetAttribute("TeamMode",settings.teamMode)
 workspace:SetAttribute("MatchLoadStage","正在部署陣營與村民…")
 local participants=table.clone(humans)
 local aiIds=plannedAIIds(settings.aiCount)
 for i=1,settings.aiCount do
  local aiId=aiIds[i]
  local actor=Instance.new("Folder")
  actor.Name="AI_"..i
  actor:SetAttribute("UserId",aiId)
  actor:SetAttribute("OwnerId",aiId)
  local chapter=LobbyRules.story(settings)
  actor:SetAttribute("DisplayName",chapter and (chapter.enemy..(settings.aiCount>1 and " "..i or "")) or "電腦 "..i)
  actor:SetAttribute("IsAI",true)
  actor.Parent=factions
  local state={actor=actor,id=aiId,ai=true,aiTurn=0,nextAttack=0,tokens=12,last=os.clock(),civilization=Config.CivilizationOrder[i%#Config.CivilizationOrder+1]}
  states[actor],byId[aiId]=state,state
  resetActor(state)
  table.insert(participants,state)
 end
 local roster={}
 for _,state in ipairs(participants) do table.insert(roster,{id=state.id,ai=state.ai}) end
 matchTeams,message=TeamRules.assign(settings.teamMode,roster)
 if not matchTeams then lobbyReset(); notify(player,message or "分隊建立失敗，請重新設定戰局。","Error"); return end
 local initial=Config.Settings.startingResources
 if Config.StartingResources then initial=Config.StartingResources[settings.startingResources] or initial end
 if settings.startingResources=="Rich" and not (Config.StartingResources and Config.StartingResources.Rich) then initial={food=1200,wood=1200,gold=800,stone=600} end
 local made,spawnError=pcall(function()
  for _,state in ipairs(participants) do
   local slot=matchTeams.slotById[state.id]
   local actor,home=state.actor,Config.Spawns[slot]
   state.slot,state.home,state.playing=slot,home,true
   actor:SetAttribute("Spectator",false)
   actor:SetAttribute("TeamColor",colors[slot])
   publishTeam(state,actor)
   actor:SetAttribute("HomePosition",home)
   actor:SetAttribute("FactionSlot",slot)
   for key,value in pairs(initial) do actor:SetAttribute(key,value) end
   local center=makeBuilding(state,"TownCenter",home,true)
   center:SetAttribute("MainBase",true)
   for i=1,Config.Settings.startingVillagers do
    local inward=home.Z>0 and -1 or 1
    makeUnit(state,"villager",home+Vector3.new(-12+i*6,0,inward*28))
   end
   if Config.Units.scout then makeUnit(state,"scout",home+Vector3.new(home.X>0 and -32 or 32,0,0)) end
   population(state)
  end
 end)
 if not made then warn("[RTS] 初始陣營生成失敗："..tostring(spawnError)); lobbyReset(); notify(player,"陣營生成失敗，已返回大廳。"); return end
 for _,state in ipairs(humans) do
  clearLobbyCharacter(state)
  state.queued,state.ready,state.roomId=false,false,nil
  state.actor:SetAttribute("LobbyQueued",false)
  state.actor:SetAttribute("LobbyReady",false)
  state.actor:SetAttribute("LobbyRoomId",nil)
 end
 startingSides,matchStart=#participants,os.clock()
 workspace:SetAttribute("AICount",settings.aiCount)
 workspace:SetAttribute("FactionCount",#participants)
 workspace:SetAttribute("Sandbox",startingSides==1)
 setPhase("Playing")
 workspace:SetAttribute("MatchLoadStage",nil)
 currentMatch={id=HttpService:GenerateGUID(false),participants={},factions={},results={},teamMode=settings.teamMode,
  eligible=ProfileRules.eligible(profiles.enabled,#humans,settings.aiCount,true),
  mode=settings.gameMode=="Story" and "Story" or #humans>=2 and settings.aiCount==0 and "PurePvP" or settings.aiCount>0 and "AIPractice" or "Sandbox"}
 for _,state in ipairs(participants) do
  currentMatch.factions[state.id]=state
  clearReport(state)
  state.report=MatchReportRules.New(currentMatch.id,matchStart)
 end
 for _,state in ipairs(humans) do
  currentMatch.participants[state.id]=state
  telemetry:Fact(state.actor,"start")
  telemetry:Match(state.actor,"Started",0,matchContext(state))
 end
 updateHost()
 print(string.format("[RTS] 對局開始：%d 名玩家、%d 個電腦陣營，地圖 %s。",#humans,settings.aiCount,settings.size))
 local story=LobbyRules.story(settings)
 workspace:SetAttribute("StoryChapter",story and settings.storyChapter or 0)
 local startMessage=story and ("第 "..settings.storyChapter.." 章「"..story.title.."」\n"..story.briefing.."\n目標："..story.objective)
  or startingSides==1 and "練習對局開始：可自由熟悉經濟與建造；投降後返回大廳。"
  or settings.teamMode=="CoopAI" and "合作對局開始！所有玩家同隊，發展經濟並擊敗電腦聯軍。"
  or settings.teamMode=="Teams" and "分隊對局開始！與盟友共同發展，擊敗敵方隊伍。"
  or "對局開始！採集資源、發展時代並擊敗對手。"
 for _,state in ipairs(humans) do
  notify(state.actor,state.actor:GetAttribute("TutorialMatch")==true and "新手教程開始：跟著左上角的指引一步一步來；這一局沒有對手，可以慢慢練習。" or startMessage,"MatchStart")
 end
end
autoStartLobby=function()
 if phase~="Lobby" then return end
 for _,portal in ipairs(Config.Lobby.portals) do
  local room=rooms[portal.id]
  local members=queuedStates(room.id)
  if room.configured and not room.travel and LobbyRules.canStart(room.expected,members) then
    local host=members[1] and members[1].actor
    if host and host.Parent==Players then startMatch(host); if phase~="Lobby" then return end end
  end
 end
end
local function lobbyReady(state,value,revision)
 local room=state.roomId and rooms[state.roomId]
 if not room or not room.configured or room.travel or not state.inLobby or state.playing or not state.queued or activeRoomId==room.id
  or type(value)~="boolean" or revision~=room.revision then return end
 if not lobbyWorld:ContainsPortal(state.actor,room.id) then queueLeave(state); return end
 state.ready=value
 state.actor:SetAttribute("LobbyReady",value)
 updateHost()
end
local function join(player)
 if states[player] then return end
 joinSequence+=1
 local state={actor=player,id=player.UserId,joined=joinSequence,tokens=12,last=os.clock(),ai=false,civilizationRevision=0,inLobby=true,autoWork=true}
 states[player],byId[state.id]=state,state
 resetActor(state)
 player:SetAttribute("AutoWork",true)
 player:SetAttribute("IsAI",false)
 player:SetAttribute("Spectator",false)
 player:SetAttribute("InLobby",true)
 player:SetAttribute("LobbyRoomId",nil)
 player:SetAttribute("LobbyQueued",false)
 player:SetAttribute("LobbyReady",false)
 profiles:Open(player,function(profile)
  if states[player]~=state then return end
  local preference=CivilizationPreferenceRules.receive(state,profile.civilization,state.inLobby and "Lobby" or phase)
  if preference and state.civilization~=preference then
   state.civilization=preference
   publishCivilization(state,player)
   if state.queued then invalidateReady(rooms[state.roomId]); updateHost() end
  end
 end)
 telemetry:Join(player)
 if Travel.role=="Match" then Travel.admit(state); return end
 updateHost()
 spawnLobby(state)
 if phase~="Lobby" then notify(player,"目前有對局進行中；可在其他匹配點集合等待下一局。") end
 if Travel.role=="Lobby" then
  local ok,data=pcall(function() return player:GetJoinData() end)
  if ok and type(data)=="table" and data.SourcePlaceId==Config.Places.matchPlaceId then notify(player,"已返回大廳，選擇匹配點即可開始下一局。") end
 end
end
-- 大廳 place：整隊出發。房間在傳送期間鎖定；任一步失敗都恢復房間並取消準備。
Travel.dispatch=function(room,humans,validated)
 local id=HttpService:GenerateGUID(false)
 local members,players={},{}
 room.travel={id=id,at=os.clock()}
 for _,state in ipairs(humans) do
  state.teleporting=id
  table.insert(members,{id=state.id,civilization=state.civilization,tutorial=state.actor:GetAttribute("TutorialMatch")==true})
  table.insert(players,state.actor)
 end
 workspace:SetAttribute(roomPrefix(room,"TravelStage"),"正在預留對戰伺服器…")
 updateHost()
 local ticket=Travel.rules.newTicket(id,room.id,validated,members,os.time())
 task.spawn(function()
  local ok,message=Travel.service:Dispatch(players,ticket,function(actor)
   Travel.restore(states[actor],id,"傳送到對戰伺服器失敗，請重新準備。")
  end)
  if not room.travel or room.travel.id~=id then return end
  if ok then workspace:SetAttribute(roomPrefix(room,"TravelStage"),"正在傳送到對戰伺服器…"); return end
  for _,state in ipairs(humans) do Travel.restore(state,id,message) end
 end)
end
Travel.restore=function(state,id,message)
 if not state or state.teleporting~=id or state.actor.Parent~=Players then return end
 state.teleporting=nil
 Travel.service:Cancel(state.actor)
 state.ready=false
 state.actor:SetAttribute("LobbyReady",false)
 if message then notify(state.actor,message,"Error") end
 updateHost()
end
-- 對戰 place：玩家抵達後等票據，名單外或開局後才到的玩家送回大廳。
Travel.admit=function(state)
 state.inLobby=false
 state.actor:SetAttribute("InLobby",false)
 Travel.step()
end
Travel.returnPlayers=function(list,message)
 local players={}
 for _,state in ipairs(list) do
  if state.actor.Parent==Players and not state.returning then
   state.returning=true
   state.actor:SetAttribute("ReturningToLobby",true)
   if message then notify(state.actor,message) end
   table.insert(players,state.actor)
  end
 end
 if #players==0 then return end
 local function failed(actor)
  local state=states[actor]
  if not state or not state.returning then return end
  state.returning=false
  actor:SetAttribute("ReturningToLobby",false)
  notify(actor,"返回大廳失敗，請稍後再試一次，或直接離開遊戲。","Error")
 end
 task.spawn(function()
  if not Travel.service:Return(players,failed) then for _,actor in ipairs(players) do failed(actor) end end
 end)
end
Travel.returnAll=function(message)
 Travel.returnPlayers(humanStates(),message)
end
-- Studio 模擬：以先進入的玩家組成名單，設定取 RTSStudioSettings（JSON）或匹配點 1 的預設。
Travel.studioTicket=function()
 local payload=table.clone(Config.Lobby.portals[1].settings)
 local raw=script.Parent:GetAttribute("RTSStudioSettings")
 if type(raw)=="string" then
  local ok,decoded=pcall(HttpService.JSONDecode,HttpService,raw)
  if ok and type(decoded)=="table" then payload=decoded end
 end
 local validated,count=LobbyRules.settings(payload)
 if not validated then warn("[RTS Travel] Studio 對局設定無效："..tostring(count)); return nil end
 local deadline=os.clock()+10
 while #humanStates()<count and os.clock()<deadline do task.wait(0.25) end
 local members={}
 for index,state in ipairs(humanStates()) do
  if index>count then break end
  table.insert(members,{id=state.id,civilization=state.civilization})
 end
 if #members==0 then return nil end
 local tutorial=script.Parent:GetAttribute("RTSStudioTutorial")==true
 for _,member in ipairs(members) do member.tutorial=tutorial end
 return Travel.rules.newTicket("studio-"..HttpService:GenerateGUID(false),"Room1",validated,members,os.time())
end
Travel.load=function()
 Travel.bootedAt=os.clock()
 workspace:SetAttribute("MatchLoadStage","正在讀取對局資料…")
 task.spawn(function()
  local raw
  if RunService:IsStudio() then raw=Travel.studioTicket()
  elseif Travel.rules.reserved(game.PrivateServerId,game.PrivateServerOwnerId) then raw=Travel.service:ReadTicket(game.PrivateServerId) end
  local ticket,message=Travel.rules.readTicket(raw,os.time(),Config.Places.ticketTtl,Config.Lobby.portals)
  if not ticket then
   warn("[RTS Travel] 無法取得對局資料："..tostring(message))
   Travel.ticketError=true
   workspace:SetAttribute("MatchLoadStage","找不到這場對局的資料，正在返回大廳…")
  else
   Travel.ticket=ticket
   Travel.bootedAt=os.clock()
   -- 房間狀態跟隨 Starting，客戶端在等待抵達時顯示出發畫面。
   activeRoomId=ticket.roomId
   workspace:SetAttribute("ActiveBattleRoomId",ticket.roomId)
  end
  Travel.step()
 end)
end
Travel.step=function()
 if Travel.role=="Lobby" then
  for _,room in pairs(rooms) do
   local travel=room.travel
   if travel and os.clock()-travel.at>Config.Places.travelTimeout then
    for _,state in ipairs(queuedStates(room.id)) do Travel.restore(state,travel.id,"傳送逾時，請重新準備。") end
   end
  end
  return
 end
 if Travel.role~="Match" then return end
 if Travel.ticketError then Travel.returnAll("找不到這場對局的資料，正在返回大廳。"); return end
 local ticket=Travel.ticket
 if not ticket then return end
 for _,state in ipairs(humanStates()) do
  if not state.admitted then
   state.admitted=true
   local entry=Travel.rules.member(ticket,state.id)
   if Travel.launched or not entry then
    Travel.returnPlayers({state},entry and "這場對局已經開始，正在返回大廳。" or "你不在這場對局的名單中，正在返回大廳。")
   else
    local order=0
    for index,candidate in ipairs(ticket.players) do if candidate==entry then order=index end end
    state.civilization=CivilizationRules.resolve(Config,entry.civilization or state.civilization)
    publishCivilization(state,state.actor)
    state.queued,state.ready,state.roomId,state.queueOrder=true,true,ticket.roomId,order
    state.actor:SetAttribute("LobbyQueued",true)
    state.actor:SetAttribute("LobbyReady",true)
    state.actor:SetAttribute("LobbyRoomId",ticket.roomId)
    state.actor:SetAttribute("TutorialMatch",entry.tutorial or nil)
   end
  end
 end
 if Travel.launched then return end
 local present=queuedStates(ticket.roomId)
 local decision=Travel.rules.arrival(ticket.expected,#present,os.clock()-Travel.bootedAt,Config.Places.arrivalTimeout)
 workspace:SetAttribute("MatchLoadStage",string.format("等待玩家抵達（%d / %d）…",#present,ticket.expected))
 updateHost()
 if decision=="wait" then return end
 Travel.launched=true
 if decision=="abort" then return end
 if not RunService:IsStudio() then task.spawn(function() Travel.service:RemoveTicket(game.PrivateServerId) end) end
 local validated,message=Rules.settings(ticket.settings,#present)
 if not validated then Travel.returnAll("部分玩家未抵達，這場對局無法開始："..tostring(message)); return end
 local room=rooms[ticket.roomId]
 room.settings,room.expected,room.configured=validated,#present,true
 if #present<ticket.expected then
  for _,state in ipairs(present) do notify(state.actor,"部分玩家未能抵達，以已抵達的玩家開局。") end
 end
 task.spawn(Travel.launch,room,present,validated,present[1].actor)
end
-- Trade 是區塊內的別名，不占主程式的區域變數。
do
local Trade=Relic.trade
-- 聖物 ----------------------------------------------------------------------
Relic.isRelic=function(model)
 return typeof(model)=="Instance" and model:IsA("Model") and model.Parent==resources and model:GetAttribute("Relic")==true
end
-- 可放聖物：地圖內，且周圍沒有資源、建築、單位或其他聖物。
Relic.clear=function(x,z)
 local pos=Vector3.new(x,Config.Map.GroundY,z)
 local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2-Config.Map.ResourceLayout.BorderMargin
 if not validPosition(pos) or math.abs(x)>half or math.abs(z)>half then return false end
 local box=Relic.config.clearance*2
 return #obstacleParts(pos+Vector3.new(0,3,0),Vector3.new(box,6,box))==0
end
Relic.make=function(x,z)
 local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2-Config.Map.ResourceLayout.BorderMargin
 local pos=Vector3.new(math.clamp(x,-half,half),Config.Map.GroundY,math.clamp(z,-half,half))
 local size=Relic.config.size
 local model=Factory.model("Relic",pos,Vector3.new(size,size,size),Color3.fromRGB(226,190,92),"Resource")
 -- 聖物不擋路；占地只用來點選與避免把建築蓋在上面。
 model.PrimaryPart.CanCollide=false
 model:SetAttribute("RTSManagedResource",true)
 model:SetAttribute("Relic",true)
 model:SetAttribute("DisplayName",Relic.config.name)
 model.Parent=resources
 Relic.ground[model]=true
 return model
end
Relic.spawnAll=function(sizeName)
 local count=Relic.config.counts[sizeName] or 0
 local size=workspace:GetAttribute("MapSize") or Config.Map.MapSize
 local points=Relic.rules.relicPoints(size,count,Relic.config.axisRadii[sizeName] or {}) or {}
 local placed=0
 for _,point in ipairs(points) do
  local spot=Relic.rules.nudge(point,Relic.clear,6,12)
  if spot then Relic.make(spot.X,spot.Z); placed+=1 else warn("[RTS] 找不到聖物的空位：",point.X,point.Z) end
 end
 workspace:SetAttribute("RelicTotal",placed)
 Relic.holder,Relic.holdSince=nil,nil
 workspace:SetAttribute("RelicHoldRemaining",nil)
end
-- 聖物勝利：同一隊（FFA 時就是單一陣營）存放全圖所有聖物後開始倒數，期間失去任何一件就重新計算。
Relic.victoryStep=function(now)
 local totals={}
 for _,state in pairs(states) do
  if alive(state) then
   local team=TeamRules.team(matchTeams,state.id)
   if team~=nil then totals[team]=(totals[team] or 0)+(state.actor:GetAttribute("Relics") or 0) end
  end
 end
 local holder=Relic.rules.relicHolder(totals,workspace:GetAttribute("RelicTotal") or 0)
 if holder~=Relic.holder then
  if holder~=nil then announce(string.format("有勢力已集齊全部聖物！守住 %d 秒就會獲勝。",Relic.config.victoryTime),"Error")
  elseif Relic.holder~=nil then announce("聖物已被奪走，聖物勝利倒數中斷。") end
  Relic.holder,Relic.holdSince=holder,holder~=nil and now or nil
 end
 local remaining=Relic.holdSince and math.max(0,Relic.config.victoryTime-(now-Relic.holdSince)) or nil
 for _,state in pairs(states) do
  local holding=remaining~=nil and alive(state) and TeamRules.team(matchTeams,state.id)==holder
  state.actor:SetAttribute("RelicRemaining",holding and math.ceil(remaining) or nil)
 end
 workspace:SetAttribute("RelicHoldRemaining",remaining and math.ceil(remaining) or nil)
 if remaining and remaining<=0 then
  Relic.holder,Relic.holdSince=nil,nil
  endMatch(holder)
 end
end
-- 掉落時找附近空位；真的找不到也照放，聖物不能消失。
Relic.drop=function(origin,count,spread)
 for index=1,count do
  local angle=index*2*math.pi/math.max(1,count)
  local start={X=origin.X+math.cos(angle)*spread,Z=origin.Z+math.sin(angle)*spread}
  local spot=Relic.rules.nudge(start,Relic.clear,5,14) or start
  Relic.make(spot.X,spot.Z)
 end
end
Relic.publish=function(state)
 local total=0
 for building in pairs(state.buildings) do
  if building.Parent==buildings and building:GetAttribute("BuildingType")=="Monastery" then total+=building:GetAttribute("Relics") or 0 end
 end
 state.actor:SetAttribute("Relics",total)
 return total
end
Relic.release=function(model)
 local state=owner(model)
 if model.Parent==units and model:GetAttribute("CarryingRelic")==true then
  model:SetAttribute("CarryingRelic",nil)
  Relic.drop(position(model),1,0)
  if state then notify(state.actor,"攜帶聖物的僧侶倒下了，聖物掉落在原地。","Error") end
 elseif model.Parent==buildings and (model:GetAttribute("Relics") or 0)>0 then
  local count=model:GetAttribute("Relics")
  model:SetAttribute("Relics",0)
  local half=model.PrimaryPart and model.PrimaryPart.Size/2 or Vector3.new(8,8,8)
  Relic.drop(position(model),count,math.max(half.X,half.Z)+6)
  if state then Relic.publish(state); notify(state.actor,"修道院被摧毀，"..count.." 件聖物掉落在廢墟旁。","Error") end
 end
end
Relic.income=function(state,dt)
 local relics=state.actor:GetAttribute("Relics") or 0
 if relics<=0 then return end
 local gold,rest=Relic.rules.relicIncome(Relic.accumulated[state] or 0,relics,Relic.config.goldPerSecond,dt)
 Relic.accumulated[state]=rest
 if gold>0 then
  state.actor:SetAttribute("gold",(state.actor:GetAttribute("gold") or 0)+gold)
  state.actor:SetAttribute("RelicGold",(state.actor:GetAttribute("RelicGold") or 0)+gold)
 end
end
Relic.storeTarget=function(state,building)
 return isOwned(state,building,buildings) and building:GetAttribute("BuildingType")=="Monastery" and building:GetAttribute("Complete")==true
end
Relic.order=function(state,unit,relic)
 if unit:GetAttribute("CarryingRelic")==true then notify(state.actor,"這位僧侶已攜帶聖物；先右鍵自己的修道院存放。"); return end
 issue(unit,"relic",relic)
end
Relic.orderStore=function(state,unit,building)
 if not Relic.storeTarget(state,building) then notify(state.actor,"聖物只能存放在自己已完工的修道院。"); return end
 issue(unit,"relicStore",building)
end
Relic.pickup=function(state,unit,relic)
 if not Relic.isRelic(relic) or unit:GetAttribute("CarryingRelic")==true then stop(unit); return end
 Relic.ground[relic]=nil
 relic:Destroy()
 unit:SetAttribute("CarryingRelic",true)
 Factory.relicCarry(unit,true)
 local best,bestDistance=nil,math.huge
 for building in pairs(state.buildings) do
  if Relic.storeTarget(state,building) then
   local distance=(position(building)-position(unit)).Magnitude
   if distance<bestDistance then best,bestDistance=building,distance end
  end
 end
 if best then issue(unit,"relicStore",best); notify(state.actor,"僧侶拾起聖物，正送回修道院。","Order")
 else stop(unit); notify(state.actor,"僧侶拾起聖物；建造修道院後右鍵它存放聖物。","Order") end
end
Relic.store=function(state,unit,building)
 if unit:GetAttribute("CarryingRelic")~=true or not Relic.storeTarget(state,building) then stop(unit); return end
 unit:SetAttribute("CarryingRelic",nil)
 Factory.relicCarry(unit,false)
 building:SetAttribute("Relics",(building:GetAttribute("Relics") or 0)+1)
 local total=Relic.publish(state)
 stop(unit)
 notify(state.actor,string.format("聖物已存放到修道院：共 %d 件，每秒 +%g 黃金。",total,total*Relic.config.goldPerSecond),"Research")
end
-- 貿易 ----------------------------------------------------------------------
-- 可貿易的市集：己方或盟友（存活且非敵對）已完工的市集。
Trade.market=function(state,building)
 if typeof(building)~="Instance" or building.Parent~=buildings or building:GetAttribute("BuildingType")~="Market" or building:GetAttribute("Complete")~=true then return false end
 local other=owner(building)
 if other==state then return true end
 return alive(other) and currentMatch~=nil and TeamRules.isParticipant(matchTeams,currentMatch.factions,other) and not enemies(state,other)
end
Trade.distance=function(a,b) return (position(a)-position(b)).Magnitude end
Trade.order=function(state,unit,destination)
 if not Trade.market(state,destination) then
  notify(state.actor,"貿易車只能前往己方或盟友已完工的市集；貿易車不能攻擊。")
  return
 end
 local home=Trade.home[unit]
 if not (home and home~=destination and isOwned(state,home,buildings) and Trade.market(state,home)) then
  -- 沒有有效的出發市集時，選離目的地最遠的己方市集，每趟收益最高。
  home=nil
  local farthest=-1
  for building in pairs(state.buildings) do
   if building~=destination and Trade.market(state,building) then
    local distance=Trade.distance(building,destination)
    if distance>farthest then home,farthest=building,distance end
   end
  end
 end
 if not home then notify(state.actor,"需要另一座己方已完工的市集作為貿易起點。","Error"); return end
 local distance=Trade.distance(home,destination)
 if distance<Trade.config.minDistance then
  notify(state.actor,string.format("兩座市集只相距 %d，至少要 %d 才能貿易。",math.floor(distance),Trade.config.minDistance),"Error")
  return
 end
 Trade.home[unit]=home
 issue(unit,"trade",destination)
 orders[unit].home=home
end
-- 目的地仍有效；回程載著黃金時，出發點失效也繼續把黃金帶回。
Trade.valid=function(state,unit,order)
 if not Trade.market(state,order.target) then return false end
 if (unit:GetAttribute("TradeGold") or 0)>0 and isOwned(state,order.target,buildings) then return true end
 return order.home~=nil and order.home~=order.target and Trade.market(state,order.home)
end
Trade.arrive=function(state,unit,order)
 local market=order.target
 local carrying=unit:GetAttribute("TradeGold") or 0
 local action=Relic.rules.tradeArrival(isOwned(state,market,buildings),carrying)
 if action=="deliver" then
  state.actor:SetAttribute("gold",(state.actor:GetAttribute("gold") or 0)+carrying)
  state.actor:SetAttribute("TradeIncome",(state.actor:GetAttribute("TradeIncome") or 0)+carrying)
  unit:SetAttribute("TradeGold",0)
  Factory.tradeCargo(unit,false)
 elseif action=="load" then
  local partner=order.home
  local gold=(partner and partner.Parent==buildings) and Relic.rules.tradeGold(Trade.distance(partner,market),Trade.config,owner(market)~=state) or 0
  unit:SetAttribute("TradeGold",gold)
  Factory.tradeCargo(unit,gold>0)
 end
 local nextTarget=order.home
 if not (nextTarget and nextTarget~=market and Trade.market(state,nextTarget)) then
  stop(unit)
  if action~="deliver" then notify(state.actor,"貿易路線的另一座市集已失效，貿易車停止。") end
  return
 end
 issue(unit,"trade",nextTarget)
 orders[unit].home=market
 Trade.home[unit]=isOwned(state,nextTarget,buildings) and nextTarget or market
end
-- 電腦（基本版）：城堡時代起蓋修道院、派僧侶撿聖物，並在己方／盟友市集之間跑貿易車。
-- build 由 aiStep 傳入（aiBuild 在本區塊之後才定義）。
Relic.aiRelics=function(state,saving,build)
 local relics,relicList={}, {}
 for relic in pairs(Relic.ground) do
  if Relic.isRelic(relic) then table.insert(relics,relic); local p=position(relic); table.insert(relicList,{X=p.X,Z=p.Z}) else Relic.ground[relic]=nil end
 end
 if #relics==0 and settings.victory~="Relic" then return end
 local monastery
 for building in pairs(state.buildings) do if Relic.storeTarget(state,building) then monastery=building; break end end
 if not monastery then build(state,"Monastery"); return end
 local claimed,free,seekers,monks={}, {}, {},0
 for unit in pairs(state.units) do
  if unit.Parent==units and unit:GetAttribute("UnitType")=="monk" then
   monks+=1
   local order=orders[unit]
   if unit:GetAttribute("CarryingRelic")==true then
    if not order or order.kind~="relicStore" then issue(unit,"relicStore",monastery,true) end
   elseif order and order.kind=="relic" then claimed[order.target]=true
   elseif not order or order.automatic then
    table.insert(free,unit); local p=position(unit); table.insert(seekers,{X=p.X,Z=p.Z})
   end
  end
 end
 local openRelics,openList={}, {}
 for index,relic in ipairs(relics) do
  if not claimed[relic] then table.insert(openRelics,relic); table.insert(openList,relicList[index]) end
 end
 for seeker,relicIndex in pairs(Relic.rules.assignRelics(seekers,openList)) do issue(free[seeker],"relic",openRelics[relicIndex],true) end
 local want=math.min(math.max(#relics,1),settings.difficulty=="Easy" and 1 or settings.difficulty=="Hard" and 4 or 2)
 local queue=training[monastery]
 if monks<want and not saving and (not queue or #queue==0) then trainRequest(state,monastery,"monk",true) end
end
Relic.aiTrade=function(state,saving,build)
 local Trade=Relic.trade
 local markets,list,ownMarkets,building={}, {}, {},false
 for _,other in pairs(states) do
  for market in pairs(other.buildings) do
   if market.Parent==buildings and market:GetAttribute("BuildingType")=="Market" then
    if other==state and not market:GetAttribute("Complete") then building=true
    elseif Trade.market(state,market) then
     local p=position(market)
     table.insert(markets,market); table.insert(list,{X=p.X,Z=p.Z,own=other==state})
     if other==state then table.insert(ownMarkets,market) end
    end
   end
  end
 end
 if #ownMarkets==0 then return end
 local homeIndex,destinationIndex=Relic.rules.tradeRoute(list,Trade.config)
 if not homeIndex then
  -- 沒有可獲利的路線：在基地另一側蓋第二座市集（已有工地時讓 aiBuild 接手施工）。
  if building then build(state,"Market")
  elseif not saving and affordable(state.actor,Config.Buildings.Market.cost) then
   local data,candidates=Config.Buildings.Market,{}
   for ring=2,6 do for index=0,15 do
    local angle=index*math.pi/8
    table.insert(candidates,{X=state.home.X+math.cos(angle)*(40+ring*20),Z=state.home.Z+math.sin(angle)*(40+ring*20)})
   end end
   local first=position(ownMarkets[1])
   for _,spot in ipairs(Relic.rules.farSpots(candidates,{X=first.X,Z=first.Z},Trade.config.minDistance+16)) do
    local pos=Grid.snap(Vector3.new(spot.X,Config.Map.GroundY,spot.Z),data.size)
    if validPosition(pos) and Grid.inBounds(pos,data.size) and placementClear(pos,data) and buildRequest(state,"Market",pos,nil,true) then break end
   end
  end
  return
 end
 local home,destination=markets[homeIndex],markets[destinationIndex]
 local limit=settings.difficulty=="Easy" and 1 or settings.difficulty=="Hard" and 6 or 3
 local carts=0
 for unit in pairs(state.units) do
  if unit.Parent==units and unit:GetAttribute("UnitType")=="tradeCart" then
   carts+=1
   if not orders[unit] then Trade.home[unit]=home; Trade.order(state,unit,destination) end
  end
 end
 local queue=training[home]
 if carts<limit and not saving and (not queue or #queue==0) then trainRequest(state,home,"tradeCart",true) end
end
end
local function selectedFormationUnits(state,selection)
 return FormationRules.selection(selection,Config.Formations.maxSelectedUnits,function(unit)
  if not isOwned(state,unit,units) then return false end
  local hp=unit:GetAttribute("HP")
  return Rules.finite(hp) and hp>0
 end)
end
local function formationMove(state,selection,key,target)
 local records,selected,sumX,sumZ={},{},0,0
 for index,unit in ipairs(selection) do
  local current=position(unit)
  local radius=unit:GetAttribute("Radius") or Config.UnitCollision.default.radius
  if not Rules.finite(radius) or radius<=0 or radius>MAX_UNIT_RADIUS or not validPosition(current) then return false end
  records[index]={X=current.X,Z=current.Z,radius=radius}
  selected[unit]=true
  sumX+=current.X; sumZ+=current.Z
 end
 local first=selection[1]
 local facing={X=first:GetAttribute("FormationForwardX") or 0,Z=first:GetAttribute("FormationForwardZ") or -1}
 local center=target and {X=target.X,Z=target.Z} or {X=sumX/#selection,Z=sumZ/#selection}
 -- validPosition 保留原有 3 studs 邊距；整組額外留出最大身體半徑。
 local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2-3
 local plan=FormationRules.plan(Config.Formations,key,records,center,half,facing)
 if not plan then notify(state.actor,"這個陣形無法放入地圖，請減少選取部隊。","Error"); return false end
 local goals,reserved={},{}
 for index,unit in ipairs(selection) do
  local slot=plan.slots[plan.assignment[index]]
  local radius=records[index].radius
  local function usable(point)
   local goal=Vector3.new(point.X,Config.Map.GroundY,point.Z)
   if not staticUnitSegmentClear(unit,goal,goal) or UnitCollisionRules.overlaps(point.X,point.Z,radius,reserved) then return nil end
   local neighbors=unitNeighbors(unit,goal,goal,radius)
   if not neighbors then return nil end
   local external={}
   for _,other in ipairs(neighbors) do if not selected[other.key] then table.insert(external,other) end end
   if UnitCollisionRules.overlaps(point.X,point.Z,radius,external) then return nil end
   return goal
  end
  local goal=usable(slot)
  if not goal then
   -- 僅在下令時查詢附近障礙；目的地小幅讓位，既有路徑與單位避讓繼續負責移動。
   for ring=1,Config.Formations.obstacleSearchRings do
    for step=0,7 do
     local angle=step*math.pi/4
     local candidate={X=slot.X+math.cos(angle)*ring*plan.spacing,Z=slot.Z+math.sin(angle)*ring*plan.spacing}
     goal=usable(candidate)
     if goal then break end
    end
    if goal then break end
   end
  end
  if not goal then notify(state.actor,"陣形周圍空間不足，請選擇較空曠的位置。","Error"); return false end
  goals[index]=goal
  table.insert(reserved,{X=goal.X,Z=goal.Z,radius=radius})
 end
 -- 所有選取、陣形與目的地檢查完成後才同步修改，非法批次沒有部分套用。
 for index,unit in ipairs(selection) do
  unit:SetAttribute("Formation",key)
  unit:SetAttribute("FormationForwardX",plan.forwardX)
  unit:SetAttribute("FormationForwardZ",plan.forwardZ)
  issue(unit,"move",goals[index])
  AutoWork.hold(unit) -- 玩家指定站位：抵達後保持待命，不自動找工作。
 end
 return true
end
local function acceptFormation(state,selection,key)
 if not FormationRules.validKey(Config.Formations,key) then return end
 local validated=selectedFormationUnits(state,selection)
 if validated and formationMove(state,validated,key,nil) then notify(state.actor,nil,"Order") end
end
-- 僧侶右鍵：敵方單位招降，自己或同盟的受傷單位治療；建築與敵方僧侶不可招降。
Monk.order=function(state,unit,target,victim)
 if unit:GetAttribute("CarryingRelic")==true then notify(state.actor,"攜帶聖物的僧侶不能招降或治療；右鍵自己的修道院存放聖物。","Error"); return end
 local data=target.Parent==units and Config.Units[target:GetAttribute("UnitType")] or nil
 if enemies(state,victim) then
  if not data then notify(state.actor,"僧侶無法招降建築。","Error"); return end
  local ok,reason=Monk.rules.canConvert(data.class,false,target:GetAttribute("HP"),Monk.config.maxFaith,Monk.config.maxFaith)
  if not ok then notify(state.actor,reason,"Error"); return end
  issue(unit,"convert",target)
  if (unit:GetAttribute("Faith") or 0)<Monk.config.maxFaith then notify(state.actor,"僧侶信仰恢復中，恢復後才會開始招降。") end
 elseif data and victim and target~=unit and not enemies(state,victim)
  and Monk.rules.canHeal(data.class,false,true,target:GetAttribute("HP"),target:GetAttribute("MaxHP")) then
  issue(unit,"heal",target)
 end
end
-- 招降成功：原單位交由僧侶陣營重新生成，保留類型、位置與生命比例；戰報記為擊殺／損失。
Monk.convert=function(state,monk,target)
 local victim=owner(target)
 local kind,pos=target:GetAttribute("UnitType"),position(target)
 local hp,maxHP=target:GetAttribute("HP") or 0,target:GetAttribute("MaxHP") or 1
 local name=target:GetAttribute("DisplayName") or (Config.Units[kind] and Config.Units[kind].name) or "單位"
 local subjectId=reportSubject(target)
 recordReport(state,"kill",{subjectId=subjectId,category="unit"})
 if victim then recordReport(victim,"loss",{subjectId=subjectId,category="unit"}) end
 destroyModel(target)
 local ok,model=pcall(makeUnit,state,kind,pos)
 if ok then model:SetAttribute("HP",math.clamp(model:GetAttribute("MaxHP")*hp/math.max(1,maxHP),1,model:GetAttribute("MaxHP")))
 else warn("[RTS] 招降單位生成失敗："..tostring(model)) end
 monk:SetAttribute("Faith",0)
 monk:SetAttribute("ConversionTime",nil)
 stop(monk)
 notify(state.actor,"僧侶成功招降了"..name.."。","Order")
 if victim then notify(victim.actor,"你的"..name.."被敵方僧侶招降了。","Error"); eliminationCheck(victim) end
 if phase=="Playing" then checkVictory() end
end
Monk.step=function(state,unit,order,target,now)
 local data=Config.Units[target:GetAttribute("UnitType")]
 local faith=unit:GetAttribute("Faith") or 0
 local ok,reason=Monk.rules.canConvert(data and data.class,false,target:GetAttribute("HP"),faith,Monk.config.maxFaith)
 if not ok then
  -- 信仰不足時留在射程內等待；其他原因（目標改變、不可招降）則停止。
  order.convertTime,order.convertLast=0,nil
  unit:SetAttribute("Animation","Idle")
  if faith>=Monk.config.maxFaith then notify(state.actor,reason,"Error"); stop(unit) end
  return
 end
 -- 只累計在射程內的時間；目標短暫走開時僧侶跟隨，進度保留（村民採集只停留約 3 秒）。
 local last=order.convertLast
 order.convertTime=(order.convertTime or 0)+((last and now-last<=0.6) and now-last or 0)
 order.convertLast=now
 unit:SetAttribute("ConversionTime",order.convertTime)
 if UnitRules.takeAction(actionClocks,unit,"convert",now,1) then
  local roll=Monk.random:NextNumber()
  if Monk.rules.conversionSucceeds(order.convertTime,Monk.config.convertMin,Monk.config.convertMax,Monk.config.convertChance,roll) then Monk.convert(state,unit,target) end
 end
end
Monk.autoHeal=function(state,monk)
 if monk:GetAttribute("CarryingRelic")==true then return end
 local current,best,bestDistance=position(monk),nil,Monk.config.autoHealRadius
 for other in pairs(state.units) do
  local data=other~=monk and other.Parent==units and Config.Units[other:GetAttribute("UnitType")]
  if data and Monk.rules.canHeal(data.class,false,true,other:GetAttribute("HP"),other:GetAttribute("MaxHP")) then
   local distance=(position(other)-current).Magnitude
   if distance<bestDistance then best,bestDistance=other,distance end
  end
 end
 if best then issue(monk,"heal",best,true) end
end
local function acceptOrder(state,selection,target,key)
 local validated=selectedFormationUnits(state,selection)
 if not validated or (key~=nil and not FormationRules.validKey(Config.Formations,key)) then return end
 local targetModel=isTarget(target)
 if not targetModel and not validPosition(target) then return end
 if not targetModel then
  key=key or validated[1]:GetAttribute("Formation") or Config.Formations.default
  if not FormationRules.validKey(Config.Formations,key) then return end
  if formationMove(state,validated,key,target) then notify(state.actor,nil,"Order") end
  return
 end
 local accepted=false
 for _,unit in ipairs(validated) do
  local previous=orders[unit]
  local victim,kind=owner(target),unit:GetAttribute("UnitType")
  -- 右鍵不會駐紮：駐紮一律走專用的 Garrison 指令（駐紮按鈕／G、Alt+右鍵、觸控模式），村民與軍隊相同。
  if kind=="monk" and Relic.isRelic(target) then Relic.order(state,unit,target)
  elseif kind=="monk" and unit:GetAttribute("CarryingRelic")==true and isOwned(state,target,buildings) and target:GetAttribute("BuildingType")=="Monastery" then Relic.orderStore(state,unit,target)
  elseif kind=="monk" then Monk.order(state,unit,target,victim)
  elseif Relic.isRelic(target) then notify(state.actor,"只有僧侶能拾取聖物。")
  elseif kind=="tradeCart" then Relic.trade.order(state,unit,target)
  elseif enemies(state,victim) then issue(unit,"attack",target)
  elseif canBuildWorker(state,unit) and isOwned(state,target,buildings) and construction[target] and not target:GetAttribute("Complete") then issue(unit,"build",target)
  elseif kind=="villager" and target:GetAttribute("ResourceType") and (not victim or victim==state) and (target.Parent~=buildings or target:GetAttribute("Complete"))
   and ((target:GetAttribute("Amount") or 0)>0 or (AutoWork.isFarm(target) and (not AutoWork.farmFree(target,unit) or AutoWork.reseed(state,target,true)))) then
   -- 己方耗盡的農田下令時先重新播種（預置或扣木材）；已有村民的農田在指令步驟改派。
   if (unit:GetAttribute("Carrying") or 0)>0 and unit:GetAttribute("CarryType")~=target:GetAttribute("ResourceType") then beginDelivery(state,unit,target)
   else issue(unit,"gather",target); orders[unit].manual=true end
  elseif kind=="villager" and isOwned(state,target,buildings) and (target:GetAttribute("HP") or 0)<(target:GetAttribute("MaxHP") or 0) then issue(unit,"repair",target)
  elseif kind=="villager" and isOwned(state,target,buildings) and (unit:GetAttribute("Carrying") or 0)>0 then
   if target:GetAttribute("Complete") and acceptsResource(target,unit:GetAttribute("CarryType")) then beginDelivery(state,unit,nil,target)
   else notify(state.actor,"這座建築無法接收村民攜帶的資源。") end
  end
  if orders[unit] and orders[unit]~=previous then accepted=true end
 end
 if accepted then notify(state.actor,nil,"Order") end
end
command.OnServerEvent:Connect(function(player,action,a,b,c,d)
 local state=states[player]
 if not state or type(action)~="string" then return end
 local now=os.clock()
 state.tokens=math.min(12,state.tokens+(now-state.last)*6)
 state.last=now
 if state.tokens<1 then
  -- Coalesce rejected confirmations into the lobby scan so a pending UI always receives an answer.
  if action=="LobbyConfigureComplete" then state.configureRejected=true end
  return
 end
 state.tokens-=1
 if action=="QueueJoin" then queueJoin(state,a,false,a~=nil); return end
 if action=="QueueLeave" then queueLeave(state); return end
 if action=="LobbySettings" then configureLobby(player,a); return end
 if action=="LobbyConfigureComplete" then configureLobbyComplete(player,a); return end
 -- 教程旗標只是偏好：不給資源或戰力，完成或跳過都只記一次。
 if action=="TutorialDone" then profiles:CompleteTutorial(player); return end
 -- 熱鍵只是介面偏好：伺服器重新解析成合法綁定後才存檔，不影響戰局。
 if action=="Hotkeys" then
  if type(a)=="string" and #a<=512 then
   local HotkeyRules=require(RS.Shared.HotkeyRules)
   profiles:SetHotkeys(player,HotkeyRules.serialize(HotkeyRules.parse(a)))
  end
  return
 end
 if action=="StartTutorial" then
  -- 新手教程：伺服器代玩家把一間空房設成單人、無對手、豐富資源並準備，之後走正常的開局流程。
  if phase~="Lobby" or not state.inLobby or state.playing then notify(player,"戰場目前使用中，請稍候再開始新手教程。"); return end
  if state.queued then notify(player,"請先離開目前的房間，再開始新手教程。"); return end
  local validated,count=LobbyRules.settings({gameMode="Sandbox",expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"},{internal=true})
  local room
  for _,portal in ipairs(Config.Lobby.portals) do
   local candidate=rooms[portal.id]
   if activeRoomId~=candidate.id and #queuedStates(candidate.id)==0 then room=candidate; break end
  end
  if not validated or not room then notify(player,"目前沒有空的匹配點，請稍候再試。"); return end
  queueJoin(state,room.id,true,true)
  if not state.queued or state.roomId~=room.id then notify(player,"大廳角色尚未準備好，請稍候再開始新手教程。"); return end
  room.settings,room.expected,room.configured=validated,count,true
  invalidateReady(room)
  state.ready=true
  player:SetAttribute("LobbyReady",true)
  player:SetAttribute("TutorialMatch",true)
  updateHost()
  return
 end
 if action=="QuickPlay" then
  -- 快速開始：單人劇情直接開下一章；其他玩法先加入同玩法、還有空位的房間，沒有就建立新房間由玩家當房主設定。
  local GameModes=LobbyRules.GameModes
  local solo=a=="StorySolo"
  local mode=solo and "Story" or a
  if type(mode)~="string" or not table.find(GameModes.Order,mode) then return end
  if not state.inLobby or state.playing then notify(player,"目前在對局中，請先返回大廳。"); return end
  if state.queued then notify(player,"請先離開目前的房間，再使用快速開始。"); return end
  local unlocked=GameModes.unlocked(player:GetAttribute("StoryCleared"))
  if not solo then
   for _,portal in ipairs(Config.Lobby.portals) do
    local candidate=rooms[portal.id]
    local count=#queuedStates(candidate.id)
    if activeRoomId~=candidate.id and candidate.configured and candidate.settings.gameMode==mode and count>0 and count<candidate.expected then
     queueJoin(state,candidate.id,true,true)
     if state.queued then notify(player,"已加入"..portal.name.."："..GameModes.label(candidate.settings).."。確認設定後按準備完成。"); return end
    end
   end
  end
  local room,name
  for _,portal in ipairs(Config.Lobby.portals) do
   local candidate=rooms[portal.id]
   if activeRoomId~=candidate.id and #queuedStates(candidate.id)==0 then room,name=candidate,portal.name; break end
  end
  local validated,count=LobbyRules.settings(GameModes.defaults(mode,solo and 1 or 2,unlocked),{unlocked=unlocked})
  if not validated or not room then notify(player,"目前沒有空的匹配點，請稍候再試。"); return end
  queueJoin(state,room.id,true,true)
  if not state.queued or state.roomId~=room.id then notify(player,"大廳角色尚未準備好，請稍候再試。"); return end
  room.settings,room.expected,room.configured=validated,count,solo
  invalidateReady(room)
  if solo then
   state.ready=true
   player:SetAttribute("LobbyReady",true)
   notify(player,phase=="Lobby" and ("開始第 "..validated.storyChapter.." 章「"..GameModes.chapter(validated.storyChapter).title.."」…") or "戰場目前使用中；已準備好劇情章節，戰場開放後自動出發。")
  else
   notify(player,"已在"..name.."建立"..GameModes.mode(mode).title.."房間；確認設定後等候其他玩家加入。")
  end
  updateHost()
  return
 end
 if action=="SelectCivilization" then
  local allowed,entry=CivilizationRules.canSelect(Config,state.inLobby and "Lobby" or phase,a)
  if not allowed then notify(player,entry); return end
  CivilizationPreferenceRules.select(state)
  profiles:SelectCivilization(player,a)
  if state.civilization~=a then
   state.civilization=a
   publishCivilization(state,player)
   invalidateReady(state.roomId and rooms[state.roomId])
   updateHost()
   notify(player,"已選擇"..entry.name.."；所有文明使用相同對戰數值與科技。")
  end
  return
 end
 if action=="LobbyReady" then
  lobbyReady(state,a,b)
  return
 end
 if action=="AutoWork" then
  if type(a)~="boolean" or state.autoWork==a then return end
  state.autoWork=a
  player:SetAttribute("AutoWork",a)
  notify(player,a and "自動工作已開啟：閒置村民會就近施工、交貨或採集。" or "自動工作已關閉：村民只執行你下的指令。")
  return
 end
 if action=="StartMatch" then startMatch(player); return end
 if action=="RestartMatch" then if Travel.role~="Match" and phase=="Ended" and workspace:GetAttribute("HostUserId")==player.UserId then lobbyReset() end; return end
 -- 對戰 place：對局結束、已淘汰或觀戰的玩家可以各自返回大廳；仍在作戰的玩家要先投降。
 if action=="ReturnToLobby" then
  if Travel.role=="Match" and (phase=="Ended" or not alive(state)) then Travel.returnPlayers({state},"正在返回大廳…") end
  return
 end
 if phase~="Playing" or not alive(state) then return end
 if action=="Surrender" then defeat(state,"你已投降，本局判負；可以繼續觀戰。",true); if startingSides==1 then endMatch(nil) end
 elseif action=="Build" then buildRequest(state,a,b,c,false,d)
 elseif action=="BuildLine" then Walls.lineRequest(state,a,b,c,d)
 elseif action=="Train" then trainRequest(state,a,b,false)
 elseif action=="CancelTraining" then cancelTrainingRequest(state,a,b,c)
 elseif action=="Rally" then rallyRequest(state,a,b)
 elseif action=="AdvanceAge" then advanceRequest(state,a,false)
 elseif action=="Research" then researchRequest(state,a,b,false)
 elseif action=="QueueFarm" or action=="UnqueueFarm" then AutoWork.queueFarm(state,a,action=="QueueFarm")
 elseif action=="Trade" then
  if not isOwned(state,a,buildings) or a:GetAttribute("BuildingType")~="Market" or not a:GetAttribute("Complete") then return end
  if type(b)~="string" or not ({food=true,wood=true,stone=true})[b] or (c~="Buy" and c~="Sell") then return end
  local market=Config.MarketTrade or {batch=100,buyGold=130,sellGold=70}
  local cost=c=="Buy" and {gold=market.buyGold} or {[b]=market.batch}
  if not Economy.spend(player,cost) then notify(player,"交易所需資源不足。","Error"); return end
  local key,amount=c=="Buy" and b or "gold",c=="Buy" and market.batch or market.sellGold
  player:SetAttribute(key,(player:GetAttribute(key) or 0)+amount)
  recordReport(state,"spend",{cost=cost})
 elseif action=="Order" then acceptOrder(state,a,b,c)
 elseif action=="Formation" then acceptFormation(state,a,b)
 elseif action=="Garrison" then
  local validated=selectedFormationUnits(state,a)
  if not validated or not isOwned(state,b,buildings) then return end
  local accepted=false
  for _,unit in ipairs(validated) do if Garrison.order(state,unit,b) then accepted=true end end
  if accepted then notify(player,nil,"Order") end
 elseif action=="Ungarrison" then
  if not isOwned(state,a,buildings) or not Garrison.inside[a] then return end
  local left=Garrison.eject(state,a)
  if Garrison.inside[a] then notify(player,left>0 and "建築周圍空位不足，部分駐軍仍留在裡面。" or "建築周圍沒有空位，駐軍無法離開。","Error")
  else notify(player,nil,"Order") end
 elseif action=="Delete" then
  local selection=CommandRules.deletion(a,b,matchGeneration,function(model)
   if not (isOwned(state,model,units) or isOwned(state,model,buildings)) then return false end
   local hp=model:GetAttribute("HP")
   return type(hp)=="number" and hp==hp and hp>0 and hp<math.huge
  end)
  if not selection then notify(player,"無法拆除：選取已失效，或包含非己方的單位與建築。","Error"); return end
  -- No refund, damage, kill credit or queued production can run between
  -- validation and this synchronous cleanup. Reuse the normal lifecycle.
  for _,model in ipairs(selection) do
   if model.Parent==buildings then Garrison.release(model) else destroyModel(model) end
  end
  eliminationCheck(state)
  if phase=="Playing" then checkVictory() end
  notify(player,"已移除所選單位與建築；不退還資源。","Order")
 elseif action=="Stop" then
  if type(a)~="table" or #a>200 then return end
  for _,unit in ipairs(a) do if isOwned(state,unit,units) then stop(unit); AutoWork.hold(unit) end end
 end
end)
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player)
 local state=states[player]
 if not state then return end
 if phase=="Playing" and state.playing then telemetry:Match(player,"Departed",os.clock()-matchStart,matchContext(state)) end
 if phase=="Playing" and state.playing then defeat(state,"玩家已離開。",true) end
 for unit in pairs(state.units) do destroyModel(unit) end
 for b in pairs(state.buildings) do destroyModel(b) end
 clearLobbyCharacter(state)
 Travel.service:Cancel(player)
 profiles:Close(player)
 telemetry:Leave(player)
 states[player],byId[state.id]=nil,nil
 if state.queued then invalidateReady(state.roomId and rooms[state.roomId]) end
 updateHost()
 checkVictory()
 local humans=humanStates()
 local hasBattlePlayer=false
 for _,human in ipairs(humans) do if human.playing then hasBattlePlayer=true; break end end
 -- A room waiting in the courtyard must not depend on a departed match host to release the arena.
 if #humans==0 or ((phase=="Playing" or phase=="Ended") and not hasBattlePlayer) then lobbyReset() end
end)

local function aiBuild(state,kind)
 local data=Config.Buildings[kind]
 if not data then return false end
 for b in pairs(state.buildings) do
  if b.Parent==buildings and b:GetAttribute("BuildingType")==kind and construction[b] and not b:GetAttribute("Complete") then
   local candidates={}
   local retries=state.buildRetryAfter[b] or {}
   for unit in pairs(state.units) do
    if canBuildWorker(state,unit) then
     local order=orders[unit]
     table.insert(candidates,{unit=unit,valid=true,orderKind=order and order.kind,
      orderTarget=order and order.target,distance=(position(unit)-position(b)).Magnitude,retryAfter=retries[unit]})
    end
   end
   local builder,assigned=AIWorkerRules.builder(candidates,b,os.clock())
   if builder and not assigned then issue(builder,"build",b) end
   return builder~=nil -- Resume the existing paid site, even when its owner cannot afford another.
  end
 end
 if not affordable(state.actor,data.cost) then return false end
 local home=state.home
 for ring=1,4 do
  for index=0,11 do
   local angle=index*math.pi/6
   local radius=44+ring*24
   local candidate=home+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
   local pos=Grid.snap(candidate,data.size)
   if validPosition(pos) and Grid.inBounds(pos,data.size) and placementClear(pos,data) then
    if buildRequest(state,kind,pos,nil,true) then return true end
   end
  end
 end
 return false
end
local function aiStep(state,now)
 if phase~="Playing" or not alive(state) then return end
 state.aiTurn+=1
 local age=state.actor:GetAttribute("Age") or 1
 local villagerCount,military,idle=0,{},{}
 local gathering={wood=0,food=0,gold=0,stone=0}
 for unit in pairs(state.units) do
  if unit.Parent==units then
   local kind,order=unit:GetAttribute("UnitType"),orders[unit]
   if kind=="villager" then
    villagerCount+=1
    if order and (order.kind=="gather" or order.kind=="deliver") then
     local key=order.kind=="gather" and order.target:GetAttribute("ResourceType") or unit:GetAttribute("CarryType")
     if gathering[key] then gathering[key]+=1 end
    elseif not order then table.insert(idle,unit) end
   -- 貿易車與負責聖物的僧侶是經濟單位，不跟著進攻。
   elseif kind=="tradeCart" or unit:GetAttribute("CarryingRelic")==true or (order and (order.kind=="relic" or order.kind=="relicStore")) then
   else table.insert(military,unit) end
  end
 end
 for _,unit in ipairs(idle) do
  if (unit:GetAttribute("Carrying") or 0)>0 then beginDelivery(state,unit,nil)
  else
   local priorities=AIWorkerRules.resourcePriorities(villagerCount,gathering,state.actor:GetAttribute("food") or 0)
   local target,key=AIWorkerRules.findResource(priorities,function(resourceKind) return nearestResource(state,position(unit),resourceKind,unit) end)
   if target then issue(unit,"gather",target); gathering[key]+=1 end
  end
 end
 local count,cap=population(state)
 if count>=cap-2 and cap<settings.population then aiBuild(state,"House") end
 local center=completedBuilding(state,"TownCenter") or completedBuilding(state,"Castle")
 local nextAge=Config.Ages[age+1]
 local targetVillagers=settings.difficulty=="Easy" and 14 or settings.difficulty=="Hard" and 30 or 22
 local threshold=math.min(targetVillagers,age==1 and 8 or age==2 and 14 or 22)
 local savingForAge=nextAge and villagerCount>=threshold and ageRequirements(state,nextAge)
 if center and savingForAge and not state.advancing then advanceRequest(state,center,true) end
 if center and villagerCount<targetVillagers and not savingForAge and not state.advancing and not researching[center] then
  local queue=training[center]
  if not queue or #queue<2 then trainRequest(state,center,"villager",true) end
 end
 if not completedBuilding(state,"Barracks") then aiBuild(state,"Barracks")
 elseif not completedBuilding(state,"LumberCamp") then aiBuild(state,"LumberCamp")
 elseif not completedBuilding(state,"Mill") then aiBuild(state,"Mill")
 elseif not completedBuilding(state,"MiningCamp") then aiBuild(state,"MiningCamp") end
 if age>=2 then
  if not completedBuilding(state,"ArcheryRange") then aiBuild(state,"ArcheryRange")
  elseif not completedBuilding(state,"Blacksmith") then aiBuild(state,"Blacksmith")
  elseif not completedBuilding(state,"Stable") then aiBuild(state,"Stable")
  elseif not completedBuilding(state,"Market") then aiBuild(state,"Market") end
 end
 if age>=3 then
  if not completedBuilding(state,"SiegeWorkshop") then aiBuild(state,"SiegeWorkshop")
  elseif not completedBuilding(state,"University") then aiBuild(state,"University") end
 end
 if age>=2 and not completedBuilding(state,"Tower") and (state.actor:GetAttribute("stone") or 0)>150 then aiBuild(state,"Tower") end
 if age>=3 then Relic.aiRelics(state,savingForAge,aiBuild); Relic.aiTrade(state,savingForAge,aiBuild) end
 -- 一塊農田只容一位村民：食物人手不足且沒有空閒食物來源時才增建。
 if gathering.food<math.ceil(villagerCount*0.42) and not nearestResource(state,state.home,"food") then aiBuild(state,"Farm") end
 if settings.victory=="Wonder" and age>=4 and not completedBuilding(state,"Wonder") then aiBuild(state,"Wonder") end
 local armyLimit=settings.difficulty=="Easy" and 16 or settings.difficulty=="Hard" and 60 or 36
 if #military<armyLimit and not savingForAge then
  for b in pairs(state.buildings) do
   if b:GetAttribute("Complete") then
    local queue=training[b]
    if not queue or #queue<2 then
     local options=Config.Buildings[b:GetAttribute("BuildingType")].trains or {}
     for offset=1,#options do local kind=options[(state.aiTurn+offset)%#options+1]; if kind~="villager" and Config.Units[kind].class~="trade" and trainRequest(state,b,kind,true) then break end end
    end
   end
  end
 end
 if state.aiTurn%3==0 and not savingForAge then
  for key,data in pairs(Config.Technologies) do
   if not state.technologies[key] and not state.pendingTech[key] and age>=(data.minAge or 1) then
    for b in pairs(state.buildings) do if researchRequest(state,b,key,true) then break end end
   end
  end
 end
 if now>=state.nextAttack and #military>=(settings.difficulty=="Easy" and 8 or 4) then
  state.nextAttack=now+(settings.difficulty=="Easy" and 30 or settings.difficulty=="Hard" and 12 or 20)
  local target,nearest=nil,math.huge
  for _,enemy in pairs(states) do
   if enemies(state,enemy) then
    for b in pairs(enemy.buildings) do
     local priority=b:GetAttribute("MainBase") and -150 or 0
     local distance=(position(b)-state.home).Magnitude+priority
     if distance<nearest then target,nearest=b,distance end
    end
    if not target then for unit in pairs(enemy.units) do target=unit; break end end
   end
  end
  if target then
   for _,unit in ipairs(military) do
    local order=orders[unit]
    -- 正在交戰的部隊只記下進攻目標，打完眼前敵人再前往，避免整波被拉離戰鬥。
    if order and order.kind=="attack" and order.automatic and order.target~=target and order.target.Parent then
     order.objective,order.anchor=target,nil
    else
     issue(unit,"attack",target,true)
     orders[unit].objective=target
    end
   end
  end
 end
end
-- 戰鬥索敵輔助函式留在區塊內，避免主程式區塊超過 Studio 的 200 個 local 暫存器。
-- 索敵步掛在 Strike 表上（Strike.step），不另占主程式區塊的 local。
do
local spatial={}
local CELL=64
-- 數字格鍵避免每次查詢建立字串；地圖最大 1536 studs，格座標遠小於 4096。
local function spatialKey(x,z) return x*8192+z end
local function targetCategory(model)
 if model.Parent==units then return model:GetAttribute("UnitType")=="villager" and "villager" or "military" end
 local data=Config.Buildings[model:GetAttribute("BuildingType")]
 return data and data.damage and model:GetAttribute("Complete") and "defense" or "building"
end
-- 每個索敵步重建一次：位置、擁有者、類別與占地都先讀進純 Lua 表，
-- 之後每個單位掃描候選目標時不再逐一呼叫引擎（原本 N×N 次屬性／位置讀取是大型戰鬥的尖峰）。
local function rebuildSpatial()
 spatial={}
 for _,state in pairs(states) do
  if alive(state) then
   for index,models in ipairs({state.units,state.buildings}) do
    for model in pairs(models) do
     if model.Parent then
      local p=position(model)
      local entry={model=model,state=state,isUnit=index==1,X=p.X,Z=p.Z,category=targetCategory(model)}
      if index==1 then entry.radius=model:GetAttribute("Radius") or Config.UnitCollision.default.radius
      else
       local half=model.PrimaryPart and model.PrimaryPart.Size/2 or Vector3.new(2,2,2)
       entry.halfX,entry.halfZ=half.X,half.Z
      end
      local key=spatialKey(math.floor(p.X/CELL),math.floor(p.Z/CELL))
      local bucket=spatial[key] or {}
      table.insert(bucket,entry)
      spatial[key]=bucket
     end
    end
   end
  end
 end
end
local function targetScore(target,current,preferred)
 return CombatRules.targetScore(distanceTo(target,current),targetCategory(target),COMBAT.tierDistance,preferred)
end
-- 依優先層級與邊緣距離挑選目標；unitsOnly 供防禦建築只射擊單位。
-- 距離算法與 edgePosition 相同：單位取碰撞圓邊緣，建築取占地矩形邊緣。
local function bestEnemy(state,current,radius,preferred,unitsOnly,skip)
 local found,best=nil,math.huge
 local cells=SpatialRules.searchCells(radius,TARGET_HALF_EXTENT,CELL)
 if not cells then return nil end
 local cx,cz=current.X,current.Z
 local x,z=math.floor(cx/CELL),math.floor(cz/CELL)
 local hostile={}
 for dx=-cells,cells do
  for dz=-cells,cells do
   local bucket=spatial[spatialKey(x+dx,z+dz)]
   if bucket then
    for _,entry in ipairs(bucket) do
     if not unitsOnly or entry.isUnit then
      local other=entry.state
      local enemy=hostile[other]
      if enemy==nil then enemy=enemies(state,other); hostile[other]=enemy end
      if enemy then
       local distance
       if entry.isUnit then
        local ox,oz=cx-entry.X,cz-entry.Z
        distance=math.max(0,math.sqrt(ox*ox+oz*oz)-entry.radius)
       else
        local ox=math.max(0,math.abs(cx-entry.X)-entry.halfX)
        local oz=math.max(0,math.abs(cz-entry.Z)-entry.halfZ)
        distance=math.sqrt(ox*ox+oz*oz)
       end
       if distance<=radius and entry.model~=skip and entry.model.Parent then
        local score=CombatRules.targetScore(distance,entry.category,COMBAT.tierDistance,preferred)
        if score and score<best then found,best=entry.model,score end
       end
      end
     end
    end
   end
  end
 end
 return found,best
end
-- 被友軍擋在後排的攻擊者：近戰找「周圍還有空位」的敵人（先看目前目標，再由近到遠），繞到那個空位去打；
-- 遠程改打已在射程內的敵人。玩家手動指定的目標不換人，只繞位。回傳是否找到新的打法。
Strike.flank=function(state,unit,order,current,range,now)
 local body=unit:GetAttribute("Radius") or Config.UnitCollision.default.radius
 local reach=CombatRules.acquisitionRadius(COMBAT.acquisitionRadius,range)
 local cells=reach and SpatialRules.searchCells(reach,TARGET_HALF_EXTENT,CELL)
 if not cells then return false end
 local cx,cz=current.X,current.Z
 local x,z=math.floor(cx/CELL),math.floor(cz/CELL)
 local hostile,found={}, {}
 for dx=-cells,cells do
  for dz=-cells,cells do
   local bucket=spatial[spatialKey(x+dx,z+dz)]
   if bucket then
    for _,entry in ipairs(bucket) do
     if order.automatic or entry.model==order.target then
      local other=entry.state
      local enemy=hostile[other]
      if enemy==nil then enemy=enemies(state,other); hostile[other]=enemy end
      if enemy then
       local ox,oz=cx-entry.X,cz-entry.Z
       local distance=math.sqrt(ox*ox+oz*oz)
       -- 目前目標優先；其餘由近到遠。
       if distance<=reach+TARGET_HALF_EXTENT then table.insert(found,{entry=entry,distance=entry.model==order.target and -1 or distance}) end
      end
     end
    end
   end
  end
 end
 table.sort(found,function(a,b) return a.distance<b.distance end)
 for index=1,math.min(#found,5) do
  local entry=found[index].entry
  local model=entry.model
  if model.Parent then
   local goal=nil
   local usable=false
   if range>20 then
    usable=model~=order.target and distanceTo(model,current)<=range
   else
    local center=position(model)
    local point=ApproachRules.nearest(MeleeRules.candidates(center.X,center.Z,entry.isUnit and entry.radius or entry.halfX,entry.isUnit and entry.radius or entry.halfZ,body,range) or {},cx,cz,nil,function(candidate)
     local spot=Vector3.new(candidate.X,Config.Map.GroundY,candidate.Z)
     return unitPositionClear(unit,spot,body) and staticUnitSegmentClear(unit,spot,spot)
    end)
    if point then goal,usable=Vector3.new(point.X,Config.Map.GroundY,point.Z),true end
   end
   if usable then
    if model~=order.target then
     local previous=order
     issue(unit,"attack",model,true)
     order=orders[unit]
     order.objective,order.anchor=previous.objective,previous.anchor
     order.resumeGather,order.resumeKind=previous.resumeGather,previous.resumeKind
    end
    order.flankGoal,order.flankUntil,order.flankHold=goal,now+4,now+4
    return true
   end
  end
 end
 return false
end
-- 待命或自動攻擊中的軍隊重新評估目標。afterKill 讓剛完成擊殺（含玩家手動指定）的部隊立即接戰，不留空檔。
acquireTarget=function(state,unit,now,afterKill)
 local kind=unit:GetAttribute("UnitType")
 local data=Config.Units[kind]
 if kind=="villager" or kind=="monk" or not data or data.damage<=0 or unit.Parent~=units then return false end
 local order=orders[unit]
 if order and not afterKill and not (order.kind=="attack" and order.automatic) then return false end
 local current=position(unit)
 local radius=CombatRules.acquisitionRadius(COMBAT.acquisitionRadius,unit:GetAttribute("Range") or data.range)
 if not radius then return false end
 -- 剛繞路改打的目標先保留幾秒，不被「最近的敵人」拉回擠不進去的位置。
 if order and order.flankHold and now<order.flankHold and order.target.Parent then return true end
 local clock=actionClocks[unit]
 local skip=clock and clock.skipUntil and now<clock.skipUntil and clock.skipTarget or nil
 local target,score=bestEnemy(state,current,radius,data.preferredTarget,nil,skip)
 if not target then return false end
 local previous=order and order.kind=="attack" and order.target or nil
 if previous==target then return true end
 local currentScore=nil
 if previous and previous.Parent and enemies(state,owner(previous)) then currentScore=targetScore(previous,current,data.preferredTarget) end
 if not CombatRules.shouldSwitch(currentScore,score,COMBAT.retargetMargin) then return true end
 local objective=order and order.objective
 -- 有進攻目標時不設追擊上限；其餘自動接戰都從目前原點計算追擊距離。
 local anchor=not objective and (order and order.anchor or current) or nil
 issue(unit,"attack",target,true)
 orders[unit].objective,orders[unit].anchor=objective,anchor
 return true
end
-- 每 0.2 秒呼叫一次；單位分成三組輪流索敵，每個單位仍是 0.6 秒評估一次，但不會全部擠在同一步。
local turns={of=setmetatable({},{__mode="k"}),next=0,current=0}
Strike.step=function(now)
 rebuildSpatial()
 turns.current=(turns.current+1)%3
 for _,state in pairs(states) do
  if phase~="Playing" then return end
  if alive(state) then
   for unit in pairs(state.units) do
    local mine=turns.of[unit]
    if not mine then mine=turns.next; turns.of[unit]=mine; turns.next=(mine+1)%3 end
    if mine==turns.current then
     local retryAfter=actionClocks[unit] and actionClocks[unit].acquireAfter or 0
     if now>=retryAfter then acquireTarget(state,unit,now) end
     if orders[unit]==nil and unit.Parent==units and unit:GetAttribute("UnitType")=="monk" then Monk.autoHeal(state,unit) end
    end
   end
   for b in pairs(state.buildings) do
    if phase~="Playing" then return end
    local data=Config.Buildings[b:GetAttribute("BuildingType")]
    local interval=data and data.attackInterval or 1.5
    local last=state.defenseLast[b]
    if b.Parent==buildings and data and data.damage and b:GetAttribute("Complete") and now-(last or -math.huge)>=interval then
     local target=bestEnemy(state,position(b),data.range or 64,nil,true)
     -- 城堡（attacksBuildings）：射程內沒有敵方單位時改射擊敵方建築；單位永遠優先。
     if not target and data.attacksBuildings==true then target=bestEnemy(state,position(b),data.range or 64,"buildings",false) end
     if target then
      -- 以射擊間隔累進，不受 0.6 秒索敵週期量化而變慢；中斷過久才重新對齊。
      state.defenseLast[b]=last and now-last<interval+0.75 and last+interval or now
      local impact=position(target)
      local flight=Strike.flight(nil,(impact-position(b)).Magnitude)
      local raw=buildingAttack(state,data)
      -- 駐軍每多一支箭就多結算一次傷害（各自扣護甲），全部射向同一目標。
      local held=Garrison.inside[b]
      local volley=1+(held and held.arrows or 0)
      b:SetAttribute("AttackPosition",impact)
      b:SetAttribute("AttackFlight",flight)
      b:SetAttribute("AttackVolley",volley)
      b:SetAttribute("LastAttack",now)
      Strike.land(b,flight,function(at)
       for _=1,volley do
        if not target.Parent then break end
        damage(target,raw,b,at)
       end
      end)
     end
    end
   end
  end
 end
end
end
-- 自動工作：只處理真人玩家且已開啟的村民；AI 經濟仍由 aiStep 決定。
-- 函式放在區塊內並掛在 AutoWork 表上，避免增加主程式區塊的 local 數量。
do
local AUTO=Config.AutoWork
local function entryFor(unit)
 local entry=AutoWork.units[unit]
 if not entry then entry={}; AutoWork.units[unit]=entry end
 return entry
end
local function skipped(entry,target,now)
 local expiry=entry.blocked and entry.blocked[target]
 if expiry and now>=expiry then entry.blocked[target]=nil; return false end
 return expiry~=nil
end
local function enabled(state)
 return state and not state.ai and state.autoWork~=false and alive(state)
end
local function nearbySite(state,pos,entry,now)
 local found,best=nil,AUTO.buildRadius
 for b,item in pairs(construction) do
  if item.state==state and b.Parent==buildings and not b:GetAttribute("Complete") and not skipped(entry,b,now) then
   local d=distanceTo(b,pos)
   if d<=best then found,best=b,d end
  end
 end
 return found
end
-- 單次掃描取得半徑內各資源最近的目標；已有人耕作的農田不重複指派。
local function nearbyResources(state,unit,pos,entry,now,farmUsed)
 local nearest,distance={},{}
 local radius=AUTO.gatherRadius
 for resource in pairs(managedResources) do
  if resource.Parent==resources and (resource:GetAttribute("Amount") or 0)>0 then
   local key=resource:GetAttribute("ResourceType")
   if key then
    local d=(position(resource)-pos).Magnitude
    if d<=radius and d<(distance[key] or math.huge) and not skipped(entry,resource,now) then nearest[key],distance[key]=resource,d end
   end
  end
 end
 for b in pairs(state.buildings) do
  if not farmUsed[b] and AutoWork.farmUsable(state,b,unit) and not skipped(entry,b,now) then
   local d=distanceTo(b,pos)
   if d<=radius and d<(distance.food or math.huge) then nearest.food,distance.food=b,d end
  end
 end
 return nearest
end
local function summary(state)
 local context={villagers=0,gathering={food=0,wood=0,gold=0,stone=0},farmUsed={}}
 for unit in pairs(state.units) do
  if unit.Parent==units and unit:GetAttribute("UnitType")=="villager" then
   context.villagers+=1
   local order=orders[unit]
   if order and (order.kind=="gather" or order.kind=="deliver") then
    local key=order.kind=="gather" and order.target:GetAttribute("ResourceType") or unit:GetAttribute("CarryType")
    if context.gathering[key] then context.gathering[key]+=1 end
    if order.kind=="gather" and order.target.Parent==buildings then context.farmUsed[order.target]=true end
   end
  end
 end
 return context
end
local function assign(state,unit,context,now)
 local entry=entryFor(unit)
 local pos=position(unit)
 local carrying=unit:GetAttribute("Carrying") or 0
 local choice={site=nearbySite(state,pos,entry,now),carrying=carrying}
 if not choice.site and carrying>0 then choice.dropoff=nearestDropoff(state,pos,unit:GetAttribute("CarryType")) end
 if not choice.site and carrying<=0 then
  choice.nearby=nearbyResources(state,unit,pos,entry,now,context.farmUsed)
  local general=AIWorkerRules.resourcePriorities(context.villagers,context.gathering,state.actor:GetAttribute("food") or 0)
  local priorities=table.clone(context.preferred or {})
  for _,key in ipairs(general) do if not table.find(priorities,key) then table.insert(priorities,key) end end
  choice.priorities=priorities
 end
 local action,target,key=AutoWorkRules.choose(choice)
 if action=="build" then issue(unit,"build",target)
 elseif action=="deliver" then beginDelivery(state,unit,nil,target)
 elseif action=="gather" then
  issue(unit,"gather",target)
  context.gathering[key]=(context.gathering[key] or 0)+1
  if target.Parent==buildings then context.farmUsed[target]=true end
 else return false end
 if orders[unit] then orders[unit].autoWork=true end
 entry.idleSince=nil
 return true
end
AutoWork.hold=function(unit)
 local entry=entryFor(unit)
 entry.hold,entry.idleSince=true,nil
end
-- 完工後立刻接續：附近工地優先，經濟建築則採集它收取的資源。
AutoWork.afterBuild=function(state,unit,building)
 if not enabled(state) or unit.Parent~=units then return false end
 local context=summary(state)
 local data=Config.Buildings[building:GetAttribute("BuildingType")]
 context.preferred=data and AutoWorkRules.dropoffPreference(data.dropoff)
 return assign(state,unit,context,os.clock())
end
-- 耗盡的農田重新播種：優先使用磨坊預置（已付款）；否則在玩家下令或允許自動播種時扣木材。
AutoWork.reseed=function(state,farm,manual)
 if not AutoWork.isFarm(farm) or not farm:GetAttribute("Complete") or (farm:GetAttribute("Amount") or 0)>0 then return false end
 local cost=Config.Buildings.Farm.cost
 local queued=state.actor:GetAttribute("FarmQueue") or 0
 local source=AutoWork.farmRules.reseedSource(queued,manual,AutoWork.autoReseed(state))
 if source=="queue" then
  state.actor:SetAttribute("FarmQueue",queued-1)
  if state.farmReceipts then table.remove(state.farmReceipts,1) end
 elseif source=="wood" then
  if not Economy.spend(state.actor,cost) then
   if manual then notify(state.actor,"重新播種所需資源不足："..Grid.costText(cost),"Error") end
   return false
  end
  recordReport(state,"spend",{cost=cost})
 else return false end
 farm:SetAttribute("Amount",farm:GetAttribute("MaxAmount") or 0)
 AutoWork.farmLook(farm)
 notify(state.actor,source=="queue" and ("農田已用磨坊的預置重新播種，剩餘預置 "..(queued-1).." 塊。") or ("農田已重新播種："..Grid.costText(cost)))
 return true
end
-- 磨坊預置農田：先付款，之後農田耗盡時自動重新播種；取消時全額退回。
AutoWork.queueFarm=function(state,mill,add)
 if not isOwned(state,mill,buildings) or mill:GetAttribute("BuildingType")~="Mill" then return false end
 if not mill:GetAttribute("Complete") then notify(state.actor,"建築尚未完工。"); return false end
 local cost=Config.Buildings.Farm.cost
 local queued=state.actor:GetAttribute("FarmQueue") or 0
 if add then
  if not AutoWork.farmRules.canQueue(queued,Config.Farms.queueLimit) then notify(state.actor,"預置農田已達上限 "..Config.Farms.queueLimit.." 塊。","Error"); return false end
  if not Economy.spend(state.actor,cost) then notify(state.actor,"預置農田所需資源不足："..Grid.costText(cost),"Error"); return false end
  state.farmReceipts=state.farmReceipts or {}
  table.insert(state.farmReceipts,recordReport(state,"spend",{cost=cost,refundable=true}) or false)
  state.actor:SetAttribute("FarmQueue",queued+1)
 else
  if not AutoWork.farmRules.canUnqueue(queued) then notify(state.actor,"目前沒有預置的農田。"); return false end
  refund(state.actor,cost)
  local receipt=state.farmReceipts and table.remove(state.farmReceipts)
  if receipt then recordReport(state,"refund",{spendId=receipt}) end
  state.actor:SetAttribute("FarmQueue",queued-1)
 end
 return true
end
AutoWork.step=function(now)
 local budget=AUTO.maxPerStep
 for _,state in pairs(states) do
  if budget<=0 or phase~="Playing" then return end
  if enabled(state) then
   local ready={}
   for unit in pairs(state.units) do
    if unit.Parent==units and orders[unit]==nil and unit:GetAttribute("UnitType")=="villager" and (unit:GetAttribute("HP") or 0)>0 then
     local entry=entryFor(unit)
     entry.idleSince=entry.idleSince or now
     if AutoWorkRules.idleReady(entry.idleSince,now,AUTO.idleDelay,entry.nextCheck,entry.hold) then table.insert(ready,unit) end
    end
   end
   if #ready>0 then
    local context=summary(state)
    for _,unit in ipairs(ready) do
     if budget<=0 then break end
     budget-=1
     if not assign(state,unit,context,now) then entryFor(unit).nextCheck=now+AUTO.retryInterval end
    end
   end
   -- 無人施工的工地：施工村民被調走或陣亡後，附近沒有閒置村民就會永遠停在「等待村民」。
   -- 等待 siteDelay 秒後重新派工；只找閒置、採集或交貨中的村民，不動玩家指定待命、移動或修復的村民。
   for b,item in pairs(construction) do
    if budget<=0 then break end
    if item.state==state and b.Parent==buildings and not b:GetAttribute("Complete") then
     local assigned,candidates=0,{}
     local sitePosition=position(b)
     for unit in pairs(state.units) do
      if unit.Parent==units and canBuildWorker(state,unit) then
       local order=orders[unit]
       if order and order.kind=="build" and order.target==b then assigned+=1
       elseif (order==nil or order.kind=="gather" or order.kind=="deliver") and not entryFor(unit).hold and not skipped(entryFor(unit),b,now) then
        table.insert(candidates,{unit=unit,distance=(position(unit)-sitePosition).Magnitude,idle=order==nil,building=false})
       end
      end
     end
     if assigned>0 then item.waitingSince=nil
     else
      item.waitingSince=item.waitingSince or now
      if AutoWorkRules.siteNeedsBuilders(assigned,item.waitingSince,now,AUTO.siteDelay or 4,item.nextDispatch) then
       local data=Config.Buildings[b:GetAttribute("BuildingType")]
       local count=data and AutoWorkRules.builderCount(data.size.X,data.size.Y,Config.Construction.maxSelectedWorkers) or 1
       for _,unit in ipairs(AutoWorkRules.pickBuilders(candidates,math.max(1,count),AUTO.busyPenalty)) do
        budget-=1
        issue(unit,"build",b)
        if orders[unit] then orders[unit].autoWork=true end
       end
       item.nextDispatch=now+AUTO.retryInterval
      end
     end
    end
   end
  end
 end
end
end
local function productionStep(dt)
 local now=os.clock()
 for b,item in pairs(construction) do
  if b.Parent~=buildings or not alive(item.state) then construction[b]=nil
  else
   local builders,working=0,{}
   for unit in pairs(item.state.units) do
    local order=orders[unit]
    if canBuildWorker(item.state,unit) and order and ConstructionRules.isWorking(unit:GetAttribute("UnitType"),unit:GetAttribute("HP"),true,
     order.kind,order.target==b,distanceTo(b,position(unit)),Config.Construction.workRange)
     and interactionLineClear(b,position(unit)) then builders+=1; table.insert(working,unit) end
   end
   b:SetAttribute("BuilderCount",builders)
   b:SetAttribute("ConstructionStatus",builders>0 and "施工中" or "等待村民")
   if builders>0 then
    local nextWork,work,complete=ConstructionRules.stepWork(item.work,item.duration,builders,dt,Config.Construction.extraWorkerRate)
    if work>0 then
     for _,unit in ipairs(working) do
      unit:SetAttribute("WorkKind","build")
      if UnitRules.takeAction(actionClocks,unit,"workFeedback",now,1) then unit:SetAttribute("LastWork",now) end
     end
    end
    item.work=nextWork
    local max=b:GetAttribute("MaxHP")
    local health=ConstructionRules.addWorkHP(b:GetAttribute("HP") or 0,max,work,item.duration)
    if health then b:SetAttribute("HP",health) end
    b:SetAttribute("ConstructionProgress",item.work/item.duration)
    b:SetAttribute("ConstructionRemaining",math.ceil(item.duration-item.work))
    if complete then
     construction[b]=nil
     b:SetAttribute("Complete",true)
     b:SetAttribute("UnderConstruction",false)
     b:SetAttribute("BuilderCount",0)
     b:SetAttribute("ConstructionStatus","已完工")
     b:SetAttribute("ConstructionProgress",1)
     b:SetAttribute("ConstructionRemaining",0)
     -- 整排放置的牆段不逐段提示完工。
     if not Config.Buildings[b:GetAttribute("BuildingType")].line then notify(item.state.actor,nil,"ConstructionComplete") end
     if b:GetAttribute("BuildingType")=="Farm" then b:SetAttribute("Amount",b:GetAttribute("MaxAmount") or 0); AutoWork.farmLook(b) end
     recordReport(item.state,"building",{subjectId=reportSubject(b)})
     population(item.state)
     if b:GetAttribute("BuildingType")=="House" then telemetry:Fact(item.state.actor,"firsthouse") end
     if Config.Buildings[b:GetAttribute("BuildingType")].gate then Walls.activate(item.state,b) end
     for unit in pairs(item.state.units) do
      local order=orders[unit]
      if order and order.kind=="build" and order.target==b then
       local following=Walls.nextSite(unit,order.buildQueue)
       if b:GetAttribute("BuildingType")=="Farm" then issue(unit,"gather",b)
       elseif following then issue(unit,"build",following); orders[unit].buildQueue=order.buildQueue
       else stop(unit); AutoWork.afterBuild(item.state,unit,b) end
      end
     end
    end
   end
  end
 end
 for b,queue in pairs(training) do
  local item=queue[1]
  if b.Parent~=buildings or not item or not alive(item.state) then training[b]=nil
  else
   item.remaining=math.max(0,item.remaining-dt)
   if item.remaining<=0 then
    local _,cap=population(item.state)
    local liveUnits=Garrison.count(item.state)
    for unit in pairs(item.state.units) do if unit.Parent==units then liveUnits+=1 end end
    local spawn=UnitRules.canCompletePopulation(liveUnits,cap) and freeSpawn(b,item.kind)
    if spawn then
     local ok,model=pcall(makeUnit,item.state,item.kind,spawn)
     if not ok then
      warn("[RTS] 單位生成失敗："..tostring(model))
      refund(item.state.actor,item.cost)
      if item.reportReceipt then recordReport(item.state,"refund",{spendId=item.reportReceipt}) end
     else
      recordReport(item.state,"train",{subjectId=reportSubject(model),role=item.kind=="villager" and "villager" or "military",spendId=item.reportReceipt})
      item.state.actor:SetAttribute("TrainedUnits",(item.state.actor:GetAttribute("TrainedUnits") or 0)+1)
      if item.kind=="villager" then item.state.actor:SetAttribute("TrainedVillagers",(item.state.actor:GetAttribute("TrainedVillagers") or 0)+1) end
      telemetry:Fact(item.state.actor,"firsttrain")
      notify(item.state.actor,nil,"Train")
      if item.kind=="tradeCart" then Relic.trade.home[model]=b end
      applyRally(item.state,b,model,item.kind)
     end
     table.remove(queue,1)
     b:SetAttribute("QueueRevision",(b:GetAttribute("QueueRevision") or 0)+1)
     if #queue==0 then training[b]=nil end
     population(item.state)
    end
   end
   queueAttributes(b)
  end
 end
 for b,item in pairs(researching) do
  if b.Parent~=buildings or not alive(item.state) then cancelResearch(b,item.state)
  else
   item.remaining=math.max(0,item.remaining-dt)
   b:SetAttribute("ResearchRemaining",math.ceil(item.remaining))
   b:SetAttribute("ResearchProgress",1-item.remaining/item.duration)
   if item.remaining<=0 then
    local state,data=item.state,Config.Technologies[item.key]
    state.technologies[item.key],state.pendingTech[item.key]=true,nil
    state.actor:SetAttribute("Tech_"..item.key,true)
    local modifiers=state.modifiers
    if data.unitClass then
     modifiers=state.classModifiers[data.unitClass] or {}
     state.classModifiers[data.unitClass]=modifiers
    end
    for key,value in pairs(data.effect or {}) do
     if state.modifiers[key]~=nil then modifiers[key]=(modifiers[key] or 0)+value end
    end
    if data.upgrade and ProductionRules.applyUpgrade(state.unitModifiers,state.unitNames,data.upgrade,Config.Units) then
     state.actor:SetAttribute("UnitName_"..data.upgrade.unit,state.unitNames[data.upgrade.unit])
    end
    state.statsCache=nil
    if data.effect and data.effect.farmCapacity then
     for farm in pairs(state.buildings) do
      if farm:GetAttribute("BuildingType")=="Farm" then
       -- 耗盡的農田維持耗盡，重新播種時才取得新容量。
       if farm:GetAttribute("Complete") and (farm:GetAttribute("Amount") or 0)>0 then farm:SetAttribute("Amount",(farm:GetAttribute("Amount") or 0)+data.effect.farmCapacity) end
       farm:SetAttribute("MaxAmount",(farm:GetAttribute("MaxAmount") or 0)+data.effect.farmCapacity)
      end
     end
    end
    for unit in pairs(state.units) do refreshUnit(state,unit) end
    for building in pairs(state.buildings) do
     if building.Parent==buildings then refreshBuildingStats(state,building) end
    end
    researching[b]=nil
    b:SetAttribute("Research",nil)
    b:SetAttribute("ResearchRemaining",nil)
    b:SetAttribute("ResearchProgress",nil)
    notify(state.actor,data.name.." 研究完成。","Research")
   end
  end
 end
 for _,state in pairs(states) do if alive(state) then Relic.income(state,dt) end end
 for _,state in pairs(states) do
  local item=state.advancing
  if alive(state) and item then
   if item.building.Parent~=buildings then cancelResearch(item.building,state)
   else
    item.remaining=math.max(0,item.remaining-dt)
    local progress=1-item.remaining/item.duration
    state.actor:SetAttribute("AgeProgress",progress)
    state.actor:SetAttribute("AgeRemaining",math.ceil(item.remaining))
    item.building:SetAttribute("ResearchProgress",progress)
    item.building:SetAttribute("ResearchRemaining",math.ceil(item.remaining))
    if item.remaining<=0 then
     state.actor:SetAttribute("Age",item.age)
     state.actor:SetAttribute("AgeProgress",0)
     state.actor:SetAttribute("AgeRemaining",0)
     item.building:SetAttribute("Research",nil)
     item.building:SetAttribute("ResearchProgress",nil)
     item.building:SetAttribute("ResearchRemaining",nil)
     state.advancing=nil
     announce(actorName(state.actor).." 已進入"..Config.Ages[item.age].name.."。","Age")
    end
   end
  end
 end
end
local orderStep
do
-- 先複製本步要處理的單位：步驟中反擊、改派會對 orders 新增鍵，邊走訪邊新增會讓部分單位被跳過或重複處理。
local pending={}
-- 每步最多幾個單位重新找繞路位置；其餘留到下一步，避免整支軍隊同一步一起搜尋造成尖峰。
local FLANK_PER_STEP=6
orderStep=function(dt,now)
 local flankBudget=FLANK_PER_STEP
 local profile=unitCollisionIndex.profile
 table.clear(pending)
 for unit in pairs(orders) do table.insert(pending,unit) end
 for _,unit in ipairs(pending) do
  if phase~="Playing" then return end
  local order=orders[unit]
  if not order then continue end
  local state=owner(unit)
  if unit.Parent~=units or not alive(state) then orders[unit]=nil; continue end
  local target=order.target
  local farming=order.kind=="gather" and AutoWork.isFarm(target)
  if farming then
   if not AutoWork.claimFarm(target,unit) then
    -- 這塊田已有村民：改派最近的空閒農田或其他食物來源。
    local replacement=nearestResource(state,position(unit),"food",unit)
    local manual,auto=order.manual,order.autoWork
    if replacement then issue(unit,"gather",replacement); orders[unit].autoWork=auto else stop(unit) end
    if manual then notify(state.actor,replacement and "這塊農田已有村民耕作，已改派到其他食物來源。" or "這塊農田已有村民耕作，一塊農田只能有一位村民。") end
    continue
   end
   -- 耗盡的農田：有磨坊預置或允許自動播種時重新播種後繼續耕作，否則照一般耗盡處理。
   if (target:GetAttribute("Amount") or 0)<=0 then AutoWork.reseed(state,target) end
   order.manual=nil
  end
  if order.kind~="move" and (not target.Parent or (order.kind=="gather" and (target:GetAttribute("Amount") or 0)<=0)) then
   if order.kind=="gather" then
    local key=target:GetAttribute("ResourceType")
    if (unit:GetAttribute("Carrying") or 0)>0 then beginDelivery(state,unit,target)
    else local replacement=nearestResource(state,position(unit),key,unit); if replacement then issue(unit,"gather",replacement) else stop(unit) end end
   elseif order.kind=="deliver" then beginDelivery(state,unit,order.returnTarget,nil,order.returnKind)
   elseif order.kind=="attack" then
    if order.resumeGather or not acquireTarget(state,unit,now,true) then finishAttack(state,unit,order) end
   else stop(unit) end
   continue
  end
  if order.kind=="attack" and not enemies(state,owner(target)) then
   if order.resumeGather or not acquireTarget(state,unit,now,true) then finishAttack(state,unit,order) end
   continue
  end
  if order.kind=="convert" and (target.Parent~=units or not enemies(state,owner(target))) then stop(unit); continue end
  if order.kind=="heal" and (target.Parent~=units or not owner(target) or enemies(state,owner(target))
   or (target:GetAttribute("HP") or 0)>=(target:GetAttribute("MaxHP") or 0)) then stop(unit); continue end
  if order.kind=="deliver" and (not isOwned(state,target,buildings) or not target:GetAttribute("Complete") or not acceptsResource(target,unit:GetAttribute("CarryType"))) then
   beginDelivery(state,unit,order.returnTarget,nil,order.returnKind); continue
  end
  if order.kind=="build" and (not canBuildWorker(state,unit) or not isOwned(state,target,buildings) or not construction[target] or target:GetAttribute("Complete")) then stop(unit); continue end
  if order.kind=="garrison" and not isOwned(state,target,buildings) then stop(unit); continue end
  if order.kind=="relic" and (not Relic.isRelic(target) or unit:GetAttribute("CarryingRelic")==true) then stop(unit); continue end
  if order.kind=="relicStore" and (not Relic.storeTarget(state,target) or unit:GetAttribute("CarryingRelic")~=true) then stop(unit); continue end
  if order.kind=="trade" and not Relic.trade.valid(state,unit,order) then stop(unit); notify(state.actor,"貿易路線上的市集已失效，貿易車停止。"); continue end
  local current=position(unit)
  local stats=unitStats(state,unit:GetAttribute("UnitType"),order.kind=="gather" and target:GetAttribute("ResourceType") or nil)
  -- 農田可以踩踏：村民走進田中央耕作，其餘目標停在外緣。
  local destination=order.kind=="move" and target or farming and position(target) or edgePosition(target,current)
  -- 到位誤差小於陣形間隙，避免先停止的前排占住後排目的地。
  local range=order.kind=="move" and Config.Formations.arrivalTolerance or (order.kind=="attack" or order.kind=="convert") and stats.range or order.kind=="heal" and Monk.config.healRange or order.kind=="build" and Config.Construction.workRange or farming and Config.Farms.workRange or order.kind=="garrison" and Garrison.config.enterRange or 5
  local inRange=(destination-current).Magnitude<=range
  if order.kind=="attack" and order.anchor and not order.objective and not inRange
   and CombatRules.beyondLeash(order.anchor.X,order.anchor.Z,current.X,current.Z,COMBAT.leashDistance) then
   -- 自動追擊超出上限：村民回去採集，軍隊回到原點，短暫不再索敵以免來回拉扯。
   actionClocks[unit]=actionClocks[unit] or {}
   actionClocks[unit].acquireAfter=now+COMBAT.leashCooldown
   if order.resumeGather then finishAttack(state,unit,order) else issue(unit,"move",order.anchor) end
   continue
  end
  if farming then order.approachGoal=nil
  elseif ApproachRules.isWork(order.kind) then
   if inRange and interactionLineClear(target,current) then
    if order.approachGoal then order.path=nil end
    order.approachGoal=nil
   else
    inRange=false
    if not interactionApproach(unit,order,target,current,range,now) then
     unreachable(unit,order,"目標周圍找不到可抵達的工作位置，請調整位置後重試。")
     continue
    end
   end
  elseif order.kind=="attack" and range<=20 and (inRange or order.approachGoal or order.approachBlacklist) then
   -- 攻擊通道剛確認暢通時短暫沿用結果，貼身纏鬥不必每 0.1 秒各打一次射線。
   if now<(order.lineClearUntil or 0) or interactionLineClear(target,current) then
    if now>=(order.lineClearUntil or 0) then order.lineClearUntil=now+0.4 end
    if order.approachGoal then order.path=nil end
    order.approachGoal=nil
   else
    inRange=false
    if not interactionApproach(unit,order,target,current,range,now) then
     actionClocks[unit]=actionClocks[unit] or {}
     actionClocks[unit].acquireAfter=now+3
     finishAttack(state,unit,order)
     if not order.automatic then notify(state.actor,"目標受到障礙保護，找不到可抵達的近戰攻擊位置。") end
     continue
    end
   end
  end
  if inRange and order.kind=="garrison" then Garrison.enter(state,unit,target); continue end
  if inRange and order.kind=="relic" then Relic.pickup(state,unit,target); continue end
  if inRange and order.kind=="relicStore" then Relic.store(state,unit,target); continue end
  if inRange and order.kind=="trade" then Relic.trade.arrive(state,unit,order); continue end
  if inRange then
   order.path=nil
   unit:SetAttribute("Animation",order.kind=="attack" and "Attack" or (order.kind=="gather" or order.kind=="build" or order.kind=="repair" or order.kind=="convert" or order.kind=="heal") and "Work" or "Idle")
   unit:SetAttribute("WorkKind",order.kind=="gather" and target:GetAttribute("ResourceType") or order.kind=="build" and "build" or order.kind=="repair" and "repair" or nil)
   -- 到位後面向目標並換上對應工具；只轉向，不改變權威位置。
   if order.kind~="move" and order.kind~="deliver" then
    Factory.face(unit,position(target))
    Factory.workTool(unit,unit:GetAttribute("WorkKind"),target)
   end
   if order.kind=="move" then stop(unit,true)
   elseif order.kind=="deliver" then
    local key,carrying=unit:GetAttribute("CarryType"),unit:GetAttribute("Carrying") or 0
    if carrying>0 and ({food=true,wood=true,gold=true,stone=true})[key] then
     state.actor:SetAttribute(key,(state.actor:GetAttribute(key) or 0)+carrying)
     state.actor:SetAttribute("DeliveredResources",(state.actor:GetAttribute("DeliveredResources") or 0)+carrying)
     recordReport(state,"delivery",{resource=key,amount=carrying})
     telemetry:Fact(state.actor,"firstdeliver")
     unit:SetAttribute("Carrying",0)
     unit:SetAttribute("CarryType","")
     unit:SetAttribute("LastDelivery",now)
    end
    local returnTarget=order.returnTarget
    if not returnTarget or not returnTarget.Parent or ((returnTarget:GetAttribute("Amount") or 0)<=0 and not (AutoWork.isFarm(returnTarget) and AutoWork.farmUsable(state,returnTarget,unit))) then returnTarget=nearestResource(state,current,order.returnKind or key,unit) end
    if returnTarget then issue(unit,"gather",returnTarget) else stop(unit) end
   elseif order.kind=="gather" and UnitRules.takeAction(actionClocks,unit,"gather",now,1) then
    local key=target:GetAttribute("ResourceType")
    local carrying=unit:GetAttribute("Carrying") or 0
    local rate=GatheringRules.gatherRate(stats.gather,target:GetAttribute("GatherMultiplier"))
    local amount=GatheringRules.takeAmount(target:GetAttribute("Amount") or 0,carrying,stats.carry,rate)
    target:SetAttribute("Amount",math.max(0,(target:GetAttribute("Amount") or 0)-amount))
    if target.Parent==resources then Factory.refreshStage(target) end
    if target.Parent==buildings and (target:GetAttribute("Amount") or 0)<=0 and not AutoWork.reseed(state,target) then AutoWork.farmLook(target) end
    unit:SetAttribute("CarryType",key)
    unit:SetAttribute("Carrying",carrying+amount)
    if amount>0 then unit:SetAttribute("LastWork",now) end
    if carrying+amount>=stats.carry or (target:GetAttribute("Amount") or 0)<=0 then beginDelivery(state,unit,target) end
    if (target:GetAttribute("Amount") or 0)<=0 and target.Parent==resources then managedResources[target]=nil; target:Destroy() end
   elseif order.kind=="attack" and UnitRules.takeAction(actionClocks,unit,"attack",now,stats.interval,0.3) then
    local kind=unit:GetAttribute("UnitType")
    local data=Config.Units[kind]
    local impact=position(target)
    local raw=Strike.amount(state,unit,target)
    local melee=range<=20
    local stone=not melee and COMBAT.projectileKinds[kind]=="stone"
    local flight=melee and (COMBAT.windup[kind] or COMBAT.windup.default) or Strike.flight(kind,(impact-current).Magnitude)
    local contact=nil
    if melee then
     -- 武器要碰到的點：建築取最近的牆面，單位取碰撞圓內側的身體。
     contact=edgePosition(target,current)
     if target.Parent==units then contact=contact:Lerp(impact,0.5) end
    end
    unit:SetAttribute("AttackPosition",impact)
    unit:SetAttribute("AttackContact",contact)
    unit:SetAttribute("AttackFlight",flight)
    unit:SetAttribute("LastAttack",now)
    Strike.land(unit,flight,function(at)
     if target.Parent then
      local hit=true
      if melee then hit=CombatRules.connects(distanceTo(target,position(unit)),range,COMBAT.meleeTolerance)
      elseif stone then hit=CombatRules.landsOn(target.Parent==buildings,(position(target)-impact).Magnitude,math.max(data.splash or 0,COMBAT.projectile.stoneRadius)) end
      if hit then damage(target,raw,unit,at) end
     end
     if data.splash and data.splash>0 then
      for _,enemy in pairs(states) do
       if enemies(state,enemy) then
        for other in pairs(enemy.units) do if other~=target and other.Parent and (position(other)-impact).Magnitude<=data.splash then damage(other,stats.damage*0.5,unit,at) end end
       end
      end
     end
    end)
   elseif order.kind=="convert" then Monk.step(state,unit,order,target,now)
   elseif order.kind=="heal" and UnitRules.takeAction(actionClocks,unit,"heal",now,1) then
    local maxHP=target:GetAttribute("MaxHP") or 0
    local healed=Monk.rules.heal(target:GetAttribute("HP") or 0,maxHP,Monk.config.healRate,1)
    target:SetAttribute("HP",healed)
    if healed>=maxHP then stop(unit) end
   elseif order.kind=="repair" and UnitRules.takeAction(actionClocks,unit,"repair",now,1) then
    if (target:GetAttribute("HP") or 0)>=(target:GetAttribute("MaxHP") or 0) then stop(unit)
    elseif Economy.spend(state.actor,{wood=1}) then
     target:SetAttribute("HP",math.min(target:GetAttribute("MaxHP"),target:GetAttribute("HP")+15))
     unit:SetAttribute("LastWork",now)
     recordReport(state,"spend",{cost={wood=1}})
    end
   end
  else
   -- 攻擊者被友軍擋住超過半秒：改打有空位的敵人或繞到空位；找不到就拉長重試間隔。
   if flankBudget>0 and order.kind=="attack" and order.crowdedSince and now-order.crowdedSince>=0.5 and now>=(order.nextFlank or 0) then
    flankBudget-=1
    local flankStarted=profile and os.clock()
    local found=Strike.flank(state,unit,order,current,range,now)
    if profile then profile.flank+=os.clock()-flankStarted; profile.flanks+=1 end
    order.flankTries=found and 0 or (order.flankTries or 0)+1
    order.nextFlank=now+math.min(4,1.5+order.flankTries)
    if orders[unit]~=order then continue end
   end
   local goal=order.approachGoal or destination
   if order.flankGoal then
    if now>=order.flankUntil or (order.flankGoal-current).Magnitude<0.5 then order.flankGoal=nil
    elseif not order.approachGoal then goal=order.flankGoal end
   end
   if order.kind~="move" and not order.approachGoal and not order.flankGoal then
    local outward=current-destination
    if outward.Magnitude>0.01 then
     local standoff=destination+outward.Unit*math.max(1,range-1)
     -- 僧侶的停步點若落在建築或障礙內就無法抵達（Studio 實測卡在伐木場內的點）；改朝目標本身尋路，
     -- 途中進入射程即開始治療／招降。目標移動超過 4 studs 才重新檢查；其他指令維持原本的停步點。
     if order.kind~="heal" and order.kind~="convert" then order.standoffClear,order.standoffFrom=true,nil
     elseif not order.standoffFrom or (order.standoffFrom-destination).Magnitude>4 then
      local r,h=unit:GetAttribute("Radius") or 2,unit:GetAttribute("CollisionHeight") or 5
      order.standoffFrom=destination
      order.standoffClear=#obstacleParts(standoff+Vector3.new(0,h/2,0),Vector3.new(r*2,h,r*2))==0
     end
     if order.standoffClear then goal=standoff end
    end
   end
   local moveStarted=profile and os.clock()
   moveToward(unit,order,goal,stats.speed,dt,now)
   if profile then profile.move+=os.clock()-moveStarted; profile.moves+=1 end
  end
 end
end
end

workspace:SetAttribute("Winner","")
workspace:SetAttribute("WinnerId",0)
workspace:SetAttribute("WinnerTeamId",0)
workspace:SetAttribute("TeamMode","")
workspace:SetAttribute("LobbyTeamPreviewReady",false)
for index=1,3 do workspace:SetAttribute("LobbyAITeam_"..index,nil) end
workspace:SetAttribute("MatchTime",0)
workspace:SetAttribute("VictoryMode","Conquest")
workspace:SetAttribute("Sandbox",false)
workspace:SetAttribute("CommerceEnabled",false)
workspace:SetAttribute("CommercePolicy",Config.Commerce.policyText)
workspace:SetAttribute("ProfilesEnabled",profiles.enabled)
workspace:SetAttribute("AnalyticsEnabled",telemetry.enabled)
game:BindToClose(function() profiles:FlushAll() end)
workspace:SetAttribute("PlaceRole",Travel.role)
if Travel.role=="Match" then
 -- 對戰伺服器關閉（更新或錯誤）時盡量把仍在場的玩家送回大廳。
 game:BindToClose(function()
  local players=Players:GetPlayers()
  if #players>0 then Travel.service:Return(players) end
 end)
 setPhase("Starting")
 Travel.load()
else
 setPhase("Lobby")
end
publishLobbySettings()
-- The lobby sits outside the RTS battlefield. Generate resources only after
-- the host's confirmed settings enter Starting, before any faction is spawned.
for roomId,portal in pairs(lobbyWorld.Portals) do
 portal.Prompt.Triggered:Connect(function(player)
  local state=states[player]
  if state then queueJoin(state,roomId) end
 end)
end
for _,player in ipairs(Players:GetPlayers()) do join(player) end
do
local stepTimers={accumulated=0,combat=0,ai=0,attributes=0,lobby=0,auto=0}
-- Studio 專用戰鬥壓力探針：tests/battle-stress.server.lua 用來直接生成對戰部隊並讀取每步耗時。
-- 正式伺服器不建立；BindableFunction 留在 ServerScriptService，不複製給客戶端。
if RunService:IsStudio() then
 local probe=Instance.new("BindableFunction")
 probe.Name="RTSBattleProbe"
 probe.OnInvoke=function(action,a,b,c)
  if phase~="Playing" then return nil end
  if action=="spawn" then
   local state=byId[a]
   if not alive(state) or type(b)~="string" or not Config.Units[b] or not validPosition(c) then return nil end
   return makeUnit(state,b,c)
  elseif action=="build" then
   -- 直接放一座已完工的建築（不扣資源、不看時代）；占地仍須在界內且沒有障礙。
   local state,data=byId[a],type(b)=="string" and Config.Buildings[b] or nil
   if not alive(state) or not data or not validPosition(c) then return nil end
   local pos=Grid.snap(c,data.size)
   if not validPosition(pos) or not Grid.inBounds(pos,data.size) or not placementClear(pos,data) then return nil end
   return makeBuilding(state,b,pos,true)
  elseif action=="attack" then
   if typeof(a)~="Instance" or a.Parent~=units or not isTarget(b) or not enemies(owner(a),owner(b)) then return false end
   issue(a,"attack",b,true)
   orders[a].objective=b
   return true
  elseif action=="remove" then
   if typeof(a)=="Instance" and a.Parent==units then destroyModel(a) end
   return true
  elseif action=="timings" then
   local result=stepTimers.probe or {}
   local orderCount=0
   for _ in pairs(orders) do orderCount+=1 end
   result.orders,result.pathTasks=orderCount,pathTasks
   result.profile=unitCollisionIndex.profile
   unitCollisionIndex.profile={move=0,moves=0,flank=0,flanks=0,pivot=0,pivots=0,neighbor=0,neighbors=0}
   stepTimers.probe={order={count=0,sum=0,worst=0},combat={count=0,sum=0,worst=0},step={count=0,sum=0,worst=0}}
   return result
  end
  return nil
 end
 probe.Parent=script.Parent
end
RunService.Heartbeat:Connect(function(dt)
 do
  stepTimers.lobby+=dt
  if stepTimers.lobby>=Config.Lobby.scanInterval then
   stepTimers.lobby=0
   Travel.step()
   for _,state in ipairs(humanStates()) do
    if state.configureRejected then
     state.configureRejected=false
     configureLobbyComplete(state.actor,nil,true)
    end
    if state.inLobby and not state.playing then
     if state.queued then
      if not lobbyWorld:ContainsPortal(state.actor,state.roomId) then queueLeave(state) end
     else
      local roomId=lobbyWorld:PortalAt(state.actor)
      if roomId then queueJoin(state,roomId,true) end
     end
    end
   end
  end
 end
 if phase~="Playing" then return end
 stepTimers.accumulated+=dt
 stepTimers.combat+=dt
 stepTimers.ai+=dt
 stepTimers.auto+=dt
 stepTimers.attributes+=dt
 if stepTimers.accumulated<0.1 then return end
 local step=math.min(stepTimers.accumulated,0.3)
 stepTimers.accumulated=0
 local now=os.clock()
 updateObstacleFilters()
 if stepTimers.attributes>=1 then
  workspace:SetAttribute("MatchTime",math.floor(now-matchStart))
  stepTimers.attributes=0
  for _,state in pairs(states) do
   if alive(state) then
    local removed=false
    for unit in pairs(state.units) do
     if unit.Parent~=units then state.units[unit]=nil; orders[unit]=nil; actionClocks[unit]=nil; AutoWork.units[unit]=nil; removed=true
     elseif unit:GetAttribute("UnitType")=="monk" and (unit:GetAttribute("Faith") or 0)<Monk.config.maxFaith then
      unit:SetAttribute("Faith",Monk.rules.regenFaith(unit:GetAttribute("Faith"),Monk.config.maxFaith,Monk.config.rechargeTime,1))
     end
    end
    for building in pairs(state.buildings) do
     if building.Parent~=buildings then
      state.buildings[building]=nil
      state.rallies[building]=nil
      training[building],construction[building]=nil,nil
      cancelResearch(building,state)
      removed=true
     end
    end
    Garrison.heal(state,1)
    if removed then population(state); eliminationCheck(state) end
   end
  end
 end
 if phase~="Playing" then return end
 local probe=stepTimers.probe
 local function mark(entry,started)
  local seconds=os.clock()-started
  entry.count+=1; entry.sum+=seconds; entry.worst=math.max(entry.worst,seconds)
 end
 productionStep(step)
 local orderStarted=os.clock()
 orderStep(step,now)
 if probe then mark(probe.order,orderStarted) end
 if phase~="Playing" then return end
 if stepTimers.combat>=0.2 then
  stepTimers.combat=0
  local combatStarted=os.clock()
  Strike.step(now)
  if probe then mark(probe.combat,combatStarted) end
  Walls.step()
 end
 if probe then mark(probe.step,now) end
 if phase~="Playing" then return end
 if stepTimers.ai>=2 then stepTimers.ai=0; for _,state in pairs(states) do if state.ai then aiStep(state,now) end end end
 if phase~="Playing" then return end
 if stepTimers.auto>=Config.AutoWork.checkInterval then stepTimers.auto=0; AutoWork.step(now) end
 if settings.victory=="Wonder" and phase=="Playing" then
  for _,state in pairs(states) do
   if alive(state) then
    local earliest=nil
    for wonder in pairs(state.buildings) do
     if wonder.Parent==buildings and wonder:GetAttribute("BuildingType")=="Wonder" and wonder:GetAttribute("Complete") then
      state.wonderTimes[wonder]=state.wonderTimes[wonder] or now
      if not earliest or state.wonderTimes[wonder]<earliest then earliest=state.wonderTimes[wonder] end
     end
    end
    for wonder in pairs(state.wonderTimes) do
     if wonder.Parent~=buildings then state.wonderTimes[wonder]=nil end
    end
    if earliest then
     local remaining=math.max(0,(Config.Settings.wonderVictoryTime or 180)-(now-earliest))
     state.actor:SetAttribute("WonderRemaining",math.ceil(remaining))
     if remaining<=0 then endMatch(TeamRules.team(matchTeams,state.id)); break end
    else state.actor:SetAttribute("WonderRemaining",nil) end
   end
  end
 end
 if settings.victory=="Relic" and phase=="Playing" then Relic.victoryStep(now) end
end)
end
workspace:SetAttribute("RTSReady",true)
