# 戰鬥預告片（2026-10-03）

在 Roblox Studio 裡自動導演一段約 77 秒的戰鬥影片，可以直接錄成宣傳影片。只在 Studio 執行，**不在正式專案** `default.project.json` 裡，不會出現在玩家的遊戲中。

## 使用方式
1. `.\rojo.exe build cinematic.project.json -o build/AOE2-cinematic.rbxlx`
2. 在 Studio 開啟 `build/AOE2-cinematic.rbxlx`，按 Play（F5）。客戶端會用大廳指令自動開一局（1 名玩家＋1 名簡單電腦、小地圖），不用手動操作大廳。
3. 開局約 4 秒後畫面變黑，接著影片開始。用 Roblox 內建錄影（選單 → 錄影）或 OBS 錄下 Play 視窗。建議把視窗拉成 16:9，播放中不要點擊地圖。
4. 片尾標題停留 4 秒後，畫面會交還給一般的 RTS 鏡頭與介面。要重拍就停止再按一次 Play。地圖種子固定，每次都是同一片戰場。

無畫面驗證：`bash tests/run-cinematic-studio.sh`（命令列啟動測試伺服器＋1 客戶端，收集 `[TRAILER]`、`[TRAILER_SHOT]` 紀錄到 `tests/cinematic-studio-latest.txt`）。

## 分鏡
| 秒數 | 段落 | 鏡頭 | 戰場上發生的事 |
|---|---|---|---|
| 0–4.5 | intro | 全黑，標題「一場決定帝國命運的戰役」 | 伺服器已排好兩軍與起火的敵方城堡 |
| 4.5–12.5 | muster | 沿我方前排低空橫移 | 兩軍對峙（間距 92，大於自動索敵半徑 72） |
| 12.5–18.5 | standoff | 從我軍後方升起，揭開兩軍與遠方城堡 | — |
| 18.5–26.5 | charge | 側面跟拍騎士衝鋒，馬蹄震動 | 雙方全軍各自攻擊最近的敵人 |
| 26.5–32.5 | volley | 弓兵肩後仰望，再壓低看交戰處 | — |
| 32.5–44.5 | clash | 環繞交戰中心，越轉越近 | — |
| 44.5–55.5 | siege | 衝車旁低角度仰望城堡 | 4 輛衝車、6 名護衛、2 台投石車攻城；城堡降到 30% 血量 |
| 55.5–62.5 | collapse | 遠景推近，城堡倒塌時強烈震動與閃光 | 倒塌段前 1.5 秒城堡只剩 1 點血，下一擊照正式流程摧毀 |
| 62.5–72.5 | finale | 拉高拉遠後淡出，標題「帝國鍛造坊／採集・建造・征服」 | — |

每側 46 人：前排長槍兵與步兵、第二排步兵、兩排弓兵與矛兵、兩翼各 3 名騎士、後方 2 台投石車。交戰、投射物、倒地、屍體、建築起火與倒塌全部是正式遊戲邏輯與現有動畫，預告片只負責排兵與運鏡。

## 畫面處理（只在本機）
- 2.39:1 電影黑邊，字幕顯示在下方黑邊。
- 隱藏 HUD、血條與 Roblox 內建介面，結束後只還原原本開著的。
- 關閉本機戰爭迷霧，看得見敵軍與城堡（只影響客戶端顯示）。
- 傍晚光（ClockTime 16.9）、提高對比、略降飽和、偏暖色調、Bloom、景深（對焦在注視點）與 SunRays。
- 鏡頭震動依「創傷值」累積與衰減：附近的石彈落地、衝車撞擊、陣亡與城堡倒塌都會讓鏡頭震動，倒塌時拉滿並閃一下。

## 檔案
- `src/ReplicatedStorage/Shared/CinematicRules.lua`：分鏡時間軸、緩動、淡入淡出、黑邊與震動數學。伺服器與客戶端共用同一張時間表，只同步一個開始時間 `TrailerStartAt`。
- `cinematic/BattleTrailer.server.lua`：用 Studio 專用的 `RTSBattleProbe` 排兵、蓋城堡並依時間軸下令。
- `cinematic/BattleTrailer.client.lua`：鏡頭、黑邊、調色、字幕與震動。綁在 `RTSCamera` 之後的 RenderStep，不修改遊戲本身的鏡頭腳本。
- `cinematic.project.json`、`tests/cinematic.spec.lua`（已加入 `scripts/verify.ps1`）、`tests/run-cinematic-studio.sh`。

## 調整
- 段落長度、字幕、標題：`CinematicRules.Stages`。
- 兵力與陣形：`BattleTrailer.server.lua` 的 `LINES`、`WIDTH`。
- 各鏡頭的位置與視角：`BattleTrailer.client.lua` 的 `SHOTS`。

## 限制
- 戰場位置依兩座主城的連線自動選擇；森林擋到的位置會少生成一些兵。放不下城堡時改用瞭望塔或兵營。
- 衝車若沒能在倒塌段前抵達城堡，城堡會晚一點倒，或在這段影片中沒有倒。
- 伺服器的模擬速度無法放慢，因此沒有真正的慢動作。
- 簡單電腦本身的部隊可能走進畫面。

## 開局方式的備註
- 第一版用 `RTSPlaceRole=Match`＋`RTSStudioSettings` 自動開局。在 `-task StartServer` 命令列測試伺服器上，伺服器出現「[RTS Travel] 無法取得對局資料：參戰名單無效。」，一直沒有進入對局。
- 推測原因（讀程式碼判斷，未實測）：命令列測試玩家的 UserId 是負數（Player1=-1），`PlaceRules.readTicket` 要求正整數，所以 Studio 的模擬票據被拒絕。Studio 單人 Play 使用登入帳號的正數 ID，正式伺服器的 UserId 也一定是正數，所以只影響 Studio 命令列測試伺服器的 Match 模擬。
- 現在改由客戶端以大廳指令（`LobbyTests.Start`）開局，和 combat-feel 測試相同，Play 與命令列測試伺服器都適用。

## 驗證（2026-10-03）
- `scripts/verify.ps1` 全部通過，包含 `cinematic.spec` 的 288 項檢查與 `cinematic/` 的 `-O0` 編譯。
- Studio 命令列測試伺服器＋1 客戶端（`tests/run-cinematic-studio.sh`，第三次執行，紀錄在 `tests/cinematic-studio-latest.txt`）：0 個錯誤，影片完整播完後交還 RTS 鏡頭。
  - 排兵：我方 38、電腦 44（障礙物擋掉部分位置），城堡放不下所以改放瞭望塔。誘餌成功觸發電腦的進攻波。
  - 對峙段結束時 82 名單位全部存活，衝鋒段才開打。衝鋒段鏡頭距最近的騎士 4–6 studs，震動 0.5 上下，峰值 0.98。
  - 塔在攻城段一直沒倒，到倒塌段才倒，倒下時鏡頭震動拉滿。HUD 與血條全程隱藏。
- 之後修正：橫移鏡頭的後半段原本拍到 0 個單位，改為注視點永遠在鏡頭前方。第四次執行（同一個戰場）中段畫面裡有 26 名單位、結尾有 9 名，0 個錯誤。
- 第四次執行也記錄了客戶端的 `Corpses`／`Ruins`：屍體有複製下來（最多 50 具、1392 個零件）。但塔倒塌後 `Ruins` 資料夾是空的（倒塌段 3.5 秒與 7 秒取樣都是 0 個子物件），和回歸測試發現的「遺骸複本是空的」一致。這是遊戲本身的問題，修好之前，倒塌鏡頭可能只看得到塔消失，看不到倒塌動畫。
- **未驗證**：實際畫面的美感（構圖、調色、字幕排版只用數值檢查，沒有人看過截圖）、Studio 單人 Play、其他地圖種子與 16:9 以外的視窗比例、錄影時的幀率。
