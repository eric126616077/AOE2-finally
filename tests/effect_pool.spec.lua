local Pool=require("../src/ReplicatedStorage/Shared/EffectPool")
local count=0
local function expect(value,message) count+=1; assert(value,message) end
local built,hidden,destroyed=0,0,0
local function make(limit,maxIdle)
 return Pool.new({limit=limit,maxIdle=maxIdle,
  build=function(key) built+=1; return {name=key} end,
  hide=function(record) hidden+=1; record.visible=false end,
  destroy=function(record) destroyed+=1; record.gone=true end})
end
expect(not pcall(Pool.new,{}),"pool accepted missing callbacks")
local pool=make(3,2)
local a,leaseA=pool:Acquire("arrow")
expect(a and a.key=="arrow" and leaseA and pool.count==1 and pool.created==1,"first acquire did not build")
expect(pool:Release(a,leaseA) and pool.count==0 and hidden==1 and pool:IdleCount()==1,"release did not hide and keep the object")
local b,leaseB=pool:Acquire("arrow")
expect(b==a and pool.reused==1 and pool.created==1,"idle object was not reused")
-- 舊計時器拿過期租約歸還，不能收回已被重用的物件。
expect(not pool:Release(a,leaseA) and pool.count==1 and pool.active[b],"stale lease released a reused object")
-- 不同種類不混用。
local c=pool:Acquire("ball")
expect(c~=b and c.key=="ball" and pool.created==2,"different kinds shared an object")
-- 上限：使用中達到 limit 時不再給。
local d=pool:Acquire("ball")
expect(d and pool.count==3 and pool:Acquire("ball")==nil and pool.count==3,"limit not enforced")
-- 換手：舊租約失效，新租約有效。
local renewed=pool:Renew(b)
expect(renewed and renewed~=leaseB and not pool:Release(b,leaseB) and pool.active[b],"renew kept the old lease alive")
expect(pool:Release(b,renewed) and not pool.active[b],"renewed lease could not release")
expect(pool:Renew(b)==nil,"renewed an idle object")
expect(not pool:Release(b),"double release accepted")
-- 閒置上限：超過 maxIdle 的物件被銷毀。
expect(pool:Release(c) and pool:Release(d) and pool:IdleCount()==3,"idle stock per kind wrong")
local e1=pool:Acquire("ball"); local e2=pool:Acquire("ball"); local e3=pool:Acquire("ball")
expect(e1==d and e2==c and e3 and pool.created==4,"ball stock not reused before building")
pool:Release(e1); pool:Release(e2); pool:Release(e3)
expect(pool:IdleCount()==3 and destroyed==1 and e3.gone==true,"idle stock exceeded maxIdle")
-- 條件歸還與清除。
local moving=pool:Acquire("ball"); moving.moving=true
local still=pool:Acquire("arrow")
expect(pool:ReleaseWhere(function(record) return record.moving==true end)==1 and pool.active[still] and not pool.active[moving],"conditional release wrong")
pool:Clear()
expect(pool.count==0 and pool:IdleCount()==0 and next(pool.active)==nil,"clear left objects behind")
-- 長時間大量使用：建立數量受同時使用量限制，而不是總次數。
local churn=make(80,40)
built=0
local live={}
for step=1,5000 do
 local record,lease=churn:Acquire(step%3==0 and "arrow" or "ball")
 if record then table.insert(live,{record,lease}) end
 if #live>30 then local item=table.remove(live,1); churn:Release(item[1],item[2]) end
end
expect(built<=80 and churn.reused>4800,"pool kept building objects during sustained use")
print(("PASS: %d effect pool reuse / lease / limit / idle cap checks"):format(count))
