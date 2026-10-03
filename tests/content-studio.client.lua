-- Test-only LocalScript, mapped only by content-validation.project.json.
-- Studio CLIENT：以正常大廳指令開一局（1 真人＋1 簡單電腦、小地圖、豐富資源、聖物勝利），驗收：
--  1. 鹿群：每個出生區都有鹿、村民用狩獵矛採集、鹿的食物減少。
--  2. 新兵種：騎射手／駱駝騎兵／火槍手經正式 Train 指令訓練出來，類別與數值正確。
--  3. 兵種升級：長劍兵、長戟兵研究完成後，現有單位改名、生命／攻擊／剋制加成提升，訓練卡名稱同步。
--  4. 貿易：貿易車在兩座己方市集之間往返，回到出發市集時黃金入帳。
--  5. 電腦：給電腦修道院與兩座市集後，它會自己訓練僧侶去撿聖物、訓練貿易車跑貿易。
--  6. 聖物：僧侶拾取、存放、修道院產金；攜帶者被移除時聖物掉落；集齊全部聖物後倒數並贏得對局。
-- 捷徑見 tests/content-studio.server.lua（時代、資源、直接放建築與單位）。輸出以 [CONTENT] 開頭。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local TAG="[CONTENT] "
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
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Relic",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 task.wait(3)
 local Config=require(RS.GameData.GameConfig)
 local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
 local server=assert(RS:WaitForChild("ContentStudioTest",20),"伺服器測試輔助不存在")
 local function mine(kind,folder)
  local result={}
  for _,model in ipairs(workspace[folder or "Units"]:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and (model:GetAttribute("UnitType")==kind or model:GetAttribute("BuildingType")==kind) then table.insert(result,model) end
  end
  return result
 end
 local function groundRelics()
  local result={}
  for _,model in ipairs(workspace.Resources:GetChildren()) do if model:GetAttribute("Relic")==true then table.insert(result,model) end end
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
 -- 把伺服器的每則通知印出來，任何失敗都能看到伺服器給的原因（例如人口已滿、勢力淘汰）。
 RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message)
  if type(message)=="string" and message~="" then print(TAG.."INFO 通知："..message) end
 end)
 local info=server:InvokeServer("setup")
 check(info and info.age==4 and info.ai~=nil and info.houses>=6,"測試前置：帝王時代、資源、房屋與電腦陣營",info and ("ai="..tostring(info.ai).." houses="..tostring(info.houses)))
 -- 測試期間持續移除電腦的戰鬥單位，避免電腦進攻淘汰玩家而讓後續項目失效。
 running=true
 task.spawn(function()
  while running and workspace:GetAttribute("MatchPhase")=="Playing" do
   local removed=server:InvokeServer("aiDisarm")
   if removed and removed>0 then print(TAG.."INFO 移除電腦戰鬥單位 "..removed) end
   task.wait(3)
  end
 end)
 local function guard(section)
  local d=server:InvokeServer("diag")
  print(TAG.."INFO "..section.."：單位 "..d.units.." 建築 "..d.buildings.." 人口 "..tostring(d.population).."/"..tostring(d.cap).." 階段 "..tostring(d.phase))
  assert(not d.defeated and d.phase=="Playing","玩家在「"..section.."」前已被淘汰或對局已結束")
 end
 -- 電腦需要時間訓練：先讓電腦準備，最後再檢查。
 local prepared=server:InvokeServer("aiPrepare")
 check(prepared and prepared.monastery and prepared.market and prepared.second,"測試前置：電腦的修道院與兩座市集",prepared and (tostring(prepared.monastery).."/"..tostring(prepared.market).."/"..tostring(prepared.second)))
 local home=player:GetAttribute("HomePosition")

 -- 1. 鹿群與狩獵 -------------------------------------------------------------
 local deer={}
 for _,model in ipairs(workspace.Resources:GetChildren()) do if model.Name=="Deer" then table.insert(deer,model) end end
 local perBase=0; for _,patch in ipairs(Config.Map.ResourceLayout.OpeningClusters) do if patch.kind=="Deer" then perBase=patch.count end end
 check(#deer==perBase*4,"四個出生區都有鹿群",#deer)
 check(#deer>0 and deer[1]:GetAttribute("Hunt")==true and deer[1]:GetAttribute("GatherMultiplier")==Config.Resources.Deer.gatherMultiplier and deer[1]:GetAttribute("ResourceType")=="food","鹿是可狩獵的食物資源")
 local hunter=mine("villager")[1]
 local prey=nearest(deer,home)
 local preyBefore=prey and prey:GetAttribute("Amount")
 command:FireServer("Order",{hunter},prey)
 check(waitFor(function() return (hunter:GetAttribute("Carrying") or 0)>0 and hunter:GetAttribute("CarryType")=="food" end,60),"村民走到鹿旁採集食物",hunter:GetAttribute("Carrying"))
 check(server:InvokeServer("tool",hunter)=="spear","打獵時換上狩獵矛",server:InvokeServer("tool",hunter))
 check(prey.Parent==nil or (prey:GetAttribute("Amount") or 0)<preyBefore,"鹿的食物減少",prey:GetAttribute("Amount"))
 command:FireServer("Stop",{hunter})

 guard("新兵種與兵種升級")
 -- 2／3. 新兵種與兵種升級 -------------------------------------------------------
 local archery=server:InvokeServer("build","ArcheryRange",home,{min=48,max=170})
 local stable=server:InvokeServer("build","Stable",home,{min=48,max=170})
 local barracks=server:InvokeServer("build","Barracks",home,{min=48,max=170})
 check(archery and stable and barracks,"測試前置：射箭場、馬廄、兵營")
 local infantry=server:InvokeServer("spawn","infantry",home+Vector3.new(0,0,30))
 local spearman=server:InvokeServer("spawn","spearman",home+Vector3.new(6,0,30))
 local baseHP,baseAttack=infantry:GetAttribute("MaxHP"),infantry:GetAttribute("Attack")
 command:FireServer("Train",archery,"cavalryArcher")
 command:FireServer("Train",archery,"handCannoneer")
 command:FireServer("Train",stable,"camel")
 command:FireServer("Research",barracks,"LongSwordsman")
 check(waitFor(function() return barracks:GetAttribute("Research")=="長劍兵" end,5),"長劍兵開始研究")
 check(waitFor(function() return player:GetAttribute("Tech_LongSwordsman")==true end,Config.Technologies.LongSwordsman.time+15),"長劍兵研究完成")
 check(waitFor(function() return infantry:GetAttribute("DisplayName")=="長劍兵" end,3),"現有步兵改名為長劍兵",infantry:GetAttribute("DisplayName"))
 check(infantry:GetAttribute("MaxHP")==baseHP+20 and infantry:GetAttribute("Attack")==baseAttack+3,"長劍兵生命 +20、攻擊 +3",infantry:GetAttribute("MaxHP").."/"..infantry:GetAttribute("Attack"))
 check(player:GetAttribute("UnitName_infantry")=="長劍兵","訓練卡名稱同步為長劍兵")
 command:FireServer("Research",barracks,"Pikeman")
 check(waitFor(function() return player:GetAttribute("Tech_Pikeman")==true end,Config.Technologies.Pikeman.time+15),"長戟兵研究完成")
 check(waitFor(function() return spearman:GetAttribute("Bonus_cavalry")==Config.Units.spearman.bonus.cavalry+10 end,3),"長戟兵對騎兵加成 +10",spearman:GetAttribute("Bonus_cavalry"))
 local cavalryArcher=waitFor(function() return mine("cavalryArcher")[1] end,Config.Units.cavalryArcher.trainTime+15)
 check(cavalryArcher and cavalryArcher:GetAttribute("UnitClass")=="cavalry" and cavalryArcher:GetAttribute("Range")>20,"騎射手訓練完成，是騎乘的遠程單位",cavalryArcher and cavalryArcher:GetAttribute("Range"))
 local camel=waitFor(function() return mine("camel")[1] end,Config.Units.camel.trainTime+15)
 check(camel and camel:GetAttribute("UnitClass")=="cavalry","駱駝騎兵訓練完成")
 local cannon=waitFor(function() return mine("handCannoneer")[1] end,Config.Units.handCannoneer.trainTime+20)
 check(cannon and cannon:GetAttribute("Attack")>=Config.Units.handCannoneer.damage,"火槍手訓練完成",cannon and cannon:GetAttribute("Attack"))

 guard("貿易")
 -- 4. 貿易 ----------------------------------------------------------------------
 local marketA=server:InvokeServer("build","Market",home,{min=48,max=170})
 local marketB=marketA and server:InvokeServer("build","Market",home,{min=48,max=190,awayFrom=marketA:GetPivot().Position,minAway=Config.Trade.minDistance+20})
 check(marketA and marketB,"測試前置：兩座相距足夠的市集",marketA and marketB and math.floor((marketA:GetPivot().Position-marketB:GetPivot().Position).Magnitude))
 command:FireServer("Train",marketA,"tradeCart")
 local cart=waitFor(function() return mine("tradeCart")[1] end,Config.Units.tradeCart.trainTime+15)
 check(cart~=nil,"貿易車訓練完成")
 if cart and marketB then
  local goldBefore=player:GetAttribute("gold") or 0
  command:FireServer("Order",{cart},marketB)
  check(waitFor(function() return cart:GetAttribute("OrderKind")=="trade" end,3),"貿易車接受貿易指令")
  check(waitFor(function() return (cart:GetAttribute("TradeGold") or 0)>0 end,60),"抵達目的地後裝貨",cart:GetAttribute("TradeGold"))
  local cargo=cart:GetAttribute("TradeGold") or 0
  check(waitFor(function() return (player:GetAttribute("TradeIncome") or 0)>=cargo and cargo>0 end,60),"回到出發市集後黃金入帳",player:GetAttribute("TradeIncome"))
  check((player:GetAttribute("gold") or 0)>=goldBefore+cargo-300,"玩家黃金增加（容許期間其他花費）")
  check(waitFor(function() return cart:GetAttribute("OrderKind")=="trade" end,5),"入帳後自動繼續下一趟")
 end

 guard("電腦撿聖物與跑貿易")
 -- 5. 電腦撿聖物與跑貿易（電腦在測試一開始就已準備）。兩者都觀察到後才讓電腦退回黑暗時代。
 local seen,trading
 waitFor(function()
  local s=server:InvokeServer("aiState")
  if s and (s.seeking>0 or s.carrying>0) then seen=seen or s end
  if s and s.trading>0 then trading=trading or s end
  return seen and trading
 end,180)
 server:InvokeServer("aiStop")
 check(seen~=nil,"電腦訓練僧侶並派去撿聖物",seen and ("monks="..seen.monks))
 check(trading~=nil,"電腦訓練貿易車並跑貿易",trading and ("carts="..trading.carts))

 guard("聖物")
 -- 6. 聖物：拾取、存放、收入、掉落、聖物勝利 ----------------------------------------
 local total=workspace:GetAttribute("RelicTotal") or 0
 check(total==Config.Relics.counts.Small,"小地圖放置設定數量的聖物",total)
 check(waitFor(function() return #groundRelics()==total end,30),"電腦停止後聖物都在地上",#groundRelics())
 local monastery=server:InvokeServer("build","Monastery",home,{min=48,max=180})
 check(monastery~=nil,"測試前置：修道院")
 local monks={}
 for i=1,total+1 do monks[i]=server:InvokeServer("spawn","monk",home+Vector3.new(i*5-15,0,-30)) end
 -- 先驗掉落：一位僧侶撿起最近的聖物後被移除，聖物應回到地上。
 local first=nearest(groundRelics(),home)
 command:FireServer("Order",{monks[total+1]},first)
 check(waitFor(function() return monks[total+1]:GetAttribute("CarryingRelic")==true end,120),"僧侶拾取聖物",monks[total+1]:GetAttribute("OrderKind"))
 check(#groundRelics()==total-1,"拾取後地上少一件",#groundRelics())
 command:FireServer("Order",{monks[total+1]},infantry)
 task.wait(0.5)
 check(monks[total+1]:GetAttribute("CarryingRelic")==true,"攜帶聖物時其他指令不會讓聖物消失")
 server:InvokeServer("remove",monks[total+1])
 check(waitFor(function() return #groundRelics()==total end,5),"攜帶者被移除時聖物掉回地上",#groundRelics())
 -- 收集全部聖物：每位僧侶各拿一件，拿到後自動送回修道院。
 local relics=groundRelics()
 for i,relic in ipairs(relics) do command:FireServer("Order",{monks[i]},relic) end
 local firstStored=waitFor(function() return (monastery:GetAttribute("Relics") or 0)>=1 end,150)
 check(firstStored,"聖物存放到修道院",monastery:GetAttribute("Relics"))
 if firstStored then
  local goldBefore=player:GetAttribute("RelicGold") or 0
  task.wait(4.5)
  check((player:GetAttribute("RelicGold") or 0)>goldBefore,"存放的聖物持續產生黃金",player:GetAttribute("RelicGold"))
 end
 check(waitFor(function() return (player:GetAttribute("Relics") or 0)==total end,200),"集齊全部聖物",player:GetAttribute("Relics"))
 guard("聖物勝利倒數")
 local countdown=waitFor(function() return player:GetAttribute("RelicRemaining") end,5)
 check(countdown and countdown<=Config.Relics.victoryTime,"聖物勝利開始倒數",countdown)
 local guiObjective=player.PlayerGui:FindFirstChild("AOE2_MainGUI") and player.PlayerGui.AOE2_MainGUI:FindFirstChild("MatchObjective",true)
 if guiObjective and guiObjective:IsA("TextLabel") then check(guiObjective.Text:find("勝利倒數")~=nil,"畫面目標顯示勝利倒數",guiObjective.Text) end
 check(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,Config.Relics.victoryTime+20),"守住倒數後對局結束")
 check(workspace:GetAttribute("WinnerId")==player.UserId,"聖物勝利的勝利者是玩家",workspace:GetAttribute("WinnerId"))
end)
if not ok then failed+=1; warn(TAG.."FAIL 測試中斷："..tostring(problem)) end
running=false
print(string.format("%s%s %d passed, %d failed",TAG,failed==0 and "COMPLETE" or "INCOMPLETE",passed,failed))
