-- 僅映射於 remains-validation.project.json；正式專案不會建立這個遠端，也不會執行這個腳本。
-- Studio SERVER：倒地／倒塌／資源消失動畫（f999599）的命令列驗證輔助。
--  1. 測試前置捷徑（透過 GameServer 的 Studio 專用 RTSBattleProbe）：直接放已完工的建築、生成單位、
--     把目標生命設為 1、把資源存量設為 1。擊殺與摧毀仍走正式 damage()（probe 的 attack 下令），
--     採集走客戶端的正式 Command「Order」，所以屍體與倒塌複本都由正式的 Factory.corpse／ruinBuilding／ruinResource 建立。
--  2. 伺服器端檢查：每個屍體與倒塌複本的零件都不碰撞、不可查詢；在 CorpseExpires／RuinStart+RuinSeconds+0.5 準時移除。
--  3. 在屍體與複本的零件上寫入 RemainsServerCFrame（伺服器的最終位置），客戶端以此比較本機動畫姿勢。
--     這只是測試用屬性，正式腳本不讀取。
-- 輸出以 [REMAINS SERVER] 開頭；總結由 Player1 客戶端印出 [REMAINS] COMPLETE／INCOMPLETE。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("RemainsRules"))
Config.Map.RandomizeSeed=false
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
local TAG="[REMAINS SERVER] "
local passed,failed=0,0
local function check(ok,message,detail)
 if ok then passed+=1 else failed+=1 end
 local line=TAG..(ok and "PASS " or "FAIL ")..message..(detail~=nil and ("  ("..tostring(detail)..")") or "")
 if ok then print(line) else warn(line) end
end
local function info(text) print(TAG.."INFO "..text) end

-- 伺服器端追蹤 -------------------------------------------------------------------
-- 只有 Playing 階段中被移除的才檢查時間；投降／回大廳時 Factory.clearCorpses 提早清掉的不算。
local stats={corpses=0,ruins=0,pending={}}
local victims={} -- 測試擊殺的單位：unit -> {tag,last}
local razed={}   -- 測試摧毀的建築與採完的資源：model -> {tag,ground}
local function flatDistance(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function partsOf(model)
 local list={}
 for _,part in ipairs(model:GetDescendants()) do if part:IsA("BasePart") then table.insert(list,part) end end
 return list
end
local function inert(model)
 local bad=0
 local parts=partsOf(model)
 for _,part in ipairs(parts) do
  if not part.Anchored or part.CanCollide or part.CanQuery or part.CanTouch then bad+=1 end
 end
 return #parts>0 and bad==0,#parts.." 個零件，"..bad.." 個會碰撞／查詢"
end
local function stamp(model)
 for _,part in ipairs(partsOf(model)) do part:SetAttribute("RemainsServerCFrame",part.CFrame) end
 model:SetAttribute("RemainsTagged",true)
end
local function trackCorpse(corpse)
 if not corpse:IsA("Model") or stats.pending[corpse] then return end
 stats.corpses+=1
 local base,expires=corpse:GetAttribute("CorpseBase"),corpse:GetAttribute("CorpseExpires")
 -- 對應到測試擊殺的單位（伺服器每幀記錄它們的位置）。
 if typeof(base)=="CFrame" then
  for unit,entry in pairs(victims) do
   if not entry.matched and (unit.Parent==nil or (unit:GetAttribute("HP") or 1)<=0) and entry.last
    and flatDistance(entry.last,base.Position)<5 then
    entry.matched=true
    corpse:SetAttribute("RemainsTestTag",entry.tag)
    victims[unit]=nil
    break
   end
  end
 end
 stamp(corpse)
 local ok,detail=inert(corpse)
 local label="屍體 "..tostring(corpse:GetAttribute("UnitType"))..(corpse:GetAttribute("RemainsTestTag") and ("〔"..corpse:GetAttribute("RemainsTestTag").."〕") or "")
 check(ok and typeof(base)=="CFrame" and typeof(corpse:GetAttribute("CorpseLay"))=="CFrame" and type(expires)=="number",
  label.."：有 CorpseBase／CorpseLay／CorpseExpires，零件錨定且不碰撞、不可查詢",detail)
 stats.pending[corpse]={kind="corpse",label=label,due=expires,created=workspace:GetServerTimeNow()}
end
local function trackRuin(ruin)
 if not ruin:IsA("Model") or stats.pending[ruin] then return end
 stats.ruins+=1
 local kind,start,seconds=ruin:GetAttribute("RuinKind"),ruin:GetAttribute("RuinStart"),ruin:GetAttribute("RuinSeconds")
 local ground=ruin:GetAttribute("RuinGround")
 if typeof(ground)=="Vector3" then
  local best,bestDistance=nil,6
  for model,entry in pairs(razed) do
   local d=flatDistance(entry.ground,ground)
   local gone=model.Parent==nil or (model:GetAttribute("HP") or 1)<=0 or (model:GetAttribute("Amount") or 1)<=0
   if gone and d<bestDistance then best,bestDistance=model,d end
  end
  if best then ruin:SetAttribute("RemainsTestTag",razed[best].tag); razed[best]=nil end
 end
 stamp(ruin)
 local expected=({building=Rules.CollapseSeconds,tree=Rules.TreeFallSeconds,resource=Rules.ResourceFadeSeconds})[kind]
 local ok,detail=inert(ruin)
 local label="倒塌複本 "..tostring(kind)..(ruin:GetAttribute("RemainsTestTag") and ("〔"..ruin:GetAttribute("RemainsTestTag").."〕") or "")
 check(ok and expected~=nil and seconds==expected and type(start)=="number" and typeof(ground)=="Vector3" and type(ruin:GetAttribute("RuinHeight"))=="number",
  label.."：屬性完整（RuinSeconds="..tostring(seconds).."），零件錨定且不碰撞、不可查詢",detail)
 stats.pending[ruin]={kind="ruin",label=label,due=type(start)=="number" and type(seconds)=="number" and start+seconds+.5 or nil,created=workspace:GetServerTimeNow()}
end
local function removed(model)
 local entry=stats.pending[model]
 if not entry then return end
 stats.pending[model]=nil
 local now=workspace:GetServerTimeNow()
 if workspace:GetAttribute("MatchPhase")~="Playing" then info(entry.label.." 在對局結束清場時移除"); return end
 if not entry.due then check(false,entry.label.."：缺少移除時間屬性"); return end
 local late=now-entry.due
 -- Debris 依自己的節奏檢查，允許少量延遲；不可提早。
 check(late>=-.15 and late<=.75,entry.label.."：伺服器準時移除",string.format("比預定 %+.2f 秒",late))
end
local function attach(folder)
 if not folder:IsA("Folder") then return end
 local handler=folder.Name=="Corpses" and trackCorpse or folder.Name=="Ruins" and trackRuin or nil
 if not handler then return end
 folder.ChildAdded:Connect(handler)
 folder.ChildRemoved:Connect(removed)
 for _,child in ipairs(folder:GetChildren()) do handler(child) end
end
workspace.ChildAdded:Connect(attach)
for _,child in ipairs(workspace:GetChildren()) do attach(child) end
Run.Heartbeat:Connect(function()
 for unit,entry in pairs(victims) do
  if unit.Parent and unit.PrimaryPart then entry.last=unit.PrimaryPart.Position-Vector3.new(0,2.5,0)
  elseif unit.Parent==nil and entry.matched==nil and entry.goneAt==nil then entry.goneAt=os.clock() end
  -- 沒留下屍體（例如被清場）的單位不再追蹤。
  if entry.goneAt and os.clock()-entry.goneAt>3 then victims[unit]=nil end
 end
end)

-- 前置捷徑 ---------------------------------------------------------------------
local function aiId()
 local folder=RS:FindFirstChild("RTSFactions")
 for _,actor in ipairs(folder and folder:GetChildren() or {}) do
  if actor:IsA("Folder") and actor:GetAttribute("IsAI")==true then return actor:GetAttribute("OwnerId") end
 end
 return nil
end
local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Include
local function clear(position,radius)
 local include={}
 for _,name in ipairs({"Resources","Buildings","Units"}) do
  local folder=workspace:FindFirstChild(name)
  if folder then table.insert(include,folder) end
 end
 overlap.FilterDescendantsInstances=include
 for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(position+Vector3.new(0,2.6,0)),Vector3.new(radius*2,5,radius*2),overlap)) do
  if part.CanCollide or part.Name=="Footprint" or part.Name=="CollisionVolume" then return false end
 end
 return true
end
local function inMap(position)
 local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize or 768)/2-6
 return math.abs(position.X)<=half and math.abs(position.Z)<=half
end
-- 在 center 附近找一個沒有障礙的位置生成單位（probe 本身不檢查占位）。
local function spawnNear(ownerId,kind,center,minRadius,maxRadius)
 for radius=minRadius,maxRadius,2 do
  for index=0,15 do
   local angle=index*math.pi/8
   local position=Vector3.new(center.X+math.cos(angle)*radius,0,center.Z+math.sin(angle)*radius)
   if inMap(position) and clear(position,2.6) then
    local unit=probe:Invoke("spawn",ownerId,kind,position)
    if unit then return unit end
   end
   if radius==0 then break end
  end
 end
 return nil
end
local function placeNear(ownerId,kind,center,maxRadius)
 for radius=0,maxRadius,6 do
  for index=0,(radius==0 and 0 or 15) do
   local angle=index*math.pi/8
   local position=Vector3.new(center.X+math.cos(angle)*radius,0,center.Z+math.sin(angle)*radius)
   if inMap(position) then
    local model=probe:Invoke("build",ownerId,kind,position)
    if model then return model end
   end
  end
 end
 return nil
end
local function bottom(model)
 local frame,size=model:GetBoundingBox()
 return frame.Position-Vector3.new(0,size.Y/2,0)
end
local function testUnit(unit,tag,player)
 if not unit then return nil end
 unit:SetAttribute("RemainsTestTag",tag)
 if player then unit:SetAttribute("RemainsTestOwner",player.UserId) end
 return unit
end

local built={} -- build 標籤 -> 尚未摧毀的電腦房屋
local prepared={} -- resource 標籤 -> 尚未設定存量的資源
local helper=Instance.new("RemoteFunction")
helper.Name="RemainsTestHelper"
helper.OnServerInvoke=function(player,action,a,b,c,d)
 if not probe then return nil end
 if action=="ai" then return aiId()
 elseif action=="kill" then
  -- a：位置，b：標籤。電腦村民生命設為 1，自己的弓箭手以正式攻擊命中它。
  local ai=aiId()
  if not ai or typeof(a)~="Vector3" or type(b)~="string" then return nil end
  local victim=testUnit(spawnNear(ai,"villager",a,0,24),b)
  if not victim then return nil end
  local spot=victim:GetPivot().Position
  local toward=player:GetAttribute("HomePosition")
  local away=typeof(toward)=="Vector3" and Vector3.new(toward.X-spot.X,0,toward.Z-spot.Z) or Vector3.new(1,0,0)
  away=away.Magnitude>0.1 and away.Unit or Vector3.new(1,0,0)
  local archer=testUnit(spawnNear(player.UserId,"archer",spot+away*20,0,14),b.."-attacker",player)
  if not archer then probe:Invoke("remove",victim); return nil end
  victims[victim]={tag=b,last=spot-Vector3.new(0,2.5,0)}
  victim:SetAttribute("HP",1)
  probe:Invoke("attack",archer,victim)
  return {position=Vector3.new(spot.X,0,spot.Z)}
 elseif action=="build" then
  -- a：位置，b：標籤。放一座電腦的已完工房屋（之後由 strike 摧毀）。
  local ai=aiId()
  if not ai or typeof(a)~="Vector3" or type(b)~="string" then return nil end
  local house=placeNear(ai,"House",a,c=="far" and 48 or 30)
  if not house then return nil end
  house:SetAttribute("RemainsTestTag",b)
  built[b]=house
  return {ground=bottom(house)}
 elseif action=="strike" then
  -- a：build 的標籤，b：攻擊兵種，c：攻擊者生成位置。生命設為 1，自己的單位以正式攻擊摧毀它。
  -- 以標籤在伺服器查建築，避免客戶端還沒收到新建築就把 nil 傳回來。
  local house=type(a)=="string" and built[a] or nil
  if not house or house.Parent~=workspace:FindFirstChild("Buildings") or (b~="archer" and b~="trebuchet") or typeof(c)~="Vector3" then return false end
  local attacker=testUnit(spawnNear(player.UserId,b,c,0,14),a.."-attacker",player)
  if not attacker then return false end
  built[a]=nil
  razed[house]={tag=a,ground=bottom(house)}
  house:SetAttribute("HP",1)
  return probe:Invoke("attack",attacker,house)==true
 elseif action=="resource" then
  -- a：資源名稱（Tree／Gold／Stone／Berries），b：靠近的位置，c：標籤。
  -- 找最近一個完好、附近沒有其他單位（不會被別人先採完）的資源，在旁邊生成自己的村民。
  -- 存量要等客戶端把鏡頭對準後再由 deplete 設為 1；採集由客戶端正式 Order 指令下令。
  local folder=workspace:FindFirstChild("Resources")
  if not folder or type(a)~="string" or typeof(b)~="Vector3" or type(c)~="string" then return nil end
  local candidates={}
  for _,model in ipairs(folder:GetChildren()) do
   if model.Name==a and model:GetAttribute("RTSManagedResource")==true and (model:GetAttribute("Amount") or 0)>1
    and not model:GetAttribute("Slain") and not model:GetAttribute("Herdable") and model.PrimaryPart then
    local dist=flatDistance(model:GetPivot().Position,b)
    local busy=false
    for _,unit in ipairs(workspace:FindFirstChild("Units") and workspace.Units:GetChildren() or {}) do
     if flatDistance(unit:GetPivot().Position,model:GetPivot().Position)<18 then busy=true; break end
    end
    if dist<260 and not busy then table.insert(candidates,{model=model,distance=dist}) end
   end
  end
  table.sort(candidates,function(x,y) return x.distance<y.distance end)
  for index=1,math.min(#candidates,8) do
   local model=candidates[index].model
   local size=model.PrimaryPart.Size
   local villager=testUnit(spawnNear(player.UserId,"villager",model:GetPivot().Position,math.max(size.X,size.Z)/2+3,math.max(size.X,size.Z)/2+15),c.."-villager",player)
   if villager then
    model:SetAttribute("RemainsTestTag",c)
    prepared[c]=model
    return {model=model,ground=bottom(model),villagerTag=c.."-villager"}
   end
  end
  return nil
 elseif action=="deplete" then
  -- a：resource 的標籤。存量設為 1，下一次採集就會歸零並走正式的 Factory.ruinResource。
  local model=type(a)=="string" and prepared[a] or nil
  if not model or model.Parent~=workspace:FindFirstChild("Resources") or (model:GetAttribute("Amount") or 0)<=0 then return false end
  prepared[a]=nil
  razed[model]={tag=a,ground=bottom(model)}
  model:SetAttribute("Amount",1)
  return true
 elseif action=="remove" then
  -- 只移除這個測試生成的單位（probe remove 不留屍體）。
  local removedCount=0
  local units=workspace:FindFirstChild("Units")
  for _,unit in ipairs(units and units:GetChildren() or {}) do
   if unit:GetAttribute("RemainsTestOwner")==player.UserId then probe:Invoke("remove",unit); removedCount+=1 end
  end
  return removedCount
 elseif action=="summary" then
  local now=workspace:GetServerTimeNow()
  local corpses,ruins=workspace:FindFirstChild("Corpses"),workspace:FindFirstChild("Ruins")
  local stale,pending=0,0
  for _,corpse in ipairs(corpses and corpses:GetChildren() or {}) do
   local expires=corpse:GetAttribute("CorpseExpires")
   if type(expires)~="number" or expires<now-1 then stale+=1 end
  end
  for _ in pairs(stats.pending) do pending+=1 end
  return {passed=passed,failed=failed,corpsesCreated=stats.corpses,ruinsCreated=stats.ruins,pending=pending,
   corpsesNow=corpses and #corpses:GetChildren() or 0,ruinsNow=ruins and #ruins:GetChildren() or 0,staleCorpses=stale}
 elseif action=="phase" then
  -- Player1 公布進度給其他客戶端（觀察者）；done 時一併公布伺服器至今建立的數量。
  if type(a)~="string" then return false end
  if a=="done" then
   workspace:SetAttribute("RemainsServerCorpses",stats.corpses)
   workspace:SetAttribute("RemainsServerRuins",stats.ruins)
  end
  workspace:SetAttribute("RemainsHarnessPhase",a)
  return true
 elseif action=="report" then
  -- 觀察者客戶端回報：a 通過，b 失敗，c 看到的屍體數，d 看到的複本數。
  if type(a)~="number" or type(b)~="number" or type(c)~="number" or type(d)~="number" then return false end
  workspace:SetAttribute("RemainsObserverReport",string.format("%s|%d|%d|%d|%d",player.Name,math.floor(a),math.floor(b),math.floor(c),math.floor(d)))
  return true
 end
 return nil
end
helper.Parent=RS
Players.PlayerRemoving:Connect(function(player)
 info(player.Name.." 離開")
end)
info("輔助就緒")
