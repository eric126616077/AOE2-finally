-- Only engine doubles for the actual ModelFactory body bundled by verify.ps1.
local checks=0
local function expect(condition,message)
 checks+=1
 assert(condition,message)
end
local Vector3={}
local vectorMeta={}
vectorMeta.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
local frameMeta={}
local CFrame={}
local function frame(position,right,up,look)
 return setmetatable({Position=position,RightVector=right,UpVector=up,LookVector=look},frameMeta)
end
function CFrame.new(x,y,z)
 local position=type(x)=="table" and x or Vector3.new(x or 0,y or 0,z or 0)
 return frame(position,Vector3.new(1,0,0),Vector3.new(0,1,0),Vector3.new(0,0,-1))
end
local function rotate(a,b) return a.RightVector*b.X+a.UpVector*b.Y-a.LookVector*b.Z end
frameMeta.__mul=function(a,b)
 return frame(a.Position+rotate(a,b.Position),rotate(a,b.RightVector),rotate(a,b.UpVector),rotate(a,b.LookVector))
end
frameMeta.__index={Inverse=function(self)
 local r,u,l=self.RightVector,self.UpVector,self.LookVector
 local inverse=frame(Vector3.new(0,0,0),Vector3.new(r.X,u.X,-l.X),Vector3.new(r.Y,u.Y,-l.Y),Vector3.new(-r.Z,-u.Z,l.Z))
 inverse.Position=rotate(inverse,self.Position)*-1
 return inverse
end,ToObjectSpace=function(self,other) return self:Inverse()*other end}
function CFrame.Angles(x,y,z)
 local zero=Vector3.new(0,0,0)
 local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
 return frame(zero,Vector3.new(1,0,0),Vector3.new(0,cx,sx),Vector3.new(0,sx,-cx))
  *frame(zero,Vector3.new(cy,0,-sy),Vector3.new(0,1,0),Vector3.new(-sy,0,-cy))
  *frame(zero,Vector3.new(cz,sz,0),Vector3.new(-sz,cz,0),Vector3.new(0,0,-1))
end
local Enum={PartType={Cylinder="Cylinder"}}
local function item(class,name)
 local value={ClassName=class,Name=name,Archivable=true,Anchored=false,CanCollide=true,CanTouch=true,CanQuery=true,Transparency=0,
  CastShadow=true,Size=Vector3.new(1,1,1),CFrame=CFrame.new(Vector3.new(0,0,0)),children={}}
 function value:IsA(target)
  return target==self.ClassName or (target=="BasePart" and self.ClassName=="Part")
   or (target=="BaseScript" and (self.ClassName=="Script" or self.ClassName=="LocalScript"))
 end
 function value:FindFirstChildWhichIsA(target)
  for _,child in ipairs(self.children) do if not child.destroyed and child:IsA(target) then return child end end
 end
 function value:Destroy() self.destroyed=true end
 function value:SetAttribute(name,attribute) self.attributes=self.attributes or {}; self.attributes[name]=attribute end
 return setmetatable(value,{__index=function(self,key)
  if key=="Position" then return self.CFrame.Position end
 end,__newindex=function(self,key,newValue)
  rawset(self,key,newValue)
  if key=="Parent" and type(newValue)=="table" and type(newValue.children)=="table" then table.insert(newValue.children,self) end
 end})
end
local function model(children)
 local value=item("Model","Template")
 value.children=children or {}
 value.bounds=Vector3.new(4,2,2)
 value.scale=1
 value.attributes={}
 value.cloneCalls=0
 function value:FindFirstChildWhichIsA(class)
  for _,child in ipairs(self.children) do if not child.destroyed and child:IsA(class) then return child end end
 end
 function value:FindFirstChild(name)
  for _,child in ipairs(self.children) do if not child.destroyed and child.Name==name then return child end end
 end
 function value:GetDescendants() assert(not self.destroyed,"queried destroyed copy"); return self.children end
 function value:Clone()
  self.cloneCalls+=1
  if self.cloneError then error("engine clone failure") end
  if not self.Archivable then return nil end
  local copied={}
  for _,child in ipairs(self.children) do
   if child.Archivable then
    local copy=item(child.ClassName,child.Name)
    copy.Anchored,copy.CanCollide,copy.CanTouch,copy.CanQuery=child.Anchored,child.CanCollide,child.CanTouch,child.CanQuery
    copy.Transparency=child.Transparency
    copy.CastShadow,copy.Size,copy.CFrame=child.CastShadow,child.Size,child.CFrame
    table.insert(copied,copy)
   end
  end
  self.lastCopy=model(copied)
  self.lastCopy.bounds=self.bounds
  self.lastCopy.scale=self.scale
  return self.lastCopy
 end
 function value:GetBoundingBox() return CFrame.new(Vector3.new(0,0,0)),self.bounds end
 function value:GetScale() return self.scale end
 function value:ScaleTo(scale) self.bounds=self.bounds*(scale/self.scale); self.scale=scale end
 function value:GetPivot()
  if self.PrimaryPart then
   local position=rawget(self.PrimaryPart,"Position")
   if position then self.PrimaryPart.CFrame=CFrame.new(position); rawset(self.PrimaryPart,"Position",nil) end
   return self.PrimaryPart.CFrame
  end
  return self.pivot or CFrame.new(Vector3.new(0,0,0))
 end
 function value:PivotTo(target)
  local transform=target*self:GetPivot():Inverse()
  for _,child in ipairs(self.children) do
   if child:IsA("BasePart") and not child.destroyed then child.CFrame=transform*child.CFrame end
  end
  self.pivot=target
 end
 function value:SetAttribute(name,attribute) self.attributes[name]=attribute end
 return value
end
local folders={}
local RS={Shared={Art={}}}
function RS:FindFirstChild(name) return folders[name] end
local game={GetService=function(_,name) assert(name=="ReplicatedStorage"); return RS end}
local Instance={new=function(class) return item(class,class) end}
local fallbackCalls=0
local Art={ApplyPlayerColor=function(value,team) value.appliedTeam=team end,Create=function(kind,team)
 fallbackCalls+=1
 local geometry=item("Part","FallbackGeometry")
 geometry.Anchored,geometry.CanCollide,geometry.CanTouch=true,false,false
 local value=model({geometry})
 value.fallbackKind,value.fallbackTeam=kind,team
 return value
end}
