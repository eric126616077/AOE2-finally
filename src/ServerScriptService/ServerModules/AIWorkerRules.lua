-- Economic allocation uses shortages, then tries actual available nodes in that order.
local Rules={}
local keys={"food","wood","gold","stone"}
local ratios={food=0.42,wood=0.36,gold=0.16,stone=0.06}
function Rules.resourcePriorities(villagers,gathering,food)
 local priorities={}
 for index,key in ipairs(keys) do
  local shortage=villagers*ratios[key]-(gathering[key] or 0)
  if key=="food" and food<150 then shortage+=1 end
  table.insert(priorities,{key=key,shortage=shortage,index=index})
 end
 table.sort(priorities,function(a,b) return a.shortage==b.shortage and a.index<b.index or a.shortage>b.shortage end)
 local ordered={}
 for _,entry in ipairs(priorities) do table.insert(ordered,entry.key) end
 return ordered
end
function Rules.findResource(priorities,find)
 for _,key in ipairs(priorities) do
  local target=find(key)
  if target then return target,key end
 end
 return nil
end
function Rules.builder(candidates,site,now)
 local found,nearest=nil,math.huge
 for _,candidate in ipairs(candidates) do
  if candidate.valid then
   if candidate.orderKind=="build" and candidate.orderTarget==site then return candidate.unit,true end
   if candidate.orderKind~="build" and (not candidate.retryAfter or now>=candidate.retryAfter) and candidate.distance<nearest then
    found,nearest=candidate.unit,candidate.distance
   end
  end
 end
 return found,false
end
return Rules
