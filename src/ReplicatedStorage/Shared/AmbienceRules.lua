-- Pure, bounded rules for client-only idle life: wind, grass layout and per-frame budgets.
-- Nothing here touches gameplay; the same inputs always give the same meadow and the same gusts.
local Rules={
 UpdateInterval=.2,
 -- Appearance parts rewritten per rendered frame by the slow ring (trees and grass take turns).
 WriteBudget=420,
 MaxTrees=320,MaxBuildings=48,MaxSmoke=16,
 ResourceCell=32,
 GrassCell=7,GrassDensity=.8,MaxTufts=640,MaxNewTufts=120,GrassSeed=2718,FlowerChance=.55,
 ScreenMargin=90,MinViewRadius=90,MaxViewRadius=400,
 -- Unit wind direction on the ground plane (X,Z) and the average lean into it.
 WindX=.8,WindZ=.6,Lean=.25,
 -- Crown travel in studs; whole-model rocking and grass bending in radians.
 CrownSway=.7,RockAngle=.035,BushAngle=.08,TuftAngle=.3,
 SailSpeed=.55,
 MaxFlocks=2,FlockMin=3,FlockMax=5,FlockSpeed=26,FlockGapMin=9,FlockGapMax=22,FlockSeconds=26,
}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function mix(n)
 n=bit32.bxor(n,bit32.rshift(n,15)); n=(n*1103515)%4294967296
 n=bit32.bxor(n,bit32.rshift(n,13)); n=(n*741103)%4294967296
 return bit32.bxor(n,bit32.rshift(n,16))
end
-- Stable 0..1 value per integer cell; salt gives independent values for the same cell.
function Rules.Hash(x,z,seed,salt)
 return mix((x*73856093+z*19349663+(seed%1000003)*83492791+(salt or 0)*2971)%4294967296)/4294967296
end
-- Gust strength -1..1: two travelling waves, so a forest ripples downwind instead of pulsing in unison.
function Rules.Gust(x,z,t)
 if not finite(x) or not finite(z) or not finite(t) then return 0 end
 local along=x*Rules.WindX+z*Rules.WindZ
 local across=x*Rules.WindZ-z*Rules.WindX
 return .6*math.sin(along*.0449-t*1.496)+.4*math.sin(along*.1186+across*.07-t*2.732)
end
-- Ground radius worth animating around the camera focus, and how much grass survives zooming out.
function Rules.ViewRadius(cameraHeight)
 if not finite(cameraHeight) then return Rules.MinViewRadius end
 return math.clamp(cameraHeight*1.6,Rules.MinViewRadius,Rules.MaxViewRadius)
end
function Rules.Density(cameraHeight)
 if not finite(cameraHeight) or cameraHeight<=0 then return Rules.GrassDensity end
 return Rules.GrassDensity*math.clamp((170/cameraHeight)^2,.12,1)
end
-- Roads, courtyards, the crossroads and the shore stay bare (mirrors MapGenerator's scenery).
function Rules.Bare(x,z,mapSize,roadWidth)
 if not finite(x) or not finite(z) or not finite(mapSize) or not finite(roadWidth) then return true end
 local half=mapSize/2
 local ax,az=math.abs(x),math.abs(z)
 if ax>half-6 or az>half-6 then return true end
 if math.abs(ax-az)/math.sqrt(2)<roadWidth/2+1.5 then return true end
 if ax<38 and az<38 then return true end
 local base=half-168
 return math.abs(ax-base)<43.5 and math.abs(az-base)<43.5
end
local function lattice(cx,cz,scale,salt)
 local fx,fz=cx/scale,cz/scale
 local x0,z0=math.floor(fx),math.floor(fz)
 local tx,tz=fx-x0,fz-z0
 tx,tz=tx*tx*(3-2*tx),tz*tz*(3-2*tz)
 local seed=Rules.GrassSeed
 local near=Rules.Hash(x0,z0,seed,salt)+(Rules.Hash(x0+1,z0,seed,salt)-Rules.Hash(x0,z0,seed,salt))*tx
 local far=Rules.Hash(x0,z0+1,seed,salt)+(Rules.Hash(x0+1,z0+1,seed,salt)-Rules.Hash(x0,z0+1,seed,salt))*tx
 return near+(far-near)*tz
end
-- Smooth 0..1 field over grass cells: broad drifts broken up by a finer layer. It decides where
-- the meadow thickens, thins out and blooms, so nothing lines up with the cell grid.
function Rules.Patch(cx,cz,salt)
 return .65*lattice(cx,cz,6,salt)+.35*lattice(cx,cz,2.5,salt+1)
end
-- At most one tuft per grass cell. Tufts gather in irregular patches with bare gaps between
-- them. rank decides which tufts remain when the camera zooms out, so thinning never
-- reshuffles the meadow.
function Rules.Tuft(cx,cz)
 local seed,cell=Rules.GrassSeed,Rules.GrassCell
 local cover=math.clamp((Rules.Patch(cx,cz,20)-.4)/.2,0,1)
 if cover<=0 then return nil end
 local rank=Rules.Hash(cx,cz,seed,1)/cover
 if rank>=Rules.GrassDensity then return nil end
 -- Mostly short tufts, shorter still towards the edge of a patch.
 local tall=Rules.Hash(cx,cz,seed,5)
 local flower=0
 if Rules.Patch(cx,cz,30)>.57 and Rules.Hash(cx,cz,seed,8)<Rules.FlowerChance then
  -- A drift of flowers shares one colour, with the odd stray.
  local stray=Rules.Hash(cx,cz,seed,9)
  flower=1+math.floor((stray<.2 and stray*5 or Rules.Hash(math.floor(cx/6),math.floor(cz/6),seed,10))*4)
 end
 return {
  rank=rank,
  x=(cx+Rules.Hash(cx,cz,seed,2))*cell,
  z=(cz+Rules.Hash(cx,cz,seed,3))*cell,
  yaw=Rules.Hash(cx,cz,seed,4)*math.pi*2,
  height=(.8+.9*tall*tall)*(.7+.3*cover),
  width=1.1+.9*Rules.Hash(cx,cz,seed,6),
  spread=1.1+1.6*Rules.Hash(cx,cz,seed,11),
  tone=math.clamp((Rules.Patch(cx,cz,40)-.25)*1.5+.25*Rules.Hash(cx,cz,seed,7),0,1),
  flower=flower,
 }
end
return Rules
