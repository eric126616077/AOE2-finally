-- Cosmetic motion only; roots, orders, damage and movement remain server authoritative.
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local Config=require(game.ReplicatedStorage.GameData.GameConfig)
local player=Players.LocalPlayer
local units=workspace:WaitForChild("Units")
local tracked={}
local attacks={}
local observers={}
local activeEffects=0
local effects=Instance.new("Folder")
effects.Name="RTSClientEffects"
effects.Parent=workspace
local function attackEffect(model)
 if player:GetAttribute("ReducedMotion")==true or activeEffects>=40 then return end
 local target=model:GetAttribute("AttackPosition")
 local data=Config.Units[model:GetAttribute("UnitType")]
 if not data or typeof(target)~="Vector3" or not model.PrimaryPart then return end
 local camera=workspace.CurrentCamera
 if not camera then return end
 local start=model.PrimaryPart.Position+Vector3.new(0,1,0)
 local _,visible=camera:WorldToViewportPoint(start)
 if not visible then return end
 local projectile=Instance.new("Part")
 projectile.Name="AttackEffect"
 projectile.Anchored=true
 projectile.CanCollide,projectile.CanQuery,projectile.CanTouch=false,false,false
 projectile.Material=Enum.Material.Neon
 projectile.Color=Color3.fromRGB(245,206,123)
 local ranged=data.range>20
 local finish=target+Vector3.new(0,2,0)
 if ranged and (finish-start).Magnitude>1 then
  projectile.Size=Vector3.new(.2,.2,2)
  projectile.CFrame=CFrame.lookAt(start,finish)
  TweenService:Create(projectile,TweenInfo.new(.24,Enum.EasingStyle.Linear),{CFrame=CFrame.lookAt(finish,finish+(finish-start).Unit),Transparency=.7}):Play()
 else
  projectile.Shape=Enum.PartType.Ball
  projectile.Size=Vector3.new(.6,.6,.6)
  projectile.Position=finish
  TweenService:Create(projectile,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(2,2,2),Transparency=1}):Play()
 end
 activeEffects+=1
 projectile.Destroying:Once(function() activeEffects-=1 end)
 projectile.Parent=effects
 Debris:AddItem(projectile,.3)
end
local animatedParts={BootL=true,BootR=true,Arm=true,ArmL=true,ArmR=true,Tool=true,ToolHead=true,Sword=true}
local function refresh(model)
 local root=model.PrimaryPart
 if model.Parent~=units or not root or not root:IsDescendantOf(model) then tracked[model]=nil; return end
 local previous=tracked[model]
 local existing={}
 if previous and previous.root==root then
  for _,entry in ipairs(previous.parts) do existing[entry.part]=entry end
 end
 local parts={}
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and animatedParts[part.Name] then
   -- Preserve rest offsets when later appearance parts arrive during an animation.
   table.insert(parts,existing[part] or {part=part,offset=root.CFrame:ToObjectSpace(part.CFrame),side=part.Position.X<root.Position.X and -1 or 1})
  end
 end
 if #parts>0 then
  if previous and previous.root==root then previous.parts=parts
  else tracked[model]={root=root,parts=parts,last=root.Position,phase=0,wasActive=false} end
 else tracked[model]=nil end
end
local function scheduleRefresh(model)
 local observer=observers[model]
 if not observer or observer.pending then return end
 observer.pending=true
 -- One scan of this model after the replication batch, never a Workspace scan.
 task.defer(function()
  if observers[model]~=observer then return end
  observer.pending=false
  refresh(model)
 end)
end
local function track(model)
 if not model:IsA("Model") or observers[model] then return end
 local observer={pending=false,connections={}}
 observers[model]=observer
 attacks[model]=model:GetAttributeChangedSignal("LastAttack"):Connect(function() attackEffect(model) end)
 table.insert(observer.connections,model:GetPropertyChangedSignal("PrimaryPart"):Connect(function() scheduleRefresh(model) end))
 table.insert(observer.connections,model.DescendantAdded:Connect(function(part)
  if part:IsA("BasePart") then scheduleRefresh(model) end
 end))
 table.insert(observer.connections,model.DescendantRemoving:Connect(function(part)
  if part:IsA("BasePart") then scheduleRefresh(model) end
 end))
 refresh(model)
end
units.ChildAdded:Connect(track)
units.ChildRemoved:Connect(function(model)
 tracked[model]=nil
 if attacks[model] then attacks[model]:Disconnect(); attacks[model]=nil end
 local observer=observers[model]
 if observer then
  observers[model]=nil
  for _,connection in ipairs(observer.connections) do connection:Disconnect() end
 end
end)
for _,model in ipairs(units:GetChildren()) do track(model) end
local accumulator=0
RunService.RenderStepped:Connect(function(dt)
 accumulator+=dt
 if accumulator<1/30 then return end
 local step=math.min(accumulator,0.1)
 accumulator=0
 local camera=workspace.CurrentCamera
 if not camera then return end
 local reduced=player:GetAttribute("ReducedMotion")==true
 for model,item in pairs(tracked) do
  if not model.Parent or not item.root.Parent then tracked[model]=nil; continue end
  local point=item.root.Position
  local moving=(point-item.last).Magnitude>0.03
  item.last=point
  local screen,visible=camera:WorldToViewportPoint(point)
  local order=model:GetAttribute("Order")
  local work=order=="採集" or order=="建造" or order=="施工" or order=="修復" or order=="攻擊"
  local active=not reduced and visible and screen.Z<500 and (moving or work)
  if active then item.phase+=step*(moving and 10 or 7) end
  if active or item.wasActive then
   for _,entry in ipairs(item.parts) do
    local part=entry.part
    if part.Parent then
     local angle=0
     if active then
      if part.Name=="BootL" then angle=math.sin(item.phase)*0.3
      elseif part.Name=="BootR" then angle=-math.sin(item.phase)*0.3
      elseif moving then angle=math.sin(item.phase)*entry.side*0.18
      else angle=math.sin(item.phase)*0.32 end
     end
     part.CFrame=item.root.CFrame*entry.offset*CFrame.Angles(angle,0,0)
    end
   end
  end
  item.wasActive=active
 end
end)
