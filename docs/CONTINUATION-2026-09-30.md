# 持續驗收紀錄

本輪修改前備份：`C:/Users/user/AppData/Local/Temp/AOE2-before-continuation-20260930-171631`。保留原模型與本地原 place；不自動發布。本文保留早期失敗及其來源，並追加截至20:39的引擎／原始碼狀態。Download副本意外自動保存雲端草稿的披露另記於文末；未執行Publish。

2026-09-30 17:20–17:21（Asia/Taipei），重新啟用 Studio build 視窗後在真正單人 Play、無自訂模型、iPhone XR 橫向模擬器取得 Release 19、Touch 33、Construction 36 項 COMPLETE。原始日誌摘錄見 [latest-continuation-results.txt](../tests/latest-continuation-results.txt)。這個快照早於本輪新增的原生觸控控制政策、UI 命中探針與伺服器生命週期修正，不代表後續所有修改已通過。

同一測試局以實際介面點選「村民」、「主城」、訓練村民，觀察真實伺服器生成人口及引導完成；再切換 iPhone XR 直向，資源、指引、小地圖、操作列與生產卡可見。直向開啟選單也可操作。這是 Studio 模擬器及合成滑鼠操作，不是首次玩家研究、真機或多指手勢測試。

17:23 讀取實際 PlayerGui：Playing 階段 GuiService.TouchControlsEnabled 當時仍為 true，但 TouchGui.Enabled=false，搖桿與跳躍控制的完整祖先可見性均為 false。新修正明確在 RTS 階段關閉控制，以避免階段切換短暫顯示；不能把這次讀取描述為持續殘留控制的證據。

17:39–17:40 新 iPhone XR 橫向 Play：Release 19、Touch 38、Construction 36 項 COMPLETE。Touch 檢查實際原生控制、GUI 命中探針、操作列中心與上鄰地面、新手提示中心；雙指部分仍是規則模擬，沒有真手指證據。

17:40 相機觀察只通過首個聚焦與置中，未觀察到 15 studs 平移而逾時；17:44 真實 W 事件是 processed=false、沒有 TextBox 或模態，不支持「預設控制吞鍵」推論。Sky 短按不能當作持續按鍵證據。17:47–17:48 再以正常介面開啟邊緣移動，主城→鼠標邊緣平移→同主城得到 TouchFocus 5 項 COMPLETE；沒有寫入 CameraFocus 屬性或直接搬動相機。

17:53 新桌面 Play 以正在運作的 PlayerInput Studio 唯讀控制探針取得 Lobby 還原初值與 Touch 21 項 COMPLETE；17:58 Playing 的同一真實探針確認全部預設角色控制停用，Touch 26 項 COMPLETE。這些探針讀真正腳本 closure，測試不 require 另一份 PlayerModule 或 GUI 建立假共享狀態。

17:53–17:57 Advanced 真實發展測試 **FAIL**：按正常成本／計時完成磨坊、伐木場、採礦營地、兵營後，農田正常行走施工逾時，工地進度 0、BuilderCount 0。當時版本見 [advanced-play-source.json](../tests/advanced-play-source.json)。這個失敗保留；19:20 原座標正常施工的新 PASS 見下文，不能用搬遠工地替代修復。

## 18:33–19:14：覆盤失敗、修正與正常兩局 COMPLETE

18:33 首版結果 footer 因 `44 / UIScale` 的 UDim 整數截斷，實際點擊高度約 43 px，嚴格 44 px 斷言 FAIL。改為 `math.ceil(44 / factor)` 後，18:36 第一局正式 UI 27 與正常 Restart／清零通過；第二局完成 House、Train、採到食物 10，仍在返場交貨 130 秒逾時，沒有 Flow COMPLETE。原始 [latest-match-report-results.txt](../tests/latest-match-report-results.txt) 及 [play](../tests/match-report-play-source.json)／[fixed](../tests/match-report-fixed-source.json) manifest 保留失敗。

18:50–18:51 真實桌面介面操作：Menu→投降→結果、捲動、Watch→Menu 重開報告、結果按鈕 Restart。畫面有食物支出 50、木材 25、房屋 1、村民 1，交貨仍為 0；背包內的 10 食物沒有當成已交貨。這是當時的操作觀察，沒有補成失敗 Flow 通過。

19:10 R09 與第一輪全路徑 Blockcast／精確 waypoint 修正已安全整合；19:13:36–19:14:16 新桌面單人 Play，正常 Rich／Small／AI0 兩局 Flow 取得 **92 事實／控制＋54 正式 UI COMPLETE，40.5 秒**。第一局驗免費開局／投降清場不混入覆盤；第二局用真村民房屋完工、正常訓練村民、食物攜帶／交貨，以及獨立資源餘額核對報告。兩局都走正常 Surrender／Restart；JSON、欄位文字／標記與累計事實清除，actual 控制探針還原初值。每局正式 UI 27 核對精確數字／存活文字、44 px、捲動幾何與模態防穿透。證據：[latest-integrated-studio-results.txt](../tests/latest-integrated-studio-results.txt)、[integrated-path-team-source.json](../tests/integrated-path-team-source.json)。

這個 COMPLETE 支持單人非戰鬥範圍，沒有真 HP 傷害／kill/loss、退款、隊伍 pending→final、手機覆盤或正式雲端戰績證據。House／食物的精確座標未在這局另印，只能證明相同正常操作流程能完成交貨。初始及 Restart 仍有官方 `Player:Move called, but player currently has no character/no humanoid` 警告，不能因控制探針 PASS 宣稱警告消失。

## 19:18–19:46：原相鄰 Farm 已 PASS，Advanced 木材返場仍 FAIL

19:18:06 開始新的 Advanced 正常發展，沒有增資源、縮短訓練或搬動村民／模型。19:20:19 的原失敗 Farm `(-228,-156)`，相鄰 Barracks `(-204,-156)`，以真村民正常施工完工 **PASS**。同段完成磨坊、伐木場、採礦營地、兵營、房屋及正常訓練到 16 村民；前置／高時代拒絕不扣款與食物單次採集／攜帶／交貨亦有局部 PASS。

完整測試在 **19:24:30 木材首次正值／交貨逾時 FAIL，已用 383.9 秒、Age 1**。沒有 `[RTS_ADVANCED COMPLETE]`，未到四時代、18 建築、11 科技與 10 單位完整驗收。新版來源見 [advanced-integrated-source.json](../tests/advanced-integrated-source.json)，原始記錄在 [latest-integrated-studio-results.txt](../tests/latest-integrated-studio-results.txt) 的 `19:18-19:46 Advanced original farm and wood path evidence` 段。17:57 舊 FAIL 與 19:20 原情境新 PASS 均保留，不把木材 FAIL 合併為完整發展通過。

失敗後的唯讀診斷：16 個資源抵達候選×AgentRadius 2／3／4，共 **48 次 PathStatus.Success**；從真村民位置出發的首個執行段仍撞 `Workspace.Buildings.House.Footprint`，不能接受引擎 Success 旗標當可行走證據。19:45:37–19:45:38，從原 liveStart `(-253.7949,-173.5756)` 做安全前綴診斷；`(0,0,-8)` 前綴及 radius 3／4 的後續整段 Blockcast 顯示 clear，反向 `(0,0,8)` 與 `(8,0,8)` 被 House 阻擋。這是實際引擎路徑／碰撞查詢，沒有移動模型或回寫 HP／資源；當時尚未驗到伺服器新前綴修法讓村民完成真行走／交貨；20:39另局正常Advanced的新證據見下文。

## 19:57–19:58：新控制初始化 regression，前綴尚未到 runtime

19:57 將 R09＋bounded安全8stud前綴＋完整avatar readiness 凍結，來源見 [escape-readiness-source.json](../tests/escape-readiness-source.json)，CLI／Luau／Rojo通過。新桌面Play仍在19:58:36的 `MatchReportFlowTests` Lobby初始化逾時 **FAIL，未到第一局**，不把CLI或25helper mocks升為引擎就緒。真實avatar／Humanoid／HRP已完整，actual控制initial=true、Enabled=false，cached lobbyReady未完成提交；事件提交後defer＋Character屬性變更觀察的最小修正中。初始 `Player:Move` nocharacter警告仍有。

原始失敗與actual probe診斷已存 [latest-escape-readiness-results.txt](../tests/latest-escape-readiness-results.txt)。這局沒有到木材field，安全前綴尚未實際驗到村民行走／交貨。19:13舊快照Flow與19:20原Farm的PASS保留，不能當作新凍結來源已通過；修正後須重新fresh Flow／Advanced。

## 20:17–20:39：真四資源與正常完整發展 COMPLETE

20:16 凍結 [advanced-escape-source.json](../tests/advanced-escape-source.json)，GameServer／PathRules／PlayerInput 與 20:10 事件修正版保持相同 runtime hash；新加入的 CombatFlowTests 未被這局呼叫。新的單人桌面 Play 於20:17:00以正常大廳開局並執行 `AdvancedTests.RunDevelopment({deadlineSeconds=1800})`，沒有增資源、搬模型、縮計時或管理後門。

20:22–20:23，food／wood／gold／stone 的真節點減少、攜帶上限與村民正常交貨均 PASS；木材包含樹 `(-304,9,-120)`，20:22:30 正常交貨增加庫存，後續雙刃斧後木材也再次交貨。20:39:11取得 **238 項 COMPLETE，耗時1331.3秒（約22.2分鐘）**：4時代、18種建築、11科技、10種單位均以正常成本／施工／研究／訓練計時完成；市集正常比例買賣及黃金不足拒絕不扣資源亦 PASS。新村民／軍隊繼承科技數值、實際採集量與新農田容量有對應實例觀察。完整原始行見 [latest-advanced-escape-results.txt](../tests/latest-advanced-escape-results.txt)。

這次解決了19:24正常木材返場情境，歷史FAIL仍保留。log明確印出 G07 **UNVERIFIED**：箭羽實際射程、拇指環實際攻擊間隔、研究建築被真攻擊摧毀的取消／重研、傷害及三勝利仍須另開雙方對戰。封倉庫自動回退、耗盡／交貨點被毀、修復、滿人口／堵出口與被毀佇列也沒有因238項正常發展而通過；DeliveryFallbackTests目前僅編譯、尚待freshPlay。不把單人22.2分鐘當成四方200人口、五次重開或真機性能證據。
## R09、控制生命週期與其餘門檻

19:58初始化FAIL後，加入事件提交後defer與Character屬性觀察的最小修正；20:10:46新快照見 [escape-events-source.json](../tests/escape-events-source.json)，PlayerInput SHA256 `BA23D6FE0598823D18445CFE7FD240D261D91E03ACA937E2A53B96FEF6D729CE`。20:11:39–20:12:19新桌面Flow取得 **92事實／控制＋54正式UI COMPLETE，40.4秒**。兩次正常Restart的actual控制初值還原通過，沒有觀察到新的noHumanoid warning；初始20:10:47仍有一次noCharacter warning，不宣稱官方初始化警告全部消失。

新局House為 `(-184,-184)`、TC為 `(-216,-216)`，food為 `(-152,-104)`，worker交貨前位置 `(-196.6179,-188.2441)`；真房屋完工／村民訓練／食物交貨、獨立餘額與精確UI再次通過。完整log見 [latest-escape-events-results.txt](../tests/latest-escape-events-results.txt)。這是新快照的非戰鬥兩局證據；當時木材safe prefix尚未驗到field行走／交貨，後續20:39另局Advanced才取得正常發展COMPLETE。19:58失敗與19:24木材FAIL均保留，不把20:12Flow當成四資源或全部發展通過。

R09 主目錄已在 19:10 接入 FFA／兩陣營 1v1／四陣營 2v2／所有真人合作 AI；伺服器發布人齊後的 preview 與 actual TeamId。盟友不可攻擊、各自控制／資源，自然淘汰凍結個人記錄並等待隊伍結果；最後盟友獲勝仍為 win，投降／退出個人維持 loss。GUI 支援 pending／final，最終報告優先 Defeated，模式／設定列手機可捲動。

20:10:46 的 [latest-cli-results.txt](../tests/latest-cli-results.txt) 記錄Team2132、team/report lifecycle33、client35、Report92、Path4837及Luau／Rojo，檔尾對應 [escape-events-source.json](../tests/escape-events-source.json)；皆為純規則／CLI。19:13與20:12單人FFA不能證明隊伍功能。已新增 `Shared/TeamUITests.lua` 唯讀正式PlayerGui／屬性，以及 `Shared/TeamMatchTests.lua` 正常Lobby／Command多客戶階段。真正雙／四客戶改mode取消ready、preview→actual、友軍攻擊／跨控制拒絕不扣款、投降／退出／Restart仍待；天然淘汰pending→盟友win必須正常戰鬥另驗。退出者私人JSON未在Player卸載前送達時須標觀測限制，不把快取或缺失資料當其loss／持久戰績通過。

19:48完整character／Humanoid／HRP／RootPart與runtime／teardown兩個observer來源SHA256為 `FF0187FAA6819449715F73FF0EC833A7C3FCC1021CC576C8BC31712978301424`；編譯及25 mock通過卻於19:58 freshPlay初始化FAIL。20:10事件修正版兩次Restart已取得上述actual還原PASS；任意avatar替換／teardown與多客戶仍待，初始官方預設模組noCharacter警告仍未宣告解決。

剩餘門檻見 [ROADMAP.md](ROADMAP.md)：G02 原模型 runtime、G05 新雙客戶／房主生命週期、G06 正常發展之外的耗盡／封倉庫／被毀／取消／人口／出口條件、G07 真戰鬥／三勝利／戰損、R09 真隊伍與 pending/final、G10 正式存檔／Dashboard、G11 四方 200 人口／五次重開／真機效能、G12 準確發布資料。全程維持原創 RTS 測試版描述與文明／造型公平付費邊界。

## 原檔保存與發布狀態

兩份本地原模型檔 [Original-before-20260930.rbxl](../build/Original-before-20260930.rbxl) 與 [Original-models-20260930-1924.rbxl](../build/Original-models-20260930-1924.rbxl) 的大小皆為 **181,144 bytes**、SHA256 皆為 `7FC5659DF805BB00667D2540D804272E42EC6F26CDFF8D538FA92FAFC5BD7F17`；本次唯讀核對一致。這支持副本保存。20:35–20:36，本地 [Original-validation副本](../build/Original-validation-20260930-1954.rbxl) Rojo同步前後 protected metadata multiset 為7,616筆、零差異，見 [before](../tests/original-models-before-sync-results.txt)、[after](../tests/original-models-after-sync-results.txt) 及 [comparison](../tests/original-models-sync-comparison.json)。這是Edit保留檢查；相機／地形／mapped roots排除，Source長度＋rolling fingerprints不是cryptographic byte proof，尚未證明Play的遮擋／碰撞／出口。protected inventory只含Workspace.Model／SpawnLocation／matchpart1，沒有RS Buildings／Resource真模板與其指令碼，不能宣稱真模板分支或全DataModel無script已驗。matchpart1為原先未錨定Part，Play位移須區分自然重力。

根代理已告知使用者，Studio 的 Download 副本意外觸發自動雲端草稿保存；沒有執行 Publish。後續不得自動公開發布或覆寫本地原 place；新的構建仍輸出到 build。

根代理已新增本機幾何繪製的原創堡壘鍛火徽記：`assets/publishing/forge-badge-512.png`、`forge-badge-128.png`、`forge-badge.svg`，生成腳本 `scripts/create-store-icon.py` 與索引 [STORE-LISTING.zh-TW.md](STORE-LISTING.zh-TW.md)。圖示尚未上傳，實際對局縮圖仍待；這項素材不構成 G12 整體通過。
