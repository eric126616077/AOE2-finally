-- Center-indexed spatial queries must include every target whose footprint edge is in range.
local Rules={}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Rules.maxHalfFootprint(buildings,gridSize)
 if type(buildings)~="table" or not finite(gridSize) or gridSize<=0 then return nil end
 local margin=0
 for _,data in pairs(buildings) do
  local size=data and data.size
  local x,z=size and size.X,size and size.Y
  if not finite(x) or not finite(z) or x<=0 or z<=0 then return nil end
  local half=math.max(x,z)*gridSize/2
  if not finite(half) then return nil end
  margin=math.max(margin,half)
 end
 return margin
end
function Rules.searchCells(radius,targetHalfExtent,cellSize)
 if not finite(radius) or radius<0 or not finite(targetHalfExtent) or targetHalfExtent<0 or not finite(cellSize) or cellSize<=0 then return nil end
 local reach=radius+targetHalfExtent
 local cells=math.ceil(reach/cellSize)
 if not finite(reach) or not finite(cells) then return nil end
 return cells
end
return Rules
