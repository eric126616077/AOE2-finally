-- ReplicatedStorage/Shared/SharedFunctions.lua
-- 共享函数库 - 客户端和服务器都可以使用

local SharedFunctions = {}

-- 格式化资源显示
function SharedFunctions:formatResources(resources)
	return string.format("Food: %d, Wood: %d, Gold: %d, Stone: %d",
		resources.food or 0,
		resources.wood or 0,
		resources.gold or 0,
		resources.stone or 0
	)
end

-- 计算单位造价
function SharedFunctions:calculateCost(unitType, count)
	local unitData = require(game.ReplicatedStorage.GameData.GameConfig).Units[unitType]
	if not unitData then return {} end
	
	local cost = {}
	for resource, amount in pairs(unitData.cost or {}) do
		cost[resource] = amount * (count or 1)
	end
	return cost
end

-- 检查资源是否充足
function SharedFunctions:hasEnoughResources(playerResources, cost)
	for resource, amount in pairs(cost) do
		if (playerResources[resource] or 0) < amount then
			return false
		end
	end
	return true
end

-- 扣除资源
function SharedFunctions:deductResources(playerResources, cost)
	local newResources = {}
	for resource, amount in pairs(playerResources) do
		newResources[resource] = amount
	end
	
	for resource, amount in pairs(cost) do
		newResources[resource] = newResources[resource] - amount
	end
	
	return newResources
end

-- 格式化时间
function SharedFunctions:formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", minutes, secs)
end

-- 随机选择
function SharedFunctions:randomSelect(tbl)
	if #tbl == 0 then return nil end
	local index = math.random(1, #tbl)
	return tbl[index]
end

-- 克隆对象
function SharedFunctions:clone(instance)
	local clone = instance:Clone()
	clone.Parent = nil
	clone.Name = instance.Name .. "_Clone"
	return clone
end

return SharedFunctions
