# 可切換隊形的 Studio 驗證

此原型新增方陣 `Box`、橫列 `Line`、縱隊 `Column`、楔形 `Wedge`、分散 `Spread`。正式請求為 `Command:FireServer("Formation", selection, key)` 與 `Command:FireServer("Order", selection, Vector3, key)`；省略移動的 `key` 時沿用選取單位的隊形偏好。村民與軍隊都能使用；採集、建造、交貨與攻擊仍使用既有目標模型指令。

`ReplicatedStorage.Shared.FormationTests` 是明確呼叫的整合測試。僅 require 不執行測試，不生成單位、不增資源、不寫權威位置，也不踢玩家。`Run()` 會移動該次測試局的單位、切換隊形、發送無效請求，最後以正式 Stop 清理；請用獨立建置與新 Play。原始碼修改前的備份由主代理保存在 `build/backups/formations-20261001/`。不要發布體驗或覆寫使用者原 place。

## 新單人 Play

1. Rojo 建置獨立輸出，開啟建置副本，啟動新 Play。以介面進入無對手的單人練習局；保留起始 3 村民與 1 斥候待命，沒有攜帶資源。
2. 在 **CLIENT** Command Bar 呼叫：

```lua
task.spawn(function()
 local report=require(game.ReplicatedStorage.Shared.FormationTests).Run()
 assert(report.complete,report.error or "隊形測試未完整完成")
end)
```

3. 模組會在基地清空區尋找沒有靜態障礙的 96 × 96 studs 區域，透過真正 `Command` 遠端完成五種隊形移動，等待所有受選單位抵達不同的伺服器目的地。核對方向向量、目的地間距、碰撞半徑與地圖邊界；另外用 `Formation` 指令原地切換縱隊，確認移動與重排完成。
4. 無效隊形、只有字串鍵的非陣列字典、包含非法成員的密集陣列、空／重複／超量選取、建築混入單位、NaN／無限／地圖外目標須保持己方隊形、指令、位置及四種資源不變。請求速率低於正式伺服器每秒補充額度，避免以限流誤判驗證成功。RemoteEvent 會序列化資料，不能假設混合陣列／字典的額外欄位或稀疏數字鍵原樣保留；混合鍵與稀疏表格另外由 `tests/formation.spec.lua` 直接檢查伺服器驗證函式，不宣稱那些原始 table 欄位已經跨端送達。
5. 五隊形另有地圖角落的目的地提交與半徑邊界檢查；之後立即 Stop，**沒有聲稱單位已實際走到角落**。Stop 必須清除 `FormationSlot` 並保留 `Formation` 偏好，且所有單位保持靜止。
6. 收集所有 `[FORMATION PASS]`、五份完整 `[FORMATION SNAPSHOT]` 和最後小型摘要 `[FORMATION COMPLETE]`；摘要僅保留隊形名稱，完整 slot 證據在各階段 SNAPSHOT，以避免 Studio 截斷過長 JSON。出現 INCOMPLETE、逾時或 Lua 錯誤時保留該局日誌診斷。單人沙盒沒有外方單位，`ownershipCovered=false` 是明確缺項，不算真正所有權或雙人同步驗證。

測試只檢查客戶端收到的伺服器資料。仍需看見實際地面／單位、操作實際 HUD 隊形按鈕、核對底部面板附近地面可點擊且 UI 不穿透；不能以 ModuleScript 或 CLI 語法通過代替畫面及輸入驗收。

## 真正雙人同步與所有權

1. 在另一份新建置啟動 **Server & Clients：2 Players**。兩個真正客戶端用正常大廳流程加入、準備並開局；雙方起始單位全部待命。不要重用先前單人 require 快取或測試局。
2. 第一位的 CLIENT 呼叫 `FormationTests.Run({allowMultiplayer=true})`，另一位保持閒置。這時實際外方單位的混合隊形／外方移動請求須原子拒絕，第一位結果應包含 `ownershipCovered=true`。不要讓 AI 或另一位同時下令，否則不能把其自行移動與非法請求造成的改變區分。
3. 以實際 HUD 框選第一位單位、切換楔形並移到空地，等待全部待命。正常抵達會保留 `FormationSlot`；這一步不要按 Stop。記下第一位玩家的真實 UserId。
4. 在 **SERVER、第一位 CLIENT、第二位 CLIENT** 各自明確呼叫相同 ownerId：

```lua
require(game.ReplicatedStorage.Shared.FormationTests).Snapshot(實際UserId)
```

5. 每份完整 `[FORMATION SNAPSHOT]` 的 generation、ownerId、phase 及 sorted `units` 陣列須相同，並且 `formation="Wedge"`、`order="待命"`、每個 slot 非空。`context` 與 `observerId` 代表不同觀察端，預期不同。保存三端原始日誌；任何客戶端未收到或資料不一致均未通過。確認兩個畫面呈現同一組位置與相同玩家色。
6. 用第一位 HUD 切換另一隊形，再重複三端快照。第二位嘗試選擇／下令第一位單位須被阻擋；第二位自己隊形仍可獨立變更。另確認框選多單位、單選、沒有選取、混合隊形顯示與小地圖右鍵移動。

## 真正玩家離開清理

在上面的 SERVER 先啟動唯讀觀察，再關閉第一位測試 client；模組不會自行關閉或踢出任何玩家：

```lua
task.spawn(function()
 local report=require(game.ReplicatedStorage.Shared.FormationTests).WatchDeparture(實際UserId,45)
 assert(report.complete,"玩家離開後的隊形單位清理未完成")
end)
```

必須出現 `[FORMATION DEPARTURE COMPLETE]`，包含真正 PlayerRemoving 與原受選玩家全部 managed 單位／建築 Parent=nil。另一位仍在時確認其畫面移除離開者單位，自己的單位仍在；若最後一位離開，獨立 SERVER 仍需確認 MatchPhase 返回 Lobby。這項觀察不聲稱涵蓋伺服器私人 Lua table 的記憶體分析。

## 本次驗證狀態

`FormationTests.lua` 已通過本機 Luau 語法編譯。Computer Use 的 `@oai/sky` 初始化與 Studio 視窗列舉成功；主代理另外操作新的 r3 Studio Play，在 2026-10-01 13:38–13:39 取得 120 項檢查：五隊形全部真正抵達，原地 Column 重排、一般移動沿用 Column 以及 Stop 停止均通過。原始日誌為 `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20261001T053325Z_Studio_20215_last.log`。

該輪在「非陣列表格」fixture 停止，整體結果為 INCOMPLETE。原 fixture 使用 `{unit, extra=true}`；混合資料經 RemoteEvent 序列化後不再保留這項非法結構，成為可接受的單一單位陣列，故不能要求伺服器拒絕。已改用只有字串鍵的 `{unit=unit}` 字典，並將網路稀疏表格測試改成保留非法成員的密集陣列；混合鍵／稀疏資料仍在直接伺服器函式 fixture 驗證。完整修正版須在新的 Play 重跑，不能把 r3 部分通過寫成完整通過。

修正版在新的 `build/AOE2-formations-studio-r4-20261001.rbxlx` Play，於 2026-10-01 13:45–13:46 完整通過 **210 項**檢查。五隊形全部真正抵達，原地切換、偏好沿用、Stop、15 種無效請求不改變己方狀態／不扣資源，以及五隊形邊角目的地提交與半徑邊界通過。角落只驗證目的地並立刻 Stop，未宣稱真正走到角落。沒有匯入原有模型，使用正式替代外觀；相機、地面與資源 HUD 正常初始化。

來源清單為 `tests/formations-r4-source-manifest-20261001.json`；保留日誌 `tests/formations-r4-studio-results-20261001.txt`、精簡結果 `tests/formations-r4-studio-summary-20261001.json`，對應 Studio 原日誌 `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20261001T054359Z_Studio_29961_last.log`。完整本機 verify 與 Rojo build 通過，記錄在 `tests/formations-cli-results-20261001.txt`；其中陣形幾何與實際 handler fixture 為 507684 項。

另在同一 r4 Play 使用實際 `PlayerGui` 的 `RTSSelectionProbe`／`RTSHUDProbe`，確認己方四單位可進入陣形頁、五張卡片及其父容器可見、散開標記為使用中、建造分類卡隱藏、陣形入口可見，取得 `[FORMATION_UI_COMPLETE] formation`。沒有使用 Command Bar 的 GUIManager require 複本代替正式介面狀態。以實際滑鼠點擊橫列卡片後看見部隊重新排列；完整鍵盤、小地圖及所有原生 GUI 輸入仍未追加全面回歸。

**雙人所有權／同步、真正玩家離開、真實手機觸控、本輪所有建築與資源不足的 Studio 回歸仍未驗證。** 不以單人通過或既有版本的測試記錄替代這些項目。

