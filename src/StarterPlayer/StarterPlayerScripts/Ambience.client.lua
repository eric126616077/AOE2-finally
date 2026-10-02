-- Client-only idle life: swaying canopies and bushes, meadow grass, flags, mill sails, chimney
-- smoke and passing birds. Nothing here is gameplay: every part it creates ignores queries and
-- collisions, and server-owned appearance parts return to their authored frame when released.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local Rules=require(RS:WaitForChild("Shared"):WaitForChild("AmbienceRules"))
local Config=require(RS:WaitForChild("GameData"):WaitForChild("GameConfig"))
local player=Players.LocalPlayer
if script:GetAttribute("Initialized")==true then return end
script:SetAttribute("Initialized",true)
local resources=workspace:WaitForChild("Resources")
local buildings=workspace:WaitForChild("Buildings")
local folder=Instance.new("Folder")
folder.Name="RTSAmbience"
folder.Parent=workspace
local wind=Vector3.new(Rules.WindX,0,Rules.WindZ)
-- Turning about this axis by a positive angle tips the top of a model downwind.
local windAxis=Vector3.new(Rules.WindZ,0,-Rules.WindX)
local moveParts,moveFrames={},{}
local connections={}
local viewport=Vector2.new(1,1)
local function cellKey(x,z) return x*4096+z end
local function visible(camera,x,y,z)
 local point=camera:WorldToViewportPoint(Vector3.new(x,y,z))
 local margin=Rules.ScreenMargin
 return point.Z>0 and point.X>=-margin and point.Y>=-margin and point.X<=viewport.X+margin and point.Y<=viewport.Y+margin
end
local function cosmetic(class,name,size,color,material)
 local part=Instance.new(class)
 part.Name,part.Size,part.Color=name,size,color
 part.Material=material or Enum.Material.SmoothPlastic
 part.Anchored,part.CanCollide,part.CanQuery,part.CanTouch=true,false,false,false
 part.CastShadow=false
 part.TopSurface,part.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
 return part
end

-- Actors own a few parts and their authored frames. Trees and grass share the slow ring, which
-- rewrites a bounded number of parts per frame; flags and sails are few and move every frame.
local ring,cursor={},1
local fast={}
local function ringAdd(actor)
 table.insert(ring,actor)
 actor.index=#ring
end
local function ringRemove(actor)
 local index=actor.index
 if not index then return end
 local last=ring[#ring]
 ring[index]=last
 last.index=index
 ring[#ring]=nil
 actor.index=nil
end
local function rest(actor)
 if actor.owner and not actor.owner.Parent then return end
 for index,part in ipairs(actor.parts) do
  if part.Parent then
   table.insert(moveParts,part)
   table.insert(moveFrames,actor.bases[index])
  end
 end
end
local function writeCrown(actor,t)
 local bases,weights=actor.bases,actor.weights
 for index,part in ipairs(actor.parts) do
  if part.Parent then
   -- Each crown trails the one below it, so the canopy rolls instead of sliding as one lump.
   table.insert(moveParts,part)
   table.insert(moveFrames,bases[index]+wind*(weights[index]*(Rules.Lean+Rules.Gust(actor.x,actor.z,t-index*.35))))
  end
 end
end
local function writeTurn(actor,turn)
 local bases=actor.bases
 for index,part in ipairs(actor.parts) do
  if part.Parent then
   table.insert(moveParts,part)
   table.insert(moveFrames,turn*bases[index])
  end
 end
end
local function writeRock(actor,t)
 local angle=actor.angle*(Rules.Lean+Rules.Gust(actor.x,actor.z,t))+actor.flutter*math.sin(t*6.1+actor.phase)
 writeTurn(actor,actor.pivot*CFrame.fromAxisAngle(windAxis,angle)*actor.pivotInverse)
end
local function writeSail(actor,t)
 writeTurn(actor,actor.pivot*CFrame.fromAxisAngle(actor.axis,(t*Rules.SailSpeed+actor.phase)%(math.pi*2))*actor.pivotInverse)
end
local function writeFlag(actor,t)
 local part=actor.parts[1]
 if not part.Parent then return end
 local angle=.32*math.sin(t*4.6+actor.phase)+.12*math.sin(t*7.9+actor.phase*2)
 table.insert(moveParts,part)
 table.insert(moveFrames,actor.bases[1]*actor.hinge*CFrame.Angles(0,angle,0)*actor.hingeInverse)
end
local function writeHang(actor,t)
 local part=actor.parts[1]
 if not part.Parent then return end
 -- Hanging cloth swings in its own plane, so it never dips into the wall behind it.
 local angle=.12*math.sin(t*1.9+actor.phase)+.06*Rules.Gust(actor.x,actor.z,t)
 table.insert(moveParts,part)
 table.insert(moveFrames,actor.bases[1]*actor.hinge*CFrame.Angles(0,0,angle)*actor.hingeInverse)
end

-- Resources never move: index them once by ground cell, without per-model connections.
local swayKinds={Tree=true,Berries=true}
local resourceCells,resourceRecords,pendingResources={}, {}, {}
local activeTrees={}
local function indexResource(model)
 if not model:IsA("Model") or resourceRecords[model] then return end
 local root=model.PrimaryPart
 if not root then pendingResources[model]=true; return end
 pendingResources[model]=nil
 local position=root.Position
 local record={model=model,x=position.X,z=position.Z,kind=model.Name,sway=swayKinds[model.Name]==true,
  key=cellKey(math.floor(position.X/Rules.ResourceCell),math.floor(position.Z/Rules.ResourceCell))}
 resourceRecords[model]=record
 local list=resourceCells[record.key]
 if not list then list={}; resourceCells[record.key]=list end
 table.insert(list,record)
end
local function unindexResource(model)
 pendingResources[model]=nil
 local record=resourceRecords[model]
 if not record then return end
 resourceRecords[model]=nil
 activeTrees[record]=nil
 if record.actor then ringRemove(record.actor); record.actor=nil end
 local list=resourceCells[record.key]
 local index=table.find(list,record)
 if index then
  list[index]=list[#list]
  list[#list]=nil
 end
 if #list==0 then resourceCells[record.key]=nil end
end
local function treeActor(record)
 local model=record.model
 local root=model.PrimaryPart
 if not root then return nil end
 local actor={owner=model,x=record.x,z=record.z,parts={},bases={},stage=model:GetAttribute("ResourceStage")}
 if record.kind=="Tree" and model:GetAttribute("OriginalArt")==true then
  -- Fallback trees keep the trunk planted; smaller crowns travel further than the main one.
  actor.write,actor.weights=writeCrown,{}
  for _,part in ipairs(model:GetChildren()) do
   if part.Name=="Crown" and part:IsA("BasePart") then
    table.insert(actor.parts,part)
    table.insert(actor.bases,part.CFrame)
    table.insert(actor.weights,Rules.CrownSway*math.clamp(9/math.max(part.Size.X,1),.7,1.5))
   end
  end
 else
  -- Imported trees and berry bushes have unknown parts: rock the whole look about its base.
  local ground=root.Position-Vector3.new(0,root.Size.Y/2,0)
  actor.write,actor.pivot,actor.pivotInverse=writeRock,CFrame.new(ground),CFrame.new(-ground)
  actor.angle=record.kind=="Tree" and Rules.RockAngle or Rules.BushAngle
  actor.flutter,actor.phase=0,0
  for _,part in ipairs(model:GetDescendants()) do
   if part:IsA("BasePart") and part~=root and part.Transparency<1 then
    table.insert(actor.parts,part)
    table.insert(actor.bases,part.CFrame)
   end
  end
 end
 return #actor.parts>0 and actor or nil
end
local function releaseTree(record)
 activeTrees[record]=nil
 local actor=record.actor
 if not actor then return end
 rest(actor)
 ringRemove(actor)
 record.actor=nil
end
-- Cell offsets nearest first, so the tree budget is spent around the camera focus.
local cellOffsets={}
do
 local span=math.ceil(Rules.MaxViewRadius/Rules.ResourceCell)+1
 for x=-span,span do
  for z=-span,span do table.insert(cellOffsets,{x=x,z=z,distance=math.sqrt(x*x+z*z)}) end
 end
 table.sort(cellOffsets,function(a,b) return a.distance<b.distance end)
end
local function treePass(camera,focus,radius,stamp)
 local cell=Rules.ResourceCell
 local span=radius/cell+1
 local cx,cz=math.floor(focus.X/cell),math.floor(focus.Z/cell)
 local count=0
 for _,offset in ipairs(cellOffsets) do
  if offset.distance>span or count>=Rules.MaxTrees then break end
  local list=resourceCells[cellKey(cx+offset.x,cz+offset.z)]
  if list then
   for _,record in ipairs(list) do
    if count>=Rules.MaxTrees then break end
    if record.sway and visible(camera,record.x,6,record.z) then
     count+=1
     record.stamp=stamp
     local actor=record.actor
     -- A depletion stage swaps the server parts: drop the stale frames without writing them.
     if actor and (actor.stage~=record.model:GetAttribute("ResourceStage") or actor.parts[1].Parent==nil) then
      ringRemove(actor)
      record.actor,actor=nil,nil
     end
     if not actor then
      actor=treeActor(record)
      if actor then
       record.actor=actor
       activeTrees[record]=true
       ringAdd(actor)
      end
     end
    end
   end
  end
 end
 for record in pairs(activeTrees) do
  if record.stamp~=stamp then releaseTree(record) end
 end
end

-- Meadow grass. Tufts exist only around the camera, come from a pool, and stay off roads,
-- courtyards, building footprints and resource nodes.
local grass={tufts={},count=0,cache={},blocked={},blades={},flowers={}}
local grassFolder=Instance.new("Folder")
grassFolder.Name="Grass"
grassFolder.Parent=folder
-- Tones stay close to the ground colour so the meadow reads as texture, not as objects.
local grassDark,grassLight,grassDry=Color3.fromRGB(88,138,64),Color3.fromRGB(118,162,80),Color3.fromRGB(140,160,86)
local petals={Color3.fromRGB(226,224,206),Color3.fromRGB(218,196,112),Color3.fromRGB(196,122,112),Color3.fromRGB(160,142,192)}
local function tuftAt(cx,cz)
 local key=cellKey(cx,cz)
 local tuft=grass.cache[key]
 if tuft==nil then
  tuft=Rules.Tuft(cx,cz) or false
  grass.cache[key]=tuft
 end
 return tuft or nil,key
end
local function releaseTuft(key)
 local actor=grass.tufts[key]
 if not actor then return end
 grass.tufts[key]=nil
 grass.count-=1
 ringRemove(actor)
 for _,part in ipairs(actor.parts) do
  part.Parent=nil
  table.insert(part.Name=="Flower" and grass.flowers or grass.blades,part)
 end
end
local function growTuft(key,tuft)
 local pivot=CFrame.new(tuft.x,Config.Map.GroundY,tuft.z)
 local base=pivot*CFrame.Angles(0,tuft.yaw,0)
 local color=tuft.tone<.75 and grassDark:Lerp(grassLight,tuft.tone/.75) or grassLight:Lerp(grassDry,(tuft.tone-.75)*3)
 local actor={x=tuft.x,z=tuft.z,parts={},bases={},write=writeRock,angle=Rules.TuftAngle,flutter=.06,
  phase=tuft.tone*math.pi*2,pivot=pivot,pivotInverse=pivot:Inverse()}
 for index=1,2 do
  local part=table.remove(grass.blades) or cosmetic("WedgePart","GrassBlade",Vector3.one,color)
  local height=tuft.height*(index==1 and 1 or .7)
  part.Size=Vector3.new(.3,height,tuft.width*(index==1 and 1 or .8))
  part.Color=index==1 and color or color:Lerp(grassDark,.4)
  local frame=base*CFrame.Angles(0,(index-1)*tuft.spread,0)*CFrame.new(0,height/2,0)
  part.CFrame=frame
  part.Parent=grassFolder
  table.insert(actor.parts,part)
  table.insert(actor.bases,frame)
 end
 if tuft.flower>0 then
  local part=table.remove(grass.flowers) or cosmetic("Part","Flower",Vector3.new(.5,.5,.5),petals[1])
  part.Shape=Enum.PartType.Ball
  part.Color=petals[tuft.flower] or petals[1]
  local frame=base*CFrame.new(0,tuft.height*.8,tuft.width*.2)
  part.CFrame=frame
  part.Parent=grassFolder
  table.insert(actor.parts,part)
  table.insert(actor.bases,frame)
 end
 grass.tufts[key]=actor
 grass.count+=1
 ringAdd(actor)
end
local function resourceNear(x,z)
 local cell=Rules.ResourceCell
 for cx=math.floor((x-7)/cell),math.floor((x+7)/cell) do
  for cz=math.floor((z-7)/cell),math.floor((z+7)/cell) do
   local list=resourceCells[cellKey(cx,cz)]
   if list then
    for _,record in ipairs(list) do
     local dx,dz=record.x-x,record.z-z
     local reach=record.kind=="Tree" and 3.5 or 6.5
     if dx*dx+dz*dz<reach*reach then return record.model end
    end
   end
  end
 end
 return nil
end
local function grassPass(camera,focus,radius,height,stamp)
 local cell=Rules.GrassCell
 local density=Rules.Density(height)
 local mapSize=workspace:GetAttribute("MapSize") or workspace:GetAttribute("MatchSize") or Config.Map.MapSize
 -- The tuft budget is met by lowering the rank threshold, which thins the whole view evenly;
 -- filling it in scan order would leave one side of the screen bare.
 local limit=math.min(density,grass.limit or density)
 local made,wanted=0,0
 for cx=math.floor((focus.X-radius)/cell),math.floor((focus.X+radius)/cell) do
  for cz=math.floor((focus.Z-radius)/cell),math.floor((focus.Z+radius)/cell) do
   local tuft,key=tuftAt(cx,cz)
   if tuft and tuft.rank<limit and not grass.blocked[key] and visible(camera,tuft.x,0,tuft.z) then
    if tuft.mapSize~=mapSize then
     tuft.mapSize=mapSize
     tuft.bare=Rules.Bare(tuft.x,tuft.z,mapSize,Config.Map.RoadWidth)
    end
    if not tuft.bare then
     wanted+=1
     local live=grass.tufts[key]
     if live then
      live.stamp=stamp
     elseif made<Rules.MaxNewTufts and grass.count<Rules.MaxTufts and not (tuft.near and tuft.near.Parent) then
      tuft.near=resourceNear(tuft.x,tuft.z)
      if not tuft.near then
       growTuft(key,tuft)
       grass.tufts[key].stamp=stamp
       made+=1
      end
     end
    end
   end
  end
 end
 if wanted>Rules.MaxTufts then
  grass.limit=limit*Rules.MaxTufts/wanted*.95
 elseif wanted<Rules.MaxTufts*.8 then
  grass.limit=math.min(density,limit*1.15)
 end
 for key,actor in pairs(grass.tufts) do
  if actor.stamp~=stamp then releaseTuft(key) end
 end
end

-- Buildings: far fewer than resources, so each keeps a record. Its footprint clears the grass,
-- and once complete and on screen its flags, sails and chimneys come alive.
local buildingRecords={}
local smokeCount=0
local sailNames={SailSpar=true,CanvasSail=true,SailBatten=true,SailHub=true}
local clothNames={Banner=true,Flag=true}
local function blockGrass(record)
 local root=record.model.PrimaryPart
 if not root then return end
 local frame,size=root.CFrame,root.Size
 local halfX=(math.abs(frame.RightVector.X)*size.X+math.abs(frame.LookVector.X)*size.Z)/2+1.5
 local halfZ=(math.abs(frame.RightVector.Z)*size.X+math.abs(frame.LookVector.Z)*size.Z)/2+1.5
 local x,z=frame.Position.X,frame.Position.Z
 local cell=Rules.GrassCell
 record.keys={}
 for cx=math.floor((x-halfX)/cell),math.floor((x+halfX)/cell) do
  for cz=math.floor((z-halfZ)/cell),math.floor((z+halfZ)/cell) do
   local tuft,key=tuftAt(cx,cz)
   if tuft and math.abs(tuft.x-x)<=halfX and math.abs(tuft.z-z)<=halfZ then
    grass.blocked[key]=(grass.blocked[key] or 0)+1
    table.insert(record.keys,key)
    releaseTuft(key)
   end
  end
 end
end
local function smokeAt(opening)
 local width=math.max(opening.Size.X,opening.Size.Z)
 local holder=cosmetic("Part","ChimneySmoke",Vector3.new(.2,.2,.2),Color3.new(1,1,1))
 holder.Transparency=1
 holder.CFrame=CFrame.new(opening.Position)
 local emitter=Instance.new("ParticleEmitter")
 emitter.Texture="rbxasset://textures/particles/smoke_main.dds"
 emitter.Color=ColorSequence.new(Color3.fromRGB(226,222,212),Color3.fromRGB(176,174,170))
 emitter.Size=NumberSequence.new(width*.7,width*2.4)
 emitter.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.55),NumberSequenceKeypoint.new(.6,.78),NumberSequenceKeypoint.new(1,1)})
 emitter.Lifetime=NumberRange.new(3,4.5)
 emitter.Rate=2.5
 emitter.Speed=NumberRange.new(2.4,3.4)
 emitter.SpreadAngle=Vector2.new(10,10)
 emitter.EmissionDirection=Enum.NormalId.Top
 emitter.Acceleration=wind*2.2
 emitter.Rotation=NumberRange.new(0,360)
 emitter.RotSpeed=NumberRange.new(-20,20)
 emitter.LightEmission,emitter.LightInfluence=0,1
 emitter.Parent=holder
 holder.Parent=folder
 return holder
end
local function activateBuilding(record)
 local model=record.model
 local poles,cloth,sails,axle,chimneys={}, {}, {}, nil, {}
 for _,part in ipairs(model:GetDescendants()) do
  if part:IsA("BasePart") and part.Transparency<1 then
   local name=part.Name
   if name=="Flagpole" then table.insert(poles,part)
   elseif clothNames[name] then table.insert(cloth,part)
   elseif name=="SailAxle" then axle=part
   elseif sailNames[name] then table.insert(sails,part)
   elseif name=="ChimneyOpening" then table.insert(chimneys,part) end
  end
 end
 local actors={}
 for _,part in ipairs(cloth) do
  local size,frame=part.Size,part.CFrame
  local actor={owner=model,x=frame.Position.X,z=frame.Position.Z,parts={part},bases={frame},
   phase=(frame.Position.X*.37+frame.Position.Z*.61)%(math.pi*2)}
  if size.X>size.Y then
   -- A flag flies from whichever edge touches its pole.
   for _,pole in ipairs(poles) do
    local point=frame:PointToObjectSpace(pole.Position)
    if math.abs(point.X)<size.X and math.abs(point.Z)<size.X*.5 then
     actor.hinge=CFrame.new((point.X<0 and -1 or 1)*size.X/2,0,0)
     actor.write=writeFlag
     break
    end
   end
  end
  if not actor.hinge then actor.hinge,actor.write=CFrame.new(0,size.Y/2,0),writeHang end
  actor.hingeInverse=actor.hinge:Inverse()
  table.insert(actors,actor)
 end
 if axle and #sails>0 then
  local pivot=CFrame.new(axle.Position)
  local actor={owner=model,parts=sails,bases={},write=writeSail,pivot=pivot,pivotInverse=pivot:Inverse(),
   axis=axle.CFrame.RightVector,phase=0}
  for index,part in ipairs(sails) do actor.bases[index]=part.CFrame end
  table.insert(actors,actor)
 end
 local smoke={}
 for _,opening in ipairs(chimneys) do
  if smokeCount>=Rules.MaxSmoke then break end
  smokeCount+=1
  table.insert(smoke,smokeAt(opening))
 end
 if #actors==0 and #smoke==0 then
  -- Nothing to animate here; a chimney that only missed the smoke budget is retried later.
  if #chimneys==0 then record.plain=true end
  return false
 end
 for _,actor in ipairs(actors) do fast[actor]=true end
 record.actors,record.smoke=actors,smoke
 return true
end
local function deactivateBuilding(record)
 if not record.actors then return end
 for _,actor in ipairs(record.actors) do
  fast[actor]=nil
  rest(actor)
 end
 for _,holder in ipairs(record.smoke) do
  holder:Destroy()
  smokeCount-=1
 end
 record.actors,record.smoke=nil,nil
end
local function buildingPass(camera)
 local count=0
 for model,record in pairs(buildingRecords) do
  local root=model.PrimaryPart
  local complete=model:GetAttribute("Complete")~=false and model:GetAttribute("UnderConstruction")~=true
  -- Construction reveals parts in stages: a rebuilt or re-opened site is scanned again.
  if not complete then record.plain=nil end
  local show=complete and not record.plain and root~=nil and count<Rules.MaxBuildings
   and visible(camera,root.Position.X,root.Position.Y,root.Position.Z)
  if show and record.actors then
   for _,actor in ipairs(record.actors) do
    if actor.parts[1].Parent==nil then deactivateBuilding(record); break end
   end
  end
  if show then
   if record.actors or activateBuilding(record) then count+=1 end
  else deactivateBuilding(record) end
 end
end
local function trackBuilding(model)
 if not model:IsA("Model") or buildingRecords[model] then return end
 buildingRecords[model]={model=model}
end
local function untrackBuilding(model)
 local record=buildingRecords[model]
 if not record then return end
 buildingRecords[model]=nil
 deactivateBuilding(record)
 for _,key in ipairs(record.keys or {}) do
  local remaining=(grass.blocked[key] or 1)-1
  grass.blocked[key]=remaining>0 and remaining or nil
 end
end

-- Small flocks cross the view now and then, well below the camera and above every roof.
local flocks={}
local nextFlock=os.clock()+Rules.FlockGapMin
local function spawnFlock(focus,radius,height,now)
 local heading=math.random()*math.pi*2
 local direction=Vector3.new(math.cos(heading),0,math.sin(heading))
 local side=Vector3.new(-direction.Z,0,direction.X)
 local origin=Vector3.new(focus.X,math.clamp(height*.3,14,48),focus.Z)-direction*radius*1.15+side*((math.random()-.5)*radius*.8)
 local color=math.random()<.5 and Color3.fromRGB(54,50,48) or Color3.fromRGB(232,230,222)
 local model=Instance.new("Model")
 model.Name="Birds"
 local flock={model=model,origin=origin,direction=direction,side=side,born=now,span=radius*2.5,birds={},phase=math.random()*6}
 for index=1,math.random(Rules.FlockMin,Rules.FlockMax) do
  -- A loose V behind the leader.
  local row=math.ceil((index-1)/2)
  local bird={phase=math.random()*math.pi*2,
   offset=-direction*(row*3.2)+side*((index%2==0 and 1 or -1)*row*2.6)+Vector3.new(0,(math.random()-.5)*1.2,0),
   body=cosmetic("Part","Body",Vector3.new(.45,.35,1.5),color),
   left=cosmetic("Part","Wing",Vector3.new(1.7,.1,.8),color),
   right=cosmetic("Part","Wing",Vector3.new(1.7,.1,.8),color)}
  bird.body.Parent,bird.left.Parent,bird.right.Parent=model,model,model
  table.insert(flock.birds,bird)
 end
 model.Parent=folder
 table.insert(flocks,flock)
end
local function writeFlocks(now)
 for index=#flocks,1,-1 do
  local flock=flocks[index]
  local age=now-flock.born
  local travelled=age*Rules.FlockSpeed
  if travelled>flock.span or age>Rules.FlockSeconds then
   flock.model:Destroy()
   table.remove(flocks,index)
  else
   local center=flock.origin+flock.direction*travelled+flock.side*(math.sin(age*.3+flock.phase)*5)
   for _,bird in ipairs(flock.birds) do
    local position=center+bird.offset+Vector3.new(0,math.sin(age*2+bird.phase)*.3,0)
    local frame=CFrame.lookAt(position,position+flock.direction)
    local flap=math.sin(age*9+bird.phase)*.6
    table.insert(moveParts,bird.body); table.insert(moveFrames,frame)
    table.insert(moveParts,bird.left); table.insert(moveFrames,frame*CFrame.new(-.2,0,0)*CFrame.Angles(0,0,-flap)*CFrame.new(-.85,0,0))
    table.insert(moveParts,bird.right); table.insert(moveFrames,frame*CFrame.new(.2,0,0)*CFrame.Angles(0,0,flap)*CFrame.new(.85,0,0))
   end
  end
 end
end

local function clearMoving()
 for record in pairs(activeTrees) do releaseTree(record) end
 for _,record in pairs(buildingRecords) do deactivateBuilding(record) end
 for _,flock in ipairs(flocks) do flock.model:Destroy() end
 table.clear(flocks)
end
local function clearGrass()
 for key in pairs(grass.tufts) do releaseTuft(key) end
end
local function focusPoint(camera)
 local phase=workspace:GetAttribute("MatchPhase")
 if player:GetAttribute("InLobby")==true or (phase~="Playing" and phase~="Ended") then return nil end
 local frame=camera.CFrame
 if frame.LookVector.Y>=-.05 then return nil end
 return frame.Position+frame.LookVector*((Config.Map.GroundY-frame.Position.Y)/frame.LookVector.Y)
end
local stamp=0
local still=true
local function pass(now)
 local camera=workspace.CurrentCamera
 local focus=camera and focusPoint(camera)
 if not focus then clearMoving(); clearGrass(); return end
 for model in pairs(pendingResources) do
  if model.Parent==resources then indexResource(model) else pendingResources[model]=nil end
 end
 for _,record in pairs(buildingRecords) do
  if not record.keys then blockGrass(record) end
 end
 stamp+=1
 viewport=camera.ViewportSize
 local height=camera.CFrame.Position.Y
 local radius=Rules.ViewRadius(height)
 local reduced=player:GetAttribute("ReducedMotion")==true
 if reduced then
  -- Reduced motion keeps the meadow as still scenery and drops everything that moves.
  if not still then
   clearMoving()
   for _,actor in pairs(grass.tufts) do rest(actor) end
  end
 else
  treePass(camera,focus,radius,stamp)
  buildingPass(camera)
  if now>=nextFlock then
   nextFlock=now+Rules.FlockGapMin+math.random()*(Rules.FlockGapMax-Rules.FlockGapMin)
   if #flocks<Rules.MaxFlocks then spawnFlock(focus,radius,height,now) end
  end
 end
 still=reduced
 grassPass(camera,focus,radius,height,stamp)
end

for _,model in ipairs(resources:GetChildren()) do indexResource(model) end
for _,model in ipairs(buildings:GetChildren()) do trackBuilding(model) end
table.insert(connections,resources.ChildAdded:Connect(indexResource))
table.insert(connections,resources.ChildRemoved:Connect(unindexResource))
table.insert(connections,buildings.ChildAdded:Connect(trackBuilding))
table.insert(connections,buildings.ChildRemoved:Connect(untrackBuilding))
local elapsed,clock=Rules.UpdateInterval,0
local diagnostics={writes=0}
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
 local now=os.clock()
 clock+=math.min(dt,.1)
 elapsed+=dt
 if elapsed>=Rules.UpdateInterval then
  elapsed=0
  pass(now)
 end
 if not still then
  -- Round robin: every tree and tuft is rewritten every few frames, never all in one frame.
  local total=#ring
  local visited=0
  while visited<total and #moveParts<Rules.WriteBudget do
   if cursor>total then cursor=1 end
   local actor=ring[cursor]
   actor.write(actor,clock)
   cursor+=1
   visited+=1
  end
  for actor in pairs(fast) do actor.write(actor,clock) end
  writeFlocks(now)
 end
 diagnostics.writes=#moveParts
 -- One engine batch of appearance parts only; footprints and unit Roots are never in it.
 if #moveParts>0 then workspace:BulkMoveTo(moveParts,moveFrames,Enum.BulkMoveMode.FireCFrameChanged) end
 table.clear(moveParts); table.clear(moveFrames)
end))
local probe
if RunService:IsStudio() then
 probe=Instance.new("BindableFunction")
 probe.Name="RTSAmbienceProbe"
 probe.OnInvoke=function()
  local trees,sites,moving=0,0,0
  for _ in pairs(activeTrees) do trees+=1 end
  for _,record in pairs(buildingRecords) do if record.actors then sites+=1 end end
  for _ in pairs(fast) do moving+=1 end
  return {trees=trees,tufts=grass.count,buildings=sites,fastActors=moving,smoke=smokeCount,flocks=#flocks,
   ring=#ring,writes=diagnostics.writes,still=still,writeBudget=Rules.WriteBudget,maxTrees=Rules.MaxTrees,maxTufts=Rules.MaxTufts}
 end
 probe.Parent=script.Parent
end
script.Destroying:Once(function()
 for _,connection in ipairs(connections) do connection:Disconnect() end
 clearMoving()
 -- Released server parts go back to their authored frames before this script disappears.
 if #moveParts>0 then workspace:BulkMoveTo(moveParts,moveFrames,Enum.BulkMoveMode.FireCFrameChanged) end
 if probe then probe:Destroy() end
 folder:Destroy()
end)
script:SetAttribute("RTSAmbienceReady",true)
