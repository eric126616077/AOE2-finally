# 大廳生成資源與小地圖清理

僅在新 Studio Play 的本機副本明確執行。正常專案沒有映射這些測試，也沒有自動執行入口。

1. 建置 `rojo.exe build lobby-cleanup-validation.project.json -o build/AOE2-lobby-cleanup-studio-20261001-r2.rbxlx`，Studio 開啟該本機檔並 Play。重驗時使用新名稱，保留歷史副本。
2. 等大廳角色、Resources 與 UI 就緒；在 SERVER Command Bar 呼叫 `require(game.ReplicatedStorage.LobbyCleanupValidation.Fixture).Run()`。
3. 等 CLIENT 已收到 fixture 模型與 PrimaryPart，再在 CLIENT Command Bar 呼叫 `task.spawn(function() require(game.ReplicatedStorage.LobbyCleanupValidation.Tests).Run() end)`；SERVER READY 本身不能證明客戶端複製就緒。
4. 收集五段 `LOBBY_CLEANUP CYCLE` 與最後 `LOBBY_CLEANUP COMPLETE`；保留任何失敗。停止 Play，不儲存／發布暫時局。

測試正常開 Small、Small、Large、Large、Small 五局；每局 MapTests 檢查生成資源與地圖占地，結果畫面仍保留資源，正常重開返回大廳才清除生成資源和實際 PlayerGui 小地圖節點。第四局正常花費 25 木材建房，並讓村民採集重新生成的樹木。沒有直接增資源、生成單位或搬動 Root。

SERVER fixture 只新建暫時、未標記的資源模型／資料夾、同名未知場景及模型模板；測試驗證 identity 與標記保留。未知資料夾內即使有巢狀標記模型也不能被直接子項清理遍歷刪除。fixture 在 Play 中保留，停止 Play 才清除。生成景物只有 38–62 部件，為同尺寸新局保留；沒有宣稱世界所有物件清空。

這個測試是單人重開生命週期，不代表最新雙人同步／玩家離線清理、正式裝置、總記憶體下降數值或滿人口效能已通過。

2026-10-01 06:42:52（Asia/Taipei）r2 新 Play 已取得 **126 項 COMPLETE、五輪循環**；大型客戶端資源部件 census 6204、小地圖 dots 1106 返回大廳後皆為 0。第四輪正常建房／扣款／採集完成。來源與兩個建置比對一致，詳見 `optimization-lobby-r2-studio-results-20261001.json`／`.txt`。部件 census 不代表全部視覺複製或記憶體量；保留測試檢查原身分、Parent 與管理標記，沒有覆蓋所有材質／色彩／位置。

初次 helper 因 MatchGeneration 在第一局前是 nil 而提前 INCOMPLETE；r2 僅修正測試初始化為 0，正常執行程式不變。失敗與初次建置／來源清單已保留。
