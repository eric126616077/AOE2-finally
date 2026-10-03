-- 陣亡倒地、建築倒塌、資源耗盡消失的純本機動畫時序。只影響畫面；
-- 死亡、摧毀與資源移除仍由伺服器決定，客戶端從不延後或改變它們。
local Rules={
 -- 單位倒地：前 80% 時間加速倒下，最後 20% 輕微回彈落定。
 FallSeconds=.55,FallSettle=.2,FallBounce=.06,
 -- 屍體在伺服器移除前最後這段時間沉入地面並淡出。
 FadeSeconds=1.5,SinkDepth=1.2,
 -- 建築倒塌：搖晃、下沉、傾斜並淡出。
 CollapseSeconds=1.8,CollapseShake=.35,CollapseTilt=.12,CollapseDust=5,
 -- 資源耗盡：樹木倒下，其他資源沉降淡出。
 TreeFallSeconds=1.1,ResourceFadeSeconds=.7,
 -- 同時播放的上限；超過時直接照舊立即出現 / 消失。
 -- 伺服器同時保留的倒塌／資源複本上限（Ruins），以及單棟建築複製的零件上限。
 MaxFalls=32,MaxCollapses=4,MaxRuins=24,MaxCollapseParts=180,MaxDistance=600,
}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function clamp01(value)
 if not finite(value) then return 1 end
 return math.clamp(value,0,1)
end
-- 倒地進度 0..1：重力式加速，到底後回彈一點再落定。永遠不超過 1，避免外插穿地。
function Rules.FallProgress(t)
 t=clamp01(t)
 local split=1-Rules.FallSettle
 if t<split then
  local x=t/split
  return x*x
 end
 return 1-Rules.FallBounce*math.sin(math.pi*(t-split)/Rules.FallSettle)
end
-- 屍體淡出：回傳 (透明度 0..1, 下沉深度)。expires 與 now 都是伺服器時間。
function Rules.CorpseFade(now,expires)
 if not finite(now) or not finite(expires) then return 0,0 end
 local left=expires-now
 if left>=Rules.FadeSeconds then return 0,0 end
 local x=1-clamp01(left/Rules.FadeSeconds)
 return x*x,x*Rules.SinkDepth
end
-- 建築倒塌：回傳 (下沉比例 0..1, 傾斜角, 水平搖晃, 透明度)。
-- seed 讓每棟建築往不同方向倒，但所有玩家看到同一方向。
function Rules.Collapse(t,seed)
 t=clamp01(t)
 seed=finite(seed) and seed or 0
 local sink=t*t*(3-2*t)
 local tilt=Rules.CollapseTilt*sink*(seed<.5 and -1 or 1)
 local shake=Rules.CollapseShake*(1-t)*math.sin(t*38+seed*6.28)
 local fade=t<.6 and 0 or ((t-.6)/.4)^2
 return sink,tilt,shake,fade
end
-- 樹倒下：回傳 (倒下角度 0..pi/2, 透明度)。最後三分之一時間淡出。
function Rules.TreeFall(t)
 t=clamp01(t)
 local fallEnd=.7
 local angle=t<fallEnd and (t/fallEnd)^2*math.pi/2 or math.pi/2
 local fade=t<fallEnd and 0 or (t-fallEnd)/(1-fallEnd)
 return angle,fade
end
-- 一般資源消失：回傳 (下沉比例, 透明度)。
function Rules.ResourceFade(t)
 t=clamp01(t)
 return t*t,t
end
-- 由座標得出穩定的 [0,1) 值，用來決定倒向；同一位置在所有客戶端一致。
function Rules.Seed(x,z)
 if not finite(x) or not finite(z) then return 0 end
 local n=math.floor(x*2+.5)*73856093+math.floor(z*2+.5)*83492791
 n=(n%233280*9301+49297)%233280
 return n/233280
end
-- 是否還能開新的動畫；超過上限就讓模型照舊瞬間處理。
function Rules.Admit(active,limit)
 return type(active)=="number" and type(limit)=="number" and active<limit
end
return Rules
