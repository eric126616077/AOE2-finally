-- No Marketplace requests or receipt grants occur here. An unconfigured catalog stays closed.
local Commerce = {}
local allowedFields={name=true,category=true,gamePassId=true,civilizationId=true,cosmeticId=true}

local function integer(value)
 return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge and value>=0 and value%1==0 and value<=9007199254740991
end

function Commerce.audit(config)
 local commerce=type(config)=="table" and config.Commerce
 if type(commerce)~="table" or type(commerce.enabled)~="boolean" or type(commerce.catalog)~="table" then return false,"商店設定無效。" end
 local ids={}
 for key,entry in pairs(commerce.catalog) do
  if type(key)~="string" or #key==0 or #key>64 or type(entry)~="table" then return false,"商品設定無效。" end
  for field in pairs(entry) do if not allowedFields[field] then return false,"商品不得授予對戰優勢。" end end
  if entry.category~="cosmetic" and entry.category~="civilization" then return false,"商品只能是造型或文明。" end
  if type(entry.name)~="string" or #entry.name==0 or #entry.name>150 or not integer(entry.gamePassId) then return false,"商品名稱或通行證編號無效。" end
  if entry.gamePassId>0 then
   if ids[entry.gamePassId] then return false,"通行證編號重複。" end
   ids[entry.gamePassId]=true
  end
  if entry.category=="civilization" then
   if type(entry.civilizationId)~="string" or not config.Civilizations[entry.civilizationId] or entry.cosmeticId~=nil then return false,"文明商品設定無效。" end
  elseif type(entry.cosmeticId)~="string" or #entry.cosmeticId==0 or #entry.cosmeticId>64 or entry.civilizationId~=nil then return false,"造型商品設定無效。" end
 end
 return true
end

function Commerce.purchase(config,key)
 if type(key)~="string" or #key==0 or #key>64 then return nil,"商品不存在。" end
 local valid=Commerce.audit(config)
 if not valid or not config.Commerce.enabled then return nil,"商店尚未開放；目前三個文明皆可免費使用。" end
 local entry=config.Commerce.catalog[key]
 if not entry or entry.gamePassId==0 then return nil,"此商品尚未上架。" end
 return entry
end

return Commerce
