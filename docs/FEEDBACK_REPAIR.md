# 真戰損修復回饋驗證

`Shared/FeedbackRepairTests.lua` 是明確呼叫才執行的 Studio 客戶端驗證；目前僅已通過 Luau 編譯，尚未記錄實際 Play 的 COMPLETE。此頁不宣稱修復引擎測試已通過。

在真正兩名敵對玩家的 Playing 對局，由非房主於正常戰鬥開始前明確呼叫：

```lua
require(game.ReplicatedStorage.Shared.FeedbackRepairTests).Arm()
```

`Arm()` 唯讀觀察己方完工建築的 HP 下降，要求對應另一名真人軍隊新增的 `LastAttack`、`AttackPosition` 平面位置及短複製時間窗口。只記錄符合這些條件的真正戰損；初始化缺血、正常未完工建築、AI 或沒有真正攻擊脈衝的 HP 差額都不足以成為修復證據。`require` 本身不建立觀察器。

完成正式 `FeedbackBattleTests` 的軍事回饋樣本並讓房主軍隊正常撤離後，在同一非房主客戶端執行：

```lua
task.spawn(function()
    require(game.ReplicatedStorage.Shared.FeedbackRepairTests).Run()
end)
```

測試優先選取至少兩次真戰損、累計至少 75 HP、目前仍有至少 75 HP 修復缺口的己方完工石牆，再選最近的本方村民。先要求造成戰損的存活敵軍已撤離射程，正常 Stop 全部村民，驗證一個工作週期內目標 HP 穩定。使用本機「減少動態」並等待三個真正 RenderStepped 畫格，才記錄工具／手臂的基準姿勢。

正常 Order 執行修復；兩次真正 `LastWork`／`WorkKind=repair` 工作脈衝必須各增加 15 HP、扣除一木材。驗證正式 LocalScript 建立的 `RTS_Repair` Sound 已載入且正在播放、工具或手臂有動作、減少動態在三個畫格後還原。接著本機靜音，要求下一次實際修復仍正常增加 HP 與支付木材，但活動播放與世界播放均為零；解除靜音後下一次修復恢復空間音效。最後正常停止，跨越 1.1 秒仍不增加 HP、不扣款、不更新 `LastWork`、不建立新修復音效，播放池歸零。

Run 的總期限為 170 秒，每個等待都有更短的明確期限。失敗會打印選定工人、建築、真正戰損證據、木材、時間戳記及正式音效播放池狀態。成功與失敗都停止選定工人、還原原來音效／動態設定、斷開觀察器。玩家離開、對局或世代改變、驗證協調器任一玩家 `FV_Failed` 旗標都會關閉 Arm 觀察；外部驗證流程也可明確呼叫 `FeedbackRepairTests.Close()`。

本測試不補資源、不改 HP、不移動單位或目標、不寫伺服器遊戲時間戳記、不加速遊戲，也不把既有缺血推定為戰鬥傷害。修復會使用真正庫存並改變測試局，應在專用的全新 Studio 工作階段執行。
