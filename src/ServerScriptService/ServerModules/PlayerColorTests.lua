-- Explicit Studio SERVER test. Requiring this module never changes the match.
-- Fresh Play server Command Bar:
-- require(game.ServerScriptService.ServerModules.PlayerColorTests).Run({keepDisplay=true})
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local Art=require(ReplicatedStorage.Shared.Art)
local Config=require(ReplicatedStorage.GameData.GameConfig)
local Factory=require(script.Parent.ModelFactory)
local Tests={}
local colors={
 {name="紅色",value=Color3.fromRGB(220,74,65)},
 {name="藍色",value=Color3.fromRGB(81,158,199)},
 {name="綠色",value=Color3.fromRGB(92,175,103)},
 {name="黃色",value=Color3.fromRGB(232,191,64)},
}
local function assertContext()
 assert(RunService:IsStudio() and RunService:IsServer() and RunService:IsRunning(),"僅限新的 Studio SERVER Play 明確呼叫")
end
local function colorMatches(model,color)
 local marked=0
 for _,item in ipairs(model:GetDescendants()) do
  if item:IsA("BasePart") and item.Transparency<1 and item:GetAttribute("TeamColorPart")==true then
   marked+=1
   if item.Color~=color then return false,item:GetFullName().." 陣營飾邊顏色不符" end
  end
 end
 return marked>0,"須有至少一個已標記的可見陣營部件"
end
local function naturalMatches(model,reference)
 local parts,referenceParts=model:GetDescendants(),reference:GetDescendants()
 if #parts~=#referenceParts then return false end
 local natural=0
 for index,item in ipairs(parts) do
  local other=referenceParts[index]
  if item:IsA("BasePart") and item.Transparency<1 and item:GetAttribute("TeamColorPart")~=true then
   natural+=1
   if item.Name~=other.Name or item.Color~=other.Color then return false end
  end
 end
 return natural>0
end
local function snapshot(root)
 local values={}
 for _,item in ipairs({root,table.unpack(root:GetDescendants())}) do
  local value={object=item,Parent=item.Parent,Name=item.Name,Archivable=item.Archivable,TeamColorPartMarker=item:GetAttribute("TeamColorPart")}
  if item:IsA("BasePart") then
   value.Size,value.CFrame,value.Color=item.Size,item.CFrame,item.Color
   value.Anchored,value.CanCollide,value.CanTouch,value.CanQuery=item.Anchored,item.CanCollide,item.CanTouch,item.CanQuery
   value.Transparency,value.Material=item.Transparency,item.Material
   if item:IsA("MeshPart") then value.TextureID=item.TextureID end
  elseif item:IsA("SpecialMesh") then value.TextureId=item.TextureId
  elseif item:IsA("Decal") or item:IsA("Texture") then value.Texture=item.Texture end
  if item:IsA("Model") then value.PrimaryPart=item.PrimaryPart end
  table.insert(values,value)
 end
 return values
end
local function isUnchanged(root,values,accentMayChange)
 if #root:GetDescendants()~=#values-1 then return false end
 for _,value in ipairs(values) do
  local item=value.object
  for name,before in pairs(value) do
   if name~="object" and name~="TeamColorPartMarker" and not (accentMayChange and name=="Color" and value.TeamColorPartMarker==true) then
    if item[name]~=before then return false end
   end
  end
  if item:GetAttribute("TeamColorPart")~=value.TeamColorPartMarker then return false end
 end
 return true
end
local function fixture(name,withBanner)
 local source=Instance.new("Model")
 source.Name=name
 local roof=Instance.new("Part")
 roof.Name,roof.Color="固定藍色屋頂",colors[2].value
 roof.Size,roof.CFrame=Vector3.new(12,6,10),CFrame.new(0,3,0)
 roof.Anchored,roof.CanCollide,roof.CanTouch,roof.CanQuery=false,true,true,true
 roof.Parent=source
 source.PrimaryPart=roof
 local special=Instance.new("SpecialMesh")
 special.Name,special.TextureId="固定色網格","rbxassetid://1"
 special.Parent=roof
 local mesh=Instance.new("MeshPart")
 mesh.Name,mesh.TextureID="固定色MeshPart","rbxassetid://1"
 mesh.Size,mesh.CFrame,mesh.Color=Vector3.new(3,3,3),CFrame.new(0,8,0),colors[2].value
 mesh.Parent=source
 local surface=Instance.new("SurfaceAppearance")
 surface.Name="固定色SurfaceAppearance"
 surface.Parent=mesh
 for _,class in ipairs({"Decal","Texture"}) do
  local overlay=Instance.new(class)
  overlay.Name,overlay.Texture="固定色"..class,"rbxassetid://1"
  overlay.Parent=roof
 end
 local hidden=Instance.new("Part")
 hidden.Name,hidden.Transparency="HiddenCollider",1
 hidden.Size,hidden.CFrame=Vector3.new(14,12,14),CFrame.new(0,6,0)
 hidden.Anchored,hidden.CanCollide,hidden.CanTouch,hidden.CanQuery=true,true,false,true
 hidden.Parent=source
 if withBanner~=false then
  local flag=Instance.new("Part")
  flag.Name,flag.Size,flag.CFrame,flag.Color="Banner",Vector3.new(3,2,.2),CFrame.new(3,8,0),colors[2].value
  flag:SetAttribute("TeamColorPart",true)
  flag.Parent=source
 end
 return source
end
local function appearancePreserved(model)
 local roof=model:FindFirstChild("固定藍色屋頂",true)
 local mesh=model:FindFirstChild("固定色MeshPart",true)
 local special=model:FindFirstChild("固定色網格",true)
 local decal=model:FindFirstChild("固定色Decal",true)
 local texture=model:FindFirstChild("固定色Texture",true)
 local surface=model:FindFirstChild("固定色SurfaceAppearance",true)
 return roof and roof.Color==colors[2].value and mesh and mesh.Color==colors[2].value and mesh.TextureID=="rbxassetid://1"
  and special and special.TextureId=="rbxassetid://1" and decal and decal.Texture=="rbxassetid://1"
  and texture and texture.Texture=="rbxassetid://1" and surface and surface:IsA("SurfaceAppearance")
end
local function accentsInside(model,box,size)
 local half=size/2
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and part.Transparency<1 and part:GetAttribute("TeamColorPart")==true then
   for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
    local point=box:PointToObjectSpace(part.CFrame:PointToWorldSpace(part.Size*Vector3.new(x,y,z)/2))
    -- A shallow flag hangs in front of the facade so the wall cannot hide it.
    if math.abs(point.X)>half.X+.001 or math.abs(point.Y)>half.Y+.001 or math.abs(point.Z)>half.Z+.2 then return false end
   end end end
  end
 end
 return true
end
function Tests.MakeDisplay()
 assertContext()
 local folder=Instance.new("Folder")
 folder.Name="RTSPlayerColorDisplay_"..HttpService:GenerateGUID(false)
 folder:SetAttribute("PlayerColorTestDisplay",true)
 local ok,failure=xpcall(function()
  -- Above the map, separate from gameplay folders and without gameplay colliders.
  local origin=Vector3.new(0,100,0)
  local kinds={"TownCenter","Castle","House","Barracks","villager","cavalry","infantry","archer","trebuchet"}
  for row=1,2 do
   local color=colors[row]
   for index,kind in ipairs(kinds) do
    local model=Art.Create(kind,color.value)
    model.Name=color.name.."_"..kind
    if index>4 then model:ScaleTo(2.6) end
    model:PivotTo(CFrame.new(origin+Vector3.new((index-(#kinds+1)/2)*56,0,(row-1)*100)))
    for _,part in ipairs(model:GetDescendants()) do
     if part:IsA("BasePart") then part.CanQuery=false; part.CanCollide=false; part.CanTouch=false end
    end
    model.Parent=folder
   end
  end
  folder.Parent=workspace
 end,debug.traceback)
 if not ok then folder:Destroy(); error(failure,0) end
 print("[玩家改色展示] 紅藍建築與部隊："..folder.Name.."；僅本次 Play，無遊戲所有權")
 return folder
end
function Tests.Run(options)
 assertContext()
 options=options or {}
 local checks=0
 local outputs={}
 local createdBuildings=false
 local buildings=ReplicatedStorage:FindFirstChild("Buildings")
 local source,unknownSource,display
 local function keep(model) table.insert(outputs,model); return model end
 local function expect(condition,message)
  assert(condition,"[玩家改色 FAIL] "..message)
  checks+=1
  print("[玩家改色 PASS] "..message)
 end
 local function expectColor(model,color,message)
  local matches,reason=colorMatches(model,color)
  expect(matches,message..(matches and "" or "："..reason))
 end
 local ok,failure=xpcall(function()
  local kinds={}
  for kind in pairs(Config.Buildings) do table.insert(kinds,kind) end
  for kind in pairs(Config.Units) do table.insert(kinds,kind) end
  if not Config.Units.monk then table.insert(kinds,"monk") end
  table.sort(kinds)
  local naturalReferences={}
  for _,kind in ipairs(kinds) do naturalReferences[kind]=keep(Art.Create(kind,colors[2].value)) end
  for _,color in ipairs(colors) do
   for _,kind in ipairs(kinds) do
    local model=keep(Art.Create(kind,color.value))
    expectColor(model,color.value,color.name.." "..kind.." 陣營部件使用玩家色")
    expect(naturalMatches(model,naturalReferences[kind]),kind.." 牆面、皮膚、武器、馬匹等自然部件不隨陣營改色")
    local before=snapshot(model)
    Art.ApplyPlayerColor(model,colors[1].value)
    expectColor(model,colors[1].value,kind.." 再次套用只更新陣營色")
    expect(isUnchanged(model,before,true),kind.." 改色保留自然色、貼圖、尺寸、位置、材質與碰撞旗標")
   end
   local owner=keep(Instance.new("Folder"))
   owner.Name="私有改色測試玩家"
   owner:SetAttribute("UserId",-999999)
   owner:SetAttribute("DisplayName",color.name.."測試玩家")
   owner:SetAttribute("TeamColor",color.value)
   for kind,data in pairs(Config.Units) do
    local unit=keep(Factory.unit(kind,Vector3.zero,data,owner))
    expectColor(unit,color.value,color.name.." "..kind.." 工廠部隊飾邊沿用擁有者色")
    expect(unit:GetAttribute("TeamColor")==color.value,kind.." 保留模型玩家色屬性")
    local root=unit.PrimaryPart
    expect(root and root.Name=="Root" and root.Transparency==1 and root.Anchored and not root.CanCollide and not root.CanQuery and not root.CanTouch,kind.." 透明Root旗標不受改色影響")
    local volume=unit:FindFirstChild("CollisionVolume")
    local profile=Config.UnitCollision.profiles[data.class] or Config.UnitCollision.default
    expect(volume and volume.Transparency==1 and volume.Anchored and volume.CanCollide and volume.CanQuery and not volume.CanTouch and volume.Size==Vector3.new(profile.height,profile.radius*2,profile.radius*2),kind.." 透明CollisionVolume尺寸與碰撞旗標保留")
    local before=snapshot(unit)
    Art.ApplyPlayerColor(unit,colors[1].value)
    expect(isUnchanged(unit,before,true),kind.." 再次改色不改動Root或CollisionVolume")
   end
  end
  for kind in pairs(Config.Resources) do
   local red=keep(Art.Create(kind,colors[1].value))
   local blue=keep(Art.Create(kind,colors[2].value))
   local redParts,blueParts=red:GetDescendants(),blue:GetDescendants()
   expect(#redParts==#blueParts,kind.." 中立資源幾何一致")
   for index,item in ipairs(redParts) do
    if item:IsA("BasePart") then expect(item.Color==blueParts[index].Color,kind.." 中立資源保留自然色") end
   end
  end
  if not buildings then
   buildings=Instance.new("Folder")
   buildings.Name="Buildings"
   buildings.Parent=ReplicatedStorage
   createdBuildings=true
  end
  source=fixture("RTSPlayerColorFixture_"..HttpService:GenerateGUID(false))
  source.Parent=buildings
  local original=snapshot(source)
  local direct=keep(source:Clone())
  local collider=direct:FindFirstChild("HiddenCollider")
  local colliderBefore=snapshot(collider)
  local directBefore=snapshot(direct)
  Art.ApplyPlayerColor(direct,colors[1].value)
  expectColor(direct,colors[1].value,"複製模板已標記旗幟改為紅色")
  expect(appearancePreserved(direct),"複製模板未知屋頂與Mesh貼圖、Decal、Texture、SurfaceAppearance完整保留")
  expect(isUnchanged(direct,directBefore,true),"直接套用僅改既有陣營部件，不新增旗幟或改自然幾何")
  expect(isUnchanged(collider,colliderBefore,true),"改色保留隱形碰撞部件")
  local whitelist=keep(source:Clone())
  whitelist.Banner:SetAttribute("TeamColorPart",nil)
  Art.ApplyPlayerColor(whitelist,colors[1].value)
  expectColor(whitelist,colors[1].value,"白名單Banner辨識為陣營旗幟並記錄標記")
  local position,size=Vector3.new(64,0,64),Vector3.new(16,14,16)
  for _,color in ipairs(colors) do
   local model=keep(Factory.model(source.Name,position,size,nil,"Buildings",color.value))
   expectColor(model,color.value,color.name.." 工廠複製建築旗幟使用陣營色")
   expect(appearancePreserved(model),color.name.." 工廠複製建築保留未知屋頂與所有貼圖")
   local footprint=model.PrimaryPart
   expect(footprint and footprint.Name=="Footprint" and footprint.Size==size and footprint.CFrame==CFrame.new(position+Vector3.new(0,size.Y/2,0)),"建築占地尺寸與位置保留")
   expect(footprint.Transparency==1 and footprint.Anchored and footprint.CanCollide and footprint.CanQuery and not footprint.CanTouch,"建築占地碰撞旗標保留")
  end
  expect(isUnchanged(source,original,false),"原模板幾何、原藍色與所有貼圖完整保留")
  unknownSource=fixture("RTSPlayerColorUnknownFixture_"..HttpService:GenerateGUID(false),false)
  unknownSource.Parent=buildings
  local unknownOriginal=snapshot(unknownSource)
  local unknownDirect=keep(unknownSource:Clone())
  local unknownBefore=snapshot(unknownDirect)
  Art.ApplyPlayerColor(unknownDirect,colors[1].value)
  expect(not colorMatches(unknownDirect,colors[1].value) and isUnchanged(unknownDirect,unknownBefore,false),"直接套用未知模板不亂染屋頂、不新增部件")
  local baseline=keep(Factory.model(unknownSource.Name,position,size,nil,"Buildings",nil))
  local baselineFootprint=baseline.PrimaryPart
  baselineFootprint.Parent=nil
  local visualBox,visualBounds=baseline:GetBoundingBox()
  baselineFootprint.Parent=baseline
  baseline.PrimaryPart=baselineFootprint
  for _,color in ipairs(colors) do
   local model=keep(Factory.model(unknownSource.Name,position,size,nil,"Buildings",color.value))
   expectColor(model,color.value,color.name.." 未標記進口建築補上小型陣營旗")
   expect(appearancePreserved(model),color.name.." 補旗後未知屋頂與貼圖仍保留")
   expect(accentsInside(model,visualBox,visualBounds),"新增小旗保留原擬合範圍，正面外掛厚度不超過0.2 studs")
   expect(model:GetScale()==baseline:GetScale(),"新增小旗不改原模型縮放")
   for _,part in ipairs(baseline:GetDescendants()) do
    if part:IsA("BasePart") then
     local other=model:FindFirstChild(part.Name,true)
     expect(other and other.Size==part.Size and other.CFrame==part.CFrame and other.Color==part.Color and other.Transparency==part.Transparency and other.CanCollide==part.CanCollide and other.CanQuery==part.CanQuery,"補旗保留原幾何與占地："..part.Name)
    end
   end
  end
  expect(isUnchanged(unknownSource,unknownOriginal,false),"未知原模板未增加旗幟，幾何與貼圖完整保留")
  if options.keepDisplay==true then display=Tests.MakeDisplay() end
 end,debug.traceback)
 for _,model in ipairs(outputs) do model:Destroy() end
 if source then source:Destroy() end
 if unknownSource then unknownSource:Destroy() end
 if createdBuildings and buildings and #buildings:GetChildren()==0 then buildings:Destroy() end
 if not ok then
  if display then display:Destroy() end
  error("[玩家改色 FAIL] "..tostring(failure),0)
 end
 print(string.format("[玩家改色 COMPLETE] %d 項引擎檢查通過；私有fixtures已清除",checks))
 return checks,display
end
return Tests
