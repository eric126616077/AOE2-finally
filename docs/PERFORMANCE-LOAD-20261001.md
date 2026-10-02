# 漸增負載觀測：2026-10-01

本輪使用凍結 runtime 的獨立 Studio 驗證 place，不發布體驗。由主聊天唯一操作 Studio；地圖效能 agent 只整理來源與觀測資料。此方法量測目前 RTS 原型，不能據此描述為完整遊戲或宣布效能驗收通過。

## 來源與重現

已建立的 r2 place 為 `build/AOE2-performance-validation-20261001-r2.rbxlx`，SHA256：

```text
6896A5E1586DD2481BAA7E4C3B15E47F5BE1757C2B564280FA953343B346FD02
```

完整來源紀錄為 `tests/performance-load-source-manifest-20261001-r2.json`。該 manifest 的 `not yet Play verified` 是建置時狀態，不能當成後續 Play 結果。`performance-validation.project.json` 額外映射兩個明確呼叫才執行的 ModuleScript：

| Studio 路徑 | 檔案 | 用途 |
| --- | --- | --- |
| `ReplicatedStorage.PerformanceValidation.Load` | `tests/PerformanceLoadTests.lua` | CLIENT 正常準備單位、量測與發出停止指令 |
| `ReplicatedStorage.PerformanceValidation.ServerProbe` | `tests/PerformanceServerProbe.lua` | SERVER 唯讀 Heartbeat／模型／Stats 觀察 |

它們不在 `default.project.json`。重現時建置另名輸出並保存新 manifest，不覆蓋正在驗證的 r2 place：

```powershell
.\rojo.exe build performance-validation.project.json -o build/AOE2-performance-repro.rbxlx
```

新開此 place 的 Play，經正常大廳設定 `Small`、單人、`aiCount=0`、`Rich` 後開始。必須實際進入 `Playing`／`Sandbox=true`／一方；helper 不直接改大廳設定、增發資源或生成單位。記錄 Studio 版本、硬體、圖形品質、視窗大小、焦點事件、地圖、generation、來源 manifest 與原始 log。量測前固定正常 RTS 相機與 ReducedMotion 設定；各階段不得改變相機、FOV 或 viewport。

## 階段與入口

先完成地圖、HUD 與 Presentation 回歸，再量測負載；回歸通過不等於負載完成。每次只執行一個 CLIENT helper，先確認所有生產佇列為空。

CLIENT Command Bar 依序執行以下三個獨立 30 秒窗口，先用 `expectedUnits=4`，再按相同順序量測 10、20 個實際單位：

```lua
require(game.ReplicatedStorage.PerformanceValidation.Load).Measure({mode="idle",seconds=30,expectedUnits=4})
require(game.ReplicatedStorage.PerformanceValidation.Load).Measure({mode="move",seconds=30,expectedUnits=4})
require(game.ReplicatedStorage.PerformanceValidation.Load).Measure({mode="stop",seconds=30,expectedUnits=4})
```

窗口之間以正常準備流程增加負載；每條指令完成後才執行下一條：

```lua
require(game.ReplicatedStorage.PerformanceValidation.Load).Prepare({targetUnits=10,timeoutSeconds=300})
-- 完成 10 個單位的 idle / move / stop 後：
require(game.ReplicatedStorage.PerformanceValidation.Load).Prepare({targetUnits=20,timeoutSeconds=300})
```

`Prepare` 僅接受 10 或 20，期限 60–600 秒；以正常 Build／Train／Order／Stop 提出請求，驗證木材、食物扣款、村民施工、實際生成與出口集結。房屋會避開測試走廊，不刪單位湊數。`Measure` 僅接受 4／10／20 個實際自有存活單位，窗口 30–120 秒。移動窗口先確認全體至少移動 4 studs 且處於 Walk，再於兩個端點間每約 2 秒發正常指令；停止窗口先確認待命及位置穩定。

需要伺服器側對照時，在單位準備完成後，SERVER Command Bar 明確啟動獨立窗口：

```lua
require(game.ReplicatedStorage.PerformanceValidation.ServerProbe).Start({
 seconds=45,
 label="r2 Small 10 move",
 sourceVersion="performance-load-20261001-r2"
})
```

伺服器窗口限制 30–120 秒，預設 45 秒；每 5 秒讀頂層模型數及可讀 Stats，最多 25 個樣本。Start 回傳 handle，可呼叫 `handle:Snapshot()`／`handle:Finish()`；deadline 會自動結束。兩端沒有新增 remote 同步時鐘，應以原始 log 時間與 generation 核對重疊範圍，不能假設 45 秒伺服器窗口等於 30 秒 CLIENT 窗口。

## 指標與 helper 限制

- CLIENT `ClientLoad` 的 `FRAMES`、`FOCUS_FRAMES`、`FOCUS`、`LOAD`、`METRIC`、`COMPLETE` 必須分開保存。優先比較 `Focused` 的有效 FPS、p95 上界、最差幀及低於 30／15 FPS 的幀比例。沒有焦點事件時，`Unknown` 不能改稱已驗證前景；背景樣本須另外列出。
- `LOAD` 每 0.5 秒取樣實際 root 的視口及移動數。`minimumVisible`／`everVisible` 只依 `WorldToViewportPoint(root.Position)` 的 `onScreen` 與 `screen.Z>0` 計數；沒有 GUI 命中、世界遮擋或外觀部件可見性檢查，不能稱為全部單位未被 HUD 遮蔽。它也不能證明全體每幀同時位於視口或連續移動；端點轉向及正常停止可能讓 `minimumMoving` 為 0。`movingSampleFraction` 表示至少一個 root 確有位移且處於 Walk 的取樣比例。
- SERVER `ServerHeartbeat` 的 `meanHeartbeatHz`、p95、最差 delta 是整個 Heartbeat 節奏，包含 helper 成本；它不量 GameServer CPU、ComputeAsync 耗時／併發、每腳本成本或 CLIENT rendering FPS。
- 模型計數區分自有標記與其他 Model；缺少資料夾或不可讀 Stats 會記 missing。`MemoryTrackingEnabled=false` 不把 heap API 回傳 0 當成實測。模型數不是 BasePart／drawcall 數，人口、佇列也不是已生成單位。
- `sourceVersion` 是呼叫者標記；GameServer.Source 指紋僅代表可讀的 Script.Source，不證明 active VM。來源新鮮度須另外以凍結 manifest、新 Play 和載入檢查建立。
- helper 輸出每行 JSON 上限 700 bytes；超長會明記 missing。不要把整個 `lastReport` 或 Snapshot 一次 JSONEncode 到 Studio log，避免截斷；可分欄位輸出。`COMPLETE`／`Finished` 表示窗口完成，所有報告仍是 `performanceAccepted=false`。

目前方法只有單人 Small、4／10／20 個單位，沒有修改前的同條件 baseline；不能宣布改善百分比、四方各 200 人口承載、雙人同步、多人退出或真手機效能通過。

## 結束與清理條件

每個 CLIENT 窗口結束後 helper 會送 Stop；失敗會輸出 `INCOMPLETE`，並嘗試停止本人單位。Stop 是請求，`COMPLETE` 先於末次 Stop 的確認，仍需核對實際單位 Order=待命、位置穩定、生產佇列為 0、helper 與 PerformanceObserver.running=false。中途失敗保留正常建築、已生成單位及未完生產，不撤銷已付成本、不刪實例；未完生產須待正常完成或由玩家正常取消。

SERVER 收到 `Finished` 後應無同 epoch 的新增週期樣本；Finish/deadline 會 disconnect Heartbeat 並取消取樣與期限 task。單次測試完成後以正常投降／返回大廳或結束 Play 清理。若要驗證返回大廳清理，另外確認 phase=Lobby、generation 切換、自有 Units／Buildings 為 0、玩家對局欄位清除；Resources 不要求為 0，未知 Studio 模型不得刪除。這些清理條件需保存實際 log，不能用 mocks 或 helper 結束標記代替。

## 本輪結果狀態

以下時間均為 2026-10-01、Asia/Taipei。來源是 r2 新 Play、Small／Rich／一方／無 AI／generation=1；由主聊天唯一操作。原始回歸摘錄保存在 `tests/performance-load-r2-regression-20261001.txt`，負載逐行 JSON 與分段結果保存在 `tests/performance-load-r2-evidence-20261001.json`，該檔隨原始 log 的後續資料更新。解析器固定讀取 `0.741.19.7411056_20260930T211509Z_Studio_EB6AA_last.log`，不以「最新 log」猜測本輪來源；只接受真正 CreatorOutput 的完整 JSON，不把 Command Bar 的程式文字當成結果。

05:19:14–05:19:19 取得本輪實際回歸完成紀錄：

| 回歸入口 | 實際檢查通過 | 範圍 |
| --- | ---: | --- |
| `FeedbackTests.RunPresentation` | 65 | PlayerGui／安全區域、實際資產載入、多音及靜音；聽感與真人觸控仍未驗收 |
| `MapTests.Run` | 6,775 | Small=768、420 節點、420 query／shadow、38 自有裝飾；當刻收到 2,468 資源部件，`completeVisualReplicationProven=false` |
| `HUDTests.Run` | 24 | 真實資源列、指令／選取／小地圖版面、安全區域、底部鄰近地面點擊與 UI 不穿透 |

4 個實際單位的三個 CLIENT 窗口各約 30 秒，均取得 `COMPLETE`；固定相機位置 `(-168,160,-48)`、FOV=50、viewport=1610×638，每窗 59 個負載取樣、`minimumVisible=everVisible=4`：

| 模式 | 完成時間 | 有效 FPS | p95 上界 ms | 最差幀 ms | 有單位移動的取樣比例 |
| --- | --- | ---: | ---: | ---: | ---: |
| idle | 05:27:06.607 | 50.00 | 20.5 | 21.89 | 0% |
| move | 05:27:37.265 | 50.00 | 20.5 | 21.99 | 98.28% |
| stop | 05:28:08.142 | 50.00 | 20.5 | 21.98 | 0% |

三窗皆未收到焦點事件，`Focused`／`Background` 沒有有效幀，整段為 `Unknown`；這些數值不能稱為已驗證前景 FPS，也不能用約 50 FPS 推定節流原因。三窗低於 30／15 FPS 的幀比例皆為 0，但這仍不是效能驗收。move 的 `minimumMoving=0`，98.28% 表示取樣時至少一個單位正在移動，沒有證明全體連續每幀移動。

保留首個 CLIENT 嘗試於 05:25:08 的 `INCOMPLETE`：helper 偵測相機／viewport 改變，未混入三個完整窗口。首個 SERVER 窗口雖以 `4 units triplet` 為標記，實際於 05:22:14–05:24:14 結束，與上述三個 CLIENT 窗口沒有重疊；它是獨立的 4 單位觀測，不能當作各 mode 的伺服器配對資料。Probe 不記錄單位 Orders。

05:33:27.584 取得正常 `PREPARED`：1 棟付費房屋、6 個新村民，實際單位達 10，食物=900、木材=1175、人口上限=10。10 個實際單位的三個 CLIENT 窗口各約 30 秒，均取得 `COMPLETE`；相機、FOV 與 viewport 和 4 單位階段相同，取樣 `minimumVisible=everVisible=10`：

| 模式 | 完成時間 | 有效 FPS | p95 上界 ms | 最差幀 ms | 有單位移動的取樣比例 |
| --- | --- | ---: | ---: | ---: | ---: |
| idle | 05:33:58.053 | 49.97 | 21.0 | 24.10 | 0% |
| move | 05:34:28.909 | 49.95 | 21.0 | 24.39 | 100% |
| stop | 05:34:59.519 | 49.98 | 21.0 | 25.56 | 0% |

10 單位 idle／stop 各 59 個負載取樣，move 有 60 個。move 的 `minimumMoving=9`，尚不能稱為每次全 10 個同時移動。三窗皆 `Unknown`、焦點事件 0，低於 30／15 FPS 的幀比例為 0；其前景與節流限制和 4 單位階段相同。

SERVER epoch=2、標記 `10 units preparation and triplet` 於 05:33:23.542–05:35:23.543 取得 `Finished`，120 秒內 25 次頂層模型取樣皆為 10 個自有單位。整段 Heartbeat 平均 49.94 Hz、p95 上界 22 ms、最差 delta 32.86 ms，低於 30／15 Hz 的 delta 比例為 0。依 log 時間推定它包含三個已完成 CLIENT 窗口，但也包含末次集結與待命時間；parser 保留 `workloadEquivalenceProven=false`。這是整段 cadence，不是分 mode 配對、GameServer CPU 或尋路耗時。

05:40:38.874 取得下一個正常 `PREPARED`：另外 2 棟付費房屋、10 個新村民，實際單位達 20，食物=400、木材=1125、人口上限=20。20 個實際單位的三個 CLIENT 窗口各約 30 秒，均取得 `COMPLETE`；相機、FOV 與 viewport 和前兩階段相同，取樣 `minimumVisible=everVisible=20`，僅表示全部 20 個 root 在各次取樣落於視口：

| 模式 | 完成時間 | 有效 FPS | p95 上界 ms | 最差幀 ms | 有單位移動的取樣比例 |
| --- | --- | ---: | ---: | ---: | ---: |
| idle | 05:41:09.467 | 49.97 | 21.0 | 25.48 | 0% |
| move | 05:41:40.234 | 49.95 | 21.0 | 24.78 | 100% |
| stop | 05:42:10.867 | 49.97 | 21.0 | 23.76 | 0% |

20 單位 idle／stop 各 59 個負載取樣，move 有 60 個。move 的 `minimumMoving=19`，沒有證明每次全 20 個同時移動。三窗仍為 `Unknown`、焦點事件 0，低於 30／15 FPS 的幀比例為 0；沒有 GUI 未遮蔽或前景效能證據。

SERVER epoch=3、標記 `20 units preparation and triplet` 於 05:40:34.331–05:42:34.351 取得 `Finished`，約 120 秒內 25 次頂層模型取樣皆為 20 個自有單位。整段 Heartbeat 平均 49.94 Hz、p95 上界 22 ms、最差 delta 32.09 ms，低於 30／15 Hz 的 delta 比例為 0。依 log 時間推定它包含 20 單位的三個 CLIENT 窗口，另含集結與待命；仍是整段 cadence，`workloadEquivalenceProven=false`，不拆成各 mode 耗時。

補入 20 單位結果時的 parser 快照有 384 個有效紀錄、15 個階段、0 個拒絕紀錄，最大 probe JSON 為 432 bytes；原始 `INCOMPLETE` 仍保留。目前 4／10／20 的 9 個 CLIENT 窗口皆已完成取樣，SERVER 三窗亦有 `Finished`；首個 4 單位 SERVER 窗與完整 CLIENT 三窗無重疊。

同一個固定 EB6AA 原始 log 另取得以下實際清理紀錄；這些有標記前綴的紀錄不在僅接受 `ClientLoad`／`ServerHeartbeat` 的 parser 結果內，須直接保存原始行：

| 時間／標記 | 實際結果 |
| --- | --- |
| 05:45:55.904 `LOAD_R2_CLEANUP_JSON` | 自有存活單位 20、建築 4、佇列 0；wrapper 確認單位待命，1 秒內最大 root 位移 0；Load.running=false、PerformanceObserver.running=false；食物=400、木材=1125、人口=20、上限=20 |
| 05:46:50.617 `LOAD_R2_RESET`、label=`20 after load` | 正常投降／返回大廳後 phase=Lobby、generation=2、自有 Units／Buildings=0、avatar=true、相機 Custom、resourcesZero=true；操作 wrapper 另確認玩家食物／木材／黃金／石材／人口／上限為 0，LobbyQueued／LobbyReady=false |

`resourcesZero` 在這裡表示玩家資源及人口欄位清零，不表示 `Workspace.Resources` 沒有節點。這些證據完成了本輪 20 單位停止及返回大廳的清理核對，沒有測玩家離開、多次長局記憶體回收或多人清理。中／大地圖及各自正常 reset 的紀錄由 `docs/MAP-PERFORMANCE-20261001.md` 另行保存。

其後在 fresh Play 明確呼叫既有 `ConstructionTests.Run()`，原始摘錄保存在 `tests/performance-load-r2-construction-studio-20261001.txt`。檔案保留真正 CreatorOutput 的 START、36 個 PASS、COMPLETE、RESULT、CENSUS、reset／final cleanup，以及少量真正 Stop／disconnect 引擎紀錄；排除 Command Bar 的 `>` 程式回音：

| 時間／標記 | 實際結果 |
| --- | --- |
| 05:48:59.018 `LOAD_R2_FRESH_CONSTRUCTION_START` | fresh Play、Small／Rich 單人、generation=1 開始施工測試 |
| 05:49:40.288 `RTS_CONSTRUCTION COMPLETE`／`LOAD_R2_FRESH_CONSTRUCTION_RESULT` | 36 項實際引擎檢查完成、結果 true 36；覆蓋村民限制、不合格請求不扣款、重複村民、遠方工地、到場前後停工／續建、兵營完工前拒絕訓練、農田完工前後資源啟用 |
| 05:51:14.604 `LOAD_R2_CONSTRUCTION_CENSUS` | TownCenter／House／Barracks／Farm 皆 Complete=true、總佇列 0；TownCenter 是開局建築，這不代表測過新建 TownCenter，正常新施工為 House／Barracks／Farm |
| 05:51:15.468 `LOAD_R2_RESET`／`LOAD_R2_FINAL_CLEANUP` | fresh Construction 正常返回大廳；Lobby、generation=2、自有 Units／Buildings=0、resourcesZero=true、avatar=true、相機 Custom，final cleanup=true |
| 05:51:25.524–05:51:26.429 | Studio 真正執行 Stop Play；有 CLIENT disconnect、SERVER stopped 與 StopPlaySoloEnd，非僅送出按鍵的宣告 |

只讀核對固定 EB6AA log 直到上述最後 Stop：SERVER epoch 1／2／3 分別於 05:24:14.866／05:35:23.543／05:42:34.351 輸出 `Finished`，其後各自同 epoch 的 `Counts`／`Stats`／`Cadence` 新取樣數均為 0。這是取樣已停止的觀察，沒有額外推定所有引擎連線或長期記憶體回收皆已驗證。

不宣稱整輪效能驗收通過。ServerProbe 的 TEMP engine mocks 與 Luau 編譯只驗證 helper 統計、JSON 長度與生命週期邏輯，不能替代 Play。沒有修改前同條件 baseline、前景焦點證據、伺服器 CPU／尋路計時、多人或真手機資料。
