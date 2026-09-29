local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local Config=require(RS.GameData.GameConfig)
local Grid=require(RS.Shared.Grid)
local Controller={kind=nil,position=nil,valid=false}
local preview
function Controller:Cancel()
 self.kind,self.position,self.valid=nil,nil,false
 if preview then preview:Destroy(); preview=nil end
end
function Controller:Begin(kind)
 self:Cancel()
 self.kind=kind
 local data=Config.Buildings[kind]
 preview=Instance.new("Part")
 preview.Name="BuildingPreview"
 preview.Anchored,preview.CanCollide,preview.CanQuery,preview.CanTouch=true,false,false,false
 preview.Size=Vector3.new(data.size.X*Config.Map.GridSize,data.height,data.size.Y*Config.Map.GridSize)
 preview.Material=Enum.Material.SmoothPlastic
 preview.Transparency=0.65
 local outline=Instance.new("SelectionBox")
 outline.Name="Outline"
 outline.Adornee=preview
 outline.LineThickness=0.06
 outline.SurfaceTransparency=1
 outline.Parent=preview
 preview.Parent=workspace
end
function Controller:Update(worldPosition)
 if not preview then return end
 self.position=nil
 self.valid=false
 if not worldPosition then preview.Transparency=1; preview.Outline.Visible=false; return end
 local data=Config.Buildings[self.kind]
 local pos=Grid.snap(worldPosition,data.size)
 preview.Transparency=0.65
 preview.Outline.Visible=true
 preview.Position=pos+Vector3.new(0,data.height/2,0)
 self.position=pos
 local params=OverlapParams.new()
 params.FilterType=Enum.RaycastFilterType.Include
 local folders={}
 for _,name in ipairs({"Buildings","Resources","Units"}) do
  local f=workspace:FindFirstChild(name)
  if f then table.insert(folders,f) end
 end
 params.FilterDescendantsInstances=folders
 local nearby=false
 local units=workspace:FindFirstChild("Units")
 if units then
  for _,unit in ipairs(units:GetChildren()) do
   if unit:GetAttribute("OwnerId")==Players.LocalPlayer.UserId and unit:GetAttribute("UnitType")=="villager" then
    local p=unit:GetPivot().Position
    if (Vector3.new(p.X,0,p.Z)-pos).Magnitude<=80 then nearby=true; break end
   end
  end
 end
 local affordable=true
 for key,cost in pairs(data.cost) do if (Players.LocalPlayer:GetAttribute(key) or 0)<cost then affordable=false end end
 self.valid=nearby and affordable and Grid.inBounds(pos,data.size) and #workspace:GetPartBoundsInBox(preview.CFrame,preview.Size-Vector3.new(0.2,0,0.2),params)==0
 preview.Color=self.valid and Color3.fromRGB(91,218,139) or Color3.fromRGB(231,97,88)
 preview.Outline.Color3=preview.Color
end
return Controller
