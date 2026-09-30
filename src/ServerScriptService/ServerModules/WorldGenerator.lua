-- Seeded, mirrored resource layout. Never deletes unmarked Studio models.
local Config = require(game.ReplicatedStorage.GameData.GameConfig)
local WorldGenerator = {}
local function distanceSquared(a,b)
 local x,z=a.X-b.X,a.Z-b.Z
 return x*x+z*z
end
function WorldGenerator.Generate(sizeName, makeResource)
 sizeName = Config.Map.Sizes[sizeName] and sizeName or "Medium"
 local size=Config.Map.Sizes[sizeName]
 local half=size/2
 local base=half-168
 local spawns={Vector3.new(-base,0,-base),Vector3.new(base,0,base),Vector3.new(base,0,-base),Vector3.new(-base,0,base)}
 Config.Map.MapSize=size
 Config.Spawns=spawns
 workspace:SetAttribute("MatchSize",size)
 workspace:SetAttribute("MatchSizeName",sizeName)
 workspace:SetAttribute("MapSize",size)
 local resources=workspace:FindFirstChild("Resources")
 if resources then
  for _,item in ipairs(resources:GetChildren()) do
   if item:GetAttribute("RTSManagedResource")==true then item:Destroy() end
  end
 end
 local buckets={}
 local count=0
 local function key(x,z) return tostring(x)..":"..tostring(z) end
 local function clear(position)
  if math.abs(position.X)>half-20 or math.abs(position.Z)>half-20 then return false end
  -- Leave castle + town center and their exits clear in every ruleset.
  for _,spawn in ipairs(spawns) do
   if distanceSquared(position,spawn)<128*128 then return false end
  end
  if position.X*position.X+position.Z*position.Z<64*64 then return false end
  -- A diagonal avenue joins each base to the central battlefield.
  if math.abs(math.abs(position.X)-math.abs(position.Z))<18 then return false end
  local bx,bz=math.floor(position.X/16),math.floor(position.Z/16)
  for dx=-1,1 do for dz=-1,1 do
   local nearby=buckets[key(bx+dx,bz+dz)]
   if nearby then for _,other in ipairs(nearby) do
    if distanceSquared(position,other)<13*13 then return false end
   end end
  end end
  return true
 end
 local function add(kind,position)
  local model=makeResource(kind,position)
  if model then model:SetAttribute("RTSManagedResource",true) end
  local k=key(math.floor(position.X/16),math.floor(position.Z/16))
  buckets[k]=buckets[k] or {}
  table.insert(buckets[k],position)
  count+=1
  return true
 end
 local mirrors={{-1,-1},{1,1},{1,-1},{-1,1}}
 local function orbit(kind,x,z)
  local positions={}
  for _,sign in ipairs(mirrors) do
   local position=Vector3.new(sign[1]*x,0,sign[2]*z)
   if not clear(position) then return false end
   for _,candidate in ipairs(positions) do
    if distanceSquared(candidate,position)<13*13 then return false end
   end
   table.insert(positions,position)
  end
  for _,position in ipairs(positions) do add(kind,position) end
  return true
 end
 local function cluster(kind,cx,cz,rows,columns)
  for row=1,rows do for column=1,columns do
   orbit(kind,cx+(column-(columns+1)/2)*16,cz+(row-(rows+1)/2)*16)
  end end
 end
 -- Identical accessible opening economies, with room to place drop-off camps.
 cluster("Tree",base-164,base+32,4,7)
 cluster("Tree",base+32,base-164,4,6)
 cluster("Berries",base-142,base-40,2,3)
 cluster("Gold",base-48,base-152,2,3)
 cluster("Stone",base-178,base-48,2,2)
 local random=Random.new(Config.Map.Seed+size)
 local target=({Small=420,Medium=680,Large=1100})[sizeName]
 local neutralKinds={"Tree","Tree","Tree","Tree","Gold","Stone","Berries"}
 -- Small groves and ore seams create strategic areas, rather than uniform noise.
 for attempt=1,350 do
  if count>=target then break end
  local cx=random:NextInteger(4,math.floor((half-40)/16))*16
  local cz=random:NextInteger(4,math.floor((half-40)/16))*16
  local kind=neutralKinds[random:NextInteger(1,#neutralKinds)]
  local rows=kind=="Tree" and random:NextInteger(2,4) or 2
  local columns=kind=="Tree" and random:NextInteger(3,5) or random:NextInteger(2,3)
  cluster(kind,cx,cz,rows,columns)
 end
 workspace:SetAttribute("ResourceNodeCount",count)
 workspace:SetAttribute("MapSeed",Config.Map.Seed)
 return spawns
end
return WorldGenerator
