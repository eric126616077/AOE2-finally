-- Explicit independent Studio CLIENT stages. Uses an already developed two-human FFA
-- with the requested NORMAL lobby mode; cannot switch victory mode in a Playing match.
-- RunConquest({army}) / RunRegicide({army}) command only real owned military.
-- RunWonder({position}) normally gathers, builds and observes the full 180s timer.
-- No surrender, Destroy(), HP/resources/age/timer changes. Failure preserves the battle.
local Tests={running=false}
local Context=require(script.Parent.CombatStageContext)
local function execute(label,mode,options,callback)
 assert(not Tests.running,"已有自然勝利階段執行中"); Tests.running=true
 options=options or {}; local context
 local ok,result=xpcall(function()
  context=Context.New(label,options.deadlineSeconds or 1800)
  context:Check(workspace:GetAttribute("VictoryMode")==mode,"由正常大廳開啟正確自然勝利模式")
  return context:Finish(callback(context,options))
 end,debug.traceback)
 if context then context:Close() end
 Tests.running=false; if not ok then error(result,0) end; return result
end
local function army(c,selection)
 assert(type(selection)=="table" and #selection>0 and #selection<=200,"需真實正常訓練的己方軍隊")
 local seen={}
 for _,unit in ipairs(selection) do
  c:Model(unit,c.units,c.player.UserId)
  c:Check(not seen[unit] and c.Config.Units[unit:GetAttribute("UnitType")].class~="villager" and (unit:GetAttribute("HP") or 0)>0,"軍隊非重複、非村民且真的存活")
  seen[unit]=true
 end
 return selection
end
local function liveArmy(c,selection)
 local result={}; for _,unit in ipairs(selection) do if unit.Parent==c.units and (unit:GetAttribute("HP") or 0)>0 then table.insert(result,unit) end end
 assert(#result>0,"正常戰鬥軍隊全部陣亡；不能生成替代單位")
 return result
end
local function attack(c,selection,target,seconds,allowEnded)
 local before=target:GetAttribute("HP"); local observedDamage=0; local previous=before
 local connection=target:GetAttributeChangedSignal("HP"):Connect(function()
  local hp=target:GetAttribute("HP")
  if type(hp)=="number" and hp<previous then observedDamage+=previous-hp end
  if type(hp)=="number" then previous=hp end
 end); table.insert(c.connections,connection)
 c:Send("Order",liveArmy(c,selection),target)
 c:Wait(function() return target.Parent~=c.units and target.Parent~=c.buildings end,seconds,"正常敵軍攻擊造成目標移除",allowEnded)
 connection:Disconnect()
 c:Check(type(before)=="number" and before>0,"目標戰鬥前具有真正 HP")
 return observedDamage
end
local function conquestLedger(startingVillagers,hasScout,trained,mine,theirs,initialUnits,initialBuildings)
 local function count(value) return type(value)=="number" and value>=0 and value<math.huge and value%1==0 end
 if not count(startingVillagers) or not count(trained) or not count(initialUnits) or not count(initialBuildings) then return nil end
 for _,entry in ipairs({{mine,"unitsKilled"},{mine,"buildingsKilled"},{theirs,"unitsLost"},{theirs,"buildingsLost"},{theirs,"buildingsCompleted"},{theirs,"villagersTrained"},{theirs,"militaryTrained"}}) do
  if not count(entry[1][entry[2]]) then return nil end
 end
 if trained~=theirs.villagersTrained+theirs.militaryTrained then return nil end
 local births=startingVillagers+(hasScout and 1 or 0)+trained
 local buildings=math.max(1+theirs.buildingsCompleted,initialBuildings)
 return {unitBirths=births,minimumBuildingBirths=buildings,
  allUnitsDied=initialUnits<=births and theirs.unitsLost==births and mine.unitsKilled==births,
  allCompletedBuildingsDied=theirs.buildingsLost>=buildings and mine.buildingsKilled>=buildings}
end
function Tests.RunConquest(options)
 return execute("NATURAL_CONQUEST","Conquest",options,function(c,o)
  local selection=army(c,o.army)
  local initialUnits=#c:Models(c.units,c.other.UserId)
  local initialBuildings=#c:Models(c.buildings,c.other.UserId)
  c:Check(initialUnits+initialBuildings>0,"征服階段開始時對手有真正存活物件")
  local unitsKilled,buildingsKilled,damage=0,0,0
  while workspace:GetAttribute("MatchPhase")=="Playing" do
   local targets=c:Models(c.units,c.other.UserId)
   local isBuilding=false
   if #targets==0 then targets=c:Models(c.buildings,c.other.UserId); isBuilding=true end
   if #targets==0 or c.other:GetAttribute("Defeated")==true then
    c:Wait(function()
     return workspace:GetAttribute("MatchPhase")=="Ended" and c.other:GetAttribute("Defeated")==true
      and c.other:GetAttribute("Forfeited")==false and #c:Models(c.units,c.other.UserId)==0 and #c:Models(c.buildings,c.other.UserId)==0
    end,5,"最後戰鬥死亡、自然淘汰、剩餘物件與終局欄位完成複製",true)
    break
   end
   local source=c:Position(liveArmy(c,selection)[1])
   table.sort(targets,function(a,b) return (c:Position(a)-source).Magnitude<(c:Position(b)-source).Magnitude end)
   local target=targets[1]
   damage+=attack(c,selection,target,420,true)
   if isBuilding then buildingsKilled+=1 else unitsKilled+=1 end
   if workspace:GetAttribute("MatchPhase")=="Playing" then
    c:Check(c.other:GetAttribute("Forfeited")==false,"征服戰鬥期間對手沒有投降")
   end
  end
  c:Wait(function() return #c:Models(c.units,c.other.UserId)==0 and #c:Models(c.buildings,c.other.UserId)==0 and c.other:GetAttribute("Defeated")==true end,5,"自然淘汰後敵方物件移除完成複製；再以出生與戰損總量核對",true)
  local mine,theirs=c:FinalWin("Conquest")
  local ledger
  c:Wait(function()
   mine,theirs=c:Report(c.player),c:Report(c.other)
   if not mine or not theirs then return false end
   ledger=conquestLedger(c.Config.Settings.startingVillagers,c.Config.Units.scout~=nil,c.other:GetAttribute("TrainedUnits"),mine,theirs,initialUnits,initialBuildings)
   return ledger~=nil
  end,15,"正式訓練覆盤與伺服器真實出生計數完成複製",true)
  c:Check(ledger.allUnitsDied,"起始村民／斥候＋全局真正訓練總數，全部具有雙方一致的戰鬥死亡紀錄，不能把淘汰清場當征服")
  c:Check(ledger.allCompletedBuildingsDied,"起始主城、全局真正完工建築與階段初始建築集合均有真正戰鬥損失")
  c:Check(mine.unitsKilled>=unitsKilled and mine.buildingsKilled>=buildingsKilled and theirs.unitsLost>=unitsKilled and theirs.buildingsLost>=buildingsKilled and mine.damageDealt>=damage,"正式覆盤涵蓋本階段戰鬥擊殺／損失與傷害下界")
  return {unitsKilledThisStage=unitsKilled,buildingsKilledThisStage=buildingsKilled,allUnitBirths=ledger.unitBirths,minimumBuildingBirths=ledger.minimumBuildingBirths,observedDamageLowerBound=damage}
 end)
end
function Tests.RunRegicide(options)
 return execute("NATURAL_REGICIDE","Regicide",options,function(c,o)
  local selection=army(c,o.army)
  local main
  for _,model in ipairs(c:Models(c.buildings,c.other.UserId)) do if model:GetAttribute("MainBase")==true then assert(not main,"對手有多座 MainBase，不能假設單一主城"); main=model end end
  assert(main,"需真正 MainBase")
  local lastPositiveOthers,lastPositiveSampleAt=0,0
  local function sample()
   if main.Parent~=c.buildings or (main:GetAttribute("HP") or 0)<=0 then return end
   local count=0
   for _,folder in ipairs({c.units,c.buildings}) do
    for _,model in ipairs(c:Models(folder,c.other.UserId)) do if model~=main and (model:GetAttribute("HP") or 0)>0 then count+=1 end end
   end
   lastPositiveOthers,lastPositiveSampleAt=count,os.clock()
  end
  sample(); c:Check(lastPositiveOthers>0,"主城決戰前對手仍有其他軍隊／建築")
  for _,folder in ipairs({c.units,c.buildings}) do
   table.insert(c.connections,folder.ChildAdded:Connect(sample))
   table.insert(c.connections,folder.ChildRemoved:Connect(sample))
  end
  local connection=main:GetAttributeChangedSignal("HP"):Connect(sample); table.insert(c.connections,connection)
  local damage=attack(c,selection,main,600,true); connection:Disconnect()
  c:Check(lastPositiveOthers>0,"主城正 HP／物件生命週期最後有效觀察仍有其他敵方存活物件")
  c:Wait(function() return c.other:GetAttribute("Defeated")==true end,5,"真正 MainBase 戰鬥摧毀引發自然淘汰",true)
  local mine,theirs=c:FinalWin("Regicide")
  c:Check(mine.buildingsKilled>=1 and theirs.buildingsLost>=1 and mine.damageDealt>=damage,"正式覆盤記錄主城真正戰鬥損失，不把自然淘汰清場當額外 HP")
  print("[NATURAL_REGICIDE LIMIT] 終局清場可能與最後 HP 複製合併；其他物件存活取最後實際正 HP／生命週期樣本，不能宣稱死亡瞬間狀態或看到所有零 HP。")
  return {mainBase=main,lastPositiveOtherObjects=lastPositiveOthers,lastPositiveSampleAgeSeconds=os.clock()-lastPositiveSampleAt,observedDamageLowerBound=damage}
 end)
end
function Tests.RunWonder(options)
 return execute("NATURAL_WONDER","Wonder",options,function(c,o)
  c:Check(c.player:GetAttribute("Age")==4,"正常發展至帝王時代")
  c:Check(#c:Models(c.buildings,c.player.UserId,"Wonder")==0 and #c:Models(c.buildings,c.other.UserId,"Wonder")==0,"完整倒數觀察前雙方沒有已開始計時的奇觀")
  local position=o.position or c.player:GetAttribute("HomePosition")+Vector3.new(96,0,96)
  local wonder=c:Build("Wonder",position)
  local began=os.clock(); local initial,previous,lowest,samples
  samples=0
  c:Wait(function()
   local remaining=c.player:GetAttribute("WonderRemaining")
   if type(remaining)=="number" and remaining>0 then initial,previous,lowest=remaining,remaining,remaining; return true end
   return false
  end,3,"真正完工奇觀觸發伺服器正倒數")
  local duration=c.Config.Settings.wonderVictoryTime
  c:Check(initial>=duration-1 and wonder:GetAttribute("Complete")==true and wonder:GetAttribute("HP")>0,"由正常完工開始原始完整倒數")
  c:Wait(function()
   if workspace:GetAttribute("MatchPhase")=="Ended" then return true end
   assert(wonder.Parent==c.buildings and (wonder:GetAttribute("HP") or 0)>0 and c.player:GetAttribute("Defeated")==false and c.other:GetAttribute("Defeated")==false,"倒數期間奇觀或參戰者被淘汰")
   local remaining=c.player:GetAttribute("WonderRemaining")
   assert(type(remaining)=="number" and remaining<=previous and remaining>=0,"奇觀倒數重置／缺失／增加")
   if remaining~=previous then samples+=1; lowest=math.min(lowest,remaining); previous=remaining end
   return false
  end,duration+15,"等待原始奇觀倒數自然終局",true)
  c:Check(os.clock()-began>=duration-1 and samples>=math.floor(duration/2) and lowest<=2,"真實經過完整倒數且連續觀察下降，沒有改時間")
  c:Check(c.player:GetAttribute("Defeated")==false and c.other:GetAttribute("Defeated")==false,"奇觀勝利發生於雙方尚存活時")
  c:FinalWin("Wonder")
  return {wonder=wonder,originalDuration=duration,observedRemainingSamples=samples,lowestObservedRemaining=lowest}
 end)
end
return Tests
