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
