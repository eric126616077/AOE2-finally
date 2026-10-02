# 2026-10-01 發佈收尾狀態

使用者已明確授權「等全部完成為我發佈到roblox studio」，並回覆 Studio「現在可以接手」。更新既有體驗 EmpireForge: Beta Version，Universe `9550687645`、入口 Place `106565275080490`。目前尚未發佈本輪更新。

本輪較早的 94 份程式已固定來源驗證：Luau、完整 CLI、Rojo 預檢通過，150 個輸入前後 SHA256 一致。预檢 `build/AOE2-publish-preflight-20261001-final.rbxlx` SHA256 為 `D6ACCBE9E17DBA07DA0C153B11FEC4E952A3070C195E729CBDA3A26C9D0C6B4E`；來源與輸出見 `tests/publish-20261001-final-cli-source-manifest.json`、`tests/publish-20261001-final-cli-results.txt`。前輪 Art 執行中變更的紀錄仍保留，不列為固定來源成功。

新的無模型單人 Play 於台北時間 18:08:45–18:09:43 完成 Release 19、BuildMenu 840、HUD 55、Formation 210、UnitCollision 74 項檢查。真正的整合 COMPLETE 已確認，Command Bar 回音不列為完成證據。見 `tests/publish-20261001-integration-studio-results.txt`；原 log 為 `C:/Users/user/AppData/Local/Roblox/logs/0.741.19.7411056_20261001T100640Z_Studio_A787A_last.log`。此為單人測試，不宣稱雙人同步、所有權、玩家離開及真機已通過；原生小地圖右鍵仍須補測。

驗證後新增兩個仍在修改的聊天：「精緻化遊戲介面與模型」（`01a0f6e9-ab4a-7d93-9d46-4667adc72a5a`）與「為所有單位新增圖示」（`01a0f6e8-522a-7661-a312-246b8583d14d`）。最新 UnitIcons／UnitSelectionPanel／GUI／模型變更不在上述固定來源證據內。依「全部完成」的先後條件，等待這些工作收尾，再固定最新來源重做必要驗證；不得將上面的 COMPLETE 延伸為新版全數通過。

原始碼備份在 `build/backups/publish-20261001/source-before-publish.zip`。保留原模型的發布合併工具已準備於 `build/publish-tools/prepare_candidate.py`，接受 `--base --preflight --output --report`；10 組合成驗證通過，可用 `selftest_candidate.py` 重跑。尚未執行真正合併。工具以先前 `build/AOE2-publish-snapshot-20260930.rbxlx` 為基礎，只更新 Rojo 映射 properties／Source並新增映射節點；核對完整來源、非串流、沒有驗證自動啟動器，以及所有未知最大子樹與原模型內容保留。不得覆寫原 place 或以前快照。

已建立本聊天的五分鐘後續檢查，名稱「整合完成後發佈 Roblox」、id `roblox`。保持無可行動時安靜；其他修改完成後繼續最新版本驗證、保留模型候選與既有體驗發布。必須取得正確目的地與 PublishSuccessful 才宣稱成功；成功後停用後續檢查。這份紀錄不是已發佈證明。
