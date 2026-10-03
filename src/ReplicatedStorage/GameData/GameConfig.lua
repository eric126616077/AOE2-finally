-- Shared rules for the original Roblox RTS. Ages are numeric on both client and server.
local Config = {}
Config.Construction = {workRange=5, extraWorkerRate=0.5, maxSelectedWorkers=200}
-- 自動工作（玩家可在選單關閉）：閒置村民就近施工、交貨或採集；未選村民時建造會派最近村民。
-- 玩家手動移動或停止的村民保持待命，直到再收到工作指令。
-- 工地沒有任何村民施工超過 siteDelay 秒時，重新派最近的村民（閒置優先，採集中的次之），不受 buildRadius 限制。
-- 採集半徑涵蓋開局資源圈（ResourceLayout.OpeningRadius）；資源至少離基地 BaseClearance，80 會讓主城旁的村民找不到資源。
Config.AutoWork = {idleDelay=2, siteDelay=4, buildRadius=64, gatherRadius=260, checkInterval=0.5, retryInterval=4, maxPerStep=12, blockedTime=20, busyPenalty=40, reseedFarms=true}
-- 自動索敵：基礎半徑、換目標需領先的距離、每一優先層級的等效距離，以及自動追擊離開原位的上限。
Config.Combat = {acquisitionRadius=72, retargetMargin=12, tierDistance=40, leashDistance=120, leashCooldown=2,
 -- 陣亡單位留在戰場的秒數與同時存在的上限；超過上限先移除最舊的。
 corpseSeconds=20, maxCorpses=60,
 -- 被打時頭上血條在最後一次受擊後保留的秒數。
 healthBarSeconds=5,
 -- 近戰在揮到的瞬間結算（windup 秒後）；目標此時超出射程加容許值就落空。
 windup={default=0.15, ram=0.25}, meleeTolerance=1.5,
 -- 投射物每秒 studs；傷害在飛抵時結算。石彈落在發射當下的位置，離開 stoneRadius 的單位可以躲開。
 projectile={arrow=110, javelin=80, stone=70, bullet=170, minFlight=0.15, maxFlight=1.8, stoneRadius=6},
 projectileKinds={skirmisher="javelin", mangonel="stone", trebuchet="stone", handCannoneer="bullet", scorpion="javelin", bombardCannon="stone"},
}
Config.Lobby = {
 origin = Vector3.new(0,0,2048), spawnOffset = Vector3.new(0,4,90),
 portalOffset = Vector3.new(54,0,62), portalRadius = 14, portalUseRange = 24,
 expectedPlayers = 2, scanInterval = 0.25,
 -- Equivalent room stations: the first entrant configures a room before everyone confirms readiness.
 portals = {
  {id="Room1",name="匹配點 1",description="由房主選擇劇情、對戰或合作，準備齊全後進入新戰場。",offset=Vector3.new(54,0,62),color=Color3.fromRGB(255,176,32),
   settings={gameMode="PvP",expectedPlayers=2,size="Medium",aiCount=0,difficulty="Normal",population=100,startingResources="Standard",victory="Conquest",teamMode="FFA"}},
  {id="Room2",name="匹配點 2",description="由房主選擇劇情、對戰或合作，準備齊全後進入新戰場。",offset=Vector3.new(-54,0,4),color=Color3.fromRGB(46,196,104),
   settings={gameMode="PvP",expectedPlayers=2,size="Medium",aiCount=0,difficulty="Normal",population=100,startingResources="Standard",victory="Conquest",teamMode="FFA"}},
  {id="Room3",name="匹配點 3",description="由房主選擇劇情、對戰或合作，準備齊全後進入新戰場。",offset=Vector3.new(54,0,4),color=Color3.fromRGB(32,148,255),
   settings={gameMode="PvP",expectedPlayers=2,size="Medium",aiCount=0,difficulty="Normal",population=100,startingResources="Standard",victory="Conquest",teamMode="FFA"}},
  {id="Room4",name="匹配點 4",description="由房主選擇劇情、對戰或合作，準備齊全後進入新戰場。",offset=Vector3.new(-54,0,62),color=Color3.fromRGB(160,92,250),
   settings={gameMode="PvP",expectedPlayers=2,size="Medium",aiCount=0,difficulty="Normal",population=100,startingResources="Standard",victory="Conquest",teamMode="FFA"}},
 },
 -- 戰鬥預告片（cinematic.project.json 錄下的 77 秒影片）。videoId 是上傳到 Roblox 的影片資產 ID；
 -- 0 表示尚未上傳：大螢幕改輪播預告片字卡，大廳不顯示「觀看預告片」按鈕。
 -- 後牆左右各一面螢幕，朝向出生點；screenX 為正的一側是海報，負的一側播放影片。
 trailer = {
  videoId = 0,
  screenX = 80, screenZ = -102, screenBottom = 6, screenSize = Vector2.new(56, 31.5), screenYaw = 18,
  slideSeconds = 4.5,
 },
}
-- 大廳玩法：劇情（單人或多人合作闖關）、玩家對戰（只有真人）、合作對電腦。Sandbox 只供新手教程由伺服器建立。
-- 人數上限受四個出生點限制：真人＋電腦最多四方。
Config.GameModes = {
 order = {"Story","PvP","PvE"},
 Story = {name="劇情",title="劇情戰役",minPlayers=1,maxPlayers=3,accent=Color3.fromRGB(223,184,102),
  description="依章節闖關，單人或與好友合作；勝利後解鎖下一章。"},
 PvP = {name="對戰",title="玩家對戰",minPlayers=2,maxPlayers=4,accent=Color3.fromRGB(209,96,84),
  description="只有真人玩家，各自為戰或分隊；計入對戰紀錄。"},
 PvE = {name="合作",title="合作對電腦",minPlayers=1,maxPlayers=3,accent=Color3.fromRGB(101,190,143),
  description="自訂電腦數量與難度，單人或與好友一起對抗電腦。"},
 Sandbox = {name="練習",title="練習局",minPlayers=1,maxPlayers=1,internal=true,description="沒有對手的練習局。"},
}
-- 劇情章節：章節決定戰場、電腦、難度與勝利規則；真人玩家固定同隊。多人時電腦數量不超過剩餘出生點。
-- 解鎖以房主的進度為準；勝利的真人玩家都會記錄通關。
Config.Story = {
 chapters = {
  {id="RiverDawn",title="河灣初興",enemy="灰狼掠奪者",size="Small",aiCount=1,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",
   briefing="北方的灰狼掠奪者燒毀了河灣的漁村。重建市鎮、訓練守軍，把他們趕出河谷。",
   objective="消滅灰狼掠奪者的全部單位與建築。"},
  {id="SunOath",title="旭日之盟",enemy="赤砂軍閥",size="Medium",aiCount=1,difficulty="Normal",population=100,startingResources="Standard",victory="Regicide",
   briefing="旭日城邦請求援軍：赤砂軍閥佔據了高原古城。攻下他們的主城，軍閥就會瓦解。",
   objective="攻陷赤砂軍閥的起始市鎮中心，同時守住你的主城。"},
  {id="JadeWatch",title="青林守望",enemy="霧沼部族",size="Medium",aiCount=2,difficulty="Normal",population=150,startingResources="Standard",victory="Conquest",
   briefing="兩支霧沼部族從森林兩側包夾青林公國。先穩住經濟，再分頭擊破。",
   objective="擊敗所有霧沼部族。"},
  {id="WonderVow",title="奇觀之誓",enemy="鐵冠帝國",size="Large",aiCount=2,difficulty="Normal",population=200,startingResources="Rich",victory="Wonder",
   briefing="三國立誓共建世界奇觀，象徵新的同盟。鐵冠帝國不會坐視不管。",
   objective="建成世界奇觀並守住，或擊敗所有敵軍。"},
  {id="LastThrone",title="最後的王座",enemy="鐵冠帝國",size="Large",aiCount=2,difficulty="Hard",population=200,startingResources="Standard",victory="Conquest",
   briefing="鐵冠帝國傾全力反撲。這一戰決定河谷的命運。",
   objective="徹底消滅鐵冠帝國的大軍。"},
 },
}
-- 跨 place 對局：同一體驗內的大廳 place（起始 place）與對戰 place。兩個 ID 都填入且不同時，
-- 大廳只負責集合，每場對局傳送到對戰 place 的獨立保留伺服器；保持 0 或在 Studio 中則維持單一伺服器流程。
-- 兩個 place 發布同一份 build；伺服器依 game.PlaceId 判斷角色。
Config.Places = {
 lobbyPlaceId = 0, matchPlaceId = 0,
 ticketTtl = 600,          -- 對局票據在 MemoryStore 保存秒數
 ticketReadAttempts = 5,   -- 對戰伺服器讀取票據的嘗試次數
 teleportAttempts = 3, retryPause = 2,
 arrivalTimeout = 45,      -- 對戰伺服器等待全員抵達的秒數；逾時以已抵達的玩家開局
 travelTimeout = 60,       -- 大廳等待玩家離開伺服器的秒數；逾時視為傳送失敗並恢復房間
 returnDelay = 90,         -- 對局結束後自動送回大廳的秒數
}
Config.Map = {
 MapSize = 1024, GridSize = 8, GroundY = 0, Seed = 2718, RandomizeSeed = true,
 Sizes = { Small = 768, Medium = 1024, Large = 1536 },
 SizeNames = { Small = "小型 · 768", Medium = "標準 · 1024", Large = "大型 · 1536" },
 ResourceNodeTargets = { Small = 760, Medium = 1280, Large = 2200 },
 ResourceFootprint = 8, RoadWidth = 20,
 -- Canopies may overlap while the authoritative trunk / ore collider stays small.
 ResourceVisualFootprints = { Tree = 14, Gold = 11, Stone = 11, Berries = 11, Deer = 10, Relic = 6, Boar = 10, Sheep = 6 },
 ResourceLayout = {
  BorderMargin = 20, BaseClearance = 128, CenterClearance = 64,
  MinNodeSpacing = 12.5, ClusterSpacing = 13, ClusterSeparation = 20, OpeningRadius = 260,
  NodeJitter = 0.25, MaxClusterTilt = math.rad(2),
  NeutralTreeMin = 36, NeutralTreeMax = 72, NeutralOtherMin = 8, NeutralOtherMax = 16,
  OpeningClusters = {
   {kind="Tree",count=48}, {kind="Tree",count=40},
   {kind="Berries",count=8}, {kind="Deer",count=4}, {kind="Gold",count=9}, {kind="Stone",count=7},
  },
 },
}
-- 農田：磨坊可預先付款預置，耗盡時優先使用預置；workRange 是村民站在田中央耕作的距離。
Config.Farms = {queueLimit=40, workRange=4}
-- 駐紮（AOE2 式）：只能用專用指令（駐紮按鈕／G、Alt+右鍵、觸控模式），一般右鍵不會駐紮。單位走到建築旁進入，在裡面不會被攻擊並緩慢回復生命，仍計入人口。
-- 每次射擊多出的箭數 = 各類別駐軍人數 × arrows 權重（無條件捨去），上限為建築的 garrison.maxArrows。
-- 攻城器械不能進入；個別建築可用 garrison.blocked 再排除類別。建築被摧毀或拆除時駐軍全數離開。
Config.Garrison = {enterRange=5, healRate=1, arrows={villager=1,archer=1,infantry=0.5}, blocked={siege=true,trade=true,herd=true}}
-- 城牆一次拖曳的最大段數；城門在己方或同盟單位進入 gateOpenRadius 時升起閘門（僅外觀，通行權由伺服器判定）。
Config.Walls = {maxLine=40, gateOpenRadius=18}
Config.Settings = {
 maxPlayers = 4, gameMode = "Conquest", defaultMapSize = "Medium",
 startingResources = { food = 300, wood = 300, gold = 150, stone = 150 },
 startingVillagers = 3, populationLimit = 100, wonderVictoryTime = 180,
}
Config.Spawns = { Vector3.new(-344,0,-344), Vector3.new(344,0,344), Vector3.new(344,0,-344), Vector3.new(-344,0,344) }
Config.BuildOrder = { "TownCenter", "House", "Mill", "LumberCamp", "MiningCamp", "Barracks", "Farm", "ArcheryRange", "Stable", "Blacksmith", "Market", "Palisade", "Outpost", "Tower", "Wall", "Gate", "Castle", "SiegeWorkshop", "Monastery", "University", "Wonder" }
-- Fixed villager command pages; building availability still comes from BuildOrder and minAge.
Config.BuildPages = {
 {key="economy",name="經濟",buildings={"House","Mill","LumberCamp","MiningCamp","Farm","Market","TownCenter"}},
 {key="military",name="軍事",buildings={"Barracks","ArcheryRange","Stable","Blacksmith","SiegeWorkshop"}},
 {key="defense",name="防禦",buildings={"Palisade","Outpost","Tower","Wall","Gate","Castle","Monastery","University","Wonder"}},
}
Config.Buildings = {
 TownCenter = { name="市鎮中心", description="訓練村民、交回資源並升級時代，會射擊附近敵軍；可駐紮 15 個單位，駐軍越多射出的箭越多。城堡時代可增建。", cost={wood=275,stone=100}, hp=2400, size=Vector2.new(4,4), height=26, color=Color3.fromRGB(174,130,79), population=5, minAge=3, buildTime=25, damage=6, range=56, attackInterval=2.0, garrison={capacity=15,maxArrows=10}, dropoff={"food","wood","gold","stone"}, trains={"villager"} },
 House = { name="房屋", description="增加 5 人口上限。", cost={wood=25}, hp=550, size=Vector2.new(2,2), height=14, color=Color3.fromRGB(200,173,125), population=5, minAge=1, buildTime=8, trains={} },
 Barracks = { name="兵營", description="訓練步兵與對抗騎兵的長槍兵。", cost={wood=175}, hp=1200, size=Vector2.new(3,3), height=20, color=Color3.fromRGB(149,117,103), population=0, minAge=1, buildTime=18, trains={"infantry","spearman"} },
 Farm = { name="農田", description="提供可採集的食物；一塊農田一位村民，單位可以踩過，耗盡後可重新播種。", cost={wood=60}, hp=300, size=Vector2.new(3,3), height=1.2, walkable=true, color=Color3.fromRGB(165,141,60), population=0, minAge=1, buildTime=7, amount=700, trains={} },
 Mill = { name="磨坊", description="收集附近的食物，研究農田科技，並可預置農田供耗盡時自動重新播種。", cost={wood=100}, hp=800, size=Vector2.new(2,2), height=20, color=Color3.fromRGB(196,174,121), population=0, minAge=1, buildTime=12, dropoff={"food"}, trains={} },
 LumberCamp = { name="伐木場", description="交回木材，縮短村民往返路程。", cost={wood=100}, hp=800, size=Vector2.new(2,2), height=12, color=Color3.fromRGB(166,134,92), population=0, minAge=1, buildTime=12, dropoff={"wood"}, trains={} },
 MiningCamp = { name="採礦營地", description="交回黃金與石材。", cost={wood=100}, hp=800, size=Vector2.new(2,2), height=12, color=Color3.fromRGB(145,142,125), population=0, minAge=1, buildTime=12, dropoff={"gold","stone"}, trains={} },
 ArcheryRange = { name="射箭場", description="訓練弓箭手、反制弓兵的矛兵；城堡時代可訓練騎射手，帝王時代可訓練火槍手。", cost={wood=175}, hp=1200, size=Vector2.new(3,3), height=20, color=Color3.fromRGB(161,131,92), population=0, minAge=2, buildTime=20, trains={"archer","skirmisher","cavalryArcher","handCannoneer"} },
 Stable = { name="馬廄", description="訓練偵察騎兵與重裝騎兵；城堡時代可訓練剋制騎兵的駱駝騎兵。", cost={wood=175}, hp=1400, size=Vector2.new(4,3), height=19, color=Color3.fromRGB(172,128,89), population=0, minAge=2, buildTime=20, trains={"scout","cavalry","camel"} },
 SiegeWorkshop = { name="攻城器械廠", description="製造攻城衝車、投石車與能貫穿敵陣的弩砲；帝王時代研究化學後可製造射石砲。", cost={wood=200}, hp=1500, size=Vector2.new(4,3), height=21, color=Color3.fromRGB(144,122,99), population=0, minAge=3, buildTime=24, trains={"ram","mangonel","scorpion","bombardCannon"} },
 Monastery = { name="修道院", description="訓練僧侶：招降敵方單位並治療友軍。僧侶把聖物存放在這裡，每件聖物持續產生黃金。", cost={wood=175}, hp=1300, size=Vector2.new(3,3), height=28, color=Color3.fromRGB(218,207,165), population=0, minAge=3, buildTime=24, trains={"monk"} },
 University = { name="大學", description="研究帝國的高階軍事科技。", cost={wood=200}, hp=1500, size=Vector2.new(4,4), height=26, color=Color3.fromRGB(188,167,134), population=0, minAge=3, buildTime=24, trains={} },
 Blacksmith = { name="兵工廠", description="研究武器與護甲升級。", cost={wood=150}, hp=1100, size=Vector2.new(3,3), height=19, color=Color3.fromRGB(133,126,113), population=0, minAge=2, buildTime=18, trains={} },
 Market = { name="市集", description="交換木材、食物、石材與黃金，並訓練在市集之間往返賺取黃金的貿易車。", cost={wood=175}, hp=1300, size=Vector2.new(4,3), height=19, color=Color3.fromRGB(177,147,97), population=0, minAge=2, buildTime=20, dropoff={"food","wood","gold","stone"}, trains={"tradeCart"} },
 Tower = { name="瞭望塔", description="自動射擊進入射程的敵軍；可駐紮 5 個步行單位增加箭數。", cost={wood=50,stone=125}, hp=1500, size=Vector2.new(2,2), height=30, color=Color3.fromRGB(161,158,144), population=0, minAge=2, buildTime=22, damage=8, range=60, attackInterval=1.8, garrison={capacity=5,maxArrows=5,blocked={cavalry=true}}, trains={} },
 Wall = { name="石牆", description="封鎖狹道並保護基地；按住拖曳可一次放置整排。", cost={stone=15}, hp=1700, size=Vector2.new(1,1), height=13, color=Color3.fromRGB(169,166,150), population=0, minAge=2, buildTime=4, line=true, trains={} },
 Gate = { name="城門", description="己方與同盟部隊可自由通行，敵軍必須攻破才能進入；可直接蓋在自己的石牆上。放置時可旋轉方向。", cost={stone=30}, hp=2000, size=Vector2.new(3,1), height=16, color=Color3.fromRGB(160,156,140), population=0, minAge=2, buildTime=14, gate=true, rotatable=true, trains={} },
 Castle = { name="城堡", description="強大的基地防禦，可製造巨型投石機與本文明的專屬兵種；射程內沒有敵軍時會射擊敵方建築。可駐紮 20 個單位增加箭數。", cost={stone=650}, hp=4800, size=Vector2.new(8,8), height=48, color=Color3.fromRGB(118,128,146), population=10, minAge=3, buildTime=45, damage=14, range=75, attackInterval=1.6, attacksBuildings=true, garrison={capacity=20,maxArrows=15}, dropoff={"food","wood","gold","stone"}, trains={"trebuchet","longbowman","sunKnight","woodWarden"} },
 -- 木柵牆：黑暗時代的廉價木牆，整排放置規則與石牆相同。前哨站只提供視野，不會攻擊。
 Palisade = { name="木柵牆", description="黑暗時代就能蓋的廉價木牆，能拖延敵軍突襲；生命比石牆低。按住拖曳可一次放置整排。", cost={wood=3}, hp=300, size=Vector2.new(1,1), height=10, color=Color3.fromRGB(150,112,70), population=0, minAge=1, buildTime=2, line=true, trains={} },
 Outpost = { name="前哨站", description="便宜的木造瞭望台，提供很遠的視野，用來監視敵軍動向；不會攻擊。", cost={wood=25,stone=10}, hp=500, size=Vector2.new(1,1), height=18, color=Color3.fromRGB(158,122,82), population=0, minAge=1, buildTime=10, trains={} },
 Wonder = { name="世界奇觀", description="奇觀模式中守住完工奇觀即可勝利。", cost={wood=1000,gold=1000,stone=1000}, hp=4500, size=Vector2.new(7,7), height=57, color=Color3.fromRGB(213,197,155), population=0, minAge=4, buildTime=80, trains={} },
}
Config.Units = {
 -- 近戰射程是武器實際長度（自己中心到目標邊緣）；必須不小於碰撞半徑 + 1.5，否則站不到攻擊位置。
 villager = { name="村民", description="採集資源、建造與修復。", cost={food=50}, hp=40, speed=14, damage=3, range=3.5, trainTime=10, color=Color3.fromRGB(227,196,137), minAge=1, trainsAt={"TownCenter"}, class="villager", armor=0, attackInterval=1.6, population=1, carryCapacity=10, gatherRate=3, bonus={} },
 infantry = { name="步兵", description="便宜且可靠的近戰部隊。", cost={food=60,gold=20}, hp=75, speed=16, damage=10, range=3.5, trainTime=14, color=Color3.fromRGB(160,182,208), minAge=1, trainsAt={"Barracks"}, class="infantry", armor=1, attackInterval=1.4, population=1, bonus={building=3} },
 spearman = { name="長槍兵", description="長槍對騎兵造成額外傷害。", cost={food=35,wood=25}, hp=55, speed=16, damage=5, range=5.5, trainTime=12, color=Color3.fromRGB(173,186,167), minAge=2, trainsAt={"Barracks"}, class="infantry", armor=0, attackInterval=1.5, population=1, bonus={cavalry=22} },
 archer = { name="弓箭手", description="遠距離射擊，畏懼快速騎兵。", cost={wood=25,gold=45}, hp=40, speed=15, damage=6, range=48, trainTime=14, color=Color3.fromRGB(159,181,116), minAge=2, trainsAt={"ArcheryRange"}, class="archer", armor=0, attackInterval=1.8, population=1, bonus={infantry=1} },
 scout = { name="斥候騎兵", description="快速探索地圖與突襲村民。", cost={food=80}, hp=55, speed=27, damage=5, range=4.5, trainTime=16, color=Color3.fromRGB(167,126,78), minAge=1, trainsAt={"Stable"}, class="cavalry", mounted=true, armor=0, attackInterval=1.3, population=1, bonus={villager=2} },
 skirmisher = { name="矛兵", description="低成本遠程部隊，克制弓箭手。", cost={food=25,wood=35}, hp=40, speed=15, damage=3, range=40, trainTime=14, color=Color3.fromRGB(171,185,126), minAge=2, trainsAt={"ArcheryRange"}, class="archer", armor=2, attackInterval=1.9, population=1, bonus={archer=7} },
 cavalry = { name="騎士", description="迅速突襲經濟與遠程部隊。", cost={food=60,gold=75}, hp=125, speed=24, damage=12, range=4.5, trainTime=20, color=Color3.fromRGB(182,151,105), minAge=3, trainsAt={"Stable"}, class="cavalry", mounted=true, armor=2, attackInterval=1.5, population=1, bonus={archer=5} },
 ram = { name="攻城衝車", description="高護甲、低速度，專精摧毀建築。", cost={wood=160,gold=75}, hp=280, speed=9, damage=4, range=6.5, trainTime=25, color=Color3.fromRGB(151,127,84), minAge=3, trainsAt={"SiegeWorkshop"}, class="siege", armor=8, attackInterval=2.2, population=1, preferredTarget="buildings", bonus={building=40} },
 mangonel = { name="投石車", description="遠距投石造成範圍傷害，適合對付密集部隊。", cost={wood=160,gold=135}, hp=90, speed=10, damage=24, range=62, trainTime=28, color=Color3.fromRGB(157,134,94), minAge=3, trainsAt={"SiegeWorkshop"}, class="siege", armor=2, attackInterval=3.5, population=1, splash=12, bonus={building=18} },
 monk = { name="僧侶", description="招降敵方單位、治療受傷友軍；不會攻擊。", cost={gold=100}, hp=30, speed=11, damage=0, range=36, trainTime=30, color=Color3.fromRGB(150,104,64), minAge=3, trainsAt={"Monastery"}, class="monk", armor=0, attackInterval=1, population=1, bonus={} },
 trebuchet = { name="巨型投石機", description="極遠程攻城武器，需要軍隊保護。", cost={wood=200,gold=200}, hp=170, speed=8, damage=12, range=115, trainTime=35, color=Color3.fromRGB(165,145,97), minAge=4, trainsAt={"Castle"}, class="siege", armor=3, attackInterval=4.5, population=1, preferredTarget="buildings", bonus={building=85} },
 -- 騎射手同時屬於騎兵與遠程部隊（alsoClass）：吃兩類的科技，也會被兩類的剋制加成命中。
 cavalryArcher = { name="騎射手", description="騎馬的弓箭手，機動騷擾與拉扯；怕矛兵與長槍兵。", cost={wood=40,gold=70}, hp=55, speed=22, damage=6, range=40, trainTime=24, color=Color3.fromRGB(150,170,110), minAge=3, trainsAt={"ArcheryRange"}, class="cavalry", alsoClass="archer", mounted=true, armor=0, attackInterval=2.0, population=1, bonus={} },
 camel = { name="駱駝騎兵", description="快速的騎乘部隊，對騎兵造成大量額外傷害。", cost={food=55,gold=60}, hp=100, speed=22, damage=6, range=4.5, trainTime=20, color=Color3.fromRGB(196,160,104), minAge=3, trainsAt={"Stable"}, class="cavalry", mounted=true, armor=0, attackInterval=1.6, population=1, bonus={cavalry=9} },
 -- 貿易車不能攻擊；在兩座相距夠遠的己方／盟友市集之間往返，回到出發市集時交回黃金。
 tradeCart = { name="貿易車", description="右鍵另一座己方或盟友的市集開始往返貿易；距離越遠，每趟黃金越多。不能攻擊。", cost={wood=100,gold=50}, hp=70, speed=15, damage=0, range=4.5, trainTime=25, color=Color3.fromRGB(176,138,82), minAge=2, trainsAt={"Market"}, class="trade", armor=0, attackInterval=1, population=1, bonus={} },
 handCannoneer = { name="火槍手", description="火藥步兵，一槍重創步兵；射速慢、怕騎兵。", cost={food=45,gold=50}, hp=35, speed=14, damage=17, range=38, trainTime=26, color=Color3.fromRGB(120,104,92), minAge=4, trainsAt={"ArcheryRange"}, class="archer", armor=0, attackInterval=3.4, population=1, bonus={infantry=10} },
 -- 弩砲：弩矢貫穿目標後方直線上的敵方單位（pierce）；後方每多一個目標傷害乘上 falloff。
 scorpion = { name="弩砲", description="發射穿透弩矢的攻城器械，一箭可貫穿直線上的多名敵軍，適合對付密集的步兵與弓兵；怕騎兵近身。", cost={wood=75,gold=75}, hp=40, speed=10, damage=12, range=56, trainTime=30, color=Color3.fromRGB(150,118,78), minAge=3, trainsAt={"SiegeWorkshop"}, class="siege", armor=0, attackInterval=3.6, population=1, pierce={width=3,falloff=0.6,max=6}, bonus={} },
 -- 射石砲：需要化學（requiresTech）。對建築造成巨大傷害，射程很遠。
 bombardCannon = { name="射石砲", description="火藥攻城砲，在很遠的距離重創建築與城牆；需要先在大學研究化學。射速慢、近身脆弱。", cost={wood=225,gold=225}, hp=80, speed=8, damage=40, range=88, trainTime=40, color=Color3.fromRGB(96,92,88), minAge=4, trainsAt={"SiegeWorkshop"}, class="siege", armor=2, attackInterval=6, population=1, preferredTarget="buildings", requiresTech="Chemistry", bonus={building=160} },
 -- 綿羊（AOE2 式放牧）：不佔人口、不能訓練、不會攻擊。附近只有某一方的單位時歸那一方；
 -- 村民右鍵宰殺後變成可採集的食物（Config.Resources.Sheep）。
 sheep = { name="綿羊", description="放牧的羊群：附近沒有原主人的單位時，其他玩家靠近就會接收。可以像部隊一樣移動，村民右鍵宰殺後採集食物。", cost={}, hp=7, speed=8, damage=0, range=3.5, trainTime=1, color=Color3.fromRGB(236,232,220), minAge=1, trainsAt={}, class="herd", armor=0, attackInterval=1, population=0, bonus={} },
 -- 文明專屬兵種（civilization 欄位）：只有該文明能在城堡訓練；其他文明的城堡不顯示也不接受。
 longbowman = { name="河灣長弓手", description="河灣盟邦的專屬兵種：射程極遠的弓兵，能在敵軍接近前先削弱對方。", cost={wood=35,gold=40}, hp=35, speed=15, damage=6, range=64, trainTime=18, color=Color3.fromRGB(110,160,150), minAge=3, trainsAt={"Castle"}, class="archer", armor=0, attackInterval=2.0, population=1, civilization="RiverHaven", bonus={infantry=1} },
 sunKnight = { name="旭日聖騎", description="旭日城邦的專屬兵種：生命與護甲都很高的重騎兵，擅長衝散弓兵陣線。", cost={food=70,gold=80}, hp=150, speed=22, damage=13, range=4.5, trainTime=22, color=Color3.fromRGB(230,190,90), minAge=3, trainsAt={"Castle"}, class="cavalry", mounted=true, armor=3, attackInterval=1.6, population=1, civilization="Sunspire", bonus={archer=4} },
 woodWarden = { name="青林林卒", description="青林公國的專屬兵種：行動迅速的輕步兵，擅長突襲建築與攻城器械。", cost={food=65,gold=25}, hp=70, speed=21, damage=9, range=3.5, trainTime=12, color=Color3.fromRGB(110,160,90), minAge=3, trainsAt={"Castle"}, class="infantry", armor=0, attackInterval=1.2, population=1, civilization="JadeGrove", bonus={building=8,siege=6} },
}
-- Shared gameplay volumes; decorative limbs, weapons and wheels do not collide.
Config.UnitCollision = {
 default={radius=2,height=5},
 profiles={
  villager={radius=2,height=5}, infantry={radius=2,height=5}, archer={radius=2,height=5},
  cavalry={radius=3,height=7}, siege={radius=4,height=5}, monk={radius=2,height=5}, trade={radius=3,height=5}, herd={radius=2,height=4},
 },
}
-- 陣形偏好及幾何同時供客戶端顯示與伺服器驗證；位置由伺服器計算。
Config.Formations = {
 default="Box", maxSelectedUnits=200, gap=0.5, arrivalTolerance=0.1, spreadMultiplier=1.8, obstacleSearchRings=4,
 order={"Box","Line","Column","Wedge","Spread"},
 types={
  Box={name="方陣",description="緊密方陣；改為列隊移動，適合集中部隊。"},
  Line={name="橫列",description="朝行進方向展開橫列；改為列隊移動。"},
  Column={name="縱隊",description="沿行進方向排成縱隊；改為列隊移動。"},
  Wedge={name="楔形",description="前窄後寬的楔形；改為列隊移動。"},
  Spread={name="散開",description="擴大部隊間距；改為列隊移動。"},
 },
}
-- 僧侶：AOE2 式招降（至少 4 秒、之後每秒 28% 機率、10 秒必定成功），成功後信仰需 25 秒恢復。
Config.Monk = { maxFaith=100, rechargeTime=25, convertMin=4, convertMax=10, convertChance=0.28, healRate=2, healRange=18, autoHealRadius=48 }
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
 GoldMining = { name="金礦開採", description="村民採集黃金 +15%。", cost={food=100,wood=75}, time=18, minAge=2, building="MiningCamp", effect={gatherGold=0.15}, unitClass="villager" },
 StoneMining = { name="石礦開採", description="村民採集石材 +15%。", cost={food=100,wood=75}, time=18, minAge=2, building="MiningCamp", effect={gatherStone=0.15}, unitClass="villager" },
 BowSaw = { name="弓鋸", description="村民伐木效率再 +20%。", cost={food=150,wood=100}, time=22, minAge=3, building="LumberCamp", requires="DoubleBitAxe", effect={gatherWood=0.2}, unitClass="villager" },
 HandCart = { name="手拉車", description="村民採集 +15%、攜帶量 +5、速度 +10%。", cost={food=300,wood=200}, time=30, minAge=3, building="TownCenter", requires="Wheelbarrow", effect={gather=0.15,carry=5,speed=0.1}, unitClass="villager" },
 Bloodlines = { name="血統", description="騎兵生命 +20。", cost={food=150,gold=100}, time=22, minAge=2, building="Stable", effect={hp=20}, unitClass="cavalry" },
 ScaleBarding = { name="鱗甲馬鎧", description="騎兵護甲 +1。", cost={food=150}, time=20, minAge=2, building="Blacksmith", effect={armor=1}, unitClass="cavalry" },
 Squires = { name="侍從", description="步兵移動速度 +10%。", cost={food=200}, time=20, minAge=3, building="Barracks", effect={speed=0.1}, unitClass="infantry" },
 BodkinArrow = { name="錐頭箭", description="遠程部隊攻擊 +1、射程 +4。", cost={food=200,gold=100}, time=24, minAge=3, building="Blacksmith", requires="Fletching", effect={attack=1,range=4}, unitClass="archer" },
 Fervor = { name="狂熱", description="僧侶移動速度 +15%。", cost={gold=140}, time=20, minAge=3, building="Monastery", effect={speed=0.15}, unitClass="monk" },
 Sanctity = { name="神聖", description="僧侶生命 +15。", cost={gold=120}, time=20, minAge=3, building="Monastery", effect={hp=15}, unitClass="monk" },
 Conscription = { name="徵兵制度", description="所有建築訓練時間減少 20%。", cost={food=150,gold=150}, time=20, minAge=4, building="Castle", effect={trainSpeed=0.2} },
 Caravan = { name="商隊", description="貿易車移動速度 +50%。", cost={food=200,gold=200}, time=25, minAge=3, building="Market", effect={speed=0.5}, unitClass="trade" },
 -- 兵種升級（AOE2 式）：只影響 upgrade.unit 這一種單位，完成後現有與之後訓練的單位都改名並提升數值。
 -- upgrade 欄位：hp／attack／armor／range 為加值，speed／interval 為比例，bonus 為對各類別的額外傷害加值。
 LongSwordsman = { name="長劍兵", description="步兵升級為長劍兵：生命 +20、攻擊 +3。", cost={food=200,gold=65}, time=25, minAge=3, building="Barracks", upgrade={unit="infantry",name="長劍兵",hp=20,attack=3} },
 Champion = { name="冠軍劍士", description="長劍兵升級為冠軍劍士：生命 +10、攻擊 +2、護甲 +1。", cost={food=750,gold=350}, time=35, minAge=4, building="Barracks", requires="LongSwordsman", upgrade={unit="infantry",name="冠軍劍士",hp=10,attack=2,armor=1} },
 Pikeman = { name="長戟兵", description="長槍兵升級為長戟兵：生命 +15、攻擊 +1、對騎兵額外傷害 +10。", cost={food=215,gold=90}, time=25, minAge=3, building="Barracks", upgrade={unit="spearman",name="長戟兵",hp=15,attack=1,bonus={cavalry=10}} },
 Crossbowman = { name="弩手", description="弓箭手升級為弩手：生命 +5、攻擊 +1、射程 +4。", cost={food=125,gold=75}, time=25, minAge=3, building="ArcheryRange", upgrade={unit="archer",name="弩手",hp=5,attack=1,range=4} },
 Arbalester = { name="重弩手", description="弩手升級為重弩手：生命 +5、攻擊 +1、攻擊間隔減少 10%。", cost={food=350,gold=300}, time=35, minAge=4, building="ArcheryRange", requires="Crossbowman", upgrade={unit="archer",name="重弩手",hp=5,attack=1,interval=0.1} },
 EliteSkirmisher = { name="精銳矛兵", description="矛兵升級為精銳矛兵：生命 +5、攻擊 +1、對遠程部隊額外傷害 +2。", cost={wood=230,gold=130}, time=25, minAge=3, building="ArcheryRange", upgrade={unit="skirmisher",name="精銳矛兵",hp=5,attack=1,bonus={archer=2}} },
 LightCavalry = { name="輕騎兵", description="斥候騎兵升級為輕騎兵：生命 +20、攻擊 +2、護甲 +1。", cost={food=150,gold=50}, time=25, minAge=3, building="Stable", upgrade={unit="scout",name="輕騎兵",hp=20,attack=2,armor=1} },
 Cavalier = { name="遊俠騎士", description="騎士升級為遊俠騎士：生命 +20、攻擊 +2。", cost={food=300,gold=300}, time=35, minAge=4, building="Stable", upgrade={unit="cavalry",name="遊俠騎士",hp=20,attack=2} },
 HeavyCamel = { name="重裝駱駝騎兵", description="駱駝騎兵升級為重裝駱駝騎兵：生命 +20、攻擊 +2。", cost={food=325,gold=360}, time=35, minAge=4, building="Stable", upgrade={unit="camel",name="重裝駱駝騎兵",hp=20,attack=2} },
 HeavyCavalryArcher = { name="重裝騎射手", description="騎射手升級為重裝騎射手：生命 +10、攻擊 +1、護甲 +1。", cost={food=900,gold=500}, time=35, minAge=4, building="ArcheryRange", upgrade={unit="cavalryArcher",name="重裝騎射手",hp=10,attack=1,armor=1} },
 CappedRam = { name="加蓋衝車", description="攻城衝車升級為加蓋衝車：生命 +70、對建築額外傷害 +15。", cost={food=300,gold=200}, time=35, minAge=4, building="SiegeWorkshop", upgrade={unit="ram",name="加蓋衝車",hp=70,bonus={building=15}} },
 -- 防禦與經濟科技（AOE2 式）：建築生命／護甲、施工速度、瞭望塔、建築視野、駐軍治療與進貢手續費。
 Masonry = { name="石工術", description="所有建築生命 +10%、護甲 +1。", cost={food=175,stone=150}, time=30, minAge=3, building="University", effect={buildingHp=0.1,buildingArmor=1} },
 Architecture = { name="建築學", description="所有建築生命再 +10%、護甲再 +1。", cost={food=300,wood=200}, time=40, minAge=4, building="University", requires="Masonry", effect={buildingHp=0.1,buildingArmor=1} },
 TreadmillCrane = { name="踏車起重機", description="村民施工速度 +20%。", cost={food=200,wood=300}, time=25, minAge=3, building="University", effect={buildSpeed=0.2} },
 GuardTower = { name="箭樓", description="瞭望塔攻擊 +3、射程 +8。", cost={food=100,stone=250}, time=30, minAge=3, building="University", effect={towerAttack=3,towerRange=8} },
 TownWatch = { name="城鎮守望", description="所有建築視野 +30%，更早發現來襲的敵軍。", cost={food=75}, time=15, minAge=2, building="TownCenter", effect={buildingVision=0.3} },
 HerbalMedicine = { name="草藥學", description="駐紮在建築裡的單位回復生命的速度變為 4 倍。", cost={gold=350}, time=25, minAge=3, building="Monastery", effect={garrisonHeal=3} },
 Coinage = { name="鑄幣", description="進貢給盟友的手續費減半。", cost={food=200,gold=100}, time=25, minAge=2, building="Market", effect={tributeFeeCut=0.5} },
 Banking = { name="銀行業", description="進貢不再收取手續費。", cost={food=300,gold=200}, time=30, minAge=3, building="Market", requires="Coinage", effect={tributeFeeCut=0.5} },
 Onager = { name="野戰投石車", description="投石車升級為野戰投石車：攻擊 +8、射程 +8。", cost={food=800,gold=500}, time=40, minAge=4, building="SiegeWorkshop", upgrade={unit="mangonel",name="野戰投石車",attack=8,range=8} },
}
Config.TechnologyOrder = { "Loom", "Wheelbarrow", "HandCart", "DoubleBitAxe", "BowSaw", "GoldMining", "StoneMining", "HorseCollar", "HeavyPlow", "Forging", "Armor", "ScaleBarding", "Fletching", "BodkinArrow", "ThumbRing", "Bloodlines", "Squires", "Fervor", "Sanctity", "Chemistry", "Conscription", "Caravan",
 "TownWatch", "Masonry", "Architecture", "TreadmillCrane", "GuardTower", "HerbalMedicine", "Coinage", "Banking",
 "LongSwordsman", "Champion", "Pikeman", "Crossbowman", "Arbalester", "EliteSkirmisher", "HeavyCavalryArcher", "LightCavalry", "Cavalier", "HeavyCamel", "CappedRam", "Onager" }
Config.Resources = {
 Tree = { resource="wood", name="樹木", amount=500, color=Color3.fromRGB(64,114,68), height=18 },
 Gold = { resource="gold", name="金礦", amount=800, color=Color3.fromRGB(202,168,70), height=6 },
 Stone = { resource="stone", name="石礦", amount=650, color=Color3.fromRGB(134,144,153), height=7 },
 Berries = { resource="food", name="漿果叢", amount=400, color=Color3.fromRGB(157,67,84), height=5 },
 -- 獵物：每頭食物較少，但村民採集速度是 gatherMultiplier 倍；靜止不逃跑。
 Deer = { resource="food", name="鹿", amount=150, color=Color3.fromRGB(168,118,72), height=6, gatherMultiplier=1.6, hunt=true },
 -- 野豬：食物多，但村民要先合力打倒牠（boar.hp），期間牠會反擊靠近的單位。
 Boar = { resource="food", name="野豬", amount=340, color=Color3.fromRGB(92,70,58), height=5, gatherMultiplier=1.6, hunt=true,
  boar={hp=60, armor=0, damage=3, attackInterval=2, reach=7} },
 -- 宰殺後的綿羊；尚未有主人時是可接收的中立羊群（Herdable），不能直接採集。
 Sheep = { resource="food", name="綿羊", amount=100, color=Color3.fromRGB(236,232,220), height=4, gatherMultiplier=1.6, hunt=true },
}
Config.MatchModes = { Conquest="征服", Regicide="主城決戰", Wonder="奇觀", Relic="聖物" }
Config.AIDifficulties = { Easy="簡單", Normal="普通", Hard="困難" }
-- 市集浮動價格（AOE2 式）：所有玩家共用；每 batch 單位的基準價 basePrice 黃金，買入價 = 基準 × buyMarkup，
-- 賣出價 = 基準 × sellMarkdown。每次買入基準價 +step、賣出 −step，限制在 minPrice～maxPrice。
-- buyGold／sellGold 是開局（基準價）時的報價，保留給舊測試與說明。
Config.MarketTrade = { batch=100, buyGold=130, sellGold=70, basePrice=100, buyMarkup=1.3, sellMarkdown=0.7, step=3, minPrice=20, maxPrice=1000 }
-- 進貢：需要己方已完工的市集；每次 amounts 其中一個數量，另付 fee 比例的手續費（鑄幣／銀行業可減免）。
Config.Tribute = { amounts={100,500}, fee=0.3, resources={"food","wood","gold","stone"} }
-- 單位姿態（AOE2 式）：攻擊＝自動索敵並追擊；防守＝只追擊短距離後回到原位；堅守＝不移動、只打射程內的敵人；不攻擊＝不索敵也不反擊。
Config.Stances = {
 default="Aggressive", order={"Aggressive","Defensive","StandGround","NoAttack"},
 defensiveLeash=36,
 types={
  Aggressive={name="攻擊姿態",short="攻擊",description="自動攻擊視野內的敵人並追擊。"},
  Defensive={name="防守姿態",short="防守",description="攻擊靠近的敵人，追擊一小段距離後回到原位。"},
  StandGround={name="堅守姿態",short="堅守",description="站在原地不移動，只攻擊射程內的敵人。"},
  NoAttack={name="不攻擊",short="不攻擊",description="不會主動攻擊，被打也不還手；適合撤退或偵察。"},
 },
}
-- 戰爭迷霧（客戶端顯示）：cell 為格子大小；radius 為各單位／建築的視野半徑（studs）。盟友共享視野。
-- 未探索區域是黑色；探索過但目前看不到的區域變暗，看不到其中的敵方單位。
Config.Vision = {
 enabled=true, cell=16, refresh=0.25,
 unitDefault=44, buildingDefault=40,
 units={villager=34, scout=88, cavalry=52, cavalryArcher=56, camel=50, monk=40, tradeCart=36, sheep=16, archer=52, skirmisher=50, handCannoneer=48,
  mangonel=56, trebuchet=60, scorpion=56, bombardCannon=60, ram=24},
 buildings={TownCenter=80, Castle=96, Tower=84, Outpost=128, House=28, Farm=20, Wall=16, Palisade=12, Gate=20, Wonder=60},
}
-- 羊群與野豬：開局每方 startSheep 隻已歸屬的綿羊；另在出生點附近對稱放置中立羊群與野豬。
-- 綿羊在 claimRadius 內只有一方的單位時歸那一方；已有主人的羊只有在附近沒有主人或盟友單位時才會被敵人帶走。
Config.Herds = { startSheep=4, neutralPairs=2, boars=2, claimRadius=14, checkInterval=0.4,
 sheepRing={min=170,max=230}, boarRing={min=140,max=190} }
-- 貿易車：每趟黃金 = 距離 × goldPerStud + 距離² × goldPerStudSquared（無條件捨去），盟友市集再加 allyBonus。
-- 兩座市集中心距離小於 minDistance 時不能貿易。
Config.Trade = { minDistance=160, goldPerStud=0.08, goldPerStudSquared=1/12000, allyBonus=0.25 }
-- 聖物：開局放在出生點之間的軸線上（較大地圖另含中心點），對每個出生點的距離對稱。
-- 只有僧侶能拾取；存放在己方已完工的修道院，每件每秒產生 goldPerSecond 黃金。
-- 攜帶者陣亡或修道院被摧毀時聖物掉落在原地。axisRadii 是相對於地圖半寬的距離。
Config.Relics = { name="聖物", description="僧侶右鍵拾取，帶回自己的修道院存放後每秒產生黃金。攜帶者陣亡時會掉落。",
 -- 聖物勝利：同一隊存放全圖所有聖物並守住 victoryTime 秒即獲勝。
 -- reserve：地圖生成時，聖物點周圍這個半徑內不放樹林與礦，聖物一定落在對稱點上、四周開闊可抵達。
 goldPerSecond=0.5, victoryTime=180, reserve=36, counts={Small=4,Medium=5,Large=9}, axisRadii={Small={0.55},Medium={0.55},Large={0.38,0.72}}, clearance=10, size=4 }
-- 文明身份免費選擇；身份本身不帶數值，加成只來自 Config.CivilizationBonuses，購買永遠不改變它們。
Config.CivilizationOrder = { "RiverHaven", "Sunspire", "JadeGrove" }
Config.DefaultCivilization = "RiverHaven"
-- 文明身份（名稱、徽記、色彩）；對戰加成另見 Config.CivilizationBonuses。
Config.Civilizations = {
 RiverHaven = { name="河灣盟邦", description="沿河而建的商旅城邦，以藍青旗幟集結盟友。", emblem="川", accent=Color3.fromRGB(83,192,195), public=true },
 Sunspire = { name="旭日城邦", description="立於高原的日耀城邦，以金色旗幟守護家園。", emblem="日", accent=Color3.fromRGB(240,187,83), public=true },
 JadeGrove = { name="青林公國", description="與森林相伴的山林公國，以翠綠旗幟記錄傳承。", emblem="森", accent=Color3.fromRGB(130,190,123), public=true },
}
-- 文明加成（AOE2 式）：三個文明都免費選擇；每個文明 2 項開局加成與 1 種城堡專屬兵種。
-- 加成沿用科技的效果欄位（effect、unitClass），開局時套用一次。付費商品不能改變這裡的任何數值（CommerceRules 稽核）。
Config.CivilizationBonuses = {
 RiverHaven = { uniqueUnit="longbowman", bonuses={
  {text="貿易車每趟黃金 +20%。", effect={tradeGold=0.2}},
  {text="村民攜帶量 +3。", effect={carry=3}, unitClass="villager"},
 }},
 Sunspire = { uniqueUnit="sunKnight", bonuses={
  {text="村民採集黃金 +15%。", effect={gatherGold=0.15}, unitClass="villager"},
  {text="所有建築生命 +10%。", effect={buildingHp=0.1}},
 }},
 JadeGrove = { uniqueUnit="woodWarden", bonuses={
  {text="村民伐木 +15%。", effect={gatherWood=0.15}, unitClass="villager"},
  {text="步兵移動速度 +10%。", effect={speed=0.1}, unitClass="infantry"},
 }},
}
-- 單項加成的上限：比例效果不超過 limits.ratio，攜帶量等加值不超過 limits.flat。
Config.CivilizationBonusLimits = { ratio=0.25, flat=5, perCivilization=2 }
Config.Commerce = {
 enabled=false,
 catalog={}, -- Add only real, configured cosmetic passes before enabling; purchases never change CivilizationBonuses.
 policyText="付費僅限文明身份與造型；不販售資源、加速、人口或戰鬥優勢。",
}
return Config
