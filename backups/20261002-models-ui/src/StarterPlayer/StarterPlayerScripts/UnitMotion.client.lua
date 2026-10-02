-- Continuous local presentation. Roots, hitboxes, orders and damage stay server authoritative.
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
local Motion=require(game.ReplicatedStorage.Shared.MotionRules)
local UnitView=require(game.ReplicatedStorage.Shared.ClientUnitView)
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
local MAX_EFFECTS=40
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
local function attackEffect(model)
 if player:GetAttribute("ReducedMotion")==true or activeEffects>=MAX_EFFECTS then return end
 local root,target=model.PrimaryPart,model:GetAttribute("AttackPosition")
 local unitKind,buildingKind=model:GetAttribute("UnitType"),model:GetAttribute("BuildingType")
 local data=Config.Units[unitKind] or Config.Buildings[buildingKind]
 if not data or not root or not finitePosition(target) or not onScreen(root.Position) then return end
 local siege=unitKind=="mangonel" or unitKind=="trebuchet"
 local sourceFrame=unitKind and UnitView.GetFrame(model) or root.CFrame
 local start=sourceFrame.Position+Vector3.new(0,unitKind and (siege and 3 or 1.5) or root.Size.Y*.35,0)
 local finish=target+Vector3.new(0,2,0)
 local direction=finish-start
 if direction.Magnitude<.1 then return end
 if (data.range or 0)<=20 then
  impact(finish,Color3.fromRGB(236,196,135),false)
  return
 end
 local javelin=unitKind=="skirmisher"
 local name=siege and "StoneEffect" or javelin and "JavelinEffect" or "ArrowEffect"
 local size=siege and Vector3.new(1.3,1.3,1.3) or Vector3.new(.14,.14,javelin and 3.2 or 1.8)
 local color=siege and Color3.fromRGB(165,162,145) or Color3.fromRGB(231,199,134)
 local part=effectPart(name,size,color,siege and Enum.Material.Slate or Enum.Material.SmoothPlastic)
 if siege then part.Shape=Enum.PartType.Ball end
 part.CFrame=CFrame.lookAt(start,finish)
 -- Cosmetic travel begins after the authoritative hit; it never delays or applies damage.
 local duration=siege and .5 or .2
 if not keepEffect(part,true,duration+.1) then return end
 projectiles[part]={start=start,finish=finish,created=os.clock(),duration=duration,
  arc=siege and math.min(18,direction.Magnitude*.16) or javelin and 3 or 0,color=color,siege=siege}
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
 Spear="right",Spearhead="right",Bow="right",Bowstring="right",Staff="right",StaffHead="right",
 ArmL="left",Shield="left",
 Body="torso",Belt="torso",Tabard="torso",Head="torso",Hat="torso",HatBand="torso",Quiver="torso",Robe="torso",
 HorseBody="horse",Saddle="horse",HorseCloth="horse",HorseHead="horse",HorseNeck="horse",Mane="horse",
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
    rootFrame=frame,viewFrame=frame,phase=0,lastMove=-math.huge,wasActive=false,dirty=true,poseDirty=true}
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
 local observer=observers[model]
 if not observer then return end
 observers[model]=nil
 for _,connection in ipairs(observer.connections) do connection:Disconnect() end
end
local function track(model)
 if not model:IsA("Model") or observers[model] then return end
 local observer={pending=false,connections={},lastAttack=-math.huge,lastWork=-math.huge,lastWorkEffect=-math.huge,
  lastDamage=-math.huge,hp=model:GetAttribute("HP"),complete=model:GetAttribute("Complete")}
 observers[model]=observer
 local function connect(signal,callback)
  table.insert(observer.connections,signal:Connect(callback))
 end
 connect(model:GetAttributeChangedSignal("LastAttack"),function()
  observer.lastAttack=os.clock()
  -- Attribute replication can arrive in one batch; read the matching position after that batch.
  task.defer(function() if observers[model]==observer then attackEffect(model) end end)
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
 local sine=math.sin(phase)
 local mounted=kind=="cavalry" or kind=="scout"
 local lift=walk and (mounted and .1 or .06)*math.abs(sine) or 0
 local frame=CFrame.new(0,lift,0)
 if group=="wheel" then
  return walk and CFrame.new(entry.offset.Position)*CFrame.Angles(phase,0,0)*entry.offset.Rotation or entry.offset
 elseif group=="horseLeg" then
  local gait=math.sin(phase+(entry.side*entry.front<0 and math.pi or 0))
  return frame*turnAt(entry.pivot,walk and gait*.45 or 0)*entry.offset
 elseif group=="horse" then
  local nod=walk and sine*.035 or 0
  return frame*turnAt(Vector3.new(0,1,-2),nod)*entry.offset
 elseif group=="foot" then
  local stride=walk and sine*entry.side*(mounted and .1 or .35) or 0
  return frame*turnAt(entry.pivot,stride)*entry.offset
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
 local body=frame*turnAt(Vector3.new(0,-.7,0),lean)
 if group=="torso" then return body*entry.offset end
 local angle=walk and sine*entry.side*-.2 or 0
 local reach=0
 if work then
  if workKind=="food" then angle=-.3-(1-sine)*.14; reach=.16*(1-sine)
  elseif workKind=="wood" then angle=group=="right" and -.65+sine*.5 or -.18
  elseif workKind=="stone" or workKind=="gold" then angle=group=="right" and -.55+sine*.55 or -.15
  else angle=group=="right" and -.42+sine*.3 or -.18 end
 elseif attack>0 then
  if kind=="archer" then angle=group=="right" and -.6-attack*.25 or -.75; reach=group=="right" and -attack*.35 or 0
  elseif kind=="spearman" or kind=="skirmisher" then angle=group=="right" and -attack*.6 or -.18; reach=group=="right" and attack*.5 or 0
  else angle=group=="right" and -attack*1.15 or -attack*.12 end
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
  item.viewFrame=frame
  UnitView.SetFrame(model,frame)
  local observer=observers[model]
  local animation=observer and observer.animation
  -- Hold between replicated movement samples; blocked / idle units stop their gait.
  local walking=animation=="Walk" and now-item.lastMove<.2
  -- Work must have produced a server pulse; failed / paused work returns to rest.
  local working=animation=="Work" and observer~=nil and now-observer.lastWork<1.3
  local kind=observer and observer.kind
  local attackTime=(kind=="mangonel" or kind=="trebuchet" or kind=="ram") and .5 or .3
  local elapsed=observer and now-observer.lastAttack or math.huge
  local attack=animation=="Attack" and elapsed<attackTime and math.sin(math.pi*elapsed/attackTime) or 0
  local active=not reduced and item.detailed and (walking or working or attack>0)
  if active and poseTick then
   local speed=observer and observer.speed
   local rate=walking and (finite(speed) and math.clamp(speed/2.4,3,12) or 6) or 7
   if kind=="ram" or kind=="mangonel" or kind=="trebuchet" then rate=walking and (finite(speed) and speed/1.6 or 6) or 7 end
   item.phase=(item.phase+step*rate)%(math.pi*2)
  end
  local poseChanged=item.poseDirty or item.wasActive~=active or (active and poseTick)
  -- ReducedMotion removes gait and work gestures while preserving readable unit travel.
  -- Server replication can overwrite an appearance part: dirty rewrites it before drawing.
  if changed or item.dirty or poseChanged then
   for _,entry in ipairs(item.parts) do
    if entry.part.Parent then
     if poseChanged then entry.localFrame=active and pose(entry,item,kind,walking,working,attack,observer and observer.workKind) or entry.offset end
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
 if motionProbe then motionProbe:Destroy() end
 effects:Destroy()
end)
