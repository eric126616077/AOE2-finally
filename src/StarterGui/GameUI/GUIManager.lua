local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Config = require(RS.GameData.GameConfig)
local Grid = require(RS.Shared.Grid)
local Art = require(RS.Shared.Art)
local player = Players.LocalPlayer
local GUI = {hitAreas = {}, reducedMotion = false, tab = "build", page = 1}
local C = {panel = Color3.fromRGB(27,32,31), card = Color3.fromRGB(43,48,43), edge = Color3.fromRGB(91,92,71),
 gold = Color3.fromRGB(217,181,111), white = Color3.fromRGB(241,231,207), muted = Color3.fromRGB(162,174,158),
 green = Color3.fromRGB(144,196,136), red = Color3.fromRGB(231,137,112)}
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
local function round(object, radius) make("UICorner", object, {CornerRadius = UDim.new(0, radius or 6)}) end
local function stroke(object, color, transparency)
 return make("UIStroke", object, {Color = color or C.edge, Thickness = 1, Transparency = transparency or 0})
end
local function panel(parent, size, position, name)
 local frame = make("Frame", parent, {Name = name or "Panel", Size = size, Position = position,
  BackgroundColor3 = C.panel, BackgroundTransparency = 0.04, BorderSizePixel = 0, Active = true})
 round(frame); stroke(frame); table.insert(GUI.hitAreas, frame)
 return frame
end
local function button(parent, size, position, callback, name)
 local b = make("TextButton", parent, {Name = name or "Action", Text = "", Size = size, Position = position,
  BackgroundColor3 = C.card, BorderSizePixel = 0, AutoButtonColor = false})
 round(b,5)
 local edge = stroke(b,C.edge,0.4)
 b.MouseEnter:Connect(function()
  if not UIS.MouseEnabled or b:GetAttribute("Unavailable") then return end
  if GUI.reducedMotion then b.BackgroundColor3 = Color3.fromRGB(58,62,51)
  else tween(b,0.125,{BackgroundColor3 = Color3.fromRGB(58,62,51)}) end
 end)
 b.MouseLeave:Connect(function()
  if GUI.reducedMotion then b.BackgroundColor3 = C.card else tween(b,0.125,{BackgroundColor3 = C.card}) end
 end)
 b.Activated:Connect(callback)
 return b,edge
end
local function namedButton(parent, label, size, position, callback, name, color)
 local b,edge = button(parent,size,position,callback,name)
 local title = text(b,label,UDim2.new(1,-14,1,0),UDim2.fromOffset(7,0),14,color or C.white,Enum.Font.SourceSansSemibold)
 title.TextXAlignment = Enum.TextXAlignment.Center
 return b,title,edge
end
local function viewport(parent, kind, size, position)
 local view = make("ViewportFrame",parent,{Size = size,Position = position,BackgroundTransparency = 1,
  Ambient = Color3.fromRGB(175,175,175),LightColor = Color3.fromRGB(255,235,196),LightDirection = Vector3.new(-1,-1,-1),Active = false})
 local world = make("WorldModel",view)
 local model = Art.Create(kind,player:GetAttribute("TeamColor")); model.Parent = world
 local cf,bounds = model:GetBoundingBox()
 local radius = math.max(bounds.X,bounds.Y,bounds.Z,4)
 local camera = make("Camera",view,{FieldOfView = 36,
  CFrame = CFrame.lookAt(cf.Position + Vector3.new(radius*1.15,radius*0.8,radius*1.4),cf.Position)})
 view.CurrentCamera = camera
 return view
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

function GUI:Init(callbacks)
 if self.screen then return self end
 self.callbacks = callbacks
 local pg = player:WaitForChild("PlayerGui")
 local old = pg:FindFirstChild("AOE2_MainGUI"); if old then old:Destroy() end
 self.screen = make("ScreenGui",pg,{Name = "AOE2_MainGUI",ResetOnSpawn = false,IgnoreGuiInset = false,ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
 self.canvas = make("Frame",self.screen,{Name = "HUD",Size = UDim2.fromScale(1,1),BackgroundTransparency = 1})
 self.scale = make("UIScale",self.canvas,{Scale = 1})
 local function resize()
  local camera = workspace.CurrentCamera; if not camera then return end
  local inset,bottomInset = GuiService:GetGuiInset()
  local width,height = camera.ViewportSize.X-bottomInset.X-inset.X,camera.ViewportSize.Y-bottomInset.Y-inset.Y
  self.scale.Scale = math.max(0.2,math.min(1.1,width/1280,height/620))
  self.canvas.Size = UDim2.fromOffset(width/self.scale.Scale,height/self.scale.Scale)
 end
 resize()
 if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
 workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(resize)
 text(self.canvas,"帝國邊境",UDim2.fromOffset(205,34),UDim2.fromOffset(22,13),30,C.white,Enum.Font.SourceSansBold)
 self.ageLabel = text(self.canvas,"黑暗時代 · 00:00",UDim2.fromOffset(225,23),UDim2.fromOffset(24,48),13,C.gold)
 self.resourceValues,self.resourceCards = {},{}
 local resourceNames = {food = "食物",wood = "木材",gold = "黃金",stone = "石材",population = "人口"}
 local resourceColors = {food = Color3.fromRGB(201,146,104),wood = Color3.fromRGB(151,185,124),gold = C.gold,stone = Color3.fromRGB(171,181,190),population = Color3.fromRGB(150,191,179)}
 local bar = make("Frame",self.canvas,{Name = "ResourceBar",Size = UDim2.fromOffset(725,64),Position = UDim2.new(1,-818,0,13),BackgroundTransparency = 1})
 for i,key in ipairs({"food","wood","gold","stone","population"}) do
  local card = panel(bar,UDim2.fromOffset(137,64),UDim2.fromOffset((i-1)*146,0),"Resource_"..key)
  local mark = make("Frame",card,{Size = UDim2.fromOffset(3,29),Position = UDim2.fromOffset(12,18),BackgroundColor3 = resourceColors[key],BorderSizePixel = 0}); round(mark,2)
  text(card,resourceNames[key],UDim2.fromOffset(103,18),UDim2.fromOffset(24,6),12,C.muted)
  self.resourceValues[key] = text(card,"—",UDim2.fromOffset(110,30),UDim2.fromOffset(24,25),24,C.white,Enum.Font.SourceSansSemibold)
  self.resourceCards[key] = card
 end
 local menu = panel(self.canvas,UDim2.fromOffset(66,64),UDim2.new(1,-84,0,13),"MenuDock")
 namedButton(menu,"選單",UDim2.fromOffset(54,26),UDim2.fromOffset(6,5),function() self:ToggleMenu() end,"MenuButton")
 namedButton(menu,"動態",UDim2.fromOffset(54,22),UDim2.fromOffset(6,36),function()
  self.reducedMotion = not self.reducedMotion; player:SetAttribute("ReducedMotion",self.reducedMotion)
  self:Notify(self.reducedMotion and "減少介面動態：開啟" or "減少介面動態：關閉")
 end,"MotionButton",C.muted)
 local objective = panel(self.canvas,UDim2.fromOffset(244,88),UDim2.fromOffset(20,96),"Objective")
 text(objective,"領 地 與 戰 局",UDim2.fromOffset(220,20),UDim2.fromOffset(13,8),12,C.gold)
 self.objective = text(objective,"建立經濟，發展軍隊\n消滅其他勢力取得勝利",UDim2.fromOffset(219,49),UDim2.fromOffset(13,31),14,C.muted)
 self.scoreboard = panel(self.canvas,UDim2.fromOffset(218,151),UDim2.new(1,-238,0,96),"Scoreboard")
 text(self.scoreboard,"對 戰 勢 力",UDim2.fromOffset(186,22),UDim2.fromOffset(12,6),12,C.gold)
 self.scoreRows = {}
 for i = 1,4 do
  self.scoreRows[i] = text(self.scoreboard,"",UDim2.fromOffset(192,26),UDim2.fromOffset(12,31+(i-1)*27),13,C.white)
  self.scoreRows[i].TextWrapped = false; self.scoreRows[i].TextTruncate = Enum.TextTruncate.AtEnd
 end
 self.menuPanel = panel(self.canvas,UDim2.fromOffset(218,166),UDim2.new(1,-238,0,96),"GameMenu"); self.menuPanel.Visible = false
 text(self.menuPanel,"戰 局 選 單",UDim2.fromOffset(191,25),UDim2.fromOffset(12,8),12,C.gold)
 namedButton(self.menuPanel,"繼續遊戲",UDim2.fromOffset(192,31),UDim2.fromOffset(13,39),function() self.menuPanel.Visible = false end,"ContinueButton")
 self.menuEndButton,self.menuEndLabel = namedButton(self.menuPanel,"投降",UDim2.fromOffset(192,31),UDim2.fromOffset(13,79),function()
  self.menuPanel.Visible = false
  if workspace:GetAttribute("MatchPhase") == "Ended" then
   self.dismissedResult = nil; self:Update(self.selected or {},self.buildingKind)
  else callbacks.surrender() end
 end,"SurrenderButton",C.red)
 self.edgeButton,self.edgeLabel = namedButton(self.menuPanel,"邊緣移動：關閉",UDim2.fromOffset(192,31),UDim2.fromOffset(13,119),function()
  local enabled = player:GetAttribute("EdgeScroll") ~= true
  player:SetAttribute("EdgeScroll",enabled); self.edgeLabel.Text = "邊緣移動："..(enabled and "開啟" or "關閉")
 end,"EdgeScrollButton",C.muted)
 self.noticePanel = panel(self.canvas,UDim2.fromOffset(554,42),UDim2.new(0.5,-277,0,95),"Notice"); self.noticePanel.Visible = false
 self.noticePanel.ZIndex = 40
 self.notice = text(self.noticePanel,"",UDim2.new(1,-24,1,0),UDim2.fromOffset(12,0),16,C.gold); self.notice.TextXAlignment = Enum.TextXAlignment.Center
 -- Separate bounds leave terrain directly above and beside the bottom panels clickable.
 self.info = panel(self.canvas,UDim2.fromOffset(264,182),UDim2.new(0,20,1,-204),"SelectionInfo")
 text(self.info,"選 取 情 報",UDim2.fromOffset(236,20),UDim2.fromOffset(14,9),12,C.gold)
 self.portraitHolder = make("Frame",self.info,{Size = UDim2.fromOffset(89,108),Position = UDim2.fromOffset(5,33),BackgroundTransparency = 1})
 self.title = text(self.info,"建立你的帝國",UDim2.fromOffset(152,27),UDim2.fromOffset(98,33),19,C.white,Enum.Font.SourceSansSemibold)
 self.details = text(self.info,"",UDim2.fromOffset(152,80),UDim2.fromOffset(98,63),13,C.muted); self.details.TextYAlignment = Enum.TextYAlignment.Top
 self.healthBack = make("Frame",self.info,{Size = UDim2.fromOffset(231,4),Position = UDim2.fromOffset(16,150),BackgroundColor3 = C.card,BorderSizePixel = 0})
 self.healthFill = make("Frame",self.healthBack,{Size = UDim2.fromScale(1,1),BackgroundColor3 = C.green,BorderSizePixel = 0})
 self.productionBack = make("Frame",self.info,{Name = "ProductionProgress",Size = UDim2.fromOffset(231,4),Position = UDim2.fromOffset(16,140),BackgroundColor3 = C.card,BorderSizePixel = 0,Visible = false})
 self.productionFill = make("Frame",self.productionBack,{Size = UDim2.fromScale(0,1),BackgroundColor3 = C.gold,BorderSizePixel = 0})
 self.healthText = text(self.info,"",UDim2.fromOffset(231,18),UDim2.fromOffset(16,158),12,C.muted)
 self.bottom = panel(self.canvas,UDim2.fromOffset(624,182),UDim2.new(0.5,-294,1,-204),"CommandDock")
 self.context = text(self.bottom,"建 造 與 指 令",UDim2.fromOffset(198,23),UDim2.fromOffset(14,7),12,C.gold)
 self.tabButtons = {}
 for i,entry in ipairs({{"build","建築 [B]"},{"train","生產 [T]"},{"research","科技 [R]"}}) do
  local b,label,edge = namedButton(self.bottom,entry[2],UDim2.fromOffset(90,23),UDim2.fromOffset(219+(i-1)*96,7),function() self:SetTab(entry[1]) end,"Tab_"..entry[1],C.muted)
  self.tabButtons[entry[1]] = {button = b,label = label,edge = edge}
 end
 self.commandHolder = make("Frame",self.bottom,{Name = "Commands",Size = UDim2.fromOffset(598,106),Position = UDim2.fromOffset(13,36),BackgroundTransparency = 1})
 self.commandEntries,self.buildButtons = {},{}
 self.buildHelp = text(self.bottom,"選取村民，再右鍵點擊資源開始採集",UDim2.fromOffset(386,25),UDim2.fromOffset(14,147),12,C.muted)
 self.previousPage = namedButton(self.bottom,"‹",UDim2.fromOffset(27,26),UDim2.fromOffset(405,147),function() self:ChangePage(-1) end,"PreviousPage",C.gold)
 self.pageLabel = text(self.bottom,"1 / 1",UDim2.fromOffset(48,25),UDim2.fromOffset(438,147),12,C.muted); self.pageLabel.TextXAlignment = Enum.TextXAlignment.Center
 self.nextPage = namedButton(self.bottom,"›",UDim2.fromOffset(27,26),UDim2.fromOffset(490,147),function() self:ChangePage(1) end,"NextPage",C.gold)
 namedButton(self.bottom,"停止 [X]",UDim2.fromOffset(82,26),UDim2.fromOffset(528,147),callbacks.stop,"StopButton",C.muted)
 self.tooltip = make("Frame",self.bottom,{Name = "CommandTooltip",Size = UDim2.fromOffset(476,100),Position = UDim2.fromOffset(72,-108),Visible = false,BackgroundColor3 = C.panel,BackgroundTransparency = 0.04,BorderSizePixel = 0,ZIndex = 6})
 round(self.tooltip); stroke(self.tooltip,C.gold,0.3)
 self.tooltipText = text(self.tooltip,"",UDim2.new(1,-26,1,-14),UDim2.fromOffset(13,7),14,C.white)
 self.tooltipText.TextYAlignment = Enum.TextYAlignment.Top
 local mapFrame = panel(self.canvas,UDim2.fromOffset(210,232),UDim2.new(1,-230,1,-254),"MinimapPanel")
 text(mapFrame,"戰 術 地 圖",UDim2.fromOffset(153,23),UDim2.fromOffset(12,7),12,C.gold)
 text(mapFrame,"N ↑",UDim2.fromOffset(35,23),UDim2.fromOffset(172,7),12,C.muted)
 self.map = make("TextButton",mapFrame,{Name = "Minimap",Text = "",AutoButtonColor = false,Size = UDim2.fromOffset(186,186),Position = UDim2.fromOffset(12,33),BackgroundColor3 = Color3.fromRGB(75,96,60),BorderSizePixel = 0,ClipsDescendants = true})
 round(self.map,3)
 for i = 1,3 do
  make("Frame",self.map,{Size = UDim2.new(1,0,0,1),Position = UDim2.fromScale(0,i/4),BackgroundColor3 = C.muted,BackgroundTransparency = 0.86,BorderSizePixel = 0})
  make("Frame",self.map,{Size = UDim2.new(0,1,1,0),Position = UDim2.fromScale(i/4,0),BackgroundColor3 = C.muted,BackgroundTransparency = 0.86,BorderSizePixel = 0})
 end
 self.mapFocus = make("Frame",self.map,{Size = UDim2.fromOffset(32,24),AnchorPoint = Vector2.new(0.5,0.5),BackgroundTransparency = 1,ZIndex = 3}); stroke(self.mapFocus,C.white,0.15)
 self.map.Activated:Connect(function()
  local pos = UIS:GetMouseLocation()-GuiService:GetGuiInset(); local p,s = self.map.AbsolutePosition,self.map.AbsoluteSize
  player:SetAttribute("CameraFocus",Vector3.new((math.clamp((pos.X-p.X)/s.X,0,1)-0.5)*mapSize(),0,(math.clamp((pos.Y-p.Y)/s.Y,0,1)-0.5)*mapSize()))
 end)
 text(self.canvas,"WASD 移動 · 滾輪縮放 · Home 回基地 · 拖曳框選 · 右鍵下令 · Ctrl + 1–9 編隊 · . 閒置村民",UDim2.fromOffset(960,18),UDim2.new(0.5,-480,1,-19),11,C.white).TextXAlignment = Enum.TextXAlignment.Center
 self.dots = {}
 self.selectionBox = make("Frame",self.screen,{Name = "SelectionBox",Visible = false,BackgroundColor3 = C.green,BackgroundTransparency = 0.86,BorderSizePixel = 1,BorderColor3 = C.green,ZIndex = 8})
 self:CreateLobby(); self:CreateResult(); self:SetPortrait("TownCenter"); self:Update({},nil)
 return self
end

function GUI:CreateLobby()
 self.settings = {size = "Medium",aiCount = 1,difficulty = "Normal",population = 100,startingResources = "Standard",victory = "Conquest"}
 self.lobby = panel(self.canvas,UDim2.fromScale(1,1),UDim2.fromScale(0,0),"LobbyLayer")
 self.lobby.BackgroundColor3 = Color3.fromRGB(13,18,18); self.lobby.BackgroundTransparency = 0.2; self.lobby.ZIndex = 20
 local body = panel(self.lobby,UDim2.fromOffset(860,494),UDim2.new(0.5,-430,0.5,-247),"MatchLobby")
 make("Frame",body,{Size = UDim2.new(1,-32,0,2),Position = UDim2.fromOffset(16,83),BackgroundColor3 = C.gold,BorderSizePixel = 0,BackgroundTransparency = 0.55})
 text(body,"帝國邊境",UDim2.fromOffset(390,45),UDim2.fromOffset(28,15),36,C.white,Enum.Font.SourceSansBold)
 text(body,"自訂戰局 / 中世紀即時戰略原型",UDim2.fromOffset(470,24),UDim2.fromOffset(30,56),14,C.gold)
 text(body,"戰 局 設 定",UDim2.fromOffset(300,22),UDim2.fromOffset(29,96),13,C.gold)
 local fields = {
  {key = "size",label = "地圖尺寸",values = {"Small","Medium","Large"},names = {Small = "小型 · 768",Medium = "中型 · 1024",Large = "大型 · 1536"}},
  {key = "aiCount",label = "電腦對手",values = {0,1,2,3,"Auto"},names = {[0] = "無 · 自由建設",[1] = "1 位 AI",[2] = "2 位 AI",[3] = "3 位 AI",Auto = "自動補滿 4 方"}},
  {key = "difficulty",label = "AI 難度",values = {"Easy","Normal","Hard"},names = {Easy = "簡單",Normal = "普通",Hard = "困難"}},
  {key = "population",label = "人口上限",values = {60,100,150,200}},
  {key = "startingResources",label = "初始資源",values = {"Standard","Rich"},names = {Standard = "標準經濟",Rich = "豐富資源"}},
  {key = "victory",label = "勝利規則",values = {"Conquest","Regicide","Wonder"},names = {Conquest = "征服 · 消滅所有對手",Regicide = "主城決戰 · 保護主城",Wonder = "奇觀 · 守住世界奇觀"}},
 }
 self.settingLabels = {}
 for i,field in ipairs(fields) do
  local y = 125+(i-1)*44
  text(body,field.label,UDim2.fromOffset(100,32),UDim2.fromOffset(30,y),15,C.muted)
  local b,label = namedButton(body,"",UDim2.fromOffset(258,33),UDim2.fromOffset(135,y),function()
   if workspace:GetAttribute("HostUserId") ~= player.UserId or workspace:GetAttribute("MatchPhase") ~= "Lobby" then self:Notify("戰局設定由房主決定。") return end
   local index = table.find(field.values,self.settings[field.key]) or 1
   self.settings[field.key] = field.values[index % #field.values+1]; self:UpdateLobby()
  end,"Setting_"..field.key)
  self.settingLabels[field.key] = {label = label,field = field,button = b}
 end
 make("Frame",body,{Size = UDim2.fromOffset(1,279),Position = UDim2.fromOffset(424,119),BackgroundColor3 = C.edge,BackgroundTransparency = 0.4,BorderSizePixel = 0})
 text(body,"參 戰 勢 力",UDim2.fromOffset(300,22),UDim2.fromOffset(451,96),13,C.gold)
 self.lobbyRows = {}
 for i = 1,4 do
  local row = panel(body,UDim2.fromOffset(374,42),UDim2.fromOffset(450,125+(i-1)*47),"LobbyFaction_"..i)
  self.lobbyRows[i] = text(row,"",UDim2.fromOffset(349,38),UDim2.fromOffset(12,2),15,C.white)
 end
 self.rules = text(body,"",UDim2.fromOffset(371,74),UDim2.fromOffset(452,320),14,C.muted); self.rules.TextYAlignment = Enum.TextYAlignment.Top
 self.hostLabel = text(body,"",UDim2.fromOffset(485,26),UDim2.fromOffset(30,402),14,C.muted)
 self.startButton,self.startLabel = namedButton(body,"開始戰局",UDim2.fromOffset(226,45),UDim2.fromOffset(598,402),function()
  if workspace:GetAttribute("HostUserId") ~= player.UserId or workspace:GetAttribute("MatchPhase") ~= "Lobby" then return end
  local request = table.clone(self.settings); local available = math.max(0,4-#Players:GetPlayers())
  request.aiCount = request.aiCount == "Auto" and available or math.min(request.aiCount,available)
  self.callbacks.start(request)
 end,"StartMatchButton",C.gold)
 text(body,"原創美術與規則實作 · 仍在開發與測試 · 尚非完整商業遊戲",UDim2.fromOffset(795,23),UDim2.fromOffset(30,460),12,C.muted)
end
function GUI:CreateResult()
 self.result = panel(self.canvas,UDim2.fromScale(1,1),UDim2.fromScale(0,0),"ResultOverlay")
 self.result.ZIndex = 30; self.result.BackgroundColor3 = Color3.fromRGB(13,18,18); self.result.BackgroundTransparency = 0.22; self.result.Visible = false
 local body = panel(self.result,UDim2.fromOffset(586,322),UDim2.new(0.5,-293,0.5,-161),"MatchResult")
 self.resultHeading = text(body,"戰局結束",UDim2.fromOffset(526,63),UDim2.fromOffset(30,30),41,C.gold,Enum.Font.SourceSansBold); self.resultHeading.TextXAlignment = Enum.TextXAlignment.Center
 self.resultDescription = text(body,"",UDim2.fromOffset(506,77),UDim2.fromOffset(40,108),18,C.white); self.resultDescription.TextXAlignment = Enum.TextXAlignment.Center
 self.resultContinue = namedButton(body,"繼續觀戰",UDim2.fromOffset(228,42),UDim2.fromOffset(42,212),function()
  self.dismissedResult = self.resultKey; self.result.Visible = false
  player:SetAttribute("RTSModalOpen",self.lobby.Visible)
 end,"WatchButton",C.muted)
 self.restartButton,self.restartLabel = namedButton(body,"返回戰局設定",UDim2.fromOffset(228,42),UDim2.fromOffset(310,212),function()
  if workspace:GetAttribute("HostUserId") == player.UserId then self.callbacks.restart() end
 end,"RestartMatchButton",C.gold)
 text(body,"Ctrl + 1–9 儲存編隊 · 數字鍵選取編隊 · H 選取基地",UDim2.fromOffset(506,23),UDim2.fromOffset(40,276),12,C.muted).TextXAlignment = Enum.TextXAlignment.Center
end
function GUI:UpdateLobby()
 local humanCount = #Players:GetPlayers()
 local aiCount = self.settings.aiCount == "Auto" and math.max(0,4-humanCount) or math.min(self.settings.aiCount,math.max(0,4-humanCount))
 local starting = workspace:GetAttribute("MatchPhase") == "Starting"
 local isHost = workspace:GetAttribute("HostUserId") == player.UserId and not starting
 for key,entry in pairs(self.settingLabels) do
  local value = self.settings[key]; entry.label.Text = (entry.field.names and entry.field.names[value] or tostring(value)).."  ›"
  entry.label.TextColor3 = isHost and C.white or C.muted
 end
 local humans = Players:GetPlayers(); table.sort(humans,function(a,b) return a.UserId < b.UserId end)
 for i,label in ipairs(self.lobbyRows) do
  local human = humans[i]
  if human then label.Text = "●  "..human.DisplayName..(human.UserId == workspace:GetAttribute("HostUserId") and "  · 房主" or "  · 玩家"); label.TextColor3 = human:GetAttribute("TeamColor") or C.white
  elseif i <= humanCount+aiCount then label.Text = "◆  電腦勢力 "..(i-humanCount).."  · AI"; label.TextColor3 = C.gold
  else label.Text = "○  空位"; label.TextColor3 = C.muted end
 end
 self.hostLabel.Text = starting and "正在生成地圖、資源及各方基地…" or (isHost and "你是房主 · 點擊選項可切換設定" or "等待房主開始 · 開局後同步戰局設定")
 self.startLabel.Text = starting and "正在準備戰局…" or (isHost and "開始戰局  →" or "等待房主開始"); self.startButton:SetAttribute("Unavailable",not isHost)
 self.rules.Text = self.settings.victory == "Regicide" and "保護你的起始市鎮中心。\n起始主城失守即出局，最後存活的勢力獲勝。"
  or self.settings.victory == "Wonder" and ("完工後守住世界奇觀 "..(Config.Settings.wonderVictoryTime or 180).." 秒即可勝利。\n消滅其餘勢力也能獲勝。")
  or "消滅敵方全部單位與建築。\n最後存活的勢力獲勝；沒有對手可自由建設。"
end
function GUI:SetPortrait(kind)
 if self.portraitKind == kind then return end
 self.portraitKind = kind; self.portraitHolder:ClearAllChildren()
 viewport(self.portraitHolder,kind,UDim2.fromScale(1,1),UDim2.fromScale(0,0))
end
function GUI:BlocksPointer(screenPoint)
 local point = (screenPoint or UIS:GetMouseLocation())-GuiService:GetGuiInset()
 for _,area in ipairs(self.hitAreas) do
  if area.Parent and visibleInTree(area) then
   local pos,size = area.AbsolutePosition,area.AbsoluteSize
   if point.X >= pos.X and point.Y >= pos.Y and point.X < pos.X+size.X and point.Y < pos.Y+size.Y then return true end
  end
 end
 return false
end
function GUI:IsModalOpen() return self.lobby.Visible or self.result.Visible end
function GUI:ToggleMenu() if not self:IsModalOpen() then self.menuPanel.Visible = not self.menuPanel.Visible end end
function GUI:Notify(message)
 if type(message) ~= "string" then return end
 self.notice.Text = message; self.noticePanel.Visible = true; self.noticePanel.BackgroundTransparency = self.reducedMotion and 0.04 or 0.28
 if not self.reducedMotion then tween(self.noticePanel,0.2,{BackgroundTransparency = 0.04}) end
 self.messageTime = os.clock()
end
function GUI:SetTab(tab)
 self.tab,self.page,self.commandKey = tab,1,nil
 if self.selected then self:UpdateCommands(self.selected,self.buildingKind) end
end
function GUI:ChangePage(delta)
 self.page = math.clamp(self.page+delta,1,self.pageCount or 1); self.commandKey = nil
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
 local age = player:GetAttribute("Age") or 1
 local key = table.concat({self.tab,self.page,kind or "",owned and "owned" or "foreign",age},":")
 if key ~= self.commandKey then
  self.commandKey = key; self.commandHolder:ClearAllChildren(); self.commandEntries,self.buildButtons = {},{}; self.tooltip.Visible = false
  local actions = {}
  if self.tab == "build" then
   for _,buildKind in ipairs(Config.BuildOrder) do
    local data = Config.Buildings[buildKind]
    table.insert(actions,{key = buildKind,name = data.name,description = data.description,cost = data.cost,minAge = data.minAge or 1,art = buildKind,callback = function() self.callbacks.build(buildKind) end})
   end
  elseif self.tab == "train" and owned and Config.Buildings[kind] then
   for _,unitKind in ipairs(Config.Buildings[kind].trains or {}) do
    local data = Config.Units[unitKind]
    table.insert(actions,{key = unitKind,name = data.name,description = data.description,cost = data.cost,minAge = data.minAge or 1,art = unitKind,callback = function() self.callbacks.train(unitKind) end})
   end
   if kind == "Market" then
    local trade = Config.MarketTrade or {batch = 100,buyGold = 130,sellGold = 70}
    for _,resourceKey in ipairs({"food","wood","stone"}) do
     local resourceName = ({food = "食物",wood = "木材",stone = "石材"})[resourceKey]
     table.insert(actions,{key = "Buy_"..resourceKey,name = "購買"..resourceName,description = "花費 "..trade.buyGold.." 黃金，獲得 "..trade.batch.." "..resourceName.."。",
      cost = {gold = trade.buyGold},costLabel = "金"..trade.buyGold.." → "..trade.batch,minAge = 2,callback = function() self.callbacks.trade(resourceKey,"Buy") end})
     table.insert(actions,{key = "Sell_"..resourceKey,name = "出售"..resourceName,description = "出售 "..trade.batch.." "..resourceName.."，獲得 "..trade.sellGold.." 黃金。",
      cost = {[resourceKey] = trade.batch},costLabel = trade.batch.." → 金"..trade.sellGold,minAge = 2,callback = function() self.callbacks.trade(resourceKey,"Sell") end})
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
    table.insert(actions,{key = techKey,name = data.name,description = data.description,cost = data.cost,minAge = data.minAge or 1,tech = true,requires = data.requires,callback = function() self.callbacks.research(techKey) end})
   end
  end
  self.pageCount = math.max(1,math.ceil(#actions/6)); self.page = math.min(self.page,self.pageCount)
  for i = 1,6 do
   local action = actions[(self.page-1)*6+i]
   if action then
    local b,edge = button(self.commandHolder,UDim2.fromOffset(92,103),UDim2.fromOffset((i-1)*101,0),function()
     if (player:GetAttribute("Age") or 1) < action.minAge then self:Notify("需要"..ageName(action.minAge).."才能使用。") return end
     if action.tech and researched(action.key) then self:Notify("這項科技已完成研究。") return end
     if action.requires and not researched(action.requires) then self:Notify("需要先研究"..Config.Technologies[action.requires].name.."。") return end
     action.callback()
    end,"Command_"..action.key)
    b.MouseEnter:Connect(function()
     if not UIS.MouseEnabled or self:IsModalOpen() then return end
     local requirement = action.requires and (" · 前置："..Config.Technologies[action.requires].name) or ""
     self.tooltipText.Text = action.name.."  ·  "..ageName(action.minAge)..requirement.."\n"..(action.description or "").."\n"..Grid.costText(action.cost)
     self.tooltip.Visible = true
    end)
    b.MouseLeave:Connect(function() self.tooltip.Visible = false end)
    if action.art then viewport(b,action.art,UDim2.fromOffset(76,52),UDim2.fromOffset(8,-1))
    else text(b,"✦",UDim2.fromOffset(84,46),UDim2.fromOffset(4,0),35,C.gold).TextXAlignment = Enum.TextXAlignment.Center end
    local title = text(b,action.name,UDim2.fromOffset(84,31),UDim2.fromOffset(4,47),14,C.white,Enum.Font.SourceSansSemibold); title.TextXAlignment = Enum.TextXAlignment.Center
    local cost = text(b,compactCost(action.cost),UDim2.fromOffset(86,25),UDim2.fromOffset(3,77),11,C.muted); cost.TextXAlignment = Enum.TextXAlignment.Center
    local entry = {button = b,edge = edge,cost = cost,title = title,action = action}; table.insert(self.commandEntries,entry)
    if self.tab == "build" then self.buildButtons[action.key] = entry end
   end
  end
  if #actions == 0 then
   local help = self.tab == "train" and "選取自己的市鎮中心、兵營、射箭場或馬廄，訓練單位。" or "選取市鎮中心升級時代；選取經濟建築或鐵匠鋪研究科技。"
   text(self.commandHolder,help,UDim2.new(1,-42,1,0),UDim2.fromOffset(21,0),16,C.muted).TextXAlignment = Enum.TextXAlignment.Center
  end
 end
 for tab,entry in pairs(self.tabButtons) do entry.edge.Color = self.tab == tab and C.gold or C.edge; entry.label.TextColor3 = self.tab == tab and C.gold or C.muted end
 for _,entry in ipairs(self.commandEntries) do
  local action = entry.action; local locked = age < action.minAge; local done = action.tech and researched(action.key)
  local missingTech = action.requires and not researched(action.requires)
  entry.button:SetAttribute("Unavailable",locked or done or missingTech); entry.edge.Color = buildingKind == action.key and C.gold or C.edge; entry.edge.Thickness = buildingKind == action.key and 2 or 1
  entry.title.TextColor3 = locked and C.muted or C.white
  entry.cost.Text = done and "已完成" or (locked and ("需要"..ageName(action.minAge)) or (missingTech and ("需"..Config.Technologies[action.requires].name) or action.costLabel or compactCost(action.cost)))
  entry.cost.TextColor3 = done and C.green or (affordable(action.cost) and C.muted or C.red)
 end
 self.pageLabel.Text = self.page.." / "..self.pageCount; self.previousPage.Visible = self.pageCount > 1; self.nextPage.Visible = self.pageCount > 1
end
function GUI:Update(selected,buildingKind)
 self.selected,self.buildingKind = selected,buildingKind
 local phase = workspace:GetAttribute("MatchPhase") or "Lobby"; local lobbyVisible = phase == "Lobby" or phase == "Starting"
 if self.lobby.Visible ~= lobbyVisible then self.lobby.Visible = lobbyVisible; if not lobbyVisible then self.dismissedResult = nil end end
 if lobbyVisible then self:UpdateLobby() end
 local ended,defeated = phase == "Ended" or workspace:GetAttribute("MatchEnded"),player:GetAttribute("Defeated")
 self.menuEndLabel.Text = ended and "查看結果 / 重新開局" or "投降"
 self.resultKey = ended and ("ended:"..tostring(workspace:GetAttribute("Winner"))) or (defeated and "defeated" or nil)
 local resultVisible = not lobbyVisible and self.resultKey ~= nil and self.dismissedResult ~= self.resultKey
 if resultVisible and not self.result.Visible then
  self.result.BackgroundTransparency = self.reducedMotion and 0.22 or 0.55
  if not self.reducedMotion then tween(self.result,0.25,{BackgroundTransparency = 0.22}) end
 end
 self.result.Visible = resultVisible
 local modalOpen = self.lobby.Visible or self.result.Visible
 if player:GetAttribute("RTSModalOpen") ~= modalOpen then player:SetAttribute("RTSModalOpen",modalOpen) end
 if resultVisible then
  self.resultHeading.Text = ended and "戰局結束" or "你的勢力已戰敗"
  self.resultDescription.Text = ended and ("勝利勢力："..tostring(workspace:GetAttribute("Winner") or "—").."\n領地的故事，將在下一局延續。") or "你可以繼續觀戰，觀看其他勢力的發展。"
  self.restartButton.Visible = ended; self.restartLabel.Text = workspace:GetAttribute("HostUserId") == player.UserId and "返回戰局設定" or "等待房主重新開局"
 end
 local elapsed = math.max(0,math.floor(workspace:GetAttribute("MatchTime") or 0)); local age = player:GetAttribute("Age") or 1
 self.ageLabel.Text = ageName(age)..string.format(" · %02d:%02d",math.floor(elapsed/60),elapsed%60)
 local ageRemaining = player:GetAttribute("AgeRemaining") or 0; if ageRemaining > 0 then self.ageLabel.Text ..= " · 升級 "..math.ceil(ageRemaining).."秒" end
 for key,label in pairs(self.resourceValues) do label.Text = key == "population" and string.format("%d / %d",player:GetAttribute("Population") or 0,player:GetAttribute("PopulationCap") or 0) or tostring(math.floor(player:GetAttribute(key) or 0)) end
 if self.messageTime and os.clock()-self.messageTime > 5 then self.noticePanel.Visible = false; self.messageTime = nil end
 if defeated then self.objective.Text = "勢力已戰敗 · 可以繼續觀戰"
 elseif ended then self.objective.Text = "對局結束\n勝利者："..tostring(workspace:GetAttribute("Winner") or "—")
 elseif player:GetAttribute("Spectator") then self.objective.Text = "觀戰中 · 等待下一場戰局"
 elseif workspace:GetAttribute("VictoryMode") == "Regicide" then self.objective.Text = "保護你的起始主城\n摧毀敵方主城，取得勝利"
 elseif workspace:GetAttribute("VictoryMode") == "Wonder" then
  local remaining = player:GetAttribute("WonderRemaining") or 0
  self.objective.Text = remaining > 0 and ("世界奇觀已完工\n勝利倒數 "..math.ceil(remaining).." 秒") or ("升級帝王時代建造世界奇觀\n完工後守住 "..(Config.Settings.wonderVictoryTime or 180).." 秒")
 else self.objective.Text = "採集、升級、擴張\n消滅敵方全部單位與建築" end
 local factionList = factions()
 for i,row in ipairs(self.scoreRows) do
  local faction = factionList[i]
  if faction then
   local actor = faction.actor
   local remaining = actor:GetAttribute("WonderRemaining") or 0
   local stateText = actor:GetAttribute("Defeated") and "戰敗" or (remaining > 0 and ("奇觀 "..math.ceil(remaining).."秒") or ("時代 "..(actor:GetAttribute("Age") or 1)))
   row.Text = (faction.ai and "◆ " or "● ")..faction.name.."  "..stateText
   row.TextColor3 = actor:GetAttribute("Defeated") and C.muted or (actor:GetAttribute("TeamColor") or C.white)
  else row.Text = "" end
 end
 self.healthBack.Visible = false; self.healthText.Text = ""; self.productionBack.Visible = false
 if buildingKind then
  local data = Config.Buildings[buildingKind]; self:SetPortrait(buildingKind); self.title.Text = data.name
  self.details.Text = "選擇建造位置\n需要附近村民\n右鍵 / Esc 取消"; self.context.Text = "放 置  /  "..data.name; self.buildHelp.Text = "綠色可以建造 · 紅色表示條件不符"
 elseif #selected > 0 then
  local model = selected[1]
  local kind = model:GetAttribute("UnitType") or model:GetAttribute("BuildingType") or ({wood = "Tree",gold = "Gold",stone = "Stone",food = "Berries"})[model:GetAttribute("ResourceType")] or "TownCenter"
  self:SetPortrait(kind); self.title.Text = #selected > 1 and (#selected.." 個單位") or (model:GetAttribute("DisplayName") or model.Name)
  local lines = {model:GetAttribute("OwnerName") or "自然資源"}
  if model:GetAttribute("Order") then table.insert(lines,model:GetAttribute("Order")) end
  if (model:GetAttribute("Carrying") or 0) > 0 then
   local resource = ({food = "食物",wood = "木材",gold = "黃金",stone = "石材"})[model:GetAttribute("CarryType")] or "資源"
   table.insert(lines,"攜帶 "..resource.." "..math.floor(model:GetAttribute("Carrying")))
  end
  if model:GetAttribute("Amount") then table.insert(lines,"剩餘 "..math.floor(model:GetAttribute("Amount"))) end
  if model:GetAttribute("Complete") == false then table.insert(lines,"施工 "..math.floor((model:GetAttribute("ConstructionProgress") or 0)*100).."%") end
  if model:GetAttribute("Training") then table.insert(lines,"訓練 "..math.ceil(model:GetAttribute("TrainingRemaining") or 0).."秒 · 佇列 "..(model:GetAttribute("QueueCount") or 1)) end
  if model:GetAttribute("Research") then table.insert(lines,model:GetAttribute("Research").." · "..math.ceil(model:GetAttribute("ResearchRemaining") or 0).."秒") end
  if kind == "Wonder" and model:GetAttribute("OwnerId") == player.UserId and (player:GetAttribute("WonderRemaining") or 0) > 0 then table.insert(lines,"奇觀勝利倒數 "..math.ceil(player:GetAttribute("WonderRemaining")).."秒") end
  local progress = model:GetAttribute("Complete") == false and model:GetAttribute("ConstructionProgress") or model:GetAttribute("ResearchProgress") or model:GetAttribute("TrainingProgress")
  if progress then self.productionBack.Visible = true; self.productionFill.Size = UDim2.fromScale(math.clamp(progress,0,1),1) end
  self.details.Text = table.concat(lines,"\n")
  local hp,maximum = model:GetAttribute("HP"),model:GetAttribute("MaxHP")
  if hp and maximum then self.healthBack.Visible = true; self.healthFill.Size = UDim2.fromScale(math.clamp(hp/math.max(1,maximum),0,1),1); self.healthText.Text = string.format("生命值  %d / %d",math.ceil(hp),maximum) end
  self.context.Text = model:GetAttribute("BuildingType") and "生 產 與 科 技" or "建 造 與 指 令"
  self.buildHelp.Text = kind == "villager" and "右鍵採集、施工或移動 · B 開啟建築" or "T 訓練 · R 科技 · U 升級時代 · X 停止"
 else
  self:SetPortrait("TownCenter"); self.title.Text = "建立你的帝國"; self.details.Text = "選取村民採集\n建造房屋增加人口\n發展軍隊守護領地"
  self.context.Text = "建 造 與 指 令"; self.buildHelp.Text = "選取村民，再右鍵點擊資源開始採集"
 end
 self:UpdateCommands(selected,buildingKind)
end
function GUI:UpdateMap()
 local alive,colors = {},{}
 for _,faction in ipairs(factions()) do colors[faction.id] = faction.actor:GetAttribute("TeamColor") end
 for _,name in ipairs({"Resources","Buildings","Units"}) do
  local folder = workspace:FindFirstChild(name)
  if folder then for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart then
    alive[model] = true; local dot = self.dots[model]
    if not dot then
     dot = make("Frame",self.map,{BorderSizePixel = 0,AnchorPoint = Vector2.new(0.5,0.5),Size = UDim2.fromOffset(name == "Buildings" and 7 or 3,name == "Buildings" and 7 or 3),Active = false,ZIndex = 2})
     round(dot,name == "Buildings" and 1 or 2); self.dots[model] = dot
    end
    local pos = model:GetPivot().Position; dot.Position = UDim2.fromScale(pos.X/mapSize()+0.5,pos.Z/mapSize()+0.5)
    dot.BackgroundColor3 = colors[model:GetAttribute("OwnerId")] or Color3.fromRGB(183,173,107)
   end
  end end
 end
 for model,dot in pairs(self.dots) do if not alive[model] then dot:Destroy(); self.dots[model] = nil end end
 local camera = workspace.CurrentCamera
 if camera and camera.CFrame.LookVector.Y < 0 then
  local hit = camera.CFrame.Position+camera.CFrame.LookVector*(-camera.CFrame.Position.Y/camera.CFrame.LookVector.Y)
  self.mapFocus.Position = UDim2.fromScale(hit.X/mapSize()+0.5,hit.Z/mapSize()+0.5)
 end
end
return GUI
