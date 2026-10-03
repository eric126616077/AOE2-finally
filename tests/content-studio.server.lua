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
 elseif action=="remove" then
  return probe:Invoke("remove",a)
 elseif action=="aiPrepare" then
  -- 電腦：城堡時代、資源充足、已完工的修道院與兩座相距足夠的市集，觀察它自己訓練與派工。
  local ai=aiActor()
  if not ai then return nil end
  local id=ai:GetAttribute("OwnerId")
  -- 帝王時代：電腦不會再為升級時代存資源（存資源時不訓練）；只給足夠訓練僧侶與貿易車的少量資源。
  ai:SetAttribute("Age",4)
  for _,key in ipairs({"food","wood","gold","stone"}) do ai:SetAttribute(key,(ai:GetAttribute(key) or 0)+800) end
  local home=ai:GetAttribute("HomePosition") or Vector3.zero
  local monastery=owned(id,"Monastery","Buildings")[1] or place(id,"Monastery",home,40,200)
  local market=owned(id,"Market","Buildings")[1] or place(id,"Market",home,40,200)
  local second=market and (#owned(id,"Market","Buildings")>=2 and owned(id,"Market","Buildings")[2] or place(id,"Market",market:GetPivot().Position,180,240,market:GetPivot().Position,180))
  return {id=id,monastery=monastery~=nil,market=market~=nil,second=second~=nil}
 elseif action=="aiState" then
  local ai=aiActor()
  if not ai then return nil end
  local id=ai:GetAttribute("OwnerId")
  local result={monks=0,seeking=0,carrying=0,carts=0,trading=0}
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
  local id=ai:GetAttribute("OwnerId")
  ai:SetAttribute("Age",1)
  ai:SetAttribute("gold",0)
  for _,unit in ipairs(owned(id,"monk","Units")) do probe:Invoke("remove",unit) end
  return true
 elseif action=="aiDisarm" then
  -- 移除電腦的戰鬥單位（保留村民、僧侶與貿易車），讓電腦無法進攻玩家。
  local ai=aiActor()
  if not ai then return 0 end
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
