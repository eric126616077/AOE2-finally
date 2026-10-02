# Studio 驗收紀錄與重現步驟

## 最新整合驗收：截至20:39，Flow修正版與正常Advanced發展COMPLETE

本節時間為 2026-09-30 Asia/Taipei；原始 log 的 11:xxZ 對應本地 19:xx。真正執行證據見 [latest-integrated-studio-results.txt](latest-integrated-studio-results.txt)，19:13 快照見 [integrated-path-team-source.json](integrated-path-team-source.json)，19:18 Advanced 快照見 [advanced-integrated-source.json](advanced-integrated-source.json)。後來修改 source 不會更新已執行的 Play VM。

| 時間／版本界線 | 實際結果 | 範圍與限制 |
| --- | --- | --- |
| 19:10，R09 與第一輪全路徑修正已整合 | FFA／Teams／CoopAI、pending／final 覆盤與普通遠端多客戶測試已在主來源。 | 這是實作狀態；下列單人 FFA Play 不證明真雙／四客戶或同盟功能。 |
| 19:13:36–19:14:16，新桌面單人無模型 Play | **MatchReportFlow 92 事實／控制＋54 正式 UI COMPLETE，40.5 秒**；兩局正常投降、Restart 與清除。 | 免費開局／投降清場排除、真 House 完工／正常訓練村民、真食物交貨、獨立餘額、精確正式 Text、存活文字、44 px／捲動幾何與 UI 防穿透。沒有真戰鬥／退款／隊伍／手機覆盤。House／食物精確座標本局未另印。 |
| 同局初始與 Restart | 實際控制探針正常還原初值，但仍有官方 `Player:Move` no character／no humanoid 警告。 | 探針通過不等於警告消失；後續 19:48 角色就緒修正須 fresh Play。 |
| 19:18:06–19:24:30，新 Advanced | 原 Farm `(-228,-156)`，相鄰 Barracks `(-204,-156)`，19:20:19 以真村民正常施工 **PASS**；部分建築、16 村民與食物交貨亦 PASS。 | **木材首次正值／交貨 383.9 秒逾時 FAIL，Age 1**。未取得 Advanced COMPLETE，沒有四時代／18 建築／11 科技／10 單位全通過。 |
| 19:33–19:45，失敗後唯讀尋路／碰撞診斷 | 16 抵達候選×radius 2／3／4＝**48 次 PathStatus.Success**，首個真正執行段都撞 House；19:45 原位置的安全 8 studs 前綴與 radius 3／4 後續路徑全段 clear。 | 是真正引擎查詢，沒有搬動模型／改資源。不是伺服器新前綴修正已讓村民完成真行走／交貨；仍待 fresh Play。 |
| 19:48，PlayerInput 兩個角色就緒 observer 已整合 | 完整 Character／Humanoid／HRP／RootPart 條件；單檔編譯與隔離 actual helper **25 mock PASS**。 | 當時尚未新 Play；19:58 後來取得初始化 FAIL，20:12 為後續事件修正版。此版 SHA256 `FF0187FAA6819449715F73FF0EC833A7C3FCC1021CC576C8BC31712978301424`。 |
| 19:57–19:58，新 safePrefix／readiness Play | Teams＋安全前綴＋完整 avatar readiness 的 CLI／Rojo通過；**19:58:36 MatchReportFlow Lobby INIT FAIL，未到第一局**。 | actual avatar／Humanoid／HRP已完整，但 cached lobbyReady未完成提交、initial=true而Enabled=false。25mock沒有抓到真事件生命週期問題。初始nocharacter warning仍在；最小事件提交／defer修正中，path runtime未到field。 |
| 20:10／20:11:39–20:12:19，事件提交修正版新桌面Play | **Flow92事實／控制＋54正式UI COMPLETE，40.4秒**；兩次正常Restart的actual控制還原PASS，未觀察到新的noHumanoid warning。 | 新House(-184,-184)／TC(-216,-216)、food(-152,-104)真交貨與獨立餘額、精確Text再次通過。初始20:10:47仍一次noCharacter；當時木材／Advanced待另一freshPlay，後續20:39另局COMPLETE。 |
| 20:17:00–20:39:11，新單人正常Advanced Play | **238項發展COMPLETE，1331.3秒（約22.2分鐘）**；真四資源交貨、4時代、18建築、11科技、10單位、市集買賣／不足拒絕。 | [advanced-escape-source.json](advanced-escape-source.json)、[latest-advanced-escape-results.txt](latest-advanced-escape-results.txt)。木材樹(-304,9,-120)正常交貨；真射程／攻擊間隔、研究被毀、傷害／三勝利log明示UNVERIFIED。 |
| 20:35–20:36，原模型副本Edit同步 | protected metadata multiset **7,616筆／0差異**。 | [comparison](original-models-sync-comparison.json) 與 [before](original-models-before-sync-results.txt)／[after](original-models-after-sync-results.txt)。無RS真模板，Play待；這不是模板／碰撞／出口引擎通過。 |

失敗證據見 [latest-escape-readiness-results.txt](latest-escape-readiness-results.txt)、[escape-readiness-source.json](escape-readiness-source.json)，修正版見 [latest-escape-events-results.txt](latest-escape-events-results.txt)、[escape-events-source.json](escape-events-source.json)。保留各版本PASS／FAIL，不延伸為其他版本或四資源通過。根代理目前可正常操作Studio；上述皆為桌面／模擬器或單人結果。最新R09多客戶、原模型runtime、真戰鬥、發展異常回退／取消／被毀、真機與正式雲端仍待；20:39正常發展另有238項COMPLETE，不把全部G06打勾。實際多指不能用純手勢測試代替。下面保留較早快照與重現步驟。

## 歷史持續驗收：17:20–17:58，局部通過並保留當時施工 FAIL

本節時間皆為 2026-09-30 Asia/Taipei。原始 log 的 09:xxZ 對應本地 17:xx。證據見 [latest-continuation-results.txt](latest-continuation-results.txt)，版本敘述見 [持續驗收紀錄](../docs/CONTINUATION-2026-09-30.md)。這些是真正 Studio Play，仍不是實際手機或首次玩家研究。

| 時間／正在執行的版本 | 結果 | 範圍與限制 |
| --- | --- | --- |
| 17:20–17:21，新的單人無模型 XR 橫向 Play | Release **19**、Touch **33**、Construction **36** COMPLETE。 | 完整複製、文明、雲端關閉、實際 UI、安全區／尺寸及正常施工。早於本輪新增原生控制政策、UI 命中探針與伺服器生命週期修正。 |
| 同局實際介面與 XR 直向 | 點選村民、主城、訓練村民並觀察伺服器人口及指引完成；直向資源／指引／小地圖／操作列／生產卡可見，選單可操作。 | 是裝置模擬器與合成滑鼠的操作觀察，沒有直向獨立 COMPLETE、實際多指或手機效能證據。 |
| 17:23 原生觸控觀察 | Playing 的 `TouchControlsEnabled=true`，但 `TouchGui.Enabled=false`，搖桿／跳躍的祖先完整可見性均為 false。 | 不能寫成原生控制持續顯示的證據；之後改為 RTS 明確停用以防階段切換問題。 |
| 17:39–17:40，新的 XR 橫向 Play | Release **19**、Touch **38**、Construction **36** COMPLETE。 | 新增正式 UI 命中探針與原生控制檢查；操作列／提示中心阻擋，操作列上鄰地面可點。雙指部分仍為純規則模擬。 |
| 17:40–17:48 相機觀察 | 首次聚焦／置中 2 PASS 後未見 15 studs 平移而 FAIL；17:47–17:48 正常選單啟用邊緣移動，主城→鼠標邊緣平移→同主城 **TouchFocus 5 COMPLETE**。 | 17:44 的真實 W 事件 `processed=false`、無 TextBox／模態；不足以推論預設控制吞鍵。通過的是邊緣平移與重複聚焦，沒有持續鍵盤／多指平移通過聲明。 |
| 17:53／17:58，新桌面 Play | Lobby **Touch 21**／Playing **Touch 26 COMPLETE**。 | `RTSControlProbe` 讀真正 PlayerInput closure，確認大廳還原初值、RTS 全部預設角色控制停用。測試不 require 另一份 PlayerModule／GUI。 |
| 17:53–17:57，Advanced 正常發展 | 有前置／時代不足不扣款，以及磨坊、伐木場、採礦營地、兵營真施工 PASS；232.1 秒後 **Farm FAIL**。 | 17:58 唯讀工地為 `(-228,0.6,-156)`、進度 0、BuilderCount 0。當時來源見 [advanced-play-source.json](advanced-play-source.json)。沒有四時代／18 建築／11 科技／10 單位 COMPLETE。 |

Computer Use 已於 17:20 恢復；較早的 `failed to activate captured window` 不再是目前持續阻擋。共用 Studio 須協調視窗與來源快照。不要因其他聊天使用相同目錄，就把其結果自動當成本輪所有功能已驗收。

17:57 FAIL 之後新增共用 `ApproachRules`／工作抵達回退，以及 R06 伺服器／GUI 覆盤與正常流程測試。當時 18:12 CLI 有工作抵達 **411**、報告 **80** 與既有純檢查、Luau／Rojo；GUI **22** 為代理回報的 CLI，TeamRules **2,083** 尚未掛接。這些是當時狀態；後來 R09 已整合，19:13 Flow 與 19:20 原位置 Farm 的新 Play 證據見上節。[latest-cli-results.txt](latest-cli-results.txt) 現已更新為較新 CLI 快照，不能把現存檔內容當作當時未變動檔案。

## 較早文明／介面／觸控快照：16:40–16:41

2026-09-30 16:40–16:41（Asia/Taipei），在 Rojo 同步的 `build/AOE2.rbxlx` 開新的單人、無外部模型 Play，使用 **iPhone XR 橫向 Studio 裝置模擬器**，取得 Release 19／Touch 33／Construction 36 COMPLETE。完整原始標記見 [latest-release-touch-results.txt](latest-release-touch-results.txt)。16:30 較早桌面快照另有 Release 18／Touch 20／Construction 36 COMPLETE。

Release 檢查文明非法值、名稱、修改後取消準備、局內鎖定、實例身份複製、Studio 停用 DataStore／Analytics、實際練習按鈕、無角色相機與教學事實歸零。Touch 檢查實際 PlayerGui 九個快捷鍵、手機 44 px 尺寸與 UIScale=1、安全區／相鄰地面、地面射線座標，以及手勢純規則。Construction 使用正常遠端驗證施工、停止／繼續、協作與完工才生效。**不是手指／雙指實際操作、真實手機效能或完整對戰通過。**

16:36 短橫向教學可見斷言曾失敗；加入可展開的 44 px `GuidanceHint` 後重開 Play，上述整合重跑通過。FAIL 一併保存。其後的短橫向條件、防提示按鈕穿透，以及複查發現的相機重複聚焦、桌面下緣捲動與文明偏好載入修正，須另開新 Play 驗收；CLI 回歸不能把這些自動升為引擎通過。

這個較早工作階段在測試後遇到 `failed to activate captured window`，依技能停止 UI 輸入，當時未追加直向或新版雙人／進階 COMPLETE。17:20 之後已恢復並取得上節的新證據；保留工具故障的歷史，不把它判定為遊戲失敗或目前持續阻擋。

重現需 **新的單人 Lobby**，在客戶端 Command Bar 明確呼叫：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.ReleaseTests).Run()
    require(game.ReplicatedStorage.Shared.ConstructionTests).Run()
end)
```

先選裝置模擬器，再重開 Play，避免啟動時 TouchEnabled／介面配置不同。相同已開始的測試局不要重跑 ReleaseTests；它要求新大廳。可另呼叫唯讀的 `TouchTests.Run()`，但仍需實際操作選取、採集、拖移施工、雙指相機、彈窗防穿透與直向旋轉。下面保留其他時間的歷史證據與各流程尚未覆蓋範圍。

## 其他已取得的歷史引擎證據（2026-09-30）

以下結果來自真正的 Roblox Studio Play、雙人客戶端、實際 RemoteEvent 與 Studio log。CLI 編譯或純邏輯測試不列入引擎通過數；舊版測試結果也不延伸到新增功能。

| 範圍 | 已取得的結果 | 證據與限制 |
| --- | --- | --- |
| 新城堡大廳 | **12 項 COMPLETE**，2026-09-30 16:04–16:05（Asia/Taipei），新的無模型 Play。 | [latest-lobby-construction-results.txt](latest-lobby-construction-results.txt)。涵蓋廣場複製、角色與一般相機、傳送門集合、第一位集合者成為房主、未準備／缺人拒絕、修改配置重置準備、舊配置與無效設定拒絕、同伺服器 RTS 切換。單一客戶端證據不能證明兩名真人集合。 |
| 新村民施工 | **36 項 COMPLETE**，同一個新的無模型 Play。 | [latest-lobby-construction-results.txt](latest-lobby-construction-results.txt)。涵蓋未選／軍人／混選不建造不扣款、重複村民去重、遠距工地、到場才施工、停止與繼續、多人協作，以及房屋人口、兵營訓練、農田食物在完工後啟用。 |
| 較早基礎流程 | 35 項通過，2026-09-30 15:07（Asia/Taipei）。 | [latest-studio-results.txt](latest-studio-results.txt) 有 `[RTS_TEST COMPLETE]`。涵蓋當時的地面／HUD 複製、開局、建屋施工與扣款、非法建造拒絕、訓練、採集交貨、停止、投降、結果畫面與返回大廳。新大廳與新版完整基礎流程未重跑。 |
| 較早真正雙人流程 | 29 個 PASS，2026-09-30 15:25–15:31（Asia/Taipei）。 | [latest-multiplayer-results.txt](latest-multiplayer-results.txt) 記錄兩名真實玩家、房主權限、跨端建築／訓練複製、跨玩家指令拒絕、實際玩家退出後清理、勝利與房主轉移。當時沒有本輪的傳送門集合與全部準備規則，不能當作新雙人大廳驗收。 |
| 較早手動操作 | 大型 1536 地圖與三個 AI 的對局，曾觀察採集、建造、訓練、小地圖操作與 AI 軍隊出現。 | 屬於實際操作觀察，尚未完成長局 AI、滿人口與效能壓力驗收。 |
| 較早 Progression 測試 | **完整流程未驗證。** | 首次執行在開局旗標尚未完全複製時失敗；修正條件等待並編譯通過後，未取得新版 `[RTS_PROGRESSION COMPLETE]`。17:53 新 Advanced 另有 Farm FAIL，不合併為 Progression 通過。 |

基礎測試當時的 AI 人口斷言為 `>=4`，四人可全部來自起始三村民與斥候，不能據此證明 AI 已額外訓練村民。人口 `>=5` 仍可能包含預留的訓練佇列，也不足以證明新村民已生成。新版 `StudioTests` 已改為核對 `Workspace.Units` 中 `OwnerId` 屬於該 AI 且 `UnitType=villager` 的真正實例數，要求超過 `Config.Settings.startingVillagers`；這項嚴格斷言尚未重新完成實機驗證。保留 35 項通過紀錄的原始範圍，不把它當成最新版全部通過。

進階測試已等待 `Playing`、`Sandbox=true`、`MatchSize=768`、`AICount=0`，以及初始玩家與重要單位數值完整複製。較早的重跑曾因原生輸入工具反覆回報 `failed to activate captured window` 而停止；保留這次未完成紀錄，不能視為進階遊戲流程通過，也不能據此判定後續時代或科技流程失敗。本輪大廳與施工通過沒有重跑完整進階流程。

較早的 35／29 項結果之後，另調整單位動畫晚到部件追蹤、未知障礙預覽、指令冷卻與人口容量，以及進階測試複製等待與農田容量斷言。本輪新增大廳和施工的 12／36 項實機通過只支持新測試的範圍，不能延伸為上述全部系統或整體遊戲驗收。

最後追加的 GUI 配置版本傳遞與準備狀態顯示仍待新的 Play 驗證；本輪新大廳的兩名真人集合、兩端配置同步、加入／退出重置準備及房主轉移也尚未重跑。使用者原模型的 place 未在本輪重新驗收；無模型 Play 通過不代表所有模板與未知障礙都已驗證。

之後在 16:08 起另啟動真正兩人 Server & Clients，已觀察並記錄兩人入隊、房主雙人配置及準備名單同步，見 [雙人大廳部分紀錄](latest-lobby-multiplayer-partial.txt)。首次因操作第二視窗延誤而入隊等候逾時；重試同一設定時，測試未等待新的配置 revision，準備請求被拒絕。`MultiplayerTests` 已補配置 revision 與準備 ACK 等待，尚未重跑，沒有取得新版完整 HOST READY／OWNERSHIP COMPLETE。其後工作目錄另出現文明、觸控及教學的並行變更，電腦操作工具也回報已有活動請求；停止本輪視窗操作以免互相干擾。上述 12／36 項只證明當時測試版本，最新整合版本須重新驗收。

20:10:46 的 [latest-cli-results.txt](latest-cli-results.txt) 記錄核心 205,531、對局 167、大廳 43、Team 2,132、team/report lifecycle 33、client team 35、文明／商店 67、檔案／分析 mock 80、報告 92、AI 12、伺服器空間／生產 25,084、交戰 51、近戰 5,156、工作抵達 411、Path 4,837、採集 5,840、施工 36、觸控／相機 66、feedback 70、教學與地圖 13,667 等檢查；Luau與 `rojo build` 通過。檔尾保存 [escape-events-source.json](escape-events-source.json) 版本；只支持該CLI快照，不用這些數字替代Play或後續修改。CLI／mock與Studio數量分開。

## 共通前置條件

1. 使用最新 `build/AOE2.rbxlx`，或確認 Rojo 已同步最新原始碼。無模型建置與保留使用者模板的原 place 要分別驗證。
2. 更新遊戲腳本後停止目前測試，重新開 Play。已執行 Script 不保證因 Rojo 熱同步而重新初始化。
3. 所有下列呼叫都放在 **客戶端** Command Bar；若在伺服器執行，測試會拒絕。`require` 本身不開始測試，必須明確呼叫方法。
4. 測試會扣除資源、建立建築、生成單位、投降或重開對局，請使用新的測試工作階段。
5. Command Bar 的 ModuleScript 快取與遊戲 LocalScript 狀態分離。HUD 檢查讀取真正的 `PlayerGui`；預設控制讀實際 `RTSControlProbe` closure。不能 require 另一份 GUI／PlayerModule 重造狀態再當作正在運作的控制器。
6. 保留 Output／log 的 PASS、FAIL、COMPLETE 與腳本錯誤。只有對應 COMPLETE 與完整記錄能支持該流程通過；畫面看起來正常不能替代遠端權限、經濟或勝負驗證。

## 城堡大廳與村民施工：本輪重現

開新的單人 Play，使用無模型建置，保持城堡廣場。在客戶端 Command Bar 執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.LobbyTests).Run()
end)
```

測試會把測試角色移到實際傳送門位置，透過正常遠端加入集合，並確認第一位集合者取得房主權限。它先驗證未準備不能開始，設定需兩人的戰局後確認單人不能開局，再改回一人，檢查修改配置取消準備、拒絕舊配置的準備請求及無效設定。最後確認一人全部準備後可以開始 Small／0 AI／Rich 沙盒，角色被移除且相機切換為 RTS。集合只是同一伺服器內的開局流程，目前不使用跨 place 傳送。

看到 `[LOBBY_TEST COMPLETE] 12 checks` 且對局已開始後，在同一個客戶端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.ConstructionTests).Run()
end)
```

施工測試需要新的單人豐富資源沙盒，會建立房屋、兵營、農田並訓練步兵。它檢查沒有選村民、只選軍隊或村民與軍隊混選會被拒絕且不扣款；重複村民不重算。指定村民能前往遠於 80 studs 的工地，只有實際到場才增加進度，停止後不自行施工，再右鍵工地可繼續；多名村民可協作。房屋完成才增加人口，未完工兵營拒絕訓練且不扣款，未完工農田沒有可採集食物。成功結尾為 `[RTS_CONSTRUCTION COMPLETE] 36 項施工引擎檢查通過`。

這兩個測試只在明確呼叫時執行，沒有直接修改伺服器餘額或加速施工。上述本輪紀錄已取得對應 COMPLETE；最後的 GUI 顯示變更與新版雙人集合仍依前述限制另行驗證。

## 單人基礎流程：新版尚待完整重跑

開新的單人 Play，保持大廳，客戶端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.StudioTests).Run()
end)
```

此流程先透過新大廳的集合、設定與準備，再開始小地圖、豐富資源、一個簡單 AI 的對局。測試建造房屋、扣款、重疊與不合法座標拒絕、村民訓練、尋路、有限資源採集、攜帶與交貨、停止；最後投降並返回城堡廣場，確認 AI 狀態清除。

成功結尾為 `[RTS_TEST COMPLETE]`。需重新執行最新版以確認 AI 真正新增村民實例的嚴格條件。這個測試沒有涵蓋 18 種建築、四個時代、全部科技或完整軍事對抗。

## 真正雙人流程：新大廳尚待重跑

使用 Studio 的 Server & Clients 測試啟動 **兩個玩家客戶端**，兩人都保持新的城堡廣場。先選一個客戶端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.MultiplayerTests).RunHost()
end)
```

`RunHost()` 會將此玩家加入實際傳送門，成為第一位集合的房主，設定 2 名真人、Small／0 AI／Rich，然後等待第二位玩家。看到 `[RTS_MULTI WAIT]` 後，在第二個客戶端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.MultiplayerTests).JoinLobby()
end)
```

第二端進入傳送門並提出準備；房主流程等兩人到齊後也提出準備，兩人皆準備才開始。可在介面或各端的 `LobbyQueued`／`LobbyReady` 屬性確認狀態；若其間修改配置、加入或退出集合，必須按最新配置重新準備。第一位集合者才是房主，不以玩家加入伺服器的先後判定。真人與 AI 合計最多四方，AI 不補指定真人名額。

在房主開始前，可由第二端呼叫 `RunOwnership()` 確認非房主不能自行開局。開始後 `RunHost()` 等待兩方市鎮中心、三村民與斥候複製，並正常建屋、訓練村民。看到 `[RTS_MULTI HOST READY]` 後，第二端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.MultiplayerTests).RunOwnership()
end)
```

此階段檢查房屋同步、不能移動／停止對方村民、不能使用對方建築訓練或研究、非有限座標與突發請求不扣款、不生成非法單位。完成時印出 `[RTS_MULTI OWNERSHIP COMPLETE]`。

在打算保留的非房主客戶端掛上退出觀察器：

```lua
require(game.ReplicatedStorage.Shared.MultiplayerTests).ObserveCleanupClient()
```

看到 `[RTS_MULTI CLEANUP ARMED]` 後，退出另一位房主玩家的客戶端，保留伺服器與觀察者客戶端。不要直接結束整個 Server & Clients 工作階段，否則無法觀察真正的 `PlayerRemoving` 清理。應印出 `[RTS_MULTI CLEANUP COMPLETE]`，並看到退出玩家的單位與建築消失、存留玩家勝利、房主權限轉移。

較早的 29 個 PASS 涵蓋當時的跨端建造／訓練、所有權及實際退出清理，尚未使用上述新傳送門與準備流程。本輪沒有新的雙人 COMPLETE；需確認兩端同步配置、加入／退出取消所有人的準備、房主轉移、指定人數不足拒絕開始與全部準備後開始。雙方長時間採集與戰鬥、全部單位傷害同步、重連與觀戰者邊界情況仍待驗收。

## 單人進階發展流程：尚待完整重跑

開新的單人 Play 大廳；或先完成對局並返回大廳。不要在兩個活躍玩家或正在進行的一般對局中呼叫：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.ProgressionTests).Run()
end)
```

此測試透過新大廳的集合、配置、準備與正常遠端請求開始 Small／0 AI／Rich 沙盒，整體最多五分鐘，不改伺服器資源、不加速研究、沒有管理後門。完整範圍包含：

- 初始市鎮中心不能代替時代前置；兩座同類磨坊不能代替兩種不同的黑暗時代建築。
- 織布機真實研究時間、村民生命／護甲加成、斥候不受影響、重複研究不再次扣款。
- 磨坊、伐木場、兵營、農田、市集、兵工廠的正常施工；步兵生產與農田容量。
- 封建時代正確扣除 500 食物並完成 35 秒研究。
- 市集買賣、鍛造與手推車、對應單位數值、黃金不足時拒絕購買且資源不變。

若時間或資源有限，測試可能印出 `[RTS_PROGRESSION SKIP]`，僅完成前置／織布機／封建／市集範圍。此時 COMPLETE 會標明「核心進階範圍」，不能視為鍛造、手推車或其餘科技也通過。未取得新版 COMPLETE 前，以上均保持未驗證。

## 完整發展 Advanced：20:39正常發展238項COMPLETE，歷史FAIL保留

此流程與較早 `ProgressionTests` 分開。新的單人 CLIENT Play 保持大廳，不與其他模組或真實對局並行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.AdvancedTests).RunDevelopment({deadlineSeconds=1800})
end)
```

預設總期限 1,200 秒，可設定 `deadlineSeconds=600` 至 `1800`。流程只使用正常 Rich 開局、遠端命令、真實村民採集／交貨與伺服器計時，不直接補餘額或加速；目標為四時代、18 建築、11 科技、10 種單位及對應前置／扣款／效果。

17:53–17:57 實際執行在黑暗時代停於農田：正常扣 60 木材建立工地，但相鄰兵營情境下無到場工人，`ConstructionProgress=0`／`BuilderCount=0`，總時間 232.1 秒後 FAIL。磨坊、伐木場、採礦營地、兵營與部分不扣款拒絕的 PASS 僅屬該局已走到的範圍。後續任何時代／科技／軍隊段落均未因這次執行而通過。

共用工作抵達位置與失敗側回退後，19:18 新 Play 在 **19:20:19 原 Farm `(-228,-156)`／相鄰 Barracks `(-204,-156)` 正常完工 PASS**。沒有搬遠工地、增資源或改計時。該局完成部分建築、正常訓練到 16 村民與食物交貨，仍在 19:24:30 木材首次正值／交貨逾時，總時間 **383.9 秒、Age 1 FAIL**。證據與 source 見 [latest-integrated-studio-results.txt](latest-integrated-studio-results.txt)、[advanced-integrated-source.json](advanced-integrated-source.json)。

失敗後唯讀診斷取得 48 次 PathStatus.Success，但首個執行段都撞 House。19:45 從原 liveStart 查得安全 8 studs 前綴及 radius 3／4 的完整 clear 後續路徑；這不是村民實際返場交貨。當時新伺服器前綴修法需 fresh Play 重現木材與完整 Advanced；20:39另局已取得下列正常發展證據。若再失敗，保存當局來源 hash、工地／工人座標、Order、路徑與進度；不清場後強制印 COMPLETE。只有全程出現 `[RTS_ADVANCED COMPLETE]` 才支持對應正常發展範圍。真正戰鬥、研究建築被攻擊摧毀與三勝利仍另驗。

20:17:00–20:39:11使用上面的1800秒期限命令，新的單人正常Play取得 **238項COMPLETE，實際1331.3秒、約22.2分鐘**；預設1200秒小於這次實測時間，不把此局稱為20分鐘內完成。真food／wood／gold／stone節點減少、攜帶上限與交貨PASS；wood樹(-304,9,-120)於20:22:30正常交貨，後續經濟科技後亦再交貨。4時代、18建築、11科技、10種單位、正常市集買賣與黃金不足拒絕不扣資源均有完整原始行，見 [latest-advanced-escape-results.txt](latest-advanced-escape-results.txt)、[advanced-escape-source.json](advanced-escape-source.json)。

log末段明示 `[RTS_ADVANCED UNVERIFIED]`：箭羽實際射程、拇指環實際攻擊間隔、研究建築被真攻擊摧毀取消／重研、傷害及三勝利須真雙方對戰。封倉庫自動回退、耗盡／交貨點被毀、修復、取消／被毀佇列、滿人口／堵出口仍另驗；DeliveryFallbackTests目前僅編譯，不因正常交貨成功而通過此異常情境。上述22.2分鐘單人發展不代替G11四方200人口／五次重開。
## 覆盤正常兩局流程：19:13與20:12 COMPLETE，真戰鬥與隊伍另驗

使用新的單人 CLIENT Play 大廳，執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.MatchReportFlowTests).Run()
end)
```

預設總期限 360 秒，可用 `Run({deadlineSeconds=420})`，合法範圍為 300–420 秒。19:13:36–19:14:16 新桌面單人 Play 已取得 **92 事實／控制＋54 正式 UI COMPLETE，40.5 秒**；[latest-integrated-studio-results.txt](latest-integrated-studio-results.txt) 與 [integrated-path-team-source.json](integrated-path-team-source.json) 保存來源與實際結果。18:33 44 px FAIL、修正後第二局返場 130 秒 FAIL 亦保留在 [latest-match-report-results.txt](latest-match-report-results.txt)，不把早期失敗抹成通過。

19:58最新avatar就緒版在Lobby初始化FAIL，尚未開第一局；20:10事件提交修正版的新Play於20:11:39–20:12:19重取 **92＋54 COMPLETE、40.4秒**，兩次Restart actual還原PASS。精確House(-184,-184)／TC(-216,-216)、food(-152,-104)的真食物交貨成功；Source／log見 [escape-events-source.json](escape-events-source.json)、[latest-escape-events-results.txt](latest-escape-events-results.txt)。初始仍一次noCharacterwarning，沒有觀察到兩次Restart的noHumanoid；木材安全前綴與完整發展沒有因這局Flow通過；後續20:39另局Advanced才取得正常發展證據。

第一局透過既有 `LobbyTests.Start` 的正常集合／準備啟動 Rich／Small／0 AI，直接正常投降。等待 Ended、Defeated 與 finished JSON，檢查真正 Snapshot schema、戰敗與有限存活時間，所有交貨／支出／完工／訓練／傷害／kill／loss 必須為零。初始免費市鎮中心、三村民與斥候，以及投降清場不計為生產或戰損。唯讀 `MatchReportTests.Run()` 再核對實際 PlayerGui 的文字與數值，不 require GUI 或 PlayerModule 造共享狀態。

正常 Restart 後等待大廳、`MatchReportJSON=nil`，呼叫唯讀 `CheckClear()` 核對數據與標記已清空；從實際 `RTSControlProbe` 確認大廳控制還原原初值。

第二局以相同正式設定開局，真村民建立／完工一棟房屋，正常訓練一名新村民；比對實際完工建築及新增 `Workspace.Units` 實例。只派一名村民採最近食物，觀察攜帶、資源堆減少與一筆真交貨，停止所有工人並等待複製穩定。用獨立餘額核對食物淨支出 50、木材 25，交貨等於 `DeliveredResources` 與資源守恆；再正常投降核對報告，無真戰鬥則戰鬥計數全零。第二局 ID 須不同，最後正常重開清除。

只有全部事實、UI 與還原檢查完成才印 `[MATCH_REPORT_FLOW COMPLETE]`。失敗會保留測試局，僅移除觀察連線，不自動重開或強制 pass。此流程不驗市場／高時代／真傷害，也不證明觀戰按鈕、選單重開按鈕、手動捲動或真觸控手勢已操作成功；這些須另外實際操作驗收。

18:50–18:51 曾以真正桌面介面走Menu→投降→結果捲動→Watch→Menu重開報告→Restart；當時畫面交貨為0，背包10沒有算成已交貨。這是較早快照的人工操作證據，不取代19:13／20:12 Flow或最新手機／隊伍覆盤驗收。20:12正常兩次Restart控制已通過，仍不能宣告初始noCharacter或任意avatar生命週期全部解決。

## R09 真雙／四客戶驗收：來源已整合、引擎仍待

使用新的 Server & Clients，所有人正常走入傳送門集合，不能修改 Player／Workspace 屬性、HP、資源或位置以製造結果。`Shared/TeamMatchTests.lua` 的 require 不自動操作；各 CLIENT 的快取獨立。模式驗收順序如下，每階段先完成再前進，並保存各端來源／log：

1. **兩客戶 Teams／2 真人＋0 AI（1v1）**：兩人正常集合，房主 `Configure("Teams",2,0)`、各端 `Ready()`。非房主 `RejectNonHostChange()`；房主 `ChangeMode("FFA")` 驗全 ready 取消，再切 Teams／重新 ready。各端 `CapturePreview()` 與唯讀 `TeamUITests.RunLobby()`；非房主先用 `task.spawn` 等 `ObserveStart()`，房主才 `Start()`。兩端 `CheckAssignment()` 驗 preview→actual，不用視窗順序推隊伍。正常 Surrender 及 `ObserveFinal()` 驗對方勝利，房主 Restart／各端 `ObserveRestart()` 驗清除與配置。
2. **兩客戶 CoopAI／2 真人＋1 AI**：新的正常對局，重做 preview／assignment；有真人盟友才可 `RunFriendlyFire()`，驗正常移動／停止先有效，再驗友軍攻擊及跨擁有權指令拒絕、不扣資源。正常選取盟友後以 `TeamUITests.CheckSelectedAlly(actualModel)` 核對友方不可攻擊 UI。1v1 沒有盟友，不能把略過當 friendly fire 通過。另局用真正關閉客戶端及其他端 `ObserveLeave(victimId)` 驗退出清理；離開前私人 JSON 未複製時須保留觀測限制，不假判其覆盤已通過。
3. **四客戶 Teams／4 真人＋0 AI（2v2）**：各端保存人齊後的 preview，開局後讀真正 TeamId 分 A1／A2／B1／B2；每端各自驗控制／資源和友軍拒絕。A1 正常投降為個人 loss、A2 繼續；再由 B1／B2 正常投降，A2 最終 win，A1 仍 loss。`ObserveFinal(expectedOutcome,seconds,expectedWinnerTeam)` 必須指定實際預期勝方，不能只看 finished。最後普通 Restart，各端驗 report／TeamId／Forfeited 清除。這不等於自然淘汰 pending 驗收。
4. **自然淘汰→盟友逆轉**：另局正常經濟、訓練與戰鬥消滅 A1；唯讀 `MatchReportTests.CheckPending()` 保存已凍結的個人數值／存活時間。A2 以真戰鬥獲胜後 `ObservePendingFinal("win",180)` 核對 A1 最終 win、先前計數不變與正式 UI；不能用 Surrender、直接減 HP 或改結果替代自然淘汰。

上述是待執行順序，尚無最新雙／四客戶 COMPLETE。Team 2,132、lifecycle 33、client 35 與 Report 92 為 CLI。手機大廳 settings 捲動、44 px、隊伍預覽和 pending／final 結果仍須最新裝置／真機操作；勝利音效亦須按真人結果驗證。

## 尚待驗收的必要項目

| 項目 | 需確認的引擎行為 |
| --- | --- |
| 新集合大廳雙人流程 | 兩名真人的配置同步、只有第一位集合者可設定與開局、加入／退出重置全部準備、舊配置準備拒絕、房主離開轉移、缺人或未全部準備拒絕。單人 12 項與歷史雙人 29 個 PASS 不取代此驗收。 |
| 所有建築與模板／G02 | 20:39無外部模板Advanced的18種正常建築已PASS。原模型副本Edit同步前後7,616筆protected metadata零差異；副本無RS真模板。仍須原模型Play／未知大模型遮擋、初始出生、碰撞、出口及真模板／Clone失敗回退，不把Edit保留當成runtime通過。 |
| 四時代與全部科技 | 20:39正常四時代／11科技成本、前置、計時、既有及新生數值效果PASS。真射程／攻擊間隔、研究互斥、建築被真攻擊摧毀後取消／重研仍待。 |
| 經濟與施工的剩餘範圍／G06 | 19:20原相鄰FarmPASS、19:24木材383.9秒FAIL保留；20:39四資源真交貨與完整正常發展238項COMPLETE。另驗封倉庫自動回退／耗盡／交貨點被毀、修復成本、中斷／工人損失、建築被毀佇列／研究、滿人口與堵出口。DeliveryFallbackTests僅編譯未Play。 |
| 軍隊與同步 | 20:39十種正常訓練／己方實例生成PASS。仍須十種真戰鬥、索敵／反擊、護甲／剋制／範圍、城堡／塔、不同體型尋路、堵出口與多人傷害同步。 |
| 勝利規則 | 戰鬥消滅全部單位與建築的征服判定、真正摧毀起始市鎮中心的主城決戰、奇觀完整 180 秒守成與被摧毀／多奇觀計時。已有投降與玩家離開結束雙人局的證據，不能代替全部勝利條件。 |
| 戰後覆盤／G07 | 19:13及20:12各自正常兩局Flow92／正式UI54、免費開局／投降清場排除與Restart清除已通過。真HP差、攻擊kill/loss、退款、自然敗方凍結、隊伍pending／final仍待，純規則不能代替。 |
| 同盟與朋友合作／R09 | 19:10 已整合 GameServer／大廳／GUI 與正常遠端 TeamMatchTests；真正雙／四客戶 preview→assignment、改 mode 取消 ready、友軍拒絕、同隊勝負、投降／退出、天然淘汰 pending→final 與重開仍待。 |
| AI 長局 | 三種難度實際採集／交貨、生產與升級到四時代、資源枯竭後恢復、進攻與防禦、奇觀模式、玩家離開後持續運行。 |
| 效能／G11 | 大型地圖四方長局、每方 200 人口、資源節點大量耗盡與五次重開的幀率、尋路併發、記憶體與遠端頻率。22.2分鐘單人Advanced及兩局短Flow不代替四方每方200人口或五次重開壓力。 |
| 村民自動工作 | 新增 `Shared/AutoWorkTests.lua`（新單人 Play 執行 `require(game.ReplicatedStorage.Shared.AutoWorkTests).Run()`）：停止的村民保持待命、空選取顯示建築分類、空選取建造只扣款一次並自動派工、完工接續、選單開關。2026-10-02 單人新 Play：R1 15 項 COMPLETE 但探針發現採集半徑 80 小於資源離基地距離（主城旁村民不會自動採集），改為 260 後 R2 18 項 COMPLETE（含閒置村民自動開始工作、完工接續），見 [紀錄](auto-work-studio-20261002.txt)。仍需觀察多名閒置村民分工、農田自動重新播種、觸控、雙人各自開關互不影響與長局效能。其他手動控制整合測試開頭會關閉自動工作。 |
| 僧侶招降與治療 | 新增 `Shared/MonkTests.lua`：Studio「伺服器與客戶端」2 名玩家，客戶端 1 執行 `require(game.ReplicatedStorage.Shared.MonkTests).Run({peer=true})`，看到「等待第二客戶端」後客戶端 2 執行 `.Peer()`（被動、關閉自動工作，派一名村民到主城射程外）。2026-10-02 前幾輪找到並修正三個實際問題：`UnitRules.takeAction` 白名單缺 convert／heal 導致永不判定；移動時重設招降進度使採集村民無法被招降；治療停步點落在伐木場內使僧侶原地不動。其餘失敗為測試路線設計，已改用伺服器待命狀態與距離判定。最終新 Play **36 項 COMPLETE（428.9 秒）**，見 [紀錄](monk-studio-20261002.txt)。單人對 Easy AI 模式會在約 5 分鐘被 Rich AI 突襲，不適合此測試。未驗收：招降 AI 軍隊、多僧侶、觸控操作與長局平衡。 |
| 介面與輸入 | 已有XR橫向命中／安全區、直向可見操作、桌面真控制停用／還原、邊緣平移重聚焦、19:13及20:12桌面覆盤Text／幾何與兩次Restart actual還原。19:58初始化FAIL保留；初始noCharacter、任意avatar替換／teardown、最新手機／隊伍配置、實際多指、持續鍵盤、全部快捷鍵／編隊、聊天輸入、失焦與真手機仍待。 |
| 正式客戶端 | Roblox 正式客戶端的複製與操作、網路延遲、晚加入觀戰、離開／房主轉移與重開。 |
| 正式雲端／G10 | 偏好／戰績讀寫與失敗、離開／關閉、跨服併發、Dashboard／Analytics；Studio 關閉 API 與 mock 不證明正式服務通過。 |
| 發布內容／G12 | 原創幾何堡壘鍛火圖示與介紹草稿已製作，尚未上傳；實際對局縮圖、裝置支援與測試版限制仍待審查。Download 副本意外自動保存雲端草稿已披露，未執行 Publish；不自動發布。 |

原始程式與 place 備份位置見 [README.md](../README.md)。不要自動發布體驗或覆蓋原 place；新建置輸出到 `build`。2026-09-29 舊版天空／串流修正屬於歷史紀錄，不能為本輪未完成的進階驗收背書。

## 2026-10-01 隨機資源佈局

後續依「更多、更密集」改為 760／1280／2200 節點與每方 48／40 棵開局森林。13:31–13:34 新無模型副本 Play 完成 Small／Small／Medium／Large 四局：種子／位置不同、森林密度與樹冠相接、完整節點及每節點可見外觀、四種資源與一個林內木材節點各真採集並交回 10、四次返回大廳清除資源。1,000 小圖種子 CLI 壓測零失敗。固定快照、SHA256、原始 log 與限制見 [密集資源紀錄](../docs/DENSE-RESOURCES-2026-10-01.md)。不延伸為所有林內節點、所有模板 descendants、手機／多人與長局效能通過。下面保留較早稀疏版本的歷史結果。

地圖改為各出生區獨立隨機群落，正常每局使用新種子並保留相當的資源配額。12:38–12:40 固定快照新 CLIENT Play 已取得 Small／Small／Medium／Large 四局 `MAP_TEST COMPLETE`：420／420／680／1100 個節點，同尺寸位置與種子不同，四種資源各有真採集與交回 10 單位的證據，四次正常重開清除生成資源。來源 hash、固定快照、CLI、Studio log 與驗證限制見 [隨機佈局紀錄](../docs/RESOURCE-LAYOUT-2026-10-01.md)。沒有把本輪單人地圖結果算作雙人／離開、每個林內節點、所有建築或 UI 並行修改的通過證據。

## 村民建造三頁驗收

選取己方村民後先顯示「經濟／軍事／防禦」三個分類按鈕，不先列出建築；點選分類才顯示該類建築，並提供「返回分類」。目前與較早時代可使用，下一時代灰化並標示需求，更後時代不生成指令。防禦頁也收納修道院、大學與世界奇觀。資源不足保留項目與紅色價格，不能啟動建造預覽。手機頁內可橫向捲動，分類數固定為三頁。

在新 Studio CLIENT Play 戰局呼叫 `require(game.ReplicatedStorage.Shared.BuildMenuTests).Run()`，會暫時改動本機 Age、資源與選取以驗證實際 PlayerGui，結束後還原。這只驗證渲染，不代表伺服器升級或資源扣款通過。`HUDTests.Run()` 同時驗證 UI 命中、安全區域與生產介面。

專用 `villager-pages-validation.project.json` 額外映射 `tests/villager-build-harness.client.lua`；Play 後會透過正常大廳指令開始單人新局、執行兩套介面測試。若在 Play 前明確設定 Workspace 的 `BuildMenuInteractiveTests=true`，接著會等待實際 UI 點擊灰色射箭場、兵營與石牆。此測試腳本不在 `default.project.json` 的映射內。石牆預覽驗收暫設本機封建時代，未向伺服器提交建造或升級。

先前三頁版本的桌面 Studio 固定快照 `build/AOE2-villager-pages-validation-r2-20261001.rbxlx` 通過 45 項 HUD 與 707 項三頁／四時代渲染檢查，記錄於 `tests/villager-build-pages-desktop-studio-20261001.txt`。這份結果早於「先選三個分類按鈕」的流程修正，不能作為新流程的 Studio 通過證據。相關測試已更新為驗證分類入口、返回與時代更新保留分類；最新流程仍待新 CLIENT Play 驗證。手機模擬、真觸控，以及互動點擊／伺服器建造未在本輪完成。

分類入口修正後，完整 `scripts/verify.ps1` 通過，包含 Luau 語法、198 項建造分類／時代規則與預設 Rojo 建置；記錄於 `tests/villager-category-chooser-cli-20261001.txt`。更新的測試腳本語法與專用快照 `build/AOE2-villager-category-chooser-20261001.rbxlx` 也已建置通過。Studio 已讓給並行地圖驗收，因此此快照尚未執行 Play，不能宣稱新入口的畫面、點擊或手機實機驗證通過。

## 駐紮（2026-10-02）

市鎮中心 15、瞭望塔 5（不收騎兵）、城堡 20；攻城器械不能進入。駐紮只能用專用指令：「駐紮 [G]」按鈕／G 鍵後點建築（觸控相同）、或 Alt+右鍵；一般右鍵不會駐紮（村民與軍事單位相同，右鍵維持施工／修復／交貨）。選取建築後按「全部離開」放出駐軍。城堡在射程內沒有敵方單位時會射擊敵方建築（`attacksBuildings`），瞭望塔與市鎮中心只打單位。駐軍計入人口、每秒回復 1 生命；每位村民／遠程多射 1 支箭、步兵每 2 位多射 1 支，上限 10／5／15。建築被摧毀或拆除時駐軍出現在原占地。

CLI：`tests/garrison.spec.lua` 93 項純規則通過，Luau 語法（含 -O0 的 200 local 上限）與 Rojo 建置通過。

Studio：`garrison-validation.project.json` 額外映射 `tests/garrison-studio.server.lua`（Studio 專用輔助遠端：生成指定兵種、設定生命、移除）與 `tests/garrison-studio.client.lua`。客戶端以正常大廳指令開 Small／1 Easy AI 局，駐紮、離開與拆除都經正式 `Command` 遠端。2026-10-02 21:12 本機測試伺服器＋1 客戶端 **32 項 PASS、0 FAIL**，見 [紀錄](garrison-studio-20261002.txt)：右鍵駐紮（3 村民＋1 斥候）、模型消失、人口不變、箭數 3→6（斥候不加箭、步兵兩位一支）、面板「駐軍 4 / 15」與「全部離開」、攻城衝車被拒、齊射 7 支且敵方騎士每輪 −28（7×4，逐箭扣護甲）、客戶端畫出 7 支箭、駐紮 6 秒回復 20→25、全部離開（占地外、不重疊、兵種保留）、容量 15（第 16 個留在外面並停止）、拆除市鎮中心後 16 個單位出現在原占地且可再下令。第一輪 5 項 FAIL 是測試把開局斥候算成村民，修正預期後重跑。

這輪因另一工作階段占用電腦控制，改用命令列 `RobloxStudioBeta.exe -task StartServer … -numTestServerPlayersUponStartup 1` 啟動（伺服器固定讀 `%LOCALAPPDATA%\Roblox\server.rbxl`，測試前後已備份還原），沒有人工看畫面。未驗收：實際滑鼠右鍵／Alt+右鍵與觸控點擊、按鈕實際點擊、箭矢與面板的目視外觀、建築被敵軍打爆的放出路徑（與拆除共用 `Garrison.release`，但未實跑）、瞭望塔與城堡（含塔拒收騎兵）、離開時的集合點、雙人同步。AI 不會主動駐紮。

補充（同日）：選取自己的單位時指令面板有「駐紮 [G]」按鈕，按下或按 G 進入選目標模式，左鍵／觸控點自己可駐紮的建築送出，右鍵或 Esc 取消，點錯目標保留模式；選取有駐軍的建築時 G 等同「全部離開」。刪除按鈕改名：單位顯示「死亡」、建築顯示「拆除」，確認視窗同步。CLI：`tests/cursor.spec.lua` 65 項、Luau 語法與 Rojo 建置通過。未驗收：這兩項都沒有在 Studio Play 實測（按鈕位置與是否遮住說明文字、G 鍵、觸控版按鈕、游標外觀）。

Studio 實測（同日 22:40，computer-use 操作，`build/AOE2-garrison-check.rbxlx` 以當下磁碟原始碼重建，單人、無電腦對手）：選取斥候騎兵與 3 位村民時底列「駐紮 [G]／陣形 [F]／停止 [X]」不重疊、說明文字未被遮住；按 G 進入選目標模式（提示訊息、標題「選擇駐紮建築」、指到市鎮中心為選取游標、指到地面為禁止游標），再按 G 取消；G 後左鍵市鎮中心，斥候進駐（駐軍 1 / 15）；選市鎮中心按 G，駐軍離開（0 / 15）；一般右鍵市鎮中心不駐紮（仍 0 / 15）；滑鼠點「駐紮 [G]」按鈕後點市鎮中心，3 位村民進駐（駐軍 3 / 15 · 多射 3 箭）；單位顯示「死亡 [Del]」、建築顯示「拆除 [Del]」，確認視窗為「死亡：斥候騎兵」與「確認死亡」，文字未截斷。截圖：`tests/garrison-button-studio-20261002-1` 至 `-7`。未驗證：Alt+右鍵（computer-use 送出的 Alt 修飾鍵沒有讓單位進駐，無法分辨是工具限制還是功能問題，需人工按一次）；混選單位與建築的「死亡／拆除」文字（正常操作選不到這種組合）；確認視窗的 Esc 取消（這次用「保留」按鈕關閉，Esc 按鍵未生效，可能被 Studio 攔截）；觸控版按鈕；瞭望塔與城堡；雙人同步。

既定設計（使用者 2026-10-02 最終決定，經統籌工作階段轉達）：(1) 任何單位右鍵己方可駐紮建築都不直接駐紮，只能用專用指令（駐紮按鈕／G、Alt+右鍵、觸控駐紮模式）；先前「右鍵即駐紮」與觸控「移動模式點建築即駐紮」已移除，下面較早紀錄裡的「右鍵駐紮」是舊行為。(2) 城堡自動攻擊敵方建築：單位優先，射程內沒有敵方單位才打建築，沿用同一條射擊／`AttackVolley` 路徑，駐軍多箭同樣適用。這兩項改動後 `scripts/verify.ps1` 全部通過（`server_rules.spec` 新增設定與評分檢查），**尚未在 Studio 重跑**；`tests/garrison-studio.client.lua` 已改為驗證「右鍵不駐紮、Garrison 指令才駐紮」並新增第 13 段（城堡射擊敵方房屋、單位出現時改打單位、單位離開後回頭打建築）。

瞭望塔／城堡／被敵軍摧毀（同日 21:44–21:57，三輪，`tests/run-garrison-studio.sh` 以命令列啟動）：測試腳本新增第 10–12 段，`RTSBattleProbe` 新增 Studio 專用 `build` 動作直接放已完工建築。已實跑通過：瞭望塔容量 5（第 6 位弓箭手留在外面）、拒收騎士並通知、空塔每次 1 支箭（125→119）、駐 5 位弓箭手齊射 6 支（125→89）且客戶端畫出 6 支；10 台敵方衝車摧毀瞭望塔後 5 位駐軍出現在原位置、人口不變、未被淘汰並自動迎戰；空城堡會攻擊（攻擊 14、射程 75，125→113）、駐 15 個單位（14 個加箭）時齊射 15 支、拒收攻城衝車、全部離開後都在占地外。紀錄：[r2](garrison-studio-20261002-r2.txt)、[r3](garrison-studio-20261002-r3.txt)、[r4](garrison-studio-20261002-r4.txt)。

這三輪找到並修正：瞭望塔被摧毀時第 5 位駐軍疊在中心（間距 1.41）——`Garrison.release` 改為占地排滿後往外三圈找空位並檢查靜態障礙，r3／r4 間距 5.00。另把 `Garrison.notice` 改為依訊息分開節流（不同拒絕原因不互相蓋掉），此項改後尚未重跑。

仍為 FAIL、原因未證實：城堡 16 位弓箭手＋1 位騎士只進 15 個（r2、r4），兩位弓箭手帶著駐紮指令停在生成點不動、沒有通知；推測是測試把單位生在樹／礦的碰撞體上（probe 生成不檢查占位），測試輔助已改為避開障礙並記錄擋住的物件，待重跑確認。r3 城堡 0 個進入、單位在牆外待命，原因不明。這四項 FAIL（進入數、箭數 15、齊射 16、16 支箭特效）不能算通過。未驗收：城堡被摧毀、離開時的集合點、雙人同步、實際滑鼠與觸控。

最終兩輪（同日 22:15–22:24，r5、r6，磁碟最新原始碼重建，含新手教程與熱鍵改動，開局流程未受影響）：**各 64 項 PASS、0 FAIL**，伺服器與客戶端 log 沒有遊戲腳本錯誤（只有 Studio 內建 ChatScript 的 SetCore 訊息）。紀錄：[r5](garrison-studio-20261002-r5.txt)、[r6](garrison-studio-20261002-r6.txt)。
- 上面的城堡 FAIL 已證實是測試問題：r5 記錄到 3 位弓箭手的生成點壓在 `Resources.Gold.Footprint`／`Tree.Footprint` 上，改到旁邊空位後 16 位弓箭手＋騎士 17 個全進，箭數 15、齊射 16 支（敵方騎士一輪陣亡）、客戶端 16 支箭。r3「0 個進入」未再出現，當時沒有留下原因，無法確認是否同一問題。
- 右鍵不駐紮：右鍵市鎮中心 2.5 秒後 4 個開局單位仍在外面、沒有駐紮指令；改送 `Garrison` 指令後 4 個全進。
- 城堡攻擊建築：射程內沒有敵方單位時射擊敵方房屋（550→536，每箭 14）、瞄準點在該建築；敵方騎士進入射程後 5 秒內房屋不再掉血、騎士 113→77；騎士移除後回頭射擊房屋（536→522）。
- 其餘同前：市鎮中心、瞭望塔（含被衝車摧毀後放出駐軍，間距 5.00）、通知依訊息分開節流後「不能進入」與「建築已滿」都有送達。

仍未驗收：城堡被摧毀時放出駐軍、離開時前往集合點、雙人同步、實際滑鼠（含 Alt+右鍵）、「駐紮 [G]」按鈕與 G 鍵的實際點按、觸控、箭矢與面板的目視外觀、駐滿城堡對建築的多箭傷害（只測了空城堡 1 支箭）。AI 不會主動駐紮。

熱鍵設定（2026-10-02，僅命令列）：戰局選單新增「熱鍵設定」，12 個指令可改綁（`Shared/HotkeyRules.lua`，存在本機玩家屬性 `Hotkeys`，不跨場次保存）；相機 WASD／方向鍵、Home、數字編隊、Esc 與組合鍵固定。`tests/hotkey.spec.lua` 85 項通過，`scripts/verify.ps1` 全部通過並完成 Rojo 建置。Studio Play 未驗證，待測：開啟面板後地面與 HUD 不可點、相機不移動；改綁後新鍵生效而舊鍵失效；綁到已使用的按鍵會互換；保留鍵被拒絕並顯示原因；Esc 先取消擷取、再關閉面板；「恢復預設」；HUD 按鈕與說明列的按鍵字樣同步；短橫向畫面可捲動到最後一列；觸控版面不受影響。

## 新手教程（2026-10-02，尚未在 Studio 驗收）

CLI 已通過：`tests/tutorial.spec.lua`（11 步順序、不可跳關、略過、進度、首次判定、按鍵代換）與 `tests/profile.spec.lua` 新增的 `tutorialDone` 檢查（單向、冪等、載入前完成、Studio 不寫雲端、讀取失敗不寫入）。

待新的 Play 工作階段驗證：
- 大廳出現 `TutorialInvite`；「稍後再說」後左上角出現 `ReopenTutorialButton`；矮畫面時歡迎卡與匹配點清單不重疊。
- 「開始新手教程」：角色被放進空匹配點、自動準備並開局（單人、Small、Rich）；`TutorialMatch` 屬性為 true，回大廳後清除。
- 局內 `TutorialGuidance`（278×234）不遮住指令列與通知；11 步依序推進，鏡頭步驟在開局 1.5 秒後才計算；改鍵後文字跟著變。
- 完成後 `TutorialDone` 變 true，同一工作階段下一局不再自動顯示；選單「重新查看新手指引」仍可開啟。
- 觸控版面（104 px 高）只顯示標題、進度與做法；短橫向仍由 `GuidanceHint` 展開。
- 雙人：另一位玩家在其他匹配點集合時，教程局的開始與結束不影響對方的房間設定。

熱鍵跨場次保存（2026-10-02，僅命令列）：上段「不跨場次保存」已不適用。改鍵後客戶端送 `Hotkeys` 指令，伺服器重新解析成合法綁定後寫入個人檔案（`ProfileRules` 新欄位 `hotkeys`，`ProfileStore:SetHotkeys` 15 秒合併寫入、離開時立即存檔）；載入後以玩家屬性 `SavedHotkeys` 回傳，客戶端套用。`tests/profile.spec.lua` 新增檢查與 `scripts/verify.ps1` 全部通過。Studio 停用雲端，所以 Studio Play 內不會保存；未驗證：正式伺服器上改鍵、離開、重新進入後沿用，以及載入失敗時不覆寫雲端。舊版伺服器讀到含 `hotkeys` 的檔案會視為不支援而不載入，需全部伺服器更新後才一致。

## 建築受損外觀（2026-10-03，單人桌面 Play 已驗證部分）

完工建築依生命比例換外觀：≤ 1/2 為「受損」（約三成屋頂與少量裝飾脫落、其餘部件燻黑、周圍 3 塊瓦礫、1 處火與煙），≤ 1/3 為「殘破」（約六成屋頂脫落、更深的燻黑、6 塊瓦礫與 2 根焦梁、3 處火加光源）。修復須超過門檻 4% 才恢復上一階，滿血完全還原。整排放置的石牆只有瓦礫與燻黑、不起火；城門與一般建築相同。全部在客戶端 `BuildingVisuals.client.lua`，規則在 `Shared/DamageVisualRules.lua`；伺服器的 HP、碰撞、占地都不變，匯入的 Studio 模型只改本機透明度與顏色、不刪除或替換。上限：40 個受損疊加物件、24 處火，超過時只保留破損與燻黑。

CLI 已通過：`tests/damage_visuals.spec.lua` 3719 項（門檻、修復緩衝、脫落比例單調、預算），`scripts/verify.ps1` 全部通過並完成 Rojo 建置。

Studio（2026-10-03 00:08–00:23，三輪，`tests/run-damage-visuals-studio.sh` 以命令列啟動本機伺服器＋1 客戶端，映射 `damage-visuals-validation.project.json`）：`tests/damage-visuals.client.lua` 以正常大廳指令開局（1 真人＋1 簡單電腦、Small），伺服器輔助直接設定建築 HP，再讀探針與實際部件。最後一輪 **92 項 PASS、0 FAIL**，Studio log 沒有遊戲腳本錯誤（只有 Studio 自己的未登入與 StyleRule 訊息）。紀錄：[r1](damage-visuals-studio-20261003-r1.txt)（91／1，唯一 FAIL 是測試以名稱比對疊加物件、誤算到另一棟同名房屋，已改用探針）、[r2](damage-visuals-studio-20261003-r2.txt)（92／0）、[r3](damage-visuals-studio-20261003.txt)（92／0，火與煙放大後）。

已驗證：
- 房屋、市鎮中心、城堡、石牆、城門、農田各跑 60%→50%→33%→36%→45%→52%→55%→100%：階段 0→1→2→2→1→1→0→0，滿血後每個部件的顏色與 LocalTransparencyModifier 與原本完全相同，疊加物件歸零。
- 脫落部件數（受損／殘破／可見部件）：房屋與各建築都隨階段增加；石牆 0 處火、其餘受損 1 處、殘破 3 處；殘破房屋 1 個火光、2 根焦梁、6 塊瓦礫。
- 玩家色部件、旗桿、城門門扇在兩個階段都沒有被隱藏。
- 施工中的房屋（正式 Build 指令，生命 15%）不顯示受損外觀，完工滿血為完好。
- 受損農田由伺服器換階段（部件全部重建）後仍是殘破並重新套用，滿血後還原。
- 「減少動態效果」開啟時火為 0、破損與 8 個瓦礫／焦梁保留，關閉後火恢復 3 處。
- 真實戰鬥：4 台電腦攻城衝車把房屋打到倒塌，階段依序 0,1,2，倒塌後原位置沒有殘留。
- 投降→對局結束→回大廳後 `RTSDamageEffects` 為空、疊加與火的計數為 0。
- 畫面（截圖）：火、煙、火光、焦梁、缺屋頂在預設鏡頭距離清楚可見，未遮住上方生命條。[受損房屋](damage-visuals-studio-house-damaged-20261003.jpg)、[殘破房屋與受損市鎮中心](damage-visuals-studio-house-ruined-20261003.jpg)、[殘破城堡](damage-visuals-studio-castle-ruined-20261003.jpg)、[殘破石牆與城門](damage-visuals-studio-wall-gate-ruined-20261003.jpg)。

這幾輪找到並修正：第一版的火與煙在預設鏡頭下幾乎看不到（r1、r2 截圖只見火光與淡煙），已把火焰尺寸、數量與不透明度調高、煙調深，並把火源抬到脫落部件上方 1 stud；r3 截圖確認。

觀感備註：房屋屋頂部件少，殘破時屋頂整片消失、只剩屋脊與牆體；城堡殘破時塔頂圓錐部分消失。是否可接受待使用者看截圖決定。

未驗證：
- 建築 HP 多數由測試輔助直接設定；只有一棟房屋走真實戰鬥，實際「村民修復」流程沒有跑（修復只是 HP 上升，階段邏輯相同）。
- 城門升降動畫在受損狀態下的外觀、選取外框與受損外觀同時出現的畫面。
- 玩家離開時的清理（只驗了回大廳）、雙人同步是否看到相同脫落部件、匯入模型（沒有 `ConstructionStage` 屬性）的高度判斷。
- 同時 40 棟以上受損建築的幀率與火數上限、觸控裝置。
- 真實滑鼠／鍵盤操作：Studio 視窗拿不到前景，鏡頭只由測試腳本移動。

## 環境動態（2026-10-02，單人桌面 Play 已驗證部分）

`Ambience.client.lua`／`AmbienceRules.lua` 加入純客戶端的樹冠與灌木擺動、草叢與野花、旗幟、風車、煙囪煙與飛鳥；`UnitMotion.client.lua` 加入閒置單位重心晃動。皆為本地外觀，零件不參與查詢與碰撞。Studio 下可用 `PlayerScripts.RTSAmbienceProbe:Invoke()` 讀取數量與每幀寫入數。

三輪新的單人 Play（Small／0 AI／Rich，以 `LobbyTests.Start` 開局），原始輸出見 [ambience-studio-20261002.txt](ambience-studio-20261002.txt)：

| 時間／快照 | 結果 |
| --- | --- |
| 21:33–21:36 `AOE2-ambience-r2` | 樹冠 3 秒位移 0.48 studs、旗幟與飛鳥有位移；ReducedMotion 開啟後 trees／fastActors／flocks／writes 皆為 0 且旗幟、單位靜止，關閉後恢復。**發現草叢只長在畫面左側**（上限依掃描順序填滿）與閒置晃動僅 0.002 studs。本輪數值只留在當時 Output，未存檔。 |
| 21:38–21:40 `AOE2-ambience-r3` | 草叢改為 rank 門檻後左右 554／438；風車 2 秒位移 4.7 studs；房屋完工後煙囪 smoke=1；閒置斥候頭部 0.37 studs；59.7 fps、每幀 433–465 次寫入。 |
| 22:29–22:30 `AOE2-ambience-r4` | 旗幟加大後：掛旗 4 秒內偏轉 7.6°／16°、旗桿旗 34°；停工村民頭部 0.22–0.38 studs；定案草色（SmoothPlastic）在預設高度與拉近皆可辨識，左右 556／456、tufts 506／640；59.75 fps、每幀 444 次寫入。截圖 [預設高度](ambience-studio-r4-default-20261002.jpg)、[拉近](ambience-studio-r4-zoomed-20261002.jpg)。 |

三輪的 Studio log 都沒有遊戲腳本錯誤。未驗證：莓果叢擺動與匯入模型的樹、Medium／Large 地圖與大量單位下的效能、有陰影樹冠在低階裝置的成本、手機／觸控、雙人。位移數值是腳本量測，不代表觀感已由真人確認。

## 框選（2026-10-02，單人桌面 Play 已驗證部分）

`RTSClient.client.lua` 的框選改為「框碰到單位畫面輪廓就選中」（`Shared/SelectionRules.lua`），拖曳時以框線預覽會被選到的單位；選取外框（Highlight）只給前 24 個，所有被選單位另有地面光圈（`workspace.RTSSelectionRings`）。

三輪新的單人 Play（Medium／1 真人／0 AI／標準經濟，走正式大廳流程），第三輪原始輸出見 [selection-studio-20261002.txt](selection-studio-20261002.txt)。

| 時間／快照 | 結果 |
| --- | --- |
| 21:25–21:28 `AOE2-selection-20261002` | 掃到村民邊緣可選中、預覽框與光圈顯示；從地圖拖到底部 HUD 放開仍選中。**只掃到騎兵馬腿未選中**（輪廓只用 Root 尺寸，比模型矮）。 |
| 21:29–21:30 `AOE2-selection-20261002-r2` | 輪廓改用模型實際大小並計入鏡頭傾斜深度後：只掃馬腿、只掃頭皆選中；手滑約 17 px 點主城仍選到主城；最遠視角一次框 3 個單位。 |
| 22:32–22:38 `AOE2-selection-20261002-r3`（含駐紮、熱鍵、城牆拖曳、教程卡的最新來源） | 以 `RTSBattleProbe` 生成 40 個步兵／弓兵。一次框 42 個單位：`highlights=24 rings=42`。幀時間：閒置 mean 20.7 ms／p95 23.4／worst 29.9；拖曳 11 秒 mean 20.8 ms／p95 23.7／worst 63.4（單一尖峰，區間含放開瞬間）。一般框選（13／20／22 個）、點選單一步兵、點選主城、從地圖拖到建造面板放開（41 個）、拖到左上教程卡上放開（42 個）皆正常。 |

截圖：[大軍拖曳預覽](selection-studio-20261002-army-preview.jpg)、[42 個單位已選](selection-studio-20261002-army-selected.jpg)、[HUD 上放開](selection-studio-20261002-hud-release.jpg)、[教程卡上放開](selection-studio-20261002-tutorial-card.jpg)。

三輪的 Studio log 都沒有遊戲腳本錯誤。教程卡（HUD 左上）會擋住從卡片上起始的拖曳與點擊（HUD 命中區的既有行為）；選取框畫在卡片底下，在卡片上放開不影響結果。

未驗證：
- **Shift 加選（框選與點選）**：computer-use 無法在滑鼠放開時維持 Shift。log 顯示 LeftShift 按下事件有送達，但放開滑鼠時 `IsKeyDown(LeftShift)=false`，選取被取代而非累加；這是工具時序限制，不是通過也不是已確認的遊戲缺陷，需真人按住 Shift 測。
- 63 ms 尖峰是否來自放開瞬間一次建立 42 個光圈／24 個 Highlight（未單獨量測）；200 個單位以上的拖曳效能。
- 雙人同步（框選為純客戶端，未開第二客戶端）、觸控裝置、匯入模型的單位輪廓。

### 新手教程 Studio 實測（2026-10-02 22:54–23:01，computer-use，`build/AOE2-tutorial.rbxlx` 以當下磁碟原始碼重建，單人桌面）

已觀察（截圖 `tests/tutorial-studio-20261002-1` 至 `-6.jpg`，輸出 [tutorial-studio-20261002.txt](tutorial-studio-20261002.txt)）：
- 大廳頂部出現「歡迎，新領主！」歡迎卡，三個按鈕不重疊，下方匹配點清單未被遮住。
- 「稍後再說」關閉歡迎卡，左上角出現「新手教程」按鈕；點它可重新開啟歡迎卡。
- 「開始新手教程」約 10 秒內直接進入對局：伺服器輸出 `對局開始：1 名玩家、0 個電腦陣營，地圖 Small`，資源 1200／1200／800／600（Rich），沒有手動設定房間。
- 局內教程卡在 HUD 左上，未遮住資源列、指令列、通知橫幅與小地圖；顯示章節、進度條、做法、原因與「略過這一步」。
- 步驟推進：按住 D 平移鏡頭後 1→2；按 V 選取村民後 2→3；自動工作交回木材後 3→4；放置房屋並完工後 4→5（人口上限 5→10）。
- 「略過這一步」連按可由 5 走到 11，再按一次顯示「新手教程完成 ✓」與完成說明，按鈕變為「關閉」。文字中的按鍵（B、V、G）正確代換。
- log 沒有遊戲腳本錯誤；只有 Studio 內建的雲端驗證、頭像資源與 StartPage 訊息。

實測後的修改（**未再進 Studio 驗證**，只通過 `scripts/verify.ps1`）：每一步至少停留 5 秒才推進，因為自動工作讓「採集並交回資源」在玩家讀到之前就完成了。

未驗證：完成後 `TutorialDone` 為 true 且回大廳不再自動跳歡迎卡；回大廳後 `TutorialMatch` 清除；第 5–11 步以真實操作（非略過）推進；選單「重新查看新手指引」；觸控與矮畫面版面；雙人。原因：Studio 視窗持續失去前景（桌面殼層搶走焦點），每次用 `open_application` 取回都會多開一個 Studio 起始頁，因此中止。熱鍵設定面板的代驗同樣沒有進行。

### 新手教程補驗（2026-10-02 23:04–23:07，同一個 `AOE2-tutorial.rbxlx` Play 工作階段續測）

- 選單「重新查看新手指引」：教程卡重新出現並回到 1 / 11。
- 完成教程後投降、按「返回戰局設定」回大廳：歡迎卡標題變成「新手教程」且沒有「跳過教程」按鈕，表示 `TutorialDone` 已為 true。
- 發現並修正：先前從大廳左上按鈕重開歡迎卡再開始教程，`inviteForced` 沒清掉，回大廳後歡迎卡又自動開啟。現在按「開始新手教程」時清除（`GUIManager.lua`）。**修正後未再進 Studio 驗證。**
- 之後以 `scripts/verify.ps1` 重建 `build/AOE2-tutorial-r2.rbxlx` 並用命令列開啟（PID 47652），但視窗兩次都拿不到前景（桌面殼層在最前），依約定停止。

仍未驗證：每步至少停留 5 秒、`inviteForced` 修正、第 5–11 步真實操作、`TutorialMatch` 屬性清除（只有間接證據）、觸控／矮畫面、雙人、熱鍵設定面板全部項目。

### 新手教程第三輪與熱鍵面板代驗（2026-10-02 23:57–2026-10-03 00:04，`build/AOE2-tutorial-r3.rbxlx` 以當下磁碟原始碼重建，單人桌面，computer-use）

截圖 `tests/tutorial-studio-20261002-7` 至 `-14.jpg`；輸出 `tests/tutorial-studio-20261003-r3-*.txt`。

新手教程（全部以真實操作，沒有使用「略過」）：
- 「稍後再說」→ 左上「新手教程」重開 →「開始新手教程」進入教程局。
- 每步至少停留 5 秒：按 V 後第 3 步「採集並交回資源」在木材已入帳（1200→1210）的情況下仍停留，之後才進到第 4 步。
- 1 鏡頭（按住 D）→ 2 選村民（V）→ 3 交貨 → 4 房屋完工 → 5 主城訓練村民（人口 4→6）→ 6 伐木場完工 → 7 農田完工 → 8 兵營完工 → 9 訓練步兵 → 10 框選步兵 → 11 主城按 U 升級封建時代 →「新手教程完成 ✓」。
- 投降回大廳：沒有自動跳歡迎卡，只有左上「新手教程」按鈕（`inviteForced` 修正有效）。屬性面板篩選 `Tutorial`：`TutorialDone` 為勾選，沒有 `TutorialMatch`。
- 觀察：農田工地曾停在「等待村民 50%」，手動右鍵派村民後完工；與教程無關，可能是自動施工在村民忙碌時沒補派，未進一步追查。

熱鍵設定面板（代驗）：
- 戰局選單捲到底有「熱鍵設定」；面板置中、有暗幕，列出建築頁 B、生產頁 T、科技頁 R、陣形頁 F、升級時代 U、停止 X、駐紮 G、死亡／拆除 Del、選取所有村民 V、選取主城 H…，底部「恢復預設／完成」，清單可捲動。
- 面板開啟時按住 D 鏡頭不動、點地面不改變選取。
- 「停止」改綁 K：面板顯示 K；關閉面板後 HUD 顯示「停止 [K]」。步兵移動中按 X 仍顯示「移動」並繼續前進；按 K 後顯示「待命」且位置不再變。
- 保留鍵：擷取中按 W、按 1 都不會綁定，面板維持「請按新按鍵…」。**面板內沒有看到拒絕原因文字**（STUDIO.md 待測項寫「顯示原因」；若原因走通知橫幅，會被面板與暗幕蓋住）。
- Esc：擷取中按 Esc 取消擷取，面板仍開著、綁定不變。
- 衝突：把「生產頁」綁到 B，建築頁變 T、生產頁變 B（互換）；HUD 分頁顯示「生產 [B]」。
- 「恢復預設」：全部回到預設，HUD 回到「停止 [X]」。

未驗證：Esc 關閉面板本身（只測了取消擷取）；短橫向／觸控版面；改鍵跨場次保存（Studio 停用雲端）；教程的觸控與矮畫面版面、雙人。

熱鍵面板狀態列（2026-10-03，僅命令列）：Studio 代驗發現保留鍵被拒絕時通知橫幅被面板暗幕蓋住。面板內新增 `HotkeyStatus` 一行：拒絕原因以紅字顯示並維持擷取狀態，改綁成功、互換與恢復預設以綠字顯示；清單下移 24px。`tests/hotkey.spec.lua` 98 項與 `scripts/verify.ps1` 全部通過。Studio 未驗證：狀態列實際顯示與版面、Esc 關閉面板、短橫向／觸控版面、跨場次保存。

### 無人工地重新派工（2026-10-03，僅命令列）

原因：施工村民被調去別的工地後，只有 64 studs（`buildRadius`）內的閒置村民會回來接手，其餘村民去採集，遠處工地永遠停在「等待村民」。修正：`AutoWork.step` 對沒有任何村民施工超過 `siteDelay`（4 秒）的工地重新派最近的村民（閒置優先、採集／交貨中的次之），不動玩家指定待命、移動或修復中的村民；派工失敗每 `retryInterval` 重試。`tests/auto_work.spec.lua` 39 項通過、Luau 編譯與 Rojo 建置通過。

未驗證（需 Studio Play）：把施工中的村民全部調去蓋另一棟後，原工地約 4 秒後有人回來並完工；關閉自動工作時不派工；被擋住到不了的工地不會反覆抽調村民。

相機鍵改綁（2026-10-03，僅命令列）：熱鍵設定新增相機上／下／左／右四項（預設 WASD），方向鍵、Home、數字編隊、Esc 與組合鍵仍固定；`PlayerInput.client.lua` 的相機移動改為讀取目前綁定。`tests/hotkey.spec.lua` 118 項與 `scripts/verify.ps1` 全部通過。Studio 未驗證：相機鍵改綁後新鍵移動相機而舊鍵不再移動、把指令綁到 W 時與相機上移互換、方向鍵仍可移動、16 列清單可捲到最後、說明列的相機鍵字樣。

## 2026-10-02／03 大型戰鬥壓力測試與效能優化

`battle-validation.project.json` 額外映射 `tests/battle-stress.server.lua`、`tests/battle-stress.client.lua`（不在 `default.project.json` 內）。客戶端以正常大廳指令開 Small／1 簡單電腦／固定種子 2718 的對局；伺服器透過 Studio 專用 `RTSBattleProbe`（`GameServer`，僅 `RunService:IsStudio()` 建立）直接生成雙方部隊，不經訓練、不扣資源、不受人口上限，再由正式索敵／移動／攻擊邏輯交戰，記錄每個 0.1 秒邏輯步的耗時。重現：`bash tests/run-battle-stress-studio.sh`（命令列啟動本機伺服器＋1 客戶端，約 7 分鐘）。

伺服器每步平均／最差耗時（ms）；一幀預算 16.7 ms。基準與 r3 為 Studio 單機 Play，r4 為命令列伺服器＋客戶端，兩者行程配置不同：

| 場景（實際生成） | 優化前基準 | r3 | r4（最新原始碼） |
| --- | --- | --- | --- |
| 50 對 50 | 6.1／29 | 2.9／16 | 2.8／14 |
| 101 對 102 | 19.0／109 | 7.4／38 | 5.6／31 |
| 143 對 197（340 人） | 58.8／214 | 19.5／43 | 16.7／48 |
| 行軍接戰 98–100 對 72 | 27.9／105 | 11.9／41 | 11.0／39 |

r4 log 沒有遊戲腳本錯誤。r4 的 340 人場景中，指令步 9.3 秒有 7.7 秒在 `moveToward`，其中 `PivotTo` 2.5 秒（每次約 79 µs）。原始輸出見 [battle-stress-optimization-studio-20261002.txt](battle-stress-optimization-studio-20261002.txt)，最初未固定種子的一輪見 [battle-stress-studio-20261002.txt](battle-stress-studio-20261002.txt)。

未驗證：客戶端幀率（各輪 Studio 視窗失焦或在背景，數字不可採信）；複製流量（接收 Kbps 讀數為 0）；正式伺服器、真手機、多真人；攻城衝車／巨型投石機／僧侶／防禦建築參與的大型戰鬥；「自動接戰找不到路不再跳提示」與「被友軍擋住改打有空位的敵人或繞位」只有程式路徑與統計（卡住人數下降）佐證，沒有逐一目視確認行為。

### 無人工地重新派工 Studio 實測（2026-10-03 00:39–00:41，命令列伺服器＋1 客戶端，`bash tests/run-site-studio.sh`）

`site-validation.project.json` 只多映射 `tests/site-studio.client.lua`；全部經正式 `Command` 遠端下令，沒有改屬性或位置。結果 [site-studio-20261003.txt](site-studio-20261003.txt)：**11 項 PASS、0 FAIL**。
- A：空選取放農田（伺服器派 2 位村民），立刻把這 2 位改去 192 studs 外蓋房屋；農田 25.4 秒後完工（由第三位村民接手），房屋也完工。
- B：關閉自動工作後放房屋並把施工村民移走，12 秒內 `BuilderCount=0`、狀態「等待村民」；重新開啟自動工作後完工。
- C：全部村民按停止（待命）後放房屋、把施工村民移走再停止；12 秒內沒有村民被抽去施工（三位皆「待命」）。

未驗證：到不了的工地是否反覆抽調村民；雙人。熱鍵面板新項目（狀態列紅／綠字、相機鍵改綁、16 列捲動、Esc 關閉）與觸控城門旋轉按鈕**未驗證**：Studio 視窗拿不到前景（命令列開檔兩次、`open_application` 一次，最前方是系統的 Textinputhost）。
