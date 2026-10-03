local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Config = require(RS.GameData.GameConfig)
local Grid = require(RS.Shared.Grid)
local Art = require(RS.Shared.Art)
local Tutorial = require(RS.Shared.Tutorial)
local TouchRules = require(RS.Shared.TouchRules)
local CameraFocus = require(RS.Shared.CameraFocus)
local Audio = require(RS.Shared.AudioFeedback)
local TeamClient = require(RS.Shared.TeamClientRules)
local GameModes = require(RS.Shared.GameModeRules)
local Building = require(RS.Shared.BuildingController)
local ClientUnitView = require(RS.Shared.ClientUnitView)
local BuildMenuRules = require(RS.Shared.BuildMenuRules)
local UnitIcons = require(RS.Shared.UnitIcons)
local SelectionIcons = require(RS.Shared.SelectionIcons)
local UnitSelectionPanel = require(RS.Shared.UnitSelectionPanel)
local HotkeyRules = require(RS.Shared.HotkeyRules)
local FogView = require(RS.Shared.FogView)
local player = Players.LocalPlayer
local GUI = {hitAreas = {}, reducedMotion = false, tab = "build", page = 1}
-- Parchment-and-timber theme, matching the storybook models: warm paper panels in a wood frame,
-- ink text, cream tiles for buttons. `white` is the main text color (ink), kept under its old key.
local C = {panel = Color3.fromRGB(240,227,194), card = Color3.fromRGB(252,244,220), edge = Color3.fromRGB(128,92,56),
 gold = Color3.fromRGB(156,98,16), white = Color3.fromRGB(54,38,26), muted = Color3.fromRGB(120,98,72),
 green = Color3.fromRGB(44,120,56), red = Color3.fromRGB(184,56,40), inset = Color3.fromRGB(218,201,164),
 trimLight = Color3.fromRGB(176,134,84), trimDark = Color3.fromRGB(84,58,36), ribbon = Color3.fromRGB(96,66,42)}
-- Text that sits on a dark timber band (ribbons, badges, notices) or directly over the terrain.
local L = {white = Color3.fromRGB(252,242,216), gold = Color3.fromRGB(250,216,140), muted = Color3.fromRGB(216,196,162)}
local resourceColors = {food = Color3.fromRGB(190,84,52),wood = Color3.fromRGB(84,130,56),gold = Color3.fromRGB(188,138,22),
 stone = Color3.fromRGB(108,122,138),population = Color3.fromRGB(50,126,148)}
local NUMBER_FONT = Enum.Font.GothamBold
local reportOutcomes={pending="等待對局結果",win="勝利",loss="戰敗",draw="無勝者"}
local reportCounters={"buildingsCompleted","villagersTrained","militaryTrained","damageDealt","unitsKilled","buildingsKilled","unitsLost","buildingsLost"}
local reportLabels={resourcesDelivered="資源交貨量",resourcesSpent="資源淨支出",buildingsCompleted="完工建築",villagersTrained="訓練村民",
 militaryTrained="訓練軍隊",damageDealt="造成傷害",unitsKilled="單位擊殺",buildingsKilled="建築摧毀",unitsLost="戰鬥單位損失",
 buildingsLost="戰鬥建築損失",survivalSeconds="存活時長",outcome="對局結果",food="食物",wood="木材",gold="黃金",stone="石材"}
local reportFields={version=true,matchId=true,finished=true,outcome=true,outcomeLabel=true,survivalSeconds=true,resourcesDelivered=true,resourcesSpent=true,labels=true}
for _,key in ipairs(reportCounters) do reportFields[key]=true end
local function reportNumber(value,whole)
 return type(value)=="number" and value==value and value>=0 and value<=9007199254740991 and (not whole or value%1==0)
end
local function validReport(value)
 if type(value)~="table" or value.version~=1 or type(value.finished)~="boolean" or not reportOutcomes[value.outcome]
  or (value.finished and value.outcome=="pending") or (not value.finished and value.outcome~="pending")
  or type(value.matchId)~="string" or #value.matchId==0 or #value.matchId>100 or not value.matchId:match("^[%w_:%-]+$")
  or value.outcomeLabel~=reportOutcomes[value.outcome] or not reportNumber(value.survivalSeconds) or type(value.labels)~="table" then return false end
 for key in pairs(value) do if not reportFields[key] then return false end end
 for key,label in pairs(value.labels) do if not reportLabels[key] or type(label)~="string" or #label>96 then return false end end
 for _,key in ipairs(reportCounters) do if not reportNumber(value[key],key~="damageDealt") then return false end end
 for _,field in ipairs({"resourcesDelivered","resourcesSpent"}) do
  local amounts=value[field]
  if type(amounts)~="table" then return false end
  for key in pairs(amounts) do if key~="food" and key~="wood" and key~="gold" and key~="stone" then return false end end
  for _,key in ipairs({"food","wood","gold","stone"}) do if not reportNumber(amounts[key]) then return false end end
 end
 return true
end
local function reportValue(value)
 if value>=100000000 then return string.format("%.2f 億",value/100000000) end
 if value>=10000 then return string.format("%.1f 萬",value/10000) end
 return value%1==0 and string.format("%.0f",value) or string.format("%.1f",value)
end
local function reportDuration(value)
 local seconds=math.floor(value)
 return string.format("%d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end
local animations = setmetatable({}, {__mode = "k"})
local function tween(object, duration, properties)
 if animations[object] then animations[object]:Cancel() end
 local animation = TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), properties)
 animations[object] = animation; animation:Play()
end
local function make(class, parent, properties)
 local object = Instance.new(class)
 for key, value in pairs(properties or {}) do object[key] = value end
 object.Parent = parent
 return object
end
local function text(parent, value, size, position, fontSize, color, font)
 return make("TextLabel", parent, {Text = value, Size = size, Position = position, BackgroundTransparency = 1,
  TextColor3 = color or C.white, TextSize = fontSize or 16, Font = font or Enum.Font.SourceSans,
  TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true})
end
local function round(object, radius) make("UICorner", object, {CornerRadius = UDim.new(0, radius or 4)}) end
local function stroke(object, color, transparency)
 return make("UIStroke", object, {Color = color or C.edge, Thickness = 1, Transparency = transparency or 0,
  ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
-- A light-to-dark gold sweep turns a flat stroke into a gilded frame.
local function gild(edge)
 edge.Color = Color3.new(1,1,1)
 make("UIGradient",edge,{Rotation=90,Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C.trimLight),
  ColorSequenceKeypoint.new(0.45,C.edge),ColorSequenceKeypoint.new(1,C.trimDark)})})
 return edge
end
-- Decorative children never take input or enlarge the existing HUD hit rectangles.
local function rule(parent,position,size,color,transparency,name)
 return make("Frame",parent,{Name=name or "BrassRule",Position=position,Size=size,BackgroundColor3=color or C.gold,
  BackgroundTransparency=transparency or 0.6,BorderSizePixel=0,Active=false})
end
local function inset(parent,size,position,name)
 local frame=make("Frame",parent,{Name=name or "InsetSurface",Size=size,Position=position,BackgroundColor3=C.inset,
  BackgroundTransparency=0.35,BorderSizePixel=0,Active=false})
 round(frame,5); stroke(frame,C.edge,0.7)
 return frame
end
local function heraldry(parent,size,position)
 local holder=make("Frame",parent,{Name="CastleSeal",Size=UDim2.fromOffset(size,size),Position=position,BackgroundTransparency=1,Active=false})
 local scale=make("UIScale",holder,{Scale=size/48}); holder.Size=UDim2.fromOffset(48,48)
 local shield=make("Frame",holder,{Size=UDim2.fromOffset(34,34),Position=UDim2.fromOffset(7,7),Rotation=45,
  BackgroundColor3=C.card,BorderSizePixel=0,Active=false})
 round(shield,4); stroke(shield,C.gold,0.28)
 local castle=rule(holder,UDim2.fromOffset(14,19),UDim2.fromOffset(20,15),C.gold,0.04,"CastleSilhouette")
 for i=0,2 do rule(holder,UDim2.fromOffset(14+i*8,14),UDim2.fromOffset(4,8),C.gold,0.04,"Merlon") end
 rule(holder,UDim2.fromOffset(21,25),UDim2.fromOffset(6,10),C.card,0,"Gate")
 return holder,scale,castle
end
local function panel(parent, size, position, name, class)
 local frame = make(class or "Frame", parent, {Name = name or "Panel", Size = size, Position = position,
  BackgroundColor3 = C.panel, BackgroundTransparency = 0, BorderSizePixel = 0, Active = true})
 round(frame,8); local edge=stroke(frame,C.edge,0); edge.Thickness=2.5; gild(edge); table.insert(GUI.hitAreas, frame)
 if class ~= "ScrollingFrame" then
  make("UIGradient",frame,{Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(226,211,182)),Rotation=90})
  -- A pale top edge and a soft lower shadow read as a sheet of paper set into a timber frame.
  rule(frame,UDim2.fromOffset(8,3),UDim2.new(1,-16,0,1),Color3.new(1,1,1),0.45,"PanelLightEdge")
  rule(frame,UDim2.new(0,8,1,-4),UDim2.new(1,-16,0,1),C.trimDark,0.72,"PanelLowerSeam")
 end
 return frame
end
-- Full-screen dimmers keep the panel hit area but drop the frame, bevel and tint.
local function scrim(frame)
 for _,name in ipairs({"UIStroke","UICorner","UIGradient"}) do
  local child=frame:FindFirstChildOfClass(name); if child then child:Destroy() end
 end
 for _,name in ipairs({"PanelLightEdge","PanelLowerSeam"}) do
  local child=frame:FindFirstChild(name); if child then child:Destroy() end
 end
 return frame
end
-- Dark title band with gilt diamonds; purely decorative and never takes input.
local function ribbon(parent,title,name)
 local band=make("Frame",parent,{Name=name or "TitleRibbon",Size=UDim2.new(1,-8,0,22),Position=UDim2.fromOffset(4,4),
  BackgroundColor3=C.ribbon,BackgroundTransparency=0,BorderSizePixel=0,Active=false})
 round(band,5)
 make("UIGradient",band,{Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(196,180,160)),Rotation=90})
 rule(band,UDim2.new(0,8,1,-2),UDim2.new(1,-16,0,1),L.gold,0.6,"RibbonUnderline")
 for _,side in ipairs({0,1}) do
  local gem=make("Frame",band,{Name="RibbonGem",Size=UDim2.fromOffset(6,6),AnchorPoint=Vector2.new(0.5,0.5),
   Position=UDim2.new(side,side==0 and 10 or -10,0.5,0),Rotation=45,BackgroundColor3=L.gold,BorderSizePixel=0,Active=false})
  gem.Visible=title~=nil
 end
 local label=text(band,title or "",UDim2.new(1,-40,1,0),UDim2.fromOffset(20,0),14,L.gold,Enum.Font.SourceSansBold)
 label.Name="RibbonTitle"; label.TextWrapped=false; label.TextTruncate=Enum.TextTruncate.AtEnd
 return band,label
end
-- 大廳按鈕可登記自己的配色；沒有登記的按鈕（戰場 HUD）維持羊皮紙主題。
local buttonPalettes = setmetatable({}, {__mode = "k"})
local function button(parent, size, position, callback, name)
 local b = make("TextButton", parent, {Name = name or "Action", Text = "", Size = size, Position = position,
  BackgroundColor3 = C.card, BorderSizePixel = 0, AutoButtonColor = false})
 round(b,6)
 local edge = stroke(b,C.edge,0.4); edge.Thickness=1.5
 make("UIGradient",b,{Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(230,216,188)),Rotation=90})
 local sheen=rule(b,UDim2.new(0,6,1,-2),UDim2.new(1,-12,0,1),C.trimDark,0.8,"ButtonLightEdge")
 local hovered,pressed,focused=false,false,false
 local function refresh(immediate)
  local unavailable=b:GetAttribute("Unavailable")==true
  local selected=b:GetAttribute("Selected")==true
  local primary=b:GetAttribute("Primary")==true
  local palette=buttonPalettes[b]
  local color=palette and (unavailable and (selected and palette.on:Lerp(palette.off,0.45) or palette.off)
   or pressed and palette.press or (hovered or focused) and palette.hover or (selected or primary) and palette.on or palette.base)
   or b:GetAttribute("AgeLocked") and Color3.fromRGB(176,176,176)
   or unavailable and Color3.fromRGB(226,216,196)
   or pressed and Color3.fromRGB(224,186,110)
   or (hovered or focused) and Color3.fromRGB(255,236,180)
   or (selected or primary) and Color3.fromRGB(244,210,128) or C.card
  if animations[b] then animations[b]:Cancel(); animations[b]=nil end
  if immediate or GUI.reducedMotion then b.BackgroundColor3=color else tween(b,0.1,{BackgroundColor3=color}) end
  if palette then
   edge.Transparency=unavailable and 0.45 or 0
   palette.gradient.Offset=pressed and Vector2.new(0,0.1) or Vector2.zero
   return
  end
  edge.Transparency=focused and 0 or pressed and 0.05 or hovered and 0.1 or unavailable and 0.75 or 0.35
  sheen.BackgroundTransparency=pressed and 1 or unavailable and 0.92 or 0.8
 end
 b.MouseEnter:Connect(function() hovered=UIS.MouseEnabled; refresh(false) end)
 b.MouseLeave:Connect(function() hovered=false; pressed=false; refresh(false) end)
 b.InputBegan:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA then pressed=true; refresh(true) end
 end)
 b.InputEnded:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA then pressed=false; refresh(false) end
 end)
 b.SelectionGained:Connect(function() focused=true; refresh(true) end)
 b.SelectionLost:Connect(function() focused=false; pressed=false; refresh(true) end)
 for _,attribute in ipairs({"Unavailable","AgeLocked","Selected","Primary","LobbySkin"}) do b:GetAttributeChangedSignal(attribute):Connect(function() refresh(true) end) end
 b.Activated:Connect(function(...)
  if GuiService.MenuIsOpen then return end
  if GUI.result and GUI.result.Visible and not b:IsDescendantOf(GUI.result) then return end
  if GUI.deleteConfirm and GUI.deleteConfirm.Visible and not b:IsDescendantOf(GUI.deleteConfirm) then return end
  if GUI.hotkeyPanel and GUI.hotkeyPanel.Visible and not b:IsDescendantOf(GUI.hotkeyPanel) then return end
  if GUI.menuPanel and GUI.menuPanel.Visible and not b:IsDescendantOf(GUI.menuPanel) and b.Name~="MenuButton" then return end
  if b.Name~="SoundButton" then Audio:Play("Click") end
  callback(...)
 end)
 return b,edge
end
local function namedButton(parent, label, size, position, callback, name, color)
 local b,edge = button(parent,size,position,callback,name)
 local title = text(b,label,UDim2.new(1,-14,1,0),UDim2.fromOffset(7,0),14,color or C.white,Enum.Font.SourceSansSemibold)
 title.TextXAlignment = Enum.TextXAlignment.Center
 return b,title,edge
end
-- Roblox 風格大廳：白色面板、深藍粗外框、FredokaOne 字體與帶底部厚度的糖果色按鈕。只套用在大廳，戰場 HUD 不變。
local LB = {text = Color3.fromRGB(33,38,58), muted = Color3.fromRGB(100,110,138), blue = Color3.fromRGB(0,132,230),
 green = Color3.fromRGB(24,160,72), gold = Color3.fromRGB(214,136,0), outline = Color3.fromRGB(27,31,48),
 line = Color3.fromRGB(196,206,224), panel = Color3.fromRGB(248,250,255), header = Color3.fromRGB(0,162,255), white = Color3.new(1,1,1)}
local LOBBY_TITLE_FONT, LOBBY_BODY_FONT = Enum.Font.FredokaOne, Enum.Font.GothamMedium
local function lobbyPalette(base, ink)
 return {base = base, hover = base:Lerp(Color3.new(1,1,1),0.18), press = base:Lerp(Color3.new(0,0,0),0.16), on = base,
  off = Color3.fromRGB(178,186,202), ink = ink or LB.white}
end
local LOBBY_PALETTES = {
 neutral = {base = Color3.new(1,1,1), hover = Color3.fromRGB(236,245,255), press = Color3.fromRGB(212,228,248),
  on = Color3.fromRGB(220,239,255), off = Color3.fromRGB(234,237,243), ink = LB.text},
 blue = lobbyPalette(Color3.fromRGB(0,162,255)), green = lobbyPalette(Color3.fromRGB(40,196,90)),
 red = lobbyPalette(Color3.fromRGB(240,78,78)), yellow = lobbyPalette(Color3.fromRGB(255,196,40),LB.text)}
local LOBBY_MODE_COLORS = {Story = Color3.fromRGB(255,170,30), PvP = Color3.fromRGB(240,78,78), PvE = Color3.fromRGB(40,190,96)}
-- 白字配深色描邊；深色字不加描邊。
local function lobbyText(label, color, font, outlined)
 if not label then return end
 label.TextColor3 = color; label.Font = font or LOBBY_BODY_FONT
 local outline = label:FindFirstChild("LobbyTextStroke")
 if outlined and not outline then outline = make("UIStroke",label,{Name = "LobbyTextStroke",Color = LB.outline,Thickness = 1.5,Transparency = 0.1}) end
 if outline then outline.Enabled = outlined == true end
end
local function lobbyPanel(frame, radius)
 for _,child in ipairs(frame:GetChildren()) do
  if child:IsA("UIStroke") or child:IsA("UIGradient") or child.Name == "PanelLightEdge" or child.Name == "PanelLowerSeam" then child:Destroy() end
 end
 local corner = frame:FindFirstChildOfClass("UICorner") or make("UICorner",frame)
 corner.CornerRadius = UDim.new(0,radius or 16)
 frame.BackgroundColor3 = LB.panel
 make("UIStroke",frame,{Name = "LobbyOutline",Color = LB.outline,Thickness = 3,ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
 make("UIGradient",frame,{Name = "LobbyShade",Rotation = 90,Color = ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(228,236,250))})
 return frame
end
-- 漸層底部較暗，形成按鈕厚度；按下時漸層下移，像被壓下去。lip 是厚度開始的位置（0–1）。
local function lobbyButton(b, palette, label, lip)
 local edge = b:FindFirstChildOfClass("UIStroke")
 if edge then edge.Color = LB.outline; edge.Thickness = 2.5 end
 local corner = b:FindFirstChildOfClass("UICorner"); if corner then corner.CornerRadius = UDim.new(0,10) end
 local sheen = b:FindFirstChild("ButtonLightEdge"); if sheen then sheen.Visible = false end
 local gradient = b:FindFirstChildOfClass("UIGradient")
 lip = lip or 0.86
 gradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),ColorSequenceKeypoint.new(lip-0.02,Color3.fromRGB(238,238,238)),
  ColorSequenceKeypoint.new(lip,Color3.fromRGB(186,186,186)),ColorSequenceKeypoint.new(1,Color3.fromRGB(186,186,186))})
 buttonPalettes[b] = {base = palette.base, hover = palette.hover, press = palette.press, on = palette.on, off = palette.off, gradient = gradient}
 b:SetAttribute("LobbySkin",true)
 if label then lobbyText(label,palette.ink,LOBBY_TITLE_FONT,palette.ink == LB.white) end
end
local function buttonLabel(b) return b:FindFirstChildOfClass("TextLabel") end
-- Shared, asset-free art stays recognizable when the resource cards shrink.
local function resourceIcon(parent,key)
 local holder=SelectionIcons.Create(parent,key,UDim2.fromOffset(28,28),UDim2.fromOffset(6,7))
 holder.Name="ResourceIcon"
 return holder
end
local function previewColor(source)
 if not source then return player:GetAttribute("TeamColor") end
 local color=source:GetAttribute("TeamColor")
 if typeof(color)=="Color3" then return color end
 local ownerId=source:GetAttribute("OwnerId")
 for _,actor in ipairs(Players:GetPlayers()) do
  if actor.UserId==ownerId then return actor:GetAttribute("TeamColor") end
 end
 local actors=RS:FindFirstChild("RTSFactions")
 if actors then
  for _,actor in ipairs(actors:GetChildren()) do
   if (actor:GetAttribute("OwnerId") or actor:GetAttribute("UserId"))==ownerId then return actor:GetAttribute("TeamColor") end
  end
 end
 return nil
end
local function viewport(parent, kind, size, position, source, stage)
 local view = make("ViewportFrame",parent,{Size = size,Position = position,BackgroundTransparency = 1,
  Ambient = Color3.fromRGB(157,165,157),LightColor = Color3.fromRGB(255,236,206),LightDirection = Vector3.new(-1,-1.3,-0.6),Active = false})
 local world = make("WorldModel",view)
 local model = Art.Create(kind,previewColor(source),nil,stage); model.Parent = world
 local cf,bounds = model:GetBoundingBox()
 local radius = math.max(bounds.X,bounds.Y,bounds.Z,4)
 local camera = make("Camera",view,{FieldOfView = 36,
  CFrame = CFrame.lookAt(cf.Position + Vector3.new(radius*1.15,radius*0.8,radius*1.4),cf.Position)})
 view.CurrentCamera = camera
 return view
end
local function previewStage(parent,size,position)
 local stage=inset(parent,size,position,"PreviewStage")
 stage.BackgroundColor3=Color3.new(1,1,1); stage.BackgroundTransparency=0
 make("UIGradient",stage,{Color=ColorSequence.new(Color3.fromRGB(214,226,214),Color3.fromRGB(154,178,128)),Rotation=90})
 rule(stage,UDim2.new(0,6,1,-3),UDim2.new(1,-12,0,1),C.edge,0.48,"StageFloor")
 return stage
end
local function visibleInTree(object)
 while object do
  if object:IsA("GuiObject") and not object.Visible then return false end
  if object:IsA("ScreenGui") and not object.Enabled then return false end
  object = object.Parent
 end
 return true
end
local function ageName(age)
 local data = Config.Ages and Config.Ages[age]
 return data and data.name or ({"黑暗時代","封建時代","城堡時代","帝王時代"})[age] or "黑暗時代"
end
local function mapSize() return workspace:GetAttribute("MapSize") or Config.Map.MapSize end
local function factions()
 local result = {}
 for _,human in ipairs(Players:GetPlayers()) do table.insert(result,{actor = human,name = human.DisplayName,id = human.UserId,ai = false}) end
 local folder = RS:FindFirstChild("RTSFactions")
 if folder then
  for _,actor in ipairs(folder:GetChildren()) do
   local id = actor:GetAttribute("OwnerId") or actor:GetAttribute("UserId")
   if type(id) == "number" and id < 0 then table.insert(result,{actor = actor,name = actor:GetAttribute("DisplayName") or actor.Name,id = id,ai = true}) end
  end
 end
 table.sort(result,function(a,b) if a.ai ~= b.ai then return not a.ai end return a.id > b.id end)
 return result
end
local function affordable(cost)
 for key,value in pairs(cost or {}) do if (player:GetAttribute(key) or 0) < value then return false end end
 return true
end
local function researched(key) return player:GetAttribute("Tech_"..key) == true or player:GetAttribute(key) == true end
local function compactCost(cost)
 local pieces = {}
 local names = {food = "食",wood = "木",gold = "金",stone = "石"}
 for _,key in ipairs({"food","wood","gold","stone"}) do if cost[key] then table.insert(pieces,names[key]..cost[key]) end end
 return table.concat(pieces," · ")
end
-- Price chips: one resource pictogram per amount, each turning red when that resource is short.
-- Costs too wide for the card keep the compact text underneath.
local function costChips(parent,cost,label,width,iconSize)
 local needed=0
 for _,key in ipairs({"food","wood","gold","stone"}) do
  if cost[key] then needed+=iconSize+4+#tostring(cost[key])*label.TextSize*0.55 end
 end
 if needed==0 or needed>width then return nil end
 local holder=make("Frame",parent,{Name="CommandCostChips",Size=label.Size,Position=label.Position,BackgroundTransparency=1,Active=false,Visible=false})
 make("UIListLayout",holder,{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Center,
  VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,2),SortOrder=Enum.SortOrder.LayoutOrder})
 local labels={}
 for index,key in ipairs({"food","wood","gold","stone"}) do
  if cost[key] then
   SelectionIcons.Create(holder,key,UDim2.fromOffset(iconSize,iconSize)).LayoutOrder=index*2-1
   local value=text(holder,tostring(cost[key]),UDim2.fromOffset(0,iconSize+2),UDim2.fromOffset(0,0),label.TextSize,C.muted)
   value.Name="Cost_"..key; value.AutomaticSize=Enum.AutomaticSize.X; value.TextWrapped=false; value.LayoutOrder=index*2
   labels[key]=value
  end
 end
 return holder,labels
end
local function selectedBuilders(selected)
 return Building:HasBuilders(selected)
end
-- 未選任何目標時也開啟建築選單；放置後由伺服器派最近的村民施工。
local function buildMenuAvailable(selected)
 return selectedBuilders(selected) or (#selected==0 and Building:CanAutoBuild())
end
local function formationSelection(selected)
 local folder=workspace:FindFirstChild("Units")
 if #selected==0 or #selected>Config.Formations.maxSelectedUnits then return nil end
 local current
 for _,unit in ipairs(selected) do
  if unit.Parent~=folder or unit:GetAttribute("OwnerId")~=player.UserId or not Config.Units[unit:GetAttribute("UnitType")] then return nil end
  local key=unit:GetAttribute("Formation") or Config.Formations.default
  if not Config.Formations.types[key] then key=Config.Formations.default end
  if current and current~=key then current="Mixed" else current=current or key end
 end
 return current
end
local function formationIcon(parent,key,width)
 local patterns={Box={{-1,-1},{0,-1},{1,-1},{-1,0},{0,0},{1,0},{-1,1},{0,1},{1,1}},
  Line={{-2,0},{-1,0},{0,0},{1,0},{2,0}},Column={{0,-2},{0,-1},{0,0},{0,1},{0,2}},
  Wedge={{0,-1},{-1,0},{1,0},{-2,1},{2,1}},Spread={{-2,-1},{0,-1},{2,-1},{-2,1},{0,1},{2,1}}}
 local holder=make("Frame",parent,{Size=UDim2.fromOffset(50,32),Position=UDim2.fromOffset((width-50)/2,3),BackgroundTransparency=1})
 for _,point in ipairs(patterns[key]) do
  local dot=make("Frame",holder,{Size=UDim2.fromOffset(5,5),Position=UDim2.fromOffset(23+point[1]*9,14+point[2]*6),BackgroundColor3=C.gold,BorderSizePixel=0})
  round(dot,2)
 end
 return holder
end
-- Pictogram per technology: what it improves, not a generic scroll.
local techIcons={Loom="armor",Forging="attack",Armor="armor",Wheelbarrow="cart",HandCart="cart",DoubleBitAxe="axe",BowSaw="axe",
 HorseCollar="food",HeavyPlow="food",Fletching="range",BodkinArrow="range",ThumbRing="interval",Chemistry="flask",GoldMining="gold",
 StoneMining="stone",Bloodlines="heart",ScaleBarding="armor",Squires="speed",Fervor="speed",Sanctity="heart",Conscription="population",
 Masonry="armor",Architecture="armor",TreadmillCrane="hammer",GuardTower="range",TownWatch="flag",HerbalMedicine="heart",Coinage="gold",Banking="gold",Caravan="cart"}
-- 姿態按鈕的圖示。
local stanceIcons={Aggressive="attack",Defensive="armor",StandGround="flag",NoAttack="stop"}
-- 可進貢的盟友：分隊或合作模式中同隊、仍在場上的其他陣營。
local function tributeAllies()
 local result={}
 local team=player:GetAttribute("TeamId")
 if team==nil or (workspace:GetAttribute("TeamMode") or "FFA")=="FFA" then return result end
 for _,faction in ipairs(factions()) do
  local actor=faction.actor
  if faction.id~=player.UserId and actor:GetAttribute("TeamId")==team and actor:GetAttribute("Defeated")~=true
   and actor:GetAttribute("Spectator")~=true and actor:GetAttribute("InLobby")~=true then table.insert(result,faction) end
 end
 return result
end
-- 所選單位目前的姿態；沒有可切換姿態的單位時為 nil，姿態不同時為 "Mixed"。
local function stanceSelection(selected)
 local current
 for _,unit in ipairs(selected) do
  local key=unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("Stance")
  if key then
   if current and current~=key then return "Mixed" end
   current=key
  end
 end
 return current
end
-- 可駐紮的己方完工建築：駐軍人數與每次射擊多出的箭數。
local function garrisonText(model)
 local capacity=model:GetAttribute("GarrisonCapacity") or 0
 if capacity<=0 or model:GetAttribute("OwnerId")~=player.UserId or model:GetAttribute("Complete")==false then return nil end
 local arrows=model:GetAttribute("GarrisonArrows") or 0
 return "駐軍 "..(model:GetAttribute("Garrison") or 0).." / "..capacity..(arrows>0 and (" · 多射 "..arrows.." 箭") or "")
end
local function commandSymbol(parent,action,width)
 local holder=make("Frame",parent,{Size=UDim2.fromOffset(width,37),BackgroundTransparency=1,Active=false})
 local center=width/2
 local function badge(symbol)
  local mark=text(holder,symbol,UDim2.fromOffset(16,18),UDim2.fromOffset(center+9,17),17,C.gold,Enum.Font.SourceSansBold)
  mark.Name="SymbolBadge"; mark.TextXAlignment=Enum.TextXAlignment.Center
 end
 if action.tech then
  SelectionIcons.Create(holder,techIcons[action.key] or "scroll",UDim2.fromOffset(30,30),UDim2.fromOffset(center-15,4)).Name="ResearchIcon"
  badge("+")
 elseif action.key:match("^Buy_") or action.key:match("^Sell_") then
  local key=action.key:match("_(.+)$")
  local icon=resourceIcon(holder,key); icon.Position=UDim2.fromOffset(center-16,3)
  badge(action.key:match("^Buy_") and "+" or "−")
 elseif action.resource then
  local icon=resourceIcon(holder,action.resource); icon.Position=UDim2.fromOffset(center-16,3)
  if action.symbol then badge(action.symbol) end
 elseif action.icon then
  SelectionIcons.Create(holder,action.icon,UDim2.fromOffset(30,30),UDim2.fromOffset(center-15,4)).Name="OrderIcon"
  if action.symbol then badge(action.symbol) end
 elseif action.key=="Stop" then
  SelectionIcons.Create(holder,"stop",UDim2.fromOffset(28,28),UDim2.fromOffset(center-14,5)).Name="StopMark"
 else
  SelectionIcons.Create(holder,"scroll",UDim2.fromOffset(28,28),UDim2.fromOffset(center-14,5)).Name="OrderIcon"
  if action.symbol then badge(action.symbol) end
 end
 return holder
end
local function deletable(model)
 if typeof(model)~="Instance" or not model:IsA("Model") or model:GetAttribute("RTSManaged")~=true or model:GetAttribute("OwnerId")~=player.UserId then return false end
 local hp=model:GetAttribute("HP")
 return type(hp)=="number" and Grid.isFinite(hp) and hp>0
  and ((model.Parent==workspace:FindFirstChild("Units") and Config.Units[model:GetAttribute("UnitType")]~=nil)
   or (model.Parent==workspace:FindFirstChild("Buildings") and Config.Buildings[model:GetAttribute("BuildingType")]~=nil))
end
local function deleteSelection(selected)
 if type(selected)~="table" or #selected==0 or #selected>200 then return nil end
 local result,seen={},{}
 for _,model in ipairs(selected) do
  if not deletable(model) then return nil end
  if not seen[model] then seen[model]=true; table.insert(result,model) end
 end
 return result
end
-- 單位是「死亡」、建築是「拆除」；兩種都選到時並列。
local function deleteLabel(selected)
 local units,structures=false,false
 for _,model in ipairs(type(selected)=="table" and selected or {}) do
  if model:GetAttribute("BuildingType") then structures=true else units=true end
 end
 return units and structures and "死亡／拆除" or structures and "拆除" or "死亡"
end
local function lobbyCommand(action, ...)
 local remotes = RS:FindFirstChild("RTSRemotes")
 local command = remotes and remotes:FindFirstChild("Command")
 if command then command:FireServer(action,...) end
end
local function lobbyRoomAttribute(roomId,key)
 local value=workspace:GetAttribute("LobbyRoom_"..roomId.."_"..key)
 if value~=nil or roomId~="Room1" then return value end
 local legacy={Players="LobbyPlayers",ExpectedPlayers="LobbyExpectedPlayers",HostUserId="HostUserId",SettingsRevision="LobbySettingsRevision",TeamPreviewReady="LobbyTeamPreviewReady"}
 local oldKey=legacy[key] or (key:match("^Setting_") and "Lobby"..key) or (key:match("^AITeam_") and "Lobby"..key)
 return oldKey and workspace:GetAttribute(oldKey) or nil
end
-- 每種玩法在設定精靈兩頁中顯示的欄位；劇情的戰場規則由章節決定，只顯示不能改。
local lobbyLayouts={
 Story={{"storyChapter","expectedPlayers"},{"size","aiCount","difficulty","population","startingResources","victory"}},
 PvP={{"expectedPlayers","teamMode"},{"size","population","startingResources","victory"}},
 PvE={{"expectedPlayers","aiCount","teamMode","difficulty"},{"size","population","startingResources","victory"}},
 Sandbox={{"expectedPlayers"},{"size","population","startingResources","victory"}},
}
local storyLocked={size=true,aiCount=true,difficulty=true,population=true,startingResources=true,victory=true}
local LOBBY_FIELD_TOP={152,64}
local function waitingInLobby()
 local inLobby=player:GetAttribute("InLobby")
 return inLobby==true or (inLobby==nil and workspace:GetAttribute("MatchPhase")=="Lobby")
end

function GUI:Init(callbacks)
 if self.screen then return self end
 self.callbacks = callbacks
 for name,value in pairs({SoundEnabled=true,SoundVolume=1,MusicEnabled=true,MusicVolume=0.7}) do
  if player:GetAttribute(name)==nil then player:SetAttribute(name,value) end
 end
 -- 熱鍵與其他設定一樣存在本機玩家屬性；內容無效時回到預設。
 self.hotkeys=HotkeyRules.parse(player:GetAttribute("Hotkeys"))
 -- 個人檔案載入後套用已保存的熱鍵；本場已經改過鍵就以玩家剛才的選擇為準。
 local function applySavedHotkeys()
  local saved=player:GetAttribute("SavedHotkeys")
  if self.hotkeysChanged or type(saved)~="string" then return end
  self.hotkeys=HotkeyRules.parse(saved); self.hotkeyCapture=nil
  player:SetAttribute("Hotkeys",HotkeyRules.serialize(self.hotkeys))
  if self.hotkeyRows then self:RefreshHotkeyLabels(); self:Update(self.selected or {},self.buildingKind) end
 end
 player:GetAttributeChangedSignal("SavedHotkeys"):Connect(applySavedHotkeys)
 applySavedHotkeys()
 local pg = player:WaitForChild("PlayerGui")
 local old = pg:FindFirstChild("AOE2_MainGUI"); if old then old:Destroy() end
 local oldTopbar=pg:FindFirstChild("AOE2_TopbarGUI"); if oldTopbar then oldTopbar:Destroy() end
 self.screen = make("ScreenGui",pg,{Name = "AOE2_MainGUI",ResetOnSpawn = false,IgnoreGuiInset = false,DisplayOrder=2,ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
 -- Roblox supplies the free space beside its own buttons, including changing device insets.
 self.topScreen=make("ScreenGui",pg,{Name="AOE2_TopbarGUI",ResetOnSpawn=false,ScreenInsets=Enum.ScreenInsets.TopbarSafeInsets,
  SafeAreaCompatibility=Enum.SafeAreaCompatibility.None,DisplayOrder=1,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,Enabled=false})
 self.canvas = make("Frame",self.screen,{Name = "Canvas",Size = UDim2.fromScale(1,1),BackgroundTransparency = 1})
 self.scale = make("UIScale",self.canvas,{Scale = 1})
 local function resize()
  local camera = workspace.CurrentCamera; if not camera then return end
  local width,height = self.screen.AbsoluteSize.X,self.screen.AbsoluteSize.Y
  if width<=0 or height<=0 then return end
  self.scale.Scale = self.touchLayout and 1 or math.max(0.2,math.min(1.1,width/1280,height/620))
  self.canvas.Size = UDim2.fromOffset(width/self.scale.Scale,height/self.scale.Scale)
  self.layoutWidth,self.layoutHeight = width/self.scale.Scale,height/self.scale.Scale
  if self.touchDock then self:LayoutTouch() end
  if self.backBuildCategories then self:LayoutBuildCategories() end
  if self.menuDock then self:LayoutTopbar() end
  if self.resultBody then self:LayoutResult() end
  if self.deleteBody then self:LayoutDeleteConfirm() end
  if self.hotkeyBody then self:LayoutHotkeyPanel() end
  if self.unitSelection then self:LayoutUnitSelection() end
  if self.lobby then self:LayoutLobby() end
 end
 self.resize = resize
 self.touchLayout = UIS.TouchEnabled
 resize()
 if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
 workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(resize)
 self.screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
 self.topScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
 GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(resize)
 self.topBar=panel(self.topScreen,UDim2.new(1,-8,1,-8),UDim2.fromOffset(4,4),"EmpireBar")
 self.topbarScale=make("UIScale",self.topBar,{Scale=1})
 self:CreateResourceBar()
 -- Age crest: numeral badge, age name, then the clock or the upgrade countdown.
 self.ageBlock=make("Frame",self.topBar,{Name="AgeBlock",Size=UDim2.fromOffset(210,46),BackgroundTransparency=1,Active=false})
 self.ageEmblem=make("Frame",self.ageBlock,{Name="AgeEmblem",Size=UDim2.fromOffset(26,26),AnchorPoint=Vector2.new(0.5,0.5),
  Position=UDim2.fromOffset(21,23),Rotation=45,BackgroundColor3=C.ribbon,BorderSizePixel=0,Active=false})
 round(self.ageEmblem,4)
 local emblemEdge=gild(stroke(self.ageEmblem,C.edge,0)); emblemEdge.Thickness=2
 self.ageNumeral=text(self.ageBlock,"I",UDim2.fromOffset(42,46),UDim2.fromOffset(0,0),15,L.gold,Enum.Font.Garamond)
 self.ageNumeral.Name="AgeNumeral"; self.ageNumeral.TextXAlignment=Enum.TextXAlignment.Center
 self.ageLabel = text(self.ageBlock,"黑暗時代",UDim2.fromOffset(160,22),UDim2.fromOffset(46,3),17,C.gold,Enum.Font.SourceSansBold)
 self.ageLabel.Name="AgeLabel"; self.ageLabel.TextWrapped=false; self.ageLabel.TextTruncate=Enum.TextTruncate.AtEnd
 self.clockLabel=text(self.ageBlock,"00:00",UDim2.fromOffset(160,16),UDim2.fromOffset(46,25),12,C.muted,NUMBER_FONT)
 self.clockLabel.Name="MatchClock"; self.clockLabel.TextWrapped=false
 self.ageTrack=make("Frame",self.ageBlock,{Name="AgeProgress",Size=UDim2.fromOffset(150,3),Position=UDim2.fromOffset(46,41),
  BackgroundColor3=C.inset,BorderSizePixel=0,Visible=false,Active=false})
 round(self.ageTrack,2)
 self.ageFill=make("Frame",self.ageTrack,{Name="Fill",Size=UDim2.fromScale(0,1),BackgroundColor3=C.gold,BorderSizePixel=0,Active=false})
 round(self.ageFill,2)
 -- Idle villagers: portrait, count badge and hotkey; the badge lights up when anyone waits.
 self.idleButton=button(self.topBar,UDim2.fromOffset(118,44),UDim2.fromOffset(622,7),function() if callbacks.selectIdle then callbacks.selectIdle() end end,"IdleVillagerButton")
 self.idleIcon=UnitIcons.Create(self.idleButton,"villager",UDim2.fromOffset(34,34),UDim2.fromOffset(4,5))
 self.idleIcon.Name="IdleVillagerIcon"
 self.idleLabel=text(self.idleButton,"閒置村民",UDim2.new(1,-46,0,18),UDim2.fromOffset(42,4),13,C.muted,Enum.Font.SourceSansSemibold)
 self.idleLabel.TextWrapped=false; self.idleLabel.TextTruncate=Enum.TextTruncate.AtEnd
 self.idleHotkey=text(self.idleButton,"按 [.] 選取",UDim2.new(1,-46,0,14),UDim2.fromOffset(42,23),11,C.muted)
 self.idleHotkey.Name="IdleHotkey"; self.idleHotkey.TextWrapped=false
 self.idleBadge=make("Frame",self.idleButton,{Name="IdleBadge",Size=UDim2.fromOffset(20,16),Position=UDim2.fromOffset(24,1),
  BackgroundColor3=C.red,BorderSizePixel=0,Visible=false,Active=false})
 round(self.idleBadge,8)
 self.idleCount=text(self.idleBadge,"0",UDim2.fromScale(1,1),UDim2.fromOffset(0,0),11,L.white,NUMBER_FONT)
 self.idleCount.Name="IdleCountLabel"; self.idleCount.TextXAlignment=Enum.TextXAlignment.Center
 local menu = make("Frame",self.topBar,{Name="MenuDock",Size=UDim2.fromOffset(66,46),Position=UDim2.new(1,-73,0,6),BackgroundTransparency=1,Active=false})
 self.menuDock = menu
 local menuButton,menuLabel=namedButton(menu,"☰  選單",UDim2.fromScale(1,1),UDim2.fromOffset(0,0),function() self:ToggleMenu() end,"MenuButton",C.gold)
 table.insert(self.hitAreas,menuButton); self.menuLabel=menuLabel
 local objective = panel(self.canvas,UDim2.fromOffset(230,78),UDim2.new(1,-246,0,8),"Objective")
 ribbon(objective,"領地與戰局")
 self.objective = text(objective,"建立經濟，發展軍隊\n消滅其他勢力取得勝利",UDim2.fromOffset(206,44),UDim2.fromOffset(12,29),13,C.white)
 self.objective.Name="MatchObjective"; self.objective.TextYAlignment=Enum.TextYAlignment.Top
 self.scoreboard = panel(self.canvas,UDim2.fromOffset(230,151),UDim2.new(1,-246,0,94),"Scoreboard")
 ribbon(self.scoreboard,"對戰勢力")
 self.scoreRows,self.scoreSwatches = {},{}
 for i = 1,4 do
  local y=32+(i-1)*28
  local swatch=make("Frame",self.scoreboard,{Name="FactionSwatch",Size=UDim2.fromOffset(4,20),Position=UDim2.fromOffset(10,y+3),
   BackgroundColor3=C.muted,BorderSizePixel=0,Visible=false,Active=false})
  round(swatch,2); self.scoreSwatches[i]=swatch
  self.scoreRows[i] = text(self.scoreboard,"",UDim2.fromOffset(196,26),UDim2.fromOffset(20,y),13,C.white)
  self.scoreRows[i].TextWrapped = false; self.scoreRows[i].TextTruncate = Enum.TextTruncate.AtEnd
 end
 self.menuPanel = panel(self.canvas,UDim2.fromOffset(218,166),UDim2.new(1,-234,0,8),"GameMenu","ScrollingFrame"); self.menuPanel.Visible = false; self.menuPanel.ZIndex=20
 self.menuPanel.CanvasSize=UDim2.fromOffset(0,504)
 self.menuPanel.ScrollingDirection=Enum.ScrollingDirection.Y
 self.menuPanel.ScrollBarThickness=4
 self.menuPanel.ScrollBarImageColor3=C.gold
 local menuRibbon=ribbon(self.menuPanel,"戰局選單"); menuRibbon.Size=UDim2.fromOffset(202,24); menuRibbon.Position=UDim2.fromOffset(8,8)
 namedButton(self.menuPanel,"繼續遊戲",UDim2.fromOffset(192,31),UDim2.fromOffset(13,39),function() self.menuPanel.Visible = false end,"ContinueButton")
 self.menuEndButton,self.menuEndLabel = namedButton(self.menuPanel,"投降",UDim2.fromOffset(192,31),UDim2.fromOffset(13,79),function()
  self.menuPanel.Visible = false
  if workspace:GetAttribute("MatchPhase") == "Ended" or player:GetAttribute("Defeated") then
   self.dismissedResult = nil; self:Update(self.selected or {},self.buildingKind)
  else callbacks.surrender() end
 end,"SurrenderButton",C.red)
 self.edgeButton,self.edgeLabel = namedButton(self.menuPanel,"邊緣移動：關閉",UDim2.fromOffset(192,31),UDim2.fromOffset(13,119),function()
  local enabled = player:GetAttribute("EdgeScroll") ~= true
  player:SetAttribute("EdgeScroll",enabled); self.edgeLabel.Text = "邊緣移動："..(enabled and "開啟" or "關閉")
 end,"EdgeScrollButton",C.muted)
 -- 自動工作由伺服器決定；按鈕只送出偏好，標籤跟隨伺服器回寫的屬性。
 self.autoWorkButton,self.autoWorkLabel = namedButton(self.menuPanel,"自動工作：開啟",UDim2.fromOffset(192,31),UDim2.fromOffset(13,119),function()
  if callbacks.autoWork then callbacks.autoWork(player:GetAttribute("AutoWork")==false) end
 end,"AutoWorkButton",C.green)
 local function autoWorkLabel() self.autoWorkLabel.Text="自動工作："..(player:GetAttribute("AutoWork")==false and "關閉" or "開啟") end
 player:GetAttributeChangedSignal("AutoWork"):Connect(autoWorkLabel)
 autoWorkLabel()
 namedButton(self.menuPanel,"熱鍵設定",UDim2.fromOffset(192,31),UDim2.fromOffset(13,119),function() self:OpenHotkeys() end,"HotkeyButton",C.gold)
 self.noticePanel = panel(self.canvas,UDim2.fromOffset(554,42),UDim2.new(0.5,-277,0,95),"Notice"); self.noticePanel.Visible = false
 self.noticePanel.ZIndex = 40; self.noticePanel.BackgroundColor3 = C.ribbon
 for _,side in ipairs({0,1}) do
  make("Frame",self.noticePanel,{Name="NoticeGem",Size=UDim2.fromOffset(7,7),AnchorPoint=Vector2.new(0.5,0.5),
   Position=UDim2.new(side,side==0 and 14 or -14,0.5,0),Rotation=45,BackgroundColor3=L.gold,BorderSizePixel=0,Active=false})
 end
 self.notice = text(self.noticePanel,"",UDim2.new(1,-48,1,0),UDim2.fromOffset(24,0),16,L.gold,Enum.Font.SourceSansSemibold); self.notice.TextXAlignment = Enum.TextXAlignment.Center
 -- Selection controls live in the command dock; the former center panel is open terrain.
 self.bottom = panel(self.canvas,UDim2.fromOffset(608,220),UDim2.new(0,16,1,-242),"CommandDock")
 self.commandSurface=inset(self.bottom,UDim2.fromOffset(582,148),UDim2.fromOffset(13,35),"CommandSurface")
 self.dockHeader=make("Frame",self.bottom,{Name="DockHeaderBand",Size=UDim2.new(1,-8,0,28),Position=UDim2.fromOffset(4,4),
  BackgroundColor3=C.inset,BackgroundTransparency=0.3,BorderSizePixel=0,Active=false})
 round(self.dockHeader,5)
 rule(self.bottom,UDim2.fromOffset(14,32),UDim2.new(1,-28,0,1),C.gold,0.5,"CommandHeaderRule")
 rule(self.bottom,UDim2.fromOffset(14,183),UDim2.new(1,-28,0,1),C.edge,0.5,"CommandFooterRule")
 self.deleteButton,self.deleteButtonLabel=namedButton(self.bottom,"死亡 [Del]",UDim2.fromOffset(96,25),UDim2.fromOffset(198,5),function() if callbacks.requestDelete then callbacks.requestDelete() end end,"DeleteButton",C.red)
 self.deleteButton.Visible=false
 self.details = text(self.bottom,"",UDim2.fromOffset(272,63),UDim2.fromOffset(320,112),13,C.muted); self.details.TextYAlignment = Enum.TextYAlignment.Top
 self.details.Name="TargetDetails"
 self.selectionState=text(self.bottom,"",UDim2.fromOffset(300,21),UDim2.fromOffset(16,110),13,C.gold,Enum.Font.SourceSansSemibold)
 self.selectionState.Name="ConstructionState"; self.selectionState.Visible=false
 self.healthBack = make("Frame",self.bottom,{Name="SelectionHealth",Size = UDim2.fromOffset(272,3),Position = UDim2.fromOffset(320,179),BackgroundColor3 = C.card,BorderSizePixel = 0})
 self.healthFill = make("Frame",self.healthBack,{Size = UDim2.fromScale(1,1),BackgroundColor3 = C.green,BorderSizePixel = 0})
 self.productionBack = make("Frame",self.bottom,{Name = "ProductionProgress",Size = UDim2.fromOffset(300,3),Position = UDim2.fromOffset(16,176),BackgroundColor3 = C.card,BorderSizePixel = 0,Visible = false})
 self.productionFill = make("Frame",self.productionBack,{Size = UDim2.fromScale(0,1),BackgroundColor3 = C.gold,BorderSizePixel = 0})
 self.productionText=text(self.bottom,"",UDim2.fromOffset(300,21),UDim2.fromOffset(16,138),12,C.gold)
 self.productionText.Name="ConstructionProgressText"; self.productionText.Visible=false
 self.healthText = text(self.bottom,"",UDim2.fromOffset(272,18),UDim2.fromOffset(320,159),12,C.muted)
 self.queueHolder=make("Frame",self.bottom,{Name="ProductionQueue",Size=UDim2.fromOffset(300,40),Position=UDim2.fromOffset(16,133),BackgroundTransparency=1})
 self.statLine=text(self.bottom,"",UDim2.fromOffset(272,20),UDim2.fromOffset(320,138),12,C.gold)
 self.context = text(self.bottom,"建 造 與 指 令",UDim2.fromOffset(178,23),UDim2.fromOffset(14,7),14,C.gold,Enum.Font.SourceSansSemibold)
 self.context.TextWrapped=false; self.context.TextTruncate=Enum.TextTruncate.AtEnd
 self.context.Name="TargetContext"
 self.mobileState=text(self.bottom,"",UDim2.new(1,-24,0,44),UDim2.fromOffset(12,126),14,C.gold)
 self.mobileState.Name="TouchSelectionState"; self.mobileState.Visible=false
 self.tabButtons = {}
 for i,entry in ipairs({{"build","建築 [B]"},{"train","生產 [T]"},{"research","科技 [R]"}}) do
  local b,label,edge = namedButton(self.bottom,entry[2],UDim2.fromOffset(90,23),UDim2.fromOffset(304+(i-1)*96,7),function() self:SetTab(entry[1]) end,"Tab_"..entry[1],C.muted)
  self.tabButtons[entry[1]] = {button = b,label = label,edge = edge}
 end
 self.buildPageButtons = {}
 local categoryArt={economy="TownCenter",military="Barracks",defense="Castle"}
 local categoryHints={economy="採集 · 發展 · 人口",military="訓練 · 軍備 · 科技",defense="城牆 · 塔樓 · 要塞"}
 for i,entry in ipairs(Config.BuildPages) do
  local b,label,edge = namedButton(self.bottom,entry.name,UDim2.fromOffset(182,100),UDim2.fromOffset(13+(i-1)*196,62),function() self:SetBuildPage(i) end,"BuildPage_"..entry.key,C.gold)
  local stage=previewStage(b,UDim2.fromOffset(166,53),UDim2.fromOffset(8,5))
  local modelView=viewport(b,categoryArt[entry.key] or entry.buildings[1],UDim2.fromOffset(166,56),UDim2.fromOffset(8,2))
  modelView.Name="CategoryModel"
  label.Position=UDim2.fromOffset(10,58); label.Size=UDim2.new(1,-30,0,23); label.TextSize=18; label.TextXAlignment=Enum.TextXAlignment.Left
  local detail=text(b,categoryHints[entry.key] or "選擇建築",UDim2.new(1,-20,0,15),UDim2.fromOffset(10,80),11,C.muted)
  local arrow=text(b,"›",UDim2.fromOffset(18,23),UDim2.new(1,-26,0,58),22,C.gold); arrow.TextXAlignment=Enum.TextXAlignment.Center
  b.Visible=false; self.buildPageButtons[i]={button=b,label=label,edge=edge,stage=stage,view=modelView,detail=detail,arrow=arrow,art=categoryArt[entry.key] or entry.buildings[1]}
 end
 self.categoryPreviewColor=tostring(previewColor())
 self.buildCategoryHint=text(self.bottom,"選擇建造分類",UDim2.fromOffset(582,20),UDim2.fromOffset(13,36),14,C.muted)
 self.buildCategoryHint.Name="BuildCategoryHint"; self.buildCategoryHint.Visible=false
 self.buildCategoryTitle=text(self.bottom,"",UDim2.fromOffset(124,23),UDim2.fromOffset(304,7),14,C.gold)
 self.buildCategoryTitle.Name="BuildCategoryTitle"; self.buildCategoryTitle.Visible=false
 self.backBuildCategories=namedButton(self.bottom,"‹ 返回分類",UDim2.fromOffset(156,23),UDim2.fromOffset(438,7),function() self:ShowBuildCategories() end,"BackBuildCategories",C.gold)
 self.backBuildCategories.Visible=false
 self.commandHolder = make("ScrollingFrame",self.bottom,{Name = "Commands",Size = UDim2.fromOffset(582,144),Position = UDim2.fromOffset(13,36),BackgroundTransparency = 1,
  BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),ScrollBarThickness=0,ScrollingEnabled=false,ScrollingDirection=Enum.ScrollingDirection.X})
 self.commandEntries,self.buildButtons = {},{}
 self.buildHelp = text(self.bottom,"選取村民，再右鍵點擊資源開始採集",UDim2.fromOffset(378,25),UDim2.fromOffset(14,187),12,C.muted)
 self.buildHelp.Name="TargetHelp"
 self.buildHelp.TextWrapped=false; self.buildHelp.TextTruncate=Enum.TextTruncate.AtEnd
 self.previousPage = namedButton(self.bottom,"‹",UDim2.fromOffset(27,26),UDim2.fromOffset(390,187),function() self:ChangePage(-1) end,"PreviousPage",C.gold)
 self.pageLabel = text(self.bottom,"1 / 1",UDim2.fromOffset(48,25),UDim2.fromOffset(420,187),12,C.muted); self.pageLabel.TextXAlignment = Enum.TextXAlignment.Center; self.pageLabel.Name="CommandPageLabel"
 self.nextPage = namedButton(self.bottom,"›",UDim2.fromOffset(27,26),UDim2.fromOffset(471,187),function() self:ChangePage(1) end,"NextPage",C.gold)
 self.stopButton,self.stopLabel = namedButton(self.bottom,"停止 [X]",UDim2.fromOffset(82,26),UDim2.fromOffset(512,187),callbacks.stop,"StopButton",C.muted)
 self.formationButton,self.formationLabel=namedButton(self.bottom,"陣形 [F]",UDim2.fromOffset(82,26),UDim2.fromOffset(300,187),function() self:SetTab("formation") end,"FormationButton",C.gold)
 self.garrisonButton,self.garrisonLabel,self.garrisonEdge=namedButton(self.bottom,"駐紮 [G]",UDim2.fromOffset(82,26),UDim2.fromOffset(214,187),function() if callbacks.garrison then callbacks.garrison() end end,"GarrisonButton",C.gold)
 self.garrisonButton.Visible=false
 self.formationButton.Visible=false
 self.tooltip = make("Frame",self.bottom,{Name = "CommandTooltip",Size = UDim2.fromOffset(476,100),Position = UDim2.fromOffset(72,-108),Visible = false,BackgroundColor3 = C.panel,BackgroundTransparency = 0.04,BorderSizePixel = 0,ZIndex = 6})
 round(self.tooltip,6); gild(stroke(self.tooltip,C.gold,0)).Thickness=1.5
 self.tooltipText = text(self.tooltip,"",UDim2.new(1,-26,1,-14),UDim2.fromOffset(13,7),14,C.white)
 self.tooltipText.TextYAlignment = Enum.TextYAlignment.Top
 self.unitPanel=panel(self.canvas,UDim2.fromOffset(384,220),UDim2.new(0,638,1,-242),"UnitSelectionPanel")
 self.unitSelection=UnitSelectionPanel.new(self.unitPanel,{
  portrait=viewport,
  blocked=function() return self:IsModalOpen() end,
  select=function(unit,remove) if self.callbacks.selectUnit then self.callbacks.selectUnit(unit,remove) end end,
  tooltip=function(value) self.tooltip.Visible=value~=nil; if value then self.tooltipText.Text=value end end,
 })
 local mapFrame = panel(self.canvas,UDim2.fromOffset(230,220),UDim2.new(1,-246,1,-242),"MinimapPanel")
 self.mapPanel = mapFrame
 local _,mapTitle=ribbon(mapFrame,"戰術地圖"); mapTitle.Size=UDim2.fromOffset(100,22)
 self.mapMode="all"
 self.mapModeButton,self.mapModeLabel=namedButton(mapFrame,"全部",UDim2.fromOffset(46,23),UDim2.fromOffset(134,4),function()
  self.mapMode=({all="economy",economy="military",military="all"})[self.mapMode]
  self.mapModeLabel.Text=({all="全部",economy="經濟",military="軍事"})[self.mapMode]; self:UpdateMap()
 end,"MinimapFilter",C.muted)
 text(mapFrame,"N ↑",UDim2.fromOffset(28,22),UDim2.fromOffset(186,4),12,L.gold,Enum.Font.SourceSansBold).Name="MapNorth"
 self.map = make("TextButton",mapFrame,{Name = "Minimap",Text = "",AutoButtonColor = false,Size = UDim2.fromOffset(184,184),Position = UDim2.fromOffset(23,30),BackgroundColor3 = Color3.fromRGB(96,132,74),BorderSizePixel = 0,ClipsDescendants = true})
 round(self.map,4); stroke(self.map,C.trimDark,0)
 for i = 1,3 do
  make("Frame",self.map,{Size = UDim2.new(1,0,0,1),Position = UDim2.fromScale(0,i/4),BackgroundColor3 = C.muted,BackgroundTransparency = 0.86,BorderSizePixel = 0})
  make("Frame",self.map,{Size = UDim2.new(0,1,1,0),Position = UDim2.fromScale(i/4,0),BackgroundColor3 = C.muted,BackgroundTransparency = 0.86,BorderSizePixel = 0})
 end
 self.mapFocus = make("Frame",self.map,{Size = UDim2.fromOffset(32,24),AnchorPoint = Vector2.new(0.5,0.5),BackgroundTransparency = 1,ZIndex = 3}); stroke(self.mapFocus,C.white,0.15)
 self.map.Activated:Connect(function(input)
  local raw = input and input.UserInputType == Enum.UserInputType.Touch and Vector2.new(input.Position.X,input.Position.Y) or UIS:GetMouseLocation()
  local position = self:MinimapPosition(raw)
  if position then CameraFocus.Request(player,position) end
 end)
 -- Handle the GUI input here: world right-clicks deliberately remain blocked by the HUD.
 self.map.InputBegan:Connect(function(input)
  if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
  local position = self:MinimapPosition(UIS:GetMouseLocation())
  if position and self.callbacks.minimapMove then self.callbacks.minimapMove(position) end
 end)
 self.keyHelp = text(self.canvas,"WASD 移動 · 滾輪縮放 · Home 回基地 · 拖曳框選 · 右鍵下令／小地圖移動 · F 陣形 · Ctrl + 1–9 編隊 · . 閒置村民 · G 駐紮 · Del 死亡／拆除",UDim2.fromOffset(760,18),UDim2.new(0.5,-380,1,-20),11,L.white); self.keyHelp.TextXAlignment = Enum.TextXAlignment.Center
 self.keyHelp.Name="KeyHelp"; self.keyHelp.BackgroundColor3=C.ribbon; self.keyHelp.BackgroundTransparency=0.25; self.keyHelp.TextWrapped=false; round(self.keyHelp,9)
 self.dots = {}
 self.selectionBox = make("Frame",self.screen,{Name = "SelectionBox",Visible = false,BackgroundColor3 = C.green,BackgroundTransparency = 0.84,BorderSizePixel = 0,ZIndex = 8})
 make("UIStroke",self.selectionBox,{Color = Color3.fromRGB(190,236,170),Thickness = 1.5,Transparency = 0.05})
 self.hudLayer = make("Frame",self.canvas,{Name = "HUD",Size = UDim2.fromScale(1,1),BackgroundTransparency = 1})
 for _,child in ipairs(self.canvas:GetChildren()) do
  if child:IsA("GuiObject") and child ~= self.hudLayer and child ~= self.noticePanel then child.Parent = self.hudLayer end
 end
 self:CreateLobby(); self:CreateResult(); self:CreateGuidance(); self:CreateTouchDock(); self:CreateTouchRotate(); self:CreateDeleteConfirm(); self:CreateHotkeyPanel(); resize(); self:RefreshHotkeyLabels(); self:Update({},nil)
 if game:GetService("RunService"):IsStudio() then
  local probe=make("BindableFunction",self.screen,{Name="RTSInputProbe"})
  probe.OnInvoke=function(point)
   if typeof(point)~="Vector2" or not Grid.isFinite(point.X) or not Grid.isFinite(point.Y) then return nil end
   return {blocked=self:BlocksPointer(point),modal=self:IsModalOpen()==true}
  end
  local hudProbe=make("BindableFunction",self.screen,{Name="RTSHUDProbe"})
  hudProbe.OnInvoke=function(action,value)
   if action=="delete" then return self:RequestDelete() end
   if action=="cancelDelete" then self:CancelDelete(); return true end
   if action=="tab" and (value=="build" or value=="train" or value=="research" or value=="formation") then self:SetTab(value); return true end
   if action=="buildPage" and type(value)=="number" and value%1==0 and value>=1 and value<=#Config.BuildPages then self:SetBuildPage(value); return true end
   if action=="buildCategories" then self:ShowBuildCategories(); return true end
   if action=="page" and (value==1 or value==-1) then self:ChangePage(value); return true end
   if action=="lobbyPage" and (value==1 or value==2) and self.lobbyWizard then self:SetLobbyPage(value); return true end
   if action=="lobbyConfigureComplete" then return self:CompleteLobbySetup() end
   if action=="lobbyEdit" then return self:EditLobbySettings() end
   if action=="selectUnit" and type(value)=="number" and value%1==0 then
    local entry=self.unitSelection.entries[value]
    return entry and self.unitSelection:Select(entry.unit,false) or false
   end
   return {tab=self.tab,page=self.page,pageCount=self.pageCount,buildCategory=self.buildCategory,modal=self:IsModalOpen()==true,lobbyPage=self.lobbyPage,lobbyRoomId=self.lobbyRoomId}
  end
 end
 return self
end
local RESOURCE_ORDER = {"wood","food","gold","stone","population"}
local STOCKPILE = {"food","wood","gold","stone"}
local RESOURCE_NAMES = {food = "食物",wood = "木材",gold = "黃金",stone = "石材",population = "人口"}
local INCOME_WINDOW = 60
-- Each slot: medallion icon with a gatherer badge, name and recent income, then the stock value.
function GUI:CreateResourceBar()
 self.resourceValues,self.resourceCards,self.resourceWorkers,self.resourceLabels = {},{},{},{}
 self.resourceRates,self.resourceDeltas,self.resourceEdges = {},{},{}
 local bar = make("Frame",self.topBar,{Name = "ResourceBar",Size = UDim2.fromOffset(640,46),Position = UDim2.fromOffset(8,6),BackgroundTransparency = 1,Active = false})
 self.resourceBar = bar
 for i,key in ipairs(RESOURCE_ORDER) do
  local color=resourceColors[key]
  local card=make("Frame",bar,{Name="Resource_"..key,Size=UDim2.fromOffset(122,46),Position=UDim2.fromOffset((i-1)*128,0),
   BackgroundColor3=C.inset,BackgroundTransparency=0.28,BorderSizePixel=0,Active=true})
  round(card,5); self.resourceEdges[key]=stroke(card,color,0.72)
  table.insert(self.hitAreas,card)
  local accent=make("Frame",card,{Name="ResourceAccent",Size=UDim2.new(1,-12,0,2),Position=UDim2.new(0,6,1,-3),
   BackgroundColor3=key=="population" and C.ribbon or color,BackgroundTransparency=key=="population" and 0 or 0.5,BorderSizePixel=0,Active=false})
  round(accent,1)
  if key=="population" then
   local fill=make("Frame",accent,{Name="Fill",Size=UDim2.fromScale(0,1),BackgroundColor3=color,BorderSizePixel=0,Active=false})
   round(fill,1)
  end
  local medallion=make("Frame",card,{Name="ResourceIcon",Size=UDim2.fromOffset(34,34),Position=UDim2.fromOffset(4,6),
   BackgroundColor3=C.card,BorderSizePixel=0,Active=false})
  make("UICorner",medallion,{CornerRadius=UDim.new(0.5,0)})
  local ring=stroke(medallion,color,0.05); ring.Thickness=2
  SelectionIcons.Create(medallion,key,UDim2.fromScale(0.72,0.72),UDim2.fromScale(0.14,0.14)).Name="ResourceGlyph"
  local name=text(card,RESOURCE_NAMES[key],UDim2.fromOffset(60,14),UDim2.fromOffset(43,2),12,C.muted,Enum.Font.SourceSansSemibold)
  name.Name="ResourceName"; name.TextWrapped=false
  local rate=text(card,"",UDim2.fromOffset(60,14),UDim2.fromOffset(43,2),11,C.green,NUMBER_FONT)
  rate.Name="ResourceRate"; rate.TextXAlignment=Enum.TextXAlignment.Right; rate.TextWrapped=false
  local value=text(card,"—",UDim2.fromOffset(74,22),UDim2.fromOffset(43,19),19,C.white,NUMBER_FONT)
  value.Name="ResourceValue"; value.TextWrapped=false
  make("UITextSizeConstraint",value,{MinTextSize=10,MaxTextSize=19})
  local delta=text(card,"",UDim2.fromOffset(48,16),UDim2.fromOffset(43,19),12,C.green,NUMBER_FONT)
  delta.Name="ResourceDelta"; delta.TextWrapped=false; delta.TextTransparency=1; delta.ZIndex=card.ZIndex+2
  -- Gatherer count sits on the medallion's corner, like a unit-count pip.
  local badge=make("Frame",card,{Name="WorkerBadge",Size=UDim2.fromOffset(18,13),BackgroundColor3=C.ribbon,BorderSizePixel=0,Visible=false,Active=false,ZIndex=card.ZIndex+1})
  round(badge,6); stroke(badge,color,0.15)
  local workers=text(badge,"",UDim2.fromScale(1,1),UDim2.fromOffset(0,0),10,L.white,NUMBER_FONT)
  workers.Name="ResourceWorkers"; workers.TextXAlignment=Enum.TextXAlignment.Center; workers.TextWrapped=false; workers.ZIndex=badge.ZIndex
  self.resourceCards[key],self.resourceLabels[key],self.resourceValues[key] = card,name,value
  self.resourceRates[key],self.resourceDeltas[key] = rate,delta
  if key~="population" then self.resourceWorkers[key]=workers end
 end
 self.income,self.lastResources = {food={},wood={},gold={},stone={}},{}
end
function GUI:LayoutResourceCard(key,width,height,compact)
 local card=self.resourceCards[key]
 card.Size=UDim2.fromOffset(width,height)
 local iconSize=math.max(12,math.min(compact and 24 or 34,height-10))
 local iconTop=math.floor((height-iconSize)/2)
 card.ResourceIcon.Size=UDim2.fromOffset(iconSize,iconSize); card.ResourceIcon.Position=UDim2.fromOffset(4,iconTop)
 card.WorkerBadge.Position=UDim2.fromOffset(iconSize-10,iconTop+iconSize-9)
 local left=iconSize+9
 self.resourceLabels[key].Visible=not compact
 self.resourceLabels[key].Position=UDim2.fromOffset(left,2); self.resourceLabels[key].Size=UDim2.new(1,-left-4,0,14)
 self.resourceRates[key].Visible=not compact
 self.resourceRates[key].Position=UDim2.fromOffset(left,2); self.resourceRates[key].Size=UDim2.new(1,-left-5,0,14)
 local value=self.resourceValues[key]
 value.Position=UDim2.fromOffset(left,compact and math.floor((height-22)/2) or height-26)
 value.Size=UDim2.new(1,-left-3,0,22); value.TextSize=compact and 16 or 19
 card.ResourceAccent.Position=UDim2.new(0,6,1,-3); card.ResourceAccent.Size=UDim2.new(1,-12,0,2)
end
function GUI:PulseResource(key,change)
 if self.reducedMotion or not self.hudLayer or not self.hudLayer.Visible then return end
 local value,delta=self.resourceValues[key],self.resourceDeltas[key]
 local color=change>0 and C.green or C.red
 value.TextColor3=color; tween(value,0.7,{TextColor3=C.white})
 if not self.resourceLabels[key].Visible then return end
 local x=value.Position.X.Offset+math.min(value.TextBounds.X,value.AbsoluteSize.X)+4
 local y=value.Position.Y.Offset
 delta.Text=(change>0 and "+" or "−")..math.abs(change); delta.TextColor3=color
 delta.Position=UDim2.fromOffset(x,y+3); delta.TextTransparency=0
 tween(delta,0.9,{TextTransparency=1,Position=UDim2.fromOffset(x,y-5)})
end
-- Client-side display only: income is inferred from positive stock changes over the last minute.
function GUI:UpdateResources()
 local playing=workspace:GetAttribute("MatchPhase")=="Playing"
 local generation=workspace:GetAttribute("MatchGeneration")
 if not playing or self.incomeGeneration~=generation then
  self.incomeGeneration=generation; self.lastResources={}
  for _,key in ipairs(STOCKPILE) do table.clear(self.income[key]) end
 end
 local now=os.clock()
 for _,key in ipairs(STOCKPILE) do
  local amount=math.floor(player:GetAttribute(key) or 0)
  self.resourceValues[key].Text=tostring(amount)
  local previous=self.lastResources[key]
  if previous and amount~=previous then
   if amount>previous then table.insert(self.income[key],{time=now,amount=amount-previous}) end
   self:PulseResource(key,amount-previous)
  end
  self.lastResources[key]=playing and amount or nil
  local history,total=self.income[key],0
  while history[1] and now-history[1].time>INCOME_WINDOW do table.remove(history,1) end
  for _,entry in ipairs(history) do total+=entry.amount end
  self.resourceRates[key].Text=total>0 and ("+"..total.."/分") or ""
 end
 local population,cap=player:GetAttribute("Population") or 0,player:GetAttribute("PopulationCap") or 0
 local full=cap>0 and population>=cap
 local value,rate=self.resourceValues.population,self.resourceRates.population
 value.Text=string.format("%d / %d",population,cap)
 value.TextColor3=full and C.red or C.white
 rate.Text=full and "已滿" or (cap>0 and cap-population<=3 and "將滿" or "")
 rate.TextColor3=full and C.red or C.gold
 local ratio=cap>0 and math.clamp(population/cap,0,1) or 0
 local fill=self.resourceCards.population.ResourceAccent.Fill
 fill.Size=UDim2.fromScale(ratio,1)
 fill.BackgroundColor3=full and C.red or ratio>=0.85 and C.gold or resourceColors.population
 self.resourceEdges.population.Color=full and C.red or resourceColors.population
 self.resourceEdges.population.Transparency=full and 0.2 or 0.72
end
function GUI:LayoutUnitSelection()
 if not self.touchLayout then
  self.unitPanel.Size=UDim2.fromOffset(384,220); self.unitPanel.Position=UDim2.new(0,638,1,-242)
 else
  self.unitPanel.Size=UDim2.fromOffset(self.touchDock.Size.X.Offset,126)
  self.unitPanel.Position=self.touchDock.Position+UDim2.fromOffset(0,-132)
 end
end

function GUI:CreateLobby()
 self.settings = {gameMode="PvP",storyChapter=0,expectedPlayers = 2,size = "Medium",aiCount = 0,difficulty = "Normal",population = 100,startingResources = "Standard",victory = "Conquest",teamMode="FFA"}
 -- Only the visible surfaces catch input; the rest of the courtyard stays walkable.
 self.lobby = make("Frame",self.canvas,{Name = "LobbyLayer",Size = UDim2.fromScale(1,1),BackgroundTransparency = 1,ZIndex = 20,Active = false})
 self.lobbyWelcome = panel(self.lobby,UDim2.fromOffset(860,290),UDim2.new(0.5,-430,1,-302),"CourtyardWelcome")
 self.welcomeHeading=text(self.lobbyWelcome,"選擇玩法",UDim2.new(1,-36,0,32),UDim2.fromOffset(18,11),26,C.white,Enum.Font.SourceSansBold)
 self.welcomeDescription=text(self.lobbyWelcome,"快速開始會自動找房間；也可以走進庭院光圈，或選擇下方匹配點自訂房間。",UDim2.new(1,-36,0,25),UDim2.fromOffset(18,45),14,C.muted)
 self.queueSummary=text(self.lobbyWelcome,"",UDim2.new(1,-36,0,20),UDim2.fromOffset(18,181),12,C.muted)
 -- 快速開始只送出玩法；伺服器決定加入哪個房間或建立新房間。
 self.quickButtons={}
 for i,entry in ipairs({{id="StorySolo",mode="Story",title="單人劇情"},{id="Story",mode="Story",title="多人劇情"},{id="PvP",mode="PvP",title="玩家對戰"},{id="PvE",mode="PvE",title="合作對電腦"}}) do
  local b=button(self.lobbyWelcome,UDim2.fromOffset(196,64),UDim2.fromOffset(18+(i-1)*208,77),function()
   local quick=self.quickButtons[i]
   if waitingInLobby() and not self.lobbyStarting and quick.button:GetAttribute("Unavailable")~=true then lobbyCommand("QuickPlay",entry.id) end
  end,"QuickPlay_"..entry.id)
  local accent=Config.GameModes[entry.mode].accent or C.gold
  rule(b,UDim2.fromOffset(0,8),UDim2.new(0,4,1,-16),accent,0,"QuickAccent")
  local title=text(b,entry.title.."  ›",UDim2.new(1,-20,0,26),UDim2.fromOffset(12,6),17,C.white,Enum.Font.SourceSansBold)
  local detail=text(b,"",UDim2.new(1,-20,0,22),UDim2.fromOffset(12,34),12,C.muted)
  detail.TextWrapped=false; detail.TextTruncate=Enum.TextTruncate.AtEnd
  self.quickButtons[i]={button=b,title=title,detail=detail,entry=entry}
 end
 self.roomsHeading=text(self.lobbyWelcome,"自 訂 房 間",UDim2.new(1,-36,0,20),UDim2.fromOffset(18,150),13,C.gold,Enum.Font.SourceSansSemibold)
 self.portalCards={}
 for i,portal in ipairs(Config.Lobby.portals or {}) do
  local b,edge=button(self.lobbyWelcome,UDim2.fromOffset(196,98),UDim2.fromOffset(18+(i-1)*208,77),function()
   local entry=self.portalCards[portal.id]
   if waitingInLobby() and not self.lobbyStarting and entry and entry.button:GetAttribute("Unavailable")~=true then lobbyCommand("QueueJoin",portal.id) end
  end,"PortalCard_"..portal.id)
  b:SetAttribute("PortalId",portal.id)
  local accent=portal.color or C.gold
  local color=accent:Lerp(C.white,0.45)
  rule(b,UDim2.fromOffset(0,8),UDim2.new(0,4,1,-16),accent,0,"PortalAccent")
  local title=text(b,portal.name,UDim2.new(1,-43,0,27),UDim2.fromOffset(12,7),18,C.white,Enum.Font.SourceSansSemibold)
  local arrow=text(b,"›",UDim2.fromOffset(20,27),UDim2.new(1,-29,0,7),23,color)
  arrow.TextXAlignment=Enum.TextXAlignment.Center
  local detail=text(b,portal.description,UDim2.new(1,-24,0,34),UDim2.fromOffset(12,34),13,C.muted)
  detail.TextYAlignment=Enum.TextYAlignment.Top
  local status=text(b,"",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,72),12,color)
  self.portalCards[portal.id]={button=b,title=title,arrow=arrow,detail=detail,status=status,edge=edge,portal=portal}
  if i==1 then self.joinButton,self.joinLabel=b,title end
 end
 self.lobbyFrame = panel(self.lobby,UDim2.fromOffset(760,572),UDim2.new(0.5,-380,0.5,-286),"MatchLobby")
 self.lobbyFrame.Visible=false
 self.lobbySeal=heraldry(self.lobbyFrame,42,UDim2.fromOffset(17,14))
 self.lobbyHeading=text(self.lobbyFrame,"匹配房間",UDim2.new(1,-206,0,34),UDim2.fromOffset(72,13),28,C.white,Enum.Font.SourceSansBold)
 self.lobbyDescription=text(self.lobbyFrame,"先選模式與人數，再設定這場遊戲。",UDim2.new(1,-98,0,24),UDim2.fromOffset(72,47),14,C.muted)
 self.leaveButton = namedButton(self.lobbyFrame,"離開房間",UDim2.fromOffset(104,44),UDim2.new(1,-120,0,15),function()
  if waitingInLobby() and not self.lobbyStarting then lobbyCommand("QueueLeave") end
 end,"LeaveQueueButton",C.muted)
 self.wizardSteps=make("Frame",self.lobbyFrame,{Name="WizardSteps",Size=UDim2.new(1,-32,0,44),Position=UDim2.fromOffset(16,83),BackgroundTransparency=1,Active=false})
 self.lobbyStepButtons={}
 for i,name in ipairs({"選擇玩法","遊戲設定","等候玩家"}) do
  local b,label=namedButton(self.wizardSteps,i.."  "..name,UDim2.new(1/3,-5,1,0),UDim2.new((i-1)/3,0,0,0),function()
   if self.lobbyWizard and not self.lobbyStarting and not self.lobbyConfigurePending and i<3 then self:SetLobbyPage(i) end
  end,"Step_"..i)
  self.lobbyStepButtons[i]={button=b,label=label}
 end
 self.lobbyBody = make("ScrollingFrame",self.lobbyFrame,{Name="LobbyContent",Size=UDim2.new(1,-32,1,-234),Position=UDim2.fromOffset(16,140),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,336),ScrollBarThickness=4,ScrollingDirection=Enum.ScrollingDirection.Y,Active=true,ClipsDescendants=true})
 self.lobbyPages={}
 for i,name in ipairs({"BasicSettingsPage","AdvancedSettingsPage","ReadyReviewPage"}) do
  self.lobbyPages[i]=make("Frame",self.lobbyBody,{Name=name,Size=UDim2.new(1,-8,0,400),BackgroundTransparency=1,Active=false,Visible=i==1})
 end
 local basic,advanced,review=self.lobbyPages[1],self.lobbyPages[2],self.lobbyPages[3]
 self.basicHeading=text(basic,"這場怎麼玩？",UDim2.new(1,0,0,28),UDim2.fromOffset(0,0),21,C.white,Enum.Font.SourceSansSemibold)
 self.basicHint=text(basic,"選擇玩法，再決定人數與對手。",UDim2.new(1,0,0,25),UDim2.fromOffset(0,30),14,C.muted)
 self.advancedHeading=text(advanced,"遊戲設定",UDim2.new(1,0,0,28),UDim2.fromOffset(0,0),21,C.white,Enum.Font.SourceSansSemibold)
 self.advancedHint=text(advanced,"已有預設規則；可直接完成設定，或再調整這場遊戲。",UDim2.new(1,0,0,25),UDim2.fromOffset(0,30),14,C.muted)
 -- 三張玩法卡片；按下只送出提案，伺服器驗證後才會改變房間。
 self.modeCards={}
 for i,id in ipairs(GameModes.Order) do
  local data=Config.GameModes[id]
  local b,edge=button(basic,UDim2.new(1/3,-6,0,78),UDim2.new((i-1)/3,i==1 and 0 or 3,0,62),function()
   if not self.lobbyWizard or not waitingInLobby() or self.lobbyStarting or self.lobbyConfigurePending then self:Notify("玩法由房主決定。") return end
   if self.settings.gameMode==id then return end
   local request,message=GameModes.next(self.settings,"gameMode",{id},self.lobbyHumanCount or 0,self:StoryUnlocked())
   if not request then self:Notify(message or "目前人數不能切換到這個玩法。") return end
   self:Notify((message and message.."\n" or "")..GameModes.label(request).." · "..request.expectedPlayers.." 真人＋"..request.aiCount.." 電腦")
   lobbyCommand("LobbySettings",request)
  end,"ModeCard_"..id)
  rule(b,UDim2.fromOffset(0,8),UDim2.new(0,4,1,-16),data.accent or C.gold,0,"ModeAccent")
  local title=text(b,data.title,UDim2.new(1,-20,0,26),UDim2.fromOffset(12,5),17,C.white,Enum.Font.SourceSansBold)
  local detail=text(b,data.description,UDim2.new(1,-20,0,40),UDim2.fromOffset(12,31),12,C.muted)
  detail.TextYAlignment=Enum.TextYAlignment.Top
  self.modeCards[id]={button=b,edge=edge,title=title,detail=detail}
 end
 self.storyBriefing=text(basic,"",UDim2.new(1,-8,0,70),UDim2.fromOffset(4,264),14,C.white)
 self.storyBriefing.Name="StoryBriefing"; self.storyBriefing.TextYAlignment=Enum.TextYAlignment.Top
 local chapterNames,chapterValues={},{}
 for index,chapter in ipairs(Config.Story.chapters) do chapterNames[index]="第 "..index.." 章 · "..chapter.title; chapterValues[index]=index end
 local fields = {
  {key="storyChapter",label="劇情章節",values=chapterValues,names=chapterNames},
  {key="expectedPlayers",label="真人玩家",values={1,2,3,4},names={[1]="1 人",[2]="2 人",[3]="3 人",[4]="4 人"}},
  {key="teamMode",label="隊伍模式",values={"FFA","Teams","CoopAI"}},
  {key="size",label="戰場大小",values={"Small","Medium","Large"},names={Small="小型",Medium="標準",Large="大型"}},
  {key="aiCount",label="電腦對手",values={0,1,2,3},names={[0]="無",[1]="1 位電腦",[2]="2 位電腦",[3]="3 位電腦"}},
  {key="difficulty",label="電腦難度",values={"Easy","Normal","Hard"},names={Easy="簡單",Normal="普通",Hard="困難"}},
  {key="population",label="人口上限",values={60,100,150,200}},
  {key="startingResources",label="初始資源",values={"Standard","Rich"},names={Standard="標準經濟",Rich="豐富資源"}},
  {key="victory",label="勝利規則",values={"Conquest","Regicide","Wonder","Relic"},names={Conquest="征服",Regicide="主城決戰",Wonder="世界奇觀",Relic="聖物"}},
 }
 self.settingLabels = {}
 for _,field in ipairs(fields) do
  local caption=text(basic,field.label,UDim2.fromOffset(100,48),UDim2.fromOffset(6,0),15,C.muted)
  local b,label = namedButton(basic,"",UDim2.new(1,-126,0,48),UDim2.fromOffset(122,0),function()
   if not self.lobbyWizard or not waitingInLobby() or self.lobbyStarting or self.lobbyConfigurePending then self:Notify("戰局設定由房主決定。") return end
   local entry=self.settingLabels[field.key]
   if entry.locked then self:Notify("劇情章節已決定這項規則；換一章就能換規則。") return end
   local request,message = GameModes.next(self.settings,field.key,field.values,self.lobbyHumanCount or 0,self:StoryUnlocked())
   if not request then self:Notify(message or "目前設定沒有其他合法選項。") return end
   if field.key=="teamMode" or message then self:Notify((message and message.."\n" or "")..GameModes.label(request).." · "..request.expectedPlayers.." 真人＋"..request.aiCount.." 電腦；確認設定後重新準備。") end
   lobbyCommand("LobbySettings",request)
  end,"Setting_"..field.key)
  self.settingLabels[field.key] = {label = label,caption=caption,field = field,button = b}
  label.Font=Enum.Font.SourceSansSemibold
  rule(b,UDim2.new(1,-6,0.5,-3),UDim2.fromOffset(2,6),C.gold,0.7,"SettingIndicator")
 end
 local function selectCivilization()
  if not waitingInLobby() or self.lobbyStarting then return end
  local order=Config.CivilizationOrder or {}; if #order==0 then return end
  local index=table.find(order,player:GetAttribute("Civilization")) or 1
  lobbyCommand("SelectCivilization",order[index % #order+1])
 end
 self.civilizationButton,self.civilizationLabel = namedButton(review,"文明",UDim2.new(1,-8,0,44),UDim2.fromOffset(4,348),selectCivilization,"CivilizationButton",C.gold)
 self.reviewCivilizationButton,self.reviewCivilizationLabel=self.civilizationButton,self.civilizationLabel
 self.reviewStatus=text(review,"等候玩家",UDim2.new(1,-8,0,30),UDim2.fromOffset(4,0),21,C.white,Enum.Font.SourceSansSemibold)
 self.reviewSummary=text(review,"",UDim2.new(1,-8,0,49),UDim2.fromOffset(4,0),16,C.white,Enum.Font.SourceSansSemibold)
 self.rosterHeading = text(review,"集 合 名 單",UDim2.new(1,-142,0,22),UDim2.fromOffset(4,56),13,C.gold)
 self.readySummary=text(review,"準備 0 / 1",UDim2.fromOffset(124,22),UDim2.new(1,-132,0,56),13,C.muted)
 self.readySummary.TextXAlignment=Enum.TextXAlignment.Right
 self.lobbyRows = {}
 for i = 1,4 do
  local row = panel(review,UDim2.new(1,-8,0,44),UDim2.fromOffset(4,80+(i-1)*50),"LobbyFaction_"..i)
  rule(row,UDim2.fromOffset(1,8),UDim2.new(0,3,1,-16),C.edge,0.24,"RosterStateAccent")
  self.lobbyRows[i] = text(row,"",UDim2.new(1,-24,1,0),UDim2.fromOffset(12,0),15,C.white)
  self.lobbyRows[i].TextWrapped=false; self.lobbyRows[i].TextTruncate=Enum.TextTruncate.AtEnd
 end
 self.rules = text(review,"",UDim2.new(1,-8,0,56),UDim2.fromOffset(4,286),14,C.muted); self.rules.TextYAlignment = Enum.TextYAlignment.Top
 self.lobbyFooter=make("Frame",self.lobbyFrame,{Name="LobbyFooter",Size=UDim2.new(1,-32,0,86),Position=UDim2.new(0,16,1,-94),BackgroundTransparency=1,Active=false})
 rule(self.lobbyFooter,UDim2.fromOffset(0,0),UDim2.new(1,0,0,1),C.edge,0.44,"LobbyFooterRule")
 self.hostLabel = text(self.lobbyFooter,"",UDim2.new(1,0,0,30),UDim2.fromOffset(0,6),14,C.muted)
 self.previousLobbyPage=namedButton(self.lobbyFooter,"‹ 上一步",UDim2.fromOffset(110,44),UDim2.fromOffset(0,40),function()
  if self.lobbyWizard then self:SetLobbyPage(math.max(1,self.lobbyPage-1)) end
 end,"PreviousLobbyPage",C.muted)
 self.skipLobbyRules=namedButton(self.lobbyFooter,"沿用預設規則",UDim2.fromOffset(190,44),UDim2.fromOffset(118,40),function()
  if self.lobbyWizard then self:SetLobbyPage(2) end
 end,"UseDefaultRules",C.muted)
 self.nextLobbyPage,self.nextLobbyLabel=namedButton(self.lobbyFooter,"下一步：遊戲設定  ›",UDim2.fromOffset(240,44),UDim2.new(1,-240,0,40),function()
  if self.lobbyWizard and not self.lobbyConfigurePending then self:SetLobbyPage(2) end
 end,"NextLobbyPage",C.gold)
 self.nextLobbyPage:SetAttribute("Primary",true)
 self.completeLobbySetup,self.completeLobbyLabel=namedButton(self.lobbyFooter,"完成設定，等候玩家  ✓",UDim2.fromOffset(280,44),UDim2.new(1,-280,0,40),function()
  self:CompleteLobbySetup()
 end,"CompleteLobbySetup",C.gold)
 self.completeLobbySetup:SetAttribute("Primary",true)
 self.readyButton,self.readyLabel = namedButton(self.lobbyFooter,"準備完成",UDim2.fromOffset(250,44),UDim2.new(1,-510,0,40),function()
  if player:GetAttribute("LobbyQueued") and waitingInLobby() and not self.lobbyStarting and self.lobbyConfigured and not self.lobbyWizard then
   lobbyCommand("LobbyReady",player:GetAttribute("LobbyReady") ~= true,self.lobbyRevision)
  end
 end,"ReadyButton",C.green)
 self.readyButton:SetAttribute("Primary",true)
 self.editLobbyButton=namedButton(self.lobbyFooter,"修改設定",UDim2.fromOffset(130,44),UDim2.fromOffset(0,40),function() self:EditLobbySettings() end,"EditLobbySettings",C.muted)
 self.startingTravel=panel(self.lobby,UDim2.fromOffset(500,238),UDim2.new(0.5,-250,0.5,-119),"StartingTravel")
 self.startingTravel.Visible=false; self.startingTravel.ZIndex=25
 heraldry(self.startingTravel,48,UDim2.new(0.5,-24,0,22))
 local travelTitle=text(self.startingTravel,"前往全新戰場",UDim2.new(1,-36,0,38),UDim2.fromOffset(18,82),28,C.white,Enum.Font.SourceSansBold)
 travelTitle.TextXAlignment=Enum.TextXAlignment.Center
 self.travelStatus=text(self.startingTravel,"正在生成地圖與資源…",UDim2.new(1,-36,0,35),UDim2.fromOffset(18,128),16,C.gold)
 self.travelStatus.TextXAlignment=Enum.TextXAlignment.Center
 self.travelDetail=text(self.startingTravel,"隊伍已確認。戰場準備完成後會自動進入遊戲。",UDim2.new(1,-40,0,43),UDim2.fromOffset(20,173),14,C.muted)
 self.travelDetail.TextXAlignment=Enum.TextXAlignment.Center
 self.lobbyPage=1
 self:SkinLobby()
 self:LayoutLobby()
end
function GUI:SkinLobby()
 local P=LOBBY_PALETTES
 lobbyPanel(self.lobbyWelcome)
 lobbyText(self.welcomeHeading,LB.text,LOBBY_TITLE_FONT)
 lobbyText(self.welcomeDescription,LB.muted)
 lobbyText(self.queueSummary,LB.muted)
 lobbyText(self.roomsHeading,LB.blue,LOBBY_TITLE_FONT)
 for _,quick in ipairs(self.quickButtons) do
  lobbyButton(quick.button,lobbyPalette(LOBBY_MODE_COLORS[quick.entry.mode] or LB.header),quick.title,0.84)
  lobbyText(quick.detail,LB.white,LOBBY_BODY_FONT,true)
  local accent=quick.button:FindFirstChild("QuickAccent"); if accent then accent.Visible=false end
 end
 for _,entry in pairs(self.portalCards) do
  lobbyButton(entry.button,lobbyPalette(entry.portal.color or LB.header),entry.title,0.92)
  lobbyText(entry.detail,LB.white,LOBBY_BODY_FONT,true)
  for _,child in ipairs(entry.button:GetChildren()) do
   if child:IsA("TextLabel") and child.Text=="›" then lobbyText(child,LB.white,LOBBY_TITLE_FONT,true) end
  end
  local accent=entry.button:FindFirstChild("PortalAccent"); if accent then accent.Visible=false end
  -- 狀態做成深色膠囊，任何房間顏色上都看得清楚。
  local status=entry.status
  lobbyText(status,LB.white,Enum.Font.GothamBold)
  status.Size=UDim2.fromOffset(0,20); status.AutomaticSize=Enum.AutomaticSize.X; status.TextWrapped=false
  status.BackgroundColor3=LB.outline; status.BackgroundTransparency=0.45
  round(status,10)
  make("UIPadding",status,{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)})
 end
 for id,card in pairs(self.modeCards) do
  local palette=table.clone(P.neutral); palette.on=LOBBY_MODE_COLORS[id] or LB.header
  lobbyButton(card.button,palette,nil,0.88)
  lobbyText(card.title,LB.text,LOBBY_TITLE_FONT); lobbyText(card.detail,LB.muted)
  local accent=card.button:FindFirstChild("ModeAccent"); if accent then accent.BackgroundColor3=palette.on end
 end
 lobbyPanel(self.lobbyFrame)
 -- 房間面板頂部的藍色標題列；下半部用填色蓋掉圓角，與內容區平接。
 self.lobbyHeaderBand=make("Frame",self.lobbyFrame,{Name="LobbyHeaderBand",Size=UDim2.new(1,0,0,76),BackgroundColor3=LB.header,BorderSizePixel=0,ZIndex=0,Active=false})
 round(self.lobbyHeaderBand,16)
 make("Frame",self.lobbyHeaderBand,{Name="BandFill",Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,0,1,-16),BackgroundColor3=LB.header,BorderSizePixel=0,ZIndex=0,Active=false})
 lobbyText(self.lobbyHeading,LB.white,LOBBY_TITLE_FONT,true)
 lobbyText(self.lobbyDescription,Color3.fromRGB(226,242,255))
 self.lobbyBody.ScrollBarImageColor3=LB.blue
 for _,label in ipairs({self.basicHeading,self.advancedHeading,self.reviewStatus}) do lobbyText(label,LB.text,LOBBY_TITLE_FONT) end
 for _,label in ipairs({self.basicHint,self.advancedHint,self.readySummary,self.rules,self.hostLabel}) do lobbyText(label,LB.muted) end
 lobbyText(self.storyBriefing,LB.text)
 lobbyText(self.reviewSummary,LB.text,Enum.Font.GothamBold)
 lobbyText(self.rosterHeading,LB.blue,LOBBY_TITLE_FONT)
 for _,entry in pairs(self.settingLabels) do
  lobbyButton(entry.button,P.neutral,entry.label)
  lobbyText(entry.caption,LB.muted,Enum.Font.GothamBold)
  entry.button.SettingIndicator.BackgroundColor3=LB.blue
 end
 for _,entry in ipairs(self.lobbyStepButtons) do lobbyButton(entry.button,P.neutral,entry.label) end
 for b,palette in pairs({[self.leaveButton]=P.red,[self.previousLobbyPage]=P.neutral,[self.skipLobbyRules]=P.neutral,[self.editLobbyButton]=P.neutral,
  [self.nextLobbyPage]=P.blue,[self.completeLobbySetup]=P.blue,[self.readyButton]=P.green,[self.civilizationButton]=P.yellow}) do
  lobbyButton(b,palette,buttonLabel(b))
 end
 for _,label in ipairs(self.lobbyRows) do
  local row=lobbyPanel(label.Parent,10)
  row.LobbyOutline.Thickness=2; row.LobbyOutline.Color=LB.line
  lobbyText(label,LB.text,Enum.Font.GothamBold)
 end
 local footerRule=self.lobbyFooter:FindFirstChild("LobbyFooterRule"); if footerRule then footerRule.BackgroundColor3=LB.line end
 lobbyPanel(self.startingTravel)
 for _,child in ipairs(self.startingTravel:GetChildren()) do
  if child:IsA("TextLabel") then lobbyText(child,LB.text,LOBBY_TITLE_FONT) end
 end
 lobbyText(self.travelStatus,LB.blue,Enum.Font.GothamBold)
 lobbyText(self.travelDetail,LB.muted)
end
function GUI:SkinTutorialInvite()
 local P=LOBBY_PALETTES
 lobbyPanel(self.tutorialInvite)
 lobbyText(self.inviteTitle,LB.text,LOBBY_TITLE_FONT)
 lobbyText(self.inviteBody,LB.muted)
 lobbyButton(self.inviteStart,P.green,self.inviteStartLabel)
 lobbyButton(self.inviteSkip,P.neutral,self.inviteSkipLabel)
 lobbyButton(self.inviteLater,P.neutral,self.inviteLaterLabel)
 lobbyButton(self.inviteReopen,P.yellow,buttonLabel(self.inviteReopen))
end
function GUI:StoryUnlocked()
 return GameModes.unlocked(player:GetAttribute("StoryCleared"))
end
-- 依目前玩法把設定欄位放到精靈的第一或第二頁。
function GUI:ArrangeLobbyFields()
 local layout=lobbyLayouts[self.settings.gameMode] or lobbyLayouts.PvP
 local story=self.settings.gameMode=="Story"
 for _,entry in pairs(self.settingLabels) do entry.page=nil end
 for page,keys in ipairs(layout) do
  for row,key in ipairs(keys) do
   local entry=self.settingLabels[key]
   entry.page,entry.row=page,row
   entry.caption.Parent,entry.button.Parent=self.lobbyPages[page],self.lobbyPages[page]
  end
 end
 for key,entry in pairs(self.settingLabels) do
  entry.locked=story and storyLocked[key]==true
  entry.caption.Visible,entry.button.Visible=entry.page~=nil,entry.page~=nil
 end
 self.lobbyFieldRows={#layout[1],#layout[2]}
end
function GUI:CompleteLobbySetup()
 if not self.lobbyWizard or not self.lobbyIsHost or not waitingInLobby() or self.lobbyStarting or self.lobbyConfigurePending then return false end
 if type(self.lobbyRevision)~="number" then self:Notify("正在同步房間設定，請稍候再試。") return false end
 self.lobbyEditing=true
 self.lobbyConfigurePending={roomId=self.lobbyRoomId,revision=self.lobbyRevision,ack=player:GetAttribute("LobbyConfigureAck") or 0}
 self.completeLobbySetup:SetAttribute("Unavailable",true)
 self.completeLobbyLabel.Text="正在確認設定…"
 lobbyCommand("LobbyConfigureComplete",self.lobbyRevision)
 return true
end
function GUI:EditLobbySettings()
 if not self.lobbyIsHost or not waitingInLobby() or self.lobbyStarting or self.lobbyConfigurePending then return false end
 self.lobbyEditing=true
 self.lobbyWizard=true
 if self.lobbyConfigured then
  lobbyCommand("LobbySettings",table.clone(self.settings))
 end
 self:SetLobbyPage(1)
 return true
end
function GUI:SetLobbyPage(page)
 if not self.lobbyPages then return end
 self.lobbyPage=self.lobbyWizard and math.clamp(page,1,2) or 3
 self.lobbyFrame:SetAttribute("WizardPage",self.lobbyPage)
 for i,body in ipairs(self.lobbyPages) do body.Visible=i==self.lobbyPage end
 for i,entry in ipairs(self.lobbyStepButtons) do
  entry.button:SetAttribute("Selected",i==self.lobbyPage)
  entry.button:SetAttribute("Unavailable",i==3 or self.lobbyConfigurePending~=nil)
  entry.label.TextColor3=i==self.lobbyPage and LB.blue or LB.muted
 end
 local editing=self.lobbyWizard==true
 self.previousLobbyPage.Visible=editing and self.lobbyPage>1
 self.skipLobbyRules.Visible=false
 self.nextLobbyPage.Visible=editing and self.lobbyPage==1
 self.completeLobbySetup.Visible=editing and self.lobbyPage==2
 self.nextLobbyLabel.Text="下一步：遊戲設定  ›"
 self.readyButton.Visible=not editing
 self.editLobbyButton.Visible=not editing and self.lobbyIsHost==true
 self.civilizationButton.Visible=not editing
 self.lobbyBody.CanvasPosition=Vector2.zero
 self:LayoutLobby()
end
function GUI:LayoutLobby()
 if not self.lobby then return end
 local width,height=self.layoutWidth or 1280,self.layoutHeight or 720
 local compact=width<700
 -- 手機橫向等矮畫面：只留標題、快速開始與房間名稱／狀態，面板不蓋住大半個庭院。
 local tight=height<520
 local small=compact or tight
 local welcomeWidth=math.min(width-16,860)
 local columns=compact and 2 or 4
 local cardHeight=tight and 52 or compact and 82 or 98
 -- 快速開始固定一列四格；窄畫面只留標題，避免歡迎面板蓋住庭院。
 local quickTop=tight and 42 or compact and 67 or 77
 local quickHeight=small and 44 or 64
 local quickWidth=(welcomeWidth-28-3*6)/4
 for i,quick in ipairs(self.quickButtons) do
  quick.button.Size=UDim2.fromOffset(quickWidth,quickHeight)
  quick.button.Position=UDim2.fromOffset(14+(i-1)*(quickWidth+6),quickTop)
  quick.title.Text=small and quick.entry.title or quick.entry.title.."  ›"
  quick.title.TextSize=small and 14 or 17
  quick.title.Position=UDim2.fromOffset(small and 8 or 12,small and 9 or 6)
  quick.title.Size=UDim2.new(1,small and -12 or -20,0,26)
  quick.detail.Visible=not small
  quick.detail.Position=UDim2.fromOffset(12,34)
 end
 local roomsTop=quickTop+quickHeight+8
 self.roomsHeading.Visible=not small
 self.roomsHeading.Position=UDim2.fromOffset(14,roomsTop)
 local welcomeTop=roomsTop+(small and 0 or 24)
 local rows=math.ceil(#(Config.Lobby.portals or {})/columns)
 local welcomeHeight=welcomeTop+rows*(cardHeight+6)+(tight and 8 or 28)
 self.lobbyWelcome.Size=UDim2.fromOffset(welcomeWidth,welcomeHeight)
 self.lobbyWelcome.Position=UDim2.new(0.5,-welcomeWidth/2,1,-welcomeHeight-8)
 self.welcomeHeading.TextSize=small and 22 or 26
 self.welcomeHeading.Position=UDim2.fromOffset(14,8)
 self.welcomeHeading.Size=UDim2.new(1,-36,0,small and 28 or 32)
 self.welcomeDescription.Visible=not tight
 self.welcomeDescription.Position=UDim2.fromOffset(14,compact and 37 or 43)
 self.welcomeDescription.Size=UDim2.new(1,-28,0,compact and 29 or 27)
 self.welcomeDescription.TextSize=compact and 12 or 14
 self.queueSummary.Visible=not tight
 self.queueSummary.Position=UDim2.fromOffset(14,welcomeHeight-23)
 local cardWidth=(welcomeWidth-28-(columns-1)*6)/columns
 for i,portal in ipairs(Config.Lobby.portals or {}) do
  local entry=self.portalCards[portal.id]
  if entry then
   entry.button.Size=UDim2.fromOffset(cardWidth,cardHeight)
   entry.button.Position=UDim2.fromOffset(14+((i-1)%columns)*(cardWidth+6),welcomeTop+math.floor((i-1)/columns)*(cardHeight+6))
   entry.title.TextSize=small and 16 or 18
   entry.title.Position=UDim2.fromOffset(12,small and 4 or 7)
   entry.title.Size=UDim2.new(1,-43,0,tight and 24 or 27)
   -- 窄卡片的「›」會壓到說明文字；矮畫面只顯示房間名稱與狀態。
   entry.arrow.Visible=not small
   entry.detail.Visible=not tight
   entry.detail.Position=UDim2.fromOffset(12,compact and 30 or 34)
   entry.detail.Size=UDim2.new(1,-24,0,compact and 28 or 34)
   entry.detail.TextSize=compact and 12 or 13
   entry.status.Position=UDim2.fromOffset(12,cardHeight-24)
   entry.status.TextSize=compact and 11 or 12
  end
 end
 local panelWidth=math.min(760,width-24)
 local panelHeight=math.min(600,height-24)
 local short=panelHeight<420
 if self.lobbyHeaderBand then self.lobbyHeaderBand.Size=UDim2.new(1,0,0,short and 52 or 76) end
 self.lobbyFrame.Size=UDim2.fromOffset(panelWidth,panelHeight)
 self.lobbyFrame.Position=UDim2.new(0.5,-panelWidth/2,0.5,-panelHeight/2)
 self.lobbySeal.Visible=panelWidth>=480
 self.lobbyHeading.Position=UDim2.fromOffset(panelWidth>=480 and 72 or 16,short and 7 or 13)
 self.lobbyHeading.Size=UDim2.new(1,panelWidth>=480 and -204 or -148,0,34)
 self.lobbyHeading.TextSize=panelWidth<480 and 23 or 28
 self.lobbyDescription.Visible=not short
 self.lobbyDescription.Position=UDim2.fromOffset(panelWidth>=480 and 72 or 16,47)
 self.lobbyDescription.Size=UDim2.new(1,panelWidth>=480 and -208 or -152,0,24)
 self.lobbyDescription.TextSize=panelWidth<480 and 12 or 14
 self.leaveButton.Position=UDim2.new(1,-120,0,short and 6 or 15)
 local stepTop=short and 54 or 83
 self.wizardSteps.Position=UDim2.fromOffset(16,stepTop)
 self.wizardSteps.Visible=self.lobbyWizard==true
 for _,entry in ipairs(self.lobbyStepButtons) do entry.label.TextSize=panelWidth<480 and 12 or 14 end
 local bodyTop=self.lobbyWizard and stepTop+54 or (short and 57 or 84)
 self.lobbyBody.Position=UDim2.fromOffset(16,bodyTop)
 self.lobbyBody.Size=UDim2.fromOffset(panelWidth-32,math.max(32,panelHeight-bodyTop-104))
 local factionCount=self.lobbyFactionCount or 4
 local reviewColumns=panelWidth>=620
 local summaryHeight=panelWidth<480 and 80 or 72
 local rosterTop=reviewColumns and 66 or summaryHeight+72
 local rulesTop=rosterTop+factionCount*50+8
 local reviewHeight=reviewColumns and 334 or rulesTop+134
 local fieldRows=self.lobbyFieldRows or {2,4}
 local story=self.settings.gameMode=="Story"
 local briefingTop=LOBBY_FIELD_TOP[1]+fieldRows[1]*56+4
 local basicHeight=briefingTop+(story and 84 or 0)
 local pageHeight=self.lobbyPage==1 and basicHeight or self.lobbyPage==2 and LOBBY_FIELD_TOP[2]+fieldRows[2]*56 or reviewHeight
 self.lobbyBody.CanvasSize=UDim2.fromOffset(0,pageHeight)
 for _,body in ipairs(self.lobbyPages) do body.Size=UDim2.new(1,-8,0,pageHeight) end
 local narrow=panelWidth<480
 for _,card in pairs(self.modeCards) do
  card.title.TextSize=narrow and 14 or 17
  card.detail.Visible=panelWidth>=560
  card.button.Size=UDim2.new(1/3,-6,0,card.detail.Visible and 78 or 48)
 end
 self.storyBriefing.Visible=story
 self.storyBriefing.Position=UDim2.fromOffset(4,briefingTop)
 self.storyBriefing.Size=UDim2.new(1,-8,0,80)
 self.storyBriefing.TextSize=narrow and 13 or 14
 local captionWidth=narrow and 84 or 110
 for _,entry in pairs(self.settingLabels) do
  if entry.page then
   local y=LOBBY_FIELD_TOP[entry.page]+(entry.row-1)*56
   entry.caption.Position=UDim2.fromOffset(4,y); entry.caption.Size=UDim2.fromOffset(captionWidth,48)
   entry.caption.TextSize=narrow and 14 or 15
   entry.button.Position=UDim2.fromOffset(captionWidth+12,y)
   entry.button.Size=UDim2.new(1,-captionWidth-16,0,48)
   entry.label.TextSize=narrow and 13 or 14
  end
 end
 self.reviewStatus.Position=UDim2.fromOffset(4,0)
 self.reviewStatus.Size=UDim2.new(1,-8,0,30)
 self.reviewSummary.Position=reviewColumns and UDim2.new(0.5,12,0,38) or UDim2.fromOffset(4,38)
 self.reviewSummary.Size=reviewColumns and UDim2.new(0.5,-20,0,100) or UDim2.new(1,-8,0,summaryHeight)
 self.reviewSummary.TextSize=panelWidth<480 and 14 or 16
 self.rosterHeading.Position=UDim2.fromOffset(4,rosterTop-26)
 self.rosterHeading.Size=reviewColumns and UDim2.new(0.5,-144,0,22) or UDim2.new(1,-140,0,22)
 self.readySummary.Position=reviewColumns and UDim2.new(0.5,-136,0,rosterTop-26) or UDim2.new(1,-132,0,rosterTop-26)
 for i,label in ipairs(self.lobbyRows) do
  label.Parent.Position=UDim2.fromOffset(4,rosterTop+(i-1)*50)
  label.Parent.Size=reviewColumns and UDim2.new(0.5,-16,0,44) or UDim2.new(1,-8,0,44)
  label.TextSize=panelWidth<480 and 13 or 14
 end
 self.rules.Position=reviewColumns and UDim2.new(0.5,12,0,151) or UDim2.fromOffset(4,rulesTop)
 self.rules.Size=reviewColumns and UDim2.new(0.5,-20,0,107) or UDim2.new(1,-8,0,76)
 self.civilizationButton.Position=UDim2.fromOffset(4,reviewColumns and 278 or rulesTop+82)
 self.civilizationButton.Size=UDim2.new(1,-8,0,44)
 local footerWidth=panelWidth-32
 self.hostLabel.TextSize=panelWidth<480 and 12 or 14
 self.previousLobbyPage.Size=UDim2.fromOffset(panelWidth<480 and 86 or 110,44)
 self.previousLobbyPage.Position=UDim2.fromOffset(0,40)
 local editing=self.lobbyWizard==true
 if editing then
  local nextWidth=math.min(280,footerWidth*(panelWidth<480 and 0.69 or 0.48))
  self.nextLobbyPage.Size=UDim2.fromOffset(nextWidth,44); self.nextLobbyPage.Position=UDim2.new(1,-nextWidth,0,40)
  self.completeLobbySetup.Size=self.nextLobbyPage.Size; self.completeLobbySetup.Position=self.nextLobbyPage.Position
  self.previousLobbyPage.Size=UDim2.fromOffset(math.min(110,footerWidth-nextWidth-8),44)
  self.completeLobbyLabel.TextSize=panelWidth<480 and 12 or 14
 else
  local leftWidth=self.lobbyIsHost and (panelWidth<480 and 100 or 138) or 0
  local actionWidth=footerWidth-leftWidth
  self.readyButton.Size=UDim2.fromOffset(actionWidth,44)
  self.readyButton.Position=UDim2.fromOffset(leftWidth,40)
  self.editLobbyButton.Size=UDim2.fromOffset(math.max(44,leftWidth-8),44)
  self.editLobbyButton.Position=UDim2.fromOffset(0,40)
  self.readyLabel.TextSize=panelWidth<480 and 12 or 14
 end
 local travelWidth=math.min(500,width-28)
 self.startingTravel.Size=UDim2.fromOffset(travelWidth,238)
 self.startingTravel.Position=UDim2.new(0.5,-travelWidth/2,0.5,-119)
end
function GUI:CreateGuidance()
 self.tutorialState=Tutorial.New()
 -- 桌面顯示完整說明（章節、進度、做法、原因）；觸控版面只保留標題與做法。
 self.guidance=panel(self.hudLayer,UDim2.fromOffset(278,234),UDim2.fromOffset(16,8),"TutorialGuidance")
 self.guidanceChapter=text(self.guidance,"",UDim2.new(1,-78,0,16),UDim2.fromOffset(12,6),12,C.muted)
 self.guidanceChapter.Name="GuidanceChapter"; self.guidanceChapter.TextWrapped=false; self.guidanceChapter.TextTruncate=Enum.TextTruncate.AtEnd
 self.guidanceTitle=text(self.guidance,"新手指引",UDim2.new(1,-78,0,24),UDim2.fromOffset(12,22),17,C.gold,Enum.Font.SourceSansSemibold)
 self.guidanceTitle.Name="GuidanceTitle"
 self.guidanceTrack=make("Frame",self.guidance,{Name="GuidanceProgress",Size=UDim2.new(1,-24,0,4),Position=UDim2.fromOffset(12,52),
  BackgroundColor3=C.inset,BorderSizePixel=0,Active=false})
 round(self.guidanceTrack,2)
 self.guidanceFill=make("Frame",self.guidanceTrack,{Name="Fill",Size=UDim2.fromScale(0,1),BackgroundColor3=C.green,BorderSizePixel=0,Active=false})
 round(self.guidanceFill,2)
 self.guidanceText=text(self.guidance,"",UDim2.new(1,-24,0,82),UDim2.fromOffset(12,62),14,C.white)
 self.guidanceText.Name="GuidanceText"; self.guidanceText.TextYAlignment=Enum.TextYAlignment.Top
 self.guidanceWhy=text(self.guidance,"",UDim2.new(1,-24,0,54),UDim2.fromOffset(12,146),13,C.muted)
 self.guidanceWhy.Name="GuidanceWhy"; self.guidanceWhy.TextYAlignment=Enum.TextYAlignment.Top
 namedButton(self.guidance,"隱藏",UDim2.fromOffset(52,44),UDim2.new(1,-58,0,4),function() self.tutorialHidden=true; self.guidanceExpanded=false; self.guidance.Visible=false end,"HideGuidanceButton",C.muted)
 self.guidanceSkip,self.guidanceSkipLabel=namedButton(self.guidance,"略過這一步  ›",UDim2.fromOffset(124,24),UDim2.new(1,-136,1,-30),function()
  if self.tutorialState.complete then self.tutorialHidden=true; self.guidanceExpanded=false; self.guidance.Visible=false
  else Tutorial.Skip(self.tutorialState); self.guidanceCameraStart=nil end
 end,"SkipGuidanceStep",C.muted)
 self.guidanceHint,self.guidanceHintText=namedButton(self.hudLayer,"新手提示",UDim2.fromOffset(270,44),UDim2.fromOffset(16,88),function() self.tutorialHidden=false; self.guidanceExpanded=true end,"GuidanceHint",C.gold)
 table.insert(self.hitAreas,self.guidanceHint)
 self.guidanceHint.Visible=false
 -- 第一次進大廳的歡迎卡：伺服器確認檔案後才顯示；開始鍵只送出請求，由伺服器開一場單人練習局。
 self.tutorialInvite=panel(self.lobby,UDim2.fromOffset(520,190),UDim2.new(0.5,-260,0,12),"TutorialInvite")
 self.tutorialInvite.Visible=false; self.tutorialInvite.ZIndex=22
 self.inviteTitle=text(self.tutorialInvite,"歡迎，新領主！",UDim2.new(1,-32,0,30),UDim2.fromOffset(16,10),24,C.white,Enum.Font.SourceSansBold)
 self.inviteBody=text(self.tutorialInvite,"",UDim2.new(1,-32,0,84),UDim2.fromOffset(16,44),14,C.muted)
 self.inviteBody.TextYAlignment=Enum.TextYAlignment.Top
 self.inviteStart,self.inviteStartLabel=namedButton(self.tutorialInvite,"開始新手教程  ›",UDim2.fromOffset(220,44),UDim2.new(0,16,1,-54),function()
  if not waitingInLobby() or player:GetAttribute("LobbyQueued")==true then return end
  self.invitePending=os.clock()+3; self.inviteForced=nil
  lobbyCommand("StartTutorial")
 end,"StartTutorialButton",C.green)
 self.inviteStart:SetAttribute("Primary",true)
 self.inviteSkip,self.inviteSkipLabel=namedButton(self.tutorialInvite,"跳過教程",UDim2.fromOffset(150,44),UDim2.new(0,244,1,-54),function()
  self.inviteDismissed=true; self.inviteForced=nil
  lobbyCommand("TutorialDone")
  self:Notify("已跳過新手教程；之後可以從大廳左上角的「新手教程」再開始。")
 end,"SkipTutorialButton",C.muted)
 self.inviteLater,self.inviteLaterLabel=namedButton(self.tutorialInvite,"稍後再說",UDim2.fromOffset(100,44),UDim2.new(0,402,1,-54),function()
  self.inviteDismissed=true; self.inviteForced=nil
 end,"LaterTutorialButton",C.muted)
 self.inviteReopen=namedButton(self.lobby,"新手教程",UDim2.fromOffset(112,44),UDim2.fromOffset(12,12),function()
  self.inviteDismissed=nil; self.inviteForced=true
 end,"ReopenTutorialButton",C.gold)
 table.insert(self.hitAreas,self.inviteReopen)
 self.inviteReopen.Visible=false; self.inviteReopen.ZIndex=21
 self:SkinTutorialInvite()
 self.helpButton=namedButton(self.menuPanel,"重新查看新手指引",UDim2.fromOffset(192,44),UDim2.fromOffset(13,158),function()
  self.tutorialHidden=false; self.guidanceExpanded=true; self.menuPanel.Visible=false
  if self.tutorialState.complete then self.tutorialState=Tutorial.New(); self.guidanceCameraStart=nil end
 end,"GuidanceButton",C.green)
 self.soundButton,self.soundLabel=namedButton(self.menuPanel,"音效：開啟",UDim2.fromOffset(192,44),UDim2.fromOffset(13,239),function()
  local enabled=player:GetAttribute("SoundEnabled")==false
  player:SetAttribute("SoundEnabled",enabled)
  Audio:SetEnabled(enabled)
  if enabled then Audio:Play("Select") end
 end,"SoundButton",C.muted)
 local function soundLabel() self.soundLabel.Text="音效："..(player:GetAttribute("SoundEnabled")==false and "關閉" or "開啟") end
 player:GetAttributeChangedSignal("SoundEnabled"):Connect(soundLabel)
 soundLabel()
 self.motionSetting,self.motionLabel=namedButton(self.menuPanel,"動態：一般",UDim2.fromOffset(192,44),UDim2.fromOffset(13,289),function()
  player:SetAttribute("ReducedMotion",player:GetAttribute("ReducedMotion")~=true)
 end,"ReducedMotionButton",C.muted)
 local function motionLabel()
  self.reducedMotion=player:GetAttribute("ReducedMotion")==true
  self.motionLabel.Text="動態："..(self.reducedMotion and "減少" or "一般")
 end
 player:GetAttributeChangedSignal("ReducedMotion"):Connect(motionLabel)
 motionLabel()
 -- Music and volume follow AOE's options: soundtrack toggle plus stepped levels.
 local steps={1,0.7,0.4,0.2}
 local function nextStep(value)
  for i,step in ipairs(steps) do if math.abs((value or 1)-step)<0.05 then return steps[i%#steps+1] end end
  return steps[1]
 end
 local function percent(value) return tostring(math.floor((type(value)=="number" and value or 1)*100+0.5)).."%" end
 self.musicButton,self.musicLabel=namedButton(self.menuPanel,"音樂：開啟",UDim2.fromOffset(192,44),UDim2.fromOffset(13,339),function()
  player:SetAttribute("MusicEnabled",player:GetAttribute("MusicEnabled")==false)
 end,"MusicButton",C.muted)
 self.musicVolumeButton,self.musicVolumeLabel=namedButton(self.menuPanel,"音樂音量：70%",UDim2.fromOffset(192,44),UDim2.fromOffset(13,389),function()
  player:SetAttribute("MusicVolume",nextStep(player:GetAttribute("MusicVolume")))
 end,"MusicVolumeButton",C.muted)
 self.soundVolumeButton,self.soundVolumeLabel=namedButton(self.menuPanel,"音效音量：100%",UDim2.fromOffset(192,44),UDim2.fromOffset(13,439),function()
  player:SetAttribute("SoundVolume",nextStep(player:GetAttribute("SoundVolume")))
 end,"SoundVolumeButton",C.muted)
 local function audioLabels()
  self.musicLabel.Text="音樂："..(player:GetAttribute("MusicEnabled")==false and "關閉" or "開啟")
  self.musicVolumeLabel.Text="音樂音量："..percent(player:GetAttribute("MusicVolume"))
  self.soundVolumeLabel.Text="音效音量："..percent(player:GetAttribute("SoundVolume"))
 end
 for _,name in ipairs({"MusicEnabled","MusicVolume","SoundVolume"}) do player:GetAttributeChangedSignal(name):Connect(audioLabels) end
 audioLabels()
 self.menuPanel.Size=UDim2.fromOffset(218,354)
 self.menuPanel.CanvasSize=UDim2.fromOffset(0,604)
 for i,name in ipairs({"ContinueButton","SurrenderButton","AutoWorkButton","EdgeScrollButton","GuidanceButton","SoundButton","MusicButton","MusicVolumeButton","SoundVolumeButton","ReducedMotionButton","HotkeyButton"}) do local b=self.menuPanel:FindFirstChild(name); b.Position=UDim2.fromOffset(13,39+(i-1)*50); b.Size=UDim2.fromOffset(192,44) end
end
function GUI:UpdateTutorialInvite(phase)
 local firstTime=Tutorial.FirstTime(player:GetAttribute("ProfileStatus"),player:GetAttribute("TutorialDone"))
 local idle=self.lobby.Visible and phase=="Lobby" and waitingInLobby() and player:GetAttribute("LobbyQueued")~=true
 local pending=self.invitePending~=nil and os.clock()<self.invitePending
 local open=idle and not pending and (self.inviteForced==true or (firstTime and not self.inviteDismissed))
 self.tutorialInvite.Visible=open
 self.inviteReopen.Visible=idle and not open and not pending
 local width,height=self.layoutWidth or 1280,self.layoutHeight or 720
 local cardWidth=math.min(520,width-16)
 local narrow=cardWidth<480
 local cardHeight=narrow and 214 or 190
 self.tutorialInvite.Size=UDim2.fromOffset(cardWidth,cardHeight)
 self.tutorialInvite.Position=UDim2.new(0.5,-cardWidth/2,0,12)
 self.inviteTitle.Text=firstTime and "歡迎，新領主！" or "新手教程"
 self.inviteTitle.TextSize=narrow and 20 or 24
 self.inviteBody.Size=UDim2.new(1,-32,0,cardHeight-108)
 self.inviteBody.TextSize=narrow and 13 or 14
 self.inviteBody.Text=(firstTime and "第一次來嗎？" or "想再複習一次？").."新手教程會開一場沒有對手、資源充足的練習局，分 "..#Tutorial.Chapters.." 章 "..#Tutorial.Steps
  .." 步帶你學會鏡頭、採集、人口、建造、生產、指揮軍隊與升級時代，大約 10 分鐘。每一步都會說明要做什麼、為什麼這樣做，卡住時可以略過。"
 -- 三個按鈕依卡片寬度分配；「跳過」只給還沒完成教程的玩家。
 local inner=cardWidth-32
 self.inviteSkip.Visible=firstTime
 local startWidth=firstTime and math.floor(inner*0.46) or math.floor(inner*0.68)
 local skipWidth=firstTime and math.floor(inner*0.28) or 0
 local laterX=16+startWidth+8+(firstTime and skipWidth+8 or 0)
 self.inviteStart.Size=UDim2.fromOffset(startWidth,44)
 self.inviteSkip.Size=UDim2.fromOffset(skipWidth,44); self.inviteSkip.Position=UDim2.new(0,16+startWidth+8,1,-54)
 self.inviteLater.Size=UDim2.fromOffset(cardWidth-16-laterX,44); self.inviteLater.Position=UDim2.new(0,laterX,1,-54)
 for _,label in ipairs({self.inviteStartLabel,self.inviteSkipLabel,self.inviteLaterLabel}) do label.TextSize=narrow and 13 or 14 end
 -- 矮畫面放不下兩張卡時，歡迎卡開著就先收起匹配點清單。
 self.tutorialInviteCovers=open and height<self.lobbyWelcome.Size.Y.Offset+cardHeight+32
end
function GUI:UpdateGuidance(selected,phase)
 if phase ~= self.guidancePhase then
  if phase=="Playing" then
   self.tutorialState=Tutorial.New()
   -- nil：尚未決定。新手與教程局自動顯示；完成過教程的玩家要從選單開啟。
   self.tutorialHidden=nil
   self.guidanceCameraStart=nil; self.guidanceCameraSettle=os.clock()+1.5
  end
  self.guidancePhase=phase
 end
 self:UpdateTutorialInvite(phase)
 local available=phase=="Playing" and not player:GetAttribute("Defeated") and not player:GetAttribute("Spectator")
 local state=self.tutorialState
 local facts={selectedVillager=false,selectedArmy=false,delivered=(player:GetAttribute("DeliveredResources") or 0)>0,
  trained=(player:GetAttribute("TrainedVillagers") or 0)>0,
  feudal=(player:GetAttribute("Age") or 1)>=2 or (player:GetAttribute("AgeRemaining") or 0)>0}
 for _,model in ipairs(selected) do
  if model:GetAttribute("OwnerId")==player.UserId then
   local kind=model:GetAttribute("UnitType")
   if kind=="villager" then facts.selectedVillager=true elseif kind=="infantry" then facts.selectedArmy=true end
  end
 end
 local buildings=workspace:FindFirstChild("Buildings")
 if buildings and available and not state.complete then for _,model in ipairs(buildings:GetChildren()) do
  if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("Complete")==true then
   local kind=model:GetAttribute("BuildingType")
   if kind=="House" then facts.house=true
   elseif kind=="LumberCamp" or kind=="Mill" or kind=="MiningCamp" then facts.dropoff=true
   elseif kind=="Farm" then facts.farm=true
   elseif kind=="Barracks" then facts.barracks=true end
  end
 end end
 local units=workspace:FindFirstChild("Units")
 if units and available and not state.complete then for _,model in ipairs(units:GetChildren()) do
  if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("UnitType")=="infantry" then facts.army=true; break end
 end end
 -- 鏡頭步驟只看本機鏡頭位置；開局鏡頭跳回主城的那段時間不算。
 local camera=workspace.CurrentCamera
 if camera and available and not state.complete and Tutorial.Steps[state.step].key=="cameraMoved" then
  local position=camera.CFrame.Position
  if not self.guidanceCameraStart or os.clock()<(self.guidanceCameraSettle or 0) then self.guidanceCameraStart=position
  elseif (position-self.guidanceCameraStart).Magnitude>24 then facts.cameraMoved=true end
 end
 -- 每一步至少停留幾秒：自動工作會立刻完成交貨之類的步驟，玩家仍要有時間讀完說明。
 if self.guidanceShownStep~=state.step then self.guidanceShownStep=state.step; self.guidanceStepSince=os.clock() end
 if available and os.clock()-self.guidanceStepSince>=5 then Tutorial.Advance(state,facts) end
 if state.complete and available and not self.tutorialReported and player:GetAttribute("TutorialDone")~=true then
  self.tutorialReported=true
  lobbyCommand("TutorialDone")
 end
 if self.tutorialHidden==nil and available and (player:GetAttribute("TutorialMatch")==true
  or Tutorial.FirstTime(player:GetAttribute("ProfileStatus"),player:GetAttribute("TutorialDone"))) then self.tutorialHidden=false end
 local wanted=available and self.tutorialHidden==false
 local compact=self.touchLayout and self.shortLandscape==true
 self.guidance.Visible=wanted and (not compact or self.guidanceExpanded==true)
 self.guidanceHint.Visible=wanted and compact and not self.guidance.Visible
 local touch=self.touchLayout==true
 local function keys(value) return Tutorial.Format(value,function(id) return self.hotkeys and self.hotkeys[id] and self:HotkeyLabel(id) or nil end) end
 self.guidanceChapter.Visible=not touch
 self.guidanceWhy.Visible=not touch and not state.complete
 self.guidanceSkip.Visible=not touch
 self.guidanceTitle.Position=UDim2.fromOffset(12,touch and 6 or 22)
 self.guidanceTrack.Position=UDim2.fromOffset(12,touch and 32 or 52); self.guidanceTrack.Size=UDim2.new(1,touch and -84 or -24,0,4)
 self.guidanceText.Position=UDim2.fromOffset(12,touch and 38 or 62)
 self.guidanceText.Size=UDim2.new(1,-24,0,touch and 62 or state.complete and 136 or 82)
 self.guidanceFill.Size=UDim2.fromScale(Tutorial.Progress(state),1)
 if state.complete then
  self.guidanceChapter.Text="全部 "..#Tutorial.Steps.." 步完成"
  self.guidanceTitle.Text=Tutorial.Completion.title.." ✓"
  self.guidanceText.Text=touch and Tutorial.Completion.touch or Tutorial.Completion.text
  self.guidanceSkipLabel.Text="關閉"
 else
  local step=Tutorial.Steps[state.step]
  self.guidanceChapter.Text="第 "..step.chapter.." 章 · "..Tutorial.Chapters[step.chapter]
  self.guidanceTitle.Text=state.step.." / "..#Tutorial.Steps.."  "..step.title
  self.guidanceText.Text=touch and step.touch or keys(step.desktop)
  self.guidanceWhy.Text="為什麼："..keys(step.why)
  self.guidanceSkipLabel.Text="略過這一步  ›"
 end
 self.guidanceHintText.Text=self.guidanceTitle.Text.."  ›"
end
function GUI:CreateTouchDock()
 self.touchDock=panel(self.hudLayer,UDim2.fromOffset(740,48),UDim2.new(0.5,-370,1,-258),"TouchDock")
 self.touchButtons={}
 local actions={{"Select","選取","select"},{"Move","移動","move"},{"Gather","採集","gather"},{"Attack","攻擊","attack"},{"Build","建造","build"},
  {"Home","主城",nil,"selectHome"},{"Idle","閒置",nil,"selectIdle"},{"Villagers","村民",nil,"selectVillagers"},{"Cancel","取消",nil,"cancel"},
  {"Delete","死亡",nil,"requestDelete"}}
 for _,action in ipairs(actions) do
  local b,label,edge=namedButton(self.touchDock,action[2],UDim2.fromOffset(76,44),UDim2.fromOffset(4,2),function()
   local callback=action[3] and self.callbacks.touchMode or self.callbacks[action[4]]
   if callback then callback(action[3]) end
  end,"Touch"..action[1].."Button",C.white)
  table.insert(self.touchButtons,{button=b,label=label,edge=edge,mode=action[3],key=action[1]})
 end
end
-- 觸控沒有 R 鍵：放置可旋轉建築（城門）時在畫面右側顯示旋轉按鈕；先點按鈕選方向，再拖曳放置。
function GUI:CreateTouchRotate()
 self.touchRotate=panel(self.hudLayer,UDim2.fromOffset(132,56),UDim2.new(1,-140,0.5,-28),"TouchRotatePanel")
 self.touchRotate.Visible=false
 local _,label=namedButton(self.touchRotate,"旋轉",UDim2.new(1,-8,1,-8),UDim2.fromOffset(4,4),function()
  if Building:Rotate() then self:UpdateTouchRotate(self.buildingKind) end
 end,"TouchRotateButton",C.white)
 label.TextSize=16
 self.touchRotateLabel=label
end
function GUI:UpdateTouchRotate(buildingKind)
 local data=buildingKind and Config.Buildings[buildingKind]
 local visible=self.touchLayout==true and data~=nil and data.rotatable==true and workspace:GetAttribute("MatchPhase")=="Playing"
 self.touchRotate.Visible=visible
 if visible then self.touchRotateLabel.Text="旋轉 ⟳ · "..(Building.rotated and "直向" or "橫向") end
end
function GUI:UpdateTouchDock(phase)
 self.touchDock.Visible=self.touchLayout and phase=="Playing" and not player:GetAttribute("Defeated") and not player:GetAttribute("Spectator")
 local mode=player:GetAttribute("RTSTouchMode") or "select"
 for _,entry in ipairs(self.touchButtons) do
  local unavailable=(entry.mode=="build" and not selectedBuilders(self.selected or {})) or (entry.key=="Delete" and not deleteSelection(self.selected or {}))
  entry.button:SetAttribute("Unavailable",unavailable==true)
  entry.button:SetAttribute("Selected",entry.mode==mode)
  entry.edge.Color=entry.mode==mode and C.gold or C.edge
  if entry.key=="Delete" then entry.label.Text=deleteLabel(self.selected) end
  entry.label.TextColor3=unavailable and C.muted or (entry.key=="Delete" and C.red or (entry.mode==mode and C.gold or C.white))
 end
end
function GUI:LayoutTopbar()
 if self.touchLayout then return end
 local width,height=self.topScreen.AbsoluteSize.X,self.topScreen.AbsoluteSize.Y
 self.topBar.Visible=width>8 and height>8
 if not self.topBar.Visible then return end
 local scale=math.min(1,(width-8)/480)
 self.topbarScale.Scale=scale
 local barWidth,barHeight=(width-8)/scale,math.min(58,(height-8)/scale)
 self.topBar.Size=UDim2.fromOffset(barWidth,barHeight)
 self.topBar.Position=UDim2.fromOffset(4,(height-barHeight*scale)/2)
 local cardHeight=math.max(1,math.min(46,barHeight-4))
 local rowY=(barHeight-cardHeight)/2
 local gap=6
 local showAge,showIdle=barWidth>=900,barWidth>=600
 local idleWidth=showIdle and 124 or 0
 local ageWidth=showAge and 196 or 0
 local menuWidth=barWidth>=760 and 84 or 52
 local available=barWidth-12-menuWidth-gap-(showIdle and idleWidth+gap or 0)-(showAge and ageWidth+gap or 0)
 local step=math.max(1,math.min(136,available/5))
 self.resourceBar.Position=UDim2.fromOffset(6,rowY); self.resourceBar.Size=UDim2.fromOffset(step*5,cardHeight)
 for i,key in ipairs(RESOURCE_ORDER) do
  self.resourceCards[key].Position=UDim2.fromOffset((i-1)*step,0)
  self:LayoutResourceCard(key,math.max(1,step-gap),cardHeight,step<104)
  self.resourceValues[key].TextScaled=false
 end
 local x=6+step*5
 self.idleButton.Visible=showIdle; self.idleButton.Position=UDim2.fromOffset(x,rowY)
 self.idleButton.Size=UDim2.fromOffset(idleWidth,cardHeight)
 self.idleHotkey.Visible=cardHeight>=40
 self.idleLabel.Position=UDim2.fromOffset(42,cardHeight>=40 and 4 or (cardHeight-18)/2)
 if showIdle then x+=idleWidth+gap end
 local menuX=barWidth-menuWidth-6
 -- The age crest takes the middle of whatever space is left, as in classic RTS headers.
 self.ageBlock.Visible=showAge
 self.ageBlock.Position=UDim2.fromOffset(x+math.max(0,(menuX-gap-x-ageWidth)/2),rowY); self.ageBlock.Size=UDim2.fromOffset(ageWidth,cardHeight)
 self.ageEmblem.Position=UDim2.fromOffset(21,cardHeight/2); self.ageNumeral.Size=UDim2.fromOffset(42,cardHeight)
 self.ageLabel.Position=UDim2.fromOffset(46,cardHeight/2-21); self.ageLabel.Size=UDim2.fromOffset(ageWidth-50,22); self.ageLabel.TextSize=17
 self.clockLabel.Position=UDim2.fromOffset(46,cardHeight/2+1); self.clockLabel.Size=UDim2.fromOffset(ageWidth-50,16)
 self.ageTrack.Position=UDim2.fromOffset(46,cardHeight-4); self.ageTrack.Size=UDim2.fromOffset(ageWidth-56,3)
 self.menuDock.Position=UDim2.fromOffset(menuX,rowY); self.menuDock.Size=UDim2.fromOffset(menuWidth,cardHeight)
 self.menuLabel.Text=menuWidth>=80 and "☰  選單" or "☰"
end
function GUI:LayoutTouch()
 if not self.touchLayout then return end
 self.topBar.Visible=false
 self.resourceBar.Parent=self.hudLayer; self.menuDock.Parent=self.hudLayer; self.ageLabel.Parent=self.hudLayer
 self.idleButton.Visible=false
 local width,height=self.layoutWidth,self.layoutHeight
 self.shortLandscape=width>height and height<480
 local narrow=width<700
 local dockWidth=math.min(width-16,620)
 self.scoreboard.Visible=false; self.keyHelp.Visible=false
 self.hudLayer:FindFirstChild("Objective").Visible=false
 -- Keep a readable UI in screen pixels, rather than shrinking desktop buttons.
 for _,child in ipairs(self.hudLayer:GetChildren()) do
  if child:IsA("TextLabel") and child~=self.ageLabel then child.Visible=false end
 end
 self.ageLabel.Position=UDim2.fromOffset(8,59); self.ageLabel.Size=UDim2.fromOffset(math.min(230,math.max(120,width-150)),20); self.ageLabel.TextSize=13
 -- Outside the bar the label sits over the terrain, so it carries its own timber pill.
 self.ageLabel.BackgroundColor3=C.ribbon; self.ageLabel.BackgroundTransparency=0.08; self.ageLabel.TextColor3=L.gold
 self.ageLabel.TextXAlignment=Enum.TextXAlignment.Center
 if not self.ageLabel:FindFirstChildOfClass("UICorner") then round(self.ageLabel,6) end
 self.resourceBar.Size=UDim2.fromOffset(width-72,52); self.resourceBar.Position=UDim2.fromOffset(4,4)
 local cardWidth=(width-76)/5
 for i,key in ipairs(RESOURCE_ORDER) do
  local card=self.resourceCards[key]; card.Position=UDim2.fromOffset((i-1)*cardWidth,0)
  card.BackgroundTransparency=0.08
  self:LayoutResourceCard(key,cardWidth-3,52,cardWidth<110)
  self.resourceValues[key].TextScaled=true
  if cardWidth<90 then
   -- Narrow phones stack a small icon above a full-width value.
   card.ResourceIcon.Size=UDim2.fromOffset(18,18); card.ResourceIcon.Position=UDim2.fromOffset(3,3)
   card.WorkerBadge.Position=UDim2.fromOffset(24,5)
   self.resourceValues[key].Position=UDim2.fromOffset(3,23); self.resourceValues[key].Size=UDim2.new(1,-6,0,24)
  end
 end
 self.menuDock.Position=UDim2.new(1,-66,0,4); self.menuDock.Size=UDim2.fromOffset(62,52)
 self.menuLabel.Text="選單"
 -- Keep every setting reachable in short landscape viewports.
 self.menuPanel.Size=UDim2.fromOffset(218,math.max(44,math.min(354,height-8)))
 self.menuPanel.Position=UDim2.new(1,-226,0,math.max(0,math.min(62,height-self.menuPanel.Size.Y.Offset-4)))
 self.bottom.Size=UDim2.fromOffset(dockWidth,216); self.bottom.Position=UDim2.new(0.5,-dockWidth/2,1,-222)
 self.queueHolder.Parent=self.bottom; self.queueHolder.Size=UDim2.fromOffset(dockWidth-20,44); self.queueHolder.Position=UDim2.fromOffset(10,126)
 self.context.Visible=false; self.buildHelp.Visible=false
 self.commandHolder.Size=UDim2.fromOffset(dockWidth-20,78); self.commandHolder.Position=UDim2.fromOffset(10,48)
 for i,key in ipairs({"build","train","research"}) do
  local entry=self.tabButtons[key]; entry.button.Position=UDim2.fromOffset(8+(i-1)*(dockWidth-16)/3,2); entry.button.Size=UDim2.fromOffset((dockWidth-22)/3,44)
 end
 self.previousPage.Position=UDim2.fromOffset(8,172); self.previousPage.Size=UDim2.fromOffset(44,44)
 self.pageLabel.Position=UDim2.fromOffset(54,182); self.nextPage.Position=UDim2.fromOffset(104,172); self.nextPage.Size=UDim2.fromOffset(44,44)
 self.stopButton.Position=UDim2.new(1,-90,0,172); self.stopButton.Size=UDim2.fromOffset(82,44)
 self.formationButton.Position=UDim2.new(1,-72,0,128); self.formationButton.Size=UDim2.fromOffset(62,44)
 self.garrisonButton.Position=UDim2.new(1,-160,0,172); self.garrisonButton.Size=UDim2.fromOffset(66,44)
 self.garrisonLabel.Text="駐紮"
 self.formationButton:FindFirstChildWhichIsA("TextLabel").Text="陣形"
 self.mobileState.Size=UDim2.new(1,-90,0,44)
 local columns=narrow and 5 or 10; local rows=math.ceil(#self.touchButtons/columns); local modeWidth=math.min(width-16,800)
 self.touchDock.Size=UDim2.fromOffset(modeWidth,rows*46+4); self.touchDock.Position=UDim2.new(0.5,-modeWidth/2,1,-226-rows*46-4)
 for i,entry in ipairs(self.touchButtons) do
  entry.button.Size=UDim2.fromOffset((modeWidth-8)/columns-4,44); entry.button.Position=UDim2.fromOffset(4+((i-1)%columns)*(modeWidth-8)/columns,2+math.floor((i-1)/columns)*46)
 end
 self.guidance.Size=UDim2.fromOffset(math.min(width-150,350),104); self.guidance.Position=UDim2.fromOffset(8,83)
 self.guidanceHint.Size=UDim2.fromOffset(math.min(270,width-200),44)
 self.guidanceTitle.TextSize=14; self.guidanceText.TextSize=13
 self.mapPanel.Size=UDim2.fromOffset(124,142); self.mapPanel.Position=UDim2.new(1,-132,0,72)
 self.mapModeButton.Visible=false
 self.map.Size=UDim2.fromOffset(112,112); self.map.Position=UDim2.fromOffset(6,24)
 self.noticePanel.Size=UDim2.fromOffset(width-16,44)
 self.noticePanel.Position=UDim2.new(0,8,0,62)
 self.notice.TextSize=14
 self:FitNotice()
 self.commandKey=nil
 self:LayoutLobby()
 self.mapPanel.Visible=not self.shortLandscape
 if self.shortLandscape then
  -- On landscape phones, give the world the left side and keep commands to the right.
  local sideWidth=math.min(340,width*0.43)
  self.bottom.Size=UDim2.fromOffset(sideWidth,216); self.bottom.Position=UDim2.new(1,-sideWidth-8,1,-222)
  self.queueHolder.Size=UDim2.fromOffset(sideWidth-20,44)
  self.commandHolder.Size=UDim2.fromOffset(sideWidth-20,78)
  for i,key in ipairs({"build","train","research"}) do self.tabButtons[key].button.Position=UDim2.fromOffset(8+(i-1)*(sideWidth-16)/3,2); self.tabButtons[key].button.Size=UDim2.fromOffset((sideWidth-22)/3,44) end
  local leftWidth=math.max(240,width-sideWidth-28)
  self.touchDock.Size=UDim2.fromOffset(leftWidth,96); self.touchDock.Position=UDim2.new(0,8,1,-102)
  for i,entry in ipairs(self.touchButtons) do
   entry.button.Size=UDim2.fromOffset((leftWidth-8)/5-4,44); entry.button.Position=UDim2.fromOffset(4+((i-1)%5)*(leftWidth-8)/5,2+math.floor((i-1)/5)*46)
  end
 end
 self.commandSurface.Size=UDim2.fromOffset(self.bottom.Size.X.Offset-20,122); self.commandSurface.Position=UDim2.fromOffset(10,48)
 self.bottom.CommandHeaderRule.Position=UDim2.fromOffset(10,46); self.bottom.CommandHeaderRule.Size=UDim2.new(1,-20,0,1)
 self.bottom.CommandFooterRule.Position=UDim2.fromOffset(10,170); self.bottom.CommandFooterRule.Size=UDim2.new(1,-20,0,1)
 self.dockHeader.Size=UDim2.new(1,-8,0,42); self.dockHeader.Position=UDim2.fromOffset(4,3)
end
function GUI:CreateDeleteConfirm()
 self.deleteConfirm=scrim(panel(self.canvas,UDim2.fromScale(1,1),UDim2.fromScale(0,0),"DeleteConfirmOverlay"))
 self.deleteConfirm.BackgroundColor3=Color3.new(0,0,0); self.deleteConfirm.BackgroundTransparency=0.42
 self.deleteConfirm.ZIndex=50; self.deleteConfirm.Visible=false
 self.deleteBody=panel(self.deleteConfirm,UDim2.fromOffset(420,208),UDim2.new(0.5,-210,0.5,-104),"DeleteConfirmBody")
 self.deleteBody.ZIndex=51
 self.deleteTitle=text(self.deleteBody,"確認死亡",UDim2.new(1,-32,0,34),UDim2.fromOffset(16,12),22,C.white,Enum.Font.SourceSansSemibold)
 self.deleteTitle.Name="DeleteTitle"
 self.deleteWarning=text(self.deleteBody,"",UDim2.new(1,-32,0,92),UDim2.fromOffset(16,50),16,C.muted)
 self.deleteWarning.Name="DeleteWarning"; self.deleteWarning.TextYAlignment=Enum.TextYAlignment.Top
 self.deleteCancel=namedButton(self.deleteBody,"保留 · 取消",UDim2.new(0.5,-22,0,44),UDim2.new(0,16,1,-56),function() self:CancelDelete() end,"DeleteCancel",C.white)
 self.deleteAccept,self.deleteAcceptLabel=namedButton(self.deleteBody,"確認死亡",UDim2.new(0.5,-22,0,44),UDim2.new(0.5,6,1,-56),function()
  local models=self.pendingDelete and deleteSelection(self.pendingDelete)
  local generation=self.deleteGeneration
  if not models or workspace:GetAttribute("MatchPhase")~="Playing" or workspace:GetAttribute("MatchGeneration")~=generation
   or player:GetAttribute("Defeated") or player:GetAttribute("Spectator") then
   self:CancelDelete(); self:Notify("選取目標或對局已改變，請重新選取。","Error"); return
  end
  self:CancelDelete()
  if self.callbacks.delete then self.callbacks.delete(models,generation) end
 end,"DeleteAccept",C.red)
end
function GUI:LayoutDeleteConfirm()
 local width=math.max(220,math.min(420,self.layoutWidth-24))
 self.deleteBody.Size=UDim2.fromOffset(width,208); self.deleteBody.Position=UDim2.new(0.5,-width/2,0.5,-104)
end
function GUI:CancelDelete()
 self.pendingDelete,self.deleteGeneration=nil,nil
 if self.deleteConfirm then self.deleteConfirm.Visible=false end
 player:SetAttribute("RTSModalOpen",self:IsModalOpen()==true)
end
function GUI:RequestDelete()
 if self:IsModalOpen() or workspace:GetAttribute("MatchPhase")~="Playing" or player:GetAttribute("Defeated") or player:GetAttribute("Spectator") then return false end
 local models=deleteSelection(self.selected)
 if not models then self:Notify("請先選取自己的存活單位或建築。","Error"); return false end
 local model=models[1]
 local buildingType=model:GetAttribute("BuildingType")
 local incomplete=buildingType and model:GetAttribute("Complete")==false
 local name=model:GetAttribute("DisplayName") or model.Name
 local label=deleteLabel(models)
 self.deleteTitle.Text=#models>1 and ("讓選取的 "..#models.." 個目標"..label.."？") or ((incomplete and "取消工地：" or (label.."："))..name)
 self.deleteAcceptLabel.Text=incomplete and #models==1 and "確認取消工地" or ("確認"..label)
 local warning="單位死亡、拆除建築或取消工地，都不退還資源。\n建築內的訓練與研究也會取消。"
 if workspace:GetAttribute("VictoryMode")=="Regicide" then
  for _,target in ipairs(models) do if target:GetAttribute("MainBase")==true then warning="包含主城決戰的起始主城，拆除將立即戰敗。\n拆除不退還資源；訓練與研究也會取消。"; break end end
 end
 self.deleteWarning.Text=warning.."\n按 Esc 或「保留」取消。"
 self.pendingDelete=models; self.deleteGeneration=workspace:GetAttribute("MatchGeneration")
 self.tooltip.Visible=false; self.deleteConfirm.Visible=true
 player:SetAttribute("RTSModalOpen",true)
 return true
end
function GUI:CreateHotkeyPanel()
 self.hotkeyPanel=scrim(panel(self.canvas,UDim2.fromScale(1,1),UDim2.fromScale(0,0),"HotkeyOverlay"))
 self.hotkeyPanel.BackgroundColor3=Color3.new(0,0,0); self.hotkeyPanel.BackgroundTransparency=0.42
 self.hotkeyPanel.ZIndex=50; self.hotkeyPanel.Visible=false
 self.hotkeyBody=panel(self.hotkeyPanel,UDim2.fromOffset(440,520),UDim2.new(0.5,-220,0.5,-260),"HotkeyBody")
 self.hotkeyBody.ZIndex=51
 text(self.hotkeyBody,"熱鍵設定",UDim2.new(1,-32,0,30),UDim2.fromOffset(16,10),22,C.white,Enum.Font.SourceSansSemibold).Name="HotkeyTitle"
 self.hotkeyHint=text(self.hotkeyBody,"",UDim2.new(1,-32,0,40),UDim2.fromOffset(16,42),13,C.muted)
 self.hotkeyHint.Name="HotkeyHint"; self.hotkeyHint.TextYAlignment=Enum.TextYAlignment.Top
 -- 通知橫幅會被這個面板的暗幕蓋住，改鍵結果與拒絕原因直接顯示在面板內。
 self.hotkeyStatus=text(self.hotkeyBody,"",UDim2.new(1,-32,0,20),UDim2.fromOffset(16,84),14,C.red,Enum.Font.SourceSansSemibold)
 self.hotkeyStatus.Name="HotkeyStatus"; self.hotkeyStatus.TextWrapped=false; self.hotkeyStatus.TextTruncate=Enum.TextTruncate.AtEnd
 self.hotkeyList=make("ScrollingFrame",self.hotkeyBody,{Name="HotkeyList",Size=UDim2.new(1,-24,1,-176),Position=UDim2.fromOffset(12,110),
  BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,#HotkeyRules.Actions*48),ScrollBarThickness=4,ScrollBarImageColor3=C.gold,
  ScrollingDirection=Enum.ScrollingDirection.Y,Active=true,ClipsDescendants=true})
 self.hotkeyRows={}
 for i,action in ipairs(HotkeyRules.Actions) do
  local row=make("Frame",self.hotkeyList,{Name="Hotkey_"..action.id,Size=UDim2.new(1,-8,0,44),Position=UDim2.fromOffset(0,(i-1)*48),
   BackgroundColor3=C.card,BackgroundTransparency=0.45,BorderSizePixel=0})
  round(row,5)
  local name=text(row,action.name,UDim2.new(1,-150,1,0),UDim2.fromOffset(12,0),16,C.white)
  name.TextWrapped=false; name.TextTruncate=Enum.TextTruncate.AtEnd
  local b,label=namedButton(row,"",UDim2.fromOffset(124,36),UDim2.new(1,-130,0,4),function()
   self.hotkeyCapture=self.hotkeyCapture~=action.id and action.id or nil
   self:SetHotkeyStatus(nil)
  end,"KeyButton",C.gold)
  self.hotkeyRows[action.id]={button=b,label=label}
 end
 namedButton(self.hotkeyBody,"恢復預設",UDim2.new(0.5,-22,0,44),UDim2.new(0,16,1,-56),function()
  self:SetHotkeys(HotkeyRules.defaults()); self:SetHotkeyStatus("熱鍵已恢復預設。"); self:Notify("熱鍵已恢復預設。")
 end,"HotkeyReset",C.muted)
 local done=namedButton(self.hotkeyBody,"完成",UDim2.new(0.5,-22,0,44),UDim2.new(0.5,6,1,-56),function() self:CloseHotkeys() end,"HotkeyDone",C.gold)
 done:SetAttribute("Primary",true)
end
function GUI:LayoutHotkeyPanel()
 local width=math.max(220,math.min(440,self.layoutWidth-24))
 local height=math.max(200,math.min(176+#HotkeyRules.Actions*48,self.layoutHeight-16))
 self.hotkeyBody.Size=UDim2.fromOffset(width,height); self.hotkeyBody.Position=UDim2.new(0.5,-width/2,0.5,-height/2)
end
function GUI:HotkeyLabel(id) return HotkeyRules.label(self.hotkeys[id]) end
-- HUD 上所有按鍵提示都由目前的綁定產生，改鍵後不會留下舊字樣。
function GUI:RefreshHotkeyLabels()
 local function key(id) return self:HotkeyLabel(id) end
 for tab,name in pairs({build="建築",train="生產",research="科技"}) do self.tabButtons[tab].label.Text=name.." ["..key(tab).."]" end
 self.stopLabel.Text="停止 ["..key("stop").."]"
 if not self.touchLayout then
  self.formationLabel.Text="陣形 ["..key("formation").."]"
  self.garrisonLabel.Text="駐紮 ["..key("garrison").."]"
 end
 self.idleHotkey.Text="按 ["..key("selectIdle").."] 選取"
 -- 四個相機鍵都是單一字元時並排顯示（例如 WASD），否則用分隔號分開。
 local cameraKeys={key("cameraUp"),key("cameraLeft"),key("cameraDown"),key("cameraRight")}
 local compact=true
 for _,label in ipairs(cameraKeys) do if #label~=1 then compact=false end end
 self.keyHelp.Text=table.concat(cameraKeys,compact and "" or "／").." 移動 · 滾輪縮放 · Home 回基地 · 拖曳框選 · 右鍵下令／小地圖移動 · "..key("formation").." 陣形 · Ctrl + 1–9 編隊 · "
  ..key("selectIdle").." 閒置村民 · "..key("garrison").." 駐紮 · "..key("delete").." 死亡／拆除"
 for id,row in pairs(self.hotkeyRows) do
  local capturing=self.hotkeyCapture==id
  row.label.Text=capturing and "請按新按鍵…" or key(id)
  row.button:SetAttribute("Selected",capturing)
 end
 self.hotkeyHint.Text=self.hotkeyCapture and "按下要使用的按鍵；Esc 取消這次變更。"
  or "點選右側按鍵後按下新按鍵；已被使用的按鍵會互換。\n方向鍵、Home、數字編隊與 Esc 為固定按鍵。"
end
function GUI:SetHotkeyStatus(message,isError)
 self.hotkeyStatus.Text=message or ""
 self.hotkeyStatus.TextColor3=isError and C.red or C.green
 self:RefreshHotkeyLabels()
end
function GUI:SetHotkeys(map)
 self.hotkeys=map; self.hotkeyCapture=nil; self.hotkeysChanged=true
 local stored=HotkeyRules.serialize(map)
 player:SetAttribute("Hotkeys",stored)
 lobbyCommand("Hotkeys",stored) -- 伺服器驗證後寫入個人檔案，下次進入遊戲沿用。
 self:RefreshHotkeyLabels()
 self:Update(self.selected or {},self.buildingKind)
end
function GUI:OpenHotkeys()
 self.menuPanel.Visible=false; self.tooltip.Visible=false
 self.hotkeyCapture=nil; self:SetHotkeyStatus(nil)
 self.hotkeyPanel.Visible=true
 player:SetAttribute("RTSModalOpen",true)
end
function GUI:CloseHotkeys()
 self.hotkeyCapture=nil
 if self.hotkeyPanel then self.hotkeyPanel.Visible=false end
 player:SetAttribute("RTSModalOpen",self:IsModalOpen()==true)
end
-- 熱鍵面板開啟時由它接收鍵盤輸入；回傳 true 表示這次按鍵已處理，不再當作遊戲指令。
function GUI:HotkeyInput(input)
 if not self.hotkeyPanel or not self.hotkeyPanel.Visible or input.UserInputType~=Enum.UserInputType.Keyboard then return false end
 local id=self.hotkeyCapture
 if input.KeyCode==Enum.KeyCode.Escape then
  if id then self.hotkeyCapture=nil; self:SetHotkeyStatus(nil) else self:CloseHotkeys() end
  return true
 end
 if not id then return true end
 local map,swapped,reason=HotkeyRules.bind(self.hotkeys,id,input.KeyCode.Name)
 -- 被拒絕時維持擷取狀態，玩家可以直接再按別的鍵。
 if not map then self:SetHotkeyStatus(reason,true); self:Notify(reason,"Error"); return true end
 self:SetHotkeys(map)
 local name=HotkeyRules.action(id).name
 local message=name.." 改為 ["..self:HotkeyLabel(id).."]"
  ..(swapped and ("；"..HotkeyRules.action(swapped).name.." 換成 ["..self:HotkeyLabel(swapped).."]。") or "。")
 self:SetHotkeyStatus(message); self:Notify(message)
 return true
end
function GUI:CreateResult()
 self.result = scrim(panel(self.canvas,UDim2.fromScale(1,1),UDim2.fromScale(0,0),"ResultOverlay"))
 self.result.ZIndex = 30; self.result.BackgroundColor3 = Color3.fromRGB(13,18,18); self.result.BackgroundTransparency = 0.22; self.result.Visible = false
 local body = panel(self.result,UDim2.fromOffset(640,600),UDim2.new(0.5,-320,0.5,-300),"MatchResult")
 self.resultBody=body; body.ClipsDescendants=true
 self.resultHeading = text(body,"戰後覆盤",UDim2.new(1,-24,0,32),UDim2.fromOffset(12,12),28,C.gold,Enum.Font.SourceSansBold); self.resultHeading.TextXAlignment = Enum.TextXAlignment.Center
 self.resultHeading.Name="ReportHeading"
 self.resultDescription = text(body,"",UDim2.new(1,-24,0,30),UDim2.fromOffset(12,47),16,C.white); self.resultDescription.TextXAlignment = Enum.TextXAlignment.Center
 self.resultDescription.Name="ReportSummary"
 self.reportScroll=make("ScrollingFrame",body,{Name="ReportContent",Size=UDim2.new(1,-24,1,-154),Position=UDim2.fromOffset(12,86),
  BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,90),ScrollBarThickness=4,ScrollingDirection=Enum.ScrollingDirection.Y,Active=true,ClipsDescendants=true})
 self.reportStatus=text(self.reportScroll,"覆盤資料尚未送達",UDim2.new(1,-16,0,80),UDim2.fromOffset(8,4),16,C.muted)
 self.reportStatus.Name="ReportStatus"
 self.reportStats=make("Frame",self.reportScroll,{Name="ReportStats",Size=UDim2.new(1,-6,0,610),BackgroundTransparency=1,Visible=false})
 self.reportRows={}; self.reportValues={resourcesDelivered={},resourcesSpent={}}
 local function row(kind,label,key,height)
  local frame=make("Frame",self.reportStats,{Name=key or kind,Size=UDim2.new(1,0,0,height),BackgroundColor3=C.card,BackgroundTransparency=(kind=="resource" or kind=="stat") and 0.45 or 1,BorderSizePixel=0})
  local caption=text(frame,label,UDim2.new(0.7,-24,1,0),UDim2.fromOffset(12,0),kind=="section" and 14 or 16,kind=="section" and C.gold or C.muted)
  local entry={frame=frame,caption=caption,kind=kind,height=height}
  if kind=="resource" or kind=="header" then
   entry.first=text(frame,kind=="header" and "交貨" or "—",UDim2.new(0.36,-8,1,0),UDim2.fromScale(0.28,0),16,C.white)
   entry.second=text(frame,kind=="header" and "淨支出" or "—",UDim2.new(0.36,-12,1,0),UDim2.fromScale(0.64,0),16,C.white)
   entry.first.TextXAlignment=Enum.TextXAlignment.Right; entry.second.TextXAlignment=Enum.TextXAlignment.Right
   entry.first.TextWrapped=false; entry.second.TextWrapped=false; entry.first.TextTruncate=Enum.TextTruncate.AtEnd; entry.second.TextTruncate=Enum.TextTruncate.AtEnd
   if kind=="resource" then
    entry.first.Name="ReportDelivered_"..key; entry.second.Name="ReportSpent_"..key
    self.reportValues.resourcesDelivered[key]=entry.first; self.reportValues.resourcesSpent[key]=entry.second
   end
  elseif kind=="stat" then
   entry.first=text(frame,"—",UDim2.new(0.3,-12,1,0),UDim2.fromScale(0.7,0),16,C.white)
   entry.first.TextXAlignment=Enum.TextXAlignment.Right; entry.first.Name="ReportValue_"..key; self.reportValues[key]=entry.first
   entry.first.TextWrapped=false; entry.first.TextTruncate=Enum.TextTruncate.AtEnd
  end
  table.insert(self.reportRows,entry)
 end
 row("section","資源交貨與淨支出",nil,26); row("header","資源",nil,28)
 for _,key in ipairs({"food","wood","gold","stone"}) do row("resource",reportLabels[key],key,34) end
 row("section","建造與生產",nil,26)
 for _,key in ipairs({"buildingsCompleted","villagersTrained","militaryTrained"}) do row("stat",reportLabels[key],key,34) end
 row("section","戰鬥紀錄",nil,26)
 for _,key in ipairs({"damageDealt","unitsKilled","buildingsKilled","unitsLost","buildingsLost"}) do row("stat",reportLabels[key],key,34) end
 row("note","交貨只計回到倉庫的資源；淨支出已扣除失敗退款。戰鬥損失不含投降後清場。",nil,70)
 self.resultContinue,self.resultContinueLabel = namedButton(body,"繼續觀戰",UDim2.fromOffset(228,44),UDim2.new(0,12,1,-56),function()
  self.dismissedResult = self.resultKey; self.result.Visible = false
  player:SetAttribute("RTSModalOpen",self:IsModalOpen())
 end,"WatchButton",C.muted)
 self.restartButton,self.restartLabel = namedButton(body,"返回戰局設定",UDim2.fromOffset(228,44),UDim2.new(0.5,6,1,-56),function()
  -- 對戰 place 每局獨立：每位玩家自行返回大廳 place，由伺服器判斷是否已可離開。
  if workspace:GetAttribute("PlaceRole")=="Match" then
   if player:GetAttribute("ReturningToLobby")~=true then lobbyCommand("ReturnToLobby") end
   return
  end
  if workspace:GetAttribute("MatchPhase")=="Ended" and workspace:GetAttribute("HostUserId") == player.UserId then self.callbacks.restart() end
 end,"RestartMatchButton",C.gold)
 self.restartButton:SetAttribute("Primary",true)
 self.reportState="missing"
end
function GUI:LayoutResult()
 local factor=self.scale.Scale
 local width=math.min(self.screen.AbsoluteSize.X-16,640)
 local height=math.min(self.screen.AbsoluteSize.Y-16,600)
 if width<=36 or height<=154 then return end
 self.resultBody.Size=UDim2.fromOffset(width/factor,height/factor)
 self.resultBody.Position=UDim2.new(0.5,-width/(2*factor),0.5,-height/(2*factor))
 self.resultHeading.Size=UDim2.new(1,-24/factor,0,32/factor); self.resultHeading.Position=UDim2.fromOffset(12/factor,12/factor); self.resultHeading.TextSize=28/factor
 self.resultDescription.Size=UDim2.new(1,-24/factor,0,30/factor); self.resultDescription.Position=UDim2.fromOffset(12/factor,47/factor); self.resultDescription.TextSize=16/factor
 self.reportScroll.Size=UDim2.new(1,-24/factor,0,(height-154)/factor); self.reportScroll.Position=UDim2.fromOffset(12/factor,86/factor)
 self.reportScroll.ScrollBarThickness=4/factor
 self.reportStatus.Size=UDim2.new(1,-16/factor,0,80/factor); self.reportStatus.Position=UDim2.fromOffset(8/factor,4/factor); self.reportStatus.TextSize=16/factor
 local y=0
 for _,entry in ipairs(self.reportRows) do
  entry.frame.Size=UDim2.new(1,0,0,entry.height/factor); entry.frame.Position=UDim2.fromOffset(0,y/factor)
  entry.caption.Position=UDim2.fromOffset(12/factor,0); entry.caption.TextSize=(entry.kind=="section" and 14 or entry.kind=="note" and 13 or 16)/factor
  entry.caption.Size=UDim2.new((entry.kind=="resource" or entry.kind=="header") and 0.28 or entry.kind=="stat" and 0.7 or 1,-24/factor,1,0)
  if entry.first then
   entry.first.Position=UDim2.fromScale(entry.second and 0.28 or 0.7,0); entry.first.Size=UDim2.new(entry.second and 0.36 or 0.3,-12/factor,1,0); entry.first.TextSize=16/factor
  end
  if entry.second then entry.second.Position=UDim2.fromScale(0.64,0); entry.second.Size=UDim2.new(0.36,-12/factor,1,0); entry.second.TextSize=16/factor end
  y+=entry.height+2
 end
 local pendingOffset=self.reportState=="pending" and 56 or 0
 self.reportStatus.Size=UDim2.new(1,-16/factor,0,(self.reportState=="pending" and 44 or 80)/factor)
 self.reportStats.Position=UDim2.fromOffset(0,pendingOffset/factor)
 self.reportStats.Size=UDim2.new(1,-6/factor,0,y/factor)
 self.reportScroll.CanvasSize=UDim2.fromOffset(0,((self.reportState=="ready" or self.reportState=="pending") and y+pendingOffset or 90)/factor)
 local buttonWidth=(width-36)/(2*factor)
 -- UDim offsets become integers. Round up before UIScale so fractional scales
 -- cannot shrink the actual click target below 44 screen pixels.
 local buttonHeight=math.ceil(44/factor)
 self.resultContinue.Size=UDim2.fromOffset(buttonWidth,buttonHeight); self.resultContinue.Position=UDim2.new(0,12/factor,1,-56/factor)
 self.restartButton.Size=UDim2.fromOffset(buttonWidth,buttonHeight); self.restartButton.Position=UDim2.new(0.5,6/factor,1,-56/factor)
 self.resultContinueLabel.TextSize=14/factor; self.restartLabel.TextSize=14/factor
end
function GUI:UpdateMatchReport(ended)
 local raw=player:GetAttribute("MatchReportJSON")
 if raw~=self.reportRaw then
  self.reportRaw=raw; self.matchReport=nil; self.reportState="missing"
  if raw~=nil and raw~="" then
   self.reportState="invalid"
   if type(raw)=="string" and #raw<=16384 then
    local ok,value=pcall(function() return HttpService:JSONDecode(raw) end)
    if ok and validReport(value) then self.matchReport=value; self.reportState=value.finished and "ready" or "pending" end
   end
  end
  self.reportScroll.CanvasPosition=Vector2.zero
  self.reportStats.Visible=self.reportState=="ready" or self.reportState=="pending"; self.reportStatus.Visible=self.reportState~="ready"
  self.reportStatus.Text=self.reportState=="invalid" and "資料無法顯示" or self.reportState=="pending" and "個人行動與存活紀錄已停止，等待隊伍結果。" or "覆盤資料尚未送達"
  local function display(label,value)
   label.Text=value~=nil and reportValue(value) or "—"
   label:SetAttribute("ReportValue",value)
  end
  for _,field in ipairs({"resourcesDelivered","resourcesSpent"}) do for _,key in ipairs({"food","wood","gold","stone"}) do display(self.reportValues[field][key],self.matchReport and self.matchReport[field][key]) end end
  for _,key in ipairs(reportCounters) do display(self.reportValues[key],self.matchReport and self.matchReport[key]) end
  self:LayoutResult()
 end
 local report=self.matchReport
 self.resultHeading.Text=report and (report.finished and (reportOutcomes[report.outcome].." · 戰後覆盤") or "等待隊伍結果") or (ended and "戰局結束" or "你的勢力已淘汰")
 self.resultDescription.Text=report and ("存活 "..reportDuration(report.survivalSeconds)) or (workspace:GetAttribute("PlaceRole")=="Match" and "你可以繼續觀戰，或返回大廳。" or "你可以繼續觀戰，或由房主開始新局。")
end
function GUI:UpdateLobby()
 local roomId=player:GetAttribute("LobbyRoomId") or "Room1"
 local portal
 for _,entry in ipairs(Config.Lobby.portals or {}) do if entry.id==roomId then portal=entry; break end end
 local queued = player:GetAttribute("LobbyQueued") == true
 local phase=workspace:GetAttribute("MatchPhase")
 local activeRoom=workspace:GetAttribute("ActiveBattleRoomId")
 -- 大廳 place 的房間各自出發（全域階段維持 Lobby），以房間狀態判斷；單一伺服器仍看全域階段。
 -- 對戰 place 沒有大廳：開局前一律顯示出發畫面（讀取票據、等待其他玩家抵達）。
 local starting=(workspace:GetAttribute("PlaceRole")=="Match" and phase~="Playing" and phase~="Ended")
  or queued and (lobbyRoomAttribute(roomId,"Status")=="Starting" or (phase=="Starting" and (activeRoom==nil or activeRoom==roomId)))
 local hostId=lobbyRoomAttribute(roomId,"HostUserId")
 local isHost=hostId==player.UserId and queued and not starting
 local changed=self.lobbyRoomId~=roomId or self.lobbyWasQueued~=queued or (isHost and not self.lobbyWasHost)
 local previousWizard=self.lobbyWizard
 if changed or not isHost then self.lobbyEditing=nil; self.lobbyConfigurePending=nil end
 self.lobbyRoomId=roomId
 self.lobbyWasQueued,self.lobbyWasHost=queued,isHost
 self.lobbyStarting=starting
 self.lobbyIsHost=isHost
 self.lobbyConfigured=lobbyRoomAttribute(roomId,"Configured")==true
 local civilization=Config.Civilizations and Config.Civilizations[player:GetAttribute("Civilization")]
 self.civilizationLabel.Text="文明："..(civilization and civilization.name or "載入中").."  ›"
 self.reviewCivilizationLabel.Text=self.civilizationLabel.Text
 for key,default in pairs(self.settings) do
  local value=lobbyRoomAttribute(roomId,key=="expectedPlayers" and "ExpectedPlayers" or "Setting_"..key)
  self.settings[key]=value~=nil and value or (portal and portal.settings[key]) or default
 end
 self:ArrangeLobbyFields()
 local gameMode=self.settings.gameMode
 local chapter=gameMode=="Story" and GameModes.chapter(self.settings.storyChapter) or nil
 local unlocked=self:StoryUnlocked()
 self.lobbyRevision=lobbyRoomAttribute(roomId,"SettingsRevision")
 local pending=self.lobbyConfigurePending
 if pending then
  local ack=player:GetAttribute("LobbyConfigureAck") or 0
  if ack~=pending.ack then
   if player:GetAttribute("LobbyConfigureAccepted")==true and player:GetAttribute("LobbyConfigureRoomId")==roomId then
    pending.accepted=true
   else self.lobbyConfigurePending=nil end
  end
  if pending.accepted and self.lobbyConfigured then
   self.lobbyConfigurePending=nil
   self.lobbyEditing=nil
  end
 end
 self.lobbyWizard=isHost and (not self.lobbyConfigured or self.lobbyEditing==true or self.lobbyConfigurePending~=nil)
 self.lobbyFrame:SetAttribute("RoomId",roomId)
 self.lobbyFrame:SetAttribute("Configurable",true)
 self.lobbyFrame:SetAttribute("WizardEnabled",self.lobbyWizard)
 self.lobbyFrame:SetAttribute("Configured",self.lobbyConfigured)
 self.lobbyFrame:SetAttribute("SetupPending",self.lobbyConfigurePending~=nil)
 local expectedPlayers = self.settings.expectedPlayers
 local aiCount = math.min(self.settings.aiCount,math.max(0,4-expectedPlayers))
 local humans = {}
 for _,human in ipairs(Players:GetPlayers()) do
  if human:GetAttribute("LobbyQueued") and (human:GetAttribute("LobbyRoomId") or "Room1")==roomId then table.insert(humans,human) end
 end
 table.sort(humans,function(a,b)
  if a == b then return false end
  if a.UserId == hostId then return true end
  if b.UserId == hostId then return false end
  local orderA,orderB = a:GetAttribute("LobbyJoinOrder") or math.huge,b:GetAttribute("LobbyJoinOrder") or math.huge
  if orderA ~= orderB then return orderA < orderB end
  return a.UserId < b.UserId
 end)
 local humanCount,readyCount = #humans,0
 self.lobbyHumanCount=humanCount
 self.lobbyFactionCount=expectedPlayers+aiCount
 for _,human in ipairs(humans) do if human:GetAttribute("LobbyReady") then readyCount += 1 end end
 local teamMode=self.settings.teamMode
 local previewReady=lobbyRoomAttribute(roomId,"TeamPreviewReady")==true
 self.canStart = self.lobbyConfigured and phase=="Lobby" and humanCount == expectedPlayers and readyCount == humanCount and previewReady
 self.lobbyWelcome.Visible=not queued and not starting and not self.tutorialInviteCovers
 self.lobbyFrame.Visible=queued and not starting
 self.startingTravel.Visible=starting
 self.lobbyBody.Visible=queued and not starting
 self.queueSummary.Text="劇情已通關 "..math.min(player:GetAttribute("StoryCleared") or 0,GameModes.ChapterCount).." / "..GameModes.ChapterCount.." 章 · 房主設定玩法，滿員且全員準備後自動出發。"
 local nextChapter=GameModes.chapter(unlocked)
 local quickDetails={StorySolo="第 "..unlocked.." 章 · "..(nextChapter and nextChapter.title or "").." · 立即出發",
  Story="2–3 人合作闖關",PvP="2–4 位真人對戰",PvE="與好友一起對抗電腦"}
 for _,quick in ipairs(self.quickButtons) do
  quick.detail.Text=quickDetails[quick.entry.id] or ""
  quick.button:SetAttribute("Unavailable",not waitingInLobby() or queued or starting)
 end
 for id,entry in pairs(self.portalCards) do
  local count=lobbyRoomAttribute(id,"Players") or 0
  local required=lobbyRoomAttribute(id,"ExpectedPlayers") or entry.portal.settings.expectedPlayers
  local status=lobbyRoomAttribute(id,"Status") or "Configuring"
  local computers=lobbyRoomAttribute(id,"Setting_aiCount") or entry.portal.settings.aiCount
  local roomSettings={gameMode=lobbyRoomAttribute(id,"Setting_gameMode") or entry.portal.settings.gameMode,
   storyChapter=lobbyRoomAttribute(id,"Setting_storyChapter"),teamMode=lobbyRoomAttribute(id,"Setting_teamMode") or entry.portal.settings.teamMode}
  local available=(status=="Waiting" or status=="Configuring") and waitingInLobby() and count<required
  entry.detail.Text=count==0 and status=="Configuring" and "劇情、對戰或合作\n由第一位進入的房主設定。" or GameModes.label(roomSettings).."\n"..required.." 位真人 · "..computers.." 位電腦"
  entry.button:SetAttribute("Unavailable",not available)
  entry.status.Text=status=="Configuring" and (count==0 and "空房間 · 進入設定  ›" or "設定中 · "..count.." / "..required.." 人")
   or status=="Waiting" and ((count>=required and "已滿員 · " or "等候中 · ")..count.." / "..required.." 人")
   or status=="Starting" and "隊伍正在出發…" or "對局進行中 · 稍後開放"
  entry.status.TextColor3=LB.white
 end
 self.lobbyHeading.Text=portal and portal.name or "匹配房間"
 self.lobbyDescription.Text=self.lobbyWizard and "選擇玩法與人數，再確認遊戲規則。" or (self.lobbyConfigured and "確認設定並準備；滿員且全員準備後自動出發。" or "房主正在設定模式與規則，先等候玩家加入。")
 self.reviewStatus.Text=self.lobbyConfigured and "等候玩家" or "房主正在設定"
 self.rosterHeading.Text = "集 合 名 單  ·  "..humanCount.." / "..expectedPlayers.." 人"
 self.readySummary.Text="準備 "..readyCount.." / "..humanCount
 self.readySummary.TextColor3=humanCount>0 and readyCount==humanCount and LB.green or LB.muted
 for _,id in ipairs(GameModes.Order) do
  local card=self.modeCards[id]
  card.button:SetAttribute("Selected",gameMode==id)
  card.button:SetAttribute("Unavailable",not self.lobbyWizard or self.lobbyConfigurePending~=nil)
  lobbyText(card.title,gameMode==id and LB.white or LB.text,LOBBY_TITLE_FONT,gameMode==id)
  lobbyText(card.detail,gameMode==id and LB.white or LB.muted,LOBBY_BODY_FONT,gameMode==id)
 end
 self.basicHint.Text=gameMode=="Story" and ("真人玩家同隊闖關；已解鎖到第 "..unlocked.." 章。") or Config.GameModes[gameMode] and Config.GameModes[gameMode].description or "選擇玩法，再決定人數與對手。"
 self.advancedHint.Text=gameMode=="Story" and "這一章的戰場規則；換章節就會換規則。" or "已有預設規則；可直接完成設定，或再調整這場遊戲。"
 self.advancedHeading.Text=gameMode=="Story" and "章節規則" or "遊戲設定"
 self.lobbyStepButtons[2].label.Text="2  "..(gameMode=="Story" and "章節規則" or "遊戲設定")
 self.storyBriefing.Text=chapter and (chapter.briefing.."\n目標："..chapter.objective..(chapter.aiCount>aiCount and "\n多人時敵方陣營減為 "..aiCount.." 個（出生點有限）。" or "")) or ""
 for key,entry in pairs(self.settingLabels) do
  local editable=self.lobbyWizard and not self.lobbyConfigurePending and not entry.locked and (key ~= "aiCount" or expectedPlayers < 4)
  local value = self.settings[key]
  local shown=key=="teamMode" and TeamClient.ModeLabel(value,expectedPlayers,aiCount)
   or key=="expectedPlayers" and gameMode=="Story" and (value==1 and "單人" or value.." 人合作")
   or entry.field.names and entry.field.names[value] or tostring(value)
  entry.label.Text = shown..(key=="storyChapter" and value==unlocked and (player:GetAttribute("StoryCleared") or 0)<GameModes.ChapterCount and "（最新）" or "")..(entry.locked and "（章節）" or "")..(editable and "  ›" or "")
  entry.label.TextColor3 = editable and LB.text or LB.muted
  entry.button:SetAttribute("Unavailable",not editable)
  entry.button.SettingIndicator.BackgroundTransparency=editable and 0.45 or 0.86
 end
 for i,label in ipairs(self.lobbyRows) do
  local human = humans[i]
  if human then
   local ready = human:GetAttribute("LobbyReady") == true
   local teamLabel=previewReady and TeamClient.TeamLabel(teamMode,human:GetAttribute("LobbyTeamId")) or "分隊待確認"
   label.Text = (ready and "✓  " or "●  ")..human.DisplayName.." · "..teamLabel..(human.UserId == hostId and " · 房主" or "")..(ready and " · 已準備" or " · 未準備")
   label.TextColor3 = ready and LB.green or LB.text
  elseif i <= expectedPlayers then label.Text = "○  等候玩家加入傳送門"; label.TextColor3 = LB.muted
  elseif i <= expectedPlayers+aiCount then
   local aiIndex=i-expectedPlayers
   local teamLabel=previewReady and TeamClient.TeamLabel(teamMode,lobbyRoomAttribute(roomId,"AITeam_"..aiIndex)) or "分隊待確認"
   local enemy=chapter and (chapter.enemy..(aiCount>1 and " "..aiIndex or "")) or "電腦 "..aiIndex
   label.Text = "◆  "..enemy.." · "..teamLabel.." · 已準備"; label.TextColor3 = LB.gold
  else label.Text = "○  空位"; label.TextColor3 = LB.muted end
  label.Parent.RosterStateAccent.BackgroundColor3=label.TextColor3
  label.Parent.Visible=i<=self.lobbyFactionCount
 end
 local battlefieldBusy=phase~="Lobby" and not starting
 self.hostLabel.Text=self.lobbyConfigurePending and "正在確認房間設定…"
  or self.lobbyWizard and (self.lobbyPage==1 and "先選玩法與人數，再前往下一步。" or gameMode=="Story" and "確認章節規則；完成設定後開放準備。" or "規則可沿用預設；完成設定後開放準備。")
  or not self.lobbyConfigured and "房主完成設定後，就可以準備。"
  or battlefieldBusy and "戰場尚未開放。可先集合與準備，開放後自動出發。"
  or (humanCount<expectedPlayers and ("還差 "..(expectedPlayers-humanCount).." 位玩家 · 可先完成準備"))
  or (readyCount<humanCount and ("確認本場設定，再按準備完成 · "..readyCount.." / "..humanCount.." 人已準備"))
  or "全員已準備，正在匹配全新戰場…"
 local readyAvailable=not starting and self.lobbyConfigured and not self.lobbyWizard
 self.readyButton:SetAttribute("Unavailable",not readyAvailable)
 self.readyLabel.Text=starting and "正在出發…" or not self.lobbyConfigured and "等待房主完成設定" or (player:GetAttribute("LobbyReady") and "取消準備" or "準備完成  ✓")
 self.readyLabel.TextColor3 = LB.white
 self.completeLobbySetup:SetAttribute("Unavailable",self.lobbyConfigurePending~=nil)
 self.completeLobbyLabel.Text=self.lobbyConfigurePending and "正在確認設定…" or "完成設定，等候玩家  ✓"
 self.previousLobbyPage:SetAttribute("Unavailable",self.lobbyConfigurePending~=nil)
 self.nextLobbyPage:SetAttribute("Unavailable",self.lobbyConfigurePending~=nil)
 for i,entry in ipairs(self.lobbyStepButtons) do entry.button:SetAttribute("Unavailable",i==3 or self.lobbyConfigurePending~=nil) end
 self.leaveButton:SetAttribute("Unavailable",starting)
 self.civilizationButton:SetAttribute("Unavailable",starting)
 self.reviewCivilizationButton:SetAttribute("Unavailable",starting)
 local victoryText = self.settings.victory == "Regicide" and (teamMode=="FFA" and "保護你的起始市鎮中心。\n起始主城失守即淘汰。" or "保護你的起始市鎮中心。\n起始主城失守即淘汰；盟友仍可繼續作戰。")
  or self.settings.victory == "Wonder" and ("完工後守住世界奇觀 "..(Config.Settings.wonderVictoryTime or 180).." 秒即可勝利。\n消滅其餘勢力也能獲勝。")
  or self.settings.victory == "Relic" and ("用僧侶把全圖聖物存放到自己"..(teamMode=="FFA" and "" or "隊伍").."的修道院，守住 "..Config.Relics.victoryTime.." 秒即可勝利。\n消滅其餘勢力也能獲勝。")
  or (teamMode=="FFA" and "消滅敵方全部單位與建築。\n最後存活的勢力獲勝；沒有對手可自由建設。" or "消滅敵隊全部陣營；盟友不可互相攻擊。\n各自管理資源與單位，最後存活的隊伍獲勝。")
 self.reviewSummary.Text=GameModes.label(self.settings).." · "..expectedPlayers.." 真人＋"..aiCount.." 電腦\n"
  ..self.settingLabels.size.field.names[self.settings.size].."戰場 · 人口上限 "..self.settings.population.."\n"
  ..self.settingLabels.startingResources.field.names[self.settings.startingResources]..(aiCount>0 and " · 電腦難度："..self.settingLabels.difficulty.field.names[self.settings.difficulty] or "")
 self.rules.Text=chapter and ("目標："..chapter.objective) or (self.settingLabels.victory.field.names[self.settings.victory].." · "..victoryText)
 self.travelStatus.Text=lobbyRoomAttribute(roomId,"TravelStage") or workspace:GetAttribute("MatchLoadStage") or "正在生成地圖與資源…"
 if changed or (self.lobbyWizard and not previousWizard) then self:SetLobbyPage(self.lobbyWizard and 1 or 3)
 elseif not self.lobbyWizard and self.lobbyPage~=3 then self:SetLobbyPage(3) end
 self:LayoutLobby()
end
function GUI:MinimapPosition(screenPoint)
 if not self.map or not visibleInTree(self.map) or self:IsModalOpen() or UIS:GetFocusedTextBox() then return nil end
 if typeof(screenPoint)~="Vector2" or not Grid.isFinite(screenPoint.X) or not Grid.isFinite(screenPoint.Y) then return nil end
 local point = screenPoint-GuiService:GetGuiInset()
 local pos,size = self.map.AbsolutePosition,self.map.AbsoluteSize
 if size.X<=0 or size.Y<=0 or not TouchRules.inRect(point.X,point.Y,pos.X,pos.Y,size.X,size.Y) then return nil end
 -- AbsolutePosition/Size already include UIScale; subtract the core UI inset only once.
 return Vector3.new(((point.X-pos.X)/size.X-0.5)*mapSize(),0,((point.Y-pos.Y)/size.Y-0.5)*mapSize())
end
function GUI:BlocksPointer(screenPoint)
 local point = (screenPoint or UIS:GetMouseLocation())-GuiService:GetGuiInset()
 for _,area in ipairs(self.hitAreas) do
  if area.Parent and visibleInTree(area) then
   local pos,size = area.AbsolutePosition,area.AbsoluteSize
   if TouchRules.inRect(point.X,point.Y,pos.X,pos.Y,size.X,size.Y) then return true end
  end
 end
 return false
end
function GUI:IsModalOpen()
 return GuiService.MenuIsOpen or (self.deleteConfirm and self.deleteConfirm.Visible) or (self.result and self.result.Visible) or (self.menuPanel and self.menuPanel.Visible) or (self.hotkeyPanel and self.hotkeyPanel.Visible) or (self.lobby and self.lobby.Visible and (player:GetAttribute("LobbyQueued") == true or (self.startingTravel and self.startingTravel.Visible)))
end
function GUI:ToggleMenu()
 if self.menuPanel.Visible then self.menuPanel.Visible=false
 elseif not self:IsModalOpen() then self.menuPanel.Visible=true end
 player:SetAttribute("RTSModalOpen",self:IsModalOpen())
end
-- 通知列依文字行數長高；劇情簡報等多行通知不會被截掉。
function GUI:FitNotice()
 local width=self.noticePanel.Size.X.Offset
 local bounds=game:GetService("TextService"):GetTextSize(self.notice.Text,self.notice.TextSize,self.notice.Font,Vector2.new(math.max(1,width-48),10000))
 self.noticePanel.Size=UDim2.fromOffset(width,math.max(self.touchLayout and 44 or 42,math.ceil(bounds.Y)+14))
end
function GUI:Notify(message,cue)
 if type(message) ~= "string" then return end
 if cue then Audio:Play(cue) end
 self.notice.Text = message; self:FitNotice(); self.noticePanel.Visible = true; self.noticePanel.BackgroundTransparency = self.reducedMotion and 0.04 or 0.28
 if not self.reducedMotion then tween(self.noticePanel,0.2,{BackgroundTransparency = 0.04}) end
 self.messageTime = os.clock()
end
function GUI:SetTab(tab)
 self.tab,self.page,self.commandKey,self.buildCategory = tab,1,nil,nil
 if tab=="build" and self.callbacks and self.callbacks.cancel then self.callbacks.cancel() end
 if self.selected then self:UpdateCommands(self.selected,self.buildingKind) end
end
function GUI:ShowBuildCategories()
 if buildMenuAvailable(self.selected or {}) then self:SetTab("build") end
end
function GUI:LayoutBuildCategories()
 local width=self.bottom.Size.X.Offset
 for i,entry in ipairs(self.buildPageButtons) do
  entry.button.Position=self.touchLayout and UDim2.fromOffset(8+(i-1)*(width-10)/3,48) or UDim2.fromOffset(13+(i-1)*196,62)
  entry.button.Size=self.touchLayout and UDim2.fromOffset((width-28)/3,78) or UDim2.fromOffset(182,100)
  local cardWidth=entry.button.Size.X.Offset
  entry.stage.Size=UDim2.fromOffset(cardWidth-16,self.touchLayout and 43 or 53)
  entry.view.Size=UDim2.fromOffset(cardWidth-16,self.touchLayout and 46 or 56)
  entry.label.Position=UDim2.fromOffset(10,self.touchLayout and 49 or 58)
  entry.label.Size=UDim2.new(1,-30,0,self.touchLayout and 24 or 23); entry.label.TextSize=self.touchLayout and 16 or 18
  entry.detail.Visible=not self.touchLayout
  entry.arrow.Position=UDim2.new(1,-26,0,self.touchLayout and 48 or 58)
 end
 self.buildCategoryHint.Position=self.touchLayout and UDim2.fromOffset(12,2) or UDim2.fromOffset(13,36)
 self.buildCategoryHint.Size=self.touchLayout and UDim2.fromOffset(width-24,44) or UDim2.fromOffset(582,20)
 self.buildCategoryTitle.Position=self.touchLayout and UDim2.fromOffset(12,2) or UDim2.fromOffset(304,7)
 self.buildCategoryTitle.Size=self.touchLayout and UDim2.fromOffset(width-184,44) or UDim2.fromOffset(124,23)
 self.backBuildCategories.Position=self.touchLayout and UDim2.fromOffset(width-164,2) or UDim2.fromOffset(438,7)
 self.backBuildCategories.Size=self.touchLayout and UDim2.fromOffset(156,44) or UDim2.fromOffset(156,23)
end
function GUI:SetBuildPage(page)
 if not buildMenuAvailable(self.selected or {}) or not Config.BuildPages[page] then return end
 self.tab,self.page,self.commandKey,self.buildCategory="build",page,nil,page
 self:UpdateCommands(self.selected,self.buildingKind)
end
function GUI:ChangePage(delta)
 if self.tab=="build" and not self.buildCategory then return end
 self.page = math.clamp(self.page+delta,1,self.pageCount or 1); self.commandKey = nil
 if self.tab=="build" then self.buildCategory=self.page end
 if self.selected then self:UpdateCommands(self.selected,self.buildingKind) end
end
function GUI:DefaultTrain()
 local model = self.selected and self.selected[1]
 if not model or model:GetAttribute("OwnerId") ~= player.UserId then return end
 local data = Config.Buildings[model:GetAttribute("BuildingType")]
 if data and data.trains and data.trains[1] then self.callbacks.train(data.trains[1]) end
end
function GUI:AdvanceAge()
 local model = self.selected and self.selected[1]
 if model and model:GetAttribute("OwnerId") == player.UserId then self.callbacks.age() end
end
function GUI:UpdateCommands(selected,buildingKind)
 local model = selected[1]; local owned = model and model:GetAttribute("OwnerId") == player.UserId
 local kind = model and (model:GetAttribute("BuildingType") or model:GetAttribute("UnitType"))
 local canBuild = buildMenuAvailable(selected)
 local currentFormation=formationSelection(selected)
 local formationPage=currentFormation~=nil and (self.tab=="formation" or not canBuild)
 self.hasFormationCommands=formationPage
 self.formationButton.Visible=currentFormation~=nil
 local ownedBuilding=owned and Config.Buildings[kind]~=nil
 -- 駐紮按鈕：選取自己的單位時顯示，按下後點建築進駐（快捷鍵 G）。
 local garrisonMode=player:GetAttribute("RTSGarrisonPlacement")==true
 self.garrisonButton.Visible=owned==true and not ownedBuilding
 self.garrisonEdge.Color=garrisonMode and C.gold or C.edge
 self.buildHelp.Size=UDim2.fromOffset(not self.touchLayout and (self.garrisonButton.Visible and 196 or currentFormation and 280) or 378,25)
 if self.tab=="build" and not canBuild then self.tab=ownedBuilding and "train" or "orders"; self.page=1; self.buildCategory=nil end
 if canBuild and self.tab~="build" and self.tab~="formation" then self.tab="build"; self.page=1; self.buildCategory=nil end
 if self.tab=="formation" and not currentFormation then self.tab=canBuild and "build" or ownedBuilding and "train" or "orders"; self.page=1; self.buildCategory=nil end
 local buildMenu=canBuild and self.tab=="build"
 local choosingBuildCategory=buildMenu and self.buildCategory==nil
 local categoryColor=tostring(previewColor())
 if choosingBuildCategory and categoryColor~=self.categoryPreviewColor then
  self.categoryPreviewColor=categoryColor
  for _,entry in ipairs(self.buildPageButtons) do
   local size,position=entry.view.Size,entry.view.Position
   entry.view:Destroy(); entry.view=viewport(entry.button,entry.art,size,position); entry.view.Name="CategoryModel"
  end
 end
 self:LayoutBuildCategories()
 for tab,entry in pairs(self.tabButtons) do entry.button.Visible=not canBuild and tab~="build" and ownedBuilding==true end
 for i,entry in ipairs(self.buildPageButtons) do
  entry.button.Visible=choosingBuildCategory; entry.edge.Color=C.edge; entry.label.TextColor3=C.gold
 end
 self.buildCategoryHint.Visible=choosingBuildCategory
 self.buildCategoryHint.Text=(#selected==0 and canBuild) and "選擇建造分類 · 未選村民時自動派最近的村民施工" or "選擇建造分類"
 self.buildCategoryTitle.Visible=buildMenu and not choosingBuildCategory
 self.buildCategoryTitle.Text=self.buildCategory and Config.BuildPages[self.buildCategory].name.."建築" or ""
 self.backBuildCategories.Visible=buildMenu and not choosingBuildCategory
 self.commandHolder.Visible=not choosingBuildCategory
 if self.touchLayout then
  local width=self.bottom.Size.X.Offset
  self.context.Visible=not canBuild; self.context.Position=UDim2.fromOffset(12,2)
  self.context.Size=UDim2.fromOffset((width-16)/3-16,44)
  self.context.TextSize=14; self.context.TextWrapped=false; self.context.TextTruncate=Enum.TextTruncate.AtEnd
  self.context.Text=#selected>1 and (#selected.." 個單位") or model and (model:GetAttribute("DisplayName") or model.Name) or "選取目標"
  if ownedBuilding and model:GetAttribute("Complete")~=false then
   local research=model:GetAttribute("Research")
   local training=model:GetAttribute("Training")
   if research or training then
    local activeName=research or training
    local remaining=model:GetAttribute(research and "ResearchRemaining" or "TrainingRemaining") or 0
    local progress=model:GetAttribute(research and "ResearchProgress" or "TrainingProgress") or 0
    self.context.Text=(model:GetAttribute("DisplayName") or model.Name).."\n"..activeName.."\n"..math.ceil(remaining).."秒 · "..math.floor(math.clamp(progress,0,1)*100).."%"
    self.context.TextSize=12
   end
  end
 end
 local age = player:GetAttribute("Age") or 1
 local incomplete=ownedBuilding and model:GetAttribute("Complete")==false
 local garrisoned=ownedBuilding==true and (model:GetAttribute("Garrison") or 0)>0
 self.stopButton.Visible=owned==true and not ownedBuilding
 -- The lobby can assign a different slot color before a new match. Rebuild the
 -- cached art when it changes, retaining the existing locked-age presentation.
 -- 兵種升級會改變訓練卡片上的名稱，名稱變了就重建卡片。
 local upgradedNames = {}
 for _,unitKind in ipairs(ownedBuilding and Config.Buildings[kind].trains or {}) do table.insert(upgradedNames,player:GetAttribute("UnitName_"..unitKind) or "") end
 local key = table.concat({self.tab,self.page,self.buildCategory or "categories",kind or "",table.concat(upgradedNames,","),model and "target" or "empty",owned and "owned" or "foreign",canBuild and "builders" or "no-builders",formationPage and "formations" or "normal",incomplete and "incomplete" or "complete",garrisoned and "garrisoned" or "empty",age,tostring(previewColor()),player:GetAttribute("TownBell") and "bell" or "calm",
  #tributeAllies(),stanceSelection(selected) and "stances" or "nostance"},":")
 if key ~= self.commandKey then
  self.commandKey = key; self.commandHolder:ClearAllChildren(); self.emptyCommandHint=nil; self.commandEntries,self.buildButtons = {},{}; self.tooltip.Visible = false
  local actions = {}
  if formationPage then
   for _,formationKey in ipairs(Config.Formations.order) do
    local data=Config.Formations.types[formationKey]
    table.insert(actions,{key="Formation_"..formationKey,formation=formationKey,name=data.name,description=data.description.."\n改為列隊移動，取代目前工作；之後地面移動會沿用此陣形。",cost={},minAge=1,callback=function() self.callbacks.formation(formationKey) end})
   end
   -- 姿態（AOE2 式）：只對能作戰的軍隊有效。
   if stanceSelection(selected) then
    for _,stanceKey in ipairs(Config.Stances.order) do
     local data=Config.Stances.types[stanceKey]
     table.insert(actions,{key="Stance_"..stanceKey,name=data.short,description=data.name.."：\n"..data.description,cost={},minAge=1,icon=stanceIcons[stanceKey],
      costLabel=function() return stanceSelection(self.selected or {})==stanceKey and "使用中" or "切換姿態" end,
      callback=function() if self.callbacks.stance then self.callbacks.stance(stanceKey) end end})
    end
   end
  elseif self.tab == "build" and canBuild and self.buildCategory then
   for _,item in ipairs(BuildMenuRules.items(Config,self.page,age)) do
    local buildKind=item.kind
    local data = Config.Buildings[buildKind]
    table.insert(actions,{key = buildKind,name = data.name,description = data.description,cost = data.cost,minAge = data.minAge or 1,art = buildKind,requiresBuilders = true,callback = function() self.callbacks.build(buildKind) end})
   end
  elseif self.tab == "train" and owned and Config.Buildings[kind] then
   for _,unitKind in ipairs(Config.Buildings[kind].trains or {}) do
    local data = Config.Units[unitKind]
    -- 其他文明的專屬兵種不顯示（伺服器同樣拒絕）。
    if data.civilization and data.civilization ~= player:GetAttribute("Civilization") then continue end
    local upgradedName = player:GetAttribute("UnitName_"..unitKind)
    table.insert(actions,{key = unitKind,name = upgradedName or data.name,description = (upgradedName and ("已升級為"..upgradedName.."。\n") or "")..data.description,cost = data.cost,minAge = data.minAge or 1,requires = data.requiresTech,art = unitKind,callback = function() self.callbacks.train(unitKind) end})
   end
   if kind == "TownCenter" then
    -- 城鎮警鐘：村民躲進最近的駐紮建築；再按一次解除警報。
    local ringing = player:GetAttribute("TownBell") == true
    table.insert(actions,1,{key = "TownBell",name = ringing and "解除警報" or "城鎮警鐘",icon = "bell",symbol = ringing and "✓" or "!",
     description = ringing and "解除警報：駐紮中的村民離開建築，回到原本的工作。" or "敲響城鎮警鐘：所有村民立刻躲進最近、仍有空位的市鎮中心、瞭望塔或城堡；駐軍會讓建築多射箭。\n再按一次解除警報。",
     cost = {},minAge = 1,costLabel = ringing and "警報中" or "全員駐紮",callback = function() if self.callbacks.townBell then self.callbacks.townBell() end end})
   end
   if kind == "Market" then
    -- 浮動價格：伺服器發布目前報價；所有玩家的買賣都會改變價格。
    local trade = Config.MarketTrade
    for _,resourceKey in ipairs({"food","wood","stone"}) do
     local resourceName = ({food = "食物",wood = "木材",stone = "石材"})[resourceKey]
     local buyCost,sellCost = {gold = trade.buyGold},{[resourceKey] = trade.batch}
     table.insert(actions,{key = "Buy_"..resourceKey,name = "購買"..resourceName,description = "用黃金買入 "..trade.batch.." "..resourceName.."。\n價格由所有玩家的買賣決定：每次買入都會漲價。",
      cost = buyCost,costLabel = function() buyCost.gold = workspace:GetAttribute("MarketBuy_"..resourceKey) or trade.buyGold; return "金"..buyCost.gold.." → "..trade.batch end,
      minAge = 2,callback = function() self.callbacks.trade(resourceKey,"Buy") end})
     table.insert(actions,{key = "Sell_"..resourceKey,name = "出售"..resourceName,description = "賣出 "..trade.batch.." "..resourceName.."換黃金。\n價格由所有玩家的買賣決定：每次賣出都會跌價。",
      cost = sellCost,costLabel = function() return trade.batch.." → 金"..(workspace:GetAttribute("MarketSell_"..resourceKey) or trade.sellGold) end,
      minAge = 2,callback = function() self.callbacks.trade(resourceKey,"Sell") end})
    end
    -- 進貢：選擇盟友後送出 100（按住 Shift 為 500）；另付手續費，鑄幣／銀行業可減免。
    local allies = tributeAllies()
    if #allies > 0 then
     local function recipient()
      local list = tributeAllies()
      for _,faction in ipairs(list) do if faction.id == self.tributeTarget then return faction end end
      self.tributeTarget = list[1] and list[1].id or nil
      return list[1]
     end
     table.insert(actions,{key = "TributeTarget",name = "進貢對象",icon = "flag",description = "點一下切換要進貢的盟友。",cost = {},minAge = 1,
      costLabel = function() local target = recipient(); return target and target.name or "沒有盟友" end,
      callback = function()
       local list,index = tributeAllies(),0
       for i,faction in ipairs(list) do if faction.id == self.tributeTarget then index = i end end
       local nextTarget = list[index % math.max(1,#list) + 1]
       self.tributeTarget = nextTarget and nextTarget.id or nil
       if nextTarget then self:Notify("進貢對象："..nextTarget.name) end
      end})
     for _,resourceKey in ipairs(Config.Tribute.resources) do
      local resourceName = ({food = "食物",wood = "木材",gold = "黃金",stone = "石材"})[resourceKey]
      table.insert(actions,{key = "Tribute_"..resourceKey,name = "進貢"..resourceName,resource = resourceKey,symbol = "→",
       description = "把 100 "..resourceName.."送給進貢對象（按住 Shift 送 500）。\n需另付 "..math.floor(Config.Tribute.fee*100).."% 手續費；鑄幣減半、銀行業免除。",
       cost = {},minAge = 1,costLabel = function() local target = recipient(); return target and ("給 "..target.name) or "沒有盟友" end,
       callback = function()
        local target = recipient()
        if not target then self:Notify("目前沒有可以進貢的盟友。") return end
        if self.callbacks.tribute then self.callbacks.tribute(target.id,resourceKey) end
       end})
     end
    end
   end
  elseif self.tab == "research" and owned and Config.Buildings[kind] then
   if (kind == "TownCenter" or kind == "Castle") and age < 4 then
    local nextAge = Config.Ages and Config.Ages[age+1]
    table.insert(actions,{key = "AdvanceAge",name = "升級"..ageName(age+1),description = "需完成目前時代兩種不同的經濟或軍事建築。\n房屋、農田與防禦建築不計入；帝王時代也可用城堡。",cost = nextAge and nextAge.cost or {},minAge = age,art = "TownCenter",callback = function() self.callbacks.age() end})
   end
   local researchKeys = {}
   for _,techKey in ipairs(Config.TechnologyOrder or {}) do
    local data = Config.Technologies[techKey]
    if data and (data.building == kind or (type(data.building) == "table" and table.find(data.building,kind))) then table.insert(researchKeys,techKey) end
   end
   if #researchKeys == 0 then
    for techKey,data in pairs(Config.Technologies or {}) do if data.building == kind then table.insert(researchKeys,techKey) end end
    table.sort(researchKeys)
   end
   for _,techKey in ipairs(researchKeys) do
    local data = Config.Technologies[techKey]
    table.insert(actions,{key = techKey,name = data.name,description = data.description,cost = data.cost,minAge = data.minAge or 1,tech = true,requires = data.requires,art = data.upgrade and data.upgrade.unit or nil,callback = function() self.callbacks.research(techKey) end})
   end
   if kind == "Mill" then
    local farmCost,limit = Config.Buildings.Farm.cost,Config.Farms.queueLimit
    table.insert(actions,{key = "QueueFarm",name = "預置農田",description = "預先付款儲備一塊農田；任何農田耗盡時自動重新播種，不必另外下令。\n最多預置 "..limit.." 塊。",
     cost = farmCost,minAge = 1,art = "Farm",costLabel = function() return "已預置 "..(player:GetAttribute("FarmQueue") or 0).." / "..limit end,callback = function() self.callbacks.farmQueue(true) end})
    table.insert(actions,{key = "UnqueueFarm",name = "取消預置",description = "取消一塊預置的農田，全額退回："..Grid.costText(farmCost),
     cost = {},minAge = 1,symbol = "−",costLabel = function() return (player:GetAttribute("FarmQueue") or 0) > 0 and "退回一塊" or "尚無預置" end,callback = function() self.callbacks.farmQueue(false) end})
   end
  end
  if garrisoned and (self.tab=="train" or self.tab=="research") then
   -- 有駐軍時排在最前面，任何分頁都看得到。
   table.insert(actions,1,{key="Ungarrison",name="全部離開",description="讓駐紮在這座建築裡的單位全部離開，出現在建築周圍；有集合點時會前往集合點。快捷鍵 "..self:HotkeyLabel("garrison").."。",cost={},minAge=1,symbol="→",
    costLabel=function() local target=self.selected and self.selected[1]; return target and ("駐軍 "..(target:GetAttribute("Garrison") or 0).." 位") or "" end,
    callback=function() if self.callbacks.ungarrison then self.callbacks.ungarrison() end end})
  end
  if currentFormation and (formationPage or not canBuild) then
   table.insert(actions,{key="Stop",name="停止",description="停止所選單位的目前指令。快捷鍵 "..self:HotkeyLabel("stop").."。",cost={},minAge=1,symbol="■",callback=self.callbacks.stop})
  end
  local buildPage=buildMenu and self.buildCategory~=nil
  local singleRow=buildPage or formationPage
  local slots=singleRow and #actions or (self.touchLayout and 4 or 6)
  local cardWidth=self.touchLayout and math.floor((self.commandHolder.Size.X.Offset-18)/4) or 92
  self.pageCount = buildPage and #Config.BuildPages or math.max(1,math.ceil(#actions/slots)); self.page = math.min(self.page,self.pageCount)
  local scrollBuild=singleRow and self.touchLayout and #actions>4
  self.commandHolder.ScrollingEnabled=scrollBuild; self.commandHolder.ScrollBarThickness=scrollBuild and 3 or 0
  self.commandHolder.CanvasPosition=Vector2.zero
  self.commandHolder.CanvasSize=UDim2.fromOffset(scrollBuild and (#actions*(cardWidth+6)-6) or self.commandHolder.Size.X.Offset,self.commandHolder.Size.Y.Offset)
  for i = 1,slots do
   local action = actions[singleRow and i or (self.page-1)*slots+i]
   if action then
    local b,edge = button(self.commandHolder,UDim2.fromOffset(cardWidth,self.touchLayout and 78 or 70),UDim2.fromOffset((self.touchLayout and singleRow and (i-1) or (i-1)%(self.touchLayout and 4 or 6))*(cardWidth+6),self.touchLayout and 0 or math.floor((i-1)/6)*74),function()
     if incomplete then self:Notify("建築施工尚未完成。指派村民繼續施工。") return end
     if action.requiresBuilders and not buildMenuAvailable(self.selected or {}) then self:Notify("只有村民能建造。請只選取自己的村民，再選擇建築。") return end
     if (player:GetAttribute("Age") or 1) < action.minAge then self:Notify("需要"..ageName(action.minAge).."才能使用。") return end
     if action.requiresBuilders and not affordable(action.cost) then self:Notify("資源不足，請先採集或交換資源。") return end
     if action.tech and researched(action.key) then self:Notify("這項科技已完成研究。") return end
     if action.requires and not researched(action.requires) then self:Notify("需要先研究"..Config.Technologies[action.requires].name.."。") return end
     action.callback()
    end,"Command_"..action.key)
    b.MouseEnter:Connect(function()
     if not UIS.MouseEnabled or self:IsModalOpen() then return end
     local requirement = action.requires and (" · 前置："..Config.Technologies[action.requires].name) or ""
     local builderRequirement = action.requiresBuilders and (selectedBuilders(self.selected or {}) and "\n已選村民會走到工地，到達後開始施工。" or buildMenuAvailable(self.selected or {}) and "\n未選村民：放置後自動派最近的村民施工。" or "\n需只選取自己的村民才能建造。") or ""
     self.tooltipText.Text = action.name.."  ·  "..ageName(action.minAge)..requirement.."\n"..(action.description or "")..builderRequirement.."\n"..Grid.costText(action.cost)
     self.tooltip.Visible = true
    end)
    b.MouseLeave:Connect(function() self.tooltip.Visible = false end)
    local stage
    if not self.touchLayout then stage=previewStage(b,UDim2.fromOffset(cardWidth-8,34),UDim2.fromOffset(4,3)) end
    local icon
    if action.formation then icon=formationIcon(b,action.formation,cardWidth)
    elseif action.art and Config.Units[action.art] then icon=UnitIcons.Create(b,action.art,UDim2.fromOffset(40,36),UDim2.fromOffset((cardWidth-40)/2,1),previewColor())
    elseif action.art and not self.touchLayout then icon=viewport(b,action.art,UDim2.fromOffset(cardWidth-10,41),UDim2.fromOffset(5,-1))
    elseif self.touchLayout then icon=text(b,action.name,UDim2.new(1,-8,0,32),UDim2.fromOffset(4,2),15,C.white); icon.TextXAlignment=Enum.TextXAlignment.Center
    else icon=commandSymbol(b,action,cardWidth) end
    icon.Name="CommandIcon"
    if action.requiresBuilders and age<action.minAge and icon:IsA("ViewportFrame") then
     for _,part in ipairs(icon:GetDescendants()) do
      if part:IsA("BasePart") then local shade=part.Color.R*0.299+part.Color.G*0.587+part.Color.B*0.114; part.Color=Color3.new(shade,shade,shade) end
     end
    end
    local title = text(b,action.name,UDim2.fromOffset(84,17),UDim2.fromOffset(4,37),13,C.white,Enum.Font.SourceSansSemibold); title.TextXAlignment = Enum.TextXAlignment.Center; title.TextWrapped=false; title.TextTruncate=Enum.TextTruncate.AtEnd
    local cost = text(b,compactCost(action.cost),UDim2.fromOffset(86,15),UDim2.fromOffset(3,54),11,C.muted); cost.TextXAlignment = Enum.TextXAlignment.Center
    title.Name="CommandTitle"; cost.Name="CommandCost"
    if self.touchLayout then
     local pictured=action.formation~=nil or (action.art and Config.Units[action.art]~=nil)
     title.Visible=pictured; title.Size=UDim2.new(1,-8,0,17)
     cost.Size=UDim2.new(1,-6,0,pictured and 20 or 38); cost.Position=UDim2.fromOffset(3,pictured and 55 or 34); cost.TextSize=13
    end
    local chips,chipLabels
    if not action.costLabel and not action.formation then chips,chipLabels=costChips(b,action.cost,cost,cardWidth-6,self.touchLayout and 15 or 13) end
    local entry = {button = b,edge = edge,cost = cost,title = title,icon=icon,stage=stage,action = action,chips=chips,chipLabels=chipLabels}; table.insert(self.commandEntries,entry)
    if self.tab == "build" then self.buildButtons[action.key] = entry end
   end
  end
  if #actions == 0 and not choosingBuildCategory then
   local help = buildPage and "此頁尚無目前或下一時代的建築。\n升級時代後會自動顯示。" or not model and ("選取村民，開啟建築與採集指令。\n按 "..self:HotkeyLabel("selectHome").." 選主城 · 按 "..self:HotkeyLabel("selectIdle").." 找閒置村民") or not owned and "可查看此目標的資訊。\n選取自己的單位或建築下達指令。" or self.tab == "train" and "此建築沒有訓練單位。\n開啟科技頁查看可研究項目。" or "此建築沒有可研究項目。"
   self.emptyCommandHint=text(self.commandHolder,help,UDim2.new(1,-42,1,0),UDim2.fromOffset(21,0),16,C.muted)
   self.emptyCommandHint.TextXAlignment = Enum.TextXAlignment.Center
  end
 end
 for tab,entry in pairs(self.tabButtons) do
  entry.edge.Color = self.tab == tab and C.gold or C.edge; entry.label.TextColor3 = self.tab == tab and C.gold or C.muted
  entry.button:SetAttribute("Selected",self.tab==tab)
 end
 for _,entry in ipairs(self.commandEntries) do
  local action = entry.action; local locked = age < action.minAge; local done = action.tech and researched(action.key)
  local missingTech = action.requires and not researched(action.requires)
  local missingBuilders = action.requiresBuilders and not canBuild
  local ageLocked=action.requiresBuilders==true and locked
  local shortage=action.requiresBuilders and not affordable(action.cost)
  entry.button:SetAttribute("AgeLocked",ageLocked)
  local activeFormation=action.formation and currentFormation==action.formation
  entry.button:SetAttribute("Selected",buildingKind==action.key or activeFormation==true)
  entry.button:SetAttribute("Unavailable",locked or done or missingTech or missingBuilders or incomplete or shortage); entry.edge.Color = (buildingKind == action.key or activeFormation) and C.gold or C.edge; entry.edge.Thickness = (buildingKind == action.key or activeFormation) and 2 or 1
  entry.button:SetAttribute("FormationActive",activeFormation==true)
  local grey=Color3.fromRGB(104,104,104)
  if ageLocked then if animations[entry.button] then animations[entry.button]:Cancel(); animations[entry.button]=nil end; entry.button.BackgroundColor3=Color3.fromRGB(184,184,184) end
  entry.title.TextColor3 = ageLocked and grey or (locked or missingBuilders) and C.muted or C.white
  if entry.icon:IsA("ViewportFrame") then entry.icon.ImageColor3=ageLocked and grey or Color3.new(1,1,1)
  elseif entry.icon:IsA("TextLabel") then entry.icon.TextColor3=ageLocked and grey or C.white end
  if entry.stage then entry.stage.BackgroundColor3=ageLocked and Color3.fromRGB(150,150,150) or Color3.new(1,1,1); entry.stage.BackgroundTransparency=locked and 0.25 or 0 end
  if entry.icon:GetAttribute("UnitType") then UnitIcons.SetMuted(entry.icon,locked or incomplete) end
  entry.cost.Text = incomplete and "施工未完成" or missingBuilders and "需選取己方村民" or (done and "已完成" or (locked and ("需要"..ageName(action.minAge)) or (missingTech and ("需"..Config.Technologies[action.requires].name) or (type(action.costLabel)=="function" and action.costLabel()) or action.costLabel or compactCost(action.cost))))
  entry.cost.TextColor3 = ageLocked and grey or done and C.green or (missingBuilders and C.muted or (affordable(action.cost) and C.muted or C.red))
  if action.formation then entry.cost.Text=activeFormation and "使用中" or "點選列隊"; entry.cost.TextColor3=activeFormation and C.gold or C.muted end
  if entry.chips then
   -- 狀態文字（需要時代、已完成…）仍用文字；顯示價格時改用圖示。
   local priced=entry.cost.Text==compactCost(action.cost)
   entry.chips.Visible=priced; entry.cost.TextTransparency=priced and 1 or 0
   if priced then
    for key,value in pairs(entry.chipLabels) do value.TextColor3=(player:GetAttribute(key) or 0)<action.cost[key] and C.red or C.muted end
   end
  end
 end
 if formationPage then self.buildHelp.Text=currentFormation=="Mixed" and "混合陣形 · 下次移動依首選單位" or ("陣形："..Config.Formations.types[currentFormation].name.." · 右鍵地面移動") end
 if self.tab == "build" and not canBuild then self.buildHelp.Text = "只有村民能建造 · 請只選取自己的村民" end
 self.pageLabel.Text = self.page.." / "..self.pageCount; self.pageLabel.Visible=not choosingBuildCategory
 self.previousPage.Visible = not choosingBuildCategory and self.pageCount > 1; self.nextPage.Visible = not choosingBuildCategory and self.pageCount > 1
end
function GUI:UpdateProduction(model)
 local kind=model and model:GetAttribute("BuildingType")
 local data=kind and Config.Buildings[kind]
 local enabled=model and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("Complete")==true and data and data.trains and #data.trains>0
 self.queueHolder.Visible=enabled==true
 if not enabled then self.queueKey=nil; return end
 local revision=model:GetAttribute("QueueRevision") or 0
 local queueKey=tostring(model)..":"..revision..":"..tostring(model:GetAttribute("RallyType"))..":"..tostring(previewColor(model))
 if self.queueModel~=model or self.queueKey~=queueKey then
  self.queueModel,self.queueKey=model,queueKey; self.queueHolder:ClearAllChildren()
  local count=model:GetAttribute("QueueCount") or 0
  local queueArea=self.queueHolder
  if self.touchLayout then
   queueArea=make("ScrollingFrame",self.queueHolder,{Name="QueueSlots",Size=UDim2.new(1,-116,1,0),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(math.max(0,count*48-4),0),ScrollBarThickness=2,ScrollingDirection=Enum.ScrollingDirection.X,ClipsDescendants=true,Active=true})
  end
  if count==0 then text(queueArea,"訓練佇列空白",UDim2.new(1,0,1,0),UDim2.fromOffset(0,0),12,C.muted) end
  for i=1,math.min(count,5) do
   local unitKind=model:GetAttribute("QueueKind_"..i)
   if Config.Units[unitKind] then
    local b=button(queueArea,UDim2.fromOffset(self.touchLayout and 44 or 34,self.touchLayout and 44 or 38),UDim2.fromOffset((i-1)*(self.touchLayout and 48 or 38),0),function()
     if self.selected and self.selected[1]==model and self.callbacks.cancelTraining then self.callbacks.cancelTraining(i,revision) end
    end,"QueueSlot_"..i)
    local icon=UnitIcons.Create(b,unitKind,UDim2.fromOffset(self.touchLayout and 38 or 32,self.touchLayout and 34 or 32),UDim2.fromOffset(self.touchLayout and 3 or 1,0),previewColor(model))
    icon.Name="QueueIcon"
    text(b,tostring(i),UDim2.fromOffset(12,12),UDim2.fromOffset(2,25),10,C.gold)
    if i==1 then
     local track=make("Frame",b,{Name="QueueProgress",Size=UDim2.new(1,-4,0,3),Position=UDim2.new(0,2,1,-4),BackgroundColor3=C.card,BorderSizePixel=0})
     make("Frame",track,{Name="Fill",Size=UDim2.fromScale(0,1),BackgroundColor3=C.gold,BorderSizePixel=0})
    end
    b.MouseEnter:Connect(function()
     if not self:IsModalOpen() then self.tooltipText.Text=Config.Units[unitKind].name.." · 點擊取消訓練\n退回此單位的訓練成本。\n"..Grid.costText(Config.Units[unitKind].cost); self.tooltip.Visible=true end
    end)
    b.MouseLeave:Connect(function() self.tooltip.Visible=false end)
   end
  end
  namedButton(self.queueHolder,"集合點",UDim2.fromOffset(self.touchLayout and 64 or 58,self.touchLayout and 44 or 38),self.touchLayout and UDim2.new(1,-110,0,0) or UDim2.fromOffset(202,0),function() if self.callbacks.rally then self.callbacks.rally() end end,"RallyButton",C.gold)
  if model:GetAttribute("RallyType") then
   namedButton(self.queueHolder,"×",UDim2.fromOffset(self.touchLayout and 44 or 30,self.touchLayout and 44 or 38),self.touchLayout and UDim2.new(1,-44,0,0) or UDim2.fromOffset(266,0),function() if self.callbacks.clearRally then self.callbacks.clearRally() end end,"ClearRallyButton",C.muted)
  end
 end
 local track=self.queueHolder:FindFirstChild("QueueProgress",true)
 if track then track.Fill.Size=UDim2.fromScale(math.clamp(model:GetAttribute("TrainingProgress") or 0,0,1),1) end
end
function GUI:UpdateEconomy()
 local now=os.clock()
 if self.economyTime and now-self.economyTime<0.6 then return end
 self.economyTime=now
 local idle,workers=0,{food=0,wood=0,gold=0,stone=0}
 local units=workspace:FindFirstChild("Units")
 if units then for _,unit in ipairs(units:GetChildren()) do
  if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" and (unit:GetAttribute("HP") or 0)>0 then
   if unit:GetAttribute("Order")=="待命" then idle+=1 end
   local key=unit:GetAttribute("WorkKind")
   if workers[key] then workers[key]+=1 end
  end
 end end
 self.idleLabel.Text=idle>0 and ("閒置 "..idle.." 位") or "閒置村民"; self.idleLabel.TextColor3=idle>0 and C.gold or C.muted
 self.idleCount.Text=idle>99 and "99+" or tostring(idle); self.idleBadge.Visible=idle>0
 self.idleButton:SetAttribute("Primary",idle>0)
 UnitIcons.SetMuted(self.idleIcon,idle==0)
 self.idleButton:SetAttribute("IdleCount",idle)
 for key,count in pairs(workers) do
  local label=self.resourceWorkers[key]
  label.Text=count>99 and "99+" or tostring(count); label.Parent.Visible=count>0
  self.resourceCards[key]:SetAttribute("Gatherers",count)
 end
end
function GUI:Update(selected,buildingKind)
 self.selected,self.buildingKind = selected,buildingKind
 local phase = workspace:GetAttribute("MatchPhase") or "Lobby"; local lobbyVisible = player:GetAttribute("InLobby")==true or phase == "Lobby" or phase == "Starting"
 if self.pendingDelete and (phase~="Playing" or workspace:GetAttribute("MatchGeneration")~=self.deleteGeneration or not deleteSelection(self.pendingDelete)) then self:CancelDelete() end
 self.deleteButton.Visible=phase=="Playing" and not player:GetAttribute("Spectator") and not player:GetAttribute("Defeated") and deleteSelection(selected)~=nil
 self.deleteButtonLabel.Text=deleteLabel(selected)=="死亡／拆除" and "死亡／拆除" or (deleteLabel(selected).." ["..self:HotkeyLabel("delete").."]")
 if self.lobby.Visible ~= lobbyVisible then self.lobby.Visible = lobbyVisible; if not lobbyVisible then self.dismissedResult = nil end end
 self.hudLayer.Visible = not lobbyVisible
 self.topScreen.Enabled=not lobbyVisible and not self.touchLayout
 if lobbyVisible and next(self.dots) then
  -- Release hidden minimap frames and their model references between matches.
  for model,dot in pairs(self.dots) do dot:Destroy(); self.dots[model]=nil end
 end
 self:UpdateGuidance(selected,phase)
 self:UpdateTouchDock(phase)
 self:UpdateTouchRotate(buildingKind)
 self.noticePanel.Position = self.touchLayout and UDim2.new(0,8,0,62) or UDim2.new(0.5,-277,0,8)
 if lobbyVisible then self.selectionBox.Visible = false; self.menuPanel.Visible = false; self.hotkeyPanel.Visible = false; self.hotkeyCapture = nil end
 if lobbyVisible then self:UpdateLobby() end
 local ended,defeated = phase == "Ended" or workspace:GetAttribute("MatchEnded"),player:GetAttribute("Defeated")
 self.menuEndLabel.Text = (ended or defeated) and "查看戰後覆盤" or "投降"
 local generation=tostring(workspace:GetAttribute("MatchGeneration") or 0)
 self.resultKey = ended and ("ended:"..generation) or (defeated and ("defeated:"..generation) or nil)
 local resultVisible = not lobbyVisible and self.resultKey ~= nil and self.dismissedResult ~= self.resultKey
 if resultVisible and not self.result.Visible then
  self.result.BackgroundTransparency = self.reducedMotion and 0.22 or 0.55
  if not self.reducedMotion then tween(self.result,0.25,{BackgroundTransparency = 0.22}) end
 end
 self.result.Visible = resultVisible
 if resultVisible then self.menuPanel.Visible=false; self.hotkeyPanel.Visible=false; self.hotkeyCapture=nil end
 self:UpdateMatchReport(ended)
 local modalOpen = self:IsModalOpen()
 if player:GetAttribute("RTSModalOpen") ~= modalOpen then player:SetAttribute("RTSModalOpen",modalOpen) end
 if resultVisible then
  if workspace:GetAttribute("PlaceRole")=="Match" then
   self.restartButton.Visible = true; self.restartLabel.Text = player:GetAttribute("ReturningToLobby")==true and "正在返回大廳…" or "返回大廳"
  else
   self.restartButton.Visible = ended; self.restartLabel.Text = workspace:GetAttribute("HostUserId") == player.UserId and "返回戰局設定" or "等待房主重新開局"
  end
 end
 local elapsed = math.max(0,math.floor(workspace:GetAttribute("MatchTime") or 0)); local age = player:GetAttribute("Age") or 1
 local clock = string.format("%02d:%02d",math.floor(elapsed/60),elapsed%60)
 local ageRemaining = player:GetAttribute("AgeRemaining") or 0
 local upgrading = ageRemaining > 0 and Config.Ages and Config.Ages[age+1] ~= nil
 if self.touchLayout then
  self.ageLabel.Text = ageName(age).." · "..clock..(ageRemaining > 0 and (" · 升級 "..math.ceil(ageRemaining).."秒") or "")
 else
  self.ageLabel.Text = ageName(age)
  self.ageNumeral.Text = ({"I","II","III","IV"})[age] or tostring(age)
  self.clockLabel.Text = upgrading and (clock.." · 升級 "..math.ceil(ageRemaining).."秒") or clock
  self.clockLabel.TextColor3 = upgrading and C.gold or C.muted
  self.ageTrack.Visible = upgrading
  if upgrading then self.ageFill.Size = UDim2.fromScale(math.clamp(1-ageRemaining/math.max(1,Config.Ages[age+1].time or 1),0,1),1) end
 end
 self:UpdateResources()
 self:UpdateEconomy()
 if self.messageTime and os.clock()-self.messageTime > 5 then self.noticePanel.Visible = false; self.messageTime = nil end
 local report=self.matchReport
 local teamMode=workspace:GetAttribute("TeamMode") or "FFA"
 if report and report.finished then self.objective.Text = reportOutcomes[report.outcome].." · 對局結果已確定\n可以查看戰後覆盤"
 elseif report and not report.finished then self.objective.Text = "個人勢力已淘汰\n等待隊伍結果 · 可以繼續觀戰"
 elseif defeated then self.objective.Text = teamMode~="FFA" and not player:GetAttribute("Forfeited") and "個人勢力已淘汰 · 等待隊伍結果" or "勢力已戰敗 · 可以繼續觀戰"
 elseif ended then self.objective.Text = "對局結束\n勝利者："..tostring(workspace:GetAttribute("Winner") or "—")
 elseif player:GetAttribute("Spectator") then self.objective.Text = "觀戰中 · 等待下一場戰局"
 elseif workspace:GetAttribute("VictoryMode") == "Regicide" then self.objective.Text = "保護你的起始主城\n摧毀敵方主城，取得勝利"
 elseif workspace:GetAttribute("VictoryMode") == "Wonder" then
  local remaining = player:GetAttribute("WonderRemaining") or 0
  self.objective.Text = remaining > 0 and ("世界奇觀已完工\n勝利倒數 "..math.ceil(remaining).." 秒") or ("升級帝王時代建造世界奇觀\n完工後守住 "..(Config.Settings.wonderVictoryTime or 180).." 秒")
 elseif workspace:GetAttribute("VictoryMode") == "Relic" then
  local remaining = player:GetAttribute("RelicRemaining") or 0
  local others = workspace:GetAttribute("RelicHoldRemaining")
  self.objective.Text = remaining > 0 and ("已集齊全部聖物\n勝利倒數 "..math.ceil(remaining).." 秒")
   or (others and ("敵方已集齊聖物！"..math.ceil(others).." 秒後獲勝\n派兵奪回聖物或摧毀修道院"))
   or ("聖物 "..(player:GetAttribute("Relics") or 0).." / "..(workspace:GetAttribute("RelicTotal") or 0).."\n用僧侶集齊全部聖物並守住 "..Config.Relics.victoryTime.." 秒")
 else self.objective.Text = "採集、升級、擴張\n消滅敵方全部單位與建築" end
 local factionList = factions()
 for i,row in ipairs(self.scoreRows) do
  local faction = factionList[i]
  if faction then
   local actor = faction.actor
   local remaining = actor:GetAttribute("WonderRemaining") or 0
   local actorTeam=actor:GetAttribute("TeamId")
   local won=ended and not actor:GetAttribute("Forfeited") and ((teamMode=="FFA" and workspace:GetAttribute("WinnerId")==faction.id)
    or (teamMode~="FFA" and type(actorTeam)=="number" and actorTeam>0 and workspace:GetAttribute("WinnerTeamId")==actorTeam))
   local finishedParticipant=ended and type(actorTeam)=="number" and actorTeam>0
   local noWinner=teamMode=="FFA" and workspace:GetAttribute("WinnerId")==0 or teamMode~="FFA" and workspace:GetAttribute("WinnerTeamId")==0
   local stateText=won and "勝利" or actor:GetAttribute("Forfeited") and "已投降" or finishedParticipant and (noWinner and "無勝者" or "戰敗")
    or actor:GetAttribute("Defeated") and (not ended and teamMode~="FFA" and "已淘汰 · 待結算" or "戰敗")
    or (remaining > 0 and ("奇觀 "..math.ceil(remaining).."秒")
     or (actor:GetAttribute("RelicRemaining") and ("聖物 "..math.ceil(actor:GetAttribute("RelicRemaining")).."秒"))
     or (workspace:GetAttribute("VictoryMode") == "Relic" and ("聖物 "..(actor:GetAttribute("Relics") or 0).." · 時代 "..(actor:GetAttribute("Age") or 1)))
     or ("時代 "..(actor:GetAttribute("Age") or 1)))
   local teamLabel=teamMode~="FFA" and (" · "..TeamClient.TeamLabel(teamMode,actorTeam)) or ""
   row.Text = (faction.ai and "◆ " or "")..faction.name..teamLabel.."  ·  "..stateText
   local teamColor = actor:GetAttribute("TeamColor")
   row.TextColor3 = won and C.green or (actor:GetAttribute("Defeated") and C.muted or C.white)
   self.scoreSwatches[i].Visible = true
   self.scoreSwatches[i].BackgroundColor3 = typeof(teamColor)=="Color3" and teamColor or C.muted
   self.scoreSwatches[i].BackgroundTransparency = actor:GetAttribute("Defeated") and 0.6 or 0
  else row.Text = ""; self.scoreSwatches[i].Visible = false end
 end
 if not self.touchLayout then
  -- The roster is only as tall as its factions and hangs under the objective card.
  self.scoreboard.Size=UDim2.fromOffset(230,38+math.max(1,math.min(4,#factionList))*28)
 end
 self.healthBack.Visible = false; self.healthText.Text = ""; self.productionBack.Visible = false
 self.selectionState.Visible=false; self.productionText.Visible=false; self.statLine.Text=""; self.queueHolder.Visible=false; self.mobileState.Visible=false
 self.details.Text=""
 self.details:SetAttribute("TargetOwnerId",nil); self.details:SetAttribute("TargetTeamId",nil)
 local targetRelation
 if buildingKind then
  local data = Config.Buildings[buildingKind]
  self.details.Text = "選擇建造位置\n村民到達後開始施工\n右鍵 / Esc 取消"; self.context.Text = "放 置  /  "..data.name; self.buildHelp.Text = data.line and "按住拖曳放置整排 · 綠色可建造 · 黃色資源不足 · 紅色跳過" or data.rotatable and ("綠色可以建造 · "..self:HotkeyLabel("research").." 旋轉方向 · 可蓋在自己的石牆上") or "綠色可以建造 · 放置後村民會走到工地"
 elseif #selected > 0 then
  local model = selected[1]
  targetRelation=TeamClient.Relation(teamMode,player.UserId,player:GetAttribute("TeamId"),model:GetAttribute("OwnerId"),model:GetAttribute("TeamId"))
  self.details:SetAttribute("TargetOwnerId",model:GetAttribute("OwnerId")); self.details:SetAttribute("TargetTeamId",model:GetAttribute("TeamId"))
  local kind = model:GetAttribute("UnitType") or model:GetAttribute("BuildingType") or (model:GetAttribute("Relic") and "Relic") or ({wood = "Tree",gold = "Gold",stone = "Stone",food = "Berries"})[model:GetAttribute("ResourceType")] or "TownCenter"
  local lines = {model:GetAttribute("OwnerName") or "自然資源"}
  if targetRelation=="ally" then table.insert(lines,"盟友 · 友方不可攻擊")
  elseif targetRelation=="unresolved" then table.insert(lines,"隊伍資料載入中") end
  if model:GetAttribute("Order") then table.insert(lines,model:GetAttribute("Order")) end
  if (model:GetAttribute("Carrying") or 0) > 0 then
   local resource = ({food = "食物",wood = "木材",gold = "黃金",stone = "石材"})[model:GetAttribute("CarryType")] or "資源"
   table.insert(lines,"攜帶 "..resource.." "..math.floor(model:GetAttribute("Carrying")))
  end
  if model:GetAttribute("Amount") then table.insert(lines,"剩餘 "..math.floor(model:GetAttribute("Amount"))) end
  if model:GetAttribute("Complete") == false then
   local builders = model:GetAttribute("BuilderCount") or 0
   table.insert(lines,(model:GetAttribute("ConstructionStatus") or "等待村民").." · "..math.floor((model:GetAttribute("ConstructionProgress") or 0)*100).."%")
   table.insert(lines,builders > 0 and ("施工村民："..builders.." 位") or (targetRelation=="own" and "右鍵工地，指派村民施工" or "等待對方指派村民"))
  end
  if model:GetAttribute("Training") then table.insert(lines,"訓練 "..math.ceil(model:GetAttribute("TrainingRemaining") or 0).."秒 · 佇列 "..(model:GetAttribute("QueueCount") or 1)) end
  if model:GetAttribute("Research") then table.insert(lines,model:GetAttribute("Research").." · "..math.ceil(model:GetAttribute("ResearchRemaining") or 0).."秒") end
  if model:GetAttribute("RallyType") then table.insert(lines,"集合點："..tostring(model:GetAttribute("RallyTargetName") or "地面")) end
  if garrisonText(model) then table.insert(lines,garrisonText(model)) end
  if model:GetAttribute("Relic") then
   table.insert(lines,Config.Relics.description)
   table.insert(lines,"全圖聖物 "..(workspace:GetAttribute("RelicTotal") or 0).." 件 · 每件每秒 +"..Config.Relics.goldPerSecond.." 黃金")
  end
  if kind == "Monastery" and model:GetAttribute("OwnerId") == player.UserId then
   local relics = model:GetAttribute("Relics") or 0
   table.insert(lines,relics > 0 and ("存放聖物 "..relics.." 件 · 每秒 +"..(relics*Config.Relics.goldPerSecond).." 黃金") or "尚無聖物：派僧侶拾取地圖上的聖物")
   if (player:GetAttribute("RelicGold") or 0) > 0 then table.insert(lines,"聖物累計產出 "..math.floor(player:GetAttribute("RelicGold")).." 黃金") end
  end
  if model:GetAttribute("CarryingRelic") then table.insert(lines,"攜帶聖物 · 右鍵自己的修道院存放") end
  if kind == "tradeCart" then
   local cargo = model:GetAttribute("TradeGold") or 0
   table.insert(lines,cargo > 0 and ("載運黃金 "..cargo.." · 回到己方市集後入帳") or "空車 · 右鍵另一座己方或盟友市集開始貿易")
  end
  if kind == "Market" and model:GetAttribute("OwnerId") == player.UserId and (player:GetAttribute("TradeIncome") or 0) > 0 then
   table.insert(lines,"貿易累計收入 "..math.floor(player:GetAttribute("TradeIncome")).." 黃金")
  end
  if kind == "Wonder" and model:GetAttribute("OwnerId") == player.UserId and (player:GetAttribute("WonderRemaining") or 0) > 0 then table.insert(lines,"奇觀勝利倒數 "..math.ceil(player:GetAttribute("WonderRemaining")).."秒") end
  local progress = model:GetAttribute("Complete") == false and model:GetAttribute("ConstructionProgress") or model:GetAttribute("ResearchProgress") or model:GetAttribute("TrainingProgress")
  if progress then self.productionBack.Visible = true; self.productionFill.Size = UDim2.fromScale(math.clamp(progress,0,1),1) end
  self.details.Text = table.concat(lines,"\n")
  if model:GetAttribute("BuildingType") then
   self.selectionState.Visible=true
   local complete=model:GetAttribute("Complete")~=false
   self.selectionState.Text=complete and "✓ 建築已完工" or ((model:GetAttribute("BuilderCount") or 0)>0 and "施工中" or "工地停工 · 等待村民")
   self.selectionState.TextColor3=complete and C.green or C.gold
   if not complete then
    self.productionText.Visible=true
    self.productionText.Text="施工進度 "..math.floor((model:GetAttribute("ConstructionProgress") or 0)*100).."%  ·  "..(model:GetAttribute("BuilderCount") or 0).." 位村民"
   end
  elseif #selected==1 and model:GetAttribute("UnitType") then
   self.statLine.Text=string.format("攻擊 %g   護甲 %g   移速 %g",model:GetAttribute("Attack") or 0,model:GetAttribute("Armor") or 0,model:GetAttribute("Speed") or 0)
  end
  self:UpdateProduction(model)
  if self.touchLayout and not self.queueHolder.Visible then
   self.mobileState.Visible=true
   self.mobileState.Text=model:GetAttribute("Complete")==false and (self.selectionState.Text.." · "..math.floor((model:GetAttribute("ConstructionProgress") or 0)*100).."%")
    or model:GetAttribute("BuildingType") and "✓ 建築已完工"
    or model:GetAttribute("UnitType") and (model:GetAttribute("Order") or "待命")
    or self.details.Text:gsub("\n"," · ")
  end
  local hp,maximum = model:GetAttribute("HP"),model:GetAttribute("MaxHP")
  if #selected>1 then
   local villagers,military,totalHP,totalMax=0,0,0,0
   for _,unit in ipairs(selected) do
    if unit:GetAttribute("UnitType")=="villager" then villagers+=1 elseif unit:GetAttribute("UnitType") then military+=1 end
    totalHP+=unit:GetAttribute("HP") or 0; totalMax+=unit:GetAttribute("MaxHP") or 0
   end
   self.details.Text=string.format("村民 %d · 軍隊 %d\n右鍵下令 · Shift 加選",villagers,military)
   if self.touchLayout then self.mobileState.Visible=true; self.mobileState.Text=string.format("村民 %d · 軍隊 %d\n生命值 %d / %d",villagers,military,math.ceil(totalHP),totalMax) end
   hp,maximum=totalHP,totalMax
  end
  if hp and maximum then self.healthBack.Visible = true; self.healthFill.Size = UDim2.fromScale(math.clamp(hp/math.max(1,maximum),0,1),1); self.healthFill.BackgroundColor3=hp/maximum<0.25 and C.red or C.green; self.healthText.Text = string.format("生命值  %d / %d",math.ceil(hp),maximum) end
  self.context.Text = model:GetAttribute("BuildingType") and "生 產 與 科 技" or "建 造 與 指 令"
  self.buildHelp.Text = kind == "villager" and "右鍵採集、施工或移動 · B 開啟建築" or model:GetAttribute("UnitType") and model:GetAttribute("OwnerId")==player.UserId and "右鍵移動或攻擊 · G 駐紮" or "T 訓練 · R 科技 · U 升級時代 · G 駐軍離開"
 else
  self.context.Text = "建 造 與 指 令"; self.buildHelp.Text = "選取村民，再右鍵點擊資源開始採集"
 end
 self:UpdateCommands(selected,buildingKind)
 if player:GetAttribute("RTSRallyPlacement") then self.context.Text="設 定 集 合 點"; self.buildHelp.Text="點選地面或資源 · 右鍵 / Esc 取消" end
 if player:GetAttribute("RTSGarrisonPlacement") then self.context.Text="選 擇 駐 紮 建 築"; self.buildHelp.Text="點自己的主城、塔或城堡" end
 if targetRelation=="ally" then
  self.context.Text="友 方 勢 力"; self.buildHelp.Text="友方不可攻擊 · 各自管理自己的資源與單位"
 elseif targetRelation=="unresolved" then
  self.context.Text="隊 伍 載 入 中"; self.buildHelp.Text="隊伍資料載入中，請稍後再下令"
 end
 self:LayoutSelection(selected,buildingKind,targetRelation)
 self:LayoutUnitSelection()
 self.unitSelection:Update(selected,buildingKind,self.touchLayout,targetRelation)
 if self.touchLayout and self.unitPanel.Visible then
  -- This roster replaces the tutorial card where short touch screens share space.
  self.guidance.Visible=false; self.guidanceHint.Visible=false
 end
end
function GUI:LayoutSelection(selected,buildingKind,relation)
 local model=selected[1]
 local builders=selectedBuilders(selected)
 local compact=not self.touchLayout and model~=nil and not builders and not buildingKind
 self.details.Visible=compact; self.statLine.Visible=compact and self.statLine.Text~=""
 self.healthText.Visible=compact; self.healthBack.Visible=compact and self.healthText.Text~=""
 self.selectionState.Visible=compact and model:GetAttribute("BuildingType")~=nil
 self.productionText.Visible=compact and model:GetAttribute("Complete")==false
 self.productionBack.Visible=compact and self.productionBack.Visible
 if self.emptyCommandHint then self.emptyCommandHint.Visible=true; self.emptyCommandHint.Size=UDim2.new(1,-42,1,0) end
 if self.touchLayout then self.deleteButton.Visible=false; return end
 if model and not buildingKind and relation~="ally" and relation~="unresolved" and not player:GetAttribute("RTSRallyPlacement") and not player:GetAttribute("RTSGarrisonPlacement") then
  self.context.Text=#selected>1 and (#selected.." 個單位") or (model:GetAttribute("DisplayName") or model.Name)
 end
 if builders and not self.hasFormationCommands and not buildingKind and self.healthText.Text~="" then
  self.buildHelp.Text=self.healthText.Text.." · 右鍵採集、施工或移動"
 end
 if not compact and not self.hasFormationCommands then return end
 if self.hasFormationCommands then
  self.details.Position=UDim2.fromOffset(320,112); self.details.Size=UDim2.fromOffset(272,42)
  self.statLine.Position=UDim2.fromOffset(320,138)
  self.healthText.Position=UDim2.fromOffset(320,159); self.healthBack.Position=UDim2.fromOffset(320,179)
  self.healthBack.Size=UDim2.fromOffset(272,3)
  return
 end
 if model:GetAttribute("BuildingType") then
  self.details.Position=UDim2.fromOffset(320,112); self.details.Size=UDim2.fromOffset(272,42)
  self.healthText.Position=UDim2.fromOffset(320,159); self.healthBack.Position=UDim2.fromOffset(320,179)
  self.healthBack.Size=UDim2.fromOffset(272,3)
  local summary={(model:GetAttribute("OwnerName") or "建築")..(garrisonText(model) and (" · "..garrisonText(model)) or "")}
  if relation=="ally" then table.insert(summary,"盟友 · 友方不可攻擊")
  elseif relation=="unresolved" then table.insert(summary,"隊伍資料載入中") end
  if model:GetAttribute("Research") then table.insert(summary,model:GetAttribute("Research").." · "..math.ceil(model:GetAttribute("ResearchRemaining") or 0).."秒")
  elseif model:GetAttribute("Training") then table.insert(summary,"訓練 "..model:GetAttribute("Training").." · "..math.ceil(model:GetAttribute("TrainingRemaining") or 0).."秒")
  elseif model:GetAttribute("RallyType") then table.insert(summary,"集合點："..tostring(model:GetAttribute("RallyTargetName") or "地面")) end
  self.details.Text=table.concat(summary,"\n")
  if self.emptyCommandHint then self.emptyCommandHint.Size=UDim2.new(1,-42,0,70); self.emptyCommandHint.Visible=true end
 else
  self.details.Position=UDim2.fromOffset(120,42); self.details.Size=UDim2.fromOffset(470,83)
  self.statLine.Position=UDim2.fromOffset(120,128)
  self.healthText.Position=UDim2.fromOffset(120,152); self.healthBack.Position=UDim2.fromOffset(120,176)
  self.healthBack.Size=UDim2.fromOffset(470,3)
  if self.emptyCommandHint then self.emptyCommandHint.Visible=false end
 end
end
function GUI:UpdateMap()
 if not self.mapPanel.Visible or not self.hudLayer.Visible then return end
 local alive,colors = {},{}
 for _,faction in ipairs(factions()) do colors[faction.id] = faction.actor:GetAttribute("TeamColor") end
 for _,name in ipairs({"Resources","Buildings","Units"}) do
  local folder = workspace:FindFirstChild(name)
  if folder then for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart then
    alive[model] = true; local dot = self.dots[model]
    if not dot then
     dot = make("Frame",self.map,{Name = "MinimapDot",BorderSizePixel = 0,AnchorPoint = Vector2.new(0.5,0.5),Size = UDim2.fromOffset(name == "Buildings" and 7 or 3,name == "Buildings" and 7 or 3),Active = false,ZIndex = 2})
     round(dot,name == "Buildings" and 1 or 2); self.dots[model] = dot
    end
    local frame=name=="Units" and ClientUnitView.GetFrame(model) or model:GetPivot()
    local pos = frame.Position; dot.Position = UDim2.fromScale(pos.X/mapSize()+0.5,pos.Z/mapSize()+0.5)
    local unitType=model:GetAttribute("UnitType")
    local economic=name=="Resources" or unitType=="villager" or name=="Buildings"
    dot.Visible=self.mapMode=="all" or self.mapMode=="economy" and economic or self.mapMode=="military" and name~="Resources" and unitType~="villager"
    dot.BackgroundColor3 = colors[model:GetAttribute("OwnerId")] or ({wood=Color3.fromRGB(46,84,37),food=Color3.fromRGB(170,77,58),gold=Color3.fromRGB(224,184,82),stone=Color3.fromRGB(154,165,170)})[model:GetAttribute("ResourceType")] or C.muted
    -- 聖物在小地圖上以較大的白點標示，方便爭奪。
    if model:GetAttribute("Relic") then dot.BackgroundColor3=Color3.fromRGB(255,250,236); dot.Size=UDim2.fromOffset(6,6); dot.Visible=self.mapMode~="military" end
    -- 戰爭迷霧：未探索的資源／建築與視野外的敵方單位不顯示。
    if dot.Visible and not FogView.CanSee(model) then dot.Visible=false end
   end
  end end
 end
 for model,dot in pairs(self.dots) do if not alive[model] then dot:Destroy(); self.dots[model] = nil end end
 self:UpdateMapFog()
 local camera = workspace.CurrentCamera
 if camera and camera.CFrame.LookVector.Y < 0 then
  local hit = camera.CFrame.Position+camera.CFrame.LookVector*(-camera.CFrame.Position.Y/camera.CFrame.LookVector.Y)
  self.mapFocus.Position = UDim2.fromScale(hit.X/mapSize()+0.5,hit.Z/mapSize()+0.5)
  local minimum,maximum=Vector2.new(math.huge,math.huge),Vector2.new(-math.huge,-math.huge)
  local viewportSize=camera.ViewportSize
  for _,corner in ipairs({Vector2.new(0,0),Vector2.new(viewportSize.X,0),viewportSize,Vector2.new(0,viewportSize.Y)}) do
   local ray=camera:ViewportPointToRay(corner.X,corner.Y)
   if ray.Direction.Y<0 then
    local p=ray.Origin+ray.Direction*(-ray.Origin.Y/ray.Direction.Y)
    minimum=Vector2.new(math.min(minimum.X,p.X),math.min(minimum.Y,p.Z)); maximum=Vector2.new(math.max(maximum.X,p.X),math.max(maximum.Y,p.Z))
   end
  end
  if minimum.X<maximum.X then
   self.mapFocus.Position=UDim2.fromScale((minimum.X+maximum.X)/2/mapSize()+0.5,(minimum.Y+maximum.Y)/2/mapSize()+0.5)
   self.mapFocus.Size=UDim2.fromScale(math.min(1,(maximum.X-minimum.X)/mapSize()),math.min(1,(maximum.Y-minimum.Y)/mapSize()))
  end
 end
end
-- 小地圖上的黑色地圖與暗霧：只重畫迷霧有變化的列（FogView.mapRows）。
function GUI:UpdateMapFog()
 local rows=FogView.mapRows
 if next(rows)==nil then return end
 FogView.mapRows={}
 self.mapFog=self.mapFog or {}
 local grid=FogView.Active() and FogView.grid or nil
 if rows.all or not grid then
  for _,frames in pairs(self.mapFog) do for _,frame in ipairs(frames) do frame:Destroy() end end
  self.mapFog={}
  if not grid then return end
  rows={}
  for row=1,grid.count do rows[row]=true end
 end
 local FogRules=require(RS.Shared.FogRules)
 for row in pairs(rows) do
  if type(row)=="number" then
   for _,frame in ipairs(self.mapFog[row] or {}) do frame:Destroy() end
   local frames={}
   for _,run in ipairs(FogRules.runs(grid,row)) do
    table.insert(frames,make("Frame",self.map,{Name="MinimapFog",BorderSizePixel=0,Active=false,ZIndex=2,BackgroundColor3=Color3.new(0,0,0),
     BackgroundTransparency=run.state==0 and 0 or .5,Position=UDim2.fromScale((run.first-1)/grid.count,(row-1)/grid.count),
     Size=UDim2.fromScale((run.last-run.first+1)/grid.count,1/grid.count)}))
   end
   self.mapFog[row]=frames
  end
 end
end
-- AOE-style alert ping: a red ring pulses on the minimap where you are attacked.
function GUI:PingMap(position)
 if not self.map or typeof(position)~="Vector3" then return end
 local size=mapSize()
 local ping=make("Frame",self.map,{Name="MinimapAlertPing",AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,
  Position=UDim2.fromScale(math.clamp(position.X/size+0.5,0,1),math.clamp(position.Z/size+0.5,0,1)),
  Size=UDim2.fromOffset(10,10),Active=false,ZIndex=4})
 round(ping,99)
 local ring=stroke(ping,C.red,0)
 ring.Thickness=2
 if self.reducedMotion then
  ping.Size=UDim2.fromOffset(16,16)
  task.delay(2.5,function() ping:Destroy() end)
  return
 end
 task.spawn(function()
  for _=1,3 do
   if not ping.Parent then return end
   ping.Size=UDim2.fromOffset(6,6); ring.Transparency=0
   tween(ping,0.75,{Size=UDim2.fromOffset(34,34)})
   tween(ring,0.75,{Transparency=1})
   task.wait(0.8)
  end
  ping:Destroy()
 end)
end
return GUI
