local checks = 0
local function check(condition, message)
 checks += 1
 assert(condition, message)
end
for _,size in ipairs({Vector2.new(2,2),Vector2.new(3,3),Vector2.new(4,4),Vector2.new(8,8)}) do
 for x=-256,256,7 do
  for z=-256,256,11 do
   local pos,gx,gz=Grid.snap(Vector3.new(x,0,z),size)
   local again,ax,az=Grid.snap(pos,size)
   check(again.X==pos.X and again.Z==pos.Z and ax==gx and az==gz,"snap must be idempotent")
   check(math.abs((pos.X-size.X*4+256)/8-gx)<0.0001,"X footprint grid mismatch")
   check(math.abs((pos.Z-size.Y*4+256)/8-gz)<0.0001,"Z footprint grid mismatch")
   if Grid.inBounds(pos,size) then
    check(gx>=0 and gz>=0 and gx+size.X<=64 and gz+size.Y<=64,"footprint escapes map")
   end
  end
 end
 local edge=Vector3.new(256-size.X*4,0,256-size.Y*4)
 check(Grid.inBounds(edge,size),"exact edge must be allowed")
 check(not Grid.inBounds(Vector3.new(edge.X+0.01,0,edge.Z),size),"partial footprint off map must fail")
end
check(Grid.isFinite(0) and Grid.isFinite(-512),"finite coordinates rejected")
check(not Grid.isFinite(0/0),"NaN accepted")
check(not Grid.isFinite(math.huge) and not Grid.isFinite(-math.huge),"infinity accepted")
check(not Grid.isFinite("0") and not Grid.isFinite(nil),"wrong types accepted")
local balances={wood=175,food=49,stone=0,gold=20}
local writes=0
local player={}
function player:GetAttribute(key) return balances[key] end
function player:SetAttribute(key,value) balances[key]=value; writes+=1 end
check(not Economy.spend(player,{wood=100,food=50}),"partial insufficient cost accepted")
check(writes==0 and balances.wood==175,"failed cost mutated balances")
check(Economy.spend(player,{wood=175}),"exact balance should succeed")
check(balances.wood==0,"incorrect cost deduction")
local before=writes
check(not Economy.spend(player,{wood=1}),"negative balance permitted")
check(writes==before,"failed repeated request mutated balances")
check(not Economy.spend(player,{missing=1}),"missing resource accepted")
check(Economy.spend(player,{}),"zero cost rejected")
print(string.format("PASS: %d grid / finite-coordinate / atomic-cost checks",checks))
