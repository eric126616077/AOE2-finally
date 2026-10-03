-- 市集浮動價格與進貢的純規則（AOE2 式）；伺服器扣款與客戶端報價共用，不依賴 Roblox 物件。
-- price 是每 batch 單位的基準價（黃金）。所有玩家共用同一組價格：買入讓價格上漲、賣出讓價格下跌。
local MarketRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function MarketRules.valid(config)
 return type(config)=="table" and finite(config.basePrice) and finite(config.buyMarkup) and finite(config.sellMarkdown)
  and finite(config.step) and finite(config.minPrice) and finite(config.maxPrice) and finite(config.batch)
  and config.minPrice>0 and config.minPrice<=config.basePrice and config.basePrice<=config.maxPrice
  and config.buyMarkup>=1 and config.sellMarkdown>0 and config.sellMarkdown<=1 and config.step>=0 and config.batch>0
end

-- 目前價格；缺少或無效時回到基準價，並限制在上下限之內。
function MarketRules.price(value,config)
 if not finite(value) then return config.basePrice end
 return math.clamp(math.floor(value+0.5),config.minPrice,config.maxPrice)
end

-- 回傳 (買入 batch 單位要付的黃金, 賣出 batch 單位得到的黃金)。賣出至少 1 黃金，買入一定高於賣出。
function MarketRules.quote(value,config)
 local price=MarketRules.price(value,config)
 local buy=math.max(1,math.floor(price*config.buyMarkup+0.5))
 local sell=math.max(1,math.floor(price*config.sellMarkdown+0.5))
 if sell>=buy then sell=math.max(1,buy-1) end
 return buy,sell
end

-- 成交後的新價格；direction 為 "Buy" 或 "Sell"，其他值不改價。
function MarketRules.after(value,direction,config)
 local price=MarketRules.price(value,config)
 if direction=="Buy" then return math.min(config.maxPrice,price+config.step) end
 if direction=="Sell" then return math.max(config.minPrice,price-config.step) end
 return price
end

-- 進貢：送出 amount，另付手續費。feeCut 為科技減免比例（0～1）。回傳 (總共要付的數量, 手續費)。
function MarketRules.tribute(amount,fee,feeCut)
 if not finite(amount) or amount<=0 or amount%1~=0 or not finite(fee) or fee<0 then return nil end
 local cut=finite(feeCut) and math.clamp(feeCut,0,1) or 0
 local charge=math.floor(amount*fee*(1-cut)+0.5)
 return amount+charge,charge
end

-- 允許的進貢數量（設定中的其中一個值）。
function MarketRules.tributeAmount(amount,amounts)
 if not finite(amount) or type(amounts)~="table" then return false end
 for _,allowed in ipairs(amounts) do if allowed==amount then return true end end
 return false
end

return MarketRules
