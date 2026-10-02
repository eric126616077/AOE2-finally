# Offline parser for the explicitly invoked R2 Server & Clients helper.
# Only complete, unchanged raw log snapshots can produce an accepted result.
param(
    [Parameter(Mandatory=$true)][string]$ServerLog,
    [Parameter(Mandatory=$true)][string]$HostLog,
    [Parameter(Mandatory=$true)][string]$PeerLog,
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'optimization-multiplayer-lifecycle-r2-source-manifest-20261001.json'),
    [string]$OutputJson = (Join-Path $PSScriptRoot 'optimization-multiplayer-lifecycle-r2-studio-results-20261001.json'),
    [string]$OutputText = (Join-Path $PSScriptRoot 'optimization-multiplayer-lifecycle-r2-studio-results-20261001.txt')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false,$true)
$culture = [Globalization.CultureInfo]::InvariantCulture
$snapshots = [Collections.Generic.List[object]]::new()
$reports = [Collections.Generic.List[object]]::new()
$records = [Collections.Generic.List[object]]::new()
$globalIds = @{}

function Assert-True($condition,[string]$message) {
    if (!$condition) { throw "拒絕完整通過：$message" }
}
function Field($value,[string]$name) {
    if ($null -eq $value) { return $null }
    $property = $value.PSObject.Properties | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
    if ($null -ne $property) { return $property.Value }
    return $null
}
function Is-Integer($value) {
    return $null -ne $value -and $value -is [ValueType] -and $value -isnot [bool] -and
        ![double]::IsNaN([double]$value) -and ![double]::IsInfinity([double]$value) -and
        [double]$value -eq [math]::Truncate([double]$value)
}
function Assert-Number($value,[string]$label) {
    Assert-True ($null -ne $value -and $value -is [ValueType] -and $value -isnot [bool] -and
        ![double]::IsNaN([double]$value) -and ![double]::IsInfinity([double]$value)) "$label 不是有限數值"
}
function Parse-Json([string]$text,[string]$label) {
    try { $value = ConvertFrom-Json -InputObject $text -ErrorAction Stop }
    catch { throw "拒絕完整通過：$label 的 JSON 無效：$($_.Exception.Message)" }
    Assert-True ($null -ne $value -and $value -is [pscustomobject]) "$label 須為 JSON object"
    return $value
}
function Canonical($value) {
    if ($null -eq $value) { return 'null' }
    if ($value -is [pscustomobject] -or $value -is [Collections.IDictionary]) {
        $names = if ($value -is [Collections.IDictionary]) { @($value.Keys) } else { @($value.PSObject.Properties.Name) }
        $pairs = foreach ($name in @($names | Sort-Object -CaseSensitive)) {
            $item = if ($value -is [Collections.IDictionary]) { $value[$name] } else { Field $value $name }
            (ConvertTo-Json -InputObject ([string]$name) -Compress) + ':' + (Canonical $item)
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($value -is [Array]) { return '[' + (@($value | ForEach-Object { Canonical $_ }) -join ',') + ']' }
    return ConvertTo-Json -InputObject $value -Compress -Depth 40
}
function Assert-Same($left,$right,[string]$label) {
    Assert-True ((Canonical $left) -ceq (Canonical $right)) "$label 不一致"
}
function Assert-Fields($value,$expected,[string]$label) {
    foreach ($name in $expected.Keys) { Assert-Same (Field $value $name) $expected[$name] "$label.$name" }
}
function Repo-Path([string]$relative) {
    Assert-True (![string]::IsNullOrWhiteSpace($relative) -and ![IO.Path]::IsPathRooted($relative)) 'manifest 路徑必須相對於專案'
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    Assert-True ($full.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) "manifest 路徑超出專案：$relative"
    return $full
}
function Check-Hash([string]$path,[string]$hash) {
    Assert-True ($hash -cmatch '^[0-9A-Fa-f]{64}$') "無效 SHA256：$path"
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "缺少來源／建置：$path"
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Assert-True ($actual -ieq $hash) "來源／建置 SHA256 不一致：$path"
    return $actual
}
function File-Map($rows,[int]$count,[string]$label) {
    Assert-True (@($rows).Count -eq $count) "$label 須有 $count 檔"
    $map = @{}
    foreach ($row in @($rows)) {
        $path = Field $row 'path'; $hash = Field $row 'sha256'
        Assert-True ($path -is [string] -and $hash -is [string]) "$label 缺 path/sha256"
        $full = Repo-Path $path
        Assert-True (!$map.ContainsKey($full)) "$label 重複來源路徑：$path"
        $map[$full] = Check-Hash $full $hash
    }
    return $map
}
function Read-Snapshot([string]$path,[string]$role) {
    $full = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
    $stream = [IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $length = $stream.Length
        Assert-True ($length -gt 0 -and $length -le 134217728) "$role 日誌須為 1 byte 至 128 MiB"
        $buffer = [byte[]]::new([int]$length); $read = 0
        while ($read -lt $buffer.Length) {
            $next = $stream.Read($buffer,$read,$buffer.Length-$read)
            Assert-True ($next -gt 0) "$role 日誌在擷取期間截短"
            $read += $next
        }
    } finally { $stream.Dispose() }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($buffer)).Replace('-','') } finally { $sha.Dispose() }
    try { $text = $utf8.GetString($buffer).TrimStart([char]0xFEFF) }
    catch { throw "拒絕完整通過：$role 日誌不是完整 UTF-8：$($_.Exception.Message)" }
    return [ordered]@{role=$role;path=$full;snapshotBytes=$length;snapshotSha256=$hash;lines=@($text -split '\r?\n');reports=0;records=0}
}
function Check-Summary($group,$payload) {
    $expected = [ordered]@{reportId=$group.reportId;chunks=$group.total;bytes=$utf8.GetByteCount($group.json)}
    foreach ($name in @('complete','role','checks')) {
        $value = Field $payload $name
        if ($null -ne $value) { $expected[$name]=$value }
    }
    foreach ($role in @('host','peer')) {
        $value = Field $payload ($role+'UserId')
        if ($null -eq $value) { $value = Field (Field $payload 'playersUserId') $role }
        if ($null -ne $value) { $expected[$role+'UserId']=$value }
    }
    if ($null -ne (Field $payload 'failure')) { $expected['failure']='see complete report chunks' }
    $after = Field $payload 'afterLast'
    if ($null -ne $after) {
        $expected['afterNodes']=Field $after 'resourceNodes'; $expected['afterParts']=Field $after 'resourceParts'; $expected['generation']=Field $after 'generation'
    }
    Assert-Same $group.summary.payload $expected "$($group.source)/$($group.reportId) compact summary"
}
function Read-Reports($source) {
    $groups = @{}; $lineNumber = 0
    $allowed = if ($source.role -eq 'server') { @('SERVER_STAGE','BEFORE_LAST_KICK','COMPLETE','INCOMPLETE') } else { @('CLIENT_STAGE','CLIENT_COMPLETE','CLIENT_INCOMPLETE') }
    foreach ($line in $source.lines) {
        $lineNumber++
        # Source echoes begin with '>'; accept only the actual CreatorOutput print.
        if ($line -notmatch '^(?<time>[^,]+),[^,]+,[^,]+,[^,]+,\w+ \[FLog::CreatorOutput\]\s*(?<message>.*)$') { continue }
        $message=$Matches.message; $time=$Matches.time
        if (!$message.StartsWith('[MULTIPLAYER_LIFECYCLE_R2 ',[StringComparison]::Ordinal)) { continue }
        Assert-True ($message -cmatch '^\[MULTIPLAYER_LIFECYCLE_R2 (?<tag>[A-Z_]+)\] (?<json>\{.*\})\s*$') "$($source.role) 第 $lineNumber 行 R2 紀錄截短或格式錯誤"
        $tag=$Matches.tag; $raw=$Matches.json
        Assert-True ($tag -ceq 'REPORT_CHUNK' -or $allowed -ccontains $tag) "$($source.role) 日誌含不相符的 stage：$tag"
        $stamp=[DateTimeOffset]::MinValue
        Assert-True ([DateTimeOffset]::TryParse($time,$culture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$stamp)) "R2 日誌時間無效：$time"
        $value=Parse-Json $raw "$($source.role) 第 $lineNumber 行"
        $id=Field $value 'reportId'
        Assert-True ($id -is [string] -and $id -cmatch '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') 'reportId 不是 GUID'
        $key=$id.ToLowerInvariant()
        if (!$groups.ContainsKey($key)) {
            Assert-True (!$globalIds.ContainsKey($key)) "reportId 跨來源重複：$id"
            $globalIds[$key]=$source.role
            $groups[$key]=[ordered]@{reportId=$id;source=$source.role;stage=$null;total=$null;chunks=@{};summary=$null;json=$null;payload=$null}
        }
        $group=$groups[$key]
        Assert-True ($group.reportId -ceq $id) "reportId 大小寫衝突：$id"
        $record=[ordered]@{source=$source.role;line=$lineNumber;timestampUtc=$stamp.ToUniversalTime().ToString('o');tag=$tag;rawLine=$line;payload=$value}
        $records.Add($record); $source.records++
        Assert-True ($records.Count -le 50000) 'R2 紀錄超出合理上限'
        if ($tag -ceq 'REPORT_CHUNK') {
            Assert-True ($utf8.GetByteCount($message) -lt 850) "chunk 原始行超過 helper 上限：$id"
            Assert-Same @($value.PSObject.Properties.Name | Sort-Object) @('index','reportId','stage','text','total') 'chunk 欄位'
            $index=Field $value 'index'; $total=Field $value 'total'; $stage=Field $value 'stage'; $text=Field $value 'text'
            Assert-True ((Is-Integer $index) -and (Is-Integer $total) -and $index -ge 1 -and $index -le $total -and $total -le 4096) "chunk index/total 無效：$id"
            Assert-True ($allowed -ccontains $stage) "chunk stage 與來源不符：$id"
            Assert-True ($text -is [string] -and $utf8.GetByteCount($text) -ge 1 -and $utf8.GetByteCount($text) -le 320) "chunk 非完整 UTF-8 或超過 320 bytes：$id"
            Assert-True ($null -eq $group.summary) "summary 後又出現 chunk：$id"
            if ($null -eq $group.stage) { $group.stage=$stage; $group.total=[int]$total }
            Assert-True ($group.stage -ceq $stage -and $group.total -eq $total) "chunk stage/total 衝突：$id"
            Assert-True (!$group.chunks.ContainsKey([int]$index)) "chunk index 重複／衝突：$id/$index"
            $group.chunks[[int]$index]=$record
        } else {
            Assert-True ($utf8.GetByteCount($message) -lt 700) "compact summary 超過 helper 上限：$id"
            Assert-True ($null -eq $group.summary) "compact summary 重複：$id"
            Assert-True ($group.stage -ceq $tag -and $group.chunks.Count -eq $group.total) "summary 前缺少完整 chunk／stage 不一致：$id"
            $group.summary=$record
        }
    }
    Assert-True ($groups.Count -gt 0) "$($source.role) 未找到 R2 原始報告"
    foreach ($group in $groups.Values) {
        Assert-True ($null -ne $group.summary -and $group.chunks.Count -eq $group.total) "缺少 chunk 或 matching summary：$($group.reportId)"
        $builder=[Text.StringBuilder]::new(); $previousLine=0
        for ($i=1;$i -le $group.total;$i++) {
            Assert-True ($group.chunks.ContainsKey($i)) "缺少 chunk $i：$($group.reportId)"
            $chunk=$group.chunks[$i]
            Assert-True ($chunk.line -gt $previousLine -and $chunk.line -lt $group.summary.line) "chunk 順序／summary 時序錯誤：$($group.reportId)"
            $previousLine=$chunk.line; [void]$builder.Append((Field $chunk.payload 'text'))
        }
        $group.json=$builder.ToString(); $group.payload=Parse-Json $group.json "$($group.reportId) 重組報告"
        Check-Summary $group $group.payload
        Assert-True ($group.stage -cnotmatch 'INCOMPLETE' -and $null -eq (Field $group.payload 'failure')) "R2 報告含失敗：$($group.reportId)"
        $reports.Add($group); $source.reports++
    }
}
function One-Report([string]$source,[string]$stage) {
    $items=@($reports | Where-Object { $_.source -ceq $source -and $_.stage -ceq $stage })
    Assert-True ($items.Count -eq 1) "$source 須恰有一份 $stage 完整報告"
    return $items[0]
}
function Check-Census($value,[string]$label,$expected) {
    $keys=@('players','phase','generation','resourceNodes','resourceParts','resourceNodeCount','managedUnits','managedBuildings','victimUnits','victimBuildings','peerUnits','peerBuildings','hostUserId','winnerId','winnerTeamId','aiCount','factionCount','lobbyPlayers','matchTime')
    Assert-Same @($value.PSObject.Properties.Name | Sort-Object) @($keys | Sort-Object) "$label census 欄位"
    foreach ($key in $keys) { if ($key -ne 'phase') { Assert-Number (Field $value $key) "$label.$key" } }
    Assert-Fields $value $expected $label
}
function Check-Walk($walk,[string]$label) {
    Assert-Fields $walk @{priority=101;serverConfirmed=$true} $label
    Assert-Number (Field $walk 'distanceMoved') "$label.distanceMoved"
    Assert-True ($walk.distanceMoved -gt 16) "$label 未離開出生點"
    foreach ($point in @('initial','queuedClient')) {
        foreach ($axis in @('x','y','z')) { Assert-Number (Field (Field $walk $point) $axis) "$label.$point.$axis" }
    }
    $initial=$walk.initial; $queued=$walk.queuedClient
    $distance=[math]::Sqrt([math]::Pow($queued.x-$initial.x,2)+[math]::Pow($queued.y-$initial.y,2)+[math]::Pow($queued.z-$initial.z,2))
    Assert-True ([math]::Abs($distance-$walk.distanceMoved) -lt 0.001) "$label 位移與座標不符"
}

try {
    $manifestFull=(Resolve-Path -LiteralPath $ManifestPath).Path
    $manifest=Parse-Json ([IO.File]::ReadAllText($manifestFull,$utf8)) 'R2 source manifest'
    $manifestHash=(Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash
    $baselineFull=Repo-Path $manifest.baselineManifest
    $baselineHash=Check-Hash $baselineFull $manifest.baselineManifestSha256
    $baseline=Parse-Json ([IO.File]::ReadAllText($baselineFull,$utf8)) '94-file baseline manifest'
    Assert-True ($manifest.baselineFilesMatched -eq 94) 'baselineFilesMatched 不是 94'
    $baselineMap=File-Map $baseline.files 94 'baseline manifest'
    $listedBaseline=File-Map $manifest.baselineFiles 94 'R2 baselineFiles'
    Assert-Same $baselineMap $listedBaseline '94 baseline 來源列'
    $added=File-Map $manifest.addedFiles 2 'R2 addedFiles'
    Assert-Same @($added.Keys | Sort-Object) @((Repo-Path 'tests/MultiplayerLifecycleTestsR2.lua'),(Repo-Path 'multiplayer-lifecycle-r2-validation.project.json') | Sort-Object) 'R2 新增檔範圍'
    $files=File-Map $manifest.files 96 'R2 files'
    $combined=@{}; foreach ($key in $baselineMap.Keys) { $combined[$key]=$baselineMap[$key] }
    foreach ($key in $added.Keys) { Assert-True (!$combined.ContainsKey($key)) 'R2 addedFiles 混入 baseline'; $combined[$key]=$added[$key] }
    Assert-Same $files $combined '96 來源列'
    $normalPath=Repo-Path $baseline.buildPath; $normalHash=Check-Hash $normalPath $baseline.buildSha256
    $validationPath=Repo-Path $manifest.validationBuildPath; $validationHash=Check-Hash $validationPath $manifest.validationBuildSha256
    $preserved=File-Map $manifest.preservedV1 4 'preservedV1'
    $protected=@($files.Keys)+@($preserved.Keys)+@($manifestFull,$baselineFull,$normalPath,$validationPath,(Join-Path $PSScriptRoot 'optimization-multiplayer-lifecycle-r2-evidence-parser.ps1'))
    foreach ($pair in @(@{role='server';path=$ServerLog},@{role='host';path=$HostLog},@{role='peer';path=$PeerLog})) { $snapshots.Add((Read-Snapshot $pair.path $pair.role)) }
    Assert-True (@($snapshots.path | Select-Object -Unique).Count -eq 3) '須使用三個不同的原始 server/host/peer 日誌'
    $jsonFull=[IO.Path]::GetFullPath($OutputJson); $textFull=[IO.Path]::GetFullPath($OutputText)
    Assert-True ($jsonFull -ine $textFull) 'JSON/TXT 輸出不得相同'
    foreach ($output in @($jsonFull,$textFull)) {
        Assert-True ((Split-Path -Parent $output) -ieq $PSScriptRoot) '證據輸出須在 tests 目錄'
        Assert-True ($protected -inotcontains $output -and @($snapshots.path) -inotcontains $output) '輸出不可覆蓋來源、manifest、build 或原始日誌'
        Assert-True (!(Test-Path -LiteralPath $output)) "輸出已存在，請指定新檔名保存這次擷取：$output"
    }
    foreach ($snapshot in $snapshots) { Read-Reports $snapshot }
    Assert-True ($reports.Count -eq 26) 'R2 完整工作流程須恰有 26 份重組報告'
    $server=One-Report 'server' 'COMPLETE'; $hostReportGroup=One-Report 'host' 'CLIENT_COMPLETE'; $peerReportGroup=One-Report 'peer' 'CLIENT_COMPLETE'
    $beforeKick=One-Report 'server' 'BEFORE_LAST_KICK'
    $s=$server.payload; $h=$hostReportGroup.payload; $p=$peerReportGroup.payload
    foreach ($item in @($s,$h,$p)) {
        Assert-Fields $item @{complete=$true} 'complete'
        Assert-True ((Is-Integer $item.checks) -and $item.checks -gt 0) 'checks 須為正整數'
    }
    Assert-Fields $s @{scope='server instances/public lifecycle attributes; no private cache, FPS or memory claim';firstKickIssued=$true;lastKickIssued=$true;peerCleanupAcknowledged=$true} 'server'
    Assert-Fields $h @{role='host';scope='actual client Humanoid walking, replicated instances and normal RTS commands';sharedHostCompleted=$true;normalStopConfirmed=$true} 'host'
    Assert-Fields $p @{role='peer';scope='actual client Humanoid walking, replicated instances and normal RTS commands';sharedOwnershipCompleted=$true;playerRemovingSeen=$true} 'peer'
    $hostId=$s.playersUserId.host; $peerId=$s.playersUserId.peer
    Assert-True ((Is-Integer $hostId) -and (Is-Integer $peerId) -and $hostId -ne 0 -and $peerId -ne 0 -and $hostId -ne $peerId) '須為兩位不同真 Player ID（可為 Studio 負 ID）'
    Assert-True ($s.playerNames.host -is [string] -and $s.playerNames.peer -is [string] -and $s.playerNames.host -ne $s.playerNames.peer) '兩位玩家名稱不完整／重複'
    Assert-True ($s.session -is [string] -and $s.session -cmatch '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') 'server session 不是 GUID'
    Assert-Fields $h @{playerUserId=$hostId;hostUserId=$hostId;peerUserId=$peerId} 'host IDs'
    Assert-Fields $p @{playerUserId=$peerId;hostUserId=$hostId;peerUserId=$peerId} 'peer IDs'
    Assert-Fields $s.clientComplete @{host=$true;peer=$true} 'server CLIENT_DONE ACK'
    Assert-Fields $s.playerRemovingSeen @{host=$true;peer=$true} '真 PlayerRemoving'
    # These constants are from the hash-verified baseline's Small-map R2 scenario.
    $config=[IO.File]::ReadAllText((Repo-Path 'src/ReplicatedStorage/GameData/GameConfig.lua'),$utf8)
    Assert-True ($config -match 'ResourceNodeTargets\s*=\s*\{\s*Small\s*=\s*(\d+)') '無法讀取驗證來源 Small 資源數'
    $target=[int]$Matches[1]
    $zero=@{resourceNodes=0;resourceParts=0;resourceNodeCount=0;managedUnits=0;managedBuildings=0;victimUnits=0;victimBuildings=0;peerUnits=0;peerBuildings=0;hostUserId=0;winnerId=0;winnerTeamId=0;aiCount=0;factionCount=0;lobbyPlayers=0;matchTime=0;phase='Lobby'}
    Check-Census $s.initial 'server initial' $zero; Assert-Fields $s.initial @{players=2;generation=0} 'server initial'
    $playing=@{players=2;phase='Playing';generation=1;resourceNodes=$target;resourceNodeCount=$target;managedUnits=9;managedBuildings=3;victimUnits=5;victimBuildings=2;peerUnits=4;peerBuildings=1;hostUserId=$hostId;winnerId=0;aiCount=0;factionCount=2;lobbyPlayers=2}
    foreach ($item in @(@{value=$s.before;label='server before'},@{value=$h.before;label='host before'},@{value=$p.before;label='peer before'})) {
        Check-Census $item.value $item.label $playing
        Assert-True ($item.value.resourceParts -gt 0) "$($item.label) 未觀察到資源零件"
    }
    $ended=@{players=1;phase='Ended';generation=1;resourceNodes=$target;resourceNodeCount=$target;managedUnits=4;managedBuildings=1;victimUnits=0;victimBuildings=0;peerUnits=4;peerBuildings=1;hostUserId=$peerId;winnerId=$peerId;aiCount=0;factionCount=2;lobbyPlayers=2}
    Check-Census $s.afterHost 'server afterHost' $ended; Check-Census $p.afterHost 'peer afterHost' $ended
    Assert-Same $s.afterHost.resourceParts $s.before.resourceParts 'server Ended 保留零件'
    Assert-Same $p.afterHost.resourceParts $p.before.resourceParts 'peer Ended 保留收到的零件'
    Check-Census $s.afterLast 'server afterLast' $zero; Assert-Fields $s.afterLast @{players=0;generation=2} 'server afterLast'
    Assert-Same $s.generatedReferencesRemoved $target '生成資源原引用清理數'
    Assert-Fields $beforeKick.payload @{peerCleanupAcknowledged=$true} 'BEFORE_LAST_KICK'
    Assert-Same $beforeKick.payload.before $s.before 'BEFORE_LAST_KICK before'
    Assert-Same $beforeKick.payload.afterHost $s.afterHost 'BEFORE_LAST_KICK afterHost'
    Assert-True ($beforeKick.summary.line -lt $server.chunks[1].line) '最後 Kick 前觀察須先於 COMPLETE'
    $sequences=@{host=@('CLIENT_STARTED','WALK_QUEUED','HOST_READY','CLIENT_DONE');peer=@('CLIENT_STARTED','WALK_QUEUED','PEER_QUEUED','OWNERSHIP_READY','CLEANUP_ARMED','PEER_CLEANUP','CLIENT_DONE')}
    $accepted=@($s.clientStages); $serverStages=@($reports | Where-Object { $_.source -ceq 'server' -and $_.stage -ceq 'SERVER_STAGE' } | Sort-Object { $_.summary.line })
    Assert-True ($accepted.Count -eq 11 -and $serverStages.Count -eq 11) 'server 須接受並記錄 11 個 CLIENT stages'
    for ($i=0;$i -lt 11;$i++) {
        $entry=$accepted[$i]
        Assert-True ($entry.role -ceq 'host' -or $entry.role -ceq 'peer') 'server client stage 角色錯誤'
        Assert-Fields $serverStages[$i].payload @{role=$entry.role;stage=$entry.stage;checks=$entry.checks} 'server stage log 與 final report'
        Assert-Same $entry.checks $entry.data.checks 'server stage data checks'
        Assert-True ($serverStages[$i].summary.line -lt $beforeKick.chunks[1].line) '所有 server CLIENT_DONE 須先於最後 Kick'
    }
    foreach ($role in @('host','peer')) {
        $clientStages=@($reports | Where-Object { $_.source -ceq $role -and $_.stage -ceq 'CLIENT_STAGE' } | Sort-Object { $_.summary.line })
        $roleAccepted=@($accepted | Where-Object { $_.role -ceq $role })
        Assert-Same @($clientStages | ForEach-Object { $_.payload.stage }) $sequences[$role] "$role client stage 順序"
        Assert-Same @($roleAccepted.stage) $sequences[$role] "$role server ACK 順序"
        $previousChecks=0
        for ($i=0;$i -lt $clientStages.Count;$i++) {
            Assert-Fields $clientStages[$i].payload @{role=$role;checks=$roleAccepted[$i].checks} "$role client/server stage"
            Assert-True ((Is-Integer $roleAccepted[$i].checks) -and $roleAccepted[$i].checks -ge $previousChecks -and $roleAccepted[$i].checks -le 200) "$role checks 非有效遞增計數"
            $previousChecks=$roleAccepted[$i].checks
        }
        $complete=if ($role -eq 'host') {$hostReportGroup} else {$peerReportGroup}
        $done=$clientStages[-1]; $ack=$roleAccepted[-1]
        Assert-True ($clientStages[-2].summary.line -lt $complete.chunks[1].line -and $complete.summary.line -lt $done.chunks[1].line) "$role CLIENT_COMPLETE 必須先印完所有 chunks/summary 才 CLIENT_DONE"
        Assert-Fields $ack.data @{complete=$true;checks=$complete.payload.checks} "$role CLIENT_DONE data"
        Check-Walk $complete.payload.walk "$role walk"
        $walk=$roleAccepted[1].data.walk
        foreach ($name in @('initial','queuedClient','distanceMoved','priority')) { Assert-Same (Field $walk $name) (Field $complete.payload.walk $name) "$role server WALK_QUEUED.$name" }
        $spawn=Field $s.serverSpawn $role; $queue=Field $s.serverQueue $role
        foreach ($axis in @('x','y','z')) { Assert-Number (Field $spawn $axis) "$role serverSpawn.$axis"; Assert-Number (Field $queue $axis) "$role serverQueue.$axis" }
        Assert-True (($spawn.x*$spawn.x + [math]::Pow($spawn.z-2103,2)) -le 64 -and [math]::Abs($spawn.y-4) -le 8) "$role serverSpawn 不在大廳出生範圍"
        Assert-True (($queue.x*$queue.x + [math]::Pow($queue.z-2048,2)) -le 196 -and $queue.y -ge -3 -and $queue.y -le 18) "$role serverQueue 不在傳送門範圍"
        Assert-Fields $queue @{queued=$true;anchored=$true;players=$(if ($role -eq 'host') {1} else {2})} "$role server Queue ACK"
        Assert-True ((Is-Integer $queue.joinOrder) -and $queue.joinOrder -gt 0) "$role Queue joinOrder 無效"
    }
    $hostReady=@($accepted | Where-Object {$_.role -ceq 'host' -and $_.stage -ceq 'HOST_READY'})[0]
    $ownership=@($accepted | Where-Object {$_.role -ceq 'peer' -and $_.stage -ceq 'OWNERSHIP_READY'})[0]
    $cleanup=@($accepted | Where-Object {$_.role -ceq 'peer' -and $_.stage -ceq 'PEER_CLEANUP'})[0]
    $armed=@($accepted | Where-Object {$_.role -ceq 'peer' -and $_.stage -ceq 'CLEANUP_ARMED'})[0]
    Assert-Fields $hostReady.data @{sharedHostCompleted=$true;normalStopConfirmed=$true} 'HOST_READY 正常命令'
    Assert-Fields $ownership.data @{sharedOwnershipCompleted=$true} 'OWNERSHIP_READY 正常所有權'
    Assert-Fields $armed.data @{victimUserId=$hostId;eventArmed=$true} '離開事件已監聽'
    Assert-Fields $cleanup.data @{playerRemovingSeen=$true} 'peer 真離開 ACK'
    Assert-Same $hostReady.data.census $h.before 'host 自身 census 回報'
    Assert-Same $ownership.data.census $p.before 'peer 自身 census 回報'
    Assert-Same $cleanup.data.census $p.afterHost 'peer 離開後 census 回報'
    $stageNames=@($accepted | ForEach-Object {$_.role+':'+$_.stage})
    Assert-True ([array]::IndexOf($stageNames,'host:HOST_READY') -lt [array]::IndexOf($stageNames,'peer:OWNERSHIP_READY') -and
        [array]::IndexOf($stageNames,'host:CLIENT_DONE') -lt [array]::IndexOf($stageNames,'peer:PEER_CLEANUP')) '跨端工作流程順序錯誤'
    $limitations=@(
        '僅接受此次隔離 Studio Server & Clients 雙人工作流程；不等同完整遊戲或所有機型驗證。',
        '來源與兩份 build 在解析時吻合 manifest；原始日誌沒有執行中 VM source hash，不能單憑 parser 證明載入的 place 身分。',
        'resourceParts 是各 VM 實例／客戶端收到的 census；沒有把客戶端零件數當作完整視覺複製或伺服器記憶體證據。',
        '未知模型 metadata、正常成本／所有權與命令檢查由 hash 對應 helper/Shared tests 的完成斷言支持；沒有另造逐項結果。',
        '不包含 FPS、CPU、記憶體、滿人口效能、聲音聽感或全部建築畫面驗證。',
        '跨 VM UTC 時鐘可能有偏移；CLIENT_DONE 採各原始日誌行序與 server 接受順序核對，沒有假設跨日誌同秒順序。')
    $sourceEvidence=@($snapshots | ForEach-Object {[ordered]@{role=$_.role;path=$_.path;snapshotBytes=$_.snapshotBytes;snapshotSha256=$_.snapshotSha256;linesRead=$_.lines.Count;reports=$_.reports;records=$_.records}})
    $reportEvidence=@($reports | Sort-Object @{Expression={$_.source}},@{Expression={[int]$_.summary.line}} | ForEach-Object {
        $currentGroup=$_
        $chunkLines=@(1..$currentGroup.total | ForEach-Object {$currentGroup.chunks[[int]$_].line})
        [ordered]@{source=$currentGroup.source;reportId=$currentGroup.reportId;stage=$currentGroup.stage;chunks=$currentGroup.total;utf8Bytes=$utf8.GetByteCount($currentGroup.json);summaryLine=$currentGroup.summary.line;summaryTimestampUtc=$currentGroup.summary.timestampUtc;chunkLines=$chunkLines;summary=$currentGroup.summary.payload;report=$currentGroup.payload}
    })
    $evidence=[ordered]@{
        schemaVersion=2;capturedUtc=[DateTimeOffset]::UtcNow.ToString('o');complete=$true;acceptedScope='R2 two-client normal walking, multiplayer commands and true player-removal lifecycle';performanceAccepted=$false
        sourceManifest=$manifestFull;sourceManifestSha256=$manifestHash;baselineManifest=$baselineFull;baselineManifestSha256=$baselineHash;baselineFilesMatched=94;sourceFilesMatched=96;preservedV1FilesMatched=4
        defaultBuild=$normalPath;defaultBuildSha256=$normalHash;validationBuild=$validationPath;validationBuildSha256=$validationHash
        parserPath=(Join-Path $PSScriptRoot 'optimization-multiplayer-lifecycle-r2-evidence-parser.ps1');parserSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'optimization-multiplayer-lifecycle-r2-evidence-parser.ps1') -Algorithm SHA256).Hash
        logs=$sourceEvidence;reportCount=$reports.Count;recordCount=$records.Count;serverReport=$s;hostReport=$h;peerReport=$p;reassembledReports=$reportEvidence;limits=$limitations
    }
    $text=[Collections.Generic.List[string]]::new()
    $text.Add('R2 雙端正常命令／真正離開生命週期證據：完整 chunks、summary、CLIENT_DONE 及來源／build 核對通過。')
    $text.Add("Server checks=$($s.checks); Host=$($h.checks); Peer=$($p.checks); reassembled reports=$($reports.Count); raw R2 records=$($records.Count)")
    $text.Add("Manifest: $manifestFull SHA256=$manifestHash; baseline=94; sources=96; preservedV1=4")
    $text.Add("Default build SHA256: $normalHash"); $text.Add("R2 validation build SHA256: $validationHash")
    foreach ($source in $sourceEvidence) { $text.Add("$($source.role) log: $($source.path); bytes=$($source.snapshotBytes); snapshot SHA256=$($source.snapshotSha256)") }
    $text.Add(''); foreach ($limit in $limitations) {$text.Add('限制：'+$limit)}
    foreach ($source in $sourceEvidence) {
        $text.Add(''); $text.Add('原始 '+$source.role+' 日誌 R2 紀錄（保留 chunks 與摘要）：')
        foreach ($record in @($records | Where-Object {$_.source -ceq $source.role} | Sort-Object {[int]$_.line})) { $text.Add("Line $($record.line): $($record.rawLine)") }
    }
    # No result is written before all checks above succeed. Refuse existing outputs.
    [IO.File]::WriteAllText($jsonFull,($evidence | ConvertTo-Json -Depth 60),$utf8)
    [IO.File]::WriteAllLines($textFull,$text.ToArray(),$utf8)
    Write-Output "PASS R2 lifecycle evidence: server=$($s.checks), host=$($h.checks), peer=$($p.checks); 26 complete reassembled reports; 94 baseline / 96 sources; both builds match."
    Write-Output "JSON: $jsonFull"
    Write-Output "TXT: $textFull"
} catch {
    Write-Error "R2 evidence INCOMPLETE / rejected. No complete-pass evidence is authorized by this run. $($_.Exception.Message)"
    exit 1
}
