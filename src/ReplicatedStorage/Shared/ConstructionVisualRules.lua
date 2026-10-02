-- Cosmetic construction stages. No costs, collision, health, or completion live here.
local Rules={MaxVisibleSites=24,MaxCompletionEffects=6,MaxDistance=600,UpdateInterval=.25}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Rules.Progress(value)
 return finite(value) and math.clamp(value,0,1) or 0
end
function Rules.Stage(progress)
 progress=Rules.Progress(progress)
 if progress>=1 then return 4 end
 if progress>=.7 then return 3 end
 if progress>=.3 then return 2 end
 if progress>=.08 then return 1 end
 return 0
end
function Rules.RevealAt(stage,height)
 height=Rules.Progress(height)
 if stage==0 then return 0 end
 if stage==1 then return .22+height*.3 end
 if stage==3 then return .7+height*.24 end
 return .4+height*.24
end
return Rules
