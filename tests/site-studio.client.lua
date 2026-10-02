-- Test-only LocalScript, mapped only by site-validation.project.json.
-- 以正常大廳指令開單人局，再用正式的 Command 遠端驗證「無人施工的工地會重新派工」：
-- A 施工村民被調走後由其他村民接手完工；B 關閉自動工作時不派工、重新開啟後派工；C 全部村民被玩家指定待命時不派工。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local passed,failed=0,0
local function check(name,ok,detail)
 if ok then passed+=1 else failed+=1 end
 print("[SITE_TEST] "..(ok and "PASS " or "FAIL ")..name..(detail~=nil and (" | "..tostring(detail)) or ""))
end
local function info(text) print("[SITE_TEST] INFO "..text) end
local function waitFor(predicate,seconds)
 local deadline=os.clock()+seconds
 repeat
  if predicate() then return true end
  Run.Heartbeat:Wait()
 until os.clock()>deadline
 return predicate()==true
end
local function main()
 assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30),"初始化逾時")
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 local command=RS.RTSRemotes.Command
 RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message) if type(message)=="string" then info("伺服器通知："..message) end end)
 local unitFolder,buildingFolder=workspace.Units,workspace.Buildings
 local function villagers()
  local list={}
  for _,unit in ipairs(unitFolder:GetChildren()) do
   if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" and (unit:GetAttribute("HP") or 0)>0 then table.insert(list,unit) end
  end
  return list
 end
 local function builders()
  local list={}
  for _,unit in ipairs(villagers()) do if unit:GetAttribute("Order")=="施工" then table.insert(list,unit) end end
  return list
 end
 local function orders()
  local parts={}
  for _,unit in ipairs(villagers()) do table.insert(parts,tostring(unit:GetAttribute("Order"))) end
  return table.concat(parts,",")
 end
 local tc
 assert(waitFor(function()
  for _,building in ipairs(buildingFolder:GetChildren()) do
   if building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")=="TownCenter" then tc=building; return true end
  end
  return false
 end,10),"找不到自己的市鎮中心")
 local center=tc:GetPivot().Position
 center=Vector3.new(center.X,0,center.Z)
 -- 放置一個工地並回傳模型；selection 為空表時由伺服器派最近的村民。
 local function place(kind,offset,selection)
  local before={}
  for _,building in ipairs(buildingFolder:GetChildren()) do before[building]=true end
  command:FireServer("Build",kind,center+offset,selection or {},false)
  local found
  waitFor(function()
   for _,building in ipairs(buildingFolder:GetChildren()) do
    if not before[building] and building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")==kind then found=building; return true end
   end
   return false
  end,6)
  return found
 end
 local function state(site)
  return "complete="..tostring(site:GetAttribute("Complete")).." builders="..tostring(site:GetAttribute("BuilderCount")).." status="..tostring(site:GetAttribute("ConstructionStatus")).." orders="..orders()
 end
 check("開局有 3 位村民",#villagers()==3,#villagers())
 task.wait(4) -- 讓閒置村民先自動去採集。
 info("開局指令："..orders())

 -- A. 農田的施工村民被調去遠處蓋房屋；農田應由其他村民接手完工。
 local farm=place("Farm",Vector3.new(96,0,0))
 check("A 農田工地建立",farm~=nil)
 if farm then
  check("A 伺服器派村民到農田",waitFor(function() return #builders()>0 end,6),orders())
  local first=builders()
  local house=place("House",Vector3.new(-96,0,0),first)
  check("A 農田的施工村民改去蓋 192 studs 外的房屋",house~=nil and #first>0,#first)
  local started=os.clock()
  local done=waitFor(function() return farm:GetAttribute("Complete")==true end,60)
  check("A 農田在施工村民被調走後仍完工",done,string.format("%.1f 秒 | %s",os.clock()-started,state(farm)))
  if house then check("A 房屋也完工",waitFor(function() return house:GetAttribute("Complete")==true end,40),state(house)) end
 end

 -- B. 關閉自動工作：工地沒人時不派工；重新開啟後派工並完工。
 command:FireServer("AutoWork",false)
 waitFor(function() return player:GetAttribute("AutoWork")==false end,5)
 local houseB=place("House",Vector3.new(0,0,96))
 check("B 房屋工地建立",houseB~=nil)
 if houseB then
  waitFor(function() return #builders()>0 end,6)
  local away=builders()
  command:FireServer("Order",away,center+Vector3.new(0,0,-60))
  task.wait(12)
  check("B 自動工作關閉時，無人工地 12 秒內沒有被派工",houseB:GetAttribute("Complete")~=true and #builders()==0,state(houseB))
  command:FireServer("AutoWork",true)
  waitFor(function() return player:GetAttribute("AutoWork")==true end,5)
  check("B 重新開啟自動工作後工地完工",waitFor(function() return houseB:GetAttribute("Complete")==true end,50),state(houseB))
 end

 -- C. 全部村民由玩家指定待命（停止）：無人工地不搶走他們。
 command:FireServer("Stop",villagers())
 task.wait(1)
 local houseC=place("House",Vector3.new(0,0,-96))
 check("C 房屋工地建立",houseC~=nil)
 if houseC then
  waitFor(function() return #builders()>0 end,6)
  local away=builders()
  command:FireServer("Order",away,center+Vector3.new(40,0,60))
  task.wait(1)
  command:FireServer("Stop",villagers())
  task.wait(12)
  check("C 玩家指定待命的村民 12 秒內沒有被抽去施工",houseC:GetAttribute("Complete")~=true and #builders()==0,state(houseC))
 end
 print(string.format("[SITE_TEST] COMPLETE passed=%d failed=%d",passed,failed))
end
local ok,err=pcall(main)
if not ok then print("[SITE_TEST] FAIL 測試中止 | "..tostring(err)) end
