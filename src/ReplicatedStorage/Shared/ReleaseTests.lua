-- Explicit new-session Studio client checks, using real remotes and actual PlayerGui.
local Tests={}
function Tests.Run()
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"只在新的 Studio 客戶端 Play 執行")
 local RS=game:GetService("ReplicatedStorage")
 local player=game.Players.LocalPlayer
 local Config=require(RS.GameData.GameConfig)
 local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
 local checks=0
 local function check(ok,message) assert(ok,"[RELEASE_TEST FAIL] "..message); checks+=1; print("[RELEASE_TEST PASS] "..message) end
 local function waitFor(predicate,seconds,message)
  local deadline=os.clock()+seconds
  repeat if predicate() then return end; task.wait(0.1) until os.clock()>deadline
  error("[RELEASE_TEST FAIL] "..message)
 end
 waitFor(function() return workspace:GetAttribute("RTSReady")==true and player:GetAttribute("Civilization")~=nil end,12,"初始化")
 check(workspace:GetAttribute("MatchPhase")=="Lobby","在新的大廳開始")
 check(workspace.StreamingEnabled==false,"完整地圖複製")
 check(workspace:GetAttribute("CommerceEnabled")==false,"未配置商店關閉")
 check(workspace:GetAttribute("ProfilesEnabled")==false and workspace:GetAttribute("AnalyticsEnabled")==false,"Studio 不讀寫正式雲端資料或分析")
 local original=player:GetAttribute("Civilization")
 command:FireServer("SelectCivilization",{})
 task.wait(0.2)
 command:FireServer("SelectCivilization","NotACivilization")
 task.wait(0.2)
 check(player:GetAttribute("Civilization")==original,"不合法文明無法覆寫")
 require(RS.Shared.LobbyTests).Join()
 command:FireServer("LobbyReady",true,workspace:GetAttribute("LobbySettingsRevision"))
 waitFor(function() return player:GetAttribute("LobbyReady")==true end,5,"準備")
 local nextCivilization=Config.CivilizationOrder[(table.find(Config.CivilizationOrder,original) or 1)%#Config.CivilizationOrder+1]
 command:FireServer("SelectCivilization",nextCivilization)
 waitFor(function() return player:GetAttribute("Civilization")==nextCivilization end,5,"文明選擇")
 check(player:GetAttribute("LobbyReady")==false,"切換文明清除準備")
 check(player:GetAttribute("CivilizationName")==Config.Civilizations[nextCivilization].name,"文明名稱由伺服器同步")
 local pg=player:WaitForChild("PlayerGui")
 waitFor(function() local screen=pg:FindFirstChild("AOE2_MainGUI"); return screen and screen:FindFirstChild("CivilizationButton",true) and screen:FindFirstChild("TutorialGuidance",true) end,5,"新版 UI")
 local screen=pg.AOE2_MainGUI
 check(screen:FindFirstChild("PracticeButton",true)~=nil,"實際 PlayerGui 有練習設定")
 require(RS.Shared.LobbyTests).Start({expectedPlayers=1,size="Small",aiCount=0,difficulty="Easy",population=60,startingResources="Rich",victory="Conquest"})
 waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("HomePosition")~=nil end,15,"開局")
 task.wait(0.3)
 check(player.Character==nil and workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable,"無角色 RTS 相機")
 check(player:GetAttribute("DeliveredResources")==0 and player:GetAttribute("TrainedUnits")==0,"新局教學事實歸零")
 command:FireServer("SelectCivilization",original)
 task.wait(0.3)
 check(player:GetAttribute("Civilization")==nextCivilization,"遊戲中不能改文明")
 for _,name in ipairs({"Buildings","Units"}) do
  local found=false
  for _,model in ipairs(workspace[name]:GetChildren()) do if model:GetAttribute("OwnerId")==player.UserId then found=true; check(model:GetAttribute("Civilization")==nextCivilization,name.." 文明身份複製") end end
  check(found,name.." 存在己方實例")
 end
 check(screen:FindFirstChild("TutorialGuidance",true).Visible or screen:FindFirstChild("GuidanceHint",true).Visible,"新手指引或橫向提示可見")
 require(RS.Shared.TouchTests).Run()
 print(string.format("[RELEASE_TEST COMPLETE] %d checks; gameplay construction follows separately",checks))
 return checks
end
return Tests
