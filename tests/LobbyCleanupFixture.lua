-- Explicit SERVER fixture in an isolated Studio Play; no normal project mapping.
local Fixture={}
function Fixture.Run()
 assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsServer(),"僅限 Studio SERVER")
 assert(workspace:GetAttribute("MatchPhase")=="Lobby" and #game.Players:GetPlayers()==1,"需要新的單人 Play 大廳")
 local resources=workspace:FindFirstChild("Resources")
 assert(resources and not resources:FindFirstChild("使用者資源測試"),"測試 fixture 已存在或 Resources 未就緒")
 local function model(name,parent,nestedFlag)
  local m=Instance.new("Model"); m.Name=name; m:SetAttribute("LobbyCleanupFixture",true)
  if nestedFlag then m:SetAttribute("RTSManagedResource",true) end
  local p=Instance.new("Part"); p.Name="原有外觀"; p.Anchored=true
  p.CanCollide=false; p.CanQuery=false; p.CanTouch=false; p.Size=Vector3.new(3,3,3)
  p.Position=Vector3.new(0,5,0); p.Material=Enum.Material.Marble; p.Color=Color3.fromRGB(80,190,100)
  p.Parent=m; m.PrimaryPart=p; m.Parent=parent; return m
 end
 model("使用者資源測試",resources)
 local container=Instance.new("Folder"); container.Name="使用者資料夾測試"; container:SetAttribute("LobbyCleanupFixture",true); container.Parent=resources
 model("巢狀標記模型保留測試",container,true)
 local original=workspace:FindFirstChild("RTSScenery")
 if original then
  assert(original:GetAttribute("RTSManagedScenery")==true and not workspace:FindFirstChild("RTSManagedScenery"),"保留既有未知場景，不改名")
  original.Name="RTSManagedScenery"
 end
 local unknown=Instance.new("Folder"); unknown.Name="RTSScenery"; unknown:SetAttribute("LobbyCleanupFixture",true); unknown.Parent=workspace
 model("使用者場景測試",unknown)
 local RS=game.ReplicatedStorage
 local templates=RS:FindFirstChild("Buildings")
 if not templates then templates=Instance.new("Folder"); templates.Name="Buildings"; templates.Parent=RS end
 assert(not templates:FindFirstChild("使用者模型模板測試"),"測試模板已存在")
 model("使用者模型模板測試",templates)
 print("[LOBBY_CLEANUP_FIXTURE READY] temporary unknown direct/nested resource, scenery and template")
end
return Fixture
