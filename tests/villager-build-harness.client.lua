-- Test-only LocalScript, mapped only by villager-pages-validation.project.json.
-- Starts an isolated Studio match via normal lobby commands and checks the live PlayerGui.
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local function untilTrue(predicate,seconds,message)
 local deadline=os.clock()+seconds
 repeat if predicate() then return end; Run.Heartbeat:Wait() until os.clock()>deadline
 error("[BUILD_MENU_HARNESS FAIL] "..message)
end
untilTrue(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30,"初始化逾時")
require(RS.Shared.LobbyTests).Start({size="Small",aiCount=0,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest"})
untilTrue(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,30,"開始測試局逾時")
local hud=require(RS.Shared.HUDTests).Run()
local menu=require(RS.Shared.BuildMenuTests).Run()
local screen=player.PlayerGui.AOE2_MainGUI
local worker
for _,unit in ipairs(workspace.Units:GetChildren()) do if unit:GetAttribute("OwnerId")==player.UserId and unit:GetAttribute("UnitType")=="villager" then worker=unit; break end end
assert(worker,"測試局缺少村民")
screen.RTSSelectionProbe:Invoke({worker})
screen.RTSHUDProbe:Invoke("buildCategories")
print("[BUILD_MENU_HARNESS COMPLETE]",hud,menu,"touch",game:GetService("UserInputService").TouchEnabled)
-- Observe actual UI clicks after the automated render checks; do not synthesize activation.
-- Opt in before Play so an unattended render run does not fail waiting for a human click.
if workspace:GetAttribute("BuildMenuInteractiveTests")~=true then return end
screen.RTSHUDProbe:Invoke("buildPage",2)
print("[BUILD_MENU_CLICK WAIT] 先點灰色射箭場，再點兵營；之後會切到本機封建防禦頁，請點石牆。")
local building=require(RS.Shared.BuildingController)
local notice=screen:FindFirstChild("Notice",true)
untilTrue(function() local label=notice and notice:FindFirstChildWhichIsA("TextLabel"); return notice and notice.Visible and label and label.Text:find("需要封建時代",1,true) end,120,"等待實際點灰色射箭場")
assert(building.kind==nil,"[BUILD_MENU_CLICK FAIL] 灰色建築啟動預覽")
print("[BUILD_MENU_CLICK PASS] 灰色射箭場無法啟動建造預覽")
local function observe(kind,page)
 local deadline=os.clock()+120
 repeat Run.Heartbeat:Wait() until building.kind==kind or os.clock()>deadline
 assert(building.kind==kind,"[BUILD_MENU_CLICK FAIL] 等待實際按鈕 "..kind.." 逾時")
 local state=screen.RTSHUDProbe:Invoke()
 assert(state.page==page and state.buildCategory==page,"[BUILD_MENU_CLICK FAIL] 點建築後分類跳頁")
 print("[BUILD_MENU_CLICK PASS]",kind,"分類保留",page)
end
observe("Barracks",2)
building:Cancel()
local originalAge=player:GetAttribute("Age")
player:SetAttribute("Age",2) -- Local preview checks only; no server age progression is claimed.
screen.RTSHUDProbe:Invoke("buildPage",3)
observe("Wall",3)
building:Cancel(); player:SetAttribute("Age",originalAge)
