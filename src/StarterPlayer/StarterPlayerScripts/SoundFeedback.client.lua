local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local StarterGui=game:GetService("StarterGui")
local Audio=require(RS:WaitForChild("Shared"):WaitForChild("AudioFeedback"))
local Music=require(RS.Shared.MusicDirector)
local Rules=require(RS.Shared.FeedbackRules)
local Config=require(RS.GameData.GameConfig)
local player=Players.LocalPlayer
if script:GetAttribute("Initialized")==true or player:GetAttribute("RTSSoundReady")==true then return end
script:SetAttribute("Initialized",true)
local observers,folders,connections={},{},{}
local destroyed=false
local feedbackRevision=0
local alerts=Rules.newAlerts()
local mood=Rules.newMood()
local UI
local probe,musicProbe
if RunService:IsStudio() then
 probe=Instance.new("BindableFunction")
 probe.Name="RTSAudioProbe"
 probe.OnInvoke=function() return Audio:GetStats() end
 probe.Parent=script.Parent
 musicProbe=Instance.new("BindableFunction")
 musicProbe.Name="RTSMusicProbe"
 musicProbe.OnInvoke=function() return Music:GetStats() end
 musicProbe.Parent=script.Parent
end
-- Settings live on the local player; defaults are written once by GUIManager too.
for name,value in pairs({SoundEnabled=true,SoundVolume=1,MusicEnabled=true,MusicVolume=0.7}) do
 if player:GetAttribute(name)==nil then player:SetAttribute(name,value) end
end
local workCues={food="GatherFood",wood="GatherWood",gold="GatherGold",stone="GatherStone",build="BuildWork",repair="Repair"}
local function ui()
 if UI then return UI end
 local gui=StarterGui:FindFirstChild("GameUI")
 local module=gui and gui:FindFirstChild("GUIManager")
 if module then UI=require(module) end
 return UI
end
local function playing()
 return workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("InLobby")~=true
end
local function enabled()
 local value=player:GetAttribute("SoundEnabled")~=false
 if not value then feedbackRevision+=1 end
 Audio:SetEnabled(value)
end
local function volumes()
 Audio:SetVolume(player:GetAttribute("SoundVolume"))
 Music:SetSoundVolume(player:GetAttribute("SoundEnabled")==false and 0 or player:GetAttribute("SoundVolume"))
 Music:SetVolume(player:GetAttribute("MusicVolume"))
 Music:SetEnabled(player:GetAttribute("MusicEnabled")~=false)
end
-- Lobby court music, then the peaceful playlist in a match; dense fighting
-- involving your own forces turns it martial until the field goes quiet.
local function refreshMood()
 local phase=workspace:GetAttribute("MatchPhase")
 if player:GetAttribute("InLobby")==true or phase=="Lobby" or phase=="Starting" or phase==nil then
  Music:SetMood("Lobby"); Music:SetAmbience(false)
 elseif phase=="Playing" then
  Music:SetMood(Rules.UpdateMood(mood,os.clock())); Music:SetAmbience(true)
 else Music:SetMood("Peace"); Music:SetAmbience(true) end
end
local function combat()
 if not playing() then return end
 Rules.ReportCombat(mood,os.clock())
 refreshMood()
end
local function position(model)
 local ok,pivot=pcall(model.GetPivot,model)
 return ok and pivot.Position or nil
end
local function underAttack(model)
 local point=position(model)
 if not point or not Rules.Alert(alerts,os.clock(),point.X,point.Z) then return end
 local building=model:GetAttribute("BuildingType")~=nil
 -- Local-only attributes: the camera key and minimap read the latest alert.
 player:SetAttribute("RTSAlertPosition",point)
 player:SetAttribute("RTSAlertRevision",(player:GetAttribute("RTSAlertRevision") or 0)+1)
 Audio:Play("UnderAttack")
 local gui=ui()
 if gui and gui.screen then
  gui:Notify(building and "你的建築正遭受攻擊！按空白鍵前往。" or "你的部隊正遭受攻擊！按空白鍵前往。")
  if gui.PingMap then gui:PingMap(point) end
 end
end
local function untrack(model)
 local observer=observers[model]
 if not observer then return end
 observers[model]=nil
 for _,connection in ipairs(observer.connections) do connection:Disconnect() end
end
local function track(model)
 if not model:IsA("Model") or observers[model] then return end
 -- Establish baselines without replaying attributes from an existing/initial spawn.
 local observer={connections={},last={},hp=model:GetAttribute("HP"),carry=model:GetAttribute("CarryType")}
 observers[model]=observer
 for _,attribute in ipairs({"LastWork","LastDelivery","LastAttack"}) do
  observer.last[attribute]=model:GetAttribute(attribute)
  table.insert(observer.connections,model:GetAttributeChangedSignal(attribute):Connect(function()
   local value,previous=model:GetAttribute(attribute),observer.last[attribute]
   observer.last[attribute]=value
   if not playing() or not Rules.IsNewPulse(value,previous) then return end
   -- WorkKind and a work pulse can arrive in one replication batch. Read the
   -- committed kind afterward, and discard pulses superseded or reset meanwhile.
   local revision=feedbackRevision
   task.defer(function()
    if revision~=feedbackRevision or observers[model]~=observer or observer.last[attribute]~=value or not playing() then return end
    if attribute=="LastWork" then
     Audio:Play(workCues[model:GetAttribute("WorkKind")],model)
    elseif attribute=="LastDelivery" then Audio:Play(Rules.DeliveryCue(observer.carry),model)
    else
     local kind=model:GetAttribute("UnitType")
     local cue=Rules.AttackCue(kind,Config.Units[kind] or Config.Buildings[model:GetAttribute("BuildingType")])
     if cue then Audio:Play(cue,model) end
     if model:GetAttribute("OwnerId")==player.UserId then combat() end
    end
   end)
  end))
 end
 -- Delivery clears CarryType before the pulse; remember what was carried.
 table.insert(observer.connections,model:GetAttributeChangedSignal("CarryType"):Connect(function()
  local value=model:GetAttribute("CarryType")
  if type(value)=="string" and value~="" then observer.carry=value end
 end))
 table.insert(observer.connections,model:GetAttributeChangedSignal("HP"):Connect(function()
  local value,previous=model:GetAttribute("HP"),observer.hp
  observer.hp=value
  if type(value)~="number" or type(previous)~="number" or value>=previous or not playing() then return end
  if value<=0 then
   -- The server zeroes HP just before removal; sound it where the model stood.
   local point=position(model)
   if point then Audio:Play(model:GetAttribute("BuildingType") and "BuildingDestroyed" or "UnitDeath",point) end
  end
  if model:GetAttribute("OwnerId")==player.UserId then
   combat()
   underAttack(model)
  end
 end))
end
local function attachFolder(folder)
 if (folder.Name~="Units" and folder.Name~="Buildings") or folders[folder] then return end
 local bindings={}
 folders[folder]=bindings
 table.insert(bindings,folder.ChildAdded:Connect(track))
 table.insert(bindings,folder.ChildRemoved:Connect(untrack))
 for _,model in ipairs(folder:GetChildren()) do track(model) end
end
local function detachFolder(folder)
 local bindings=folders[folder]
 if not bindings then return end
 folders[folder]=nil
 for _,connection in ipairs(bindings) do connection:Disconnect() end
 for _,model in ipairs(folder:GetChildren()) do untrack(model) end
end
local function reset()
 feedbackRevision+=1
 Audio:StopAll()
 alerts=Rules.newAlerts()
 mood=Rules.newMood()
 -- Baseline current attributes when phases/generations change, including restart.
 for model,observer in pairs(observers) do
  for _,attribute in ipairs({"LastWork","LastDelivery","LastAttack"}) do observer.last[attribute]=model:GetAttribute(attribute) end
  observer.hp=model:GetAttribute("HP")
 end
 refreshMood()
end
table.insert(connections,player:GetAttributeChangedSignal("SoundEnabled"):Connect(function() enabled(); volumes() end))
for _,name in ipairs({"SoundVolume","MusicEnabled","MusicVolume"}) do
 table.insert(connections,player:GetAttributeChangedSignal(name):Connect(volumes))
end
table.insert(connections,player:GetAttributeChangedSignal("InLobby"):Connect(refreshMood))
table.insert(connections,workspace:GetAttributeChangedSignal("MatchPhase"):Connect(reset))
table.insert(connections,workspace:GetAttributeChangedSignal("MatchGeneration"):Connect(reset))
table.insert(connections,workspace.ChildAdded:Connect(attachFolder))
table.insert(connections,workspace.ChildRemoved:Connect(detachFolder))
-- Battle music cools down on a slow, bounded clock instead of per frame.
local moodClock=0
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
 moodClock+=dt
 if moodClock<1 then return end
 moodClock=0
 if playing() then refreshMood() end
end))
for _,name in ipairs({"Units","Buildings"}) do
 local folder=workspace:FindFirstChild(name)
 if folder then attachFolder(folder) end
end
Audio.OnStinger=function(duration) Music:Duck(duration) end
enabled()
volumes()
refreshMood()
Audio:Preload()
script.Destroying:Connect(function()
 destroyed=true
 for _,connection in ipairs(connections) do connection:Disconnect() end
 for folder in pairs(folders) do detachFolder(folder) end
 for model in pairs(observers) do untrack(model) end
 Audio:StopAll()
 Audio.OnStinger=nil
 Music:Destroy()
 if probe then probe:Destroy() end
 if musicProbe then musicProbe:Destroy() end
 player:SetAttribute("RTSSoundReady",false)
end)
local remotes=RS:WaitForChild("RTSRemotes")
local feedback=remotes:WaitForChild("Feedback")
if not destroyed then
 table.insert(connections,feedback.OnClientEvent:Connect(function(_,cue)
  -- A message can be nil for quiet accepted orders; never guess a cue from prose.
  if type(cue)=="string" then Audio:Play(cue) end
 end))
 player:SetAttribute("RTSSoundReady",true)
end
