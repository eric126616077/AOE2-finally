-- Engine/service doubles only; verify.ps1 injects the real server lobby functions below.
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local vectorMeta={}
vectorMeta.__add=function(a,b) return setmetatable({X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z},vectorMeta) end
local Vector3={new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end}
local function actor(id,class)
 local result={UserId=id,Name="Actor_"..id,DisplayName="Actor "..id,class=class or "Player",attributes={}}
 function result:IsA(kind) return kind==self.class end
 function result:SetAttribute(key,value) self.attributes[key]=value end
 function result:GetAttribute(key) return self.attributes[key] end
 function result:Destroy() self.Parent=nil; self.destroyed=true end
 return result
end
local Players={}
local workspace={attributes={}}
function workspace:SetAttribute(key,value) self.attributes[key]=value end
function workspace:GetAttribute(key) return self.attributes[key] end
local task={spawn=function() end,defer=function(callback,...) callback(...) end,wait=function() end}
local Instance={new=function(class) return actor(-1,class) end}
local HttpService={GenerateGUID=function() return "actual-lobby-test-match" end}
local telemetry={Fact=function() end,Match=function() end}
local profiles={enabled=false}
local ProfileRules={eligible=function() return false end}
local MatchReportRules={New=function() return {} end}
local RunService={Heartbeat={Wait=function() end}}
local CivilizationPreferenceRules={takeLobby=function() return nil end}
local Rules=MatchRules
local colors={"blue","red","gold","purple"}
local states,byId={},{}
local phase,matchStart,matchGeneration,startingSides="Lobby",0,0,0
local joinSequence=0
local settings={}
local expectedPlayers,lobbyRevision=1,0
local rooms={}
local activeRoomId
local currentMatch,matchTeams
local queueJoin,queueLeave,spawnLobby,startMatch,autoStartLobby
local Travel={role="Combined"}
local resources={}
function resources:GetChildren() return {} end
local managedResources={}
local factions={}
local orders,training,construction,researching={},{},{},{}
local actionClocks={}
local AutoWork={units={}}
local reportSequence,reportSubjectSequence=0,0
local reportSubjects={}
local generatedMaps=0
local announcements,notifications={},{}
local function notify(player,message) table.insert(notifications,{player=player,message=message}) end
local function announce(message) table.insert(announcements,message) end
local function warn() end
local function setPhase(value) phase=value; workspace:SetAttribute("MatchPhase",value) end
local lobbyWorld={statuses={}}
function lobbyWorld:NearPortal(player,id) return player.nearRoom==id end
function lobbyWorld:ContainsPortal(player,id) return player.containedRoom==id end
function lobbyWorld:PortalForPlayer(player) return player.containedRoom end
function lobbyWorld:SpawnCFrame() return {spawn=true} end
function lobbyWorld:QueueCFrame(index,count,id) return {roomId=id,index=index,count=count} end
function lobbyWorld:SetStatus(count,expected,ready,currentPhase,id)
 self.statuses[id]={count=count,expected=expected,ready=ready,phase=currentPhase}
end
local function livingCharacter(player)
 local root={Anchored=false}
 function root:IsA(kind) return kind=="BasePart" end
 local humanoid={Health=100,WalkSpeed=16,AutoRotate=true}
 local character={root=root,humanoid=humanoid}
 function character:FindFirstChild(name) return name=="HumanoidRootPart" and self.root or nil end
 function character:FindFirstChildOfClass(kind) return kind=="Humanoid" and self.humanoid or nil end
 function character:PivotTo(position)
  self.pivot=position
  if position.roomId then player.nearRoom=position.roomId; player.containedRoom=position.roomId end
 end
 function character:Destroy() self.destroyed=true end
 return character
end
local function addHuman(id,joined)
 local player=actor(id)
 player.Parent=Players
 player.Character=livingCharacter(player)
 player:SetAttribute("InLobby",true)
 local state={id=id,actor=player,joined=joined or id,ai=false,inLobby=true,playing=false,units={},buildings={},civilization=Config.DefaultCivilization}
 states[player],byId[id]=state,state
 return state
end
local function resetActor(state)
 state.resetCalls=(state.resetCalls or 0)+1
 state.playing=false
 state.units,state.buildings={},{}
 state.actor:SetAttribute("HomePosition",nil)
end
local Factory={cleared=0}
function Factory.clearCorpses() Factory.cleared+=1 end
local function stop(model) orders[model]=nil end
local function destroyModel(model)
 for _,state in pairs(states) do state.units[model]=nil; state.buildings[model]=nil end
 model:Destroy()
end
local function clearReport(state) state.report=nil end
local function publishCivilization() end
local function publishTeam(state,player) player:SetAttribute("TeamId",TeamRules.team(matchTeams,state.id)) end
local function plannedAIIds(count)
 local result={}
 for index=1,count do result[index]=-10000-index end
 return result
end
local function makeResource() end
local function makeBuilding(state)
 local model=actor(state.id,"Model")
 state.buildings[model]=true
 return model
end
local function makeUnit(state)
 local model=actor(state.id,"Model")
 state.units[model]=true
 return model
end
local function population() end
local function matchContext() return {} end
local World={Generate=function(size)
 generatedMaps+=1
 workspace:SetAttribute("MapSeed",1000+generatedMaps)
 workspace:SetAttribute("MapReady",true)
 workspace:SetAttribute("MatchSizeName",size)
 return {Vector3.new(-128,0,-128),Vector3.new(128,0,128),Vector3.new(128,0,-128),Vector3.new(-128,0,128)}
end}

-- ACTUAL_SERVER_LOBBY_ROOM_INIT
-- ACTUAL_SERVER_LOBBY_ROOM_BODY
-- ACTUAL_SERVER_LOBBY_CLEAR_BODY
-- ACTUAL_SERVER_LOBBY_LIFECYCLE_BODY
