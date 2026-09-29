-- Pure grid rules shared by preview and authority. Coordinates are cell lower corners.
local Config = require(script.Parent.Parent.GameData.GameConfig)
local Grid = {}
function Grid.isFinite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Grid.snap(position, size)
 local g, half = Config.Map.GridSize, Config.Map.MapSize/2
 local x = math.floor((position.X+half)/g-size.X/2+0.5)
 local z = math.floor((position.Z+half)/g-size.Y/2+0.5)
 return Vector3.new(-half+(x+size.X/2)*g, Config.Map.GroundY, -half+(z+size.Y/2)*g), x, z
end
function Grid.inBounds(position, size)
 local half, g = Config.Map.MapSize/2, Config.Map.GridSize
 return math.abs(position.X)+size.X*g/2<=half and math.abs(position.Z)+size.Y*g/2<=half
end
function Grid.costText(cost)
 local names, result = {food="食物",wood="木材",gold="黃金",stone="石材"}, {}
 for _, key in ipairs({"food","wood","gold","stone"}) do
  if cost[key] then table.insert(result, names[key].." "..cost[key]) end
 end
 return table.concat(result," · ")
end
return Grid
