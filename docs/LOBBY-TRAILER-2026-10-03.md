# 大廳播放戰鬥預告片（2026-10-03）

把 77 秒的戰鬥預告片（`docs/BATTLE-TRAILER-2026-10-03.md`）放進大廳。大廳伺服器沒有戰場，無法即時重演那場戰鬥，所以預告片要先錄成影片、上傳成 Roblox 影片資產，再由客戶端的 `VideoFrame` 播放。

## 玩家看到的內容
- **廣場大螢幕**：城堡兩側的後牆草地上各有一面 16:9 大螢幕（56×31.5 studs），斜向出生台。
  - 左側螢幕靜音循環播放預告片。
  - 右側是海報：「帝國鍛造坊／採集・建造・征服」，附上觀看提示。
- **「▶ 預告片」按鈕**：大廳閒置時出現在左上角，位置在「新手教程」旁邊。按下後全螢幕有聲播放，全黑底、16:9 置中，附進度條與「✕ 關閉」鍵，手把可按 B 關閉。
  - 播完自動關閉，配樂在播放期間完全靜音（`Music:Hush`）。
  - 加入房間、出發或離開大廳時按鈕會隱藏；如果正在播放，會直接關閉。
- **還沒有影片時**（`videoId = 0`，或影片載入失敗、逾時 20 秒）：
  - 左側螢幕改為輪播預告片字幕字卡，每張 4.5 秒，有淡入淡出；開啟「減少動態」時不淡入淡出。
  - 觀看按鈕不出現，海報提示改成「戰役預告片即將上映」。

## 上架步驟（需由使用者操作）
1. 錄影：依 `docs/BATTLE-TRAILER-2026-10-03.md` 用 `cinematic.project.json` 在 Studio 播放，用 OBS 或 Roblox 錄影錄成 16:9。建議 1920×1080，從片頭黑畫面錄到片尾標題結束。
2. 上傳：在 Creator Hub 上傳影片。Roblox 對影片上傳有帳號驗證、長度與審核限制，以 Creator Hub 當下的說明為準。審核通過後會取得資產 ID。
3. 把資產 ID 填入 `src/ReplicatedStorage/GameData/GameConfig.lua` 的 `Config.Lobby.trailer.videoId`。數字、數字字串或 `rbxassetid://…` 都可以。
4. 重新 build 並發布大廳 place。

## 檔案
- `GameConfig.Lobby.trailer`：影片 ID、螢幕位置、大小、角度與字卡秒數。
- `ServerModules/LobbyWorld.lua`：兩面螢幕的框架、支架、屋簷，以及右側的靜態海報。左側的 `TrailerScreen` 只是黑色面板，帶 `LobbyTrailerScreen` 屬性。
- `Shared/LobbyTrailerView.lua`：只在客戶端執行。
  - 大螢幕用 PlayerGui 裡的 SurfaceGui（`ResetOnSpawn=false`），全螢幕用 `AOE2_LobbyTrailer` ScreenGui（DisplayOrder 10）。
  - 只在大廳時播放或更新字卡，不在每幀遍歷 Workspace。
  - 開啟全螢幕時，大螢幕會暫停，同一時間只解碼一支影片。
- `Shared/LobbyTrailerRules.lua`：純邏輯，包含影片 ID 驗證、字卡、16:9 尺寸與進度。測試在 `tests/lobby_trailer.spec.lua`，已加入 `scripts/verify.ps1`。
- `GUIManager.lua`：`WatchTrailerButton`（紅色大廳按鈕，已加入 hitAreas）。全螢幕開啟時 `IsModalOpen()` 為 true。
- `MusicDirector.lua`：`Music:Hush(on)` 讓配樂完全靜音或淡回原本音量。`GetStats()` 多了 `hushed`。

## 驗證
- `scripts/verify.ps1` 全部通過，包含 `lobby_trailer.spec` 53 項、`-O0` 編譯與 Rojo build。
- **未在 Roblox Studio 驗證**，以下都還沒實測：
  - 兩面螢幕的位置是否被城堡、傳送門或樹擋住，大小與角度是否合適，出生台看過去的構圖
  - 字卡輪播與「▶」「✕」符號的字形
  - 左上角按鈕與新手教程按鈕並排的樣子，以及在手機上的大小
  - 全螢幕的黑底是否擋住點擊，安全區域是否正確
  - 真實影片資產的載入、循環、音量、播完自動關閉與配樂靜音
  - 離開大廳時是否停止播放
  - 載入失敗時是否改回字卡
- 實際影片尚未錄製與上傳，所以目前只能看到字卡版本。
