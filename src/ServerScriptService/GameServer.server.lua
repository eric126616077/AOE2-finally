local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local PathfindingService=game:GetService("PathfindingService")
local Config=require(RS.GameData.GameConfig)
local Grid=require(RS.Shared.Grid)
local Factory=require(script.Parent.ServerModules.ModelFactory)
local Economy=require(script.Parent.ServerModules.Economy)
local GRID_SIZE=Config.Map.GridSize
Players.CharacterAutoLoads=false
workspace:WaitForChild("AOE2_Ground")
local function folder(parent,name)
 local f=parent:FindFirstChild(name) or Instance.new("Folder")
 f.Name,f.Parent=name,parent
 return f
end
local buildings=folder(workspace,"Buildings")
local resources=folder(workspace,"Resources")
local units=folder(workspace,"Units")
local remotes=folder(RS,"RTSRemotes")
local command=Instance.new("RemoteEvent")
command.Name,command.Parent="Command",remotes
local feedback=Instance.new("RemoteEvent")
feedback.Name,feedback.Parent="Feedback",remotes
local states, slots, orders, training = {}, {}, {}, {}
local started=false
local function notify(player,message) feedback:FireClient(player,message) end
local function position(model)
 local p=model:GetPivot().Position
 return Vector3.new(p.X,0,p.Z)
end
local function population(player)
 local count,cap=0,0
 for _, u in ipairs(units:GetChildren()) do if u:GetAttribute("OwnerId")==player.UserId then count+=1 end end
 for _, b in ipairs(buildings:GetChildren()) do
  if b:GetAttribute("OwnerId")==player.UserId then
   local data=Config.Buildings[b:GetAttribute("BuildingType")]
   cap+=data and data.population or 0
   if training[b] then count+=1 end
  end
 end
 cap=math.min(cap,Config.Settings.populationLimit)
 player:SetAttribute("Population",count)
 player:SetAttribute("PopulationCap",cap)
 return count,cap
end
local function pay(player,cost)
 return Economy.spend(player,cost)
end
local function makeBuilding(player,kind,pos)
 local data=Config.Buildings[kind]
 local model=Factory.model(kind,pos,Vector3.new(data.size.X*GRID_SIZE,data.height,data.size.Y*GRID_SIZE),data.color,"Buildings",player:GetAttribute("TeamColor"))
 model:SetAttribute("BuildingType",kind)
 model:SetAttribute("DisplayName",data.name)
 model:SetAttribute("HP",data.hp)
 model:SetAttribute("MaxHP",data.hp)
 model:SetAttribute("OwnerId",player.UserId)
 model:SetAttribute("OwnerName",player.DisplayName)
 if kind=="Farm" then
  model:SetAttribute("ResourceType","food")
  model:SetAttribute("Amount",600)
  model:SetAttribute("MaxAmount",600)
 end
 model.Parent=buildings
 population(player)
 return model
end
local function makeUnit(player,kind,pos)
 local unit=Factory.unit(kind,pos,Config.Units[kind],player)
 unit.Parent=units
 population(player)
 return unit
end
local function makeResource(kind,pos)
 local data=Config.Resources[kind]
 local model=Factory.model(kind,pos,Vector3.new(8,data.height,8),data.color,"Resource")
 model:SetAttribute("ResourceType",data.resource)
 model:SetAttribute("DisplayName",data.name)
 model:SetAttribute("Amount",data.amount)
 model:SetAttribute("MaxAmount",data.amount)
 model.Parent=resources
end
-- Every starting location has the same nearby economy, independent of random seed.
for _, spawn in ipairs(Config.Spawns) do
 local direction=Vector3.new(spawn.X>0 and -1 or 1,0,spawn.Z>0 and -1 or 1)
 for index,kind in ipairs({"Tree","Tree","Berries","Gold","Stone"}) do
  makeResource(kind,spawn+Vector3.new(direction.X*(48+index*8),0,direction.Z*64))
 end
end
local random=Random.new(Config.Map.Seed)
for index=1,70 do
 local pos=Vector3.new(random:NextInteger(-27,27)*8+4,0,random:NextInteger(-27,27)*8+4)
 local clear=true
 for _, spawn in ipairs(Config.Spawns) do if (pos-spawn).Magnitude<115 then clear=false end end
 for _, resource in ipairs(resources:GetChildren()) do if (pos-position(resource)).Magnitude<16 then clear=false end end
 if clear then makeResource(({"Tree","Tree","Tree","Gold","Stone","Berries"})[random:NextInteger(1,6)],pos) end
end
local function isOwned(player,model,parent)
 return typeof(model)=="Instance" and model:IsA("Model") and model.Parent==parent and model:GetAttribute("OwnerId")==player.UserId
end
local function isTarget(model)
 return typeof(model)=="Instance" and model:IsA("Model") and (model.Parent==buildings or model.Parent==units or model.Parent==resources)
end
local function validPosition(pos)
 return typeof(pos)=="Vector3" and Grid.isFinite(pos.X) and Grid.isFinite(pos.Y) and Grid.isFinite(pos.Z)
  and math.abs(pos.X)<=Config.Map.MapSize/2-3 and math.abs(pos.Z)<=Config.Map.MapSize/2-3
end
local function placementClear(pos,data)
 local params=OverlapParams.new()
 params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={buildings,resources,units}
 return #workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*GRID_SIZE-0.2,data.height,data.size.Y*GRID_SIZE-0.2),params)==0
end
local function stop(unit)
 orders[unit]=nil
 if unit.Parent then unit:SetAttribute("Order","待命") end
end
local function route(unit,order,goal)
 if order.computing then return end
 order.computing=true
 order.lastPath=os.clock()
 task.spawn(function()
  local path=PathfindingService:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=false,WaypointSpacing=4})
  local ok=pcall(function() path:ComputeAsync(position(unit)+Vector3.new(0,2,0),goal+Vector3.new(0,2,0)) end)
  if orders[unit]~=order or not unit.Parent then return end
  order.computing=false
  if ok and path.Status==Enum.PathStatus.Success then
   order.path=path:GetWaypoints()
   order.index=2
  else
   stop(unit)
   local owner=Players:GetPlayerByUserId(unit:GetAttribute("OwnerId"))
   if owner then notify(owner,"無法抵達目標，請選擇其他位置。") end
  end
 end)
end
local function issue(unit,kind,target)
 local order={kind=kind,target=target,lastAction=0,lastPath=0}
 orders[unit]=order
 unit:SetAttribute("Order",({move="移動",gather="採集",attack="攻擊"})[kind])
end
local function checkVictory()
 if not started or workspace:GetAttribute("MatchEnded") then return end
 local survivors={}
 for player,state in pairs(states) do if not state.defeated then table.insert(survivors,player) end end
 if #survivors<=1 then
  workspace:SetAttribute("MatchEnded",true)
  local winner=survivors[1]
  workspace:SetAttribute("Winner",winner and winner.DisplayName or "無")
  for player in pairs(states) do notify(player,winner and (winner.DisplayName.." 獲得勝利！重新測試可開始新局。") or "對局結束") end
 end
end
local function defeat(player)
 local state=states[player]
 if not state or state.defeated then return end
 state.defeated=true
 player:SetAttribute("Defeated",true)
 for _, unit in ipairs(units:GetChildren()) do
  if unit:GetAttribute("OwnerId")==player.UserId then stop(unit); unit:Destroy() end
 end
 for _, b in ipairs(buildings:GetChildren()) do
  if b:GetAttribute("OwnerId")==player.UserId then training[b]=nil; b:Destroy() end
 end
 population(player)
 notify(player,"主堡已被摧毀，你已戰敗。")
 checkVictory()
end
local colors={Color3.fromRGB(80,151,224),Color3.fromRGB(209,83,75),Color3.fromRGB(218,177,70),Color3.fromRGB(136,101,190)}
local function join(player)
 if states[player] then return end
 if workspace:GetAttribute("MatchEnded") then player:SetAttribute("Spectator",true); return end
 local slot
 for i=1,Config.Settings.maxPlayers do if not slots[i] then slot=i; break end end
 if not slot then player:SetAttribute("Spectator",true); return end
 slots[slot]=player
 states[player]={slot=slot,tokens=12,last=os.clock(),defeated=false}
 player:SetAttribute("TeamColor",colors[slot])
 for key,value in pairs(Config.Settings.startingResources) do player:SetAttribute(key,value) end
 player:SetAttribute("HomePosition",Config.Spawns[slot])
 makeBuilding(player,"Castle",Config.Spawns[slot])
 for i=1,Config.Settings.startingVillagers do makeUnit(player,"villager",Config.Spawns[slot]+Vector3.new(-12+i*6,0,44)) end
 local count=0
 for _ in pairs(states) do count+=1 end
 if count>=2 then started=true end
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player)
 local state=states[player]
 if not state then return end
 states[player]=nil
 slots[state.slot]=nil
 for _, model in ipairs(units:GetChildren()) do if model:GetAttribute("OwnerId")==player.UserId then orders[model]=nil; model:Destroy() end end
 for _, model in ipairs(buildings:GetChildren()) do if model:GetAttribute("OwnerId")==player.UserId then training[model]=nil; model:Destroy() end end
 checkVictory()
end)
for _, player in ipairs(Players:GetPlayers()) do join(player) end
command.OnServerEvent:Connect(function(player,action,a,b)
 local state=states[player]
 if not state or state.defeated or workspace:GetAttribute("MatchEnded") then return end
 local now=os.clock()
 state.tokens=math.min(12,state.tokens+(now-state.last)*6)
 state.last=now
 if state.tokens<1 then return end
 state.tokens-=1
 if action=="Build" then
  if type(a)~="string" or a=="Castle" or not Config.Buildings[a] or not validPosition(b) then return end
  local data=Config.Buildings[a]
  local pos=Grid.snap(b,data.size)
  if not Grid.inBounds(pos,data.size) or not placementClear(pos,data) then notify(player,"此處有障礙物或超出地圖。") return end
  local nearby=false
  for _, unit in ipairs(units:GetChildren()) do
   if isOwned(player,unit,units) and unit:GetAttribute("UnitType")=="villager" and (position(unit)-pos).Magnitude<=80 then nearby=true; break end
  end
  if not nearby then notify(player,"需要一名村民在建築位置 80 studs 內。") return end
  if not pay(player,data.cost) then notify(player,"資源不足："..Grid.costText(data.cost)) return end
  local ok,err=pcall(makeBuilding,player,a,pos)
  if not ok then
   for key,value in pairs(data.cost) do player:SetAttribute(key,player:GetAttribute(key)+value) end
   warn("Building creation failed: "..tostring(err))
   notify(player,"建築模型載入失敗，已退還資源。")
   return
  end
  notify(player,data.name.." 已建造")
 elseif action=="Train" then
  if not isOwned(player,a,buildings) or type(b)~="string" or not Config.Units[b] then return end
  local kind=a:GetAttribute("BuildingType")
  if not ((b=="villager" and (kind=="Castle" or kind=="TownCenter")) or (b=="infantry" and kind=="Barracks")) then return end
  if training[a] then notify(player,"此建築正在訓練單位。") return end
  local count,cap=population(player)
  if count>=cap then notify(player,"人口已滿，請建造房屋。") return end
  if not pay(player,Config.Units[b].cost) then notify(player,"訓練所需資源不足。") return end
  training[a]={kind=b,ends=now+Config.Units[b].trainTime,player=player}
  a:SetAttribute("Training",Config.Units[b].name)
  a:SetAttribute("TrainingRemaining",Config.Units[b].trainTime)
  population(player)
 elseif action=="Order" then
  if type(a)~="table" or #a>60 then return end
  local targetModel=isTarget(b)
  if not targetModel and not validPosition(b) then return end
  for index,unit in ipairs(a) do
   if isOwned(player,unit,units) then
    if targetModel then
     local owner=b:GetAttribute("OwnerId")
     if owner and owner~=player.UserId and (b.Parent==units or b.Parent==buildings) then issue(unit,"attack",b)
     elseif b:GetAttribute("ResourceType") and (not owner or owner==player.UserId) and unit:GetAttribute("UnitType")=="villager" then issue(unit,"gather",b) end
    else
     local offset=Vector3.new(((index-1)%5)*4,0,math.floor((index-1)/5)*4)
     local goal=b+offset
     if validPosition(goal) then issue(unit,"move",Vector3.new(goal.X,0,goal.Z)) end
    end
   end
  end
 elseif action=="Stop" then
  if type(a)~="table" or #a>60 then return end
  for _, unit in ipairs(a) do if isOwned(player,unit,units) then stop(unit) end end
 end
end)
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt
 if elapsed<0.1 then return end
 local step=math.min(elapsed,0.25)
 elapsed=0
 if workspace:GetAttribute("MatchEnded") then return end
 local now=os.clock()
 for building,item in pairs(training) do
  if not building.Parent then training[building]=nil
  elseif now>=item.ends then
   local radius=building:GetAttribute("Radius")+6
   local origin=position(building)
   local spawn
   local params=OverlapParams.new()
   params.FilterType=Enum.RaycastFilterType.Include
   params.FilterDescendantsInstances={buildings,resources,units}
   for i=0,7 do
    local angle=i*math.pi/4
    local candidate=origin+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
    if validPosition(candidate) and #workspace:GetPartBoundsInBox(CFrame.new(candidate+Vector3.new(0,3,0)),Vector3.new(4,5,4),params)==0 then spawn=candidate; break end
   end
   if spawn then
    training[building]=nil
    building:SetAttribute("Training",nil)
    building:SetAttribute("TrainingRemaining",nil)
    makeUnit(item.player,item.kind,spawn)
   else building:SetAttribute("TrainingRemaining",0) end
  else building:SetAttribute("TrainingRemaining",math.ceil(item.ends-now)) end
 end
 for unit,order in pairs(orders) do
  if not unit.Parent then orders[unit]=nil; continue end
  local target=order.target
  if order.kind~="move" and (not target.Parent or (order.kind=="gather" and (target:GetAttribute("Amount") or 0)<=0)) then stop(unit); continue end
  local current=position(unit)
  local destination=order.kind=="move" and target or position(target)
  if order.kind~="move" then
   -- Approach the nearest footprint edge, not a circle inside square buildings.
   local footprint=target.PrimaryPart
   local half=footprint and footprint.Size/2 or Vector3.new(2,2,2)
   destination=Vector3.new(math.clamp(current.X,destination.X-half.X,destination.X+half.X),0,math.clamp(current.Z,destination.Z-half.Z,destination.Z+half.Z))
  end
  local data=Config.Units[unit:GetAttribute("UnitType")]
  local range=order.kind=="move" and 1 or (order.kind=="attack" and data.range or 4)
  local distance=(destination-current).Magnitude
  if distance<=range then
   order.path=nil
   if order.kind=="move" then stop(unit)
   elseif now-order.lastAction>=1 then
    order.lastAction=now
    local owner=Players:GetPlayerByUserId(unit:GetAttribute("OwnerId"))
    if order.kind=="gather" and owner then
     local key=target:GetAttribute("ResourceType")
     local amount=math.min(5,target:GetAttribute("Amount") or 0)
     target:SetAttribute("Amount",target:GetAttribute("Amount")-amount)
     owner:SetAttribute(key,(owner:GetAttribute(key) or 0)+amount)
     if target:GetAttribute("Amount")<=0 and target.Parent==resources then target:Destroy() end
    elseif order.kind=="attack" then
     local hp=math.max(0,(target:GetAttribute("HP") or 0)-data.damage)
     target:SetAttribute("HP",hp)
     if hp<=0 then
      local victim=Players:GetPlayerByUserId(target:GetAttribute("OwnerId"))
      local main=target:GetAttribute("BuildingType")=="Castle"
      orders[target],training[target]=nil,nil
      target:Destroy()
      if victim then if main then defeat(victim) else population(victim) end end
     end
    end
   end
  else
   local goal=destination
   if order.kind~="move" then goal=destination+(current-destination).Unit*math.max(1,range-1) end
   if not order.path or now-order.lastPath>2 then route(unit,order,goal) end
   if order.path and order.path[order.index] then
    local waypoint=order.path[order.index].Position
    local flat=Vector3.new(waypoint.X,0,waypoint.Z)
    local delta=flat-current
    if delta.Magnitude<0.6 then order.index+=1
    else
     local nextPos=current+delta.Unit*math.min(delta.Magnitude,data.speed*step)
     local params=RaycastParams.new()
     params.FilterType=Enum.RaycastFilterType.Include
     params.FilterDescendantsInstances={buildings,resources}
     if not workspace:Raycast(current+Vector3.new(0,2,0),nextPos-current,params) then
      unit:PivotTo(CFrame.lookAt(nextPos+Vector3.new(0,2.5,0),nextPos+delta.Unit+Vector3.new(0,2.5,0)))
     else order.path=nil end
    end
   elseif order.path then order.path=nil end
  end
 end
end)
workspace:SetAttribute("RTSReady",true)
