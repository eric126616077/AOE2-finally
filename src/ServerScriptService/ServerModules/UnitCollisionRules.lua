-- 伺服器 XZ 圓柱碰撞：純幾何及局部空間索引，不依賴 Roblox 引擎。
local Rules = { MIN_GAP = 0.05, MAX_RETREAT_ATTEMPTS = 2 }
local EPSILON = 1e-9
local MAX_CELL = 1073741824
local MAX_QUERY_WORK = 65536

local function finite(value)
 return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function positive(value)
 return finite(value) and value > 0
end

local function validKey(key)
 return key ~= nil and (type(key) ~= "number" or finite(key))
end

local function cellAt(value, size)
 if not finite(value) then return nil end
 local cell = math.floor(value / size)
 if not finite(cell) or math.abs(cell) > MAX_CELL then return nil end
 return cell
end

local function recordValid(record)
 return type(record) == "table" and finite(record.X) and finite(record.Z) and positive(record.radius)
end

local function squared(x, z)
 local value = x * x + z * z
 if not finite(value) then return nil end
 return value
end

local Index = {}
Index.__index = Index

function Rules.newIndex(cellSize, maxRadius)
 if not positive(cellSize) or not positive(maxRadius) then return nil end
 local reach = math.ceil((maxRadius * 2 + Rules.MIN_GAP) / cellSize)
 if not finite(reach) or (reach * 2 + 1) ^ 2 > MAX_QUERY_WORK then return nil end
 return setmetatable({
  cellSize = cellSize, maxRadius = maxRadius, _cells = {}, _records = {},
  lastQueryCellCount = 0, lastQueryRecordCount = 0,
 }, Index)
end

local function unlink(index, record)
 local column = index._cells[record.cellX]
 local bucket = column and column[record.cellZ]
 if bucket then
  bucket[record.key] = nil
  if next(bucket) == nil then
   column[record.cellZ] = nil
   if next(column) == nil then index._cells[record.cellX] = nil end
  end
 end
end

function Index:Update(key, x, z, radius)
 if not validKey(key) or not positive(radius) or radius > self.maxRadius then return false end
 local cellX, cellZ = cellAt(x, self.cellSize), cellAt(z, self.cellSize)
 if not cellX or not cellZ then return false end
 local old = self._records[key]
 if old and old.cellX == cellX and old.cellZ == cellZ then
  old.X, old.Z, old.radius = x, z, radius
  return true
 end
 if old then unlink(self, old) end
 local record = { key = key, X = x, Z = z, radius = radius, cellX = cellX, cellZ = cellZ }
 local column = self._cells[cellX]
 if not column then column = {}; self._cells[cellX] = column end
 local bucket = column[cellZ]
 if not bucket then bucket = {}; column[cellZ] = bucket end
 bucket[key], self._records[key] = record, record
 return true
end

function Index:Remove(key)
 if not validKey(key) then return false end
 local record = self._records[key]
 if not record then return false end
 unlink(self, record)
 self._records[key] = nil
 return true
end

-- 沿線段走訪格子，再讀取半徑範圍內的桶；不掃描所有單位。
function Index:Nearby(fromX, fromZ, toX, toZ, radius, excludeKey)
 self.lastQueryCellCount, self.lastQueryRecordCount = 0, 0
 if not positive(radius) or radius > self.maxRadius then return nil end
 if excludeKey ~= nil and not validKey(excludeKey) then return nil end
 local x, z = cellAt(fromX, self.cellSize), cellAt(fromZ, self.cellSize)
 local endX, endZ = cellAt(toX, self.cellSize), cellAt(toZ, self.cellSize)
 if not x or not z or not endX or not endZ then return nil end
 local dx, dz = toX - fromX, toZ - fromZ
 if not finite(dx) or not finite(dz) then return nil end
 local reach = math.ceil((radius + self.maxRadius + Rules.MIN_GAP) / self.cellSize)
 local maxVisits = math.abs(endX - x) + math.abs(endZ - z) + 1
 if not finite(reach) or maxVisits * (reach * 2 + 1) ^ 2 > MAX_QUERY_WORK then return nil end
 local result, visited = {}, {}
 local function visit(centerX, centerZ)
  for nearbyX = centerX - reach, centerX + reach do
   local visitedColumn = visited[nearbyX]
   if not visitedColumn then visitedColumn = {}; visited[nearbyX] = visitedColumn end
   local column = self._cells[nearbyX]
   for nearbyZ = centerZ - reach, centerZ + reach do
    if not visitedColumn[nearbyZ] then
     visitedColumn[nearbyZ] = true
     self.lastQueryCellCount += 1
     local bucket = column and column[nearbyZ]
     if bucket then
      for key, record in pairs(bucket) do
       self.lastQueryRecordCount += 1
       if key ~= excludeKey then
        table.insert(result, { key = key, X = record.X, Z = record.Z, radius = record.radius })
       end
      end
     end
    end
   end
  end
 end
 local stepX = dx > 0 and 1 or dx < 0 and -1 or 0
 local stepZ = dz > 0 and 1 or dz < 0 and -1 or 0
 local deltaX = stepX ~= 0 and self.cellSize / math.abs(dx) or math.huge
 local deltaZ = stepZ ~= 0 and self.cellSize / math.abs(dz) or math.huge
 local boundaryX = (x + (stepX > 0 and 1 or 0)) * self.cellSize
 local boundaryZ = (z + (stepZ > 0 and 1 or 0)) * self.cellSize
 local nextX = stepX ~= 0 and (boundaryX - fromX) / dx or math.huge
 local nextZ = stepZ ~= 0 and (boundaryZ - fromZ) / dz or math.huge
 for _ = 1, maxVisits do
  visit(x, z)
  if x == endX and z == endZ then return result end
  if nextX < nextZ then x += stepX; nextX += deltaX
  elseif nextZ < nextX then z += stepZ; nextZ += deltaZ
  else x += stepX; z += stepZ; nextX += deltaX; nextZ += deltaZ end
 end
 return nil
end

function Rules.overlaps(x, z, radius, neighbors)
 if not finite(x) or not finite(z) or not positive(radius) or type(neighbors) ~= "table" then return true end
 for _, record in ipairs(neighbors) do
  if not recordValid(record) then return true, record end
  local distance = squared(x - record.X, z - record.Z)
  local clearance = radius + record.radius + Rules.MIN_GAP
  local limit = clearance * clearance
  if not distance or not finite(limit) then return true, record end
  if distance < limit - EPSILON then return true, record end
 end
 return false
end

-- 檢查整個 swept disk；終點空曠也不能穿過另一單位。
-- 已重疊時，只有與阻擋中心距離單調增加的位移可以逐步逃出。
function Rules.segmentClear(fromX, fromZ, toX, toZ, radius, neighbors)
 if not finite(fromX) or not finite(fromZ) or not finite(toX) or not finite(toZ)
  or not positive(radius) or type(neighbors) ~= "table" then return false end
 local dx, dz = toX - fromX, toZ - fromZ
 local lengthSquared = squared(dx, dz)
 if not lengthSquared then return false end
 for _, record in ipairs(neighbors) do
  if not recordValid(record) then return false, record end
  local startX, startZ = fromX - record.X, fromZ - record.Z
  local startSquared = squared(startX, startZ)
  local clearance = radius + record.radius + Rules.MIN_GAP
  local limit = clearance * clearance
  local outward = startX * dx + startZ * dz
  if not startSquared or not finite(limit) or not finite(outward) then return false, record end
  if startSquared < limit - EPSILON then
   local endSquared = squared(toX - record.X, toZ - record.Z)
   if not endSquared or outward < -EPSILON or endSquared <= startSquared + EPSILON then return false, record end
  else
   local t = lengthSquared > 0 and math.max(0, math.min(1, -outward / lengthSquared)) or 0
   local closestSquared = squared(startX + dx * t, startZ + dz * t)
   if not closestSquared or closestSquared < limit - EPSILON then return false, record end
  end
 end
 return true
end

function Rules.steeringCandidates(fromX, fromZ, goalX, goalZ, step, side)
 if not finite(fromX) or not finite(fromZ) or not finite(goalX) or not finite(goalZ)
  or not finite(step) or step < 0 or (side ~= nil and side ~= 1 and side ~= -1) then return nil end
 local dx, dz = goalX - fromX, goalZ - fromZ
 local lengthSquared = squared(dx, dz)
 if not lengthSquared then return nil end
 if lengthSquared == 0 or step == 0 then return {} end
 local distance = math.sqrt(lengthSquared)
 local travel = math.min(step, distance)
 local forwardX, forwardZ = dx / distance, dz / distance
 local preferred = side or 1
 local candidates = {}
 -- 等效前進量的左右選項以先前避讓側優先，避免每個 tick 換邊。
 for _, angle in ipairs({ 0, preferred * 30, -preferred * 30, preferred * 60, -preferred * 60, preferred * 90, -preferred * 90 }) do
  local radians = math.rad(angle)
  local cosine, sine = math.cos(radians), math.sin(radians)
  local x = fromX + (forwardX * cosine - forwardZ * sine) * travel
  local z = fromZ + (forwardZ * cosine + forwardX * sine) * travel
  if not finite(x) or not finite(z) then return nil end
  table.insert(candidates, { X = x, Z = z, side = angle == 0 and preferred or angle > 0 and 1 or -1 })
 end
 return candidates
end

-- 正常前向避讓皆受阻時，選擇短距離的後退點；是否可走仍由伺服器
-- 檢查完整線段。點固定保留到到達／逾時，不每個 tick 反向重選。
function Rules.retreatCandidates(fromX, fromZ, goalX, goalZ, distance, side)
 if not finite(fromX) or not finite(fromZ) or not finite(goalX) or not finite(goalZ)
  or not positive(distance) or (side ~= nil and side ~= 1 and side ~= -1) then return nil end
 local dx, dz = goalX - fromX, goalZ - fromZ
 local lengthSquared = squared(dx, dz)
 if not lengthSquared then return nil end
 if lengthSquared == 0 then return {} end
 local length = math.sqrt(lengthSquared)
 local forwardX, forwardZ = dx / length, dz / length
 local preferred = side or 1
 local candidates = {}
 for _, raw in ipairs({ 120, -120, 150, -150, 180 }) do
  local angle = raw * preferred
  local radians = math.rad(angle)
  local cosine, sine = math.cos(radians), math.sin(radians)
  local x = fromX + (forwardX * cosine - forwardZ * sine) * distance
  local z = fromZ + (forwardZ * cosine + forwardX * sine) * distance
  if not finite(x) or not finite(z) then return nil end
  table.insert(candidates, { X = x, Z = z, side = angle > 0 and 1 or -1 })
 end
 return candidates
end

function Rules.retreatDuration(distance, speed, tick)
 if not positive(distance) or not positive(speed) or not finite(tick) or tick < 0 then return nil end
 local duration = distance / speed * 2 + tick
 return positive(duration) and duration or nil
end

return Rules
