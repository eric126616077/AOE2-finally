-- Explicit Studio-only client helper. Moves the test avatar and changes room settings.
local Tests={}
local function client()
 assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsClient(),"僅限 Studio 客戶端")
 return game.Players.LocalPlayer,game.ReplicatedStorage.RTSRemotes.Command
end
local function attribute(roomId,key) return "LobbyRoom_"..roomId.."_"..key end
local function waitFor(predicate,seconds,message)
 local deadline=os.clock()+seconds
 repeat
  if predicate() then return end
  task.wait(0.1)
 until os.clock()>deadline
 error(message)
end
function Tests.Join(roomId)
 local player,command=client()
 local Config=require(game.ReplicatedStorage.GameData.GameConfig)
 roomId=roomId or "Room1"
 waitFor(function() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end,15,"大廳角色未載入")
 local selected
 for _,portal in ipairs(Config.Lobby.portals) do if portal.id==roomId then selected=portal end end
 assert(selected,"測試匹配點不存在")
 player.Character:PivotTo(CFrame.new(Config.Lobby.origin+selected.offset+Vector3.new(0,4,0)))
 local deadline=os.clock()+15
 while player:GetAttribute("LobbyQueued")~=true or player:GetAttribute("LobbyRoomId")~=roomId do
  assert(os.clock()<deadline,"未加入匹配點")
  command:FireServer("QueueJoin",roomId)
  task.wait(0.3)
 end
 return roomId
end
function Tests.ConfigureComplete()
 local player,command=client()
 local roomId=assert(player:GetAttribute("LobbyRoomId"),"測試玩家尚未入隊")
 command:FireServer("LobbyConfigureComplete",workspace:GetAttribute(attribute(roomId,"SettingsRevision")))
 waitFor(function() return workspace:GetAttribute(attribute(roomId,"Configured"))==true end,8,"房主未確認房間設定")
 return roomId
end
function Tests.Start(settings)
 local roomId=Tests.Join()
 local player,command=client()
 settings=table.clone(settings)
 settings.expectedPlayers=settings.expectedPlayers or 1
 local revision=workspace:GetAttribute(attribute(roomId,"SettingsRevision"))
 command:FireServer("LobbySettings",settings)
 waitFor(function() return workspace:GetAttribute(attribute(roomId,"SettingsRevision"))~=revision end,8,"設定未通過伺服器驗證")
 Tests.ConfigureComplete()
 command:FireServer("LobbyReady",true,workspace:GetAttribute(attribute(roomId,"SettingsRevision")))
 -- Automatic start consumes LobbyReady immediately; phase is also a successful result.
 waitFor(function()
  local phase=workspace:GetAttribute("MatchPhase")
  return player:GetAttribute("LobbyReady")==true or phase=="Starting" or phase=="Playing"
 end,12,"玩家未完成準備或開局")
end
function Tests.Run()
 local roomId=Tests.Join()
 local player,command=client()
 local checks=0
 local function check(ok,message) assert(ok,"[LOBBY_TEST FAIL] "..message); checks+=1; print("[LOBBY_TEST PASS] "..message) end
 check(workspace:FindFirstChild("AOE2_LobbyWorld")~=nil,"城堡廣場複製到客戶端")
 check(player.Character~=nil,"大廳角色可載入")
 check(workspace.CurrentCamera.CameraType==Enum.CameraType.Custom,"大廳使用角色相機")
 check(workspace:GetAttribute(attribute(roomId,"HostUserId"))==player.UserId,"首位集合玩家成為房主")
 command:FireServer("LobbyReady",true,workspace:GetAttribute(attribute(roomId,"SettingsRevision")))
 task.wait(0.4)
 check(workspace:GetAttribute("MatchPhase")=="Lobby" and not player:GetAttribute("LobbyReady"),"未完成設定不能準備開局")
 local settings={expectedPlayers=2,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"}
 local before=workspace:GetAttribute(attribute(roomId,"SettingsRevision"))
 command:FireServer("LobbySettings",settings)
 waitFor(function() return workspace:GetAttribute(attribute(roomId,"SettingsRevision"))~=before end,8,"測試設定未套用")
 Tests.ConfigureComplete()
 command:FireServer("LobbyReady",true,workspace:GetAttribute(attribute(roomId,"SettingsRevision")))
 task.wait(0.4)
 check(workspace:GetAttribute("MatchPhase")=="Lobby","單人不能開兩人集合局")
 settings.expectedPlayers=1
 command:FireServer("LobbySettings",settings)
 waitFor(function() return workspace:GetAttribute(attribute(roomId,"Configured"))==false end,8,"變更設定未重置確認狀態")
 check(player:GetAttribute("LobbyReady")==false,"修改配置重置準備")
 command:FireServer("LobbyConfigureComplete",workspace:GetAttribute(attribute(roomId,"SettingsRevision"))-1)
 command:FireServer("LobbyReady",true,workspace:GetAttribute(attribute(roomId,"SettingsRevision")))
 task.wait(0.4)
 check(workspace:GetAttribute(attribute(roomId,"Configured"))==false and player:GetAttribute("LobbyReady")==false,"舊配置確認與未確認準備請求被拒絕")
 local revision=workspace:GetAttribute(attribute(roomId,"SettingsRevision"))
 settings.size="Invalid"
 command:FireServer("LobbySettings",settings)
 task.wait(0.4)
 check(workspace:GetAttribute(attribute(roomId,"SettingsRevision"))==revision and workspace:GetAttribute(attribute(roomId,"Setting_size"))=="Small","無效設定沒有覆蓋配置")
 settings.size="Small"
 Tests.Start(settings)
 waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" end,30,"開局逾時")
 check(player.Character==nil,"開局後移除大廳角色")
 waitFor(function() return workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable end,5,"RTS 相機尚未切換")
 check(workspace:GetAttribute("MatchSizeName")=="Small" and player:GetAttribute("wood")==1200,"套用已確認的配置")
 print(string.format("[LOBBY_TEST COMPLETE] %d checks",checks))
 return checks
end
return Tests
