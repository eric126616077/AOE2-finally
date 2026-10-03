-- Opt-in only through lobby-modes-validation.project.json; never mapped by the normal project.
-- One client: lobby portal cards, per-portal mode lock, server validation, solo Story start / win / unlock, PvE portal.
-- Two clients (Player1 / Player2): multiplayer Story co-op and a PvP match, both joined through their portals.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
local probe=RS:WaitForChild("LobbyModesProbe",30)
local Config=require(RS.GameData.GameConfig)
local GameModes=require(RS.Shared.GameModeRules)
local label="[LOBBY_MODES "..player.Name.."] "
local checks=0
local function check(ok,message)
 if not ok then error(label.."FAIL "..message,0) end
 checks+=1; print(label.."PASS "..message)
end
local function await(predicate,message,seconds)
 local deadline=os.clock()+(seconds or 20)
 repeat
  local ok,result=pcall(predicate)
  if ok and result then return end
  task.wait(0.1)
 until os.clock()>deadline
 error(label.."FAIL timeout: "..message,0)
end
local function room(id,key) return workspace:GetAttribute("LobbyRoom_"..id.."_"..key) end
local function gui() return player.PlayerGui:FindFirstChild("AOE2_MainGUI") end
local function find(name) local g=gui(); return g and g:FindFirstChild(name,true) end
local function textOf(button)
 for _,child in ipairs(button:GetChildren()) do if child:IsA("TextLabel") and child.Text~="" then return child.Text end end
 return ""
end
local function visible(object)
 while object and object:IsA("GuiObject") do
  if not object.Visible then return false end
  object=object.Parent
 end
 return object~=nil
end
local function settingsOf(id)
 local result={gameMode=room(id,"Setting_gameMode"),storyChapter=room(id,"Setting_storyChapter"),expectedPlayers=room(id,"ExpectedPlayers")}
 for _,key in ipairs({"size","aiCount","difficulty","population","startingResources","victory","teamMode"}) do result[key]=room(id,"Setting_"..key) end
 return result
end
local function send(payload,id)
 local revision=room(id,"SettingsRevision")
 command:FireServer("LobbySettings",payload)
 return revision
end
local function changed(id,revision) return room(id,"SettingsRevision")~=revision end
local function lobbyReady()
 return workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("InLobby")==true
  and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and find("LobbyLayer") and find("LobbyLayer").Visible
end
local function leave()
 command:FireServer("QueueLeave")
 await(function() return player:GetAttribute("LobbyQueued")==false end,"left room")
 task.wait(2.3) -- server queue cooldown after leaving
end
local function inBattle()
 return workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("InLobby")==false and player:GetAttribute("TeamId")~=nil
end
-- 每座傳送門固定一種玩法；沒有快速開始，直接用卡片同一個指令加入。
local function portalFor(mode)
 for _,portal in ipairs(Config.Lobby.portals) do if portal.settings.gameMode==mode then return portal.id end end
 error(label.."FAIL no portal for "..mode,0)
end
local function join(id)
 command:FireServer("QueueJoin",id)
 await(function() return player:GetAttribute("LobbyRoomId")==id end,"joined "..id)
 return id
end
local function aiActors()
 local result={}
 local folder=RS:FindFirstChild("RTSFactions")
 for _,actor in ipairs(folder and folder:GetChildren() or {}) do if actor:GetAttribute("IsAI")==true then table.insert(result,actor) end end
 return result
end
local function finishSetup(id)
 command:FireServer("LobbyConfigureComplete",room(id,"SettingsRevision"))
 await(function() return room(id,"Configured")==true end,"setup committed "..id)
end
local function readyUp(id)
 await(function() return room(id,"Configured")==true end,"room configured before ready")
 command:FireServer("LobbyReady",true,room(id,"SettingsRevision"))
end
local function backToLobby(isHost)
 if isHost then command:FireServer("RestartMatch") end
 await(lobbyReady,"returned to lobby",40)
end

local function solo()
 -- Lobby welcome panel: one card per portal, no mode buttons.
 local welcome=find("CourtyardWelcome")
 check(welcome and visible(welcome),"welcome panel visible")
 for _,id in ipairs({"StorySolo","Story","PvP","PvE"}) do check(find("QuickPlay_"..id)==nil,"no quick start button "..id) end
 for _,portal in ipairs(Config.Lobby.portals) do
  local card=find("PortalCard_"..portal.id)
  check(card and visible(card) and card:GetAttribute("Unavailable")~=true,"portal card "..portal.id.." visible and available")
  await(function() return textOf(card):find(portal.name,1,true) end,"portal card "..portal.id.." shows "..portal.name)
 end
 check(player:GetAttribute("StoryCleared")==0,"new session has no story clears")
 local pvpId,pveId,storyId=portalFor("PvP"),portalFor("PvE"),portalFor("Story")

 -- PvP portal: host wizard without mode cards; the server keeps the portal's mode.
 join(pvpId)
 local frame=find("MatchLobby")
 await(function() return visible(frame) and frame:GetAttribute("WizardEnabled")==true end,"host wizard opened")
 check(settingsOf(pvpId).gameMode=="PvP","PvP portal room is PvP")
 for _,id in ipairs(GameModes.Order) do check(find("ModeCard_"..id)==nil,"no mode card "..id) end
 check(visible(find("Setting_teamMode")) and not visible(find("Setting_storyChapter")),"PvP page shows team mode, hides chapter")
 local request=GameModes.defaults("Story",1,1,settingsOf(pvpId))
 local revision=send(request,pvpId); task.wait(1)
 check(not changed(pvpId,revision) and settingsOf(pvpId).gameMode=="PvP","PvP portal rejects switching to Story")
 revision=send({gameMode="PvP",storyChapter=0,expectedPlayers=2,aiCount=1,teamMode="FFA",size="Medium",difficulty="Normal",population=100,startingResources="Standard",victory="Conquest"},pvpId); task.wait(1)
 check(not changed(pvpId,revision) and settingsOf(pvpId).aiCount==0,"PvP with AI rejected")
 revision=send({gameMode="Sandbox",storyChapter=0,expectedPlayers=1,aiCount=0,teamMode="FFA",size="Small",difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"},pvpId); task.wait(1)
 check(not changed(pvpId,revision),"client Sandbox rejected")
 leave()

 -- PvE portal: AI and difficulty on page 1.
 join(pveId)
 await(function() return find("MatchLobby"):GetAttribute("WizardEnabled")==true end,"PvE wizard opened")
 local s=settingsOf(pveId)
 check(s.gameMode=="PvE" and s.aiCount>=1 and s.storyChapter==0 and (s.teamMode=="CoopAI" or s.teamMode=="FFA"),"PvE portal has AI and no chapter")
 await(function() return visible(find("Setting_aiCount")) and visible(find("Setting_difficulty")) end,"PvE page 1 shows AI and difficulty")
 leave()

 -- Story portal: starts at chapter 1 with chapter rules; locked chapters and rule overrides are refused.
 join(storyId)
 await(function() return find("MatchLobby"):GetAttribute("WizardEnabled")==true end,"Story wizard opened")
 local chapter=Config.Story.chapters[1]
 s=settingsOf(storyId)
 check(s.gameMode=="Story" and s.storyChapter==1 and s.teamMode=="CoopAI" and s.aiCount==chapter.aiCount and s.size==chapter.size and s.victory==chapter.victory,"story portal applies chapter 1 rules")
 await(function() return visible(find("Setting_storyChapter")) and not visible(find("Setting_teamMode")) end,"Story shows chapter, hides team mode")
 await(function() return visible(find("StoryBriefing")) and find("StoryBriefing").Text:find(chapter.briefing,1,true) end,"chapter briefing shown")
 local locked=table.clone(s); locked.storyChapter=2
 revision=send(locked,storyId); task.wait(1)
 check(not changed(storyId,revision) and settingsOf(storyId).storyChapter==1,"locked chapter 2 rejected")
 local override=table.clone(s); override.size="Large"; override.aiCount=3; override.difficulty="Hard"; override.expectedPlayers=1
 revision=send(override,storyId)
 await(function() return changed(storyId,revision) end,"override request processed")
 s=settingsOf(storyId)
 check(s.size==chapter.size and s.aiCount==chapter.aiCount and s.difficulty==chapter.difficulty,"chapter rules not overridable by client")

 -- Solo story departs once the host finishes setup and is ready.
 finishSetup(storyId)
 readyUp(storyId)
 await(inBattle,"solo Story battle started",60)
 check(workspace:GetAttribute("StoryChapter")==1 and workspace:GetAttribute("TeamMode")=="CoopAI","battle is Story chapter 1 co-op")
 await(function() return #aiActors()==chapter.aiCount end,"chapter AI spawned")
 check(aiActors()[1]:GetAttribute("DisplayName")==chapter.enemy,"AI named after chapter enemy")
 check(aiActors()[1]:GetAttribute("TeamName")==chapter.enemy and player:GetAttribute("TeamId")==1,"enemy team named, player on team 1")

 -- Chapter victory records progress and unlocks chapter 2.
 task.wait(3)
 probe:FireServer("DefeatAI")
 await(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,"chapter ended after AI eliminated",30)
 -- The winner attributes are set right after the phase; give replication a moment, then report what ended the match.
 local deadline=os.clock()+3
 while workspace:GetAttribute("WinnerTeamId")~=1 and os.clock()<deadline do task.wait(0.1) end
 if workspace:GetAttribute("WinnerTeamId")~=1 then
  local ai=aiActors()[1]
  print(label.."INFO match end: WinnerTeamId="..tostring(workspace:GetAttribute("WinnerTeamId"))
   .." Winner="..tostring(workspace:GetAttribute("Winner")).." player Defeated="..tostring(player:GetAttribute("Defeated"))
   .." Forfeited="..tostring(player:GetAttribute("Forfeited")).." TeamId="..tostring(player:GetAttribute("TeamId"))
   .." AI="..tostring(ai and ai:GetAttribute("DisplayName")).." AI Defeated="..tostring(ai and ai:GetAttribute("Defeated"))
   .." StoryCleared="..tostring(player:GetAttribute("StoryCleared")))
 end
 check(workspace:GetAttribute("WinnerTeamId")==1,"humans won the chapter")
 await(function() return player:GetAttribute("StoryCleared")==1 end,"chapter 1 recorded as cleared")
 backToLobby(true)

 -- The next story host starts from the newest unlocked chapter.
 task.wait(2.3)
 join(storyId)
 await(function() return settingsOf(storyId).storyChapter==2 end,"story portal opens at newest chapter 2")
 check(settingsOf(storyId).victory==Config.Story.chapters[2].victory,"chapter 2 rules applied")
 leave()
end

local function duo()
 local first=player.Name=="Player1"
 local other
 await(function() for _,p in ipairs(Players:GetPlayers()) do if p~=player then other=p end end; return other~=nil end,"second client present")
 local storyId,pvpId=portalFor("Story"),portalFor("PvP")
 -- Multiplayer Story: Player1 hosts the story portal for two; Player2 walks into the same portal.
 if first then
  join(storyId)
  local coop=settingsOf(storyId); coop.expectedPlayers=2
  local revision=send(coop,storyId)
  await(function() return changed(storyId,revision) and room(storyId,"ExpectedPlayers")==2 end,"Story room set for two players")
  finishSetup(storyId)
 else
  await(function() return room(storyId,"Configured")==true and room(storyId,"ExpectedPlayers")==2 and (room(storyId,"Players") or 0)==1 end,"host Story room waiting",40)
  join(storyId)
 end
 await(function() return room(storyId,"Players")==2 end,"two players in Story room")
 check(other:GetAttribute("LobbyRoomId")==storyId,"both clients in the same Story room")
 readyUp(storyId)
 await(inBattle,"co-op Story battle started",60)
 check(workspace:GetAttribute("StoryChapter")==1 and player:GetAttribute("TeamId")==1,"co-op chapter 1, humans on team 1")
 await(function() return other:GetAttribute("TeamId")==1 end,"teammate on team 1")
 check(#aiActors()==GameModes.storyAI(Config.Story.chapters[1],2),"co-op enemy count")
 if first then task.wait(3); probe:FireServer("DefeatAI") end
 await(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,"co-op chapter ended",30)
 await(function() return player:GetAttribute("StoryCleared")==1 end,"co-op win recorded for this player")
 backToLobby(first)

 -- PvP portal: humans only, then one surrenders.
 task.wait(2.3)
 if first then
  join(pvpId)
  finishSetup(pvpId)
 else
  await(function() return room(pvpId,"Configured")==true and (room(pvpId,"Players") or 0)==1 end,"host PvP room waiting",40)
  join(pvpId)
 end
 await(function() return room(pvpId,"Players")==2 end,"two players in PvP room")
 readyUp(pvpId)
 await(inBattle,"PvP battle started",60)
 check(workspace:GetAttribute("AICount")==0 and #aiActors()==0 and workspace:GetAttribute("StoryChapter")==0,"PvP has no AI and no chapter")
 await(function() return other:GetAttribute("TeamId")~=nil and other:GetAttribute("TeamId")~=player:GetAttribute("TeamId") end,"PvP opponents on separate teams")
 if not first then task.wait(2); command:FireServer("Surrender") end
 await(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,"PvP ended after surrender",30)
 check(workspace:GetAttribute("WinnerTeamId")==(first and player:GetAttribute("TeamId") or other:GetAttribute("TeamId")),"remaining player won PvP")
end

task.spawn(function()
 local ok,err=pcall(function()
  await(function() return workspace:GetAttribute("RTSReady")==true and lobbyReady() end,"client initialized",60)
  task.wait(4) -- let a second Studio client connect before choosing the flow
  if #Players:GetPlayers()>=2 then duo() else solo() end
 end)
 if ok then print(label.."ALL PASS "..checks.." checks")
 else warn(tostring(err)); print(label.."STOPPED after "..checks.." checks") end
end)
