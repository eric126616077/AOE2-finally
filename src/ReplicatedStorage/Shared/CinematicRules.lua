-- 戰鬥預告片（cinematic.project.json）的共用時間軸與鏡頭數學；不碰引擎物件，可在 CLI 測試。
-- 伺服器依同一張表安排部隊動作，客戶端依同一張表切換鏡頭與字幕，兩端只同步一個開始時間。
local Rules={}

-- dip：切入時先從全黑淡出；caption：下方黑邊的字幕。
Rules.Stages={
 {id="intro",seconds=4.5,title="一場決定帝國命運的戰役"},
 {id="muster",seconds=8,caption="兩支大軍在平原上對峙",dip=true},
 {id="standoff",seconds=6,caption="號角響起——"},
 {id="charge",seconds=8,caption="騎士衝鋒",dip=true},
 {id="volley",seconds=6,caption="箭如雨下"},
 {id="clash",seconds=12,caption="刀劍交鋒，寸土必爭"},
 {id="siege",seconds=11,caption="攻城衝車推向敵方城堡",dip=true},
 {id="collapse",seconds=7,caption="城牆崩塌"},
 {id="finale",seconds=10,title="帝國鍛造坊",tagline="採集・建造・征服"},
}
-- 城堡在攻城段開始時降到這個血量比例（起火），倒塌段開始前 CollapseLead 秒降到 1，下一擊即倒。
Rules.FortHPFraction=0.3
Rules.CollapseLead=1.5
-- 攻城段期間城堡血量不低於這個比例，避免在倒塌鏡頭之前就被打倒。
Rules.FortFloorFraction=0.12
-- 電腦每累積 8 名以上軍隊就把全部軍隊派去進攻（簡單難度每 30 秒一次）。
-- 先用誘餌觸發一次，下一波要等 AIWaveSeconds，必須晚於衝鋒開始，對峙段才不會被打斷。
Rules.AIWaveSeconds=30
-- 兩軍前排的間距必須大於 Config.Combat.acquisitionRadius，否則對峙段就會自動開打。
Rules.FrontGap=92
-- 片尾黑底標題停留秒數，之後交還一般遊戲畫面。
Rules.EndHold=4

local starts,byId,total={},{},0
for index,stage in ipairs(Rules.Stages) do
 starts[stage.id]=total
 byId[stage.id]=index
 total+=stage.seconds
end
Rules.Total=total

local function finite(value) return type(value)=="number" and value==value and math.abs(value)~=math.huge end

function Rules.StageStart(id)
 return starts[id]
end

-- 傳回目前的段落、段內秒數、段落序號；開始前為 nil，超過總長固定在最後一段的結尾。
function Rules.StageAt(elapsed)
 if not finite(elapsed) or elapsed<0 then return nil end
 for index,stage in ipairs(Rules.Stages) do
  local start=starts[stage.id]
  if elapsed<start+stage.seconds then return stage,elapsed-start,index end
 end
 local last=Rules.Stages[#Rules.Stages]
 return last,last.seconds,#Rules.Stages
end

function Rules.Clamp01(value)
 if not finite(value) then return 0 end
 return math.clamp(value,0,1)
end

-- 三次緩入緩出：起訖速度為 0，鏡頭不會在切換瞬間抖動。
function Rules.Ease(t)
 t=Rules.Clamp01(t)
 return t<.5 and 4*t*t*t or 1-(-2*t+2)^3/2
end

function Rules.Lerp(a,b,t)
 return a+(b-a)*t
end

-- 在 [0,duration] 內淡入、停留、淡出的可見度；超出範圍為 0。
function Rules.FadeAlpha(t,duration,fadeIn,fadeOut)
 if not finite(t) or not finite(duration) or duration<=0 or t<0 or t>duration then return 0 end
 fadeIn,fadeOut=math.max(fadeIn or 0,0),math.max(fadeOut or 0,0)
 local alpha=1
 if fadeIn>0 then alpha=math.min(alpha,t/fadeIn) end
 if fadeOut>0 then alpha=math.min(alpha,(duration-t)/fadeOut) end
 return Rules.Clamp01(alpha)
end

-- 讓畫面變成 aspect（寬／高）的上下黑邊高度（像素）；畫面本身已經更寬時為 0。
function Rules.Letterbox(width,height,aspect)
 if not finite(width) or not finite(height) or not finite(aspect) or width<=0 or height<=0 or aspect<=0 then return 0 end
 return math.max(0,(height-width/aspect)/2)
end

-- 指數平滑的插值係數；與幀率無關。
function Rules.Damp(dt,speed)
 if not finite(dt) or not finite(speed) or dt<=0 or speed<=0 then return 0 end
 return 1-math.exp(-speed*math.min(dt,0.25))
end

-- 鏡頭震動以「創傷值」累積：事件加值、隨時間衰減，振幅與創傷值平方成正比，小事件幾乎看不出來。
function Rules.AddTrauma(current,amount)
 if not finite(current) then current=0 end
 if not finite(amount) or amount<=0 then return Rules.Clamp01(current) end
 return Rules.Clamp01(current+amount)
end

function Rules.DecayTrauma(current,dt,rate)
 if not finite(current) then return 0 end
 if not finite(dt) or dt<=0 or not finite(rate) or rate<=0 then return Rules.Clamp01(current) end
 return Rules.Clamp01(current-rate*dt)
end

function Rules.ShakeAmplitude(trauma,maximum)
 trauma=Rules.Clamp01(trauma)
 if not finite(maximum) or maximum<=0 then return 0 end
 return maximum*trauma*trauma
end

-- 爆炸／倒塌離鏡頭越近，震動越大；超過 radius 不震。
function Rules.ImpactTrauma(distance,radius,strength)
 if not finite(distance) or not finite(radius) or not finite(strength) or radius<=0 or strength<=0 or distance<0 then return 0 end
 return Rules.Clamp01(strength*(1-distance/radius))
end

return Rules
