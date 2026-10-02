-- Validate the entire destructive request before touching any game object.
local Rules={MAX_SELECTION=200}
local function integer(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge and value%1==0 and value>=0
end
function Rules.deletion(selection,generation,currentGeneration,eligible)
 if not integer(generation) or generation~=currentGeneration or type(selection)~="table" or type(eligible)~="function" then return nil end
 local count=0
 for index in pairs(selection) do
  count+=1
  if count>Rules.MAX_SELECTION or not integer(index) or index<1 or index>Rules.MAX_SELECTION then return nil end
 end
 if count==0 then return nil end
 local validated,seen={},{}
 for index=1,count do
  local model=selection[index]
  if model==nil or seen[model] then return nil end
  local ok,allowed=pcall(eligible,model)
  if not ok or allowed~=true then return nil end
  seen[model]=true
  validated[index]=model
 end
 return validated
end
return Rules
