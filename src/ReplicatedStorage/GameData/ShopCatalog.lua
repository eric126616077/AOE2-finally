-- 王國商店資料：金冠（遊戲幣）、外觀、Robux 商品與通行證。
-- 原則：付費與免費都只換外觀或大廳展示。這裡不得出現資源、人口、加速、生命、攻擊或任何對戰數值；
-- ShopRules.audit 在伺服器啟動時以白名單檢查每個欄位，違反時伺服器拒絕啟動。
-- 沒有隨機抽獎：每個商品都標明內容與價格。
local Catalog = {}

Catalog.currency = {name="金冠", icon="♛"}
Catalog.policyText = "所有商品只改變外觀與大廳展示，不販售資源、加速、人口或任何對戰優勢。金冠可以免費透過遊玩取得。"
-- 每日重置以臺灣時間午夜為準（UTC+8）。
Catalog.dayOffsetHours = 8
Catalog.maxCrowns = 10000000

-- 外觀欄位與預設值；預設外觀永遠免費擁有。
Catalog.slots = {
 {id="unitSkin", name="部隊塗裝", default="skin_standard", description="改變單位的鎧甲、金屬與皮革配色；隊伍顏色不變，敵我依然一眼可辨。"},
 {id="buildingStyle", name="城鎮風格", default="style_village", description="改變建築的牆面、屋頂與石材配色；隊伍顏色與建築外形不變。"},
 {id="title", name="稱號", default="title_none", description="顯示在大廳角色頭上與對戰勢力列表。"},
 {id="trail", name="大廳拖尾", default="trail_none", description="在大廳庭院行走時留下的光帶。"},
 {id="victory", name="勝利慶典", default="victory_none", description="獲勝時在你的市鎮中心上方施放，所有玩家都看得到。"},
}

-- source：default 預設擁有｜shop 金冠購買｜vip 王室通行證｜milestone 成就解鎖｜bundle 禮包限定
-- 配色鍵對應 ArtKit 的共用色票；未列出的顏色與隊伍色零件保持原樣。
local rgb = Color3.fromRGB
Catalog.items = {
 -- 部隊塗裝
 skin_standard = {slot="unitSkin", name="標準鐵甲", source="default", description="王國軍的制式鐵甲。", look={palette={}}},
 skin_gilded = {slot="unitSkin", name="鍍金鎧甲", source="shop", price=400, description="閃耀的金色鎧甲與深色皮革。",
  look={palette={steel=rgb(222,182,78), iron=rgb(170,128,52), leather=rgb(70,44,30)}, material={steel="Foil", iron="Metal"}}},
 skin_obsidian = {slot="unitSkin", name="黑曜戰甲", source="shop", price=400, description="以黑曜石打磨的暗色重甲。",
  look={palette={steel=rgb(58,60,70), iron=rgb(34,36,44), gold=rgb(150,160,182), leather=rgb(44,36,34)}, material={steel="Metal"}}},
 skin_frost = {slot="unitSkin", name="霜銀甲冑", source="shop", price=300, description="北境工匠鍛造的銀白甲冑。",
  look={palette={steel=rgb(214,232,240), iron=rgb(150,176,196), leather=rgb(120,104,92)}, material={steel="Metal"}}},
 skin_royal = {slot="unitSkin", name="王室禮甲", source="vip", description="王室通行證專屬：紫金禮儀鎧甲。",
  look={palette={steel=rgb(196,170,226), iron=rgb(104,74,140), gold=rgb(255,214,96), leather=rgb(76,44,92)}, material={steel="Foil"}}},
 skin_veteran = {slot="unitSkin", name="百戰鏽甲", source="milestone", description="累積 10 場玩家對戰勝利解鎖。",
  look={palette={steel=rgb(150,112,82), iron=rgb(104,74,54), leather=rgb(84,58,40)}, material={steel="CorrodedMetal"}}},

 -- 城鎮風格
 style_village = {slot="buildingStyle", name="暖陽村落", source="default", description="溫暖的灰泥牆與紅瓦屋頂。", look={palette={}}},
 style_desert = {slot="buildingStyle", name="沙岩城郭", source="shop", price=500, description="砂岩牆面與赭紅陶瓦。",
  look={palette={plaster=rgb(226,196,146), wallShade=rgb(204,170,118), stone=rgb(196,160,112), paleStone=rgb(230,204,160), tile=rgb(196,110,62), tileDark=rgb(160,84,48)}, material={stone="Sandstone", paleStone="Sandstone"}}},
 style_snow = {slot="buildingStyle", name="雪境木屋", source="shop", price=500, description="深色原木、藍灰屋頂與覆雪石牆。",
  look={palette={plaster=rgb(236,240,246), wallShade=rgb(206,214,226), tile=rgb(84,108,140), tileDark=rgb(62,84,112), thatch=rgb(220,226,234), thatchDark=rgb(184,194,208), timber=rgb(70,50,40), stone=rgb(176,184,196)}}},
 style_marble = {slot="buildingStyle", name="大理石宮殿", source="shop", price=800, description="白色大理石與青銅屋頂。",
  look={palette={plaster=rgb(244,242,236), wallShade=rgb(226,222,214), stone=rgb(220,218,212), paleStone=rgb(248,246,240), tile=rgb(74,140,128), tileDark=rgb(56,112,102), roof=rgb(74,140,128)}, material={stone="Marble", paleStone="Marble", plaster="Marble"}}},
 style_royal = {slot="buildingStyle", name="王冠金頂", source="vip", description="王室通行證專屬：深紫屋頂與金色石材。",
  look={palette={tile=rgb(92,58,130), tileDark=rgb(70,42,104), thatch=rgb(110,74,150), thatchDark=rgb(84,54,118), roof=rgb(92,58,130), paleStone=rgb(232,206,132)}}},
 style_epic = {slot="buildingStyle", name="史詩城塞", source="milestone", description="通關全部劇情章節解鎖。",
  look={palette={plaster=rgb(190,182,170), wallShade=rgb(160,152,142), stone=rgb(112,108,104), paleStone=rgb(150,146,140), tile=rgb(48,52,60), tileDark=rgb(36,38,44), roof=rgb(48,52,60)}, material={stone="Slate"}}},

 -- 稱號
 title_none = {slot="title", name="不顯示", source="default", description="不顯示稱號。", look={text="", color=rgb(255,255,255)}},
 title_lord = {slot="title", name="新任領主", source="default", description="每位玩家都有的起始稱號。", look={text="新任領主", color=rgb(232,222,196)}},
 title_builder = {slot="title", name="築城大師", source="shop", price=150, description="給熱愛蓋城的你。", look={text="築城大師", color=rgb(214,180,120)}},
 title_strategist = {slot="title", name="戰略家", source="shop", price=250, description="運籌帷幄，決勝千里。", look={text="戰略家", color=rgb(120,196,236)}},
 title_conqueror = {slot="title", name="征服者", source="shop", price=600, description="讓對手記住你的名字。", look={text="征服者", color=rgb(236,96,84)}},
 title_pioneer = {slot="title", name="開拓先鋒", source="bundle", description="新手禮包限定。", look={text="開拓先鋒", color=rgb(124,214,140)}},
 title_royal = {slot="title", name="王室貴族", source="vip", description="王室通行證專屬，帶有王冠標記。", look={text="王室貴族", color=rgb(255,206,84), crown=true}},
 title_hero = {slot="title", name="河谷英雄", source="milestone", description="通關全部劇情章節解鎖。", look={text="河谷英雄", color=rgb(240,190,92)}},
 title_veteran = {slot="title", name="常勝將軍", source="milestone", description="累積 10 場玩家對戰勝利解鎖。", look={text="常勝將軍", color=rgb(255,128,96)}},

 -- 大廳拖尾
 trail_none = {slot="trail", name="無", source="default", description="不顯示拖尾。", look={colors={}}},
 trail_gold = {slot="trail", name="金色光輝", source="shop", price=200, description="一道溫暖的金光。", look={colors={rgb(255,222,120), rgb(255,170,40)}, light=0.8}},
 trail_petals = {slot="trail", name="翠林花瓣", source="bundle", description="新手禮包限定的青綠花光。", look={colors={rgb(150,236,160), rgb(255,160,210)}, light=0.5}},
 trail_flame = {slot="trail", name="烈焰之路", source="shop", price=350, description="腳下燃起火焰般的光帶。", look={colors={rgb(255,200,80), rgb(230,60,30)}, light=1}},
 trail_sky = {slot="trail", name="晴空流光", source="shop", price=200, description="清爽的藍白光帶。", look={colors={rgb(200,240,255), rgb(64,160,255)}, light=0.7}},
 trail_royal = {slot="trail", name="王室星塵", source="vip", description="王室通行證專屬的紫金星塵。", look={colors={rgb(255,214,96), rgb(150,90,230)}, light=1}},

 -- 勝利慶典
 victory_none = {slot="victory", name="無", source="default", description="不施放勝利特效。", look={kind="none", colors={}}},
 victory_fireworks = {slot="victory", name="煙火慶典", source="shop", price=300, description="五彩煙火在主城上空綻放。", look={kind="fireworks", colors={rgb(255,90,90), rgb(255,214,64), rgb(90,200,255), rgb(160,255,140)}}},
 victory_coins = {slot="victory", name="金幣雨", source="shop", price=450, description="金幣從天而降。", look={kind="coins", colors={rgb(255,214,64), rgb(255,170,40)}}},
 victory_flame = {slot="victory", name="巨龍之焰", source="shop", price=600, description="主城噴發沖天烈焰。", look={kind="flame", colors={rgb(255,220,110), rgb(240,90,30)}}},
 victory_royal = {slot="victory", name="王冠禮炮", source="vip", description="王室通行證專屬的紫金禮炮。", look={kind="fireworks", colors={rgb(255,214,96), rgb(176,110,255), rgb(255,255,255)}}},
}

-- Robux 開發者商品。productId 由使用者在 Creator Hub 建立後填入；0 代表尚未上架，按鈕會停用。
-- 建議售價僅供設定參考，實際價格以 Creator Hub 為準。
Catalog.products = {
 {id="crowns_small", name="一袋金冠", crowns=100, productId=0, suggestedRobux=49},
 {id="crowns_medium", name="一箱金冠", crowns=550, bonus="多 10%", productId=0, suggestedRobux=249},
 {id="crowns_large", name="一車金冠", crowns=1200, bonus="多 20%", productId=0, suggestedRobux=499},
 {id="crowns_treasury", name="王國寶庫", crowns=2600, bonus="多 30%", productId=0, suggestedRobux=999},
 {id="starter", name="新手禮包", crowns=300, items={"title_pioneer","trail_petals"}, once=true, productId=0, suggestedRobux=99,
  description="300 金冠＋限定稱號「開拓先鋒」＋限定拖尾「翠林花瓣」。每個帳號限購一次。"},
}

-- 通行證：只解鎖外觀與每日登入金冠加成（金冠只能買外觀）。
Catalog.passes = {
 vip = {name="王室通行證", gamePassId=0, suggestedRobux=299, dailyBonusPercent=50,
  items={"skin_royal","style_royal","title_royal","trail_royal","victory_royal"},
  description="5 款王室專屬外觀，每日登入金冠多 50%。不提供任何對戰加成。"},
}

-- 免費取得金冠的方式。
Catalog.rewards = {
 daily = {20,25,30,40,50,60,120}, -- 連續登入第 1–7 天；第 7 天後重新循環，中斷一天從第 1 天開始。
 matchBase = 25, -- 完整打完一場（劇情、對戰或合作）
 matchWin = 25, -- 勝利額外
 pvpWin = 15, -- 玩家對戰勝利再額外
 firstWin = 50, -- 每日首勝（不受每日上限限制）
 minMatchSeconds = 300, -- 少於 5 分鐘的對局不給對局獎勵，避免刷局
 dailyMatchCap = 300, -- 每日從對局取得的金冠上限
 modes = {Story=true, PurePvP=true, AIPractice=true}, -- 無對手的練習局不給獎勵
}

-- 一次性成就：每個帳號只發一次。
Catalog.milestones = {
 welcome = {name="新手起步", crowns=100},
 story1 = {name="劇情第 1 章", crowns=60},
 story2 = {name="劇情第 2 章", crowns=60},
 story3 = {name="劇情第 3 章", crowns=60},
 story4 = {name="劇情第 4 章", crowns=60},
 story5 = {name="劇情全破", crowns=150, items={"title_hero","style_epic"}},
 pvp10 = {name="10 場對戰勝利", crowns=100, items={"title_veteran","skin_veteran"}},
 starter = {name="新手禮包", crowns=0}, -- 只記錄已購買，避免重複販售
}

return Catalog
