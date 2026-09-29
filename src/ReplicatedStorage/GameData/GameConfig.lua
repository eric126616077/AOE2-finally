local Config = {}
Config.Map = { MapSize = 512, GridSize = 8, GroundY = 0, Seed = 2718 }
Config.Settings = {
 maxPlayers = 4, gameMode = "deathmatch", startingResources = { food = 500, wood = 500, gold = 300, stone = 200 },
 startingVillagers = 3, populationLimit = 60,
}
Config.Spawns = { Vector3.new(-192,0,-192), Vector3.new(192,0,192), Vector3.new(192,0,-192), Vector3.new(-192,0,192) }
Config.BuildOrder = { "TownCenter", "House", "Barracks", "Farm" }
Config.Buildings = {
 Castle = { name = "主堡", cost = {}, hp = 2400, size = Vector2.new(8,8), height = 48, color = Color3.fromRGB(118,128,146), population = 10 },
 TownCenter = { name = "市鎮中心", cost = {wood=350,stone=100}, hp = 1600, size = Vector2.new(4,4), height = 24, color = Color3.fromRGB(174,130,79), population = 5 },
 House = { name = "房屋", cost = {wood=25}, hp = 400, size = Vector2.new(2,2), height = 14, color = Color3.fromRGB(200,173,125), population = 5 },
 Barracks = { name = "兵營", cost = {wood=175}, hp = 1000, size = Vector2.new(3,3), height = 20, color = Color3.fromRGB(149,117,103), population = 0 },
 Farm = { name = "農田", cost = {wood=60}, hp = 250, size = Vector2.new(3,3), height = 1, color = Color3.fromRGB(165,141,60), population = 0 },
}
Config.Units = {
 villager = { name="村民", cost={food=50}, hp=40, speed=14, damage=3, range=5, trainTime=6, color=Color3.fromRGB(227,196,137) },
 infantry = { name="步兵", cost={food=60,gold=20}, hp=90, speed=16, damage=10, range=6, trainTime=8, color=Color3.fromRGB(160,182,208) },
}
Config.Resources = {
 Tree = { resource="wood", name="樹木", amount=300, color=Color3.fromRGB(64,114,68), height=16 },
 Gold = { resource="gold", name="金礦", amount=250, color=Color3.fromRGB(202,168,70), height=6 },
 Stone = { resource="stone", name="石礦", amount=350, color=Color3.fromRGB(134,144,153), height=7 },
 Berries = { resource="food", name="漿果叢", amount=250, color=Color3.fromRGB(157,67,84), height=5 },
}
return Config
