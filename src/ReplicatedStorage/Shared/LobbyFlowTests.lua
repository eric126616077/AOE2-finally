-- Explicit Studio CLIENT integration checks. Run only in a fresh solo Play session.
-- This configures equivalent rooms, checks the real wizard, and starts a solo match.
local Tests={}
function Tests.Run()
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"僅限新 Studio Play 工作階段的客戶端")
 local Players=game:GetService("Players")
 local ReplicatedStorage=game:GetService("ReplicatedStorage")
 local player=Players.LocalPlayer
 local Config=require(ReplicatedStorage.GameData.GameConfig)
 local command=ReplicatedStorage:WaitForChild("RTSRemotes"):WaitForChild("Command")
 local checks=0
 local function check(ok,message)
  assert(ok,"[LOBBY_FLOW FAIL] "..message)
  checks+=1
  print("[LOBBY_FLOW PASS] "..message)
 end
 local function untilTrue(predicate,seconds,message)
  local deadline=os.clock()+seconds
  repeat
   if predicate() then check(true,message); return end
   task.wait(0.1)
  until os.clock()>deadline
  check(false,message)
 end
 local function settle() task.wait(math.max(0.35,Config.Lobby.scanInterval*2)) end
 local function actualGui() return player.PlayerGui:FindFirstChild("AOE2_MainGUI") end
 local function lobbyGui()
  local gui=actualGui()
  return gui and gui:FindFirstChild("LobbyLayer",true)
 end
 local function visibleInTree(object)
  if not object or not object.Parent then return false end
  while object do
   if object:IsA("GuiObject") and not object.Visible then return false end
   if object:IsA("ScreenGui") and not object.Enabled then return false end
   object=object.Parent
  end
  return true
 end
 local function room(id,key) return workspace:GetAttribute("LobbyRoom_"..id.."_"..key) end
 local pageNames={"BasicSettingsPage","AdvancedSettingsPage","ReadyReviewPage"}
 local function visiblePageCount(panel)
  local count=0
  for _,name in ipairs(pageNames) do
   local page=panel:FindFirstChild(name,true)
   assert(page,"設定精靈頁面不存在："..name)
   if page.Visible then count+=1 end
  end
  return count
 end
 local function waitForAck(previous,accepted,message)
  untilTrue(function()
   return (player:GetAttribute("LobbyConfigureAck") or 0)>previous
    and player:GetAttribute("LobbyConfigureAccepted")==accepted
  end,5,"伺服器回覆設定確認")
  check(player:GetAttribute("LobbyConfigureAccepted")==accepted,message)
 end
 untilTrue(function() return workspace:GetAttribute("RTSReady")==true end,15,"伺服器完成初始化")
 check(workspace:GetAttribute("MatchPhase")=="Lobby" and #Players:GetPlayers()==1,"測試從新的單人大廳開始")
 check(not workspace.StreamingEnabled,"大廳與戰場完整複製")
 untilTrue(function() return actualGui() and lobbyGui() end,8,"實際 PlayerGui 已掛載大廳")
 untilTrue(function() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end,15,"大廳角色已載入")
 untilTrue(function() return workspace.CurrentCamera.CameraType==Enum.CameraType.Custom end,5,"入場使用角色相機")
 local lobby=workspace:FindFirstChild("AOE2_LobbyWorld")
 check(lobby~=nil,"大廳廣場已複製")
 local layer=lobbyGui()
 local welcome=layer:FindFirstChild("CourtyardWelcome")
 check(welcome and welcome.Visible,"入場顯示匹配入口")
 for _,data in ipairs(Config.Lobby.portals) do
  local id=data.id
  local card=welcome:FindFirstChild("PortalCard_"..id,true)
  check(card and card:IsA("TextButton"),"實際介面提供傳送門卡片："..id)
  local portal=lobby:FindFirstChild("Portal_"..id)
  check(portal and portal:GetAttribute("PortalId")==id and portal:FindFirstChild("PortalDais"),"場景提供獨立傳送門："..id)
  check(room(id,"Configured")==false and room(id,"ExpectedPlayers")==data.settings.expectedPlayers and room(id,"Setting_gameMode")==data.settings.gameMode,"新房間依傳送門玩法等候房主設定："..id)
 end
 check(welcome:FindFirstChild("QuickPlay_PvP",true)==nil and layer:FindFirstChild("ModeCard_PvP",true)==nil,"大廳不再提供玩法切換按鈕")
 check(player:GetAttribute("InLobby")==true,"入場狀態仍在大廳")
 local initialGeneration=workspace:GetAttribute("MatchGeneration") or 0
 command:FireServer("QueueJoin","Unknown")
 settle()
 check(player:GetAttribute("LobbyQueued")~=true,"無效匹配點請求不會入隊")
 command:FireServer("QueueJoin")
 settle()
 check(player:GetAttribute("LobbyQueued")~=true,"未接近傳送門的舊版請求不會入隊")
 command:FireServer("QueueJoin","Room2")
 untilTrue(function() return player:GetAttribute("LobbyRoomId")=="Room2" end,5,"加入第二個等價匹配點")
 local panel=layer:FindFirstChild("MatchLobby")
 untilTrue(function() return panel.Visible and panel:GetAttribute("RoomId")=="Room2" and panel:GetAttribute("Configurable")==true end,5,"第二個匹配點同樣可以設定")
 local secondRevision=room("Room2","SettingsRevision")
 local setup={expectedPlayers=2,size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"}
 command:FireServer("LobbySettings",setup)
 untilTrue(function() return room("Room2","SettingsRevision")~=secondRevision and room("Room2","Setting_size")=="Small" end,5,"第二個匹配點接受自己的房主設定")
 command:FireServer("LobbyConfigureComplete",room("Room2","SettingsRevision"))
 untilTrue(function() return room("Room2","Configured")==true end,5,"第二個匹配點可以完成設定")
 check(room("Room1","Configured")==false and room("Room1","Setting_size")=="Medium","第二個匹配點設定不影響第一個")
 command:FireServer("QueueLeave")
 untilTrue(function() return player:GetAttribute("LobbyQueued")==false and room("Room2","Configured")==false and room("Room2","Setting_size")=="Medium" end,5,"空房間重置為待設定的共同預設")
 task.wait(2.1)
 command:FireServer("QueueJoin","Room1")
 untilTrue(function() return player:GetAttribute("LobbyRoomId")=="Room1" end,5,"從廣場加入第一個匹配點")
 untilTrue(function() return panel.Visible and panel:GetAttribute("RoomId")=="Room1" and panel:GetAttribute("WizardPage")==1 end,5,"房主設定精靈從第一頁開始")
 check(visiblePageCount(panel)==1 and panel:FindFirstChild(pageNames[1],true).Visible,"設定精靈一次只顯示第一頁")
 local basic=panel:FindFirstChild(pageNames[1],true)
 check(basic:FindFirstChild("Setting_teamMode",true) and basic:FindFirstChild("Setting_expectedPlayers",true),"第一頁先設定模式與真人數")
 local hudProbe=actualGui():FindFirstChild("RTSHUDProbe")
 check(hudProbe and hudProbe:IsA("BindableFunction"),"Studio 檢查接到目前實際 HUD 實例")
 local browsingRevision=room("Room1","SettingsRevision")
 for _,index in ipairs({2,1,2}) do
  check(hudProbe:Invoke("lobbyPage",index)==true,"實際設定精靈可以切換第 "..index.." 頁")
  untilTrue(function() return panel:GetAttribute("WizardPage")==index end,3,"精靈頁碼與目前頁面同步")
  check(visiblePageCount(panel)==1 and panel:FindFirstChild(pageNames[index],true).Visible,"切頁只保留目前表單")
 end
 check(room("Room1","SettingsRevision")==browsingRevision,"單純瀏覽設定頁不改變伺服器配置")
 check(not panel:FindFirstChild("ReadyButton",true).Visible,"完成設定前不顯示準備操作")
 local viewport=workspace.CurrentCamera.ViewportSize
 check(panel.AbsolutePosition.X>=0 and panel.AbsolutePosition.Y>=0 and panel.AbsolutePosition.X+panel.AbsoluteSize.X<=viewport.X+1 and panel.AbsolutePosition.Y+panel.AbsoluteSize.Y<=viewport.Y+1,"設定面板位於客戶端安全畫面內")
 for _,name in ipairs({"NextLobbyPage","PreviousLobbyPage","CompleteLobbySetup","ReadyButton","LeaveQueueButton"}) do
  check(panel:FindFirstChild(name,true)~=nil,"分階段操作存在："..name)
 end
 command:FireServer("LobbyReady",true,room("Room1","SettingsRevision"))
 settle()
 check(player:GetAttribute("LobbyReady")==false,"完成設定前不能確認準備")
 local previousRevision=room("Room1","SettingsRevision")
 setup.expectedPlayers=1
 command:FireServer("LobbySettings",setup)
 untilTrue(function() return room("Room1","SettingsRevision")~=previousRevision and room("Room1","ExpectedPlayers")==1 end,5,"單人測試設定由伺服器套用")
 check(room("Room1","Configured")==false,"更改設定需要房主重新確認")
 local ack=player:GetAttribute("LobbyConfigureAck") or 0
 command:FireServer("LobbyConfigureComplete",previousRevision)
 waitForAck(ack,false,"舊設定版本不能完成房間設定")
 check(room("Room1","Configured")==false and not player:GetAttribute("LobbyReady"),"過期確認不會進入等待或準備")
 local invalid=table.clone(setup); invalid.roomId="Room2"
 local configuredRevision=room("Room1","SettingsRevision")
 command:FireServer("LobbySettings",invalid)
 settle()
 check(room("Room1","SettingsRevision")==configuredRevision and room("Room2","Setting_size")=="Medium","偽造房間欄位不覆蓋任何配置")
 -- Commit through the real mounted GUI closure, just as its completion button does.
 untilTrue(function() return panel:GetAttribute("WizardPage")==2 end,3,"完成設定前停在第二頁")
 check(hudProbe:Invoke("lobbyConfigureComplete")==true,"實際 HUD 完成設定操作可送出確認")
 untilTrue(function() return room("Room1","Configured")==true and panel:GetAttribute("WizardPage")==3 end,8,"房主確認後切換玩家等待面板")
 check(visiblePageCount(panel)==1 and panel:FindFirstChild(pageNames[3],true).Visible,"等待階段只顯示名單與準備頁")
 check(panel:FindFirstChild("ReadyButton",true).Visible and not panel:FindFirstChild("CompleteLobbySetup",true).Visible,"完成設定後顯示準備操作")
 check(panel:FindFirstChild("StartMatchButton",true)==nil,"等待面板不需手動開始戰局")
 local travel=layer:FindFirstChild("StartingTravel")
 check(travel~=nil,"入場介面提供前往戰場的轉場面板")
 local observedStarting=false
 local transition=workspace:GetAttributeChangedSignal("MatchPhase"):Connect(function()
  if workspace:GetAttribute("MatchPhase")=="Starting" then observedStarting=true end
 end)
 command:FireServer("LobbyReady",true,room("Room1","SettingsRevision"))
 local ok,message=pcall(function()
  untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("HomePosition")~=nil end,30,"確認設定並準備後自動進入新戰場")
 end)
 transition:Disconnect()
 assert(ok,message)
 -- A one-frame stage may be coalesced by replication; record it without rejecting a completed match.
 print("[LOBBY_FLOW OBSERVE] StartingReceived="..tostring(observedStarting))
 untilTrue(function()
  return workspace:GetAttribute("ActiveBattleRoomId")=="Room1"
   and (workspace:GetAttribute("MatchGeneration") or 0)>initialGeneration
 end,8,"開局使用新的戰場版本")
 untilTrue(function() return player:GetAttribute("InLobby")==false and player.Character==nil end,8,"參戰玩家離開大廳角色")
 untilTrue(function() return player:GetAttribute("LobbyQueued")==false and player:GetAttribute("LobbyRoomId")==nil end,8,"開局消耗所選房間的入隊狀態")
 untilTrue(function() return workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable end,5,"抵達戰場切換 RTS 相機")
 local ground
 untilTrue(function()
  ground=workspace:FindFirstChild("AOE2_Ground")
  return ground and ground:IsA("BasePart") and ground.Transparency==0
 end,10,"新戰場地面真實複製可見")
 untilTrue(function()
  return ground.Size.X==Config.Map.Sizes.Small and ground.Size.Z==Config.Map.Sizes.Small
 end,8,"房主規則建立對應大小的新地圖")
 local home=player:GetAttribute("HomePosition")
 check(math.abs(home.X)<ground.Size.X/2 and math.abs(home.Z)<ground.Size.Z/2 and (home-Config.Lobby.origin).Magnitude>1000,"玩家陣營位於與大廳分離的戰場")
 untilTrue(function()
  local resourceFolder=workspace:FindFirstChild("Resources")
  local count=workspace:GetAttribute("ResourceNodeCount")
  return resourceFolder and #resourceFolder:GetChildren()>250 and type(count)=="number" and count>250
 end,20,"新戰場已有伺服器生成的資源")
 local base,worker
 untilTrue(function()
  local buildings,units=workspace:FindFirstChild("Buildings"),workspace:FindFirstChild("Units")
  if not buildings or not units then return false end
  base,worker=nil,nil
  for _,model in ipairs(buildings:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType")=="TownCenter" then base=model; break end
  end
  for _,model in ipairs(units:GetChildren()) do
   if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("UnitType")=="villager" then worker=model; break end
  end
  return base and base.PrimaryPart and base.PrimaryPart:IsDescendantOf(base)
   and worker and worker.PrimaryPart and worker.PrimaryPart:IsDescendantOf(worker)
 end,20,"城鎮中心與村民具有實際幾何")
 untilTrue(function()
  local gui=actualGui()
  local hud=gui and gui:FindFirstChild("HUD",true)
  return visibleInTree(hud) and not visibleInTree(panel)
   and not visibleInTree(welcome) and not visibleInTree(travel)
 end,5,"實際 PlayerGui 顯示 RTS HUD 並收起大廳與轉場")
 print(string.format("[LOBBY_FLOW COMPLETE] %d checks",checks))
 return checks
end
return Tests
