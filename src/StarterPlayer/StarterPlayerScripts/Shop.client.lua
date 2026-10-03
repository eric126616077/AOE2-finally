-- 王國商店介面（只在大廳顯示）：金冠餘額、外觀商店、每日獎勵與 Robux 商品。
-- 客戶端只送出請求與顯示伺服器同步的屬性；扣款、發放與裝備都由伺服器決定。
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Catalog = require(RS:WaitForChild("GameData"):WaitForChild("ShopCatalog"))
local ShopRules = require(RS:WaitForChild("Shared"):WaitForChild("ShopRules"))
local Cosmetic = require(RS.Shared:WaitForChild("CosmeticArt"))
local Art = require(RS.Shared:WaitForChild("Art"))
local command = RS:WaitForChild("RTSRemotes"):WaitForChild("Command")

local C = {panel=Color3.fromRGB(240,227,194), card=Color3.fromRGB(252,244,220), edge=Color3.fromRGB(128,92,56),
 gold=Color3.fromRGB(156,98,16), text=Color3.fromRGB(54,38,26), muted=Color3.fromRGB(120,98,72),
 green=Color3.fromRGB(44,120,56), red=Color3.fromRGB(184,56,40), inset=Color3.fromRGB(218,201,164),
 ribbon=Color3.fromRGB(96,66,42), light=Color3.fromRGB(252,242,216), crown=Color3.fromRGB(255,206,84), royal=Color3.fromRGB(112,72,160)}
local icon = Catalog.currency.icon

local function make(class,parent,props)
 local item = Instance.new(class)
 for k,v in pairs(props or {}) do item[k] = v end
 item.Parent = parent
 return item
end
local function round(item,radius) make("UICorner",item,{CornerRadius=UDim.new(0,radius or 8)}) end
local function stroke(item,color,thickness) return make("UIStroke",item,{Color=color or C.edge,Thickness=thickness or 1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border}) end
local function label(parent,text,size,position,textSize,color,font)
 return make("TextLabel",parent,{Text=text,Size=size,Position=position,TextSize=textSize or 14,TextColor3=color or C.text,
  Font=font or Enum.Font.SourceSansSemibold,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true,Active=false})
end
local function button(parent,text,size,position,color,callback,name)
 local b = make("TextButton",parent,{Name=name or "Button",Text=text,Size=size,Position=position,BackgroundColor3=color or C.ribbon,
  TextColor3=C.light,Font=Enum.Font.SourceSansBold,TextSize=16,AutoButtonColor=true,TextWrapped=true})
 round(b,8)
 if callback then b.Activated:Connect(callback) end
 return b
end
local function formatCrowns(value)
 local text = tostring(math.floor(value or 0))
 local result = text:reverse():gsub("(%d%d%d)","%1,"):reverse()
 return (result:gsub("^,",""))
end
local function send(sub,arg) command:FireServer("Shop",sub,arg) end

local pg = player:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("AOE2_ShopGUI"); if old then old:Destroy() end
local screen = make("ScreenGui",pg,{Name="AOE2_ShopGUI",ResetOnSpawn=false,IgnoreGuiInset=false,DisplayOrder=5,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local canvas = make("Frame",screen,{Name="Canvas",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Active=false})
local scale = make("UIScale",canvas,{Scale=1})
local layoutWidth,layoutHeight = 1280,720

-- 左側直排：金冠餘額、商店、每日獎勵。位於畫面中段左緣，不擋上方教程邀請與下方玩法面板。
local dock = make("Frame",canvas,{Name="ShopDock",Size=UDim2.fromOffset(138,152),BackgroundTransparency=1,Visible=false,Active=false})
local crownPill = button(dock,"",UDim2.fromOffset(138,40),UDim2.fromOffset(0,0),C.ribbon,nil,"CrownBalance")
stroke(crownPill,C.crown,2)
local crownText = label(crownPill,icon.." 0",UDim2.new(1,-16,1,0),UDim2.fromOffset(10,0),20,C.crown,Enum.Font.GothamBold)
crownText.Name = "CrownText"
local shopButton = button(dock,"🛒 王國商店",UDim2.fromOffset(138,44),UDim2.fromOffset(0,48),C.gold,nil,"ShopButton")
shopButton.TextSize = 18
local dailyButton = button(dock,"🎁 每日獎勵",UDim2.fromOffset(138,44),UDim2.fromOffset(0,100),C.green,nil,"DailyButton")
dailyButton.TextSize = 18
local dailyDot = make("Frame",dailyButton,{Name="DailyDot",Size=UDim2.fromOffset(14,14),Position=UDim2.new(1,-10,0,-4),BackgroundColor3=C.red,Visible=false,Active=false})
round(dailyDot,7)
stroke(dailyDot,C.light,2)

-- 全螢幕遮罩：商店開啟時攔截點擊，不會穿透到庭院。
local backdrop = make("TextButton",canvas,{Name="ShopBackdrop",Text="",AutoButtonColor=false,Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),
 BackgroundTransparency=0.45,Visible=false,ZIndex=30})
local panel = make("Frame",backdrop,{Name="ShopPanel",BackgroundColor3=C.panel,ZIndex=31,Active=true})
round(panel,12)
stroke(panel,C.edge,3)
local header = make("Frame",panel,{Name="Header",Size=UDim2.new(1,0,0,52),BackgroundColor3=C.ribbon,ZIndex=31})
round(header,12)
label(header,"♛ 王國商店",UDim2.new(0.5,0,1,0),UDim2.fromOffset(16,0),24,C.light,Enum.Font.SourceSansBold).ZIndex=32
local headerCrowns = label(header,"",UDim2.fromOffset(200,52),UDim2.new(1,-262,0,0),20,C.crown,Enum.Font.GothamBold)
headerCrowns.TextXAlignment = Enum.TextXAlignment.Right
headerCrowns.ZIndex = 32
local close = button(header,"✕",UDim2.fromOffset(40,36),UDim2.new(1,-50,0,8),C.red,nil,"CloseShop")
close.ZIndex = 32
local tabsBar = make("Frame",panel,{Name="Tabs",Size=UDim2.new(1,-24,0,38),Position=UDim2.fromOffset(12,60),BackgroundTransparency=1,ZIndex=31})
make("UIListLayout",tabsBar,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
local body = make("ScrollingFrame",panel,{Name="Items",Position=UDim2.fromOffset(12,106),BackgroundColor3=C.inset,BorderSizePixel=0,
 ScrollBarThickness=8,ScrollBarImageColor3=C.edge,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ZIndex=31,ScrollingDirection=Enum.ScrollingDirection.Y})
round(body,8)
make("UIPadding",body,{PaddingTop=UDim.new(0,8),PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8),PaddingBottom=UDim.new(0,8)})
local grid = make("UIGridLayout",body,{CellSize=UDim2.fromOffset(168,226),CellPadding=UDim2.fromOffset(8,8),SortOrder=Enum.SortOrder.LayoutOrder})
local footer = label(panel,Catalog.policyText,UDim2.new(1,-24,0,34),UDim2.new(0,12,1,-40),13,C.muted)
footer.Name = "Policy"
footer.ZIndex = 31

-- 購買確認
local confirm = make("Frame",backdrop,{Name="ShopConfirm",Size=UDim2.fromOffset(360,168),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
 BackgroundColor3=C.card,Visible=false,ZIndex=40,Active=true})
round(confirm,12)
stroke(confirm,C.edge,3)
local confirmText = label(confirm,"",UDim2.new(1,-32,0,84),UDim2.fromOffset(16,14),18,C.text)
confirmText.ZIndex = 41
confirmText.TextXAlignment = Enum.TextXAlignment.Center
local confirmYes = button(confirm,"購買",UDim2.fromOffset(150,44),UDim2.fromOffset(18,108),C.green,nil,"ConfirmBuy")
confirmYes.ZIndex = 41
local confirmNo = button(confirm,"取消",UDim2.fromOffset(150,44),UDim2.new(1,-168,0,108),C.muted,nil,"CancelBuy")
confirmNo.ZIndex = 41
local pendingBuy

-- 每日獎勵面板
local daily = make("Frame",backdrop,{Name="DailyPanel",Size=UDim2.fromOffset(520,250),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
 BackgroundColor3=C.panel,Visible=false,ZIndex=35,Active=true})
round(daily,12)
stroke(daily,C.edge,3)
local dailyTitle = label(daily,"🎁 每日登入獎勵",UDim2.new(1,-80,0,40),UDim2.fromOffset(18,10),24,C.text,Enum.Font.SourceSansBold)
dailyTitle.ZIndex = 36
local dailyClose = button(daily,"✕",UDim2.fromOffset(40,36),UDim2.new(1,-50,0,10),C.red,nil,"CloseDaily")
dailyClose.ZIndex = 36
local dailyRow = make("Frame",daily,{Size=UDim2.new(1,-36,0,86),Position=UDim2.fromOffset(18,56),BackgroundTransparency=1,ZIndex=36})
make("UIListLayout",dailyRow,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
local dayTiles = {}
for index,amount in ipairs(Catalog.rewards.daily) do
 local tile = make("Frame",dailyRow,{Size=UDim2.fromOffset(62,86),BackgroundColor3=C.card,LayoutOrder=index,ZIndex=36})
 round(tile,8)
 local edge = stroke(tile,C.edge,1.5)
 local dayLabel = label(tile,"第 "..index.." 天",UDim2.new(1,0,0,24),UDim2.fromOffset(0,6),13,C.muted)
 dayLabel.TextXAlignment,dayLabel.ZIndex = Enum.TextXAlignment.Center,37
 local amountLabel = label(tile,icon..amount,UDim2.new(1,0,0,34),UDim2.fromOffset(0,36),index==#Catalog.rewards.daily and 20 or 18,C.gold,Enum.Font.GothamBold)
 amountLabel.TextXAlignment,amountLabel.ZIndex = Enum.TextXAlignment.Center,37
 dayTiles[index] = {tile=tile,edge=edge,amount=amountLabel,day=dayLabel}
end
local dailyNote = label(daily,"",UDim2.new(1,-200,0,40),UDim2.fromOffset(18,152),13,C.muted)
dailyNote.ZIndex = 36
local claim = button(daily,"領取",UDim2.fromOffset(170,48),UDim2.new(1,-188,0,186),C.green,nil,"ClaimDaily")
claim.ZIndex = 36
claim.TextSize = 20

local currentTab = "unitSkin"
local Refresh
local tabButtons = {}
local tabs = {}
for _,slot in ipairs(Catalog.slots) do table.insert(tabs,{id=slot.id,name=slot.name}) end
table.insert(tabs,{id="crowns",name=icon.." 金冠與禮包"})

local function owned() return ShopRules.decodeOwned(player:GetAttribute("OwnedCosmetics")) end
local function vip() return player:GetAttribute("ShopVIP")==true end
local attributeOf = {unitSkin="CosmeticUnitSkin",buildingStyle="CosmeticBuildingStyle",title="CosmeticTitle",trail="CosmeticTrail",victory="CosmeticVictory"}

local function viewport(parent,kind,cosmeticId,slot)
 local view = make("ViewportFrame",parent,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Ambient=Color3.fromRGB(157,165,157),
  LightColor=Color3.fromRGB(255,236,206),LightDirection=Vector3.new(-1,-1.3,-0.6),ZIndex=parent.ZIndex,Active=false})
 local world = make("WorldModel",view)
 local team = player:GetAttribute("TeamColor")
 local model = Art.Create(kind,typeof(team)=="Color3" and team or Color3.fromRGB(46,120,220))
 if slot=="unitSkin" then Cosmetic.SkinUnit(model,cosmeticId) else Cosmetic.StyleBuilding(model,cosmeticId) end
 model.Parent = world
 local cf,bounds = model:GetBoundingBox()
 local radius = math.max(bounds.X,bounds.Y,bounds.Z,4)
 make("Camera",view,{FieldOfView=36,CFrame=CFrame.lookAt(cf.Position+Vector3.new(radius*1.15,radius*0.8,radius*1.4),cf.Position)})
 view.CurrentCamera = view:FindFirstChildOfClass("Camera")
 return view
end

local function swatch(parent,colors)
 local bar = make("Frame",parent,{Size=UDim2.new(1,-24,0,26),Position=UDim2.new(0,12,0.5,-13),BackgroundColor3=Color3.new(1,1,1),ZIndex=parent.ZIndex,Active=false})
 round(bar,13)
 if #colors>=2 then make("UIGradient",bar,{Color=ColorSequence.new(colors[1],colors[#colors])})
 elseif colors[1] then bar.BackgroundColor3 = colors[1]
 else bar.BackgroundColor3,bar.BackgroundTransparency = C.edge,0.7 end
 return bar
end

local function preview(holder,id,item)
 local look = item.look
 if item.slot=="unitSkin" then viewport(holder,"infantry",id,"unitSkin")
 elseif item.slot=="buildingStyle" then viewport(holder,"House",id,"buildingStyle")
 elseif item.slot=="title" then
  local text = look.text=="" and "—" or ((look.crown and "♛ " or "").."「"..look.text.."」")
  local t = label(holder,text,UDim2.fromScale(1,1),UDim2.new(),22,look.text=="" and C.muted or look.color,Enum.Font.FredokaOne)
  t.TextXAlignment,t.ZIndex,t.TextStrokeTransparency,t.TextStrokeColor3 = Enum.TextXAlignment.Center,holder.ZIndex,0.3,Color3.fromRGB(20,22,30)
 elseif item.slot=="trail" then swatch(holder,look.colors)
 elseif item.slot=="victory" then
  local symbol = ({fireworks="✦ ✧ ✦",coins="● ● ●",flame="▲▲▲",none="—"})[look.kind] or "—"
  local t = label(holder,symbol,UDim2.fromScale(1,0.6),UDim2.new(),30,look.colors[1] or C.muted,Enum.Font.GothamBold)
  t.TextXAlignment,t.ZIndex = Enum.TextXAlignment.Center,holder.ZIndex
  local bar = swatch(holder,look.colors)
  bar.Position = UDim2.new(0,12,0.68,0)
  bar.Size = UDim2.new(1,-24,0,12)
 end
end

local function clearBody()
 for _,child in ipairs(body:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
end

local function itemCard(id,item,order,mine,equippedId)
 local card = make("Frame",body,{Name="Item_"..id,BackgroundColor3=C.card,LayoutOrder=order,ZIndex=32,Active=false})
 round(card,10)
 local isEquipped = equippedId==id
 stroke(card,isEquipped and C.green or (item.source=="vip" and C.royal or C.edge),isEquipped and 3 or 1.5)
 local holder = make("Frame",card,{Name="Preview",Size=UDim2.new(1,-12,0,104),Position=UDim2.fromOffset(6,6),BackgroundColor3=C.inset,ZIndex=33,ClipsDescendants=true,Active=false})
 round(holder,8)
 preview(holder,id,item)
 local name = label(card,item.name,UDim2.new(1,-16,0,22),UDim2.fromOffset(8,114),17,C.text,Enum.Font.SourceSansBold)
 name.ZIndex = 33
 local tag = item.source=="vip" and "王室" or item.source=="milestone" and "成就" or item.source=="bundle" and "限定" or nil
 if tag then
  local badge = label(card,tag,UDim2.fromOffset(40,18),UDim2.new(1,-48,0,116),12,C.light,Enum.Font.SourceSansBold)
  badge.BackgroundTransparency,badge.BackgroundColor3,badge.TextXAlignment,badge.ZIndex = 0,item.source=="vip" and C.royal or C.gold,Enum.TextXAlignment.Center,34
  round(badge,6)
 end
 local description = label(card,item.description,UDim2.new(1,-16,0,40),UDim2.fromOffset(8,136),13,C.muted)
 description.TextYAlignment,description.ZIndex = Enum.TextYAlignment.Top,33
 local text,color,action
 if isEquipped then text,color = "✔ 已裝備",C.green
 elseif mine then text,color,action = "裝備",C.ribbon,function() send("Equip",id) end
 elseif item.source=="shop" then
  text,color = icon.." "..formatCrowns(item.price),C.gold
  action = function()
   pendingBuy = id
   local enough = (player:GetAttribute("Crowns") or 0)>=item.price
   confirmText.Text = enough and ("以 "..icon..formatCrowns(item.price).." 購買「"..item.name.."」？\n購買後自動裝備，只改變外觀。")
    or ("金冠不足：「"..item.name.."」需要 "..icon..formatCrowns(item.price).."。\n可以遊玩賺取，或到「金冠與禮包」補充。")
   confirmYes.Text = enough and "購買" or "前往補充"
   confirm.Visible = true
  end
 elseif item.source=="vip" then text,color,action = "王室通行證",C.royal,function() currentTab = "crowns"; Refresh() end
 else text,color = ShopRules.unlockHint(Catalog,id),C.muted end
 local b = button(card,text,UDim2.new(1,-16,0,34),UDim2.new(0,8,1,-42),color,action,"Action")
 b.ZIndex = 34
 b.TextSize = 15
 if not action then b.AutoButtonColor = false end
end

local function productCard(product,order,wide)
 local card = make("Frame",body,{Name="Product_"..product.id,BackgroundColor3=C.card,LayoutOrder=order,ZIndex=32,Active=false})
 round(card,10)
 stroke(card,product.once and C.green or C.gold,product.once and 2.5 or 1.5)
 local amount = label(card,icon.." "..formatCrowns(product.crowns),UDim2.new(1,-16,0,44),UDim2.fromOffset(8,10),28,C.gold,Enum.Font.GothamBold)
 amount.TextXAlignment,amount.ZIndex = Enum.TextXAlignment.Center,33
 local name = label(card,product.name,UDim2.new(1,-16,0,24),UDim2.fromOffset(8,58),18,C.text,Enum.Font.SourceSansBold)
 name.TextXAlignment,name.ZIndex = Enum.TextXAlignment.Center,33
 local detail = product.description or (product.bonus and ("加贈 "..product.bonus) or "")
 local info = label(card,detail,UDim2.new(1,-16,0,74),UDim2.fromOffset(8,84),13,product.bonus and C.green or C.muted)
 info.TextXAlignment,info.TextYAlignment,info.ZIndex = Enum.TextXAlignment.Center,Enum.TextYAlignment.Top,33
 local bought = product.once and player:GetAttribute("StarterPackOwned")==true
 local text = bought and "已購買" or (product.productId==0 and "尚未上架" or "購買（Robux）")
 local b = button(card,text,UDim2.new(1,-16,0,38),UDim2.new(0,8,1,-46),(bought or product.productId==0) and C.muted or C.green,
  (not bought and product.productId~=0) and function() send("PromptProduct",product.id) end or nil,"Buy")
 b.ZIndex = 34
end

local function passCard(order)
 local pass = Catalog.passes.vip
 local card = make("Frame",body,{Name="VIPPass",BackgroundColor3=C.royal,LayoutOrder=order,ZIndex=32,Active=false})
 round(card,10)
 stroke(card,C.crown,3)
 local title = label(card,"♛ "..pass.name,UDim2.new(1,-16,0,30),UDim2.fromOffset(8,10),22,C.crown,Enum.Font.SourceSansBold)
 title.TextXAlignment,title.ZIndex = Enum.TextXAlignment.Center,33
 local info = label(card,pass.description,UDim2.new(1,-16,0,110),UDim2.fromOffset(8,46),14,C.light)
 info.TextXAlignment,info.TextYAlignment,info.ZIndex = Enum.TextXAlignment.Center,Enum.TextYAlignment.Top,33
 local text = vip() and "✔ 已擁有" or (pass.gamePassId==0 and "尚未上架" or "購買（Robux）")
 local b = button(card,text,UDim2.new(1,-16,0,38),UDim2.new(0,8,1,-46),(vip() or pass.gamePassId==0) and C.muted or C.gold,
  (not vip() and pass.gamePassId~=0) and function() send("PromptPass") end or nil,"BuyPass")
 b.ZIndex = 34
end

local function freeCard(order)
 local r = Catalog.rewards
 local card = make("Frame",body,{Name="FreeCrowns",BackgroundColor3=C.card,LayoutOrder=order,ZIndex=32,Active=false})
 round(card,10)
 stroke(card,C.green,2)
 local title = label(card,"免費取得金冠",UDim2.new(1,-16,0,26),UDim2.fromOffset(8,8),18,C.green,Enum.Font.SourceSansBold)
 title.TextXAlignment,title.ZIndex = Enum.TextXAlignment.Center,33
 local lines = string.format("每日登入 %s%d–%d\n完成對局 %s%d，勝利 +%d\n每日首勝 +%d\n劇情章節與成就獎勵\n（對局每日上限 %s%d）",
  icon,r.daily[1],r.daily[#r.daily],icon,r.matchBase,r.matchWin,r.firstWin,icon,r.dailyMatchCap)
 local info = label(card,lines,UDim2.new(1,-16,0,170),UDim2.fromOffset(8,40),14,C.text)
 info.TextXAlignment,info.TextYAlignment,info.ZIndex = Enum.TextXAlignment.Center,Enum.TextYAlignment.Top,33
end

Refresh = function()
 for id,b in pairs(tabButtons) do
  b.BackgroundColor3 = id==currentTab and C.gold or C.ribbon
 end
 clearBody()
 if currentTab=="crowns" then
  passCard(1)
  for index,product in ipairs(Catalog.products) do
   if not (product.once and player:GetAttribute("StarterPackOwned")==true) then productCard(product,index+1) end
  end
  freeCard(100)
  return
 end
 local mine = owned()
 local equippedId = player:GetAttribute(attributeOf[currentTab])
 local list = {}
 for id,item in pairs(Catalog.items) do if item.slot==currentTab then table.insert(list,{id=id,item=item}) end end
 -- 預設在前，接著依價格；同價依名稱，順序穩定。
 local rank = {default=0,shop=1,milestone=2,bundle=3,vip=4}
 table.sort(list,function(a,b)
  if rank[a.item.source]~=rank[b.item.source] then return rank[a.item.source]<rank[b.item.source] end
  if (a.item.price or 0)~=(b.item.price or 0) then return (a.item.price or 0)<(b.item.price or 0) end
  return a.id<b.id
 end)
 for index,entry in ipairs(list) do itemCard(entry.id,entry.item,index,ShopRules.owns(Catalog,mine,entry.id,vip()),equippedId) end
end

for index,tab in ipairs(tabs) do
 local b = button(tabsBar,tab.name,UDim2.fromOffset(tab.id=="crowns" and 128 or 92,36),UDim2.new(),C.ribbon,function()
  currentTab = tab.id
  Refresh()
 end,"Tab_"..tab.id)
 b.LayoutOrder,b.ZIndex,b.TextSize = index,32,15
 tabButtons[tab.id] = b
end

local function inLobby() return player:GetAttribute("InLobby")==true end
local function layout()
 local width,height = screen.AbsoluteSize.X,screen.AbsoluteSize.Y
 if width<=0 or height<=0 then return end
 scale.Scale = UIS.TouchEnabled and 1 or math.max(0.2,math.min(1.1,width/1280,height/620))
 layoutWidth,layoutHeight = width/scale.Scale,height/scale.Scale
 canvas.Size = UDim2.fromOffset(layoutWidth,layoutHeight)
 dock.Position = UDim2.fromOffset(10,math.floor(layoutHeight*0.3))
 local panelWidth,panelHeight = math.min(800,layoutWidth-20),math.min(560,layoutHeight-20)
 panel.Size = UDim2.fromOffset(panelWidth,panelHeight)
 panel.Position = UDim2.fromOffset((layoutWidth-panelWidth)/2,(layoutHeight-panelHeight)/2)
 body.Size = UDim2.new(1,-24,1,-156)
 local columns = math.max(2,math.floor((panelWidth-40)/176))
 local cell = math.floor((panelWidth-40-(columns-1)*8)/columns)
 grid.CellSize = UDim2.fromOffset(cell,226)
 for _,b in pairs(tabButtons) do b.Size = UDim2.fromOffset(math.floor((panelWidth-24-6*(#tabs-1))/#tabs),36) end
 daily.Size = UDim2.fromOffset(math.min(520,layoutWidth-20),250)
 local tileWidth = math.floor((daily.Size.X.Offset-36-6*(#Catalog.rewards.daily-1))/#Catalog.rewards.daily)
 for _,tile in ipairs(dayTiles) do tile.tile.Size = UDim2.fromOffset(tileWidth,86) end
end

local function refreshDaily()
 local claimable = player:GetAttribute("DailyClaimable")==true
 local nextStreak = player:GetAttribute("DailyNextStreak") or 0
 local streak = player:GetAttribute("DailyStreak") or 0
 dailyDot.Visible = claimable
 for index,tile in ipairs(dayTiles) do
  local active = claimable and index==nextStreak
  local done = (claimable and index<nextStreak) or (not claimable and index<=streak)
  tile.tile.BackgroundColor3 = active and C.crown or (done and C.inset or C.card)
  tile.edge.Color,tile.edge.Thickness = active and C.gold or C.edge,active and 3 or 1.5
  tile.day.Text = done and "✔ 已領" or ("第 "..index.." 天")
 end
 claim.Text = claimable and ("領取 "..icon..(player:GetAttribute("DailyNextAmount") or 0)) or "明天再來"
 claim.BackgroundColor3 = claimable and C.green or C.muted
 claim.AutoButtonColor = claimable
 local note = "連續登入天數越多，獎勵越高；中斷一天會從第 1 天開始。"
 if vip() then note = note.."\n王室通行證：每日獎勵 +"..Catalog.passes.vip.dailyBonusPercent.."%" end
 dailyNote.Text = note
end

local function refreshDock()
 local lobby = inLobby()
 dock.Visible = lobby
 if not lobby then backdrop.Visible = false end
 local crowns = formatCrowns(player:GetAttribute("Crowns"))
 crownText.Text = icon.." "..crowns
 local status = player:GetAttribute("WalletStatus")
 local persistent = player:GetAttribute("WalletPersistent")~=false
 headerCrowns.Text = (status=="Ready" and "" or (status=="LoadFailed" and "（錢包讀取失敗）" or "（讀取中）"))..icon.." "..crowns
 footer.Text = Catalog.policyText..(persistent and "" or "\nStudio 測試：金冠與外觀只在本次遊玩有效，不會保存。")
end

local function openShop(tab)
 if not inLobby() then return end
 currentTab = tab or currentTab
 daily.Visible,confirm.Visible = false,false
 panel.Visible = true
 backdrop.Visible = true
 Refresh()
end
local function openDaily()
 if not inLobby() then return end
 panel.Visible,confirm.Visible = false,false
 daily.Visible = true
 backdrop.Visible = true
 refreshDaily()
end
local function closeAll()
 backdrop.Visible,daily.Visible,confirm.Visible = false,false,false
 panel.Visible = true
end

crownPill.Activated:Connect(function() openShop("crowns") end)
shopButton.Activated:Connect(function() openShop() end)
dailyButton.Activated:Connect(openDaily)
close.Activated:Connect(closeAll)
dailyClose.Activated:Connect(closeAll)
backdrop.Activated:Connect(function() if not confirm.Visible then closeAll() end end)
confirmNo.Activated:Connect(function() confirm.Visible,pendingBuy = false,nil end)
confirmYes.Activated:Connect(function()
 local id = pendingBuy
 confirm.Visible,pendingBuy = false,nil
 local item = id and Catalog.items[id]
 if not item then return end
 if (player:GetAttribute("Crowns") or 0)<item.price then currentTab = "crowns"; Refresh(); return end
 send("Buy",id)
end)
claim.Activated:Connect(function() if player:GetAttribute("DailyClaimable")==true then send("ClaimDaily") end end)
UIS.InputBegan:Connect(function(input,processed)
 if not processed and input.KeyCode==Enum.KeyCode.Escape and backdrop.Visible then closeAll() end
end)

-- 屬性一變就重畫（餘額、擁有、裝備、通行證）；商店開著才重建卡片。
local refreshQueued = false
local function queueRefresh()
 refreshDock()
 if refreshQueued then return end
 refreshQueued = true
 task.defer(function()
  refreshQueued = false
  if backdrop.Visible and panel.Visible then Refresh() end
  if daily.Visible then refreshDaily() end
 end)
end
for _,name in ipairs({"Crowns","OwnedCosmetics","ShopVIP","StarterPackOwned","WalletStatus","WalletPersistent","InLobby",
 "CosmeticUnitSkin","CosmeticBuildingStyle","CosmeticTitle","CosmeticTrail","CosmeticVictory"}) do
 player:GetAttributeChangedSignal(name):Connect(queueRefresh)
end
-- 每日獎勵：已完成教程的玩家在大廳時自動提示一次；新玩家只顯示紅點，不打斷教程。
local dailyShown = false
local function dailyChanged()
 refreshDaily()
 if not dailyShown and player:GetAttribute("DailyClaimable")==true and player:GetAttribute("TutorialDone")==true and inLobby()
  and player:GetAttribute("LobbyQueued")~=true and not backdrop.Visible then
  dailyShown = true
  openDaily()
 end
end
for _,name in ipairs({"DailyClaimable","DailyNextAmount","DailyNextStreak","DailyStreak","TutorialDone"}) do
 player:GetAttributeChangedSignal(name):Connect(dailyChanged)
end
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()
refreshDock()
dailyChanged()
