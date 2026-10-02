-- Pure drag-box selection geometry in screen pixels. No engine globals.
local Rules = {dragThreshold=8,smallBox=24,minHalfSize=9}
local function finite(value)
 return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function allFinite(...)
 for index=1,select("#",...) do if not finite((select(index,...))) then return false end end
 return true
end
-- A press that travels less than the threshold stays a click.
function Rules.isDrag(ax,ay,bx,by)
 if not allFinite(ax,ay,bx,by) then return false end
 local dx,dy=bx-ax,by-ay
 return dx*dx+dy*dy>Rules.dragThreshold*Rules.dragThreshold
end
function Rules.box(ax,ay,bx,by)
 if not allFinite(ax,ay,bx,by) then return nil end
 return {left=math.min(ax,bx),top=math.min(ay,by),right=math.max(ax,bx),bottom=math.max(ay,by)}
end
-- A slipped click: a box too small to be a deliberate sweep. When it catches
-- nothing the caller falls back to an ordinary click instead of deselecting.
function Rules.isSmall(box)
 return box~=nil and box.right-box.left<Rules.smallBox and box.bottom-box.top<Rules.smallBox
end
-- Screen silhouette of a unit from its projected feet and head plus its
-- projected half width. Far-away units keep a minimum size so they stay catchable.
function Rules.unitRect(feetX,feetY,headX,headY,halfWidth)
 if not allFinite(feetX,feetY,headX,headY) then return nil end
 local half=math.max(finite(halfWidth) and math.abs(halfWidth) or 0,Rules.minHalfSize)
 local left,right=math.min(feetX,headX)-half,math.max(feetX,headX)+half
 local top,bottom=math.min(feetY,headY),math.max(feetY,headY)
 local missing=Rules.minHalfSize*2-(bottom-top)
 if missing>0 then top-=missing/2; bottom+=missing/2 end
 return {left=left,top=top,right=right,bottom=bottom}
end
-- Any overlap counts: sweeping across legs or a helmet selects the unit.
function Rules.overlaps(box,rect)
 if not box or not rect then return false end
 return rect.right>=box.left and rect.left<=box.right and rect.bottom>=box.top and rect.top<=box.bottom
end
return Rules
