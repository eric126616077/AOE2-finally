-- Test-only LocalScript, mapped only by shop-validation.project.json（伺服器以 RTSTestCrowns=1200 建立記憶體錢包）。
-- 經由正式的 Command 遠端測試王國商店：拒絕不合法請求、購買、重複與連點、透支、每日獎勵、成就、裝備、
-- 大廳稱號、實際 PlayerGui，再開一局確認外觀套用在自己的單位與建築、電腦勢力與數值不受影響、對戰中無法換裝。
local Run=game:GetService("RunService")
if not Run:IsStudio() then return end
local RS=game:GetService("ReplicatedStorage")
local player=game.Players.LocalPlayer
local passed,failed=0,0
local function check(name,ok,detail)
 if ok then passed+=1 else failed+=1 end
 print("[SHOP_TEST] "..(ok and "PASS " or "FAIL ")..name..(detail~=nil and (" | "..tostring(detail)) or ""))
end
local function info(text) print("[SHOP_TEST] INFO "..text) end
local function waitFor(predicate,seconds)
 local deadline=os.clock()+seconds
 repeat
  if predicate() then return true end
  task.wait(0.1)
 until os.clock()>deadline
 return predicate()==true
end
local function crowns() return player:GetAttribute("Crowns") or -1 end
local function owns(id) return ((","..(player:GetAttribute("OwnedCosmetics") or "")..",")):find(","..id..",",1,true)~=nil end
local function key(color) return string.format("%d,%d,%d",math.round(color.R*255),math.round(color.G*255),math.round(color.B*255)) end

local function main()
 assert(waitFor(function() return workspace:GetAttribute("RTSReady")==true and player.PlayerGui:FindFirstChild("AOE2_MainGUI") end,30),"初始化逾時")
 local command=RS.RTSRemotes.Command
 RS.RTSRemotes.Feedback.OnClientEvent:Connect(function(message) if type(message)=="string" then info("伺服器通知："..message) end end)
 local Catalog=require(RS.GameData.ShopCatalog)
 check("錢包載入",waitFor(function() return player:GetAttribute("WalletStatus")=="Ready" end,15),player:GetAttribute("WalletStatus"))
 check("Studio 記憶體錢包起始金冠",crowns()==1200,crowns())
 check("Studio 不寫入雲端",player:GetAttribute("WalletPersistent")==false)
 check("預設外觀",player:GetAttribute("CosmeticUnitSkin")=="skin_standard" and player:GetAttribute("CosmeticTitle")=="title_none",player:GetAttribute("CosmeticUnitSkin"))
 local gui=player.PlayerGui:WaitForChild("AOE2_ShopGUI",10)
 local dock=gui and gui:FindFirstChild("ShopDock",true)
 check("實際 PlayerGui 有商店入口且大廳可見",dock~=nil and dock.Visible==true)
 local crownText=gui and gui:FindFirstChild("CrownText",true)
 check("金冠餘額顯示",crownText~=nil and crownText.Text:find("1,200",1,true)~=nil,crownText and crownText.Text)

 -- 不合法請求：通行證專屬、不存在、錯型別、未擁有的裝備。全部不改變餘額與外觀。
 command:FireServer("Shop","Buy","skin_royal")
 command:FireServer("Shop","Buy","no_such_item")
 command:FireServer("Shop","Buy",{})
 command:FireServer("Shop",123,"skin_gilded")
 command:FireServer("Shop","Equip","skin_gilded")
 command:FireServer("Shop","Buy","title_pioneer")
 task.wait(1.5)
 check("拒絕不合法購買與未擁有裝備",crowns()==1200 and not owns("skin_royal") and not owns("skin_gilded") and not owns("title_pioneer")
  and player:GetAttribute("CosmeticUnitSkin")=="skin_standard",crowns())

 command:FireServer("Shop","Buy","skin_gilded")
 check("購買部隊塗裝並自動裝備",waitFor(function() return crowns()==800 and owns("skin_gilded") and player:GetAttribute("CosmeticUnitSkin")=="skin_gilded" end,8),crowns())
 command:FireServer("Shop","Buy","skin_gilded")
 task.wait(1.5)
 check("重複購買不扣款",crowns()==800,crowns())
 command:FireServer("Shop","Buy","style_desert")
 check("購買城鎮風格",waitFor(function() return crowns()==300 and player:GetAttribute("CosmeticBuildingStyle")=="style_desert" end,8),crowns())
 task.wait(0.5)
 command:FireServer("Shop","Buy","title_builder")
 command:FireServer("Shop","Buy","title_builder")
 task.wait(2.5)
 check("連點購買只扣一次",crowns()==150 and owns("title_builder"),crowns())
 command:FireServer("Shop","Buy","style_marble")
 task.wait(1.5)
 check("金冠不足不能購買",crowns()==150 and not owns("style_marble"),crowns())
 check("每日獎勵可領",player:GetAttribute("DailyClaimable")==true and player:GetAttribute("DailyNextAmount")==Catalog.rewards.daily[1])
 command:FireServer("Shop","ClaimDaily")
 check("領取每日獎勵",waitFor(function() return crowns()==150+Catalog.rewards.daily[1] and player:GetAttribute("DailyClaimable")==false end,8),crowns())
 task.wait(0.5)
 command:FireServer("Shop","ClaimDaily")
 task.wait(1.5)
 check("每日獎勵不可重領",crowns()==150+Catalog.rewards.daily[1],crowns())
 local before=crowns()
 command:FireServer("TutorialDone")
 check("完成教程發放一次性成就",waitFor(function() return crowns()==before+Catalog.milestones.welcome.crowns end,8),crowns())
 command:FireServer("Shop","Equip","title_builder")
 check("裝備稱號",waitFor(function() return player:GetAttribute("CosmeticTitle")=="title_builder" end,5))
 check("大廳角色頭上顯示稱號",waitFor(function()
  local head=player.Character and player.Character:FindFirstChild("Head")
  local title=head and head:FindFirstChild("RTSCosmeticTitle")
  local label=title and title:FindFirstChildWhichIsA("TextLabel")
  return label~=nil and label.Text:find("築城大師",1,true)~=nil
 end,5))
 check("餘額顯示同步",waitFor(function() return crownText.Text:find(tostring(crowns()),1,true)~=nil end,3),crownText.Text)

 -- 開局：外觀只在自己的單位與建築，數值與電腦一致。
 require(RS.Shared.LobbyTests).Start({size="Small",aiCount=1,difficulty="Easy",population=100,startingResources="Rich",victory="Conquest",teamMode="FFA"})
 assert(waitFor(function() return workspace:GetAttribute("MatchPhase")=="Playing" and workspace:FindFirstChild("Units") and #workspace.Units:GetChildren()>0 end,40),"開始測試局逾時")
 check("對戰中隱藏商店入口",waitFor(function() return dock.Visible==false end,5))
 local tc
 waitFor(function()
  for _,building in ipairs(workspace.Buildings:GetChildren()) do
   if building:GetAttribute("OwnerId")==player.UserId and building:GetAttribute("BuildingType")=="TownCenter" then tc=building; return true end
  end
  return false
 end,10)
 check("市鎮中心套用城鎮風格",tc~=nil and tc:GetAttribute("CosmeticStyle")=="style_desert",tc and tc:GetAttribute("CosmeticStyle"))
 if tc then
  local desert={}
  for _,color in pairs(Catalog.items.style_desert.look.palette) do desert[key(color)]=true end
  local styled,teamOK,teamParts=0,true,0
  local team=player:GetAttribute("TeamColor")
  for _,part in ipairs(tc:GetDescendants()) do
   if part:IsA("BasePart") then
    if part:GetAttribute("TeamColorPart")==true then teamParts+=1; if key(part.Color)~=key(team) then teamOK=false end
    elseif desert[key(part.Color)] then styled+=1 end
   end
  end
  check("建築零件換成沙岩配色",styled>0,styled)
  check("隊伍色零件不受外觀影響",teamParts>0 and teamOK,teamParts)
 end
 local mine,theirs
 for _,unit in ipairs(workspace.Units:GetChildren()) do
  if unit:GetAttribute("UnitType")=="villager" then
   if unit:GetAttribute("OwnerId")==player.UserId then mine=mine or unit elseif (unit:GetAttribute("OwnerId") or 0)<0 then theirs=theirs or unit end
  end
 end
 check("自己的村民套用部隊塗裝",mine~=nil and mine:GetAttribute("CosmeticSkin")=="skin_gilded",mine and mine:GetAttribute("CosmeticSkin"))
 check("電腦村民維持預設外觀",theirs~=nil and theirs:GetAttribute("CosmeticSkin")==nil)
 check("外觀不改變單位數值",mine~=nil and theirs~=nil and mine:GetAttribute("MaxHP")==theirs:GetAttribute("MaxHP"),mine and mine:GetAttribute("MaxHP"))
 check("外觀不改變資源",(player:GetAttribute("food") or 0)>0)
 command:FireServer("Shop","Equip","skin_standard")
 task.wait(1.5)
 check("對戰中不能更換外觀",player:GetAttribute("CosmeticUnitSkin")=="skin_gilded",player:GetAttribute("CosmeticUnitSkin"))
 local scoreboard=player.PlayerGui.AOE2_MainGUI:FindFirstChild("Scoreboard",true)
 local listed=false
 if scoreboard then for _,row in ipairs(scoreboard:GetDescendants()) do if row:IsA("TextLabel") and row.Text:find("「築城大師」",1,true) then listed=true end end end
 check("對戰勢力列表顯示稱號",waitFor(function()
  if not scoreboard then return false end
  for _,row in ipairs(scoreboard:GetDescendants()) do if row:IsA("TextLabel") and row.Text:find("「築城大師」",1,true) then return true end end
  return false
 end,5) or listed)
 local beforeSurrender=crowns()
 command:FireServer("Surrender")
 task.wait(3)
 check("投降不發對局金冠",crowns()==beforeSurrender,crowns())
 print(string.format("[SHOP_TEST] DONE %d PASS / %d FAIL",passed,failed))
end
task.spawn(function()
 local ok,err=pcall(main)
 if not ok then print("[SHOP_TEST] FAIL 測試中斷 | "..tostring(err)); print(string.format("[SHOP_TEST] DONE %d PASS / %d FAIL",passed,failed+1)) end
end)
