param(
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string]$OutputPrefix = 'tests/unit-collision-studio-20261001'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
# Offline only. JSON contains complete (evidence acceptance), evidence (scope),
# and report (the original reconstructed test JSON). Rejected evidence is saved
# for inspection, then raises an error; it must never be interpreted as PASS.
$inputPath = (Resolve-Path -LiteralPath $LogPath).Path
$prefixPath = [IO.Path]::GetFullPath($OutputPrefix)
$jsonPath = $prefixPath + '.json'
$textPath = $prefixPath + '.txt'
if ($inputPath -eq $jsonPath -or $inputPath -eq $textPath) { throw 'Outputs must not overwrite the Studio log.' }
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$stream = [IO.File]::Open($inputPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
try {
    if ($stream.Length -gt 134217728) { throw 'Studio log snapshot exceeds 128 MiB.' }
    $buffer = [byte[]]::new([int]$stream.Length)
    $readCount = 0
    while ($readCount -lt $buffer.Length) {
        $count = $stream.Read($buffer, $readCount, $buffer.Length - $readCount)
        if ($count -eq 0) { break }
        $readCount += $count
    }
} finally { $stream.Dispose() }
$sourceText = $utf8.GetString($buffer, 0, $readCount)
$lines = $sourceText -split '\r?\n'
$records = [Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match '\[FLog::(?:Output|CreatorOutput)\]\s*(?<message>.*)$') {
        $records.Add([pscustomobject]@{ line = $index + 1; message = $Matches.message; raw = $lines[$index] })
    }
}
$runs = [Collections.Generic.List[object]]::new()
$current = $null
$passStart = $null
function New-Run([int]$line, [int]$total, [int]$rawStart) {
    return [pscustomobject][ordered]@{
        ordinal = $runs.Count + 1; firstJsonLine = $line; rawStartLine = $rawStart
        total = $total; chunks = [Collections.Generic.List[object]]::new()
        status = $null; statusLine = $null; statusText = $null
        issues = [Collections.Generic.List[string]]::new(); report = $null; validSequence = $false
    }
}
foreach ($record in $records) {
    if ($record.message -match '^\[UNIT_COLLISION PASS\]') {
        if ($null -eq $passStart) { $passStart = $record.line }
    }
    if ($record.message -match '^\[UNIT_COLLISION JSON (?<part>\d+)/(?<total>\d+)\] (?<payload>.*)$') {
        $part, $total, $payload = [int]$Matches.part, [int]$Matches.total, $Matches.payload
        if ($part -eq 1 -or $null -eq $current) {
            $restarted = $null -ne $current
            if ($null -ne $current) { $current.issues.Add('A new JSON sequence began before the preceding status marker.') }
            $rawStart = if ($null -ne $passStart) { [int]$passStart } else { [int]$record.line }
            $current = New-Run $record.line $total $rawStart
            if ($restarted) { $current.issues.Add('JSON restarted before a terminal marker; a duplicate first segment or overlapping run is ambiguous.') }
            $runs.Add($current)
        }
        if ($total -lt 1 -or $total -gt 10000) { $current.issues.Add('Invalid segment count.') }
        if ($total -ne $current.total) { $current.issues.Add('Segment totals disagree.') }
        if ($part -ne $current.chunks.Count + 1) { $current.issues.Add('Segment indices are missing, repeated, or out of order.') }
        if ($utf8.GetByteCount($record.message) -gt 600) { $current.issues.Add('A JSON segment line exceeds 600 UTF-8 bytes.') }
        $payloadBytes = $utf8.GetByteCount($payload)
        # The producer packs 560 bytes and backs up at most 3 bytes for UTF-8.
        # Without this, truncation inside a JSON string could still decode after
        # concatenation and silently delete text without changing status counts.
        if ($payloadBytes -lt 1 -or $payloadBytes -gt 560 -or ($part -lt $total -and $payloadBytes -lt 557)) {
            $current.issues.Add('Segment payload length is inconsistent with the UTF-8 producer; possible truncation.')
        }
        $current.chunks.Add([pscustomobject]@{ index = $part; total = $total; line = $record.line; payload = $payload })
        continue
    }
    if ($record.message -match '^\[UNIT_COLLISION (?<status>COMPLETE|INCOMPLETE)\] (?<details>.*)$') {
        $status, $details = $Matches.status, $Matches.details
        if ($null -eq $current) {
            $rawStart = if ($null -ne $passStart) { [int]$passStart } else { [int]$record.line }
            $current = New-Run $record.line 0 $rawStart
            $current.issues.Add('Status marker has no segmented JSON; legacy or truncated output is not acceptance evidence.')
            $runs.Add($current)
        }
        $current.status, $current.statusLine, $current.statusText = $status, $record.line, $details
        $current = $null
        $passStart = $null
    }
}
if ($null -ne $current) { $current.issues.Add('Missing COMPLETE/INCOMPLETE status marker.') }

foreach ($run in $runs) {
    if ($run.chunks.Count -ne $run.total -or $run.total -lt 1) { $run.issues.Add('Incomplete segment sequence.') }
    if ($null -eq $run.status) { $run.issues.Add('No terminal status.') }
    if ($run.chunks.Count -gt 0) {
        try {
            $joined = ($run.chunks | ForEach-Object { $_.payload }) -join ''
            $run.report = $joined | ConvertFrom-Json
            if ($null -eq $run.report) { $run.issues.Add('Joined JSON contains no report object.') }
        } catch { $run.issues.Add('Joined JSON cannot be decoded: ' + $_.Exception.Message) }
    }
    if ($null -ne $run.report) {
        try {
            if ($run.report.complete -isnot [bool]) { throw 'report.complete is not Boolean.' }
            if (($run.status -eq 'COMPLETE') -ne $run.report.complete) { throw 'Status and report.complete disagree.' }
            if ($run.statusText -notmatch '^checks=(?<checks>\d+) samples=(?<samples>\d+) rootChanges=(?<roots>\d+) elapsed=(?<elapsed>\d+(?:\.\d+)?) work=(?<gather>true|false)/(?<deliver>true|false) segments=(?<segments>\d+)$') {
                throw 'Short status is missing, truncated, or unsupported.'
            }
            $statusFields = @{} + $Matches
            $rootChanges = 0
            foreach ($stage in $run.report.stages) { $rootChanges += [int]$stage.rootChanges }
            $statusElapsed = [double]::Parse($statusFields.elapsed, [Globalization.CultureInfo]::InvariantCulture)
            if ([int]$statusFields.checks -ne $run.report.checks -or [int]$statusFields.samples -ne $run.report.samples -or
                [int]$statusFields.roots -ne $rootChanges -or [int]$statusFields.segments -ne $run.total -or
                [Math]::Abs($statusElapsed - $run.report.elapsedSeconds) -gt .001 -or
                [bool]::Parse($statusFields.gather) -ne $run.report.work.gathered -or
                [bool]::Parse($statusFields.deliver) -ne $run.report.work.delivered) { throw 'Short status metrics disagree with JSON.' }
            if ($run.report.complete -and (!$run.report.cleanupStopped -or $run.report.elapsedSeconds -gt 90)) {
                throw 'Completed report has unconfirmed cleanup or exceeds the total deadline.'
            }
        } catch { $run.issues.Add($_.Exception.Message) }
    }
    $run.validSequence = $run.issues.Count -eq 0
}
$validRuns = @($runs | Where-Object { $_.validSequence })
$selected = if ($validRuns.Count -gt 0) { $validRuns[-1] } elseif ($runs.Count -gt 0) { $runs[$runs.Count - 1] } else { $null }
$errors = [Collections.Generic.List[string]]::new()
if ($null -eq $selected) { $errors.Add('No unit collision run was found.') }
else {
    foreach ($issue in $selected.issues) { $errors.Add($issue) }
    if ($selected.status -ne 'COMPLETE') { $errors.Add('The selected test ended INCOMPLETE or has no terminal marker.') }
    if ($selected.ordinal -ne $runs.Count) { $errors.Add('A later incomplete or truncated run exists; an earlier COMPLETE cannot stand in for it.') }
}

# UC95 is the validation chat's explicit scope marker. Fixtures may run before
# STARTUP, so include the nearest preceding fixture block, not every Factory
# message in a shared Studio process. Formation/other chat output is excluded.
$scopeStart, $scopeEnd, $startupLine, $fixtureLine = $null, $null, $null, $null
$rawSelected = [Collections.Generic.List[string]]::new()
if ($null -ne $selected) {
    $scopeStart = $selected.rawStartLine
    $scopeEnd = if ($null -ne $selected.statusLine) { $selected.statusLine } else { $lines.Count }
    $startup = @($records | Where-Object { $_.line -le $selected.firstJsonLine -and $_.message -match '^\[?UC95(?:\]|\s)+STARTUP\b' })
    if ($startup.Count -gt 0) {
        $startupLine = $startup[-1].line
        $fixtures = @($records | Where-Object { $_.line -lt $startupLine -and $_.message -match '^\[?UC95(?:\]|\s)+FIXTURE\b' })
        $scopeStart = $startupLine
        if ($fixtures.Count -gt 0) {
            $fixtureLine = $fixtures[-1].line
            $previousFixture = if ($fixtures.Count -gt 1) { $fixtures[-2].line } else { 0 }
            $earlierStatus = @($runs | Where-Object { $null -ne $_.statusLine -and $_.statusLine -lt $fixtureLine })
            if ($earlierStatus.Count -gt 0) { $previousFixture = [Math]::Max($previousFixture, $earlierStatus[-1].statusLine) }
            $factoryBlock = @($records | Where-Object { $_.line -gt $previousFixture -and $_.line -le $fixtureLine -and $_.message -match '^\[FACTORY(?:[ _\]])' })
            $scopeStart = if ($factoryBlock.Count -gt 0) { $factoryBlock[0].line } else { $fixtureLine }
        }
        $laterStartup = @($records | Where-Object { $_.line -gt $scopeEnd -and $_.message -match '^\[?UC95(?:\]|\s)+STARTUP\b' })
        if ($laterStartup.Count -gt 0) { $errors.Add('A later UC95 validation Play startup exists without a selected complete run.') }
    }
    $nextRun = @($runs | Where-Object { $_.ordinal -gt $selected.ordinal })
    $upperBound = if ($nextRun.Count -gt 0) { $nextRun[0].rawStartLine } else { $lines.Count + 1 }
    $final = @($records | Where-Object { $_.line -gt $scopeEnd -and $_.line -lt $upperBound -and $_.message -match '^\[?UC95(?:\]|\s)+FINAL\b' })
    if ($final.Count -gt 0) { $scopeEnd = $final[0].line }
    foreach ($record in $records) {
        $collision = $record.line -ge $selected.rawStartLine -and $record.line -le $scopeEnd -and $record.message -match '^\[UNIT_COLLISION(?:[ _\]])'
        $support = $null -ne $startupLine -and $record.line -ge $scopeStart -and $record.line -le $scopeEnd -and
            ($record.message -match '^\[?(?:UC95|FACTORY)(?:[ _\]])' -or $record.message -match '^\[RTS\].*(?:對局開始|初始化|RTSReady|ready|startup)')
        if ($collision -or $support) { $rawSelected.Add($record.raw) }
    }
}
$accepted = $errors.Count -eq 0 -and $null -ne $selected -and $selected.validSequence -and $selected.report.complete
$runDetails = @($runs | ForEach-Object {
    [ordered]@{ ordinal = $_.ordinal; firstJsonLine = $_.firstJsonLine; statusLine = $_.statusLine; status = $_.status
        segmentsExpected = $_.total; segmentsObserved = $_.chunks.Count; validSequence = $_.validSequence; issues = @($_.issues.ToArray()) }
})
$evidence = [ordered]@{
    logPath = $inputPath; snapshotBytes = $readCount; selection = 'Last structurally valid sequence; reject any later unfinished run'
    selectedRun = if ($null -ne $selected) { $selected.ordinal } else { $null }
    observedRuns = $runs.Count; validSequences = $validRuns.Count; runs = $runDetails
    rawScopeStartLine = $scopeStart; rawScopeEndLine = $scopeEnd; startupLine = $startupLine; fixtureLine = $fixtureLine
    supportingScope = if ($null -ne $startupLine) { 'Latest UC95 STARTUP and its preceding UC95 FIXTURE/Factory block' } else { 'Unit collision run only; no UC95 scope marker found' }
    errors = @($errors.ToArray())
}
$artifact = [ordered]@{ complete = [bool]$accepted; evidence = $evidence; report = if ($null -ne $selected) { $selected.report } else { $null } }
$outputDirectory = [IO.Path]::GetDirectoryName($prefixPath)
if (!(Test-Path -LiteralPath $outputDirectory)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
[IO.File]::WriteAllText($jsonPath, ($artifact | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines($textPath, $rawSelected.ToArray(), [Text.UTF8Encoding]::new($false))
if ($validRuns.Count -gt 1) { Write-Warning "Multiple valid sequences found; selected run $($selected.ordinal) of $($runs.Count). Earlier runs are recorded as excluded context." }
if (!$accepted) { throw ('Unit collision evidence rejected: ' + ($errors.ToArray() -join '; ') + '. Saved diagnostics: ' + $jsonPath) }
[pscustomobject]@{ complete = $true; selectedRun = $selected.ordinal; observedRuns = $runs.Count; json = $jsonPath; raw = $textPath }
