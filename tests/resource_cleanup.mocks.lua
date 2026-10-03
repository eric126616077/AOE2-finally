-- Engine/lifecycle doubles only. The runner extracts the real cleanup and clearMatch bodies.
local checks=0
local function expect(condition,message)
 checks+=1
 assert(condition,message)
end
local events={}
local workspace={attributes={MapSize=1024,MatchSize=1024,MapSeed=2718,SceneryPartCount=46,MapReady=true,ResourceNodeCount=680}}
function workspace:SetAttribute(key,value)
 self.attributes[key]=value
 if key=="ResourceNodeCount" then table.insert(events,"resourceCount:"..tostring(value)) end
end
function workspace:FindFirstChild() error("resource cleanup must not discover/delete other Workspace geometry") end
local function object(name,class,parent,attributes)
 local item={Name=name,ClassName=class,Parent=parent,attributes=attributes or {},children={},destroyCalls=0}
 function item:IsA(kind) return self.ClassName==kind end
 function item:GetAttribute(key) return self.attributes[key] end
 function item:GetChildren()
  local result={}
  for _,child in ipairs(self.children) do if child.Parent==self then table.insert(result,child) end end
  return result
 end
 function item:Destroy()
  self.destroyCalls+=1
  table.insert(events,"destroy:"..self.Name)
  for _,child in ipairs(self:GetChildren()) do child:Destroy() end
  self.Parent=nil
 end
 if parent and parent.children then table.insert(parent.children,item) end
 return item
end
local resources=object("Resources","Folder",workspace)
local taggedModel=object("GeneratedTree","Model",resources,{RTSManagedResource=true})
local taggedGeometry=object("GeneratedTreeGeometry","Part",taggedModel)
local taggedFolder=object("GeneratedResourceGroup","Folder",resources,{RTSManagedResource=true})
local unknownModel=object("UserTree","Model",resources)
local unknownGeometry=object("UserTreeGeometry","Part",unknownModel)
local unknownFolder=object("UserResourceFolder","Folder",resources)
local nestedMarked=object("NestedUserCopyWithFlag","Model",unknownFolder,{RTSManagedResource=true})
local nestedUnknown=object("NestedUserModel","Model",unknownFolder)
local falseFlag=object("FalseFlag","Model",resources,{RTSManagedResource=false})
local numericFlag=object("NumericFlag","Model",resources,{RTSManagedResource=1})
local zeroFlag=object("ZeroFlag","Model",resources,{RTSManagedResource=0})
local textFlag=object("TextFlag","Model",resources,{RTSManagedResource="true"})
local ground=object("AOE2_Ground","Part",workspace)
local lobby=object("AOE2_LobbyWorld","Folder",workspace,{RTSLobbyGenerated=true})
local scenery=object("RTSScenery","Folder",workspace,{RTSManagedScenery=true})
local sceneryPart=object("TradePath","Part",scenery)
local templateFolder=object("Buildings","Folder",nil)
local template=object("OriginalTreeTemplate","Model",templateFolder,{RTSManagedResource=true})
local staleRegistryObject=object("OutsideResources","Model",workspace,{RTSManagedResource=true})
local managedResources={[taggedModel]=true,[taggedFolder]=true,[unknownModel]=true,[staleRegistryObject]=true}
local originalRegistry=managedResources
local currentMatch={id="old-match"}
local matchTeams={old=true}
local matchGeneration=7
local byId={}
local player=object("Player","Player",workspace)
local ai=object("AI","Folder",workspace)
local unit=object("OwnedVillager","Model",workspace)
local building=object("OwnedTownCenter","Model",workspace)
local aiUnit=object("OwnedAIUnit","Model",workspace)
local state={id=12,actor=player,units={[unit]=true},buildings={[building]=true},report={}}
local aiState={id=-3,actor=ai,units={[aiUnit]=true},buildings={},report={}}
local states={[player]=state,[ai]=aiState}
byId[state.id],byId[aiState.id]=state,aiState
local orders={[unit]={kind="gather",target=taggedModel},[aiUnit]={kind="attack"}}
local training={[building]={queued=true}}
local construction={[building]={work=true}}
local researching={[building]={research=true}}
local actionClocks={[unit]={work=true}}
local AutoWork={units={[unit]={hold=true}}}
local AOE={boars={},neutralSheep={},prices={},publishPrices=function() end}
local reportSequence,reportSubjectSequence=99,23
local reportSubjects={[unit]=true}
local startingSides=2
local Factory={cleared=0}
function Factory.clearCorpses() Factory.cleared+=1 end
local function stop(model)
 expect(workspace.attributes.MatchGeneration==8,"pending unit orders stopped before generation invalidation")
 table.insert(events,"stop:"..model.Name)
 orders[model]=nil
end
local function clearReport(actorState) actorState.report=nil end
local function destroyModel(model)
 expect(workspace.attributes.MatchGeneration==8,"player geometry destroyed before generation invalidation")
 if state.units[model] then state.units[model]=nil end
 if state.buildings[model] then state.buildings[model]=nil end
 if aiState.units[model] then aiState.units[model]=nil end
 model:Destroy()
end
local function resetActor(actorState)
 actorState.units,actorState.buildings={},{}
 actorState.reset=true
end
local originalResourceChildren=resources.GetChildren
function resources:GetChildren()
 expect(next(orders)==nil and next(training)==nil and next(construction)==nil and next(researching)==nil,
  "resource cleanup began while old orders/production still referenced nodes")
 expect(unit.destroyCalls==1 and building.destroyCalls==1 and aiUnit.destroyCalls==1,
  "resource cleanup began before owned unit/building teardown")
 return originalResourceChildren(self)
end
