-- 僅映射於 cinematic.project.json；正式專案不會載入。
-- Studio SERVER：戰鬥預告片的「場務」。用 GameServer 的 Studio 專用 RTSBattleProbe 在兩座主城之間排出兩軍與一座起火的敵方城堡，
-- 再依 CinematicRules 的時間軸下達衝鋒、攻城與倒塌。交戰、投射物、倒地與倒塌全部由正式遊戲邏輯產生。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("CinematicRules"))
-- 固定地圖種子：每次重拍都是同一片戰場（必須在開局生成地圖前設定）。
Config.Map.RandomizeSeed=false
local function log(message) print("[TRAILER] "..message) end

local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
if not probe then warn("[TRAILER] RTSBattleProbe missing"); return end
repeat task.wait(0.5) until workspace:GetAttribute("MatchPhase")=="Playing" and (workspace:GetAttribute("FactionCount") or 0)>=2
task.wait(3)
local player=Players:GetPlayers()[1]
local aiActor=RS:WaitForChild("RTSFactions"):FindFirstChildWhichIsA("Folder")
if not player or not aiActor then warn("[TRAILER] need one human and one AI faction"); return end
local ids={player.UserId,aiActor:GetAttribute("OwnerId")}
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local home=flat(player:GetAttribute("HomePosition") or Vector3.zero)
local aiHome=aiActor:GetAttribute("HomePosition")
aiHome=typeof(aiHome)=="Vector3" and flat(aiHome) or -home
local half=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
local unitFolder=workspace:WaitForChild("Units")

local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Exclude
do
 local ground=workspace:FindFirstChild("AOE2_Ground")
 overlap.FilterDescendantsInstances=ground and {ground} or {}
end
local function blockers(frame,size)
 local count=0
 for _,part in ipairs(workspace:GetPartBoundsInBox(frame,size,overlap)) do if part.CanCollide then count+=1 end end
 return count
end

-- 戰場沿「我方主城 → 電腦主城」的方向展開；在兩城連線附近挑障礙最少的位置。
local axis=(aiHome-home).Magnitude>1 and (aiHome-home).Unit or Vector3.xAxis
local side=Vector3.new(-axis.Z,0,axis.X)
local center,best=nil,math.huge
for _,fraction in ipairs({0.5,0.45,0.55,0.4,0.6}) do
 for _,lateral in ipairs({0,-40,40,-80,80}) do
  local candidate=home:Lerp(aiHome,fraction)+side*lateral
  if math.abs(candidate.X)<half-60 and math.abs(candidate.Z)<half-60 then
   local count=blockers(CFrame.lookAt(candidate+Vector3.new(0,4,0),candidate+Vector3.new(0,4,0)+axis),Vector3.new(110,8,200))
   if count<best then center,best=candidate,count end
  end
 end
end
if not center then warn("[TRAILER] no battlefield"); return end
local gapHalf=Rules.FrontGap/2
local fronts={center-axis*gapHalf,center+axis*gapHalf}
workspace:SetAttribute("TrailerCenter",center)
workspace:SetAttribute("TrailerAxis",axis)
workspace:SetAttribute("TrailerHumanFront",fronts[1])
workspace:SetAttribute("TrailerAIFront",fronts[2])
log(("battlefield center=(%d,%d) obstacles=%d"):format(center.X,center.Z,best))

local roster={{},{}}
local function inBounds(position,margin) return math.abs(position.X)<half-margin and math.abs(position.Z)<half-margin end
local function place(sideIndex,kind,position,role)
 local profile=Config.UnitCollision.profiles[Config.Units[kind].class] or Config.UnitCollision.default
 local size=Vector3.new(profile.radius*2+0.6,profile.height,profile.radius*2+0.6)
 if not inBounds(position,profile.radius+4) or blockers(CFrame.new(position+Vector3.new(0,profile.height/2+0.2,0)),size)>0 then return nil end
 local unit=probe:Invoke("spawn",ids[sideIndex],kind,position)
 if not unit then return nil end
 -- 面向敵陣排好隊；伺服器下一次移動才會改變朝向。
 local facing=sideIndex==1 and axis or -axis
 pcall(function() local p=unit:GetPivot().Position; unit:PivotTo(CFrame.lookAt(p,p+facing)) end)
 unit:SetAttribute("TrailerSide",sideIndex)
 unit:SetAttribute("TrailerRole",role)
 table.insert(roster[sideIndex],unit)
 return unit
end

-- 電腦累積 8 名以上軍隊時會把全部軍隊派去進攻（GameServer 的 aiStep）。先在電腦主城旁放 8 名誘餌觸發這一波，
-- 誘餌接到進攻命令後立刻移除；下一波要等 Rules.AIWaveSeconds，電腦的大軍才能在對峙段站著不動。
do
 local decoys={}
 for index=1,24 do
  if #decoys>=8 then break end
  local angle=index*2.4
  local position=aiHome+Vector3.new(math.cos(angle),0,math.sin(angle))*(40+index*2)
  if inBounds(position,8) then
   local unit=probe:Invoke("spawn",ids[2],"infantry",position)
   if unit then table.insert(decoys,unit) end
  end
 end
 local deadline=os.clock()+6
 local triggered=false
 repeat
  task.wait(0.1)
  for _,unit in ipairs(decoys) do if unit.Parent and unit:GetAttribute("OrderKind")=="attack" then triggered=true end end
 until triggered or os.clock()>deadline
 for _,unit in ipairs(decoys) do if unit.Parent then probe:Invoke("remove",unit) end end
 log(("AI wave decoys=%d triggered=%s"):format(#decoys,tostring(triggered)))
end

-- 每側：前排長槍／步兵、第二排步兵、兩排弓兵與矛兵、兩翼騎士、後方投石車。
local WIDTH,SPACING,ROW=10,6,6.5
local LINES={
 {kinds={"spearman","infantry"},role="melee"},
 {kinds={"infantry"},role="melee"},
 {kinds={"archer"},role="archer"},
 {kinds={"archer","skirmisher"},role="archer",width=8},
}
for sideIndex=1,2 do
 local forward=sideIndex==1 and axis or -axis
 local front=fronts[sideIndex]
 for row,line in ipairs(LINES) do
  local width=line.width or WIDTH
  for column=1,width do
   local lateral=(column-(width+1)/2)*SPACING
   place(sideIndex,line.kinds[(column-1)%#line.kinds+1],front-forward*(row-1)*ROW+side*lateral,line.role)
  end
 end
 for _,wing in ipairs({-1,1}) do
  for index=0,2 do
   place(sideIndex,"cavalry",front+forward*2-forward*index*ROW+side*wing*((WIDTH+1)/2*SPACING+8),"cavalry")
  end
 end
 for _,lateral in ipairs({-14,14}) do place(sideIndex,"mangonel",front-forward*(#LINES*ROW+10)+side*lateral,"mangonel") end
end
log(("armies placed human=%d ai=%d"):format(#roster[1],#roster[2]))

-- 電腦方的城堡在電腦陣線後方；放不下城堡就退而求其次。
local fort
for _,kind in ipairs({"Castle","Tower","Barracks"}) do
 local data=Config.Buildings[kind]
 local depth=math.max(data.size.X,data.size.Y)*Config.Map.GridSize/2
 for _,distance in ipairs({gapHalf+50,gapHalf+60,gapHalf+40,gapHalf+75}) do
  for _,lateral in ipairs({0,-16,16,-32,32}) do
   local position=center+axis*(distance+depth)+side*lateral
   if inBounds(position,depth+8) then fort=probe:Invoke("build",ids[2],kind,position) end
   if fort then break end
  end
  if fort then break end
 end
 if fort then log("fort="..kind); break end
end
local fortPosition
if fort then
 fort:SetAttribute("TrailerRole","fort")
 fortPosition=flat(fort:GetPivot().Position)
 workspace:SetAttribute("TrailerFort",fortPosition)
else
 warn("[TRAILER] no space for an enemy fort; siege shots will frame the AI rear instead")
 fortPosition=center+axis*(gapHalf+60)
 workspace:SetAttribute("TrailerFort",fortPosition)
end
local fortRadius=fort and math.max(fort:GetExtentsSize().X,fort:GetExtentsSize().Z)/2 or 10

local function alive(unit) return unit.Parent==unitFolder end
local function nearest(unit,list)
 local p,best,bestDistance=unit:GetPivot().Position,nil,math.huge
 for _,other in ipairs(list) do
  if alive(other) then
   local distance=(other:GetPivot().Position-p).Magnitude
   if distance<bestDistance then best,bestDistance=other,distance end
  end
 end
 return best
end

local startAt
local ACTIONS={}
-- 衝鋒：雙方所有部隊各自鎖定最近的敵人；投石車打對方近戰密集處。
ACTIONS.charge=function()
 for sideIndex=1,2 do
  local enemies=roster[3-sideIndex]
  local melee={}
  for _,unit in ipairs(enemies) do if unit:GetAttribute("TrailerRole")=="melee" then table.insert(melee,unit) end end
  for _,unit in ipairs(roster[sideIndex]) do
   if alive(unit) then
    local target=unit:GetAttribute("TrailerRole")=="mangonel" and nearest(unit,melee) or nearest(unit,enemies)
    if target then probe:Invoke("attack",unit,target) end
   end
  end
 end
end
-- 攻城：在城堡前方（從我方看）放下衝車、護衛與投石車；鏡頭此時剛好切走，看不到生成瞬間。
ACTIONS.siege=function()
 if not fort or not fort.Parent then return end
 local maxHP=fort:GetAttribute("MaxHP") or 1
 fort:SetAttribute("HP",math.min(fort:GetAttribute("HP") or maxHP,maxHP*Rules.FortHPFraction))
 local attackers={}
 local approach=fortPosition-axis*(fortRadius+20)
 for _,lateral in ipairs({-10,-3.5,3.5,10}) do table.insert(attackers,place(1,"ram",approach+side*lateral,"ram")) end
 for index=0,5 do table.insert(attackers,place(1,"infantry",approach-axis*9+side*((index-2.5)*5),"escort")) end
 for _,lateral in ipairs({-12,12}) do table.insert(attackers,place(1,"mangonel",fortPosition-axis*(fortRadius+48)+side*lateral,"siegeMangonel")) end
 local placed=0
 for _,unit in pairs(attackers) do
  if unit and probe:Invoke("attack",unit,fort) then placed+=1 end
 end
 log(("siege group attacking=%d"):format(placed))
end
-- 倒塌：只留 1 點血，下一發衝車或石彈就會照正式流程摧毀並留下倒塌複本。
ACTIONS.collapse=function()
 if fort and fort.Parent and (fort:GetAttribute("HP") or 0)>1 then fort:SetAttribute("HP",1) end
end
-- 攻城段期間持續撐住城堡血量下限，倒塌時間點才由時間軸決定。
ACTIONS.hold=function()
 local release=startAt+Rules.StageStart("collapse")-Rules.CollapseLead
 while fort and fort.Parent and workspace:GetServerTimeNow()<release do
  local floor=(fort:GetAttribute("MaxHP") or 1)*Rules.FortFloorFraction
  local hp=fort:GetAttribute("HP") or 0
  if hp>0 and hp<floor then fort:SetAttribute("HP",floor) end
  task.wait(0.05)
 end
end

startAt=workspace:GetServerTimeNow()+1
workspace:SetAttribute("TrailerStartAt",startAt)
local function at(offset,callback)
 task.delay(math.max(0,startAt+offset-workspace:GetServerTimeNow()),function()
  if workspace:GetAttribute("MatchPhase")~="Playing" then return end
  local ok,message=pcall(callback)
  if not ok then warn("[TRAILER] "..tostring(message)) end
 end)
end
at(Rules.StageStart("charge"),ACTIONS.charge)
at(Rules.StageStart("siege")-0.3,ACTIONS.siege)
at(Rules.StageStart("siege")-0.3,ACTIONS.hold)
at(Rules.StageStart("collapse")-Rules.CollapseLead,ACTIONS.collapse)
at(Rules.Total,function() log("done fortStanding="..tostring(fort~=nil and fort.Parent~=nil)) end)
log(("rolling total=%.1fs"):format(Rules.Total))
