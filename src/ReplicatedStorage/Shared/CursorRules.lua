-- Pure context-cursor decision shared by the client and CLI tests. Like AOE, the
-- pointer previews what a right click would do; the server still decides.
local CursorRules={}
CursorRules.Kinds={
 none=true, default=true, select=true, move=true, attack=true,
 gather_food=true, gather_wood=true, gather_gold=true, gather_stone=true,
 build=true, repair=true, rally=true, invalid=true,
}
local gatherKinds={food="gather_food",wood="gather_wood",gold="gather_gold",stone="gather_stone"}
-- ctx = {
--  active, touch, overUI, placing, placementValid, rally,
--  garrison                       -- 駐紮模式：等待點選自己可駐紮的建築
--  villagers, military            -- counts of selected own units
--  monks                          -- selected own monks (also counted in military)
--  target = nil | {relation="own"|"ally"|"enemy"|"neutral"|"unresolved",
--                  unit, building, resource, complete, damaged,
--                  garrison}      -- 自己已完工、可駐紮的建築
-- }
function CursorRules.Resolve(ctx)
 if type(ctx)~="table" or not ctx.active or ctx.touch then return "none" end
 if ctx.overUI then return "default" end
 if ctx.placing then return ctx.placementValid and "build" or "invalid" end
 local target=type(ctx.target)=="table" and ctx.target or nil
 if ctx.rally then
  if target and (target.relation=="enemy" or target.relation=="ally" or (not target.resource and target.relation~="neutral")) then return "invalid" end
  return "rally"
 end
 if ctx.garrison then return target and target.garrison==true and "select" or "invalid" end
 local villagers=type(ctx.villagers)=="number" and ctx.villagers or 0
 local military=type(ctx.military)=="number" and ctx.military or 0
 if villagers+military<=0 then
  return target and "select" or "default"
 end
 if not target then return "move" end
 local monks=type(ctx.monks)=="number" and math.clamp(ctx.monks,0,military) or 0
 -- Monks convert units, never buildings; a monk-only selection cannot act on an enemy building.
 if target.relation=="enemy" and target.building and monks>0 and monks==villagers+military then return "invalid" end
 if target.relation=="enemy" and (target.unit or target.building) then return "attack" end
 if monks>0 and target.unit and target.relation=="own" and target.damaged then return "repair" end
 if target.relation=="unresolved" then return "default" end
 local ownWork=target.building and target.relation=="own" and villagers>0
 -- An unfinished farm is still a construction site before it yields food.
 if ownWork and target.complete==false then return "build" end
 if target.resource and (target.relation=="neutral" or target.relation=="own") then
  return villagers>0 and gatherKinds[target.resource] or "move"
 end
 if ownWork and target.damaged then return "repair" end
 return "select"
end
return CursorRules
