-- Engine-independent match validation. Remote payloads never become game configuration.
local TeamRules = require(script.Parent.TeamRules)
local Rules = {}
local sizes = {Small = true, Medium = true, Large = true}
local difficulties = {Easy = true, Normal = true, Hard = true}
local populations = {[60] = true, [100] = true, [150] = true, [200] = true}
local resources = {Standard = true, Rich = true}
local victories = {Conquest = true, Regicide = true, Wonder = true}
local settingFields={expectedPlayers=true,size=true,aiCount=true,difficulty=true,population=true,startingResources=true,victory=true,teamMode=true}

function Rules.finite(value)
 return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Rules.settings(payload, humanCount)
 if type(payload) ~= "table" or not Rules.finite(humanCount) or humanCount%1~=0 or humanCount < 1 or humanCount > 4 then
  return nil, "對局設定無效。"
 end
 for key in pairs(payload) do if not settingFields[key] then return nil,"對局設定包含不支援的欄位。" end end
 local aiCount = payload.aiCount
 if not Rules.finite(aiCount) or aiCount % 1 ~= 0 or aiCount < 0 or aiCount > 3 then
  return nil, "電腦數量必須介於 0 到 3。"
 end
 if not sizes[payload.size] or not difficulties[payload.difficulty]
  or not populations[payload.population] or not resources[payload.startingResources]
  or not victories[payload.victory] then
  return nil, "對局設定包含不支援的選項。"
 end
 if humanCount + aiCount > 4 then return nil, "玩家與電腦合計最多四個陣營。" end
 local mode=payload.teamMode
 if mode==nil then mode="FFA" end -- Existing development callers retain their individual-faction mode.
 local teamMode,message=TeamRules.validateMode(mode,humanCount,aiCount)
 if not teamMode then return nil,message end
 return {
  size = payload.size, aiCount = aiCount, difficulty = payload.difficulty,
  population = payload.population, startingResources = payload.startingResources,
  victory = payload.victory,teamMode=teamMode,
 }
end

function Rules.canSpend(balance, cost)
 if type(balance) ~= "table" or type(cost) ~= "table" then return false end
 for key, value in pairs(cost) do
  if not Rules.finite(value) or value < 0 or not Rules.finite(balance[key]) or balance[key] < value then return false end
 end
 return true
end

function Rules.winner(alive, startingSides)
 if type(alive) ~= "table" then return nil, false end
 if startingSides ~= nil and not Rules.finite(startingSides) then return nil, false end
 if #alive == 0 then return nil, true end
 if #alive == 1 then
  if startingSides ~= nil and startingSides < 2 then return nil, false end
  return alive[1], true
 end
 return nil, false
end

return Rules
