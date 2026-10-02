-- Pure gesture state shared by command input and the camera. No engine globals.
local Rules = {}
local modes = {select=true,move=true,gather=true,attack=true,build=true}
local function finite(value)
 return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
function Rules.validMode(mode) return modes[mode]==true end
function Rules.inRect(x,y,left,top,width,height)
 if not finite(x) or not finite(y) or not finite(left) or not finite(top) or not finite(width) or not finite(height) or width<=0 or height<=0 then return false end
 return x>=left and y>=top and x<left+width and y<top+height
end
function Rules.edgeDirection(rawX,rawY,insetX,insetY,width,height,margin)
 margin=margin or 10
 if not finite(rawX) or not finite(rawY) or not finite(insetX) or not finite(insetY) or not finite(width) or not finite(height) or not finite(margin) then return 0,0 end
 if width<=0 or height<=0 or margin<=0 then return 0,0 end
 local x,y=rawX-insetX,rawY-insetY
 if not Rules.inRect(x,y,0,0,width,height) then return 0,0 end
 local horizontal,vertical=0,0
 if x<margin then horizontal=-1 elseif x>width-margin then horizontal=1 end
 if y<margin then vertical=-1 elseif y>height-margin then vertical=1 end
 return horizontal,vertical
end
function Rules.new()
 return {points={},order={},tapSlop=18,maxTapSeconds=0.65}
end
function Rules.reset(state)
 table.clear(state.points); table.clear(state.order)
end
function Rules.cancelCommands(state)
 -- UI actions can change modes while another finger is still held. Preserve
 -- those IDs until release so the next finger cannot become a false solo tap.
 for _,id in ipairs(state.order) do state.points[id].cancelled=true end
end
function Rules.begin(state,id,x,y,time,blocked)
 if id==nil or not finite(x) or not finite(y) or not finite(time) then return nil end
 if state.points[id] then return nil end
 local point={id=id,x=x,y=y,startX=x,startY=y,time=time,blocked=blocked==true,cancelled=false,moved=false}
 state.points[id]=point; table.insert(state.order,id)
 -- Every touch in a multi-finger sequence loses its tap/placement permission,
 -- including a finger that began on UI. Lifting one finger cannot issue an order.
 if #state.order>1 then
  for _,key in ipairs(state.order) do state.points[key].cancelled=true end
 end
 return point
end
function Rules.move(state,id,x,y,blocked)
 local point=state.points[id]
 if not point then return nil end
 if not finite(x) or not finite(y) then point.blocked=true; return point end
 point.x,point.y=x,y
 if blocked then point.blocked=true end
 local dx,dy=x-point.startX,y-point.startY
 if dx*dx+dy*dy>state.tapSlop*state.tapSlop then point.moved=true end
 return point
end
function Rules.finish(state,id,x,y,time,blocked)
 local point=Rules.move(state,id,x,y,blocked)
 if not point then return nil end
 state.points[id]=nil
 local index=table.find(state.order,id); if index then table.remove(state.order,index) end
 local elapsed=finite(time) and time-point.time or -1
 local allowed=not point.blocked and not point.cancelled and elapsed>=0
 return {x=point.x,y=point.y,tap=allowed and not point.moved and elapsed<=state.maxTapSeconds,place=allowed}
end
function Rules.single(state)
 if #state.order~=1 then return nil end
 local point=state.points[state.order[1]]
 return not point.blocked and not point.cancelled and point or nil
end
function Rules.pair(state)
 if #state.order~=2 then return nil end
 local a,b=state.points[state.order[1]],state.points[state.order[2]]
 if a.blocked or b.blocked then return nil end
 local dx,dy=b.x-a.x,b.y-a.y
 return {x=(a.x+b.x)/2,y=(a.y+b.y)/2,distance=math.sqrt(dx*dx+dy*dy),a=a.id,b=b.id}
end
function Rules.zoom(height,previousDistance,distance)
 if not finite(height) or not finite(previousDistance) or not finite(distance) or previousDistance<8 or distance<8 then return height end
 return math.clamp(height*previousDistance/distance,65,360)
end
return Rules
