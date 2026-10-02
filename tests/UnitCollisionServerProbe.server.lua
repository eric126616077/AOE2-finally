-- 僅映射於 unit-collision-validation.project.json；正式專案不會自動執行。
-- 新 Studio SERVER Play 的私有引擎 fixture + 四名起始單位唯讀稽核。
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerScriptService=game:GetService("ServerScriptService")
local WINDOW_SECONDS,WAIT_SECONDS,MAX_HEARTBEAT_GAP=95,600,2
local TOLERANCE,MIN_GAP=0.001,0.05
local launched=os.clock()
local checks,samples,violations,fixtureChecks=0,0,0,0
local auditStart,lastSample,minGap,generation,unitFolder
local entries={}
local waitingConnection,auditConnection,removedConnection
local finished=false

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function rounded(value)
 return math.floor(value*1000+0.5)/1000
end
local function emit(stage,record)
 record.probe,record.stage="UC95",stage
 local encoded=HttpService:JSONEncode(record)
 assert(#encoded<600,"UC95 JSON exceeds 600 bytes")
 print("[UC95] "..encoded)
end
local function disconnect()
 if waitingConnection then waitingConnection:Disconnect(); waitingConnection=nil end
 if auditConnection then auditConnection:Disconnect(); auditConnection=nil end
 if removedConnection then removedConnection:Disconnect(); removedConnection=nil end
end
local function finish(ok,reason)
 if finished then return end
 finished=true
 disconnect()
 local moving,kinds={},{}
 for _,entry in ipairs(entries) do
  table.insert(moving,entry.moving)
  table.insert(kinds,entry.kind)
 end
 local now=os.clock()
 local elapsed=auditStart and now-auditStart or 0
 emit("FINAL",{ok=ok,reason=reason,seconds=finite(elapsed) and rounded(elapsed) or false,
  checks=checks,samples=samples,minGap=minGap and rounded(minGap) or false,
  violations=violations,factory=fixtureChecks,moving=moving,kinds=kinds})
end
local function verify(condition,reason)
 checks+=1
 if not condition then error(reason,0) end
end
local function frameFinite(frame)
 for _,component in ipairs({frame:GetComponents()}) do if not finite(component) then return false end end
 return true
end
local function fail(reason,detail)
 violations+=1
 if detail then warn("[UC95 ERROR] "..string.sub(tostring(detail),1,180)) end
 finish(false,reason)
end

local function beginAudit(Config)
 if finished then return end
 local ok,failure=pcall(function()
  verify(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true,"sandbox_not_playing")
  generation=workspace:GetAttribute("MatchGeneration")
  verify(finite(generation),"generation_invalid")
  unitFolder=workspace:FindFirstChild("Units")
  verify(unitFolder and unitFolder:IsA("Folder"),"units_folder_missing")
  -- 正式 GameServer 的資料夾名稱是 Units；只讀取一次其直屬子物件。
  local initial={}
  for _,unit in ipairs(unitFolder:GetChildren()) do
   if unit:IsA("Model") and unit:GetAttribute("RTSManaged")==true then table.insert(initial,unit) end
  end
  verify(#initial==4,"initial_unit_count")
  table.sort(initial,function(a,b)
   local ka,kb=tostring(a:GetAttribute("UnitType")),tostring(b:GetAttribute("UnitType"))
   if ka~=kb then return ka<kb end
   local pa,pb=a:GetPivot().Position,b:GetPivot().Position
   return pa.X==pb.X and pa.Z<pb.Z or pa.X<pb.X
  end)
  local counts={}
  for _,unit in ipairs(initial) do
   local root,volume=unit:FindFirstChild("Root"),unit:FindFirstChild("CollisionVolume")
   local kind=unit:GetAttribute("UnitType")
   verify(type(kind)=="string" and #kind<=24 and Config.Units[kind]~=nil,"unit_type_invalid")
   verify(root and root:IsA("BasePart") and root==unit.PrimaryPart,"root_missing")
   verify(volume and volume:IsA("Part"),"volume_missing")
   counts[kind]=(counts[kind] or 0)+1
   table.insert(entries,{unit=unit,root=root,volume=volume,modifier=volume:FindFirstChildWhichIsA("PathfindingModifier"),
    kind=kind,profile=Config.UnitCollision.profiles[Config.Units[kind].class] or Config.UnitCollision.default,
    previous=root.Position,moving=0})
  end
  verify(counts.villager==3 and counts.scout==1,"initial_unit_kinds")
  auditStart,lastSample=os.clock(),os.clock()
  verify(finite(auditStart) and auditStart>=launched,"audit_clock_invalid")
 end)
 if not ok then fail("initial_invalid",failure); return end
 emit("START",{seconds=WINDOW_SECONDS,units=4,generation=generation,factory=fixtureChecks})
 removedConnection=unitFolder.ChildRemoved:Connect(function(unit)
  for _,entry in ipairs(entries) do if entry.unit==unit then fail("initial_unit_removed"); return end end
 end)
 -- 此連線由 task.defer 建立，位於 GameServer 啟動／當次 Heartbeat 之後。
 auditConnection=RunService.Heartbeat:Connect(function(dt)
  if finished then return end
  local passed,detail=pcall(function()
   local now=os.clock()
   verify(finite(dt) and dt>0 and dt<=MAX_HEARTBEAT_GAP,"heartbeat_dt_invalid")
   verify(finite(now) and now>=lastSample and now-lastSample<=MAX_HEARTBEAT_GAP,"heartbeat_clock_gap")
   verify(now-auditStart<=WINDOW_SECONDS+MAX_HEARTBEAT_GAP,"audit_deadline_exceeded")
   verify(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true,"sandbox_changed")
   verify(workspace:GetAttribute("MatchGeneration")==generation,"generation_changed")
   verify(unitFolder.Parent==workspace,"units_folder_removed")
   lastSample=now
   samples+=1
   for _,entry in ipairs(entries) do
    local unit,root,volume=entry.unit,entry.root,entry.volume
    verify(unit.Parent==unitFolder and unit.PrimaryPart==root and root.Parent==unit and volume.Parent==unit,"unit_structure_changed")
    local radius,height=unit:GetAttribute("Radius"),unit:GetAttribute("CollisionHeight")
    verify(finite(radius) and radius>0 and finite(height) and height>0,"collision_number_invalid")
    verify(radius==entry.profile.radius and height==entry.profile.height,"collision_profile_changed")
    local hp,maxHP,ownerId=unit:GetAttribute("HP"),unit:GetAttribute("MaxHP"),unit:GetAttribute("OwnerId")
    verify(finite(hp) and hp>0 and finite(maxHP) and maxHP>=hp and finite(ownerId),"unit_attribute_invalid")
    verify(unit:GetAttribute("UnitType")==entry.kind and unit:GetAttribute("UnitClass")==Config.Units[entry.kind].class,"unit_identity_changed")
    verify(frameFinite(root.CFrame) and frameFinite(volume.CFrame),"unit_frame_invalid")
    verify(root.Anchored and not root.CanCollide and not root.CanQuery and not root.CanTouch,"root_flags_changed")
    verify(volume.Shape==Enum.PartType.Cylinder and volume.Anchored and volume.CanCollide and volume.CanQuery
     and not volume.CanTouch and volume.Transparency==1 and not volume.CastShadow,"volume_flags_changed")
    verify(entry.modifier and entry.modifier.Parent==volume and entry.modifier.PassThrough,"modifier_changed")
    verify((volume.Size-Vector3.new(height,radius*2,radius*2)).Magnitude<=TOLERANCE,"volume_size_changed")
    local point=root.Position
    verify(math.abs(point.Y-(Config.Map.GroundY+2.5))<=TOLERANCE,"root_ground_offset")
    local expected=Vector3.new(point.X,point.Y-2.5+height/2,point.Z)
    verify((volume.Position-expected).Magnitude<=TOLERANCE,"volume_does_not_follow_root")
    verify(math.abs(math.abs(volume.CFrame.RightVector.Y)-1)<=TOLERANCE,"volume_not_vertical")
    if Vector3.new(point.X-entry.previous.X,0,point.Z-entry.previous.Z).Magnitude>0.0001 then entry.moving+=1 end
    entry.previous,entry.point,entry.radius=point,point,radius
   end
   for first=1,#entries do
    for second=first+1,#entries do
     local a,b=entries[first],entries[second]
     local dx,dz=a.point.X-b.point.X,a.point.Z-b.point.Z
     local gap=math.sqrt(dx*dx+dz*dz)-a.radius-b.radius
     verify(finite(gap),"pair_gap_invalid")
     minGap=minGap and math.min(minGap,gap) or gap
     verify(gap>=MIN_GAP-TOLERANCE,"unit_overlap")
    end
   end
   if now-auditStart>=WINDOW_SECONDS then
    verify(samples>0 and finite(minGap) and violations==0 and fixtureChecks>0,"audit_incomplete")
    finish(true,"complete")
   end
  end)
  if not passed then fail("sample_invalid",detail) end
 end)
end

-- 從 defer 啟動，避免在 GameServer 初始化前掛上正式局的 Heartbeat 稽核。
task.defer(function()
 if not (RunService:IsStudio() and RunService:IsServer() and RunService:IsRunning()) then fail("not_studio_server_play"); return end
 local loaded,Config=pcall(function() return require(ReplicatedStorage.GameData.GameConfig) end)
 if not loaded then fail("config_load_failed",Config); return end
 local fixtureOK,result=pcall(function() return require(ServerScriptService.ServerModules.ModelFactoryTests).Run() end)
 if not fixtureOK or not finite(result) or result<=0 then fail("factory_fixture_failed",result); return end
 fixtureChecks=result
 emit("FIXTURE",{ok=true,checks=fixtureChecks})
 local waitStarted=os.clock()
 waitingConnection=RunService.Heartbeat:Connect(function(dt)
  if finished then return end
  local now=os.clock()
  if not finite(dt) or dt<=0 or not finite(now) or now<waitStarted or now-waitStarted>WAIT_SECONDS then
   fail("sandbox_wait_timeout"); return
  end
  if workspace:GetAttribute("MatchPhase")=="Playing" then
   waitingConnection:Disconnect(); waitingConnection=nil
   if workspace:GetAttribute("Sandbox")~=true then fail("not_sandbox"); return end
   task.defer(beginAudit,Config)
  elseif workspace:GetAttribute("MatchPhase")=="Ended" then fail("match_ended_before_audit") end
 end)
end)
