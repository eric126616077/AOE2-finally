-- Engine-independent farm rules: one worker per field, reseeding and the mill's prepaid queue.
local Rules = {}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function count(value)
 return finite(value) and value>=0 and value%1==0
end

-- A villager keeps its field while gathering there or while delivering a load it will return from.
function Rules.holds(orderKind, orderTarget, returnTarget, farm)
 if farm==nil then return false end
 return (orderKind=="gather" and orderTarget==farm) or (orderKind=="deliver" and returnTarget==farm)
end

function Rules.free(holder, unit)
 return holder==nil or holder==unit
end

function Rules.canQueue(queued, limit)
 return count(queued) and count(limit) and queued<limit
end

function Rules.canUnqueue(queued)
 return count(queued) and queued>0
end

-- An exhausted field first uses a farm prepaid at the mill; otherwise wood is spent only
-- for an explicit player order or when automatic reseeding is allowed.
function Rules.reseedSource(queued, manual, automatic)
 if count(queued) and queued>0 then return "queue" end
 if manual==true or automatic==true then return "wood" end
 return nil
end

return Rules
