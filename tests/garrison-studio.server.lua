-- 僅映射於 garrison-validation.project.json；正式專案不會建立這個遠端。
-- Studio SERVER：提供客戶端測試腳本需要、但正常指令做不到的準備動作（直接生成指定兵種、設定生命、移除單位）。
-- 駐紮、離開與拆除本身都由客戶端經正式的 Command 遠端下令，走伺服器的正常驗證流程。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
Config.Map.RandomizeSeed=false
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
local helper=Instance.new("RemoteFunction")
helper.Name="GarrisonTestHelper"
local function aiId()
 local actor=RS:WaitForChild("RTSFactions"):FindFirstChildWhichIsA("Folder")
 return actor and actor:GetAttribute("OwnerId")
end
helper.OnServerInvoke=function(player,action,a,b,c,d)
 if not probe then return false end
 if action=="spawn" then
  -- a：human／ai，b：兵種，c：位置，d：標籤（客戶端用屬性找到複製過來的模型）。
  local id=a=="ai" and aiId() or player.UserId
  -- probe 不檢查占位：指定位置若壓在樹木、礦或建築的碰撞體上，單位會一步也走不動。
  -- 這裡先查障礙，被擋住就往四周找最近的空位，並把原本擋住的物件名稱記在屬性上供紀錄。
  local data=Config.Units[b]
  if not id or not data or typeof(c)~="Vector3" then return false end
  local profile=Config.UnitCollision.profiles[data.class] or Config.UnitCollision.default
  local params=OverlapParams.new()
  params.FilterType=Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances={workspace:FindFirstChild("AOE2_Ground"),workspace:FindFirstChild("Units")}
  local function blockers(pos)
   local names={}
   for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,profile.height/2+0.2,0)),
    Vector3.new(profile.radius*2+1,profile.height,profile.radius*2+1),params)) do
    if part.CanCollide then table.insert(names,part:GetFullName()) end
   end
   return names
  end
  local blocked=blockers(c)
  local position=c
  if #blocked>0 then
   position=nil
   for ring=1,4 do
    for step=0,7 do
     local candidate=c+Vector3.new(math.cos(step*math.pi/4)*ring*6,0,math.sin(step*math.pi/4)*ring*6)
     if #blockers(candidate)==0 then position=candidate; break end
    end
    if position then break end
   end
   if not position then return false end
  end
  local unit=probe:Invoke("spawn",id,b,position)
  if not unit then return false end
  if #blocked>0 then unit:SetAttribute("TestSpawnBlockedBy",table.concat(blocked,", ",1,math.min(3,#blocked))) end
  unit:SetAttribute("TestTag",d)
  return true
 elseif action=="setHP" then
  if typeof(a)~="Instance" or a.Parent~=workspace.Units or type(b)~="number" then return false end
  a:SetAttribute("HP",b)
  return true
 elseif action=="remove" then
  return probe:Invoke("remove",a)==true
 elseif action=="build" then
  -- a：建築種類，b：希望的位置，c：標籤。在附近找一塊沒有障礙的占地，直接放已完工的建築。
  if typeof(b)~="Vector3" then return false end
  for ring=0,8 do
   for step=0,ring==0 and 0 or 7 do
    local angle=step*math.pi/4
    local model=probe:Invoke("build",player.UserId,a,b+Vector3.new(math.cos(angle)*ring*24,0,math.sin(angle)*ring*24))
    if model then model:SetAttribute("TestTag",c); return true end
   end
  end
  return false
 elseif action=="buildEnemy" then
  -- a：建築種類，b：位置（只試這一格），c：標籤。放一座電腦陣營的已完工建築。
  local id=aiId()
  local model=id and typeof(b)=="Vector3" and probe:Invoke("build",id,a,b)
  if not model then return false end
  model:SetAttribute("TestTag",c)
  return true
 elseif action=="attack" then
  return probe:Invoke("attack",a,b)==true
 end
 return false
end
helper.Parent=RS
