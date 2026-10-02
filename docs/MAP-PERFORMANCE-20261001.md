# 地圖與靜態場景效能：2026-10-01

本輪由地圖聊天負責 WorldGenerator、MapGenerator、ModelFactory 的 Resource 分支與地圖測試；操作聊天負責移動、施工、音效。首輪由介面聊天唯一操作 Studio；r2 交接後改由地圖主聊天唯一控制 Studio，該段實機驗證期間兩個本地審查 agent 只讀文件與 log，未對 Studio 輸入。地圖原檔備份在 `C:/Users/user/AppData/Local/Temp/AOE2-map-before-20261001-041437`；Resource Factory 與測試備份在 `C:/Users/user/AppData/Local/Temp/AOE2-resource-factory-before-89d79512aa9445639d57d17fc5c622cd`。

## 實際變更

- 四條基地大道改為各一個 20 studs 寬的直線零件，保留庭院、中央戰場、草地與海岸。自有裝飾不投影，不參與碰撞、觸碰或查詢；移除裝飾的透明表面疊繪。草地減量並採接近地面的不透明色。
- `GameConfig.Map` 共用道路寬度、資源占地和三尺寸節點預算。資源必須整組四方新增，上限不再被最後一個林群超過；占地外緣與大道至少相隔 1 stud。保留基地 128 studs、中央 64 studs 的資源保留區。這些保留區針對生成資源，未知原有障礙仍須實機測試。
- Resource 外觀仍使用使用者模型的副本或原創替代幾何，原始模型未改。外觀零件關閉 CanQuery，以 Footprint 作唯一權威查詢／碰撞體；至多保留一個原本會投影的可見零件，選最終世界 XZ 投影包圍盒面積最大的候選。建築與 Factory.unit 不受此分支影響。
- 生成失敗會立即回報錯誤，取消成功資源計數；已生成的自有副本仍帶清理標記。未加入生成 yield，避免擴大 Starting 階段的玩家退出競態。
- `StreamingEnabled=false`、未知 Studio 實例保留規則維持。未發布體驗或覆蓋既有 place；建置輸出到 build。

## 可重現的靜態成本

| 尺寸 | 自有裝飾零件：前→後 | 預設種子資源節點：前→後 | 替代資源 BasePart：前→後 |
| --- | ---: | ---: | ---: |
| Small | 199 → 38 | 428 → 420 | 2,396 → 2,324 |
| Medium | 274 → 46 | 740 → 680 | 4,004 → 3,704 |
| Large | 425 → 62 | 1,104 → 1,100 | 5,984 → 5,948 |

裝飾數由生成規則直接計算。資源數為實際 WorldGenerator body 配合 verify.ps1 的 Park–Miller Random shim、種子 2718 所產生的結果；shim 不等同 Roblox Random。替代資源部件數包含 Footprint，依現有 Tree/Stone 各 5、Gold/Berries 各 9 部件計算；使用者模板的部件數可能不同。這些數字不代表 FPS、draw calls 或記憶體改善比例。

## 本輪已驗證

`scripts/verify.ps1 -PlaceOutput build/AOE2-map-performance-20261001.rbxlx` 完成且 exit 0：全部 src Luau 語法編譯、既有 CLI 套件、ModelFactory 實際 body engine mocks 161 checks、地圖 3,816,585 checks，以及 Rojo 映射建置。另已依專案指示執行 `rojo.exe build default.project.json -o build/AOE2.rbxlx`。修改檔案 `git diff --check` 無錯。

地圖測試覆蓋三尺寸 × 四種種子、上限、非四倍餘量、所有節點兩兩間距、道路占地外緣、基地／中央保留區、種類與位置鏡射、種子重現與變種、建立失敗、未知原模型保留。它們不取代引擎尋路或 Play 驗證。

## 集中 Studio 驗證

在新 Play 以正常大廳流程開局後，尚未耗盡資源時，CLIENT Command Bar 明確呼叫：

```lua
require(game.ReplicatedStorage.Shared.MapTests).Run()
```

這是唯讀驗證，不產生單位、不傳 remote、不變更資源或相機。它檢查真正客戶端地面、相機、資源節點與必要外觀／占地的複製、鏡射、道路間隙、query／shadow flags 和自有裝飾，僅於完成時輸出 `[MAP_TEST COMPLETE]` JSON。沒有伺服器權威外觀部件總數可核對，因此不證明每個外觀子零件已完成複製。須保存來源 manifest 與原始 log；沒有該完成標記不能宣稱通過。

另可明確啟動現有唯讀幀率觀察器，再正常操作／平移相機：

```lua
require(game.ReplicatedStorage.Shared.PerformanceObserver).Start({
 seconds=60, sampleInterval=2, context="桌面 Studio，新地圖整合觀測"
})
```

比較前景 `framesByFocus.Focused` 的有效 FPS、p95 上界與最差幀，以及可讀的 draw calls、triangles、instance count、記憶體和流量。未知焦點、背景與不可用 Stats 必須保留，不能補成有效資料。這個觀察器不量伺服器 CPU／尋路／每腳本耗時，也不會宣告效能 PASS。

2026-10-01 04:32:52（Asia/Taipei），由 UI 聊天唯一操作的無模型 Small 新局取得 `[MAP_TEST COMPLETE]`：420 個資源節點、420 個查詢占地、420 個資源投影零件、38 個自有裝飾零件、6,755 checks。當刻收到 2,468 個資源 BasePart；真 Roblox Random 的種類分布與 CLI shim 不同，這不與上表混用。原始摘錄存於 `tests/map-performance-small-studio-20261001.txt`，來源為 `tests/ui-source-manifest-20261001.json` 與 `build/AOE2-ui-20261001.rbxlx`（SHA256 `77D7B2495D079207BBA81366145134A51A0647060043582824864EFC83EF46CA`）。

Small 的完成證據使用初版 MapTests。其後僅修正測試工具的複製等待：同一期限等待地面、每個資源占地／至少一個可見外觀和完整裝飾，確認驗證期間同一場比賽，另直接核對四條道路寬度／朝向。遊戲地圖來源沒有因此變更。部件統計明記是當刻採樣，沒有伺服器權威外觀部件總數，不能據此證明每一個裝飾子零件皆已收到。新版 helper 已編譯，Play 證據須另列。

2026-10-01 04:35:53 的短局 30.13 秒取樣記錄 1,804 幀、4 個實際單位：有效 FPS 59.90、p95 上界 17.5 ms、最差幀 26.87 ms；沒有低於 30 FPS 的幀。焦點整段 Unknown，沒有取得 WindowFocused 事件，不能稱為已驗證前景數據。該局 Small／1 方／0 AI，沒有實際四方各 200 人口。這是目前有限負載的一次觀測，沒有修改前的同條件 baseline，不能據此宣稱改善比例。有效樣本摘要存於 `tests/map-performance-small-30s-summary-20261001.json`。

45 秒觀察有 FINISHED 標記，但其完整 JSON 被 Studio log 截斷，未把不可解析的最後結果當成完整摘要；已向操作 agent 要求由原 handle 輸出有限欄位，避免重跑或改動遊戲。

## r2 三尺寸實機與返回大廳

凍結的 r2 來源在同一份 `Studio_EB6AA_last.log` 中取得三種尺寸的真正 CLIENT 完成輸出。原始紀錄保留 UTC；下表時間換算為 2026-10-01 Asia/Taipei。摘錄截止 05:46:54.247 地圖序列完成，只保留 `CreatorOutput` 的實際標記，排除 `>` Command Bar 指令回顯，存於 [r2 Studio 原始摘錄](../tests/map-performance-r2-studio-20261001.txt)。[r2 來源 manifest](../tests/performance-load-source-manifest-20261001-r2.json) 的 92 個檔案 SHA256 已再次核對，runtime、default／optional project、helper 與 r2 建置全部相符。

上述 92／92 核對是 r2 驗證結束時的來源狀態，r2 snapshot、manifest 與 log 保留不變。其後 GameServer 與 BuildingController 修正未知同名 `RTSScenery` 障礙的查詢問題，不再依資料夾名稱排除 scenery；自有裝飾仍透過 `CanQuery=false`／`CanCollide=false` 排除。再後續 GameServer 與 GUIManager 修改返回大廳的生成資源／小地圖清理。這些改動不包含在 r2 九個負載窗口或原三尺寸 MapTests 證據中；下方另列各自新 build／新 Play 的完成證據與來源範圍，沒有把歷史 FPS 或檢查數沿用為最新版整體驗收。

| 尺寸 | 完成時間 | 地圖寬度（studs） | checks | 資源節點 | 查詢占地 | 投影零件 | 自有裝飾零件 | 採樣資源 BasePart |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Small | 05:19:14.841 | 768 | 6,775 | 420 | 420 | 420 | 38 | 2,468 |
| Medium | 05:46:51.715 | 1,024 | 10,803 | 680 | 680 | 680 | 46 | 3,880 |
| Large | 05:46:53.561 | 1,536 | 17,359 | 1,100 | 1,100 | 1,100 | 62 | 6,204 |

三尺寸共 34,937 checks，均使用真正 Roblox Random 與客戶端 API。完成標記涵蓋目前測試的節點上限、四方鏡射、道路占地外緣及四條 20 studs 寬大道的幾何、query／shadow 與裝飾規則；它不證明引擎尋路或採集。三筆結果均明記 `completeVisualReplicationProven=false`，資源 BasePart 只是本次採樣收到的部件數，不能用作完整外觀複製或效能改善的證據。這些實機部件數與上方 shim 種類分布的靜態成本分別保留。

20 單位負載結束後，05:45:55.904 的 `[LOAD_R2_CLEANUP_JSON]` 記錄實際單位 20、建築 4、人口／上限各 20、訓練佇列 0、食物 400、木材 1,125。Observer 與負載 helper 均已停止，此次清理抽查的 `maximumRootDisplacement=0`；測量結束保留正常生產的單位與建築，之後再經正常對局流程返回大廳。

| 返回大廳標籤 | 時間 | generation | 單位／建築 | resourcesZero | 角色／相機 |
| --- | --- | ---: | --- | --- | --- |
| 20 after load | 05:46:50.617 | 2 | 0／0 | true | avatar=true／Custom |
| Medium | 05:46:52.405 | 4 | 0／0 | true | avatar=true／Custom |
| Large | 05:46:54.247 | 6 | 0／0 | true | avatar=true／Custom |

三筆 `[LOAD_R2_RESET]` 的 `phase` 均為 `Lobby`。Medium、Large 各有 `[LOAD_R2_MAP_DONE]`，最後 05:46:54.247 的 `[LOAD_R2_MAP_SEQUENCE] true` 證明此序列正常完成並回到大廳。以上為紀錄所涵蓋的清理狀態，不宣稱刪除或核對未知 Workspace 實例，也不構成 FPS、伺服器 CPU 或手機效能 PASS。

另一次 fresh Play 的施工測試在 05:49:40.288 完成 36 項檢查，05:51:14.604 census 確認初始 TownCenter 與新建 House／Barracks／Farm 均已完工、訓練佇列 0；05:51:15.468 正常返回大廳（generation 2、單位／建築 0、resourcesZero=true、avatar=true／Custom）。詳見 [負載與施工實機紀錄](PERFORMANCE-LOAD-20261001.md)，這些後續紀錄不併入前述三尺寸摘錄。

## 後續障礙與五輪重開：分開來源

2026-10-01 06:13:26.901（Asia/Taipei），障礙修正版的新 Play 取得 `[SCENERY_COLLISION COMPLETE]`：14 checks、152 次 Root 取樣、78 次權威移動更新、最大側繞 23.42 studs、繞行 9.42 秒。已核對 [原始逐行摘錄](../tests/optimization-query-studio-results-20261001.txt) 與 `Studio_5CF22_last.log` 的真正 CreatorOutput，排除指令回顯。該次未知同名資料夾牆面由 CLIENT 公開 BuildingController API 拒絕；正常 Build 請求沒有生成工地且 food／wood／gold／stone 均不扣；正常 Order 抵達牆後並保留未知牆面。預覽模組在 Command Bar 的獨立 VM 執行，未證明正式 LocalScript 預覽 cache 共用。此證據屬於 [障礙修正來源清單](../tests/optimization-query-final-source-manifest-20261001.json)，正常建置 `build/AOE2.rbxlx` SHA256 為 `3C6ECEDD9050DD6F68B07EBCB648BBF28F629CB34B7FC5A132E0F309B7524E2F`；隔離建置 `build/AOE2-query-validation-20261001.rbxlx` SHA256 為 `9D8F26A9082706E8CB7FF9A647EEB8152CD7AD99BDC7A1927EA566550D981B1C`。

2026-10-01 06:42:52.417，加入大廳清理後的另一個新 Play 取得 `[LOBBY_CLEANUP COMPLETE]`：126 checks、5 個完整循環。已將 [有限 JSON](../tests/optimization-lobby-r2-studio-results-20261001.json) 的 report／completeLogLine／cycles 與 [原始逐行摘錄](../tests/optimization-lobby-r2-studio-results-20261001.txt) 及 `Studio_8AE4B_last.log` 的真正完成標記逐一核對一致；126 條 PASS 與 5 條 CYCLE 均存在。

| 循環 | 地圖 | generation | 開局生成資源節點 | 已收到資源部件 | 實際 PlayerGui dots | 返回大廳節點／部件／dots |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Small | 1 | 420 | 2,468 | 426 | 0／0／0 |
| 2 | Small | 3 | 420 | 2,468 | 426 | 0／0／0 |
| 3 | Large | 5 | 1,100 | 6,204 | 1,106 | 0／0／0 |
| 4 | Large | 7 | 1,100 | 6,204 | 1,106 | 0／0／0 |
| 5 | Small | 9 | 420 | 2,468 | 426 | 0／0／0 |

每輪有獨立 MapTests 完成標記（Small 6,775／Large 17,359），均明記 `completeVisualReplicationProven=false`；126 是 LobbyCleanup 的檢查數，沒有加入原 r2 三尺寸的 34,937 checks。未知直接資源、未知資料夾內的巢狀模型、同名 `RTSScenery` 與原有模板保留身分／Parent／管理標記；未逐一核對材質／顏色／CFrame。第四輪 Large 同尺寸重新生成後，有正常建房完工與扣款、重新指派資源且實際採集的獨立 PASS。正常返回大廳會清除己方單位／建築、四資源／人口及生成資源／dots，恢復角色與 Custom 相機；這不等同多人離線清理驗收。

該次結果檔記錄 [大廳清理 r2 來源清單](../tests/optimization-lobby-r2-source-manifest-20261001.json) 94／94 相符；正常 `build/AOE2.rbxlx` SHA256 為 `EECCAC08521CB465450E20B08532A6CB082C9BACBE9E60236F194946768D8AFE`，隔離 `build/AOE2-lobby-cleanup-studio-20261001-r2.rbxlx` SHA256 為 `DC760287ACABD15CF1EB92B88C32B69DDB82897D46825913054A6EF086A252B2`。SceneryCollision 14 屬於前一份障礙建置，沒有在此 EECC／DC76 版本重驗拒建不扣款或繞障；LobbyCleanup 126 僅補上保留、重開、建造／採集與清理範圍，也沒有重測原 r2 九個 FPS 窗口。完整版本沿革見 [最佳化紀錄](OPTIMIZATION-2026-10-01.md)。

## 後續有限雙人與最後玩家離開

2026-10-01 07:33:04（Asia/Taipei），另一個隔離 Server & Clients 工作階段完成 server 36／host 11／peer 14 項檢查。已讀取 [完整結果 JSON](../tests/optimization-multiplayer-lifecycle-r2-studio-results-20261001.json) 的三端 complete、檢查數與清理狀態：兩次真正 PlayerRemoving 均被觀察；第一位離開後 Ended 保留 420 個生成資源節點／2,468 個部件，最後一位離開後為無玩家的 Lobby、generation=2、生成資源節點／部件、單位與建築均為 0，420 個原生成資源引用已移除。結果保存 26 份報告／72 筆分段與摘要，詳細正常入隊、成本／所有權及未知模型 metadata 的來源範圍見 [最佳化紀錄](OPTIMIZATION-2026-10-01.md)；這些完成斷言不擴稱任意匯入模型已驗收。

該結果記錄 94 項正常來源／96 項含驗證 helper 的來源，正常建置 SHA256 仍為 `EECCAC08521CB465450E20B08532A6CB082C9BACBE9E60236F194946768D8AFE`，獨立 `build/AOE2-multiplayer-lifecycle-20261001-r2.rbxlx` 為 `B135EA4D01AB063C535ACA00E3BFE396D013DB0536E1F1F6E71C9FC2D3ECB80A`；本次讀取時兩個實際檔案 hash 與結果相符。原始來源清單為 [雙人 R2 manifest](../tests/optimization-multiplayer-lifecycle-r2-source-manifest-20261001.json)。此局只有兩位玩家、Small 與短時間建造／訓練，`performanceAccepted=false`；沒有雙人 FPS／CPU／記憶體測量，也沒有重測原 r2 九個 FPS 窗口或原三尺寸 MapTests。

上述部件數均為實例或客戶端收到的 census，不證明完整外觀複製、伺服器記憶體下降或 FPS 改善。單人重開局另有外部大廳角色動畫資產 `96806611330323` 載入失敗，未列作無錯誤或實際聽感通過。新建 TownCenter 與其餘建築類型、fixture 以外的障礙／邊界／資源不足成本、其餘採集情境與全部大道可行走、未知匯入模型完整外觀、此雙人 fixture 以外的同步／退出情境、四方各 200 人口長局及真手機效能仍須各自實測。
