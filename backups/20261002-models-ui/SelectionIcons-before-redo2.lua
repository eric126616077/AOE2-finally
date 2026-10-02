-- Original, asset-free pictograms for the parchment selection panel.
local SelectionIcons = {}
local P = {
 edge = Color3.fromRGB(68, 45, 28), shade = Color3.fromRGB(112, 77, 43),
 steel = Color3.fromRGB(157, 169, 167), steelLight = Color3.fromRGB(219, 226, 214),
 gold = Color3.fromRGB(202, 148, 47), goldLight = Color3.fromRGB(245, 205, 108),
 wood = Color3.fromRGB(156, 101, 49), woodLight = Color3.fromRGB(206, 149, 85),
 stone = Color3.fromRGB(148, 147, 132), stoneLight = Color3.fromRGB(207, 203, 182),
 ivory = Color3.fromRGB(239, 218, 173), red = Color3.fromRGB(169, 72, 48), redLight = Color3.fromRGB(222, 112, 86),
 green = Color3.fromRGB(96, 142, 72), greenLight = Color3.fromRGB(150, 190, 104),
 skin = Color3.fromRGB(208, 153, 94),
}

local function rect(parent, name, x, y, width, height, color, rotation, radius)
 local part = Instance.new("Frame")
 part.Name = name
 part.Position = UDim2.fromScale(x, y)
 part.Size = UDim2.fromScale(width, height)
 part.BackgroundColor3 = color
 part.BorderSizePixel = 0
 part.Rotation = rotation or 0
 part.Active = false
 part.Selectable = false
 part.ZIndex = parent.ZIndex
 if radius then
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(radius, 0)
  corner.Parent = part
 end
 part.Parent = parent
 return part
end

local function oval(parent, name, x, y, width, height, color, rotation)
 return rect(parent, name, x, y, width, height, color, rotation, 0.5)
end

local function line(parent, name, x1, y1, x2, y2, thickness, color)
 local dx, dy = x2 - x1, y2 - y1
 local length = math.sqrt(dx * dx + dy * dy)
 return rect(parent, name, (x1 + x2) / 2 - length / 2, (y1 + y2) / 2 - thickness / 2,
  length, thickness, color, math.deg(math.atan2(dy, dx)), 0.2)
end

local function edgedLine(parent, name, x1, y1, x2, y2, thickness, color)
 line(parent, name .. "Edge", x1, y1, x2, y2, thickness + 0.055, P.edge)
 return line(parent, name, x1, y1, x2, y2, thickness, color)
end

local painters = {}

function painters.attack(canvas)
 edgedLine(canvas, "SwordBlade", 0.41, 0.62, 0.79, 0.2, 0.135, P.steelLight)
 line(canvas, "SwordFuller", 0.44, 0.6, 0.76, 0.24, 0.028, P.steel)
 edgedLine(canvas, "SwordGrip", 0.225, 0.825, 0.395, 0.64, 0.09, P.wood)
 edgedLine(canvas, "SwordGuard", 0.265, 0.505, 0.555, 0.765, 0.065, P.gold)
 oval(canvas, "SwordPommel", 0.145, 0.805, 0.14, 0.14, P.edge)
 oval(canvas, "PommelLight", 0.175, 0.827, 0.08, 0.08, P.gold)
end

function painters.armor(canvas)
 rect(canvas, "ShieldPoint", 0.25, 0.38, 0.5, 0.5, P.edge, 45, 0.13)
 rect(canvas, "ShieldTop", 0.145, 0.115, 0.71, 0.5, P.edge, nil, 0.2)
 rect(canvas, "ShieldPointFace", 0.285, 0.38, 0.43, 0.43, P.steel, 45, 0.1)
 rect(canvas, "ShieldFace", 0.2, 0.17, 0.6, 0.425, P.steel, nil, 0.14)
 rect(canvas, "ShieldLight", 0.235, 0.195, 0.2, 0.385, P.steelLight, nil, 0.1)
 line(canvas, "ShieldSpine", 0.5, 0.22, 0.5, 0.79, 0.065, P.gold)
 line(canvas, "ShieldBar", 0.27, 0.42, 0.73, 0.42, 0.06, P.gold)
end

function painters.range(canvas)
 oval(canvas, "TargetEdge", 0.1, 0.16, 0.76, 0.76, P.edge)
 oval(canvas, "TargetOuter", 0.145, 0.205, 0.67, 0.67, P.ivory)
 oval(canvas, "TargetRing", 0.245, 0.305, 0.47, 0.47, P.red)
 oval(canvas, "TargetInner", 0.335, 0.395, 0.29, 0.29, P.ivory)
 oval(canvas, "Bullseye", 0.415, 0.475, 0.13, 0.13, P.edge)
 edgedLine(canvas, "TargetArrow", 0.48, 0.54, 0.89, 0.135, 0.045, P.wood)
 line(canvas, "ArrowFeather", 0.755, 0.1, 0.755, 0.27, 0.065, P.edge)
 line(canvas, "ArrowFeather", 0.765, 0.255, 0.925, 0.255, 0.065, P.edge)
end

function painters.speed(canvas)
 for i = 0, 1 do
  local x = 0.28 + i * 0.34
  line(canvas, "SpeedChevron", x, 0.21, x + 0.24, 0.5, 0.13, P.edge)
  line(canvas, "SpeedChevron", x + 0.24, 0.5, x, 0.79, 0.13, P.edge)
  line(canvas, "SpeedHighlight", x + 0.045, 0.245, x + 0.245, 0.49, 0.045, P.gold)
 end
 line(canvas, "SpeedTrail", 0.09, 0.4, 0.275, 0.4, 0.055, P.shade)
 line(canvas, "SpeedTrail", 0.05, 0.595, 0.25, 0.595, 0.055, P.shade)
end

function painters.interval(canvas)
 line(canvas, "GlassEdge", 0.27, 0.235, 0.72, 0.765, 0.08, P.edge)
 line(canvas, "GlassEdge", 0.73, 0.235, 0.28, 0.765, 0.08, P.edge)
 line(canvas, "SandTop", 0.37, 0.32, 0.63, 0.32, 0.1, P.gold)
 line(canvas, "SandDrop", 0.5, 0.45, 0.5, 0.62, 0.04, P.gold)
 oval(canvas, "SandBottom", 0.325, 0.67, 0.35, 0.125, P.gold)
 rect(canvas, "HourglassTop", 0.2, 0.125, 0.6, 0.125, P.edge, nil, 0.16)
 rect(canvas, "HourglassBottom", 0.2, 0.755, 0.6, 0.125, P.edge, nil, 0.16)
 line(canvas, "TopTrim", 0.255, 0.163, 0.745, 0.163, 0.027, P.woodLight)
 line(canvas, "BottomTrim", 0.255, 0.835, 0.745, 0.835, 0.027, P.woodLight)
end

function painters.population(canvas)
 oval(canvas, "PersonHeadEdge", 0.325, 0.075, 0.35, 0.35, P.edge)
 oval(canvas, "PersonHead", 0.375, 0.125, 0.25, 0.25, P.ivory)
 oval(canvas, "PersonShoulders", 0.155, 0.44, 0.69, 0.34, P.edge)
 rect(canvas, "PersonBody", 0.22, 0.605, 0.56, 0.295, P.edge, nil, 0.13)
 line(canvas, "PersonCollar", 0.355, 0.525, 0.5, 0.66, 0.06, P.gold)
 line(canvas, "PersonCollar", 0.5, 0.66, 0.645, 0.525, 0.06, P.gold)
end

function painters.food(canvas)
 -- A tied sheaf of three fat wheat ears: reads at 13 px where a single stalk vanished.
 for _,stalk in ipairs({{0.3, 0.42, -16}, {0.5, 0.36, 0}, {0.7, 0.42, 16}}) do
  edgedLine(canvas, "WheatStem", 0.5, 0.9, stalk[1], stalk[2], 0.05, P.gold)
 end
 for _,ear in ipairs({{0.13, 0.13, -20}, {0.385, 0.05, 0}, {0.64, 0.13, 20}}) do
  oval(canvas, "WheatEarEdge", ear[1], ear[2], 0.23, 0.4, P.edge, ear[3])
  oval(canvas, "WheatEar", ear[1] + 0.028, ear[2] + 0.028, 0.174, 0.344, P.goldLight, ear[3])
  oval(canvas, "WheatGrain", ear[1] + 0.085, ear[2] + 0.07, 0.06, 0.26, P.gold, ear[3])
 end
 rect(canvas, "SheafTieEdge", 0.345, 0.62, 0.31, 0.13, P.edge, nil, 0.3)
 rect(canvas, "SheafTie", 0.37, 0.645, 0.26, 0.08, P.red, nil, 0.3)
end

function painters.wood(canvas)
 for i = 0, 2 do
  local y = 0.225 + i * 0.225
  local log = rect(canvas, "TimberEdge", 0.17, y, 0.66, 0.175, P.edge, -17, 0.18)
  rect(log, "TimberBark", 0.025, 0.18, 0.8, 0.64, P.wood, nil, 0.13)
  line(log, "TimberGrain", 0.06, 0.4, 0.74, 0.4, 0.14, P.woodLight)
  oval(log, "TimberEnd", 0.785, 0.15, 0.17, 0.7, P.woodLight)
  oval(log, "TimberRing", 0.827, 0.3, 0.075, 0.4, P.shade)
 end
end

function painters.gold(canvas)
 rect(canvas, "GoldBarEdge", 0.125, 0.56, 0.73, 0.245, P.edge, -12, 0.14)
 rect(canvas, "GoldBar", 0.16, 0.585, 0.655, 0.185, P.gold, -12, 0.1)
 rect(canvas, "GoldNuggetEdge", 0.27, 0.21, 0.46, 0.46, P.edge, 38, 0.14)
 rect(canvas, "GoldNugget", 0.31, 0.25, 0.38, 0.38, P.gold, 38, 0.12)
 rect(canvas, "GoldFacet", 0.325, 0.275, 0.19, 0.19, P.goldLight, 38, 0.1)
 line(canvas, "GoldBarLight", 0.225, 0.61, 0.733, 0.505, 0.05, P.goldLight)
end

function painters.stone(canvas)
 rect(canvas, "RockEdge", 0.14, 0.375, 0.5, 0.45, P.edge, -15, 0.19)
 rect(canvas, "Rock", 0.185, 0.415, 0.41, 0.355, P.stone, -15, 0.16)
 rect(canvas, "RockFacet", 0.22, 0.425, 0.195, 0.155, P.stoneLight, -15, 0.12)
 rect(canvas, "RockEdge", 0.565, 0.245, 0.28, 0.295, P.edge, 22, 0.18)
 rect(canvas, "Rock", 0.6, 0.28, 0.205, 0.22, P.stone, 22, 0.12)
 rect(canvas, "RockFacet", 0.615, 0.3, 0.095, 0.07, P.stoneLight, 22, 0.05)
 rect(canvas, "PebbleEdge", 0.655, 0.695, 0.21, 0.165, P.edge, 10, 0.26)
 rect(canvas, "Pebble", 0.687, 0.723, 0.15, 0.108, P.stoneLight, 10, 0.22)
end

function painters.axe(canvas)
 edgedLine(canvas, "AxeHandle", 0.27, 0.88, 0.6, 0.2, 0.075, P.woodLight)
 rect(canvas, "AxeHeadEdge", 0.43, 0.09, 0.4, 0.34, P.edge, -26, 0.16)
 rect(canvas, "AxeHead", 0.46, 0.12, 0.34, 0.28, P.steel, -26, 0.14)
 rect(canvas, "AxeBit", 0.62, 0.17, 0.15, 0.27, P.steelLight, -26, 0.3)
end

function painters.pick(canvas)
 edgedLine(canvas, "PickHandle", 0.3, 0.9, 0.56, 0.26, 0.075, P.woodLight)
 edgedLine(canvas, "PickArm", 0.17, 0.42, 0.52, 0.2, 0.085, P.steel)
 edgedLine(canvas, "PickArm", 0.52, 0.2, 0.88, 0.36, 0.085, P.steelLight)
 oval(canvas, "PickCollar", 0.44, 0.15, 0.16, 0.16, P.edge)
end

function painters.hammer(canvas)
 edgedLine(canvas, "HammerHandle", 0.26, 0.88, 0.58, 0.3, 0.075, P.woodLight)
 rect(canvas, "HammerHeadEdge", 0.33, 0.1, 0.5, 0.28, P.edge, -28, 0.14)
 rect(canvas, "HammerHead", 0.36, 0.13, 0.44, 0.22, P.steel, -28, 0.12)
 rect(canvas, "HammerFace", 0.38, 0.15, 0.13, 0.18, P.steelLight, -28, 0.1)
end

function painters.cart(canvas)
 edgedLine(canvas, "CartHandle", 0.7, 0.44, 0.95, 0.27, 0.05, P.woodLight)
 rect(canvas, "CartBoxEdge", 0.1, 0.3, 0.66, 0.36, P.edge, nil, 0.12)
 rect(canvas, "CartBox", 0.135, 0.335, 0.59, 0.29, P.wood, nil, 0.1)
 line(canvas, "CartPlank", 0.16, 0.44, 0.7, 0.44, 0.03, P.woodLight)
 oval(canvas, "CartLoad", 0.2, 0.2, 0.2, 0.18, P.gold)
 oval(canvas, "CartLoad", 0.42, 0.18, 0.22, 0.2, P.goldLight)
 oval(canvas, "CartWheelEdge", 0.26, 0.52, 0.38, 0.38, P.edge)
 oval(canvas, "CartWheel", 0.3, 0.56, 0.3, 0.3, P.woodLight)
 oval(canvas, "CartHub", 0.4, 0.66, 0.1, 0.1, P.edge)
end

function painters.heart(canvas)
 oval(canvas, "HeartEdge", 0.1, 0.16, 0.44, 0.44, P.edge)
 oval(canvas, "HeartEdge", 0.46, 0.16, 0.44, 0.44, P.edge)
 rect(canvas, "HeartEdge", 0.24, 0.3, 0.52, 0.52, P.edge, 45, 0.1)
 oval(canvas, "HeartLobe", 0.14, 0.2, 0.36, 0.36, P.red)
 oval(canvas, "HeartLobe", 0.5, 0.2, 0.36, 0.36, P.red)
 rect(canvas, "HeartPoint", 0.28, 0.33, 0.44, 0.44, P.red, 45, 0.08)
 oval(canvas, "HeartLight", 0.2, 0.25, 0.15, 0.12, P.redLight, -30)
end

function painters.flask(canvas)
 rect(canvas, "FlaskNeckEdge", 0.39, 0.1, 0.22, 0.36, P.edge, nil, 0.2)
 oval(canvas, "FlaskBodyEdge", 0.17, 0.36, 0.66, 0.56, P.edge)
 rect(canvas, "FlaskNeck", 0.43, 0.14, 0.14, 0.3, P.ivory, nil, 0.15)
 oval(canvas, "FlaskBody", 0.215, 0.405, 0.57, 0.47, P.ivory)
 oval(canvas, "FlaskLiquid", 0.255, 0.56, 0.49, 0.3, P.green)
 oval(canvas, "FlaskBubble", 0.36, 0.62, 0.11, 0.11, P.greenLight)
 rect(canvas, "FlaskCork", 0.4, 0.06, 0.2, 0.1, P.wood, nil, 0.3)
end

function painters.scroll(canvas)
 rect(canvas, "ScrollEdge", 0.2, 0.18, 0.6, 0.64, P.edge, nil, 0.06)
 rect(canvas, "ScrollPaper", 0.235, 0.2, 0.53, 0.6, P.ivory, nil, 0.05)
 for i = 0, 2 do line(canvas, "ScrollWriting", 0.31, 0.36 + i * 0.12, i == 2 and 0.55 or 0.69, 0.36 + i * 0.12, 0.04, P.shade) end
 for _,y in ipairs({0.12, 0.74}) do
  rect(canvas, "ScrollRodEdge", 0.12, y, 0.76, 0.15, P.edge, nil, 0.5)
  rect(canvas, "ScrollRod", 0.15, y + 0.03, 0.7, 0.09, P.woodLight, nil, 0.5)
 end
end

function painters.stop(canvas)
 rect(canvas, "StopEdge", 0.14, 0.14, 0.72, 0.72, P.edge, nil, 0.3)
 rect(canvas, "StopFace", 0.185, 0.185, 0.63, 0.63, P.red, nil, 0.27)
 rect(canvas, "StopBar", 0.3, 0.43, 0.4, 0.14, P.ivory, nil, 0.3)
end

function painters.flag(canvas)
 edgedLine(canvas, "FlagPole", 0.28, 0.92, 0.28, 0.1, 0.06, P.woodLight)
 rect(canvas, "FlagEdge", 0.3, 0.12, 0.56, 0.36, P.edge, nil, 0.1)
 rect(canvas, "FlagCloth", 0.33, 0.15, 0.5, 0.3, P.red, nil, 0.08)
 rect(canvas, "FlagStripe", 0.33, 0.27, 0.5, 0.06, P.goldLight)
 oval(canvas, "FlagFinial", 0.22, 0.04, 0.12, 0.12, P.gold)
end

function painters.empty(canvas)
 -- Open palm and five visible fingers: no resource is currently held.
 local fingers = {{0.28, 0.24, 0.37}, {0.425, 0.11, 0.48}, {0.57, 0.16, 0.46}, {0.715, 0.29, 0.33}}
 for _,finger in ipairs(fingers) do
  rect(canvas, "OpenFingerEdge", finger[1], finger[2], 0.145, finger[3], P.edge, nil, 0.45)
  rect(canvas, "OpenFinger", finger[1] + 0.033, finger[2] + 0.036, 0.079, finger[3] - 0.046, P.skin, nil, 0.4)
 end
 oval(canvas, "PalmEdge", 0.255, 0.41, 0.6, 0.405, P.edge)
 oval(canvas, "Palm", 0.297, 0.445, 0.512, 0.33, P.skin)
 edgedLine(canvas, "OpenThumb", 0.15, 0.45, 0.345, 0.67, 0.105, P.skin)
 rect(canvas, "WristEdge", 0.43, 0.715, 0.28, 0.2, P.edge, nil, 0.13)
 rect(canvas, "Wrist", 0.468, 0.745, 0.204, 0.17, P.skin, nil, 0.08)
 line(canvas, "PalmCrease", 0.4, 0.64, 0.705, 0.6, 0.032, P.shade)
end

function SelectionIcons.Create(parent, key, size, position)
 local root = Instance.new("Frame")
 root.Name = "SelectionIcon"
 root.Size = size or UDim2.fromOffset(22, 22)
 root.Position = position or UDim2.fromScale(0, 0)
 root.BackgroundTransparency = 1
 root.BorderSizePixel = 0
 root.Active = false
 root.Selectable = false
 root.ZIndex = parent:IsA("GuiObject") and parent.ZIndex or 1
 root:SetAttribute("IconKind", type(key) == "string" and key or "empty")
 root.Parent = parent
 local canvas = Instance.new("Frame")
 canvas.Name = "IconArt"
 canvas.AnchorPoint = Vector2.new(0.5, 0.5)
 canvas.Position = UDim2.fromScale(0.5, 0.5)
 canvas.Size = UDim2.fromScale(1, 1)
 canvas.BackgroundTransparency = 1
 canvas.BorderSizePixel = 0
 canvas.Active = false
 canvas.Selectable = false
 canvas.ZIndex = root.ZIndex
 canvas.Parent = root
 local aspect = Instance.new("UIAspectRatioConstraint")
 aspect.AspectRatio = 1
 aspect.AspectType = Enum.AspectType.FitWithinMaxSize
 aspect.Parent = canvas
 local painter = painters[key] or painters.empty
 painter(canvas)
 return root
end

return SelectionIcons
