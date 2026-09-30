$ErrorActionPreference = 'Stop'
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
    Set-Content -Encoding utf8 build/core-tests.luau $bundle
    & $runtime build/core-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
    $matchRules = Get-Content src/ServerScriptService/ServerModules/MatchRules.lua -Raw
    $matchTests = Get-Content tests/match.spec.lua -Raw
    $matchBundle = $shim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal MatchRules=(function()`n" + $matchRules + "`nend)()`n" + $matchTests
    Set-Content -Encoding utf8 build/match-tests.luau $matchBundle
    & $runtime build/match-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'Match rules tests failed.' }
    $world = Get-Content src/ServerScriptService/ServerModules/WorldGenerator.lua -Raw
    $world = $world.Replace('local Config = require(game.ReplicatedStorage.GameData.GameConfig)', '')
    $worldTests = Get-Content tests/world.spec.lua -Raw
    $worldShim = @'
local Random={new=function(seed)
 local state=seed
 return {NextInteger=function(_,low,high) state=(state*48271)%2147483647; return low+state%(high-low+1) end}
end}
local testOwnedResource={GetAttribute=function() return true end,Destroy=function(self) self.removed=true end}
local testUnknownResource={GetAttribute=function() return nil end,Destroy=function(self) self.removed=true end}
local workspace={SetAttribute=function() end,FindFirstChild=function() return {GetChildren=function() return {testOwnedResource,testUnknownResource} end} end}
'@
    $worldBundle = $shim + "`n" + $worldShim + "`nlocal Config=(function()`n" + $config + "`nend)()`nlocal WorldGenerator=(function()`n" + $world + "`nend)()`n" + $worldTests
    Set-Content -Encoding utf8 build/world-tests.luau $worldBundle
    & $runtime build/world-tests.luau
    if ($LASTEXITCODE -ne 0) { throw 'World layout tests failed.' }
    & ./rojo.exe build default.project.json -o build/AOE2.rbxlx
    if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
} finally {
    Pop-Location
}
