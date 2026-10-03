-- Continuous local presentation. Roots, hitboxes, orders and damage stay server authoritative.
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
local Motion=require(game.ReplicatedStorage.Shared.MotionRules)
local UnitView=require(game.ReplicatedStorage.Shared.ClientUnitView)
-- 戰爭迷霧中看不到的敵方單位不顯示血條與攻擊特效。
local FogView=require(game.ReplicatedStorage.Shared.FogView)
local player=Players.LocalPlayer
if script:GetAttribute("MotionInitialized") then return end
script:SetAttribute("MotionInitialized",true)
local units=workspace:WaitForChild("Units")
local buildings=workspace:WaitForChild("Buildings")
local tracked,observers,projectiles={}, {}, {}
local visibleUnits={}
local diagnostics={rootSamples=0,partWrites=0,totalPartWrites=0}
local motionProbe
local reducedMotion=player:GetAttribute("ReducedMotion")==true
local activeEffects=0
local MAX_EFFECTS=80
local effects=Instance.new("Folder")
effects.Name="RTSClientEffects"
effects.Parent=workspace
local effectKinds={}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function finitePosition(value)
 return typeof(value)=="Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function onScreen(point)
 local camera=workspace.CurrentCamera
 if not camera then return false end
 local screen,visible=camera:WorldToViewportPoint(point)
 return visible and screen.Z>0 and screen.Z<600
end
local function keepEffect(effect,moving,lifetime)
 if activeEffects>=MAX_EFFECTS then effect:Destroy(); return false end
 activeEffects+=1
 effectKinds[effect]=moving
 effect.Destroying:Once(function()
  activeEffects-=1
  effectKinds[effect]=nil
  projectiles[effect]=nil
 end)
 effect.Parent=effects
 Debris:AddItem(effect,lifetime)
 return true
end
local function effectPart(name,size,color,material)
 local part=Instance.new("Part")
 part.Name,part.Size,part.Color=name,size,color
 part.Anchored=true
 part.CanCollide,part.CanQuery,part.CanTouch=false,false,false
 part.Material=material or Enum.Material.SmoothPlastic
 part.CastShadow=false
 return part
end
local function flash(model,name,color)
 local root=model.PrimaryPart
 if not root or not onScreen(root.Position) or activeEffects>=MAX_EFFECTS then return end
 local outline=Instance.new("Highlight")
 outline.Name=name
 outline.Adornee=model
 outline.DepthMode=Enum.HighlightDepthMode.Occluded
 outline.FillColor,outline.OutlineColor=color,color
 outline.FillTransparency,outline.OutlineTransparency=.92,.25
 if not keepEffect(outline,false,.25) then return end
 TweenService:Create(outline,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
  {FillTransparency=1,OutlineTransparency=1}):Play()
end
local function impact(point,color,siege)
 if player:GetAttribute("ReducedMotion")==true or not onScreen(point) then return end
 local part=effectPart("ImpactEffect",siege and Vector3.new(2,.3,2) or Vector3.new(.45,.45,.45),color)
 part.Shape=Enum.PartType.Ball
 part.Position=point
 part.Transparency=.25
 if not keepEffect(part,true,.25) then return end
 TweenService:Create(part,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
  {Transparency=1}):Play()
end
-- Overhead health bar: appears when a unit or building is hit, follows later HP changes and
-- hides a few seconds after the last hit. Local display only; HP stays server authoritative.
local healthBars={}
-- Unit bars hang on a local anchor that is placed on the smoothed visible frame every render
-- step. Adorning the replicated Root would show its 10 Hz server steps as stutter.
local anchors=Instance.new("Folder")
anchors.Name="RTSClientAnchors"
anchors.Parent=workspace
local function hideHealth(model)
 local bar=healthBars[model]
 if not bar then return end
 healthBars[model]=nil
 bar.gui:Destroy()
 if bar.anchor then bar.anchor:Destroy() end
end
local function fillHealth(model,bar)
 local hp,maxHP=model:GetAttribute("HP"),model:GetAttribute("MaxHP")
 if not finite(hp) or not finite(maxHP) or maxHP<=0 or hp<=0 then hideHealth(model); return end
 local ratio=math.clamp(hp/maxHP,0,1)
 bar.fill.Size=UDim2.fromScale(ratio,1)
 bar.fill.BackgroundColor3=ratio>.5 and Color3.fromRGB(96,196,92) or ratio>.25 and Color3.fromRGB(232,190,70) or Color3.fromRGB(214,72,60)
end
local function showHealth(model)
 if not FogView.CanSee(model) then return end
 local root=model.PrimaryPart
 if not root then return end
 local bar=healthBars[model]
 if not bar then
  local unit=model.Parent==units
  local gui=Instance.new("BillboardGui")
  gui.Name="RTSHealthBar"
  local anchor
  if unit then
   anchor=effectPart("HealthAnchor",Vector3.new(.2,.2,.2),Color3.new())
   anchor.Transparency=1
   anchor.Position=UnitView.GetFrame(model).Position
   anchor.Parent=anchors
  end
  gui.Adornee=anchor or root
  gui.AlwaysOnTop=true
  gui.LightInfluence=0
  gui.MaxDistance=900
  gui.ResetOnSpawn=false
  gui.Size=unit and UDim2.fromScale(root.Size.Y>6 and 5 or 4,.55) or UDim2.fromScale(math.clamp(root.Size.X*.6,6,18),.9)
  local offset=Vector3.new(0,unit and (root.Size.Y>6 and 7.5 or 4.5) or root.Size.Y/2+3,0)
  gui.StudsOffsetWorldSpace=offset
  local back=Instance.new("Frame")
  back.Size=UDim2.fromScale(1,1)
  back.BackgroundColor3=Color3.fromRGB(28,24,20)
  back.BorderSizePixel=0
  back.Parent=gui
  local stroke=Instance.new("UIStroke")
  stroke.Color=Color3.fromRGB(12,10,8)
  stroke.Thickness=1
  stroke.Parent=back
  local fill=Instance.new("Frame")
  fill.Name="Fill"
  fill.BorderSizePixel=0
  fill.Parent=back
  bar={gui=gui,fill=fill,token=0,anchor=anchor}
  healthBars[model]=bar
  gui.Parent=player:WaitForChild("PlayerGui")
 end
 fillHealth(model,bar)
 if healthBars[model]~=bar then return end
 bar.token+=1
 local token=bar.token
 task.delay(Config.Combat.healthBarSeconds,function()
  if healthBars[model]==bar and bar.token==token then hideHealth(model) end
 end)
end
-- How far in front of its own center each melee weapon ends at the peak of the swing.
-- The figure steps in by the remaining gap, so the blade, spear point or ram head touches the target.
local meleeReach={villager=1.6,infantry=2.4,spearman=5.3,scout=4.1,cavalry=4.1,camel=4.1,ram=7.1}
local MAX_LUNGE=3.5
local function meleeLunge(model,kind)
 local reach,contact=meleeReach[kind],model:GetAttribute("AttackContact")
 if not reach or not finitePosition(contact) then return 0 end
 local from=UnitView.GetFrame(model).Position
 local dx,dz=contact.X-from.X,contact.Z-from.Z
 return math.clamp(math.sqrt(dx*dx+dz*dz)-reach,0,MAX_LUNGE)
end
-- Extra pieces ride the main projectile part: -Z is the direction of travel.
local function projectilePiece(parent,extras,size,offset,color,material)
 local piece=effectPart("Piece",size,color,material)
 piece.Parent=parent
 table.insert(extras,{part=piece,offset=offset})
end
local function attackEffect(model)
 if player:GetAttribute("ReducedMotion")==true or activeEffects>=MAX_EFFECTS then return end
 local root,target=model.PrimaryPart,model:GetAttribute("AttackPosition")
 local unitKind,buildingKind=model:GetAttribute("UnitType"),model:GetAttribute("BuildingType")
 local data=Config.Units[unitKind] or Config.Buildings[buildingKind]
 if not data or not root or not finitePosition(target) or not onScreen(root.Position) then return end
 if not FogView.CanSee(model) and not FogView.VisibleAt(target) then return end
 local kind=Config.Combat.projectileKinds[unitKind] or "arrow"
 local stone,javelin,bullet=kind=="stone",kind=="javelin",kind=="bullet"
 local sourceFrame=unitKind and UnitView.GetFrame(model) or root.CFrame
 local start=sourceFrame.Position+Vector3.new(0,unitKind and (stone and 3 or 1.5) or root.Size.Y*.35,0)
 local finish=target+Vector3.new(0,2,0)
 local direction=finish-start
 if direction.Magnitude<.1 then return end
 -- The server resolves the hit after this many seconds: the swing lands / the projectile arrives then.
 local flight=model:GetAttribute("AttackFlight")
 if (data.range or 0)<=20 then
  local contact=model:GetAttribute("AttackContact")
  local point=finitePosition(contact) and contact+Vector3.new(0,2.5,0) or finish
  task.delay(finite(flight) and math.clamp(flight,0,1) or Config.Combat.windup.default,function()
   impact(point,Color3.fromRGB(236,196,135),false)
  end)
  return
 end
 local name=stone and "StoneEffect" or javelin and "JavelinEffect" or bullet and "BulletEffect" or "ArrowEffect"
 local wood,steel=Color3.fromRGB(150,112,70),Color3.fromRGB(196,202,204)
 local color=stone and Color3.fromRGB(165,162,145) or Color3.fromRGB(231,199,134)
 -- 駐軍讓防禦建築一次射出多支箭：每支箭從稍微錯開的位置出發，落點相同。
 local volley=buildingKind and math.clamp(tonumber(model:GetAttribute("AttackVolley")) or 1,1,16) or 1
 local side=direction:Cross(Vector3.yAxis)
 side=side.Magnitude>.01 and side.Unit or Vector3.xAxis
 local origin=start
 for shot=1,volley do
 if shot>1 and activeEffects>=MAX_EFFECTS then return end
 start=origin+side*((shot-(volley+1)/2)*1.4)+Vector3.new(0,((shot*7)%5-2)*.35,0)
 local extras={}
 local part
 if stone then
  local diameter=unitKind=="trebuchet" and 2.3 or 1.7
  part=effectPart(name,Vector3.new(diameter,diameter,diameter),color,Enum.Material.Slate)
  part.Shape=Enum.PartType.Ball
 elseif bullet then
  -- Lead ball with a short bright tracer; a puff of powder smoke hangs at the muzzle.
  part=effectPart(name,Vector3.new(.35,.35,1.6),Color3.fromRGB(255,214,140),Enum.Material.Neon)
  if shot==1 and activeEffects<MAX_EFFECTS then
   local smoke=effectPart("MuzzleSmoke",Vector3.new(1.4,1.4,1.4),Color3.fromRGB(214,210,200))
   smoke.Shape=Enum.PartType.Ball
   smoke.Transparency=.35
   smoke.Position=start
   if keepEffect(smoke,true,.6) then
    TweenService:Create(smoke,TweenInfo.new(.55,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
     {Size=Vector3.new(3.4,3.4,3.4),Position=start+Vector3.new(0,1.4,0),Transparency=1}):Play()
   end
  end
 else
  -- A real shaft with an iron head and fletching, not a flash.
  local length=javelin and 3.8 or 2.6
  local thickness=javelin and .2 or .14
  part=effectPart(name,Vector3.new(thickness,thickness,length),wood,Enum.Material.Wood)
  projectilePiece(part,extras,Vector3.new(.3,.3,javelin and .8 or .5),CFrame.new(0,0,-length/2-.2),steel,Enum.Material.Metal)
  if not javelin then
   local feather=Color3.fromRGB(236,232,220)
   projectilePiece(part,extras,Vector3.new(.5,.06,.55),CFrame.new(0,0,length/2-.3),feather)
   projectilePiece(part,extras,Vector3.new(.06,.5,.55),CFrame.new(0,0,length/2-.3),feather)
  end
 end
 part.CFrame=CFrame.lookAt(start,finish)
 for _,extra in ipairs(extras) do extra.part.CFrame=part.CFrame*extra.offset end
 local duration=finite(flight) and math.clamp(flight,.05,3) or (stone and .5 or .2)
 if not keepEffect(part,true,duration+.25) then return end
 projectiles[part]={start=start,finish=finish,created=os.clock(),duration=duration,extras=extras,
  arc=stone and math.min(22,direction.Magnitude*.2) or bullet and 0 or math.min(javelin and 5 or 6,direction.Magnitude*.08),
  color=color,siege=stone}
 end
end
local workColors={
 food=Color3.fromRGB(164,190,109),wood=Color3.fromRGB(171,127,77),
 gold=Color3.fromRGB(226,187,78),stone=Color3.fromRGB(181,183,168),
 build=Color3.fromRGB(191,161,112),repair=Color3.fromRGB(210,193,133),
}
local function workEffect(model,observer)
 if player:GetAttribute("ReducedMotion")==true or model:GetAttribute("Animation")~="Work" then return end
 local root=model.PrimaryPart
 local now=os.clock()
 if not root or now-observer.lastWorkEffect<.65 or not onScreen(root.Position) then return end
 observer.lastWorkEffect=now
 local color=workColors[model:GetAttribute("WorkKind")]
 if not color then return end
 local part=effectPart("WorkEffect",Vector3.new(.22,.22,.22),color)
 part.Position=(UnitView.GetFrame(model)*CFrame.new(1.6,-1,-2)).Position
 if not keepEffect(part,true,.25) then return end
 TweenService:Create(part,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
  {Position=part.Position+Vector3.new(.15,.4,0),Transparency=1}):Play()
end

-- Animate known fallback groups. Other appearance parts follow the same frame at rest.
-- Queryable original geometry moves with its image, so a visible unit remains clickable.
local groups={
 BootL="foot",BootR="foot",HorseLeg="horseLeg",Wheel="wheel",
 Arm="right",ArmR="right",Tool="right",ToolHead="right",Sword="right",
 Spear="right",Spearhead="right",Bow="right",Bowstring="right",Staff="right",StaffHead="right",Gun="right",
 ArmL="left",Shield="left",
 Body="torso",Belt="torso",Tabard="torso",Head="torso",Hat="torso",HatBand="torso",Quiver="torso",Robe="torso",Carry="torso",
 HorseBody="horse",Saddle="horse",HorseCloth="horse",HorseHead="horse",HorseNeck="horse",Mane="horse",Hump="horse",
 Chassis="siege",Roof="siege",Ridge="siege",SiegeBanner="siege",CatapultPost="siege",TrebuchetFrame="siege",
 RamLog="ram",RamHead="ram",CatapultArm="catapult",StoneBasket="catapult",
 TrebuchetArm="trebuchet",Counterweight="trebuchet",Sling="trebuchet",
}
local function detachPresentation(model,item)
 if item.rootConnection then item.rootConnection:Disconnect() end
 for _,entry in ipairs(item.parts) do
  if entry.part.Parent and item.root.Parent then entry.part.CFrame=item.root.CFrame*entry.offset end
 end
 for _,entry in ipairs(item.billboards) do
  if entry.gui.Parent then entry.gui.StudsOffsetWorldSpace=entry.offset end
 end
 UnitView.Clear(model)
end
local function refresh(model)
 local root=model.PrimaryPart
 local previous=tracked[model]
 if model.Parent~=units or not root or not root:IsDescendantOf(model) then
  if previous then detachPresentation(model,previous) end
  tracked[model]=nil; visibleUnits[model]=nil; return
 end
 if previous and previous.root~=root then detachPresentation(model,previous); previous=nil end
 local existing={}
 if previous and previous.root==root then
  for _,entry in ipairs(previous.parts) do existing[entry.part]=entry end
 end
 local parts,billboards={},{}
 for _,part in ipairs(model:GetDescendants()) do
  local group=groups[part.Name]
  if part:IsA("BasePart") and part~=root and part.Name~="Root" and part.Name~="Footprint"
   and part.Name~="CollisionVolume" and not part.CanCollide then
   local entry=existing[part]
   if not entry then
    local offset=root.CFrame:ToObjectSpace(part.CFrame)
    entry={part=part,offset=offset,group=group,side=offset.X<0 and -1 or 1,
     front=offset.Z<0 and -1 or 1,pivot=offset.Position+Vector3.new(0,part.Size.Y/2-.1,0)}
   end
   table.insert(parts,entry)
  elseif part:IsA("BillboardGui") and part.Adornee==root then
   local original=part.StudsOffsetWorldSpace
   if previous then
    for _,entry in ipairs(previous.billboards) do if entry.gui==part then original=entry.offset; break end end
   end
   table.insert(billboards,{gui=part,offset=original})
  end
 end
 if #parts>0 then
  if previous then previous.parts,previous.billboards=parts,billboards
  else
   local frame=root.CFrame
   local item={root=root,parts=parts,billboards=billboards,timeline=Motion.New(os.clock(),frame),
    rootFrame=frame,viewFrame=frame,phase=0,gait=0,lastMove=-math.huge,wasActive=false,dirty=true,poseDirty=true,
    idleNext=0,idleSeed=math.random()*math.pi*2,idleClock=0}
   tracked[model]=item
   diagnostics.rootSamples+=1
   item.rootConnection=root:GetPropertyChangedSignal("CFrame"):Connect(function()
    if tracked[model]~=item then return end
    local nextFrame=root.CFrame
    if nextFrame==item.rootFrame then return end
    local now=os.clock()
    local distance=(nextFrame.Position-item.rootFrame.Position).Magnitude
    if distance>.002 then item.lastMove=now end
    local observer=observers[model]
    Motion.Push(item.timeline,now,nextFrame,Motion.IsDiscontinuity(distance,observer and observer.speed))
    diagnostics.rootSamples+=1
    item.rootFrame=nextFrame
    item.dirty=true
   end)
  end
 else
  if previous then detachPresentation(model,previous) end
  tracked[model]=nil; visibleUnits[model]=nil
 end
end
local function scheduleRefresh(model)
 local observer=observers[model]
 if not observer or observer.pending then return end
 observer.pending=true
 task.defer(function()
  if observers[model]~=observer then return end
  observer.pending=false
  refresh(model)
 end)
end
local function untrack(model)
 local item=tracked[model]
 if item then detachPresentation(model,item) end
 tracked[model]=nil
 visibleUnits[model]=nil
 UnitView.Clear(model)
 hideHealth(model)
 local observer=observers[model]
 if not observer then return end
 observers[model]=nil
 for _,connection in ipairs(observer.connections) do connection:Disconnect() end
end
local function track(model)
 if not model:IsA("Model") or observers[model] then return end
 local observer={pending=false,connections={},lunge=0,lastAttack=-math.huge,lastWork=-math.huge,lastWorkEffect=-math.huge,
  lastDamage=-math.huge,hp=model:GetAttribute("HP"),complete=model:GetAttribute("Complete")}
 observers[model]=observer
 local function connect(signal,callback)
  table.insert(observer.connections,signal:Connect(callback))
 end
 connect(model:GetAttributeChangedSignal("LastAttack"),function()
  observer.lastAttack=os.clock()
  observer.lunge=0
  -- Attribute replication can arrive in one batch; read the matching position after that batch.
  task.defer(function()
   if observers[model]~=observer then return end
   observer.lunge=meleeLunge(model,observer.kind)
   attackEffect(model)
  end)
 end)
 connect(model:GetAttributeChangedSignal("LastWork"),function()
  observer.lastWork=os.clock()
  task.defer(function() if observers[model]==observer then workEffect(model,observer) end end)
 end)
 connect(model:GetAttributeChangedSignal("LastDelivery"),function()
  flash(model,"DeliveryFeedback",Color3.fromRGB(143,190,111))
 end)
 connect(model:GetAttributeChangedSignal("HP"),function()
  local hp=model:GetAttribute("HP")
  local now=os.clock()
  -- A hit shows the bar and restarts its timer; healing or repair only updates a visible bar.
  if finite(hp) and finite(observer.hp) and hp<observer.hp then showHealth(model)
  elseif healthBars[model] then fillHealth(model,healthBars[model]) end
  if finite(hp) and finite(observer.hp) and hp<observer.hp and now-observer.lastDamage>=.25 then
   observer.lastDamage=now
   flash(model,"DamageFeedback",Color3.fromRGB(224,140,114))
  end
  observer.hp=hp
 end)
 connect(model:GetAttributeChangedSignal("Complete"),function()
  local complete=model:GetAttribute("Complete")
  if complete==true and observer.complete==false then
   flash(model,"CompletionFeedback",Color3.fromRGB(153,195,144))
  end
  observer.complete=complete
 end)
 if model.Parent==units then
  for field,attribute in pairs({animation="Animation",kind="UnitType",speed="Speed",workKind="WorkKind"}) do
   observer[field]=model:GetAttribute(attribute)
   connect(model:GetAttributeChangedSignal(attribute),function() observer[field]=model:GetAttribute(attribute) end)
  end
  connect(model:GetPropertyChangedSignal("PrimaryPart"),function() scheduleRefresh(model) end)
  connect(model.DescendantAdded,function(part)
   if part:IsA("BasePart") or part:IsA("BillboardGui") then scheduleRefresh(model) end
  end)
  connect(model.DescendantRemoving,function(part)
   if part:IsA("BasePart") or part:IsA("BillboardGui") then scheduleRefresh(model) end
  end)
  refresh(model)
 end
end
local folderConnections={
 units.ChildAdded:Connect(track),units.ChildRemoved:Connect(untrack),
 buildings.ChildAdded:Connect(track),buildings.ChildRemoved:Connect(untrack),
}
for _,model in ipairs(units:GetChildren()) do track(model) end
for _,model in ipairs(buildings:GetChildren()) do track(model) end

local function turnAt(point,angle)
 return CFrame.new(point)*CFrame.Angles(angle,0,0)*CFrame.new(-point)
end
local function pose(entry,item,kind,walk,work,attack,workKind)
 local group,phase=entry.group,item.phase
 if not group then return entry.offset end
 local sine,cosine=math.sin(phase),math.cos(phase)
 local mounted=Config.Units[kind]~=nil and Config.Units[kind].mounted==true
 -- A standing figure slowly shifts its weight; feet, hooves and wheels stay planted.
 local idle=walk<=0 and not work and attack<=0
 local breath=item.idleClock*1.6+item.idleSeed
 -- walk is the stride weight 0..1. A walker sinks as its legs spread, so the planted sole
 -- stays on the ground; a horse rises with each bound.
 local lift=mounted and walk*.18*sine*sine or -walk*.3*sine*sine
 local frame=CFrame.new(0,lift,0)
 if group=="wheel" then
  return walk>0 and CFrame.new(entry.offset.Position)*CFrame.Angles(phase,0,0)*entry.offset.Rotation or entry.offset
 elseif group=="horseLeg" then
  local shift=entry.side*entry.front<0 and math.pi or 0
  -- The leg swinging forward lifts clear; the one pushing back stays planted.
  local swing=walk*.3*math.max(0,math.cos(phase+shift))
  return CFrame.new(0,swing,0)*turnAt(entry.pivot,walk*math.sin(phase+shift)*.55)*entry.offset
 elseif group=="horse" then
  return frame*turnAt(Vector3.new(0,1,-2),walk*sine*.035+(idle and .045*math.sin(breath*.8) or 0))*entry.offset
 elseif group=="foot" then
  if mounted then return frame*turnAt(entry.pivot,walk*sine*entry.side*.1)*entry.offset end
  -- Legs swing from the hip under the skirt, not from the boot top.
  local swing=walk*.3*math.max(0,cosine*entry.side)
  return CFrame.new(0,lift+swing,0)*turnAt(entry.pivot+Vector3.new(0,.6,0),walk*sine*entry.side*.65)*entry.offset
 elseif group=="siege" then
  return entry.offset
 elseif group=="ram" then
  return CFrame.new(0,0,-attack*.9)*entry.offset
 elseif group=="catapult" then
  return turnAt(Vector3.new(0,2.5,0),-attack*.8)*entry.offset
 elseif group=="trebuchet" then
  return turnAt(Vector3.new(0,6.5,0),attack*1.2)*entry.offset
 end
 local lean=work and (workKind=="food" and .13 or .055)*(1-sine)*.5 or 0
 -- A walker tips slightly into its stride.
 if not mounted then lean-=walk*.09 end
 local body=frame*turnAt(Vector3.new(0,-.7,0),lean)
 if idle then
  local hip=Vector3.new(0,mounted and 2.4 or -.7,0)
  body=CFrame.new(hip)*CFrame.Angles(.03*math.sin(breath*1.3),0,.07*math.sin(breath))*CFrame.new(-hip)
 end
 if group=="torso" then return body*entry.offset end
 local angle=walk*sine*entry.side*(mounted and -.2 or -.45)
 if idle then angle=.12*math.sin(breath*1.3+entry.side) end
 local reach=0
 if work then
  if workKind=="food" then angle=-.3-(1-sine)*.14; reach=.16*(1-sine)
  elseif workKind=="wood" then angle=group=="right" and -.65+sine*.5 or -.18
  elseif workKind=="stone" or workKind=="gold" then angle=group=="right" and -.55+sine*.55 or -.15
  else angle=group=="right" and -.42+sine*.3 or -.18 end
 elseif attack>0 then
  if kind=="archer" or kind=="cavalryArcher" then angle=group=="right" and -.6-attack*.25 or -.75; reach=group=="right" and -attack*.35 or 0
  -- The hand gun stays levelled and kicks back with the shot.
  elseif kind=="handCannoneer" then angle=group=="right" and attack*.22 or -.5; reach=group=="right" and -attack*.6 or 0
  elseif kind=="skirmisher" then angle=group=="right" and -attack*.6 or -.18; reach=group=="right" and attack*.5 or 0
  -- The spear levels at the target; a rider leans the sword arm out past the horse's head.
  elseif kind=="spearman" then angle=group=="right" and -attack*1.3 or -.18; reach=group=="right" and attack*.5 or 0
  else angle=group=="right" and -attack*1.15 or -attack*.12; reach=group=="right" and attack*(mounted and 2.2 or .5) or 0 end
 end
 local shoulder=Vector3.new(entry.side*1.4,mounted and 4.3 or 1.2,0)
 return body*CFrame.new(0,0,-reach)*turnAt(shoulder,angle)*entry.offset
end

local moveParts,moveFrames={},{}
local function queueRest(model,item)
 local frame=item.root.CFrame
 for _,entry in ipairs(item.parts) do
  if entry.part.Parent then
   table.insert(moveParts,entry.part)
   table.insert(moveFrames,frame*entry.offset)
  end
 end
 for _,entry in ipairs(item.billboards) do if entry.gui.Parent then entry.gui.StudsOffsetWorldSpace=entry.offset end end
 item.wasActive=false
 item.poseDirty=true
 UnitView.Clear(model)
end
local function updateVisibility()
 local camera=workspace.CurrentCamera
 local candidates={}
 for model,item in pairs(tracked) do
  if model.Parent~=units or not item.root.Parent then untrack(model); continue end
  local visible,depth=false,math.huge
  if camera then
   local point=camera:WorldToViewportPoint(item.root.Position)
   local size=camera.ViewportSize
   -- A small margin avoids popping legs / weapons whose Root is just outside the image.
   visible=point.Z>0 and point.Z<1000 and point.X>=-40 and point.Y>=-40 and point.X<=size.X+40 and point.Y<=size.Y+40
   depth=point.Z
  end
  if visible then
   if not visibleUnits[model] then item.dirty=true; item.poseDirty=true end
   visibleUnits[model]=item
   table.insert(candidates,{item=item,depth=depth})
  elseif visibleUnits[model] then
   queueRest(model,item)
   visibleUnits[model]=nil
  end
 end
 -- All visible units keep continuous movement. Bound costly gait details in large crowds.
 table.sort(candidates,function(a,b) return a.depth<b.depth end)
 for index,candidate in ipairs(candidates) do
  local detail=index<=Motion.MaxDetailedUnits and candidate.depth<480
  if candidate.item.detailed~=detail then candidate.item.poseDirty=true end
  candidate.item.detailed=detail
 end
end
local poseElapsed,visibilityElapsed=0,Motion.VisibilityInterval
local renderConnection=RunService.RenderStepped:Connect(function(dt)
 poseElapsed+=dt
 visibilityElapsed+=dt
 local poseTick=poseElapsed>=Motion.PoseInterval
 local step=poseTick and math.min(poseElapsed,.1) or 0
 if poseTick then poseElapsed=0 end
 if visibilityElapsed>=Motion.VisibilityInterval then visibilityElapsed=0; updateVisibility() end
 local now=os.clock()
 local reduced=reducedMotion
 for part,item in pairs(projectiles) do
  if reduced then part:Destroy(); continue end
  local t=math.clamp((now-item.created)/item.duration,0,1)
  local point=item.start:Lerp(item.finish,t)+Vector3.new(0,4*item.arc*t*(1-t),0)
  local tangent=item.finish-item.start+Vector3.new(0,4*item.arc*(1-2*t),0)
  if tangent.Magnitude<.001 then tangent=item.finish-item.start end
  part.CFrame=CFrame.lookAt(point,point+tangent)
  for _,extra in ipairs(item.extras) do extra.part.CFrame=part.CFrame*extra.offset end
  if t>=1 then
   part:Destroy()
   impact(item.finish,item.color,item.siege)
  end
 end
 for model,item in pairs(visibleUnits) do
  if model.Parent~=units or not item.root.Parent then untrack(model); continue end
  local before,after,alpha=Motion.Sample(item.timeline,now)
  local frame=before==after and before or before:Lerp(after,alpha)
  local changed=frame~=item.viewFrame
  local observer=observers[model]
  local kind=observer and observer.kind
  -- Work must have produced a server pulse; failed / paused work returns to rest.
  local working=observer~=nil and observer.animation=="Work" and now-observer.lastWork<1.3
  if changed and not working then
   -- Steps are paid for in ground actually covered on screen, so feet do not slide.
   local travelled=frame.Position-item.viewFrame.Position
   item.phase=(item.phase+Motion.GaitAdvance(kind,math.sqrt(travelled.X*travelled.X+travelled.Z*travelled.Z)))%(math.pi*2)
  end
  item.viewFrame=frame
  UnitView.SetFrame(model,frame)
  local animation=observer and observer.animation
  -- Hold between replicated movement samples; blocked / idle units stop their gait.
  local walking=animation=="Walk" and now-item.lastMove<.2
  -- A melee swing peaks exactly when the server resolves the hit (Config.Combat.windup).
  local attackTime=(kind=="mangonel" or kind=="trebuchet") and .5 or 2*(Config.Combat.windup[kind] or Config.Combat.windup.default)
  local elapsed=observer and now-observer.lastAttack or math.huge
  -- LastAttack is the server fact: finish the swing even if the unit resumes walking the same step.
  local attack=elapsed<attackTime and math.sin(math.pi*elapsed/attackTime) or 0
  local detailed=not reduced and item.detailed
  if poseTick then
   item.gait=Motion.GaitBlend(item.gait,detailed and walking and not working,step)
   -- Work gestures have no ground travel to follow; they keep a steady clock.
   if detailed and working then item.phase=(item.phase+step*7)%(math.pi*2) end
  end
  local busy=detailed and (item.gait>0 or working or attack>0)
  -- Detailed units at rest keep a slow weight shift, refreshed at Motion.IdleInterval.
  local idleTick=false
  if busy then item.idleNext=0
  elseif detailed and now>=item.idleNext then
   item.idleNext=now+Motion.IdleInterval
   item.idleClock=now
   idleTick=true
  end
  local active=detailed
  local poseChanged=item.poseDirty or item.wasActive~=active or (busy and poseTick) or idleTick
  -- ReducedMotion removes gait and work gestures while preserving readable unit travel.
  -- Server replication can overwrite an appearance part: dirty rewrites it before drawing.
  if changed or item.dirty or poseChanged then
   -- Step in so the weapon reaches the target, then back; the Root never moves.
   local lunge=active and observer and observer.lunge*attack or 0
   if lunge>0 then frame*=CFrame.new(0,0,-lunge) end
   for _,entry in ipairs(item.parts) do
    if entry.part.Parent then
     if poseChanged then entry.localFrame=active and pose(entry,item,kind,item.gait,working,attack,observer and observer.workKind) or entry.offset end
     table.insert(moveParts,entry.part)
     table.insert(moveFrames,frame*(entry.localFrame or entry.offset))
    end
   end
   local offset=frame.Position-item.root.Position
   for _,entry in ipairs(item.billboards) do if entry.gui.Parent then entry.gui.StudsOffsetWorldSpace=entry.offset+offset end end
  end
  item.wasActive=active
  item.dirty,item.poseDirty=false,false
 end
 -- Every frame, including units outside the detailed set.
 for model,bar in pairs(healthBars) do
  if bar.anchor and model.Parent==units then bar.anchor.Position=UnitView.GetFrame(model).Position end
 end
 -- One engine batch, only appearance parts. Never PivotTo / BulkMoveTo an authoritative Root.
 diagnostics.partWrites=#moveParts
 diagnostics.totalPartWrites+=#moveParts
 if #moveParts>0 then workspace:BulkMoveTo(moveParts,moveFrames,Enum.BulkMoveMode.FireCFrameChanged) end
 table.clear(moveParts); table.clear(moveFrames)
end)
local reducedConnection=player:GetAttributeChangedSignal("ReducedMotion"):Connect(function()
 reducedMotion=player:GetAttribute("ReducedMotion")==true
 if not reducedMotion then return end
 for effect,moving in pairs(effectKinds) do if moving then effect:Destroy() end end
end)
if RunService:IsStudio() then
 -- Read the real LocalScript's cache; Command Bar ModuleScript require caches are separate.
 motionProbe=Instance.new("BindableFunction")
 motionProbe.Name="RTSMotionProbe"
 motionProbe.OnInvoke=function(model)
  local count,visible,details=0,0,0
  for _ in pairs(tracked) do count+=1 end
  for _,item in pairs(visibleUnits) do visible+=1; if item.detailed then details+=1 end end
  local result={ready=script:GetAttribute("RTSMotionReady")==true,
   stats={tracked=count,visible=visible,detailed=details,rootSamples=diagnostics.rootSamples,
    partWrites=diagnostics.partWrites,totalPartWrites=diagnostics.totalPartWrites,
    delay=Motion.Delay,maxSamples=Motion.MaxSamples,maxDetailed=Motion.MaxDetailedUnits}}
  if typeof(model)=="Instance" and model:IsA("Model") then
   local item=tracked[model]
   result.tracked=item~=nil
   result.visible=visibleUnits[model]~=nil
   result.root=model.PrimaryPart
   result.frame=UnitView.GetFrame(model)
   if item then
    result.sampleCount=#item.timeline.samples
    for _,entry in ipairs(item.parts) do
     if entry.part.Name=="Body" then result.body=entry.part; result.bodyOffset=entry.offset; break end
    end
   end
  end
  return result
 end
 motionProbe.Parent=script.Parent
end
script:SetAttribute("RTSMotionReady",true)
script.Destroying:Once(function()
 renderConnection:Disconnect()
 reducedConnection:Disconnect()
 for _,connection in ipairs(folderConnections) do connection:Disconnect() end
 for model in pairs(observers) do untrack(model) end
 for model in pairs(healthBars) do hideHealth(model) end
 anchors:Destroy()
 if motionProbe then motionProbe:Destroy() end
 effects:Destroy()
end)
