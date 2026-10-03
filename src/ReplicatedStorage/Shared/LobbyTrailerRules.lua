-- 大廳預告片的純邏輯：影片資產 ID、沒有影片時的字卡輪播、全螢幕的 16:9 尺寸與進度。
-- 不碰引擎物件，可在 CLI 測試。
local Rules={}

local function finite(value) return type(value)=="number" and value==value and math.abs(value)~=math.huge end

-- 接受正整數、純數字字串或 rbxassetid:// 開頭的字串；其他一律視為尚未設定。
function Rules.AssetId(value)
 local number
 if type(value)=="number" then
  number=value
 elseif type(value)=="string" then
  local digits=value:match("^%s*rbxassetid://(%d+)%s*$") or value:match("^%s*(%d+)%s*$")
  number=digits and #digits<=16 and tonumber(digits) or nil
 end
 if not finite(number) or number<=0 or number%1~=0 then return nil end
 return "rbxassetid://"..string.format("%d",number)
end

-- 沒有影片時的大螢幕字卡：依預告片分鏡順序取標題或字幕，不重複。
function Rules.Slides(stages)
 local slides,seen={},{}
 for _,stage in ipairs(type(stages)=="table" and stages or {}) do
  local heading=type(stage.title)=="string" and stage.title or (type(stage.caption)=="string" and stage.caption) or nil
  if heading and heading~="" and not seen[heading] then
   seen[heading]=true
   table.insert(slides,{heading=heading,detail=type(stage.tagline)=="string" and stage.tagline or nil,title=stage.title~=nil})
  end
 end
 return slides
end

-- 傳回目前字卡序號與淡入淡出透明度（0 為完全顯示）；每張字卡頭尾各 fade 秒。
function Rules.SlideAt(count,elapsed,seconds,fade)
 if type(count)~="number" or count<1 or not finite(elapsed) or not finite(seconds) or seconds<=0 then return nil,1 end
 elapsed=math.max(elapsed,0)
 local index=math.floor(elapsed/seconds)%count+1
 local t=elapsed%seconds
 fade=finite(fade) and math.clamp(fade,0,seconds/2) or 0
 if fade<=0 then return index,0 end
 local edge=math.min(t,seconds-t)
 return index,1-math.clamp(edge/fade,0,1)
end

-- 在可用範圍內放下最大的 aspect 比例畫面（預設 16:9），多出的部分留黑邊。
function Rules.Fit(width,height,aspect)
 aspect=finite(aspect) and aspect>0 and aspect or 16/9
 if not finite(width) or not finite(height) or width<=0 or height<=0 then return 0,0 end
 if width/height>aspect then return height*aspect,height end
 return width,width/aspect
end

-- 進度 0–1；影片長度未知時為 0。
function Rules.Progress(position,length)
 if not finite(position) or not finite(length) or length<=0 then return 0 end
 return math.clamp(position/length,0,1)
end

return Rules
