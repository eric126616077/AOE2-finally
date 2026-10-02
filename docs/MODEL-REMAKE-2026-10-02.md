# 替代模型重製（2026-10-02）

只改 `src/ReplicatedStorage/Shared/Art.lua` 的原創替代外觀；Studio 模板、`ModelFactory` 與遊戲規則未變。這是原型美術改進，不代表完整遊戲。

修改前備份：`C:/Users/user/AppData/Local/Temp/AOE2-before-model-remake-20261002-121717/Art.lua`（SHA256 `2979E74A…14CF1`，即上一輪最終 Art）。新 Art SHA256：`D5C697A50D432DE35642905CB6B4FA1815D03C47A83E863E44A2AD695BECEAA6`。

## 主要問題

Roblox 的 `Ball` 一律以單一直徑繪製，舊版用不等邊尺寸做的「橢圓」實際上會變成球：漿果叢縮小後漿果漂浮在叢外、馬身變成圓球、帽子變成小球。本輪所有 Ball 一律以等邊尺寸建立（新增 `ball()` 輔助函式），外觀不再依賴引擎如何夾取尺寸。

## 重製範圍

- **單位**：頭盔改為圓頂加盔緣與護鼻，露出眼睛；村民草帽、弓箭手兜帽加羽毛、散兵皮帽、僧侶連帽長袍；鳶形盾（步兵、騎士）與圓盾（長槍兵、散兵、斥候）朝前斜放；弓改為相連的弧形；散兵改持兩支標槍。
- **馬**：圓柱加前後球組成的膠囊身體、斜頸、帶口鼻的頭、耳眼與下垂馬尾；騎士有馬衣與面甲，騎手雙腿跨在馬側。
- **資源**：金礦／石礦改為主岩加倚靠石塊，金塊嵌在岩縫；漿果叢改三團矮叢，漿果嵌在表面；樹改為等邊樹冠並露出樹幹。部件預算維持 Tree 4、Gold 8、Stone 4、Berries 8。
- **攻城**：投石機轉軸對齊客戶端擺動支點，配重箱掛在短臂上；衝車屋頂改獸皮色，只有屋脊與側旗用玩家色。
- **建築**：只把大學圓頂、磨坊糧袋、旗杆頂飾等球體改為等邊，造型不變。

動畫群組名稱（`ArmR`、`Sword`、`HorseLeg`、`Bow`、`Counterweight` 等）與 `TeamColorPart` 規則沿用，戰鬥測試需要的部件名稱都在。樹仍為一個 `Trunk` 加三個 `Crown` Ball；擬合後主樹冠約 13.3，高於叢集間距 13。

## 已執行的檢查

- 全部 `src` 的 Luau 編譯（預設與 `-O0`）通過；`rojo build default.project.json -o build/AOE2.rbxlx` 成功。
- `build/art-budget-snapshot.luau` 的模擬斷言改用新 Art 執行，結果 PASS：單位部件皆在動畫群組、建築部件皆有施工階段、資源預算不變、各模型有玩家色部件。
- `build/art-preview/` 的離線預覽：`dump.py` 以模擬環境執行真正的 Art.lua 並輸出部件，`render.py`／`compare.py` 依 Roblox 基本形狀規則（Ball 取最小邊、Cylinder 沿 X、WedgePart 斜面朝 -Z）繪圖。對照圖：`compare-units.png`、`compare-other.png`。這是近似繪圖，不是 Studio 畫面。

## 未驗證

沒有 Studio 連線，以下都沒有執行：Studio Play 實際外觀、材質與光影、單位走路／工作／攻擊動畫的部件對齊（特別是騎手腿、盾牌、投石機擺臂）、`PlayerColorTests`、`MapTests` 樹冠檢查、`FeedbackBattleTests`、HUD 預覽、雙人同步與效能。`scripts/verify.ps1` 需要 PowerShell 7，本機沒有安裝，因此沒有跑完整腳本，只執行了上列的編譯與建置步驟。
