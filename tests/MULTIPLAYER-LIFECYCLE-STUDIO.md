# 最新雙人與最後離開清理

這是明確呼叫的隔離 Studio 測試；正常 `default.project.json` 沒有映射 helper、測試遠端或注入腳本，不會自動執行。

1. 使用 `rojo.exe build multiplayer-lifecycle-r2-validation.project.json -o build/AOE2-multiplayer-lifecycle-20261001-r2.rbxlx` 建置獨立副本。V1 helper／build／manifest 保留供失敗診斷；R2 正常來源與已驗證的五輪單人大廳版本完全相同。
2. 在該副本啟動 Studio 的 Server & Clients，選兩位玩家；確認伺服器與兩個真正客戶端已進入新大廳。
3. 在 **SERVER** Command Bar 明確呼叫 `task.spawn(function() require(game.ReplicatedStorage.MultiplayerLifecycleValidation.Tests).RunServer() end)`。
4. Helper 僅在 Studio、伺服器、新 Lobby 與恰好兩位玩家條件下執行。暫時測試 LocalScript 用正常 `Humanoid:Move` 走進集合入口；伺服器核對真實 Root 位置與集合旗標後才開始既有 shared tests。接著在真正客戶端透過正常 RTSRemotes 執行準備／建造／訓練／所有權拒絕測試。
5. 完成雙端檢查後，helper 用 `Player:Kick` 觸發真正 PlayerRemoving。先驗第一位離開時另一位保留勝利結果與全域資源，再退出最後一位，由仍在執行的獨立 Studio server 驗證 Lobby、生成資源、單位與建築清理。
6. 收集每個客戶端與 server 的 COMPLETE／INCOMPLETE、全部 `REPORT_CHUNK`、對應摘要、原始日誌、來源與建置 hash。Studio 會截斷長行；必須重組所有分段並核對摘要，單獨 COMPLETE 行不足以證明完整結果。失敗後保留原局作診斷。
7. 在原副本主視窗使用「測試 → 結束作業」停止 server 與 clients；這種模式的 Shift+F5 可能停用。關閉副本時選不要儲存，保留使用者原 place。

暫時未知資源 fixture 用來檢查清理保留；不增資源、不直接生成遊戲單位、不改權威 Root、網路擁有權或集合旗標。原 Shared.LobbyTests 仍有 client PivotTo；R2 在呼叫前已完成真實行走與 SERVER ACK，因此不靠該 Pivot 當集合前置。伺服器資源部件數與客戶端已收到的部件數分開記錄；沒有把它們當完整視覺複製、CPU／FPS／記憶體量或正式裝置效能驗收。

這次只驗雙人基本同步、所有權與離開生命週期。未包含所有勝利條件、完整戰鬥、正式跨伺服器配對、真機觸控或四方滿人口長局。

2026-10-01 07:33 新工作階段已取得 server 36／host 11／peer 14 COMPLETE；26 份完整分段報告、72 筆原始紀錄、94 baseline／96 驗證來源與建置 hash 已核對。結果保存在 `optimization-multiplayer-lifecycle-r2-studio-results-20261001.json` 與同名 `.txt`。兩次 Kick 確實觸發 PlayerRemoving；最後空 Lobby generation=2，生成資源、單位與建築歸零。原始 V1 集合失敗仍保留，沒有覆寫成通過。

可在專案根目錄重跑證據解析；這只讀日誌與核對來源，不啟動或修改 Studio：

```powershell
.\tests\optimization-multiplayer-lifecycle-r2-evidence-parser.ps1 `
  -ServerLog 'C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T233124Z_Studio_15AB1_last.log' `
  -HostLog 'C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T233130Z_Studio_D9700_last.log' `
  -PeerLog 'C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T233131Z_Studio_56565_last.log' `
  -OutputJson 'tests/multiplayer-r2-new-audit.json' `
  -OutputText 'tests/multiplayer-r2-new-audit.txt'
```

缺段、重複／衝突摘要、CLIENT_DONE 缺失或來源 hash 改變時，parser 會拒絕完整通過。輸出檔已存在或不在 tests 目錄時也會拒絕；每次重跑請指定 tests 內尚不存在的新檔名，保留歷史結果。操作停止／不要儲存的補充紀錄在本輪優化文件。
