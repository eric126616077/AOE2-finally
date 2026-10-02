-- Run explicitly from the CLIENT Command Bar in a fresh local Play session.
-- Exercises real lobby commands, gathering and restarts; changes the test match.
task.spawn(function()
 local RS=game:GetService("ReplicatedStorage")
 local player=game.Players.LocalPlayer
 assert(game:GetService("RunService"):IsStudio() and player,"僅限 Studio CLIENT Play")
 local command=RS.RTSRemotes.Command
 local seeds,fingerprints={},{}
 local function waitFor(predicate,seconds,message)
  local deadline=os.clock()+seconds
  repeat if predicate() then return end; task.wait(.1) until os.clock()>deadline
  error("[RESOURCE_LAYOUT FAIL] "..message)
 end
 local function fingerprint()
  local items={}
  for _,model in ipairs(workspace.Resources:GetChildren()) do
   if model:GetAttribute("RTSManagedResource")==true then
    local p=model.PrimaryPart.Position
    table.insert(items,model.Name..":"..string.format("%.3f:%.3f",p.X,p.Z))
   end
  end
  table.sort(items)
  return table.concat(items,"|")
 end
 for round,sizeName in ipairs({"Small","Small","Medium","Large"}) do
  require(RS.Shared.LobbyTests).Start({expectedPlayers=1,size=sizeName,aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" end,20,"正常大廳開局")
  local census=require(RS.Shared.MapTests).Run()
  local seed=workspace:GetAttribute("MapSeed")
  assert(type(seed)=="number" and not seeds[seed],"[RESOURCE_LAYOUT FAIL] 新局種子重複")
  seeds[seed]=true
  local mapFingerprint=fingerprint()
  if fingerprints[sizeName] then assert(fingerprints[sizeName]~=mapFingerprint,"[RESOURCE_LAYOUT FAIL] 同尺寸重開仍為相同資源位置") end
  fingerprints[sizeName]=mapFingerprint
  print("[RESOURCE_LAYOUT ROUND]",round,sizeName,seed,census.nodes,census.clusters)
  if round==1 then
   local worker
   for _,unit in ipairs(workspace.Units:GetChildren()) do
    if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then worker=unit; break end
   end
   assert(worker,"[RESOURCE_LAYOUT FAIL] 開局村民未複製")
   for _,case in ipairs({{kind="food"},{kind="wood"},{kind="gold"},{kind="stone"},{kind="wood",interior=true}}) do
    local kind=case.kind
    local nearest,best=nil,math.huge
    local home=player:GetAttribute("HomePosition")
    for _,node in ipairs(workspace.Resources:GetChildren()) do
     if node:GetAttribute("ResourceType")==kind and node:GetAttribute("ResourceZone")=="Opening" and node:GetAttribute("ResourceSpawnSlot")==player:GetAttribute("FactionSlot") then
      local eligible=true
      if case.interior then
       local neighbors=0
       for _,other in ipairs(workspace.Resources:GetChildren()) do
        if other~=node and other:GetAttribute("ResourceClusterId")==node:GetAttribute("ResourceClusterId") and
         (other.PrimaryPart.Position-node.PrimaryPart.Position).Magnitude<14 then neighbors+=1 end
       end
       eligible=neighbors>=4
      end
      local distance=(node.PrimaryPart.Position-home).Magnitude
      if eligible and distance<best then nearest,best=node,distance end
     end
    end
    assert(nearest,"[RESOURCE_LAYOUT FAIL] 缺少開局資源 "..kind)
    local amount,stock=nearest:GetAttribute("Amount"),player:GetAttribute(kind)
    command:FireServer("Order",{worker},nearest)
    waitFor(function() return worker:GetAttribute("CarryType")==kind and (worker:GetAttribute("Carrying") or 0)>0 end,80,"村民抵達並採集 "..kind)
    waitFor(function() return player:GetAttribute(kind)>stock end,60,"實際交回 "..kind)
    assert(nearest:GetAttribute("Amount")<amount,"[RESOURCE_LAYOUT FAIL] 資源沒有真正減少")
    command:FireServer("Stop",{worker})
    waitFor(function() return worker:GetAttribute("Order")=="待命" end,5,"村民正常停止")
    print("[RESOURCE_LAYOUT GATHER PASS]",case.interior and "林內木材" or kind,stock,player:GetAttribute(kind),amount,nearest:GetAttribute("Amount"))
   end
  end
  command:FireServer("Surrender")
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,10,"正常投降")
  command:FireServer("RestartMatch")
  waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" end,15,"正常返回大廳")
  waitFor(function()
   for _,model in ipairs(workspace.Resources:GetChildren()) do if model:GetAttribute("RTSManagedResource")==true then return false end end
   return true
  end,8,"重開清除本局生成資源")
 end
 print("[RESOURCE_LAYOUT COMPLETE] 四局密集地圖、同尺寸隨機重開、四資源與林內木材真採集交貨、清理完成")
end)
