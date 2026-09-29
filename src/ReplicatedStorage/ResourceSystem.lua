-- ===============================
-- 資源設置系統（服務器端）
-- 放在 ReplicatedStorage 內，由 ServerScriptService 調用
-- ===============================
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GRID_SIZE = 8

-- ========== 資源配置 ==========
local RESOURCE_CONFIGS = {
	Tree = {
		icon = "rbxassetid://112932136502898",
		name = "樹木",
		maxAmount = 100,
		height = 1.5, -- 1.5 格高
		hitboxSize = Vector3.new(1.2, 1.8, 1.2), -- 相對於 GRID_SIZE
		tag = "Tree",
		harvestTag = "TreeHitbox",
		resourceType = "Wood",
	},
	Stone = {
		icon = "rbxassetid://137580463962288",
		name = "石頭",
		maxAmount = 200,
		height = 0.8, -- 較矮
		hitboxSize = Vector3.new(1.0, 1.2, 1.0),
		tag = "Stone",
		harvestTag = "StoneHitbox",
		resourceType = "Stone",
	},
	Gold = {
		icon = "rbxassetid://117337856379493",
		name = "金礦",
		maxAmount = 150,
		height = 0.6, -- 更矮
		hitboxSize = Vector3.new(1.0, 1.0, 1.0),
		tag = "Gold",
		harvestTag = "GoldHitbox",
		resourceType = "Gold",
	},
}

-- ========== 獲取模板類型 ==========
local function GetResourceType(model)
	local templateName = model.Name
	if templateName:match("Tree") then return "Tree" end
	if templateName:match("Stone") then return "Stone" end
	if templateName:match("Gold") then return "Gold" end
	return nil
end

-- ========== 查找 MeshPart ==========
local function FindMeshPart(model)
	-- 嘗試多種常見的 MeshPart 名稱
	local meshNames = {"Mesh0", "Mesh", "MeshPart", "ModelMesh", "TreeMesh", "StoneMesh", "GoldMesh", "Visuals", "Graphic"}
	
	for _, name in ipairs(meshNames) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("MeshPart") then
			return part
		end
	end
	
	-- 如果找不到，創建一個默認的
	local defaultPart = model:FindFirstChildOfClass("Part")
	if defaultPart then
		return defaultPart
	end
	
	return nil
end

-- ========== 設置資源大小 ==========
local function SetupSize(model, config)
	local meshPart = FindMeshPart(model)
	local currentPivot = model:GetPivot()
	
	-- 移動 Model 的 Pivot 到正確的格子中心（地面上方）
	local newPivotPos = Vector3.new(currentPivot.Position.X, 4, currentPivot.Position.Z)  -- Y=4 在地面上
	model:PivotTo(CFrame.new(newPivotPos))
	
	if meshPart then
		-- 記住 meshpart 當前的 local position
		local currentLocalCFrame = meshPart.CFrame
		local localPos = meshPart.Position - currentPivot.Position
		
		-- 設置大小
		meshPart.Size = Vector3.new(GRID_SIZE, GRID_SIZE * config.height, GRID_SIZE)
		
		-- 恢復相對位置並設置高度
		meshPart.CFrame = CFrame.new(newPivotPos + Vector3.new(0, GRID_SIZE * config.height / 2, 0))
	end
end

-- ========== 創建 Hitbox ==========
local function SetupHitbox(model, config)
	-- 刪除舊的
	local oldHitbox = model:FindFirstChild("HarvestHitbox")
	if oldHitbox then oldHitbox:Destroy() end
	
	-- 獲取模型的當前位置
	local modelPos = model:GetPivot().Position
	
	-- 創建新 Hitbox
	local hitbox = Instance.new("Part")
	hitbox.Name = "HarvestHitbox"
	hitbox.Size = Vector3.new(
		GRID_SIZE * config.hitboxSize.X,
		GRID_SIZE * config.hitboxSize.Y,
		GRID_SIZE * config.hitboxSize.Z
	)
	-- 中心在模型位置上方
	hitbox.CFrame = CFrame.new(modelPos + Vector3.new(0, GRID_SIZE * config.height / 2, 0))
	hitbox.Transparency = 1          -- 完全透明
	hitbox.CanCollide = false        -- 不阻擋村民
	hitbox.Anchored = true
	hitbox.Locked = true
	hitbox.Parent = model
	
	-- 添加標籤
	CollectionService:AddTag(model, config.tag)
	CollectionService:AddTag(hitbox, config.harvestTag)
end

-- ========== 設置屬性 ==========
local function SetupAttributes(model, config)
	-- 資源數量屬性
	local amountAttr = config.resourceType .. "Amount"
	local maxAttr = "Max" .. config.resourceType
	
	if not model:GetAttribute(amountAttr) then
		model:SetAttribute(amountAttr, config.maxAmount)
	end
	if not model:GetAttribute(maxAttr) then
		model:SetAttribute(maxAttr, config.maxAmount)
	end
	-- 資源類型
	model:SetAttribute("ResourceType", config.resourceType)
	-- 圖標
	model:SetAttribute("IconId", config.icon)
	-- 顯示名稱
	model:SetAttribute("DisplayName", config.name)
end

-- ========== 創建採集點 ==========
local function SetupHarvestPoint(model, config)
	local oldPoint = model:FindFirstChild("HarvestPoint")
	if oldPoint then oldPoint:Destroy() end
	
	-- 獲取模型的當前位置
	local modelPos = model:GetPivot().Position
	
	local harvestPoint = Instance.new("Part")
	harvestPoint.Name = "HarvestPoint"
	harvestPoint.Size = Vector3.new(2, 2, 2)  -- 村民站的位置
	harvestPoint.Transparency = 1               -- 透明
	harvestPoint.CanCollide = false
	harvestPoint.Anchored = true
	harvestPoint.Locked = true
	harvestPoint.Parent = model
	
	-- 站在資源的前面（南邊）- 使用世界座標
	harvestPoint.CFrame = CFrame.new(modelPos + Vector3.new(0, 0, -GRID_SIZE * 0.6))
end

-- ========== 完整設置資源 ==========
local function SetupResource(model)
	if not model or not model.Parent then return end
	
	-- 檢查是否已經設置
	if model:GetAttribute("ResourceType") then
		return -- 已經設置過了
	end
	
	-- 獲取資源類型
	local resourceType = GetResourceType(model)
	if not resourceType then
		return
	end
	
	local config = RESOURCE_CONFIGS[resourceType]
	if not config then return end
	
	-- 執行所有設置步驟
	SetupSize(model, config)
	SetupHitbox(model, config)
	SetupAttributes(model, config)
	SetupHarvestPoint(model, config)
end

-- ========== 監控新生成的資源 ==========
local function MonitorResources()
	-- 監控 Resources 文件夾中的新資源
	local resourcesFolder = workspace:FindFirstChild("Resources")
	if not resourcesFolder then
		return
	end
	
	resourcesFolder.ChildAdded:Connect(function(child)
		task.wait(0.1) -- 等待一下確保所有子對象載入
		SetupResource(child)
	end)
end

-- ========== 初始化 ==========
local function Init()
	-- 等待 Resources 文件夾
	local resourcesFolder = workspace:FindFirstChild("Resources")
	if not resourcesFolder then
		-- 創建它
		resourcesFolder = Instance.new("Folder")
		resourcesFolder.Name = "Resources"
		resourcesFolder.Parent = workspace
	end
	
	-- 監控新資源
	MonitorResources()
end

-- ========== 運行（由 Loader 調用）==========
-- 不自動運行，讓 ResourceSystemLoader.server.lua 控制

-- ========== 公共 API ==========
return {
	SetupResource = SetupResource,
	SetupAllResources = function()
		local folder = workspace:FindFirstChild("Resources")
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				SetupResource(child)
			end
		end
	end,
	Init = Init,
}
