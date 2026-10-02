-- Pure presentation rules. Construction eligibility remains authoritative on the server.
local Rules = {}

local function positiveInteger(value)
 return type(value)=="number" and value==value and value<math.huge and value>=1 and value%1==0
end

function Rules.items(config,page,age)
 local result={}
 if type(config)~="table" or not positiveInteger(page) or not positiveInteger(age)
  or type(config.BuildPages)~="table" or type(config.BuildOrder)~="table" or type(config.Buildings)~="table" then return result end
 local entry=config.BuildPages[page]
 if type(entry)~="table" or type(entry.buildings)~="table" then return result end
 local allowed,seen={},{}
 for _,kind in ipairs(config.BuildOrder) do
  if type(kind)=="string" then allowed[kind]=true end
 end
 for _,kind in ipairs(entry.buildings) do
  local data=type(kind)=="string" and allowed[kind] and config.Buildings[kind]
  if type(data)=="table" and not seen[kind] then
   seen[kind]=true
   local minimum=data.minAge
   if minimum==nil then minimum=1 end
   if positiveInteger(minimum) and minimum<=age+1 then
    table.insert(result,{kind=kind,locked=minimum>age})
   end
  end
 end
 return result
end

return Rules
