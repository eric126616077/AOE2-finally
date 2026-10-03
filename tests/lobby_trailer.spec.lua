local Rules=require("../src/ReplicatedStorage/Shared/LobbyTrailerRules")
local Cinematic=require("../src/ReplicatedStorage/Shared/CinematicRules")
local count=0
local function expect(value,message) count+=1; assert(value,message) end
local function near(a,b) return math.abs(a-b)<1e-6 end

-- 影片 ID：數字、數字字串與 rbxassetid:// 都轉成同一個 ContentId；0 與其他值視為尚未上傳。
expect(Rules.AssetId(123456789)=="rbxassetid://123456789","number id")
expect(Rules.AssetId("123456789")=="rbxassetid://123456789","digit string id")
expect(Rules.AssetId(" rbxassetid://42 ")=="rbxassetid://42","rbxassetid string id")
expect(Rules.AssetId(9007199254740991)=="rbxassetid://9007199254740991","large id keeps every digit")
for _,bad in ipairs({0,-5,1.5,0/0,math.huge,"","abc","12a","rbxassetid://","http://x/1","rbxassetid://-3",{},true,"12345678901234567"}) do
 expect(Rules.AssetId(bad)==nil,"invalid id accepted: "..tostring(bad))
end
expect(Rules.AssetId(nil)==nil,"nil id accepted")

-- 字卡：照分鏡順序，開頭是片頭標題、結尾是遊戲名與標語，沒有重複或空白字卡。
local slides=Rules.Slides(Cinematic.Stages)
expect(#slides>=5,"too few fallback slides")
expect(slides[1].heading==Cinematic.Stages[1].title and slides[1].title,"first slide is not the opening title")
local last=slides[#slides]
expect(last.heading=="帝國鍛造坊" and last.detail=="採集・建造・征服","last slide is not the finale card")
local seen={}
for _,slide in ipairs(slides) do
 expect(type(slide.heading)=="string" and slide.heading~="" and not seen[slide.heading],"empty or duplicated slide")
 seen[slide.heading]=true
end
expect(#Rules.Slides(nil)==0 and #Rules.Slides({{id="x"},{caption=""}})==0,"slides from invalid stages")
expect(#Rules.Slides({{caption="甲"},{title="甲"}})==1,"duplicate heading kept")

-- 輪播：每 seconds 秒換一張、循環；頭尾淡入淡出，中段完全顯示；無效輸入不顯示。
local index,fade=Rules.SlideAt(3,0,4,0.5)
expect(index==1 and near(fade,1),"slide does not fade in from transparent")
index,fade=Rules.SlideAt(3,2,4,0.5)
expect(index==1 and near(fade,0),"slide is not fully visible mid-way")
index,fade=Rules.SlideAt(3,4.25,4,0.5)
expect(index==2 and near(fade,0.5),"second slide fade-in is wrong")
index=Rules.SlideAt(3,12.1,4,0.5)
expect(index==1,"slides do not loop")
index,fade=Rules.SlideAt(3,0.1,4,0)
expect(index==1 and fade==0,"reduced motion still fades")
index,fade=Rules.SlideAt(3,1e9+0.3,4,0.5)
expect(index>=1 and index<=3 and fade>=0 and fade<=1,"large clock value breaks the slideshow")
for _,bad in ipairs({{0,1,4},{3,0/0,4},{3,1,0},{3,1,-2},{"x",1,4}}) do
 local i,f=Rules.SlideAt(bad[1],bad[2],bad[3],0.5)
 expect(i==nil and f==1,"invalid slideshow input shows a slide")
end

-- 全螢幕：16:9 放進可用範圍，寬螢幕左右留黑，窄螢幕上下留黑。
local w,h=Rules.Fit(1920,1080)
expect(near(w,1920) and near(h,1080),"exact 16:9 does not fill")
w,h=Rules.Fit(2560,1000)
expect(near(h,1000) and near(w,1000*16/9),"wide screen is not pillarboxed")
w,h=Rules.Fit(800,1200)
expect(near(w,800) and near(h,450),"tall screen is not letterboxed")
w,h=Rules.Fit(-1,100); expect(w==0 and h==0,"negative size")
w,h=Rules.Fit(0/0,100); expect(w==0 and h==0,"NaN size")
w,h=Rules.Fit(400,300,0/0); expect(near(w,400) and near(h,225),"bad aspect does not fall back to 16:9")

-- 進度：夾在 0–1，長度未知時為 0。
expect(near(Rules.Progress(38.5,77),0.5),"progress midpoint")
expect(Rules.Progress(90,77)==1 and Rules.Progress(-3,77)==0,"progress not clamped")
expect(Rules.Progress(10,0)==0 and Rules.Progress(0/0,77)==0 and Rules.Progress(10,math.huge)==0,"progress with unknown length")

print(("lobby_trailer.spec: %d checks passed"):format(count))
