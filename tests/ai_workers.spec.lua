local Rules=require("../src/ServerScriptService/ServerModules/AIWorkerRules")
local count=0
local function expect(ok,message) count+=1; assert(ok,message) end
local shortages=Rules.resourcePriorities(10,{food=0,wood=0,gold=0,stone=0},0)
expect(shortages[1]=="food" and shortages[2]=="wood","economic shortages not prioritized")
local targets={gold={kind="gold"},stone={kind="stone"}}
local found,key=Rules.findResource(shortages,function(resource) return targets[resource] end)
expect(found==targets.gold and key=="gold","exhausted preferred resources trapped villagers idle")
targets.gold=nil
found,key=Rules.findResource(shortages,function(resource) return targets[resource] end)
expect(found==targets.stone and key=="stone","last available resource not used")
expect(not Rules.findResource(shortages,function() return nil end),"no-resource case fabricated a target")
local farm={kind="food",owned=true}
found,key=Rules.findResource(shortages,function(resource) return resource=="food" and farm end)
expect(found==farm and key=="food","owned replenished farm not considered")
local shifted=Rules.resourcePriorities(10,{food=8,wood=0,gold=0,stone=0},400)
expect(shifted[1]=="wood","allocation failed to rebalance already assigned food workers")
local site,otherSite={},{}
local working,idle,dead,foreign={},{},{},{}
local candidates={
 {unit=dead,valid=false,distance=0},
 {unit=foreign,valid=false,distance=1},
 {unit=working,valid=true,orderKind="build",orderTarget=otherSite,distance=2},
 {unit=idle,valid=true,orderKind="gather",distance=20},
}
local worker,assigned=Rules.builder(candidates,site,100)
expect(worker==idle and not assigned,"abandoned site could not recruit valid nonconstruction worker")
candidates[4].retryAfter=108
expect(not Rules.builder(candidates,site,100),"unreachable worker immediately retried same failed site")
expect(Rules.builder(candidates,site,108)==idle,"route cooldown never allowed retry")
candidates[3].orderTarget=site
worker,assigned=Rules.builder(candidates,site,100)
expect(worker==working and assigned,"existing builder was replaced, resetting its in-flight route")
candidates[3].valid=false
expect(not Rules.builder(candidates,site,100),"dead assigned builder kept abandoned site marked active")
candidates[4].retryAfter=nil
expect(Rules.builder(candidates,site,100)==idle,"replacement builder not recruited after original died")
print(string.format("PASS: %d AI resource fallback / abandoned-site recovery checks",count))
