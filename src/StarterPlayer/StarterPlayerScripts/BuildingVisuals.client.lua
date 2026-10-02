-- Client cosmetic overlays only. Footprints and the original model geometry stay
-- authoritative; user model templates are neither replaced nor transformed.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local RS=game:GetService("ReplicatedStorage")
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("ConstructionVisualRules"))
local player=Players.LocalPlayer
if script:GetAttribute("Initialized")==true or player:GetAttribute("RTSBuildingVisualsReady")==true then return end
script:SetAttribute("Initialized",true)
local tracked,sites,folders,connections={},{},{},{}
local effects=Instance.new("Folder")
effects.Name="RTSConstructionEffects"
effects.Parent=workspace
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
local function cachePart(model,observer,part)
 if not part:IsA("BasePart") or part==model.PrimaryPart or part.Name=="Footprint" or part.Transparency>=1 or observer.parts[part] then return end
 local root=model.PrimaryPart
 if not root then return end
 local height=math.max(root.Size.Y,1)
 local relative=root.CFrame:PointToObjectSpace(part.Position)
 local ratio=math.clamp((relative.Y+height/2)/height,0,1)
 local stage=part:GetAttribute("ConstructionStage")
 -- Imported models need no metadata: ground detail, walls, then roof/top follow
 -- height; all original appearances return unchanged when complete.
 if type(stage)~="number" then stage=ratio<=.08 and 0 or ratio<.58 and 1 or 3 end
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
local function update(model,observer)
 if tracked[model]~=observer then return end
 local constructing=model:GetAttribute("UnderConstruction")==true or model:GetAttribute("Complete")==false
 if constructing then
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
  if observer.constructing then restore(observer); destroyOverlay(observer); completion(model) end
  observer.constructing=false
  sites[model]=nil
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
end
local function track(model)
 if not model:IsA("Model") or tracked[model] then return end
 local observer={parts={},connections={},hadUpdate=false}
 tracked[model]=observer
 for _,attribute in ipairs({"Complete","UnderConstruction","ConstructionProgress","BuilderCount"}) do
  table.insert(observer.connections,model:GetAttributeChangedSignal(attribute):Connect(function() schedule(model,observer) end))
 end
 table.insert(observer.connections,model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
  destroyOverlay(observer)
  if observer.constructing then
   restore(observer)
   for _,part in ipairs(model:GetDescendants()) do cachePart(model,observer,part) end
  end
  schedule(model,observer)
 end))
 table.insert(observer.connections,model.DescendantAdded:Connect(function(part)
  if observer.constructing then cachePart(model,observer,part) end
 end))
 table.insert(observer.connections,model.DescendantRemoving:Connect(function(part)
  local entry=observer.parts[part]
  if entry then cancelTween(entry); part.LocalTransparencyModifier=entry.original; observer.parts[part]=nil end
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
   if not observer.overlay then overlay(model,observer); updateOverlay(model,observer) end
  else destroyOverlay(observer) end
 end
end))
table.insert(connections,player:GetAttributeChangedSignal("ReducedMotion"):Connect(function()
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
  end
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
 if probe then probe:Destroy() end
 player:SetAttribute("RTSBuildingVisualsReady",false)
end)
player:SetAttribute("RTSBuildingVisualsReady",true)
