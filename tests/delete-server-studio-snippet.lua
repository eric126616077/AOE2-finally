-- Paste in Studio CLIENT Command Bar after the other fresh-sandbox checks.
-- This only changes the ephemeral test match: stops own units, spends one
-- House's cost, removes that site and one villager using validated commands.
task.spawn(function()
 local RS=game:GetService("ReplicatedStorage")
 local player=game.Players.LocalPlayer
 assert(game:GetService("RunService"):IsStudio() and player,"Studio client only")
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true,"Fresh solo sandbox required")
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local command=RS.RTSRemotes.Command
 local generation=workspace:GetAttribute("MatchGeneration")
 local checks,errors=0,0
 local deadline=os.clock()+25
 local connection=RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message,cue)
  if cue=="Error" and type(message)=="string" and string.find(message,"無法拆除",1,true) then errors+=1 end
 end)
 local function check(value,message)
  assert(value,"[DELETE_SERVER FAIL] "..message)
  checks+=1; print("[DELETE_SERVER PASS] "..message)
 end
 local function waitFor(predicate,message)
  local untilTime=math.min(deadline,os.clock()+5)
  repeat if predicate() then return end; assert(os.clock()<untilTime,"[DELETE_SERVER FAIL] "..message); task.wait(.03) until false
 end
 local ok,failure=xpcall(function()
  local own,worker={},nil
  for _,unit in ipairs(workspace.Units:GetChildren()) do
   if unit:GetAttribute("RTSManaged")==true and unit:GetAttribute("OwnerId")==player.UserId then
    table.insert(own,unit)
    if not worker and unit:GetAttribute("UnitType")=="villager" then worker=unit end
   end
  end
  check(worker and #own>=2,"己方存活村民與其他單位存在")
  command:FireServer("Stop",own)
  waitFor(function() for _,unit in ipairs(own) do if unit.Parent and unit:GetAttribute("Order")~="待命" then return false end end; return true end,"己方單位停止")
  local beforeHP=worker:GetAttribute("HP")
  local balances={}
  for _,key in ipairs({"food","wood","gold","stone"}) do balances[key]=player:GetAttribute(key) end
  local function rejected(selection,version,message)
   local before=errors
   command:FireServer("Delete",selection,version)
   waitFor(function() return errors>before end,message.." 未收到拒絕")
   check(worker.Parent==workspace.Units and worker:GetAttribute("HP")==beforeHP,message.." 整批拒絕且不刪己方村民")
   for key,balance in pairs(balances) do check(player:GetAttribute(key)==balance,message.." 不改 "..key) end
  end
  rejected({worker},generation-1,"舊對局 generation")
  rejected({worker,worker},generation,"重複模型")
  rejected({worker,workspace.Resources:GetChildren()[1]},generation,"含中立資源的混合選取")
  local data=Config.Buildings.House
  check((player:GetAttribute("wood") or 0)>=data.cost.wood,"一棟測試房屋所需木材足夠")
  local exclusions={workspace.AOE2_Ground}
  local scenery=workspace:FindFirstChild("RTSScenery")
  if scenery then table.insert(exclusions,scenery) end
  local params=OverlapParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances=exclusions
  local size=Vector3.new(data.size.X*Config.Map.GridSize-.2,data.height,data.size.Y*Config.Map.GridSize-.2)
  local location
  Config.Map.MapSize=workspace:GetAttribute("MapSize") or Config.Map.MapSize
  for radius=40,128,8 do
   for index=0,31 do
    local angle=index*math.pi/16
    local point=Grid.snap(worker.PrimaryPart.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
    if Grid.inBounds(point,data.size) and #workspace:GetPartBoundsInBox(CFrame.new(point+Vector3.new(0,data.height/2,0)),size,params)==0 then location=point; break end
   end
   if location then break end
  end
  check(location~=nil,"找到正式無占用且在地圖內的房屋位置")
  local existing={}; for _,model in ipairs(workspace.Buildings:GetChildren()) do existing[model]=true end
  local wood=player:GetAttribute("wood")
  command:FireServer("Build","House",location,{worker})
  local site
  waitFor(function()
   for _,model in ipairs(workspace.Buildings:GetChildren()) do
    if not existing[model] and model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType")=="House" then site=model; return true end
   end
   return false
  end,"伺服器房屋工地未建立")
  check(site:GetAttribute("Complete")==false and player:GetAttribute("wood")==wood-data.cost.wood,"正常工地扣款一次，尚未完工")
  command:FireServer("Delete",{site},generation)
  waitFor(function() return site.Parent==nil end,"己方工地未被正常刪除")
  check(player:GetAttribute("wood")==wood-data.cost.wood,"取消工地不退款")
  local population=player:GetAttribute("Population")
  command:FireServer("Delete",{worker},generation)
  waitFor(function() return worker.Parent==nil and player:GetAttribute("Population")==population-1 end,"單位未刪除或人口未更新")
  check(true,"正常刪除村民清理單位與人口")
  check(workspace:GetAttribute("MatchGeneration")==generation and workspace:GetAttribute("MatchPhase")=="Playing","其餘沙盒對局持續運作")
  print("[DELETE_SERVER COMPLETE] "..checks.." 項；單人無模型，未驗真正敵方／跨客戶端")
 end,debug.traceback)
 connection:Disconnect()
 if not ok then error(failure,0) end
end)
