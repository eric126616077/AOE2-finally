-- Test-only LocalScript, mapped only by fog-validation.project.json.
-- Studio CLIENT：開一局（1 真人＋1 簡單電腦、小地圖），檢查戰爭迷霧不再由一列一塊的 Part 拼成：
--  1. RTSFogOfWar 只有一片透明平面（FogPlane），沒有舊的 Unexplored／Fog 方塊。
--  2. SurfaceGui 每格對齊整數像素，同一列的區段不重疊、不留縫；己方主城所在格沒有被蓋住。
--  3. 小地圖迷霧在兩層 CanvasGroup 內，層內格子不透明。
-- 畫布方向（平面上的洞是否落在主城）無法從腳本讀回，跑完後由截圖確認。輸出以 [FOG] 開頭。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local TAG="[FOG] "
local passed,failed=0,0
local function check(condition,message,detail)
 if condition then passed+=1; print(TAG.."PASS "..message..(detail~=nil and ("  ("..tostring(detail)..")") or ""))
 else failed+=1; warn(TAG.."FAIL "..message..(detail~=nil and ("  ("..tostring(detail)..")") or "")) end
 return condition
end
local function waitFor(predicate,seconds)
 local deadline=os.clock()+seconds
 repeat
  local value=predicate()
  if value then return value end
  task.wait(0.25)
 until os.clock()>deadline
 return nil
end
local function whole(value) return value==math.floor(value) end
local ok,problem=pcall(function()
 assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30),"初始化逾時")
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=200,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 task.wait(3)
 local Config=require(RS.GameData.GameConfig)
 local FogView=require(RS.Shared.FogView)
 local FogRules=require(RS.Shared.FogRules)
 local grid=FogView.grid

 -- 1. 平面 -------------------------------------------------------------------
 local folder=workspace:FindFirstChild("RTSFogOfWar")
 check(FogView.Active() and grid~=nil and folder~=nil,"迷霧啟用")
 local children=folder and folder:GetChildren() or {}
 local plane=folder and folder:FindFirstChild("FogPlane")
 check(#children==1 and plane~=nil,"迷霧資料夾只有一片平面",#children)
 local slabs=0
 for _,item in ipairs(folder and folder:GetDescendants() or {}) do if item:IsA("BasePart") and item~=plane then slabs+=1 end end
 check(slabs==0,"沒有一列一塊的迷霧方塊",slabs)
 if not (plane and grid) then return end
 check(plane.Transparency==1 and not plane.CanCollide and not plane.CanQuery and not plane.CastShadow,"平面透明且不參與碰撞、點選與陰影")
 local span=grid.count*grid.cell
 local top=plane.CFrame:PointToWorldSpace(Vector3.new(0,0,-plane.Size.Z/2))
 check(math.abs(top.Y-(Config.Map.GroundY+1.95))<1e-3,"平面正面朝上、高度與舊迷霧頂面相同",top.Y)
 check(plane.CFrame.LookVector:Dot(Vector3.yAxis)>0.999,"平面正面法線朝上",plane.CFrame.LookVector)
 check(math.abs(plane.Size.X-span)<1e-3 and math.abs(plane.Size.Y-span)<1e-3,"平面涵蓋整個迷霧格線",plane.Size)

 -- 2. SurfaceGui ---------------------------------------------------------------
 local surface=plane:FindFirstChildOfClass("SurfaceGui")
 check(surface~=nil and surface.Face==Enum.NormalId.Front and surface.Adornee==plane,"SurfaceGui 在平面正面")
 if not surface then return end
 local canvas=surface.CanvasSize
 local px=canvas.X/grid.count
 check(whole(px) and px>=1 and canvas.X==canvas.Y,"每格是整數像素",px)
 local frames,misaligned,unknown,overlaps,gaps=0,0,0,0,0
 local rowsSeen={}
 for _,frame in ipairs(surface:GetChildren()) do
  if frame:IsA("Frame") then
   frames+=1
   local p,s=frame.Position,frame.Size
   if p.X.Scale~=0 or p.Y.Scale~=0 or s.X.Scale~=0 or s.Y.Scale~=0 or frame.BorderSizePixel~=0
    or not whole(p.X.Offset/px) or not whole(p.Y.Offset/px) or not whole(s.X.Offset/px) or s.Y.Offset~=px then misaligned+=1 end
   local expected=frame.Name=="Unexplored" and 0 or frame.Name=="Fog" and .5 or nil
   if expected==nil or frame.BackgroundTransparency~=expected then unknown+=1 end
   local row=grid.count-p.Y.Offset/px
   rowsSeen[row]=rowsSeen[row] or {}
   table.insert(rowsSeen[row],{from=p.X.Offset,to=p.X.Offset+s.X.Offset})
  end
 end
 for _,spans in pairs(rowsSeen) do
  table.sort(spans,function(a,b) return a.from<b.from end)
  for i=2,#spans do if spans[i].from<spans[i-1].to then overlaps+=1 end end
 end
 -- 每列的區段應和 FogRules.runs 完全一致（含相鄰不同狀態之間不留縫）。
 local expectedFrames=0
 for row=1,grid.count do
  local runs=FogRules.runs(grid,row)
  expectedFrames+=#runs
  local spans=rowsSeen[row] or {}
  if #spans~=#runs then gaps+=1 else
   for i,run in ipairs(runs) do
    local from=(grid.count-run.last)*px
    local found=false
    for _,span in ipairs(spans) do if span.from==from and span.to==from+(run.last-run.first+1)*px then found=true end end
    if not found then gaps+=1 end
   end
  end
 end
 check(frames>0 and frames==expectedFrames,"迷霧格數與規則一致",frames.."/"..expectedFrames)
 check(misaligned==0,"所有格子位置與大小對齊像素",misaligned)
 check(unknown==0,"未探索不透明、暗霧半透明",unknown)
 check(overlaps==0,"同一列的格子不重疊",overlaps)
 check(gaps==0,"每列與規則區段完全吻合（無縫隙）",gaps)
 local home=player:GetAttribute("HomePosition")
 local column,row=FogRules.cellOf(grid,home.X,home.Z)
 local u,v=(grid.count-column+.5)*px,(grid.count-row+.5)*px
 local covered=false
 for _,frame in ipairs(surface:GetChildren()) do
  if frame:IsA("Frame") then
   local p,s=frame.Position,frame.Size
   if u>=p.X.Offset and u<p.X.Offset+s.X.Offset and v>=p.Y.Offset and v<p.Y.Offset+s.Y.Offset then covered=true end
  end
 end
 check(FogView.VisibleAt(home) and not covered,"主城所在格沒有迷霧",column..","..row)

 -- 3. 小地圖 -----------------------------------------------------------------
 local minimap=player.PlayerGui:FindFirstChild("Minimap",true)
 local layers,cells,badCells,stray=0,0,0,0
 if minimap then
  for _,item in ipairs(minimap:GetChildren()) do
   if item.Name=="MinimapFogLayer" and item:IsA("CanvasGroup") then
    layers+=1
    for _,cell in ipairs(item:GetChildren()) do
     cells+=1
     if cell.BackgroundTransparency~=0 or cell.BorderSizePixel~=0 then badCells+=1 end
    end
   elseif item.Name=="MinimapFog" then stray+=1 end
  end
 end
 check(layers==2,"小地圖迷霧有兩層 CanvasGroup",layers)
 check(cells>0,"小地圖迷霧有格子",cells)
 check(badCells==0 and stray==0,"小地圖格子在層內且不透明",badCells.."/"..stray)
end)
if not ok then failed+=1; warn(TAG.."FAIL 測試中斷："..tostring(problem)) end
print(TAG..(failed==0 and "ALL PASS" or "DONE WITH FAILURES").." passed="..passed.." failed="..failed)

-- 目視檢查：俯瞰主城 90 秒，供截圖確認視野圓落在主城上、地面沒有一條條線（只截圖，不需要輸入）。
local home=player:GetAttribute("HomePosition")
if typeof(home)=="Vector3" then
 local focus=Vector3.new(home.X,0,home.Z)
 Run:BindToRenderStep("FogTestCamera",Enum.RenderPriority.Camera.Value+5,function()
  local camera=workspace.CurrentCamera
  if camera then camera.CameraType=Enum.CameraType.Scriptable; camera.FieldOfView=50; camera.CFrame=CFrame.lookAt(focus+Vector3.new(0,330,250),focus) end
 end)
 print(TAG.."HOLD 相機俯瞰主城 "..tostring(focus).."（畫面上方＝世界 -Z，右方＝世界 +X）")
 task.delay(90,function() Run:UnbindFromRenderStep("FogTestCamera"); print(TAG.."HOLD END") end)
end
