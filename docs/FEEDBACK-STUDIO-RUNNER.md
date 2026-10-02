# 音效與動作的獨立雙人驗證檔

`feedback-validation.project.json` 是明確選用的測試專案。它沿用正式程式與數值，額外映射 `tests/studio-feedback-harness.client.lua` 和 `tests/studio-feedback-coordinator.server.lua`。正式 `default.project.json` 不包含這兩個啟動器；共用測試 ModuleScript 的 `require()` 本身不啟動測試。

使用新的輸出檔，保留既有 place：

```powershell
.\rojo.exe build feedback-validation.project.json -o build/AOE2-feedback-validation-run-r2.rbxlx
```

在 Studio 開啟這個獨立檔案，選「伺服器與客戶端」，設定兩名玩家並啟動。不連接正式專案的 Rojo 同步。此檔會明確自動執行測試，會花費正常資源、正常施工與戰鬥；不能使用正式玩家工作階段。

兩個真正客戶端依 UserId 選房主與第二端，以正式傳送門、準備和開局流程開始 Small／Rich／0 AI／FFA。先驗房主施工與生產、跨玩家所有權拒絕，才掛上第二端的採集、交貨、近戰與本機靜音觀察。兩端完成後各自正常發展、建造與升代，再觀察九種軍事單位及兩種防禦建築的真實傷害、音效和動作。最後由第二端修復本輪軍隊真正打傷的建築。

協調遠端只交換允許的測試階段，在玩家設 `FV_` 測試標記；只在 Studio 存在。它不寫 HP、資源、時代、單位位置、工作時間戳或遊戲對局屬性。任一端失敗會停止後續測試，保留真正失敗戰局與日誌。

必須分別保存兩端的原始 `PASS`、`FAIL`、`COMPLETE`，以及測試開始時的來源與建置 SHA256。`FEEDBACK_BATTLE COMPLETE` 的「正常發展與戰場準備」只證明前置；九兵種戰鬥、第二端戰鬥觀察、修復及整體 `FEEDBACK_VALIDATION COMPLETE` 各有獨立結果，不可互相代替。

整體完成後，第二端才掛上真正 `PlayerRemoving` 的清理觀察器。此時只關閉房主客戶端；「結束作業」同時關閉伺服器與全部客戶端不能驗證存留玩家的清理、勝利和房主轉移。

這個流程驗證無外部模型的 Studio 回饋。實際手機聽感、正式 Roblox 網路、全剋制矩陣、長局效能及原模型碰撞等仍須各自驗收；本文件不是已通過的結果宣告。
