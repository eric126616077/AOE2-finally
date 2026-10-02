# 未知同名場景碰撞回歸

這是明確呼叫的暫時測試，不屬於正常 Rojo 映射，也不會自動執行。測試會建立牆面並移動自己的村民。請使用新的隔離 Play；完成後停止 Play，不儲存或發布測試局。

1. 執行 `rojo.exe build query-validation.project.json -o build/AOE2-query-validation-20261001.rbxlx`，在 Studio 開啟該本機副本。
2. 新 Play 的 CLIENT 明確呼叫 `require(game.ReplicatedStorage.Shared.LobbyTests).Start({expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})`。等待實際 Units／Buildings、無角色及 Scriptable 相機就緒。
3. SERVER Command Bar 呼叫 `require(game.ReplicatedStorage.SceneryValidation.Fixture).Run()`。它只在 Studio／Playing／單陣營沙盒建立測試牆面；遇既有未知 `RTSScenery` 或名稱衝突會停止。
4. CLIENT Command Bar 呼叫 `task.spawn(function() require(game.ReplicatedStorage.SceneryValidation.Tests).Run() end)`。檢查 `SCENERY_COLLISION COMPLETE`，若失敗保留完整 INCOMPLETE／錯誤。
5. 停止 Play 清除暫時牆面。不要在同一 Play 重開其他測試局，因未知模型的保留是測試的一部分。

預覽檢查使用 BuildingController 公開 API，在 Command Bar 的獨立 require VM 執行；不代表正式 RTS LocalScript 的 require cache 或 UI 選取共用。建造及移動則透過正常遠端命令，讀權威模型與資源；不直接生成單位、移動 Root、贈送資源或調速度。

`report.seconds` 是第二段繞牆命令時間，並非整個測試 Run 總時間。單陣營沙盒仍可能有觀戰玩家，這個 helper 不驗多人同步。

2026-10-01 06:13:26 Asia/Taipei 的隔離新 Play 結果：14 項 COMPLETE、152 段取樣／78 次 Root 更新，側向繞行 23.42 studs，繞牆命令 9.42 秒。來源、建置雜湊與原始 log 在 `optimization-query-final-source-manifest-20261001.json`、`optimization-query-studio-results-20261001.txt`；CLI mock 與 Studio 引擎結果分開保存。
