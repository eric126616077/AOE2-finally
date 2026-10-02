-- Client cosmetic overlays only. Footprints and the original model geometry stay
-- authoritative; user model templates are neither replaced nor transformed.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local RS=game:GetService("ReplicatedStorage")
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("ConstructionVisualRules"))
local Damage=require(RS:WaitForChild("Shared"):WaitForChild("DamageVisualRules"))
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
-- 整排放置的牆段數量多：不顯示鷹架、進度條與完工標示，只保留由下而上的顯現。
local function quiet(model)
 local data=Config.Buildings[model:GetAttribute("BuildingType")]
 return data~=nil and data.line==true
end
local player=Players.LocalPlayer
if script:GetAttribute("Initialized")==true or player:GetAttribute("RTSBuildingVisualsReady")==true then return end
script:SetAttribute("Initialized",true)
local tracked,sites,folders,connections={},{},{},{}
local effects=Instance.new("Folder")
effects.Name="RTSConstructionEffects"
effects.Parent=workspace
local damageEffects=Instance.new("Folder")
damageEffects.Name="RTSDamageEffects"
damageEffects.Parent=workspace
local damageOverlays,damageFires=0,0
local completionCount=0
local completionEffects={}
local visibleSites=0
local destroyed=false
local function inView(root)
 local camera=workspace.CurrentCamera
 if not root or not camera then return false end
 local point,visible=camera:WorldToViewportPoint(root.Position)
 return visible and point.Z>0 and (camera.CFrame.Position-root.Position).Magnitude<=Rules.MaxDistance
end
local function cosmetic(name,size,frame,color,material,parent)
 local part=Instance.new("Part")
 part.Name,part.Size,part.CFrame=name,size,frame
 part.Color,part.Material=color,material or Enum.Material.Wood
 part.Anchored,part.CanCollide,part.CanQuery,part.CanTouch=true,false,false,false
 part.CastShadow=false
 part.TopSurface,part.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
 part.Parent=parent
 return part
end
local function destroyOverlay(observer)
 if observer.overlay then observer.overlay:Destroy(); observer.overlay=nil; visibleSites-=1 end
 observer.label,observer.bar,observer.scaffold=nil,nil,nil
 observer.scaffoldVisible,observer.stage=nil,nil
end
local function cancelTween(entry)
 if entry.tween then entry.tween:Cancel(); entry.tween=nil end
end
local function setRevealed(entry,reveal,animate)
 if entry.revealed==reveal then return end
 entry.revealed=reveal
 cancelTween(entry)
 local value=reveal and entry.original or 1
 if animate and reveal and player:GetAttribute("ReducedMotion")~=true then
  entry.tween=TweenService:Create(entry.part,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{LocalTransparencyModifier=value})
  entry.tween:Play()
 else entry.part.LocalTransparencyModifier=value end
end
local function restore(observer)
 for part,entry in pairs(observer.parts) do
  cancelTween(entry)
  if part.Parent then part.LocalTransparencyModifier=entry.original end
 end
 table.clear(observer.parts)
end
-- Imported models need no metadata: ground detail, walls, then roof/top follow
-- height; all original appearances return unchanged when complete or repaired.
local function partStage(root,part)
 local height=math.max(root.Size.Y,1)
 local relative=root.CFrame:PointToObjectSpace(part.Position)
 local ratio=math.clamp((relative.Y+height/2)/height,0,1)
 local stage=part:GetAttribute("ConstructionStage")
 if type(stage)~="number" then stage=ratio<=.08 and 0 or ratio<.58 and 1 or 3 end
 return stage,ratio,relative
end
local function cachePart(model,observer,part)
 if not part:IsA("BasePart") or part==model.PrimaryPart or part.Name=="Footprint" or part.Transparency>=1 or observer.parts[part] then return end
 local root=model.PrimaryPart
 if not root then return end
 local stage,ratio=partStage(root,part)
 local entry={part=part,original=part.LocalTransparencyModifier,threshold=Rules.RevealAt(stage,ratio)}
 observer.parts[part]=entry
 setRevealed(entry,Rules.Progress(model:GetAttribute("ConstructionProgress"))>=entry.threshold,false)
end
local function overlay(model,observer)
 local root=model.PrimaryPart
 if not root or observer.overlay or visibleSites>=Rules.MaxVisibleSites then return end
 local site=Instance.new("Model")
 site.Name="Construction_"..model.Name
 observer.overlay=site
 visibleSites+=1
 local frame=root.CFrame*CFrame.new(0,-root.Size.Y/2,0)
 local w,d,h=root.Size.X,root.Size.Z,math.min(root.Size.Y*.78,22)
 local timber=Color3.fromRGB(132,96,58)
 cosmetic("SiteFoundation",Vector3.new(w,.22,d),frame*CFrame.new(0,.16,0),Color3.fromRGB(142,126,97),Enum.Material.Ground,site)
 for _,x in ipairs({-w/2,w/2}) do
  for _,z in ipairs({-d/2,d/2}) do cosmetic("SurveyStake",Vector3.new(.45,1.8,.45),frame*CFrame.new(x,1,z),timber,nil,site) end
 end
 local scaffold=Instance.new("Model")
 scaffold.Name="Scaffold"
 scaffold.Parent=site
 observer.scaffold=scaffold
 for _,x in ipairs({-w/2,w/2}) do
  for _,z in ipairs({-d/2,d/2}) do cosmetic("Post",Vector3.new(.55,h,.55),frame*CFrame.new(x,h/2,z),timber,nil,scaffold) end
 end
 for _,y in ipairs({h*.45,h*.9}) do
  for _,z in ipairs({-d/2,d/2}) do cosmetic("Crossbeam",Vector3.new(w+.7,.45,.5),frame*CFrame.new(0,y,z),timber,nil,scaffold) end
  for _,x in ipairs({-w/2,w/2}) do cosmetic("Crossbeam",Vector3.new(.5,.45,d+.7),frame*CFrame.new(x,y,0),timber,nil,scaffold) end
 end
 -- One work platform, rather than dozens of small decorative planks.
 cosmetic("WorkPlatform",Vector3.new(w+1,.22,1.3),frame*CFrame.new(0,h*.45,d/2),timber,Enum.Material.WoodPlanks,scaffold)
 cosmetic("LumberSupply",Vector3.new(math.min(w*.45,7),.75,2),frame*CFrame.new(-w*.2,.8,d*.25),timber,Enum.Material.WoodPlanks,site)
 local billboard=Instance.new("BillboardGui")
 billboard.Name="ConstructionProgress"
 billboard.Adornee=root
 billboard.Size=UDim2.fromOffset(174,42)
 billboard.StudsOffsetWorldSpace=Vector3.new(0,root.Size.Y/2+3,0)
 billboard.MaxDistance=Rules.MaxDistance
 billboard.AlwaysOnTop=false
 billboard.Active=false
 billboard.Parent=site
 local background=Instance.new("Frame")
 background.Name="Status"
 background.Size=UDim2.fromScale(1,1)
 background.BackgroundColor3=Color3.fromRGB(31,30,26)
 background.BackgroundTransparency=.12
 background.BorderSizePixel=0
 background.Parent=billboard
 local corner=Instance.new("UICorner")
 corner.CornerRadius=UDim.new(0,4)
 corner.Parent=background
 local label=Instance.new("TextLabel")
 label.Name="StageLabel"
 label.Size=UDim2.new(1,-8,0,27)
 label.Position=UDim2.fromOffset(4,1)
 label.BackgroundTransparency=1
 label.Font=Enum.Font.SourceSansSemibold
 label.TextSize=16
 label.TextColor3=Color3.fromRGB(241,225,189)
 label.Parent=background
 observer.label=label
 local track=Instance.new("Frame")
 track.Name="ProgressTrack"
 track.Size=UDim2.new(1,-12,0,5)
 track.Position=UDim2.fromOffset(6,32)
 track.BackgroundColor3=Color3.fromRGB(76,66,49)
 track.BorderSizePixel=0
 track.Parent=background
 local bar=Instance.new("Frame")
 bar.Name="ProgressBar"
 bar.BackgroundColor3=Color3.fromRGB(212,175,103)
 bar.BorderSizePixel=0
 bar.Parent=track
 observer.bar=bar
 site.Parent=effects
end
local stageNames={[0]="整地與地基",[1]="架設鷹架",[2]="砌牆施工",[3]="屋頂與裝修"}
local function updateOverlay(model,observer)
 if not observer.overlay then return end
 local progress=Rules.Progress(model:GetAttribute("ConstructionProgress"))
 local stage=Rules.Stage(progress)
 local waiting=(model:GetAttribute("BuilderCount") or 0)<=0
 observer.label.Text=(waiting and "等待村民" or stageNames[stage] or "施工中").."  "..math.floor(progress*100).."%"
 observer.label.TextColor3=waiting and Color3.fromRGB(226,166,115) or Color3.fromRGB(241,225,189)
 observer.bar.Size=UDim2.fromScale(progress,1)
 local scaffoldVisible=stage>=1
 if observer.scaffoldVisible~=scaffoldVisible then
  observer.scaffoldVisible=scaffoldVisible
  for _,part in ipairs(observer.scaffold:GetChildren()) do part.Transparency=scaffoldVisible and (stage==3 and .35 or 0) or 1 end
 elseif scaffoldVisible and observer.stage~=stage then
  for _,part in ipairs(observer.scaffold:GetChildren()) do part.Transparency=stage==3 and .35 or 0 end
 end
 observer.stage=stage
end
local function completion(model)
 local root=model.PrimaryPart
 if not inView(root) or completionCount>=Rules.MaxCompletionEffects or workspace:GetAttribute("MatchPhase")~="Playing" then return end
 local sign=Instance.new("BillboardGui")
 sign.Name="ConstructionComplete"
 sign.Adornee=root
 sign.Size=UDim2.fromOffset(164,28)
 sign.StudsOffsetWorldSpace=Vector3.new(0,root.Size.Y/2+3,0)
 sign.MaxDistance=Rules.MaxDistance
 sign.AlwaysOnTop=false
 sign.Active=false
 local label=Instance.new("TextLabel")
 label.Name="CompleteLabel"
 label.Size=UDim2.fromScale(1,1)
 label.BackgroundColor3=Color3.fromRGB(46,70,40)
 label.BackgroundTransparency=.12
 label.Text="✓ 建築已完工"
 label.TextColor3=Color3.fromRGB(225,239,187)
 label.TextSize=18
 label.Font=Enum.Font.SourceSansSemibold
 label.Parent=sign
 sign.Parent=effects
 completionCount+=1
 completionEffects[sign]=true
 sign.Destroying:Once(function() completionCount-=1; completionEffects[sign]=nil end)
 if player:GetAttribute("ReducedMotion")~=true then
  TweenService:Create(sign,TweenInfo.new(1.6,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{StudsOffsetWorldSpace=sign.StudsOffsetWorldSpace+Vector3.new(0,1.5,0)}):Play()
 end
 task.delay(1.8,function() if sign.Parent then sign:Destroy() end end)
end
-- Portcullis: every "GateDoor" part rises into the gatehouse while the server reports GateOpen.
-- Purely cosmetic; who may pass is decided on the server.
local function gateDoors(model,observer,animate)
 local root=model.PrimaryPart
 if tracked[model]~=observer or not root then return end
 local open=model:GetAttribute("GateOpen")==true
 local raise=Vector3.new(0,root.Size.Y*5/16,0)
 observer.gateBase=observer.gateBase or {}
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and part.Name=="GateDoor" then
   local base=observer.gateBase[part] or part.CFrame
   observer.gateBase[part]=base
   local goal=open and base+raise or base
   if animate and player:GetAttribute("ReducedMotion")~=true and inView(root) then
    TweenService:Create(part,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{CFrame=goal}):Play()
   else part.CFrame=goal end
  end
 end
end
-- Damage states of a completed building: at half health part of the roof and trim breaks away,
-- the rest is sooted, rubble lies around it and a fire starts; at a third the holes, soot,
-- rubble and fires grow. Everything is local and returns to the original look when repaired.
local charcoal=Color3.fromRGB(38,34,31)
local function restoreDamagedPart(part,entry)
 if entry.hidden then part.LocalTransparencyModifier=entry.original
 elseif entry.soot and part.Color==entry.soot then part.Color=entry.color end
end
local function clearDamage(observer)
 local parts=observer.damageParts
 if parts then
  observer.damageParts=nil
  for part,entry in pairs(parts) do restoreDamagedPart(part,entry) end
 end
 if observer.damageOverlay then
  observer.damageOverlay:Destroy()
  observer.damageOverlay=nil
  damageOverlays-=1
  damageFires-=observer.damageFires
  observer.damageFires=0
 end
end
local function blaze(site,position,scale,heavy)
 local holder=cosmetic("Blaze",Vector3.new(scale,.2,scale),CFrame.new(position),charcoal,nil,site)
 holder.Transparency=1
 local flame=Instance.new("ParticleEmitter")
 flame.Name="Flame"
 flame.Texture="rbxasset://textures/particles/fire_main.dds"
 flame.Color=ColorSequence.new(Color3.fromRGB(255,196,92),Color3.fromRGB(214,72,30))
 flame.Size=NumberSequence.new(scale*1.3,scale*.4)
 flame.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.6,.3),NumberSequenceKeypoint.new(1,1)})
 flame.Lifetime=NumberRange.new(.8,1.4)
 flame.Rate=heavy and 22 or 12
 flame.Speed=NumberRange.new(scale*1.4,scale*2.2)
 flame.SpreadAngle=Vector2.new(14,14)
 flame.EmissionDirection=Enum.NormalId.Top
 flame.Rotation=NumberRange.new(0,360)
 flame.LightEmission,flame.LightInfluence=.6,0
 flame.Parent=holder
 local smoke=Instance.new("ParticleEmitter")
 smoke.Name="Smoke"
 smoke.Texture="rbxasset://textures/particles/smoke_main.dds"
 smoke.Color=ColorSequence.new(Color3.fromRGB(48,45,42),Color3.fromRGB(110,106,100))
 smoke.Size=NumberSequence.new(scale*1.2,scale*3.2)
 smoke.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(.6,.6),NumberSequenceKeypoint.new(1,1)})
 smoke.Lifetime=NumberRange.new(3,4.5)
 smoke.Rate=heavy and 7 or 4
 smoke.Speed=NumberRange.new(3,4.5)
 smoke.SpreadAngle=Vector2.new(12,12)
 smoke.EmissionDirection=Enum.NormalId.Top
 smoke.Rotation=NumberRange.new(0,360)
 smoke.RotSpeed=NumberRange.new(-20,20)
 smoke.LightEmission,smoke.LightInfluence=0,1
 smoke.Parent=holder
 return holder,smoke
end
local function damageOverlay(model,observer,stage,spots,worsened)
 if damageOverlays>=Damage.MaxOverlays then return end
 local root=model.PrimaryPart
 local line=quiet(model)
 local site=Instance.new("Model")
 site.Name="Damage_"..model.Name
 observer.damageOverlay,observer.damageFires=site,0
 damageOverlays+=1
 local frame=root.CFrame*CFrame.new(0,-root.Size.Y/2,0)
 local w,d,h=root.Size.X,root.Size.Z,root.Size.Y
 local seed=math.floor(Damage.Rank(root.Position.X,0,root.Position.Z)*997)
 local grain=math.clamp(math.min(w,d)/10,.6,1.6)
 -- The stage 1 pieces keep their place at stage 2; later indices only add to them.
 for index=1,Damage.Rubble(stage,line) do
  local along,size,spin=Damage.Rank(index,seed,1),Damage.Rank(index,seed,2),Damage.Rank(index,seed,3)
  local side=index%2==0 and 1 or -1
  local edge=(.8+1.3*size)*grain
  local x,z
  if index%4<2 then x,z=(along-.5)*w,side*(d/2+.5*grain) else x,z=side*(w/2+.5*grain),(along-.5)*d end
  local charred=index%3==0
  cosmetic("Rubble",Vector3.new(edge,edge*.55,edge*(.6+.5*spin)),frame*CFrame.new(x,edge*.22,z)*CFrame.Angles(0,spin*math.pi*2,(size-.5)*.5),
   charred and charcoal or Color3.fromRGB(150,144,132),charred and Enum.Material.Wood or Enum.Material.Slate,site)
 end
 if stage>=2 and not line then
  for _,side in ipairs({-1,1}) do
   local foot=frame*Vector3.new(side*w*.28,0,side*(d/2+1.2*grain))
   local top=frame*Vector3.new(side*w*.18,h*.42,side*d*.42)
   cosmetic("CharredBeam",Vector3.new(.5*grain,.5*grain,(top-foot).Magnitude),CFrame.lookAt((foot+top)/2,top),charcoal,nil,site)
  end
 end
 local puff
 if player:GetAttribute("ReducedMotion")~=true then
  local scale=math.clamp(math.min(w,d)*.22,2,5)
  for index=1,Damage.Fires(stage,line) do
   if damageFires>=Damage.MaxFires then break end
   -- Burn where a roof piece fell; a model with nothing to lose burns on its upper part.
   local position=spots[index] and spots[index]+Vector3.new(0,1,0) or frame*Vector3.new((Damage.Rank(index,seed,4)-.5)*w*.6,h*.7,(Damage.Rank(index,seed,5)-.5)*d*.6)
   local holder,smoke=blaze(site,position,scale,stage>=2)
   if index==1 then
    puff=smoke
    if stage>=2 then
     local glow=Instance.new("PointLight")
     glow.Color,glow.Range,glow.Brightness,glow.Shadows=Color3.fromRGB(255,150,70),16,1,false
     glow.Parent=holder
    end
   end
   observer.damageFires+=1
   damageFires+=1
  end
 end
 site.Parent=damageEffects
 if puff and worsened and inView(root) then puff:Emit(8) end
end
local function applyDamage(model,observer,stage,worsened)
 local root=model.PrimaryPart
 local parts,roof,trim={}, {}, {}
 observer.damageParts=parts
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and part~=root and part.Name~="Footprint" and part.Transparency<1 then
   local constructionStage,_,relative=partStage(root,part)
   local entry={rank=Damage.Rank(relative.X,relative.Y,relative.Z)}
   parts[part]=entry
   -- Owner colors (with the pole that carries them) and the gate leaf stay readable in every state.
   if part:GetAttribute("TeamColorPart")==true or part.Name=="GateDoor" or part.Name=="Flagpole" then entry.keep=true
   elseif constructionStage==3 then table.insert(roof,part)
   elseif constructionStage==2 then table.insert(trim,part) end
  end
 end
 local spots={}
 for _,group in ipairs({roof,trim}) do
  table.sort(group,function(a,b) return parts[a].rank<parts[b].rank end)
  for index=1,Damage.HideCount(stage,group==roof and 3 or 2,#group) do
   local part=group[index]
   local entry=parts[part]
   entry.hidden,entry.original=true,part.LocalTransparencyModifier
   part.LocalTransparencyModifier=1
   table.insert(spots,part.Position)
  end
 end
 for part,entry in pairs(parts) do
  if not entry.hidden and not entry.keep then
   entry.color=part.Color
   part.Color=entry.color:Lerp(charcoal,Damage.Soot(stage,entry.rank))
   -- Read back the stored value, so a later server recolor is recognised and left alone.
   entry.soot=part.Color
  end
 end
 damageOverlay(model,observer,stage,spots,worsened)
end
local function refreshDamage(model,observer,constructing)
 local stage=0
 if not constructing and model.PrimaryPart then
  stage=Damage.Stage(model:GetAttribute("HP"),model:GetAttribute("MaxHP"),observer.damageStage)
 end
 if stage==observer.damageStage and not observer.damageDirty then return end
 local worsened=observer.hadUpdate and stage>observer.damageStage
 clearDamage(observer)
 observer.damageStage,observer.damageDirty=stage,false
 if stage>0 then applyDamage(model,observer,stage,worsened) end
end
local function update(model,observer)
 if tracked[model]~=observer then return end
 local constructing=model:GetAttribute("UnderConstruction")==true or model:GetAttribute("Complete")==false
 if constructing then
  refreshDamage(model,observer,true)
  if not observer.constructing then
   observer.constructing=true
   for _,part in ipairs(model:GetDescendants()) do cachePart(model,observer,part) end
  end
  sites[model]=observer
  local progress=Rules.Progress(model:GetAttribute("ConstructionProgress"))
  local animate=observer.hadUpdate and inView(model.PrimaryPart)
  for part,entry in pairs(observer.parts) do
   if part.Parent then setRevealed(entry,progress>=entry.threshold,animate) end
  end
  if observer.overlay then updateOverlay(model,observer) end
 else
  if observer.constructing then
   restore(observer); destroyOverlay(observer)
   if not quiet(model) then completion(model) end
  end
  observer.constructing=false
  sites[model]=nil
  refreshDamage(model,observer,false)
 end
 observer.hadUpdate=true
end
local function schedule(model,observer)
 if observer.pending then return end
 observer.pending=true
 task.defer(function()
  observer.pending=false
  if not destroyed then update(model,observer) end
 end)
end
local function untrack(model)
 local observer=tracked[model]
 if not observer then return end
 tracked[model],sites[model]=nil,nil
 for _,connection in ipairs(observer.connections) do connection:Disconnect() end
 restore(observer)
 destroyOverlay(observer)
 clearDamage(observer)
end
local function track(model)
 if not model:IsA("Model") or tracked[model] then return end
 local observer={parts={},connections={},hadUpdate=false,damageStage=0,damageFires=0}
 tracked[model]=observer
 for _,attribute in ipairs({"Complete","UnderConstruction","ConstructionProgress","BuilderCount","HP","MaxHP"}) do
  table.insert(observer.connections,model:GetAttributeChangedSignal(attribute):Connect(function() schedule(model,observer) end))
 end
 table.insert(observer.connections,model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
  destroyOverlay(observer)
  if observer.constructing then
   restore(observer)
   for _,part in ipairs(model:GetDescendants()) do cachePart(model,observer,part) end
  end
  observer.damageDirty=true
  schedule(model,observer)
 end))
 table.insert(observer.connections,model.DescendantAdded:Connect(function(part)
  if observer.constructing then cachePart(model,observer,part) end
  -- Late replicated parts and a re-staged farm take the current damage state in one deferred pass.
  if observer.damageStage>0 and part:IsA("BasePart") then observer.damageDirty=true; schedule(model,observer) end
  if part.Name=="GateDoor" and model:GetAttribute("GateOpen")==true then task.defer(gateDoors,model,observer,false) end
 end))
 if model:GetAttribute("BuildingType")=="Gate" then
  table.insert(observer.connections,model:GetAttributeChangedSignal("GateOpen"):Connect(function() gateDoors(model,observer,true) end))
  gateDoors(model,observer,false)
 end
 table.insert(observer.connections,model.DescendantRemoving:Connect(function(part)
  local entry=observer.parts[part]
  if entry then cancelTween(entry); part.LocalTransparencyModifier=entry.original; observer.parts[part]=nil end
  local damaged=observer.damageParts and observer.damageParts[part]
  if damaged then
   restoreDamagedPart(part,damaged)
   observer.damageParts[part]=nil
   observer.damageDirty=true
   schedule(model,observer)
  end
 end))
 update(model,observer)
end
local function attach(folder)
 if folder.Name~="Buildings" or folders[folder] then return end
 folders[folder]={folder.ChildAdded:Connect(track),folder.ChildRemoved:Connect(untrack)}
 for _,model in ipairs(folder:GetChildren()) do track(model) end
end
local function detach(folder)
 local bindings=folders[folder]
 if not bindings then return end
 folders[folder]=nil
 for _,connection in ipairs(bindings) do connection:Disconnect() end
 for _,model in ipairs(folder:GetChildren()) do untrack(model) end
end
table.insert(connections,workspace.ChildAdded:Connect(attach))
table.insert(connections,workspace.ChildRemoved:Connect(detach))
local folder=workspace:FindFirstChild("Buildings")
if folder then attach(folder) end
local elapsed=0
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt
 if elapsed<Rules.UpdateInterval then return end
 elapsed=0
 -- Only active construction sites are visited, four times a second. Completed
 -- buildings and resources never take part in this camera visibility pass.
 for model,observer in pairs(sites) do
  if workspace:GetAttribute("MatchPhase")=="Playing" and inView(model.PrimaryPart) then
   if not observer.overlay and not quiet(model) then overlay(model,observer); updateOverlay(model,observer) end
  else destroyOverlay(observer) end
 end
end))
table.insert(connections,player:GetAttributeChangedSignal("ReducedMotion"):Connect(function()
 -- Fire and smoke are motion: rebuild damaged buildings with or without them.
 for model,observer in pairs(tracked) do
  if observer.damageStage>0 then observer.damageDirty=true; schedule(model,observer) end
 end
 if player:GetAttribute("ReducedMotion")~=true then return end
 for _,observer in pairs(sites) do
  for _,entry in pairs(observer.parts) do
   cancelTween(entry)
   if entry.part.Parent then entry.part.LocalTransparencyModifier=entry.revealed and entry.original or 1 end
  end
 end
 for sign in pairs(completionEffects) do sign:Destroy() end
end))
table.insert(connections,workspace:GetAttributeChangedSignal("MatchPhase"):Connect(function()
 if workspace:GetAttribute("MatchPhase")=="Playing" then return end
 for _,observer in pairs(sites) do destroyOverlay(observer) end
 for sign in pairs(completionEffects) do sign:Destroy() end
end))
local probe
if RunService:IsStudio() then
 probe=Instance.new("BindableFunction")
 probe.Name="RTSConstructionVisualProbe"
 probe.OnInvoke=function(model)
  local active,hidden=0,0
  for _,observer in pairs(sites) do
   active+=1
   for _,entry in pairs(observer.parts) do if not entry.revealed then hidden+=1 end end
  end
  local result={activeSites=active,visibleSites=visibleSites,hiddenParts=hidden,completionEffects=completionCount,maxVisibleSites=Rules.MaxVisibleSites}
  local observer=typeof(model)=="Instance" and tracked[model]
  if observer then
   local partCount,hiddenCount=0,0
   for _,entry in pairs(observer.parts) do partCount+=1; if not entry.revealed then hiddenCount+=1 end end
   result.site={constructing=observer.constructing==true,progress=Rules.Progress(model:GetAttribute("ConstructionProgress")),
    stage=Rules.Stage(model:GetAttribute("ConstructionProgress")),parts=partCount,hiddenParts=hiddenCount,
    overlay=observer.overlay~=nil,scaffoldVisible=observer.scaffoldVisible==true,
    label=observer.label and observer.label.Text or nil}
   local damagedParts,brokenParts,sootedParts=0,0,0
   for _,entry in pairs(observer.damageParts or {}) do
    damagedParts+=1
    if entry.hidden then brokenParts+=1 elseif entry.soot then sootedParts+=1 end
   end
   result.damage={stage=observer.damageStage,parts=damagedParts,brokenParts=brokenParts,sootedParts=sootedParts,
    overlay=observer.damageOverlay~=nil,fires=observer.damageFires,
    effectParts=observer.damageOverlay and #observer.damageOverlay:GetChildren() or 0}
  end
  result.damageOverlays,result.damageFires=damageOverlays,damageFires
  return result
 end
 probe.Parent=script.Parent
end
script.Destroying:Connect(function()
 destroyed=true
 for _,connection in ipairs(connections) do connection:Disconnect() end
 for current in pairs(folders) do detach(current) end
 for model in pairs(tracked) do untrack(model) end
 effects:Destroy()
 damageEffects:Destroy()
 if probe then probe:Destroy() end
 player:SetAttribute("RTSBuildingVisualsReady",false)
end)
player:SetAttribute("RTSBuildingVisualsReady",true)
