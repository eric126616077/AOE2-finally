# 倒地、倒塌與資源消失動畫（2026-10-03）

## 變更
- **單位陣亡倒地**：伺服器 `Factory.corpse` 另外記錄 `CorpseBase`、`CorpseLay`、`CorpseExpires`。客戶端 `Remains.client.lua` 讓剛出現的屍體在 0.55 秒內由直立轉為平躺，最後輕微回彈。屍體在伺服器移除前 1.5 秒沉入地面並淡出。
- **建築倒塌**：只有在戰鬥中被摧毀的完工建築，伺服器會用 `Factory.ruinBuilding` 在 `workspace.Ruins` 建立外觀複本：顏色偏灰，最多 180 個零件，不碰撞、不可點選、不參與查詢。客戶端播放 1.8 秒的搖晃、傾斜、下沉、淡出與揚塵。原建築仍在同一步立即移除。
- **資源耗盡**：伺服器在資源移除前呼叫 `Factory.ruinResource`。樹木從底部倒下並淡出，樹樁、木頭與切口只淡出。金礦、石礦與漿果等其他資源下沉並淡出。
- 計時常數與預算都放在 `Shared/RemainsRules.lua`。單位倒地最多同時 32 個，建築倒塌最多 4 棟，伺服器最多保留 24 個複本。超過上限、超出畫面、在迷霧中，或複本已播放過半時，都會直接隱藏。
- 「降低動態效果」開啟時，不倒地、不下沉、不搖晃、不揚塵，只保留淡出。

## 為何由伺服器建立複本
Roblox 預設使用延遲訊號（Deferred）。伺服器在 HP 或 Amount 歸零的同一步就移除模型，客戶端的屬性事件執行時，模型與子零件已經被銷毀，無法複製。所以複本由伺服器建立，做法與既有的屍體機制相同。

## 驗證
- `scripts/verify.ps1` 全部通過，包含 `-O0` 編譯、`tests/remains.spec.lua` 的 2000 項檢查、ModelFactory mock 的 704 項檢查，以及 Rojo build。
- **尚未在 Studio Play 驗證**：倒地方向與穿地情形、建築倒塌外觀、樹木倒向、迷霧中的隱藏、降低動態效果、雙人同步、中途加入時的屍體與複本狀態，以及大型戰鬥的效能。
- `Factory.ruin` 尚無 mock 測試，因為現有 mock 沒有 `workspace:GetServerTimeNow` 與 `Debris`。

## Studio 命令列驗證（remains-validation）
`remains-validation.project.json` 比正式專案多映射兩個測試腳本：`tests/remains-studio.server.lua`（Studio 專用的 `RemainsTestHelper` 遠端，加上伺服器端檢查）與 `tests/remains-studio.client.lua`。Play 開始後會自動以正常大廳指令開局：Small 地圖、1 位簡單電腦、豐富資源、征服。不必操作 Studio 視窗。

執行方式（用 Git Bash；第一個參數是含有 `remains-validation.project.json` 的資料夾，可以是主資料夾或 worktree）：

```bash
bash C:/Users/user/Desktop/AOE2-finally/build/run-studio-harness.sh "$PWD" remains-validation.project.json 2 250 tests/remains-studio-latest.txt REMAINS
```

- **玩家數**：建議 2 位。Player1 負責主控，Player2 觀察。改為 1 位也能執行，但會少掉雙人同步，也不會檢查遠方事件在另一個客戶端上是否立即隱藏。
- **等待秒數**：建議 250 秒。正常流程大約在 Studio 啟動後 150 秒內結束；客戶端腳本從啟動起算 210 秒會逾時，並印出 `INCOMPLETE`。
- **判讀**：只看 Player1 log 的最後一行。全部通過時為 `[REMAINS] COMPLETE n passed, 0 failed`，其他情況為 `[REMAINS] INCOMPLETE …`（包含通過與失敗數，以及中斷或逾時原因）。總數 n 已包含伺服器的 `[REMAINS SERVER]` 檢查，以及 Player2 回報的 `[REMAINS Player2]` 檢查。Player2 自己的 log 最後一行是 `[REMAINS Player2] DONE …`。

測試捷徑只用於前置作業，全部走 Studio 專用的 `RTSBattleProbe`：直接放置電腦的已完工房屋、生成單位、把目標生命設為 1、把資源存量設為 1。擊殺與摧毀仍經過正式的 `damage()`，由 probe 的 attack 下令；採集則經過正式的 `Command` `Order`。伺服器會在屍體與複本的零件上寫入測試用屬性 `RemainsServerCFrame`，客戶端用它比對本機動畫中的實際姿勢。正式腳本不讀取這個屬性，也沒有修改任何正式程式碼。

涵蓋項目：
- **屍體**：檢查三個屬性；剛出現時是否為直立姿勢（`base·lay⁻¹·base⁻¹·最終位置`）；倒地結束後是否回到伺服器的平躺位置；最後 1.5 秒 `LocalTransparencyModifier` 是否上升並下沉；伺服器是否在 `CorpseExpires` 準時移除。使用正式的 20 秒壽命，沒有覆寫 Config。
- **建築倒塌**：檢查 `RuinKind=building`；是否產生 5 個 `CollapseDust`；零件是否下沉並淡出到 1；是否在 `RuinSeconds+0.5` 秒移除；揚塵是否清除。
- **樹木與資源**：樹木 `tree` 複本離地 1.5 以上的零件是否旋轉倒下；金礦（找不到時改用石礦或漿果）`resource` 複本是否下沉並淡出。
- **立即隱藏**：分成兩種情況。畫面外的倒塌，以及畫面內但位於迷霧中的倒塌（由巨型投石機在視野外摧毀）。都會檢查一出現就 `LocalTransparencyModifier=1`、不移動、不揚塵。
- **降低動態效果**：屍體一出現就是平躺，只淡出不下沉；建築沒有揚塵、不移動，只淡出。
- **清理**：檢查 Ruins 已清空、沒有殘留揚塵、沒有過期屍體；投降並回到大廳後，客戶端與伺服器的 Corpses／Ruins 都清空。雙人時，Player2 必須看到伺服器建立的全部屍體與複本。

未涵蓋：
- 同時動畫數量上限（MaxFalls／MaxCollapses／MaxRuins）。
- 中途加入時，已過半的複本是否直接隱藏。
- 大型戰鬥的效能。
- 倒地方向與穿地的目視外觀（只比對 CFrame，沒有截圖）。

背景視窗幀率很低時，淡出取樣可能不足。這個 harness **尚未實際在 Studio 執行過**。
