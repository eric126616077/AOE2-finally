-- Two independent explicit Studio CLIENT roles, using normal attacks/build/research only.
-- Owner first PrepareTarget({position,retreat}), then RunOwner({target,enemyTrebuchet}).
-- Attacker RunAttacker({target,trebuchet,standOff?}) concurrently with RunOwner.
-- Default Fletching must remain unresearched on OWNER. This checks real combat destruction,
-- cancellation and a normal replacement's same-key research, not an external Destroy() test.
local Tests={running=false}
local Context=require(script.Parent.CombatStageContext)
local function execute(label,options,callback)
 assert(not Tests.running,"已有研究戰鬥階段執行中"); Tests.running=true
 options=options or {}; local context
 local ok,result=xpcall(function()
  context=Context.New(label,options.deadlineSeconds or 1200)
  return context:Finish(callback(context,options))
 end,debug.traceback)
 if context then context:Close() end
 Tests.running=false; if not ok then error(result,0) end; return result
end
local function facts(c,target,attacker,key,ownerId,attackerId)
 local data=assert(c.Config.Technologies[key],"未知科技")
 c:Model(target,c.buildings,ownerId,data.building)
 c:Model(attacker,c.units,attackerId,"trebuchet")
 c:Check(target:GetAttribute("Complete")==true and target:GetAttribute("Research")==nil and (target:GetAttribute("QueueCount") or 0)==0,"真實空佇列研究建築")
 local owner=ownerId==c.player.UserId and c.player or c.other
 c:Check(owner:GetAttribute("Tech_"..key)~=true,"屋主尚未研究此科技")
 local hit=c:Damage(attacker,target)
 return data,hit
end
function Tests.PrepareTarget(options)
 return execute("RESEARCH_ATTACK_FIXTURE",options,function(c,o)
  local key=o.key or "Fletching"; local data=assert(c.Config.Technologies[key],"未知科技")
  local target=c:Build(data.building,o.position)
  c:Move(c:Models(c.units,c.player.UserId),o.retreat,"屋主全軍正常撤離研究測試建築")
  c:Check(c:EdgeDistance(target,o.retreat)>220,"屋主單位撤到削血與研究區外")
  return {target=target,key=key,position=c:Position(target)}
 end)
end
function Tests.RunAttacker(options)
 return execute("RESEARCH_ATTACK_DESTROY",options,function(c,o)
  local key=o.key or "Fletching"; local target,attacker=o.target,o.trebuchet
  local data,hit=facts(c,target,attacker,key,c.other.UserId,c.player.UserId)
  local center,half=c:Position(target),target.PrimaryPart.Size/2
  local range=c.Config.Units.trebuchet.range
  local standOff=o.standOff or center+Vector3.new(half.X+math.max(72,range)+16,0,0)
  c:Point(standOff)
  c:Check(c:EdgeDistance(target,standOff)>math.max(72,range)+8,"撤退點在巨投實際射程與自動索敵之外")
  for _,folder in ipairs({c.units,c.buildings}) do
   for _,model in ipairs(folder:GetChildren()) do
    if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("RTSManaged")==true and model~=target and model~=attacker then
     c:Check((c:Position(model)-center).Magnitude>180,"研究工地附近沒有額外攻擊者或防禦")
     if model:GetAttribute("OwnerId")==c.other.UserId then c:Check(c:EdgeDistance(model,standOff)>math.max(72,range)+8,"巨投撤退點也避開其他敵方自動索敵目標") end
    end
   end
  end
  c:Check((target:GetAttribute("HP") or 0)>hit*2,"從真實高 HP 建築開始削血")
  local previousHP=target:GetAttribute("HP"); local observedDamage=0
  local connection=target:GetAttributeChangedSignal("HP"):Connect(function()
   local hp=target:GetAttribute("HP")
   if type(previousHP)=="number" and type(hp)=="number" and hp<previousHP then observedDamage+=previousHP-hp end
   previousHP=hp
  end); table.insert(c.connections,connection)
  c:Send("Order",{attacker},target)
  c:Wait(function() local hp=target:GetAttribute("HP"); return target.Parent==c.buildings and type(hp)=="number" and hp>0 and hp<=hit*2 end,240,"正常巨投攻擊把研究建築降至一至兩擊 HP")
  c:Send("Order",{attacker},standOff)
  c:Move({attacker},standOff,"巨投正常撤離且停止自動索敵")
  local researchStarted
  c:Wait(function()
   local remaining=target:GetAttribute("ResearchRemaining")
   if target:GetAttribute("Research")==data.name and type(remaining)=="number" and remaining>0 then researchStarted=os.clock(); return true end
   return false
  end,300,"屋主透過正常 Research 開始未完成科技")
  local previousResearchAttack=attacker:GetAttribute("LastAttack")
  c:Send("Order",{attacker},target)
  c:Wait(function() return target.Parent~=c.buildings end,data.time-1,"研究仍進行時由真實巨投攻擊摧毀")
  local deathSeconds=os.clock()-researchStarted
  local lastAttack,impact=attacker:GetAttribute("LastAttack"),attacker:GetAttribute("AttackPosition")
  c:Check(type(lastAttack)=="number" and type(previousResearchAttack)=="number" and lastAttack>previousResearchAttack and typeof(impact)=="Vector3" and (Vector3.new(impact.X,c.Config.Map.GroundY,impact.Z)-center).Magnitude<2,"建築死亡具有真正巨投 LastAttack／AttackPosition")
  c:Check(observedDamage>0 and c.other:GetAttribute("Tech_"..key)~=true and c.other:GetAttribute("Defeated")==false and workspace:GetAttribute("MatchPhase")=="Playing","研究科技未生效，摧毀並非投降／終局清場")
  c:Send("Order",{attacker},standOff); c:Move({attacker},standOff,"戰鬥摧毀後巨投正常撤離替代工地")
  c:Wait(function() return c.other:GetAttribute("Tech_"..key)==true end,600,"屋主在正常重建後真正重新完成同一科技")
  print("[RESEARCH_ATTACK LIMIT] HP ledger 是已複製扣減下界，不能重建未觀察到的最後零 HP。")
  return {key=key,observedDamageLowerBound=observedDamage,deathDuringResearchSeconds=deathSeconds,combatBuildingDeaths=1}
 end)
end
function Tests.RunOwner(options)
 return execute("RESEARCH_ATTACK_CANCEL_RERUN",options,function(c,o)
  local key=o.key or "Fletching"; local target,attacker=o.target,o.enemyTrebuchet
  local data,hit=facts(c,target,attacker,key,c.player.UserId,c.other.UserId)
  local center,half=c:Position(target),target.PrimaryPart.Size/2
  -- The destroyed Model has no PrimaryPart; retain only its read-only footprint.
  local function distanceFromFormerFootprint(point)
   local dx=math.max(0,math.abs(point.X-center.X)-half.X)
   local dz=math.max(0,math.abs(point.Z-center.Z)-half.Z)
   return math.sqrt(dx*dx+dz*dz)
  end
  c:Wait(function()
   local hp=target:GetAttribute("HP")
   return target.Parent==c.buildings and type(hp)=="number" and hp>0 and hp<=hit*2
    and attacker:GetAttribute("Order")=="待命" and distanceFromFormerFootprint(c:Position(attacker))>math.max(72,c.Config.Units.trebuchet.range)+8
  end,300,"敵巨投以正常攻擊削血後真正撤離")
  local began=c:BeginResearch(target,key)
  local latestPositive=target:GetAttribute("ResearchRemaining")
  local connection=target:GetAttributeChangedSignal("ResearchRemaining"):Connect(function()
   local value=target:GetAttribute("ResearchRemaining")
   if type(value)=="number" and value>0 then latestPositive=value end
  end); table.insert(c.connections,connection)
  c:Wait(function() return target.Parent~=c.buildings end,data.time-1,"科技未完成前研究建築被真正敵軍摧毀")
  c:Check(type(latestPositive)=="number" and latestPositive>0 and os.clock()-began<data.time and c.player:GetAttribute("Tech_"..key)~=true,"死亡發生於原始研究計時內且沒有科技效果")
  c:Check(c.player:GetAttribute("Defeated")==false and c.player:GetAttribute("Forfeited")==false and c.other:GetAttribute("Forfeited")==false,"雙方仍正常參戰，沒有清場或投降")
  c:Wait(function() return os.clock()-began>=data.time+1 end,data.time+3,"等待原始研究應完成時間，觀察真正取消")
  c:Check(c.player:GetAttribute("Tech_"..key)~=true,"被摧毀研究沒有延遲套用科技")
  c:Wait(function() return attacker.Parent==c.units and attacker:GetAttribute("Order")=="待命" and distanceFromFormerFootprint(c:Position(attacker))>math.max(72,c.Config.Units.trebuchet.range)+8 end,30,"敵軍正常撤離，替代工地不受自動攻擊")
  local replacement=c:Build(data.building,center)
  c:Check(replacement~=target and replacement:GetAttribute("HP")>0,"正常成本與施工建立新的研究建築")
  c:Research(replacement,key)
  c:Check(c.player:GetAttribute("Tech_"..key)==true,"同一科技重新扣款、正常計時並完成，pending 不再卡住")
  return {key=key,replacement=replacement,cancelled=true,researchPayments=2,latestPositiveRemaining=latestPositive}
 end)
end
return Tests