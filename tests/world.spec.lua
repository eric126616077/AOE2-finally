local worldChecks=0
local function expect(condition,message)
 worldChecks+=1
 assert(condition,message)
end
local function distanceSquared(a,b)
 local dx,dz=a.X-b.X,a.Z-b.Z
 return dx*dx+dz*dz
end
local function nodeKey(kind,pos)
 return kind..":"..string.format("%.6f:%.6f",pos.X,pos.Z)
end
local published={}
local originalSetAttribute=workspace.SetAttribute
workspace.SetAttribute=function(self,key,value)
 published[key]=value
 return originalSetAttribute(self,key,value)
end
local function generate(name,seed)
 local nodes={}
 local spawns=WorldGenerator.Generate(name,function(kind,pos)
  local attributes={}
  table.insert(nodes,{kind=kind,pos=pos,attributes=attributes})
  return {SetAttribute=function(_,key,value) attributes[key]=value end}
 end,seed)
 return nodes,spawns
end
local function fingerprint(nodes,openingSlot)
 local result={}
 for _,node in ipairs(nodes) do
  if openingSlot==nil or (node.attributes.ResourceZone=="Opening" and node.attributes.ResourceSpawnSlot==openingSlot) then
   table.insert(result,nodeKey(node.kind,node.pos))
  end
 end
 table.sort(result)
 return table.concat(result,"|")
end
local layout=Config.Map.ResourceLayout
-- Compute a graph and density measurements from final coordinates, independent
-- of the generator's frontier scores, placement retries and spatial buckets.
local function patchGeometry(cluster)
 local count=#cluster.nodes
 local graph,nearest={},{}
 local minX,minZ,maxX,maxZ=math.huge,math.huge,-math.huge,-math.huge
 local neighborRadius=layout.ClusterSpacing+math.sqrt(8)*layout.NodeJitter+1e-3
 for index,node in ipairs(cluster.nodes) do
  graph[index]={}; nearest[index]=math.huge
  local p=node.pos
  minX,minZ,maxX,maxZ=math.min(minX,p.X),math.min(minZ,p.Z),math.max(maxX,p.X),math.max(maxZ,p.Z)
 end
 for i=1,count do for j=i+1,count do
  local d=distanceSquared(cluster.nodes[i].pos,cluster.nodes[j].pos)
  nearest[i]=math.min(nearest[i],d); nearest[j]=math.min(nearest[j],d)
  if d<=neighborRadius^2 then table.insert(graph[i],j); table.insert(graph[j],i) end
 end end
 local visited,queue={[1]=true},{1}
 local head=1
 while head<=#queue do
  for _,other in ipairs(graph[queue[head]]) do
   if not visited[other] then visited[other]=true; table.insert(queue,other) end
  end
  head+=1
 end
 local totalNearest,interior,wellConnected=0,0,0
 for index,neighbors in ipairs(graph) do
  totalNearest+=math.sqrt(nearest[index])
  if #neighbors>=3 then wellConnected+=1 end
  if #neighbors>=4 then interior+=1 end
 end
 local width,depth=maxX-minX+layout.ClusterSpacing,maxZ-minZ+layout.ClusterSpacing
 return {connected=#queue==count,averageNearest=totalNearest/count,width=width,depth=depth,
  fill=count*layout.ClusterSpacing^2/(width*depth),interior=interior,wellConnected=wellConnected}
end
local kinds={"Tree","Gold","Stone","Berries","Deer"}
local openingSizes={Tree={},Gold={},Stone={},Berries={},Deer={}}
local openingCount=0
for _,patch in ipairs(layout.OpeningClusters) do
 table.insert(openingSizes[patch.kind],patch.count)
 openingCount+=patch.count
end
for _,sizes in pairs(openingSizes) do table.sort(sizes) end
local RelicTradeRules=require("../src/ServerScriptService/ServerModules/RelicTradeRules")
local function inspect(name,seed,nodes,spawns,target)
 local size=Config.Map.Sizes[name]
 -- 與伺服器放聖物用的同一個規則：生成器保留的點必須就是聖物會放的點。
 local relicSpots=assert(RelicTradeRules.relicPoints(size,Config.Relics.counts[name],Config.Relics.axisRadii[name]),"relic layout unavailable")
 expect(Config.Map.MapSize==size,"map config size mismatch")
 expect(#spawns==4,"match needs four reserved spawns")
 expect(#nodes==target,"resource target not reached: "..name.." seed "..seed)
 expect(published.ResourceNodeCount==#nodes,"published count must equal successful resource creations")
 expect(published.MapSeed==seed,"published seed mismatch")
 local slotCounts={0,0,0,0}
 local kindCounts={}
 local openingCounts={0,0,0,0}
 local openingClusters={{},{},{},{}}
 local positions,clusters={},{}
 for slot=1,4 do
  kindCounts[slot]={Tree=0,Gold=0,Stone=0,Berries=0,Deer=0}
  for _,kind in ipairs(kinds) do openingClusters[slot][kind]={} end
 end
 for _,node in ipairs(nodes) do
  expect(Config.Resources[node.kind]~=nil,"unknown resource kind")
  local attributes=node.attributes
  expect(attributes.RTSManagedResource==true,"generated resource must be marked for managed cleanup")
  local slot,id,zone=attributes.ResourceSpawnSlot,attributes.ResourceClusterId,attributes.ResourceZone
  expect(type(slot)=="number" and slot%1==0 and slot>=1 and slot<=4,"resource slot metadata invalid")
  expect(type(id)=="number" and id%1==0 and id>0,"resource cluster metadata invalid")
  expect(zone=="Opening" or zone=="Neutral","resource zone metadata invalid")
  local pos=node.pos
  expect(pos.X*spawns[slot].X>0 and pos.Z*spawns[slot].Z>0,"resource must remain strictly in its reserved slot quadrant")
  expect(math.abs(pos.X)<=size/2-layout.BorderMargin and math.abs(pos.Z)<=size/2-layout.BorderMargin,"resource outside map")
  expect(pos.X*pos.X+pos.Z*pos.Z>=layout.CenterClearance^2,"resource blocks central reservation")
  for _,spot in ipairs(relicSpots) do
   expect((pos.X-spot.X)^2+(pos.Z-spot.Z)^2>=Config.Relics.reserve^2-1e-6,"resource blocks a relic reservation")
  end
  local roadDistance=math.abs(math.abs(pos.X)-math.abs(pos.Z))/math.sqrt(2)
  local resourceReach=Config.Map.ResourceFootprint/math.sqrt(2)
  expect(roadDistance-resourceReach>=Config.Map.RoadWidth/2+1-1e-6,"resource footprint blocks diagonal road margin")
  slotCounts[slot]+=1
  kindCounts[slot][node.kind]+=1
  local key=nodeKey(node.kind,pos)
  expect(not positions[key],"duplicate resource position")
  positions[key]=true
  for _,spawn in ipairs(spawns) do expect(distanceSquared(pos,spawn)>=layout.BaseClearance^2-1e-6,"resource blocks base reservation") end
  if zone=="Opening" then
   openingCounts[slot]+=1
   expect(distanceSquared(pos,spawns[slot])<=layout.OpeningRadius^2+1e-6,"opening resource outside base reach")
  end
  if not clusters[id] then
   clusters[id]={kind=node.kind,slot=slot,zone=zone,nodes={}}
   if zone=="Opening" then table.insert(openingClusters[slot][node.kind],clusters[id]) end
  end
  local cluster=clusters[id]
  expect(cluster.kind==node.kind and cluster.slot==slot and cluster.zone==zone,"one cluster cannot mix kinds, slots or zones")
  table.insert(cluster.nodes,node)
 end
 for slot=1,4 do
  expect(slotCounts[slot]>=math.floor(target/4) and slotCounts[slot]<=math.ceil(target/4),"quadrant resource count must differ by at most one")
  expect(openingCounts[slot]==openingCount,"each slot must receive the complete configured opening economy")
  for _,kind in ipairs(kinds) do
   local sizes={}
   for _,cluster in ipairs(openingClusters[slot][kind]) do table.insert(sizes,#cluster.nodes) end
   table.sort(sizes)
   expect(#sizes==#openingSizes[kind],"opening patch count mismatch: "..kind)
   for index,wanted in ipairs(openingSizes[kind]) do expect(sizes[index]==wanted,"opening patch size mismatch: "..kind) end
   for other=slot+1,4 do expect(math.abs(kindCounts[slot][kind]-kindCounts[other][kind])<=1,"resource kind quotas differ between slots: "..kind) end
  end
 end
 local denseForests={0,0,0,0}
 for _,cluster in pairs(clusters) do
  local maximum=cluster.kind=="Tree" and layout.NeutralTreeMax+1 or layout.NeutralOtherMax+1
  if cluster.zone=="Opening" then maximum=openingSizes[cluster.kind][#openingSizes[cluster.kind]] end
  expect(#cluster.nodes>=2 and #cluster.nodes<=maximum,"resource patch size is outside its bounds")
  local geometry=patchGeometry(cluster)
  expect(geometry.connected,"resource patch has isolated nodes or disconnected fragments")
  expect(geometry.averageNearest<=layout.ClusterSpacing+layout.NodeJitter*2+1e-3,"resource patch nearest neighbors are too sparse")
  if cluster.kind=="Tree" and #cluster.nodes>=layout.NeutralTreeMin/2 then
   expect(geometry.fill>=0.55,"forest leaves too much empty space inside its bounding box")
   expect(math.max(geometry.width,geometry.depth)/math.min(geometry.width,geometry.depth)<=2,"forest forms an elongated sparse branch")
   expect(math.max(geometry.width,geometry.depth)<=math.sqrt(#cluster.nodes)*layout.ClusterSpacing*1.8,"forest spreads too far for its tree count")
   expect(geometry.wellConnected>=math.ceil(#cluster.nodes/5) and geometry.interior>=1,"forest lacks densely connected interior trees")
   denseForests[cluster.slot]+=1
  end
 end
 for slot=1,4 do expect(denseForests[slot]>=#openingSizes.Tree,"every slot must contain its configured dense opening forests") end
 -- Check every pair independently of the generator's spatial buckets.
 for i=1,#nodes do for j=i+1,#nodes do
  local a,b=nodes[i].pos,nodes[j].pos
  local distance=distanceSquared(a,b)
  expect(distance>=layout.MinNodeSpacing^2-1e-6,"resources are too close")
  -- Villager pathfinding inflates the axis-aligned resource footprints by its
  -- blocked body width. Euclidean distance alone can leave their corners sealed.
  local inflatedWidth=Config.Map.ResourceFootprint+Config.UnitCollision.profiles.villager.radius*2
  expect(math.max(math.abs(a.X-b.X),math.abs(a.Z-b.Z))>=inflatedWidth-1e-6,"inflated resource footprints overlap and seal villager passage")
  if nodes[i].attributes.ResourceClusterId~=nodes[j].attributes.ResourceClusterId then
   local separation=Config.Map.ResourceLayout.ClusterSeparation
   expect(distance>=separation*separation-1e-6,"different resource patches do not leave enough passage space")
  end
 end end
 local mirrored=0
 for _,node in ipairs(nodes) do
  for _,sign in ipairs({{-1,-1},{1,1},{1,-1},{-1,1}}) do
   local mirror=Vector3.new(math.abs(node.pos.X)*sign[1],0,math.abs(node.pos.Z)*sign[2])
   if (mirror.X~=node.pos.X or mirror.Z~=node.pos.Z) and positions[nodeKey(node.kind,mirror)] then mirrored+=1 end
  end
 end
 expect(mirrored==0,"independently placed slots still contain exact mirrored resource coordinates")
 return kindCounts
end
local originalSeed,originalRandomizeSeed=Config.Map.Seed,Config.Map.RandomizeSeed
local seeds={1,2,17,91,2718,9001,1234567,2147483646,42,512,777,991,10007,65537,987654,314159}
-- This uses the actual generator with a deterministic CLI RNG shim; it does not
-- claim Roblox Random parity, visual replication or engine navigation success.
for _,name in ipairs({"Small","Medium","Large"}) do
 local target=Config.Map.ResourceNodeTargets[name]
 local firstFingerprint,firstOpening
 for seedIndex,seed in ipairs(seeds) do
  local nodes,spawns=generate(name,seed)
  local counts=inspect(name,seed,nodes,spawns,target)
  local currentFingerprint=fingerprint(nodes)
  local second=generate(name,seed)
  expect(currentFingerprint==fingerprint(second),"explicit seed layout is not reproducible")
  if seedIndex==1 then
   firstFingerprint=currentFingerprint
   firstOpening={}
   for slot=1,4 do firstOpening[slot]=fingerprint(nodes,slot) end
   local total={Tree=0,Gold=0,Stone=0,Berries=0,Deer=0}
   for _,byKind in ipairs(counts) do for _,kind in ipairs(kinds) do total[kind]+=byKind[kind] end end
   local fallbackParts=total.Tree*5+total.Gold*9+total.Stone*5+total.Berries*9+total.Deer*20
   print(string.format("WORLD %s seed=%d nodes=%d/%d Tree=%d Gold=%d Stone=%d Berries=%d Deer=%d fallbackParts=%d",name,seed,#nodes,target,total.Tree,total.Gold,total.Stone,total.Berries,total.Deer,fallbackParts))
  else
   expect(currentFingerprint~=firstFingerprint,"different seeds must vary resource layout")
   for slot=1,4 do expect(fingerprint(nodes,slot)~=firstOpening[slot],"different seeds must also vary every opening economy") end
  end
 end
end
-- Exact budgets include a remainder instead of silently dropping resources.
local originalTarget=Config.Map.ResourceNodeTargets.Small
for remainder=1,3 do
 Config.Map.ResourceNodeTargets.Small=originalTarget+remainder
 local nodes,spawns=generate("Small",9001)
 inspect("Small",9001,nodes,spawns,originalTarget+remainder)
end
Config.Map.ResourceNodeTargets.Small=originalTarget
-- The nil-seed shim is controllable so two fresh matches are deterministic tests.
Config.Map.RandomizeSeed=true
testRandomAutomaticSeeds={101,202}
testRandomUnseededCalls=0
local automaticFirst=generate("Small")
local firstSeed=published.MapSeed
local automaticSecond=generate("Small")
local secondSeed=published.MapSeed
expect(testRandomUnseededCalls==2,"fresh matches must request a new server random seed")
expect(type(firstSeed)=="number" and firstSeed%1==0 and type(secondSeed)=="number" and secondSeed%1==0,"random server seed must be an integer")
expect(firstSeed~=secondSeed and fingerprint(automaticFirst)~=fingerprint(automaticSecond),"fresh matches must change seeds and resource positions")
local replay=generate("Small",firstSeed)
expect(fingerprint(replay)==fingerprint(automaticFirst),"published automatic seed must reproduce the map")
Config.Map.RandomizeSeed=false
Config.Map.Seed=2718
local fixed=generate("Small")
expect(published.MapSeed==2718,"disabled randomization must use configured seed")
local explicit=generate("Small",2718)
expect(fingerprint(fixed)==fingerprint(explicit),"configured seed fallback differs from explicit seed")
Config.Map.Seed,Config.Map.RandomizeSeed=originalSeed,originalRandomizeSeed
-- Failing after successful siblings aborts instead of publishing phantom nodes.
local created,calls={},0
local ok,message=pcall(function()
 WorldGenerator.Generate("Small",function()
  calls+=1
  if calls==3 then return nil end
  local attributes={}
  table.insert(created,attributes)
  return {SetAttribute=function(_,key,value) attributes[key]=value end}
 end,9001)
end)
expect(not ok and type(message)=="string" and string.find(message,"無法建立地圖資源",1,true)~=nil,"nil resource creation must fail generation")
expect(calls==3 and #created==2,"generation must stop at the first failed resource")
expect(created[1].RTSManagedResource and created[2].RTSManagedResource,"successful resources before failure must remain managed")
expect(published.ResourceNodeCount==nil,"failed generation must not publish a successful node count")
expect(testOwnedResource.removed==true,"owned generated resources not cleaned")
expect(testUnknownResource.removed~=true,"unknown Studio resource destroyed")
workspace.SetAttribute=originalSetAttribute
print(string.format("PASS: %d randomized-world / opening-fairness / patch / budget / preservation checks",worldChecks))
