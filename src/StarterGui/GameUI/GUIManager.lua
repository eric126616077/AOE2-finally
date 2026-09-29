local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local TweenService=game:GetService("TweenService")
local Config=require(RS.GameData.GameConfig)
local Grid=require(RS.Shared.Grid)
local Art=require(RS.Shared.Art)
local player=Players.LocalPlayer
local GUI={hitAreas={}}
local C={panel=Color3.fromRGB(24,32,35),card=Color3.fromRGB(36,46,47),edge=Color3.fromRGB(74,86,78),gold=Color3.fromRGB(213,181,115),white=Color3.fromRGB(242,237,220),muted=Color3.fromRGB(156,174,166),green=Color3.fromRGB(136,194,135),red=Color3.fromRGB(222,132,111)}
local function make(class,parent,props)
 local object=Instance.new(class)
 for key,value in pairs(props or {}) do object[key]=value end
 object.Parent=parent
 return object
end
local function text(parent,value,size,pos,fontSize,color,font)
 return make("TextLabel",parent,{Text=value,Size=size,Position=pos,BackgroundTransparency=1,TextColor3=color or C.white,TextSize=fontSize or 16,Font=font or Enum.Font.SourceSans,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=true})
end
local function round(object,radius) make("UICorner",object,{CornerRadius=UDim.new(0,radius or 10)}) end
local function stroke(object,color,transparency) return make("UIStroke",object,{Color=color or C.edge,Thickness=1,Transparency=transparency or 0}) end
local function panel(parent,size,pos)
 local frame=make("Frame",parent,{Size=size,Position=pos,BackgroundColor3=C.panel,BackgroundTransparency=0.04,BorderSizePixel=0,Active=true})
 round(frame,10); stroke(frame)
 table.insert(GUI.hitAreas,frame)
 return frame
end
local function button(parent,size,pos,callback)
 local b=make("TextButton",parent,{Text="",Size=size,Position=pos,BackgroundColor3=C.card,BorderSizePixel=0,AutoButtonColor=false})
 round(b,7)
 local edge=stroke(b,C.edge,0.5)
 b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(52,65,59)}):Play(); edge.Color=C.gold end)
 b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=C.card}):Play(); edge.Color=C.edge end)
 b.Activated:Connect(callback)
 return b,edge
end
local function viewport(parent,kind,size,pos)
 local view=make("ViewportFrame",parent,{Size=size,Position=pos,BackgroundTransparency=1,Ambient=Color3.fromRGB(180,180,180),LightColor=Color3.fromRGB(255,239,206),LightDirection=Vector3.new(-1,-1,-1),Active=false})
 local world=Instance.new("WorldModel"); world.Parent=view
 local model=Art.Create(kind,player:GetAttribute("TeamColor"))
 model.Parent=world
 local cf,bounds=model:GetBoundingBox()
 local center=cf.Position
 local radius=math.max(bounds.X,bounds.Y,bounds.Z)
 local camera=Instance.new("Camera")
 camera.FieldOfView=36
 camera.CFrame=CFrame.lookAt(center+Vector3.new(radius*1.15,radius*0.8,radius*1.4),center)
 camera.Parent=view; view.CurrentCamera=camera
 return view
end
function GUI:Init(callbacks)
 if self.screen then return self end
 local pg=player:WaitForChild("PlayerGui")
 local old=pg:FindFirstChild("AOE2_MainGUI")
 if old then old:Destroy() end
 self.screen=make("ScreenGui",pg,{Name="AOE2_MainGUI",ResetOnSpawn=false,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
 self.canvas=make("Frame",self.screen,{Name="HUD",Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
 self.scale=make("UIScale",self.canvas,{Scale=1})
 local function resize()
  local camera=workspace.CurrentCamera
  if not camera then return end
  local inset=GuiService:GetGuiInset()
  local width,height=camera.ViewportSize.X,camera.ViewportSize.Y-inset.Y
  local scale=math.min(1.15,width/1280,height/600)
  self.scale.Scale=math.max(0.2,scale)
  self.canvas.Size=UDim2.fromOffset(width/self.scale.Scale,height/self.scale.Scale)
 end
 resize()
 if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
 local brand=text(self.canvas,"FRONTIER",UDim2.fromOffset(210,30),UDim2.fromOffset(24,17),27,C.white,Enum.Font.Garamond)
 brand.TextXAlignment=Enum.TextXAlignment.Left
 text(self.canvas,"帝 國 邊 境  /  自 由 建 設",UDim2.fromOffset(225,20),UDim2.fromOffset(24,46),12,C.gold)
 self.resourceValues={}
 self.resourceCards={}
 local resourceNames={food="食物",wood="木材",gold="黃金",stone="石材",population="人口"}
 local resourceColors={food=Color3.fromRGB(205,149,107),wood=Color3.fromRGB(150,185,122),gold=C.gold,stone=Color3.fromRGB(161,182,196),population=Color3.fromRGB(151,194,184)}
 local bar=make("Frame",self.canvas,{Size=UDim2.fromOffset(765,65),Position=UDim2.new(1,-785,0,14),BackgroundTransparency=1})
 for i,key in ipairs({"food","wood","gold","stone","population"}) do
  local card=panel(bar,UDim2.fromOffset(145,65),UDim2.fromOffset((i-1)*155,0))
  local mark=make("Frame",card,{Size=UDim2.fromOffset(4,29),Position=UDim2.fromOffset(13,18),BackgroundColor3=resourceColors[key],BorderSizePixel=0}); round(mark,2)
  text(card,resourceNames[key],UDim2.fromOffset(100,19),UDim2.fromOffset(26,7),13,C.muted)
  self.resourceValues[key]=text(card,"—",UDim2.fromOffset(115,29),UDim2.fromOffset(26,27),25,C.white,Enum.Font.SourceSansSemibold)
  self.resourceCards[key]=card
 end
 local objective=panel(self.canvas,UDim2.fromOffset(232,82),UDim2.fromOffset(20,103))
 text(objective,"你的第一座帝國",UDim2.fromOffset(200,23),UDim2.fromOffset(14,9),18,C.white,Enum.Font.SourceSansSemibold)
 self.objective=text(objective,"採集資源，擴張領地\n摧毀敵方主堡取得勝利",UDim2.fromOffset(203,39),UDim2.fromOffset(14,34),14,C.muted)
 self.noticePanel=panel(self.canvas,UDim2.fromOffset(540,42),UDim2.new(0.5,-270,0,97))
 self.noticePanel.Visible=false
 self.notice=text(self.noticePanel,"",UDim2.new(1,-26,1,0),UDim2.fromOffset(13,0),16,C.gold)
 self.notice.TextXAlignment=Enum.TextXAlignment.Center
 -- Independent bottom cards leave the terrain visible between them.
 self.info=panel(self.canvas,UDim2.fromOffset(264,182),UDim2.new(0,20,1,-205))
 text(self.info,"領 地 情 報",UDim2.fromOffset(225,19),UDim2.fromOffset(14,10),12,C.gold)
 self.portraitHolder=make("Frame",self.info,{Size=UDim2.fromOffset(90,111),Position=UDim2.fromOffset(5,34),BackgroundTransparency=1})
 self.title=text(self.info,"建立你的帝國",UDim2.fromOffset(157,26),UDim2.fromOffset(98,35),20,C.white,Enum.Font.SourceSansSemibold)
 self.details=text(self.info,"",UDim2.fromOffset(151,80),UDim2.fromOffset(98,64),14,C.muted)
 self.details.TextYAlignment=Enum.TextYAlignment.Top
 self.healthBack=make("Frame",self.info,{Size=UDim2.fromOffset(231,4),Position=UDim2.fromOffset(16,150),BackgroundColor3=C.card,BorderSizePixel=0})
 self.healthFill=make("Frame",self.healthBack,{Size=UDim2.fromScale(1,1),BackgroundColor3=C.green,BorderSizePixel=0})
 self.healthText=text(self.info,"",UDim2.fromOffset(231,18),UDim2.fromOffset(16,158),12,C.muted)
 self.bottom=panel(self.canvas,UDim2.fromOffset(624,182),UDim2.new(0.5,-294,1,-205))
 self.bottom.Name="CommandDock"
 self.context=text(self.bottom,"建 造 與 指 令",UDim2.fromOffset(440,22),UDim2.fromOffset(14,8),12,C.gold)
 self.buildButtons={}
 for i,kind in ipairs(Config.BuildOrder) do
  local data=Config.Buildings[kind]
  local b,edge=button(self.bottom,UDim2.fromOffset(140,103),UDim2.fromOffset(14+(i-1)*152,35),function() callbacks.build(kind) end)
  viewport(b,kind,UDim2.fromOffset(82,61),UDim2.fromOffset(28,-1))
  text(b,tostring(i),UDim2.fromOffset(20,20),UDim2.fromOffset(8,4),12,C.muted)
  local title=text(b,data.name,UDim2.fromOffset(128,23),UDim2.fromOffset(6,58),17,C.white,Enum.Font.SourceSansSemibold)
  title.TextXAlignment=Enum.TextXAlignment.Center
  local cost=text(b,Grid.costText(data.cost),UDim2.fromOffset(132,19),UDim2.fromOffset(4,81),11,C.muted)
  cost.TextXAlignment=Enum.TextXAlignment.Center
  self.buildButtons[kind]={button=b,edge=edge,cost=cost}
 end
 self.train=button(self.bottom,UDim2.fromOffset(435,29),UDim2.fromOffset(14,146),callbacks.train)
 self.trainLabel=text(self.train,"",UDim2.new(1,-16,1,0),UDim2.fromOffset(8,0),14,C.gold)
 self.train.Visible=false
 self.buildHelp=text(self.bottom,"選取村民，再右鍵點擊資源開始採集",UDim2.fromOffset(435,28),UDim2.fromOffset(14,146),13,C.muted)
 local stop=button(self.bottom,UDim2.fromOffset(141,29),UDim2.fromOffset(469,146),callbacks.stop)
 local stopLabel=text(stop,"停止  [X]",UDim2.fromScale(1,1),UDim2.fromOffset(0,0),13,C.muted); stopLabel.TextXAlignment=Enum.TextXAlignment.Center
 local mapFrame=panel(self.canvas,UDim2.fromOffset(210,232),UDim2.new(1,-230,1,-255))
 text(mapFrame,"戰 術 地 圖",UDim2.fromOffset(150,23),UDim2.fromOffset(12,7),12,C.gold)
 text(mapFrame,"N ↑",UDim2.fromOffset(36,23),UDim2.fromOffset(172,7),12,C.muted)
 self.map=make("TextButton",mapFrame,{Text="",AutoButtonColor=false,Size=UDim2.fromOffset(186,186),Position=UDim2.fromOffset(12,33),BackgroundColor3=Color3.fromRGB(81,103,66),BorderSizePixel=0,ClipsDescendants=true})
 round(self.map,3)
 for i=1,3 do
  make("Frame",self.map,{Size=UDim2.new(1,0,0,1),Position=UDim2.fromScale(0,i/4),BackgroundColor3=C.muted,BackgroundTransparency=0.85,BorderSizePixel=0})
  make("Frame",self.map,{Size=UDim2.new(0,1,1,0),Position=UDim2.fromScale(i/4,0),BackgroundColor3=C.muted,BackgroundTransparency=0.85,BorderSizePixel=0})
 end
 self.mapFocus=make("Frame",self.map,{Size=UDim2.fromOffset(32,24),AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,ZIndex=3})
 stroke(self.mapFocus,C.white,0.15)
 self.map.Activated:Connect(function()
  local pos=UIS:GetMouseLocation()-GuiService:GetGuiInset()
  local p,s=self.map.AbsolutePosition,self.map.AbsoluteSize
  player:SetAttribute("CameraFocus",Vector3.new((math.clamp((pos.X-p.X)/s.X,0,1)-0.5)*Config.Map.MapSize,0,(math.clamp((pos.Y-p.Y)/s.Y,0,1)-0.5)*Config.Map.MapSize))
 end)
 text(self.canvas,"WASD 移動  ·  滾輪縮放  ·  Home 回主堡  ·  拖曳框選  ·  右鍵下令",UDim2.fromOffset(750,18),UDim2.new(0.5,-375,1,-20),12,C.white).TextXAlignment=Enum.TextXAlignment.Center
 self.dots={}
 -- Drag box remains in unscaled screen coordinates.
 self.selectionBox=make("Frame",self.screen,{Visible=false,BackgroundColor3=C.green,BackgroundTransparency=0.85,BorderSizePixel=1,BorderColor3=C.green,ZIndex=8})
 self:SetPortrait("Castle")
 return self
end
function GUI:SetPortrait(kind)
 if self.portraitKind==kind then return end
 self.portraitKind=kind
 self.portraitHolder:ClearAllChildren()
 viewport(self.portraitHolder,kind,UDim2.fromScale(1,1),UDim2.fromScale(0,0))
end
function GUI:BlocksPointer(screenPoint)
 -- AbsolutePosition is in the inset-adjusted ScreenGui coordinate system.
 local point=(screenPoint or UIS:GetMouseLocation())-GuiService:GetGuiInset()
 for _,area in ipairs(self.hitAreas) do
  if area.Visible then
   local pos,size=area.AbsolutePosition,area.AbsoluteSize
   if point.X>=pos.X and point.Y>=pos.Y and point.X<pos.X+size.X and point.Y<pos.Y+size.Y then return true end
  end
 end
 return false
end
function GUI:Notify(message)
 self.notice.Text=message
 self.noticePanel.Visible=true
 self.messageTime=os.clock()
end
function GUI:Update(selected,buildingKind)
 for key,label in pairs(self.resourceValues) do
  label.Text=key=="population" and string.format("%d / %d",player:GetAttribute("Population") or 0,player:GetAttribute("PopulationCap") or 0) or tostring(player:GetAttribute(key) or 0)
 end
 if self.messageTime and os.clock()-self.messageTime>5 then self.noticePanel.Visible=false; self.messageTime=nil end
 if player:GetAttribute("Defeated") then self.objective.Text="主堡失守 · 本局戰敗"
 elseif workspace:GetAttribute("MatchEnded") then self.objective.Text="對局結束\n勝利者："..(workspace:GetAttribute("Winner") or "—")
 elseif player:GetAttribute("Spectator") then self.objective.Text="觀戰中 · 觀看這片領地的發展" end
 for kind,entry in pairs(self.buildButtons) do
  local affordable=true
  for key,value in pairs(Config.Buildings[kind].cost) do if (player:GetAttribute(key) or 0)<value then affordable=false end end
  entry.edge.Color=buildingKind==kind and C.gold or C.edge
  entry.edge.Thickness=buildingKind==kind and 2 or 1
  entry.cost.TextColor3=affordable and C.muted or C.red
 end
 self.train.Visible=false; self.buildHelp.Visible=true
 self.healthBack.Visible=false; self.healthText.Text=""
 if buildingKind then
  local data=Config.Buildings[buildingKind]
  self:SetPortrait(buildingKind)
  self.title.Text=data.name
  self.details.Text="選擇建造位置\n需要附近村民\n右鍵 / Esc 取消"
  self.context.Text="放 置 建 築  /  "..data.name
  self.buildHelp.Text="綠色可以建造 · 紅色表示條件不符"
 elseif #selected>0 then
  local model=selected[1]
  local kind=model:GetAttribute("UnitType") or model:GetAttribute("BuildingType") or ({wood="Tree",gold="Gold",stone="Stone",food="Berries"})[model:GetAttribute("ResourceType")] or "Castle"
  self:SetPortrait(kind)
  self.title.Text=#selected>1 and (#selected.." 個單位") or (model:GetAttribute("DisplayName") or model.Name)
  local lines={model:GetAttribute("OwnerName") or "自然資源"}
  if model:GetAttribute("Order") then table.insert(lines,model:GetAttribute("Order")) end
  if model:GetAttribute("Amount") then table.insert(lines,"剩餘 "..model:GetAttribute("Amount")) end
  if model:GetAttribute("Training") then table.insert(lines,"訓練中 · "..(model:GetAttribute("TrainingRemaining") or 0).." 秒") end
  self.details.Text=table.concat(lines,"\n")
  if model:GetAttribute("HP") then
   local hp,max=model:GetAttribute("HP"),model:GetAttribute("MaxHP")
   self.healthBack.Visible=true; self.healthFill.Size=UDim2.fromScale(math.clamp(hp/math.max(1,max),0,1),1)
   self.healthText.Text=string.format("生命值  %d / %d",hp,max)
  end
  self.context.Text="建 造 與 指 令"
  self.buildHelp.Text=kind=="villager" and "右鍵採集或移動 · 建造需要村民在附近" or "選取村民建造 · 右鍵向單位下令"
  if model:GetAttribute("OwnerId")==player.UserId then
   local unit=(kind=="Castle" or kind=="TownCenter") and "villager" or (kind=="Barracks" and "infantry")
   if unit then
    self.train.Visible=true; self.buildHelp.Visible=false
    self.trainLabel.Text=model:GetAttribute("Training") and ("訓練"..model:GetAttribute("Training").."中…") or ("[T]  訓練"..Config.Units[unit].name.."   ·   "..Grid.costText(Config.Units[unit].cost))
   end
  end
 else
  self:SetPortrait("Castle")
  self.title.Text="建立你的帝國"
  self.details.Text="選取村民採集\n建造房屋增加人口\n發展軍隊守護領地"
  self.context.Text="建 造 與 指 令"
  self.buildHelp.Text="選取村民，再右鍵點擊資源開始採集"
 end
end
function GUI:UpdateMap()
 local alive={}
 for _,name in ipairs({"Resources","Buildings","Units"}) do
  local folder=workspace:FindFirstChild(name)
  if folder then for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart then
    alive[model]=true
    local dot=self.dots[model]
    if not dot then
     dot=make("Frame",self.map,{BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(name=="Buildings" and 7 or 3,name=="Buildings" and 7 or 3),Active=false,ZIndex=2})
     round(dot,name=="Buildings" and 1 or 2); self.dots[model]=dot
    end
    local pos=model:GetPivot().Position
    dot.Position=UDim2.fromScale(pos.X/Config.Map.MapSize+0.5,pos.Z/Config.Map.MapSize+0.5)
    local owner=Players:GetPlayerByUserId(model:GetAttribute("OwnerId") or 0)
    dot.BackgroundColor3=owner and owner:GetAttribute("TeamColor") or Color3.fromRGB(191,180,116)
   end
  end end
 end
 for model,dot in pairs(self.dots) do if not alive[model] then dot:Destroy(); self.dots[model]=nil end end
 local camera=workspace.CurrentCamera
 if camera and camera.CFrame.LookVector.Y<0 then
  local hit=camera.CFrame.Position+camera.CFrame.LookVector*(-camera.CFrame.Position.Y/camera.CFrame.LookVector.Y)
  self.mapFocus.Position=UDim2.fromScale(hit.X/Config.Map.MapSize+0.5,hit.Z/Config.Map.MapSize+0.5)
 end
end
return GUI
