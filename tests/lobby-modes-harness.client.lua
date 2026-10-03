-- Opt-in only through lobby-modes-validation.project.json; never mapped by the normal project.
-- One client: lobby UI, server validation, solo Story start / win / unlock, PvE and PvP quick rooms.
-- Two clients (Player1 / Player2): multiplayer Story co-op and a PvP match through QuickPlay.
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
local function quick(choice)
 command:FireServer("QuickPlay",choice)
 -- Solo Story can depart before the queued flag is observed; reaching the battle also counts.
 await(function() return player:GetAttribute("LobbyQueued")==true or inBattle() end,"QuickPlay "..choice.." joined a room")
 return player:GetAttribute("LobbyRoomId") or workspace:GetAttribute("ActiveBattleRoomId")
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
 -- Lobby welcome panel.
 local welcome=find("CourtyardWelcome")
 check(welcome and visible(welcome),"welcome panel visible")
 for _,id in ipairs({"StorySolo","Story","PvP","PvE"}) do
  local b=find("QuickPlay_"..id)
  check(b and visible(b) and b:GetAttribute("Unavailable")~=true,"quick start "..id.." visible and available")
 end
 await(function() return textOf(find("QuickPlay_StorySolo")):find("單人劇情",1,true) end,"quick story title")
 check(player:GetAttribute("StoryCleared")==0,"new session has no story clears")

 -- Room wizard as host, default PvP.
 command:FireServer("QueueJoin","Room1")
 await(function() return player:GetAttribute("LobbyRoomId")=="Room1" end,"joined Room1")
 local frame=find("MatchLobby")
 await(function() return visible(frame) and frame:GetAttribute("WizardEnabled")==true end,"host wizard opened")
 check(settingsOf("Room1").gameMode=="PvP","room default mode is PvP")
 for _,id in ipairs(GameModes.Order) do check(find("ModeCard_"..id)~=nil,"mode card "..id) end
 await(function() return find("ModeCard_PvP"):GetAttribute("Selected")==true end,"PvP card selected")
 check(visible(find("Setting_teamMode")) and not visible(find("Setting_storyChapter")),"PvP page shows team mode, hides chapter")

 -- Switch to Story through the same proposal the cards use.
 local current=settingsOf("Room1")
 local request=GameModes.next(current,"gameMode",{"Story"},1,GameModes.unlocked(player:GetAttribute("StoryCleared")))
 check(request and request.storyChapter==1,"client proposes Story chapter 1")
 local revision=send(request,"Room1")
 await(function() return changed("Room1",revision) and settingsOf("Room1").gameMode=="Story" end,"server stored Story")
 local s,chapter=settingsOf("Room1"),Config.Story.chapters[1]
 check(s.storyChapter==1 and s.teamMode=="CoopAI" and s.aiCount==chapter.aiCount and s.size==chapter.size and s.victory==chapter.victory,"server applied chapter 1 rules")
 await(function() return find("ModeCard_Story"):GetAttribute("Selected")==true and visible(find("Setting_storyChapter")) end,"Story card selected, chapter field shown")
 await(function() return visible(find("StoryBriefing")) and find("StoryBriefing").Text:find(chapter.briefing,1,true) end,"chapter briefing shown")
 check(not visible(find("Setting_teamMode")),"Story hides team mode")

 -- Server rejects a locked chapter, a client override of chapter rules, AI in PvP and an internal mode.
 local locked=table.clone(s); locked.storyChapter=2
 revision=send(locked,"Room1"); task.wait(1)
 check(not changed("Room1",revision) and settingsOf("Room1").storyChapter==1,"locked chapter 2 rejected")
 local override=table.clone(s); override.size="Large"; override.aiCount=3; override.difficulty="Hard"; override.expectedPlayers=1
 revision=send(override,"Room1")
 await(function() return changed("Room1",revision) end,"override request processed")
 s=settingsOf("Room1")
 check(s.size==chapter.size and s.aiCount==chapter.aiCount and s.difficulty==chapter.difficulty,"chapter rules not overridable by client")
 revision=send({gameMode="PvP",storyChapter=0,expectedPlayers=2,aiCount=1,teamMode="FFA",size="Medium",difficulty="Normal",population=100,startingResources="Standard",victory="Conquest"},"Room1"); task.wait(1)
 check(not changed("Room1",revision) and settingsOf("Room1").gameMode=="Story","PvP with AI rejected")
 revision=send({gameMode="Sandbox",storyChapter=0,expectedPlayers=1,aiCount=0,teamMode="FFA",size="Small",difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"},"Room1"); task.wait(1)
 check(not changed("Room1",revision),"client Sandbox rejected")

 -- PvE through the proposal; UI moves AI and difficulty to page 1.
 request=GameModes.next(settingsOf("Room1"),"gameMode",{"PvE"},1,1)
 revision=send(request,"Room1")
 await(function() return changed("Room1",revision) and settingsOf("Room1").gameMode=="PvE" end,"server stored PvE")
 s=settingsOf("Room1")
 check(s.aiCount>=1 and s.storyChapter==0 and (s.teamMode=="CoopAI" or s.teamMode=="FFA"),"PvE has AI and no chapter")
 await(function() return visible(find("Setting_aiCount")) and visible(find("Setting_difficulty")) and find("ModeCard_PvE"):GetAttribute("Selected")==true end,"PvE page 1 shows AI and difficulty")
 leave()

 -- Solo Story quick start: departs immediately into chapter 1.
 local id=quick("StorySolo")
 await(inBattle,"solo Story battle started",60)
 check(workspace:GetAttribute("StoryChapter")==1 and workspace:GetAttribute("TeamMode")=="CoopAI","battle is Story chapter 1 co-op")
 await(function() return #aiActors()==Config.Story.chapters[1].aiCount end,"chapter AI spawned")
 check(aiActors()[1]:GetAttribute("DisplayName")==Config.Story.chapters[1].enemy,"AI named after chapter enemy")
 check(aiActors()[1]:GetAttribute("TeamName")==Config.Story.chapters[1].enemy and player:GetAttribute("TeamId")==1,"enemy team named, player on team 1")
 check(id~=nil,"solo story used room "..tostring(id))

 -- Chapter victory records progress and unlocks chapter 2.
 task.wait(3)
 probe:FireServer("DefeatAI")
 await(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,"chapter ended after AI eliminated",30)
 check(workspace:GetAttribute("WinnerTeamId")==1,"humans won the chapter")
 await(function() return player:GetAttribute("StoryCleared")==1 end,"chapter 1 recorded as cleared")
 backToLobby(true)
 await(function() return textOf(find("QuickPlay_StorySolo")):len()>0 and find("QuickPlay_StorySolo"):FindFirstChildWhichIsA("TextLabel") end,"quick buttons back")
 local detailFound=false
 for _,child in ipairs(find("QuickPlay_StorySolo"):GetChildren()) do
  if child:IsA("TextLabel") and child.Text:find("第 2 章",1,true) then detailFound=true end
 end
 check(detailFound,"solo story quick start now offers chapter 2")

 -- Chapter 2 is now accepted in a custom room.
 task.wait(2.3)
 command:FireServer("QueueJoin","Room2")
 await(function() return player:GetAttribute("LobbyRoomId")=="Room2" end,"joined Room2")
 request=GameModes.next(settingsOf("Room2"),"gameMode",{"Story"},1,GameModes.unlocked(player:GetAttribute("StoryCleared")))
 check(request.storyChapter==2,"Story proposal defaults to newest chapter 2")
 revision=send(request,"Room2")
 await(function() return changed("Room2",revision) and settingsOf("Room2").storyChapter==2 end,"unlocked chapter 2 accepted")
 check(settingsOf("Room2").victory==Config.Story.chapters[2].victory,"chapter 2 rules applied")
 leave()

 -- PvE / PvP quick rooms are created unconfigured for the host.
 for _,mode in ipairs({"PvE","PvP"}) do
  id=quick(mode)
  await(function() return settingsOf(id).gameMode==mode and room(id,"Configured")==false end,mode.." quick room created")
  await(function() return find("ModeCard_"..mode):GetAttribute("Selected")==true and find("MatchLobby"):GetAttribute("WizardEnabled")==true end,mode.." wizard open with mode selected")
  check(settingsOf(id).expectedPlayers==2,mode.." quick room waits for two players")
  leave()
 end
end

local function duo()
 local first=player.Name=="Player1"
 local other
 await(function() for _,p in ipairs(Players:GetPlayers()) do if p~=player then other=p end end; return other~=nil end,"second client present")
 -- Multiplayer Story: Player1 creates the room; Player2 quick-joins the same room.
 local id
 if first then
  id=quick("Story")
  await(function() return settingsOf(id).gameMode=="Story" end,"Story room created")
  finishSetup(id)
 else
  await(function()
   for _,portal in ipairs(Config.Lobby.portals) do
    if room(portal.id,"Setting_gameMode")=="Story" and room(portal.id,"Configured")==true and (room(portal.id,"Players") or 0)==1 then return true end
   end
  end,"host Story room waiting",40)
  id=quick("Story")
 end
 await(function() return room(id,"Players")==2 end,"two players in Story room")
 check(other:GetAttribute("LobbyRoomId")==id,"both clients in the same Story room")
 readyUp(id)
 await(inBattle,"co-op Story battle started",60)
 check(workspace:GetAttribute("StoryChapter")==1 and player:GetAttribute("TeamId")==1,"co-op chapter 1, humans on team 1")
 await(function() return other:GetAttribute("TeamId")==1 end,"teammate on team 1")
 check(#aiActors()==GameModes.storyAI(Config.Story.chapters[1],2),"co-op enemy count")
 if first then task.wait(3); probe:FireServer("DefeatAI") end
 await(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,"co-op chapter ended",30)
 await(function() return player:GetAttribute("StoryCleared")==1 end,"co-op win recorded for this player")
 backToLobby(first)

 -- PvP through QuickPlay: humans only, then one surrenders.
 task.wait(2.3)
 if first then
  id=quick("PvP")
  finishSetup(id)
 else
  await(function()
   for _,portal in ipairs(Config.Lobby.portals) do
    if room(portal.id,"Setting_gameMode")=="PvP" and room(portal.id,"Configured")==true and (room(portal.id,"Players") or 0)==1 then return true end
   end
  end,"host PvP room waiting",40)
  id=quick("PvP")
 end
 await(function() return room(id,"Players")==2 end,"two players in PvP room")
 readyUp(id)
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
