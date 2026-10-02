-- Explicit SERVER Studio fixture only. Requiring this module never runs it.
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local Factory=require(script.Parent.ModelFactory)
local Config=require(ReplicatedStorage.GameData.GameConfig)
local Tests={}
function Tests.Run()
 assert(RunService:IsStudio() and RunService:IsServer() and RunService:IsRunning(),"僅限新的 Studio SERVER Play 明確呼叫")
 local checks=0
 local function expect(condition,message)
  checks+=1
  assert(condition,message)
  print("[FACTORY_FIXTURE PASS] "..message)
 end
 local private=Instance.new("Folder")
 private.Name="RTSFactoryFixture_"..HttpService:GenerateGUID(false)
 private.Parent=ReplicatedStorage
 local unitWorld=Instance.new("Folder")
 unitWorld.Name=private.Name.."_Units"
 unitWorld.Parent=workspace
 private:SetAttribute("UserId",-98765)
 private:SetAttribute("DisplayName","碰撞測試電腦")
 private:SetAttribute("TeamColor",Color3.fromRGB(70,150,190))
 local outputs={}
 local source
 local position,size=Vector3.new(64,0,64),Vector3.new(16,14,16)
 local function snapshot(root)
  local values={}
  for _,item in ipairs({root,table.unpack(root:GetDescendants())}) do
   local value={object=item,Parent=item.Parent,Name=item.Name,Archivable=item.Archivable,marker=item:GetAttribute("FactoryFixtureMarker")}
   if item:IsA("BasePart") then
    value.Size,value.CFrame,value.Color=item.Size,item.CFrame,item.Color
    value.Anchored,value.CanCollide,value.CanTouch,value.CanQuery=item.Anchored,item.CanCollide,item.CanTouch,item.CanQuery
    value.Transparency=item.Transparency
   elseif item:IsA("BaseScript") then value.Enabled=item.Enabled end
   if item:IsA("Model") then value.PrimaryPart=item.PrimaryPart end
   table.insert(values,value)
  end
  return values
 end
 local function unchanged(values)
  for _,value in ipairs(values) do
   local item=value.object
   for name,before in pairs(value) do
    if name~="object" and name~="marker" then expect(item[name]==before,"原fixture "..item.Name.." 的 "..name.." 保留") end
   end
   expect(item:GetAttribute("FactoryFixtureMarker")==value.marker,"原fixture標記保留")
  end
  expect(#source:GetDescendants()==#values-1,"原fixture實例數未變")
 end
 local function create(rootArchivable,partArchivable)
  source=Instance.new("Model")
  source.Name="House"
  source:SetAttribute("FactoryFixtureMarker","source")
  local part=Instance.new("Part")
  part.Name="PrivateGeometry"
  part.Size,part.CFrame=Vector3.new(6,5,4),CFrame.new(900,15,900)
  part.Anchored,part.CanCollide,part.CanTouch,part.CanQuery=false,true,true,true
  part.Archivable=partArchivable
  part.Parent=source
  source.PrimaryPart=part
  local hidden=Instance.new("Part")
  hidden.Name="PrivateHiddenGeometry"
  hidden.Size,hidden.CFrame=Vector3.new(2,2,2),part.CFrame
  hidden.Transparency=1
  hidden.Archivable=partArchivable
  hidden.Parent=source
  -- Disabled before parenting; never enabled, never given Source, never required.
  local passiveScript=Instance.new("Script")
  passiveScript.Name="DisabledPrivateScript"
  passiveScript.Enabled=false
  passiveScript.Parent=source
  local passiveModule=Instance.new("ModuleScript")
  passiveModule.Name="UnrequiredPrivateModule"
  passiveModule.Parent=source
  source.Archivable=rootArchivable
  source.Parent=private
  return snapshot(source)
 end
 local function generate()
  local value=Factory.model("House",position,size,nil,private.Name,Color3.fromRGB(70,150,190))
  table.insert(outputs,value)
  expect(value:IsA("Model") and value.Parent==nil,"工廠返回孤立Model、不生成遊戲單位或建築")
  local footprint=value.PrimaryPart
  expect(footprint and footprint.Name=="Footprint" and footprint.Size==size,"正式占地尺寸與PrimaryPart正確")
  expect(footprint.Anchored and footprint.CanCollide and footprint.CanQuery and not footprint.CanTouch,"正式占地旗標正確")
  expect((footprint.Position-(position+Vector3.new(0,size.Y/2,0))).Magnitude<0.001,"正式占地位置正確")
  local _,bounds=value:GetBoundingBox()
  expect(bounds.X>0 and bounds.Y>0 and bounds.Z>0,"回退或複製後有實際幾何")
  return value
 end
 local ok,failure=xpcall(function()
  local missing=generate()
  expect(not missing:FindFirstChild("PrivateGeometry",true),"缺模板使用替代外觀")
  local values=create(false,true)
  local denied=generate()
  expect(not denied:FindFirstChild("PrivateGeometry",true),"Archivable=false根模板回退成功")
  unchanged(values)
  source:Destroy(); source=nil
  values=create(true,false)
  local omitted=generate()
  expect(not omitted:FindFirstChild("PrivateGeometry",true),"所有BasePart不可複製時回退成功")
  unchanged(values)
  source:Destroy(); source=nil
  values=create(true,true)
  local copy=generate()
  local geometry=copy:FindFirstChild("PrivateGeometry",true)
  expect(geometry and geometry~=source.PrimaryPart and geometry.Anchored and not geometry.CanCollide and not geometry.CanTouch,"可用模板複製且只調整複製品")
  expect(not copy:FindFirstChild("DisabledPrivateScript",true),"複製品BaseScript已移除")
  expect(copy:FindFirstChild("UnrequiredPrivateModule",true)~=nil,"未執行的ModuleScript保留")
  expect(not copy.PrivateHiddenGeometry.CanQuery,"透明複製幾何不擋射線")
  unchanged(values)
  local count=0
  for kind,data in pairs(Config.Units) do
   count+=1
   local profile=Config.UnitCollision.profiles[data.class] or Config.UnitCollision.default
   local location=Vector3.new(1200+count*24,Config.Map.GroundY,1200)
   local unit=Factory.unit(kind,location,data,private)
   table.insert(outputs,unit)
   unit.Parent=unitWorld
   local root,volume=unit:FindFirstChild("Root"),unit:FindFirstChild("CollisionVolume")
   expect(root and unit.PrimaryPart==root and not root.CanCollide and not root.CanQuery,kind.."保留原Root與PrimaryPart")
   expect(volume and volume.Shape==Enum.PartType.Cylinder,kind.."具有圓柱碰撞體積")
   expect(volume.Anchored and volume.CanCollide and volume.CanQuery and not volume.CanTouch,kind.."碰撞旗標正確")
   expect(volume.Transparency==1 and not volume.CastShadow,kind.."碰撞體積透明且不投影")
   expect((volume.Size-Vector3.new(profile.height,profile.radius*2,profile.radius*2)).Magnitude<0.001,kind.."碰撞尺寸使用共用設定")
   expect((volume.Position-(location+Vector3.new(0,profile.height/2,0))).Magnitude<0.001,kind.."碰撞底面貼合地面")
   expect(math.abs(math.abs(volume.CFrame.RightVector.Y)-1)<0.001,kind.."圓柱X軸保持垂直")
   expect(unit:GetAttribute("Radius")==profile.radius and unit:GetAttribute("CollisionHeight")==profile.height,kind.."碰撞屬性一致")
   local modifier=volume:FindFirstChildWhichIsA("PathfindingModifier")
   expect(modifier and modifier.PassThrough,kind.."動態體積不阻擋靜態尋路網格")
   local colliders=0
   for _,part in ipairs(unit:GetDescendants()) do
    if part:IsA("BasePart") and part.CanCollide then colliders+=1; expect(part==volume,kind.."裝飾部件不參與碰撞") end
   end
   expect(colliders==1,kind.."恰有一個實體碰撞部件")
   local moved=location+Vector3.new(5,0,9)
   unit:PivotTo(CFrame.new(moved+Vector3.new(0,2.5,0))*CFrame.Angles(0,1.3,0))
   expect((volume.Position-(moved+Vector3.new(0,profile.height/2,0))).Magnitude<0.001,kind.."移動轉向時體積跟隨Root")
   expect(math.abs(math.abs(volume.CFrame.RightVector.Y)-1)<0.001,kind.."轉向後圓柱仍垂直")
   local ray=RaycastParams.new()
   ray.FilterType=Enum.RaycastFilterType.Include
   ray.FilterDescendantsInstances={volume}
   local hit=workspace:Raycast(volume.Position+Vector3.new(0,profile.height+2,0),Vector3.new(0,-profile.height*2-4,0),ray)
   expect(hit and hit.Instance==volume and math.abs(hit.Position.Y-(Config.Map.GroundY+profile.height))<0.03,kind.."引擎射線命中正確碰撞頂面")
  end
  expect(count>0,"所有設定單位均已驗證碰撞體積")
 end,debug.traceback)
 for _,value in ipairs(outputs) do value:Destroy() end
 unitWorld:Destroy()
 private:Destroy()
 if not ok then error("[FACTORY_FIXTURE FAIL] "..tostring(failure),0) end
 print(string.format("[FACTORY_FIXTURE COMPLETE] %d項引擎fixture檢查；私有fixture已清除，非使用者真模板驗收",checks))
 return checks
end
return Tests
