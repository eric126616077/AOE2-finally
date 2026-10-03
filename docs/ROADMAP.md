# 開發與驗收逐項進度

盤點日期：2026-09-30（Asia/Taipei），本次更新截至 20:39 正常發展 Advanced COMPLETE。依 [持續驗收紀錄](CONTINUATION-2026-09-30.md)、[19:13–19:46 原始引擎日誌](../tests/latest-integrated-studio-results.txt)、[整合 Play 來源 manifest](../tests/integrated-path-team-source.json)、[早期 Advanced 來源](../tests/advanced-integrated-source.json)、[19:58 初始化失敗日誌](../tests/latest-escape-readiness-results.txt)、[20:10 來源 manifest](../tests/escape-events-source.json)、[20:11–20:12 新 Flow 日誌](../tests/latest-escape-events-results.txt)、[20:17–20:39 Advanced 日誌](../tests/latest-advanced-escape-results.txt)、[新 Advanced 來源](../tests/advanced-escape-source.json) 與 [原模型同步 metadata 比對](../tests/original-models-sync-comparison.json) 核對；CLI／mock／來源整合和真正 Play 分開。調研見 [RESEARCH-2026-09-30.md](RESEARCH-2026-09-30.md)。後續修改須更新對應行及證據，不把「已寫程式碼」改稱「已驗證」。

**首發範圍：原創陸戰 RTS 測試版。** 支援村民四資源經濟、施工、時代／科技、可理解的兵種反制、最多四方對局、AI 練習、觸控／桌面、新手引導、免費公平文明主題。不是 AOE2 復刻；海軍、全歷史文明、完整戰役與全部官方科技樹不屬於首發必做。達到穩定首局、完整勝負、跨端公平與發布前門檻，才進入外部封閉測試。

使用三個獨立狀態：**程式**（實現／部分／缺）、**Studio**（對應快照通過／FAIL／待新版／未驗收）、**線上**（待正式客戶端或發布後量測）。所有線上項目目前均未在本清單取得新證據。本輪持續修改前備份為 `C:/Users/user/AppData/Local/Temp/AOE2-before-continuation-20260930-171631`，較早調研備份另保留；不覆寫原 place、不自動發布。

19:13:36–19:14:16，桌面單人正式覆盤兩局 Flow 取得 **92 事實／控制＋54 正式 UI COMPLETE**。19:20:19 原 Farm `(-228,-156)` 相鄰 Barracks `(-204,-156)` 正常完工 PASS；19:24:30 木材首次交貨 FAIL、383.9 秒、Age 1 保留。48 次引擎 Success 首段撞 House 與 19:45 安全前綴診斷後，20:17–20:39 的新 Advanced 真村民四資源採集／交貨、4 時代、18 建築、11 科技、10 種單位取得 **238 項 COMPLETE，1331.3 秒**，木材包含樹 `(-304,9,-120)` 的正常交貨。這支持該快照的正常發展，未涵蓋真戰鬥、封倉庫／耗盡回退或全部 G06。證據：[歷史失敗日誌](../tests/latest-integrated-studio-results.txt)、[新 Advanced 日誌](../tests/latest-advanced-escape-results.txt) 及 [來源](../tests/advanced-escape-source.json)。

R09 的伺服器、大廳與 GUI 已在 19:10 整合，尚無新版真正雙／四客戶隊伍 COMPLETE。完整 avatar observer 的 25 mock／CLI 未抓到19:58:36 fresh Flow Lobby INIT FAIL：actual avatar 已完整而 initial=true／Enabled=false。事件提交／defer及 Character 屬性觀察修正後，20:10 新快照的 **20:11:39–20:12:19 Flow 92＋54 COMPLETE，40.4 秒**；兩次 Restart 的 actual 控制還原通過，沒有觀察到新的 noHumanoid warning。初始20:10:47仍有一次 noCharacter warning；同一 runtime 的後續 20:39 Advanced 已取得真木材交貨與正常發展 COMPLETE；任意 avatar 替換／teardown仍待。

原模型兩份本地副本 [Original-before](../build/Original-before-20260930.rbxl) 與 [Original-models](../build/Original-models-20260930-1924.rbxl) 均為 **181,144 bytes**、SHA256 `7FC5659DF805BB00667D2540D804272E42EC6F26CDFF8D538FA92FAFC5BD7F17`；檔案一致只證明副本保存，原模型 runtime 尚未驗收。根代理已披露 Download 副本在 Studio 意外自動保存為雲端草稿，未執行 Publish；後續保持不自動發布、不覆寫本地原 place。

## 已有核心系統：仍須對應最新引擎版本

| ID／功能 | 程式盤點與位置 | Studio 與線上狀態／完成標準 |
| --- | --- | --- |
| C01 Rojo 映射與完整複製 | 實現。`default.project.json` 明訂 StreamingEnabled=false；Workspace／ReplicatedStorage 保留未知實例。 | 17:20 與 17:39 iPhone XR 橫向 Studio Release 19 通過完整複製與己方實例檢查；各自只支援當時快照。18:12 build 不構成新 Play。正式客戶端與原模型仍須驗收。 |
| C02 伺服器權威與遠端驗證 | 實現。`GameServer.server.lua` 統一命令，`MatchRules`／`UnitRules`／`ConstructionRules` 檢查設定、有限值、擁有者、頻率、人口、成本。 | 歷史雙人測試有許可權／無效請求證據；新版所有新增遠端仍需重複攻擊性驗證，失敗不得扣款。 |
| C03 大廳與集合 | 實現。`LobbyWorld`／`LobbyRules`、伺服器佇列、房主、1–4 真人、FFA／1v1／2v2／合作 AI、全部準備與變更取消準備；隊伍預覽在人齊後由伺服器發布。 | 19:13／20:12 Flow 與 20:17 Advanced 用正常單人大廳開局；沒有新版雙／四客戶模式、ready 取消、preview→assignment、退出與房主轉移 COMPLETE。G05／R09 仍待。 |
| C04 RTS 初始化與相機 | 實現。CharacterAutoLoads=false；大廳手動角色，開局清角色；UI 不等待 CharacterAdded。`PlayerInput` 非同步接管預設控制，完整 avatar 就緒與事件提交後還原初值、替換／teardown 清 observer；Studio `RTSControlProbe` 讀實際 closure。 | 19:58 Lobby INIT FAIL保留；20:10事件修正版的新Flow 92＋54／兩次Restart actual控制還原PASS，未觀察到兩次Restart noHumanoid。初始仍一次noCharacter；任意avatar替換／teardown、持續鍵盤／多指待驗。17:47–17:48 TouchFocus5只支持當時相機快照。 |
| C05 地圖與資源公平性 | 實現。`WorldGenerator` 三尺寸、固定種子、對稱出生資源與建設區；只清理系統標記實例。 | 純地圖檢查及舊大型地圖觀察是歷史證據。三尺寸新 Play、原模型障礙、四方長局與客戶端複製仍待。 |
| C06 模型保留與替代外觀 | 實現。`ModelFactory` 優先模板、清複製品指令碼；`Shared/Art.lua` 替代外觀；不刪除原模板。 | 原模型副本同步前後 Edit 的 7,616 筆 protected metadata multiset 無差；副本無 RS Buildings／Resource 真模板，不能支持模板分支。原模型 Play、未知障礙／初始出生、模板尺寸／碰撞／出口與 Clone 失敗回退仍待 G02。 |
| C07 四資源採集／攜帶／交貨 | 實現。伺服器尋資源、攜帶、適當營地、耗盡與再找資源；共用抵達與 PathRules 全段碰撞驗證。 | 20:17–20:39 Advanced 的 food／wood／gold／stone 真節點減少、攜帶上限與村民正常交貨 PASS，木材樹(-304,9,-120)亦真交貨；19:24木材FAIL保留。交貨點被毀、耗盡與封倉庫自動回退仍待；DeliveryFallbackTests目前僅編譯。 |
| C08 村民施工與協作 | 實現指定村民、到場才施工、停止／恢復、協作、完工才生效；`ApproachRules` 共用抵達位置／失敗側回退。 | 17:57 Farm FAIL 保留；19:20:19 原 Farm(-228,-156) 相鄰 Barracks(-204,-156) 正常施工 PASS。20:39 Advanced 全18建築正常施工完工 COMPLETE；工人損失、途中中斷／修復與被毀生命週期另待。 |
| C09 修復 | 實現。村民修復自己受損建築，伺服器扣木材。 | 完整成本／中斷／敵方拒絕／目標被毀待新 Studio。 |
| C10 建築 | 配置與伺服器支援 18 種。修道院只有建築，沒有僧侶；保留本作時代與前置規則。 | 20:39 Advanced 的18種建築正常成本／施工與至少一座真正完工 PASS，含原相鄰 Farm；被毀清佇列、未知原模型障礙及 RS 真模板仍待。 |
| C11 訓練與人口 | 實現。10 種單位、每建築佇列 5、預留人口、出口受堵等待。 | 20:39 Advanced 的10種單位正常成本／計時與己方實例生成 PASS，含新村民／軍隊繼承已研究數值；滿人口、造屋被毀、堵出口與佇列併發仍待。 |
| C12 四時代 | 實現共享成本／時間、不同種完工建築前置與城堡替代；`AdvancedTests.RunDevelopment()` 正常經濟／計時驗收。 | 20:39 Advanced 四時代正常前置／扣款／計時 COMPLETE，19:24 Age1木材FAIL保留；研究互斥與研究建築被真攻擊摧毀／重研仍待。較早 ProgressionTests 沒有新版完整 COMPLETE，不與 Advanced 混稱。 |
| C13 科技 | 實現 11 項，伺服器研究、前置、既有及新單位套用；生產／研究取消生命週期有純檢查。 | 20:39 Advanced 全11科技正常成本／計時／研究狀態與相關現有／新生數值、實際採集量／新農田容量 PASS；箭羽實際射程、拇指環實際攻擊間隔及研究建築被真攻擊摧毀取消／重研明確未驗收。 |
| C14 市集 | 實現固定 100 批次、買 130／賣 70 黃金。 | 20:39 Advanced 正常比例買賣、黃金不足拒絕不扣任何資源 PASS；惡意頻率另待。沒有貿易車／動態市價。 |
| C15 戰鬥與兵種反制 | 實現攻擊、索敵／反擊、塔／城堡、額外傷害及投石車範圍；`CombatRules`、`MeleeRules` 與共用抵達選擇具純檢查。 | 51 項交戰關係／索敵與 5,156 項近戰幾何只是純邏輯。尚未完成十種真實交戰、傷害／護甲／節奏、雙人同步與窄路；R06 戰損計數亦待真攻擊。不能以靜態數值認定已平衡。 |
| C16 AI | 實現三難度經濟、施工、訓練、時代／科技與進攻。本輪 `AIWorkerRules.lua` 與伺服器修復中斷工地接手、不重扣造價；耗盡後按原目標 ResourceType 尋找替代；按缺口順位搜尋仍可取得的資源。 | 新增 12 項 AI 工地接手／資源回退純邏輯檢查，主代理回報通過；不代表引擎已重現所有恢復情境。舊人口斷言可由起始單位滿足；最新版仍須確認真實新增村民、四時代、資源枯竭、滿人口、奇觀與長局。 |
| C17 三勝利規則 | 實現征服、起始主城決戰、完工奇觀 180 秒。 | 舊投降／離開能結束雙人局；不等於實際戰鬥征服、主城摧毀、奇觀守成／被毀都通過。 |
| C18 離開／觀戰／重開 | 實現PlayerRemoving清狀態實例、晚加入觀戰、房主重開；R09自然淘汰待隊伍結果、投降／退出個人判負。 | 18:50–18:51真桌面Watch→Menu再開報告→Restart操作保留；19:13與20:12各自Flow兩局正常Restart／JSON／UI清零通過。新版隊伍離開／晚加入／轉移、連續五次與記憶體待。退出者私人JSON未複製前卸載時不能聲稱其outcome已被客戶端驗到。 |
| C19 HUD／滑鼠鍵盤 | 實現資源、人口、操作卡片、小地圖、框選／編隊／快捷鍵、安全區與模態命中探針；覆盤捲動／非同步 JSON、R09 模式設定與盟友文字。 | 19:13 桌面覆盤每局正式 UI 27，共 54 通過精確文字、存活時間、44 px、捲動幾何、模態／清除；18:50 真 Watch／Menu／捲動／Restart 操作是早期版本。最新 R09 手機橫／直向與盟友指令仍待。17:39 XR Touch38、17:47 TouchFocus5 均只支援當時快照；真機／多指／持續鍵盤仍待。 |
| C20 Luau／純邏輯／Rojo 檢查 | `scripts/verify.ps1` 與 Shared 顯式引擎模組已存在；[latest-cli-results.txt](../tests/latest-cli-results.txt) 記錄規則／mock／CLI／build，來源快照須各自保存。 | 19:57 CLI＋25 helper mock仍有19:58引擎INIT FAIL，保留差異；20:10事件修正版Flow與20:39 Advanced各自取得真Play證據；TeamMatchTests／CombatFlowTests仍未完成引擎驗收。CLI不替代Play，mock不連正式雲端。 |

## Roblox 產品缺口與實施順序

| ID／優先順序 | 開發範圍 | 初始狀態／結束判定 |
| --- | --- | --- |
| R01／P0 初學引導 | `Shared/Tutorial.lua` 五步：選村民、交貨、房屋完工、訓練新村民、生成步兵；可隱藏與重新檢視。短橫向 44 px 可展開提示，手機橫／直向重排。 | **程式實現；17:20、17:39 指引可見檢查通過，玩家理解待測。** 同局實際 UI 選村民／主城／訓練村民並觀察引導完成；直向有可見操作觀察。第五步只查步兵生成，不能宣稱真攻擊或首次玩家理解已驗收。16:36 FAIL 與修正後快照保留。 |
| R02／P0 觸控操作 | `TouchRules`／`RTSClient`／`PlayerInput`／GUI 提供觸控命令、雙指相機、44 px、安全區、模態探針；完整角色與事件提交後還原預設控制。 | **舊 XR Touch38／桌面 Lobby21／Playing26 證據保留；20:12桌面Flow兩次Restart控制PASS。** 19:58初始化FAIL與20:10初始noCharacter仍保留。R09設定／盟友／pending UI待新橫直向Play；實際手指／多指／真機效能仍待。 |
| R03／P0 公平文明／造型 | 三免費原創主題：河灣盟邦、旭日城邦、青林公國。`CivilizationRules` 限身份欄位；AOE2 式加成與專屬兵種只在 `Config.CivilizationBonuses`，有上限且三文明數量一致、全部免費；`CommerceRules` 限文明／造型且空目錄保持關閉，局中鎖文明。 | **程式實現；17:20、17:39 Release 19 COMPLETE 支援當時文明選擇、非法拒絕、取消準備與局中鎖定；交易未上線。** 主題標識不是完整三套建築美術；目錄沒有正式商品。白名單與正式驗收見 [LAUNCH.md](LAUNCH.md)。 |
| R04／P0 新版整合驗收 | 無模型、原模型、正常發展、雙／四客戶隊伍、真實戰鬥與三勝利；覆盤正常流程。 | **正常 Flow 與 238 項 Advanced 發展 COMPLETE，歷史 Farm／木材 FAIL 保留。** 根代理正正常操作 Studio 診斷；來源修改後須新 Play。G02 原模型、G05 新多客戶、G07 戰鬥／勝利、R09 隊伍、G10–12 正式環境／壓力／發布資料仍待。 |
| R05／P1 練習與快速模式 | 本輪「新手練習 · 無對手」按鈕設定一人／Small／0 AI／Rich／60 人口沙盒，仍經準備規則。未來另測有對手的快速主城模式。 | **練習預設程式實現；16:40–16:41 查到實際練習按鈕並以測試遠端設定成功開單人練習。** 尚未由首次玩家操作該按鈕完成首局。無對手沙盒沒有完整戰鬥勝負，不等於快速 PvP 已完成；12–18 分鐘僅假說。 |
| R06／P1 新手回饋與戰後覆盤 | **伺服器／GUI實現，正常單人範圍有引擎通過。** 真交貨、淨支出／退款、完工／訓練、HP差與戰損；免費模型／投降清場排除；R09 pending凍結個人行動與存活，final隊伍結果優先Defeated；不存經濟／戰力。 | 19:13及20:12各自Flow **92事實／控制＋54正式UI COMPLETE**：兩局正常開局／投降／Restart、第二局房屋／村民／食物交貨與獨立餘額、精確文字／存活／44px／捲動幾何／模態／清零。18:33 footer44、18:39交貨、19:58初始化FAIL均保留。真HP差／擊殺／損失、退款與pending→隊伍final仍待正常戰鬥／多客戶。 |
| R07／P1 效能與穩定性 | 大型四方每方 200 人、長局、尋路、記憶體、遠端頻率、重開。 | 待。記錄客戶端 FPS／伺服器步驟／記憶體／網路，真實低階裝置穩定 30 FPS 為初始目標。純函式檢查不替代。 |
| R08／P1 留存與漏斗 | `Telemetry` 與伺服器掛接：加入→集合→開局→首次交貨→房屋完工→首次訓練漏斗，及開局／完成／退出，含模式／文明／地圖。含在 80 項 profile／analytics mock 中。 | **基礎程式與 mock 通過，正式 Dashboard／線上 cohort 未驗收。** 17:20、17:39 Release 確認當時 Studio 停用雲端分析；未有完整 UI 行為、版本／入口分群與玩家理解量測。正式驗收見 [LAUNCH.md](LAUNCH.md)。 |
| R09／P1 同盟與朋友合作 | **19:10 主目錄已整合** TeamRules／GameServer／LobbyRules／GUI／RTSClient：FFA、兩陣營1v1、四陣營2v2、所有真人合作對 AI；伺服器分隊與 preview、盟友不可攻擊、各自資源／控制、pending／final、投降／退出不翻盤。`TeamUITests` 唯讀、`TeamMatchTests` 正常遠端分階段驗收。 | Team2132、team/report lifecycle33、client proposal35、Report92 為 CLI；19:13 單人 FFA Flow 不代表團隊通過。**真正雙／四客戶仍未驗收**：改 mode 取消所有ready／舊revision拒絕、preview→actual、友軍攻擊／跨控制拒絕不扣款、投降／退出、restartclear。天然淘汰→pending→盟友win須正常戰鬥另測；手機模式列／設定捲動／pending也待。 |
| R10／P1 文明偏好與戰績存檔 | `ProfileRules`／`ProfileStore` 儲存文明偏好及已完成、至少兩名真人且無 AI 的對戰結果。UpdateAsync 合併增量、結果 ID 去重、重試、離開／關閉寫入，載入失敗禁止覆寫。`CivilizationPreferenceRules` 延後套用非大廳偏好；有效明選清待套用值，延遲讀取保留原時間戳。 | **基礎程式與 80 項 mock 回歸通過，正式重連／跨服併發未驗收。** 17:20、17:39 Release 確認當時 Studio 停用正式存檔，不是正式偏好讀寫證據。R06 僅單局覆盤，不新增持久經濟或戰力；無造型庫／教學進度存檔。正式驗收見 [LAUNCH.md](LAUNCH.md)。 |
| R11／P2 戰爭迷霧 | 共享視野規則、探明地形、當前敵軍可見、輸入與小地圖一致。 | 缺。當前全圖可見。需評估完整複製下保密與效能，單純隱藏客戶端外觀不是強反作弊保密。 |
| R12／P2 配對與段位 | 正式體驗多伺服器／隊伍匹配、水平匹配、斷線政策、公平反濫用。 | 缺。現有同伺服器等待門不等於跨伺服器配對；需要正式服務環境。 |
| R13／P2 更深玩法 | 僧侶／聖物、貿易、單位升級系譜、展開投石機、駐軍／陣形、狩獵、海軍／戰役。 | 部分。2026-10-03 新增 12 項兵種升級（長劍兵→冠軍劍士、長戟兵、弩手→重弩手、精銳矛兵、重裝騎射手、輕騎兵、遊俠騎士、重裝駱駝騎兵、加蓋衝車、野戰投石車）、騎射手／駱駝騎兵／火槍手，以及開局鹿群狩獵（靜止獵物）；CLI 設定完整性與美術 mock 通過，**Studio 未驗收**。駐軍、陣形、僧侶已實作；2026-10-03 另新增聖物（僧侶拾取、修道院產金、掉落）與貿易車／商隊（己方或盟友市集往返），CLI 規則通過，**Studio 未驗收**。聖物勝利、會逃跑的獵物、海軍／戰役仍缺。 |
| R14／上線項 真實付費交易 | 註冊 Roblox 商品、伺服器 API 驗證／發貨、已擁有／取消／失敗狀態、安全儲存。 | 未配置、未驗收。商品目錄與假 ID 不算完成；商品建立和正式發布依使用者授權與專案約束。 |
| R15／上線項 內容與增長實驗 | 原創名稱／圖示／縮圖／準確介紹、招募測試、版本實驗、正式留存測量。 | 原創幾何圖示與介紹草稿已製作、未上傳；實際對局縮圖／招募／版本實驗／留存測量仍待。先完成可玩的首局，再測不同素材／入口；不宣稱一定爆款，不發布誤導畫面。 |

## 歷史證據保留方式

以下時間皆為 2026-09-30 Asia/Taipei；原始 Studio log 採 UTC，09:xxZ 對應 17:xx。每行只支援當時正在運作的腳本快照。後續同步原始碼不能讓舊 VM 的結果自動涵蓋新功能。

| 時間／版本界線 | 真實證據 | 未涵蓋／後續狀態 |
| --- | --- | --- |
| 16:30、16:40–16:41 歷史快照 | 桌面 Release 18／Touch 20／施工 36；後者 XR 橫向 Release 19／Touch 33／施工 36 COMPLETE。16:36 指引 FAIL 及重跑修正保留。 | 不是本次最新快照；當時 Computer Use 啟用失敗後曾依技能停止。 |
| 17:20–17:21 新 XR 橫向 Play | Release 19／Touch 33／施工 36 COMPLETE；同局正常 UI 選取、訓練與指引，以及旋轉 XR 直向的版面／選單操作觀察。 | 早於新增原生控制政策、UI 探針與生命週期修正；直向沒有獨立 COMPLETE，沒有真機／多指。 |
| 17:23 唯讀原生 UI 觀察 | `TouchControlsEnabled=true`，但 `TouchGui.Enabled=false`，搖桿／跳躍完整祖先可見性為 false。 | 不能描述成畫面持續殘留原生控制；之後明確關閉控制屬於修正。 |
| 17:39–17:40 新 XR 橫向 Play | Release 19／Touch 38／施工 36 COMPLETE；實際 UI 命中探針、原生控制、操作列中心／相鄰地面、提示中心。 | 沒有實際手指／多指證據，早於最後預設 ControlModule 接管與 R06。 |
| 17:40–17:48 相機觀察 | 首次聚焦 2 PASS 後未觀察到 15 studs 平移而 FAIL；17:44 W 是 processed=false、無 TextBox／模態；17:47–17:48 正常選單開邊緣移動後，同主城重聚焦 5 COMPLETE。 | 不支持預設控制吞鍵因果；只證明正常邊緣平移與重聚焦，沒有持續鍵盤／多指完整驗收。 |
| 17:53、17:58 桌面新 Play | 實際 `RTSControlProbe`：Lobby Touch 21／Playing Touch 26 COMPLETE，確認還原初值與預設角色控制停用。 | 不 require 新一份 PlayerModule／GUI 假共享狀態；早於工作抵達與覆盤。 |
| 17:53–17:57 Advanced | 正常資源／計時完成磨坊、伐木場、採礦營地、兵營與部分不扣款拒絕；232.1 秒 **Farm FAIL**，之後讀到 `(-228,0.6,-156)`、進度 0、BuilderCount 0。 | [advanced-play-source.json](../tests/advanced-play-source.json) 保存當時版本。未完成四時代／18 建築／11 科技／10 單位；共用工作抵達修正後仍待新 Play。 |
| 18:12 CLI 與其後新增來源 | 當時有報告 80、工作抵達 411、其他既有純檢查、Luau／Rojo；覆盤 GUI 22 為代理另行回報，Flow 單檔編譯。 | 當時不是新 Play／TeamRules 尚未整合；19:13 後來取得新的 Flow 證據。現存 latest-cli-results 已更新，不當作未變動的舊日誌。 |
| 18:33–18:51 覆盤迭代 | footer44 FAIL；ceil 修正後第一局 UI27／Restart PASS，第二局食物交貨 130 秒 FAIL；18:50–18:51 真桌面 Menu／結果捲動／Watch／Menu 重開／Restart 操作。 | [latest-match-report-results.txt](../tests/latest-match-report-results.txt) 與當時 manifests 保留。畫面交貨0、背包10未誤計；沒有當時 Flow COMPLETE。 |
| 19:10／19:13–19:14 整合來源與新 Flow | R09 已整合；新桌面單人 **92 事實／控制＋54 正式 UI COMPLETE**、兩局正常 Surrender／Restart／清除。 | [integrated-path-team-source.json](../tests/integrated-path-team-source.json)。不涵蓋真戰鬥／退款／隊伍／手機；官方初始化與 Restart warning 仍有。 |
| 19:18–19:24 新 Advanced | 原 Farm(-228,-156)／相鄰 Barracks(-204,-156) 19:20:19 正常完工 PASS；16 村民與食物交貨局部 PASS。 | [advanced-integrated-source.json](../tests/advanced-integrated-source.json)。木材首次正值／交貨383.9秒FAIL、Age1，無 Advanced COMPLETE。 |
| 19:33–19:45 唯讀引擎診斷 | 48 次 PathStatus.Success 首段都撞 House；原位置安全8stud前綴後 radius3／4全段 Blockcast clear。 | [latest-integrated-studio-results.txt](../tests/latest-integrated-studio-results.txt) 原始查詢。不代表伺服器單位真返場交貨。 |
| 19:48／19:57–19:58 新控制／前綴快照 | main完整 avatar observer＋safe prefix；25 helper mock、CLI／Rojo通過；**19:58:36 Flow Lobby INIT FAIL**，未開局。 | [escape-readiness-source.json](../tests/escape-readiness-source.json)、[latest-escape-readiness-results.txt](../tests/latest-escape-readiness-results.txt)。actual完整avatar仍Enabledfalse；修正中，path runtime 未到 field。 |
| 20:10／20:11–20:12 事件提交修正新 Play | **Flow 92事實／控制＋54正式UI COMPLETE、40.4秒**；兩次Restart actual控制還原PASS，未觀察到新的noHumanoid warning。 | [escape-events-source.json](../tests/escape-events-source.json)、[latest-escape-events-results.txt](../tests/latest-escape-events-results.txt)。House(-184,-184)／TC(-216,-216)、food(-152,-104)真交貨；初始仍1次noCharacter，當時木材前綴field／Advanced尚未驗；後續另局20:39 COMPLETE。 |
| 20:17:00–20:39:11，新正常發展 Play | **Advanced 238 項 COMPLETE，1331.3 秒**：真四資源採集／交貨、4時代、18建築、11科技、10單位與市集買賣／不足拒絕。 | [advanced-escape-source.json](../tests/advanced-escape-source.json)、[latest-advanced-escape-results.txt](../tests/latest-advanced-escape-results.txt)。正常木材返場已走完；log 明示真射程／攻擊間隔、研究被毀、傷害與三勝利 UNVERIFIED。 |
| 20:35–20:36，原模型本地副本 Edit | Rojo 同步前後 protected metadata multiset **7,616 筆／0差異**。 | [before](../tests/original-models-before-sync-results.txt)、[after](../tests/original-models-after-sync-results.txt)、[comparison](../tests/original-models-sync-comparison.json)。相機／地形／mapped roots排除；Source長度＋rolling fingerprints非cryptographic byte proof；無 RS 真模板，Play仍待。 |

Computer Use 已於 17:20 恢復，根代理協調來源與視窗，禁止把來源熱同步套到舊 VM 的結果。19:24木材／19:58初始化FAIL保留；20:12事件修正版Flow與20:39正常Advanced分別COMPLETE。真機、多指、最新雙／四客戶、真戰鬥、原模型runtime、封倉庫／耗盡回退及正式雲端仍待。

- [`tests/latest-release-touch-results.txt`](../tests/latest-release-touch-results.txt)：2026-09-30 16:30 桌面、16:36 失敗與 16:40–16:41 XR 橫向的原始 PASS/FAIL/COMPLETE；記錄最後 GUI 微調未再 Play，及工具限制。
- [`docs/CONTINUATION-2026-09-30.md`](CONTINUATION-2026-09-30.md)、[`tests/latest-continuation-results.txt`](../tests/latest-continuation-results.txt)：17:20–17:58 真實 Play、相機觀察與 Farm FAIL；此文件更新以這份結果核對。
- [`tests/advanced-play-source.json`](../tests/advanced-play-source.json)：17:53 Advanced 工作階段的四個關鍵原始碼 hash；不同 hash 的修正不沿用此局驗收。
- [`tests/latest-cli-results.txt`](../tests/latest-cli-results.txt)：當前 CLI 快照；純函式／mock／build 與 Studio 分開，現存檔已較18:12更新。
- [`tests/latest-match-report-results.txt`](../tests/latest-match-report-results.txt)、[`tests/match-report-play-source.json`](../tests/match-report-play-source.json)、[`tests/match-report-fixed-source.json`](../tests/match-report-fixed-source.json)：18:33 footer FAIL、修正後第二局交貨 FAIL 與18:50–18:51桌面人工操作。
- [`tests/latest-integrated-studio-results.txt`](../tests/latest-integrated-studio-results.txt)、[`tests/integrated-path-team-source.json`](../tests/integrated-path-team-source.json)、[`tests/advanced-integrated-source.json`](../tests/advanced-integrated-source.json)：19:13正常Flow、19:20原Farm PASS、19:24完整Advanced FAIL與19:45唯讀路徑診斷。
- [`tests/latest-escape-readiness-results.txt`](../tests/latest-escape-readiness-results.txt)、[`tests/escape-readiness-source.json`](../tests/escape-readiness-source.json)：19:57最新來源凍結及19:58 freshFlow LobbyINITFAIL，未取得前綴runtime。
- [`tests/latest-escape-events-results.txt`](../tests/latest-escape-events-results.txt)、[`tests/escape-events-source.json`](../tests/escape-events-source.json)：20:10事件提交修正版來源；20:12正常兩局Flow92＋54與兩次Restart控制PASS，初始noCharacter仍在；當局未驗wood，20:39另局Advanced正常交貨已通過。
- [`tests/latest-advanced-escape-results.txt`](../tests/latest-advanced-escape-results.txt)、[`tests/advanced-escape-source.json`](../tests/advanced-escape-source.json)：20:17–20:39正常發展238項／1331.3秒COMPLETE與G07未驗收聲明。
- [`tests/original-models-before-sync-results.txt`](../tests/original-models-before-sync-results.txt)、[`tests/original-models-after-sync-results.txt`](../tests/original-models-after-sync-results.txt)、[`tests/original-models-sync-comparison.json`](../tests/original-models-sync-comparison.json)：本地原模型副本Edit同步前後7,616筆零差異；無RS真模板、runtime待。
- [`docs/STORE-LISTING.zh-TW.md`](STORE-LISTING.zh-TW.md)、[`forge-badge-512.png`](../assets/publishing/forge-badge-512.png)、[`forge-badge-128.png`](../assets/publishing/forge-badge-128.png)、[`forge-badge.svg`](../assets/publishing/forge-badge.svg)：原創幾何圖示與介紹草稿，尚未上傳；實際對局縮圖仍待。
- [`tests/latest-lobby-construction-results.txt`](../tests/latest-lobby-construction-results.txt)：2026-09-30 16:04–16:05，12 項大廳與 36 項施工 COMPLETE。僅支援當時原始碼／單人無模型。
- [`tests/latest-studio-results.txt`](../tests/latest-studio-results.txt)：2026-09-30 15:07 的 35 項基礎檢查。AI 真新增村民的嚴格新版斷言尚未重跑。
- [`tests/latest-multiplayer-results.txt`](../tests/latest-multiplayer-results.txt)：2026-09-30 15:25–15:31 的 29 PASS。早於新傳送門集合與全部準備規則。
- [`tests/STUDIO.md`](../tests/STUDIO.md)：具體呼叫、原模型／無模型區分與引擎限制。`ProgressionTests` 未取得修正版完整通過日誌。

這些路徑為既有證據索引，不表示本調研代理已重新執行。任何新驗收須寫版本、時間、模式、玩家數、PASS/FAIL/COMPLETE 和未覆蓋範圍。

## 發布前必須逐項驗收

以下是首發門檻，不以完整 AOE2 功能當驗收。每行須記錄版本／日誌／裝置，未通過不自動打勾。

| 門檻 | 實際執行 | 通過條件 |
| --- | --- | --- |
| G01 構建與最小啟動 | Luau 編譯、純規則檢查、指定 Rojo build；以新無模型 Play 啟動。 | 無語法／映射錯誤；客戶端有地面、資源、替代模型與 HUD，原始 place 未覆寫。 |
| G02 模型保留 | 在原模型副本同步並 Play，含未知 Workspace 障礙。 | **Edit保留部分PASS、runtime仍待**。本地副本同步前後7,616筆protected metadata multiset零差異；兩原副本181,144bytes／SHA相同。這份副本無RS真模板，不支持模板Clone／尺寸分支；未知大模型初始重疊、遮擋／碰撞／出口須真Play。 |
| G03 完整首局 | 未玩過本作的人執行練習，實際選擇／交貨／房屋完工／訓練／部隊操作。 | 指引與真實 PlayerGui 同步；可略過／重開，無卡住的必要步驟；完成或失敗均有解釋。 |
| G04 桌面／觸控 | 1366×768、常見寬屏、手機橫向與直向／安全區；底部面板相鄰地面、UI／彈窗、小地圖與雙指手勢。 | UI 不穿透；能選取、採集、施工、訓練、移動與攻擊；相機不被單選手勢誤移；真實手機另驗。 |
| G05 大廳兩人 | 最新兩個真正客戶加入／退出、切設定、拒絕舊 revision、全部準備、房主離開與重開；R09 另做四客戶。 | **多客戶新版未 COMPLETE**。20:12修正版單人Flow／兩次Restart控制PASS不替代兩端；仍驗同配置、缺人／未準備拒絕、改mode取消準備、preview→actual、角色→RTS與晚加入觀戰。初始官方Move noCharacter warning仍保留。 |
| G06 經濟與發展 | 四資源、18 建築、四時代／11 科技／市集、取消／被毀／人口／出口；原相鄰 Farm 與木材返場。 | **正常發展238項COMPLETE，G06整體仍未全驗**。20:39四資源真交貨、18建築、4時代、11科技、10單位與市集PASS；19:24木材FAIL保留。封倉庫／耗盡／交貨點被毀、取消／研究被毀、修復、滿人口／堵出口另待；DeliveryFallbackTests僅編譯。 |
| G07 戰鬥／勝負／覆盤 | 雙端十單位、剋制／範圍／塔城堡、真征服／主城摧毀／奇觀守成及被毀、隊伍pending/final與覆盤。 | **真戰鬥與三勝利仍待**。19:13及20:12已驗單人非戰鬥覆盤、正常投降／Restart與清零；未涵蓋真HP／kill/loss、退款、自然淘汰或盟友逆轉。投降、斷線與多人結果各需新引擎證據。 |
| G08 AI 可持續 | 三難度，真實新增村民、建設、交貨、出兵、發展到帝王；資源耗盡／建築損失後恢復。 | 不使用免費生產或瞬間施工；無經濟死鎖；在所列首發地圖完整打一局。 |
| G09 公平與濫用 | 三文明同配置；未知欄位／文明／非有限座標／他人實例／重複／突發遠端請求。 | 數值與可用命令一致；不得付費資源或能力；錯誤請求不扣款、不越權、不崩服；文明局中不變。 |
| G10 檔案／線上統計 | 正式偏好／戰績重連、讀寫失敗、離開／關閉、跨服併發；Dashboard 與合法／偽造／重複 analytics。 | **正式服務未驗收**。mock／Studio API關閉不是雲端成功；不覆蓋未載入存檔、無資源／戰力存檔，隊伍自然淘汰待final／forfeitloss持久結果仍需正式驗證。 |
| G11 穩定性 | 大型四方每方200人口、長局、連續五次重開、退出／晚加入與真實低階裝置。 | **未驗收**。20:39單人Advanced正常發展22.2分鐘及兩局短Flow不支持四方200人口／五次重開穩定；須記真FPS、伺服器步驟、網路／記憶體與連線清理。 |
| G12 可審查發布內容 | 原創名稱／圖示／縮圖／準確介紹、裝置支援、測試版標識；未配置文明／造型商店保持關閉。 | **部分素材完成，發布門檻未完成**。原創堡壘鍛火徽記512／128／SVG及本機生成腳本、介紹草稿已製作，尚未上傳；實際對局縮圖仍待。只能描述原創RTS測試版；未完成真機／原模型／多人／戰鬥不得宣稱完整遊戲。Download副本意外自動保存雲端草稿已披露，未執行Publish；後續不自動發布／覆寫本地原place。 |

正式發布之後的 D1/D7/D30、自然流量、朋友共玩與文明／造型購買意願屬於市場實驗。即使 G01–G12 全通過，也只能證明該版本達到測試門檻，不能宣稱市場成功。

## 對本輪完成的定義

本輪可以自主完成原始碼、介面、測試模組、文件、Rojo 輸出與獲得工具允許的 Studio 驗收；必須仍稱測試版。真實手機、外部玩家理解／留存、正式商品、正式伺服器跨局儲存及配對、公開上線後的增長沒有資料便保持待驗證。無外部玩家不意味著程式碼不能推進，也不意味著可以把市場成功打勾。
