-- Explicit read-only Studio CLIENT checks after a real defeat/end. No remotes,
-- attribute writes, UI callbacks, camera changes, or GUI module cache assumptions.
local Tests={}
local counters={"buildingsCompleted","villagersTrained","militaryTrained","damageDealt","unitsKilled","buildingsKilled","unitsLost","buildingsLost"}
local function expectedNumber(value)
 if value>=100000000 then return string.format("%.2f 億",value/100000000) end
 if value>=10000 then return string.format("%.1f 萬",value/10000) end
 return value%1==0 and string.format("%.0f",value) or string.format("%.1f",value)
end
local function expectedDuration(value)
 local seconds=math.floor(value)
 return string.format("存活 %d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end
local function client()
 local RunService=game:GetService("RunService")
 assert(RunService:IsStudio() and RunService:IsClient(),"僅限 Studio Play 客戶端")
 local player=game.Players.LocalPlayer
 local screen=player.PlayerGui:FindFirstChild("AOE2_MainGUI")
 assert(screen,"正式 PlayerGui 尚未初始化")
 return player,screen
end
local function waitFor(predicate,seconds,message)
 local deadline=os.clock()+seconds
 repeat
  if predicate() then return end
  assert(os.clock()<deadline,"[MATCH_REPORT_TEST FAIL] "..message)
  task.wait(0.05)
 until false
end
local function nodes(screen)
 local overlay=assert(screen:FindFirstChild("ResultOverlay",true),"缺少正式結果視窗")
 local body=assert(overlay:FindFirstChild("MatchResult"),"缺少結果內容")
 return overlay,body,assert(body:FindFirstChild("ReportContent"),"缺少覆盤捲動區域")
end
local function read(player,allowPending)
 local raw=player:GetAttribute("MatchReportJSON")
 if type(raw)~="string" or raw=="" then return nil end
 local ok,value=pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
 return ok and type(value)=="table" and (value.finished==true or (allowPending and value.finished==false and value.outcome=="pending")) and value or nil
end
function Tests.Run()
 local player,screen=client()
 local checks=0
 local function check(ok,message)
  assert(ok,"[MATCH_REPORT_TEST FAIL] "..message); checks+=1
  print("[MATCH_REPORT_TEST PASS] "..message)
 end
 check(workspace:GetAttribute("MatchPhase")=="Ended" or player:GetAttribute("Defeated")==true,"先由正常戰敗／結束取得正式報告")
 waitFor(function() return read(player)~=nil end,10,"伺服器 finished JSON 未送達")
 local report=read(player)
 check(report.version==1 and (report.outcome=="win" or report.outcome=="loss" or report.outcome=="draw"),"實際複製報告具有版本與已定勝負")
 local overlay,body,scroll=nodes(screen)
 local stats=assert(scroll:FindFirstChild("ReportStats"),"缺少正式覆盤欄位")
 local status=assert(scroll:FindFirstChild("ReportStatus"),"缺少載入狀態")
 waitFor(function() return stats.Visible and not status.Visible end,5,"正式 UI 沒有消化非同步報告")
 check(overlay.Visible and stats.Visible and not status.Visible,"正式結果視窗顯示已送達的資料")
 local function displayed(labelName,value)
  local label=stats:FindFirstChild(labelName,true)
  check(label and label:IsA("TextLabel") and label:GetAttribute("ReportValue")==value and label.Text==expectedNumber(value),"正式 JSON 對應到實際數值與精確文字："..labelName)
 end
 for _,key in ipairs({"food","wood","gold","stone"}) do
  displayed("ReportDelivered_"..key,report.resourcesDelivered[key])
  displayed("ReportSpent_"..key,report.resourcesSpent[key])
 end
 for _,key in ipairs(counters) do displayed("ReportValue_"..key,report[key]) end
 local heading=body:FindFirstChild("ReportHeading")
 local summary=body:FindFirstChild("ReportSummary")
 check(heading and heading.Text:find(report.outcomeLabel,1,true)~=nil,"勝負呈現在實際結果標題")
 check(summary and summary.Text==expectedDuration(report.survivalSeconds),"存活時長精確文字與正式報告秒數一致")
 local watch=body:FindFirstChild("WatchButton")
 local restart=body:FindFirstChild("RestartMatchButton")
 check(watch and restart and watch.AbsoluteSize.X>=43.9 and watch.AbsoluteSize.Y>=43.9 and restart.AbsoluteSize.X>=43.9 and restart.AbsoluteSize.Y>=43.9,"觀戰／重開使用至少 44 個畫面像素的點擊區")
 check(scroll.ScrollingDirection==Enum.ScrollingDirection.Y and scroll.AbsoluteSize.Y>0 and scroll.AbsoluteCanvasSize.Y>scroll.AbsoluteSize.Y,"實際數據內容可垂直捲動")
 check(scroll.AbsolutePosition.Y+scroll.AbsoluteSize.Y<=watch.AbsolutePosition.Y-8,"捲動數據與固定底部按鈕不重疊")
 check(watch.AbsolutePosition.Y+watch.AbsoluteSize.Y<=body.AbsolutePosition.Y+body.AbsoluteSize.Y-8,"固定按鈕留在結果容器內")
 local canvas=screen:FindFirstChild("Canvas")
 check(body.AbsolutePosition.X>=canvas.AbsolutePosition.X+7 and body.AbsolutePosition.Y>=canvas.AbsolutePosition.Y+7
  and body.AbsolutePosition.X+body.AbsoluteSize.X<=canvas.AbsolutePosition.X+canvas.AbsoluteSize.X-7
  and body.AbsolutePosition.Y+body.AbsoluteSize.Y<=canvas.AbsolutePosition.Y+canvas.AbsoluteSize.Y-7,"結果容器位於目前畫面安全範圍內")
 local probe=screen:FindFirstChild("RTSInputProbe")
 local raw=body.AbsolutePosition+body.AbsoluteSize/2+game:GetService("GuiService"):GetGuiInset()
 local input=probe and probe:Invoke(raw)
 check(input and input.modal and input.blocked and player:GetAttribute("RTSModalOpen")==true,"正式覆盤視窗攔截世界指令")
 print(string.format("[MATCH_REPORT_TEST COMPLETE] %d checks; 唯讀正式屬性與 PlayerGui",checks))
 return checks
end
-- Run after natural elimination in a team match. This does not cause elimination
-- or invoke a GUI callback; actual PlayerGui must consume the replicated report.
function Tests.CheckPending()
 local player,screen=client()
 assert(workspace:GetAttribute("MatchPhase")=="Playing" and player:GetAttribute("Defeated")==true and player:GetAttribute("Forfeited")~=true,"請先讓自己的勢力自然淘汰，並保留存活盟友")
 waitFor(function() local value=read(player,true); return value and value.finished==false end,10,"等待隊伍結算的正式報告未送達")
 local report=read(player,true)
 assert(report.version==1 and report.outcome=="pending" and report.outcomeLabel=="等待對局結果","pending 正式契約不符")
 local overlay,body,scroll=nodes(screen)
 local stats,status=scroll:FindFirstChild("ReportStats"),scroll:FindFirstChild("ReportStatus")
 waitFor(function() return stats and stats.Visible and status and status.Visible and status.Text=="個人行動與存活紀錄已停止，等待隊伍結果。" end,5,"pending 正式 UI 尚未顯示凍結資料與等待文字")
 assert(overlay.Visible and body.ReportHeading.Text=="等待隊伍結果" and body.ReportSummary.Text==expectedDuration(report.survivalSeconds),"pending 標題／存活秒數／結果視窗不符")
 local function displayed(name,value)
  local label=stats:FindFirstChild(name,true)
  assert(label and label:GetAttribute("ReportValue")==value and label.Text==expectedNumber(value),"pending 正式數值文字不符："..name)
 end
 for _,key in ipairs({"food","wood","gold","stone"}) do displayed("ReportDelivered_"..key,report.resourcesDelivered[key]); displayed("ReportSpent_"..key,report.resourcesSpent[key]) end
 for _,key in ipairs(counters) do displayed("ReportValue_"..key,report[key]) end
 assert(status.AbsolutePosition.Y+status.AbsoluteSize.Y<=stats.AbsolutePosition.Y-4,"pending 等待文字覆蓋凍結數據")
 print("[MATCH_REPORT_PENDING COMPLETE] 正式 pending JSON、16 個數值文字、存活時長與等待隊伍說明；唯讀")
 return true
end
-- Start while naturally eliminated, then let allies finish the ordinary match.
-- It permits using Watch meanwhile and never substitutes another focus/result.
function Tests.ObservePendingFinal(expectedOutcome,timeoutSeconds)
 local player,screen=client()
 expectedOutcome=expectedOutcome or "win"; timeoutSeconds=timeoutSeconds or 120
 assert(expectedOutcome=="win" or expectedOutcome=="loss" or expectedOutcome=="draw","結果必須為 win、loss 或 draw")
 assert(type(timeoutSeconds)=="number" and timeoutSeconds>=5 and timeoutSeconds<=180,"觀察時間須介於 5 至 180 秒")
 local before=read(player,true)
 assert(before and before.finished==false and player:GetAttribute("Defeated")==true and player:GetAttribute("Forfeited")~=true,"須先自然淘汰並取得 pending 正式報告")
 print("[MATCH_REPORT_PENDING OBSERVE] 等待盟友透過正常玩法結束對局；不修改任何狀態。")
 waitFor(function() return read(player)~=nil end,timeoutSeconds,"隊伍結束仍未送達 finished 正式報告")
 local after=read(player)
 assert(after.matchId==before.matchId and after.outcome==expectedOutcome and player:GetAttribute("Forfeited")~=true,"自然淘汰者最終隊伍結果不符或發生投降")
 assert(after.survivalSeconds==before.survivalSeconds,"自然淘汰後存活秒數繼續增加")
 for _,key in ipairs(counters) do assert(after[key]==before[key],"自然淘汰後個人事實繼續累計："..key) end
 for _,field in ipairs({"resourcesDelivered","resourcesSpent"}) do for _,key in ipairs({"food","wood","gold","stone"}) do assert(after[field][key]==before[field][key],"自然淘汰後資源事實繼續累計："..field.."."..key) end end
 local _,body,scroll=nodes(screen)
 local objective=screen:FindFirstChild("MatchObjective",true)
 waitFor(function() return body.ReportHeading.Text:find(after.outcomeLabel,1,true)~=nil and objective and objective.Text:sub(1,#after.outcomeLabel)==after.outcomeLabel and not scroll.ReportStatus.Visible end,5,"正式 UI 的最終結果未優先於 Defeated")
 assert(body.ReportSummary.Text==expectedDuration(after.survivalSeconds),"最終存活文字與凍結秒數不符")
 print("[MATCH_REPORT_PENDING_FINAL COMPLETE] 同局 frozen 事實／存活秒數未變，實際 UI 優先呈現正式隊伍結果")
 return true
end
function Tests.CheckClear()
 local player,screen=client()
 assert(player:GetAttribute("MatchReportJSON")==nil or player:GetAttribute("MatchReportJSON")=="","[MATCH_REPORT_TEST FAIL] 新局／重開仍有前局 JSON")
 local overlay,_,scroll=nodes(screen)
 local stats,status=scroll:FindFirstChild("ReportStats"),scroll:FindFirstChild("ReportStatus")
 waitFor(function() return stats and not stats.Visible and status and status.Visible and status.Text=="覆盤資料尚未送達" end,5,"前局 UI 資料沒有清空")
 for _,object in ipairs(stats:GetDescendants()) do
  if object:IsA("TextLabel") and (object.Name:sub(1,16)=="ReportDelivered_" or object.Name:sub(1,12)=="ReportSpent_" or object.Name:sub(1,12)=="ReportValue_") then
   assert(object.Text=="—" and object:GetAttribute("ReportValue")==nil,"[MATCH_REPORT_TEST FAIL] 無報告仍保留或偽造數據："..object.Name)
  end
 end
 if workspace:GetAttribute("MatchPhase")=="Lobby" or workspace:GetAttribute("MatchPhase")=="Playing" then
  assert(not overlay.Visible,"[MATCH_REPORT_TEST FAIL] 重開後仍顯示前局結果")
 end
 print("[MATCH_REPORT_CLEAR COMPLETE] 正式 JSON、可見數據與欄位標記已清空；沒有填零代替報告")
 return true
end
-- Start before using the normal restart UI. Observes that a real completed report
-- disappears after reset/new game; it never performs the reset itself.
function Tests.ObserveClear(timeoutSeconds)
 local player=client()
 assert(read(player),"請先取得正式已結束的覆盤資料，再觀察重開清零")
 timeoutSeconds=timeoutSeconds or 120
 assert(type(timeoutSeconds)=="number" and timeoutSeconds>=5 and timeoutSeconds<=180,"觀察時間須介於 5 至 180 秒")
 print("[MATCH_REPORT_CLEAR OBSERVE] 請透過正式介面返回戰局設定，必要時開始新局。")
 waitFor(function() local value=player:GetAttribute("MatchReportJSON"); return value==nil or value=="" end,timeoutSeconds,"正常重開未清除前局 JSON")
 return Tests.CheckClear()
end
return Tests
