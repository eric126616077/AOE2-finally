-- Pure validation. Civilization metadata deliberately cannot override gameplay configuration.
local Rules = {}
local metadataFields = {name=true,description=true,emblem=true,accent=true,public=true}

function Rules.validId(value)
 return type(value)=="string" and #value>0 and #value<=32 and value:match("^[%a][%w_]*$")~=nil
end

function Rules.audit(config)
 if type(config)~="table" or type(config.Civilizations)~="table" or type(config.CivilizationOrder)~="table" then return false,"文明設定缺失。" end
 local seen,count={},0
 for _,id in ipairs(config.CivilizationOrder) do
  local entry=config.Civilizations[id]
  if not Rules.validId(id) or seen[id] or type(entry)~="table" then return false,"文明清單無效。" end
  seen[id],count=true,count+1
  for key in pairs(entry) do if not metadataFields[key] then return false,"文明不得設定對戰數值或付費優勢。" end end
  for _,key in ipairs({"name","description","emblem"}) do
   if type(entry[key])~="string" or #entry[key]==0 or #entry[key]>300 then return false,"文明說明無效。" end
  end
  if type(entry.public)~="boolean" then return false,"文明公開狀態無效。" end
 end
 for id in pairs(config.Civilizations) do if not seen[id] then return false,"文明未列入清單。" end end
 if count<1 or not seen[config.DefaultCivilization] or not config.Civilizations[config.DefaultCivilization].public then return false,"預設文明必須免費開放。" end
 return true
end

function Rules.canSelect(config,phase,id)
 if phase~="Lobby" then return false,"文明只能在大廳選擇；本局文明已鎖定。" end
 if not Rules.validId(id) then return false,"請選擇有效的文明。" end
 local entry=config.Civilizations[id]
 if not entry or not entry.public then return false,"此文明尚未開放。" end
 return true,entry
end

function Rules.resolve(config,id)
 local entry=Rules.validId(id) and config.Civilizations[id]
 if entry and entry.public then return id,entry end
 return config.DefaultCivilization,config.Civilizations[config.DefaultCivilization]
end

-- Every identity uses the same tables, including prices, population, training and technology.
function Rules.gameplay(config,id)
 if not Rules.validId(id) or not config.Civilizations[id] then return nil end
 return {units=config.Units,buildings=config.Buildings,technologies=config.Technologies,ages=config.Ages,settings=config.Settings}
end

return Rules
