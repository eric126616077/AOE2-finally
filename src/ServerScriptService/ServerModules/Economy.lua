local Economy = {}

-- Never mutate any balance until every part of the server-defined cost is affordable.
function Economy.spend(player, cost)
 for key, value in pairs(cost) do
  if (player:GetAttribute(key) or 0) < value then return false end
 end
 for key, value in pairs(cost) do
  player:SetAttribute(key, player:GetAttribute(key) - value)
 end
 return true
end

return Economy
