local Rules=require("../src/ReplicatedStorage/Shared/HotkeyRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
-- Defaults match the keys the game shipped with, one key per action.
local defaults=Rules.defaults()
expect(defaults.build=="B" and defaults.train=="T" and defaults.research=="R" and defaults.formation=="F","tab defaults")
expect(defaults.stop=="X" and defaults.garrison=="G" and defaults.delete=="Delete" and defaults.advanceAge=="U","command defaults")
expect(defaults.cameraUp=="W" and defaults.cameraDown=="S" and defaults.cameraLeft=="A" and defaults.cameraRight=="D","camera defaults")
expect(defaults.selectVillagers=="V" and defaults.selectHome=="H" and defaults.selectIdle=="Period" and defaults.gotoAlert=="Space","selection defaults")
local seen={}
for _,action in ipairs(Rules.Actions) do
 expect(Rules.allowed(action.default),action.id.." default must be bindable")
 expect(not seen[action.default],action.id.." default must be unique")
 seen[action.default]=true
 expect(Rules.action(action.id)==action,"action lookup")
end
expect(Rules.isDefault(defaults) and not Rules.isDefault({}) and not Rules.isDefault(nil),"default detection")
-- Fixed keys can never be taken.
for _,key in ipairs({"Up","Down","Left","Right","Escape","One","Nine","Home","LeftShift","RightControl","LeftAlt"}) do
 expect(not Rules.allowed(key) and Rules.rejectReason(key)~=nil,key.." is reserved")
end
for _,key in ipairs({"Slash","Tab","F9","Unknown","",false}) do
 expect(Rules.rejectReason(key)~=nil,"unsupported key rejected")
end
-- The panel shows these reasons to the player, so each must say what the key is kept for.
for key,use in pairs({Up="相機移動",Left="相機移動",Home="回到基地",Escape="取消",Five="編隊",LeftShift="組合鍵"}) do
 local why=Rules.rejectReason(key)
 expect(type(why)=="string" and why:find(use,1,true)~=nil and why:find("不能改綁",1,true)~=nil,key.." reason names its fixed use")
 local _,_,bindWhy=Rules.bind(defaults,"stop",key)
 expect(bindWhy==why,"bind reports the same reason for "..key)
end
expect(Rules.rejectReason("Slash")=="這個按鍵不能設為熱鍵。" and Rules.rejectReason("Unknown")=="無法辨識這個按鍵。","unsupported and unknown keys have their own reasons")
expect(Rules.rejectReason("Q")==nil and Rules.rejectReason("Comma")==nil,"free keys are accepted")
-- Binding a free key.
local map,swapped,reason=Rules.bind(defaults,"stop","Q")
expect(map and map.stop=="Q" and swapped==nil and reason==nil,"bind free key")
expect(defaults.stop=="X","bind must not mutate its input")
expect(Rules.actionFor(map,"Q")=="stop" and Rules.actionFor(map,"X")==nil,"lookup follows the new key")
-- Binding a key in use swaps the two actions.
local swappedMap,other=Rules.bind(map,"build","Q")
expect(swappedMap.build=="Q" and swappedMap.stop=="B" and other=="stop","conflict swaps keys")
local same,none=Rules.bind(swappedMap,"build","Q")
expect(same.build=="Q" and none==nil,"rebinding the same key is a no-op")
-- Camera keys rebind and swap like any other action; the arrows stay as a fixed fallback.
local cameraMap,cameraOther=Rules.bind(defaults,"cameraUp","I")
expect(cameraMap.cameraUp=="I" and cameraOther==nil and Rules.actionFor(cameraMap,"W")==nil,"camera key moves to a free key")
local freed=Rules.bind(cameraMap,"build","W")
expect(freed.build=="W" and freed.cameraUp=="I","a freed camera key can be used by a command")
local cameraSwap,cameraSwapped=Rules.bind(defaults,"stop","W")
expect(cameraSwap.stop=="W" and cameraSwap.cameraUp=="X" and cameraSwapped=="cameraUp","taking a camera key swaps with the camera action")
local rejected,_,why=Rules.bind(defaults,"build","Up")
expect(rejected==nil and type(why)=="string","reserved key is rejected with a reason")
expect(Rules.bind(defaults,"missing","Q")==nil and Rules.bind(nil,"build","Q")==nil,"bad action or map is rejected")
-- Round trip through the stored attribute.
local restored=Rules.parse(Rules.serialize(swappedMap))
for _,action in ipairs(Rules.Actions) do expect(restored[action.id]==swappedMap[action.id],action.id.." survives a round trip") end
-- Broken stored values fall back safely.
expect(Rules.isDefault(Rules.parse(nil)) and Rules.isDefault(Rules.parse(42)) and Rules.isDefault(Rules.parse("")),"missing value uses defaults")
expect(Rules.isDefault(Rules.parse("build=Up;hack=Q;stop=Escape")),"reserved keys and unknown actions are ignored")
expect(Rules.isDefault(Rules.parse("build=T")),"a duplicate key discards the stored value")
expect(Rules.isDefault(Rules.parse(string.rep("build=Q;",100))),"oversized value is ignored")
expect(Rules.parse("stop=Q").stop=="Q","partial value keeps other defaults")
expect(Rules.parse("cameraUp=I;build=W").build=="W" and Rules.isDefault(Rules.parse("build=W")),"camera keys round trip; a clash with a camera default is discarded")
expect(Rules.serialize({stop="Escape"}):find("stop=X",1,true)~=nil,"serialize never writes an unusable key")
-- Labels shown on the HUD.
expect(Rules.label("Period")=="." and Rules.label("Delete")=="Del" and Rules.label("B")=="B" and Rules.label(nil)=="?","key labels")
print("hotkey rules: "..checks.." checks passed")
