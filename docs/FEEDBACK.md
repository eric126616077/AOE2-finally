# 音效與動作回饋

> 2026-10-02 更新：音效已改用 Roblox 授權素材並加入配樂、受攻擊警報與情境游標，詳見 [音效與游標紀錄](AUDIO-CURSOR-2026-10-02.md)。下文「六個內附音檔」為先前版本，現僅作為素材載入失敗時的替代音。

2026-09-30 新增測試版回饋。修改前來源備份：`C:/Users/user/AppData/Local/Temp/AOE2-before-feedback-20260930-180021`。不發布、不覆蓋原 place 或使用者模型。

## 行為

- 選取及操作介面使用短提示；接受指令、成功放置工地、完工、訓練、研究、升級與對局結果由伺服器提供提示類型，不從文字猜成功或失敗。
- 村民採集、施工、修復及交貨使用伺服器的 `WorkKind`、`LastWork`、`LastDelivery`。沒有成功工作脈衝時恢復休息姿態。停止及改派會清除工作種類。
- 軍隊依 `Animation`／`LastAttack` 顯示步態、揮擊、射箭、標槍與投石。塔及城堡也有防禦射擊。這些視覺投射物在伺服器傷害確認後才顯示，不做命中判定。
- 客戶端最多 40 個短暫視覺效果，鏡頭外不生成效果。離屏或「減少動態」時零件回到休息姿態並跟隨伺服器根部。受傷、交貨與完工保留短淡出輪廓提示。
- 音效最多八個同時播放，世界音效最多五個；限制同來源、同類型及總播放頻率。世界音效依鏡頭可見性與 460 studs 距離限制，不依賴 RTS 角色。
- 使用 `rbxasset://sounds/` 六個 Roblox 內附素材的短片段，作為測試版提示。正式音色、混音與真人裝置聽感仍需調整。
- 選單的「音效」即時靜音／解除；「動態」可減少單位和介面動態。觸控選單限制高度並可捲動，保留 44 像素按鈕。

## 重現

本輪實際結果（Asia/Taipei）：2026-09-30 18:20–18:21 的無模板桌面 Play 通過 Presentation 65／Gameplay 17 項；18:27 的 iPhone 17 Pro 橫向模擬 Play 通過 Presentation 66／Gameplay 18 項。涵蓋真實音檔預載及解碼、同時播放上限、靜音與解除、六個選單按鈕的安全範圍／捲動到達、村民採集／交貨及減少動態還原。桌面另實際點擊音效按鈕確認可來回切換。模擬器不等於真實手機聽感或手勢驗收。

先前用原始路徑預載被引擎當成圖片，已改成 Sound 實例後重開 Play 通過。18:24 手機的第一輪 Gameplay 音效檢查逾時：原測試只在行走前聚焦，未確認到場後仍符合可聽條件；測試改成先聚焦目前工作位置、確認正式可聽規則，再等下一採集脈衝，18:27 重跑通過。原始 FAIL 與後續 COMPLETE 一併保留，不改寫為所有測試從未失敗。

最新 CLI 全部編譯、現有純邏輯套件及 70 項音效規則通過；建置輸出 `build/AOE2.rbxlx` 與 `build/AOE2-feedback.rbxlx`，來源雜湊見 `tests/feedback-source-manifest.json`。此結果沒有涵蓋完整戰鬥／攻城、施工音效與多人效果同步，不能延伸為完整測試版通過。

執行 `./scripts/verify.ps1`，包括 `tests/feedback.spec.lua` 的 70 項節流、同時播放上限、靜音與鏡頭規則測試及 Rojo 建置。

新單人 Studio Play 客戶端 Command Bar：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.FeedbackTests).RunPresentation()
    require(game.ReplicatedStorage.Shared.FeedbackTests).RunGameplay()
end)
```

Presentation 讀取實際 PlayerGui、PlayerScripts 的播放探針及真正 Sound 資產載入。Gameplay 透過正常大廳啟動單人豐富資源局，以實際採集／交貨驗證時間戳、音效與工具姿態，會改變測試局，最後停止村民。測試不加資源、不修改伺服器單位。Command Bar 的 require 快取與遊戲腳本可分離，正式播放池以 `PlayerScripts.RTSAudioProbe:Invoke()` 讀取。

Studio 結果保留在 `tests/latest-feedback-studio-results.txt`；只有 COMPLETE 所列範圍可視為通過。桌面、手機橫向版面須各自在實際模擬設定的 Play 中執行。大量戰鬥、十種單位完整視覺、雙人聲音同步、真實手機手勢與正式 Roblox 客戶端聽感仍待驗收。

## 施工回饋：2026-09-30 實際 Play 完成

20:50:44–20:50:56（Asia/Taipei）的全新單人 Studio Play 通過 **38 項施工回饋檢查**。無外部 Buildings／Resource 模板，以正常大廳啟動 Small、Rich 沙盒，使用正式 Build／Order／Stop 指令及替代外觀村民。測試沒有補資源、修改伺服器時間戳記或加速施工。

涵蓋工地建立只扣一次成本、未完工不提前增加人口或提示完工；村民實際到場增加進度後才發布 `WorkKind=build`／`LastWork`；正式音效腳本的已載入施工空間音效及工具／手臂姿勢；減少動態還原、停工不增加進度或產生假工作音效、靜音時正常續建、解除靜音後下一次實際工作播放；真正完工才發布一次提示音效、保留減少動態下的短輪廓回饋及啟用人口；重疊建造拒絕時只有錯誤音效、不扣款、不出現假成功回饋，最後活動播放池完整清理。

保留前兩輪真實失敗：20:40 的測試在 `Playing` 複製後立即檢查角色，遇到大廳角色清理尚未複製的時間差。已改成最多等待 10 秒，仍要求實際 `Sandbox=true` 且 `Character=nil`。20:43 的房屋其實可以完工，卻沒有村民工作脈衝；唯讀診斷顯示 `Complete=true`／進度 1，但村民沒有 `LastWork`。根因是 `UnitRules.takeAction` 的允許動作清單漏掉 `workFeedback`，施工回饋時鐘永久拒絕該呼叫。已補這個動作，實際模組的回歸先重現失敗、修正後 76 項施工／工作時鐘檢查通過。選址規則及 35 秒到場期限保持相同，沒有移遠工地或延長期限取得通過。

原始兩次 FAIL、修正後全部 38 PASS／COMPLETE、第二輪失敗後的唯讀模型診斷及相關來源雜湊保存在 `tests/latest-feedback-construction-studio-results.txt`；純邏輯修正前後證據在 `tests/latest-construction-feedback-clock-results.txt`。這個新增結果僅證明施工回饋，不延伸為多人同步、完整戰鬥／攻城、真人聽感或正式 Roblox 客戶端已通過。

全新單人 Studio Play 的客戶端 Command Bar：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.FeedbackConstructionTests).Run()
end)
```

這個測試會正常開局、花費一棟房屋的木材並完成施工，最後停止村民、還原原來的音效與動態設定。`require` 本身不執行測試。
