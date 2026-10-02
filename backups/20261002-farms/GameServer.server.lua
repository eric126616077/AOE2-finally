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
local CommerceRules = require(script.Parent.ServerModules.CommerceRules)
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
assert(CommerceRules.audit(Config))
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
local CONSTRUCTION = Config.Construction
local COMBAT = Config.Combat
local MAX_UNIT_RADIUS=Config.UnitCollision.default.radius
for _,profile in pairs(Config.UnitCollision.profiles) do MAX_UNIT_RADIUS=math.max(MAX_UNIT_RADIUS,profile.radius) end
local unitCollisionIndex=assert(UnitCollisionRules.newIndex(16,MAX_UNIT_RADIUS))
-- 僧侶規則、設定與函式集中在一個表，避免超過 Studio 的 200 個區域變數上限。
local Monk={rules=require(script.Parent.ServerModules.MonkRules),config=Config.Monk,random=Random.new()}
local stop, issue, destroyModel, defeat, checkVictory, finishAttack, acquireTarget
-- 自動工作的每單位狀態（閒置起點、玩家保留待命、暫時略過的目標）與延後定義的函式。
local AutoWork={units=setmetatable({},{__mode="k"})}
local lobbyWorld = LobbyWorld.Create()
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
 if settings.teamMode=="CoopAI" then return team==1 and "玩家聯軍" or "電腦聯軍" end
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
  and (model:GetAttribute("HP")~=nil or model:GetAttribute("Amount")~=nil)
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
 local count,cap=0,0
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
local function unitStats(state,kind,resourceKind)
 local data,m=Config.Units[kind],state.modifiers
 local c=state.classModifiers[data.class] or {}
 local function value(key) return (m[key] or 0)+(c[key] or 0) end
 local specific=({food="gatherFood",wood="gatherWood",gold="gatherGold",stone="gatherStone"})[resourceKind]
 local military=data.class~="villager" and data.class~="monk"
 return {
  speed=data.speed*(1+value("speed")), damage=data.damage+(military and m.attack or 0)+(c.attack or 0),
  armor=(data.armor or 0)+(military and m.armor or 0)+(c.armor or 0),
  hp=data.hp+value("hp"),
  range=data.range+((military and data.range>20) and value("range") or 0), interval=(data.attackInterval or 1)*math.max(0.4,1-value("interval")),
  carry=(data.carryCapacity or 15)+value("carry"),
  gather=(data.gatherRate or 4)*(1+value("gather")+(specific and value(specific) or 0)),
 }
end
local function refreshUnit(state,unit)
 local stats=unitStats(state,unit:GetAttribute("UnitType"))
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
end
local function makeBuilding(state,kind,pos,complete)
 local data=Config.Buildings[kind]
 local model=Factory.model(kind,pos,Vector3.new(data.size.X*GRID_SIZE,data.height,data.size.Y*GRID_SIZE),data.color,"Buildings",state.actor:GetAttribute("TeamColor"))
 model:SetAttribute("RTSManaged",true)
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
 end
 refreshBuildingStats(state,model)
 model.Parent=buildings
 state.buildings[model]=true
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
  if part.CanCollide or part:IsDescendantOf(buildings) or part:IsDescendantOf(resources) or part:IsDescendantOf(units) then table.insert(obstacles,part) end
 end
 return obstacles
end
local function placementClear(pos,data)
 return #obstacleParts(pos+Vector3.new(0,data.height/2,0),
  Vector3.new(data.size.X*GRID_SIZE-0.2,math.max(4,data.height),data.size.Y*GRID_SIZE-0.2))==0
end
-- Static scenery stays in engine queries; moving units use a live spatial index.
-- PivotTo bypasses physics, so every server movement segment checks both.
units.ChildRemoved:Connect(function(unit) unitCollisionIndex:Remove(unit) end)
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
 updateObstacleFilters()
 local offset=Vector3.new(0,height/2,0)
 local delta=to-from
 return (delta.Magnitude==0 or workspace:Blockcast(CFrame.new(from+offset),size,delta,rayParams)==nil)
  and #workspace:GetPartBoundsInBox(CFrame.new(to+offset),size,attackOverlap)==0
end
local function unitNeighbors(unit,from,to,radius)
 return unitCollisionIndex:Nearby(from.X,from.Z,to.X,to.Z,radius,unit)
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
stop=function(unit,preserveFormationSlot)
 orders[unit]=nil
 if not preserveFormationSlot and unit.Parent then unit:SetAttribute("FormationSlot",nil) end
 if unit.Parent then
  unit:SetAttribute("Order","待命"); unit:SetAttribute("Animation","Idle"); unit:SetAttribute("WorkKind",nil)
  unit:SetAttribute("OrderKind",nil)
  unit:SetAttribute("OrderTargetName",nil)
  unit:SetAttribute("OrderTargetBuildingType",nil)
  unit:SetAttribute("OrderTargetResourceType",nil)
 end
end
issue=function(unit,kind,target,automatic)
 orders[unit]={kind=kind,target=target,lastPath=0,automatic=automatic==true}
 local autoEntry=AutoWork.units[unit]
 if autoEntry then autoEntry.idleSince=nil; if kind~="move" then autoEntry.hold=nil end end
 unit:SetAttribute("FormationSlot",kind=="move" and target or nil)
 unit:SetAttribute("Animation","Idle")
 unit:SetAttribute("WorkKind",nil)
 unit:SetAttribute("Order",({move="移動",gather="採集",deliver="交貨",attack="攻擊",build="施工",repair="修復",convert="招降",heal="治療"})[kind] or "移動")
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
 if order.kind=="attack" and state then finishAttack(state,unit,order) else stop(unit) end
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
     local path=PathfindingService:CreatePath({AgentRadius=agentRadius,AgentHeight=unit:GetAttribute("CollisionHeight") or 5,AgentCanJump=false,WaypointSpacing=8})
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
   if staticUnitSegmentClear(unit,current,point)
    and UnitCollisionRules.segmentClear(current.X,current.Z,point.X,point.Z,radius,unitNeighbors(unit,current,point,radius)) then
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
    if not visited and staticUnitSegmentClear(unit,current,point)
     and UnitCollisionRules.segmentClear(current.X,current.Z,point.X,point.Z,radius,unitNeighbors(unit,current,point,radius))
     and staticUnitSegmentClear(unit,current,advance)
     and UnitCollisionRules.segmentClear(current.X,current.Z,advance.X,advance.Z,radius,unitNeighbors(unit,current,advance,radius)) then
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
 unit:PivotTo(CFrame.lookAt(nextPos+Vector3.new(0,2.5,0),nextPos+facing.Unit+Vector3.new(0,2.5,0)))
 unitCollisionIndex:Update(unit,nextPos.X,nextPos.Z,radius)
end
local function nearestResource(state,pos,kind)
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
   if b.Parent==buildings and b:GetAttribute("BuildingType")=="Farm" and b:GetAttribute("Complete") and (b:GetAttribute("Amount") or 0)>0 then
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
 if not target.Parent or (target:GetAttribute("Amount") or 0)<=0 then target=nearestResource(state,position(unit),key) end
 if (unit:GetAttribute("Carrying") or 0)>0 and (not target or unit:GetAttribute("CarryType")~=key) then
  beginDelivery(state,unit,target,nil,key)
 elseif target then issue(unit,"gather",target)
 else stop(unit) end
end
local function buildRequest(state,kind,rawPosition,selection,quiet)
 local data=type(kind)=="string" and Config.Buildings[kind]
 if not data or not validPosition(rawPosition) or not alive(state) then return false end
 local builders=ConstructionRules.validateSelection(selection,function(unit) return canBuildWorker(state,unit) end,CONSTRUCTION.maxSelectedWorkers)
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
  local picked=AutoWorkRules.pickBuilders(candidates,AutoWorkRules.builderCount(data.size.X,data.size.Y,CONSTRUCTION.maxSelectedWorkers),Config.AutoWork.busyPenalty)
  if #picked>0 then builders,autoAssigned=picked,true end
 end
 if not builders then if not quiet then notify(state.actor,"先選取自己的村民才能建造；軍隊不能施工。") end; return false end
 if (state.actor:GetAttribute("Age") or 1)<(data.minAge or 1) then if not quiet then notify(state.actor,"需先升級時代才能建造"..data.name.."。") end; return false end
 local pos=Grid.snap(rawPosition,data.size)
 if not Grid.inBounds(pos,data.size) or not placementClear(pos,data) then if not quiet then notify(state.actor,"此處有障礙物或超出地圖。","Error") end; return false end
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"資源不足："..Grid.costText(data.cost),"Error") end; return false end
 local ok,model=pcall(makeBuilding,state,kind,pos,false)
 if not ok then
  refund(state.actor,data.cost)
  warn("[RTS] 建築生成失敗："..tostring(model))
  if not quiet then notify(state.actor,"建築模型載入失敗，已退還資源。") end
  return false
 end
 construction[model]={state=state,duration=data.buildTime or 12,work=0}
 recordReport(state,"spend",{cost=data.cost})
 for _,builder in ipairs(builders) do issue(builder,"build",model) end
 if not quiet then notify(state.actor,data.name..(autoAssigned and (" 工地已建立；已派最近的 "..#builders.." 位村民前往施工。") or " 工地已建立；選中的村民正前往施工。"),"Build") end
 return true,model
end
local function canTrain(buildingKind,unitKind)
 local data=Config.Buildings[buildingKind]
 for _,kind in ipairs(data and data.trains or {}) do if kind==unitKind then return true end end
 return false
end
local function queueAttributes(building)
 local queue=training[building]
 local names={}
 for _,item in ipairs(queue or {}) do table.insert(names,Config.Units[item.kind].name) end
 for index=1,5 do building:SetAttribute("QueueKind_"..index,queue and queue[index] and queue[index].kind or nil) end
 building:SetAttribute("QueueCount",#names)
 building:SetAttribute("Queue",table.concat(names,"、"))
 local item=queue and queue[1]
 building:SetAttribute("Training",item and Config.Units[item.kind].name or nil)
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
 notify(state.actor,"已取消"..Config.Units[item.kind].name.."訓練，退回全部資源。")
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
   if b.Parent==buildings and b:GetAttribute("Complete") and info and kind~="TownCenter" and kind~="House" and kind~="Farm" and kind~="Wall" and kind~="Tower" and kind~="Castle" and (info.minAge or 1)==age and not kinds[kind] then kinds[kind],count=true,count+1 end
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
 elseif model.Parent==buildings then training[model],construction[model]=nil,nil; if state then state.buildings[model]=nil; cancelResearch(model,state); state.defenseLast[model]=nil end end
 if state and state.rallies then state.rallies[model]=nil end
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
 announce(winnerTeam and (winnerName.." 獲得勝利！房主可返回大廳開始新局。") or "對局結束。房主可返回大廳。")
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
  destroyModel(target)
  eliminationCheck(victim)
 elseif target.Parent==units and target:GetAttribute("UnitType")~="monk" and CombatRules.canRetaliate(orders[target] and orders[target].kind,enemies(victim,owner(attacker)),
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
local function attackDamage(state,unit,target)
 local data=Config.Units[unit:GetAttribute("UnitType")]
 local targetKind=target:GetAttribute("UnitType")
 local class=target.Parent==buildings and "building" or (Config.Units[targetKind] and Config.Units[targetKind].class or targetKind)
 return unitStats(state,unit:GetAttribute("UnitType")).damage+((data.bonus or {})[class] or 0)
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
  target=nearestResource(state,rally.position,rally.resourceType)
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
local function resetActor(state)
 clearReport(state)
 state.civilization=CivilizationRules.resolve(Config,state.civilization)
 publishCivilization(state,state.actor)
 state.units,state.buildings,state.technologies,state.pendingTech,state.defenseLast={},{},{},{},{}
 state.modifiers={attack=0,armor=0,hp=0,gather=0,carry=0,speed=0,gatherFood=0,gatherWood=0,gatherGold=0,gatherStone=0,farmCapacity=0,range=0,interval=0,trainSpeed=0}
 state.classModifiers={}
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
  if #members==0 and room.hadMembers and activeRoomId~=room.id then resetRoomDefaults(room) end
  if #members>0 then room.hadMembers=true end
  local ready=0
  local host=members[1] and members[1].id or 0
  local status=activeRoomId==room.id and phase or (room.configured and "Waiting" or "Configuring")
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
 if not state.inLobby or state.playing or not state.queued then return end
 local room=rooms[state.roomId]
 state.queued,state.ready,state.roomId=false,false,nil
 state.queueCooldown=os.clock()+2
 state.actor:SetAttribute("LobbyQueued",false)
 state.actor:SetAttribute("LobbyReady",false)
 state.actor:SetAttribute("LobbyRoomId",nil)
 state.actor:SetAttribute("LobbyTeamId",nil)
 positionLobby(state)
 if state.actor.Character then state.actor.Character:PivotTo(lobbyWorld:SpawnCFrame()) end
 invalidateReady(room)
 updateHost()
end
local function configureLobby(player,payload)
 local state=states[player]
 local room=state and state.roomId and rooms[state.roomId]
 if not room or not state.inLobby or state.playing or not state.queued or activeRoomId==room.id
  or workspace:GetAttribute(roomPrefix(room,"HostUserId"))~=player.UserId then return end
 local validated,count=LobbyRules.settings(payload)
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
 if room and state.inLobby and not state.playing and state.queued and activeRoomId~=room.id
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
end
local function clearMatch()
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
  if not state.actor.Character then spawnLobby(state) else positionLobby(state) end
 end
 if departingRoom then invalidateReady(departingRoom) end
 updateHost()
 announce("已返回匹配大廳，選擇匹配點後可準備新局。")
end
startMatch=function(player)
 local requester=states[player]
 local room=requester and requester.roomId and rooms[requester.roomId]
 if phase~="Lobby" or not room or not room.configured or not requester.inLobby or requester.playing
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
  actor:SetAttribute("DisplayName","電腦 "..i)
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
  mode=#humans>=2 and settings.aiCount==0 and "PurePvP" or settings.aiCount>0 and "AIPractice" or "Sandbox"}
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
 local startMessage=startingSides==1 and "練習對局開始：可自由熟悉經濟與建造；投降後返回大廳。"
  or settings.teamMode=="CoopAI" and "合作對局開始！所有玩家同隊，發展經濟並擊敗電腦聯軍。"
  or settings.teamMode=="Teams" and "分隊對局開始！與盟友共同發展，擊敗敵方隊伍。"
  or "對局開始！採集資源、發展時代並擊敗對手。"
 for _,state in ipairs(humans) do notify(state.actor,startMessage,"MatchStart") end
end
autoStartLobby=function()
 if phase~="Lobby" then return end
 for _,portal in ipairs(Config.Lobby.portals) do
  local room=rooms[portal.id]
  local members=queuedStates(room.id)
  if room.configured and LobbyRules.canStart(room.expected,members) then
    local host=members[1] and members[1].actor
    if host and host.Parent==Players then startMatch(host); if phase~="Lobby" then return end end
  end
 end
end
local function lobbyReady(state,value,revision)
 local room=state.roomId and rooms[state.roomId]
 if not room or not room.configured or not state.inLobby or state.playing or not state.queued or activeRoomId==room.id
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
 updateHost()
 spawnLobby(state)
 if phase~="Lobby" then notify(player,"目前有對局進行中；可在其他匹配點集合等待下一局。") end
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
 local name=Config.Units[kind] and Config.Units[kind].name or "單位"
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
  if kind=="monk" then Monk.order(state,unit,target,victim)
  elseif enemies(state,victim) then issue(unit,"attack",target)
  elseif canBuildWorker(state,unit) and isOwned(state,target,buildings) and construction[target] and not target:GetAttribute("Complete") then issue(unit,"build",target)
  elseif kind=="villager" and target:GetAttribute("ResourceType") and (not victim or victim==state) and (target:GetAttribute("Amount") or 0)>0 and (target.Parent~=buildings or target:GetAttribute("Complete")) then
   if (unit:GetAttribute("Carrying") or 0)>0 and unit:GetAttribute("CarryType")~=target:GetAttribute("ResourceType") then beginDelivery(state,unit,target) else issue(unit,"gather",target) end
  elseif kind=="villager" and isOwned(state,target,buildings) and (target:GetAttribute("HP") or 0)<(target:GetAttribute("MaxHP") or 0) then issue(unit,"repair",target)
  elseif kind=="villager" and isOwned(state,target,buildings) and (unit:GetAttribute("Carrying") or 0)>0 then
   if target:GetAttribute("Complete") and acceptsResource(target,unit:GetAttribute("CarryType")) then beginDelivery(state,unit,nil,target)
   else notify(state.actor,"這座建築無法接收村民攜帶的資源。") end
  end
  if orders[unit] and orders[unit]~=previous then accepted=true end
 end
 if accepted then notify(state.actor,nil,"Order") end
end
command.OnServerEvent:Connect(function(player,action,a,b,c)
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
 if action=="RestartMatch" then if phase=="Ended" and workspace:GetAttribute("HostUserId")==player.UserId then lobbyReset() end; return end
 if phase~="Playing" or not alive(state) then return end
 if action=="Surrender" then defeat(state,"你已投降，本局判負；可以繼續觀戰。",true); if startingSides==1 then endMatch(nil) end
 elseif action=="Build" then buildRequest(state,a,b,c,false)
 elseif action=="Train" then trainRequest(state,a,b,false)
 elseif action=="CancelTraining" then cancelTrainingRequest(state,a,b,c)
 elseif action=="Rally" then rallyRequest(state,a,b)
 elseif action=="AdvanceAge" then advanceRequest(state,a,false)
 elseif action=="Research" then researchRequest(state,a,b,false)
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
 elseif action=="Delete" then
  local selection=CommandRules.deletion(a,b,matchGeneration,function(model)
   if not (isOwned(state,model,units) or isOwned(state,model,buildings)) then return false end
   local hp=model:GetAttribute("HP")
   return type(hp)=="number" and hp==hp and hp>0 and hp<math.huge
  end)
  if not selection then notify(player,"無法拆除：選取已失效，或包含非己方的單位與建築。","Error"); return end
  -- No refund, damage, kill credit or queued production can run between
  -- validation and this synchronous cleanup. Reuse the normal lifecycle.
  for _,model in ipairs(selection) do destroyModel(model) end
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
   else table.insert(military,unit) end
  end
 end
 for _,unit in ipairs(idle) do
  if (unit:GetAttribute("Carrying") or 0)>0 then beginDelivery(state,unit,nil)
  else
   local priorities=AIWorkerRules.resourcePriorities(villagerCount,gathering,state.actor:GetAttribute("food") or 0)
   local target,key=AIWorkerRules.findResource(priorities,function(resourceKind) return nearestResource(state,position(unit),resourceKind) end)
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
 if not nearestResource(state,state.home,"food") then aiBuild(state,"Farm") end
 if settings.victory=="Wonder" and age>=4 and not completedBuilding(state,"Wonder") then aiBuild(state,"Wonder") end
 local armyLimit=settings.difficulty=="Easy" and 16 or settings.difficulty=="Hard" and 60 or 36
 if #military<armyLimit and not savingForAge then
  for b in pairs(state.buildings) do
   if b:GetAttribute("Complete") then
    local queue=training[b]
    if not queue or #queue<2 then
     local options=Config.Buildings[b:GetAttribute("BuildingType")].trains or {}
     for offset=1,#options do local kind=options[(state.aiTurn+offset)%#options+1]; if kind~="villager" and trainRequest(state,b,kind,true) then break end end
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
local combatStep
do
local spatial={}
local CELL=64
-- 數字格鍵避免每次查詢建立字串；地圖最大 1536 studs，格座標遠小於 4096。
local function spatialKey(x,z) return x*8192+z end
local function rebuildSpatial()
 spatial={}
 for _,state in pairs(states) do
  if alive(state) then
   for _,models in ipairs({state.units,state.buildings}) do
    for model in pairs(models) do
     if model.Parent then
      local p=position(model)
      local key=spatialKey(math.floor(p.X/CELL),math.floor(p.Z/CELL))
      local bucket=spatial[key] or {}
      table.insert(bucket,model)
      spatial[key]=bucket
     end
    end
   end
  end
 end
end
local function targetCategory(model)
 if model.Parent==units then return model:GetAttribute("UnitType")=="villager" and "villager" or "military" end
 local data=Config.Buildings[model:GetAttribute("BuildingType")]
 return data and data.damage and model:GetAttribute("Complete") and "defense" or "building"
end
local function targetScore(target,current,preferred)
 return CombatRules.targetScore(distanceTo(target,current),targetCategory(target),COMBAT.tierDistance,preferred)
end
-- 依優先層級與邊緣距離挑選目標；unitsOnly 供防禦建築只射擊單位。
local function bestEnemy(state,current,radius,preferred,unitsOnly)
 local found,best=nil,math.huge
 local cells=SpatialRules.searchCells(radius,TARGET_HALF_EXTENT,CELL)
 if not cells then return nil end
 local x,z=math.floor(current.X/CELL),math.floor(current.Z/CELL)
 for dx=-cells,cells do
  for dz=-cells,cells do
   local bucket=spatial[spatialKey(x+dx,z+dz)]
   if bucket then
    for _,target in ipairs(bucket) do
     if target.Parent and (not unitsOnly or target.Parent==units) and enemies(state,owner(target)) then
      local distance=distanceTo(target,current)
      if distance<=radius then
       local score=CombatRules.targetScore(distance,targetCategory(target),COMBAT.tierDistance,preferred)
       if score and score<best then found,best=target,score end
      end
     end
    end
   end
  end
 end
 return found,best
end
-- 待命或自動攻擊中的軍隊重新評估目標。afterKill 讓剛完成擊殺（含玩家手動指定）的部隊立即接戰，不留空檔。
acquireTarget=function(state,unit,now,afterKill)
 local kind=unit:GetAttribute("UnitType")
 local data=Config.Units[kind]
 if kind=="villager" or kind=="monk" or not data or unit.Parent~=units then return false end
 local order=orders[unit]
 if order and not afterKill and not (order.kind=="attack" and order.automatic) then return false end
 local current=position(unit)
 local radius=CombatRules.acquisitionRadius(COMBAT.acquisitionRadius,unit:GetAttribute("Range") or data.range)
 if not radius then return false end
 local target,score=bestEnemy(state,current,radius,data.preferredTarget)
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
combatStep=function(now)
 rebuildSpatial()
 for _,state in pairs(states) do
  if phase~="Playing" then return end
  if alive(state) then
   for unit in pairs(state.units) do
    local retryAfter=actionClocks[unit] and actionClocks[unit].acquireAfter or 0
    if now>=retryAfter then acquireTarget(state,unit,now) end
    if orders[unit]==nil and unit.Parent==units and unit:GetAttribute("UnitType")=="monk" then Monk.autoHeal(state,unit) end
   end
   for b in pairs(state.buildings) do
    if phase~="Playing" then return end
    local data=Config.Buildings[b:GetAttribute("BuildingType")]
    local interval=data and data.attackInterval or 1.5
    local last=state.defenseLast[b]
    if b.Parent==buildings and data and data.damage and b:GetAttribute("Complete") and now-(last or -math.huge)>=interval then
     local target=bestEnemy(state,position(b),data.range or 64,nil,true)
     if target then
      -- 以射擊間隔累進，不受 0.6 秒索敵週期量化而變慢；中斷過久才重新對齊。
      state.defenseLast[b]=last and now-last<interval+0.75 and last+interval or now
      b:SetAttribute("AttackPosition",position(target))
      b:SetAttribute("LastAttack",now)
      damage(target,buildingAttack(state,data),b,now)
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
local function nearbyResources(state,pos,entry,now,farmUsed)
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
  if b.Parent==buildings and b:GetAttribute("BuildingType")=="Farm" and b:GetAttribute("Complete") and (b:GetAttribute("Amount") or 0)>0
   and not farmUsed[b] and not skipped(entry,b,now) then
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
  choice.nearby=nearbyResources(state,pos,entry,now,context.farmUsed)
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
-- 農田耗盡且木材足夠時自動重新播種，扣款與一般建造相同。
AutoWork.reseed=function(state,farm)
 if not AUTO.reseedFarms or not enabled(state) or farm:GetAttribute("BuildingType")~="Farm" or not farm:GetAttribute("Complete") then return false end
 local cost=Config.Buildings.Farm.cost
 if not Economy.spend(state.actor,cost) then return false end
 recordReport(state,"spend",{cost=cost})
 farm:SetAttribute("Amount",farm:GetAttribute("MaxAmount") or 0)
 notify(state.actor,"農田已耗盡，自動重新播種："..Grid.costText(cost))
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
     order.kind,order.target==b,distanceTo(b,position(unit)),CONSTRUCTION.workRange)
     and interactionLineClear(b,position(unit)) then builders+=1; table.insert(working,unit) end
   end
   b:SetAttribute("BuilderCount",builders)
   b:SetAttribute("ConstructionStatus",builders>0 and "施工中" or "等待村民")
   if builders>0 then
    local nextWork,work,complete=ConstructionRules.stepWork(item.work,item.duration,builders,dt,CONSTRUCTION.extraWorkerRate)
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
     notify(item.state.actor,nil,"ConstructionComplete")
     if b:GetAttribute("BuildingType")=="Farm" then b:SetAttribute("Amount",b:GetAttribute("MaxAmount") or 0) end
     recordReport(item.state,"building",{subjectId=reportSubject(b)})
     population(item.state)
     if b:GetAttribute("BuildingType")=="House" then telemetry:Fact(item.state.actor,"firsthouse") end
     for unit in pairs(item.state.units) do
      local order=orders[unit]
      if order and order.kind=="build" and order.target==b then
       if b:GetAttribute("BuildingType")=="Farm" then issue(unit,"gather",b) else stop(unit); AutoWork.afterBuild(item.state,unit,b) end
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
    local liveUnits=0
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
    if data.effect and data.effect.farmCapacity then
     for farm in pairs(state.buildings) do
      if farm:GetAttribute("BuildingType")=="Farm" then
       if farm:GetAttribute("Complete") then farm:SetAttribute("Amount",(farm:GetAttribute("Amount") or 0)+data.effect.farmCapacity) end
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
local function orderStep(dt,now)
 for unit,order in pairs(orders) do
  if phase~="Playing" then return end
  local state=owner(unit)
  if unit.Parent~=units or not alive(state) then orders[unit]=nil; continue end
  local target=order.target
  if order.kind~="move" and (not target.Parent or (order.kind=="gather" and (target:GetAttribute("Amount") or 0)<=0)) then
   if order.kind=="gather" then
    local key=target:GetAttribute("ResourceType")
    if (unit:GetAttribute("Carrying") or 0)>0 then beginDelivery(state,unit,target)
    else local replacement=nearestResource(state,position(unit),key); if replacement then issue(unit,"gather",replacement) else stop(unit) end end
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
  local current=position(unit)
  local stats=unitStats(state,unit:GetAttribute("UnitType"),order.kind=="gather" and target:GetAttribute("ResourceType") or nil)
  local destination=order.kind=="move" and target or edgePosition(target,current)
  -- 到位誤差小於陣形間隙，避免先停止的前排占住後排目的地。
  local range=order.kind=="move" and Config.Formations.arrivalTolerance or (order.kind=="attack" or order.kind=="convert") and stats.range or order.kind=="heal" and Monk.config.healRange or order.kind=="build" and CONSTRUCTION.workRange or 5
  local inRange=(destination-current).Magnitude<=range
  if order.kind=="attack" and order.anchor and not order.objective and not inRange
   and CombatRules.beyondLeash(order.anchor.X,order.anchor.Z,current.X,current.Z,COMBAT.leashDistance) then
   -- 自動追擊超出上限：村民回去採集，軍隊回到原點，短暫不再索敵以免來回拉扯。
   actionClocks[unit]=actionClocks[unit] or {}
   actionClocks[unit].acquireAfter=now+COMBAT.leashCooldown
   if order.resumeGather then finishAttack(state,unit,order) else issue(unit,"move",order.anchor) end
   continue
  end
  if ApproachRules.isWork(order.kind) then
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
   if interactionLineClear(target,current) then
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
  if inRange then
   order.path=nil
   unit:SetAttribute("Animation",order.kind=="attack" and "Attack" or (order.kind=="gather" or order.kind=="build" or order.kind=="repair" or order.kind=="convert" or order.kind=="heal") and "Work" or "Idle")
   unit:SetAttribute("WorkKind",order.kind=="gather" and target:GetAttribute("ResourceType") or order.kind=="build" and "build" or order.kind=="repair" and "repair" or nil)
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
    if not returnTarget or not returnTarget.Parent or (returnTarget:GetAttribute("Amount") or 0)<=0 then returnTarget=nearestResource(state,current,order.returnKind or key) end
    if returnTarget then issue(unit,"gather",returnTarget) else stop(unit) end
   elseif order.kind=="gather" and UnitRules.takeAction(actionClocks,unit,"gather",now,1) then
    local key=target:GetAttribute("ResourceType")
    local carrying=unit:GetAttribute("Carrying") or 0
    local amount=GatheringRules.takeAmount(target:GetAttribute("Amount") or 0,carrying,stats.carry,stats.gather)
    target:SetAttribute("Amount",math.max(0,(target:GetAttribute("Amount") or 0)-amount))
    if target.Parent==buildings and (target:GetAttribute("Amount") or 0)<=0 then AutoWork.reseed(state,target) end
    unit:SetAttribute("CarryType",key)
    unit:SetAttribute("Carrying",carrying+amount)
    if amount>0 then unit:SetAttribute("LastWork",now) end
    if carrying+amount>=stats.carry or (target:GetAttribute("Amount") or 0)<=0 then beginDelivery(state,unit,target) end
    if (target:GetAttribute("Amount") or 0)<=0 and target.Parent==resources then managedResources[target]=nil; target:Destroy() end
   elseif order.kind=="attack" and UnitRules.takeAction(actionClocks,unit,"attack",now,stats.interval) then
    unit:SetAttribute("AttackPosition",position(target))
    unit:SetAttribute("LastAttack",now)
    local data=Config.Units[unit:GetAttribute("UnitType")]
    local impact=position(target)
    damage(target,attackDamage(state,unit,target),unit,now)
    if data.splash and data.splash>0 then
     for _,enemy in pairs(states) do
      if enemies(state,enemy) then
       for other in pairs(enemy.units) do if other~=target and other.Parent and (position(other)-impact).Magnitude<=data.splash then damage(other,stats.damage*0.5,unit,now) end end
      end
     end
    end
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
   local goal=order.approachGoal or destination
   if order.kind~="move" and not order.approachGoal then
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
   moveToward(unit,order,goal,stats.speed,dt,now)
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
setPhase("Lobby")
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
RunService.Heartbeat:Connect(function(dt)
 do
  stepTimers.lobby+=dt
  if stepTimers.lobby>=Config.Lobby.scanInterval then
   stepTimers.lobby=0
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
    if removed then population(state); eliminationCheck(state) end
   end
  end
 end
 if phase~="Playing" then return end
 productionStep(step)
 orderStep(step,now)
 if phase~="Playing" then return end
 if stepTimers.combat>=0.6 then stepTimers.combat=0; combatStep(now) end
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
end)
end
workspace:SetAttribute("RTSReady",true)
