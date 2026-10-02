-- Opt-in validation place only, observing actual PlayerRemoving without changing game rules.
if not game:GetService("RunService"):IsStudio() then return end
local Players=game:GetService("Players")
Players.PlayerRemoving:Connect(function(player)
 local id=player.UserId
 task.defer(function()
  local deadline=os.clock()+10
  repeat task.wait() until not player.Parent or os.clock()>deadline
  local count=0
  for _,name in ipairs({"Units","Buildings"}) do
   local folder=workspace:FindFirstChild(name)
   if folder then for _,model in ipairs(folder:GetChildren()) do if model:GetAttribute("RTSManaged")==true and model:GetAttribute("OwnerId")==id then count+=1 end end end
  end
  print("[LOBBY_STORY SERVER] LEAVE "..player.Name.." owned="..count.." online="..#Players:GetPlayers())
  assert(count==0,"[LOBBY_STORY SERVER] departed player retained owned instances")
  if #Players:GetPlayers()==0 then
   repeat task.wait() until workspace:GetAttribute("MatchPhase")=="Lobby" or os.clock()>deadline
   assert(workspace:GetAttribute("MatchPhase")=="Lobby" and workspace:GetAttribute("ActiveBattleRoomId")==nil,"[LOBBY_STORY SERVER] last departure did not release battlefield")
   print("[LOBBY_STORY SERVER] EMPTY_ARENA_RESET PASS")
  end
 end)
end)
