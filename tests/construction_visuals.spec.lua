local Rules=require("../src/ReplicatedStorage/Shared/ConstructionVisualRules")
local Feedback=require("../src/ReplicatedStorage/Shared/FeedbackRules")
local count=0
local function expect(value,message) count+=1; assert(value,message) end
for _,value in ipairs({false,".5",0/0,math.huge,-math.huge}) do
 expect(Rules.Progress(value)==0,"invalid progress must stay at the foundation")
 expect(Rules.Stage(value)==0,"invalid progress revealed a later construction stage")
end
expect(Rules.Progress(-10)==0 and Rules.Progress(9)==1,"progress is not bounded")
expect(Rules.Stage(0)==0 and Rules.Stage(.079)==0,"fresh site skipped ground work")
expect(Rules.Stage(.08)==1 and Rules.Stage(.299)==1,"scaffold stage boundary drifted")
expect(Rules.Stage(.3)==2 and Rules.Stage(.699)==2,"wall stage boundary drifted")
expect(Rules.Stage(.7)==3 and Rules.Stage(.999)==3 and Rules.Stage(1)==4,"roof/completion boundary drifted")
local previous=-1
for index=0,100 do
 local stage=Rules.Stage(index/100)
 expect(stage>=previous,"construction stage moved backwards under increasing progress")
 previous=stage
end
for _,height in ipairs({0,.25,.5,.75,1}) do
 expect(Rules.RevealAt(0,height)==0,"foundation did not remain visible")
 expect(Rules.RevealAt(1,height)<Rules.RevealAt(2,height),"trim revealed before walls")
 expect(Rules.RevealAt(2,height)<Rules.RevealAt(3,height),"roof revealed before trim")
 expect(Rules.RevealAt(3,height)<1,"roof stayed invisible at completion")
end
for stage=1,3 do
 expect(Rules.RevealAt(stage,0)<Rules.RevealAt(stage,1),"height reveal must rise from bottom to top")
 expect(Rules.RevealAt(stage,math.huge)==Rules.RevealAt(stage,0),"invalid height corrupted reveal time")
end
expect(Rules.MaxVisibleSites<=24 and Rules.MaxCompletionEffects<=6 and Rules.UpdateInterval>=.25,"cosmetic budgets exceeded")
expect(Feedback.CameraGain(0)==1 and Feedback.CameraGain(100)==1,"nearby camera audio was attenuated")
expect(Feedback.CameraGain(200)>Feedback.CameraGain(350) and Feedback.CameraGain(350)>Feedback.CameraGain(Feedback.MaxDistance),"camera gain does not fall with distance")
expect(Feedback.CameraGain(Feedback.MaxDistance)>0 and Feedback.CameraGain(Feedback.MaxDistance+.01)==0,"audible distance boundary drifted")
for _,distance in ipairs({false,"200",-1,math.huge,0/0}) do expect(Feedback.CameraGain(distance)==0,"invalid camera distance produced sound") end
print(string.format("PASS: %d construction reveal / cosmetic budget / camera mix checks (not Studio)",count))
