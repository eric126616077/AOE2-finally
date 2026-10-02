-- Explicit read-only Studio CLIENT checks. These inspect the real PlayerGui and
-- server attributes; they do not join, start, select, issue commands, or move UI.
local Tests={}
local Rules=require(script.Parent.TeamClientRules)
local function client()
 local run=game:GetService("RunService")
 assert(run:IsStudio() and run:IsClient(),"僅限 Studio Play 客戶端")
 local player=game.Players.LocalPlayer
 local screen=assert(player.PlayerGui:FindFirstChild("AOE2_MainGUI"),"正式 PlayerGui 尚未初始化")
 return player,screen
end
local function waitFor(predicate,message)
 local deadline=os.clock()+5
 repeat
  if predicate() then return end
  assert(os.clock()<deadline,"[TEAM_UI_TEST FAIL] "..message)
  task.wait(0.05)
 until false
end
local function label(button)
 return assert(button:FindFirstChildWhichIsA("TextLabel"),"正式按鈕文字不存在")
end
function Tests.RunLobby()
 local player,screen=client()
 assert(workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("LobbyQueued")==true,"請先透過正式傳送門加入大廳")
 local checks=0
 local function check(ok,message)
  assert(ok,"[TEAM_UI_TEST FAIL] "..message); checks+=1; print("[TEAM_UI_TEST PASS] "..message)
 end
 local body=assert(screen:FindFirstChild("LobbyContent",true),"缺少正式大廳捲動容器")
 local mode=workspace:GetAttribute("LobbySetting_teamMode")
 local expected=workspace:GetAttribute("LobbyExpectedPlayers")
 local aiCount=workspace:GetAttribute("LobbySetting_aiCount")
 local humans={}
 for _,human in ipairs(game.Players:GetPlayers()) do if human:GetAttribute("LobbyQueued")==true then table.insert(humans,human) end end
 local settings={teamMode=mode,expectedPlayers=expected,aiCount=aiCount}
 check(Rules.ValidSettings(settings,#humans),"正式伺服器發布合法模式與陣營數")
 local modeButton=assert(body:FindFirstChild("Setting_teamMode"),"缺少正式模式設定按鈕")
 local text=Rules.ModeLabel(mode,expected,aiCount)
 local editable=workspace:GetAttribute("HostUserId")==player.UserId
 waitFor(function() return label(modeButton).Text==text..(editable and "  ›" or "") end,"正式模式按鈕沒有消化伺服器設定")
 check(body.Visible and modeButton.Visible,"模式選項存在於正式大廳內容")
 check(modeButton:GetAttribute("Unavailable")==not editable,"正式房主可設定、非房主僅查看")
 waitFor(function() return (workspace:GetAttribute("LobbyTeamPreviewReady")==true)==(#humans==expected) end,"隊伍預覽就緒與實際集合人數不符")
 local ready=workspace:GetAttribute("LobbyTeamPreviewReady")==true
 table.sort(humans,function(a,b)
  if a==b then return false end
  local host=workspace:GetAttribute("HostUserId")
  if a.UserId==host then return true end
  if b.UserId==host then return false end
  local aOrder,bOrder=a:GetAttribute("LobbyJoinOrder") or math.huge,b:GetAttribute("LobbyJoinOrder") or math.huge
  return aOrder~=bOrder and aOrder<bOrder or aOrder==bOrder and a.UserId<b.UserId
 end)
 for i,human in ipairs(humans) do
  local team=human:GetAttribute("LobbyTeamId")
  check(ready and type(team)=="number" and team>=1 and team<=4 or not ready and team==nil,"真人隊伍由伺服器發布且未齊不猜測："..i)
  if ready and mode=="CoopAI" then check(team==1,"合作真人均屬正式真人隊") end
  local row=assert(body:FindFirstChild("LobbyFaction_"..i),"正式真人名單列不存在")
  local teamText=ready and Rules.TeamLabel(mode,team) or "分隊待確認"
  waitFor(function() return label(row).Text:find(human.DisplayName,1,true) and label(row).Text:find(teamText,1,true) end,"正式真人列未呈現伺服器隊伍")
 end
 for i=1,aiCount do
  local team=workspace:GetAttribute("LobbyAITeam_"..i)
  check(ready and type(team)=="number" and team>=1 and team<=4 or not ready and team==nil,"電腦隊伍由伺服器發布且未齊不猜測："..i)
  if ready and mode=="CoopAI" then check(team==2,"合作電腦均屬正式電腦隊") end
  local row=assert(body:FindFirstChild("LobbyFaction_"..(expected+i)),"正式電腦名單列不存在")
  local teamText=ready and Rules.TeamLabel(mode,team) or "分隊待確認"
  waitFor(function() return label(row).Text:find("電腦 "..i,1,true) and label(row).Text:find(teamText,1,true) end,"正式電腦列未呈現伺服器隊伍")
 end
 -- The phone layout has one UIScale and eight vertically reachable settings.
 local canvas=assert(screen:FindFirstChild("Canvas"),"缺少正式安全區域")
 local scale=canvas:FindFirstChildWhichIsA("UIScale")
 if scale and scale.Scale==1 and game:GetService("UserInputService").TouchEnabled then
  local previous
  for _,key in ipairs({"teamMode","expectedPlayers","size","aiCount","difficulty","population","startingResources","victory"}) do
   local button=assert(body:FindFirstChild("Setting_"..key),"手機設定按鈕不存在")
   check(button.AbsoluteSize.X>=43.9 and button.AbsoluteSize.Y>=43.9,"手機模式／設定有至少 44 像素點擊區："..key)
   if previous then check(button.AbsolutePosition.Y>=previous.AbsolutePosition.Y+previous.AbsoluteSize.Y+3,"手機設定列沒有重疊："..key) end
   previous=button
  end
  local row=body.LobbyFaction_1
  check(row.AbsolutePosition.Y>=previous.AbsolutePosition.Y+previous.AbsoluteSize.Y+4,"隊伍預覽位於八個設定列之後")
  local start=assert(body:FindFirstChild("StartMatchButton"),"缺少正式開始按鈕")
  local lastBottom=start.AbsolutePosition.Y-body.AbsolutePosition.Y+body.CanvasPosition.Y+start.AbsoluteSize.Y
  check(body.ScrollingDirection==Enum.ScrollingDirection.Y and body.AbsoluteCanvasSize.Y>=lastBottom,"手機短橫向／直向設定可捲到開始按鈕")
 end
 print(string.format("[TEAM_UI_TEST COMPLETE] %d checks; 唯讀正式隊伍預覽與 PlayerGui；未替代點擊／指令驗收",checks))
 return checks
end
-- Caller supplies the actual ally model they selected through ordinary input.
function Tests.CheckSelectedAlly(model)
 local player,screen=client()
 assert(typeof(model)=="Instance" and model:IsA("Model") and model:IsDescendantOf(workspace),"請傳入透過正式介面選取的實際盟友模型")
 local relation=Rules.Relation(workspace:GetAttribute("TeamMode"),player.UserId,player:GetAttribute("TeamId"),model:GetAttribute("OwnerId"),model:GetAttribute("TeamId"))
 assert(relation=="ally","所傳模型不是伺服器屬性認定的盟友")
 local details=assert(screen:FindFirstChild("TargetDetails",true),"缺少正式目標詳情")
 waitFor(function() return details:GetAttribute("TargetOwnerId")==model:GetAttribute("OwnerId") and details:GetAttribute("TargetTeamId")==model:GetAttribute("TeamId") and details.Text:find("盟友 · 友方不可攻擊",1,true) end,"正式目標詳情未呈現選取盟友")
 local context,help=screen:FindFirstChild("TargetContext",true),screen:FindFirstChild("TargetHelp",true)
 assert(context and context.Text=="友 方 勢 力" and help and help.Text=="友方不可攻擊 · 各自管理自己的資源與單位","正式盟友指令意圖不符")
 print("[TEAM_ALLY_UI COMPLETE] 實際模型 owner/team 與正式目標文字一致；未發送或替代任何攻擊指令")
 return true
end
return Tests
