local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local StarterGui=game:GetService("StarterGui")
local player=Players.LocalPlayer
local mouse=player:GetMouse()
local guiModule=StarterGui:WaitForChild("GameUI"):WaitForChild("GUIManager")
local UI=require(guiModule)
local Building=require(RS.Shared.BuildingController)
local Config=require(RS.GameData.GameConfig)
local remotes=RS:WaitForChild("RTSRemotes")
local command=remotes:WaitForChild("Command")
local feedback=remotes:WaitForChild("Feedback")
local selected,highlights={},{}
local dragStart
local function ownedUnits()
 local result={}
 for _,model in ipairs(selected) do
  if model.Parent==workspace:FindFirstChild("Units") and model:GetAttribute("OwnerId")==player.UserId then table.insert(result,model) end
 end
 return result
end
local function selectModels(models)
 for _,highlight in ipairs(highlights) do highlight:Destroy() end
 highlights={}
 selected=models
 for _,model in ipairs(selected) do
  local h=Instance.new("Highlight")
  h.Adornee=model
  h.FillTransparency=0.9
  h.OutlineColor=model:GetAttribute("OwnerId")==player.UserId and Color3.fromRGB(145,214,150) or Color3.fromRGB(239,202,117)
  h.DepthMode=Enum.HighlightDepthMode.Occluded
  h.Parent=model
  table.insert(highlights,h)
 end
end
local function train()
 local model=selected[1]
 if not model or model:GetAttribute("OwnerId")~=player.UserId then return end
 local kind=model:GetAttribute("BuildingType")
 local unit=(kind=="Castle" or kind=="TownCenter") and "villager" or (kind=="Barracks" and "infantry")
 if unit then command:FireServer("Train",model,unit) end
end
local function stop() command:FireServer("Stop",ownedUnits()) end
UI:Init({build=function(kind) Building:Begin(kind) end,train=train,stop=stop})
feedback.OnClientEvent:Connect(function(message) UI:Notify(message) end)
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false); StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health,false) end)
local function overUI()
 return UI:BlocksPointer()
end
local function groundPoint()
 local ground=workspace:FindFirstChild("AOE2_Ground")
 if not ground then return nil end
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={ground}
 local ray=mouse.UnitRay
 local result=workspace:Raycast(ray.Origin,ray.Direction*2000,params)
 return result and result.Position
end
local function targetModel()
 local target=mouse.Target
 while target and target~=workspace do
  if target:IsA("Model") and (target:GetAttribute("BuildingType") or target:GetAttribute("UnitType") or target:GetAttribute("ResourceType")) then return target end
  target=target.Parent
 end
 return nil
end
local hotkeys={[Enum.KeyCode.One]="TownCenter",[Enum.KeyCode.Two]="House",[Enum.KeyCode.Three]="Barracks",[Enum.KeyCode.Four]="Farm"}
UIS.InputBegan:Connect(function(input,processed)
 if input.KeyCode==Enum.KeyCode.Escape then Building:Cancel(); dragStart=nil; UI.selectionBox.Visible=false; return end
 if processed or UIS:GetFocusedTextBox() then return end
 if hotkeys[input.KeyCode] then Building:Begin(hotkeys[input.KeyCode])
 elseif input.KeyCode==Enum.KeyCode.T then train()
 elseif input.KeyCode==Enum.KeyCode.X then stop()
 elseif input.KeyCode==Enum.KeyCode.V then
  local models={}
  local folder=workspace:FindFirstChild("Units")
  if folder then for _,unit in ipairs(folder:GetChildren()) do if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then table.insert(models,unit) end end end
  selectModels(models)
 elseif input.UserInputType==Enum.UserInputType.MouseButton1 and not overUI() then
  if Building.kind then
   Building:Update(groundPoint())
   if Building.valid then command:FireServer("Build",Building.kind,Building.position)
   else UI:Notify("無法建造：請確認資源、村民距離及占地。") end
  else dragStart=Vector2.new(mouse.X,mouse.Y) end
 elseif input.UserInputType==Enum.UserInputType.MouseButton2 and not overUI() then
  if Building.kind then Building:Cancel(); return end
  local units=ownedUnits()
  if #units==0 then UI:Notify("先選取自己的村民或軍隊，再按右鍵下令。") return end
  local target=targetModel() or groundPoint()
  if target then command:FireServer("Order",units,target) end
 end
end)
UIS.InputEnded:Connect(function(input)
 if input.UserInputType~=Enum.UserInputType.MouseButton1 or not dragStart then return end
 local start=dragStart
 dragStart=nil
 UI.selectionBox.Visible=false
 if overUI() then return end
 local finish=Vector2.new(mouse.X,mouse.Y)
 if (finish-start).Magnitude>8 then
  local models={}
  local folder=workspace:FindFirstChild("Units")
  if folder then
   for _,unit in ipairs(folder:GetChildren()) do
    local point,visible=workspace.CurrentCamera:WorldToScreenPoint(unit:GetPivot().Position)
    if visible and unit:GetAttribute("OwnerId")==player.UserId and point.X>=math.min(start.X,finish.X) and point.X<=math.max(start.X,finish.X) and point.Y>=math.min(start.Y,finish.Y) and point.Y<=math.max(start.Y,finish.Y) then table.insert(models,unit) end
   end
  end
  selectModels(models)
 else
  local target=targetModel()
  if UIS:IsKeyDown(Enum.KeyCode.LeftShift) and target and target:GetAttribute("UnitType") and target:GetAttribute("OwnerId")==player.UserId then
   local models=ownedUnits()
   local index=table.find(models,target)
   if index then table.remove(models,index) else table.insert(models,target) end
   selectModels(models)
  else selectModels(target and {target} or {}) end
 end
end)
UIS.WindowFocusReleased:Connect(function() dragStart=nil; UI.selectionBox.Visible=false end)
local updateTime,mapTime=0,0
RunService.RenderStepped:Connect(function(dt)
 if Building.kind then Building:Update(not overUI() and groundPoint() or nil) end
 if dragStart then
  local finish=Vector2.new(mouse.X,mouse.Y)
  UI.selectionBox.Visible=(finish-dragStart).Magnitude>8
  UI.selectionBox.Position=UDim2.fromOffset(math.min(finish.X,dragStart.X),math.min(finish.Y,dragStart.Y))
  UI.selectionBox.Size=UDim2.fromOffset(math.abs(finish.X-dragStart.X),math.abs(finish.Y-dragStart.Y))
 end
 updateTime+=dt; mapTime+=dt
 if updateTime>=0.15 then
  updateTime=0
  local alive={}
  for _,model in ipairs(selected) do if model.Parent then table.insert(alive,model) end end
  if #alive~=#selected then selectModels(alive) end
  UI:Update(selected,Building.kind)
 end
 if mapTime>=0.5 then mapTime=0; UI:UpdateMap() end
end)
UI:Notify("選取村民，右鍵點擊樹木或漿果叢開始採集。")
