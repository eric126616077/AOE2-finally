local Tutorial = require('../src/ReplicatedStorage/Shared/Tutorial')
local state=Tutorial.New()
assert(not Tutorial.Advance(state,{army=true}), 'Later military activity cannot skip economic learning')
assert(state.step==1)
local keys={'cameraMoved','selectedVillager','delivered','house','trained','dropoff','farm','barracks','army','selectedArmy','feudal'}
assert(#Tutorial.Steps==#keys, 'Step list changed without updating the ordered expectation')
local seen={}
for index,key in ipairs(keys) do
 local step=Tutorial.Steps[index]
 assert(step.key==key and not seen[key], 'Steps keep a unique, ordered fact')
 seen[key]=true
 for _,field in ipairs({'title','desktop','touch','why'}) do assert(type(step[field])=='string' and #step[field]>0, 'Every step explains both inputs and its reason') end
 assert(Tutorial.Chapters[step.chapter] and (index==1 or step.chapter>=Tutorial.Steps[index-1].chapter), 'Chapters exist and never go backwards')
 assert(math.abs(Tutorial.Progress(state)-(index-1)/#keys)<1e-9)
 assert(not Tutorial.Advance(state,{[key]=false}), 'Incomplete server facts must not advance')
 assert(Tutorial.Advance(state,{[key]=true}))
end
assert(state.complete and state.step==#keys+1 and Tutorial.Progress(state)==1)
assert(not Tutorial.Advance(state,{army=true}), 'Completion is idempotent')
assert(not Tutorial.Skip(state), 'A finished tutorial cannot be skipped further')
assert(Tutorial.New().step==1, 'A new match has independent guidance')
local skipped=Tutorial.New()
for _=1,#keys do assert(Tutorial.Skip(skipped)) end
assert(skipped.complete, 'Skipping every step ends the tutorial')
assert(Tutorial.FirstTime('Ready',false) and Tutorial.FirstTime('Disabled',nil) and Tutorial.FirstTime('SaveFailed',false))
assert(not Tutorial.FirstTime('Ready',true), 'Finished players are never treated as new')
assert(not Tutorial.FirstTime('Loading',false) and not Tutorial.FirstTime('LoadFailed',false) and not Tutorial.FirstTime(nil,nil), 'Unknown profile state must not nag returning players')
assert(Tutorial.Format('按 {build:B} 與 {garrison:G}',function(id) return id=='build' and 'N' or nil end)=='按 N 與 G', 'Rebound keys replace defaults; unbound keep them')
assert(Tutorial.Format('按 {build:B}')=='按 B' and Tutorial.Format('沒有按鍵')=='沒有按鍵')
for _,step in ipairs(Tutorial.Steps) do
 assert(not Tutorial.Format(step.desktop):find('[{}]') and not step.touch:find('[{}]') and not step.why:find('{%w+}'), 'No raw key token reaches the player')
end
print('PASS: tutorial sequence, no skipped steps, false facts, completion, new match')
