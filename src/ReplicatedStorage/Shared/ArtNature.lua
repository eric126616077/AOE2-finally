-- Fallback art: natural resources. stage 0 is full; later stages show depletion.
-- Later stages only remove or shrink pieces, so they always stay inside the stage-0 bounds
-- that ModelFactory used to fit the node.
local K=require(script.Parent.ArtKit)
local timber,cutWood,paleStone,dark=K.timber,K.cutWood,K.paleStone,K.dark
local leaf,leafDark,leafLight=K.leaf,K.leafDark,K.leafLight
local block,round,ball=K.block,K.round,K.ball
local B={}
B.Tree=function(model,kind,team,stage)
 -- Four parts per tree across thousands of forest nodes: trunk plus three uniform crowns.
 -- The main crown spans the full width so the fitted canopy still covers forest spacing.
 -- Felling thins the canopy, cuts a pale notch and finally leaves a log by a small remnant crown.
 round(model,"Trunk",2,8.5,Vector3.new(0,4.25,0),timber,Enum.Material.Wood)
 if stage<=0 then
  ball(model,"Crown",12,Vector3.new(0,10.2,0),leafDark,Enum.Material.Grass)
  ball(model,"Crown",7,Vector3.new(2.6,12.6,1.8),leaf,Enum.Material.Grass)
  ball(model,"Crown",6.4,Vector3.new(-2.4,13,-1.9),leafLight,Enum.Material.Grass)
 elseif stage==1 then
  ball(model,"Crown",9.2,Vector3.new(0,10.4,0),leafDark,Enum.Material.Grass)
  ball(model,"Crown",5.4,Vector3.new(2,12.6,1.3),leaf,Enum.Material.Grass)
  round(model,"Cut",2.3,.6,Vector3.new(0,1.3,0),cutWood,Enum.Material.Wood)
 else
  ball(model,"Crown",6.2,Vector3.new(0,10,0),leaf,Enum.Material.Grass)
  round(model,"Cut",2.3,.9,Vector3.new(0,1.4,0),cutWood,Enum.Material.Wood)
  local log=block(model,"Log",Vector3.new(5.4,1.5,1.5),Vector3.new(2.8,.75,1.9),cutWood,Enum.Material.Wood)
  log.Shape=Enum.PartType.Cylinder
  log.CFrame*=CFrame.Angles(0,.7,0)
 end
end
-- Rock piles: {class, size, position, rotation, shade}. Mining removes the leaning stones first,
-- then lowers what is left, so each stage reads shorter and smaller from above.
local keepRocks={[0]=math.huge,3,2}
local rockHeight={[0]=1,.82,.55}
local rockSpread={[0]=1,1,.72}
local function rocks(model,list,base,stage)
 local height,spread=rockHeight[stage],rockSpread[stage]
 for index,rock in ipairs(list) do
  if index>keepRocks[stage] then break end
  local shade=rock[5]>=0 and base:Lerp(paleStone,rock[5]) or base:Lerp(dark,-rock[5])
  local size,pos=rock[2],rock[3]
  local p=block(model,"Rock",Vector3.new(size.X*spread,size.Y*height,size.Z*spread),Vector3.new(pos.X*spread,pos.Y*height,pos.Z*spread),shade,Enum.Material.Slate,rock[1])
  p.CFrame*=CFrame.Angles(rock[4].X,rock[4].Y,rock[4].Z)
 end
 if stage>=2 then
  block(model,"Rock",Vector3.new(1.6,.7,1.5),Vector3.new(-2.6,.35,1.4),base:Lerp(paleStone,.2),Enum.Material.Slate).CFrame*=CFrame.Angles(0,.8,0)
 end
 return height,spread
end
B.Gold=function(model,kind,team,stage)
 -- Warm brown ore rock bristling with bright gold crystals: reads as gold even as a small dot.
 stage=math.min(stage,2)
 local height,spread=rocks(model,{
  {"Part",Vector3.new(5.4,3.8,5),Vector3.new(0,1.9,-.4),Vector3.new(.06,.4,-.05),0},
  {"Part",Vector3.new(4,2.7,3.6),Vector3.new(3,1.35,1.8),Vector3.new(-.08,-.5,.1),.14},
  {"WedgePart",Vector3.new(4,2.9,3.6),Vector3.new(-3,1.45,-1.2),Vector3.new(0,2.3,0),-.14},
  {"Part",Vector3.new(2.6,1.7,2.4),Vector3.new(-1.8,.85,2.7),Vector3.new(0,.9,0),.06},
 },Color3.fromRGB(142,120,96),stage)
 local bright,deep=Color3.fromRGB(246,200,70),Color3.fromRGB(214,160,44)
 local crystals={
  {Vector3.new(1.2,3,1.2),Vector3.new(.3,4.5,-.5),Vector3.new(.25,.6,.2)},
  {Vector3.new(1.1,2.6,1.1),Vector3.new(2.9,2.9,1.9),Vector3.new(-.2,.3,.3)},
  {Vector3.new(1,2.4,1),Vector3.new(-1.4,3.9,.7),Vector3.new(-.3,.2,-.35)},
  {Vector3.new(1,2.2,1),Vector3.new(1.7,3.8,.3),Vector3.new(.2,1,.4)},
  {Vector3.new(.95,2,.95),Vector3.new(-3.1,2.7,-1),Vector3.new(.3,.8,-.3)},
  {Vector3.new(1,.9,1),Vector3.new(-1.7,2,3),Vector3.new(.2,.5,.1)},
 }
 for index=1,({[0]=6,4,2})[stage] do
  local c=crystals[index]
  local p=block(model,"Ore",c[1]*(stage==2 and .8 or 1),Vector3.new(c[2].X*spread,c[2].Y*height,c[2].Z*spread),index%2==0 and deep or bright,Enum.Material.Metal)
  p.CFrame*=CFrame.Angles(c[3].X,c[3].Y,c[3].Z)
 end
end
B.Stone=function(model,kind,team,stage)
 -- Pale, cool grey slabs with one squared quarry block: clearly not gold from any distance.
 stage=math.min(stage,2)
 rocks(model,{
  {"Part",Vector3.new(5.6,4.2,5.2),Vector3.new(0,2.1,-.4),Vector3.new(.08,.5,-.06),.25},
  {"Part",Vector3.new(4.2,3,3.8),Vector3.new(2.9,1.5,2.1),Vector3.new(-.1,-.4,.14),.45},
  {"WedgePart",Vector3.new(4,3,3.6),Vector3.new(-3,1.5,-1.4),Vector3.new(0,2.2,0),-.12},
  {"Part",Vector3.new(3,1.5,2.8),Vector3.new(-.4,4.7,-.4),Vector3.new(.3,.8,.2),.6},
  {"Part",Vector3.new(2.4,1.6,2.2),Vector3.new(-2,.8,2.7),Vector3.new(0,.6,0),.1},
 },Color3.fromRGB(150,158,162),stage)
 if stage<2 then
  block(model,"Rock",Vector3.new(1.7,1.3,1.7),Vector3.new(1.3,.65,3.7),Color3.fromRGB(214,214,204),Enum.Material.Slate).CFrame*=CFrame.Angles(0,.25,0)
 end
end
B.Berries=function(model,kind,team,stage)
 -- Three low leaf mounds studded with berry clusters on their upper, camera-facing sides.
 -- Foraging strips the berries, then leaves two thinner, yellowing bushes.
 stage=math.min(stage,2)
 local picked=Color3.fromRGB(150,140,78)
 local mounds=stage>=2 and {
  {4.2,Vector3.new(-1.9,2.1,-.4),leafDark:Lerp(picked,.4)},
  {3.8,Vector3.new(1.7,1.9,.7),leaf:Lerp(picked,.4)},
 } or {
  {5.2,Vector3.new(-2.5,2.6,-.6),leafDark},
  {4.8,Vector3.new(2.4,2.4,-.9),leaf},
  {4.6,Vector3.new(.1,2.3,1.9),leaf:Lerp(leafLight,.5)},
 }
 for _,mound in ipairs(mounds) do ball(model,"Bush",mound[1],mound[2],mound[3],Enum.Material.Grass) end
 local spots=({[0]={{1,Vector3.new(-.5,.6,.62)},{2,Vector3.new(.35,.8,-.5)},{3,Vector3.new(-.15,.6,.8)},{1,Vector3.new(.4,.85,-.35)},
   {2,Vector3.new(.6,.55,.58)},{3,Vector3.new(.7,.7,.1)},{1,Vector3.new(-.2,.95,.2)},{2,Vector3.new(-.4,.9,.2)}},
  {{1,Vector3.new(-.5,.6,.62)},{2,Vector3.new(.35,.8,-.5)},{3,Vector3.new(-.15,.6,.8)},{2,Vector3.new(.6,.55,.58)}},
  {{1,Vector3.new(-.3,.8,.5)}}})[stage]
 for i,spot in ipairs(spots) do
  local mound=mounds[spot[1]]
  ball(model,"Berry",1.25,mound[2]+spot[2].Unit*(mound[1]/2-.25),i%2==0 and Color3.fromRGB(214,58,76) or Color3.fromRGB(170,40,66))
 end
end
return B
