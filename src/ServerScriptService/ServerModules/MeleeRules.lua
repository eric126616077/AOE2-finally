-- 候選位置只做數值幾何；地圖範圍、碰撞、攻擊通道與尋路仍由伺服器驗證。
local MeleeRules = {}
local POINT_COUNT = 16
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function MeleeRules.candidates(centerX,centerZ,halfX,halfZ,attackerRadius,attackRange)
 if not finite(centerX) or not finite(centerZ) or not finite(halfX) or not finite(halfZ)
  or not finite(attackerRadius) or not finite(attackRange) or halfX<=0 or halfZ<=0
  or attackerRadius<=0 or attackRange<0 then return nil end
 local gap=attackerRadius+0.5
 local outerX,outerZ=halfX+gap,halfZ+gap
 if not finite(gap) or not finite(outerX) or not finite(outerZ) then return nil end
 local points={}
 for index=0,POINT_COUNT-1 do
  local angle=index*math.pi*2/POINT_COUNT
  local dx,dz=math.cos(angle),math.sin(angle)
  -- 擴張矩形包含方形 Blockcast 半寬與間隙，斜角也不會與目標占地重疊。
  local xDistance=math.abs(dx)>1e-9 and outerX/math.abs(dx) or math.huge
  local zDistance=math.abs(dz)>1e-9 and outerZ/math.abs(dz) or math.huge
  local distance=math.min(xDistance,zDistance)
  local x,z=centerX+dx*distance,centerZ+dz*distance
  if not finite(x) or not finite(z) then return nil end
  local edgeX,edgeZ=math.max(0,math.abs(x-centerX)-halfX),math.max(0,math.abs(z-centerZ)-halfZ)
  local edgeDistance=math.sqrt(edgeX*edgeX+edgeZ*edgeZ)
  if finite(edgeDistance) and edgeDistance<=attackRange+1e-7 then
   table.insert(points,{X=x,Z=z,index=index+1})
  end
 end
 return points
end

return MeleeRules
