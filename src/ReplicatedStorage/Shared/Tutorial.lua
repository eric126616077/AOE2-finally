-- Client guidance observes server facts; it grants no resources or gameplay advantages.
-- desktop / touch：這一步要做什麼；why：為什麼要這樣做。key 對應介面觀察到的事實。
-- {動作:預設鍵} 會由 Tutorial.Format 換成玩家目前綁定的按鍵。
local Tutorial = {}
Tutorial.Chapters = {"認識戰場","建立經濟","擴張基地","組建軍隊","邁向新時代"}
Tutorial.Steps = {
 {chapter=1, title="移動鏡頭", key="cameraMoved",
  desktop="用 W A S D 平移畫面、滾輪縮放；按 Home 隨時回到主城。也可以點右下角的小地圖直接跳過去。",
  touch="雙指拖移可平移畫面，雙指開合可縮放；點「主城」隨時回到基地。",
  why="你的領地比畫面大得多。先看看主城四周的樹木、漿果、金礦與石礦在哪裡。"},
 {chapter=1, title="選取村民", key="selectedVillager",
  desktop="左鍵點一名村民，或按住左鍵拖出方框一次選多名；按 {selectVillagers:V} 可選取全部村民。",
  touch="點「村民」選取全部村民，或在「選取」模式點一名村民。",
  why="村民是經濟的核心：採集、建造與修復都靠他們。被選取的單位腳下會出現光圈。"},
 {chapter=2, title="採集並交回資源", key="delivered",
  desktop="選取村民後，右鍵點樹木（木材）或漿果叢（食物）。村民裝滿後會自己走回主城交貨。",
  touch="選取村民，點「採集」再點樹木或漿果叢。村民裝滿後會自己走回主城交貨。",
  why="資源要「交回」才會入帳，上方資源列的數字才會增加。閒置的村民也會自動找附近的工作。"},
 {chapter=2, title="蓋一間房屋", key="house",
  desktop="按 {build:B} 開啟建築頁，進入「經濟」選房屋，再左鍵點一塊空地。綠色預覽表示可以蓋，紅色表示被擋住。",
  touch="在建築頁進入「經濟」點房屋，於空地拖移預覽，放開後就會派村民施工。",
  why="每間房屋增加 5 人口上限。人口滿了就無法再訓練單位，所以要提早蓋。"},
 {chapter=2, title="訓練新村民", key="trained",
  desktop="左鍵點主城（市鎮中心），在「生產」頁點村民。可以連點幾次排入佇列。",
  touch="以「選取」模式點主城，在「生產」頁點村民。可以連點幾次排入佇列。",
  why="村民越多，資源進帳越快。開局持續訓練村民，是最重要的習慣。新村民會自動去工作。"},
 {chapter=3, title="蓋伐木場", key="dropoff",
  desktop="按 {build:B} 進入「經濟」選伐木場，蓋在樹林旁邊。磨坊（食物）與採礦營地（黃金、石材）也是同樣用法。",
  touch="在建築頁進入「經濟」點伐木場，把預覽拖到樹林旁邊再放開。",
  why="村民會把資源交回最近的收集點。收集點離資源越近，來回走路的時間越短。"},
 {chapter=3, title="開墾農田", key="farm",
  desktop="按 {build:B} 進入「經濟」選農田，蓋在主城或磨坊旁。完工後施工的村民會直接留下來耕作。",
  touch="在建築頁進入「經濟」點農田，放在主城或磨坊旁邊。",
  why="漿果會採完，農田是長期穩定的食物來源。一塊農田只容納一名村民，耗盡後可以重新播種。"},
 {chapter=4, title="蓋兵營", key="barracks",
  desktop="按 {build:B} 進入「軍事」選兵營。占地比房屋大，找一塊夠寬的空地。",
  touch="在建築頁進入「軍事」點兵營，放在夠寬的空地。",
  why="軍事建築用來訓練部隊。兵營可以訓練步兵，升上封建時代後還能訓練長槍兵。"},
 {chapter=4, title="訓練步兵", key="army",
  desktop="左鍵點兵營，在「生產」頁點步兵。步兵需要食物與黃金；黃金不夠就派村民去採金礦。",
  touch="以「選取」模式點兵營，在「生產」頁點步兵。",
  why="沒有軍隊就守不住基地。兵種互相克制：長槍兵剋騎兵、矛兵剋弓箭手、騎兵剋弓箭手。"},
 {chapter=4, title="指揮軍隊", key="selectedArmy",
  desktop="拖曳方框選取步兵，右鍵點地面移動、右鍵點敵人攻擊。按 Ctrl + 1 編隊，之後按 1 就能再選到他們。",
  touch="選取步兵，用「移動」點地面、用「攻擊」點敵人。",
  why="右鍵是萬用指令。要讓單位躲進主城或塔樓，必須用「駐紮」按鈕（{garrison:G}）或 Alt + 右鍵，一般右鍵不會駐紮。"},
 {chapter=5, title="升級到封建時代", key="feudal",
  desktop="左鍵點主城，在「科技」頁點「升級封建時代」。需要 500 食物，以及兩種不同的經濟或軍事建築。",
  touch="以「選取」模式點主城，在「科技」頁點「升級封建時代」。",
  why="新時代會解鎖射箭場、馬廄、兵工廠、市集、瞭望塔與城牆。房屋、農田與防禦建築不計入升級條件。"},
}
Tutorial.Completion = {
 title="新手教程完成",
 text="你已學會鏡頭、採集、人口、建造、生產與指揮。接下來試試：蓋射箭場與馬廄搭配兵種、在兵工廠研究升級、用石牆與城門保護基地。準備好後從選單投降回到大廳，加一位「簡單」電腦對手打第一場對戰。",
 touch="你已學會採集、建造、生產與指揮。接著試試其他兵種與科技；準備好後從選單投降回大廳，加一位「簡單」電腦對手。",
}
function Tutorial.New() return {step=1, complete=false} end
function Tutorial.Advance(state, facts)
 if state.complete then return false end
 local step = Tutorial.Steps[state.step]
 if not step or facts[step.key] ~= true then return false end
 state.step += 1
 state.complete = state.step > #Tutorial.Steps
 return true
end
-- 略過不會偽造事實；只把指引移到下一步。
function Tutorial.Skip(state)
 if state.complete then return false end
 state.step += 1
 state.complete = state.step > #Tutorial.Steps
 return true
end
-- label(id) 回傳目前綁定的按鍵文字；沒有綁定時使用括號內的預設鍵。
function Tutorial.Format(text, label)
 return (string.gsub(text, "{(%w+):([^}]+)}", function(id, default)
  local key = label and label(id)
  return type(key) == "string" and key ~= "" and key or default
 end))
end
function Tutorial.Progress(state)
 return math.clamp((state.step-1)/#Tutorial.Steps,0,1)
end
-- 只有確定檔案狀態時才把玩家視為新手；讀取失敗時不打擾老玩家。
function Tutorial.FirstTime(profileStatus, tutorialDone)
 if tutorialDone == true then return false end
 return profileStatus == "Ready" or profileStatus == "SaveFailed" or profileStatus == "Disabled"
end
return Tutorial
