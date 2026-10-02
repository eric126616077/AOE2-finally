-- Balanced resource quotas with independently grown patches, rather than mirrored tiles.
-- Optional explicit seeds reproduce a map; normal matches receive a fresh server seed.
local Config = require(game.ReplicatedStorage.GameData.GameConfig)
local WorldGenerator = {}
local lastRandomSeed
local function distanceSquared(a,b)
 local x,z=a.X-b.X,a.Z-b.Z
 return x*x+z*z
end
function WorldGenerator.Generate(sizeName, makeResource, seed)
 sizeName = Config.Map.Sizes[sizeName] and sizeName or "Medium"
 local layout=Config.Map.ResourceLayout
 local size=Config.Map.Sizes[sizeName]
 local half,base=size/2,size/2-168
 local spawns={Vector3.new(-base,0,-base),Vector3.new(base,0,base),Vector3.new(base,0,-base),Vector3.new(-base,0,base)}
 local target=Config.Map.ResourceNodeTargets[sizeName]
 local openingCount=0
 for _,patch in ipairs(layout.OpeningClusters) do openingCount+=patch.count end
 assert(target>=openingCount*#spawns,"地圖資源預算不足以配置開局資源")
 if seed==nil then
  if Config.Map.RandomizeSeed then
   seed=Random.new():NextInteger(1,2147483646)
   if seed==lastRandomSeed then seed=seed%2147483646+1 end
   lastRandomSeed=seed
  else seed=Config.Map.Seed end
 end
 assert(type(seed)=="number" and seed==seed and seed%1==0 and seed>=1 and seed<=2147483646,"地圖種子必須是有效正整數")
 local random=Random.new(seed)
 local buckets,plan={},{}
 local clusterId=0
 local bucketSize=layout.ClusterSeparation
 local roadClearance=Config.Map.RoadWidth/2+Config.Map.ResourceFootprint/math.sqrt(2)+1
 local function key(x,z) return tostring(x)..":"..tostring(z) end
 local function clear(position,slot,opening)
  if math.abs(position.X)>half-layout.BorderMargin or math.abs(position.Z)>half-layout.BorderMargin then return false end
  local home=spawns[slot]
  if position.X*home.X<=0 or position.Z*home.Z<=0 then return false end
  for _,spawn in ipairs(spawns) do
   if distanceSquared(position,spawn)<layout.BaseClearance^2 then return false end
  end
  if opening and distanceSquared(position,home)>layout.OpeningRadius^2 then return false end
  if position.X^2+position.Z^2<layout.CenterClearance^2 then return false end
  if math.abs(math.abs(position.X)-math.abs(position.Z))/math.sqrt(2)<roadClearance then return false end
  local bx,bz=math.floor(position.X/bucketSize),math.floor(position.Z/bucketSize)
  for dx=-1,1 do for dz=-1,1 do
   local nearby=buckets[key(bx+dx,bz+dz)]
   if nearby then for _,other in ipairs(nearby) do
    if distanceSquared(position,other)<layout.ClusterSeparation^2 then return false end
   end end
  end end
  return true
 end
 -- Fill the middle before the fringe: big woods should be dense groves rather
 -- than long branches with empty holes. A different ellipse and scored fringe
 -- retain an irregular outline for every independent patch.
 local directions={{1,0},{-1,0},{0,1},{0,-1}}
 local function shape(count)
  local cells,frontier,seen={{x=0,z=0}},{},{["0:0"]=true}
  local radius=math.ceil(math.sqrt(count/math.pi))+2
  local aspect=random:NextNumber(0.9,1.1)
  local function expand(cell)
   for _,direction in ipairs(directions) do
    local x,z=cell.x+direction[1],cell.z+direction[2]
    local k=key(x,z)
    if not seen[k] and x*x+z*z<=radius*radius then
     seen[k]=true
     table.insert(frontier,{x=x,z=z,score=x*x/(aspect*aspect)+z*z*aspect*aspect+random:NextNumber(0,1.5)})
    end
   end
  end
  expand(cells[1])
  while #cells<count do
   local index=1
   for i=2,#frontier do
    if frontier[i].score<frontier[index].score then index=i end
   end
   local cell=table.remove(frontier,index)
   table.insert(cells,cell)
   expand(cell)
  end
  local cx,cz=0,0
  for _,cell in ipairs(cells) do cx+=cell.x; cz+=cell.z end
  cx,cz=cx/count,cz/count
  -- Gameplay footprints stay axis-aligned. Limit the tilt so their inflated
  -- villager collision boxes cannot join up and seal the interior of a grove.
  local angle=random:NextInteger(0,3)*math.pi/2+random:NextNumber(-layout.MaxClusterTilt,layout.MaxClusterTilt)
  local cosine,sine=math.cos(angle),math.sin(angle)
  local offsets={}
  for _,cell in ipairs(cells) do
   local x,z=(cell.x-cx)*layout.ClusterSpacing,(cell.z-cz)*layout.ClusterSpacing
   table.insert(offsets,{x=x*cosine-z*sine+random:NextNumber(-layout.NodeJitter,layout.NodeJitter),z=x*sine+z*cosine+random:NextNumber(-layout.NodeJitter,layout.NodeJitter)})
  end
  return offsets
 end
 local function place(kind,count,slot,opening)
  -- Retry the whole patch, so rejected tiles never turn into isolated speckles.
  for attempt=1,320 do
   local cx,cz
   if opening then
    local angle=random:NextNumber(0,math.pi*2)
    local radius=random:NextNumber(layout.BaseClearance+32,layout.OpeningRadius-20)
    cx,cz=spawns[slot].X+math.cos(angle)*radius,spawns[slot].Z+math.sin(angle)*radius
   else
    local signX=spawns[slot].X>0 and 1 or -1
    local signZ=spawns[slot].Z>0 and 1 or -1
    cx,cz=signX*random:NextNumber(24,half-layout.BorderMargin),signZ*random:NextNumber(24,half-layout.BorderMargin)
   end
   local positions={}
   local valid=true
   for _,offset in ipairs(shape(count)) do
    local position=Vector3.new(cx+offset.x,0,cz+offset.z)
    if not clear(position,slot,opening) then valid=false; break end
    for _,other in ipairs(positions) do
     if distanceSquared(position,other)<layout.MinNodeSpacing^2 then valid=false; break end
    end
    if not valid then break end
    table.insert(positions,position)
   end
   if valid then
    clusterId+=1
    for _,position in ipairs(positions) do
     table.insert(plan,{kind=kind,position=position,slot=slot,opening=opening,cluster=clusterId})
     local k=key(math.floor(position.X/bucketSize),math.floor(position.Z/bucketSize))
     buckets[k]=buckets[k] or {}
     table.insert(buckets[k],position)
    end
    return true
   end
  end
  return false
 end
 local neutralKinds={"Tree","Tree","Tree","Tree","Gold","Stone","Berries"}
 local function neutralPatch(kind,count,slot)
  if place(kind,count,slot,false) then return true end
  -- Crowded small maps can use two smaller connected groves with the same quota.
  if count<4 then return false end
  local left=math.floor(count/2)
  return neutralPatch(kind,left,slot) and neutralPatch(kind,count-left,slot)
 end
 local function planLayout()
  -- Each base receives identical opening quotas with independent positions.
  for _,patch in ipairs(layout.OpeningClusters) do
   for slot=1,#spawns do
    if not place(patch.kind,patch.count,slot,true) then return false end
   end
  end
  local remaining=math.floor(target/#spawns)-openingCount
  local neutralPlan={}
  while remaining>0 do
   local kind=neutralKinds[random:NextInteger(1,#neutralKinds)]
   local count=math.min(remaining,kind=="Tree" and random:NextInteger(layout.NeutralTreeMin,layout.NeutralTreeMax) or random:NextInteger(layout.NeutralOtherMin,layout.NeutralOtherMax))
   if remaining-count==1 then count-=1 end
   table.insert(neutralPlan,{kind=kind,count=count})
   remaining-=count
  end
  for index,patch in ipairs(neutralPlan) do
   for slot=1,#spawns do
    local extra=index==#neutralPlan and slot<=target%#spawns and 1 or 0
    if not neutralPatch(patch.kind,patch.count+extra,slot) then return false end
   end
  end
  return true
 end
 -- Dense patches can fragment a small quadrant. Retry the complete plan using
 -- the same seeded stream, preserving every quota and reproducibility before
 -- touching the live world; never accept a map with missing resources.
 local planned=false
 for attempt=1,16 do
  buckets,plan,clusterId={},{},0
  if planLayout() then planned=true; break end
 end
 assert(planned,"無法配置完整密集資源地圖")
 assert(#plan==target,"地圖資源數與預算不符")
 -- Plan first; never replace user-owned models or publish a partial success.
 Config.Map.MapSize=size
 Config.Spawns=spawns
 workspace:SetAttribute("MatchSize",size)
 workspace:SetAttribute("MatchSizeName",sizeName)
 workspace:SetAttribute("MapSize",size)
 workspace:SetAttribute("ResourceNodeCount",nil)
 local resources=workspace:FindFirstChild("Resources")
 if resources then
  for _,item in ipairs(resources:GetChildren()) do
   if item:GetAttribute("RTSManagedResource")==true then item:Destroy() end
  end
 end
 for _,node in ipairs(plan) do
  local model=makeResource(node.kind,node.position)
  if not model then error("無法建立地圖資源："..node.kind) end
  model:SetAttribute("RTSManagedResource",true)
  model:SetAttribute("ResourceClusterId",node.cluster)
  model:SetAttribute("ResourceZone",node.opening and "Opening" or "Neutral")
  model:SetAttribute("ResourceSpawnSlot",node.slot)
 end
 workspace:SetAttribute("ResourceNodeCount",#plan)
 workspace:SetAttribute("MapSeed",seed)
 return spawns
end
return WorldGenerator
