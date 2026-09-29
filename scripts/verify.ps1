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
    & ./rojo.exe build default.project.json -o build/AOE2.rbxlx
    if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed.' }
} finally {
    Pop-Location
}
