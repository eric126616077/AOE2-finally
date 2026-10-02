-- Client selection cards display authoritative replicated values for units and buildings.
local UIS = game:GetService("UserInputService")
local Config = require(script.Parent.Parent.GameData.GameConfig)
local Grid = require(script.Parent.Grid)
local Icons = require(script.Parent.UnitIcons)
local StatIcons = require(script.Parent.SelectionIcons)
local Panel = {}
Panel.__index = Panel
local C = {ink=Color3.fromRGB(61,44,28),muted=Color3.fromRGB(112,88,57),paper=Color3.fromRGB(225,207,166),
 card=Color3.fromRGB(72,57,38),edge=Color3.fromRGB(142,110,62),green=Color3.fromRGB(64,131,66),red=Color3.fromRGB(164,53,39),gold=Color3.fromRGB(179,126,40),white=Color3.fromRGB(248,234,204)}
local classes = {villager="村民",infantry="步兵",archer="遠程部隊",cavalry="騎兵",siege="攻城器械",monk="僧侶",building="建築"}
local resources = {food="食物",wood="木材",gold="黃金",stone="石材"}
local function make(class,parent,properties)
 local object=Instance.new(class)
 for key,value in pairs(properties) do object[key]=value end
 object.Parent=parent
 return object
end
local function label(parent,name,size,position,fontSize,color)
 return make("TextLabel",parent,{Name=name,Size=size,Position=position,BackgroundTransparency=1,Text="",TextColor3=color or C.ink,
  TextSize=fontSize,Font=Enum.Font.SourceSans,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true})
end
local function dataFor(model)
 return Config.Units[model:GetAttribute("UnitType")] or Config.Buildings[model:GetAttribute("BuildingType")]
end
local function number(model,key,fallback)
 local value=model:GetAttribute(key)
 return Grid.isFinite(value) and value or fallback
end
local function hp(model)
 local maximum=math.max(1,number(model,"MaxHP",dataFor(model).hp))
 return math.clamp(number(model,"HP",maximum),0,maximum),maximum
end
local function healthColor(value,maximum)
 local ratio=value/maximum
 return ratio<=.25 and C.red or ratio<=.5 and C.gold or C.green
end
local function status(model)
 if model:GetAttribute("BuildingType") then
  if model:GetAttribute("Complete")==false then
   return (model:GetAttribute("ConstructionStatus") or "施工中").."\n"..math.floor(number(model,"ConstructionProgress",0)*100).."% · "..number(model,"BuilderCount",0).." 位村民"
  end
  if model:GetAttribute("Research") then return "研究中" end
  if model:GetAttribute("Training") then return "訓練中" end
  return "已完工"
 end
 local order=model:GetAttribute("Order") or "待命"
 local target=model:GetAttribute("OrderTargetName")
 local building=Config.Buildings[model:GetAttribute("OrderTargetBuildingType")]
 if building then target=building.name end
 if not target then target=resources[model:GetAttribute("OrderTargetResourceType")] end
 local verbs={gather="採集",build="施工",repair="修復",deliver="交貨至",attack="攻擊",convert="招降",heal="治療"}
 local verb=verbs[model:GetAttribute("OrderKind")]
 if verb and target then order=verb..target end
 local formation=Config.Formations.types[model:GetAttribute("Formation")]
 if formation then order..="\n"..formation.name end
 return order
end
local function details(model)
 local data=dataFor(model)
 local lines={data.description}
 if model:GetAttribute("BuildingType") then
  if not data.damage then table.insert(lines,"無主動攻擊能力") end
  if model:GetAttribute("Training") then
   table.insert(lines,"訓練："..model:GetAttribute("Training").." · "..math.ceil(number(model,"TrainingRemaining",0)).." 秒")
  end
  if number(model,"QueueCount",0)>0 then table.insert(lines,"生產佇列："..number(model,"QueueCount",0).." 個單位") end
  if model:GetAttribute("Research") then table.insert(lines,"研究："..model:GetAttribute("Research").." · "..math.ceil(number(model,"ResearchRemaining",0)).." 秒") end
  if model:GetAttribute("Amount") then table.insert(lines,"剩餘食物："..math.floor(number(model,"Amount",0)).." / "..number(model,"MaxAmount",data.amount or 0)) end
  if model:GetAttribute("RallyType") then table.insert(lines,"集合點："..tostring(model:GetAttribute("RallyTargetName") or "地面")) end
  if data.dropoff then
   local accepts={}; for _,key in ipairs(data.dropoff) do table.insert(accepts,resources[key]) end
   table.insert(lines,"交回資源："..table.concat(accepts,"、"))
  end
  table.insert(lines,"建造成本："..Grid.costText(data.cost))
  table.insert(lines,"基礎建造時間 "..data.buildTime.." 秒 · "..Config.Ages[data.minAge].name)
 else
  table.insert(lines,"類型："..(classes[data.class] or data.class))
  if data.splash then table.insert(lines,string.format("範圍傷害半徑 %g",data.splash)) end
  for _,key in ipairs({"villager","infantry","archer","cavalry","siege","building"}) do
   if data.bonus[key] then table.insert(lines,"對"..classes[key].."額外傷害 +"..data.bonus[key]) end
  end
  if data.class=="monk" then
   local faith,maxFaith=number(model,"Faith",0),math.max(1,number(model,"MaxFaith",100))
   table.insert(lines,string.format("信仰：%d / %d%s",math.floor(faith),maxFaith,faith>=maxFaith and " · 可招降" or " · 恢復中"))
   table.insert(lines,"右鍵敵方單位招降、右鍵受傷友軍治療；待命時自動治療附近友軍。")
  end
  if data.class=="villager" then
   for _,key in ipairs({"food","wood","gold","stone"}) do
    table.insert(lines,string.format("採集%s：%.2g / 秒",resources[key],number(model,"GatherRate_"..key,data.gatherRate)))
   end
  end
  table.insert(lines,"訓練成本："..Grid.costText(data.cost))
  table.insert(lines,"基礎訓練時間 "..data.trainTime.." 秒 · "..Config.Ages[data.minAge].name)
 end
 return table.concat(lines,"\n")
end
function Panel.new(root,callbacks)
 local self=setmetatable({root=root,callbacks=callbacks,units={},entries={},statCells={}},Panel)
 root.BackgroundColor3=C.paper; root.BackgroundTransparency=0
 make("UIGradient",root,{Color=ColorSequence.new(Color3.fromRGB(247,231,192),Color3.fromRGB(205,180,133)),Rotation=90})
 self.title=label(root,"UnitSelectionTitle",UDim2.new(1,-24,0,22),UDim2.fromOffset(12,7),16)
 self.title.Font=Enum.Font.SourceSansSemibold; self.title.TextWrapped=false; self.title.TextTruncate=Enum.TextTruncate.AtEnd
 self.summary=label(root,"UnitSelectionSummary",UDim2.new(1,-24,0,21),UDim2.fromOffset(12,32),12,C.muted)
 self.summary.TextWrapped=false; self.summary.TextTruncate=Enum.TextTruncate.AtEnd
 self.single=make("Frame",root,{Name="SingleUnitDetails",Size=UDim2.new(1,-24,1,-60),Position=UDim2.fromOffset(12,54),BackgroundTransparency=1})
 self.portraitHolder=make("Frame",self.single,{Name="PortraitHolder",Size=UDim2.fromOffset(78,78),BackgroundColor3=C.card,BorderSizePixel=0})
 make("UIStroke",self.portraitHolder,{Color=C.edge,Thickness=1})
 self.healthTrack=make("Frame",self.single,{Name="SelectedUnitHealth",Size=UDim2.fromOffset(78,5),Position=UDim2.fromOffset(0,84),BackgroundColor3=C.card,BorderSizePixel=0})
 self.healthFill=make("Frame",self.healthTrack,{Name="Fill",Size=UDim2.fromScale(1,1),BackgroundColor3=C.green,BorderSizePixel=0})
 self.healthText=label(self.single,"SelectedUnitHP",UDim2.fromOffset(90,18),UDim2.fromOffset(0,92),14,C.ink)
 self.status=label(self.single,"SelectedUnitStatus",UDim2.fromOffset(88,44),UDim2.fromOffset(0,115),12,C.muted)
 self.statsScroll=make("ScrollingFrame",self.single,{Name="UnitStatsScroll",Size=UDim2.new(1,-94,1,0),Position=UDim2.fromOffset(94,0),
  BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.edge,ScrollingDirection=Enum.ScrollingDirection.Y,Active=true,
  AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.fromOffset(0,0)})
 self.core=make("Frame",self.statsScroll,{Name="SelectionCoreStats",Size=UDim2.new(1,-5,0,78),BackgroundTransparency=1})
 for index,entry in ipairs({{"Attack","attack"},{"Armor","armor"},{"Range","range"},{"AttackInterval","interval"},{"Speed","speed"},{"Population","population"}}) do
  local cell=make("Frame",self.core,{Name="Stat_"..entry[1],Size=UDim2.new(.5,-3,0,24),Position=UDim2.new((index-1)%2*.5,0,0,math.floor((index-1)/2)*26),BackgroundTransparency=1})
  StatIcons.Create(cell,entry[2],UDim2.fromOffset(20,20),UDim2.fromOffset(0,0))
  local value=label(cell,"SelectedUnit"..entry[1],UDim2.new(1,-25,1,0),UDim2.fromOffset(25,1),13)
  value.TextWrapped=false; value.TextTruncate=Enum.TextTruncate.AtEnd
  self.statCells[entry[1]]={cell=cell,value=value}
 end
 self.carry=make("Frame",self.statsScroll,{Name="CarryingCard",Size=UDim2.new(1,-6,0,34),BackgroundColor3=Color3.fromRGB(203,178,127),BackgroundTransparency=.25,BorderSizePixel=0,Visible=false})
 self.carryText=label(self.carry,"CarryingText",UDim2.new(1,-42,1,0),UDim2.fromOffset(38,8),14)
 self.carryText.TextWrapped=false
 self.stats=label(self.statsScroll,"SelectedUnitStats",UDim2.new(1,-8,0,0),UDim2.fromOffset(0,82),13,C.muted)
 self.stats.AutomaticSize=Enum.AutomaticSize.Y
 self.name=label(root,"SelectedUnitName",UDim2.new(1,-24,0,22),UDim2.fromOffset(12,7),16)
 self.name.Font=Enum.Font.SourceSansSemibold; self.name.TextWrapped=false; self.name.TextTruncate=Enum.TextTruncate.AtEnd
 self.grid=make("ScrollingFrame",root,{Name="UnitSelectionGrid",Size=UDim2.new(1,-24,1,-60),Position=UDim2.fromOffset(12,54),
  BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.edge,ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.fromOffset(0,0),Active=true})
 root.Visible=false
 return self
end
function Panel:Rebuild(units,touch)
 self.grid:ClearAllChildren(); self.portraitHolder:ClearAllChildren(); self.entries={}; self.units=table.clone(units)
 self.touch=touch; self.width=self.root.Size.X.Offset; self.portraitColor=#units==1 and units[1]:GetAttribute("TeamColor") or nil
 self.single.Visible=#units==1; self.grid.Visible=#units>1
 if #units==1 then
  local model=units[1]
  if model:GetAttribute("BuildingType") then
   local icon=self.callbacks.portrait(self.portraitHolder,model:GetAttribute("BuildingType"),UDim2.fromScale(1,1),UDim2.fromOffset(0,0),model)
   icon.Name="SelectedBuildingIcon"; icon:SetAttribute("BuildingType",model:GetAttribute("BuildingType"))
  else
   local icon=Icons.Create(self.portraitHolder,model:GetAttribute("UnitType"),UDim2.fromScale(1,1),UDim2.fromOffset(0,0),model:GetAttribute("TeamColor"))
   icon.Name="SelectedUnitIcon"
  end
  self.statsScroll.CanvasPosition=Vector2.zero
  return
 end
 local columns=math.max(1,math.floor((self.width-24)/58))
 for i,unit in ipairs(units) do
  local kind=unit:GetAttribute("UnitType")
  local tile=make("TextButton",self.grid,{Name="SelectionUnit_"..i,Text="",Size=UDim2.fromOffset(52,64),
   Position=UDim2.fromOffset((i-1)%columns*58,math.floor((i-1)/columns)*70),BackgroundColor3=C.card,BorderSizePixel=0,AutoButtonColor=true})
  tile:SetAttribute("UnitType",kind)
  make("UIStroke",tile,{Color=C.edge,Thickness=1})
  Icons.Create(tile,kind,UDim2.fromOffset(46,43),UDim2.fromOffset(3,0),unit:GetAttribute("TeamColor"))
  local track=make("Frame",tile,{Name="UnitHealthTrack",Size=UDim2.new(1,-8,0,3),Position=UDim2.fromOffset(4,44),BackgroundColor3=Color3.fromRGB(24,21,18),BorderSizePixel=0})
  local fill=make("Frame",track,{Name="Fill",Size=UDim2.fromScale(1,1),BackgroundColor3=C.green,BorderSizePixel=0})
  local value=label(tile,"UnitHealthText",UDim2.new(1,-2,0,15),UDim2.fromOffset(1,49),11,C.white)
  value.TextXAlignment=Enum.TextXAlignment.Center; value.TextWrapped=false
  tile.Activated:Connect(function()
   local remove=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
    or UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
   self:Select(unit,remove)
  end)
  tile.MouseEnter:Connect(function()
   if not self.callbacks.blocked() and UIS.MouseEnabled then
    local current,maximum=hp(unit)
    local data=Config.Units[kind]
    self.callbacks.tooltip(data.name..string.format(" · 生命值 %d / %d\n攻擊 %g · 護甲 %g · 射程 %g\n",math.ceil(current),maximum,
     number(unit,"Attack",data.damage),number(unit,"Armor",data.armor or 0),number(unit,"Range",data.range))
     ..status(unit).."\n點選查看 · Shift / Ctrl 點選移出選取")
   end
  end)
  tile.MouseLeave:Connect(function() self.callbacks.tooltip(nil) end)
  table.insert(self.entries,{unit=unit,tile=tile,fill=fill,value=value})
 end
 self.grid.CanvasPosition=Vector2.zero
 self.grid.CanvasSize=UDim2.fromOffset(0,math.ceil(#units/columns)*70)
end
function Panel:Select(unit,remove)
 if self.callbacks.blocked() or not table.find(self.units,unit) or not unit.Parent or (unit:GetAttribute("HP") or 0)<=0 then return false end
 self.callbacks.tooltip(nil)
 self.callbacks.select(unit,remove==true)
 return true
end
function Panel:UpdateSingle(model,touch)
 local data=dataFor(model)
 local building=model:GetAttribute("BuildingType")~=nil
 self.statCells.Attack.value.Text=string.format("攻擊 %g",number(model,"Attack",data.damage or 0))
 self.statCells.Armor.value.Text=string.format("護甲 %g",number(model,"Armor",data.armor or 0))
 self.statCells.Range.value.Text=string.format("射程 %g",number(model,"Range",data.range or 0))
 local interval=number(model,"AttackInterval",data.attackInterval or 0)
 self.statCells.AttackInterval.value.Text=interval>0 and string.format("間隔 %.2g 秒",interval) or "間隔 —"
 self.statCells.Speed.cell.Visible=not building
 self.statCells.Speed.value.Text=string.format("移速 %g",number(model,"Speed",data.speed or 0))
 self.statCells.Population.value.Text=building and ("人口上限 +"..(data.population or 0)) or ("人口 "..(data.population or 1))
 self.statCells.Population.cell.Position=building and UDim2.fromOffset(0,52) or UDim2.new(.5,0,0,52)
 local villager=model:GetAttribute("UnitType")=="villager"
 self.carry.Visible=villager
 if villager then
  local amount=math.max(0,number(model,"Carrying",0))
  local capacity=number(model,"CarryCapacity",data.carryCapacity)
  local key=amount>0 and model:GetAttribute("CarryType") or "empty"
  if not resources[key] and key~="empty" then key="empty" end
  if self.carryKind~=key then
   if self.carryIcon then self.carryIcon:Destroy() end
   self.carryIcon=StatIcons.Create(self.carry,key,UDim2.fromOffset(28,28),UDim2.fromOffset(4,3))
   self.carryIcon.Name="CarryingIcon"; self.carryKind=key
  end
  self.carryText.Text=amount>0 and string.format("%s %g / %g",resources[key] or "資源",amount,capacity) or string.format("空手 · 0 / %g",capacity)
 end
 local cargoFirst=touch and villager
 self.core.Position=UDim2.fromOffset(0,cargoFirst and 38 or 0)
 self.carry.Position=UDim2.fromOffset(0,cargoFirst and 0 or 82)
 self.stats.Position=UDim2.fromOffset(0,villager and 120 or 82)
 self.stats.Text=details(model)
 self.status.Text=status(model)
end
function Panel:Update(selected,buildingKind,touch,relation)
 local units={}
 for _,model in ipairs(selected) do
  if model.Parent and Config.Units[model:GetAttribute("UnitType")] and (model:GetAttribute("HP") or 0)>0 then table.insert(units,model) end
 end
 if #units==0 and #selected==1 then
  local model=selected[1]
  if model.Parent and Config.Buildings[model:GetAttribute("BuildingType")] and (model:GetAttribute("HP") or 0)>0 then table.insert(units,model) end
 end
 self.root.Visible=#units>0 and not buildingKind
 if not self.root.Visible then
  if #self.units>0 then self:Rebuild({},touch) end
  return
 end
 local changed=#units~=#self.units or self.touch~=touch or self.width~=self.root.Size.X.Offset
  or (#units==1 and self.portraitColor~=units[1]:GetAttribute("TeamColor"))
 if not changed then for i,model in ipairs(units) do if model~=self.units[i] then changed=true; break end end end
 if changed then self:Rebuild(units,touch) end
 local total,maximum=0,0
 for _,model in ipairs(units) do local value,limit=hp(model); total+=value; maximum+=limit end
 local title=#units==1 and (units[1]:GetAttribute("DisplayName") or dataFor(units[1]).name) or "已選取 "..#units.." 個單位"
 self.title.Text=title
 self.title.Visible=#units>1; self.name.Visible=#units==1
 self.summary.Text=#units==1 and ((units[1]:GetAttribute("OwnerName") or "未知勢力")..(relation=="ally" and " · 盟友" or relation=="enemy" and " · 敵方" or relation=="unresolved" and " · 隊伍載入中" or ""))
  or string.format("總生命值 %d / %d · 點選圖示查看單位",math.ceil(total),maximum)
 if #units==1 then
  self.name.Text=title
  self.healthText.Text=string.format("%d / %d",math.ceil(total),maximum)
  self.healthFill.Size=UDim2.fromScale(total/maximum,1); self.healthFill.BackgroundColor3=healthColor(total,maximum)
  self:UpdateSingle(units[1],touch)
 else
  for _,entry in ipairs(self.entries) do
   local value,limit=hp(entry.unit)
   entry.tile:SetAttribute("HP",value); entry.tile:SetAttribute("MaxHP",limit)
   entry.fill.Size=UDim2.fromScale(value/limit,1); entry.fill.BackgroundColor3=healthColor(value,limit)
   entry.value.Text=string.format("%d/%d",math.ceil(value),limit)
  end
 end
 self.single.Position=UDim2.fromOffset(12,touch and 32 or 54); self.single.Size=UDim2.new(1,-24,1,touch and -38 or -60)
 self.name.Size=UDim2.new(touch and .52 or 1,-24,0,22)
 self.summary.Position=touch and #units==1 and UDim2.new(.52,0,0,11) or UDim2.fromOffset(12,32)
 self.summary.Size=touch and #units==1 and UDim2.new(.48,-12,0,18) or UDim2.new(1,-24,0,21)
 self.grid.Position=UDim2.fromOffset(12,touch and 48 or 54); self.grid.Size=UDim2.new(1,-24,1,touch and -54 or -60)
 if touch and #units>1 then
  for i,entry in ipairs(self.entries) do entry.tile.Position=UDim2.fromOffset((i-1)*58,0) end
  self.grid.ScrollingDirection=Enum.ScrollingDirection.X; self.grid.CanvasSize=UDim2.fromOffset(#units*58,64)
 else self.grid.ScrollingDirection=Enum.ScrollingDirection.Y end
 self.portraitHolder.Size=UDim2.fromOffset(touch and 48 or 78,touch and 48 or 78)
 self.healthTrack.Size=UDim2.fromOffset(touch and 48 or 78,5); self.healthTrack.Position=UDim2.fromOffset(0,touch and 49 or 84)
 self.healthText.Position=UDim2.fromOffset(touch and 54 or 0,touch and 0 or 92)
 self.status.Size=UDim2.fromOffset(touch and 136 or 88,touch and 31 or 44)
 self.status.Position=UDim2.fromOffset(0,touch and 61 or 115)
 self.statsScroll.Position=UDim2.fromOffset(touch and 142 or 94,0); self.statsScroll.Size=UDim2.new(1,touch and -142 or -94,1,0)
end
return Panel
