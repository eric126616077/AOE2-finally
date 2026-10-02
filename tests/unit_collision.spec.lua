local Rules = require("../src/ServerScriptService/ServerModules/UnitCollisionRules")
local checks = 0
local function expect(value, message) checks += 1; assert(value, message) end
local function near(value, target) return math.abs(value - target) < 1e-8 end
local function unit(key, x, z, radius) return { key = key, X = x, Z = z, radius = radius } end
local function includes(records, key)
 for _, record in ipairs(records) do if record.key == key then return record end end
 return nil
end

local body = unit("villager", 0, 0, 1.8)
local gap = 1.8 + body.radius + Rules.MIN_GAP
expect(Rules.segmentClear(-8, gap, 8, gap, 1.8, { body }), "touch at minimum gap should be legal")
expect(not Rules.segmentClear(-8, gap - .01, 8, gap - .01, 1.8, { body }), "near-tangent swept disk penetrates unit")
local clear, blocker = Rules.segmentClear(-20, 0, 20, 0, 1.8, { body })
expect(not clear and blocker == body, "long sweep passed through occupied middle despite clear endpoint")
expect(not Rules.overlaps(20, 0, 1.8, { body }), "long sweep fixture endpoint should be clear")
expect(not Rules.segmentClear(-6, 0, -2, 0, 1.8, { body }), "head-on movement did not stop before contact")
expect(not Rules.segmentClear(0, -8, 0, 8, 1.8, { body }), "crossing path went through occupied intersection")
expect(Rules.segmentClear(-8, -8, -8, 8, 1.8, { body }), "clear parallel movement blocked")
local siege = unit("siege", 0, 0, 4.6)
expect(not Rules.segmentClear(-15, 5, 15, 5, 1.8, { siege }), "large unit radius was ignored")
expect(Rules.segmentClear(-15, 6.45, 15, 6.45, 1.8, { siege }), "large unit tangent rejected")
expect(Rules.overlaps(3.6, 0, 1.8, { body }), "minimum gap did not separate touching art bodies")
expect(not Rules.overlaps(gap, 0, 1.8, { body }), "minimum gap boundary overlapped")
expect(Rules.segmentClear(1, 0, 1.2, 0, 1.8, { body }), "small outward overlap escape rejected")
expect(Rules.segmentClear(1, 0, 1, 1, 1.8, { body }), "tangential overlap escape should increase center distance")
expect(Rules.segmentClear(0, 0, 1, 0, 1.8, { body }), "coincident units cannot separate")
expect(not Rules.segmentClear(1, 0, .5, 0, 1.8, { body }), "overlap movement approached blocking center")
expect(not Rules.segmentClear(1, 0, -10, 0, 1.8, { body }), "overlap escaped through opposing body")
expect(not Rules.segmentClear(1, 0, 1, 0, 1.8, { body }), "stationary overlapping body was called clear")
expect(Rules.segmentClear(gap, 0, gap, 0, 1.8, { body }), "stationary legal contact blocked")
expect(not Rules.segmentClear(1, 0, 3, 0, 1.8, { body, unit("other", 4, 0, 1.8) }), "escaping one overlap entered another unit")

local index = assert(Rules.newIndex(12, 5))
expect(index:Update("villager", -1, -1, 1.8), "negative coordinate unit rejected")
expect(index:Update("siege", 10, 0, 5), "large supported radius rejected")
expect(index:Update("exclude", 0, 0, 1.8), "excluded record setup failed")
local nearby = index:Nearby(-1, -1, -1, -1, 1.8, "exclude")
expect(includes(nearby, "villager") and not includes(nearby, "exclude"), "negative buckets or self exclusion broken")
nearby = index:Nearby(3.1, 0, 3.1, 0, 1.8)
expect(includes(nearby, "siege"), "center cell query omitted a large body reaching into neighbor cells")
expect(not Rules.segmentClear(3.1, 0, 4, 0, 1.8, nearby), "query omitted approaching large body")
expect(index:Update("villager", 250, 250, 1.8), "moved unit rejected")
expect(not includes(index:Nearby(-1, -1, -1, -1, 1.8), "villager"), "old bucket retained moved unit")
expect(includes(index:Nearby(250, 250, 250, 250, 1.8), "villager"), "new bucket absent immediately after movement")
expect(index:Update("villager", 251, 251, 2), "same-cell position update failed")
local updated = includes(index:Nearby(251, 251, 251, 251, 1.8), "villager")
expect(updated and updated.X == 251 and updated.Z == 251 and updated.radius == 2, "same bucket update stale")
updated.X = -300
expect(includes(index:Nearby(251, 251, 251, 251, 1.8), "villager").X == 251, "query results can corrupt index positions")
expect(index:Remove("villager") and not index:Remove("villager"), "remove lifecycle idempotency failed")
expect(not includes(index:Nearby(251, 251, 251, 251, 1.8), "villager"), "removed unit still blocks")
expect(index._cells[20] == nil, "empty columns retained after unit removal")

-- Hundreds of distant buckets must not be read for one local movement.
for i = 1, 1000 do expect(index:Update("far" .. i, 1000 + i * 12, 1000, 1.8), "far fixture failed") end
nearby = index:Nearby(-2, 0, 2, 0, 1.8)
expect(#nearby == 2 and index.lastQueryRecordCount == 2, "local query read distant records")
expect(index.lastQueryCellCount <= 12, "one local segment traversed excessive grid cells")
local diagonalIndex = assert(Rules.newIndex(12, 5))
expect(diagonalIndex:Update("crossing", 120, 120, 1.8), "diagonal blocker setup failed")
expect(diagonalIndex:Update("off-line", 120, -120, 1.8), "off-line setup failed")
nearby = diagonalIndex:Nearby(-240, -240, 240, 240, 1.8)
expect(includes(nearby, "crossing") and not includes(nearby, "off-line"), "diagonal query visited distant swept-rectangle corner")
expect(diagonalIndex.lastQueryCellCount < 300, "diagonal query scanned bounding rectangle instead of segment cells")
expect(not Rules.segmentClear(-240, -240, 240, 240, 1.8, nearby), "diagonal middle blocker missed")

-- 以完整集合當獨立 oracle，確認局部查詢不遺漏不同斜率、象限或半徑。
math.randomseed(20261001)
local oracleIndex = assert(Rules.newIndex(12, 5))
local allRecords = {}
for i = 1, 120 do
 local record = unit(i, math.random() * 480 - 240, math.random() * 480 - 240, .5 + math.random() * 4.5)
 table.insert(allRecords, record)
 assert(oracleIndex:Update(record.key, record.X, record.Z, record.radius))
end
for _ = 1, 150 do
 local fromX, fromZ, toX, toZ = math.random() * 480 - 240, math.random() * 480 - 240, math.random() * 480 - 240, math.random() * 480 - 240
 local radius = .5 + math.random() * 4.5
 local localRecords = assert(oracleIndex:Nearby(fromX, fromZ, toX, toZ, radius))
 expect(Rules.segmentClear(fromX, fromZ, toX, toZ, radius, localRecords) == Rules.segmentClear(fromX, fromZ, toX, toZ, radius, allRecords), "local broadphase missed swept disk collision")
 expect(Rules.overlaps(toX, toZ, radius, localRecords) == Rules.overlaps(toX, toZ, radius, allRecords), "local broadphase missed destination overlap")
end

-- Opposing agents and crossing agents consult the latest committed position.
local live = assert(Rules.newIndex(12, 5))
expect(live:Update("a", -4, 0, 1.8) and live:Update("b", 4, 0, 1.8), "opposing fixtures failed")
expect(Rules.segmentClear(-4, 0, -1, 0, 1.8, live:Nearby(-4, 0, -1, 0, 1.8, "a")), "first head-on step unexpectedly blocked")
expect(live:Update("a", -1, 0, 1.8), "first movement not indexed")
expect(not Rules.segmentClear(4, 0, 1, 0, 1.8, live:Nearby(4, 0, 1, 0, 1.8, "b")), "second head-on step used stale first position")
expect(live:Update("a", 0, 0, 1.8) and live:Update("b", 0, -6, 1.8), "crossing fixtures failed")
expect(not Rules.segmentClear(0, -6, 0, 6, 1.8, live:Nearby(0, -6, 0, 6, 1.8, "b")), "crossing body teleported through committed intersection")

local candidates = assert(Rules.steeringCandidates(0, 0, 10, 0, 2, -1))
expect(#candidates == 7 and near(candidates[1].X, 2) and near(candidates[1].Z, 0), "straight movement candidate changed")
expect(candidates[2].Z < 0 and candidates[2].side == -1 and candidates[3].Z > 0, "persisted avoidance side not preferred")
local previousProgress = math.huge
for _, candidate in ipairs(candidates) do
 local distance = math.sqrt(candidate.X ^ 2 + candidate.Z ^ 2)
 expect(distance <= 2 + 1e-8, "steering exceeded movement step")
 expect(candidate.X <= previousProgress + 1e-8, "steering not ordered by forward benefit")
 previousProgress = candidate.X
end
candidates = assert(Rules.steeringCandidates(1, 2, 1.3, 2.4, 20, 1))
expect(near(candidates[1].X, 1.3) and near(candidates[1].Z, 2.4), "straight steering overshot near goal")
for _, candidate in ipairs(candidates) do
 expect(math.sqrt((candidate.X - 1) ^ 2 + (candidate.Z - 2) ^ 2) <= .5 + 1e-8, "near-goal steering exceeds remaining distance")
end
expect(#Rules.steeringCandidates(0, 0, 0, 0, 1) == 0 and #Rules.steeringCandidates(0, 0, 1, 0, 0) == 0, "zero-distance or zero-step generated motion")

local retreats = assert(Rules.retreatCandidates(0, 0, 0, -40, 8, -1))
expect(#retreats == 5 and retreats[1].X < 0 and retreats[1].side == -1, "retreat does not preserve preferred side")
for _, candidate in ipairs(retreats) do
 expect(near(math.sqrt(candidate.X ^ 2 + candidate.Z ^ 2), 8), "retreat exceeded fixed distance budget")
 expect(candidate.Z > 0, "retreat candidate does not create room behind the unit")
end
expect(#Rules.retreatCandidates(0, 0, 0, 0, 8) == 0, "coincident goal invented a retreat direction")
expect(near(Rules.retreatDuration(8, 14, .1), 8 / 14 * 2 + .1), "retreat expiry does not follow speed and server tick")
expect(Rules.MAX_RETREAT_ATTEMPTS == 2, "retreat retry budget is not bounded at two attempts")
expect(Rules.retreatDuration(8, 0, .1) == nil and Rules.retreatDuration(8, 14, -.1) == nil, "invalid retreat timing accepted")

local invalids = { math.huge, -math.huge, 0 / 0, "1", false }
for _, invalid in ipairs(invalids) do
 expect(Rules.newIndex(invalid, 5) == nil and Rules.newIndex(12, invalid) == nil, "invalid index sizing accepted")
 expect(not index:Update("siege", invalid, 0, 1.8), "invalid indexed coordinate accepted")
 expect(not index:Update("siege", 0, 0, invalid), "invalid indexed radius accepted")
 expect(index:Nearby(invalid, 0, 1, 0, 1.8) == nil, "invalid query origin accepted")
 expect(index:Nearby(0, 0, invalid, 0, 1.8) == nil, "invalid query endpoint accepted")
 expect(not Rules.segmentClear(invalid, 0, 1, 0, 1.8, {}), "invalid segment coordinate cleared")
 expect(not Rules.segmentClear(0, 0, 1, 0, invalid, {}), "invalid moving radius cleared")
 expect(not Rules.segmentClear(0, 0, 1, 0, 1.8, { unit("bad", invalid, 0, 1.8) }), "invalid neighbor coordinate cleared")
 expect(not Rules.segmentClear(0, 0, 1, 0, 1.8, { unit("bad", 50, 0, invalid) }), "invalid neighbor radius cleared")
 expect(Rules.overlaps(invalid, 0, 1.8, {}), "invalid overlap input accepted")
 expect(Rules.steeringCandidates(0, 0, 10, 0, invalid) == nil, "invalid steering step accepted")
 expect(Rules.retreatCandidates(invalid, 0, 10, 0, 8) == nil and Rules.retreatCandidates(0, 0, 10, 0, invalid) == nil, "invalid retreat geometry accepted")
 expect(Rules.retreatDuration(8, invalid, .1) == nil and Rules.retreatDuration(8, 14, invalid) == nil, "invalid retreat timing accepted")
end
expect(Rules.newIndex(0, 5) == nil and Rules.newIndex(12, 0) == nil, "zero index dimensions accepted")
expect(not index:Update(nil, 0, 0, 1.8) and not index:Update(0 / 0, 0, 0, 1.8), "invalid key accepted")
expect(not index:Update("siege", 0, 0, 5.1), "radius exceeds index broadphase bound")
expect(includes(index:Nearby(10, 0, 10, 0, 1.8), "siege").X == 10, "invalid updates changed previous position")
expect(index:Nearby(0, 0, 1e300, 0, 1.8) == nil, "enormous finite query not bounded")
expect(not Rules.segmentClear(0, 0, 1e300, 0, 1.8, {}), "finite coordinates overflowed sweep arithmetic")
expect(Rules.steeringCandidates(0, 0, 1e300, 0, 1) == nil, "overflowed steering accepted")
expect(Rules.retreatCandidates(0, 0, 1e300, 0, 8) == nil and Rules.retreatDuration(1e300, 1e-300, .1) == nil, "overflowed retreat geometry or deadline accepted")
expect(Rules.retreatCandidates(0, 0, 10, 0, 0) == nil and Rules.retreatCandidates(0, 0, 10, 0, 8, 0) == nil, "invalid retreat distance or side accepted")
expect(Rules.steeringCandidates(0, 0, 1, 0, -1) == nil and Rules.steeringCandidates(0, 0, 1, 0, 1, 0) == nil, "invalid step or side accepted")
expect(not Rules.segmentClear(0, 0, 1, 0, 1.8, nil) and Rules.overlaps(0, 0, 1.8, nil), "missing neighbor list failed open")
print("PASS: " .. checks .. " unit swept-disk / large-radius / overlap escape / local index / live update / steering / finite validation checks (pure geometry; not Studio Play)")
