-- 純 XZ 陣形幾何；不讀取 Instance、Workspace 或客戶端位置。
local Rules={MAX_SELECTION=200}
local kinds={Box=true,Line=true,Column=true,Wedge=true,Spread=true}
local EPSILON=1e-7

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function countValid(value,maximum)
 return finite(value) and value%1==0 and value>=1 and value<=maximum
end
local function pointValid(point)
 return type(point)=="table" and finite(point.X) and finite(point.Z)
end
function Rules.validKey(config,key)
 return type(config)=="table" and type(config.types)=="table" and type(key)=="string"
  and kinds[key]==true and type(config.types[key])=="table"
end

-- 先驗證整批：ipairs/# 不足以拒絕稀疏、重複或含字串鍵的遠端資料。
function Rules.selection(selection,maximum,eligible)
 if type(selection)~="table" or not countValid(maximum,Rules.MAX_SELECTION) or type(eligible)~="function" then return nil end
 local count=0
 for index in pairs(selection) do
  count+=1
  if count>maximum or not countValid(index,maximum) then return nil end
 end
 if count==0 then return nil end
 local result,seen={},{}
 for index=1,count do
  local value=selection[index]
  if value==nil or (type(value)=="number" and not finite(value)) or seen[value] then return nil end
  local ok,allowed=pcall(eligible,value)
  if not ok or allowed~=true then return nil end
  seen[value]=true
  result[index]=value
 end
 return result
end

function Rules.layout(key,count,spacing,maxAxisSlots)
 if not kinds[key] or not countValid(count,Rules.MAX_SELECTION) or not finite(spacing) or spacing<=0 then return nil end
 maxAxisSlots=maxAxisSlots or count
 if not countValid(maxAxisSlots,Rules.MAX_SELECTION) then return nil end
 local slots={}
 local function row(width,rowIndex)
  for column=1,width do table.insert(slots,{X=(column-(width+1)/2)*spacing,Z=-rowIndex*spacing}) end
 end
 if key=="Wedge" then
  local remaining,rowIndex=count,0
  while remaining>0 do
   local width=math.min(remaining,rowIndex*2+1)
   row(width,rowIndex)
   remaining-=width
   rowIndex+=1
  end
 elseif key=="Column" then
  local length=math.min(count,maxAxisSlots)
  for index=1,count do
   table.insert(slots,{X=math.floor((index-1)/length)*spacing,Z=-((index-1)%length)*spacing})
  end
 else
  local width=key=="Line" and math.min(count,maxAxisSlots) or math.ceil(math.sqrt(count))
  local remaining,rowIndex=count,0
  while remaining>0 do
   local used=math.min(remaining,width)
   row(used,rowIndex)
   remaining-=used
   rowIndex+=1
  end
 end
 local sumX,sumZ=0,0
 for _,slot in ipairs(slots) do sumX+=slot.X; sumZ+=slot.Z end
 if not finite(sumX) or not finite(sumZ) then return nil end
 for _,slot in ipairs(slots) do slot.X-=sumX/count; slot.Z-=sumZ/count end
 return slots
end

-- 先保持部隊左右次序，再以距離改良交換；不使用遠端陣列次序當隊形位置。
-- 工作量固定為最多 200 個單位、三輪兩兩比較，沒有每幀／全世界掃描。
function Rules.assign(records,slots,forwardX,forwardZ)
 if type(records)~="table" or type(slots)~="table" or #records~=#slots
  or not countValid(#records,Rules.MAX_SELECTION) or not finite(forwardX) or not finite(forwardZ) then return nil end
 local rightX,rightZ=forwardZ,-forwardX
 local recordOrder,slotOrder={},{}
 for index=1,#records do
  if not pointValid(records[index]) or not pointValid(slots[index]) then return nil end
  recordOrder[index],slotOrder[index]=index,index
 end
 local function ordered(points,a,b)
  local lateralA=points[a].X*rightX+points[a].Z*rightZ
  local lateralB=points[b].X*rightX+points[b].Z*rightZ
  if lateralA~=lateralB then return lateralA<lateralB end
  local depthA=points[a].X*forwardX+points[a].Z*forwardZ
  local depthB=points[b].X*forwardX+points[b].Z*forwardZ
  if depthA~=depthB then return depthA>depthB end
  return a<b
 end
 table.sort(recordOrder,function(a,b) return ordered(records,a,b) end)
 table.sort(slotOrder,function(a,b) return ordered(slots,a,b) end)
 local assigned={}
 for rank,index in ipairs(recordOrder) do assigned[index]=slotOrder[rank] end
 local costs={}
 for recordIndex=1,#records do
  costs[recordIndex]={}
  for slotIndex=1,#slots do
   local dx,dz=records[recordIndex].X-slots[slotIndex].X,records[recordIndex].Z-slots[slotIndex].Z
   local distance=math.sqrt(dx*dx+dz*dz)
   if not finite(distance) then return nil end
   costs[recordIndex][slotIndex]=distance
  end
 end
 for _=1,3 do
  local changed=false
  for a=1,#records-1 do
   for b=a+1,#records do
    local slotA,slotB=assigned[a],assigned[b]
    local current=costs[a][slotA]+costs[b][slotB]
    local swapped=costs[a][slotB]+costs[b][slotA]
    if swapped+EPSILON<current then assigned[a],assigned[b]=slotB,slotA; changed=true end
   end
  end
  if not changed then break end
 end
 return assigned
end

function Rules.plan(config,key,records,target,half,facing)
 if not Rules.validKey(config,key) or type(records)~="table" or not countValid(#records,Rules.MAX_SELECTION)
  or not pointValid(target) or not finite(half) or half<=0 or (facing~=nil and not pointValid(facing))
  or not finite(config.gap) or config.gap<0 or not finite(config.spreadMultiplier) or config.spreadMultiplier<1 then return nil end
 local count,maxRadius,sumX,sumZ=#records,0,0,0
 for index=1,count do
  local record=records[index]
  if not pointValid(record) or not finite(record.radius) or record.radius<=0 or record.radius>=half then return nil end
  maxRadius=math.max(maxRadius,record.radius)
  sumX+=record.X; sumZ+=record.Z
 end
 if not finite(sumX) or not finite(sumZ) then return nil end
 local centroidX,centroidZ=sumX/count,sumZ/count
 local forwardX,forwardZ=target.X-centroidX,target.Z-centroidZ
 local length=math.sqrt(forwardX*forwardX+forwardZ*forwardZ)
 if not finite(length) then return nil end
 if length<EPSILON then
  forwardX,forwardZ=facing and facing.X or 0,facing and facing.Z or -1
  length=math.sqrt(forwardX*forwardX+forwardZ*forwardZ)
  if not finite(length) then return nil end
  if length<EPSILON then forwardX,forwardZ,length=0,-1,1 end
 end
 forwardX,forwardZ=forwardX/length,forwardZ/length
 local spacing=maxRadius*2+config.gap
 if key=="Spread" then spacing*=config.spreadMultiplier end
 if not finite(spacing) or spacing<=0 then return nil end
 -- 保守的旋轉正方形限制，超長橫列／縱隊換列，不將單位擠到一起。
 local squareWidth=2*(half-maxRadius)/(math.abs(forwardX)+math.abs(forwardZ))
 local axisSlots=math.min(Rules.MAX_SELECTION,math.floor(squareWidth/spacing)+1)
 if not countValid(axisSlots,Rules.MAX_SELECTION) then return nil end
 local offsets=Rules.layout(key,count,spacing,axisSlots)
 if not offsets then return nil end
 local rightX,rightZ=forwardZ,-forwardX
 local minX,maxX,minZ,maxZ=math.huge,-math.huge,math.huge,-math.huge
 local slots={}
 for index,offset in ipairs(offsets) do
  local x,z=rightX*offset.X+forwardX*offset.Z,rightZ*offset.X+forwardZ*offset.Z
  minX,maxX,minZ,maxZ=math.min(minX,x),math.max(maxX,x),math.min(minZ,z),math.max(maxZ,z)
  slots[index]={X=x,Z=z}
 end
 local lowX,highX=-half+maxRadius-minX,half-maxRadius-maxX
 local lowZ,highZ=-half+maxRadius-minZ,half-maxRadius-maxZ
 if lowX>highX or lowZ>highZ then return nil end
 -- 平移整組以保留形狀；逐個 clamp 會在地圖邊緣重疊。
 local centerX,centerZ=math.clamp(target.X,lowX,highX),math.clamp(target.Z,lowZ,highZ)
 for _,slot in ipairs(slots) do
  slot.X+=centerX; slot.Z+=centerZ
  if not pointValid(slot) then return nil end
 end
 local assignment=Rules.assign(records,slots,forwardX,forwardZ)
 if not assignment then return nil end
 return {slots=slots,assignment=assignment,forwardX=forwardX,forwardZ=forwardZ,centerX=centerX,centerZ=centerZ,spacing=spacing}
end
return Rules
