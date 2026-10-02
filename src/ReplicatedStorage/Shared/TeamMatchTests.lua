-- Explicit Studio CLIENT integration stages. Requiring this module does nothing.
-- Only ordinary Lobby/Command remotes perform actions. No character teleport,
-- HP/resource/state writes, private server hooks, fake GUI, or forced disconnects.
-- Participants must enter the portal normally and avoid unrelated commands while
-- a stage samples balances/orders. Each client's Command Bar has its own cache.
local Tests={}
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local resourceKeys={"food","wood","gold","stone"}
local counterKeys={"buildingsCompleted","villagersTrained","militaryTrained","damageDealt","unitsKilled","buildingsKilled","unitsLost","buildingsLost"}
local preview,forfeitReport,lastSend
local function check(ok,message)
 assert(ok,"[TEAM_MATCH_TEST FAIL] "..message)
 print("[TEAM_MATCH_TEST PASS] "..message)
end
local function client()
 local run=game:GetService("RunService")
 assert(run:IsStudio() and run:IsClient(),"僅限 Studio Play 客戶端")
 return Players.LocalPlayer
end
local function waitFor(predicate,seconds,message)
 local deadline=os.clock()+seconds
 local progress=os.clock()
 repeat
  if predicate() then return end
  assert(os.clock()<deadline,"[TEAM_MATCH_TEST FAIL] "..message.."逾時")
  if os.clock()-progress>=25 then print("[TEAM_MATCH_TEST WAIT] "..message); progress=os.clock() end
  task.wait(0.05)
 until false
end
local function timeout(value)
 value=value or 120
 assert(type(value)=="number" and value==value and value>=5 and value<=180,"觀察期限須介於 5 至 180 秒")
 return value
end
local function send(action,...)
 client()
 local remaining=0.35-(os.clock()-(lastSend or -math.huge))
 if remaining>0 then task.wait(remaining) end
 RS:WaitForChild("RTSRemotes",5):WaitForChild("Command",5):FireServer(action,...)
 lastSend=os.clock()
end
local function queued()
 local result={}
 for _,player in ipairs(Players:GetPlayers()) do if player:GetAttribute("LobbyQueued")==true then table.insert(result,player) end end
 return result
end
local function allReady(members,value)
 for _,player in ipairs(members) do if player:GetAttribute("LobbyReady")~=value then return false end end
 return true
end
local function currentSettings()
 local result={expectedPlayers=workspace:GetAttribute("LobbyExpectedPlayers")}
 for _,key in ipairs({"size","aiCount","difficulty","population","startingResources","victory","teamMode"}) do result[key]=workspace:GetAttribute("LobbySetting_"..key) end
 return result
end
local function host()
 local player=client()
 assert(workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("LobbyQueued")==true and workspace:GetAttribute("HostUserId")==player.UserId,"須由已正常集合的大廳房主執行")
 return player
end
local function report(player)
 local raw=player:GetAttribute("MatchReportJSON")
 if type(raw)~="string" or raw=="" then return nil end
 local ok,value=pcall(HttpService.JSONDecode,HttpService,raw)
 return ok and type(value)=="table" and value.version==1 and value or nil
end
local function owned(folder,id,kind)
 local result={}
 for _,model in ipairs(folder:GetChildren()) do
  if model:IsA("Model") and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id
   and (not kind or model:GetAttribute("UnitType")==kind or model:GetAttribute("BuildingType")==kind) then table.insert(result,model) end
 end
 return result
end
local function balances(player)
 local result={}
 for _,key in ipairs(resourceKeys) do result[key]=player:GetAttribute(key) end
 return result
end
local function sameBalances(player,before)
 for _,key in ipairs(resourceKeys) do if player:GetAttribute(key)~=before[key] then return false end end
 return true
end
local function idle(player)
 for _,unit in ipairs(owned(workspace.Units,player.UserId)) do
  if unit:GetAttribute("Order")~="待命" or (unit:GetAttribute("Carrying") or 0)~=0 then return false end
 end
 for _,building in ipairs(owned(workspace.Buildings,player.UserId)) do
  if building:GetAttribute("Training") or building:GetAttribute("Research") or building:GetAttribute("Complete")==false then return false end
 end
 return (player:GetAttribute("AgeRemaining") or 0)==0
end
local function flat(model)
 local position=model:GetPivot().Position
 return Vector3.new(position.X,require(RS.GameData.GameConfig).Map.GroundY,position.Z)
end

-- Enter the actual portal before this call. This method never teleports an avatar.
function Tests.Join()
 local player=client()
 assert(workspace:GetAttribute("MatchPhase")=="Lobby","須從大廳加入集合")
 send("QueueJoin")
 waitFor(function() return player:GetAttribute("LobbyQueued")==true end,8,"正式傳送門 QueueJoin；請先走入光圈")
 check(true,"正常 QueueJoin 經伺服器確認")
 return true
end
function Tests.Configure(mode,humanCount,aiCount)
 host()
 local settings={teamMode=mode,expectedPlayers=humanCount,aiCount=aiCount,size="Small",difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"}
 assert(require(RS.Shared.TeamClientRules).ValidSettings(settings,#queued()),"測試配置不合法或會移除已集合玩家")
 local revision=workspace:GetAttribute("LobbySettingsRevision")
 send("LobbySettings",settings)
 waitFor(function() return workspace:GetAttribute("LobbySettingsRevision")~=revision and workspace:GetAttribute("LobbySetting_teamMode")==mode and workspace:GetAttribute("LobbyExpectedPlayers")==humanCount and workspace:GetAttribute("LobbySetting_aiCount")==aiCount and allReady(queued(),false) end,8,"房主正式完整配置與取消準備")
 check(true,"伺服器採用完整模式／人數／AI 組合並取消所有準備")
 return workspace:GetAttribute("LobbySettingsRevision")
end
function Tests.Ready()
 local player=client()
 assert(workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("LobbyQueued")==true,"須先正常加入集合")
 send("LobbyReady",true,workspace:GetAttribute("LobbySettingsRevision"))
 waitFor(function() return player:GetAttribute("LobbyReady")==true end,8,"正式準備確認")
 check(true,"本客戶端準備經伺服器確認")
 return true
end
function Tests.RejectNonHostChange()
 local player=client()
 local members=queued()
 assert(workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("LobbyQueued")==true and workspace:GetAttribute("HostUserId")~=player.UserId and #members>=2 and allReady(members,true),"須由全部準備後的非房主集合玩家執行")
 local before=currentSettings()
 local revision=workspace:GetAttribute("LobbySettingsRevision")
 local request=assert(require(RS.Shared.TeamClientRules).NextSetting(before,"teamMode",{"FFA","Teams","CoopAI"},#members),"目前沒有其他合法模式供非房主拒絕驗證")
 send("LobbySettings",request)
 send("StartMatch")
 task.wait(0.6)
 check(workspace:GetAttribute("MatchPhase")=="Lobby" and workspace:GetAttribute("LobbySettingsRevision")==revision and allReady(members,true),"非房主不能修改 mode、取消別人 ready 或開始已準備對局")
 local after=currentSettings()
 for key,value in pairs(before) do check(after[key]==value,"非房主請求沒有覆蓋正式設定："..key) end
 return true
end
-- Unlike an initial Configure, this proves that true readiness is invalidated.
function Tests.ChangeMode(mode)
 host()
 local members=queued()
 assert(#members>=2 and allReady(members,true),"須先讓至少兩位集合玩家全部準備，才驗證模式變更取消準備")
 local settings=currentSettings()
 assert(mode~=settings.teamMode,"請選擇不同模式")
 settings.teamMode=mode
 assert(require(RS.Shared.TeamClientRules).ValidSettings(settings,#members),"新模式不相容目前完整配置；先使用 Configure 安排合法組合")
 local revision=workspace:GetAttribute("LobbySettingsRevision")
 send("LobbySettings",settings)
 waitFor(function() return workspace:GetAttribute("LobbySettingsRevision")~=revision and workspace:GetAttribute("LobbySetting_teamMode")==mode and allReady(members,false) end,8,"真實模式變更取消全部 ready")
 check(true,"房主 mode 變更後，原本全部 true 的 ready 均變 false")
 send("LobbyReady",true,revision)
 task.wait(0.6)
 check(allReady(members,false),"舊配置 revision 的準備請求不能重新準備")
 send("StartMatch")
 task.wait(0.6)
 check(workspace:GetAttribute("MatchPhase")=="Lobby","改 mode 後沒有重新準備不能開局")
 require(RS.Shared.TeamUITests).RunLobby()
 return workspace:GetAttribute("LobbySettingsRevision")
end
function Tests.CapturePreview()
 client()
 assert(workspace:GetAttribute("MatchPhase")=="Lobby" and workspace:GetAttribute("LobbyTeamPreviewReady")==true,"須在人數已齊且正式隊伍預覽已發布時擷取")
 local settings=currentSettings()
 local members=queued()
 assert(#members==settings.expectedPlayers,"真人集合人數不符設定")
 preview={mode=settings.teamMode,humans={},ais={},humanCount=#members,aiCount=settings.aiCount,revision=workspace:GetAttribute("LobbySettingsRevision")}
 for _,player in ipairs(members) do
  local team=player:GetAttribute("LobbyTeamId")
  assert(type(team)=="number" and team>=1 and team<=4,"真人隊伍預覽尚未複製")
  preview.humans[player.UserId]=team
 end
 for i=1,settings.aiCount do preview.ais[i]=assert(workspace:GetAttribute("LobbyAITeam_"..i),"電腦隊伍預覽尚未複製") end
 check(true,"擷取伺服器真實 LobbyTeamId／AI slot；不從客戶端順序自訂隊伍")
 return preview
end
function Tests.CheckAssignment()
 local player=client()
 assert(preview,"此客戶端須在開局前 CapturePreview／ObserveStart；不能用開局結果反推預覽")
 waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and workspace:FindFirstChild("Buildings") end,20,"正式開局與模型複製")
 check(workspace:GetAttribute("TeamMode")==preview.mode and workspace:GetAttribute("AICount")==preview.aiCount,"正式對局採用原先確認的 teamMode 與 AI 數")
 check(workspace.StreamingEnabled==false,"雙／四客戶端使用完整地圖複製")
 local actors,slots,teams={},{},{}
 local config=require(RS.GameData.GameConfig)
 local freeUnits=config.Settings.startingVillagers+(config.Units.scout and 1 or 0)
 for id,team in pairs(preview.humans) do
  local actor=assert(Players:GetPlayerByUserId(id),"預覽真人開局前退出；需重新驗證")
  waitFor(function() return actor:GetAttribute("TeamId")==team and actor:GetAttribute("Spectator")==false and #owned(workspace.Buildings,id,"TownCenter")==1 and #owned(workspace.Units,id)>=freeUnits end,10,"真人 TeamId 與免費模型複製")
  actors[id]=actor; teams[team]=(teams[team] or 0)+1
  check(actor:GetAttribute("MatchReportJSON")==nil and actor:GetAttribute("Forfeited")==false,"真人新局沒有前局覆盤或投降狀態："..id)
 end
 for i,team in ipairs(preview.ais) do
  local actor,id
  waitFor(function()
   local factionFolder=RS:FindFirstChild("RTSFactions")
   local candidate=factionFolder and factionFolder:FindFirstChild("AI_"..i)
   local candidateId=candidate and candidate:GetAttribute("OwnerId")
   if not candidate or not candidate:IsA("Folder") or type(candidateId)~="number" or candidateId~=candidateId
    or math.abs(candidateId)==math.huge or candidateId%1~=0 or candidateId>=0 then return false end
   local slot,name=candidate:GetAttribute("FactionSlot"),candidate:GetAttribute("TeamName")
   if type(slot)~="number" or slot~=slot or slot%1~=0 or slot<1 or slot>4 or type(name)~="string" or name==""
    or candidate:GetAttribute("TeamId")~=team or #owned(workspace.Buildings,candidateId,"TownCenter")~=1
    or #owned(workspace.Units,candidateId)<freeUnits then return false end
   for _,folder in ipairs({workspace.Buildings,workspace.Units}) do
    for _,model in ipairs(owned(folder,candidateId)) do
     if model:GetAttribute("TeamId")~=team or model:GetAttribute("TeamName")~=name then return false end
    end
   end
   actor,id=candidate,candidateId
   return true
  end,10,"電腦 actor／OwnerId／TeamId 與免費模型完整複製")
  actors[id]=actor; teams[team]=(teams[team] or 0)+1
 end
 for id,actor in pairs(actors) do
  local slot=actor:GetAttribute("FactionSlot")
  check(type(slot)=="number" and slot>=1 and slot<=4 and not slots[slot],"各陣營有不同正式出生位置 slot："..id); slots[slot]=true
  for _,folder in ipairs({workspace.Units,workspace.Buildings}) do
   for _,model in ipairs(owned(folder,id)) do check(model:GetAttribute("TeamId")==actor:GetAttribute("TeamId") and model:GetAttribute("TeamName")==actor:GetAttribute("TeamName"),"真實模型繼承實際 actor 隊伍："..model.Name) end
  end
 end
 if preview.mode=="Teams" then
  check(teams[1]==(preview.humanCount+preview.aiCount)/2 and teams[2]==teams[1],"實際 Teams 為公平 1v1／2v2")
 elseif preview.mode=="CoopAI" then check(teams[1]==preview.humanCount and teams[2]==preview.aiCount,"實際 CoopAI 為所有真人對所有電腦")
 else
  for _,count in pairs(teams) do check(count==1,"實際 FFA 各陣營獨立成隊") end
 end
 check(player.Character==nil and player:GetAttribute("TeamId")==preview.humans[player.UserId],"本客戶端移除大廳角色並採用原預覽隊伍")
 print("[TEAM_MATCH_ASSIGNMENT COMPLETE] 真實預覽與伺服器 actor／models 一致")
 return true
end
function Tests.Start()
 host()
 assert(#queued()==workspace:GetAttribute("LobbyExpectedPlayers") and allReady(queued(),true),"須所有正式集合玩家重新準備")
 Tests.CapturePreview()
 send("StartMatch")
 return Tests.CheckAssignment()
end
function Tests.ObserveStart(seconds)
 Tests.CapturePreview()
 waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" end,timeout(seconds),"等待房主正常開局")
 return Tests.CheckAssignment()
end

-- Perform immediately after a team start with two idle HUMAN allies. The normal
-- move is a positive control, so ignored attack/ownership requests cannot pass
-- merely because this client has no live command endpoint or is defeated.
function Tests.RunFriendlyFire()
 local player=client()
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("Defeated")==false,"須在存活的正式對局執行")
 assert(workspace:GetAttribute("TeamMode")=="Teams" or workspace:GetAttribute("TeamMode")=="CoopAI","須為隊伍對局")
 local ally
 for _,candidate in ipairs(Players:GetPlayers()) do if candidate~=player and candidate:GetAttribute("TeamId")==player:GetAttribute("TeamId") and candidate:GetAttribute("Defeated")==false then ally=candidate; break end end
 assert(ally,"需要另一位真實真人盟友；兩人 Teams 1v1 不適用此階段")
 assert(idle(player) and idle(ally),"先停止雙方採集／移動／建造／訓練，再開始此採樣；測試不替玩家停止")
 local scout=assert(owned(workspace.Units,player.UserId,"scout")[1],"己方缺少開局斥候")
 local allyScout=assert(owned(workspace.Units,ally.UserId,"scout")[1],"盟友缺少開局斥候")
 local allyBase=assert(owned(workspace.Buildings,ally.UserId,"TownCenter")[1],"盟友缺少起始主城")
 local start=flat(scout)
 local ray=RaycastParams.new(); ray.FilterType=Enum.RaycastFilterType.Include; ray.FilterDescendantsInstances={workspace.Resources,workspace.Buildings}
 local size=Vector3.new(5.4,4,5.4)
 local goal
 local mapSize=workspace:GetAttribute("MapSize") or require(RS.GameData.GameConfig).Map.MapSize
 for i=0,7 do
  local candidate=start+Vector3.new(math.cos(i*math.pi/4)*8,0,math.sin(i*math.pi/4)*8)
  if math.abs(candidate.X)<mapSize/2-8 and math.abs(candidate.Z)<mapSize/2-8
   and not workspace:Blockcast(CFrame.new(start+Vector3.new(0,2.5,0)),size,candidate-start,ray) then goal=candidate; break end
 end
 assert(goal,"斥候附近沒有可用正常移動正向控制路徑")
 send("Order",{scout},goal)
 waitFor(function() return (flat(scout)-start).Magnitude>=1 end,8,"正常 Order 確實移動自己的斥候")
 send("Stop",{scout})
 waitFor(function() return scout:GetAttribute("Order")=="待命" end,5,"正常 Stop 確實停止自己的斥候")
 check(true,"同一正式端點的正常移動／停止正向控制成功")
 task.wait(0.5)
 local myBalance,allyBalance=balances(player),balances(ally)
 local myPosition,otherPosition=flat(scout),flat(allyScout)
 local baseHP,unitHP=allyBase:GetAttribute("HP"),allyScout:GetAttribute("HP")
 local unitCount=#owned(workspace.Units,ally.UserId)
 local attackSeen=false
 local orderConnection=scout:GetAttributeChangedSignal("Order"):Connect(function() if scout:GetAttribute("Order")=="攻擊" then attackSeen=true end end)
 local ok,result=pcall(function()
  send("Order",{scout},allyScout)
  send("Order",{scout},allyBase)
  send("Train",allyBase,"villager")
  send("Research",allyBase,"Loom")
  send("AdvanceAge",allyBase)
  send("Order",{allyScout},otherPosition+Vector3.new(8,0,0))
  send("Stop",{allyScout})
  task.wait(1.2)
  check(not attackSeen and scout:GetAttribute("Order")=="待命" and (flat(scout)-myPosition).Magnitude<0.1,"伺服器拒絕盟友單位與建築攻擊，沒有 transient 攻擊指令")
  check(allyScout:GetAttribute("Order")=="待命" and (flat(allyScout)-otherPosition).Magnitude<0.1,"同隊仍不能控制或停止另一位玩家的斥候")
  check(allyBase:GetAttribute("HP")==baseHP and allyScout:GetAttribute("HP")==unitHP,"真實盟友建築與單位 HP 沒有受到友軍傷害")
  check(not allyBase:GetAttribute("Training") and not allyBase:GetAttribute("Research") and (ally:GetAttribute("AgeRemaining") or 0)==0 and #owned(workspace.Units,ally.UserId)==unitCount,"同隊仍不能訓練／研究／升級對方主城")
  check(sameBalances(player,myBalance) and sameBalances(ally,allyBalance),"所有拒絕指令均未扣款或共享真人資源")
  return true
 end)
 orderConnection:Disconnect()
 assert(ok,result)
 print("[TEAM_MATCH_FRIENDLY COMPLETE] 正常正向控制＋伺服器拒絕 friendly fire／跨所有權；GUI 點擊另行驗收")
 return result
end

function Tests.Surrender()
 local player=client()
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("Defeated")==false,"須由仍存活真人正常投降")
 local allyAlive,enemyAlive=false,false
 for _,actor in ipairs(Players:GetPlayers()) do if actor~=player and actor:GetAttribute("TeamId") and actor:GetAttribute("Defeated")==false then if actor:GetAttribute("TeamId")==player:GetAttribute("TeamId") then allyAlive=true else enemyAlive=true end end end
 for _,actor in ipairs(RS.RTSFactions:GetChildren()) do if actor:GetAttribute("TeamId") and actor:GetAttribute("Defeated")==false then if actor:GetAttribute("TeamId")==player:GetAttribute("TeamId") then allyAlive=true else enemyAlive=true end end end
 send("Surrender")
 waitFor(function() local value=report(player); return player:GetAttribute("Defeated")==true and player:GetAttribute("Forfeited")==true and value and value.finished==true and value.outcome=="loss" and #owned(workspace.Units,player.UserId)==0 and #owned(workspace.Buildings,player.UserId)==0 end,10,"正常投降立即 loss 與清理個人模型")
 forfeitReport=report(player)
 check(true,"正常 Surrender 確實標記 Forfeited、finished loss 並清理自己的勢力")
 if allyAlive and enemyAlive then check(workspace:GetAttribute("MatchPhase")=="Playing","盟友與敵隊仍存活時，個人投降不提前結束對局") end
 require(RS.Shared.MatchReportTests).Run()
 print("[TEAM_MATCH_SURRENDER COMPLETE] 若盟友稍後贏，再於本客戶端 ObserveFinal('loss') 驗證投降不能翻盤")
 return true
end
function Tests.ObserveFinal(expectedOutcome,seconds,expectedWinnerTeam)
 local player=client()
 assert(expectedOutcome=="win" or expectedOutcome=="loss" or expectedOutcome=="draw","請指定真實預期 win／loss／draw")
 assert(expectedWinnerTeam==nil or type(expectedWinnerTeam)=="number" and expectedWinnerTeam%1==0 and expectedWinnerTeam>=0 and expectedWinnerTeam<=4,"預期勝隊須為 0（無勝者）或正式 TeamId")
 waitFor(function()
  if workspace:GetAttribute("MatchPhase")~="Ended" then return false end
  local winner=workspace:GetAttribute("WinnerTeamId")
  if type(winner)~="number" or winner%1~=0 or winner<0 or winner>4 then return false end
  if expectedWinnerTeam~=nil and winner~=expectedWinnerTeam then return false end
  -- Phase Ended can replicate before WinnerTeamId or each player's final JSON.
  -- A forfeiter already has finished=true while the team match is still running.
  for _,actor in ipairs(Players:GetPlayers()) do
   local team=actor:GetAttribute("TeamId")
   if team then
    local actual=report(actor)
    local outcome=actor:GetAttribute("Forfeited")==true and "loss" or winner==0 and "draw" or winner==team and "win" or "loss"
    if not actual or actual.finished~=true or actual.outcome~=outcome then return false end
   end
  end
  local value=report(player)
  return value and value.finished==true
 end,timeout(seconds),"等待正常對局結束、WinnerTeamId 與所有仍連線參戰者正式覆盤一致")
 local value=report(player)
 check(value.outcome==expectedOutcome,"本客戶端正式報告呈現預期最終結果："..expectedOutcome)
 if expectedWinnerTeam~=nil then check(workspace:GetAttribute("WinnerTeamId")==expectedWinnerTeam,"實際 WinnerTeamId 是此案例明確預期的勝隊") end
 if player:GetAttribute("Forfeited")==true then
  check(value.outcome=="loss",workspace:GetAttribute("WinnerTeamId")==player:GetAttribute("TeamId") and "投降者所屬隊伍確實獲勝，個人仍為 loss" or "投降者在正式終局仍為 loss；此案例沒有證明盟友獲勝")
  if forfeitReport then
   check(value.matchId==forfeitReport.matchId and value.survivalSeconds==forfeitReport.survivalSeconds,"投降後存活紀錄沒有延長或換局")
   for _,key in ipairs(counterKeys) do check(value[key]==forfeitReport[key],"投降後個人事實沒有再累計："..key) end
   for _,field in ipairs({"resourcesDelivered","resourcesSpent"}) do for _,key in ipairs(resourceKeys) do check(value[field][key]==forfeitReport[field][key],"投降後資源事實沒有再累計："..field.."."..key) end end
  end
 else
  local winner=workspace:GetAttribute("WinnerTeamId")
  check(value.outcome==(winner==0 and "draw" or winner==player:GetAttribute("TeamId") and "win" or "loss"),"正式報告結果對應伺服器 WinnerTeamId")
 end
 require(RS.Shared.MatchReportTests).Run()
 print("[TEAM_MATCH_FINAL COMPLETE] 正式勝負／覆盤；未製造傷害或結束狀態")
 return true
end

-- Arm in a retained client, then CLOSE the actual victim client normally.
-- Departed private reports may be removed before replication; absence is a LIMIT,
-- never a passed assertion of that player's loss or persistent profile result.
function Tests.ObserveLeave(victimId)
 local player=client()
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("TeamMode")=="Teams" and workspace:GetAttribute("AICount")==0,"離開階段使用進行中 2／4 真人 Teams 且 AI0")
 local victim=assert(Players:GetPlayerByUserId(victimId),"離開的真實玩家不存在")
 assert(victim~=player and victim:GetAttribute("Defeated")==false,"須觀察另一位仍存活的真實玩家離開")
 local survivors,aliveTeams={},{}
 for _,actor in ipairs(Players:GetPlayers()) do if actor~=victim and actor:GetAttribute("TeamId") and actor:GetAttribute("Defeated")==false then survivors[actor.UserId]=actor; aliveTeams[actor:GetAttribute("TeamId")]=true end end
 local teamCount=0; for _ in pairs(aliveTeams) do teamCount+=1 end
 assert(teamCount>0,"退出後至少須保留一位存活真人")
 local observedReport
 local reportConnection=victim:GetAttributeChangedSignal("MatchReportJSON"):Connect(function() observedReport=report(victim) end)
 local removeConnection
 removeConnection=Players.PlayerRemoving:Connect(function(leaving)
  if leaving~=victim then return end
  removeConnection:Disconnect()
  task.spawn(function()
   local ok,message=pcall(function()
    waitFor(function() return victim.Parent~=Players and #owned(workspace.Units,victimId)==0 and #owned(workspace.Buildings,victimId)==0 and (teamCount>=2 and workspace:GetAttribute("MatchPhase")=="Playing" or teamCount==1 and workspace:GetAttribute("MatchPhase")=="Ended") end,12,"真正 PlayerRemoving 與勢力清理／隊伍存活規則")
    for _,actor in pairs(survivors) do check(actor.Parent==Players and actor:GetAttribute("Defeated")==false,"離開觀察期間其餘真人保持存活；沒有混入其他投降／戰鬥") end
    check(workspace:GetAttribute("HostUserId")~=victimId,"退出者不再持有房主權限")
    check(true,teamCount>=2 and "真人退出後仍有兩個存活隊伍，對局正常繼續" or "真人退出後僅一隊存活，正常結束")
    if teamCount==1 then
     local winner; for team in pairs(aliveTeams) do winner=team end
     waitFor(function() return workspace:GetAttribute("WinnerTeamId")==winner end,5,"退出後唯一存留隊伍獲得正式勝利")
     check(true,"真正退出後 WinnerTeamId 是唯一存活隊伍")
    end
    observedReport=observedReport or report(victim)
    if observedReport then check(observedReport.finished==true and observedReport.outcome=="loss","確實複製到的退出者正式報告為 loss")
    else print("[TEAM_MATCH_LEAVE LIMIT] 私人 JSON 未在 Player 卸載前複製；退出者 loss／持久紀錄沒有客戶端引擎驗收。") end
    print("[TEAM_MATCH_LEAVE COMPLETE] 真實 PlayerRemoving、模型清理及存留隊伍規則；私人 outcome 只按實際觀測報告")
   end)
   reportConnection:Disconnect()
   assert(ok,message)
  end)
 end)
 print("[TEAM_MATCH_LEAVE ARMED] 請正常關閉實際另一客戶端，UserId="..victimId)
 return removeConnection
end
function Tests.CheckRestartClear()
 client()
 waitFor(function()
  if workspace:GetAttribute("MatchPhase")~="Lobby" or workspace:GetAttribute("WinnerTeamId")~=0 or workspace:GetAttribute("WinnerId")~=0
   or workspace:GetAttribute("TeamMode")~="" or workspace:GetAttribute("LobbyTeamPreviewReady")~=false or #RS.RTSFactions:GetChildren()~=0 then return false end
  for _,actor in ipairs(Players:GetPlayers()) do
   if actor:GetAttribute("MatchReportJSON")~=nil or actor:GetAttribute("TeamId")~=nil or actor:GetAttribute("TeamName")~=nil
    or actor:GetAttribute("Forfeited")~=false or actor:GetAttribute("Defeated")~=false then return false end
  end
  for _,folder in ipairs({workspace.Units,workspace.Buildings}) do for _,model in ipairs(folder:GetChildren()) do if model:GetAttribute("RTSManaged")==true then return false end end end
  return true
 end,10,"重開後所有真人／隊伍／模型實際複製與清理完成")
 check(workspace:GetAttribute("MatchPhase")=="Lobby","正式 Restart 已返回大廳")
 for _,actor in ipairs(Players:GetPlayers()) do
  check(actor:GetAttribute("MatchReportJSON")==nil and actor:GetAttribute("TeamId")==nil and actor:GetAttribute("TeamName")==nil and actor:GetAttribute("Forfeited")==false and actor:GetAttribute("Defeated")==false,"仍連線真人的 JSON／隊伍／投降／淘汰狀態全部清零："..actor.UserId)
 end
 check(workspace:GetAttribute("WinnerTeamId")==0 and workspace:GetAttribute("WinnerId")==0 and workspace:GetAttribute("TeamMode")=="" and workspace:GetAttribute("LobbyTeamPreviewReady")==false,"正式 winner／match team 與未集合預覽清零")
 check(#RS.RTSFactions:GetChildren()==0,"前局 AI 陣營已清除")
 for _,folder in ipairs({workspace.Units,workspace.Buildings}) do
  for _,model in ipairs(folder:GetChildren()) do check(model:GetAttribute("RTSManaged")~=true,"前局管理模型已清除；保留未知模型") end
 end
 require(RS.Shared.MatchReportTests).CheckClear()
 preview,forfeitReport=nil,nil
 print("[TEAM_MATCH_RESTART COMPLETE] 正式 JSON／UI／分隊／模型清零；沒有寫入測試狀態")
 return true
end
function Tests.Restart()
 local player=client()
 assert(workspace:GetAttribute("MatchPhase")=="Ended" and workspace:GetAttribute("HostUserId")==player.UserId,"須由結束對局的現任房主正常重開")
 local generation=workspace:GetAttribute("MatchGeneration")
 send("RestartMatch")
 waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" and workspace:GetAttribute("MatchGeneration")~=generation and workspace:GetAttribute("WinnerTeamId")==0 and player:GetAttribute("MatchReportJSON")==nil end,15,"正常 Restart 與新 generation 清零")
 return Tests.CheckRestartClear()
end
function Tests.ObserveRestart(seconds)
 client()
 assert(workspace:GetAttribute("MatchPhase")=="Ended","須先完成正式對局再觀察重開")
 local generation=workspace:GetAttribute("MatchGeneration")
 waitFor(function() return workspace:GetAttribute("MatchPhase")=="Lobby" and workspace:GetAttribute("MatchGeneration")~=generation and workspace:GetAttribute("WinnerTeamId")==0 end,timeout(seconds),"等待房主正常 Restart")
 return Tests.CheckRestartClear()
end
return Tests
