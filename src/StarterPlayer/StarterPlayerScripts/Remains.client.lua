-- 本機外觀：陣亡單位倒地、屍體淡出、建築倒塌、樹木倒下與資源消失。
-- 屍體（Corpses）與倒塌複本（Ruins）由伺服器建立且不參與碰撞、點選或查詢；
-- 這裡只移動與淡化它們的本機畫面，死亡、摧毀與移除的時機都由伺服器決定。
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local RS=game:GetService("ReplicatedStorage")
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("RemainsRules"))
local FogView=require(RS.Shared.FogView)
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local player=Players.LocalPlayer
if script:GetAttribute("Initialized") then return end
script:SetAttribute("Initialized",true)

local effects=Instance.new("Folder")
effects.Name="RTSRemainsEffects"
effects.Parent=workspace
local corpses,ruins,folders,connections={}, {}, {}, {}
local falling,collapsing=0,0
local moveParts,moveFrames={}, {}
local DUST=Color3.fromRGB(176,158,128)

local function reduced() return player:GetAttribute("ReducedMotion")==true end
local function inView(point)
 local camera=workspace.CurrentCamera
 if not camera then return false end
 local screen,visible=camera:WorldToViewportPoint(point)
 return visible and screen.Z>0 and screen.Z<Rules.MaxDistance and FogView.VisibleAt(point)
end
-- 客戶端收到 Corpses／Ruins 的新模型時，子零件可能還沒複製過來（ChildAdded 先到）。
-- 所以先追蹤模型，零件陸續到達時再加入；晚到的零件立即套用目前的淡出，下一次 RenderStepped 套用動作。
local function addPart(entry,part)
 local item={part=part,final=part.CFrame}
 -- 樹幹與樹冠從底部倒下；地面上的樹樁、木頭與切口只淡出。
 if entry.kind=="tree" then item.topples=item.final.Position.Y-entry.ground.Y>1.5 end
 table.insert(entry.parts,item)
 if entry.alpha~=0 then part.LocalTransparencyModifier=entry.alpha end
end
local function watchParts(model,entry)
 entry.parts={}
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") then addPart(entry,part) end
 end
 entry.connection=model.DescendantAdded:Connect(function(part)
  if part:IsA("BasePart") then addPart(entry,part) end
 end)
end
local function setFade(entry,alpha)
 if entry.alpha==alpha then return end
 entry.alpha=alpha
 for _,item in ipairs(entry.parts) do
  if item.part.Parent then item.part.LocalTransparencyModifier=alpha end
 end
end
local function flush()
 if #moveParts>0 then workspace:BulkMoveTo(moveParts,moveFrames,Enum.BulkMoveMode.FireCFrameChanged) end
 table.clear(moveParts); table.clear(moveFrames)
end
local function queue(entry,motion)
 for _,item in ipairs(entry.parts) do
  if item.part.Parent then
   table.insert(moveParts,item.part)
   table.insert(moveFrames,motion*item.final)
  end
 end
end

-- 單位陣亡 ------------------------------------------------------------------
-- 伺服器把屍體放在 base*lay（平躺）。倒地時從直立 base 逐步轉到 lay：
-- 零件畫面 = base * Lerp(I, lay, a) * lay⁻¹ * base⁻¹ * 最終位置。a=1 時正好回到伺服器位置。
local function trackCorpse(corpse)
 if not corpse:IsA("Model") or corpses[corpse] then return end
 local base,lay,expires=corpse:GetAttribute("CorpseBase"),corpse:GetAttribute("CorpseLay"),corpse:GetAttribute("CorpseExpires")
 if typeof(base)~="CFrame" or typeof(lay)~="CFrame" or type(expires)~="number" then return end
 local entry={base=base,lay=lay,expires=expires,alpha=0}
 watchParts(corpse,entry)
 corpses[corpse]=entry
 -- 只有剛倒下的屍體播倒地；中途加入或畫面外的屍體直接是平躺狀態。
 local age=Config.Combat.corpseSeconds-(expires-workspace:GetServerTimeNow())
 if age<.5 and not reduced() and Rules.Admit(falling,Rules.MaxFalls) and inView(base.Position) then
  entry.fallStart=os.clock()
  entry.undo=lay:Inverse()*base:Inverse()
  falling+=1
  -- 立即擺回直立，避免第一個畫面先看到平躺的屍體。
  queue(entry,base*entry.undo)
  flush()
 end
end
local function untrackCorpse(corpse)
 local entry=corpses[corpse]
 if not entry then return end
 corpses[corpse]=nil
 if entry.connection then entry.connection:Disconnect() end
 if entry.fallStart then falling-=1 end
end
local function stepCorpses(clock,serverNow)
 local still=reduced()
 for corpse,entry in pairs(corpses) do
  if not corpse.Parent then untrackCorpse(corpse); continue end
  local alpha,sink=Rules.CorpseFade(serverNow,entry.expires)
  local motion
  if entry.fallStart then
   local t=(clock-entry.fallStart)/Rules.FallSeconds
   if t>=1 or still then
    entry.fallStart=nil
    falling-=1
    motion=CFrame.identity
   else
    motion=entry.base*CFrame.identity:Lerp(entry.lay,Rules.FallProgress(t))*entry.undo
   end
  end
  -- 降低動態效果時只淡出，不下沉。
  if sink>0 and not still then
   motion=CFrame.new(0,-sink,0)*(motion or CFrame.identity)
  end
  if motion then queue(entry,motion) end
  setFade(entry,alpha)
 end
end

-- 建築倒塌、樹木倒下、資源消失 ----------------------------------------------
local function dust(ground,radius,height)
 for index=1,Rules.CollapseDust do
  local angle=index/Rules.CollapseDust*math.pi*2+Rules.Seed(ground.X,ground.Z)*3
  local puff=Instance.new("Part")
  puff.Name="CollapseDust"
  puff.Shape=Enum.PartType.Ball
  puff.Anchored,puff.CanCollide,puff.CanQuery,puff.CanTouch,puff.CastShadow=true,false,false,false,false
  puff.Material=Enum.Material.SmoothPlastic
  puff.Color=DUST
  puff.Transparency=.35
  local size=math.clamp(radius*.45,2,7)
  puff.Size=Vector3.new(size,size,size)
  puff.Position=ground+Vector3.new(math.cos(angle)*radius*.6,size*.3,math.sin(angle)*radius*.6)
  puff.Parent=effects
  local grown=size*2.2
  TweenService:Create(puff,TweenInfo.new(Rules.CollapseSeconds,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
   {Size=Vector3.new(grown,grown,grown),Position=puff.Position+Vector3.new(0,math.min(height*.4,8),0),Transparency=1}):Play()
  Debris:AddItem(puff,Rules.CollapseSeconds+.2)
 end
end
local function trackRuin(ruin)
 if not ruin:IsA("Model") or ruins[ruin] then return end
 local kind,start,seconds=ruin:GetAttribute("RuinKind"),ruin:GetAttribute("RuinStart"),ruin:GetAttribute("RuinSeconds")
 local ground,height=ruin:GetAttribute("RuinGround"),ruin:GetAttribute("RuinHeight")
 if type(kind)~="string" or type(start)~="number" or type(seconds)~="number" or seconds<=0
  or typeof(ground)~="Vector3" or type(height)~="number" then return end
 local entry={kind=kind,start=start,seconds=seconds,ground=ground,height=math.max(height,1),
  alpha=0,seed=Rules.Seed(ground.X,ground.Z)}
 watchParts(ruin,entry)
 ruins[ruin]=entry
 local fresh=workspace:GetServerTimeNow()-start<seconds*.5
 -- 看不見、太遠、超過同時上限或已過半：直接隱藏，避免已死的建築靜止地多留一會。
 if not fresh or not inView(ground) or (kind=="building" and not Rules.Admit(collapsing,Rules.MaxCollapses)) then
  setFade(entry,1)
  entry.done=true
  return
 end
 local angle=entry.seed*math.pi*2
 entry.axis=Vector3.new(math.cos(angle),0,math.sin(angle))
 if kind=="building" then
  collapsing+=1
  entry.counted=true
  if not reduced() then
   -- 半徑由伺服器給（零件可能還沒到）；舊伺服器沒有這個屬性時用最小值。
   local radius=ruin:GetAttribute("RuinRadius")
   dust(ground,math.max(type(radius)=="number" and radius or 0,3),entry.height)
  end
 end
end
local function untrackRuin(ruin)
 local entry=ruins[ruin]
 if not entry then return end
 ruins[ruin]=nil
 if entry.connection then entry.connection:Disconnect() end
 if entry.counted then collapsing-=1 end
end
local function finishRuin(entry)
 entry.done=true
 setFade(entry,1)
 if entry.counted then entry.counted=false; collapsing-=1 end
end
local function stepRuins(serverNow)
 local still=reduced()
 for ruin,entry in pairs(ruins) do
  if not ruin.Parent then untrackRuin(ruin); continue end
  if entry.done then continue end
  local t=(serverNow-entry.start)/entry.seconds
  if t>=1 then finishRuin(entry); continue end
  local ground=entry.ground
  if entry.kind=="building" then
   local sink,tilt,shake,fade=Rules.Collapse(t,entry.seed)
   if not still then
    local axis=entry.axis
    queue(entry,CFrame.new(ground)
     *CFrame.new(axis.Z*shake,-sink*entry.height*.85,-axis.X*shake)
     *CFrame.fromAxisAngle(axis,tilt)*CFrame.new(-ground))
   end
   setFade(entry,fade)
  elseif entry.kind=="tree" then
   local angle,fade=Rules.TreeFall(t)
   if not still then
    local motion=CFrame.new(ground)*CFrame.fromAxisAngle(entry.axis,angle)*CFrame.new(-ground)
    for _,item in ipairs(entry.parts) do
     if item.topples and item.part.Parent then
      table.insert(moveParts,item.part)
      table.insert(moveFrames,motion*item.final)
     end
    end
   end
   setFade(entry,fade)
  else
   local sink,fade=Rules.ResourceFade(t)
   if not still then queue(entry,CFrame.new(0,-sink*math.min(entry.height,4)*.5,0)) end
   setFade(entry,fade)
  end
 end
end

-- 資料夾監聽 ----------------------------------------------------------------
local handlers={Corpses={add=trackCorpse,remove=untrackCorpse},Ruins={add=trackRuin,remove=untrackRuin}}
local function attach(folder)
 local handler=handlers[folder.Name]
 if not handler or folders[folder] or not folder:IsA("Folder") then return end
 folders[folder]={folder.ChildAdded:Connect(handler.add),folder.ChildRemoved:Connect(handler.remove)}
 for _,child in ipairs(folder:GetChildren()) do handler.add(child) end
end
local function detach(folder)
 local bindings=folders[folder]
 if not bindings then return end
 folders[folder]=nil
 for _,connection in ipairs(bindings) do connection:Disconnect() end
end
for _,child in ipairs(workspace:GetChildren()) do attach(child) end
table.insert(connections,workspace.ChildAdded:Connect(attach))
table.insert(connections,workspace.ChildRemoved:Connect(detach))

table.insert(connections,RunService.RenderStepped:Connect(function()
 if next(corpses)==nil and next(ruins)==nil then return end
 local clock,serverNow=os.clock(),workspace:GetServerTimeNow()
 stepCorpses(clock,serverNow)
 stepRuins(serverNow)
 flush()
end))

script:SetAttribute("RTSRemainsReady",true)
script.Destroying:Once(function()
 for _,connection in ipairs(connections) do connection:Disconnect() end
 for folder in pairs(folders) do detach(folder) end
 effects:Destroy()
end)
