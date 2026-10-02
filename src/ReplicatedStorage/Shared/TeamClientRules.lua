-- Client display/proposal rules only. Server TeamRules still assigns teams and
-- validates every setting/command; clients cannot grant ownership or alliances.
local Rules={}
local modeNames={FFA="各自為戰",Teams="分隊對戰",CoopAI="合作對電腦"}
local settingFields={expectedPlayers=true,size=true,aiCount=true,difficulty=true,population=true,startingResources=true,victory=true,teamMode=true}
local function integer(value,minimum,maximum)
 return type(value)=="number" and value==value and value%1==0 and value>=minimum and value<=maximum
end
local function ownerId(value)
 return integer(value,-9007199254740991,9007199254740991) and value~=0
end
function Rules.ValidSettings(settings,queuedCount)
 if type(settings)~="table" or not integer(settings.expectedPlayers,1,4) or not integer(settings.aiCount,0,3)
  or not integer(queuedCount,0,4) or settings.expectedPlayers<queuedCount or settings.expectedPlayers+settings.aiCount>4 then return false end
 local mode=settings.teamMode or "FFA"
 if not modeNames[mode] then return false end
 local total=settings.expectedPlayers+settings.aiCount
 return (mode~="Teams" or total==2 or total==4) and (mode~="CoopAI" or settings.aiCount>=1)
end
function Rules.NextSetting(settings,key,values,queuedCount)
 if type(settings)~="table" or not integer(settings.expectedPlayers,1,4) or not integer(settings.aiCount,0,3)
  or not settingFields[key] or type(values)~="table" or #values<1 or #values>8 or not integer(queuedCount,0,4) then return nil end
 local index=table.find(values,settings[key]) or 1
 local blockedMessage
 for _=1,#values do
  index=index%#values+1
  local request=table.clone(settings)
  request[key]=values[index]
  if not integer(request.expectedPlayers,1,4) or not integer(request.aiCount,0,3) then continue end
  if key=="teamMode" then
   local total=request.expectedPlayers+request.aiCount
   if request.teamMode=="Teams" then
    if total==1 then request.aiCount=1 elseif total==3 then request.aiCount=4-request.expectedPlayers end
   elseif request.teamMode=="CoopAI" then
    if request.expectedPlayers==4 then
     if queuedCount==4 then blockedMessage="合作對電腦需先由一位玩家退出集合；已略過這個選項。"; continue end
     request.expectedPlayers=3
    end
    request.aiCount=math.max(1,math.min(request.aiCount,4-request.expectedPlayers))
   end
  elseif key=="expectedPlayers" then request.aiCount=math.min(request.aiCount,4-request.expectedPlayers) end
  if Rules.ValidSettings(request,queuedCount) and (request[key]~=settings[key] or request.aiCount~=settings.aiCount or request.expectedPlayers~=settings.expectedPlayers) then return request,blockedMessage end
 end
 return nil,blockedMessage or "目前人數沒有其他合法選項；分隊需 2 或 4 陣營，合作需至少一個電腦。"
end
function Rules.ModeLabel(mode,humanCount,aiCount)
 if not modeNames[mode] then return "模式載入中" end
 if mode=="Teams" then
  local total=type(humanCount)=="number" and type(aiCount)=="number" and humanCount+aiCount or 0
  return modeNames[mode]..(total==4 and " · 2v2" or total==2 and " · 1v1" or "")
 end
 return modeNames[mode]
end
function Rules.TeamLabel(mode,teamId)
 if not integer(teamId,1,4) then return "分隊待確認" end
 if mode=="CoopAI" then return teamId==1 and "真人隊" or "電腦隊" end
 if mode=="Teams" then return "第 "..teamId.." 隊" end
 return "各自為戰"
end
function Rules.Relation(mode,localId,localTeam,targetId,targetTeam)
 if targetId==nil then return "neutral" end
 if not ownerId(localId) or not ownerId(targetId) then return "unresolved" end
 if localId==targetId then return "own" end
 if mode=="FFA" then return "enemy" end
 if mode~="Teams" and mode~="CoopAI" then return "unresolved" end
 if not integer(localTeam,1,4) or not integer(targetTeam,1,4) then return "unresolved" end
 return localTeam==targetTeam and "ally" or "enemy"
end
return Rules
