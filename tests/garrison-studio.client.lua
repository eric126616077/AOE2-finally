-- Test-only LocalScript, mapped only by garrison-validation.project.json.
-- 以正常大廳指令開一局（1 真人＋1 簡單電腦），再用正式的 Command 遠端測試駐紮：
-- 右鍵駐紮、強制駐紮、禁止兵種、多箭傷害、駐紮中回復、全部離開、容量上限、拆除建築放出駐軍。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local passed,failed=0,0
local function check(name,ok,detail)
 if ok then passed+=1 else failed+=1 end
 print("[GARRISON_TEST] "..(ok and "PASS " or "FAIL ")..name..(detail~=nil and (" | "..tostring(detail)) or ""))
end
local function info(text) print("[GARRISON_TEST] INFO "..text) end
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
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 local command=RS.RTSRemotes.Command
 local helper=RS:WaitForChild("GarrisonTestHelper",20)
 assert(helper,"GarrisonTestHelper 不存在")
 command:FireServer("AutoWork",false)
 -- 伺服器給玩家的文字通知（例如被拒絕的原因）一併記錄。
 RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message) if type(message)=="string" then info("伺服器通知："..message) end end)
 local unitFolder,buildingFolder=workspace.Units,workspace.Buildings
 local function mine()
  local list={}
  for _,unit in ipairs(unitFolder:GetChildren()) do
   -- 開局的綿羊（UnitClass=herd，人口 0）不能駐紮，也不是這組測試的對象。
   if unit:GetAttribute("OwnerId")==player.UserId and (unit:GetAttribute("HP") or 0)>0 and unit:GetAttribute("UnitClass")~="herd" then table.insert(list,unit) end
  end
  return list
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
 require(RS.Shared.CameraFocus).Request(player,center)
 local sequence=0
 local function spawn(side,kind,angle,distance,origin)
  sequence+=1
  local tag="garrison-"..sequence
  local position=(origin or center)+Vector3.new(math.cos(angle)*distance,0,math.sin(angle)*distance)
  assert(helper:InvokeServer("spawn",side,kind,position,tag),"生成 "..kind.." 失敗")
  local found
  assert(waitFor(function()
   for _,unit in ipairs(unitFolder:GetChildren()) do if unit:GetAttribute("TestTag")==tag then found=unit; return true end end
   return false
  end,8),"生成的 "..kind.." 沒有複製到客戶端")
  local blockedBy=found:GetAttribute("TestSpawnBlockedBy")
  if blockedBy then info("生成位置被擋住，已改到旁邊的空位："..kind.." ← "..blockedBy) end
  return found
 end
 local function garrison() return tc:GetAttribute("Garrison") or 0 end

 -- 1. 屬性與初始狀態
 check("市鎮中心容量 15、初始駐軍 0",tc:GetAttribute("GarrisonCapacity")==15 and garrison()==0,
  "capacity="..tostring(tc:GetAttribute("GarrisonCapacity")).." garrison="..tostring(tc:GetAttribute("Garrison")))

 -- 2. 右鍵（Order）讓閒置村民駐紮
 task.wait(0.5)
 local villagers=mine()
 command:FireServer("Stop",villagers)
 task.wait(0.4)
 -- 開局單位含一位斥候騎兵：只有村民會增加箭數。
 local carrying,villagerCount=0,0
 for _,unit in ipairs(villagers) do
  carrying+=unit:GetAttribute("Carrying") or 0
  if unit:GetAttribute("UnitType")=="villager" then villagerCount+=1 end
 end
 local populationBefore=player:GetAttribute("Population")
 -- 一般右鍵（Order）不會駐紮：村民與軍事單位都一樣，只有專用的 Garrison 指令才會。
 command:FireServer("Order",villagers,tc)
 task.wait(2.5)
 local orderKinds,garrisonOrders={},0
 for _,unit in ipairs(villagers) do
  table.insert(orderKinds,tostring(unit:GetAttribute("Order")))
  if unit:GetAttribute("OrderKind")=="garrison" then garrisonOrders+=1 end
 end
 info("開局單位 "..#villagers.." 個（村民 "..villagerCount.."），攜帶 "..carrying.."，右鍵後狀態："..table.concat(orderKinds,","))
 check("右鍵市鎮中心不會駐紮（村民與斥候都留在外面）",garrison()==0 and #mine()==#villagers and garrisonOrders==0,
  "garrison="..garrison().." outside="..#mine().." garrisonOrders="..garrisonOrders)
 command:FireServer("Garrison",villagers,tc)
 check("駐紮指令：開局單位走進建築",waitFor(function() return garrison()==#villagers end,30),"garrison="..garrison().." expected="..#villagers)
 check("駐紮後單位模型消失",waitFor(function() return #mine()==0 end,3),"remaining="..#mine())
 check("駐軍仍計入人口",player:GetAttribute("Population")==populationBefore,"before="..tostring(populationBefore).." after="..tostring(player:GetAttribute("Population")))
 check("每位村民多射一支箭（斥候騎兵不加箭）",tc:GetAttribute("GarrisonArrows")==villagerCount,"arrows="..tostring(tc:GetAttribute("GarrisonArrows")))

 -- 3. 介面：選取建築後顯示駐軍與「全部離開」
 local selection=player.PlayerGui:FindFirstChild("RTSSelectionProbe",true)
 if selection then
  selection:Invoke({tc})
  local expected="駐軍 "..#villagers.." / 15"
  local shown=waitFor(function()
   for _,item in ipairs(player.PlayerGui:GetDescendants()) do
    if item:IsA("TextLabel") and item.Visible and string.find(item.Text,expected,1,true) then return true end
   end
   return false
  end,3)
  check("面板顯示「"..expected.."」",shown)
  check("面板出現「全部離開」指令",waitFor(function() return player.PlayerGui:FindFirstChild("Command_Ungarrison",true)~=nil end,3))
 else check("RTSSelectionProbe 存在",false) end

 -- 4. 強制駐紮（Garrison 指令）：弓箭手、步兵、騎士可進；攻城衝車被拒絕
 local archers={spawn("human","archer",0.2,34),spawn("human","archer",0.5,34)}
 local infantry={spawn("human","infantry",0.8,34),spawn("human","infantry",1.1,34)}
 local knight=spawn("human","cavalry",1.4,36)
 local ram=spawn("human","ram",1.8,38)
 local group={archers[1],archers[2],infantry[1],infantry[2],knight,ram}
 populationBefore=player:GetAttribute("Population")
 command:FireServer("Garrison",group,tc)
 local expectedInside=#villagers+5
 check("弓箭手、步兵、騎士進入市鎮中心",waitFor(function() return garrison()==expectedInside end,30),"garrison="..garrison().." expected="..expectedInside)
 check("攻城衝車不能駐紮",ram.Parent==unitFolder and ram:GetAttribute("OrderKind")~="garrison","order="..tostring(ram:GetAttribute("OrderKind")))
 local expectedArrows=villagerCount+2+1
 check("箭數＝村民＋弓箭手＋步兵每兩位一支",tc:GetAttribute("GarrisonArrows")==expectedArrows,"arrows="..tostring(tc:GetAttribute("GarrisonArrows")).." expected="..expectedArrows)
 check("混合駐軍仍計入人口",player:GetAttribute("Population")==populationBefore,"before="..tostring(populationBefore).." after="..tostring(player:GetAttribute("Population")))
 helper:InvokeServer("remove",ram)

 -- 5. 多箭傷害：敵方騎士進入射程，每次齊射的生命減少量＝箭數 ×（攻擊 − 護甲）
 local enemy=spawn("ai","cavalry",3.6,44)
 local perArrow=math.max(1,(tc:GetAttribute("Attack") or 0)-(enemy:GetAttribute("Armor") or 0))
 local volleys,matched,arrowParts={},false,0
 local connection
 connection=tc:GetAttributeChangedSignal("LastAttack"):Connect(function()
  task.defer(function()
   local before=enemy:GetAttribute("HP")
   local volley=tc:GetAttribute("AttackVolley")
   local flight=tc:GetAttribute("AttackFlight") or 0.3
   task.wait(0.05)
   local parts=0
   for _,item in ipairs(workspace:GetDescendants()) do if item.Name=="ArrowEffect" then parts+=1 end end
   arrowParts=math.max(arrowParts,parts)
   task.wait(flight+0.35)
   local after=enemy.Parent and enemy:GetAttribute("HP") or 0
   table.insert(volleys,string.format("volley=%s hp %s->%s",tostring(volley),tostring(before),tostring(after)))
   if volley==expectedArrows+1 and before and (before-after==volley*perArrow or (after==0 and before<=volley*perArrow)) then matched=true end
  end)
 end)
 waitFor(function() return matched or #volleys>=4 or not enemy.Parent end,25)
 task.wait(1)
 connection:Disconnect()
 info("每箭傷害 "..perArrow.."；"..table.concat(volleys,"; ").."；畫面箭矢最多 "..arrowParts.." 支")
 check("齊射箭數 "..(expectedArrows+1).." 且傷害逐箭結算",matched)
 check("客戶端畫出多支箭",arrowParts>=expectedArrows+1,"arrowParts="..arrowParts)
 if enemy.Parent then helper:InvokeServer("remove",enemy) end

 -- 6. 駐紮中回復生命
 local wounded=spawn("human","infantry",2.2,34)
 assert(helper:InvokeServer("setHP",wounded,20),"設定生命失敗")
 command:FireServer("Garrison",{wounded},tc)
 expectedInside+=1
 check("受傷步兵駐紮",waitFor(function() return garrison()==expectedInside end,20),"garrison="..garrison())
 task.wait(6)

 -- 7. 全部離開
 populationBefore=player:GetAttribute("Population")
 command:FireServer("Ungarrison",tc)
 check("全部離開後駐軍歸零",waitFor(function() return garrison()==0 end,5),"garrison="..garrison())
 check("離開的單位數量正確",waitFor(function() return #mine()==expectedInside end,5),"units="..#mine().." expected="..expectedInside)
 check("離開後人口不變",player:GetAttribute("Population")==populationBefore,"before="..tostring(populationBefore).." after="..tostring(player:GetAttribute("Population")))
 local half=tc.PrimaryPart and tc.PrimaryPart.Size/2 or Vector3.new(16,0,16)
 local insideFootprint,kinds,healed,minimumGap=0,{},nil,math.huge
 local outside=mine()
 for index,unit in ipairs(outside) do
  local p=unit:GetPivot().Position
  if math.abs(p.X-center.X)<half.X and math.abs(p.Z-center.Z)<half.Z then insideFootprint+=1 end
  local kind=unit:GetAttribute("UnitType")
  kinds[kind]=(kinds[kind] or 0)+1
  if kind=="infantry" and (unit:GetAttribute("HP") or 0)<(unit:GetAttribute("MaxHP") or 0) then healed=unit:GetAttribute("HP") end
  for other=index+1,#outside do
   local q=outside[other]:GetPivot().Position
   minimumGap=math.min(minimumGap,(Vector3.new(p.X,0,p.Z)-Vector3.new(q.X,0,q.Z)).Magnitude)
  end
 end
 check("離開的單位都在建築占地外",insideFootprint==0,"insideFootprint="..insideFootprint)
 check("離開的單位彼此不重疊",minimumGap>=3.5,"minimumGap="..string.format("%.2f",minimumGap))
 check("兵種保留（村民／斥候／弓箭手／步兵／騎士）",kinds.villager==villagerCount and (kinds.scout or 0)==#villagers-villagerCount and kinds.archer==2 and kinds.infantry==3 and kinds.cavalry==1,
  string.format("villager=%s scout=%s archer=%s infantry=%s cavalry=%s",tostring(kinds.villager),tostring(kinds.scout),tostring(kinds.archer),tostring(kinds.infantry),tostring(kinds.cavalry)))
 check("受傷步兵在建築內回復生命（20 → 約 25）",healed~=nil and healed>=23 and healed<=30,"hp="..tostring(healed))

 -- 8. 容量上限：16 個單位只進得去 15 個
 command:FireServer("AutoWork",false)
 while #mine()<16 do spawn("human","infantry",2.6+#mine()*0.22,36) end
 local everyone=mine()
 populationBefore=player:GetAttribute("Population")
 command:FireServer("Garrison",everyone,tc)
 check("駐軍達到容量 15",waitFor(function() return garrison()==15 end,45),"garrison="..garrison())
 task.wait(4)
 local leftover=mine()
 check("第 16 個單位留在外面並停止",garrison()==15 and #leftover==1 and leftover[1]:GetAttribute("OrderKind")==nil,
  "garrison="..garrison().." outside="..#leftover.." order="..tostring(leftover[1] and leftover[1]:GetAttribute("OrderKind")))
 check("滿員時箭數在 1 到上限 10 之間",(tc:GetAttribute("GarrisonArrows") or 0)>=1 and tc:GetAttribute("GarrisonArrows")<=10,
  "arrows="..tostring(tc:GetAttribute("GarrisonArrows")))
 check("滿員時人口不變",player:GetAttribute("Population")==populationBefore,"before="..tostring(populationBefore).." after="..tostring(player:GetAttribute("Population")))

 -- 9. 拆除建築：駐軍出現在原占地
 command:FireServer("Delete",{tc},workspace:GetAttribute("MatchGeneration"))
 check("市鎮中心已拆除",waitFor(function() return tc.Parent==nil end,5))
 check("駐軍全數出現",waitFor(function() return #mine()==16 end,5),"units="..#mine())
 local released=mine()
 local near,gap=0,math.huge
 for index,unit in ipairs(released) do
  local p=unit:GetPivot().Position
  if math.abs(p.X-center.X)<=half.X+40 and math.abs(p.Z-center.Z)<=half.Z+40 then near+=1 end
  for other=index+1,#released do
   local q=released[other]:GetPivot().Position
   gap=math.min(gap,(Vector3.new(p.X,0,p.Z)-Vector3.new(q.X,0,q.Z)).Magnitude)
  end
 end
 check("放出的駐軍在原建築位置附近",near==16,"near="..near)
 check("放出的駐軍彼此不重疊",gap>=3.5,"minimumGap="..string.format("%.2f",gap))
 check("拆除後單位數與人口一致",player:GetAttribute("Population")==16,"population="..tostring(player:GetAttribute("Population")))
 check("拆除主城後仍未被淘汰（征服模式）",player:GetAttribute("Defeated")~=true and workspace:GetAttribute("MatchPhase")=="Playing",
  "defeated="..tostring(player:GetAttribute("Defeated")).." phase="..tostring(workspace:GetAttribute("MatchPhase")))
 -- 放出的單位可以正常接受移動指令
 command:FireServer("Order",released,center+Vector3.new(60,0,0))
 task.wait(1)
 local moving=0
 for _,unit in ipairs(released) do if unit:GetAttribute("OrderKind")=="move" then moving+=1 end end
 check("放出的單位可接受移動指令",moving==16,"moving="..moving)

 -- ===== 瞭望塔、城堡與被敵軍摧毀 =====
 local function flat(model) local p=model:GetPivot().Position; return Vector3.new(p.X,0,p.Z) end
 local function clearMine()
  for _,unit in ipairs(mine()) do helper:InvokeServer("remove",unit) end
  waitFor(function() return #mine()==0 end,5)
 end
 local function build(kind,position)
  sequence+=1
  local tag="garrison-"..sequence
  assert(helper:InvokeServer("build",kind,position,tag),"找不到可放置 "..kind.." 的空地")
  local found
  assert(waitFor(function()
   for _,building in ipairs(buildingFolder:GetChildren()) do if building:GetAttribute("TestTag")==tag then found=building; return true end end
   return false
  end,8),kind.." 沒有複製到客戶端")
  return found
 end
 local function inside(building) return building:GetAttribute("Garrison") or 0 end
 -- 在建築射程內放一名敵方騎士，量測齊射的箭數與生命減少量；回傳是否符合預期與畫面箭矢數。
 local function volleyCheck(building,expectedVolley,angle,distance)
  local enemy=spawn("ai","cavalry",angle,distance,flat(building))
  local perArrow=math.max(1,(building:GetAttribute("Attack") or 0)-(enemy:GetAttribute("Armor") or 0))
  local seen,matched,parts={},false,0
  local connection
  connection=building:GetAttributeChangedSignal("LastAttack"):Connect(function()
   task.defer(function()
    local before=enemy.Parent and enemy:GetAttribute("HP") or 0
    local volley=building:GetAttribute("AttackVolley")
    local flight=building:GetAttribute("AttackFlight") or 0.3
    task.wait(0.05)
    local count=0
    for _,item in ipairs(workspace:GetDescendants()) do if item.Name=="ArrowEffect" then count+=1 end end
    parts=math.max(parts,count)
    task.wait(flight+0.35)
    local after=enemy.Parent and enemy:GetAttribute("HP") or 0
    table.insert(seen,string.format("volley=%s hp %s->%s",tostring(volley),tostring(before),tostring(after)))
    if volley==expectedVolley and before>0 and (before-after==volley*perArrow or (after==0 and before<=volley*perArrow)) then matched=true end
   end)
  end)
  waitFor(function() return matched or #seen>=4 or not enemy.Parent end,25)
  task.wait(1.2)
  connection:Disconnect()
  if enemy.Parent then helper:InvokeServer("remove",enemy) end
  info(string.format("%s 每箭傷害 %d；%s；畫面箭矢最多 %d 支",tostring(building:GetAttribute("BuildingType")),perArrow,table.concat(seen,"; "),parts))
  return matched,parts
 end
 clearMine()
 local inward=Vector3.new(center.X>0 and -1 or 1,0,center.Z>0 and -1 or 1)

 -- 10. 瞭望塔：會攻擊、容量 5、不收騎兵、箭數上限 5
 local tower=build("Tower",center+inward*55)
 local towerPosition=flat(tower)
 require(RS.Shared.CameraFocus).Request(player,towerPosition)
 check("瞭望塔容量 5、初始駐軍 0",tower:GetAttribute("GarrisonCapacity")==5 and inside(tower)==0,"capacity="..tostring(tower:GetAttribute("GarrisonCapacity")))
 local matched=volleyCheck(tower,1,0.6,34)
 check("空的瞭望塔會攻擊（一次 1 支箭）",matched)
 local towerGroup={}
 for index=1,6 do table.insert(towerGroup,spawn("human","archer",index*0.9,20,towerPosition)) end
 table.insert(towerGroup,spawn("human","cavalry",6.0,24,towerPosition))
 command:FireServer("Garrison",towerGroup,tower)
 check("瞭望塔駐軍達到容量 5",waitFor(function() return inside(tower)==5 end,30),"garrison="..inside(tower))
 task.wait(3)
 local outsideKinds={}
 for _,unit in ipairs(mine()) do table.insert(outsideKinds,unit:GetAttribute("UnitType")..":"..tostring(unit:GetAttribute("OrderKind"))) end
 table.sort(outsideKinds)
 check("騎士不能進瞭望塔、第 6 位弓箭手留在外面",inside(tower)==5 and table.concat(outsideKinds,",")=="archer:nil,cavalry:nil",table.concat(outsideKinds,","))
 check("瞭望塔箭數 5（上限 5）",tower:GetAttribute("GarrisonArrows")==5,"arrows="..tostring(tower:GetAttribute("GarrisonArrows")))
 clearMine()
 local towerParts
 matched,towerParts=volleyCheck(tower,6,0.6,34)
 check("駐軍的瞭望塔齊射 6 支且傷害逐箭結算",matched)
 check("客戶端畫出瞭望塔的 6 支箭",towerParts>=6,"arrowParts="..towerParts)

 -- 11. 瞭望塔被敵軍打爆：駐軍出現在原位置
 populationBefore=player:GetAttribute("Population")
 local rams={}
 for index=1,10 do table.insert(rams,spawn("ai","ram",index*0.628,26,towerPosition)) end
 for _,ram in ipairs(rams) do helper:InvokeServer("attack",ram,tower) end
 local hpSeen=tower:GetAttribute("HP")
 check("敵方衝車摧毀瞭望塔",waitFor(function()
  if tower.Parent then hpSeen=tower:GetAttribute("HP") end
  return tower.Parent==nil
 end,90),"lastHP="..tostring(hpSeen))
 check("瞭望塔被摧毀後 5 位駐軍出現",waitFor(function() return #mine()==5 end,5),"units="..#mine())
 local survivors=mine()
 local close,spread,kindsOut=0,math.huge,{}
 for index,unit in ipairs(survivors) do
  local p=flat(unit)
  if (p-towerPosition).Magnitude<=30 then close+=1 end
  kindsOut[unit:GetAttribute("UnitType")]=(kindsOut[unit:GetAttribute("UnitType")] or 0)+1
  for other=index+1,#survivors do spread=math.min(spread,(p-flat(survivors[other])).Magnitude) end
 end
 check("放出的駐軍在瞭望塔原位置",close==5,"close="..close)
 check("放出的駐軍彼此不重疊",spread>=3.5,"minimumGap="..string.format("%.2f",spread))
 check("放出的都是弓箭手",kindsOut.archer==5,"archer="..tostring(kindsOut.archer))
 check("駐軍一直計入人口（摧毀前後皆為 5）",player:GetAttribute("Population")==5 and populationBefore==5,"before="..tostring(populationBefore).." after="..tostring(player:GetAttribute("Population")))
 check("失去瞭望塔後未被淘汰",player:GetAttribute("Defeated")~=true and workspace:GetAttribute("MatchPhase")=="Playing")
 task.wait(2.5)
 local fighting=0
 for _,unit in ipairs(mine()) do if unit:GetAttribute("OrderKind")=="attack" then fighting+=1 end end
 check("放出的弓箭手自動迎戰衝車",fighting>=1,"attacking="..fighting.." alive="..#mine())
 for _,ram in ipairs(rams) do if ram.Parent then helper:InvokeServer("remove",ram) end end
 clearMine()

 -- 12. 城堡：會攻擊、容量 20、收騎兵、不收攻城器械、箭數上限 15
 local castle=build("Castle",center+inward*130)
 local castlePosition=flat(castle)
 require(RS.Shared.CameraFocus).Request(player,castlePosition)
 check("城堡容量 20、初始駐軍 0",castle:GetAttribute("GarrisonCapacity")==20 and inside(castle)==0,"capacity="..tostring(castle:GetAttribute("GarrisonCapacity")))
 check("城堡有攻擊力與射程",(castle:GetAttribute("Attack") or 0)>0 and (castle:GetAttribute("Range") or 0)>0,
  "attack="..tostring(castle:GetAttribute("Attack")).." range="..tostring(castle:GetAttribute("Range")))
 matched=volleyCheck(castle,1,0.4,62)
 check("空的城堡會攻擊進入射程的敵軍（一次 1 支箭）",matched)
 local castleGroup={}
 for index=1,16 do table.insert(castleGroup,spawn("human","archer",index*0.39,52,castlePosition)) end
 table.insert(castleGroup,spawn("human","cavalry",0.1,56,castlePosition))
 local castleRam=spawn("human","ram",3.3,58,castlePosition)
 table.insert(castleGroup,castleRam)
 populationBefore=player:GetAttribute("Population")
 command:FireServer("Garrison",castleGroup,castle)
 info(string.format("城堡位置相對主城 %.0f,%.0f；PrimaryPart 尺寸 %s",castlePosition.X-center.X,castlePosition.Z-center.Z,tostring(castle.PrimaryPart and castle.PrimaryPart.Size)))
 local lastSample=0
 local entered=waitFor(function()
  if os.clock()-lastSample>=2 then
   lastSample=os.clock()
   local kindsNow,enemiesNear={},0
   for _,unit in ipairs(unitFolder:GetChildren()) do
    if unit:GetAttribute("OwnerId")==player.UserId then
     local key=tostring(unit:GetAttribute("OrderKind"))..":"..tostring(unit:GetAttribute("Animation"))
     kindsNow[key]=(kindsNow[key] or 0)+1
    elseif (flat(unit)-castlePosition).Magnitude<140 then enemiesNear+=1 end
   end
   local parts={}
   for key,count in pairs(kindsNow) do table.insert(parts,key.."="..count) end
   table.sort(parts)
   info("城堡駐紮中 inside="..inside(castle).." 外面："..table.concat(parts," ").." 附近敵軍="..enemiesNear)
  end
  return inside(castle)==17
 end,45)
 check("16 位弓箭手與騎士進入城堡",entered,"garrison="..inside(castle))
 for _,unit in ipairs(mine()) do
  local offset=flat(unit)-castlePosition
  info(string.format("城堡外的單位 %s order=%s (%s) 相對位置 %.0f,%.0f",tostring(unit:GetAttribute("UnitType")),tostring(unit:GetAttribute("OrderKind")),
   tostring(unit:GetAttribute("Order")),offset.X,offset.Z))
 end
 check("攻城衝車不能進城堡",castleRam.Parent==unitFolder and castleRam:GetAttribute("OrderKind")~="garrison","order="..tostring(castleRam:GetAttribute("OrderKind")))
 check("城堡箭數 15（上限 15）",castle:GetAttribute("GarrisonArrows")==15,"arrows="..tostring(castle:GetAttribute("GarrisonArrows")))
 check("城堡駐軍計入人口",player:GetAttribute("Population")==populationBefore,"before="..tostring(populationBefore).." after="..tostring(player:GetAttribute("Population")))
 helper:InvokeServer("remove",castleRam)
 local castleParts
 matched,castleParts=volleyCheck(castle,16,0.4,62)
 check("駐軍的城堡齊射 16 支且傷害逐箭結算",matched)
 check("客戶端畫出城堡的 16 支箭",castleParts>=16,"arrowParts="..castleParts)
 command:FireServer("Ungarrison",castle)
 check("城堡全部離開",waitFor(function() return inside(castle)==0 and #mine()==17 end,6),"garrison="..inside(castle).." units="..#mine())
 local castleHalf=castle.PrimaryPart and castle.PrimaryPart.Size/2 or Vector3.new(32,0,32)
 local within=0
 for _,unit in ipairs(mine()) do
  local p=flat(unit)
  if math.abs(p.X-castlePosition.X)<castleHalf.X and math.abs(p.Z-castlePosition.Z)<castleHalf.Z then within+=1 end
 end
 check("離開城堡的單位都在占地外",within==0,"insideFootprint="..within)

 -- 13. 城堡自動攻擊敵方建築：射程內沒有敵方單位時才打建築，單位出現後改打單位
 clearMine()
 local enemyHouse
 for step=0,7 do
  sequence+=1
  local tag="garrison-"..sequence
  local angle=step*math.pi/4+0.3
  if helper:InvokeServer("buildEnemy","House",castlePosition+Vector3.new(math.cos(angle)*56,0,math.sin(angle)*56),tag) then
   waitFor(function()
    for _,building in ipairs(buildingFolder:GetChildren()) do if building:GetAttribute("TestTag")==tag then enemyHouse=building; return true end end
    return false
   end,8)
   break
  end
 end
 assert(enemyHouse,"城堡射程內找不到可放敵方房屋的空地")
 local housePosition=flat(enemyHouse)
 local houseStart=enemyHouse:GetAttribute("HP")
 local perHit=math.max(1,(castle:GetAttribute("Attack") or 0)-(enemyHouse:GetAttribute("Armor") or 0))
 check("沒有敵方單位時城堡射擊敵方建築",waitFor(function() return (enemyHouse:GetAttribute("HP") or 0)<houseStart end,10),
  "houseHP "..tostring(houseStart).."->"..tostring(enemyHouse:GetAttribute("HP")))
 local aim=castle:GetAttribute("AttackPosition")
 check("城堡瞄準的是那座建築",typeof(aim)=="Vector3" and (Vector3.new(aim.X,0,aim.Z)-housePosition).Magnitude<=12,"aim="..tostring(aim))
 local lost=houseStart-(enemyHouse:GetAttribute("HP") or 0)
 check("對建築的傷害為每箭（攻擊 − 護甲）的整數倍",lost>0 and lost%perHit==0,"lost="..lost.." perHit="..perHit)
 -- 敵方單位進入射程：之後的箭都射向單位，建築不再掉血。
 local intruder=spawn("ai","cavalry",3.6,62,castlePosition)
 task.wait(2.6)
 local houseBefore,intruderBefore=enemyHouse:GetAttribute("HP"),intruder.Parent and intruder:GetAttribute("HP") or 0
 task.wait(5)
 local houseAfter,intruderAfter=enemyHouse:GetAttribute("HP"),intruder.Parent and intruder:GetAttribute("HP") or 0
 check("敵方單位在射程內時城堡優先打單位、不打建築",houseAfter==houseBefore and intruderAfter<intruderBefore,
  string.format("houseHP %s->%s cavalryHP %s->%s",tostring(houseBefore),tostring(houseAfter),tostring(intruderBefore),tostring(intruderAfter)))
 if intruder.Parent then helper:InvokeServer("remove",intruder) end
 local houseResume=enemyHouse:GetAttribute("HP")
 check("單位離開後城堡回頭射擊建築",waitFor(function() return (enemyHouse:GetAttribute("HP") or 0)<houseResume end,10),
  "houseHP "..tostring(houseResume).."->"..tostring(enemyHouse:GetAttribute("HP")))
end
local ok,message=pcall(main)
if not ok then failed+=1; print("[GARRISON_TEST] ERROR "..tostring(message)) end
print(string.format("[GARRISON_TEST] DONE pass=%d fail=%d",passed,failed))
