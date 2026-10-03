-- Opt-in only through lobby-layout-validation.project.json; never mapped by the normal project.
-- Geometry checks for the lobby UI at desktop, tablet and phone canvas sizes: panels stay on screen,
-- controls do not overlap, text fits its label, touch targets are at least 44 px and scroll content
-- is reachable. It drives the live GUI module the game client already uses; it cannot judge looks.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then return end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local StarterGui=game:GetService("StarterGui")
local player=Players.LocalPlayer
local command=RS:WaitForChild("RTSRemotes"):WaitForChild("Command")
local probe=RS:WaitForChild("LobbyModesProbe",30)
local UI=require(StarterGui:WaitForChild("GameUI"):WaitForChild("GUIManager"))
local GameModes=require(RS.Shared.GameModeRules)
local Config=require(RS.GameData.GameConfig)
local label="[LOBBY_LAYOUT] "
local checks,failures=0,{}
local function check(ok,message)
 checks+=1
 if ok then print(label.."PASS "..message) else table.insert(failures,message); warn(label.."FAIL "..message) end
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

-- Canvas sizes after UIScale: desktop windows scale to roughly 1280 wide; touch devices use scale 1.
local SIZES={
 {name="desktop 1280x720",w=1280,h=720},
 {name="desktop 1454x818",w=1454,h=818},
 {name="short desktop 1366x620",w=1366,h=620},
 {name="tablet 1024x768",w=1024,h=768,touch=true},
 {name="phone 812x375",w=812,h=375,touch=true},
 {name="phone 667x375",w=667,h=375,touch=true},
 {name="phone 568x320",w=568,h=320,touch=true},
}
-- The game client creates the GUI (UI.scale / UI.canvas) in UI:Init; snapshot it once the lobby is ready.
local real
local function remember()
 real={scale=UI.scale.Scale,size=UI.canvas.Size,w=UI.layoutWidth,h=UI.layoutHeight}
end
local function applySize(size)
 UI.scale.Scale=1
 UI.canvas.Size=UDim2.fromOffset(size.w,size.h)
 UI.layoutWidth,UI.layoutHeight=size.w,size.h
 UI:LayoutLobby()
 -- RTSClient calls UI:Update every 0.15 s; panel visibility (e.g. the tutorial card rule) follows on that cadence.
 task.wait(0.4)
 UI:LayoutLobby()
 task.wait()
end
local function restoreSize()
 if not real then return end
 UI.scale.Scale,UI.canvas.Size,UI.layoutWidth,UI.layoutHeight=real.scale,real.size,real.w,real.h
 if UI.resize then UI.resize() end
end

local function shown(object)
 while object and not object:IsA("ScreenGui") do
  if object:IsA("GuiObject") and not object.Visible then return false end
  object=object.Parent
 end
 return object~=nil and object.Enabled
end
local function box(g)
 local p,s=g.AbsolutePosition,g.AbsoluteSize
 return {x0=p.X,y0=p.Y,x1=p.X+s.X,y1=p.Y+s.Y,w=s.X,h=s.Y}
end
local function inside(child,parent)
 local a,b=box(child),box(parent)
 return a.x0>=b.x0-1 and a.y0>=b.y0-1 and a.x1<=b.x1+1 and a.y1<=b.y1+1
end
local function overlaps(x,y)
 local a,b=box(x),box(y)
 return math.min(a.x1,b.x1)-math.max(a.x0,b.x0)>1 and math.min(a.y1,b.y1)-math.max(a.y0,b.y0)>1
end
local function named(g) return g.Name..(g:IsA("TextLabel") and (" \""..g.Text:sub(1,30).."\"") or "") end
local function textual(g) return g:IsA("TextButton") or (g:IsA("TextLabel") and g.Text~="") end

-- Every shown, non-empty label inside root must fit its own bounds.
local function textFits(root,tag)
 local bad={}
 for _,g in ipairs(root:GetDescendants()) do
  if g:IsA("TextLabel") and g.Text~="" and shown(g) and not g.TextScaled and not g.TextFits then table.insert(bad,named(g)) end
 end
 check(#bad==0,tag.." text fits"..(#bad>0 and (": "..table.concat(bad,", ")) or ""))
end
-- Shown text controls that are direct children of container must not overlap each other.
local function noOverlap(container,tag)
 local items,bad={},{}
 for _,g in ipairs(container:GetChildren()) do
  if g:IsA("GuiObject") and textual(g) and shown(g) then table.insert(items,g) end
 end
 for i=1,#items do for j=i+1,#items do
  if overlaps(items[i],items[j]) then table.insert(bad,named(items[i]).." / "..named(items[j])) end
 end end
 check(#bad==0,tag.." no overlap"..(#bad>0 and (": "..table.concat(bad,"; ")) or ""))
end
local function onCanvas(g,tag)
 check(shown(g) and inside(g,UI.canvas),tag.." inside the screen ("..math.floor(box(g).w).."x"..math.floor(box(g).h).." at "..math.floor(box(g).y0-box(UI.canvas).y0)..")")
end
local function childrenInside(container,tag)
 local bad={}
 for _,g in ipairs(container:GetChildren()) do
  if g:IsA("GuiObject") and textual(g) and shown(g) and not inside(g,container) then table.insert(bad,named(g)) end
 end
 check(#bad==0,tag.." controls inside their panel"..(#bad>0 and (": "..table.concat(bad,", ")) or ""))
end
local function touchTargets(root,tag,size)
 if not size.touch then return end
 local bad={}
 for _,g in ipairs(root:GetDescendants()) do
  if g:IsA("TextButton") and shown(g) and (g.AbsoluteSize.X<43.9 or g.AbsoluteSize.Y<43.9) then
   table.insert(bad,g.Name.." "..math.floor(g.AbsoluteSize.X).."x"..math.floor(g.AbsoluteSize.Y))
  end
 end
 check(#bad==0,tag.." touch targets >= 44 px"..(#bad>0 and (": "..table.concat(bad,", ")) or ""))
end
-- Everything placed on a scroll page must be reachable inside its canvas.
local function reachable(page,tag)
 local body=UI.lobbyBody
 local bottom,right=0,0
 for _,g in ipairs(page:GetChildren()) do
  if g:IsA("GuiObject") and textual(g) and shown(g) then
   local b=box(g)
   bottom=math.max(bottom,b.y1-body.AbsolutePosition.Y+body.CanvasPosition.Y)
   right=math.max(right,b.x1-body.AbsolutePosition.X)
  end
 end
 check(bottom<=body.AbsoluteCanvasSize.Y+1 and right<=body.AbsoluteSize.X+1,tag.." content reachable by scrolling (content "..math.floor(bottom).." / canvas "..math.floor(body.AbsoluteCanvasSize.Y)..")")
end
local function buttonInternals(container,tag)
 for _,b in ipairs(container:GetChildren()) do
  if b:IsA("TextButton") and shown(b) then noOverlap(b,tag.." "..b.Name) end
 end
end

local function welcomeChecks(size)
 local tag=size.name.." welcome"
 local welcome=UI.lobbyWelcome
 if not shown(welcome) then check(UI.tutorialInviteCovers==true,tag.." hidden only while the tutorial card needs the space"); return end
 onCanvas(welcome,tag)
 -- 「▶ 預告片」只在有影片時顯示；不論是否顯示，都檢查它擺放的位置（AbsolutePosition 照常計算）。
 local trailer=UI.trailerButton
 if trailer then
  check(inside(trailer,UI.canvas),tag.." trailer button inside the screen")
  check(not overlaps(trailer,welcome),tag.." trailer button clear of the welcome panel")
  check(not (shown(UI.inviteReopen) and overlaps(trailer,UI.inviteReopen)),tag.." trailer button clear of the tutorial button")
  check(not (shown(UI.tutorialInvite) and trailer.Visible),tag.." trailer button hidden while the tutorial card is open")
  check(not (shown(UI.noticePanel) and overlaps(trailer,UI.noticePanel)),tag.." trailer button clear of the notice")
 end
 check(box(welcome).h<=size.h*0.7,tag.." leaves the courtyard visible (panel "..math.floor(box(welcome).h).." of "..size.h.." px)")
 childrenInside(welcome,tag)
 noOverlap(welcome,tag)
 buttonInternals(welcome,tag)
 textFits(welcome,tag)
 touchTargets(welcome,tag,size)
 if shown(UI.tutorialInvite) then
  onCanvas(UI.tutorialInvite,size.name.." tutorial card")
  check(not overlaps(UI.tutorialInvite,welcome),size.name.." tutorial card does not cover the welcome panel")
  textFits(UI.tutorialInvite,size.name.." tutorial card")
 end
end
local function wizardChecks(size,state)
 local tag=size.name.." "..state
 local frame=UI.lobbyFrame
 onCanvas(frame,tag.." room panel")
 noOverlap(frame,tag.." header")
 noOverlap(UI.lobbyFooter,tag.." footer")
 childrenInside(UI.lobbyFooter,tag.." footer")
 local page=UI.lobbyPages[UI.lobbyPage]
 noOverlap(page,tag.." page "..UI.lobbyPage)
 buttonInternals(page,tag.." page "..UI.lobbyPage)
 reachable(page,tag.." page "..UI.lobbyPage)
 if UI.wizardSteps.Visible then noOverlap(UI.wizardSteps,tag.." steps") end
 textFits(frame,tag)
 touchTargets(frame,tag,size)
end
local function eachSize(fn,...)
 for _,size in ipairs(SIZES) do applySize(size); fn(size,...) end
 restoreSize()
end
local function setPage(page)
 if UI.lobbyWizard then UI:SetLobbyPage(page) end
 task.wait()
end
local function propose(id,mode)
 local current={gameMode=room(id,"Setting_gameMode"),storyChapter=room(id,"Setting_storyChapter"),expectedPlayers=room(id,"ExpectedPlayers")}
 for _,key in ipairs({"size","aiCount","difficulty","population","startingResources","victory","teamMode"}) do current[key]=room(id,"Setting_"..key) end
 local request=GameModes.next(current,"gameMode",{mode},1,GameModes.unlocked(player:GetAttribute("StoryCleared")))
 local revision=room(id,"SettingsRevision")
 command:FireServer("LobbySettings",request)
 await(function() return room(id,"SettingsRevision")~=revision and room(id,"Setting_gameMode")==mode and UI.settings.gameMode==mode end,"room switched to "..mode)
end

local function run()
 await(function() return workspace:GetAttribute("RTSReady")==true and workspace:GetAttribute("MatchPhase")=="Lobby"
  and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and UI.scale and UI.canvas and UI.lobby and UI.lobby.Visible end,"lobby ready",60)
 task.wait(1)
 remember()
 -- 1. Welcome panel, first with the first-visit tutorial card, then after "later".
 eachSize(welcomeChecks)
 UI.inviteDismissed=true; UI.inviteForced=nil; task.wait(0.3)
 eachSize(welcomeChecks)

 -- 2-3. Room wizard in each mode and page, then the configured review page.
 command:FireServer("QueueJoin","Room1")
 await(function() return player:GetAttribute("LobbyRoomId")=="Room1" and UI.lobbyWizard end,"host wizard open")
 for _,mode in ipairs({"PvP","Story","PvE"}) do
  if UI.settings.gameMode~=mode then propose("Room1",mode) end
  for page=1,2 do
   setPage(page)
   eachSize(function(size) setPage(page); wizardChecks(size,mode.." wizard") end)
  end
 end
 propose("Room1","Story")
 command:FireServer("LobbyConfigureComplete",room("Room1","SettingsRevision"))
 await(function() return room("Room1","Configured")==true and not UI.lobbyWizard and UI.lobbyPage==3 end,"review page")
 eachSize(function(size) wizardChecks(size,"Story review") end)

 -- 4. Plaza portal sign for the configured room.
 local lobbyFolder
 for _,child in ipairs(workspace:GetChildren()) do if child:FindFirstChild("Portal_Room1",true) then lobbyFolder=child; break end end
 local sign=lobbyFolder and lobbyFolder:FindFirstChild("Portal_Room1",true)
 local mode=sign and sign:FindFirstChild("Mode",true)
 await(function() return mode and mode.Text:find(GameModes.label({gameMode="Story",storyChapter=1}),1,true) end,"portal sign shows the room mode",10)
 check(mode.TextScaled and mode.Parent and mode.Parent:IsA("GuiObject"),"portal sign mode label scales with its card")
 local count=mode.Parent:FindFirstChild("Count")
 check(count and not overlaps(mode,count),"portal sign mode and count lines do not overlap")
 print(label.."INFO portal sign text: "..mode.Text)

 -- 5. Story start and chapter victory notices.
 command:FireServer("QueueLeave")
 await(function() return player:GetAttribute("LobbyQueued")==false end,"left room")
 task.wait(2.3)
 command:FireServer("QuickPlay","StorySolo")
 local chapter=Config.Story.chapters[1]
 await(function() return UI.notice.Text:find(chapter.objective,1,true) and UI.noticePanel.Visible end,"story start notice shown",60)
 local function noticeChecks(tag)
  onCanvas(UI.noticePanel,tag.." notice")
  check(UI.notice.TextFits,tag.." notice text fits ("..math.floor(UI.notice.TextBounds.Y).." px text in "..math.floor(UI.notice.AbsoluteSize.Y).." px)")
 end
 noticeChecks("story start")
 print(label.."INFO start notice: "..UI.notice.Text:gsub("\n"," / "))
 task.wait(3)
 probe:FireServer("DefeatAI")
 await(function() return UI.notice.Text:find("已解鎖第 2 章",1,true) end,"chapter unlock notice shown",30)
 noticeChecks("chapter unlock")
 if UI.result and shown(UI.result) then
  onCanvas(UI.result,"victory result")
  textFits(UI.result,"victory result")
 end
end

task.spawn(function()
 local ok,err=pcall(run)
 restoreSize()
 if not ok then warn(tostring(err)) end
 print(label..(ok and "DONE " or "STOPPED ")..checks.." checks, "..#failures.." failed")
 for _,message in ipairs(failures) do print(label.."FAILED: "..message) end
end)
