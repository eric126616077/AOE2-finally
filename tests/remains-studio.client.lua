-- Test-only LocalScript, mapped only by remains-validation.project.json.
-- Studio CLIENT：倒地、倒塌與資源消失動畫（Remains.client.lua，f999599）的命令列驗證。
-- 只讀實際實例（零件 CFrame、LocalTransparencyModifier、屬性、RTSRemainsEffects），不讀任何模組內部狀態。
--
-- 1 位客戶端（Player1，主控）：以正常大廳指令開局（1 真人＋1 簡單電腦、Small、豐富資源），依序驗證
--  A. 戰鬥擊殺留下屍體：屬性、剛出現時直立、倒地後到伺服器的平躺位置、最後 FadeSeconds 淡出與下沉、準時移除。
--  B. 完工建築被摧毀：Ruins 複本（building）、揚塵 CollapseDust、下沉、淡出、準時移除、揚塵清除。
--  C. 樹木採到 0：tree 複本上半部倒下；金礦（或石礦／漿果）採到 0：resource 複本下沉淡出。
--  D. 畫面外的倒塌複本與迷霧中的倒塌複本立即隱藏（LocalTransparencyModifier=1、不動、不揚塵）。
--  E. 降低動態效果（ReducedMotion）：屍體直接平躺、只淡出不下沉；建築不揚塵、不動、只淡出。
--  F. 清理：Ruins 清空、揚塵清除、沒有過期屍體；回大廳後 Corpses／Ruins 清空。
-- 2 位客戶端：Player2 加入同一房間當觀察者（鏡頭留在自己的主城），對每個出現的屍體與複本做同樣的
--  一般性檢查（遠方事件應立即隱藏／不倒地），並把結果回報給伺服器；Player1 把它算進總結。
-- 輸出：Player1 為 [REMAINS] PASS／FAIL／INFO，最後一行 [REMAINS] COMPLETE n passed, 0 failed 或 [REMAINS] INCOMPLETE …；
--       Player2 為 [REMAINS Player2] …（最後 DONE），伺服器為 [REMAINS SERVER] …。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("RemainsRules"))
local FogView=require(RS.Shared.FogView)
local CameraFocus=require(RS.Shared.CameraFocus)
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))

-- 從腳本啟動起算的全域逾時；逾時印出 INCOMPLETE，不會無限等待。
local TIMEOUT=210
-- 角色決定前一律以 [REMAINS] 開頭；觀察者改為 [REMAINS PlayerN]。
local label="[REMAINS] "
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

-- 與 Remains.client.lua 的 inView 完全相同的判定 -------------------------------------
local function onScreen(point)
 local camera=workspace.CurrentCamera
 if not camera then return false,math.huge end
 local screen,visible=camera:WorldToViewportPoint(point)
 return visible and screen.Z>0,screen.Z
end
local function inView(point)
 local shown,depth=onScreen(point)
 return shown and depth<Rules.MaxDistance and FogView.VisibleAt(point)
end
local function describeView(point)
 local shown,depth=onScreen(point)
 return string.format("畫面內=%s 深度=%.0f 視野=%s 迷霧啟用=%s",tostring(shown),depth,tostring(FogView.VisibleAt(point)),tostring(FogView.Active()))
end
local function angleBetween(a,b)
 local _,_,_,r00,_,_,_,r11,_,_,_,r22=a:ToObjectSpace(b):GetComponents()
 return math.acos(math.clamp((r00+r11+r22-1)/2,-1,1))
end
local function effects() return workspace:FindFirstChild("RTSRemainsEffects") end
local function dustNear(point,radius)
 local count=0
 local folder=effects()
 for _,item in ipairs(folder and folder:GetChildren() or {}) do
  if item.Name=="CollapseDust" and item:IsA("BasePart") and (not point or (flat(item.Position)-flat(point)).Magnitude<=radius) then count+=1 end
 end
 return count
end

-- 追蹤每個出現的屍體與倒塌複本 ---------------------------------------------------
-- 伺服器測試腳本在零件上寫入 RemainsServerCFrame（伺服器的最終位置）；本機姿勢與它比較。
local records,recordList,active,attached={}, {}, {}, {}
local scanning=true
local function track(model,folderName,preexisting)
 if records[model] or not model:IsA("Model") then return end
 local rec={model=model,corpse=folderName=="Corpses",preexisting=preexisting==true,appearClock=os.clock(),appearServer=serverNow(),parts={},
  maxLTM=0,maxMove=0,maxAngle=0,maxDown=0,maxTopAngle=0,preFadeLTM=0,preFadeMove=0,preFadeAngle=0,fadeLTM=0,fadeDown=0,fadeMove=0,fadeSamples=0}
 for _,part in ipairs(model:GetDescendants()) do if part:IsA("BasePart") then table.insert(rec.parts,part) end end
 if rec.corpse then
  rec.base,rec.lay,rec.expires=model:GetAttribute("CorpseBase"),model:GetAttribute("CorpseLay"),model:GetAttribute("CorpseExpires")
  rec.point=typeof(rec.base)=="CFrame" and rec.base.Position or nil
  rec.age=type(rec.expires)=="number" and Config.Combat.corpseSeconds-(rec.expires-rec.appearServer) or nil
 else
  rec.kind,rec.start,rec.seconds=model:GetAttribute("RuinKind"),model:GetAttribute("RuinStart"),model:GetAttribute("RuinSeconds")
  rec.ground,rec.height=model:GetAttribute("RuinGround"),model:GetAttribute("RuinHeight")
  rec.point=typeof(rec.ground)=="Vector3" and rec.ground or nil
  rec.age=type(rec.start)=="number" and rec.appearServer-rec.start or nil
 end
 records[model]=rec
 table.insert(recordList,rec)
 -- 延後到同一輪的 Remains ChildAdded 處理之後、下一次 RenderStepped 之前：
 -- 這時的姿勢與透明度就是 Remains 一開始決定的狀態（直立／立即隱藏／揚塵數）。
 task.defer(function()
  rec.first={}
  local hidden=#rec.parts>0
  for index,part in ipairs(rec.parts) do
   rec.first[index]=part.CFrame
   if part.LocalTransparencyModifier<.999 then hidden=false end
  end
  rec.firstHidden=hidden
  if rec.point then
   rec.view=inView(rec.point)
   rec.screen,rec.depth=onScreen(rec.point)
   rec.fogVisible=FogView.VisibleAt(rec.point)
   rec.viewText=describeView(rec.point)
  else rec.view=false; rec.viewText="沒有位置屬性" end
  rec.reduced=player:GetAttribute("ReducedMotion")==true
  rec.dust=(not rec.corpse and rec.point) and dustNear(rec.point,45) or 0
  rec.ready=true
  if model.Parent then active[model]=rec end
 end)
end
local function untrack(model)
 local rec=records[model]
 if not rec or rec.removed then return end
 rec.removed=true
 rec.removedServer=serverNow()
 rec.removedPhase=workspace:GetAttribute("MatchPhase")
 active[model]=nil
end
local function attach(folder)
 if not folder:IsA("Folder") or (folder.Name~="Corpses" and folder.Name~="Ruins") or attached[folder] then return end
 attached[folder]=true
 local name=folder.Name
 folder.ChildAdded:Connect(function(child) track(child,name) end)
 folder.ChildRemoved:Connect(untrack)
 -- 只有腳本啟動前就存在的才算既有；對局中第一個屍體會連同新資料夾一起出現，仍要檢查。
 for _,child in ipairs(folder:GetChildren()) do track(child,name,scanning) end
end
workspace.ChildAdded:Connect(attach)
for _,child in ipairs(workspace:GetChildren()) do attach(child) end
scanning=false
-- Heartbeat 在 RenderStepped（Remains 寫入姿勢）之後，讀到的是這一幀實際畫出的姿勢。
Run.Heartbeat:Connect(function()
 local now=serverNow()
 for model,rec in pairs(active) do
  if not model.Parent then active[model]=nil; continue end
  local fading=rec.corpse and type(rec.expires)=="number" and now>=rec.expires-Rules.FadeSeconds-.05
  local alpha=0
  for _,part in ipairs(rec.parts) do
   if part.Parent then
    alpha=math.max(alpha,part.LocalTransparencyModifier)
    local server=part:GetAttribute("RemainsServerCFrame")
    if typeof(server)=="CFrame" then
     local cf=part.CFrame
     local move=(cf.Position-server.Position).Magnitude
     local angle=angleBetween(server,cf)
     local down=server.Position.Y-cf.Position.Y
     rec.maxMove=math.max(rec.maxMove,move)
     rec.maxAngle=math.max(rec.maxAngle,angle)
     rec.maxDown=math.max(rec.maxDown,down)
     if rec.kind=="tree" and rec.point and server.Position.Y-rec.point.Y>1.5 then rec.maxTopAngle=math.max(rec.maxTopAngle,angle) end
     if rec.corpse then
      if fading then rec.fadeDown=math.max(rec.fadeDown,down); rec.fadeMove=math.max(rec.fadeMove,move)
      else rec.preFadeMove=math.max(rec.preFadeMove,move); rec.preFadeAngle=math.max(rec.preFadeAngle,angle) end
     end
    end
   end
  end
  rec.maxLTM=math.max(rec.maxLTM,alpha)
  if rec.corpse then
   if fading then rec.fadeLTM=math.max(rec.fadeLTM,alpha); rec.fadeSamples+=1 else rec.preFadeLTM=math.max(rec.preFadeLTM,alpha) end
  end
 end
end)

-- 姿勢比較 -------------------------------------------------------------------------
local function tagged(rec,seconds)
 return waitFor(function() return rec.ready and rec.model:GetAttribute("RemainsTagged")==true end,seconds)~=nil
end
-- 第一個畫面（Remains 處理後）與 expected(server) 的最大差距。
local function firstDeviation(rec,expected)
 local maxMove,maxAngle,count=0,0,0
 for index,part in ipairs(rec.parts) do
  local server=part:GetAttribute("RemainsServerCFrame")
  local first=rec.first and rec.first[index]
  if typeof(server)=="CFrame" and first then
   local target=expected and expected(server) or server
   count+=1
   maxMove=math.max(maxMove,(first.Position-target.Position).Magnitude)
   maxAngle=math.max(maxAngle,angleBetween(target,first))
  end
 end
 return maxMove,maxAngle,count
end
local function currentDeviation(rec)
 local maxMove,maxAngle,count=0,0,0
 for _,part in ipairs(rec.parts) do
  local server=part:GetAttribute("RemainsServerCFrame")
  if part.Parent and typeof(server)=="CFrame" then
   count+=1
   maxMove=math.max(maxMove,(part.CFrame.Position-server.Position).Magnitude)
   maxAngle=math.max(maxAngle,angleBetween(server,part.CFrame))
  end
 end
 return maxMove,maxAngle,count
end
-- Remains 倒地開始時把零件擺成 base * lay⁻¹ * base⁻¹ * 最終位置（直立）。
local function uprightOf(rec)
 local motion=rec.base*rec.lay:Inverse()*rec.base:Inverse()
 return function(server) return motion*server end
end
local function fmt(move,angle) return string.format("位移 %.2f、角度 %.2f rad",move,angle) end

-- 共用：屍體與複本的屬性、移除與淡出檢查 --------------------------------------------
local function corpseAttributes(rec,name)
 local ok=typeof(rec.base)=="CFrame" and typeof(rec.lay)=="CFrame" and type(rec.expires)=="number"
 return check(ok and math.abs(rec.age or math.huge)<1.5,name.."：屍體有 CorpseBase／CorpseLay／CorpseExpires，到期時間約為 "..Config.Combat.corpseSeconds.." 秒後",
  ok and string.format("出現時已過 %.2f 秒",rec.age) or "屬性缺少")
end
local function ruinAttributes(rec,name,kind)
 local expected=({building=Rules.CollapseSeconds,tree=Rules.TreeFallSeconds,resource=Rules.ResourceFadeSeconds})[rec.kind]
 local ok=(kind==nil or rec.kind==kind) and expected~=nil and rec.seconds==expected and type(rec.start)=="number"
  and typeof(rec.ground)=="Vector3" and type(rec.height)=="number" and rec.height>0 and #rec.parts>0
 return check(ok,name.."：Ruins 複本 RuinKind="..tostring(rec.kind).."、RuinSeconds="..tostring(rec.seconds).."、有 RuinStart／RuinGround／RuinHeight",
  #rec.parts.." 個零件")
end
local function awaitRemoval(rec,due)
 return waitFor(function() return rec.removed end,math.max(due-serverNow(),0)+2.5)~=nil
end
local function corpseRemoval(rec,name)
 if type(rec.expires)~="number" then return check(false,name.."：屍體缺少 CorpseExpires，無法檢查移除時間") end
 if not awaitRemoval(rec,rec.expires) then return check(false,name.."：伺服器在 CorpseExpires 後移除屍體","仍存在") end
 local late=rec.removedServer-rec.expires
 return check(late>=-.5 and late<=1.5,name.."：伺服器在 CorpseExpires 移除屍體",string.format("比到期 %+.2f 秒（客戶端時間）",late))
end
local function ruinRemoval(rec,name)
 if type(rec.start)~="number" or type(rec.seconds)~="number" then return check(false,name.."：複本缺少 RuinStart／RuinSeconds，無法檢查移除時間") end
 local due=rec.start+rec.seconds+.5
 if not awaitRemoval(rec,due) then return check(false,name.."：伺服器在 RuinSeconds+0.5 秒內移除複本","仍存在") end
 local late=rec.removedServer-due
 return check(late>=-.5 and late<=1.5,name.."：伺服器在 RuinSeconds+0.5 秒移除複本",string.format("比預定 %+.2f 秒（客戶端時間）",late))
end
local function corpseFade(rec,name,reduced)
 check(rec.preFadeLTM<=.01,name.."：淡出前保持不透明",string.format("最大 LocalTransparencyModifier %.2f",rec.preFadeLTM))
 check(rec.fadeSamples>0 and rec.fadeLTM>=.3,name.."：最後 "..Rules.FadeSeconds.." 秒 LocalTransparencyModifier 上升",
  string.format("最大 %.2f（%d 個取樣）",rec.fadeLTM,rec.fadeSamples))
 if reduced then
  check(rec.fadeDown<=.02 and rec.fadeMove<=.02,name.."：降低動態效果時只淡出、不下沉",string.format("下沉 %.2f、位移 %.2f",rec.fadeDown,rec.fadeMove))
 else
  check(rec.fadeDown>=.2,name.."：淡出時沉入地面",string.format("最大下沉 %.2f（上限 %.2f）",rec.fadeDown,Rules.SinkDepth))
 end
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
local function remainsReady()
 local scripts=player:FindFirstChild("PlayerScripts")
 local remains=scripts and scripts:FindFirstChild("Remains")
 return remains~=nil and remains:GetAttribute("RTSRemainsReady")==true and effects()~=nil
end

-- Player1：主控 -----------------------------------------------------------------------
local helper
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
 helper=assert(RS:WaitForChild("RemainsTestHelper",20),"RemainsTestHelper 不存在")
 command:FireServer("AutoWork",false)
 check(waitFor(remainsReady,10),"Remains.client.lua 已初始化（RTSRemainsReady、RTSRemainsEffects）")
 check(helper:InvokeServer("ai")~=nil,"對局有電腦陣營（擊殺與摧毀的對手）")
 -- 已在工作的開局單位全部停下（自動工作已關閉，停下後保持待命），避免它們先採完測試資源。
 local mine={}
 for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("OwnerId")==player.UserId then table.insert(mine,unit) end end
 command:FireServer("Stop",mine)
 local home=flat(player:GetAttribute("HomePosition"))
 local ax=Vector3.new(home.X>0 and -1 or 1,0,0)
 local az=Vector3.new(0,0,home.Z>0 and -1 or 1)
 local inward=(ax+az).Unit
 local function at(a,b) return home+ax*a+az*b end
 info("主城 "..tostring(home).."，迷霧啟用="..tostring(FogView.Active()))

 -- 鏡頭：測試期間定時把鏡頭拉回指定點（避免邊緣捲動把鏡頭帶走）。
 local hold
 task.spawn(function()
  while not finished do
   if hold and not onScreen(hold) then CameraFocus.Request(player,hold) end
   task.wait(.5)
  end
 end)
 local function focus(point)
  hold=point
  CameraFocus.Request(player,point)
  return waitFor(function() local shown,depth=onScreen(point); return shown and depth<Rules.MaxDistance end,5)~=nil
 end
 local function findRecord(corpse,tag,seconds)
  return waitFor(function()
   for _,rec in ipairs(recordList) do
    if rec.corpse==corpse and rec.ready and rec.model:GetAttribute("RemainsTestTag")==tag then return rec end
   end
   return nil
  end,seconds)
 end
 local function findUnit(tag,seconds)
  return waitFor(function()
   for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("RemainsTestTag")==tag then return unit end end
   return nil
  end,seconds)
 end

 -- 屍體：擊殺並檢查剛出現與倒地結束的姿勢；淡出與移除在 finishCorpse 檢查。
 local function corpseTest(name,spot,reduced)
  stage=name
  check(focus(spot),name.."：鏡頭對準擊殺地點",describeView(spot))
  local tag="corpse-"..name
  local result=helper:InvokeServer("kill",spot,tag)
  if not check(result~=nil,name.."：生成電腦村民（生命 1）與自己的弓箭手並以正式攻擊下令") then return nil end
  focus(result.position)
  local rec=findRecord(true,tag,15)
  if not check(rec~=nil,name.."：戰鬥擊殺後 workspace.Corpses 出現屍體") then return nil end
  helper:InvokeServer("remove")
  corpseAttributes(rec,name)
  if not check(tagged(rec,3),name.."：收到伺服器最終位置（RemainsServerCFrame）") then return rec end
  info(name.." 出現時："..rec.viewText..string.format("，已過 %.2f 秒，%d 個零件",rec.age or -1,#rec.parts))
  if reduced then
   check(rec.reduced,name.."：前置：本機 ReducedMotion=true")
   local move,angle=firstDeviation(rec)
   check(move<=.05 and angle<=.02,name.."：降低動態效果時屍體一出現就是伺服器的平躺位置（不倒地）",fmt(move,angle))
   -- 等過一般倒地所需的時間，確認全程沒有動。
   waitFor(function() return os.clock()-rec.appearClock>=Rules.FallSeconds+.3 end,Rules.FallSeconds+1)
   check(rec.preFadeMove<=.02 and rec.preFadeAngle<=.02,name.."：降低動態效果時倒地期間零件沒有移動",fmt(rec.preFadeMove,rec.preFadeAngle))
  else
   check(rec.view and (rec.age or 1)<.5,name.."：前置：屍體出現時在畫面與視野內且剛倒下（Remains 會播倒地）",rec.viewText)
   local move,angle=math.huge,math.huge
   if typeof(rec.base)=="CFrame" and typeof(rec.lay)=="CFrame" then move,angle=firstDeviation(rec,uprightOf(rec)) end
   check(move<=1 and angle<=.35,name.."：剛出現時零件是直立姿勢（base·lay⁻¹·base⁻¹·最終位置）",fmt(move,angle))
   local finalMove,finalAngle=firstDeviation(rec)
   check(finalAngle>=.6 or finalMove>=1.5,name.."：剛出現的姿勢與伺服器平躺位置不同",fmt(finalMove,finalAngle))
   local done=waitFor(function()
    local m,a,count=currentDeviation(rec)
    return count>0 and m<=.05 and a<=.02
   end,Rules.FallSeconds+1.5)
   local m,a=currentDeviation(rec)
   check(done~=nil,name.."：倒地結束後零件到達伺服器的最終平躺位置",fmt(m,a)..string.format("，出現後 %.2f 秒",os.clock()-rec.appearClock))
  end
  return rec
 end
 local function finishCorpse(rec,name,reduced)
  if not rec then return end
  stage=name.."（淡出與移除）"
  corpseRemoval(rec,name)
  corpseFade(rec,name,reduced)
 end

 -- 倒塌複本：expect={kind,visible,dust,motion="sink"|"topple"|"settle"|"none"}
 local function finishRuin(rec,name,expect)
  ruinAttributes(rec,name,expect.kind)
  tagged(rec,3)
  info(name.." 出現時："..rec.viewText..string.format("，%d 個零件，揚塵 %d",#rec.parts,rec.dust))
  if expect.visible then
   check(rec.view and (rec.age or 99)<(rec.seconds or 0)*.5,name.."：前置：出現時在畫面與視野內（Remains 會播放）",rec.viewText)
   check(not rec.firstHidden,name.."：開始時可見（沒有被立即隱藏）")
  end
  check(rec.dust==expect.dust,name.."：RTSRemainsEffects 的 CollapseDust 數量為 "..expect.dust,"實際 "..rec.dust)
  local removed=ruinRemoval(rec,name)
  if expect.motion=="sink" then
   check(rec.maxDown>=.2*(rec.height or math.huge),name.."：零件下沉",string.format("最大下沉 %.2f（高度 %.1f）",rec.maxDown,rec.height or 0))
  elseif expect.motion=="topple" then
   check(rec.maxTopAngle>=.5,name.."：樹幹與樹冠倒下（離地 1.5 以上的零件旋轉）",string.format("最大旋轉 %.2f rad",rec.maxTopAngle))
  elseif expect.motion=="settle" then
   check(rec.maxDown>=.05,name.."：零件下沉",string.format("最大下沉 %.2f",rec.maxDown))
  else
   check(rec.maxMove<=.01 and rec.maxAngle<=.01,name.."：零件沒有移動",fmt(rec.maxMove,rec.maxAngle))
  end
  if expect.visible then
   check(removed and rec.maxLTM>=.99,name.."：移除前淡出到完全透明",string.format("最大 LocalTransparencyModifier %.2f",rec.maxLTM))
  else
   check(rec.firstHidden and rec.maxLTM>=.999,name.."：一出現就隱藏（所有零件 LocalTransparencyModifier=1）",rec.viewText)
  end
  if expect.dust>0 then
   local cleared=waitFor(function() return dustNear(rec.point,45)==0 end,Rules.CollapseSeconds+.2+1.5-(os.clock()-rec.appearClock))
   check(cleared~=nil,name.."：揚塵在 CollapseSeconds+0.2 秒後清除","剩 "..dustNear(rec.point,45))
  end
 end
 local function buildingTest(name,spot,view,attacker,attackerDistance,expect)
  stage=name
  local tag="ruin-"..name
  local built=helper:InvokeServer("build",spot,tag,view=="fog" and "far" or nil)
  if not check(built~=nil,name.."：放置電腦的已完工房屋") then return end
  local ground=built.ground
  if view=="visible" then
   check(focus(ground),name.."：鏡頭對準房屋",describeView(ground))
  elseif view=="offscreen" then
   local far
   for _,candidate in ipairs({at(330,330),at(0,520),at(520,0),at(600,600)}) do
    focus(candidate)
    if waitFor(function() return not inView(ground) end,2) then far=candidate; break end
   end
   check(far~=nil,name.."：前置：鏡頭移開後房屋不在畫面內",describeView(ground))
  elseif view=="fog" then
   focus(ground)
   local ready=waitFor(function()
    local shown,depth=onScreen(ground)
    return shown and depth<Rules.MaxDistance and FogView.Active() and not FogView.VisibleAt(ground)
   end,5)
   check(ready~=nil,name.."：前置：房屋在畫面內但位於迷霧（目前看不見）",describeView(ground))
  end
  local spot2=flat(ground)+(home-flat(ground)).Unit*attackerDistance
  if not check(helper:InvokeServer("strike",tag,attacker,spot2)==true,name.."：生命設為 1，自己的"..(attacker=="trebuchet" and "巨型投石機" or "弓箭手").."以正式攻擊下令") then return end
  local rec=findRecord(false,tag,attacker=="trebuchet" and 25 or 15)
  if not check(rec~=nil,name.."：完工建築被摧毀後 workspace.Ruins 出現倒塌複本") then return end
  helper:InvokeServer("remove")
  if view=="offscreen" then
   check(not rec.screen or (rec.depth or 0)>=Rules.MaxDistance,name.."：前置：複本出現時在畫面外（不是因為迷霧）",rec.viewText)
  elseif view=="fog" then
   check(rec.screen and (rec.depth or math.huge)<Rules.MaxDistance and rec.fogVisible==false,name.."：前置：複本出現時在畫面內、但位於迷霧",rec.viewText)
  end
  finishRuin(rec,name,expect)
 end
 local function resourceTest(name,names,near,expect)
  stage=name
  local tag="ruin-"..name
  local prep,used
  for _,resourceName in ipairs(names) do
   prep=helper:InvokeServer("resource",resourceName,near,tag)
   if prep then used=resourceName; break end
  end
  if not check(prep~=nil,name.."：找到附近沒有其他單位的 "..table.concat(names,"／").." 並在旁邊生成村民",used) then return end
  local villager=findUnit(prep.villagerTag,5)
  if not check(villager~=nil,name.."：測試村民複製到客戶端") then return end
  check(focus(prep.ground),name.."：鏡頭對準資源",describeView(prep.ground))
  waitFor(function() return inView(prep.ground) end,3)
  check(helper:InvokeServer("deplete",tag)==true,name.."：鏡頭就位後把存量設為 1")
  command:FireServer("Order",{villager},prep.model)
  local rec=findRecord(false,tag,25)
  if not check(rec~=nil,name.."：村民以正式 Order 採到 0 後 workspace.Ruins 出現複本") then return end
  check(waitFor(function() return prep.model.Parent==nil end,3)~=nil,name.."：原資源已由伺服器移除")
  info(name.." 測試村民攜帶 "..tostring(villager:GetAttribute("Carrying")).." "..tostring(villager:GetAttribute("CarryType")))
  helper:InvokeServer("remove")
  finishRuin(rec,name,expect)
 end

 -- A. 一般戰鬥擊殺（背景等待淡出）
 local savedMotion=player:GetAttribute("ReducedMotion")
 player:SetAttribute("ReducedMotion",false)
 local corpseA=corpseTest("屍體A",at(40,40),false)
 -- B～D. 倒塌複本（屍體 A 在背景繼續取樣，約 20 秒後淡出）
 buildingTest("建築倒塌",at(55,25),"visible","archer",22,{kind="building",visible=true,dust=Rules.CollapseDust,motion="sink"})
 resourceTest("樹木倒下",{"Tree"},home+inward*40,{kind="tree",visible=true,dust=0,motion="topple"})
 resourceTest("資源消失",{"Gold","Stone","Berries"},home+inward*40,{kind="resource",visible=true,dust=0,motion="settle"})
 buildingTest("畫面外倒塌",at(15,70),"offscreen","archer",22,{kind="building",visible=false,dust=0,motion="none"})
 if FogView.Active() then
  buildingTest("迷霧中倒塌",home+inward*235,"fog","trebuchet",95,{kind="building",visible=false,dust=0,motion="none"})
 else info("戰爭迷霧未啟用，略過迷霧中倒塌") end
 finishCorpse(corpseA,"屍體A",false)

 -- E. 降低動態效果
 player:SetAttribute("ReducedMotion",true)
 local corpseB=corpseTest("屍體B（降低動態效果）",at(65,60),true)
 buildingTest("建築倒塌（降低動態效果）",at(30,75),"visible","archer",22,{kind="building",visible=true,dust=0,motion="none"})
 finishCorpse(corpseB,"屍體B（降低動態效果）",true)
 player:SetAttribute("ReducedMotion",savedMotion)
 hold=nil

 -- F. 清理
 stage="清理"
 local longest=math.max(Rules.CollapseSeconds,Rules.TreeFallSeconds,Rules.ResourceFadeSeconds)+.5
 check(waitFor(function() return not workspace:FindFirstChild("Ruins") or #workspace.Ruins:GetChildren()==0 end,longest+2.5)~=nil,
  "客戶端 workspace.Ruins 已清空",workspace:FindFirstChild("Ruins") and #workspace.Ruins:GetChildren())
 check(waitFor(function() return dustNear(nil,0)==0 end,Rules.CollapseSeconds+1.5)~=nil,"RTSRemainsEffects 沒有殘留的 CollapseDust",dustNear(nil,0))
 local stale=0
 for _,corpse in ipairs(workspace:FindFirstChild("Corpses") and workspace.Corpses:GetChildren() or {}) do
  local expires=corpse:GetAttribute("CorpseExpires")
  if type(expires)~="number" or expires<serverNow()-1.5 or corpse:GetAttribute("RemainsTestTag") then stale+=1 end
 end
 check(stale==0,"workspace.Corpses 沒有過期或測試留下的屍體","不該存在 "..stale.." 個")
 local summary=helper:InvokeServer("summary")
 check(summary and summary.ruinsNow==0 and summary.staleCorpses==0,"伺服器 Ruins 已清空、沒有過期屍體",
  summary and string.format("Ruins %d、Corpses %d、過期 %d、建立屍體 %d、複本 %d",summary.ruinsNow,summary.corpsesNow,summary.staleCorpses,summary.corpsesCreated,summary.ruinsCreated))

 -- 雙人：通知觀察者並等待回報
 if duo then
  stage="等待 Player2 回報"
  helper:InvokeServer("phase","done")
  local report=waitFor(function() return workspace:GetAttribute("RemainsObserverReport") end,60)
  if check(report~=nil,"Player2 回報觀察結果") then
   local name,p,f,corpses,ruins=string.match(report,"^(.-)|(%d+)|(%d+)|(%d+)|(%d+)$")
   observerReport={name=name,passed=tonumber(p) or 0,failed=tonumber(f) or 1,corpses=tonumber(corpses),ruins=tonumber(ruins)}
   check(observerReport.failed==0,(name or "Player2").." 的客戶端檢查全部通過",string.format("%s passed, %s failed，看到屍體 %s、複本 %s",tostring(p),tostring(f),tostring(corpses),tostring(ruins)))
  end
 end

 -- 回大廳後 Factory.clearCorpses 清空（雙人時 Player2 回報後也會投降）。
 stage="回大廳"
 command:FireServer("Surrender")
 local ended=waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,30)
 if check(ended~=nil,"投降後對局結束",workspace:GetAttribute("MatchPhase")) then
  command:FireServer("RestartMatch")
  local lobby=waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" end,30)
  check(lobby~=nil,"回到大廳",workspace:GetAttribute("MatchPhase"))
  local emptied=waitFor(function()
   local corpses,ruins=workspace:FindFirstChild("Corpses"),workspace:FindFirstChild("Ruins")
   return (not corpses or #corpses:GetChildren()==0) and (not ruins or #ruins:GetChildren()==0)
  end,5)
  check(emptied~=nil,"回大廳後客戶端 Corpses／Ruins 皆清空")
  summary=helper:InvokeServer("summary")
  check(summary and summary.corpsesNow==0 and summary.ruinsNow==0,"回大廳後伺服器 Corpses／Ruins 皆清空",
   summary and string.format("Corpses %d、Ruins %d",summary.corpsesNow,summary.ruinsNow))
 end
 serverSummary=helper:InvokeServer("summary")
end

-- Player2：觀察者 --------------------------------------------------------------------
local function observer()
 local Lobby=require(RS.Shared.LobbyTests)
 stage="等待 Player1 建立兩人房間"
 assert(waitFor(function()
  return room("Room1","Configured")==true and room("Room1","ExpectedPlayers")==2 and (room("Room1","Players") or 0)==1
 end,90),"Player1 沒有建立兩人房間")
 Lobby.Join("Room1")
 stage="等待開局"
 assert(readyUntilBattle("Room1",60),"兩人對局沒有開始")
 local matchClock=os.clock()
 helper=assert(RS:WaitForChild("RemainsTestHelper",20),"RemainsTestHelper 不存在")
 command:FireServer("AutoWork",false)
 check(waitFor(remainsReady,10),"Remains.client.lua 已初始化（RTSRemainsReady、RTSRemainsEffects）")
 stage="觀察 Player1 的測試"
 assert(waitFor(function() return workspace:GetAttribute("RemainsHarnessPhase")=="done" end,TIMEOUT),"Player1 沒有完成")
 stage="檢查觀察結果"
 local corpses,ruins=0,0
 for _,rec in ipairs(recordList) do
  if rec.appearClock<matchClock-1 or rec.preexisting or not rec.ready then continue end
  tagged(rec,3)
  if rec.corpse then
   corpses+=1
   local name="屍體 #"..corpses
   corpseAttributes(rec,name)
   if typeof(rec.base)~="CFrame" or typeof(rec.lay)~="CFrame" then info(name.." 缺少姿勢屬性，略過倒地檢查")
   elseif rec.age and rec.age<.35 and rec.view and not rec.reduced then
    local move,angle=firstDeviation(rec,uprightOf(rec))
    check(move<=1 and angle<=.35,name.."：在畫面內剛倒下，開始時直立",fmt(move,angle))
   elseif rec.age and (rec.age>.65 or not rec.view or rec.reduced) then
    local move,angle=firstDeviation(rec)
    check(move<=.05 and angle<=.02,name.."：不在畫面內（或非剛倒下），直接平躺不倒地",rec.viewText.."；"..fmt(move,angle))
   else info(name.." 出現時間在判定邊界，略過倒地檢查") end
   if rec.removed and rec.removedPhase=="Playing" and type(rec.expires)=="number" then
    local late=rec.removedServer-rec.expires
    check(late>=-.5 and late<=1.5,name.."：伺服器在 CorpseExpires 移除",string.format("%+.2f 秒",late))
    check(rec.fadeSamples>0 and rec.fadeLTM>=.3 and rec.preFadeLTM<=.01,name.."：最後 "..Rules.FadeSeconds.." 秒淡出",string.format("最大 %.2f",rec.fadeLTM))
   elseif not rec.removed then info(name.." 尚未到期，略過移除與淡出") end
  else
   ruins+=1
   local name="複本 #"..ruins.." "..tostring(rec.kind)
   ruinAttributes(rec,name)
   if rec.age and rec.age>=(rec.seconds or 0)*.5 then info(name.." 出現時已過半，略過")
   elseif rec.view then
    check(not rec.firstHidden,name.."：在畫面與視野內，開始播放",rec.viewText)
    if rec.removed then check(rec.maxLTM>=.99,name.."：移除前淡出到完全透明",string.format("%.2f",rec.maxLTM)) end
   else
    check(rec.firstHidden,name.."：不在畫面內或位於迷霧，一出現就隱藏（LocalTransparencyModifier=1）",rec.viewText)
    check(rec.maxMove<=.01 and rec.maxAngle<=.01 and rec.dust==0,name.."：隱藏的複本不移動、不揚塵",fmt(rec.maxMove,rec.maxAngle).."，揚塵 "..rec.dust)
   end
   if rec.removed and rec.removedPhase=="Playing" and type(rec.start)=="number" and type(rec.seconds)=="number" then
    local late=rec.removedServer-(rec.start+rec.seconds+.5)
    check(late>=-.5 and late<=1.5,name.."：伺服器在 RuinSeconds+0.5 秒移除",string.format("%+.2f 秒",late))
   end
  end
 end
 local serverCorpses,serverRuins=workspace:GetAttribute("RemainsServerCorpses") or 0,workspace:GetAttribute("RemainsServerRuins") or 0
 check(corpses>=serverCorpses and ruins>=serverRuins and ruins>0,"雙人同步：本客戶端看到伺服器建立的全部屍體與複本",
  string.format("屍體 %d／%d、複本 %d／%d",corpses,serverCorpses,ruins,serverRuins))
 check(waitFor(function() return not workspace:FindFirstChild("Ruins") or #workspace.Ruins:GetChildren()==0 end,4)~=nil,"workspace.Ruins 已清空")
 check(dustNear(nil,0)==0,"RTSRemainsEffects 沒有殘留的 CollapseDust")
 helper:InvokeServer("report",passed,failed,corpses,ruins)
 command:FireServer("Surrender")
end

-- 啟動 -------------------------------------------------------------------------------
task.delay(TIMEOUT,function()
 finish(string.format("INCOMPLETE %d passed, %d failed（逾時 %d 秒，停在「%s」）",passed,failed,TIMEOUT,stage))
end)
task.spawn(function()
 local ok,problem=pcall(function()
  assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,60),"初始化逾時")
  stage="等待其他客戶端"
  -- run-studio-harness 以 2 位玩家啟動時，第二個客戶端幾秒內就會連上。
  -- Player1 以外的客戶端等久一點，避免第一個客戶端較慢時誤判成單人而各自開局。
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
   label="[REMAINS "..player.Name.."] "
   info("雙人模式：本客戶端為觀察者，主控為 "..leader.Name)
   observer()
  end
 end)
 if finished then return end
 if role~="observer" then
  -- 中斷時仍把伺服器已完成的檢查算進總結。
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
   -- 讓主控不必等到逾時。
   if helper and not workspace:GetAttribute("RemainsObserverReport") then pcall(function() helper:InvokeServer("report",passed,failed,0,0) end) end
  end
  finish(string.format("DONE %d passed, %d failed",passed,failed))
 end
end)
