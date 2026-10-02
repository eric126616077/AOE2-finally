-- Original HUD portraits made from GUI geometry; no uploaded image assets required.
-- Coordinates are relative to a square canvas so the same art stays legible at 32–72 px.
local UnitIcons = {}

local P = {
 outline = Color3.fromRGB(31, 26, 22), backdrop = Color3.fromRGB(57, 47, 35),
 border = Color3.fromRGB(149, 118, 70), gold = Color3.fromRGB(224, 184, 103),
 light = Color3.fromRGB(247, 225, 180), steel = Color3.fromRGB(169, 184, 187),
 steelLight = Color3.fromRGB(221, 225, 209), steelDark = Color3.fromRGB(95, 110, 113),
 skin = Color3.fromRGB(214, 166, 112), skinLight = Color3.fromRGB(245, 204, 151),
 wood = Color3.fromRGB(146, 99, 53), woodLight = Color3.fromRGB(206, 151, 79),
 leather = Color3.fromRGB(104, 66, 39), green = Color3.fromRGB(118, 137, 84),
 olive = Color3.fromRGB(169, 161, 99), horse = Color3.fromRGB(181, 131, 76),
 mane = Color3.fromRGB(68, 43, 28), stone = Color3.fromRGB(181, 174, 149),
}
local COLOR_ATTRIBUTE = "UnitIconOriginalColor"
local TRANSPARENCY_ATTRIBUTE = "UnitIconOriginalTransparency"

local function rect(parent, name, x, y, width, height, color, rotation, radius)
 local part = Instance.new("Frame")
 part.Name = name
 part.Size = UDim2.fromScale(width, height)
 part.Position = UDim2.fromScale(x, y)
 part.Rotation = rotation or 0
 part.BackgroundColor3 = color
 part.BorderSizePixel = 0
 part.Active = false
 part.Selectable = false
 part.ZIndex = parent.ZIndex
 part:SetAttribute(COLOR_ATTRIBUTE, color)
 part:SetAttribute(TRANSPARENCY_ATTRIBUTE, 0)
 if radius then
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(radius, 0)
  corner.Parent = part
 end
 part.Parent = parent
 return part
end

local function ellipse(parent, name, x, y, width, height, color, rotation)
 return rect(parent, name, x, y, width, height, color, rotation, 0.5)
end

local function line(parent, name, x1, y1, x2, y2, thickness, color)
 local dx, dy = x2 - x1, y2 - y1
 local length = math.sqrt(dx * dx + dy * dy)
 return rect(parent, name, (x1 + x2) / 2 - length / 2, (y1 + y2) / 2 - thickness / 2,
  length, thickness, color, math.deg(math.atan2(dy, dx)), 0.25)
end

local function edgedLine(parent, name, x1, y1, x2, y2, thickness, color)
 line(parent, name .. "Edge", x1, y1, x2, y2, thickness + 0.035, P.outline)
 return line(parent, name, x1, y1, x2, y2, thickness, color)
end

local function face(parent, x, y, width, height)
 ellipse(parent, "FaceEdge", x - 0.018, y - 0.018, width + 0.036, height + 0.036, P.outline)
 ellipse(parent, "Face", x, y, width, height, P.skin)
 ellipse(parent, "FaceLight", x + width * 0.12, y + height * 0.08, width * 0.54, height * 0.75, P.skinLight)
 rect(parent, "Eye", x + width * 0.56, y + height * 0.41, 0.032, 0.023, P.outline, nil, 0.3)
end

local function shoulders(parent, x, y, width, height, color, team)
 ellipse(parent, "ShoulderEdge", x - 0.02, y - 0.02, width + 0.04, height + 0.04, P.outline)
 ellipse(parent, "Shoulders", x, y, width, height, color)
 rect(parent, "Tunic", x + width * 0.16, y + height * 0.25, width * 0.68, height * 0.72, color, nil, 0.16)
 rect(parent, "TeamTabard", x + width * 0.38, y + height * 0.12, width * 0.24, height * 0.72, team, nil, 0.08)
 line(parent, "Collar", x + width * 0.28, y + 0.025, x + width * 0.72, y + 0.025, 0.04, P.gold)
end

local function helmet(parent, x, y, width, height, team, heavy)
 ellipse(parent, "HelmetEdge", x - 0.017, y - 0.017, width + 0.034, height + 0.034, P.outline)
 ellipse(parent, "Helmet", x, y, width, height, heavy and P.steelDark or P.steel)
 ellipse(parent, "HelmetLight", x + width * 0.13, y + height * 0.08, width * 0.52, height * 0.68, P.steelLight)
 rect(parent, "HelmetBand", x - 0.025, y + height * 0.63, width + 0.05, 0.04, P.gold, nil, 0.12)
 if heavy then
  rect(parent, "Visor", x + 0.025, y + height * 0.68, width - 0.05, 0.055, P.outline, nil, 0.14)
  rect(parent, "NasalGuard", x + width * 0.48, y + height * 0.6, 0.05, height * 0.72, P.steel)
  line(parent, "PlumeEdge", x + width * 0.45, y + 0.03, x + width * 0.67, y - 0.09, 0.115, P.outline)
  line(parent, "Plume", x + width * 0.45, y + 0.03, x + width * 0.67, y - 0.09, 0.075, team)
 end
end

local function roundShield(parent, x, y, diameter, team)
 ellipse(parent, "ShieldEdge", x, y, diameter, diameter, P.outline)
 ellipse(parent, "ShieldRim", x + 0.018, y + 0.018, diameter - 0.036, diameter - 0.036, P.gold)
 ellipse(parent, "ShieldFace", x + 0.043, y + 0.043, diameter - 0.086, diameter - 0.086, team)
 ellipse(parent, "ShieldBoss", x + diameter * 0.39, y + diameter * 0.39, diameter * 0.22, diameter * 0.22, P.steelLight)
end

local function kiteShield(parent, x, y, width, height, team)
 rect(parent, "ShieldPointEdge", x + width * 0.17, y + height * 0.3, width * 0.7, width * 0.7, P.outline, 45, 0.08)
 rect(parent, "ShieldTopEdge", x, y, width, height * 0.62, P.outline, nil, 0.17)
 rect(parent, "ShieldPoint", x + width * 0.23, y + height * 0.32, width * 0.57, width * 0.57, team, 45, 0.05)
 rect(parent, "ShieldTop", x + 0.018, y + 0.018, width - 0.036, height * 0.57, team, nil, 0.1)
 line(parent, "ShieldSpine", x + width / 2, y + 0.04, x + width / 2, y + height * 0.8, 0.032, P.gold)
 line(parent, "ShieldCross", x + 0.03, y + height * 0.28, x + width - 0.03, y + height * 0.28, 0.028, P.gold)
end

local painters = {}

function painters.villager(canvas, team)
 -- Straw hat, linen tunic and a broad iron pick.
 edgedLine(canvas, "PickShaft", 0.72, 0.81, 0.8, 0.3, 0.055, P.woodLight)
 edgedLine(canvas, "PickHead", 0.61, 0.31, 0.9, 0.38, 0.055, P.steelLight)
 shoulders(canvas, 0.18, 0.56, 0.48, 0.32, team, P.light)
 face(canvas, 0.31, 0.3, 0.23, 0.28)
 ellipse(canvas, "StrawCrownEdge", 0.285, 0.22, 0.285, 0.18, P.outline)
 ellipse(canvas, "StrawCrown", 0.305, 0.235, 0.245, 0.16, P.gold)
 ellipse(canvas, "StrawBrimEdge", 0.2, 0.33, 0.44, 0.075, P.outline)
 ellipse(canvas, "StrawBrim", 0.21, 0.335, 0.42, 0.048, P.light)
 line(canvas, "HatRibbon", 0.31, 0.317, 0.55, 0.317, 0.035, team)
 line(canvas, "TunicSeam", 0.36, 0.63, 0.36, 0.84, 0.025, P.light)
 ellipse(canvas, "ToolHand", 0.695, 0.6, 0.09, 0.1, P.skinLight)
end

function painters.infantry(canvas, team)
 -- Sword and kite shield distinguish the melee infantry portrait.
 edgedLine(canvas, "SwordBlade", 0.76, 0.65, 0.76, 0.22, 0.072, P.steelLight)
 line(canvas, "SwordFuller", 0.775, 0.57, 0.775, 0.24, 0.015, P.steelDark)
 edgedLine(canvas, "SwordGrip", 0.76, 0.65, 0.76, 0.82, 0.05, P.leather)
 edgedLine(canvas, "SwordGuard", 0.65, 0.635, 0.87, 0.635, 0.035, P.gold)
 shoulders(canvas, 0.24, 0.55, 0.43, 0.32, P.steelDark, team)
 face(canvas, 0.36, 0.31, 0.22, 0.26)
 helmet(canvas, 0.33, 0.225, 0.275, 0.22, team, false)
 rect(canvas, "CheekGuard", 0.32, 0.385, 0.05, 0.17, P.steel)
 kiteShield(canvas, 0.17, 0.6, 0.25, 0.29, team)
end

function painters.spearman(canvas, team)
 -- Tall spear, pointed cap and large round shield.
 edgedLine(canvas, "LongSpear", 0.795, 0.86, 0.795, 0.22, 0.045, P.woodLight)
 rect(canvas, "SpearTipEdge", 0.739, 0.145, 0.112, 0.112, P.outline, 45, 0.06)
 rect(canvas, "SpearTip", 0.755, 0.16, 0.08, 0.08, P.steelLight, 45, 0.05)
 shoulders(canvas, 0.24, 0.56, 0.44, 0.3, P.light, team)
 face(canvas, 0.36, 0.32, 0.21, 0.26)
 ellipse(canvas, "KettleDomeEdge", 0.345, 0.215, 0.24, 0.2, P.outline)
 ellipse(canvas, "KettleDome", 0.362, 0.232, 0.206, 0.166, P.steel)
 ellipse(canvas, "KettleLight", 0.385, 0.245, 0.1, 0.09, P.steelLight)
 ellipse(canvas, "KettleBrimEdge", 0.27, 0.33, 0.39, 0.095, P.outline)
 ellipse(canvas, "KettleBrim", 0.285, 0.343, 0.36, 0.066, P.steelLight)
 line(canvas, "HelmetBrow", 0.36, 0.335, 0.57, 0.335, 0.03, team)
 roundShield(canvas, 0.15, 0.59, 0.31, team)
 ellipse(canvas, "SpearHand", 0.747, 0.61, 0.095, 0.085, P.skinLight)
end

function painters.archer(canvas, team)
 -- Curved bow and taut string alongside a green hood.
 edgedLine(canvas, "BowUpper", 0.71, 0.25, 0.845, 0.4, 0.06, P.woodLight)
 edgedLine(canvas, "BowMiddle", 0.845, 0.4, 0.865, 0.61, 0.06, P.woodLight)
 edgedLine(canvas, "BowLower", 0.865, 0.61, 0.74, 0.81, 0.06, P.woodLight)
 line(canvas, "Bowstring", 0.71, 0.25, 0.74, 0.81, 0.025, P.light)
 shoulders(canvas, 0.22, 0.56, 0.43, 0.31, P.green, team)
 ellipse(canvas, "HoodEdge", 0.285, 0.215, 0.34, 0.385, P.outline)
 ellipse(canvas, "Hood", 0.302, 0.232, 0.305, 0.35, P.green)
 face(canvas, 0.358, 0.325, 0.19, 0.24)
 line(canvas, "HoodRim", 0.325, 0.318, 0.565, 0.295, 0.055, P.olive)
 edgedLine(canvas, "Arrow", 0.54, 0.535, 0.915, 0.535, 0.027, P.light)
 rect(canvas, "Arrowhead", 0.88, 0.498, 0.06, 0.06, P.steelLight, 45)
 ellipse(canvas, "BowHand", 0.69, 0.5, 0.09, 0.1, P.skinLight)
end

function painters.skirmisher(canvas, team)
 -- Short diagonal javelin and a small buckler; visibly different from the spear.
 edgedLine(canvas, "Javelin", 0.49, 0.75, 0.88, 0.29, 0.043, P.woodLight)
 rect(canvas, "JavelinTipEdge", 0.837, 0.21, 0.085, 0.145, P.outline, 40, 0.1)
 rect(canvas, "JavelinTip", 0.855, 0.23, 0.05, 0.105, P.steelLight, 40, 0.08)
 shoulders(canvas, 0.23, 0.56, 0.44, 0.31, P.olive, team)
 face(canvas, 0.345, 0.305, 0.23, 0.265)
 ellipse(canvas, "LeatherCapEdge", 0.31, 0.23, 0.295, 0.155, P.outline)
 ellipse(canvas, "LeatherCap", 0.325, 0.245, 0.265, 0.13, P.leather)
 line(canvas, "Headband", 0.305, 0.345, 0.605, 0.345, 0.048, team)
 roundShield(canvas, 0.185, 0.665, 0.23, P.woodLight)
 line(canvas, "BucklerBrace", 0.236, 0.695, 0.366, 0.845, 0.024, P.gold)
 ellipse(canvas, "ThrowingHand", 0.63, 0.47, 0.085, 0.09, P.skinLight)
end

local function horse(canvas, team, armored)
 -- Horse in profile, rider above the saddle. Heavy cavalry adds a steel faceplate.
 local coat = armored and P.leather or P.horse
 ellipse(canvas, "HorseBodyEdge", 0.15, 0.61, 0.58, 0.25, P.outline)
 ellipse(canvas, "HorseBody", 0.17, 0.63, 0.54, 0.205, coat)
 edgedLine(canvas, "Foreleg", 0.63, 0.755, 0.69, 0.9, 0.065, coat)
 edgedLine(canvas, "Hindleg", 0.25, 0.76, 0.21, 0.9, 0.065, coat)
 ellipse(canvas, "NeckEdge", 0.585, 0.43, 0.24, 0.35, P.outline, -18)
 ellipse(canvas, "Neck", 0.602, 0.448, 0.205, 0.3, coat, -18)
 ellipse(canvas, "HorseHeadEdge", 0.67, 0.385, 0.26, 0.145, P.outline, 22)
 ellipse(canvas, "HorseHead", 0.683, 0.4, 0.235, 0.117, coat, 22)
 rect(canvas, "HorseEar", 0.687, 0.33, 0.06, 0.11, coat, -14, 0.18)
 line(canvas, "Mane", 0.635, 0.446, 0.59, 0.67, 0.065, P.mane)
 rect(canvas, "SaddleCloth", 0.32, 0.638, 0.22, 0.19, team, nil, 0.12)
 line(canvas, "SaddleTrim", 0.332, 0.805, 0.53, 0.805, 0.024, P.gold)
 if armored then
  rect(canvas, "CaparisonEdge", 0.17, 0.64, 0.54, 0.2, P.outline, nil, 0.25)
  rect(canvas, "Caparison", 0.19, 0.655, 0.5, 0.165, team, nil, 0.22)
  line(canvas, "CaparisonHem", 0.2, 0.815, 0.68, 0.815, 0.025, P.gold)
  ellipse(canvas, "HorseArmor", 0.623, 0.447, 0.15, 0.245, P.steel, -18)
  ellipse(canvas, "HorseFaceplate", 0.705, 0.398, 0.18, 0.09, P.steelLight, 22)
  line(canvas, "HorseArmorRidge", 0.66, 0.47, 0.697, 0.632, 0.027, P.gold)
 end
 rect(canvas, "HorseEye", 0.77, 0.425, 0.028, 0.028, P.outline, nil, 0.5)
 line(canvas, "Bridle", 0.839, 0.429, 0.821, 0.514, 0.022, P.gold)
 line(canvas, "Reins", 0.801, 0.504, 0.51, 0.572, 0.021, P.leather)
end

function painters.scout(canvas, team)
 horse(canvas, team, false)
 shoulders(canvas, 0.29, 0.4, 0.265, 0.25, P.leather, team)
 face(canvas, 0.335, 0.205, 0.17, 0.21)
 ellipse(canvas, "ScoutCapEdge", 0.305, 0.16, 0.24, 0.12, P.outline)
 ellipse(canvas, "ScoutCap", 0.322, 0.175, 0.205, 0.09, P.woodLight)
 line(canvas, "ScoutBand", 0.312, 0.242, 0.532, 0.242, 0.027, team)
 edgedLine(canvas, "ScoutSword", 0.18, 0.515, 0.19, 0.235, 0.035, P.steelLight)
 line(canvas, "ScoutGuard", 0.13, 0.45, 0.235, 0.45, 0.035, P.gold)
end

function painters.cavalry(canvas, team)
 edgedLine(canvas, "KnightLance", 0.585, 0.65, 0.815, 0.145, 0.04, P.woodLight)
 rect(canvas, "LanceTip", 0.783, 0.105, 0.067, 0.1, P.steelLight, 24, 0.04)
 horse(canvas, team, true)
 shoulders(canvas, 0.295, 0.405, 0.27, 0.245, P.steel, team)
 rect(canvas, "GreatHelmEdge", 0.325, 0.185, 0.21, 0.25, P.outline, nil, 0.22)
 rect(canvas, "GreatHelm", 0.343, 0.203, 0.174, 0.214, P.steel, nil, 0.2)
 rect(canvas, "GreatHelmLight", 0.36, 0.215, 0.06, 0.18, P.steelLight, nil, 0.3)
 rect(canvas, "Visor", 0.4, 0.29, 0.125, 0.035, P.outline, nil, 0.3)
 line(canvas, "PlumeEdge", 0.42, 0.2, 0.52, 0.09, 0.105, P.outline)
 line(canvas, "Plume", 0.42, 0.2, 0.52, 0.09, 0.065, team)
 kiteShield(canvas, 0.25, 0.455, 0.165, 0.22, team)
end

local function wheel(canvas, x, y, diameter)
 ellipse(canvas, "WheelEdge", x, y, diameter, diameter, P.outline)
 ellipse(canvas, "WheelRim", x + 0.014, y + 0.014, diameter - 0.028, diameter - 0.028, P.woodLight)
 ellipse(canvas, "WheelInside", x + 0.037, y + 0.037, diameter - 0.074, diameter - 0.074, P.leather)
 line(canvas, "WheelSpoke", x + diameter / 2, y + 0.034, x + diameter / 2, y + diameter - 0.034, 0.024, P.woodLight)
 line(canvas, "WheelSpoke", x + 0.034, y + diameter / 2, x + diameter - 0.034, y + diameter / 2, 0.024, P.woodLight)
 ellipse(canvas, "WheelHub", x + diameter * 0.39, y + diameter * 0.39, diameter * 0.22, diameter * 0.22, P.gold)
end

function painters.ram(canvas, team)
 -- Low covered wagon with a projecting iron-tipped battering log.
 edgedLine(canvas, "RamLog", 0.21, 0.61, 0.865, 0.61, 0.105, P.woodLight)
 rect(canvas, "RamHeadEdge", 0.818, 0.535, 0.09, 0.153, P.outline, nil, 0.15)
 rect(canvas, "RamHead", 0.826, 0.547, 0.075, 0.127, P.steelLight, nil, 0.13)
 rect(canvas, "WagonEdge", 0.17, 0.43, 0.57, 0.31, P.outline, nil, 0.04)
 rect(canvas, "WagonSide", 0.19, 0.45, 0.53, 0.245, P.wood, nil, 0.04)
 for i = 0, 3 do
  line(canvas, "WagonPlank", 0.22 + i * 0.115, 0.46, 0.22 + i * 0.115, 0.67, 0.027, P.woodLight)
 end
 line(canvas, "RoofSlope", 0.165, 0.44, 0.335, 0.305, 0.09, P.outline)
 line(canvas, "RoofSlope", 0.335, 0.305, 0.75, 0.44, 0.09, P.outline)
 line(canvas, "RoofCover", 0.17, 0.421, 0.335, 0.305, 0.055, P.leather)
 line(canvas, "RoofCover", 0.335, 0.305, 0.735, 0.421, 0.055, P.leather)
 line(canvas, "RoofTrim", 0.17, 0.44, 0.745, 0.44, 0.035, team)
 rect(canvas, "RoofRidge", 0.295, 0.262, 0.085, 0.085, team, 45, 0.15)
 wheel(canvas, 0.19, 0.68, 0.205)
 wheel(canvas, 0.555, 0.68, 0.205)
end

function painters.mangonel(canvas, team)
 -- Compact catapult: wide cart, triangular supports and a loaded stone basket.
 edgedLine(canvas, "CartBed", 0.18, 0.72, 0.825, 0.72, 0.105, P.woodLight)
 edgedLine(canvas, "CatapultBrace", 0.29, 0.69, 0.46, 0.38, 0.062, P.woodLight)
 edgedLine(canvas, "CatapultBrace", 0.67, 0.69, 0.49, 0.38, 0.062, P.woodLight)
 edgedLine(canvas, "ThrowingArm", 0.335, 0.665, 0.75, 0.27, 0.07, P.woodLight)
 ellipse(canvas, "BasketEdge", 0.637, 0.175, 0.245, 0.165, P.outline, -23)
 ellipse(canvas, "Basket", 0.653, 0.196, 0.213, 0.125, P.wood, -23)
 ellipse(canvas, "StoneEdge", 0.682, 0.14, 0.14, 0.13, P.outline)
 ellipse(canvas, "Stone", 0.694, 0.15, 0.116, 0.112, P.stone)
 ellipse(canvas, "StoneLight", 0.706, 0.166, 0.055, 0.041, P.light, -18)
 ellipse(canvas, "Pivot", 0.425, 0.395, 0.12, 0.12, P.gold)
 rect(canvas, "CartBanner", 0.31, 0.615, 0.24, 0.135, team, nil, 0.06)
 wheel(canvas, 0.21, 0.715, 0.19)
 wheel(canvas, 0.65, 0.715, 0.19)
end

function painters.trebuchet(canvas, team)
 -- Tall A-frame, long throwing beam, counterweight and sling.
 edgedLine(canvas, "SiegeBed", 0.185, 0.795, 0.84, 0.795, 0.055, P.woodLight)
 edgedLine(canvas, "TallBrace", 0.27, 0.77, 0.46, 0.3, 0.055, P.woodLight)
 edgedLine(canvas, "TallBrace", 0.69, 0.77, 0.475, 0.3, 0.055, P.woodLight)
 line(canvas, "CrossBrace", 0.34, 0.61, 0.62, 0.61, 0.036, P.wood)
 edgedLine(canvas, "TrebuchetBeam", 0.225, 0.515, 0.79, 0.16, 0.063, P.woodLight)
 line(canvas, "SlingRope", 0.785, 0.165, 0.86, 0.4, 0.025, P.light)
 ellipse(canvas, "SlingPouch", 0.815, 0.366, 0.108, 0.075, team, 15)
 line(canvas, "CounterweightChain", 0.27, 0.483, 0.26, 0.605, 0.028, P.gold)
 rect(canvas, "CounterweightEdge", 0.145, 0.575, 0.205, 0.145, P.outline, nil, 0.08)
 rect(canvas, "Counterweight", 0.16, 0.587, 0.175, 0.119, P.stone, nil, 0.06)
 rect(canvas, "WeightLight", 0.175, 0.6, 0.075, 0.083, P.steelLight, nil, 0.03)
 ellipse(canvas, "BeamPivot", 0.418, 0.326, 0.095, 0.095, P.gold)
 rect(canvas, "SiegePennant", 0.49, 0.465, 0.14, 0.12, team, nil, 0.04)
 wheel(canvas, 0.215, 0.76, 0.14)
 wheel(canvas, 0.68, 0.76, 0.14)
end

function painters.monk(canvas, team)
 -- Cream robe, tonsured head, a mantle in the player color and a gold-disc staff.
 edgedLine(canvas, "CrookShaft", 0.76, 0.88, 0.76, 0.3, 0.05, P.wood)
 ellipse(canvas, "StaffDiscEdge", 0.675, 0.12, 0.17, 0.2, P.outline)
 ellipse(canvas, "StaffDisc", 0.695, 0.14, 0.13, 0.16, P.gold)
 ellipse(canvas, "RobeEdge", 0.2, 0.52, 0.5, 0.4, P.outline)
 ellipse(canvas, "Robe", 0.22, 0.54, 0.46, 0.36, P.light)
 rect(canvas, "RobeSkirt", 0.27, 0.66, 0.36, 0.22, P.light, nil, 0.12)
 ellipse(canvas, "MantleEdge", 0.225, 0.5, 0.45, 0.2, P.outline)
 ellipse(canvas, "Mantle", 0.245, 0.515, 0.41, 0.165, team)
 rect(canvas, "Stole", 0.415, 0.6, 0.07, 0.28, team, nil, 0.08)
 ellipse(canvas, "TonsureEdge", 0.325, 0.235, 0.25, 0.2, P.outline)
 ellipse(canvas, "Tonsure", 0.34, 0.25, 0.22, 0.17, P.mane)
 face(canvas, 0.355, 0.3, 0.19, 0.23)
 ellipse(canvas, "BaldCrown", 0.385, 0.245, 0.13, 0.075, P.skinLight)
 ellipse(canvas, "CrookHand", 0.715, 0.58, 0.085, 0.09, P.skinLight)
end

local function unknown(canvas, team)
 shoulders(canvas, 0.235, 0.57, 0.53, 0.31, P.steelDark, team)
 ellipse(canvas, "HeadEdge", 0.345, 0.255, 0.31, 0.31, P.outline)
 ellipse(canvas, "Head", 0.365, 0.275, 0.27, 0.27, P.stone)
 ellipse(canvas, "HeadLight", 0.39, 0.295, 0.12, 0.21, P.light)
end

function UnitIcons.Create(parent, kind, size, position, teamColor)
 local root = Instance.new("Frame")
 root.Name = "UnitIcon"
 root.Size = size or UDim2.fromOffset(48, 48)
 root.Position = position or UDim2.fromScale(0, 0)
 root.BackgroundTransparency = 1
 root.BorderSizePixel = 0
 root.Active = false
 root.Selectable = false
 root.ZIndex = parent:IsA("GuiObject") and parent.ZIndex or 1
 root:SetAttribute("UnitType", type(kind) == "string" and kind or "unknown")
 root:SetAttribute("Muted", false)
 root.Parent = parent

 local canvas = Instance.new("Frame")
 canvas.Name = "PortraitArt"
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

 local team = typeof(teamColor) == "Color3" and teamColor or P.gold
 rect(canvas, "PortraitBorder", 0.045, 0.045, 0.91, 0.91, P.border, nil, 0.14)
 rect(canvas, "PortraitTeamRing", 0.07, 0.07, 0.86, 0.86, team, nil, 0.12)
 rect(canvas, "PortraitGround", 0.105, 0.105, 0.79, 0.79, P.backdrop, nil, 0.09)
 ellipse(canvas, "GroundShadow", 0.16, 0.815, 0.68, 0.08, P.outline)
 local painter = painters[kind] or unknown
 painter(canvas, team)
 return root
end

function UnitIcons.SetMuted(root, muted)
 if typeof(root) ~= "Instance" or not root:IsA("Frame") then return end
 muted = muted == true
 if root:GetAttribute("Muted") == muted then return end
 root:SetAttribute("Muted", muted)
 for _,part in ipairs(root:GetDescendants()) do
  local original = part:GetAttribute(COLOR_ATTRIBUTE)
  if part:IsA("GuiObject") and typeof(original) == "Color3" then
   if muted then
    local shade = original.R * 0.299 + original.G * 0.587 + original.B * 0.114
    part.BackgroundColor3 = Color3.new(shade * 0.78, shade * 0.78, shade * 0.78)
    part.BackgroundTransparency = math.min(1, (part:GetAttribute(TRANSPARENCY_ATTRIBUTE) or 0) + 0.12)
   else
    part.BackgroundColor3 = original
    part.BackgroundTransparency = part:GetAttribute(TRANSPARENCY_ATTRIBUTE) or 0
   end
  end
 end
end

return UnitIcons
