# 真實雙人戰鬥音效與動作驗證

`Shared/FeedbackBattleTests.lua` 是明確呼叫的 Studio **客戶端**測試。`require()` 不會自動執行；它不寫入 HP、資源、時代、單位位置或攻擊屬性，不提供管理遠端。建造、訓練、升級、行軍與攻擊皆使用正式 `Command`，保留原始成本與計時。失敗保留當前對局。

本文件提供執行方法；只有實際 Studio log 的 `COMPLETE` 能確認當次引擎驗證完成。Luau 編譯成功不能替代引擎驗證。

## 短測試：已開局的斥候與敵方房屋

先在 Studio 啟動真正的 Server & Clients 兩個客戶端，以正常大廳配置開啟無 AI 的兩人 FFA；兩人都須持有完工房屋。可使用既有 `MultiplayerTests.RunHost()` 與 `JoinLobby()` 建立正式測試局。

先在**房屋擁有者**的客戶端 Command Bar 執行：

```lua
task.spawn(function()
 local player=game.Players.LocalPlayer
 local attacker,target
 for _,model in ipairs(workspace.Units:GetChildren()) do
  if model:GetAttribute("UnitType")=="scout" and model:GetAttribute("OwnerId")~=player.UserId then attacker=model end
 end
 for _,model in ipairs(workspace.Buildings:GetChildren()) do
  if model:GetAttribute("BuildingType")=="House" and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("Complete")==true then target=model end
 end
 require(game.ReplicatedStorage.Shared.FeedbackBattleTests).ObserveUnit(attacker,target,{deadlineSeconds=180})
end)
```

再在**斥候擁有者**的客戶端執行相同選擇，但斥候篩選改為 `OwnerId==player.UserId`、房屋改為 `OwnerId~=player.UserId`，最後呼叫：

```lua
require(game.ReplicatedStorage.Shared.FeedbackBattleTests).RunUnit(attacker,target,{deadlineSeconds=180})
```

主動端會以正常路徑行軍至敵方房屋附近，分別執行正常、靜音、減少動態各至少兩次新攻擊。必須觀察真正 `LastAttack`、敵方 HP 減少、已載入且播放中的實際 Sound、正式 `RTSClientEffects` 和原始外觀部分的動作。被動端觀察同一部隊與房屋，不下戰鬥指令。

## 正常發展至攻城與防禦

同樣從真正兩人 FFA 的 Playing 階段開始。先在第二端執行 `RunPeer`，再在主動端執行 `RunHost`：

```lua
-- 主動端
task.spawn(function()
 require(game.ReplicatedStorage.Shared.FeedbackBattleTests).RunHost({deadlineSeconds=1200})
end)

-- 第二端
task.spawn(function()
 require(game.ReplicatedStorage.Shared.FeedbackBattleTests).RunPeer({deadlineSeconds=1200})
end)
```

兩端會正常增建房屋、經濟建築、農田與八名村民，以實際採集及交貨補足成本。主動端依原始研究時間升到帝王時代，正常訓練步兵、長槍兵、弓箭手、矛兵、斥候、騎士、衝車、投石車、巨型投石機九種軍事單位。第二端升至城堡時代，於中央正常施工石牆、瞭望塔與城堡。

九種主動端軍隊依序攻擊真正敵方石牆，每類攻擊後正常撤回基地。長槍兵及矛兵觀察原始 `Spear`／`Spearhead` 部位，矛兵必須產生 `JavelinEffect`；騎士另觀察馬腿行軍與持劍攻擊。巨型投石機另驗靜音與減少動態。瞭望塔及城堡會真正射擊主動端的衝車；雙端均觀察實際傷害、聲音及箭矢。全程保留兩方市鎮中心，不以投降清場代替戰鬥結果。

若需先分階段準備，可分別執行 `Prepare("host",options)` 和 `Prepare("peer",options)`；完成後主動端執行 `RunHost({prepared=true,deadlineSeconds=1200})`，第二端執行 `ObservePeer({deadlineSeconds=1200})`。這些呼叫須在同一客戶端 Command Bar 的模組快取內完成。

## 範圍與判定

- 每個階段只以當次新的攻擊脈衝及 HP 變化計數，不把已存在的攻擊屬性視為新攻擊。
- 音效必須符合真實相機可見性、深度與距離條件，並檢查正式 Sound `IsLoaded` 與 `IsPlaying`。
- 減少動態允許傷害提示 Highlight；測試排除揮動、飛行及移動效果。
- 所有設定修改只在本機，測試結束或失敗會還原音效與減少動態設定，斷開觀察連線。
- 這是回饋驗證，不覆蓋完整剋制矩陣、擊殺覆盤、所有科技、2v2、AI 長跑、實機性能或人耳主觀音質。

## 尚需由引擎確認的限制

- 正常前置為：封建時代需要完工磨坊與兵營；城堡時代需要完工射箭場與馬廄；帝王時代以完工城堡滿足替代條件。測試等待伺服器研究完成，不直接改時代。
- 目前 Rich 起始為食物／木材各 1200、黃金 800、石材 600。主動端必須真實採集額外食物約 1610、木材約 625、黃金約 750，以及城堡所需的額外石材；測試經濟目標保留工作存量，實際採集可能更多。
- 地圖保留基地 128 studs 範圍的開闊區，天然資源在其外。農田能縮短食物交貨；近基地的採礦／伐木營仍有較長走路路程。1200 秒為失敗上限，沒有以提高採集率、縮短原始計時或補餘額保證完成。
- 所有移動完成皆檢查正常多選的 4-stud 陣形個別目標與待命狀態；等待位置以完整城堡占地尋找空地。任何合法路徑失敗會保留當前模型及工地，不能當作回饋通過。
- 每類單位必須實際找到其原始外觀動作部位，部位不存在時不能跳過動作驗證。減少動態切換後等待三次真正 `RenderStepped`（至多三秒），再取靜止部位基準。
- 此模組本身尚無引擎完成紀錄；執行時需保存兩個實際客戶端各自的 `PASS`／`FAIL`／`COMPLETE`，並綁定測試時來源 hash。編譯通過只證明語法可解析。
