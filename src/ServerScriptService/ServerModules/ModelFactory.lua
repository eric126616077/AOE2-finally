local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art=require(ReplicatedStorage.Shared.Art)
local Config=require(ReplicatedStorage.GameData.GameConfig)
local Remains=require(ReplicatedStorage.Shared.RemainsRules)
local Cosmetic=require(ReplicatedStorage.Shared.CosmeticArt)
local Factory = {}
-- Canopies may meet while the shared gameplay footprint leaves walking room.
local function visualFootprint(kind,size,category)
 if category=="Resource" then
  local visualWidths=Config.Map.ResourceVisualFootprints
  local width=visualWidths and visualWidths[kind]
  if type(width)=="number" and width>0 and width<math.huge then return width,width end
 end
 return size.X,size.Z
end
-- Resource visuals never participate in queries; the footprint is their one
-- gameplay collider. Only the largest projected part keeps a shadow.
local function resourceFlags(model)
 local shadow,largest=nil,-1
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") then
   part.CanQuery=false
   if part.CastShadow and part.Transparency<1 then
    -- Compare world XZ projected bounds after the model has been fitted.
    local size,frame=part.Size,part.CFrame
    local width=math.abs(frame.RightVector.X)*size.X+math.abs(frame.UpVector.X)*size.Y+math.abs(frame.LookVector.X)*size.Z
    local depth=math.abs(frame.RightVector.Z)*size.X+math.abs(frame.UpVector.Z)*size.Y+math.abs(frame.LookVector.Z)*size.Z
    local area=width*depth
    if area>largest then shadow,largest=part,area end
   end
   part.CastShadow=false
  end
 end
 if shadow then shadow.CastShadow=true end
end
-- size is the world footprint. quarterTurn fits the art (authored along X) to the swapped
-- footprint and turns only the art, so the Footprint part stays axis-aligned for every rule.
function Factory.model(kind, position, size, color, category, team, quarterTurn)
 local folder=ReplicatedStorage:FindFirstChild(category)
 local template=folder and folder:FindFirstChild(kind)
 if not template and category=="Buildings" then
  folder=ReplicatedStorage:FindFirstChild("Resource")
  template=folder and folder:FindFirstChild(kind)
 end
 local model
 if template and template:IsA("Model") and template:FindFirstChildWhichIsA("BasePart",true) then
  -- Clone can return nil for an unarchivable root, or omit every BasePart.
  -- Validate only the copy; the user's template and Archivable stay untouched.
  local ok,copy=pcall(function() return template:Clone() end)
  if ok and copy and copy:IsA("Model") and copy:FindFirstChildWhichIsA("BasePart",true) then
   model=copy
  elseif ok and copy then copy:Destroy() end
 end
 if model then
  for _,item in ipairs(model:GetDescendants()) do
   if item:IsA("BaseScript") then item:Destroy()
   elseif item:IsA("BasePart") then
    item.Anchored,item.CanCollide,item.CanTouch=true,false,false
    if item.Transparency>=1 then item.CanQuery=false end
   end
  end
 else model=Art.Create(kind,team) end
 local _,bounds=model:GetBoundingBox()
 local visualX,visualZ=visualFootprint(kind,size,category)
 if quarterTurn==true then visualX,visualZ=visualZ,visualX end
 -- Fit only the cloned / generated geometry; keep its original proportions.
 model:ScaleTo(model:GetScale()*math.min(visualX/bounds.X,size.Y/bounds.Y,visualZ/bounds.Z))
 local box,fitted=model:GetBoundingBox()
 local desired=CFrame.new(position+Vector3.new(0,fitted.Y/2,0))
 model:PivotTo(desired*box:Inverse()*model:GetPivot())
 if quarterTurn==true then
  model:PivotTo(CFrame.new(position)*CFrame.Angles(0,math.pi/2,0)*CFrame.new(-position)*model:GetPivot())
 end
 if category=="Buildings" and Art.ApplyPlayerColor(model,team)==0 then
  Art.AddPlayerMarker(model,team)
 end
 model.Name=kind
 -- Change only the generated copy / fallback, before the footprint exists.
 if category=="Resource" then resourceFlags(model) end
 local footprint=Instance.new("Part")
 footprint.Name,footprint.Size,footprint.CFrame="Footprint",size,CFrame.new(position+Vector3.new(0,size.Y/2,0))
 -- Walkable fields keep a queryable footprint for selection and placement, without blocking units.
 local data=category=="Buildings" and Config.Buildings[kind]
 footprint.Anchored,footprint.CanCollide,footprint.CanQuery,footprint.CanTouch=true,not (data and data.walkable==true),true,false
 if category=="Resource" then footprint.CastShadow=false end
 footprint.Transparency=1
 footprint.Parent=model
 model.PrimaryPart=footprint
 model:SetAttribute("Radius",math.max(size.X,size.Z)/2)
 return model
end
-- Where the full (stage 0) fallback art lands relative to the ground point, measured by
-- running the same fit as Factory.model once per kind. Later stages reuse that scale and
-- origin, so a thinned tree or mined rock stays exactly where the full one stood.
local artFits={}
local function artFit(kind,size,category)
 local fit=artFits[kind]
 if fit then return fit end
 local art=Art.Create(kind)
 local marker=art:FindFirstChildWhichIsA("BasePart")
 local authored=marker.CFrame
 local _,bounds=art:GetBoundingBox()
 local visualX,visualZ=visualFootprint(kind,size,category)
 local scale=math.min(visualX/bounds.X,size.Y/bounds.Y,visualZ/bounds.Z)
 art:ScaleTo(art:GetScale()*scale)
 local box,fitted=art:GetBoundingBox()
 art:PivotTo(CFrame.new(0,fitted.Y/2,0)*box:Inverse()*art:GetPivot())
 fit={scale=scale,frame=marker.CFrame*(CFrame.new(authored.Position*scale)*authored.Rotation):Inverse()}
 art:Destroy()
 artFits[kind]=fit
 return fit
end
-- Swap generated fallback geometry for a depletion stage. Imported Studio templates carry no
-- OriginalArt mark and keep the look their author gave them.
function Factory.restage(model,kind,category,stage)
 local footprint=model.PrimaryPart
 if not footprint or model:GetAttribute("OriginalArt")~=true or (model:GetAttribute("ResourceStage") or 0)==stage then return false end
 local size=footprint.Size
 local fit=artFit(kind,size,category)
 local frame=CFrame.new(footprint.Position-Vector3.new(0,size.Y/2,0))*fit.frame
 local art=Art.Create(kind,model:GetAttribute("TeamColor"),nil,stage)
 for _,part in ipairs(model:GetChildren()) do
  if part:IsA("BasePart") and part~=footprint then part:Destroy() end
 end
 local resource=category=="Resource"
 local shadow,largest=nil,-1
 for _,part in ipairs(art:GetChildren()) do
  if part:IsA("BasePart") then
   local authored=part.CFrame
   part.Size*=fit.scale
   part.CFrame=frame*CFrame.new(authored.Position*fit.scale)*authored.Rotation
   part.CanCollide,part.CanTouch=false,false
   if resource then
    -- Same budget as a fresh node: no queries, one shadow caster.
    part.CanQuery,part.CastShadow=false,false
    local area=part.Size.X*part.Size.Z
    if area>largest then shadow,largest=part,area end
   end
   part.Parent=model
  end
 end
 if shadow then shadow.CastShadow=true end
 art:Destroy()
 model:SetAttribute("ResourceStage",stage)
 return true
end
-- Natural nodes and completed farms show how much is left; an exhausted node is removed by the caller.
function Factory.refreshStage(model)
 if not model.Parent then return false end
 local building=model:GetAttribute("BuildingType")
 if building and model:GetAttribute("Complete")~=true then return false end
 local stage=Art.ResourceStage(model:GetAttribute("Amount"),model:GetAttribute("MaxAmount"))
 if stage>=3 and not building then return false end
 return Factory.restage(model,building or model.Name,building and "Buildings" or "Resource",stage)
end
function Factory.watchFarm(model)
 for _,attribute in ipairs({"Amount","MaxAmount","Complete"}) do
  -- Deferred: an emptied farm that is reseeded in the same step rebuilds nothing.
  model:GetAttributeChangedSignal(attribute):Connect(function() task.defer(Factory.refreshStage,model) end)
 end
end
-- 單位移動只搬 Root 與碰撞體積兩個零件；外觀零件由客戶端 UnitMotion 依 Root 推算。
-- 每個外觀零件記下相對 Root 的位置（RootOffset 屬性，客戶端優先使用），伺服器端只在
-- 停下、原地轉向與陣亡留屍時一次對齊。原本每步 PivotTo 整個多零件模型是大型戰鬥最大的單項成本，
-- 也讓每個零件每步都要複製給客戶端。
local appearance=setmetatable({},{__mode="k"})
local function appearanceParts(unit)
 local root=unit.PrimaryPart
 if not root then return nil end
 local entry=appearance[unit]
 if not entry or entry.root~=root then entry={root=root,parts={},stale=false}; appearance[unit]=entry end
 for _,part in ipairs(unit:GetDescendants()) do
  if part:IsA("BasePart") and part~=root then
   if part.Name=="CollisionVolume" then
    if entry.volume~=part then entry.volume,entry.volumeOffset=part,root.CFrame:ToObjectSpace(part.CFrame) end
   elseif entry.parts[part]==nil then
    -- 新零件（工具、攜帶物）由 Art 依目前 Root 擺放，此刻記錄的相對位置一定正確。
    local offset=root.CFrame:ToObjectSpace(part.CFrame)
    entry.parts[part]=offset
    part:SetAttribute("RootOffset",offset)
   end
  end
 end
 return entry
end
Factory.trackAppearance=appearanceParts
function Factory.syncAppearance(unit)
 local entry=appearance[unit]
 if not entry or not entry.stale or entry.root~=unit.PrimaryPart or not entry.root.Parent then return false end
 local frame=entry.root.CFrame
 local parts,frames={},{}
 for part,offset in pairs(entry.parts) do
  if part:IsDescendantOf(unit) then table.insert(parts,part); table.insert(frames,frame*offset)
  else entry.parts[part]=nil end
 end
 if #parts>0 then workspace:BulkMoveTo(parts,frames,Enum.BulkMoveMode.FireCFrameChanged) end
 entry.stale=false
 return true
end
function Factory.moveUnit(unit,frame)
 local entry=appearance[unit]
 if not entry or entry.root~=unit.PrimaryPart or not entry.volume or entry.volume.Parent~=unit then entry=appearanceParts(unit) end
 if not entry or not entry.volume then unit:PivotTo(frame); return end
 workspace:BulkMoveTo({entry.root,entry.volume},{frame,frame*entry.volumeOffset},Enum.BulkMoveMode.FireCFrameChanged)
 entry.stale=true
end
-- Workers and fighters turn toward what they are acting on; the Root keeps its position.
function Factory.face(unit,point)
 local pivot=unit:GetPivot()
 local dx,dz=point.X-pivot.Position.X,point.Z-pivot.Position.Z
 local length=math.sqrt(dx*dx+dz*dz)
 local look=pivot.LookVector
 if length>=0.05 and (look.X*dx+look.Z*dz)/length<=0.999 then
  Factory.moveUnit(unit,CFrame.lookAt(pivot.Position,pivot.Position+Vector3.new(dx,0,dz)))
  Factory.syncAppearance(unit)
  return true
 end
 -- 走到定點後站著工作／攻擊：外觀零件在伺服器端對齊一次。
 Factory.syncAppearance(unit)
 return false
end
local workTools={wood="axe",gold="pick",stone="pick",build="hammer",repair="hammer"}
function Factory.workTool(unit,workKind,target)
 if unit:GetAttribute("UnitType")~="villager" then return false end
 -- 打獵用狩獵矛，耕田用鋤頭，採漿果用籃子。
 local tool=workKind=="food" and (target:GetAttribute("BuildingType") and "hoe" or target:GetAttribute("Hunt") and "spear" or "basket") or workTools[workKind]
 local changed=tool~=nil and Art.SetTool(unit,tool)
 if changed then appearanceParts(unit) end
 return changed
end
-- 僧侶背著聖物、貿易車載著貨箱；只是外觀，數量由伺服器屬性決定。
local function carry(unit,kind)
 local changed=Art.SetCarry(unit,kind)
 if changed then appearanceParts(unit) end
 return changed
end
function Factory.relicCarry(unit,on) return carry(unit,on and "relic" or nil) end
function Factory.tradeCargo(unit,on) return carry(unit,on and "trade" or nil) end
function Factory.watchCarry(unit)
 unit:GetAttributeChangedSignal("Carrying"):Connect(function()
  carry(unit,(unit:GetAttribute("Carrying") or 0)>0 and unit:GetAttribute("CarryType") or nil)
 end)
end
-- Fallen units stay on the field as remains: people lie on their back, mounts on their side,
-- siege engines slump as wrecks. Remains are anchored copies of the appearance parts only, so
-- they never block movement, placement, selection or line-of-attack queries.
local corpseFolder
local corpseQueue={}
local corpseLay={
 siege=CFrame.new(0,-.35,0)*CFrame.Angles(0,0,.22),
 trade=CFrame.new(0,-.35,0)*CFrame.Angles(0,0,.22),
 cavalry=CFrame.new(0,1.4,0)*CFrame.Angles(0,0,math.pi/2),
 default=CFrame.new(0,.75,-2.2)*CFrame.Angles(math.pi/2,0,0),
}
local ashen=Color3.fromRGB(96,88,80)
function Factory.corpse(unit,seconds,limit)
 Factory.syncAppearance(unit)
 local root=unit.PrimaryPart
 if not root or type(seconds)~="number" or seconds<=0 or type(limit)~="number" or limit<1 then return nil end
 local ground=root.Position-Vector3.new(0,2.5,0)
 local look=root.CFrame.LookVector
 local flat=Vector3.new(look.X,0,look.Z)
 local base=flat.Magnitude>.01 and CFrame.lookAt(ground,ground+flat) or CFrame.new(ground)
 local lay=corpseLay[unit:GetAttribute("UnitClass")] or corpseLay.default
 local frame=base*lay
 local corpse=Instance.new("Model")
 corpse.Name="Corpse"
 for _,part in ipairs(unit:GetDescendants()) do
  if part:IsA("BasePart") and part~=root and part.Name~="CollisionVolume" and part.Transparency<1 then
   local ok,copy=pcall(function() return part:Clone() end)
   if ok and copy then
    for _,child in ipairs(copy:GetDescendants()) do
     if child:IsA("BasePart") or child:IsA("BaseScript") or child:IsA("BillboardGui") then child:Destroy() end
    end
    copy.Anchored,copy.CanCollide,copy.CanQuery,copy.CanTouch,copy.CastShadow=true,false,false,false,false
    copy.Color=copy.Color:Lerp(ashen,.35)
    copy.CFrame=frame*base:ToObjectSpace(part.CFrame)
    copy.Parent=corpse
   end
  end
 end
 if not corpse:FindFirstChildWhichIsA("BasePart") then corpse:Destroy(); return nil end
 corpse:SetAttribute("UnitType",unit:GetAttribute("UnitType"))
 -- 客戶端 Remains 用這三項播放倒地與淡出；屍體本身已在最終位置，缺少時照舊靜止顯示。
 corpse:SetAttribute("CorpseBase",base)
 corpse:SetAttribute("CorpseLay",lay)
 corpse:SetAttribute("CorpseExpires",workspace:GetServerTimeNow()+seconds)
 if not corpseFolder or not corpseFolder.Parent then
  corpseFolder=workspace:FindFirstChild("Corpses")
  if not corpseFolder then
   corpseFolder=Instance.new("Folder")
   corpseFolder.Name="Corpses"
   corpseFolder.Parent=workspace
  end
 end
 corpse.Parent=corpseFolder
 game:GetService("Debris"):AddItem(corpse,seconds)
 -- Drop entries that already expired, then the oldest ones beyond the cap.
 for index=#corpseQueue,1,-1 do if not corpseQueue[index].Parent then table.remove(corpseQueue,index) end end
 table.insert(corpseQueue,corpse)
 while #corpseQueue>limit do table.remove(corpseQueue,1):Destroy() end
 return corpse
end
-- 被摧毀的建築與採完的資源留下短暫的外觀複本（Ruins），由客戶端 Remains 播放倒塌／倒下／淡出。
-- 原模型仍照常立即移除，複本不碰撞、不可點選、不參與查詢；伺服器在 seconds 後刪除。
-- 客戶端無法在延遲訊號中複製已被移除的模型，所以複本必須由伺服器建立。
local ruinFolder
local ruinQueue={}
local keepInRuin={Decal=true,Texture=true,SpecialMesh=true,SurfaceAppearance=true}
local function ruin(model,kind,seconds,limit,maxParts)
 if typeof(model)~="Instance" or not model:IsA("Model") or type(seconds)~="number" or seconds<=0 then return nil end
 local ok,frame,size=pcall(function() return model:GetBoundingBox() end)
 if not ok then return nil end
 local candidates={}
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and part~=model.PrimaryPart and part.Name~="CollisionVolume" and part.Name~="Footprint" and part.Transparency<1 then
   table.insert(candidates,part)
  end
 end
 -- 超過上限時只保留最大的零件：倒塌中的小裝飾消失不明顯，大塊牆面才是輪廓。
 if type(maxParts)=="number" and #candidates>maxParts then
  table.sort(candidates,function(a,b) return a.Size.X*a.Size.Y*a.Size.Z>b.Size.X*b.Size.Y*b.Size.Z end)
  for index=#candidates,maxParts+1,-1 do candidates[index]=nil end
 end
 local ruin=Instance.new("Model")
 ruin.Name="Ruin"
 for _,part in ipairs(candidates) do
  local copied,copy=pcall(function() return part:Clone() end)
  if copied and copy then
   for _,child in ipairs(copy:GetDescendants()) do
    if not keepInRuin[child.ClassName] then child:Destroy() end
   end
   copy.Anchored,copy.CanCollide,copy.CanQuery,copy.CanTouch=true,false,false,false
   if kind=="building" then copy.Color=copy.Color:Lerp(ashen,.3) end
   copy.CFrame=part.CFrame
   copy.Parent=ruin
  end
 end
 if not ruin:FindFirstChildWhichIsA("BasePart") then ruin:Destroy(); return nil end
 ruin:SetAttribute("RuinKind",kind)
 ruin:SetAttribute("RuinStart",workspace:GetServerTimeNow())
 ruin:SetAttribute("RuinSeconds",seconds)
 ruin:SetAttribute("RuinGround",frame.Position-Vector3.new(0,size.Y/2,0))
 ruin:SetAttribute("RuinHeight",size.Y)
 ruin:SetAttribute("RuinRadius",math.max(size.X,size.Z)/2)
 if not ruinFolder or not ruinFolder.Parent then
  ruinFolder=workspace:FindFirstChild("Ruins")
  if not ruinFolder then
   ruinFolder=Instance.new("Folder")
   ruinFolder.Name="Ruins"
   ruinFolder.Parent=workspace
  end
 end
 ruin.Parent=ruinFolder
 -- 稍晚於動畫結束才刪除，網路延遲時客戶端仍能播完淡出。
 game:GetService("Debris"):AddItem(ruin,seconds+.5)
 for index=#ruinQueue,1,-1 do if not ruinQueue[index].Parent then table.remove(ruinQueue,index) end end
 table.insert(ruinQueue,ruin)
 while type(limit)=="number" and #ruinQueue>limit do table.remove(ruinQueue,1):Destroy() end
 return ruin
end
-- 只有完工建築留下倒塌複本；工地的鷹架與未顯現零件屬於客戶端外觀，照舊直接消失。
function Factory.ruinBuilding(model)
 if model:GetAttribute("Complete")~=true then return nil end
 return ruin(model,"building",Remains.CollapseSeconds,Remains.MaxRuins,Remains.MaxCollapseParts)
end
function Factory.ruinResource(model)
 local tree=model:GetAttribute("ResourceType")=="wood"
 return ruin(model,tree and "tree" or "resource",tree and Remains.TreeFallSeconds or Remains.ResourceFadeSeconds,Remains.MaxRuins,Remains.MaxCollapseParts)
end
function Factory.clearCorpses()
 for _,corpse in ipairs(corpseQueue) do corpse:Destroy() end
 table.clear(corpseQueue)
 for _,ruin in ipairs(ruinQueue) do ruin:Destroy() end
 table.clear(ruinQueue)
end
-- 新單位（訓練完成、離開駐軍）記錄從哪個建築邊緣走出來；客戶端 UnitMotion 只用它播放出場，
-- 伺服器的位置、碰撞與指令從生成那一刻起就在出生點，不受影響。
function Factory.markSpawn(unit,building)
 local root=unit and unit.PrimaryPart
 local footprint=building and building.PrimaryPart
 if not root or not footprint then return false end
 local center=footprint.Position
 local flat=Vector3.new(root.Position.X-center.X,0,root.Position.Z-center.Z)
 if flat.Magnitude<.5 then return false end
 local direction=flat.Unit
 -- 沿方向到占地邊緣的距離（占地可能旋轉），再往內一點，看起來是從門內走出。
 local along=footprint.CFrame:VectorToObjectSpace(direction)
 local half=footprint.Size/2
 local toX=math.abs(along.X)>1e-3 and half.X/math.abs(along.X) or math.huge
 local toZ=math.abs(along.Z)>1e-3 and half.Z/math.abs(along.Z) or math.huge
 local edge=math.max(0,math.min(toX,toZ,flat.Magnitude)-1)
 local from=center+direction*edge
 unit:SetAttribute("SpawnFrom",Vector3.new(from.X,root.Position.Y,from.Z))
 unit:SetAttribute("SpawnAt",workspace:GetServerTimeNow())
 return true
end
function Factory.unit(kind,position,data,owner)
 local team=owner:GetAttribute("TeamColor")
 local ownerId=owner:IsA("Player") and owner.UserId or owner:GetAttribute("UserId")
 local ownerName=owner:IsA("Player") and owner.DisplayName or owner:GetAttribute("DisplayName") or owner.Name
 local model=Art.Create(kind,team)
 -- 部隊塗裝只換非隊伍色零件的配色；電腦玩家沒有外觀屬性，維持預設。
 Cosmetic.SkinUnit(model,owner:GetAttribute("CosmeticUnitSkin"))
 model.Name=data.name
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") then part.CanCollide,part.CanTouch=false,false end
 end
 local root=Instance.new("Part")
 local siege=data.class=="siege"
 local mounted=data.class=="cavalry"
 root.Name,root.Size,root.Position="Root",siege and Vector3.new(6,5,8) or (mounted and Vector3.new(4,7,7) or Vector3.new(3,5,3)),Vector3.new(0,2.5,0)
 root.Transparency=1
 root.Anchored,root.CanCollide,root.CanTouch,root.CanQuery=true,false,false,false
 root.Parent=model
 model.PrimaryPart=root
 local profile=Config.UnitCollision.profiles[data.class] or Config.UnitCollision.default
 local volume=Instance.new("Part")
 volume.Name,volume.Shape="CollisionVolume",Enum.PartType.Cylinder
 -- A Roblox cylinder extends along local X; rotate that axis vertically.
 volume.Size=Vector3.new(profile.height,profile.radius*2,profile.radius*2)
 volume.CFrame=CFrame.new(0,profile.height/2,0)*CFrame.Angles(0,0,math.pi/2)
 volume.Transparency=1
 volume.Anchored,volume.CanCollide,volume.CanQuery,volume.CanTouch=true,true,true,false
 volume.CastShadow=false
 local modifier=Instance.new("PathfindingModifier")
 modifier.PassThrough=true -- Moving units are handled by server collision, not the static navmesh.
 modifier.Parent=volume
 volume.Parent=model
 model:PivotTo(CFrame.new(position+Vector3.new(0,2.5,0)))
 appearanceParts(model)
 model:SetAttribute("UnitType",kind)
 model:SetAttribute("DisplayName",data.name)
 model:SetAttribute("HP",data.hp)
 model:SetAttribute("MaxHP",data.hp)
 model:SetAttribute("OwnerId",ownerId)
 model:SetAttribute("OwnerName",ownerName)
 model:SetAttribute("Team",owner:GetAttribute("Team"))
 model:SetAttribute("TeamId",owner:GetAttribute("TeamId"))
 model:SetAttribute("UnitClass",data.class)
 model:SetAttribute("Radius",profile.radius)
 model:SetAttribute("CollisionHeight",profile.height)
 model:SetAttribute("Order","待命")
 return model
end
return Factory
