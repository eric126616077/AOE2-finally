local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art=require(ReplicatedStorage.Shared.Art)
local Config=require(ReplicatedStorage.GameData.GameConfig)
local Factory = {}
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
 local visualX,visualZ=size.X,size.Z
 if category=="Resource" then
  local visualWidths=Config.Map.ResourceVisualFootprints
  local width=visualWidths and visualWidths[kind]
  if type(width)=="number" and width>0 and width<math.huge then
   visualX,visualZ=width,width
  end
 end
 -- Canopies may meet while the shared gameplay footprint leaves walking room.
 -- Fit only the cloned / generated geometry; keep its original proportions.
 model:ScaleTo(model:GetScale()*math.min(visualX/bounds.X,size.Y/bounds.Y,visualZ/bounds.Z))
 local box,fitted=model:GetBoundingBox()
 local desired=CFrame.new(position+Vector3.new(0,fitted.Y/2,0))
 model:PivotTo(desired*box:Inverse()*model:GetPivot())
 if category=="Buildings" and Art.ApplyPlayerColor(model,team)==0 then
  Art.AddPlayerMarker(model,team)
 end
 model.Name=kind
 if category=="Resource" then
  -- Resource visuals never participate in queries; the footprint below is
  -- their one gameplay collider. Change only the generated copy / fallback.
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
 local footprint=Instance.new("Part")
 footprint.Name,footprint.Size,footprint.CFrame="Footprint",size,CFrame.new(position+Vector3.new(0,size.Y/2,0))
 footprint.Anchored,footprint.CanCollide,footprint.CanQuery,footprint.CanTouch=true,true,true,false
 if category=="Resource" then footprint.CastShadow=false end
 footprint.Transparency=1
 footprint.Parent=model
 model.PrimaryPart=footprint
 model:SetAttribute("Radius",math.max(size.X,size.Z)/2)
 return model
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
