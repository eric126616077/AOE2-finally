-- Client cursor presentation. The hardware pointer always stays visible (so a
-- script error can never hide it); action cursors add an AOE-style badge.
local UIS=game:GetService("UserInputService")
local Players=game:GetService("Players")
local CursorRules=require(script.Parent.CursorRules)
local View={}
local ARROW="rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png"
local HAND="rbxasset://textures/Cursors/KeyboardMouse/ArrowCursor.png"
-- glyph, badge colour, pointer image
local styles={
 default={nil,nil,ARROW}, move={nil,nil,ARROW}, select={nil,nil,HAND},
 attack={"⚔️",Color3.fromRGB(158,38,32),HAND},
 gather_food={"🌾",Color3.fromRGB(116,92,34),HAND},
 gather_wood={"🪓",Color3.fromRGB(64,94,42),HAND},
 gather_gold={"⛏️",Color3.fromRGB(150,118,30),HAND},
 gather_stone={"⛏️",Color3.fromRGB(92,98,104),HAND},
 build={"🔨",Color3.fromRGB(110,78,44),HAND},
 repair={"🛠️",Color3.fromRGB(70,90,120),HAND},
 rally={"🚩",Color3.fromRGB(46,86,140),ARROW},
 invalid={"🚫",Color3.fromRGB(70,30,30),ARROW},
}
local screen,badge,glyph
local current="none"
local function ensure()
 if screen and screen.Parent then return end
 local playerGui=Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
 if not playerGui then return end
 screen=Instance.new("ScreenGui")
 screen.Name="RTSCursor"
 screen.ResetOnSpawn=false
 screen.IgnoreGuiInset=true
 screen.DisplayOrder=100
 screen.Parent=playerGui
 badge=Instance.new("Frame")
 badge.Name="CursorBadge"
 badge.Size=UDim2.fromOffset(26,26)
 badge.BorderSizePixel=0
 badge.BackgroundTransparency=0.1
 badge.Active=false
 badge.Visible=false
 badge.Parent=screen
 local corner=Instance.new("UICorner")
 corner.CornerRadius=UDim.new(1,0)
 corner.Parent=badge
 local edge=Instance.new("UIStroke")
 edge.Color=Color3.fromRGB(226,190,112)
 edge.Thickness=1.5
 edge.Parent=badge
 glyph=Instance.new("TextLabel")
 glyph.Name="Glyph"
 glyph.BackgroundTransparency=1
 glyph.Size=UDim2.fromScale(1,1)
 glyph.TextScaled=true
 glyph.Font=Enum.Font.SourceSansBold
 glyph.TextColor3=Color3.new(1,1,1)
 glyph.Active=false
 glyph.Parent=badge
end
function View:Set(kind)
 if not CursorRules.Kinds[kind] then kind="none" end
 ensure()
 if kind~=current then
  current=kind
  local style=styles[kind]
  UIS.MouseIcon=style and style[3] or ""
  if badge then
   badge.Visible=style~=nil and style[1]~=nil
   if badge.Visible then glyph.Text=style[1]; badge.BackgroundColor3=style[2] end
  end
 end
 if badge and badge.Visible then
  -- GetMouseLocation includes the top inset; IgnoreGuiInset matches that origin.
  local point=UIS:GetMouseLocation()
  badge.Position=UDim2.fromOffset(point.X+12,point.Y+12)
 end
end
function View:Get()
 return current
end
function View:Destroy()
 UIS.MouseIcon=""
 if screen then screen:Destroy() end
 screen,badge,glyph,current=nil,nil,nil,"none"
end
return View
