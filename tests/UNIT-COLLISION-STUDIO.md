# 單位碰撞體積驗證

## 實作

- 所有 `Config.Units` 兵種透過 `ModelFactory.unit` 產生一個透明、直立圓柱 `CollisionVolume`；村民、步兵與弓兵半徑 2／高度 5，騎兵半徑 3／高度 7，攻城器半徑 4／高度 5 studs。未列出的類別使用共用預設值。
- 保留原本 Root 與外觀。客戶端外觀插值不移動伺服器碰撞部件；游標射線略過透明碰撞部件，繼續命中實際顯示的外觀。
- 單位使用 anchored `PivotTo`，因此伺服器每一步額外驗證完整體積對靜態場景的 Blockcast、地圖邊界與單位圓盤掃掠。動態空間索引在每次移動後更新，出生與互動接近點也會檢查占用；移除單位時清理索引。
- 障礙或單位占用時先試左右繞行；正常方向全部受阻時，可嘗試最大兵種直徑長度的退讓點。完整退讓段與實際小步都檢查碰撞，期限依距離與速度推導，每道指令最多兩次，無安全候選時等待。碰撞體積不改變靜態尋路網格。

## CLI

執行 `./scripts/verify.ps1`，輸出保存於 `unit-collision-cli-20261001.txt`。其中包含實際工廠模組與 `moveToward` 函式的回歸測試、圓盤掃掠／索引測試、Luau 編譯與 Rojo 映射；引擎查詢使用 mock，因此不能替代 Play。

退讓修正前，另以正式 `FormationRules.plan`、0.1 stud 到達公差模擬四村民的八種初始角度，全部到位且維持間隙。20 人混合半徑密集編隊模擬全程沒有重疊，但 150 秒後仍有兩人未到位：已停止的外圈可能封住內圈。這份結果保存在 `unit-collision-crowd-simulation-20261001.txt`，不是修正版的大型人群通過證據。本次沒有加入編隊排程或讓已到位單位重新移動的系統，大型人群導航仍未完整驗證。

## Studio 測試方式

1. `./rojo.exe build unit-collision-validation.project.json -o build/AOE2-unit-collision-validation-20261001.rbxlx`。這個獨立映射加入測試用伺服器 probe，正式 `default.project.json` 不自動執行測試。
2. 開啟生成的測試副本並啟動新的單人 Play。伺服器 probe 在私有 fixture 中呼叫 `ModelFactoryTests.Run()`，檢查所有十種兵種的實際尺寸、移動轉向、引擎射線與原模板保留，隨後清除 fixture。
3. 使用正常大廳流程開啟無 AI 的小圖沙盒，等待相機、HUD、無角色與起始四單位就緒後，在 CLIENT 明確呼叫 `require(game.ReplicatedStorage.Shared.UnitCollisionTests).Run()`。
4. 客戶端測試使用正常 Order／Stop；檢查散開、繞過待命單位、迎面交換與四人混合編隊，逐人核對正式編隊 slot、到達及待命。測試會嘗試採集交貨，清理時停止測試單位。
5. `[UNIT_COLLISION JSON i/n]` 是每段最多 600 bytes 的完整 JSON 證據；需依序合併。客戶端 Root 樣本允許 0.25 stud 複製公差；伺服器 probe 另在 Heartbeat 稽核實際 Root 與碰撞體積，不能以客戶端樣本代替。

## 驗證範圍

第一輪 Play 的散開、待命繞行與迎面接近通過；混合編隊逾時。後續修正了移動隊友暫時占用目的地被誤判為已停止，以及測試與正式編隊 slot 的不一致。此初次失敗紀錄保留於 `unit-collision-first-play-20261001.txt`，不當作修正版通過證據。

第二輪 Play 的四人移動全部通過，但採集木材後的交貨逾時：村民被三名待命隊友堵在緊密編隊後側，沒有穿透。紀錄保存在 `unit-collision-delivery-first-failure-studio-20261001.json`；同輪 95 秒伺服器稽核沒有違規。這個實際座標已加入回歸測試，退讓修正後可脫困，三名待命單位保持原位。

最終 Play 使用已開啟的生成測試副本，透過 Rojo 7.6.1 的本機 34879 埠同步 validation project；Command Bar 印出 `[UC_SYNC] true true true` 確認新退讓與 probe 已存在，斷開同步後啟動新的 Play。沒有儲存覆蓋這個舊 place 檔。`unit-collision-studio-source-manifest-20261001.json` 記錄來源與等效建置 `build/AOE2-unit-collision-validation-final-20261001.rbxlx`；正式輸出 `build/AOE2.rbxlx` 不包含自動執行的 probe。

| 最終驗證 | 結果 |
| --- | --- |
| Luau 編譯、CLI 全套與正式 Rojo 建置 | 通過；碰撞幾何 1463、實際移動函式 1166、工廠 mock 514 項 |
| 十種兵種的引擎私有工廠 fixture | 285 項通過；實際圓柱尺寸、底面、PivotTo 轉向與頂面射線 |
| CLIENT 正常指令整合 | 74 項通過，25.827 秒；四人散開、待命繞行、迎面交換、正式混合編隊、採集食物與交貨 3 |
| CLIENT 移動證據 | 1536 次樣本、370 次 Root 變動；最小表面間距 0.168149 studs；碰撞部件相對 Root 位移誤差 0 |
| SERVER Heartbeat 稽核 | 95.004 秒、5673 次樣本、397129 項檢查、0 違規；最小間距 0.168 studs（紀錄四捨五入），四人都有實際移動 |
| 啟動狀態 | `StreamingEnabled=false`、`Character=nil`、相機 Scriptable、實際 PlayerGui HUD 存在 |

最終完整分段 JSON 與原始相關 log 位於 `unit-collision-studio-20261001.json/.txt`，解析器選取第三輪並保留前兩輪失敗脈絡。伺服器 FINAL 紀錄另存於 `unit-collision-server-audit-20261001.json/.txt`。

此任務沒有完成多人碰撞 Play、死亡／玩家離開的引擎重驗，亦沒有重跑全部四種建築與 UI 邊界案例；這些不得宣稱已通過。
