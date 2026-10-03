-- Test-only LocalScript, mapped only by anim-validation.project.json.
-- Studio CLIENT：新單位出場、箭落地與特效池（UnitMotion.client.lua，d116b10）的命令列驗證。
-- 只讀實際實例與實際 PlayerScripts 的 RTSMotionProbe（Command Bar／測試腳本的 require 快取與遊戲腳本分開）。
--
-- 1 位客戶端（Player1，主控）：以正常大廳指令開局（1 真人＋1 簡單電腦、Small、豐富資源），依序驗證
--  A. 市鎮中心以正式 Train 訓練村民：SpawnFrom／SpawnAt、第一個畫面在建築邊緣、單調走向出生點、面向外、
--     依 MotionRules.SpawnDuration 準時停在伺服器 Root（位置與朝向），外觀零件跟著顯示位置，播放步態，Root 不動。
--  B. 非正方形占地：馬廄（4×3）連續訓練 4 位斥候騎兵，伺服器確認長邊與短邊都有走出（遊戲中可旋轉的只有城門，
--     它不訓練也不駐軍，所以旋轉占地不會出場；伺服器以占地 CFrame 計算，旋轉也成立）。
--  C. 離開駐軍：2 位村民以正式 Garrison 進入市鎮中心，再以 Ungarrison 離開。
--  D. 集結點：正式 Rally 後訓練斥候騎兵；出場位移與伺服器移動疊加、沒有瞬移、收斂到移動中的 Root。
--  E. 箭：追著跑開的電腦村民射擊 → 地面 StuckArrow（38°、箭頭埋入地面）；射擊電腦房屋 → 插在可見牆面、
--     沿飛行方向；房屋被摧毀時插在上面的箭立即消失；自然到期的箭在 StuckSeconds 移除、最後 StuckFadeSeconds 淡出。
--  F. 降低動態效果：已插著的箭立即清除、不再插箭、沒有投射物；新單位直接在出生點（不出場）；暫時特效資料夾清空。
--  G. 特效池：重用次數 > 0、閒置時 effectsActive=0、RTSClientEffects 與 RTSStuckArrows 為空、沒有 ArrowEffect、
--     建立數量有上限；投降回大廳後同樣清空。
-- 2 位客戶端：Player2 加入同一房間，在自己的主城獨立驗證一部分（市鎮中心訓練村民的出場、射擊電腦房屋的插箭與到期），
--  把結果回報給伺服器；Player1 把它算進總結。
-- 輸出：Player1 為 [ANIM] PASS／FAIL／INFO，最後一行 [ANIM] COMPLETE n passed, 0 failed 或 [ANIM] INCOMPLETE …；
--       Player2 為 [ANIM PlayerN] …（最後 DONE），伺服器為 [ANIM SERVER] …。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local Motion=require(RS:WaitForChild("Shared"):WaitForChild("MotionRules"))
local Remains=require(RS.Shared.RemainsRules)
local CameraFocus=require(RS.Shared.CameraFocus)

-- 從腳本啟動起算的全域逾時；逾時印出 INCOMPLETE，不會無限等待。
local TIMEOUT=270
-- UnitMotion 的 MAX_EFFECTS（同時使用中的暫時特效上限）；物件池上限另加 RemainsRules.MaxStuck。
local MAX_TRANSIENT=80
local label="[ANIM] "
local role=nil
local passed,failed=0,0
local stage="初始化"
local finished=false
local function finish(text)
 if finished then return end
 finished=true
 print(label..text)
end
local function check(condition,message,detail)
 local ok=condition and true or false
 if finished then return ok end
 if ok then passed+=1 else failed+=1 end
 local text=label..(ok and "PASS " or "FAIL ")..message..(detail~=nil and ("  ("..tostring(detail)..")") or "")
 if ok then print(text) else warn(text) end
 return ok
end
local function info(text) if not finished then print(label.."INFO "..text) end end
local function waitFor(predicate,seconds)
 local deadline=os.clock()+math.max(seconds,0)
 repeat
  local value=predicate()
  if value then return value end
  Run.Heartbeat:Wait()
 until os.clock()>deadline or finished
 return predicate() or nil
end
local function serverNow() return workspace:GetServerTimeNow() end
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function turn(v,degrees) return CFrame.Angles(0,math.rad(degrees),0):VectorToWorldSpace(v) end
local function angleBetween(a,b)
 local _,_,_,r00,_,_,_,r11,_,_,_,r22=a:ToObjectSpace(b):GetComponents()
 return math.acos(math.clamp((r00+r11+r22-1)/2,-1,1))
end
local function children(folder) return folder and #folder:GetChildren() or -1 end

-- 實際 PlayerScripts 的 UnitMotion 與 RTSMotionProbe ------------------------------------
local function motionProbe()
 local scripts=player:FindFirstChild("PlayerScripts")
 local probe=scripts and scripts:FindFirstChild("RTSMotionProbe")
 return probe and probe:IsA("BindableFunction") and probe or nil
end
local function motionReady()
 local scripts=player:FindFirstChild("PlayerScripts")
 local motion=scripts and scripts:FindFirstChild("UnitMotion")
 return motion~=nil and motion:GetAttribute("RTSMotionReady")==true and motionProbe()~=nil
  and workspace:FindFirstChild("RTSClientEffects")~=nil and workspace:FindFirstChild("RTSStuckArrows")~=nil
end
local function probeStats()
 local probe=motionProbe()
 if not probe then return nil end
 local ok,result=pcall(function() return probe:Invoke() end)
 return ok and type(result)=="table" and type(result.stats)=="table" and result.stats or nil
end
local function statsText(stats)
 if not stats then return "沒有 stats" end
 return string.format("active %s、idle %s、created %s、reused %s、stuck %s",tostring(stats.effectsActive),tostring(stats.effectsIdle),
  tostring(stats.effectsCreated),tostring(stats.effectsReused),tostring(stats.stuckArrows))
end
local function effectsFolder() return workspace:FindFirstChild("RTSClientEffects") end
local function stuckFolder() return workspace:FindFirstChild("RTSStuckArrows") end
local function countNamed(name)
 local count=0
 for _,item in ipairs(workspace:GetDescendants()) do if item.Name==name then count+=1 end end
 return count
end

-- 新單位出場的取樣 ---------------------------------------------------------------------
-- 本機用同一個 MotionRules 時間軸重建「沒有出場時」的顯示位置（base）；顯示位置減 base 就是出場位移。
-- 只追蹤自己的新單位（有 SpawnFrom 屬性），每個 Heartbeat 讀一次實際的 GetFrame、Root 與 Body。
local frameClock=os.clock()
Run.RenderStepped:Connect(function() frameClock=os.clock() end)
local spawnRecs,sampling={}, {}
local function startSpawn(unit,addedClock,addedServer,late)
 local root=unit.PrimaryPart
 local from,at=unit:GetAttribute("SpawnFrom"),unit:GetAttribute("SpawnAt")
 if not root then return end
 local rec={unit=unit,kind=unit:GetAttribute("UnitType"),from=from,at=at,late=late,appearClock=addedClock,appearServer=addedServer,
  reduced=player:GetAttribute("ReducedMotion")==true,speed=unit:GetAttribute("Speed"),root0=root.CFrame,samples={},
  timeline=Motion.New(addedClock,root.CFrame),lastRoot=root.CFrame,rootMoved=0,lastRootMove=nil,stopClock=addedClock+Motion.SpawnMax+2.5}
 rec.connection=root:GetPropertyChangedSignal("CFrame"):Connect(function()
  local cf=root.CFrame
  if cf==rec.lastRoot then return end
  local distance=(cf.Position-rec.lastRoot.Position).Magnitude
  local now=os.clock()
  if distance>.002 then rec.lastRootMove=now end
  rec.rootMoved=math.max(rec.rootMoved,(cf.Position-rec.root0.Position).Magnitude)
  Motion.Push(rec.timeline,now,cf,Motion.IsDiscontinuity(distance,rec.speed))
  rec.lastRoot=cf
 end)
 table.insert(spawnRecs,rec)
 sampling[rec]=true
end
local function watchUnit(unit)
 if not unit:IsA("Model") or unit:GetAttribute("OwnerId")~=player.UserId then return end
 -- 客戶端的 ChildAdded 可能早於子零件複製。UnitMotion 也是等 Root 與外觀零件到了才開始追蹤，
 -- 所以等 PrimaryPart 出現，並以那一刻為「出現時間」。
 if not unit.PrimaryPart then
  local connection
  connection=unit:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
   if unit.PrimaryPart then connection:Disconnect(); watchUnit(unit) end
  end)
  task.delay(3,function() connection:Disconnect() end)
  return
 end
 local addedClock,addedServer=os.clock(),serverNow()
 if unit:GetAttribute("SpawnFrom")~=nil then startSpawn(unit,addedClock,addedServer,false); return end
 -- UnitMotion 只在追蹤當下讀屬性：晚到的屬性代表不會播放出場，記錄下來由檢查判定失敗。
 local connection
 connection=unit:GetAttributeChangedSignal("SpawnFrom"):Connect(function()
  connection:Disconnect()
  if os.clock()-addedClock<2 then startSpawn(unit,addedClock,addedServer,true) end
 end)
 task.delay(2,function() connection:Disconnect() end)
end
Run.Heartbeat:Connect(function()
 local probe
 for rec in pairs(sampling) do
  if os.clock()>rec.stopClock or not rec.unit.Parent then
   sampling[rec]=nil
   rec.connection:Disconnect()
   rec.done=true
   continue
  end
  probe=probe or motionProbe()
  if not probe then continue end
  local ok,state=pcall(probe.Invoke,probe,rec.unit)
  local root=rec.unit.PrimaryPart
  if ok and type(state)=="table" and typeof(state.frame)=="CFrame" and root then
   local before,after,alpha=Motion.Sample(rec.timeline,frameClock)
   local base=before==after and before or before:Lerp(after,alpha)
   table.insert(rec.samples,{t=frameClock,visible=state.visible==true,display=state.frame,base=base,root=root.CFrame,
    body=typeof(state.body)=="Instance" and state.body:IsA("BasePart") and state.body.CFrame or nil,
    bodyOffset=typeof(state.bodyOffset)=="CFrame" and state.bodyOffset or nil})
  end
 end
end)

-- 插著的箭 ---------------------------------------------------------------------------
local surfaceRay=RaycastParams.new()
surfaceRay.FilterType=Enum.RaycastFilterType.Include
local function buildingOf(instance)
 local folder=workspace:FindFirstChild("Buildings")
 local model=instance
 while model and model.Parent~=folder do model=model.Parent end
 return model
end
-- 與 UnitMotion 相同：穿過透明零件（占地）繼續找看得見的建築表面。
local function visibleSurface(from,direction,distance)
 local folder=workspace:FindFirstChild("Buildings")
 if not folder then return nil end
 surfaceRay.FilterDescendantsInstances={folder}
 local travelled=0
 for _=1,6 do
  local result=workspace:Raycast(from,direction*distance,surfaceRay)
  if not result then return nil end
  local step=(result.Position-from).Magnitude
  travelled+=step
  if result.Instance.Transparency<1 then return result,travelled end
  distance-=step+.05
  travelled+=.05
  if distance<=0 then return nil end
  from=result.Position+direction*.05
 end
 return nil
end
local stuck={list={},live={},reducedAdds=0,maxLive=0}
local reducedToggles={}
local buildingGone={}
local transientAdds={arrowWhileReduced=0,projectilesWhileReduced=0}
-- UnitMotion 在降低動態效果時不該產生的移動特效（WorkEffect 不受此設定影響，不列入）。
local PROJECTILES={ArrowEffect=true,JavelinEffect=true,StoneEffect=true,BulletEffect=true,MuzzleSmoke=true,ImpactEffect=true}
local function onStuck(part)
 -- 事件延後觸發時，同一格就被移除（或已被物件池重用）的箭讀不到插著的姿勢，略過。
 if not part:IsA("BasePart") or part.Parent~=stuckFolder() then return end
 local cf,size=part.CFrame,part.Size
 local look=cf.LookVector
 -- 箭頭在前方（-Z 方向，即 LookVector）；埋入 StuckBury 比例的長度：露出部分與表面的交點。
 local entry=cf.Position+look*(size.Z*(.5-Remains.StuckBury))
 local rec={part=part,name=part.Name,appear=os.clock(),cf=cf,look=look,length=size.Z,entry=entry,
  pitch=math.asin(math.clamp(-look.Y,-1,1)),reduced=player:GetAttribute("ReducedMotion")==true,
  maxT=part.Transparency,earlyT=part.Transparency}
 local hit,distance=visibleSurface(entry-look*1.5,look,3)
 rec.hit,rec.hitDistance=hit,distance
 rec.lodged=hit~=nil and distance>=1.2 and distance<=1.8
 rec.building=rec.lodged and buildingOf(hit.Instance) or nil
 stuck.live[part]=rec
 table.insert(stuck.list,rec)
 if rec.reduced then stuck.reducedAdds+=1 end
 local live=0
 for _ in pairs(stuck.live) do live+=1 end
 stuck.maxLive=math.max(stuck.maxLive,live)
end
local function onUnstuck(part)
 local rec=stuck.live[part]
 if not rec then return end
 stuck.live[part]=nil
 rec.removed=os.clock()
 rec.removedPhase=workspace:GetAttribute("MatchPhase")
end
Run.Heartbeat:Connect(function()
 local now=os.clock()
 for part,rec in pairs(stuck.live) do
  local transparency=part.Transparency
  rec.maxT=math.max(rec.maxT,transparency)
  if now-rec.appear<Remains.StuckSeconds-Remains.StuckFadeSeconds-.1 then rec.earlyT=math.max(rec.earlyT,transparency) end
 end
end)
local function liveOn(building)
 local count=0
 for _,rec in pairs(stuck.live) do if rec.building==building then count+=1 end end
 return count
end
local function liveCount()
 local count=0
 for _ in pairs(stuck.live) do count+=1 end
 return count
end
local function attachFolders()
 local stuckArrows=workspace:WaitForChild("RTSStuckArrows",30)
 local effects=workspace:WaitForChild("RTSClientEffects",30)
 local buildings=workspace:WaitForChild("Buildings",30)
 local units=workspace:WaitForChild("Units",30)
 assert(stuckArrows and effects and buildings and units,"RTSStuckArrows／RTSClientEffects／Buildings／Units 不存在")
 stuckArrows.ChildAdded:Connect(onStuck)
 stuckArrows.ChildRemoved:Connect(onUnstuck)
 for _,part in ipairs(stuckArrows:GetChildren()) do onStuck(part) end
 effects.ChildAdded:Connect(function(item)
  if player:GetAttribute("ReducedMotion")~=true then return end
  if item.Name=="ArrowEffect" or item.Name=="JavelinEffect" then transientAdds.arrowWhileReduced+=1 end
  if PROJECTILES[item.Name] then transientAdds.projectilesWhileReduced+=1 end
 end)
 buildings.ChildRemoved:Connect(function(model) buildingGone[model]=os.clock() end)
 units.ChildAdded:Connect(watchUnit)
 player:GetAttributeChangedSignal("ReducedMotion"):Connect(function() table.insert(reducedToggles,os.clock()) end)
end

-- 出場分析 ---------------------------------------------------------------------------
-- mode："plain"（出生點不動）、"rally"（立刻前往集結點）、"reduced"（降低動態效果）。回傳是否全部通過。
local function insideFootprint(building,point)
 local footprint=building and building.PrimaryPart
 if not footprint or typeof(point)~="Vector3" then return false end
 local here=footprint.CFrame:PointToObjectSpace(Vector3.new(point.X,footprint.Position.Y,point.Z))
 return math.abs(here.X)<=footprint.Size.X/2+1 and math.abs(here.Z)<=footprint.Size.Z/2+1
end
local function findSpawn(kind,building,since,seconds)
 return waitFor(function()
  for _,rec in ipairs(spawnRecs) do
   if not rec.claimed and rec.kind==kind and rec.appearClock>=since and insideFootprint(building,rec.from) then
    rec.claimed=true
    return rec
   end
  end
  return nil
 end,seconds)
end
local spawnsChecked=0
local function analyzeSpawn(rec,name,mode)
 local before=failed
 if mode=="rally" then rec.stopClock=math.max(rec.stopClock,rec.appearClock+10) end
 waitFor(function() return rec.done end,rec.stopClock-os.clock()+1)
 spawnsChecked+=1
 if not check(not rec.late and typeof(rec.from)=="Vector3" and type(rec.at)=="number",name.."：單位一出現（UnitMotion 追蹤當下）就帶 SpawnFrom／SpawnAt",
  rec.late and "屬性晚到" or nil) then return false end
 local age=rec.appearServer-rec.at
 check(age>-.25 and age<Motion.SpawnFresh,name.."：客戶端在 SpawnFresh（"..Motion.SpawnFresh.." 秒）內收到新單位",string.format("出現時已過 %.2f 秒",age))
 local offset=flat(rec.from)-flat(rec.root0.Position)
 local distance=offset.Magnitude
 local toward=distance>1e-3 and offset.Unit or Vector3.zero
 local expected=Motion.SpawnDuration(distance,rec.speed)
 local first
 for _,sample in ipairs(rec.samples) do if sample.visible then first=sample; break end end
 if not check(first~=nil and first.t-rec.appearClock<=.45,name.."：出場時單位在畫面內（UnitMotion 會繪製）",
  first and string.format("出現後 %.2f 秒第一次繪製",first.t-rec.appearClock) or string.format("%d 個取樣都不在畫面內",#rec.samples)) then return false end
 local function walk(sample) return flat(sample.display.Position)-flat(sample.base.Position) end
 if mode=="reduced" then
  check(rec.reduced,name.."：前置：本機 ReducedMotion=true")
  -- 只比較「顯示位置－同時間軸重建的基準」：前面 D 設的集結點仍有效，新單位會移動，
  -- 顯示位置本來就比 Root 晚 Motion.Delay，直接和 Root 比會把正常的插值落後當成出場位移。
  local worst=0
  for _,sample in ipairs(rec.samples) do
   if sample.visible then worst=math.max(worst,walk(sample).Magnitude) end
  end
  check(walk(first).Magnitude<=.05,name.."：降低動態效果時第一個畫面就在伺服器出生點（不播放出場）",string.format("偏差 %.3f",walk(first).Magnitude))
  check(worst<=(rec.rootMoved>.05 and .3 or .05),name.."：降低動態效果時全程沒有出場位移",string.format("最大偏差 %.3f（Root 最大位移 %.1f）",worst,rec.rootMoved))
  return failed==before
 end
 check(not rec.reduced,name.."：前置：本機 ReducedMotion 關閉")
 if not check(expected>0,name.."：SpawnFrom 到出生點的距離會播放出場（SpawnDuration>0）",
  string.format("距離 %.2f、速度 %s、預期 %.2f 秒",distance,tostring(rec.speed),expected)) then return false end
 local tolerance=mode=="rally" and .3 or .05
 -- 1) 第一個畫面：在 SpawnFrom 那一側（剩餘比例 ≥ 0.5），不在出生點。
 local w0=walk(first)
 local along=w0:Dot(toward)
 local side=(w0-toward*along).Magnitude
 check(along>=.5*distance and side<=.3,name.."：第一個顯示畫面靠近建築邊緣 SpawnFrom，不在伺服器出生點",
  string.format("剩餘比例 %.2f、偏離連線 %.2f、距離 %.2f",along/distance,side,distance))
 if first.body and first.bodyOffset then
  local onFrame=(first.body.Position-(first.display*first.bodyOffset).Position).Magnitude
  local fromRoot=(flat(first.body.Position)-flat((first.root*first.bodyOffset).Position)).Magnitude
  check(onFrame<=1.2 and fromRoot>=.4*distance,name.."：外觀零件（Body）跟著顯示位置，不在伺服器 Root",
   string.format("離顯示位置 %.2f、離 Root 位置 %.2f",onFrame,fromRoot))
 else info(name.." 探針沒有 Body 零件，略過外觀零件檢查") end
 -- 2) 逐格：出場位移單調縮小、面向外、沒有瞬移；何時結束。
 local previous,previousMagnitude
 local worstIncrease,worstJump,worstFacing,facingSamples=0,0,1,0
 local ended,reopened,gait,curve=nil,0,0,0
 local speed=rec.speed or Motion.SpawnDefaultSpeed
 for _,sample in ipairs(rec.samples) do
  if sample.visible and sample.t>=first.t then
   local w=walk(sample)
   local magnitude=w.Magnitude
   if previousMagnitude then worstIncrease=math.max(worstIncrease,magnitude-previousMagnitude) end
   if previous then
    local dt=math.max(sample.t-previous.t,1/240)
    local limit=(1.6*distance/expected+1.3*speed)*dt+.3
    worstJump=math.max(worstJump,(flat(sample.display.Position)-flat(previous.display.Position)).Magnitude/limit)
   end
   if not ended and w:Dot(toward)>=.3*distance then
    local look=flat(sample.display.LookVector)
    if look.Magnitude>.01 then worstFacing=math.min(worstFacing,look.Unit:Dot(-toward)); facingSamples+=1 end
   end
   if not ended and magnitude<=tolerance then ended=sample
   elseif ended and magnitude>tolerance then reopened=math.max(reopened,magnitude) end
   if not ended and sample.body and sample.bodyOffset then
    gait=math.max(gait,(sample.body.Position-(sample.display*sample.bodyOffset).Position).Magnitude)
   end
   if not ended then
    local model=distance*Motion.SpawnRemaining(sample.t-rec.appearClock,expected)
    curve=math.max(curve,math.abs(w:Dot(toward)-model))
   end
   previous,previousMagnitude=sample,magnitude
  end
 end
 check(worstIncrease<=(mode=="rally" and .25 or .02),name.."：出場位移逐格縮小（單調走向出生點）",string.format("最大回增 %.3f",worstIncrease))
 if facingSamples>0 then
  check(worstFacing>=.95,name.."：走出時面向外（背對建築）",string.format("最小 cos %.3f，%d 格",worstFacing,facingSamples))
 else info(name.." 出場太短，沒有剩餘比例 ≥ 0.3 的取樣，略過面向檢查") end
 check(worstJump<=1,name.."：顯示位置逐格移動，沒有瞬移",string.format("最大位移／上限 %.2f",worstJump))
 local endAt=ended and ended.t-rec.appearClock or nil
 check(ended~=nil and endAt<=expected+.3 and endAt>=.6*expected and reopened==0,
  name.."：依 SpawnDuration（"..string.format("%.2f",expected).." 秒）結束出場，之後不再偏離",
  endAt and string.format("出現後 %.2f 秒結束，之後最大偏離 %.3f",endAt,reopened) or "沒有結束")
 info(string.format("%s 與 SpawnRemaining 曲線的最大差距 %.2f studs（只供參考）",name,curve))
 if rec.samples[1] and rec.samples[1].body then
  check(gait>=.02,name.."：出場期間播放步態（Body 離開靜止姿勢）",string.format("最大 %.3f",gait))
 end
 if mode=="plain" then
  check(rec.rootMoved<=.05,name.."：伺服器 Root 在出場期間不動",string.format("最大位移 %.3f",rec.rootMoved))
  local last=rec.samples[#rec.samples]
  local move=last and (last.display.Position-last.root.Position).Magnitude or math.huge
  local angle=last and angleBetween(last.root,last.display) or math.huge
  check(move<=.05 and angle<=.05,name.."：最後停在伺服器 Root（位置與朝向）",string.format("位移 %.3f、角度 %.3f rad",move,angle))
 else
  check(rec.rootMoved>=5,name.."：前置：伺服器依集結點移動新單位",string.format("最大位移 %.1f",rec.rootMoved))
  -- 停下 0.6 秒後顯示位置必須回到 Root。
  waitFor(function() return rec.lastRootMove and os.clock()-rec.lastRootMove>.6 end,math.max(rec.stopClock-os.clock(),0))
  local probe=motionProbe()
  local ok,state=false,nil
  if probe then ok,state=pcall(probe.Invoke,probe,rec.unit) end
  local root=rec.unit.PrimaryPart
  local move=(ok and type(state)=="table" and typeof(state.frame)=="CFrame" and root) and (state.frame.Position-root.Position).Magnitude or math.huge
  check(move<=.05,name.."：抵達集結點停下後，顯示位置收斂到伺服器 Root",string.format("位移 %.3f",move))
 end
 return failed==before
end

-- 箭的分析 ---------------------------------------------------------------------------
local arrowsChecked=0
local function groundChecks(list,name)
 local worstPitch,worstY=0,0
 for _,rec in ipairs(list) do
  worstPitch=math.max(worstPitch,math.abs(rec.pitch-Remains.StuckPitch))
  worstY=math.max(worstY,math.abs(rec.entry.Y-Config.Map.GroundY))
 end
 arrowsChecked+=#list
 check(#list>0 and worstPitch<=.03 and worstY<=.06,name.."：地面的 StuckArrow 向下斜插 "..math.deg(Remains.StuckPitch).."°，露出部分在 GroundY 入地",
  string.format("%d 支，角度最大差 %.1f°、入地點高度最大差 %.3f",#list,math.deg(worstPitch),worstY))
end
local function lodgeChecks(list,house,name)
 local center=flat(house:GetPivot().Position)
 local bad,worstDot,worstDistance={},1,0
 for _,rec in ipairs(list) do
  local toCenter=center-flat(rec.entry)
  local look=flat(rec.look)
  local dot=(toCenter.Magnitude>.5 and look.Magnitude>.01) and look.Unit:Dot(toCenter.Unit) or -1
  worstDot=math.min(worstDot,dot)
  worstDistance=math.max(worstDistance,math.abs((rec.hitDistance or 99)-1.5))
  if not rec.lodged or rec.building~=house or dot<.97 or rec.look.Y>.02 or rec.name~="StuckArrow" then table.insert(bad,rec) end
 end
 arrowsChecked+=#list
 check(#list>0 and #bad==0,name.."：插在房屋可見表面上（入點前 1.5 studs 沿箭身射線命中不透明零件）、箭身沿飛行方向",
  string.format("%d 支，%d 支不符；水平方向 cos 最小 %.3f、表面距離最大差 %.2f",#list,#bad,worstDot,worstDistance))
end
local function arrowsNear(since,point,radius,predicate)
 local list={}
 for _,rec in ipairs(stuck.list) do
  if rec.appear>=since and (flat(rec.entry)-flat(point)).Magnitude<=radius and (not predicate or predicate(rec)) then table.insert(list,rec) end
 end
 return list
end
-- 自然到期：不是因為建築移除、降低動態效果或回大廳而提早移除的箭。
local function lifetimeChecks(list,name)
 local natural,bad,worstEarly,worstLate,worstFade,worstEarlyT=0,0,0,0,1,0
 for _,rec in ipairs(list) do
  if rec.removed and rec.removedPhase=="Playing" then
   local early=false
   for _,clock in ipairs(reducedToggles) do if math.abs(rec.removed-clock)<=.15 then early=true end end
   if rec.building and buildingGone[rec.building] and math.abs(rec.removed-buildingGone[rec.building])<=.3 then early=true end
   if not early then
    natural+=1
    local life=rec.removed-rec.appear
    worstEarly=math.max(worstEarly,Remains.StuckSeconds-life)
    worstLate=math.max(worstLate,life-Remains.StuckSeconds)
    worstFade=math.min(worstFade,rec.maxT)
    worstEarlyT=math.max(worstEarlyT,rec.earlyT)
    if life<Remains.StuckSeconds-.15 or life>Remains.StuckSeconds+.4 or rec.maxT<.5 or rec.earlyT>.01 then bad+=1 end
   end
  end
 end
 check(natural>0 and bad==0,name.."：自然到期的箭在 StuckSeconds（"..Remains.StuckSeconds.." 秒）移除，最後 "..Remains.StuckFadeSeconds.." 秒才淡出",
  string.format("%d 支，%d 支不符；最多提早 %.2f、延後 %.2f 秒；移除前最低透明度 %.2f、淡出前最高透明度 %.2f",natural,bad,worstEarly,worstLate,worstFade,worstEarlyT))
 return natural
end

-- 大廳與開局 -----------------------------------------------------------------------
local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
local function room(id,key) return workspace:GetAttribute("LobbyRoom_"..id.."_"..key) end
local function inBattle()
 return workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("InLobby")==false
  and typeof(player:GetAttribute("HomePosition"))=="Vector3" and workspace:FindFirstChild("Units")~=nil and #workspace.Units:GetChildren()>0
end
local SETTINGS={size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"}
local function readyUntilBattle(roomId,seconds)
 local deadline=os.clock()+seconds
 while os.clock()<deadline and not finished do
  if inBattle() then return true end
  if player:GetAttribute("InLobby")~=false and room(roomId,"Configured")==true and player:GetAttribute("LobbyReady")~=true then
   command:FireServer("LobbyReady",true,room(roomId,"SettingsRevision"))
  end
  waitFor(inBattle,1)
 end
 return inBattle()
end

-- 共用的對局內步驟 ---------------------------------------------------------------------
local helper
local hold -- Vector3 或回傳 Vector3 的函式：測試期間定時把鏡頭拉回來
local function holdPoint() if type(hold)=="function" then return hold() end return hold end
local function comfortablyOnScreen(point)
 local camera=workspace.CurrentCamera
 if not camera then return false end
 local screen,visible=camera:WorldToViewportPoint(point)
 local size=camera.ViewportSize
 return visible and screen.Z>0 and screen.Z<500 and screen.X>size.X*.08 and screen.X<size.X*.92 and screen.Y>size.Y*.08 and screen.Y<size.Y*.92
end
task.spawn(function()
 while not finished do
  local point=holdPoint()
  if typeof(point)=="Vector3" and not comfortablyOnScreen(point) then CameraFocus.Request(player,point) end
  task.wait(.25)
 end
end)
local function focus(point)
 hold=point
 CameraFocus.Request(player,point)
 return waitFor(function() return comfortablyOnScreen(point) end,5)~=nil
end
local function findBuilding(predicate,seconds)
 return waitFor(function()
  for _,model in ipairs(workspace.Buildings:GetChildren()) do if predicate(model) then return model end end
  return nil
 end,seconds)
end
local function tagged(tag,seconds)
 return findBuilding(function(model) return model:GetAttribute("AnimTestTag")==tag end,seconds)
end
local function testUnits(prefix)
 local list={}
 for _,unit in ipairs(workspace.Units:GetChildren()) do
  local tag=unit:GetAttribute("AnimTestTag")
  if type(tag)=="string" and string.sub(tag,1,#prefix)==prefix then table.insert(list,unit) end
 end
 return list
end
local function myTownCenter()
 local home=player:GetAttribute("HomePosition")
 return findBuilding(function(model)
  return model:GetAttribute("BuildingType")=="TownCenter" and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("Complete")==true
   and (typeof(home)~="Vector3" or (flat(model:GetPivot().Position)-flat(home)).Magnitude<60)
 end,10)
end
local function setup()
 helper=assert(RS:WaitForChild("AnimTestHelper",20),"AnimTestHelper 不存在")
 command:FireServer("AutoWork",false)
 check(waitFor(motionReady,10),"UnitMotion.client.lua 已初始化（RTSMotionReady、RTSMotionProbe、RTSClientEffects、RTSStuckArrows）")
 local stats=probeStats()
 check(stats and type(stats.effectsActive)=="number" and type(stats.effectsReused)=="number" and type(stats.stuckArrows)=="number",
  "RTSMotionProbe stats 有 effectsActive／effectsIdle／effectsCreated／effectsReused／stuckArrows",statsText(stats))
 check(helper:InvokeServer("ai")~=nil,"對局有電腦陣營（射擊目標）")
 local mine={}
 for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("OwnerId")==player.UserId then table.insert(mine,unit) end end
 command:FireServer("Stop",mine)
 local home=flat(player:GetAttribute("HomePosition"))
 local inward=home.Magnitude>1 and (-home).Unit or Vector3.new(1,0,0)
 return home,inward,Vector3.new(-inward.Z,0,inward.X)
end
-- 以正式 Train 指令訓練，回傳依出現順序的出場紀錄。
local function train(name,building,kind,count)
 local since=os.clock()
 local revision=building:GetAttribute("QueueRevision")
 for _=1,count do command:FireServer("Train",building,kind) end
 check(waitFor(function() return building:GetAttribute("QueueRevision")~=revision end,4)~=nil,name.."：伺服器接受正式 Train 指令（"..kind.."×"..count.."）")
 local list={}
 for index=1,count do
  local rec=findSpawn(kind,building,since,(Config.Units[kind].trainTime+3)*index+3)
  if not check(rec~=nil,name.."：第 "..index.." 個 "..kind.." 訓練完成並從建築邊緣出場") then break end
  table.insert(list,rec)
 end
 return list
end
-- 射擊電腦房屋：至少看到 wanted 支插在牆上的箭；回傳房屋、這些箭與開始時間。
local function lodgeRun(name,spot,tag,archers,wanted)
 focus(spot)
 local since=os.clock()
 local result=helper:InvokeServer("lodge",spot,tag,archers)
 if not check(result~=nil and result.archers>0,name.."：放置電腦的已完工房屋，自己的弓箭手以正式攻擊下令",result and ("弓箭手 "..result.archers)) then return nil end
 local house=tagged(tag,5)
 if not check(house~=nil,name.."：房屋複製到客戶端") then return nil end
 focus(result.ground)
 local seen=waitFor(function()
  local count=0
  for _,rec in ipairs(stuck.list) do if rec.appear>=since and rec.building==house then count+=1 end end
  return count>=wanted and count or nil
 end,16)
 check(seen~=nil,name.."：RTSStuckArrows 出現插在房屋上的 StuckArrow（至少 "..wanted.." 支）",seen and (seen.." 支") or nil)
 return house,since,result
end

-- Player1：主控 -----------------------------------------------------------------------
local serverSummary,observerReport
local function driver(duo)
 local Lobby=require(RS.Shared.LobbyTests)
 stage="開局"
 if duo then
  local roomId=Lobby.Join("Room1")
  local revision=room(roomId,"SettingsRevision")
  local settings=table.clone(SETTINGS); settings.expectedPlayers=2
  command:FireServer("LobbySettings",settings)
  assert(waitFor(function() return room(roomId,"SettingsRevision")~=revision end,8),"兩人房間設定未通過伺服器驗證")
  Lobby.ConfigureComplete()
  assert(waitFor(function() return (room(roomId,"Players") or 0)>=2 end,90),"Player2 沒有加入 Room1")
  assert(readyUntilBattle(roomId,60),"兩人對局沒有開始")
 else
  Lobby.Start(SETTINGS)
  assert(waitFor(inBattle,40),"開始測試局逾時")
 end
 local home,inward,side=setup()
 local savedMotion=player:GetAttribute("ReducedMotion")
 player:SetAttribute("ReducedMotion",false)
 local prep=helper:InvokeServer("prepare",true)
 check(prep and prep.houses>=2 and prep.stable,"放置自己的已完工房屋（人口）與馬廄",prep and string.format("房屋 %d、馬廄 %s",prep.houses,tostring(prep.stable)))
 local stable=prep and prep.stable and tagged(prep.stableTag,5)
 local tc=myTownCenter()
 assert(tc,"找不到自己的市鎮中心")
 info("主城 "..tostring(home))

 -- A. 市鎮中心訓練村民（正式訓練時間）
 stage="A 市鎮中心出場"
 check(focus(tc:GetPivot().Position),"A：鏡頭對準市鎮中心")
 local villager=train("A 市鎮中心",tc,"villager",1)[1]
 if villager then analyzeSpawn(villager,"A 村民出場","plain") end

 -- B. 非正方形占地：馬廄連續訓練 4 位斥候騎兵（伺服器把 trainTime 縮短為 3 秒）
 stage="B 馬廄出場"
 if check(stable~=nil,"B：馬廄複製到客戶端") then
  local footprint=stable.PrimaryPart
  check(footprint and math.abs(footprint.Size.X-footprint.Size.Z)>1,"B：馬廄占地不是正方形",footprint and string.format("%.0f×%.0f",footprint.Size.X,footprint.Size.Z))
  info("可旋轉的建築只有城門，它不訓練也不駐軍；旋轉占地的出場改由伺服器以占地 CFrame 計算驗證，實際以非正方形馬廄測長短邊")
  check(focus(stable:GetPivot().Position),"B：鏡頭對準馬廄")
  for index,rec in ipairs(train("B 馬廄",stable,"scout",4)) do analyzeSpawn(rec,"B 斥候騎兵 #"..index,"plain") end
 end

 -- C. 離開駐軍
 stage="C 離開駐軍"
 focus(tc:GetPivot().Position)
 local candidates={}
 for _,unit in ipairs(workspace.Units:GetChildren()) do
  if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" and unit:GetAttribute("AnimTestTag")==nil
   and (unit:GetAttribute("HP") or 0)>0 then table.insert(candidates,unit) end
 end
 local tcPoint=flat(tc:GetPivot().Position)
 table.sort(candidates,function(a,b) return (flat(a:GetPivot().Position)-tcPoint).Magnitude<(flat(b:GetPivot().Position)-tcPoint).Magnitude end)
 local group={candidates[1],candidates[2]}
 if check(#group==2,"C：找到 2 位自己的村民") then
  command:FireServer("Garrison",group,tc)
  if check(waitFor(function() return (tc:GetAttribute("Garrison") or 0)>=2 end,25)~=nil,"C：2 位村民以正式 Garrison 進入市鎮中心",tc:GetAttribute("Garrison")) then
   local since=os.clock()
   command:FireServer("Ungarrison",tc)
   for index=1,2 do
    local rec=findSpawn("villager",tc,since,4)
    if check(rec~=nil,"C：正式 Ungarrison 後第 "..index.." 位村民從市鎮中心邊緣出場") then analyzeSpawn(rec,"C 離開駐軍 #"..index,"plain") end
   end
  end
 end

 -- D. 集結點
 stage="D 集結點"
 if stable then
  local center=flat(stable:GetPivot().Position)
  local rally=center+inward*48
  focus(center+inward*20)
  command:FireServer("Rally",stable,rally)
  if check(waitFor(function() return typeof(stable:GetAttribute("RallyPosition"))=="Vector3" end,4)~=nil,"D：正式 Rally 指令設定馬廄集結點") then
   local rec=train("D 集結點",stable,"scout",1)[1]
   if rec then analyzeSpawn(rec,"D 斥候騎兵（集結點）","rally") end
  end
  command:FireServer("Rally",stable,nil)
 end

 -- E1. 地面：追著跑開的電腦村民射擊
 stage="E 地面插箭"
 local area=home+inward*115
 local groundList={}
 for attempt=1,2 do
  local spot=area+side*((attempt-1)*45)
  focus(spot)
  local since=os.clock()
  local result=helper:InvokeServer("runner",spot,"ground"..attempt)
  if check(result~=nil,"E：第 "..attempt.." 次：電腦村民跑向遠處的誘餌，自己的弓箭手以正式攻擊追射") then
   local archer=waitFor(function() return testUnits("ground"..attempt.."-archer")[1] end,5)
   hold=function() return archer and archer.Parent and archer:GetPivot().Position or result.target end
   waitFor(function() return #arrowsNear(since,result.target,170,function(rec) return not rec.lodged end)>=2 end,14)
   groundList=arrowsNear(since,result.target,170,function(rec) return not rec.lodged end)
   if #groundList>0 then
    -- 停火後：暫時特效歸還，物件池中使用中的只剩插著的箭。
    helper:InvokeServer("remove")
    local stats
    local equal=waitFor(function()
     stats=probeStats()
     return stats and stats.stuckArrows>0 and stats.effectsActive==stats.stuckArrows
    end,1.8)
    if equal then check(true,"E：停火後物件池使用中數量等於插著的箭數（暫時特效已歸還）",statsText(stats))
    elseif stats and stats.stuckArrows==0 then info("E：插著的箭在檢查前已全部到期，略過 effectsActive=stuckArrows 檢查")
    else check(false,"E：停火後物件池使用中數量等於插著的箭數（暫時特效已歸還）",statsText(stats)) end
    break
   end
   helper:InvokeServer("remove")
   info("第 "..attempt.." 次沒有地面箭，換位置重試")
  end
 end
 groundChecks(groundList,"E 地面")
 for _,rec in ipairs(groundList) do if rec.name~="StuckArrow" then check(false,"E：插著的箭改名為 StuckArrow",rec.name) end end

 -- E2. 牆面：射擊電腦房屋，摧毀時插在上面的箭一起消失
 stage="E 牆面插箭"
 local houseA,sinceA=lodgeRun("E 牆面",home+turn(inward,35)*100,"lodgeA",3,3)
 if houseA then
  lodgeChecks(arrowsNear(sinceA,houseA:GetPivot().Position,40,function(rec) return rec.entry.Y>Config.Map.GroundY+.25 end),houseA,"E 牆面")
  check(waitFor(function() return liveOn(houseA)>=1 end,8)~=nil,"E：前置：摧毀前房屋上有插著的箭",liveOn(houseA))
  local gone
  local connection=houseA.AncestryChanged:Connect(function()
   if not gone and not houseA:IsDescendantOf(workspace.Buildings) then gone=os.clock() end
  end)
  check(helper:InvokeServer("raze","lodgeA")==true,"E：房屋生命設為 1，弓箭手以正式攻擊摧毀它")
  waitFor(function() return gone end,12)
  connection:Disconnect()
  if check(gone~=nil,"E：房屋被摧毀並從 Buildings 移除") then
   local onHouse={}
   for _,rec in ipairs(stuck.list) do
    if rec.building==houseA and rec.appear<gone and (not rec.removed or rec.removed>=gone-.1) then table.insert(onHouse,rec) end
   end
   check(#onHouse>0,"E：前置：移除當下房屋上有插著的箭",#onHouse.." 支")
   waitFor(function() for _,rec in ipairs(onHouse) do if not rec.removed then return false end end return true end,.6)
   local late,left=0,0
   for _,rec in ipairs(onHouse) do
    if rec.removed then late=math.max(late,rec.removed-gone) else left+=1 end
   end
   check(#onHouse>0 and left==0 and late<=.2,"E：房屋移除時插在上面的箭立即消失",string.format("%d 支，剩 %d 支，最慢 %.2f 秒",#onHouse,left,late))
  end
 end
 helper:InvokeServer("remove")

 -- F. 降低動態效果
 stage="F 降低動態效果"
 local houseB,sinceB=lodgeRun("F 前置",home+turn(inward,-35)*100,"lodgeB",2,1)
 if houseB then
  check(waitFor(function() return liveCount()>=1 end,8)~=nil,"F：前置：開啟前有插著的箭",liveCount())
  local archers=testUnits("lodgeB-archer")
  local shots=0
  local connections={}
  for _,archer in ipairs(archers) do
   table.insert(connections,archer:GetAttributeChangedSignal("LastAttack"):Connect(function()
    if player:GetAttribute("ReducedMotion")==true then shots+=1 end
   end))
  end
  player:SetAttribute("ReducedMotion",true)
  local cleared=waitFor(function() return children(stuckFolder())==0 end,.5)
  local stats=probeStats()
  check(cleared~=nil and stats and stats.stuckArrows==0,"F：開啟後已插著的箭立即清除（RTSStuckArrows 空、stats.stuckArrows=0）",
   string.format("剩 %d、%s",children(stuckFolder()),statsText(stats)))
  local function parts()
   local count=0
   for _,item in ipairs(effectsFolder() and effectsFolder():GetChildren() or {}) do if item:IsA("BasePart") and PROJECTILES[item.Name] then count+=1 end end
   return count
  end
  check(waitFor(function() return parts()==0 end,.5)~=nil,"F：飛行中的投射物與命中特效立即歸還（RTSClientEffects 沒有投射物）",parts())
  waitFor(function() return shots>=2 end,8)
  check(shots>=2,"F：前置：開啟期間弓箭手繼續射擊",shots.." 次")
  check(stuck.reducedAdds==0 and transientAdds.arrowWhileReduced==0 and transientAdds.projectilesWhileReduced==0,
   "F：開啟期間不產生投射物，也不插箭",string.format("插箭 %d、箭與標槍 %d、投射物與命中特效 %d",stuck.reducedAdds,transientAdds.arrowWhileReduced,transientAdds.projectilesWhileReduced))
  for _,connection in ipairs(connections) do connection:Disconnect() end
 end
 helper:InvokeServer("remove")
 if stable then
  focus(stable:GetPivot().Position)
  local rec=train("F 降低動態效果",stable,"scout",1)[1]
  if rec then analyzeSpawn(rec,"F 斥候騎兵（降低動態效果）","reduced") end
 end
 player:SetAttribute("ReducedMotion",savedMotion==true)
 check(waitFor(function() return children(effectsFolder())==0 end,1.5)~=nil,"F：停火並關閉後 RTSClientEffects 清空",children(effectsFolder()))
 hold=nil

 -- 自然到期與淡出（地面與牆面測試留下的箭）
 stage="E 到期"
 waitFor(function() return liveCount()==0 end,Remains.StuckSeconds+1)
 lifetimeChecks(stuck.list,"E")
 local names=0
 for _,rec in ipairs(stuck.list) do if rec.name~="StuckArrow" then names+=1 end end
 check(#stuck.list>0 and names==0,"E：所有插著的箭都改名為 StuckArrow、放在 RTSStuckArrows",string.format("%d 支，%d 支名稱不符",#stuck.list,names))
 check(stuck.maxLive<=Remains.MaxStuck,"E：同時插著的箭不超過 MaxStuck（"..Remains.MaxStuck.."）",stuck.maxLive)

 -- G. 特效池與閒置
 stage="G 特效池"
 local idle
 local stats
 idle=waitFor(function()
  stats=probeStats()
  return stats and stats.effectsActive==0 and stats.stuckArrows==0 and children(effectsFolder())==0 and children(stuckFolder())==0
 end,Remains.StuckSeconds+3)
 check(idle~=nil,"G：閒置時物件池沒有使用中的物件，RTSClientEffects 與 RTSStuckArrows 為空",
  statsText(stats)..string.format("、資料夾 %d／%d",children(effectsFolder()),children(stuckFolder())))
 check(countNamed("ArrowEffect")==0 and countNamed("StuckArrow")==0,"G：閒置時 workspace 沒有 ArrowEffect 或 StuckArrow",
  string.format("ArrowEffect %d、StuckArrow %d",countNamed("ArrowEffect"),countNamed("StuckArrow")))
 check(stats and stats.effectsReused>0,"G：戰鬥後物件池有重用（effectsReused>0）",statsText(stats))
 check(stats and stats.effectsCreated<=MAX_TRANSIENT+Remains.MaxStuck,"G：建立的物件數有上限（≤ "..(MAX_TRANSIENT+Remains.MaxStuck).."）",statsText(stats))

 -- 伺服器端出生點稽核
 stage="伺服器稽核"
 local summary=helper:InvokeServer("summary")
 if check(summary~=nil,"取得伺服器稽核") then
  check(summary.human>=spawnsChecked and summary.noBuilding==0,"伺服器檢查了每個真人新單位的 SpawnFrom，且都在來源建築占地內",
   string.format("伺服器 %d 個、本客戶端分析 %d 個、找不到建築 %d",summary.human,spawnsChecked,summary.noBuilding))
  local faces=summary.faces and summary.faces.Stable
  check(faces and faces.x>0 and faces.z>0,"B：非正方形占地（馬廄）的 X 面與 Z 面都有新單位走出，SpawnFrom 都正好在邊緣內 1 stud",
   faces and string.format("X 面 %d、Z 面 %d",faces.x,faces.z) or "沒有馬廄出場")
 end

 -- 雙人：等待 Player2 回報
 if duo then
  stage="等待 Player2 回報"
  local report=waitFor(function() return workspace:GetAttribute("AnimObserverReport") end,90)
  local name
  if check(report~=nil,"Player2 回報結果") then
   local p,f,spawns,arrows
   name,p,f,spawns,arrows=string.match(report,"^(.-)|(%d+)|(%d+)|(%d+)|(%d+)$")
   observerReport={name=name,passed=tonumber(p) or 0,failed=tonumber(f) or 1}
   check(observerReport.failed==0 and (tonumber(spawns) or 0)>0 and (tonumber(arrows) or 0)>0,(name or "Player2").." 的客戶端檢查全部通過",
    string.format("%s passed, %s failed，出場 %s 個、插箭 %s 支",tostring(p),tostring(f),tostring(spawns),tostring(arrows)))
  end
  local final=helper:InvokeServer("summary")
  check(final and final.byOwner and (final.byOwner[name or ""] or 0)>0,"伺服器也檢查了 Player2 的新單位 SpawnFrom",
   final and final.byOwner and tostring(final.byOwner[name or ""]) or nil)
  helper:InvokeServer("phase","done")
 end

 -- 回大廳：清空
 stage="回大廳"
 command:FireServer("Surrender")
 local ended=waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,30)
 if check(ended~=nil,"投降後對局結束",workspace:GetAttribute("MatchPhase")) then
  command:FireServer("RestartMatch")
  local lobby=waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" end,30)
  check(lobby~=nil,"回到大廳",workspace:GetAttribute("MatchPhase"))
  local emptied=waitFor(function()
   local stats=probeStats()
   return children(effectsFolder())==0 and children(stuckFolder())==0 and stats and stats.effectsActive==0 and stats.stuckArrows==0
  end,3)
  check(emptied~=nil and countNamed("ArrowEffect")==0 and countNamed("StuckArrow")==0,"回大廳後 RTSClientEffects、RTSStuckArrows 為空，物件池沒有使用中的物件",statsText(probeStats()))
  local after=helper:InvokeServer("summary")
  check(after and after.testUnits==0,"回大廳後伺服器沒有留下測試單位",after and after.testUnits)
 end
 serverSummary=helper:InvokeServer("summary")
end

-- Player2：在自己的主城獨立驗證一部分 ---------------------------------------------------
local function observer()
 local Lobby=require(RS.Shared.LobbyTests)
 stage="等待 Player1 建立兩人房間"
 assert(waitFor(function()
  return room("Room1","Configured")==true and room("Room1","ExpectedPlayers")==2 and (room("Room1","Players") or 0)==1
 end,90),"Player1 沒有建立兩人房間")
 Lobby.Join("Room1")
 stage="等待開局"
 assert(readyUntilBattle("Room1",60),"兩人對局沒有開始")
 local home,inward=setup()
 player:SetAttribute("ReducedMotion",false)
 local prep=helper:InvokeServer("prepare",false)
 check(prep and prep.houses>=1,"放置自己的已完工房屋（人口）",prep and prep.houses)
 local tc=myTownCenter()
 assert(tc,"找不到自己的市鎮中心")
 stage="市鎮中心出場"
 check(focus(tc:GetPivot().Position),"鏡頭對準自己的市鎮中心")
 local villager=train("市鎮中心",tc,"villager",1)[1]
 if villager then analyzeSpawn(villager,"村民出場","plain") end
 stage="牆面插箭"
 local house,since=lodgeRun("牆面",home+turn(inward,20)*100,"p2lodge-"..player.UserId,2,2)
 if house then
  lodgeChecks(arrowsNear(since,house:GetPivot().Position,40,function(rec) return rec.entry.Y>Config.Map.GroundY+.25 end),house,"牆面")
 end
 helper:InvokeServer("remove")
 hold=nil
 stage="到期"
 waitFor(function() return liveCount()==0 end,Remains.StuckSeconds+1.5)
 lifetimeChecks(stuck.list,"到期")
 local stats
 check(waitFor(function()
  stats=probeStats()
  return stats and stats.stuckArrows==0 and children(stuckFolder())==0
 end,2)~=nil,"停火後插著的箭全部到期，RTSStuckArrows 為空",statsText(stats))
 helper:InvokeServer("report",passed,failed,spawnsChecked,arrowsChecked)
 stage="等待 Player1 完成"
 waitFor(function() return workspace:GetAttribute("AnimHarnessPhase")=="done" end,TIMEOUT)
 command:FireServer("Surrender")
end

-- 啟動 -------------------------------------------------------------------------------
task.delay(TIMEOUT,function()
 finish(string.format("INCOMPLETE %d passed, %d failed（逾時 %d 秒，停在「%s」）",passed,failed,TIMEOUT,stage))
end)
task.spawn(function()
 local ok,problem=pcall(function()
  assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,60),"初始化逾時")
  attachFolders()
  stage="等待其他客戶端"
  -- run-studio-harness 以 2 位玩家啟動時，第二個客戶端幾秒內就會連上。
  waitFor(function() return #Players:GetPlayers()>=2 end,player.Name=="Player1" and 8 or 20)
  local list=Players:GetPlayers()
  local leader=player
  for _,other in ipairs(list) do if other.UserId>leader.UserId then leader=other end end
  local duo=#list>=2
  if leader==player then
   role="driver"
   info(duo and "雙人模式：本客戶端主控" or "單人模式")
   driver(duo)
  else
   role="observer"
   label="[ANIM "..player.Name.."] "
   info("雙人模式：本客戶端在自己的主城驗證，主控為 "..leader.Name)
   observer()
  end
 end)
 if finished then return end
 if role~="observer" then
  if not serverSummary and helper then
   local fetched,value=pcall(function() return helper:InvokeServer("summary") end)
   if fetched and type(value)=="table" then serverSummary=value end
  end
  local total,bad=passed,failed
  local parts={}
  if serverSummary then
   total+=serverSummary.passed; bad+=serverSummary.failed
   table.insert(parts,string.format("伺服器 %d／%d",serverSummary.passed,serverSummary.failed))
  elseif ok then bad+=1; table.insert(parts,"沒有伺服器總結") end
  if observerReport then
   total+=observerReport.passed; bad+=observerReport.failed
   table.insert(parts,string.format("%s %d／%d",tostring(observerReport.name),observerReport.passed,observerReport.failed))
  end
  if ok and bad==0 then
   finish(string.format("COMPLETE %d passed, 0 failed",total))
  else
   finish(string.format("INCOMPLETE %d passed, %d failed（%s%s）",total,bad,ok and "" or ("中斷於「"..stage.."」："..tostring(problem).."；"),table.concat(parts,"，")))
  end
 else
  if not ok then
   failed+=1; warn(label.."FAIL 中斷於「"..stage.."」："..tostring(problem))
   if helper and not workspace:GetAttribute("AnimObserverReport") then pcall(function() helper:InvokeServer("report",passed,failed,spawnsChecked,arrowsChecked) end) end
  end
  finish(string.format("DONE %d passed, %d failed",passed,failed))
 end
end)
