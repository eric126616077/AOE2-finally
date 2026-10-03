-- Pure validation. Civilization metadata (name, emblem, colors) cannot carry gameplay values;
-- AOE2-style bonuses and unique units live only in Config.CivilizationBonuses and are audited here:
-- every civilization with bonuses is free and public, every bonus is bounded, and each civilization
-- gets the same number of bonuses and exactly one unique unit. Purchases never change any of it.
local Rules = {}
local metadataFields = {name=true,description=true,emblem=true,accent=true,public=true}
-- 文明加成可用的效果（與科技相同的修正值）；ratio 類是比例，flat 類是加值。
local ratioEffects = {gather=true,gatherFood=true,gatherWood=true,gatherGold=true,gatherStone=true,speed=true,buildingHp=true,buildSpeed=true,tradeGold=true,trainSpeed=true}
local flatEffects = {carry=true,hp=true,armor=true}
local classes = {villager=true,infantry=true,archer=true,cavalry=true,siege=true,monk=true,trade=true}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function Rules.validId(value)
 return type(value)=="string" and #value>0 and #value<=32 and value:match("^[%a][%w_]*$")~=nil
end

-- 單一文明的加成設定；回傳 true 或 false 與原因。
local function auditBonuses(config,id,entry,limits)
 if type(entry)~="table" or type(entry.bonuses)~="table" then return false,"文明加成設定無效："..id end
 if #entry.bonuses~=limits.perCivilization then return false,"每個文明的加成數量必須相同："..id end
 for _,bonus in ipairs(entry.bonuses) do
  if type(bonus)~="table" or type(bonus.text)~="string" or #bonus.text==0 or #bonus.text>120 or type(bonus.effect)~="table" then return false,"文明加成說明無效："..id end
  if bonus.unitClass~=nil and not classes[bonus.unitClass] then return false,"文明加成的單位類別無效："..id end
  local count=0
  for key,value in pairs(bonus.effect) do
   count+=1
   if ratioEffects[key] then
    if not finite(value) or value<=0 or value>limits.ratio then return false,"文明加成超出上限："..id.."."..key end
   elseif flatEffects[key] then
    if not finite(value) or value<=0 or value>limits.flat then return false,"文明加成超出上限："..id.."."..key end
   else return false,"文明加成使用了不允許的效果："..id.."."..key end
  end
  if count==0 then return false,"文明加成沒有效果："..id end
 end
 local unique=config.Units and config.Units[entry.uniqueUnit]
 if type(entry.uniqueUnit)~="string" or type(unique)~="table" or unique.civilization~=id then return false,"文明專屬兵種無效："..id end
 return true
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
 -- 文明加成：只能給已列入清單、免費公開的文明；有加成就每個文明都要有。
 local bonuses=config.CivilizationBonuses
 if bonuses~=nil then
  local limits=config.CivilizationBonusLimits
  if type(bonuses)~="table" or type(limits)~="table" or not finite(limits.ratio) or not finite(limits.flat) or not finite(limits.perCivilization) then return false,"文明加成設定缺失。" end
  for id,entry in pairs(bonuses) do
   if not seen[id] then return false,"加成指向未列入清單的文明："..tostring(id) end
   if config.Civilizations[id].public~=true then return false,"有對戰加成的文明必須免費開放："..id end
   local ok,reason=auditBonuses(config,id,entry,limits)
   if not ok then return false,reason end
  end
  for _,id in ipairs(config.CivilizationOrder) do
   if bonuses[id]==nil then return false,"每個文明都必須有加成："..id end
  end
  -- 專屬兵種只屬於一個文明，且一定是該文明的 uniqueUnit。
  for kind,unit in pairs(config.Units or {}) do
   if unit.civilization~=nil and (not bonuses[unit.civilization] or bonuses[unit.civilization].uniqueUnit~=kind) then return false,"專屬兵種沒有對應的文明："..kind end
  end
 end
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

-- 所有文明共用同一份兵種、建築、科技與時代表；差別只有 bonuses（開局套用）與只有自己能訓練的專屬兵種。
function Rules.gameplay(config,id)
 if not Rules.validId(id) or not config.Civilizations[id] then return nil end
 local entry=config.CivilizationBonuses and config.CivilizationBonuses[id]
 return {units=config.Units,buildings=config.Buildings,technologies=config.Technologies,ages=config.Ages,settings=config.Settings,
  bonuses=entry and entry.bonuses or {},uniqueUnit=entry and entry.uniqueUnit or nil}
end

-- 這個文明能不能訓練某種兵種：一般兵種所有文明都能，專屬兵種只有所屬文明。
function Rules.canTrain(config,id,unitKind)
 local unit=config.Units and config.Units[unitKind]
 if type(unit)~="table" then return false end
 return unit.civilization==nil or unit.civilization==id
end

-- 大廳與通知用的一行說明：「加成一；加成二；專屬兵種：X」。
function Rules.summary(config,id)
 local data=Rules.gameplay(config,id)
 if not data then return "" end
 local parts={}
 for _,bonus in ipairs(data.bonuses) do table.insert(parts,(bonus.text:gsub("。$",""))) end
 local unique=data.uniqueUnit and config.Units[data.uniqueUnit]
 if unique then table.insert(parts,"專屬兵種："..unique.name) end
 return table.concat(parts,"；")
end

return Rules
