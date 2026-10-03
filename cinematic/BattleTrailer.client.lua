-- 僅映射於 cinematic.project.json；正式專案不會載入。
-- Studio CLIENT：戰鬥預告片的「導演」。接手鏡頭、隱藏 HUD，加上電影黑邊、調色、景深、字幕與片尾標題；
-- 依 CinematicRules 的時間軸切換八個鏡頭，鏡頭震動來自附近的石彈落地、衝車撞擊、陣亡與城堡倒塌。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Lighting=game:GetService("Lighting")
local StarterGui=game:GetService("StarterGui")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("CinematicRules"))
local View=require(RS.Shared:WaitForChild("ClientUnitView"))
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
-- 預告片要看見敵軍與城堡：開局前關閉本機戰爭迷霧（FogOfWar.client 在開局時讀同一張設定表）。
Config.Vision.enabled=false

local UP=Vector3.yAxis
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function lerp(a,b,t) return a+(b-a)*t end

-- 黑幕、黑邊、字幕與標題。
local overlay=Instance.new("ScreenGui")
overlay.Name="TrailerOverlay"
overlay.IgnoreGuiInset=true
overlay.ScreenInsets=Enum.ScreenInsets.None
overlay.DisplayOrder=1000
overlay.ResetOnSpawn=false
local function frame(name,parent)
 local f=Instance.new("Frame")
 f.Name=name
 f.BackgroundColor3=Color3.new(0,0,0)
 f.BorderSizePixel=0
 f.Parent=parent
 return f
end
local black=frame("Black",overlay)
black.Size=UDim2.fromScale(1,1)
black.ZIndex=2
local topBar=frame("TopBar",overlay)
local bottomBar=frame("BottomBar",overlay)
topBar.ZIndex,bottomBar.ZIndex=3,3
bottomBar.AnchorPoint=Vector2.new(0,1)
bottomBar.Position=UDim2.fromScale(0,1)
local function label(name,parent,font,maxSize,color)
 local l=Instance.new("TextLabel")
 l.Name=name
 l.BackgroundTransparency=1
 l.Font=font
 l.TextColor3=color or Color3.fromRGB(240,226,196)
 l.TextScaled=true
 l.TextTransparency=1
 l.TextStrokeTransparency=1
 l.ZIndex=4
 local limit=Instance.new("UITextSizeConstraint")
 limit.MaxTextSize=maxSize
 limit.Parent=l
 l.Parent=parent
 return l
end
local caption=label("Caption",bottomBar,Enum.Font.Garamond,30)
caption.AnchorPoint=Vector2.new(.5,.5)
caption.Position=UDim2.fromScale(.5,.5)
caption.Size=UDim2.fromScale(.8,.42)
local title=label("Title",overlay,Enum.Font.Garamond,84,Color3.fromRGB(236,200,120))
title.AnchorPoint=Vector2.new(.5,.5)
title.Position=UDim2.fromScale(.5,.45)
title.Size=UDim2.fromScale(.8,.13)
local tagline=label("Tagline",overlay,Enum.Font.Garamond,34)
tagline.AnchorPoint=Vector2.new(.5,0)
tagline.Position=UDim2.fromScale(.5,.53)
tagline.Size=UDim2.fromScale(.6,.05)
local footnote=label("Footnote",overlay,Enum.Font.Gotham,18,Color3.fromRGB(170,160,140))
footnote.AnchorPoint=Vector2.new(.5,0)
footnote.Position=UDim2.fromScale(.5,.6)
footnote.Size=UDim2.fromScale(.6,.03)
footnote.Text="Roblox 即時戰略｜測試版畫面"
for _,l in ipairs({caption,title,tagline}) do l.TextStrokeColor3=Color3.new(0,0,0) end
-- 開局後才顯示；開局前若卡住，仍看得到原本的出發畫面與錯誤提示。
overlay.Enabled=false
overlay.Parent=playerGui

-- 隱藏 HUD、血條與 Roblox 內建介面；結束時只還原原本開著的。
local hidden={}
local function hide(gui)
 if gui==overlay or not gui:IsA("LayerCollector") or not gui.Enabled then return end
 hidden[gui]=true
 gui.Enabled=false
end
local guiConnection
local coreHidden=false
local function hideInterface()
 for _,gui in ipairs(playerGui:GetChildren()) do hide(gui) end
 guiConnection=playerGui.ChildAdded:Connect(function(gui) task.defer(function() if gui.Parent then hide(gui) end end) end)
 coreHidden=pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All,false) end)
end
local function restoreInterface()
 if guiConnection then guiConnection:Disconnect() end
 for gui in pairs(hidden) do if gui.Parent then gui.Enabled=true end end
 table.clear(hidden)
 if coreHidden then pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All,true) end) end
end

-- 調色：較高對比、略降飽和、偏暖的傍晚光；只在本機。
local grade,bloom,depth,rays
local savedClock
local function addLook()
 savedClock=Lighting.ClockTime
 Lighting.ClockTime=16.9
 grade=Instance.new("ColorCorrectionEffect")
 grade.Name="TrailerGrade"
 grade.Contrast,grade.Saturation,grade.TintColor=.16,-.12,Color3.fromRGB(255,238,218)
 grade.Parent=Lighting
 bloom=Instance.new("BloomEffect")
 bloom.Name="TrailerBloom"
 bloom.Intensity,bloom.Size,bloom.Threshold=.5,28,1.7
 bloom.Parent=Lighting
 depth=Instance.new("DepthOfFieldEffect")
 depth.Name="TrailerDepth"
 depth.NearIntensity,depth.FarIntensity,depth.InFocusRadius,depth.FocusDistance=.2,.32,22,40
 depth.Parent=Lighting
 rays=Instance.new("SunRaysEffect")
 rays.Name="TrailerRays"
 rays.Intensity,rays.Spread=.06,.6
 rays.Parent=Lighting
end
local function removeLook()
 for _,effect in ipairs({grade,bloom,depth,rays}) do if effect then effect:Destroy() end end
 if savedClock then Lighting.ClockTime=savedClock end
end

-- 由伺服器標記的預告片部隊算出鏡頭追蹤點：各兵種重心與正在交戰的位置；每 0.1 秒取樣、每幀平滑。
local units=workspace:WaitForChild("Units")
local buildings=workspace:WaitForChild("Buildings")
local targets,anchors={}, {}
local sampleClock=0
local function sample()
 local sums={}
 local function add(key,p)
  local entry=sums[key]
  if entry then entry.sum+=p; entry.n+=1 else sums[key]={sum=p,n=1} end
 end
 for _,model in ipairs(units:GetChildren()) do
  local side=model:GetAttribute("TrailerSide")
  if side then
   local role=model:GetAttribute("TrailerRole") or "melee"
   local p=flat(View.GetFrame(model).Position)
   add(role..side,p)
   if (role=="melee" or role=="cavalry") and model:GetAttribute("Animation")=="Attack" then add("fight",p) end
  end
 end
 table.clear(targets)
 for key,entry in pairs(sums) do
  if key~="fight" or entry.n>=3 then targets[key]=entry.sum/entry.n end
 end
 for _,model in ipairs(buildings:GetChildren()) do
  if model:GetAttribute("TrailerRole")=="fort" then targets.fort=flat(model:GetPivot().Position) end
 end
end
local function anchor(key,fallback)
 return anchors[key] or fallback
end
local function stepAnchors(dt)
 sampleClock+=dt
 if sampleClock>=.1 then sampleClock=0; sample() end
 local alpha=Rules.Damp(dt,2.4)
 for key,target in pairs(targets) do
  anchors[key]=anchors[key] and anchors[key]:Lerp(target,alpha) or target
 end
end

-- 鏡頭震動：事件加創傷值，隨時間衰減。
local trauma,flash,rumble=0,0,0
local look=Vector3.zero
local function impact(position,radius,strength)
 if typeof(position)~="Vector3" then return end
 trauma=Rules.AddTrauma(trauma,Rules.ImpactTrauma((flat(position)-flat(look)).Magnitude,radius,strength))
end
local watched=setmetatable({}, {__mode="k"})
local function watch(model)
 local kind=model:GetAttribute("UnitType")
 if watched[model] or (kind~="mangonel" and kind~="ram") then return end
 watched[model]=true
 model:GetAttributeChangedSignal("LastAttack"):Connect(function()
  if not model:GetAttribute("TrailerSide") then return end
  local point,flight=model:GetAttribute("AttackPosition"),model:GetAttribute("AttackFlight")
  if typeof(point)~="Vector3" then point=model:GetAttribute("AttackContact") end
  task.delay(type(flight)=="number" and math.clamp(flight,0,3) or .4,function()
   if kind=="ram" then impact(point,45,.3) else impact(point,80,.45) end
  end)
 end)
end
for _,model in ipairs(units:GetChildren()) do watch(model) end
units.ChildAdded:Connect(watch)
units.ChildRemoved:Connect(function(model)
 if model:GetAttribute("TrailerSide") then impact(View.GetFrame(model).Position,35,.07) end
end)
buildings.ChildRemoved:Connect(function(model)
 if model:GetAttribute("TrailerRole")~="fort" then return end
 trauma,flash=1,1
end)

-- 八個鏡頭。u 為段內進度（0→1），e 為緩入緩出後的進度。傳回鏡頭位置、注視點、視角。
local SHOTS={}
local function geometry()
 local center=workspace:GetAttribute("TrailerCenter")
 local axis=workspace:GetAttribute("TrailerAxis")
 if typeof(center)~="Vector3" or typeof(axis)~="Vector3" then return nil end
 local g={center=center,axis=axis,side=Vector3.new(-axis.Z,0,axis.X)}
 g.humanFront=workspace:GetAttribute("TrailerHumanFront") or center-axis*Rules.FrontGap/2
 g.aiFront=workspace:GetAttribute("TrailerAIFront") or center+axis*Rules.FrontGap/2
 g.fort=anchor("fort",workspace:GetAttribute("TrailerFort") or center+axis*110)
 local m1,m2=anchors.melee1,anchors.melee2
 g.clash=anchors.fight or (m1 and m2 and m1:Lerp(m2,.5)) or center
 return g
end
SHOTS.intro=function(g)
 return g.center-g.axis*120+UP*120,g.center,50
end
-- 沿我方前排低空橫移，注視點永遠在鏡頭前方 24 studs，整段都看得到還沒經過的士兵。
SHOTS.muster=function(g,u,e)
 local front,a,s=g.humanFront,g.axis,g.side
 return front+a*9+s*lerp(-44,4,e)+UP*lerp(3.5,5,e),front-a*4+s*lerp(-20,28,e)+UP*3,38
end
-- 從我軍後方升起，揭開兩軍與遠方的城堡。
SHOTS.standoff=function(g,u,e)
 local behind=anchor("melee1",g.humanFront)
 return behind-g.axis*lerp(22,62,e)+UP*lerp(5,64,e)+g.side*lerp(8,-12,e),(g.humanFront+UP*4):Lerp(g.center+g.axis*45,e),lerp(44,52,e)
end
-- 側面跟拍騎士衝鋒，鏡頭略落後、視角逐漸放大。
SHOTS.charge=function(g,u,e)
 local rider=anchor("cavalry1",anchor("melee1",g.humanFront))
 return rider+g.side*lerp(26,19,e)-g.axis*lerp(10,2,e)+UP*4.5,rider+g.axis*14+UP*2,lerp(56,66,e)
end
-- 弓兵肩後仰望箭雨，再壓低看向交戰處。
SHOTS.volley=function(g,u)
 local archers=anchor("archer1",g.humanFront-g.axis*14)
 local tilt=Rules.Ease((u-.35)/.65)
 return archers-g.axis*12+g.side*5+UP*4.5,(archers+g.axis*55+UP*30):Lerp(g.clash+UP*2,tilt),48
end
-- 環繞交戰中心，越轉越近。
SHOTS.clash=function(g,u,e)
 local angle=math.rad(lerp(-35,60,e))
 local around=g.side*math.cos(angle)+g.axis*math.sin(angle)
 return g.clash+around*lerp(30,20,e)+UP*lerp(10,6,e),g.clash+UP*2.5,50
end
-- 跟在衝車旁低角度仰望起火的城堡。
SHOTS.siege=function(g,u,e)
 local rams=anchor("ram1",g.fort-g.axis*40)
 local toward=flat(g.fort-rams)
 toward=toward.Magnitude>1 and toward.Unit or g.axis
 local across=Vector3.new(-toward.Z,0,toward.X)
 return rams-toward*lerp(14,6,e)+across*10+UP*2.8,g.fort+UP*lerp(10,18,e),52
end
-- 遠景看城堡倒塌，緩慢推近。
SHOTS.collapse=function(g,u,e)
 return g.fort-g.axis*lerp(88,70,e)+g.side*30+UP*lerp(17,12,e),g.fort+UP*8,45
end
-- 從戰場上方升高拉遠，淡出到片尾標題。
SHOTS.finale=function(g,u,e)
 return g.center-g.axis*lerp(40,120,e)+g.side*lerp(10,-30,e)+UP*lerp(25,150,e),g.clash:Lerp(g.center,e),50
end

-- 每個鏡頭在中段與尾段各記一次：畫面內有幾個預告片單位、離最近一個多遠、目前震動強度，供無畫面的 Studio 驗證。
local reported,peakTrauma={},0
local function report(stage,u,camera)
 local key=stage.id..(u<.9 and ":mid" or ":end")
 if reported[key] then return end
 reported[key]=true
 local inView,total,closest=0,0,math.huge
 local viewport=camera.ViewportSize
 for _,model in ipairs(units:GetChildren()) do
  if model:GetAttribute("TrailerSide") then
   total+=1
   local p=View.GetFrame(model).Position
   local point,front=camera:WorldToViewportPoint(p)
   if front and point.X>=0 and point.X<=viewport.X and point.Y>=0 and point.Y<=viewport.Y then
    inView+=1
    closest=math.min(closest,(p-camera.CFrame.Position).Magnitude)
   end
  end
 end
 local fort=false
 for _,model in ipairs(buildings:GetChildren()) do
  if model:GetAttribute("TrailerRole")=="fort" then
   local point,front=camera:WorldToViewportPoint(model:GetPivot().Position)
   fort=(front and point.X>=0 and point.X<=viewport.X and point.Y>=0 and point.Y<=viewport.Y) and "inView" or "offscreen"
  end
 end
 print(("[TRAILER_SHOT] %s units=%d/%d closest=%s fort=%s trauma=%.2f peak=%.2f hudHidden=%d"):format(key,inView,total,
  closest<math.huge and ("%.1f"):format(closest) or "none",tostring(fort or "gone"),trauma,peakTrauma,(function() local n=0; for _ in pairs(hidden) do n+=1 end; return n end)()))
 if u>=.9 then peakTrauma=0 end
end

local finished=false
local function finish(message)
 if finished then return end
 finished=true
 Run:UnbindFromRenderStep("TrailerCamera")
 overlay:Destroy()
 removeLook()
 restoreInterface()
 print("[TRAILER] "..message)
end
local function render(dt)
 local camera=workspace.CurrentCamera
 if not camera then return end
 stepAnchors(dt)
 -- HUD 可能在換階段時自己重新開啟。
 for gui in pairs(hidden) do if gui.Enabled then gui.Enabled=false end end
 local startAt=workspace:GetAttribute("TrailerStartAt")
 local g=geometry()
 -- 黑邊在開始前就展開。
 local viewport=camera.ViewportSize
 local bar=Rules.Letterbox(viewport.X,viewport.Y,2.39)
 topBar.Size=UDim2.new(1,0,0,bar)
 bottomBar.Size=UDim2.new(1,0,0,math.max(bar,48))
 if type(startAt)~="number" or not g then black.BackgroundTransparency=0; return end
 local elapsed=workspace:GetServerTimeNow()-startAt
 local stage,t=Rules.StageAt(elapsed)
 if not stage then black.BackgroundTransparency=0; return end
 local u=Rules.Clamp01(t/stage.seconds)
 local ok,position,target,fov=pcall(SHOTS[stage.id],g,u,Rules.Ease(u))
 if not ok then
  -- 單一鏡頭出錯時保留上一幀畫面，只記一次，不讓每幀都丟錯誤。
  if not reported[stage.id..":error"] then reported[stage.id..":error"]=true; warn("[TRAILER] shot "..stage.id.." failed: "..tostring(position)) end
  return
 end
 look=target
 -- 震動：衝鋒段有持續的馬蹄震動，倒塌時一次拉滿。
 rumble=stage.id=="charge" and .32*Rules.Clamp01((u-.15)/.2) or 0
 trauma=Rules.DecayTrauma(math.max(trauma,rumble),dt,1.1)
 local amplitude=Rules.ShakeAmplitude(trauma,math.rad(2.4))
 local clock=os.clock()*14
 local shake=CFrame.Angles(amplitude*math.noise(clock,1.7),amplitude*math.noise(clock,5.3),amplitude*.6*math.noise(clock,9.1))
 local offset=Vector3.new(math.noise(clock,13.9),math.noise(clock,17.3),0)*Rules.ShakeAmplitude(trauma,.7)
 camera.CameraType=Enum.CameraType.Scriptable
 camera.FieldOfView=fov
 camera.CFrame=CFrame.lookAt(position,target)*shake+offset
 depth.FocusDistance=(target-position).Magnitude
 peakTrauma=math.max(peakTrauma,trauma)
 if u>=.5 and elapsed<Rules.Total then report(stage,u,camera) end
 flash=math.max(0,flash-dt*1.6)
 grade.Brightness=flash*.3
 -- 黑幕：切入淡出、片尾淡入。
 local cover=0
 if stage.id=="intro" then cover=1
 elseif stage.dip then cover=1-Rules.Clamp01(t/.45) end
 if stage.id=="finale" then cover=math.max(cover,Rules.Clamp01((t-4.6)/1.2)) end
 black.BackgroundTransparency=1-cover
 -- 字幕與標題。
 local captionAlpha=stage.caption and Rules.FadeAlpha(t-.5,stage.seconds-.8,.45,.45) or 0
 caption.Text=stage.caption or ""
 caption.TextTransparency,caption.TextStrokeTransparency=1-captionAlpha,1-captionAlpha*.6
 local titleAlpha,tagAlpha=0,0
 if stage.id=="intro" then
  title.Text=stage.title
  titleAlpha=Rules.FadeAlpha(t-.6,stage.seconds-1.1,.8,.8)
 elseif stage.id=="finale" then
  -- 片尾標題在畫面全黑後出現，停到 EndHold 結束（段內時間 t 在段尾會被固定，這裡用不受限的時間）。
  local ft=elapsed-Rules.StageStart("finale")
  local hold=stage.seconds+Rules.EndHold-5.6
  title.Text,tagline.Text=stage.title,stage.tagline
  titleAlpha=Rules.FadeAlpha(ft-5.6,hold,1,.8)
  tagAlpha=Rules.FadeAlpha(ft-6.4,hold-.8,1,.8)
 end
 title.TextTransparency,title.TextStrokeTransparency=1-titleAlpha,1-titleAlpha*.5
 tagline.TextTransparency=1-tagAlpha
 footnote.TextTransparency=1-tagAlpha*.8
 if elapsed>=Rules.Total+Rules.EndHold then task.defer(finish,"finished; control returned to the RTS camera") end
end

-- 用正常的大廳指令開一局（1 名玩家＋1 名簡單電腦、小地圖）；Studio Play 與命令列測試伺服器都適用。
local function untilTrue(predicate,seconds)
 local deadline=os.clock()+seconds
 repeat if predicate() then return true end; task.wait(.2) until os.clock()>deadline
 return false
end
if not untilTrue(function() return workspace:GetAttribute("RTSReady")==true and playerGui:FindFirstChild("AOE2_MainGUI")~=nil end,60) then
 warn("[TRAILER] game UI never became ready"); return
end
if workspace:GetAttribute("MatchPhase")~="Playing" then
 local ok,message=pcall(function()
  require(RS.Shared:WaitForChild("LobbyTests")).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 end)
 if not ok then warn("[TRAILER] could not start the match: "..tostring(message)) end
end
if not untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Playing" end,90) then
 warn("[TRAILER] match never reached Playing"); return
end
overlay.Enabled=true
hideInterface()
addLook()
-- RTSCamera 綁在 Camera+1；預告片在它之後覆寫同一幀的鏡頭。
Run:BindToRenderStep("TrailerCamera",Enum.RenderPriority.Camera.Value+2,render)
print("[TRAILER] director ready; waiting for the battlefield")
task.delay(120,function()
 if workspace:GetAttribute("TrailerStartAt")==nil then finish("server never started the trailer; see the [TRAILER] server log") end
end)
