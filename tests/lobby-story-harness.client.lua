-- Opt-in only through lobby-story-validation.project.json; never mapped by the normal project.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
local Config=require(RS.GameData.GameConfig)
local Grid=require(RS.Shared.Grid)
local label="[LOBBY_STORY "..player.Name.."] "
local checks=0
local function check(ok,message)
 assert(ok,label.."FAIL "..message)
 checks+=1; print(label.."PASS "..message)
end
local function awaitFact(predicate,message,seconds)
 local deadline=os.clock()+(seconds or 25)
 repeat if predicate() then return end; task.wait(0.1) until os.clock()>deadline
 error(label.."FAIL timeout: "..message)
end
local function room(id,key) return workspace:GetAttribute("LobbyRoom_"..id.."_"..key) end
local function own(folder,id,kind)
 local models={}
 for _,model in ipairs(folder:GetChildren()) do
  if model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id
   and (not kind or model:GetAttribute("BuildingType")==kind) then table.insert(models,model) end
 end
 return models
end
local function configure(id,humans)
 local revision=room(id,"SettingsRevision")
 command:FireServer("LobbySettings",{expectedPlayers=humans,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 awaitFact(function() return room(id,"SettingsRevision")~=revision end,"settings accepted")
 command:FireServer("LobbyConfigureComplete",room(id,"SettingsRevision"))
 awaitFact(function() return room(id,"Configured")==true end,"setup completed")
end
local function enter(id)
 command:FireServer("QueueJoin",id)
 awaitFact(function() return player:GetAttribute("LobbyRoomId")==id end,"enter "..id)
end
local function playing(id)
 return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("ActiveBattleRoomId")==id
end
local function battle(id)
 awaitFact(function() return playing(id) and player:GetAttribute("InLobby")==false and player.Character==nil end,"battle "..id,45)
 awaitFact(function() return #own(workspace.Buildings,player.UserId,"TownCenter")==1 and #own(workspace.Units,player.UserId)>=4 end,"geometry")
 awaitFact(function() return workspace:FindFirstChild("AOE2_Ground") and workspace.AOE2_Ground.Transparency==0 and workspace:FindFirstChild("Resources") and #workspace.Resources:GetChildren()>250 end,"battlefield resources replicated")
 check(workspace.StreamingEnabled==false,"battle ground/resources replicated")
 awaitFact(function() return workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable end,"battle camera")
 check(true,"automatic departure to fresh battlefield "..id)
end
local function lobbyView()
 local gui=player.PlayerGui:FindFirstChild("AOE2_MainGUI")
 local layer=gui and gui:FindFirstChild("LobbyLayer",true)
 local hud=gui and gui:FindFirstChild("HUD",true)
 return layer and layer.Visible and hud and not hud.Visible
end
task.spawn(function()
 local ok,err=pcall(function()
  awaitFact(function() return workspace:GetAttribute("RTSReady")==true and #Players:GetPlayers()==2 and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and lobbyView() end,"two clients initialized",60)
  local roster=Players:GetPlayers(); table.sort(roster,function(a,b) return a.Name<b.Name end)
  local leader,follower=roster[1],roster[2]
  local first=player==leader
  local initialGeneration=workspace:GetAttribute("MatchGeneration") or 0
  enter(first and "Room1" or "Room2")
  configure(first and "Room1" or "Room2",1)
  awaitFact(function() return room("Room1","Configured") and room("Room2","Configured") end,"separate rooms configured")
  check(room("Room1","HostUserId")==leader.UserId and room("Room2","HostUserId")==follower.UserId,"equivalent stations have independent hosts")
  if first then
   command:FireServer("LobbyReady",true,room("Room1","SettingsRevision")); battle("Room1")
   awaitFact(function() return room("Room2","ReadyPlayers")==1 end,"other room prepared during battle")
   check(follower:GetAttribute("InLobby")==true and follower:GetAttribute("LobbyRoomId")=="Room2","active battle preserved other waiting room")
   command:FireServer("Surrender")
   awaitFact(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,"first sandbox ended")
   command:FireServer("RestartMatch")
   awaitFact(function() return playing("Room2") and player:GetAttribute("InLobby")==true and player.Character end,"second room starts while first returns",45)
   awaitFact(function() return workspace.CurrentCamera.CameraType==Enum.CameraType.Custom and lobbyView() end,"waiting lobby camera/HUD")
   check(true,"waiting client keeps its lobby character, camera and HUD state")
   enter("Room3") -- Observable acknowledgement before the other client ends its short solo match.
  else
   awaitFact(function() return playing("Room1") end,"first room battle",45)
   command:FireServer("LobbyReady",true,room("Room2","SettingsRevision"))
   awaitFact(function() return player:GetAttribute("LobbyReady")==true end,"second room readiness")
   check(player:GetAttribute("InLobby")==true and player.Character~=nil and lobbyView(),"second client remains in its own waiting panel")
   awaitFact(function() return workspace.CurrentCamera.CameraType==Enum.CameraType.Custom end,"second waiting camera")
   battle("Room2")
   awaitFact(function() return leader:GetAttribute("InLobby")==true and leader.Character end,"leader returned to lobby")
   awaitFact(function() return room("Room3","HostUserId")==leader.UserId end,"leader verified waiting view")
   command:FireServer("Surrender")
   awaitFact(function() return workspace:GetAttribute("MatchPhase")=="Ended" end,"second sandbox ended")
   command:FireServer("RestartMatch")
  end
  awaitFact(function() return workspace:GetAttribute("MatchPhase")=="Lobby" and player:GetAttribute("InLobby")==true and player.Character end,"shared room setup after resets",45)
  if first then
   enter("Room3")
   awaitFact(function() return room("Room3","Players")==2 end,"both joined shared room")
   configure("Room3",2)
  else
   awaitFact(function() return room("Room3","HostUserId")==leader.UserId end,"shared room host")
   enter("Room3")
   awaitFact(function() return room("Room3","Configured")==true end,"host finished shared setup")
  end
  command:FireServer("LobbyReady",true,room("Room3","SettingsRevision")); battle("Room3")
  awaitFact(function() return #own(workspace.Buildings,leader.UserId,"TownCenter")==1 and #own(workspace.Buildings,follower.UserId,"TownCenter")==1 end,"both player bases synchronized")
  check((workspace:GetAttribute("MatchGeneration") or 0)>=initialGeneration+5,"each match gets a fresh generation")
  print(label.."SYNC generation="..workspace:GetAttribute("MatchGeneration").." seed="..workspace:GetAttribute("MapSeed"))
  if first then
   local home=player:GetAttribute("HomePosition")
   local worker=own(workspace.Units,player.UserId)[1]
   for _,unit in ipairs(own(workspace.Units,player.UserId)) do if unit:GetAttribute("UnitType")=="villager" then worker=unit; break end end
   local params=OverlapParams.new(); params.FilterType=Enum.RaycastFilterType.Include
   params.FilterDescendantsInstances={workspace.Buildings,workspace.Resources,workspace.Units}
   local position
   for radius=40,88,8 do
    for i=0,15 do
     local angle=i*math.pi/8
     local candidate=Grid.snap(home+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),Config.Buildings.House.size)
     if Grid.inBounds(candidate,Config.Buildings.House.size) and #workspace:GetPartBoundsInBox(CFrame.new(candidate+Vector3.new(0,7,0)),Vector3.new(15.8,14,15.8),params)==0 then position=candidate; break end
    end
    if position then break end
   end
   assert(position,label.."no house location")
   command:FireServer("Build","House",position,{worker})
   awaitFact(function() return #own(workspace.Buildings,player.UserId,"House")==1 end,"server created synchronized house")
   awaitFact(function() return follower:GetAttribute("Defeated")==true and workspace:GetAttribute("MatchPhase")=="Ended" end,"other player surrender resolves",45)
   awaitFact(function() return #own(workspace.Units,follower.UserId)==0 and #own(workspace.Buildings,follower.UserId)==0 end,"remote surrender cleanup replicated")
   check(true,"surrender cleans departing faction on both clients")
   check(#own(workspace.Buildings,player.UserId,"House")==1,"opponent could not delete host's house")
   print(label.."COMPLETE "..checks.." checks")
   player:Kick("大廳整合測試完成")
  else
   awaitFact(function() return #own(workspace.Buildings,leader.UserId,"House")==1 end,"remote house visible")
   local enemy=own(workspace.Buildings,leader.UserId,"House")[1]
   awaitFact(function() return leader:GetAttribute("wood")==1175 and player:GetAttribute("wood")==1200 end,"resource balances replicated")
   check(true,"server cost is independently synchronized")
   command:FireServer("Delete",{enemy},workspace:GetAttribute("MatchGeneration"))
   task.wait(0.5)
   check(enemy.Parent==workspace.Buildings,"other player's delete request is rejected")
   command:FireServer("Surrender")
   awaitFact(function() return player:GetAttribute("Defeated")==true and workspace:GetAttribute("MatchPhase")=="Ended" end,"surrender synchronized")
   awaitFact(function() return #own(workspace.Units,player.UserId)==0 and #own(workspace.Buildings,player.UserId)==0 end,"local surrender cleanup replicated")
   check(true,"local surrender cleans owned instances")
   print(label.."COMPLETE "..checks.." checks")
   awaitFact(function() return leader.Parent~=Players end,"leader leaves",20)
   player:Kick("大廳整合測試完成")
  end
 end)
 if not ok then warn(label.."FAIL "..tostring(err)) end
end)
