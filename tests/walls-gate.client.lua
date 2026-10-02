-- Test-only LocalScript, mapped only by walls-validation.project.json.
-- Studio CLIENT：以正常大廳指令開一局（1 真人＋1 簡單電腦、豐富資源），用正式的 Build／BuildLine／Order
-- 遠端指令蓋一圈 7×7 的石牆與一座城門，檢查整排放置、扣款、跳過占用格、資源用完即停、城門取代牆段、
-- 己方穿越城門、敵方被擋在外面，以及放置預覽（BuildingController）的自動轉向與整排段數。
-- 唯一的捷徑是伺服器輔助把 Age 設為 2；見 tests/walls-gate.server.lua。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local TAG="[WALLS_GATE] "
local passed,failed=0,0
local function check(condition,message,detail)
 if condition then passed+=1; print(TAG.."PASS "..message..(detail and ("  ("..tostring(detail)..")") or ""))
 else failed+=1; warn(TAG.."FAIL "..message..(detail and ("  ("..tostring(detail)..")") or "")) end
 return condition
end
local function waitFor(predicate,seconds)
 local deadline=os.clock()+seconds
 repeat
  local value=predicate()
  if value then return value end
  task.wait(0.2)
 until os.clock()>deadline
 return nil
end
local ok,problem=pcall(function()
 assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30),"初始化逾時")
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 task.wait(3)
 local Config=require(RS.GameData.GameConfig)
 local Grid=require(RS.Shared.Grid)
 local Building=require(RS.Shared.BuildingController)
 local Focus=require(RS.Shared.CameraFocus)
 local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
 local server=RS:WaitForChild("WallsGateTest",20)
 assert(server,"伺服器測試輔助不存在")
 Config.Map.MapSize=workspace:GetAttribute("MapSize") or Config.Map.MapSize
 local one=Vector2.new(1,1)
 local wallCost=Config.Buildings.Wall.cost.stone
 local gateCost=Config.Buildings.Gate.cost.stone
 local function stone() return player:GetAttribute("stone") or 0 end
 local function mine(kind,folder)
  local result={}
  for _,model in ipairs(workspace[folder or "Units"]:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and (model:GetAttribute("UnitType")==kind or model:GetAttribute("BuildingType")==kind) then table.insert(result,model) end
  end
  return result
 end
 -- 己方建築依格子索引："x:z" -> model。
 local function cellsOf(kind)
  local map,count={},0
  for _,model in ipairs(mine(kind,"Buildings")) do
   local root=model:FindFirstChild("Footprint")
   if root then
    local _,x,z=Grid.snap(root.Position,one)
    map[x..":"..z]=model; count+=1
   end
  end
  return map,count
 end
 local function at(x,z) return Grid.cellPosition(x,z,one) end
 local function settle() task.wait(0.8) end

 local info=server:InvokeServer("setup")
 check(info and info.age==2 and info.ai~=nil and info.probe,"測試前置：封建時代、電腦陣營與探針",info and ("ai="..tostring(info.ai)))
 local home=player:GetAttribute("HomePosition")
 local inward=Vector3.new(home.X>0 and -1 or 1,0,home.Z>0 and -1 or 1).Unit
 local center,cx,cz=Grid.snap(home+inward*72,one)
 -- 額外的測試牆段放在圍牆旁、靠主城這一側的空地（mx(k)：往主城的 X 方向 k 格）。
 local side=home.X>center.X and 1 or -1
 local function mx(k) return cx+side*k end
 local zside=center.Z>home.Z and 1 or -1
 Focus.Request(player,center)
 print(TAG.."INFO 圍牆中心 "..tostring(center).." 格 "..cx..","..cz.." 主城 "..tostring(home).." 石材 "..stone())
 local villagers=mine("villager")
 check(#villagers>=3,"開局村民",#villagers)

 -- 1. 被拒絕的請求不扣款。
 local before=stone()
 local _,wallsBefore=cellsOf("Wall")
 command:FireServer("BuildLine","House",at(mx(6),cz-6),at(mx(9),cz-6),{})
 command:FireServer("BuildLine","Wall",Vector3.new(0/0,0,0),at(mx(9),cz-6),{})
 command:FireServer("BuildLine","Wall",at(mx(6),cz-6),"bad",{})
 command:FireServer("Build","Gate",home,{},false)
 settle()
 local _,wallsAfter=cellsOf("Wall")
 check(stone()==before and wallsAfter==wallsBefore and #mine("Gate","Buildings")==0,"非城牆整排、無效座標、壓在主城上的城門都被拒絕且不扣款",stone())

 -- 2. 斜向整排：空選取由伺服器派村民；牆段邊相接。
 before=stone()
 command:FireServer("BuildLine","Wall",at(mx(6),cz-1),at(mx(9),cz+1),{})
 settle()
 local walls,count=cellsOf("Wall")
 local diagonal={{6,-1},{7,-1},{7,0},{8,0},{8,1},{9,1}}
 local found=0
 for _,cell in ipairs(diagonal) do if walls[mx(cell[1])..":"..(cz+cell[2])] then found+=1 end end
 check(count==6 and before-stone()==6*wallCost,"斜向拖曳建立 6 段並扣 6 段石材",count.." 段，扣 "..(before-stone()))
 check(found==6 and count==6,"斜向牆段沿拖曳方向排成邊相接的階梯",found.."/6 符合預期格")
 do
  local connected=true
  local list={}
  for key in pairs(walls) do local x,z=string.match(key,"(-?%d+):(-?%d+)"); table.insert(list,{tonumber(x),tonumber(z)}) end
  for _,a in ipairs(list) do
   local neighbours=0
   for _,b in ipairs(list) do if math.abs(a[1]-b[1])+math.abs(a[2]-b[2])==1 then neighbours+=1 end end
   if neighbours==0 then connected=false end
  end
  check(connected,"每一段都與相鄰牆段共用一邊（沒有只靠角相接的縫）")
 end
 local busy=0
 for _,unit in ipairs(villagers) do if unit:GetAttribute("OrderKind")=="build" then busy+=1 end end
 check(busy>=1,"空選取時伺服器派村民施工",busy.." 位")

 -- 3. 四排圍成 7×7：轉角已被前一排占用，應跳過且不重複扣款。
 local lines={
  {cx-3,cz-3,cx+3,cz-3,7},{cx+3,cz-3,cx+3,cz+3,6},{cx+3,cz+3,cx-3,cz+3,6},{cx-3,cz+3,cx-3,cz-3,5},
 }
 for index,line in ipairs(lines) do
  before=stone()
  local _,had=cellsOf("Wall")
  local now,tries=had,0
  -- 有單位站在格子上時該格會被跳過（正式規則）；同一排重送，已建立的牆段不會重複扣款。
  repeat
   tries+=1
   command:FireServer("BuildLine","Wall",at(line[1],line[2]),at(line[3],line[4]),villagers)
   settle()
   _,now=cellsOf("Wall")
   if now-had<line[5] then task.wait(2) end
  until now-had>=line[5] or tries>=8
  check(now-had==line[5] and before-stone()==line[5]*wallCost,"第 "..index.." 排：建立 "..line[5].." 段、跳過已占用的格子且不重複扣款",(now-had).." 段，扣 "..(before-stone()).."，送出 "..tries.." 次")
 end
 walls=cellsOf("Wall")
 local ring=0
 for x=cx-3,cx+3 do for z=cz-3,cz+3 do
  if (math.abs(x-cx)==3 or math.abs(z-cz)==3) and walls[x..":"..z] then ring+=1 end
 end end
 check(ring==24,"7×7 外圈 24 格都有牆段",ring)

 -- 4. 城門蓋在自己的石牆上（背向主城的一側、轉 90 度）。
 before=stone()
 local gx=cx-side*3 -- 背向主城的那一側，村民不會經過
 local gatePoint=at(gx,cz)
 local gates,gateTries={},0
 repeat
  gateTries+=1
  command:FireServer("Build","Gate",gatePoint,villagers,true)
  settle()
  gates=mine("Gate","Buildings")
  if #gates==0 then task.wait(2) end
 until #gates>0 or gateTries>=8
 walls=cellsOf("Wall")
 local gate=gates[1]
 local replaced=not walls[gx..":"..(cz-1)] and not walls[gx..":"..cz] and not walls[gx..":"..(cz+1)]
 check(#gates==1 and replaced and before-stone()==gateCost,"城門取代三段己方石牆並只扣城門的石材",#gates.." 座，扣 "..(before-stone()).."，送出 "..gateTries.." 次")
 local gateRoot=gate and gate:WaitForChild("Footprint",5)
 check(gateRoot~=nil and math.abs(gateRoot.Size.X-8)<0.01 and math.abs(gateRoot.Size.Z-24)<0.01 and gate:GetAttribute("Rotated")==true,
  "旋轉後的城門占地為 1×3 格（沿 Z）",gateRoot and tostring(gateRoot.Size))
 check(gateRoot~=nil and (gateRoot.Position-Vector3.new(gatePoint.X,gateRoot.Position.Y,gatePoint.Z)).Magnitude<0.01,"城門對齊牆段格線")
 if gate then
  local _,bounds=gate:GetBoundingBox()
  check(bounds.Z>bounds.X*2,"城門模型也跟著轉向（長邊沿 Z）",tostring(bounds))
 end
 check(gateRoot~=nil and gateRoot.CanCollide==true,"施工中的城門仍然擋路")

 -- 5. 放置預覽：自動轉向、可蓋在自己的牆上、整排段數受資源限制。
 do
  local began,message=Building:Begin("Gate",{})
  check(began,"預覽：未選取時可開始放置城門",message)
  if began then
   -- 這一側朝向主城，村民可能正好站在格子上（占地有單位即不可放置）；最多等 12 秒讓他們走開。
   local tries=0
   repeat
    tries+=1
    Building:Cancel(); Building:Begin("Gate",{})
    Building:Update(at(cx+side*3,cz))
    if not Building.valid then task.wait(1) end
   until Building.valid or tries>=12
   check(Building.rotated==true and Building.valid==true,"預覽：另一側牆上自動轉 90 度且可放置",tostring(Building.rotated).." / "..tostring(Building.reason))
   Building:Cancel(); Building:Begin("Gate",{})
   Building:Update(at(cx,cz-3))
   check(Building.rotated==false and Building.valid==true,"預覽：北側牆上維持橫向且可放置",tostring(Building.rotated).." / "..tostring(Building.reason))
   check(Building:Rotate() and Building.rotated==true,"預覽：R 旋轉切換方向")
   Building:Update(home)
   check(Building.valid==false,"預覽：壓在主城上顯示不可放置",Building.reason)
   Building:Cancel()
  end
  began=Building:Begin("Wall",{})
  if check(began and Building:IsLine(),"預覽：石牆為整排放置模式") then
   Building:StartLine(at(mx(6),cz+6*zside))
   Building:Update(at(mx(25),cz+6*zside))
   local affordable=math.floor(stone()/wallCost)
   check(Building.lineStart~=nil and Building.lineCount==math.min(20,affordable) and Building.valid==true,"預覽：20 格的拖曳只標出買得起的段數",Building.lineCount.." / 買得起 "..affordable)
   Building:Cancel()
   check(workspace:FindFirstChild("BuildingPreviewLine")==nil and workspace:FindFirstChild("BuildingPreview")==nil,"預覽：取消後清除整排預覽")
  end
 end

 -- 6. 等待外圈與城門完工。
 local function ringDone()
  local map=cellsOf("Wall")
  for x=cx-3,cx+3 do for z=cz-3,cz+3 do
   if math.abs(x-cx)==3 or math.abs(z-cz)==3 then
    local model=map[x..":"..z]
    if model and model:GetAttribute("Complete")~=true then return false end
    if not model and not (x==gx and math.abs(z-cz)<=1) then return false end
   end
  end end
  return gate~=nil and gate:GetAttribute("Complete")==true
 end
 local started=os.clock()
 local finished=waitFor(ringDone,420)
 check(finished,"村民依序完成整圈牆段與城門",math.floor(os.clock()-started).." 秒")
 if not finished then error("外圈未完工，後續通行測試無法進行") end
 task.wait(1)
 local facts=server:InvokeServer("gate",gate)
 check(facts and facts.canCollide==false and facts.label=="RTSGate"..player.UserId,"完工後城門占地不再碰撞並帶導航標籤",facts and (tostring(facts.canCollide).." / "..tostring(facts.label)))

 -- 7. 導航：己方可穿過城門進入圈內；城門標籤成本無限大時無路可走。
 local outside=at(cx-side*7,cz)
 local nav=server:InvokeServer("nav",outside,center)
 check(nav and nav.friendly=="Success","導航：己方從城外到圈內有路",nav and (nav.friendly.." "..nav.friendlyWaypoints.." 點"))
 check(nav and nav.hostile~="Success","導航：敵方（城門標籤不可通行）沒有路",nav and (nav.hostile.." "..nav.hostileWaypoints.." 點"))

 -- 8. 己方單位穿過城門。
 local interior=20
 local function inside(position,margin)
  return position~=nil and math.abs(position.X-center.X)<margin and math.abs(position.Z-center.Z)<margin
 end
 local scout=mine("scout")[1]
 assert(scout,"找不到開局的斥候騎兵")
 local opened=false
 local connection=gate:GetAttributeChangedSignal("GateOpen"):Connect(function() if gate:GetAttribute("GateOpen")==true then opened=true end end)
 if gate:GetAttribute("GateOpen")==true then opened=true end
 local scoutStart=server:InvokeServer("pos",scout)
 check(not inside(scoutStart,28),"斥候一開始在圈外",tostring(scoutStart))
 command:FireServer("Order",{scout},center)
 started=os.clock()
 local arrived=waitFor(function() return inside(server:InvokeServer("pos",scout),interior) end,60)
 check(arrived,"己方斥候穿過城門進入圈內",math.floor(os.clock()-started).." 秒，位置 "..tostring(server:InvokeServer("pos",scout)))
 check(opened,"己方單位靠近時閘門升起（GateOpen）")

 -- 9. 敵方單位被擋在城門外。
 local enemy,ordered=server:InvokeServer("enemy",outside,scout)
 check(enemy~=nil and ordered==true,"生成敵方步兵並下令攻擊圈內的斥候")
 if enemy then
  local entered,closest=false,math.huge
  local deadline=os.clock()+35
  while os.clock()<deadline do
   local position=server:InvokeServer("pos",enemy)
   if not position then break end
   -- 占地外緣離中心 28，步兵半徑 2：中心進到 29.5 以內代表身體已經壓進牆或城門的占地。
   if inside(position,29.5) then entered=true end
   closest=math.min(closest,math.max(math.abs(position.X-center.X),math.abs(position.Z-center.Z)))
   task.wait(0.25)
  end
  check(not entered,"敵方步兵 35 秒內沒有穿過城門或城牆",string.format("最接近時離中心 %.1f studs（合法下限約 29.9）",closest))
  check(closest<60,"敵方步兵確實走近了城門（不是站在原地）",string.format("%.1f",closest))
  server:InvokeServer("remove",enemy)
 end
 connection:Disconnect()

 -- 10. 資源用完即停。
 before=stone()
 local _,had=cellsOf("Wall")
 local expected=math.floor(before/wallCost)
 command:FireServer("BuildLine","Wall",at(mx(6),cz+6*zside),at(mx(25),cz+6*zside),{})
 settle()
 local _,now=cellsOf("Wall")
 check(expected<20 and now-had==expected and stone()==before-expected*wallCost,"20 格的拖曳只建到石材用完",(now-had).." 段，剩 "..stone())
 before=stone()
 command:FireServer("BuildLine","Wall",at(mx(6),cz+8*zside),at(mx(10),cz+8*zside),{})
 settle()
 local _,after=cellsOf("Wall")
 check(after==now and stone()==before,"石材不足一段時整排被拒絕且不扣款")
end)
if not ok then failed+=1; warn(TAG.."FAIL 測試中止："..tostring(problem)) end
print(TAG..(failed==0 and "COMPLETE" or "INCOMPLETE").." passed="..passed.." failed="..failed)
