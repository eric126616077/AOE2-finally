-- Shared rules for the original Roblox RTS. Ages are numeric on both client and server.
local Config = {}
Config.Map = {
 MapSize = 1024, GridSize = 8, GroundY = 0, Seed = 2718,
 Sizes = { Small = 768, Medium = 1024, Large = 1536 },
 SizeNames = { Small = "小型 · 768", Medium = "標準 · 1024", Large = "大型 · 1536" },
}
Config.Settings = {
 maxPlayers = 4, gameMode = "Conquest", defaultMapSize = "Medium",
 startingResources = { food = 300, wood = 300, gold = 150, stone = 150 },
 startingVillagers = 3, populationLimit = 100, wonderVictoryTime = 180,
}
Config.Spawns = { Vector3.new(-344,0,-344), Vector3.new(344,0,344), Vector3.new(344,0,-344), Vector3.new(-344,0,344) }
Config.BuildOrder = { "TownCenter", "House", "Mill", "LumberCamp", "MiningCamp", "Barracks", "Farm", "ArcheryRange", "Stable", "Blacksmith", "Market", "Tower", "Wall", "Castle", "SiegeWorkshop", "Monastery", "University", "Wonder" }
Config.Buildings = {
 TownCenter = { name="市鎮中心", description="訓練村民、交回資源並升級時代；城堡時代可增建。", cost={wood=275,stone=100}, hp=2400, size=Vector2.new(4,4), height=26, color=Color3.fromRGB(174,130,79), population=5, minAge=3, buildTime=25, dropoff={"food","wood","gold","stone"}, trains={"villager"} },
 House = { name="房屋", description="增加 5 人口上限。", cost={wood=25}, hp=550, size=Vector2.new(2,2), height=14, color=Color3.fromRGB(200,173,125), population=5, minAge=1, buildTime=8, trains={} },
 Barracks = { name="兵營", description="訓練步兵與對抗騎兵的長槍兵。", cost={wood=175}, hp=1200, size=Vector2.new(3,3), height=20, color=Color3.fromRGB(149,117,103), population=0, minAge=1, buildTime=18, trains={"infantry","spearman"} },
 Farm = { name="農田", description="提供可採集的食物。", cost={wood=60}, hp=300, size=Vector2.new(3,3), height=1.2, color=Color3.fromRGB(165,141,60), population=0, minAge=1, buildTime=7, amount=700, trains={} },
 Mill = { name="磨坊", description="收集附近的食物，研究農田科技。", cost={wood=100}, hp=800, size=Vector2.new(2,2), height=20, color=Color3.fromRGB(196,174,121), population=0, minAge=1, buildTime=12, dropoff={"food"}, trains={} },
 LumberCamp = { name="伐木場", description="交回木材，縮短村民往返路程。", cost={wood=100}, hp=800, size=Vector2.new(2,2), height=12, color=Color3.fromRGB(166,134,92), population=0, minAge=1, buildTime=12, dropoff={"wood"}, trains={} },
 MiningCamp = { name="採礦營地", description="交回黃金與石材。", cost={wood=100}, hp=800, size=Vector2.new(2,2), height=12, color=Color3.fromRGB(145,142,125), population=0, minAge=1, buildTime=12, dropoff={"gold","stone"}, trains={} },
 ArcheryRange = { name="射箭場", description="訓練弓箭手與反制弓兵的矛兵。", cost={wood=175}, hp=1200, size=Vector2.new(3,3), height=20, color=Color3.fromRGB(161,131,92), population=0, minAge=2, buildTime=20, trains={"archer","skirmisher"} },
 Stable = { name="馬廄", description="訓練偵察騎兵與重裝騎兵。", cost={wood=175}, hp=1400, size=Vector2.new(4,3), height=19, color=Color3.fromRGB(172,128,89), population=0, minAge=2, buildTime=20, trains={"scout","cavalry"} },
 SiegeWorkshop = { name="攻城器械廠", description="製造攻城衝車與投石車。", cost={wood=200}, hp=1500, size=Vector2.new(4,3), height=21, color=Color3.fromRGB(144,122,99), population=0, minAge=3, buildTime=24, trains={"ram","mangonel"} },
 Monastery = { name="修道院", description="守護信仰的城堡時代建築。", cost={wood=175}, hp=1300, size=Vector2.new(3,3), height=28, color=Color3.fromRGB(218,207,165), population=0, minAge=3, buildTime=24, trains={} },
 University = { name="大學", description="研究帝國的高階軍事科技。", cost={wood=200}, hp=1500, size=Vector2.new(4,4), height=26, color=Color3.fromRGB(188,167,134), population=0, minAge=3, buildTime=24, trains={} },
 Blacksmith = { name="兵工廠", description="研究武器與護甲升級。", cost={wood=150}, hp=1100, size=Vector2.new(3,3), height=19, color=Color3.fromRGB(133,126,113), population=0, minAge=2, buildTime=18, trains={} },
 Market = { name="市集", description="交換木材、食物、石材與黃金。", cost={wood=175}, hp=1300, size=Vector2.new(4,3), height=19, color=Color3.fromRGB(177,147,97), population=0, minAge=2, buildTime=20, dropoff={"food","wood","gold","stone"}, trains={} },
 Tower = { name="瞭望塔", description="自動射擊進入射程的敵軍。", cost={wood=50,stone=125}, hp=1500, size=Vector2.new(2,2), height=30, color=Color3.fromRGB(161,158,144), population=0, minAge=2, buildTime=22, damage=8, range=60, attackInterval=1.8, trains={} },
 Wall = { name="石牆", description="封鎖狹道並保護基地。", cost={stone=15}, hp=1700, size=Vector2.new(1,1), height=13, color=Color3.fromRGB(169,166,150), population=0, minAge=2, buildTime=4, trains={} },
 Castle = { name="城堡", description="強大的基地防禦，可製造巨型投石機。", cost={stone=650}, hp=4800, size=Vector2.new(8,8), height=48, color=Color3.fromRGB(118,128,146), population=10, minAge=3, buildTime=45, damage=14, range=75, attackInterval=1.6, dropoff={"food","wood","gold","stone"}, trains={"trebuchet"} },
 Wonder = { name="世界奇觀", description="奇觀模式中守住完工奇觀即可勝利。", cost={wood=1000,gold=1000,stone=1000}, hp=4500, size=Vector2.new(7,7), height=57, color=Color3.fromRGB(213,197,155), population=0, minAge=4, buildTime=80, trains={} },
}
Config.Units = {
 villager = { name="村民", description="採集資源、建造與修復。", cost={food=50}, hp=40, speed=14, damage=3, range=5, trainTime=10, color=Color3.fromRGB(227,196,137), minAge=1, trainsAt={"TownCenter"}, class="villager", armor=0, attackInterval=1.6, population=1, carryCapacity=10, gatherRate=3, bonus={} },
 infantry = { name="步兵", description="便宜且可靠的近戰部隊。", cost={food=60,gold=20}, hp=75, speed=16, damage=10, range=6, trainTime=14, color=Color3.fromRGB(160,182,208), minAge=1, trainsAt={"Barracks"}, class="infantry", armor=1, attackInterval=1.4, population=1, bonus={building=3} },
 spearman = { name="長槍兵", description="長槍對騎兵造成額外傷害。", cost={food=35,wood=25}, hp=55, speed=16, damage=5, range=8, trainTime=12, color=Color3.fromRGB(173,186,167), minAge=2, trainsAt={"Barracks"}, class="infantry", armor=0, attackInterval=1.5, population=1, bonus={cavalry=22} },
 archer = { name="弓箭手", description="遠距離射擊，畏懼快速騎兵。", cost={wood=25,gold=45}, hp=40, speed=15, damage=6, range=48, trainTime=14, color=Color3.fromRGB(159,181,116), minAge=2, trainsAt={"ArcheryRange"}, class="archer", armor=0, attackInterval=1.8, population=1, bonus={infantry=1} },
 scout = { name="斥候騎兵", description="快速探索地圖與突襲村民。", cost={food=80}, hp=55, speed=27, damage=5, range=7, trainTime=16, color=Color3.fromRGB(167,126,78), minAge=1, trainsAt={"Stable"}, class="cavalry", armor=0, attackInterval=1.3, population=1, bonus={villager=2} },
 skirmisher = { name="矛兵", description="低成本遠程部隊，克制弓箭手。", cost={food=25,wood=35}, hp=40, speed=15, damage=3, range=40, trainTime=14, color=Color3.fromRGB(171,185,126), minAge=2, trainsAt={"ArcheryRange"}, class="archer", armor=2, attackInterval=1.9, population=1, bonus={archer=7} },
 cavalry = { name="騎士", description="迅速突襲經濟與遠程部隊。", cost={food=60,gold=75}, hp=125, speed=24, damage=12, range=7, trainTime=20, color=Color3.fromRGB(182,151,105), minAge=3, trainsAt={"Stable"}, class="cavalry", armor=2, attackInterval=1.5, population=1, bonus={archer=5} },
 ram = { name="攻城衝車", description="高護甲、低速度，專精摧毀建築。", cost={wood=160,gold=75}, hp=280, speed=9, damage=4, range=8, trainTime=25, color=Color3.fromRGB(151,127,84), minAge=3, trainsAt={"SiegeWorkshop"}, class="siege", armor=8, attackInterval=2.2, population=1, bonus={building=40} },
 mangonel = { name="投石車", description="遠距投石造成範圍傷害，適合對付密集部隊。", cost={wood=160,gold=135}, hp=90, speed=10, damage=24, range=62, trainTime=28, color=Color3.fromRGB(157,134,94), minAge=3, trainsAt={"SiegeWorkshop"}, class="siege", armor=2, attackInterval=3.5, population=1, splash=12, bonus={building=18} },
 trebuchet = { name="巨型投石機", description="極遠程攻城武器，需要軍隊保護。", cost={wood=200,gold=200}, hp=170, speed=8, damage=12, range=115, trainTime=35, color=Color3.fromRGB(165,145,97), minAge=4, trainsAt={"Castle"}, class="siege", armor=3, attackInterval=4.5, population=1, bonus={building=85} },
}
Config.Ages = {
 [1]={name="黑暗時代",cost={},time=0,requirements={}},
 [2]={name="封建時代",cost={food=500},time=35,requirements={buildings=2}},
 [3]={name="城堡時代",cost={food=800,gold=200},time=45,requirements={buildings=2}},
 [4]={name="帝王時代",cost={food=1000,gold=800},time=55,requirements={buildings=2,castleOrBuildings=true}},
}
Config.Technologies = {
 Loom = { name="織布機", description="村民生命 +15、護甲 +1。", cost={gold=50}, time=15, minAge=1, building="TownCenter", effect={hp=15,armor=1}, unitClass="villager" },
 Forging = { name="鍛造", description="軍隊攻擊力 +2。", cost={food=150,gold=75}, time=22, minAge=2, building="Blacksmith", effect={attack=2} },
 Armor = { name="鎖甲", description="軍隊護甲 +2。", cost={food=150,gold=100}, time=22, minAge=2, building="Blacksmith", effect={armor=2} },
 Wheelbarrow = { name="手推車", description="村民採集 +25%、攜帶量 +5、速度 +10%。", cost={food=175,wood=50}, time=25, minAge=2, building="TownCenter", effect={gather=0.25,carry=5,speed=0.1}, unitClass="villager" },
 DoubleBitAxe = { name="雙刃斧", description="村民伐木效率 +20%。", cost={food=100,wood=50}, time=20, minAge=2, building="LumberCamp", effect={gatherWood=0.2}, unitClass="villager" },
 HorseCollar = { name="馬軛", description="農田食物容量 +200。", cost={food=75,wood=75}, time=18, minAge=2, building="Mill", effect={farmCapacity=200} },
 HeavyPlow = { name="重犁", description="農田食物容量 +300。", cost={food=125,wood=125}, time=22, minAge=3, building="Mill", requires="HorseCollar", effect={farmCapacity=300} },
 Fletching = { name="箭羽", description="遠程部隊射程 +8。", cost={food=100,gold=50}, time=20, minAge=2, building="Blacksmith", effect={range=8}, unitClass="archer" },
 ThumbRing = { name="拇指環", description="遠程部隊攻擊間隔減少 15%。", cost={food=300,wood=250}, time=24, minAge=3, building="ArcheryRange", effect={interval=0.15}, unitClass="archer" },
 Chemistry = { name="化學", description="軍隊攻擊力 +3。", cost={food=300,gold=200}, time=28, minAge=4, building="University", effect={attack=3} },
 Conscription = { name="徵兵制度", description="所有建築訓練時間減少 20%。", cost={food=150,gold=150}, time=20, minAge=4, building="Castle", effect={trainSpeed=0.2} },
}
Config.TechnologyOrder = { "Loom", "Wheelbarrow", "DoubleBitAxe", "HorseCollar", "HeavyPlow", "Forging", "Armor", "Fletching", "ThumbRing", "Chemistry", "Conscription" }
Config.Resources = {
 Tree = { resource="wood", name="樹木", amount=500, color=Color3.fromRGB(64,114,68), height=18 },
 Gold = { resource="gold", name="金礦", amount=800, color=Color3.fromRGB(202,168,70), height=6 },
 Stone = { resource="stone", name="石礦", amount=650, color=Color3.fromRGB(134,144,153), height=7 },
 Berries = { resource="food", name="漿果叢", amount=400, color=Color3.fromRGB(157,67,84), height=5 },
}
Config.MatchModes = { Conquest="征服", Regicide="主城決戰", Wonder="奇觀" }
Config.AIDifficulties = { Easy="簡單", Normal="普通", Hard="困難" }
Config.MarketTrade = { batch=100, buyGold=130, sellGold=70 }
return Config
