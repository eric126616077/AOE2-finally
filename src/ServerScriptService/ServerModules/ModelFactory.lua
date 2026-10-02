local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art=require(ReplicatedStorage.Shared.Art)
local Config=require(ReplicatedStorage.GameData.GameConfig)
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
function Factory.model(kind, position, size, color, category, team)
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
 -- Fit only the cloned / generated geometry; keep its original proportions.
 model:ScaleTo(model:GetScale()*math.min(visualX/bounds.X,size.Y/bounds.Y,visualZ/bounds.Z))
 local box,fitted=model:GetBoundingBox()
 local desired=CFrame.new(position+Vector3.new(0,fitted.Y/2,0))
 model:PivotTo(desired*box:Inverse()*model:GetPivot())
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
-- Workers and fighters turn toward what they are acting on; the Root keeps its position.
function Factory.face(unit,point)
 local pivot=unit:GetPivot()
 local dx,dz=point.X-pivot.Position.X,point.Z-pivot.Position.Z
 local length=math.sqrt(dx*dx+dz*dz)
 if length<0.05 then return false end
 local look=pivot.LookVector
 if (look.X*dx+look.Z*dz)/length>0.999 then return false end
 unit:PivotTo(CFrame.lookAt(pivot.Position,pivot.Position+Vector3.new(dx,0,dz)))
 return true
end
local workTools={wood="axe",gold="pick",stone="pick",build="hammer",repair="hammer"}
function Factory.workTool(unit,workKind,target)
 if unit:GetAttribute("UnitType")~="villager" then return false end
 local tool=workKind=="food" and (target:GetAttribute("BuildingType") and "hoe" or "basket") or workTools[workKind]
 return tool~=nil and Art.SetTool(unit,tool)
end
function Factory.watchCarry(unit)
 unit:GetAttributeChangedSignal("Carrying"):Connect(function()
  Art.SetCarry(unit,(unit:GetAttribute("Carrying") or 0)>0 and unit:GetAttribute("CarryType") or nil)
 end)
end
function Factory.unit(kind,position,data,owner)
 local team=owner:GetAttribute("TeamColor")
 local ownerId=owner:IsA("Player") and owner.UserId or owner:GetAttribute("UserId")
 local ownerName=owner:IsA("Player") and owner.DisplayName or owner:GetAttribute("DisplayName") or owner.Name
 local model=Art.Create(kind,team)
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
