-- 僅映射於 aoe2-elements-validation.project.json；正式專案不會自動執行。
-- Studio SERVER 輔助（戰爭迷霧、羊群、野豬、市集浮動價格、進貢、姿態、城鎮警鐘、新科技與新兵種）：
-- 透過 GameServer 的 Studio 專用 RTSBattleProbe 直接放已完工的建築與生成單位，並回報伺服器端事實。
-- 捷徑只用於測試前置（時代、資源、直接放建築與單位）；宰殺、圍獵、接收羊群、交易、進貢、姿態、警鐘與研究都走正式指令。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
local remote=Instance.new("RemoteFunction")
remote.Name="AOE2ElementsTest"
local function aiActor() return RS:WaitForChild("RTSFactions"):FindFirstChildWhichIsA("Folder") end
local function place(ownerId,kind,center,minRadius,maxRadius)
 for radius=minRadius,maxRadius,8 do
  for index=0,23 do
   local angle=index*math.pi/12
   local model=probe:Invoke("build",ownerId,kind,center+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
   if model then return model end
  end
 end
 return nil
end
-- 在 center 附近找一個能生成單位的位置。
local function spawnNear(ownerId,kind,center,minRadius)
 for radius=minRadius or 6,minRadius+30,3 do
  for index=0,11 do
   local angle=index*math.pi/6
   local unit=probe:Invoke("spawn",ownerId,kind,center+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius))
   if unit then return unit end
  end
 end
 return nil
end
remote.OnServerInvoke=function(player,action,a,b,c)
 if not probe then return nil end
 if action=="setup" then
  player:SetAttribute("Age",4)
  for _,key in ipairs({"food","wood","gold","stone"}) do player:SetAttribute(key,(player:GetAttribute(key) or 0)+20000) end
  local home=player:GetAttribute("HomePosition")
  local houses=0
  for _=1,8 do if place(player.UserId,"House",home,50,140) then houses+=1 end end
  local ai=aiActor()
  return {ai=ai and ai:GetAttribute("OwnerId"),houses=houses}
 elseif action=="build" then
  return place(player.UserId,a,b,c or 50,(c or 50)+120)
 elseif action=="spawn" then
  return spawnNear(type(c)=="number" and c or player.UserId,a,b,6)
 elseif action=="remove" then
  return probe:Invoke("remove",a)
 elseif action=="aiDisarm" then
  local ai=aiActor()
  if not ai then return 0 end
  local id,removed=ai:GetAttribute("OwnerId"),0
  for _,unit in ipairs(workspace.Units:GetChildren()) do
   local kind=unit:GetAttribute("UnitType")
   if unit:GetAttribute("OwnerId")==id and kind~="villager" and kind~="sheep" and not unit:GetAttribute("KeepForTest") then probe:Invoke("remove",unit); removed+=1 end
  end
  return removed
 elseif action=="keep" then
  if typeof(a)=="Instance" then a:SetAttribute("KeepForTest",true) end
  return true
 elseif action=="garrison" then
  local total=0
  for _,model in ipairs(workspace.Buildings:GetChildren()) do if model:GetAttribute("OwnerId")==player.UserId then total+=model:GetAttribute("Garrison") or 0 end end
  return total
 elseif action=="diag" then
  return {phase=workspace:GetAttribute("MatchPhase"),defeated=player:GetAttribute("Defeated"),population=player:GetAttribute("Population")}
 end
 return nil
end
remote.Parent=RS
