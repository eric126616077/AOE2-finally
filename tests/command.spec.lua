local Rules=require("../src/ServerScriptService/ServerModules/CommandRules")
local checks=0
local function expect(value,message) checks+=1; assert(value,message) end
local own,enemy,removed={},{},{}
local function eligible(model) return model==own end
local accepted=Rules.deletion({own},3,3,eligible)
expect(accepted and accepted[1]==own,"valid owned selection accepted")
for _,selection in ipairs({{}, {own,enemy}, {own,removed}, {own,own}, {[1]=own,[3]=enemy}, {[0]=own}, {named=own}, {[1]=own,extra=true}}) do
 expect(Rules.deletion(selection,3,3,eligible)==nil,"invalid whole batch rejected without partial changes")
end
for _,generation in ipairs({-1,2,3.5,math.huge,0/0,"3",false}) do
 expect(Rules.deletion({own},generation,3,eligible)==nil,"stale/nonfinite/noninteger generations rejected")
end
expect(Rules.deletion(nil,3,3,eligible)==nil,"missing selection")
expect(Rules.deletion({own},3,3,function() error("removed instance") end)==nil,"eligibility errors fail closed")
local many={}
for i=1,200 do many[i]={} end
expect(#Rules.deletion(many,3,3,function() return true end)==200,"200 distinct owned entries")
many[201]={}
expect(Rules.deletion(many,3,3,function() return true end)==nil,"over-limit selection")
expect(Rules.deletion({own},3,3,function() return 1 end)==nil,"eligibility must explicitly succeed")
print("Command deletion rules:",checks,"checks passed")
