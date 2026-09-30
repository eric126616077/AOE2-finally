local worldChecks=0
local function expect(condition,message)
 worldChecks+=1
 assert(condition,message)
end
-- The layout algorithm is tested with seeded RNG and fake resource instances, not fake gameplay.
for name,size in pairs(Config.Map.Sizes) do
 local nodes={}
 local spawns=WorldGenerator.Generate(name,function(kind,pos)
  table.insert(nodes,{kind=kind,pos=pos})
  return {SetAttribute=function() end}
 end)
 expect(Config.Map.MapSize==size,"map config size mismatch")
 expect(#spawns==4,"match needs four reserved spawns")
 expect(#nodes>=250,"resource density insufficient: "..name)
 local quadrants={0,0,0,0}
 for _,node in ipairs(nodes) do
  expect(Config.Resources[node.kind]~=nil,"unknown resource kind")
  local pos=node.pos
  expect(math.abs(pos.X)<=size/2-20 and math.abs(pos.Z)<=size/2-20,"resource outside map")
  local quadrant=(pos.X>0 and 1 or 0)+(pos.Z>0 and 2 or 0)+1
  quadrants[quadrant]+=1
  for _,spawn in ipairs(spawns) do
   local dx,dz=pos.X-spawn.X,pos.Z-spawn.Z
   expect(dx*dx+dz*dz>=128*128,"resource blocks base reservation")
  end
 end
 for i=2,4 do expect(quadrants[i]==quadrants[1],"asymmetric resource count") end
 for _,spawn in ipairs(spawns) do
  local near={}
  for _,node in ipairs(nodes) do
   local dx,dz=node.pos.X-spawn.X,node.pos.Z-spawn.Z
   if dx*dx+dz*dz<230*230 then near[Config.Resources[node.kind].resource]=true end
  end
  expect(near.food and near.wood and near.gold and near.stone,"base missing accessible opening resources")
 end
 local fingerprint={}
 for _,node in ipairs(nodes) do table.insert(fingerprint,node.kind..":"..node.pos.X..":"..node.pos.Z) end
 local second={}
 WorldGenerator.Generate(name,function(kind,pos)
  table.insert(second,kind..":"..pos.X..":"..pos.Z)
  return {SetAttribute=function() end}
 end)
 expect(table.concat(fingerprint,"|")==table.concat(second,"|"),"seeded layout is not reproducible")
end
expect(testOwnedResource.removed==true,"owned generated resources not cleaned")
expect(testUnknownResource.removed~=true,"unknown Studio resource destroyed")
print(string.format("PASS: %d seeded-world / fairness / preservation checks",worldChecks))
