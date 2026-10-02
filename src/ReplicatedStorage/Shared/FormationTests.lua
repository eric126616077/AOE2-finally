-- 明確呼叫才執行的 Studio 整合測試。Run 會改變本次測試局的單位指令與隊形。
-- 新 Play CLIENT：require(game.ReplicatedStorage.Shared.FormationTests).Run()
-- 正常遊戲不呼叫本模組，也不生成遊戲單位、不修改權威位置或玩家資源。
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local Config=require(RS.GameData.GameConfig)
local Tests={running=false}
local KEYS={"Box","Line","Column","Wedge","Spread"}
local ATTRIBUTES={"Formation","FormationSlot","FormationForwardX","FormationForwardZ","Order"}
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function horizontal(point) return Vector3.new(point.X,0,point.Z) end
local function point(value) return typeof(value)=="Vector3" and {X=value.X,Y=value.Y,Z=value.Z} or nil end
local function managed(folder,ownerId)
 local result={}
 if folder then
  for _,model in ipairs(folder:GetChildren()) do
   if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==ownerId then
    table.insert(result,model)
   end
  end
 end
 return result
end
local function capture(selection)
 local result={}
 for _,unit in ipairs(selection) do
  local row={}
  for _,key in ipairs(ATTRIBUTES) do row[key]=unit:GetAttribute(key) end
  row.position=horizontal(unit:GetPivot().Position)
  result[unit]=row
 end
 return result
end
local function unchanged(selection,before)
 for _,unit in ipairs(selection) do
  for _,key in ipairs(ATTRIBUTES) do if unit:GetAttribute(key)~=before[unit][key] then return false end end
  if (horizontal(unit:GetPivot().Position)-before[unit].position).Magnitude>.1 then return false end
 end
 return true
end
local function assertStudio()
 assert(RunService:IsStudio() and RunService:IsRunning(),"僅限新的 Studio Play 明確呼叫")
end

-- 同一停止狀態可由 SERVER 與每個真正 CLIENT 分別呼叫，核對整份 units 陣列。
-- 不把單一客戶端的複製屬性當成雙人同步證據。
function Tests.Snapshot(ownerId)
 assertStudio()
 assert(finite(ownerId) and ownerId%1==0,"需指定實際玩家 UserId")
 local result={context=RunService:IsServer() and "SERVER" or "CLIENT",ownerId=ownerId,
  observerId=Players.LocalPlayer and Players.LocalPlayer.UserId or nil,
  generation=workspace:GetAttribute("MatchGeneration"),phase=workspace:GetAttribute("MatchPhase"),units={}}
 for _,unit in ipairs(managed(workspace:FindFirstChild("Units"),ownerId)) do
  table.insert(result.units,{kind=unit:GetAttribute("UnitType"),formation=unit:GetAttribute("Formation"),
   slot=point(unit:GetAttribute("FormationSlot")),forwardX=unit:GetAttribute("FormationForwardX"),
   forwardZ=unit:GetAttribute("FormationForwardZ"),order=unit:GetAttribute("Order")})
 end
 table.sort(result.units,function(a,b)
  local ax,bx=a.slot and a.slot.X or 0,b.slot and b.slot.X or 0
  local az,bz=a.slot and a.slot.Z or 0,b.slot and b.slot.Z or 0
  if ax~=bx then return ax<bx end
  if az~=bz then return az<bz end
  return (a.kind or "")<(b.kind or "")
 end)
 print("[FORMATION SNAPSHOT] "..HttpService:JSONEncode(result))
 return result
end

function Tests.Run(options)
 assertStudio()
 assert(RunService:IsClient(),"Run 僅能在 Studio CLIENT 呼叫")
 assert(not Tests.running,"隊形整合測試已在執行")
 options=options or {}
 assert(type(options)=="table","options 須為 table")
 assert(workspace:GetAttribute("MatchPhase")=="Playing","先在新 Play 開始測試局")
 assert(workspace:GetAttribute("Sandbox")==true or options.allowMultiplayer==true,"預設僅限新單人沙盒；雙人局須 allowMultiplayer=true")
 Tests.running=true
 local player=Players.LocalPlayer
 local generation=workspace:GetAttribute("MatchGeneration")
 local units=workspace:FindFirstChild("Units")
 local remotes=RS:FindFirstChild("RTSRemotes")
 local command=remotes and remotes:FindFirstChild("Command")
 local tested=managed(units,player.UserId)
 local started,deadline,lastRequest=os.clock(),os.clock()+180,0
 local report={checks=0,formations={},rejections={},generation=generation,ownerId=player.UserId,
  ownershipCovered=false,cleanupStopped=false,scope="正常 Command 遠端與客戶端收到的伺服器單位複製；未宣稱雙人同步"}
 local function check(condition,message)
  assert(condition,"[FORMATION FAIL] "..message)
  report.checks+=1
  print("[FORMATION PASS] "..message)
 end
 local function current()
  assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("MatchGeneration")==generation,
   "[FORMATION FAIL] 對局已改變")
  for _,unit in ipairs(tested) do assert(unit.Parent==units and unit.PrimaryPart and (unit:GetAttribute("HP") or 0)>0,"[FORMATION FAIL] 測試單位失效") end
 end
 local function waitFor(predicate,seconds,message)
  local untilTime=math.min(deadline,os.clock()+seconds)
  repeat
   current()
   if predicate() then return end
   assert(os.clock()<untilTime,"[FORMATION FAIL] "..message.."；逾時")
   RunService.Heartbeat:Wait()
  until false
 end
 local function send(action,a,b,c)
  -- 正式伺服器每秒補充 6 個請求額度；以 Heartbeat 控制測試速率，不靠突發封包判定拒絕。
  while os.clock()-lastRequest<.2 do current(); RunService.Heartbeat:Wait() end
  lastRequest=os.clock()
  command:FireServer(action,a,b,c)
 end
 local function allIdle()
  for _,unit in ipairs(tested) do if unit:GetAttribute("Order")~="待命" then return false end end
  return true
 end
 local function stopped()
  if not allIdle() then return false end
  for _,unit in ipairs(tested) do if unit:GetAttribute("FormationSlot")~=nil then return false end end
  return true
 end
 local function stop()
  send("Stop",tested)
  waitFor(stopped,4,"Stop 清除移動與隊形目的地")
 end
 local function rejects(label,action,selection,target,key)
  local before=capture(tested)
  local balances={}
  for _,resource in ipairs({"food","wood","gold","stone"}) do balances[resource]=player:GetAttribute(resource) end
  local foreign={}
  for _,unit in ipairs(units:GetChildren()) do
   if unit:IsA("Model") and unit:GetAttribute("RTSManaged")==true and unit:GetAttribute("OwnerId")~=player.UserId then table.insert(foreign,unit) end
  end
  local foreignBefore=capture(foreign)
  send(action,selection,target,key)
  local untilTime=os.clock()+.45
  repeat
   current()
   assert(unchanged(tested,before),"[FORMATION FAIL] "..label.." 改變了己方隊形、指令或位置")
   assert(unchanged(foreign,foreignBefore) or options.allowMultiplayer~=true,"外方狀態改變，請在雙方均閒置的新測試局重跑")
   RunService.Heartbeat:Wait()
  until os.clock()>=untilTime
  check(true,label.." 沒有改變任何己方隊形、指令或位置")
  for resource,amount in pairs(balances) do check(player:GetAttribute(resource)==amount,label.." 不扣除 "..resource) end
  table.insert(report.rejections,label)
 end
 local ok,failure=xpcall(function()
  check(not workspace.StreamingEnabled,"RTS 使用完整複製")
  check(units and command and command:IsA("RemoteEvent"),"正式 Units 與 Command 遠端存在")
  check(#tested>=4 and #tested<=200,"新局至少有 4 個己方有效單位")
  check(allIdle(),"測試前受選單位全部待命")
  for _,unit in ipairs(tested) do check((unit:GetAttribute("Carrying") or 0)==0,"測試前沒有攜帶資源") end
  local base=managed(workspace:FindFirstChild("Buildings"),player.UserId)[1]
  check(base and base.PrimaryPart,"己方基地已複製")
  local home=horizontal(base:GetPivot().Position)
  local mapHalf=(workspace:GetAttribute("MapSize") or Config.Map.MapSize)/2
  local params=OverlapParams.new()
  params.FilterType=Enum.RaycastFilterType.Exclude
  params.RespectCanCollide=true
  local excluded={units}
  local floor=workspace:FindFirstChild("AOE2_Ground")
  if floor then table.insert(excluded,floor) end
  params.FilterDescendantsInstances=excluded
  local arena
  for _,distance in ipairs({72,80,88}) do
   for _,side in ipairs({0,24,-24}) do
    local candidate=home+Vector3.new(side,0,(home.Z>0 and -1 or 1)*distance)
    if math.abs(candidate.X)+48<mapHalf and math.abs(candidate.Z)+48<mapHalf
     and #workspace:GetPartBoundsInBox(CFrame.new(candidate+Vector3.new(0,4,0)),Vector3.new(96,8,96),params)==0 then
     arena=candidate; break
    end
   end
   if arena then break end
  end
  check(arena,"找到沒有靜態障礙且保留邊界空間的測試區")
  local function completedAt(slots)
   if not allIdle() then return false end
   for _,unit in ipairs(tested) do if (horizontal(unit:GetPivot().Position)-horizontal(slots[unit])).Magnitude>1.6 then return false end end
   return true
  end
  local signatures={}
  for index,key in ipairs(KEYS) do
   local goal=arena+Vector3.new((index%2==0 and 12 or -12),0,0)
   send("Order",tested,goal,key)
   waitFor(function()
    for _,unit in ipairs(tested) do
     if unit:GetAttribute("Formation")~=key or typeof(unit:GetAttribute("FormationSlot"))~="Vector3" then return false end
    end
    return true
   end,4,key.." 伺服器接受群體移動")
   local slots,distances={},{}
   local maximumRadius=0
   for _,unit in ipairs(tested) do
    slots[unit]=unit:GetAttribute("FormationSlot")
    local radius=unit:GetAttribute("Radius") or Config.UnitCollision.default.radius
    maximumRadius=math.max(maximumRadius,radius)
    check(finite(slots[unit].X) and finite(slots[unit].Z) and math.abs(slots[unit].X)+radius<=mapHalf
     and math.abs(slots[unit].Z)+radius<=mapHalf,key.." 目的地有限且碰撞體積沒有超出地圖")
    local fx,fz=unit:GetAttribute("FormationForwardX"),unit:GetAttribute("FormationForwardZ")
    check(finite(fx) and finite(fz) and math.abs(fx*fx+fz*fz-1)<.001,key.." 方向為單位向量")
   end
   for first=1,#tested-1 do
    for second=first+1,#tested do
     local distance=(horizontal(slots[tested[first]])-horizontal(slots[tested[second]])).Magnitude
     check(distance>=(tested[first]:GetAttribute("Radius") or 2)+(tested[second]:GetAttribute("Radius") or 2)-.001,key.." 目的地沒有重疊")
     table.insert(distances,string.format("%.2f",distance))
    end
   end
   local fx,fz=tested[1]:GetAttribute("FormationForwardX"),tested[1]:GetAttribute("FormationForwardZ")
   local minSide,maxSide,minForward,maxForward=math.huge,-math.huge,math.huge,-math.huge
   for _,unit in ipairs(tested) do
    local slot=slots[unit]
    local side,forward=-fz*slot.X+fx*slot.Z,fx*slot.X+fz*slot.Z
    minSide,maxSide=math.min(minSide,side),math.max(maxSide,side)
    minForward,maxForward=math.min(minForward,forward),math.max(maxForward,forward)
    check(unit:GetAttribute("FormationForwardX")==fx and unit:GetAttribute("FormationForwardZ")==fz,key.." 受選單位共用方向")
   end
   if key=="Line" then check(maxSide-minSide>maxForward-minForward+maximumRadius*2,"橫列沿行進方向的側邊展開")
   elseif key=="Column" then check(maxForward-minForward>maxSide-minSide+maximumRadius*2,"縱隊沿行進方向前後展開") end
   table.sort(distances)
   signatures[key]=table.concat(distances,",")
   waitFor(function() return completedAt(slots) end,25,key.." 真正移動並抵達各自目的地")
   check(true,key.." 移動完成並保留已到達的隊形位置")
   table.insert(report.formations,{key=key,snapshot=Tests.Snapshot(player.UserId),maximumRadius=maximumRadius})
  end
  check(signatures.Box~=signatures.Line and signatures.Box~=signatures.Spread and signatures.Line~=signatures.Wedge,
   "方陣、橫列、楔形、分散具有不同的實際群體幾何")
  local beforeSwitch=capture(tested)
  send("Formation",tested,"Column")
  waitFor(function()
   for _,unit in ipairs(tested) do
    if unit:GetAttribute("Formation")~="Column" or typeof(unit:GetAttribute("FormationSlot"))~="Vector3"
     or unit:GetAttribute("FormationSlot")==beforeSwitch[unit].FormationSlot then return false end
   end
   return true
  end,4,"原地切換 Column")
  local switchedSlots={}
  for _,unit in ipairs(tested) do switchedSlots[unit]=unit:GetAttribute("FormationSlot") end
  waitFor(function() return completedAt(switchedSlots) end,25,"原地 Column 重排完成")
  check(true,"Formation 命令能切換偏好並重排現有選取")
  stop()
  for _,unit in ipairs(tested) do check(unit:GetAttribute("Formation")=="Column","Stop 保留隊形偏好") end
  local still=capture(tested)
  local stillUntil=os.clock()+.5
  repeat current(); assert(unchanged(tested,still),"[FORMATION FAIL] Stop 後單位仍在移動"); RunService.Heartbeat:Wait() until os.clock()>=stillUntil
  check(true,"Stop 後單位保持靜止")
  local validGoal=arena+Vector3.new(0,0,8)
  send("Order",tested,validGoal)
  waitFor(function()
   for _,unit in ipairs(tested) do if unit:GetAttribute("Formation")~="Column" or typeof(unit:GetAttribute("FormationSlot"))~="Vector3" then return false end end
   return true
  end,4,"一般移動沿用既有隊形")
  local rememberedSlots={}
  for _,unit in ipairs(tested) do rememberedSlots[unit]=unit:GetAttribute("FormationSlot") end
  waitFor(function() return completedAt(rememberedSlots) end,25,"一般移動沿用 Column 並抵達")
  check(true,"沒有指定 key 的一般移動沿用已保存的 Column 偏好")
  stop()
  rejects("重複選取","Formation",{tested[1],tested[1]},"Line")
  -- RemoteEvent 可能將混合 array/dictionary table 的字串鍵丟掉，或改寫稀疏數字鍵。
  -- 對網路測試只使用可保留其非法結構的 named-only 字典與密集非法成員陣列。
  -- 混合鍵與稀疏表格由純邏輯 fixture 直接檢查伺服器收到後的資料。
  rejects("非陣列表格","Formation",{unit=tested[1]},"Line")
  rejects("密集陣列包含非法成員","Formation",{tested[1],false,tested[2]},"Line")
  rejects("空選取","Formation",{},"Line")
  rejects("非法隊形","Formation",tested,"Circle")
  rejects("錯誤隊形型別","Formation",tested,{})
  rejects("重複移動選取","Order",{tested[1],tested[1]},validGoal,"Line")
  rejects("密集移動選取包含非法成員","Order",{tested[1],false,tested[2]},validGoal,"Line")
  rejects("錯誤移動目標型別","Order",tested,{},"Line")
  rejects("非法移動隊形","Order",tested,validGoal,"Circle")
  rejects("NaN 移動位置","Order",tested,Vector3.new(0/0,0,0),"Line")
  rejects("無限移動位置","Order",tested,Vector3.new(math.huge,0,0),"Line")
  rejects("地圖外移動位置","Order",tested,Vector3.new(mapHalf+10,0,0),"Line")
  rejects("混合建築選取","Formation",{tested[1],base},"Line")
  local tooMany={}
  for index=1,201 do tooMany[index]=tested[1] end
  rejects("超量選取","Formation",tooMany,"Line")
  local foreign
  for _,unit in ipairs(units:GetChildren()) do
   if unit:IsA("Model") and unit:GetAttribute("RTSManaged")==true and unit:GetAttribute("OwnerId")~=player.UserId then foreign=unit; break end
  end
  if foreign then
   rejects("混合外方單位","Formation",{tested[1],foreign},"Line")
   rejects("外方單位移動","Order",{foreign},validGoal,"Line")
   report.ownershipCovered=true
  else report.ownershipOmittedReason="單人沙盒沒有外方單位；仍需真正雙人新局檢查所有權" end
  -- 不讓單位真的走向邊角；只核對伺服器提交的邊界調整，接著使用正式 Stop。
  for _,key in ipairs(KEYS) do
   send("Order",tested,Vector3.new(mapHalf-3,0,mapHalf-3),key)
   waitFor(function()
    for _,unit in ipairs(tested) do if unit:GetAttribute("Formation")~=key or typeof(unit:GetAttribute("FormationSlot"))~="Vector3" then return false end end
    return true
   end,4,key.." 邊角指令提交")
   for _,unit in ipairs(tested) do
    local slot,radius=unit:GetAttribute("FormationSlot"),unit:GetAttribute("Radius") or 2
    check(math.abs(slot.X)+radius<=mapHalf and math.abs(slot.Z)+radius<=mapHalf,key.." 邊角調整仍在地圖內")
   end
   stop()
  end
 end,debug.traceback)
 if command and #tested>0 and workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("MatchGeneration")==generation then
  local cleanupOk=pcall(function() stop() end)
  report.cleanupStopped=cleanupOk and stopped()
 end
 Tests.running=false
 report.elapsedSeconds=os.clock()-started
 report.complete=ok and report.cleanupStopped
 if not ok then report.error=tostring(failure) end
 -- 每個實際隊形已各自輸出完整 SNAPSHOT；最後僅輸出小型摘要，避免 Studio 截斷長 JSON。
 local summary=table.clone(report)
 summary.formations={}
 for _,formation in ipairs(report.formations) do table.insert(summary.formations,formation.key) end
 print("[FORMATION "..(report.complete and "COMPLETE" or "INCOMPLETE").."] "..HttpService:JSONEncode(summary))
 return report
end

-- SERVER 唯讀等待；先開始此函式，再讓測試玩家關閉 client 或明確執行 Player:Kick。
-- 不自行踢玩家，使用真正的 PlayerRemoving 檢查正常生命週期清理。
function Tests.WatchDeparture(ownerId,timeout)
 assertStudio()
 assert(RunService:IsServer(),"離開清理觀察僅限 Studio SERVER")
 assert(finite(ownerId) and ownerId%1==0,"需指定實際玩家 UserId")
 timeout=timeout or 45
 assert(finite(timeout) and timeout>0 and timeout<=120,"timeout 須為 1 到 120 秒")
 local actor=Players:GetPlayerByUserId(ownerId)
 assert(actor,"指定玩家必須仍在線上")
 local units=managed(workspace:FindFirstChild("Units"),ownerId)
 local buildings=managed(workspace:FindFirstChild("Buildings"),ownerId)
 assert(#units>0 and #buildings>0,"先在測試局形成隊伍再觀察離開")
 local departed=false
 local connection=Players.PlayerRemoving:Connect(function(player) if player==actor then departed=true end end)
 local deadline=os.clock()+timeout
 repeat
  if departed and #managed(workspace:FindFirstChild("Units"),ownerId)==0
   and #managed(workspace:FindFirstChild("Buildings"),ownerId)==0 then break end
  RunService.Heartbeat:Wait()
 until os.clock()>=deadline
 connection:Disconnect()
 local cleaned=departed and #managed(workspace:FindFirstChild("Units"),ownerId)==0
  and #managed(workspace:FindFirstChild("Buildings"),ownerId)==0
 for _,model in ipairs(units) do cleaned=cleaned and model.Parent==nil end
 for _,model in ipairs(buildings) do cleaned=cleaned and model.Parent==nil end
 local result={ownerId=ownerId,departed=departed,complete=cleaned==true,removedUnits=#units,removedBuildings=#buildings,
  phase=workspace:GetAttribute("MatchPhase"),remainingPlayers=#Players:GetPlayers(),generation=workspace:GetAttribute("MatchGeneration")}
 if result.remainingPlayers==0 then result.complete=result.complete and result.phase=="Lobby" end
 print("[FORMATION DEPARTURE "..(result.complete and "COMPLETE" or "INCOMPLETE").."] "..HttpService:JSONEncode(result))
 return result
end
return Tests
