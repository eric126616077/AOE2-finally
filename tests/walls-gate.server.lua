-- 僅映射於 walls-validation.project.json；正式專案不會自動執行。
-- Studio SERVER 輔助：提供客戶端測試讀取伺服器端事實（單位位置、城門占地、導航結果），
-- 並用 GameServer 的 Studio 專用 RTSBattleProbe 生成敵方單位。唯一寫入的遊戲狀態是把測試玩家的
-- Age 設為 2（略過正常升級到封建時代），其餘建造、扣款、施工與移動都走正式指令。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local Pathfinding=game:GetService("PathfindingService")
local probe=script.Parent:WaitForChild("RTSBattleProbe",60)
local remote=Instance.new("RemoteFunction")
remote.Name="WallsGateTest"
local function aiId()
 local actor=RS:WaitForChild("RTSFactions"):FindFirstChildWhichIsA("Folder")
 return actor and actor:GetAttribute("OwnerId")
end
local function navigate(from,to,costs)
 local ok,status,count=pcall(function()
  local path=Pathfinding:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=false,WaypointSpacing=8,Costs=costs})
  path:ComputeAsync(from+Vector3.new(0,2,0),to+Vector3.new(0,2,0))
  return path.Status.Name,#path:GetWaypoints()
 end)
 return ok and status or ("error: "..tostring(status)),ok and count or 0
end
remote.OnServerInvoke=function(player,action,a,b)
 if action=="setup" then
  player:SetAttribute("Age",2)
  return {age=player:GetAttribute("Age"),ai=aiId(),probe=probe~=nil}
 elseif action=="pos" then
  if typeof(a)~="Instance" or not a:IsDescendantOf(workspace) then return nil end
  return a:GetPivot().Position
 elseif action=="gate" then
  local root=typeof(a)=="Instance" and a:IsA("Model") and a.PrimaryPart
  if not root then return nil end
  local modifier=root:FindFirstChildWhichIsA("PathfindingModifier")
  return {canCollide=root.CanCollide,canQuery=root.CanQuery,label=modifier and modifier.Label or false,
   passThrough=modifier and modifier.PassThrough or false,size=root.Size,position=root.Position,
   open=a:GetAttribute("GateOpen"),rotated=a:GetAttribute("Rotated")}
 elseif action=="enemy" then
  if not probe or typeof(a)~="Vector3" or typeof(b)~="Instance" then return nil end
  local unit=probe:Invoke("spawn",aiId(),"infantry",a)
  if not unit then return nil end
  return unit,probe:Invoke("attack",unit,b)
 elseif action=="remove" then
  if probe then probe:Invoke("remove",a) end
  return true
 elseif action=="nav" then
  -- a：城外起點，b：城內終點。敵方（城門標籤成本無限大）與己方（無成本表）各算一次。
  if typeof(a)~="Vector3" or typeof(b)~="Vector3" then return nil end
  local label="RTSGate"..tostring(player.UserId)
  local friendly,friendlyCount=navigate(a,b,nil)
  local hostile,hostileCount=navigate(a,b,{[label]=math.huge})
  return {friendly=friendly,friendlyWaypoints=friendlyCount,hostile=hostile,hostileWaypoints=hostileCount,label=label}
 end
 return nil
end
remote.Parent=RS
