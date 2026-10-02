-- 僅映射於 combat-feel-validation.project.json；正式專案不會自動執行。
-- Studio SERVER：用 GameServer 的 Studio 專用 RTSBattleProbe 生成小規模部隊，讓正式戰鬥邏輯自行交戰，
-- 記錄「飛抵／揮到才扣血」的實際延遲、近戰出手距離、石彈落點與屍體存在秒數。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local function round(value,digits)
 if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false end
 local scale=10^(digits or 2)
 return math.floor(value*scale+0.5)/scale
end
local function emit(kind,data)
 print("[COMBAT_FEEL] "..Http:JSONEncode({kind=kind,data=data}))
end
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
if not probe then emit("ABORT",{reason="RTSBattleProbe missing"}); return end
repeat task.wait(0.5) until workspace:GetAttribute("MatchPhase")=="Playing" and (workspace:GetAttribute("FactionCount") or 0)>=2
task.wait(4)
local player=Players:GetPlayers()[1]
local aiActor=RS:WaitForChild("RTSFactions"):FindFirstChildWhichIsA("Folder")
if not player or not aiActor then emit("ABORT",{reason="need one human and one AI faction"}); return end
local humanId,aiId=player.UserId,aiActor:GetAttribute("OwnerId")
local home=player:GetAttribute("HomePosition")
local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Exclude
do
 local ground=workspace:FindFirstChild("AOE2_Ground")
 overlap.FilterDescendantsInstances=ground and {ground} or {}
end
local function blockers(center,size)
 local count=0
 for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(center),size,overlap)) do if part.CanCollide then count+=1 end end
 return count
end
local inward=Vector3.new(home.X>0 and -1 or 1,0,home.Z>0 and -1 or 1)
local center,best=nil,math.huge
for _,distance in ipairs({70,85,100,120,145,175}) do
 local candidate=home+inward*distance
 if math.abs(candidate.X)<half-80 and math.abs(candidate.Z)<half-80 then
  local count=blockers(candidate+Vector3.new(0,4,0),Vector3.new(150,8,60))
  if count<best then center,best=candidate,count end
 end
end
if not center then emit("ABORT",{reason="no battlefield"}); return end
workspace:SetAttribute("CombatFeelCenter",center)
emit("FIELD",{center={round(center.X),round(center.Z)},obstacles=best})

local function flat(model) local p=model:GetPivot().Position; return Vector3.new(p.X,0,p.Z) end
local spawned={}
local function spawn(id,kind,offset)
 local unit=probe:Invoke("spawn",id,kind,center+offset)
 if unit then table.insert(spawned,unit) end
 return unit
end
local function cleanup()
 for _,unit in ipairs(spawned) do if unit.Parent then probe:Invoke("remove",unit) end end
 table.clear(spawned)
end
-- 每次出手記錄伺服器宣告的 AttackFlight 與出手瞬間到目標中心的距離；目標每次扣血記錄距最近一次出手的秒數。
local function watch(attacker,target,record)
 local connections={}
 local lastShot
 table.insert(connections,attacker:GetAttributeChangedSignal("LastAttack"):Connect(function()
  lastShot=os.clock()
  local flight,point,contact=attacker:GetAttribute("AttackFlight"),attacker:GetAttribute("AttackPosition"),attacker:GetAttribute("AttackContact")
  table.insert(record.shots,{flight=round(flight,3),centerDistance=typeof(point)=="Vector3" and round((Vector3.new(point.X,0,point.Z)-flat(attacker)).Magnitude,2),
   contactDistance=typeof(contact)=="Vector3" and round((Vector3.new(contact.X,0,contact.Z)-flat(attacker)).Magnitude,2) or false})
 end))
 if target then
  local hp=target:GetAttribute("HP")
  table.insert(connections,target:GetAttributeChangedSignal("HP"):Connect(function()
   local value=target:GetAttribute("HP")
   if type(value)=="number" and type(hp)=="number" and value<hp and lastShot then
    table.insert(record.hits,{delay=round(os.clock()-lastShot,3),damage=round(hp-value,2)})
   end
   hp=value
  end))
 end
 return connections
end
local function duel(name,attackerKind,targetKind,gap,seconds,walkAway)
 workspace:SetAttribute("CombatFeelStage",name)
 local attacker=spawn(humanId,attackerKind,Vector3.new(-gap/2,0,0))
 local target=spawn(aiId,targetKind,Vector3.new(gap/2,0,0))
 if not attacker or not target then emit("SKIP",{name=name}); cleanup(); return end
 local record={shots={},hits={}}
 local connections=watch(attacker,target,record)
 probe:Invoke("attack",attacker,target)
 if walkAway then
  -- 石彈出手後目標走開：落點半徑外不應扣血。
  task.spawn(function()
   local stamp=attacker:GetAttribute("LastAttack")
   local deadline=os.clock()+seconds
   repeat task.wait() until attacker:GetAttribute("LastAttack")~=stamp or os.clock()>deadline
   record.targetAtShot=round((flat(target)-center).X,2)
  end)
 end
 task.wait(seconds)
 for _,connection in ipairs(connections) do connection:Disconnect() end
 record.name,record.attacker,record.target=name,attackerKind,targetKind
 record.range=attacker.Parent and attacker:GetAttribute("Range") or false
 record.targetHP=target.Parent and target:GetAttribute("HP") or 0
 emit("DUEL",record)
 cleanup()
 task.wait(1)
end

duel("duel-archer",  "archer",   "ram",40,10)
duel("duel-skirm",   "skirmisher","ram",34,10)
duel("duel-mangonel","mangonel", "ram",55,11)
duel("duel-infantry","infantry", "ram",20,10)
duel("duel-spearman","spearman", "ram",20,10)
duel("duel-cavalry", "cavalry",  "ram",24,10)
duel("duel-villager","villager", "ram",20,10)

-- 混戰：近戰對近戰加雙方弓兵，觀察屍體、血條、箭矢與踏步；記錄每具屍體實際存在秒數。
workspace:SetAttribute("CombatFeelStage","brawl")
local corpseLife,corpseSeen,corpseKinds={},0,{}
local corpseFolder
local function watchCorpses(folder)
 corpseFolder=folder
 folder.ChildAdded:Connect(function(corpse)
  corpseSeen+=1
  local born=os.clock()
  local kind=corpse:GetAttribute("UnitType") or "?"
  corpseKinds[kind]=(corpseKinds[kind] or 0)+1
  local parts,queryable,collidable=0,0,0
  for _,part in ipairs(corpse:GetDescendants()) do
   if part:IsA("BasePart") then
    parts+=1
    if part.CanQuery then queryable+=1 end
    if part.CanCollide then collidable+=1 end
   end
  end
  if corpseSeen<=3 then emit("CORPSE",{kind=kind,parts=parts,queryable=queryable,collidable=collidable}) end
  corpse.AncestryChanged:Connect(function() if not corpse.Parent then table.insert(corpseLife,round(os.clock()-born,2)) end end)
 end)
end
if workspace:FindFirstChild("Corpses") then watchCorpses(workspace.Corpses)
else
 local connection
 connection=workspace.ChildAdded:Connect(function(child) if child.Name=="Corpses" then connection:Disconnect(); watchCorpses(child) end end)
end
local humans,enemies={},{}
local lineup={"infantry","infantry","spearman","cavalry","infantry","villager"}
for index,kind in ipairs(lineup) do
 local z=(index-(#lineup+1)/2)*7
 table.insert(humans,spawn(humanId,kind,Vector3.new(-12,0,z)))
 table.insert(enemies,spawn(aiId,kind,Vector3.new(12,0,z)))
end
for index=1,3 do
 local z=(index-2)*7
 table.insert(humans,spawn(humanId,"archer",Vector3.new(-34,0,z)))
 table.insert(enemies,spawn(aiId,"archer",Vector3.new(34,0,z)))
end
local kills=0
for _,list in ipairs({humans,enemies}) do
 for _,unit in ipairs(list) do unit.AncestryChanged:Connect(function() if not unit.Parent then kills+=1 end end) end
end
for index,unit in ipairs(humans) do probe:Invoke("attack",unit,enemies[(index-1)%#enemies+1]) end
for index,unit in ipairs(enemies) do probe:Invoke("attack",unit,humans[(index-1)%#humans+1]) end
local deadline=os.clock()+45
repeat task.wait(1) until os.clock()>deadline or kills>=#humans+#enemies-1
emit("BRAWL",{kills=kills,corpsesSeen=corpseSeen,corpsesNow=corpseFolder and #corpseFolder:GetChildren() or 0,corpseKinds=corpseKinds,seconds=round(45-(deadline-os.clock()),1)})
workspace:SetAttribute("CombatFeelStage","corpses")
-- 存活者留在原地；等最後一具屍體過期。
task.wait(Config.Combat.corpseSeconds+3)
table.sort(corpseLife)
emit("CORPSE_LIFE",{count=#corpseLife,min=corpseLife[1] or false,max=corpseLife[#corpseLife] or false,
 remaining=corpseFolder and #corpseFolder:GetChildren() or 0,configured=Config.Combat.corpseSeconds})
cleanup()
workspace:SetAttribute("CombatFeelStage","done")
emit("DONE",{phase=workspace:GetAttribute("MatchPhase")})
