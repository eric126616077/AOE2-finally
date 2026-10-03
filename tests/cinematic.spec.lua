local Rules=require("../src/ReplicatedStorage/Shared/CinematicRules")
local count=0
local function expect(value,message) count+=1; assert(value,message) end
local function near(a,b) return math.abs(a-b)<1e-6 end
-- 時間軸：段落首尾相接，總長等於各段相加，伺服器動作的時間點都落在影片內。
local sum,ids=0,{}
for index,stage in ipairs(Rules.Stages) do
 expect(type(stage.id)=="string" and not ids[stage.id],"stage id missing or duplicated")
 ids[stage.id]=true
 expect(stage.seconds>0,"stage has no duration")
 expect(near(Rules.StageStart(stage.id),sum),"stage start is not the sum of earlier stages")
 local found,t,at=Rules.StageAt(sum)
 expect(found==stage and near(t,0) and at==index,"stage lookup misses the first frame of "..stage.id)
 found=Rules.StageAt(sum+stage.seconds-1e-3)
 expect(found==stage,"stage lookup misses the last frame of "..stage.id)
 sum+=stage.seconds
end
expect(near(Rules.Total,sum),"total length is wrong")
for _,id in ipairs({"intro","charge","siege","collapse","finale"}) do expect(ids[id],"missing stage "..id) end
expect(Rules.StageStart("siege")<Rules.StageStart("collapse")-Rules.CollapseLead,"fort drops to 1 HP before the siege starts")
expect(Rules.StageStart("collapse")-Rules.CollapseLead>Rules.StageStart("siege")+3,"rams get no time to reach the fort")
expect(Rules.Stages[1].id=="intro" and Rules.Stages[#Rules.Stages].id=="finale","trailer does not open on the title and end on the finale")
expect(Rules.FortFloorFraction>0 and Rules.FortFloorFraction<Rules.FortHPFraction,"fort floor is not below its siege HP")
-- 誘餌觸發電腦進攻後到衝鋒開始（含 1 秒開場延遲與 3 秒排兵餘裕）必須早於下一波。
expect(Rules.StageStart("charge")+1+3<Rules.AIWaveSeconds,"the next AI wave arrives before the charge")
-- 開始前沒有段落；結束後固定在最後一段的結尾，不會繞回開頭。
for _,bad in ipairs({-0.01,-5,0/0,math.huge,-math.huge,"x",nil}) do
 expect(Rules.StageAt(bad)==nil,"invalid or negative time returned a stage")
end
local last,lastT=Rules.StageAt(Rules.Total+30)
expect(last==Rules.Stages[#Rules.Stages] and near(lastT,last.seconds),"time past the end does not hold the last frame")
-- 對峙段不能自動開打：前排間距要超過自動索敵半徑（GameConfig 為 72）。
expect(Rules.FrontGap>72,"front lines start inside the acquisition radius")
-- 緩入緩出：端點固定、單調、對稱，輸入超出 [0,1] 時夾住。
expect(near(Rules.Ease(0),0) and near(Rules.Ease(1),1) and near(Rules.Ease(.5),.5),"ease endpoints are wrong")
local previous=0
for step=0,100 do
 local value=Rules.Ease(step/100)
 expect(value>=previous-1e-9,"ease is not monotonic")
 expect(near(value+Rules.Ease(1-step/100),1),"ease is not symmetric")
 previous=value
end
expect(Rules.Ease(.05)<.05 and Rules.Ease(.95)>.95,"ease does not start and stop slowly")
expect(near(Rules.Ease(-2),0) and near(Rules.Ease(3),1) and near(Rules.Ease(0/0),0),"ease input is not clamped")
-- 淡入淡出。
expect(near(Rules.FadeAlpha(0,4,1,1),0) and near(Rules.FadeAlpha(.5,4,1,1),.5) and near(Rules.FadeAlpha(2,4,1,1),1),"fade in is wrong")
expect(near(Rules.FadeAlpha(3.5,4,1,1),.5) and near(Rules.FadeAlpha(4,4,1,1),0),"fade out is wrong")
expect(Rules.FadeAlpha(-.1,4,1,1)==0 and Rules.FadeAlpha(4.1,4,1,1)==0,"visible outside its window")
expect(near(Rules.FadeAlpha(2,4,0,0),1),"zero-length fades hide the text")
expect(Rules.FadeAlpha(0/0,4,1,1)==0 and Rules.FadeAlpha(1,0,1,1)==0 and Rules.FadeAlpha(1,"x",1,1)==0,"invalid fade input is visible")
-- 黑邊：16:9 的 1920×1080 換成 2.39:1 是上下各 138.33 像素；已經更寬的畫面不加黑邊。
expect(math.abs(Rules.Letterbox(1920,1080,2.39)-138.33)<.01,"letterbox height is wrong")
expect(Rules.Letterbox(2400,800,2.39)==0,"ultra-wide screen got bars")
expect(Rules.Letterbox(0,1080,2.39)==0 and Rules.Letterbox(1920,1080,0)==0 and Rules.Letterbox(0/0,1,1)==0,"invalid viewport got bars")
-- 平滑係數與幀率無關：兩個半幀等於一整幀；長卡頓不會一次跳過頭。
local half=Rules.Damp(1/120,3)
expect(near(1-(1-half)^2,Rules.Damp(1/60,3)),"damping depends on frame rate")
expect(Rules.Damp(10,3)<1 and Rules.Damp(0,3)==0 and Rules.Damp(-1,3)==0 and Rules.Damp(0/0,3)==0,"damping input is not guarded")
-- 震動：累加上限 1、隨時間歸零、振幅隨平方增加；越遠越小，超出半徑為 0。
expect(near(Rules.AddTrauma(.8,.5),1) and near(Rules.AddTrauma(.2,.3),.5),"trauma does not accumulate up to 1")
expect(near(Rules.AddTrauma(.4,-1),.4) and near(Rules.AddTrauma(0/0,.2),.2) and near(Rules.AddTrauma(.4,0/0),.4),"invalid trauma input changed the value")
expect(near(Rules.DecayTrauma(.5,.25,1),.25) and Rules.DecayTrauma(.1,1,1)==0,"trauma does not decay to zero")
expect(near(Rules.DecayTrauma(.5,0/0,1),.5) and Rules.DecayTrauma(0/0,.1,1)==0,"invalid decay input")
expect(near(Rules.ShakeAmplitude(.5,2),.5) and near(Rules.ShakeAmplitude(1,2),2) and Rules.ShakeAmplitude(0,2)==0,"shake is not trauma squared")
expect(Rules.ShakeAmplitude(2,2)==2 and Rules.ShakeAmplitude(.5,-1)==0,"shake input is not clamped")
expect(near(Rules.ImpactTrauma(0,80,.45),.45) and near(Rules.ImpactTrauma(40,80,.45),.225),"impact trauma is not linear in distance")
expect(Rules.ImpactTrauma(80,80,.45)==0 and Rules.ImpactTrauma(120,80,.45)==0,"impact beyond its radius shook the camera")
expect(Rules.ImpactTrauma(-1,80,.45)==0 and Rules.ImpactTrauma(0/0,80,.45)==0 and Rules.ImpactTrauma(10,0,.45)==0,"invalid impact input")
print(("cinematic.spec: %d checks passed"):format(count))
