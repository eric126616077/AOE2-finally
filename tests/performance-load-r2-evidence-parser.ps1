param(
    [string[]]$LogPath,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'performance-load-r2-evidence-20261001.json')
)
$ErrorActionPreference = 'Stop'
# Offline evidence extraction only: no Studio control, game writes, or acceptance verdict.
if (!$LogPath -or $LogPath.Count -eq 0) {
    $latestLog = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Roblox/logs') -Filter '*Studio*.log' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (!$latestLog) { throw 'No Roblox Studio log found.' }
    $LogPath = @($latestLog.FullName)
}
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
$inputPaths = @($LogPath | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
if ($inputPaths -contains $outputFullPath) { throw 'Output must never overwrite an input Studio log.' }
$records = [Collections.Generic.List[object]]::new()
$stages = [Collections.Generic.List[object]]::new()
$rejected = [Collections.Generic.List[object]]::new()
$sources = [Collections.Generic.List[object]]::new()
$culture = [Globalization.CultureInfo]::InvariantCulture
$style = [Globalization.DateTimeStyles]::AssumeUniversal
$taipei = [TimeZoneInfo]::FindSystemTimeZoneById('Taipei Standard Time')

function New-Stage($probe, $sourceIndex, $record) {
    $stage = [ordered]@{
        id = $stages.Count + 1; probe = $probe; sourceIndex = $sourceIndex
        generation = $record.payload.generation; mode = $record.payload.data.mode
        label = $record.payload.label; epoch = $record.payload.epoch
        actualUnits = $record.payload.data.actualUnits
        firstRecordUtc = $record.timestampUtc; endUtc = $null; startUtc = $null
        startEstimatedFromReportedDuration = $false; terminal = 'unfinished'
        recordIndices = [Collections.Generic.List[int]]::new()
        frames = $null; framesByFocus = [ordered]@{}; focusCoverage = $null
        load = $null; camera = $null; metrics = [ordered]@{}
        managedUnitCounts = [Collections.Generic.List[int]]::new()
        heartbeatCadence = $null; latestServerStats = $null
        ordersInServerProbe = 'not measured'; performanceAccepted = $false
        missingRecords = [Collections.Generic.List[string]]::new()
    }
    $stages.Add($stage)
    return $stage
}

for ($sourceIndex = 0; $sourceIndex -lt $inputPaths.Count; $sourceIndex++) {
    $path = $inputPaths[$sourceIndex]
    $clientStage = $null
    $serverEpochs = @{}
    $lineNumber = 0
    $parsedCount = 0
    # FileShare.ReadWrite permits a bounded snapshot while Studio keeps appending.
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $snapshotBytes = $stream.Length
    if ($snapshotBytes -gt 134217728) { $stream.Dispose(); throw 'Studio log snapshot exceeds 128 MiB.' }
    $buffer = [byte[]]::new([int]$snapshotBytes)
    $bytesRead = 0
    try {
        while ($bytesRead -lt $buffer.Length) {
            $read = $stream.Read($buffer,$bytesRead,$buffer.Length-$bytesRead)
            if ($read -eq 0) { break }
            $bytesRead += $read
        }
    } finally { $stream.Dispose() }
    $memory = [IO.MemoryStream]::new($buffer,0,$bytesRead,$false)
    $reader = [IO.StreamReader]::new($memory, [Text.Encoding]::UTF8)
    try {
        while (!$reader.EndOfStream) {
            $line = $reader.ReadLine()
            $lineNumber++
            # Exclude Command Bar source echoes, JSON embedded in Lua, and unrelated logs.
            if ($line -notmatch '^(?<timestamp>[^,]+),[^,]+,[^,]+,[^,]+,\w+ \[FLog::CreatorOutput\]\s*(?<json>\{.*)\s*$') { continue }
            $raw = $Matches.json
            $timestampText = $Matches.timestamp
            $payload = $null
            try { $payload = $raw | ConvertFrom-Json } catch {
                if ($raw -match '"probe"\s*:\s*"(ClientLoad|ServerHeartbeat)"') {
                    $rejected.Add([ordered]@{sourceIndex=$sourceIndex;line=$lineNumber;reason='invalid JSON'})
                }
                continue
            }
            if ($payload.probe -ne 'ClientLoad' -and $payload.probe -ne 'ServerHeartbeat') { continue }
            $bytes = [Text.Encoding]::UTF8.GetByteCount($raw)
            if ($bytes -gt 700) {
                $rejected.Add([ordered]@{sourceIndex=$sourceIndex;line=$lineNumber;reason='probe JSON exceeds 700 UTF-8 bytes';bytes=$bytes})
                continue
            }
            if ($payload.kind -isnot [string]) {
                $rejected.Add([ordered]@{sourceIndex=$sourceIndex;line=$lineNumber;reason='missing kind'})
                continue
            }
            $stamp = [DateTimeOffset]::MinValue
            if (![DateTimeOffset]::TryParse($timestampText, $culture, $style, [ref]$stamp)) {
                $rejected.Add([ordered]@{sourceIndex=$sourceIndex;line=$lineNumber;reason='invalid UTC timestamp'})
                continue
            }
            $record = [ordered]@{
                sourceIndex=$sourceIndex;line=$lineNumber
                timestampUtc=$stamp.ToUniversalTime().ToString('o')
                timestampTaipei=[TimeZoneInfo]::ConvertTime($stamp,$taipei).ToString('o')
                jsonBytes=$bytes;payload=$payload
            }
            $recordIndex = $records.Count
            $records.Add($record)
            $parsedCount++
            $stage = $null
            if ($payload.probe -eq 'ServerHeartbeat') {
                $epochKey = [string]$payload.epoch
                # Source is emitted first; a new Source/Started also separates reset epochs.
                if (!$serverEpochs.ContainsKey($epochKey) -or $payload.kind -eq 'Source' -or
                    ($payload.kind -eq 'Started' -and $serverEpochs[$epochKey].startUtc)) {
                    $serverEpochs[$epochKey] = New-Stage 'ServerHeartbeat' $sourceIndex $record
                }
                $stage = $serverEpochs[$epochKey]
                if ($payload.label) { $stage.label = $payload.label }
                if ($payload.kind -eq 'Started') { $stage.startUtc = $record.timestampUtc }
                if ($payload.kind -eq 'Counts') {
                    $stage.generation = $payload.data.context.generation
                    if ($payload.data.models.managed.Units -is [ValueType]) {
                        $stage.managedUnitCounts.Add([int]$payload.data.models.managed.Units)
                    }
                }
                if ($payload.kind -eq 'Finished') { $stage.terminal='Finished';$stage.endUtc=$record.timestampUtc }
                if ($payload.kind -eq 'Cadence') { $stage.heartbeatCadence=$payload.data }
                if ($payload.kind -eq 'Stats') { $stage.latestServerStats=$payload.data }
                if ($payload.kind -eq 'OutputMissing' -or $payload.kind -eq 'SampleError') { $stage.missingRecords.Add($payload.kind) }
            } else {
                if ($payload.kind -eq 'FRAMES' -or !$clientStage) { $clientStage = New-Stage 'ClientLoad' $sourceIndex $record }
                $stage = $clientStage
                if ($payload.data.mode) { $stage.mode = $payload.data.mode }
                if ($payload.data.actualUnits -is [ValueType]) { $stage.actualUnits = $payload.data.actualUnits }
                switch ($payload.kind) {
                    'FRAMES' { $stage.frames = $payload.data.frames }
                    'FOCUS_FRAMES' { $stage.framesByFocus[[string]$payload.data.focus] = $payload.data.frames }
                    'FOCUS' { $stage.focusCoverage = $payload.data }
                    'LOAD' { $stage.load = $payload.data.load; $stage.camera = $payload.data.camera }
                    'METRIC' { $stage.metrics[[string]$payload.data.name] = $payload.data.value }
                    'COMPLETE' {
                        $stage.terminal='COMPLETE';$stage.endUtc=$record.timestampUtc
                        if ($payload.data.seconds -is [ValueType] -and $payload.data.seconds -gt 0) {
                            $stage.startUtc=$stamp.AddSeconds(-[double]$payload.data.seconds).ToUniversalTime().ToString('o')
                            $stage.startEstimatedFromReportedDuration=$true
                        }
                        foreach ($required in @('FRAMES','FOCUS','LOAD')) {
                            $field=@{FRAMES='frames';FOCUS='focusCoverage';LOAD='load'}[$required]
                            if (!$stage[$field]) { $stage.missingRecords.Add($required) }
                        }
                        $clientStage=$null
                    }
                    'INCOMPLETE' { $stage.terminal='INCOMPLETE';$stage.endUtc=$record.timestampUtc;$stage.error=$payload.data.error;$clientStage=$null }
                    'PREPARED' { $stage.terminal='PREPARED';$stage.endUtc=$record.timestampUtc;$stage.preparation=$payload.data;$clientStage=$null }
                }
                if ($payload.missing) { $stage.missingRecords.Add([string]$payload.missing) }
            }
            $stage.recordIndices.Add($recordIndex)
        }
    } finally { $reader.Dispose() }
    $sources.Add([ordered]@{path=$path;snapshotBytes=$snapshotBytes;linesRead=$lineNumber;probeRecords=$parsedCount})
}

# Interval overlap is an inference from log times, not proof of the same live workload.
$overlaps = [Collections.Generic.List[object]]::new()
foreach ($server in @($stages | Where-Object {$_.probe -eq 'ServerHeartbeat'})) {
    if ($server.managedUnitCounts.Count -gt 0) {
        $countSummary=$server.managedUnitCounts | Measure-Object -Minimum -Maximum
        $server.unitCountSummary=[ordered]@{samples=$server.managedUnitCounts.Count;minimum=$countSummary.Minimum;maximum=$countSummary.Maximum}
    }
    $matches = [Collections.Generic.List[int]]::new()
    if ($server.startUtc -and $server.endUtc) {
        foreach ($client in @($stages | Where-Object {$_.probe -eq 'ClientLoad' -and $_.terminal -eq 'COMPLETE'})) {
            if (!$client.startUtc -or !$client.endUtc -or $client.generation -ne $server.generation -or $client.sourceIndex -ne $server.sourceIndex) { continue }
            $start = [DateTimeOffset]::Parse($client.startUtc)
            $end = [DateTimeOffset]::Parse($client.endUtc)
            if ($start -lt [DateTimeOffset]::Parse($server.endUtc) -and $end -gt [DateTimeOffset]::Parse($server.startUtc)) { $matches.Add($client.id) }
        }
    }
    $overlaps.Add([ordered]@{serverStageId=$server.id;completedClientStageIds=$matches.ToArray();overlapInferred=$matches.Count -gt 0;workloadEquivalenceProven=$false})
}
$report = [ordered]@{
    schemaVersion=1;scope='Offline Studio CreatorOutput JSON extraction'
    performanceAccepted=$false;baselineImprovementProven=$false;serverCPUMeasured=$false
    generatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');sources=$sources.ToArray()
    records=$records.ToArray();stages=$stages.ToArray();serverClientOverlaps=$overlaps.ToArray();rejected=$rejected.ToArray()
    limitations=@('COMPLETE means the helper finished a sampling segment, not performance acceptance.',
        'Server labels are caller labels; the heartbeat probe never measures unit orders.',
        'Unknown focus remains unknown; no foreground or throttling cause is inferred.',
        'Client starts are estimated from reported duration; INCOMPLETE may lack mode/start/duration.',
        'No active VM source identity, server CPU, pathfinding duration or baseline improvement is established.')
}
$outputDirectory = Split-Path -Parent $outputFullPath
if (!(Test-Path -LiteralPath $outputDirectory -PathType Container)) { throw 'Output directory must already exist.' }
$json = $report | ConvertTo-Json -Depth 40 -Compress
[IO.File]::WriteAllText($outputFullPath,$json,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{Output=$outputFullPath;Sources=$sources.Count;Records=$records.Count;Stages=$stages.Count;Rejected=$rejected.Count;PerformanceAccepted=$false} | ConvertTo-Json -Compress
