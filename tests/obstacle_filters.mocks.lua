-- Engine doubles for actual GameServer filter initialization/update and preview filter source.
-- The runner extracts those source sections; collision policy is never copied here.
local checks=0
local function expect(condition,message)
 checks+=1
 assert(condition,message)
end
local Enum={RaycastFilterType={Exclude="Exclude"}}
local function queryParams(class)
 local values={RespectCanCollide=false}
 local object={class=class,filterWrites=0}
 return setmetatable(object,{
  __index=function(_,key) return values[key] end,
  __newindex=function(self,key,value)
   if key=="FilterDescendantsInstances" then rawset(self,"filterWrites",self.filterWrites+1) end
   values[key]=value
  end,
 })
end
local RaycastParams={new=function() return queryParams("RaycastParams") end}
local OverlapParams={new=function() return queryParams("OverlapParams") end}
local function node(name,parent,collidable,queryable)
 return {Name=name,Parent=parent,CanCollide=collidable,CanQuery=queryable}
end
local workspace={children={}}
function workspace:FindFirstChild(name) return self.children[name] end
local units=node("Units",workspace)
local originalGround=node("AOE2_Ground",workspace,true,true)
workspace.children.AOE2_Ground=originalGround
local userScenery=node("RTSScenery",workspace)
workspace.children.RTSScenery=userScenery
local generatedScenery=node("RTSManagedScenery",workspace)
workspace.children.RTSManagedScenery=generatedScenery
local userWall=node("UserWall",userScenery,true,true)
local generatedRoad=node("TradePath",generatedScenery,false,false)
local unitCollider=node("UnitCollider",units,true,true)
local visualOnly=node("VisibleDecoration",workspace,false,true)
local preview=node("BuildingPreview",workspace,false,true)
local ghost=node("BuildingPreviewArt",workspace)
local ghostPart=node("Body",ghost,false,true)
local testParts={originalGround,userWall,generatedRoad,unitCollider,visualOnly,preview,ghostPart}
local function descendant(part,ancestor)
 local current=part
 while current do
  if current==ancestor then return true end
  current=current.Parent
 end
 return false
end
local function contains(list,item)
 for _,value in ipairs(list) do if value==item then return true end end
 return false
end
local function query(params)
 assert(params.FilterType==Enum.RaycastFilterType.Exclude,"fixture only models exclusion queries")
 local result={}
 for _,part in ipairs(testParts) do
  local enabled=params.RespectCanCollide and part.CanCollide or (not params.RespectCanCollide and part.CanQuery)
  local hidden=false
  for _,ancestor in ipairs(params.FilterDescendantsInstances or {}) do
   if descendant(part,ancestor) then hidden=true; break end
  end
  if enabled and not hidden then table.insert(result,part) end
 end
 return result
end
