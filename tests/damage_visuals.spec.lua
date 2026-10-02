local Rules=require("../src/ReplicatedStorage/Shared/DamageVisualRules")
local count=0
local function expect(value,message) count+=1; assert(value,message) end
for _,value in ipairs({false,"50",0/0,math.huge,-math.huge}) do
 expect(Rules.Stage(value,100)==0 and Rules.Stage(50,value)==0,"invalid health produced a damage state")
end
expect(Rules.Stage(10,0)==0 and Rules.Stage(10,-5)==0,"non-positive maximum health produced a damage state")
expect(Rules.Stage(100,100)==0 and Rules.Stage(51,100)==0,"healthy building looks damaged")
expect(Rules.Stage(50,100)==1 and Rules.Stage(34,100)==1,"half health boundary drifted")
expect(Rules.Stage(100,300)==2 and Rules.Stage(1,100)==2 and Rules.Stage(0,100)==2,"one third health boundary drifted")
expect(Rules.Stage(250,100)==0 and Rules.Stage(-5,100)==2,"health ratio is not bounded")
local previous=0
for hp=100,0,-1 do
 local stage=Rules.Stage(hp,100,previous)
 expect(stage>=previous,"damage state improved while health fell")
 previous=stage
end
expect(previous==2,"destroyed building did not reach the ruined state")
for hp=0,100 do
 local stage=Rules.Stage(hp,100,previous)
 expect(stage<=previous,"damage state worsened while health rose")
 previous=stage
end
expect(previous==0,"fully repaired building still looks damaged")
expect(Rules.Stage(52,100,1)==1 and Rules.Stage(52,100,0)==0 and Rules.Stage(55,100,1)==0,"half health repair margin drifted")
expect(Rules.Stage(36,100,2)==2 and Rules.Stage(36,100,1)==1 and Rules.Stage(38,100,2)==1,"one third repair margin drifted")
expect(Rules.Stage(52,100,2)==1 and Rules.Stage(60,100,2)==0,"large repair kept the ruined state")
local below,total=0,0
for x=-6,6 do for y=0,8 do for z=-6,6 do
 local rank=Rules.Rank(x*.75,y*.5,z*.75)
 expect(rank>=0 and rank<1,"rank left [0,1)")
 expect(rank==Rules.Rank(x*.75,y*.5,z*.75),"rank is not stable")
 total+=1
 if rank<.5 then below+=1 end
end end end
expect(below/total>.35 and below/total<.65,"rank is too lopsided to spread damage")
for _,value in ipairs({0/0,math.huge,false}) do expect(Rules.Rank(value,1,1)==0,"invalid position corrupted rank") end
for parts=0,40 do
 for _,constructionStage in ipairs({0,1}) do
  expect(Rules.HideCount(1,constructionStage,parts)==0 and Rules.HideCount(2,constructionStage,parts)==0,"foundation or wall broke away")
 end
 for _,constructionStage in ipairs({2,3}) do
  local half,ruined=Rules.HideCount(1,constructionStage,parts),Rules.HideCount(2,constructionStage,parts)
  expect(Rules.HideCount(0,constructionStage,parts)==0,"intact building lost parts")
  expect(half<=ruined and ruined<=parts,"ruined state shows fewer holes than the damaged state")
  if parts>0 then expect(half>=1,"damaged state changed no part") end
  if parts>1 then expect(ruined>half,"ruined state looks the same as the damaged state") end
  if constructionStage==3 and parts>2 then expect(ruined<parts,"ruined roof vanished completely") end
 end
end
expect(Rules.HideCount(1,3,0/0)==0 and Rules.HideCount(1,3,-3)==0,"invalid part count hid parts")
expect(Rules.HideCount(1,3,10)==3 and Rules.HideCount(2,3,10)==6,"roof share drifted")
for _,rank in ipairs({0,.5,1}) do
 expect(Rules.Soot(0,rank)==0,"intact building is sooty")
 expect(Rules.Soot(1,rank)>0 and Rules.Soot(1,rank)<Rules.Soot(2,rank) and Rules.Soot(2,rank)<=.6,"soot does not deepen with damage")
end
expect(Rules.Soot(2,0/0)==Rules.Soot(2,0),"invalid rank corrupted soot")
expect(Rules.Fires(0,false)==0 and Rules.Fires(1,false)==1 and Rules.Fires(2,false)==3,"fire count drifted")
expect(Rules.Fires(1,true)==0 and Rules.Fires(2,true)==0,"wall line caught fire")
expect(Rules.Rubble(0,false)==0 and Rules.Rubble(1,false)<Rules.Rubble(2,false),"rubble does not grow with damage")
expect(Rules.Rubble(1,true)>=1 and Rules.Rubble(2,true)<Rules.Rubble(1,false),"wall line rubble budget drifted")
expect(Rules.MaxOverlays<=40 and Rules.MaxFires<=24,"cosmetic damage budgets exceeded")
print(string.format("PASS: %d building damage state / break share / effect budget checks (not Studio)",count))
