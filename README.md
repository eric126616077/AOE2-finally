# Roblox RTS 原型

以經典 RTS 為方向：村民採集、基地建造、訓練軍隊與多人對戰。這是可進入 Studio 測試的第一輪核心實作，尚非完整《帝國時代》。

## 畫面與載入修正（2026-09-29）

在使用者原有 Studio place 重現「只有天空」後，確認客戶端 `StreamingEnabled=true`、`AOE2_Ground=nil`，相機腳本本身有執行。RTS 關閉角色自動生成後，預設以角色為中心的串流不適用；目前明確關閉此小地圖的串流，並把地面納入 Rojo 宣告，編輯模式與 Play 均可見。

HUD 已重新設計：獨立資源卡、3D 建築卡、單位肖像與生命條、戰術小地圖及視野指示。縮放依視窗大小調整；底部卡片之間保留地圖可見區。新 fallback 幾何含屋頂、樑柱、旗幟、農田作物及村民／步兵外觀；優先沿用原有 Studio 模型。地面增加城堡庭院、道路、柔和草地細節與周邊水面。

## 連接 Roblox Studio

在專案目錄執行：

```powershell
.\scripts\serve.ps1
```

或直接執行：

```powershell
.\rojo.exe serve default.project.json --address 127.0.0.1 --port 34872
```

在 Studio 的 Rojo 插件按 Connect，使用 `localhost:34872`。保留這個程序執行才能持續同步；Ctrl+C 可停止。若埠已被占用，先檢查是否已有本專案的服務，勿重複啟動。`rojo build` 只產生檔案，不會啟動同步。

現有 Studio place 可能含未匯出的模型。同步前先另存 place 備份，並檢查 Rojo 差異。`ReplicatedStorage` 與 `Workspace` 已設定保留未知實例；不要選擇刪掉自己的美術資產。舊的額外 Script 若仍存在，可能與新系統重複執行，需依 Output 查明後處理。

## 本輪功能

- 512 × 512 studs 地圖、8 studs 格線、四個出生點與對稱的起始資源。
- 每位玩家一座主堡、三位村民；伺服器控制資源、人口與單位所有權。
- 樹木、石礦、金礦、漿果叢與可採集農田；採集耗盡會停止。
- 四種付費建築，伺服器驗證占地、邊界、附近村民、資源與請求頻率。
- 主堡／市鎮中心訓練村民，兵營訓練步兵；每棟同時訓練一個單位，預先保留人口。
- 尋路移動、指定敵人攻擊、主堡被摧毀後戰敗；至少兩名參賽者才啟用勝負判定。
- 資源與人口 HUD、選取外框、拖曳框選、多選、建築預覽、小地圖。
- 最多四位參賽者，其餘觀戰；對局結束後需重新啟動測試開始新局。

## 操作

| 操作 | 功能 |
| --- | --- |
| WASD／方向鍵 | 移動相機 |
| Shift + 移動鍵 | 加速相機 |
| 滾輪 | 縮放 |
| Home／點小地圖 | 回主堡／移動視角 |
| 左鍵 | 選取單位、建築或資源 |
| 左鍵拖曳 | 框選自己的單位 |
| Shift + 左鍵 | 加選／取消單一單位 |
| V | 選取全部自己的村民 |
| 右鍵地面／資源／敵人 | 移動／採集／攻擊 |
| 1／2／3／4 | 市鎮中心／房屋／兵營／農田 |
| 建築預覽時左鍵 | 提出建造請求；可連續放置 |
| 右鍵／Esc | 取消建築預覽 |
| T | 在所選建築訓練單位 |
| X | 停止所選單位 |

第一個測試循環：村民採漿果 → 建房增加人口 → 主堡訓練村民 → 建兵營 → 訓練步兵。

## 模型與原始碼

優先使用 `ReplicatedStorage/Buildings/{Castle,TownCenter,House,Barracks,Farm}` 與 `ReplicatedStorage/Resource/{Tree,Gold,Stone,Berries}` 的 Model。缺少模板時由程式建立簡易外觀；原有模板不會被修改。複製的模型會統一縮放到占地範圍，複製品內的舊 Script 不執行，避免再次調整位置與大小。

`GameConfig.lua` 集中管理價格、占地、生命、訓練時間與人口。`GameServer.server.lua` 協調世界與指令，`ModelFactory` 建立實例，`Economy` 負責扣款；`RTSClient`、`BuildingController`、`GUIManager` 與 `PlayerInput` 負責操作及顯示。

舊 `ResourceSystem`、`GameManager` 與無副檔名的 `*Setup` 保留為遷移參考，未用於新啟動流程。舊 spawner／loader 保留空入口，避免既有 Rojo 映射產生第二套生成流程。

## 驗證與目前限制

```powershell
.\scripts\verify.ps1
```

驗證需要官方 [Luau CLI](https://github.com/luau-lang/luau/releases) 的 Windows 執行檔放在 `.tools/luau`。本次使用 0.740。腳本會編譯所有 Luau 檔案，執行格線／有限數值／原子扣款測試，最後由 Rojo 輸出 `build/AOE2.rbxlx`。

純邏輯測試使用實際模組內容與最小建構器替身，不模擬 Roblox 引擎。Studio 驗證清單見 [tests/STUDIO.md](tests/STUDIO.md)。語法與建置通過不代表尋路、多人同步或美術實測通過。

本專案另外提供真正的 Studio 客戶端整合測試。新開 Play 後，在客戶端 Command Bar 執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.StudioTests).Run()
end)
```

會透過實際 RemoteEvent 測試建造、扣款、拒絕非法請求、訓練、尋路、採集與停止。請在空白新局執行一次；測試會消耗資源、產生房屋與村民。這不是正式服遠端管理介面，只有 Studio 客戶端可執行。詳細實測結果見驗收紀錄。

目前為桌面滑鼠鍵盤原型。採集直接入帳、建築即時完成，單位使用簡易外觀。尚未實作回營交貨、施工時間、戰爭迷霧、文明與科技樹、AI、遠程兵種、單位動畫、觸控操作、配對與存檔。攻擊需玩家下令，尚無自動索敵或反擊；不要視為最終戰鬥平衡。

## 原始專案檢查紀錄

本輪修正前發現：建築 LocalScript 位於 ReplicatedStorage 並依賴非標準 `getgenv()`、射線排除所有 Workspace 實例、建築只在本地建立、UI 等待角色而相機刪除角色、地圖／資源／城堡尺寸各自不同、資源模板缺失會造成 nil 存取、四人之後出生點重疊、UI 資源未連接真正經濟。

舊碼備份：`C:\Users\user\AppData\Local\Temp\AOE2-before-20260929-225511`（含 `src` 與 `default.project.json`，不含 Studio 內未匯出的模型）。專案起初沒有 Git repository。

參考官方文件：[腳本執行位置](https://create.roblox.com/docs/scripting/locations)、[伺服器驗證](https://create.roblox.com/docs/scripting/security/client-server-boundary)、[Rojo 同步規則](https://rojo.space/docs/v7/sync-details/)。

