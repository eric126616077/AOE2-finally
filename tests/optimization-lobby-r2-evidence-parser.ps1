$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot 'optimization-lobby-r2-source-manifest-20261001.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$differences = @($manifest.files | Where-Object {
    (Get-FileHash -LiteralPath (Join-Path $root $_.path) -Algorithm SHA256).Hash -ne $_.sha256
})
if ($differences.Count -gt 0) { throw "Source mismatch: $($differences.path -join ', ')" }
foreach ($build in @(
    @{ path = $manifest.buildPath; hash = $manifest.buildSha256 },
    @{ path = $manifest.validationBuildPath; hash = $manifest.validationBuildSha256 }
)) {
    if ((Get-FileHash -LiteralPath (Join-Path $root $build.path) -Algorithm SHA256).Hash -ne $build.hash) {
        throw "Build mismatch: $($build.path)"
    }
}
$studioLog = 'C:\Users\user\AppData\Local\Roblox\logs\0.741.19.7411056_20260930T223624Z_Studio_8AE4B_last.log'
$lines = Get-Content -LiteralPath $studioLog -Encoding UTF8
$completeLines = @($lines | Where-Object { $_ -match '\[LOBBY_CLEANUP COMPLETE\] ' })
if ($completeLines.Count -ne 1) { throw 'Expected one complete report' }
$completeLine = $completeLines[0]
$report = $completeLine.Substring($completeLine.IndexOf('[LOBBY_CLEANUP COMPLETE] ') + '[LOBBY_CLEANUP COMPLETE] '.Length) | ConvertFrom-Json
if (-not $report.complete -or $report.cycles.Count -ne 5 -or $report.checks -ne 126) { throw 'Incomplete report' }
if (($report.cycles.size -join ',') -ne 'Small,Small,Large,Large,Small') { throw 'Unexpected cycle sequence' }
if (@($report.cycles | Where-Object { $_.afterNodes -ne 0 -or $_.afterParts -ne 0 -or $_.afterDots -ne 0 }).Count -ne 0) {
    throw 'Cleanup census did not reach zero'
}
$evidence = [ordered]@{
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    originalLog = $studioLog
    sourceManifest = 'tests/optimization-lobby-r2-source-manifest-20261001.json'
    sourceFilesMatched = $manifest.files.Count
    defaultBuild = $manifest.buildPath
    defaultBuildSha256 = $manifest.buildSha256
    validationBuild = $manifest.validationBuildPath
    validationBuildSha256 = $manifest.validationBuildSha256
    completeLogLine = $completeLine
    report = $report
    limits = @(
        'Single-player Studio Play; no multiplayer, player-leave, full population or device FPS claim.',
        'beforeParts is the client received-parts census, not proof of complete visual replication or server memory.',
        'Unknown fixture identity, parent and management flags are checked; not all material/color/CFrame metadata.',
        'Studio also logged avatar animation asset 96806611330323 load failures; this run does not claim a clean external avatar asset load.'
    )
}
$evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'optimization-lobby-r2-studio-results-20261001.json') -Encoding UTF8
$excerpt = @(
    "Original log: $studioLog",
    "Source manifest: tests/optimization-lobby-r2-source-manifest-20261001.json; matched $($manifest.files.Count)/$($manifest.files.Count)",
    "Default build SHA256: $($manifest.buildSha256)",
    "Validation build SHA256: $($manifest.validationBuildSha256)",
    'Client received-parts census only; single-player normal restart lifecycle.',
    ''
) + @($lines | Where-Object { $_ -match '\[LOBBY_CLEANUP (PASS|CYCLE|COMPLETE)\]|\[LOBBY_CLEANUP_FIXTURE READY\]|\[MAP_TEST COMPLETE\]|Disconnect from 127\.0\.0\.1|Failed to load animation.*96806611330323' })
$excerpt | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'optimization-lobby-r2-studio-results-20261001.txt') -Encoding UTF8
Write-Output "PASS: $($report.checks) checks; five cycles; $($manifest.files.Count) source files and both builds match."
