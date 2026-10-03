-- 戰爭迷霧的純規則（AOE2 式黑色地圖）：格子、視野圓、探索紀錄與每列的連續區段。
-- 客戶端用它畫地面上的黑幕／暗霧並決定敵方單位是否可見；不依賴 Roblox 物件，CLI 可測。
-- 每格狀態：0＝未探索（黑色），1＝探索過但目前看不到（暗霧），2＝目前看得到。
local FogRules = {}

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function FogRules.new(mapSize,cell)
 if not finite(mapSize) or mapSize<=0 or not finite(cell) or cell<=0 then return nil end
 local count=math.ceil(mapSize/cell)
 if count>512 then return nil end
 return {size=mapSize,cell=cell,count=count,explored={},seen={},generation=0}
end

-- 世界座標所在的格子（1 起算）；地圖外回傳 nil。
function FogRules.cellOf(grid,x,z)
 if not finite(x) or not finite(z) then return nil end
 local half=grid.size/2
 local column=math.floor((x+half)/grid.cell)+1
 local row=math.floor((z+half)/grid.cell)+1
 if column<1 or row<1 or column>grid.count or row>grid.count then return nil end
 return column,row
end

local function key(grid,column,row) return (row-1)*grid.count+column end

-- 重新計算目前視野。sources：{X,Z,radius}。回傳本次狀態有改變的列（row → true）。
-- 以世代編號標記可見，不必每次清空整張表。
function FogRules.update(grid,sources)
 local previous=grid.generation
 local generation=previous+1
 grid.generation=generation
 local seen,explored,count,cell=grid.seen,grid.explored,grid.count,grid.cell
 local half=grid.size/2
 local changed={}
 for _,source in ipairs(sources or {}) do
  local x,z,radius=source.X,source.Z,source.radius
  if finite(x) and finite(z) and finite(radius) and radius>0 then
   local firstRow=math.max(1,math.floor((z-radius+half)/cell)+1)
   local lastRow=math.min(count,math.floor((z+radius+half)/cell)+1)
   for row=firstRow,lastRow do
    -- 以該列中心線與圓的交點決定範圍；圓心所在的列整列以半徑計。
    local centerZ=(row-0.5)*cell-half
    local dz=math.abs(centerZ-z)
    if math.floor((z+half)/cell)+1==row then dz=0 end
    if dz<=radius then
     local width=math.sqrt(radius*radius-dz*dz)
     local first=math.max(1,math.floor((x-width+half)/cell)+1)
     local last=math.min(count,math.floor((x+width+half)/cell)+1)
     for column=first,last do
      local index=(row-1)*count+column
      if seen[index]~=generation then
       if seen[index]~=previous or not explored[index] then changed[row]=true end
       seen[index]=generation
       explored[index]=true
      end
     end
    end
   end
  end
 end
 -- 上一輪看得到、這一輪看不到的格子也算改變。
 for index,mark in pairs(seen) do
  if mark==previous then
   changed[math.floor((index-1)/count)+1]=true
   seen[index]=nil
  end
 end
 return changed
end

function FogRules.stateAt(grid,column,row)
 local index=key(grid,column,row)
 if grid.seen[index]==grid.generation then return 2 end
 return grid.explored[index] and 1 or 0
end

function FogRules.visibleAt(grid,x,z)
 local column,row=FogRules.cellOf(grid,x,z)
 return column~=nil and FogRules.stateAt(grid,column,row)==2
end

function FogRules.exploredAt(grid,x,z)
 local column,row=FogRules.cellOf(grid,x,z)
 return column~=nil and grid.explored[key(grid,column,row)]==true
end

-- 把整片地圖標為已探索（觀戰、遊戲結束或關閉迷霧時使用）。
function FogRules.revealAll(grid)
 for index=1,grid.count*grid.count do grid.explored[index]=true end
end

-- 一列中未探索（0）與暗霧（1）的連續區段：{first, last, state}。看得到的格子不輸出。
function FogRules.runs(grid,row)
 local result={}
 local current,first=nil,nil
 for column=1,grid.count+1 do
  local state=column<=grid.count and FogRules.stateAt(grid,column,row) or nil
  if state==2 then state=nil end
  if state~=current then
   if current~=nil then table.insert(result,{first=first,last=column-1,state=current}) end
   current,first=state,column
  end
 end
 return result
end

-- 單位或建築的視野半徑。bonus 為比例加成（例如城鎮守望 0.3）。
function FogRules.radius(config,kind,isBuilding,bonus)
 if type(config)~="table" then return 0 end
 local list=isBuilding and config.buildings or config.units
 local base=type(list)=="table" and list[kind] or nil
 if not finite(base) then base=isBuilding and config.buildingDefault or config.unitDefault end
 if not finite(base) or base<0 then return 0 end
 return base*(1+(finite(bonus) and math.max(0,bonus) or 0))
end

return FogRules
