# 介面與共用美術精修

本輪改善 Roblox RTS 原型的介面與原創替代模型，採深色木材、黃銅細節、暖色日光與清楚的建築輪廓。這是原型美術改進，不代表完整遊戲已完成。

## 範圍

- `GUIManager.lua`：面板受光邊／下緣、內凹圖卡、資源圖示、建築分類模型卡、指令預覽舞台、大廳章紋與設定／集合名單分區。按下即時回饋，支援滑鼠 hover、控制器 focus 與減少動態。
- `Art.lua`：共用模型的輪廓、建築用途特徵、屋頂木構、材質與單位細節；施工階段與陣營標記沿用原有契約。原有 Studio 模板與未知實例保留，生成模型仍只供缺模型時使用。
- `MapGenerator.server.lua`：暖色日光、冷色陰影、草地／道路／水色與橢圓草甸；新增一個自有色彩校正效果，不取代使用者的其他效果，沒有新增地圖裝飾部件。

同時有另一批來源變更加入 `UnitIcons` 與 `UnitSelectionPanel`，本輪保留它們。選取面板外層繼承新面板皮膚，內層沿用自己的色盤。整合快照的結果不能只歸因於本輪三個檔案。

## 保留與驗證方式

修改前完整 `src` 備份：`C:/Users/user/AppData/Local/Temp/AOE2-before-visual-polish-20261001-180322`。

獨立驗證副本會額外映射 `build/visual-polish-harness.client.lua` 與 `build/visual-polish-harness.server.lua`，不在 `default.project.json` 內。它們明確執行現有的隊色／工廠／HUD／建築選單／地圖／施工外觀／位移測試。客戶端先停在大廳，需在該測試局的客戶端 Command Bar 明確執行 `game.Players.LocalPlayer.PlayerGui.VisualPolishStart:Fire()` 才開始；啟動後會正常開一場無 AI、豐富資源沙盒，並消耗施工測試資源。

`build/visual-polish-gallery.lua` 是獨立副本編輯模式的臨時十八種建築展示片段，沒有對局所有權或經濟效果，不保存回原 place。

## 本輪結果

最終 Art SHA256：`2979E74A4A3DBA3621E94299AF558444AEFE201599389A0C21CE6D2C5C714CF1`。

最終一般副本為 [AOE2-visual-polish-20261001-r3.rbxlx](../build/AOE2-visual-polish-20261001-r3.rbxlx)，SHA256 `89579B6C17BC865C05AA8A9E838337BEB5A91B7A2286C8D0835A31CAD554B8AB`，與本輪 `build/AOE2.rbxlx`、最終 CLI 副本一致。測試映射額外含測試腳本，因此其整個 place hash 不同；遊戲来源由 [r3 固定來源清單](../tests/visual-polish-source-manifest-20261001-r3.json) 核對。

- 完整 `scripts/verify.ps1` 通過，exit 0：[最終 CLI 輸出](../tests/visual-polish-cli-20261001-r2.txt)。首次使用 Windows PowerShell 5 因 UTF-8 BOM 失敗，失敗記錄保留，後以 PowerShell 7 原版腳本重跑通過。
- 最後驗證使用上述最終 Art。執行期間只有另一聊天的 `UnitIconTests.lua` 更新；最終 r3 全來源另外完成 Luau 編譯與 Rojo 建置，沒有把測試模組的舊編譯結果當成新來源語法證明。
- 來源審查修正了樹冠擬合後過窄的回歸；最終樹外框為 14 × 18 × 14，維持四個外觀部件。建築 8–111 個、單位 18–39 個外觀部件，不含工廠 Root／占地。
- 首版 Studio 已取得隊色 748 項與模型工廠 285 項 COMPLETE，但之後樹冠及材質又有修正；[首版紀錄](../tests/visual-polish-r1-studio-20261001.txt) 不作為最終整套 Play 驗收。

最終快照的 Studio 結果於實際執行後補入；沒有以歷史 PASS 作為本輪驗收。

尚未執行本輪雙人同步、玩家離開清理、真實手機手勢、長局與大軍負載驗收。資源外觀預算的控制不等於 FPS 或大規模效能驗收。本輪沒有執行 Roblox 體驗發布。
