-- 以最小引擎 mock 實際執行原創備用美術（單位、資源）與 HUD 肖像的建構函式，
-- 抓出呼叫不存在的函式、參數錯誤等執行期錯誤。只檢查能建出零件，不檢查外觀；不代替 Studio。
local checks=0
local function expect(ok,message)
 checks+=1
 assert(ok,message)
end
local Vector3,CFrame,Color3,Vector2,UDim2,UDim,Enum,Instance
do
 local V={}
 V.__index=function(v,key)
  if key=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)
  elseif key=="Unit" then local m=math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z); return m>0 and Vector3.new(v.X/m,v.Y/m,v.Z/m) or Vector3.new(0,0,0)
  elseif key=="Cross" then return function(a,b) return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end
  elseif key=="Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
  return nil
 end
 V.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
 V.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
 V.__unm=function(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
 V.__mul=function(a,b)
  if type(a)=="number" then a,b=b,a end
  if type(b)=="number" then return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
  return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
 end
 V.__div=function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end
 Vector3={new=function(x,y,z)
  x,y,z=x or 0,y or 0,z or 0
  assert(type(x)=="number" and type(y)=="number" and type(z)=="number" and x==x and y==y and z==z,"Vector3 needs finite numbers")
  return setmetatable({X=x,Y=y,Z=z,__vector=true},V)
 end}
 Vector3.zero=Vector3.new(0,0,0)
 Vector3.yAxis=Vector3.new(0,1,0)
 -- CFrame: position p plus a row-major 3x3 rotation r.
 local C={}
 local function mulR(a,b)
  local r={}
  for i=0,2 do for j=0,2 do
   r[i*3+j+1]=a[i*3+1]*b[j+1]+a[i*3+2]*b[3+j+1]+a[i*3+3]*b[6+j+1]
  end end
  return r
 end
 local function apply(r,v) return Vector3.new(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z) end
 local function make(p,r) return setmetatable({p=p,r=r},C) end
 C.__index=function(cf,key)
  if key=="Position" then return cf.p
  elseif key=="Rotation" then return make(Vector3.zero,cf.r)
  elseif key=="LookVector" then return apply(cf.r,Vector3.new(0,0,-1))
  elseif key=="RightVector" then return apply(cf.r,Vector3.new(1,0,0))
  elseif key=="UpVector" then return apply(cf.r,Vector3.new(0,1,0))
  elseif key=="Inverse" then return function(self)
   local r=self.r
   local t={r[1],r[4],r[7],r[2],r[5],r[8],r[3],r[6],r[9]}
   return make(-apply(t,self.p),t)
  end end
  return nil
 end
 C.__mul=function(a,b)
  if rawget(b,"__vector") then return apply(a.r,b)+a.p end
  return make(a.p+apply(a.r,b.p),mulR(a.r,b.r))
 end
 C.__add=function(a,v) return make(a.p+v,a.r) end
 C.__sub=function(a,v) return make(a.p-v,a.r) end
 local identity={1,0,0,0,1,0,0,0,1}
 CFrame={}
 CFrame.new=function(x,y,z)
  if type(x)=="table" then return make(x,identity) end
  return make(Vector3.new(x,y,z),identity)
 end
 CFrame.identity=CFrame.new(0,0,0)
 CFrame.Angles=function(x,y,z)
  local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
  local rx={1,0,0,0,cx,-sx,0,sx,cx}
  local ry={cy,0,sy,0,1,0,-sy,0,cy}
  local rz={cz,-sz,0,sz,cz,0,0,0,1}
  return make(Vector3.zero,mulR(mulR(rx,ry),rz))
 end
 CFrame.lookAt=function(at,target)
  local look=(target-at).Unit
  local up=math.abs(look.Y)>0.99 and Vector3.new(0,0,1) or Vector3.new(0,1,0)
  local right=look:Cross(up).Unit
  local realUp=right:Cross(look)
  return make(at,{right.X,realUp.X,-look.X,right.Y,realUp.Y,-look.Y,right.Z,realUp.Z,-look.Z})
 end
 local Col={}
 Col.__index={Lerp=function(a,b,t) return Color3.new(a.R+(b.R-a.R)*t,a.G+(b.G-a.G)*t,a.B+(b.B-a.B)*t) end}
 Color3={new=function(r,g,b) return setmetatable({R=r,G=g,B=b},Col) end}
 Color3.fromRGB=function(r,g,b) return Color3.new(r/255,g/255,b/255) end
 Vector2={new=function(x,y) return {X=x,Y=y} end}
 UDim2={fromScale=function(x,y) return {x,y} end,fromOffset=function(x,y) return {x,y} end,new=function(a,b,c,d) return {a,b,c,d} end}
 UDim={new=function(a,b) return {a,b} end}
 local function enumGroup() return setmetatable({},{__index=function(_,key) return key end}) end
 Enum=setmetatable({},{__index=function(t,key) local g=enumGroup(); rawset(t,key,g); return g end})
 local baseParts={Part=true,WedgePart=true,UnionOperation=true,MeshPart=true}
 local guiObjects={Frame=true,TextLabel=true,ImageLabel=true}
 Instance={new=function(class)
  local props={ClassName=class,Name=class,children={},attributes={}}
  local object
  object=setmetatable({},{
   __index=function(_,key)
    if key=="SetAttribute" then return function(self,k,v) props.attributes[k]=v end
    elseif key=="GetAttribute" then return function(self,k) return props.attributes[k] end
    elseif key=="GetChildren" then return function() local list={}; for child in pairs(props.children) do table.insert(list,child) end; return list end
    elseif key=="GetDescendants" then return function()
     local list={}
     local function walk(node) for child in pairs(rawget(getmetatable(node),"props").children) do table.insert(list,child); walk(child) end end
     walk(object)
     return list
    end
    elseif key=="IsA" then return function(self,name) return name==class or (name=="BasePart" and baseParts[class]==true) or (name=="GuiObject" and guiObjects[class]==true) end
    elseif key=="Destroy" then return function() if props.Parent then rawget(getmetatable(props.Parent),"props").children[object]=nil end end
    end
    return props[key]
   end,
   __newindex=function(_,key,value)
    if key=="Parent" then
     if props.Parent then rawget(getmetatable(props.Parent),"props").children[object]=nil end
     if value then rawget(getmetatable(value),"props").children[object]=true end
    elseif key=="CFrame" then assert(type(value)=="table" and value.r,"CFrame must be a CFrame")
    elseif key=="Size" and baseParts[class] then assert(rawget(value,"__vector"),"part Size must be a Vector3")
    end
    props[key]=value
   end,
   props=props,
  })
  return object
 end}
end
local function count(model) return #model:GetDescendants() end
--@@MODULES@@
local team=Color3.fromRGB(81,158,199)
for kind in pairs(Config.Units) do
 local build=ArtUnits.builders[kind]
 expect(build~=nil,"no fallback art builder for unit "..kind)
 local model=Instance.new("Model")
 model.Name=kind
 build(model,kind,team,0)
 expect(count(model)>=8,"unit art built too few parts: "..kind)
 for _,part in ipairs(model:GetDescendants()) do
  expect(part.CFrame~=nil and part.Size~=nil,"unit part without CFrame / Size: "..kind)
 end
 local holder=Instance.new("Frame")
 UnitIcons.Create(holder,kind,nil,nil,team)
 local fallback=Instance.new("Frame")
 UnitIcons.Create(fallback,"__unknown__",nil,nil,team)
 expect(count(holder)>count(fallback),"unit has no HUD portrait painter: "..kind)
end
for kind in pairs(Config.Resources) do
 local build=ArtNature[kind]
 expect(build~=nil,"no fallback art builder for resource "..kind)
 for stage=0,3 do
  local model=Instance.new("Model")
  model.Name=kind
  build(model,kind,team,stage)
  expect(count(model)>=1,"resource stage built nothing: "..kind.." "..stage)
 end
end
do
 local relic=Instance.new("Model")
 relic.Name="Relic"
 expect(ArtNature.Relic~=nil,"no relic art builder")
 ArtNature.Relic(relic,"Relic",team,0)
 expect(count(relic)>=6,"relic art built too few parts")
end
for carry in pairs(ArtUnits.carryKinds) do
 local model=Instance.new("Model")
 expect(#ArtUnits.carry(model,carry)>=1,"carry load built nothing: "..carry)
end
for tool in pairs(ArtUnits.toolKinds) do
 local model=Instance.new("Model")
 expect(#ArtUnits.tool(model,tool)>=1,"villager tool built nothing: "..tool)
end
print(string.format("PASS: %d fallback unit / resource art and HUD portrait smoke checks (engine mock, not Studio)",checks))
