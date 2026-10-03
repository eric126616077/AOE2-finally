-- 僅映射於 content-validation.project.json；正式專案不會自動執行。
-- Studio SERVER 輔助（兵種升級／新兵種／狩獵／聖物／貿易／聖物勝利／電腦）：
-- 透過 GameServer 的 Studio 專用 RTSBattleProbe 直接放已完工的建築與生成單位，並提供伺服器端事實。
-- 捷徑（皆為測試前置，不驗證這些步驟本身）：把時代設為帝王、補足資源、直接放建築（含提供人口的房屋）與單位、
-- 調整電腦的時代與少量資源，並在測試期間持續移除電腦的戰鬥單位（避免電腦進攻把玩家淘汰，干擾後續驗收）。
-- 訓練、研究、採集、拾取、存放、貿易與勝利判定都走正式流程。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
local remote=Instance.new("RemoteFunction")
remote.Name="ContentStudioTest"
local function aiActor()
 return RS:WaitForChild("RTSFactions"):FindFirstChildWhichIsA("Folder")
end
local function owned(ownerId,kind,folderName)
 local result={}
 for _,model in ipairs(workspace[folderName]:GetChildren()) do
  if model:GetAttribute("OwnerId")==ownerId and (model:GetAttribute("UnitType")==kind or model:GetAttribute("BuildingType")==kind) then table.insert(result,model) end
 end
 return result
end
-- 在 center 周圍逐圈找能放下的位置（由 probe 檢查占地），minDistance 以上才採用。
local function place(ownerId,kind,center,minRadius,maxRadius,awayFrom,minAway)
 for radius=minRadius,maxRadius,8 do
  for index=0,23 do
   local angle=index*math.pi/12
   local pos=center+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
   if not awayFrom or (pos-awayFrom).Magnitude>=minAway then
    local model=probe:Invoke("build",ownerId,kind,pos)
    if model then return model end
   end
  end
 end
 return nil
end
-- 開局時聖物的對稱位置；電腦觀察結束後，把被電腦僧侶帶走又掉落的聖物放回原位（電腦僧侶被移除時聖物掉在牠腳下，
-- 常在電腦主城射程內，玩家的僧侶過去會被射死，讓「集齊全部聖物」的前提不成立）。
local relicHome={}
local function groundRelics()
 local result={}
 for _,model in ipairs(workspace.Resources:GetChildren()) do if model:GetAttribute("Relic")==true then table.insert(result,model) end end
 return result
end
local function aiHold(ai)
 -- 測試的聖物階段：電腦維持在城堡時代以前（電腦只在城堡時代以後撿聖物），且沒有僧侶。
 ai:SetAttribute("Age",1)
 ai:SetAttribute("gold",0)
 local id=ai:GetAttribute("OwnerId")
 for _,unit in ipairs(owned(id,"monk","Units")) do probe:Invoke("remove",unit) end
end
remote.OnServerInvoke=function(player,action,a,b,c)
 if not probe then return nil end
 if action=="setup" then
  player:SetAttribute("Age",4)
  for _,key in ipairs({"food","wood","gold","stone"}) do player:SetAttribute(key,(player:GetAttribute(key) or 0)+20000) end
  -- 開局只有市鎮中心的 5 人口；測試會生成與訓練十多個單位，先放 8 間房屋（+40）。
  local home=player:GetAttribute("HomePosition")
  local houses=0
  for _=1,8 do if place(player.UserId,"House",home,30,120) then houses+=1 end end
  local ai=aiActor()
  return {ai=ai and ai:GetAttribute("OwnerId"),age=player:GetAttribute("Age"),houses=houses}
 elseif action=="build" then
  -- a：建築種類、b：中心、c：{min,max,awayFrom,minAway}
  local options=type(c)=="table" and c or {}
  return place(player.UserId,a,b,options.min or 40,options.max or 160,options.awayFrom,options.minAway)
 elseif action=="spawn" then
  return probe:Invoke("spawn",player.UserId,a,b)
 elseif action=="spawnFree" then
  -- 在 b 附近找沒有建築、資源或可碰撞零件的空地再生成，避免單位卡在房屋裡。
  local params=OverlapParams.new()
  params.FilterType=Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances={workspace:FindFirstChild("AOE2_Ground"),workspace.Units}
  for radius=0,96,6 do
   for index=0,math.max(0,radius//2) do
    local angle=index*2*math.pi/math.max(1,radius//2+1)
    local pos=b+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
    local blocked=false
    for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,2.5,0)),Vector3.new(8,5,8),params)) do
     if part.CanCollide or part:IsDescendantOf(workspace.Buildings) or part:IsDescendantOf(workspace.Resources) then blocked=true; break end
    end
    if not blocked then
     local unit=probe:Invoke("spawn",player.UserId,a,pos)
     if unit then return unit end
    end
   end
  end
  return nil
 elseif action=="remove" then
  return probe:Invoke("remove",a)
 elseif action=="aiPrepare" then
  -- 電腦：城堡時代、資源充足、已完工的修道院與兩座相距足夠的市集，觀察它自己訓練與派工。
  local ai=aiActor()
  if not ai then return nil end
  local id=ai:GetAttribute("OwnerId")
  table.clear(relicHome)
  for _,relic in ipairs(groundRelics()) do table.insert(relicHome,relic:GetPivot().Position) end
  -- 帝王時代：電腦不會再為升級時代存資源（存資源時不訓練）；只給足夠訓練僧侶與貿易車的少量資源。
  ai:SetAttribute("Age",4)
  -- 測試期間電腦的軍隊會被持續移除、電腦會一直補兵，所以給足以同時補兵與訓練僧侶／貿易車的資源。
  for _,key in ipairs({"food","wood","gold"}) do ai:SetAttribute(key,(ai:GetAttribute(key) or 0)+4000) end
  local home=ai:GetAttribute("HomePosition") or Vector3.zero
  local monastery=owned(id,"Monastery","Buildings")[1] or place(id,"Monastery",home,40,200)
  local market=owned(id,"Market","Buildings")[1] or place(id,"Market",home,40,200)
  local second=market and (#owned(id,"Market","Buildings")>=2 and owned(id,"Market","Buildings")[2] or place(id,"Market",market:GetPivot().Position,180,240,market:GetPivot().Position,180))
  return {id=id,monastery=monastery~=nil,market=market~=nil,second=second~=nil}
 elseif action=="aiState" then
  local ai=aiActor()
  if not ai then return nil end
  local id=ai:GetAttribute("OwnerId")
  local result={monks=0,seeking=0,carrying=0,carts=0,trading=0,gold=ai:GetAttribute("gold"),age=ai:GetAttribute("Age"),
   population=tostring(ai:GetAttribute("Population")).."/"..tostring(ai:GetAttribute("PopulationCap")),monastery="無"}
  for _,b in ipairs(owned(id,"Monastery","Buildings")) do result.monastery=(b:GetAttribute("Complete") and "完工" or "施工中").." 訓練="..tostring(b:GetAttribute("Training")) end
  for _,unit in ipairs(workspace.Units:GetChildren()) do
   if unit:GetAttribute("OwnerId")==id then
    local kind,order=unit:GetAttribute("UnitType"),unit:GetAttribute("OrderKind")
    if kind=="monk" then
     result.monks+=1
     if order=="relic" then result.seeking+=1 end
     if unit:GetAttribute("CarryingRelic") then result.carrying+=1 end
    elseif kind=="tradeCart" then
     result.carts+=1
     if order=="trade" then result.trading+=1 end
    end
   end
  end
  return result
 elseif action=="aiStop" then
  -- 電腦觀察結束：回到黑暗時代（電腦只在城堡時代以後處理聖物與貿易），並移除牠的僧侶，攜帶的聖物會掉回地上。
  local ai=aiActor()
  if not ai then return false end
  aiHold(ai)
  task.wait(0.5)
  -- 把不在原位的聖物移回空著的原位。
  local moved=0
  for _,relic in ipairs(groundRelics()) do
   local here=relic:GetPivot().Position
   local atHome=false
   for _,spot in ipairs(relicHome) do if (spot-here).Magnitude<3 then atHome=true; break end end
   if not atHome then
    for _,spot in ipairs(relicHome) do
     local taken=false
     for _,other in ipairs(groundRelics()) do if (other:GetPivot().Position-spot).Magnitude<3 then taken=true; break end end
     if not taken then relic:PivotTo(CFrame.new(spot)); moved+=1; break end
    end
   end
  end
  return {moved=moved,home=#relicHome}
 elseif action=="aiDisarm" then
  -- 移除電腦的戰鬥單位（保留村民、僧侶與貿易車），讓電腦無法進攻玩家。a=true 時（聖物階段）另外維持電腦不撿聖物。
  local ai=aiActor()
  if not ai then return 0 end
  if a==true then aiHold(ai) end
  local id,removed=ai:GetAttribute("OwnerId"),0
  for _,unit in ipairs(workspace.Units:GetChildren()) do
   local kind=unit:GetAttribute("UnitType")
   if unit:GetAttribute("OwnerId")==id and kind~="villager" and kind~="monk" and kind~="tradeCart" then probe:Invoke("remove",unit); removed+=1 end
  end
  return removed
 elseif action=="diag" then
  local units,buildingCount=0,0
  for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("OwnerId")==player.UserId then units+=1 end end
  for _,b in ipairs(workspace.Buildings:GetChildren()) do if b:GetAttribute("OwnerId")==player.UserId then buildingCount+=1 end end
  return {units=units,buildings=buildingCount,defeated=player:GetAttribute("Defeated"),phase=workspace:GetAttribute("MatchPhase"),
   population=player:GetAttribute("Population"),cap=player:GetAttribute("PopulationCap")}
 elseif action=="tool" then
  return typeof(a)=="Instance" and a:GetAttribute("ToolKind") or nil
 end
 return nil
end
remote.Parent=RS
