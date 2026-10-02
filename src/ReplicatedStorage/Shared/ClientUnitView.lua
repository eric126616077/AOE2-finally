-- Client-only presentation cache: UI anchors share the same frame as the visible unit.
-- No replicated attributes, extra instances, or authoritative gameplay positions.
local View={}
local frames=setmetatable({}, {__mode="k"})
function View.GetFrame(model)
 local frame=frames[model]
 if frame then return frame end
 local root=model.PrimaryPart
 return root and root.CFrame or model:GetPivot()
end
function View.SetFrame(model,frame) frames[model]=frame end
function View.Clear(model) frames[model]=nil end
return View
