-- Explicit Studio CLIENT test utilities. require() is inert; every mutation is a normal Command.
local Context={}
local keys={"food","wood","gold","stone"}
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
function Context.New(label,seconds)
 local Players=game:GetService("Players")
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"僅限 Studio Play 客戶端明確呼叫")
 assert(finite(seconds) and seconds>=30 and seconds<=3600,"階段期限須為 30–3600 秒")
 local self={label=label,started=os.clock(),deadline=os.clock()+seconds,checks=0,connections={},lastSend=0}
 self.player=Players.LocalPlayer
 self.RS=game:GetService("ReplicatedStorage")
 self.Config=require(self.RS.GameData.GameConfig)
 self.Grid=require(self.RS.Shared.Grid)
 self.command=assert(self.RS:FindFirstChild("RTSRemotes"),"缺少正式 RTSRemotes"):FindFirstChild("Command")
 assert(self.command,"缺少正式 Command")
 self.units=assert(workspace:FindFirstChild("Units"),"缺少正式 Units")
 self.buildings=assert(workspace:FindFirstChild("Buildings"),"缺少正式 Buildings")
 self.resources=assert(workspace:FindFirstChild("Resources"),"缺少正式 Resources")
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and #Players:GetPlayers()==2 and workspace:GetAttribute("AICount")==0 and workspace:GetAttribute("TeamMode")=="FFA","需 Playing 兩真人 FFA／無 AI 的正常 fixture")
 for _,actor in ipairs(Players:GetPlayers()) do if actor~=self.player then self.other=actor end end
 for _,actor in ipairs({self.player,self.other}) do
  assert(actor:GetAttribute("Defeated")==false and actor:GetAttribute("Forfeited")~=true and not actor:GetAttribute("Spectator"),"雙方須是存活真人參戰者")
 end
 local first,second=self.player:GetAttribute("TeamId"),self.other:GetAttribute("TeamId")
 assert(finite(first) and finite(second) and first>0 and second>0 and first%1==0 and second%1==0 and first~=second,"雙方須有正式合法且不同的敵對隊伍")
 self.generation=workspace:GetAttribute("MatchGeneration")
 return setmetatable(self,{__index=Context})
end
function Context:Check(ok,message)
 assert(ok,"["..self.label.." FAIL] "..message)
 self.checks+=1; print("["..self.label.." PASS] "..message)
end
function Context:Wait(predicate,seconds,message,allowEnded)
 assert(finite(seconds) and seconds>0,"無效觀察期限")
 local deadline=math.min(self.deadline,os.clock()+seconds)
 repeat
  assert(workspace:GetAttribute("MatchGeneration")==self.generation,"["..self.label.." FAIL] 戰局已重開")
  local phase=workspace:GetAttribute("MatchPhase")
  assert(phase=="Playing" or (allowEnded and phase=="Ended"),"["..self.label.." FAIL] 非預期階段："..tostring(phase))
  if predicate() then self:Check(true,message); return end
  task.wait(0.05)
 until os.clock()>=deadline
 error("["..self.label.." FAIL] 觀察逾時："..message,0)
end
function Context:Send(action,...)
 local delay=0.3-(os.clock()-self.lastSend); if delay>0 then task.wait(delay) end
 assert(os.clock()<self.deadline and workspace:GetAttribute("MatchPhase")=="Playing","階段已結束；停止正常命令")
 self.command:FireServer(action,...); self.lastSend=os.clock()
end
function Context:Models(folder,id,kind)
 local result={}
 for _,model in ipairs(folder:GetChildren()) do
  if model:IsA("Model") and model.PrimaryPart and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id
   and (not kind or model:GetAttribute(folder==self.units and "UnitType" or "BuildingType")==kind) then table.insert(result,model) end
 end
 return result
end
function Context:Model(model,folder,id,kind)
 self:Check(typeof(model)=="Instance" and model:IsA("Model") and model.Parent==folder and model.PrimaryPart
  and model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id
  and (not kind or model:GetAttribute(folder==self.units and "UnitType" or "BuildingType")==kind),"正式模型與所有權")
 return model
end
function Context:Position(model)
 local point=model:GetPivot().Position; return Vector3.new(point.X,self.Config.Map.GroundY,point.Z)
end
function Context:EdgeDistance(model,point)
 local center,half=self:Position(model),model.PrimaryPart.Size/2
 local dx=math.max(0,math.abs(point.X-center.X)-half.X)
 local dz=math.max(0,math.abs(point.Z-center.Z)-half.Z)
 return math.sqrt(dx*dx+dz*dz)
end
function Context:Point(point,margin)
 local half=(workspace:GetAttribute("MapSize") or self.Config.Map.MapSize)/2
 assert(typeof(point)=="Vector3" and finite(point.X) and finite(point.Y) and finite(point.Z)
  and math.abs(point.Y-self.Config.Map.GroundY)<0.01 and math.abs(point.X)+(margin or 2)<=half and math.abs(point.Z)+(margin or 2)<=half,"需地圖內有限地面位置")
 return point
end
function Context:Move(selection,point,message)
 self:Point(point)
 assert(type(selection)=="table" and #selection>0,"需真實己方單位選取")
 local far,slow=0,math.huge
 local goals={}; local columns=math.ceil(math.sqrt(#selection))
 for index,unit in ipairs(selection) do
  goals[unit]=self:Point(point+Vector3.new(((index-1)%columns-(columns-1)/2)*4,0,math.floor((index-1)/columns)*4))
 end
 for _,unit in ipairs(selection) do
  self:Model(unit,self.units,self.player.UserId)
  far=math.max(far,(self:Position(unit)-point).Magnitude); slow=math.min(slow,unit:GetAttribute("Speed") or 8)
 end
 self:Send("Order",selection,point)
 self:Wait(function()
  for _,unit in ipairs(selection) do if unit.Parent~=self.units or (self:Position(unit)-goals[unit]).Magnitude>4 or unit:GetAttribute("Order")~="待命" then return false end end
  return true
 end,far/math.max(1,slow)+90,message or "正常路徑移動到位")
end
function Context:Balances()
 local values={}; for _,key in ipairs(keys) do values[key]=self.player:GetAttribute(key) or 0 end; return values
end
function Context:Paid(before,cost)
 for _,key in ipairs(keys) do if math.abs((self.player:GetAttribute(key) or 0)-(before[key]-(cost[key] or 0)))>0.0001 then return false end end
 return true
end
function Context:QuietWorkers()
 local selection=self:Models(self.units,self.player.UserId,"villager")
 if #selection>0 then self:Send("Stop",selection) end
 self:Wait(function() for _,unit in ipairs(selection) do if unit.Parent==self.units and unit:GetAttribute("Order")~="待命" then return false end end; return true end,8,"經濟正常停止")
 local before,stable=self:Balances(),os.clock()
 self:Wait(function()
  local current=self:Balances()
  for _,key in ipairs(keys) do if before[key]~=current[key] then before,stable=current,os.clock(); break end end
  return os.clock()-stable>=0.6
 end,8,"扣款前真實餘額穩定")
end
function Context:Afford(cost)
 local missing=false; for key,value in pairs(cost) do if (self.player:GetAttribute(key) or 0)<value then missing=true end end
 if missing then
  local deliveredBefore=self.player:GetAttribute("DeliveredResources") or 0
  local workers=self:Models(self.units,self.player.UserId,"villager")
  assert(#workers>0,"需要真實村民採集補足成本")
  local last,assignments=0,{}
  self:Wait(function()
   local deficits={}
   for key,value in pairs(cost) do if (self.player:GetAttribute(key) or 0)<value then table.insert(deficits,key) end end
   if #deficits==0 then return true end
   if os.clock()-last>=4 then
    last=os.clock()
    for index,worker in ipairs(workers) do
     if worker.Parent==self.units then
      local key=assignments[worker]
      if not key or not table.find(deficits,key) then key=deficits[(index-1)%#deficits+1] end
      -- Preserve automatic carrying/delivery. Reissuing every scan can prevent deposits.
      if assignments[worker]~=key or worker:GetAttribute("Order")=="待命" then
      local target,best
      local candidates=self.resources:GetChildren()
      if key=="food" then for _,farm in ipairs(self:Models(self.buildings,self.player.UserId,"Farm")) do table.insert(candidates,farm) end end
      for _,candidate in ipairs(candidates) do
       if candidate:IsA("Model") and candidate.PrimaryPart and candidate:GetAttribute("ResourceType")==key and (candidate:GetAttribute("Amount") or 0)>0
        and ((candidate.Parent==self.resources and candidate:GetAttribute("RTSManagedResource")==true) or (candidate.Parent==self.buildings and candidate:GetAttribute("Complete")==true)) then
        local d=(self:Position(candidate)-self:Position(worker)).Magnitude
        if not best or d<best then target,best=candidate,d end
       end
      end
      assert(target,"正常地圖已沒有可採資源："..key)
      self:Send("Order",{worker},target); assignments[worker]=key
      end
     end
    end
   end
   return false
  end,900,"真實採集與交貨補足階段成本")
  self:Check((self.player:GetAttribute("DeliveredResources") or 0)>deliveredBefore,"補足成本來自伺服器實際交貨")
 end
 self:QuietWorkers()
end
function Context:BeginResearch(building,key)
 local data=assert(self.Config.Technologies[key],"未知科技")
 self:Model(building,self.buildings,self.player.UserId,data.building)
 assert(building:GetAttribute("Complete")==true and building:GetAttribute("Research")==nil and (building:GetAttribute("QueueCount") or 0)==0 and self.player:GetAttribute("Tech_"..key)~=true,"需未完成科技與空的正式研究建築")
 self:Afford(data.cost)
 local before,began=self:Balances(),os.clock()
 self:Send("Research",building,key)
 self:Wait(function() return self:Paid(before,data.cost) and building:GetAttribute("Research")==data.name and (building:GetAttribute("ResearchRemaining") or 0)>0 end,8,data.name.."真實扣款及研究開始")
 self:Check(self.player:GetAttribute("Tech_"..key)~=true,data.name.."研究尚未生效")
 return began,data
end
function Context:Research(building,key)
 local began,data=self:BeginResearch(building,key)
 self:Wait(function() return self.player:GetAttribute("Tech_"..key)==true and building:GetAttribute("Research")==nil end,data.time+15,data.name.."正常研究完成")
 self:Check(os.clock()-began>=data.time-1,data.name.."未縮短研究時間")
end
function Context:Placement(kind,anchor)
 local data=assert(self.Config.Buildings[kind],"未知建築")
 local half,g=(workspace:GetAttribute("MapSize") or self.Config.Map.MapSize)/2,self.Config.Map.GridSize
 local params=OverlapParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
 local excluded={}
 for _,name in ipairs({"AOE2_Ground","RTSScenery"}) do local item=workspace:FindFirstChild(name); if item then table.insert(excluded,item) end end
 params.FilterDescendantsInstances=excluded
 for radius=0,160,8 do for index=0,31 do
  local angle=index*math.pi/16
  local point=self.Grid.snap(anchor+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius),data.size)
  if math.abs(point.X)+data.size.X*g/2<=half-2 and math.abs(point.Z)+data.size.Y*g/2<=half-2 then
   local clear=true
   for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(point+Vector3.new(0,data.height/2,0)),Vector3.new(data.size.X*g-0.2,math.max(4,data.height),data.size.Y*g-0.2),params)) do
    if part.CanCollide or part:IsDescendantOf(self.units) or part:IsDescendantOf(self.buildings) or part:IsDescendantOf(self.resources) then clear=false; break end
   end
   if clear then return point end
  end
 end end
 error("沒有合法工地；不移走模型："..kind,0)
end
function Context:Build(kind,anchor)
 local data=assert(self.Config.Buildings[kind],"未知建築")
 self:Afford(data.cost)
 local workers=self:Models(self.units,self.player.UserId,"villager"); assert(#workers>=2,"需兩名正常村民施工")
 local selection={workers[1],workers[2]}
 local before,known,began=self:Balances(),{},os.clock()
 for _,model in ipairs(self:Models(self.buildings,self.player.UserId)) do known[model]=true end
 local point=self:Placement(kind,self:Point(anchor))
 self:Send("Build",kind,point,selection)
 local site
 self:Wait(function()
  for _,model in ipairs(self:Models(self.buildings,self.player.UserId,kind)) do if not known[model] then site=model; return true end end
  return false
 end,8,data.name.."正常工地生成")
 self:Check(site:GetAttribute("Complete")==false and site:GetAttribute("UnderConstruction")==true,"先建立未完工工地")
 self:Wait(function() return self:Paid(before,data.cost) end,8,data.name.."真實建造成本")
 local observed=false
 self:Wait(function()
  if (site:GetAttribute("ConstructionProgress") or 0)>0 and (site:GetAttribute("BuilderCount") or 0)>0 then observed=true end
  return site.Parent==self.buildings and site:GetAttribute("Complete")==true
 end,data.buildTime+240,data.name.."真實走路與施工完工")
 self:Check(observed and os.clock()-began>=data.buildTime/(1+self.Config.Construction.extraWorkerRate)-1,"正常施工進度與計時")
 self:Send("Stop",selection)
 return site
end
function Context:Damage(attacker,target)
 local data=assert(self.Config.Units[attacker:GetAttribute("UnitType")],"未知部隊")
 local victim=self.Config.Units[target:GetAttribute("UnitType")]
 local class=target.Parent==self.buildings and "building" or assert(victim,"未知敵方類別").class
 return math.max(1,(attacker:GetAttribute("Attack") or data.damage)+((data.bonus or {})[class] or 0)-(target:GetAttribute("Armor") or 0))
end
function Context:Report(actor)
 local raw=actor:GetAttribute("MatchReportJSON"); if type(raw)~="string" then return nil end
 local ok,value=pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
 return ok and type(value)=="table" and value.finished==true and value or nil
end
function Context:FinalWin(mode)
 self:Wait(function()
  return workspace:GetAttribute("MatchPhase")=="Ended" and self:Report(self.player) and self:Report(self.other)
   and workspace:GetAttribute("VictoryMode")==mode and workspace:GetAttribute("WinnerId")==self.player.UserId
   and workspace:GetAttribute("WinnerTeamId")==self.player:GetAttribute("TeamId")
 end,15,"自然終局、勝方欄位與雙方正式覆盤完成複製",true)
 local mine,theirs=self:Report(self.player),self:Report(self.other)
 self:Check(workspace:GetAttribute("VictoryMode")==mode and workspace:GetAttribute("WinnerId")==self.player.UserId and workspace:GetAttribute("WinnerTeamId")==self.player:GetAttribute("TeamId"),"模式與實際勝方一致")
 self:Check(mine.outcome=="win" and theirs.outcome=="loss" and mine.matchId==theirs.matchId and self.player:GetAttribute("Forfeited")==false and self.other:GetAttribute("Forfeited")==false,"雙方同局自然勝負，沒有投降")
 return mine,theirs
end
function Context:Finish(details)
 for _,connection in ipairs(self.connections) do connection:Disconnect() end
 return {checks=self.checks,elapsedSeconds=os.clock()-self.started,details=details,engineExecuted=true,cloudVerified=false}
end
function Context:Close()
 for _,connection in ipairs(self.connections) do connection:Disconnect() end
end
return Context