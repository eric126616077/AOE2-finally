-- Studio CLIENT Command Bar. Observes real UI clicks; never sends remotes.
task.spawn(function()
 local player=game.Players.LocalPlayer
 local screen=player.PlayerGui.AOE2_MainGUI
 local base
 for _,model in ipairs(workspace.Buildings:GetChildren()) do
  if model:GetAttribute("OwnerId")==player.UserId and model:GetAttribute("BuildingType")=="TownCenter" then base=model; break end
 end
 assert(base and game:GetService("UserInputService").TouchEnabled,"手機新測試局需要主城")
 screen.RTSSelectionProbe:Invoke({base}); screen.RTSHUDProbe:Invoke("tab","train")
 local deadline=os.clock()+120
 local checks=0
 local function waitFor(callback)
  repeat task.wait(.05); assert(os.clock()<deadline,"[UI_CLICK FAIL] 等待實際UI操作逾時") until callback()
 end
 local function check(ok,message) assert(ok,"[UI_CLICK FAIL] "..message); checks+=1; print("[UI_CLICK PASS] "..message) end
 local food,population=player:GetAttribute("food"),player:GetAttribute("Population")
 print("[UI_CLICK OBSERVE] 點村民訓練，再點佇列頭像取消；之後點科技與織布機。")
 waitFor(function()return base:GetAttribute("Training")~=nil end)
 task.wait(.2)
 local context=screen:FindFirstChild("TargetContext",true)
 check(context.Visible and context.Text:find(base:GetAttribute("Training"),1,true) and context.Text:find("秒",1,true) and context.Text:find("%",1,true),"實際手機指令區顯示訓練名稱、秒數與百分比")
 local slot=screen:FindFirstChild("QueueSlot_1",true)
 check(slot and slot.AbsoluteSize.X>=44 and slot.AbsoluteSize.Y>=44 and slot:FindFirstChild("QueueProgress"),"訓練頭像維持44px並顯示進度條")
 waitFor(function()return base:GetAttribute("QueueCount")==0 end)
 waitFor(function()return player:GetAttribute("food")==food end)
 check(player:GetAttribute("Population")==population,"實際點佇列取消退還50食物、未產生單位")
 waitFor(function()return base:GetAttribute("Research")~=nil end)
 task.wait(.2)
 check(context.Visible and context.Text:find(base:GetAttribute("Research"),1,true) and context.Text:find("秒",1,true) and context.Text:find("%",1,true),"實際手機指令區顯示研究名稱、秒數與百分比")
 print("[UI_CLICK COMPLETE] "..checks.." checks; 以滑鼠操作Studio觸控模擬UI，未驗真實手指")
end)
