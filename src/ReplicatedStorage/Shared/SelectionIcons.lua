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
 -- Two crossed swords.
 for _,side in ipairs({1, -1}) do
  local function x(value) return 0.5 + side * (value - 0.5) end
  edgedLine(canvas, "SwordBlade", x(0.36), 0.62, x(0.82), 0.14, 0.11, P.steelLight)
  line(canvas, "SwordFuller", x(0.4), 0.585, x(0.78), 0.19, 0.025, P.steel)
  edgedLine(canvas, "SwordGuard", x(0.22), 0.56, x(0.44), 0.78, 0.06, P.gold)
  edgedLine(canvas, "SwordGrip", x(0.2), 0.83, x(0.32), 0.69, 0.075, P.wood)
  oval(canvas, "SwordPommel", x(0.17) - 0.055, 0.8, 0.11, 0.11, P.gold)
 end
end

function painters.armor(canvas)
 -- Steel breastplate with pauldrons and a gilt collar.
 oval(canvas, "PauldronEdge", 0.06, 0.16, 0.34, 0.3, P.edge)
 oval(canvas, "PauldronEdge", 0.6, 0.16, 0.34, 0.3, P.edge)
 rect(canvas, "PlateEdge", 0.2, 0.14, 0.6, 0.6, P.edge, nil, 0.22)
 rect(canvas, "PlateWaistEdge", 0.27, 0.6, 0.46, 0.3, P.edge, nil, 0.2)
 oval(canvas, "Pauldron", 0.1, 0.2, 0.26, 0.22, P.steel)
 oval(canvas, "Pauldron", 0.64, 0.2, 0.26, 0.22, P.steel)
 rect(canvas, "Plate", 0.245, 0.185, 0.51, 0.51, P.steel, nil, 0.2)
 rect(canvas, "PlateWaist", 0.31, 0.62, 0.38, 0.235, P.steel, nil, 0.18)
 rect(canvas, "PlateLight", 0.29, 0.24, 0.16, 0.36, P.steelLight, nil, 0.3)
 line(canvas, "PlateRidge", 0.5, 0.26, 0.5, 0.82, 0.04, P.edge)
 rect(canvas, "PlateCollar", 0.36, 0.14, 0.28, 0.1, P.gold, nil, 0.4)
 line(canvas, "PlateBelt", 0.31, 0.66, 0.69, 0.66, 0.05, P.gold)
end

function painters.range(canvas)
 -- Drawn bow with a nocked arrow.
 edgedLine(canvas, "BowLimb", 0.3, 0.1, 0.62, 0.24, 0.085, P.woodLight)
 edgedLine(canvas, "BowLimb", 0.62, 0.24, 0.76, 0.5, 0.085, P.woodLight)
 edgedLine(canvas, "BowLimb", 0.76, 0.5, 0.62, 0.76, 0.085, P.woodLight)
 edgedLine(canvas, "BowLimb", 0.62, 0.76, 0.3, 0.9, 0.085, P.woodLight)
 line(canvas, "Bowstring", 0.3, 0.1, 0.22, 0.5, 0.03, P.edge)
 line(canvas, "Bowstring", 0.22, 0.5, 0.3, 0.9, 0.03, P.edge)
 edgedLine(canvas, "Arrow", 0.14, 0.5, 0.86, 0.5, 0.05, P.ivory)
 rect(canvas, "ArrowheadEdge", 0.8, 0.41, 0.18, 0.18, P.edge, 45, 0.1)
 rect(canvas, "Arrowhead", 0.83, 0.44, 0.12, 0.12, P.steelLight, 45, 0.08)
 line(canvas, "ArrowFeather", 0.08, 0.42, 0.2, 0.5, 0.05, P.red)
 line(canvas, "ArrowFeather", 0.08, 0.58, 0.2, 0.5, 0.05, P.red)
 rect(canvas, "BowGrip", 0.71, 0.42, 0.1, 0.16, P.edge, nil, 0.3)
end

function painters.speed(canvas)
 -- Running boot with motion lines.
 for i,y in ipairs({0.3, 0.48, 0.66}) do line(canvas, "SpeedTrail", 0.04, y, 0.3 - i * 0.03, y, 0.055, P.shade) end
 rect(canvas, "BootShaftEdge", 0.36, 0.1, 0.32, 0.58, P.edge, 8, 0.2)
 rect(canvas, "BootFootEdge", 0.36, 0.56, 0.58, 0.32, P.edge, nil, 0.4)
 rect(canvas, "BootShaft", 0.4, 0.14, 0.24, 0.52, P.wood, 8, 0.18)
 rect(canvas, "BootFoot", 0.4, 0.6, 0.5, 0.2, P.wood, nil, 0.4)
 rect(canvas, "BootSole", 0.38, 0.79, 0.55, 0.075, P.edge, nil, 0.4)
 rect(canvas, "BootCuff", 0.37, 0.12, 0.28, 0.13, P.woodLight, 8, 0.3)
 line(canvas, "BootLight", 0.47, 0.3, 0.5, 0.58, 0.05, P.woodLight)
end

function painters.interval(canvas)
 -- Stopwatch: time between attacks.
 rect(canvas, "WatchStem", 0.44, 0.04, 0.12, 0.16, P.edge, nil, 0.3)
 rect(canvas, "WatchCrown", 0.36, 0.02, 0.28, 0.09, P.gold, nil, 0.4)
 line(canvas, "WatchLug", 0.76, 0.2, 0.86, 0.12, 0.08, P.edge)
 oval(canvas, "WatchEdge", 0.1, 0.16, 0.8, 0.8, P.edge)
 oval(canvas, "WatchCase", 0.15, 0.21, 0.7, 0.7, P.gold)
 oval(canvas, "WatchFace", 0.215, 0.275, 0.57, 0.57, P.ivory)
 for i = 0, 3 do
  local a = i * math.pi / 2
  line(canvas, "WatchTick", 0.5 + math.sin(a) * 0.2, 0.56 - math.cos(a) * 0.2, 0.5 + math.sin(a) * 0.255, 0.56 - math.cos(a) * 0.255, 0.035, P.shade)
 end
 line(canvas, "WatchHand", 0.5, 0.56, 0.5, 0.36, 0.05, P.edge)
 line(canvas, "WatchHand", 0.5, 0.56, 0.65, 0.63, 0.045, P.red)
 oval(canvas, "WatchPin", 0.455, 0.515, 0.09, 0.09, P.edge)
end

function painters.population(canvas)
 -- Two villagers side by side: the one behind is paler.
 oval(canvas, "PersonHeadEdge", 0.5, 0.1, 0.3, 0.3, P.edge)
 oval(canvas, "PersonHead", 0.54, 0.14, 0.22, 0.22, P.skin)
 oval(canvas, "PersonShouldersEdge", 0.4, 0.4, 0.52, 0.5, P.edge)
 oval(canvas, "PersonShoulders", 0.44, 0.44, 0.44, 0.44, P.stone)
 oval(canvas, "PersonHeadEdge", 0.17, 0.16, 0.36, 0.36, P.edge)
 oval(canvas, "PersonHead", 0.215, 0.205, 0.27, 0.27, P.ivory)
 oval(canvas, "PersonShouldersEdge", 0.05, 0.5, 0.6, 0.5, P.edge)
 oval(canvas, "PersonShoulders", 0.095, 0.545, 0.51, 0.42, P.wood)
 rect(canvas, "PersonTunic", 0.3, 0.6, 0.1, 0.3, P.goldLight, nil, 0.3)
 rect(canvas, "PersonFloor", 0.02, 0.86, 0.96, 0.14, P.edge, nil, 0.4)
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
 -- Stacked logs seen end-on: three pale cut faces with growth rings.
 rect(canvas, "TimberBackEdge", 0.34, 0.18, 0.6, 0.3, P.edge, -14, 0.45)
 rect(canvas, "TimberBack", 0.375, 0.215, 0.53, 0.23, P.wood, -14, 0.45)
 line(canvas, "TimberGrain", 0.5, 0.36, 0.84, 0.275, 0.035, P.shade)
 for _,log in ipairs({{0.06, 0.5}, {0.46, 0.5}, {0.26, 0.17}}) do
  oval(canvas, "TimberEndEdge", log[1], log[2], 0.44, 0.44, P.edge)
  oval(canvas, "TimberBark", log[1] + 0.04, log[2] + 0.04, 0.36, 0.36, P.wood)
  oval(canvas, "TimberEnd", log[1] + 0.085, log[2] + 0.085, 0.27, 0.27, P.woodLight)
  oval(canvas, "TimberRing", log[1] + 0.15, log[2] + 0.15, 0.14, 0.14, P.wood)
  oval(canvas, "TimberHeart", log[1] + 0.19, log[2] + 0.19, 0.06, 0.06, P.woodLight)
 end
end

function painters.gold(canvas)
 -- A stack of coins beside a single coin showing its face.
 for i = 0, 3 do
  local y = 0.66 - i * 0.14
  oval(canvas, "GoldCoinEdge", 0.06, y, 0.52, 0.26, P.edge)
  oval(canvas, "GoldCoin", 0.095, y + 0.03, 0.45, 0.17, i == 3 and P.goldLight or P.gold)
 end
 oval(canvas, "GoldCoinShine", 0.2, 0.3, 0.2, 0.06, P.ivory)
 oval(canvas, "GoldFaceEdge", 0.46, 0.4, 0.5, 0.5, P.edge)
 oval(canvas, "GoldFace", 0.5, 0.44, 0.42, 0.42, P.gold)
 oval(canvas, "GoldFaceInner", 0.555, 0.495, 0.31, 0.31, P.goldLight)
 rect(canvas, "GoldFaceMark", 0.66, 0.6, 0.1, 0.1, P.gold, 45, 0.1)
end

function painters.stone(canvas)
 -- Dressed stone blocks laid as a short wall course.
 local blocks = {{0.04, 0.58, 0.44, 0.32, P.stone}, {0.5, 0.58, 0.46, 0.32, P.stoneLight}, {0.2, 0.26, 0.5, 0.32, P.stoneLight}, {0.72, 0.3, 0.24, 0.28, P.stone}}
 for _,b in ipairs(blocks) do
  rect(canvas, "RockEdge", b[1], b[2], b[3], b[4], P.edge, nil, 0.12)
  rect(canvas, "Rock", b[1] + 0.035, b[2] + 0.035, b[3] - 0.07, b[4] - 0.07, b[5], nil, 0.1)
  line(canvas, "RockFacet", b[1] + 0.08, b[2] + 0.09, b[1] + b[3] * 0.55, b[2] + 0.09, 0.04, P.ivory)
 end
 line(canvas, "RockCrack", 0.34, 0.4, 0.42, 0.5, 0.03, P.shade)
 oval(canvas, "Pebble", 0.08, 0.42, 0.11, 0.1, P.stone)
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
 -- An empty carrying basket: nothing is currently held.
 line(canvas, "BasketHandleEdge", 0.22, 0.4, 0.5, 0.12, 0.1, P.edge)
 line(canvas, "BasketHandleEdge", 0.5, 0.12, 0.78, 0.4, 0.1, P.edge)
 line(canvas, "BasketHandle", 0.22, 0.4, 0.5, 0.12, 0.05, P.woodLight)
 line(canvas, "BasketHandle", 0.5, 0.12, 0.78, 0.4, 0.05, P.woodLight)
 rect(canvas, "BasketEdge", 0.14, 0.42, 0.72, 0.48, P.edge, nil, 0.25)
 rect(canvas, "BasketBody", 0.18, 0.46, 0.64, 0.4, P.woodLight, nil, 0.22)
 oval(canvas, "BasketMouth", 0.2, 0.42, 0.6, 0.18, P.edge)
 oval(canvas, "BasketInside", 0.24, 0.45, 0.52, 0.11, P.shade)
 for i = 0, 2 do line(canvas, "BasketWeave", 0.3 + i * 0.2, 0.62, 0.3 + i * 0.2, 0.84, 0.035, P.wood) end
 line(canvas, "BasketBand", 0.2, 0.72, 0.8, 0.72, 0.035, P.wood)
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
