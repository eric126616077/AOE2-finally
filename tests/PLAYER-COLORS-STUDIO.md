# 玩家陣營屋頂、飾邊與自然配色

2026-10-01 修正：依使用者要求以屋頂主體作為最明顯的陣營識別，屋頂與屋脊使用所屬玩家／AI 的 `TeamColor`，紅方紅屋頂、藍方藍屋頂。建築牆面、木材，以及村民／士兵的皮膚、武器、馬匹保留自然色；旗幟、衣飾、盾牌、馬鞍與小型飾邊也使用陣營色。所有替代建築與部隊至少保留一個可見陣營標記。中立資源與大廳裝飾城堡維持自然色。

`Art.ApplyPlayerColor` 僅處理可見、具有 `TeamColorPart=true` 標記或名稱屬於陣營白名單的部件；包含屋頂 `Roof`、屋脊、旗幟、戰袍、盾牌、馬鞍、遮棚、帽帶與馬衣等部件。共用幾何外觀、HUD 與建造預覽的屋頂都會跟隨陣營色。貼圖、Decal、Texture、SpecialMesh 與 SurfaceAppearance 保留。進口建築的屋頂需命名為 `Roof` 或標記 `TeamColorPart=true` 才會跟色；未知名稱或貼圖屋頂尚未實機驗收。進口建築若沒有陣營部件，由工廠在擬合後的原模型正面補上小旗；旗的位置沿用原模型範圍，測試允許不超過 0.2 studs 的正面外掛厚度以免旗被外牆遮住。原模型的縮放、幾何與占地維持。未知部件的原色與貼圖不視為陣營飾邊，原始模板不被修改。新增帽帶、馬衣與攻城旗隨原有部位動作，避免與模型分離。

屋頂主色修正的 Luau 編譯與 Rojo 建置通過，記錄見 `faction-roofs-cli-20261001.txt`，輸出 `build/AOE2.rbxlx`。前一版陣營飾邊的完整 CLI 回歸記錄為 `faction-accents-cli-20261001.txt`，來源雜湊為 `faction-accents-source-manifest-20261001.json`；本次小幅調整未重跑完整 CLI 回歸。既有 `player-colors-cli-20261001.txt`、`player-colors-source-manifest-20261001.json` 屬於修正前的整模型改色版本，不能用作本次屋頂與陣營飾邊驗證。

**本次屋頂主色與陣營飾邊 Studio Play 尚未驗證。** 前一版 Computer Use 嘗試開啟獨立預覽，遇到 `unknown screenshotId screenshot-0` 與 `Computer Use helper already has an active request`。未執行陣營飾邊引擎測試，未取得新版紅藍對照畫面、實際雙人同步或使用者真模型的驗收。`build/AOE2-faction-preview-20261001.rbxlx` 為前一版獨立預覽快照，正式映射不包含自動預覽腳本。

後續可在新 Play 的 SERVER Command Bar 明確呼叫：

```lua
require(game.ServerScriptService.ServerModules.PlayerColorTests).Run({keepDisplay=true})
```

此模組只建立／清除私有 fixture，檢查四色所有建築與單位的已標記陣營部件，並要求至少一個可見標記。測試同時驗證自然部件不隨陣營改色、原貼圖與模板保留、未知模型補旗的位置與縮放，以及建築占地、單位 Root／CollisionVolume 的碰撞旗標。直接套用 `Art.ApplyPlayerColor` 不會替未知模型新增小旗；補旗由建築工廠負責。

`keepDisplay=true` 會留下位於地圖上方的紅藍自然配色對照展示供檢視，僅存在該次 Play；預設 `Run()` 會清除全部私有 fixture 且不保留展示。正常遊戲不自動執行此模組。實際 HUD 圖示、建造預覽、集合點旗幟及雙人客戶端仍需另外檢查，不能以語法檢查替代 Studio Play。
