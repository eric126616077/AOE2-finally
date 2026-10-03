-- Fallback art: people, mounts and siege engines. Front faces -Z; feet stand on y=0.
-- Toy-soldier proportions: stub legs, flared tunic, big head and mitten hands, so headgear,
-- weapon and player color read from the far top-down camera. Units are never scaled, and
-- part names / pivots follow UnitMotion.client.lua (see docs/ART-STYLE.md).
local K=require(script.Parent.ArtKit)
local stone,timber,cutWood,plaster,iron,dark,straw,gold=K.stone,K.timber,K.cutWood,K.plaster,K.iron,K.dark,K.straw,K.gold
local block,beam,round,disc,ball,segment,plate,point,turn=K.block,K.beam,K.round,K.disc,K.ball,K.segment,K.plate,K.point,K.turn
local steel,skin,leather=K.steel,K.skin,K.leather
local V=Vector3.new
local Metal,Fabric,Planks=Enum.Material.Metal,Enum.Material.Fabric,Enum.Material.WoodPlanks
local blade=Color3.fromRGB(208,216,218)
local mail=Color3.fromRGB(118,130,136)
local linen=Color3.fromRGB(222,206,170)
local hair=Color3.fromRGB(84,58,40)
local hide=Color3.fromRGB(122,88,60)
local tan=Color3.fromRGB(176,140,94)
local forest=Color3.fromRGB(92,112,64)
local forestDark=Color3.fromRGB(70,90,54)
local habit=Color3.fromRGB(226,212,184)
-- Opt a part in or out of the player color whatever its name.
local function tint(part,on) part:SetAttribute("TeamColorPart",on); return part end
local function append(list,more) for _,p in ipairs(more) do table.insert(list,p) end; return list end
-- Villager hand tools follow the job. Every piece keeps the Tool / ToolHead names
-- of the right-arm animation group and is held in the right hand, head toward -Z.
local toolKinds={axe=true,pick=true,hoe=true,hammer=true,basket=true,spear=true}
local function villagerTool(model,tool)
 local parts={}
 local function add(part) table.insert(parts,part); return part end
 local x,z=1.38,-.35
 if tool=="pick" then
  add(block(model,"Tool",V(.22,3.3,.22),V(x,2.45,z),cutWood))
  add(block(model,"ToolHead",V(.3,.4,1.3),V(x,4,z),iron,Metal))
  for _,side in ipairs({-1,1}) do
   add(block(model,"ToolHead",V(.22,.3,.95),V(x,3.8,z+side*1),blade,Metal)).CFrame*=CFrame.Angles(side*.5,0,0)
  end
 elseif tool=="hoe" then
  add(block(model,"Tool",V(.2,3.8,.2),V(x,2.6,z),cutWood))
  add(block(model,"ToolHead",V(.18,.18,.7),V(x,4.4,z-.3),iron,Metal))
  add(block(model,"ToolHead",V(.8,.75,.14),V(x,4.1,z-.62),blade,Metal))
 elseif tool=="hammer" then
  add(block(model,"Tool",V(.22,2.7,.22),V(x,2.45,z),cutWood))
  add(block(model,"ToolHead",V(.62,.62,1.3),V(x,3.75,z),iron,Metal))
  add(block(model,"ToolHead",V(.7,.7,.3),V(x,3.75,z-.6),blade,Metal))
 elseif tool=="spear" then
  -- Hunting spear: a long shaft with a broad leaf blade and a crossbar lug.
  add(block(model,"Tool",V(.2,5.2,.2),V(x,3.3,z),cutWood))
  add(block(model,"ToolHead",V(.5,.14,.14),V(x,5.6,z),iron,Metal))
  for _,piece in ipairs(point(model,"ToolHead",V(x,5.75,z),.5,1.1,.14,blade,Metal)) do add(piece) end
 elseif tool=="basket" then
  add(round(model,"Tool",1.4,.9,V(x,1.5,-.45),straw,Fabric))
  add(round(model,"Tool",1.54,.18,V(x,1.95,-.45),cutWood,Enum.Material.Wood))
  add(ball(model,"ToolHead",.55,V(x-.25,2.05,-.7),Color3.fromRGB(184,54,72)))
  add(ball(model,"ToolHead",.5,V(x+.25,2.03,-.75),Color3.fromRGB(148,38,62)))
 else
  add(block(model,"Tool",V(.22,3.3,.22),V(x,2.45,z),cutWood))
  add(block(model,"ToolHead",V(.28,.75,.7),V(x,3.65,z-.4),iron,Metal))
  add(block(model,"ToolHead",V(.16,1.15,.36),V(x,3.65,z-.9),blade,Metal))
 end
 return parts
end
-- Goods on the back show what a villager is hauling to the drop-off.
local carryKinds={food=true,wood=true,gold=true,stone=true,relic=true,trade=true}
local function carryLoad(model,kind)
 local parts={}
 local function add(part) table.insert(parts,part); return part end
 if kind=="relic" then
  -- A monk shoulders the gilded reliquary; the gem glows so a carrier is easy to spot and chase.
  add(block(model,"Carry",V(1.7,1.1,1.1),V(0,3.3,1.25),gold,Metal))
  add(block(model,"Carry",V(1.85,.18,1.25),V(0,3.92,1.25),Color3.fromRGB(176,128,46),Metal))
  add(block(model,"Carry",V(.4,.4,.1),V(0,3.35,1.85),Color3.fromRGB(120,214,255),Enum.Material.Neon))
 elseif kind=="trade" then
  -- Bales and a strongbox stacked on the cart bed show a loaded trade cart.
  add(block(model,"Carry",V(1.5,1.2,1.4),V(-.85,3.5,2.6),straw,Fabric))
  add(block(model,"Carry",V(1.4,1.1,1.3),V(.85,3.45,3.9),linen,Fabric))
  add(block(model,"Carry",V(1.2,.9,1.1),V(.8,3.35,2.4),cutWood,Planks))
  add(block(model,"Carry",V(1.3,.25,1.2),V(.8,3.9,2.4),gold,Metal))
 elseif kind=="wood" then
  for i,at in ipairs({V(0,2.45,1.05),V(0,3.1,1.05),V(0,2.8,1.62)}) do
   add(plate(model,"Carry",.64,2.5,at,i==3 and timber or cutWood,Enum.Material.Wood))
  end
 elseif kind=="food" then
  add(ball(model,"Carry",1.55,V(0,2.7,1.3),linen,Fabric))
  add(round(model,"Carry",.6,.45,V(0,3.55,1.3),linen,Fabric))
  add(round(model,"Carry",.66,.14,V(0,3.4,1.3),leather,Fabric))
 else
  add(round(model,"Carry",1.6,1.2,V(0,2.55,1.35),straw,Fabric))
  if kind=="gold" then
   add(ball(model,"Carry",.8,V(-.3,3.25,1.3),Color3.fromRGB(236,190,72),Metal))
   add(ball(model,"Carry",.66,V(.35,3.2,1.45),Color3.fromRGB(236,190,72),Metal))
  else
   add(block(model,"Carry",V(.9,.6,.8),V(-.2,3.3,1.3),Color3.fromRGB(136,146,150),Enum.Material.Slate)).CFrame*=CFrame.Angles(0,.4,.15)
   add(block(model,"Carry",V(.6,.5,.6),V(.42,3.25,1.5),stone,Enum.Material.Slate)).CFrame*=CFrame.Angles(.2,-.3,0)
  end
 end
 return parts
end
-- Shared body. Arms hang from the client shoulder pivots (+-1.4,3.7,0) and end in a
-- hand at y 2.15, where every weapon and tool is gripped.
local grip=V(1.38,2.15,-.35)
local function figure(model,o)
 local metal=o.metal and Metal or nil
 for _,side in ipairs({-1,1}) do
  local arm=side<0 and "ArmL" or "ArmR"
  block(model,side<0 and "BootL" or "BootR",V(.82,1.3,1.05),V(side*.5,.65,-.05),o.boot or leather)
  block(model,arm,V(.7,1.3,.8),V(side*1.38,3.02,0),o.sleeve or o.cloth,metal or Fabric)
  ball(model,arm,.74,V(side*1.38,2.15,-.05),o.glove or skin)
  if o.pauldron then ball(model,arm,1.02,V(side*1.3,3.62,0),o.pauldron,Metal) end
 end
 local skirt=block(model,"Body",V(2.2,1,1.5),V(0,1.65,0),o.skirt or o.cloth,metal)
 local body=block(model,"Body",V(1.95,1.55,1.3),V(0,2.85,0),o.cloth,metal)
 block(model,"Belt",V(2.06,.3,1.4),V(0,2.2,0),o.belt or leather,Fabric)
 if not o.helm then
  ball(model,"Head",1.85,V(0,4.5,-.05),skin)
  for _,side in ipairs({-1,1}) do block(model,"Head",V(.17,.28,.1),V(side*.3,4.55,-.93),dark) end
 end
 return body,skirt
end
local function sword(model,lean)
 local parts={block(model,"Sword",V(.24,.7,.24),grip,leather),
  block(model,"Sword",V(.3,.22,1.1),grip+V(0,.45,0),gold,Metal),
  block(model,"Sword",V(.16,2.2,.42),grip+V(0,1.65,0),blade,Metal)}
 append(parts,point(model,"Sword",grip+V(0,2.75,0),.42,.5,.16,blade,Metal))
 turn(parts,grip,CFrame.Angles(-lean,0,0))
end
-- Shields ride the left arm, turned toward the front and tipped up to face the camera.
local shieldPivot=V(-1.6,2.9,0)
local shieldTurn=CFrame.Angles(0,-.6,0)*CFrame.Angles(0,0,-.16)
local function kiteShield(model,team)
 local c=V(-1.68,3,-.05)
 local parts={block(model,"Shield",V(.26,1.5,1.8),c,team,Planks)}
 append(parts,point(model,"Shield",c-V(0,.75,0),1.8,1.1,.26,team,Planks,true))
 -- Pale cross: named for the arm group so it swings with the shield but stays uncolored.
 table.insert(parts,block(model,"ArmL",V(.3,2.2,.34),c+V(-.03,-.3,0),linen))
 table.insert(parts,block(model,"ArmL",V(.3,.34,1.82),c+V(-.03,.25,0),linen))
 turn(parts,shieldPivot,shieldTurn)
end
local function roundShield(model,team,d)
 local c=V(-1.78,2.8,-.05)
 turn({plate(model,"Shield",d,.26,c,team,Planks),plate(model,"ArmL",d*.34,.4,c-V(.03,0,0),iron,Metal)},shieldPivot,shieldTurn)
end
local function horse(model,team,barded)
 local coat=barded and Color3.fromRGB(78,64,56) or Color3.fromRGB(156,104,62)
 local points=barded and Color3.fromRGB(48,40,36) or Color3.fromRGB(92,60,40)
 if barded then
  -- Caparison boxes the whole barrel: a large player-colored slab from above.
  block(model,"HorseCloth",V(2.75,1.4,6),V(0,4.05,.2),team,Fabric)
  block(model,"HorseCloth",V(3,1.35,6.2),V(0,2.8,.2),team,Fabric)
  block(model,"HorseBody",V(3.08,.22,6.28),V(0,2.22,.2),gold,Fabric)
  segment(model,"HorseCloth",V(0,3.8,-2.3),V(0,5.2,-2.9),1.35,1.8,team,Fabric)
 else
  -- Capsule barrel (cylinder plus chest / rump balls) reads as a horse from above.
  disc(model,"HorseBody",2.5,3.6,V(0,3.4,.15),coat)
  ball(model,"HorseBody",2.6,V(0,3.5,-1.6),coat)
  ball(model,"HorseBody",2.7,V(0,3.5,1.95),coat)
  block(model,"HorseCloth",V(2.75,1.15,2.5),V(0,4,.2),team,Fabric)
 end
 for _,x in ipairs({-.74,.74}) do for _,z in ipairs({-1.7,2}) do
  block(model,"HorseLeg",V(.8,2.7,.9),V(x,1.35,z),points)
 end end
 segment(model,"HorseNeck",V(0,3.9,-2.2),V(0,6,-3.2),1.15,1.6,coat)
 segment(model,"Mane",V(0,4.7,-1.75),V(0,6.75,-2.8),.42,.6,points)
 local brow,muzzle=V(0,6.3,-3),V(0,5,-4.45)
 local face=(muzzle-brow).Unit
 segment(model,"HorseHead",brow,muzzle,1.02,1.12,coat)
 segment(model,"HorseHead",muzzle-face*.55,muzzle+face*.12,1.08,1.02,points)
 for _,side in ipairs({-1,1}) do
  block(model,"HorseHead",V(.24,.62,.4),brow+V(side*.32,.5,.2),coat,nil,"WedgePart")
 end
 if barded then segment(model,"HorseHead",brow+V(0,.25,.1),muzzle+V(0,.3,.35),1.1,.7,steel,Metal) end
 segment(model,"Mane",V(0,4.4,barded and 3.15 or 3.05),V(0,2.1,3.8),.55,.65,points)
 block(model,"Saddle",V(1.8,.45,1.9),V(0,4.82,.2),team,Fabric)
 block(model,"HorseBody",V(1.5,.75,.35),V(0,5.05,1.2),leather)
end
-- Rider sits in the saddle with legs along the horse's flanks.
local function mount(model,team,barded)
 for _,p in ipairs(model:GetChildren()) do
  if p:IsA("BasePart") then
   p.CFrame+=V(0,3.2,0)
   if p.Name=="BootL" or p.Name=="BootR" then
    p.Size=V(.7,1.7,.95)
    p.CFrame=CFrame.new((p.Name=="BootL" and -1 or 1)*1.5,3.8,-.2)
   end
  end
 end
 horse(model,team,barded)
end
local B={}
function B.villager(model,kind,team,stage)
 local body,skirt=figure(model,{cloth=team,sleeve=linen,boot=K.earth})
 body:SetAttribute("TeamColorPart",true)
 skirt:SetAttribute("TeamColorPart",true)
 -- Hair shows under the brim from behind; the wide straw hat is the villager's badge.
 ball(model,"Hat",1.75,V(0,4.5,.22),hair)
 round(model,"Hat",2.9,.16,V(0,5.02,0),straw,Fabric)
 round(model,"Hat",1.55,.6,V(0,5.38,0),straw,Fabric)
 round(model,"HatBand",1.62,.22,V(0,5.22,0),team,Fabric)
 villagerTool(model,"axe")
 model:SetAttribute("ToolKind","axe")
end
function B.infantry(model,kind,team,stage)
 figure(model,{cloth=steel,skirt=mail,sleeve=mail,glove=leather,pauldron=steel,metal=true,boot=iron})
 block(model,"Tabard",V(1.4,2.2,1.74),V(0,2.45,0),team,Fabric)
 ball(model,"Hat",1.95,V(0,4.72,.12),steel,Metal)
 block(model,"Hat",V(.2,.62,.12),V(0,4.55,-.95),iron,Metal)
 block(model,"HatBand",V(.34,.5,1.75),V(0,5.6,.15),team,Fabric)
 sword(model,.3)
 kiteShield(model,team)
end
function B.spearman(model,kind,team,stage)
 figure(model,{cloth=linen,skirt=tan,sleeve=linen,glove=leather,boot=leather})
 block(model,"Tabard",V(1.4,2.2,1.74),V(0,2.45,0),team,Fabric)
 -- Kettle hat: the wide steel brim separates him from the crested swordsman.
 ball(model,"Hat",1.75,V(0,4.82,.02),steel,Metal)
 round(model,"Hat",2.55,.16,V(0,4.95,0),steel,Metal)
 round(model,"HatBand",1.8,.22,V(0,5.14,0),team,Fabric)
 local x,z=grip.X,grip.Z
 block(model,"Spear",V(.22,7,.22),V(x,3.8,z),cutWood,Enum.Material.Wood)
 block(model,"Spearhead",V(.32,.34,.32),V(x,7.3,z),iron,Metal)
 point(model,"Spearhead",V(x,7.44,z),.56,1.15,.14,blade,Metal)
 tint(block(model,"Spear",V(.1,.7,1.25),V(x,6.55,z+.72),team,Fabric),true)
 roundShield(model,team,2.3)
end
function B.skirmisher(model,kind,team,stage)
 figure(model,{cloth=tan,skirt=hide,boot=hide})
 block(model,"Belt",V(.5,1.75,1.5),V(-.35,2.9,0),leather,Fabric).CFrame*=CFrame.Angles(0,0,-.5)
 ball(model,"Hat",1.9,V(0,4.62,.14),hair)
 round(model,"HatBand",1.98,.26,V(0,4.98,0),team,Fabric)
 block(model,"HatBand",V(.3,.9,.12),V(.2,4.5,1.1),team,Fabric).CFrame*=CFrame.Angles(.25,0,.2)
 -- Throwing javelin levelled forward in the hand, two spares slung across the back.
 local shaft={block(model,"Spear",V(.18,4.2,.18),grip+V(0,.45,0),cutWood,Enum.Material.Wood)}
 append(shaft,point(model,"Spearhead",grip+V(0,2.55,0),.44,.85,.14,blade,Metal))
 turn(shaft,grip,CFrame.Angles(-.95,0,0))
 block(model,"Quiver",V(.75,1.5,.5),V(.1,2.9,.9),leather).CFrame*=CFrame.Angles(0,0,-.35)
 for _,x in ipairs({-.18,.2}) do
  local a,b=V(x-.55,1.9,.95),V(x+.75,5.2,.95)
  beam(model,"Quiver",a,b,.16,cutWood,Enum.Material.Wood)
  beam(model,"Quiver",b,b+(b-a).Unit*.6,.24,blade,Metal)
 end
 roundShield(model,team,1.7)
end
-- Curved bow from connected limb segments; the string closes the arc. scale shortens a horse bow.
local function bow(model,scale)
 local hold=V(1.84,2.3,-.45)
 local arc={}
 for i=0,4 do local t=i/2-1; table.insert(arc,hold+V(0,t*2*scale,t*t*.85*scale)) end
 for i=1,4 do beam(model,"Bow",arc[i],arc[i+1],.24,cutWood,Enum.Material.Wood) end
 block(model,"Bow",V(.34,.6,.34),hold,leather)
 block(model,"Bowstring",V(.07,4*scale,.07),hold+V(0,0,.85*scale),plaster)
end
function B.archer(model,kind,team,stage)
 figure(model,{cloth=forest,skirt=forestDark,glove=leather,boot=leather})
 block(model,"Tabard",V(1.3,1.3,1.5),V(0,2.95,0),team,Fabric)
 -- Hood with a trailing tip and a shoulder cowl.
 ball(model,"Hat",2.02,V(0,4.6,.14),forest,Fabric)
 ball(model,"Hat",.85,V(0,4.75,1.05),forest,Fabric)
 round(model,"Hat",2.6,.4,V(0,3.72,.05),forestDark,Fabric)
 block(model,"HatBand",V(.14,1.25,.5),V(.72,5.25,.3),team,Fabric).CFrame*=CFrame.Angles(-.45,0,-.4)
 bow(model,1)
 local top=V(-.55,3.9,1)
 beam(model,"Quiver",V(.6,1.9,1),top,.6,leather)
 local out=(top-V(.6,1.9,1)).Unit
 for _,x in ipairs({-.17,.17}) do beam(model,"Quiver",top+V(x,0,0),top+V(x,0,0)+out*.75,.13,plaster) end
 tint(beam(model,"Quiver",top+out*.55,top+out*.95,.42,team,Fabric),true)
end
function B.monk(model,kind,team,stage)
 figure(model,{cloth=habit,belt=tan,boot=leather})
 block(model,"Robe",V(2.5,.9,1.75),V(0,.95,0),habit,Fabric)
 block(model,"Robe",V(2.8,.5,2),V(0,.25,0),habit,Fabric)
 -- Player-colored mantle and stole ring the tonsured head when seen from above.
 round(model,"Tabard",2.75,.34,V(0,3.66,0),team,Fabric)
 block(model,"Tabard",V(.6,2.6,1.92),V(0,2.2,0),team,Fabric)
 round(model,"Hat",1.96,.36,V(0,4.88,-.02),hair)
 ball(model,"Hat",1.15,V(0,3.95,.8),habit,Fabric)
 local x,z=grip.X,grip.Z
 block(model,"Staff",V(.22,6.2,.22),V(x,3.2,z),timber)
 disc(model,"StaffHead",1.15,.2,V(x,6.7,z),gold,Metal)
 block(model,"StaffHead",V(.24,.5,.24),V(x,7.4,z),gold,Metal)
end
function B.scout(model,kind,team,stage)
 figure(model,{cloth=tan,skirt=hide,sleeve=linen,glove=leather,boot=leather})
 block(model,"Tabard",V(1.9,1.9,.16),V(0,2.75,.82),team,Fabric).CFrame*=CFrame.Angles(.22,0,0)
 ball(model,"Hat",1.9,V(0,4.66,.12),leather,Fabric)
 round(model,"HatBand",1.98,.24,V(0,5,0),team,Fabric)
 block(model,"HatBand",V(.14,1.1,.45),V(.6,5.45,.25),team,Fabric).CFrame*=CFrame.Angles(-.45,0,-.35)
 sword(model,.3)
 roundShield(model,team,1.6)
 mount(model,team,false)
end
function B.cavalry(model,kind,team,stage)
 figure(model,{cloth=steel,skirt=mail,sleeve=mail,glove=leather,pauldron=steel,metal=true,boot=iron,helm=true})
 block(model,"Tabard",V(1.4,2.2,1.74),V(0,2.45,0),team,Fabric)
 -- Flat-topped great helm with a plume.
 round(model,"Hat",1.95,1.7,V(0,4.6,-.02),steel,Metal)
 block(model,"Hat",V(1.3,.18,.12),V(0,4.75,-.96),dark)
 ball(model,"HatBand",.8,V(0,5.6,.2),team,Fabric)
 block(model,"HatBand",V(.4,.5,1.1),V(0,5.45,.85),team,Fabric).CFrame*=CFrame.Angles(-.5,0,0)
 sword(model,.3)
 kiteShield(model,team)
 mount(model,team,true)
end
-- Horse archer: fur-trimmed cap, short recurve bow and a hip quiver, on an unarmored horse.
function B.cavalryArcher(model,kind,team,stage)
 figure(model,{cloth=tan,skirt=forestDark,sleeve=forest,glove=leather,boot=leather})
 block(model,"Tabard",V(1.3,1.6,1.5),V(0,2.85,0),team,Fabric)
 ball(model,"Hat",1.95,V(0,4.7,.1),forest,Fabric)
 round(model,"Hat",2.3,.42,V(0,4.95,0),hide,Fabric)
 round(model,"HatBand",1.2,.5,V(0,5.45,0),team,Fabric)
 bow(model,.75)
 beam(model,"Quiver",V(-1.25,1.6,.5),V(-1.05,3.2,.95),.55,leather)
 for _,x in ipairs({-.12,.12}) do beam(model,"Quiver",V(-1.05+x,3.2,.95),V(-.98+x,3.85,1.12),.12,plaster) end
 mount(model,team,false)
end
-- Camel: tall legs, a long curved neck and a hump the saddle sits behind; named like
-- horse parts so the client gait and corpse rules animate it without a new group.
local function camelBody(model,team)
 local coat,points=Color3.fromRGB(198,160,104),Color3.fromRGB(150,112,70)
 disc(model,"HorseBody",2.4,3.8,V(0,4.6,.3),coat)
 ball(model,"HorseBody",2.5,V(0,4.7,-1.5),coat)
 ball(model,"HorseBody",2.5,V(0,4.6,2.1),coat)
 ball(model,"Hump",2.2,V(0,6,-.6),coat)
 for _,x in ipairs({-.7,.7}) do for _,z in ipairs({-1.6,2.1}) do
  block(model,"HorseLeg",V(.62,3.9,.7),V(x,1.95,z),points)
 end end
 segment(model,"HorseNeck",V(0,5,-2.3),V(0,5.4,-3.9),1,1.1,coat)
 segment(model,"HorseNeck",V(0,5.3,-3.8),V(0,7.2,-4.1),.85,.95,coat)
 segment(model,"HorseHead",V(0,7.3,-3.9),V(0,6.9,-5.3),.9,.85,coat)
 ball(model,"HorseHead",.7,V(0,6.85,-5.3),points)
 for _,side in ipairs({-1,1}) do block(model,"HorseHead",V(.2,.4,.25),V(side*.3,7.75,-3.85),points) end
 block(model,"HorseCloth",V(2.6,1.2,2.2),V(0,5.4,1),team,Fabric)
 block(model,"Saddle",V(1.7,.45,1.6),V(0,6.1,1),team,Fabric)
 segment(model,"Mane",V(0,4.6,3.3),V(0,3.2,3.6),.4,.45,points)
end
function B.camel(model,kind,team,stage)
 figure(model,{cloth=linen,skirt=tan,sleeve=linen,glove=leather,boot=leather})
 block(model,"Tabard",V(1.4,2.1,1.74),V(0,2.5,0),team,Fabric)
 -- Wrapped turban with a trailing tail in the player color.
 ball(model,"Hat",1.95,V(0,4.75,.08),linen,Fabric)
 round(model,"HatBand",2.05,.3,V(0,4.92,0),team,Fabric)
 block(model,"HatBand",V(.3,1,.14),V(0,4.4,1),team,Fabric).CFrame*=CFrame.Angles(.3,0,0)
 sword(model,.3)
 roundShield(model,team,1.6)
 for _,p in ipairs(model:GetChildren()) do
  if p:IsA("BasePart") then
   p.CFrame+=V(0,4.3,1)
   if p.Name=="BootL" or p.Name=="BootR" then
    p.Size=V(.7,1.7,.95)
    p.CFrame=CFrame.new((p.Name=="BootL" and -1 or 1)*1.45,5,.8)
   end
  end
 end
 camelBody(model,team)
end
-- Hand cannoneer: broad felt hat, padded doublet, powder horn and a levelled iron hand gun.
function B.handCannoneer(model,kind,team,stage)
 local doublet=Color3.fromRGB(132,58,46)
 figure(model,{cloth=doublet,skirt=Color3.fromRGB(96,44,38),sleeve=linen,glove=leather,boot=leather})
 block(model,"Tabard",V(1.3,1.9,1.6),V(0,2.6,0),team,Fabric)
 ball(model,"Hat",1.85,V(0,4.62,.1),hair)
 round(model,"Hat",3,.16,V(0,5.12,0),dark,Fabric)
 round(model,"Hat",1.6,.75,V(0,5.5,0),dark,Fabric)
 round(model,"HatBand",1.68,.24,V(0,5.24,0),team,Fabric)
 local gun={block(model,"Gun",V(.32,.32,2.2),grip+V(0,.3,.6),cutWood,Enum.Material.Wood),
  block(model,"Gun",V(.36,.36,3),grip+V(0,.45,-1.6),iron,Metal),
  block(model,"Gun",V(.48,.48,.3),grip+V(0,.45,-3.05),iron,Metal)}
 turn(gun,grip,CFrame.Angles(.1,0,0))
 segment(model,"Quiver",V(-.9,2.6,.6),V(-.6,2.1,1.1),.42,.42,straw)
 block(model,"Belt",V(.5,1.8,1.5),V(.35,2.9,0),leather,Fabric).CFrame*=CFrame.Angles(0,0,.5)
end
-- Trade cart: a horse in harness pulling a two-wheeled cart with a canvas hood in the player color.
-- Horse parts keep their names so the client gait animates the legs; Chassis / Wheel follow the siege groups.
function B.tradeCart(model,kind,team,stage)
 horse(model,team,false)
 for _,p in ipairs(model:GetChildren()) do
  if p:IsA("BasePart") then p.CFrame+=V(0,0,-3.2) end
 end
 block(model,"Chassis",V(4.4,.5,5),V(0,2.85,3.2),cutWood,Planks)
 for _,x in ipairs({-2.05,2.05}) do
  block(model,"Chassis",V(.3,1,5),V(x,3.5,3.2),timber,Planks)
  beam(model,"Chassis",V(x*.55,2.9,.8),V(x*.42,3.6,-3.6),.25,timber)
  plate(model,"Wheel",3.4,.45,V(x*1.2,1.7,3.6),timber,Planks)
  plate(model,"Wheel",1.1,.6,V(x*1.2,1.7,3.6),iron,Metal)
 end
 block(model,"Chassis",V(4.4,.3,.3),V(0,1.7,3.6),iron,Metal)
 -- Arched canvas hood: three bent hoops under a player-colored cover.
 for _,z in ipairs({1.4,3.2,5}) do
  for _,side in ipairs({-1,1}) do beam(model,"Chassis",V(side*2.05,4,z),V(side*1.3,5.9,z),.18,timber) end
  block(model,"Chassis",V(2.7,.18,.18),V(0,6.05,z),timber)
 end
 for _,side in ipairs({-1,1}) do
  block(model,"CanvasSail",V(.14,2,4.1),V(side*1.75,5,3.2),team,Fabric).CFrame*=CFrame.Angles(0,0,side*.35)
 end
 block(model,"CanvasSail",V(2.8,.14,4.1),V(0,6.2,3.2),team,Fabric)
end
-- Wheels are cylinders on the X axis so the client can spin them about their own center.
local function wheels(model,x,z,d)
 for _,wz in ipairs({-z,z}) do
  block(model,"Chassis",V(x*2,.4,.4),V(0,d/2,wz),iron,Metal)
  for _,wx in ipairs({-x,x}) do
   plate(model,"Wheel",d,.55,V(wx,d/2,wz),timber,Planks)
   plate(model,"Wheel",d*.36,.78,V(wx,d/2,wz),iron,Metal)
  end
 end
end
function B.ram(model,kind,team,stage)
 wheels(model,3.2,2.9,3)
 block(model,"Chassis",V(5.4,.6,8.4),V(0,2.3,0),cutWood,Planks)
 for _,x in ipairs({-2.5,2.5}) do for _,z in ipairs({-3.2,3.2}) do
  block(model,"Chassis",V(.55,2.7,.55),V(x,3.9,z),timber)
 end end
 disc(model,"RamLog",1.7,8.6,V(0,3.7,-1),cutWood,Enum.Material.Wood)
 for _,z in ipairs({-3.4,1.6}) do disc(model,"RamLog",1.9,.4,V(0,3.7,z),iron,Metal) end
 disc(model,"RamHead",2.05,1.2,V(0,3.7,-5.7),iron,Metal)
 ball(model,"RamHead",1.4,V(0,3.7,-6.2),iron,Metal)
 -- Hide-covered shed with the ridge along the log; ridge and draped bands carry the player color.
 local run,rise=3.3,2.2
 local angle,slope=math.atan(rise/run),math.sqrt(run*run+rise*rise)
 for _,side in ipairs({-1,1}) do
  local p=tint(block(model,"Roof",V(slope+.3,.36,8.4),V(side*run/2,5.2+rise/2,0),hide,Fabric),false)
  p.CFrame*=CFrame.Angles(0,0,-side*angle)
  block(model,"SiegeBanner",V(slope+.34,.14,2.2),V(0,0,0),team,Fabric).CFrame=p.CFrame*CFrame.new(0,.22,0)
  block(model,"Chassis",V(.45,.45,8.6),V(side*(run+.05),5.1,0),timber)
 end
 block(model,"Ridge",V(.9,.5,8.7),V(0,5.3+rise,0),team,Fabric)
end
function B.mangonel(model,kind,team,stage)
 wheels(model,3.15,2.7,2.6)
 block(model,"Chassis",V(5.4,.6,8.2),V(0,2,0),cutWood,Planks)
 for _,x in ipairs({-2.45,2.45}) do block(model,"Chassis",V(.55,.5,8.4),V(x,2.4,0),timber) end
 -- The axle matches the client swing pivot; the cocked arm lies back and flings up and forward.
 local axle=V(0,5,0)
 for _,x in ipairs({-1.9,1.9}) do for _,z in ipairs({-2.7,2.7}) do
  beam(model,"CatapultPost",V(x,2.4,z),axle+V(x,.25,0),.62,timber)
 end end
 plate(model,"Chassis",.7,4.8,axle,iron,Metal)
 local cup=V(0,3.7,4.3)
 local dir=(cup-axle).Unit
 segment(model,"CatapultArm",axle-dir*2.2,cup,.7,.7,cutWood,Enum.Material.Wood)
 segment(model,"CatapultArm",axle-dir*2.4,axle+dir*.7,1.05,1.05,timber)
 round(model,"StoneBasket",2.5,.7,cup+V(0,.2,.1),timber,Planks)
 ball(model,"StoneBasket",1.6,cup+V(0,1,.1),stone,Enum.Material.Slate)
 plate(model,"Chassis",.8,3.4,V(0,2.9,2.4),cutWood,Enum.Material.Wood)
 -- Slanted front mantlet: the big player-colored face of the machine.
 block(model,"SiegeBanner",V(5.2,.22,2.6),V(0,3.2,-3.6),team,Planks).CFrame*=CFrame.Angles(-.6,0,0)
 for _,x in ipairs({-2.8,2.8}) do block(model,"SiegeBanner",V(.14,1.5,2.6),V(x,3.4,.2),team,Fabric) end
end
function B.trebuchet(model,kind,team,stage)
 wheels(model,3.15,3.3,2.6)
 for _,x in ipairs({-2.5,2.5}) do block(model,"Chassis",V(.8,.8,9.6),V(x,1.9,0),cutWood,Enum.Material.Wood) end
 for _,z in ipairs({-4.3,4.3}) do block(model,"Chassis",V(5.8,.6,.8),V(0,2,z),timber) end
 -- The axle matches the client swing pivot, so arm, counterweight and sling stay joined.
 local axle=V(0,9,0)
 for _,side in ipairs({-1,1}) do
  for _,z in ipairs({-3.4,3.4}) do beam(model,"TrebuchetFrame",V(side*2.5,2.2,z),axle+V(side*1.75,.2,0),.7,timber) end
  block(model,"SiegeBanner",V(.14,2.6,2.4),V(side*2.4,5,0),team,Fabric).CFrame*=CFrame.Angles(0,0,side*.115)
 end
 plate(model,"Chassis",.7,4.3,axle,iron,Metal)
 local dir=V(0,math.cos(.5),-math.sin(.5))
 local tip,heel=axle+dir*9,axle-dir*3
 segment(model,"TrebuchetArm",heel,tip,.7,.7,cutWood,Enum.Material.Wood)
 for _,x in ipairs({-.8,.8}) do block(model,"Counterweight",V(.24,1.5,.24),heel+V(x,-.6,0),iron,Metal) end
 block(model,"Counterweight",V(2.7,2.2,2.5),heel+V(0,-2.4,0),cutWood,Planks)
 tint(block(model,"Counterweight",V(2.9,.4,2.7),heel+V(0,-1.25,0),team,Fabric),true)
 beam(model,"TrebuchetArm",tip,tip+V(0,-3.2,-.4),.14,straw)
 block(model,"Sling",V(1.4,.5,1.4),tip+V(0,-3.5,-.45),team,Fabric)
 ball(model,"TrebuchetArm",1.1,tip+V(0,-3.1,-.45),stone,Enum.Material.Slate)
end
return {builders=B,tool=villagerTool,carry=carryLoad,toolKinds=toolKinds,carryKinds=carryKinds}
