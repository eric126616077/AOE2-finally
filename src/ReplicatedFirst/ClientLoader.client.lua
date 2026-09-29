-- RTS has no avatar; loading must depend on DataModel readiness, not CharacterAdded.
if not game:IsLoaded() then game.Loaded:Wait() end
game:GetService("ReplicatedFirst"):RemoveDefaultLoadingScreen()
