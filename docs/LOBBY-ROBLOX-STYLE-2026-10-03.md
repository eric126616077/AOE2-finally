# 大廳 Roblox 風格外觀

本輪只改大廳外觀，不改流程和伺服器規則。戰場 HUD 維持原本的羊皮紙主題。

## 3D 廣場（`ServerModules/LobbyWorld.lua`）

- 廣場整體改用 SmoothPlastic，地面是棋盤格，四周是草地、花圃和樹籬。城牆為白色加藍色飾帶，角樓頂是紅色階梯屋頂。
- 中央有噴泉，上方是浮動的金色星星；另有經典 Roblox 出生台（貼圖 `rbxasset://textures/SpawnLocation.png`）和面向出生台的歡迎拱門。
- 四座傳送門：白色台座、霓虹光環、上升的光點、彩色柱子、門楣名牌、ForceField 光幕和浮動寶石。上方的狀態看板是圓角卡片，顯示玩法（`GameModeRules.label`）、階段、玩家數與準備數。
- 看板用 stud 尺寸的 BillboardGui，會隨距離縮小。
- 對外 API 和測試依賴的名稱不變：`Portal_<id>`、`PortalId`、`PortalDais`、`JoinQueue`，以及 `SpawnCFrame`／`QueueCFrame`／`ContainsPortal`／`NearPortal`／`PortalAt`／`SetStatus`。
- `StarterPlayerScripts/LobbyMotion.client.lua`：只轉動帶有 `LobbySpin` 屬性的零件，而且只在玩家位於大廳時執行；減少動態設定開啟時，寶石回到原位。
- `GameConfig` 四個匹配點的顏色改為較飽和的顏色。

## 大廳介面（`GUIManager.lua`）

- `button()` 可以替個別按鈕登記配色（`buttonPalettes`，加上 `LobbySkin` 屬性）。沒有登記的按鈕行為與外觀完全不變。
- `GUI:SkinLobby()`／`GUI:SkinTutorialInvite()` 在元件建立後才套用外觀：白色面板、深藍 3px 外框、FredokaOne 標題，以及帶底部厚度的糖果色按鈕（按下時會下沉）。
  - 快速開始依玩法上色，房間卡片使用匹配點顏色，狀態顯示成深色膠囊。
  - 選中的玩法卡片會填滿玩法顏色。
  - 房間面板加上藍色標題列；準備是綠色、下一步是藍色、離開是紅色、文明是黃色。
- 元件名稱以及 `Selected`／`Unavailable` 屬性都沒有變。

## 驗證

- `scripts/verify.ps1` 全部通過，包含 Rojo build；`luau-analyze` 沒有新增警告。
- **未在 Roblox Studio Play 驗證**（螢幕由其他 session 使用中）。尚未實測：
  - 出生台貼圖是否顯示
  - FredokaOne 搭配中文的實際字形
  - 寶石轉動和光點
  - 看板在桌面與手機的大小
  - 標題列在矮畫面的位置
  - 按鈕各狀態的顏色
  - 走進傳送門加入是否正常
  - 樹籬、噴泉和拱門是否擋住通道
