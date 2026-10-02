local Tutorial = require('../src/ReplicatedStorage/Shared/Tutorial')
local state=Tutorial.New()
assert(not Tutorial.Advance(state,{army=true}), 'Later military activity cannot skip economic learning')
assert(state.step==1)
for _,key in ipairs({'selectedVillager','delivered','house','trained','army'}) do
 assert(not Tutorial.Advance(state,{[key]=false}), 'Incomplete server facts must not advance')
 assert(Tutorial.Advance(state,{[key]=true}))
end
assert(state.complete and state.step==6)
assert(not Tutorial.Advance(state,{army=true}), 'Completion is idempotent')
assert(Tutorial.New().step==1, 'A new match has independent guidance')
print('PASS: tutorial sequence, no skipped steps, false facts, completion, new match')
