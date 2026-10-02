-- Explicit independent Studio CLIENT stages; requires a normal developed two-human FFA.
-- PrepareTarget({position,retreat}) on the defending client builds an isolated House.
-- Attacker RunRange({archer,target,blacksmith,retreat}); then RunInterval({archer,target,archeryRange,retreat}).
-- Archer must not yet have Fletching / ThumbRing for the respective before/after stage.
-- No other test or manual command may run concurrently. HP replication coalescing fails strict sampling.
local Tests={running=false}
local Context=require(script.Parent.CombatStageContext)
local function execute(label,options,callback)
 assert(not Tests.running,"已有科技戰鬥階段執行中"); Tests.running=true
 options=options or {}; local context
 local ok,result=xpcall(function()
  context=Context.New(label,options.deadlineSeconds or 900)
  local detail=callback(context,options)
  return context:Finish(detail)
 end,debug.traceback)
 if context then context:Close() end
 Tests.running=false
 if not ok then error(result,0) end
 return result
end
local function fixture(c,o)
 local archer=c:Model(o.archer,c.units,c.player.UserId,"archer")
 local target=c:Model(o.target,c.buildings,c.other.UserId,"House")
 c:Check(target:GetAttribute("Complete")==true and (target:GetAttribute("HP") or 0)>180,"真實高 HP 完工房屋靶")
 c:Point(o.retreat)
 c:Check(c:EdgeDistance(target,o.retreat)>160,"正常撤退點在目標自動索敵範圍之外")
 for _,folder in ipairs({c.units,c.buildings}) do
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("RTSManaged")==true and model~=archer and model~=target then
    c:Check((c:Position(model)-c:Position(target)).Magnitude>180,"孤立房屋周圍沒有其他攻擊者、敵靶或防禦")
    if model:GetAttribute("OwnerId")==c.other.UserId then c:Check(c:EdgeDistance(model,o.retreat)>80,"弓兵撤退點避開所有其他敵方索敵目標") end
   end
  end
 end
 return archer,target
end
local function targetStamp(archer,target,c)
 local stamp,point=archer:GetAttribute("LastAttack"),archer:GetAttribute("AttackPosition")
 return type(stamp)=="number" and typeof(point)=="Vector3" and (Vector3.new(point.X,c.Config.Map.GroundY,point.Z)-c:Position(target)).Magnitude<2 and stamp or nil
end
local function shotFrom(c,archer,target,probe,retreat)
 c:Move({archer},retreat,"弓兵先正常撤到索敵範圍外")
 local before,previous=target:GetAttribute("HP"),archer:GetAttribute("LastAttack")
 local after,firstPosition
 local connection=target:GetAttributeChangedSignal("HP"):Connect(function()
  local hp=target:GetAttribute("HP")
  if not after and type(hp)=="number" and hp<before then after,firstPosition=hp,c:Position(archer) end
 end); table.insert(c.connections,connection)
 -- A normal movement command reaches the same probe point. The game's automatic
 -- acquisition then shoots there or genuinely walks closer before its first shot.
 c:Send("Order",{archer},c:Point(probe))
 c:Wait(function() return after~=nil end,(c:Position(archer)-probe).Magnitude/math.max(1,archer:GetAttribute("Speed") or 15)+60,"正常行軍／索敵產生第一擊實際 HP 差")
 c:Send("Order",{archer},retreat); connection:Disconnect()
 c:Check(math.abs(before-after-c:Damage(archer,target))<0.0001,"第一擊只有選定弓兵的正常傷害；沒有複製合併或干擾")
 c:Wait(function() local stamp=targetStamp(archer,target,c); return stamp and stamp~=previous end,3,"第一擊由真 LastAttack／AttackPosition 確認")
 local distance=c:EdgeDistance(target,firstPosition)
 c:Move({archer},retreat,"觀察後弓兵正常撤離")
 return distance,firstPosition
end
function Tests.PrepareTarget(options)
 return execute("COMBAT_TECH_FIXTURE",options,function(c,o)
  assert(typeof(o.position)=="Vector3" and typeof(o.retreat)=="Vector3","需合法工地與基地撤退點")
  local target=c:Build("House",o.position)
  c:Move(c:Models(c.units,c.player.UserId),o.retreat,"防守方全部單位正常離開測量區")
  c:Check(c:EdgeDistance(target,o.retreat)>200,"防守方撤到孤立區外")
  return {target=target,position=c:Position(target)}
 end)
end
function Tests.RunRange(options)
 return execute("COMBAT_RANGE",options,function(c,o)
  assert(c.player:GetAttribute("Tech_Fletching")~=true,"已研究箭羽，不能假裝擁有科技前樣本")
  local archer,target=fixture(c,o)
  local base=c.Config.Units.archer.range
  local center,half=c:Position(target),target.PrimaryPart.Size/2
  local probe=o.probe or center+Vector3.new(half.X+base+4,0,0)
  c:Point(probe)
  c:Check(math.abs(c:EdgeDistance(target,probe)-(base+4))<=0.25,"相同測量點位於舊射程外四 studs")
  local oldDistance=shotFrom(c,archer,target,probe,o.retreat)
  c:Check(oldDistance<=base+1,"箭羽前第一擊需要實際走近至原始射程")
  c:Research(o.blacksmith,"Fletching")
  local newDistance,newPosition=shotFrom(c,archer,target,probe,o.retreat)
  local upgraded=base+c.Config.Technologies.Fletching.effect.range
  c:Check(newDistance>base+1 and newDistance<=upgraded+1 and (newPosition-probe).Magnitude<=2,"箭羽後同一弓兵從舊射程外的同位置真正命中")
  return {baseRange=base,upgradedRange=upgraded,oldFirstShotDistance=oldDistance,newFirstShotDistance=newDistance,target=target}
 end)
end
local function median(values)
 local sorted=table.clone(values); table.sort(sorted); return sorted[math.ceil(#sorted/2)]
end
local function measure(c,archer,target,retreat)
 local damage=c:Damage(archer,target)
 c:Check((target:GetAttribute("HP") or 0)>damage*8,"房屋 HP 足夠連續觀察，不藉死亡或修復延長樣本")
 c:Move({archer},retreat,"連續射擊前正常撤離")
 local previousHP,previousStamp=target:GetAttribute("HP"),archer:GetAttribute("LastAttack")
 local stamps={}
 c:Send("Order",{archer},target)
 c:Wait(function()
  local hp,stamp=target:GetAttribute("HP"),targetStamp(archer,target,c)
  if stamp and stamp~=previousStamp and type(hp)=="number" and hp<previousHP then
   c:Check(math.abs(previousHP-hp-damage)<0.0001,"連續樣本一個 LastAttack 對應一個實際 HP 扣減")
   table.insert(stamps,stamp); previousHP,previousStamp=hp,stamp
  end
  return #stamps>=5
 end,(c:Position(archer)-c:Position(target)).Magnitude/15+90,"五個連續真攻擊時間戳與 HP 樣本")
 c:Send("Order",{archer},retreat)
 local intervals={}
 for index=2,#stamps do table.insert(intervals,stamps[index]-stamps[index-1]) end
 c:Move({archer},retreat,"連續樣本後正常撤離")
 return intervals,median(intervals)
end
function Tests.RunInterval(options)
 return execute("COMBAT_INTERVAL",options,function(c,o)
  assert(c.player:GetAttribute("Tech_ThumbRing")~=true,"已研究拇指環，不能重建科技前樣本")
  local archer,target=fixture(c,o)
  local before,oldMedian=measure(c,archer,target,o.retreat)
  c:Research(o.archeryRange,"ThumbRing")
  local after,newMedian=measure(c,archer,target,o.retreat)
  local old=c.Config.Units.archer.attackInterval
  local expected=old*(1-c.Config.Technologies.ThumbRing.effect.interval)
  for _,value in ipairs(before) do c:Check(value>=old-0.005 and value<=old+0.15,"科技前實際攻擊間隔符合原始節拍") end
  for _,value in ipairs(after) do c:Check(value>=expected-0.005 and value<=expected+0.15,"拇指環後實際間隔沒有早於冷卻且符合新節拍") end
  c:Check(newMedian<oldMedian-0.12,"同一弓兵的實際連續攻擊中位數縮短")
  print("[COMBAT_INTERVAL LIMIT] >150ms 伺服器節拍抖動或複製跳樣會嚴格 FAIL；不能據編譯聲稱速度已驗證")
  return {beforeIntervals=before,afterIntervals=after,oldMedian=oldMedian,newMedian=newMedian}
 end)
end
return Tests