-- Client guidance observes server facts; it grants no resources or gameplay advantages.
local Tutorial = {}
Tutorial.Steps = {
 {title="選取村民", desktop="點選村民，或按 V 選取全部村民。", touch="點「村民」，或以「選取」模式點一名村民。", key="selectedVillager"},
 {title="交回第一批資源", desktop="閒置村民會自動採集附近資源；也可選村民右鍵樹木或漿果指定。", touch="閒置村民會自動採集；也可選村民，點「採集」再點樹木或漿果。", key="delivered"},
 {title="完成第一間房屋", desktop="不選單位時按 B 開建築頁，選房屋再點空地；最近的村民會自動施工。", touch="不選單位時在建築頁點房屋；在空地拖移預覽，放開後自動派村民施工。", key="house"},
 {title="訓練新村民", desktop="點主城，在生產頁點村民；新村民會自動去工作。", touch="以「選取」點主城，在生產頁點村民；新村民會自動去工作。", key="trained"},
 {title="建立第一支軍隊", desktop="選村民完成兵營，點兵營生產步兵；右鍵敵人下令攻擊。", touch="完成兵營，選兵營生產步兵；選軍隊，以「攻擊」點敵人。", key="army"},
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
return Tutorial
