# 替代模型美術規範（Art* 模組）

原型用的原創零件模型；不使用網格、貼圖、Union 或外部資產。目標是「溫暖的童話桌遊模型」：比例厚實、輪廓清楚、從俯視鏡頭一眼分得出種類。

## 模組

| 檔案 | 內容 |
| --- | --- |
| `Shared/ArtKit.lua` | 共用色盤與基本形狀。**凍結**：建造模組只讀不改，需要新輔助函式時寫在自己的模組內。 |
| `Shared/ArtBuildingsA.lua` | TownCenter, House, Barracks, ArcheryRange, Stable, Blacksmith, Market, SiegeWorkshop, University |
| `Shared/ArtBuildingsB.lua` | Monastery, Mill, LumberCamp, MiningCamp, Tower, Wall, Castle, Wonder, Farm |
| `Shared/ArtUnits.lua` | 11 種單位、村民工具、背負物 |
| `Shared/ArtNature.lua` | Tree, Gold, Stone, Berries（含耗損階段） |
| `Shared/Art.lua` | 公開 API：`Create / SetTool / SetCarry / ResourceStage / ApplyPlayerColor / AddPlayerMarker` |

每個建造函式簽名為 `B.Kind=function(model,kind,team,stage)`，以 `K.block` 等把零件加到 `model`。

## 座標與鏡頭

- 單位為 studs，`y=0` 是地面。建築正面朝 **+Z**；單位正面朝 **−Z**。
- 遊戲鏡頭是高角度俯視，從 +Z 往 −Z 看（預覽圖最左欄）。屋頂、+Z 立面與前院占了玩家看到的絕大部分，細節要放在這些地方；背面（−Z）與底部幾乎看不到。
- 鏡頭很遠：小於約 0.3 studs 的細節看不見，不要浪費零件。

## 色盤（`ArtKit`）

牆 `plaster` / `wallShade`、石 `stone` / `paleStone`、木 `timber`（深）/ `cutWood`（淺）、金屬 `iron` / `steel` / `gold`、暗部 `dark`、植物 `leaf` / `leafDark` / `leafLight`、土 `earth`、稻草 `straw`、皮膚 `skin`、皮革 `leather`。

屋頂三個家族，用來區分建築類別：

- `tile`（紅陶瓦）：市政與軍事廳舍。
- `thatch`（茅草）：住家、農業與採集工棚。
- `roof`（石板灰藍）：石造防禦與宗教建築。

可以在模組內定義少量自己的顏色，但應與上述色盤同色溫（偏暖、低飽和），不要引入鮮豔的純色。

## 玩家色

玩家色是**點綴**，不是整棟建築：旗幟、盾牌、遮陽篷、屋脊、窗板、風車帆。屋頂面（`RoofTile`）一律用屋頂家族色。零件名稱在 `teamColorNames` 內的才會被染色：`Banner Flag Shield Ridge Awning CanvasSail TeamTrim Shutter Bullseye Tabard Saddle HatBand HorseCloth SiegeBanner Sling Cuff TeamPatch Roof`。每個模型至少要有兩個從俯視鏡頭看得到的玩家色零件。村民的 `Body` 另由程式標成玩家色。

## 形狀規則

- `Ball` 只能等邊（用 `K.ball`）；圓柱用 `K.round`（直立）／`K.disc`（面朝 Z）／`K.plate`（面朝 X）。
- `WedgePart`：高的一邊在 +Z，斜面朝 −Z。不要用 CornerWedgePart、網格或 Union。
- `K.roofAt(model,center,width,depth,height,color,wallColor,axis)`：山牆屋頂，屋脊預設沿 X；`axis="z"` 時沿 Z。`K.cone` 是圓塔用的階梯圓錐。
- 模型必須站在 `y>=0`，不要有懸空或穿到地下的零件。

## 建築

`ModelFactory` 會把模型等比例縮放進「占地 × 高度」的盒子，取三軸中最小的比例。所以模型的長寬高比例要貼近下表，否則會被縮小而顯得又小又空。設計時直接照這個尺寸做，X 與 Z 至少填滿 90%，Y 不超過高度。

| 建築 | X × Y × Z | 零件上限 |
| --- | --- | --- |
| TownCenter | 32 × 26 × 32 | 100 |
| House | 16 × 14 × 16 | 60 |
| Barracks | 24 × 20 × 24 | 85 |
| ArcheryRange | 24 × 20 × 24 | 75 |
| Stable | 32 × 19 × 24 | 75 |
| Blacksmith | 24 × 19 × 24 | 75 |
| Market | 32 × 19 × 24 | 85 |
| SiegeWorkshop | 32 × 21 × 24 | 75 |
| University | 32 × 26 × 32 | 110 |
| Monastery | 24 × 28 × 24 | 90 |
| Mill | 16 × 20 × 16 | 65 |
| LumberCamp | 16 × 12 × 16 | 45 |
| MiningCamp | 16 × 12 × 16 | 45 |
| Tower | 16 × 30 × 16 | 45 |
| Wall | 8 × 13 × 8 | 10 |
| Castle | 64 × 48 × 64 | 130 |
| Wonder | 56 × 57 × 56 | 130 |
| Farm | 24 × 1.2 × 24 | 22 |

施工動畫依零件名稱分階段顯現（`ArtKit` 的 `foundationNames`、`wallNames`、`roofNames`）：地基類名稱（`Foundation StonePlinth Courtyard Step Paddock Soil`）最先出現，牆體類（`Walls Keep Tower StoneWall Storehouse Temple WindmillTower Post StoneColumn Beam TimberBrace GatePier BellTower Chimney`）其次，其他名稱是裝飾，屋頂類（`RoofTile Roof Ridge Spire GildedCap CanvasSail Banner Eave RoofFascia Awning CanopyStripe Finial Flag Flagpole TeamTrim`）最後。主要量體務必使用這些名稱。

每棟建築要有一個**從上方就認得出來的招牌特徵**（例如磨坊的風車、兵工廠的熔爐與煙囪、射箭場的箭靶、馬廄的圍欄與乾草、市集的攤位遮陽篷）。

農田有耗損階段：`stage` 0 滿田、1 已收 2 列、2 已收 5 列、3 休耕；各階段不得超出階段 0 的外框。

## 單位

單位**不會被縮放**，尺寸就是遊戲內尺寸，而且客戶端動畫依零件名稱與固定支點運作，所以以下是硬性規定：

- 步行單位約 3.5 寬 × 5.7 高；騎兵不超過 4.3 寬 × 9.2 高 × 9 長；攻城器械約 7.3 寬 × 8 高 × 11 長（投石機可高到 17）。腳底在 `y=0`。
- 動畫群組（`UnitMotion.client.lua` 的 `groups`）：
  - 腳 `BootL BootR`（以零件頂端為支點前後擺）
  - 右臂 `ArmR Arm Tool ToolHead Sword Spear Spearhead Bow Bowstring Staff StaffHead`，左臂 `ArmL Shield`；肩膀支點在 `(±1.4, 3.7, 0)`，騎乘時 `(±1.4, 6.8, 0)`。右手的東西 `x>0`，左手 `x<0`。
  - 軀幹 `Body Belt Tabard Head Hat HatBand Quiver Robe Carry`
  - 馬 `HorseBody Saddle HorseCloth HorseHead HorseNeck Mane`，馬腿 `HorseLeg`（以零件頂端為支點）
  - 攻城 `Chassis Roof Ridge SiegeBanner CatapultPost TrebuchetFrame`，輪子 `Wheel`（繞自身中心對 X 軸轉），`RamLog RamHead`（沿 Z 前後推），`CatapultArm StoneBasket`（支點 `(0,5,0)`），`TrebuchetArm Counterweight Sling`（支點 `(0,9,0)`）
  - 不在群組內的名稱會跟著身體整體移動，不會擺動。
- 村民：`villagerTool(model,tool)` 回傳 `Tool`／`ToolHead` 零件清單（axe, pick, hoe, hammer, basket），握在右手 `x≈1.38`；`carryLoad(model,kind)` 回傳背上（+Z）的 `Carry` 零件清單（wood, food, gold, stone）。
- 零件上限：步行 32、騎兵 56、攻城 30（畫面上會有上百個單位）。
- 每個兵種要能從俯視鏡頭靠頭飾、武器與玩家色分辨。

## 預覽

```
python build/art-preview/preview.py Kind1,Kind2 輸出名稱 360
```

以模擬引擎執行真正的 Art 模組，印出零件數與外框，並輸出 `build/art-preview/輸出名稱.png`（左：遊戲鏡頭；中：3/4 視角；右：側面）。`Kind:2` 可指定階段。這是近似繪圖，不是 Studio 畫面。
