# 移動、施工與操作優化：2026-10-01

本輪為原創 Roblox RTS 測試版，朝 AOE2 的經濟與操作習慣改進。這份紀錄不將尚未測量的效能、真機或多人驗收寫成通過。

修改前完整來源備份：`C:/Users/user/AppData/Local/Temp/AOE2-before-smooth-20261001-040938`。原始使用者模型與未知實例保留，輸出使用 `build`；不自動發布體驗或覆寫原 place。

## 本輪分工

- 本聊天：單位連續移動、伺服器尋路節點停頓修正、Delete 安全驗證、施工外觀、原創材質細節與音效混音。
- UI 聊天：村民選取後才顯示建築、Delete 確認視窗、HUD 重設、集合點與佇列取消；單獨操作 Studio。
- 地圖聊天：資源與道路的靜態負擔、模型 query 與影子減量。其具體數量與驗收由該聊天記錄。

## 已實作行為

### 大廳與戰場

保留兩個獨立空間：城堡大廳位於 Z=2048，戰場以原點為中心，在同一個 place 中切換。開局先完成戰場生成，再收起大廳角色並切換俯視鏡頭；返回大廳重新載入角色，控制等待角色元件就緒後恢復。`StreamingEnabled=false` 和未知實例保留設定維持。

唯讀整合檢查確認玩家離開會清除其單位、建築、工作、訓練、研究與角色連線；過期尋路結果由 generation 拒絕。本輪後續修正返回大廳時保留上一局生成資源與小地圖標記的問題，五輪正常重開已另取得新 Play 證據。少量生成景物保留供同尺寸重開使用。文末另記錄最新來源的真雙人退出驗證；這些清理結果不代表已解決滿載效能問題。

### 單位移動

伺服器原本每經過一個已到達的尋路節點便返回，因而多停一個約 0.1 秒的更新週期。現在同一週期跳過已到達節點並繼續移動。每段移動仍做實際 Blockcast；安全前綴走完後仍須取得下一段有效路徑，不能穿越障礙。

客戶端保留最多 6 個 Root 位置快照，以 0.12 秒緩衝連續補間原視覺零件，不外推至伺服器尚未確認的位置。權威 Root、成本、命令、碰撞與戰鬥規則仍由伺服器決定。原可點擊外觀一起移動，`ClientUnitView` 的弱表可供框選與介面使用同一呈現位置；不以每幀 Attribute 傳送外觀位置。

外觀以 BulkMoveTo 批次更新；鏡頭範圍檢查 8 Hz、肢體動作 30 Hz，最多 96 個可見近距單位使用詳細姿勢。所有可見單位保留移動補間。減少動態設定關閉肢體與裝飾動作，仍保留可讀的連續移動。待命及畫面外單位不持續寫入零件位置。伺服器的障礙排除清單只有地面身分改變才重建；不按場景資料夾名稱排除使用者障礙。

這些改變減少固定停頓與不必要工作，不能保證所有硬體、封包延遲或四方滿人口下皆不卡。

### 施工與外觀

`BuildingVisuals` 依真實伺服器進度呈現地基、鷹架、牆面與屋頂；顯示施工百分比、等待村民及完工提示。只有正在施工的建築參與鏡頭檢查，每秒 4 次；施工覆蓋外觀上限 24、同時完工提示上限 6。施工停止不會自行增加進度。

替代建築新增石材、木板、布料等內建表面材質，以及屋脊、窗台、木窗與門鐵箍等少量原創幾何細節。這不是從 AOE2 擷取的貼圖。匯入模型僅在測試局的複製實例以 LocalTransparencyModifier 分階段顯示，完工還原原有外觀，不刪除或覆蓋模型模板。

### Delete

介面確認後才發送 `Command("Delete", models, generation)`。伺服器驗證目前 Playing／存活狀態、對局 generation、1–200 個連續且不重複的選取，以及每個模型的己方所有權、管理標記與正值有限 HP。整批驗證成功才執行既有生命週期清理；任一失效項目使整批拒絕。

刪除單位、建築及未完工工地均不退還資源。自拆不當成戰鬥傷害或擊殺。主城決戰中拆掉起始主城會觸發淘汰。佇列個別取消與退款屬另一個明確命令，不能與整棟拆除混淆。

### 音效

保留 Roblox 內建、已有載入流程的音檔，調整選取類型的音高與各種採集／施工／戰鬥聲音混音。介面和世界音效分組，重要提示時降低工作聲音；世界音量依 RTS 相機距離衰減。保留總音軌、世界音軌與頻率上限，靜音會停止現有聲音。載入失敗的檔案不反覆配置聲音實例。

整合審查另修正滿額時的搶占順序：先完成所有冷卻／靜音／來源檢查，只有合法優先提示因播放池容量不足，才釋放最舊的一個世界聲並以同一時間重試。被限頻的重複提示不再誤掐工作聲。三檔小修前備份為 `C:/Users/user/AppData/Local/Temp/AOE2-audio-preflight-20261001-045931`。

本輪沒有上傳自製音效庫，也不把內建音檔混音描述為 AOE2 原版語音。

## 驗證

| 檢查 | 狀態與範圍 |
| --- | --- |
| Delete 原子驗證 | 21 項純規則檢查通過；含敵方／失效／重複／稀疏／超量／舊對局／非有限 generation。 |
| 實際伺服器 moveToward 原始碼回歸 | 9 項通過；覆蓋節點不停頓、重複節點、終點不越過、安全前綴重新規劃與每段碰撞拒絕。碰撞引擎為 mock，不替代 Studio 路徑測試。 |
| 客戶端補間規則 | 560 項純規則檢查通過；不是 FPS 或網路效能驗收。 |
| 施工呈現／音效規則 | 151 項施工階段／特效上限與最終 96 項音效限頻／滿池搶占／優先提示／靜音等純規則檢查通過。 |
| 全專案編譯／純測試／Rojo | 初次與後續整合的 `scripts/verify.ps1` 均 exit 0，指定 `build/AOE2.rbxlx` 建置成功。最新日誌 `tests/optimization-lobby-final-cli-results-20261001.txt` 另包含實際來源障礙過濾 29 項與資源清理 43 項；來源清單見文件末段。純檢查不替代引擎。 |
| 新 Play 單位呈現 | **18 項 COMPLETE**，04:35:30 Asia/Taipei：X／Z 各 40 studs 正常 Order，52 次 Root 變動之間取得 294 個外觀中間影格；Body／GetFrame 位置與轉向一致，停止對齊。最大 Root 顯示偏差 1.531 studs、最多 6 個快照，6.81 秒完成。讀實際 LocalScript 探針，不使用 Command Bar 的另一份 require 快取假定狀態共用。 |
| 新 Play 施工呈現 | **42 項 COMPLETE**，04:35:42 Asia/Taipei：正常指令扣款造房、停工／再派工、鷹架／外牆／屋頂揭露、百分比／等待村民、減少動態、真正完工、外觀還原／占地不變與提示清理。 |
| 新 Play 地圖／HUD | **Map 6755、HUD 23 COMPLETE**，04:32:52–53 Asia/Taipei：Small 768／420 資源／420 query 部件／38 場景部件；村民建築情境、主城訓練／科技、Delete modal、GUIInset／相鄰地面與實際 PlayerGui。HUD 此模組不真正刪除物件。 |
| 新 Play 生產／集合點 | **41 項 COMPLETE**，04:36:52 Asia/Taipei：逐格訓練取消／退款與人口預留釋放、舊版本／重複／非法索引拒絕、村民按樹木集合點出生後實際採集、軍隊地面集合點與無效位置拒絕。詳細 UI／生產改動由 UI 聊天記錄。 |
| 新 Play Delete 伺服器 | **22 項 COMPLETE**，04:38:02 Asia/Taipei：舊對局／重複／中立資源混選整批拒絕且不刪己方村民、不改四資源；正常房屋工地扣款、取消工地不退款、正常村民刪除及人口同步，其餘局持續運作。使用 `tests/delete-server-studio-snippet.lua` 正常 Command；未驗真正敵方或跨客戶端。 |
| XR 橫向模擬手機初次驗收 | 04:48:17–18 Asia/Taipei：**Map 6775、Touch 41、Feedback 66 COMPLETE**；真正音效資產載入、多音／上限、靜音／還原及安全區域得到檢查。**同局 HUDTests 明確 FAIL「緊鄰底部面板的地面可點擊」**，原因為可見開局通知尚蓋著該座標；後續修正版另驗原座標，保留此失敗。不將模擬器或合成滑鼠當真人觸控／聽感驗收。 |
| 手機修正版實際操作 | **HUD 21、Touch 42 COMPLETE**，04:57:40 Asia/Taipei；開局通知關閉後驗同一個操作列上方座標，沒有把測試點移走。04:58:21 **UI_CLICK 4 COMPLETE**：以 sky 滑鼠點手機模擬介面的村民訓練、佇列取消與織布機，讀實際名稱／倒數／百分比、44 px 頭像／進度條，以及取消退還 50 食物且不生成單位。新來源另含多選數量與總生命值；仍未驗真人手指。 |
| 最終音效／介面桌面回歸 | 05:19:14–19 Asia/Taipei，獨立負載測試副本 r2 的新 Play：**Feedback 65、Map 6775、HUD 24 COMPLETE**。這次含最後音效容量搶占小修及最後手機／桌面共用 GUI。音檔載入、多音、靜音正常，聽感與正式裝置仍未驗；地圖外觀部件 census 仍不作全部子零件完整複製證明。 |
| 效能短段觀測 | 45 秒 Observer 已 FINISHED，整份 JSON 在 Studio log 截斷，不能假稱完整報告已保存。30 秒 SAMPLE：4 個實際單位、有效 FPS 59.90、p95 影格時間上界 17.5 ms、最差 26.87 ms；focus=Unknown、四方 200 人未配置／未觀察、沒有重開。這是 Studio 短段觀察，不是效能驗收或低階裝置保證。 |
| 漸增負載首段失敗 | r2 新局第一個 server probe 為 4 單位待命、120 秒，因原生介面操作延遲未與 client phase 重疊；不作配對。05:25:08 client 4 單位首段因「相機或視窗改變」輸出 **INCOMPLETE**，當刻 viewport=330×161；不採用其影格統計為固定視圖比較，測試局正常單位保留。固定視窗後同版重跑，沒有放寬相機斷言。 |
| 固定視窗漸增負載 | **4／10／20 實際單位 × 待命／移動／停止，九段各 30 秒 COMPLETE**。Small、單人、無 AI、1610×638、FOV 50、同相機；各段約 50 FPS，p95 上界 20.5–21 ms、最差 21.9–25.6 ms，沒有低於 30 FPS 的影格。焦點皆 Unknown，沒有舊版同條件基線；不稱作效能驗收或改善比例。完整有限結果見下表。 |
| 真機／四方每方 200 人／長局／最新雙人 | 未驗證。短路徑與純測試不能替代。 |

以上新 Play 為單人、Small、aiCount 0、Rich、Sandbox、無匯入模型的替代外觀。原始 Studio 日誌：`C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T202946Z_Studio_6397E_last.log`；本聊天的逐行摘錄為 `tests/optimization-studio-results-20261001.txt`。版本使用 `tests/ui-source-manifest-20261001.json`，`build/AOE2-ui-20261001.rbxlx` SHA256：`77D7B2495D079207BBA81366145134A51A0647060043582824864EFC83EF46CA`。

04:38 的來源比對：UI manifest 所列 87 個檔案中，86 個與當前來源一致；唯一不同是 `Shared/MapTests.lua` 測試模組（原 SHA256 `85C4D6D19D41616DE6B1BF58B2DE9FB874CB374A5379BA0F54B057AA4F5FDC8C`，現 `3C01C8E11968AF74E58BC19A326F25AE5A948DE9ED6E402D7E51B0ADF6710B96`）。遊戲執行程式未變，但 Map 6755 的結果不延伸至該測試後續修訂。

手機佇列修正後的另一個新 Play：`tests/ui-mobile-source-manifest-20261001.json`、Studio log `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T204614Z_Studio_BC7B6_last.log`，逐行摘錄 `tests/optimization-mobile-results-20261001.txt`。其新增手機行為不能沿用桌面 HUD 23 的舊結果。

手機最終介面版本：`tests/ui-final-source-manifest-20261001.json`，UI 聊天回報驗證建置 SHA256 `89688297EDE4A3A5E9C320A8DD04F64EE4BCD990F0BD0D34108FE390A2AFC7C5`；原始 log `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T205327Z_Studio_1FF38_last.log`，摘錄 `tests/UI-FINAL-STUDIO-20261001.txt`。04:56:23 首次測試只見 Playing、初始模型／角色切換未就緒，HUD 與 Touch 先失敗；04:57 等到真正就緒後同局重驗完成。兩次結果均保留。

先前「相鄰地面」失敗源自可見開局 Notice 尚在座標上；測試新增最多 6 秒等待通知關閉，再驗原座標。可見通知期間仍應阻擋世界操作，沒有刪除該阻擋來取得通過。音效之後另有優先提示限頻的小修，不能直接沿用前版 Feedback 66 結果。

## 音效／介面版本來源與建置（障礙修正前）

手機介面凍結及音效小修後，完整 `scripts/verify.ps1` 再次 exit 0，並再次明確執行 `rojo.exe build default.project.json -o build/AOE2.rbxlx` 成功。日誌為 `tests/optimization-final-cli-results-20261001.txt`；最終來源清單 `tests/optimization-final-source-manifest-20261001.json` 含 87 個 src Luau 檔、專案映射與 verify 腳本。`build/AOE2.rbxlx` SHA256：`EB6ECFAA620A56707553DE28AA4532040B73E612FB265C096557371D7788EBC2`。

與手機最終 UI 清單比對，僅 `AudioFeedback.lua`、`FeedbackRules.lua` 不同；GUI、伺服器與地圖來源相同。前版 Studio 各模組的完成證據沿用其已保存的來源界限，新音效與漸增負載會使用另一個明確啟動的驗證副本。測試副本不加入 default 的自動執行入口。

最後桌面回歸的獨立副本來源為 `tests/performance-load-source-manifest-20261001-r2.json`，新 log `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T211509Z_Studio_EB6AA_last.log`。同局在進入 Playing 後另等實際地面、初始單位、建築、無角色與 Scriptable 相機均就緒，再執行檢查；完成標記由本聊天直接讀取日誌確認。

## 固定視窗的有限負載結果

本聊天直接解析上述原始 log 的 compact JSON，保存為 `tests/optimization-load-results-20261001.json`，保留初次 INCOMPLETE、造屋／訓練扣款與每段完整欄位。新測試副本 r2 SHA256 為 `6896A5E1586DD2481BAA7E4C3B15E47F5BE1757C2B564280FA953343B346FD02`；執行當下 92 項來源均核對一致；其後障礙過濾修正另有新來源與驗證界限。全九段保持 1610×638、相機位置 (-168,160,-48)、FOV 50；每段 30 秒，取樣時所有該階段單位均在視野內。

| 實際單位 | 待命 FPS | 移動 FPS | 停止 FPS | 三段 p95 上界 | 三段最差影格 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 50.00 | 50.00 | 50.00 | 20.5 ms | 21.99 ms |
| 10 | 49.97 | 49.95 | 49.98 | 21.0 ms | 25.56 ms |
| 20 | 49.97 | 49.95 | 49.97 | 21.0 ms | 25.48 ms |

4 人移動段有位移的取樣比例為 98.28%，最少移動人數一度為 0；10／20 人移動段每次後續取樣都有位移，最少分別 9／19 人。這是每 0.5 秒一次的觀察，不能證明每個影格全體都持續移動。待命與停止段位移取樣為 0。九段都沒有超過 1/30 秒的影格。

10 人為正常新增 1 屋、6 村民；20 人另新增 2 屋、10 村民。累積正常支出 75 木材與 800 食物，餘額 1125 木材／400 食物，人口容量 20；沒有直接生成、增資源或改速度。這仍不是軍隊交戰、四方滿人口、低階裝置或正式伺服器測試。

Server probe 記錄 Heartbeat 節奏和可讀 Stats，不能當 GameServer CPU 或尋路耗時。4 人首個 120 秒窗口沒有與客戶端三段重疊；10／20 人的整段窗口也不能拆稱逐模式 CPU。Studio 總記憶體與 instance count 包含宿主場景影響，不能當作獨立正式客戶端的資源用量。焦點仍 Unknown；沒有修改前同條件對照，不能歸因 FPS 改善百分比。

這些完成訊息不代表模板分支、多客戶端、正式 Roblox 裝置或四方大軍通過。歷史日誌只代表其當時版本。

## 後續施工／地圖回歸（r2，障礙修正前）

05:46:51 Medium Map **10803 COMPLETE**：1024 地圖、680 資源、680 query／shadow 節點、46 場景部件、3880 資源零件。05:46:53 Large Map **17359 COMPLETE**：1536 地圖、1100 資源、1100 query／shadow 節點、62 場景部件、6204 資源零件。這是複製後 census，仍未證明全部子零件的完整視覺複製。

05:47 停止並重新 Play，再正常開 Small／Rich／無 AI 沙盒。05:49:40 **ConstructionTests 36 COMPLETE**：正常房屋／兵營／農田工地、村民到場施工、到場前後停止保留進度、重複施工村民只扣一次費用、軍隊拒絕施工、未完工兵營拒絕訓練且不扣款、房屋完工才增加人口、兵營完工才可訓練、農田完工才提供食物。05:51:14 census 確認主城、房屋、兵營、農田均 Complete、訓練佇列為 0。

上述對局均以正常投降／重開返回大廳；檢查己方 Units／Buildings 為 0、資源與人口歸零、角色重新出現與 Custom 相機。這是重開清理，沒有把它當成雙人離線清理測試。原始逐行摘錄 `tests/performance-load-r2-construction-studio-20261001.txt`，來源仍是 r2 的歷史 92 項清單。

## 障礙修正與來源（大廳清理前）

MapGenerator 遇未知同名 `RTSScenery` 時會保留它並另建 `RTSManagedScenery`。整合審查發現原本的伺服器／建築預覽按名稱排除 `RTSScenery`，使保留下來的使用者牆面失去移動與建造阻擋。現在只排除正式地面與各查詢所需的 Units／本地預覽。自己生成的裝飾本來就 CanQuery=false／CanCollide=false，不需要額外按資料夾名稱隱藏；沒有新增每幀 Workspace 掃描。備份：`C:/Users/user/AppData/Local/Temp/AOE2-before-obstacle-filters-20261001-055759`。

新增 **29 項實際來源過濾器回歸**，由 verify 抽取 GameServer 的初始化／更新與 BuildingController 的查詢過濾段；覆蓋未知同名牆面、生成裝飾、單位占地、預覽自我排除、地面替換與 100 次未變場景快取。原本來源在同一 fixture 下會失敗。最終整套 verify exit 0，再明確執行 `rojo.exe build default.project.json -o build/AOE2.rbxlx` 成功；日誌 `tests/optimization-query-final-cli-results-20261001.txt`。

06:13:26 Asia/Taipei，新 Play 最新來源 **SceneryCollision 14 COMPLETE**：SERVER 僅在這個隔離沙盒新增未知同名資料夾牆面，CLIENT 用實際 BuildingController 公開 API 拒絕牆面位置，正常 Build 遠端請求被伺服器拒絕、沒有生成工地、四種資源皆不扣。正常 Order 從牆前抵達牆後，152 段 Root 取樣／78 次移動更新無穿牆，繞到側邊 23.42 studs，繞牆階段 9.42 秒完成。未知牆面仍保留。預覽模組為 Command Bar 的獨立 require VM，沒有宣稱它與正式 LocalScript 的 cache 共用。

暫時測試牆面不映射進正常專案、不會自動 Run；於 06:14:53 停止 Play 清除，本機副本關閉時選「不要儲存」，沒有覆寫已建置的驗證檔或發布。單陣營不代表測試 helper 強制只有一位連線玩家；本次實際單人、無觀戰與 AI。

原始 log：`C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T220944Z_Studio_5CF22_last.log`。摘錄 `tests/optimization-query-studio-results-20261001.txt`；最後清單 `tests/optimization-query-final-source-manifest-20261001.json`，**94／94 檔**於停止 Play 後比對一致。CLI／Studio 測試適用以上來源界限，前版負載與施工成績不擴稱最後版全部重新驗過。

- 正常建置 `build/AOE2.rbxlx` SHA256：`3C6ECEDD9050DD6F68B07EBCB648BBF28F629CB34B7FC5A132E0F309B7524E2F`。
- 隔離驗證建置 `build/AOE2-query-validation-20261001.rbxlx` SHA256：`9D8F26A9082706E8CB7FF9A647EEB8152CD7AD99BDC7A1927EA566550D981B1C`。
- 前版 EB6E 正常建置另保存在 `build/AOE2-pre-obstacle-filter-20261001.rbxlx`；先前來源清單與日誌未覆寫。

截至障礙副本的多人驗收尚未完成；最新基本雙人生命週期另見文末。敵方 Delete、正式手機、實際聽感、未知匯入模型視覺、四方滿人口戰鬥與長時間對局仍未驗證。本輪成果是持續改善的 RTS 原型，沒有宣稱已 100% 模擬 AOE2 或任何裝置都不卡。

## 最新大廳清理與五輪重開

`clearMatch` 先讓舊工作失效並清除單位／建築，再銷毀 Resources **直接子項**中 `RTSManagedResource=true` 的實例，清空管理表並將 ResourceNodeCount 設為 0。保留未知模型、未標記資料夾及其巢狀子項、Resources 本身、模型模板、大廳與地面。Ended 結果畫面仍保留戰場；正常返回大廳才清理。沒有重設可能尚在等待的 pathTasks，舊尋路結果仍由對局與指令身分拒絕。

真正 GUIManager 在進入 Lobby／Starting 時銷毀既有小地圖 dots 並清表，不等到下一局才回收；沒有新增每幀場景掃描。伺服器清理前備份為 `C:/Users/user/AppData/Local/Temp/AOE2-before-lobby-resource-cleanup-20261001-062438`，GUI 備份為 `C:/Users/user/AppData/Local/Temp/AOE2-before-lobby-mapdots-20261001-062825`。

新增 **43 項實際來源清理測試**，檢查 true 標記、未知直接／巢狀模型、registry 身分／清空、重複清理及既有生命週期順序。完整 verify exit 0；其後明確建置正常 `build/AOE2.rbxlx` 成功。最新 CLI 摘錄為 `tests/optimization-lobby-final-cli-results-20261001.txt`。

06:34:29 Asia/Taipei 初次 Studio helper 因開局前 MatchGeneration 尚為 nil 而提前 **INCOMPLETE**，4 項檢查、0 個完整循環。這是測試初始化比較錯誤，沒有列作玩法通過。僅修正 helper 以 0 作初始 generation，保留初次副本／manifest／失敗摘錄 `tests/optimization-lobby-first-failure-results-20261001.txt`。

重新開啟 r2 副本並開始新 Play，06:42:52 Asia/Taipei **LobbyCleanup 126 COMPLETE**。全部循環透過正常 Lobby／Build／Order／Surrender／Restart 指令完成，沒有增資源或直接生成單位。

| 循環 | 地圖 | generation | 開局資源節點 | 已收到的資源部件 | 實際 PlayerGui 標記 | 返回大廳節點／部件／標記 |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Small | 1 | 420 | 2468 | 426 | 0／0／0 |
| 2 | Small | 3 | 420 | 2468 | 426 | 0／0／0 |
| 3 | Large | 5 | 1100 | 6204 | 1106 | 0／0／0 |
| 4 | Large | 7 | 1100 | 6204 | 1106 | 0／0／0 |
| 5 | Small | 9 | 420 | 2468 | 426 | 0／0／0 |

每局重建資源、地面／場景、初始單位、無角色與俯視鏡頭均就緒；Small Map 6775、Large Map 17359 檢查完成。第四局同尺寸 Large 重新生成後，正常花 25 木材造屋至 Complete，再讓村民實際採木。每次正常重開皆清單位／建築、四資源／人口，恢復大廳角色與 Custom 相機。暫時未知直接資源模型、未知資料夾內的巢狀標記模型、同名未知 RTSScenery 及模板保持原身分／Parent／管理標記。

原始 log：`C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T223624Z_Studio_8AE4B_last.log`。完整有限 JSON／逐行摘錄為 `tests/optimization-lobby-r2-studio-results-20261001.json` 與同名 `.txt`；可用 `tests/optimization-lobby-r2-evidence-parser.ps1` 再核對。**94／94 項來源與兩個建置 hash 一致**。正常執行程式的後續變更為 GameServer／GUI 的清理；歷史移動／音效／施工與負載成績保留原版本界限，沒有宣稱最新整體全數重驗。

- 最新正常 `build/AOE2.rbxlx` SHA256：`EECCAC08521CB465450E20B08532A6CB082C9BACBE9E60236F194946768D8AFE`。
- r2 隔離驗證 `build/AOE2-lobby-cleanup-studio-20261001-r2.rbxlx` SHA256：`DC760287ACABD15CF1EB92B88C32B69DDB82897D46825913054A6EF086A252B2`。
- 最新來源清單：`tests/optimization-lobby-r2-source-manifest-20261001.json`。前次障礙正常建置保存在 `build/AOE2-query-final-normal-20261001.rbxlx`，歷史清單與日誌未覆寫。

06:43:26 停止 Play，兩個本輪副本關閉時均選「不要儲存」，沒有發布或覆寫使用者原 place。測試模組只在獨立 validation project 映射並明確呼叫，不進入正常專案。

這些部件數是客戶端收到的 census，不能證明全部外觀子部件的完整複製、伺服器記憶體減少量或 FPS 改善比例。五輪單人保留測試沒有逐一核對未知模型的材質／顏色／CFrame；fixture 尚需等待客戶端收到子樹後再執行。Studio 另記錄大廳角色動畫資產 `96806611330323` 載入失敗，來源沒有使用該 ID；沒有把外部角色動畫或實際聽感列作通過。正式真機與四方滿人口長局仍未驗證。

## 最新真雙人集合、建造與退出

R2 使用獨立 Server & Clients、兩位真正 Player（Studio UserId -1／-2）、兩個實際 PlayerGui LocalScript 與正常遊戲遠端；正常 94 項來源維持五輪大廳驗證的版本，沒有為測試改權威位置、網路擁有權、集合旗標或資源。新增 helper／project 只映射到 R2 副本，不進入 default。

初次 V1 在第二端僅做一次 client PivotTo，客戶端已顯示入口但 server Root 仍在出生點，因此集合前置 INCOMPLETE，沒有執行 Kick。保存 V1 build／manifest、三端日誌及失敗摘錄 `tests/optimization-multiplayer-lifecycle-first-failure-20261001.txt`。這是已觀察到的客戶端／伺服器位置落差；角色初始化競態仍是推論，沒有寫成已證實的玩法原因。V1 原始長報告被 Studio 截斷，不能當完整 JSON。

R2 改讓真大廳角色用 `Humanoid:Move` 行走，再提出正常 QueueJoin。伺服器核對已集合與 Root 在入口半徑內才 ACK：房主實際位於 (0,4,2053)，第二位約 (0,4,2043)。既有 Shared.LobbyTests 的 client PivotTo 仍存在，但在呼叫前已完成真行走與 server ACK；沒有把它當測試前置的權威確認。這是腳本驅動的正常角色物理測試，不是鍵盤長按或人類手動入口驗收。

07:33:04 Asia/Taipei，server **36 COMPLETE**、host client **11 COMPLETE**、peer client **14 COMPLETE**。以下為同一新工作階段的公開狀態與實例 census：

| 時點 | phase／generation | 玩家 | 房主單位／建築 | 第二位單位／建築 | 生成資源節點／部件 |
| --- | --- | ---: | --- | --- | --- |
| 正常建造、訓練後 | Playing／1 | 2 | 5／2 | 4／1 | 420／2468 |
| 第一位真正離開後 | Ended／1 | 1 | 0／0 | 4／1 | 420／2468 |
| 最後一位真正離開後 | Lobby／2 | 0 | 0／0 | 0／0 | 0／0 |

房主正常設定雙人 Small／Rich／無 AI、兩人準備、開局、25 木材造屋完工與 50 食物訓練村民。第二端看到完成房屋與雙方物件，跨玩家 Order／Stop／Train／Research／AdvanceAge、非有限座標與請求突發均未改外方物件或雙方餘額。這次沒有測敵方 Delete、非房主 StartMatch 或所有戰鬥條件。

兩端先保存完成報告並經 CLIENT_DONE ACK，才依序 `Player:Kick` 觸發真正 PlayerRemoving。存留玩家確認勝利、房主權限轉移與 Ended 保留完整資源；最後離開後 server 確認 420 個原生成資源引用 Parent=nil、剩餘單位／建築消失、generation 只增加一次，公開勝負／房主／陣營數／對局時間狀態歸零。server 與 peer 也核對未知直接模型、未知資料夾內巢狀標記模型的身分、Parent、PrimaryPart、CFrame、Size、Material、Color、碰撞／query／touch 與管理標記保留。這是明確 fixture 的 metadata 測試，不涵蓋任意匯入模型的完整視覺。

原始日誌：server `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T233124Z_Studio_15AB1_last.log`、host `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T233130Z_Studio_D9700_last.log`、peer `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20260930T233131Z_Studio_56565_last.log`。R2 每段最多 320 UTF-8 bytes，並保留 reportId／index／total 與 compact summary；完整 server 報告 4457 bytes／14 段，host 768／3 段，peer 1128／4 段。`tests/optimization-multiplayer-lifecycle-r2-evidence-parser.ps1` 已核對 **26 份報告／72 筆原始分段與摘要**、兩端 CLIENT_DONE 行序及 server ACK；結果保存為 `tests/optimization-multiplayer-lifecycle-r2-studio-results-20261001.json` 與同名 `.txt`，不能只憑單行 COMPLETE 判讀。parser 的來源 hash 核對配合本聊天實際開啟 R2 檔及操作工作階段；原始日誌本身沒有執行 VM source hash，不能單憑 parser 證明載入的 place 身分。

- R2 build `build/AOE2-multiplayer-lifecycle-20261001-r2.rbxlx` SHA256：`B135EA4D01AB063C535ACA00E3BFE396D013DB0536E1F1F6E71C9FC2D3ECB80A`。
- 來源界限：`tests/optimization-multiplayer-lifecycle-r2-source-manifest-20261001.json`，94 baseline＋2 新驗證檔＝96。正常 build 仍為 `EECCAC08521CB465450E20B08532A6CB082C9BACBE9E60236F194946768D8AFE`。
- 本聊天以最終 parser 獨立重讀同三份原始 log，再取得同樣 36／11／14、26 報告／72 紀錄，保存為 `tests/optimization-multiplayer-lifecycle-r2-root-audit-20261001.json` 與同名 `.txt`；三份 log snapshot hash 與前次結果一致。parser 在暫存損壞副本的缺段、重複段、total 衝突、摘要 byte 數錯誤及缺少 CLIENT_DONE 五種情形均拒絕且不輸出。輸出已存在或不在 tests 目錄亦拒絕；重跑須用新檔名，不能覆寫歷史證據。
- 07:34–07:35 從副本主視窗「測試 → 結束作業」，關閉副本選「不要儲存」。最終視窗清單只保留使用者原 Studio；沒有連上原 place、發布或覆寫。

此局只有兩名玩家、9 個單位、Small 地圖與短時間施工／訓練；沒有量測雙人 FPS、CPU、記憶體，也沒有驗收正式配對、低階真機、手機手勢或四方滿人口長局。AOE2 的完整文明科技樹、陣形、迷霧、海軍、戰役等仍是後續功能；不能宣稱原型已 100% 模擬或普遍不卡。
