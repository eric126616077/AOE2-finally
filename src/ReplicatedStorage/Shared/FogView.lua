-- 客戶端的戰爭迷霧狀態：FogOfWar.client.lua 每次更新後寫入，小地圖、點選與滑鼠提示讀取。
-- 只影響本機顯示；伺服器的戰鬥、採集與 AI 不依賴迷霧。
local Players=game:GetService("Players")
local FogRules=require(script.Parent.FogRules)
local TeamClient=require(script.Parent.TeamClientRules)
local FogView={active=false,grid=nil,version=0,mapRows={},seenBuildings=setmetatable({},{__mode="k"})}

function FogView.Active()
 return FogView.active and FogView.grid~=nil
end

function FogView.Relation(model)
 local player=Players.LocalPlayer
 return TeamClient.Relation(workspace:GetAttribute("TeamMode") or "FFA",player.UserId,player:GetAttribute("TeamId"),model:GetAttribute("OwnerId"),model:GetAttribute("TeamId"))
end

function FogView.VisibleAt(position)
 if not FogView.Active() then return true end
 return FogRules.visibleAt(FogView.grid,position.X,position.Z)
end

function FogView.ExploredAt(position)
 if not FogView.Active() then return true end
 return FogRules.exploredAt(FogView.grid,position.X,position.Z)
end

-- 本機玩家現在能不能看到這個模型：自己與盟友一律可見；敵方單位要在視野內；
-- 建築看過一次後保留（AOE2 的最後已知位置）；資源與中立目標在探索過的區域可見。
function FogView.CanSee(model)
 if not FogView.Active() or typeof(model)~="Instance" or not model.Parent then return true end
 local relation=model:GetAttribute("OwnerId")~=nil and FogView.Relation(model) or "neutral"
 if relation=="own" or relation=="ally" then return true end
 if model:GetAttribute("UnitType") then return FogView.VisibleAt(model:GetPivot().Position) end
 if model:GetAttribute("BuildingType") then return FogView.seenBuildings[model]==true end
 return FogView.ExploredAt(model:GetPivot().Position)
end

return FogView
