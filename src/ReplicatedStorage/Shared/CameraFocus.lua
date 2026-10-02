-- Client focus requests are events: identical destinations still get a new revision.
-- Engine-free so the attribute commit order and stale-request policy can be tested.
local CameraFocus={}
local maximumRevision=9007199254740991
local function validRevision(value,allowZero)
 return type(value)=="number" and value==value and value>= (allowZero and 0 or 1)
  and value<=maximumRevision and value%1==0
end
function CameraFocus.NextRevision(current)
 if current==nil then return 1 end
 if not validRevision(current,true) or current>=maximumRevision then return nil end
 return current+1
end
function CameraFocus.IsNew(revision,lastApplied)
 return validRevision(revision,false) and validRevision(lastApplied or 0,true) and revision>(lastApplied or 0)
end
function CameraFocus.Request(player,position)
 -- Callers provide Vector3; the camera also checks the observed position type.
 if position==nil then return false end
 local revision=CameraFocus.NextRevision(player:GetAttribute("CameraFocusRevision"))
 if not revision then return false end
 player:SetAttribute("CameraFocus",position)
 -- Publish after the destination, so a revision listener always sees committed data.
 player:SetAttribute("CameraFocusRevision",revision)
 return true
end
return CameraFocus
