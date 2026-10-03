-- Engine boundary mocks; verify.ps1 inserts the actual moveToward source here.
local PathRules=require("../src/ServerScriptService/ServerModules/PathRules")
local UnitCollisionRules=require("../src/ServerScriptService/ServerModules/UnitCollisionRules")
local MAX_UNIT_RADIUS=4
local unitCollisionIndex=UnitCollisionRules.newIndex(16,MAX_UNIT_RADIUS)
local orders={}
local Config={Map={GroundY=0}}
-- Server movement only moves the Root; the mock unit tracks its position the same way.
local Factory={moveUnit=function(unit,frame) unit:PivotTo(frame) end}
local vector={}
vector.__index=function(self,key)
 if key=="Magnitude" then return math.sqrt(self.X*self.X+self.Y*self.Y+self.Z*self.Z) end
 if key=="Unit" then local n=self.Magnitude; return setmetatable({X=self.X/n,Y=self.Y/n,Z=self.Z/n},vector) end
 return vector[key]
end
local Vector3={new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vector) end}
vector.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vector.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vector.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local CFrame={new=function(point) return {Position=point} end,lookAt=function(point,target) return {Position=point,target=target} end}
local blocked=false
local staticSegmentHook
local workspace={Blockcast=function() return blocked and {} or nil end}
local rayParams={}
local routes=0
local function position(unit) return unit.pos end
local function route() routes+=1 end -- Asynchronous engine requests are counted only.
local function staticUnitSegmentClear(unit,from,to)
 return not blocked and (not staticSegmentHook or staticSegmentHook(unit,from,to))
end -- Mock engine scenery only; optional boundaries exercise actual movement guards.
local function unitNeighbors(unit,from,to,radius) return unitCollisionIndex:Nearby(from.X,from.Z,to.X,to.Z,radius,unit) end
local function unitPositionClear(unit,pos,radius) return not UnitCollisionRules.overlaps(pos.X,pos.Z,radius,unitNeighbors(unit,pos,pos,radius)) end
local function stop(unit) unit.stopped=true; orders[unit]=nil end
-- 讓路分支只對真正的 Instance 生效；mock 單位是表，這裡只提供名稱（讓路的候選點規則在 unit_collision.spec 測）。
local units={}
local function owner(model) return model and model.owner end
local function issue(unit,kind,target) orders[unit]={kind=kind,target=target} end
local function actor(x,z,radius,keepIndex)
 if not keepIndex then unitCollisionIndex=UnitCollisionRules.newIndex(16,MAX_UNIT_RADIUS); orders={} end
 local unit={pos=Vector3.new(x,0,z or 0),radius=radius or 2,moves=0,GetAttribute=function(self,key) return key=="Animation" and (self.Animation or "Idle") or self.radius end,SetAttribute=function(self,key,value) self[key]=value end,
  PivotTo=function(self,frame) self.pos=frame.Position-Vector3.new(0,2.5,0); self.moves+=1 end}
 unitCollisionIndex:Update(unit,unit.pos.X,unit.pos.Z,unit.radius)
 return unit
end
