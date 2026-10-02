# 生產佇列與集合點

本輪將 AOE2 的生產建築操作補進 RTS 測試版：自己的已完工生產建築可設定集合點，村民的新生產單位可直接前往資源工作。官方教學亦將訓練、科技與集合點列為建築的操作內容：[Controlling Your Empire & Gathering Resources](https://www.ageofempires.com/learn-to-play/control-resources-aoe2/)。這些改進不是完整 AOE2 複製或完整遊戲的聲明。

## 行為

- 選取自己的生產建築，右鍵地面、中立資源或自己的已完工農田設定集合點。HUD 的旗幟動作可改用一次性點選模式，支援桌面與觸控；右鍵或 Esc 可取消模式。
- 新村民前往資源採集；軍隊前往集合位置。已耗盡的資源會在下一次訓練完成時尋找同類可採集資源。客戶端只顯示本地旗幟，不生成單位、不決定採集收入。
- 點選訓練佇列項可取消該項，包括目前訓練項，並退回當時伺服器扣除的全部成本、釋放預留人口。取消等待中的項目不重設頭項進度。拆除建築與刪除單位沿用原本不退款規則。
- 佇列每次入列、完成或取消時推進版本；HUD 送出它所顯示的版本。若完成與點擊同時發生，過時請求會被拒絕，不會誤取消下一個單位或多退資源。對局報告一併沖銷實際退款的淨支出。
- 遠端請求沿用伺服器頻率限制，檢查所有權、已完工生產建築、合法資源、有限座標及地圖邊界。玩家離開、建築拆除或離開管理資料夾會清除集合點狀態。
- 大廳不再先生成標準戰場資源。正式開局進入 `Starting` 後，依已確認設定生成地圖，完成後才生成各陣營；保留資源資料夾初始化與未知使用者模型。

## 介面 API

`GUIManager` 的 callbacks 增加 `rally()`、`clearRally()`、`cancelTraining(index, queueRevision)`。現有 build/train/research/age/stop/trade 等接口保留。集合點模式以本地玩家屬性 `RTSRallyPlacement` 顯示。

每座建築的複製屬性：

| 屬性 | 用途 |
| --- | --- |
| `QueueKind_1` 至 `QueueKind_5` | 逐格單位種類；不存在的項目清空。 |
| `QueueRevision` | 佇列變動版本；進度更新不改版本。 |
| `QueueCount`、`TrainingProgress`、`TrainingRemaining` | 數量與頭項進度。 |
| `RallyPosition`、`RallyType`、`RallyTargetName` | 集合點位置、`move/gather` 與名稱；清除時全部置空。 |

Studio 才建立 `RTSSelectionProbe`，供測試用同一個執行中客戶端的選取狀態，避免 Command Bar require 的 UI 快取與實際 `PlayerGui` 分離。這是本地 `BindableFunction`，不對正式遊戲建立測試入口。

## 驗證與限制

`tests/production.spec.lua` 已通過 92 項純邏輯檢查，涵蓋頭／中間／尾項取消、保留其餘佇列及進度、精確成本、重複與過時版本、完成競態、非法索引、淨支出沖銷、集合點建築與資源授權。相關 Luau 編譯通過。

`Shared/ProductionTests.lua` 只有明確呼叫才執行，會正常扣款、建房屋／兵營並訓練單位。需先開新的豐富資源單人沙盒，再在客戶端 Command Bar 執行：

```lua
task.spawn(function() require(game.ReplicatedStorage.Shared.ProductionTests).Run() end)
```

測試涵蓋正常佇列退款與人口、過時／重複取消、非法索引、資源集合點新村民實際採集、清除集合點、地面集合點的新村民與軍隊移動，以及邊界／型別拒絕。此文件撰寫時尚未取得本輪 Studio Play 結果；Luau 與純邏輯檢查不能代替實機。觸控手勢、HUD 卡片實際點擊、雙人所有權與離開清理仍須由 Studio 驗收確認。

修改前備份：`C:/Users/user/AppData/Local/Temp/AOE2-before-production-20261001-041550`。未發布 Roblox 體驗、未覆蓋原 place、未建立 commit。
