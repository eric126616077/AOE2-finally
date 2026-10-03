param([string]$PlaceOutput = 'build/AOE2.rbxlx')
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 reads ANSI and writes a UTF-8 BOM by default; Luau rejects the BOM.
$PSDefaultParameterValues['Get-Content:Encoding'] = 'UTF8'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Write-Utf8NoBom([string]$Path, [string]$Text) { [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Path), $Text, $utf8NoBom) }
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $compiler = Join-Path $root '.tools/luau/luau-compile.exe'
    $runtime = Join-Path $root '.tools/luau/luau.exe'
    if (!(Test-Path $compiler) -or !(Test-Path $runtime)) {
        throw 'Install official luau-lang/luau Windows CLI binaries in .tools/luau first.'
    }
    $files = @(Get-ChildItem src -Recurse -Filter *.lua | ForEach-Object FullName)
    & $compiler --null @files
    if ($LASTEXITCODE -ne 0) { throw 'Luau syntax compilation failed.' }
    # Studio also compiles without optimization; catch its stricter local-register budget.
    & $compiler -O0 --null @files
    if ($LASTEXITCODE -ne 0) { throw 'Luau Studio-compatible compilation failed.' }
    New-Item -ItemType Directory -Force build | Out-Null
    # Execute actual module bodies, substituting only engine constructors and module loading.
    $shim = @'
local Vector2 = {new=function(x,y) return {X=x,Y=y} end}
local Vector3 = {new=function(x,y,z) return {X=x,Y=y,Z=z} end}
local Color3 = {fromRGB=function(r,g,b) return {r,g,b} end}
'@
    $config = Get-Content src/ReplicatedStorage/GameData/GameConfig.lua -Raw
    $grid = Get-Content src/ReplicatedStorage/Shared/Grid.lua -Raw
    $grid = $grid.Replace('local Config = require(script.Parent.Parent.GameData.GameConfig)', '')
    $economy = Get-Content src/ServerScriptService/ServerModules/Economy.lua -Raw
    $tests = Get-Content tests/core.spec.lua -Raw
    $bundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal Grid=(function()`n" + $grid + "`nend)()`nlocal Economy=(function()`n" + $economy + "`nend)()`n" + $tests
    Write-Utf8NoBom build/core-tests.luau $bundle
    & $runtime build/core-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
    $buildMenuRules = Get-Content src/ReplicatedStorage/Shared/BuildMenuRules.lua -Raw
    $buildMenuTests = Get-Content tests/build_menu.spec.lua -Raw
    $buildMenuBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal BuildMenuRules=(function()`n" + $buildMenuRules + "`nend)()`n" + $buildMenuTests
    Write-Utf8NoBom build/build-menu-tests.luau $buildMenuBundle
    & $runtime build/build-menu-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Villager building page / age visibility tests failed.' }
    $teamRules = Get-Content src/ServerScriptService/ServerModules/TeamRules.lua -Raw
    $matchRules = Get-Content src/ServerScriptService/ServerModules/MatchRules.lua -Raw
    $matchRules = $matchRules.Replace('local TeamRules = require(script.Parent.TeamRules)', '')
    $matchTests = Get-Content tests/match.spec.lua -Raw
    $teamMatchPrelude = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal TeamRules=(function()`n" + $teamRules + "`nend)()`nlocal MatchRules=(function()`n" + $matchRules + "`nend)()`n"
    $matchBundle = $teamMatchPrelude + $matchTests
    Write-Utf8NoBom build/match-tests.luau $matchBundle
    & $runtime build/match-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Match rules tests failed.' }
    $lobbyRules = Get-Content src/ServerScriptService/ServerModules/LobbyRules.lua -Raw
    $lobbyRules = $lobbyRules.Replace('local MatchRules = require(script.Parent.MatchRules)', '')
    $lobbyRules = $lobbyRules.Replace('local TeamRules = require(script.Parent.TeamRules)', '')
    $lobbyRules = $lobbyRules.Replace('local GameModeRules = require(game:GetService("ReplicatedStorage").Shared.GameModeRules)', '')
    $gameModeRules = (Get-Content src/ReplicatedStorage/Shared/GameModeRules.lua -Raw).Replace('local Config = require(script.Parent.Parent.GameData.GameConfig)', '')
    $lobbyPrelude = $teamMatchPrelude + "local GameModeRules=(function()`n" + $gameModeRules + "`nend)()`n"
    $lobbyTests = Get-Content tests/lobby.spec.lua -Raw
    $lobbyTests = $lobbyTests.Replace('local MatchRules=require("../src/ServerScriptService/ServerModules/MatchRules")', '')
    $lobbyBundle = $lobbyPrelude + "local LobbyRules=(function()`n" + $lobbyRules + "`nend)()`n" + $lobbyTests
    Write-Utf8NoBom build/lobby-tests.luau $lobbyBundle
    & $runtime build/lobby-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Lobby rules tests failed.' }
    $gameModeTests = Get-Content tests/game_modes.spec.lua -Raw
    $gameModeBundle = $lobbyPrelude + "local LobbyRules=(function()`n" + $lobbyRules + "`nend)()`n" + $gameModeTests
    Write-Utf8NoBom build/game-mode-tests.luau $gameModeBundle
    & $runtime build/game-mode-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Story / PvP / PvE lobby mode tests failed.' }
    $lobbyServerSource = Get-Content src/ServerScriptService/GameServer.server.lua -Raw
    $lobbyInitStart = $lobbyServerSource.IndexOf('for _,portal in ipairs(Config.Lobby.portals) do')
    $lobbyInitEnd = $lobbyServerSource.IndexOf('local queueJoin, queueLeave, spawnLobby', $lobbyInitStart)
    $lobbyRoomStart = $lobbyServerSource.IndexOf('local function humanStates()')
    $lobbyRoomEnd = $lobbyServerSource.IndexOf('local function clearBattlefieldResources()', $lobbyRoomStart)
    $lobbyLifecycleStart = $lobbyServerSource.IndexOf('local function lobbyReset()')
    $lobbyLifecycleEnd = $lobbyServerSource.IndexOf('local function join(player)', $lobbyLifecycleStart)
    if ($lobbyInitStart -lt 0 -or $lobbyInitEnd -le $lobbyInitStart -or $lobbyRoomStart -lt 0 -or $lobbyRoomEnd -le $lobbyRoomStart -or $lobbyLifecycleStart -lt 0 -or $lobbyLifecycleEnd -le $lobbyLifecycleStart) {
        throw 'Actual server lobby room / matching lifecycle source unavailable.'
    }
    $lobbyRoomMocks = Get-Content tests/lobby_rooms.mocks.lua -Raw
    $lobbyRoomMocks = $lobbyRoomMocks.Replace('-- ACTUAL_SERVER_LOBBY_ROOM_INIT', $lobbyServerSource.Substring($lobbyInitStart, $lobbyInitEnd - $lobbyInitStart))
    $lobbyRoomMocks = $lobbyRoomMocks.Replace('-- ACTUAL_SERVER_LOBBY_ROOM_BODY', $lobbyServerSource.Substring($lobbyRoomStart, $lobbyRoomEnd - $lobbyRoomStart))
    $lobbyRoomMocks = $lobbyRoomMocks.Replace('-- ACTUAL_SERVER_LOBBY_CLEAR_BODY', $lobbyServerSource.Substring($lobbyRoomEnd, $lobbyLifecycleStart - $lobbyRoomEnd))
    $lobbyRoomMocks = $lobbyRoomMocks.Replace('-- ACTUAL_SERVER_LOBBY_LIFECYCLE_BODY', $lobbyServerSource.Substring($lobbyLifecycleStart, $lobbyLifecycleEnd - $lobbyLifecycleStart))
    $lobbyRoomTests = Get-Content tests/lobby_rooms.spec.lua -Raw
    $lobbyRoomBundle = $lobbyPrelude + "local LobbyRules=(function()`n" + $lobbyRules + "`nend)()`n" + $lobbyRoomMocks + "`n" + $lobbyRoomTests
    Write-Utf8NoBom build/lobby-room-tests.luau $lobbyRoomBundle
    & $runtime build/lobby-room-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Actual lobby room separation / readiness / host / matching lifecycle tests failed.' }
    $placeRules = Get-Content src/ServerScriptService/ServerModules/PlaceRules.lua -Raw
    $placeRules = $placeRules.Replace('local LobbyRules = require(script.Parent.LobbyRules)', '')
    $matchTravel = Get-Content src/ServerScriptService/ServerModules/MatchTravel.lua -Raw
    $matchTravel = $matchTravel.Replace('local PlaceRules = require(script.Parent.PlaceRules)', '')
    $placeTests = Get-Content tests/place_travel.spec.lua -Raw
    $taskShim = "local task={spawn=function(callback,...) return callback(...) end}`n"
    $placeBundle = $lobbyPrelude + "local LobbyRules=(function()`n" + $lobbyRules + "`nend)()`n" + $taskShim + "local PlaceRules=(function()`n" + $placeRules + "`nend)()`nlocal MatchTravel=(function()`n" + $matchTravel + "`nend)()`n" + $placeTests
    Write-Utf8NoBom build/place-travel-tests.luau $placeBundle
    & $runtime build/place-travel-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Cross-place match ticket / teleport tests failed.' }
    & $runtime tests/team.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Server team assignment / alliance / victory tests failed.' }
    & $runtime tests/team_lifecycle.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Team elimination / frozen report / profile lifecycle tests failed.' }
    & $runtime tests/team_client.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Team client settings / ally input / report rules tests failed.' }
    $civilizationRules = Get-Content src/ServerScriptService/ServerModules/CivilizationRules.lua -Raw
    $commerceRules = Get-Content src/ServerScriptService/ServerModules/CommerceRules.lua -Raw
    $civilizationTests = Get-Content tests/civilization.spec.lua -Raw
    $civilizationBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal CivilizationRules=(function()`n" + $civilizationRules + "`nend)()`nlocal CommerceRules=(function()`n" + $commerceRules + "`nend)()`n" + $civilizationTests
    Write-Utf8NoBom build/civilization-tests.luau $civilizationBundle
    & $runtime build/civilization-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Civilization / fair commerce tests failed.' }
    $profileRules = Get-Content src/ServerScriptService/ServerModules/ProfileRules.lua -Raw
    $profileStore = Get-Content src/ServerScriptService/ServerModules/ProfileStore.lua -Raw
    $profileStore = $profileStore.Replace('local Rules=require(script.Parent.ProfileRules)', 'local Rules=ProfileRules')
    $telemetry = Get-Content src/ServerScriptService/ServerModules/Telemetry.lua -Raw
    $profileTests = Get-Content tests/profile.spec.lua -Raw
    $profileBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal ProfileRules=(function()`n" + $profileRules + "`nend)()`nlocal ProfileStore=(function()`n" + $profileStore + "`nend)()`nlocal Telemetry=(function()`n" + $telemetry + "`nend)()`n" + $profileTests
    Write-Utf8NoBom build/profile-tests.luau $profileBundle
    & $runtime build/profile-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Profile / telemetry safety tests failed.' }
    & $runtime tests/match_report.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Match report successful-fact accounting tests failed.' }
    & $runtime tests/ai_workers.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'AI worker recovery tests failed.' }
    & $runtime tests/auto_work.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Villager auto-work tests failed.' }
    $serverRuleTests = Get-Content tests/server_rules.spec.lua -Raw
    $serverRuleBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`n" + $serverRuleTests
    Write-Utf8NoBom build/server-rules-tests.luau $serverRuleBundle
    & $runtime build/server-rules-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Server spatial / production lifecycle tests failed.' }
    & $runtime tests/combat.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Combat acquisition / ownership tests failed.' }
    # Fallback art builders and HUD portraits run against a small engine mock.
    $artTest = (Get-Content tests/art_smoke.spec.lua -Raw) -split '--@@MODULES@@'
    $artKit = Get-Content src/ReplicatedStorage/Shared/ArtKit.lua -Raw
    $artUnits = (Get-Content src/ReplicatedStorage/Shared/ArtUnits.lua -Raw).Replace('require(script.Parent.ArtKit)', '__ArtKit')
    $artNature = (Get-Content src/ReplicatedStorage/Shared/ArtNature.lua -Raw).Replace('require(script.Parent.ArtKit)', '__ArtKit')
    $unitIcons = Get-Content src/ReplicatedStorage/Shared/UnitIcons.lua -Raw
    $artBundle = $artTest[0] + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal __ArtKit=(function()`n" + $artKit + "`nend)()`nlocal ArtUnits=(function()`n" + $artUnits + "`nend)()`nlocal ArtNature=(function()`n" + $artNature + "`nend)()`nlocal UnitIcons=(function()`n" + $unitIcons + "`nend)()`n" + $artTest[1]
    Write-Utf8NoBom build/art-smoke-tests.luau $artBundle
    & $runtime build/art-smoke-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Fallback art / HUD portrait smoke tests failed.' }
    $contentTests = Get-Content tests/content.spec.lua -Raw
    $contentBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`n" + $contentTests
    Write-Utf8NoBom build/content-tests.luau $contentBundle
    & $runtime build/content-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Unit upgrade / new unit / hunting content tests failed.' }
    $elementsTests = Get-Content tests/aoe2_elements.spec.lua -Raw
    Write-Utf8NoBom build/aoe2-elements-tests.luau ($shim + "`nlocal Config=(function()`n" + $config + "`nend)()`n" + $elementsTests)
    & $runtime build/aoe2-elements-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Market / stance / herd / fog-of-war rule tests failed.' }
    & $runtime tests/monk.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Monk conversion / heal / faith tests failed.' }
    & $runtime tests/garrison.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Garrison capacity / entry / extra-arrow tests failed.' }
    & $runtime tests/melee.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Melee attack approach geometry tests failed.' }
    & $runtime tests/approach.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Shared work approach / blocked Farm regression tests failed.' }
    & $runtime tests/farm.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Farm single-worker / prepaid queue / reseed rule tests failed.' }
    & $runtime tests/path.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Path radius / actual movement segment safety tests failed.' }
    & $runtime tests/path_prefix.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Safe-prefix progress / bounded replan tests failed.' }
    & $runtime tests/unit_collision.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Unit volume sweep / steering / live spatial index tests failed.' }
    & $runtime tests/command.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Atomic delete ownership / generation validation tests failed.' }
    & $runtime tests/production.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Production queue revision / rally / refund validation tests failed.' }
    $serverSource = Get-Content src/ServerScriptService/GameServer.server.lua -Raw
    # endMatch must publish winner attributes before switching to Ended (clients see changes in set order).
    $endStart = $serverSource.IndexOf('local function endMatch(winnerTeam)')
    $endEnd = $serverSource.IndexOf('checkVictory=function()', $endStart)
    if ($endStart -lt 0 -or $endEnd -le $endStart) { throw 'Actual endMatch source unavailable.' }
    $endBody = $serverSource.Substring($endStart, $endEnd - $endStart)
    $winnerAt = $endBody.IndexOf('SetAttribute("WinnerTeamId"')
    $endedAt = $endBody.IndexOf('setPhase("Ended")')
    if ($winnerAt -lt 0 -or $endedAt -lt 0 -or $winnerAt -gt $endedAt) { throw 'endMatch switches to Ended before publishing the winner.' }
    Write-Output 'PASS: endMatch publishes winner attributes before MatchPhase=Ended'
    $formationStart = $serverSource.IndexOf('local function selectedFormationUnits(')
    $formationEnd = $serverSource.IndexOf('command.OnServerEvent:Connect(', $formationStart)
    if ($formationStart -lt 0 -or $formationEnd -le $formationStart) { throw 'Actual formation command source unavailable.' }
    $formationTests = Get-Content tests/formation.spec.lua -Raw
    $formationBody = $serverSource.Substring($formationStart, $formationEnd - $formationStart)
    $formationTests = $formationTests.Replace('-- ACTUAL_SERVER_FORMATION_BODY', $formationBody + "`nrunServerChecks=true")
    $orderStateStart = $serverSource.IndexOf('stop=function(unit,preserveFormationSlot)')
    $orderStateEnd = $serverSource.IndexOf('local function unreachable(', $orderStateStart)
    if ($orderStateStart -lt 0 -or $orderStateEnd -le $orderStateStart) { throw 'Actual order/formation attribute lifecycle source unavailable.' }
    $formationTests = $formationTests.Replace('-- ACTUAL_SERVER_ORDER_STATE_BODY', $serverSource.Substring($orderStateStart, $orderStateEnd - $orderStateStart))
    Write-Utf8NoBom build/formation-tests.luau $formationTests
    & $runtime build/formation-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Formation geometry / atomic authoritative command tests failed.' }
    $movementStart = $serverSource.IndexOf('local function moveToward(')
    $movementEnd = $serverSource.IndexOf('local function nearestResource(', $movementStart)
    if ($movementStart -lt 0 -or $movementEnd -le $movementStart) { throw 'Actual moveToward source section unavailable.' }
    $movementMocks = Get-Content tests/movement_step.mocks.lua -Raw
    $movementTests = Get-Content tests/movement_step.spec.lua -Raw
    $movementBody = $serverSource.Substring($movementStart, $movementEnd - $movementStart)
    $stationaryStart = $serverSource.IndexOf('local function stationaryUnitAt(')
    $stationaryEnd = $serverSource.IndexOf('local function edgePosition(', $stationaryStart)
    if ($stationaryStart -lt 0 -or $stationaryEnd -le $stationaryStart) { throw 'Actual stationary unit occupancy source unavailable.' }
    $stationaryBody = $serverSource.Substring($stationaryStart, $stationaryEnd - $stationaryStart)
    $routeGoalStart = $serverSource.IndexOf('local function refreshRouteGoal(')
    $routeGoalEnd = $serverSource.IndexOf('local function route(', $routeGoalStart)
    if ($routeGoalStart -lt 0 -or $routeGoalEnd -le $routeGoalStart) { throw 'Actual route goal lifecycle source unavailable.' }
    $routeGoalBody = $serverSource.Substring($routeGoalStart, $routeGoalEnd - $routeGoalStart)
    Write-Utf8NoBom build/movement-step-tests.luau ($movementMocks + "`n" + $stationaryBody + "`n" + $routeGoalBody + "`n" + $movementBody + "`n" + $movementTests)
    & $runtime build/movement-step-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Actual server waypoint tick / live collision regression failed.' }
    $filterStart = $serverSource.IndexOf('local overlap=OverlapParams.new()')
    $filterEnd = $serverSource.IndexOf('local function obstacleParts(', $filterStart)
    $previewSource = Get-Content src/ReplicatedStorage/Shared/BuildingController.lua -Raw
    $previewStart = $previewSource.IndexOf(' local params = OverlapParams.new()')
    $previewEnd = $previewSource.IndexOf(' local folders = {}', $previewStart)
    if ($filterStart -lt 0 -or $filterEnd -le $filterStart -or $previewStart -lt 0 -or $previewEnd -le $previewStart) { throw 'Actual server/preview obstacle filter sections unavailable.' }
    $filterBody = $serverSource.Substring($filterStart, $filterEnd - $filterStart)
    $previewBody = "local function previewObstacleFilters(preview,ghost)`n" + $previewSource.Substring($previewStart, $previewEnd - $previewStart) + "`n return params`nend`n"
    $filterMocks = Get-Content tests/obstacle_filters.mocks.lua -Raw
    $filterTests = Get-Content tests/obstacle_filters.spec.lua -Raw
    Write-Utf8NoBom build/obstacle-filter-tests.luau ($filterMocks + "`n" + $filterBody + "`n" + $previewBody + "`n" + $filterTests)
    & $runtime build/obstacle-filter-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Actual server/preview unknown scenery collision / filter cache regression failed.' }
    $cleanupStart = $serverSource.IndexOf('local function clearBattlefieldResources()')
    if ($cleanupStart -lt 0) { throw 'Actual battlefield resource cleanup source unavailable.' }
    $cleanupEnd = $serverSource.IndexOf('local function lobbyReset()', $cleanupStart)
    if ($cleanupEnd -le $cleanupStart) { throw 'Actual battlefield cleanup lifecycle source unavailable.' }
    $cleanupBody = $serverSource.Substring($cleanupStart, $cleanupEnd - $cleanupStart)
    $cleanupMocks = Get-Content tests/resource_cleanup.mocks.lua -Raw
    $cleanupTests = Get-Content tests/resource_cleanup.spec.lua -Raw
    Write-Utf8NoBom build/resource-cleanup-tests.luau ($cleanupMocks + "`n" + $cleanupBody + "`n" + $cleanupTests)
    & $runtime build/resource-cleanup-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Actual resource cleanup lifecycle / registry / unknown model preservation regression failed.' }
    $gatheringTests = Get-Content tests/gathering.spec.lua -Raw
    $gatheringBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`n" + $gatheringTests
    Write-Utf8NoBom build/gathering-tests.luau $gatheringBundle
    & $runtime build/gathering-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Gathering conservation / delivery tests failed.' }
    & $runtime tests/construction.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Construction rules tests failed.' }
    & $runtime tests/walls.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Wall line / gate passage geometry tests failed.' }
    & $runtime tests/construction_hp.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Construction health conservation tests failed.' }
    & $runtime tests/construction_visuals.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Construction reveal stages / visible effect budget tests failed.' }
    & $runtime tests/damage_visuals.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Building damage state / break share / effect budget tests failed.' }
    $factory = Get-Content src/ServerScriptService/ServerModules/ModelFactory.lua -Raw
    $factory = $factory.Replace('local Art=require(ReplicatedStorage.Shared.Art)', '')
    $factory = $factory.Replace('local Config=require(ReplicatedStorage.GameData.GameConfig)', '')
    $remains = Get-Content src/ReplicatedStorage/Shared/RemainsRules.lua -Raw
    $factory = $factory.Replace('local Remains=require(ReplicatedStorage.Shared.RemainsRules)', "local Remains=(function()`n" + $remains + "`nend)()")
    $factoryMocks = Get-Content tests/model_factory.mocks.lua -Raw
    $factoryTests = Get-Content tests/model_factory.spec.lua -Raw
    $factoryBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`n" + $factoryMocks + "`nlocal Factory=(function()`n" + $factory + "`nend)()`n" + $factoryTests
    Write-Utf8NoBom build/model-factory-tests.luau $factoryBundle
    & $runtime build/model-factory-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Model factory copy / fallback tests failed.' }
    & $runtime tests/performance_observer.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Performance observer accounting tests failed.' }
    & $runtime tests/motion.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Buffered unit motion / visible pose budget tests failed.' }
    & $runtime tests/remains.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Death fall / collapse / resource fade timing tests failed.' }
    & $runtime tests/cinematic.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Battle trailer timeline / camera math tests failed.' }
    & $runtime tests/lobby_trailer.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Lobby trailer video id / slideshow / fit tests failed.' }
    $cinematic = @(Get-ChildItem cinematic -Filter *.lua | ForEach-Object FullName)
    & $compiler -O0 --null @cinematic
    if ($LASTEXITCODE -ne 0) { throw 'Battle trailer scripts failed to compile.' }
    & $runtime tests/effect_pool.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Client effect pool reuse / lease tests failed.' }
    & $runtime tests/ambience.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Ambience wind / grass layout tests failed.' }
    & $runtime tests/touch.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Touch rules tests failed.' }
    & $runtime tests/tutorial.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Tutorial rules tests failed.' }
    & $runtime tests/feedback.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Cosmetic audio playback rules tests failed.' }
    & $runtime tests/cursor.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Context cursor rules tests failed.' }
    & $runtime tests/selection.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Drag-box selection rules tests failed.' }
    & $runtime tests/hotkey.spec.lua
    if ($LASTEXITCODE -ne 0) { throw 'Hotkey binding rules tests failed.' }
    $world = Get-Content src/ServerScriptService/ServerModules/WorldGenerator.lua -Raw
    $world = $world.Replace('local Config = require(game.ReplicatedStorage.GameData.GameConfig)', '')
    $worldTests = Get-Content tests/world.spec.lua -Raw
    $worldShim = @'
local testRandomAutomaticSeeds={2718,9001}
local testRandomUnseededCalls=0
local Random={new=function(seed)
 if seed==nil then
  testRandomUnseededCalls+=1
  seed=testRandomAutomaticSeeds[testRandomUnseededCalls] or 100000+testRandomUnseededCalls*997
 end
 local state=math.floor(math.abs(seed))%2147483646+1
 local function nextUnit()
  state=(state*48271)%2147483647
  return (state-1)/2147483646
 end
 return {
  NextInteger=function(_,low,high) return low+math.floor(nextUnit()*(high-low+1)) end,
  NextNumber=function(_,low,high)
   low,high=low or 0,high or 1
   return low+(high-low)*nextUnit()
  end,
 }
end}
local testOwnedResource={GetAttribute=function() return true end,Destroy=function(self) self.removed=true end}
local testUnknownResource={GetAttribute=function() return nil end,Destroy=function(self) self.removed=true end}
local workspace={SetAttribute=function() end,FindFirstChild=function() return {GetChildren=function() return {testOwnedResource,testUnknownResource} end} end}
'@
    $worldBundle = $shim + "`n" + $worldShim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal WorldGenerator=(function()`n" + $world + "`nend)()`n" + $worldTests
    Write-Utf8NoBom build/world-tests.luau $worldBundle
    & $runtime build/world-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'World layout tests failed.' }
    & ./rojo.exe build default.project.json -o $PlaceOutput
    if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
} finally {
    Pop-Location
}
