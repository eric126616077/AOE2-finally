-- Signatures: https://create.roblox.com/docs/reference/engine/classes/AnalyticsService
-- Published servers only. Client input mode is never guessed; Creator Hub supplies OS breakdowns.
local Telemetry={}
Telemetry.__index=Telemetry
local steps={join=1,queue=2,start=3,firstdeliver=4,firsthouse=5,firsttrain=6}
local names={"Joined","Queued","Started","FirstDelivery","FirstHouseCompleted","FirstUnitTrained"}
function Telemetry.new(options)
 options=options or {}
 local enabled=options.enabled
 if enabled==nil then enabled=not game:GetService("RunService"):IsStudio() and game.PlaceId>0 end
 return setmetatable({enabled=enabled,sessions={},service=options.service or (enabled and game:GetService("AnalyticsService")),
  guid=options.guid or function() return game:GetService("HttpService"):GenerateGUID(false) end,
  defer=options.defer or task.defer,log=options.log or warn},Telemetry)
end
function Telemetry:Join(player)
 if not self.enabled or self.sessions[player] then return end
 self.sessions[player]={id=self.guid(),facts={},sent=0}
 self:Fact(player,"join")
end
function Telemetry:Fact(player,fact)
 local session=self.sessions[player]
 local step=steps[fact]
 if not self.enabled or not session or not step then return end
 session.facts[step]=true
 while session.facts[session.sent+1] do
  session.sent+=1
  local nextStep=session.sent
  self.defer(function()
   local ok=pcall(function() self.service:LogFunnelStepEvent(player,"RTSFirstSession",session.id,nextStep,names[nextStep]) end)
   if not ok then self.log("[RTS Analytics] 漏斗事件未送出。") end
  end)
 end
end
function Telemetry:Match(player,event,duration,context)
 if not self.enabled or not self.sessions[player] or (event~="Started" and event~="Completed" and event~="Departed") then return end
 context=context or {}
 local fields={CustomField01="Mode="..(context.mode or "Unknown"),CustomField02="Civilization="..(context.civilization or "Unknown"),CustomField03="Map="..(context.size or "Unknown")}
 local value=event=="Started" and 1 or math.max(0,math.floor(duration or 0))
 self.defer(function()
  local ok=pcall(function() self.service:LogCustomEvent(player,"RTSMatch"..event,value,fields) end)
  if not ok then self.log("[RTS Analytics] 對局事件未送出。") end
 end)
end
function Telemetry:Leave(player) self.sessions[player]=nil end
return Telemetry
