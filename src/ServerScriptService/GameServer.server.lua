local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Config = require(RS.GameData.GameConfig)
local Grid = require(RS.Shared.Grid)
local Factory = require(script.Parent.ServerModules.ModelFactory)
local Economy = require(script.Parent.ServerModules.Economy)
local Rules = require(script.Parent.ServerModules.MatchRules)
local UnitRules = require(script.Parent.ServerModules.UnitRules)
local World = require(script.Parent.ServerModules.WorldGenerator)
Players.CharacterAutoLoads = false

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
local buildings = folder(workspace, "Buildings")
local resources = folder(workspace, "Resources")
local units = folder(workspace, "Units")
local factions = folder(RS, "RTSFactions")
local remotes = folder(RS, "RTSRemotes")
local command, feedback = remote(remotes, "Command"), remote(remotes, "Feedback")
local states, byId, orders, training, construction, researching = {}, {}, {}, {}, {}, {}
local managedResources = {}
local actionClocks = {}
local colors = {Color3.fromRGB(80,151,224), Color3.fromRGB(209,83,75), Color3.fromRGB(218,177,70), Color3.fromRGB(136,101,190)}
local settings = {size="Medium", aiCount=1, difficulty="Normal", population=100, startingResources="Standard", victory="Conquest"}
local phase, matchStart, matchGeneration, startingSides = "Lobby", 0, 0, 0
local joinSequence, pathTasks = 0, 0
local GRID_SIZE = Config.Map.GridSize
local stop, issue, destroyModel, defeat, checkVictory

local function actorName(actor)
 return actor:IsA("Player") and actor.DisplayName or actor:GetAttribute("DisplayName") or actor.Name
end
local function notify(actor, message)
 if actor and actor:IsA("Player") and actor.Parent == Players then feedback:FireClient(actor, message) end
end
local function announce(message)
 for _, player in ipairs(Players:GetPlayers()) do notify(player, message) end
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
local function isTarget(model)
 return typeof(model)=="Instance" and model:IsA("Model")
  and (model.Parent==buildings or model.Parent==units or model.Parent==resources)
  and (model:GetAttribute("RTSManaged")==true or model:GetAttribute("RTSManagedResource")==true)
  and (model:GetAttribute("HP")~=nil or model:GetAttribute("Amount")~=nil)
end
local function enemies(a,b)
 return alive(a) and alive(b) and a.id~=b.id
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
 return {
  speed=data.speed*(1+value("speed")), damage=data.damage+(kind~="villager" and m.attack or 0)+(c.attack or 0),
  armor=(data.armor or 0)+(kind~="villager" and m.armor or 0)+(c.armor or 0),
  hp=data.hp+value("hp"),
  range=data.range+((data.range>20) and value("range") or 0), interval=(data.attackInterval or 1)*math.max(0.4,1-value("interval")),
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
end
local function makeBuilding(state,kind,pos,complete)
 local data=Config.Buildings[kind]
 local model=Factory.model(kind,pos,Vector3.new(data.size.X*GRID_SIZE,data.height,data.size.Y*GRID_SIZE),data.color,"Buildings",state.actor:GetAttribute("TeamColor"))
 model:SetAttribute("RTSManaged",true)
 model:SetAttribute("BuildingType",kind)
 model:SetAttribute("DisplayName",data.name)
 model:SetAttribute("HP",complete and data.hp or math.max(1,math.floor(data.hp*0.15)))
 model:SetAttribute("MaxHP",data.hp)
 model:SetAttribute("OwnerId",state.id)
 model:SetAttribute("OwnerName",actorName(state.actor))
 model:SetAttribute("Complete",complete==true)
 model:SetAttribute("ConstructionProgress",complete and 1 or 0)
 model:SetAttribute("ConstructionRemaining",complete and 0 or data.buildTime or 12)
 if kind=="Farm" then
  local amount=(data.amount or 600)+state.modifiers.farmCapacity
  model:SetAttribute("ResourceType","food")
  model:SetAttribute("Amount",amount)
  model:SetAttribute("MaxAmount",amount)
 end
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
 model.Parent=units
 state.units[model]=true
 refreshUnit(state,model)
 population(state)
 return model
end
local function makeResource(kind,pos)
 local data=Config.Resources[kind]
 local model=Factory.model(kind,pos,Vector3.new(8,data.height,8),data.color,"Resource")
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
local function updateObstacleFilters()
 local excluded={units}
 local ground=workspace:FindFirstChild("AOE2_Ground")
 local scenery=workspace:FindFirstChild("RTSScenery")
 if ground then table.insert(excluded,ground) end
 if scenery then table.insert(excluded,scenery) end
 rayParams.FilterDescendantsInstances=excluded
 local placementExcluded={}
 if ground then table.insert(placementExcluded,ground) end
 if scenery then table.insert(placementExcluded,scenery) end
 overlap.FilterDescendantsInstances=placementExcluded
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
local function edgePosition(target,current)
 local center=position(target)
 local half=target.PrimaryPart and target.PrimaryPart.Size/2 or Vector3.new(2,2,2)
 return Vector3.new(math.clamp(current.X,center.X-half.X,center.X+half.X),Config.Map.GroundY,
  math.clamp(current.Z,center.Z-half.Z,center.Z+half.Z))
end
local function distanceTo(target,current)
 return (edgePosition(target,current)-current).Magnitude
end
stop=function(unit)
 orders[unit]=nil
 if unit.Parent then unit:SetAttribute("Order","待命"); unit:SetAttribute("Animation","Idle") end
end
issue=function(unit,kind,target,automatic)
 orders[unit]={kind=kind,target=target,lastPath=0,automatic=automatic==true}
 unit:SetAttribute("Order",({move="移動",gather="採集",deliver="交貨",attack="攻擊",build="施工",repair="修復"})[kind] or "移動")
end
local function route(unit,order,goal,now)
 if order.computing or pathTasks>=8 or now-order.lastPath<1.5 then return end
 order.computing,order.lastPath=true,now
 pathTasks+=1
 local generation=matchGeneration
 task.spawn(function()
  local path=PathfindingService:CreatePath({AgentRadius=unit:GetAttribute("Radius") or 2,AgentHeight=5,AgentCanJump=false,WaypointSpacing=8})
  local ok=pcall(function() path:ComputeAsync(position(unit)+Vector3.new(0,2,0),goal+Vector3.new(0,2,0)) end)
  pathTasks=math.max(0,pathTasks-1)
  if generation~=matchGeneration or orders[unit]~=order or unit.Parent~=units then return end
  order.computing=false
  if ok and path.Status==Enum.PathStatus.Success then order.path,order.index,order.failures=path:GetWaypoints(),2,0
  else
   order.failures=(order.failures or 0)+1
   if order.failures>=3 then stop(unit); local state=owner(unit); if state then notify(state.actor,"無法抵達目標，請選擇其他位置。") end end
  end
 end)
end
local function moveToward(unit,order,destination,speed,dt,now)
 local current,goal=position(unit),destination
 if order.path and order.path[order.index] then
  local p=order.path[order.index].Position
  goal=Vector3.new(p.X,Config.Map.GroundY,p.Z)
  if (goal-current).Magnitude<1 then order.index+=1; if not order.path[order.index] then order.path=nil end; return end
 elseif order.path then order.path=nil end
 local delta=goal-current
 if delta.Magnitude<0.05 then return end
 local nextPos=current+delta.Unit*math.min(delta.Magnitude,speed*dt)
 local radius=unit:GetAttribute("Radius") or 2
 if workspace:Blockcast(CFrame.new(current+Vector3.new(0,2.5,0)),Vector3.new(radius*1.8,4,radius*1.8),nextPos-current,rayParams) then order.path=nil; route(unit,order,destination,now); return end
 unit:SetAttribute("Animation","Walk")
 unit:PivotTo(CFrame.lookAt(nextPos+Vector3.new(0,2.5,0),nextPos+delta.Unit+Vector3.new(0,2.5,0)))
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
 if not data then return false end
 if data.dropoff then
  if data.dropoff==true then return true end
  for _,kind in ipairs(data.dropoff) do if kind==key then return true end end
 end
 return building:GetAttribute("BuildingType")=="TownCenter" or building:GetAttribute("BuildingType")=="Castle" or building:GetAttribute("BuildingType")=="Market"
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
local function beginDelivery(state,unit,returnTarget)
 local dropoff=nearestDropoff(state,position(unit),unit:GetAttribute("CarryType"))
 if dropoff then issue(unit,"deliver",dropoff); orders[unit].returnTarget=returnTarget
 else stop(unit); notify(state.actor,"需要合適的經濟建築才能交回資源。") end
end
local function buildRequest(state,kind,rawPosition,quiet)
 local data=type(kind)=="string" and Config.Buildings[kind]
 if not data or not validPosition(rawPosition) or not alive(state) then return false end
 if (state.actor:GetAttribute("Age") or 1)<(data.minAge or 1) then if not quiet then notify(state.actor,"需先升級時代才能建造"..data.name.."。") end; return false end
 local pos=Grid.snap(rawPosition,data.size)
 if not Grid.inBounds(pos,data.size) or not placementClear(pos,data) then if not quiet then notify(state.actor,"此處有障礙物或超出地圖。") end; return false end
 local builder,nearest=nil,80
 for unit in pairs(state.units) do
  if unit.Parent==units and unit:GetAttribute("UnitType")=="villager" then
   local distance=(position(unit)-pos).Magnitude
   local order=orders[unit]
   if distance<=nearest and (not order or order.kind~="build") then builder,nearest=unit,distance end
  end
 end
 if not builder then if not quiet then notify(state.actor,"需要一名村民在建築位置 80 studs 內。") end; return false end
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"資源不足："..Grid.costText(data.cost)) end; return false end
 local ok,model=pcall(makeBuilding,state,kind,pos,false)
 if not ok then
  refund(state.actor,data.cost)
  warn("[RTS] 建築生成失敗："..tostring(model))
  if not quiet then notify(state.actor,"建築模型載入失敗，已退還資源。") end
  return false
 end
 construction[model]={state=state,duration=data.buildTime or 12,work=0}
 issue(builder,"build",model)
 if not quiet then notify(state.actor,data.name.." 已開始施工。") end
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
 if count>=cap then if not quiet then notify(state.actor,"人口已滿，請建造房屋。") end; return false end
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"訓練所需資源不足。") end; return false end
 local duration=data.trainTime*math.max(0.4,1-state.modifiers.trainSpeed)
 table.insert(queue,{kind=kind,state=state,remaining=duration,duration=duration})
 training[building]=queue
 queueAttributes(building)
 population(state)
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
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"升級時代所需資源不足："..Grid.costText(data.cost)) end; return false end
 state.advancing={building=building,age=age+1,remaining=data.time,duration=data.time,cost=data.cost}
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
 if state.technologies[key] or state.pendingTech[key] or (state.actor:GetAttribute("Age") or 1)<(data.minAge or 1) then return false end
 if researching[building] or (training[building] and #training[building]>0) or (state.advancing and state.advancing.building==building) then if not quiet then notify(state.actor,"此建築的佇列尚未完成。") end; return false end
 if data.requires and not state.technologies[data.requires] then if not quiet then notify(state.actor,"需先研究前置科技。") end; return false end
 if not Economy.spend(state.actor,data.cost) then if not quiet then notify(state.actor,"研究所需資源不足。") end; return false end
 researching[building]={state=state,key=key,remaining=data.time,duration=data.time}
 state.pendingTech[key]=true
 building:SetAttribute("Research",data.name)
 building:SetAttribute("ResearchProgress",0)
 building:SetAttribute("ResearchRemaining",data.time)
 return true
end
local function cancelResearch(building,state)
 local research=researching[building]
 if research then state.pendingTech[research.key]=nil; researching[building]=nil end
 if state.advancing and state.advancing.building==building then state.advancing=nil; state.actor:SetAttribute("AgeProgress",0); state.actor:SetAttribute("AgeRemaining",0) end
end
destroyModel=function(model)
 actionClocks[model]=nil
 local state=owner(model)
 if model.Parent==units then orders[model]=nil; if state then state.units[model]=nil end
 elseif model.Parent==buildings then training[model],construction[model]=nil,nil; if state then state.buildings[model]=nil; cancelResearch(model,state); state.defenseLast[model]=nil end end
 model:Destroy()
 if state then population(state) end
end
local function endMatch(winner)
 if phase~="Playing" then return end
 setPhase("Ended")
 workspace:SetAttribute("Winner",winner and actorName(winner.actor) or "無")
 workspace:SetAttribute("WinnerId",winner and winner.id or 0)
 for unit in pairs(orders) do stop(unit) end
 announce(winner and (actorName(winner.actor).." 獲得勝利！房主可返回大廳開始新局。") or "對局結束。房主可返回大廳。")
end
checkVictory=function()
 if phase~="Playing" or startingSides<2 then return end
 local survivors={}
 for _,state in pairs(states) do if alive(state) then table.insert(survivors,state) end end
 local winner,ended=Rules.winner(survivors)
 if ended then endMatch(winner) end
end
defeat=function(state,reason)
 if not alive(state) then return end
 state.defeated=true
 state.actor:SetAttribute("Defeated",true)
 state.actor:SetAttribute("AgeRemaining",0)
 for unit in pairs(state.units) do destroyModel(unit) end
 for building in pairs(state.buildings) do destroyModel(building) end
 state.units,state.buildings={},{}
 state.pendingTech,state.wonderTimes={},{}
 population(state)
 state.advancing=nil
 notify(state.actor,reason or "你的陣營已被消滅，可以繼續觀戰。")
 announce(actorName(state.actor).." 已戰敗。")
 checkVictory()
end
local function eliminationCheck(state)
 if not alive(state) then return end
 if settings.victory=="Regicide" then
  local main=false
  for b in pairs(state.buildings) do if b.Parent==buildings and b:GetAttribute("MainBase") then main=true; break end end
  if not main then defeat(state,"主城被摧毀，你已戰敗。") end
 elseif next(state.units)==nil and next(state.buildings)==nil then defeat(state,"全部單位與建築已被摧毀，你已戰敗。") end
end
local function damage(target,raw,attacker,now)
 local victim=owner(target)
 if not victim or not alive(victim) or not target.Parent then return end
 local amount=math.max(1,raw-(target:GetAttribute("Armor") or 0))
 target:SetAttribute("HP",math.max(0,(target:GetAttribute("HP") or 0)-amount))
 if (target:GetAttribute("HP") or 0)<=0 then destroyModel(target); eliminationCheck(victim)
 elseif target.Parent==units and attacker and attacker.Parent and (not orders[target] or orders[target].kind=="gather") then issue(target,"attack",attacker,true) end
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
 local class=Config.Units[kind].class
 local radius=class=="siege" and 4 or class=="cavalry" and 3 or 2
 for ring=1,3 do
  for index=0,15 do
   local angle=index*math.pi/8
   local spawnRadius=math.max(half.X,half.Z)+radius+2+ring*4
   local candidate=origin+Vector3.new(math.cos(angle)*spawnRadius,0,math.sin(angle)*spawnRadius)
   if validPosition(candidate) and #obstacleParts(candidate+Vector3.new(0,3,0),Vector3.new(radius*2,5,radius*2))==0 then return candidate end
  end
 end
 return nil
end
local function resetActor(state)
 state.units,state.buildings,state.technologies,state.pendingTech,state.defenseLast={},{},{},{},{}
 state.modifiers={attack=0,armor=0,hp=0,gather=0,carry=0,speed=0,gatherFood=0,gatherWood=0,gatherGold=0,gatherStone=0,farmCapacity=0,range=0,interval=0,trainSpeed=0}
 state.classModifiers={}
 state.playing,state.defeated,state.advancing=false,false,nil
 state.wonderTimes={}
 state.actor:SetAttribute("WonderRemaining",nil)
 state.actor:SetAttribute("Defeated",false)
 state.actor:SetAttribute("Age",1)
 state.actor:SetAttribute("AgeProgress",0)
 state.actor:SetAttribute("AgeRemaining",0)
 state.actor:SetAttribute("Population",0)
 state.actor:SetAttribute("PopulationCap",0)
 for key in pairs(Config.Technologies) do state.actor:SetAttribute("Tech_"..key,nil) end
 for _,key in ipairs({"food","wood","gold","stone"}) do state.actor:SetAttribute(key,0) end
end
local function humanStates()
 local humans={}
 for actor,state in pairs(states) do if actor:IsA("Player") and actor.Parent==Players then table.insert(humans,state) end end
 table.sort(humans,function(a,b) return a.joined<b.joined end)
 return humans
end
local function updateHost()
 local humans=humanStates()
 workspace:SetAttribute("HostUserId",humans[1] and humans[1].id or 0)
 workspace:SetAttribute("LobbyPlayers",math.min(#humans,4))
 if phase=="Lobby" then
  for index,state in ipairs(humans) do
   state.slot=index<=4 and index or nil
   state.actor:SetAttribute("Spectator",index>4)
   if index<=4 then state.actor:SetAttribute("TeamColor",colors[index]); state.actor:SetAttribute("HomePosition",Config.Spawns[index]) end
  end
 end
end
local function clearMatch()
 matchGeneration+=1
 workspace:SetAttribute("MatchGeneration",matchGeneration)
 for unit in pairs(orders) do stop(unit) end
 for _,state in pairs(states) do
  for unit in pairs(state.units) do destroyModel(unit) end
  for b in pairs(state.buildings) do destroyModel(b) end
 end
 for actor,state in pairs(states) do
  if not actor:IsA("Player") then byId[state.id],states[actor]=nil,nil; actor:Destroy()
  else resetActor(state) end
 end
 training,construction,researching,orders={},{},{},{}
 actionClocks={}
 startingSides=0
 workspace:SetAttribute("AICount",0)
 workspace:SetAttribute("FactionCount",0)
 workspace:SetAttribute("Winner","")
 workspace:SetAttribute("WinnerId",0)
 workspace:SetAttribute("MatchTime",0)
end
local function lobbyReset()
 setPhase("Lobby")
 clearMatch()
 updateHost()
 announce("已返回大廳，房主可調整設定後開始新局。")
end
local function startMatch(player,payload)
 if phase~="Lobby" or workspace:GetAttribute("HostUserId")~=player.UserId then return end
 local humans=humanStates()
 while #humans>4 do table.remove(humans) end
 local validated,message=Rules.settings(payload,#humans)
 if not validated then notify(player,message); return end
 setPhase("Starting")
 clearMatch()
 settings=validated
 local ok,spawns=pcall(World.Generate,settings.size,makeResource)
 if not ok then setPhase("Lobby"); updateHost(); warn("[RTS] 地圖生成失敗："..tostring(spawns)); notify(player,"地圖生成失敗，請查看 Studio 輸出後重試。"); return end
 Config.Spawns=spawns or Config.Spawns
 for model in pairs(managedResources) do if model.Parent~=resources then managedResources[model]=nil end end
 workspace:SetAttribute("Difficulty",settings.difficulty)
 workspace:SetAttribute("VictoryMode",settings.victory)
 workspace:SetAttribute("PopulationLimit",settings.population)
 workspace:SetAttribute("StartingResources",settings.startingResources)
 local participants=table.clone(humans)
 for i=1,settings.aiCount do
  local aiId=-10000-i
  while byId[aiId] do aiId-=100 end
  local actor=Instance.new("Folder")
  actor.Name="AI_"..i
  actor:SetAttribute("UserId",aiId)
  actor:SetAttribute("OwnerId",aiId)
  actor:SetAttribute("DisplayName","電腦 "..i)
  actor:SetAttribute("IsAI",true)
  actor.Parent=factions
  local state={actor=actor,id=aiId,ai=true,aiTurn=0,nextAttack=0,tokens=12,last=os.clock()}
  states[actor],byId[aiId]=state,state
  resetActor(state)
  table.insert(participants,state)
 end
 local initial=Config.Settings.startingResources
 if Config.StartingResources then initial=Config.StartingResources[settings.startingResources] or initial end
 if settings.startingResources=="Rich" and not (Config.StartingResources and Config.StartingResources.Rich) then initial={food=1200,wood=1200,gold=800,stone=600} end
 local made,spawnError=pcall(function()
  for index,state in ipairs(participants) do
   local actor,home=state.actor,Config.Spawns[index]
   state.slot,state.home,state.playing=index,home,true
   actor:SetAttribute("Spectator",false)
   actor:SetAttribute("TeamColor",colors[index])
   actor:SetAttribute("HomePosition",home)
   actor:SetAttribute("FactionSlot",index)
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
 for actor,state in pairs(states) do if actor:IsA("Player") and not state.playing then actor:SetAttribute("Spectator",true) end end
 startingSides,matchStart=#participants,os.clock()
 workspace:SetAttribute("AICount",settings.aiCount)
 workspace:SetAttribute("FactionCount",#participants)
 workspace:SetAttribute("Sandbox",startingSides==1)
 setPhase("Playing")
 print(string.format("[RTS] 對局開始：%d 名玩家、%d 個電腦陣營，地圖 %s。",#humans,settings.aiCount,settings.size))
 announce(startingSides==1 and "沙盒對局開始：可自由練習經濟與建造；投降後返回大廳。" or "對局開始！採集資源、發展時代並擊敗對手。")
end
local function join(player)
 if states[player] then return end
 joinSequence+=1
 local state={actor=player,id=player.UserId,joined=joinSequence,tokens=12,last=os.clock(),ai=false}
 states[player],byId[state.id]=state,state
 resetActor(state)
 player:SetAttribute("IsAI",false)
 player:SetAttribute("Spectator",phase~="Lobby")
 updateHost()
 if phase~="Lobby" then notify(player,"本局已開始，你將觀戰；下一局可加入。") end
end
local function acceptOrder(state,selection,target)
 if type(selection)~="table" or #selection==0 or #selection>200 then return end
 local targetModel=isTarget(target)
 if not targetModel and not validPosition(target) then return end
 local seen={}
 for index,unit in ipairs(selection) do
  if not seen[unit] and isOwned(state,unit,units) then
   seen[unit]=true
   if targetModel then
    local victim,kind=owner(target),unit:GetAttribute("UnitType")
    if enemies(state,victim) then issue(unit,"attack",target)
    elseif kind=="villager" and isOwned(state,target,buildings) and not target:GetAttribute("Complete") then issue(unit,"build",target)
    elseif kind=="villager" and target:GetAttribute("ResourceType") and (not victim or victim==state) and (target:GetAttribute("Amount") or 0)>0 and (target.Parent~=buildings or target:GetAttribute("Complete")) then
     if (unit:GetAttribute("Carrying") or 0)>0 and unit:GetAttribute("CarryType")~=target:GetAttribute("ResourceType") then beginDelivery(state,unit,target) else issue(unit,"gather",target) end
    elseif kind=="villager" and isOwned(state,target,buildings) and (target:GetAttribute("HP") or 0)<(target:GetAttribute("MaxHP") or 0) then issue(unit,"repair",target)
    elseif kind=="villager" and isOwned(state,target,buildings) and (unit:GetAttribute("Carrying") or 0)>0 then beginDelivery(state,unit,nil) end
   else
    local columns=math.ceil(math.sqrt(#selection))
    local offset=Vector3.new(((index-1)%columns-(columns-1)/2)*4,0,math.floor((index-1)/columns)*4)
    local goal=Vector3.new(target.X,Config.Map.GroundY,target.Z)+offset
    if validPosition(goal) then issue(unit,"move",goal) end
   end
  end
 end
end
command.OnServerEvent:Connect(function(player,action,a,b,c)
 local state=states[player]
 if not state or type(action)~="string" then return end
 local now=os.clock()
 state.tokens=math.min(12,state.tokens+(now-state.last)*6)
 state.last=now
 if state.tokens<1 then return end
 state.tokens-=1
 if action=="StartMatch" then startMatch(player,a); return end
 if action=="RestartMatch" then if phase=="Ended" and workspace:GetAttribute("HostUserId")==player.UserId then lobbyReset() end; return end
 if phase~="Playing" or not alive(state) then return end
 if action=="Surrender" then defeat(state,"你已投降，可以繼續觀戰。"); if startingSides==1 then endMatch(nil) end
 elseif action=="Build" then buildRequest(state,a,b,false)
 elseif action=="Train" then trainRequest(state,a,b,false)
 elseif action=="AdvanceAge" then advanceRequest(state,a,false)
 elseif action=="Research" then researchRequest(state,a,b,false)
 elseif action=="Trade" then
  if not isOwned(state,a,buildings) or a:GetAttribute("BuildingType")~="Market" or not a:GetAttribute("Complete") then return end
  if type(b)~="string" or not ({food=true,wood=true,stone=true})[b] or (c~="Buy" and c~="Sell") then return end
  local market=Config.MarketTrade or {batch=100,buyGold=130,sellGold=70}
  local cost=c=="Buy" and {gold=market.buyGold} or {[b]=market.batch}
  if not Economy.spend(player,cost) then notify(player,"交易所需資源不足。"); return end
  local key,amount=c=="Buy" and b or "gold",c=="Buy" and market.batch or market.sellGold
  player:SetAttribute(key,(player:GetAttribute(key) or 0)+amount)
 elseif action=="Order" then acceptOrder(state,a,b)
 elseif action=="Stop" then
  if type(a)~="table" or #a>200 then return end
  for _,unit in ipairs(a) do if isOwned(state,unit,units) then stop(unit) end end
 end
end)
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player)
 local state=states[player]
 if not state then return end
 if phase=="Playing" and alive(state) then defeat(state,"玩家已離開。") end
 for unit in pairs(state.units) do destroyModel(unit) end
 for b in pairs(state.buildings) do destroyModel(b) end
 states[player],byId[state.id]=nil,nil
 updateHost()
 checkVictory()
 if #humanStates()==0 then lobbyReset() end
end)

local function aiBuild(state,kind)
 local data=Config.Buildings[kind]
 if state.pendingBuild and state.pendingBuild.kind~=kind then return false end
 if not data or not affordable(state.actor,data.cost) then return false end
 for b in pairs(state.buildings) do if b:GetAttribute("BuildingType")==kind and not b:GetAttribute("Complete") then return false end end
 local home=state.home
 for ring=1,4 do
  for index=0,11 do
   local angle=index*math.pi/6
   local radius=44+ring*24
   local candidate=home+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
   local pos=Grid.snap(candidate,data.size)
   if validPosition(pos) and Grid.inBounds(pos,data.size) and placementClear(pos,data) then
    if buildRequest(state,kind,pos,true) then return true end
    local builder,distance=nil,math.huge
    for unit in pairs(state.units) do
     local order=orders[unit]
     if unit:GetAttribute("UnitType")=="villager" and (not order or (order.kind~="build" and order.kind~="move")) then
      local d=(position(unit)-pos).Magnitude
      if d<distance then builder,distance=unit,d end
     end
    end
    if builder and distance>75 then
     local outward=position(builder)-pos
     local direction=outward.Magnitude>0.01 and outward.Unit or Vector3.new(1,0,0)
     local staging=pos+direction*(math.max(data.size.X,data.size.Y)*GRID_SIZE/2+8)
     issue(builder,"move",staging)
     state.pendingBuild={kind=kind,pos=pos}
     return false
    end
   end
  end
 end
 return false
end
local function aiStep(state,now)
 if not alive(state) then return end
 state.aiTurn+=1
 if state.pendingBuild then
  local pending=state.pendingBuild
  if buildRequest(state,pending.kind,pending.pos,true) or state.aiTurn%6==0 then state.pendingBuild=nil end
 end
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
 local ratios={wood=0.36,food=0.42,gold=0.16,stone=0.06}
 for _,unit in ipairs(idle) do
  if (unit:GetAttribute("Carrying") or 0)>0 then beginDelivery(state,unit,nil)
  else
   local key,need="food",-math.huge
   for _,resourceKind in ipairs({"food","wood","gold","stone"}) do
    local score=villagerCount*ratios[resourceKind]-gathering[resourceKind]
    if resourceKind=="food" and (state.actor:GetAttribute("food") or 0)<150 then score+=1 end
    if score>need then key,need=resourceKind,score end
   end
   local target=nearestResource(state,position(unit),key)
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
  if target then for _,unit in ipairs(military) do issue(unit,"attack",target,true) end end
 end
end
local spatial={}
local CELL=64
local function rebuildSpatial()
 spatial={}
 for _,state in pairs(states) do
  if alive(state) then
   for _,models in ipairs({state.units,state.buildings}) do
    for model in pairs(models) do
     if model.Parent then
      local p=position(model)
      local key=math.floor(p.X/CELL)..":"..math.floor(p.Z/CELL)
      local bucket=spatial[key] or {}
      table.insert(bucket,model)
      spatial[key]=bucket
     end
    end
   end
  end
 end
end
local function nearestEnemy(state,current,radius)
 local found,nearest=nil,radius
 local cells=math.ceil(radius/CELL)
 local x,z=math.floor(current.X/CELL),math.floor(current.Z/CELL)
 for dx=-cells,cells do
  for dz=-cells,cells do
   for _,target in ipairs(spatial[(x+dx)..":"..(z+dz)] or {}) do
    if target.Parent and enemies(state,owner(target)) then
     local distance=distanceTo(target,current)
     if distance<nearest then found,nearest=target,distance end
    end
   end
  end
 end
 return found
end
local function combatStep(now)
 rebuildSpatial()
 for _,state in pairs(states) do
  if alive(state) then
   for unit in pairs(state.units) do
    local kind,order=unit:GetAttribute("UnitType"),orders[unit]
    if kind~="villager" and (not order or (order.kind=="attack" and order.automatic)) then
     local target=nearestEnemy(state,position(unit),72)
     if target and (not order or order.target~=target) then issue(unit,"attack",target,true) end
    end
   end
   for b in pairs(state.buildings) do
    local data=Config.Buildings[b:GetAttribute("BuildingType")]
    if b:GetAttribute("Complete") and data.damage and now-(state.defenseLast[b] or 0)>=(data.attackInterval or 1.5) then
     local target=nearestEnemy(state,position(b),data.range or 64)
     if target then
      state.defenseLast[b]=now
      b:SetAttribute("AttackPosition",position(target))
      b:SetAttribute("LastAttack",now)
      damage(target,data.damage+state.modifiers.attack,b,now)
     end
    end
   end
  end
 end
end
local function productionStep(dt)
 for b,item in pairs(construction) do
  if b.Parent~=buildings or not alive(item.state) then construction[b]=nil
  else
   local builders=0
   for unit in pairs(item.state.units) do local order=orders[unit]; if order and order.kind=="build" and order.target==b and distanceTo(b,position(unit))<=6 then builders+=1 end end
   if builders>0 then
    local work=math.min(item.duration-item.work,dt*(1+(builders-1)*0.5))
    item.work+=work
    local max=b:GetAttribute("MaxHP")
    b:SetAttribute("HP",math.min(max,(b:GetAttribute("HP") or 0)+work/item.duration*max*0.85))
    b:SetAttribute("ConstructionProgress",item.work/item.duration)
    b:SetAttribute("ConstructionRemaining",math.ceil(item.duration-item.work))
    if item.work>=item.duration then
     construction[b]=nil
     b:SetAttribute("Complete",true)
     b:SetAttribute("ConstructionProgress",1)
     b:SetAttribute("ConstructionRemaining",0)
     population(item.state)
     for unit in pairs(item.state.units) do
      local order=orders[unit]
      if order and order.kind=="build" and order.target==b then
       if b:GetAttribute("BuildingType")=="Farm" then issue(unit,"gather",b) else stop(unit) end
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
     if not ok then warn("[RTS] 單位生成失敗："..tostring(model)); refund(item.state.actor,Config.Units[item.kind].cost) end
     table.remove(queue,1)
     if #queue==0 then training[b]=nil end
     population(item.state)
    end
   end
   queueAttributes(b)
  end
 end
 for b,item in pairs(researching) do
  if b.Parent~=buildings or not alive(item.state) then researching[b]=nil
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
      if farm:GetAttribute("BuildingType")=="Farm" then farm:SetAttribute("Amount",(farm:GetAttribute("Amount") or 0)+data.effect.farmCapacity); farm:SetAttribute("MaxAmount",(farm:GetAttribute("MaxAmount") or 0)+data.effect.farmCapacity) end
     end
    end
    for unit in pairs(state.units) do refreshUnit(state,unit) end
    researching[b]=nil
    b:SetAttribute("Research",nil)
    b:SetAttribute("ResearchRemaining",nil)
    b:SetAttribute("ResearchProgress",nil)
    notify(state.actor,data.name.." 研究完成。")
   end
  end
 end
 for _,state in pairs(states) do
  local item=state.advancing
  if alive(state) and item then
   if item.building.Parent~=buildings then state.advancing=nil; state.actor:SetAttribute("AgeRemaining",0)
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
     announce(actorName(state.actor).." 已進入"..Config.Ages[item.age].name.."。")
    end
   end
  end
 end
end
local function orderStep(dt,now)
 for unit,order in pairs(orders) do
  local state=owner(unit)
  if unit.Parent~=units or not alive(state) then orders[unit]=nil; continue end
  local target=order.target
  if order.kind~="move" and (not target.Parent or (order.kind=="gather" and (target:GetAttribute("Amount") or 0)<=0)) then
   if order.kind=="gather" then
    local key=unit:GetAttribute("CarryType")
    if (unit:GetAttribute("Carrying") or 0)>0 then beginDelivery(state,unit,nil)
    else local replacement=nearestResource(state,position(unit),key); if replacement then issue(unit,"gather",replacement) else stop(unit) end end
   elseif order.kind=="deliver" then beginDelivery(state,unit,order.returnTarget)
   else stop(unit) end
   continue
  end
  if order.kind=="attack" and not enemies(state,owner(target)) then stop(unit); continue end
  if order.kind=="build" and target:GetAttribute("Complete") then stop(unit); continue end
  local current=position(unit)
  local stats=unitStats(state,unit:GetAttribute("UnitType"),order.kind=="gather" and target:GetAttribute("ResourceType") or nil)
  local destination=order.kind=="move" and target or edgePosition(target,current)
  local range=order.kind=="move" and 1 or order.kind=="attack" and stats.range or 5
  if (destination-current).Magnitude<=range then
   order.path=nil
   unit:SetAttribute("Animation",order.kind=="attack" and "Attack" or (order.kind=="gather" or order.kind=="build" or order.kind=="repair") and "Work" or "Idle")
   if order.kind=="move" then stop(unit)
   elseif order.kind=="deliver" then
    local key,carrying=unit:GetAttribute("CarryType"),unit:GetAttribute("Carrying") or 0
    if carrying>0 and ({food=true,wood=true,gold=true,stone=true})[key] then state.actor:SetAttribute(key,(state.actor:GetAttribute(key) or 0)+carrying); unit:SetAttribute("Carrying",0) end
    local returnTarget=order.returnTarget
    if not returnTarget or not returnTarget.Parent or (returnTarget:GetAttribute("Amount") or 0)<=0 then returnTarget=nearestResource(state,current,key) end
    if returnTarget then issue(unit,"gather",returnTarget) else stop(unit) end
   elseif order.kind=="gather" and UnitRules.takeAction(actionClocks,unit,"gather",now,1) then
    local key=target:GetAttribute("ResourceType")
    local carrying=unit:GetAttribute("Carrying") or 0
    local amount=math.min(stats.gather,target:GetAttribute("Amount") or 0,math.max(0,stats.carry-carrying))
    target:SetAttribute("Amount",math.max(0,(target:GetAttribute("Amount") or 0)-amount))
    unit:SetAttribute("CarryType",key)
    unit:SetAttribute("Carrying",carrying+amount)
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
   elseif order.kind=="repair" and UnitRules.takeAction(actionClocks,unit,"repair",now,1) then
    if (target:GetAttribute("HP") or 0)>=(target:GetAttribute("MaxHP") or 0) then stop(unit)
    elseif Economy.spend(state.actor,{wood=1}) then target:SetAttribute("HP",math.min(target:GetAttribute("MaxHP"),target:GetAttribute("HP")+15)) end
   end
  else
   local goal=destination
   if order.kind~="move" then local outward=current-destination; if outward.Magnitude>0.01 then goal=destination+outward.Unit*math.max(1,range-1) end end
   if order.path and order.kind=="attack" and now-order.lastPath>4 then order.path=nil end
   moveToward(unit,order,goal,stats.speed,dt,now)
  end
 end
end

workspace:SetAttribute("Winner","")
workspace:SetAttribute("MatchTime",0)
workspace:SetAttribute("VictoryMode","Conquest")
workspace:SetAttribute("Sandbox",false)
setPhase("Lobby")
World.Generate("Medium",makeResource)
for _,player in ipairs(Players:GetPlayers()) do join(player) end
local accumulated,combatElapsed,aiElapsed,attributeElapsed=0,0,0,0
RunService.Heartbeat:Connect(function(dt)
 if phase~="Playing" then return end
 accumulated+=dt
 combatElapsed+=dt
 aiElapsed+=dt
 attributeElapsed+=dt
 if accumulated<0.1 then return end
 local step=math.min(accumulated,0.3)
 accumulated=0
 local now=os.clock()
 updateObstacleFilters()
 if attributeElapsed>=1 then
  workspace:SetAttribute("MatchTime",math.floor(now-matchStart))
  attributeElapsed=0
  for _,state in pairs(states) do
   if alive(state) then
    local removed=false
    for unit in pairs(state.units) do
     if unit.Parent~=units then state.units[unit]=nil; orders[unit]=nil; actionClocks[unit]=nil; removed=true end
    end
    for building in pairs(state.buildings) do
     if building.Parent~=buildings then
      state.buildings[building]=nil
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
 if combatElapsed>=0.6 then combatElapsed=0; combatStep(now) end
 if aiElapsed>=2 then aiElapsed=0; for _,state in pairs(states) do if state.ai then aiStep(state,now) end end end
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
     if remaining<=0 then endMatch(state); break end
    else state.actor:SetAttribute("WonderRemaining",nil) end
   end
  end
 end
end)
workspace:SetAttribute("RTSReady",true)
