-- 本機特效物件池：投射物、命中、採集、外框等短暫特效重複使用，不必每次 Instance.new / Destroy。
-- 純邏輯；建立、隱藏與銷毀由呼叫端注入，所以能在 Luau CLI 測試。
-- 每次取出都會換一個新的租約編號：舊的計時器拿著過期租約歸還時不會誤收回已被重用的物件。
local Pool={}
Pool.__index=Pool
-- options.build(key) -> record（table）；options.hide(record) 歸還時隱藏；options.destroy(record) 永久移除。
-- options.limit 同時使用中的上限；options.maxIdle 每種物件保留的閒置數量上限。
function Pool.new(options)
 assert(type(options)=="table" and type(options.build)=="function" and type(options.hide)=="function"
  and type(options.destroy)=="function","effect pool needs build / hide / destroy")
 return setmetatable({build=options.build,hide=options.hide,destroy=options.destroy,
  limit=math.max(0,tonumber(options.limit) or math.huge),maxIdle=math.max(0,tonumber(options.maxIdle) or 0),
  idle={},active={},count=0,created=0,reused=0},Pool)
end
-- 回傳 (record, lease)；達到上限時回傳 nil，呼叫端照舊略過這次特效。
function Pool:Acquire(key)
 if self.count>=self.limit then return nil end
 local stock=self.idle[key]
 local record=stock and table.remove(stock)
 if record then
  self.reused+=1
 else
  record=self.build(key)
  if type(record)~="table" then return nil end
  record.key=key
  self.created+=1
 end
 record.lease=(record.lease or 0)+1
 self.active[record]=true
 self.count+=1
 return record,record.lease
end
-- 使用中的物件換手（例如飛行中的箭變成插在地上的箭）：舊的到期計時器因此失效。
function Pool:Renew(record)
 if not self.active[record] then return nil end
 record.lease+=1
 return record.lease
end
-- lease 為 nil 時無條件歸還；租約不符（已被重用）或不是使用中時不做事。
function Pool:Release(record,lease)
 if not self.active[record] or (lease~=nil and record.lease~=lease) then return false end
 self.active[record]=nil
 self.count-=1
 record.lease+=1
 self.hide(record)
 local stock=self.idle[record.key]
 if not stock then stock={}; self.idle[record.key]=stock end
 if #stock<self.maxIdle then table.insert(stock,record) else self.destroy(record) end
 return true
end
function Pool:ReleaseWhere(predicate)
 local list={}
 for record in pairs(self.active) do if predicate(record) then table.insert(list,record) end end
 for _,record in ipairs(list) do self:Release(record) end
 return #list
end
function Pool:IdleCount()
 local total=0
 for _,stock in pairs(self.idle) do total+=#stock end
 return total
end
-- 全部歸還並銷毀閒置物件（腳本移除時）。
function Pool:Clear()
 self:ReleaseWhere(function() return true end)
 for _,stock in pairs(self.idle) do
  for _,record in ipairs(stock) do self.destroy(record) end
 end
 table.clear(self.idle)
end
return Pool
