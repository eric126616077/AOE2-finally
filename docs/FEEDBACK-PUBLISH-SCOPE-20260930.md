# 2026-09-30 試玩發布的音效與動作驗證範圍

使用者已授權更新既有 Roblox 體驗供試玩。本文件記錄發布前可確認的測試範圍；目前仍是 RTS 原型，不能稱為完整遊戲，也不能把發布操作視為未完成引擎測試的通過證據。本文本身不證明雲端版本已發布成功。

| 驗證 | 實際結果 | 可以確認的範圍 |
| --- | --- | --- |
| 最新 CLI／Rojo | 編譯與所有列出的純邏輯套件通過；產生正式映射的預檢檔 | 語法、映射、成本／所有權等規則；含 70 項音效規則、76 項施工時鐘、41 項錄得位置的安全前綴／有界延續檢查。CLI 和引擎模擬測試不等於 Studio Play。 |
| 單人施工回饋 | 20:50:44–20:50:56，38 項 COMPLETE | 正常成本建屋、工人到場／工作脈衝、正式已載入施工聲音與工具動作、停工／續建、靜音／恢復、減少動態、真正完工的人口與一次提示、重疊建造拒絕不扣款及播放清理。使用無外部模板的替代外觀。 |
| 真正雙端 r1 | 21:34–21:36 的兩名 Studio 客戶端有局部 PASS，之後 FAIL | 正常大廳、房主建屋／訓練、第二端所有權拒絕；兩端同來源採集聲音已載入，第二端工具動作存在，真實交貨增加庫存。4 筆 LastWork 與 1 筆 LastDelivery 的伺服器時間戳記逐一完全相同。 |
| 雙端 r1 攻擊 | 21:36:22，雙端 100 秒等待逾時 | 房主斥候跨圖攻擊市鎮中心未產生 LastAttack 或傷害。沒有近戰、雙端本機靜音隔離、九兵種戰鬥、修復或離開清理的 COMPLETE；這些項目不能算通過。 |

以上時間使用 Asia/Taipei。單人 38 項是當時來源快照的實際證據；保留此前大廳角色清理時間差與施工工作時鐘缺少 `workFeedback` 的兩次 FAIL，修正後重開 Play 才取得 COMPLETE。它沒有驗證後續新版導航的全程行軍。

最新導航來源的 SHA256 如下。這兩個版本目前只有 CLI／純邏輯驗證，尚未重跑 r1 原情境的完整真實行軍與攻擊：

| 來源 | SHA256 |
| --- | --- |
| GameServer.server.lua | `C6710AA707E33C7058567DECC8406518864503EEA1E092FFC16F4856C4207081` |
| ServerModules/PathRules.lua | `4D680443963ED183A74C6C9414685842F87BD323444986B6E6D31007F412BA13` |

r1 失敗後的唯讀導航查詢顯示，`PathStatus.Success` 的路徑仍有執行段撞房屋、樹或漿果的 Footprint。新的安全前綴與有界延續修正通過 41 項錄得位置的純邏輯檢查，尚不足以宣稱跨圖攻擊已修復並通過引擎驗證。

發布應使用 `default.project.json` 的正式映射，保留既有使用者模型。`feedback-validation.project.json` 與 `build/AOE2-feedback-validation-run-r2.rbxlx` 是獨立 Studio 驗證專案，額外含自動測試啟動器及 `FV_` 階段協調遠端；**這份 r2 特別建置不供發布**。正式映射沒有這兩個測試啟動器。共用測試 ModuleScript 的 `require()` 本身不啟動測試。

r2 已建置但尚未啟動新雙人 Play。步兵、長槍兵、弓箭手、矛兵、斥候、騎士、衝車、投石車、巨型投石機九兵種，以及瞭望塔／城堡的完整雙端音效、動作與真實傷害流程仍未完成引擎驗證。`FeedbackRepairTests` 也未取得真戰損、正常扣木材修復及回饋的 Play COMPLETE。真正退出的音效／效果清理、勝利及房主轉移，以及正式 Roblox 網路、真機操作與聽感，仍須在試玩環境各自確認。

可追溯證據：

- [最新 CLI 結果](C:/Users/user/Desktop/AOE2-finally/tests/latest-feedback-r2-cli-results.txt)
- [單人 38 項及歷史失敗](C:/Users/user/Desktop/AOE2-finally/tests/latest-feedback-construction-studio-results.txt)
- [r1 真實雙端原始日誌](C:/Users/user/Desktop/AOE2-finally/tests/feedback-multiplayer-studio-log-20260930-r1.txt)
- [r1 五筆精確時間戳記比較](C:/Users/user/Desktop/AOE2-finally/tests/feedback-multiplayer-pulse-comparison-20260930-r1.json)
- [r1 失敗後唯讀導航診斷](C:/Users/user/Desktop/AOE2-finally/tests/feedback-navigation-diagnostics-20260930-r1.txt)
- [r2 來源及獨立建置雜湊](C:/Users/user/Desktop/AOE2-finally/tests/feedback-real-clients-source-manifest-r2.json)
