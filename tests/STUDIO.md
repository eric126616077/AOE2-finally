# Studio 驗收紀錄與重現步驟

## 目前已取得的實機證據（2026-09-30）

以下結果來自真正的 Roblox Studio Play、雙人客戶端、實際 RemoteEvent 與 Studio log。CLI 編譯或純邏輯測試不列入引擎通過數；舊版測試結果也不延伸到新增功能。

| 範圍 | 已取得的結果 | 證據與限制 |
| --- | --- | --- |
| 基礎引擎流程 | 35 項通過，2026-09-30 15:07（Asia/Taipei）。 | [latest-studio-results.txt](latest-studio-results.txt) 有 `[RTS_TEST COMPLETE]`。涵蓋地面／HUD 複製、開局、建屋施工與扣款、非法建造拒絕、訓練、採集交貨、停止、投降、結果畫面與返回大廳。 |
| 真正雙人流程 | 29 個 PASS，2026-09-30 15:25–15:31（Asia/Taipei）。 | [latest-multiplayer-results.txt](latest-multiplayer-results.txt) 記錄兩名真實玩家、房主權限、跨端建築／訓練複製、跨玩家指令拒絕、實際玩家退出後清理、勝利與房主轉移。不是以 AI 代替第二個客戶端。 |
| 手動介面操作 | 在大型 1536 地圖、Auto 補三個 AI 的對局，觀察到採集、建造、訓練、小地圖操作與 AI 軍隊出現。 | 屬於實際操作觀察，尚未完成長局 AI、滿人口與效能壓力驗收。 |
| 進階發展測試 | **完整流程未驗證。** | 首次執行在開局旗標尚未完全複製時失敗；修正條件等待並編譯通過後，未取得新版 `[RTS_PROGRESSION COMPLETE]`。 |

基礎測試當時的 AI 人口斷言為 `>=4`，四人可全部來自起始三村民與斥候，不能據此證明 AI 已額外訓練村民。人口 `>=5` 仍可能包含預留的訓練佇列，也不足以證明新村民已生成。新版 `StudioTests` 已改為核對 `Workspace.Units` 中 `OwnerId` 屬於該 AI 且 `UnitType=villager` 的真正實例數，要求超過 `Config.Settings.startingVillagers`；這項嚴格斷言尚未重新完成實機驗證。保留 35 項通過紀錄的原始範圍，不把它當成最新版全部通過。

進階測試現已等待 `Playing`、`Sandbox=true`、`MatchSize=768`、`AICount=0`，以及初始玩家與重要單位數值完整複製。後續新單人 Play 的原生輸入工具反覆回報 `failed to activate captured window`，因此已停止原生電腦輸入；這是無法繼續驗收的工具限制，不能視為進階遊戲流程通過，也不能據此判定後續時代或科技流程失敗。

上述通過紀錄之後另調整了 `UnitMotion` 的晚到部件追蹤、`BuildingController` 的未知障礙預覽，以及伺服器指令冷卻與人口容量處理。進階測試另修正農田完工後自動採集所造成的容量斷言時序：驗證最大容量與合法剩餘量，並透過正常停止指令固定後續成本測量。這些最後修改沒有完成整體 Studio 重跑；基礎 35 項與雙人 29 個 PASS 是本輪較早版本的證據，不是最新整體建置的通過證明。

## 共通前置條件

1. 使用最新 `build/AOE2.rbxlx`，或確認 Rojo 已同步最新原始碼。無模型建置與保留使用者模板的原 place 要分別驗證。
2. 更新遊戲腳本後停止目前測試，重新開 Play。已執行 Script 不保證因 Rojo 熱同步而重新初始化。
3. 所有下列呼叫都放在 **客戶端** Command Bar；若在伺服器執行，測試會拒絕。`require` 本身不開始測試，必須明確呼叫方法。
4. 測試會扣除資源、建立建築、生成單位、投降或重開對局，請使用新的測試工作階段。
5. Command Bar 的 ModuleScript 快取與遊戲 LocalScript 狀態分離。HUD 檢查讀取真正的 `PlayerGui`，不能把 Command Bar require 的介面模組狀態當作正在運行的 HUD。
6. 保留 Output／log 的 PASS、FAIL、COMPLETE 與腳本錯誤。只有對應 COMPLETE 與完整記錄能支持該流程通過；畫面看起來正常不能替代遠端權限、經濟或勝負驗證。

## 單人基礎流程

開新的單人 Play，保持大廳，客戶端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.StudioTests).Run()
end)
```

此流程使用小地圖、豐富資源、一個簡單 AI。測試建造房屋、扣款、重疊與不合法座標拒絕、村民訓練、尋路、有限資源採集、攜帶與交貨、停止；最後投降並返回大廳，確認 AI 狀態清除。

成功結尾為 `[RTS_TEST COMPLETE]`。需重新執行最新版以確認 AI 真正新增村民實例的嚴格條件。這個測試沒有涵蓋 18 種建築、四個時代、全部科技或完整軍事對抗。

## 真正雙人流程

使用 Studio 的 Server & Clients 測試啟動 **兩個玩家客戶端**，兩人都保持新大廳。房主可由 `workspace:GetAttribute("HostUserId")` 與本機 `Players.LocalPlayer.UserId` 判別。

先在非房主的客戶端執行，驗證不能自行開始對局：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.MultiplayerTests).RunOwnership()
end)
```

然後在房主的客戶端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.MultiplayerTests).RunHost()
end)
```

此呼叫開始 Small／0 AI／Rich 對局，等待兩方市鎮中心、三村民與斥候複製，並由房主正常建屋與訓練村民。看到 `[RTS_MULTI HOST READY]` 後，在非房主客戶端再次執行 `RunOwnership()`。檢查房屋同步、不能移動／停止對方村民、不能使用對方建築訓練或研究、非有限座標與突發請求不扣款、不生成非法單位。完成時印出 `[RTS_MULTI OWNERSHIP COMPLETE]`。

在打算保留的非房主客戶端掛上退出觀察器：

```lua
require(game.ReplicatedStorage.Shared.MultiplayerTests).ObserveCleanupClient()
```

看到 `[RTS_MULTI CLEANUP ARMED]` 後，退出另一位房主玩家的客戶端，保留伺服器與觀察者客戶端。不要直接結束整個 Server & Clients 工作階段，否則無法觀察真正的 `PlayerRemoving` 清理。應印出 `[RTS_MULTI CLEANUP COMPLETE]`，並看到退出玩家的單位與建築消失、存留玩家勝利、房主權限轉移。

本輪 29 個 PASS 包含上述流程。它仍未涵蓋雙方長時間採集與戰鬥、全部單位傷害同步、重連與觀戰者邊界情況。

## 單人進階發展流程：尚待完整重跑

開新的單人 Play 大廳；或先完成對局並返回大廳。不要在兩個活躍玩家或正在進行的一般對局中呼叫：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.ProgressionTests).Run()
end)
```

此測試透過正常遠端請求開始 Small／0 AI／Rich 沙盒，整體最多五分鐘，不改伺服器資源、不加速研究、沒有管理後門。完整範圍包含：

- 初始市鎮中心不能代替時代前置；兩座同類磨坊不能代替兩種不同的黑暗時代建築。
- 織布機真實研究時間、村民生命／護甲加成、斥候不受影響、重複研究不再次扣款。
- 磨坊、伐木場、兵營、農田、市集、兵工廠的正常施工；步兵生產與農田容量。
- 封建時代正確扣除 500 食物並完成 35 秒研究。
- 市集買賣、鍛造與手推車、對應單位數值、黃金不足時拒絕購買且資源不變。

若時間或資源有限，測試可能印出 `[RTS_PROGRESSION SKIP]`，僅完成前置／織布機／封建／市集範圍。此時 COMPLETE 會標明「核心進階範圍」，不能視為鍛造、手推車或其餘科技也通過。未取得新版 COMPLETE 前，以上均保持未驗證。

## 尚待驗收的必要項目

| 項目 | 需確認的引擎行為 |
| --- | --- |
| 所有建築與模板 | 18 種建築在所需時代可建造，缺少模板有替代外觀；使用者原模型與未知實例保留，模型尺寸、占地、碰撞、出口正確。 |
| 四時代與全部科技 | 城堡／帝王資源成本與不同種類前置、城堡替代條件、研究互斥、前置科技、現有及新生單位加成、重複與失敗扣款。 |
| 經濟與施工 | 四資源交回正確營地、耗盡後再找資源、農田科技、多人協助施工、修復成本、建築被摧毀後的佇列／研究處理。 |
| 軍隊與同步 | 十種單位、索敵與反擊、護甲／克制／範圍傷害、城堡與塔、不同體型尋路、出口被堵與多人傷害同步。 |
| 勝利規則 | 戰鬥消滅全部單位與建築的征服判定、真正摧毀起始市鎮中心的主城決戰、奇觀完整 180 秒守成與被摧毀／多奇觀計時。已有投降與玩家離開結束雙人局的證據，不能代替全部勝利條件。 |
| AI 長局 | 三種難度實際採集／交貨、生產與升級到四時代、資源枯竭後恢復、進攻與防禦、奇觀模式、玩家離開後持續運行。 |
| 效能 | 大型地圖四方長局、每方 200 人口、資源節點大量耗盡與反覆重開的幀率、尋路併發、記憶體與遠端頻率。 |
| 介面與輸入 | 不同螢幕尺寸與 GuiInset、安全區域、底部緊鄰地面點擊、UI 不穿透、全部快捷鍵／編隊、聊天輸入、切出視窗、減少動態、邊緣捲動。 |
| 正式客戶端 | Roblox 正式客戶端的複製與操作、網路延遲、晚加入觀戰、離開／房主轉移與重開。 |

原始程式與 place 備份位置見 [README.md](../README.md)。不要自動發布體驗或覆蓋原 place；新建置輸出到 `build`。2026-09-29 舊版天空／串流修正屬於歷史紀錄，不能為本輪未完成的進階驗收背書。
