-- Original, self-contained geometry for fallback models and HUD previews.
-- Builders live in ArtBuildingsA / ArtBuildingsB / ArtUnits / ArtNature and share ArtKit.
local K=require(script.Parent.ArtKit)
local Units=require(script.Parent.ArtUnits)
local builders={}
for _,group in ipairs({require(script.Parent.ArtBuildingsA),require(script.Parent.ArtBuildingsB),require(script.Parent.ArtNature),Units.builders}) do
 for kind,build in pairs(group) do builders[kind]=build end
end
local Art={ApplyPlayerColor=K.ApplyPlayerColor,AddPlayerMarker=K.AddPlayerMarker}
local toolKinds,carryKinds,villagerTool,carryLoad=Units.toolKinds,Units.carryKinds,Units.tool,Units.carry
-- Placed units carry a Root 2.5 studs above the art origin (ModelFactory.unit); previews have none.
local function place(model,parts)
 local root=model.PrimaryPart
 local origin=root and root.CFrame*CFrame.new(0,-2.5,0) or CFrame.identity
 for _,part in ipairs(parts) do
  part.CFrame=origin*part.CFrame
  part.CanCollide,part.CanTouch=false,false
 end
end
function Art.SetTool(model,tool)
 if not toolKinds[tool] or model:GetAttribute("ToolKind")==tool then return false end
 for _,part in ipairs(model:GetChildren()) do
  if part.Name=="Tool" or part.Name=="ToolHead" then part:Destroy() end
 end
 place(model,villagerTool(model,tool))
 model:SetAttribute("ToolKind",tool)
 return true
end
function Art.SetCarry(model,kind)
 kind=carryKinds[kind] and kind or ""
 if (model:GetAttribute("CarryVisual") or "")==kind then return false end
 model:SetAttribute("CarryVisual",kind)
 if kind~="" and model:GetAttribute("CarryBuilt")~=kind then
  for _,part in ipairs(model:GetChildren()) do if part.Name=="Carry" then part:Destroy() end end
  place(model,carryLoad(model,kind))
  model:SetAttribute("CarryBuilt",kind)
 else
  -- Same goods as the last trip: keep the parts and only show / hide them.
  for _,part in ipairs(model:GetChildren()) do if part.Name=="Carry" then part.Transparency=kind=="" and 1 or 0 end end
 end
 return true
end
-- 0 full, 1 two thirds or less, 2 one third or less, 3 empty (fallow farm).
function Art.ResourceStage(amount,maximum)
 if type(amount)~="number" or type(maximum)~="number" or amount~=amount or maximum~=maximum or maximum<=0 then return 0 end
 local ratio=amount/maximum
 return ratio<=0 and 3 or ratio<=1/3 and 2 or ratio<=2/3 and 1 or 0
end
function Art.Create(kind,team,applyPlayerColor,stage)
 team=typeof(team)=="Color3" and team or Color3.fromRGB(81,158,199)
 stage=type(stage)=="number" and math.clamp(math.floor(stage),0,3) or 0
 local model=Instance.new("Model")
 model.Name=kind
 model:SetAttribute("OriginalArt",true)
 local build=builders[kind]
 if build then build(model,kind,team,stage) end
 if applyPlayerColor~=false and (K.buildingKinds[kind] or K.unitKinds[kind]) then Art.ApplyPlayerColor(model,team) end
 return model
end
return Art
