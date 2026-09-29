# 專案工作指引

## 目標
在 Roblox 製作受《帝國時代》啟發的 RTS：俯視操作、村民經濟、建造、軍隊與對戰。溝通與新增玩家文字使用繁體中文。不把原型描述為完整遊戲。

## 專案與同步
- 使用 Luau、Rojo 7.6.1；入口為 `default.project.json`。
- `src/ServerScriptService`：伺服器啟動與權威遊戲邏輯。
- `src/ReplicatedStorage/GameData`：共用數值設定；`Shared`：共用模組。
- `src/StarterPlayer/StarterPlayerScripts`：客戶端輸入、相機、建築預覽。
- `src/StarterGui/GameUI/GUIManager.lua`：介面模組。
- ReplicatedStorage 內的 LocalScript 不會自動執行。不要使用 `getgenv()`。
- 根目錄無副檔名的 `*Setup` 是舊 Studio 模型腳本參考，不在 Rojo 映射內。不要直接把它們全部啟用，避免重複調整模型。
- Studio 可能有未匯出的 `ReplicatedStorage/Buildings` 與 `Resource` 模型；保留未知實例，不刪除或覆蓋使用者模型。程式須能在缺少模型時使用替代外觀。
- 使用者已授權重構與重新設計 UI，不必保留舊介面。原有模型仍應保留；新的共用幾何外觀位於 `Shared/Art.lua`。

## 實作原則
- 金錢、資源扣款、建築生成、單位、採集、戰鬥由伺服器決定。客戶端只能提出指令與顯示預覽。
- 所有遠端請求驗證型別、有限數值、範圍、所有權、成本與頻率；失敗不得扣款。
- 地圖範圍、格線、建築占地與價格共用 GameConfig。避免任意等待秒數、跨端全域變數與每幀遍歷整個 Workspace。
- RTS 不依賴玩家角色；伺服器關閉 CharacterAutoLoads，客戶端不得等待 CharacterAdded 才初始化 UI。
- 此 512 studs 地圖使用完整複製：`default.project.json` 必須明確設定 `Workspace.StreamingEnabled=false`。沒有角色卻使用預設串流中心，會讓客戶端只收到空 Model、看不到地面。不可只以小地圖或伺服器實例存在判定場景正常。
- HUD 使用 UIScale 與安全區域，輸入命中檢查必須考慮 GuiInset；測試底部面板緊鄰的地面可點擊且 UI 不穿透。
- 初始化應避免重複執行，玩家離開清除其狀態與實例。
- 先讀現有程式並保留美術與玩法意圖，分階段完成可驗證的功能。

## 驗證
- 執行 `.\rojo.exe build default.project.json -o build/AOE2.rbxlx` 檢查映射。
- Luau 語法檢查與純邏輯測試不能取代 Roblox Studio Play 測試。
- Studio 至少驗證：無模型啟動、UI 資源、相機、四種建築、障礙／邊界／資源不足、雙人同步與玩家離開清理。
- 沒有 Studio 連線或實機測試時，明確寫出未驗證部分，不能宣稱測試通過。
- Windows 上可用 computer-use 技能的 `@oai/sky` 直接操作 Studio、Play、Command Bar，再讀 Roblox Studio log；先閱讀技能，不要自行使用 PowerShell UI Automation。
- `Shared/StudioTests.lua` 是明確呼叫才執行的 Studio 客戶端整合測試，會改變測試局的建築與資源；在新 Play 工作階段執行。Command Bar 的 require 快取與遊戲腳本分離，檢查畫面時使用實際 PlayerGui，不能假設 UI ModuleScript 的狀態共用。
- 不自動發布 Roblox 體驗、不覆蓋現有 place 檔；輸出到 build，原始碼變更前保留備份或版本紀錄。
