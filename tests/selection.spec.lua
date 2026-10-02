local Rules=require("../src/ReplicatedStorage/Shared/SelectionRules")
local checks=0
local function expect(ok,message) checks+=1; assert(ok,message) end
-- Click versus drag.
expect(not Rules.isDrag(100,100,105,105),"a small slip should stay a click")
expect(Rules.isDrag(100,100,109,100),"a 9 px move should start a drag")
expect(not Rules.isDrag(100,100,0/0,100),"non-finite input must not start a drag")
-- The box is the same whichever corner the drag starts from.
local box=Rules.box(300,260,100,120)
expect(box.left==100 and box.top==120 and box.right==300 and box.bottom==260,"box corners should be normalised")
expect(Rules.box(1,2,math.huge,4)==nil,"non-finite box should be rejected")
expect(Rules.isSmall(Rules.box(0,0,20,10)) and not Rules.isSmall(Rules.box(0,0,20,30)),"small box classification")
expect(not Rules.isSmall(nil),"missing box is not a small box")
-- A unit standing at x=200 with feet at y=300 and head at y=250, 12 px half width.
local unit=Rules.unitRect(200,300,200,250,12)
expect(unit.left==188 and unit.right==212 and unit.top==250 and unit.bottom==300,"unit silhouette from feet, head and width")
-- The old centre-point test missed all of these.
expect(Rules.overlaps(Rules.box(100,290,195,400),unit),"sweeping across the legs should select")
expect(Rules.overlaps(Rules.box(205,100,400,255),unit),"sweeping across the head should select")
expect(Rules.overlaps(Rules.box(210,270,400,280),unit),"clipping the side should select")
expect(Rules.overlaps(Rules.box(0,0,1000,1000),unit),"a box containing the unit should select")
expect(Rules.overlaps(Rules.box(195,260,205,270),unit),"a box inside the unit should select")
expect(not Rules.overlaps(Rules.box(100,100,180,400),unit),"a box beside the unit should miss")
expect(not Rules.overlaps(Rules.box(100,310,400,400),unit),"a box below the feet should miss")
expect(not Rules.overlaps(Rules.box(100,100,400,240),unit),"a box above the head should miss")
expect(not Rules.overlaps(nil,unit) and not Rules.overlaps(box,nil),"missing geometry never selects")
-- Zoomed-out units keep a catchable minimum size.
local tiny=Rules.unitRect(500,400,500,398,1)
expect(tiny.right-tiny.left==Rules.minHalfSize*2 and tiny.bottom-tiny.top==Rules.minHalfSize*2,"distant unit keeps a minimum silhouette")
expect(Rules.overlaps(Rules.box(505,300,600,395),tiny),"distant unit is catchable near its edge")
-- Tilted projection: head and feet differ horizontally.
local tilted=Rules.unitRect(100,200,120,150,10)
expect(tilted.left==90 and tilted.right==130,"tilted silhouette spans feet and head")
expect(Rules.unitRect(0/0,1,2,3,4)==nil,"non-finite projection has no silhouette")
local fallback=Rules.unitRect(10,40,10,10,0/0)
expect(fallback.right-fallback.left==Rules.minHalfSize*2,"non-finite width falls back to the minimum")
print(string.format("selection rules: %d checks passed",checks))
