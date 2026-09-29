-- ServerScriptService/ServerModules/GameManager.lua
-- 游戏管理器 - 核心逻辑

local GameManager = {}
GameManager.__index = GameManager

function GameManager.new()
	local self = setmetatable({}, GameManager)
	self.gameState = "waiting"  -- waiting, playing, ended
	self.players = {}
	return self
end

-- 初始化游戏
function GameManager:init()
	print("AOE2 Game Initialized!")
end

-- 玩家加入游戏
function GameManager:playerJoined(player)
	table.insert(self.players, player)
	print(player.Name .. " joined the game!")
end

-- 开始游戏
function GameManager:startGame()
	self.gameState = "playing"
	print("Game started!")
end

-- 获取游戏状态
function GameManager:getState()
	return self.gameState
end

return GameManager
