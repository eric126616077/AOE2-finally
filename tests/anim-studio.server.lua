-- 僅映射於 anim-validation.project.json；正式專案不會建立這個遠端，也不會執行這個腳本。
-- Studio SERVER：新單位出場、箭落地與特效池（d116b10）的命令列驗證輔助。
--  1. 伺服器端檢查：每個真人玩家的新單位（訓練完成、離開駐軍）一出現就檢查 Factory.markSpawn 寫入的
--     SpawnFrom／SpawnAt：SpawnFrom 在「建築中心→出生點」的連線上、在占地內，往外 1 stud 正好到占地邊緣
--     （以占地零件的 CFrame 與 Size 計算，旋轉也成立），高度等於 Root，SpawnAt 是剛剛的伺服器時間。
--     並記錄每種建築命中的是占地的 X 面或 Z 面，供客戶端確認非正方形建築的長短邊都測到。
--  2. 測試前置捷徑（透過 GameServer 的 Studio 專用 RTSBattleProbe）：放已完工的房屋與馬廄（人口與非正方形占地）、
--     生成弓箭手與電腦單位、下攻擊命令。訓練、集結點、駐紮與離開駐軍都由客戶端的正式 Command 下令，
--     所以 SpawnFrom 一律來自正式的 productionStep／Garrison.eject。
--  3. 為了縮短等待，本腳本把伺服器 GameConfig 的斥候騎兵 trainTime 改為 3 秒（只在這個驗證專案；
--     與其他驗證腳本把 Config.Map.RandomizeSeed 設為 false 相同的做法）。村民維持正式的訓練時間。
-- 輸出以 [ANIM SERVER] 開頭；總結由 Player1 客戶端印出 [ANIM] COMPLETE／INCOMPLETE。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
Config.Map.RandomizeSeed=false
local SCOUT_TRAIN_TIME=3
Config.Units.scout.trainTime=SCOUT_TRAIN_TIME
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
local TAG="[ANIM SERVER] "
local passed,failed=0,0
local function check(ok,message,detail)
 if ok then passed+=1 else failed+=1 end
 local line=TAG..(ok and "PASS " or "FAIL ")..message..(detail~=nil and ("  ("..tostring(detail)..")") or "")
 if ok then print(line) else warn(line) end
 return ok
end
local function info(text) print(TAG.."INFO "..text) end
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function flatDistance(a,b) return (flat(a)-flat(b)).Magnitude end

-- 可旋轉的建築不訓練、不駐軍：出場只會發生在 Factory.model 建立的軸對齊占地上。
do
 local offenders={}
 for kind,data in pairs(Config.Buildings) do
  local trains=type(data.trains)=="table" and #data.trains>0
  if data.rotatable==true and (trains or data.garrison~=nil) then table.insert(offenders,kind) end
 end
 check(#offenders==0,"可旋轉的建築（城門）不訓練、不駐軍，新單位只會從軸對齊占地走出",#offenders>0 and table.concat(offenders,",") or nil)
end

-- 新單位的 SpawnFrom 稽核 ---------------------------------------------------------------
local audit={human=0,ai=0,noBuilding=0,faces={},byOwner={}}
local function ownerOf(unit)
 local id=unit:GetAttribute("OwnerId")
 return type(id)=="number" and Players:GetPlayerByUserId(id) or nil
end
-- SpawnFrom 所在的建築：同一擁有者、占地（含旋轉）在 XZ 平面包含 SpawnFrom。
local function sourceBuilding(unit,from)
 local folder=workspace:FindFirstChild("Buildings")
 for _,building in ipairs(folder and folder:GetChildren() or {}) do
  local footprint=building.PrimaryPart
  if footprint and building:GetAttribute("OwnerId")==unit:GetAttribute("OwnerId") then
   local here=footprint.CFrame:PointToObjectSpace(Vector3.new(from.X,footprint.Position.Y,from.Z))
   if math.abs(here.X)<=footprint.Size.X/2+.05 and math.abs(here.Z)<=footprint.Size.Z/2+.05 then return building,footprint end
  end
 end
 return nil
end
local function auditSpawn(unit)
 if not unit:IsA("Model") or not unit.Parent or workspace:GetAttribute("MatchPhase")~="Playing" then return end
 local from,at=unit:GetAttribute("SpawnFrom"),unit:GetAttribute("SpawnAt")
 if from==nil and at==nil then return end
 local owner=ownerOf(unit)
 if not owner then audit.ai+=1; return end
 audit.human+=1
 audit.byOwner[owner.Name]=(audit.byOwner[owner.Name] or 0)+1
 local root=unit.PrimaryPart
 local kind=tostring(unit:GetAttribute("UnitType"))
 if typeof(from)~="Vector3" or type(at)~="number" or not root then
  check(false,"出生點〔"..owner.Name.."·"..kind.."〕：SpawnFrom 是 Vector3、SpawnAt 是數字、單位有 Root",typeof(from).."/"..typeof(at))
  return
 end
 local now=workspace:GetServerTimeNow()
 check(at<=now+.05 and now-at<=.5,"出生點〔"..owner.Name.."·"..kind.."〕：SpawnAt 是剛剛的伺服器時間",string.format("%.3f 秒前",now-at))
 local building,footprint=sourceBuilding(unit,from)
 if not building then
  audit.noBuilding+=1
  check(false,"出生點〔"..owner.Name.."·"..kind.."〕：SpawnFrom 落在自己某座建築的占地內",tostring(from))
  return
 end
 local buildingKind=tostring(building:GetAttribute("BuildingType"))
 local label="出生點〔"..owner.Name.."·"..buildingKind.."→"..kind.."〕"
 local center=footprint.Position
 local toRoot=flat(root.Position-center)
 local fromCenter=flat(from-center)
 local direction=toRoot.Magnitude>1e-3 and toRoot.Unit or Vector3.zero
 -- 1) 在「建築中心→出生點」的連線上，且介於兩者之間。
 local along=fromCenter:Dot(direction)
 local perpendicular=(fromCenter-direction*along).Magnitude
 -- 2) 在占地內，往外 1 stud 正好到達占地邊界（用占地本身的 CFrame，旋轉也成立）。
 local half=footprint.Size/2
 local inside=footprint.CFrame:PointToObjectSpace(Vector3.new(from.X,center.Y,from.Z))
 local edge=footprint.CFrame:PointToObjectSpace(Vector3.new(from.X,center.Y,from.Z)+direction)
 local insideRatio=math.max(math.abs(inside.X)/half.X,math.abs(inside.Z)/half.Z)
 local edgeX,edgeZ=math.abs(edge.X)/half.X,math.abs(edge.Z)/half.Z
 local edgeRatio=math.max(edgeX,edgeZ)
 local face=edgeX>=edgeZ and "x" or "z"
 local _,_,_,r00,_,_,_,r11,_,_,_,r22=footprint.CFrame:GetComponents()
 local rotation=math.acos(math.clamp((r00+r11+r22-1)/2,-1,1))
 -- 這裡在 task.defer 之後才檢查：同一批連續出生的單位可能已被單位碰撞分離推開約 1 stud，
 -- Root 不再是 markSpawn 當下的出生點，所以連線偏離容許 1.5 studs；邊緣比例仍以占地精確檢查。
 local ok=direction.Magnitude>0 and perpendicular<=1.5 and along>0 and along<toRoot.Magnitude
  and insideRatio<1 and math.abs(edgeRatio-1)<=.02 and math.abs(from.Y-root.Position.Y)<=.01
 check(ok,label.."：SpawnFrom 在中心→出生點連線上、占地內，往外 1 stud 到占地邊緣，高度同 Root",
  string.format("偏離連線 %.3f、離中心 %.2f／出生點 %.2f、邊緣比例 %.3f（%s 面）、占地 %.0f×%.0f、占地旋轉 %.3f rad、高度差 %.3f",
   perpendicular,along,toRoot.Magnitude,edgeRatio,face,footprint.Size.X,footprint.Size.Z,rotation,from.Y-root.Position.Y))
 local faces=audit.faces[buildingKind] or {x=0,z=0,square=math.abs(footprint.Size.X-footprint.Size.Z)<.01}
 faces[face]+=1
 audit.faces[buildingKind]=faces
end
local function attachUnits(folder)
 if folder.Name~="Units" or not folder:IsA("Folder") then return end
 -- markSpawn 在單位放進 Units 之後才寫屬性：延後到同一輪結束再讀。
 folder.ChildAdded:Connect(function(unit) task.defer(auditSpawn,unit) end)
end
workspace.ChildAdded:Connect(attachUnits)
for _,child in ipairs(workspace:GetChildren()) do attachUnits(child) end

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
local function spawnNear(ownerId,kind,center,minRadius,maxRadius)
 for radius=minRadius,maxRadius,2 do
  for index=0,15 do
   local angle=index*math.pi/8
   local position=Vector3.new(center.X+math.cos(angle)*radius,0,center.Z+math.sin(angle)*radius)
   if inMap(position) and clear(position,3.2) then
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
-- 測試生成的單位（含電腦的）都標記要求者，remove 只移除這些。
local function testUnit(unit,tag,player)
 if not unit then return nil end
 unit:SetAttribute("AnimTestTag",tag)
 unit:SetAttribute("AnimTestOwner",player.UserId)
 return unit
end
local function directions(player)
 local home=player:GetAttribute("HomePosition")
 if typeof(home)~="Vector3" then return nil end
 home=flat(home)
 local inward=home.Magnitude>1 and (-home).Unit or Vector3.new(1,0,0)
 return home,inward,Vector3.new(-inward.Z,0,inward.X)
end

local built={} -- 標籤 -> 測試用的電腦房屋
local helper=Instance.new("RemoteFunction")
helper.Name="AnimTestHelper"
helper.OnServerInvoke=function(player,action,a,b,c,d)
 if not probe then return nil end
 if action=="ai" then return aiId()
 elseif action=="prepare" then
  -- 自己的已完工房屋（人口）；a=true 時另放一座自己的馬廄（4×3 非正方形占地）。
  local home,inward,side=directions(player)
  if not home then return nil end
  local houses=0
  for _,center in ipairs({home+side*50,home-side*50,home-inward*45,home+side*50-inward*25,home-side*50-inward*25}) do
   if houses>=3 then break end
   local house=placeNear(player.UserId,"House",center,30)
   if house then houses+=1; house:SetAttribute("AnimTestTag","house") end
  end
  local stable=nil
  if a==true then
   stable=placeNear(player.UserId,"Stable",home+inward*62,40)
   if stable then stable:SetAttribute("AnimTestTag","stable-"..player.UserId) end
  end
  return {houses=houses,stable=stable~=nil,stableTag="stable-"..player.UserId}
 elseif action=="runner" then
  -- 地面箭：a 位置，b 標籤。電腦村民去攻擊遠處自己的誘餌（一路跑開），自己的弓箭手追著射它。
  -- 箭飛向發射當下的位置；抵達時目標已離開 2.5 studs 以上，就會插在地上。
  local ai=aiId()
  local home=directions(player)
  if not ai or not home or typeof(a)~="Vector3" or type(b)~="string" then return nil end
  local away=flat(a-home)
  away=away.Magnitude>1 and away.Unit or Vector3.new(1,0,0)
  local target=testUnit(spawnNear(ai,"villager",a,0,24),b.."-target",player)
  if not target then return nil end
  local spot=flat(target:GetPivot().Position)
  local bait=testUnit(spawnNear(player.UserId,"villager",spot+away*100,0,30),b.."-bait",player)
  local archer=testUnit(spawnNear(player.UserId,"archer",spot-away*34,0,14),b.."-archer",player)
  if not bait or not archer then return nil end
  probe:Invoke("attack",target,bait)
  probe:Invoke("attack",archer,target)
  return {target=spot,archer=flat(archer:GetPivot().Position),bait=flat(bait:GetPivot().Position)}
 elseif action=="lodge" then
  -- 插在建築上的箭：a 位置，b 標籤，c 弓箭手數量（1～3）。放一座電腦的已完工房屋，自己的弓箭手射它。
  local ai=aiId()
  local home=directions(player)
  if not ai or not home or typeof(a)~="Vector3" or type(b)~="string" then return nil end
  local house=placeNear(ai,"House",a,36)
  if not house then return nil end
  house:SetAttribute("AnimTestTag",b)
  built[b]=house
  local center=flat(house:GetPivot().Position)
  local toward=flat(home-center)
  toward=toward.Magnitude>1 and toward.Unit or Vector3.new(1,0,0)
  local side=Vector3.new(-toward.Z,0,toward.X)
  local count=math.clamp(type(c)=="number" and math.floor(c) or 2,1,3)
  local archers=0
  for index=1,count do
   local archer=testUnit(spawnNear(player.UserId,"archer",center+toward*28+side*((index-(count+1)/2)*7),0,12),b.."-archer",player)
   if archer and probe:Invoke("attack",archer,house)==true then archers+=1 end
  end
  return {center=center,ground=bottom(house),archers=archers}
 elseif action=="raze" then
  -- a：lodge 的標籤。生命設為 1，弓箭手下一箭以正式 damage() 摧毀它。
  local house=type(a)=="string" and built[a] or nil
  if not house or house.Parent~=workspace:FindFirstChild("Buildings") then return false end
  built[a]=nil
  house:SetAttribute("HP",1)
  return true
 elseif action=="remove" then
  -- 只移除這位玩家要求生成的測試單位（probe remove 不留屍體）。
  local count=0
  local units=workspace:FindFirstChild("Units")
  for _,unit in ipairs(units and units:GetChildren() or {}) do
   if unit:GetAttribute("AnimTestOwner")==player.UserId then probe:Invoke("remove",unit); count+=1 end
  end
  return count
 elseif action=="summary" then
  local units=workspace:FindFirstChild("Units")
  local leftover=0
  for _,unit in ipairs(units and units:GetChildren() or {}) do
   if unit:GetAttribute("AnimTestOwner")~=nil then leftover+=1 end
  end
  return {passed=passed,failed=failed,human=audit.human,ai=audit.ai,noBuilding=audit.noBuilding,
   faces=audit.faces,byOwner=audit.byOwner,testUnits=leftover,scoutTrainTime=SCOUT_TRAIN_TIME}
 elseif action=="phase" then
  if type(a)~="string" then return false end
  workspace:SetAttribute("AnimHarnessPhase",a)
  return true
 elseif action=="report" then
  -- 第二位客戶端回報：a 通過，b 失敗，c 檢查過的出場數，d 檢查過的插著的箭數。
  if type(a)~="number" or type(b)~="number" or type(c)~="number" or type(d)~="number" then return false end
  workspace:SetAttribute("AnimObserverReport",string.format("%s|%d|%d|%d|%d",player.Name,math.floor(a),math.floor(b),math.floor(c),math.floor(d)))
  return true
 end
 return nil
end
helper.Parent=RS
Players.PlayerRemoving:Connect(function(player) info(player.Name.." 離開") end)
info("輔助就緒（斥候騎兵訓練時間 "..SCOUT_TRAIN_TIME.." 秒）")
