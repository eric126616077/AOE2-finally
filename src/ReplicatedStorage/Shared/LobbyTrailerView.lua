-- 大廳的戰鬥預告片（只在客戶端）：廣場大螢幕靜音循環播放，大廳按鈕開啟有聲的全螢幕播放。
-- 影片是 cinematic.project.json 錄下後上傳的 Roblox 影片資產（GameConfig.Lobby.trailer.videoId）；
-- 尚未設定或載入失敗時，大螢幕改輪播預告片字卡，全螢幕播放不提供。
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local RS=game:GetService("ReplicatedStorage")
local Config=require(RS.GameData.GameConfig)
local Rules=require(script.Parent.LobbyTrailerRules)
local Cinematic=require(script.Parent.CinematicRules)
local Music=require(script.Parent.MusicDirector)

local View={}
local player=Players.LocalPlayer
local settings=Config.Lobby.trailer or {}
local videoId=Rules.AssetId(settings.videoId)
local slides=Rules.Slides(Cinematic.Stages)
local SLIDE_SECONDS=settings.slideSeconds or 4.5
local LOAD_TIMEOUT=20
local INK=Color3.fromRGB(27,31,48)
local GOLD=Color3.fromRGB(255,200,40)
local TITLE_FONT,BODY_FONT=Enum.Font.FredokaOne,Enum.Font.GothamBold

local started=false
local failed=false
local screenGui,screenVideo,slideFrame,slideHeading,slideDetail
local theater,theaterVideo,theaterProgress,theaterStage,theaterScale
local slideConnection,progressConnection
local refreshScreen
local opened=false
local openedAt=0
local changed=Instance.new("BindableEvent")
View.Changed=changed.Event

local function make(class,parent,properties)
 local object=Instance.new(class)
 for key,value in pairs(properties or {}) do object[key]=value end
 object.Parent=parent
 return object
end
local function label(parent,name,text,position,size,color,font)
 local item=make("TextLabel",parent,{Name=name,Text=text,Position=position,Size=size,BackgroundTransparency=1,
  TextScaled=true,TextWrapped=true,Font=font or TITLE_FONT,TextColor3=color or Color3.new(1,1,1)})
 make("UIStroke",item,{Color=INK,Thickness=2})
 return item
end

local function inLobby()
 local value=player:GetAttribute("InLobby")
 return value==true or (value==nil and workspace:GetAttribute("MatchPhase")=="Lobby")
end
local function reducedMotion() return player:GetAttribute("ReducedMotion")==true end

function View.Available()
 return videoId~=nil and not failed
end
function View.IsOpen()
 return opened
end

-- 影片無法載入（未審核、已刪除、ID 錯誤）時改用字卡，並收起觀看按鈕。
local function markFailed(reason)
 if failed then return end
 failed=true
 warn("[LobbyTrailer] 預告片影片無法播放，改顯示字卡："..tostring(reason))
 if screenVideo then screenVideo.Playing=false; screenVideo.Visible=false end
 if opened then View.Close() end
 refreshScreen()
 changed:Fire()
end
local function watchLoad(video)
 local deadline=os.clock()+LOAD_TIMEOUT
 task.spawn(function()
  while video.Parent and not video.IsLoaded and os.clock()<deadline do task.wait(0.5) end
  if video.Parent and not video.IsLoaded then markFailed("載入逾時") end
 end)
end

local function stepSlides()
 if not slideFrame then return end
 local index,fade=Rules.SlideAt(#slides,os.clock(),SLIDE_SECONDS,reducedMotion() and 0 or 0.6)
 local slide=index and slides[index]
 if not slide then return end
 slideHeading.Text=slide.heading
 slideDetail.Text=slide.detail or (slide.title and "" or "帝國鍛造坊 · 戰役預告")
 slideHeading.TextTransparency,slideDetail.TextTransparency=fade,fade
 slideHeading.UIStroke.Transparency,slideDetail.UIStroke.Transparency=fade,fade
end

-- 大螢幕只在玩家位於大廳且沒開全螢幕時播放；不在大廳時停止影片與字卡更新。
function refreshScreen()
 if not screenGui then return end
 local active=inLobby()
 screenGui.Enabled=active
 local video=View.Available() and screenVideo~=nil
 if screenVideo then
  screenVideo.Visible=video
  screenVideo.Playing=active and video and not opened
 end
 slideFrame.Visible=not video
 local wantSlides=active and not video
 if wantSlides and not slideConnection then
  slideConnection=RunService.Heartbeat:Connect(stepSlides)
  stepSlides()
 elseif not wantSlides and slideConnection then
  slideConnection:Disconnect(); slideConnection=nil
 end
end

local function buildScreen(part)
 if screenGui then screenGui:Destroy() end
 screenGui=make("SurfaceGui",player:WaitForChild("PlayerGui"),{Name="AOE2_LobbyTrailerScreen",Adornee=part,Face=Enum.NormalId.Front,
  SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud,PixelsPerStud=16,LightInfluence=0,ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
 make("Frame",screenGui,{Name="Black",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0})
 slideFrame=make("Frame",screenGui,{Name="Slides",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(16,22,44),BorderSizePixel=0})
 make("UIGradient",slideFrame,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(150,70,40),Color3.fromRGB(14,12,22))})
 slideHeading=label(slideFrame,"Heading","",UDim2.fromScale(0.06,0.28),UDim2.fromScale(0.88,0.26))
 slideHeading.UIStroke.Thickness=4
 slideDetail=label(slideFrame,"Detail","",UDim2.fromScale(0.15,0.6),UDim2.fromScale(0.7,0.12),GOLD,BODY_FONT)
 screenVideo=nil
 if videoId and not failed then
  screenVideo=make("VideoFrame",screenGui,{Name="Video",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
   Video=videoId,Looped=true,Volume=0,ZIndex=2})
  watchLoad(screenVideo)
 end
 local tag=make("Frame",screenGui,{Name="Tag",Position=UDim2.fromOffset(18,16),Size=UDim2.fromOffset(190,40),BackgroundColor3=Color3.fromRGB(226,64,58),ZIndex=3})
 make("UICorner",tag,{CornerRadius=UDim.new(0,10)})
 label(tag,"Text","▶ 戰役預告片",UDim2.fromScale(0.06,0.1),UDim2.fromScale(0.88,0.8)).ZIndex=3
 refreshScreen()
end

local function watchFolder(folder)
 if folder.Name~="AOE2_LobbyWorld" or not folder:IsA("Folder") then return end
 local function consider(item)
  if item.Name=="TrailerScreen" and item:IsA("BasePart") then buildScreen(item) end
 end
 for _,item in ipairs(folder:GetChildren()) do consider(item) end
 folder.ChildAdded:Connect(consider)
end

local function volume()
 if player:GetAttribute("SoundEnabled")==false then return 0 end
 local value=player:GetAttribute("SoundVolume")
 return type(value)=="number" and value==value and math.clamp(value,0,1) or 1
end

local function layoutTheater()
 if not theater then return end
 local size=theater.AbsoluteSize
 local inset=GuiService:GetGuiInset()
 local scale=math.clamp(math.min(size.X/1280,size.Y/620),0.6,1.1)
 theaterScale.Scale=scale
 -- 上方留給 Roblox 按鈕與關閉鍵，下方留給進度列；影片放在剩下的空間中央。
 local top,bottom=inset.Y+56*scale,30*scale
 local width,height=Rules.Fit(size.X-24,size.Y-top-bottom,16/9)
 theaterStage.Size=UDim2.fromOffset(width,height)
 theaterStage.Position=UDim2.fromOffset((size.X-width)/2,top+(size.Y-top-bottom-height)/2)
end

local function buildTheater()
 theater=make("ScreenGui",player:WaitForChild("PlayerGui"),{Name="AOE2_LobbyTrailer",IgnoreGuiInset=true,ResetOnSpawn=false,
  DisplayOrder=10,Enabled=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
 -- 全黑底板吸收所有點擊，不會穿透到廣場或大廳介面。
 make("TextButton",theater,{Name="Backdrop",Text="",AutoButtonColor=false,Size=UDim2.fromScale(1,1),
  BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0,BorderSizePixel=0,Selectable=false})
 theaterStage=make("Frame",theater,{Name="Stage",BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0})
 theaterVideo=make("VideoFrame",theaterStage,{Name="Video",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Looped=false})
 local track=make("Frame",theaterStage,{Name="Progress",AnchorPoint=Vector2.new(0,0),Position=UDim2.new(0,0,1,8),
  Size=UDim2.new(1,0,0,5),BackgroundColor3=Color3.fromRGB(60,64,80),BorderSizePixel=0})
 make("UICorner",track,{CornerRadius=UDim.new(1,0)})
 theaterProgress=make("Frame",track,{Name="Fill",Size=UDim2.fromScale(0,1),BackgroundColor3=GOLD,BorderSizePixel=0})
 make("UICorner",theaterProgress,{CornerRadius=UDim.new(1,0)})
 local controls=make("Frame",theater,{Name="Controls",Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
 theaterScale=make("UIScale",controls)
 local inset=GuiService:GetGuiInset()
 make("UIPadding",controls,{PaddingTop=UDim.new(0,inset.Y+8),PaddingLeft=UDim.new(0,16),PaddingRight=UDim.new(0,16)})
 local title=label(controls,"Title","戰役預告片",UDim2.fromOffset(0,0),UDim2.fromOffset(260,40))
 title.TextXAlignment=Enum.TextXAlignment.Left
 local close=make("TextButton",controls,{Name="CloseTrailer",Text="",AutoButtonColor=true,AnchorPoint=Vector2.new(1,0),
  Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(132,42),BackgroundColor3=Color3.fromRGB(240,78,78),BorderSizePixel=0})
 make("UICorner",close,{CornerRadius=UDim.new(0,10)})
 make("UIStroke",close,{Color=INK,Thickness=2.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 label(close,"Label","✕ 關閉",UDim2.fromScale(0.1,0.15),UDim2.fromScale(0.8,0.7))
 close.Activated:Connect(function() View.Close() end)
 theaterVideo.Ended:Connect(function() if opened then View.Close() end end)
 theater:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutTheater)
 -- 手把 B 鍵也能關閉；Esc 保留給 Roblox 選單。
 UIS.InputBegan:Connect(function(input)
  if opened and input.KeyCode==Enum.KeyCode.ButtonB then View.Close() end
 end)
end

function View.Open()
 if opened or not View.Available() or not inLobby() then return false end
 if not theater then buildTheater() end
 opened,openedAt=true,os.clock()
 theaterVideo.Video=videoId
 theaterVideo.Volume=volume()
 theaterVideo.TimePosition=0
 theater.Enabled=true
 layoutTheater()
 theaterVideo.Playing=true
 Music:Hush(true)
 refreshScreen()
 if progressConnection then progressConnection:Disconnect() end
 progressConnection=RunService.Heartbeat:Connect(function()
  theaterProgress.Size=UDim2.fromScale(Rules.Progress(theaterVideo.TimePosition,theaterVideo.TimeLength),1)
  -- 開啟後一直沒載入就視為無法播放，避免玩家盯著黑畫面。
  if not theaterVideo.IsLoaded and os.clock()-openedAt>LOAD_TIMEOUT then markFailed("全螢幕載入逾時") end
 end)
 changed:Fire()
 return true
end

function View.Close()
 if not opened then return end
 opened=false
 if theaterVideo then theaterVideo.Playing=false end
 if theater then theater.Enabled=false end
 if progressConnection then progressConnection:Disconnect(); progressConnection=nil end
 Music:Hush(false)
 refreshScreen()
 changed:Fire()
end

function View.Start()
 if started then return end
 started=true
 workspace.ChildAdded:Connect(watchFolder)
 local existing=workspace:FindFirstChild("AOE2_LobbyWorld")
 if existing then watchFolder(existing) end
 -- 離開大廳（開局）時關閉全螢幕並停止大螢幕。
 local function lobbyChanged()
  if opened and not inLobby() then View.Close() end
  refreshScreen()
 end
 player:GetAttributeChangedSignal("InLobby"):Connect(lobbyChanged)
 workspace:GetAttributeChangedSignal("MatchPhase"):Connect(lobbyChanged)
 for _,name in ipairs({"SoundEnabled","SoundVolume"}) do
  player:GetAttributeChangedSignal(name):Connect(function()
   if theaterVideo then theaterVideo.Volume=volume() end
  end)
 end
end

return View
