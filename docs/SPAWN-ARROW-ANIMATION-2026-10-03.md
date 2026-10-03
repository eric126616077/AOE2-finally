# 新單位出場與箭落地動畫（2026-10-03）

## 新單位出場
- 訓練完成或離開駐軍時，伺服器 `Factory.markSpawn` 會記錄兩個屬性：`SpawnFrom` 是建築占地邊緣往內 1 stud 的點，`SpawnAt` 是伺服器時間。
- 伺服器的位置、碰撞與指令在生成那一刻就在出生點，不受這段動畫影響。
- 客戶端 `UnitMotion` 會在屬性出現後 0.6 秒內追蹤到新單位時播放。單位從建築邊緣面朝外走到出生點，最後 25% 的路程轉回伺服器的朝向，並播放走路步態。
  - 時間依單位速度計算，限制在 0.35 到 1.2 秒。距離超過 30 studs 時不播放。
  - 若單位立刻收到集結點移動指令，出場的位移會與伺服器移動疊加，最後收斂。
- 開啟「降低動態效果」時不播放。不使用透明度，所以不會蓋掉戰爭迷霧對敵方單位的隱藏。
- 計時常數在 `MotionRules.lua`：`SpawnFresh`、`SpawnMin`、`SpawnMax`、`SpawnMaxDistance`、`SpawnDefaultSpeed`。

## 箭與標槍落地
- 投射物抵達時，若落點 2.5 studs 內仍有單位，就照原本的方式消失並閃一下。
- 若沒有命中單位、但飛行方向前方有建築的可見表面，箭會插在牆上。查詢時會穿過透明的占地方盒繼續找。
- 都沒有時，表示目標已經離開，箭以 38 度斜插在地面上。
- 插著的箭停留 4 秒，最後 0.6 秒淡出，同時最多 40 支，超過時先移除最舊的。所插的建築被移除時，箭會一起消失。
- 插著的箭放在獨立的 `workspace.RTSStuckArrows`，主零件改名為 `StuckArrow`。現有 Studio 測試會計算 workspace 內的 `ArrowEffect` 來量駐軍齊射支數，也要求 `RTSClientEffects` 在關閉回饋或玩家離開後 2～3 秒內清空；停留 4 秒的箭若留在原資料夾或保留原名，會讓這些測試誤判。
- 石彈與鉛彈不會留下。開啟「降低動態效果」時不留下，並清除已插著的箭。
- 這些純屬本機外觀，伺服器的命中判定不變。即使箭插在地上，原本鎖定的目標仍可能受到傷害，與原本箭飛到舊位置的行為相同。
- 常數在 `RemainsRules.lua`：`StuckSeconds`、`StuckFadeSeconds`、`MaxStuck`、`StuckPitch`、`StuckBury`，判斷函式為 `ArrowLanding`。

## 特效物件重複利用
- 新增 `Shared/EffectPool.lua`，為純邏輯，建立、隱藏與銷毀由呼叫端注入。`UnitMotion` 的箭、標槍、石彈、鉛彈、槍口煙、命中閃光、採集粒子與受擊／交貨／完工外框都從池中取用，不再每次 `Instance.new` 再交給 `Debris` 銷毀。
- 使用中的物件放在 `RTSClientEffects`，保留原本名稱，`ChildAdded` 照常觸發；歸還時取消補間並設 `Parent=nil`，所以閒置時資料夾仍是空的，現有測試的計數與清空條件不變。
- 每次取出都換新的租約編號，過期的計時器無法收回已被重用的物件。飛行中的箭插在地上時直接換手，沿用同一組零件。
- 同時使用上限仍為 80 個暫時特效，另外加上最多 40 支插著的箭；每種物件最多保留 48 個閒置。`RTSMotionProbe` 的 stats 新增 `effectsActive`、`effectsIdle`、`effectsCreated`、`effectsReused`、`stuckArrows`，可以在 Studio 量測重用率。
- 健康條錨點與遺骸揚塵數量少，沒有放進池裡。

## 驗證
- `scripts/verify.ps1` 全部通過，包含 `-O0` 編譯、`motion.spec` 的 699 項、`remains.spec` 的 2007 項、`effect_pool.spec` 的 17 項，以及 Rojo build。
- **尚未在 Studio Play 驗證**：出場方向與穿牆情形、旋轉建築的邊緣、集結點疊加、插在牆上與地面的箭的角度與深度、插著的箭隨建築移除而消失、降低動態效果、雙人同步，大型弓箭戰的效能（每支箭抵達時做 1 次範圍查詢與最多 4 次射線檢測），以及物件池在實際戰鬥中的重用率。也需要重跑 FeedbackBattle、FeedbackConstruction、FeedbackMultiplayer、garrison 與 combat-feel 這幾組依賴 `RTSClientEffects` 的 Studio 測試。

## Studio 命令列驗證（anim-validation）
`anim-validation.project.json` 比正式專案多映射兩個測試腳本：`tests/anim-studio.server.lua`（Studio 專用的 `AnimTestHelper` 遠端與伺服器端出生點稽核，只在 `RunService:IsStudio()` 時建立）與 `tests/anim-studio.client.lua`。Play 開始後自動以正常大廳指令開局：Small 地圖、1 位簡單電腦、豐富資源、征服。不必操作 Studio 視窗。

執行方式（Git Bash；第一個參數是含有 `anim-validation.project.json` 的資料夾，可以是主資料夾或 worktree）：

```bash
bash C:/Users/user/Desktop/AOE2-finally/build/run-studio-harness.sh "$PWD" anim-validation.project.json 2 330 tests/anim-studio-latest.txt ANIM
```

- **玩家數**：建議 2 位。Player1 主控全部項目；Player2 在自己的主城獨立驗證一部分（市鎮中心訓練村民的出場、射擊電腦房屋的插箭、自然到期），再回報給伺服器。1 位也能執行，只是少了第二個客戶端的確認。
- **等待秒數**：建議 330 秒。客戶端腳本從啟動起算 270 秒逾時並印出 `INCOMPLETE`；正常流程預估在開局後約 2～2.5 分鐘結束。
- **判讀**：只看 Player1 log 的最後一行：全部通過為 `[ANIM] COMPLETE n passed, 0 failed`，其他情況為 `[ANIM] INCOMPLETE …`（含通過／失敗數與中斷或逾時原因）。n 已包含伺服器 `[ANIM SERVER]` 的檢查與 Player2 回報的檢查；Player2 自己的最後一行是 `[ANIM Player2] DONE …`。

前置捷徑都走 Studio 專用的 `RTSBattleProbe`：放置自己的已完工房屋（人口）與馬廄、電腦的已完工房屋、生成弓箭手與電腦村民並下攻擊命令、把要摧毀的房屋生命設為 1。訓練、集結點、駐紮與離開駐軍都走客戶端正式的 `Command`（`Train`、`Rally`、`Garrison`、`Ungarrison`），所以 `SpawnFrom` 一律來自正式的 `productionStep`／`Garrison.eject`。為了縮短等待，伺服器測試腳本把伺服器端 `Config.Units.scout.trainTime` 改為 3 秒（只在這個驗證專案）；村民使用正式訓練時間。沒有修改任何正式程式碼。客戶端只讀實際實例與實際 PlayerScripts 裡的 `RTSMotionProbe`。

涵蓋項目（所有等待都以 `MotionRules`／`RemainsRules` 的常數計算期限）：
- **出場**：伺服器檢查每個真人新單位的 `SpawnFrom` 在「建築中心→出生點」連線上、在占地內、往外 1 stud 正好到占地邊緣（以占地 CFrame 計算，旋轉也成立）、高度同 Root，`SpawnAt` 是剛剛的伺服器時間。客戶端以同一個 `MotionRules` 時間軸重建沒有出場時的位置，檢查：在 `SpawnFresh` 內收到；第一個畫面在 SpawnFrom 那一側（剩餘比例 ≥ 0.5）；外觀零件 Body 跟著顯示位置；出場位移逐格縮小；剩餘比例 ≥ 0.3 時面向外；沒有瞬移；依 `SpawnDuration` 結束；播放步態；伺服器 Root 不動；最後位置與朝向等於 Root。來源有市鎮中心訓練、馬廄連續訓練 4 位斥候騎兵、2 位村民離開駐軍。
- **旋轉占地**：遊戲中只有城門可旋轉，它不訓練也不駐軍，`Factory.model` 的占地 CFrame 永遠軸對齊，所以實機不會從旋轉占地出場；伺服器檢查這個設定，並改以非正方形的馬廄（4×3）確認 X 面與 Z 面都有單位正確走出。
- **集結點**：正式 `Rally` 後訓練，出場位移與伺服器移動疊加，單調縮小、沒有瞬移，抵達停下後顯示位置收斂到 Root。
- **箭**：電腦村民跑向遠處誘餌、自己的弓箭手追射 → 地面 `StuckArrow` 角度 38°、露出部分在 `GroundY` 入地；射擊電腦房屋 → 沿箭身射線在入點命中房屋的不透明零件、水平方向朝向房屋中心（即飛行方向）；房屋被摧毀時插在上面的箭 0.2 秒內消失；自然到期的箭在 `StuckSeconds` 移除、最後 `StuckFadeSeconds` 才淡出；同時數量不超過 `MaxStuck`；停火後 `effectsActive` 等於 `stuckArrows`。
- **降低動態效果**：開啟時已插著的箭立即清除、投射物立即歸還；開啟期間不產生投射物也不插箭；新單位直接在出生點；關閉並停火後 `RTSClientEffects` 清空。
- **特效池與清理**：閒置時 `effectsActive=0`、`stuckArrows=0`，兩個資料夾為空，workspace 沒有 `ArrowEffect`／`StuckArrow`；`effectsReused>0`；`effectsCreated` ≤ 120；投降回大廳後同樣清空，伺服器沒有留下測試單位。

未涵蓋：
- 降低動態效果期間 `WorkEffect` 與受擊外框（UnitMotion 本來就不因這個設定停用）。
- 標槍、石彈、鉛彈的外觀（只用弓箭手）；防禦建築齊射的插箭；`AOE.releaseVillagers`（鐘聲後離開）的出場路徑。
- 物件池上限滿載與 `MaxStuck` 淘汰最舊的箭；大型弓箭戰的效能。
- 出場是否穿過牆、箭插入深度的目視外觀（只比對 CFrame 與射線，沒有截圖）。
- 中途加入時正在出場的單位。

風險：地面箭依賴電腦村民確實跑開（電腦 AI 若改派任務或敲鐘，最多換位置重試一次）；馬廄長短邊依賴出生點周圍沒有障礙；背景視窗幀率很低時取樣可能不足。這個 harness **尚未實際在 Studio 執行過**。
