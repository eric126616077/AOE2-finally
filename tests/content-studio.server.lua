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
-- 聖物階段前把地上所有聖物（包含電腦僧侶被移除時掉落的）放回正式的對稱點，並回報總數與是否都在原位。
local Config=require(RS.GameData.GameConfig)
local RelicRules=require(script.Parent:WaitForChild("ServerModules"):WaitForChild("RelicTradeRules"))
local function groundRelics()
 local result={}
 for _,model in ipairs(workspace.Resources:GetChildren()) do if model:GetAttribute("Relic")==true then table.insert(result,model) end end
 return result
end
-- 電腦觀察開始前保存一件聖物的複本，重設時用來補回被存進修道院的聖物。
local relicTemplate
local function removeAIMonks(ai)
 local removed=0
 for _,unit in ipairs(owned(ai:GetAttribute("OwnerId"),"monk","Units")) do probe:Invoke("remove",unit); removed+=1 end
 return removed
end
local function aiHold(ai)
 -- 測試的聖物階段：電腦維持在城堡時代以前（電腦只在城堡時代以後撿聖物），且沒有僧侶。
 ai:SetAttribute("Age",1)
 ai:SetAttribute("gold",0)
 removeAIMonks(ai)
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
  local sample=groundRelics()[1]
  if sample and not relicTemplate then relicTemplate=sample:Clone() end
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
  return true
 elseif action=="relicReset" then
  -- 0. 先移除電腦的所有僧侶與任何攜帶聖物的單位（玩家也算）：攜帶中的聖物只是單位上的旗標，
  --    移除時伺服器會讓它掉回地上成為實例。必須在計數前做，否則會把攜帶中的那件當成遺失而多補一件。
  local ai=aiActor()
  if ai then aiHold(ai) end
  for _,unit in ipairs(workspace.Units:GetChildren()) do
   if unit:GetAttribute("CarryingRelic")==true then probe:Invoke("remove",unit) end
  end
  -- 1. 取出所有修道院裡存放的聖物，並把各勢力的聖物件數歸零（伺服器的聖物勝利以勢力的 Relics 屬性計算）。
  local stored=0
  for _,building in ipairs(workspace.Buildings:GetChildren()) do
   if building:GetAttribute("BuildingType")=="Monastery" and (building:GetAttribute("Relics") or 0)>0 then
    stored+=building:GetAttribute("Relics"); building:SetAttribute("Relics",0)
   end
  end
  for _,actor in ipairs(game:GetService("Players"):GetPlayers()) do actor:SetAttribute("Relics",0) end
  for _,actor in ipairs(RS:WaitForChild("RTSFactions"):GetChildren()) do actor:SetAttribute("Relics",0) end
  -- 2. 補回地上不足的聖物（從保存的複本產生，屬性與伺服器產生的聖物相同）。
  local total=workspace:GetAttribute("RelicTotal") or 0
  local created=0
  while #groundRelics()<total and relicTemplate do
   relicTemplate:Clone().Parent=workspace.Resources
   created+=1
  end
  local size=workspace:GetAttribute("MapSize") or Config.Map.MapSize
  local sizeName=workspace:GetAttribute("MatchSizeName") or "Medium"
  local points=RelicRules.relicPoints(size,Config.Relics.counts[sizeName],Config.Relics.axisRadii[sizeName]) or {}
  local relics=groundRelics()
  local half=Config.Relics.size/2
  for index,relic in ipairs(relics) do
   local point=points[index]
   if point then relic:PivotTo(CFrame.new(point.X,Config.Map.GroundY+half,point.Z)) end
  end
  local atHome=0
  for _,relic in ipairs(groundRelics()) do
   local p=relic:GetPivot().Position
   for _,point in ipairs(points) do if (Vector3.new(point.X,p.Y,point.Z)-p).Magnitude<1 then atHome+=1; break end end
  end
  -- 全場的聖物實例（不限 Resources）與仍攜帶聖物的單位，用來斷言總數守恆。
  local instances,carriers=0,0
  for _,item in ipairs(workspace:GetDescendants()) do
   if item:IsA("Model") and item:GetAttribute("Relic")==true then instances+=1 end
  end
  for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("CarryingRelic")==true then carriers+=1 end end
  return {count=#relics,points=#points,atHome=atHome,stored=stored,created=created,total=total,instances=instances,carriers=carriers}
 elseif action=="aiDisarm" then
  -- 移除電腦的戰鬥單位（保留村民、僧侶與貿易車），讓電腦無法進攻玩家。
  -- a="noMonks"：已觀察到電腦派僧侶撿聖物，之後持續移除電腦僧侶（聖物掉回地上），貿易照常。
  -- a="hold"：聖物階段，電腦維持在城堡時代以前、沒有黃金與僧侶。
  local ai=aiActor()
  if not ai then return 0 end
  if a=="hold" then aiHold(ai) elseif a=="noMonks" then removeAIMonks(ai) end
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
 elseif action=="near" then
  -- 診斷：a 周圍 10 studs 內的單位（種類、指令、是否己方）。
  if typeof(a)~="Instance" or not a.Parent then return "" end
  local here,list=a:GetPivot().Position,{}
  for _,unit in ipairs(workspace.Units:GetChildren()) do
   if unit~=a and (unit:GetPivot().Position-here).Magnitude<=10 then
    table.insert(list,tostring(unit:GetAttribute("UnitType")).."/"..tostring(unit:GetAttribute("OrderKind")).."/"..(unit:GetAttribute("OwnerId")==a:GetAttribute("OwnerId") and "己方" or "他方"))
   end
  end
  return table.concat(list,"、")
 elseif action=="tool" then
  return typeof(a)=="Instance" and a:GetAttribute("ToolKind") or nil
 end
 return nil
end
remote.Parent=RS
