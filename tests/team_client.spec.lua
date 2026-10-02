local Rules=require("../src/ReplicatedStorage/Shared/TeamClientRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
local base={expectedPlayers=2,aiCount=1,teamMode="FFA",size="Small",victory="Conquest"}
expect(Rules.ValidSettings(base,2),"normal FFA proposal rejected")
local teams=Rules.NextSetting(base,"teamMode",{"FFA","Teams","CoopAI"},2)
expect(teams.teamMode=="Teams" and teams.expectedPlayers==2 and teams.aiCount==2,"three-side team proposal not made into four sides")
expect(base.aiCount==1 and base.teamMode=="FFA","proposal mutated current server settings")
expect(Rules.ModeLabel("Teams",2,2)=="分隊對戰 · 2v2" and Rules.ModeLabel("Teams",1,1)=="分隊對戰 · 1v1","wrong match size advertised")
local solo=Rules.NextSetting({expectedPlayers=1,aiCount=0,teamMode="FFA"},"teamMode",{"FFA","Teams","CoopAI"},1)
expect(solo.aiCount==1 and solo.expectedPlayers==1,"solo team proposal does not become legal 1v1")
local coop=Rules.NextSetting({expectedPlayers=4,aiCount=0,teamMode="Teams"},"teamMode",{"FFA","Teams","CoopAI"},3)
expect(coop.teamMode=="CoopAI" and coop.expectedPlayers==3 and coop.aiCount==1,"coop does not reserve AI slot")
local blocked,message=Rules.NextSetting({expectedPlayers=4,aiCount=0,teamMode="Teams"},"teamMode",{"FFA","Teams","CoopAI"},4)
expect(blocked and blocked.teamMode=="FFA" and blocked.expectedPlayers==4 and blocked.aiCount==0 and message~=nil,"unavailable coop traps the mode cycle or evicts a queued player")
local count=Rules.NextSetting({expectedPlayers=1,aiCount=1,teamMode="Teams"},"aiCount",{0,1,2,3},1)
expect(count and count.aiCount==3,"three-faction invalid proposal traps AI button")
local people=Rules.NextSetting({expectedPlayers=1,aiCount=1,teamMode="Teams"},"expectedPlayers",{1,2,3,4},1)
expect(people.expectedPlayers==3 and people.aiCount==1,"player cycle fails to skip illegal three-side total")
local noLower=Rules.NextSetting({expectedPlayers=3,aiCount=1,teamMode="CoopAI"},"expectedPlayers",{1,2,3,4},3)
expect(noLower==nil,"count cycle removes already queued players")
for _,s in ipairs({{expectedPlayers=0,aiCount=0,teamMode="FFA"},{expectedPlayers=2,aiCount=math.huge,teamMode="FFA"},
 {expectedPlayers=2.5,aiCount=1,teamMode="FFA"},{expectedPlayers=2,aiCount=1,teamMode="Teams"},
 {expectedPlayers=2,aiCount=0,teamMode="CoopAI"},{expectedPlayers=4,aiCount=1,teamMode="FFA"},
 {expectedPlayers=1,aiCount=0,teamMode="Cheat"}}) do expect(not Rules.ValidSettings(s,0),"invalid settings accepted for display proposal") end
expect(Rules.Relation("Teams",-1,1,-2,1)=="ally","Studio negative human IDs treated as enemies")
expect(Rules.Relation("CoopAI",12,1,13,1)=="ally","cooperative humans not allies")
expect(Rules.Relation("CoopAI",12,1,-10001,2)=="enemy","server AI enemy not recognized")
expect(Rules.Relation("Teams",12,1,12,nil)=="own","ownership waits for team replication")
expect(Rules.Relation("FFA",12,1,13,1)=="enemy","FFA leaks stale same-team alliance")
expect(Rules.Relation("Teams",12,1,nil,nil)=="neutral","unowned world resource treated as ally")
for _,value in ipairs({0,-1,0/0,math.huge,"1",false}) do expect(Rules.Relation("Teams",12,value,13,1)=="unresolved","invalid local team accepted as an alliance") end
expect(Rules.Relation("Teams",12,1,13,nil)=="unresolved","missing team replication guessed as hostile")
expect(Rules.Relation("Unknown",12,1,13,1)=="unresolved","unknown mode grants alliance")
expect(Rules.TeamLabel("CoopAI",1)=="真人隊" and Rules.TeamLabel("CoopAI",2)=="電腦隊","cooperative roster labels wrong")
expect(Rules.TeamLabel("Teams",2)=="第 2 隊" and Rules.TeamLabel("Teams",nil)=="分隊待確認","uncommitted preview guessed as a team")
expect(Rules.NextSetting({expectedPlayers="two",aiCount=1,teamMode="FFA"},"teamMode",{"FFA","Teams"},0)==nil,"malformed current counts raise an arithmetic error")
expect(Rules.NextSetting(base,"expectedPlayers",{"bad",math.huge},0)==nil,"malformed proposal counts raise an arithmetic error")
print(string.format("PASS: %d client team proposals, no eviction, relation, label checks",checks))
