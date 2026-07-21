[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ConfigPath,
    [ValidateSet('TestApi','Discover','PreFlight','Transfer','Validate','SizeCheck','Report','Certificate','Finalize','DestInventory','Menu')] [string] $Action = 'Menu',
    [ValidateSet('Cancelled','Incomplete')] [string] $FinalizeStatus = 'Incomplete',
    [ValidateSet('FirstPass','Delta','Resume')] [string] $Mode = 'FirstPass',
    [ValidateSet('AddMissing','NewerWins')] [string] $DeltaMode = 'NewerWins',
    [string] $OnlySpace,
    [string] $AuditPath,
    [string] $Spaces,
    [int]    $SpoolAhead = 3,
    [int]    $MaxParallelSpaces = 1,
    [string] $ResultDir = '',
    [switch] $NonInteractive,
    [switch] $VerboseFiles,
    [switch] $UseEnumCache,
    [switch] $FailedOnly,
    [string] $FailedFromAudit,
    [switch] $GuiMode,
    [switch] $Execute,
    [int]    $TrialLimitForTest = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$script:VerboseFiles = [bool]$VerboseFiles
$script:GuiMode = [bool]$GuiMode
$script:UseEnumCache = [bool]$UseEnumCache
function Lz67aab01d86 { param([int]$Done,[int]$Total,[int64]$BytesDone,[int64]$BytesTotal,[string]$Space,
        [int]$SmallDone=0,[int]$SmallTotal=0,[int64]$LargeBytesDone=0,[int64]$LargeBytesTotal=0,[int]$Final=1)
    if ($script:GuiMode) { Write-Host "##PROGRESS##|$Done|$Total|$BytesDone|$BytesTotal|$SmallDone|$SmallTotal|$LargeBytesDone|$LargeBytesTotal|$Final|$Space" }
}
$script:LastThrMax = -1; $script:LastThrPaused = $false
function Lzc5f2c77844 { param([int]$Max,[int]$HardMax,[int]$PausedSeconds,[int]$Events,[int]$Code=0)
    if ($script:GuiMode) { Write-Host "##THROTTLE##|$Max|$HardMax|$PausedSeconds|$Events|$Code" }
}
$script:LogFile = $null
$script:LegacyStateNoticeDone = $false
$script:HttpTimeoutSec     = 120
$script:TransferTimeoutSec = 3600
$script:EmailMaxAttachMB   = 3
$script:EmailDefaultSubject = 'Liscaragh migration - {Action} {Outcome}: {JobName}'
$script:ToolVersionCache   = $null
$script:EmailMsgBody       = $null
$script:EtaSmallDone      = 0
$script:EtaSmallTotal     = 0
$script:EtaLargeBytesDone = [int64]0
$script:EtaLargeBytesTotal= [int64]0
$script:fIdxRef = $null; $script:copiedRef = $null; $script:bytesRef = $null; $script:zeroRef = $null
$script:verifyFailRef = $null; $script:failedRef = $null
$script:streamCountRef = $null; $script:streamBytesRef = $null
$script:EnsuredFolders = @{}
$script:UpHttp = $null
$script:RetryEvents = 0
$script:SrcTotal = 0
$script:DattoPace = [hashtable]::Synchronized(@{ GapMs = 0; NextTicks = [int64]0; MaxMs = 8000; FloorMs = 0; HeadersSeen = $false; ReqCount = 0; WindowStartTicks = [int64]0; LastProbeTicks = [int64]0 })
$script:DattoLastHeaders = $null
$script:DattoBudgetLogAt = $null
function Lz598441362f {
    $p = $script:DattoPace
    if ($p.GapMs -le 0) { return }
    $sleepMs = 0
    [System.Threading.Monitor]::Enter($p.SyncRoot)
    try {
        $now  = [DateTime]::UtcNow.Ticks
        $slot = [math]::Max($now, $p.NextTicks)
        $sleepMs = [int](($slot - $now) / [TimeSpan]::TicksPerMillisecond)
        $p.NextTicks = $slot + ($p.GapMs * [TimeSpan]::TicksPerMillisecond)
    } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
    if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
}
function Lz18d0a721ab {
    param($Headers)
    $r = @{ HasBudget=$false; Remaining=$null; Limit=$null; ResetSec=$null; Raw=@() }
    if (-not $Headers) { return $r }
    $keys = @(); try { $keys = @($Headers.Keys) } catch {}
    foreach ($k in $keys) {
        $kl = "$k".ToLowerInvariant()
        if ($kl -notmatch 'rate.?limit|ratelimit') { continue }
        if ($kl -match 'retry') { continue }
        $v = $Headers[$k]; if ($v -is [System.Array]) { $v = $v[0] }
        $v = "$v"; $r.Raw += "$k=$v"
        $num = ($v -replace '[^0-9.]','')
        if ($kl -match 'remain') { if ($num) { $r.Remaining = [double]$num } }
        elseif ($kl -match 'reset') {
            if ($num) { $n = [double]$num; if ($n -gt 1000000000) { $r.ResetSec = $n - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } else { $r.ResetSec = $n } }
            else { try { $r.ResetSec = ([datetime]$v).ToUniversalTime().Subtract([datetime]::UtcNow).TotalSeconds } catch {} }
            if (($null -ne $r.ResetSec) -and ($r.ResetSec -lt 0)) { $r.ResetSec = 0 }
        }
        elseif ($kl -match 'limit') { if ($num) { $r.Limit = [double]$num } }
    }
    if ($null -ne $r.Remaining) { $r.HasBudget = $true }
    return $r
}
function Lz086388ac1f {
    param($Headers)
    $p = $script:DattoPace
    $rl = Lz18d0a721ab $Headers
    if (-not $rl.HasBudget) {
        [System.Threading.Monitor]::Enter($p.SyncRoot)
        try {
            $nowT = [DateTime]::UtcNow.Ticks
            if ($p.WindowStartTicks -le 0) { $p.WindowStartTicks = $nowT; $p.ReqCount = 1 } else { $p.ReqCount++ }
            if ($p.GapMs -gt $p.FloorMs) { $p.GapMs = [math]::Max($p.FloorMs, $p.GapMs - 25) }
            if ($p.FloorMs -gt 0) {
                if ($p.LastProbeTicks -le 0) { $p.LastProbeTicks = $nowT }
                elseif ((($nowT - [int64]$p.LastProbeTicks) / [double][TimeSpan]::TicksPerSecond) -ge 30) { $p.FloorMs = [int][math]::Floor($p.FloorMs * 0.95); $p.LastProbeTicks = $nowT }
            }
        } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
        return
    }
    if (-not $p.HeadersSeen) { $p.HeadersSeen = $true; Lz12e519cc30 INFO "  Datto rate budget detected ($([string]::Join(', ', $rl.Raw))). Flying close: pacing to stay just under it and avoid forced pauses." }
    $limit   = if ($rl.Limit -and $rl.Limit -gt 0) { $rl.Limit } else { [math]::Max($rl.Remaining, 1) }
    $ratio   = $rl.Remaining / $limit
    $reset   = if ($null -ne $rl.ResetSec) { [double]$rl.ResetSec } else { 0 }
    $reserve = [math]::Max(2, [math]::Floor($limit * 0.05))
    $note = ''
    if ($rl.Remaining -le $reserve -and $reset -gt 0) {
        $waitS = [math]::Min($reset + 1, 60)
        [System.Threading.Monitor]::Enter($p.SyncRoot)
        try {
            $p.NextTicks = [math]::Max([int64]$p.NextTicks, [int64]([DateTime]::UtcNow.Ticks + [int64]($waitS * [TimeSpan]::TicksPerSecond)))
            $p.GapMs = [math]::Min($p.MaxMs, [int](($reset * 1000.0) / [math]::Max($rl.Remaining, 1)))
        } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
        $note = "Datto budget nearly spent (remaining $([int]$rl.Remaining) of $([int]$limit)); holding ~$([int]$waitS)s for it to reset, which avoids a forced pause."
    }
    elseif ($ratio -le 0.30 -and $reset -gt 0) {
        $usable = [math]::Max(1, $rl.Remaining - $reserve)
        $target = [math]::Min($p.MaxMs, [math]::Max(0, [int](($reset * 1000.0) / $usable)))
        [System.Threading.Monitor]::Enter($p.SyncRoot)
        try { $p.GapMs = $target } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
        $note = "Datto budget at $([int]($ratio*100))% (remaining $([int]$rl.Remaining) of $([int]$limit)); easing to ~$target ms between reads to glide under the limit."
    }
    else {
        [System.Threading.Monitor]::Enter($p.SyncRoot)
        try { $p.GapMs = [math]::Min($p.GapMs, 25) } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
    }
    if ($note) {
        $now = [DateTime]::UtcNow
        if ((-not $script:DattoBudgetLogAt) -or (($now - $script:DattoBudgetLogAt).TotalSeconds -ge 10)) { $script:DattoBudgetLogAt = $now; Lz12e519cc30 INFO "  $note" }
    }
}
function Lz699ea8d8d6 {
    $p = $script:DattoPace
    [System.Threading.Monitor]::Enter($p.SyncRoot)
    try {
        $cur = [int]$p.GapMs
        $base = if ($cur -lt 150) { 300 } else { $cur }
        $learned = [int][math]::Min([int]$p.MaxMs, [int][math]::Ceiling($base * 1.5))
        $p.GapMs = $learned; $p.FloorMs = $learned
        $p.ReqCount = 0; $p.WindowStartTicks = [int64]0; $p.LastProbeTicks = [int64]0
        $txt = " Slowing the read rate to about $learned ms between requests and holding there; this settles after the first few."
    } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
    return $txt
}
$script:DirectPutOk = $null
$script:SmallFilePutThreshold = 60MB
$script:OmitFsi = $false
$script:AuditFile = $null
$script:AuditWriteFails = 0
$script:ExitCode  = 0
$script:StopTag = '##CLEANSTOP##'
$script:ChunkSize = 10MB
$script:SpoolEncrypt = $true
$script:SpoolKey = $null
$script:TrialFileLimit = 20
$script:TrialCap = $null
$script:TrialFilesRemaining = 0
$script:TrialCapped = $false
$script:TrialLedgerKey = $null
$script:TrialBucket = ''
$script:LicencePublicKey = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEMOOjrKfrPG0mI1XtA+iXZVOwtjp075WeGEYaNZxG0TyVvAp6B9SZ3AAX5Ue7AxQrrwTfDzzX2lIgT7TmVKt9XA=='
$script:LicenceInfo = $null
$script:ScopeRefId = ''
$script:ExcludePatterns = @()
$script:IncludePatterns = @()
$script:MaxFileBytes = [int64]0
$script:LargeFileBytes = 25MB
$script:ModifiedAfterUtc  = $null
$script:ModifiedBeforeUtc = $null
$script:AssessmentTopFiles = 20
$script:FailedOnlySet = $null
$script:CurrentEnumSpace = ''
$script:RegPath = 'HKCU:\Software\DattoMigration'
function Get-RegSetting { param([string]$Name) try { return [string]((Get-ItemProperty -Path $script:RegPath -Name $Name -ErrorAction Stop).$Name) } catch { return $null } }
function Expand-ConfigTokens {
    param($Node)
    if ($null -eq $Node) { return }
    foreach ($p in @($Node.PSObject.Properties)) {
        $v = $p.Value
        if ($v -is [string]) {
            if ($v -match '^reg:(.+)$') { $p.Value = [string](Get-RegSetting $Matches[1]) }
        } elseif ($v -is [System.Management.Automation.PSCustomObject]) {
            Expand-ConfigTokens $v
        }
    }
}
function Import-MigrationConfig {
    param([string] $Path)
    if (-not (Test-Path $Path)) { throw "Config not found at '$Path'." }
    $cfg = (Unprotect-ConfigText (Get-Content $Path -Raw)) | ConvertFrom-Json
    Expand-ConfigTokens $cfg
    if ($cfg.datto.provider -ne 'LocalSim') {
        $eu = [string]$cfg.datto.endpointUrl
        if ($eu -and $eu -notmatch '^(?i)https://') {
            throw "The Datto endpoint URL must start with https:// so file transfers are encrypted. It is currently '$eu'. Correct it in Settings, under API settings."
        }
    }
    foreach ($p in @($cfg.run.logRoot, $cfg.run.reportRoot, $cfg.run.stateRoot, $cfg.run.tempWorkingFolder)) {
        if ($p -and -not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    return $cfg
}
function Lzffe69bba89 {
    param($Config, [string] $Stage, [string] $Friendly = '')
    if (-not $Friendly) {
        $Friendly = switch ($Stage) {
            'api-transfer-FirstPass' { 'Upload all files' }
            'api-transfer-Delta'     { 'Sync new and changed' }
            'api-sizecheck'          { 'Compare sizes' }
            'api-validation'         { 'Verify files arrived' }
            'api-destinv'            { 'Destination read' }
            'api-discovery'          { 'List projects' }
            'api-preflight'          { 'Readiness checks' }
            'api-report'             { 'Build report' }
            'api-certificate'        { 'Completion certificate' }
            'api-finalize'           { 'Record outcome' }
            'api-permissions'        { 'Permissions plan' }
            'api-test'               { 'Connection test' }
            default                  { $Stage }
        }
    }
    $script:LogFile = Join-Path $Config.run.logRoot ("$Friendly - " + (Get-Date -Format 'yyyy-MM-dd HH.mm.ss') + " - $Stage-$PID.log")
    $tv = Lz27226ed768
    Lz12e519cc30 INFO ("=== Stage '$Stage' started (pid $PID" + $(if ($tv) { ", v$tv" } else { '' }) + ") ===")
}
$script:ConfigEntropy   = [Text.Encoding]::UTF8.GetBytes('Liscaragh.DattoMigration.config.v1')
$script:ConfigEncMarker = 'LZCFG1:'
function Unprotect-ConfigText {
    param([string]$Text)
    if ($null -eq $Text -or -not $Text.StartsWith($script:ConfigEncMarker)) { return $Text }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop | Out-Null
        $b = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($Text.Substring($script:ConfigEncMarker.Length)), $script:ConfigEntropy, 'CurrentUser')
        return [Text.Encoding]::UTF8.GetString($b)
    } catch {
        throw "This job's settings file is encrypted for a different Windows account or machine and cannot be read here. Run the tool under the account that installed it, or re-run setup."
    }
}
function Lz73f26517ca {
    param([string]$Name)
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop | Out-Null
        $b64 = [string]((Get-ItemProperty -Path 'HKCU:\Software\DattoMigration\Secure' -Name $Name -ErrorAction Stop).$Name)
        if (-not $b64) { return $null }
        $ent = [Text.Encoding]::UTF8.GetBytes('Liscaragh.DattoMigration.v1')
        $b = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($b64), $ent, 'CurrentUser')
        return [Text.Encoding]::UTF8.GetString($b)
    } catch { return $null }
}
function Resolve-Secret {
    param([string] $Value)
    if ("$Value" -match '^env:(.+)$') {
        $n = $Matches[1]
        $v = [Environment]::GetEnvironmentVariable($n, 'User')
        if (-not $v) { $v = [Environment]::GetEnvironmentVariable($n, 'Machine') }
        if (-not $v) { $v = [Environment]::GetEnvironmentVariable($n) }
        if (-not $v) { $v = Lz73f26517ca -Name $n }
        if (-not $v) { throw "Environment variable '$n' is empty (referenced by env: in config). In plain terms: a required password or secret has not been set up on this computer yet. Re-run the setup, or ask your IT contact to set it." }
        return $v
    }
    return $Value
}
function Lz12e519cc30 {
    param([ValidateSet('INFO','WARN','ERROR','SKIP','OK')] [string] $Level, [string] $Message)
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'o'), $Level, $Message
    $c = @{ ERROR='Red'; WARN='Yellow'; SKIP='DarkGray'; OK='Green'; INFO='Gray' }[$Level]
    Write-Host $line -ForegroundColor $c
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line }
}
function Lz3c19440102 {
    param(
        [string]$Space, $Item, [string]$Status, [string]$Reason = '',
        [int64]$DestSize = 0, [string]$DestPath = '', [string]$Method = '',
        [int]$Retries = 0, [double]$DurationMs = 0, [double]$DownloadMs = 0, [string]$ErrorMsg = '',
        [string]$DestHash = ''
    )
    if (-not $script:AuditFile) { return }
    $now = Get-Date
    $rec = [pscustomobject][ordered]@{
        TimestampUtc      = $now.ToUniversalTime().ToString('o')
        TimestampLocal    = $now.ToString('yyyy-MM-dd HH:mm:ss')
        Space             = $Space
        SourcePath        = $Item.RelativePath
        DestPath          = $DestPath
        Renamed           = [bool](($Item.PSObject.Properties.Name -contains 'Renamed') -and $Item.Renamed)
        RenamedFrom       = if ($Item.PSObject.Properties.Name -contains 'RenamedFrom') { "$($Item.RenamedFrom)" } else { '' }
        Status            = $Status
        SourceSizeBytes   = [int64]$Item.Size
        DestSizeBytes     = [int64]$DestSize
        SourceModifiedUtc = "$($Item.ModifiedUtc)"
        SourceMd5         = "$($Item.Hash)"
        DestHash          = $DestHash
        Method            = $Method
        DownloadMs        = [int]$DownloadMs
        UploadMs          = [int]$DurationMs
        Retries           = $Retries
        Reason            = $Reason
        Error             = $ErrorMsg
    }
    $ok = $false
    for ($i=1;$i -le 5;$i++){ try { $rec | Export-Csv -Path $script:AuditFile -Append -NoTypeInformation -Encoding UTF8; $ok=$true; break } catch { Start-Sleep -Milliseconds (100*$i) } }
    if (-not $ok) { $script:AuditWriteFails++ }
}
$script:RenameFile     = $null
$script:CollisionFile  = $null
$script:RenameCount    = 0
$script:CollisionCount = 0
$script:RenameSeenDirs = $null
$script:FinalSeen      = $null
function Lz1eadd2ba8a {
    param([string]$Space, [string]$Original, [string]$Final)
    $script:RenameCount++
    if ($script:RenameFile) { try { [pscustomobject][ordered]@{ Space=$Space; Original=$Original; Final=$Final } | Export-Csv -Path $script:RenameFile -Append -NoTypeInformation -Encoding UTF8 } catch {} }
    $dir = ($Final -replace '/[^/]*$','')
    $key = "$Space|$dir"
    if ($script:RenameSeenDirs -is [hashtable] -and -not $script:RenameSeenDirs.ContainsKey($key)) {
        $script:RenameSeenDirs[$key] = $true
        Lz12e519cc30 INFO "  tidied name(s) to suit SharePoint in: $dir  (every change is listed in the report and the renames CSV)"
    }
}
function Lz702e99e4f7 {
    param([string]$Space, [string]$Final, [string]$FirstSource, [string]$SecondSource)
    $script:CollisionCount++
    if ($script:CollisionFile) { try { [pscustomobject][ordered]@{ Space=$Space; Final=$Final; FirstSource=$FirstSource; SecondSource=$SecondSource } | Export-Csv -Path $script:CollisionFile -Append -NoTypeInformation -Encoding UTF8 } catch {} }
    Lz12e519cc30 WARN "  NAME COLLISION in [$Space]: '$SecondSource' and '$FirstSource' both become '$Final' after tidying. In plain terms: two Datto items would land on the same SharePoint path, so one could overwrite the other. Both are in the collisions CSV and the report."
}
function Lzfcde41179d {
    param([string]$Space, [string]$Rp, $Item)
    $safe = ConvertTo-SafeRelPath $Rp
    if ($safe -ne $Rp) {
        Lz1eadd2ba8a -Space $Space -Original $Rp -Final $safe
        if ($Item) { $Item | Add-Member -NotePropertyName Renamed -NotePropertyValue $true -Force; $Item | Add-Member -NotePropertyName RenamedFrom -NotePropertyValue $Rp -Force }
    }
    if ($script:FinalSeen -is [hashtable]) {
        $k = "$Space|" + $safe.ToLowerInvariant()
        if ($script:FinalSeen.ContainsKey($k)) { $prev = $script:FinalSeen[$k]; if ($prev -ne $Rp) { Lz702e99e4f7 -Space $Space -Final $safe -FirstSource $prev -SecondSource $Rp } }
        else { $script:FinalSeen[$k] = $Rp }
    }
    return $safe
}
function Lz390831b78c {
    param([string]$Activity, [string]$Status, [int]$Current, [int]$Total, [int]$Id = 1)
    $pct = if ($Total -gt 0) { [int]([math]::Min(100, ($Current / $Total) * 100)) } else { 100 }
    try { Write-Progress -Id $Id -Activity $Activity -Status ("{0} ({1}/{2}, {3}%)" -f $Status,$Current,$Total,$pct) -PercentComplete $pct } catch {}
    return $pct
}
function Lz90772778a5 {
    param($ErrorRecord)
    $ra = 0
    try { $ra = [int](($ErrorRecord.Exception.Response.Headers.GetValues('X-Rate-Limit-Retry-After-Seconds'))[0]) } catch {}
    if (-not $ra) { try { $ra = [int]$ErrorRecord.Exception.Response.Headers['Retry-After'] } catch {} }
    if ($ra -lt 0) { $ra = 0 }
    return $ra
}
function Lz85d62aeb50 {
    param([int]$Attempt, $Throttle, [int]$RetryAfter = 0, [int]$Cap = 300)
    $base = [double]$Throttle.baseDelaySeconds; if ($base -le 0) { $base = 5 }
    if ($Throttle.honorRetryAfter -and $RetryAfter -gt 0) {
        $d = [math]::Min($RetryAfter, $Cap) + (Get-Random -Minimum 0.0 -Maximum 2.0)
        return [int][math]::Ceiling($d)
    }
    $exp = [math]::Min($base * [math]::Pow(2, $Attempt), $Cap)
    $d = ($exp / 2.0) + (Get-Random -Minimum 0.0 -Maximum ($exp / 2.0))
    return [int][math]::Max(1, [math]::Ceiling($d))
}
function Lz2b8bb14982 {
    param($ErrorRecord)
    $status = $null; try { $status = $ErrorRecord.Exception.Response.StatusCode.value__ } catch {}
    if ($status) { return $false }
    $m = ''
    try { $ex = $ErrorRecord.Exception; $d = 0; while ($ex -and $d -lt 8) { $m += ' ' + $ex.GetType().FullName + ' ' + $ex.Message; $ex = $ex.InnerException; $d++ } } catch {}
    return ($m -match '(?i)SSL|secure channel|connection was closed|connection was forcibly|actively refused|timed out|timeout|reset by peer|unexpectedly closed|transport connection|underlying connection|SocketException|IOException|WebException|HttpRequestException')
}
function Invoke-WithRetry {
    param([scriptblock] $Action, $Config, [string] $What = 'operation', [switch] $RetryNotFound)
    $t = $Config.run.throttle
    $retryCodes = @(408, 429, 500, 502, 503, 504)
    if ($RetryNotFound) { $retryCodes += 404 }
    $throttleMax = [math]::Max([int]$t.maxRetries, 40)
    for ($a = 1; $a -le $throttleMax; $a++) {
        try { return & $Action }
        catch {
            $status = $null; try { $status = $_.Exception.Response.StatusCode.value__ } catch {}
            $ra = Lz90772778a5 $_
            $isThrottle = (@(429, 503) -contains $status)
            $isTransient = Lz2b8bb14982 $_
            $cap = if ($isThrottle) { $throttleMax } else { [int]$t.maxRetries }
            if ((($retryCodes -notcontains $status) -and (-not $isTransient)) -or $a -ge $cap) {
                Lz12e519cc30 ERROR "$What failed (attempt $a): $($_.Exception.Message)"; throw
            }
            $delay = Lz85d62aeb50 -Attempt $a -Throttle $t -RetryAfter $ra
            if ($isTransient) {
                Lz12e519cc30 WARN "$What hit a network blip and is retrying in $delay s (attempt $a/$cap): $($_.Exception.Message). In plain terms: a brief connection glitch, not a real failure. It retries here so nothing has to wait for a later Sync."
            } elseif ($What -like 'Datto*' -and @(429,503) -contains $status) {
                $learnedTxt = Lz699ea8d8d6
                Lz12e519cc30 WARN "  Datto is limiting how fast we can read (HTTP $status). Pausing $delay s as it asked, then settling to the fastest rate your account allows.$learnedTxt This is normal on large projects, not an error, and it gets smarter after the first one or two."
                if ($script:GuiMode) { Write-Host "##STATUS##|Datto asked us to wait ~$delay s (its rate limit). Resuming automatically, nothing is stuck." }
                if ($script:GuiMode) {
                    $gapNow = 0; try { $gapNow = [int]$script:DattoPace.GapMs } catch {}
                    Write-Host "##DATTOPACE##|$delay|$gapNow|$status"
                }
            } else {
                $why = if ($t.honorRetryAfter -and $ra) { "server asked for $ra s" } else { "backing off" }
                Lz12e519cc30 WARN "$What retrying (HTTP $status): $why, waiting $delay s (attempt $a/$cap)."
            }
            $script:RetryEvents++
            Start-Sleep -Seconds $delay
        }
    }
}
function ConvertTo-Slug { param([string] $Name) return ($Name -replace '[^\w\-]', '-') -replace '-+', '-' }
function Test-DestructiveGate { param([switch]$Execute) if (-not $Execute){ Lz12e519cc30 WARN "Preview only: nothing will be uploaded. In plain terms: this is a safe rehearsal. Use 'Upload all files' when you are ready to do it for real." } return [bool]$Execute }
try { if ([System.Net.WebRequest]::DefaultWebProxy) { [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials } } catch {}
if (-not ('SpoolHttpException' -as [type])) {
    Add-Type -TypeDefinition 'public class SpoolHttpException : System.Exception { public object Response; public SpoolHttpException(string m, object r) : base(m) { Response = r; } }'
}
function New-SpoolKey {
    $k = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($k); $rng.Dispose()
    return ,$k
}
function Save-SpoolStream {
    param([System.IO.Stream]$InStream, [string]$OutFile, [byte[]]$Key)
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Key = $Key; $aes.GenerateIV()
        $fs = [System.IO.File]::Create($OutFile)
        try {
            $fs.Write([byte[]]::new(8), 0, 8)
            $fs.Write($aes.IV, 0, 16)
            $enc = $aes.CreateEncryptor()
            $cs = [System.Security.Cryptography.CryptoStream]::new($fs, $enc, [System.Security.Cryptography.CryptoStreamMode]::Write, $true)
            $buf = [byte[]]::new(1MB); $total = [int64]0
            while (($r = $InStream.Read($buf, 0, $buf.Length)) -gt 0) { $cs.Write($buf, 0, $r); $total += $r }
            $cs.FlushFinalBlock(); $cs.Dispose(); $enc.Dispose()
            $fs.Position = 0
            $fs.Write([BitConverter]::GetBytes([int64]$total), 0, 8)
            return $total
        } finally { $fs.Dispose() }
    } finally { $aes.Dispose() }
}
function Save-SpoolFile { param([string]$InFile, [string]$OutFile, [byte[]]$Key)
    $in = [System.IO.File]::OpenRead($InFile)
    try { return (Save-SpoolStream -InStream $in -OutFile $OutFile -Key $Key) } finally { $in.Dispose() }
}
function Get-SpoolLength { param([string]$File)
    $fs = [System.IO.File]::OpenRead($File)
    try { $b = [byte[]]::new(8); [void]$fs.Read($b, 0, 8); return [BitConverter]::ToInt64($b, 0) } finally { $fs.Dispose() }
}
function Open-SpoolRead {
    param([string]$File, [byte[]]$Key)
    $fs = [System.IO.File]::OpenRead($File)
    $b = [byte[]]::new(8); [void]$fs.Read($b, 0, 8); $len = [BitConverter]::ToInt64($b, 0)
    $iv = [byte[]]::new(16); [void]$fs.Read($iv, 0, 16)
    $aes = [System.Security.Cryptography.Aes]::Create(); $aes.Key = $Key; $aes.IV = $iv
    $cs = [System.Security.Cryptography.CryptoStream]::new($fs, $aes.CreateDecryptor(), [System.Security.Cryptography.CryptoStreamMode]::Read)
    return @{ Stream = $cs; Length = $len }
}
function Copy-SpoolToFile {
    param([string]$File, [string]$OutFile, [byte[]]$Key)
    $sp = Open-SpoolRead -File $File -Key $Key
    try { $out = [System.IO.File]::Create($OutFile); try { $sp.Stream.CopyTo($out) } finally { $out.Dispose() } }
    finally { $sp.Stream.Dispose() }
}
function Read-SpoolChunk {
    param($Stream, [int]$Count)
    $buf = [byte[]]::new($Count); $got = 0
    while ($got -lt $Count) { $r = $Stream.Read($buf, $got, $Count - $got); if ($r -le 0) { break }; $got += $r }
    if ($got -eq $Count) { return ,$buf }
    $sl = [byte[]]::new($got); if ($got -gt 0) { [Array]::Copy($buf, 0, $sl, 0, $got) }; return ,$sl
}
function Send-SpoolHttp {
    param([string]$Method = 'PUT', [string]$Uri, [hashtable]$Headers = @{}, [byte[]]$BodyBytes, $BodyStream, [int64]$ContentLength = -1, [string]$ContentRange = '', [int]$TimeoutSec = 3600)
    $h = [System.Net.Http.HttpClientHandler]::new(); $h.AllowAutoRedirect = $false
    $h.DefaultProxyCredentials = [System.Net.CredentialCache]::DefaultCredentials
    $c = [System.Net.Http.HttpClient]::new($h); $c.Timeout = [TimeSpan]::FromSeconds([math]::Max($TimeoutSec, 1))
    try {
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
        foreach ($k in $Headers.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) }
        if ($null -ne $BodyBytes) { $req.Content = [System.Net.Http.ByteArrayContent]::new($BodyBytes) }
        elseif ($null -ne $BodyStream) { $req.Content = [System.Net.Http.StreamContent]::new($BodyStream) }
        else { $req.Content = [System.Net.Http.ByteArrayContent]::new([byte[]]::new(0)) }
        $req.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        if ($ContentLength -ge 0) { $req.Content.Headers.ContentLength = $ContentLength }
        if ($ContentRange) { [void]$req.Content.Headers.TryAddWithoutValidation('Content-Range', $ContentRange) }
        $resp = $c.Send($req)
        $body = ''; try { $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch {}
        if (-not $resp.IsSuccessStatusCode) {
            $hdrs = @{}; foreach ($hk in $resp.Headers) { $hdrs[$hk.Key] = @($hk.Value)[0] }
            throw ([SpoolHttpException]::new("HTTP $([int]$resp.StatusCode) from ${Uri}: $body", ([pscustomobject]@{ StatusCode = [pscustomobject]@{ value__ = [int]$resp.StatusCode }; Headers = $hdrs })))
        }
        return @{ Content = $body; StatusCode = [int]$resp.StatusCode }
    } finally { $c.Dispose(); $h.Dispose() }
}
function Invoke-SpoolDownload {
    param([string]$Uri, [hashtable]$Headers = @{}, [string]$OutFile, [byte[]]$Key, [int]$TimeoutSec = 3600)
    $h = [System.Net.Http.HttpClientHandler]::new()
    $h.DefaultProxyCredentials = [System.Net.CredentialCache]::DefaultCredentials
    $c = [System.Net.Http.HttpClient]::new($h); $c.Timeout = [TimeSpan]::FromSeconds([math]::Max($TimeoutSec, 1))
    try {
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)
        foreach ($k in $Headers.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) }
        $resp = $c.Send($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        if (-not $resp.IsSuccessStatusCode) {
            $hdrs = @{}; foreach ($hk in $resp.Headers) { $hdrs[$hk.Key] = @($hk.Value)[0] }
            throw ([SpoolHttpException]::new("HTTP $([int]$resp.StatusCode) from $Uri", ([pscustomobject]@{ StatusCode = [pscustomobject]@{ value__ = [int]$resp.StatusCode }; Headers = $hdrs })))
        }
        $rs = $resp.Content.ReadAsStream()
        try { return (Save-SpoolStream -InStream $rs -OutFile $OutFile -Key $Key) } finally { $rs.Dispose() }
    } finally { $c.Dispose(); $h.Dispose() }
}
$script:SpoolHelperSource = (@('Save-SpoolStream','Save-SpoolFile','Get-SpoolLength','Open-SpoolRead','Copy-SpoolToFile','Read-SpoolChunk','Send-SpoolHttp','Invoke-SpoolDownload') | ForEach-Object { "function $_ { $((Get-Item "function:$_").Definition) }" }) -join "`n"
function Lz6ddb3e4788 {
    param([Parameter(Mandatory)] [string] $Path)
    $WIDTH = 160; $SHIFT = 11
    $data = [byte[]]::new([math]::Ceiling($WIDTH/8.0))
    $lengthSoFar = 0; $shiftSoFar = 0
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = [byte[]]::new(65536)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            for ($i = 0; $i -lt $read; $i++) {
                $vectorArrayIndex = [int]([math]::Floor($shiftSoFar/8.0))
                $vectorOffset = $shiftSoFar % 8
                $data[$vectorArrayIndex] = $data[$vectorArrayIndex] -bxor ([byte](($buffer[$i] -shl $vectorOffset) -band 0xFF))
                if ($vectorOffset -gt 3) { $next = ($vectorArrayIndex+1) % $data.Length; $data[$next] = $data[$next] -bxor ([byte]($buffer[$i] -shr (8-$vectorOffset))) }
                $shiftSoFar = ($shiftSoFar + $SHIFT) % $WIDTH
            }
            $lengthSoFar += $read
        }
    } finally { $stream.Dispose() }
    $lenBytes = [BitConverter]::GetBytes([int64]$lengthSoFar)
    for ($i = 0; $i -lt 8; $i++) { $data[($data.Length-8)+$i] = $data[($data.Length-8)+$i] -bxor $lenBytes[$i] }
    return [Convert]::ToBase64String($data)
}
function Get-DattoAuthHeader {
    param($Config)
    $id = $Config.datto.clientId
    $secret = Resolve-Secret $Config.datto.clientSecret
    $pair = [Text.Encoding]::UTF8.GetBytes("$id`:$secret")
    return @{ Authorization = 'Basic ' + [Convert]::ToBase64String($pair) }
}
function Lz35962d6dcd {
    param($Config)
    if ($Config.datto.provider -eq 'LocalSim') { Lz12e519cc30 OK "Datto provider: LocalSim ($($Config.datto.sim.rootPath))"; return }
    if ($script:GuiMode) { Write-Host "##STATUS##|Connecting to Datto..." }
    $null = Invoke-DattoApi -Config $Config -Path $Config.datto.apiPaths.listProjects
    Lz12e519cc30 OK "Datto API authenticated (Basic auth)."
}
function Invoke-DattoApi {
    param($Config, [string]$Path, [hashtable]$Query)
    $uri = ($Config.datto.endpointUrl.TrimEnd('/')) + $Path
    if ($Query) { $uri += '?' + (($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }) -join '&') }
    $headers = Get-DattoAuthHeader -Config $Config
    Lz598441362f
    $r = Invoke-WithRetry -Config $Config -What "Datto GET $Path" -Action {
        $resp  = Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -Headers $headers -TimeoutSec $script:HttpTimeoutSec
        $script:DattoLastHeaders = $resp.Headers
        $bytes = if ($resp.RawContentStream) { $resp.RawContentStream.ToArray() } else { [Text.Encoding]::UTF8.GetBytes([string]$resp.Content) }
        [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    }
    Lz086388ac1f -Headers $script:DattoLastHeaders
    return $r
}
function Get-DattoSpaces {
    param($Config)
    if ($Config.datto.provider -eq 'LocalSim') {
        $root = $Config.datto.sim.rootPath
        $out = @()
        foreach ($t in @('Personal','TeamShares')) {
            $p = Join-Path $root $t
            if (Test-Path $p) { foreach ($d in Get-ChildItem $p -Directory) {
                $out += [pscustomobject]@{ Id = $d.FullName; Name = $d.Name; Type = $(if($t -eq 'Personal'){'Personal'}else{'Team'}); OwnerUpn = $(if($d.Name -match '@'){$d.Name}else{''}) }
            } }
        }
        return $out
    }
    $f = $Config.datto.fields
    $resp = Invoke-DattoApi -Config $Config -Path $Config.datto.apiPaths.listProjects
    $items = if ($resp -is [System.Array]) { $resp } elseif ($f.collection -and $resp.PSObject.Properties.Name -contains $f.collection) { $resp.($f.collection) } else { $resp }
    return @($items | ForEach-Object {
        [pscustomobject]@{ Id = $_.($f.itemId); Name = $_.($f.itemName); Type = 'Team'; OwnerUpn = '' }
    })
}
function Test-ItemInFailedSet {
    param($it)
    if ($null -eq $script:FailedOnlySet) { return $true }
    return $script:FailedOnlySet.Contains(("$($script:CurrentEnumSpace)" + [char]0 + "$($it.RelativePath)"))
}
function Test-ItemInDateWindow {
    param($it)
    if (-not ($script:ModifiedAfterUtc -or $script:ModifiedBeforeUtc)) { return $true }
    $m = $null; try { $m = ConvertTo-UtcDate $it.ModifiedUtc } catch {}
    if ($null -eq $m) { return $true }
    if ($script:ModifiedAfterUtc  -and $m -lt $script:ModifiedAfterUtc)  { return $false }
    if ($script:ModifiedBeforeUtc -and $m -ge $script:ModifiedBeforeUtc) { return $false }
    return $true
}
function Lz28616782b6 {
    param($leaf)
    if (-not $script:IncludePatterns.Count) { return $true }
    foreach ($pat in $script:IncludePatterns) { if ($leaf -like $pat) { return $true } }
    return $false
}
function Select-IncludedItems {
    param($Items)
    if (-not ($script:ExcludePatterns.Count -or $script:IncludePatterns.Count -or $script:MaxFileBytes -gt 0 -or $script:ModifiedAfterUtc -or $script:ModifiedBeforeUtc -or $null -ne $script:FailedOnlySet)) { return $Items }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($it in @($Items)) {
        $leaf = ($it.RelativePath -split '/')[-1]
        $skip = $false
        foreach ($pat in $script:ExcludePatterns) { if ($leaf -like $pat) { $skip = $true; break } }
        if (-not $skip -and -not (Lz28616782b6 $leaf)) { $skip = $true }
        if (-not $skip -and $script:MaxFileBytes -gt 0 -and [int64]$it.Size -gt $script:MaxFileBytes) { $skip = $true }
        if (-not $skip -and -not (Test-ItemInDateWindow $it)) { $skip = $true }
        if (-not $skip -and -not (Test-ItemInFailedSet $it)) { $skip = $true }
        if (-not $skip) { $out.Add($it) }
    }
    return $out
}
function Test-ItemIncluded {
    param($it)
    if (-not ($script:ExcludePatterns.Count -or $script:IncludePatterns.Count -or $script:MaxFileBytes -gt 0 -or $script:ModifiedAfterUtc -or $script:ModifiedBeforeUtc -or $null -ne $script:FailedOnlySet)) { return $true }
    $leaf = ($it.RelativePath -split '/')[-1]
    foreach ($pat in $script:ExcludePatterns) { if ($leaf -like $pat) { return $false } }
    if (-not (Lz28616782b6 $leaf)) { return $false }
    if ($script:MaxFileBytes -gt 0 -and [int64]$it.Size -gt $script:MaxFileBytes) { return $false }
    if (-not (Test-ItemInDateWindow $it)) { return $false }
    if (-not (Test-ItemInFailedSet $it)) { return $false }
    return $true
}
function Lzdf43513bbf {
    param($Config, [string]$AuditPath)
    if (-not $AuditPath) {
        $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $AuditPath = $latest.FullName }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) { throw "Rerun failed only: no run audit found in $($Config.run.reportRoot). There is no record of a previous run to take the failed files from. Run 'Sync new and changed' instead." }
    $rows = $null
    try { $rows = @(Import-Csv $AuditPath) } catch { throw "Rerun failed only: the audit could not be read ($($_.Exception.Message)). Run 'Sync new and changed' instead. Audit: $AuditPath" }
    if (-not $rows.Count) { throw "Rerun failed only: the audit is empty. Run 'Sync new and changed' instead. Audit: $AuditPath" }
    $cols = @($rows[0].PSObject.Properties.Name)
    if (($cols -notcontains 'Status') -or ($cols -notcontains 'SourcePath') -or ($cols -notcontains 'Space')) {
        throw "Rerun failed only: $([System.IO.Path]::GetFileName($AuditPath)) is not a run audit (it has no Status/SourcePath/Space columns). Pick a real run's audit, or run 'Sync new and changed'."
    }
    $failStatuses = @('Error','DownloadError','VerifyFail','SkippedTooLarge')
    $failed = @($rows | Where-Object { $failStatuses -contains "$($_.Status)" })
    if (-not $failed.Count) { throw "Rerun failed only: $([System.IO.Path]::GetFileName($AuditPath)) recorded no failed files, so there is nothing to rerun. If you expected failures, check you picked the right run." }
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in $failed) { [void]$set.Add(("$($r.Space)" + [char]0 + "$($r.SourcePath)")) }
    Lz12e519cc30 WARN "RERUN FAILED ONLY: re-copying just the $($failed.Count) file(s) that failed in $([System.IO.Path]::GetFileName($AuditPath)). Everything else is left exactly as it is."
    return $set
}
function New-SpaceRef {
    param($Row)
    $sub = ''
    try { if ($Row.PSObject.Properties.Name -contains 'SourceSubPath') { $sub = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
    $co = $false
    try { if ($Row.PSObject.Properties.Name -contains 'SourceContentsOnly') { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    if (-not $sub) { $co = $false }
    return [pscustomobject]@{ Id = $Row.SpaceId; Name = $Row.Space; SubPath = $sub; ContentsOnly = $co }
}
function Resolve-DattoSubPath {
    param($Config, $Space, [string]$SubPath)
    $f = $Config.datto.fields
    $parent = $Space.Id
    foreach ($seg in @($SubPath -split '/' | Where-Object { $_ })) {
        $childPath = ($Config.datto.apiPaths.listChildren -replace '\{parentID\}', $parent)
        $resp = Invoke-DattoApi -Config $Config -Path $childPath -Query @{}
        $items = if ($resp -is [System.Array]) { $resp } elseif ($f.collection -and ($resp.PSObject.Properties.Name -contains $f.collection)) { $resp.($f.collection) } else { $resp }
        $hit = $null
        foreach ($it in @($items)) {
            $isFolder = $false; try { $isFolder = [bool]$it.($f.itemFolder) } catch {}
            if ($isFolder -and ("$($it.($f.itemName))" -eq $seg)) { $hit = $it; break }
        }
        if (-not $hit) { throw "SourceSubPath not found: no folder named '$seg' under '$($Space.Name)$(if($SubPath){"/$SubPath"})'. Check the path in mapping.csv. It is case-sensitive and must be the path as Datto shows it, with / between folders and no leading slash." }
        $parent = $hit.($f.itemId)
    }
    return $parent
}
function Get-DattoItems {
    param($Config, $Space, [scriptblock]$OnItem)
    $script:CurrentEnumSpace = "$($Space.Name)"
    $subPath = ''
    try { if ($Space.PSObject.Properties.Name -contains 'SubPath') { $subPath = "$($Space.SubPath)" } } catch {}
    $contentsOnly = $false
    try { if ($Space.PSObject.Properties.Name -contains 'ContentsOnly') { $contentsOnly = [bool]$Space.ContentsOnly } } catch {}
    if ($subPath) {
        Lz12e519cc30 WARN "  SOURCE IS SCOPED to [$subPath] inside [$($Space.Name)]. Only that folder is being listed. This is a partial view of the project: do not read the result as a complete migration of it."
        if ($contentsOnly) { Lz12e519cc30 WARN "  CONTENTS ONLY is on for this project: the [$subPath] folder itself is NOT created at the destination; its contents land directly in the target folder. Only runs of this mapping with the setting on understand that layout: a run WITHOUT it would not find these files and would copy them again to [$subPath/...]." }
    }
    $scopeLabel = if ($subPath) { "$($Space.Name) / $subPath" } else { "$($Space.Name)" }
    if ($Config.datto.provider -eq 'LocalSim') {
        $base = $Space.Id
        if ($subPath) { $base = Join-Path $Space.Id ($subPath -replace '/','\') }
        if (-not (Test-Path $base)) { throw "SourceSubPath not found: '$subPath' does not exist under '$($Space.Name)'." }
        $list = Select-IncludedItems (Get-ChildItem $base -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\','/') -replace '\\','/'
            if ($subPath -and -not $contentsOnly) { $rel = "$subPath/$rel" }
            $h = ''; if ($_.Length -gt 0) { try { $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash.ToLower() } catch {} }
            [pscustomobject]@{ Id = $_.FullName; RelativePath = $rel; Size = $_.Length; ModifiedUtc = $_.LastWriteTimeUtc.ToString('o'); Hash = $h }
        })
        if ($OnItem) { foreach ($x in @($list)) { & $OnItem $x }; return (New-Object System.Collections.Generic.List[object]) }
        return $list
    }
    $f = $Config.datto.fields
    $meta = ''; try { if ($Config.datto.metadataParam) { $meta = $Config.datto.metadataParam } } catch {}
    $out = New-Object System.Collections.Generic.List[object]
    $prog = @{ Folders = 0; Files = 0; Node = ''; LastLog = [DateTime]::MinValue }
    $suspects = New-Object System.Collections.Generic.List[object]
    $emitEnum = {
        param([switch]$Force)
        $now = [DateTime]::UtcNow
        if (-not $Force -and ($now - $prog.LastLog).TotalSeconds -lt 3) { return }
        $prog.LastLog = $now
        $w = if ($prog.Node) { "  now in: /$($prog.Node)" } else { '' }
        Lz12e519cc30 INFO "  SOURCE [$scopeLabel]: $('{0:N0}' -f $prog.Folders) folder(s) read, $('{0:N0}' -f $prog.Files) file(s) found so far.$w"
        if ($script:GuiMode) { Write-Host "##STATUS##|Source: $('{0:N0}' -f $prog.Folders) folders, $('{0:N0}' -f $prog.Files) files so far  (reading the Datto list, nothing uploads yet)" }
    }
    function Lz2eb63eb068 { param($ParentId, [string]$Prefix)
        $childPath = ($Config.datto.apiPaths.listChildren -replace '\{parentID\}', $ParentId)
        $q = @{}; if ($meta) { $q['metadata'] = $meta }
        $resp = Invoke-DattoApi -Config $Config -Path $childPath -Query $q
        $prog.Folders++; $prog.Node = $Prefix; & $emitEnum
        $items = if ($resp -is [System.Array]) { $resp } elseif ($f.collection -and ($resp.PSObject.Properties.Name -contains $f.collection)) { $resp.($f.collection) } else { $resp }
        $n = @($items).Count
        if ($n -gt 0 -and (@(100,200,250,500,1000,2000,5000) -contains $n)) {
            $suspects.Add(@{ Path = $(if ($Prefix) { $Prefix } else { '(root)' }); Count = $n })
        }
        foreach ($it in @($items)) {
            $name = $it.($f.itemName)
            $rel = if ($Prefix) { "$Prefix/$name" } else { $name }
            $isFolder = $false; try { $isFolder = [bool]$it.($f.itemFolder) } catch {}
            if ($isFolder) {
                Lz2eb63eb068 -ParentId $it.($f.itemId) -Prefix $rel
            } else {
                $size = 0; try { $size = [int64]$it.($f.itemSize) } catch {}
                $md5 = ''; try { $md5 = "$($it.($f.itemHash))" } catch {}
                $modUtc = ''
                try {
                    $t = [int64]$it.($f.itemTime)
                    if ($t -gt 0) { $ms = if ($t -gt 100000000000) { $t } else { $t * 1000 }; $modUtc = [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime.ToString('o') }
                } catch {}
                $obj = [pscustomobject]@{ Id = "$($it.($f.itemId))"; RelativePath = $rel; Size = $size; ModifiedUtc = $modUtc; Hash = $md5 }
                if (Test-ItemIncluded $obj) { $prog.Files++; if ($OnItem) { & $OnItem $obj } else { $out.Add($obj) } }
            }
        }
    }
    $startId = $Space.Id
    if ($subPath) { $startId = Resolve-DattoSubPath -Config $Config -Space $Space -SubPath $subPath }
    Lz2eb63eb068 -ParentId $startId -Prefix $(if ($contentsOnly) { '' } else { $subPath })
    & $emitEnum -Force
    $script:SrcTotal = $prog.Files
    Lz12e519cc30 OK "  SOURCE [$scopeLabel] FINISHED: $('{0:N0}' -f $prog.Files) file(s) across $('{0:N0}' -f $prog.Folders) folder(s)."
    Lz487ef9330e -Config $Config -Space $Space -Suspects $suspects
    return $out
}
$script:EnumCacheMaxAgeSec = 86400
function Lzb7c41876b6 {
    param($Config, $Space)
    if (-not $Config.run.stateRoot) { return $null }
    return (Join-Path $Config.run.stateRoot ("enum-" + (ConvertTo-Slug "$($Space.Name)") + ".json"))
}
function Lzf60c8f61c3 {
    param($Config, $Space, $Items)
    $p = Lzb7c41876b6 -Config $Config -Space $Space
    if (-not $p) { return }
    try {
        if (-not (Test-Path $Config.run.stateRoot)) { New-Item -ItemType Directory -Path $Config.run.stateRoot -Force | Out-Null }
        $sub = ''; try { if ($Space.PSObject.Properties.Name -contains 'SubPath') { $sub = "$($Space.SubPath)" } } catch {}
        $co = $false; try { if ($Space.PSObject.Properties.Name -contains 'ContentsOnly') { $co = [bool]$Space.ContentsOnly } } catch {}
        $now = [DateTime]::UtcNow
        [pscustomobject]@{
            Version        = 2
            SpaceId        = "$($Space.Id)"
            SpaceName      = "$($Space.Name)"
            SourceSubPath  = $sub
            ContentsOnly   = $co
            ListedUtcTicks = "$($now.Ticks)"
            ListedUtc      = $now.ToString('o')
            FileCount      = @($Items).Count
            Items          = @($Items)
        } | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $p -Encoding UTF8
    } catch {
        Lz12e519cc30 INFO "  (could not save the file list for a later Resume: $($_.Exception.Message). Harmless: a Resume would read Datto again instead.)"
    }
}
function Get-SpaceItemsCached {
    param($Config, $Space)
    $sub = ''; try { if ($Space.PSObject.Properties.Name -contains 'SubPath') { $sub = "$($Space.SubPath)" } } catch {}
    $co = $false; try { if ($Space.PSObject.Properties.Name -contains 'ContentsOnly') { $co = [bool]$Space.ContentsOnly } } catch {}
    if ($script:UseEnumCache) {
        $p = Lzb7c41876b6 -Config $Config -Space $Space
        $why = ''
        if (-not $p -or -not (Test-Path $p)) { $why = 'there is no saved file list for this project' }
        else {
            try {
                $c = Get-Content $p -Raw | ConvertFrom-Json
                $listedUtc = [DateTime]::new([int64]$c.ListedUtcTicks, [System.DateTimeKind]::Utc)
                $ageSec = ([DateTime]::UtcNow - $listedUtc).TotalSeconds
                if    ([int]$c.Version -ne 2)                    { $why = 'the saved file list is in an older format' }
                elseif ("$($c.SpaceId)" -ne "$($Space.Id)")      { $why = 'the saved file list is for a different project' }
                elseif ("$($c.SourceSubPath)" -ne $sub)          { $why = 'the source subfolder has changed since the list was saved' }
                elseif ($(($c.PSObject.Properties.Name -contains 'ContentsOnly') -and [bool]$c.ContentsOnly) -ne $co) { $why = 'the contents-only setting has changed since the list was saved' }
                elseif ($ageSec -gt $script:EnumCacheMaxAgeSec)  { $why = "the saved file list is too old ($([int]($ageSec/3600))h)" }
                else {
                    $items = @($c.Items)
                    $when  = $listedUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
                    Lz12e519cc30 WARN "  RESUMED FROM THE EARLIER FILE LIST taken at $when ($($items.Count) file(s)), so Datto was not read again. ANYTHING ADDED OR CHANGED IN DATTO SINCE THEN IS NOT IN THIS RUN. In plain terms: that is true of any long run, because the list is always a snapshot from when it started, which is why you finish with a Sync. Run 'Sync new and changed' afterwards to pick up anything new."
                    return $items
                }
            } catch { $why = "the saved file list could not be read ($($_.Exception.Message))" }
        }
        Lz12e519cc30 INFO "  reading the file list from Datto again, because $why."
    }
    $items = @(Get-DattoItems -Config $Config -Space $Space)
    Lzf60c8f61c3 -Config $Config -Space $Space -Items $items
    return $items
}
function Lz487ef9330e {
    param($Config, $Space, $Suspects)
    if (-not $Suspects -or $Suspects.Count -eq 0) { return }
    $verified = @{}
    try {
        if ($Config.datto.PSObject.Properties.Name -contains 'verifiedFolderCounts') {
            foreach ($pr in $Config.datto.verifiedFolderCounts.PSObject.Properties) { $verified["$($pr.Name)"] = [int]$pr.Value }
        }
    } catch {}
    $toNote = @($Suspects | Where-Object { -not ($verified.ContainsKey($_.Path) -and $verified[$_.Path] -eq [int]$_.Count) })
    if (-not $toNote.Count) { return }
    Lz12e519cc30 INFO "  Note, not a problem: $($toNote.Count) folder(s) in [$($Space.Name)] returned a round number of items (100, 200, ...), which is the shape a truncated listing would take, so they are flagged here for the record. Testing has confirmed Datto returns every child with no paging (folders come back with far more than 100), so these are genuine counts and nothing is missing. No action needed. To stop noting a folder you have counted in Datto, add it under datto.verifiedFolderCounts in config.json."
    foreach ($s in ($toNote | Sort-Object Path)) {
        Lz12e519cc30 INFO "    [$($s.Path)] returned $($s.Count) items."
    }
}
function Lza83d2fc83b {
    param($Config, $Item, [string]$OutFile)
    if ($Config.datto.provider -eq 'LocalSim') {
        if ($script:SpoolKey) { Save-SpoolFile -InFile $Item.Id -OutFile $OutFile -Key $script:SpoolKey | Out-Null }
        else { Copy-Item -LiteralPath $Item.Id -Destination $OutFile -Force }
        return $OutFile
    }
    $uri = ($Config.datto.endpointUrl.TrimEnd('/')) + ($Config.datto.apiPaths.downloadFile -replace '\{fileID\}', $Item.Id)
    $headers = Get-DattoAuthHeader -Config $Config
    Invoke-WithRetry -Config $Config -What "Datto download $($Item.RelativePath)" -Action {
        Lz598441362f
        if ($script:SpoolKey) { Invoke-SpoolDownload -Uri $uri -Headers $headers -OutFile $OutFile -Key $script:SpoolKey -TimeoutSec $script:TransferTimeoutSec | Out-Null }
        else { Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -Headers $headers -OutFile $OutFile -TimeoutSec $script:TransferTimeoutSec }
    } | Out-Null
    return $OutFile
}
$script:ReservedDosNames = @('con','prn','aux','nul') + (0..9 | ForEach-Object { "com$_" }) + (0..9 | ForEach-Object { "lpt$_" })
$script:ReservedWholeNames = @('.lock','desktop.ini','forms')
function ConvertTo-SafeRelPath {
    param([string]$RelPath)
    $segs = $RelPath -split '[\\/]'
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($s in $segs) {
        if ($s -eq '') { continue }
        $x = $s -replace '["\*:<>\?\|]', '_'
        $x = $x -replace '[\x00-\x1F]', '_'
        $x = $x -replace '^~\$', '_'
        $x = $x.TrimEnd([char]0x20, [char]0x2E)
        if ($x -eq '') { $x = '_' }
        if ($x -match '(?i)_vti_') { $x = $x -replace '(?i)_vti_', '_vti-' }
        $dot  = $x.LastIndexOf('.')
        $base = if ($dot -gt 0) { $x.Substring(0, $dot) } else { $x }
        $ext  = if ($dot -gt 0) { $x.Substring($dot) } else { '' }
        $lw = $x.ToLowerInvariant(); $lb = $base.ToLowerInvariant()
        if (($script:ReservedDosNames -contains $lb) -or ($script:ReservedDosNames -contains $lw) -or ($script:ReservedWholeNames -contains $lw)) {
            $x = if ($ext) { $base + '_' + $ext } else { $x + '_' }
        }
        $out.Add($x)
    }
    return ($out -join '/')
}
function Lzee101c9f2d {
    param($Config, $Space)
    if ($Config.datto.provider -eq 'LocalSim') { return @() }
    if (-not $Config.datto.apiPaths.listPermissions) { return @() }
    $f = $Config.datto.fields
    try {
        $resp = Invoke-DattoApi -Config $Config -Path ($Config.datto.apiPaths.listPermissions -replace '\{spaceId\}', $Space.Id)
        return $resp.($f.collection) | ForEach-Object { [pscustomobject]@{ Principal = $_.($f.permPrincipal); Role = $_.($f.permRole) } }
    } catch { Lz12e519cc30 WARN "  permissions unavailable for $($Space.Name)"; return @() }
}
function Lz8dced97797 {
    param([string]$Broker, $Config)
    $lic = ''
    try { if (($Config.run.PSObject.Properties.Name -contains 'licenceFile') -and $Config.run.licenceFile) { $lic = "$($Config.run.licenceFile)" } } catch {}
    if (-not $lic) { $lic = Join-Path (Split-Path $PSScriptRoot -Parent) 'licence.json' }
    $brokerArgs = @(
        '--tenant', "$($Config.auth.tenantId)",
        '--client', "$($Config.auth.clientId)",
        '--thumbprint', "$($Config.auth.certThumbprint)",
        '--store', "$($Config.auth.certStore)",
        '--expected-tenant', "$($Config.auth.tenantId)",
        '--scope', 'https://graph.microsoft.com/.default'
    )
    if (Test-Path $lic) { $brokerArgs += @('--licence', $lic) }
    $raw  = (& $Broker @brokerArgs 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $line = ($raw -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    $obj  = $null
    if ($line) { try { $obj = $line | ConvertFrom-Json } catch {} }
    $tokenOk = $obj -and ($obj.PSObject.Properties.Name -contains 'token') -and $obj.token
    if ($code -eq 0 -and $tokenOk) {
        $exp = [DateTimeOffset]::UtcNow.AddMinutes(45)
        try { if (($obj.PSObject.Properties.Name -contains 'expiresOn') -and $obj.expiresOn) { $exp = ([DateTimeOffset]::Parse("$($obj.expiresOn)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)).AddMinutes(-4) } } catch {}
        return [pscustomobject]@{ Token = "$($obj.token)"; Exp = $exp; Mode = "$($obj.mode)"; Customer = "$($obj.customer)" }
    }
    $reason = if ($obj -and ($obj.PSObject.Properties.Name -contains 'reason')) { "$($obj.reason)" } else { $raw.Trim() }
    if ($code -eq 2) {
        if ($script:GuiMode) { Write-Host "##LICENCE##|$reason" }
        throw "$($script:StopTag)This migration needs a valid licence. $reason Nothing has been changed. Obtain a licence at https://www.liscaragh.com, then install it via Help > Install licence file."
    }
    if ($code -eq 5) {
        $custMsg = "This installation has been modified or is damaged, so it will not run. Nothing has been changed. Re-run the installer to restore it. If it keeps happening, contact support@liscaragh.com."
        if ("$reason".Trim()) { Lz12e519cc30 WARN "Integrity check detail: $reason" }
        if ($script:GuiMode) { Write-Host "##TAMPER##|$custMsg" }
        throw "$($script:StopTag)$custMsg"
    }
    throw "$($script:StopTag)Could not sign in to Microsoft 365. Nothing has been changed. $reason Check the internet connection and that the certificate and app registration are still in place, then try again. If it persists, contact support@liscaragh.com."
}
function Connect-Destination {
    param($Config)
    if ($Config.destination.provider -eq 'LocalSim') { Lz12e519cc30 OK "Destination provider: LocalSim ($($Config.destination.sim.rootPath))"; return }
    if ($script:GuiMode) { Write-Host "##STATUS##|Connecting to Microsoft 365..." }
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) { throw "Microsoft.Graph module not installed (run: Install-Module Microsoft.Graph -Scope CurrentUser). In plain terms: the Microsoft 365 connection component is missing on this computer. Re-run the setup, or ask your IT contact to install it." }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $broker = Join-Path $PSScriptRoot 'LiscaraAuth.exe'
    if (-not (Test-Path $broker)) {
        throw "$($script:StopTag)Microsoft 365 sign-in is not available on this computer, so the run cannot start. Nothing has been changed. Re-run the installer to repair the installation, then try again. If it keeps happening, contact support@liscaragh.com."
    }
    $auth = Lz8dced97797 -Broker $broker -Config $Config
    Connect-MgGraph -AccessToken (ConvertTo-SecureString "$($auth.Token)" -AsPlainText -Force) -NoWelcome
    Lz12e519cc30 OK "Microsoft 365 sign-in via the licence broker (LiscaraAuth): the token is bound to a verified licence."
    $liveTenant = ''
    try { $liveTenant = "$((Get-MgContext).TenantId)" } catch {}
    if ($liveTenant -and "$($Config.auth.tenantId)" -and ($liveTenant -ne "$($Config.auth.tenantId)")) {
        throw "$($script:StopTag)This computer is signed in to a different Microsoft 365 organisation than this migration job expects, so the run was stopped before anything was written, to make sure data cannot go to the wrong place. Nothing has been changed. Check you have opened the correct migration job and are signed in to the right tenant."
    }
    if ($script:LicenceInfo -and $liveTenant) {
        $lic2 = Test-MigrationLicence -Config $Config -LiveTenantId $liveTenant
        if (-not $lic2.Licensed) {
            throw "$($script:StopTag)This licence belongs to a different Microsoft 365 organisation than the one this job is connected to, so the run was stopped. Nothing has been changed. $($lic2.Reason)"
        }
    }
    if ($script:ScopeRefId -and $liveTenant -and ($script:ScopeRefId -ne $liveTenant) -and ($null -eq $script:TrialCap)) {
        $script:TrialCap = 0; $script:TrialFilesRemaining = 0
        Lz12e519cc30 WARN "Evaluation limits apply to this run."
    }
    Lz12e519cc30 OK "Connected to Graph (tenant $liveTenant)."
}
function Join-SubPath { param([string]$A,[string]$B) $p=@(); foreach($x in @($A,$B)){ $t="$x".Trim('/'); if($t){ $p+=$t } }; return ($p -join '/') }
function Get-NestFolder {
    param($Config, $Row)
    $nest = $true
    try { if ($Config.destination.PSObject.Properties.Name -contains 'nestUnderProjectFolder') { $nest = [bool]$Config.destination.nestUnderProjectFolder } } catch {}
    if (-not $nest) { return '' }
    $name = "$($Row.Space)"; if (-not $name) { return '' }
    if (($Config.run.PSObject.Properties.Name -contains 'sanitiseNames') -and $Config.run.sanitiseNames) { $name = ConvertTo-SafeRelPath $name }
    return $name
}
function Get-GraphCollection {
    param($Config, [string]$Uri, [string]$What = 'list')
    $values = [System.Collections.Generic.List[object]]::new()
    $pages = 0
    $next = $Uri
    while ($next) {
        $u = $next
        $resp = Invoke-WithRetry -Config $Config -What $What -Action { Invoke-MgGraphRequest -Method GET -Uri $u }
        $pages++
        foreach ($v in @($resp['value'])) { [void]$values.Add($v) }
        $next = $null
        try { if ($resp.ContainsKey('@odata.nextLink')) { $next = "$($resp['@odata.nextLink'])" } } catch {}
    }
    return @{ Values = $values; Pages = $pages }
}
function Resolve-DestinationDriveId {
    param($Config, $Row)
    if ($Config.destination.provider -eq 'LocalSim') { return @{ DriveId = "sim:$($Row.DestinationUrl)"; SubFolder = (Join-SubPath $Row.TargetSubFolder (Get-NestFolder $Config $Row)) } }
    if ($Row.DestinationType -eq 'OneDrive') {
        if (-not $Row.TargetPrincipal) { throw "OneDrive target for '$($Row.Space)' needs a TargetPrincipal (the user's UPN) in mapping.csv. In plain terms: no user email was set for this project's OneDrive destination. Enter it in the destination box and save the mapping." }
        $upnEnc = [uri]::EscapeDataString($Row.TargetPrincipal)
        $d = $null
        try { $d = Invoke-WithRetry -Config $Config -What "OneDrive $($Row.TargetPrincipal)" -Action { Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$upnEnc/drive" } } catch { $d = $null }
        if (-not $d) { throw "OneDrive not found for '$($Row.TargetPrincipal)'. In plain terms: that user's OneDrive could not be opened. Check the email is spelled correctly, the user has a Microsoft 365 licence, and they have opened their OneDrive at least once." }
        return @{ DriveId = $d['id']; SubFolder = (Join-SubPath $Row.TargetSubFolder (Get-NestFolder $Config $Row)) }
    }
    $u = [Uri]$Row.DestinationUrl
    $segs = @(($u.AbsolutePath.Trim('/') -split '/') | Where-Object { $_ -ne '' })
    $sitePath = ''; $extra = @()
    if ($segs.Count -ge 2 -and (@('sites','teams') -contains $segs[0].ToLower())) {
        $sitePath = "/$($segs[0])/$($segs[1])"
        if ($segs.Count -gt 2) { $extra = $segs[2..($segs.Count - 1)] }
    } elseif ($segs.Count -ge 1) {
        $extra = $segs
    }
    $extra = @($extra | ForEach-Object { [uri]::UnescapeDataString($_) })
    $siteId = if ($sitePath) { "$($u.Host):$sitePath" } else { $u.Host }
    $site = $null
    try { $site = Invoke-WithRetry -Config $Config -What "Site $siteId" -Action { Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId" } } catch { $site = $null }
    if (-not $site) { throw "SharePoint site not found for URL '$($Row.DestinationUrl)'. In plain terms: that SharePoint address could not be found. Copy the site address from your browser (it usually looks like https://host/sites/SiteName) and put any folder in the folder box." }
    $drives = @((Get-GraphCollection -Config $Config -Uri "https://graph.microsoft.com/v1.0/sites/$($site['id'])/drives" -What "Site libraries").Values)
    if (-not $drives.Count) { throw "No document library found in site '$($Row.DestinationUrl)'. In plain terms: this SharePoint site has no document library to upload into. Check you have the right site." }
    $lib = ''; if ($Row.PSObject.Properties.Name -contains 'TargetLibrary') { $lib = "$($Row.TargetLibrary)".Trim() }
    if ($lib) {
        $d = $drives | Where-Object { "$($_['name'])" -eq $lib } | Select-Object -First 1
        if (-not $d) { throw "Library '$lib' not found in site '$($Row.DestinationUrl)'. In plain terms: that document library name does not exist on the site. Pick one of these instead: $(@($drives | ForEach-Object { $_['name'] }) -join ', ')." }
    } else {
        $d = $drives | Select-Object -First 1
    }
    $subParts = @($extra) + @(($Row.TargetSubFolder -split '[\\/]') | Where-Object { $_ -ne '' })
    return @{ DriveId = $d['id']; SubFolder = (Join-SubPath ($subParts -join '/') (Get-NestFolder $Config $Row)) }
}
function Lzca23b15031 {
    param($Config, [string]$DriveId, [string]$FolderPath)
    if (-not $FolderPath) { return }
    if (-not $script:EnsuredFolders) { $script:EnsuredFolders = @{} }
    $parts = @(($FolderPath -split '/') | Where-Object { $_ -ne '' })
    $cur = ''
    foreach ($p in $parts) {
        $parent = $cur
        $cur = if ($cur) { "$cur/$p" } else { $p }
        if ($script:EnsuredFolders.ContainsKey("$DriveId|$cur")) { continue }
        $parentUri = if ($parent) {
            "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$([uri]::EscapeDataString($parent) -replace '%2F','/'):/children"
        } else { "https://graph.microsoft.com/v1.0/drives/$DriveId/root/children" }
        $body = @{ name = $p; folder = @{}; '@microsoft.graph.conflictBehavior' = 'fail' } | ConvertTo-Json
        try { Invoke-MgGraphRequest -Method POST -Uri $parentUri -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null } catch { }
        $checkUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$([uri]::EscapeDataString($cur) -replace '%2F','/')"
        for ($w = 1; $w -le 10; $w++) {
            try { Invoke-MgGraphRequest -Method GET -Uri $checkUri -ErrorAction Stop | Out-Null; break }
            catch { Start-Sleep -Milliseconds 1000 }
        }
        $script:EnsuredFolders["$DriveId|$cur"] = $true
    }
}
function Lz52210bd33e {
    param([string]$Url)
    try {
        $u = [Uri]$Url
        $segs = @(($u.AbsolutePath.Trim('/') -split '/') | Where-Object { $_ -ne '' })
        $sitePath = ''
        if ($segs.Count -ge 2 -and (@('sites','teams') -contains $segs[0].ToLower())) { $sitePath = "/$($segs[0])/$($segs[1])" }
        $siteId = if ($sitePath) { "$($u.Host):$sitePath" } else { $u.Host }
        return Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId" -ErrorAction Stop
    } catch { return $null }
}
function Lz204bc8c5c6 {
    param($Config)
    $broker = Join-Path $PSScriptRoot 'LiscaraAuth.exe'
    if (-not (Test-Path $broker)) {
        throw "$($script:StopTag)Microsoft 365 sign-in is not available on this computer, so the run cannot start. Nothing has been changed. Re-run the installer to repair the installation, then try again. If it keeps happening, contact support@liscaragh.com."
    }
    $auth = Lz8dced97797 -Broker $broker -Config $Config
    return @{ Token = $auth.Token; Exp = $auth.Exp }
}
function Lz452f714f93 {
    if ($null -eq $script:DirectPutOk) {
        try { $script:DirectPutOk = [bool]((Get-Command Invoke-MgGraphRequest -ErrorAction Stop).Parameters.ContainsKey('InputFilePath')) }
        catch { $script:DirectPutOk = $false }
    }
    return $script:DirectPutOk
}
function Lzfd01e0628d {
    param($Config, [string]$UploadUrl, [string]$FilePath, [int64]$From, [int64]$To, [int64]$Total, [byte[]]$Bytes)
    $range = "bytes $From-$To/$Total"
    if ($null -ne $Bytes) {
        return Invoke-WithRetry -Config $Config -What "chunk $range" -Action {
            Send-SpoolHttp -Uri $UploadUrl -BodyBytes $Bytes -ContentRange $range -TimeoutSec $script:TransferTimeoutSec
        }
    }
    return Invoke-WithRetry -Config $Config -What "chunk $range" -Action {
        Invoke-WebRequest -UseBasicParsing -Method Put -Uri $UploadUrl -InFile $FilePath -Headers @{ 'Content-Range' = $range } -ContentType 'application/octet-stream' -TimeoutSec $script:TransferTimeoutSec
    }
}
function Send-FileToDestination {
    param($Config, [string]$DriveId, [string]$TargetFolder, $Item, [string]$LocalFile, [string]$Space = '')
    $relPath = if ($TargetFolder) { ($TargetFolder.Trim('/') + '/' + $Item.RelativePath) } else { $Item.RelativePath }
    $relPath = $relPath -replace '\\','/'
    if (($Config.run.PSObject.Properties.Name -contains 'sanitiseNames') -and $Config.run.sanitiseNames) {
        $relPath = Lzfcde41179d -Space $Space -Rp $relPath -Item $Item
    }
    if ($Config.destination.provider -eq 'LocalSim') {
        $dest = Join-Path $Config.destination.sim.rootPath ((ConvertTo-Slug ($DriveId -replace '^sim:','')) + '/' + $relPath)
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        if ($script:SpoolKey) { Copy-SpoolToFile -File $LocalFile -OutFile $dest -Key $script:SpoolKey }
        else { Copy-Item -LiteralPath $LocalFile -Destination $dest -Force }
        return @{ Size = (Get-Item $dest).Length; Hash = (Lz6ddb3e4788 $dest); Path = $relPath; Method = 'LocalSim'; Retries = 0 }
    }
    if ($relPath -match '/') { Lzca23b15031 -Config $Config -DriveId $DriveId -FolderPath ($relPath -replace '/[^/]*$','') }
    $size = if ($script:SpoolKey) { Get-SpoolLength $LocalFile } else { (Get-Item $LocalFile).Length }
    $mtime = $Item.ModifiedUtc
    $encPath = ([uri]::EscapeDataString($relPath) -replace '%2F','/')
    $finalResp = $null
    $dSize = 0; $dHash = ''; $directDone = $false
    $method = ''; $localRetries = 0
    if ($size -eq 0) {
        $method = 'Empty'
        $u = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${encPath}:/content"
        Invoke-WithRetry -Config $Config -What "upload(empty) $relPath" -Action {
            Invoke-MgGraphRequest -Method PUT -Uri $u -Body ([byte[]]::new(0)) -ContentType 'application/octet-stream' | Out-Null
        }
    } elseif ($size -le $script:SmallFilePutThreshold -and (Lz452f714f93) -and -not $script:SpoolKey) {
        $putUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${encPath}:/content"
        try {
            $item = Invoke-WithRetry -Config $Config -What "put $relPath" -RetryNotFound -Action {
                Invoke-MgGraphRequest -Method PUT -Uri $putUri -InputFilePath $LocalFile -ContentType 'application/octet-stream'
            }
            try { $dSize = [int64]$item['size'] } catch { try { $dSize = [int64]$item.size } catch {} }
            try { $dHash = [string]$item['file']['hashes']['quickXorHash'] } catch { try { $dHash = [string]$item.file.hashes.quickXorHash } catch {} }
            if ($dSize -gt 0 -or $script:OfficeTypes -contains ([System.IO.Path]::GetExtension($relPath)).ToLower()) { $directDone = $true; $method = 'DirectPut' }
        } catch {
            Lz12e519cc30 WARN "  direct PUT failed for ${relPath}; falling back to upload session: $($_.Exception.Message). In plain terms: the quick upload did not work for this file, so the tool is switching to the slower resumable method. Usually harmless, the file should still upload."
        }
    }
    if (-not $directDone -and $size -gt 0) {
        $sessUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${encPath}:/createUploadSession"
        $itemMeta = @{ '@microsoft.graph.conflictBehavior' = 'replace' }
        $parsedMtime = [datetime]::MinValue
        $hasFsi = $false
        if (-not $script:OmitFsi -and $mtime -and [datetime]::TryParse($mtime, [ref]$parsedMtime)) {
            $itemMeta['fileSystemInfo'] = @{ lastModifiedDateTime = ([datetimeoffset]$parsedMtime).UtcDateTime.ToString('o') }
            $hasFsi = $true
        }
        $sessBody = @{ item = $itemMeta } | ConvertTo-Json -Depth 5
        $chunk = $script:ChunkSize
        $t = $Config.run.throttle
        $strippedFsi = $false
        for ($attempt = 1; $attempt -le $t.maxRetries; $attempt++) {
            try {
                $sess = Invoke-MgGraphRequest -Method POST -Uri $sessUri -Body $sessBody
                $uploadUrl = if ($sess -is [hashtable]) { $sess['uploadUrl'] } else { $sess.uploadUrl }
                if ($size -le $chunk) {
                    if ($script:SpoolKey) {
                        $sp = Open-SpoolRead -File $LocalFile -Key $script:SpoolKey
                        try { $plain = Read-SpoolChunk -Stream $sp.Stream -Count ([int]$size) } finally { $sp.Stream.Dispose() }
                        $finalResp = Lzfd01e0628d -Config $Config -UploadUrl $uploadUrl -Bytes $plain -From 0 -To ($size - 1) -Total $size
                    } else {
                        $finalResp = Lzfd01e0628d -Config $Config -UploadUrl $uploadUrl -FilePath $LocalFile -From 0 -To ($size - 1) -Total $size
                    }
                } elseif ($script:SpoolKey) {
                    $sp = Open-SpoolRead -File $LocalFile -Key $script:SpoolKey
                    try {
                        $pos = [int64]0
                        while ($true) {
                            $plain = Read-SpoolChunk -Stream $sp.Stream -Count ([int]$chunk)
                            if ($plain.Length -le 0) { break }
                            $finalResp = Lzfd01e0628d -Config $Config -UploadUrl $uploadUrl -Bytes $plain -From $pos -To ($pos + $plain.Length - 1) -Total $size
                            $pos += $plain.Length
                            if ($plain.Length -lt $chunk) { break }
                        }
                    } finally { $sp.Stream.Dispose() }
                } else {
                    $fs = [System.IO.File]::OpenRead($LocalFile)
                    $chunkTmp = "$LocalFile.chunk"
                    try {
                        $buffer = [byte[]]::new($chunk); $pos = 0
                        while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
                            if ($read -eq $buffer.Length) { [System.IO.File]::WriteAllBytes($chunkTmp, $buffer) }
                            else { $slice = [byte[]]::new($read); [Array]::Copy($buffer, 0, $slice, 0, $read); [System.IO.File]::WriteAllBytes($chunkTmp, $slice) }
                            $finalResp = Lzfd01e0628d -Config $Config -UploadUrl $uploadUrl -FilePath $chunkTmp -From $pos -To ($pos + $read - 1) -Total $size
                            $pos += $read
                        }
                    } finally { $fs.Dispose(); if (Test-Path $chunkTmp) { Remove-Item $chunkTmp -Force -ErrorAction SilentlyContinue } }
                }
                $method = 'UploadSession'
                break
            } catch {
                $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
                if ($st -eq 400 -and $hasFsi -and -not $strippedFsi) {
                    $strippedFsi = $true
                    if (-not $script:OmitFsi) {
                        $script:OmitFsi = $true
                        Lz12e519cc30 WARN "  destination rejects the modified-date field; omitting it for the rest of this run. In plain terms: SharePoint would not accept the file's last-modified date, so the tool will stop sending it. Files still upload fine."
                    }
                    $sessBody = @{ item = @{ '@microsoft.graph.conflictBehavior' = 'replace' } } | ConvertTo-Json -Depth 5
                    Lz12e519cc30 WARN "  createUploadSession 400 for ${relPath}: retrying without the modified-date field. In plain terms: the first upload attempt was refused, so the tool is retrying without the date. Usually harmless."
                    $script:RetryEvents++; $localRetries++
                    continue
                }
                if ((@(401, 404, 408, 429, 500, 502, 503, 504) -contains $st) -and $attempt -lt $t.maxRetries) {
                    $ra = Lz90772778a5 $_
                    $delay = Lz85d62aeb50 -Attempt $attempt -Throttle $t -RetryAfter $ra
                    $why = if ($t.honorRetryAfter -and $ra) { "Microsoft asked us to wait $ra s" } else { "Microsoft 365 asked the tool to slow down or the connection blipped" }
                    Lz12e519cc30 WARN "  upload retry for $relPath (HTTP $st): new session, waiting $delay s (attempt $attempt/$($t.maxRetries)). In plain terms: $why, so it will wait $delay seconds and try again. Normal on busy runs."
                    $script:RetryEvents++; $localRetries++
                    Start-Sleep -Seconds $delay; continue
                }
                $gBody = ''
                try { $gBody = $_.ErrorDetails.Message } catch {}
                if (-not $gBody) { try { $gBody = $_.Exception.Message } catch {} }
                if ($gBody) { Lz12e519cc30 ERROR "  Graph reason for $relPath (HTTP $st): $gBody" }
                throw
            }
        }
    }
    if (-not $directDone) {
        if ($finalResp -and $finalResp.Content) {
            try { $item = $finalResp.Content | ConvertFrom-Json; $dSize = [int64]$item.size; try { $dHash = [string]$item.file.hashes.quickXorHash } catch {} } catch {}
        }
        if (-not $dSize) {
            Start-Sleep -Milliseconds 500
            $meta = Invoke-WithRetry -Config $Config -What "meta $relPath" -RetryNotFound -Action {
                Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$([uri]::EscapeDataString($relPath) -replace '%2F','/')"
            }
            try { $dSize = [int64]$meta['size'] } catch { try { $dSize = [int64]$meta.size } catch {} }
            try { $dHash = [string]$meta['file']['hashes']['quickXorHash'] } catch { try { $dHash = [string]$meta.file.hashes.quickXorHash } catch {} }
        }
    }
    return @{ Size = $dSize; Hash = $dHash; Path = $relPath; Method = $method; Retries = $localRetries }
}
$script:OfficeTypes = @(
    '.docx','.docm','.dotx','.dotm','.dot',
    '.xlsx','.xlsm','.xltx','.xltm','.xlsb','.xlt',
    '.pptx','.pptm','.potx','.potm','.ppsx','.ppsm','.pps','.pot',
    '.doc','.xls','.ppt',
    '.mpp','.mpt',
    '.pub',
    '.vsd','.vsdx','.vsdm','.vssx','.vstx','.vss','.vst',
    '.one','.thmx'
)
function Lzc4af9c3f51 {
    param([string]$RelPath, [int64]$SourceSize, [int64]$DestSize)
    if ($SourceSize -eq 0) { return $true }
    if ($DestSize -le 0)   { return $false }
    if ($script:OfficeTypes -contains ([System.IO.Path]::GetExtension($RelPath)).ToLower()) { return $true }
    $tol = [math]::Max(65536, [int64]($SourceSize * 0.01))
    return ([math]::Abs($DestSize - $SourceSize) -le $tol)
}
function Lz3413b7702d {
    param($Repair, $Item, [string]$Status, [string]$Reason)
    if (-not $Repair -or $Repair.Count -eq 0) { return $Reason }
    if ($Status -ne 'Copied' -and $Status -ne 'ZeroByte') { return $Reason }
    $k = "$($Item.Id)"
    if (-not $Repair.ContainsKey($k)) { return $Reason }
    return "REPAIRED (an earlier run left a wrong-sized copy at the destination: $($Repair[$k])) | $Reason"
}
function Lzee645c3ed5 {
    param($Item, [string]$LocalFile, $DestInfo)
    $localSize = if ($script:SpoolKey) { Get-SpoolLength $LocalFile } else { (Get-Item $LocalFile).Length }
    if ($localSize -eq 0) { return @{ Ok = $true; Reason = 'zero-byte (accepted, flagged)'; Zero = $true } }
    $ext = ([System.IO.Path]::GetExtension($Item.RelativePath)).ToLower()
    if ($script:OfficeTypes -contains $ext) {
        if ([int64]$DestInfo.Size -gt 0) { return @{ Ok = $true; Reason = 'Office file accepted (M365 rewrites metadata)'; Zero = $false } }
        return @{ Ok = $false; Reason = 'Office file not stored (size 0 at destination)'; Zero = $false }
    }
    $dsz = [int64]$DestInfo.Size
    if ($dsz -eq $localSize) { return @{ Ok = $true; Reason = 'verified (size)'; Zero = $false } }
    $tol = [math]::Max(65536, [int64]($localSize * 0.01))
    if ($dsz -gt 0 -and [math]::Abs($dsz - $localSize) -le $tol) {
        return @{ Ok = $true; Reason = "accepted (stored $dsz vs source $localSize, diff $($dsz - $localSize) bytes; likely M365 rewrite)"; Zero = $false }
    }
    return @{ Ok = $false; Reason = "size mismatch (dest $dsz vs $localSize)"; Zero = $false }
}
function ConvertTo-UtcDate {
    param($v)
    if ($null -eq $v -or "$v" -eq '') { return $null }
    if ($v -is [datetime]) { return $v.ToUniversalTime() }
    try { return ([datetimeoffset]::Parse("$v", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).UtcDateTime }
    catch { try { return ([datetime]::Parse("$v", [Globalization.CultureInfo]::InvariantCulture)).ToUniversalTime() } catch { return $null } }
}
function ConvertTo-ConfigUtcBound {
    param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) {
        return [datetime]::new($v.Year, $v.Month, $v.Day, $v.Hour, $v.Minute, $v.Second, [System.DateTimeKind]::Utc)
    }
    $s = "$v".Trim(); if (-not $s) { return $null }
    try { return ([datetimeoffset]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)).UtcDateTime }
    catch { throw "run.tuning.modifiedAfter/modifiedBefore must be a date (yyyy-MM-dd) or an ISO UTC timestamp. Got: '$v'." }
}
function Lz2db64bd078 {
    param($Config, $Project)
    Write-Host ""
    Write-Host ("Project: {0}" -f $Project.Name) -ForegroundColor Cyan
    Write-Host "  1. SharePoint site"
    Write-Host "  2. OneDrive of a user"
    Write-Host "  3. Skip this project"
    $choice = Read-Host "  Select [1]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    $validate = ($Config.destination.provider -eq 'Graph')
    switch ($choice.Trim()) {
        '2' {
            while ($true) {
                $upn = Read-Host "  User UPN / login email (e.g. user@yourdomain.com)"
                if ([string]::IsNullOrWhiteSpace($upn)) { Write-Host "  No UPN, skipping." -ForegroundColor DarkGray; return @{ Action='SKIP'; DestinationType='OneDrive'; DestinationUrl=''; TargetPrincipal=''; TargetLibrary=''; TargetSubFolder=''; Notes='No UPN provided.' } }
                if ($validate) {
                    $drv = $null; try { $drv = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($upn.Trim()))/drive" -ErrorAction Stop } catch { }
                    if (-not $drv) { Write-Host "  No OneDrive found for '$upn' (is the user licensed and has the OneDrive been opened once?). Try again." -ForegroundColor Yellow; continue }
                    Write-Host "  OK, OneDrive found." -ForegroundColor Green
                }
                break
            }
            $folder = Read-Host "  Folder inside the OneDrive (blank = root)"
            return @{ Action='MIGRATE'; DestinationType='OneDrive'; DestinationUrl="$($Config.destination.oneDriveHostUrl)/personal/$((ConvertTo-Slug $upn))"; TargetPrincipal=$upn.Trim(); TargetLibrary=''; TargetSubFolder=$folder.Trim(); Notes='' }
        }
        '3' { return @{ Action='SKIP'; DestinationType=''; DestinationUrl=''; TargetPrincipal=''; TargetLibrary=''; TargetSubFolder=''; Notes='Skipped by choice.' } }
        default {
            $libs = @()
            while ($true) {
                $site = Read-Host "  SharePoint site URL (e.g. https://contoso.sharepoint.com/sites/Projects)"
                if ([string]::IsNullOrWhiteSpace($site)) { Write-Host "  No site URL, skipping." -ForegroundColor DarkGray; return @{ Action='SKIP'; DestinationType='SharePoint'; DestinationUrl=''; TargetPrincipal=''; TargetLibrary=''; TargetSubFolder=''; Notes='No site URL provided.' } }
                if ($validate) {
                    $siteObj = Lz52210bd33e -Url $site.Trim()
                    if (-not $siteObj) { Write-Host "  Site not found at that URL. Check it, e.g. https://tenant.sharepoint.com/sites/Name. Try again." -ForegroundColor Yellow; continue }
                    $libs = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($siteObj['id'])/drives")['value'] | ForEach-Object { $_['name'] })
                    Write-Host ("  OK, site found. Libraries: " + ($libs -join ', ')) -ForegroundColor Green
                }
                break
            }
            while ($true) {
                $lib = Read-Host "  Library name (blank = the default 'Documents')"
                if ($validate -and $lib.Trim() -and $libs.Count -and ($libs -notcontains $lib.Trim())) { Write-Host ("  '$($lib.Trim())' is not a library here. Available: " + ($libs -join ', ')) -ForegroundColor Yellow; continue }
                break
            }
            $folder = Read-Host "  Folder inside the library (blank = root; created if missing)"
            return @{ Action='MIGRATE'; DestinationType='SharePoint'; DestinationUrl=$site.Trim().TrimEnd('/'); TargetPrincipal=''; TargetLibrary=$lib.Trim(); TargetSubFolder=$folder.Trim(); Notes='' }
        }
    }
}
function Format-Destination {
    param($Row)
    $sub = if (($Row.PSObject.Properties.Name -contains 'TargetSubFolder') -and $Row.TargetSubFolder) { $Row.TargetSubFolder } else { 'root' }
    if ($Row.DestinationType -eq 'OneDrive') {
        return "OneDrive [$($Row.TargetPrincipal)] folder [$sub]"
    }
    $lib = if (($Row.PSObject.Properties.Name -contains 'TargetLibrary') -and $Row.TargetLibrary) { $Row.TargetLibrary } else { 'Documents' }
    return "SharePoint [$($Row.DestinationUrl)] library [$lib] folder [$sub]"
}
function Lzc9c5dadfd0 {
    param($Project, $Dest)
    return [pscustomobject]@{
        Space=$Project.Name; SpaceId=$Project.Id; SourceSubPath=''; SourceContentsOnly=''; Type='Project'; OwnerResolved='n/a'
        DestinationType=$Dest.DestinationType; DestinationUrl=$Dest.DestinationUrl
        TargetPrincipal=$Dest.TargetPrincipal; TargetLibrary=$Dest.TargetLibrary; TargetSubFolder=$Dest.TargetSubFolder
        Action=$Dest.Action; Notes=$Dest.Notes
    }
}
function Lz8e036f1614 {
    param($Config, [switch]$NonInteractive)
    Lzffe69bba89 -Config $Config -Stage 'api-discovery'
    Lz35962d6dcd -Config $Config
    if (-not $NonInteractive) { Connect-Destination -Config $Config }
    $projects = @(Get-DattoSpaces -Config $Config)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($NonInteractive) {
        foreach ($s in $projects) {
            $rows.Add((Lzc9c5dadfd0 -Project $s -Dest @{ Action='MIGRATE'; DestinationType='SharePoint'; DestinationUrl="$($Config.destination.teamSiteBaseUrl)/$((ConvertTo-Slug $s.Name))"; TargetPrincipal=''; TargetLibrary=''; TargetSubFolder=''; Notes='auto (non-interactive)' }))
        }
    } else {
        $remaining = New-Object System.Collections.Generic.List[object]
        foreach ($p in $projects) { $remaining.Add($p) }
        while ($remaining.Count -gt 0) {
            Write-Host ""
            Write-Host "Sources still available:" -ForegroundColor Cyan
            for ($n = 0; $n -lt $remaining.Count; $n++) { Write-Host ("  {0}. {1}" -f ($n + 1), $remaining[$n].Name) }
            if ($rows.Count -gt 0) {
                Write-Host "Mapped so far:" -ForegroundColor DarkGray
                foreach ($r in $rows) {
                    $w = if ($r.DestinationType -eq 'OneDrive') { "OneDrive:$($r.TargetPrincipal)" } else { $r.DestinationUrl }
                    Write-Host ("  - {0} -> {1} {2}" -f $r.Space, $w, $(if($r.TargetSubFolder){"/$($r.TargetSubFolder)"}else{'(root)'})) -ForegroundColor DarkGray
                }
            }
            $pick = "$(Read-Host "Pick a source number to map, or 'done' to finish")".Trim().ToLower()
            if ($pick -eq 'done' -or $pick -eq 'proceed' -or $pick -eq '') { break }
            if ($pick -notmatch '^\d+$') { Write-Host "  Enter a number, or 'done'." -ForegroundColor DarkGray; continue }
            $n = [int]$pick
            if ($n -lt 1 -or $n -gt $remaining.Count) { Write-Host "  Out of range." -ForegroundColor DarkGray; continue }
            $proj = $remaining[$n - 1]
            $dest = Lz2db64bd078 -Config $Config -Project $proj
            if ($dest.Action -eq 'MIGRATE') {
                $newRow = Lzc9c5dadfd0 -Project $proj -Dest $dest
                $rows.Add($newRow)
                Write-Host ("  mapped: source [{0}] -> destination {1}" -f $proj.Name, (Format-Destination -Row $newRow)) -ForegroundColor Green
            } else {
                Write-Host ("  {0} left unmapped." -f $proj.Name) -ForegroundColor DarkGray
            }
            $remaining.RemoveAt($n - 1)
        }
    }
    if ($rows.Count -eq 0) { Lz12e519cc30 WARN "No sources mapped, nothing to migrate. mapping.csv not written."; return }
    $out = Join-Path $Config.run.reportRoot 'mapping.csv'
    ($rows | Sort-Object Space) | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
    Lz12e519cc30 OK "Discovery complete. $($rows.Count) project(s) mapped. Review: $out"
}
function Lz52638821a3 {
    param($Config)
    Lzffe69bba89 -Config $Config -Stage 'api-preflight'
    Lz35962d6dcd -Config $Config
    Connect-Destination -Config $Config
    $map = @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')
    $invalidRegex = '[' + [regex]::Escape('"*:<>?|') + ']'
    $maxPath = 400
    $sanitise = (($Config.run.PSObject.Properties.Name -contains 'sanitiseNames') -and $Config.run.sanitiseNames)
    $issues  = New-Object System.Collections.Generic.List[object]
    $summary = New-Object System.Collections.Generic.List[object]
    $renameCount = 0; $failCount = 0
    $allItems = New-Object System.Collections.Generic.List[object]
    $allBytes = [int64]0
    $t = $map.Count; $i = 0
    foreach ($row in $map) {
        $i++; Lz390831b78c -Activity 'Pre-flight' -Status $row.Space -Current $i -Total $t | Out-Null
        $space = New-SpaceRef -Row $row
        $items = @(Get-DattoItems -Config $Config -Space $space)
        $bytes = [int64](($items | Measure-Object Size -Sum).Sum)
        $allBytes += $bytes
        foreach ($it in $items) { [void]$allItems.Add([pscustomobject]@{ Space = $row.Space; RelativePath = $it.RelativePath; Size = [int64]$it.Size; ModifiedUtc = "$($it.ModifiedUtc)"; Hash = "$($it.Hash)" }) }
        $effSubPre = Join-SubPath $row.TargetSubFolder (Get-NestFolder $Config $row)
        foreach ($it in $items) {
            $p = @()
            $subLen = $(if ($effSubPre) { $effSubPre.Length + 1 } else { 0 })
            $destLen = $row.DestinationUrl.Length + 1 + $subLen + $it.RelativePath.Length
            if ($destLen -gt $maxPath) { $p += "path too long ($destLen > $maxPath): WILL FAIL - shorten the target folder/library name"; $failCount++ }
            if ((Split-Path $it.RelativePath -Leaf) -match $invalidRegex) {
                if ($sanitise) { $p += 'illegal character: will be auto-renamed on upload (migrates fine)'; $renameCount++ }
                else { $p += 'illegal character: WILL FAIL - set run.sanitiseNames to true'; $failCount++ }
            }
            if ($p.Count) { $issues.Add([pscustomobject]@{ Space = $row.Space; File = $it.RelativePath; Problem = ($p -join '; ') }) }
        }
        $verdict = 'REVIEW'; $freeTxt = 'UNKNOWN'
        if ($Config.destination.provider -eq 'LocalSim') { $verdict = 'SIM'; $freeTxt = 'SIM' }
        else {
            try {
                $drive = if ($row.DestinationType -eq 'OneDrive') {
                    Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($row.TargetPrincipal))/drive"
                } else {
                    $sr = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites?search=$([uri]::EscapeDataString($row.Space))"
                    $s = @($sr['value']) | Select-Object -First 1
                    if ($s) { $dr = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($s['id'])/drives"; @($dr['value']) | Select-Object -First 1 }
                }
                $q = if ($drive) { $drive['quota'] } else { $null }
                if ($q -and $q['total']) {
                    $free = [int64]$q['total'] - [int64]$q['used']
                    $verdict = if ($free -ge $bytes) { 'OK' } else { 'BLOCKED' }
                    $freeTxt = [string]([math]::Round($free/1GB,2)) + 'GB'
                } else { $freeTxt = 'NOT-PROVISIONED' }
            } catch { $freeTxt = 'ERROR'; $verdict = 'REVIEW' }
        }
        $summary.Add([pscustomobject]@{ Space = $row.Space; Type = $row.Type; RequiredGB = [math]::Round($bytes/1GB,2); Free = $freeTxt; Verdict = $verdict })
        if ($verdict -eq 'BLOCKED') { Lz12e519cc30 ERROR "  BLOCKED: $($row.Space) needs $([math]::Round($bytes/1GB,2))GB, free $freeTxt. In plain terms: the destination does not have enough free space for this project. Free up space or increase the storage quota, then run this again." }
    }
    try { Write-Progress -Activity 'Pre-flight' -Completed } catch {}
    $issues  | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-issues.csv') -NoTypeInformation -Encoding UTF8
    $summary | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-summary.csv') -NoTypeInformation -Encoding UTF8
    $blocked = @($summary | Where-Object Verdict -eq 'BLOCKED').Count
    Lz12e519cc30 OK "Readiness check complete. $blocked destination(s) blocked for lack of storage - 'Upload all files' will skip those."
    if ($renameCount -gt 0) { Lz12e519cc30 INFO "$renameCount file(s) have illegal characters and will be AUTO-RENAMED on upload (they migrate, nothing skipped)." }
    if ($failCount -gt 0)   { Lz12e519cc30 WARN "$failCount file(s) WILL FAIL (path too long, or illegal char with sanitiseNames off). See api-preflight-issues.csv. In plain terms: some files have names or folder paths SharePoint cannot accept. They will be skipped unless shortened or renamed first." }
    if ($issues.Count -eq 0) { Lz12e519cc30 OK "No file name/path issues." }
    $topN = if ($script:AssessmentTopFiles -gt 0) { $script:AssessmentTopFiles } else { 20 }
    $largestRows = @($allItems | Sort-Object Size -Descending | Select-Object -First $topN | ForEach-Object {
        [pscustomobject]@{ Space = $_.Space; RelativePath = $_.RelativePath; SizeBytes = [int64]$_.Size; ModifiedUtc = $_.ModifiedUtc }
    })
    $largestRows | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-largest-files.csv') -NoTypeInformation -Encoding UTF8
    if ($largestRows.Count) { Lz12e519cc30 INFO "Largest file: $(Format-Bytes ([int64]$largestRows[0].SizeBytes)) - $($largestRows[0].Space)/$($largestRows[0].RelativePath). The biggest $($largestRows.Count) are in api-preflight-largest-files.csv." }
    $dupRows = New-Object System.Collections.Generic.List[object]
    $gid = 0
    foreach ($g in (@($allItems | Where-Object { [int64]$_.Size -gt 0 -and "$($_.Hash)".Trim() }) | Group-Object Hash | Where-Object { $_.Count -gt 1 } | Sort-Object { [int64]$_.Group[0].Size } -Descending)) {
        $gid++
        foreach ($x in $g.Group) { [void]$dupRows.Add([pscustomobject]@{ DuplicateGroupId = $gid; Hash = $g.Name; Space = $x.Space; RelativePath = $x.RelativePath; SizeBytes = [int64]$x.Size }) }
    }
    $dupRows | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-duplicates.csv') -NoTypeInformation -Encoding UTF8
    if ($gid -gt 0) {
        $wasted = [int64](@($dupRows | Group-Object DuplicateGroupId | ForEach-Object { [int64]$_.Group[0].SizeBytes * ($_.Count - 1) } | Measure-Object -Sum).Sum)
        Lz12e519cc30 INFO "$gid set(s) of duplicate files (identical content), about $(Format-Bytes $wasted) in redundant copies. See api-preflight-duplicates.csv. Nothing is de-duplicated automatically; this is for review before migrating."
    } else {
        Lz12e519cc30 INFO "No duplicate files detected by content hash."
    }
    $rate = $null; $rateFrom = ''
    foreach ($a in @(Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $rows = @(Import-Csv $a.FullName)
            $cp = @($rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' })
            if (-not $cp.Count) { continue }
            $tms = @($rows | ForEach-Object { try { [datetime]::Parse($_.TimestampUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch {} } | Where-Object { $_ })
            if ($tms.Count -lt 2) { continue }
            $sec = (($tms | Measure-Object -Maximum).Maximum - ($tms | Measure-Object -Minimum).Minimum).TotalSeconds
            $cb  = [int64](@($cp | Measure-Object SourceSizeBytes -Sum).Sum)
            if ($sec -ge 5 -and $cb -gt 0) { $rate = ($cb * 8.0 / 1e6) / $sec; $rateFrom = $a.Name; break }
        } catch {}
    }
    if ($rate -and $rate -gt 0 -and $allBytes -gt 0) {
        $secs = ($allBytes * 8.0) / ($rate * 1e6)
        Lz12e519cc30 INFO "Estimated transfer time for $(Format-Bytes $allBytes): about $(Format-Duration ([TimeSpan]::FromSeconds($secs))), at this job's last measured throughput of $([math]::Round($rate,1)) Mb/s (from $rateFrom). Actual time depends on your line speed and Microsoft 365 throttling."
    } else {
        Lz12e519cc30 INFO "No duration estimate yet: this job has no completed upload to measure real throughput from. One will appear here after the first upload finishes."
    }
}
function Lzf329c4956e {
    param([string]$AuditFile,[string]$Status,[string]$Reason,[int]$Processed,[int]$Expected,[int]$Copied,[int]$Skipped,
          [int]$Failed,[int]$VerifyFail,[int]$ZeroByte,[int64]$Bytes,[int]$SpacesPlanned,[int]$SpacesCompleted,[string]$ElapsedText)
    if (-not $AuditFile) { return }
    $now = Get-Date
    $rec = [pscustomobject][ordered]@{
        TimestampUtc=$now.ToUniversalTime().ToString('o'); TimestampLocal=$now.ToString('yyyy-MM-dd HH:mm:ss')
        Space='(run)'; SourcePath='(run-end)'; DestPath=''; Renamed=$false; RenamedFrom=''
        Status="RUN_END:$Status"; SourceSizeBytes=[int64]$Bytes; DestSizeBytes=[int64]$Bytes
        SourceModifiedUtc=''; SourceMd5=''; Method=''; DownloadMs=0; UploadMs=0; Retries=0
        Reason=("$Status | $Reason | processed $Processed of $Expected | copied $Copied skipped $Skipped failed $Failed verifyFail $VerifyFail zero $ZeroByte | spaces $SpacesCompleted/$SpacesPlanned | elapsed $ElapsedText")
        Error=''
    }
    for ($i=1;$i -le 5;$i++){ try { $rec | Export-Csv -Path $AuditFile -Append -NoTypeInformation -Encoding UTF8; break } catch { Start-Sleep -Milliseconds (120*$i) } }
}
function Lz8837d4d9c9 { param($Config) return (Join-Path $Config.run.reportRoot 'run-active.json') }
function Lz2a3d4bb598 {
    param($Config,[string]$Mode,[datetime]$StartUtc,[string]$AuditFile,[int]$ExpectedFiles,[int]$SpacesPlanned,[int]$SpacesCompleted)
    $o = [ordered]@{ Status='RUNNING'; Pid=$PID; Mode=$Mode; StartUtc=$StartUtc.ToUniversalTime().ToString('o')
        AuditFile=$AuditFile; ExpectedFiles=$ExpectedFiles; SpacesPlanned=$SpacesPlanned; SpacesCompleted=$SpacesCompleted }
    try { [System.IO.File]::WriteAllText((Lz8837d4d9c9 $Config), ($o | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false)) } catch {}
}
function Lzf2c52e2d63 { param($Config) try { Remove-Item (Lz8837d4d9c9 $Config) -Force -ErrorAction SilentlyContinue } catch {} }
function Get-EmailRegValue {
    param([string]$Name)
    try { return [string]((Get-ItemProperty -Path 'HKCU:\Software\DattoMigration' -Name $Name -ErrorAction Stop).$Name) } catch { return $null }
}
function Get-EmailNotifySettings {
    try {
        if ($env:LISCARA_EMAIL_SETTINGS -and (Test-Path $env:LISCARA_EMAIL_SETTINGS)) {
            $j = Get-Content $env:LISCARA_EMAIL_SETTINGS -Raw | ConvertFrom-Json
            $gv = { param($n) $p = $j.PSObject.Properties[$n]; if ($p -and $null -ne $p.Value) { [string]$p.Value } else { $null } }
            return @{
                Enabled = (& $gv 'Enabled'); Sender = (& $gv 'Sender'); Recipients = (& $gv 'Recipients'); Subject = (& $gv 'Subject')
                OnSuccess = (& $gv 'OnSuccess'); OnWarning = (& $gv 'OnWarning'); OnFailure = (& $gv 'OnFailure')
                OnTransfer = (& $gv 'OnTransfer'); OnDelta = (& $gv 'OnDelta'); OnValidate = (& $gv 'OnValidate'); OnSizeCheck = (& $gv 'OnSizeCheck')
                Attach = (& $gv 'Attach'); MaxAttachMB = (& $gv 'MaxAttachMB')
            }
        }
        return @{
            Enabled = (Get-EmailRegValue 'EmailEnabled'); Sender = (Get-EmailRegValue 'EmailSender')
            Recipients = (Get-EmailRegValue 'EmailRecipients'); Subject = (Get-EmailRegValue 'EmailSubject')
            OnSuccess = (Get-EmailRegValue 'EmailOnSuccess'); OnWarning = (Get-EmailRegValue 'EmailOnWarning'); OnFailure = (Get-EmailRegValue 'EmailOnFailure')
            OnTransfer = (Get-EmailRegValue 'EmailOnTransfer'); OnDelta = (Get-EmailRegValue 'EmailOnDelta')
            OnValidate = (Get-EmailRegValue 'EmailOnValidate'); OnSizeCheck = (Get-EmailRegValue 'EmailOnSizeCheck')
            Attach = (Get-EmailRegValue 'EmailAttach'); MaxAttachMB = (Get-EmailRegValue 'EmailMaxAttachMB')
        }
    } catch { return $null }
}
function Lz27226ed768 {
    if ($null -ne $script:ToolVersionCache) { return $script:ToolVersionCache }
    $v = ''
    try {
        $gui = Join-Path $PSScriptRoot 'DattoMigration-GUI.ps1'
        if (Test-Path $gui) {
            $m = [regex]::Match((Get-Content $gui -Raw), '\$script:AppVersion\s*=\s*''([^'']+)''')
            if ($m.Success) { $v = $m.Groups[1].Value }
        }
    } catch {}
    $script:ToolVersionCache = $v
    return $v
}
function Get-EmailCommonVars {
    param($Config)
    $job = ''
    try {
        $jj = Join-Path (Split-Path -Parent $ConfigPath) 'job.json'
        if (Test-Path $jj) {
            $jd = Get-Content $jj -Raw | ConvertFrom-Json
            $p = $jd.PSObject.Properties['name']
            if ($p -and $p.Value) { $job = [string]$p.Value }
        }
        if (-not $job) { $job = [IO.Path]::GetFileName((Split-Path -Parent $ConfigPath)) }
    } catch {}
    $tenant = ''
    try {
        $org = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop
        $doms = @(@($org['value'])[0]['verifiedDomains'])
        $best = @($doms | Where-Object { $_['isDefault'] -and ("$($_['name'])" -notlike '*.onmicrosoft.com') })
        if (-not $best.Count) { $best = @($doms | Where-Object { "$($_['name'])" -notlike '*.onmicrosoft.com' }) }
        if (-not $best.Count) { $best = @($doms) }
        if ($best.Count) { $tenant = "$($best[0]['name'])" }
    } catch {}
    if (-not $tenant) { try { $tenant = "$($Config.auth.tenantId)" } catch {} }
    return @{ JobName = $job; Tenant = $tenant; Version = (Lz27226ed768) }
}
function Get-EmailScopeVars {
    param($Config)
    $src = ''; $dst = ''
    try {
        $map = @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')
        if ($map.Count -eq 1) {
            $src = "$($map[0].Space)"
            $pp = $map[0].PSObject.Properties['SourceSubPath']
            if ($pp -and "$($pp.Value)".Trim()) { $src += " / $($pp.Value)" }
            $tp = $map[0].PSObject.Properties['TargetPrincipal']
            if ($tp) { $dst = "$($tp.Value)" }
        } elseif ($map.Count -gt 1) {
            $src = "$($map.Count) projects"; $dst = "$($map.Count) destinations"
        }
    } catch {}
    return @{ Source = $src; Destination = $dst }
}
function Resolve-EmailTemplate {
    param([string]$Template, [hashtable]$Vars)
    $out = "$Template"
    foreach ($k in @($Vars.Keys)) { $out = $out.Replace('{' + $k + '}', "$($Vars[$k])") }
    $out = [regex]::Replace($out, '\{(JobName|Action|Outcome|Source|Destination|FilesCopied|FilesFailed|Errors|SizeCopied|Duration|StartTime|EndTime|Tenant|Version)\}', '')
    return ([regex]::Replace($out, '\s{2,}', ' ')).Trim()
}
function Get-EmailAttachmentSet {
    param([string[]]$Paths, [double]$MaxMB)
    $result = @{ Files = @(); Note = '' }
    try {
        $ex = @()
        foreach ($p in $Paths) { if ($p -and (Test-Path $p)) { $ex += (Get-Item $p) } }
        if (-not $ex.Count) { return $result }
        $limit = [int64]($MaxMB * 1MB)
        $tot = [int64](($ex | Measure-Object Length -Sum).Sum)
        if ($tot -le $limit) { $result.Files = @($ex.FullName); return $result }
        $zip = Join-Path ([IO.Path]::GetTempPath()) ('liscara-run-files-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.zip')
        try {
            Compress-Archive -Path @($ex.FullName) -DestinationPath $zip -Force
            if ((Get-Item $zip).Length -le $limit) {
                $result.Files = @($zip)
                $result.Note = 'The run files are attached as one zip; together they were too large to attach individually.'
                return $result
            }
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
        } catch {}
        $kept = @(); [int64]$acc = 0; $dropped = @()
        foreach ($f in $ex) {
            if (($acc + $f.Length) -le $limit) { $kept += $f.FullName; $acc += $f.Length }
            else { $dropped += $f }
        }
        $result.Files = $kept
        $result.Note = 'Too large to attach, still on the migration computer: ' + (@($dropped | ForEach-Object { "$($_.Name) ($([math]::Round($_.Length/1MB,1)) MB) at $($_.FullName)" }) -join '; ') + '.'
    } catch { $result.Note = 'Attachments could not be prepared; the files remain on the migration computer.' }
    return $result
}
function Send-RunEmail {
    param($Config,
          [string]$ActionKey,
          [string]$ActionLabel,
          [string]$OutcomeBucket,
          [string]$OutcomeLabel,
          [hashtable]$Vars,
          [string[]]$AttachPaths,
          [string[]]$BodyLines)
    try {
        $s = Get-EmailNotifySettings
        if (-not $s) { return }
        if ("$($s.Enabled)" -ne '1') { return }
        $prov = ''; try { $prov = "$($Config.destination.provider)" } catch {}
        if ($prov -eq 'LocalSim' -and -not $env:LISCARA_EMAIL_TEST) { return }
        if (-not "$($s.Sender)".Trim() -or -not "$($s.Recipients)".Trim()) {
            Lz12e519cc30 WARN 'Email alerts are switched on but the sender or recipients are missing (Settings > Email alerts). No email was sent; the run itself is unaffected.'
            return
        }
        $wantOutcome = switch ($OutcomeBucket) {
            'Success' { "$($s.OnSuccess)" } 'Warning' { "$($s.OnWarning)" } default { "$($s.OnFailure)" }
        }
        if ($wantOutcome -eq '0') { return }
        $wantAction = switch ($ActionKey) {
            'Transfer' { "$($s.OnTransfer)" } 'Delta' { "$($s.OnDelta)" } 'Validate' { "$($s.OnValidate)" } 'SizeCheck' { "$($s.OnSizeCheck)" } default { '1' }
        }
        if ($wantAction -eq '0') { return }
        $all = Get-EmailCommonVars -Config $Config
        foreach ($k in @($Vars.Keys)) { $all[$k] = $Vars[$k] }
        if (-not $all.ContainsKey('Action'))  { $all['Action']  = $ActionLabel }
        if (-not $all.ContainsKey('Outcome')) { $all['Outcome'] = $OutcomeLabel }
        $tmpl = "$($s.Subject)"; if (-not $tmpl.Trim()) { $tmpl = $script:EmailDefaultSubject }
        $subject = Resolve-EmailTemplate -Template $tmpl -Vars $all
        if (-not $subject) { $subject = "Migration $ActionLabel $OutcomeLabel" }
        $to = @()
        foreach ($r in ("$($s.Recipients)" -split '[;,\r\n]+')) {
            $a = "$r".Trim()
            if ($a -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $to += @{ emailAddress = @{ address = $a } } }
            elseif ($a) { Lz12e519cc30 WARN "Email alerts: '$a' does not look like an email address and was skipped." }
        }
        if (-not $to.Count) {
            Lz12e519cc30 WARN 'Email alerts: no valid recipient address is configured. No email was sent; the run itself is unaffected.'
            return
        }
        $atts = @(); $attachNote = ''
        if ("$($s.Attach)" -ne '0') {
            $maxMB = $script:EmailMaxAttachMB
            try { if ("$($s.MaxAttachMB)" -match '^\d+(\.\d+)?$') { $maxMB = [double]$s.MaxAttachMB } } catch {}
            $set = Get-EmailAttachmentSet -Paths $AttachPaths -MaxMB $maxMB
            $attachNote = "$($set.Note)"
            foreach ($f in @($set.Files)) {
                try {
                    $atts += @{
                        '@odata.type' = '#microsoft.graph.fileAttachment'
                        name          = [IO.Path]::GetFileName($f)
                        contentBytes  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f))
                    }
                } catch { Lz12e519cc30 WARN "Email alerts: could not read attachment $f ($($_.Exception.Message)); sending without it." }
            }
        }
        $esc = { param($t) [System.Net.WebUtility]::HtmlEncode("$t") }
        $rows = ''
        foreach ($ln in @($BodyLines)) {
            if (-not "$ln".Trim()) { continue }
            $parts = @("$ln" -split ':', 2)
            $lab = & $esc $parts[0]
            $val = if ($parts.Count -gt 1) { & $esc "$($parts[1])".Trim() } else { '' }
            $rows += ('<tr><td style="padding:2px 14px 2px 0;color:#475467;white-space:nowrap;vertical-align:top;">' + $lab + '</td><td style="padding:2px 0;color:#101828;">' + $val + '</td></tr>')
        }
        $html = '<html><body style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#101828;">' +
                '<p style="font-size:16px;font-weight:600;">' + (& $esc $subject) + '</p>' +
                '<table style="border-collapse:collapse;">' + $rows + '</table>' +
                $(if ($attachNote) { '<p style="color:#B54708;">' + (& $esc $attachNote) + '</p>' } else { '' }) +
                '<p style="color:#98A2B3;font-size:12px;">Sent by the Datto Workplace to SharePoint Migrator' +
                $(if ("$($all['Version'])") { ' v' + (& $esc $all['Version']) } else { '' }) +
                ' from this organisation''s own Microsoft 365 tenant. The audit CSV on the migration computer is the authoritative record of the run.</p>' +
                '</body></html>'
        $script:EmailMsgBody = @{
            message = @{
                subject = $subject
                body = @{ contentType = 'HTML'; content = $html }
                toRecipients = $to
                attachments = $atts
            }
            saveToSentItems = $true
        }
        $emSender = "$($s.Sender)".Trim()
        Invoke-WithRetry -Config $Config -What 'completion email' -Action {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$emSender/sendMail" -Body $script:EmailMsgBody -ErrorAction Stop | Out-Null
        } | Out-Null
        Lz12e519cc30 OK "Completion email sent from $emSender to $(@($to).Count) recipient(s)$(if ($atts.Count) { " with $($atts.Count) attachment(s)" })."
    } catch {
        Lz12e519cc30 WARN "The completion email could not be sent: $($_.Exception.Message). The run itself is unaffected; the outcome above stands. Check Settings > Email alerts (sender, recipients, Mail.Send permission)."
    }
}
function Invoke-RunFinalize {
    param($Config,[string]$AuditFile,[string]$Mode='FirstPass',[datetime]$RunStart=(Get-Date),
          [int]$ExpectedFiles=0,[int]$SpacesPlanned=0,[int]$SpacesCompleted=0,$RunError=$null,
          [string]$ForcedStatus='',[string]$ForcedReason='')
    $elapsed = (Get-Date) - $RunStart
    $el = '{0:hh\:mm\:ss}' -f $elapsed
    $copied=0;$skipped=0;$failed=0;$verify=0;$zero=0;$processed=0;[int64]$bytes=0;$auditWriteFails=0
    $auditRows = @()
    if ($AuditFile -and (Test-Path $AuditFile)) {
        for ($t=1;$t -le 6;$t++){ try { $auditRows = @(Import-Csv $AuditFile); break } catch { Start-Sleep -Milliseconds (150*$t) } }
    }
    foreach ($r in $auditRows) {
        switch ("$($r.Status)") {
            'Copied'        { $copied++; $processed++; try { $bytes += [int64]$r.SourceSizeBytes } catch {} }
            'ZeroByte'      { $zero++; $copied++; $processed++ }
            'Skipped'       { $skipped++; $processed++ }
            'VerifyFail'    { $verify++; $processed++ }
            'Error'         { $failed++; $processed++ }
            'DownloadError' { $failed++; $processed++ }
            'SkippedTooLarge' { $failed++; $processed++ }
            'WouldCopy'     { $processed++ }
            default { }
        }
    }
    try { $auditWriteFails = [int]$script:AuditWriteFails } catch {}
    $errCount = $failed + $verify
    if ($ForcedStatus) {
        $status = $ForcedStatus; $reason = $ForcedReason
    } else {
        $finished = (-not $RunError) -and ($SpacesCompleted -ge $SpacesPlanned)
        if (-not $finished)      { $status='ENDED_EARLY'; $reason = if ($RunError) { $RunError.Exception.Message } else { "stopped after $SpacesCompleted of $SpacesPlanned project(s)" } }
        elseif ($errCount -gt 0) { $status='COMPLETED_WITH_ERRORS'; $reason = "$errCount file(s) failed or could not be verified" }
        else                     { $status='COMPLETED'; $reason='' }
    }
    if ($auditWriteFails -gt 0) { $reason = ("$reason (note: $auditWriteFails audit row(s) could not be written, so counts may under-report)").Trim() }
    $szTxt = Format-Bytes $bytes
    try {
        Lzf329c4956e -AuditFile $AuditFile -Status $status -Reason $reason -Processed $processed -Expected $ExpectedFiles `
            -Copied $copied -Skipped $skipped -Failed $failed -VerifyFail $verify -ZeroByte $zero `
            -Bytes $bytes -SpacesPlanned $SpacesPlanned -SpacesCompleted $SpacesCompleted -ElapsedText $el
    } catch {}
    $outcome = [ordered]@{
        Status=$status; Reason=$reason; Mode=$Mode; Finished=($status -eq 'COMPLETED' -or $status -eq 'COMPLETED_WITH_ERRORS')
        StartUtc=$RunStart.ToUniversalTime().ToString('o'); EndUtc=(Get-Date).ToUniversalTime().ToString('o'); ElapsedText=$el
        ExpectedFiles=$ExpectedFiles; ProcessedFiles=$processed
        Resumed=[bool]$script:UseEnumCache
        Copied=$copied; Skipped=$skipped; Failed=$failed; VerifyFail=$verify; ZeroByte=$zero
        Bytes=$bytes; BytesText=$szTxt; SpacesPlanned=$SpacesPlanned; SpacesCompleted=$SpacesCompleted
        AuditWriteFails=$auditWriteFails; AuditFile="$AuditFile"; LogFile="$script:LogFile"
        SpoolEncrypted=[bool]$script:SpoolEncrypt
        TrialMode=($null -ne $script:TrialCap); TrialLimit=$script:TrialFileLimit; TrialCapped=[bool]$script:TrialCapped
        ToolVersion=(Lz27226ed768)
    }
    $json = ($outcome | ConvertTo-Json -Depth 4)
    $sidecar = ($AuditFile -replace '\.csv$','') + '.outcome.json'
    foreach ($p in @($sidecar, (Join-Path $Config.run.reportRoot 'lastrun-outcome.json'))) {
        try { [System.IO.File]::WriteAllText($p, $json, [System.Text.UTF8Encoding]::new($false)) } catch {}
    }
    try {
        switch ($status) {
            'COMPLETED'             { Lz12e519cc30 OK    "=== RUN COMPLETE: all $SpacesPlanned project(s) finished. Uploaded $copied file(s) ($szTxt), skipped $skipped unchanged, 0 failures, in $el. ===" }
            'COMPLETED_WITH_ERRORS' { Lz12e519cc30 ERROR "=== RUN COMPLETE WITH ERRORS: reached the end of all $SpacesPlanned project(s). Uploaded $copied ($szTxt), but $errCount file(s) failed or could not be verified and are NOT marked done. Run 'Sync new and changed' to retry just those. ===" }
            'CANCELLED'             { Lz12e519cc30 WARN  "=== RUN CANCELLED by user. Uploaded $copied file(s) ($szTxt) before stopping; those are saved. The rest were NOT uploaded. Click 'Sync new and changed' to carry on from where it stopped: it copies only what is not already there. ===" }
            'INCOMPLETE'            { Lz12e519cc30 ERROR "=== RUN INCOMPLETE: the previous run stopped without finalising (a crash, a forced close, or power loss). $copied file(s) ($szTxt) were recorded as uploaded. Run 'Sync new and changed' to continue and confirm. ===" }
            default                 { Lz12e519cc30 ERROR "=== RUN ENDED EARLY - DID NOT FINISH. Processed $processed file(s) (of ~$ExpectedFiles listed) across $SpacesCompleted of $SpacesPlanned project(s) before stopping. Reason: $reason. The remaining files were NOT uploaded. Fix the cause, then click 'Sync new and changed' to carry on from where it stopped. ===" }
        }
    } catch {}
    if ($script:GuiMode) { try { Write-Host "##OUTCOME##|$status|$processed|$ExpectedFiles|$copied|$failed|$verify|$el|$reason" } catch {} }
    if ($script:GuiMode -and $script:TrialCapped) { try { Write-Host "##TRIAL##|CAPPED|$($script:TrialFileLimit)|$copied" } catch {} }
    if ($script:TrialLedgerKey) { try { Add-EvalUsage -Key $script:TrialLedgerKey -Bucket $script:TrialBucket -Count $copied } catch {} }
    $script:ExitCode = switch ($status) { 'COMPLETED' { 0 } 'COMPLETED_WITH_ERRORS' { 2 } default { 1 } }
    $savedLog = $script:LogFile
    try { Invoke-HtmlReport -Config $Config -AuditPath $AuditFile -NoStageLog | Out-Null } catch {}
    $script:LogFile = $savedLog
    try {
        $emBucket = switch ($status) { 'COMPLETED' { 'Success' } 'COMPLETED_WITH_ERRORS' { 'Warning' } default { 'Failure' } }
        $emAction = if ($Mode -eq 'Delta') { 'Delta' } else { 'Transfer' }
        $emLabel  = if ($Mode -eq 'Delta') { 'Sync' } else { 'Full upload' }
        $emReport = ''
        try { $emReport = "$(@(Get-ChildItem (Join-Path $Config.run.reportRoot 'report-*.html') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)[0].FullName)" } catch {}
        $emVars = Get-EmailScopeVars -Config $Config
        $emVars['Action'] = $emLabel; $emVars['Outcome'] = $status
        $emVars['FilesCopied'] = $copied; $emVars['FilesFailed'] = $failed; $emVars['Errors'] = $errCount
        $emVars['SizeCopied'] = $szTxt; $emVars['Duration'] = $el
        $emVars['StartTime'] = $RunStart.ToString('yyyy-MM-dd HH:mm'); $emVars['EndTime'] = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Send-RunEmail -Config $Config -ActionKey $emAction -ActionLabel $emLabel `
            -OutcomeBucket $emBucket -OutcomeLabel $status -Vars $emVars `
            -AttachPaths @($emReport, "$AuditFile", "$script:LogFile") `
            -BodyLines @(
                "Action: $emLabel",
                "Outcome: $status$(if ($reason) { " ($reason)" })",
                "Copied: $copied file(s) ($szTxt)",
                "Skipped (already up to date): $skipped",
                "Failed: $failed$(if ($verify) { ", plus $verify verify failure(s)" })",
                "Duration: $el",
                "Source: $($emVars['Source'])",
                "Destination: $($emVars['Destination'])")
    } catch {}
    Lzf2c52e2d63 -Config $Config
    return $outcome
}
function Lzf8243e7ae0 {
    param($Config,[string]$Mode,[datetime]$RunStart,[int]$ExpectedFiles,[int]$SpacesPlanned,
          [int]$SpacesCompleted,$RunError,[bool]$WillWrite,[string]$ResultDir='')
    if (-not $WillWrite) { return }
    if ($ResultDir)      { return }
    Invoke-RunFinalize -Config $Config -AuditFile $script:AuditFile -Mode $Mode -RunStart $RunStart `
        -ExpectedFiles $ExpectedFiles -SpacesPlanned $SpacesPlanned -SpacesCompleted $SpacesCompleted -RunError $RunError | Out-Null
}
function Lz9a738a84d1 {
    param($Config,[string]$Status='Incomplete',[string]$AuditPath='')
    Lzffe69bba89 -Config $Config -Stage 'api-finalize'
    $act = $null
    $ap = Lz8837d4d9c9 $Config
    if (Test-Path $ap) { try { $act = Get-Content $ap -Raw | ConvertFrom-Json } catch {} }
    if (-not $AuditPath) {
        if ($act -and $act.AuditFile -and (Test-Path $act.AuditFile)) { $AuditPath = "$($act.AuditFile)" }
        else {
            $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $AuditPath = $latest.FullName }
        }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) {
        Lz12e519cc30 WARN "Record outcome: no audit CSV found, so there is nothing to record."; Lzf2c52e2d63 -Config $Config; return
    }
    $sidecar = ($AuditPath -replace '\.csv$','') + '.outcome.json'
    if (Test-Path $sidecar) { Lz12e519cc30 INFO "Record outcome: the run already has an outcome; leaving it as it is."; Lzf2c52e2d63 -Config $Config; return }
    $su = if ($act -and $act.StartUtc) { try { [datetime]::Parse($act.StartUtc,$null,[System.Globalization.DateTimeStyles]::RoundtripKind) } catch { (Get-Date) } } else { (Get-Date) }
    $mode = if ($act -and $act.Mode) { "$($act.Mode)" } else { 'FirstPass' }
    $exp  = if ($act) { [int]$act.ExpectedFiles } else { 0 }
    $sp   = if ($act) { [int]$act.SpacesPlanned } else { 0 }
    $sc   = if ($act) { [int]$act.SpacesCompleted } else { 0 }
    $fs = if ($Status -match '^(?i)cancel') { 'CANCELLED' } else { 'INCOMPLETE' }
    $fr = if ($fs -eq 'CANCELLED') { 'stopped by the user' } else { 'the run did not finalise (crash, forced close, or power loss)' }
    Invoke-RunFinalize -Config $Config -AuditFile $AuditPath -Mode $mode -RunStart $su `
        -ExpectedFiles $exp -SpacesPlanned $sp -SpacesCompleted $sc -ForcedStatus $fs -ForcedReason $fr | Out-Null
}
function Lz4f4fde1a18 {
    param([string]$Path)
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if (-not $root) { return -1 }
        return ([System.IO.DriveInfo]::new($root)).AvailableFreeSpace
    } catch { return -1 }
}
function Lz5306d4ce4e {
    param($Config)
    try {
        $thumb = "$($Config.auth.certThumbprint)".Trim()
        if (-not $thumb -or $thumb -like 'reg:*') { return }
        $store = 'Cert:\CurrentUser\My'
        try { if (($Config.auth.PSObject.Properties.Name -contains 'certStore') -and $Config.auth.certStore) { $store = "$($Config.auth.certStore)" } } catch {}
        $cert = Get-ChildItem -Path $store -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
        if (-not $cert) { return }
        $days = [math]::Floor(($cert.NotAfter.ToUniversalTime() - [DateTime]::UtcNow).TotalDays)
        if ($days -lt 0) {
            throw "The sign-in certificate expired on $($cert.NotAfter.ToString('yyyy-MM-dd')). Uploads cannot authenticate until it is renewed, so nothing was uploaded. Renew the app certificate and update its thumbprint in Settings."
        } elseif ($days -le 7) {
            Lz12e519cc30 WARN "  the sign-in certificate expires in $([int]$days) day(s) (on $($cert.NotAfter.ToString('yyyy-MM-dd'))). Renew it soon to avoid a mid-run authentication failure."
        }
    } catch { throw }
}
function Lz79ee3b5706 {
    param($Config)
    if ($Config.datto.provider -eq 'LocalSim') { return }
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPath)) { return }
    $known = @{}
    try { foreach ($p in @(Get-DattoSpaces -Config $Config)) { $known["$($p.Id)"] = $p.Name } } catch { return }
    if (-not $known.Count) { return }
    foreach ($row in @(Import-Csv $mapPath | Where-Object Action -eq 'MIGRATE')) {
        $id = "$($row.SpaceId)"
        if ($id -and -not $known.ContainsKey($id)) {
            throw "mapping.csv row '$($row.Space)' has SpaceId '$id', which is not one of this account's Datto projects. If you were trying to migrate a single folder, do NOT put the folder's id here: it silently strips the folder's path from every destination file, and a later full Sync then copies them all again to the right place and leaves the first set behind as orphans. Put the space's real id back, and set the SourceSubPath column to the folder path instead (for example: Drawings/Current). Nothing has been uploaded."
        }
    }
}
function Lz249c9cb407 {
    param($Config)
    if ($script:LegacyStateNoticeDone) { return }
    $script:LegacyStateNoticeDone = $true
    try {
        $root = $Config.run.stateRoot
        if (-not $root -or -not (Test-Path $root)) { return }
        $old = @(Get-ChildItem -Path $root -Filter 'apistate-*.json' -File -ErrorAction SilentlyContinue)
        if (-not $old.Count) { return }
        Lz12e519cc30 INFO "  found $($old.Count) resume record(s) from an older version in [$root]. They are no longer used: the destination is now the source of truth for what has already been copied. They are harmless, and you can delete them whenever you like. Nothing here will delete them for you."
    } catch {}
}
function Lz71cc26b12f {
    param($Config)
    if ($Config.destination.provider -eq 'LocalSim') { return }
    try {
        $tmpRoot = $Config.run.tempWorkingFolder
        if ($tmpRoot -and (Test-Path $tmpRoot)) {
            $orphans = @(Get-ChildItem $tmpRoot -File -Recurse -ErrorAction SilentlyContinue)
            if ($orphans.Count) {
                $orphans | Remove-Item -Force -ErrorAction SilentlyContinue
                Lz12e519cc30 INFO "  cleared $($orphans.Count) leftover temp file(s) from a previous run."
            }
            $freeB = Lz4f4fde1a18 -Path $tmpRoot
            if ($freeB -ge 0) {
                Lz12e519cc30 INFO "  temp drive free space: $(Format-Bytes $freeB) (files are staged here then deleted immediately after upload, so only a handful sit on disk at once)."
                if ($freeB -lt 2GB) { Lz12e519cc30 WARN "  the temp drive has under 2 GB free. Everyday files are fine (only a handful stage at a time), but any single file larger than the free space is skipped and reported. Free space, or point run.tempWorkingFolder at a bigger drive." }
            }
        }
    } catch {}
    Lz5306d4ce4e -Config $Config
}
function Lz0f4f6ef1b4 {
    param($Config, $Rows)
    if ($Config.destination.provider -eq 'LocalSim') { return }
    $seen = @{}
    foreach ($row in $Rows) {
        $key = "$($row.DestinationType)|$($row.DestinationUrl)|$($row.TargetPrincipal)|$($row.TargetLibrary)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $label = Format-Destination -Row $row
        try {
            $res = Resolve-DestinationDriveId -Config $Config -Row $row
            $free = $null
            try {
                $drv = Invoke-WithRetry -Config $Config -What "quota $label" -Action { Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$($res.DriveId)" }
                try { $free = [int64]$drv['quota']['remaining'] } catch { try { $free = [int64]$drv.quota.remaining } catch {} }
            } catch {}
            if ($null -ne $free -and $free -gt 0) {
                $ftxt = Format-Bytes $free
                if ($free -lt 2GB) { Lz12e519cc30 WARN "  destination check: $label is reachable but has only $ftxt free. A large upload may fail part-way; free up space or pick another destination." }
                else { Lz12e519cc30 OK "  destination check: $label reachable, $ftxt free." }
            } else {
                Lz12e519cc30 OK "  destination check: $label reachable."
            }
        } catch {
            throw "Destination not reachable for '$($row.Space)' ($label): $($_.Exception.Message). In plain terms: the place these files were going to could not be opened, so nothing was uploaded. Check the destination and try again."
        }
    }
}
function Invoke-Transfer {
    param($Config, [string]$Mode='FirstPass', [string]$OnlySpace, [string]$Spaces, [int]$SpoolAhead=3,
          [int]$MaxParallelSpaces=1, [int]$UploadWorkers=1, [string]$ResultDir='', [string[]]$RestoreIds=@(),
          [string]$DeltaMode='NewerWins', [switch]$Execute, [switch]$FailedOnly, [string]$FailedFromAudit)
    $restoreSet = @{}; foreach ($rid in $RestoreIds) { $restoreSet["$rid"] = $true }
    if ($Mode -eq 'Resume') {
        $Mode = 'Delta'
        Lz12e519cc30 INFO "Resume now runs as a Sync: it compares Datto against the destination itself, file by file, instead of trusting a local record of the last run. Same intent, and it cannot be fooled by a stale or damaged record."
    }
    Lzffe69bba89 -Config $Config -Stage "api-transfer-$Mode" -Friendly $(
        if (-not $Execute) { 'Preview (nothing copied)' }
        elseif ($Mode -eq 'Delta') { 'Sync new and changed' } else { 'Upload all files' })
    $script:FailedOnlySet = $null
    if ($FailedOnly) {
        $MaxParallelSpaces = 1
        $script:UseEnumCache = $false
        $script:FailedOnlySet = Lzdf43513bbf -Config $Config -AuditPath $FailedFromAudit
    }
    Lz249c9cb407 -Config $Config
    Lz79ee3b5706 -Config $Config
    if ($Execute -and $Config.destination.provider -ne 'LocalSim' -and $null -eq $script:TrialCap) {
        $lzOk = $false; $lzTen = ''
        try {
            $lzP = ''
            try { if (($Config.run.PSObject.Properties.Name -contains 'licenceFile') -and $Config.run.licenceFile) { $lzP = "$($Config.run.licenceFile)" } } catch {}
            if (-not $lzP) { $lzP = Join-Path (Split-Path $PSScriptRoot -Parent) 'licence.json' }
            if (Test-Path $lzP) {
                $lzJ = Get-Content $lzP -Raw | ConvertFrom-Json
                $lzB = [Convert]::FromBase64String("$($lzJ.PayloadB64)")
                $lzE = [System.Security.Cryptography.ECDsa]::Create()
                try {
                    $lzR = 0
                    $lzKey = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEMOOjrKfrPG0mI1XtA+iXZVOwtjp075WeGEYaNZxG0TyVvAp6B9SZ3AAX5Ue7AxQrrwTfDzzX2lIgT7TmVKt9XA=='
                    if ($env:LISCARA_LICKEY_TEST) { $lzKey = "$env:LISCARA_LICKEY_TEST" }
                    $lzE.ImportSubjectPublicKeyInfo([Convert]::FromBase64String($lzKey), [ref]$lzR)
                    if ($lzE.VerifyData($lzB, [Convert]::FromBase64String("$($lzJ.Signature)"), [System.Security.Cryptography.HashAlgorithmName]::SHA256)) {
                        $lzPl = [Text.Encoding]::UTF8.GetString($lzB) | ConvertFrom-Json
                        if ([int]$lzPl.Schema -eq 1) { $lzOk = $true; $lzTen = "$($lzPl.TenantId)" }
                    }
                } finally { $lzE.Dispose() }
            }
        } catch {}
        if ($lzOk) { $script:ScopeRefId = $lzTen }
        else {
            $lzBkt = if ($Mode -eq 'FirstPass') { 'FirstPass' } else { 'Delta' }
            $lzRem = $script:TrialFileLimit
            try {
                $lzU = Get-EvalUsage -Key (Get-EvalKey -TenantId "$($Config.auth.tenantId)")
                $lzSp = if ($lzBkt -eq 'FirstPass') { $lzU.FirstPass } else { $lzU.Delta }
                $lzRem = [Math]::Max(0, $script:TrialFileLimit - $lzSp)
            } catch {}
            $script:TrialCap = $lzRem
            $script:TrialFilesRemaining = $lzRem
            if ($script:GuiMode) { Write-Host "##TRIAL##|START|$lzRem|$lzBkt" }
            Lz12e519cc30 WARN "Evaluation limits apply to this run: up to $lzRem file(s) will be copied. Licence this Microsoft tenant at https://www.liscaragh.com to remove the limit."
        }
    }
    $runStart = Get-Date
    $auditDir = if ($ResultDir) { $ResultDir } else { $Config.run.reportRoot }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:AuditFile = Join-Path $auditDir ("audit-$Mode-$stamp-$PID.csv")
    $script:AuditWriteFails = 0
    $script:RenameFile     = Join-Path $auditDir ("renames-$Mode-$stamp-$PID.csv")
    $script:CollisionFile  = Join-Path $auditDir ("collisions-$Mode-$stamp-$PID.csv")
    $script:RenameCount    = 0
    $script:CollisionCount = 0
    $script:RenameSeenDirs = @{}
    $script:FinalSeen      = @{}
    $willWrite = Test-DestructiveGate -Execute:$Execute
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPath)) { throw "mapping.csv not found. In plain terms: no destinations have been set yet. Set a destination for at least one project and click 'Save mapping', then try again." }
    $map = @(Import-Csv $mapPath | Where-Object Action -eq 'MIGRATE')
    if ($OnlySpace) { $map = @($map | Where-Object Space -eq $OnlySpace); if (-not $map){ throw "Space '$OnlySpace' not found." } }
    if ($Spaces)   { $names = @($Spaces -split ',' | ForEach-Object { $_.Trim() }); $map = @($map | Where-Object { $names -contains $_.Space }); if (-not $map){ throw "None of the batch spaces found: $Spaces" } }
    $blockedSpaces = @()
    $preSum = Join-Path $Config.run.reportRoot 'api-preflight-summary.csv'
    if (Test-Path $preSum) { $blockedSpaces = @((Import-Csv $preSum) | Where-Object Verdict -eq 'BLOCKED' | Select-Object -ExpandProperty Space) }
    else { Lz12e519cc30 INFO "No readiness check was run for this job (it is optional). The upload checks the destination is reachable before it starts, tidies names as it goes, and flags any problems in the report." }
    $runnable = @($map | Where-Object { $blockedSpaces -notcontains $_.Space })
    if ($MaxParallelSpaces -gt 1 -and $runnable.Count -gt 1) {
        Lz52e5b1e5ca -Config $Config -Rows $runnable -Mode $Mode -DeltaMode $DeltaMode -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -Execute:$Execute
        return
    }
    Lz12e519cc30 INFO "This run: $($map.Count) project(s). (Read-ahead: $SpoolAhead file(s).)"
    if ($script:SpoolEncrypt) {
        $script:SpoolKey = New-SpoolKey
        Lz12e519cc30 OK "Files staged on this computer are ENCRYPTED (AES-256) while they wait to upload. The key exists only in this run's memory and dies with it, staged names are random identifiers, and the destination receives the original files unchanged."
    } else {
        $script:SpoolKey = $null
        Lz12e519cc30 INFO "Spool encryption is OFF (run.encryptSpool = false): files staged on this computer are readable while a run is in flight."
    }
    Lz35962d6dcd -Config $Config
    Connect-Destination -Config $Config
    $expectedTotal   = 0
    $spacesPlanned   = @($map | Where-Object { $blockedSpaces -notcontains $_.Space }).Count
    $spacesCompleted = 0
    $transferError   = $null
    if ($willWrite -and -not $ResultDir) { Lz2a3d4bb598 -Config $Config -Mode $Mode -StartUtc $runStart -AuditFile $script:AuditFile -ExpectedFiles 0 -SpacesPlanned $spacesPlanned -SpacesCompleted 0 }
    $summary = New-Object System.Collections.Generic.List[object]
    $sTotal = $map.Count; $sIdx = 0
    try {
    if ($willWrite) { Lz0f4f6ef1b4 -Config $Config -Rows $map; Lz71cc26b12f -Config $Config }
    foreach ($row in $map) {
        $sIdx++
        Lz390831b78c -Activity "Transfer ($Mode)" -Status $row.Space -Current $sIdx -Total $sTotal -Id 1 | Out-Null
        if ($blockedSpaces -contains $row.Space) { Lz12e519cc30 ERROR "SKIPPED '$($row.Space)': the readiness check found too little storage at this destination. Increase the quota or free up space, then run again."; continue }
        Lz12e519cc30 INFO "[$(if (-not $willWrite) { 'Preview' } elseif ($Mode -eq 'Delta') { 'Sync' } else { 'Upload' })] source [$($row.Space)] -> destination $(Format-Destination -Row $row)"
        $space = New-SpaceRef -Row $row
        $overlapListing = $false
        try { if (($Config.run.upload.PSObject.Properties.Name -contains 'overlapListing') -and $Config.run.upload.overlapListing) { $overlapListing = $true } } catch {}
        $streamFP = ($Mode -eq 'FirstPass' -and $willWrite -and $UploadWorkers -gt 1 -and $overlapListing -and ($null -eq $script:TrialCap))
        if ($streamFP) {
            Lz12e519cc30 INFO "  Upload all: listing and uploading run together (files start moving while the folder list is still being read)."
            $items = @()
        } else {
            $rowScope = "$($row.Space)"
            try { if (($row.PSObject.Properties.Name -contains 'SourceSubPath') -and "$($row.SourceSubPath)".Trim()) { $rowScope = "$($row.Space) / $("$($row.SourceSubPath)".Trim().Trim('/'))" } } catch {}
            Lz12e519cc30 INFO "  listing files in [$rowScope] (large projects can take a few minutes, nothing uploads yet)..."
            $items = @(Get-SpaceItemsCached -Config $Config -Space $space)
            Lz12e519cc30 INFO "  listing complete: $($items.Count) file(s)."
        }
        $spaceTemp = Join-Path $Config.run.tempWorkingFolder (ConvertTo-Slug $row.Space)
        if (Test-Path $spaceTemp) { Get-ChildItem $spaceTemp -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
        else { New-Item -ItemType Directory -Path $spaceTemp -Force | Out-Null }
        $driveId = '(dry-run)'; $effSub = (Join-SubPath $row.TargetSubFolder (Get-NestFolder $Config $row))
        if ($willWrite) { $res = Resolve-DestinationDriveId -Config $Config -Row $row; $driveId = $res.DriveId; $effSub = $res.SubFolder }
        $nestNote = if (Get-NestFolder $Config $row) { ' (the project has its own folder inside your chosen destination)' } else { '' }
        if ($effSub) { Lz12e519cc30 INFO "  files land under: [$effSub]$nestNote." }
        elseif ($nestNote) { Lz12e519cc30 INFO "  files land under the project's own folder at the destination root." }
        $copied = 0; $skipped = 0; $failed = 0; $bytes = 0; $verifyFail = 0; $zero = 0
        $presenceMode = $false
        $repair = @{}
        $san = (($Config.run.PSObject.Properties.Name -contains 'sanitiseNames') -and $Config.run.sanitiseNames)
        if ($restoreSet.Count) {
            $toDo = @($items | Where-Object { $restoreSet.ContainsKey("$($_.Id)") })
            Lz12e519cc30 INFO "  restore: $($toDo.Count) selected file(s) will be overwritten at the destination with the Datto version."
        }
        elseif ($Mode -eq 'FirstPass') {
            $toDo = @($items)
        }
        elseif ($Mode -eq 'Delta') {
            $presenceMode = $true
            if ($willWrite) { $inv = Get-DestinationInventory -Config $Config -Row $row -WithTimes }
            else { $inv = @{ Paths = (New-Object 'System.Collections.Generic.HashSet[string]'); Times = @{} } }
            $addOnly = ($DeltaMode -eq 'AddMissing')
            $tol = [TimeSpan]::FromSeconds(2)
            $toDo = @($items | Where-Object {
                $rp = $_.RelativePath -replace '\\','/'; if ($san) { $rp = ConvertTo-SafeRelPath $rp }
                if (-not $inv.Paths.Contains($rp)) { return $true }
                $ds = $null; if ($inv.Sizes -and $inv.Sizes.ContainsKey($rp)) { $ds = [int64]$inv.Sizes[$rp] }
                if ($null -ne $ds -and -not (Lzc4af9c3f51 -RelPath $rp -SourceSize ([int64]$_.Size) -DestSize $ds)) {
                    $repair["$($_.Id)"] = "destination copy was $ds byte(s), source is $($_.Size) byte(s)"
                    return $true
                }
                if ($addOnly) { return $false }
                $st = ConvertTo-UtcDate $_.ModifiedUtc
                $dt = if ($inv.Times.ContainsKey($rp)) { $inv.Times[$rp] } else { $null }
                if ($null -eq $st -or $null -eq $dt) { return $false }
                return ($st -gt $dt.Add($tol))
            })
            $modeTxt = if ($addOnly) { 'add new files only' } else { 'update where Datto is newer' }
            Lz12e519cc30 INFO "  sync ($modeTxt): $($toDo.Count) of $($items.Count) file(s) to copy; the rest are already present and are left as they are."
            if ($repair.Count) {
                Lz12e519cc30 WARN "  $($repair.Count) of those file(s) are ALREADY at the destination but are the wrong size, and will be re-copied to repair them. These are uploads that did not complete correctly on an earlier run, not new or changed files. They are recorded as 'repaired' in the audit CSV, not as ordinary copies."
            }
        }
        else {
            $toDo = @($items)
        }
        $toDo = @($toDo)
        if ($null -ne $script:TrialCap) {
            if ($script:TrialFilesRemaining -le 0) {
                if ($toDo.Count -gt 0) { $script:TrialCapped = $true }
                $toDo = @()
            } elseif ($toDo.Count -gt $script:TrialFilesRemaining) {
                $script:TrialCapped = $true
                $toDo = @($toDo | Select-Object -First $script:TrialFilesRemaining)
            }
            $script:TrialFilesRemaining -= $toDo.Count
        }
        $skipped = $items.Count - $toDo.Count
        $fTotal = $toDo.Count; $fIdx = 0
        $spaceBytesTotal = if ($toDo.Count) { [int64](($toDo | Measure-Object Size -Sum).Sum) } else { [int64]0 }
        $expectedTotal += $fTotal
        if ($willWrite) { Lz67aab01d86 -Done 0 -Total $fTotal -BytesDone 0 -BytesTotal $spaceBytesTotal -Space $row.Space }
        if ($script:GuiMode) { Write-Host "##SCOPE##|$fTotal|$($items.Count)|$skipped" }
        if ($willWrite -and $Mode -ne 'FirstPass') {
            $toDoIds = @($toDo | ForEach-Object { $_.Id })
            foreach ($sk in @($items | Where-Object { $toDoIds -notcontains $_.Id })) {
                Lz3c19440102 -Space $row.Space -Item $sk -Status 'Skipped' -Reason 'already at the destination, intact and not older than the source'
            }
        }
        if (-not $willWrite) {
            $copied = $fTotal; $bytes = $spaceBytesTotal
            foreach ($it in $toDo) { Lz3c19440102 -Space $row.Space -Item $it -Status 'WouldCopy' -Reason 'dry-run' }
        }
        elseif ($UploadWorkers -gt 1) {
            $sanitise = (($Config.run.PSObject.Properties.Name -contains 'sanitiseNames') -and $Config.run.sanitiseNames)
            foreach ($it in $toDo) {
                $rp = if ($effSub) { ($effSub.Trim('/') + '/' + $it.RelativePath) } else { $it.RelativePath }
                $rp = $rp -replace '\\','/'
                if ($sanitise) { $rp = Lzfcde41179d -Space $row.Space -Rp $rp -Item $it }
                $it | Add-Member -NotePropertyName RelPath -NotePropertyValue $rp -Force
            }
            $downloadThreads = 4
            if (($Config.run.PSObject.Properties.Name -contains 'download') -and ($Config.run.download.PSObject.Properties.Name -contains 'threads') -and $Config.run.download.threads) { $downloadThreads = [int]$Config.run.download.threads }
            $simDestBase = ''
            if ($Config.destination.provider -eq 'LocalSim') { $simDestBase = Join-Path $Config.destination.sim.rootPath (ConvertTo-Slug ($driveId -replace '^sim:','')) }
            $tokenHolder = [hashtable]::Synchronized(@{ Token = $null; Exp = [DateTimeOffset]::MinValue })
            if ($Config.destination.provider -ne 'LocalSim') { $tk = Lz204bc8c5c6 -Config $Config; $tokenHolder.Token = $tk.Token; $tokenHolder.Exp = $tk.Exp }
            $ensured = [hashtable]::Synchronized(@{})
            Lz12e519cc30 INFO "  copying up to $downloadThreads file(s) at a time from Datto, and up to $UploadWorkers at a time into Microsoft 365."
            $adaptOn = $true; $minWorkers = 1; $growAfter = 30
            if ($Config.run.throttle.PSObject.Properties.Name -contains 'adaptive') {
                $ad = $Config.run.throttle.adaptive
                if ($ad.PSObject.Properties.Name -contains 'enabled') { $adaptOn = [bool]$ad.enabled }
                if ($ad.PSObject.Properties.Name -contains 'minWorkers' -and [int]$ad.minWorkers -ge 1) { $minWorkers = [int]$ad.minWorkers }
                if ($ad.PSObject.Properties.Name -contains 'growAfterSeconds' -and [int]$ad.growAfterSeconds -ge 1) { $growAfter = [int]$ad.growAfterSeconds }
            }
            if ($minWorkers -gt $UploadWorkers) { $minWorkers = $UploadWorkers }
            $startMax = $UploadWorkers; $effMin = if ($adaptOn) { $minWorkers } else { $UploadWorkers }
            $thr = [hashtable]::Synchronized(@{ Max = $startMax; Active = 0; HardMax = $UploadWorkers; Events = 0; LastCode = 0; PauseUntilTicks = [int64]0; LastThrottleTicks = [int64]0; LastGrowTicks = [DateTime]::UtcNow.Ticks })
            $script:LastThrMax = -1; $script:LastThrPaused = $false
            $maxUpMbps = 0.0; $maxDownMbps = 0.0; $burstSec = 1.0
            if ($Config.run.PSObject.Properties.Name -contains 'bandwidth') {
                $bwc = $Config.run.bandwidth
                if ($bwc.PSObject.Properties.Name -contains 'maxUploadMbps')   { $maxUpMbps   = [double]$bwc.maxUploadMbps }
                if ($bwc.PSObject.Properties.Name -contains 'maxDownloadMbps') { $maxDownMbps = [double]$bwc.maxDownloadMbps }
                if (($bwc.PSObject.Properties.Name -contains 'burstSeconds') -and ([double]$bwc.burstSeconds -gt 0)) { $burstSec = [double]$bwc.burstSeconds }
            }
            $upBps   = if ($maxUpMbps   -gt 0) { $maxUpMbps   * 125000.0 } else { 0.0 }
            $downBps = if ($maxDownMbps -gt 0) { $maxDownMbps * 125000.0 } else { 0.0 }
            $bwUp   = [hashtable]::Synchronized(@{ CapBps = $upBps;   Tokens = ($upBps   * $burstSec); LastTicks = [DateTime]::UtcNow.Ticks; BucketMax = ($upBps   * $burstSec) })
            $bwDown = [hashtable]::Synchronized(@{ CapBps = $downBps; Tokens = ($downBps * $burstSec); LastTicks = [DateTime]::UtcNow.Ticks; BucketMax = ($downBps * $burstSec) })
            if ($maxUpMbps -gt 0 -or $maxDownMbps -gt 0) {
                $upTxt = if ($maxUpMbps -gt 0) { "upload capped at $maxUpMbps Mb/s" } else { "upload unlimited" }
                $dnTxt = if ($maxDownMbps -gt 0) { "download capped at $maxDownMbps Mb/s" } else { "download unlimited" }
                Lz12e519cc30 INFO "  bandwidth: $upTxt, $dnTxt (so the client's line is not saturated)."
            }
            $bwControlPath = Join-Path $Config.run.stateRoot 'bandwidth.control.json'
            try { if (-not (Test-Path $Config.run.stateRoot)) { New-Item -ItemType Directory -Path $Config.run.stateRoot -Force | Out-Null } } catch {}
            try { @{ maxUploadMbps = $maxUpMbps; maxDownloadMbps = $maxDownMbps } | ConvertTo-Json | Set-Content -Path $bwControlPath -Encoding UTF8 } catch {}
            $bwCtrlStamp = $null; try { $bwCtrlStamp = (Get-Item $bwControlPath).LastWriteTimeUtc } catch {}
            $bwLastUp = $maxUpMbps; $bwLastDown = $maxDownMbps
            $spool = [System.Collections.Concurrent.BlockingCollection[hashtable]]::new([int][math]::Max($SpoolAhead, $UploadWorkers * 2))
            $delQ  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
            $resQ  = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
            $inQ   = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
            foreach ($it in $toDo) { $inQ.Enqueue($it) }
            $script:EtaSmallDone = 0; $script:EtaLargeBytesDone = [int64]0
            $script:EtaSmallTotal = 0; $script:EtaLargeBytesTotal = [int64]0
            if (-not $streamFP) {
                foreach ($it in $toDo) {
                    if ([int64]$it.Size -ge $script:LargeFileBytes) { $script:EtaLargeBytesTotal += [int64]$it.Size } else { $script:EtaSmallTotal++ }
                }
            }
            $enumFlag = [hashtable]::Synchronized(@{ Done = (-not $streamFP) })
            $flags = [hashtable]::Synchronized(@{ Done = $false })
            $dlScript = {
                param($inQ, $spool, $cfg, $temp, $bwDown, $enum, $pace, $largeBytes, $spoolKey, $spoolHelpers)
                if ($spoolKey) { . ([scriptblock]::Create($spoolHelpers)) }
                $xferTo = 3600; try { if ($cfg.run.throttle.transferTimeoutSec) { $xferTo = [int]$cfg.run.throttle.transferTimeoutSec } } catch {}
                $DoPace = {
                    param($p)
                    if ($p.GapMs -le 0) { return }
                    $sleepMs = 0
                    [System.Threading.Monitor]::Enter($p.SyncRoot)
                    try {
                        $now  = [DateTime]::UtcNow.Ticks
                        $slot = [math]::Max($now, $p.NextTicks)
                        $sleepMs = [int](($slot - $now) / [TimeSpan]::TicksPerMillisecond)
                        $p.NextTicks = $slot + ($p.GapMs * [TimeSpan]::TicksPerMillisecond)
                    } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
                    if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
                }
                $PaceEase = { param($p) if ($p.GapMs -gt 0) { [System.Threading.Monitor]::Enter($p.SyncRoot); try { $p.GapMs = [math]::Max(0, $p.GapMs - 25) } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) } } }
                $PaceBump = { param($p) [System.Threading.Monitor]::Enter($p.SyncRoot); try { $p.GapMs = [math]::Min($p.MaxMs, $p.GapMs + 300) } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) } }
                $BwAcquire = {
                    param($bucket,$need)
                    while ($true) {
                        $done=$false
                        [System.Threading.Monitor]::Enter($bucket.SyncRoot)
                        try {
                            if ($bucket.CapBps -le 0) {
                                $bucket.Tokens = 0; $done = $true
                            } else {
                                $now=[DateTime]::UtcNow.Ticks
                                $elapsed=($now - $bucket.LastTicks)/[double][TimeSpan]::TicksPerSecond
                                if ($elapsed -gt 0) { $bucket.Tokens=[math]::Min($bucket.Tokens + $elapsed*$bucket.CapBps, $bucket.BucketMax); $bucket.LastTicks=$now }
                                if ($bucket.Tokens -gt 0) { $bucket.Tokens=$bucket.Tokens - $need; $done=$true }
                            }
                        } finally { [System.Threading.Monitor]::Exit($bucket.SyncRoot) }
                        if ($done) { break }
                        Start-Sleep -Milliseconds 50
                    }
                }
                $authHeader = @{}
                if ($cfg.datto.provider -ne 'LocalSim') {
                    $sec = $cfg.datto.clientSecret
                    if ("$sec" -match '^env:(.+)$') { $sn=$Matches[1]; $sec=[Environment]::GetEnvironmentVariable($sn); if(-not $sec){$sec=[Environment]::GetEnvironmentVariable($sn,'User')}; if(-not $sec){$sec=[Environment]::GetEnvironmentVariable($sn,'Machine')} }
                    $pair=[Text.Encoding]::UTF8.GetBytes("$($cfg.datto.clientId):$sec"); $authHeader=@{Authorization='Basic '+[Convert]::ToBase64String($pair)}
                }
                $it=$null
                while ((-not $enum.Done) -or ($inQ.Count -gt 0)) {
                    if (-not $inQ.TryDequeue([ref]$it)) { Start-Sleep -Milliseconds 100; continue }
                    if ([int64]$it.Size -ge [int64]$largeBytes) {
                        $freeB = -1; try { $freeB = ([System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($temp))).AvailableFreeSpace } catch {}
                        if ($freeB -ge 0 -and ([int64]$it.Size + 512MB) -gt $freeB) {
                            $gbF = [math]::Round($it.Size/1GB,2); $gbFree = [math]::Round($freeB/1GB,2)
                            $spool.Add(@{ Item=$it; TempFile=$null; Ok=$false; Error="TOOLARGE: this file is $gbF GB but only $gbFree GB is free on the temp drive"; DlMs=0.0 })
                            continue
                        }
                    }
                    $tf = Join-Path $temp ([guid]::NewGuid().ToString('N') + $(if ($spoolKey) { '' } else { [System.IO.Path]::GetExtension($it.RelativePath) }))
                    & $BwAcquire $bwDown ([double]$it.Size)
                    $ok=$true; $err=''; $dlSw=[System.Diagnostics.Stopwatch]::StartNew()
                    $hardTry=0; $throttleTry=0
                    while ($true) { try {
                        if ($cfg.datto.provider -eq 'LocalSim') { if ($spoolKey) { Save-SpoolFile -InFile $it.Id -OutFile $tf -Key $spoolKey | Out-Null } else { Copy-Item -LiteralPath $it.Id -Destination $tf -Force } }
                        else {
                            & $DoPace $pace
                            $uri=($cfg.datto.endpointUrl.TrimEnd('/'))+($cfg.datto.apiPaths.downloadFile -replace '\{fileID\}',$it.Id)
                            if ($spoolKey) { Invoke-SpoolDownload -Uri $uri -Headers $authHeader -OutFile $tf -Key $spoolKey -TimeoutSec $xferTo | Out-Null }
                            else { Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -Headers $authHeader -OutFile $tf -TimeoutSec $xferTo | Out-Null }
                            & $PaceEase $pace
                        }
                        $ok=$true; break } catch {
                            $st=$null; try { $st=$_.Exception.Response.StatusCode.value__ } catch {}
                            if (@(429,503) -contains $st) {
                                & $PaceBump $pace
                                $throttleTry++
                                $ra=0; try { $rah=$_.Exception.Response.Headers['X-Rate-Limit-Retry-After-Seconds']; if(-not $rah){$rah=$_.Exception.Response.Headers['Retry-After']}; if($rah){$ra=[int]$rah} } catch {}
                                if ($ra -le 0) { $ra=[int][math]::Min([math]::Pow(2,[math]::Min($throttleTry,5)),30) }
                                if ($throttleTry -ge 40) { $ok=$false; $err="still rate-limited by Datto (HTTP $st) after $throttleTry waits: $($_.Exception.Message)"; break }
                                Start-Sleep -Seconds $ra
                            } else {
                                $hardTry++
                                if ($hardTry -ge 5) { $ok=$false; $err=$_.Exception.Message; if ($err -match '(?i)enough space|disk( is)? full|not enough space') { $err = "the temp drive filled up while staging this file - free space or point run.tempWorkingFolder at a bigger drive. ($err)" }; break }
                                Start-Sleep -Seconds ([int][math]::Min([math]::Pow(2,$hardTry),30))
                            } } }
                    $dlSw.Stop()
                    $spool.Add(@{ Item=$it; TempFile=$tf; Ok=$ok; Error=$err; DlMs=$dlSw.Elapsed.TotalMilliseconds })
                }
            }
            $downloaders=@()
            for ($d=0; $d -lt $downloadThreads; $d++) {
                $dp=[powershell]::Create(); $null=$dp.AddScript($dlScript).AddArgument($inQ).AddArgument($spool).AddArgument($Config).AddArgument($spaceTemp).AddArgument($bwDown).AddArgument($enumFlag).AddArgument($script:DattoPace).AddArgument([int64]$script:LargeFileBytes).AddArgument($script:SpoolKey).AddArgument($script:SpoolHelperSource)
                $downloaders += @{ PS=$dp; Handle=$dp.BeginInvoke() }
            }
            $del = [powershell]::Create()
            $null = $del.AddScript({ param($delQ,$flags) while (-not $flags.Done -or $delQ.Count -gt 0){ $p=$null; if($delQ.TryDequeue([ref]$p)){try{[IO.File]::Delete($p)}catch{}}else{Start-Sleep -Milliseconds 50} } }).AddArgument($delQ).AddArgument($flags)
            $delH = $del.BeginInvoke()
            $workerScript = {
                param($spool,$resQ,$delQ,$tokenHolder,$driveId,$provider,$simDestBase,$threshold,$officeTypes,$maxRetries,$baseDelay,$graphBase,$ensured,$chunkBytes,$honorRetryAfter,$thr,$minWorkers,$bwUp,$apiTo,$xferTo,$spoolKey,$spoolHelpers)
                if ($spoolKey) { . ([scriptblock]::Create($spoolHelpers)) }
                $BwAcquire = {
                    param($bucket,$need)
                    while ($true) {
                        $done=$false
                        [System.Threading.Monitor]::Enter($bucket.SyncRoot)
                        try {
                            if ($bucket.CapBps -le 0) {
                                $bucket.Tokens = 0; $done = $true
                            } else {
                                $now=[DateTime]::UtcNow.Ticks
                                $elapsed=($now - $bucket.LastTicks)/[double][TimeSpan]::TicksPerSecond
                                if ($elapsed -gt 0) { $bucket.Tokens=[math]::Min($bucket.Tokens + $elapsed*$bucket.CapBps, $bucket.BucketMax); $bucket.LastTicks=$now }
                                if ($bucket.Tokens -gt 0) { $bucket.Tokens=$bucket.Tokens - $need; $done=$true }
                            }
                        } finally { [System.Threading.Monitor]::Exit($bucket.SyncRoot) }
                        if ($done) { break }
                        Start-Sleep -Milliseconds 50
                    }
                }
                $GetRA = {
                    param($errRec)
                    $ra = 0
                    try { $ra = [int](($errRec.Exception.Response.Headers.GetValues('Retry-After'))[0]) } catch {}
                    if (-not $ra) { try { $ra = [int]$errRec.Exception.Response.Headers['Retry-After'] } catch {} }
                    if ($ra -lt 0) { $ra = 0 }; return $ra
                }
                $GetWait = {
                    param($errRec,$attempt,$base,$honor)
                    $ra = & $GetRA $errRec
                    if ($honor -and $ra -gt 0) { return [int][math]::Ceiling([math]::Min($ra,300) + (Get-Random -Minimum 0.0 -Maximum 2.0)) }
                    $exp = [math]::Min([math]::Pow(2,$attempt) * $base, 300)
                    return [int][math]::Max(1, [math]::Ceiling(($exp/2.0) + (Get-Random -Minimum 0.0 -Maximum ($exp/2.0))))
                }
                $Throttled = {
                    param($retryAfter,$code)
                    [System.Threading.Monitor]::Enter($thr.SyncRoot)
                    try {
                        $nowT = [DateTime]::UtcNow.Ticks
                        if ($code) { $thr.LastCode = [int]$code }
                        if (($nowT - $thr.LastThrottleTicks) -gt [TimeSpan]::FromSeconds(5).Ticks) {
                            $thr.Max = [int][math]::Max($minWorkers, [math]::Floor($thr.Max / 2.0))
                            $thr.LastThrottleTicks = $nowT; $thr.Events = $thr.Events + 1
                        }
                        if ($retryAfter -gt 0) {
                            $pu = $nowT + [TimeSpan]::FromSeconds([math]::Min($retryAfter,300)).Ticks
                            if ($pu -gt $thr.PauseUntilTicks) { $thr.PauseUntilTicks = $pu }
                        }
                    } finally { [System.Threading.Monitor]::Exit($thr.SyncRoot) }
                }
                $HandleRetry = {
                    param($errRec,$attempt)
                    $st=$null; try { $st=$errRec.Exception.Response.StatusCode.value__ } catch {}
                    $ra = & $GetRA $errRec
                    if (@(429,503) -contains $st) { & $Throttled $ra $st }
                    return (& $GetWait $errRec $attempt $baseDelay $honorRetryAfter)
                }
                $IsTransient = {
                    param($errRec)
                    $st=$null; try { $st=$errRec.Exception.Response.StatusCode.value__ } catch {}
                    if ($st) { return $false }
                    $m=''; try { $ex=$errRec.Exception; $d=0; while ($ex -and $d -lt 8) { $m += ' ' + $ex.GetType().FullName + ' ' + $ex.Message; $ex=$ex.InnerException; $d++ } } catch {}
                    return ($m -match '(?i)SSL|secure channel|connection was closed|connection was forcibly|actively refused|timed out|timeout|reset by peer|unexpectedly closed|transport connection|underlying connection|SocketException|IOException|WebException|HttpRequestException')
                }
                $Acquire = {
                    while ($true) {
                        if ([DateTime]::UtcNow.Ticks -lt $thr.PauseUntilTicks) { Start-Sleep -Milliseconds 200; continue }
                        $got = $false
                        [System.Threading.Monitor]::Enter($thr.SyncRoot)
                        try { if ($thr.Active -lt $thr.Max) { $thr.Active = $thr.Active + 1; $got = $true } }
                        finally { [System.Threading.Monitor]::Exit($thr.SyncRoot) }
                        if ($got) { break }
                        Start-Sleep -Milliseconds 100
                    }
                }
                $Release = {
                    [System.Threading.Monitor]::Enter($thr.SyncRoot)
                    try { if ($thr.Active -gt 0) { $thr.Active = $thr.Active - 1 } }
                    finally { [System.Threading.Monitor]::Exit($thr.SyncRoot) }
                }
                foreach ($ready in $spool.GetConsumingEnumerable()) {
                    $it=$ready.Item; $rp=$it.RelPath; $tf=$ready.TempFile; $dlMs=0.0; try{$dlMs=[double]$ready.DlMs}catch{}
                    if (-not $ready.Ok) { $st0 = if ("$($ready.Error)" -like 'TOOLARGE:*') { 'SkippedTooLarge' } else { 'DownloadError' }; $resQ.Enqueue(@{Item=$it;Status=$st0;Error="$($ready.Error)";Reason='';DestSize=[int64]0;DestHash='';DestPath=$rp;Method='';Retries=0;Ms=0.0;DlMs=$dlMs}); if($tf){$delQ.Enqueue($tf)}; continue }
                    & $Acquire
                    $sw=[System.Diagnostics.Stopwatch]::StartNew(); $r=0; $method=''; $destSize=[int64]0; $destHash=''; $status='Error'; $err=''; $reason=''
                    try {
                        $localSize = if ($spoolKey) { Get-SpoolLength $tf } else { (Get-Item $tf).Length }
                        & $BwAcquire $bwUp ([double]$localSize)
                        $ext=([System.IO.Path]::GetExtension($rp)).ToLower()
                        if ($provider -eq 'LocalSim') {
                            $dest=Join-Path $simDestBase $rp; New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null; if ($spoolKey) { Copy-SpoolToFile -File $tf -OutFile $dest -Key $spoolKey } else { Copy-Item -LiteralPath $tf -Destination $dest -Force }; $destSize=(Get-Item $dest).Length; $method='LocalSim'
                        } else {
                            $enc=([uri]::EscapeDataString($rp) -replace '%2F','/'); $resp=$null
                            $hdr=@{ Authorization='Bearer '+$tokenHolder.Token }
                            if ($rp -match '/') {
                                $folder = $rp -replace '/[^/]*$',''
                                if (-not $ensured.ContainsKey($folder)) {
                                    $segs = $folder -split '/'; $cur=''
                                    for ($i=0;$i -lt $segs.Count;$i++){
                                        $parent=$cur; $cur = if($cur){"$cur/$($segs[$i])"}else{$segs[$i]}
                                        if ($ensured.ContainsKey($cur)) { continue }
                                        $purl = if ($parent) { "$graphBase/drives/$driveId/root:/$([uri]::EscapeDataString($parent) -replace '%2F','/'):/children" } else { "$graphBase/drives/$driveId/root/children" }
                                        try { Invoke-RestMethod -Method Post -Uri $purl -Headers @{Authorization='Bearer '+$tokenHolder.Token} -Body (@{name=$segs[$i];folder=@{};'@microsoft.graph.conflictBehavior'='fail'}|ConvertTo-Json) -ContentType 'application/json' -TimeoutSec $apiTo | Out-Null } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if ($st -ne 409){ throw } }
                                        $ensured[$cur]=$true
                                    }
                                }
                            }
                            if ($localSize -eq 0) { $resp=Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$graphBase/drives/$driveId/root:/${enc}:/content" -Headers $hdr -Body ([byte[]]::new(0)) -ContentType 'application/octet-stream' -TimeoutSec $apiTo; $method='Empty' }
                            elseif ($localSize -le $threshold) {
                                for ($a=1;$a -le $maxRetries;$a++){ try {
                                    if ($spoolKey) {
                                        $spx = Open-SpoolRead -File $tf -Key $spoolKey
                                        try { $resp = Send-SpoolHttp -Uri "$graphBase/drives/$driveId/root:/${enc}:/content" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -BodyStream $spx.Stream -ContentLength $localSize -TimeoutSec $xferTo }
                                        finally { $spx.Stream.Dispose() }
                                    } else { $resp=Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$graphBase/drives/$driveId/root:/${enc}:/content" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -InFile $tf -ContentType 'application/octet-stream' -TimeoutSec $xferTo }
                                    break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,404,408,429,500,502,503,504)-contains $st) -or (& $IsTransient $_))-and $a -lt $maxRetries){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $a);continue}; throw } }
                                $method='DirectPut'
                            } else {
                                $sess=$null
                                for ($a=1;$a -le $maxRetries;$a++){ try { $sess=Invoke-RestMethod -Method Post -Uri "$graphBase/drives/$driveId/root:/${enc}:/createUploadSession" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -Body (@{item=@{'@microsoft.graph.conflictBehavior'='replace'}}|ConvertTo-Json) -ContentType 'application/json' -TimeoutSec $apiTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,404,408,429,500,502,503,504)-contains $st) -or (& $IsTransient $_))-and $a -lt $maxRetries){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $a);continue}; throw } }
                                $uu=$sess.uploadUrl; $chunk=$chunkBytes
                                if ($spoolKey) {
                                    $fsr=(Open-SpoolRead -File $tf -Key $spoolKey).Stream
                                    try { $pos=[int64]0
                                        while ($true) {
                                            $sl = Read-SpoolChunk -Stream $fsr -Count ([int]$chunk)
                                            $read = $sl.Length; if ($read -le 0) { break }
                                            for ($ca=1;$ca -le $maxRetries;$ca++){ try { $resp=Send-SpoolHttp -Uri $uu -BodyBytes $sl -ContentRange "bytes $pos-$($pos+$read-1)/$localSize" -TimeoutSec $xferTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,408,429,500,502,503,504)-contains $st) -or (& $IsTransient $_))-and $ca -lt $maxRetries){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $ca);continue}; throw } }
                                            $pos+=$read
                                            if ($read -lt $chunk) { break }
                                        }
                                    } finally { $fsr.Dispose() }
                                } else {
                                $fsr=[System.IO.File]::OpenRead($tf); $ctmp="$tf.chunk"
                                try { $buf=[byte[]]::new($chunk); $pos=0
                                    while(($read=$fsr.Read($buf,0,$buf.Length))-gt 0){ if($read -eq $buf.Length){[System.IO.File]::WriteAllBytes($ctmp,$buf)}else{$sl=[byte[]]::new($read);[Array]::Copy($buf,0,$sl,0,$read);[System.IO.File]::WriteAllBytes($ctmp,$sl)}
                                        for ($ca=1;$ca -le $maxRetries;$ca++){ try { $resp=Invoke-WebRequest -UseBasicParsing -Method Put -Uri $uu -Headers @{'Content-Range'="bytes $pos-$($pos+$read-1)/$localSize"} -InFile $ctmp -ContentType 'application/octet-stream' -TimeoutSec $xferTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,408,429,500,502,503,504)-contains $st) -or (& $IsTransient $_))-and $ca -lt $maxRetries){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $ca);continue}; throw } }
                                        $pos+=$read }
                                } finally { $fsr.Dispose(); if(Test-Path $ctmp){Remove-Item $ctmp -Force -ErrorAction SilentlyContinue} }
                                }
                                $method='UploadSession'
                            }
                            try { $j=$resp.Content|ConvertFrom-Json; $destSize=[int64]$j.size; try { $destHash=[string]$j.file.hashes.quickXorHash } catch {} } catch {}
                        }
                        if ($localSize -eq 0) { $status='ZeroByte'; $reason='zero-byte (accepted, flagged)' }
                        elseif ($officeTypes -contains $ext) { if ($destSize -gt 0){$status='Copied';$reason='Office file accepted (M365 rewrites metadata)'}else{$status='VerifyFail';$reason='Office file not stored (size 0 at destination)'} }
                        elseif ($destSize -eq $localSize) { $status='Copied';$reason='verified (size)' }
                        elseif ($destSize -gt 0 -and [math]::Abs($destSize-$localSize) -le [math]::Max(65536,[int64]($localSize*0.01))) { $status='Copied';$reason="accepted (stored $destSize vs source $localSize, diff $($destSize-$localSize) bytes; likely M365 rewrite)" }
                        else { $status='VerifyFail';$reason="size mismatch (dest $destSize vs $localSize)" }
                    } catch { $status='Error'; $err=$_.Exception.Message }
                    finally { & $Release }
                    $sw.Stop()
                    $resQ.Enqueue(@{Item=$it;Status=$status;Error=$err;Reason=$reason;DestSize=$destSize;DestHash=$destHash;DestPath=$rp;Method=$method;Retries=$r;Ms=$sw.Elapsed.TotalMilliseconds;DlMs=$dlMs})
                    if($tf){$delQ.Enqueue($tf)}
                }
            }
            $graphBase='https://graph.microsoft.com/v1.0'
            $workers=@()
            for ($w=0; $w -lt $UploadWorkers; $w++) {
                $ps=[powershell]::Create()
                $null=$ps.AddScript($workerScript).AddArgument($spool).AddArgument($resQ).AddArgument($delQ).AddArgument($tokenHolder).AddArgument($driveId).AddArgument($Config.destination.provider).AddArgument($simDestBase).AddArgument([int64]$script:SmallFilePutThreshold).AddArgument($script:OfficeTypes).AddArgument([int]$Config.run.throttle.maxRetries).AddArgument([int]$Config.run.throttle.baseDelaySeconds).AddArgument($graphBase).AddArgument($ensured).AddArgument([int64]$script:ChunkSize).AddArgument([bool]$Config.run.throttle.honorRetryAfter).AddArgument($thr).AddArgument([int]$effMin).AddArgument($bwUp).AddArgument([int]$script:HttpTimeoutSec).AddArgument([int]$script:TransferTimeoutSec).AddArgument($script:SpoolKey).AddArgument($script:SpoolHelperSource)
                $workers += @{ PS=$ps; Handle=$ps.BeginInvoke() }
            }
            $process = {
                param($res)
                $script:fIdxRef.Value++
                $it=$res.Item
                if ([int64]$it.Size -ge $script:LargeFileBytes) { $script:EtaLargeBytesDone += [int64]$it.Size } else { $script:EtaSmallDone++ }
                switch ($res.Status) {
                    'Copied'   { $script:copiedRef.Value++; $script:bytesRef.Value+=$it.Size; if($script:VerboseFiles){Lz12e519cc30 INFO "  + [$($it.RelativePath)] $($res.Reason)"} }
                    'ZeroByte' { $script:copiedRef.Value++; $script:zeroRef.Value++; $script:bytesRef.Value+=$it.Size; Lz12e519cc30 WARN "  empty file (0 bytes), uploaded as-is: $($it.RelativePath)" }
                    'VerifyFail'{ $script:verifyFailRef.Value++; Lz12e519cc30 ERROR "  VERIFY FAILED $($it.RelativePath): $($res.Reason). In plain terms: the uploaded copy did not match the original, so it was not marked done. It will be retried on the next Sync." }
                    'DownloadError'{ $script:failedRef.Value++; Lz12e519cc30 ERROR "  DOWNLOAD FAILED $($it.RelativePath): $($res.Error). In plain terms: the file could not be downloaded from Datto. It will be retried on the next Sync." }
                    'SkippedTooLarge'{ $script:failedRef.Value++; Lz12e519cc30 ERROR "  SKIPPED (too large for temp drive) $($it.RelativePath): $($res.Error). In plain terms: this one file will not fit in the temp drive's free space, so it was left for a later run. Free up space (or point the temp folder at a bigger drive) and Sync to pick it up." }
                    default    { $script:failedRef.Value++; Lz12e519cc30 ERROR "  UPLOAD FAILED $($it.RelativePath): $($res.Error). In plain terms: the file could not be uploaded to Microsoft 365. It will be retried on the next Sync." }
                }
                $rDl = 0.0; try { $rDl = [double]$res.DlMs } catch {}
                $rsn = Lz3413b7702d -Repair $repair -Item $it -Status $res.Status -Reason $res.Reason
                Lz3c19440102 -Space $row.Space -Item $it -Status $res.Status -Reason $rsn -DestSize $res.DestSize -DestPath $res.DestPath -DestHash $res.DestHash -Method $res.Method -Retries $res.Retries -DurationMs $res.Ms -DownloadMs $rDl -ErrorMsg $res.Error
                Lz67aab01d86 -Done $script:fIdxRef.Value -Total $fTotal -BytesDone $script:bytesRef.Value -BytesTotal $spaceBytesTotal -Space $row.Space `
                    -SmallDone $script:EtaSmallDone -SmallTotal $script:EtaSmallTotal -LargeBytesDone $script:EtaLargeBytesDone -LargeBytesTotal $script:EtaLargeBytesTotal -Final ([int][bool]$enumFlag.Done)
            }
            $script:fIdxRef=[ref]$fIdx; $script:copiedRef=[ref]$copied; $script:bytesRef=[ref]$bytes; $script:zeroRef=[ref]$zero; $script:verifyFailRef=[ref]$verifyFail; $script:failedRef=[ref]$failed
            if ($streamFP) {
                $script:streamCountRef=[ref]0; $script:streamBytesRef=[ref]([int64]0)
                Get-DattoItems -Config $Config -Space $space -OnItem {
                    param($it)
                    if ($Config.destination.provider -ne 'LocalSim' -and [DateTimeOffset]::UtcNow -gt $tokenHolder.Exp) {
                        try { $tk = Lz204bc8c5c6 -Config $Config; $tokenHolder.Token = $tk.Token; $tokenHolder.Exp = $tk.Exp } catch {}
                    }
                    $rp = if ($effSub) { ($effSub.Trim('/') + '/' + $it.RelativePath) } else { $it.RelativePath }
                    $rp = $rp -replace '\\','/'
                    if ($sanitise) { $rp = Lzfcde41179d -Space $row.Space -Rp $rp -Item $it }
                    $it | Add-Member -NotePropertyName RelPath -NotePropertyValue $rp -Force
                    $inQ.Enqueue($it)
                    $script:streamCountRef.Value++
                    $script:streamBytesRef.Value += [int64]$it.Size
                    if ([int64]$it.Size -ge $script:LargeFileBytes) { $script:EtaLargeBytesTotal += [int64]$it.Size } else { $script:EtaSmallTotal++ }
                } | Out-Null
                $enumFlag.Done = $true
                $fTotal = [int]$script:streamCountRef.Value
                $spaceBytesTotal = [int64]$script:streamBytesRef.Value
                $expectedTotal += $fTotal
                Lz12e519cc30 INFO "  listing finished: $fTotal file(s), $([math]::Round($spaceBytesTotal/1MB,1)) MB to move."
                if ($script:GuiMode) { Write-Host "##STATUS##|File list complete: $fTotal file(s). Uploading now..." }
            }
            $spoolClosed=$false
            while (@($workers | Where-Object { -not $_.Handle.IsCompleted }).Count -gt 0 -or $resQ.Count -gt 0) {
                $res=$null
                while ($resQ.TryDequeue([ref]$res)) { & $process $res; Lz390831b78c -Activity "Files: $($row.Space)" -Status $res.DestPath -Current $script:fIdxRef.Value -Total $fTotal -Id 2 | Out-Null }
                if (-not $spoolClosed -and (@($downloaders | Where-Object { -not $_.Handle.IsCompleted }).Count -eq 0)) { $spool.CompleteAdding(); $spoolClosed=$true }
                if ($Config.destination.provider -ne 'LocalSim' -and [DateTimeOffset]::UtcNow -gt $tokenHolder.Exp) { try { $tk=Lz204bc8c5c6 -Config $Config; $tokenHolder.Token=$tk.Token; $tokenHolder.Exp=$tk.Exp } catch {} }
                $nowT=[DateTime]::UtcNow.Ticks
                [System.Threading.Monitor]::Enter($thr.SyncRoot)
                try {
                    $pausedSecs = if ($thr.PauseUntilTicks -gt $nowT) { [int][math]::Ceiling(($thr.PauseUntilTicks - $nowT)/[double][TimeSpan]::TicksPerSecond) } else { 0 }
                    if ($adaptOn -and $pausedSecs -eq 0 -and $thr.Max -lt $thr.HardMax -and (($nowT - $thr.LastThrottleTicks) -gt [TimeSpan]::FromSeconds($growAfter).Ticks) -and (($nowT - $thr.LastGrowTicks) -gt [TimeSpan]::FromSeconds($growAfter).Ticks)) {
                        $thr.Max = $thr.Max + 1; $thr.LastGrowTicks = $nowT
                    }
                    $curMax=$thr.Max; $curEvents=$thr.Events; $curCode=$thr.LastCode
                } finally { [System.Threading.Monitor]::Exit($thr.SyncRoot) }
                $isPaused = $pausedSecs -gt 0
                if ($curMax -ne $script:LastThrMax -or $isPaused -ne $script:LastThrPaused) {
                    Lzc5f2c77844 -Max $curMax -HardMax $thr.HardMax -PausedSeconds $pausedSecs -Events $curEvents -Code $curCode
                    $codeTxt = if ($curCode) { " (HTTP ${curCode}: too many requests too fast)" } else { "" }
                    if ($curMax -lt $thr.HardMax -or $isPaused) {
                        $msg = if ($isPaused) { "Throttling${codeTxt}: Microsoft asked us to pause about $pausedSecs s. Easing off to $curMax of $($thr.HardMax) uploader(s)." } else { "Throttling${codeTxt}: easing off to $curMax of $($thr.HardMax) uploader(s) to stay within Microsoft 365 limits." }
                        Lz12e519cc30 WARN "  $msg In plain terms: this is normal protection, the job keeps running and speeds back up on its own."
                    } elseif ($script:LastThrMax -ne -1) {
                        Lz12e519cc30 OK "  Throttling cleared: back to full speed ($curMax of $($thr.HardMax) uploaders)."
                    }
                    $script:LastThrMax=$curMax; $script:LastThrPaused=$isPaused
                }
                try {
                    if (Test-Path $bwControlPath) {
                        $st = (Get-Item $bwControlPath).LastWriteTimeUtc
                        if ($st -ne $bwCtrlStamp) {
                            $bwCtrlStamp = $st
                            $cc = Get-Content $bwControlPath -Raw | ConvertFrom-Json
                            $nu = [double]$cc.maxUploadMbps; $nd = [double]$cc.maxDownloadMbps
                            if ($nu -ne $bwLastUp -or $nd -ne $bwLastDown) {
                                $bwLastUp = $nu; $bwLastDown = $nd
                                $nUpBps = if ($nu -gt 0) { $nu * 125000.0 } else { 0.0 }
                                $nDnBps = if ($nd -gt 0) { $nd * 125000.0 } else { 0.0 }
                                [System.Threading.Monitor]::Enter($bwUp.SyncRoot); try { $bwUp.CapBps=$nUpBps; $bwUp.BucketMax=($nUpBps*$burstSec); $bwUp.LastTicks=[DateTime]::UtcNow.Ticks; if ($bwUp.Tokens -gt $bwUp.BucketMax) { $bwUp.Tokens=$bwUp.BucketMax } } finally { [System.Threading.Monitor]::Exit($bwUp.SyncRoot) }
                                [System.Threading.Monitor]::Enter($bwDown.SyncRoot); try { $bwDown.CapBps=$nDnBps; $bwDown.BucketMax=($nDnBps*$burstSec); $bwDown.LastTicks=[DateTime]::UtcNow.Ticks; if ($bwDown.Tokens -gt $bwDown.BucketMax) { $bwDown.Tokens=$bwDown.BucketMax } } finally { [System.Threading.Monitor]::Exit($bwDown.SyncRoot) }
                                $ut = if ($nu -gt 0) { "$nu Mb/s" } else { "unlimited" }
                                $dt = if ($nd -gt 0) { "$nd Mb/s" } else { "unlimited" }
                                Lz12e519cc30 INFO "  bandwidth changed on the fly: upload $ut, download $dt. Applied immediately."
                            }
                        }
                    }
                } catch {}
                Start-Sleep -Milliseconds 100
            }
            if ($script:LastThrMax -ne -1 -and $script:LastThrMax -lt $thr.HardMax) { Lzc5f2c77844 -Max $thr.HardMax -HardMax $thr.HardMax -PausedSeconds 0 -Events $thr.Events }
            if (-not $spoolClosed) { $spool.CompleteAdding() }
            $res=$null; while ($resQ.TryDequeue([ref]$res)) { & $process $res }
            $fIdx=$script:fIdxRef.Value; $copied=$script:copiedRef.Value; $bytes=$script:bytesRef.Value; $zero=$script:zeroRef.Value; $verifyFail=$script:verifyFailRef.Value; $failed=$script:failedRef.Value
            foreach ($wk in $workers) { try { $wk.PS.EndInvoke($wk.Handle) } catch {}; try { $wk.PS.Dispose() } catch {} }
            $flags.Done=$true
            foreach ($dp in $downloaders) { try { $dp.PS.EndInvoke($dp.Handle) } catch {}; try { $dp.PS.Dispose() } catch {} }
            try { $del.EndInvoke($delH) } catch {}; try { $del.Dispose() } catch {}
        }
        elseif ($SpoolAhead -le 1) {
            $etaSmallDone=0; $etaLargeDone=[int64]0; $etaSmallTotal=0; $etaLargeTotal=[int64]0
            foreach ($it in $toDo) { if ([int64]$it.Size -ge $script:LargeFileBytes) { $etaLargeTotal += [int64]$it.Size } else { $etaSmallTotal++ } }
            foreach ($it in $toDo) {
                $fIdx++
                if ([int64]$it.Size -ge $script:LargeFileBytes) { $etaLargeDone += [int64]$it.Size } else { $etaSmallDone++ }
                Lz390831b78c -Activity "Files: $($row.Space)" -Status $it.RelativePath -Current $fIdx -Total $fTotal -Id 2 | Out-Null
                $tempFile = Join-Path $spaceTemp ([guid]::NewGuid().ToString('N') + $(if ($script:SpoolKey) { '' } else { [System.IO.Path]::GetExtension($it.RelativePath) }))
                $dlSw = [System.Diagnostics.Stopwatch]::StartNew(); $upSw = [System.Diagnostics.Stopwatch]::new()
                try {
                    Lza83d2fc83b -Config $Config -Item $it -OutFile $tempFile | Out-Null
                    $dlSw.Stop(); $upSw.Start()
                    $destInfo = Send-FileToDestination -Config $Config -DriveId $driveId -TargetFolder $effSub -Item $it -LocalFile $tempFile -Space $row.Space
                    $v = Lzee645c3ed5 -Item $it -LocalFile $tempFile -DestInfo $destInfo
                    $upSw.Stop()
                    if ($v.Ok) {
                        if ($v.Zero) { Lz12e519cc30 WARN "  empty file (0 bytes), uploaded as-is: $($it.RelativePath)"; $zero++ }
                        $copied++; $bytes += $it.Size
                        if ($script:VerboseFiles) { Lz12e519cc30 INFO "  + [$($it.RelativePath)] $($v.Reason)" }
                        $stat = if($v.Zero){'ZeroByte'}else{'Copied'}
                        Lz3c19440102 -Space $row.Space -Item $it -Status $stat -Reason (Lz3413b7702d -Repair $repair -Item $it -Status $stat -Reason $v.Reason) -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $upSw.Elapsed.TotalMilliseconds -DownloadMs $dlSw.Elapsed.TotalMilliseconds
                    } else {
                        $verifyFail++; Lz12e519cc30 ERROR "  VERIFY FAILED $($it.RelativePath): $($v.Reason). In plain terms: the uploaded copy did not match the original, so it was not marked done. It will be retried on the next Sync."
                        Lz3c19440102 -Space $row.Space -Item $it -Status 'VerifyFail' -Reason $v.Reason -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $upSw.Elapsed.TotalMilliseconds -DownloadMs $dlSw.Elapsed.TotalMilliseconds
                    }
                } catch { if ($dlSw.IsRunning){$dlSw.Stop()}; if($upSw.IsRunning){$upSw.Stop()}; $failed++; Lz12e519cc30 ERROR "  FAILED $($it.RelativePath): $($_.Exception.Message). In plain terms: this file could not be copied. It will be retried on the next Sync."; Lz3c19440102 -Space $row.Space -Item $it -Status 'Error' -DurationMs $upSw.Elapsed.TotalMilliseconds -DownloadMs $dlSw.Elapsed.TotalMilliseconds -ErrorMsg $_.Exception.Message }
                finally { if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue } }
                Lz67aab01d86 -Done $fIdx -Total $fTotal -BytesDone $bytes -BytesTotal $spaceBytesTotal -Space $row.Space -SmallDone $etaSmallDone -SmallTotal $etaSmallTotal -LargeBytesDone $etaLargeDone -LargeBytesTotal $etaLargeTotal -Final 1
            }
        }
        else {
            $spool = [System.Collections.Concurrent.BlockingCollection[hashtable]]::new([int]$SpoolAhead)
            $delQ  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
            $flags = [hashtable]::Synchronized(@{ Done = $false })
            $etaSmallDone=0; $etaLargeDone=[int64]0; $etaSmallTotal=0; $etaLargeTotal=[int64]0
            foreach ($it in $toDo) { if ([int64]$it.Size -ge $script:LargeFileBytes) { $etaLargeTotal += [int64]$it.Size } else { $etaSmallTotal++ } }
            $prod = [powershell]::Create()
            $null = $prod.AddScript({
                param($spool, $toDo, $cfg, $temp, $spoolKey, $spoolHelpers)
                if ($spoolKey) { . ([scriptblock]::Create($spoolHelpers)) }
                $xferTo = 3600; try { if ($cfg.run.throttle.transferTimeoutSec) { $xferTo = [int]$cfg.run.throttle.transferTimeoutSec } } catch {}
                $authHeader = @{}
                if ($cfg.datto.provider -ne 'LocalSim') {
                    $sec = $cfg.datto.clientSecret
                    if ("$sec" -match '^env:(.+)$') {
                        $sn = $Matches[1]
                        $sec = [Environment]::GetEnvironmentVariable($sn)
                        if (-not $sec) { $sec = [Environment]::GetEnvironmentVariable($sn, 'User') }
                        if (-not $sec) { $sec = [Environment]::GetEnvironmentVariable($sn, 'Machine') }
                    }
                    $pair = [Text.Encoding]::UTF8.GetBytes("$($cfg.datto.clientId):$sec")
                    $authHeader = @{ Authorization = 'Basic ' + [Convert]::ToBase64String($pair) }
                }
                try {
                    foreach ($it in $toDo) {
                        $tf = Join-Path $temp ([guid]::NewGuid().ToString('N') + $(if ($spoolKey) { '' } else { [System.IO.Path]::GetExtension($it.RelativePath) }))
                        $ok = $true; $err = ''
                        $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
                        $hardTry = 0; $throttleTry = 0
                        while ($true) {
                            try {
                                if ($cfg.datto.provider -eq 'LocalSim') { if ($spoolKey) { Save-SpoolFile -InFile $it.Id -OutFile $tf -Key $spoolKey | Out-Null } else { Copy-Item -LiteralPath $it.Id -Destination $tf -Force } }
                                else {
                                    $uri = ($cfg.datto.endpointUrl.TrimEnd('/')) + ($cfg.datto.apiPaths.downloadFile -replace '\{fileID\}', $it.Id)
                                    if ($spoolKey) { Invoke-SpoolDownload -Uri $uri -Headers $authHeader -OutFile $tf -Key $spoolKey -TimeoutSec $xferTo | Out-Null }
                                    else { Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -Headers $authHeader -OutFile $tf -TimeoutSec $xferTo | Out-Null }
                                }
                                $ok = $true; break
                            } catch {
                                $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
                                if (@(429,503) -contains $st) {
                                    $throttleTry++
                                    $ra = 0; try { $rah = $_.Exception.Response.Headers['X-Rate-Limit-Retry-After-Seconds']; if (-not $rah) { $rah = $_.Exception.Response.Headers['Retry-After'] }; if ($rah) { $ra = [int]$rah } } catch {}
                                    if ($ra -le 0) { $ra = [int][math]::Min([math]::Pow(2,[math]::Min($throttleTry,5)),30) }
                                    if ($throttleTry -ge 40) { $ok = $false; $err = "still rate-limited by Datto (HTTP $st) after $throttleTry waits: $($_.Exception.Message)"; break }
                                    Start-Sleep -Seconds $ra
                                } else {
                                    $hardTry++
                                    if ($hardTry -ge 5) { $ok = $false; $err = $_.Exception.Message; break }
                                    Start-Sleep -Seconds ([int][math]::Min([math]::Pow(2,$hardTry),30))
                                }
                            }
                        }
                        $dlSw.Stop()
                        $spool.Add(@{ Item = $it; TempFile = $tf; Ok = $ok; Error = $err; DlMs = $dlSw.Elapsed.TotalMilliseconds })
                    }
                } finally { $spool.CompleteAdding() }
            }).AddArgument($spool).AddArgument($toDo).AddArgument($Config).AddArgument($spaceTemp).AddArgument($script:SpoolKey).AddArgument($script:SpoolHelperSource)
            $prodH = $prod.BeginInvoke()
            $del = [powershell]::Create()
            $null = $del.AddScript({
                param($delQ, $flags)
                while (-not $flags.Done -or $delQ.Count -gt 0) {
                    $p = $null
                    if ($delQ.TryDequeue([ref]$p)) { try { [System.IO.File]::Delete($p) } catch {} }
                    else { Start-Sleep -Milliseconds 50 }
                }
            }).AddArgument($delQ).AddArgument($flags)
            $delH = $del.BeginInvoke()
            foreach ($ready in $spool.GetConsumingEnumerable()) {
                $fIdx++
                $it = $ready.Item
                if ([int64]$it.Size -ge $script:LargeFileBytes) { $etaLargeDone += [int64]$it.Size } else { $etaSmallDone++ }
                Lz390831b78c -Activity "Files: $($row.Space)" -Status $it.RelativePath -Current $fIdx -Total $fTotal -Id 2 | Out-Null
                $dlMs = 0.0; try { $dlMs = [double]$ready.DlMs } catch {}
                if (-not $ready.Ok) { $failed++; Lz12e519cc30 ERROR "  DOWNLOAD FAILED $($it.RelativePath): $($ready.Error). In plain terms: the file could not be downloaded from Datto. It will be retried on the next Sync."; Lz3c19440102 -Space $row.Space -Item $it -Status 'DownloadError' -DownloadMs $dlMs -ErrorMsg $ready.Error; if ($ready.TempFile) { $delQ.Enqueue($ready.TempFile) }; continue }
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $destInfo = Send-FileToDestination -Config $Config -DriveId $driveId -TargetFolder $effSub -Item $it -LocalFile $ready.TempFile -Space $row.Space
                    $v = Lzee645c3ed5 -Item $it -LocalFile $ready.TempFile -DestInfo $destInfo
                    $sw.Stop()
                    if ($v.Ok) {
                        if ($v.Zero) { Lz12e519cc30 WARN "  empty file (0 bytes), uploaded as-is: $($it.RelativePath)"; $zero++ }
                        $copied++; $bytes += $it.Size
                        if ($script:VerboseFiles) { Lz12e519cc30 INFO "  + [$($it.RelativePath)] $($v.Reason)" }
                        $stat = if($v.Zero){'ZeroByte'}else{'Copied'}
                        Lz3c19440102 -Space $row.Space -Item $it -Status $stat -Reason (Lz3413b7702d -Repair $repair -Item $it -Status $stat -Reason $v.Reason) -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $sw.Elapsed.TotalMilliseconds -DownloadMs $dlMs
                    } else {
                        $verifyFail++; Lz12e519cc30 ERROR "  VERIFY FAILED $($it.RelativePath): $($v.Reason). In plain terms: the uploaded copy did not match the original, so it was not marked done. It will be retried on the next Sync."
                        Lz3c19440102 -Space $row.Space -Item $it -Status 'VerifyFail' -Reason $v.Reason -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $sw.Elapsed.TotalMilliseconds -DownloadMs $dlMs
                    }
                } catch { $sw.Stop(); $failed++; Lz12e519cc30 ERROR "  UPLOAD FAILED $($it.RelativePath): $($_.Exception.Message). In plain terms: the file could not be uploaded to Microsoft 365. It will be retried on the next Sync."; Lz3c19440102 -Space $row.Space -Item $it -Status 'Error' -DurationMs $sw.Elapsed.TotalMilliseconds -DownloadMs $dlMs -ErrorMsg $_.Exception.Message }
                finally { $delQ.Enqueue($ready.TempFile) }
                Lz67aab01d86 -Done $fIdx -Total $fTotal -BytesDone $bytes -BytesTotal $spaceBytesTotal -Space $row.Space -SmallDone $etaSmallDone -SmallTotal $etaSmallTotal -LargeBytesDone $etaLargeDone -LargeBytesTotal $etaLargeTotal -Final 1
            }
            $prod.EndInvoke($prodH); $prod.Dispose()
            $flags.Done = $true
            $del.EndInvoke($delH); $del.Dispose()
        }
        try { Write-Progress -Id 2 -Activity 'Files' -Completed } catch {}
        $gb = [math]::Round($bytes/1GB,2)
        $szTxt = Format-Bytes $bytes
        $lvl = if (($failed + $verifyFail) -gt 0) { 'ERROR' } else { 'OK' }
        if ($willWrite) {
            Lz12e519cc30 $lvl "  $($row.Space): copied $copied, skipped $skipped, failed $failed, failed verification $verifyFail, empty files $zero ($szTxt)"
        } else {
            Lz12e519cc30 INFO "  $($row.Space): PREVIEW - would copy $copied file(s) ($szTxt) and skip $skipped unchanged. Nothing was uploaded."
        }
        $summary.Add([pscustomobject]@{ Space=$row.Space; Copied=$copied; Skipped=$skipped; Failed=$failed; VerifyFail=$verifyFail; ZeroByte=$zero; GB=$gb; Bytes=$bytes })
        $spacesCompleted++
        if ($willWrite -and -not $ResultDir) { Lz2a3d4bb598 -Config $Config -Mode $Mode -StartUtc $runStart -AuditFile $script:AuditFile -ExpectedFiles $expectedTotal -SpacesPlanned $spacesPlanned -SpacesCompleted $spacesCompleted }
    }
    try { Write-Progress -Id 1 -Activity "Transfer ($Mode)" -Completed } catch {}
    if ($ResultDir) {
        $summary | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $ResultDir ((ConvertTo-Slug ($map[0].Space)) + '-' + [guid]::NewGuid().ToString('N') + '.json')) -Encoding UTF8
    } else {
        $summary | Export-Csv -Path (Join-Path $Config.run.reportRoot "api-transfer-$Mode-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv") -NoTypeInformation -Encoding UTF8
    }
    $tc = ($summary | Measure-Object Copied -Sum).Sum
    $ts = ($summary | Measure-Object Skipped -Sum).Sum
    $tf = ($summary | Measure-Object Failed -Sum).Sum
    $tv = ($summary | Measure-Object VerifyFail -Sum).Sum
    $tb = [int64](($summary | Measure-Object Bytes -Sum).Sum)
    $szTxt = Format-Bytes $tb
    $elapsed = (Get-Date) - $runStart
    $el = '{0:hh\:mm\:ss}' -f $elapsed
    $rate = if ($elapsed.TotalSeconds -gt 0 -and $tb -gt 0) { " ~$([math]::Round(($tb*8/1e6)/$elapsed.TotalSeconds,1)) Mb/s ($([math]::Round(($tb/1MB)/$elapsed.TotalSeconds,1)) MB/s)." } else { '' }
    if ($willWrite) {
        $lvl = if (($tf + $tv) -gt 0) { 'ERROR' } else { 'OK' }
        Lz12e519cc30 $lvl "$(if ($Mode -eq 'Delta') { 'Sync' } else { 'Upload' }) finished in $(Format-Duration $elapsed) of copying. Totals: copied $tc, skipped $ts, failed $tf, failed verification $tv, $szTxt.$rate  Rate-limit pauses and retries: $script:RetryEvents."
        if ($script:RenameCount -gt 0) { Lz12e519cc30 INFO "Tidied $script:RenameCount name(s) to suit SharePoint (trailing spaces, illegal characters). Every change is listed in the report and in: $script:RenameFile" }
        if ($script:CollisionCount -gt 0) { Lz12e519cc30 WARN "$script:CollisionCount name collision(s): two Datto items would land on the same SharePoint path. Review before relying on this migration. Details in the report and in: $script:CollisionFile" }
        if (($tf + $tv) -gt 0) {
            Lz12e519cc30 WARN "In plain terms: uploaded $tc file(s) ($szTxt), but $($tf + $tv) did not make it ($tf failed, $tv could not be verified). Next step: click 'Sync new and changed' to retry the ones that did not upload, then 'Verify files arrived' to confirm everything is there."
            Lz12e519cc30 WARN "Review this log for [ERROR] lines (files that failed or failed verification). Failed files are not recorded as done; 'Sync new and changed' will retry them."
        } else {
            Lz12e519cc30 OK "In plain terms: all done. Uploaded $tc file(s) ($szTxt) with no failures. Next step (optional): click 'Verify files arrived' to double-check, or 'Compare sizes' for a quick overview."
        }
        if (-not $ResultDir -and $script:AuditFile -and (Test-Path $script:AuditFile)) {
            Lz12e519cc30 OK "Audit trail written: $script:AuditFile"
            try {
                $diag = Lz34a335c621 -Rows @(Import-Csv $script:AuditFile) -Elapsed $elapsed -ConfiguredWorkers $UploadWorkers -ThrottleEvents $script:RetryEvents
                if ($diag) {
                    Lz12e519cc30 INFO "What limited this run: $($diag.Verdict). $($diag.Why)"
                    Lz12e519cc30 INFO "  $($diag.Action)"
                    Lz12e519cc30 INFO "  Numbers: moved $(Format-Bytes $diag.Bytes) at about $($diag.AggMbps) Mb/s overall; single file about $($diag.PerStreamMbps) Mb/s; $($diag.UpSec)s uploading vs $($diag.DlSec)s downloading."
                    if ($diag.Concurrency) { Lz12e519cc30 INFO "  Concurrency: $($diag.Concurrency)" }
                    if ($diag.RetryDetail) { Lz12e519cc30 INFO "  Retries: $($diag.RetryDetail)" }
                    if ($diag.Projection)  { Lz12e519cc30 INFO "  Planning: $($diag.Projection)" }
                    if ($diag.Headroom)    { Lz12e519cc30 INFO "  Headroom: $($diag.Headroom)" }
                }
            } catch {}
        }
    }
    else { Lz12e519cc30 OK "Preview finished in $el. This was a rehearsal, nothing was uploaded. It would copy $tc file(s), $szTxt. In plain terms: if this looks right, click 'Upload all files' to do it for real." }
    }
    catch {
        $transferError = $_
        Lz12e519cc30 ERROR "RUN ABORTED before all files were processed: $($_.Exception.Message)"
    }
    finally {
        Lzf8243e7ae0 -Config $Config -Mode $Mode -RunStart $runStart -ExpectedFiles $expectedTotal `
            -SpacesPlanned $spacesPlanned -SpacesCompleted $spacesCompleted -RunError $transferError `
            -WillWrite:$willWrite -ResultDir $ResultDir
    }
}
function Lz52e5b1e5ca {
    param($Config, $Rows, [string]$Mode, [string]$DeltaMode='NewerWins', [int]$SpoolAhead, [int]$MaxParallelSpaces, [switch]$Execute)
    $willWrite = [bool]$Execute
    Lz12e519cc30 INFO "Parallel projects: $($Rows.Count) project(s), $MaxParallelSpaces at a time."
    $parallelStart = Get-Date
    $childExitCodes = New-Object System.Collections.Generic.List[int]
    if ($willWrite) { Lz2a3d4bb598 -Config $Config -Mode $Mode -StartUtc $parallelStart -AuditFile '' -ExpectedFiles 0 -SpacesPlanned $Rows.Count -SpacesCompleted 0 }
    $pwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $self = $PSCommandPath
    $resultDir = Join-Path $Config.run.stateRoot ("_parallel-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
    $childLogDir = Join-Path $Config.run.logRoot 'parallel'
    New-Item -ItemType Directory -Path $childLogDir -Force | Out-Null
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($r in $Rows) { $queue.Enqueue($r.Space) }
    $running = @{}
    $childInfo = @{}
    function Lz5f37328e3c {
        param($SpaceName)
        $q = { param($s) if ("$s" -match '\s') { '"' + $s + '"' } else { "$s" } }
        $slug = ConvertTo-Slug $SpaceName
        $childArgs = @('-NoProfile','-File', (& $q $self),
                       '-ConfigPath', (& $q $script:ConfigPath),
                       '-Action','Transfer','-Spaces', (& $q $SpaceName),
                       '-Mode', $Mode, '-DeltaMode', $DeltaMode, '-SpoolAhead', "$SpoolAhead",
                       '-MaxParallelSpaces','1','-ResultDir', (& $q $resultDir), '-GuiMode')
        if ($script:VerboseFiles) { $childArgs += '-VerboseFiles' }
        if ($script:UseEnumCache) { $childArgs += '-UseEnumCache' }
        if ($willWrite) { $childArgs += '-Execute' }
        $out = Join-Path $childLogDir "$slug.out.log"
        $err = Join-Path $childLogDir "$slug.err.log"
        $childInfo[$SpaceName] = @{ OutFile=$out; Pos=0; Partial=''; Done=0; Total=0; Bytes=[int64]0; BytesTotal=[int64]0 }
        return Start-Process -FilePath $pwshExe -ArgumentList $childArgs -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow
    }
    function Lz1a5281d0fd {
        param($Space)
        $ci = $childInfo[$Space]
        if (-not $ci -or -not (Test-Path $ci.OutFile)) { return }
        $chunk = ''
        try {
            $fs = [System.IO.File]::Open($ci.OutFile,'Open','Read','ReadWrite')
            $fs.Seek($ci.Pos,'Begin') | Out-Null
            $sr = New-Object System.IO.StreamReader($fs)
            $chunk = $sr.ReadToEnd(); $ci.Pos = $fs.Position; $sr.Close(); $fs.Close()
        } catch { return }
        if (-not $chunk) { return }
        $lines = ($ci.Partial + $chunk) -split "`r?`n"
        $ci.Partial = $lines[-1]
        for ($k = 0; $k -lt $lines.Count - 1; $k++) {
            $ln = $lines[$k]
            if ($ln -match '^##PROGRESS##\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|') {
                $ci.Done=[int]$Matches[1]; $ci.Total=[int]$Matches[2]; $ci.Bytes=[int64]$Matches[3]; $ci.BytesTotal=[int64]$Matches[4]
            } elseif ($ln) {
                Write-Host ("  [{0}] {1}" -f $Space, $ln)
            }
        }
    }
    function Lza11148ae77 {
        $sd=0; $st=0; $sb=[int64]0; $sbt=[int64]0
        foreach ($ci in $childInfo.Values) { $sd+=$ci.Done; $st+=$ci.Total; $sb+=$ci.Bytes; $sbt+=$ci.BytesTotal }
        if ($st -gt 0) { Lz67aab01d86 -Done $sd -Total $st -BytesDone $sb -BytesTotal $sbt -Space '(all projects)' }
    }
    while ($queue.Count -gt 0 -or $running.Count -gt 0) {
        while ($running.Count -lt $MaxParallelSpaces -and $queue.Count -gt 0) {
            $sp = $queue.Dequeue()
            Lz12e519cc30 INFO "  launch: $sp"
            $running[(Lz5f37328e3c -SpaceName $sp)] = $sp
        }
        Start-Sleep -Milliseconds 400
        foreach ($proc in @($running.Keys)) {
            $sp = $running[$proc]
            Lz1a5281d0fd -Space $sp
            if ($proc.HasExited) {
                Lz1a5281d0fd -Space $sp
                $lvl = if ($proc.ExitCode -eq 0) { 'OK' } else { 'ERROR' }
                Lz12e519cc30 $lvl "  done: $sp (exit $($proc.ExitCode))"
                $childExitCodes.Add([int]$proc.ExitCode)
                $running.Remove($proc)
            }
        }
        Lza11148ae77
    }
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($j in Get-ChildItem $resultDir -Filter *.json -ErrorAction SilentlyContinue) {
        foreach ($row in @(Get-Content $j.FullName -Raw | ConvertFrom-Json)) { $all.Add($row) }
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $combined = Join-Path $Config.run.reportRoot "api-transfer-$Mode-$stamp.csv"
    $all | Export-Csv -Path $combined -NoTypeInformation -Encoding UTF8
    $auditRows = New-Object System.Collections.Generic.List[object]
    foreach ($a in Get-ChildItem $resultDir -Filter 'audit-*.csv' -ErrorAction SilentlyContinue) {
        foreach ($r in @(Import-Csv $a.FullName)) { $auditRows.Add($r) }
    }
    if ($auditRows.Count) {
        $auditOut = Join-Path $Config.run.reportRoot "audit-$Mode-$stamp.csv"
        $auditRows | Export-Csv -Path $auditOut -NoTypeInformation -Encoding UTF8
        Lz12e519cc30 OK "Audit trail written: $auditOut ($($auditRows.Count) file actions)"
        if ($willWrite) {
            $spacesDone = @($childExitCodes | Where-Object { $_ -eq 0 -or $_ -eq 2 }).Count
            Invoke-RunFinalize -Config $Config -AuditFile $auditOut -Mode $Mode -RunStart $parallelStart `
                -SpacesPlanned $Rows.Count -SpacesCompleted $spacesDone | Out-Null
        } else {
            $savedLog = $script:LogFile
            try { Invoke-HtmlReport -Config $Config -AuditPath $auditOut | Out-Null } catch {}
            $script:LogFile = $savedLog
        }
    } elseif ($willWrite) {
        $spacesDone = @($childExitCodes | Where-Object { $_ -eq 0 -or $_ -eq 2 }).Count
        $emptyAudit = Join-Path $Config.run.reportRoot "audit-$Mode-$stamp.csv"
        try { '' | Set-Content -Path $emptyAudit -Encoding UTF8 } catch {}
        Invoke-RunFinalize -Config $Config -AuditFile $emptyAudit -Mode $Mode -RunStart $parallelStart `
            -SpacesPlanned $Rows.Count -SpacesCompleted $spacesDone | Out-Null
    }
    Remove-Item $resultDir -Recurse -Force -ErrorAction SilentlyContinue
    Lzf2c52e2d63 -Config $Config
    $tc = ($all | Measure-Object Copied -Sum).Sum
    $tf = ($all | Measure-Object Failed -Sum).Sum
    $tv = ($all | Measure-Object VerifyFail -Sum).Sum
    Lz12e519cc30 OK "Parallel projects finished. Copied $tc, failed $tf, failed verification $tv. Record: $combined"
}
function Get-RowDestLabel {
    param($Row)
    if ("$($Row.DestinationType)" -eq 'OneDrive') { return "OneDrive of $($Row.TargetPrincipal)" }
    $lib = ''
    try { if ($Row.PSObject.Properties.Name -contains 'TargetLibrary') { $lib = "$($Row.TargetLibrary)".Trim() } } catch {}
    if (-not $lib) { $lib = 'the default library' }
    return "$($Row.DestinationUrl) > $lib"
}
function Get-DestinationInventory {
    param($Config, $Row, [switch]$WithTimes)
    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $times = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $sizes = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($Config.destination.provider -eq 'LocalSim') {
        $base = Join-Path $Config.destination.sim.rootPath (ConvertTo-Slug ($Row.DestinationUrl))
        $sub = Join-SubPath $Row.TargetSubFolder (Get-NestFolder $Config $Row)
        $simScope = ''
        try { if ($Row.PSObject.Properties.Name -contains 'SourceSubPath') { $simScope = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
        $simCo = $false
        try { if ($Row.PSObject.Properties.Name -contains 'SourceContentsOnly') { $simCo = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
        if (-not $simCo) { $sub = Join-SubPath $sub $simScope }
        $root = if ($sub) { Join-Path $base ($sub -replace '/', '\') } else { $base }
        if (-not (Test-Path $root)) { return @{ Count = 0; Bytes = 0; Paths = $paths; Times = $times; Sizes = $sizes } }
        $files = @(Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/]_DattoMigration[\\/]' })
        foreach ($f in $files) {
            $rel = ($f.FullName.Substring($root.Length).TrimStart('\','/') -replace '\\','/')
            [void]$paths.Add($rel)
            $sizes[$rel] = [int64]$f.Length
            if ($WithTimes) { $times[$rel] = $f.LastWriteTimeUtc }
        }
        return @{ Count = $files.Count; Bytes = [int64](($files | Measure-Object Length -Sum).Sum); Paths = $paths; Times = $times; Sizes = $sizes }
    }
    $res = Resolve-DestinationDriveId -Config $Config -Row $Row
    $driveId = $res.DriveId
    $scope = ''
    try { if ($Row.PSObject.Properties.Name -contains 'SourceSubPath') { $scope = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
    $co = $false
    try { if ($Row.PSObject.Properties.Name -contains 'SourceContentsOnly') { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    if (-not $scope) { $co = $false }
    $startSub = if ($co) { $res.SubFolder } else { Join-SubPath $res.SubFolder $scope }
    $count = 0; $bytes = [int64]0; $folders = 0; $pages = 0
    $dProg = @{ LastLog = [DateTime]::UtcNow }
    $emitDest = {
        param([string]$Where, [switch]$Force)
        $now = [DateTime]::UtcNow
        if (-not $Force -and ($now - $dProg.LastLog).TotalSeconds -lt 3) { return }
        $dProg.LastLog = $now
        $w = if ($Where) { "  now in: /$Where" } else { '' }
        Lz12e519cc30 INFO "  DESTINATION: $('{0:N0}' -f $folders) folder(s) read, $('{0:N0}' -f $count) file(s) found so far.$w"
        if ($script:GuiMode) { Write-Host "##STATUS##|Source: $('{0:N0}' -f $script:SrcTotal) files (done)   ->   Destination: $('{0:N0}' -f $folders) folders, $('{0:N0}' -f $count) files so far (reading Microsoft 365)" }
    }
    $stack = New-Object System.Collections.Stack
    $startNode = if ($startSub) { "root:/$([uri]::EscapeDataString($startSub) -replace '%2F','/'):" } else { 'root' }
    $stack.Push(@{ Node = $startNode; Prefix = $(if ($scope -and -not $co) { "$scope/" } else { '' }); Root = $true })
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $uri = "https://graph.microsoft.com/v1.0/drives/$driveId/$($cur.Node)/children"
        $page = $null
        try {
            $page = Get-GraphCollection -Config $Config -Uri $uri -What "list $($cur.Node)"
        } catch {
            $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
            if ($cur.Root -and $st -eq 404) {
                Lz12e519cc30 INFO "  destination inventory: the folder does not exist at the destination yet, so there is nothing to compare against and every file will be copied. This is normal the first time you copy into a new folder."
                return @{ Count = 0; Bytes = 0; Paths = $paths; Times = $times; Sizes = $sizes }
            }
            throw
        }
        $folders++; $pages += $page.Pages; & $emitDest $cur.Prefix
        foreach ($c in $page.Values) {
            $nm = "$($c['name'])"
            if ($nm -eq '_DattoMigration' -and $cur.Root) { continue }
            if ($c.ContainsKey('folder')) { $stack.Push(@{ Node = "items/$($c['id'])"; Prefix = ($cur.Prefix + $nm + '/'); Root = $false } ) }
            else {
                $count++; $bytes += [int64]$c['size']; $rel = ($cur.Prefix + $nm); [void]$paths.Add($rel)
                $sizes[$rel] = [int64]$c['size']
                if ($WithTimes) { $lm = $null; try { $lm = [string]$c['lastModifiedDateTime'] } catch {}; $times[$rel] = (ConvertTo-UtcDate $lm) }
            }
        }
    }
    $extra = $pages - $folders
    Lz12e519cc30 INFO "  DESTINATION FINISHED: $('{0:N0}' -f $count) file(s) across $('{0:N0}' -f $folders) folder(s), $pages page(s) followed."
    if ($extra -gt 0) {
        Lz12e519cc30 WARN "  $extra destination folder(s) held more than one page of children. Before the paging fix everything past the first page was invisible here, so a Sync would have judged those files missing and re-uploaded over the top of them. They are now enumerated in full."
    }
    return @{ Count = $count; Bytes = $bytes; Paths = $paths; Times = $times; Sizes = $sizes }
}
function Get-EvalKey {
    param([string]$TenantId)
    $t = "$TenantId".Trim().ToLowerInvariant()
    if (-not $t) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("liscaragh-eval:$t")) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}
function Lz5f1e4dc7c1 {
    $root = ''
    try { $root = "$env:LISCARA_EVAL_ROOT" } catch {}
    if ($root) { return @{ RegPath = ''; FilePath = (Join-Path $root 'eval.dat') } }
    $pd = ''
    try { $pd = "$env:ProgramData" } catch {}
    $fp = if ($pd) { Join-Path $pd (Join-Path 'Liscaragh' 'eval.dat') } else { '' }
    return @{ RegPath = 'HKCU:\Software\DattoMigration\State'; FilePath = $fp }
}
function Lzcf1f6a0a7c {
    param([string]$Value)
    $o = @{ FirstPass = 0; Delta = 0 }
    if ("$Value" -match 'F:(\d+)') { $o.FirstPass = [int]$Matches[1] }
    if ("$Value" -match 'D:(\d+)') { $o.Delta     = [int]$Matches[1] }
    return $o
}
function Get-EvalUsage {
    param([string]$Key)
    $out = @{ FirstPass = 0; Delta = 0 }
    if (-not $Key) { return $out }
    $st = Lz5f1e4dc7c1
    if ($st.RegPath) {
        try {
            $v = (Get-ItemProperty -Path $st.RegPath -Name $Key -ErrorAction Stop).$Key
            $p = Lzcf1f6a0a7c "$v"
            if ($p.FirstPass -gt $out.FirstPass) { $out.FirstPass = $p.FirstPass }
            if ($p.Delta     -gt $out.Delta)     { $out.Delta     = $p.Delta }
        } catch {}
    }
    if ($st.FilePath) {
        try {
            if (Test-Path $st.FilePath) {
                foreach ($line in (Get-Content $st.FilePath -ErrorAction Stop)) {
                    if ("$line".StartsWith("$Key=")) {
                        $p = Lzcf1f6a0a7c "$line"
                        if ($p.FirstPass -gt $out.FirstPass) { $out.FirstPass = $p.FirstPass }
                        if ($p.Delta     -gt $out.Delta)     { $out.Delta     = $p.Delta }
                    }
                }
            }
        } catch {}
    }
    return $out
}
function Add-EvalUsage {
    param([string]$Key, [string]$Bucket, [int]$Count)
    if (-not $Key -or $Count -le 0) { return }
    $u = Get-EvalUsage -Key $Key
    if ($Bucket -eq 'FirstPass') { $u.FirstPass += $Count } else { $u.Delta += $Count }
    $val = "F:$($u.FirstPass);D:$($u.Delta)"
    $st = Lz5f1e4dc7c1
    if ($st.RegPath) {
        try {
            if (-not (Test-Path $st.RegPath)) { New-Item -Path $st.RegPath -Force | Out-Null }
            New-ItemProperty -Path $st.RegPath -Name $Key -Value $val -PropertyType String -Force | Out-Null
        } catch {}
    }
    if ($st.FilePath) {
        try {
            $dir = Split-Path -Parent $st.FilePath
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $lines = New-Object System.Collections.Generic.List[string]
            if (Test-Path $st.FilePath) {
                foreach ($line in (Get-Content $st.FilePath -ErrorAction Stop)) {
                    if (-not "$line".StartsWith("$Key=")) { $lines.Add("$line") }
                }
            }
            $lines.Add("$Key=$val")
            [System.IO.File]::WriteAllLines($st.FilePath, $lines)
        } catch {}
    }
}
function Test-MigrationLicence {
    param($Config, [string]$PublicKeyB64 = '', [string]$LiveTenantId = '')
    if (-not $PublicKeyB64) { $PublicKeyB64 = $script:LicencePublicKey }
    $out = @{ Licensed = $false; Customer = ''; TenantId = ''; LicenceId = ''; Reason = ''; Path = '' }
    $path = ''
    try { if (($Config.run.PSObject.Properties.Name -contains 'licenceFile') -and $Config.run.licenceFile) { $path = "$($Config.run.licenceFile)" } } catch {}
    if (-not $path) { $path = Join-Path (Split-Path $PSScriptRoot -Parent) 'licence.json' }
    $out.Path = $path
    if (-not (Test-Path $path)) { $out.Reason = "no licence file at $path"; return $out }
    if (-not $PublicKeyB64) { $out.Reason = 'this build carries no licence verification key, so it runs as a demo'; return $out }
    try {
        $j = Get-Content $path -Raw | ConvertFrom-Json
        $pb  = [Convert]::FromBase64String("$($j.PayloadB64)")
        $sig = [Convert]::FromBase64String("$($j.Signature)")
        $ecdsa = [System.Security.Cryptography.ECDsa]::Create()
        try {
            $read = 0
            $ecdsa.ImportSubjectPublicKeyInfo([Convert]::FromBase64String($PublicKeyB64), [ref]$read)
            if (-not $ecdsa.VerifyData($pb, $sig, [System.Security.Cryptography.HashAlgorithmName]::SHA256)) {
                $out.Reason = 'the licence file failed its signature check (it has been edited, or was not issued by Liscaragh)'; return $out
            }
        } finally { $ecdsa.Dispose() }
        $pl = [System.Text.Encoding]::UTF8.GetString($pb) | ConvertFrom-Json
        $out.Customer = "$($pl.Customer)"; $out.TenantId = "$($pl.TenantId)"; $out.LicenceId = "$($pl.LicenceId)"
        if ([int]$pl.Schema -ne 1) { $out.Reason = "unsupported licence format (schema $($pl.Schema)); update the tool"; return $out }
        $exp = ''; try { $exp = "$($pl.Expires)" } catch {}
        if ($exp) {
            $ed = [datetime]::MinValue
            if ([datetime]::TryParse($exp, [ref]$ed) -and $ed.Date -lt (Get-Date).Date) { $out.Reason = "the licence expired on $exp"; return $out }
        }
        if ($LiveTenantId -and ($out.TenantId -ne $LiveTenantId)) {
            $out.Reason = "this licence is for Microsoft tenant $($out.TenantId), but this job is connected to tenant $LiveTenantId. Licences are per tenant and cannot be moved."
            return $out
        }
        $out.Licensed = $true
        return $out
    } catch { $out.Reason = "the licence file could not be read: $($_.Exception.Message)"; return $out }
}
function Format-Duration {
    param([TimeSpan]$T)
    if ($T.TotalHours -ge 1) { return ('{0}h {1:00}m {2:00}s' -f [int][math]::Floor($T.TotalHours), $T.Minutes, $T.Seconds) }
    if ($T.TotalMinutes -ge 1) { return ('{0}m {1:00}s' -f $T.Minutes, $T.Seconds) }
    return ('{0}s' -f [int][math]::Max([math]::Ceiling($T.TotalSeconds), 0))
}
function Format-Bytes {
    param([int64]$b)
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N2} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N1} KB' -f ($b / 1KB)) }
    return "$b B"
}
function Lz34a335c621 {
    param($Rows, [TimeSpan]$Elapsed, [int]$ConfiguredWorkers=0, [int]$ThrottleEvents=0)
    $copied    = @($Rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' })
    $attempted = @($Rows | Where-Object { $_.Status -ne 'Skipped' -and $_.Status -ne 'WouldCopy' })
    $fails     = @($Rows | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'DownloadError' -or $_.Status -eq 'VerifyFail' -or $_.Status -eq 'SkippedTooLarge' })
    $n = $copied.Count
    if ($n -eq 0) { return $null }
    $bytes = [int64]0; foreach ($r in $copied) { $bytes += [int64]$r.SourceSizeBytes }
    $upMs = 0.0; $dlMs = 0.0; $retriesSum = 0; $retriedCount = 0
    foreach ($r in $Rows) {
        $upMs += [double]$r.UploadMs; $dlMs += [double]$r.DownloadMs
        $rt = [int]$r.Retries; $retriesSum += $rt; if ($rt -gt 0) { $retriedCount++ }
    }
    $upSec = $upMs/1000.0; $dlSec = $dlMs/1000.0
    $wallSec = [math]::Max($Elapsed.TotalSeconds, 0.001)
    $aggMbps = [math]::Round(($bytes*8/1e6)/$wallSec, 1)
    $spd = New-Object System.Collections.Generic.List[double]
    foreach ($r in $copied) { $sz=[int64]$r.SourceSizeBytes; $u=[double]$r.UploadMs; if ($sz -ge 65536 -and $u -gt 0) { $spd.Add(($sz*8/1e6)/($u/1000.0)) } }
    $sorted = @($spd | Sort-Object)
    $perStream = if ($sorted.Count) { [math]::Round($sorted[[int][math]::Floor($sorted.Count/2)],1) } else { 0 }
    $effConc = [math]::Round($upSec/$wallSec, 1)
    $avgBytes = [int64]($bytes/[math]::Max($n,1))
    $avgKB = [math]::Round($avgBytes/1KB, 0)
    $retryPct = if ($n) { [math]::Round(100.0*$retriedCount/$n,1) } else { 0 }
    $failPct  = if ($attempted.Count) { [math]::Round(100.0*$fails.Count/$attempted.Count,1) } else { 0 }
    if ($fails.Count -gt 0 -and $failPct -ge 5) {
        $verdict = 'Errors / verification, not speed'
        $why     = "$($fails.Count) file(s) failed or failed verification, which is $failPct% of those attempted."
        $action  = "Click 'Sync new and changed' to retry them, then 'Verify files arrived' to confirm."
    }
    elseif (($upSec + $dlSec) -lt 1 -or $n -lt 5) {
        $verdict = 'Too small to analyse'
        $why     = "Only $n file(s) and under a second of transfer time, so there is not enough here to identify a bottleneck."
        $action  = "Run a larger batch to get a meaningful reading."
    }
    elseif ($retryPct -ge 5 -or ($n -ge 50 -and $retriesSum -ge ($n*0.1))) {
        $verdict = 'Microsoft 365 API throttling'
        $why     = "$retriedCount file(s) ($retryPct%) hit a backoff/retry and there were $retriesSum retries in total. Microsoft was asking the tool to slow down."
        $action  = "This is expected on large jobs and the tool handled it automatically (easing off, then recovering). If it dominated, lower 'Upload workers' a little or run fewer projects at once."
    }
    elseif ($dlSec -gt ($upSec*1.5)) {
        $verdict = 'Datto download speed'
        $why     = "Reading files from Datto took the most time, about $([int]$dlSec)s downloading versus $([int]$upSec)s uploading."
        $action  = "The limit was the Datto side, not writing to Microsoft 365. Usually the Datto service or your download bandwidth."
    }
    elseif ($avgKB -lt 256 -and $n -ge 200 -and $perStream -lt 8) {
        $spdTxt = if ($perStream -gt 0) { "single-file speed was only about $perStream Mb/s" } else { "the files are too small to reach any real transfer speed" }
        $verdict = 'Many small files (per-file overhead)'
        $why     = "Files averaged about $avgKB KB across $n files, and $spdTxt, so per-file overhead (setup plus network latency), not bandwidth, set the pace."
        $action  = "Bandwidth is not the bottleneck here; many tiny files are simply slow to handle one by one. More upload workers can help if the tenant tolerates it."
    }
    else {
        $verdict = 'Upload bandwidth (your internet upload speed)'
        $why     = "Uploading dominated (about $([int]$upSec)s versus $([int]$dlSec)s downloading) with few retries. Single stream was about $perStream Mb/s across roughly $effConc concurrent uploads, for about $aggMbps Mb/s overall."
        $action  = "The upload line was the ceiling. Only more upload bandwidth, or more parallel uploads if Microsoft 365 tolerates it, will go faster."
    }
    $fmtDur = {
        param($secs)
        if ($secs -lt 90)     { return ('{0}s' -f [int]$secs) }
        if ($secs -lt 5400)   { return ('{0:N0} min' -f ($secs/60.0)) }
        if ($secs -lt 172800) { return ('{0:N1} hours' -f ($secs/3600.0)) }
        return ('{0:N1} days' -f ($secs/86400.0))
    }
    $projection = if ($aggMbps -gt 0) {
        "At about $aggMbps Mb/s overall, 100 GB would take about $(& $fmtDur (100.0*8000.0/$aggMbps)) and 1 TB about $(& $fmtDur (1000.0*8000.0/$aggMbps)) (network permitting)."
    } else { $null }
    $thrEv = [math]::Max($ThrottleEvents, $retriesSum)
    $retryDetail = if ($thrEv -gt 0) {
        $fw = if ($retriedCount -eq 1) { 'file' } else { 'files' }
        "$thrEv back-off/retry event(s) across $retriedCount $fw. Microsoft asked the tool to slow down; it did, then recovered."
    } else {
        "No back-offs or retries. Every file uploaded first time."
    }
    $concurrency = if ($ConfiguredWorkers -gt 0) {
        if ($effConc -ge ($ConfiguredWorkers - 0.3)) {
            "Ran at roughly $effConc of $ConfiguredWorkers configured uploaders (full concurrency)."
        } else {
            $capBy = if ($thrEv -gt 0) { 'throttling and/or files not being ready in time' } else { 'files not always being ready in time (download or per-file overhead)' }
            "Ran at roughly $effConc of $ConfiguredWorkers configured uploaders; concurrency was held below the maximum by $capBy."
        }
    } else { $null }
    $headroom = switch ($verdict) {
        'Upload bandwidth (your internet upload speed)' {
            "Single stream was about $perStream Mb/s for $aggMbps Mb/s total. If your upload line is faster than $aggMbps Mb/s, more upload workers should raise the total; if $aggMbps Mb/s is your line's ceiling, more workers will not help."
        }
        'Many small files (per-file overhead)' {
            "Bandwidth is not the limit here, so more upload workers should raise throughput. Tenant permitting, try increasing them."
        }
        'Microsoft 365 API throttling' {
            "The tenant is pushing back, so more workers would worsen throttling. Fewer workers, or fewer projects at once, is the lever."
        }
        'Datto download speed' {
            "The limit is reading from Datto, so more upload workers will not change it."
        }
        default { $null }
    }
    return [pscustomobject]@{
        Verdict=$verdict; Why=$why; Action=$action
        AggMbps=$aggMbps; PerStreamMbps=$perStream; EffConcurrency=$effConc
        AvgFileKB=$avgKB; AvgFileBytes=$avgBytes; RetriedCount=$retriedCount; RetriesSum=$retriesSum; RetryPct=$retryPct
        Failures=$fails.Count; UpSec=[int]$upSec; DlSec=[int]$dlSec; Files=$n; Bytes=$bytes
        Projection=$projection; RetryDetail=$retryDetail; Concurrency=$concurrency; Headroom=$headroom
    }
}
function Lz1b8f5c9685 {
    param($Config, $Row, $Items, $Inv)
    $folderOf = {
        param([string]$Path)
        $i = "$Path".LastIndexOf('/')
        if ($i -lt 0) { return '(top level)' }
        return "$Path".Substring(0, $i)
    }
    $srcSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($it in $Items) { [void]$srcSet.Add("$($it.RelativePath)") }
    $agg = @{}
    $nExtra = 0; $nMissing = 0
    $extraPaths   = [System.Collections.Generic.List[string]]::new()
    $missingPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $Inv.Paths) {
        if ($srcSet.Contains("$p")) { continue }
        $nExtra++; [void]$extraPaths.Add("$p"); $k = "AtDestinationOnly|$(& $folderOf $p)"
        if ($agg.ContainsKey($k)) { $agg[$k]++ } else { $agg[$k] = 1 }
    }
    foreach ($it in $Items) {
        $p = "$($it.RelativePath)"
        if ($Inv.Paths.Contains($p)) { continue }
        $nMissing++; [void]$missingPaths.Add("$p"); $k = "InDattoOnly|$(& $folderOf $p)"
        if ($agg.ContainsKey($k)) { $agg[$k]++ } else { $agg[$k] = 1 }
    }
    if (-not $agg.Count) { Lz12e519cc30 OK "  [$($Row.Space)] every file matches by path, both ways. Nothing extra, nothing missing."; return ([pscustomobject]@{ Missing = 0; Extra = 0 }) }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($p in $missingPaths) { [void]$rows.Add([pscustomobject]@{ Side = 'InDattoOnly';       Space = "$($Row.Space)"; Folder = (& $folderOf $p); Path = "$p" }) }
    foreach ($p in $extraPaths)   { [void]$rows.Add([pscustomobject]@{ Side = 'AtDestinationOnly'; Space = "$($Row.Space)"; Folder = (& $folderOf $p); Path = "$p" }) }
    $sortedAgg = @($agg.Keys | ForEach-Object {
        $side, $folder = "$_".Split('|', 2)
        [pscustomobject]@{ Side = $side; Folder = $folder; Files = $agg[$_] }
    } | Sort-Object -Property @{Expression='Side'}, @{Expression='Files'; Descending=$true})
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $safe  = "$($Row.Space)" -replace '[^A-Za-z0-9\-]+', '_'
    $out   = Join-Path $Config.run.reportRoot ("sizecheck-diff-{0}-{1}.csv" -f $safe, $stamp)
    try {
        $rows | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
        Lz12e519cc30 OK "  [$($Row.Space)] difference written (one row per file): $out"
        if ($script:GuiMode) { Write-Host "##CHECKFILES##|$nMissing|$nExtra|0|$out" }
    } catch {
        Lz12e519cc30 WARN "  [$($Row.Space)] could not write the difference CSV: $($_.Exception.Message)"
    }
    if ($nMissing) {
        Lz12e519cc30 WARN "  [$($Row.Space)] $('{0:N0}' -f $nMissing) file(s) in Datto that are NOT at the destination:"
        foreach ($p in @($missingPaths | Select-Object -First 15)) { Lz12e519cc30 WARN "      missing: /$p" }
        if ($nMissing -gt 15) { Lz12e519cc30 WARN "      ... and $('{0:N0}' -f ($nMissing - 15)) more. Every one is named in the CSV above." }
    }
    if ($nExtra)   { Lz12e519cc30 INFO "  [$($Row.Space)] $('{0:N0}' -f $nExtra) file(s) at the destination that are NOT in Datto (usually pre-existing content). Biggest folders:" }
    foreach ($r in @($sortedAgg | Where-Object { $_.Side -eq 'AtDestinationOnly' } | Select-Object -First 8)) {
        Lz12e519cc30 INFO ("      {0,8:N0}  /{1}" -f $r.Files, $r.Folder)
    }
    return ([pscustomobject]@{ Missing = $nMissing; Extra = $nExtra })
}
function Lz10e2c69832 {
    param($Config, [string]$SpaceName, [string]$ResultDir)
    Lzffe69bba89 -Config $Config -Stage 'api-destinv'
    if (-not $SpaceName) { throw "DestInventory needs -Spaces with exactly one space name." }
    if (-not $ResultDir) { throw "DestInventory needs -ResultDir." }
    Connect-Destination -Config $Config
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPath)) { throw "No mapping.csv found in $($Config.run.reportRoot)." }
    $row = @(Import-Csv $mapPath | Where-Object { $_.Action -eq 'MIGRATE' -and $_.Space -eq $SpaceName }) | Select-Object -First 1
    if (-not $row) { throw "Space '$SpaceName' is not a MIGRATE row in mapping.csv." }
    $inv = Get-DestinationInventory -Config $Config -Row $row -WithTimes
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $inv.Paths) {
        $t = ''
        if ($inv.Times.ContainsKey($p) -and $null -ne $inv.Times[$p]) { $t = "$(([datetime]$inv.Times[$p]).ToUniversalTime().Ticks)" }
        $s = [int64]0; if ($inv.Sizes.ContainsKey($p)) { $s = [int64]$inv.Sizes[$p] }
        [void]$files.Add([pscustomobject]@{ p = $p; s = $s; t = $t })
    }
    $scope = ''
    try { if ($row.PSObject.Properties.Name -contains 'SourceSubPath') { $scope = "$($row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
    $co = $false
    try { if ($row.PSObject.Properties.Name -contains 'SourceContentsOnly') { $co = ("$($row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    $doc = [pscustomobject]@{ Version = 1; Space = "$SpaceName"; SourceSubPath = $scope; ContentsOnly = $co
                              Count = [int]$inv.Count; Bytes = [int64]$inv.Bytes; Files = $files }
    $out = Join-Path $ResultDir ("destinv-" + (ConvertTo-Slug $SpaceName) + ".json")
    $doc | ConvertTo-Json -Depth 4 -Compress | Set-Content -Path $out -Encoding UTF8
    Lz12e519cc30 OK "  DESTINATION inventory written: $('{0:N0}' -f [int]$inv.Count) file(s). $out"
}
function Lz1977e2a874 {
    param($Config, $Row)
    try {
        $pwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $self = $PSCommandPath
        $slug = ConvertTo-Slug $Row.Space
        $dir = Join-Path $Config.run.stateRoot ("_destinv-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID")
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $q = { param($s) if ("$s" -match '\s') { '"' + $s + '"' } else { "$s" } }
        $childArgs = @('-NoProfile','-File', (& $q $self),
                       '-ConfigPath', (& $q $script:ConfigPath),
                       '-Action','DestInventory','-Spaces', (& $q $Row.Space),
                       '-ResultDir', (& $q $dir))
        $out = Join-Path $dir "$slug.out.log"
        $err = Join-Path $dir "$slug.err.log"
        $proc = Start-Process -FilePath $pwshExe -ArgumentList $childArgs -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow
        Lz12e519cc30 INFO "  Reading the DESTINATION in the background (helper process $($proc.Id)) while the Datto list is read."
        return @{ Process = $proc; File = (Join-Path $dir "destinv-$slug.json"); OutLog = $out; ErrLog = $err; Pos = [long]0; Partial = '' }
    } catch {
        Lz12e519cc30 WARN "  could not start the background destination read ($($_.Exception.Message)). The destination will be read after the source instead - slower, same answer."
        return $null
    }
}
function Lzc9b9db72b7 {
    param($Job)
    if (-not (Test-Path $Job.OutLog)) { return }
    $chunk = ''
    try {
        $fs = [System.IO.File]::Open($Job.OutLog,'Open','Read','ReadWrite')
        $fs.Seek($Job.Pos,'Begin') | Out-Null
        $sr = New-Object System.IO.StreamReader($fs)
        $chunk = $sr.ReadToEnd(); $Job.Pos = $fs.Position; $sr.Close(); $fs.Close()
    } catch { return }
    if (-not $chunk) { return }
    $lines = ($Job.Partial + $chunk) -split "`r?`n"
    $Job.Partial = $lines[-1]
    for ($k = 0; $k -lt $lines.Count - 1; $k++) {
        if ("$($lines[$k])".Trim()) { Write-Host ("  [destination] {0}" -f $lines[$k]) }
    }
}
function Receive-DestInventoryJob {
    param($Config, $Row, $Job, [switch]$WithTimes)
    if (-not $Job) { return (Get-DestinationInventory -Config $Config -Row $Row -WithTimes:$WithTimes) }
    $lastStatus = [DateTime]::UtcNow
    while (-not $Job.Process.HasExited) {
        Lzc9b9db72b7 -Job $Job
        if ($script:GuiMode -and ([DateTime]::UtcNow - $lastStatus).TotalSeconds -ge 3) {
            $lastStatus = [DateTime]::UtcNow
            Write-Host "##STATUS##|Source: $('{0:N0}' -f $script:SrcTotal) files (done)   ->   Destination: still being read (started in parallel)..."
        }
        Start-Sleep -Milliseconds 400
    }
    Lzc9b9db72b7 -Job $Job
    try {
        if ($Job.Process.ExitCode -ne 0) { throw "the destination child exited $($Job.Process.ExitCode); its log is $($Job.OutLog)" }
        if (-not (Test-Path $Job.File)) { throw "the destination child wrote no result file ($($Job.File))" }
        $doc = Get-Content $Job.File -Raw | ConvertFrom-Json
        if ([int]$doc.Version -ne 1) { throw "result version $($doc.Version) is not 1" }
        if ("$($doc.Space)" -ne "$($Row.Space)") { throw "result is for space '$($doc.Space)', expected '$($Row.Space)'" }
        $scope = ''
        try { if ($Row.PSObject.Properties.Name -contains 'SourceSubPath') { $scope = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
        if ("$($doc.SourceSubPath)" -ne $scope) { throw "result scope '$($doc.SourceSubPath)' does not match the row's '$scope'" }
        $co = $false
        try { if ($Row.PSObject.Properties.Name -contains 'SourceContentsOnly') { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
        $docCo = $false; if ($doc.PSObject.Properties.Name -contains 'ContentsOnly') { $docCo = [bool]$doc.ContentsOnly }
        if ($docCo -ne $co) { throw "result contents-only flag '$docCo' does not match the row's '$co' (087)" }
        $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $times = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $sizes = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($f in @($doc.Files)) {
            $p = "$($f.p)"
            [void]$paths.Add($p)
            $sizes[$p] = [int64]$f.s
            if ($WithTimes) { $times[$p] = if ("$($f.t)" -match '^\d+$') { [DateTime]::new([long]$f.t, [System.DateTimeKind]::Utc) } else { $null } }
        }
        Lz12e519cc30 OK "  DESTINATION list received from the background helper: $('{0:N0}' -f [int]$doc.Count) file(s)."
        return @{ Count = [int]$doc.Count; Bytes = [int64]$doc.Bytes; Paths = $paths; Times = $times; Sizes = $sizes }
    } catch {
        Lz12e519cc30 WARN "  the background destination list could not be used ($($_.Exception.Message)). Reading the destination directly instead - slower, same answer."
        return (Get-DestinationInventory -Config $Config -Row $Row -WithTimes:$WithTimes)
    }
}
function Invoke-SizeCheck {
    param($Config, [string]$OnlySpace)
    Lzffe69bba89 -Config $Config -Stage 'api-sizecheck'
    $ckStart = Get-Date
    Lz35962d6dcd -Config $Config
    Connect-Destination -Config $Config
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPath)) { Lz12e519cc30 ERROR "No mapping.csv found. Set a destination and save the mapping first."; return }
    $map = @(Import-Csv $mapPath | Where-Object Action -eq 'MIGRATE')
    if ($OnlySpace) { $map = @($map | Where-Object { $_.Space -eq $OnlySpace }) }
    if (-not $map.Count) { Lz12e519cc30 WARN "No mapped projects to check."; return }
    $tSrcC = 0; $tSrcB = [int64]0; $tDstC = 0; $tDstB = [int64]0; $tMissing = 0; $tExtra = 0; $i = 0; $t = $map.Count
    foreach ($row in $map) {
        $i++; Lz67aab01d86 -Done $i -Total $t -BytesDone 0 -BytesTotal 0 -Space $row.Space
        try {
            $null = Resolve-DestinationDriveId -Config $Config -Row $row
            Lz12e519cc30 OK "  destination reachable: $(Get-RowDestLabel $row). Reading the source now."
        } catch {
            Lz12e519cc30 ERROR "  destination NOT reachable for [$($row.Space)], so the source was not read: $($_.Exception.Message)"
            continue
        }
        $space = New-SpaceRef -Row $row
        $dj = Lz1977e2a874 -Config $Config -Row $row
        $items = @(Get-DattoItems -Config $Config -Space $space)
        $sc = $items.Count
        $sb = [int64](($items | Measure-Object Size -Sum).Sum)
        $inv = Receive-DestInventoryJob -Config $Config -Row $row -Job $dj
        $tSrcC += $sc; $tSrcB += $sb; $tDstC += $inv.Count; $tDstB += $inv.Bytes
        $d = Lz1b8f5c9685 -Config $Config -Row $row -Items $items -Inv $inv
        $nMiss = [int]$d.Missing; $nExt = [int]$d.Extra
        $tMissing += $nMiss; $tExtra += $nExt
        if ($nMiss -gt 0)     { $tag = "destination is MISSING $nMiss file(s)$(if ($nExt) { ", and holds $nExt extra" })"; $lvl = 'WARN' }
        elseif ($nExt -gt 0)  { $tag = "destination has $nExt more (likely pre-existing content)"; $lvl = 'OK' }
        else                  { $tag = 'counts match';                                          $lvl = 'OK' }
        Lz12e519cc30 $lvl ("  [$($row.Space)]  source $sc files / $(Format-Bytes $sb)   ->   destination $($inv.Count) files / $(Format-Bytes $inv.Bytes)   [$tag]")
    }
    Lz12e519cc30 OK ("TOTAL  source $tSrcC files / $(Format-Bytes $tSrcB)    destination $tDstC files / $(Format-Bytes $tDstB)")
    if ($tMissing -gt 0) {
        Lz12e519cc30 WARN "$('{0:N0}' -f $tMissing) file(s) in Datto are not at the destination (named above and in the difference CSV), so some files may not have migrated. Click 'Sync new and changed' to copy them, then compare again.$(if ($tExtra) { " The destination also holds $('{0:N0}' -f $tExtra) extra file(s), which is usually pre-existing content." })"
    } elseif ($tExtra -gt 0) {
        Lz12e519cc30 INFO "The destination has more files than the source. That is normal if the destination already held content before the migration. To confirm every source file actually arrived, click 'Verify files arrived': it checks file by file and ignores pre-existing extras."
    }
    Lz12e519cc30 INFO "Bytes differ from the source because Microsoft 365 rewrites Office files on upload, so treat totals as indicative. 'Verify files arrived' is the definitive per-file check."
    if ($script:GuiMode) {
        if ($tMissing -gt 0)   { Write-Host "##CHECKOUTCOME##|WARN|found a problem: $('{0:N0}' -f $tMissing) file(s) in Datto are NOT at the destination, so some files may not have migrated. They are named in the log below and in the difference CSV.$(if ($tExtra) { " (The destination also holds $('{0:N0}' -f $tExtra) extra file(s), usually pre-existing content.)" }) Click 'Sync new and changed' to copy them, then compare again." }
        elseif ($tExtra -gt 0) { Write-Host "##CHECKOUTCOME##|WARN|counts differ: the destination holds $('{0:N0}' -f $tExtra) file(s) that are not in Datto ($('{0:N0}' -f $tDstC) vs $('{0:N0}' -f $tSrcC)). That is normal if the destination already held content before the migration - is that expected? 'Verify files arrived' checks file by file and ignores extras." }
        else                   { Write-Host "##CHECKOUTCOME##|OK|every file matches by path: $('{0:N0}' -f $tSrcC) file(s) at both ends." }
    }
    try {
        $emVerdict = if ($tMissing -gt 0 -or $tExtra -gt 0) { 'WARN' } else { 'OK' }
        $emBucket  = if ($emVerdict -eq 'OK') { 'Success' } else { 'Warning' }
        $emDiffs = @()
        try { $emDiffs = @(Get-ChildItem (Join-Path $Config.run.reportRoot 'sizecheck-diff-*.csv') -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $ckStart } | ForEach-Object FullName) } catch {}
        $emVars = Get-EmailScopeVars -Config $Config
        $emVars['EndTime'] = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        $emVars['Duration'] = ('{0:hh\:mm\:ss}' -f ((Get-Date) - $ckStart))
        Send-RunEmail -Config $Config -ActionKey 'SizeCheck' -ActionLabel 'Compare sizes' `
            -OutcomeBucket $emBucket -OutcomeLabel $emVerdict -Vars $emVars `
            -AttachPaths (@("$script:LogFile") + $emDiffs) `
            -BodyLines @(
                "Action: Compare sizes",
                "Outcome: $emVerdict",
                "In Datto: $('{0:N0}' -f $tSrcC) file(s)",
                "At the destination: $('{0:N0}' -f $tDstC) file(s)",
                "Missing at destination: $('{0:N0}' -f $tMissing)",
                "Extra at destination: $('{0:N0}' -f $tExtra)",
                "Source: $($emVars['Source'])",
                "Destination: $($emVars['Destination'])")
    } catch {}
}
$script:LiscaraghLogoB64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEBAQFBQQFBwsHBwYGBw4KCggLEA4RERAOEA8SFBoWEhMYEw8QFh8XGBsbHR0dERYgIh8cIhocHRz/2wBDAQUFBQcGBw0HBw0cEhASHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBz/wAARCACnANwDASIAAhEBAxEB/8QAHQABAQADAAMBAQAAAAAAAAAAAAEGBwgCBQkEA//EAE4QAAECBQIEAwIICgcECwAAAAECAwAEBQYRBxIIITFBE1FhIoEUGSMyVnGU0gkVFkJSVHKRk9EXGDVDgpXTRGJ0sjc4Y3N1kqGisbO0/8QAGwEBAAIDAQEAAAAAAAAAAAAAAAIDBAUGAQf/xAAvEQACAgECBAQGAQUBAAAAAAAAAQIDEQQhBRIxUUFhgZEGExQiMnFyQmKhscHx/9oADAMBAAIRAxEAPwD5/wAIQgBFiResAWEQQxACGYGEAMwiQgBFiQgBCEWAEMQi+6AJiGIQgBFiQgAYCLEgBFhEgCx4xYkAIsSLAEhCEAIsMQgBCESALCEIARIQgBCEXEAMZPKLgx3JwWcLVBvy26jel+0dNQpk4oy1KlHVrQlQSr5R/wBkgn2hsTz7L5dI/fxlWDo5ozZUrTLds2QYvCuKxLuB95SpVhJHiO4KyMk4QnI7qP5sAcdac2O7fVe+BeKWZNhHizLyRkpRnGB/vE8h+/tHRDej9mNyfwY0ZKxjBdU8vxD67s9fdGCcM1Nqc4/dczK0596nyksy7NTKE5Qx8oQkK+vJ/wDKT0Eb0Mcdx3W6mvU/LhJxiksY2yfQvhnh+kt0fzZwUpNvOd8eX/TkvVHT42JVmRLurepk4Cpha/nJI+chXmRkc+4MYHG9OIiuSrzlJozS0rmpcrfeA/u9wASk+pAJx9UaLjo+GW2XaWE7erOQ4zRTRrbK6PxT9tt16MZhFiGM41ghAQzzgBCJ3iwAiRe8SALiHuhD3wBIQhACLEiwAhDOId4ARIsSAEIQgCxn+jGl1R1i1Eo9qU/chM0vfNTCRkS0unm44fqHIeaikd4wDEfVLgb0R/o407/Kqqy3h3FdCEPbVpwqXlOrSPQqzvP1pB+bAHQyE0DS6xgkFqm23b0h1PzWWGkf+pwPrJ9THxv1k1LquuOqFSuF1p5RnnhL0+SHtKZYB2tNADqrnk46qUT3jsD8INreJeWldLqPM/KvhE5WFIPzUdWWD9Zw4R5BHmY1/wABGiH5X3i7qBV5bdR7dc2SSVp9l6dxkK9Q2khX7SkeRgDtDhq0WltGNLJCiTDLaq1PD4XVnMA731jm36pQnCB2OCe8cLcXGr0pJanz1u6fpYpcjSQZaemJNIHwmaz7YHUJCPmezj2gr0jt7io1qRorpdOz0o8lNx1TMlS0d0uke07jybT7Xlu2jvHx1ddW+6t11aluLJUpazkqJ6knuYrsqrs/OKf7RbVfbTn5cnHPZ4Dzzsy6t55xTjqyVKWsklRPck9Y8IsTMWFT3EDCGIAkIRcZgCCLDvCAHeJFhAAQhDlAEhCLAEixIQAhCEAIQhACEI/tKyz07MNS0u0t195YQ22gZUtROAAO5J5QBvbhJ0UVrJqjKtz0uXLZom2dqZI9lwA/Js/41DBH6KVx9StWNR6XpFp7WLpqW3waez8jLg4Mw8eTbSf2lYHoMntGJ8M2jLOiel1PpDzaPx9OYnKq6nnufUB7APdKBhA+onvHD/Hfrd+Xd+IsmkzO+g2y4pL5QrKX50jCz6hsZQPUr84A58lJe5tcdT0NBSp65rnqGSo/N3rOST+ihIyfIJT6R9ltNrEpGktgUi2aaUNyFKl8LfXhPir+c46s9ipRUo+WfIRyP+D80PNLpczqdWJfE1UEqlaQhY5oYzhx4ftkbQf0Uq7KjLePDXD8hbGRY9JmNteuZtQmFIV7UvJZws+hcOUD0C/SAOLOKfWpzWrVCdnpV5Rtyl7pKlI7FoH2ncebiva88bR2jSIh1hADEWJH66fTJyrTSJWQlXpqZX81tlBUo+4R42kss9ScnhdT8ggY99WLLuCgMB+pUiclmD/eONnaPrI5CPRHIjyE4zWYvKJWVzrfLNNPzJiJzixYkQJCGYQA7xIuecIAQiRfdAEhCEAIQhACEIQAhCEAI7I4B9EfyvvN6/6tLbqNbrm2SCx7L06RkH1DaSFftKR5GOVLLtKp33dVItujM+NU6pMIl2UdgSeaj5JAyonsATH2v02sOkaS2BSLZppQ3IUqXwt9eE+Kv5zjqz5qUVKPl9QgDAeKnWlGiuls7PSjyU3HVMyVLRnml0j2nceTafa8t20d4+X+helVQ1u1Ppdutrd+DvLMzUpvqpmWSQXFk/pHISM9VKEZBxS60ua1aozs/KuqVbtM3SVKR2LQPtO483Fe1542jtHrNGeIa6NC2qoLXkKIt+plHjzM9Kqdd2pztQCFpwnJJx3J9BgD7LUikydCpUlS6dLolpCSZRLsMNjCW20gJSkegAAjSOoXCHp5qfdk/c9xqrczVJ3aFFNQKUISlISlKE7fZSAOnqT3jiz4wrVv9Vtj7A5/qw+MK1a/VbY+wOf6sAdWf1BNH/1auf5kfuw/qCaP/q1c/wAyP3Y5T+MK1a/VbY+wOf6sPjCtWv1W2PsDn+rAHVn9QTR8f7NXP8yV92NLVPTi2dMrqr1HtiSeYlGZjwiuYdLrq9qRnKyByzkgRrv4wnVo/wCzWx9gc/1Y9bSOJP8ALeuT05eaZKQqE2sLExJsqQwr2QMKTlRSeWc9D6RpuOU3W6bFO++6XijofhnUaejWc17SysJvwf8A4bPeZbmGXGXm0OMuJKVtrGUrSeoI7iON79obNt3fV6ZLEmXl3j4YJyQkgKA9wOPdHStd1ZtWiSS30VRief25bl5RW9Sz2BI5JHqY5YrtYmLgrE7U5ojx5t1TqgOgz2HoByjX/DunvrlOU01F9+5tvi3Vaa2FcK5KU0/DfCPXZiwhHUnEEhCEATpCEIARYQ5wBIQhACEIQAhFiQAixI/pLrbbfbU62XGkqBUgK27hnmM9s+cAfQ/8H3oh+LaXNan1iXxNT4XKUhKxzQyDh14eqiNgPklXZUdfal2U5qLZNWthNYnKQ1VGvAempNKS74RPtoG7kNycpJ8iY4Do/wCEPrFApUlSqZp7Q5WnSLKJeXYam3QlttACUpHLoABH7fjJrl+g9H+2O/ygDYvxblm/TG4P4TH3YfFuWb9Mbg/hMfdjXXxk1y/Qej/bHf5Q+MmuX6DUj7Y7/KANi/FuWb9Mbg/hMfdh8W5Zv0xuD+Ex92NdfGTXL9B6P9sd/lF+MmuX6DUj7Y7/ACgDYnxblmfTG4P4TH3YfFuWb9Mbg/hMfdjXXxk1y/QakfbHf5Q+MmuX6D0f7Y7/ACgDYnxbtmfTG4P4TH3Y4z4iNPLT0q1BftS1qzP1ZVObCZ+Ymg2AiYPMtp2DntSRkn84kdo6Cm/wkV1uyr7cvZtHYfWhQbdMy6vYrHJW0jng88RxZUJ+aqs/Mz06+5MTk06p555w5U4tRJUonuSSTAH54dIRYAkIGEASLmHaJACEXyiQBYRIogCQhCAKAT0EI7W4DNJbK1Mp18uXbbslV1yL0mmXMyFHwwsO7sYI67R+6OTdRJCWpWoF1SMkyhiTlarNsstI+a2hLyglI9AABAGOAZPKJgjkY25wwWxSLy13s6h16Qan6TOvPJflXs7HAGHFDOCDyIB90bQ4sNHqJSeIK1LJsikSlIbrUlJtIZa3eGX3ZhxverJJ6BOfQQByngnnDbiPpJddgcOnClRqJK3fbb9y1qooUQ6/LfCnX9mAtexSg22nKhgDnz74JjUOsFzcMN56YVuqWhQl0e85cITJSbTK5NxSlKAyUgqaWgDJOOfLtmAOOekMHyMdKcKfC6vXeoTlYrUy/JWfTHQ06tjAdm3sBXhIJBCQAQVKwcbgAMnI6BrN38IOnNTdtc2vI1NyVV4D80xILnUtrHI5fWrKiO5RmAPnV0hHVXFLY2hdLt2h3NpjXm0T9YVvTSZRxT7KmRkKcIWd7BChjarqcgJGCY1lwz6Uf0wau0OhTLRco7CjPVLqB8GbIKkkjpvJSj/HAGoyCPSJH0o4j+GXTyo6RXLU9OKDTpSv2y+Xpj8XlRUoNJy+woEnmELC8dcpHnHzYgBtPkYYI6x9TdQ9OOHrR6xqRct12DKGUnFsyoVKy7jqy6tor5jeOWEK5xiFoafcLvEgzUaJaFLdpFel2C8PADsrMNozjxEpUpTbgBIBHPGR0zmAPm/FAJMZlqvp3P6Uag120Ki4l6Ypb2xL6U7Q82pIU2sDtuQpJx2JI7R1bwa6B2fXLCuTUPUimyUzQwosyZnyUtNNtc3niQRy3EJB7bFQBxAQR1hHVPG7oTTNKbwpFatimtyNsVtjYGGc+GxMt4CkjJOApJSoeu+NM6K6RVfWy/ZK16StLAWkvzc2tO5MqwnG5wjueYAHcqAyOsAa8wYpyI+kVxWhwv8ADK1KUa56WivXEtoOOImmTPTKkn89SMhtoHsOWfXrGG31R+FTU3Tau3JQZtu1apS28hEo0pmYLivmI+CKO10KPLKMY7qTiAODgCe0POOvuA/S60NTKxezN2UGUq7UlLyqmEzIV8mVLcCiMEdcD90c9az0WSt/Vu+KTTJVErTpGszcvLsN52ttpdUEpGewAAgDBsEjocRI724f9GbDujhUuC6Kxa8hOXBLMVRTc66FeIkttqKDyOORAxyjgowAxCEIAkIQgD6F/g0v7J1H/wC/kP8AlejiLVT/AKTr1/8AGZ3/AO9cdRcCus1i6UU+92rxuBmkrqLsmqWDjLq/ECEu7vmJVjG5PXzjOaxT+C+u1afqk7XSucn33Jl5YfqCQpa1FSjgJwOZPKAOaeDn/rKWF/xEx/8Amdja3HnW522eIy161TnfCqFNpMnNS7mM7XETDyknHfmBH5JWvaH6bcTunlcsKsJasuSl3XKlNrMy6Gn1IfQOTid/Qt9ARz+uPWcUmqun9+8QNqXNJTS7itKRkpVufblUKaU6EPurW0PESOqVD059YA3XJcX2ims9BkqXq5awlJtrmVvypmpdCyMKU04j5VvP1cvM4zHrNRODrTS/NPJ69dGq0csMuPtSqJozMrM7BlTQKvbbcwDjJPPAIGchUUcHerDiqu7PC2Ki+d77LXiyByefNG1TWfVEfoujiQ0e0L0pqdk6PuOVSozyXQl5IcU0266nap9x1wDeoJAwlII9kDkIAy/hoEw9wS1VFsE/j8ydXSnwvn/CvlNmMfnbfDx7o+YxzmOi+Fjief0Gq03TqpLPz9n1RxLkwwwR4ss6BjxmwSASUgBSSRnA5gjn0TW5Xg61GqLlzzdWlKfNTKi9NS7T0zJeIsnJ3MhPUnrsxmAPnZgmPplwN6ZzVhaOVi+vxYqcuC4kLekpXIQtyXaCvCbBUQE+IvcckgYKD2jSeu2pWhF9Is+wrPpEtTqTTpxtty5hLrYRJSpVl1KE4LjxVzOVj53MZJJjMuI7jAplFty1Ld0QuYMtSoxMzMrKlIYZbQENMAPI6HmTgfmDnzgDZPCPZ+rlnXJfLGo1uusUu5XVVUzLk0w6gThVhxJShajhaVeWPkwI4U4jdLVaQ6u3BbzbakUxTnwunEjkqWcypAHnt9pB9UGMjpfGVrNI1KTmX70mZthh5Di5Z2XYCHkhQJQohvOCOXLnzjb3GVqXpVrRZlu3BbNyS7l3U0hC5FUu8h1cu6AVNlRQElTa8HrjmvEAdV686JTmvOk9vW3JVdiluy8xLTxefZU6lQSwtO3CSOftg59IwDQnhbpPDFUKvqBdV5S8wJWScZLngGXl5ZtRSVLUVKJUo7QAOXXuSI1XxbcQNiX5ozbtFs66xOVqVqEs68yw2+ypLaWHEqO5SUggKUkYzHqOFbietqQsms6b6tT4NuLZcEnNTaHH0qac5OSy9oUrHMqSe2VDIwmANH6wXM5xF8Qs/N21LLUmuzrEhTkLSUqWhKUtIWods7d5z0B59I7w1/0tu6R4eqHpbpfQnai2QzKTjiH2mcS7Y3qJ3qTlTjmCcf72escxcO8xo7pRrpcdwVS/JKZoNKbKbfmlSr5U8XsgqUkN5Cm0ZQcgAleRHp9XONHUOqai19+ybtmafaqZgtU9luXawppACQ57aCrKyCvB6bsdoA63uLSq6tWeExm1rxpC5O/KVJhUuhx1t1S5mWyGlhSCR8q2Np59VmNG/g2kyjd0agNvAJqQk5UNpVyUGw4vxOX7Xh590eq4bONOvyl9PSuq12OTNtzkqtKJp+WTiUfT7SVfJI3EKAUnoeZTGA3fqxRdIeJScv7SmrytXoVRUZl6WQhxptSXT8vLqCkggbxvSQMDKeuCIAwDiZbqrWvmoIrHifCzVnlJ355sk/I49PC2Y9MRs7hn4WaNrnYtfuCpV+o056mTipZLUsy2tK0hlK8kq55yoj3Rvuv6ocL3EfLSlSvRz8T3Cy2EFc34stMIT+h4zYKHEgk4yT9QzHk1xD6AcPFj1OhabqmazNThW6qXlVPLS48UBAU4+7gAYA+YD06QBhP4NT+3tQv+Fkv+d2M3v2/OFCRve45a5bZQ9cLNQfRUHTTH1b5gLIcO4KwcqzzHWNKcC+rdmaU1e9H7wrrVJan5eVRLqcacX4hQtwqA2JVjG4dfOOfdY65IXLqxe1YpUyJmm1CsTczLPpBAcbW6opVggEZBB5iAPqRbdWsCs8Nl4TemsiJK2DTamlDIYWz8qGV7ztUSeuI+QJ6x3ZoHrrp7aPCzX7RrVysSdxTTFTQ1JKYdUpRdbUG/aSgp5kjvHCZ6wBYmYZiwB4whFgBkjvDJ84kIAuT1zDrEj+su54Lzbm0K2KCtquhwcwCM5pGjt31mRbnGKcG2XEhSA+6ltSweh2nn+/EYvWbcqlAqhplQlHGp8bcNZCird0xjOcxu2sVm1NU1yDyLonKFVG0BtMs4SlsKJz6JJycZBGRiPCybOnqNq6EXFNioTSJJUzLTS1FRcxhAVz5gpGeXbEaaPEbIRlK/ZpN8uGnt59H6HR2cIpslCGmbabS5sprfulun2TMCldEr0mpMTKaWlvIyGnX0Jc/cTy9+Iw96g1KUq6aRMSrrFQU6lrwXRtO5RwOvY569IyS7ryuM3jUZhyozktMS0ytDbbbqkhkJUQEhPTHL3xtDUNIqCNNKzONJarEw+wl4YwSDsURj0Ufdui1am+uUFdhqecYzs0s9917FD0WlujY6OZOtrOcbpvHbZ+W5r3+g69snFLQceUy3/OPzy+jt4TcxOS7VNQp2TWlt4fCEDapSQod+fIiNs6j2vL1a5lzDt9y1EX4KE/BHHCkjGfaxvHX6o0bPzU5SbhmpSWrj0203MBHwpl5QS+AQArrz5esQ0eqv1MOZSWcZ/GX+87+hZr9DpdHbyyhLGcZ5o7+mMr1Pfr0SvRtC1mlt7UAqJEy2eQGfOMcrVnVigUyn1Kel0pkagkKYdQ6lYVlIUOh5cj3jZ/EDUZySuClIl5uYZQuSypLbqkgnerqAY8qA0u/NFpultpLtSorwLKeqiM5SPelSx7o8q1t/ya9Rbjlk0nhPZPbv3wSv4bpnqLdLTzc0U2stPLWHjovDJrFFkVxy11XIJTNIScF3xE5+dtztznGeWY/lRLPq1wSFRnpFhKpSnI3zDq3UoCBgnuefIHpHSjSqc1MNaZkIKTRCCv8A7Tv7+q411V2F2Fos3TXU+HVK7NK8VPRQQDz/APahI/xRGridln24WXJcv8X4+yZK7g1VS53JuMYvm/msbe7X+TV9s2lVrvnHZWky/jPNN+KvcsICU5A5k8upj19Upc1RajM0+daLU3LLLbiCc4I9e8b2sehVq19L36jRZB6YuGsrQtsNpBLbIPsk57YCj/iEem14ttxSqVdKZVcuZ5tLM2yoYLToTlOfXGU/4Ytq4jz6p1bcrbS75XX064/RRdwj5eiV+/Okm+2HnGPNbN/sxGnaPXfVJGVnpSnIXLzLaXW1fCEAlKhkHGciMfuO0K1aj6GqxIOyqnMlClYUleOuFDIMb5rNq126tO7KZoUylh5iVQpwqmC1kFtIHMdeYj0OqC1UHTOj25Wp9E9cXih7cFFakIG7nk88YITk9cHyimjiNk7IxbTzJrCzlJZ36+RkarhFNVMppSWIp8za5W3jbou/cwxrRK9XW0ON0xBQtIUCJlvoRkd4xi57Qq9nzbMrWJcMPvN+KhIcSvKckZ5HzBjoHUaWocwzQDWLqnKIsSg8NEuhSg6MJyTjy6RoG8ESLVZW3TaxMVeSQhOyafCgokjJGD5GLtBq7tRiU+m/9L7984Mfiug0+kTjXnO2/NF+GfxSyj0HSEBCNqaIZPnEixIAohEiwBIQhACLEiwBI/qy4GnUOFCVhKgdi+isdj6R/KLAG3f6U7UnnETlSsOTcqKcHey4EoUR3Ix/85jGa9qfWKvd0tcbJRJzEoAiXaR7SUI55Sc/Ozk588xhMSMSGipg+ZLPhu29n+zPt4nqbI8rljfOyS3XRvCRuResVu1B5FRqlkSkxWUAfLhadqlDoeaSf35jDbg1FqFz3RIVmfQnwpF1C2ZVo4ShKVBRAJ7nHMmMNhiFWhoqfNFeXVvC8s9PQXcT1N0eWcts52SWX3eFv6mV6hXgi+LiVVW5QyqS0hrw1L3n2c884HnGLtL8J1CyM7VA4+qPDEIyK641wVcFstjFtundY7ZvLbyzNdSr8bv6pyc43IqkxLseDtU6F7vaJznA848tNtQVWBUJx5Uoqbl5toNraS5sO4HKVZwenMe+MIhFX0lXyfp8fb2Lvrr/AKj6rm+/rkzNWoMydRBdwZIWJgOfB9/93jb4ecfo8s4j9OoOoiL8q1NfckXJeRk07Sx4wUpWVZUd2BgkADp2jA4QWkpU42KO8Vhfo9evvdc6nLaTy/Nmxbw1bqtcnJVVHdm6NIyzIaRLy8weeO5Ix2wB9USW1SfmrNqlvV5mYqhmlb2ZpyY9tlXIjqDnChnr3IjXkSIrRUKKio9N139+pJ8S1LnKbnvJYfbD26dDOrn1CFfte3aMzJuSzlIQE+OHs+IQgJyAAMdM9Y87w1CZvO36ZLz9OUK5IjZ+MEujDqe4UnHfkevXPnGBQiUdJVHlaXRtr16+5GevvmpKUsqSSfTount36m5Z/WS36yzJoq1ltzy5VoNtqemQdowM49nviMBvO4KNX5iUco9Aao7bSFJcQ2vd4hJyD0HQcoxiHeI06Oql5ryvV49s4JajiN+oi42tPP8Aas7eeMgGEDCMowSQixIARYkX3QBIQhACEIQAhCEAXMMwhACGYQgBEhCALmEIQAzCEIAZhmEIAQhCABhmEIAkWEIAkIQgBFhCAP/Z'
function Invoke-HtmlReport {
    param($Config, [string]$AuditPath, [switch]$NoStageLog)
    if (-not $NoStageLog) { Lzffe69bba89 -Config $Config -Stage 'api-report' }
    if (-not $AuditPath) {
        $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $AuditPath = $latest.FullName }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) { Lz12e519cc30 ERROR "No audit CSV found in $($Config.run.reportRoot). In plain terms: there is no record to build a report from yet. Run an upload first, then build the report."; return }
    $rows = @(Import-Csv $AuditPath)
    $endRow = @($rows | Where-Object { "$($_.Status)" -like 'RUN_END:*' }) | Select-Object -Last 1
    $rows   = @($rows | Where-Object { "$($_.Status)" -notlike 'RUN_END:*' })
    if (-not $rows.Count) { Lz12e519cc30 WARN "Audit CSV is empty: $AuditPath"; return }
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    function Lz8067f5c42c { param($st) @($rows | Where-Object { $_.Status -eq $st }).Count }
    function _sumBytes { param($items) $a = @($items); if ($a.Count) { [int64](($a | Measure-Object SourceSizeBytes -Sum).Sum) } else { [int64]0 } }
    $brand = 'Datto Workplace to SharePoint Migrator'
    $logoTag = ''
    if ($Config.run.PSObject.Properties.Name -contains 'report') {
        if (($Config.run.report.PSObject.Properties.Name -contains 'brand') -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
        if (($Config.run.report.PSObject.Properties.Name -contains 'logo') -and $Config.run.report.logo -and (Test-Path $Config.run.report.logo)) {
            try {
                $lb = [System.IO.File]::ReadAllBytes($Config.run.report.logo)
                $ext = ([System.IO.Path]::GetExtension($Config.run.report.logo)).TrimStart('.').ToLower(); if ($ext -eq 'jpg') { $ext = 'jpeg' }
                $logoTag = "<img class='logo' alt='logo' src='data:image/$ext;base64,$([Convert]::ToBase64String($lb))' />"
            } catch {}
        }
    }
    $total = $rows.Count
    $copied = (Lz8067f5c42c 'Copied') + (Lz8067f5c42c 'ZeroByte')
    $skipped = Lz8067f5c42c 'Skipped'
    $errors = (Lz8067f5c42c 'Error') + (Lz8067f5c42c 'DownloadError') + (Lz8067f5c42c 'SkippedTooLarge')
    $verifyFail = Lz8067f5c42c 'VerifyFail'
    $wouldCopy = Lz8067f5c42c 'WouldCopy'
    $retried = @($rows | Where-Object { [int]$_.Retries -gt 0 }).Count
    $copiedBytes = _sumBytes (@($rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' }))
    $dryRun = ($wouldCopy -gt 0 -and $copied -eq 0)
    $wouldCopyBytes = _sumBytes (@($rows | Where-Object { $_.Status -eq 'WouldCopy' }))
    $moveBytes = if ($dryRun) { $wouldCopyBytes } else { $copiedBytes }
    function _estAt { param([double]$mbps) if ($mbps -le 0 -or $wouldCopyBytes -le 0) { return '&mdash;' } Format-Duration ([TimeSpan]::FromSeconds(($wouldCopyBytes * 8.0) / ($mbps * 1000000.0))) }
    $times = @($rows | ForEach-Object { try { [datetime]::Parse($_.TimestampUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch {} } | Where-Object { $_ })
    $elapsed = if ($times.Count -ge 2) { ($times | Measure-Object -Maximum).Maximum - ($times | Measure-Object -Minimum).Minimum } else { [TimeSpan]::Zero }
    $elapsedStr = Format-Duration $elapsed
    $mbPerMin = if ($elapsed.TotalMinutes -gt 0) { [math]::Round(($copiedBytes / 1MB) / $elapsed.TotalMinutes, 1) } else { 0 }
    $mbitsPerSec = if ($elapsed.TotalSeconds -gt 0) { [math]::Round(($copiedBytes * 8 / 1000000) / $elapsed.TotalSeconds, 1) } else { 0 }
    $diagSection = ''
    if (-not $dryRun) {
        $diag = $null; try { $diag = Lz34a335c621 -Rows $rows -Elapsed $elapsed } catch {}
        if ($diag) {
            $diagSection = @"
<h2>What limited this run</h2>
<div class='diag'>
  <div class='dv'>$(_enc $diag.Verdict)</div>
  <p>$(_enc $diag.Why)</p>
  <p class='dim'>$(_enc $diag.Action)</p>
  <table><tbody>
    <tr><td>Overall throughput</td><td class='n'>$($diag.AggMbps) Mb/s</td></tr>
    <tr><td>Single-file speed (typical)</td><td class='n'>$($diag.PerStreamMbps) Mb/s</td></tr>
    <tr><td>Uploads at once (average)</td><td class='n'>~$($diag.EffConcurrency)</td></tr>
    <tr><td>Average file size</td><td class='n'>$(Format-Bytes ([int64]$diag.AvgFileBytes))</td></tr>
    <tr><td>Files that hit a backoff/retry</td><td class='n'>$($diag.RetriedCount) ($($diag.RetryPct)%)</td></tr>
    <tr><td>Time uploading vs downloading</td><td class='n'>$($diag.UpSec)s / $($diag.DlSec)s</td></tr>
  </tbody></table>
  $(if ($diag.Projection) { "<p><b>Planning:</b> $(_enc $diag.Projection)</p>" })
  $(if ($diag.Headroom)   { "<p><b>Headroom:</b> $(_enc $diag.Headroom)</p>" })
</div>
"@
        }
    }
    $readySection = ''
    if ($dryRun) {
        $wc = @($rows | Where-Object { $_.Status -eq 'WouldCopy' })
        $estRows = ''
        foreach ($r in 50,100,200,500) { $estRows += "<tr><td class='n'>$r Mb/s</td><td class='n'>$(_estAt $r)</td></tr>`n" }
        $spLimit = 250GB; $bigMark = 15GB
        $tooBig  = @($wc | Where-Object { [int64]$_.SourceSizeBytes -gt $spLimit } | Sort-Object { [int64]$_.SourceSizeBytes } -Descending)
        $bigSlow = @($wc | Where-Object { [int64]$_.SourceSizeBytes -gt $bigMark -and [int64]$_.SourceSizeBytes -le $spLimit } | Sort-Object { [int64]$_.SourceSizeBytes } -Descending)
        $bigBits = ''
        if ($tooBig.Count) {
            $tr=''; foreach ($x in ($tooBig | Select-Object -First 300)) { $tr += "<tr><td>$(_enc $x.Space)</td><td>$(_enc $x.SourcePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SourceSizeBytes))</td></tr>`n" }
            $bigBits += "<details open><summary style='color:#b00000'><strong>$($tooBig.Count) file(s) over the SharePoint 250 GB per-file limit</strong>: these cannot be uploaded and need another home &middot; click for details</summary><table><thead><tr><th>Project</th><th>File</th><th class='n'>Size</th></tr></thead><tbody>$tr</tbody></table></details>"
        }
        if ($bigSlow.Count) {
            $tr=''; foreach ($x in ($bigSlow | Select-Object -First 300)) { $tr += "<tr><td>$(_enc $x.Space)</td><td>$(_enc $x.SourcePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SourceSizeBytes))</td></tr>`n" }
            $bigBits += "<details><summary>$($bigSlow.Count) large file(s) over 15 GB: these will upload slowly and may need retries &middot; click for details</summary><table><thead><tr><th>Project</th><th>File</th><th class='n'>Size</th></tr></thead><tbody>$tr</tbody></table></details>"
        }
        if (-not $bigBits) { $bigBits = "<p class='okbox'>No file is over 15 GB, so none is close to the SharePoint 250 GB per-file limit.</p>" }
        $readySection = @"
<h2>Migration readiness</h2>
<p class='dim'>This is a preview: nothing has been copied. It shows what a full run would move, roughly how long it would take, and anything worth dealing with first.</p>
<h2>Estimated time</h2>
<p class='dim'>$(Format-Bytes $wouldCopyBytes) to move. The real time depends on your internet upload speed and Microsoft 365 throttling, so treat this as a planning guide, not a promise.</p>
<table style='width:auto'><thead><tr><th class='n'>Sustained upload</th><th class='n'>Rough time</th></tr></thead><tbody>
$estRows
</tbody></table>
<h2>Large files</h2>
$bigBits
"@
    }
    $destBySpace = @{}
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (Test-Path $mapPath) { foreach ($m in Import-Csv $mapPath) { $destBySpace[$m.Space] = $m } }
    $spaceRows = ''
    foreach ($g in ($rows | Group-Object Space | Sort-Object Name)) {
        if ($dryRun) {
            $sc = @($g.Group | Where-Object { $_.Status -eq 'WouldCopy' }).Count
            $sb = _sumBytes (@($g.Group | Where-Object { $_.Status -eq 'WouldCopy' }))
        } else {
            $sc = @($g.Group | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' }).Count
            $sb = _sumBytes (@($g.Group | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' }))
        }
        $ss = @($g.Group | Where-Object { $_.Status -eq 'Skipped' }).Count
        $se = @($g.Group | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'DownloadError' -or $_.Status -eq 'VerifyFail' }).Count
        $dest = ''
        if ($destBySpace.ContainsKey($g.Name)) { $d = $destBySpace[$g.Name]; $dest = if ($d.DestinationType -eq 'OneDrive') { "OneDrive: $($d.TargetPrincipal)" } else { (@("$($d.DestinationUrl)", "$($d.TargetLibrary)", "$($d.TargetSubFolder)") | Where-Object { "$_".Trim() }) -join ' / ' } }
        $seCell = if ($se -gt 0) { "<td class='n err'>$se</td>" } else { "<td class='n'>0</td>" }
        $spaceRows += "<tr><td>$(_enc $g.Name)</td><td class='dim'>$(_enc $dest)</td><td class='n'>$sc</td><td class='n'>$ss</td>$seCell<td class='n'>$(Format-Bytes $sb)</td></tr>`n"
    }
    $detailSections = ''
    foreach ($g in ($rows | Group-Object Space | Sort-Object Name)) {
        $moved = @($g.Group | Where-Object { $_.Status -ne 'Skipped' -and $_.Status -ne 'WouldCopy' })
        if (-not $moved.Count) { $moved = @($g.Group) }
        $fileRows = ''
        foreach ($p in ($moved | Sort-Object SourcePath)) {
            $sz = [int64]$p.SourceSizeBytes
            $ums = 0.0; try { $ums = [double]$p.UploadMs } catch {}
            $spdCell = if ($ums -gt 0) { "$([math]::Round(($sz * 8 / 1000000) / ($ums / 1000), 1)) Mb/s" } else { '' }
            $stCls = if ($p.Status -eq 'Copied' -or $p.Status -eq 'ZeroByte') { 'dim' } else { 'err' }
            $mod = ''; try { $mod = ([datetime]$p.SourceModifiedUtc).ToString('yyyy-MM-dd') } catch {}
            $fileRows += "<tr><td>$(_enc $p.SourcePath)</td><td class='n'>$(Format-Bytes $sz)</td><td class='$stCls'>$(_enc $p.Status)</td><td class='n'>$([int]$ums) ms</td><td class='n'>$spdCell</td><td class='dim'>$(_enc $mod)</td></tr>`n"
        }
        $detailSections += "<details><summary>$(_enc $g.Name) &mdash; $($moved.Count) file(s) &middot; click for details</summary><table><thead><tr><th>File</th><th class='n'>Size</th><th>Status</th><th class='n'>Upload time</th><th class='n'>Speed</th><th>Modified</th></tr></thead><tbody>$fileRows</tbody></table></details>`n"
    }
    $probs = @($rows | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'DownloadError' -or $_.Status -eq 'VerifyFail' })
    if ($probs.Count) {
        $probRows = ''
        foreach ($p in $probs) { $probRows += "<tr><td>$(_enc $p.Space)</td><td>$(_enc $p.SourcePath)</td><td class='err'>$(_enc $p.Status)</td><td class='dim'>$(_enc ($p.Reason + $p.Error))</td></tr>`n" }
        $probSection = "<h2>Files needing attention ($($probs.Count))</h2><table><thead><tr><th>Project</th><th>File</th><th>Status</th><th>Detail</th></tr></thead><tbody>$probRows</tbody></table>"
    } else {
        $probSection = "<p class='okbox'>No errors or verification failures. Every file was accounted for.</p>"
    }
    $copiedRows = @($rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' })
    $dlSecTotal = [math]::Round((@($rows | ForEach-Object { [double]$_.DownloadMs }) | Measure-Object -Sum).Sum / 1000, 0)
    $upSecTotal = [math]::Round((@($rows | ForEach-Object { [double]$_.UploadMs }) | Measure-Object -Sum).Sum / 1000, 0)
    $extRows = ''
    foreach ($eg in (($copiedRows | Group-Object { $x = ([System.IO.Path]::GetExtension($_.SourcePath)).ToLower(); if ($x) { $x } else { '(none)' } }) | Sort-Object { _sumBytes $_.Group } -Descending | Select-Object -First 14)) {
        $extRows += "<tr><td>$(_enc $eg.Name)</td><td class='n'>$($eg.Count)</td><td class='n'>$(Format-Bytes (_sumBytes $eg.Group))</td></tr>`n"
    }
    $hasFlag = ($rows.Count -and ($rows[0].PSObject.Properties.Name -contains 'Renamed'))
    if ($hasFlag) { $renamed = @($rows | Where-Object { "$($_.Renamed)" -eq 'True' }) }
    else { $renamed = @($copiedRows | Where-Object { $_.DestPath -and ((($_.SourcePath -split '/')[-1]) -ne (($_.DestPath -split '/')[-1])) }) }
    $longPaths = @($copiedRows | Where-Object { $_.DestPath -and $_.DestPath.Length -gt 300 })
    $zeros     = @($rows | Where-Object { $_.Status -eq 'ZeroByte' })
    $collisions = @()
    foreach ($g in ($copiedRows | Where-Object { $_.DestPath } | Group-Object { $_.DestPath.ToLowerInvariant() })) {
        $srcs = @($g.Group | ForEach-Object { $_.SourcePath } | Sort-Object -Unique)
        if ($srcs.Count -gt 1) { $collisions += [pscustomobject]@{ Dest = $g.Group[0].DestPath; Sources = $srcs } }
    }
    $qualityBits = ''
    if ($collisions.Count) {
        $cr=''; foreach ($x in ($collisions | Select-Object -First 300)) { $cr += "<tr><td>$(_enc $x.Dest)</td><td>$(_enc ($x.Sources -join '  |  '))</td></tr>`n" }
        $qualityBits += "<details open><summary style='color:#b00000'><strong>$($collisions.Count) name collision(s)</strong>: different Datto items share one destination path &middot; click for details</summary><table><thead><tr><th>Destination path</th><th>Datto sources that collide</th></tr></thead><tbody>$cr</tbody></table></details>"
    }
    if ($renamed.Count) {
        $rr=''; foreach ($x in ($renamed | Select-Object -First 300)) { $of = if (($x.PSObject.Properties.Name -contains 'RenamedFrom') -and $x.RenamedFrom) { $x.RenamedFrom } else { $x.SourcePath }; $rr += "<tr><td>$(_enc $of)</td><td>$(_enc $x.DestPath)</td></tr>`n" }
        $qualityBits += "<details><summary>$($renamed.Count) name(s) tidied for M365 (illegal characters or trailing spaces removed) &middot; click for details</summary><table><thead><tr><th>Original path</th><th>Stored as</th></tr></thead><tbody>$rr</tbody></table></details>"
    }
    if ($longPaths.Count) {
        $lr=''; foreach ($x in ($longPaths | Select-Object -First 300)) { $lr += "<tr><td>$(_enc $x.DestPath)</td><td class='n'>$($x.DestPath.Length)</td></tr>`n" }
        $qualityBits += "<details><summary>$($longPaths.Count) path(s) over 300 characters (check against the ~400-char M365 URL limit) &middot; click for details</summary><table><thead><tr><th>Destination path</th><th class='n'>Length</th></tr></thead><tbody>$lr</tbody></table></details>"
    }
    if ($zeros.Count) { $qualityBits += "<p class='dim'>$($zeros.Count) zero-byte file(s) were copied and flagged.</p>" }
    if (-not $qualityBits) { $qualityBits = "<p class='okbox'>No collisions, renamed names, over-length paths, or zero-byte files. Nothing to review.</p>" }
    $helpUrl = 'https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/document-id-provider-sharepoint-add-in'
    if (($Config.run.PSObject.Properties.Name -contains 'report') -and ($Config.run.report.PSObject.Properties.Name -contains 'helpUrl') -and $Config.run.report.helpUrl) { $helpUrl = "$($Config.run.report.helpUrl)" }
    $resized = @($copiedRows | Where-Object { ([int64]$_.DestSizeBytes -gt 0) -and ([int64]$_.DestSizeBytes -ne [int64]$_.SourceSizeBytes) })
    if ($resized.Count) {
        $rz = ''
        foreach ($x in ($resized | Sort-Object { [math]::Abs([int64]$_.DestSizeBytes - [int64]$_.SourceSizeBytes) } -Descending | Select-Object -First 300)) {
            $sb2 = [int64]$x.SourceSizeBytes; $db2 = [int64]$x.DestSizeBytes; $delta = $db2 - $sb2
            $rz += "<tr><td>$(_enc $x.SourcePath)</td><td class='n'>$(Format-Bytes $sb2)</td><td class='n'>$(Format-Bytes $db2)</td><td class='n'>$(if($delta -ge 0){'+'})$delta B</td></tr>`n"
        }
        $resizeSection = "<p class='dim'>$($resized.Count) file(s) were stored at a slightly different size than the source. This is expected and not data loss: Microsoft 365 rewrites Office-family documents on upload, injecting a document ID and metadata, so the stored file differs from the original by a small amount. <a href='$(_enc $helpUrl)'>How Microsoft 365 changes files on upload</a>.</p><details><summary>Source vs stored size ($($resized.Count) files) &middot; click for details</summary><table><thead><tr><th>File</th><th class='n'>Source</th><th class='n'>Stored</th><th class='n'>Difference</th></tr></thead><tbody>$rz</tbody></table></details>"
    } else {
        $resizeSection = "<p class='okbox'>Every file was stored at exactly its source size.</p>"
    }
    $ocStatus=''; $ocReason=''; $ocExpected=$null; $ocResumed=$false; $ocSpoolEnc=$null
    $sidecar = ($AuditPath -replace '\.csv$','') + '.outcome.json'
    if (Test-Path $sidecar) {
        try {
            $oc = Get-Content $sidecar -Raw | ConvertFrom-Json
            $ocStatus="$($oc.Status)"; $ocReason="$($oc.Reason)"; $ocExpected=$oc.ExpectedFiles
            try {
                $rv = $oc.Resumed
                $ocResumed = if ($null -ne $rv -and $rv.PSObject.Properties.Name -contains 'IsPresent') { [bool]$rv.IsPresent } else { [bool]$rv }
            } catch {}
            try { if ($oc.PSObject.Properties.Name -contains 'SpoolEncrypted') { $ocSpoolEnc = [bool]$oc.SpoolEncrypted } } catch {}
        } catch {}
    }
    if (-not $ocStatus -and $endRow) { $ocStatus = ("$($endRow.Status)" -replace '^RUN_END:',''); $ocReason = "$($endRow.Reason)" }
    if ($null -ne $ocSpoolEnc) {
        $qualityBits += if ($ocSpoolEnc) {
            "<p class='okbox'>Files were staged on the transfer computer ENCRYPTED at rest (AES-256, key held only in that run's memory). Readable copies of the data existed only in memory, in transit over TLS, and at the destination.</p>"
        } else {
            "<p class='dim'>Spool encryption was switched off for this run (run.encryptSpool = false): staged files were readable on the transfer computer while the run was in flight.</p>"
        }
    }
    if (-not $ocStatus) { $ocStatus = if ($dryRun) { 'PREVIEW' } else { 'INCOMPLETE' } }
    $bannerStyle = switch ($ocStatus) {
        'COMPLETED'             { 'background:#ecfdf5;border:1px solid #6ee7b7;color:#065f46' }
        'PREVIEW'               { 'background:#eff6ff;border:1px solid #bfdbfe;color:#1e40af' }
        'COMPLETED_WITH_ERRORS' { 'background:#fffbeb;border:1px solid #fcd34d;color:#92400e' }
        'CANCELLED'             { 'background:#fffbeb;border:1px solid #fcd34d;color:#92400e' }
        default                 { 'background:#fef2f2;border:1px solid #fca5a5;color:#991b1b' }
    }
    $bannerTitle = switch ($ocStatus) {
        'COMPLETED'             { 'Completed - all planned files uploaded' }
        'PREVIEW'               { 'Preview (dry-run) - nothing was uploaded' }
        'COMPLETED_WITH_ERRORS' { 'Completed with errors - reached the end; some files need a retry' }
        'CANCELLED'             { 'Cancelled by user - stopped before finishing; uploaded files are kept' }
        'ENDED_EARLY'           { 'ENDED EARLY - the run did NOT finish' }
        default                 { 'INCOMPLETE - no completion marker (the run was interrupted before it could finish)' }
    }
    $bannerExtra = ''
    if ($skipped -gt 0)  { $bannerExtra += " $copied file(s) copied, $skipped already present and left alone: $total file(s) accounted for." }
    elseif ($total -gt 0) { $bannerExtra += " $total file(s) accounted for." }
    if ($ocResumed) { $bannerExtra += " This run was RESUMED after a pause, so the files already present are the ones the paused run had finished." }
    if (@('ENDED_EARLY','CANCELLED','INCOMPLETE') -contains $ocStatus -and $ocExpected) {
        $bannerExtra += " This run had planned to copy about $ocExpected file(s)."
    }
    if ($ocReason) { $bannerExtra += " Reason: $(_enc $ocReason)." }
    $statusBanner = "<div style='$bannerStyle;border-radius:8px;padding:14px 16px;margin:0 0 18px;font-size:14px'><strong>$(_enc $bannerTitle)</strong>$bannerExtra</div>"
    $title = if ($dryRun) { 'Migration Readiness (preview)' } else { 'Migration Report' }
    $now = Get-Date
    $tv = Lz27226ed768
    $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_enc $brand) - $title</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .wrap{max-width:960px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:32px}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:16px;margin-bottom:24px}
 .logo{height:48px}
 .brandlogo{height:60px;border-radius:8px;margin-left:auto}
 h1{font-size:20px;margin:0}
 .sub{color:#6b7280;font-size:13px;margin-top:2px}
 h2{font-size:15px;margin:28px 0 10px;color:#111827}
 .cards{display:flex;flex-wrap:wrap;gap:12px;margin:8px 0 4px}
 .card{flex:1;min-width:120px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:12px 14px}
 .card .v{font-size:22px;font-weight:600}
 .card .l{font-size:12px;color:#6b7280;margin-top:2px}
 table{width:100%;border-collapse:collapse;font-size:13px;margin-top:6px}
 th,td{text-align:left;padding:7px 10px;border-bottom:1px solid #eef2f7}
 th{background:#f3f4f6;font-weight:600}
 td.n{text-align:right;font-variant-numeric:tabular-nums}
 .err{color:#b91c1c;font-weight:600}
 .dim{color:#6b7280}
 .okbox{background:#ecfdf5;border:1px solid #a7f3d0;color:#065f46;padding:12px 14px;border-radius:8px}
 details{margin:6px 0;border:1px solid #e5e7eb;border-radius:8px;padding:8px 12px;background:#fff}
 .diag{background:#f0f7ff;border:1px solid #bcd8f5;border-radius:8px;padding:14px 16px}
 .diag .dv{font-size:16px;font-weight:700;color:#1e40af;margin-bottom:4px}
 .diag table{width:auto;margin-top:8px}
 .diag td{border-bottom:1px solid #e0ecf9;padding:5px 10px}
 summary{cursor:pointer;font-weight:600;font-size:13px;color:#111827}
 details table{margin-top:8px}
 footer{margin-top:28px;color:#9ca3af;font-size:12px;border-top:1px solid #e5e7eb;padding-top:12px}
 @media print{body{background:#fff;padding:0}.wrap{border:none}}
</style></head><body><div class='wrap'>
<header>$logoTag<div><h1>$(_enc $brand)</h1><div class='sub'>$title &middot; generated $($now.ToString('dd MMM yyyy HH:mm'))$verSub</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
$statusBanner
<div class='cards'>
 <div class='card'><div class='v'>$total</div><div class='l'>Files recorded</div></div>
 <div class='card'><div class='v'>$(if($dryRun){$wouldCopy}else{$copied})</div><div class='l'>$(if($dryRun){'Would copy'}else{'Copied'})</div></div>
 <div class='card'><div class='v'>$skipped</div><div class='l'>Skipped (unchanged)</div></div>
 <div class='card'><div class='v $(if(($errors+$verifyFail) -gt 0){'err'})'>$($errors + $verifyFail)</div><div class='l'>Errors / verify-fail</div></div>
 <div class='card'><div class='v'>$(Format-Bytes $moveBytes)</div><div class='l'>Data $(if($dryRun){'to move'}else{'moved'})</div></div>
$(if ($dryRun) {
 "<div class='card'><div class='v'>$(_estAt 100)</div><div class='l'>Est. time @ 100 Mb/s</div></div>"
} else {
 "<div class='card'><div class='v'>$mbitsPerSec Mb/s</div><div class='l'>Average speed</div></div>
 <div class='card'><div class='v'>$elapsedStr</div><div class='l'>Copying time</div></div>"
})
</div>
$diagSection
$readySection
<h2>By project</h2>
<table><thead><tr><th>Project</th><th>Destination</th><th class='n'>$(if($dryRun){'Would copy'}else{'Copied'})</th><th class='n'>Skipped</th><th class='n'>Errors</th><th class='n'>Data</th></tr></thead><tbody>
$spaceRows
</tbody></table>
$probSection
<h2>File types</h2>
<table><thead><tr><th>Extension</th><th class='n'>Files</th><th class='n'>Size</th></tr></thead><tbody>
$extRows
</tbody></table>
<h2>M365 data notes</h2>
$qualityBits
<h2>Source vs destination</h2>
$resizeSection
<h2>File details</h2>
$detailSections
<h2>Verification</h2>
<p class='dim'>Files are verified as they upload. Non-Office files are checked byte-for-byte by size. Microsoft 365 rewrites Office documents on upload (it adds a document ID and metadata), so their stored size differs by design; those are verified as stored rather than by exact bytes. $retried file(s) needed one or more retries (Microsoft throttling) and then succeeded.</p>
<p class='dim'>Time split, summed across the parallel streams: $dlSecTotal s downloading from Datto, $upSecTotal s uploading to Microsoft 365.</p>
<footer>Source: Datto Workplace &middot; Full per-file detail: $(_enc ([System.IO.Path]::GetFileName($AuditPath))) &middot; Generated from the migration audit trail by Datto Workplace to SharePoint Migrator &middot; Liscaragh Software &middot; www.liscaragh.com</footer>
</div>
<script>window.addEventListener('beforeprint',function(){document.querySelectorAll('details').forEach(function(d){d.open=true;});});</script>
</body></html>
"@
    $runType = 'run'; if ([IO.Path]::GetFileName($AuditPath) -match '^audit-([A-Za-z]+)-') { $runType = $Matches[1] }
    $outPath = Join-Path $Config.run.reportRoot ("report-" + $runType + "-" + $now.ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Lz12e519cc30 OK "HTML report written: $outPath"
    return $outPath
}
function Invoke-CompletionCertificate {
    param($Config, [string]$AuditPath, [switch]$NoStageLog)
    if (-not $NoStageLog) { Lzffe69bba89 -Config $Config -Stage 'api-certificate' }
    if (-not $AuditPath) {
        $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $AuditPath = $latest.FullName }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) { Lz12e519cc30 ERROR "No audit CSV found in $($Config.run.reportRoot). A certificate is built from a completed run's audit trail; run a migration to completion first."; return }
    $rows = @(Import-Csv $AuditPath)
    $endRow = @($rows | Where-Object { "$($_.Status)" -like 'RUN_END:*' }) | Select-Object -Last 1
    $rows   = @($rows | Where-Object { "$($_.Status)" -notlike 'RUN_END:*' })
    if (-not $rows.Count) { Lz12e519cc30 WARN "Audit CSV is empty: $AuditPath"; return }
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    function Lz8067f5c42c { param($st) @($rows | Where-Object { $_.Status -eq $st }).Count }
    function _sumBytes { param($items) $a = @($items); if ($a.Count) { [int64](($a | Measure-Object SourceSizeBytes -Sum).Sum) } else { [int64]0 } }
    $copied  = (Lz8067f5c42c 'Copied') + (Lz8067f5c42c 'ZeroByte')
    $skipped = Lz8067f5c42c 'Skipped'
    $errors  = (Lz8067f5c42c 'Error') + (Lz8067f5c42c 'DownloadError') + (Lz8067f5c42c 'SkippedTooLarge')
    $verifyFail = Lz8067f5c42c 'VerifyFail'
    $wouldCopy  = Lz8067f5c42c 'WouldCopy'
    $present = $copied + $skipped
    $presentBytes = _sumBytes (@($rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' -or $_.Status -eq 'Skipped' }))
    $projects = @($rows | Where-Object { "$($_.Space)".Trim() } | Group-Object Space).Count
    $dryRun = ($wouldCopy -gt 0 -and $copied -eq 0)
    $ocStatus=''
    $sidecar = ($AuditPath -replace '\.csv$','') + '.outcome.json'
    if (Test-Path $sidecar) { try { $oc = Get-Content $sidecar -Raw | ConvertFrom-Json; $ocStatus="$($oc.Status)" } catch {} }
    if (-not $ocStatus -and $endRow) { $ocStatus = ("$($endRow.Status)" -replace '^RUN_END:','') }
    if (-not $ocStatus) { $ocStatus = if ($dryRun) { 'PREVIEW' } else { 'INCOMPLETE' } }
    if ($dryRun -or @('PREVIEW','INCOMPLETE','ENDED_EARLY','CANCELLED') -contains $ocStatus) {
        Lz12e519cc30 ERROR ("A completion certificate is only issued for a completed migration. This run is '" + $ocStatus + "'. Run a full sync through to completion (then a verify), and issue the certificate from that run.")
        return
    }
    $withErrors = ($ocStatus -eq 'COMPLETED_WITH_ERRORS') -or (($errors + $verifyFail) -gt 0)
    $times = @($rows | ForEach-Object { try { [datetime]::Parse($_.TimestampUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch {} } | Where-Object { $_ })
    $dateStr = if ($times.Count) {
        $mn = ($times | Measure-Object -Minimum).Minimum.ToLocalTime(); $mx = ($times | Measure-Object -Maximum).Maximum.ToLocalTime()
        if ($mn.Date -eq $mx.Date) { $mx.ToString('dd MMMM yyyy') } else { $mn.ToString('dd MMM yyyy') + ' to ' + $mx.ToString('dd MMM yyyy') }
    } else { (Get-Date).ToString('dd MMMM yyyy') }
    $dests = New-Object System.Collections.Generic.List[string]
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (Test-Path $mapPath) {
        foreach ($m in Import-Csv $mapPath) {
            $d = if ($m.DestinationType -eq 'OneDrive') { "OneDrive: $($m.TargetPrincipal)" } else { (@("$($m.DestinationUrl)", "$($m.TargetLibrary)") | Where-Object { "$_".Trim() }) -join ' / ' }
            if ("$d".Trim() -and -not $dests.Contains($d)) { [void]$dests.Add($d) }
        }
    }
    $destList = if ($dests.Count) { ($dests | Select-Object -First 12 | ForEach-Object { "<li>$(_enc $_)</li>" }) -join '' } else { "<li class='dim'>See the migration report for the full destination list.</li>" }
    $brand = 'Datto Workplace to SharePoint Migrator'; $logoTag = ''; $client = ''
    if ($Config.run.PSObject.Properties.Name -contains 'report') {
        if (($Config.run.report.PSObject.Properties.Name -contains 'brand') -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
        if (($Config.run.report.PSObject.Properties.Name -contains 'client') -and $Config.run.report.client) { $client = "$($Config.run.report.client)" }
        if (($Config.run.report.PSObject.Properties.Name -contains 'logo') -and $Config.run.report.logo -and (Test-Path $Config.run.report.logo)) {
            try { $lb=[System.IO.File]::ReadAllBytes($Config.run.report.logo); $ext=([System.IO.Path]::GetExtension($Config.run.report.logo)).TrimStart('.').ToLower(); if($ext -eq 'jpg'){$ext='jpeg'}; $logoTag = "<img class='logo' alt='logo' src='data:image/$ext;base64,$([Convert]::ToBase64String($lb))' />" } catch {}
        }
    }
    $caveat = ''
    if ($withErrors) {
        $caveat = "<div class='caveat'><strong>Issued with exceptions.</strong> $($errors + $verifyFail) file(s) need attention and are listed in the migration report; every other file is present and verified. This certificate records the migration as complete apart from those items.</div>"
    }
    $tv = Lz27226ed768; $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    $now = Get-Date
    $refName = [System.IO.Path]::GetFileName($AuditPath)
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_enc $brand) - Migration Completion Certificate</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .cert{max-width:820px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:40px 44px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:18px}
 .logo{height:52px}
 .brandlogo{height:64px;border-radius:8px;margin-left:auto}
 h1{font-size:23px;margin:0;letter-spacing:.2px}
 .sub{color:#6b7280;font-size:13px;margin-top:3px}
 .statement{font-size:15px;line-height:1.65;margin:22px 0 6px}
 .cards{display:flex;flex-wrap:wrap;gap:12px;margin:18px 0}
 .card{flex:1;min-width:140px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:14px 16px}
 .card .v{font-size:24px;font-weight:700}
 .card .l{font-size:12px;color:#6b7280;margin-top:2px}
 .err{color:#b91c1c}
 h2{font-size:13px;margin:24px 0 8px;color:#374151;text-transform:uppercase;letter-spacing:.5px}
 ul{margin:6px 0;padding-left:20px;font-size:14px}
 li{margin:3px 0}
 .dim{color:#6b7280}
 .verify{background:#ecfdf5;border:1px solid #a7f3d0;color:#065f46;padding:12px 16px;border-radius:8px;font-size:13px;line-height:1.55}
 .caveat{background:#fffbeb;border:1px solid #fcd34d;color:#92400e;padding:12px 16px;border-radius:8px;font-size:13px;line-height:1.55;margin:14px 0}
 .sign{display:flex;gap:40px;margin-top:40px}
 .sig{flex:1}
 .sig .line{border-bottom:1px solid #9ca3af;height:40px}
 .sig .who{font-size:12px;color:#6b7280;margin-top:6px}
 footer{margin-top:30px;color:#9ca3af;font-size:11px;border-top:1px solid #e5e7eb;padding-top:12px}
 @media print{body{background:#fff;padding:0}.cert{border:none;box-shadow:none}}
</style></head><body><div class='cert'>
<header>$logoTag<div style='flex:1'><h1>Migration Completion Certificate</h1><div class='sub'>$(_enc $brand)$verSub</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
<p class='statement'>This certifies that the migration of data from <strong>Datto Workplace</strong>$(if($client){" for <strong>$(_enc $client)</strong>"}) to <strong>Microsoft 365 (SharePoint / OneDrive)</strong> was completed on <strong>$dateStr</strong>.</p>
$caveat
<div class='cards'>
 <div class='card'><div class='v'>$present</div><div class='l'>Files present &amp; verified</div></div>
 <div class='card'><div class='v'>$(Format-Bytes $presentBytes)</div><div class='l'>Total data</div></div>
 <div class='card'><div class='v'>$projects</div><div class='l'>Projects migrated</div></div>
 <div class='card'><div class='v $(if($withErrors){'err'})'>$($errors + $verifyFail)</div><div class='l'>Files needing attention</div></div>
</div>
<h2>Where the data now lives</h2>
<ul>$destList</ul>
<h2>How it was verified</h2>
<div class='verify'>Every file was verified as it was uploaded. Non-Office files are checked byte-for-byte by size. Microsoft 365 rewrites Office documents on upload (it adds a document ID and metadata), so those are verified at their stored size by design. The complete per-file record is in the migration audit ($(_enc $refName)).</div>
<div class='sign'>
 <div class='sig'><div class='line'></div><div class='who'>Migrated by (Liscaragh Software / delivery partner)</div></div>
 <div class='sig'><div class='line'></div><div class='who'>Accepted by (client)</div></div>
</div>
<footer>Issued $($now.ToString('dd MMM yyyy HH:mm')) by Datto Workplace to SharePoint Migrator$verSub &middot; Liscaragh Software &middot; www.liscaragh.com &middot; Audit reference: $(_enc $refName)</footer>
</div></body></html>
"@
    $outPath = Join-Path $Config.run.reportRoot ("certificate-" + $now.ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Lz12e519cc30 OK "Completion certificate written: $outPath"
    return $outPath
}
function Invoke-Validate {
    param($Config)
    Lzffe69bba89 -Config $Config -Stage 'api-validation'
    $ckStart = Get-Date
    Lz35962d6dcd -Config $Config
    Connect-Destination -Config $Config
    $map = @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')
    $report = New-Object System.Collections.Generic.List[object]
    $missingAll = New-Object System.Collections.Generic.List[object]
    $staleAll = New-Object System.Collections.Generic.List[object]
    $sanitise = (($Config.run.PSObject.Properties.Name -contains 'sanitiseNames') -and $Config.run.sanitiseNames)
    $tol = [TimeSpan]::FromSeconds(2)
    $t = $map.Count; $i = 0
    foreach ($row in $map) {
        $i++; Lz390831b78c -Activity 'Verify' -Status $row.Space -Current $i -Total $t | Out-Null
        if ($script:GuiMode) { Write-Host "##STATUS##|Verifying files arrived in [$($row.Space)]: checking each is present and up to date..." }
        try {
            $null = Resolve-DestinationDriveId -Config $Config -Row $row
            Lz12e519cc30 OK "  destination reachable: $(Get-RowDestLabel $row). Reading the source now."
        } catch {
            Lz12e519cc30 ERROR "  destination NOT reachable for [$($row.Space)], so the source was not read: $($_.Exception.Message)"
            continue
        }
        $space = New-SpaceRef -Row $row
        $dj = Lz1977e2a874 -Config $Config -Row $row
        $items = @(Get-DattoItems -Config $Config -Space $space)
        $srcCount = $items.Count
        $inv = Receive-DestInventoryJob -Config $Config -Row $row -Job $dj -WithTimes
        $missing = New-Object System.Collections.Generic.List[string]
        $stale = New-Object System.Collections.Generic.List[string]
        foreach ($it in $items) {
            $rp = $it.RelativePath -replace '\\','/'
            if ($sanitise) { $rp = ConvertTo-SafeRelPath $rp }
            if (-not $inv.Paths.Contains($rp)) { $missing.Add($it.RelativePath); continue }
            $st = ConvertTo-UtcDate $it.ModifiedUtc
            $dt = if ($inv.Times.ContainsKey($rp)) { $inv.Times[$rp] } else { $null }
            if ($null -ne $st -and $null -ne $dt -and $st -gt $dt.Add($tol)) { $stale.Add($it.RelativePath) }
        }
        $present = $srcCount - $missing.Count
        $extra = [math]::Max($inv.Count - $present, 0)
        $verdict = if ($missing.Count -gt 0) { 'FAIL' } elseif ($stale.Count -gt 0) { 'OUT OF DATE' } else { 'PASS' }
        foreach ($m in $missing) { $missingAll.Add([pscustomobject]@{ Space = $row.Space; MissingFile = $m }) }
        foreach ($s in $stale)   { $staleAll.Add([pscustomobject]@{ Space = $row.Space; StaleFile = $s }) }
        $report.Add([pscustomobject]@{
            Space=$row.Space; SourceFiles=$srcCount; Present=$present; Missing=$missing.Count
            OutOfDate=$stale.Count; ExtraAtDest=$extra; DestFiles=$inv.Count; Verdict=$verdict
        })
        $extraNote = if ($extra -gt 0) { " The destination also holds $extra other file(s) not from this source (content that was there before the migration); that is expected." } else { '' }
        if ($verdict -eq 'PASS') {
            Lz12e519cc30 OK "  $($row.Space): PASS - all $srcCount file(s) are present and up to date at the destination.$extraNote"
        } elseif ($verdict -eq 'OUT OF DATE') {
            Lz12e519cc30 WARN "  $($row.Space): OUT OF DATE - all $srcCount file(s) are present, but $($stale.Count) have a newer version in Datto than at the destination (see api-validation-stale.csv). In plain terms: those files were changed in Datto since they were copied. Run 'Sync new and changed' with 'Update where Datto is newer' to bring them up to date."
        } else {
            Lz12e519cc30 ERROR "  $($row.Space): FAIL - $($missing.Count) of $srcCount file(s) were NOT found at the destination (see api-validation-missing.csv).$(if($stale.Count){" $($stale.Count) present file(s) are also out of date."}) In plain terms: some files did not make it across. Run 'Sync new and changed' to copy them, then verify again."
            foreach ($m in @($missing | Select-Object -First 15)) { Lz12e519cc30 ERROR "      missing: /$m" }
            if ($missing.Count -gt 15) { Lz12e519cc30 ERROR "      ... and $('{0:N0}' -f ($missing.Count - 15)) more, all named in api-validation-missing.csv." }
        }
    }
    try { Write-Progress -Activity 'Verify' -Completed } catch {}
    $report | Export-Csv -Path (Join-Path $Config.run.reportRoot 'api-validation-report.csv') -NoTypeInformation -Encoding UTF8
    if ($missingAll.Count) {
        $missingAll | Export-Csv -Path (Join-Path $Config.run.reportRoot 'api-validation-missing.csv') -NoTypeInformation -Encoding UTF8
        if ($script:GuiMode) { Write-Host "##CHECKFILES##|$($missingAll.Count)|0|0|$(Join-Path $Config.run.reportRoot 'api-validation-missing.csv')" }
    }
    if ($staleAll.Count) {
        $staleAll | Export-Csv -Path (Join-Path $Config.run.reportRoot 'api-validation-stale.csv') -NoTypeInformation -Encoding UTF8
        if ($script:GuiMode) { Write-Host "##CHECKFILES##|0|0|$($staleAll.Count)|$(Join-Path $Config.run.reportRoot 'api-validation-stale.csv')" }
    }
    $fail  = @($report | Where-Object Verdict -eq 'FAIL').Count
    $stalep = @($report | Where-Object Verdict -eq 'OUT OF DATE').Count
    if ($fail -gt 0) { Lz12e519cc30 ERROR "Verify complete. $fail project(s) have missing files (see api-validation-missing.csv). Run 'Sync new and changed' to re-copy them, then verify again." }
    elseif ($stalep -gt 0) { Lz12e519cc30 WARN "Verify complete. Everything is present, but $stalep project(s) have file(s) that are newer in Datto than at the destination (see api-validation-stale.csv). Run 'Sync new and changed' with 'Update where Datto is newer' to refresh them." }
    else { Lz12e519cc30 OK "Verify complete. Every file is present at the destination and up to date (no file is newer in Datto). Extra files already in the destination are expected and were ignored." }
    if ($script:GuiMode) {
        if ($fail -gt 0)       { Write-Host "##CHECKOUTCOME##|BAD|found a problem: $('{0:N0}' -f $missingAll.Count) file(s) are MISSING at the destination across $fail project(s). They are named in the log below and in api-validation-missing.csv. Click 'Sync new and changed' to copy them, then verify again." }
        elseif ($stalep -gt 0) { Write-Host "##CHECKOUTCOME##|WARN|everything is present, but $('{0:N0}' -f $staleAll.Count) file(s) are newer in Datto than at the destination (api-validation-stale.csv names them). Run 'Sync new and changed' with 'Update where Datto is newer' to refresh them." }
        else                   { Write-Host "##CHECKOUTCOME##|OK|every file is present at the destination and up to date." }
    }
    try {
        $emVerdict = if ($fail -gt 0) { 'BAD' } elseif ($stalep -gt 0) { 'WARN' } else { 'OK' }
        $emBucket  = switch ($emVerdict) { 'OK' { 'Success' } 'WARN' { 'Warning' } default { 'Failure' } }
        $emAtt = @("$script:LogFile", (Join-Path $Config.run.reportRoot 'api-validation-report.csv'))
        if ($missingAll.Count) { $emAtt += (Join-Path $Config.run.reportRoot 'api-validation-missing.csv') }
        if ($staleAll.Count)   { $emAtt += (Join-Path $Config.run.reportRoot 'api-validation-stale.csv') }
        $emVars = Get-EmailScopeVars -Config $Config
        $emVars['EndTime'] = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        $emVars['Duration'] = ('{0:hh\:mm\:ss}' -f ((Get-Date) - $ckStart))
        Send-RunEmail -Config $Config -ActionKey 'Validate' -ActionLabel 'Verify' `
            -OutcomeBucket $emBucket -OutcomeLabel $emVerdict -Vars $emVars `
            -AttachPaths $emAtt `
            -BodyLines @(
                "Action: Verify files arrived",
                "Outcome: $emVerdict",
                "Missing at destination: $('{0:N0}' -f $missingAll.Count)",
                "Newer in Datto (out of date at destination): $('{0:N0}' -f $staleAll.Count)",
                "Source: $($emVars['Source'])",
                "Destination: $($emVars['Destination'])")
    } catch {}
}
function Lzb83d988e1f {
    param($Config)
    Lzffe69bba89 -Config $Config -Stage 'api-permissions'
    Lz35962d6dcd -Config $Config
    $map = @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')
    function Lz3e301dad52 { param([string]$r) switch -Regex ($r.ToLower()) { 'owner|manage|admin'{'Site Owner (Full Control)';break} 'edit|write|contrib'{'Member (Edit)';break} 'view|read'{'Visitor (Read)';break} default{'REVIEW'} } }
    $plan = New-Object System.Collections.Generic.List[object]
    $t = $map.Count; $i = 0
    foreach ($row in $map) {
        $i++; Lz390831b78c -Activity 'Permissions' -Status $row.Space -Current $i -Total $t | Out-Null
        $space = New-SpaceRef -Row $row
        foreach ($p in @(Lzee101c9f2d -Config $Config -Space $space)) {
            $plan.Add([pscustomobject]@{ Space=$row.Space; Principal=$p.Principal; DattoRole=$p.Role; DestinationUrl=$row.DestinationUrl; ProposedM365Role=(Lz3e301dad52 $p.Role) })
        }
    }
    try { Write-Progress -Activity 'Permissions' -Completed } catch {}
    $out = Join-Path $Config.run.reportRoot 'api-permissions-plan.csv'
    $plan | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
    if ($plan.Count -eq 0) { Lz12e519cc30 WARN "No permissions returned by the API (endpoint may not be configured). $out is empty." }
    else { Lz12e519cc30 OK "Permissions plan written (NOT applied): $($plan.Count) entries. $out" }
}
function Lzd5faf79a54 {
    param($Config)
    Lzffe69bba89 -Config $Config -Stage 'api-test'
    Lz35962d6dcd -Config $Config
    Connect-Destination -Config $Config
    $spaces = @(Get-DattoSpaces -Config $Config)
    Lz12e519cc30 OK "Datto returned $($spaces.Count) project(s)."
    if ($spaces.Count) {
        $s = $spaces[0]
        Lz12e519cc30 INFO "First project: $($s.Name) ($($s.Type))"
        $items = @(Get-DattoItems -Config $Config -Space $s | Select-Object -First 5)
        foreach ($it in $items) { Lz12e519cc30 INFO "  file: $($it.RelativePath) ($([math]::Round($it.Size/1KB,1)) KB, mod $($it.ModifiedUtc))" }
        Lz12e519cc30 OK "If the project and files above look right, the Datto connection is reading real data correctly."
    }
}
function Lza482636a65 {
    param($Config)
    while ($true) {
        Write-Host "`n=== Datto API -> M365 (100% API, temp streaming) ===" -ForegroundColor Cyan
        Write-Host " Datto provider: $($Config.datto.provider)   Destination provider: $($Config.destination.provider)" -ForegroundColor DarkGray
        Write-Host " 1. Test API (auth + list one project)"
        Write-Host " 2. Discover (choose a destination per project -> mapping.csv)"
        Write-Host " 3. Pre-flight (quota + path/name checks)"
        Write-Host " 4. Transfer DRY-RUN (preview only, nothing is uploaded)"
        Write-Host " 5. Transfer EXECUTE (FirstPass)" -ForegroundColor Yellow
        Write-Host " 6. Transfer EXECUTE (Delta)" -ForegroundColor Yellow
        Write-Host " 7. Validate (reconcile against destination)"
        Write-Host " 8. RUN FULL FLOW: Discover -> Pre-flight -> Transfer -> Validate" -ForegroundColor Green
        Write-Host " Q. Quit"
        switch ((Read-Host 'Select').ToUpper()) {
            '1' { Lzd5faf79a54 -Config $Config }
            '2' { Lz8e036f1614 -Config $Config }
            '3' { Lz52638821a3 -Config $Config }
            '4' { Invoke-Transfer -Config $Config -Mode FirstPass -SpoolAhead $SpoolAhead }
            '5' { if ((Read-Host 'Type YES to upload') -eq 'YES') { Invoke-Transfer -Config $Config -Mode FirstPass -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -Execute } }
            '6' { if ((Read-Host 'Type YES to upload') -eq 'YES') { Invoke-Transfer -Config $Config -Mode Delta -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -Execute } }
            '7' { Invoke-Validate -Config $Config }
            '8' {
                Lz8e036f1614 -Config $Config
                $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
                if (Test-Path $mapPath) {
                    Lz52638821a3 -Config $Config
                    if ((Read-Host 'Proceed to UPLOAD (this writes to your tenant)? Type YES') -eq 'YES') {
                        Invoke-Transfer -Config $Config -Mode FirstPass -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -Execute
                        Invoke-Validate -Config $Config
                    } else { Write-Host 'Stopped before upload.' -ForegroundColor DarkGray }
                } else { Write-Host 'No projects mapped; nothing to do.' -ForegroundColor DarkGray }
            }
            'Q' { return }
            default { Write-Host 'Unknown option.' -ForegroundColor DarkGray }
        }
    }
}
if ($MyInvocation.InvocationName -ne '.') {
$cfg = Import-MigrationConfig -Path $ConfigPath
if (-not $PSBoundParameters.ContainsKey('SpoolAhead') -and
    ($cfg.run.PSObject.Properties.Name -contains 'parallel') -and
    ($cfg.run.parallel.PSObject.Properties.Name -contains 'spoolAhead')) {
    $SpoolAhead = [int]$cfg.run.parallel.spoolAhead
}
if (-not $PSBoundParameters.ContainsKey('MaxParallelSpaces') -and
    ($cfg.run.PSObject.Properties.Name -contains 'parallel') -and
    ($cfg.run.parallel.PSObject.Properties.Name -contains 'maxParallelSpaces')) {
    $MaxParallelSpaces = [int]$cfg.run.parallel.maxParallelSpaces
}
$parallelEnabled = $false
try { if (($cfg.run.PSObject.Properties.Name -contains 'parallel') -and ($cfg.run.parallel.PSObject.Properties.Name -contains 'enabled') -and $cfg.run.parallel.enabled) { $parallelEnabled = $true } } catch {}
if (-not $parallelEnabled -and $MaxParallelSpaces -gt 1) {
    Lz12e519cc30 INFO "Parallel projects are off (run.parallel.enabled is not set); running one project at a time."
    $MaxParallelSpaces = 1
}
if ($cfg.run.PSObject.Properties.Name -contains 'throttle') {
    if (($cfg.run.throttle.PSObject.Properties.Name -contains 'timeoutSec') -and $cfg.run.throttle.timeoutSec) {
        $script:HttpTimeoutSec = [int]$cfg.run.throttle.timeoutSec
    }
    if (($cfg.run.throttle.PSObject.Properties.Name -contains 'transferTimeoutSec') -and $cfg.run.throttle.transferTimeoutSec) {
        $script:TransferTimeoutSec = [int]$cfg.run.throttle.transferTimeoutSec
    }
}
$UploadWorkers = 4
if ($cfg.run.PSObject.Properties.Name -contains 'upload') {
    if (($cfg.run.upload.PSObject.Properties.Name -contains 'directPutMaxMB') -and $cfg.run.upload.directPutMaxMB) {
        $script:SmallFilePutThreshold = [int64]$cfg.run.upload.directPutMaxMB * 1MB
    }
    if (($cfg.run.upload.PSObject.Properties.Name -contains 'workers') -and $cfg.run.upload.workers) {
        $UploadWorkers = [int]$cfg.run.upload.workers
    }
}
if ($cfg.run.PSObject.Properties.Name -contains 'encryptSpool') { $script:SpoolEncrypt = [bool]$cfg.run.encryptSpool }
if ($cfg.run.PSObject.Properties.Name -contains 'trialFileLimit' -and $cfg.run.trialFileLimit) { $script:TrialFileLimit = [Math]::Min([Math]::Max(1, [int]$cfg.run.trialFileLimit), $script:TrialFileLimit) }
if ($TrialLimitForTest -gt 0 -and $cfg.destination.provider -eq 'LocalSim') { $script:TrialFileLimit = $TrialLimitForTest; $script:TrialCap = $TrialLimitForTest; $script:TrialFilesRemaining = $TrialLimitForTest }
if ($cfg.run.PSObject.Properties.Name -contains 'tuning') {
    $tn = $cfg.run.tuning
    if (($tn.PSObject.Properties.Name -contains 'chunkSizeMB')  -and $tn.chunkSizeMB)  { $script:ChunkSize    = [int64]$tn.chunkSizeMB * 1MB }
    if (($tn.PSObject.Properties.Name -contains 'excludePatterns'))                    { $script:ExcludePatterns = @($tn.excludePatterns | Where-Object { "$_".Trim() }) }
    if (($tn.PSObject.Properties.Name -contains 'includePatterns'))                    { $script:IncludePatterns = @($tn.includePatterns | Where-Object { "$_".Trim() }) }
    if (($tn.PSObject.Properties.Name -contains 'maxFileSizeMB') -and $tn.maxFileSizeMB){ $script:MaxFileBytes  = [int64]$tn.maxFileSizeMB * 1MB }
    if (($tn.PSObject.Properties.Name -contains 'largeFileMB')   -and $tn.largeFileMB)  { $script:LargeFileBytes = [int64]$tn.largeFileMB * 1MB }
    if (($tn.PSObject.Properties.Name -contains 'modifiedAfter'))  { $script:ModifiedAfterUtc  = ConvertTo-ConfigUtcBound $tn.modifiedAfter }
    if (($tn.PSObject.Properties.Name -contains 'modifiedBefore')) { $script:ModifiedBeforeUtc = ConvertTo-ConfigUtcBound $tn.modifiedBefore }
    if ($script:ModifiedAfterUtc -and $script:ModifiedBeforeUtc -and $script:ModifiedAfterUtc -ge $script:ModifiedBeforeUtc) {
        throw "run.tuning.modifiedAfter ($($tn.modifiedAfter)) is not before modifiedBefore ($($tn.modifiedBefore)); nothing would match. Widen the window, or clear one bound."
    }
    if (($tn.PSObject.Properties.Name -contains 'assessmentTopFiles') -and $tn.assessmentTopFiles) { $script:AssessmentTopFiles = [Math]::Max(1, [int]$tn.assessmentTopFiles) }
}
try {
    $needsLicence = (($Action -eq 'Transfer' -and $Execute) -or ($Action -eq 'Validate'))
    if ($needsLicence -and ($cfg.destination.provider -ne 'LocalSim')) {
        $lic = Test-MigrationLicence -Config $cfg
        if ($lic.Licensed) {
            $script:LicenceInfo = $lic
            Lz12e519cc30 OK "Licence accepted: $($lic.Customer), Microsoft tenant $($lic.TenantId) (licence $($lic.LicenceId))."
        }
        elseif ($lic.Reason -match '^no licence file') {
            if ($Action -eq 'Validate') {
                if ($script:GuiMode) { Write-Host "##TRIAL##|START|0|Validate" }
                Lz12e519cc30 WARN "No licence: EVALUATION MODE. Verify will still check whatever is at the destination, so you can confirm the trial copy landed correctly. Licence this Microsoft tenant at https://www.liscaragh.com to remove the limit."
            }
            else {
                $bucket = if ($Mode -eq 'FirstPass') { 'FirstPass' } else { 'Delta' }
                $what   = if ($bucket -eq 'FirstPass') { 'full copy' } else { 'sync' }
                $key    = Get-EvalKey -TenantId "$($cfg.auth.tenantId)"
                $used   = Get-EvalUsage -Key $key
                $spent  = if ($bucket -eq 'FirstPass') { $used.FirstPass } else { $used.Delta }
                $remaining = $script:TrialFileLimit - $spent
                if ($remaining -le 0) {
                    if ($script:GuiMode) { Write-Host "##TRIAL##|EXHAUSTED|$bucket|$($script:TrialFileLimit)" }
                    Lz12e519cc30 ERROR "The free evaluation for this Microsoft tenant is used up: it has already had its $($script:TrialFileLimit) free $what file(s). You can still test the connection, list projects, Preview, Compare sizes and Verify. To migrate everything, licence this tenant at https://www.liscaragh.com, then install the licence via Help > Install licence file."
                    exit 1
                }
                $script:TrialLedgerKey = $key
                $script:TrialBucket = $bucket
                $script:TrialCap = $remaining
                $script:TrialFilesRemaining = $remaining
                if ($script:GuiMode) { Write-Host "##TRIAL##|START|$remaining|$bucket" }
                Lz12e519cc30 WARN "No licence: EVALUATION MODE. Up to $remaining $what file(s) will be copied for real so you can prove the migration works end to end, then it stops. This is a sample, not a full migration: this tenant's free $what allowance is $($script:TrialFileLimit) file(s) in total, and $spent have been used. Licence this Microsoft tenant at https://www.liscaragh.com, then Help > Install licence file, to migrate everything."
            }
        }
        else {
            if ($script:GuiMode) { Write-Host "##LICENCE##|$($lic.Reason)" }
            Lz12e519cc30 ERROR "This action needs a valid licence: $($lic.Reason). Without a valid licence you can still test the connection, list projects, Preview (see what would copy, without copying), and run 'Compare sizes'. Obtain a licence at https://www.liscaragh.com, then install it via Help > Install licence file."
            exit 1
        }
    }
    switch ($Action) {
        'TestApi'     { Lzd5faf79a54        -Config $cfg }
        'Discover'    { Lz8e036f1614 -Config $cfg -NonInteractive:$NonInteractive }
        'PreFlight'   { Lz52638821a3 -Config $cfg }
        'Transfer'    { Invoke-Transfer -Config $cfg -Mode $Mode -DeltaMode $DeltaMode -OnlySpace $OnlySpace -Spaces $Spaces -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -UploadWorkers $UploadWorkers -ResultDir $ResultDir -Execute:$Execute -FailedOnly:$FailedOnly -FailedFromAudit $FailedFromAudit
                        exit $script:ExitCode }
        'Validate'    { Invoke-Validate -Config $cfg }
        'SizeCheck'   { Invoke-SizeCheck -Config $cfg -OnlySpace $OnlySpace }
        'DestInventory' { Lz10e2c69832 -Config $cfg -SpaceName $Spaces -ResultDir $ResultDir }
        'Report'      { Invoke-HtmlReport -Config $cfg -AuditPath $AuditPath | Out-Null }
        'Certificate' { Invoke-CompletionCertificate -Config $cfg -AuditPath $AuditPath | Out-Null }
        'Finalize'    { Lz9a738a84d1 -Config $cfg -Status $FinalizeStatus -AuditPath $AuditPath; exit $script:ExitCode }
        default       { Lza482636a65       -Config $cfg }
    }
}
catch {
    $e = $_
    $emit = {
        param([string]$Level, [string]$Text)
        try { Lz12e519cc30 $Level $Text } catch { Write-Host "[$Level] $Text" }
    }
    if ("$($e.Exception.Message)" -like "*$($script:StopTag)*") {
        & $emit 'ERROR' ((("$($e.Exception.Message)") -replace [regex]::Escape($script:StopTag), '').Trim())
        $script:ExitCode = 1
        exit 1
    }
    & $emit 'ERROR' "The run stopped with an unexpected error. Everything below is the technical detail; nothing was left half-written, and no file at the destination was touched by this failure."
    & $emit 'ERROR' "  Message : $($e.Exception.Message)"
    & $emit 'ERROR' "  Type    : $($e.Exception.GetType().FullName)"
    try {
        $ii = $e.InvocationInfo
        if ($ii) {
            & $emit 'ERROR' "  Where   : $($ii.ScriptName):$($ii.ScriptLineNumber) char $($ii.OffsetInLine)"
            if ("$($ii.Line)".Trim()) { & $emit 'ERROR' "  Line    : $("$($ii.Line)".Trim())" }
        }
    } catch { }
    try {
        foreach ($ln in ("$($e.ScriptStackTrace)" -split "`r?`n")) {
            if ("$ln".Trim()) { & $emit 'ERROR' "    $("$ln".Trim())" }
        }
    } catch { }
    try {
        $inner = $e.Exception.InnerException; $depth = 0
        while ($inner -and $depth -lt 5) {
            & $emit 'ERROR' "  Caused by: $($inner.GetType().FullName): $($inner.Message)"
            $inner = $inner.InnerException; $depth++
        }
    } catch { }
    & $emit 'ERROR' "Send this log to support@liscaragh.com (Help menu > Email support attaches it for you)."
    $script:ExitCode = 1
    exit 1
}
}
