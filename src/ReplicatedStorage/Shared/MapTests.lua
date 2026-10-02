-- Explicit, read-only Studio CLIENT checks. Run soon after a fresh match starts.
-- Requiring the module does not generate a world, send remotes or start sampling.
local Tests={}
function Tests.Run()
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient() and RunService:IsRunning(),"僅限新的 Studio CLIENT Play 地圖驗證")
 local Config=require(game.ReplicatedStorage.GameData.GameConfig)
 local layout=Config.Map.ResourceLayout
 local sizeName,size,expected
 local checks=0
 local function check(ok,message)
  checks+=1
  assert(ok,"[MAP_TEST FAIL] "..message)
 end
 check(workspace:GetAttribute("MatchPhase")=="Playing","請先以正常大廳流程開始新局")
 local generation=workspace:GetAttribute("MatchGeneration")
 local deadline=os.clock()+10
 local function waitFor(predicate,message)
  while not predicate() and os.clock()<deadline do task.wait(.1) end
  check(predicate(),message)
  check(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("MatchGeneration")==generation,"驗證期間仍為同一場新局")
 end
 waitFor(function()
  sizeName=workspace:GetAttribute("MatchSizeName")
  size=Config.Map.Sizes[sizeName]
  expected=workspace:GetAttribute("ResourceNodeCount")
  return size~=nil and type(expected)=="number" and expected>0
 end,"伺服器已公布地圖尺寸與資源數")
 check(not workspace.StreamingEnabled,"無角色 RTS 使用完整複製")
 local ground,resources
 waitFor(function()
  ground=workspace:FindFirstChild("AOE2_Ground")
  return ground and ground:IsA("BasePart") and ground.Transparency==0 and ground.Size.X==size and ground.Size.Z==size
 end,"客戶端收到正確尺寸的可見地面")
 waitFor(function() return workspace:GetAttribute("MapReady")==true end,"地圖裝飾初始化完成")
 waitFor(function() resources=workspace:FindFirstChild("Resources"); return resources~=nil end,"客戶端收到資源資料夾")
 local function collect()
  local nodes={}
  for _,model in ipairs(resources:GetChildren()) do
   if model:IsA("Model") and model:GetAttribute("RTSManagedResource")==true then table.insert(nodes,model) end
  end
  return nodes
 end
 local nodes
 waitFor(function()
  nodes=collect()
  if #nodes~=expected then return false end
  for _,model in ipairs(nodes) do
   if not model.PrimaryPart or model.PrimaryPart.Parent~=model or type(model:GetAttribute("ResourceType"))~="string"
    or type(model:GetAttribute("ResourceClusterId"))~="number" or type(model:GetAttribute("ResourceSpawnSlot"))~="number"
    or type(model:GetAttribute("ResourceZone"))~="string" then return false end
   local visible=false
   for _,part in ipairs(model:GetDescendants()) do
    if part:IsA("BasePart") and part~=model.PrimaryPart and part.Transparency<1 then visible=true; break end
   end
   if not visible then return false end
  end
  return true
 end,"整張地圖的資源占地與可見外觀已收到；耗盡後請另開新局")
 check(#nodes==Config.Map.ResourceNodeTargets[sizeName],"資源節點數符合完整預算")
 local mapSeed=workspace:GetAttribute("MapSeed")
 check(type(mapSeed)=="number" and mapSeed%1==0,"伺服器公布可重現的地圖種子")
 local census={sizeName=sizeName,size=size,seed=mapSeed,nodes=#nodes,resourceParts=0,queryParts=0,shadowParts=0,sceneryParts=0,standardTreeCanopyChecks=0,
  resourcePartCountScope="本次採樣收到的部件；沒有伺服器外觀部件總數可核對",completeVisualReplicationProven=false}
 local positions,clusters,resourceNodes={},{},{}
 local slotCounts,openingCounts={0,0,0,0},{0,0,0,0}
 local kindCounts,openingClusters={{},{},{},{}},{{},{},{},{}}
 local kinds={"Tree","Gold","Stone","Berries"}
 local openingSizes={Tree={},Gold={},Stone={},Berries={}}
 local openingCount=0
 for _,patch in ipairs(layout.OpeningClusters) do
  table.insert(openingSizes[patch.kind],patch.count)
  openingCount+=patch.count
 end
 for _,sizes in pairs(openingSizes) do table.sort(sizes) end
 local spawns={}
 local base=size/2-168
 for slot,spawn in ipairs(Config.Spawns) do
  spawns[slot]=Vector3.new(math.sign(spawn.X)*base,0,math.sign(spawn.Z)*base)
  for _,kind in ipairs(kinds) do kindCounts[slot][kind]=0; openingClusters[slot][kind]={} end
 end
 local function distanceSquared(a,b) local dx,dz=a.X-b.X,a.Z-b.Z; return dx*dx+dz*dz end
 local function key(kind,x,z) return kind..":"..string.format("%.3f:%.3f",x,z) end
 for _,model in ipairs(nodes) do
  local root=model.PrimaryPart
  check(root and root.Name=="Footprint" and root.CanQuery and root.CanCollide and not root.CanTouch,"資源有可採集、可阻擋的權威占地")
  check(root.Size.X==Config.Map.ResourceFootprint and root.Size.Z==Config.Map.ResourceFootprint,"資源占地使用共用尺寸")
  local p=root.Position
  check(math.abs(p.X)<=size/2-layout.BorderMargin and math.abs(p.Z)<=size/2-layout.BorderMargin,"資源位於邊界內")
  check(p.X*p.X+p.Z*p.Z>=layout.CenterClearance^2-1e-3,"中央戰場保留空間")
  for _,spawn in ipairs(spawns) do check(distanceSquared(p,spawn)>=layout.BaseClearance^2-1e-3,"基地建築與出口保留空間") end
  local clearance=math.abs(math.abs(p.X)-math.abs(p.Z))/math.sqrt(2)-Config.Map.ResourceFootprint/math.sqrt(2)-Config.Map.RoadWidth/2
  check(clearance>=1-1e-4,"資源占地外緣沒有侵入道路")
  local shadows,query=0,0
  local crownCount,crownSpan,hasTrunk=0,0,false
  for _,part in ipairs(model:GetDescendants()) do
   if part:IsA("BasePart") then
    census.resourceParts+=1
    if part.CanQuery then query+=1 end
    if part.CastShadow then shadows+=1 end
    if part.Name=="Trunk" then hasTrunk=true end
    if part.Name=="Crown" and part:IsA("Part") and part.Shape==Enum.PartType.Ball then
     crownCount+=1
     crownSpan=math.max(crownSpan,math.min(part.Size.X,part.Size.Z))
    end
    if part~=root then check(not part.CanQuery and not part.CanCollide and not part.CanTouch,"資源外觀不增加碰撞與查詢負擔") end
   end
  end
  check(query==1 and shadows<=1 and not root.CastShadow,"每個資源只有一個查詢占地與至多一個投影零件")
  -- Custom Studio templates may have any names or structure. Only recognize
  -- the standard three-crown / trunk geometry when it is actually present.
  if model.Name=="Tree" and hasTrunk and crownCount==3 then
   check(crownSpan>=layout.ClusterSpacing-1e-3,"標準樹冠覆蓋密集森林間距，同時保留較小的權威占地")
   census.standardTreeCanopyChecks+=1
  end
  census.queryParts+=query; census.shadowParts+=shadows
  local kind=model.Name
  check(Config.Resources[kind] and model:GetAttribute("ResourceType")==Config.Resources[kind].resource,"資源種類與採集類別已複製")
  local slot,id,zone=model:GetAttribute("ResourceSpawnSlot"),model:GetAttribute("ResourceClusterId"),model:GetAttribute("ResourceZone")
  check(type(slot)=="number" and slot%1==0 and slot>=1 and slot<=4,"出生區標記有效")
  check(type(id)=="number" and id%1==0 and id>0,"資源群標記有效")
  check(zone=="Opening" or zone=="Neutral","資源區域標記有效")
  check(p.X*spawns[slot].X>0 and p.Z*spawns[slot].Z>0,"資源位於所屬出生區象限")
  slotCounts[slot]+=1
  kindCounts[slot][kind]+=1
  if zone=="Opening" then
   openingCounts[slot]+=1
   check(distanceSquared(p,spawns[slot])<=layout.OpeningRadius^2+1e-3,"開局資源在基地可達範圍內")
  end
  if not clusters[id] then
   clusters[id]={kind=kind,slot=slot,zone=zone,nodes={}}
   if zone=="Opening" then table.insert(openingClusters[slot][kind],clusters[id]) end
  end
  local cluster=clusters[id]
  check(cluster.kind==kind and cluster.slot==slot and cluster.zone==zone,"同一資源群沒有混入其他種類或區域")
  table.insert(cluster.nodes,p)
  table.insert(resourceNodes,{position=p,kind=kind,cluster=id})
  local k=key(kind,p.X,p.Z)
  check(not positions[k],"資源位置沒有重複")
  positions[k]=true
 end
 for slot=1,4 do
  check(slotCounts[slot]>=math.floor(#nodes/4) and slotCounts[slot]<=math.ceil(#nodes/4),"四方資源數量差至多一個")
  check(openingCounts[slot]==openingCount,"每個基地都有設定中的完整開局資源")
  for _,kind in ipairs(kinds) do
   local sizes={}
   for _,cluster in ipairs(openingClusters[slot][kind]) do table.insert(sizes,#cluster.nodes) end
   table.sort(sizes)
   check(#sizes==#openingSizes[kind],"開局資源群數量公平")
   for index,wanted in ipairs(openingSizes[kind]) do check(sizes[index]==wanted,"開局森林、礦脈與漿果群規模公平") end
   for other=slot+1,4 do check(math.abs(kindCounts[slot][kind]-kindCounts[other][kind])<=1,"各出生區同類資源總量公平") end
  end
 end
 local denseForests={0,0,0,0}
 local forestInteriorNodes,minimumForestFill=0,1
 -- Each small patch is measured once in O(k^2), then its adjacency graph is
 -- traversed without rescanning the map or depending on the server's shape code.
 for _,cluster in pairs(clusters) do
  local count=#cluster.nodes
  local maximum=cluster.kind=="Tree" and layout.NeutralTreeMax+1 or layout.NeutralOtherMax+1
  if cluster.zone=="Opening" then maximum=openingSizes[cluster.kind][#openingSizes[cluster.kind]] end
  check(count>=2 and count<=maximum,"資源群大小保持有限")
  local graph,nearest={},{}
  local minX,minZ,maxX,maxZ=math.huge,math.huge,-math.huge,-math.huge
  local neighborRadius=layout.ClusterSpacing+math.sqrt(8)*layout.NodeJitter+1e-3
  for index,p in ipairs(cluster.nodes) do
   graph[index]={}; nearest[index]=math.huge
   minX,minZ,maxX,maxZ=math.min(minX,p.X),math.min(minZ,p.Z),math.max(maxX,p.X),math.max(maxZ,p.Z)
  end
  for index=1,count do for other=index+1,count do
   local distance=distanceSquared(cluster.nodes[index],cluster.nodes[other])
   nearest[index]=math.min(nearest[index],distance); nearest[other]=math.min(nearest[other],distance)
   if distance<=neighborRadius^2 then table.insert(graph[index],other); table.insert(graph[other],index) end
  end end
  local visited,queue={[1]=true},{1}
  local head=1
  while head<=#queue do
   for _,other in ipairs(graph[queue[head]]) do
    if not visited[other] then visited[other]=true; table.insert(queue,other) end
   end
   head+=1
  end
  check(#queue==count,"森林與礦脈成群連接，沒有孤立節點")
  local totalNearest,interior,wellConnected=0,0,0
  for index,neighbors in ipairs(graph) do
   totalNearest+=math.sqrt(nearest[index])
   if #neighbors>=3 then wellConnected+=1 end
   if #neighbors>=4 then interior+=1 end
  end
  check(totalNearest/count<=layout.ClusterSpacing+layout.NodeJitter*2+1e-3,"資源群的平均最近鄰距離保持緊密")
  if cluster.kind=="Tree" and count>=layout.NeutralTreeMin/2 then
   local width,depth=maxX-minX+layout.ClusterSpacing,maxZ-minZ+layout.ClusterSpacing
   local fill=count*layout.ClusterSpacing^2/(width*depth)
   check(fill>=0.55,"森林包圍盒內有足夠樹木，沒有大片空洞")
   check(math.max(width,depth)/math.min(width,depth)<=2,"森林沒有形成狹長稀疏分枝")
   check(math.max(width,depth)<=math.sqrt(count)*layout.ClusterSpacing*1.8,"森林範圍與樹木數量相符")
   check(wellConnected>=math.ceil(count/5) and interior>=1,"森林具有多鄰居的密集內部節點")
   denseForests[cluster.slot]+=1
   forestInteriorNodes+=interior
   minimumForestFill=math.min(minimumForestFill,fill)
  end
 end
 for slot=1,4 do check(denseForests[slot]>=#openingSizes.Tree,"每個基地收到設定中的密集開局森林") end
 -- Cache coordinates and IDs before the full O(n^2) pair check, avoiding millions
 -- of repeated engine property / attribute calls on the 2,200-node map.
 for index,node in ipairs(resourceNodes) do
  for other=index+1,#resourceNodes do
   local a,b=node.position,resourceNodes[other].position
   local distance=distanceSquared(a,b)
   check(distance>=layout.MinNodeSpacing^2-1e-3,"資源占地之間保持間距")
   check(math.max(math.abs(a.X-b.X),math.abs(a.Z-b.Z))>=Config.Map.ResourceFootprint+Config.UnitCollision.profiles.villager.radius*2-1e-3,"膨脹後的資源占地沒有封住村民通道")
   if node.cluster~=resourceNodes[other].cluster then
    local separation=layout.ClusterSeparation
    check(distance>=separation*separation-1e-3,"不同資源群之間保留通行間距")
   end
  end
  if index%64==0 then task.wait() end
 end
 local mirrored=0
 for _,node in ipairs(resourceNodes) do
  local p,kind=node.position,node.kind
  for _,sign in ipairs({{-1,-1},{1,1},{1,-1},{-1,1}}) do
   local x,z=math.abs(p.X)*sign[1],math.abs(p.Z)*sign[2]
   if (x~=p.X or z~=p.Z) and positions[key(kind,x,z)] then mirrored+=1 end
  end
 end
 check(mirrored==0,"四個出生區的資源位置獨立隨機，沒有完全鏡射")
 census.clusters=0
 for _ in pairs(clusters) do census.clusters+=1 end
 census.slotCounts=slotCounts
 census.denseForests=denseForests
 census.forestInteriorNodes=forestInteriorNodes
 census.minimumForestFill=minimumForestFill
 local scenery
 waitFor(function()
  local managed=0
  for _,folder in ipairs(workspace:GetChildren()) do
   if folder:IsA("Folder") and folder:GetAttribute("RTSManagedScenery")==true then managed+=1; scenery=folder end
  end
  return managed==1 and #scenery:GetChildren()==workspace:GetAttribute("SceneryPartCount")
 end,"自有裝飾的全部零件已複製")
 local managedScenery,roads=0,0
 for _,folder in ipairs(workspace:GetChildren()) do
  if folder:IsA("Folder") and folder:GetAttribute("RTSManagedScenery")==true then
   managedScenery+=1
   for _,part in ipairs(folder:GetChildren()) do
    check(part:IsA("BasePart") and not part.CanCollide and not part.CanQuery and not part.CanTouch and not part.CastShadow,"地圖裝飾不參與碰撞、查詢或陰影")
    check(part.Transparency==0,"地圖裝飾不疊加透明表面")
    if part.Name=="TradePath" then
     roads+=1
     check(part.Size.X==Config.Map.RoadWidth and part.Size.Z>0,"實際道路使用共用寬度")
     local direction=part.CFrame.LookVector
     check(math.abs(direction.Y)<1e-4 and math.abs(math.abs(direction.X)-math.abs(direction.Z))<1e-4,"實際道路沿對角線朝向中央")
     check(math.abs(math.abs(part.Position.X)-math.abs(part.Position.Z))<1e-4 and direction:Dot(-part.Position.Unit)>0.99,"實際道路位於基地與中央之間")
    end
    census.sceneryParts+=1
   end
  end
 end
 check(managedScenery==1 and census.sceneryParts==workspace:GetAttribute("SceneryPartCount"),"只有一份完整複製的自有裝飾")
 check(roads==4,"四條基地大道已完整複製")
 check(census.sceneryParts<=64,"三種地圖的靜態裝飾保持有限零件數")
 local camera=workspace.CurrentCamera
 check(camera and camera.CameraType==Enum.CameraType.Scriptable and camera.CFrame.LookVector.Y<0,"實際客戶端相機俯視場景")
 census.checks=checks
 print("[MAP_TEST COMPLETE]",game:GetService("HttpService"):JSONEncode(census))
 return census
end
return Tests
