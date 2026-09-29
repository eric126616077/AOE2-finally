local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art=require(ReplicatedStorage.Shared.Art)
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
  model=template:Clone()
  for _,item in ipairs(model:GetDescendants()) do
   if item:IsA("BaseScript") then item:Destroy()
   elseif item:IsA("BasePart") then
    item.Anchored,item.CanCollide,item.CanTouch=true,false,false
    if item.Transparency>=1 then item.CanQuery=false end
   end
  end
 else model=Art.Create(kind,team) end
 local _,bounds=model:GetBoundingBox()
 model:ScaleTo(model:GetScale()*math.min(size.X/bounds.X,size.Y/bounds.Y,size.Z/bounds.Z))
 local box,fitted=model:GetBoundingBox()
 local desired=CFrame.new(position+Vector3.new(0,fitted.Y/2,0))
 model:PivotTo(desired*box:Inverse()*model:GetPivot())
 model.Name=kind
 local footprint=Instance.new("Part")
 footprint.Name,footprint.Size,footprint.CFrame="Footprint",size,CFrame.new(position+Vector3.new(0,size.Y/2,0))
 footprint.Anchored,footprint.CanCollide,footprint.CanQuery,footprint.CanTouch=true,true,true,false
 footprint.Transparency=1
 footprint.Parent=model
 model.PrimaryPart=footprint
 model:SetAttribute("Radius",math.max(size.X,size.Z)/2)
 return model
end
function Factory.unit(kind,position,data,owner)
 local team=owner:GetAttribute("TeamColor")
 local model=Art.Create(kind,team)
 model.Name=data.name
 local root=Instance.new("Part")
 root.Name,root.Size,root.Position="Root",Vector3.new(3,5,3),Vector3.new(0,2.5,0)
 root.Transparency=1
 root.Anchored,root.CanCollide,root.CanTouch,root.CanQuery=true,false,false,false
 root.Parent=model
 model.PrimaryPart=root
 model:PivotTo(CFrame.new(position+Vector3.new(0,2.5,0)))
 model:SetAttribute("UnitType",kind)
 model:SetAttribute("DisplayName",data.name)
 model:SetAttribute("HP",data.hp)
 model:SetAttribute("MaxHP",data.hp)
 model:SetAttribute("OwnerId",owner.UserId)
 model:SetAttribute("OwnerName",owner.DisplayName)
 model:SetAttribute("Radius",2)
 model:SetAttribute("Order","待命")
 return model
end
return Factory
