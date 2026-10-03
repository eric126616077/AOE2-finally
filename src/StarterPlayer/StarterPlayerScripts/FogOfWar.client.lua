-- 戰爭迷霧（AOE2 式黑色地圖），只在本機顯示：
-- · 未探索的區域鋪上黑幕，其中的樹木、礦、獵物與敵方建築隱藏；
-- · 探索過但目前看不到的區域鋪上暗霧，敵方單位在其中隱藏，敵方建築保留最後看到的樣子；
-- · 自己與盟友的單位、建築提供視野（城鎮守望增加建築視野）。
-- 觀戰、淘汰、對局結束或回到大廳時整張地圖重新顯示。伺服器規則不依賴迷霧。
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS.GameData.GameConfig)
local FogRules=require(RS.Shared.FogRules)
local FogView=require(RS.Shared.FogView)
local player=Players.LocalPlayer
if script:GetAttribute("FogInitialized") then return end
script:SetAttribute("FogInitialized",true)
local VISION=Config.Vision
local SLAB_HEIGHT,FOG_TRANSPARENCY=2,.5
local folder,rowParts,grid=nil,{},nil
-- 單位用 LocalTransparencyModifier 隱藏（UnitMotion 不使用它）；建築與資源改本機 Transparency，
-- 避免和施工／損壞外觀使用的 LocalTransparencyModifier 互相覆蓋。
local hiddenUnits=setmetatable({},{__mode="k"})
local hiddenStatic=setmetatable({},{__mode="k"})
local staticCells={} -- 格子索引 → {模型 = true}：尚未探索區域內的資源與敵方建築
local connections={}

local function effectOff(item,record)
 if item:IsA("BillboardGui") or item:IsA("SurfaceGui") or item:IsA("ParticleEmitter") or item:IsA("Light") or item:IsA("Fire") or item:IsA("Smoke") then
  if record.effects[item]==nil then record.effects[item]=item.Enabled end
  item.Enabled=false
 end
end
local function hideUnit(model)
 if hiddenUnits[model] then return end
 local record={effects={}}
 local function apply(item)
  if item:IsA("BasePart") then item.LocalTransparencyModifier=1 else effectOff(item,record) end
 end
 for _,item in ipairs(model:GetDescendants()) do apply(item) end
 record.connection=model.DescendantAdded:Connect(apply)
 hiddenUnits[model]=record
end
local function showUnit(model)
 local record=hiddenUnits[model]
 if not record then return end
 hiddenUnits[model]=nil
 record.connection:Disconnect()
 for _,item in ipairs(model:GetDescendants()) do if item:IsA("BasePart") then item.LocalTransparencyModifier=0 end end
 for item,enabled in pairs(record.effects) do if item.Parent then item.Enabled=enabled end end
end
local function hideStatic(model)
 if hiddenStatic[model] then return end
 local record={parts={},effects={}}
 local function apply(item)
  if item:IsA("BasePart") then
   if record.parts[item]==nil then record.parts[item]=item.Transparency end
   item.Transparency=1
  else effectOff(item,record) end
 end
 for _,item in ipairs(model:GetDescendants()) do apply(item) end
 record.connection=model.DescendantAdded:Connect(apply)
 hiddenStatic[model]=record
end
local function showStatic(model)
 local record=hiddenStatic[model]
 if not record then return end
 hiddenStatic[model]=nil
 record.connection:Disconnect()
 for part,transparency in pairs(record.parts) do if part.Parent then part.Transparency=transparency end end
 for item,enabled in pairs(record.effects) do if item.Parent then item.Enabled=enabled end end
end

local function relation(model) return model:GetAttribute("OwnerId")~=nil and FogView.Relation(model) or "neutral" end
local function friendly(model) local kind=relation(model); return kind=="own" or kind=="ally" end

-- 尚未探索區域的靜態目標（資源、敵方建築）：記在所在格子，探索到時才顯示。
local function trackStatic(model)
 if not grid or not model:IsA("Model") or friendly(model) then return end
 if model:GetAttribute("BuildingType") and FogView.seenBuildings[model] then return end
 local position=model:GetPivot().Position
 local column,row=FogRules.cellOf(grid,position.X,position.Z)
 if not column then return end
 if model:GetAttribute("BuildingType") then
  -- 敵方建築要「看到」才顯示（迷霧中新蓋的建築也看不到）；由每次更新檢查。
  if not FogRules.visibleAt(grid,position.X,position.Z) then hideStatic(model) end
  return
 end
 if FogRules.exploredAt(grid,position.X,position.Z) then return end
 local index=FogRules.index(grid,column,row)
 staticCells[index]=staticCells[index] or {}
 staticCells[index][model]=true
 hideStatic(model)
end

local function slab(row,run)
 local cell=grid.cell
 local half=grid.size/2
 local part=Instance.new("Part")
 part.Name=run.state==0 and "Unexplored" or "Fog"
 part.Anchored,part.CanCollide,part.CanQuery,part.CanTouch,part.CastShadow=true,false,false,false,false
 part.Material=Enum.Material.SmoothPlastic
 part.Color=Color3.new(0,0,0)
 part.Transparency=run.state==0 and 0 or FOG_TRANSPARENCY
 local width=(run.last-run.first+1)*cell
 part.Size=Vector3.new(width,SLAB_HEIGHT,cell)
 part.CFrame=CFrame.new((run.first-1)*cell-half+width/2,Config.Map.GroundY+SLAB_HEIGHT/2-.05,(row-.5)*cell-half)
 part.Parent=folder
 return part
end
local function drawRow(row)
 for _,part in ipairs(rowParts[row] or {}) do part:Destroy() end
 local parts={}
 for _,run in ipairs(FogRules.runs(grid,row)) do table.insert(parts,slab(row,run)) end
 rowParts[row]=parts
 FogView.mapRows[row]=true
end

local function sources()
 local list={}
 local bonus=player:GetAttribute("BuildingVision") or 0
 local units=workspace:FindFirstChild("Units")
 if units then
  for _,model in ipairs(units:GetChildren()) do
   if friendly(model) then
    local p=model:GetPivot().Position
    table.insert(list,{X=p.X,Z=p.Z,radius=FogRules.radius(VISION,model:GetAttribute("UnitType"),false,0)})
   end
  end
 end
 local buildings=workspace:FindFirstChild("Buildings")
 if buildings then
  for _,model in ipairs(buildings:GetChildren()) do
   if friendly(model) then
    local p=model:GetPivot().Position
    -- 工地只有一半視野；完工後才是完整的建築視野。
    local radius=FogRules.radius(VISION,model:GetAttribute("BuildingType"),true,bonus)
    table.insert(list,{X=p.X,Z=p.Z,radius=model:GetAttribute("Complete")==false and radius*.5 or radius})
   end
  end
 end
 return list
end

local function refresh()
 local changed,discovered=FogRules.update(grid,sources())
 for row in pairs(changed) do drawRow(row) end
 for _,index in ipairs(discovered) do
  local models=staticCells[index]
  if models then
   staticCells[index]=nil
   for model in pairs(models) do showStatic(model) end
  end
 end
 -- 敵方單位只在目前視野內顯示；敵方建築第一次進入視野後保留。
 local units=workspace:FindFirstChild("Units")
 if units then
  for _,model in ipairs(units:GetChildren()) do
   if not friendly(model) then
    local p=model:GetPivot().Position
    if FogRules.visibleAt(grid,p.X,p.Z) then showUnit(model) else hideUnit(model) end
   elseif hiddenUnits[model] then showUnit(model) end
  end
 end
 local buildings=workspace:FindFirstChild("Buildings")
 if buildings then
  for _,model in ipairs(buildings:GetChildren()) do
   if not FogView.seenBuildings[model] then
    local p=model:GetPivot().Position
    if friendly(model) or FogRules.visibleAt(grid,p.X,p.Z) then
     FogView.seenBuildings[model]=true
     showStatic(model)
    elseif not hiddenStatic[model] then hideStatic(model) end
   end
  end
 end
 FogView.version+=1
end

local function stop()
 FogView.active=false
 FogView.grid=nil
 for model in pairs(hiddenUnits) do showUnit(model) end
 for model in pairs(hiddenStatic) do showStatic(model) end
 table.clear(staticCells)
 table.clear(rowParts)
 table.clear(FogView.seenBuildings)
 FogView.mapRows={all=true}
 if folder then folder:Destroy(); folder=nil end
 for _,connection in ipairs(connections) do connection:Disconnect() end
 table.clear(connections)
 grid=nil
 FogView.version+=1
end
local function start()
 local size=workspace:GetAttribute("MapSize") or Config.Map.MapSize
 grid=FogRules.new(size,VISION.cell)
 if not grid then return end
 folder=Instance.new("Folder")
 folder.Name="RTSFogOfWar"
 folder.Parent=workspace
 FogView.grid=grid
 FogView.active=true
 FogView.mapRows={all=true}
 for row=1,grid.count do drawRow(row) end
 for _,name in ipairs({"Resources","Buildings"}) do
  local holder=workspace:FindFirstChild(name)
  if holder then
   for _,model in ipairs(holder:GetChildren()) do trackStatic(model) end
   table.insert(connections,holder.ChildAdded:Connect(function(model) task.defer(function() if model.Parent==holder then trackStatic(model) end end) end))
  end
 end
 refresh()
end
-- 是否該顯示迷霧：對局進行中、本機玩家仍在場上作戰。
local function wanted()
 return VISION.enabled==true and workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("InLobby")~=true
  and player:GetAttribute("Defeated")~=true and player:GetAttribute("Spectator")~=true and workspace:GetAttribute("MapSize")~=nil
end
local function sync()
 if wanted() then
  if not FogView.active then start() end
 elseif FogView.active then stop() end
end
for _,attribute in ipairs({"MatchPhase","MapSize"}) do workspace:GetAttributeChangedSignal(attribute):Connect(function()
 if attribute=="MapSize" and FogView.active then stop() end
 sync()
end) end
for _,attribute in ipairs({"InLobby","Defeated","Spectator","TeamId"}) do player:GetAttributeChangedSignal(attribute):Connect(sync) end
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt
 if elapsed<VISION.refresh then return end
 elapsed=0
 sync()
 if FogView.active and grid then refresh() end
end)
sync()
