local position,size=Vector3.new(10,0,20),Vector3.new(16,8,12)
local team={name="team"}
local function generate(template)
 folders.PrivateFixture={FindFirstChild=function(_,kind) return kind=="House" and template end}
 return Factory.model("House",position,size,nil,"PrivateFixture",team)
end
local function fitted(value)
 expect(value and not value.destroyed,"factory did not return live geometry")
 expect(value.Name=="House" and value.PrimaryPart.Name=="Footprint","factory did not fit gameplay footprint")
 expect(value.PrimaryPart.Size==size and value.PrimaryPart.Anchored and value.PrimaryPart.CanCollide and value.PrimaryPart.CanQuery,"footprint flags changed")
 expect(not value.PrimaryPart.CanTouch and value.attributes.Radius==8,"footprint radius/touch changed")
 expect(value.scale==4,"factory did not retain conservative min-axis scaling")
end
local function fallback(value,before)
 fitted(value)
 expect(fallbackCalls==before+1 and value.fallbackKind=="House" and value.fallbackTeam==team,"fallback skipped original Art theme")
end
local before=fallbackCalls
fallback(generate(nil),before)
local empty=model({item("ModuleScript","PassiveModule")})
before=fallbackCalls
fallback(generate(empty),before)
expect(empty.cloneCalls==0 and not empty.destroyed,"geometry-free source was cloned/destroyed")

local part=item("Part","Geometry")
local hidden=item("Part","Hidden")
hidden.Transparency=1
local legacy=item("Script","Legacy")
local localScript=item("LocalScript","LegacyClient")
local passive=item("ModuleScript","PassiveModule")
local original=model({part,hidden,legacy,localScript,passive})
original.Parent={name="OriginalFolder"}
before=fallbackCalls
local copied=generate(original)
fitted(copied)
expect(copied==original.lastCopy and copied~=original and fallbackCalls==before,"valid template not used as a copy")
expect(copied.children[1].Anchored and not copied.children[1].CanCollide and not copied.children[1].CanTouch,"copy collision sanitization lost")
expect(not copied.children[2].CanQuery,"transparent copy stays queryable")
expect(copied.children[3].destroyed and copied.children[4].destroyed,"executable scripts survived copy")
expect(not copied.children[5].destroyed,"passive ModuleScript was unnecessarily removed")
expect(original.Archivable and original.Parent.name=="OriginalFolder" and not original.destroyed,"factory moved/mutated source model")
for _,child in ipairs(original.children) do
 expect(not child.destroyed and not child.Anchored and child.CanCollide and child.CanTouch and child.CanQuery,"factory modified original descendant")
end

local unarchivable=model({item("Part","Geometry")})
unarchivable.Archivable=false
before=fallbackCalls
fallback(generate(unarchivable),before)
expect(not unarchivable.Archivable and not unarchivable.destroyed and unarchivable.cloneCalls==1,"nil Clone fallback mutated source")

local throwing=model({item("Part","Geometry")})
throwing.cloneError=true
before=fallbackCalls
fallback(generate(throwing),before)
expect(not throwing.destroyed and throwing.cloneCalls==1,"Clone error fallback mutated source")

local noncopyPart=item("Part","Geometry")
noncopyPart.Archivable=false
local omitted=model({noncopyPart,item("ModuleScript","PassiveModule")})
before=fallbackCalls
fallback(generate(omitted),before)
expect(omitted.lastCopy.destroyed,"orphaned geometry-free clone leaked")
expect(not omitted.destroyed and not noncopyPart.Archivable and not noncopyPart.destroyed,"omitted-parts fallback altered source")

-- Repeat failures ensure there is no cached invalid clone or poisoned template.
for _=1,3 do before=fallbackCalls; fallback(generate(unarchivable),before) end
expect(unarchivable.cloneCalls==4 and not unarchivable.Archivable,"repeat fallback changed Archivable")

local function generateResource(template,kind,resourceSize)
 kind=kind or "Tree"
 folders.Resource={FindFirstChild=function(_,requested) return requested==kind and template end}
 return Factory.model(kind,position,resourceSize or size,nil,"Resource",team)
end
local function resourceFlags(value,expectedShadow,expectedSize)
 expectedSize=expectedSize or size
 local queries,colliders,shadows=0,0,0
 for _,child in ipairs(value:GetDescendants()) do
  if not child.destroyed and child:IsA("BasePart") then
   if child.CanQuery then queries+=1; expect(child==value.PrimaryPart,"resource visual remained queryable") end
   if child.CanCollide then colliders+=1; expect(child==value.PrimaryPart,"resource visual became collider") end
   if child.CastShadow then shadows+=1; expect(child.Name==expectedShadow,"resource retained wrong shadow caster") end
   expect(child.Anchored and not child.CanTouch,"resource anchor/touch rule changed")
  end
 end
 expect(queries==1 and colliders==1,"resource lost unique query collider")
 expect(shadows==(expectedShadow and 1 or 0),"resource shadow budget violated")
 expect(value.PrimaryPart.Name=="Footprint" and not value.PrimaryPart.CastShadow,"invisible resource footprint casts shadow")
 expect(value.PrimaryPart.Size==expectedSize and value.attributes.Radius==math.max(expectedSize.X,expectedSize.Z)/2,"resource footprint dimensions/radius changed")
end

-- Use the real shared tuning and a wide crown, not a copy of factory math.
local treeSize=Vector3.new(Config.Map.ResourceFootprint,Config.Resources.Tree.height,Config.Map.ResourceFootprint)
local wideTree=model({item("Part","WideCrown")})
wideTree.bounds=Vector3.new(15,19,15)
local denseTree=generateResource(wideTree,"Tree",treeSize)
resourceFlags(denseTree,"WideCrown",treeSize)
expect(Config.Map.ResourceVisualFootprints.Tree==14,"dense tree visual tuning missing")
expect(math.abs(denseTree.bounds.X-14)<0.00001 and math.abs(denseTree.bounds.Z-14)<0.00001,"configured canopy width did not enlarge tree visuals")
expect(denseTree.bounds.Y<=treeSize.Y,"wider canopy exceeded configured tree height")
expect(wideTree.bounds.X==15 and wideTree.bounds.Y==19 and wideTree.scale==1,"visual fitting altered original template geometry")

local tallOre=model({item("Part","TallOre")})
tallOre.bounds=Vector3.new(12,9,12)
local oreSize=Vector3.new(Config.Map.ResourceFootprint,Config.Resources.Gold.height,Config.Map.ResourceFootprint)
local fittedOre=generateResource(tallOre,"Gold",oreSize)
resourceFlags(fittedOre,"TallOre",oreSize)
expect(Config.Map.ResourceVisualFootprints.Gold==11 and fittedOre.bounds.Y==oreSize.Y,"resource visual fitting lost the original height limit")
expect(fittedOre.bounds.X<=11 and fittedOre.bounds.Z<=11,"resource visuals exceeded configured width")

local unconfigured=generateResource(wideTree,"FutureResource",treeSize)
resourceFlags(unconfigured,"WideCrown",treeSize)
expect(math.abs(unconfigured.bounds.X-treeSize.X)<0.00001 and math.abs(unconfigured.bounds.Z-treeSize.Z)<0.00001,"unconfigured resource changed original footprint fitting")
local oldVisualWidth=Config.Map.ResourceVisualFootprints.Tree
for _,invalid in ipairs({0,-1,math.huge,0/0,"14"}) do
 Config.Map.ResourceVisualFootprints.Tree=invalid
 local safeTree=generateResource(wideTree,"Tree",treeSize)
 resourceFlags(safeTree,"WideCrown",treeSize)
 expect(math.abs(safeTree.bounds.X-treeSize.X)<0.00001,"invalid visual width poisoned geometry fitting")
end
Config.Map.ResourceVisualFootprints.Tree=oldVisualWidth

local small=item("Part","SmallCrown")
small.Size=Vector3.new(2,3,2)
local large=item("Part","LargeCrown")
large.Size=Vector3.new(6,3,5)
local noShadow=item("Part","NoShadow")
noShadow.Size,noShadow.CastShadow=Vector3.new(20,3,20),false
local invisible=item("Part","HiddenCrown")
invisible.Size,invisible.Transparency=Vector3.new(30,3,30),1
local resourceSource=model({small,large,noShadow,invisible,item("Script","OldResourceScript")})
resourceSource.Parent={name="OriginalResourceFolder"}
local resourceCopy=generateResource(resourceSource)
resourceFlags(resourceCopy,"LargeCrown")
expect(resourceCopy==resourceSource.lastCopy and not resourceSource.destroyed,"resource template was replaced/moved")
expect(resourceSource.Parent.name=="OriginalResourceFolder" and resourceSource.Archivable,"resource source identity changed")
for index,child in ipairs(resourceSource.children) do
 expect(not child.destroyed and not child.Anchored and child.CanCollide and child.CanTouch and child.CanQuery,"resource source flags mutated")
 expect(child.CastShadow==(index~=3),"resource source shadow choice mutated")
end
expect(resourceCopy:FindFirstChild("OldResourceScript")==nil,"resource executable copy survived sanitization")

-- The footprint ranking uses projected XZ bounds even when visual parts tilt.
local upright=item("Part","Upright")
upright.Size=Vector3.new(3,3,3)
local tilted=item("Part","Tilted")
tilted.Size=Vector3.new(2,10,1)
tilted.CFrame.RightVector,tilted.CFrame.UpVector,tilted.CFrame.LookVector=Vector3.new(1,0,0),Vector3.new(0,0,1),Vector3.new(0,1,0)
resourceFlags(generateResource(model({upright,tilted})),"Tilted")

local onlyDisabled=item("Part","OnlyDisabled")
onlyDisabled.CastShadow=false
resourceFlags(generateResource(model({onlyDisabled})),nil)
resourceFlags(generateResource(model({invisible})),nil)
local translucent=item("Part","Translucent")
translucent.Transparency=.5
resourceFlags(generateResource(model({translucent})),"Translucent")
resourceFlags(generateResource(nil),"FallbackGeometry")
resourceFlags(generateResource(unarchivable),"FallbackGeometry")
expect(not unarchivable.Archivable and not unarchivable.destroyed,"resource fallback changed unarchivable template")

-- Resource optimization must not change normal building copies or fallbacks.
folders.Buildings={FindFirstChild=function(_,kind) return kind=="House" and resourceSource end}
local buildingCopy=Factory.model("House",position,size,nil,"Buildings",team)
for _,child in ipairs(buildingCopy:GetDescendants()) do
 if not child.destroyed and child:IsA("BasePart") then
  expect(child.CanQuery==(child==buildingCopy.PrimaryPart or child.Transparency<1),"resource query policy leaked into building")
  expect(child.CastShadow==(child.Name~="NoShadow"),"resource shadow budget leaked into building")
 end
end
expect(buildingCopy.PrimaryPart.CastShadow,"resource-only footprint policy leaked into building")
folders.Buildings=nil
folders.Resource=nil
local buildingFallback=Factory.model("House",position,size,nil,"Buildings",team)
expect(buildingFallback.children[1].CanQuery and buildingFallback.children[1].CastShadow,"resource optimization changed building fallback")

local function near(a,b) return math.abs(a-b)<0.00001 end
local function sameVector(a,b) return near(a.X,b.X) and near(a.Y,b.Y) and near(a.Z,b.Z) end
local player={UserId=37,DisplayName="測試玩家",Name="FixturePlayer",IsA=function(_,class) return class=="Player" end,
 GetAttribute=function(_,name) return ({TeamColor=team,Team=2,TeamId=2})[name] end}
local ai={Name="FixtureAI",IsA=function() return false end,
 GetAttribute=function(_,name) return ({TeamColor=team,Team=3,TeamId=3,UserId=-1,DisplayName="測試電腦"})[name] end}
local function unitFlags(kind,data,owner,profile)
 local value=Factory.unit(kind,position,data,owner)
 local root,volume=value:FindFirstChild("Root"),value:FindFirstChild("CollisionVolume")
 expect(root and value.PrimaryPart==root,"unit changed existing Root/PrimaryPart pivot")
 expect(not root.CanCollide and not root.CanQuery and not root.CanTouch,"unit Root became gameplay collider")
 expect(sameVector(root.Position,position+Vector3.new(0,2.5,0)),"unit pivot height changed")
 expect(volume and volume.Shape==Enum.PartType.Cylinder,"unit missing circular gameplay volume")
 expect(volume.Anchored and volume.CanCollide and volume.CanQuery and not volume.CanTouch,"unit collision/query/anchor flags changed")
 expect(volume.Transparency==1 and not volume.CastShadow,"unit collision volume is visible or casts shadow")
 expect(sameVector(volume.Size,Vector3.new(profile.height,profile.radius*2,profile.radius*2)),"unit volume dimensions differ from shared class profile")
 expect(sameVector(volume.Position,position+Vector3.new(0,profile.height/2,0)),"unit collision volume is not grounded")
 expect(near(math.abs(volume.CFrame.RightVector.Y),1),"cylinder local X axis is not vertical")
 expect(value.attributes.Radius==profile.radius and value.attributes.CollisionHeight==profile.height,"unit collision metadata differs from shared profile")
 local modifier=volume:FindFirstChildWhichIsA("PathfindingModifier")
 expect(modifier and modifier.PassThrough,"unit volume would block the static navigation mesh")
 local colliders=0
 for _,part in ipairs(value:GetDescendants()) do
  if part:IsA("BasePart") then
   if part.CanCollide then colliders+=1; expect(part==volume,"unit decorative art participates in physical collisions") end
   expect(part.Anchored and not part.CanTouch,"unit art became unanchored or touchable")
  end
 end
 expect(colliders==1,"unit must have one gameplay volume")
 local moved=Vector3.new(-70,0,24)
 value:PivotTo(CFrame.new(moved+Vector3.new(0,2.5,0))*CFrame.Angles(0,1.3,0))
 expect(sameVector(volume.Position,moved+Vector3.new(0,profile.height/2,0)),"unit movement separated collision volume from Root")
 expect(near(math.abs(volume.CFrame.RightVector.Y),1),"turning unit tilted collision volume")
 expect(value.attributes.UnitType==kind and value.attributes.UnitClass==data.class and value.attributes.HP==data.hp,"unit collision removed existing gameplay metadata")
 return value
end
local unitCount=0
for kind,data in pairs(Config.Units) do
 local profile=Config.UnitCollision.profiles[data.class]
 expect(profile and profile.radius>0 and profile.height>0,"configured unit class lacks shared collision profile")
 local value=unitFlags(kind,data,player,profile)
 expect(value.attributes.OwnerId==player.UserId and value.attributes.OwnerName==player.DisplayName,"player unit ownership changed")
 unitCount+=1
end
expect(unitCount==21,"all current playable unit kinds were not checked")
local aiUnit=unitFlags("villager",Config.Units.villager,ai,Config.UnitCollision.profiles.villager)
expect(aiUnit.attributes.OwnerId==-1 and aiUnit.attributes.OwnerName=="測試電腦","AI unit collision changed ownership")
unitFlags("futureUnit",{class="futureClass",name="測試單位",hp=50},player,Config.UnitCollision.default)
-- Changing shared tuning must change both volume and metadata without a factory edit.
local oldProfile=Config.UnitCollision.profiles.cavalry
Config.UnitCollision.profiles.cavalry={radius=3.25,height=7.5}
unitFlags("cavalry",Config.Units.cavalry,player,Config.UnitCollision.profiles.cavalry)
Config.UnitCollision.profiles.cavalry=oldProfile
-- Fields are walkable: the footprint stays selectable / placement-blocking but never collides.
local field=Factory.model("Farm",position,size,nil,"Buildings",team)
expect(field.PrimaryPart.Name=="Footprint" and not field.PrimaryPart.CanCollide and field.PrimaryPart.CanQuery and field.PrimaryPart.Anchored,"farm footprint blocks units or lost its query volume")
for kind,data in pairs(Config.Buildings) do
 expect((data.walkable==true)==(kind=="Farm"),"unexpected walkable building "..kind)
end
print(string.format("ModelFactory actual-body engine-mock tests: %d PASS (not Studio)",checks))
