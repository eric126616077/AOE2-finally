-- Test-only LocalScript, mapped only by damage-visuals-validation.project.json.
-- 以正常大廳指令開一局（1 真人＋1 簡單電腦），由伺服器輔助直接設定建築生命，
-- 再讀正式 BuildingVisuals.client.lua 的 Studio 探針與實際 Workspace 外觀，驗證受損外觀的階段、還原與清理。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local passed,failed=0,0
local function check(name,ok,detail)
 if ok then passed+=1 else failed+=1 end
 print("[DAMAGE_TEST] "..(ok and "PASS " or "FAIL ")..name..(detail~=nil and (" | "..tostring(detail)) or ""))
end
local function info(text) print("[DAMAGE_TEST] INFO "..text) end
local function waitFor(predicate,seconds)
 local deadline=os.clock()+seconds
 repeat
  if predicate() then return true end
  Run.Heartbeat:Wait()
 until os.clock()>deadline
 return predicate()==true
end
local function main()
 assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30),"初始化逾時")
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 local command=RS.RTSRemotes.Command
 local helper=RS:WaitForChild("DamageTestHelper",20)
 assert(helper,"DamageTestHelper 不存在")
 command:FireServer("AutoWork",false)
 RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message) if type(message)=="string" then info("伺服器通知："..message) end end)
 local probe=player:WaitForChild("PlayerScripts"):WaitForChild("RTSConstructionVisualProbe",15)
 assert(probe,"RTSConstructionVisualProbe 不存在")
 local effects=workspace:WaitForChild("RTSDamageEffects",5)
 assert(effects,"RTSDamageEffects 不存在")
 local unitFolder,buildingFolder=workspace.Units,workspace.Buildings
 local tc
 assert(waitFor(function()
  for _,building in ipairs(buildingFolder:GetChildren()) do
   if building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")=="TownCenter" then tc=building; return true end
  end
  return false
 end,10),"找不到自己的市鎮中心")
 local center=tc:GetPivot().Position
 center=Vector3.new(center.X,0,center.Z)
 local focus=require(RS.Shared.CameraFocus)
 local function look(model)
  local position=model:GetPivot().Position
  focus.Request(player,Vector3.new(position.X,0,position.Z))
 end
 local sequence=0
 local function tagged(folder,tag,seconds)
  local found
  waitFor(function()
   for _,model in ipairs(folder:GetChildren()) do if model:GetAttribute("TestTag")==tag then found=model; return true end end
   return false
  end,seconds)
  return found
 end
 local function build(kind,angle,distance)
  sequence+=1
  local tag="damage-"..sequence
  assert(helper:InvokeServer("build",kind,center+Vector3.new(math.cos(angle)*distance,0,math.sin(angle)*distance),tag),"放置 "..kind.." 失敗")
  local model=tagged(buildingFolder,tag,8)
  assert(model,kind.." 沒有複製到客戶端")
  -- 等所有部件複製完成。
  task.wait(0.6)
  return model
 end
 local function damage(model) return probe:Invoke(model).damage end
 local function setRatio(model,ratio)
  local maxHP=model:GetAttribute("MaxHP")
  local hp=math.max(1,math.floor(maxHP*ratio+0.5))
  assert(helper:InvokeServer("setHP",model,hp),"設定生命失敗")
  waitFor(function() return model:GetAttribute("HP")==hp end,3)
  -- 外觀更新是 deferred；多等兩個 frame。
  Run.Heartbeat:Wait(); Run.Heartbeat:Wait(); Run.Heartbeat:Wait()
 end
 local function overlayOf(model)
  local count=0
  for _,site in ipairs(effects:GetChildren()) do if site.Name=="Damage_"..model.Name then count+=1 end end
  return count
 end
 local function snapshot(model)
  local result={}
  for _,part in ipairs(model:GetDescendants()) do
   if part:IsA("BasePart") then result[part]={color=part.Color,modifier=part.LocalTransparencyModifier} end
  end
  return result
 end
 local function same(model,before)
  local parts,changed=0,0
  for part,value in pairs(before) do
   parts+=1
   if part.Parent==nil or part.Color~=value.color or part.LocalTransparencyModifier~=value.modifier then changed+=1 end
  end
  return changed==0,parts.." 個部件，"..changed.." 個不同"
 end
 local function keptVisible(model)
  local kept,hidden=0,0
  for _,part in ipairs(model:GetDescendants()) do
   if part:IsA("BasePart") and part.Transparency<1 and (part:GetAttribute("TeamColorPart")==true or part.Name=="GateDoor" or part.Name=="Flagpole") then
    kept+=1
    if part.LocalTransparencyModifier>=1 then hidden+=1 end
   end
  end
  return hidden==0,kept.." 個玩家色／旗桿／門扇，"..hidden.." 個被隱藏"
 end
 local function describe(state)
  return string.format("stage=%s broken=%s sooted=%s fires=%s effectParts=%s overlay=%s",tostring(state.stage),tostring(state.brokenParts),
   tostring(state.sootedParts),tostring(state.fires),tostring(state.effectParts),tostring(state.overlay))
 end
 -- 一棟建築的完整循環：60% → 50% → 33% → 36% → 45% → 52% → 55% → 100%。
 local function cycle(label,model,line)
  local before=snapshot(model)
  setRatio(model,.6)
  local state=damage(model)
  check(label.."：60% 仍完好",state.stage==0 and state.overlay==false and overlayOf(model)==0,describe(state))
  setRatio(model,.5)
  local half=damage(model)
  check(label.."：50% 進入受損",half.stage==1 and half.sootedParts>0 and half.overlay==true,describe(half))
  check(label.."：受損的火數",half.fires==(line and 0 or 1),"fires="..half.fires)
  local ok,detail=keptVisible(model)
  check(label.."：受損時玩家色部件仍可見",ok,detail)
  setRatio(model,.33)
  local ruined=damage(model)
  check(label.."：33% 進入殘破",ruined.stage==2 and ruined.brokenParts>=half.brokenParts and ruined.effectParts>half.effectParts,describe(ruined))
  check(label.."：殘破的火數",ruined.fires==(line and 0 or 3),"fires="..ruined.fires)
  info(label.." 脫落部件：受損 "..half.brokenParts.."、殘破 "..ruined.brokenParts.."（共 "..ruined.parts.." 個可見部件）")
  ok,detail=keptVisible(model)
  check(label.."：殘破時玩家色部件仍可見",ok,detail)
  setRatio(model,.36)
  check(label.."：修到 36% 仍殘破（緩衝）",damage(model).stage==2,describe(damage(model)))
  setRatio(model,.45)
  check(label.."：修到 45% 退回受損",damage(model).stage==1,describe(damage(model)))
  setRatio(model,.52)
  check(label.."：修到 52% 仍受損（緩衝）",damage(model).stage==1,describe(damage(model)))
  setRatio(model,.55)
  check(label.."：修到 55% 恢復完好",damage(model).stage==0 and overlayOf(model)==0,describe(damage(model)))
  setRatio(model,1)
  ok,detail=same(model,before)
  check(label.."：滿血後顏色與透明度完全還原",ok and damage(model).stage==0 and overlayOf(model)==0,detail)
 end
 local function hold(name,seconds)
  print("[DAMAGE_TEST] HOLD "..name.." "..seconds)
  task.wait(seconds)
  print("[DAMAGE_TEST] RELEASE "..name)
 end

 -- 1. 初始狀態
 check("開局時沒有受損疊加物件",#effects:GetChildren()==0,"children="..#effects:GetChildren())
 check("滿血市鎮中心為完好",damage(tc).stage==0,describe(damage(tc)))

 -- 2. 各種建築的階段循環
 local house=build("House",0.3,40)
 local castle=build("Castle",2.2,70)
 local wall=build("Wall",4.0,44)
 local gate=build("Gate",4.6,50)
 local farm=build("Farm",5.4,44)
 cycle("房屋",house,false)
 cycle("市鎮中心",tc,false)
 cycle("城堡",castle,false)
 cycle("石牆",wall,true)
 cycle("城門",gate,false)
 cycle("農田",farm,false)
 check("全部修復後沒有殘留疊加物件",#effects:GetChildren()==0,"children="..#effects:GetChildren())

 -- 3. 火與煙的發射器
 setRatio(house,.5)
 local site=effects:FindFirstChild("Damage_"..house.Name)
 local blaze=site and site:FindFirstChild("Blaze")
 local flame,smoke=blaze and blaze:FindFirstChild("Flame"),blaze and blaze:FindFirstChild("Smoke")
 check("受損房屋有火與煙的發射器",flame~=nil and smoke~=nil and flame.Enabled and smoke.Enabled and flame.Rate>0 and smoke.Rate>0,
  flame and (flame.Texture.." / "..smoke.Texture) or "找不到 Blaze")
 if blaze then info(string.format("房屋火焰位置 %s，占地 %s",tostring(blaze.Position),tostring(house.PrimaryPart.Size))) end
 check("受損階段沒有火光",blaze~=nil and blaze:FindFirstChildWhichIsA("PointLight")==nil)
 look(house)
 hold("house-stage1",14)
 setRatio(house,.3)
 site=effects:FindFirstChild("Damage_"..house.Name)
 local lights,beams,rubble=0,0,0
 for _,item in ipairs(site and site:GetDescendants() or {}) do
  if item:IsA("PointLight") then lights+=1 elseif item.Name=="CharredBeam" then beams+=1 elseif item.Name=="Rubble" then rubble+=1 end
 end
 check("殘破房屋：1 個火光、2 根焦梁、6 塊瓦礫",lights==1 and beams==2 and rubble==6,string.format("lights=%d beams=%d rubble=%d",lights,beams,rubble))
 hold("house-stage2",14)

 -- 4. 減少動態效果
 local savedMotion=player:GetAttribute("ReducedMotion")
 player:SetAttribute("ReducedMotion",true)
 task.wait(0.3)
 local reduced=damage(house)
 check("減少動態效果：火與煙消失、破損與瓦礫保留",reduced.stage==2 and reduced.fires==0 and reduced.brokenParts>0 and reduced.effectParts==8,describe(reduced))
 player:SetAttribute("ReducedMotion",false)
 task.wait(0.3)
 check("關閉減少動態效果後火恢復",damage(house).fires==3,describe(damage(house)))
 player:SetAttribute("ReducedMotion",savedMotion)
 task.wait(0.3)

 -- 5. 大型建築外觀（截圖用）
 setRatio(tc,.5)
 look(tc)
 hold("towncenter-stage1",12)
 setRatio(tc,.3)
 hold("towncenter-stage2",12)
 setRatio(castle,.3)
 look(castle)
 hold("castle-stage2",12)
 setRatio(wall,.3); setRatio(gate,.3)
 look(wall)
 hold("wall-gate-stage2",12)
 setRatio(tc,1); setRatio(castle,1); setRatio(wall,1); setRatio(gate,1)

 -- 6. 受損農田換階段（Factory.restage 會換掉全部部件）
 setRatio(farm,.3)
 local farmBefore=damage(farm)
 local oldPart
 for _,part in ipairs(farm:GetChildren()) do if part:IsA("BasePart") and part~=farm.PrimaryPart then oldPart=part; break end end
 local maxAmount=farm:GetAttribute("MaxAmount") or farm:GetAttribute("Amount")
 info("農田存量 "..tostring(farm:GetAttribute("Amount")).." / "..tostring(maxAmount).."，ResourceStage="..tostring(farm:GetAttribute("ResourceStage")))
 if type(maxAmount)=="number" and oldPart then
  assert(helper:InvokeServer("setAmount",farm,math.floor(maxAmount*.2)),"設定農田存量失敗")
  local restaged=waitFor(function() return oldPart.Parent==nil end,5)
  task.wait(0.5)
  local farmAfter=damage(farm)
  check("農田換階段後部件已重建",restaged,"ResourceStage="..tostring(farm:GetAttribute("ResourceStage")))
  check("換階段後仍是殘破且重新套用",farmAfter.stage==2 and farmAfter.parts>0 and farmAfter.sootedParts>0 and overlayOf(farm)==1,
   "之前 "..describe(farmBefore).."；之後 "..describe(farmAfter))
  look(farm)
  hold("farm-stage2",8)
  setRatio(farm,1)
  local sooty=0
  for _,part in ipairs(farm:GetDescendants()) do if part:IsA("BasePart") and part.LocalTransparencyModifier>=1 and part.Transparency<1 then sooty+=1 end end
  check("農田滿血後沒有隱藏部件與疊加物件",damage(farm).stage==0 and sooty==0 and overlayOf(farm)==0,describe(damage(farm)))
 else check("農田有存量屬性可測換階段",false) end

 -- 7. 施工中不顯示受損外觀（正式 Build 指令，初始生命遠低於 1/3）
 local siteCountBefore=#buildingFolder:GetChildren()
 local known={}
 for _,model in ipairs(buildingFolder:GetChildren()) do known[model]=true end
 local villagers={}
 for _,unit in ipairs(unitFolder:GetChildren()) do
  if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then table.insert(villagers,unit) end
 end
 local newSite
 for _,offset in ipairs({Vector3.new(34,0,-30),Vector3.new(-34,0,30),Vector3.new(-40,0,-36),Vector3.new(44,0,36)}) do
  command:FireServer("Build","House",center+offset,villagers)
  if waitFor(function()
   for _,model in ipairs(buildingFolder:GetChildren()) do
    if not known[model] and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("Complete")==false then newSite=model; return true end
   end
   return false
  end,3) then break end
 end
 if newSite then
  task.wait(0.5)
  local ratio=(newSite:GetAttribute("HP") or 0)/(newSite:GetAttribute("MaxHP") or 1)
  local state=damage(newSite)
  check("工地生命低於 1/3 但不顯示受損外觀",ratio<=1/3 and state.stage==0 and state.overlay==false and state.parts==0,string.format("ratio=%.3f %s",ratio,describe(state)))
  local finished=waitFor(function() return newSite.Parent==nil or newSite:GetAttribute("Complete")==true end,60)
  task.wait(0.5)
  if finished and newSite.Parent then
   local finalRatio=(newSite:GetAttribute("HP") or 0)/(newSite:GetAttribute("MaxHP") or 1)
   local expected=finalRatio<=1/3 and 2 or finalRatio<=.5 and 1 or 0
   check("完工後依實際生命決定階段",damage(newSite).stage==expected,string.format("ratio=%.3f %s",finalRatio,describe(damage(newSite))))
  else check("工地在 60 秒內完工",false,"progress="..tostring(newSite.Parent and newSite:GetAttribute("ConstructionProgress"))) end
 else check("正式 Build 指令建立房屋工地",false,"before="..siteCountBefore) end

 -- 8. 真實戰鬥：敵方攻城衝車把房屋打到倒塌
 local target=build("House",1.2,46)
 local targetPosition=target:GetPivot().Position
 local rams={}
 for index=1,4 do
  local tag="damage-ram-"..index
  local angle=1.2+(index-2.5)*.18
  if helper:InvokeServer("spawnEnemy","ram",center+Vector3.new(math.cos(angle)*64,0,math.sin(angle)*64),tag) then
   local ram=tagged(unitFolder,tag,6)
   if ram then table.insert(rams,ram); helper:InvokeServer("attack",ram,target) end
  end
 end
 info("生成敵方攻城衝車 "..#rams.." 台")
 look(target)
 local seen={[0]=true}
 local order={0}
 local overlayAtRuin=false
 local destroyed=waitFor(function()
  if target.Parent~=buildingFolder then return true end
  local state=damage(target)
  if state and not seen[state.stage] then seen[state.stage]=true; table.insert(order,state.stage) end
  if state and state.stage==2 and overlayOf(target)>=1 then overlayAtRuin=true end
  return false
 end,120)
 local stages={}
 for _,value in ipairs(order) do table.insert(stages,tostring(value)) end
 local monotone=true
 for index=2,#order do if order[index]<order[index-1] then monotone=false end end
 check("戰鬥中階段只升不降並到達殘破",monotone and seen[2]==true,"順序："..table.concat(stages,","))
 check("殘破時戰鬥房屋有疊加物件",overlayAtRuin)
 check("房屋被摧毀",destroyed,"HP="..tostring(target.Parent and target:GetAttribute("HP")))
 task.wait(0.5)
 -- 此時只有第 3 段留下的殘破房屋還在受損狀態。
 local leftovers={}
 for _,item in ipairs(effects:GetChildren()) do
  local pivot=item:GetPivot().Position
  if (Vector3.new(pivot.X,0,pivot.Z)-Vector3.new(targetPosition.X,0,targetPosition.Z)).Magnitude<12 then table.insert(leftovers,item.Name) end
 end
 check("被摧毀的房屋位置沒有殘留瓦礫或火",#leftovers==0,"leftovers="..#leftovers.." total="..#effects:GetChildren())
 for _,ram in ipairs(rams) do if ram.Parent then command:FireServer("Stop",{ram}) end end

 -- 9. 回大廳後清空（房屋仍在殘破狀態下結束）
 local totals=probe:Invoke()
 info(string.format("結束前：受損疊加 %s、火 %s、Workspace 內 %d 個",tostring(totals.damageOverlays),tostring(totals.damageFires),#effects:GetChildren()))
 check("結束前仍有受損建築可供清理檢查",#effects:GetChildren()>=1)
 command:FireServer("Surrender")
 local ended=waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,20)
 info("投降後 MatchPhase="..tostring(workspace:GetAttribute("MatchPhase")))
 if ended then
  command:FireServer("RestartMatch")
  local lobby=waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" end,20)
  task.wait(1)
  totals=probe:Invoke()
  check("回到大廳",lobby,"MatchPhase="..tostring(workspace:GetAttribute("MatchPhase")))
  check("回大廳後 RTSDamageEffects 為空且計數歸零",#effects:GetChildren()==0 and totals.damageOverlays==0 and totals.damageFires==0,
   string.format("children=%d overlays=%s fires=%s",#effects:GetChildren(),tostring(totals.damageOverlays),tostring(totals.damageFires)))
 else check("投降後對局結束",false) end
end
local ok,message=pcall(main)
if not ok then failed+=1; print("[DAMAGE_TEST] ERROR "..tostring(message)) end
print(string.format("[DAMAGE_TEST] DONE pass=%d fail=%d",passed,failed))
