-- Test-only LocalScript, mapped only by combat-feel-validation.project.json.
-- 以正常大廳指令開一局，把鏡頭移到伺服器測試戰場，記錄客戶端實際看到的：
-- 投射物實體、受擊血條、屍體，以及近戰武器尖端離接觸點還差多少。只觀察，不下指令。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local player=game.Players.LocalPlayer
local function emit(kind,data) print("[COMBAT_FEEL_CLIENT] "..Http:JSONEncode({kind=kind,data=data})) end
local function round(value,digits)
 if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false end
 local scale=10^(digits or 2)
 return math.floor(value*scale+0.5)/scale
end
local function untilTrue(predicate,seconds,message)
 local deadline=os.clock()+seconds
 repeat if predicate() then return end; Run.Heartbeat:Wait() until os.clock()>deadline
 error("[COMBAT_FEEL_CLIENT FAIL] "..message)
end
untilTrue(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30,"初始化逾時")
require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"})
untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,40,"開始測試局逾時")
local Focus=require(RS.Shared.CameraFocus)
local units=workspace:WaitForChild("Units")
local weaponNames={Sword=true,Spearhead=true,ToolHead=true,RamHead=true}
local stage
local stats
local function reset() stats={effects={},maxHealthBars=0,maxCorpses=0,projectileSeconds={},gaps={},lunges={}} end
reset()
local function flush()
 if not stage then return end
 for name,list in pairs(stats.projectileSeconds) do
  table.sort(list)
  stats.projectileSeconds[name]={count=#list,min=list[1],median=list[math.ceil(#list/2)],max=list[#list]}
 end
 for kind,list in pairs(stats.gaps) do
  table.sort(list)
  stats.gaps[kind]={count=#list,min=list[1],median=list[math.ceil(#list/2)],max=list[#list]}
 end
 for kind,list in pairs(stats.lunges) do
  table.sort(list)
  stats.lunges[kind]={count=#list,min=list[1],median=list[math.ceil(#list/2)],max=list[#list]}
 end
 stats.stage=stage
 emit("STAGE",stats)
 reset()
end
local effects=workspace:WaitForChild("RTSClientEffects")
-- UnitMotion 的特效物件會重複使用：同一個物件每次飛行都重新加入 RTSClientEffects。
-- 每個物件只連一次 Parent 監聽，每次加入時重設起點；離開資料夾即視為飛行結束
-- （歸還物件池時 Parent=nil，插在地上／建築上時移到 RTSStuckArrows）。
local flights=setmetatable({}, {__mode="k"})
local watched=setmetatable({}, {__mode="k"})
effects.ChildAdded:Connect(function(object)
 stats.effects[object.Name]=(stats.effects[object.Name] or 0)+1
 if object.Name=="ArrowEffect" or object.Name=="JavelinEffect" or object.Name=="StoneEffect" then
  local name,bucket=object.Name,stats
  local pieces=#object:GetChildren()
  bucket.effects[name.."Pieces"]=math.max(bucket.effects[name.."Pieces"] or 0,pieces)
  flights[object]={born=os.clock(),name=name,bucket=bucket}
  if watched[object] then return end
  watched[object]=true
  object:GetPropertyChangedSignal("Parent"):Connect(function()
   local flight=flights[object]
   if not flight or object.Parent==effects then return end
   flights[object]=nil
   local list=flight.bucket.projectileSeconds
   list[flight.name]=list[flight.name] or {}
   if type(list[flight.name])=="table" and #list[flight.name]<200 then table.insert(list[flight.name],round(os.clock()-flight.born,3)) end
  end)
 end
end)
-- 近戰：出手後 0.6 秒內，武器最前緣沿面向方向離 Root 多遠；對照伺服器給的接觸點距離。
local swings={}
local function forwardExtent(part,origin,look)
 local size,frame=part.Size/2,part.CFrame
 local best=-math.huge
 for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
  local corner=frame*Vector3.new(size.X*sx,size.Y*sy,size.Z*sz)
  best=math.max(best,(corner.X-origin.X)*look.X+(corner.Z-origin.Z)*look.Z)
 end end end
 return best
end
local function track(model)
 if not model:IsA("Model") then return end
 model:GetAttributeChangedSignal("LastAttack"):Connect(function()
  task.defer(function()
   local contact,root=model:GetAttribute("AttackContact"),model.PrimaryPart
   if typeof(contact)~="Vector3" or not root then return end
   local weapons,body={},nil
   for _,part in ipairs(model:GetDescendants()) do
    if part:IsA("BasePart") and weaponNames[part.Name] then table.insert(weapons,part) end
    if part:IsA("BasePart") and (part.Name=="Body" or part.Name=="Chassis") and not body then body=part end
   end
   swings[model]={started=os.clock(),weapons=weapons,body=body,bodyRest=nil,reach=-math.huge,lunge=0,
    contact=(Vector3.new(contact.X,0,contact.Z)-Vector3.new(root.Position.X,0,root.Position.Z)).Magnitude,kind=model:GetAttribute("UnitType"),bucket=stats}
  end)
 end)
end
for _,model in ipairs(units:GetChildren()) do track(model) end
units.ChildAdded:Connect(track)
local sampleClock=0
local barPositions=setmetatable({}, {__mode="k"})
Run.RenderStepped:Connect(function(delta)
 for model,swing in pairs(swings) do
  local root=model.PrimaryPart
  if not root or not model.Parent or os.clock()-swing.started>0.6 then
   if swing.reach>-math.huge then
    local bucket=swing.bucket
    bucket.gaps[swing.kind]=bucket.gaps[swing.kind] or {}
    bucket.lunges[swing.kind]=bucket.lunges[swing.kind] or {}
    if type(bucket.gaps[swing.kind])=="table" and #bucket.gaps[swing.kind]<200 then
     table.insert(bucket.gaps[swing.kind],round(swing.contact-swing.reach,2))
     table.insert(bucket.lunges[swing.kind],round(swing.lunge,2))
    end
   end
   swings[model]=nil
  else
   local look=root.CFrame.LookVector
   for _,part in ipairs(swing.weapons) do
    if part.Parent then swing.reach=math.max(swing.reach,forwardExtent(part,root.Position,look)) end
   end
   if swing.body and swing.body.Parent then
    local forward=(swing.body.Position.X-root.Position.X)*look.X+(swing.body.Position.Z-root.Position.Z)*look.Z
    swing.bodyRest=swing.bodyRest or forward
    swing.lunge=math.max(swing.lunge,forward-swing.bodyRest)
   end
  end
 end
 sampleClock+=delta
 if sampleClock<0.2 then return end
 sampleClock=0
 local bars=0
 for _,gui in ipairs(player.PlayerGui:GetChildren()) do if gui.Name=="RTSHealthBar" then bars+=1 end end
 stats.maxHealthBars=math.max(stats.maxHealthBars,bars)
 local corpses=workspace:FindFirstChild("Corpses")
 stats.maxCorpses=math.max(stats.maxCorpses,corpses and #corpses:GetChildren() or 0)
end)
local function changed()
 local value=workspace:GetAttribute("CombatFeelStage")
 if type(value)~="string" then return end
 flush()
 stage=value
 local center=workspace:GetAttribute("CombatFeelCenter")
 if typeof(center)=="Vector3" then Focus.Request(player,center) end
end
workspace:GetAttributeChangedSignal("CombatFeelStage"):Connect(changed)
changed()
emit("READY",{})
-- Heartbeat 在畫面送出後執行：量到的是該幀實際畫出的血條錨點位置。單幀跳超過 0.9 studs 視為卡頓。
Run.Heartbeat:Connect(function()
 -- 血條平滑度：走路中的單位，血條世界位置每幀是否都有移動（卡頓＝多幀停在原地再跳）。
 for _,gui in ipairs(player.PlayerGui:GetChildren()) do
  if gui.Name=="RTSHealthBar" and gui.Adornee and gui.Adornee.Parent and gui.Adornee.Parent==workspace:FindFirstChild('RTSClientAnchors') then
   local position=gui.Adornee.Position+gui.StudsOffsetWorldSpace
   local previous=barPositions[gui]
   barPositions[gui]=position
   if previous then
    stats.barFrames=(stats.barFrames or 0)+1
    local step=(position-previous).Magnitude
    if step>0.001 then stats.barMovingFrames=(stats.barMovingFrames or 0)+1 end
    if step>0.9 then stats.barJumpFrames=(stats.barJumpFrames or 0)+1 end
    stats.barWorstStep=math.max(stats.barWorstStep or 0,round(step,2))
   end
  end
 end
end)
