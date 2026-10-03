-- 外觀套用：只改顏色、材質與純裝飾特效。不改零件大小、透明度、碰撞或隊伍色零件，
-- 所以單位與建築的外形、選取範圍與敵我辨識都和預設外觀完全相同。
local RS = game:GetService("ReplicatedStorage")
local Catalog = require(RS.GameData.ShopCatalog)
local K = require(script.Parent.ArtKit)
local Cosmetic = {}

local function key(color)
 return string.format("%d,%d,%d",math.round(color.R*255),math.round(color.G*255),math.round(color.B*255))
end
-- 預設色票 → 色票名稱。原始美術以共用色票上色，所以顏色相同就代表同一種材料。
local sourceKeys = {}
for name in pairs({steel=true,iron=true,gold=true,leather=true,plaster=true,wallShade=true,stone=true,paleStone=true,
 tile=true,tileDark=true,thatch=true,thatchDark=true,roof=true,timber=true}) do
 local color = K[name]
 if typeof(color)=="Color3" then sourceKeys[key(color)] = name end
end

local function item(id,slot)
 local entry = type(id)=="string" and Catalog.items[id]
 return entry and entry.slot==slot and entry or nil
end

local function recolor(model,look)
 if not look or not look.palette or next(look.palette)==nil then return 0 end
 local changed = 0
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and part:GetAttribute("TeamColorPart")~=true then
   local name = sourceKeys[key(part.Color)]
   local color = name and look.palette[name]
   if color then
    part.Color = color
    local material = look.material and look.material[name]
    if material and Enum.Material[material] then part.Material = Enum.Material[material] end
    if part:IsA("UnionOperation") then part.UsePartColor = true end
    changed += 1
   end
  end
 end
 return changed
end

-- 只套用一次：模型記錄已套用的外觀，避免重複轉色。
local function apply(model,id,slot,attribute)
 local entry = item(id,slot)
 if not entry or entry.source=="default" or model:GetAttribute(attribute)~=nil then return 0 end
 model:SetAttribute(attribute,id)
 return recolor(model,entry.look)
end
function Cosmetic.SkinUnit(model,id) return apply(model,id,"unitSkin","CosmeticSkin") end
function Cosmetic.StyleBuilding(model,id) return apply(model,id,"buildingStyle","CosmeticStyle") end

function Cosmetic.Title(id)
 local entry = item(id,"title")
 if not entry or entry.look.text=="" then return nil end
 return entry.look
end

-- 大廳角色：頭上稱號與拖尾。重複呼叫會先移除舊的裝飾。
function Cosmetic.Dress(character,titleId,trailId)
 for _,name in ipairs({"RTSCosmeticTitle","RTSCosmeticTrail","RTSTrailTop","RTSTrailBottom"}) do
  local old = character:FindFirstChild(name,true)
  if old then old:Destroy() end
 end
 local head = character:FindFirstChild("Head")
 local root = character:FindFirstChild("HumanoidRootPart")
 local title = Cosmetic.Title(titleId)
 if title and head then
  local gui = Instance.new("BillboardGui")
  gui.Name = "RTSCosmeticTitle"
  gui.Size = UDim2.fromOffset(180,30)
  gui.StudsOffset = Vector3.new(0,2.9,0)
  gui.MaxDistance = 90
  gui.LightInfluence = 0
  gui.Adornee = head
  local label = Instance.new("TextLabel")
  label.Size = UDim2.fromScale(1,1)
  label.BackgroundTransparency = 1
  label.Text = (title.crown and "♛ " or "").."「"..title.text.."」"
  label.TextColor3 = title.color
  label.TextStrokeColor3 = Color3.fromRGB(20,22,30)
  label.TextStrokeTransparency = 0.2
  label.TextScaled = true
  label.Font = Enum.Font.FredokaOne
  label.Parent = gui
  gui.Parent = head
 end
 local trail = item(trailId,"trail")
 if trail and #trail.look.colors>0 and root then
  local top = Instance.new("Attachment")
  top.Name,top.Position = "RTSTrailTop",Vector3.new(0,0.9,0)
  top.Parent = root
  local bottom = Instance.new("Attachment")
  bottom.Name,bottom.Position = "RTSTrailBottom",Vector3.new(0,-0.9,0)
  bottom.Parent = root
  local effect = Instance.new("Trail")
  effect.Name = "RTSCosmeticTrail"
  effect.Attachment0,effect.Attachment1 = top,bottom
  local colors = trail.look.colors
  effect.Color = ColorSequence.new(colors[1],colors[#colors])
  effect.Transparency = NumberSequence.new(0.15,1)
  effect.Lifetime = 0.7
  effect.LightEmission = trail.look.light or 0.5
  effect.FaceCamera = true
  effect.Parent = root
 end
end

local function emitter(parent,colors,props)
 local e = Instance.new("ParticleEmitter")
 local sequence = #colors>=2 and ColorSequence.new(colors[1],colors[2]) or ColorSequence.new(colors[1] or Color3.new(1,1,1))
 e.Color = sequence
 for name,value in pairs(props) do e[name] = value end
 e.Parent = parent
 return e
end

-- 勝利慶典：在指定位置上方施放約 9 秒，所有玩家都看得到；結束後自動清除。
function Cosmetic.Celebrate(position,id,parent)
 local entry = item(id,"victory")
 if not entry or entry.look.kind=="none" then return nil end
 local look = entry.look
 local anchor = Instance.new("Part")
 anchor.Name = "VictoryCelebration"
 anchor.Size = Vector3.new(6,1,6)
 anchor.Transparency = 1
 anchor.Anchored,anchor.CanCollide,anchor.CanQuery,anchor.CanTouch = true,false,false,false
 anchor.CastShadow = false
 anchor.Position = position
 anchor.Parent = parent or workspace
 local emitters = {}
 if look.kind=="fireworks" then
  for index,color in ipairs(look.colors) do
   table.insert(emitters,emitter(anchor,{color,Color3.new(1,1,1)},{
    Rate=0,Lifetime=NumberRange.new(1.2,2),Speed=NumberRange.new(34,48),SpreadAngle=Vector2.new(40,40),
    Acceleration=Vector3.new(0,-26,0),Drag=1.5,LightEmission=1,
    Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.4),NumberSequenceKeypoint.new(1,0)}),
    Transparency=NumberSequence.new(0,1),Name="Firework"..index}))
  end
 elseif look.kind=="coins" then
  anchor.Position = position+Vector3.new(0,26,0)
  anchor.Size = Vector3.new(40,1,40)
  table.insert(emitters,emitter(anchor,look.colors,{
   Rate=70,Lifetime=NumberRange.new(2,3),Speed=NumberRange.new(2,6),EmissionDirection=Enum.NormalId.Bottom,
   Acceleration=Vector3.new(0,-24,0),RotSpeed=NumberRange.new(-220,220),Rotation=NumberRange.new(0,360),LightEmission=0.6,
   Size=NumberSequence.new(0.9),Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.85,0),NumberSequenceKeypoint.new(1,1)}),
   Shape=Enum.ParticleEmitterShape.Box,Name="CoinRain"}))
 elseif look.kind=="flame" then
  table.insert(emitters,emitter(anchor,look.colors,{
   Rate=60,Lifetime=NumberRange.new(1,1.6),Speed=NumberRange.new(26,38),SpreadAngle=Vector2.new(12,12),
   Acceleration=Vector3.new(0,6,0),LightEmission=0.9,RotSpeed=NumberRange.new(-60,60),
   Size=NumberSequence.new({NumberSequenceKeypoint.new(0,3),NumberSequenceKeypoint.new(0.5,6),NumberSequenceKeypoint.new(1,2)}),
   Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.1),NumberSequenceKeypoint.new(1,1)}),Name="DragonFlame"}))
  local light = Instance.new("PointLight")
  light.Color,light.Range,light.Brightness = look.colors[2] or look.colors[1],40,3
  light.Parent = anchor
 end
 task.spawn(function()
  local deadline = os.clock()+9
  while os.clock()<deadline and anchor.Parent do
   if look.kind=="fireworks" then
    for _,e in ipairs(emitters) do e:Emit(28) end
    task.wait(0.75)
   else task.wait(0.5) end
  end
  for _,e in ipairs(emitters) do e.Enabled = false end
  task.wait(3.5)
  anchor:Destroy()
 end)
 return anchor
end

return Cosmetic
