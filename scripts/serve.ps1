$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    & ./rojo.exe serve default.project.json --address 127.0.0.1 --port 34872
} finally {
    Pop-Location
}
