-- verify.ps1 bundles Config, TeamRules, MatchRules, GameModeRules and LobbyRules ahead of these checks.
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local base={size="Medium",aiCount=0,difficulty="Normal",population=100,startingResources="Standard",victory="Conquest",teamMode="FFA"}
local function payload(fields)
 local result=table.clone(base)
 for key,value in pairs(fields) do result[key]=value end
 return result
end
local chapters=Config.Story.chapters
expect(#chapters>=3 and GameModeRules.ChapterCount==#chapters,"story needs several chapters")
expect(GameModeRules.Order[1]=="Story" and GameModeRules.Order[2]=="PvP" and GameModeRules.Order[3]=="PvE" and #GameModeRules.Order==3,"lobby must offer exactly Story / PvP / PvE")

-- Story: chapter decides rules; humans always cooperate; more humans never exceed four sides.
for index,chapter in ipairs(chapters) do
 for humans=1,3 do
  local settings,expected=LobbyRules.settings(payload({gameMode="Story",storyChapter=index,expectedPlayers=humans,size="Large",aiCount=3,difficulty="Easy",victory="Wonder",teamMode="FFA"}))
  expect(settings and expected==humans,"story chapter "..index.." rejected "..humans.." players")
  expect(settings.teamMode=="CoopAI" and settings.size==chapter.size and settings.difficulty==chapter.difficulty and settings.victory==chapter.victory
   and settings.population==chapter.population and settings.startingResources==chapter.startingResources,"client payload overrode story chapter rules")
  expect(settings.aiCount>=1 and settings.aiCount<=chapter.aiCount and humans+settings.aiCount<=4,"story enemy count invalid")
  expect(settings.gameMode=="Story" and settings.storyChapter==index,"story identity not kept")
  local preview=LobbyRules.teamPreview(settings.teamMode,humans,(function()
   local members={}
   for i=1,humans do members[i]={id=i*10,ai=false,queued=true,ready=true} end
   return members
  end)(),(function() local ids={} for i=1,settings.aiCount do ids[i]=-10000-i end; return ids end)())
  expect(preview and preview.teamById[10]==1 and preview.teamById[-10001]==2,"story humans not allied against chapter enemies")
 end
 expect(LobbyRules.story({gameMode="Story",storyChapter=index})==chapter,"story chapter lookup")
end
expect(not LobbyRules.settings(payload({gameMode="Story",storyChapter=1,expectedPlayers=4})),"story admitted four humans with no enemy slot")
for _,bad in ipairs({0,#chapters+1,1.5,0/0,math.huge,"1",false}) do
 expect(not LobbyRules.settings(payload({gameMode="Story",storyChapter=bad,expectedPlayers=1})),"invalid story chapter accepted")
end
expect(not LobbyRules.settings(payload({gameMode="Story",storyChapter=2,expectedPlayers=1}),{unlocked=1}),"locked chapter accepted")
expect(LobbyRules.settings(payload({gameMode="Story",storyChapter=2,expectedPlayers=1}),{unlocked=2}),"unlocked chapter rejected")
expect(LobbyRules.story({gameMode="PvE",storyChapter=1})==nil and LobbyRules.story(nil)==nil,"non-story match resolved a chapter")
expect(GameModeRules.unlocked(nil)==1 and GameModeRules.unlocked(0)==1 and GameModeRules.unlocked(2)==3 and GameModeRules.unlocked(99)==#chapters
 and GameModeRules.unlocked(-1)==1 and GameModeRules.unlocked(0/0)==1,"story unlock progression")

-- PvP: humans only.
for humans=2,4 do
 local settings=LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=humans}))
 expect(settings and settings.aiCount==0 and settings.storyChapter==0,"pure PvP rejected")
end
expect(not LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=1})),"PvP accepted one human")
expect(not LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=2,aiCount=2})),"PvP accepted AI")
expect(not LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=2,aiCount=1,teamMode="CoopAI"})),"PvP accepted coop")
expect(not LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=3,teamMode="Teams"})),"PvP accepted 3-way teams")
expect(LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=4,teamMode="Teams"})),"PvP 2v2 rejected")
local leaked=LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=2,storyChapter=3}))
expect(leaked and leaked.storyChapter==0,"non-story room kept a chapter")

-- PvE: humans with at least one AI opponent.
for humans=1,3 do
 for ai=1,4-humans do
  expect(LobbyRules.settings(payload({gameMode="PvE",expectedPlayers=humans,aiCount=ai,teamMode="CoopAI"})),"PvE coop rejected")
 end
end
expect(not LobbyRules.settings(payload({gameMode="PvE",expectedPlayers=2,aiCount=0,teamMode="FFA"})),"PvE accepted no AI")
expect(not LobbyRules.settings(payload({gameMode="PvE",expectedPlayers=4,aiCount=0})),"PvE accepted four humans")
expect(not LobbyRules.settings(payload({gameMode="PvE",expectedPlayers=1,aiCount=1,teamMode="Teams"})),"PvE accepted human teams")
expect(LobbyRules.settings(payload({gameMode="PvE",expectedPlayers=1,aiCount=2,teamMode="FFA"})),"PvE free-for-all rejected")

-- Sandbox is server-only; unknown modes are rejected; legacy callers keep working.
local sandbox=payload({gameMode="Sandbox",expectedPlayers=1,size="Small",startingResources="Rich"})
expect(not LobbyRules.settings(sandbox),"client created a sandbox room")
expect(LobbyRules.settings(sandbox,{internal=true}),"server tutorial sandbox rejected")
for _,bad in ipairs({"Ranked","order",12,{},true}) do expect(not LobbyRules.settings(payload({gameMode=bad,expectedPlayers=2})),"unsupported mode accepted") end
local legacy=LobbyRules.settings(payload({expectedPlayers=2,aiCount=2}))
expect(legacy and legacy.gameMode=="PvE" and legacy.storyChapter==0,"legacy payload not labeled")
legacy=LobbyRules.settings(payload({expectedPlayers=2}))
expect(legacy and legacy.gameMode=="PvP","legacy human match not labeled PvP")
expect(MatchRules.settings({size="Medium",aiCount=0,difficulty="Normal",population=100,startingResources="Standard",victory="Conquest",gameMode="Story",storyChapter=1.5},1)==nil,"fractional chapter passed match validation")

-- Defaults always produce a valid room, and room presets start as PvP.
for _,mode in ipairs(GameModeRules.Order) do
 for humans=1,4 do
  for unlocked=1,#chapters do
   local proposal=GameModeRules.defaults(mode,humans,unlocked)
   local settings=LobbyRules.settings(proposal,{unlocked=unlocked})
   expect(settings~=nil,"defaults invalid for "..mode.." "..humans.." "..unlocked)
   if mode=="Story" then expect(settings.storyChapter==unlocked,"story defaults skip the newest chapter") end
  end
 end
end
-- One portal per public mode; each portal default is a valid room in its own mode.
local portalModes={}
for _,portal in ipairs(Config.Lobby.portals) do
 local mode=portal.settings.gameMode
 expect(GameModeRules.mode(mode)~=nil and not GameModeRules.mode(mode).internal,"portal mode must be public")
 expect(portalModes[mode]==nil,"two portals share a game mode")
 portalModes[mode]=portal.id
 local preset=LobbyRules.settings(portal.settings)
 expect(preset~=nil and preset.gameMode==mode,"portal default changed mode")
end
for _,mode in ipairs(GameModeRules.Order) do expect(portalModes[mode]~=nil,"no portal for mode "..mode) end

-- Client proposals follow the same rules and never evict queued players.
local pvp=assert(LobbyRules.settings(payload({gameMode="PvP",expectedPlayers=4,teamMode="Teams"})))
pvp.expectedPlayers=4
local blocked,message=GameModeRules.next(pvp,"gameMode",{"Story"},4,1)
expect(blocked==nil and message~=nil,"switch to story evicted a full PvP room")
local story=GameModeRules.next(pvp,"gameMode",{"Story"},2,3)
expect(story and story.gameMode=="Story" and story.expectedPlayers==3 and story.storyChapter==3 and story.teamMode=="CoopAI" and story.aiCount==1,"switch to story did not keep players / newest chapter")
local back=GameModeRules.next(story,"gameMode",{"PvP"},2,3)
expect(back and back.size=="Medium" and back.victory=="Conquest" and back.aiCount==0 and back.storyChapter==0,"leaving story kept chapter rules")
local nextChapter,lockMessage=GameModeRules.next(story,"storyChapter",{1,2,3,4,5},2,3)
expect(nextChapter and nextChapter.storyChapter==1 and lockMessage~=nil,"chapter cycle did not skip locked chapters")
local pve=assert(GameModeRules.next(back,"gameMode",{"PvE"},2,3))
expect(pve.gameMode=="PvE" and pve.aiCount==1 and pve.expectedPlayers==3,"switch to PvE did not keep players / free AI slot")
local morePlayers=GameModeRules.next({gameMode="PvE",storyChapter=0,expectedPlayers=1,aiCount=3,teamMode="CoopAI",size="Medium",difficulty="Normal",population=100,startingResources="Standard",victory="Conquest"},"expectedPlayers",{1,2,3,4},1,1)
expect(morePlayers and morePlayers.expectedPlayers==2 and morePlayers.aiCount==2,"more PvE players did not free an AI slot")
local threeTeams=GameModeRules.next({gameMode="PvP",storyChapter=0,expectedPlayers=2,aiCount=0,teamMode="Teams",size="Medium",difficulty="Normal",population=100,startingResources="Standard",victory="Conquest"},"expectedPlayers",{1,2,3,4},2,1)
expect(threeTeams and threeTeams.expectedPlayers==4,"PvP team player cycle offered 3-player teams")
expect(GameModeRules.next({gameMode="Cheat"},"gameMode",{"PvP"},0,1)==nil and GameModeRules.next(false,"x",{},0,1)==nil,"malformed proposal accepted")
expect(GameModeRules.next(pvp,"gameMode",{"Sandbox"},1,1)==nil,"client proposal created a sandbox")

-- Labels for cards, rosters and the plaza signs.
expect(GameModeRules.label({gameMode="Story",storyChapter=1})=="劇情 · 第 1 章 "..chapters[1].title,"story label")
expect(GameModeRules.label({gameMode="PvP",teamMode="Teams"})=="玩家對戰 · 分隊","PvP label")
expect(GameModeRules.label({gameMode="PvE",teamMode="CoopAI"})=="合作對電腦","PvE label")
expect(GameModeRules.label(nil)=="玩法載入中" and GameModeRules.label({gameMode="order"})=="玩法載入中","bad label input")
print(string.format("PASS: %d story / PvP / PvE mode, chapter unlock and proposal checks",count))
