-- Pure wall-line and gate geometry shared by the placement preview and the authority. No engine globals.
local Rules = {}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function integer(value)
 return finite(value) and value%1==0
end

-- Footprint in cells; a quarter turn swaps the two axes.
function Rules.footprint(sizeX, sizeY, rotated)
 if rotated==true then return sizeY,sizeX end
 return sizeX,sizeY
end

-- Cells from (x0,z0) to (x1,z1). Every step shares an edge with the previous cell, so a
-- dragged diagonal becomes a staircase that units cannot slip through. Returns the cells
-- and whether the line was cut short by maximum.
function Rules.line(x0, z0, x1, z1, maximum)
 if not integer(x0) or not integer(z0) or not integer(x1) or not integer(z1)
  or not integer(maximum) or maximum<1 then return nil end
 local dx,dz=math.abs(x1-x0),math.abs(z1-z0)
 local stepX,stepZ=x1>=x0 and 1 or -1,z1>=z0 and 1 or -1
 local cells={{x=x0,z=z0}}
 local x,z,ix,iz=x0,z0,0,0
 while (ix<dx or iz<dz) and #cells<maximum do
  -- Advance along whichever axis is behind the ideal straight line.
  if iz>=dz or (ix<dx and (1+2*ix)*dz<(1+2*iz)*dx) then x+=stepX; ix+=1 else z+=stepZ; iz+=1 end
  table.insert(cells,{x=x,z=z})
 end
 return cells,ix<dx or iz<dz
end

-- How many segments a balance pays for; cost keys missing from the balance count as zero.
function Rules.affordableCount(balance, cost, wanted)
 if type(balance)~="table" or type(cost)~="table" or not integer(wanted) or wanted<0 then return 0 end
 local count=wanted
 for key,amount in pairs(cost) do
  if not finite(amount) or amount<0 then return 0 end
  if amount>0 then
   local owned=balance[key]
   if not finite(owned) or owned<0 then return 0 end
   count=math.min(count,math.floor(owned/amount))
  end
 end
 return count
end

-- Squared distance from a point to an axis-aligned rectangle (0 inside).
function Rules.boxDistanceSquared(x, z, centerX, centerZ, halfX, halfZ)
 local dx=math.max(math.abs(x-centerX)-halfX,0)
 local dz=math.max(math.abs(z-centerZ)-halfZ,0)
 return dx*dx+dz*dz
end

local function insideBox(x, z, centerX, centerZ, halfX, halfZ)
 return math.abs(x-centerX)<halfX and math.abs(z-centerZ)<halfZ
end

-- Slab test: does the open rectangle contain any point of the segment?
function Rules.segmentHitsBox(fromX, fromZ, toX, toZ, centerX, centerZ, halfX, halfZ)
 if not finite(fromX) or not finite(fromZ) or not finite(toX) or not finite(toZ)
  or not finite(centerX) or not finite(centerZ) or not finite(halfX) or not finite(halfZ)
  or halfX<=0 or halfZ<=0 then return false end
 local enter,exit=0,1
 for _,axis in ipairs({{fromX,toX-fromX,centerX,halfX},{fromZ,toZ-fromZ,centerZ,halfZ}}) do
  local origin,delta,low,high=axis[1],axis[2],axis[3]-axis[4],axis[3]+axis[4]
  if delta==0 then
   if origin<=low or origin>=high then return false end
  else
   local a,b=(low-origin)/delta,(high-origin)/delta
   if a>b then a,b=b,a end
   enter,exit=math.max(enter,a),math.min(exit,b)
   if enter>=exit then return false end
  end
 end
 return true
end

-- A hostile unit's square movement body may not enter a gate. A body that already overlaps
-- (the gate was finished around it, or the unit changed sides inside) may still walk out,
-- but a zero-length probe inside is never a valid standing position.
function Rules.gateBlocks(fromX, fromZ, toX, toZ, radius, centerX, centerZ, halfX, halfZ)
 if not finite(radius) or radius<=0 or not finite(halfX) or not finite(halfZ) then return false end
 local reachX,reachZ=halfX+radius-0.1,halfZ+radius-0.1
 if not Rules.segmentHitsBox(fromX,fromZ,toX,toZ,centerX,centerZ,reachX,reachZ) then
  return fromX==toX and fromZ==toZ and insideBox(fromX,fromZ,centerX,centerZ,reachX,reachZ)
 end
 if fromX==toX and fromZ==toZ then return true end
 return not insideBox(fromX,fromZ,centerX,centerZ,reachX,reachZ)
end

return Rules
