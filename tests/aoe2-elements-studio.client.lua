-- Test-only LocalScript, mapped only by aoe2-elements-validation.project.json.
-- Studio CLIENT：以正常大廳指令開一局（1 真人＋1 簡單電腦、小地圖、豐富資源、征服），驗收新加入的 AOE2 元素：
--  1. 戰爭迷霧：黑幕與暗霧零件、己方主城可見、未見過的敵方主城隱藏且不能點選、小地圖迷霧。
--  2. 羊群：開局 4 隻己方綿羊、不佔人口；村民宰殺後採集；斥候靠近中立羊群就接收。
--  3. 野豬：村民圍獵時野豬生命下降並反擊，打倒後可採集。
--  4. 市集：買入照伺服器報價扣款且漲價；FFA 沒有盟友時進貢被拒絕、不扣款。
--  5. 姿態：堅守姿態的弓兵不追擊射程外的敵人；改回攻擊姿態後會追擊。
--  6. 城鎮警鐘：村民進入駐紮建築，解除後離開。
--  7. 科技與兵種：石工術提高建築生命；沒有化學時不能訓練射石砲；木柵牆整排放置。
-- 捷徑見 tests/aoe2-elements-studio.server.lua。輸出以 [AOE2X] 開頭。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local TAG="[AOE2X] "
local passed,failed=0,0
local function check(condition,message,detail)
 if condition then passed+=1; print(TAG.."PASS "..message..(detail~=nil and ("  ("..tostring(detail)..")") or ""))
 else failed+=1; warn(TAG.."FAIL "..message..(detail~=nil and ("  ("..tostring(detail)..")") or "")) end
 return condition
end
local function waitFor(predicate,seconds)
 local deadline=os.clock()+seconds
 repeat
  local value=predicate()
  if value then return value end
  task.wait(0.25)
 until os.clock()>deadline
 return nil
end
local running=false
local ok,problem=pcall(function()
 assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30),"初始化逾時")
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 task.wait(3)
 local Config=require(RS.GameData.GameConfig)
 local FogView=require(RS.Shared.FogView)
 local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
 local server=assert(RS:WaitForChild("AOE2ElementsTest",20),"伺服器測試輔助不存在")
 RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message)
  if type(message)=="string" and message~="" then print(TAG.."INFO 通知："..message) end
 end)
 local function mine(kind,folder)
  local result={}
  for _,model in ipairs(workspace[folder or "Units"]:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and (model:GetAttribute("UnitType")==kind or model:GetAttribute("BuildingType")==kind) then table.insert(result,model) end
  end
  return result
 end
 local function nearest(list,from)
  local best,bestDistance=nil,math.huge
  for _,model in ipairs(list) do
   local d=(model:GetPivot().Position-from).Magnitude
   if d<bestDistance then best,bestDistance=model,d end
  end
  return best
 end
 local home=player:GetAttribute("HomePosition")
 local center=mine("TownCenter","Buildings")[1]

 -- 1. 戰爭迷霧 ---------------------------------------------------------------
 local fog=waitFor(function() return workspace:FindFirstChild("RTSFogOfWar") end,5)
 check(FogView.Active() and fog~=nil and #fog:GetChildren()>0,"戰爭迷霧啟用並鋪上黑幕／暗霧",fog and #fog:GetChildren())
 check(FogView.VisibleAt(home) and FogView.CanSee(center),"己方主城位於視野內")
 local enemyCenter
 for _,model in ipairs(workspace.Buildings:GetChildren()) do
  if model:GetAttribute("BuildingType")=="TownCenter" and model:GetAttribute("OwnerId")~=player.UserId then enemyCenter=model end
 end
 if check(enemyCenter~=nil,"電腦主城存在") then
  local hiddenPart=false
  for _,part in ipairs(enemyCenter:GetDescendants()) do if part:IsA("BasePart") and part.Name~="Footprint" then hiddenPart=part.Transparency>=1; break end end
  check(not FogView.CanSee(enemyCenter) and hiddenPart,"未見過的敵方主城在迷霧中隱藏")
 end
 local minimap=player.PlayerGui:FindFirstChild("Minimap",true)
 local fogFrames=0
 if minimap then for _,frame in ipairs(minimap:GetChildren()) do if frame.Name=="MinimapFog" then fogFrames+=1 end end end
 check(fogFrames>0,"小地圖顯示黑色地圖",fogFrames)

 local info=server:InvokeServer("setup")
 check(info and info.ai~=nil and info.houses>=6,"測試前置：帝王時代、資源、房屋與電腦陣營",info and info.houses)
 running=true
 task.spawn(function()
  while running and workspace:GetAttribute("MatchPhase")=="Playing" do
   server:InvokeServer("aiDisarm")
   task.wait(3)
  end
 end)

 -- 2. 羊群 -------------------------------------------------------------------
 -- 自動工作會讓閒置村民先去宰殺主城旁的綿羊：開局綿羊＝現存綿羊＋已宰殺的羊肉。
 local sheep=mine("sheep")
 local slain=0
 for _,model in ipairs(workspace.Resources:GetChildren()) do
  if model.Name=="Sheep" and model:GetAttribute("Slain") and (model:GetPivot().Position-home).Magnitude<80 then slain+=1 end
 end
 check(#sheep+slain==Config.Herds.startSheep,"開局有已歸屬的綿羊",#sheep.." 隻＋已宰殺 "..slain)
 local nonHerd=0
 for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")~="sheep" then nonHerd+=1 end end
 check(player:GetAttribute("Population")==nonHerd,"綿羊不佔人口",tostring(player:GetAttribute("Population")).." / "..nonHerd)
 local villager=mine("villager")[1]
 if #sheep>0 and villager then
  local target=sheep[1]
  local spot=target:GetPivot().Position
  command:FireServer("Order",{villager},target)
  check(waitFor(function() return target.Parent==nil end,25),"村民宰殺指定的綿羊")
  local carcass=waitFor(function()
   for _,model in ipairs(workspace.Resources:GetChildren()) do
    if model.Name=="Sheep" and model:GetAttribute("Slain") and (model:GetPivot().Position-spot).Magnitude<12 then return model end
   end
  end,5)
  check(carcass~=nil,"宰殺後原地留下羊肉")
  check(waitFor(function() return (villager:GetAttribute("Carrying") or 0)>0 and villager:GetAttribute("CarryType")=="food" end,15),"村民採集羊肉")
 end
 local neutral
 for _,model in ipairs(workspace.Resources:GetChildren()) do if model:GetAttribute("Herdable") then neutral=neutral and nearest({neutral,model},home) or model end end
 if check(neutral~=nil,"地圖上有中立羊群") then
  local before=#mine("sheep")
  local scout=server:InvokeServer("spawn","scout",neutral:GetPivot().Position)
  check(scout~=nil and waitFor(function() return #mine("sheep")>before end,6),"斥候靠近中立羊群後接收綿羊",#mine("sheep"))
  if scout then server:InvokeServer("remove",scout) end
 end

 -- 3. 野豬 -------------------------------------------------------------------
 local boar
 for _,model in ipairs(workspace.Resources:GetChildren()) do if model.Name=="Boar" and (model:GetAttribute("BoarHP") or 0)>0 then boar=boar and nearest({boar,model},home) or model end end
 if check(boar~=nil,"地圖上有活的野豬") then
  local hunters={}
  for _=1,4 do
   local unit=server:InvokeServer("spawn","villager",boar:GetPivot().Position)
   if unit then table.insert(hunters,unit) end
  end
  task.wait(0.5)
  command:FireServer("Order",hunters,boar)
  local startHP=boar:GetAttribute("BoarHP")
  check(waitFor(function() return (boar:GetAttribute("BoarHP") or startHP)<startHP end,12),"村民圍獵時野豬生命下降")
  check(waitFor(function()
   for _,unit in ipairs(hunters) do if unit.Parent==nil or (unit:GetAttribute("HP") or 0)<(unit:GetAttribute("MaxHP") or 0) then return true end end
  end,20),"野豬會反擊圍獵的村民")
  check(waitFor(function() return boar:GetAttribute("Slain")==true end,40),"野豬被打倒")
  check(waitFor(function()
   for _,unit in ipairs(hunters) do if unit.Parent and (unit:GetAttribute("Carrying") or 0)>0 then return true end end
  end,15),"打倒後村民開始採集野豬肉")
 end

 -- 4. 市集與進貢 --------------------------------------------------------------
 local market=server:InvokeServer("build","Market",home)
 if check(market~=nil,"放置市集") then
  local price=workspace:GetAttribute("MarketBuy_food")
  local gold,food=player:GetAttribute("gold"),player:GetAttribute("food")
  command:FireServer("Trade",market,"food","Buy")
  check(waitFor(function() return player:GetAttribute("gold")==gold-price and player:GetAttribute("food")==food+Config.MarketTrade.batch end,5),"市集依伺服器報價買入",price)
  check(waitFor(function() return (workspace:GetAttribute("MarketBuy_food") or 0)>price end,3),"買入後食物漲價",workspace:GetAttribute("MarketBuy_food"))
  local wood=player:GetAttribute("wood")
  command:FireServer("Tribute",info.ai,"wood",100)
  task.wait(1.5)
  check(player:GetAttribute("wood")==wood,"FFA 中不能進貢給敵人，資源不變")
 end

 -- 5. 姿態 -------------------------------------------------------------------
 local archer=server:InvokeServer("spawn","archer",home+Vector3.new(0,0,-60))
 if check(archer~=nil,"生成測試弓兵") then
  check(archer:GetAttribute("Stance")==Config.Stances.default,"軍隊預設為攻擊姿態")
  command:FireServer("Stance",{archer},"StandGround")
  check(waitFor(function() return archer:GetAttribute("Stance")=="StandGround" end,3),"切換為堅守姿態")
  local start=archer:GetPivot().Position
  -- 目標是電腦的房屋：在一般索敵半徑內、堅守姿態的射程外，而且不會反擊。
  local enemy=server:InvokeServer("buildFor",start,66,info.ai)
  task.wait(4)
  check(enemy~=nil and (archer:GetPivot().Position-start).Magnitude<2 and archer:GetAttribute("OrderKind")~="attack","堅守姿態不追擊射程外的敵人",(archer:GetPivot().Position-start).Magnitude)
  command:FireServer("Stance",{archer},"Aggressive")
  check(waitFor(function() return archer:GetAttribute("OrderKind")=="attack" and (archer:GetPivot().Position-start).Magnitude>4 end,8),"改回攻擊姿態後主動接戰並追擊")
  if archer.Parent then server:InvokeServer("remove",archer) end
 end

 -- 6. 城鎮警鐘 ----------------------------------------------------------------
 command:FireServer("TownBell",center)
 check(waitFor(function() return player:GetAttribute("TownBell")==true end,3),"城鎮警鐘響起")
 check(waitFor(function() return server:InvokeServer("garrison")>=3 end,25),"村民進入駐紮建築",server:InvokeServer("garrison"))
 command:FireServer("TownBell",center)
 local function headingIn()
  for _,unit in ipairs(mine("villager")) do if unit:GetAttribute("OrderKind")=="garrison" then return true end end
  return false
 end
 check(waitFor(function() return player:GetAttribute("TownBell")==false and server:InvokeServer("garrison")==0 end,8),"解除警報後村民離開建築")
 task.wait(2)
 check(not headingIn() and server:InvokeServer("garrison")==0,"解除警報後沒有村民繼續前往駐紮")

 -- 7. 科技、兵種與木柵牆 -------------------------------------------------------
 local university=server:InvokeServer("build","University",home)
 if check(university~=nil,"放置大學") then
  local maxHP=center:GetAttribute("MaxHP")
  command:FireServer("Research",university,"Masonry")
  check(waitFor(function() return player:GetAttribute("Tech_Masonry")==true end,Config.Technologies.Masonry.time+8),"研究石工術")
  check(waitFor(function() return center:GetAttribute("MaxHP")>maxHP end,3),"石工術提高建築生命",tostring(maxHP).." → "..tostring(center:GetAttribute("MaxHP")))
 end
 local workshop=server:InvokeServer("build","SiegeWorkshop",home)
 if check(workshop~=nil,"放置攻城器械廠") then
  command:FireServer("Train",workshop,"bombardCannon")
  task.wait(1)
  check((workshop:GetAttribute("QueueCount") or 0)==0,"沒有化學時不能訓練射石砲")
  command:FireServer("Train",workshop,"scorpion")
  check(waitFor(function() return (workshop:GetAttribute("QueueCount") or 0)==1 end,3),"弩砲可以排入訓練")
 end
 local wood=player:GetAttribute("wood")
 local from=home+Vector3.new((home.X>0 and -1 or 1)*90,0,(home.Z>0 and -1 or 1)*130)
 command:FireServer("BuildLine","Palisade",from,from+Vector3.new(48,0,0),{})
 check(waitFor(function() return #mine("Palisade","Buildings")>=3 end,5),"木柵牆整排放置",#mine("Palisade","Buildings"))
 check(player:GetAttribute("wood")<wood,"木柵牆扣除木材")
end)
running=false
if not ok then warn(TAG.."FAIL 測試中斷："..tostring(problem)); failed+=1 end
print(string.format("%sCOMPLETE %d PASS / %d FAIL",TAG,passed,failed))
