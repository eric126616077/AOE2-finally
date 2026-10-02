-- Explicit, temporary Studio SERVER fixture. Never mapped by the normal project.
local Fixture={}
function Fixture.Run()
 assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsServer(),"僅限 Studio SERVER")
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and workspace:GetAttribute("Sandbox")==true and workspace:GetAttribute("FactionCount")==1,"僅限新的單人沙盒")
 local player=game.Players:GetPlayers()[1]
 local home=player and player:GetAttribute("HomePosition")
 assert(typeof(home)=="Vector3","初始陣營尚未建立")
 local current=workspace:FindFirstChild("RTSScenery")
 if current then
  assert(current:GetAttribute("RTSManagedScenery")==true and not workspace:FindFirstChild("RTSManagedScenery"),"保留未知使用者資料夾，不改動它")
  current.Name="RTSManagedScenery"
 end
 local Config=require(game.ReplicatedStorage.GameData.GameConfig)
 local Grid=require(game.ReplicatedStorage.Shared.Grid)
 local location=Grid.snap(home+Vector3.new(64,0,48),Config.Buildings.House.size)
 local folder=Instance.new("Folder")
 folder.Name="RTSScenery"
 folder:SetAttribute("SceneryCollisionFixture",true)
 folder:SetAttribute("MatchGeneration",workspace:GetAttribute("MatchGeneration"))
 local wall=Instance.new("Part")
 wall.Name="測試使用者牆面"
 wall.Anchored=true; wall.CanCollide=true; wall.CanQuery=true; wall.CanTouch=false
 wall.Size=Vector3.new(8,12,40); wall.Position=location+Vector3.new(0,6,0)
 wall.Material=Enum.Material.Brick; wall.Color=Color3.fromRGB(194,96,60)
 wall.Parent=folder; folder.Parent=workspace
 print("[SCENERY_FIXTURE READY] temporary unknown-name wall",location,"managed flag",folder:GetAttribute("RTSManagedScenery"))
 return folder
end
return Fixture
