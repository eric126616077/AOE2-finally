-- Runs the actual server cleanup lifecycle, rather than a reimplemented cleanup loop.
local function eventIndex(value)
 for index,event in ipairs(events) do if event==value then return index end end
 return nil
end
clearMatch()
expect(currentMatch==nil and matchTeams==nil and matchGeneration==8,"match context/generation was not invalidated")
expect(unit.destroyCalls==1 and building.destroyCalls==1 and aiUnit.destroyCalls==1,"old armies/buildings were not destroyed")
expect(state.reset==true and state.report==nil and aiState.report==nil,"retained player state/report was not reset")
expect(states[ai]==nil and byId[aiState.id]==nil and ai.destroyCalls==1,"old AI state survived reset")
expect(next(orders)==nil and next(training)==nil and next(construction)==nil and next(researching)==nil,
 "old economy/production/combat work remained active during resource cleanup")
expect(eventIndex("destroy:OwnedVillager")<eventIndex("destroy:GeneratedTree")
 and eventIndex("destroy:OwnedTownCenter")<eventIndex("destroy:GeneratedTree")
 and eventIndex("destroy:OwnedAIUnit")<eventIndex("destroy:GeneratedTree"),
 "resource deletion preceded owned unit/building destruction")
expect(taggedModel.destroyCalls==1 and taggedFolder.destroyCalls==1 and taggedModel.Parent==nil and taggedFolder.Parent==nil,
 "generated direct resource children retained their large geometry")
expect(taggedGeometry.destroyCalls==1,"generated resource descendants were not released with their owned model")
expect(unknownModel.Parent==resources and unknownModel.destroyCalls==0 and unknownGeometry.Parent==unknownModel,
 "unmarked Studio resource model or its geometry was altered")
expect(unknownFolder.Parent==resources and unknownFolder.destroyCalls==0,"unmarked resource folder was removed")
expect(nestedMarked.Parent==unknownFolder and nestedMarked.destroyCalls==0
 and nestedUnknown.Parent==unknownFolder and nestedUnknown.destroyCalls==0,
 "cleanup recursively modified children inside an unmarked user folder")
for _,item in ipairs({falseFlag,numericFlag,zeroFlag,textFlag}) do
 expect(item.Parent==resources and item.destroyCalls==0,"non-boolean-true ownership flag erased a user model: "..item.Name)
end
expect(managedResources==originalRegistry and next(managedResources)==nil,
 "managed resource registry retained nodes or invalidated references to the registry table")
expect(staleRegistryObject.Parent==workspace and staleRegistryObject.destroyCalls==0,
 "registry clearing destroyed an object outside direct resource children")
expect(ground.Parent==workspace and lobby.Parent==workspace and scenery.Parent==workspace and sceneryPart.Parent==scenery,
 "cleanup touched ground, lobby, or generated scenery")
expect(template.Parent==templateFolder and template.destroyCalls==0,"cleanup modified an original model template")
expect(workspace.attributes.ResourceNodeCount==0,"generated-node metadata did not reach zero")
expect(workspace.attributes.MapSize==1024 and workspace.attributes.MatchSize==1024 and workspace.attributes.MapSeed==2718
 and workspace.attributes.SceneryPartCount==46 and workspace.attributes.MapReady==true,
 "resource cleanup changed map dimensions/seed/scenery/readiness metadata")
expect(eventIndex("resourceCount:0")>eventIndex("destroy:GeneratedTree"),"zero-node count was published before owned nodes were released")

local remaining=#resources:GetChildren()
clearBattlefieldResources()
expect(#resources:GetChildren()==remaining and taggedModel.destroyCalls==1 and taggedFolder.destroyCalls==1,
 "repeated cleanup double-destroyed geometry or removed remaining unknown nodes")
expect(next(managedResources)==nil and workspace.attributes.ResourceNodeCount==0,"repeated cleanup left a stale registry/count")
expect(next(Relic.ground)==nil and next(Relic.trade.home)==nil,"match cleanup kept relic or trade-cart references")

-- An empty generated-node registry cannot replace inspecting resource ownership.
local laterNode=object("LaterGeneratedStone","Model",resources,{RTSManagedResource=true})
clearBattlefieldResources()
expect(laterNode.destroyCalls==1 and #resources:GetChildren()==remaining,
 "an uncached generated direct child survived cleanup")
expect(unknownFolder.destroyCalls==0 and nestedMarked.destroyCalls==0 and template.destroyCalls==0,
 "repeated cleanup touched preserved nested/template content")
print(string.format("PASS: %d actual resource lifecycle cleanup / registry / metadata / preservation checks",checks))
