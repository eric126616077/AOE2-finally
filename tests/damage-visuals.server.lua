-- 僅映射於 damage-visuals-validation.project.json；正式專案不會建立這個遠端。
-- Studio SERVER：替客戶端測試腳本直接放已完工建築、設定建築生命與農田存量、生成敵軍並下令攻擊。
-- 受損外觀本身完全由正式的 BuildingVisuals.client.lua 依複製過來的 HP／MaxHP 屬性決定。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
Config.Map.RandomizeSeed=false
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
local helper=Instance.new("RemoteFunction")
helper.Name="DamageTestHelper"
local function aiId()
 local actor=RS:WaitForChild("RTSFactions"):FindFirstChildWhichIsA("Folder")
 return actor and actor:GetAttribute("OwnerId")
end
helper.OnServerInvoke=function(player,action,a,b,c)
 if not probe then return false end
 if action=="build" then
  -- a：建築種類，b：希望的位置，c：標籤。在附近找沒有障礙的占地，直接放已完工的建築。
  if typeof(b)~="Vector3" then return false end
  for ring=0,8 do
   for step=0,ring==0 and 0 or 7 do
    local angle=step*math.pi/4
    local model=probe:Invoke("build",player.UserId,a,b+Vector3.new(math.cos(angle)*ring*16,0,math.sin(angle)*ring*16))
    if model then model:SetAttribute("TestTag",c); return true end
   end
  end
  return false
 elseif action=="setHP" then
  if typeof(a)~="Instance" or a.Parent~=workspace:FindFirstChild("Buildings") or type(b)~="number" then return false end
  a:SetAttribute("HP",b)
  return true
 elseif action=="setAmount" then
  if typeof(a)~="Instance" or a.Parent~=workspace:FindFirstChild("Buildings") or type(b)~="number" then return false end
  a:SetAttribute("Amount",b)
  return true
 elseif action=="spawnEnemy" then
  -- a：兵種，b：位置，c：標籤。
  local id=aiId()
  local unit=id and typeof(b)=="Vector3" and probe:Invoke("spawn",id,a,b)
  if not unit then return false end
  unit:SetAttribute("TestTag",c)
  return true
 elseif action=="attack" then
  return probe:Invoke("attack",a,b)==true
 end
 return false
end
helper.Parent=RS
