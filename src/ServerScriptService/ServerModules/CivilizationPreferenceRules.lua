-- A saved preference can wait for the next lobby, while explicit choices always take priority.
local Rules={}
function Rules.takeLobby(state,phase)
 if (state.civilizationRevision or 0)>0 then state.pendingCivilization=nil; return nil end
 if phase~="Lobby" then return nil end
 local choice=state.pendingCivilization
 state.pendingCivilization=nil
 return choice
end
function Rules.receive(state,id,phase)
 if (state.civilizationRevision or 0)>0 then state.pendingCivilization=nil; return nil end
 state.pendingCivilization=id
 return Rules.takeLobby(state,phase)
end
function Rules.select(state)
 state.civilizationRevision=(state.civilizationRevision or 0)+1
 state.pendingCivilization=nil
end
return Rules
