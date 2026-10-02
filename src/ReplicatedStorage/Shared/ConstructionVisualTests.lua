-- Studio CLIENT only; requiring this module performs no work.
-- Run() starts a fresh single-player sandbox if needed and spends one House's
-- wood through normal commands. It leaves that test building in the test match.
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local Tests={running=false}
local function run()
 assert(RunService:IsStudio() and RunService:IsClient(),"[CONSTRUCTION_VISUAL FAIL] 僅限 Studio Play 客戶端")
 assert(#Players:GetPlayers()==1,"[CONSTRUCTION_VISUAL FAIL] 請使用新的單人沙盒工作階段")
 local player=Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
 command:FireServer("AutoWork",false) -- 手動控制整合測試：關閉自動工作，避免閒置村民自行介入。
 local savedMotion=player:GetAttribute("ReducedMotion")
 local deadline=os.clock()+90
 local checks,worker,site,probe=0,nil,nil,nil
 local function check(condition,message)
  assert(condition,"[CONSTRUCTION_VISUAL FAIL] "..message)
  checks+=1
  print("[CONSTRUCTION_VISUAL PASS] "..message)
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=math.min(deadline,os.clock()+seconds)
  repeat
   if predicate() then check(true,message); return end
   assert(os.clock()<untilTime,"[CONSTRUCTION_VISUAL FAIL] "..message.."；等待逾時")
   task.wait(.025)
  until false
 end
 local function location()
  Config.Map.MapSize=workspace:GetAttribute("MapSize") or Config.Map.MapSize
  local data=Config.Buildings.House
  local params=OverlapParams.new()
  params.FilterType=Enum.RaycastFilterType.Include
  params.FilterDescendantsInstances={workspace.Buildings,workspace.Units,workspace.Resources}
  for radius=40,128,8 do
   for index=0,31 do
    local angle=index*math.pi/16
    local pos=Grid.snap(worker.PrimaryPart.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
    if Grid.inBounds(pos,data.size) and #workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.new(0,data.height/2,0)),
     Vector3.new(data.size.X*Config.Map.GridSize-.2,data.height,data.size.Y*Config.Map.GridSize-.2),params)==0 then return pos end
   end
  end
  error("[CONSTRUCTION_VISUAL FAIL] 找不到合法測試工地")
 end
 local function actualOverlay()
  local folder=workspace:FindFirstChild("RTSConstructionEffects")
  if not folder then return nil end
  for _,object in ipairs(folder:GetChildren()) do
   local billboard=object:FindFirstChild("ConstructionProgress")
   if billboard and billboard.Adornee==site.PrimaryPart then return object,billboard end
  end
  return nil
 end
 local ok,result=xpcall(function()
  if workspace:GetAttribute("MatchPhase")=="Lobby" then
   require(RS.Shared.LobbyTests).Start({expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
  end
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true and player.Character==nil end,20,"正式無角色沙盒已開始")
  waitFor(function()
   probe=player.PlayerScripts:FindFirstChild("RTSConstructionVisualProbe")
   return player:GetAttribute("RTSBuildingVisualsReady")==true and probe and probe:IsA("BindableFunction")
  end,5,"正式施工 LocalScript 及唯讀探針初始化完成")
  for _,model in ipairs(workspace.Units:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("UnitType")=="villager" and model.PrimaryPart then worker=model; break end
  end
  check(worker~=nil,"正式村民已複製")
  command:FireServer("Stop",{worker})
  waitFor(function() return worker:GetAttribute("Order")=="待命" end,3,"正常停止測試村民")
  local old={}
  for _,building in ipairs(workspace.Buildings:GetChildren()) do old[building]=true end
  local pos=location()
  local wood=player:GetAttribute("wood")
  check(type(wood)=="number" and wood>=Config.Buildings.House.cost.wood,"正式資源足以建立房屋")
  player:SetAttribute("ReducedMotion",false)
  command:FireServer("Build","House",pos,{worker})
  waitFor(function()
   for _,building in ipairs(workspace.Buildings:GetChildren()) do
    if not old[building] and building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")=="House" and building.PrimaryPart then site=building; return true end
   end
   return false
  end,5,"正常指令建立伺服器房屋工地")
  check(player:GetAttribute("wood")==wood-Config.Buildings.House.cost.wood and site:GetAttribute("Complete")==false,"工地扣款一次且尚未完工")
  local root=site.PrimaryPart
  local original=root.CFrame
  require(RS.Shared.CameraFocus).Request(player,root.Position)
  waitFor(function()
   local camera=workspace.CurrentCamera
   local point,visible=camera:WorldToViewportPoint(root.Position)
   return visible and point.Z>0 and actualOverlay()~=nil
  end,4,"正式相機看見地基、鷹架與施工狀態牌")
  waitFor(function()
   local stats=probe:Invoke(site)
   return stats.site and stats.site.constructing and stats.site.hiddenParts>0
  end,2,"尚未施工的外牆或屋頂尚未揭露")
  local seen={[0]=true}
  local initialHidden=probe:Invoke(site).site.hiddenParts
  waitFor(function()
   local state=probe:Invoke(site).site
   if state then seen[state.stage]=true end
   return state and state.progress>=.12
  end,30,"村民到場後進入鷹架階段")
  local object,billboard=actualOverlay()
  check(object and billboard:FindFirstChild("StageLabel",true) and string.find(billboard:FindFirstChild("StageLabel",true).Text,"%",1,true),"實際世界狀態牌顯示施工百分比")
  command:FireServer("Stop",{worker})
  waitFor(function() return site:GetAttribute("BuilderCount")==0 and worker:GetAttribute("Order")=="待命" end,3,"正常停止施工")
  waitFor(function() return string.find(probe:Invoke(site).site.label or "","等待村民",1,true)~=nil end,2,"停工牌明確提示等待村民")
  player:SetAttribute("ReducedMotion",true)
  command:FireServer("Order",{worker},site)
  waitFor(function()
   local stats=probe:Invoke(site)
   local state=stats.site
   assert(stats.visibleSites<=stats.maxVisibleSites and stats.completionEffects<=6,"[CONSTRUCTION_VISUAL FAIL] 施工或完工效果超出上限")
   if state then seen[state.stage]=true end
   return state and state.stage==3 and state.hiddenParts<initialHidden
  end,15,"減少動態仍依正式進度揭露外牆與屋頂")
  check(probe:Invoke().visibleSites<=probe:Invoke().maxVisibleSites and probe:Invoke().completionEffects<=6,"施工與完工效果維持數量上限")
  check(seen[1] and seen[2] and seen[3],"正常施工依序經過鷹架、外牆與屋頂階段")
  waitFor(function() return site:GetAttribute("Complete")==true end,10,"房屋真正完工")
  waitFor(function()
   local state=probe:Invoke(site).site
   return state and not state.constructing and not state.overlay and state.parts==0
  end,2,"完工還原外觀並清除鷹架與施工牌")
  for _,part in ipairs(site:GetDescendants()) do
   if part:IsA("BasePart") and part~=root and part.Transparency<1 then check(part.LocalTransparencyModifier==0,"完工零件還原原始本機透明度："..part.Name) end
  end
  check(root.CFrame==original and root.CanCollide and root.CanQuery,"視覺施工未移動或修改權威占地")
  waitFor(function()
   for _,sign in ipairs(workspace.RTSConstructionEffects:GetChildren()) do
    if sign:IsA("BillboardGui") and sign.Name=="ConstructionComplete" and sign.Adornee==root then return true end
   end
   return false
  end,.8,"減少動態仍可看到真正完工提示")
  waitFor(function()
   for _,sign in ipairs(workspace.RTSConstructionEffects:GetChildren()) do if sign:IsA("BillboardGui") and sign.Adornee==root then return false end end
   return true
  end,3,"短暫完工牌到期清理")
  print(string.format("[CONSTRUCTION_VISUAL COMPLETE] %d 項檢查；正式地基、鷹架、牆面、屋頂、停工、完工與減少動態",checks))
  return checks
 end,debug.traceback)
 player:SetAttribute("ReducedMotion",savedMotion)
 if worker and workspace:GetAttribute("MatchPhase")=="Playing" then command:FireServer("Stop",{worker}) end
 if not ok then error(result,0) end
 return result
end
function Tests.Run()
 assert(not Tests.running,"[CONSTRUCTION_VISUAL FAIL] 驗證已在執行")
 Tests.running=true
 local ok,result=xpcall(run,debug.traceback)
 Tests.running=false
 if not ok then error(result,0) end
 return result
end
return Tests
