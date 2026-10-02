-- Cosmetic damage states of completed buildings. Health, repair and destruction stay on the server.
local Rules={Half=.5,Third=1/3,Recover=.04,MaxOverlays=40,MaxFires=24}
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
function Rules.Ratio(hp,maxHP)
 if not finite(hp) or not finite(maxHP) or maxHP<=0 then return nil end
 return math.clamp(hp/maxHP,0,1)
end
-- 0 intact, 1 damaged (half health or less), 2 ruined (a third or less).
-- A repair has to clear a threshold by a margin, so a building fought over at the boundary does not flicker.
function Rules.Stage(hp,maxHP,previous)
 local ratio=Rules.Ratio(hp,maxHP)
 if not ratio then return 0 end
 local stage=ratio<=Rules.Third and 2 or ratio<=Rules.Half and 1 or 0
 if finite(previous) and stage<previous then
  if previous>=2 and ratio<=Rules.Third+Rules.Recover then return 2 end
  if previous>=1 and ratio<=Rules.Half+Rules.Recover then return 1 end
 end
 return stage
end
-- Stable pseudo-random value in [0,1) from a part's place in its building, so every client
-- breaks the same pieces and a building keeps its stage 1 holes when it reaches stage 2.
function Rules.Rank(x,y,z)
 if not finite(x) or not finite(y) or not finite(z) then return 0 end
 local n=math.floor(x*4+.5)*73856093+math.floor(y*4+.5)*19349663+math.floor(z*4+.5)*83492791
 n=(n%233280*9301+49297)%233280
 return n/233280
end
-- How many of `count` parts of one construction stage are missing. Only roofs (3) and trim (2)
-- break away; foundations and walls stay, so the footprint and silhouette remain readable.
function Rules.HideCount(stage,constructionStage,count)
 if not finite(count) or count<=0 then return 0 end
 if stage<1 or (constructionStage~=2 and constructionStage~=3) then return 0 end
 local roof=constructionStage==3
 local half=math.ceil(count*(roof and .3 or .12)-1e-9)
 if stage==1 then return math.min(count,half) end
 -- The ruined state always loses at least one more piece than the damaged state.
 return math.min(count,math.max(half+1,math.ceil(count*(roof and .6 or .35)-1e-9)))
end
-- Share of charcoal mixed into a surviving part.
function Rules.Soot(stage,rank)
 rank=finite(rank) and math.clamp(rank,0,1) or 0
 if stage>=2 then return .25+.3*rank end
 if stage==1 then return .08+.2*rank end
 return 0
end
-- Wall lines are placed by the dozen: they get a little rubble and no fire.
function Rules.Fires(stage,line)
 if line then return 0 end
 return stage>=2 and 3 or stage==1 and 1 or 0
end
function Rules.Rubble(stage,line)
 if stage<1 then return 0 end
 if line then return stage>=2 and 2 or 1 end
 return stage>=2 and 6 or 3
end
return Rules
