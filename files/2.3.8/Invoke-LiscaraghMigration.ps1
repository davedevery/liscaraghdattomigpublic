[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ConfigPath,
    [ValidateSet('TestApi','Discover','PreFlight','Transfer','Validate','Drift','SizeCheck','Report','Certificate','Finalize','DestInventory','SourceReview','Provenance','Menu')] [string] $Action = 'Menu',
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
$script:SyncPreviewRead = $false
function Lz8d39824bd6 { param([int]$Done,[int]$Total,[int64]$BytesDone,[int64]$BytesTotal,[string]$Space,
        [int]$SmallDone=0,[int]$SmallTotal=0,[int64]$LargeBytesDone=0,[int64]$LargeBytesTotal=0,[int]$Final=1)
    if ($script:GuiMode) { Write-Host "##PROGRESS##|$Done|$Total|$BytesDone|$BytesTotal|$SmallDone|$SmallTotal|$LargeBytesDone|$LargeBytesTotal|$Final|$Space" }
}
$script:LastThrMax = -1; $script:LastThrPaused = $false
function Lzeb3c01b3fc { param([int]$Max,[int]$HardMax,[int]$PausedSeconds,[int]$Events,[int]$Code=0)
    if ($script:GuiMode) { Write-Host "##THROTTLE##|$Max|$HardMax|$PausedSeconds|$Events|$Code" }
}
$script:LogFile = $null
$script:LegacyStateNoticeDone = $false
$script:HttpTimeoutSec     = 120
$script:TransferTimeoutSec = 3600
$script:SourceIdleSec = 120
$script:SourceReadAttempts = 3
$script:EmailMaxAttachMB   = 3
$script:EmailDefaultSubject = 'Liscaragh Migrate - {Action} {Outcome}: {JobName}'
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
$script:RunSpaceNames = @()
$script:UpHttp = $null
$script:RetryEvents = 0
$script:LastThrottleUtc = $null
$script:DattoPauseEvents = 0
$script:SrcTotal = 0
$script:DattoPace = [hashtable]::Synchronized(@{ GapMs = 0; NextTicks = [int64]0; MaxMs = 8000; FloorMs = 0; HeadersSeen = $false; ReqCount = 0; WindowStartTicks = [int64]0; LastProbeTicks = [int64]0 })
$script:DattoLastHeaders = $null
$script:DattoBudgetLogAt = $null
function Lz4cb83a379f {
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
function Lz18d2c2ab3e {
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
function Update-DattoPaceFromHeaders {
    param($Headers)
    $p = $script:DattoPace
    $rl = Lz18d2c2ab3e $Headers
    if (-not $rl.HasBudget) {
        [System.Threading.Monitor]::Enter($p.SyncRoot)
        try {
            $nowT = [DateTime]::UtcNow.Ticks
            if ($p.WindowStartTicks -le 0) { $p.WindowStartTicks = $nowT; $p.ReqCount = 1 } else { $p.ReqCount++ }
            if ($p.GapMs -gt $p.FloorMs) { $p.GapMs = Lz7e73f9e662 -Gap ([int]$p.GapMs) -Floor ([int]$p.FloorMs) }
            if ($p.FloorMs -gt 0) {
                if ($p.LastProbeTicks -le 0) { $p.LastProbeTicks = $nowT }
                elseif ((($nowT - [int64]$p.LastProbeTicks) / [double][TimeSpan]::TicksPerSecond) -ge 30) { $p.FloorMs = [int][math]::Floor($p.FloorMs * 0.95); $p.LastProbeTicks = $nowT }
            }
        } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
        return
    }
    if (-not $p.HeadersSeen) { $p.HeadersSeen = $true; Write-MigrationLog INFO "  Datto rate budget detected ($([string]::Join(', ', $rl.Raw))). Flying close: pacing to stay just under it and avoid forced pauses." }
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
        if ((-not $script:DattoBudgetLogAt) -or (($now - $script:DattoBudgetLogAt).TotalSeconds -ge 10)) { $script:DattoBudgetLogAt = $now; Write-MigrationLog INFO "  $note" }
    }
}
function Register-Datto429Pace {
    param([int]$Status = 429)
    $p = $script:DattoPace
    [System.Threading.Monitor]::Enter($p.SyncRoot)
    try {
        $cur = [int]$p.GapMs
        $base = if ($cur -lt 150) { 300 } else { $cur }
        $learned = [int][math]::Min([int]$p.MaxMs, [int][math]::Ceiling($base * 1.5))
        $p.GapMs = $learned
        if ($Status -eq 503) {
            $txt = " Easing to about $learned ms between requests while it recovers; full speed returns once Datto answers normally."
        } else {
            $p.FloorMs = $learned
            $p.ReqCount = 0; $p.WindowStartTicks = [int64]0; $p.LastProbeTicks = [int64]0
            $txt = " Slowing the read rate to about $learned ms between requests and holding there; this settles after the first few."
        }
    } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
    return $txt
}
function Lz7e73f9e662 {
    param([int]$Gap, [int]$Floor)
    if ($Gap -le $Floor) { return $Gap }
    return [int][math]::Max($Floor, [math]::Min($Gap - 25, [math]::Floor($Gap * 0.9)))
}
$script:DirectPutOk = $null
$script:SmallFilePutThreshold = 60MB
$script:OmitFsi = $false
$script:PreserveDates = $true
$script:ProvColsOn = $false
$script:ProvOwnerAvailable = $false
$script:ProvColReady = $null
$script:FolderColRules = @()
$script:FilenameColRules = @()
$script:ExtCatRules = @()
$script:RetentionYears = 0
$script:SweepList = $null
$script:PosixSrc = $false
$script:AuditFile = $null
$script:AuditWriteFails = 0
$script:UnreadableCount = 0
$script:UnreadableSpaces = @()
$script:ExitCode  = 0
$script:StopTag = '##CLEANSTOP##'
$script:SrcNoun     = 'Datto'
$script:SrcSysName  = 'Datto Workplace'
$script:SrcNounBare = 'Datto'
$script:SrcItem    = 'project'
$script:SrcItemCap = 'Project'
$script:SrcItems   = 'projects'
$script:ChunkSize = 10MB
$script:SpoolEncrypt = $true
$script:SpoolKey = $null
$script:TrialFileLimit = 20
$script:TrialCap = $null
$script:TrialFilesRemaining = 0
$script:TrialCapped = $false
$script:TrialNotAttempted = 0
$script:TrialLedgerKey = $null
$script:TrialBucket = ''
$script:LicencePublicKey = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEMOOjrKfrPG0mI1XtA+iXZVOwtjp075WeGEYaNZxG0TyVvAp6B9SZ3AAX5Ue7AxQrrwTfDzzX2lIgT7TmVKt9XA=='
$script:LicenceInfo = $null
$script:ScopeRefId = ''
$script:GraphSession = $null
$script:ListedTotal = 0
$script:Vitals = $null
$script:VitalsBusy = $false
$script:VitalsPipe = $null
$script:VitalsWin = @{ N = 0; Dl = 0.0; Up = 0.0 }
$script:VitalsTotals = @{ Rows = 0; Copied = 0; Bytes = [int64]0 }
$script:VitalsSummary = $null
$script:ExcludePatterns = @()
$script:SelectionRules = @{}
$script:SelectionKey = ''
$script:ExcludedFile = $null
$script:SelExcluded = [System.Collections.Generic.List[object]]::new()
$script:SelRuleHits = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:IncludePatterns = @()
$script:MaxFileBytes = [int64]0
$script:LargeFileBytes = 25MB
$script:ModifiedAfterUtc  = $null
$script:ModifiedBeforeUtc = $null
$script:AssessmentTopFiles = 20
$script:FindDuplicates = $true
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
function Get-EndpointRefusal {
    param([string]$Url)
    $h = ''; try { $h = ([uri]$Url).Host } catch { return "is not a valid web address ('$Url')" }
    $h = "$h".Trim('[', ']')
    if ($h -match '^(?i)(localhost|metadata(\..*)?)$' -or $h -match '(?i)\.(internal|local|localhost)$') { return "points at an internal host name ('$h')" }
    $isBad = {
        param([System.Net.IPAddress]$a)
        if ($a.IsIPv4MappedToIPv6) { $a = $a.MapToIPv4() }
        if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            $b = $a.GetAddressBytes()
            return (($b[0] -eq 10) -or ($b[0] -eq 127) -or ($b[0] -eq 0) -or ($b[0] -eq 169 -and $b[1] -eq 254) -or
                    ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168) -or
                    ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127))
        }
        if ([System.Net.IPAddress]::IsLoopback($a) -or $a.IsIPv6LinkLocal -or $a.IsIPv6SiteLocal) { return $true }
        $b6 = $a.GetAddressBytes()
        return (($b6[0] -band 0xFE) -eq 0xFC) -or ($a.Equals([System.Net.IPAddress]::IPv6Any))
    }
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($h, [ref]$ip)) {
        if (& $isBad $ip) { return "points at a private, loopback or link-local address ('$h')" }
        return ''
    }
    try {
        foreach ($a in @([System.Net.Dns]::GetHostAddresses($h))) {
            if (& $isBad $a) { return "names '$h', which resolves to a private, loopback or link-local address ($a)" }
        }
    } catch {}
    return ''
}
function Import-MigrationConfig {
    param([string] $Path)
    if (-not (Test-Path $Path)) { throw "Config not found at '$Path'." }
    $cfg = (Unprotect-ConfigText (Get-Content $Path -Raw)) | ConvertFrom-Json
    Expand-ConfigTokens $cfg
    if ((Test-ConfigProp $cfg 'run') -and $null -ne $cfg.run) {
        $liscBase = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Liscaragh'
        $rootDefaults = [ordered]@{ tempWorkingFolder = 'temp'; logRoot = 'logs'; reportRoot = 'reports'; stateRoot = 'state' }
        foreach ($rk in @($rootDefaults.Keys)) {
            $cur = ''
            if (Test-ConfigProp $cfg.run $rk) { $cur = "$($cfg.run.$rk)" }
            if (-not $cur.Trim()) {
                $rv = Join-Path $liscBase $rootDefaults[$rk]
                if (Test-ConfigProp $cfg.run $rk) { $cfg.run.$rk = $rv }
                else { $cfg.run | Add-Member -NotePropertyName $rk -NotePropertyValue $rv }
            }
        }
        if ((Test-ConfigProp $cfg 'datto') -and $null -ne $cfg.datto -and (Test-ConfigProp $cfg.datto 'sim') -and $null -ne $cfg.datto.sim) {
            if (-not (Test-ConfigProp $cfg.datto.sim 'rootPath')) { $cfg.datto.sim | Add-Member -NotePropertyName rootPath -NotePropertyValue '' }
            if (-not "$($cfg.datto.sim.rootPath)".Trim()) { $cfg.datto.sim.rootPath = (Join-Path $liscBase 'sim-source') }
        }
        if ((Test-ConfigProp $cfg 'destination') -and $null -ne $cfg.destination -and (Test-ConfigProp $cfg.destination 'sim') -and $null -ne $cfg.destination.sim) {
            if (-not (Test-ConfigProp $cfg.destination.sim 'rootPath')) { $cfg.destination.sim | Add-Member -NotePropertyName rootPath -NotePropertyValue '' }
            if (-not "$($cfg.destination.sim.rootPath)".Trim()) { $cfg.destination.sim.rootPath = (Join-Path $liscBase 'sim-dest') }
        }
    }
    if (-not ((Test-ConfigProp $cfg 'source')) -or $null -eq $cfg.source) {
        $cfg | Add-Member -NotePropertyName source -NotePropertyValue ([pscustomobject]@{ provider = 'Datto'; localRoots = @() }) -Force
    }
    if (-not ((Test-ConfigProp $cfg.source 'provider')) -or -not "$($cfg.source.provider)") { $cfg.source | Add-Member -NotePropertyName provider -NotePropertyValue 'Datto' -Force }
    if (-not ((Test-ConfigProp $cfg.source 'localRoots')) -or $null -eq $cfg.source.localRoots) { $cfg.source | Add-Member -NotePropertyName localRoots -NotePropertyValue @() -Force }
    if ("$($cfg.source.provider)" -eq 'LocalFs') {
        $cfg.datto.provider = 'LocalSim'
        $script:SrcNoun = 'the source'; $script:SrcNounBare = 'source'; $script:SrcItem = 'source'; $script:SrcItemCap = 'Source'; $script:SrcItems = 'sources'
        $script:SrcSysName = 'local files and folders'
        if (((Test-ConfigProp $cfg.source 'posix')) -and $cfg.source.posix) { $script:PosixSrc = $true }
    }
    if (-not (Test-ConfigProp $cfg.run 'throttle') -or $null -eq $cfg.run.throttle) {
        $cfg.run | Add-Member -NotePropertyName throttle -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $__throttleDefaults = @{ maxRetries = 6; baseDelaySeconds = 5; honorRetryAfter = $true; timeoutSec = 120; transferTimeoutSec = 3600; sourceIdleTimeoutSec = 120; sourceReadAttempts = 3 }
    foreach ($__k in $__throttleDefaults.Keys) {
        if (-not (Test-ConfigProp $cfg.run.throttle $__k)) {
            $cfg.run.throttle | Add-Member -NotePropertyName $__k -NotePropertyValue $__throttleDefaults[$__k] -Force
        }
    }
    if (-not (Test-ConfigProp $cfg.run.throttle 'adaptive')) {
        $cfg.run.throttle | Add-Member -NotePropertyName adaptive -NotePropertyValue ([pscustomobject]@{ enabled = $true; minWorkers = 1; growAfterSeconds = 30 }) -Force
    }
    if ($cfg.datto.provider -ne 'LocalSim') {
        $eu = [string]$cfg.datto.endpointUrl
        if ($eu -and $eu -notmatch '^(?i)https://') {
            throw "The Datto endpoint URL must start with https:// so file transfers are encrypted. It is currently '$eu'. Correct it in Settings, under API settings."
        }
        if ($eu) {
            $why = Get-EndpointRefusal -Url $eu
            if ($why) { throw "The Datto endpoint URL $why, which the tool refuses so the Datto credential cannot be sent to an internal service. Use the public Datto Workplace API host." }
        }
    }
    foreach ($p in @($cfg.run.logRoot, $cfg.run.reportRoot, $cfg.run.stateRoot, $cfg.run.tempWorkingFolder)) {
        if ($p -and -not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    return $cfg
}
function Lz93fa3c46d9 {
    param($Config, [string] $Stage, [string] $Friendly = '')
    if (-not $Friendly) {
        $Friendly = switch ($Stage) {
            'api-transfer-FirstPass' { 'Full migration' }
            'api-transfer-Delta'     { 'Sync new and changed' }
            'api-sizecheck'          { 'Compare sizes' }
            'api-validation'         { 'Verify files arrived' }
            'api-destinv'            { 'Background destination read' }
            'api-discovery'          { 'List projects' }
            'api-preflight'          { 'Readiness checks' }
            'api-report'             { 'Build report' }
            'api-certificate'        { 'Completion certificate' }
            'api-finalize'           { 'Record outcome' }
            'api-permissions'        { 'Permissions plan' }
            'api-sourcereview'       { 'Datto source review' }
            'api-provenance'         { 'Provenance pack' }
            'api-test'               { 'Connection test' }
            default                  { $Stage }
        }
    }
    $script:LogFile = Join-Path $Config.run.logRoot ("$Friendly - " + (Get-Date -Format 'yyyy-MM-dd HH.mm.ss') + " - $Stage-$PID.log")
    $tv = Lzb0b39673dd
    Write-MigrationLog INFO ("=== Stage '$Stage' started (pid $PID" + $(if ($tv) { ", v$tv" } else { '' }) + ") ===")
    if ($Stage -match '^api-(transfer-|sizecheck|validation|preflight|drift|sourcereview)') { Lzf0e5c3d988 -Config $Config -Stage $Stage }
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
        throw "This job's settings file is encrypted for a different Windows account or machine, or the stored data is damaged and cannot be read here. Run the tool under the account that installed it, or re-run setup."
    }
}
function Get-ProtectedSecretFallback {
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
        if (-not $v) { $v = Get-ProtectedSecretFallback -Name $n }
        if (-not $v) { throw "Environment variable '$n' is empty (referenced by env: in config). In plain terms: a required password or secret has not been set up on this computer yet. Re-run the setup, or ask your IT contact to set it." }
        return $v
    }
    return $Value
}
function Get-RunspaceConfig {
    param($Config)
    try {
        if ("$($Config.datto.provider)" -in @('LocalSim','LocalFs')) { return $Config }
        if ("$($Config.datto.clientSecret)" -notmatch '^env:') { return $Config }
        $resolved = Resolve-Secret "$($Config.datto.clientSecret)"
        $copy = $Config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $copy.datto.clientSecret = $resolved
        return $copy
    } catch { return $Config }
}
$script:AppendWriters = @{}
$script:AppendCsvHeaders = @{}
function Get-AppendWriter {
    param([string]$Path)
    $k = [System.IO.Path]::GetFullPath($Path)
    $w = $script:AppendWriters[$k]
    if ($w) { if ([System.IO.File]::Exists($k)) { return $w }; try { $w.Dispose() } catch {}; $script:AppendWriters.Remove($k); $script:AppendCsvHeaders.Remove($k) }
    $fs = [System.IO.FileStream]::new($k, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    $w = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
    $w.AutoFlush = $true
    $script:AppendWriters[$k] = $w
    return $w
}
function Close-AppendWriters {
    param([string]$Path = '')
    try {
        $keys = if ($Path) { @([System.IO.Path]::GetFullPath($Path)) } else { @($script:AppendWriters.Keys) }
        foreach ($k in $keys) {
            $w = $script:AppendWriters[$k]
            if ($w) { try { $w.Dispose() } catch {} }
            $script:AppendWriters.Remove($k)
            $script:AppendCsvHeaders.Remove($k)
        }
    } catch {}
}
function Add-AppendLine {
    param([string]$Path, [string]$Text)
    try { (Get-AppendWriter $Path).WriteLine($Text) } catch { Close-AppendWriters -Path $Path; throw }
}
function Get-CsvFileHeader {
    param([string]$Path)
    $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try { $sr = [System.IO.StreamReader]::new($fs, [System.Text.UTF8Encoding]::new($false), $true); $line = $sr.ReadLine() } finally { $fs.Dispose() }
    if (-not $line) { return ,@() }
    $o = @(@($line, $line) | ConvertFrom-Csv)
    return ,@($o[0].PSObject.Properties | ForEach-Object { $_.Name })
}
function Add-CsvRecord {
    param([string]$Path, $Row)
    if ($PSVersionTable.PSVersion.Major -lt 6) { $Row | Export-Csv -Path $Path -Append -NoTypeInformation -Encoding UTF8; return }
    try {
        $w = Get-AppendWriter $Path
        $k = [System.IO.Path]::GetFullPath($Path)
        $props = @($Row.PSObject.Properties | ForEach-Object { $_.Name })
        $cols = $script:AppendCsvHeaders[$k]
        if ($null -eq $cols -and $w.BaseStream.Length -gt 0) { $cols = Get-CsvFileHeader $k; $script:AppendCsvHeaders[$k] = $cols }
        if ($null -eq $cols) {
            foreach ($ln in @($Row | ConvertTo-Csv -NoTypeInformation)) { $w.WriteLine($ln) }
            $script:AppendCsvHeaders[$k] = $props
            return
        }
        foreach ($c in $cols) { if ($props -notcontains $c) { throw "Cannot append CSV content to the following file: $Path. The appended object does not have a property that corresponds to the following column: $c." } }
        $out = if (($props -join "`n") -ceq ($cols -join "`n")) { $Row } else { $Row | Select-Object -Property $cols }
        foreach ($ln in @($out | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1)) { $w.WriteLine($ln) }
    } catch { Close-AppendWriters -Path $Path; throw }
}
function Read-FileBytesShared {
    param([string]$Path)
    $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try { $ms = [System.IO.MemoryStream]::new(); $fs.CopyTo($ms); return ,$ms.ToArray() } finally { $fs.Dispose() }
}
function Write-MigrationLog {
    param([ValidateSet('INFO','WARN','ERROR','SKIP','OK')] [string] $Level, [string] $Message)
    $Message = [regex]::Replace("$Message", '[\r\n]+', ' '); $Message = [regex]::Replace($Message, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'o'), $Level, $Message
    $c = @{ ERROR='Red'; WARN='Yellow'; SKIP='DarkGray'; OK='Green'; INFO='Gray' }[$Level]
    Write-Host $line -ForegroundColor $c
    if ($script:LogFile) { try { Add-AppendLine -Path $script:LogFile -Text $line } catch { try { Add-Content -Path $script:LogFile -Value $line } catch {} } }
    Lz3c24fdf306
}
function Write-CrashDetail {
    param($ErrorRecord)
    $e = $ErrorRecord
    $emit = {
        param([string]$Level, [string]$Text)
        try { Write-MigrationLog $Level $Text } catch { Write-Host "[$Level] $Text" }
    }
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
}
function Get-SafeSum {
    param($Items, [string]$Property)
    if ($null -eq $Items) { $Items = @() } else { $Items = [object[]]$Items }
    if ($Property) {
        $m = $Items | Measure-Object -Property $Property -Sum -ErrorAction SilentlyContinue
    } else {
        $m = $Items | Measure-Object -Sum -ErrorAction SilentlyContinue
    }
    if ($m -and $null -ne $m.Sum) { [int64]$m.Sum } else { [int64]0 }
}
function Test-ConfigProp {
    param($Obj, [string]$Name)
    if ($null -eq $Obj -or -not $Name) { return $false }
    return ($null -ne $Obj.PSObject.Properties[$Name])
}
function Protect-CsvRow {
    param([Parameter(ValueFromPipeline=$true)]$Row)
    process {
        $o = [ordered]@{}
        foreach ($p in $Row.PSObject.Properties) {
            $val = $p.Value
            if ($val -is [string] -and $val.Length -gt 0 -and ("=+-@`t`r".IndexOf($val[0]) -ge 0)) { $val = "'" + $val }
            $o[$p.Name] = $val
        }
        [pscustomobject]$o
    }
}
function Import-AuditCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][Alias('LiteralPath')][string]$Path)
    $cols = 'Space','SourcePath','DestPath','RenamedFrom','Reason','Error'
    foreach ($r in (Import-Csv -LiteralPath $Path)) {
        foreach ($c in $cols) {
            $pr = $r.PSObject.Properties[$c]
            if ($pr -and $pr.Value -is [string] -and $pr.Value.Length -gt 1 -and $pr.Value[0] -eq [char]39 -and ("=+-@`t`r".IndexOf($pr.Value[1]) -ge 0)) { $pr.Value = $pr.Value.Substring(1) }
        }
        $r
    }
}
function Write-AuditRecord {
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
        Renamed           = [bool](((Test-ConfigProp $Item 'Renamed')) -and $Item.Renamed)
        RenamedFrom       = if ((Test-ConfigProp $Item 'RenamedFrom')) { "$($Item.RenamedFrom)" } else { '' }
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
    try {
        $vt = $script:VitalsTotals; $vt.Rows++
        if (@('Copied','ZeroByte') -contains $Status) { $vt.Copied++; $vt.Bytes += [int64]$Item.Size }
        if (@('Copied','ZeroByte','VerifyFail') -contains $Status) { $vw = $script:VitalsWin; $vw.N++; $vw.Dl += [double]$DownloadMs; $vw.Up += [double]$DurationMs }
    } catch {}
    $ok = $false
    for ($i=1;$i -le 5;$i++){ try { Add-CsvRecord -Path $script:AuditFile -Row ($rec | Protect-CsvRow); $ok=$true; break } catch { Start-Sleep -Milliseconds (100*$i) } }
    if (-not $ok) { $script:AuditWriteFails++ }
}
$script:RenameFile     = $null
$script:CollisionFile  = $null
$script:RenameCount    = 0
$script:CollisionCount = 0
$script:RenameSeenDirs = $null
$script:FinalSeen      = $null
function Write-RenameRecord {
    param([string]$Space, [string]$Original, [string]$Final)
    $script:RenameCount++
    if ($script:RenameFile) { try { [pscustomobject][ordered]@{ Space=$Space; Original=$Original; Final=$Final } | Protect-CsvRow | ForEach-Object { Add-CsvRecord -Path $script:RenameFile -Row $_ } } catch {} }
    $dir = ($Final -replace '/[^/]*$','')
    $key = "$Space|$dir"
    if ($script:RenameSeenDirs -is [hashtable] -and -not $script:RenameSeenDirs.ContainsKey($key)) {
        $script:RenameSeenDirs[$key] = $true
        Write-MigrationLog INFO "  tidied name(s) to suit SharePoint in: $dir  (every change is listed in the report and the renames CSV)"
    }
}
function Lzed46702b7d {
    param([string]$Space, [string]$Final, [string]$FirstSource, [string]$SecondSource)
    $script:CollisionCount++
    if ($script:CollisionFile) { try { [pscustomobject][ordered]@{ Space=$Space; Final=$Final; FirstSource=$FirstSource; SecondSource=$SecondSource } | Protect-CsvRow | ForEach-Object { Add-CsvRecord -Path $script:CollisionFile -Row $_ } } catch {} }
    Write-MigrationLog WARN "  NAME COLLISION in [$Space]: '$SecondSource' and '$FirstSource' both become '$Final' after tidying. In plain terms: two $($script:SrcItem) items would land on the same SharePoint path, so one could overwrite the other. Both are in the collisions CSV and the report."
}
function Get-RowDestId {
    param($Row)
    $lib = ''; try { if ((Test-ConfigProp $Row 'TargetLibrary')) { $lib = "$($Row.TargetLibrary)".Trim() } } catch {}
    if ("$($Row.DestinationType)" -eq 'SharePoint' -and -not $lib) { $lib = 'Documents' }
    $pr = ''; try { if ((Test-ConfigProp $Row 'TargetPrincipal')) { $pr = "$($Row.TargetPrincipal)".Trim() } } catch {}
    return (@("$($Row.DestinationType)".Trim(), "$($Row.DestinationUrl)".Trim().TrimEnd('/'), $pr, $lib) -join '|').ToLowerInvariant()
}
function Get-AuditCollisionGroups {
    param($Config, $Rows)
    $destIdOf = @{}
    try { foreach ($m in @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')) { if (-not $destIdOf.ContainsKey("$($m.Space)")) { $destIdOf["$($m.Space)"] = (Get-RowDestId $m) } } } catch {}
    $byKey = [ordered]@{}
    foreach ($r in $Rows) {
        if (-not "$($r.DestPath)") { continue }
        if ("$($r.Status)" -ne 'Copied' -and "$($r.Status)" -ne 'ZeroByte') { continue }
        $k = "$($destIdOf["$($r.Space)"])|" + "$($r.DestPath)".ToLowerInvariant()
        if (-not $byKey.Contains($k)) { $byKey[$k] = New-Object System.Collections.Generic.List[object] }
        $byKey[$k].Add($r)
    }
    $groups = New-Object System.Collections.Generic.List[object]
    foreach ($k in $byKey.Keys) {
        $g = $byKey[$k]
        $srcs = @($g | ForEach-Object { "$($_.Space): $($_.SourcePath)" } | Sort-Object -Unique)
        if ($srcs.Count -gt 1) { $groups.Add([pscustomobject]@{ Dest = "$($g[0].DestPath)"; Sources = $srcs; Spaces = @($g | ForEach-Object { "$($_.Space)" } | Sort-Object -Unique) }) }
    }
    return $groups.ToArray()
}
function Resolve-SafeRelPathTracked {
    param([string]$Space, [string]$Rp, $Item, [string]$DestId = '', [string]$Prefix = '')
    $pfx = ("$Prefix" -replace '\\','/').Trim('/')
    if ($pfx) { $tail = $Rp; $Rp = "$pfx/$(("$tail" -replace '\\','/').TrimStart('/'))"; $safe = "$pfx/$(ConvertTo-SafeRelPath $tail)" }
    else { $safe = ConvertTo-SafeRelPath $Rp }
    if ($safe -ne $Rp) {
        Write-RenameRecord -Space $Space -Original $Rp -Final $safe
        if ($Item) { $Item | Add-Member -NotePropertyName Renamed -NotePropertyValue $true -Force; $Item | Add-Member -NotePropertyName RenamedFrom -NotePropertyValue $Rp -Force }
    }
    if ($script:FinalSeen -is [hashtable]) {
        $dk = if ($DestId) { $DestId } else { $Space }
        $k = "$dk|" + $safe.ToLowerInvariant()
        $me = "$Space|$Rp"
        if ($script:FinalSeen.ContainsKey($k)) {
            $prev = $script:FinalSeen[$k]
            if ($prev -ne $me) {
                $pSpace, $pRp = "$prev".Split('|', 2)
                $first = if ($pSpace -ne $Space) { "$pRp (from $pSpace)" } else { $pRp }
                $second = if ($pSpace -ne $Space) { "$Rp (from $Space)" } else { $Rp }
                Lzed46702b7d -Space $Space -Final $safe -FirstSource $first -SecondSource $second
            }
        }
        else { $script:FinalSeen[$k] = $me }
    }
    return $safe
}
function Get-PlannedDestPath {
    param($Config, [string]$EffSub, $Item)
    $planned = if ($EffSub) { ($EffSub.Trim('/') + '/' + $Item.RelativePath) } else { "$($Item.RelativePath)" }
    $planned = $planned -replace '\\','/'
    $orig = $planned
    if (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames) {
        $tailOnly = ("$($Item.RelativePath)" -replace '\\','/'); $planned = if ($EffSub) { $EffSub.Trim('/') + '/' + (ConvertTo-SafeRelPath $tailOnly) } else { ConvertTo-SafeRelPath $tailOnly }
    }
    $planned = Remove-PathTraversal $planned
    return @{ Path = $planned; Renamed = ($planned -ne $orig); From = $orig }
}
function Get-DestinationLabel {
    param($Row)
    if ("$($Row.DestinationType)" -eq 'OneDrive') { return "OneDrive of $($Row.TargetPrincipal)" }
    $lib = ''; try { if ((Test-ConfigProp $Row 'TargetLibrary')) { $lib = "$($Row.TargetLibrary)".Trim() } } catch {}
    if (-not $lib) { $lib = 'Documents' }
    return "$($Row.DestinationUrl) > $lib"
}
function Lz3402e3c9c5 {
    param([string]$Activity, [string]$Status, [int]$Current, [int]$Total, [int]$Id = 1)
    $pct = if ($Total -gt 0) { [int]([math]::Min(100, ($Current / $Total) * 100)) } else { 100 }
    try { Write-Progress -Id $Id -Activity $Activity -Status ("{0} ({1}/{2}, {3}%)" -f $Status,$Current,$Total,$pct) -PercentComplete $pct } catch {}
    Lz3c24fdf306
    return $pct
}
function Lz4e6a653a8d {
    param($Config)
    $m = [ordered]@{ Cpu=''; Cores=[Environment]::ProcessorCount; TotalRamMB=0; Os=''; OsBuild=''; PowerShell="$($PSVersionTable.PSVersion)"; TempDrive=''; TempDriveType=''; PowerPlan=''; OnBattery=''; Summary='' }
    $isWin = ($env:OS -eq 'Windows_NT')
    try { $t = "$($Config.run.tempWorkingFolder)"; if ($t -match '^([A-Za-z]):') { $m.TempDrive = $Matches[1].ToUpper() + ':' } } catch {}
    if ($isWin) {
        try { $cs = Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 5 -ErrorAction Stop; $m.TotalRamMB = [int]($cs.TotalPhysicalMemory / 1MB) } catch {}
        try { $cp = @(Get-CimInstance Win32_Processor -OperationTimeoutSec 5 -ErrorAction Stop)[0]; $m.Cpu = ("$($cp.Name)" -replace '\s+',' ').Trim() } catch {}
        try { $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop; $m.Os = "$($os.Caption)".Trim(); $m.OsBuild = "$($os.Version)" } catch {}
        try { $dv = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).DisplayVersion; if ($dv) { $m.OsBuild += " ($dv)" } } catch {}
        if ($m.TempDrive) {
            try {
                $part = @(Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_Partition -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { "$($_.DriveLetter)" -eq $m.TempDrive.Substring(0,1) })[0]
                if ($part) {
                    $pd = @(Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_PhysicalDisk -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { "$($_.DeviceId)" -eq "$($part.DiskNumber)" })[0]
                    if ($pd) {
                        $media = switch ([int]$pd.MediaType) { 3 { 'HDD' } 4 { 'SSD' } 5 { 'SCM' } default { 'disk' } }
                        $bus   = switch ([int]$pd.BusType)   { 7 { 'USB' } 8 { 'RAID' } 10 { 'SAS' } 11 { 'SATA' } 17 { 'NVMe' } 12 { 'SD' } 13 { 'MMC' } 15 { 'file-backed' } 16 { 'virtual' } default { '' } }
                        $m.TempDriveType = ("$media $bus").Trim()
                    }
                }
            } catch {}
            if (-not $m.TempDriveType) { try { $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($m.TempDrive)'" -OperationTimeoutSec 5 -ErrorAction Stop; if ($ld -and [int]$ld.DriveType -eq 4) { $m.TempDriveType = 'network share' } } catch {} }
        }
        try { $pc = (& powercfg.exe /getactivescheme 2>$null) -join ' '; if ($pc -match '\(([^)]+)\)\s*$') { $m.PowerPlan = $Matches[1] } } catch {}
        try { $bat = @(Get-CimInstance Win32_Battery -OperationTimeoutSec 5 -ErrorAction Stop); if ($bat.Count) { $m.OnBattery = $(if ([int]$bat[0].BatteryStatus -eq 1) { 'yes' } else { 'no (mains)' }) } else { $m.OnBattery = 'no battery' } } catch {}
    }
    $parts = @()
    if ($m.Cpu) { $parts += "$($m.Cpu), $($m.Cores) logical core(s)" } else { $parts += "$($m.Cores) logical core(s)" }
    if ($m.TotalRamMB) { $parts += "$([math]::Round($m.TotalRamMB/1024,1)) GB RAM" }
    if ($m.Os) { $parts += "$($m.Os) $($m.OsBuild)" }
    $parts += "PowerShell $($m.PowerShell)"
    if ($m.TempDrive) { $parts += "temp folder on $($m.TempDrive)$(if ($m.TempDriveType) { " ($($m.TempDriveType))" })" }
    if ($m.PowerPlan) { $parts += "power plan $($m.PowerPlan)" }
    if ($m.OnBattery) { $parts += "on battery: $($m.OnBattery)" }
    $m.Summary = ($parts -join '; ')
    return $m
}
function Lz2e1dd2a15d {
    param([string]$Drive)
    $v = $script:Vitals
    if (-not $Drive) { return $null }
    if ($v.Disk.ContainsKey($Drive)) { return $v.Disk[$Drive] }
    $set = $false
    if ($env:OS -eq 'Windows_NT') {
        try {
            $set = @{
                R   = New-Object System.Diagnostics.PerformanceCounter('LogicalDisk','Disk Read Bytes/sec',$Drive)
                W   = New-Object System.Diagnostics.PerformanceCounter('LogicalDisk','Disk Write Bytes/sec',$Drive)
                RMs = New-Object System.Diagnostics.PerformanceCounter('LogicalDisk','Avg. Disk sec/Read',$Drive)
                WMs = New-Object System.Diagnostics.PerformanceCounter('LogicalDisk','Avg. Disk sec/Write',$Drive)
                Q   = New-Object System.Diagnostics.PerformanceCounter('LogicalDisk','Current Disk Queue Length',$Drive)
            }
            foreach ($k in @($set.Keys)) { [void]$set[$k].NextValue() }
        } catch { $set = $false }
    }
    $v.Disk[$Drive] = $set
    return $set
}
function Lzdfe2735780 {
    param([string]$Drive)
    $o = @{ R=''; W=''; RMs=''; WMs=''; Q='' }
    $c = Lz2e1dd2a15d -Drive $Drive
    if (-not $c) { return $o }
    try {
        $o.R = [math]::Round($c.R.NextValue()/1MB, 2); $o.W = [math]::Round($c.W.NextValue()/1MB, 2)
        $o.RMs = [math]::Round($c.RMs.NextValue()*1000, 1); $o.WMs = [math]::Round($c.WMs.NextValue()*1000, 1)
        $o.Q = [math]::Round($c.Q.NextValue(), 1)
    } catch {}
    return $o
}
function Lzf0e5c3d988 {
    param($Config, [string]$Stage)
    if ($script:Vitals) { return }
    try {
        $root = "$($Config.run.reportRoot)"
        if (-not $root) { return }
        if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
        $iv = 10; try { if ($env:LISCARA_VITALS_SEC) { $iv = [math]::Max(1, [int]$env:LISCARA_VITALS_SEC) } } catch {}
        $base = Join-Path $root ("vitals-$Stage-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID")
        $proc = [System.Diagnostics.Process]::GetCurrentProcess()
        $v = @{
            Csv = "$base.csv"; Json = "$base.json"; IntervalSec = $iv; Stage = $Stage
            Started = [DateTime]::UtcNow; Last = [DateTime]::MinValue
            Phase = 'Start'; Space = ''
            Proc = $proc; ProcCpuPrev = $proc.TotalProcessorTime; Cores = [Environment]::ProcessorCount
            Machine = $null; Cpu = $null; Free = $null; CountersOk = $null
            Disk = @{}; TempDrive = ''; SrcDrive = ''
            NetPrev = $null; TopPrev = @{}
            Samples = New-Object System.Collections.Generic.List[object]
        }
        $script:Vitals = $v
        $v.Machine = Lz4e6a653a8d -Config $Config
        $v.TempDrive = "$($v.Machine.TempDrive)"
        $cols = 'TimestampUtc,ElapsedSec,Phase,Space,ProcCpuPct,MachineCpuPct,ProcWorkingSetMB,ProcPrivateMB,MachineFreeMB,TempDrive,TempReadMBps,TempWriteMBps,TempReadMs,TempWriteMs,TempQueue,SrcDrive,SrcReadMBps,SrcReadMs,SrcQueue,NetRecvMBps,NetSentMBps,Listed,Done,DoneBytes,SpoolDepth,SpoolCap,InQueue,WinFiles,WinAvgDownloadMs,WinAvgUploadMs,TopProcesses'
        [IO.File]::WriteAllText($v.Csv, $cols + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($v.Json, ([pscustomobject]@{ Version = 1; Stage = $Stage; StartedUtc = $v.Started.ToString('o'); IntervalSec = $iv; Csv = [IO.Path]::GetFileName($v.Csv); Machine = $v.Machine; ToolVersion = (Lzb0b39673dd) } | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        Write-MigrationLog INFO "Run vitals: sampling this computer every $iv s into $([IO.Path]::GetFileName($v.Csv)) (CPU, memory, disk, network and the copy pipeline; no file names). This computer: $($v.Machine.Summary)."
        Lz3c24fdf306 -Force
    } catch { $script:Vitals = $null }
}
function Lz883d31a1c9 {
    param([string]$Phase, [string]$Space = '', [string]$SourcePath = '', [string]$UnlessPhase = '')
    $v = $script:Vitals; if (-not $v) { return }
    try {
        if ($UnlessPhase -and $v.Phase -eq $UnlessPhase) { return }
        if (($v.Phase -ne $Phase -or $v.Space -ne $Space) -and (([DateTime]::UtcNow - $v.Last).TotalSeconds -gt 1)) { Lz3c24fdf306 -Force }
        $v.Phase = $Phase; $v.Space = $Space
        $v.SrcDrive = ''; if ($SourcePath -match '^([A-Za-z]):') { $v.SrcDrive = $Matches[1].ToUpper() + ':' }
        Lz3c24fdf306 -Force
    } catch {}
}
function Lz3c24fdf306 {
    param([switch]$Force)
    $v = $script:Vitals
    if (-not $v -or $script:VitalsBusy) { return }
    $now = [DateTime]::UtcNow
    if (-not $Force -and ($now - $v.Last).TotalSeconds -lt $v.IntervalSec) { return }
    $script:VitalsBusy = $true
    try {
        $dt = if ($v.Last -gt [DateTime]::MinValue) { ($now - $v.Last).TotalSeconds } else { 0 }
        $procPct = ''; $ws = ''; $pm = ''
        try {
            $v.Proc.Refresh()
            $cpuNow = $v.Proc.TotalProcessorTime
            if ($dt -gt 0) { $procPct = [math]::Round((($cpuNow - $v.ProcCpuPrev).TotalSeconds / $dt / $v.Cores) * 100, 1) }
            $v.ProcCpuPrev = $cpuNow
            $ws = [math]::Round($v.Proc.WorkingSet64 / 1MB); $pm = [math]::Round($v.Proc.PrivateMemorySize64 / 1MB)
        } catch {}
        $mc = ''; $free = ''
        if ($null -eq $v.CountersOk) {
            $v.CountersOk = $false
            if ($env:OS -eq 'Windows_NT') {
                try {
                    $v.Cpu  = New-Object System.Diagnostics.PerformanceCounter('Processor','% Processor Time','_Total')
                    $v.Free = New-Object System.Diagnostics.PerformanceCounter('Memory','Available MBytes')
                    [void]$v.Cpu.NextValue(); [void]$v.Free.NextValue()
                    $v.CountersOk = $true
                } catch { $v.Cpu = $null; $v.Free = $null }
            }
        }
        if ($v.CountersOk) { try { $mc = [math]::Round($v.Cpu.NextValue(), 1); $free = [math]::Round($v.Free.NextValue()) } catch {} }
        $td = Lzdfe2735780 -Drive $v.TempDrive
        $sd = Lzdfe2735780 -Drive $v.SrcDrive
        $recv = ''; $sent = ''
        try {
            $rb = [int64]0; $sb = [int64]0
            foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
                if ($ni.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up -or $ni.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }
                $st = $ni.GetIPStatistics(); $rb += [int64]$st.BytesReceived; $sb += [int64]$st.BytesSent
            }
            if ($v.NetPrev -and $dt -gt 0) { $recv = [math]::Round(($rb - $v.NetPrev.R) / 1MB / $dt, 2); $sent = [math]::Round(($sb - $v.NetPrev.S) / 1MB / $dt, 2) }
            $v.NetPrev = @{ R = $rb; S = $sb }
        } catch {}
        $top = ''
        try {
            $cur = @{}; $deltas = New-Object System.Collections.Generic.List[object]
            foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
                try {
                    if ($p.Id -eq $v.Proc.Id) { continue }
                    $t = $p.TotalProcessorTime.TotalSeconds
                    $cur[$p.Id] = @{ Name = $p.ProcessName; T = $t }
                    if ($v.TopPrev.ContainsKey($p.Id)) { $d = $t - $v.TopPrev[$p.Id].T; if ($d -gt 0) { $deltas.Add(@{ Name = $p.ProcessName; D = $d }) } }
                } catch {} finally { try { $p.Dispose() } catch {} }
            }
            $v.TopPrev = $cur
            if ($dt -gt 0 -and $deltas.Count) {
                $top = (@($deltas | Sort-Object { $_.D } -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) $([math]::Round($_.D / $dt / $v.Cores * 100))%" }) -join '; ')
            }
        } catch {}
        $listed = 0; try { $listed = [math]::Max([int]$script:ListedTotal, [int]$script:SrcTotal) } catch {}
        $depth = ''; $cap = ''; $inq = ''
        $pp = $script:VitalsPipe
        if ($pp) {
            try { if ($pp.Spool) { $depth = [int]$pp.Spool.Count; $cap = [int]$pp.Spool.BoundedCapacity } } catch {}
            try { if ($pp.InQ) { $inq = [int]$pp.InQ.Count } } catch {}
        }
        $w = $script:VitalsWin; $wn = [int]$w.N
        $wdl = if ($wn) { [math]::Round($w.Dl / $wn) } else { '' }
        $wup = if ($wn) { [math]::Round($w.Up / $wn) } else { '' }
        $w.N = 0; $w.Dl = 0.0; $w.Up = 0.0
        $tot = $script:VitalsTotals
        $row = [pscustomobject][ordered]@{
            TimestampUtc = $now.ToString('o'); ElapsedSec = [int]($now - $v.Started).TotalSeconds; Phase = $v.Phase; Space = $v.Space
            ProcCpuPct = $procPct; MachineCpuPct = $mc; ProcWorkingSetMB = $ws; ProcPrivateMB = $pm; MachineFreeMB = $free
            TempDrive = $v.TempDrive; TempReadMBps = $td.R; TempWriteMBps = $td.W; TempReadMs = $td.RMs; TempWriteMs = $td.WMs; TempQueue = $td.Q
            SrcDrive = $v.SrcDrive; SrcReadMBps = $sd.R; SrcReadMs = $sd.RMs; SrcQueue = $sd.Q
            NetRecvMBps = $recv; NetSentMBps = $sent
            Listed = $listed; Done = [int]$tot.Rows; DoneBytes = [int64]$tot.Bytes; SpoolDepth = $depth; SpoolCap = $cap; InQueue = $inq
            WinFiles = $wn; WinAvgDownloadMs = $wdl; WinAvgUploadMs = $wup; TopProcesses = $top
        }
        $v.Samples.Add($row)
        $cells = foreach ($pr in $row.PSObject.Properties) { $s = "$($pr.Value)"; if ($s -match '[",\r\n]') { '"' + ($s -replace '"','""') + '"' } else { $s } }
        [IO.File]::AppendAllText($v.Csv, (($cells -join ',') + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        $v.Last = $now
    } catch {} finally { $script:VitalsBusy = $false }
}
function Lz0349007f1e {
    param($V)
    $lines = New-Object System.Collections.Generic.List[string]
    $phases = New-Object System.Collections.Generic.List[object]
    $all = $V.Samples.ToArray()
    if (-not $all.Count) { return [pscustomobject]@{ Lines = @('no samples were taken'); Phases = @(); Machine = "$($V.Machine.Summary)"; Csv = [IO.Path]::GetFileName($V.Csv); Samples = 0 } }
    $avg = { param($rows, $name) $vals = @($rows | ForEach-Object { $x = "$($_.$name)"; if ($x -ne '') { [double]$x } }); if ($vals.Count) { [math]::Round(($vals | Measure-Object -Average).Average, 1) } else { $null } }
    $max = { param($rows, $name) $vals = @($rows | ForEach-Object { $x = "$($_.$name)"; if ($x -ne '') { [double]$x } }); if ($vals.Count) { [math]::Round(($vals | Measure-Object -Maximum).Maximum, 1) } else { $null } }
    $min = { param($rows, $name) $vals = @($rows | ForEach-Object { $x = "$($_.$name)"; if ($x -ne '') { [double]$x } }); if ($vals.Count) { [math]::Round(($vals | Measure-Object -Minimum).Minimum, 1) } else { $null } }
    $order = @(); foreach ($s in $all) { if ($order -notcontains $s.Phase) { $order += $s.Phase } }
    foreach ($ph in $order) {
        if ($ph -eq 'Start') { continue }
        $rows = @($all | Where-Object { $_.Phase -eq $ph })
        $first = [datetime]::Parse($rows[0].TimestampUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $last  = [datetime]::Parse($rows[-1].TimestampUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $dur = $last - $first
        $spaces = @($rows | ForEach-Object { $_.Space } | Where-Object { $_ } | Sort-Object -Unique).Count
        $p = [ordered]@{
            Phase = $ph; Samples = $rows.Count; Spaces = $spaces; Seconds = [int]$dur.TotalSeconds
            ProcCpuAvg = (& $avg $rows 'ProcCpuPct'); ProcCpuMax = (& $max $rows 'ProcCpuPct')
            MachineCpuAvg = (& $avg $rows 'MachineCpuPct'); MachineCpuMax = (& $max $rows 'MachineCpuPct')
            WorkingSetMaxMB = (& $max $rows 'ProcWorkingSetMB'); FreeMinMB = (& $min $rows 'MachineFreeMB')
            TempWriteMBpsAvg = (& $avg $rows 'TempWriteMBps'); TempWriteMsAvg = (& $avg $rows 'TempWriteMs'); TempReadMsAvg = (& $avg $rows 'TempReadMs'); TempQueueAvg = (& $avg $rows 'TempQueue')
            SrcReadMBpsAvg = (& $avg $rows 'SrcReadMBps'); SrcReadMsAvg = (& $avg $rows 'SrcReadMs'); SrcQueueAvg = (& $avg $rows 'SrcQueue')
            NetRecvMBpsAvg = (& $avg $rows 'NetRecvMBps'); NetSentMBpsAvg = (& $avg $rows 'NetSentMBps')
            DownloadMsAvg = (& $avg $rows 'WinAvgDownloadMs'); UploadMsAvg = (& $avg $rows 'WinAvgUploadMs')
            SpoolFullPct = $null; SpoolEmptyPct = $null; TopProcess = ''
        }
        $withCap = @($rows | Where-Object { "$($_.SpoolCap)" -ne '' -and [int]$_.SpoolCap -gt 0 })
        if ($withCap.Count) {
            $p.SpoolFullPct  = [int][math]::Round(100 * @($withCap | Where-Object { [int]$_.SpoolDepth -ge [int]$_.SpoolCap }).Count / $withCap.Count)
            $p.SpoolEmptyPct = [int][math]::Round(100 * @($withCap | Where-Object { [int]$_.SpoolDepth -eq 0 }).Count / $withCap.Count)
        }
        $tops = @($rows | ForEach-Object { "$($_.TopProcesses)" } | Where-Object { $_ } | ForEach-Object { ($_ -split ';')[0].Trim() -replace '\s+\d+%$','' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1)
        if ($tops.Count) { $p.TopProcess = $tops[0].Name }
        $phases.Add([pscustomobject]$p)
        $bits = @()
        $bits += "$ph$(if ($spaces -gt 1) { " ($spaces $($script:SrcItems))" }): $(Format-Duration $dur) over $($rows.Count) sample(s)"
        if ($null -ne $p.ProcCpuAvg) { $bits += "this tool used $($p.ProcCpuAvg)% of the processor on average (peak $($p.ProcCpuMax)%)" }
        if ($null -ne $p.MachineCpuAvg) { $bits += "the whole machine $($p.MachineCpuAvg)% (peak $($p.MachineCpuMax)%)" }
        if ($null -ne $p.WorkingSetMaxMB) { $bits += "memory up to $($p.WorkingSetMaxMB) MB$(if ($null -ne $p.FreeMinMB) { ", $($p.FreeMinMB) MB free at the lowest" })" }
        if ($null -ne $p.SrcReadMBpsAvg) { $bits += "source drive read $($p.SrcReadMBpsAvg) MB/s$(if ($null -ne $p.SrcReadMsAvg) { " at $($p.SrcReadMsAvg) ms" })" }
        if ($null -ne $p.TempWriteMBpsAvg) { $bits += "temp drive wrote $($p.TempWriteMBpsAvg) MB/s$(if ($null -ne $p.TempWriteMsAvg) { " at $($p.TempWriteMsAvg) ms" })" }
        if ($null -ne $p.NetRecvMBpsAvg) { $bits += "network in $($p.NetRecvMBpsAvg) MB/s, out $($p.NetSentMBpsAvg) MB/s" }
        if ($null -ne $p.SpoolFullPct) { $bits += "staging queue full $($p.SpoolFullPct)% and empty $($p.SpoolEmptyPct)% of the time" }
        if ($null -ne $p.UploadMsAvg) { $bits += "per file: read $($p.DownloadMsAvg) ms, upload $($p.UploadMsAvg) ms" }
        $lines.Add(($bits -join '; ') + '.')
    }
    $tr = @($phases | Where-Object { $_.Phase -eq 'Transfer' })
    if ($tr.Count) {
        $t = $tr[0]
        if ($t.Samples -lt 6) { $lines.Add("Pipeline: too short to judge ($($t.Samples) sample(s)); a run of a minute or more gives a reliable picture.") }
        elseif ($null -ne $t.SpoolFullPct) {
            if     ($t.SpoolFullPct -ge 60)  { $lines.Add("Pipeline: upload-bound. Staged files waited for an upload slot $($t.SpoolFullPct)% of the time, so the limit was the destination or the connection out, not this computer and not reading the source.") }
            elseif ($t.SpoolEmptyPct -ge 60) { $lines.Add("Pipeline: source-bound. The uploaders had nothing waiting $($t.SpoolEmptyPct)% of the time, so the limit was reading files from the source.") }
            else                              { $lines.Add("Pipeline: balanced between reading the source and uploading (staging queue full $($t.SpoolFullPct)%, empty $($t.SpoolEmptyPct)%).") }
        }
        if ($null -ne $t.MachineCpuAvg -and $t.MachineCpuAvg -ge 85) { $lines.Add("This computer was busy: the processor averaged $($t.MachineCpuAvg)% during the transfer$(if ($t.TopProcess) { " (busiest other program: $($t.TopProcess))" }). Other software was competing for it.") }
        elseif ($null -ne $t.ProcCpuAvg -and $t.ProcCpuAvg -ge 85) { $lines.Add("This tool was processor-bound during the transfer ($($t.ProcCpuAvg)% average): a faster processor or fewer uploaders would change the result.") }
        if ($null -ne $t.TempWriteMsAvg -and $t.TempWriteMsAvg -ge 20) { $lines.Add("The temp drive is slow: writes averaged $($t.TempWriteMsAvg) ms. Staging goes through it, so pointing run.tempWorkingFolder at a faster (local SSD) drive would help.") }
        if ($null -ne $t.FreeMinMB -and $t.FreeMinMB -lt 512) { $lines.Add("Memory ran low: only $($t.FreeMinMB) MB was free at one point. Close other programs or run on a machine with more memory.") }
    }
    $ls = @($phases | Where-Object { $_.Phase -eq 'Listing' })
    if ($ls.Count -and $null -ne $ls[0].SrcReadMBpsAvg -and $ls[0].SrcReadMBpsAvg -ge 1 -and $ls[0].Seconds -ge 60) { $lines.Add("Note: the source drive was read at $($ls[0].SrcReadMBpsAvg) MB/s during listing. Listing should only read names and sizes; sustained reads here mean something else on this computer (indexing, antivirus) was reading the files, or the share is slow to answer directory queries.") }
    if ("$($V.Machine.OnBattery)" -eq 'yes') { $lines.Add("This computer was running on battery, which usually caps processor and disk speed.") }
    return [pscustomobject]@{ Lines = $lines.ToArray(); Phases = $phases.ToArray(); Machine = "$($V.Machine.Summary)"; Csv = [IO.Path]::GetFileName($V.Csv); Samples = $all.Count }
}
function Lz162301ffe6 {
    $v = $script:Vitals; if (-not $v) { return $script:VitalsSummary }
    $sum = $null
    try {
        Lz3c24fdf306 -Force
        $sum = Lz0349007f1e -V $v
        $script:VitalsSummary = $sum
        $script:Vitals = $null
        try {
            [IO.File]::WriteAllText($v.Json, ([pscustomobject]@{ Version = 1; Stage = $v.Stage; StartedUtc = $v.Started.ToString('o'); EndedUtc = [DateTime]::UtcNow.ToString('o'); IntervalSec = $v.IntervalSec; Csv = [IO.Path]::GetFileName($v.Csv); Samples = $v.Samples.Count; Machine = $v.Machine; ToolVersion = (Lzb0b39673dd); Phases = $sum.Phases; Summary = $sum.Lines } | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        } catch {}
        Write-MigrationLog INFO "RUN VITALS (this computer during the run; $($v.Samples.Count) sample(s) in $([IO.Path]::GetFileName($v.Csv)), which the support bundle includes):"
        Write-MigrationLog INFO "  This computer: $($v.Machine.Summary)."
        foreach ($l in $sum.Lines) { Write-MigrationLog INFO "  $l" }
    } catch {
        $script:Vitals = $null
        try { Write-MigrationLog WARN "Run vitals: the end-of-run summary could not be built ($($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)). The samples are still in $([IO.Path]::GetFileName($v.Csv))." } catch {}
    }
    return $sum
}
function Get-RetryAfterSeconds {
    param($ErrorRecord)
    $ra = 0
    $h = $null; try { $h = $ErrorRecord.Exception.Response.Headers } catch {}
    if ($h) {
        foreach ($n in 'X-Rate-Limit-Retry-After-Seconds','Retry-After') {
            if ($ra) { break }
            try { $ra = [int](@($h.GetValues($n))[0]) } catch { try { $v = $h[$n]; if ($v) { $ra = [int]$v } } catch {} }
        }
        if (-not $ra) { try { $d = $h.RetryAfter.Delta; if ($d) { $ra = [int][math]::Ceiling($d.TotalSeconds) } } catch {} }
    }
    if ($ra -lt 0) { $ra = 0 }
    return $ra
}
function Lz3d9a7d46e6 {
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
function Test-TransientNetworkError {
    param($ErrorRecord)
    $status = $null; try { $status = $ErrorRecord.Exception.Response.StatusCode.value__ } catch {}
    if ($status) { return $false }
    $m = ''
    try { $ex = $ErrorRecord.Exception; $d = 0; while ($ex -and $d -lt 8) { $m += ' ' + $ex.GetType().FullName + ' ' + $ex.Message; $ex = $ex.InnerException; $d++ } } catch {}
    return ($m -match '(?i)SSL|secure channel|connection was closed|connection was forcibly|actively refused|timed out|timeout|reset by peer|unexpectedly closed|transport connection|underlying connection|SocketException|IOException|WebException|HttpRequestException')
}
function Test-RecentThrottle {
    param([int]$Seconds = 180)
    if (-not $script:LastThrottleUtc) { return $false }
    return (([datetime]::UtcNow - $script:LastThrottleUtc).TotalSeconds -lt $Seconds)
}
function Invoke-WithRetry {
    param([scriptblock] $Action, $Config, [string] $What = 'operation', [switch] $RetryNotFound, [switch] $QuietNotFound)
    $t = $Config.run.throttle
    $retryCodes = @(408, 429, 500, 502, 503, 504)
    if ($RetryNotFound) { $retryCodes += 404 }
    $throttleMax = [math]::Max([int]$t.maxRetries, 40)
    for ($a = 1; $a -le $throttleMax; $a++) {
        try { return & $Action }
        catch {
            $status = $null; try { $status = $_.Exception.Response.StatusCode.value__ } catch {}
            $ra = Get-RetryAfterSeconds $_
            $isThrottle = (@(429, 503) -contains $status)
            if ($isThrottle) { $script:LastThrottleUtc = [datetime]::UtcNow }
            $isTransient = Test-TransientNetworkError $_
            $cap = if ($isThrottle) { $throttleMax } else { [int]$t.maxRetries }
            if ($isTransient -and $_.Exception.Message -match 'no data received for') { $cap = [math]::Min($cap, [math]::Max([int]$script:SourceReadAttempts, 1)) }
            if ((($retryCodes -notcontains $status) -and (-not $isTransient)) -or $a -ge $cap) {
                if (-not ($QuietNotFound -and $status -eq 404)) {
                    $__edetail2 = $null; try { $__edetail2 = $_.ErrorDetails.Message } catch {}; Write-MigrationLog ERROR "$What failed (attempt $a): $($_.Exception.Message)$(if ($__edetail2) { ' [DIAG] ' + $__edetail2 })"
                }
                throw
            }
            $delay = Lz3d9a7d46e6 -Attempt $a -Throttle $t -RetryAfter $ra
            if ($isTransient) {
                Write-MigrationLog WARN "$What hit a network blip and is retrying in $delay s (attempt $a/$cap): $($_.Exception.Message). In plain terms: a brief connection glitch, not a real failure. It retries here so nothing has to wait for a later Sync."
            } elseif ($What -like 'Datto*' -and @(429,503) -contains $status) {
                $learnedTxt = Register-Datto429Pace -Status ([int]$status)
                $asked = [bool]($t.honorRetryAfter -and $ra)
                $pauseTxt = if ($asked) { "Pausing $delay s as it asked" } else { "It gave no wait time, so pausing $delay s before trying again (attempt $a; the pause grows each try)" }
                $whatTxt = if ([int]$status -eq 503) { "Datto is busy or briefly unavailable (HTTP 503)" } else { "Datto is limiting how fast we can read (HTTP $status)" }
                $tailTxt = if ([int]$status -eq 503) { "This is on Datto's side, not an error in the copy; it carries on by itself." } else { "This is normal on large projects, not an error, and it gets smarter after the first one or two." }
                Write-MigrationLog WARN "  $whatTxt. $pauseTxt.$learnedTxt $tailTxt"
                if ($script:GuiMode) {
                    $stTxt = if ([int]$status -eq 503) { "Datto is busy (HTTP 503); waiting ~$delay s, then trying again." } elseif ($asked) { "Datto asked us to wait ~$delay s (its rate limit)." } else { "Datto is rate limiting; waiting ~$delay s, then trying again." }
                    Write-Host "##STATUS##|$stTxt Resuming automatically, nothing is stuck."
                }
                if ($script:GuiMode) {
                    $gapNow = 0; try { $gapNow = [int]$script:DattoPace.GapMs } catch {}
                    Write-Host "##DATTOPACE##|$delay|$gapNow|$status"
                }
            } else {
                $why = if ($t.honorRetryAfter -and $ra) { "server asked for $ra s" } else { "backing off" }
                Write-MigrationLog WARN "$What retrying (HTTP $status): $why, waiting $delay s (attempt $a/$cap)."
            }
            if ($What -like 'Datto*') { $script:DattoPauseEvents++ } else { $script:RetryEvents++ }
            Start-Sleep -Seconds $delay
        }
    }
}
function ConvertTo-Slug { param([string] $Name) return ($Name -replace '[^\w\-]', '-') -replace '-+', '-' }
$script:RunTempRoot = $null
function ConvertTo-RunTempSlug {
    param([string]$Name)
    $s = (("$Name").ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
    if (-not $s) { $s = 'job' }
    return $s
}
function Get-RunTempRoot {
    param($Config)
    if ($script:RunTempRoot) { return $script:RunTempRoot }
    $job = ''
    try { $job = Split-Path (Split-Path "$($Config.run.reportRoot)" -Parent) -Leaf } catch {}
    $dir = Join-Path "$($Config.run.tempWorkingFolder)" ('lisc-' + (ConvertTo-RunTempSlug $job) + '-' + $PID)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:RunTempRoot = $dir
    return $dir
}
function Remove-RunTempRoot {
    if (-not $script:RunTempRoot) { return }
    $d = $script:RunTempRoot; $script:RunTempRoot = $null
    if ((Split-Path $d -Leaf) -notmatch ('^lisc-[a-z0-9-]+-' + $PID + '$')) { return }
    try { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop } }
    catch { try { Write-MigrationLog WARN "  could not remove this run's temp folder [$d]: $($_.Exception.Message). It is encrypted staging only, and the next run clears it." } catch {} }
}
function Clear-OrphanRunTemp {
    param([string]$TempRoot, [double]$MinAgeHours = 3)
    if (-not $TempRoot -or -not (Test-Path -LiteralPath $TempRoot)) { return 0 }
    $n = 0
    foreach ($d in @(Get-ChildItem -LiteralPath $TempRoot -Directory -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match($d.Name, '^lisc-[a-z0-9-]+-(\d{1,9})$')
        if (-not $m.Success) { continue }
        $owner = [int]$m.Groups[1].Value
        if ($owner -eq $PID) { continue }
        if (Get-Process -Id $owner -ErrorAction SilentlyContinue) { continue }
        if ($d.LastWriteTimeUtc -gt [datetime]::UtcNow.AddHours(-$MinAgeHours)) { continue }
        try { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop; $n++ } catch {}
    }
    return $n
}
function Test-DestructiveGate { param([switch]$Execute) if (-not $Execute){ Write-MigrationLog INFO "Preview only: nothing will be uploaded. In plain terms: this is a safe rehearsal. Use 'Full migration' when you are ready to do it for real." } return [bool]$Execute }
try { if ([System.Net.WebRequest]::DefaultWebProxy) { [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials } } catch {}
if (-not ('SpoolHttpException' -as [type])) {
    try { Add-Type -TypeDefinition 'public class SpoolHttpException : System.Exception { public object Response; public SpoolHttpException(string m, object r) : base(m) { Response = r; } }' -ErrorAction Stop } catch { if (-not ('SpoolHttpException' -as [type])) { throw } }
}
function Get-LiscHttpClient {
    param([bool]$Follow = $false)
    if (-not ('LiscHttp' -as [type])) {
        try { Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Http;
public static class LiscHttp {
    static readonly object Gate = new object();
    static HttpClient follow, noFollow;
    static HttpClient Make(bool f) {
        var h = new SocketsHttpHandler();
        h.AllowAutoRedirect = f;
        h.PooledConnectionLifetime = TimeSpan.FromMinutes(2);
        h.PooledConnectionIdleTimeout = TimeSpan.FromSeconds(60);
        h.DefaultProxyCredentials = CredentialCache.DefaultCredentials;
        var c = new HttpClient(h, true);
        c.Timeout = System.Threading.Timeout.InfiniteTimeSpan;
        return c;
    }
    public static HttpClient Get(bool f) {
        lock (Gate) {
            if (f) { if (follow == null) follow = Make(true); return follow; }
            if (noFollow == null) noFollow = Make(false); return noFollow;
        }
    }
}
"@ -ErrorAction Stop } catch { if (-not ('LiscHttp' -as [type])) { throw } }
    }
    return [LiscHttp]::Get($Follow)
}
function Invoke-LiscHttpSend {
    param($Request, [bool]$Follow = $false, [int]$TimeoutSec = 3600, [System.Net.Http.HttpCompletionOption]$Completion = [System.Net.Http.HttpCompletionOption]::ResponseContentRead)
    $c = Get-LiscHttpClient -Follow $Follow
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds([math]::Max($TimeoutSec, 1)))
    try { return $c.Send($Request, $Completion, $cts.Token) }
    catch { if ($cts.IsCancellationRequested) { throw ([System.TimeoutException]::new("The request to $($Request.RequestUri.Host) timed out after $TimeoutSec second(s).")) }; throw }
    finally { $cts.Dispose() }
}
function New-LiscIdleStream {
    param([System.IO.Stream]$Inner, [int]$IdleSec = 0)
    if ($IdleSec -le 0) { return $Inner }
    if (-not ('LiscIdleStream' -as [type])) {
        try { Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Threading.Tasks;
public class LiscIdleStream : Stream {
    readonly Stream inner; readonly int idleMs;
    public LiscIdleStream(Stream s, int ms) { inner = s; idleMs = ms; }
    public override int Read(byte[] b, int o, int c) {
        var t = inner.ReadAsync(b, o, c);
        if (!t.Wait(idleMs)) {
            var i = inner; Task.Run(() => { try { i.Dispose(); } catch { } });
            var _ = t.ContinueWith(x => { var e = x.Exception; }, TaskContinuationOptions.OnlyOnFaulted);
            throw new TimeoutException("Source read timed out: no data received for " + (idleMs / 1000) + " second(s).");
        }
        return t.Result;
    }
    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long o, SeekOrigin r) { throw new NotSupportedException(); }
    public override void SetLength(long v) { throw new NotSupportedException(); }
    public override void Write(byte[] b, int o, int c) { throw new NotSupportedException(); }
    protected override void Dispose(bool d) { if (d) { try { inner.Dispose(); } catch { } } base.Dispose(d); }
}
"@ -ErrorAction Stop } catch { if (-not ('LiscIdleStream' -as [type])) { throw } }
    }
    return ,[LiscIdleStream]::new($Inner, $IdleSec * 1000)
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
function Save-LocalSourceFile {
    param([string]$InFile, [string]$OutFile, [byte[]]$Key, [int]$IdleSec = 0)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $in = [System.IO.File]::OpenRead($InFile)
    try {
        $n = [int64]$in.Length
        $src = New-LiscIdleStream -Inner $in -IdleSec $IdleSec
        $hs = [System.Security.Cryptography.CryptoStream]::new($src, $md5, [System.Security.Cryptography.CryptoStreamMode]::Read)
        try {
            if ($Key) { Save-SpoolStream -InStream $hs -OutFile $OutFile -Key $Key | Out-Null }
            else { $out = [System.IO.File]::Create($OutFile); try { $hs.CopyTo($out) } finally { $out.Dispose() } }
        } finally { $hs.Dispose() }
        if ($n -le 0 -or $null -eq $md5.Hash) { return '' }
        return (([System.BitConverter]::ToString($md5.Hash)) -replace '-','').ToLowerInvariant()
    } finally { $in.Dispose(); $md5.Dispose() }
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
    $req = $null; $resp = $null
    try {
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
        foreach ($k in $Headers.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) }
        if ($null -ne $BodyBytes) { $req.Content = [System.Net.Http.ByteArrayContent]::new($BodyBytes) }
        elseif ($null -ne $BodyStream) { $req.Content = [System.Net.Http.StreamContent]::new($BodyStream) }
        else { $req.Content = [System.Net.Http.ByteArrayContent]::new([byte[]]::new(0)) }
        $req.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        if ($ContentLength -ge 0) { $req.Content.Headers.ContentLength = $ContentLength }
        if ($ContentRange) { [void]$req.Content.Headers.TryAddWithoutValidation('Content-Range', $ContentRange) }
        $resp = Invoke-LiscHttpSend -Request $req -Follow $false -TimeoutSec $TimeoutSec
        $body = ''; try { $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch {}
        if (-not $resp.IsSuccessStatusCode) {
            $hdrs = @{}; foreach ($hk in $resp.Headers) { $hdrs[$hk.Key] = @($hk.Value)[0] }
            throw ([SpoolHttpException]::new("HTTP $([int]$resp.StatusCode) from ${Uri}: $body", ([pscustomobject]@{ StatusCode = [pscustomobject]@{ value__ = [int]$resp.StatusCode }; Headers = $hdrs })))
        }
        return @{ Content = $body; StatusCode = [int]$resp.StatusCode }
    } finally { if ($resp) { $resp.Dispose() }; if ($req) { $req.Dispose() } }
}
function Invoke-SpoolDownload {
    param([string]$Uri, [hashtable]$Headers = @{}, [string]$OutFile, [byte[]]$Key, [int]$TimeoutSec = 3600, [int]$IdleSec = 0)
    $req = $null; $resp = $null
    try {
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)
        foreach ($k in $Headers.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) }
        $resp = Invoke-LiscHttpSend -Request $req -Follow $true -TimeoutSec $TimeoutSec -Completion ([System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        if (-not $resp.IsSuccessStatusCode) {
            $hdrs = @{}; foreach ($hk in $resp.Headers) { $hdrs[$hk.Key] = @($hk.Value)[0] }
            throw ([SpoolHttpException]::new("HTTP $([int]$resp.StatusCode) from $Uri", ([pscustomobject]@{ StatusCode = [pscustomobject]@{ value__ = [int]$resp.StatusCode }; Headers = $hdrs })))
        }
        $rs = New-LiscIdleStream -Inner $resp.Content.ReadAsStream() -IdleSec $IdleSec
        try { return (Save-SpoolStream -InStream $rs -OutFile $OutFile -Key $Key) } finally { $rs.Dispose() }
    } finally { if ($resp) { $resp.Dispose() }; if ($req) { $req.Dispose() } }
}
$script:SpoolHelperSource = (@('New-LiscIdleStream','Save-SpoolStream','Save-SpoolFile','Save-LocalSourceFile','Get-SpoolLength','Open-SpoolRead','Copy-SpoolToFile','Read-SpoolChunk','Send-SpoolHttp','Invoke-SpoolDownload','Get-LiscHttpClient','Invoke-LiscHttpSend') | ForEach-Object { "function $_ { $((Get-Item "function:$_").Definition) }" }) -join "`n"
function Lz02a0ce10c5 {
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
function Lz1338c7e606 {
    param($Config)
    if ("$($Config.source.provider)" -eq 'LocalFs') { Write-MigrationLog OK "Source: local files and folders ($(@($Config.source.localRoots).Count) root folder(s)). No source sign-in needed."; return }
    if ($Config.datto.provider -eq 'LocalSim') { Write-MigrationLog OK "Source ready: $($script:SrcSysName) ($($Config.datto.sim.rootPath))"; return }
    if ($script:GuiMode) { Write-Host "##STATUS##|Connecting to Datto..." }
    $null = Invoke-DattoApi -Config $Config -Path $Config.datto.apiPaths.listProjects
    Write-MigrationLog OK "Datto API authenticated (Basic auth)."
}
function Invoke-DattoApi {
    param($Config, [string]$Path, [hashtable]$Query)
    $uri = ($Config.datto.endpointUrl.TrimEnd('/')) + $Path
    if ($Query) { $uri += '?' + (($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }) -join '&') }
    $headers = Get-DattoAuthHeader -Config $Config
    Lz4cb83a379f
    $r = Invoke-WithRetry -Config $Config -What "Datto GET $Path" -Action {
        $resp  = Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -Headers $headers -TimeoutSec $script:HttpTimeoutSec
        $script:DattoLastHeaders = $resp.Headers
        $bytes = if ($resp.RawContentStream) { $resp.RawContentStream.ToArray() } else { [Text.Encoding]::UTF8.GetBytes([string]$resp.Content) }
        [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    }
    Update-DattoPaceFromHeaders -Headers $script:DattoLastHeaders
    return $r
}
function Get-DattoSpaces {
    param($Config)
    if ("$($Config.source.provider)" -eq 'LocalFs') {
        $roots = @(@($Config.source.localRoots) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        $leaves = @{}
        foreach ($r in $roots) { $l = Split-Path $r -Leaf; if (-not $l) { $l = $r }; $leaves[$l] = [int]$leaves[$l] + 1 }
        $out = @()
        foreach ($r in $roots) {
            $l = Split-Path $r -Leaf; if (-not $l) { $l = $r }
            $nm = if ($leaves[$l] -gt 1) { $par = ''; try { $par = Split-Path (Split-Path $r -Parent) -Leaf } catch {}; if ($par) { "$l ($par)" } else { $l } } else { $l }
            $out += [pscustomobject]@{ Id = $r; Name = $nm; Type = 'Team'; OwnerUpn = '' }
        }
        return $out
    }
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
    $items = if ($resp -is [System.Array]) { $resp } elseif ($f.collection -and (Test-ConfigProp $resp $f.collection)) { $resp.($f.collection) } else { $resp }
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
function Test-ItemTypeIncluded {
    param($leaf)
    if (-not $script:IncludePatterns.Count) { return $true }
    foreach ($pat in $script:IncludePatterns) { if ($leaf -like $pat) { return $true } }
    return $false
}
$script:LocalWalkJunkNames = @('thumbs.db','ehthumbs.db','ehthumbs_vista.db','desktop.ini','.DS_Store','~$*','*.tmp')
function Test-LocalWalkJunk {
    param($Item, [string]$Base)
    try {
        $rel = "$($Item.FullName)"
        if ($Base -and $rel.StartsWith($Base, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($Base.Length) }
        foreach ($seg in ($rel -split '[\\/]')) { if ($seg -eq '$RECYCLE.BIN' -or $seg -eq 'System Volume Information' -or $seg -eq 'RECYCLER') { return $true } }
        if (([int]$Item.Attributes -band 0x6) -eq 0) { return $false }
        foreach ($pat in $script:LocalWalkJunkNames) { if ($Item.Name -like $pat) { return $true } }
    } catch {}
    return $false
}
function ConvertTo-SelPath { param([string]$Path) return ("$Path" -replace '\\','/').Trim().Trim('/') }
function Import-SelectionRules {
    param([string]$Path)
    $script:SelectionRules = @{}; $script:SelectionKey = ''
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $raw = [System.IO.File]::ReadAllText($Path)
    if (-not "$raw".Trim()) { return }
    $j = $raw | ConvertFrom-Json
    if (-not (Test-ConfigProp $j 'Sources') -or $null -eq $j.Sources) { return }
    foreach ($sp in @($j.Sources.PSObject.Properties)) {
        $d = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $rules = $null; try { if ((Test-ConfigProp $sp.Value 'Rules')) { $rules = $sp.Value.Rules } } catch {}
        if ($null -eq $rules) { continue }
        foreach ($r in @($rules.PSObject.Properties)) {
            $k = ConvertTo-SelPath $r.Name; $v = "$($r.Value)".Trim().ToLowerInvariant()
            if ($k -and ($v -eq 'x' -or $v -eq 'i')) { $d[$k] = $v }
        }
        if ($d.Count) { $script:SelectionRules["$($sp.Name)"] = $d }
    }
    if ($script:SelectionRules.Count) {
        $script:SelectionKey = (([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($raw)) | Select-Object -First 8 | ForEach-Object { $_.ToString('x2') }) -join '')
    }
}
function Test-SelectionIncluded {
    param([string]$Space, [string]$Path)
    if (-not $script:SelectionRules.Count) { return $true }
    $rules = $script:SelectionRules["$Space"]
    if (-not $rules) { return $true }
    $p = ConvertTo-SelPath $Path
    while ($p) {
        if ($rules.ContainsKey($p)) { [void]$script:SelRuleHits.Add("$Space|$p"); return ($rules[$p] -ne 'x') }
        $i = $p.LastIndexOf('/'); if ($i -lt 0) { break }
        $p = $p.Substring(0, $i)
    }
    return $true
}
function Lz322e5690da {
    param([string]$Space, [string]$Path)
    if (-not $script:SelectionRules.Count) { return $false }
    $rules = $script:SelectionRules["$Space"]
    if (-not $rules) { return $false }
    $fp = ConvertTo-SelPath $Path
    if (-not $fp -or (Test-SelectionIncluded -Space $Space -Path $fp)) { return $false }
    $pre = "$fp/"
    foreach ($k in $rules.Keys) { if ($rules[$k] -eq 'i' -and $k.StartsWith($pre, [System.StringComparison]::OrdinalIgnoreCase)) { return $false } }
    return $true
}
function Lz101cfc999d {
    param([string]$Space, [string]$SourcePath, [int64]$SizeBytes = 0, [string]$Kind = 'File')
    $row = [pscustomobject][ordered]@{ Space = $Space; SourcePath = $SourcePath; SizeBytes = $SizeBytes; Kind = $Kind }
    [void]$script:SelExcluded.Add($row)
    if ($script:ExcludedFile) { try { $row | Protect-CsvRow | ForEach-Object { Add-CsvRecord -Path $script:ExcludedFile -Row $_ } } catch {} }
}
function Lzc9d8fe4f48 {
    $script:SelExcluded.Clear(); $script:SelRuleHits.Clear()
}
function Select-IncludedItems {
    param($Items)
    if (-not ($script:ExcludePatterns.Count -or $script:IncludePatterns.Count -or $script:MaxFileBytes -gt 0 -or $script:ModifiedAfterUtc -or $script:ModifiedBeforeUtc -or $null -ne $script:FailedOnlySet)) { return $Items }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($it in @($Items)) {
        $leaf = ($it.RelativePath -split '/')[-1]
        $skip = $false
        foreach ($pat in $script:ExcludePatterns) { if ($leaf -like $pat) { $skip = $true; break } }
        if (-not $skip -and -not (Test-ItemTypeIncluded $leaf)) { $skip = $true }
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
    if (-not (Test-ItemTypeIncluded $leaf)) { return $false }
    if ($script:MaxFileBytes -gt 0 -and [int64]$it.Size -gt $script:MaxFileBytes) { return $false }
    if (-not (Test-ItemInDateWindow $it)) { return $false }
    if (-not (Test-ItemInFailedSet $it)) { return $false }
    return $true
}
function Build-FailedOnlySet {
    param($Config, [string]$AuditPath)
    if (-not $AuditPath) {
        $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $AuditPath = $latest.FullName }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) { throw "$($script:StopTag)Rerun failed only: no run audit found in $($Config.run.reportRoot). There is no record of a previous run to take the failed files from. Run 'Sync new and changed' instead." }
    $rows = $null
    try { $rows = @(Import-AuditCsv $AuditPath) } catch { throw "$($script:StopTag)Rerun failed only: the audit could not be read ($($_.Exception.Message)). Run 'Sync new and changed' instead. Audit: $AuditPath" }
    if (-not $rows.Count) { throw "$($script:StopTag)Rerun failed only: the audit is empty. Run 'Sync new and changed' instead. Audit: $AuditPath" }
    $cols = @($rows[0].PSObject.Properties.Name)
    if (($cols -notcontains 'Status') -or ($cols -notcontains 'SourcePath') -or ($cols -notcontains 'Space')) {
        throw "$($script:StopTag)Rerun failed only: $([System.IO.Path]::GetFileName($AuditPath)) is not a run audit (it has no Status/SourcePath/Space columns). Pick a real run's audit, or run 'Sync new and changed'."
    }
    $failStatuses = @('Error','DownloadError','VerifyFail','SkippedTooLarge')
    $failed = @($rows | Where-Object { $failStatuses -contains "$($_.Status)" })
    if (-not $failed.Count) { throw "$($script:StopTag)Rerun failed only: $([System.IO.Path]::GetFileName($AuditPath)) recorded no failed files, so there is nothing to rerun. If you expected failures, check you picked the right run." }
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in $failed) { [void]$set.Add(("$($r.Space)" + [char]0 + "$($r.SourcePath)")) }
    Write-MigrationLog WARN "RERUN FAILED ONLY: re-copying just the $($failed.Count) file(s) that failed in $([System.IO.Path]::GetFileName($AuditPath)). Everything else is left exactly as it is."
    return $set
}
function New-SpaceRef {
    param($Row, $Config = $null)
    $sub = ''
    try { if ((Test-ConfigProp $Row 'SourceSubPath')) { $sub = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
    $co = $false
    try { if ((Test-ConfigProp $Row 'SourceContentsOnly')) { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    $isLocalFs = $false
    try { if ($Config -and "$($Config.source.provider)" -eq 'LocalFs') { $isLocalFs = $true } } catch {}
    if (-not $sub -and -not $isLocalFs) { $co = $false }
    return [pscustomobject]@{ Id = $Row.SpaceId; Name = $Row.Space; SubPath = $sub; ContentsOnly = $co }
}
function Resolve-DattoSubPath {
    param($Config, $Space, [string]$SubPath)
    $f = $Config.datto.fields
    $parent = $Space.Id
    foreach ($seg in @($SubPath -split '/' | Where-Object { $_ })) {
        $childPath = ($Config.datto.apiPaths.listChildren -replace '\{parentID\}', [uri]::EscapeDataString("$parent"))
        $resp = Invoke-DattoApi -Config $Config -Path $childPath -Query @{}
        $items = if ($resp -is [System.Array]) { $resp } elseif ($f.collection -and ((Test-ConfigProp $resp $f.collection))) { $resp.($f.collection) } else { $resp }
        $hit = $null
        foreach ($it in @($items)) {
            $isFolder = $false; try { $isFolder = [bool]$it.($f.itemFolder) } catch {}
            if ($isFolder -and ("$($it.($f.itemName))" -eq $seg)) { $hit = $it; break }
        }
        if (-not $hit) { throw "SourceSubPath not found: no folder named '$seg' under '$($Space.Name)$(if($SubPath){"/$SubPath"})'. Check the path in mapping.csv. Spell it as Datto shows it (upper and lower case are treated the same), with / between folders and no leading slash." }
        $parent = $hit.($f.itemId)
    }
    return $parent
}
function Get-LocalReadPath {
    param([string]$FullName, [bool]$OnWindows = ($env:OS -eq 'Windows_NT'))
    if (-not $OnWindows -or -not $FullName -or $FullName.StartsWith('\\?\')) { return $FullName }
    if ($FullName -notmatch '[ .](\\|$)') { return $FullName }
    if ($FullName.StartsWith('\\')) { return ('\\?\UNC\' + $FullName.Substring(2)) }
    return ('\\?\' + $FullName)
}
function Get-DattoItems {
    param($Config, $Space, [scriptblock]$OnItem)
    $script:CurrentEnumSpace = "$($Space.Name)"
    Lz883d31a1c9 -Phase 'Listing' -Space "$($Space.Name)" -SourcePath $(if ($Config.datto.provider -eq 'LocalSim') { "$($Space.Id)" } else { '' }) -UnlessPhase 'Transfer'
    $subPath = ''
    try { if ((Test-ConfigProp $Space 'SubPath')) { $subPath = "$($Space.SubPath)" } } catch {}
    $contentsOnly = $false
    try { if ((Test-ConfigProp $Space 'ContentsOnly')) { $contentsOnly = [bool]$Space.ContentsOnly } } catch {}
    if ($subPath) {
        Write-MigrationLog WARN "  SOURCE IS SCOPED to [$subPath] inside [$($Space.Name)]. Only that folder is being listed. This is a partial view of the project: do not read the result as a complete migration of it."
        if ($contentsOnly) { Write-MigrationLog WARN "  CONTENTS ONLY is on for this project: the [$subPath] folder itself is NOT created at the destination; its contents land directly in the target folder. Only runs of this mapping with the setting on understand that layout: a run WITHOUT it would not find these files and would copy them again to [$subPath/...]." }
    }
    $scopeLabel = if ($subPath) { "$($Space.Name) / $subPath" } else { "$($Space.Name)" }
    if ($Config.datto.provider -eq 'LocalSim') {
        $base = $Space.Id
        if ($subPath) { $base = Join-Path $Space.Id ($subPath -replace '/','\') }
        if (-not (Test-Path $base)) { throw "SourceSubPath not found: '$subPath' does not exist under '$($Space.Name)'." }
        $isLocalFs = ("$($Config.source.provider)" -eq 'LocalFs')
        $rootSeed = ''
        if ($isLocalFs -and -not $contentsOnly) {
            $rootSeed = "$($Space.Name)"
            if (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames) { $rootSeed = ConvertTo-SafeRelPath $rootSeed }
        }
        $walkErrs = $null
        $phc = [ref]0
        $selOn = ($script:SelectionRules.Count -gt 0 -and $null -ne $script:SelectionRules["$($Space.Name)"])
        $list = @(Select-IncludedItems @(Get-ChildItem $base -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable walkErrs | Where-Object { -not (Test-LocalWalkJunk -Item $_ -Base $base) } | ForEach-Object {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\','/') -replace '\\','/'
            $selPath = if ($subPath) { "$subPath/$rel" } else { $rel }
            if ($subPath -and -not $contentsOnly) { $rel = "$subPath/$rel" }
            elseif ($rootSeed) { $rel = "$rootSeed/$rel" }
            if ($selOn -and -not (Test-SelectionIncluded -Space "$($Space.Name)" -Path $selPath)) { Lz101cfc999d -Space "$($Space.Name)" -SourcePath $rel -SizeBytes ([int64]$_.Length); return }
            $srcId = Get-LocalReadPath -FullName $_.FullName
            $h = ''
            Lz3c24fdf306
            if (([int]$_.Attributes -band 0x401000) -ne 0) { $phc.Value++ }
            $nfd = $false
            if ($script:PosixSrc) { $nfc = $rel.Normalize([System.Text.NormalizationForm]::FormC); if ($nfc -cne $rel) { $rel = $nfc; $nfd = $true } }
            [pscustomobject]@{ Id = $srcId; RelativePath = $rel; Size = $_.Length; ModifiedUtc = $_.LastWriteTimeUtc.ToString('o'); CreatedUtc = $_.CreationTimeUtc.ToString('o'); Hash = $h; NfdRenamed = $nfd }
        }))
        if ("$($Config.source.provider)" -eq 'LocalFs' -and $phc.Value -gt 0) {
            Write-MigrationLog WARN "  $($phc.Value) file(s) under [$scopeLabel] are cloud placeholders (their content lives in another sync service, e.g. OneDrive Files On-Demand). Copying them will download each one from that service first, which can be slow, and fails if that service is unreachable. For a faster, safer run, right-click those folders and choose 'Always keep on this device' first."
        }
        if (@($walkErrs).Count) {
            $badPaths = @($walkErrs | ForEach-Object { try { "$($_.TargetObject)" } catch { '' } } | Where-Object { $_ } | Sort-Object -Unique)
            if (-not $badPaths.Count) { $badPaths = @($walkErrs | ForEach-Object { "$($_.Exception.Message)" } | Sort-Object -Unique) }
            $script:UnreadableCount += @($badPaths).Count
            if (@($script:UnreadableSpaces) -notcontains $scopeLabel) { $script:UnreadableSpaces += $scopeLabel }
            Write-MigrationLog WARN "  ACCESS PROBLEM under [$scopeLabel]: $(@($badPaths).Count) folder(s)/file(s) could NOT be read and are NOT part of this run: $((@($badPaths | Select-Object -First 10)) -join ' ; ')$(if (@($badPaths).Count -gt 10) { ' ...and more' }). Grant this account read access, or store a sign-in for the share (Add folder offers this), then run again. A run that skips them is NOT a complete copy of the folder."
        }
        $script:SrcTotal = @($list).Count
        if ($OnItem) { foreach ($x in @($list)) { & $OnItem $x }; return (New-Object System.Collections.Generic.List[object]) }
        return $list
    }
    $f = $Config.datto.fields
    $meta = ''; try { if ($Config.datto.metadataParam) { $meta = $Config.datto.metadataParam } } catch {}
    $selOn = ($script:SelectionRules.Count -gt 0 -and $null -ne $script:SelectionRules["$($Space.Name)"])
    $out = New-Object System.Collections.Generic.List[object]
    $prog = @{ Folders = 0; Files = 0; Node = ''; LastLog = [DateTime]::MinValue }
    $suspects = New-Object System.Collections.Generic.List[object]
    $emitEnum = {
        param([switch]$Force)
        $now = [DateTime]::UtcNow
        if (-not $Force -and ($now - $prog.LastLog).TotalSeconds -lt 3) { return }
        $prog.LastLog = $now
        $w = if ($prog.Node) { "  now in: /$($prog.Node)" } else { '' }
        Write-MigrationLog INFO "  SOURCE [$scopeLabel]: $('{0:N0}' -f $prog.Folders) folder(s) read, $('{0:N0}' -f $prog.Files) file(s) found so far.$w"
        if ($script:GuiMode) { Write-Host "##STATUS##|Source: $('{0:N0}' -f $prog.Folders) folders, $('{0:N0}' -f $prog.Files) files so far  (reading the $($script:SrcNounBare) list, nothing uploads yet)" }
    }
    function Lz44bcce21b9 { param($ParentId, [string]$Prefix)
        $childPath = ($Config.datto.apiPaths.listChildren -replace '\{parentID\}', [uri]::EscapeDataString("$ParentId"))
        $q = @{}; if ($meta) { $q['metadata'] = $meta }
        $resp = Invoke-DattoApi -Config $Config -Path $childPath -Query $q
        $prog.Folders++; $prog.Node = $Prefix; & $emitEnum
        $items = if ($resp -is [System.Array]) { $resp } elseif ($f.collection -and ((Test-ConfigProp $resp $f.collection))) { $resp.($f.collection) } else { $resp }
        $n = @($items).Count
        if ($n -gt 0 -and (@(100,200,250,500,1000,2000,5000) -contains $n)) {
            $suspects.Add(@{ Path = $(if ($Prefix) { $Prefix } else { '(root)' }); Count = $n })
        }
        foreach ($it in @($items)) {
            $name = $it.($f.itemName)
            $rel = if ($Prefix) { "$Prefix/$name" } else { $name }
            $isFolder = $false; try { $isFolder = [bool]$it.($f.itemFolder) } catch {}
            $selPath = if ($contentsOnly -and $subPath) { "$subPath/$rel" } else { $rel }
            if ($isFolder) {
                if ($selOn -and (Lz322e5690da -Space "$($Space.Name)" -Path $selPath)) { Lz101cfc999d -Space "$($Space.Name)" -SourcePath $rel -Kind 'Folder'; continue }
                Lz44bcce21b9 -ParentId $it.($f.itemId) -Prefix $rel
            } else {
                $size = 0; try { $size = [int64]$it.($f.itemSize) } catch {}
                $md5 = ''; try { $md5 = "$($it.($f.itemHash))" } catch {}
                $modUtc = ''
                try {
                    $t = [int64]$it.($f.itemTime)
                    if ($t -gt 0) { $ms = if ($t -gt 100000000000) { $t } else { $t * 1000 }; $modUtc = [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime.ToString('o') }
                } catch {}
                $obj = [pscustomobject]@{ Id = "$($it.($f.itemId))"; RelativePath = $rel; Size = $size; ModifiedUtc = $modUtc; Hash = $md5 }
                if ($selOn -and -not (Test-SelectionIncluded -Space "$($Space.Name)" -Path $selPath)) { Lz101cfc999d -Space "$($Space.Name)" -SourcePath $rel -SizeBytes $size; continue }
                if (Test-ItemIncluded $obj) { $prog.Files++; if ($OnItem) { & $OnItem $obj } else { $out.Add($obj) } }
            }
        }
    }
    $startId = $Space.Id
    if ($subPath) { $startId = Resolve-DattoSubPath -Config $Config -Space $Space -SubPath $subPath }
    Lz44bcce21b9 -ParentId $startId -Prefix $(if ($contentsOnly) { '' } else { $subPath })
    & $emitEnum -Force
    $script:SrcTotal = $prog.Files
    Write-MigrationLog OK "  SOURCE [$scopeLabel] FINISHED: $('{0:N0}' -f $prog.Files) file(s) across $('{0:N0}' -f $prog.Folders) folder(s)."
    Lzbb47915d82 -Config $Config -Space $Space -Suspects $suspects
    return $out
}
$script:EnumCacheMaxAgeSec = 86400
function Lzef12084112 {
    param($Config, $Space)
    if (-not $Config.run.stateRoot) { return $null }
    return (Join-Path $Config.run.stateRoot ("enum-" + (ConvertTo-Slug "$($Space.Name)") + ".json"))
}
function Get-EnumFilterKey {
    $parts = @(
        'x=' + ((@($script:ExcludePatterns) | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object) -join ';')
        'i=' + ((@($script:IncludePatterns) | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object) -join ';')
        'm=' + [int64]$script:MaxFileBytes
        'a=' + $(if ($script:ModifiedAfterUtc)  { ([datetime]$script:ModifiedAfterUtc).ToUniversalTime().Ticks } else { '' })
        'b=' + $(if ($script:ModifiedBeforeUtc) { ([datetime]$script:ModifiedBeforeUtc).ToUniversalTime().Ticks } else { '' })
        'f=' + $(if ($null -ne $script:FailedOnlySet) { $fk = @(if ($script:FailedOnlySet -is [System.Collections.IDictionary]) { $script:FailedOnlySet.Keys } else { $script:FailedOnlySet }) | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object; "$($fk.Count):" + ((([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes(($fk -join "`n")))) | Select-Object -First 8 | ForEach-Object { $_.ToString('x2') }) -join '') } else { '' })
        's=' + "$script:SelectionKey"
    )
    return ($parts -join '|')
}
function Save-EnumCache {
    param($Config, $Space, $Items)
    $p = Lzef12084112 -Config $Config -Space $Space
    if (-not $p) { return }
    try {
        if (-not (Test-Path $Config.run.stateRoot)) { New-Item -ItemType Directory -Path $Config.run.stateRoot -Force | Out-Null }
        $sub = ''; try { if ((Test-ConfigProp $Space 'SubPath')) { $sub = "$($Space.SubPath)" } } catch {}
        $co = $false; try { if ((Test-ConfigProp $Space 'ContentsOnly')) { $co = [bool]$Space.ContentsOnly } } catch {}
        $now = [DateTime]::UtcNow
        [pscustomobject]@{
            Version        = 2
            SpaceId        = "$($Space.Id)"
            SpaceName      = "$($Space.Name)"
            SourceSubPath  = $sub
            ContentsOnly   = $co
            FilterKey      = (Get-EnumFilterKey)
            ListedUtcTicks = "$($now.Ticks)"
            ListedUtc      = $now.ToString('o')
            FileCount      = @($Items).Count
            Items          = @($Items)
        } | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $p -Encoding UTF8
    } catch {
        Write-MigrationLog INFO "  (could not save the file list for a later Resume: $($_.Exception.Message). Harmless: a Resume would read $($script:SrcNoun) again instead.)"
    }
}
function Get-SpaceItemsCached {
    param($Config, $Space)
    $sub = ''; try { if ((Test-ConfigProp $Space 'SubPath')) { $sub = "$($Space.SubPath)" } } catch {}
    $co = $false; try { if ((Test-ConfigProp $Space 'ContentsOnly')) { $co = [bool]$Space.ContentsOnly } } catch {}
    if ($script:UseEnumCache) {
        $p = Lzef12084112 -Config $Config -Space $Space
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
                elseif ($(((Test-ConfigProp $c 'ContentsOnly')) -and [bool]$c.ContentsOnly) -ne $co) { $why = 'the contents-only setting has changed since the list was saved' }
                elseif (-not ((Test-ConfigProp $c 'FilterKey')) -or "$($c.FilterKey)" -ne (Get-EnumFilterKey)) { $why = 'the file filters have changed since the list was saved' }
                elseif ($ageSec -gt $script:EnumCacheMaxAgeSec)  { $why = "the saved file list is too old ($([int]($ageSec/3600))h)" }
                else {
                    $items = @($c.Items)
                    foreach ($__ci in $items) { if ($null -eq $__ci) { continue }; foreach ($__dp in 'ModifiedUtc','CreatedUtc') { if ((Test-ConfigProp $__ci $__dp) -and ($__ci.$__dp -is [datetime])) { $__ci.$__dp = (ConvertTo-UtcInstant $__ci.$__dp).ToString('o') } } }
                    $when  = $listedUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
                    Write-MigrationLog WARN "  RESUMED FROM THE EARLIER FILE LIST taken at $when ($($items.Count) file(s)), so $($script:SrcNoun) was not read again. ANYTHING ADDED OR CHANGED AT THE SOURCE SINCE THEN IS NOT IN THIS RUN. In plain terms: that is true of any long run, because the list is always a snapshot from when it started, which is why you finish with a Sync. Run 'Sync new and changed' afterwards to pick up anything new."
    $__clean = New-Object System.Collections.Generic.List[object]
    for ($__i = 0; $__i -lt $items.Count; $__i++) {
        $__x = $items[$__i]
        if ($null -eq $__x) {
            Write-MigrationLog WARN "  DIAGNOSTIC (180bd): dropped a null entry at index $__i of $($items.Count) in [$($Space.Name)]'s file list - see DECISIONS 180bd for the root cause (a collapsed-empty-pipeline artifact). This should not happen now the walk itself is fixed; if you see this, some other path still hands back an unwrapped empty pipeline."
            continue
        }
        $__hasRel = $false; try { $__hasRel = ($null -ne $__x.PSObject.Properties['RelativePath']) } catch {}
        if (-not $__hasRel -or [string]::IsNullOrEmpty("$($__x.RelativePath)")) {
            $__propNames = try { ($__x.PSObject.Properties.Name -join ',') } catch { '<could not enumerate>' }
            $__typeName = try { $__x.GetType().FullName } catch { '<unknown>' }
            $__dump = try { ($__x | ConvertTo-Json -Compress -Depth 3) } catch { "<could not serialise: $($_.Exception.Message)>" }
            Write-MigrationLog WARN "  DIAGNOSTIC (180bd investigation): item index $__i of $($items.Count) in [$($Space.Name)] has no usable RelativePath. Type=$__typeName Properties=[$__propNames] Raw=$__dump"
        }
        $__clean.Add($__x)
    }
    $items = $__clean
                    return $items
                }
            } catch { $why = "the saved file list could not be read ($($_.Exception.Message))" }
        }
        Write-MigrationLog INFO "  reading the file list from $($script:SrcNoun) again, because $why."
    }
    $items = @(Get-DattoItems -Config $Config -Space $Space)
    Save-EnumCache -Config $Config -Space $Space -Items $items
    $__clean = New-Object System.Collections.Generic.List[object]
    for ($__i = 0; $__i -lt $items.Count; $__i++) {
        $__x = $items[$__i]
        if ($null -eq $__x) {
            Write-MigrationLog WARN "  DIAGNOSTIC (180bd): dropped a null entry at index $__i of $($items.Count) in [$($Space.Name)]'s file list - see DECISIONS 180bd for the root cause (a collapsed-empty-pipeline artifact). This should not happen now the walk itself is fixed; if you see this, some other path still hands back an unwrapped empty pipeline."
            continue
        }
        $__hasRel = $false; try { $__hasRel = ($null -ne $__x.PSObject.Properties['RelativePath']) } catch {}
        if (-not $__hasRel -or [string]::IsNullOrEmpty("$($__x.RelativePath)")) {
            $__propNames = try { ($__x.PSObject.Properties.Name -join ',') } catch { '<could not enumerate>' }
            $__typeName = try { $__x.GetType().FullName } catch { '<unknown>' }
            $__dump = try { ($__x | ConvertTo-Json -Compress -Depth 3) } catch { "<could not serialise: $($_.Exception.Message)>" }
            Write-MigrationLog WARN "  DIAGNOSTIC (180bd investigation): item index $__i of $($items.Count) in [$($Space.Name)] has no usable RelativePath. Type=$__typeName Properties=[$__propNames] Raw=$__dump"
        }
        $__clean.Add($__x)
    }
    $items = $__clean
    return $items
}
function Lzbb47915d82 {
    param($Config, $Space, $Suspects)
    if (-not $Suspects -or $Suspects.Count -eq 0) { return }
    $verified = @{}
    try {
        if ((Test-ConfigProp $Config.datto 'verifiedFolderCounts')) {
            foreach ($pr in $Config.datto.verifiedFolderCounts.PSObject.Properties) { $verified["$($pr.Name)"] = [int]$pr.Value }
        }
    } catch {}
    $toNote = @($Suspects | Where-Object { -not ($verified.ContainsKey($_.Path) -and $verified[$_.Path] -eq [int]$_.Count) })
    if (-not $toNote.Count) { return }
    Write-MigrationLog INFO "  Note, not a problem: $($toNote.Count) folder(s) in [$($Space.Name)] returned a round number of items (100, 200, ...), which is the shape a truncated listing would take, so they are flagged here for the record. Testing has confirmed Datto returns every child with no paging (folders come back with far more than 100), so these are genuine counts and nothing is missing. No action needed. To stop noting a folder you have counted in Datto, add it under datto.verifiedFolderCounts in config.json."
    foreach ($s in ($toNote | Sort-Object Path)) {
        Write-MigrationLog INFO "    [$($s.Path)] returned $($s.Count) items."
    }
}
function Lze8f6c57ef2 {
    param($Config, $Item, [string]$OutFile)
    if ($Config.datto.provider -eq 'LocalSim') {
        $h = Save-LocalSourceFile -InFile $Item.Id -OutFile $OutFile -Key $script:SpoolKey -IdleSec $script:SourceIdleSec
        if ($h) { $Item.Hash = $h }
        return $OutFile
    }
    $uri = ($Config.datto.endpointUrl.TrimEnd('/')) + ($Config.datto.apiPaths.downloadFile -replace '\{fileID\}', [uri]::EscapeDataString("$($Item.Id)"))
    $headers = Get-DattoAuthHeader -Config $Config
    Invoke-WithRetry -Config $Config -What "Datto download $($Item.RelativePath)" -Action {
        Lz4cb83a379f
        if ($script:SpoolKey) { Invoke-SpoolDownload -Uri $uri -Headers $headers -OutFile $OutFile -Key $script:SpoolKey -TimeoutSec $script:TransferTimeoutSec -IdleSec $script:SourceIdleSec | Out-Null }
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
        $x = $x -replace '[\uE000-\uF8FF]', '_'
        $x = $x.TrimStart([char]0x20)
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
function Remove-PathTraversal {
    param([string]$RelPath)
    $segs = ($RelPath -replace '\\','/') -split '/'
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($s in $segs) {
        if ($s -eq '') { continue }
        if ($s -match '^\.+$') { continue }
        if ($s -match '^[A-Za-z]:') { continue }
        $keep.Add($s)
    }
    return ($keep -join '/')
}
function Lz97c85d70a8 {
    param($Config, $Space)
    if ($Config.datto.provider -eq 'LocalSim') { return @() }
    if (-not $Config.datto.apiPaths.listPermissions) { return @() }
    $f = $Config.datto.fields
    try {
        $resp = Invoke-DattoApi -Config $Config -Path ($Config.datto.apiPaths.listPermissions -replace '\{spaceId\}', [uri]::EscapeDataString("$($Space.Id)"))
        return $resp.($f.collection) | ForEach-Object { [pscustomobject]@{ Principal = $_.($f.permPrincipal); Role = $_.($f.permRole) } }
    } catch { Write-MigrationLog WARN "  permissions unavailable for $($Space.Name)"; return @() }
}
function Invoke-AuthBroker {
    param([string]$Broker, $Config, [int]$CapSec = 120)
    $lic = ''
    try { if (((Test-ConfigProp $Config.run 'licenceFile')) -and $Config.run.licenceFile) { $lic = "$($Config.run.licenceFile)" } } catch {}
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
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Broker
    foreach ($a in $brokerArgs) { [void]$psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $bp = [System.Diagnostics.Process]::Start($psi)
    $outTask = $bp.StandardOutput.ReadToEndAsync(); $errTask = $bp.StandardError.ReadToEndAsync()
    if (-not $bp.WaitForExit($CapSec * 1000)) {
        try { $bp.Kill($true) } catch { try { $bp.Kill() } catch {} }
        throw "$($script:StopTag)Microsoft 365 sign-in did not respond within $CapSec seconds, so the run stopped. Nothing has been changed. This can happen during a network stall or a slow certificate check. Try again in a moment; if it keeps happening, contact support@liscaragh.com."
    }
    $bp.WaitForExit()
    $code = $bp.ExitCode
    $raw  = "$($outTask.GetAwaiter().GetResult())" + "$($errTask.GetAwaiter().GetResult())"
    $line = ($raw -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    $obj  = $null
    if ($line) { try { $obj = $line | ConvertFrom-Json } catch {} }
    $tokenOk = $obj -and ((Test-ConfigProp $obj 'token')) -and $obj.token
    if ($code -eq 0 -and $tokenOk) {
        $exp = [DateTimeOffset]::UtcNow.AddMinutes(45)
        try { if (((Test-ConfigProp $obj 'expiresOn')) -and $obj.expiresOn) { $exp = ([DateTimeOffset]::Parse("$($obj.expiresOn)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)).AddMinutes(-4) } } catch {}
        return [pscustomobject]@{ Token = "$($obj.token)"; Exp = $exp; Mode = "$($obj.mode)"; Customer = "$($obj.customer)" }
    }
    $reason = if ($obj -and ((Test-ConfigProp $obj 'reason'))) { "$($obj.reason)" } else { $raw.Trim() }
    if ($code -eq 2) {
        if ($script:GuiMode) { Write-Host "##LICENCE##|$reason" }
        throw "$($script:StopTag)This migration needs a valid licence. $reason Nothing has been changed. Obtain a licence at https://www.liscaragh.com, then install it via Help > Install licence file."
    }
    if ($code -eq 5) {
        $custMsg = "This installation has been modified or is damaged, so it will not run. Nothing has been changed. Re-run the installer to restore it. If it keeps happening, contact support@liscaragh.com."
        if ("$reason".Trim()) { Write-MigrationLog WARN "Integrity check detail: $reason" }
        if ($script:GuiMode) { Write-Host "##TAMPER##|$custMsg" }
        throw "$($script:StopTag)$custMsg"
    }
    throw "$($script:StopTag)Could not sign in to Microsoft 365. Nothing has been changed. $reason Check the internet connection and that the certificate and app registration are still in place, then try again. If it persists, contact support@liscaragh.com."
}
function Connect-Destination {
    param($Config)
    if ($Config.destination.provider -eq 'LocalSim') { Write-MigrationLog OK "Destination provider: LocalSim ($($Config.destination.sim.rootPath))"; return }
    if ($script:GuiMode) { Write-Host "##STATUS##|Connecting to Microsoft 365..." }
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) { throw "Microsoft.Graph module not installed (run: Install-Module Microsoft.Graph -Scope CurrentUser). In plain terms: the Microsoft 365 connection component is missing on this computer. Re-run the setup, or ask your IT contact to install it." }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $broker = Join-Path $PSScriptRoot 'LiscaraAuth.exe'
    if (-not (Test-Path $broker)) {
        throw "$($script:StopTag)Microsoft 365 sign-in is not available on this computer, so the run cannot start. Nothing has been changed. Re-run the installer to repair the installation, then try again. If it keeps happening, contact support@liscaragh.com."
    }
    $auth = Invoke-AuthBroker -Broker $broker -Config $Config
    Connect-MgGraph -AccessToken (ConvertTo-SecureString "$($auth.Token)" -AsPlainText -Force) -NoWelcome
    Set-GraphSessionState -Config $Config -Broker $broker -Exp $auth.Exp
    Write-MigrationLog OK "Microsoft 365 sign-in via the licence broker (LiscaraAuth): the token is bound to a verified licence."
    try { Write-MigrationLog INFO "This sign-in is valid until $($script:GraphSession.Exp.ToLocalTime().ToString('HH:mm:ss')); the run renews it automatically before then." } catch {}
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
        Write-MigrationLog WARN "Evaluation limits apply to this run."
    }
    if ($script:GraphSession) { $script:GraphSession.Tenant = $liveTenant }
    Write-MigrationLog OK "Connected to Graph (tenant $liveTenant)."
}
function Set-GraphSessionState {
    param($Config, [string]$Broker, $Exp)
    $testMin = 0
    try { if ("$env:LISCARA_GRAPH_REFRESH_TEST_MIN" -match '^\d+$') { $testMin = [int]$env:LISCARA_GRAPH_REFRESH_TEST_MIN } } catch {}
    if ($testMin -gt 0) {
        $short = [DateTimeOffset]::UtcNow.AddMinutes($testMin)
        if ($short -lt $Exp) { $Exp = $short }
    }
    $tenant = ''; if ($script:GraphSession) { $tenant = "$($script:GraphSession.Tenant)" }
    $script:GraphSession = [pscustomobject]@{ Config = $Config; Broker = $Broker; Exp = $Exp; RenewedUtc = [DateTimeOffset]::UtcNow; Tenant = $tenant; Renewals = 0 }
}
function Lz4629864ef0 {
    param([switch]$Force)
    $s = $script:GraphSession
    if (-not $s) { return $false }
    if (-not $Force -and [DateTimeOffset]::UtcNow -lt $s.Exp) { return $false }
    $renewals = [int]$s.Renewals + 1
    $auth = Invoke-AuthBroker -Broker $s.Broker -Config $s.Config
    Connect-MgGraph -AccessToken (ConvertTo-SecureString "$($auth.Token)" -AsPlainText -Force) -NoWelcome
    $prevTenant = "$($s.Tenant)"
    Set-GraphSessionState -Config $s.Config -Broker $s.Broker -Exp $auth.Exp
    $script:GraphSession.Tenant = $prevTenant
    $script:GraphSession.Renewals = $renewals
    $nowTenant = ''; try { $nowTenant = "$((Get-MgContext).TenantId)" } catch {}
    if ($prevTenant -and $nowTenant -and ($nowTenant -ne $prevTenant)) {
        throw "$($script:StopTag)The renewed Microsoft 365 sign-in belongs to a different organisation than this run started in, so the run was stopped to make sure data cannot go to the wrong place. Files already uploaded are safe. Check the job's tenant settings, then run 'Sync new and changed'."
    }
    $why = if ($Force) { 'Microsoft 365 refused the old one' } else { 'the previous one was about to expire' }
    Write-MigrationLog INFO "Microsoft 365 sign-in renewed ($why; renewal $renewals this run, next due around $($script:GraphSession.Exp.ToLocalTime().ToString('HH:mm'))). In plain terms: routine, the run carries on."
    return $true
}
function Get-GraphErrorStatus {
    param($ErrorRecord)
    $st = $null; try { $st = $ErrorRecord.Exception.Response.StatusCode.value__ } catch {}
    if ($null -eq $st) {
        $txt = ''; try { $txt = "$($ErrorRecord.Exception.Message) $($ErrorRecord.ErrorDetails.Message)" } catch {}
        if ($txt -match 'InvalidAuthenticationToken') { $st = 401 }
    }
    return $st
}
function Invoke-LiscGraphRequest {
    $a = $args
    [void](Lz4629864ef0)
    try { return (Invoke-MgGraphRequest @a) }
    catch {
        $status = Get-GraphErrorStatus $_
        $s = $script:GraphSession
        if ($status -ne 401 -or -not $s) { throw }
        if (([DateTimeOffset]::UtcNow - $s.RenewedUtc).TotalSeconds -lt 60) { throw }
        Write-MigrationLog WARN "Microsoft 365 rejected the sign-in (HTTP 401) before it was due to expire. Renewing it once and retrying."
        [void](Lz4629864ef0 -Force)
        return (Invoke-MgGraphRequest @a)
    }
}
function Join-SubPath { param([string]$A,[string]$B) $p=@(); foreach($x in @($A,$B)){ $t="$x".Trim('/'); if($t){ $p+=$t } }; return ($p -join '/') }
function Get-NestFolder {
    param($Config, $Row)
    $isLocalFs = $false
    try { if (((Test-ConfigProp $Config 'source')) -and $Config.source -and ("$($Config.source.provider)" -eq 'LocalFs')) { $isLocalFs = $true } } catch {}
    if ($isLocalFs) { return '' }
    $co = $false
    try { if ((Test-ConfigProp $Row 'SourceContentsOnly')) { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    if ($co) { return '' }
    $name = "$($Row.Space)"; if (-not $name) { return '' }
    if (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames) { $name = ConvertTo-SafeRelPath $name }
    return $name
}
function Get-GraphCollection {
    param($Config, [string]$Uri, [string]$What = 'list', [switch]$QuietNotFound)
    $values = [System.Collections.Generic.List[object]]::new()
    $pages = 0
    $next = $Uri
    while ($next) {
        $u = $next
        $resp = Invoke-WithRetry -Config $Config -What $What -QuietNotFound:$QuietNotFound -Action { Invoke-LiscGraphRequest -Method GET -Uri $u }
        $pages++
        foreach ($v in @($resp['value'])) { [void]$values.Add($v) }
        $next = $null
        try { if ($resp.ContainsKey('@odata.nextLink')) { $next = "$($resp['@odata.nextLink'])" } } catch {}
    }
    return @{ Values = $values; Pages = $pages }
}
function Resolve-DestinationDriveId {
    param($Config, $Row)
    $tsf = (@(("$($Row.TargetSubFolder)" -split '[\\/]') | Where-Object { $_ -ne '' }) -join '/')
    if ($Config.destination.provider -eq 'LocalSim') { return @{ DriveId = "sim:$($Row.DestinationUrl)"; SubFolder = (Join-SubPath $tsf (Get-NestFolder $Config $Row)) } }
    if ($Row.DestinationType -eq 'OneDrive') {
        if (-not $Row.TargetPrincipal) { throw "OneDrive target for '$($Row.Space)' needs a TargetPrincipal (the user's UPN) in mapping.csv. In plain terms: no user email was set for this project's OneDrive destination. Enter it in the destination box and save the mapping." }
        $upnEnc = [uri]::EscapeDataString($Row.TargetPrincipal)
        $d = $null
        try { $d = Invoke-WithRetry -Config $Config -What "OneDrive $($Row.TargetPrincipal)" -Action { Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$upnEnc/drive" } } catch { if ((Get-GraphErrorStatus $_) -eq 401) { throw }; $d = $null }
        if (-not $d) { throw "OneDrive not found for '$($Row.TargetPrincipal)'. In plain terms: that user's OneDrive could not be opened. Check the email is spelled correctly, the user has a Microsoft 365 licence, and they have opened their OneDrive at least once." }
        return @{ DriveId = $d['id']; SubFolder = (Join-SubPath $tsf (Get-NestFolder $Config $Row)) }
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
    try { $site = Invoke-WithRetry -Config $Config -What "Site $siteId" -Action { Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId" } } catch { if ((Get-GraphErrorStatus $_) -eq 401) { throw }; $site = $null }
    if (-not $site) { throw "SharePoint site not found for URL '$($Row.DestinationUrl)'. In plain terms: that SharePoint address could not be found. Copy the site address from your browser (it usually looks like https://host/sites/SiteName) and put any folder in the folder box." }
    $drives = @((Get-GraphCollection -Config $Config -Uri "https://graph.microsoft.com/v1.0/sites/$($site['id'])/drives" -What "Site libraries").Values)
    if (-not $drives.Count) { throw "No document library found in site '$($Row.DestinationUrl)'. In plain terms: this SharePoint site has no document library to upload into. Check you have the right site." }
    $lib = ''; if ((Test-ConfigProp $Row 'TargetLibrary')) { $lib = "$($Row.TargetLibrary)".Trim() }
    if ($lib) {
        $d = $drives | Where-Object { "$($_['name'])" -eq $lib } | Select-Object -First 1
        if (-not $d) { throw "Library '$lib' not found in site '$($Row.DestinationUrl)'. In plain terms: that document library name does not exist on the site. Pick one of these instead: $(@($drives | ForEach-Object { $_['name'] }) -join ', ')." }
    } else {
        $d = $null; $defErr = ''
        try {
            $def = Invoke-WithRetry -Config $Config -What "Default library of site $siteId" -Action { Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($site['id'])/drive" }
            if ($def -and $def['id']) { $d = $drives | Where-Object { "$($_['id'])" -eq "$($def['id'])" } | Select-Object -First 1 }
        } catch { $defErr = "$($_.Exception.Message)" }
        if (-not $d) {
            $names = (@($drives | ForEach-Object { "'$($_['name'])'" }) -join ', ')
            throw "Could not work out which library is the default for '$($Row.DestinationUrl)'$(if ($defErr) { " ($defErr)" }). In plain terms: no library name was set and Microsoft 365 would not say which one is the site's default, so nothing was copied rather than risk the wrong library. Try again, or type the library name in the destination (this site has: $names)."
        }
    }
    if (@($extra).Count) {
        $first = "$(@($extra)[0])"
        $libHit = @($drives | Where-Object { ("$($_['name'])" -eq $first) -or ($(try { [uri]::UnescapeDataString(("$($_['webUrl'])" -split '/')[-1]) } catch { '' }) -eq $first) }) | Select-Object -First 1
        if ($libHit) { Write-MigrationLog WARN "  the destination address for [$($Row.Space)] includes the library name '$first', so files land in a FOLDER called '$first' inside the '$($d['name'])' library. If that is not intended, put just the site address (https://host/sites/<name>) in the Site box and pick the library in the Library box." }
    }
    $subParts = @($extra) + @(($Row.TargetSubFolder -split '[\\/]') | Where-Object { $_ -ne '' })
    return @{ DriveId = $d['id']; SubFolder = (Join-SubPath ($subParts -join '/') (Get-NestFolder $Config $Row)) }
}
function Confirm-GraphFolderPath {
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
        $t = $Config.run.throttle
        $throttleMax = [math]::Max([int]$t.maxRetries, 40)
        for ($a = 1; $a -le $throttleMax; $a++) {
            try { Invoke-LiscGraphRequest -Method POST -Uri $parentUri -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null; break }
            catch {
                $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
                if ($st -eq 409) { break }
                $isThr = (@(429, 503) -contains $st)
                $isTr = ((@(408, 500, 502, 504) -contains $st) -or (Test-TransientNetworkError $_))
                if (($isThr -and $a -lt $throttleMax) -or ($isTr -and $a -lt [int]$t.maxRetries)) {
                    $delay = Lz3d9a7d46e6 -Attempt $a -Throttle $t -RetryAfter (Get-RetryAfterSeconds $_)
                    $script:RetryEvents++
                    Write-MigrationLog WARN "  creating destination folder '$cur' was refused (HTTP $st); waiting $delay s and trying again (attempt $a). In plain terms: Microsoft 365 asked the tool to slow down. Normal on busy runs."
                    Start-Sleep -Seconds $delay; continue
                }
                break
            }
        }
        $checkUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$([uri]::EscapeDataString($cur) -replace '%2F','/')"
        $seen = $false
        for ($w = 1; $w -le 10; $w++) {
            try { Invoke-LiscGraphRequest -Method GET -Uri $checkUri -ErrorAction Stop | Out-Null; $seen = $true; break }
            catch { Start-Sleep -Milliseconds 1000 }
        }
        if ($seen) { $script:EnsuredFolders["$DriveId|$cur"] = $true }
        else { Write-MigrationLog WARN "  destination folder '$cur' could not be confirmed yet; it will be checked again for the next file rather than assumed to exist." }
    }
}
function Lzd3568dac8e {
    param([string]$Url)
    try {
        $u = [Uri]$Url
        $segs = @(($u.AbsolutePath.Trim('/') -split '/') | Where-Object { $_ -ne '' })
        $sitePath = ''
        if ($segs.Count -ge 2 -and (@('sites','teams') -contains $segs[0].ToLower())) { $sitePath = "/$($segs[0])/$($segs[1])" }
        $siteId = if ($sitePath) { "$($u.Host):$sitePath" } else { $u.Host }
        return Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId" -ErrorAction Stop
    } catch { return $null }
}
function Get-GraphAppToken {
    param($Config)
    $broker = Join-Path $PSScriptRoot 'LiscaraAuth.exe'
    if (-not (Test-Path $broker)) {
        throw "$($script:StopTag)Microsoft 365 sign-in is not available on this computer, so the run cannot start. Nothing has been changed. Re-run the installer to repair the installation, then try again. If it keeps happening, contact support@liscaragh.com."
    }
    $auth = Invoke-AuthBroker -Broker $broker -Config $Config
    return @{ Token = $auth.Token; Exp = $auth.Exp }
}
function Update-WorkerToken {
    param($Holder, $Config)
    $now = [DateTimeOffset]::UtcNow
    if (-not (($now -gt $Holder.Exp) -or $Holder.ForceRefresh)) { return }
    if ($Holder.NextTry -and $now -lt $Holder.NextTry) { return }
    try {
        $tk = Get-GraphAppToken -Config $Config
        $Holder.Token = $tk.Token; $Holder.Exp = $tk.Exp; $Holder.ForceRefresh = $false; $Holder.Fails = 0; $Holder.NextTry = [DateTimeOffset]::MinValue
    } catch {
        $Holder.Fails = [int]$Holder.Fails + 1
        $Holder.NextTry = $now.AddSeconds([math]::Min(60, 5 * [int]$Holder.Fails))
        $m = (("$($_.Exception.Message)") -replace [regex]::Escape("$($script:StopTag)"), '').Trim()
        if ([int]$Holder.Fails -eq 1 -or ([int]$Holder.Fails % 10) -eq 0) {
            Write-MigrationLog ERROR "  the Microsoft 365 sign-in for the uploads could not be renewed (attempt $($Holder.Fails)): $m. Uploads will fail with 'unauthorised' until it is. It is retried automatically every minute at most."
        }
    }
}
function Set-GraphFileDates {
    param($Config, [string]$DriveId, [string]$EncPath, [string]$Mtime, [string]$Ctime = '', [switch]$ModifiedOnly)
    if (-not $script:PreserveDates -or $script:OmitFsi -or -not $Mtime) { return }
    $pm = [datetime]::MinValue
    $parseStyles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetime]::TryParse($Mtime, [Globalization.CultureInfo]::InvariantCulture, $parseStyles, [ref]$pm)) { return }
    $iso = ([datetimeoffset]$pm).UtcDateTime.ToString('o')
    $isoC = $iso
    if ($Ctime) { $pc = [datetime]::MinValue; if ([datetime]::TryParse($Ctime, [Globalization.CultureInfo]::InvariantCulture, $parseStyles, [ref]$pc)) { $isoC = ([datetimeoffset]$pc).UtcDateTime.ToString('o') } }
    try {
        Invoke-LiscGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${EncPath}:" `
            -Body (@{ fileSystemInfo = $(if ($ModifiedOnly) { @{ lastModifiedDateTime = $iso } } else { @{ createdDateTime = $isoC; lastModifiedDateTime = $iso } }) } | ConvertTo-Json -Depth 4) -ContentType 'application/json' | Out-Null
    } catch {
        $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($st -eq 400 -and -not $script:OmitFsi) {
            $script:OmitFsi = $true
            Write-MigrationLog WARN "  destination rejects the modified-date field; omitting it for the rest of this run. In plain terms: SharePoint would not accept the file's last-modified date, so the tool will stop sending it. Files still upload fine."
        }
    }
}
function Lz8580fccc73 {
    if ($null -eq $script:DirectPutOk) {
        try { $script:DirectPutOk = [bool]((Get-Command Invoke-MgGraphRequest -ErrorAction Stop).Parameters.ContainsKey('InputFilePath')) }
        catch { $script:DirectPutOk = $false }
    }
    return $script:DirectPutOk
}
function Send-GraphChunkFile {
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
    if (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames) {
        $relPath = Resolve-SafeRelPathTracked -Space $Space -Rp ("$($Item.RelativePath)" -replace '\\','/') -Item $Item -DestId "drive:$DriveId" -Prefix $TargetFolder
    }
    $relPath = Remove-PathTraversal $relPath
    if ($Config.destination.provider -eq 'LocalSim') {
        $dest = Join-Path $Config.destination.sim.rootPath ((ConvertTo-Slug ($DriveId -replace '^sim:','')) + '/' + $relPath)
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        if ($script:SpoolKey) { Copy-SpoolToFile -File $LocalFile -OutFile $dest -Key $script:SpoolKey }
        else { Copy-Item -LiteralPath $LocalFile -Destination $dest -Force }
        if ($script:PreserveDates -and $Item.ModifiedUtc) {
            try { (Get-Item $dest).LastWriteTimeUtc = ([datetimeoffset]::Parse("$($Item.ModifiedUtc)", [System.Globalization.CultureInfo]::InvariantCulture)).UtcDateTime } catch {}
        }
        return @{ Size = (Get-Item -LiteralPath $dest -Force).Length; Hash = (Lz02a0ce10c5 $dest); Path = $relPath; Method = 'LocalSim'; Retries = 0 }
    }
    if ($relPath -match '/') { Confirm-GraphFolderPath -Config $Config -DriveId $DriveId -FolderPath ($relPath -replace '/[^/]*$','') }
    $size = if ($script:SpoolKey) { Get-SpoolLength $LocalFile } else { (Get-Item $LocalFile).Length }
    $mtime = $Item.ModifiedUtc
    $ctime = ''; try { if (((Test-ConfigProp $Item 'CreatedUtc')) -and $Item.CreatedUtc) { $ctime = "$($Item.CreatedUtc)" } } catch {}
    $encPath = ([uri]::EscapeDataString($relPath) -replace '%2F','/')
    $finalResp = $null
    $dSize = 0; $dHash = ''; $directDone = $false
    $method = ''; $localRetries = 0
    if ($size -eq 0) {
        $method = 'Empty'
        $u = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${encPath}:/content"
        Invoke-WithRetry -Config $Config -What "upload(empty) $relPath" -Action {
            Invoke-LiscGraphRequest -Method PUT -Uri $u -Body ([byte[]]::new(0)) -ContentType 'application/octet-stream' | Out-Null
        }
        Set-GraphFileDates -Config $Config -DriveId $DriveId -EncPath $encPath -Mtime $mtime -Ctime $ctime
    } elseif ($size -le $script:SmallFilePutThreshold -and (Lz8580fccc73) -and -not $script:SpoolKey) {
        $putUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${encPath}:/content"
        try {
            $item = Invoke-WithRetry -Config $Config -What "put $relPath" -RetryNotFound -Action {
                Invoke-LiscGraphRequest -Method PUT -Uri $putUri -InputFilePath $LocalFile -ContentType 'application/octet-stream'
            }
            try { $dSize = [int64]$item['size'] } catch { try { $dSize = [int64]$item.size } catch {} }
            try { $dHash = [string]$item['file']['hashes']['quickXorHash'] } catch { try { $dHash = [string]$item.file.hashes.quickXorHash } catch {} }
            if ($dSize -gt 0 -or $script:OfficeTypes -contains ([System.IO.Path]::GetExtension($relPath)).ToLower()) {
                $directDone = $true; $method = 'DirectPut'
                Set-GraphFileDates -Config $Config -DriveId $DriveId -EncPath $encPath -Mtime $mtime -Ctime $ctime
            }
        } catch {
            Write-MigrationLog WARN "  direct PUT failed for ${relPath}; falling back to upload session: $($_.Exception.Message). In plain terms: the quick upload did not work for this file, so the tool is switching to the slower resumable method. Usually harmless, the file should still upload."
        }
    }
    if (-not $directDone -and $size -gt 0) {
        $sessUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${encPath}:/createUploadSession"
        $itemMeta = @{ '@microsoft.graph.conflictBehavior' = 'replace' }
        $parsedMtime = [datetime]::MinValue
        $hasFsi = $false
        if ($script:PreserveDates -and -not $script:OmitFsi -and $mtime -and [datetime]::TryParse($mtime, [ref]$parsedMtime)) {
            $isoM = ([datetimeoffset]$parsedMtime).UtcDateTime.ToString('o')
            $isoC = $isoM
            if ($ctime) { $pc = [datetime]::MinValue; if ([datetime]::TryParse($ctime, [ref]$pc)) { $isoC = ([datetimeoffset]$pc).UtcDateTime.ToString('o') } }
            $itemMeta['fileSystemInfo'] = @{ createdDateTime = $isoC; lastModifiedDateTime = $isoM }
            $hasFsi = $true
        }
        $sessBody = @{ item = $itemMeta } | ConvertTo-Json -Depth 5
        $chunk = $script:ChunkSize
        $t = $Config.run.throttle
        $strippedFsi = $false
        $sessThrottleMax = [math]::Max([int]$t.maxRetries, 40)
        for ($attempt = 1; $attempt -le $sessThrottleMax; $attempt++) {
            try {
                $sess = Invoke-LiscGraphRequest -Method POST -Uri $sessUri -Body $sessBody
                $uploadUrl = if ($sess -is [hashtable]) { $sess['uploadUrl'] } else { $sess.uploadUrl }
                if ($size -le $chunk) {
                    if ($script:SpoolKey) {
                        $sp = Open-SpoolRead -File $LocalFile -Key $script:SpoolKey
                        try { $plain = Read-SpoolChunk -Stream $sp.Stream -Count ([int]$size) } finally { $sp.Stream.Dispose() }
                        $finalResp = Send-GraphChunkFile -Config $Config -UploadUrl $uploadUrl -Bytes $plain -From 0 -To ($size - 1) -Total $size
                    } else {
                        $finalResp = Send-GraphChunkFile -Config $Config -UploadUrl $uploadUrl -FilePath $LocalFile -From 0 -To ($size - 1) -Total $size
                    }
                } elseif ($script:SpoolKey) {
                    $sp = Open-SpoolRead -File $LocalFile -Key $script:SpoolKey
                    try {
                        $pos = [int64]0
                        while ($true) {
                            $plain = Read-SpoolChunk -Stream $sp.Stream -Count ([int]$chunk)
                            if ($plain.Length -le 0) { break }
                            $finalResp = Send-GraphChunkFile -Config $Config -UploadUrl $uploadUrl -Bytes $plain -From $pos -To ($pos + $plain.Length - 1) -Total $size
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
                            $finalResp = Send-GraphChunkFile -Config $Config -UploadUrl $uploadUrl -FilePath $chunkTmp -From $pos -To ($pos + $read - 1) -Total $size
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
                        Write-MigrationLog WARN "  destination rejects the modified-date field; omitting it for the rest of this run. In plain terms: SharePoint would not accept the file's last-modified date, so the tool will stop sending it. Files still upload fine."
                    }
                    $sessBody = @{ item = @{ '@microsoft.graph.conflictBehavior' = 'replace' } } | ConvertTo-Json -Depth 5
                    Write-MigrationLog WARN "  createUploadSession 400 for ${relPath}: retrying without the modified-date field. In plain terms: the first upload attempt was refused, so the tool is retrying without the date. Usually harmless."
                    $script:RetryEvents++; $localRetries++
                    $attempt--
                    continue
                }
                $sessIsThr = (@(429, 503) -contains $st)
                if ($sessIsThr) { $script:LastThrottleUtc = [datetime]::UtcNow }
                if (($sessIsThr -and $attempt -lt $sessThrottleMax) -or ((@(401, 404, 408, 500, 502, 504) -contains $st) -and $attempt -lt $t.maxRetries) -or ((@(400, 409) -contains $st) -and (Test-RecentThrottle) -and $attempt -lt [math]::Min([int]$t.maxRetries, 3))) {
                    $ra = Get-RetryAfterSeconds $_
                    $delay = Lz3d9a7d46e6 -Attempt $attempt -Throttle $t -RetryAfter $ra
                    $why = if ($t.honorRetryAfter -and $ra) { "Microsoft asked us to wait $ra s" } else { "Microsoft 365 asked the tool to slow down or the connection blipped" }
                    Write-MigrationLog WARN "  upload retry for $relPath (HTTP $st): new session, waiting $delay s (attempt $attempt/$($t.maxRetries)). In plain terms: $why, so it will wait $delay seconds and try again. Normal on busy runs."
                    $script:RetryEvents++; $localRetries++
                    Start-Sleep -Seconds $delay; continue
                }
                $gBody = ''
                try { $gBody = $_.ErrorDetails.Message } catch {}
                if (-not $gBody) { try { $gBody = $_.Exception.Message } catch {} }
                if ($gBody) { Write-MigrationLog ERROR "  Graph reason for $relPath (HTTP $st): $gBody" }
                throw
            }
        }
        if ($method -ne 'UploadSession') { throw "the upload of $relPath did not complete: no upload attempt succeeded and none reported an error. Run 'Sync new and changed' to copy it again." }
    }
    if (-not $directDone) {
        if ($finalResp -and $finalResp.Content) {
            try { $item = $finalResp.Content | ConvertFrom-Json; $dSize = [int64]$item.size; try { $dHash = [string]$item.file.hashes.quickXorHash } catch {} } catch {}
        }
        if (-not $dSize) {
            Start-Sleep -Milliseconds 500
            $meta = Invoke-WithRetry -Config $Config -What "meta $relPath" -RetryNotFound -Action {
                Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$([uri]::EscapeDataString($relPath) -replace '%2F','/')"
            }
            try { $dSize = [int64]$meta['size'] } catch { try { $dSize = [int64]$meta.size } catch {} }
            try { $dHash = [string]$meta['file']['hashes']['quickXorHash'] } catch { try { $dHash = [string]$meta.file.hashes.quickXorHash } catch {} }
        }
    }
    if ($script:PreserveDates -and $null -ne $script:SweepList -and $mtime -and
        ($script:OfficeTypes -contains ([System.IO.Path]::GetExtension($relPath)).ToLower())) {
        $script:SweepList.Add(@{ Drive = $DriveId; Enc = $encPath; Rel = $relPath; Mtime = $mtime; Ctime = $ctime })
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
function Lz23003cb7de {
    param([string]$RelPath, [int64]$SourceSize, [int64]$DestSize)
    if ($SourceSize -eq 0) { return $true }
    if ($DestSize -le 0)   { return $false }
    if ($script:OfficeTypes -contains ([System.IO.Path]::GetExtension($RelPath)).ToLower()) { return $true }
    $tol = [math]::Max(65536, [int64]($SourceSize * 0.01))
    return ([math]::Abs($DestSize - $SourceSize) -le $tol)
}
function Lzd93f9ea715 {
    param($Repair, $Item, [string]$Status, [string]$Reason)
    if (-not $Repair -or $Repair.Count -eq 0) { return $Reason }
    if ($Status -ne 'Copied' -and $Status -ne 'ZeroByte') { return $Reason }
    $k = "$($Item.Id)"
    if (-not $Repair.ContainsKey($k)) { return $Reason }
    return "REPAIRED (an earlier run left a wrong-sized copy at the destination: $($Repair[$k])) | $Reason"
}
function Lz397101acd9 {
    param($Item, [string]$LocalFile, $DestInfo)
    $localSize = if ($script:SpoolKey) { Get-SpoolLength $LocalFile } else { (Get-Item $LocalFile).Length }
    if ($localSize -eq 0) { return @{ Ok = $true; Reason = 'zero-byte (accepted, flagged)'; Zero = $true } }
    $ext = ([System.IO.Path]::GetExtension($Item.RelativePath)).ToLower()
    if ($script:OfficeTypes -contains $ext) {
        if ([int64]$DestInfo.Size -gt 0) { return @{ Ok = $true; Reason = 'Office file accepted (M365 rewrites metadata)'; Zero = $false } }
        return @{ Ok = $false; Reason = 'Office file not stored (size 0 at destination)'; Zero = $false }
    }
    $dsz = [int64]$DestInfo.Size
    if ($dsz -eq $localSize) { return @{ Ok = $true; Reason = 'verified (size match)'; Zero = $false } }
    $tol = [math]::Max(65536, [int64]($localSize * 0.01))
    if ($dsz -gt 0 -and [math]::Abs($dsz - $localSize) -le $tol) {
        return @{ Ok = $true; Reason = "accepted (stored $dsz vs source $localSize, diff $($dsz - $localSize) bytes; likely M365 rewrite)"; Zero = $false }
    }
    return @{ Ok = $false; Reason = "size mismatch (dest $dsz vs $localSize)"; Zero = $false }
}
function ConvertTo-UtcInstant {
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    try { return ([datetimeoffset]::Parse("$Value", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)).UtcDateTime } catch { return $null }
}
function Lz631d6c8c21 {
    param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) { return [DateTime]::SpecifyKind($v, [DateTimeKind]::Utc) }
    $s = "$v".Trim()
    if (-not $s) { return $null }
    $pm = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$pm)) { return $pm }
    return $null
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
    catch { throw "$($script:StopTag)run.tuning.modifiedAfter/modifiedBefore must be a date (yyyy-MM-dd) or an ISO UTC timestamp. Got: '$v'." }
}
function Lz5406762c37 {
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
                    $drv = $null; try { $drv = Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($upn.Trim()))/drive" -ErrorAction Stop } catch { }
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
                    $siteObj = Lzd3568dac8e -Url $site.Trim()
                    if (-not $siteObj) { Write-Host "  Site not found at that URL. Check it, e.g. https://tenant.sharepoint.com/sites/Name. Try again." -ForegroundColor Yellow; continue }
                    $libs = @((Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($siteObj['id'])/drives")['value'] | ForEach-Object { $_['name'] })
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
    $sub = if (((Test-ConfigProp $Row 'TargetSubFolder')) -and $Row.TargetSubFolder) { $Row.TargetSubFolder } else { 'root' }
    if ($Row.DestinationType -eq 'OneDrive') {
        return "OneDrive [$($Row.TargetPrincipal)] folder [$sub]"
    }
    $lib = if (((Test-ConfigProp $Row 'TargetLibrary')) -and $Row.TargetLibrary) { $Row.TargetLibrary } else { 'Documents' }
    return "SharePoint [$($Row.DestinationUrl)] library [$lib] folder [$sub]"
}
function Lz9927b2b542 {
    param($Project, $Dest)
    return [pscustomobject]@{
        Space=$Project.Name; SpaceId=$Project.Id; SourceSubPath=''; SourceContentsOnly=''; Type='Project'; OwnerResolved='n/a'
        DestinationType=$Dest.DestinationType; DestinationUrl=$Dest.DestinationUrl
        TargetPrincipal=$Dest.TargetPrincipal; TargetLibrary=$Dest.TargetLibrary; TargetSubFolder=$Dest.TargetSubFolder
        Action=$Dest.Action; Notes=$Dest.Notes
    }
}
function Invoke-Discover {
    param($Config, [switch]$NonInteractive)
    Lz93fa3c46d9 -Config $Config -Stage 'api-discovery'
    Lz1338c7e606 -Config $Config
    if (-not $NonInteractive) { Connect-Destination -Config $Config }
    $projects = @(Get-DattoSpaces -Config $Config)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($NonInteractive) {
        foreach ($s in $projects) {
            $rows.Add((Lz9927b2b542 -Project $s -Dest @{ Action='MIGRATE'; DestinationType='SharePoint'; DestinationUrl="$($Config.destination.teamSiteBaseUrl)/$((ConvertTo-Slug $s.Name))"; TargetPrincipal=''; TargetLibrary=''; TargetSubFolder=''; Notes='auto (non-interactive)' }))
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
            $dest = Lz5406762c37 -Config $Config -Project $proj
            if ($dest.Action -eq 'MIGRATE') {
                $newRow = Lz9927b2b542 -Project $proj -Dest $dest
                $rows.Add($newRow)
                Write-Host ("  mapped: source [{0}] -> destination {1}" -f $proj.Name, (Format-Destination -Row $newRow)) -ForegroundColor Green
            } else {
                Write-Host ("  {0} left unmapped." -f $proj.Name) -ForegroundColor DarkGray
            }
            $remaining.RemoveAt($n - 1)
        }
    }
    if ($rows.Count -eq 0) { Write-MigrationLog WARN "No sources mapped, nothing to migrate. mapping.csv not written."; return }
    $out = Join-Path $Config.run.reportRoot 'mapping.csv'
    ($rows | Sort-Object Space) | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
    Write-MigrationLog OK "Discovery complete. $($rows.Count) $($script:SrcItem)(s) mapped. Review: $out"
}
function Lzb0489ee16b {
    param([string[]]$Paths)
    $ps = @($Paths | ForEach-Object { ("$_" -replace '\\','/').Trim('/') } | Where-Object { $_ })
    if (-not $ps.Count) { return '' }
    $segs = @($ps[0] -split '/')
    $cand = @(if ($segs.Count -gt 1) { $segs[0..($segs.Count - 2)] } else { @() })
    while ($cand.Count -gt 0) {
        $try = ($cand -join '/') + '/'
        $allIn = $true
        foreach ($p in $ps) { if (-not $p.StartsWith($try, [System.StringComparison]::OrdinalIgnoreCase)) { $allIn = $false; break } }
        if ($allIn) { return ($cand -join '/') }
        if ($cand.Count -ge 2) { $cand = @($cand[0..($cand.Count - 2)]) } else { $cand = @() }
    }
    return ''
}
function Get-ReportHeaderTitle {
    param([string]$Brand)
    $job = "$Brand"
    $job = $job -replace '\s*-\s*Liscaragh Migrate\s*$', ''
    $job = $job -replace '^\s*Liscaragh Migrate Report\s*-\s*', ''
    $job = $job.Trim()
    $t = 'Liscaragh Migrate Report'
    if ($job -and $job -ne 'Liscaragh Migrate') { $t = "$t - $job" }
    return $t
}
function Write-PreFlightReport {
    param($Config,$Summary,$Issues,$Largest,$Duplicates,[int]$DupGroups,[int64]$DupWasted,[int64]$AllBytes,[int]$FailCount,[int]$RenameCount,[string]$EstimateText,$DestCollisions,[int]$DestCollideGroups = 0,[bool]$DupChecked = $true,$FileMapSummary = $null,[int]$FileMapCount = 0,$SelExcluded = $null,[string[]]$SelStale = @(),[string]$DevFolderNote = '')
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    if ($null -eq $SelExcluded) { $SelExcluded = @() } else { $SelExcluded = [object[]]$SelExcluded }
    $SelStale = @($SelStale | Where-Object { "$_".Trim() })
    if ($null -eq $Summary)    { $Summary = @() }    else { $Summary = [object[]]$Summary }
    if ($null -eq $Issues)     { $Issues = @() }     else { $Issues = [object[]]$Issues }
    if ($null -eq $Largest)    { $Largest = @() }    else { $Largest = [object[]]$Largest }
    if ($null -eq $Duplicates) { $Duplicates = @() } else { $Duplicates = [object[]]$Duplicates }
    if ($null -eq $DestCollisions) { $DestCollisions = @() } else { $DestCollisions = [object[]]$DestCollisions }
    $blocked = @($Summary | Where-Object Verdict -eq 'BLOCKED').Count
    $projCount = $Summary.Count
    $actionIssues = @($Issues | Where-Object { ((Test-ConfigProp $_ 'Severity')) -and "$($_.Severity)" -eq 'ACTION' })
    $autoIssues   = @($Issues | Where-Object { -not (((Test-ConfigProp $_ 'Severity')) -and "$($_.Severity)" -eq 'ACTION') })
    $reviewCount = @($Summary | Where-Object Verdict -eq 'REVIEW').Count
    $grade = if ($blocked -gt 0) { 'D' } elseif (($reviewCount -gt 0) -or ($actionIssues.Count -gt 0) -or ($DestCollideGroups -gt 0)) { 'C' } elseif ($RenameCount -gt 0) { 'B' } else { 'A' }
    $gradeLine = switch ($grade) {
        'A' { 'ready to migrate as-is.' }
        'B' { "ready to migrate. Grade B only means $RenameCount file name(s) will be tidied automatically on upload; nothing is needed from you." }
        'C' {
            $cBits = @()
            if ($reviewCount -gt 0) { $cBits += "$reviewCount destination(s) could not be verified" }
            $unreadN = @($actionIssues | Where-Object { "$($_.Problem)" -like 'source could not be read*' }).Count
            if ($unreadN -gt 0) { $cBits += "$unreadN $($script:SrcItem)(s) could not be read at all, so nothing in them was checked" }
            if (($actionIssues.Count - $unreadN) -gt 0) { $cBits += "$($actionIssues.Count - $unreadN) item(s) need a decision" }
            if ($DestCollideGroups -gt 0) { $cBits += "$DestCollideGroups destination(s) shared by more than one $($script:SrcItem)" }
            "ready once " + ($cBits -join ' and ') + " are resolved - see below."
        }
        default { "$blocked destination(s) blocked on storage - fix capacity first." }
    }
    $leadTxt = switch ($grade) {
        'A' { 'Ready to migrate as it is.' }
        'B' { "Ready: $RenameCount automatic rename(s), nothing needed from you." }
        'C' { "Not ready yet: $(($gradeLine -replace '^ready once ','') -replace ' - see below\.$','') need resolving first." }
        default { "Blocked: $blocked destination(s) do not have enough free space." }
    }
    if ($blocked -gt 0 -or $FailCount -gt 0 -or $reviewCount -gt 0 -or $DestCollideGroups -gt 0) {
        $bStyle='background:#FFF6EC;border:1px solid #F5C083;color:#B5460F'; $bTitle=$leadTxt
    } else {
        $bStyle='background:#E7F7EF;border:1px solid #86D9B4;color:#066A4B'; $bTitle=$leadTxt
    }
    $bExtra=''
    if ($blocked)     { $bExtra += " $blocked destination(s) do not have enough free space." }
    if ($reviewCount) { $bExtra += " $reviewCount destination(s) could not be checked (sign-in, access, or the destination was not found) - see the table below and verify before migrating." }
    if ($actionIssues.Count) { $bExtra += " $($actionIssues.Count) issue(s) need a decision from you - see 'Action needed before migration' below." }
    if ($DestCollideGroups -gt 0) { $bExtra += " $DestCollideGroups destination(s) are shared by more than one $($script:SrcItem) - see 'Destinations shared by more than one $($script:SrcItem)' below." }
    if ($RenameCount -and $grade -ne 'B') { $bExtra += " $RenameCount file(s) will be tidied automatically (they still migrate)." }
    $selFiles = @($SelExcluded | Where-Object { "$($_.Kind)" -ne 'Folder' }); $selFolders = @($SelExcluded | Where-Object { "$($_.Kind)" -eq 'Folder' })
    if ($SelExcluded.Count) { $selB = [int64]0; foreach ($r in $selFiles) { try { $selB += [int64]$r.SizeBytes } catch {} }; $bExtra += " Your selection leaves out $('{0:N0}' -f $selFiles.Count) file(s) ($(Format-Bytes $selB))$(if ($selFolders.Count) { " and $($selFolders.Count) folder(s) not listed" }); see 'Left out by your selection' below." }
    if (@($SelStale).Count) { $bExtra += " $(@($SelStale).Count) selection rule(s) match nothing; check them below." }
    if ($DupChecked -and $DupGroups -gt 0) { $bExtra += " Also worth a look: $DupGroups set(s) of duplicate files, $(Format-Bytes $DupWasted) in redundant copies. They migrate as they are; see 'Duplicate files' below." }
    if (-not $bExtra) { $bExtra = ' Nothing needs attention.' }
    if ($bExtra -eq ' Nothing needs attention.') { $bExtra = '' }
    $banner = "<div style='$bStyle;border-radius:8px;padding:14px 16px;margin:0 0 18px;font-size:14px'><span style='float:right;font-size:12px;font-weight:600;border:1px solid currentColor;border-radius:99px;padding:1px 9px;margin-left:10px' title='$(_enc "Readiness grade ${grade}: $gradeLine")'>Grade $grade</span><strong>$(_enc $bTitle)</strong>$(_enc $bExtra)</div>"
    $collisionSection = ''
    if ($DestCollisions.Count) {
        $coRows = ''
        foreach ($x in $DestCollisions) {
            $coNote = if ([bool]$x.ContentsOnly) { " (contents only is on for at least one of these - the risk is immediate, not just on matching filenames)" } else { '' }
            $coRows += "<tr><td>$(_enc $x.Space)</td><td class='err'>lands in the same destination folder as: $(_enc $x.SharedWith)$coNote</td></tr>`n"
        }
        $collisionSection = "<h3 style='color:#B42318'>Destinations shared by more than one $($script:SrcItem) ($DestCollideGroups)</h3>" +
            "<p class='dim' style='margin:4px 0 8px'>These $($script:SrcItems) are mapped to the exact same destination folder. If any two of them contain a file with the same name and relative path, one will silently overwrite the other during the run. Give each its own destination folder, or confirm this merge is intentional.</p>" +
            "<table><thead><tr><th>$($script:SrcItemCap)</th><th>Collision</th></tr></thead><tbody>$coRows</tbody></table>"
    }
    $actionSection = ''
    if ($actionIssues.Count) {
        $aRows=''
        foreach ($x in $actionIssues) { $aRows += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(_enc $x.File)</td><td class='err'>$(_enc $x.Problem)</td></tr>`n" }
        $actionSection = "<h3 style='color:#B42318'>Action needed before migration: files that need a decision ($($actionIssues.Count))</h3>" +
            "<p class='dim' style='margin:4px 0 8px'>The run will not fix these automatically because doing so could lose data. Fix them at the source (or shorten the destination folder), then run this check again.</p>" +
            "<table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th>What to do</th></tr></thead><tbody>$aRows</tbody></table>"
    }
    $sumRows=''
    foreach ($s in $Summary) {
        $vc = switch ("$($s.Verdict)") { 'BLOCKED' {'err'} 'OK' {'dim'} 'SIM' {'dim'} default {''} }
        $spNote = ''
        try { if (((Test-ConfigProp $s 'SrcPath')) -and "$($s.SrcPath)") { $spNote = "<div class='dim' style='font-size:11px'>$(_enc $s.SrcPath)</div>" } } catch {}
        $fNote = ''; try { if (((Test-ConfigProp $s 'FreeNote')) -and "$($s.FreeNote)") { $fNote = "<div class='dim' style='font-size:11px'>$(_enc $s.FreeNote)</div>" } } catch {}
        $typeCell = if ($script:SrcItem -eq 'source') { '' } else { "<td>$(_enc $s.Type)</td>" }
        $sumRows += "<tr><td class='src'>$(_enc $s.Space)$spNote</td>$typeCell<td class='n'>$(if ((Test-ConfigProp $s 'RequiredBytes')) { Format-Bytes ([int64]$s.RequiredBytes) } else { "$(_enc $s.RequiredGB) GB" })</td><td class='n'>$(_enc $s.Free)$fNote</td><td class='$vc'>$(_enc $s.Verdict)</td></tr>`n"
    }
    if ($autoIssues.Count) {
        $iRows=''
        foreach ($x in $autoIssues) { $iRows += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(Format-ReportLeafCell $x.File)</td><td>$(_enc $x.Problem)</td></tr>`n" }
        $issueSection = "<h3>Tidied automatically on upload ($($autoIssues.Count)): no action needed</h3>" +
            "<p class='dim' style='margin:4px 0 8px'>These names are adjusted on upload by a fixed rule (illegal character becomes _, reserved names gain a trailing _, trailing dots/spaces trimmed, Mac accents normalised). Every change is listed in the renames CSV with the run.</p>" +
            "<details><summary>$($autoIssues.Count) file(s) &middot; click for the list</summary><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th>Note</th></tr></thead><tbody>$iRows</tbody></table></details>"
    } elseif (-not $actionIssues.Count) { $issueSection = "<p class='okbox'>No file name or path problems. Every file can be uploaded as it is.</p>" } else { $issueSection = '' }
    $lRows=''
    foreach ($x in $Largest) { $m=''; try { $m=([datetime]$x.ModifiedUtc).ToString('yyyy-MM-dd') } catch {}; $lRows += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(Format-ReportLeafCell $x.RelativePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SizeBytes))</td><td class='n dim'>$(_enc $m)</td></tr>`n" }
    $largeSection = if ($lRows) { "<table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th><th>Modified</th></tr></thead><tbody>$lRows</tbody></table>" } else { "<p class='dim'>No files found.</p>" }
    $mapSection = ''
    if ($FileMapSummary -and ([object[]]$FileMapSummary).Count) {
        $mRows = ''
        foreach ($s in ([object[]]$FileMapSummary)) { $mRows += "<tr><td class='src'>$(_enc $s.Space)</td><td>$(_enc $s.Destination)</td><td class='pth'>$(_enc $s.Folder)</td><td class='n'>$('{0:N0}' -f [int]$s.Files)</td><td class='n'>$(Format-Bytes ([int64]$s.Bytes))</td><td class='n'>$([int]$s.Renamed)</td></tr>`n" }
        $mapSection = @"
<h3>Where each file will go</h3>
<table><thead><tr><th>$($script:SrcItemCap)</th><th>Destination</th><th>Folder</th><th class='n'>Files</th><th class='n'>Data</th><th class='n'>Renamed</th></tr></thead><tbody>
$mRows
</tbody></table>
<p class='dim'>Every one of the $('{0:N0}' -f $FileMapCount) file(s) is listed with its destination path in <b>api-preflight-file-map.csv</b> in this job's reports folder (columns SourcePath, Destination, DestPath, Renamed, RenamedFrom). It is computed by the same rule the upload uses. This is a snapshot from when this check ran; a Preview writes the same map into its audit as of the moment you run it. Neither reads the destination, so the map says where each file will land, not whether something is already there.</p>
"@
    }
    if ($DupGroups -gt 0) {
        $dupCap = 50
        $dGroups = @($Duplicates | Group-Object DuplicateGroupId | Sort-Object { [int64]$_.Group[0].SizeBytes * ($_.Count - 1) } -Descending)
        $tinyN = @($dGroups | Where-Object { [int64]$_.Group[0].SizeBytes -lt 1KB }).Count
        $dRows=''
        foreach ($dg in @($dGroups | Select-Object -First $dupCap)) {
            foreach ($x in $dg.Group) { $dRows += "<tr><td class='n'>$(_enc $x.DuplicateGroupId)</td><td class='src'>$(_enc $x.Space)</td><td>$(Format-ReportLeafCell $x.RelativePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SizeBytes))</td></tr>`n" }
        }
        $dCapTxt = if ($dGroups.Count -gt $dupCap) { "Showing the $dupCap sets that take the most space. All $DupGroups are in api-preflight-duplicates.csv in this job's reports folder." } else { "Every set is also in api-preflight-duplicates.csv in this job's reports folder." }
        $dTinyTxt = if ($tinyN -gt 0) { " $tinyN of the $DupGroups sets are files under 1 KB (often system or tool files), which cost almost nothing." } else { '' }
        $dupSection = "<details$(if ((([regex]::Matches($dRows, '<tr>')).Count) -gt 50) { ' data-big' })><summary>$DupGroups set(s) of duplicate files (identical content), $(Format-Bytes $DupWasted) in redundant copies &middot; click for details</summary><table><thead><tr><th class='n'>Group</th><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th></tr></thead><tbody>$dRows</tbody></table></details><p class='dim'>$dCapTxt$dTinyTxt Nothing is de-duplicated automatically; this is for your review before migrating.</p>"
    } elseif (-not $DupChecked) { $dupSection = "<p class='dim'>Duplicates were NOT checked: run.tuning.findDuplicates is off for this job, so no file content was read. Turn it on and run Check readiness again to look for duplicate files.</p>" }
    else { $dupSection = "<p class='okbox'>No duplicate files detected by content.</p>" }
    $brand = 'Liscaragh Migrate'
    if (((Test-ConfigProp $Config.run 'report')) -and ((Test-ConfigProp $Config.run.report 'brand')) -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
    $now = Get-Date
    $tv = Lzb0b39673dd; $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    $blockersN = [int]$FailCount + [int]$blocked + [int]$reviewCount + [int]$DestCollideGroups
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_enc $brand) - Readiness check</title>
$(Get-ReportStyle)
</head><body><div class='wrap'>
<header>$(Get-BrandLogoTag -Config $Config)<div><h1>$(_enc (Get-ReportHeaderTitle $brand))</h1><div class='sub'>Readiness check (before you upload) &middot; generated $($now.ToString('dd MMM yyyy HH:mm'))$verSub$(Get-ReportClientSub $Config)</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
$banner
<div class='cards'>
 <div class='card'><div class='v'>$('{0:N0}' -f $FileMapCount)</div><div class='l'>Files selected</div></div>
 <div class='card'><div class='v'>$(Format-Bytes $AllBytes)</div><div class='l'>Selected size</div></div>
 <div class='card'><div class='v $(if($blockersN -gt 0){'err'})'>$blockersN</div><div class='l'>Blockers</div></div>
 <div class='card'><div class='v'>$('{0:N0}' -f $RenameCount)</div><div class='l'>Automatic changes</div></div>
</div>
<div class='cards sec'>
 <div class='card'><div class='v'>$projCount</div><div class='l'>$($script:SrcItemCap)s checked</div></div>
 <div class='card'><div class='v'>$(if ($DupChecked) { '{0:N0}' -f $DupGroups } else { 'n/a' })</div><div class='l'>Duplicate sets</div></div>
 <div class='card'><div class='v'>$(if ($DupChecked) { Format-Bytes $DupWasted } else { 'not checked' })</div><div class='l'>In redundant copies</div></div>
 <div class='card'><div class='v'>$DestCollideGroups</div><div class='l'>Shared destinations</div></div>
 $(if ($SelExcluded.Count) { "<div class='card'><div class='v'>$(Format-SelLeftOutCount $SelExcluded)</div><div class='l'>Left out by your selection</div></div>" })
</div>
<h2 id='action'>Action required</h2>
$(if (-not $collisionSection -and -not $actionSection -and -not $blocked -and -not $reviewCount -and -not $SelStale.Count) { "<div class='action none'><b>No action required.</b> Every selected file can be uploaded$(if ($RenameCount) { ", $RenameCount after an automatic rename" })$(if ($blocked -eq 0) { ', and every destination has room' }).</div>" } else { "<div class='action todo'><ul>$(if ($blocked) { "<li>$blocked destination(s) do not have enough free space (see Scope and destination).</li>" })$(if ($reviewCount) { "<li>$reviewCount destination(s) could not be checked: sign-in, access, or not found.</li>" })$(if ($actionIssues.Count) { "<li>$($actionIssues.Count) file(s) need a decision (listed below).</li>" })$(if ($DestCollideGroups) { "<li>$DestCollideGroups destination(s) are shared by more than one $($script:SrcItem) (listed below).</li>" })$(if ($SelStale.Count) { "<li>$($SelStale.Count) selection rule(s) match nothing: check them under Left out by your selection.</li>" })</ul></div>" })
$collisionSection
$actionSection
<h2 id='scope'>Scope and destination</h2>
<table><thead><tr><th>$($script:SrcItemCap)</th>$(if ($script:SrcItem -ne 'source') { '<th>Type</th>' })<th class='n'>Required</th><th class='n'>Free at destination</th><th>Verdict</th></tr></thead><tbody>
$sumRows
</tbody></table>
$mapSection
$(Get-SelectionSectionHtml -Rows $SelExcluded -Stale $SelStale -Lead 'Every total above leaves these out.')
<h3>Estimated time</h3>
<p class='dim'>$(_enc $EstimateText)</p>
$(if ($DevFolderNote) { "<p><strong>Developer and tool folders.</strong> $(_enc ($DevFolderNote -replace '^Developer and tool folders found: ',''))</p>" })
<h2 id='exceptions'>Exceptions and changes</h2>
$issueSection
<h2 id='evidence'>Detailed evidence</h2>
<h3>Largest files</h3>
$largeSection
<h3>Duplicate files</h3>
$dupSection
<footer>Source: $(_enc $script:SrcSysName) &middot; This is a read-only readiness check: nothing was uploaded or changed &middot; $(_enc (Get-ReportTimeNote)) &middot; Liscaragh Migrate &middot; Liscaragh Software &middot; www.liscaragh.com</footer>
</div>
$(Get-ReportPrintScript)
</body></html>
"@
    $outPath = Join-Path $Config.run.reportRoot ("report-preflight-" + $now.ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "Readiness report written: $outPath"
}
function Resolve-DuplicateHashes {
    param($Items, [int64]$AllBytes)
    if (-not $script:FindDuplicates) {
        Write-MigrationLog INFO "Duplicate check skipped: run.tuning.findDuplicates is false, so no file content was read. The readiness report says duplicates were not checked."
        return $false
    }
    $local = @($Items | Where-Object { [int64]$_.Size -gt 0 -and -not "$($_.Hash)".Trim() -and "$($_.Id)" })
    if (-not $local.Count) { return $true }
    $cands = @($local | Group-Object Size | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group })
    if (-not $cands.Count) {
        Write-MigrationLog INFO "Duplicate check: every one of the $($local.Count) non-empty file(s) has a size no other file shares, so none can be a duplicate. No file content was read."
        return $true
    }
    $candBytes = Get-SafeSum -Items $cands -Property Size
    $prefixLen = 64KB
    $prefixBudget = [int64]0; foreach ($c in $cands) { $prefixBudget += [math]::Min([int64]$c.Size, [int64]$prefixLen) }
    Write-MigrationLog INFO "Duplicate check: $($cands.Count) of the $($local.Count) non-empty file(s) ($(Format-Bytes $candBytes) of $(Format-Bytes $AllBytes)) share a size with another file, so only those can be duplicates. Reading the first 64 KB of each (at most $(Format-Bytes $prefixBudget)) to narrow them; the rest of the data is not read. Set run.tuning.findDuplicates to false in config.json to skip this check."
    Lz883d31a1c9 -Phase 'Duplicates' -Space '' -SourcePath "$($cands[0].Id)"
    $unreadable = 0; $readBytes = [int64]0
    $r2 = Lze7870ebcec -Items $cands -PrefixBytes $prefixLen -Activity 'Duplicate check (first 64 KB)'
    $readBytes += $r2.Bytes; $unreadable += $r2.Bad
    foreach ($c in $cands) { $pfx = ''; if ($r2.Hashes.ContainsKey("$($c.Id)")) { $pfx = $r2.Hashes["$($c.Id)"] }; $c | Add-Member -NotePropertyName DupPrefix -NotePropertyValue $pfx -Force }
    $survivors = @($cands | Where-Object { $_.DupPrefix } | Group-Object { "$($_.Size)|$($_.DupPrefix)" } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group })
    if ($survivors.Count) {
        $survBytes = Get-SafeSum -Items $survivors -Property Size
        Write-MigrationLog INFO "Duplicate check: $($survivors.Count) file(s) ($(Format-Bytes $survBytes)) match another on size and first 64 KB. Reading those in full to confirm."
        $r3 = Lze7870ebcec -Items $survivors -PrefixBytes 0 -Activity 'Duplicate check (full read)'
        $readBytes += $r3.Bytes; $unreadable += $r3.Bad
        foreach ($s in $survivors) { if ($r3.Hashes.ContainsKey("$($s.Id)")) { $s.Hash = $r3.Hashes["$($s.Id)"] } }
    }
    $pct = if ($AllBytes -gt 0) { [math]::Round(100.0 * $readBytes / $AllBytes, 1) } else { 0 }
    Write-MigrationLog INFO "Duplicate check done: read $(Format-Bytes $readBytes) of $(Format-Bytes $AllBytes) ($pct%)$(if ($unreadable) { "; $unreadable file(s) could not be opened and were left out" })."
    return $true
}
function Lze7870ebcec {
    param($Items, [int]$PrefixBytes, [string]$Activity)
    $paths = @($Items | ForEach-Object { "$($_.Id)" } | Where-Object { $_ } | Sort-Object -Unique)
    $out = @{ Hashes = @{}; Bytes = [int64]0; Bad = 0 }
    if (-not $paths.Count) { return $out }
    $workers = [int][math]::Max(1, [math]::Min(8, [math]::Ceiling($paths.Count / 25.0)))
    $chunks = @(); for ($i = 0; $i -lt $workers; $i++) { $chunks += ,(New-Object System.Collections.Generic.List[string]) }
    for ($i = 0; $i -lt $paths.Count; $i++) { $chunks[$i % $workers].Add($paths[$i]) }
    $worker = {
        param($list, [int]$prefix, $done)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $buf = $null; if ($prefix -gt 0) { $buf = [byte[]]::new($prefix) }
        $h = @{}; $bytes = [int64]0; $bad = 0
        foreach ($p in $list) {
            try {
                $fs = [System.IO.File]::OpenRead($p)
                try {
                    if ($prefix -gt 0) { $got = $fs.Read($buf, 0, $buf.Length); $bytes += $got; $h[$p] = [System.BitConverter]::ToString($md5.ComputeHash($buf, 0, $got)) }
                    else { $h[$p] = (([System.BitConverter]::ToString($md5.ComputeHash($fs))) -replace '-','').ToLowerInvariant(); $bytes += $fs.Length }
                } finally { $fs.Dispose() }
            } catch { $bad++ }
            $done.N++
        }
        $md5.Dispose()
        return @{ Hashes = $h; Bytes = $bytes; Bad = $bad }
    }
    $done = [hashtable]::Synchronized(@{ N = 0 })
    $pool = [runspacefactory]::CreateRunspacePool(1, $workers); $pool.Open()
    $jobs = @()
    try {
        foreach ($ch in $chunks) {
            if (-not $ch.Count) { continue }
            $ps = [powershell]::Create(); $ps.RunspacePool = $pool
            [void]$ps.AddScript($worker).AddArgument($ch).AddArgument($PrefixBytes).AddArgument($done)
            $jobs += @{ PS = $ps; Handle = $ps.BeginInvoke() }
        }
        $lastShown = -1
        while (@($jobs | Where-Object { -not $_.Handle.IsCompleted }).Count -gt 0) {
            $d = [int]$done.N
            if ($d -ne $lastShown -and ($d % 200) -eq 0) { Lz3402e3c9c5 -Activity $Activity -Status "$d of $($paths.Count)" -Current $d -Total $paths.Count | Out-Null; $lastShown = $d }
            Lz3c24fdf306
            Start-Sleep -Milliseconds 100
        }
        foreach ($j in $jobs) {
            try {
                $r = @($j.PS.EndInvoke($j.Handle))[0]
                if ($r) { foreach ($k in $r.Hashes.Keys) { $out.Hashes[$k] = $r.Hashes[$k] }; $out.Bytes += [int64]$r.Bytes; $out.Bad += [int]$r.Bad }
            } catch { $out.Bad += 1 }
            try { $j.PS.Dispose() } catch {}
        }
    } finally { try { $pool.Close(); $pool.Dispose() } catch {} }
    return $out
}
function Invoke-PreFlight {
    param($Config)
    Lz93fa3c46d9 -Config $Config -Stage 'api-preflight'
    $script:ExcludedFile = $null; Lzc9d8fe4f48
    Lz1338c7e606 -Config $Config
    Connect-Destination -Config $Config
    $map = @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')
    $invalidRegex = '[' + [regex]::Escape('"*:<>?|') + ']'
    $maxPath = 400
    $sanitise = (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames)
    $issues  = New-Object System.Collections.Generic.List[object]
    $summary = New-Object System.Collections.Generic.List[object]
    $destRows = New-Object System.Collections.Generic.List[object]
    $renameCount = 0; $failCount = 0; $caseDupCount = 0; $collideCount = 0
    $allItems = New-Object System.Collections.Generic.List[object]
    $allBytes = [int64]0
    $fileMap = New-Object System.Collections.Generic.List[object]
    $fileMapSummary = New-Object System.Collections.Generic.List[object]
    $driveNeed = @{}
    $t = $map.Count; $i = 0
    foreach ($row in $map) {
        $i++; Lz3402e3c9c5 -Activity 'Pre-flight' -Status $row.Space -Current $i -Total $t | Out-Null; Lz883d31a1c9 -Phase 'Readiness' -Space "$($row.Space)"
        $space = New-SpaceRef -Row $row -Config $Config
        try {
            $items = @(Get-DattoItems -Config $Config -Space $space)
        } catch {
            Write-MigrationLog ERROR "  could not read files for '$($row.Space)': $($_.Exception.Message). In plain terms: the source may be empty, moved, or unreachable. Skipping it in pre-flight checks."
            $issues.Add([pscustomobject]@{ Space = $row.Space; File = ''; Problem = "source could not be read ($($_.Exception.Message)) - skipped"; Severity = 'ACTION' })
            continue
        }
        $bytes = Get-SafeSum -Items $items -Property Size
        $allBytes += $bytes
        foreach ($it in $items) { [void]$allItems.Add([pscustomobject]@{ Space = $row.Space; RelativePath = $it.RelativePath; Size = [int64]$it.Size; ModifiedUtc = "$($it.ModifiedUtc)"; Hash = "$($it.Hash)"; Id = "$($it.Id)" }) }
        $effSubPre = Join-SubPath $row.TargetSubFolder (Get-NestFolder $Config $row)
        $rsvSeg = Get-ReservedDestSegment "$($row.TargetSubFolder)"
        if ($rsvSeg) { $issues.Add([pscustomobject]@{ Space = $row.Space; File = ''; Problem = "the destination folder '$($row.TargetSubFolder)' contains '$rsvSeg', which is reserved by Microsoft 365 and cannot be used as a folder name, so nothing could be uploaded into it. Change the destination folder name (for example to '${rsvSeg}_')"; Severity = 'ACTION' }) }
        $fmRenamed = 0; $fmLabel = Get-DestinationLabel -Row $row
        $fmPaths = New-Object System.Collections.Generic.List[string]
        foreach ($it in $items) {
            $pd = Get-PlannedDestPath -Config $Config -EffSub $effSubPre -Item $it
            if ($pd.Renamed) { $fmRenamed++ }
            [void]$fmPaths.Add("$($pd.Path)")
            [void]$fileMap.Add([pscustomobject]@{ Space = $row.Space; SourcePath = $it.RelativePath; Destination = $fmLabel; DestPath = $pd.Path; Renamed = [bool]$pd.Renamed; RenamedFrom = $(if ($pd.Renamed) { $pd.From } else { '' }); SizeBytes = [int64]$it.Size; ModifiedUtc = "$($it.ModifiedUtc)" })
        }
        $fmFolder = Lzb0489ee16b -Paths $fmPaths.ToArray()
        if (-not $fmFolder) { $fmFolder = $effSubPre }
        [void]$fileMapSummary.Add([pscustomobject]@{ Space = $row.Space; Destination = $fmLabel; Folder = $(if ($fmFolder) { '/' + "$fmFolder".Trim('/') } else { '/' }); Files = @($items).Count; Bytes = [int64]$bytes; Renamed = $fmRenamed })
        $rowCo = $false
        try { if ((Test-ConfigProp $row 'SourceContentsOnly')) { $rowCo = ("$($row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
        $kScope = ''; try { if ((Test-ConfigProp $row 'SourceSubPath')) { $kScope = "$($row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
        $kSeed = if ($kScope -and -not $rowCo) { $kScope -replace '\\','/' } else { (Get-LocalFsRootSeed -Config $Config -Row $row) }
        $kLand = if ($rowCo) { $effSubPre } else { Join-SubPath $effSubPre $kSeed }
        $destKey = (Get-RowDestId $row) + '|' + "$kLand".ToLowerInvariant()
        [void]$destRows.Add([pscustomobject]@{ Space = $row.Space; DestKey = $destKey; ContentsOnly = $rowCo })
        $srvBase = ''
        try {
            $srvUri = [uri]"$($row.DestinationUrl)"
            $srvSite = [uri]::UnescapeDataString($srvUri.AbsolutePath).Trim('/')
            $srvLib = ''; if ((Test-ConfigProp $row 'TargetLibrary')) { $srvLib = "$($row.TargetLibrary)".Trim() }
            if (-not $srvLib) { $srvLib = if ("$($row.DestinationType)" -eq 'OneDrive') { 'Documents' } else { 'Shared Documents' } }
            $srvBase = (@($srvSite, $srvLib) | Where-Object { $_ }) -join '/'
        } catch { $srvBase = "$($row.DestinationUrl)" }
        foreach ($it in $items) {
            $p = @(); $act = $false
            $subLen = $(if ($effSubPre) { $effSubPre.Length + 1 } else { 0 })
            $tidyRel = if ($sanitise) { ConvertTo-SafeRelPath $it.RelativePath } else { ($it.RelativePath -replace '\\','/') }
            $destLen = $srvBase.Length + 1 + $subLen + $tidyRel.Length
            if ($destLen -gt $maxPath) { $p += "path too long ($destLen > $maxPath, counted as the SharePoint server path: site, library, folders and file name): WILL FAIL - shorten the target folder or the file's folder names"; $failCount++; $act = $true }
            if ((Split-Path $it.RelativePath -Leaf) -match $invalidRegex) {
                if ($sanitise) { $p += 'illegal character: will be auto-renamed on upload (migrates fine)'; $renameCount++ }
                else { $p += 'illegal character: WILL FAIL - set run.sanitiseNames to true'; $failCount++; $act = $true }
            }
            elseif (((ConvertTo-SafeRelPath $it.RelativePath) -replace '\\','/') -ne ($it.RelativePath -replace '\\','/')) {
                $tidied = (ConvertTo-SafeRelPath $it.RelativePath)
                if ($sanitise) { $p += "reserved or unsupported name (tidied on upload to '$tidied', migrates fine)"; $renameCount++ }
                else { $p += "reserved or unsupported name (SharePoint rejects it as '$($it.RelativePath)'): WILL FAIL - set run.sanitiseNames to true"; $failCount++; $act = $true }
            }
            if ($p.Count) { $issues.Add([pscustomobject]@{ Space = $row.Space; File = $it.RelativePath; Problem = ($p -join '; '); Severity = $(if ($act) { 'ACTION' } else { 'AUTO' }) }) }
        }
        foreach ($g in @($items | Group-Object { $_.RelativePath.ToLowerInvariant() } | Where-Object Count -gt 1)) {
            $names = @($g.Group | ForEach-Object RelativePath)
            foreach ($n in @($names | Select-Object -Skip 1)) {
                $issues.Add([pscustomobject]@{ Space = $row.Space; File = $n; Problem = "case-only duplicate of '$($names[0])': SharePoint keeps ONE path for both, so one file will overwrite the other. Rename one at the source before migrating."; Severity = 'ACTION' })
                $failCount++; $caseDupCount++
            }
        }
        if ("$($Config.source.provider)" -eq 'LocalFs') {
            foreach ($it2 in @($items | Where-Object { ((Test-ConfigProp $_ 'NfdRenamed')) -and $_.NfdRenamed })) {
                $issues.Add([pscustomobject]@{ Space = $row.Space; File = $it2.RelativePath; Problem = 'Mac-format accented name (NFD): normalised on upload so it matches SharePoint (migrates fine)'; Severity = 'AUTO' })
                $renameCount++
            }
        }
        if ($sanitise) {
            foreach ($g in @($items | Group-Object { (ConvertTo-SafeRelPath ($_.RelativePath -replace '\\','/')).ToLowerInvariant() } | Where-Object Count -gt 1)) {
                $names = @($g.Group | ForEach-Object RelativePath)
                if (@($names | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique).Count -lt 2) { continue }
                foreach ($n in @($names | Select-Object -Skip 1)) {
                    $issues.Add([pscustomobject]@{ Space = $row.Space; File = $n; Problem = "renames collide: '$n' and '$($names[0])' both tidy to the same SharePoint name, so one would overwrite the other. Rename one at the source before migrating."; Severity = 'ACTION' })
                    $failCount++; $collideCount++
                }
            }
        }
        $verdict = 'REVIEW'; $freeTxt = 'UNKNOWN'; $freeNote = ''
        if ($Config.destination.provider -eq 'LocalSim') { $verdict = 'SIM'; $freeTxt = 'SIM' }
        else {
            try {
                $drive = $null
                $destRes = Resolve-DestinationDriveId -Config $Config -Row $row
                if ($destRes -and $destRes.DriveId) {
                    $drive = Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$($destRes.DriveId)"
                }
                $q = if ($drive) { $drive['quota'] } else { $null }
                if ($q -and $q['total']) {
                    $free = [int64]$q['total'] - [int64]$q['used']
                    $dKey = "$($destRes.DriveId)"
                    $prior = [int64]0; if ($driveNeed.ContainsKey($dKey)) { $prior = [int64]$driveNeed[$dKey] }
                    $driveNeed[$dKey] = $prior + [int64]$bytes
                    $verdict = if ($free -ge ($prior + [int64]$bytes)) { 'OK' } else { 'BLOCKED' }
                    $freeTxt = [string]([math]::Round($free/1GB,2)) + ' GB'
                    if ($prior -gt 0) { $freeNote = "shared with an earlier $($script:SrcItem): $([math]::Round(($prior + [int64]$bytes)/1GB,2)) GB needed in total" }
                } else { $freeTxt = 'NOT-PROVISIONED' }
            } catch { $freeTxt = 'ERROR'; $verdict = 'REVIEW' }
        }
        $summary.Add([pscustomobject]@{ Space = $row.Space; Type = $row.Type; SrcPath = $(if ($script:SrcItem -eq 'source') { "$($row.SpaceId)" } else { '' }); RequiredGB = [math]::Round($bytes/1GB,2); RequiredBytes = [int64]$bytes; Free = $freeTxt; FreeNote = $freeNote; Verdict = $verdict })
        if ($verdict -eq 'BLOCKED') { Write-MigrationLog ERROR "  BLOCKED: $($row.Space) needs $([math]::Round($bytes/1GB,2))GB, free $freeTxt. In plain terms: the destination does not have enough free space for this $($script:SrcItem). Free up space or increase the storage quota, then run this again." }
    }
    try { Write-Progress -Activity 'Pre-flight' -Completed } catch {}
    $destCollisionRows = New-Object System.Collections.Generic.List[object]
    $collisionGroups = @($destRows | Group-Object DestKey | Where-Object { (@($_.Group | Select-Object -ExpandProperty Space -Unique)).Count -gt 1 })
    foreach ($g in $collisionGroups) {
        $spacesHere = @($g.Group | Select-Object -ExpandProperty Space -Unique | Sort-Object)
        $anyContentsOnly = [bool]@($g.Group | Where-Object { $_.ContentsOnly }).Count
        foreach ($sp in $spacesHere) {
            $others = ((@($spacesHere | Where-Object { $_ -ne $sp })) -join ', ')
            [void]$destCollisionRows.Add([pscustomobject]@{ Space = $sp; SharedWith = $others; ContentsOnly = $anyContentsOnly })
        }
    }
    $destCollideGroupCount = $collisionGroups.Count
    if ($destCollideGroupCount -gt 0) {
        $destCollisionRows | Protect-CsvRow | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-destination-collisions.csv') -NoTypeInformation -Encoding UTF8
        foreach ($g in $collisionGroups) {
            $spacesHere = @($g.Group | Select-Object -ExpandProperty Space -Unique | Sort-Object)
            Write-MigrationLog WARN "  DESTINATION COLLISION: $($spacesHere -join ' and ') all land in the same destination folder. Files with the same name will overwrite each other. In plain terms: these $($script:SrcItems) are set to merge into one folder - if any two contain a file with the same name and path, one will silently overwrite the other during the run."
        }
    } else {
        try { $p = Join-Path $Config.run.reportRoot 'api-preflight-destination-collisions.csv'; if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } } catch {}
    }
    $issues  | Protect-CsvRow | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-issues.csv') -NoTypeInformation -Encoding UTF8
    $summary | Protect-CsvRow | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-summary.csv') -NoTypeInformation -Encoding UTF8
    $blocked = @($summary | Where-Object Verdict -eq 'BLOCKED').Count
    $reviewCount = @($summary | Where-Object Verdict -eq 'REVIEW').Count
    Write-MigrationLog OK "Readiness check complete. $blocked destination(s) blocked for lack of storage - 'Full migration' will skip those."
    if ($reviewCount -gt 0) { Write-MigrationLog WARN "$reviewCount destination(s) could not be checked (sign-in, access, or the destination was not found) - see api-preflight-summary.csv. In plain terms: the tool could not confirm this destination is reachable, so it is NOT counted as ready. Fix sign-in or access, or confirm the destination exists, then run this check again." }
    if ($renameCount -gt 0) { Write-MigrationLog INFO "$renameCount file(s) have illegal characters and will be AUTO-RENAMED on upload (they migrate, nothing skipped)." }
    if ($failCount -gt 0)   { Write-MigrationLog WARN "$failCount file(s) WILL FAIL (path too long, or illegal char with sanitiseNames off). See api-preflight-issues.csv. In plain terms: some files have names or folder paths SharePoint cannot accept. The copy will still try them and each one will be recorded as an upload error, so shorten or rename them first (M2)." }
    if ($caseDupCount -gt 0) { Write-MigrationLog WARN "$caseDupCount case-only duplicate name(s) (e.g. Report.txt AND report.txt): SharePoint keeps ONE path, so one file will overwrite the other. Rename them at the source before migrating - each pair is named in api-preflight-issues.csv." }
    if ($collideCount -gt 0) { Write-MigrationLog WARN "$collideCount predicted rename collision(s): two different names tidy to the SAME SharePoint name, so one would overwrite the other. Rename one of each pair at the source before migrating - pairs are named in api-preflight-issues.csv." }
    $actionCount = @($issues | Where-Object { "$($_.Severity)" -eq 'ACTION' }).Count
    $unreadCount = @($issues | Where-Object { "$($_.Problem)" -like 'source could not be read*' }).Count
    if ($unreadCount -gt 0) { Write-MigrationLog WARN "$unreadCount $($script:SrcItem)(s) could not be read at all, so this readiness check covers only the rest. In plain terms: nothing in them was checked. Fix access or try again later, then run this check again." }
    if ($actionCount -gt 0) { Write-MigrationLog WARN "ACTION NEEDED before migrating: $actionCount issue(s) the run cannot fix safely on its own (too-long paths, case-only duplicates, colliding renames). They lead the readiness report and api-preflight-issues.csv." }
    $gradeLog = if ($blocked -gt 0) { 'D' } elseif (($reviewCount -gt 0) -or ($actionCount -gt 0) -or ($destCollideGroupCount -gt 0)) { 'C' } elseif ($renameCount -gt 0) { 'B' } else { 'A' }
    Write-MigrationLog OK "Readiness grade ${gradeLog} (A = migrate as-is, B = automatic renames only, C = decisions needed, D = blocked). The full verdict is at the top of the readiness report."
    if ($issues.Count -eq 0) { Write-MigrationLog OK "No file name/path issues." }
    $topN = if ($script:AssessmentTopFiles -gt 0) { $script:AssessmentTopFiles } else { 20 }
    $largestRows = @($allItems | Sort-Object Size -Descending | Select-Object -First $topN | ForEach-Object {
        [pscustomobject]@{ Space = $_.Space; RelativePath = $_.RelativePath; SizeBytes = [int64]$_.Size; ModifiedUtc = $_.ModifiedUtc }
    })
    $largestRows | Protect-CsvRow | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-largest-files.csv') -NoTypeInformation -Encoding UTF8
    $fileMap | Protect-CsvRow | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-file-map.csv') -NoTypeInformation -Encoding UTF8
    $fmRen = 0; foreach ($s in $fileMapSummary) { $fmRen += [int]$s.Renamed }
    Write-MigrationLog INFO "Where each file will go: $($fileMap.Count) file(s) mapped source -> destination in api-preflight-file-map.csv$(if ($fmRen) { " ($fmRen will be renamed on the way; see the Renamed and RenamedFrom columns)" }). Run Preview for the same map as of the moment you run it."
    foreach ($s in $fileMapSummary) { Write-MigrationLog INFO "  $($s.Space): $('{0:N0}' -f $s.Files) file(s), $(Format-Bytes $s.Bytes) -> $($s.Destination) > $($s.Folder)$(if ($s.Renamed) { " ($($s.Renamed) renamed)" })" }
    if ($largestRows.Count) { Write-MigrationLog INFO "Largest file: $(Format-Bytes ([int64]$largestRows[0].SizeBytes)) - $($largestRows[0].Space)/$($largestRows[0].RelativePath). The biggest $($largestRows.Count) are in api-preflight-largest-files.csv." }
    $dupChecked = $true
    if ($Config.datto.provider -eq 'LocalSim') { $dupChecked = Resolve-DuplicateHashes -Items $allItems -AllBytes $allBytes }
    $dupRows = New-Object System.Collections.Generic.List[object]
    $gid = 0
    foreach ($g in (@($allItems | Where-Object { [int64]$_.Size -gt 0 -and "$($_.Hash)".Trim() }) | Group-Object Hash | Where-Object { $_.Count -gt 1 } | Sort-Object { [int64]$_.Group[0].Size } -Descending)) {
        $gid++
        foreach ($x in $g.Group) { [void]$dupRows.Add([pscustomobject]@{ DuplicateGroupId = $gid; Hash = $g.Name; Space = $x.Space; RelativePath = $x.RelativePath; SizeBytes = [int64]$x.Size }) }
    }
    $dupRows | Protect-CsvRow | Export-Csv (Join-Path $Config.run.reportRoot 'api-preflight-duplicates.csv') -NoTypeInformation -Encoding UTF8
    $wasted = [int64]0
    if ($gid -gt 0) {
        $wasted = Get-SafeSum -Items (@($dupRows | Group-Object DuplicateGroupId | ForEach-Object { [int64]$_.Group[0].SizeBytes * ($_.Count - 1) }))
        Write-MigrationLog INFO "$gid set(s) of duplicate files (identical content), about $(Format-Bytes $wasted) in redundant copies. See api-preflight-duplicates.csv. Nothing is de-duplicated automatically; this is for review before migrating."
    } elseif ($dupChecked) {
        Write-MigrationLog INFO "No duplicate files detected by content hash."
    }
    $rate = $null; $rateFrom = ''
    foreach ($a in @(Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $rows = @(Import-AuditCsv $a.FullName)
            $cp = @($rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' })
            if (-not $cp.Count) { continue }
            $tms = @($rows | ForEach-Object { try { [datetime]::Parse($_.TimestampUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch {} } | Where-Object { $_ })
            if ($tms.Count -lt 2) { continue }
            $sec = (($tms | Measure-Object -Maximum).Maximum - ($tms | Measure-Object -Minimum).Minimum).TotalSeconds
            $cb  = Get-SafeSum -Items $cp -Property SourceSizeBytes
            if ($sec -ge 60 -and $cb -gt 0) {
                $rate = ($cb * 8.0 / 1e6) / $sec; $rateFrom = $a.Name
                try { $sd = ($a.FullName -replace '\.csv$','') + '.outcome.json'; if (Test-Path $sd) { $st = "$((Get-Content $sd -Raw | ConvertFrom-Json).Status)"; if (@('CANCELLED','ENDED_EARLY','INCOMPLETE','CAPPED') -contains $st) { $rateFrom += ', a run that did not finish, so treat it as rough' } } } catch {}
                break
            }
        } catch {}
    }
    $estText = ''
    if ($rate -and $rate -gt 0 -and $allBytes -gt 0) {
        $secs = ($allBytes * 8.0) / ($rate * 1e6)
        $estText = "Estimated transfer time for $(Format-Bytes $allBytes): about $(Format-Duration ([TimeSpan]::FromSeconds($secs))), at this job's last measured throughput of $([math]::Round($rate,1)) Mb/s (from $rateFrom). Actual time depends on your line speed and Microsoft 365 throttling."
    } else {
        $estText = "No duration estimate yet: this job has no completed upload to measure real throughput from. One will appear here after the first upload finishes."
        if ($allBytes -gt 0) {
            $planBits = @(foreach ($mb in 50,100,200,500) { "$(Format-Duration ([TimeSpan]::FromSeconds(($allBytes * 8.0) / ($mb * 1e6)))) at $mb Mb/s" })
            $estText += " For planning, $(Format-Bytes $allBytes) takes about " + ($planBits -join ', ') + " of sustained upload."
            $nFilesEst = $allItems.Count
            if ($nFilesEst -ge 500 -and ($allBytes / $nFilesEst) -lt 256KB) { $estText += " These figures count bytes only. This source has $('{0:N0}' -f $nFilesEst) files averaging $(Format-Bytes ([int64]($allBytes / $nFilesEst))), and at that size the setup for each file usually takes longer than moving its data, so expect it to take noticeably longer. The first real upload gives a measured estimate." }
        }
    }
    Write-MigrationLog INFO $estText
    $devNote = ''
    $devSegs = @('.git', '.svn', '.hg', 'node_modules', '__pycache__', '.venv', '.vs', '.idea', '.cursor', '.gradle')
    $devHits = @{}
    foreach ($it in $allItems) {
        $segs = @("$($it.RelativePath)" -split '[\\/]')
        for ($si = 0; $si -lt ($segs.Count - 1); $si++) {
            $sk = "$($segs[$si])".ToLowerInvariant()
            if ($devSegs -contains $sk) {
                if (-not $devHits.ContainsKey($sk)) { $devHits[$sk] = @{ N = 0; B = [int64]0 } }
                $devHits[$sk].N++; $devHits[$sk].B += [int64]$it.Size; break
            }
        }
    }
    if ($devHits.Count) {
        $devN = 0; $devB = [int64]0; foreach ($dv in $devHits.Values) { $devN += $dv.N; $devB += $dv.B }
        $devList = (@($devHits.Keys | Sort-Object | ForEach-Object { "$_ ($('{0:N0}' -f $devHits[$_].N))" }) -join ', ')
        $devNote = "Developer and tool folders found: $('{0:N0}' -f $devN) file(s), $(Format-Bytes $devB), inside $devList. These are usually not wanted in Microsoft 365 (version-control history, package caches, editor indexes). If you do not need them, untick those folders in 'Edit what to copy' before migrating. Nothing is left out automatically."
        Write-MigrationLog INFO $devNote
    }
    $selRoots = @{}
    $selIsLocal = $false; try { $selIsLocal = ("$($Config.source.provider)" -eq 'LocalFs') } catch {}
    if ($selIsLocal) { foreach ($mr in @($map)) { if ("$($mr.SpaceId)") { $selRoots["$($mr.Space)"] = "$($mr.SpaceId)" } } }
    if ($script:SelExcluded.Count) { Write-MigrationLog INFO "Your selection (Edit selection) leaves out $($script:SelExcluded.Count) item(s); they are not counted above and are listed in the readiness report." }
    try {
        Write-PreFlightReport -Config $Config -Summary $summary -Issues $issues -Largest $largestRows `
            -Duplicates $dupRows -DupGroups $gid -DupWasted $wasted -AllBytes $allBytes -FailCount $failCount -RenameCount $renameCount -EstimateText $estText `
            -DestCollisions $destCollisionRows -DestCollideGroups $destCollideGroupCount -DupChecked $dupChecked -FileMapSummary $fileMapSummary.ToArray() -FileMapCount $fileMap.Count `
            -SelExcluded $script:SelExcluded.ToArray() -SelStale (Lz77de606fc0 -Spaces @($map | ForEach-Object { "$($_.Space)" }) -Roots $selRoots) -DevFolderNote $devNote
    } catch { Write-MigrationLog WARN "Readiness report could not be written: $($_.Exception.Message)" }
}
function Write-AuditRunEnd {
    param([string]$AuditFile,[string]$Status,[string]$Reason,[int]$Processed,[int]$Expected,[int]$Copied,[int]$Skipped,
          [int]$Failed,[int]$VerifyFail,[int]$ZeroByte,[int64]$Bytes,[int]$SpacesPlanned,[int]$SpacesCompleted,[string]$ElapsedText,[int]$NotAttempted=0)
    if (-not $AuditFile) { return $true }
    $now = Get-Date
    $rec = [pscustomobject][ordered]@{
        TimestampUtc=$now.ToUniversalTime().ToString('o'); TimestampLocal=$now.ToString('yyyy-MM-dd HH:mm:ss')
        Space='(run)'; SourcePath='(run-end)'; DestPath=''; Renamed=$false; RenamedFrom=''
        Status="RUN_END:$Status"; SourceSizeBytes=[int64]$Bytes; DestSizeBytes=[int64]$Bytes
        SourceModifiedUtc=''; SourceMd5=''; DestHash=''; Method=''; DownloadMs=0; UploadMs=0; Retries=0
        Reason=("$Status | $Reason | processed $Processed of $Expected | copied $Copied skipped $Skipped notAttempted $NotAttempted failed $Failed verifyFail $VerifyFail zero $ZeroByte | spaces $SpacesCompleted/$SpacesPlanned | elapsed $ElapsedText")
        Error=''
    }
    for ($i=1;$i -le 5;$i++){ try { Add-CsvRecord -Path $AuditFile -Row ($rec | Protect-CsvRow); return $true } catch { Start-Sleep -Milliseconds (120*$i) } }
    return $false
}
function Get-RunActivePath { param($Config) return (Join-Path $Config.run.reportRoot 'run-active.json') }
function Lz6aa2b8bd37 {
    param($Config,[string]$Mode,[datetime]$StartUtc,[string]$AuditFile,[int]$ExpectedFiles,[int]$SpacesPlanned,[int]$SpacesCompleted,[string]$ResultDir='')
    $o = [ordered]@{ Status='RUNNING'; Pid=$PID; Mode=$Mode; StartUtc=$StartUtc.ToUniversalTime().ToString('o')
        AuditFile=$AuditFile; ExpectedFiles=$ExpectedFiles; SpacesPlanned=$SpacesPlanned; SpacesCompleted=$SpacesCompleted; ResultDir=$ResultDir }
    try { [System.IO.File]::WriteAllText((Get-RunActivePath $Config), ($o | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false)) } catch {}
}
function Lze3b49cb7ce { param($Config) try { Remove-Item (Get-RunActivePath $Config) -Force -ErrorAction SilentlyContinue } catch {} }
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
function Lzb0b39673dd {
    if ($null -ne $script:ToolVersionCache) { return $script:ToolVersionCache }
    $v = ''
    try {
        $gui = Join-Path $PSScriptRoot 'LiscaraghMigrate-GUI.ps1'
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
        $org = Invoke-LiscGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop
        $doms = @(@($org['value'])[0]['verifiedDomains'])
        $best = @($doms | Where-Object { $_['isDefault'] -and ("$($_['name'])" -notlike '*.onmicrosoft.com') })
        if (-not $best.Count) { $best = @($doms | Where-Object { "$($_['name'])" -notlike '*.onmicrosoft.com' }) }
        if (-not $best.Count) { $best = @($doms) }
        if ($best.Count) { $tenant = "$($best[0]['name'])" }
    } catch {}
    if (-not $tenant) { try { $tenant = "$($Config.auth.tenantId)" } catch {} }
    return @{ JobName = $job; Tenant = $tenant; Version = (Lzb0b39673dd) }
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
    Close-AppendWriters
    try {
        $ex = @()
        foreach ($p in $Paths) { if ($p -and (Test-Path $p)) { $ex += (Get-Item $p) } }
        if (-not $ex.Count) { return $result }
        $limit = [int64]($MaxMB * 1MB)
        $tot = Get-SafeSum -Items $ex -Property Length
        if ($tot -le $limit) { $result.Files = @($ex.FullName); return $result }
        $zip = Join-Path ([IO.Path]::GetTempPath()) ('liscaragh-migrate-run-files-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.zip')
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
        $wantOutcome = switch ($OutcomeBucket) {
            'Success' { "$($s.OnSuccess)" } 'Warning' { "$($s.OnWarning)" } default { "$($s.OnFailure)" }
        }
        if ($wantOutcome -eq '0') { return }
        $wantAction = switch ($ActionKey) {
            'Transfer' { "$($s.OnTransfer)" } 'Delta' { "$($s.OnDelta)" } 'Validate' { "$($s.OnValidate)" } 'SizeCheck' { "$($s.OnSizeCheck)" } default { '1' }
        }
        if ($wantAction -eq '0') { return }
        if (-not "$($s.Sender)".Trim() -or -not "$($s.Recipients)".Trim()) {
            Write-MigrationLog WARN 'Email alerts are switched on but the sender or recipients are missing (Settings > Email alerts). No email was sent; the run itself is unaffected.'
            return
        }
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
            elseif ($a) { Write-MigrationLog WARN "Email alerts: '$a' does not look like an email address and was skipped." }
        }
        if (-not $to.Count) {
            Write-MigrationLog WARN 'Email alerts: no valid recipient address is configured. No email was sent; the run itself is unaffected.'
            return
        }
        if ($prov -ne 'LocalSim') {
            $ctxE = $null; try { $ctxE = Get-MgContext } catch {}
            if (-not $ctxE) {
                try { Connect-Destination -Config $Config }
                catch { Write-MigrationLog WARN "The completion email could not be sent: Microsoft 365 sign-in for the email failed ($((("$($_.Exception.Message)") -replace [regex]::Escape("$($script:StopTag)"), '').Trim())). The run itself is unaffected; the outcome above stands."; return }
            }
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
                        contentBytes  = [Convert]::ToBase64String((Read-FileBytesShared $f))
                    }
                } catch { Write-MigrationLog WARN "Email alerts: could not read attachment $f ($($_.Exception.Message)); sending without it." }
            }
            foreach ($f in @($set.Files)) {
                try { if ([IO.Path]::GetFileName($f) -like 'liscaragh-migrate-run-files-*.zip' -and ([IO.Path]::GetDirectoryName($f)).TrimEnd('\','/') -eq ([IO.Path]::GetTempPath()).TrimEnd('\','/')) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } } catch {}
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
                $(if ($attachNote) { '<p style="color:#B5460F;">' + (& $esc $attachNote) + '</p>' } else { '' }) +
                '<p style="color:#98A2B3;font-size:12px;">Sent by the Liscaragh Migrate' +
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
            Invoke-LiscGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($emSender) -replace "%40","@")/sendMail" -Body $script:EmailMsgBody -ErrorAction Stop | Out-Null
        } | Out-Null
        Write-MigrationLog OK "Completion email sent from $emSender to $(@($to).Count) recipient(s)$(if ($atts.Count) { " with $($atts.Count) attachment(s)" })."
    } catch {
        Write-MigrationLog WARN "The completion email could not be sent: $($_.Exception.Message). The run itself is unaffected; the outcome above stands. Check Settings > Email alerts (sender, recipients, Mail.Send permission)."
    }
}
function ConvertTo-ExtensionCategoryRules {
    param([string]$Spec)
    $rules = @()
    foreach ($part in @("$Spec" -split '(;;|\r?\n)')) {
        $t = "$part".Trim(); if (-not $t -or $t -eq ';;') { continue }
        if ($t -match '^(.+?)\s*=\s*(.+)$') {
            $cat = "$($Matches[1])".Trim()
            $exts = @("$($Matches[2])" -split '[,\s]' | ForEach-Object { $_.Trim().TrimStart('.').ToLowerInvariant() } | Where-Object { $_ } | ForEach-Object { ".$_" })
            if ($cat -and $exts.Count) { $rules += ,([pscustomobject]@{ Category = $cat; Exts = $exts }) }
        }
    }
    return ,$rules
}
function ConvertTo-FilenameColRules {
    param([string]$Spec)
    $rules = @()
    foreach ($part in @("$Spec" -split '(;;|\r?\n)')) {
        $t = "$part".Trim(); if (-not $t -or $t -eq ';;') { continue }
        try {
            $rx = [regex]::new($t)
            $cols = @($rx.GetGroupNames() | Where-Object { $_ -notmatch '^\d+$' })
            if ($cols.Count) { $rules += ,([pscustomobject]@{ Regex = $rx; Columns = $cols }) }
        } catch { }
    }
    return ,$rules
}
function ConvertTo-FolderColRules {
    param([string]$Spec)
    $rules = @()
    foreach ($part in @("$Spec" -split '[;,]')) {
        $t = "$part".Trim(); if (-not $t) { continue }
        if ($t -match '^(\d{1,2})\s*=\s*(.+)$') {
            $lvl = [int]$Matches[1]
            $col = ($Matches[2] -replace '[^A-Za-z0-9]', '')
            if ($lvl -ge 1 -and $lvl -le 10 -and $col) { $rules += ,([pscustomobject]@{ Level = $lvl; Column = $col }) }
        }
    }
    return ,$rules
}
function Confirm-ProvenanceColumns {
    param($Config, [string]$DriveId)
    if ($null -eq $script:ProvColReady) { $script:ProvColReady = @{} }
    if ($script:ProvColReady.ContainsKey($DriveId)) { return [bool]$script:ProvColReady[$DriveId] }
    $ok = $false
    try {
        $li = Invoke-WithRetry -Config $Config -What 'provenance list lookup' -Action {
            Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$DriveId/list?`$select=id,parentReference"
        }
        $listId = "$($li['id'])"; $siteId = "$($li['parentReference']['siteId'])"
        if (-not $listId) { $listId = "$($li.id)"; $siteId = "$($li.parentReference.siteId)" }
        if ($listId -and $siteId) {
            $colResp = Invoke-WithRetry -Config $Config -What 'provenance column lookup' -Action {
                Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns?`$select=name&`$top=999"
            }
            $have = @()
            try { $have = @($colResp['value'] | ForEach-Object { "$($_['name'])" }) } catch {}
            if (-not $have.Count) { try { $have = @($colResp.value | ForEach-Object { "$($_.name)" }) } catch {} }
            $defs = @()
            if ($script:ProvColsOn) {
                $defs += @(
                    @{ name = 'SourcePath';  displayName = 'Source path';  description = 'Original location at the migration source'; text = @{} }
                )
                if ($script:ProvOwnerAvailable) {
                    $defs += ,@{ name = 'SourceOwner'; displayName = 'Source owner'; description = 'Owner at the migration source'; text = @{} }
                }
                $defs += @(
                    @{ name = 'MigratedOn';  displayName = 'Migrated on';  description = 'When this file was migrated';               dateTime = @{ displayAs = 'default'; format = 'dateTime' } }
                )
            }
            foreach ($fr in @($script:FolderColRules)) {
                $defs += ,@{ name = "$($fr.Column)"; displayName = "$($fr.Column)"; description = "From folder level $($fr.Level) at the migration source"; text = @{} }
            }
            foreach ($nc in @(@($script:FilenameColRules) | ForEach-Object { $_.Columns } | Select-Object -Unique)) {
                if ($nc) { $defs += ,@{ name = "$nc"; displayName = "$nc"; description = 'Extracted from the file name at the migration source'; text = @{} } }
            }
            if (@($script:ExtCatRules).Count) { $defs += ,@{ name = 'Category'; displayName = 'Category'; description = 'File category from its type at the migration source'; text = @{} } }
            if ($script:RetentionYears -gt 0) { $defs += ,@{ name = 'Retention'; displayName = 'Retention'; description = 'Flagged for review: not modified in a long time at the source'; text = @{} } }
            foreach ($d in $defs) {
                if ($have -contains $d.name) { continue }
                Invoke-WithRetry -Config $Config -What "create column $($d.name)" -Action {
                    Invoke-LiscGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/columns" -Body ($d | ConvertTo-Json -Depth 4) -ContentType 'application/json' | Out-Null
                }
            }
            $ok = $true
        }
    } catch {
        $__edump = $null; try { $__edump = ($_ | Format-List -Force | Out-String) } catch {}; Write-MigrationLog WARN "Provenance columns could not be prepared on this library ($($_.Exception.Message)). Files migrated fine; the columns are skipped for this destination."; try { if ($__edump) { Write-MigrationLog WARN ("[DIAG-DUMP]`n" + $__edump) } } catch {}
    }
    $script:ProvColReady[$DriveId] = $ok
    return $ok
}
function Set-ProvenanceFields {
    param($Config, [string]$DriveId, [string]$EncPath, [string]$SourcePath, [string]$SourceOwner, [string]$MigratedOnIso, [hashtable]$ExtraFields)
    $bodyH = @{}
    if ("$MigratedOnIso") {
        $bodyH['SourcePath'] = "$SourcePath"
        $bodyH['MigratedOn'] = "$MigratedOnIso"
        if ("$SourceOwner") { $bodyH['SourceOwner'] = "$SourceOwner" }
    }
    if ($ExtraFields) { foreach ($k in $ExtraFields.Keys) { $bodyH[$k] = "$($ExtraFields[$k])" } }
    if (-not $bodyH.Count) { return }
    $body = $bodyH | ConvertTo-Json
    Invoke-WithRetry -Config $Config -What "provenance fields $SourcePath" -Action {
        Invoke-LiscGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/${EncPath}:/listItem/fields" -Body $body -ContentType 'application/json' | Out-Null
    }
}
function Invoke-ProvenanceColumnSweep {
    param($Config, [string]$AuditFile)
    if (-not $script:ProvColsOn -and -not @($script:FolderColRules).Count -and -not @($script:FilenameColRules).Count -and -not @($script:ExtCatRules).Count -and $script:RetentionYears -le 0) { return }
    if ("$($Config.destination.provider)" -eq 'LocalSim') { return }
    if (-not $AuditFile -or -not (Test-Path $AuditFile)) { return }
    try {
        $rows = @(Import-AuditCsv $AuditFile | Where-Object { $_.Space -ne '(run)' -and "$($_.Status)" -match '^(Copied|ZeroByte|Repaired)' -and "$($_.DestPath)".Trim() })
        if (-not $rows.Count) { return }
        $map = @{}
        foreach ($m in @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')) { $map[$m.Space] = $m }
        $script:ProvOwnerAvailable = (@(@($map.Values) | Where-Object { $o = "$($_.OwnerResolved)"; $o -and $o -ne 'n/a' }).Count -gt 0)
        $onIso = (Get-Date).ToUniversalTime().ToString('o')
        Write-MigrationLog INFO "Stamping provenance columns (Source path$(if ($script:ProvOwnerAvailable) { ' / Source owner' } else { '' }) / Migrated on) onto $($rows.Count) migrated file(s)..."
        $done = 0; $i = 0
        foreach ($r in $rows) {
            $i++
            if (($i % 25) -eq 0) { Lz3402e3c9c5 -Activity 'Provenance columns' -Status "$i of $($rows.Count)" -Current $i -Total $rows.Count | Out-Null }
            $mrow = $map[$r.Space]
            if (-not $mrow) { continue }
            $driveId = $null
            try { $driveId = (Resolve-DestinationDriveId -Config $Config -Row $mrow).DriveId } catch { continue }
            if (-not $driveId) { continue }
            if (-not (Confirm-ProvenanceColumns -Config $Config -DriveId $driveId)) { continue }
            $owner = "$($mrow.OwnerResolved)"; if ($owner -eq 'n/a') { $owner = '' }
            $enc = ([uri]::EscapeDataString(("$($r.DestPath)" -replace '\\','/')) -replace '%2F','/')
            $extra = @{}
            $relRaw   = ("$($r.SourcePath)" -replace '\\','/').TrimStart('/')
            $spaceSeg = "$($r.Space)"
            $relUnder = $relRaw
            if ($spaceSeg -and ($relRaw -eq $spaceSeg -or $relRaw.StartsWith(($spaceSeg + '/'), [System.StringComparison]::Ordinal))) {
                $relUnder = $relRaw.Substring([Math]::Min($spaceSeg.Length + 1, $relRaw.Length))
            }
            $relParts = @($relUnder -split '/')
            if (@($script:FolderColRules).Count) {
                $dirCount = $relParts.Count - 1
                foreach ($fr in @($script:FolderColRules)) {
                    if ($dirCount -ge $fr.Level) { $extra[$fr.Column] = $relParts[$fr.Level - 1] }
                }
            }
            if (@($script:FilenameColRules).Count) {
                $leaf = $relParts[$relParts.Count - 1]
                foreach ($fr in @($script:FilenameColRules)) {
                    $m = $fr.Regex.Match($leaf)
                    if ($m.Success) {
                        foreach ($cn in @($fr.Columns)) {
                            if ($m.Groups[$cn].Success -and -not $extra.ContainsKey($cn)) { $extra[$cn] = $m.Groups[$cn].Value }
                        }
                    }
                }
            }
            if (@($script:ExtCatRules).Count -and -not $extra.ContainsKey('Category')) {
                $ext = [System.IO.Path]::GetExtension($relParts[$relParts.Count - 1]).ToLowerInvariant()
                foreach ($er in @($script:ExtCatRules)) { if (@($er.Exts) -contains $ext) { $extra['Category'] = $er.Category; break } }
            }
            if ($script:RetentionYears -gt 0 -and -not $extra.ContainsKey('Retention')) {
                $mt = $null; try { $mt = ([datetimeoffset]::Parse("$($r.SourceModifiedUtc)", [System.Globalization.CultureInfo]::InvariantCulture)).UtcDateTime } catch {}
                if ($mt -and ((Get-Date).ToUniversalTime() - $mt).TotalDays -gt ($script:RetentionYears * 365.25)) {
                    $extra['Retention'] = "Review candidate: not modified since $($mt.ToString('yyyy'))"
                }
            }
            try {
                $trioOn = [bool]$script:ProvColsOn
                Set-ProvenanceFields -Config $Config -DriveId $driveId -EncPath $enc `
                    -SourcePath $(if ($trioOn) { $(if ($spaceSeg) { "$spaceSeg/$relUnder" } else { $relUnder }) } else { '' }) `
                    -SourceOwner $(if ($trioOn) { $owner } else { '' }) `
                    -MigratedOnIso $(if ($trioOn) { $onIso } else { '' }) `
                    -ExtraFields $extra
                $smu = $(if ($r.PSObject.Properties['SourceModifiedUtc']) { "$($r.SourceModifiedUtc)" } else { '' })
                if (($trioOn -or $extra.Count) -and $smu) {
                    Set-GraphFileDates -Config $Config -DriveId $driveId -EncPath $enc -Mtime $smu -ModifiedOnly
                }
                $done++
            } catch {
                $failMsg = "$($_.Exception.Message)"
                Write-MigrationLog WARN "Provenance fields for '$($r.DestPath)' were refused ($failMsg)."
                if ($failMsg -match '400|[Ii]nvalid|[Bb]ad ?[Rr]equest') { Write-MigrationLog WARN "This library refused the provenance fields; skipping the rest for this destination."; $script:ProvColReady[$driveId] = $false }
            }
        }
        try { Write-Progress -Activity 'Provenance columns' -Completed } catch {}
        if ($done -eq 0 -and $rows.Count -gt 0) {
            Write-MigrationLog WARN "Provenance columns stamped on 0 of $($rows.Count) file(s). See the warning(s) above for why; the files themselves are unaffected."
        } elseif ($done -lt $rows.Count) {
            Write-MigrationLog WARN "Provenance columns stamped on $done of $($rows.Count) file(s); the rest were refused (see above). Every stamped file now answers 'where did this come from, whose was it, when did it move' in the library itself."
        } else {
            Write-MigrationLog OK "Provenance columns stamped on $done of $($rows.Count) file(s). Every file now answers 'where did this come from, whose was it, when did it move' in the library itself."
        }
    } catch {
        Write-MigrationLog WARN "Provenance column stamping hit a problem ($($_.Exception.Message)). The run itself is unaffected."
    }
}
function Invoke-RunFinalize {
    param($Config,[string]$AuditFile,[string]$Mode='FirstPass',[datetime]$RunStart=(Get-Date),
          [int]$ExpectedFiles=0,[int]$SpacesPlanned=0,[int]$SpacesCompleted=0,$RunError=$null,
          [string]$ForcedStatus='',[string]$ForcedReason='')
    $elapsed = (Get-Date) - $RunStart
    $el = '{0:hh\:mm\:ss}' -f $elapsed
    $vitals = $null; try { $vitals = Lz162301ffe6 } catch {}
    $copied=0;$skipped=0;$failed=0;$verify=0;$zero=0;$notAttempted=0;$processed=0;[int64]$bytes=0;$auditWriteFails=0
    $auditRows = @()
    if ($AuditFile -and (Test-Path $AuditFile)) {
        for ($t=1;$t -le 6;$t++){ try { $auditRows = @(Import-AuditCsv $AuditFile); break } catch { Start-Sleep -Milliseconds (150*$t) } }
    }
    foreach ($r in $auditRows) {
        switch ("$($r.Status)") {
            'Copied'        { $copied++; $processed++; try { $bytes += [int64]$r.SourceSizeBytes } catch {} }
            'ZeroByte'      { $zero++; $copied++; $processed++ }
            'Skipped'       { $skipped++; $processed++ }
            'NotAttempted'  { $notAttempted++; $processed++ }
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
    $clashes = 0; $clashSpaces = ''; $clashFirst = ''
    try {
        $cg = @(Get-AuditCollisionGroups -Config $Config -Rows $auditRows)
        $clashes = $cg.Count
        if ($clashes) {
            $clashSpaces = (@($cg | ForEach-Object { $_.Spaces } | Sort-Object -Unique) -join '; ')
            $clashFirst = "$($cg[0].Dest)"
        }
    } catch {}
    $unreadable = 0; $unreadableWhere = 'the source'
    try {
        $unreadable = [int]$script:UnreadableCount
        $ul = @(@($script:UnreadableSpaces) | Where-Object { $_ })
        if ($ul.Count -eq 1) { $unreadableWhere = "[$($ul[0])]" } elseif ($ul.Count) { $unreadableWhere = "$($ul.Count) source(s)" }
    } catch {}
    if ($ForcedStatus) {
        $status = $ForcedStatus; $reason = $ForcedReason
    } elseif ($script:TrialCapped -or $notAttempted -gt 0) {
        $status = 'CAPPED'
        $reason = "evaluation limit reached: $copied file(s) copied for real, $notAttempted file(s) NOT attempted (never checked or copied) - a licence is required to migrate the rest"
        if ($errCount -gt 0) { $reason += "; also $errCount file(s) failed or could not be verified" }
    } else {
        $finished = (-not $RunError) -and ($SpacesCompleted -ge $SpacesPlanned)
        if (-not $finished)      { $status='ENDED_EARLY'; $reason = if ($RunError) { (("$($RunError.Exception.Message)") -replace [regex]::Escape("$($script:StopTag)"), '').Trim() } else { "stopped after $SpacesCompleted of $SpacesPlanned project(s)" } }
        elseif ($errCount -gt 0 -or $unreadable -gt 0) {
            $status = 'COMPLETED_WITH_ERRORS'
            $rParts = @()
            if ($errCount -gt 0)   { $rParts += "$errCount file(s) failed or could not be verified" }
            if ($unreadable -gt 0) { $rParts += "$unreadable folder(s)/file(s) under $unreadableWhere could NOT be read, so they were never copied - this run is NOT a complete copy of the source" }
            $reason = ($rParts -join '; ')
        }
        else                     { $status='COMPLETED'; $reason='' }
    }
    if ($auditWriteFails -gt 0) { $reason = ("$reason (note: $auditWriteFails audit row(s) could not be written, so counts may under-report)").Trim() }
    if ($clashes -gt 0) {
        $clashTxt = "$clashes name clash(es): two $($script:SrcItem) files landed on the same destination path (first: $clashFirst), so one has overwritten the other - see the collisions list in the report"
        $reason = if ($reason) { "$reason; $clashTxt" } else { $clashTxt }
    }
    $szTxt = Format-Bytes $bytes
    $runEndOk = $false
    try {
        $runEndOk = [bool](Write-AuditRunEnd -AuditFile $AuditFile -Status $status -Reason $reason -Processed $processed -Expected $ExpectedFiles `
            -Copied $copied -Skipped $skipped -Failed $failed -VerifyFail $verify -ZeroByte $zero `
            -Bytes $bytes -SpacesPlanned $SpacesPlanned -SpacesCompleted $SpacesCompleted -ElapsedText $el -NotAttempted $notAttempted)
    } catch {}
    if (-not $runEndOk) {
        $auditWriteFails++; try { $script:AuditWriteFails++ } catch {}
        $reason = ("$reason (note: the run-end record could not be written to the audit file, so the audit alone does not show how this run ended; this outcome file does)").Trim()
        try { Write-MigrationLog WARN "  the run-end record could not be written to the audit file [$AuditFile]. The outcome is still recorded in lastrun-outcome.json and the report." } catch {}
    }
    $outcome = [ordered]@{
        Status=$status; Reason=$reason; Mode=$Mode; Finished=($status -eq 'COMPLETED' -or $status -eq 'COMPLETED_WITH_ERRORS')
        StartUtc=$RunStart.ToUniversalTime().ToString('o'); EndUtc=(Get-Date).ToUniversalTime().ToString('o'); ElapsedText=$el
        ExpectedFiles=$ExpectedFiles; ProcessedFiles=$processed
        Resumed=[bool]$script:UseEnumCache
        Copied=$copied; Skipped=$skipped; NotAttempted=$notAttempted; Failed=$failed; VerifyFail=$verify; ZeroByte=$zero
        Unreadable=$unreadable
        Collisions=$clashes; CollisionSpaces=$clashSpaces
        UnreadableSpaces=(@(@($script:UnreadableSpaces) | Where-Object { $_ }) -join '; ')
        Bytes=$bytes; BytesText=$szTxt; SpacesPlanned=$SpacesPlanned; SpacesCompleted=$SpacesCompleted
        SpaceNames=(@(@($script:RunSpaceNames) | Where-Object { $_ }) -join "`n")
        AuditWriteFails=$auditWriteFails; AuditFile="$AuditFile"; LogFile="$script:LogFile"
        SpoolEncrypted=[bool]$script:SpoolEncrypt
        TrialMode=($null -ne $script:TrialCap); TrialLimit=$script:TrialFileLimit; TrialCapped=[bool]$script:TrialCapped
        ToolVersion=(Lzb0b39673dd)
        Vitals=$(if ($vitals) { @($vitals.Lines) } else { @() })
        VitalsMachine=$(if ($vitals) { "$($vitals.Machine)" } else { '' })
    }
    $json = ($outcome | ConvertTo-Json -Depth 4)
    $sidecar = ($AuditFile -replace '\.csv$','') + '.outcome.json'
    foreach ($p in @($sidecar, (Join-Path $Config.run.reportRoot 'lastrun-outcome.json'))) {
        try { [System.IO.File]::WriteAllText($p, $json, [System.Text.UTF8Encoding]::new($false)) } catch {}
    }
    $listedTxt = [math]::Max([int]$ExpectedFiles, [int]$script:ListedTotal)
    if ($clashes -gt 0) { try { Write-MigrationLog WARN "  $clashes NAME CLASH(ES): two $($script:SrcItem) files landed on the same destination path, so one has overwritten the other (first: $clashFirst). Sources involved: $clashSpaces. Every clash is listed in the report and the collisions CSV. Fix the mapping or rename at the source, then run again." } catch {} }
    try {
        switch ($status) {
            'COMPLETED'             { if ($clashes -gt 0) { Write-MigrationLog WARN "=== RUN COMPLETE, WITH $clashes NAME CLASH(ES): all $SpacesPlanned $($script:SrcItem)(s) finished. Uploaded $copied file(s) ($szTxt), 0 failures, in $el, but $clashes file(s) overwrote another source's file. ===" } else { Write-MigrationLog OK    "=== RUN COMPLETE: all $SpacesPlanned $($script:SrcItem)(s) finished. Uploaded $copied file(s) ($szTxt), skipped $skipped unchanged, 0 failures, in $el. ===" } }
            'COMPLETED_WITH_ERRORS' { Write-MigrationLog ERROR "=== RUN COMPLETE WITH ERRORS: reached the end of all $SpacesPlanned $($script:SrcItem)(s). Uploaded $copied ($szTxt), but $errCount file(s) failed or could not be verified and are NOT marked done. Run 'Sync new and changed' to retry just those. ===" }
            'CAPPED'                { Write-MigrationLog WARN  "=== RUN STOPPED: evaluation limit reached. Uploaded $copied file(s) ($szTxt) for real; $notAttempted file(s) were NOT attempted (never checked or copied) because the free evaluation cap was hit. Licence this tenant to migrate the rest, then run 'Sync new and changed' to pick up where it stopped. ===" }
            'CANCELLED'             { Write-MigrationLog WARN  "=== RUN CANCELLED by user. Uploaded $copied file(s) ($szTxt) before stopping; those are saved. The rest were NOT uploaded. Click 'Sync new and changed' to carry on from where it stopped: it copies only what is not already there. ===" }
            'INCOMPLETE'            { Write-MigrationLog ERROR "=== RUN INCOMPLETE: the previous run stopped without finalising (a crash, a forced close, or power loss). $copied file(s) ($szTxt) were recorded as uploaded. Run 'Sync new and changed' to continue and confirm. ===" }
            default                 { Write-MigrationLog ERROR "=== RUN ENDED EARLY - DID NOT FINISH. Processed $processed file(s) (of ~$listedTxt listed) across $SpacesCompleted of $SpacesPlanned $($script:SrcItem)(s) before stopping. Reason: $reason. The remaining files were NOT uploaded. Fix the cause, then click 'Sync new and changed' to carry on from where it stopped. ===" }
        }
    } catch {}
    if ($script:GuiMode) { try { Write-Host "##OUTCOME##|$status|$processed|$ExpectedFiles|$copied|$failed|$verify|$el|$reason" } catch {} }
    if ($script:GuiMode -and $script:TrialCapped) { try { Write-Host "##TRIAL##|CAPPED|$($script:TrialFileLimit)|$copied" } catch {} }
    if ($script:TrialLedgerKey) { try { Add-EvalUsage -Key $script:TrialLedgerKey -Bucket $script:TrialBucket -Count $copied } catch {} }
    $script:ExitCode = switch ($status) { 'COMPLETED' { 0 } 'COMPLETED_WITH_ERRORS' { 2 } default { 1 } }
    Close-AppendWriters
    $savedLog = $script:LogFile
    try { Invoke-HtmlReport -Config $Config -AuditPath $AuditFile -NoStageLog | Out-Null } catch {}
    $script:LogFile = $savedLog
    try {
        $emBucket = switch ($status) { 'COMPLETED' { if ($clashes -gt 0) { 'Warning' } else { 'Success' } } 'COMPLETED_WITH_ERRORS' { 'Warning' } 'CAPPED' { 'Warning' } default { 'Failure' } }
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
                $(if ($clashes -gt 0) { "Name clashes: $clashes - one source file overwrote another (sources: $clashSpaces). See the report." } else { "Name clashes: none" }),
                "Duration: $el",
                "Source: $($emVars['Source'])",
                "Destination: $($emVars['Destination'])")
    } catch {}
    Lze3b49cb7ce -Config $Config
    return $outcome
}
function Lz0e4ac9dd84 {
    param($Config,[string]$Mode,[datetime]$RunStart,[int]$ExpectedFiles,[int]$SpacesPlanned,
          [int]$SpacesCompleted,$RunError,[bool]$WillWrite,[string]$ResultDir='')
    if (-not $WillWrite) {
        try { Lz162301ffe6 | Out-Null } catch {}
        if (-not $ResultDir -and $script:AuditFile -and (Test-Path $script:AuditFile)) {
            $savedLog = $script:LogFile
            try { Invoke-HtmlReport -Config $Config -AuditPath $script:AuditFile -NoStageLog | Out-Null } catch {}
            $script:LogFile = $savedLog
        }
        return
    }
    if ($ResultDir)      { try { Lz162301ffe6 | Out-Null } catch {}; return }
    Invoke-RunFinalize -Config $Config -AuditFile $script:AuditFile -Mode $Mode -RunStart $RunStart `
        -ExpectedFiles $ExpectedFiles -SpacesPlanned $SpacesPlanned -SpacesCompleted $SpacesCompleted -RunError $RunError | Out-Null
}
function Invoke-FinalizeAction {
    param($Config,[string]$Status='Incomplete',[string]$AuditPath='')
    Lz93fa3c46d9 -Config $Config -Stage 'api-finalize'
    $act = $null
    $ap = Get-RunActivePath $Config
    if (Test-Path $ap) { try { $act = Get-Content $ap -Raw | ConvertFrom-Json } catch {} }
    if ($act) { $act = $act | Select-Object AuditFile, StartUtc, Mode, ExpectedFiles, SpacesPlanned, SpacesCompleted, ResultDir }
    if (-not $AuditPath -and $act) {
        $mModeF = if ($act.Mode) { "$($act.Mode)" } else { 'FirstPass' }
        if (-not "$($act.AuditFile)" -and "$($act.ResultDir)" -and (Test-Path "$($act.ResultDir)")) {
            $childRows = New-Object System.Collections.Generic.List[object]
            foreach ($a in @(Get-ChildItem "$($act.ResultDir)" -Filter 'audit-*.csv' -ErrorAction SilentlyContinue)) { foreach ($r in @(Import-AuditCsv $a.FullName)) { $childRows.Add($r) } }
            Merge-ParallelSideFiles -Config $Config -ResultDir "$($act.ResultDir)" -Mode $mModeF
            $AuditPath = Join-Path $Config.run.reportRoot ("audit-$mModeF-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-finalized.csv')
            if ($childRows.Count) { $childRows | Export-Csv -Path $AuditPath -NoTypeInformation -Encoding UTF8 } else { try { '' | Set-Content -Path $AuditPath -Encoding UTF8 } catch {} }
            Write-MigrationLog INFO "Record outcome: merged $($childRows.Count) file action(s) from the stopped parallel run's $($script:SrcItems) into $AuditPath."
        }
        elseif ("$($act.AuditFile)" -and -not (Test-Path "$($act.AuditFile)")) {
            $AuditPath = "$($act.AuditFile)"
            try { '' | Set-Content -Path $AuditPath -Encoding UTF8 } catch {}
            Write-MigrationLog INFO "Record outcome: the run stopped before it recorded any file, so an empty audit was started to carry its outcome."
        }
    }
    if (-not $AuditPath) {
        if ($act -and $act.AuditFile -and (Test-Path $act.AuditFile)) { $AuditPath = "$($act.AuditFile)" }
        else {
            $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $AuditPath = $latest.FullName }
        }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) {
        Write-MigrationLog WARN "Record outcome: no audit CSV found, so there is nothing to record."; Lze3b49cb7ce -Config $Config; return
    }
    $sidecar = ($AuditPath -replace '\.csv$','') + '.outcome.json'
    if (Test-Path $sidecar) { Write-MigrationLog INFO "Record outcome: the run already has an outcome; leaving it as it is."; Lze3b49cb7ce -Config $Config; return }
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
function Lz3d6ab632fb {
    param([string]$Path)
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if (-not $root) { return -1 }
        return ([System.IO.DriveInfo]::new($root)).AvailableFreeSpace
    } catch { return -1 }
}
function Lz87e717a0d8 {
    param($Config)
    try {
        $thumb = "$($Config.auth.certThumbprint)".Trim()
        if (-not $thumb -or $thumb -like 'reg:*') { return }
        $store = 'Cert:\CurrentUser\My'
        try { if (((Test-ConfigProp $Config.auth 'certStore')) -and $Config.auth.certStore) { $store = "$($Config.auth.certStore)" } } catch {}
        $cert = Get-ChildItem -Path $store -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
        if (-not $cert) { return }
        $days = [math]::Floor(($cert.NotAfter.ToUniversalTime() - [DateTime]::UtcNow).TotalDays)
        if ($days -lt 0) {
            throw "The sign-in certificate expired on $($cert.NotAfter.ToString('yyyy-MM-dd')). Uploads cannot authenticate until it is renewed, so nothing was uploaded. Renew the app certificate and update its thumbprint in Settings."
        } elseif ($days -le 7) {
            Write-MigrationLog WARN "  the sign-in certificate expires in $([int]$days) day(s) (on $($cert.NotAfter.ToString('yyyy-MM-dd'))). Renew it soon to avoid a mid-run authentication failure."
        }
    } catch { throw }
}
function Test-MappingSpaceIds {
    param($Config)
    if ("$($Config.source.provider)" -eq 'LocalFs') {
        $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
        if (-not (Test-Path $mapPath)) { return }
        foreach ($row in @(Import-Csv $mapPath | Where-Object Action -eq 'MIGRATE')) {
            $sp = "$($row.SpaceId)"
            if ($sp -and -not (Test-Path -LiteralPath $sp)) {
                throw "$($script:StopTag)The source folder for '$($row.Space)' is not reachable: '$sp'. If it is on a network share or an external drive, check it is connected and you have permission to read it, then run again. Nothing has been uploaded."
            }
        }
        return
    }
    if ($Config.datto.provider -eq 'LocalSim') { return }
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPath)) { return }
    $known = @{}
    try { foreach ($p in @(Get-DattoSpaces -Config $Config)) { $known["$($p.Id)"] = $p.Name } } catch { return }
    if (-not $known.Count) { return }
    foreach ($row in @(Import-Csv $mapPath | Where-Object Action -eq 'MIGRATE')) {
        $id = "$($row.SpaceId)"
        if ($id -and -not $known.ContainsKey($id)) {
            throw "$($script:StopTag)mapping.csv row '$($row.Space)' has SpaceId '$id', which is not one of this job's $($script:SrcItems). If you were trying to migrate a single folder, do NOT put the folder's id here: it silently strips the folder's path from every destination file, and a later full Sync then copies them all again to the right place and leaves the first set behind as orphans. Put the space's real id back, and set the SourceSubPath column to the folder path instead (for example: Drawings/Current). Nothing has been uploaded."
        }
    }
}
function Lz0ee2c00794 {
    param($Config)
    if ($script:LegacyStateNoticeDone) { return }
    $script:LegacyStateNoticeDone = $true
    try {
        $root = $Config.run.stateRoot
        if (-not $root -or -not (Test-Path $root)) { return }
        $old = @(Get-ChildItem -Path $root -Filter 'apistate-*.json' -File -ErrorAction SilentlyContinue)
        if (-not $old.Count) { return }
        Write-MigrationLog INFO "  found $($old.Count) resume record(s) from an older version in [$root]. They are no longer used: the destination is now the source of truth for what has already been copied. They are harmless, and you can delete them whenever you like. Nothing here will delete them for you."
    } catch {}
}
function Invoke-PreRunChecks {
    param($Config)
    try {
        $nOrph = Clear-OrphanRunTemp -TempRoot "$($Config.run.tempWorkingFolder)"
        if ($nOrph -gt 0) { Write-MigrationLog INFO "  cleared $nOrph leftover staging folder(s) from a previous run that did not finish. Nothing else in the temp folder was touched." }
    } catch {}
    if ($Config.destination.provider -eq 'LocalSim') { return }
    try {
        $tmpRoot = $Config.run.tempWorkingFolder
        if ($tmpRoot -and (Test-Path $tmpRoot)) {
            $freeB = Lz3d6ab632fb -Path $tmpRoot
            if ($freeB -ge 0) {
                Write-MigrationLog INFO "  temp drive free space: $(Format-Bytes $freeB) (files are staged here then deleted immediately after upload, so only a handful sit on disk at once)."
                if ($freeB -lt 2GB) { Write-MigrationLog WARN "  the temp drive has under 2 GB free. Everyday files are fine (only a handful stage at a time), but any single file larger than the free space is skipped and reported. Free space, or point run.tempWorkingFolder at a bigger drive." }
            }
        }
    } catch {}
    Lz87e717a0d8 -Config $Config
}
function Get-ReservedDestSegment {
    param([string]$Path)
    foreach ($seg in ("$Path" -split '[\\/]')) { $s = $seg.Trim(); if ($s -and ($script:ReservedWholeNames -contains $s.ToLowerInvariant())) { return $s } }
    return ''
}
function Test-DestinationReadiness {
    param($Config, $Rows)
    if ($Config.destination.provider -eq 'LocalSim') { return }
    $seen = @{}
    foreach ($row in $Rows) {
        $tsf = if ($row.PSObject.Properties.Name -contains 'TargetSubFolder') { "$($row.TargetSubFolder)" } else { '' }
        $rsvSeg = Get-ReservedDestSegment $tsf
        if ($rsvSeg) { throw "The destination folder '$tsf' for '$($row.Space)' contains '$rsvSeg', which is reserved by Microsoft 365 and cannot be used as a folder name. In plain terms: nothing could be uploaded into it, so nothing was uploaded. Change the destination folder name (for example to '${rsvSeg}_') and run again." }
        $key = "$($row.DestinationType)|$($row.DestinationUrl)|$($row.TargetPrincipal)|$($row.TargetLibrary)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $label = Format-Destination -Row $row
        try {
            $res = Resolve-DestinationDriveId -Config $Config -Row $row
            $free = $null
            try {
                $drv = Invoke-WithRetry -Config $Config -What "quota $label" -Action { Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$($res.DriveId)" }
                try { $free = [int64]$drv['quota']['remaining'] } catch { try { $free = [int64]$drv.quota.remaining } catch {} }
            } catch {}
            if ($null -ne $free -and $free -gt 0) {
                $ftxt = Format-Bytes $free
                if ($free -lt 2GB) { Write-MigrationLog WARN "  destination check: $label is reachable but has only $ftxt free. A large upload may fail part-way; free up space or pick another destination." }
                else { Write-MigrationLog OK "  destination check: $label reachable, $ftxt free." }
            } else {
                Write-MigrationLog OK "  destination check: $label reachable."
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
        Write-MigrationLog INFO "Resume now runs as a Sync: it compares $($script:SrcNoun) against the destination itself, file by file, instead of trusting a local record of the last run. Same intent, and it cannot be fooled by a stale or damaged record."
    }
    Lz93fa3c46d9 -Config $Config -Stage "api-transfer-$Mode" -Friendly $(
        if (-not $Execute) { if ($Mode -eq 'Delta') { 'Sync preview (nothing copied)' } else { 'Preview (nothing copied)' } }
        elseif ($FailedOnly) { 'Rerun failed files' }
        elseif ($Mode -eq 'Delta') { if ($DeltaMode -eq 'AddMissing') { 'Sync - add new files only' } else { 'Sync - update where newer' } }
        else { 'Full migration' })
    $script:FailedOnlySet = $null
    if ($FailedOnly) {
        $MaxParallelSpaces = 1
        $script:UseEnumCache = $false
        $script:FailedOnlySet = Build-FailedOnlySet -Config $Config -AuditPath $FailedFromAudit
    }
    Lz0ee2c00794 -Config $Config
    Test-MappingSpaceIds -Config $Config
    if ($Execute -and $Config.destination.provider -ne 'LocalSim' -and $null -eq $script:TrialCap) {
        $lzOk = $false; $lzTen = ''
        try {
            $lzP = ''
            try { if (((Test-ConfigProp $Config.run 'licenceFile')) -and $Config.run.licenceFile) { $lzP = "$($Config.run.licenceFile)" } } catch {}
            if (-not $lzP) { $lzP = Join-Path (Split-Path $PSScriptRoot -Parent) 'licence.json' }
            if (Test-Path $lzP) {
                $lzJ = Get-Content $lzP -Raw | ConvertFrom-Json
                $lzB = [Convert]::FromBase64String("$($lzJ.PayloadB64)")
                $lzE = [System.Security.Cryptography.ECDsa]::Create()
                try {
                    $lzR = 0
                    $lzKey = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEMOOjrKfrPG0mI1XtA+iXZVOwtjp075WeGEYaNZxG0TyVvAp6B9SZ3AAX5Ue7AxQrrwTfDzzX2lIgT7TmVKt9XA=='
                    if ($env:LISCARA_LICKEY_TEST -and -not (Test-Path (Join-Path $PSScriptRoot 'integrity.json'))) { $lzKey = "$env:LISCARA_LICKEY_TEST" }
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
            Write-MigrationLog WARN "Evaluation limits apply to this run: up to $lzRem file(s) will be copied. Licence this Microsoft tenant at https://www.liscaragh.com to remove the limit."
        }
    }
    $runStart = Get-Date
    $auditDir = if ($ResultDir) { $ResultDir } else { $Config.run.reportRoot }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:AuditFile = Join-Path $auditDir ("audit-$Mode-$stamp-$PID.csv")
    $script:AuditWriteFails = 0
    $script:SweepList = [System.Collections.Generic.List[object]]::new()
    $script:RenameFile     = Join-Path $auditDir ("renames-$Mode-$stamp-$PID.csv")
    $script:CollisionFile  = Join-Path $auditDir ("collisions-$Mode-$stamp-$PID.csv")
    $script:ExcludedFile   = Join-Path $auditDir ("excluded-$Mode-$stamp-$PID.csv")
    Lzc9d8fe4f48
    if ($script:SelectionRules.Count -and -not $ResultDir) { try { Copy-Item -LiteralPath (Join-Path $Config.run.reportRoot 'selection.json') -Destination (Join-Path $auditDir ("selection-$Mode-$stamp-$PID.json")) -Force } catch {} }
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
    else { Write-MigrationLog INFO "No readiness check was run for this job (it is optional). The upload checks the destination is reachable before it starts, tidies names as it goes, and flags any problems in the report." }
    $runnable = @($map | Where-Object { $blockedSpaces -notcontains $_.Space })
    if ($MaxParallelSpaces -gt 1 -and $null -ne $script:TrialCap) {
        Write-MigrationLog INFO "Evaluation mode runs one $($script:SrcItem) at a time, so the free allowance is counted once."
        $MaxParallelSpaces = 1
    }
    if ($MaxParallelSpaces -gt 1 -and $runnable.Count -gt 1) {
        Lzd0f3347cf6 -Config $Config -Rows $runnable -Mode $Mode -DeltaMode $DeltaMode -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -Execute:$Execute
        return
    }
    Write-MigrationLog INFO "This run: $($map.Count) $($script:SrcItem)(s). (Read-ahead: $SpoolAhead file(s).)"
    if ($script:SpoolEncrypt) {
        $script:SpoolKey = New-SpoolKey
        Write-MigrationLog OK "Files staged on this computer are ENCRYPTED (AES-256) while they wait to upload. The key exists only in this run's memory and dies with it, staged names are random identifiers, and the destination receives the original files unchanged."
    } else {
        $script:SpoolKey = $null
        Write-MigrationLog INFO "Spool encryption is OFF (run.encryptSpool = false): files staged on this computer are readable while a run is in flight."
    }
    Lz1338c7e606 -Config $Config
    Connect-Destination -Config $Config
    $expectedTotal   = 0
    $script:ListedTotal = 0
    $spacesPlanned   = @($map | Where-Object { $blockedSpaces -notcontains $_.Space }).Count
    $script:RunSpaceNames = @($map | Where-Object { $blockedSpaces -notcontains $_.Space } | ForEach-Object { "$($_.Space)" })
    $spacesCompleted = 0
    $transferError   = $null
    if ($willWrite -and -not $ResultDir) { Lz6aa2b8bd37 -Config $Config -Mode $Mode -StartUtc $runStart -AuditFile $script:AuditFile -ExpectedFiles 0 -SpacesPlanned $spacesPlanned -SpacesCompleted 0 }
    $summary = New-Object System.Collections.Generic.List[object]
    $sTotal = $map.Count; $sIdx = 0
    try {
    if ($willWrite) { Test-DestinationReadiness -Config $Config -Rows $map; Invoke-PreRunChecks -Config $Config }
    foreach ($row in $map) {
        $sIdx++
        $script:VitalsPipe = $null
        Lz3402e3c9c5 -Activity "Transfer ($Mode)" -Status $row.Space -Current $sIdx -Total $sTotal -Id 1 | Out-Null
        if ($blockedSpaces -contains $row.Space) { Write-MigrationLog ERROR "SKIPPED '$($row.Space)': the readiness check found too little storage at this destination. Increase the quota or free up space, then run again."; continue }
        Write-MigrationLog INFO "[$(if (-not $willWrite) { 'Preview' } elseif ($Mode -eq 'Delta') { 'Sync' } else { 'Upload' })] source [$($row.Space)] -> destination $(Format-Destination -Row $row)"
        if ($script:GuiMode -and -not $ResultDir) { Write-Host "##SOURCE##|$sIdx|$sTotal|$($row.Space)" }
        $space = New-SpaceRef -Row $row -Config $Config
        $overlapListing = $false
        try { if (((Test-ConfigProp $Config.run.upload 'overlapListing')) -and $Config.run.upload.overlapListing) { $overlapListing = $true } } catch {}
        $streamFP = ($Mode -eq 'FirstPass' -and $willWrite -and $UploadWorkers -gt 1 -and $overlapListing -and ($null -eq $script:TrialCap))
        if ($streamFP) {
            Write-MigrationLog INFO "  Upload all: listing and uploading run together (files start moving while the folder list is still being read)."
            $items = @()
        } else {
            $rowScope = "$($row.Space)"
            try { if (((Test-ConfigProp $row 'SourceSubPath')) -and "$($row.SourceSubPath)".Trim()) { $rowScope = "$($row.Space) / $("$($row.SourceSubPath)".Trim().Trim('/'))" } } catch {}
            Write-MigrationLog INFO "  listing files in [$rowScope] (large $($script:SrcItems) can take a few minutes, nothing uploads yet)..."
            try {
                $items = @(Get-SpaceItemsCached -Config $Config -Space $space)
            } catch {
                Write-MigrationLog ERROR "  could not read files for '$($row.Space)': $($_.Exception.Message). In plain terms: the source may be empty, moved, or unreachable. Skipping it in this run."
                continue
            }
            Write-MigrationLog INFO "  listing complete: $($items.Count) file(s)."
            $script:SrcTotal = @($items).Count
            $script:ListedTotal += @($items).Count
        }
        $spaceTemp = Join-Path (Get-RunTempRoot -Config $Config) (ConvertTo-Slug $row.Space)
        if (Test-Path $spaceTemp) { Get-ChildItem $spaceTemp -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
        else { New-Item -ItemType Directory -Path $spaceTemp -Force | Out-Null }
        $driveId = '(dry-run)'; $effSub = (Join-SubPath $row.TargetSubFolder (Get-NestFolder $Config $row))
        if ($willWrite) { $res = Resolve-DestinationDriveId -Config $Config -Row $row; $driveId = $res.DriveId; $effSub = $res.SubFolder }
        $nestNote = if (Get-NestFolder $Config $row) { ' (the ' + $script:SrcItem + ' has its own folder inside your chosen destination)' } else { '' }
        if ($effSub) { Write-MigrationLog INFO "  files land under: [$effSub]$nestNote." }
        elseif ($nestNote) { Write-MigrationLog INFO "  files land under the $($script:SrcItem)'s own folder at the destination root." }
        $copied = 0; $skipped = 0; $failed = 0; $bytes = 0; $verifyFail = 0; $zero = 0
        $presenceMode = $false
        $repair = @{}
        $san = (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames)
        if ($restoreSet.Count) {
            $toDo = @($items | Where-Object { $restoreSet.ContainsKey("$($_.Id)") })
            Write-MigrationLog INFO "  restore: $($toDo.Count) selected file(s) will be overwritten at the destination with the $($script:SrcNounBare) version."
        }
        elseif ($Mode -eq 'FirstPass') {
            $toDo = @($items)
        }
        elseif ($Mode -eq 'Delta') {
            $presenceMode = $true
            if ($willWrite) { $inv = Get-DestinationInventory -Config $Config -Row $row -WithTimes }
            else {
                try { $inv = Get-DestinationInventory -Config $Config -Row $row -WithTimes; $script:SyncPreviewRead = $true }
                catch {
                    Write-MigrationLog WARN "  could not read the destination for this Sync preview ($($_.Exception.Message)), so every file is counted as new. A real Sync reads it again."
                    $inv = @{ Paths = (New-Object 'System.Collections.Generic.HashSet[string]'); Times = @{} }
                }
            }
            $addOnly = ($DeltaMode -eq 'AddMissing')
            $tol = [TimeSpan]::FromSeconds(2)
            $toDo = @($items | Where-Object {
                $rp = $_.RelativePath -replace '\\','/'; if ($san) { $rp = ConvertTo-SafeRelPath $rp }
                if (-not $inv.Paths.Contains($rp)) { return $true }
                $ds = $null; if ($inv.Sizes -and $inv.Sizes.ContainsKey($rp)) { $ds = [int64]$inv.Sizes[$rp] }
                if ($null -ne $ds -and -not (Lz23003cb7de -RelPath $rp -SourceSize ([int64]$_.Size) -DestSize $ds)) {
                    $repair["$($_.Id)"] = "destination copy was $ds byte(s), source is $($_.Size) byte(s)"
                    return $true
                }
                if ($addOnly) { return $false }
                $st = ConvertTo-UtcDate $_.ModifiedUtc
                $dt = if ($inv.Times.ContainsKey($rp)) { $inv.Times[$rp] } else { $null }
                if ($null -eq $st -or $null -eq $dt) { return $false }
                $isStaleAtDest = ($st -gt $dt.Add($tol))
                if ($isStaleAtDest) {
                    Write-MigrationLog INFO "      sync out-of-date check: $rp - source $($st.ToString('o')) vs destination $($dt.ToString('o')) (tolerance $($tol.TotalSeconds)s)"
                }
                return $isStaleAtDest
            })
            $modeTxt = if ($addOnly) { 'add new files only' } else { "update where $($script:SrcNounBare) is newer" }
            Write-MigrationLog INFO "  sync ($modeTxt): $($toDo.Count) of $($items.Count) file(s) to copy; the rest are already present and are left as they are."
            if ($repair.Count) {
                Write-MigrationLog WARN "  $($repair.Count) of those file(s) are ALREADY at the destination but are the wrong size, and will be re-copied to repair them. These are uploads that did not complete correctly on an earlier run, not new or changed files. They are recorded as 'repaired' in the audit CSV, not as ordinary copies."
            }
        }
        else {
            $toDo = @($items)
        }
        $toDo = @($toDo)
        $toDoPreCapIds = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($it in $toDo) { [void]$toDoPreCapIds.Add("$($it.Id)") }
        $capCutIds = New-Object 'System.Collections.Generic.HashSet[string]'
        if ($null -ne $script:TrialCap) {
            if ($script:TrialFilesRemaining -le 0) {
                if ($toDo.Count -gt 0) { $script:TrialCapped = $true; foreach ($it in $toDo) { [void]$capCutIds.Add("$($it.Id)") } }
                $toDo = @()
            } elseif ($toDo.Count -gt $script:TrialFilesRemaining) {
                $script:TrialCapped = $true
                $kept = @($toDo | Select-Object -First $script:TrialFilesRemaining)
                $keptIds = New-Object 'System.Collections.Generic.HashSet[string]'
                foreach ($it in $kept) { [void]$keptIds.Add("$($it.Id)") }
                foreach ($it in $toDo) { if (-not $keptIds.Contains("$($it.Id)")) { [void]$capCutIds.Add("$($it.Id)") } }
                $toDo = $kept
            }
            $script:TrialFilesRemaining -= $toDo.Count
        }
        $skipped = $items.Count - $toDo.Count - $capCutIds.Count
        $script:TrialNotAttempted = ([int]$script:TrialNotAttempted) + $capCutIds.Count
        $fTotal = $toDo.Count; $fIdx = 0
        $spaceBytesTotal = Get-SafeSum -Items $toDo -Property Size
        $expectedTotal += $fTotal
        if ($willWrite) { Lz8d39824bd6 -Done 0 -Total $fTotal -BytesDone 0 -BytesTotal $spaceBytesTotal -Space $row.Space }
        if ($script:GuiMode) { Write-Host "##SCOPE##|$fTotal|$($items.Count)|$skipped" }
        if ($willWrite -and $Mode -ne 'FirstPass') {
            foreach ($sk in @($items | Where-Object { -not $toDoPreCapIds.Contains("$($_.Id)") })) {
                Write-AuditRecord -Space $row.Space -Item $sk -Status 'Skipped' -Reason 'already at the destination, intact and not older than the source'
            }
        }
        if ($willWrite -and $capCutIds.Count -gt 0) {
            foreach ($sk in @($items | Where-Object { $capCutIds.Contains("$($_.Id)") })) {
                Write-AuditRecord -Space $row.Space -Item $sk -Status 'NotAttempted' -Reason 'evaluation limit reached before this file could be attempted: never checked or copied. A licence is required to migrate it.'
            }
        }
        if (-not $willWrite) {
            $copied = $fTotal; $bytes = $spaceBytesTotal
            $pvRenamed = 0
            foreach ($it in $toDo) {
                $pd = Get-PlannedDestPath -Config $Config -EffSub $effSub -Item $it
                if ($pd.Renamed) { $pvRenamed++; $it | Add-Member -NotePropertyName Renamed -NotePropertyValue $true -Force; $it | Add-Member -NotePropertyName RenamedFrom -NotePropertyValue $pd.From -Force }
                Write-AuditRecord -Space $row.Space -Item $it -Status 'WouldCopy' -Reason 'dry-run' -DestPath $pd.Path
            }
            Write-MigrationLog INFO "  $($row.Space): every file's destination is in the audit CSV (SourcePath -> DestPath, $fTotal row(s)$(if ($pvRenamed) { ", $pvRenamed renamed on the way" })): $(Get-DestinationLabel -Row $row)$(if ($effSub) { " > /$($effSub.Trim('/'))" })"
        }
        elseif ($UploadWorkers -gt 1) {
            $sanitise = (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames)
            foreach ($it in $toDo) {
                $rp = if ($effSub) { ($effSub.Trim('/') + '/' + $it.RelativePath) } else { $it.RelativePath }
                $rp = $rp -replace '\\','/'
                if ($sanitise) { $rp = Resolve-SafeRelPathTracked -Space $row.Space -Rp ("$($it.RelativePath)" -replace '\\','/') -Item $it -DestId (Get-RowDestId $row) -Prefix $effSub }
                $rp = Remove-PathTraversal $rp
                $it | Add-Member -NotePropertyName RelPath -NotePropertyValue $rp -Force
            }
            $downloadThreads = 4
            if ("$($Config.source.provider)" -eq 'LocalFs') { $downloadThreads = 8 }
            if (((Test-ConfigProp $Config.run 'download')) -and ((Test-ConfigProp $Config.run.download 'threads')) -and $Config.run.download.threads) { $downloadThreads = [int]$Config.run.download.threads }
            $simDestBase = ''
            if ($Config.destination.provider -eq 'LocalSim') { $simDestBase = Join-Path $Config.destination.sim.rootPath (ConvertTo-Slug ($driveId -replace '^sim:','')) }
            $tokenHolder = [hashtable]::Synchronized(@{ Token = $null; Exp = [DateTimeOffset]::MinValue; ForceRefresh = $false; Fails = 0; NextTry = [DateTimeOffset]::MinValue })
            if ($Config.destination.provider -ne 'LocalSim') { $tk = Get-GraphAppToken -Config $Config; $tokenHolder.Token = $tk.Token; $tokenHolder.Exp = $tk.Exp }
            $ensured = [hashtable]::Synchronized(@{})
            Write-MigrationLog INFO "  copying up to $downloadThreads file(s) at a time from $($script:SrcNoun), and up to $UploadWorkers at a time into Microsoft 365."
            $adaptOn = $true; $minWorkers = 1; $growAfter = 30
            if ((Test-ConfigProp $Config.run.throttle 'adaptive')) {
                $ad = $Config.run.throttle.adaptive
                if ((Test-ConfigProp $ad 'enabled')) { $adaptOn = [bool]$ad.enabled }
                if ((Test-ConfigProp $ad 'minWorkers') -and [int]$ad.minWorkers -ge 1) { $minWorkers = [int]$ad.minWorkers }
                if ((Test-ConfigProp $ad 'growAfterSeconds') -and [int]$ad.growAfterSeconds -ge 1) { $growAfter = [int]$ad.growAfterSeconds }
            }
            if ($minWorkers -gt $UploadWorkers) { $minWorkers = $UploadWorkers }
            $startMax = $UploadWorkers; $effMin = if ($adaptOn) { $minWorkers } else { $UploadWorkers }
            $thr = [hashtable]::Synchronized(@{ Max = $startMax; Active = 0; HardMax = $UploadWorkers; Events = 0; LastCode = 0; PauseUntilTicks = [int64]0; LastThrottleTicks = [int64]0; LastGrowTicks = [DateTime]::UtcNow.Ticks; OmitFsi = [bool]$script:OmitFsi })
            $script:LastThrMax = -1; $script:LastThrPaused = $false
            $maxUpMbps = 0.0; $maxDownMbps = 0.0; $burstSec = 1.0
            if ((Test-ConfigProp $Config.run 'bandwidth')) {
                $bwc = $Config.run.bandwidth
                if ((Test-ConfigProp $bwc 'maxUploadMbps'))   { $maxUpMbps   = [double]$bwc.maxUploadMbps }
                if ((Test-ConfigProp $bwc 'maxDownloadMbps')) { $maxDownMbps = [double]$bwc.maxDownloadMbps }
                if (((Test-ConfigProp $bwc 'burstSeconds')) -and ([double]$bwc.burstSeconds -gt 0)) { $burstSec = [double]$bwc.burstSeconds }
            }
            $upBps   = if ($maxUpMbps   -gt 0) { $maxUpMbps   * 125000.0 } else { 0.0 }
            $downBps = if ($maxDownMbps -gt 0) { $maxDownMbps * 125000.0 } else { 0.0 }
            $bwUp   = [hashtable]::Synchronized(@{ CapBps = $upBps;   Tokens = ($upBps   * $burstSec); LastTicks = [DateTime]::UtcNow.Ticks; BucketMax = ($upBps   * $burstSec) })
            $bwDown = [hashtable]::Synchronized(@{ CapBps = $downBps; Tokens = ($downBps * $burstSec); LastTicks = [DateTime]::UtcNow.Ticks; BucketMax = ($downBps * $burstSec) })
            if ($maxUpMbps -gt 0 -or $maxDownMbps -gt 0) {
                $upTxt = if ($maxUpMbps -gt 0) { "upload capped at $maxUpMbps Mb/s" } else { "upload unlimited" }
                $dnTxt = if ($maxDownMbps -gt 0) { "download capped at $maxDownMbps Mb/s" } else { "download unlimited" }
                Write-MigrationLog INFO "  bandwidth: $upTxt, $dnTxt (so the client's line is not saturated)."
            }
            $bwControlPath = Join-Path $Config.run.stateRoot 'bandwidth.control.json'
            try { if (-not (Test-Path $Config.run.stateRoot)) { New-Item -ItemType Directory -Path $Config.run.stateRoot -Force | Out-Null } } catch {}
            try { @{ maxUploadMbps = $maxUpMbps; maxDownloadMbps = $maxDownMbps } | ConvertTo-Json | Set-Content -Path $bwControlPath -Encoding UTF8 } catch {}
            $bwCtrlStamp = $null; try { $bwCtrlStamp = (Get-Item $bwControlPath).LastWriteTimeUtc } catch {}
            $bwLastUp = $maxUpMbps; $bwLastDown = $maxDownMbps
            $spoolCap = [int][math]::Max($SpoolAhead, $UploadWorkers * 2)
            if ("$($Config.source.provider)" -eq 'LocalFs') { $spoolCap = [int][math]::Max(20, $spoolCap) }
            $spool = [System.Collections.Concurrent.BlockingCollection[hashtable]]::new($spoolCap)
            $delQ  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
            $resQ  = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
            $inQ   = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
            foreach ($it in $toDo) { $inQ.Enqueue($it) }
            $script:VitalsPipe = @{ Spool = $spool; InQ = $inQ }
            Lz883d31a1c9 -Phase 'Transfer' -Space "$($row.Space)"
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
                . ([scriptblock]::Create($spoolHelpers))
                $xferTo = 3600; try { if ($cfg.run.throttle.transferTimeoutSec) { $xferTo = [int]$cfg.run.throttle.transferTimeoutSec } } catch {}
                $idleSec = 120; $idleMax = 3; try { if ($null -ne $cfg.run.throttle.sourceIdleTimeoutSec) { $idleSec = [int]$cfg.run.throttle.sourceIdleTimeoutSec } } catch {}; try { if ($cfg.run.throttle.sourceReadAttempts) { $idleMax = [int]$cfg.run.throttle.sourceReadAttempts } } catch {}
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
                $PaceEase = { param($p) if ($p.GapMs -gt 0) { [System.Threading.Monitor]::Enter($p.SyncRoot); try { $fl = 0; try { $fl = [int]$p.FloorMs } catch {}; $p.GapMs = [int][math]::Max($fl, [math]::Min($p.GapMs - 25, [math]::Floor($p.GapMs * 0.9))) } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) } } }
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
                    $hardTry=0; $throttleTry=0; $idleTry=0
                    while ($true) { try {
                        if ($cfg.datto.provider -eq 'LocalSim') { $lh = Save-LocalSourceFile -InFile $it.Id -OutFile $tf -Key $spoolKey -IdleSec $idleSec; if ($lh) { $it.Hash = $lh } }
                        else {
                            & $DoPace $pace
                            $uri=($cfg.datto.endpointUrl.TrimEnd('/'))+($cfg.datto.apiPaths.downloadFile -replace '\{fileID\}',[uri]::EscapeDataString("$($it.Id)"))
                            if ($spoolKey) { Invoke-SpoolDownload -Uri $uri -Headers $authHeader -OutFile $tf -Key $spoolKey -TimeoutSec $xferTo -IdleSec $idleSec | Out-Null }
                            else { Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -Headers $authHeader -OutFile $tf -TimeoutSec $xferTo | Out-Null }
                            & $PaceEase $pace
                        }
                        $ok=$true; break } catch {
                            $st=$null; try { $st=$_.Exception.Response.StatusCode.value__ } catch {}
                            if (@(429,503) -contains $st) {
                                & $PaceBump $pace
                                $throttleTry++
                                $ra=0; $rh=$null; try { $rh=$_.Exception.Response.Headers } catch {}; if ($rh) { foreach ($rn in 'X-Rate-Limit-Retry-After-Seconds','Retry-After') { if (-not $ra) { try { $ra=[int](@($rh.GetValues($rn))[0]) } catch { try { $rv=$rh[$rn]; if ($rv) { $ra=[int]$rv } } catch {} } } } }
                                if ($ra -le 0) { $ra=[int][math]::Min([math]::Pow(2,[math]::Min($throttleTry,5)),30) }
                                if ($throttleTry -ge 40) { $ok=$false; $err="still rate-limited by Datto (HTTP $st) after $throttleTry waits: $($_.Exception.Message)"; break }
                                Start-Sleep -Seconds $ra
                            } else {
                                $hardTry++; if ($_.Exception.Message -match 'no data received for') { $idleTry++; if ($idleTry -ge $idleMax) { $hardTry = 99 } }
                                if ($hardTry -ge 5) { $ok=$false; $err=$_.Exception.Message; if ($err -match '(?i)enough space|disk( is)? full|not enough space') { $err = "the temp drive filled up while staging this file - free space or point run.tempWorkingFolder at a bigger drive. ($err)" }; break }
                                Start-Sleep -Seconds ([int][math]::Min([math]::Pow(2,$hardTry),30))
                            } } }
                    $dlSw.Stop()
                    $spool.Add(@{ Item=$it; TempFile=$tf; Ok=$ok; Error=$err; DlMs=$dlSw.Elapsed.TotalMilliseconds })
                }
            }
            $downloaders=@()
            for ($d=0; $d -lt $downloadThreads; $d++) {
                $dp=[powershell]::Create(); $null=$dp.AddScript($dlScript).AddArgument($inQ).AddArgument($spool).AddArgument((Get-RunspaceConfig -Config $Config)).AddArgument($spaceTemp).AddArgument($bwDown).AddArgument($enumFlag).AddArgument($script:DattoPace).AddArgument([int64]$script:LargeFileBytes).AddArgument($script:SpoolKey).AddArgument($script:SpoolHelperSource)
                $downloaders += @{ PS=$dp; Handle=$dp.BeginInvoke() }
            }
            $del = [powershell]::Create()
            $null = $del.AddScript({ param($delQ,$flags) while (-not $flags.Done -or $delQ.Count -gt 0){ $p=$null; if($delQ.TryDequeue([ref]$p)){try{[IO.File]::Delete($p)}catch{}}else{Start-Sleep -Milliseconds 50} } }).AddArgument($delQ).AddArgument($flags)
            $delH = $del.BeginInvoke()
            $workerScript = {
                param($spool,$resQ,$delQ,$tokenHolder,$driveId,$provider,$simDestBase,$threshold,$officeTypes,$maxRetries,$baseDelay,$graphBase,$ensured,$chunkBytes,$honorRetryAfter,$thr,$minWorkers,$bwUp,$apiTo,$xferTo,$spoolKey,$spoolHelpers,$preserveDates)
                if ($spoolKey) { . ([scriptblock]::Create($spoolHelpers)) }
                $wsApi  = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
                $wsXfer = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
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
                    if ($st -eq 401) { $tokenHolder.ForceRefresh = $true }
                    $ra = & $GetRA $errRec
                    if (@(429,503) -contains $st) { & $Throttled $ra $st }
                    return (& $GetWait $errRec $attempt $baseDelay $honorRetryAfter)
                }
                $maxThrottle = [math]::Max([int]$maxRetries, 40)
                $CapFor = {
                    param($st)
                    if (@(429,503) -contains $st) { return $maxThrottle }
                    if (@(400,409) -contains $st) { return [math]::Min([int]$maxRetries, 3) }
                    return $maxRetries
                }
                $StormStatus = { param($st) return ((@(400,409) -contains $st) -and ([int64]$thr.LastThrottleTicks -gt 0) -and (([DateTime]::UtcNow.Ticks - [int64]$thr.LastThrottleTicks) -lt [TimeSpan]::FromSeconds(180).Ticks)) }
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
                $dq = @{ Items = [System.Collections.Generic.List[object]]::new(); First = [DateTime]::UtcNow }
                $FlushDates = {
                    if ($dq.Items.Count -eq 0) { return }
                    $its = @($dq.Items); $dq.Items.Clear()
                    if ($thr.OmitFsi) { return }
                    $breq = [System.Collections.Generic.List[object]]::new()
                    for ($bk = 0; $bk -lt $its.Count; $bk++) { $breq.Add(@{ id = "$bk"; method = 'PATCH'; url = "/drives/$driveId/root:/$($its[$bk].Enc):"; headers = @{ 'Content-Type' = 'application/json' }; body = @{ fileSystemInfo = @{ createdDateTime = $its[$bk].C; lastModifiedDateTime = $its[$bk].M } } }) }
                    $bres = $null
                    for ($ba=1;$ba -le $maxThrottle;$ba++){ try { $bres = Invoke-RestMethod -Method Post -Uri "$graphBase/`$batch" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -Body (@{ requests = $breq.ToArray() }|ConvertTo-Json -Depth 8) -ContentType 'application/json' -WebSession $wsApi -TimeoutSec $apiTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,408,429,500,502,503,504)-contains $st) -or (& $StormStatus $st) -or (& $IsTransient $_))-and $ba -lt (& $CapFor $st)){Start-Sleep -Seconds (& $HandleRetry $_ $ba);continue}; return } }
                    if (-not $bres) { return }
                    $again = [System.Collections.Generic.List[object]]::new()
                    foreach ($br in @($bres.responses)) { $bsc = 0; try { $bsc = [int]$br.status } catch {}; if ($bsc -eq 400) { $thr.OmitFsi = $true } elseif ($bsc -lt 200 -or $bsc -ge 300) { try { $again.Add($its[[int]$br.id]) } catch {} } }
                    foreach ($x in $again) {
                        if ($thr.OmitFsi) { break }
                        try { Invoke-WebRequest -UseBasicParsing -Method Patch -Uri "$graphBase/drives/$driveId/root:/$($x.Enc):" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -Body (@{fileSystemInfo=@{createdDateTime=$x.C;lastModifiedDateTime=$x.M}}|ConvertTo-Json -Depth 4) -ContentType 'application/json' -WebSession $wsApi -TimeoutSec $apiTo | Out-Null }
                        catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if ($st -eq 400) { $thr.OmitFsi=$true } }
                    }
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
                        $fsiIso=$null
                        $fsiCreated=$null
                        if ($preserveDates) {
                            try { $fsiIso=([datetimeoffset]::Parse("$($it.ModifiedUtc)",[System.Globalization.CultureInfo]::InvariantCulture)).UtcDateTime.ToString('o') } catch {}
                            $fsiCreated=$fsiIso
                            try { if (((Test-ConfigProp $it 'CreatedUtc')) -and $it.CreatedUtc) { $fsiCreated=([datetimeoffset]::Parse("$($it.CreatedUtc)",[System.Globalization.CultureInfo]::InvariantCulture)).UtcDateTime.ToString('o') } } catch {}
                        }
                        if ($provider -eq 'LocalSim') {
                            $dest=Join-Path $simDestBase $rp; New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null; if ($spoolKey) { Copy-SpoolToFile -File $tf -OutFile $dest -Key $spoolKey } else { Copy-Item -LiteralPath $tf -Destination $dest -Force }; if ($fsiIso) { try { (Get-Item -LiteralPath $dest -Force).LastWriteTimeUtc = ([datetimeoffset]::Parse($fsiIso)).UtcDateTime } catch {} }; $destSize=(Get-Item -LiteralPath $dest -Force).Length; $method='LocalSim'
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
                        for ($fa=1;$fa -le $maxThrottle;$fa++){
                            try { Invoke-RestMethod -Method Post -Uri $purl -Headers @{Authorization='Bearer '+$tokenHolder.Token} -Body (@{name=$segs[$i];folder=@{};'@microsoft.graph.conflictBehavior'='fail'}|ConvertTo-Json) -ContentType 'application/json' -WebSession $wsApi -TimeoutSec $apiTo | Out-Null; break }
                            catch {
                                $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}
                                if ($st -eq 409) { break }
                                if(((@(401,404,408,429,500,502,503,504)-contains $st) -or (& $StormStatus $st) -or (& $IsTransient $_)) -and $fa -lt (& $CapFor $st)){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $fa);continue}
                                throw
                            }
                        }
                                        $ensured[$cur]=$true
                                    }
                                }
                            }
                            if ($localSize -eq 0) {
                                for ($a=1;$a -le $maxThrottle;$a++){ try { $resp=Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$graphBase/drives/$driveId/root:/${enc}:/content" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -Body ([byte[]]::new(0)) -ContentType 'application/octet-stream' -WebSession $wsApi -TimeoutSec $apiTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,404,408,429,500,502,503,504)-contains $st) -or (& $StormStatus $st) -or (& $IsTransient $_))-and $a -lt (& $CapFor $st)){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $a);continue}; throw } }
                                $method='Empty'
                            }
                            elseif ($localSize -le $threshold) {
                                for ($a=1;$a -le $maxThrottle;$a++){ try {
                                    if ($spoolKey) {
                                        $spx = Open-SpoolRead -File $tf -Key $spoolKey
                                        try { $resp = Send-SpoolHttp -Uri "$graphBase/drives/$driveId/root:/${enc}:/content" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -BodyStream $spx.Stream -ContentLength $localSize -TimeoutSec $xferTo }
                                        finally { $spx.Stream.Dispose() }
                                    } else { $resp=Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$graphBase/drives/$driveId/root:/${enc}:/content" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -InFile $tf -ContentType 'application/octet-stream' -WebSession $wsXfer -TimeoutSec $xferTo }
                                    break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,404,408,429,500,502,503,504)-contains $st) -or (& $StormStatus $st) -or (& $IsTransient $_))-and $a -lt (& $CapFor $st)){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $a);continue}; throw } }
                                $method='DirectPut'
                            } else {
                                for ($sx=1;$sx -le 3;$sx++) { $sess=$null; try {
                                $sessItem=@{'@microsoft.graph.conflictBehavior'='replace'}
                                if ($fsiIso -and -not $thr.OmitFsi) { $sessItem['fileSystemInfo']=@{ createdDateTime=$fsiCreated; lastModifiedDateTime=$fsiIso } }
                                for ($a=1;$a -le $maxThrottle;$a++){ try { $sess=Invoke-RestMethod -Method Post -Uri "$graphBase/drives/$driveId/root:/${enc}:/createUploadSession" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -Body (@{item=$sessItem}|ConvertTo-Json -Depth 5) -ContentType 'application/json' -WebSession $wsApi -TimeoutSec $apiTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if ($st -eq 400 -and $sessItem.ContainsKey('fileSystemInfo')) { $thr.OmitFsi=$true; $sessItem.Remove('fileSystemInfo'); continue }; if(((@(401,404,408,429,500,502,503,504)-contains $st) -or (& $StormStatus $st) -or (& $IsTransient $_))-and $a -lt (& $CapFor $st)){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $a);continue}; throw } }
                                $uu=$sess.uploadUrl; $chunk=$chunkBytes
                                if ($spoolKey) {
                                    $fsr=(Open-SpoolRead -File $tf -Key $spoolKey).Stream
                                    try { $pos=[int64]0
                                        while ($true) {
                                            $sl = Read-SpoolChunk -Stream $fsr -Count ([int]$chunk)
                                            $read = $sl.Length; if ($read -le 0) { break }
                                            for ($ca=1;$ca -le $maxThrottle;$ca++){ try { $resp=Send-SpoolHttp -Uri $uu -BodyBytes $sl -ContentRange "bytes $pos-$($pos+$read-1)/$localSize" -TimeoutSec $xferTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,408,429,500,502,503,504)-contains $st) -or (& $StormStatus $st) -or (& $IsTransient $_))-and $ca -lt (& $CapFor $st)){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $ca);continue}; throw } }
                                            $pos+=$read
                                            if ($read -lt $chunk) { break }
                                        }
                                    } finally { $fsr.Dispose() }
                                } else {
                                $fsr=[System.IO.File]::OpenRead($tf); $ctmp="$tf.chunk"
                                try { $buf=[byte[]]::new($chunk); $pos=0
                                    while(($read=$fsr.Read($buf,0,$buf.Length))-gt 0){ if($read -eq $buf.Length){[System.IO.File]::WriteAllBytes($ctmp,$buf)}else{$sl=[byte[]]::new($read);[Array]::Copy($buf,0,$sl,0,$read);[System.IO.File]::WriteAllBytes($ctmp,$sl)}
                                        for ($ca=1;$ca -le $maxThrottle;$ca++){ try { $resp=Invoke-WebRequest -UseBasicParsing -Method Put -Uri $uu -Headers @{'Content-Range'="bytes $pos-$($pos+$read-1)/$localSize"} -InFile $ctmp -ContentType 'application/octet-stream' -WebSession $wsXfer -TimeoutSec $xferTo; break } catch { $st=$null;try{$st=$_.Exception.Response.StatusCode.value__}catch{}; if(((@(401,408,429,500,502,503,504)-contains $st) -or (& $StormStatus $st) -or (& $IsTransient $_))-and $ca -lt (& $CapFor $st)){$r++;Start-Sleep -Seconds (& $HandleRetry $_ $ca);continue}; throw } }
                                        $pos+=$read }
                                } finally { $fsr.Dispose(); if(Test-Path $ctmp){Remove-Item $ctmp -Force -ErrorAction SilentlyContinue} }
                                }
                                break } catch { $stx=$null; try{$stx=$_.Exception.Response.StatusCode.value__}catch{}
                                  if ($stx -eq 404 -and $sess -and $sx -lt 3) { $r++; Start-Sleep -Seconds 2; continue }; throw } }
                                $method='UploadSession'
                            }
                            try { $j=$resp.Content|ConvertFrom-Json; $destSize=[int64]$j.size; try { $destHash=[string]$j.file.hashes.quickXorHash } catch {} } catch {}
                            if ($localSize -gt 0 -and $destSize -le 0) { try { $meta=Invoke-RestMethod -Method Get -Uri "$graphBase/drives/$driveId/root:/${enc}?`$select=size,file" -Headers @{Authorization='Bearer '+$tokenHolder.Token} -WebSession $wsApi -TimeoutSec $apiTo; if ($meta.size) { $destSize=[int64]$meta.size; try { if (-not $destHash) { $destHash=[string]$meta.file.hashes.quickXorHash } } catch {} } } catch {} }
                            if ($fsiIso -and -not $thr.OmitFsi -and ($method -eq 'DirectPut' -or $method -eq 'Empty')) {
                                if ($dq.Items.Count -eq 0) { $dq.First = [DateTime]::UtcNow }
                                $dq.Items.Add(@{ Enc = $enc; C = $fsiCreated; M = $fsiIso })
                                if ($dq.Items.Count -ge 20) { & $FlushDates }
                            }
                        }
                        if ($localSize -eq 0) { $status='ZeroByte'; $reason='zero-byte (accepted, flagged)' }
                        elseif ($officeTypes -contains $ext) { if ($destSize -gt 0){$status='Copied';$reason='Office file accepted (M365 rewrites metadata)'}else{$status='VerifyFail';$reason='Office file not stored (size 0 at destination)'} }
                        elseif ($destSize -eq $localSize) { $status='Copied';$reason='verified (size match)' }
                        elseif ($destSize -gt 0 -and [math]::Abs($destSize-$localSize) -le [math]::Max(65536,[int64]($localSize*0.01))) { $status='Copied';$reason="accepted (stored $destSize vs source $localSize, diff $($destSize-$localSize) bytes; likely M365 rewrite)" }
                        else { $status='VerifyFail';$reason="size mismatch (dest $destSize vs $localSize)" }
                    } catch { $status='Error'; $err=$_.Exception.Message }
                    finally { & $Release }
                    $sw.Stop()
                    $resQ.Enqueue(@{Item=$it;Status=$status;Error=$err;Reason=$reason;DestSize=$destSize;DestHash=$destHash;DestPath=$rp;Method=$method;Retries=$r;Ms=$sw.Elapsed.TotalMilliseconds;DlMs=$dlMs})
                    if($tf){$delQ.Enqueue($tf)}
                    if ($dq.Items.Count -and ([DateTime]::UtcNow - $dq.First).TotalSeconds -ge 5) { & $FlushDates }
                }
                & $FlushDates
            }
            $graphBase='https://graph.microsoft.com/v1.0'
            $workers=@()
            for ($w=0; $w -lt $UploadWorkers; $w++) {
                $ps=[powershell]::Create()
                $null=$ps.AddScript($workerScript).AddArgument($spool).AddArgument($resQ).AddArgument($delQ).AddArgument($tokenHolder).AddArgument($driveId).AddArgument($Config.destination.provider).AddArgument($simDestBase).AddArgument([int64]$script:SmallFilePutThreshold).AddArgument($script:OfficeTypes).AddArgument([int]$Config.run.throttle.maxRetries).AddArgument([int]$Config.run.throttle.baseDelaySeconds).AddArgument($graphBase).AddArgument($ensured).AddArgument([int64]$script:ChunkSize).AddArgument([bool]$Config.run.throttle.honorRetryAfter).AddArgument($thr).AddArgument([int]$effMin).AddArgument($bwUp).AddArgument([int]$script:HttpTimeoutSec).AddArgument([int]$script:TransferTimeoutSec).AddArgument($script:SpoolKey).AddArgument($script:SpoolHelperSource).AddArgument([bool]$script:PreserveDates)
                $workers += @{ PS=$ps; Handle=$ps.BeginInvoke() }
            }
            $process = {
                param($res)
                $script:fIdxRef.Value++
                $it=$res.Item
                if ([int64]$it.Size -ge $script:LargeFileBytes) { $script:EtaLargeBytesDone += [int64]$it.Size } else { $script:EtaSmallDone++ }
                switch ($res.Status) {
                    'Copied'   { $script:copiedRef.Value++; $script:bytesRef.Value+=$it.Size; if($script:VerboseFiles){Write-MigrationLog INFO "  + [$($it.RelativePath)] $($res.Reason)"} }
                    'ZeroByte' { $script:copiedRef.Value++; $script:zeroRef.Value++; $script:bytesRef.Value+=$it.Size; Write-MigrationLog WARN "  empty file (0 bytes), uploaded as-is: $($it.RelativePath)" }
                    'VerifyFail'{ $script:verifyFailRef.Value++; Write-MigrationLog ERROR "  VERIFY FAILED $($it.RelativePath): $($res.Reason). In plain terms: the uploaded copy did not match the original, so it was not marked done. It will be retried on the next Sync." }
                    'DownloadError'{ $script:failedRef.Value++; Write-MigrationLog ERROR "  DOWNLOAD FAILED $($it.RelativePath): $($res.Error). In plain terms: the file could not be downloaded from $($script:SrcNoun). It will be retried on the next Sync." }
                    'SkippedTooLarge'{ $script:failedRef.Value++; Write-MigrationLog ERROR "  NOT COPIED (too large for the temp drive) $($it.RelativePath): $($res.Error). In plain terms: this one file will not fit in the temp drive's free space, so it has NOT been copied. It counts as a failure until it is. Free up space (or point the temp folder at a bigger drive) and Sync to pick it up." }
                    default    { $script:failedRef.Value++; Write-MigrationLog ERROR "  UPLOAD FAILED $($it.RelativePath): $($res.Error). In plain terms: the file could not be uploaded to Microsoft 365. It will be retried on the next Sync." }
                }
                if ($script:PreserveDates -and $null -ne $script:SweepList -and $Config.destination.provider -ne 'LocalSim' -and
                    (@('Copied','ZeroByte') -contains $res.Status) -and "$($it.ModifiedUtc)" -and
                    ($script:OfficeTypes -contains ([System.IO.Path]::GetExtension($it.RelativePath)).ToLower())) {
                    $swCt = ''; try { if (((Test-ConfigProp $it 'CreatedUtc')) -and $it.CreatedUtc) { $swCt = "$($it.CreatedUtc)" } } catch {}
                    $script:SweepList.Add(@{ Drive = $driveId; Enc = (([uri]::EscapeDataString($res.DestPath) -replace '%2F','/')); Rel = $res.DestPath; Mtime = "$($it.ModifiedUtc)"; Ctime = $swCt })
                }
                $rDl = 0.0; try { $rDl = [double]$res.DlMs } catch {}
                $rsn = Lzd93f9ea715 -Repair $repair -Item $it -Status $res.Status -Reason $res.Reason
                Write-AuditRecord -Space $row.Space -Item $it -Status $res.Status -Reason $rsn -DestSize $res.DestSize -DestPath $res.DestPath -DestHash $res.DestHash -Method $res.Method -Retries $res.Retries -DurationMs $res.Ms -DownloadMs $rDl -ErrorMsg $res.Error
                Lz8d39824bd6 -Done $script:fIdxRef.Value -Total $fTotal -BytesDone $script:bytesRef.Value -BytesTotal $spaceBytesTotal -Space $row.Space `
                    -SmallDone $script:EtaSmallDone -SmallTotal $script:EtaSmallTotal -LargeBytesDone $script:EtaLargeBytesDone -LargeBytesTotal $script:EtaLargeBytesTotal -Final ([int][bool]$enumFlag.Done)
            }
            $script:fIdxRef=[ref]$fIdx; $script:copiedRef=[ref]$copied; $script:bytesRef=[ref]$bytes; $script:zeroRef=[ref]$zero; $script:verifyFailRef=[ref]$verifyFail; $script:failedRef=[ref]$failed
            if ($streamFP) {
                $script:streamCountRef=[ref]0; $script:streamBytesRef=[ref]([int64]0)
                $streamEnumFailed = $false; $streamEnumErr = ''
                try {
                Get-DattoItems -Config $Config -Space $space -OnItem {
                    param($it)
                    if ($Config.destination.provider -ne 'LocalSim') { Update-WorkerToken -Holder $tokenHolder -Config $Config }
                    $rp = if ($effSub) { ($effSub.Trim('/') + '/' + $it.RelativePath) } else { $it.RelativePath }
                    $rp = $rp -replace '\\','/'
                    if ($sanitise) { $rp = Resolve-SafeRelPathTracked -Space $row.Space -Rp ("$($it.RelativePath)" -replace '\\','/') -Item $it -DestId (Get-RowDestId $row) -Prefix $effSub }
                    $rp = Remove-PathTraversal $rp
                    $it | Add-Member -NotePropertyName RelPath -NotePropertyValue $rp -Force
                    $inQ.Enqueue($it)
                    $script:streamCountRef.Value++
                    $script:streamBytesRef.Value += [int64]$it.Size
                    if ([int64]$it.Size -ge $script:LargeFileBytes) { $script:EtaLargeBytesTotal += [int64]$it.Size } else { $script:EtaSmallTotal++ }
                } | Out-Null
                } catch {
                    $streamEnumFailed = $true; $streamEnumErr = $_.Exception.Message
                }
                $enumFlag.Done = $true
                $fTotal = [int]$script:streamCountRef.Value
                $spaceBytesTotal = [int64]$script:streamBytesRef.Value
                $expectedTotal += $fTotal
                $script:ListedTotal += $fTotal
                if ($streamEnumFailed) {
                    Write-MigrationLog ERROR "  could not read files for '$($row.Space)': $streamEnumErr. In plain terms: the source may be empty, moved, or unreachable. $fTotal file(s) already queued will still upload; nothing further will be read for this project."
                    if ($script:GuiMode) { Write-Host "##STATUS##|Could not read [$($row.Space)] from $($script:SrcNoun): $streamEnumErr" }
                } else {
                    Write-MigrationLog INFO "  listing finished: $fTotal file(s), $([math]::Round($spaceBytesTotal/1MB,1)) MB to move."
                    if ($script:GuiMode) { Write-Host "##STATUS##|File list complete: $fTotal file(s). Uploading now..." }
                }
            }
            $spoolClosed=$false
            while (@($workers | Where-Object { -not $_.Handle.IsCompleted }).Count -gt 0 -or $resQ.Count -gt 0) {
                Lz3c24fdf306
                $res=$null
                while ($resQ.TryDequeue([ref]$res)) { & $process $res; Lz3402e3c9c5 -Activity "Files: $($row.Space)" -Status $res.DestPath -Current $script:fIdxRef.Value -Total $fTotal -Id 2 | Out-Null }
                if (-not $spoolClosed -and (@($downloaders | Where-Object { -not $_.Handle.IsCompleted }).Count -eq 0)) { $spool.CompleteAdding(); $spoolClosed=$true }
                if ($Config.destination.provider -ne 'LocalSim') { Update-WorkerToken -Holder $tokenHolder -Config $Config }
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
                    Lzeb3c01b3fc -Max $curMax -HardMax $thr.HardMax -PausedSeconds $pausedSecs -Events $curEvents -Code $curCode
                    $codeTxt = if ($curCode) { " (HTTP ${curCode}: too many requests too fast)" } else { "" }
                    if (-not $isPaused -and $script:LastThrPaused -and $curMax -lt $thr.HardMax -and $curMax -eq $script:LastThrMax) {
                        Write-MigrationLog INFO "  Pause over: carrying on with $curMax of $($thr.HardMax) uploader(s). It returns to full speed after about $growAfter s with no further throttling."
                    } elseif ($curMax -lt $thr.HardMax -or $isPaused) {
                        $msg = if ($isPaused) { "Throttling${codeTxt}: Microsoft asked us to pause about $pausedSecs s. Easing off to $curMax of $($thr.HardMax) uploader(s)." } else { "Throttling${codeTxt}: easing off to $curMax of $($thr.HardMax) uploader(s) to stay within Microsoft 365 limits." }
                        Write-MigrationLog WARN "  $msg In plain terms: this is normal protection, the job keeps running and speeds back up on its own."
                    } elseif ($script:LastThrMax -ne -1) {
                        Write-MigrationLog OK "  Throttling cleared: back to full speed ($curMax of $($thr.HardMax) uploaders)."
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
                                Write-MigrationLog INFO "  bandwidth changed on the fly: upload $ut, download $dt. Applied immediately."
                            }
                        }
                    }
                } catch {}
                Start-Sleep -Milliseconds 100
            }
            if ($script:LastThrMax -ne -1 -and $script:LastThrMax -lt $thr.HardMax) { Lzeb3c01b3fc -Max $thr.HardMax -HardMax $thr.HardMax -PausedSeconds 0 -Events $thr.Events }
            if (-not $spoolClosed) { $spool.CompleteAdding() }
            $res=$null; while ($resQ.TryDequeue([ref]$res)) { & $process $res }
            $fIdx=$script:fIdxRef.Value; $copied=$script:copiedRef.Value; $bytes=$script:bytesRef.Value; $zero=$script:zeroRef.Value; $verifyFail=$script:verifyFailRef.Value; $failed=$script:failedRef.Value
            if ($thr.OmitFsi -and -not $script:OmitFsi) { $script:OmitFsi = $true }
            foreach ($wk in $workers) { try { $wk.PS.EndInvoke($wk.Handle) } catch {}; try { $wk.PS.Dispose() } catch {} }
            $flags.Done=$true
            foreach ($dp in $downloaders) { try { $dp.PS.EndInvoke($dp.Handle) } catch {}; try { $dp.PS.Dispose() } catch {} }
            try { $del.EndInvoke($delH) } catch {}; try { $del.Dispose() } catch {}
        }
        elseif ($SpoolAhead -le 1) {
            $etaSmallDone=0; $etaLargeDone=[int64]0; $etaSmallTotal=0; $etaLargeTotal=[int64]0
            foreach ($it in $toDo) { if ([int64]$it.Size -ge $script:LargeFileBytes) { $etaLargeTotal += [int64]$it.Size } else { $etaSmallTotal++ } }
            Lz883d31a1c9 -Phase 'Transfer' -Space "$($row.Space)"
            foreach ($it in $toDo) {
                $fIdx++
                if ([int64]$it.Size -ge $script:LargeFileBytes) { $etaLargeDone += [int64]$it.Size } else { $etaSmallDone++ }
                Lz3402e3c9c5 -Activity "Files: $($row.Space)" -Status $it.RelativePath -Current $fIdx -Total $fTotal -Id 2 | Out-Null
                $tempFile = Join-Path $spaceTemp ([guid]::NewGuid().ToString('N') + $(if ($script:SpoolKey) { '' } else { [System.IO.Path]::GetExtension($it.RelativePath) }))
                $dlSw = [System.Diagnostics.Stopwatch]::StartNew(); $upSw = [System.Diagnostics.Stopwatch]::new()
                try {
                    Lze8f6c57ef2 -Config $Config -Item $it -OutFile $tempFile | Out-Null
                    $dlSw.Stop(); $upSw.Start()
                    $destInfo = Send-FileToDestination -Config $Config -DriveId $driveId -TargetFolder $effSub -Item $it -LocalFile $tempFile -Space $row.Space
                    $v = Lz397101acd9 -Item $it -LocalFile $tempFile -DestInfo $destInfo
                    $upSw.Stop()
                    if ($v.Ok) {
                        if ($v.Zero) { Write-MigrationLog WARN "  empty file (0 bytes), uploaded as-is: $($it.RelativePath)"; $zero++ }
                        $copied++; $bytes += $it.Size
                        if ($script:VerboseFiles) { Write-MigrationLog INFO "  + [$($it.RelativePath)] $($v.Reason)" }
                        $stat = if($v.Zero){'ZeroByte'}else{'Copied'}
                        Write-AuditRecord -Space $row.Space -Item $it -Status $stat -Reason (Lzd93f9ea715 -Repair $repair -Item $it -Status $stat -Reason $v.Reason) -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $upSw.Elapsed.TotalMilliseconds -DownloadMs $dlSw.Elapsed.TotalMilliseconds
                    } else {
                        $verifyFail++; Write-MigrationLog ERROR "  VERIFY FAILED $($it.RelativePath): $($v.Reason). In plain terms: the uploaded copy did not match the original, so it was not marked done. It will be retried on the next Sync."
                        Write-AuditRecord -Space $row.Space -Item $it -Status 'VerifyFail' -Reason $v.Reason -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $upSw.Elapsed.TotalMilliseconds -DownloadMs $dlSw.Elapsed.TotalMilliseconds
                    }
                } catch { if ($dlSw.IsRunning){$dlSw.Stop()}; if($upSw.IsRunning){$upSw.Stop()}; $failed++; Write-MigrationLog ERROR "  FAILED $($it.RelativePath): $($_.Exception.Message). In plain terms: this file could not be copied. It will be retried on the next Sync."; Write-AuditRecord -Space $row.Space -Item $it -Status 'Error' -DurationMs $upSw.Elapsed.TotalMilliseconds -DownloadMs $dlSw.Elapsed.TotalMilliseconds -ErrorMsg $_.Exception.Message }
                finally { if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue } }
                Lz8d39824bd6 -Done $fIdx -Total $fTotal -BytesDone $bytes -BytesTotal $spaceBytesTotal -Space $row.Space -SmallDone $etaSmallDone -SmallTotal $etaSmallTotal -LargeBytesDone $etaLargeDone -LargeBytesTotal $etaLargeTotal -Final 1
            }
        }
        else {
            $spool = [System.Collections.Concurrent.BlockingCollection[hashtable]]::new([int]$SpoolAhead)
            $delQ  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
            $flags = [hashtable]::Synchronized(@{ Done = $false })
            $script:VitalsPipe = @{ Spool = $spool; InQ = $null }
            Lz883d31a1c9 -Phase 'Transfer' -Space "$($row.Space)"
            $etaSmallDone=0; $etaLargeDone=[int64]0; $etaSmallTotal=0; $etaLargeTotal=[int64]0
            foreach ($it in $toDo) { if ([int64]$it.Size -ge $script:LargeFileBytes) { $etaLargeTotal += [int64]$it.Size } else { $etaSmallTotal++ } }
            $prod = [powershell]::Create()
            $null = $prod.AddScript({
                param($spool, $toDo, $cfg, $temp, $spoolKey, $spoolHelpers, $pace)
                . ([scriptblock]::Create($spoolHelpers))
                $capBps = 0.0; try { if ($cfg.run.bandwidth.maxDownloadMbps) { $capBps = [double]$cfg.run.bandwidth.maxDownloadMbps * 125000.0 } } catch {}
                $bwStart = [DateTime]::UtcNow; $bwBytes = [double]0
                $paceSlot = {
                    param($p)
                    if (-not $p -or $p.GapMs -le 0) { return }
                    $sleepMs = 0
                    [System.Threading.Monitor]::Enter($p.SyncRoot)
                    try {
                        $now = [DateTime]::UtcNow.Ticks; $slot = [math]::Max($now, $p.NextTicks)
                        $sleepMs = [int](($slot - $now) / [TimeSpan]::TicksPerMillisecond)
                        $p.NextTicks = $slot + ($p.GapMs * [TimeSpan]::TicksPerMillisecond)
                    } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) }
                    if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
                }
                $paceEase = { param($p) if ($p -and $p.GapMs -gt 0) { [System.Threading.Monitor]::Enter($p.SyncRoot); try { $fl = 0; try { $fl = [int]$p.FloorMs } catch {}; $p.GapMs = [int][math]::Max($fl, [math]::Min($p.GapMs - 25, [math]::Floor($p.GapMs * 0.9))) } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) } } }
                $paceBump = { param($p) if ($p) { [System.Threading.Monitor]::Enter($p.SyncRoot); try { $p.GapMs = [math]::Min($p.MaxMs, $p.GapMs + 300) } finally { [System.Threading.Monitor]::Exit($p.SyncRoot) } } }
                $xferTo = 3600; try { if ($cfg.run.throttle.transferTimeoutSec) { $xferTo = [int]$cfg.run.throttle.transferTimeoutSec } } catch {}
                $idleSec = 120; $idleMax = 3; try { if ($null -ne $cfg.run.throttle.sourceIdleTimeoutSec) { $idleSec = [int]$cfg.run.throttle.sourceIdleTimeoutSec } } catch {}; try { if ($cfg.run.throttle.sourceReadAttempts) { $idleMax = [int]$cfg.run.throttle.sourceReadAttempts } } catch {}
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
                        $hardTry = 0; $throttleTry = 0; $idleTry = 0
                        while ($true) {
                            try {
                                if ($cfg.datto.provider -eq 'LocalSim') { $lh = Save-LocalSourceFile -InFile $it.Id -OutFile $tf -Key $spoolKey -IdleSec $idleSec; if ($lh) { $it.Hash = $lh } }
                                else {
                                    & $paceSlot $pace
                                    $uri = ($cfg.datto.endpointUrl.TrimEnd('/')) + ($cfg.datto.apiPaths.downloadFile -replace '\{fileID\}', [uri]::EscapeDataString("$($it.Id)"))
                                    if ($spoolKey) { Invoke-SpoolDownload -Uri $uri -Headers $authHeader -OutFile $tf -Key $spoolKey -TimeoutSec $xferTo -IdleSec $idleSec | Out-Null }
                                    else { Invoke-WebRequest -UseBasicParsing -Method Get -Uri $uri -Headers $authHeader -OutFile $tf -TimeoutSec $xferTo | Out-Null }
                                    & $paceEase $pace
                                }
                                $ok = $true; break
                            } catch {
                                $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
                                if (@(429,503) -contains $st) {
                                    & $paceBump $pace
                                    $throttleTry++
                                    $ra = 0; $rh = $null; try { $rh = $_.Exception.Response.Headers } catch {}; if ($rh) { foreach ($rn in 'X-Rate-Limit-Retry-After-Seconds','Retry-After') { if (-not $ra) { try { $ra = [int](@($rh.GetValues($rn))[0]) } catch { try { $rv = $rh[$rn]; if ($rv) { $ra = [int]$rv } } catch {} } } } }
                                    if ($ra -le 0) { $ra = [int][math]::Min([math]::Pow(2,[math]::Min($throttleTry,5)),30) }
                                    if ($throttleTry -ge 40) { $ok = $false; $err = "still rate-limited by Datto (HTTP $st) after $throttleTry waits: $($_.Exception.Message)"; break }
                                    Start-Sleep -Seconds $ra
                                } else {
                                    $hardTry++; if ($_.Exception.Message -match 'no data received for') { $idleTry++; if ($idleTry -ge $idleMax) { $hardTry = 99 } }
                                    if ($hardTry -ge 5) { $ok = $false; $err = $_.Exception.Message; break }
                                    Start-Sleep -Seconds ([int][math]::Min([math]::Pow(2,$hardTry),30))
                                }
                            }
                        }
                        $dlSw.Stop()
                        if ($capBps -gt 0 -and $ok) {
                            $bwBytes += [double]$it.Size
                            $aheadSec = ($bwBytes / $capBps) - ([DateTime]::UtcNow - $bwStart).TotalSeconds
                            if ($aheadSec -gt 0) { Start-Sleep -Milliseconds ([int][math]::Min($aheadSec * 1000, 600000)) }
                        }
                        $spool.Add(@{ Item = $it; TempFile = $tf; Ok = $ok; Error = $err; DlMs = $dlSw.Elapsed.TotalMilliseconds })
                    }
                } finally { $spool.CompleteAdding() }
            }).AddArgument($spool).AddArgument($toDo).AddArgument((Get-RunspaceConfig -Config $Config)).AddArgument($spaceTemp).AddArgument($script:SpoolKey).AddArgument($script:SpoolHelperSource).AddArgument($script:DattoPace)
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
                Lz3402e3c9c5 -Activity "Files: $($row.Space)" -Status $it.RelativePath -Current $fIdx -Total $fTotal -Id 2 | Out-Null
                $dlMs = 0.0; try { $dlMs = [double]$ready.DlMs } catch {}
                if (-not $ready.Ok) { $failed++; Write-MigrationLog ERROR "  DOWNLOAD FAILED $($it.RelativePath): $($ready.Error). In plain terms: the file could not be downloaded from $($script:SrcNoun). It will be retried on the next Sync."; Write-AuditRecord -Space $row.Space -Item $it -Status 'DownloadError' -DownloadMs $dlMs -ErrorMsg $ready.Error; if ($ready.TempFile) { $delQ.Enqueue($ready.TempFile) }; continue }
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $destInfo = Send-FileToDestination -Config $Config -DriveId $driveId -TargetFolder $effSub -Item $it -LocalFile $ready.TempFile -Space $row.Space
                    $v = Lz397101acd9 -Item $it -LocalFile $ready.TempFile -DestInfo $destInfo
                    $sw.Stop()
                    if ($v.Ok) {
                        if ($v.Zero) { Write-MigrationLog WARN "  empty file (0 bytes), uploaded as-is: $($it.RelativePath)"; $zero++ }
                        $copied++; $bytes += $it.Size
                        if ($script:VerboseFiles) { Write-MigrationLog INFO "  + [$($it.RelativePath)] $($v.Reason)" }
                        $stat = if($v.Zero){'ZeroByte'}else{'Copied'}
                        Write-AuditRecord -Space $row.Space -Item $it -Status $stat -Reason (Lzd93f9ea715 -Repair $repair -Item $it -Status $stat -Reason $v.Reason) -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $sw.Elapsed.TotalMilliseconds -DownloadMs $dlMs
                    } else {
                        $verifyFail++; Write-MigrationLog ERROR "  VERIFY FAILED $($it.RelativePath): $($v.Reason). In plain terms: the uploaded copy did not match the original, so it was not marked done. It will be retried on the next Sync."
                        Write-AuditRecord -Space $row.Space -Item $it -Status 'VerifyFail' -Reason $v.Reason -DestSize $destInfo.Size -DestPath $destInfo.Path -DestHash $destInfo.Hash -Method $destInfo.Method -Retries $destInfo.Retries -DurationMs $sw.Elapsed.TotalMilliseconds -DownloadMs $dlMs
                    }
                } catch { $sw.Stop(); $failed++; Write-MigrationLog ERROR "  UPLOAD FAILED $($it.RelativePath): $($_.Exception.Message). In plain terms: the file could not be uploaded to Microsoft 365. It will be retried on the next Sync."; Write-AuditRecord -Space $row.Space -Item $it -Status 'Error' -DurationMs $sw.Elapsed.TotalMilliseconds -DownloadMs $dlMs -ErrorMsg $_.Exception.Message }
                finally { $delQ.Enqueue($ready.TempFile) }
                Lz8d39824bd6 -Done $fIdx -Total $fTotal -BytesDone $bytes -BytesTotal $spaceBytesTotal -Space $row.Space -SmallDone $etaSmallDone -SmallTotal $etaSmallTotal -LargeBytesDone $etaLargeDone -LargeBytesTotal $etaLargeTotal -Final 1
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
            Write-MigrationLog $lvl "  $($row.Space): copied $copied, skipped $skipped, failed $failed, failed verification $verifyFail, empty files $zero ($szTxt)"
        } else {
            $previewCaveat =
                if ($Mode -eq 'FirstPass') { " This counts every file as if none of it existed at the destination yet (a Full-migration-shaped count); Sync would very likely copy far fewer, since it only touches files that are new or changed there." }
                elseif ($Mode -eq 'Delta') { if ($script:SyncPreviewRead) { " This is a real Sync forecast: the destination was read (nothing was written) and files already there are counted as skipped." } else { " NOTE: the destination could not be read for this preview, so every file was counted as new - treat it as an upper bound, not a Sync forecast." } }
                else { '' }
            Write-MigrationLog INFO "  $($row.Space): PREVIEW - would copy $copied file(s) ($szTxt) and skip $skipped unchanged. Nothing was uploaded.$previewCaveat"
        }
        $summary.Add([pscustomobject]@{ Space=$row.Space; Copied=$copied; Skipped=$skipped; Failed=$failed; VerifyFail=$verifyFail; ZeroByte=$zero; GB=$gb; Bytes=$bytes })
        $spacesCompleted++
        if ($willWrite -and -not $ResultDir) { Lz6aa2b8bd37 -Config $Config -Mode $Mode -StartUtc $runStart -AuditFile $script:AuditFile -ExpectedFiles $expectedTotal -SpacesPlanned $spacesPlanned -SpacesCompleted $spacesCompleted }
    }
    try { Write-Progress -Id 1 -Activity "Transfer ($Mode)" -Completed } catch {}
    if ($ResultDir) {
        $summary | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $ResultDir ((ConvertTo-Slug ($map[0].Space)) + '-' + [guid]::NewGuid().ToString('N') + '.json')) -Encoding UTF8
    } else {
        $summary | Protect-CsvRow | Export-Csv -Path (Join-Path $Config.run.reportRoot "api-transfer-$Mode-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv") -NoTypeInformation -Encoding UTF8
    }
    if ($willWrite -and $script:PreserveDates -and -not $script:OmitFsi -and
        $null -ne $script:SweepList -and $script:SweepList.Count -gt 0 -and
        $Config.destination.provider -ne 'LocalSim') {
        try {
            Write-MigrationLog INFO "Checking that Microsoft kept the original dates on $($script:SweepList.Count) Office file(s) (Microsoft reprocesses these after upload and can bump the date)..."
            Start-Sleep -Seconds 15
            $swOk = 0; $swFixed = 0; $swFail = 0
            foreach ($sw in $script:SweepList) {
                try {
                    $di = Invoke-LiscGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$($sw.Drive)/root:/$($sw.Enc)`?`$select=fileSystemInfo"
                    $destLm = $null
                    try { $destLm = Lz631d6c8c21 $di['fileSystemInfo']['lastModifiedDateTime'] } catch { try { $destLm = Lz631d6c8c21 $di.fileSystemInfo.lastModifiedDateTime } catch {} }
                    $destCr = $null
                    try { $destCr = Lz631d6c8c21 $di['fileSystemInfo']['createdDateTime'] } catch { try { $destCr = Lz631d6c8c21 $di.fileSystemInfo.createdDateTime } catch {} }
                    $srcLm = ConvertTo-UtcDate $sw.Mtime
                    $swCt = ''; try { if ($sw.ContainsKey('Ctime')) { $swCt = "$($sw.Ctime)" } } catch {}
                    $srcCr = if ($swCt) { ConvertTo-UtcDate $swCt } else { $srcLm }
                    $mDrift = ($null -ne $destLm -and $null -ne $srcLm -and [math]::Abs(($destLm - $srcLm).TotalSeconds) -gt 2)
                    $cDrift = ($null -ne $destCr -and $null -ne $srcCr -and [math]::Abs(($destCr - $srcCr).TotalSeconds) -gt 2)
                    if ($mDrift -or $cDrift) {
                        Set-GraphFileDates -Config $Config -DriveId $sw.Drive -EncPath $sw.Enc -Mtime $sw.Mtime -Ctime $swCt
                        $swFixed++
                    } else { $swOk++ }
                } catch {
                    $swFail++
                    if ($swFail -le 3) { Write-MigrationLog WARN "  Date check could not confirm '$($sw.Rel)': $($_.Exception.Message)" }
                }
                if ($script:OmitFsi) { break }
            }
            if ($swFixed -or $swFail) { Write-MigrationLog OK "Date check: $swOk file(s) already carried the original date, $swFixed re-stamped after Microsoft's reprocessing, $swFail could not be checked." }
            else { Write-MigrationLog OK "Date check: all $swOk Office file(s) kept their original dates." }
        } catch { Write-MigrationLog WARN "The date check after upload could not run ($($_.Exception.Message)). Files are uploaded and safe; dates can be confirmed with 'Verify files arrived'." }
    }
    Close-AppendWriters
    if ($willWrite -and -not $ResultDir -and $Config.destination.provider -ne 'LocalSim' -and $script:AuditFile -and (Test-Path $script:AuditFile)) {
        $provOn = $true
        try { if (((Test-ConfigProp $Config.run 'provenance')) -and ((Test-ConfigProp $Config.run.provenance 'enabled'))) { $provOn = [bool]$Config.run.provenance.enabled } } catch {}
        if ($provOn -and ([int](Get-SafeSum -Items $summary -Property Copied) + [int](Get-SafeSum -Items $summary -Property ZeroByte)) -eq 0) { $provOn = $false; Write-MigrationLog INFO "No provenance pack for this run: nothing was copied, so there is nothing new to attest. The packs from earlier runs still stand, and the 'Provenance pack' button builds one on demand." }
        if ($provOn) { try { Invoke-ProvenancePack -Config $Config -AuditPath $script:AuditFile -NoStageLog | Out-Null } catch { Write-MigrationLog WARN "The provenance pack could not be built ($($_.Exception.Message)). The run itself is unaffected; build it any time with the 'Provenance pack' button." } }
        try { Invoke-ProvenanceColumnSweep -Config $Config -AuditFile $script:AuditFile } catch {}
    }
    $tc = Get-SafeSum -Items $summary -Property Copied
    $ts = Get-SafeSum -Items $summary -Property Skipped
    $tf = Get-SafeSum -Items $summary -Property Failed
    $tv = Get-SafeSum -Items $summary -Property VerifyFail
    $tb = Get-SafeSum -Items $summary -Property Bytes
    $szTxt = Format-Bytes $tb
    $elapsed = (Get-Date) - $runStart
    $el = '{0:hh\:mm\:ss}' -f $elapsed
    $auditRows = @()
    if ($script:AuditFile -and (Test-Path $script:AuditFile)) { try { $auditRows = @(Import-AuditCsv $script:AuditFile) } catch { $auditRows = @() } }
    $retrySum = 0
    foreach ($ar in $auditRows) { try { $retrySum += [int]"0$($ar.Retries)" } catch {} }
    $thrShown = [math]::Max([int]$script:RetryEvents, [int]$retrySum)
    $rate = if ($elapsed.TotalSeconds -gt 0 -and $tb -gt 0) { " ~$([math]::Round(($tb*8/1e6)/$elapsed.TotalSeconds,1)) Mb/s ($([math]::Round(($tb/1e6)/$elapsed.TotalSeconds,1)) MB/s)." } else { '' }
    if ($willWrite) {
        $lvl = if (($tf + $tv) -gt 0) { 'ERROR' } elseif ($script:TrialCapped) { 'WARN' } else { 'OK' }
        Write-MigrationLog $lvl "$(if ($Mode -eq 'Delta') { 'Sync' } else { 'Upload' }) finished in $(Format-Duration $elapsed). Totals: copied $tc, skipped $ts, failed $tf, failed verification $tv, $szTxt.$rate  Rate-limit pauses and retries: $thrShown.$(if ([int]$script:DattoPauseEvents -gt 0) { " Datto read-limit pauses: $([int]$script:DattoPauseEvents) (Datto's own limit, not Microsoft 365)." })"
        if ($script:RenameCount -gt 0) { Write-MigrationLog INFO "Tidied $script:RenameCount name(s) to suit SharePoint (trailing spaces, illegal characters). Every change is listed in the report and in: $script:RenameFile" }
        if ($script:CollisionCount -gt 0) { Write-MigrationLog WARN "$script:CollisionCount name collision(s): two $($script:SrcItem) items would land on the same SharePoint path. Review before relying on this migration. Details in the report and in: $script:CollisionFile" }
        if (($tf + $tv) -gt 0) {
            Write-MigrationLog WARN "In plain terms: uploaded $tc file(s) ($szTxt), but $($tf + $tv) did not make it ($tf failed, $tv could not be verified). Next step: click 'Sync new and changed' to retry the ones that did not upload, then 'Verify files arrived' to confirm everything is there."
            Write-MigrationLog WARN "Review this log for [ERROR] lines (files that failed or failed verification). Failed files are not recorded as done; 'Sync new and changed' will retry them."
        } elseif ($script:TrialCapped) {
            Write-MigrationLog WARN "In plain terms: NOT all done. This is an evaluation run: it copied $tc file(s) ($szTxt) for real and then stopped at its free allowance - the rest of $($script:SrcNoun) was never attempted, not because anything failed. Licence this tenant at https://www.liscaragh.com to migrate everything, then run Sync to pick up exactly where this stopped."
        } else {
            Write-MigrationLog OK "In plain terms: all done. Uploaded $tc file(s) ($szTxt) with no failures. Next step (optional): click 'Verify files arrived' to double-check, or 'Compare sizes' for a quick overview."
        }
        if (-not $ResultDir -and $script:AuditFile -and (Test-Path $script:AuditFile)) {
            Write-MigrationLog OK "Audit trail written: $script:AuditFile"
            try {
                $diag = Get-RunDiagnosis -Rows $auditRows -Elapsed $elapsed -ConfiguredWorkers $UploadWorkers -ThrottleEvents $thrShown -DattoPauses ([int]$script:DattoPauseEvents) -TrialCapped:$script:TrialCapped
                if ($diag) {
                    Write-MigrationLog INFO "What limited this run: $($diag.Verdict). $($diag.Why)"
                    Write-MigrationLog INFO "  $($diag.Action)"
                    Write-MigrationLog INFO "  Numbers: moved $(Format-Bytes $diag.Bytes) at about $($diag.AggMbps) Mb/s overall; single file about $($diag.PerStreamMbps) Mb/s; $($diag.UpSec)s uploading vs $($diag.DlSec)s downloading."
                    if ($diag.Concurrency) { Write-MigrationLog INFO "  Concurrency: $($diag.Concurrency)" }
                    if ($diag.RetryDetail) { Write-MigrationLog INFO "  Retries: $($diag.RetryDetail)" }
                    if ($diag.Projection)  { Write-MigrationLog INFO "  Planning: $($diag.Projection)" }
                    if ($diag.Headroom)    { Write-MigrationLog INFO "  Headroom: $($diag.Headroom)" }
                }
            } catch {}
        }
    }
    else {
        if ($Mode -eq 'Delta') {
            $pvMode = if ($DeltaMode -eq 'AddMissing') { 'add new files only' } else { "update where $($script:SrcNounBare) is newer" }
            Write-MigrationLog OK "Sync preview finished in $el. Nothing was uploaded. A real Sync ($pvMode) would copy $tc file(s), $szTxt, and leave $ts file(s) already at the destination alone$(if (-not $script:SyncPreviewRead) { ' (the destination could not be read, so treat this as an upper bound)' }). To do it, choose 'Sync new and changed' with the same option and leave 'Preview only' unticked."
        } else {
            Write-MigrationLog OK "Preview finished in $el. This was a rehearsal, nothing was uploaded. It would copy $tc file(s), $szTxt, counting every one of them as if starting fresh - this preview does not check what is already at the destination, so it cannot forecast a Sync. In plain terms: click 'Full migration' only if you want every file re-copied from $($script:SrcNounBare) regardless of what is already there; for an ordinary top-up that copies only what is new or changed, use 'Sync new and changed' instead - it will very likely touch far fewer files than the number above."
        }
    }
    }
    catch {
        $transferError = $_
        $teMsg = "$($_.Exception.Message)"
        if ($teMsg -like "*$($script:StopTag)*") {
            Write-MigrationLog ERROR ("RUN STOPPED before all files were processed: " + (($teMsg -replace [regex]::Escape($script:StopTag), '').Trim()))
        } else {
            Write-MigrationLog ERROR "RUN ABORTED before all files were processed: $teMsg. Everything below is the technical detail (F28, DECISIONS 180aw), so this can be diagnosed without reproducing it."
            Write-CrashDetail -ErrorRecord $_
        }
    }
    finally {
        Lz0e4ac9dd84 -Config $Config -Mode $Mode -RunStart $runStart -ExpectedFiles $expectedTotal `
            -SpacesPlanned $spacesPlanned -SpacesCompleted $spacesCompleted -RunError $transferError `
            -WillWrite:$willWrite -ResultDir $ResultDir
    }
}
function Merge-ParallelSideFiles {
    param($Config, [string]$ResultDir, [string]$Mode, [string]$Stamp = '', $Rows = $null, $AuditRows = $null)
    if (-not $ResultDir -or -not (Test-Path $ResultDir)) { return }
    if (-not $Stamp) { $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss' }
    $cross = New-Object System.Collections.Generic.List[object]
    if ($Rows -and $AuditRows) {
        try {
            $destIdOf = @{}
            foreach ($r in $Rows) { if (-not $destIdOf.ContainsKey("$($r.Space)")) { $destIdOf["$($r.Space)"] = Get-RowDestId $r } }
            $firstAt = @{}
            foreach ($a in $AuditRows) {
                if (-not "$($a.DestPath)" -or ("$($a.Status)" -ne 'Copied' -and "$($a.Status)" -ne 'ZeroByte')) { continue }
                $k = "$($destIdOf["$($a.Space)"])|" + "$($a.DestPath)".ToLowerInvariant()
                if (-not $firstAt.ContainsKey($k)) { $firstAt[$k] = $a; continue }
                $first = $firstAt[$k]
                if ("$($a.Space)" -eq "$($first.Space)") { continue }
                $cross.Add([pscustomobject][ordered]@{ Space = "$($a.Space)"; Final = "$($a.DestPath)"; FirstSource = "$($first.SourcePath) (from $($first.Space))"; SecondSource = "$($a.SourcePath) (from $($a.Space))" })
                Write-MigrationLog WARN "  NAME COLLISION in [$($a.Space)]: '$($a.SourcePath) (from $($a.Space))' and '$($first.SourcePath) (from $($first.Space))' both land on '$($a.DestPath)'. In plain terms: two $($script:SrcItem) items wrote the same SharePoint path, so one has overwritten the other. Both are in the collisions CSV and the report."
            }
        } catch { Write-MigrationLog WARN "  The cross-$($script:SrcItem) collision check could not run ($($_.Exception.Message)). The run itself is unaffected; the report still lists any collision." }
    }
    foreach ($kind in 'renames','collisions','excluded') {
        $rowsK = New-Object System.Collections.Generic.List[object]
        foreach ($f in @(Get-ChildItem $ResultDir -Filter "$kind-*.csv" -ErrorAction SilentlyContinue)) { try { foreach ($r in @(Import-Csv $f.FullName)) { $rowsK.Add($r) } } catch {} }
        if ($kind -eq 'collisions') { foreach ($x in $cross) { $rowsK.Add($x) } }
        if ($rowsK.Count) {
            $out = Join-Path $Config.run.reportRoot "$kind-$Mode-$Stamp.csv"
            try { $rowsK | Protect-CsvRow | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8; Write-MigrationLog OK "  $kind trail written: $out ($($rowsK.Count) row(s))" } catch {}
        }
    }
}
function Lzd0f3347cf6 {
    param($Config, $Rows, [string]$Mode, [string]$DeltaMode='NewerWins', [int]$SpoolAhead, [int]$MaxParallelSpaces, [switch]$Execute)
    $willWrite = [bool]$Execute
    Write-MigrationLog INFO "Parallel $($script:SrcItems): $($Rows.Count) $($script:SrcItem)(s), $MaxParallelSpaces at a time."
    if ($script:GuiMode) { Write-Host "##SOURCE##|0|$($Rows.Count)|$MaxParallelSpaces" }
    $parallelStart = Get-Date
    $script:RunSpaceNames = @($Rows | ForEach-Object { "$($_.Space)" })
    $childExitCodes = New-Object System.Collections.Generic.List[int]
    $resultDir = Join-Path $Config.run.stateRoot ("_parallel-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
    if ($willWrite) { Lz6aa2b8bd37 -Config $Config -Mode $Mode -StartUtc $parallelStart -AuditFile '' -ExpectedFiles 0 -SpacesPlanned $Rows.Count -SpacesCompleted 0 -ResultDir $resultDir }
    $pwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $self = $PSCommandPath
    $childLogDir = Join-Path $Config.run.logRoot 'parallel'
    New-Item -ItemType Directory -Path $childLogDir -Force | Out-Null
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($r in $Rows) { $queue.Enqueue($r.Space) }
    $running = @{}
    $childInfo = @{}
    function Lz42021dfe22 {
        param($SpaceName)
        $q = { param($s)
            $s = "$s"
            if ($s -ne '' -and $s.IndexOfAny(" `t`"".ToCharArray()) -lt 0) { return $s }
            $sb = New-Object System.Text.StringBuilder; [void]$sb.Append('"'); $bs = 0
            foreach ($ch in $s.ToCharArray()) {
                if     ($ch -eq '\') { $bs++ }
                elseif ($ch -eq '"') { [void]$sb.Append('\', ($bs*2+1)); [void]$sb.Append('"'); $bs = 0 }
                else                 { if ($bs) { [void]$sb.Append('\', $bs) }; [void]$sb.Append($ch); $bs = 0 }
            }
            if ($bs) { [void]$sb.Append('\', ($bs*2)) }
            [void]$sb.Append('"'); $sb.ToString()
        }
        $slug = ConvertTo-Slug $SpaceName
        $childArgs = @('-NoProfile','-File', (& $q $self),
                       '-ConfigPath', (& $q $script:ConfigPath),
                       '-Action','Transfer','-OnlySpace', (& $q $SpaceName),
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
    function Lzf8ac163fbc {
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
            } elseif ($ln -match '^##SCOPE##\|(\d+)\|(\d+)\|(\d+)$') {
                $ci.Scope = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
                $sa = 0; $sb2 = 0; $sc2 = 0
                foreach ($cx in $childInfo.Values) { if ($cx.ContainsKey('Scope') -and $cx.Scope) { $sa += $cx.Scope[0]; $sb2 += $cx.Scope[1]; $sc2 += $cx.Scope[2] } }
                if ($script:GuiMode) { Write-Host "##SCOPE##|$sa|$sb2|$sc2" }
            } elseif ($ln -match '^##[A-Z]+##') {
                Write-Host $ln
            } elseif ($ln) {
                Write-Host ("  [{0}] {1}" -f $Space, $ln)
            }
        }
    }
    function Lz6c3e915243 {
        $sd=0; $st=0; $sb=[int64]0; $sbt=[int64]0
        foreach ($ci in $childInfo.Values) { $sd+=$ci.Done; $st+=$ci.Total; $sb+=$ci.Bytes; $sbt+=$ci.BytesTotal }
        if ($st -gt 0) { Lz8d39824bd6 -Done $sd -Total $st -BytesDone $sb -BytesTotal $sbt -Space '(all projects)' }
    }
    while ($queue.Count -gt 0 -or $running.Count -gt 0) {
        while ($running.Count -lt $MaxParallelSpaces -and $queue.Count -gt 0) {
            $sp = $queue.Dequeue()
            Write-MigrationLog INFO "  launch: $sp"
            $running[(Lz42021dfe22 -SpaceName $sp)] = $sp
        }
        Start-Sleep -Milliseconds 400
        foreach ($proc in @($running.Keys)) {
            $sp = $running[$proc]
            Lzf8ac163fbc -Space $sp
            if ($proc.HasExited) {
                Lzf8ac163fbc -Space $sp
                $lvl = if ($proc.ExitCode -eq 0) { 'OK' } else { 'ERROR' }
                Write-MigrationLog $lvl "  done: $sp (exit $($proc.ExitCode))"
                $childExitCodes.Add([int]$proc.ExitCode)
                $running.Remove($proc)
            }
        }
        Lz6c3e915243
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
        foreach ($r in @(Import-AuditCsv $a.FullName)) { $auditRows.Add($r) }
    }
    if ($auditRows.Count) {
        $auditOut = Join-Path $Config.run.reportRoot "audit-$Mode-$stamp.csv"
        $auditRows | Export-Csv -Path $auditOut -NoTypeInformation -Encoding UTF8
        if ($script:SelectionRules.Count) { try { Copy-Item -LiteralPath (Join-Path $Config.run.reportRoot 'selection.json') -Destination (Join-Path $Config.run.reportRoot "selection-$Mode-$stamp.json") -Force } catch {} }
        Write-MigrationLog OK "Audit trail written: $auditOut ($($auditRows.Count) file actions)"
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
    Merge-ParallelSideFiles -Config $Config -ResultDir $resultDir -Mode $Mode -Stamp $stamp -Rows $Rows -AuditRows $auditRows
    if ($willWrite -and $Config.destination.provider -ne 'LocalSim' -and $auditRows.Count -and $auditOut -and (Test-Path $auditOut)) {
        $provOnP = $true
        try { if (((Test-ConfigProp $Config.run 'provenance')) -and ((Test-ConfigProp $Config.run.provenance 'enabled'))) { $provOnP = [bool]$Config.run.provenance.enabled } } catch {}
        if ($provOnP -and @($auditRows | Where-Object { "$($_.Status)" -match '^(Copied|ZeroByte|Repaired)' }).Count -eq 0) { $provOnP = $false; Write-MigrationLog INFO "No provenance pack for this run: nothing was copied, so there is nothing new to attest. The packs from earlier runs still stand." }
        if ($provOnP) { try { Invoke-ProvenancePack -Config $Config -AuditPath $auditOut -NoStageLog | Out-Null } catch { Write-MigrationLog WARN "The provenance pack could not be built ($($_.Exception.Message)). The run itself is unaffected; build it any time with the 'Provenance pack' button." } }
        if ($script:ProvColsOn -or @($script:FolderColRules).Count -or @($script:FilenameColRules).Count -or @($script:ExtCatRules).Count -or $script:RetentionYears -gt 0) {
            try { Connect-Destination -Config $Config; Invoke-ProvenanceColumnSweep -Config $Config -AuditFile $auditOut } catch { Write-MigrationLog WARN "Provenance columns could not be stamped after the parallel run ($($_.Exception.Message)). The files are uploaded; the run is unaffected." }
        }
    }
    Remove-Item $resultDir -Recurse -Force -ErrorAction SilentlyContinue
    Lze3b49cb7ce -Config $Config
    $tc = Get-SafeSum -Items $all -Property Copied
    $tf = Get-SafeSum -Items $all -Property Failed
    $tv = Get-SafeSum -Items $all -Property VerifyFail
    Write-MigrationLog OK "Parallel $($script:SrcItems) finished. Copied $tc, failed $tf, failed verification $tv. Record: $combined"
}
function Get-RowDestLabel {
    param($Row)
    if ("$($Row.DestinationType)" -eq 'OneDrive') { return "OneDrive of $($Row.TargetPrincipal)" }
    $lib = ''
    try { if ((Test-ConfigProp $Row 'TargetLibrary')) { $lib = "$($Row.TargetLibrary)".Trim() } } catch {}
    if (-not $lib) { $lib = 'the default library' }
    return "$($Row.DestinationUrl) > $lib"
}
function Get-LocalFsRootSeed {
    param($Config, $Row)
    $isLocalFs = $false
    try { if ($Config -and ($Config.PSObject.Properties.Name -contains 'source') -and $Config.source -and ("$($Config.source.provider)" -eq 'LocalFs')) { $isLocalFs = $true } } catch {}
    if (-not $isLocalFs) { return '' }
    $scope = ''
    try { if ($Row.PSObject.Properties.Name -contains 'SourceSubPath') { $scope = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
    if ($scope) { return '' }
    $co = $false
    try { if ($Row.PSObject.Properties.Name -contains 'SourceContentsOnly') { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    if ($co) { return '' }
    $seed = "$($Row.Space)"
    try { if (($Config.run.PSObject.Properties.Name -contains 'sanitiseNames') -and $Config.run.sanitiseNames) { $seed = ConvertTo-SafeRelPath $seed } } catch {}
    return $seed
}
function Get-DestinationInventory {
    param($Config, $Row, [switch]$WithTimes)
    Lz883d31a1c9 -Phase 'Inventory' -Space "$($Row.Space)" -UnlessPhase 'Transfer'
    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $times = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $sizes = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($Config.destination.provider -eq 'LocalSim') {
        $base = Join-Path $Config.destination.sim.rootPath (ConvertTo-Slug ($Row.DestinationUrl))
        $destSub = Join-SubPath ((@(("$($Row.TargetSubFolder)" -split '[\\/]') | Where-Object { $_ -ne '' })) -join '/') (Get-NestFolder $Config $Row)
        $simScope = ''
        try { if ((Test-ConfigProp $Row 'SourceSubPath')) { $simScope = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
        $simCo = $false
        try { if ((Test-ConfigProp $Row 'SourceContentsOnly')) { $simCo = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
        $rootSeed = Get-LocalFsRootSeed -Config $Config -Row $Row
        $seedSeg = if ($simScope -and -not $simCo) { $simScope } elseif ($rootSeed) { $rootSeed } else { '' }
        $sub = if ($simCo) { $destSub } else { Join-SubPath $destSub $seedSeg }
        $root = if ($sub) { Join-Path $base ($sub -replace '/', '\') } else { $base }
        if (-not (Test-Path $root)) { return @{ Count = 0; Bytes = 0; Paths = $paths; Times = $times; Sizes = $sizes } }
        $files = @(Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/]_DattoMigration[\\/]' -and -not (Test-LocalWalkJunk -Item $_ -Base $root) })
        foreach ($f in $files) {
            $relBare = ($f.FullName.Substring($root.Length).TrimStart('\','/') -replace '\\','/')
            $rel = if ($seedSeg -and -not $simCo) { "$seedSeg/$relBare" } else { $relBare }
            [void]$paths.Add($rel)
            $sizes[$rel] = [int64]$f.Length
            if ($WithTimes) { $times[$rel] = $f.LastWriteTimeUtc }
        }
        return @{ Count = $files.Count; Bytes = (Get-SafeSum -Items $files -Property Length); Paths = $paths; Times = $times; Sizes = $sizes }
    }
    $res = Resolve-DestinationDriveId -Config $Config -Row $Row
    $driveId = $res.DriveId
    $scope = ''
    try { if ((Test-ConfigProp $Row 'SourceSubPath')) { $scope = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
    $co = $false
    try { if ((Test-ConfigProp $Row 'SourceContentsOnly')) { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    $isLocalFs = $false
    try { if (($Config.PSObject.Properties.Name -contains 'source') -and $Config.source -and ("$($Config.source.provider)" -eq 'LocalFs')) { $isLocalFs = $true } } catch {}
    if (-not $scope -and -not $isLocalFs) { $co = $false }
    $rootSeed = Get-LocalFsRootSeed -Config $Config -Row $Row
    $seedSeg = if ($co) { '' } elseif ($scope) { $scope } else { $rootSeed }
    $startSub = if ($co) { $res.SubFolder } else { Join-SubPath $res.SubFolder $seedSeg }
    $count = 0; $bytes = [int64]0; $folders = 0; $pages = 0
    $dProg = @{ LastLog = [DateTime]::UtcNow }
    $emitDest = {
        param([string]$Where, [switch]$Force)
        $now = [DateTime]::UtcNow
        if (-not $Force -and ($now - $dProg.LastLog).TotalSeconds -lt 3) { return }
        $dProg.LastLog = $now
        $w = if ($Where) { "  now in: /$Where" } else { '' }
        Write-MigrationLog INFO "  DESTINATION: $('{0:N0}' -f $folders) folder(s) read, $('{0:N0}' -f $count) file(s) found so far.$w"
        if ($script:GuiMode) { Write-Host "##STATUS##|Source: $('{0:N0}' -f $script:SrcTotal) files (done)   ->   Destination: $('{0:N0}' -f $folders) folders, $('{0:N0}' -f $count) files so far (reading Microsoft 365)" }
    }
    $stack = New-Object System.Collections.Stack
    $startNode = if ($startSub) { "root:/$([uri]::EscapeDataString($startSub) -replace '%2F','/'):" } else { 'root' }
    $stack.Push(@{ Node = $startNode; Prefix = $(if ($seedSeg) { "$seedSeg/" } else { '' }); Root = $true })
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $uri = "https://graph.microsoft.com/v1.0/drives/$driveId/$($cur.Node)/children?`$select=id,name,size,folder,fileSystemInfo,lastModifiedDateTime&`$top=999"
        $page = $null
        try {
            $page = Get-GraphCollection -Config $Config -Uri $uri -What "list $($cur.Node)" -QuietNotFound:([bool]$cur.Root)
        } catch {
            $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
            if ($cur.Root -and $st -eq 404) {
                Write-MigrationLog INFO "  destination inventory: the folder does not exist at the destination yet, so there is nothing to compare against and every file will be copied. This is normal the first time you copy into a new folder."
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
                if ($WithTimes) {
                    $lmRaw = $null
                    try { $lmRaw = $c['fileSystemInfo']['lastModifiedDateTime'] } catch {}
                    if ($null -eq $lmRaw) { try { $lmRaw = $c['lastModifiedDateTime'] } catch {} }
                    $times[$rel] = (Lz631d6c8c21 $lmRaw)
                }
            }
        }
    }
    $extra = $pages - $folders
    Write-MigrationLog INFO "  DESTINATION FINISHED: $('{0:N0}' -f $count) file(s) across $('{0:N0}' -f $folders) folder(s), $pages page(s) followed."
    if ($extra -gt 0) {
        Write-MigrationLog WARN "  $extra destination folder(s) held more than one page of children. Before the paging fix everything past the first page was invisible here, so a Sync would have judged those files missing and re-uploaded over the top of them. They are now enumerated in full."
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
function Lz0385acd60f {
    $root = ''
    try { $root = "$env:LISCARA_EVAL_ROOT" } catch {}
    if ($root) { return @{ RegPath = ''; FilePath = (Join-Path $root 'eval.dat') } }
    $pd = ''
    try { $pd = "$env:ProgramData" } catch {}
    $fp = if ($pd) { Join-Path $pd (Join-Path 'Liscaragh' 'eval.dat') } else { '' }
    return @{ RegPath = 'HKCU:\Software\DattoMigration\State'; FilePath = $fp }
}
function Lzbf53cd1d81 {
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
    $st = Lz0385acd60f
    if ($st.RegPath) {
        try {
            $v = (Get-ItemProperty -Path $st.RegPath -Name $Key -ErrorAction Stop).$Key
            $p = Lzbf53cd1d81 "$v"
            if ($p.FirstPass -gt $out.FirstPass) { $out.FirstPass = $p.FirstPass }
            if ($p.Delta     -gt $out.Delta)     { $out.Delta     = $p.Delta }
        } catch {}
    }
    if ($st.FilePath) {
        try {
            if (Test-Path $st.FilePath) {
                foreach ($line in (Get-Content $st.FilePath -ErrorAction Stop)) {
                    if ("$line".StartsWith("$Key=")) {
                        $p = Lzbf53cd1d81 "$line"
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
    $st = Lz0385acd60f
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
    try { if (((Test-ConfigProp $Config.run 'licenceFile')) -and $Config.run.licenceFile) { $path = "$($Config.run.licenceFile)" } } catch {}
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
        $ptype = ''; try { if ($pl.PSObject.Properties.Name -contains 'Type') { $ptype = "$($pl.Type)" } } catch {}
        if ($ptype -and $ptype -ne 'licence') { $out.Reason = "the file is a signed '$ptype' document, not a licence"; return $out }
        $exp = ''; try { $exp = "$($pl.Expires)" } catch {}
        if ($exp) {
            $ed = [datetime]::MinValue
            if (-not [datetime]::TryParse($exp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$ed)) { $out.Reason = "the licence's expiry date ('$exp') could not be read"; return $out }
            if ($ed.ToUniversalTime().Date -lt (Get-Date).ToUniversalTime().Date) { $out.Reason = "the licence expired on $exp"; return $out }
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
function Format-SelLeftOutCount {
    param($Rows)
    $f = @(@($Rows) | Where-Object { $_ -and "$($_.Kind)" -ne 'Folder' }).Count
    $d = @(@($Rows) | Where-Object { $_ -and "$($_.Kind)" -eq 'Folder' }).Count
    if ($f -and $d) { return "$('{0:N0}' -f $f) + $('{0:N0}' -f $d) folder(s)" }
    if ($d) { return "$('{0:N0}' -f $d) folder(s)" }
    return "$('{0:N0}' -f $f)"
}
function Format-Bytes {
    param([int64]$b)
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N2} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N1} KB' -f ($b / 1KB)) }
    return "$b B"
}
function Get-RunDiagnosis {
    param($Rows, [TimeSpan]$Elapsed, [int]$ConfiguredWorkers=0, [int]$ThrottleEvents=0, [int]$DattoPauses=0, [switch]$TrialCapped)
    $copied    = @($Rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' })
    $attempted = @($Rows | Where-Object { $_.Status -ne 'Skipped' -and $_.Status -ne 'WouldCopy' })
    $fails     = @($Rows | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'DownloadError' -or $_.Status -eq 'VerifyFail' -or $_.Status -eq 'SkippedTooLarge' })
    $n = $copied.Count
    if ($n -eq 0) { return $null }
    if ($TrialCapped) {
        return [pscustomobject]@{
            Verdict='Evaluation limit reached, not a technical bottleneck'
            Why="This run stopped after its free evaluation allowance ($n file(s) copied for real), not because of speed, errors or throttling. Files after the allowance were not attempted."
            Action='Licence this Microsoft tenant to migrate everything, then run Sync to pick up from here - nothing already copied is repeated.'
            AggMbps=0; PerStreamMbps=0; EffConcurrency=0; AvgFileKB=0; AvgFileBytes=0; RetriedCount=0; RetriesSum=0; RetryPct=0; ThrottleFails=0
            Failures=$fails.Count; UpSec=0; DlSec=0; Files=$n; Bytes=(Get-SafeSum -Items $copied -Property SourceSizeBytes)
            Projection=$null; RetryDetail=$null; Concurrency=$null; Headroom=$null
        }
    }
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
    $throttleFails = 0
    foreach ($f in $fails) {
        $txt = "$($f.Error)"
        if ($txt -match '\b429\b' -or $txt -match 'Too Many Requests' -or $txt -match '\b503\b' -or $txt -match 'Service Unavailable' -or $txt -match 'activityLimitReached' -or $txt -match 'serviceNotAvailable') { $throttleFails++ }
    }
    $throttleHint = ($throttleFails -gt 0) -or ($retriesSum -gt 0) -or ($ThrottleEvents -gt 0)
    $thrEvN = [math]::Max([int]$ThrottleEvents, [int]$retriesSum)
    $lightThrottle = $throttleHint -and $throttleFails -eq 0 -and $retryPct -lt 1 -and $thrEvN -le 2
    $thrEvTxt = "$thrEvN brief pause$(if ($thrEvN -ne 1) { 's' })"
    if ($throttleFails -gt 0 -and $throttleFails -ge ($fails.Count/2.0)) {
        $extra = if ($retriedCount -gt 0) { " A further $retriedCount file(s) hit a backoff and recovered." } else { '' }
        $verdict = 'Microsoft 365 API throttling'
        $why     = "$('{0:N0}' -f [int64]$throttleFails) file(s) were refused outright by Microsoft 365 (HTTP 429/503, meaning 'slow down') and failed, which is $failPct% of those attempted.$extra"
        $action  = "Lower 'Upload workers' (try 4), then click 'Sync new and changed' to pick up the files that failed. Do not raise the worker count on a run that was throttled."
    }
    elseif ($fails.Count -gt 0 -and $failPct -ge 5) {
        $verdict = 'Errors / verification, not speed'
        $why     = "$($fails.Count) file(s) failed or failed verification, which is $failPct% of those attempted."
        $action  = "Click 'Sync new and changed' to retry them, then 'Verify files arrived' to confirm."
    }
    elseif (($upSec + $dlSec) -lt 1 -or $n -lt 5) {
        $verdict = 'Too small to analyse'
        $why     = "Only $n file(s) and under a second of transfer time, so there is not enough here to identify a bottleneck."
        $action  = "Run a larger batch to get a meaningful reading."
    }
    elseif ($wallSec -lt 60 -and $throttleFails -eq 0 -and $fails.Count -eq 0) {
        $verdict = 'Too short to judge'
        $why     = "This run copied $('{0:N0}' -f [int64]$n) file(s) in $([int]$wallSec)s. Under a minute, start-up and the last few files dominate the timings, so no bottleneck can be read from it."
        $action  = "A run of a few minutes or more gives a meaningful reading."
    }
    elseif ($throttleFails -gt 0 -or $retryPct -ge 5 -or ($n -ge 50 -and $retriesSum -ge ($n*0.1))) {
        $lostTxt = if ($throttleFails -gt 0) { " $('{0:N0}' -f [int64]$throttleFails) file(s) were refused outright and failed." } else { '' }
        $verdict = 'Microsoft 365 API throttling'
        $why     = "$('{0:N0}' -f [int64]$retriedCount) file(s) ($retryPct%) hit a backoff/retry and there were $('{0:N0}' -f [int64]$retriesSum) retries in total. Microsoft was asking the tool to slow down.$lostTxt"
        $action  = "This is expected on large jobs and the tool handled it automatically (easing off, then recovering). If it dominated, lower 'Upload workers' a little or run fewer projects at once."
    }
    elseif ($dlSec -gt ($upSec*1.5)) {
        $verdict = 'Datto download speed'
        $why     = "Reading files from $($script:SrcNoun) took the most time, about $([int]$dlSec)s downloading versus $([int]$upSec)s uploading."
        $action  = "The limit was the $($script:SrcNounBare) side, not writing to Microsoft 365. Usually the $($script:SrcNounBare) service or your download bandwidth."
    }
    elseif ($avgKB -lt 256 -and $n -ge 200 -and $perStream -lt 8) {
        $spdTxt = if ($perStream -gt 0) { "single-file speed was only about $perStream Mb/s" } else { "the files are too small to reach any real transfer speed" }
        $verdict = 'Many small files (per-file overhead)'
        $why     = "Files averaged about $avgKB KB across $('{0:N0}' -f [int64]$n) files, and $spdTxt, so per-file overhead (setup plus network latency), not bandwidth, set the pace."
        $action  = if ($throttleHint) {
            $(if ($lightThrottle) { "Bandwidth is not the bottleneck here; many tiny files are simply slow to handle one by one. Microsoft 365 pushed back only briefly ($thrEvTxt), which is too little to say whether more upload workers would help, so this run makes no recommendation about them." } else { "Bandwidth is not the bottleneck here; many tiny files are simply slow to handle one by one. But Microsoft was already pushing back on this run, so do not add upload workers - that would make the throttling worse." })
        } else {
            "Bandwidth is not the bottleneck here; many tiny files are simply slow to handle one by one. More upload workers can help if the tenant tolerates it."
        }
    }
    else {
        $verdict = 'Upload bandwidth (your internet upload speed)'
        $retryTxt = if ($retriesSum -eq 0) { 'with no retries' } else { "with only $retriesSum retr$(if ($retriesSum -eq 1) { 'y' } else { 'ies' })" }
        $why     = "Uploading dominated (about $([int]$upSec)s versus $([int]$dlSec)s reading) $retryTxt. Single stream was about $perStream Mb/s across roughly $effConc concurrent uploads, for about $aggMbps Mb/s overall."
        $underUsed = ($ConfiguredWorkers -gt 0 -and $effConc -lt (0.6 * $ConfiguredWorkers))
        $action  = if ($underUsed) {
            "Uploads ran about $effConc at a time out of $ConfiguredWorkers allowed, so the line was not shown to be full. The uploaders were often waiting: typically on a few large files at the end, or on per-file setup for small ones. This run cannot tell whether your line is the limit; a longer run with a steady mix of files will."
        } else {
            if ($throttleHint) { $(if ($lightThrottle) { "The upload line was the ceiling. Only more upload bandwidth will go faster. Microsoft 365 pushed back only briefly ($thrEvTxt), too little to judge whether more parallel uploads would help, so this run makes no recommendation about them." } else { "The upload line was the ceiling. Only more upload bandwidth will go faster; Microsoft 365 was already asking this run to slow down, so do not add upload workers." }) }
            else { "The upload line was the ceiling. Only more upload bandwidth, or more parallel uploads if Microsoft 365 tolerates it, will go faster." }
        }
        if ($underUsed) { $verdict = 'Uploaders not kept busy (the line was not shown to be full)' }
    }
    $fmtDur = {
        param($secs)
        if ($secs -lt 90)     { return ('{0}s' -f [int]$secs) }
        if ($secs -lt 5400)   { return ('{0:N0} min' -f ($secs/60.0)) }
        if ($secs -lt 172800) { return ('{0:N1} hours' -f ($secs/3600.0)) }
        return ('{0:N1} days' -f ($secs/86400.0))
    }
    $projection = if ($aggMbps -gt 0 -and $wallSec -ge 60) {
        "At about $aggMbps Mb/s overall, 100 GB would take about $(& $fmtDur (100.0*8000.0/$aggMbps)) and 1 TB about $(& $fmtDur (1000.0*8000.0/$aggMbps)) (network permitting).$(if ($avgKB -lt 256) { " This rate is for files averaging about $avgKB KB, where the setup for each file dominates; a job of larger files usually moves far more per hour, so these figures hold only for a similar mix of small files." })"
    } else { $null }
    $thrEv = [math]::Max($ThrottleEvents, $retriesSum)
    $retryDetail = if ($thrEv -gt 0) {
        $fw = if ($retriedCount -eq 1) { 'file' } else { 'files' }
        "$thrEv back-off/retry event(s) across $retriedCount $fw. Microsoft asked the tool to slow down; it did, then recovered."
    } else {
        "No back-offs or retries. Every file uploaded first time."
    }
    if ($DattoPauses -gt 0) { $retryDetail = "$retryDetail Separately, Datto asked the tool to wait $DattoPauses time(s) while reading; that is Datto's own rate limit, not Microsoft 365, and more upload workers would not change it." }
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
            "The limit is reading from $($script:SrcNoun), so more upload workers will not change it."
        }
        default { $null }
    }
    if ($throttleHint -and $headroom -and $headroom -match 'more upload workers should|more upload workers can help|try increasing them') {
        $lost = if ($throttleFails -gt 0) { "$throttleFails file(s) were refused outright with a 429/503" } else { "$retriedCount file(s) ($retryPct%) hit a backoff" }
        $headroom = if ($lightThrottle) { "Microsoft 365 pushed back briefly on this run ($lost) and it recovered. That is too little to judge headroom either way, so this run makes no recommendation about upload workers; a longer run will show whether more would help." } else { "Microsoft 365 was throttling this run ($lost), so do not add upload workers. If the throttling slowed the run noticeably, fewer workers or fewer projects at once is the lever; otherwise leave the settings as they are." }
    }
    return [pscustomobject]@{
        Verdict=$verdict; Why=$why; Action=$action
        ThrottleFails=$throttleFails
        AggMbps=$aggMbps; PerStreamMbps=$perStream; EffConcurrency=$effConc
        AvgFileKB=$avgKB; AvgFileBytes=$avgBytes; RetriedCount=$retriedCount; RetriesSum=$retriesSum; RetryPct=$retryPct
        Failures=$fails.Count; UpSec=[int]$upSec; DlSec=[int]$dlSec; Files=$n; Bytes=$bytes
        Projection=$projection; RetryDetail=$retryDetail; Concurrency=$concurrency; Headroom=$headroom
    }
}
function Lz179fcc6c79 {
    param($Config, $Row, $Items, $Inv, [string]$EffectivePrefix = '', [hashtable]$JobAuditIndex = $null)
    $folderOf = {
        param([string]$Path)
        $i = "$Path".LastIndexOf('/')
        if ($i -lt 0) { return '(top level)' }
        return "$Path".Substring(0, $i)
    }
    $scSan = (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames)
    $keyOf = { param($it) $k = "$($it.RelativePath)" -replace '\\','/'; if ($scSan) { $k = ConvertTo-SafeRelPath $k }; return $k }
    $srcSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($it in $Items) { [void]$srcSet.Add((& $keyOf $it)) }
    $agg = @{}
    $nExtra = 0; $nMissing = 0; $nOtherSource = 0
    $extraPaths   = [System.Collections.Generic.List[string]]::new()
    $missingPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $Inv.Paths) {
        if ($srcSet.Contains("$p")) { continue }
        if ($JobAuditIndex -and $JobAuditIndex.Count) {
            $absP = (Join-SubPath $EffectivePrefix "$p") -replace '\\','/'
            $owner = $JobAuditIndex[$absP.ToLowerInvariant()]
            if ($owner -and $owner -ne "$($Row.Space)") { $nOtherSource++; continue }
        }
        $nExtra++; [void]$extraPaths.Add("$p"); $k = "AtDestinationOnly|$(& $folderOf $p)"
        if ($agg.ContainsKey($k)) { $agg[$k]++ } else { $agg[$k] = 1 }
    }
    foreach ($it in $Items) {
        $p = "$($it.RelativePath)"
        if ($Inv.Paths.Contains((& $keyOf $it))) { continue }
        $nMissing++; [void]$missingPaths.Add("$p"); $k = "InDattoOnly|$(& $folderOf $p)"
        if ($agg.ContainsKey($k)) { $agg[$k]++ } else { $agg[$k] = 1 }
    }
    if ($nOtherSource -gt 0) { Write-MigrationLog INFO "  [$($Row.Space)] $('{0:N0}' -f $nOtherSource) file(s) at the destination belong to another source mapped in this same job (a shared destination folder) - not counted as extra." }
    if (-not $agg.Count) {
        $alsoNote = if ($nOtherSource -gt 0) { " ($('{0:N0}' -f $nOtherSource) more belong to another source sharing this destination, noted above.)" } else { '' }
        Write-MigrationLog OK "  [$($Row.Space)] every file matches by path, both ways. Nothing extra, nothing missing.$alsoNote"; return ([pscustomobject]@{ Missing = 0; Extra = 0; OtherSource = $nOtherSource })
    }
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
        $rows | Protect-CsvRow | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
        Write-MigrationLog OK "  [$($Row.Space)] difference written (one row per file): $out"
        if ($script:GuiMode) { Write-Host "##CHECKFILES##|$nMissing|$nExtra|0|$out" }
    } catch {
        Write-MigrationLog WARN "  [$($Row.Space)] could not write the difference CSV: $($_.Exception.Message)"
    }
    if ($nMissing) {
        Write-MigrationLog WARN "  [$($Row.Space)] $('{0:N0}' -f $nMissing) file(s) in $($script:SrcNoun) that are NOT at the destination:"
        foreach ($p in @($missingPaths | Select-Object -First 15)) { Write-MigrationLog WARN "      missing: /$p" }
        if ($nMissing -gt 15) { Write-MigrationLog WARN "      ... and $('{0:N0}' -f ($nMissing - 15)) more. Every one is named in the CSV above." }
    }
    if ($nExtra)   { Write-MigrationLog INFO "  [$($Row.Space)] $('{0:N0}' -f $nExtra) file(s) at the destination that are NOT in $($script:SrcNoun) (usually pre-existing content). Biggest folders:" }
    foreach ($r in @($sortedAgg | Where-Object { $_.Side -eq 'AtDestinationOnly' } | Select-Object -First 8)) {
        Write-MigrationLog INFO ("      {0,8:N0}  /{1}" -f $r.Files, $r.Folder)
    }
    return ([pscustomobject]@{ Missing = $nMissing; Extra = $nExtra; OtherSource = $nOtherSource })
}
function Lz3d529cf4da {
    param($Config, [string]$SpaceName, [string]$ResultDir)
    Lz93fa3c46d9 -Config $Config -Stage 'api-destinv'
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
    try { if ((Test-ConfigProp $row 'SourceSubPath')) { $scope = "$($row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
    $co = $false
    try { if ((Test-ConfigProp $row 'SourceContentsOnly')) { $co = ("$($row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
    $doc = [pscustomobject]@{ Version = 1; Space = "$SpaceName"; SourceSubPath = $scope; ContentsOnly = $co
                              Count = [int]$inv.Count; Bytes = [int64]$inv.Bytes; Files = $files }
    $out = Join-Path $ResultDir ("destinv-" + (ConvertTo-Slug $SpaceName) + ".json")
    $doc | ConvertTo-Json -Depth 4 -Compress | Set-Content -Path $out -Encoding UTF8
    Write-MigrationLog OK "  DESTINATION inventory written: $('{0:N0}' -f [int]$inv.Count) file(s). $out"
}
function Lzef890b1d1f {
    param($Config, $Row)
    try {
        $pwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $self = $PSCommandPath
        $slug = ConvertTo-Slug $Row.Space
        $dir = Join-Path $Config.run.stateRoot ("_destinv-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID")
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $q = { param($s)
            $s = "$s"
            if ($s -ne '' -and $s.IndexOfAny(" `t`"".ToCharArray()) -lt 0) { return $s }
            $sb = New-Object System.Text.StringBuilder; [void]$sb.Append('"'); $bs = 0
            foreach ($ch in $s.ToCharArray()) {
                if     ($ch -eq '\') { $bs++ }
                elseif ($ch -eq '"') { [void]$sb.Append('\', ($bs*2+1)); [void]$sb.Append('"'); $bs = 0 }
                else                 { if ($bs) { [void]$sb.Append('\', $bs) }; [void]$sb.Append($ch); $bs = 0 }
            }
            if ($bs) { [void]$sb.Append('\', ($bs*2)) }
            [void]$sb.Append('"'); $sb.ToString()
        }
        $childArgs = @('-NoProfile','-File', (& $q $self),
                       '-ConfigPath', (& $q $script:ConfigPath),
                       '-Action','DestInventory','-Spaces', (& $q $Row.Space),
                       '-ResultDir', (& $q $dir))
        $out = Join-Path $dir "$slug.out.log"
        $err = Join-Path $dir "$slug.err.log"
        $proc = Start-Process -FilePath $pwshExe -ArgumentList $childArgs -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow
        Write-MigrationLog INFO "  Reading the DESTINATION in the background (helper process $($proc.Id)) while the $($script:SrcNounBare) list is read."
        return @{ Process = $proc; File = (Join-Path $dir "destinv-$slug.json"); OutLog = $out; ErrLog = $err; Pos = [long]0; Partial = '' }
    } catch {
        Write-MigrationLog WARN "  could not start the background destination read ($($_.Exception.Message)). The destination will be read after the source instead - slower, same answer."
        return $null
    }
}
function Lze547a12f3f {
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
        Lze547a12f3f -Job $Job
        if ($script:GuiMode -and ([DateTime]::UtcNow - $lastStatus).TotalSeconds -ge 3) {
            $lastStatus = [DateTime]::UtcNow
            Write-Host "##STATUS##|Source: $('{0:N0}' -f $script:SrcTotal) files (done)   ->   Destination: still being read (started in parallel)..."
        }
        Start-Sleep -Milliseconds 400
    }
    Lze547a12f3f -Job $Job
    try {
        if ($Job.Process.ExitCode -ne 0) { throw "the destination child exited $($Job.Process.ExitCode); its log is $($Job.OutLog)" }
        if (-not (Test-Path $Job.File)) { throw "the destination child wrote no result file ($($Job.File))" }
        $doc = Get-Content $Job.File -Raw | ConvertFrom-Json
        if ([int]$doc.Version -ne 1) { throw "result version $($doc.Version) is not 1" }
        if ("$($doc.Space)" -ne "$($Row.Space)") { throw "result is for space '$($doc.Space)', expected '$($Row.Space)'" }
        $scope = ''
        try { if ((Test-ConfigProp $Row 'SourceSubPath')) { $scope = "$($Row.SourceSubPath)".Trim().Trim('/').Trim('\') } } catch {}
        if ("$($doc.SourceSubPath)" -ne $scope) { throw "result scope '$($doc.SourceSubPath)' does not match the row's '$scope'" }
        $co = $false
        try { if ((Test-ConfigProp $Row 'SourceContentsOnly')) { $co = ("$($Row.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$') } } catch {}
        $docCo = $false; if ((Test-ConfigProp $doc 'ContentsOnly')) { $docCo = [bool]$doc.ContentsOnly }
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
        Write-MigrationLog OK "  DESTINATION list received from the background helper: $('{0:N0}' -f [int]$doc.Count) file(s)."
        return @{ Count = [int]$doc.Count; Bytes = [int64]$doc.Bytes; Paths = $paths; Times = $times; Sizes = $sizes }
    } catch {
        Write-MigrationLog WARN "  the background destination list could not be used ($($_.Exception.Message)). Reading the destination directly instead - slower, same answer."
        return (Get-DestinationInventory -Config $Config -Row $Row -WithTimes:$WithTimes)
    }
}
function Invoke-SizeCheck {
    param($Config, [string]$OnlySpace)
    $script:ExcludedFile = $null; Lzc9d8fe4f48
    Lz93fa3c46d9 -Config $Config -Stage 'api-sizecheck'
    $ckStart = Get-Date
    Lz1338c7e606 -Config $Config
    Connect-Destination -Config $Config
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPath)) { Write-MigrationLog ERROR "No mapping.csv found. Set a destination and save the mapping first."; return }
    $map = @(Import-Csv $mapPath | Where-Object Action -eq 'MIGRATE')
    if ($OnlySpace) { $map = @($map | Where-Object { $_.Space -eq $OnlySpace }) }
    if (-not $map.Count) { Write-MigrationLog WARN "No mapped projects to check."; return }
    $tSrcC = 0; $tSrcB = [int64]0; $tDstC = 0; $tDstB = [int64]0; $tMissing = 0; $tExtra = 0; $i = 0; $t = $map.Count
    $scRows = New-Object System.Collections.Generic.List[object]
    $scNotChecked = New-Object System.Collections.Generic.List[object]
    $jobAuditIndex = @{}
    try {
        foreach ($af in @(Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue)) {
            foreach ($ar in @(Import-AuditCsv $af.FullName)) {
                if ("$($ar.Space)" -eq '(run)') { continue }
                if ("$($ar.Status)" -notmatch '^(Copied|ZeroByte|Repaired|Skipped)') { continue }
                $dp = "$($ar.DestPath)".Trim(); if (-not $dp) { continue }
                $jobAuditIndex[$dp.ToLowerInvariant()] = "$($ar.Space)"
            }
        }
    } catch {}
    foreach ($row in $map) {
        $i++; Lz8d39824bd6 -Done $i -Total $t -BytesDone 0 -BytesTotal 0 -Space $row.Space
        Lz883d31a1c9 -Phase 'Compare' -Space "$($row.Space)"
        try {
            $null = Resolve-DestinationDriveId -Config $Config -Row $row
            Write-MigrationLog OK "  destination reachable: $(Get-RowDestLabel $row). Reading the source now."
        } catch {
            Write-MigrationLog ERROR "  destination NOT reachable for [$($row.Space)], so the source was not read: $($_.Exception.Message)"
            $scNotChecked.Add([pscustomobject]@{ Space = $row.Space; Reason = "destination not reachable: $($_.Exception.Message)" })
            continue
        }
        $space = New-SpaceRef -Row $row -Config $Config
        $dj = Lzef890b1d1f -Config $Config -Row $row
        try {
            $items = @(Get-DattoItems -Config $Config -Space $space)
        } catch {
            Write-MigrationLog ERROR "  could not read files for '$($row.Space)': $($_.Exception.Message). In plain terms: the source may be empty, moved, or unreachable. It could NOT be compared, so this check cannot pass."
            $scNotChecked.Add([pscustomobject]@{ Space = $row.Space; Reason = "source not readable: $($_.Exception.Message)" })
            $null = Receive-DestInventoryJob -Config $Config -Row $row -Job $dj
            continue
        }
        $sc = $items.Count
        $sb = Get-SafeSum -Items $items -Property Size
        $inv = Receive-DestInventoryJob -Config $Config -Row $row -Job $dj
        $effD = Join-SubPath $row.TargetSubFolder (Get-NestFolder $Config $row)
        $d = Lz179fcc6c79 -Config $Config -Row $row -Items $items -Inv $inv -EffectivePrefix $effD -JobAuditIndex $jobAuditIndex
        $nMiss = [int]$d.Missing; $nExt = [int]$d.Extra; $nOther = [int]$d.OtherSource
        $dstCountOwn = [Math]::Max(0, [int]$inv.Count - $nOther)
        $dstBytesOwn = $inv.Bytes
        $tSrcC += $sc; $tSrcB += $sb; $tDstC += $dstCountOwn; $tDstB += $dstBytesOwn
        $tMissing += $nMiss; $tExtra += $nExt
        [void]$scRows.Add([pscustomobject]@{ Space = $row.Space; SrcCount = $sc; SrcBytes = $sb; DstCount = $dstCountOwn; DstBytes = $dstBytesOwn; Missing = $nMiss; Extra = $nExt })
        if ($nMiss -gt 0)     { $tag = "destination is MISSING $nMiss file(s)$(if ($nExt) { ", and holds $nExt extra" })"; $lvl = 'WARN' }
        elseif ($nExt -gt 0)  { $tag = "destination has $nExt more (likely pre-existing content)"; $lvl = 'OK' }
        else                  { $tag = 'counts match';                                          $lvl = 'OK' }
        $bytesNote = if ($nOther -gt 0) { " (bytes still include $('{0:N0}' -f $nOther) file(s)' worth from another source sharing this folder - count above is corrected, bytes are not)" } else { '' }
        Write-MigrationLog $lvl ("  [$($row.Space)]  source $sc files / $(Format-Bytes $sb)   ->   destination $dstCountOwn files / $(Format-Bytes $dstBytesOwn)   [$tag]$bytesNote")
    }
    Write-MigrationLog OK ("TOTAL  source $tSrcC files / $(Format-Bytes $tSrcB)    destination $tDstC files / $(Format-Bytes $tDstB)")
    $scUnchecked = $scNotChecked.Count
    if ($scRows.Count -eq 0 -and $scUnchecked -eq 0) { $scNotChecked.Add([pscustomobject]@{ Space = '(none)'; Reason = 'no mapped project could be compared' }); $scUnchecked = 1 }
    $scNcText = (@($scNotChecked | ForEach-Object { "$($_.Space)" }) -join ', ')
    if ($scUnchecked -gt 0) { Write-MigrationLog ERROR "Compare sizes could NOT check $scUnchecked project(s) ($scNcText): the destination could not be reached or the source could not be read, so the totals above leave them out. This is not a match. Fix the source or destination named in the ERROR lines above, then compare again." }
    if ($tMissing -gt 0) {
        Write-MigrationLog WARN "$('{0:N0}' -f $tMissing) file(s) in $($script:SrcNoun) are not at the destination (named above and in the difference CSV), so some files may not have migrated. Click 'Sync new and changed' to copy them, then compare again.$(if ($tExtra) { " The destination also holds $('{0:N0}' -f $tExtra) extra file(s), which is usually pre-existing content." })"
    } elseif ($tExtra -gt 0) {
        Write-MigrationLog INFO "The destination has more files than the source. That is normal if the destination already held content before the migration. To confirm every source file actually arrived, click 'Verify files arrived': it checks file by file and ignores pre-existing extras."
    }
    $byteGap = [int64]$tDstB - [int64]$tSrcB
    if ($byteGap -eq 0) { Write-MigrationLog OK "Byte totals match exactly. 'Verify files arrived' is still the definitive per-file check." }
    else {
        $gapPct = if ($tSrcB -gt 0) { [math]::Round(100.0 * [math]::Abs($byteGap) / $tSrcB, 3) } else { 0 }
        Write-MigrationLog INFO "Byte totals differ by $('{0:N0}' -f [math]::Abs($byteGap)) byte(s) ($gapPct%), the destination being $(if ($byteGap -gt 0) { 'larger' } else { 'smaller' }). That is expected: Microsoft 365 rewrites Office files on upload$(if ($tExtra -gt 0) { ', and the destination holds extra files' }). Treat byte totals as indicative; 'Verify files arrived' is the definitive per-file check."
    }
    try { Write-SizeCheckReport -Config $Config -Rows $scRows -SrcCount $tSrcC -SrcBytes $tSrcB -DstCount $tDstC -DstBytes $tDstB -Missing $tMissing -Extra $tExtra -NotChecked $scNotChecked } catch { Write-MigrationLog WARN "Compare report could not be written: $($_.Exception.Message)" }
    if ($script:GuiMode) {
        if ($scUnchecked -gt 0) { Write-Host "##CHECKOUTCOME##|BAD|could not compare $scUnchecked project(s) ($scNcText): the destination could not be reached or the source could not be read, so this is NOT a match. The reason is in the ERROR lines in the log below. Fix it, then compare again." }
        elseif ($tMissing -gt 0) { Write-Host "##CHECKOUTCOME##|WARN|found a problem: $('{0:N0}' -f $tMissing) file(s) in $($script:SrcNoun) are NOT at the destination, so some files may not have migrated. They are named in the log below and in the difference CSV.$(if ($tExtra) { " (The destination also holds $('{0:N0}' -f $tExtra) extra file(s), usually pre-existing content.)" }) Click 'Sync new and changed' to copy them, then compare again." }
        elseif ($tExtra -gt 0) { Write-Host "##CHECKOUTCOME##|WARN|counts differ: the destination holds $('{0:N0}' -f $tExtra) file(s) that are not in $($script:SrcNoun) ($('{0:N0}' -f $tDstC) vs $('{0:N0}' -f $tSrcC)). That is normal if the destination already held content before the migration - is that expected? 'Verify files arrived' checks file by file and ignores extras." }
        else                   { Write-Host "##CHECKOUTCOME##|OK|every file matches by path: $('{0:N0}' -f $tSrcC) file(s) at both ends." }
    }
    try {
        $emVerdict = if ($scUnchecked -gt 0) { 'BAD' } elseif ($tMissing -gt 0 -or $tExtra -gt 0) { 'WARN' } else { 'OK' }
        $emBucket  = switch ($emVerdict) { 'OK' { 'Success' } 'WARN' { 'Warning' } default { 'Failure' } }
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
                "Could not be compared: $scUnchecked project(s)$(if ($scUnchecked) { " ($scNcText)" })",
                "In $($script:SrcNounBare): $('{0:N0}' -f $tSrcC) file(s)",
                "At the destination: $('{0:N0}' -f $tDstC) file(s)",
                "Missing at destination: $('{0:N0}' -f $tMissing)",
                "Extra at destination: $('{0:N0}' -f $tExtra)",
                "Source: $($emVars['Source'])",
                "Destination: $($emVars['Destination'])")
    } catch {}
}
function Get-SelectionSectionHtml {
    param($Rows, $LeftInPlace = $null, [string[]]$Stale = @(), [string]$Lead = '')
    function _encX { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    if ($null -eq $Rows) { $Rows = @() } else { $Rows = [object[]]$Rows }
    $Stale = @($Stale | Where-Object { $_ })
    if (-not $Rows.Count -and -not $Stale.Count) { return '' }
    $files = @($Rows | Where-Object { "$($_.Kind)" -ne 'Folder' }); $folders = @($Rows | Where-Object { "$($_.Kind)" -eq 'Folder' })
    $bytes = [int64]0; foreach ($r in $files) { try { $bytes += [int64]$r.SizeBytes } catch {} }
    $inPlace = 0
    if ($LeftInPlace) { foreach ($r in $files) { if ($LeftInPlace.Contains("$($r.Space)|$($r.SourcePath)")) { $inPlace++ } } }
    if ($inPlace -eq 0) { $LeftInPlace = $null }
    $sumRows = ''
    foreach ($g in @($Rows | Group-Object Space | Sort-Object Name)) {
        $gf = @($g.Group | Where-Object { "$($_.Kind)" -ne 'Folder' }); $gd = @($g.Group | Where-Object { "$($_.Kind)" -eq 'Folder' })
        $gb = [int64]0; foreach ($r in $gf) { try { $gb += [int64]$r.SizeBytes } catch {} }
        $gp = 0; if ($LeftInPlace) { foreach ($r in $gf) { if ($LeftInPlace.Contains("$($r.Space)|$($r.SourcePath)")) { $gp++ } } }
        $sumRows += "<tr><td class='src'>$(_encX $g.Name)</td><td class='n'>$('{0:N0}' -f $gf.Count)</td><td class='n'>$(Format-Bytes $gb)</td>$(if ($folders.Count) { "<td class='n'>$($gd.Count)</td>" })$(if ($LeftInPlace) { "<td class='n'>$gp</td>" })</tr>`n"
    }
    $list = ''
    foreach ($r in @($Rows | Sort-Object Space, SourcePath | Select-Object -First 200)) {
        $where = if ("$($r.Kind)" -eq 'Folder') { 'whole folder, not listed' } elseif ($LeftInPlace -and $LeftInPlace.Contains("$($r.Space)|$($r.SourcePath)")) { 'already at the destination, left in place' } elseif ($LeftInPlace) { 'never copied' } else { '' }
        $list += "<tr><td class='src'>$(_encX $r.Space)</td><td>$(Format-ReportLeafCell $r.SourcePath)</td><td class='n'>$(if ("$($r.Kind)" -ne 'Folder') { Format-Bytes ([int64]$r.SizeBytes) })</td><td class='dim'>$where</td></tr>`n"
    }
    $html = "<h3 id='selection'>Left out by your selection</h3>"
    $html += "<p class='dim'>$(if ($Lead) { "$(_encX $Lead) " })These were unticked with Edit selection on the $($script:SrcItem). They are not copied, checked or counted anywhere else in this report. Nothing is ever deleted from the destination because of a selection.</p>"
    if ($Rows.Count) {
        $html += "<div class='cards'><div class='card'><div class='v'>$('{0:N0}' -f $files.Count)</div><div class='l'>Files left out</div></div><div class='card'><div class='v'>$(Format-Bytes $bytes)</div><div class='l'>Data left out</div></div>$(if ($folders.Count) { "<div class='card'><div class='v'>$($folders.Count)</div><div class='l'>Folders not listed</div></div>" })$(if ($LeftInPlace) { "<div class='card'><div class='v'>$inPlace</div><div class='l'>Already at destination (left in place)</div></div>" })</div>"
        $html += "<table><thead><tr><th>$($script:SrcItemCap)</th><th class='n'>Files</th><th class='n'>Data</th>$(if ($folders.Count) { "<th class='n'>Folders not listed</th>" })$(if ($LeftInPlace) { "<th class='n'>Left in place</th>" })</tr></thead><tbody>$sumRows</tbody></table>"
        if ($folders.Count) { $html += "<p class='dim'>A folder that is left out entirely, with nothing ticked inside it, is not listed from Datto at all, so its files are not counted.</p>" }
        $html += New-ReportDetails -Summary 'What was left out &middot; click for details' -Rows ([math]::Min(200, $Rows.Count)) -Total $Rows.Count -Csv 'the excluded CSV beside the audit' -Table "<table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th><th></th></tr></thead><tbody>$list</tbody></table>"
    }
    if ($Stale.Count) {
        $html += "<p style='background:#FFF6EC;border:1px solid #F5C083;color:#B5460F;padding:12px 14px;border-radius:8px'><b>$($Stale.Count) selection rule(s) match nothing in the $($script:SrcNounBare).</b> The folder or file may have been renamed, moved or deleted since the selection was saved. A renamed folder you had unticked is now copied under its new name. Open Edit selection on the $($script:SrcItem) to check: $(_encX (($Stale | Select-Object -First 10) -join '; '))$(if ($Stale.Count -gt 10) { ' ...' })</p>"
    }
    return $html
}
function Lz77de606fc0 {
    param([string[]]$Spaces, [hashtable]$Roots = @{})
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($sp in @($Spaces | Select-Object -Unique)) {
        $rules = $script:SelectionRules["$sp"]; if (-not $rules) { continue }
        foreach ($k in $rules.Keys) {
            if ($script:SelRuleHits.Contains("$sp|$k")) { continue }
            $root = if ($Roots.ContainsKey("$sp")) { "$($Roots["$sp"])" } else { '' }
            if ($root) {
                $onDisk = [System.IO.Path]::Combine($root, ($k -replace '/', [string][System.IO.Path]::DirectorySeparatorChar))
                if (Test-Path -LiteralPath $onDisk) { continue }
            }
            $out.Add("${sp}: /$k ($(if ($rules[$k] -eq 'x') { 'left out' } else { 'ticked' }))")
        }
    }
    return $out.ToArray()
}
function Lzab15d9452a {
    param($Config,[string]$Subtitle,[string]$Banner,[string]$Body)
    function _encS { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    $brand = 'Liscaragh Migrate'
    if (((Test-ConfigProp $Config.run 'report')) -and ((Test-ConfigProp $Config.run.report 'brand')) -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
    $now = Get-Date
    $tv = Lzb0b39673dd; $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    return @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_encS $brand) - $(_encS $Subtitle)</title>
$(Get-ReportStyle)
</head><body><div class='wrap'>
<header>$(Get-BrandLogoTag -Config $Config)<div><h1>$(_encS (Get-ReportHeaderTitle $brand))</h1><div class='sub'>$(_encS $Subtitle) &middot; generated $($now.ToString('dd MMM yyyy HH:mm'))$verSub$(Get-ReportClientSub $Config)</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
$Banner
$Body
<h2>Check details</h2>
<table style='width:auto'><tbody><tr><td>Run by</td><td>$(_encS $(if ("$env:USERNAME".Trim()) { "$env:USERNAME$(if ("$env:COMPUTERNAME".Trim()) { " on $env:COMPUTERNAME" })" } else { '-' }))</td></tr><tr><td>App version</td><td>$(_encS "$tv")</td></tr><tr><td>Generated</td><td>$($now.ToString('dd MMM yyyy HH:mm:ss'))</td></tr></tbody></table>
<footer>Source: $(_encS $script:SrcSysName) &middot; This is a read-only check: nothing was uploaded or changed &middot; $(_encS (Get-ReportTimeNote)) &middot; Liscaragh Migrate &middot; Liscaragh Software &middot; www.liscaragh.com</footer>
</div>
$(Get-ReportPrintScript)
</body></html>
"@
}
function Lz8693f3210b {
    param($Config)
    $ctx = [pscustomobject]@{ Status = ''; When = ''; Unfinished = $false; Word = 'did not finish' }
    try {
        $lrp = Join-Path $Config.run.reportRoot 'lastrun-outcome.json'
        if (-not (Test-Path $lrp)) { return $ctx }
        $lastRun = Get-Content $lrp -Raw | ConvertFrom-Json
        $ctx.Status = "$($lastRun.Status)"
        if ((Test-ConfigProp $lastRun 'EndUtc') -and "$($lastRun.EndUtc)") {
            $eu = $lastRun.EndUtc
            $euDt = if ($eu -is [datetime]) { $eu } else { [datetime]::Parse("$eu", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) }
            $ctx.When = $euDt.ToLocalTime().ToString('dd MMM yyyy HH:mm')
        }
    } catch {}
    $ctx.Unfinished = @('CANCELLED','ENDED_EARLY','INCOMPLETE','CAPPED') -contains $ctx.Status
    $ctx.Word = switch ($ctx.Status) { 'CANCELLED' { 'was cancelled' } 'CAPPED' { 'stopped at the evaluation limit' } default { 'did not finish' } }
    return $ctx
}
function Write-ValidationReport {
    param($Config,$Report,$Missing,$Stale,$NotChecked)
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    if ($null -eq $NotChecked) { $NotChecked = @() } else { $NotChecked = [object[]]$NotChecked }
    if ($null -eq $Report)  { $Report = @() }  else { $Report = [object[]]$Report }
    if ($null -eq $Missing) { $Missing = @() } else { $Missing = [object[]]$Missing }
    if ($null -eq $Stale)   { $Stale = @() }   else { $Stale = [object[]]$Stale }
    $fail   = @($Report | Where-Object Verdict -eq 'FAIL').Count
    $stalep = @($Report | Where-Object Verdict -eq 'OUT OF DATE').Count
    $projCount = $Report.Count
    $lrc = Lz8693f3210b -Config $Config
    $lastStatus = $lrc.Status; $lastWhen = $lrc.When; $lastUnfinished = $lrc.Unfinished; $lastWord = $lrc.Word
    $missBytes = [int64]0; foreach ($m in $Missing) { try { if ((Test-ConfigProp $m 'SizeBytes')) { $missBytes += [int64]$m.SizeBytes } } catch {} }
    $srcTotal  = Get-SafeSum -Items (@($Report | ForEach-Object { [int64]$_.SourceFiles }))
    $missTotal = $Missing.Count
    $staleTotal = $Stale.Count
    if ($NotChecked.Count) { $bStyle='background:#FEF3F2;border:1px solid #FDA29B;color:#B42318'; $bTitle='This check could not be completed.'; $bExtra=" $($NotChecked.Count) $($script:SrcItem)(s) could not be checked because the destination could not be reached or the source could not be read, so this is not a pass. They are listed below.$(if ($fail -gt 0) { " Separately, $missTotal file(s) are missing across $fail $($script:SrcItem)(s)." })" }
    elseif ($fail -gt 0 -and $lastUnfinished) { $bStyle='background:#FFF6EC;border:1px solid #F5C083;color:#B5460F'; $bTitle='Not finished yet: some files are still to be copied.'; $bExtra=" $missTotal file(s) ($(Format-Bytes $missBytes)) in $($script:SrcNounBare) are not at the destination yet, across $fail $($script:SrcItem)(s). That is expected: the last upload$(if ($lastWhen) { " ($lastWhen)" }) $lastWord. Run 'Sync new and changed' to finish, then verify again." }
    elseif ($fail -gt 0)   { $bStyle='background:#FEF3F2;border:1px solid #FDA29B;color:#B42318'; $bTitle='Some files are missing.'; $bExtra=" $missTotal file(s) ($(Format-Bytes $missBytes)) in $($script:SrcNounBare) are not at the destination across $fail $($script:SrcItem)(s). Run 'Sync new and changed', then verify again." }
    elseif ($stalep -gt 0) { $bStyle='background:#FFFAEB;border:1px solid #FEDF89;color:#B5460F'; $bTitle='Everything is present, some are out of date.'; $bExtra=" $staleTotal file(s) are newer in $($script:SrcNounBare) than at the destination. Run 'Sync new and changed' with 'Update where $($script:SrcNounBare) is newer' to refresh them." }
    else                   { $bStyle='background:#E7F7EF;border:1px solid #86D9B4;color:#066A4B'; $bTitle="All $('{0:N0}' -f $srcTotal) selected file(s) are present at the destination."; $bExtra=" None is newer in $($script:SrcNounBare) than at the destination. Contents were not compared: this check is by path and modified time (each file's size was checked when it was uploaded). Files already at the destination that did not come from this source were ignored." }
    $banner = "<div style='$bStyle;border-radius:8px;padding:14px 16px;margin:0 0 18px;font-size:14px'><strong>$(_enc $bTitle)</strong>$(_enc $bExtra)</div>"
    $rows=''
    foreach ($r in $Report) {
        $vShow = "$($r.Verdict)"; if ($vShow -eq 'FAIL' -and $lastUnfinished) { $vShow = 'INCOMPLETE' }
        $vc = switch ($vShow) { 'FAIL' {'err'} 'NOT CHECKED' {'err'} 'OUT OF DATE' {'warnc'} 'INCOMPLETE' {'warnc'} default {'dim'} }
        $rows += "<tr><td class='src'>$(_enc $r.Space)</td><td class='n'>$('{0:N0}' -f [int64]$r.SourceFiles)</td><td class='n'>$('{0:N0}' -f [int64]$r.Present)</td><td class='n'>$('{0:N0}' -f [int64]$r.Missing)</td><td class='n'>$('{0:N0}' -f [int64]$r.OutOfDate)</td><td class='n'>$('{0:N0}' -f [int64]$r.ExtraAtDest)</td><td class='$vc st'>$(_enc $vShow)</td></tr>`n"
    }
    if ($missTotal) {
        $fr = ''
        foreach ($sg in @($Missing | Group-Object Space | Sort-Object Name)) {
            $srcRow = @($Report | Where-Object { "$($_.Space)" -eq "$($sg.Name)" }) | Select-Object -First 1
            $sgBytes = [int64]0; foreach ($m in $sg.Group) { try { $sgBytes += [int64]$m.SizeBytes } catch {} }
            if ($srcRow -and [int]$srcRow.Present -eq 0) {
                $fr += "<tr><td class='src'>$(_enc $sg.Name)</td><td class='dim'>everything (nothing from this $($script:SrcItem) is at the destination yet)</td><td class='n'>$('{0:N0}' -f $sg.Count)</td><td class='n'>$(Format-Bytes $sgBytes)</td></tr>`n"
                continue
            }
            $byFolder = @($sg.Group | Group-Object { $d = Split-Path ("$($_.MissingFile)" -replace '\\','/') -Parent; if ($d) { ($d -replace '\\','/') } else { '(top level)' } } | Sort-Object Count -Descending)
            foreach ($fg in @($byFolder | Select-Object -First 10)) {
                $fgBytes = [int64]0; foreach ($m in $fg.Group) { try { $fgBytes += [int64]$m.SizeBytes } catch {} }
                $fr += "<tr><td class='src'>$(_enc $sg.Name)</td><td>$(_enc $fg.Name)</td><td class='n'>$('{0:N0}' -f $fg.Count)</td><td class='n'>$(Format-Bytes $fgBytes)</td></tr>`n"
            }
            if ($byFolder.Count -gt 10) { $fr += "<tr><td class='src'>$(_enc $sg.Name)</td><td class='dim'>$($byFolder.Count - 10) more folder(s)</td><td class='n'></td><td class='n'></td></tr>`n" }
        }
        $mr=''; foreach ($m in @($Missing | Select-Object -First 200)) { $msz = ''; try { if ((Test-ConfigProp $m 'SizeBytes')) { $msz = Format-Bytes ([int64]$m.SizeBytes) } } catch {}; $mr += "<tr><td class='src'>$(_enc $m.Space)</td><td>$(Format-ReportLeafCell $m.MissingFile)</td><td class='n'>$msz</td></tr>`n" }
        $capTxt = if ($missTotal -gt 200) { "Showing the first 200 of $missTotal; all are in api-validation-missing.csv in this job's reports folder." } else { "All are also in api-validation-missing.csv in this job's reports folder." }
        $missSec = "<h3>Missing files ($('{0:N0}' -f $missTotal), $(Format-Bytes $missBytes))</h3><table><thead><tr><th>$($script:SrcItemCap)</th><th>Folder</th><th class='n'>Files</th><th class='n'>Data</th></tr></thead><tbody>$fr</tbody></table><details><summary>File list &middot; click for details</summary><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th></tr></thead><tbody>$mr</tbody></table></details><p class='dim'>$capTxt</p>"
    } elseif ($NotChecked.Count) { $missSec = '' }
    else { $missSec = '' }
    $ncSec = ''
    if ($NotChecked.Count) {
        $nr=''; foreach ($n in $NotChecked) { $nr += "<tr><td>$(_enc $n.Space)</td><td>$(_enc $n.Reason)</td></tr>`n" }
        $ncSec = "<h3>Could not be checked ($($NotChecked.Count))</h3><table><thead><tr><th>$($script:SrcItemCap)</th><th>Why</th></tr></thead><tbody>$nr</tbody></table>"
    }
    if ($staleTotal) {
        $sr=''; foreach ($s in @($Stale | Select-Object -First 500)) { $sr += "<tr><td class='src'>$(_enc $s.Space)</td><td>$(Format-ReportLeafCell $s.StaleFile)</td></tr>`n" }
        $cap2 = if ($staleTotal -gt 500) { "<p class='dim'>Showing the first 500 of $staleTotal; all are in api-validation-stale.csv.</p>" } else { '' }
        $staleSec = "<h3>Newer at the source ($('{0:N0}' -f $staleTotal))</h3><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th></tr></thead><tbody>$sr</tbody></table>$cap2"
    } else { $staleSec = '' }
    $body = @"
<div class='cards'>
 <div class='card'><div class='v'>$('{0:N0}' -f $srcTotal)</div><div class='l'>Files checked</div></div>
 <div class='card'><div class='v'>$('{0:N0}' -f ($srcTotal - $missTotal))</div><div class='l'>Present</div></div>
 <div class='card'><div class='v $(if($missTotal -gt 0){'err'})'>$('{0:N0}' -f $missTotal)</div><div class='l'>Missing</div></div>
 <div class='card'><div class='v $(if($staleTotal -gt 0){'warnc'})'>$('{0:N0}' -f $staleTotal)</div><div class='l'>Newer at source</div></div>
</div>
<div class='cards sec'><div class='card'><div class='v'>$projCount</div><div class='l'>$($script:SrcItemCap)s checked</div></div>$(if ($script:SelExcluded.Count) { "<div class='card'><div class='v'>$(Format-SelLeftOutCount $script:SelExcluded)</div><div class='l'>Left out by your selection</div></div>" })</div>
<h2 id='action'>Action required</h2>
$(if ($NotChecked.Count) { "<div class='action todo'><ul><li>$($NotChecked.Count) $($script:SrcItem)(s) could not be checked; fix the reason listed below, then verify again.</li></ul></div>" } elseif ($missTotal -gt 0) { "<div class='action todo'><ul><li>Run 'Sync new and changed' to copy the $('{0:N0}' -f $missTotal) missing file(s), then verify again.</li></ul></div>" } elseif ($staleTotal -gt 0) { "<div class='action todo'><ul><li>Run 'Sync new and changed' with 'Update where $($script:SrcNounBare) is newer' to refresh $('{0:N0}' -f $staleTotal) file(s).</li></ul></div>" } else { "<div class='action none'><b>No action required.</b></div>" })
<h2>Results by $($script:SrcItem)</h2>
<table><thead><tr><th>$($script:SrcItemCap)</th><th class='n'>Files at source</th><th class='n'>Present</th><th class='n'>Missing</th><th class='n'>Out of date</th><th class='n'>Extra at dest</th><th>Verdict</th></tr></thead><tbody>
$rows
</tbody></table>
<p class='dim'><b>How this is checked:</b> a file is <b>present</b> when a file with the same path (after the same name tidying the upload applies) exists at the destination. It is <b>out of date</b> when the $($script:SrcNounBare) copy was modified after the destination copy. Sizes and contents are not compared here; each file's size is checked against the source when it is uploaded. <b>Extra at dest</b> counts files at the destination that did not come from this $($script:SrcItem), usually content that was already there.</p>
$(Get-SelectionSectionHtml -Rows $script:SelExcluded.ToArray() -Lead 'They were not checked, so they are not counted as missing.')
$(if ($ncSec -or $missTotal -or $staleSec) { "<h2 id='exceptions'>Exceptions</h2>" })
$ncSec
$missSec
$staleSec
"@
    $html = Lzab15d9452a -Config $Config -Subtitle 'Verify files arrived (per-file check)' -Banner $banner -Body $body
    $outPath = Join-Path $Config.run.reportRoot ("report-validation-" + (Get-Date).ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "Verify report written: $outPath"
}
function Write-SizeCheckReport {
    param($Config,$Rows,[int]$SrcCount,[int64]$SrcBytes,[int]$DstCount,[int64]$DstBytes,[int]$Missing,[int]$Extra,$NotChecked)
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    if ($null -eq $Rows) { $Rows = @() } else { $Rows = [object[]]$Rows }
    if ($null -eq $NotChecked) { $NotChecked = @() } else { $NotChecked = [object[]]$NotChecked }
    if ($NotChecked.Count) { $bStyle='background:#FEF3F2;border:1px solid #FDA29B;color:#B42318'; $bTitle='This comparison could not be completed.'; $bExtra=" $($NotChecked.Count) $($script:SrcItem)(s) could not be compared because the destination could not be reached or the source could not be read, so the totals leave them out and this is not a match. They are listed below." }
    $lrc = Lz8693f3210b -Config $Config
    $whyMissing = if ($lrc.Unfinished) { " That is expected: the last upload$(if ($lrc.When) { " ($($lrc.When))" }) $($lrc.Word)." } else { '' }
    if ($NotChecked.Count) { }
    elseif ($Missing -gt 0 -and $lrc.Unfinished) { $bStyle='background:#FFF6EC;border:1px solid #F5C083;color:#B5460F'; $bTitle='Not finished yet: some files are still to be copied.'; $bExtra=" $Missing file(s) in $($script:SrcNounBare) are not at the destination yet.$whyMissing Run 'Sync new and changed' to finish, then compare again.$(if($Extra){" The destination also holds $Extra extra file(s), usually pre-existing content."})" }
    elseif ($Missing -gt 0)   { $bStyle='background:#FFFAEB;border:1px solid #FEDF89;color:#B5460F'; $bTitle='Some files are missing at the destination.'; $bExtra=" $Missing file(s) in $($script:SrcNounBare) are not at the destination. Run 'Sync new and changed', then compare again.$(if($Extra){" The destination also holds $Extra extra file(s), usually pre-existing content."})" }
    elseif ($Extra -gt 0) { $bStyle='background:#FFFAEB;border:1px solid #FEDF89;color:#B5460F'; $bTitle='The destination holds extra files.'; $bExtra=" $Extra file(s) at the destination are not in $($script:SrcNounBare), usually content that was there before the migration. 'Verify files arrived' checks file by file and ignores extras." }
    else                  { $bStyle='background:#E7F7EF;border:1px solid #86D9B4;color:#066A4B'; $bTitle='File counts match.'; $bExtra=" $('{0:N0}' -f [int64]$SrcCount) file(s) at both ends." }
    $banner = "<div style='$bStyle;border-radius:8px;padding:14px 16px;margin:0 0 18px;font-size:14px'><strong>$(_enc $bTitle)</strong>$(_enc $bExtra)</div>"
    $rowHtml=''
    foreach ($r in $Rows) {
        $mc = if ([int]$r.Missing -gt 0) { 'err' } elseif ([int]$r.Extra -gt 0) { 'warnc' } else { 'dim' }
        $rowHtml += "<tr><td class='src'>$(_enc $r.Space)</td><td class='n'>$('{0:N0}' -f [int64]$r.SrcCount)</td><td class='n'>$(Format-Bytes ([int64]$r.SrcBytes))</td><td class='n'>$('{0:N0}' -f [int64]$r.DstCount)</td><td class='n'>$(Format-Bytes ([int64]$r.DstBytes))</td><td class='n $(if([int]$r.Missing -gt 0){'err'})'>$('{0:N0}' -f [int64]$r.Missing)</td><td class='n $mc'>$('{0:N0}' -f [int64]$r.Extra)</td></tr>`n"
    }
    $body = @"
<div class='cards'>
 <div class='card'><div class='v'>$('{0:N0}' -f [int64]$SrcCount)</div><div class='l'>In $($script:SrcNounBare)</div></div>
 <div class='card'><div class='v'>$('{0:N0}' -f [int64]$DstCount)</div><div class='l'>At destination</div></div>
 <div class='card'><div class='v $(if($Missing -gt 0){'err'})'>$('{0:N0}' -f [int64]$Missing)</div><div class='l'>Missing at dest</div></div>
 <div class='card'><div class='v'>$('{0:N0}' -f [int64]$Extra)</div><div class='l'>Extra at dest</div></div>
</div>
<h2>By $($script:SrcItem)</h2>
<table><thead><tr><th>$($script:SrcItemCap)</th><th class='n'>$($script:SrcItemCap) files</th><th class='n'>$($script:SrcItemCap) data</th><th class='n'>Dest files</th><th class='n'>Dest data</th><th class='n'>Missing</th><th class='n'>Extra</th></tr></thead><tbody>
$rowHtml
</tbody></table>
$(if ($NotChecked.Count) { "<h2>Could not be compared ($($NotChecked.Count))</h2><table><thead><tr><th>$($script:SrcItemCap)</th><th>Why</th></tr></thead><tbody>" + (@($NotChecked | ForEach-Object { "<tr><td>$(_enc $_.Space)</td><td>$(_enc $_.Reason)</td></tr>" }) -join "`n") + "</tbody></table>" })
$(Get-SelectionSectionHtml -Rows $script:SelExcluded.ToArray() -Lead 'The source totals above leave them out.')
<p class='dim'>$(if ($Missing -gt 0) { "The data totals differ mainly because $Missing file(s) are not at the destination yet. " })Even when every file is there, the byte totals can differ slightly because Microsoft 365 rewrites Office files on upload, so treat them as indicative. 'Verify files arrived' is the definitive per-file check.</p>
"@
    $html = Lzab15d9452a -Config $Config -Subtitle 'Compare sizes (count and byte overview)' -Banner $banner -Body $body
    $outPath = Join-Path $Config.run.reportRoot ("report-sizecheck-" + (Get-Date).ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "Compare report written: $outPath"
}
$script:BrandLogoWarned = $false
function Get-ReportStyle {
    return @'
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .wrap{max-width:960px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:32px}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:16px;margin-bottom:24px}
 .logo{height:48px;margin-right:16px}
 .brandlogo{height:78px;border-radius:8px;margin-left:auto}
 h1{font-size:20px;margin:0}
 .sub{color:#6b7280;font-size:13px;margin-top:2px}
 h2{font-size:16px;margin:30px 0 10px;color:#111827;border-bottom:1px solid #eef2f7;padding-bottom:4px}
 h3{font-size:14px;margin:20px 0 8px;color:#111827}
 .cards{display:flex;flex-wrap:wrap;gap:12px;margin:8px 0 4px}
 .card{flex:1;min-width:120px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:12px 14px}
 .card .v{font-size:22px;font-weight:600}
 .card .l{font-size:12px;color:#6b7280;margin-top:2px}
 .cards.sec{margin-top:6px;flex-wrap:nowrap}
 .cards.sec .card{min-width:0}
 .cards.sec .card{background:#fff;padding:7px 12px}
 .cards.sec .card .v{font-size:14px}
 .cards.sec .card .l{font-size:11px}
 table{width:100%;border-collapse:collapse;font-size:13px;margin-top:6px}
 th,td{text-align:left;padding:7px 10px;border-bottom:1px solid #eef2f7;overflow-wrap:anywhere;word-break:break-word;vertical-align:top}
 th{background:#f3f4f6;font-weight:600;white-space:nowrap}
 td.n,th.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
 td.st{white-space:nowrap}
 td.src{word-break:normal;overflow-wrap:normal}
 .fn{font-weight:600;color:#111827}
 .fp{color:#6b7280;font-size:11px;margin-top:1px}
 .err{color:#B42318;font-weight:600}
 .warnc{color:#B5460F;font-weight:600}
 .dim{color:#6b7280}
 .okbox{background:#E7F7EF;border:1px solid #A6E9C5;color:#066A4B;padding:12px 14px;border-radius:8px}
 .warnbox{background:#FFF6EC;border:1px solid #F5C083;color:#B5460F;padding:12px 14px;border-radius:8px}
 .action{border-radius:8px;padding:12px 16px;margin:8px 0}
 .action.none{background:#E7F7EF;border:1px solid #A6E9C5;color:#066A4B}
 .action.todo{background:#FFF6EC;border:1px solid #F5C083;color:#7A2E0E}
 .action ul{margin:6px 0 0 18px;padding:0}
 .action li{margin:3px 0}
 .count{color:#6b7280;font-size:12px;margin:6px 0 2px}
 .tblwrap{max-height:520px;overflow:auto;border:1px solid #eef2f7;border-radius:6px;margin-top:6px}
 .tblwrap table{margin-top:0}
 .tblwrap th{position:sticky;top:0;z-index:1}
 details{margin:6px 0;border:1px solid #e5e7eb;border-radius:8px;padding:8px 12px;background:#fff}
 summary{cursor:pointer;font-weight:600;font-size:13px;color:#111827}
 details table{margin-top:8px}
 .diag{background:#EDF3F8;border:1px solid #BBD3E4;border-radius:8px;padding:14px 16px}
 .diag .dv{font-size:16px;font-weight:700;color:#1C6091;margin-bottom:4px}
 .diag table{width:auto;margin-top:8px}
 .diag td{border-bottom:1px solid #DBE7F1;padding:5px 10px}
 .toc{margin:0 0 14px;color:#6b7280;font-size:13px}
 footer{margin-top:28px;color:#9ca3af;font-size:12px;border-top:1px solid #e5e7eb;padding-top:12px}
 @media print{
  body{background:#fff;padding:0}.wrap{border:none;padding:0}
  .tblwrap{max-height:none!important;overflow:visible!important;border:none}
  .tblwrap th{position:static}
  details[data-big]:not([open]) > summary::after{content:' (not printed: the full list is in the CSV named below it)';font-weight:400;color:#6b7280}
  .toc{display:none}
  h2,h3{break-after:avoid;page-break-after:avoid}
  tr{break-inside:avoid}
 }
</style>
'@
}
function Get-ReportPrintScript {
    return "<script>(function(){var o=[];window.addEventListener('beforeprint',function(){document.querySelectorAll('details').forEach(function(d){if(!d.open&&!d.hasAttribute('data-big')){d.open=true;o.push(d);}});});window.addEventListener('afterprint',function(){o.forEach(function(d){d.open=false;});o=[];});})();</script>"
}
function New-ReportDetails {
    param([string]$Summary, [string]$Table, [int]$Rows = 0, [int]$Total = -1, [string]$Csv = '', [switch]$Open)
    if ($Total -lt 0) { $Total = $Rows }
    $cnt = if ($Total -gt $Rows) { "Showing $('{0:N0}' -f $Rows) of $('{0:N0}' -f $Total).$(if ($Csv) { " All are in $Csv." })" } elseif ($Csv) { "All $('{0:N0}' -f $Total) are also in $Csv." } else { '' }
    $big = if ($Rows -gt 50) { ' data-big' } else { '' }
    return "<details$big$(if ($Open) { ' open' })><summary>$Summary</summary>$(if ($cnt) { "<p class='count'>$cnt</p>" })<div class='tblwrap'>$Table</div></details>"
}
function Get-ReportTimeNote {
    try {
        $tz = [System.TimeZoneInfo]::Local; $off = $tz.GetUtcOffset([datetime]::Now)
        $sign = if ($off -lt [TimeSpan]::Zero) { '-' } else { '+' }
        return "Times are local to the computer that produced this report ($($tz.Id), UTC$sign$($off.Duration().ToString('hh\:mm')))."
    } catch { return 'Times are local to the computer that produced this report.' }
}
function Format-ReportLeafCell {
    param([string]$Path)
    $p = "$Path" -replace '\\','/'
    $i = $p.LastIndexOf('/')
    $enc = { param($x) [System.Net.WebUtility]::HtmlEncode("$x") }
    if ($i -lt 0) { return "<div class='fn'>$(& $enc $p)</div>" }
    return "<div class='fn'>$(& $enc $p.Substring($i + 1))</div><div class='fp'>$(& $enc $p.Substring(0, $i + 1))</div>"
}
function Get-ReportClientSub {
    param($Config)
    try { if ((Test-ConfigProp $Config.run 'report') -and (Test-ConfigProp $Config.run.report 'client') -and "$($Config.run.report.client)".Trim()) { return " &middot; prepared for " + [System.Net.WebUtility]::HtmlEncode("$($Config.run.report.client)".Trim()) } } catch {}
    return ''
}
function Get-BrandLogoTag {
    param($Config, [string]$Class = 'logo')
    try {
        if (-not (Test-ConfigProp $Config.run 'report')) { return '' }
        if (-not (Test-ConfigProp $Config.run.report 'logo')) { return '' }
        $p = "$($Config.run.report.logo)".Trim()
        if (-not $p) { return '' }
        if (-not (Test-Path -LiteralPath $p)) {
            if (-not $script:BrandLogoWarned) {
                $script:BrandLogoWarned = $true
                Write-MigrationLog WARN "White-label logo not found at [$p], so this report carries no client logo. Set a valid path under Settings > Reports, or clear the setting."
            }
            return ''
        }
        $lb = [System.IO.File]::ReadAllBytes($p)
        $mime = Get-ImageMimeType -Bytes $lb
        if (-not $mime) {
            if (-not $script:BrandLogoWarned) {
                $script:BrandLogoWarned = $true
                Write-MigrationLog WARN "White-label logo [$p] is not an image file (its first bytes match no known image format), so it was NOT embedded. Embedding it would put a broken-image icon on the report."
            }
            return ''
        }
        $altName = ''
        if ((Test-ConfigProp $Config.run.report 'client')) { $altName = "$($Config.run.report.client)".Trim() }
        if (-not $altName -and (Test-ConfigProp $Config.run.report 'brand')) { $altName = "$($Config.run.report.brand)".Trim() }
        $alt = if ($altName) { "$altName logo" } else { 'logo' }
        return "<img class='$Class' alt='$([System.Net.WebUtility]::HtmlEncode($alt))' src='data:$mime;base64,$([Convert]::ToBase64String($lb))' />"
    } catch {
        if (-not $script:BrandLogoWarned) {
            $script:BrandLogoWarned = $true
            try { Write-MigrationLog WARN "White-label logo could not be read: $($_.Exception.Message). The report carries no client logo." } catch {}
        }
        return ''
    }
}
function Get-ImageMimeType {
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -lt 4) { return $null }
    $b = $Bytes
    if ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'image/png' }
    if ($b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF)                     { return 'image/jpeg' }
    if ($b[0] -eq 0x47 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x38) { return 'image/gif' }
    if ($b[0] -eq 0x42 -and $b[1] -eq 0x4D)                                         { return 'image/bmp' }
    if ($b.Length -ge 12 -and $b[0] -eq 0x52 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x46 -and
        $b[8] -eq 0x57 -and $b[9] -eq 0x45 -and $b[10] -eq 0x42 -and $b[11] -eq 0x50) { return 'image/webp' }
    $head = ''
    try { $head = [Text.Encoding]::UTF8.GetString($b, 0, [Math]::Min(256, $b.Length)) } catch {}
    if ($head -match '(?is)^\s*(<\?xml[^>]*>\s*)?(<!--.*?-->\s*)*<svg\b') { return 'image/svg+xml' }
    return $null
}
$script:LiscaraghLogoB64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEBAQFBQQFBwsHBwYGBw4KCggLEA4RERAOEA8SFBoWEhMYEw8QFh8XGBsbHR0dERYgIh8cIhocHRz/2wBDAQUFBQcGBw0HBw0cEhASHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBz/wAARCACnANwDASIAAhEBAxEB/8QAHQABAQADAAMBAQAAAAAAAAAAAAEGBwgCBQkEA//EAE4QAAECBQIEAwIICgcECwAAAAECAwAEBQYRBxIIITFBE1FhIoEUGSMyVnGU0gkVFkJSVHKRk9EXGDVDgpXTRGJ0sjc4Y3N1kqGisbO0/8QAGwEBAAIDAQEAAAAAAAAAAAAAAAIDBAUGAQf/xAAvEQACAgECBAQGAQUBAAAAAAAAAQIDEQQhBRIxUUFhgZEGExQiMnFyQmKhscHx/9oADAMBAAIRAxEAPwD5/wAIQgBFiResAWEQQxACGYGEAMwiQgBFiQgBCEWAEMQi+6AJiGIQgBFiQgAYCLEgBFhEgCx4xYkAIsSLAEhCEAIsMQgBCESALCEIARIQgBCEXEAMZPKLgx3JwWcLVBvy26jel+0dNQpk4oy1KlHVrQlQSr5R/wBkgn2hsTz7L5dI/fxlWDo5ozZUrTLds2QYvCuKxLuB95SpVhJHiO4KyMk4QnI7qP5sAcdac2O7fVe+BeKWZNhHizLyRkpRnGB/vE8h+/tHRDej9mNyfwY0ZKxjBdU8vxD67s9fdGCcM1Nqc4/dczK0596nyksy7NTKE5Qx8oQkK+vJ/wDKT0Eb0Mcdx3W6mvU/LhJxiksY2yfQvhnh+kt0fzZwUpNvOd8eX/TkvVHT42JVmRLurepk4Cpha/nJI+chXmRkc+4MYHG9OIiuSrzlJozS0rmpcrfeA/u9wASk+pAJx9UaLjo+GW2XaWE7erOQ4zRTRrbK6PxT9tt16MZhFiGM41ghAQzzgBCJ3iwAiRe8SALiHuhD3wBIQhACLEiwAhDOId4ARIsSAEIQgCxn+jGl1R1i1Eo9qU/chM0vfNTCRkS0unm44fqHIeaikd4wDEfVLgb0R/o407/Kqqy3h3FdCEPbVpwqXlOrSPQqzvP1pB+bAHQyE0DS6xgkFqm23b0h1PzWWGkf+pwPrJ9THxv1k1LquuOqFSuF1p5RnnhL0+SHtKZYB2tNADqrnk46qUT3jsD8INreJeWldLqPM/KvhE5WFIPzUdWWD9Zw4R5BHmY1/wABGiH5X3i7qBV5bdR7dc2SSVp9l6dxkK9Q2khX7SkeRgDtDhq0WltGNLJCiTDLaq1PD4XVnMA731jm36pQnCB2OCe8cLcXGr0pJanz1u6fpYpcjSQZaemJNIHwmaz7YHUJCPmezj2gr0jt7io1qRorpdOz0o8lNx1TMlS0d0uke07jybT7Xlu2jvHx1ddW+6t11aluLJUpazkqJ6knuYrsqrs/OKf7RbVfbTn5cnHPZ4Dzzsy6t55xTjqyVKWsklRPck9Y8IsTMWFT3EDCGIAkIRcZgCCLDvCAHeJFhAAQhDlAEhCLAEixIQAhCEAIQhACEI/tKyz07MNS0u0t195YQ22gZUtROAAO5J5QBvbhJ0UVrJqjKtz0uXLZom2dqZI9lwA/Js/41DBH6KVx9StWNR6XpFp7WLpqW3waez8jLg4Mw8eTbSf2lYHoMntGJ8M2jLOiel1PpDzaPx9OYnKq6nnufUB7APdKBhA+onvHD/Hfrd+Xd+IsmkzO+g2y4pL5QrKX50jCz6hsZQPUr84A58lJe5tcdT0NBSp65rnqGSo/N3rOST+ihIyfIJT6R9ltNrEpGktgUi2aaUNyFKl8LfXhPir+c46s9ipRUo+WfIRyP+D80PNLpczqdWJfE1UEqlaQhY5oYzhx4ftkbQf0Uq7KjLePDXD8hbGRY9JmNteuZtQmFIV7UvJZws+hcOUD0C/SAOLOKfWpzWrVCdnpV5Rtyl7pKlI7FoH2ncebiva88bR2jSIh1hADEWJH66fTJyrTSJWQlXpqZX81tlBUo+4R42kss9ScnhdT8ggY99WLLuCgMB+pUiclmD/eONnaPrI5CPRHIjyE4zWYvKJWVzrfLNNPzJiJzixYkQJCGYQA7xIuecIAQiRfdAEhCEAIQhACEIQAhCEAI7I4B9EfyvvN6/6tLbqNbrm2SCx7L06RkH1DaSFftKR5GOVLLtKp33dVItujM+NU6pMIl2UdgSeaj5JAyonsATH2v02sOkaS2BSLZppQ3IUqXwt9eE+Kv5zjqz5qUVKPl9QgDAeKnWlGiuls7PSjyU3HVMyVLRnml0j2nceTafa8t20d4+X+helVQ1u1Ppdutrd+DvLMzUpvqpmWSQXFk/pHISM9VKEZBxS60ua1aozs/KuqVbtM3SVKR2LQPtO483Fe1542jtHrNGeIa6NC2qoLXkKIt+plHjzM9Kqdd2pztQCFpwnJJx3J9BgD7LUikydCpUlS6dLolpCSZRLsMNjCW20gJSkegAAjSOoXCHp5qfdk/c9xqrczVJ3aFFNQKUISlISlKE7fZSAOnqT3jiz4wrVv9Vtj7A5/qw+MK1a/VbY+wOf6sAdWf1BNH/1auf5kfuw/qCaP/q1c/wAyP3Y5T+MK1a/VbY+wOf6sPjCtWv1W2PsDn+rAHVn9QTR8f7NXP8yV92NLVPTi2dMrqr1HtiSeYlGZjwiuYdLrq9qRnKyByzkgRrv4wnVo/wCzWx9gc/1Y9bSOJP8ALeuT05eaZKQqE2sLExJsqQwr2QMKTlRSeWc9D6RpuOU3W6bFO++6XijofhnUaejWc17SysJvwf8A4bPeZbmGXGXm0OMuJKVtrGUrSeoI7iON79obNt3fV6ZLEmXl3j4YJyQkgKA9wOPdHStd1ZtWiSS30VRief25bl5RW9Sz2BI5JHqY5YrtYmLgrE7U5ojx5t1TqgOgz2HoByjX/DunvrlOU01F9+5tvi3Vaa2FcK5KU0/DfCPXZiwhHUnEEhCEATpCEIARYQ5wBIQhACEIQAhFiQAixI/pLrbbfbU62XGkqBUgK27hnmM9s+cAfQ/8H3oh+LaXNan1iXxNT4XKUhKxzQyDh14eqiNgPklXZUdfal2U5qLZNWthNYnKQ1VGvAempNKS74RPtoG7kNycpJ8iY4Do/wCEPrFApUlSqZp7Q5WnSLKJeXYam3QlttACUpHLoABH7fjJrl+g9H+2O/ygDYvxblm/TG4P4TH3YfFuWb9Mbg/hMfdjXXxk1y/Qej/bHf5Q+MmuX6DUj7Y7/KANi/FuWb9Mbg/hMfdh8W5Zv0xuD+Ex92NdfGTXL9B6P9sd/lF+MmuX6DUj7Y7/ACgDYnxblmfTG4P4TH3YfFuWb9Mbg/hMfdjXXxk1y/QakfbHf5Q+MmuX6D0f7Y7/ACgDYnxbtmfTG4P4TH3Y4z4iNPLT0q1BftS1qzP1ZVObCZ+Ymg2AiYPMtp2DntSRkn84kdo6Cm/wkV1uyr7cvZtHYfWhQbdMy6vYrHJW0jng88RxZUJ+aqs/Mz06+5MTk06p555w5U4tRJUonuSSTAH54dIRYAkIGEASLmHaJACEXyiQBYRIogCQhCAKAT0EI7W4DNJbK1Mp18uXbbslV1yL0mmXMyFHwwsO7sYI67R+6OTdRJCWpWoF1SMkyhiTlarNsstI+a2hLyglI9AABAGOAZPKJgjkY25wwWxSLy13s6h16Qan6TOvPJflXs7HAGHFDOCDyIB90bQ4sNHqJSeIK1LJsikSlIbrUlJtIZa3eGX3ZhxverJJ6BOfQQByngnnDbiPpJddgcOnClRqJK3fbb9y1qooUQ6/LfCnX9mAtexSg22nKhgDnz74JjUOsFzcMN56YVuqWhQl0e85cITJSbTK5NxSlKAyUgqaWgDJOOfLtmAOOekMHyMdKcKfC6vXeoTlYrUy/JWfTHQ06tjAdm3sBXhIJBCQAQVKwcbgAMnI6BrN38IOnNTdtc2vI1NyVV4D80xILnUtrHI5fWrKiO5RmAPnV0hHVXFLY2hdLt2h3NpjXm0T9YVvTSZRxT7KmRkKcIWd7BChjarqcgJGCY1lwz6Uf0wau0OhTLRco7CjPVLqB8GbIKkkjpvJSj/HAGoyCPSJH0o4j+GXTyo6RXLU9OKDTpSv2y+Xpj8XlRUoNJy+woEnmELC8dcpHnHzYgBtPkYYI6x9TdQ9OOHrR6xqRct12DKGUnFsyoVKy7jqy6tor5jeOWEK5xiFoafcLvEgzUaJaFLdpFel2C8PADsrMNozjxEpUpTbgBIBHPGR0zmAPm/FAJMZlqvp3P6Uag120Ki4l6Ypb2xL6U7Q82pIU2sDtuQpJx2JI7R1bwa6B2fXLCuTUPUimyUzQwosyZnyUtNNtc3niQRy3EJB7bFQBxAQR1hHVPG7oTTNKbwpFatimtyNsVtjYGGc+GxMt4CkjJOApJSoeu+NM6K6RVfWy/ZK16StLAWkvzc2tO5MqwnG5wjueYAHcqAyOsAa8wYpyI+kVxWhwv8ADK1KUa56WivXEtoOOImmTPTKkn89SMhtoHsOWfXrGG31R+FTU3Tau3JQZtu1apS28hEo0pmYLivmI+CKO10KPLKMY7qTiAODgCe0POOvuA/S60NTKxezN2UGUq7UlLyqmEzIV8mVLcCiMEdcD90c9az0WSt/Vu+KTTJVErTpGszcvLsN52ttpdUEpGewAAgDBsEjocRI724f9GbDujhUuC6Kxa8hOXBLMVRTc66FeIkttqKDyOORAxyjgowAxCEIAkIQgD6F/g0v7J1H/wC/kP8AlejiLVT/AKTr1/8AGZ3/AO9cdRcCus1i6UU+92rxuBmkrqLsmqWDjLq/ECEu7vmJVjG5PXzjOaxT+C+u1afqk7XSucn33Jl5YfqCQpa1FSjgJwOZPKAOaeDn/rKWF/xEx/8Amdja3HnW522eIy161TnfCqFNpMnNS7mM7XETDyknHfmBH5JWvaH6bcTunlcsKsJasuSl3XKlNrMy6Gn1IfQOTid/Qt9ARz+uPWcUmqun9+8QNqXNJTS7itKRkpVufblUKaU6EPurW0PESOqVD059YA3XJcX2ims9BkqXq5awlJtrmVvypmpdCyMKU04j5VvP1cvM4zHrNRODrTS/NPJ69dGq0csMuPtSqJozMrM7BlTQKvbbcwDjJPPAIGchUUcHerDiqu7PC2Ki+d77LXiyByefNG1TWfVEfoujiQ0e0L0pqdk6PuOVSozyXQl5IcU0266nap9x1wDeoJAwlII9kDkIAy/hoEw9wS1VFsE/j8ydXSnwvn/CvlNmMfnbfDx7o+YxzmOi+Fjief0Gq03TqpLPz9n1RxLkwwwR4ss6BjxmwSASUgBSSRnA5gjn0TW5Xg61GqLlzzdWlKfNTKi9NS7T0zJeIsnJ3MhPUnrsxmAPnZgmPplwN6ZzVhaOVi+vxYqcuC4kLekpXIQtyXaCvCbBUQE+IvcckgYKD2jSeu2pWhF9Is+wrPpEtTqTTpxtty5hLrYRJSpVl1KE4LjxVzOVj53MZJJjMuI7jAplFty1Ld0QuYMtSoxMzMrKlIYZbQENMAPI6HmTgfmDnzgDZPCPZ+rlnXJfLGo1uusUu5XVVUzLk0w6gThVhxJShajhaVeWPkwI4U4jdLVaQ6u3BbzbakUxTnwunEjkqWcypAHnt9pB9UGMjpfGVrNI1KTmX70mZthh5Di5Z2XYCHkhQJQohvOCOXLnzjb3GVqXpVrRZlu3BbNyS7l3U0hC5FUu8h1cu6AVNlRQElTa8HrjmvEAdV686JTmvOk9vW3JVdiluy8xLTxefZU6lQSwtO3CSOftg59IwDQnhbpPDFUKvqBdV5S8wJWScZLngGXl5ZtRSVLUVKJUo7QAOXXuSI1XxbcQNiX5ozbtFs66xOVqVqEs68yw2+ypLaWHEqO5SUggKUkYzHqOFbietqQsms6b6tT4NuLZcEnNTaHH0qac5OSy9oUrHMqSe2VDIwmANH6wXM5xF8Qs/N21LLUmuzrEhTkLSUqWhKUtIWods7d5z0B59I7w1/0tu6R4eqHpbpfQnai2QzKTjiH2mcS7Y3qJ3qTlTjmCcf72escxcO8xo7pRrpcdwVS/JKZoNKbKbfmlSr5U8XsgqUkN5Cm0ZQcgAleRHp9XONHUOqai19+ybtmafaqZgtU9luXawppACQ57aCrKyCvB6bsdoA63uLSq6tWeExm1rxpC5O/KVJhUuhx1t1S5mWyGlhSCR8q2Np59VmNG/g2kyjd0agNvAJqQk5UNpVyUGw4vxOX7Xh590eq4bONOvyl9PSuq12OTNtzkqtKJp+WTiUfT7SVfJI3EKAUnoeZTGA3fqxRdIeJScv7SmrytXoVRUZl6WQhxptSXT8vLqCkggbxvSQMDKeuCIAwDiZbqrWvmoIrHifCzVnlJ355sk/I49PC2Y9MRs7hn4WaNrnYtfuCpV+o056mTipZLUsy2tK0hlK8kq55yoj3Rvuv6ocL3EfLSlSvRz8T3Cy2EFc34stMIT+h4zYKHEgk4yT9QzHk1xD6AcPFj1OhabqmazNThW6qXlVPLS48UBAU4+7gAYA+YD06QBhP4NT+3tQv+Fkv+d2M3v2/OFCRve45a5bZQ9cLNQfRUHTTH1b5gLIcO4KwcqzzHWNKcC+rdmaU1e9H7wrrVJan5eVRLqcacX4hQtwqA2JVjG4dfOOfdY65IXLqxe1YpUyJmm1CsTczLPpBAcbW6opVggEZBB5iAPqRbdWsCs8Nl4TemsiJK2DTamlDIYWz8qGV7ztUSeuI+QJ6x3ZoHrrp7aPCzX7RrVysSdxTTFTQ1JKYdUpRdbUG/aSgp5kjvHCZ6wBYmYZiwB4whFgBkjvDJ84kIAuT1zDrEj+su54Lzbm0K2KCtquhwcwCM5pGjt31mRbnGKcG2XEhSA+6ltSweh2nn+/EYvWbcqlAqhplQlHGp8bcNZCird0xjOcxu2sVm1NU1yDyLonKFVG0BtMs4SlsKJz6JJycZBGRiPCybOnqNq6EXFNioTSJJUzLTS1FRcxhAVz5gpGeXbEaaPEbIRlK/ZpN8uGnt59H6HR2cIpslCGmbabS5sprfulun2TMCldEr0mpMTKaWlvIyGnX0Jc/cTy9+Iw96g1KUq6aRMSrrFQU6lrwXRtO5RwOvY569IyS7ryuM3jUZhyozktMS0ytDbbbqkhkJUQEhPTHL3xtDUNIqCNNKzONJarEw+wl4YwSDsURj0Ufdui1am+uUFdhqecYzs0s9917FD0WlujY6OZOtrOcbpvHbZ+W5r3+g69snFLQceUy3/OPzy+jt4TcxOS7VNQp2TWlt4fCEDapSQod+fIiNs6j2vL1a5lzDt9y1EX4KE/BHHCkjGfaxvHX6o0bPzU5SbhmpSWrj0203MBHwpl5QS+AQArrz5esQ0eqv1MOZSWcZ/GX+87+hZr9DpdHbyyhLGcZ5o7+mMr1Pfr0SvRtC1mlt7UAqJEy2eQGfOMcrVnVigUyn1Kel0pkagkKYdQ6lYVlIUOh5cj3jZ/EDUZySuClIl5uYZQuSypLbqkgnerqAY8qA0u/NFpultpLtSorwLKeqiM5SPelSx7o8q1t/ya9Rbjlk0nhPZPbv3wSv4bpnqLdLTzc0U2stPLWHjovDJrFFkVxy11XIJTNIScF3xE5+dtztznGeWY/lRLPq1wSFRnpFhKpSnI3zDq3UoCBgnuefIHpHSjSqc1MNaZkIKTRCCv8A7Tv7+q411V2F2Fos3TXU+HVK7NK8VPRQQDz/APahI/xRGridln24WXJcv8X4+yZK7g1VS53JuMYvm/msbe7X+TV9s2lVrvnHZWky/jPNN+KvcsICU5A5k8upj19Upc1RajM0+daLU3LLLbiCc4I9e8b2sehVq19L36jRZB6YuGsrQtsNpBLbIPsk57YCj/iEem14ttxSqVdKZVcuZ5tLM2yoYLToTlOfXGU/4Ytq4jz6p1bcrbS75XX064/RRdwj5eiV+/Okm+2HnGPNbN/sxGnaPXfVJGVnpSnIXLzLaXW1fCEAlKhkHGciMfuO0K1aj6GqxIOyqnMlClYUleOuFDIMb5rNq126tO7KZoUylh5iVQpwqmC1kFtIHMdeYj0OqC1UHTOj25Wp9E9cXih7cFFakIG7nk88YITk9cHyimjiNk7IxbTzJrCzlJZ36+RkarhFNVMppSWIp8za5W3jbou/cwxrRK9XW0ON0xBQtIUCJlvoRkd4xi57Qq9nzbMrWJcMPvN+KhIcSvKckZ5HzBjoHUaWocwzQDWLqnKIsSg8NEuhSg6MJyTjy6RoG8ESLVZW3TaxMVeSQhOyafCgokjJGD5GLtBq7tRiU+m/9L7984Mfiug0+kTjXnO2/NF+GfxSyj0HSEBCNqaIZPnEixIAohEiwBIQhACLEiwBI/qy4GnUOFCVhKgdi+isdj6R/KLAG3f6U7UnnETlSsOTcqKcHey4EoUR3Ix/85jGa9qfWKvd0tcbJRJzEoAiXaR7SUI55Sc/Ozk588xhMSMSGipg+ZLPhu29n+zPt4nqbI8rljfOyS3XRvCRuResVu1B5FRqlkSkxWUAfLhadqlDoeaSf35jDbg1FqFz3RIVmfQnwpF1C2ZVo4ShKVBRAJ7nHMmMNhiFWhoqfNFeXVvC8s9PQXcT1N0eWcts52SWX3eFv6mV6hXgi+LiVVW5QyqS0hrw1L3n2c884HnGLtL8J1CyM7VA4+qPDEIyK641wVcFstjFtundY7ZvLbyzNdSr8bv6pyc43IqkxLseDtU6F7vaJznA848tNtQVWBUJx5Uoqbl5toNraS5sO4HKVZwenMe+MIhFX0lXyfp8fb2Lvrr/AKj6rm+/rkzNWoMydRBdwZIWJgOfB9/93jb4ecfo8s4j9OoOoiL8q1NfckXJeRk07Sx4wUpWVZUd2BgkADp2jA4QWkpU42KO8Vhfo9evvdc6nLaTy/Nmxbw1bqtcnJVVHdm6NIyzIaRLy8weeO5Ix2wB9USW1SfmrNqlvV5mYqhmlb2ZpyY9tlXIjqDnChnr3IjXkSIrRUKKio9N139+pJ8S1LnKbnvJYfbD26dDOrn1CFfte3aMzJuSzlIQE+OHs+IQgJyAAMdM9Y87w1CZvO36ZLz9OUK5IjZ+MEujDqe4UnHfkevXPnGBQiUdJVHlaXRtr16+5GevvmpKUsqSSfTount36m5Z/WS36yzJoq1ltzy5VoNtqemQdowM49nviMBvO4KNX5iUco9Aao7bSFJcQ2vd4hJyD0HQcoxiHeI06Oql5ryvV49s4JajiN+oi42tPP8Aas7eeMgGEDCMowSQixIARYkX3QBIQhACEIQAhCEAXMMwhACGYQgBEhCALmEIQAzCEIAZhmEIAQhCABhmEIAkWEIAkIQgBFhCAP/Z'
function Lz87572beb68 {
    param([string]$AuditPath)
    $dir = Split-Path -Parent $AuditPath
    $mine = Join-Path $dir (([System.IO.Path]::GetFileName($AuditPath)) -replace '^audit-','selection-' -replace '\.csv$','.json')
    $myTime = (Get-Item -LiteralPath $AuditPath).LastWriteTimeUtc
    $prevAudit = @(Get-ChildItem (Join-Path $dir 'audit-*.csv') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $AuditPath -and $_.LastWriteTimeUtc -lt $myTime -and (Test-Path -LiteralPath (($_.FullName -replace '\.csv$','') + '.outcome.json')) } |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    if (-not $prevAudit.Count) { return '' }
    $theirs = Join-Path $dir (($prevAudit[0].Name) -replace '^audit-','selection-' -replace '\.csv$','.json')
    function Lzfd6df59db2 { param([string]$f)
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if (-not (Test-Path -LiteralPath $f)) { return ,$set }
        $j = [System.IO.File]::ReadAllText($f) | ConvertFrom-Json
        foreach ($sp in @($j.Sources.PSObject.Properties)) { foreach ($r in @($sp.Value.Rules.PSObject.Properties)) { [void]$set.Add("$($sp.Name)|$(ConvertTo-SelPath $r.Name)|$("$($r.Value)".ToLowerInvariant())") } }
        return ,$set
    }
    $a = Lzfd6df59db2 $mine; $b = Lzfd6df59db2 $theirs
    $added = @($a | Where-Object { -not $b.Contains($_) }).Count; $removed = @($b | Where-Object { -not $a.Contains($_) }).Count
    if (-not $added -and -not $removed) { return '' }
    return "The selection changed since the previous run ($added rule(s) added, $removed removed)."
}
function Invoke-HtmlReport {
    param($Config, [string]$AuditPath, [switch]$NoStageLog)
    if (-not $NoStageLog) { Lz93fa3c46d9 -Config $Config -Stage 'api-report' }
    if (-not $AuditPath) {
        $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $AuditPath = $latest.FullName }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) { Write-MigrationLog ERROR "No audit CSV found in $($Config.run.reportRoot). In plain terms: there is no record to build a report from yet. Run an upload first, then build the report."; return }
    $rows = @(Import-AuditCsv $AuditPath)
    $endRow = @($rows | Where-Object { "$($_.Status)" -like 'RUN_END:*' }) | Select-Object -Last 1
    $rows   = @($rows | Where-Object { "$($_.Status)" -notlike 'RUN_END:*' })
    if (-not $rows.Count) { Write-MigrationLog WARN "Audit CSV is empty: $AuditPath"; Write-NothingProducedOutcome "no report was written: the last run's audit trail is empty, so there is nothing to report on."; return }
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    function Lz77cfd72ac2 { param($st) @($rows | Where-Object { $_.Status -eq $st }).Count }
    function _fmtMs { param([double]$ms)
        if ($ms -le 0) { return '' }
        if ($ms -lt 60000) { return ('{0:0.0} s' -f ($ms / 1000)) }
        $t = [TimeSpan]::FromMilliseconds($ms)
        if ($t.TotalHours -ge 1) { return ('{0}h {1:00}m' -f [int][math]::Floor($t.TotalHours), $t.Minutes) }
        return ('{0}m {1:00}s' -f $t.Minutes, $t.Seconds)
    }
    function _sumBytes { param($items) Get-SafeSum -Items $items -Property SourceSizeBytes }
    $brand = 'Liscaragh Migrate'
    $logoTag = ''
    if ((Test-ConfigProp $Config.run 'report')) {
        if (((Test-ConfigProp $Config.run.report 'brand')) -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
        $logoTag = Get-BrandLogoTag -Config $Config
    }
    $total = $rows.Count
    $copied = (Lz77cfd72ac2 'Copied') + (Lz77cfd72ac2 'ZeroByte')
    $skipped = Lz77cfd72ac2 'Skipped'
    $notAttempted = Lz77cfd72ac2 'NotAttempted'
    $errors = (Lz77cfd72ac2 'Error') + (Lz77cfd72ac2 'DownloadError') + (Lz77cfd72ac2 'SkippedTooLarge')
    $verifyFail = Lz77cfd72ac2 'VerifyFail'
    $wouldCopy = Lz77cfd72ac2 'WouldCopy'
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
        $diag = $null; try { $cfgW = 4; try { if (((Test-ConfigProp $Config.run 'upload')) -and ((Test-ConfigProp $Config.run.upload 'workers'))) { $cfgW = [int]$Config.run.upload.workers } } catch {}
        $diag = Get-RunDiagnosis -Rows $rows -Elapsed $elapsed -ConfiguredWorkers $cfgW -ThrottleEvents ([int]$script:RetryEvents) -DattoPauses ([int]$script:DattoPauseEvents) -TrialCapped:($notAttempted -gt 0) } catch {}
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
    $readySection = ''; $tooBigN = 0
    if ($dryRun) {
        $wc = @($rows | Where-Object { $_.Status -eq 'WouldCopy' })
        $estRows = ''
        foreach ($r in 50,100,200,500) { $estRows += "<tr><td class='n'>$r Mb/s</td><td class='n'>$(_estAt $r)</td></tr>`n" }
        $spLimit = 250GB; $bigMark = 15GB
        $tooBig  = @($wc | Where-Object { [int64]$_.SourceSizeBytes -gt $spLimit } | Sort-Object { [int64]$_.SourceSizeBytes } -Descending)
        $tooBigN = $tooBig.Count
        $bigSlow = @($wc | Where-Object { [int64]$_.SourceSizeBytes -gt $bigMark -and [int64]$_.SourceSizeBytes -le $spLimit } | Sort-Object { [int64]$_.SourceSizeBytes } -Descending)
        $bigBits = ''
        if ($tooBig.Count) {
            $tr=''; foreach ($x in ($tooBig | Select-Object -First 300)) { $tr += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(_enc $x.SourcePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SourceSizeBytes))</td></tr>`n" }
            $bigBits += "<details open><summary style='color:#B42318'><strong>$($tooBig.Count) file(s) over the SharePoint 250 GB per-file limit</strong>: these cannot be uploaded and need another home &middot; click for details</summary><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th></tr></thead><tbody>$tr</tbody></table></details>"
        }
        if ($bigSlow.Count) {
            $tr=''; foreach ($x in ($bigSlow | Select-Object -First 300)) { $tr += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(_enc $x.SourcePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SourceSizeBytes))</td></tr>`n" }
            $bigBits += "<details><summary>$($bigSlow.Count) large file(s) over 15 GB: these will upload slowly and may need retries &middot; click for details</summary><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th></tr></thead><tbody>$tr</tbody></table></details>"
        }
        if (-not $bigBits) {
            $top1 = @($wc | Sort-Object { [int64]$_.SourceSizeBytes } -Descending | Select-Object -First 1)
            $bigBits = if ($top1.Count) { "<p class='okbox'>No file is near the SharePoint 250 GB per-file limit. The largest is $(_enc $top1[0].SourcePath)$(if ("$($top1[0].Space)" -and ("$($top1[0].SourcePath)" -notlike "$($top1[0].Space)/*")) { " in $(_enc $top1[0].Space)" }) at $(Format-Bytes ([int64]$top1[0].SourceSizeBytes)).</p>" } else { "<p class='okbox'>No file is near the SharePoint 250 GB per-file limit.</p>" }
        }
        $readySection = @"
<h2 id='before'>Migration readiness: before a full run</h2>
<p class='dim'>This is a preview: nothing has been copied. It shows what a full run would move, roughly how long it would take, and anything worth dealing with first.</p>
<p class='dim'><b>Where each file will go:</b> this preview's audit CSV ($(_enc ([IO.Path]::GetFileName($AuditPath))) in this job's reports folder) lists every file with its destination path, SourcePath to DestPath, with Renamed and RenamedFrom filled where tidying changes a name. It is computed by the same rule the upload uses, and it does not read the destination, so it says where each file will land, not whether something is already there.</p>
<h3>Estimated time</h3>
<p class='dim'>$(Format-Bytes $wouldCopyBytes) to move. The real time depends on your internet upload speed and Microsoft 365 throttling, so treat this as a planning guide, not a promise.</p>
<table style='width:auto'><thead><tr><th class='n'>Sustained upload</th><th class='n'>Rough time</th></tr></thead><tbody>
$estRows
</tbody></table>
<h3>Large files</h3>
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
        if ($destBySpace.ContainsKey($g.Name)) { $d = $destBySpace[$g.Name]; $dest = if ($d.DestinationType -eq 'OneDrive') { ((@("OneDrive: $($d.TargetPrincipal)", "$($d.TargetSubFolder)") | Where-Object { "$_".Trim() }) -join ' / ') } else { (@("$($d.DestinationUrl)", "$($d.TargetLibrary)", "$($d.TargetSubFolder)") | Where-Object { "$_".Trim() }) -join ' / ' } }
        $seCell = if ($se -gt 0) { "<td class='n err'>$se</td>" } else { "<td class='n'>0</td>" }
        $srcPathNote = ''
        if ($script:SrcItem -eq 'source' -and $destBySpace.ContainsKey($g.Name)) {
            $sp0 = "$($destBySpace[$g.Name].SpaceId)"
            if ($sp0) { $srcPathNote = "<div class='dim' style='font-size:11px'>$(_enc $sp0)</div>" }
        }
        $destActual = ''
        $dps = @($g.Group | ForEach-Object { ("$($_.DestPath)" -replace '\\','/').Trim('/') } | Where-Object { $_ })
        if ($dps.Count) {
            $segsD = @($dps[0] -split '/')
            $candD = @(if ($segsD.Count -gt 1) { $segsD[0..($segsD.Count - 2)] } else { @() })
            while ($candD.Count -gt 0) {
                $tryD = ($candD -join '/') + '/'
                if (@($dps | Where-Object { -not $_.StartsWith($tryD, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { $destActual = ($candD -join '/'); break }
                if ($candD.Count -ge 2) { $candD = @($candD[0..($candD.Count - 2)]) } else { $candD = @() }
            }
        }
        $destNote = ''
        if ($destActual -and $dest.IndexOf($destActual, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $destNote = "<div class='dim' style='font-size:11px'>$(_enc $destActual)</div>"
        }
        $spaceRows += "<tr><td class='src'>$(_enc $g.Name)$srcPathNote</td><td class='dim'>$(_enc $dest)$destNote</td><td class='n'>$('{0:N0}' -f [int64]$sc)</td><td class='n'>$('{0:N0}' -f [int64]$ss)</td>$seCell<td class='n'>$(Format-Bytes $sb)</td></tr>`n"
    }
    $detailSections = ''
    foreach ($g in ($rows | Group-Object Space | Sort-Object Name)) {
        $moved = @($g.Group | Where-Object { $_.Status -ne 'Skipped' -and $_.Status -ne 'WouldCopy' })
        if (-not $moved.Count) { $moved = @($g.Group) }
        $prefix = ''
        if ($moved.Count -gt 1) {
            $segs = @("$($moved[0].SourcePath)" -split '/')
            if ($segs.Count -gt 1) {
                $cand = @($segs[0..($segs.Count - 2)])
                while ($cand.Count -gt 0) {
                    $try = ($cand -join '/') + '/'
                    if (@($moved | Where-Object { -not "$($_.SourcePath)".StartsWith($try) }).Count -eq 0) { $prefix = $try; break }
                    if ($cand.Count -ge 2) { $cand = @($cand[0..($cand.Count - 2)]) } else { $cand = @() }
                }
            }
        }
        $fileRows = ''
        foreach ($p in ($moved | Sort-Object SourcePath)) {
            $sz = [int64]$p.SourceSizeBytes
            $ums = 0.0; try { $ums = [double]$p.UploadMs } catch {}
            $spdCell = if ($ums -gt 0 -and $sz -ge 262144) { "$([math]::Round(($sz * 8 / 1000000) / ($ums / 1000), 1)) Mb/s" } else { '' }
            $stCls = if (@('Copied','ZeroByte','WouldCopy','Skipped','NotAttempted') -contains "$($p.Status)") { 'dim st' } else { 'err st' }
            $stTxt = switch ("$($p.Status)") { 'WouldCopy' { 'Would copy' } 'ZeroByte' { 'Copied (empty)' } 'NotAttempted' { 'Not attempted' } 'DownloadError' { 'Read error' } 'VerifyFail' { 'Verify failed' } 'SkippedTooLarge' { 'Too large' } default { "$($p.Status)" } }
            $mod = ''; try { $mod = ([datetime]$p.SourceModifiedUtc).ToString('yyyy-MM-dd') } catch {}
            $shown = "$($p.SourcePath)"; if ($prefix -and $shown.StartsWith($prefix)) { $shown = $shown.Substring($prefix.Length) }
            $fileRows += "<tr><td>$(Format-ReportLeafCell $shown)</td><td class='n'>$(Format-Bytes $sz)</td><td class='$stCls'>$(_enc $stTxt)</td><td class='n'>$(_fmtMs $ums)</td><td class='n'>$spdCell</td><td class='n dim'>$(_enc $mod)</td></tr>`n"
        }
        $inNote = if ($prefix) { " &middot; in $(_enc $prefix)" } else { '' }
        $fromNote = ''
        if ($script:SrcItem -eq 'source' -and $destBySpace.ContainsKey($g.Name)) {
            $sp1 = "$($destBySpace[$g.Name].SpaceId)"
            if ($sp1) { $fromNote = " &middot; from $(_enc $sp1)" }
        }
        $detailSections += (New-ReportDetails -Summary "$(_enc $g.Name) &mdash; $('{0:N0}' -f $moved.Count) file(s)$fromNote$inNote &middot; click for details" -Rows $moved.Count -Csv (_enc ([System.IO.Path]::GetFileName($AuditPath))) -Table "<table><thead><tr><th>File</th><th class='n'>Size</th><th>Status</th><th class='n'>Upload</th><th class='n'>Speed</th><th class='n'>Modified</th></tr></thead><tbody>$fileRows</tbody></table>") + "`n"
    }
    $probs = @($rows | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'DownloadError' -or $_.Status -eq 'VerifyFail' -or $_.Status -eq 'SkippedTooLarge' })
    if ($probs.Count) {
        $probRows = ''
        foreach ($p in $probs) { $probRows += "<tr><td class='src'>$(_enc $p.Space)</td><td>$(Format-ReportLeafCell $p.SourcePath)</td><td class='err'>$(_enc $(if ("$($p.Status)" -eq 'SkippedTooLarge') { 'Too large for the temp drive' } else { $p.Status }))</td><td class='dim'>$(_enc ($p.Reason + $p.Error))</td></tr>`n" }
        $probSection = "<h3>Files needing attention ($($probs.Count))</h3><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th>Status</th><th>Detail</th></tr></thead><tbody>$probRows</tbody></table>"
    } else {
        $probSection = ''
    }
    $copiedRows = @($rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' })
    $dlSecTotal = [math]::Round((Get-SafeSum -Items (@($rows | ForEach-Object { [double]$_.DownloadMs }))) / 1000, 0)
    $upSecTotal = [math]::Round((Get-SafeSum -Items (@($rows | ForEach-Object { [double]$_.UploadMs }))) / 1000, 0)
    $typeRows = if ($dryRun) { @($rows | Where-Object { $_.Status -eq 'WouldCopy' }) } else { $copiedRows }
    $extRows = ''
    foreach ($eg in (($typeRows | Group-Object { $x = ([System.IO.Path]::GetExtension($_.SourcePath)).ToLower(); if ($x) { $x } else { '(none)' } }) | Sort-Object { _sumBytes $_.Group } -Descending | Select-Object -First 14)) {
        $extRows += "<tr><td>$(_enc $eg.Name)</td><td class='n'>$('{0:N0}' -f [int64]$eg.Count)</td><td class='n'>$(Format-Bytes (_sumBytes $eg.Group))</td></tr>`n"
    }
    $hasFlag = ($rows.Count -and ((Test-ConfigProp $rows[0] 'Renamed')))
    if ($hasFlag) { $renamed = @($rows | Where-Object { "$($_.Renamed)" -eq 'True' }) }
    else { $renamed = @($copiedRows | Where-Object { $_.DestPath -and ((($_.SourcePath -split '/')[-1]) -ne (($_.DestPath -split '/')[-1])) }) }
    $longPaths = @($typeRows | Where-Object { $_.DestPath -and $_.DestPath.Length -gt 300 })
    $zeros     = @($rows | Where-Object { $_.Status -eq 'ZeroByte' })
    if ($dryRun) { $zeros = @($rows | Where-Object { $_.Status -eq 'WouldCopy' -and [int64]$_.SourceSizeBytes -eq 0 }) }
    $collisions = @(Get-AuditCollisionGroups -Config $Config -Rows $copiedRows)
    $qualityBits = ''
    if ($collisions.Count) {
        $cr=''; foreach ($x in ($collisions | Select-Object -First 300)) { $cr += "<tr><td>$(_enc $x.Dest)</td><td>$(_enc ($x.Sources -join '  |  '))</td></tr>`n" }
        $qualityBits += "<details open><summary style='color:#B42318'><strong>$($collisions.Count) name clash(es)</strong>: different $($script:SrcNounBare) items landed on one destination path, so one has overwritten the other &middot; click for details</summary><table><thead><tr><th>Destination path</th><th>$($script:SrcItemCap) items that collide</th></tr></thead><tbody>$cr</tbody></table></details>"
    }
    if ($renamed.Count) {
        $rr=''; foreach ($x in ($renamed | Select-Object -First 300)) { $of = if (((Test-ConfigProp $x 'RenamedFrom')) -and $x.RenamedFrom) { $x.RenamedFrom } else { $x.SourcePath }; $rr += "<tr><td>$(_enc $of)</td><td>$(_enc $x.DestPath)</td></tr>`n" }
        $qualityBits += "<details><summary>$($renamed.Count) name(s) tidied for M365 (illegal characters replaced, reserved names given a trailing _, trailing dots or spaces removed) &middot; click for details</summary><table><thead><tr><th>Original path</th><th>Stored as</th></tr></thead><tbody>$rr</tbody></table></details>"
    }
    if ($longPaths.Count) {
        $lr=''; foreach ($x in ($longPaths | Select-Object -First 300)) { $lr += "<tr><td>$(_enc $x.DestPath)</td><td class='n'>$($x.DestPath.Length)</td></tr>`n" }
        $qualityBits += "<details><summary>$($longPaths.Count) path(s) over 300 characters (check against the ~400-char M365 URL limit) &middot; click for details</summary><table><thead><tr><th>Destination path</th><th class='n'>Length</th></tr></thead><tbody>$lr</tbody></table></details>"
    }
    if ($zeros.Count) {
        $zNames = @($zeros | Select-Object -First 10 | ForEach-Object { _enc $_.SourcePath })
        $zMore = if ($zeros.Count -gt 10) { " &hellip; and $('{0:N0}' -f ($zeros.Count - 10)) more (see the audit CSV)" } else { '' }
        $qualityBits += "<p class='dim'>$('{0:N0}' -f $zeros.Count) empty file(s) (0 bytes) $(if ($dryRun) { 'will be' } else { 'were' }) copied as they are, which is correct and needs nothing from you: " + ($zNames -join ' &middot; ') + "$zMore.</p>"
    }
    if (-not $qualityBits) { $qualityBits = "<p class='okbox'>No collisions, renamed names, over-length paths, or zero-byte files. Nothing to review.</p>" }
    $selRows = @(); $leftInPlace = $null; $selChange = ''
    $auditDirR = Split-Path -Parent $AuditPath
    $exPath = Join-Path $auditDirR (([System.IO.Path]::GetFileName($AuditPath)) -replace '^audit-','excluded-')
    if (Test-Path -LiteralPath $exPath) { try { $selRows = @(Import-Csv -LiteralPath $exPath) } catch {} }
    if ($selRows.Count) {
        $leftInPlace = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($a in @(Get-ChildItem (Join-Path $auditDirR 'audit-*.csv') -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $AuditPath })) {
            if (-not (Test-Path -LiteralPath (($a.FullName -replace '\.csv$','') + '.outcome.json'))) { continue }
            try { foreach ($ar in @(Import-AuditCsv -LiteralPath $a.FullName)) { if (@('Copied','ZeroByte','Skipped') -contains "$($ar.Status)") { [void]$leftInPlace.Add("$($ar.Space)|$($ar.SourcePath)") } } } catch {}
        }
    }
    try { $selChange = Lz87572beb68 -AuditPath $AuditPath } catch {}
    $helpUrl = 'https://learn.microsoft.com/en-us/sharepoint/dev/solution-guidance/document-id-provider-sharepoint-add-in'
    if (((Test-ConfigProp $Config.run 'report')) -and ((Test-ConfigProp $Config.run.report 'helpUrl')) -and $Config.run.report.helpUrl) { $helpUrl = "$($Config.run.report.helpUrl)" }
    $resized = @($copiedRows | Where-Object { ([int64]$_.DestSizeBytes -gt 0) -and ([int64]$_.DestSizeBytes -ne [int64]$_.SourceSizeBytes) })
    if ($resized.Count) {
        $rz = ''
        foreach ($x in ($resized | Sort-Object { [math]::Abs([int64]$_.DestSizeBytes - [int64]$_.SourceSizeBytes) } -Descending | Select-Object -First 300)) {
            $sb2 = [int64]$x.SourceSizeBytes; $db2 = [int64]$x.DestSizeBytes; $delta = $db2 - $sb2
            $rz += "<tr><td>$(Format-ReportLeafCell $x.SourcePath)</td><td class='n'>$(Format-Bytes $sb2)</td><td class='n'>$(Format-Bytes $db2)</td><td class='n'>$(if($delta -ge 0){'+'})$delta B</td></tr>`n"
        }
        $resizeSection = "<p class='dim'>$($resized.Count) file(s) were stored at a slightly different size than the source. This is expected and not data loss: Microsoft 365 rewrites Office-family documents on upload, injecting a document ID and metadata, so the stored file differs from the original by a small amount. <a href='$(_enc $helpUrl)'>How Microsoft 365 changes files on upload</a>.</p><details><summary>Source vs stored size ($($resized.Count) files) &middot; click for details</summary><table><thead><tr><th>File</th><th class='n'>Source</th><th class='n'>Stored</th><th class='n'>Difference</th></tr></thead><tbody>$rz</tbody></table></details>"
    } else {
        $resizeSection = if ($dryRun) { '' } else { "<p class='okbox'>Every file this run uploaded was stored at exactly its source size.</p>" }
    }
    $ocStatus=''; $ocReason=''; $ocExpected=$null; $ocResumed=$false; $ocSpoolEnc=$null; $oc=$null
    $sidecar = ($AuditPath -replace '\.csv$','') + '.outcome.json'
    if (Test-Path $sidecar) {
        try {
            $oc = Get-Content $sidecar -Raw | ConvertFrom-Json
            $ocStatus="$($oc.Status)"; $ocReason="$($oc.Reason)"; $ocExpected=$oc.ExpectedFiles
            try {
                $rv = $oc.Resumed
                $ocResumed = if ($null -ne $rv -and (Test-ConfigProp $rv 'IsPresent')) { [bool]$rv.IsPresent } else { [bool]$rv }
            } catch {}
            try { if ((Test-ConfigProp $oc 'SpoolEncrypted')) { $ocSpoolEnc = [bool]$oc.SpoolEncrypted } } catch {}
        } catch {}
    }
    if (-not $ocStatus -and $endRow) { $ocStatus = ("$($endRow.Status)" -replace '^RUN_END:',''); $ocReason = "$($endRow.Reason)" }
    $vitLines = @(); $vitMachine = ''
    try {
        if ($script:VitalsSummary) { $vitLines = @($script:VitalsSummary.Lines); $vitMachine = "$($script:VitalsSummary.Machine)" }
        elseif ($oc -and (Test-ConfigProp $oc 'Vitals')) { $vitLines = @($oc.Vitals); $vitMachine = "$($oc.VitalsMachine)" }
    } catch {}
    $vitLines = @($vitLines | Where-Object { "$_".Trim() })
    if ($vitLines.Count) {
        $diagSection += @"
<h2>This computer during the run</h2>
<div class='diag'>
  $(if ($vitMachine) { "<p class='dim'>$(_enc $vitMachine)</p>" })
  <ul>$(($vitLines | ForEach-Object { "<li>$(_enc $_)</li>" }) -join '')</ul>
  <p class='dim'>Sampled every few seconds from counters Windows already keeps (processor, memory, disk, network and the copy queue; no file names). The full series is the vitals CSV in the job's reports folder, which the support bundle includes.</p>
</div>
"@
    }
    if ($null -ne $ocSpoolEnc) {
        $qualityBits += if ($ocSpoolEnc) {
            "<p class='okbox'>Files were staged on the transfer computer ENCRYPTED at rest (AES-256, key held only in that run's memory). Apart from the source itself, readable copies of the data existed only in memory, in transit over TLS, and at the destination.</p>"
        } else {
            "<p class='dim'>Spool encryption was switched off for this run (run.encryptSpool = false): staged files were readable on the transfer computer while the run was in flight.</p>"
        }
    }
    if (-not $ocStatus) { $ocStatus = if ($dryRun) { 'PREVIEW' } else { 'INCOMPLETE' } }
    $bannerStyle = switch ($ocStatus) {
        'COMPLETED'             { 'background:#E7F7EF;border:1px solid #86D9B4;color:#066A4B' }
        'PREVIEW'               { 'background:#E9F1F8;border:1px solid #A9C7DD;color:#1C6091' }
        'COMPLETED_WITH_ERRORS' { 'background:#FFF6EC;border:1px solid #F5C083;color:#B5460F' }
        'CANCELLED'             { 'background:#FFF6EC;border:1px solid #F5C083;color:#B5460F' }
        'CAPPED'                { 'background:#FFF6EC;border:1px solid #F5C083;color:#B5460F' }
        default                 { 'background:#fef2f2;border:1px solid #fca5a5;color:#8F1D12' }
    }
    $bannerTitle = switch ($ocStatus) {
        'COMPLETED'             { 'Completed - all planned files uploaded' }
        'PREVIEW'               { 'Preview (dry-run) - nothing was uploaded' }
        'COMPLETED_WITH_ERRORS' { 'Completed with errors - reached the end; some files need a retry' }
        'CANCELLED'             { 'Cancelled by user - stopped before finishing; uploaded files are kept' }
        'CAPPED'                { 'Stopped: evaluation limit reached - a licence is needed to finish' }
        'ENDED_EARLY'           { 'ENDED EARLY - the run did NOT finish' }
        default                 { 'INCOMPLETE - no completion marker (the run was interrupted before it could finish)' }
    }
    $bannerExtra = ''
    if ($ocStatus -eq 'CAPPED') {
        $bannerExtra += " $copied file(s) copied for real"
        if ($skipped -gt 0) { $bannerExtra += ", $skipped already present and left alone" }
        $bannerExtra += ", and $notAttempted file(s) NOT attempted because the evaluation limit was reached (a licence is required to migrate the rest): $total file(s) accounted for."
    }
    elseif ($skipped -gt 0)  { $bannerExtra += " $('{0:N0}' -f $copied) file(s) copied, $('{0:N0}' -f $skipped) already present and left alone: $('{0:N0}' -f $total) file(s) accounted for." }
    elseif ($total -gt 0) { $bannerExtra += " $('{0:N0}' -f $total) file(s) accounted for." }
    if ($ocResumed) { $bannerExtra += " This run was RESUMED after a pause, so the files already present are the ones the paused run had finished." }
    if (@('ENDED_EARLY','CANCELLED','INCOMPLETE') -contains $ocStatus -and $ocExpected) {
        $bannerExtra += " This run had planned to copy about $ocExpected file(s)."
    }
    if ($ocReason) { $bannerExtra += " Reason: $(_enc $ocReason)." }
    $unfinished = @('ENDED_EARLY','CANCELLED','INCOMPLETE') -contains $ocStatus
    $startedNames = @($rows | Group-Object Space | ForEach-Object { "$($_.Name)" })
    $plannedN = 0; try { if ($oc -and (Test-ConfigProp $oc 'SpacesPlanned')) { $plannedN = [int]$oc.SpacesPlanned } } catch {}
    $notStartedN = if ($unfinished -and $plannedN -gt $startedNames.Count) { $plannedN - $startedNames.Count } else { 0 }
    $notStarted = @()
    if ($notStartedN -gt 0) {
        $nsCand = @($destBySpace.Keys | Where-Object { $startedNames -notcontains "$_" } | Sort-Object)
        if ($nsCand.Count -eq $notStartedN) { $notStarted = $nsCand }
    }
    if ($unfinished) {
        $bannerExtra = " $copied file(s) copied before it stopped"
        if ($skipped -gt 0) { $bannerExtra += ", $skipped already present and left alone" }
        $bannerExtra += '.'
        if ($notStartedN -gt 0) { $bannerExtra += " $notStartedN $($script:SrcItem)(s) were not started$(if ($notStarted.Count) { " ($(_enc ($notStarted -join ', ')))" })." }
        if ($ocResumed) { $bannerExtra += " This run was RESUMED after a pause, so the files already present are the ones the paused run had finished." }
        if ($ocExpected) { $bannerExtra += " This run had planned to copy about $ocExpected file(s)." }
        $bannerExtra += " Files that were part-way through uploading when it stopped are not in this record. Run 'Sync new and changed' to finish, then 'Verify files arrived' to confirm."
        if ($ocReason) { $bannerExtra += " Reason: $(_enc $ocReason)." }
    }
    $bannerTitleTxt = "$bannerTitle"; if ($bannerTitleTxt -notmatch '[.!?]$') { $bannerTitleTxt += '.' }
    if ($selRows.Count) {
        $selFilesN = @($selRows | Where-Object { "$($_.Kind)" -ne 'Folder' }).Count; $selFoldN = @($selRows | Where-Object { "$($_.Kind)" -eq 'Folder' }).Count
        $bannerExtra += " Your selection left out $('{0:N0}' -f $selFilesN) file(s)$(if ($selFoldN) { " and $selFoldN folder(s)" }); see 'Left out by your selection'."
    }
    if ($selChange) { $bannerExtra += " $(_enc $selChange)" }
    $statusBanner = "<div style='$bannerStyle;border-radius:8px;padding:14px 16px;margin:0 0 18px;font-size:14px'><strong>$(_enc $bannerTitleTxt)</strong>$bannerExtra</div>"
    if (-not $probSection) {
        $probSection = if ($dryRun) { "<p class='okbox'>Nothing went wrong while listing. Every file is in the plan above.</p>" }
            elseif ($unfinished) { "<p style='background:#FFF6EC;border:1px solid #F5C083;color:#B5460F;padding:12px 14px;border-radius:8px'>No errors among the $total file(s) this run reached. The run did not finish, so this is not a complete record$(if ($notStartedN -gt 0) { ": $notStartedN $($script:SrcItem)(s) were not started" }). Run 'Sync new and changed', then 'Verify files arrived'.</p>" }
            elseif ($errors -gt 0) { "<p style='background:#FDECEC;border:1px solid #E5A3A3;color:#9B1C1C;padding:12px 14px;border-radius:8px'>$('{0:N0}' -f $errors) file(s) did not copy. See the audit CSV for each one.</p>" }
            else { "<p class='okbox'>No errors or verification failures. Every file was accounted for.</p>" }
    }
    $emptyNames = @()
    if (-not $unfinished) {
        $planNames = @(@($script:RunSpaceNames) | Where-Object { $_ })
        if (-not $planNames.Count) { try { if ($oc -and (Test-ConfigProp $oc 'SpaceNames') -and "$($oc.SpaceNames)") { $planNames = @("$($oc.SpaceNames)" -split "`n" | Where-Object { $_ }) } } catch {} }
        $emptyNames = @($planNames | Where-Object { $startedNames -notcontains "$_" } | Sort-Object -Unique)
    }
    foreach ($enName in $emptyNames) {
        $enPath = ''; $enDest = ''
        try { if ($destBySpace.ContainsKey($enName)) { $d = $destBySpace[$enName]; if ($script:SrcItem -eq 'source') { $enPath = "$($d.SpaceId)" }; $enDest = if ($d.DestinationType -eq 'OneDrive') { ((@("OneDrive: $($d.TargetPrincipal)", "$($d.TargetSubFolder)") | Where-Object { "$_".Trim() }) -join ' / ') } else { ((@("$($d.DestinationUrl)", "$($d.TargetLibrary)", "$($d.TargetSubFolder)") | Where-Object { "$_".Trim() }) -join ' / ') } } } catch {}
        $spaceRows += "<tr><td class='src'>$(_enc $enName)$(if ($enPath) { "<div class='dim' style='font-size:11px'>$(_enc $enPath)</div>" })</td><td class='dim'>$(_enc $enDest)<div class='dim' style='font-size:11px'>No files to copy (the $($script:SrcItem) is empty$(if ($selRows.Count) { ' or everything in it was left out' }))</div></td><td class='n'>0</td><td class='n'>0</td><td class='n'>0</td><td class='n'>0 B</td></tr>`n"
    }
    if ($notStartedN -gt 0) {
        foreach ($nsName in $notStarted) {
            $nsPath = ''; try { if ($script:SrcItem -eq 'source' -and $destBySpace.ContainsKey($nsName)) { $nsPath = "$($destBySpace[$nsName].SpaceId)" } } catch {}
            $spaceRows += "<tr><td class='src'>$(_enc $nsName)$(if ($nsPath) { "<div class='dim' style='font-size:11px'>$(_enc $nsPath)</div>" })</td><td class='warnc' colspan='5'>Not started: the run stopped before it reached this $($script:SrcItem)</td></tr>`n"
        }
        if (-not $notStarted.Count) { $spaceRows += "<tr><td class='warnc' colspan='6'>$notStartedN more $($script:SrcItem)(s) were not started: the run stopped before it reached them</td></tr>`n" }
    }
    if ($unfinished -and $diagSection) { $diagSection = $diagSection.Replace('<p><b>Planning:</b> ', '<p><b>Planning (from a run that did not finish, so treat it as rough):</b> ') }
    $runType = 'run'; if ([IO.Path]::GetFileName($AuditPath) -match '^audit-([A-Za-z]+)-') { $runType = $Matches[1] }
    $titleBase = if ($ocResumed) { 'Sync report (resumed)' } elseif ($runType -eq 'Delta') { 'Sync report (new and changed)' } else { 'Migration Report' }
    $title = if ($dryRun) { 'Preview (dry run, nothing uploaded)' } elseif ($unfinished) { "$titleBase (did not finish)" } else { $titleBase }
    $now = Get-Date
    $tv = Lzb0b39673dd
    $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    function Lz18b7aaae72 { param([string]$k, [string]$v) if (-not "$v".Trim()) { $v = '&mdash;' }; return "<tr><td>$k</td><td>$v</td></tr>`n" }
    $rdRows = ''
    $runTypeLabel = switch ($runType) {
        'FirstPass' { if ($dryRun) { 'Preview (dry run, nothing uploaded)' } else { 'Full upload (first pass)' } }
        'Delta'     { 'Sync new and changed (delta)' }
        default     { $runType }
    }
    $rdRows += Lz18b7aaae72 'Run type' (_enc $runTypeLabel)
    $rdRows += Lz18b7aaae72 'Source' (_enc $script:SrcSysName)
    $rdRows += Lz18b7aaae72 "$($script:SrcItemCap)s in this run" $(if ($notStartedN -gt 0) { "$plannedN planned, $($startedNames.Count) started" } else { "$((@($rows | Group-Object Space)).Count + $emptyNames.Count)" })
    try { if ($times.Count -ge 2) {
        $rdRows += Lz18b7aaae72 'Started'  (_enc (($times | Measure-Object -Minimum).Minimum.ToLocalTime().ToString('dd MMM yyyy HH:mm:ss')))
        $rdRows += Lz18b7aaae72 'Finished' (_enc (($times | Measure-Object -Maximum).Maximum.ToLocalTime().ToString('dd MMM yyyy HH:mm:ss')))
        $rdRows += Lz18b7aaae72 $(if ($dryRun) { 'Listing time' } else { 'Copying window' }) (_enc $elapsedStr)
    } } catch {}
    try { if ("$env:USERNAME".Trim()) { $rdRows += Lz18b7aaae72 'Run by' (_enc ("$env:USERNAME" + $(if ("$env:COMPUTERNAME".Trim()) { " on $env:COMPUTERNAME" }))) } } catch {}
    $rdRows += Lz18b7aaae72 'App version' (_enc "$tv")
    try {
        $w = 4; if (((Test-ConfigProp $Config.run 'upload')) -and ((Test-ConfigProp $Config.run.upload 'workers'))) { $w = [int]$Config.run.upload.workers }
        $rdRows += Lz18b7aaae72 'Parallel uploads' ("$w")
    } catch {}
    try {
        $bwU = 0; $bwD = 0
        if ((Test-ConfigProp $Config.run 'bandwidth')) {
            if ((Test-ConfigProp $Config.run.bandwidth 'maxUploadMbps'))   { $bwU = [int]$Config.run.bandwidth.maxUploadMbps }
            if ((Test-ConfigProp $Config.run.bandwidth 'maxDownloadMbps')) { $bwD = [int]$Config.run.bandwidth.maxDownloadMbps }
        }
        $rdRows += Lz18b7aaae72 'Speed limits' $(if ($bwU -or $bwD) { "upload $(if($bwU){"$bwU Mb/s"}else{'unlimited'}), download $(if($bwD){"$bwD Mb/s"}else{'unlimited'})" } else { 'none (unlimited)' })
    } catch {}
    try {
        $fBits = @()
        if (((Test-ConfigProp $Config.run 'tuning'))) {
            $tn = $Config.run.tuning
            if (((Test-ConfigProp $tn 'maxFileSizeMB')) -and [int]$tn.maxFileSizeMB -gt 0) { $fBits += "files over $([int]$tn.maxFileSizeMB) MB skipped" }
            if (((Test-ConfigProp $tn 'excludePatterns')) -and @($tn.excludePatterns).Count) { $fBits += "excluded: $((@($tn.excludePatterns) -join ', '))" }
            if (((Test-ConfigProp $tn 'modifiedAfter'))  -and "$($tn.modifiedAfter)".Trim())  { $fBits += "modified after $($tn.modifiedAfter)" }
            if (((Test-ConfigProp $tn 'modifiedBefore')) -and "$($tn.modifiedBefore)".Trim()) { $fBits += "modified before $($tn.modifiedBefore)" }
        }
        if (((Test-ConfigProp $Config.run 'tuning')) -and ((Test-ConfigProp $Config.run.tuning 'includePatterns')) -and @($Config.run.tuning.includePatterns).Count) { $fBits += "only: $((@($Config.run.tuning.includePatterns) -join ', '))" }
        $rdRows += Lz18b7aaae72 'File filters (type, size, date)' $(if ($fBits.Count) { _enc ($fBits -join '; ') } else { 'none' })
        $selFilesRd = @($selRows | Where-Object { "$($_.Kind)" -ne 'Folder' }).Count
        $rdRows += Lz18b7aaae72 'Selection (Edit what to copy)' $(if ($selRows.Count) { "$('{0:N0}' -f $selFilesRd) file(s) left out$(if (@($selRows).Count -gt $selFilesRd) { ", $(@($selRows).Count - $selFilesRd) folder(s) not listed" })" } else { 'none (the whole of each source)' })
    } catch {}
    try { $rdRows += Lz18b7aaae72 'Name tidying' $(if (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames) { 'on (M365-illegal names corrected and recorded)' } else { 'off' }) } catch {}
    $rdRows += Lz18b7aaae72 'Audit record' (_enc ([System.IO.Path]::GetFileName($AuditPath)))
    $runDetailsSection = "<h2 id='rundetails'>Run details</h2><table style='width:auto'><tbody>$rdRows</tbody></table>"
    $insightBits = ''; $retriedHtml = ''
    if (-not $dryRun -and $copiedRows.Count) {
        $big = @($copiedRows | Sort-Object { [int64]$_.SourceSizeBytes } -Descending | Select-Object -First 10)
        $tr = ''; foreach ($x in $big) { $ums2 = 0.0; try { $ums2 = [double]$x.UploadMs } catch {}; $tr += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(Format-ReportLeafCell $x.SourcePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SourceSizeBytes))</td><td class='n'>$(_fmtMs $ums2)</td></tr>`n" }
        $insightBits += "<details><summary>10 largest files &middot; click for details</summary><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th><th class='n'>Upload</th></tr></thead><tbody>$tr</tbody></table></details>"
        $slow = @($copiedRows | Where-Object { [double]$_.UploadMs -gt 0 } | Sort-Object { [double]$_.UploadMs } -Descending | Select-Object -First 10)
        if ($slow.Count) {
            $tr = ''; foreach ($x in $slow) { $tr += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(Format-ReportLeafCell $x.SourcePath)</td><td class='n'>$(Format-Bytes ([int64]$x.SourceSizeBytes))</td><td class='n'>$(_fmtMs ([double]$x.UploadMs))</td></tr>`n" }
            $insightBits += "<details><summary>10 slowest uploads &middot; click for details</summary><table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Size</th><th class='n'>Upload</th></tr></thead><tbody>$tr</tbody></table></details>"
        }
        $retriedRows = @($rows | Where-Object { [int]$_.Retries -gt 0 } | Sort-Object { [int]$_.Retries } -Descending)
        if ($retriedRows.Count) {
            $tr = ''; foreach ($x in ($retriedRows | Select-Object -First 300)) { $tr += "<tr><td class='src'>$(_enc $x.Space)</td><td>$(Format-ReportLeafCell $x.SourcePath)</td><td class='n'>$([int]$x.Retries)</td><td class='dim'>$(_enc $x.Status)</td></tr>`n" }
            $retriedHtml = New-ReportDetails -Summary "$('{0:N0}' -f $retriedRows.Count) file(s) hit a retry or back-off and then succeeded &middot; click for details" -Rows ([math]::Min(300, $retriedRows.Count)) -Total $retriedRows.Count -Csv (_enc ([System.IO.Path]::GetFileName($AuditPath))) -Table "<table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th class='n'>Retries</th><th>Final status</th></tr></thead><tbody>$tr</tbody></table>"
        }
    }
    $insightsSection = if ($insightBits) { "<h3>Largest and slowest files</h3>$insightBits" } else { '' }
    $actItems = New-Object System.Collections.Generic.List[string]
    if ($dryRun) {
        if ($tooBigN -gt 0) { $actItems.Add("$tooBigN file(s) are over the SharePoint 250 GB per-file limit and cannot be uploaded. Move them elsewhere or leave them out with Edit selection (see Migration readiness).") }
    } else {
        if ($ocStatus -eq 'CAPPED') { $actItems.Add("The evaluation limit stopped this run. Licence this Microsoft tenant, then run 'Sync new and changed' to copy the rest.") }
        if ($unfinished) { $actItems.Add("The run did not finish$(if ($notStartedN -gt 0) { " ($notStartedN $($script:SrcItem)(s) not started)" }). Run 'Sync new and changed' to finish, then 'Verify files arrived'.") }
        if (($errors + $verifyFail) -gt 0) { $actItems.Add("$('{0:N0}' -f ($errors + $verifyFail)) file(s) failed or failed verification. Run 'Sync new and changed' to retry them; they are listed under Exceptions and changes.") }
        if ($collisions.Count) { $actItems.Add("$($collisions.Count) name clash(es): two $($script:SrcItem) files landed on one destination path, so one overwrote the other. See Exceptions and changes.") }
    }
    $actionHtml = if ($actItems.Count) { "<div class='action todo'><ul>" + (($actItems | ForEach-Object { "<li>$(_enc $_)</li>" }) -join '') + "</ul></div>" }
        elseif ($dryRun) { "<div class='action none'><b>No action required before a full run.</b> Nothing in this preview would be refused by SharePoint.</div>" }
        else { "<div class='action none'><b>No action required.</b> Every file this run reached was copied and checked, or was already there.</div>" }
    $sizeMatched = @($copiedRows | Where-Object { [int64]$_.DestSizeBytes -gt 0 -and [int64]$_.DestSizeBytes -eq [int64]$_.SourceSizeBytes }).Count
    $zeroN = @($copiedRows | Where-Object { $_.Status -eq 'ZeroByte' }).Count
    $verifyHtml = if ($dryRun) {
        "<p class='dim'>Nothing was uploaded, so nothing was verified. A real run checks each file as it uploads: the stored size must equal the source size exactly. Office documents are the exception: Microsoft 365 rewrites them on upload, so for those the check confirms only that the upload completed and the file is stored.</p>"
    } else {
        "<table style='width:auto'><tbody>" +
        "<tr><td>Checked by size at upload</td><td class='n'>$('{0:N0}' -f $sizeMatched)</td><td class='dim'>stored size equals the source size exactly</td></tr>" +
        $(if ($resized.Count) { "<tr><td>Office documents stored at a different size</td><td class='n'>$('{0:N0}' -f $resized.Count)</td><td class='dim'>Microsoft 365 rewrites these on upload (document ID and metadata), so their size cannot be compared; the check confirms the upload completed and the file is stored</td></tr>" } else { '' }) +
        $(if ($zeroN) { "<tr><td>Empty files (0 bytes)</td><td class='n'>$('{0:N0}' -f $zeroN)</td><td class='dim'>copied as empty files, which is correct</td></tr>" } else { '' }) +
        $(if ($skipped) { "<tr><td>Already at the destination, left alone</td><td class='n'>$('{0:N0}' -f $skipped)</td><td class='dim'>judged unchanged by Sync</td></tr>" } else { '' }) +
        $(if (($errors + $verifyFail) -gt 0) { "<tr><td class='err'>Failed or failed verification</td><td class='n err'>$('{0:N0}' -f ($errors + $verifyFail))</td><td class='dim'>see Exceptions and changes</td></tr>" } else { '' }) +
        "</tbody></table><p class='dim'>Contents are not compared byte by byte. 'Verify files arrived' checks afterwards that every file is present by path.$(if ($unfinished) { ' This run did not finish, so only the files it reached were checked.' })</p>"
    }
    $retriedLine = if (-not $dryRun -and $retried) { "<p class='dim'>$('{0:N0}' -f $retried) file(s) needed one or more retries (Microsoft throttling) and then succeeded.</p>" } else { '' }
    $techInner = ("$runDetailsSection$diagSection").Replace('<h2', '<h3').Replace('</h2>', '</h3>')
    $techHtml = "<details id='tech'><summary>Technical details: run settings, what limited this run, this computer &middot; click for details</summary>$techInner$(if (-not $dryRun) { "<p class='dim'>Time split, summed across the parallel streams: $dlSecTotal s reading from $(_enc $script:SrcNoun), $upSecTotal s uploading to Microsoft 365.</p>" })</details>"
    $tocSection = "<p class='toc'>Jump to: <a href='#scope'>Scope and destination</a> &middot; <a href='#verify'>Results and verification</a> &middot; <a href='#exceptions'>Exceptions and changes</a> &middot; <a href='#files'>Detailed evidence</a> &middot; <a href='#tech'>Technical details</a></p>"
    $selFilesCard = @($selRows | Where-Object { "$($_.Kind)" -ne 'Folder' }).Count
    $selFoldCard = @($selRows | Where-Object { "$($_.Kind)" -eq 'Folder' }).Count
    $selCardV = Format-SelLeftOutCount $selRows
    $cardsHtml = if ($dryRun) {
        "<div class='cards'>" +
        "<div class='card'><div class='v'>$('{0:N0}' -f $wouldCopy)</div><div class='l'>Files planned</div></div>" +
        "<div class='card'><div class='v'>$(Format-Bytes $moveBytes)</div><div class='l'>Data planned</div></div>" +
        "<div class='card'><div class='v'>$(_estAt 100)</div><div class='l'>Est. time @ 100 Mb/s</div></div>" +
        "<div class='card'><div class='v $(if ($tooBigN) { 'err' })'>$(if ($tooBigN) { "$tooBigN blocker(s)" } else { 'Ready' })</div><div class='l'>Readiness</div></div></div>" +
        "<div class='cards sec'>$(if ($selFilesCard -or $selFoldCard) { "<div class='card'><div class='v'>$selCardV</div><div class='l'>Left out by your selection</div></div>" })<div class='card'><div class='v'>$('{0:N0}' -f $renamed.Count)</div><div class='l'>Names tidied</div></div><div class='card'><div class='v'>$('{0:N0}' -f @($rows | Where-Object { $_.Status -eq 'WouldCopy' -and [int64]$_.SourceSizeBytes -eq 0 }).Count)</div><div class='l'>Empty files</div></div></div>"
    } else {
        "<div class='cards'>" +
        "<div class='card'><div class='v'>$('{0:N0}' -f $copied)</div><div class='l'>Copied</div></div>" +
        "<div class='card'><div class='v'>$('{0:N0}' -f $skipped)</div><div class='l'>Unchanged (already there)</div></div>" +
        "<div class='card'><div class='v $(if(($errors+$verifyFail) -gt 0){'err'})'>$('{0:N0}' -f ($errors + $verifyFail))</div><div class='l'>Failed</div></div>" +
        "<div class='card'><div class='v'>$(Format-Bytes $moveBytes)</div><div class='l'>Data transferred</div></div></div>" +
        "<div class='cards sec'><div class='card'><div class='v'>$('{0:N0}' -f $total)</div><div class='l'>Files recorded</div></div><div class='card'><div class='v'>$elapsedStr</div><div class='l'>Copying time</div></div><div class='card'><div class='v'>$mbitsPerSec Mb/s</div><div class='l'>Average speed</div></div>$(if ($notAttempted -gt 0) { "<div class='card'><div class='v'>$('{0:N0}' -f $notAttempted)</div><div class='l'>Not attempted (evaluation limit)</div></div>" })$(if ($selFilesCard -or $selFoldCard) { "<div class='card'><div class='v'>$selCardV</div><div class='l'>Left out by your selection</div></div>" })</div>"
    }
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_enc $brand) - $title</title>
$(Get-ReportStyle)
</head><body><div class='wrap'>
<header>$logoTag<div><h1>$(_enc (Get-ReportHeaderTitle $brand))</h1><div class='sub'>$title &middot; generated $($now.ToString('dd MMM yyyy HH:mm'))$verSub$(Get-ReportClientSub $Config)</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
$statusBanner
$cardsHtml
$(if ($dryRun) {
 <#B1: 'Would copy' used to look like a forecast for whichever real run came next, when in fact it
   always counts every file as if none of it existed at the destination yet. This preview does not
   read the destination (deliberately, to stay fast and source-only), so it cannot tell what Sync
   would actually skip.#>
 "<p class='dim' style='margin-top:6px'>This is a rehearsal only. 'Files planned' counts every file as if starting fresh; it is not a forecast for 'Sync new and changed', which only copies what is new or changed at the destination and will very likely touch far fewer files than this number.</p>"
})
<h2 id='action'>Action required</h2>
$actionHtml
$tocSection
<h2 id='scope'>Scope and destination</h2>
<table><thead><tr><th>$($script:SrcItemCap)</th><th>Destination</th><th class='n'>$(if($dryRun){'Planned'}else{'Copied'})</th><th class='n'>Unchanged</th><th class='n'>Failed</th><th class='n'>Data</th></tr></thead><tbody>
$spaceRows
</tbody></table>
$(Get-SelectionSectionHtml -Rows $selRows -LeftInPlace $leftInPlace -Lead $selChange)
$readySection
<h2 id='verify'>Results and verification</h2>
$verifyHtml
$retriedLine
$(if ($resizeSection -and $resized.Count) { $resizeSection })
<h2 id='exceptions'>Exceptions and changes</h2>
$probSection
$qualityBits
$retriedHtml
<h2 id='files'>Detailed evidence</h2>
<h3 id='types'>File types</h3>
$(if ($extRows) { "<table><thead><tr><th>Extension</th><th class='n'>Files</th><th class='n'>Size</th></tr></thead><tbody>$extRows</tbody></table>" } else { "<p class='dim'>No file was copied in this run, so there are no file types to show.</p>" })
$insightsSection
<h3>File details</h3>
$detailSections
$techHtml
<footer>Source: $(_enc $script:SrcSysName) &middot; Full per-file detail: $(_enc ([System.IO.Path]::GetFileName($AuditPath))) &middot; $(_enc (Get-ReportTimeNote)) &middot; Generated from the migration audit trail by Liscaragh Migrate &middot; Liscaragh Software &middot; www.liscaragh.com</footer>
</div>
$(Get-ReportPrintScript)
</body></html>
"@
    $fileType = if ($dryRun) { 'Preview' } else { $runType }
    $outPath = Join-Path $Config.run.reportRoot ("report-" + $fileType + "-" + $now.ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "HTML report written: $outPath"
    return $outPath
}
function Write-NothingProducedOutcome {
    param([string]$Text)
    if ($script:GuiMode) { Write-Host ("##CHECKOUTCOME##|WARN|" + $Text) }
}
function Invoke-CompletionCertificate {
    param($Config, [string]$AuditPath, [switch]$NoStageLog)
    if (-not $NoStageLog) { Lz93fa3c46d9 -Config $Config -Stage 'api-certificate' }
    if (-not $AuditPath) {
        $latest = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $AuditPath = $latest.FullName }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) { Write-MigrationLog ERROR "No audit CSV found in $($Config.run.reportRoot). A certificate is built from a completed run's audit trail; run a migration to completion first."; Write-NothingProducedOutcome "no certificate was issued: there is no run on record to certify. Run a migration through to completion first."; return }
    $rows = @(Import-AuditCsv $AuditPath)
    $endRow = @($rows | Where-Object { "$($_.Status)" -like 'RUN_END:*' }) | Select-Object -Last 1
    $rows   = @($rows | Where-Object { "$($_.Status)" -notlike 'RUN_END:*' })
    if (-not $rows.Count) { Write-MigrationLog WARN "Audit CSV is empty: $AuditPath"; Write-NothingProducedOutcome "no certificate was issued: the last run's audit trail is empty, so there is nothing to certify."; return }
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    function Lz77cfd72ac2 { param($st) @($rows | Where-Object { $_.Status -eq $st }).Count }
    function _sumBytes { param($items) Get-SafeSum -Items $items -Property SourceSizeBytes }
    $copied  = (Lz77cfd72ac2 'Copied') + (Lz77cfd72ac2 'ZeroByte')
    $skipped = Lz77cfd72ac2 'Skipped'
    $errors  = (Lz77cfd72ac2 'Error') + (Lz77cfd72ac2 'DownloadError') + (Lz77cfd72ac2 'SkippedTooLarge')
    $verifyFail = Lz77cfd72ac2 'VerifyFail'
    $wouldCopy  = Lz77cfd72ac2 'WouldCopy'
    $present = $copied + $skipped
    $presentBytes = _sumBytes (@($rows | Where-Object { $_.Status -eq 'Copied' -or $_.Status -eq 'ZeroByte' -or $_.Status -eq 'Skipped' }))
    $projects = @($rows | Where-Object { "$($_.Space)".Trim() } | Group-Object Space).Count
    $dryRun = ($wouldCopy -gt 0 -and $copied -eq 0)
    $ocStatus=''
    $sidecar = ($AuditPath -replace '\.csv$','') + '.outcome.json'
    if (Test-Path $sidecar) { try { $oc = Get-Content $sidecar -Raw | ConvertFrom-Json; $ocStatus="$($oc.Status)" } catch {} }
    if (-not $ocStatus -and $endRow) { $ocStatus = ("$($endRow.Status)" -replace '^RUN_END:','') }
    if (-not $ocStatus) { $ocStatus = if ($dryRun) { 'PREVIEW' } else { 'INCOMPLETE' } }
    if ($dryRun -or @('PREVIEW','INCOMPLETE','ENDED_EARLY','CANCELLED','CAPPED') -contains $ocStatus) {
        Write-MigrationLog ERROR ("A completion certificate is only issued for a completed migration. This run is '" + $ocStatus + "'. Run a full sync through to completion (then a verify), and issue the certificate from that run.")
        Write-NothingProducedOutcome ("no certificate was issued: the last run is '" + $ocStatus + "', and a certificate is only issued for a completed migration. Run a full sync through to completion, then a verify, and issue it from that run.")
        return
    }
    $withErrors = ($ocStatus -eq 'COMPLETED_WITH_ERRORS') -or (($errors + $verifyFail) -gt 0)
    $certClashes = 0; try { $certClashes = @(Get-AuditCollisionGroups -Config $Config -Rows $rows).Count } catch {}
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
    $brand = 'Liscaragh Migrate'; $logoTag = ''; $client = ''
    if ((Test-ConfigProp $Config.run 'report')) {
        if (((Test-ConfigProp $Config.run.report 'brand')) -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
        if (((Test-ConfigProp $Config.run.report 'client')) -and $Config.run.report.client) { $client = "$($Config.run.report.client)" }
        $logoTag = Get-BrandLogoTag -Config $Config
    }
    $caveat = ''
    if ($withErrors) {
        $caveat = "<div class='caveat'><strong>Issued with exceptions.</strong> $($errors + $verifyFail) file(s) need attention and are listed in the migration report; every other file is present and verified. This certificate records the migration as complete apart from those items.</div>"
    }
    if ($certClashes -gt 0) {
        $caveat += "<div class='caveat'><strong>Name clashes.</strong> $certClashes destination path(s) received a file from two different sources, so one has overwritten the other. Each clash is listed in the migration report. Every file was copied, but the overwritten versions are not at the destination as separate files.</div>"
    }
    $tv = Lzb0b39673dd; $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    $now = Get-Date
    $refName = [System.IO.Path]::GetFileName($AuditPath)
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_enc $brand) - Migration Completion Certificate</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .cert{max-width:820px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:40px 44px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:18px}
 .logo{height:52px}
 .brandlogo{height:83px;border-radius:8px;margin-left:auto}
 h1{font-size:23px;margin:0;letter-spacing:.2px}
 .sub{color:#6b7280;font-size:13px;margin-top:3px}
 .statement{font-size:15px;line-height:1.65;margin:22px 0 6px}
 .cards{display:flex;flex-wrap:wrap;gap:12px;margin:18px 0}
 .card{flex:1;min-width:140px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:14px 16px}
 .card .v{font-size:24px;font-weight:700}
 .card .l{font-size:12px;color:#6b7280;margin-top:2px}
 .err{color:#B42318}
 h2{font-size:13px;margin:24px 0 8px;color:#374151;text-transform:uppercase;letter-spacing:.5px}
 ul{margin:6px 0;padding-left:20px;font-size:14px}
 li{margin:3px 0}
 .dim{color:#6b7280}
 .verify{background:#E7F7EF;border:1px solid #A6E9C5;color:#066A4B;padding:12px 16px;border-radius:8px;font-size:13px;line-height:1.55}
 .caveat{background:#FFF6EC;border:1px solid #F5C083;color:#B5460F;padding:12px 16px;border-radius:8px;font-size:13px;line-height:1.55;margin:14px 0}
 .sign{display:flex;gap:40px;margin-top:40px}
 .sig{flex:1}
 .sig .line{border-bottom:1px solid #9ca3af;height:40px}
 .sig .who{font-size:12px;color:#6b7280;margin-top:6px}
 footer{margin-top:30px;color:#9ca3af;font-size:11px;border-top:1px solid #e5e7eb;padding-top:12px}
 @media print{body{background:#fff;padding:0}.cert{border:none;box-shadow:none}}
</style></head><body><div class='cert'>
<header>$logoTag<div style='flex:1'><h1>Migration Completion Certificate</h1><div class='sub'>$(_enc $brand)$verSub</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
<p class='statement'>This certifies that the migration of data from <strong>$(_enc $script:SrcSysName)</strong>$(if($client){" for <strong>$(_enc $client)</strong>"}) to <strong>Microsoft 365 (SharePoint / OneDrive)</strong> was completed on <strong>$dateStr</strong>.</p>
$caveat
<div class='cards'>
 <div class='card'><div class='v'>$('{0:N0}' -f $present)</div><div class='l'>Files at the destination (size-checked at upload, or already there)</div></div>
 <div class='card'><div class='v'>$(Format-Bytes $presentBytes)</div><div class='l'>Total data</div></div>
 <div class='card'><div class='v'>$projects</div><div class='l'>$($script:SrcItemCap)s migrated</div></div>
 <div class='card'><div class='v $(if($withErrors){'err'})'>$($errors + $verifyFail)</div><div class='l'>Files needing attention</div></div>
</div>
<h2>Where the data now lives</h2>
<ul>$destList</ul>
<h2>How it was verified</h2>
<div class='verify'><b>Ordinary files:</b> each was checked as it was uploaded by comparing sizes; the stored size must equal the source size exactly.<br/><b>Office documents:</b> Microsoft 365 rewrites these on upload (it adds a document ID and metadata), so their size cannot be compared. For these the check confirms only that the upload completed and the file is stored.<br/><b>Files already at the destination:</b> matched by path and modified time, and left alone.<br/>Contents were not compared byte by byte. The complete per-file record is in the migration audit ($(_enc $refName)).</div>
$(try { $cx = Join-Path (Split-Path -Parent $AuditPath) (([System.IO.Path]::GetFileName($AuditPath)) -replace '^audit-','excluded-'); if (Test-Path -LiteralPath $cx) { $cxr = @(Import-Csv -LiteralPath $cx); if ($cxr.Count) { $cxf = @($cxr | Where-Object { "$($_.Kind)" -ne 'Folder' }).Count; $cxd = @($cxr | Where-Object { "$($_.Kind)" -eq 'Folder' }).Count; "<div class='verify'>By the operator's selection, $('{0:N0}' -f $cxf) file(s)$(if ($cxd) { " and $cxd folder(s)" }) in the $($script:SrcNounBare) were deliberately left out of this migration. They are listed in $(_enc ([System.IO.Path]::GetFileName($cx))).</div>" } } } catch {})
<div class='sign'>
 <div class='sig'><div class='line'></div><div class='who'>Migrated by (Liscaragh Software / delivery partner)</div></div>
 <div class='sig'><div class='line'></div><div class='who'>Accepted by (client)</div></div>
</div>
<footer>Issued $($now.ToString('dd MMM yyyy HH:mm')) by Liscaragh Migrate$verSub &middot; $(_enc (Get-ReportTimeNote)) &middot; Liscaragh Software &middot; www.liscaragh.com &middot; Audit reference: $(_enc $refName)</footer>
</div></body></html>
"@
    $outPath = Join-Path $Config.run.reportRoot ("certificate-" + $now.ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "Completion certificate written: $outPath"
    if ($script:GuiMode) { Write-Host ("##CHECKOUTCOME##|OK|completion certificate issued: " + [System.IO.Path]::GetFileName($outPath)) }
    return $outPath
}
function Invoke-DriftCheck {
    param($Config)
    Lz93fa3c46d9 -Config $Config -Stage 'api-drift'
    $mapPathD = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPathD)) {
        Write-MigrationLog ERROR "No mapping.csv found, so there is nothing to check. Set a destination and save the mapping first."
        if ($script:GuiMode) { Write-Host "##CHECKOUTCOME##|BAD|nothing was checked: this job has no saved mapping yet. Set a destination, then check for drift." }
        return
    }
    Connect-Destination -Config $Config
    $map = @(Import-Csv $mapPathD | Where-Object Action -eq 'MIGRATE')
    $base = @{}
    foreach ($af in @(Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue)) {
        foreach ($r in @(Import-AuditCsv $af.FullName)) {
            if ("$($r.Space)" -eq '(run)') { continue }
            if ("$($r.Status)" -notmatch '^(Copied|ZeroByte|Repaired|Skipped)') { continue }
            if (-not "$($r.DestPath)".Trim()) { continue }
            $k = "$($r.Space)|" + "$($r.DestPath)".ToLowerInvariant()
            $prev = $null; if ($base.ContainsKey($k)) { $prev = $base[$k] }
            if (-not $prev -or ("$($r.TimestampUtc)" -gt "$($prev.TimestampUtc)")) { $base[$k] = $r }
        }
    }
    if (-not $base.Count) {
        Write-MigrationLog WARN "No migrated files in this job's audit records yet - run an upload first, then check for drift."
        if ($script:GuiMode) { Write-Host "##CHECKOUTCOME##|WARN|nothing to compare yet: this job has no record of migrated files. Run an upload first, then check for drift." }
        return
    }
    $jobAuditIndex = @{}
    foreach ($bv in $base.Values) { $jobAuditIndex["$($bv.DestPath)".ToLowerInvariant()] = "$($bv.Space)" }
    $rows = New-Object System.Collections.Generic.List[object]
    $chg = 0; $del = 0; $add = 0; $addOther = 0
    $driftNotChecked = [System.Collections.Generic.List[string]]::new()
    $tol = [TimeSpan]::FromSeconds(5)
    $t = $map.Count; $i = 0
    $baseBySpace = @{}
    foreach ($bk in @($base.Keys)) {
        $bsp = "$bk".Split('|')[0]
        if (-not $baseBySpace.ContainsKey($bsp)) { $baseBySpace[$bsp] = New-Object System.Collections.Generic.List[string] }
        $baseBySpace[$bsp].Add("$bk")
    }
    foreach ($row in $map) {
        $i++; Lz3402e3c9c5 -Activity 'Drift check' -Status $row.Space -Current $i -Total $t | Out-Null; Lz883d31a1c9 -Phase 'Drift' -Space "$($row.Space)"
        if ($script:GuiMode) { Write-Host "##STATUS##|Checking [$($row.Space)] for changes at the destination since migration..." }
        try {
            $null = Resolve-DestinationDriveId -Config $Config -Row $row
            $inv = Get-DestinationInventory -Config $Config -Row $row -WithTimes
        } catch {
            Write-MigrationLog ERROR "  destination NOT reachable for [$($row.Space)], so it could not be checked for drift: $($_.Exception.Message)"
            $driftNotChecked.Add("$($row.Space)")
            continue
        }
        $effD = Join-SubPath $row.TargetSubFolder (Get-NestFolder $Config $row)
        $prefD = if ($effD) { ($effD -replace '\\','/').TrimEnd('/') + '/' } else { '' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $spKeys = if ("$($row.Space)".Contains('|')) { @($base.Keys | Where-Object { "$_".StartsWith("$($row.Space)|", [System.StringComparison]::OrdinalIgnoreCase) }) } elseif ($baseBySpace.ContainsKey("$($row.Space)")) { @($baseBySpace["$($row.Space)"]) } else { @() }
        foreach ($k in $spKeys) {
            $b = $base[$k]; $p = "$($b.DestPath)"
            $rel = $p
            if ($prefD -and $rel.StartsWith($prefD, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($prefD.Length) }
            [void]$seen.Add($rel)
            if (-not $inv.Paths.Contains($rel)) {
                $rows.Add([pscustomobject]@{ Space = $row.Space; Drift = 'Deleted'; Path = $p; Detail = "migrated $($b.TimestampLocal), no longer at the destination" })
                $del++; continue
            }
            $why = @()
            $auditSize = [int64]0; [void][int64]::TryParse("$($b.DestSizeBytes)", [ref]$auditSize)
            $liveSize = [int64]0; if ($inv.Sizes.ContainsKey($rel)) { $liveSize = [int64]$inv.Sizes[$rel] }
            if ($auditSize -gt 0 -and $liveSize -ne $auditSize) { $why += "size $auditSize -> $liveSize bytes" }
            $mig = $null; try { $mig = ([datetimeoffset]::Parse("$($b.TimestampUtc)", [System.Globalization.CultureInfo]::InvariantCulture)).UtcDateTime } catch {}
            if ($mig -and $inv.Times.ContainsKey($rel)) {
                $liveM = [datetime]$inv.Times[$rel]
                if (($liveM - $mig) -gt $tol) { $why += ("modified at the destination " + $liveM.ToString('yyyy-MM-dd HH:mm') + " UTC, after migration") }
            }
            if ($why.Count) {
                $rows.Add([pscustomobject]@{ Space = $row.Space; Drift = 'Changed'; Path = $p; Detail = ($why -join '; ') })
                $chg++
            }
        }
        foreach ($p in $inv.Paths) {
            if (-not $seen.Contains($p)) {
                $absP = (Join-SubPath $effD $p) -replace '\\','/'
                $owner = $jobAuditIndex["$absP".ToLowerInvariant()]
                if ($owner -and $owner -ne "$($row.Space)") { $addOther++; continue }
                $rows.Add([pscustomobject]@{ Space = $row.Space; Drift = 'Added'; Path = (Join-SubPath $effD $p); Detail = 'at the destination, not migrated by this job' })
                $add++
            }
        }
    }
    try { Write-Progress -Activity 'Drift check' -Completed } catch {}
    $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $csvPath = Join-Path $Config.run.reportRoot ("drift-" + $ts + ".csv")
    $rows | Protect-CsvRow | Export-Csv $csvPath -NoTypeInformation -Encoding UTF8
    if ($chg -gt 0) { Write-MigrationLog WARN "$chg file(s) CHANGED at the destination since migration. In plain terms: someone (or something) edited the migrated copy after this job placed it. Details: $csvPath" }
    if ($del -gt 0) { Write-MigrationLog WARN "$del migrated file(s) are GONE from the destination. They were placed by this job and have since been deleted or moved." }
    if ($add -gt 0) { Write-MigrationLog INFO "$add file(s) at the destination were not migrated by this job (added later, or already there before a merge)." }
    if ($addOther -gt 0) { Write-MigrationLog INFO "$addOther file(s) at the destination belong to another source mapped in this same job (a shared destination folder) - not counted as Added." }
    $ncD = (@($driftNotChecked) -join ', ')
    if ($driftNotChecked.Count) { Write-MigrationLog ERROR "Drift could NOT be checked for $($driftNotChecked.Count) $($script:SrcItem)(s) ($ncD): the destination could not be reached. This is not a clean result." }
    elseif (($chg + $del) -eq 0) { Write-MigrationLog OK "No drift at the destination: every file this job migrated is still there, unchanged since migration. This check reads the destination only; to see what is new or changed at the source, preview a Sync." }
    Write-DriftReport -Config $Config -Rows $rows -Changed $chg -Deleted $del -Added $add -BaselineCount $base.Count -NotChecked @($driftNotChecked)
    if ($script:GuiMode) {
        if ($driftNotChecked.Count)  { Write-Host "##CHECKOUTCOME##|BAD|could not check $($driftNotChecked.Count) $($script:SrcItem)(s) ($ncD): the destination could not be reached, so this is not a clean result. The reason is in the ERROR lines in the log below." }
        elseif (($chg + $del) -gt 0) { Write-Host "##CHECKOUTCOME##|WARN|the destination has drifted since migration: $chg changed, $del deleted, $add added. The drift report and CSV list every file." }
        else                         { Write-Host "##CHECKOUTCOME##|OK|no drift at the destination: every file this job migrated is still there, unchanged (destination only; preview a Sync for changes at the source).$(if ($add) { " $add file(s) there were not migrated by this job." })" }
    }
}
function Write-DriftReport {
    param($Config,$Rows,[int]$Changed,[int]$Deleted,[int]$Added,[int]$BaselineCount,$NotChecked)
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    if ($null -eq $Rows) { $Rows = @() } else { $Rows = [object[]]$Rows }
    if ($null -eq $NotChecked) { $NotChecked = @() } else { $NotChecked = [object[]]$NotChecked }
    if ($NotChecked.Count) {
        $bStyle='background:#FEF3F2;border:1px solid #FDA29B;color:#B42318'
        $bTitle='This drift check could not be completed.'
        $bExtra=" The destination could not be reached for: $(($NotChecked) -join ', '). Nothing is known about drift there, so this is not a clean result. $Changed changed, $Deleted deleted, $Added added in the rest."
    } elseif (($Changed + $Deleted) -gt 0) {
        $bStyle='background:#FFFAEB;border:1px solid #FEDF89;color:#B5460F'
        $bTitle='The destination has drifted since migration.'
        $bExtra=" $Changed changed, $Deleted deleted, $Added added since this job migrated. The list below is the evidence for any 'the migration lost my edits' conversation: it shows exactly what moved after the migration finished."
    } else {
        $bStyle='background:#E7F7EF;border:1px solid #86D9B4;color:#066A4B'
        $bTitle='No drift at the destination.'
        $bExtra=" Every one of the $('{0:N0}' -f [int64]$BaselineCount) migrated file(s) is still at the destination, unchanged since migration.$(if ($Added -gt 0) { " $Added file(s) exist there that this job never migrated - listed below for completeness." })"
    }
    $bExtra += " This check reads the destination only. To see what is new or changed at the source, preview a Sync."
    $banner = "<div style='$bStyle;border-radius:8px;padding:14px 16px;margin:0 0 18px;font-size:14px'><strong>$(_enc $bTitle)</strong>$(_enc $bExtra)</div>"
    $sec = ''
    foreach ($kind in 'Changed','Deleted','Added') {
        $sub = @($Rows | Where-Object Drift -eq $kind)
        if (-not $sub.Count) { continue }
        $rr = ''
        foreach ($x in @($sub | Select-Object -First 500)) { $rr += "<tr><td>$(_enc $x.Space)</td><td>$(_enc $x.Path)</td><td class='dim'>$(_enc $x.Detail)</td></tr>`n" }
        $cap = if ($sub.Count -gt 500) { "<p class='dim'>Showing the first 500 of $($sub.Count); all are in the drift CSV.</p>" } else { '' }
        $note = if ($kind -eq 'Added') { "<p class='dim'>In a destination that already held content before a merge, this bucket includes those pre-existing files - it means 'not placed by this job', not necessarily 'new'.</p>" } else { '' }
        $sec += "<h2>$kind ($($sub.Count))</h2>$note<table><thead><tr><th>$($script:SrcItemCap)</th><th>File</th><th>Detail</th></tr></thead><tbody>$rr</tbody></table>$cap"
    }
    if (-not $sec -and $NotChecked.Count) { $sec = "<p class='dim'>Nothing was found to have changed in the part that could be read. Not read, so nothing is known about: $(_enc (($NotChecked) -join ', ')).</p>" }
    elseif (-not $sec) { $sec = "<p class='okbox'>Nothing changed, nothing deleted, nothing added. The destination is exactly as this job left it.</p>" }
    $body = @"
<div class='cards'>
 <div class='card'><div class='v'>$('{0:N0}' -f [int64]$BaselineCount)</div><div class='l'>Migrated files tracked</div></div>
 <div class='card'><div class='v $(if($Changed -gt 0){'warnc'})'>$('{0:N0}' -f [int64]$Changed)</div><div class='l'>Changed since</div></div>
 <div class='card'><div class='v $(if($Deleted -gt 0){'err'})'>$('{0:N0}' -f [int64]$Deleted)</div><div class='l'>Deleted since</div></div>
 <div class='card'><div class='v'>$('{0:N0}' -f [int64]$Added)</div><div class='l'>Added since</div></div>
</div>
$sec
<p class='dim'>How this decides: the audit record of every migrated file (size and migration moment) against the destination as it is right now. A later modified time or a different size means the copy was touched after migration. Read-only on both sides.</p>
"@
    $html = Lzab15d9452a -Config $Config -Subtitle 'Destination drift (changes since migration)' -Banner $banner -Body $body
    $outPath = Join-Path $Config.run.reportRoot ("report-drift-" + (Get-Date).ToString('yyyyMMdd-HHmmss') + ".html")
    Set-Content -Path $outPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "Drift report written: $outPath"
}
function Invoke-Validate {
    param($Config)
    Lz93fa3c46d9 -Config $Config -Stage 'api-validation'
    $script:ExcludedFile = $null; Lzc9d8fe4f48
    $ckStart = Get-Date
    Lz1338c7e606 -Config $Config
    Connect-Destination -Config $Config
    $map = @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')
    foreach ($old in 'api-validation-missing.csv','api-validation-stale.csv') { try { Remove-Item -LiteralPath (Join-Path $Config.run.reportRoot $old) -Force -ErrorAction SilentlyContinue } catch {} }
    $report = New-Object System.Collections.Generic.List[object]
    $missingAll = New-Object System.Collections.Generic.List[object]
    $staleAll = New-Object System.Collections.Generic.List[object]
    $notChecked = New-Object System.Collections.Generic.List[object]
    $sanitise = (((Test-ConfigProp $Config.run 'sanitiseNames')) -and $Config.run.sanitiseNames)
    $tol = [TimeSpan]::FromSeconds(2)
    $jobAuditIndex = @{}
    try {
        foreach ($af in @(Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -ErrorAction SilentlyContinue)) {
            foreach ($ar in @(Import-AuditCsv $af.FullName)) {
                if ("$($ar.Space)" -eq '(run)') { continue }
                if ("$($ar.Status)" -notmatch '^(Copied|ZeroByte|Repaired|Skipped)') { continue }
                $dp = "$($ar.DestPath)".Trim(); if (-not $dp) { continue }
                $jobAuditIndex[$dp.ToLowerInvariant()] = "$($ar.Space)"
            }
        }
    } catch {}
    $t = $map.Count; $i = 0
    foreach ($row in $map) {
        $i++; Lz3402e3c9c5 -Activity 'Verify' -Status $row.Space -Current $i -Total $t | Out-Null; Lz883d31a1c9 -Phase 'Verify' -Space "$($row.Space)"
        if ($script:GuiMode) { Write-Host "##STATUS##|Verifying files arrived in [$($row.Space)]: checking each is present and up to date..." }
        try {
            $null = Resolve-DestinationDriveId -Config $Config -Row $row
            Write-MigrationLog OK "  destination reachable: $(Get-RowDestLabel $row). Reading the source now."
        } catch {
            Write-MigrationLog ERROR "  destination NOT reachable for [$($row.Space)], so the source was not read: $($_.Exception.Message)"
            $notChecked.Add([pscustomobject]@{ Space = $row.Space; Reason = "destination not reachable: $($_.Exception.Message)" })
            $report.Add([pscustomobject]@{ Space=$row.Space; SourceFiles=0; Present=0; Missing=0; OutOfDate=0; ExtraAtDest=0; DestFiles=0; Verdict='NOT CHECKED' })
            continue
        }
        $space = New-SpaceRef -Row $row -Config $Config
        $dj = Lzef890b1d1f -Config $Config -Row $row
        try {
            $items = @(Get-DattoItems -Config $Config -Space $space)
        } catch {
            Write-MigrationLog ERROR "  could not read files for '$($row.Space)': $($_.Exception.Message). In plain terms: the source may be empty, moved, or unreachable. It could NOT be verified, so this check cannot pass."
            $notChecked.Add([pscustomobject]@{ Space = $row.Space; Reason = "source not readable: $($_.Exception.Message)" })
            $report.Add([pscustomobject]@{ Space=$row.Space; SourceFiles=0; Present=0; Missing=0; OutOfDate=0; ExtraAtDest=0; DestFiles=0; Verdict='NOT CHECKED' })
            $null = Receive-DestInventoryJob -Config $Config -Row $row -Job $dj -WithTimes
            continue
        }
        $srcCount = $items.Count
        $inv = Receive-DestInventoryJob -Config $Config -Row $row -Job $dj -WithTimes
        $missing = New-Object System.Collections.Generic.List[string]
        $missSz = @{}
        $stale = New-Object System.Collections.Generic.List[string]
        foreach ($it in $items) {
            $rp = $it.RelativePath -replace '\\','/'
            if ($sanitise) { $rp = ConvertTo-SafeRelPath $rp }
            if (-not $inv.Paths.Contains($rp)) { $missing.Add($it.RelativePath); $missSz["$($it.RelativePath)"] = [int64]$it.Size; continue }
            $st = ConvertTo-UtcDate $it.ModifiedUtc
            $dt = if ($inv.Times.ContainsKey($rp)) { $inv.Times[$rp] } else { $null }
            if ($null -ne $st -and $null -ne $dt -and $st -gt $dt.Add($tol)) {
                $stale.Add($it.RelativePath)
                Write-MigrationLog INFO "      out-of-date check: $($it.RelativePath) - source $($st.ToString('o')) vs destination $($dt.ToString('o')) (tolerance $($tol.TotalSeconds)s)"
            }
        }
        $present = $srcCount - $missing.Count
        $rawExtra = [math]::Max($inv.Count - $present, 0)
        $otherSourceCount = 0
        if ($jobAuditIndex.Count -and $rawExtra -gt 0) {
            $srcSetForRow = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($it2 in $items) { $rp2 = $it2.RelativePath -replace '\\','/'; if ($sanitise) { $rp2 = ConvertTo-SafeRelPath $rp2 }; [void]$srcSetForRow.Add($rp2) }
            $effD = Join-SubPath $row.TargetSubFolder (Get-NestFolder $Config $row)
            foreach ($dp in $inv.Paths) {
                if ($srcSetForRow.Contains("$dp")) { continue }
                $absP = (Join-SubPath $effD "$dp") -replace '\\','/'
                $owner = $jobAuditIndex[$absP.ToLowerInvariant()]
                if ($owner -and $owner -ne "$($row.Space)") { $otherSourceCount++ }
            }
        }
        $extra = [math]::Max($rawExtra - $otherSourceCount, 0)
        $verdict = if ($missing.Count -gt 0) { 'FAIL' } elseif ($stale.Count -gt 0) { 'OUT OF DATE' } else { 'PASS' }
        foreach ($m in $missing) { $missingAll.Add([pscustomobject]@{ Space = $row.Space; MissingFile = $m; SizeBytes = [int64]$missSz["$m"] }) }
        foreach ($s in $stale)   { $staleAll.Add([pscustomobject]@{ Space = $row.Space; StaleFile = $s }) }
        $report.Add([pscustomobject]@{
            Space=$row.Space; SourceFiles=$srcCount; Present=$present; Missing=$missing.Count
            OutOfDate=$stale.Count; ExtraAtDest=$extra; DestFiles=$inv.Count; Verdict=$verdict
        })
        $extraNote = if ($extra -gt 0) { " The destination also holds $extra other file(s) not from this source (content that was there before the migration); that is expected." } else { '' }
        if ($verdict -eq 'PASS') {
            Write-MigrationLog OK "  $($row.Space): PASS - all $srcCount file(s) are present and up to date at the destination.$extraNote"
        } elseif ($verdict -eq 'OUT OF DATE') {
            Write-MigrationLog WARN "  $($row.Space): OUT OF DATE - all $srcCount file(s) are present, but $($stale.Count) have a newer version in $($script:SrcNounBare) than at the destination (see api-validation-stale.csv). In plain terms: those files were changed in $($script:SrcNounBare) since they were copied. Run 'Sync new and changed' with 'Update where $($script:SrcNounBare) is newer' to bring them up to date."
        } else {
            Write-MigrationLog ERROR "  $($row.Space): FAIL - $($missing.Count) of $srcCount file(s) were NOT found at the destination (see api-validation-missing.csv).$(if($stale.Count){" $($stale.Count) present file(s) are also out of date."}) In plain terms: some files did not make it across. Run 'Sync new and changed' to copy them, then verify again."
            foreach ($m in @($missing | Select-Object -First 15)) { Write-MigrationLog ERROR "      missing: /$m" }
            if ($missing.Count -gt 15) { Write-MigrationLog ERROR "      ... and $('{0:N0}' -f ($missing.Count - 15)) more, all named in api-validation-missing.csv." }
        }
    }
    try { Write-Progress -Activity 'Verify' -Completed } catch {}
    $report | Protect-CsvRow | Export-Csv -Path (Join-Path $Config.run.reportRoot 'api-validation-report.csv') -NoTypeInformation -Encoding UTF8
    $checkedRows = @($report | Where-Object Verdict -ne 'NOT CHECKED').Count
    $unchecked = $notChecked.Count
    if ($checkedRows -eq 0 -and $unchecked -eq 0) { $notChecked.Add([pscustomobject]@{ Space = '(none)'; Reason = 'no mapped project could be checked' }); $unchecked = 1 }
    try { Write-ValidationReport -Config $Config -Report $report -Missing $missingAll -Stale $staleAll -NotChecked $notChecked } catch { Write-MigrationLog WARN "Verify report could not be written: $($_.Exception.Message)" }
    if ($missingAll.Count) {
        $missingAll | Protect-CsvRow | Export-Csv -Path (Join-Path $Config.run.reportRoot 'api-validation-missing.csv') -NoTypeInformation -Encoding UTF8
        if ($script:GuiMode) { Write-Host "##CHECKFILES##|$($missingAll.Count)|0|0|$(Join-Path $Config.run.reportRoot 'api-validation-missing.csv')" }
    }
    if ($staleAll.Count) {
        $staleAll | Protect-CsvRow | Export-Csv -Path (Join-Path $Config.run.reportRoot 'api-validation-stale.csv') -NoTypeInformation -Encoding UTF8
        if ($script:GuiMode) { Write-Host "##CHECKFILES##|0|0|$($staleAll.Count)|$(Join-Path $Config.run.reportRoot 'api-validation-stale.csv')" }
    }
    $fail  = @($report | Where-Object Verdict -eq 'FAIL').Count
    $stalep = @($report | Where-Object Verdict -eq 'OUT OF DATE').Count
    $ncText = (@($notChecked | ForEach-Object { "$($_.Space)" }) -join ', ')
    if ($unchecked -gt 0) { Write-MigrationLog ERROR "Verify could NOT check $unchecked project(s) ($ncText): the destination could not be reached or the source could not be read, so nothing is known about whether their files arrived. This is not a pass.$(if ($fail -gt 0) { " Separately, $fail project(s) have missing files (see api-validation-missing.csv)." }) Fix the source or destination named in the ERROR lines above, then verify again." }
    elseif ($fail -gt 0) { Write-MigrationLog ERROR "Verify complete. $fail project(s) have missing files (see api-validation-missing.csv). Run 'Sync new and changed' to re-copy them, then verify again." }
    elseif ($stalep -gt 0) { Write-MigrationLog WARN "Verify complete. Everything is present, but $stalep project(s) have file(s) that are newer in $($script:SrcNounBare) than at the destination (see api-validation-stale.csv). Run 'Sync new and changed' with 'Update where $($script:SrcNounBare) is newer' to refresh them." }
    else { Write-MigrationLog OK "Verify complete. Every file is present at the destination and up to date (no file is newer in $($script:SrcNounBare)). Extra files already in the destination are expected and were ignored." }
    if ($script:GuiMode) {
        if ($unchecked -gt 0)  { Write-Host "##CHECKOUTCOME##|BAD|could not check $unchecked project(s) ($ncText): the destination could not be reached or the source could not be read, so this is NOT a pass. The reason is in the ERROR lines in the log below. Fix it, then verify again." }
        elseif ($fail -gt 0)   { Write-Host "##CHECKOUTCOME##|BAD|found a problem: $('{0:N0}' -f $missingAll.Count) file(s) are MISSING at the destination across $fail project(s). They are named in the log below and in api-validation-missing.csv. Click 'Sync new and changed' to copy them, then verify again." }
        elseif ($stalep -gt 0) { Write-Host "##CHECKOUTCOME##|WARN|everything is present, but $('{0:N0}' -f $staleAll.Count) file(s) are newer in $($script:SrcNounBare) than at the destination (api-validation-stale.csv names them). Run 'Sync new and changed' with 'Update where $($script:SrcNounBare) is newer' to refresh them." }
        else                   { Write-Host "##CHECKOUTCOME##|OK|every file is present at the destination and up to date." }
    }
    try {
        $emVerdict = if ($unchecked -gt 0 -or $fail -gt 0) { 'BAD' } elseif ($stalep -gt 0) { 'WARN' } else { 'OK' }
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
                "Could not be checked: $unchecked project(s)$(if ($unchecked) { " ($ncText)" })",
                "Missing at destination: $('{0:N0}' -f $missingAll.Count)",
                "Newer in $($script:SrcNounBare) (out of date at destination): $('{0:N0}' -f $staleAll.Count)",
                "Source: $($emVars['Source'])",
                "Destination: $($emVars['Destination'])")
    } catch {}
}
function Lz5d185e24df {
    param($Config)
    Lz93fa3c46d9 -Config $Config -Stage 'api-permissions'
    Lz1338c7e606 -Config $Config
    $map = @(Import-Csv (Join-Path $Config.run.reportRoot 'mapping.csv') | Where-Object Action -eq 'MIGRATE')
    function Lz6bc74a6888 { param([string]$r) switch -Regex ($r.ToLower()) { 'owner|manage|admin'{'Site Owner (Full Control)';break} 'edit|write|contrib'{'Member (Edit)';break} 'view|read'{'Visitor (Read)';break} default{'REVIEW'} } }
    $plan = New-Object System.Collections.Generic.List[object]
    $t = $map.Count; $i = 0
    foreach ($row in $map) {
        $i++; Lz3402e3c9c5 -Activity 'Permissions' -Status $row.Space -Current $i -Total $t | Out-Null
        $space = New-SpaceRef -Row $row -Config $Config
        foreach ($p in @(Lz97c85d70a8 -Config $Config -Space $space)) {
            $plan.Add([pscustomobject]@{ Space=$row.Space; Principal=$p.Principal; DattoRole=$p.Role; DestinationUrl=$row.DestinationUrl; ProposedM365Role=(Lz6bc74a6888 $p.Role) })
        }
    }
    try { Write-Progress -Activity 'Permissions' -Completed } catch {}
    $out = Join-Path $Config.run.reportRoot 'api-permissions-plan.csv'
    $plan | Protect-CsvRow | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
    if ($plan.Count -eq 0) { Write-MigrationLog WARN "No permissions returned by the API (endpoint may not be configured). $out is empty." }
    else { Write-MigrationLog OK "Permissions plan written (NOT applied): $($plan.Count) entries. $out" }
}
function Invoke-SourceReview {
    param($Config, [switch]$NoStageLog)
    if (-not $NoStageLog) { Lz93fa3c46d9 -Config $Config -Stage 'api-sourcereview' }
    $started = Get-Date
    $isSim = ($Config.datto.provider -eq 'LocalSim')
    if (-not $isSim) { Lz1338c7e606 -Config $Config }
    function _raw { param($o, [string]$n) if ($null -ne $o -and ((Test-ConfigProp $o $n))) { return $o.$n }; return $null }
    function Lz27735fbdfc { param($ms) try { $v = [int64]$ms; if ($v -gt 0) { $x = if ($v -gt 100000000000) { $v } else { $v * 1000 }; return [DateTimeOffset]::FromUnixTimeMilliseconds($x).UtcDateTime.ToString('dd MMM yyyy HH:mm') } } catch {}; return '' }
    $nodes = New-Object System.Collections.Generic.List[object]
    $suspects = [System.Collections.Generic.List[object]]::new()
    $stats = @{ Projects = 0; Folders = 0; Files = 0; Calls = 0; Pub = 0; Locked = 0; NotReady = 0 }
    function Lzdc2c8a77ec { param([string]$Space, [string]$Path, [string]$Kind, $Pub, $Link, $By, [int64]$Size, [string]$ModUtc, $Locked, [string]$LockName, [string]$LockEmail, [string]$LockSince, $NotReady, [string]$ReadyReason)
        $nodes.Add([pscustomobject]@{
            Space = $Space; Path = $Path; Kind = $Kind
            IsPublic = [bool]$Pub; Link = "$Link"; ChangedBy = "$By"; SizeBytes = $Size; ModifiedUtc = $ModUtc
            IsLocked = [bool]$Locked; LockName = "$LockName"; LockEmail = "$LockEmail"; LockSince = "$LockSince"
            NotReady = [bool]$NotReady; ReadyReason = "$ReadyReason"
        })
    }
    if ($isSim) {
        foreach ($sp in @(Get-DattoSpaces -Config $Config)) {
            $stats.Projects++
            Lzdc2c8a77ec -Space $sp.Name -Path '' -Kind 'Project' -Pub $false -Link '' -By '' -Size 0 -ModUtc '' -Locked $false -LockName '' -LockEmail '' -LockSince '' -NotReady $false -ReadyReason ''
            foreach ($e in @(Get-ChildItem -LiteralPath $sp.Id -Recurse -Force -ErrorAction SilentlyContinue)) {
                $rel = $e.FullName.Substring($sp.Id.Length).TrimStart('\', '/') -replace '\\', '/'
                $pub = ($e.Name -like '*~PUBLIC~*'); $lck = ($e.Name -like '*~LOCKED~*'); $off = ($e.Name -like '*~OFFLINE~*')
                if ($pub) { $stats.Pub++ }
                if ($e.PSIsContainer) {
                    $stats.Folders++
                    Lzdc2c8a77ec -Space $sp.Name -Path $rel -Kind 'Folder' -Pub $pub -Link '' -By '' -Size 0 -ModUtc '' -Locked $false -LockName '' -LockEmail '' -LockSince '' -NotReady $false -ReadyReason ''
                } else {
                    $stats.Files++
                    if ($lck) { $stats.Locked++ }
                    if ($off) { $stats.NotReady++ }
                    Lzdc2c8a77ec -Space $sp.Name -Path $rel -Kind 'File' -Pub $pub -Link '' -By 'Sim User' -Size ([int64]$e.Length) -ModUtc ($e.LastWriteTimeUtc.ToString('o')) `
                        -Locked $lck -LockName $(if ($lck) { 'Sim Locker' } else { '' }) -LockEmail $(if ($lck) { 'lock@example.com' } else { '' }) -LockSince $(if ($lck) { '01 Jan 2026 09:00' } else { '' }) `
                        -NotReady $off -ReadyReason $(if ($off) { 'not fully stored in the cloud' } else { '' })
                }
            }
        }
    } else {
        $f = $Config.datto.fields
        $q = @{ metadata = 'sjGOS' }
        $unwrap = { param($resp) if ($resp -is [System.Array]) { $resp } elseif ($f.collection -and ((Test-ConfigProp $resp $f.collection))) { $resp.($f.collection) } else { $resp } }
        $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
        $mapRows = @()
        if (Test-Path $mapPath) { $mapRows = @(Import-Csv $mapPath | Where-Object { "$($_.Action)" -eq 'MIGRATE' }) }
        if (-not $mapRows.Count) { Write-MigrationLog WARN "Source review: no folders are selected for this job (no MIGRATE rows in mapping.csv). Nothing to scan." }
        else { Write-MigrationLog INFO "Source review: $($mapRows.Count) folder(s) in this job to scan (metadata=$($q.metadata))." }
        function Lzf362a1d40a { param($it, [string]$SpaceName, [string]$Rel, [bool]$IsFolder)
            $pub = $false; try { $pub = [bool](_raw $it 'isPublicLink') } catch {}
            $link = ''; if ($pub) { $link = "$(_raw $it 'fileLink')" }
            $by = "$(_raw $it 'changedByUserName')"
            $lockObj = _raw $it 'lock'
            $locked = ($null -ne $lockObj -and "$lockObj".Trim() -ne '')
            $ln = ''; $le = ''; $ls = ''
            if ($locked) { $ln = "$(_raw $lockObj 'fullname')"; $le = "$(_raw $lockObj 'email')"; $ls = Lz27735fbdfc (_raw $lockObj 'lockedSince') }
            $notReady = $false; $reason = ''
            if (-not $IsFolder) {
                $stored = _raw $it 'stored'; $online = _raw $it 'online'
                if ($null -ne $stored -and -not [bool]$stored) { $notReady = $true; $reason = 'not fully stored in the cloud' }
                elseif ($null -ne $online -and -not [bool]$online) { $notReady = $true; $reason = 'not currently available for download' }
            }
            $size = 0; if (-not $IsFolder) { try { $size = [int64]$it.($f.itemSize) } catch {} }
            $mod = ''
            try { $t = [int64]$it.($f.itemTime); if ($t -gt 0) { $ms = if ($t -gt 100000000000) { $t } else { $t * 1000 }; $mod = [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime.ToString('o') } } catch {}
            if ($pub) { $stats.Pub++ }
            if ($locked) { $stats.Locked++ }
            if ($notReady) { $stats.NotReady++ }
            Lzdc2c8a77ec -Space $SpaceName -Path $Rel -Kind $(if ($IsFolder) { 'Folder' } else { 'File' }) -Pub $pub -Link $link -By $by -Size $size -ModUtc $mod `
                -Locked $locked -LockName $ln -LockEmail $le -LockSince $ls -NotReady $notReady -ReadyReason $reason
        }
        function Lzfecf00344a { param($ParentId, [string]$SpaceName, [string]$Prefix)
            $childPath = ($Config.datto.apiPaths.listChildren -replace '\{parentID\}', [uri]::EscapeDataString("$ParentId"))
            $resp = Invoke-DattoApi -Config $Config -Path $childPath -Query $q
            $stats.Calls++
            $items = @(& $unwrap $resp)
            if ($items.Count -gt 0 -and (@(100, 200, 250, 500, 1000, 2000, 5000) -contains $items.Count)) {
                $suspects.Add([pscustomobject]@{ Space = $SpaceName; Path = $(if ($Prefix) { $Prefix } else { '(root)' }); Count = $items.Count })
            }
            foreach ($it in $items) {
                $name = $it.($f.itemName)
                $rel = if ($Prefix) { "$Prefix/$name" } else { "$name" }
                $isFolder = $false; try { $isFolder = [bool]$it.($f.itemFolder) } catch {}
                if ($isFolder) {
                    $stats.Folders++
                    Lzf362a1d40a -it $it -SpaceName $SpaceName -Rel $rel -IsFolder $true
                    Lzfecf00344a -ParentId $it.($f.itemId) -SpaceName $SpaceName -Prefix $rel
                } else {
                    $stats.Files++
                    Lzf362a1d40a -it $it -SpaceName $SpaceName -Rel $rel -IsFolder $false
                }
                if ($script:GuiMode -and ((($stats.Folders + $stats.Files) % 250) -eq 0)) {
                    Write-Host "##STATUS##|Source review: $('{0:N0}' -f $stats.Folders) folders, $('{0:N0}' -f $stats.Files) files - $($stats.Pub) public, $($stats.Locked) locked, $($stats.NotReady) not cloud-ready"
                }
            }
        }
        $si = 0
        foreach ($row in $mapRows) {
            $si++
            $sp = New-SpaceRef -Row $row -Config $Config
            Lz3402e3c9c5 -Activity 'Source review' -Status $sp.Name -Current $si -Total $mapRows.Count | Out-Null
            if ($script:GuiMode) { Write-Host "##STATUS##|Source review: scanning folder $si of $($mapRows.Count) ('$($sp.Name)')" }
            $stats.Projects++
            Lzdc2c8a77ec -Space $sp.Name -Path '' -Kind 'Project' -Pub $false -Link '' -By '' -Size 0 -ModUtc '' -Locked $false -LockName '' -LockEmail '' -LockSince '' -NotReady $false -ReadyReason ''
            $startId = $sp.Id; $seedPrefix = ''
            if ($sp.SubPath) {
                try { $startId = Resolve-DattoSubPath -Config $Config -Space $sp -SubPath $sp.SubPath }
                catch { Write-MigrationLog WARN "  could not resolve subfolder '$($sp.SubPath)' in '$($sp.Name)'; skipping it."; continue }
                if (-not $sp.ContentsOnly) { $seedPrefix = $sp.SubPath }
            }
            Lzfecf00344a -ParentId $startId -SpaceName $sp.Name -Prefix $seedPrefix
        }
        try { Write-Progress -Activity 'Source review' -Completed } catch {}
    }
    $finished = Get-Date
    $publics = @($nodes | Where-Object IsPublic | Sort-Object Space, Path)
    $locks = @($nodes | Where-Object IsLocked | Sort-Object Space, Path)
    $notReady = @($nodes | Where-Object NotReady | Sort-Object Space, Path)
    Write-MigrationLog OK "Source review: $($stats.Projects) folder(s), $('{0:N0}' -f $stats.Folders) subfolder(s), $('{0:N0}' -f $stats.Files) file(s) scanned; $($publics.Count) public link(s), $($locks.Count) locked file(s), $($notReady.Count) not cloud-ready."
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $csvPath = Join-Path $Config.run.reportRoot ("source-review-" + $ts + ".csv")
    $csvRows = New-Object System.Collections.Generic.List[object]
    foreach ($x in $publics) { $csvRows.Add([pscustomobject]@{ Finding = 'Public link'; Space = $x.Space; Path = $(if ($x.Path) { $x.Path } else { '(the folder itself)' }); Kind = $x.Kind; Detail = $x.Link; ChangedBy = $x.ChangedBy; SizeBytes = $x.SizeBytes; ModifiedUtc = $x.ModifiedUtc }) }
    foreach ($x in $locks) { $csvRows.Add([pscustomobject]@{ Finding = 'Locked'; Space = $x.Space; Path = $x.Path; Kind = $x.Kind; Detail = ("locked by $($x.LockName) <$($x.LockEmail)> since $($x.LockSince)"); ChangedBy = $x.ChangedBy; SizeBytes = $x.SizeBytes; ModifiedUtc = $x.ModifiedUtc }) }
    foreach ($x in $notReady) { $csvRows.Add([pscustomobject]@{ Finding = 'Not cloud-ready'; Space = $x.Space; Path = $x.Path; Kind = $x.Kind; Detail = $x.ReadyReason; ChangedBy = $x.ChangedBy; SizeBytes = $x.SizeBytes; ModifiedUtc = $x.ModifiedUtc }) }
    if ($csvRows.Count) { $csvRows | Protect-CsvRow | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 }
    else { 'Finding,Space,Path,Kind,Detail,ChangedBy,SizeBytes,ModifiedUtc' | Set-Content -Path $csvPath -Encoding UTF8 }
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    $brand = 'Liscaragh Migrate'
    if (((Test-ConfigProp $Config.run 'report')) -and ((Test-ConfigProp $Config.run.report 'brand')) -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
    $now = Get-Date
    $tv = Lzb0b39673dd; $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    $durS = [int]($finished - $started).TotalSeconds
    $dur = if ($durS -ge 60) { "{0}m {1}s" -f [int][math]::Floor($durS / 60), ($durS % 60) } else { "${durS}s" }
    $scanned = $stats.Folders + $stats.Files
    $nPub = $publics.Count; $nLock = $locks.Count; $nNR = $notReady.Count
    $totalFindings = $nPub + $nLock + $nNR
    $verdict = if ($totalFindings -eq 0) {
        "<div class='banner ok'><b>Nothing flagged.</b> Across the $($stats.Projects) folder(s) in this job ($('{0:N0}' -f $scanned) item(s)), no public links, no locked files and no files that are not yet in the cloud were found.</div>"
    } else {
        $bits = @()
        if ($nPub) { $bits += "$nPub public link(s)" }
        if ($nLock) { $bits += "$nLock locked file(s)" }
        if ($nNR) { $bits += "$nNR file(s) not yet in the cloud" }
        "<div class='banner bad'><b>$totalFindings item(s) to review before migrating.</b> Found $($bits -join ', '). See the sections below.</div>"
    }
    function Lz68e1abed75 { param($v, $l, [bool]$hot) "<div class='tile$(if ($hot) { ' hot' })'><div class='v'>$v</div><div class='l'>$l</div></div>" }
    $tiles = (Lz68e1abed75 $stats.Projects 'Folders in job' $false) + (Lz68e1abed75 ('{0:N0}' -f $stats.Folders) 'Subfolders scanned' $false) + (Lz68e1abed75 ('{0:N0}' -f $stats.Files) 'Files scanned' $false) + (Lz68e1abed75 $nPub 'Public links' ($nPub -gt 0)) + (Lz68e1abed75 $nLock 'Locked files' ($nLock -gt 0)) + (Lz68e1abed75 $nNR 'Not cloud-ready' ($nNR -gt 0)) + (Lz68e1abed75 $dur 'Scan time' $false)
    $plRows = ''
    foreach ($x in $publics) {
        $itemTxt = if ($x.Path) { $x.Path } else { '(the folder itself)' }
        $sizeTxt = if ($x.Kind -eq 'File') { Format-Bytes ([int64]$x.SizeBytes) } else { '' }
        $linkCell = if ($x.Link) { "<a href='$(_enc $x.Link)' rel='noopener'>$(_enc $x.Link)</a>" } else { "<span class='dim'>(link not returned)</span>" }
        $plRows += "<tr><td>$(_enc $x.Space)</td><td class='pth'>$(_enc $itemTxt)</td><td class='n'>$(_enc $x.Kind)</td><td class='lnk'>$linkCell</td><td>$(_enc $x.ChangedBy)</td><td class='n'>$sizeTxt</td></tr>`n"
    }
    $plSection = if ($nPub -eq 0) { "<p class='okbox'>No project, subfolder or file in this job is shared by a public link.</p>" }
                 else { "<table><thead><tr><th>Folder</th><th>Item</th><th class='n'>Type</th><th>Public link</th><th>Last changed by</th><th class='n'>Size</th></tr></thead><tbody>$plRows</tbody></table>" }
    $treeSection = ''
    foreach ($g in @($publics | Group-Object Space)) {
        $rows = ''
        foreach ($x in @($g.Group | Sort-Object Path)) {
            $depth = if ($x.Path) { @($x.Path -split '/').Count } else { 0 }
            $label = if ($x.Path) { ($x.Path -split '/')[-1] } else { "$($g.Name) (the folder itself)" }
            $chain = if ($x.Path -and $x.Path.Contains('/')) { $x.Path.Substring(0, $x.Path.LastIndexOf('/')) } else { '' }
            $rows += "<div class='tnode' style='padding-left:$((14 * $depth))px'><span class='tkind'>$(_enc $x.Kind)</span> <b>$(_enc $label)</b>$(if ($chain) { " <span class='dim'>in $(_enc $chain)</span>" })<br/><span class='turl'><a href='$(_enc $x.Link)' rel='noopener'>$(_enc $x.Link)</a></span></div>`n"
        }
        $treeSection += "<details open><summary><b>$(_enc $g.Name)</b> &middot; $($g.Count) public link(s)</summary><div class='tree'>$rows</div></details>`n"
    }
    $lkRows = ''
    foreach ($x in $locks) {
        $lkRows += "<tr><td>$(_enc $x.Space)</td><td class='pth'>$(_enc $x.Path)</td><td>$(_enc $x.LockName)</td><td>$(_enc $x.LockEmail)</td><td class='n'>$(_enc $x.LockSince)</td><td class='n'>$(Format-Bytes ([int64]$x.SizeBytes))</td></tr>`n"
    }
    $lkSection = if ($nLock -eq 0) { "<p class='okbox'>No files in this job are locked. A locked file can still be copied, but the person holding the lock is mid-edit, so co-ordinate cutover with them.</p>" }
                 else { "<p>These files are locked in Datto Workplace. They still migrate, but the lock means someone is actively editing, so confirm they are finished before the final sync.</p><table><thead><tr><th>Folder</th><th>File</th><th>Locked by</th><th>Email</th><th class='n'>Since</th><th class='n'>Size</th></tr></thead><tbody>$lkRows</tbody></table>" }
    $nrRows = ''
    foreach ($x in $notReady) {
        $nrRows += "<tr><td>$(_enc $x.Space)</td><td class='pth'>$(_enc $x.Path)</td><td>$(_enc $x.ReadyReason)</td><td>$(_enc $x.ChangedBy)</td><td class='n'>$(Format-Bytes ([int64]$x.SizeBytes))</td></tr>`n"
    }
    $nrSection = if ($nNR -eq 0) { "<p class='okbox'>Every file in this job reports as fully stored in the cloud and available to download.</p>" }
                 else { "<p class='note'>These files are not fully in Datto's cloud yet (still uploading from a desktop, or archived). A migration downloads from the cloud, so these can fail or copy an incomplete version. Make sure they finish syncing in Workplace before you migrate.</p><table><thead><tr><th>Folder</th><th>File</th><th>Why</th><th>Last changed by</th><th class='n'>Size</th></tr></thead><tbody>$nrRows</tbody></table>" }
    $suspectNote = ''
    if ($suspects.Count) {
        $sr = ''
        foreach ($s in @($suspects)) { $sr += "<li>$(_enc $s.Space) / $(_enc $s.Path): exactly $($s.Count) item(s)</li>" }
        $suspectNote = "<p class='note'><b>Possible truncation.</b> These folder listings returned an exactly-round number of items, which can mean the API paginated silently and the scan under-counted there:</p><ul>$sr</ul>"
    }
    $host_ = ''; try { $host_ = ([uri]$Config.datto.endpointUrl).Host } catch {}
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>Source review - $(_enc $brand)</title><style>
 body{font-family:'Segoe UI',system-ui,sans-serif;margin:0;background:#F4F6F8;color:#101828}
 .wrap{max-width:1180px;margin:24px auto;background:#fff;border-radius:12px;padding:28px 34px;box-shadow:0 1px 4px rgba(16,24,40,.08)}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:16px;margin-bottom:20px}
 h1{font-size:22px;margin:0;color:#1C6091} .sub{color:#667085;font-size:13px;margin-top:3px}
 .logo{height:48px;margin-right:16px}
 .brandlogo{height:78px;border-radius:8px;margin-left:auto}
 h2{font-size:16px;color:#1C6091;margin:26px 0 8px}
 .banner{border-radius:8px;padding:12px 16px;margin:14px 0;font-size:14px}
 .banner.ok{background:#EFFAF4;border:1px solid #A6E9C9;color:#066A4B}
 .banner.bad{background:#FEF3F2;border:1px solid #FDA29B;color:#B42318}
 .tiles{display:flex;gap:12px;flex-wrap:wrap;margin:14px 0}
 .tile{flex:1;min-width:120px;background:#F9FAFB;border:1px solid #E4E7EC;border-radius:8px;padding:12px 16px}
 .tile.hot{background:#FEF3F2;border-color:#FDA29B}
 .tile .v{font-size:22px;font-weight:600} .tile .l{font-size:12px;color:#667085;margin-top:2px}
 table{border-collapse:collapse;width:100%;font-size:12.5px;margin:8px 0}
 th,td{border-bottom:1px solid #EAECF0;padding:6px 8px;text-align:left;vertical-align:top;overflow-wrap:anywhere;word-break:break-word}
 th{background:#F9FAFB;color:#475467;white-space:nowrap} td.n{white-space:nowrap}
 td.pth{font-family:Consolas,monospace} td.lnk{max-width:320px}
 a{color:#1C6091}
 .dim{color:#98A2B3} .okbox{background:#EFFAF4;border:1px solid #A6E9C9;color:#066A4B;border-radius:8px;padding:10px 14px;font-size:13px}
 details{border:1px solid #E4E7EC;border-radius:8px;padding:10px 14px;margin:8px 0} summary{cursor:pointer;font-size:13.5px}
 .tree{margin-top:8px} .tnode{font-size:12.5px;padding:4px 0;border-bottom:1px dashed #EAECF0;overflow-wrap:anywhere}
 .tkind{display:inline-block;background:#EFF4F9;color:#1C6091;border-radius:4px;padding:0 6px;font-size:11px;margin-right:4px}
 .turl{font-size:11.5px} .note{background:#FFFAEB;border:1px solid #FEDF89;border-radius:8px;padding:10px 14px;font-size:13px;color:#93370D}
 .rd td:first-child{color:#475467;width:190px}
 .jump{font-size:13px;margin:10px 0} .jump a{margin-right:10px}
</style></head><body><div class='wrap'>
<header>$(Get-BrandLogoTag -Config $Config)<div><h1>$(_enc (Get-ReportHeaderTitle $brand))</h1><div class='sub'>Datto Workplace source review &middot; generated $($now.ToString('dd MMM yyyy HH:mm'))$verSub$(Get-ReportClientSub $Config)</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
$verdict
<div class='jump'>Jump to: <a href='#pl'>Public links</a> <a href='#lk'>Locked files</a> <a href='#nr'>Cloud readiness</a> <a href='#scope'>Scope</a> <a href='#run'>Run details</a></div>
<div class='tiles'>$tiles</div>
<h2 id='pl'>Public links</h2>
$plSection
$treeSection
<h2 id='lk'>Locked files</h2>
$lkSection
<h2 id='nr'>Cloud readiness</h2>
$nrSection
$suspectNote
<h2 id='scope'>What was checked, and what this cannot tell you</h2>
<p>Only the folder(s) selected in this job were scanned - $($stats.Projects) folder(s), walked in full including subfolders. Each item was checked for a public link, an active lock, and whether it is fully in Datto's cloud. Nothing was changed at the source; this reads only.</p>
<p class='note'><b>What this cannot tell you.</b> The Datto Workplace public API does not expose team or external share membership, per-user permission levels, or who a public link was sent to. 'No public links' does NOT mean an item is not shared with named internal or external users; that can only be reviewed in the Workplace admin console (Team shares / Public shares).</p>
<h2 id='run'>Run details</h2>
<table class='rd'><tbody>
<tr><td>Source</td><td>Datto Workplace$(if ($host_) { " ($(_enc $host_))" })$(if ($isSim) { ' (offline simulation)' })</td></tr>
<tr><td>Folders in job</td><td>$($stats.Projects)</td></tr>
<tr><td>Subfolders / files scanned</td><td>$('{0:N0}' -f $stats.Folders) / $('{0:N0}' -f $stats.Files)</td></tr>
<tr><td>Public links / locked / not cloud-ready</td><td>$nPub / $nLock / $nNR</td></tr>
<tr><td>Started / finished</td><td>$($started.ToString('dd MMM yyyy HH:mm:ss')) / $($finished.ToString('dd MMM yyyy HH:mm:ss')) ($dur)</td></tr>
<tr><td>API requests</td><td>$('{0:N0}' -f $stats.Calls)</td></tr>
<tr><td>Run by</td><td>$(_enc $env:USERNAME) on $(_enc $env:COMPUTERNAME)</td></tr>
<tr><td>App version</td><td>$tv</td></tr>
<tr><td>Findings CSV</td><td class='pth'>$(_enc $csvPath)</td></tr>
</tbody></table>
</div></body></html>
"@
    $repPath = Join-Path $Config.run.reportRoot ("report-SourceReview-" + $ts + ".html")
    Set-Content -Path $repPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "Source review report written: $repPath"
    return $repPath
}
function Invoke-ProvenancePack {
    param($Config, [string]$AuditPath = '', [switch]$NoStageLog, [scriptblock]$TsaTransport)
    if (-not $NoStageLog) { Lz93fa3c46d9 -Config $Config -Stage 'api-provenance' }
    if (-not $AuditPath) {
        $cand = Get-ChildItem (Join-Path $Config.run.reportRoot 'audit-*.csv') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($cand) { $AuditPath = $cand.FullName }
    }
    if (-not $AuditPath -or -not (Test-Path $AuditPath)) { Write-MigrationLog WARN "Provenance pack: no audit CSV found. Run an upload or sync first."; return $null }
    $rows = @(Import-AuditCsv $AuditPath | Where-Object { @('Copied','ZeroByte','Skipped') -contains "$($_.Status)" })
    if (-not $rows.Count) {
        Write-MigrationLog WARN "Provenance pack: '$([System.IO.Path]::GetFileName($AuditPath))' contains no completed file rows (a preview, or an empty run). Evidence packs are only produced for real runs."
        return $null
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("LiscaraghMigrate-ProvenanceManifest-v1`n")
    [void]$sb.Append("Audit: $([System.IO.Path]::GetFileName($AuditPath))`n")
    [void]$sb.Append("Fields: Space|SourcePath|SizeBytes|SourceMD5|DestQuickXor|SourceModifiedUtc|Status`n")
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($r in $rows) {
        $lines.Add("$($r.Space)|$($r.SourcePath)|$($r.SourceSizeBytes)|$($r.SourceMd5)|$($r.DestHash)|$($r.SourceModifiedUtc)|$($r.Status)")
    }
    $sorted = [System.Collections.Generic.List[string]]::new($lines)
    $sorted.Sort([System.StringComparer]::Ordinal)
    foreach ($l in $sorted) { [void]$sb.Append($l); [void]$sb.Append("`n") }
    $manifestBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($sb.ToString())
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($manifestBytes)
    $hashHex = ($hashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $baseName = "provenance-$ts"
    $manPath = Join-Path $Config.run.reportRoot "$baseName-manifest.txt"
    [System.IO.File]::WriteAllBytes($manPath, $manifestBytes)
    Write-MigrationLog OK "Provenance manifest written ($($rows.Count) file record(s)): $manPath"
    Write-MigrationLog INFO "  manifest SHA-256: $hashHex"
    $tsaEnabled = $true; $tsaUrl = 'http://timestamp.digicert.com'
    if ((Test-ConfigProp $Config.run 'provenance')) {
        if ((Test-ConfigProp $Config.run.provenance 'enabled')) { $tsaEnabled = [bool]$Config.run.provenance.enabled }
        if (((Test-ConfigProp $Config.run.provenance 'tsaUrl')) -and $Config.run.provenance.tsaUrl) { $tsaUrl = "$($Config.run.provenance.tsaUrl)" }
    }
    $tokenPath = ''; $tsaTime = ''; $tsaSigner = ''; $tsaState = 'pending'
    if (-not $tsaEnabled) { $tsaState = 'disabled' }
    else {
        try {
            Add-Type -AssemblyName System.Security.Cryptography.Pkcs -ErrorAction Stop
            $req = [System.Security.Cryptography.Pkcs.Rfc3161TimestampRequest]::CreateFromHash($hashBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, $null, $null, $true)
            $reqBytes = $req.Encode()
            $respBytes = $null
            if ($TsaTransport) { $respBytes = [byte[]](& $TsaTransport $tsaUrl $reqBytes) }
            else {
                $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("tsr-" + [guid]::NewGuid().ToString('N') + '.bin')
                try {
                    Invoke-WebRequest -UseBasicParsing -Method Post -Uri $tsaUrl -Body $reqBytes -ContentType 'application/timestamp-query' -TimeoutSec 30 -OutFile $tmp | Out-Null
                    $respBytes = [System.IO.File]::ReadAllBytes($tmp)
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            $token = $req.ProcessResponse($respBytes, [ref]([int]0))
            $tsaTime = $token.TokenInfo.Timestamp.UtcDateTime.ToString('o')
            try { $cms = $token.AsSignedCms(); if ($cms.Certificates.Count) { $tsaSigner = $cms.Certificates[0].Subject } } catch {}
            $tokenPath = Join-Path $Config.run.reportRoot "$baseName.tsr"
            [System.IO.File]::WriteAllBytes($tokenPath, $respBytes)
            $tsaState = 'timestamped'
            Write-MigrationLog OK "  third-party timestamp obtained: $tsaTime ($tsaUrl). Token: $tokenPath"
        } catch {
            Write-MigrationLog WARN "  the timestamp authority could not be reached or its reply did not verify ($($_.Exception.Message)). The pack is still valid locally and is marked pending; run 'Provenance pack' again when online to add the third-party timestamp - the manifest is deterministic, so the re-run attests the identical bytes."
        }
    }
    function _enc { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    $brand = 'Liscaragh Migrate'
    if (((Test-ConfigProp $Config.run 'report')) -and ((Test-ConfigProp $Config.run.report 'brand')) -and $Config.run.report.brand) { $brand = "$($Config.run.report.brand)" }
    $now = Get-Date
    $tv = Lzb0b39673dd; $verSub = if ($tv) { " &middot; v$tv" } else { '' }
    $spaces = @($rows | Select-Object -ExpandProperty Space -Unique).Count
    $pvStatus = ''
    try { $pvSide = ($AuditPath -replace '\.csv$','') + '.outcome.json'; if (Test-Path $pvSide) { $pvStatus = "$((Get-Content $pvSide -Raw | ConvertFrom-Json).Status)" } } catch {}
    $pvScope = if (@('CANCELLED','ENDED_EARLY','INCOMPLETE','CAPPED') -contains $pvStatus) {
        "<div class='banner warn'><b>This run did not finish ($(_enc $pvStatus.ToLowerInvariant().Replace('_',' '))).</b> The manifest covers only the $($rows.Count) file(s) this run placed or confirmed before it stopped. It is not a record of the whole migration: files copied by earlier runs are in their own packs, and files not yet copied are in none.</div>"
    } else { "<p class='dim' style='font-size:12.5px;color:#667085'>Scope: the files in this one run's audit. Each run has its own pack.</p>" }
    $tsBlock = switch ($tsaState) {
        'timestamped' { "<div class='banner ok'><b>Third-party timestamped.</b> The manifest hash was countersigned by an independent RFC 3161 Time Stamping Authority at <b>$(_enc $tsaTime)</b> ($(_enc $tsaUrl)). Signer: $(_enc $tsaSigner). Token file: <span class='pth'>$(_enc ([System.IO.Path]::GetFileName($tokenPath)))</span></div>" }
        'disabled'    { "<div class='banner warn'><b>Third-party timestamp switched off</b> for this job (run.provenance.enabled). The manifest and its hash below still bind content to dates; they are simply not countersigned by an outside authority.</div>" }
        default       { "<div class='banner warn'><b>Third-party timestamp pending.</b> The timestamp authority was not reachable when this pack was built. The manifest is deterministic, so running 'Provenance pack' again when online attests these IDENTICAL bytes - nothing is lost by the delay.</div>" }
    }
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>Provenance pack - $(_enc $brand)</title><style>
 body{font-family:'Segoe UI',system-ui,sans-serif;margin:0;background:#F4F6F8;color:#101828}
 .wrap{max-width:980px;margin:24px auto;background:#fff;border-radius:12px;padding:28px 34px;box-shadow:0 1px 4px rgba(16,24,40,.08)}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:16px;margin-bottom:20px}
 h1{font-size:22px;margin:0;color:#1C6091} .sub{color:#667085;font-size:13px;margin-top:3px}
 .logo{height:48px;margin-right:16px}
 .brandlogo{height:78px;border-radius:8px;margin-left:auto}
 h2{font-size:16px;color:#1C6091;margin:24px 0 8px}
 .banner{border-radius:8px;padding:12px 16px;margin:14px 0;font-size:14px}
 .banner.ok{background:#EFFAF4;border:1px solid #A6E9C9;color:#066A4B}
 .banner.warn{background:#FFFAEB;border:1px solid #FEDF89;color:#93370D}
 table{border-collapse:collapse;width:100%;font-size:13px;margin:8px 0}
 td{border-bottom:1px solid #EAECF0;padding:6px 8px;vertical-align:top;overflow-wrap:anywhere}
 td:first-child{color:#475467;width:210px;white-space:nowrap}
 .pth{font-family:Consolas,monospace} .hash{font-family:Consolas,monospace;font-size:12px;background:#F9FAFB;border:1px solid #E4E7EC;border-radius:6px;padding:8px 10px;overflow-wrap:anywhere}
 pre{background:#0F172A;color:#E2E8F0;border-radius:8px;padding:12px 14px;font-size:12px;overflow-x:auto;white-space:pre-wrap;overflow-wrap:anywhere}
 .note{background:#FFFAEB;border:1px solid #FEDF89;border-radius:8px;padding:10px 14px;font-size:13px;color:#93370D}
 p{font-size:13.5px}
</style></head><body><div class='wrap'>
<header>$(Get-BrandLogoTag -Config $Config)<div><h1>$(_enc (Get-ReportHeaderTitle $brand))</h1><div class='sub'>Provenance pack &middot; generated $($now.ToString('dd MMM yyyy HH:mm'))$verSub$(Get-ReportClientSub $Config)</div></div><img class='brandlogo' alt='Liscaragh Software' src='data:image/jpeg;base64,$($script:LiscaraghLogoB64)' /></header>
<p>This pack is evidence of <b>what was migrated and when it was really last modified</b>. The manifest lists every file this run placed or confirmed at the destination - its path, size, content hashes at source and destination, and its <b>original modified date at the source</b>. The manifest's SHA-256 hash binds all of it together: change one byte of one record and the hash no longer matches.</p>
$pvScope
$tsBlock
<h2>Manifest</h2>
<table><tbody>
<tr><td>File records</td><td>$($rows.Count) file(s) across $spaces $($script:SrcItem)(s)</td></tr>
<tr><td>Manifest file</td><td class='pth'>$(_enc ([System.IO.Path]::GetFileName($manPath)))</td></tr>
<tr><td>Built from audit</td><td class='pth'>$(_enc ([System.IO.Path]::GetFileName($AuditPath)))</td></tr>
<tr><td>Manifest SHA-256</td><td><div class='hash'>$hashHex</div></td></tr>
</tbody></table>
<h2>How anyone can verify this, without trusting us</h2>
<p>1. Recompute the manifest hash and compare it to the value above (and to the hash inside the timestamp token):</p>
<pre>certutil -hashfile "$(_enc ([System.IO.Path]::GetFileName($manPath)))" SHA256
# or on Linux/macOS:  sha256sum "$(_enc ([System.IO.Path]::GetFileName($manPath)))"</pre>
<p>2. Inspect and verify the RFC 3161 timestamp token with standard OpenSSL (no Liscaragh software involved):</p>
<pre>openssl ts -reply -in "$(_enc $(if ($tokenPath) { [System.IO.Path]::GetFileName($tokenPath) } else { "$baseName.tsr" }))" -text
openssl ts -verify -digest $hashHex -in "$(_enc $(if ($tokenPath) { [System.IO.Path]::GetFileName($tokenPath) } else { "$baseName.tsr" }))" -CAfile tsa-chain.pem</pre>
<p>(The authority's certificate chain, tsa-chain.pem, is published by the authority, not by us. For the default authority it is at <span class='pth'>https://www.digicert.com/kb/digicert-root-certificates.htm</span> - download its timestamping root and intermediate and concatenate them into tsa-chain.pem.)</p>
<h2>What this proves, and what it does not</h2>
<p>It proves this exact record - these files, these hashes, these original dates - existed at the moment of the third-party timestamp and has not been altered since. Content hashes tie each date to the actual bytes of the file. It does <b>not</b> prove the source system's clock was accurate when the files were originally edited; no after-the-fact process can. Keep the manifest, the token file and the audit CSV together as one evidence set.</p>
<p class='note'>Privacy: the timestamp authority received only the 32-byte manifest hash. No file names, dates or content left this computer as part of the timestamping.</p>
</div></body></html>
"@
    $htmlPath = Join-Path $Config.run.reportRoot "$baseName.html"
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8
    Write-MigrationLog OK "Provenance pack written: $htmlPath"
    return $htmlPath
}
function Test-Api {
    param($Config)
    Lz93fa3c46d9 -Config $Config -Stage 'api-test'
    Lz1338c7e606 -Config $Config
    Connect-Destination -Config $Config
    $spaces = @(Get-DattoSpaces -Config $Config)
    Write-MigrationLog OK "Datto returned $($spaces.Count) project(s)."
    if ($spaces.Count) {
        $s = $spaces[0]
        Write-MigrationLog INFO "First project: $($s.Name) ($($s.Type))"
        $items = @(Get-DattoItems -Config $Config -Space $s | Select-Object -First 5)
        foreach ($it in $items) { Write-MigrationLog INFO "  file: $($it.RelativePath) ($([math]::Round($it.Size/1KB,1)) KB, mod $($it.ModifiedUtc))" }
        Write-MigrationLog OK "If the project and files above look right, the Datto connection is reading real data correctly."
    }
}
function Show-Menu {
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
            '1' { Test-Api -Config $Config }
            '2' { Invoke-Discover -Config $Config }
            '3' { Invoke-PreFlight -Config $Config }
            '4' { Invoke-Transfer -Config $Config -Mode FirstPass -SpoolAhead $SpoolAhead -UploadWorkers $UploadWorkers }
            '5' { if ((Read-Host 'Type YES to upload') -eq 'YES') { Invoke-Transfer -Config $Config -Mode FirstPass -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -UploadWorkers $UploadWorkers -Execute } }
            '6' { if ((Read-Host 'Type YES to upload') -eq 'YES') { Invoke-Transfer -Config $Config -Mode Delta -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -UploadWorkers $UploadWorkers -Execute } }
            '7' { Invoke-Validate -Config $Config }
            '8' {
                Invoke-Discover -Config $Config
                $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
                if (Test-Path $mapPath) {
                    Invoke-PreFlight -Config $Config
                    if ((Read-Host 'Proceed to UPLOAD (this writes to your tenant)? Type YES') -eq 'YES') {
                        Invoke-Transfer -Config $Config -Mode FirstPass -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -UploadWorkers $UploadWorkers -Execute
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
    ((Test-ConfigProp $cfg.run 'parallel')) -and
    ((Test-ConfigProp $cfg.run.parallel 'spoolAhead'))) {
    $SpoolAhead = [int]$cfg.run.parallel.spoolAhead
}
if (-not $PSBoundParameters.ContainsKey('MaxParallelSpaces') -and
    ((Test-ConfigProp $cfg.run 'parallel')) -and
    ((Test-ConfigProp $cfg.run.parallel 'maxParallelSpaces'))) {
    $MaxParallelSpaces = [int]$cfg.run.parallel.maxParallelSpaces
}
$parallelEnabled = $false
try { if (((Test-ConfigProp $cfg.run 'parallel')) -and ((Test-ConfigProp $cfg.run.parallel 'enabled')) -and $cfg.run.parallel.enabled) { $parallelEnabled = $true } } catch {}
if (-not $parallelEnabled -and $MaxParallelSpaces -gt 1 -and -not $PSBoundParameters.ContainsKey('MaxParallelSpaces')) {
    Write-MigrationLog INFO "Parallel is off for this job (run.parallel.enabled is not set), so this runs one $($script:SrcItem) at a time. Turn it on with the Parallel setting in Settings > Performance and tuning."
    $MaxParallelSpaces = 1
}
if ((Test-ConfigProp $cfg.run 'throttle')) {
    if (((Test-ConfigProp $cfg.run.throttle 'timeoutSec')) -and $cfg.run.throttle.timeoutSec) {
        $script:HttpTimeoutSec = [int]$cfg.run.throttle.timeoutSec
    }
    if (((Test-ConfigProp $cfg.run.throttle 'transferTimeoutSec')) -and $cfg.run.throttle.transferTimeoutSec) {
        $script:TransferTimeoutSec = [int]$cfg.run.throttle.transferTimeoutSec
    }
    if (((Test-ConfigProp $cfg.run.throttle 'sourceIdleTimeoutSec')) -and $null -ne $cfg.run.throttle.sourceIdleTimeoutSec) { $script:SourceIdleSec = [int]$cfg.run.throttle.sourceIdleTimeoutSec }
    if (((Test-ConfigProp $cfg.run.throttle 'sourceReadAttempts')) -and $cfg.run.throttle.sourceReadAttempts) { $script:SourceReadAttempts = [int]$cfg.run.throttle.sourceReadAttempts }
}
$UploadWorkers = 4
$workersExplicit = $false
if ((Test-ConfigProp $cfg.run 'upload')) {
    if (((Test-ConfigProp $cfg.run.upload 'directPutMaxMB')) -and $cfg.run.upload.directPutMaxMB) {
        $script:SmallFilePutThreshold = [int64]$cfg.run.upload.directPutMaxMB * 1MB
    }
    if (((Test-ConfigProp $cfg.run.upload 'workers')) -and $cfg.run.upload.workers) {
        $UploadWorkers = [int]$cfg.run.upload.workers
        $workersExplicit = $true
    }
    if ((Test-ConfigProp $cfg.run.upload 'preserveDates')) { $script:PreserveDates = [bool]$cfg.run.upload.preserveDates }
}
if ((Test-ConfigProp $cfg.run 'metadata')) {
    if (((Test-ConfigProp $cfg.run 'metadata')) -and $cfg.run.metadata -and
        ((Test-ConfigProp $cfg.run.metadata 'provenanceColumns'))) {
        $script:ProvColsOn = [bool]$cfg.run.metadata.provenanceColumns
    }
    if (((Test-ConfigProp $cfg.run 'metadata')) -and $cfg.run.metadata -and
        ((Test-ConfigProp $cfg.run.metadata 'folderColumns'))) {
        $script:FolderColRules = ConvertTo-FolderColRules "$($cfg.run.metadata.folderColumns)"
    }
    if (((Test-ConfigProp $cfg.run 'metadata')) -and $cfg.run.metadata -and
        ((Test-ConfigProp $cfg.run.metadata 'filenameColumns'))) {
        $script:FilenameColRules = ConvertTo-FilenameColRules "$($cfg.run.metadata.filenameColumns)"
    }
    if (((Test-ConfigProp $cfg.run 'metadata')) -and $cfg.run.metadata) {
        if ((Test-ConfigProp $cfg.run.metadata 'extensionCategory')) {
            $script:ExtCatRules = ConvertTo-ExtensionCategoryRules "$($cfg.run.metadata.extensionCategory)"
        }
        if ((Test-ConfigProp $cfg.run.metadata 'retentionYears')) {
            $ry = 0; [void][int]::TryParse("$($cfg.run.metadata.retentionYears)", [ref]$ry); $script:RetentionYears = [math]::Max(0, $ry)
        }
    }
}
if ("$($cfg.source.provider)" -eq 'LocalFs' -and -not $workersExplicit) { $UploadWorkers = 8 }
if ((Test-ConfigProp $cfg.run 'encryptSpool')) { $script:SpoolEncrypt = [bool]$cfg.run.encryptSpool }
if ((Test-ConfigProp $cfg.run 'trialFileLimit') -and $cfg.run.trialFileLimit) { $script:TrialFileLimit = [Math]::Min([Math]::Max(1, [int]$cfg.run.trialFileLimit), $script:TrialFileLimit) }
if ($TrialLimitForTest -gt 0 -and $cfg.destination.provider -eq 'LocalSim') { $script:TrialFileLimit = $TrialLimitForTest; $script:TrialCap = $TrialLimitForTest; $script:TrialFilesRemaining = $TrialLimitForTest }
if ((Test-ConfigProp $cfg.run 'tuning')) {
    $tn = $cfg.run.tuning
    if (((Test-ConfigProp $tn 'chunkSizeMB'))  -and $tn.chunkSizeMB)  { $script:ChunkSize    = [int64]$tn.chunkSizeMB * 1MB }
    if (((Test-ConfigProp $tn 'excludePatterns')))                    { $script:ExcludePatterns = @($tn.excludePatterns | ForEach-Object { "$_" -split '[;,\r\n]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if (((Test-ConfigProp $tn 'includePatterns')))                    { $script:IncludePatterns = @($tn.includePatterns | ForEach-Object { "$_" -split '[;,\r\n]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if (((Test-ConfigProp $tn 'maxFileSizeMB')) -and $tn.maxFileSizeMB){ $script:MaxFileBytes  = [int64]$tn.maxFileSizeMB * 1MB }
    if (((Test-ConfigProp $tn 'largeFileMB'))   -and $tn.largeFileMB)  { $script:LargeFileBytes = [int64]$tn.largeFileMB * 1MB }
    if (((Test-ConfigProp $tn 'modifiedAfter')))  { $script:ModifiedAfterUtc  = ConvertTo-ConfigUtcBound $tn.modifiedAfter }
    if (((Test-ConfigProp $tn 'modifiedBefore'))) { $script:ModifiedBeforeUtc = ConvertTo-ConfigUtcBound $tn.modifiedBefore }
    if ($script:ModifiedAfterUtc -and $script:ModifiedBeforeUtc -and $script:ModifiedAfterUtc -ge $script:ModifiedBeforeUtc) {
        throw "run.tuning.modifiedAfter ($($tn.modifiedAfter)) is not before modifiedBefore ($($tn.modifiedBefore)); nothing would match. Widen the window, or clear one bound."
    }
    if (((Test-ConfigProp $tn 'assessmentTopFiles')) -and $tn.assessmentTopFiles) { $script:AssessmentTopFiles = [Math]::Max(1, [int]$tn.assessmentTopFiles) }
    if (((Test-ConfigProp $tn 'findDuplicates'))) { $script:FindDuplicates = [bool]$tn.findDuplicates }
}
try { if ((Test-ConfigProp $cfg.run 'reportRoot') -and "$($cfg.run.reportRoot)") { Import-SelectionRules -Path (Join-Path "$($cfg.run.reportRoot)" 'selection.json') } } catch { throw "selection.json (the folders and files chosen with Edit selection) could not be read: $($_.Exception.Message). Nothing was copied, so nothing you unticked could leave. Open Edit selection on the source and save it again, or remove selection.json from the job's reports folder to copy everything." }
try {
    $needsLicence = (($Action -eq 'Transfer' -and $Execute) -or ($Action -eq 'Validate'))
    if ($needsLicence -and ($cfg.destination.provider -ne 'LocalSim')) {
        $lic = Test-MigrationLicence -Config $cfg
        if ($lic.Licensed) {
            $script:LicenceInfo = $lic
            Write-MigrationLog OK "Licence accepted: $($lic.Customer), Microsoft tenant $($lic.TenantId) (licence $($lic.LicenceId))."
        }
        elseif ($lic.Reason -match '^no licence file') {
            if ($Action -eq 'Validate') {
                if ($script:GuiMode) { Write-Host "##TRIAL##|START|0|Validate" }
                Write-MigrationLog WARN "No licence: EVALUATION MODE. Verify will still check whatever is at the destination, so you can confirm the trial copy landed correctly. Licence this Microsoft tenant at https://www.liscaragh.com to remove the limit."
            }
            else {
                $bucket = if ($Mode -eq 'FirstPass') { 'FirstPass' } else { 'Delta' }
                $what   = if ($bucket -eq 'FirstPass') { 'full copy' } else { 'sync' }
                $key    = Get-EvalKey -TenantId "$($cfg.auth.tenantId)"
                if (-not $key) {
                    Write-MigrationLog ERROR "This job has no Microsoft 365 tenant ID set, so the free evaluation cannot be counted and the copy will not start. Nothing has been changed. Set the tenant in Settings > API settings (or re-run the setup wizard), then try again."
                    exit 1
                }
                $used   = Get-EvalUsage -Key $key
                $spent  = if ($bucket -eq 'FirstPass') { $used.FirstPass } else { $used.Delta }
                $remaining = $script:TrialFileLimit - $spent
                if ($remaining -le 0) {
                    if ($script:GuiMode) { Write-Host "##TRIAL##|EXHAUSTED|$bucket|$($script:TrialFileLimit)" }
                    Write-MigrationLog ERROR "The free evaluation for this Microsoft tenant is used up: it has already had its $($script:TrialFileLimit) free $what file(s). You can still test the connection, list projects, Preview, Compare sizes and Verify. To migrate everything, licence this tenant at https://www.liscaragh.com, then install the licence via Help > Install licence file."
                    exit 1
                }
                $script:TrialLedgerKey = $key
                $script:TrialBucket = $bucket
                $script:TrialCap = $remaining
                $script:TrialFilesRemaining = $remaining
                if ($script:GuiMode) { Write-Host "##TRIAL##|START|$remaining|$bucket" }
                Write-MigrationLog WARN "No licence: EVALUATION MODE. Up to $remaining $what file(s) will be copied for real so you can prove the migration works end to end, then it stops. This is a sample, not a full migration: this tenant's free $what allowance is $($script:TrialFileLimit) file(s) in total, and $spent have been used. Licence this Microsoft tenant at https://www.liscaragh.com, then Help > Install licence file, to migrate everything."
            }
        }
        else {
            if ($script:GuiMode) { Write-Host "##LICENCE##|$($lic.Reason)" }
            Write-MigrationLog ERROR "This action needs a valid licence: $($lic.Reason). Without a valid licence you can still test the connection, list projects, Preview (see what would copy, without copying), and run 'Compare sizes'. Obtain a licence at https://www.liscaragh.com, then install it via Help > Install licence file."
            exit 1
        }
    }
    switch ($Action) {
        'TestApi'     { Test-Api        -Config $cfg }
        'Discover'    { Invoke-Discover -Config $cfg -NonInteractive:$NonInteractive }
        'PreFlight'   { Invoke-PreFlight -Config $cfg }
        'Transfer'    { Invoke-Transfer -Config $cfg -Mode $Mode -DeltaMode $DeltaMode -OnlySpace $OnlySpace -Spaces $Spaces -SpoolAhead $SpoolAhead -MaxParallelSpaces $MaxParallelSpaces -UploadWorkers $UploadWorkers -ResultDir $ResultDir -Execute:$Execute -FailedOnly:$FailedOnly -FailedFromAudit $FailedFromAudit
                        exit $script:ExitCode }
        'Validate'    { Invoke-Validate -Config $cfg }
        'Drift'       { Invoke-DriftCheck -Config $cfg }
        'SizeCheck'   { Invoke-SizeCheck -Config $cfg -OnlySpace $OnlySpace }
        'DestInventory' { Lz3d529cf4da -Config $cfg -SpaceName $Spaces -ResultDir $ResultDir }
        'SourceReview' { Invoke-SourceReview -Config $cfg | Out-Null }
        'Provenance'  { Invoke-ProvenancePack -Config $cfg -AuditPath $AuditPath | Out-Null }
        'Report'      { Invoke-HtmlReport -Config $cfg -AuditPath $AuditPath | Out-Null }
        'Certificate' { Invoke-CompletionCertificate -Config $cfg -AuditPath $AuditPath | Out-Null }
        'Finalize'    { Invoke-FinalizeAction -Config $cfg -Status $FinalizeStatus -AuditPath $AuditPath; exit $script:ExitCode }
        default       { Show-Menu       -Config $cfg }
    }
    try { Lz162301ffe6 | Out-Null } catch {}
}
catch {
    $e = $_
    try { Lz162301ffe6 | Out-Null } catch {}
    $emit = {
        param([string]$Level, [string]$Text)
        try { Write-MigrationLog $Level $Text } catch { Write-Host "[$Level] $Text" }
    }
    if ("$($e.Exception.Message)" -like "*$($script:StopTag)*") {
        $plainStop = ((("$($e.Exception.Message)") -replace [regex]::Escape($script:StopTag), '').Trim())
        & $emit 'ERROR' $plainStop
        if ($script:GuiMode) { try { Write-Host "##REFUSED##|$plainStop" } catch {} }
        $script:ExitCode = 1
        exit 1
    }
    & $emit 'ERROR' "The run stopped with an unexpected error. Everything below is the technical detail; nothing was left half-written, and no file at the destination was touched by this failure."
    Write-CrashDetail -ErrorRecord $e
    & $emit 'ERROR' "Send this log to support@liscaragh.com (Help menu > Email support attaches it for you)."
    $script:ExitCode = 1
    exit 1
}
finally {
    try { Remove-RunTempRoot } catch {}
}
}

# SIG # Begin signature block
# MIIzXQYJKoZIhvcNAQcCoIIzTjCCM0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBV6xxzSoyNiPQ4
# 3k6CCGogQpz/i+3yf5yKTxzWdNAZG6CCG1swggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwgga5MIIEoaADAgECAhMzAAvf/0ou
# 2tAcN/jnAAAAC9//MA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBBT0MgQ0EgMDMwHhcNMjYxMTEwMTAwMzU5WhcNMjYxMTEz
# MTAwMzU5WjB9MQswCQYDVQQGEwJJRTESMBAGA1UECBMJVGlwcGVyYXJ5MRAwDgYD
# VQQHEwdQdWNrYW5lMSMwIQYDVQQKExpEYXZlIERldmVyeSBDb25zdWx0aW5nIEx0
# ZDEjMCEGA1UEAxMaRGF2ZSBEZXZlcnkgQ29uc3VsdGluZyBMdGQwggGiMA0GCSqG
# SIb3DQEBAQUAA4IBjwAwggGKAoIBgQCIqODv7J77EGCD7trxvJcYpTBjVJDe+a1T
# F9v2Ne9cdB1BIfr5jnzWwVFcacwPlXryYdUztr5oCXi8eIKtQG3ZiuzdLBWfgdxi
# nEdOosh+sCureZhMZVqozhav+XKGYDbkR30QMJ1AWbJCpyHu38O7p4Qwx+hHPE90
# YMMXnvUUzuPSe41kbGxShDfw3ALciUZrEtgQkfuONeCwbqemtAkTDmYzUiYJqbDU
# 4XlyoXYUljIT5/MLBW1Q6X653BDst2JnFBWfM93WtR2yIW3GfxiGkHWVbGdh2igz
# /kMkpNNQi7BZnemgEUPGrRZcbf8QayfTqnlAtsQ8a3cM/zIa1lEFKnb5VksUgkuy
# M52DIinXi+pvGrtAl+tZ9Mw7ta6bPnaRPkJ01dSZZLcWfxThCPT1srvR1+suSQTS
# tq9s9K/Ro31QhUljbsArfsSA0dvZTsAiTAxDMwVMoikrRINJc3heYJNv4/0oub9k
# 6nb6OK2nDbKeO69MYinfjBTl19/jzzcCAwEAAaOCAdMwggHPMAwGA1UdEwEB/wQC
# MAAwDgYDVR0PAQH/BAQDAgeAMDoGA1UdJQQzMDEGCisGAQQBgjdhAQAGCCsGAQUF
# BwMDBhkrBgEEAYI3YaCMlW7fpoV4gq72q2PIzZYOMB0GA1UdDgQWBBRSAfst7ra0
# rwzByhZeJnhNdfJUTjAfBgNVHSMEGDAWgBSkQwx/dlqlhec+jSgPDBeiRWlwxjBn
# BgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBBT0MlMjBDQSUy
# MDAzLmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwSUQlMjBWZXJp
# ZmllZCUyMENTJTIwQU9DJTIwQ0ElMjAwMy5jcnQwVAYDVR0gBE0wSzBJBgRVHSAA
# MEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# RG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEAgUQuxe1y4a2B
# dOxAWMUS5pNVuKDIa6ba+pazug2wRcC2Siyu+7/bpKv8bmTCARhET3zGBY/km/p0
# pU8wJimq9O13PBnDB7sC1NCbi0aCyoALyaHDlN5Ir9ll8MG/jkXGerWQNhzI8qbN
# mLrXdpKidRkphB2Ro/VmVBOf1WS5APL76rQoZSvUX+so4IRqjTBfP8GxD4RFUFom
# v7tLSPXD02Bv4V1X15MSzcXlMmpCpnHhx0ict0HA2KEJCP7xTjeOErj3YIR9c85h
# MA4xmEr0EnvZR4Z/04eZ13PfPWZ1TK1zD4ae7TlzY/yVr94fJGFmv1v03ihUgxI3
# I9ZDZl9InNVYzyF+QOdMiqQu/pOyQW1pyB6asYgICegrdSkISazxIjChvNBQ3jyW
# 5EAfYAZp3eqh6N4FYpkD3Rkzo8bgngtQIQHoejm0L1ygVLDAqoqvmIMptMavnUYu
# X9G/MYVk/Wrfnea480+H2IvDfs7ddo/EJkUznuXT84DCZrsZV5bg4FZ5cVlxKDRJ
# 4uqU8a8IQkYBpWZ5Yx/6W0UauvLpnIixdtljl2urGbkgBDcW+vmlg0jC49lP2y8a
# cXWAYk4m+R3cdcJBNPVLd1zPqfvHIsprdYQfJ9v1K4BFAl3Y05dWH8ni3ZogUaYH
# Z+S2+KLApG/UvXy8bUImAXikCOgIarswggcoMIIFEKADAgECAhMzAAAAGA3rkVWp
# igCYAAAAAAAYMA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMTK01pY3Jvc29mdCBJRCBW
# ZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIwMjEwHhcNMjYwMzI2MTgxMTMyWhcN
# MzEwMzI2MTgxMTMyWjBaMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1Mg
# QU9DIENBIDAzMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyIDaYDRW
# oon9lVnlj+SOj5xV8Sf5Qd+3yUeeRgr0exi2QTJAYo24ilcIKQSN8TOZ3+POM5x/
# 6p3Cfjgqust44J0FvkfGXe1Puy45a5nLJGpc0kNIITMRKZwVvPxx7NlfGSc0JOhz
# /kg7G77C+y3ZR/3jtpeJpJ4QwcK9Gf0Peuk7xLYeW/JAsY9b6oleGDbYSxkamUfb
# tnyv8gTFrvN6ejuLqNhHYPvoBHsOSC+7555yhapkof0fbzyct1hdWHGXsAFMfLF2
# TVJ8d2YVYOfZdi6YrT4sMxOhTKiLKmhL1XtzM7hXdmv7lg2R+lWw8lIkSu/JiINQ
# 0GAPcwxMsgRXDSPp8VUs4Jby+ruz0bjaoHFd7H+hC8cPPcrEDP2eEdYURVl0acjl
# iigCrXwR05NFJzYj3MZizDGLPI3lIzonX1T40yK8v1FcJ8MXZZCvOXGXwRDGGfww
# TTsHaJj+OfWNZ/IsypG4bGvqeJcPnEFcQEwRcfYIEe/R4a8k+xw5qTy75CbwWeMF
# uAlt9lE9kjMg3tvJyDlN5voXx5VXinCwUHMpuVaEQ4yHAlSO7qoBltjzTBNHH3ov
# MwsAsuhwrLLCVhUu3oP2GxYZwEyXMlnzK5DbgGzHzDfDaYPHK0uo1VaMMg9Bhuc3
# YIvrkFXEiv+t/JgNcRGCt6ZyKEIDtPbrgwcCAwEAAaOCAdwwggHYMA4GA1UdDwEB
# /wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUpEMMf3ZapYXnPo0o
# DwwXokVpcMYwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMBAf8ECDAGAQH/AgEAMB8G
# A1UdIwQYMBaAFNlBKbAPD2Ns72nX9c0pnqRIajDmMHAGA1UdHwRpMGcwZaBjoGGG
# X2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUy
# MElEJTIwVmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3Js
# MH0GCCsGAQUFBwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIw
# Q29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDIxLmNydDANBgkqhkiG9w0BAQwFAAOC
# AgEAcccgVvl+poXUYksA/TzDFnBlAJ8ef0FMJzb2XRRhF/uA0QyK/VgoeAvO8B7c
# PpYNQ97sytdA7LT19CxSwRQAt71jGF+CJl8KC4aEdMZTfJlHaKyd24J6QiVriNed
# 9WdawsD7lK0pAcXziBg5N6dhAm9x6P8R4uT0UkfzlK1rkB8F4mlzE7l7tyES3s8F
# ZGaRZjcGEQ+e0fTcdhf8jO7czmNB4dIRgmmBCt/P+ha0tEl2nV1sg1An5+VzhgAk
# Y1Apx8fiUFBtH+Ehw/om5aQCNIJfmR51ZnV18R02Xk2tAmAiIRcSj9vdtrNIOsy5
# nolddy1lJrbf1Be061l6TItv9FDZ4mg6B+65zxkVecVV/Ll8uLGYouGrMM6jzO2O
# /ps3K2p6mfBI2ZOYIy4UNwNrGWqa5TrvAmkZsn3CIlR+81X4AL5vNTFlxc4gH+5s
# u0Dr58hBTxnXavDEnz7X0csP1Kt7h+iqaGiTSHz2B+n3HmUoud0WrdQPYKxMat0T
# o4YUqU3HIbgSLQDDVT8aCjW1Jvokf1915C/vVkIIp48h3voVy3JWPLwBlxQ9aeND
# 6jCKQGLJhCQRSlvXX+P/9TeaEA6/xWPSASZf6Ekve/Yua7U+zWc/Sr2K2gj0QRrN
# EAsvrFr4EGtHKDO9ECVS3lcJksVDv9KHdMPUK8u20i68RqAwggeeMIIFhqADAgEC
# AhMzAAAAB4ejNKN7pY4cAAAAAAAHMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYT
# AlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01p
# Y3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBB
# dXRob3JpdHkgMjAyMDAeFw0yMTA0MDEyMDA1MjBaFw0zNjA0MDEyMDE1MjBaMGMx
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAy
# BgNVBAMTK01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIw
# MjEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCy8MCvGYgo4t1UekxJ
# bGkIVQm0Uv96SvjB6yUo92cXdylN65Xy96q2YpWCiTas7QPTkGnK9QMKDXB2ygS2
# 7EAIQZyAd+M8X+dmw6SDtzSZXyGkxP8a8Hi6EO9Zcwh5A+wOALNQbNO+iLvpgOnE
# M7GGB/wm5dYnMEOguua1OFfTUITVMIK8faxkP/4fPdEPCXYyy8NJ1fmskNhW5Hdu
# NqPZB/NkWbB9xxMqowAeWvPgHtpzyD3PLGVOmRO4ka0WcsEZqyg6efk3JiV/TEX3
# 9uNVGjgbODZhzspHvKFNU2K5MYfmHh4H1qObU4JKEjKGsqqA6RziybPqhvE74fEp
# 4n1tiY9/ootdU0vPxRp4BGjQFq28nzawuvaCqUUF2PWxh+o5/TRCb/cHhcYU8Mr8
# fTiS15kRmwFFzdVPZ3+JV3s5MulIf3II5FXeghlAH9CvicPhhP+VaSFW3Da/azRO
# dEm5sv+EUwhBrzqtxoYyE2wmuHKws00x4GGIx7NTWznOm6x/niqVi7a/mxnnMvQq
# 8EMse0vwX2CfqM7Le/smbRtsEeOtbnJBbtLfoAsC3TdAOnBbUkbUfG78VRclsE7Y
# DDBUbgWt75lDk53yi7C3n0WkHFU4EZ83i83abd9nHWCqfnYa9qIHPqjOiuAgSOf4
# +FRcguEBXlD9mAInS7b6V0UaNwIDAQABo4ICNTCCAjEwDgYDVR0PAQH/BAQDAgGG
# MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTZQSmwDw9jbO9p1/XNKZ6kSGow
# 5jBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# yH7SaoUqG8oZmAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsweaB3oHWGc2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElkZW50aXR5
# JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5
# JTIwMjAyMC5jcmwwgcMGCCsGAQUFBwEBBIG2MIGzMIGBBggrBgEFBQcwAoZ1aHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJ
# ZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1
# dGhvcml0eSUyMDIwMjAuY3J0MC0GCCsGAQUFBzABhiFodHRwOi8vb25lb2NzcC5t
# aWNyb3NvZnQuY29tL29jc3AwDQYJKoZIhvcNAQEMBQADggIBAH8lKp7+1Kvq3WYK
# 21cjTLpebJDjW4ZbOX3HD5ZiG84vjsFXT0OB+eb+1TiJ55ns0BHluC6itMI2vnwc
# 5wDW1ywdCq3TAmx0KWy7xulAP179qX6VSBNQkRXzReFyjvF2BGt6FvKFR/imR4CE
# ESMAG8hSkPYso+GjlngM8JPn/ROUrTaeU/BRu/1RFESFVgK2wMz7fU4VTd8NXwGZ
# Be/mFPZG6tWwkdmA/jLbp0kNUX7elxu2+HtHo0QO5gdiKF+YTYd1BGrmNG8sTURv
# n09jAhIUJfYNotn7OlThtfQjXqe0qrimgY4Vpoq2MgDW9ESUi1o4pzC1zTgIGtdJ
# /IvY6nqa80jFOTg5qzAiRNdsUvzVkoYP7bi4wLCj+ks2GftUct+fGUxXMdBUv5sd
# r0qFPLPB0b8vq516slCfRwaktAxK1S40MCvFbbAXXpAZnU20FaAoDwqq/jwzwd8W
# o2J83r7O3onQbDO9TyDStgaBNlHzMMQgl95nHBYMelLEHkUnVVVTUsgC0Huj09du
# NfMaJ9ogxhPNThgq3i8w3DAGZ61AMeF0C1M+mU5eucj1Ijod5O2MMPeJQ3/vKBtq
# GZg4eTtUHt/BPjN74SsJsyHqAdXVS5c+ItyKWg3Eforhox9k3WgtWTpgV4gkSiS4
# +A09roSdOI4vrRw+p+fL4WrxSK5nMYIXWDCCF1QCAQEwcTBaMQswCQYDVQQGEwJV
# UzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNy
# b3NvZnQgSUQgVmVyaWZpZWQgQ1MgQU9DIENBIDAzAhMzAAvf/0ou2tAcN/jnAAAA
# C9//MA0GCWCGSAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKFeB/okX2stBiXMeUOsFOibNCXaqgXR
# HRMuhJKUxNx1MA0GCSqGSIb3DQEBAQUABIIBgB+n4Xc3aQsuVB9sNJwYieIv6cjf
# ml2Q6u+G/7i1UAP8/iV7ARLYk8Jh5ezyqEPhbbGF6bAneKViqS2B2oTYyH5/S1bR
# ffPvh37d10jiE14CN5LX69bvyOg/Hd5Hd3b+3xRLQOWPNH6msAW9h/HwQzuUPOTY
# cOuutkjqrmf4YaWHWad/eaGV6fF8YZQw4aQt+YV8zDR7bsFz2n0l04+VOoS75Lcl
# fJWm65QreS1WVmm12trNbXhWaKbLPrN7DvNO1+jr1OQRjXVKWfvf4DDcza+zvd0Z
# TpYPdTQren8VIRy4RTmkgaEAahse8QZdDnsAwMXKgU81WFy3QJRaREgiDpkxmb4A
# /B2B7iMJ2C6dLhAqqsYu/R5eD0a9hdPUEl9KVHx3ZGOSU8313+wLCT6r3Ysn2EZC
# DCvoplOLvymWoHI9o+dpFq0XjOp6QrSJ6k/scLVvVATVhdWcG2HPio3vqD6tvuiO
# 56nxMzO2MUuLJmo6Trszn+cp7k5r5ps4t69bW6GCFLEwghStBgorBgEEAYI3AwMB
# MYIUnTCCFJkGCSqGSIb3DQEHAqCCFIowghSGAgEDMQ8wDQYJYIZIAWUDBAIBBQAw
# ggFpBgsqhkiG9w0BCRABBKCCAVgEggFUMIIBUAIBAQYKKwYBBAGEWQoDATAxMA0G
# CWCGSAFlAwQCAQUABCACAUGgW9Fb+FU4QyHmG8OZ3HkedTsHgwxITf/uSiwSkgIG
# avNLGunZGBIyMDI2MTExMTE4NDkxOC43M1owBIACAfSggemkgeYwgeMxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29m
# dCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBU
# U1MgRVNOOjdBMUEtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3NvZnQgUHVibGlj
# IFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eaCCDykwggeCMIIFaqADAgECAhMz
# AAAABeXPD/9mLsmHAAAAAAAFMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDAeFw0yMDExMTkyMDMyMzFaFw0zNTExMTkyMDQyMzFaMGExCzAJ
# BgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
# BAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAnnznUmP94MWfBX1jtQYioxwe
# 1+eXM9ETBb1lRkd3kcFdcG9/sqtDlwxKoVIcaqDb+omFio5DHC4RBcbyQHjXCwMk
# /l3TOYtgoBjxnG/eViS4sOx8y4gSq8Zg49REAf5huXhIkQRKe3Qxs8Sgp02KHAzn
# Ea/Ssah8nWo5hJM1xznkRsFPu6rfDHeZeG1Wa1wISvlkpOQooTULFm809Z0ZYlQ8
# Lp7i5F9YciFlyAKwn6yjN/kR4fkquUWfGmMopNq/B8U/pdoZkZZQbxNlqJOiBGgC
# Wpx69uKqKhTPVi3gVErnc/qi+dR8A2MiAz0kN0nh7SqINGbmw5OIRC0EsZ31WF3U
# xp3GgZwetEKxLms73KG/Z+MkeuaVDQQheangOEMGJ4pQZH55ngI0Tdy1bi69INBV
# 5Kn2HVJo9XxRYR/JPGAaM6xGl57Ei95HUw9NV/uC3yFjrhc087qLJQawSC3xzY/E
# XzsT4I7sDbxOmM2rl4uKK6eEpurRduOQ2hTkmG1hSuWYBunFGNv21Kt4N20AKmbe
# uSnGnsBCd2cjRKG79+TX+sTehawOoxfeOO/jR7wo3liwkGdzPJYHgnJ54UxbckF9
# 14AqHOiEV7xTnD1a69w/UTxwjEugpIPMIIE67SFZ2PMo27xjlLAHWW3l1CEAFjLN
# Hd3EQ79PUr8FUXetXr0CAwEAAaOCAhswggIXMA4GA1UdDwEB/wQEAwIBhjAQBgkr
# BgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUa2koOjUvSGNAz3vYr0npPtk92yEwVAYD
# VR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggr
# BgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAPBgNVHRMBAf8EBTAD
# AQH/MB8GA1UdIwQYMBaAFMh+0mqFKhvKGZgEByfPUBBPaKiiMIGEBgNVHR8EfTB7
# MHmgd6B1hnNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNy
# b3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZp
# Y2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3JsMIGUBggrBgEFBQcBAQSBhzCBhDCB
# gQYIKwYBBQUHMAKGdWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2Vy
# dHMvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIw
# Q2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAyMDIwLmNydDANBgkqhkiG9w0BAQwF
# AAOCAgEAX4h2x35ttVoVdedMeGj6TuHYRJklFaW4sTQ5r+k77iB79cSLNe+GzRjv
# 4pVjJviceW6AF6ycWoEYR0LYhaa0ozJLU5Yi+LCmcrdovkl53DNt4EXs87KDogYb
# 9eGEndSpZ5ZM74LNvVzY0/nPISHz0Xva71QjD4h+8z2XMOZzY7YQ0Psw+etyNZ1C
# esufU211rLslLKsO8F2aBs2cIo1k+aHOhrw9xw6JCWONNboZ497mwYW5EfN0W3zL
# 5s3ad4Xtm7yFM7Ujrhc0aqy3xL7D5FR2J7x9cLWMq7eb0oYioXhqV2tgFqbKHeDi
# ck+P8tHYIFovIP7YG4ZkJWag1H91KlELGWi3SLv10o4KGag42pswjybTi4toQcC/
# irAodDW8HNtX+cbz0sMptFJK+KObAnDFHEsukxD+7jFfEV9Hh/+CSxKRsmnuiovC
# WIOb+H7DRon9TlxydiFhvu88o0w35JkNbJxTk4MhF/KgaXn0GxdH8elEa2Imq45g
# aa8D+mTm8LWVydt4ytxYP/bqjN49D9NZ81coE6aQWm88TwIf4R4YZbOpMKN0Cyej
# aPNN41LGXHeCUMYmBx3PkP8ADHD1J2Cr/6tjuOOCztfp+o9Nc+ZoIAkpUcA/X2gS
# MkgHAPUvIdtoSAHEUKiBhI6JQivRepyvWcl+JYbYbBh7pmgAXVswggefMIIFh6AD
# AgECAhMzAAAAW0q1jUEybdx0AAAAAABbMA0GCSqGSIb3DQEBDAUAMGExCzAJBgNV
# BAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMT
# KU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMB4XDTI2
# MDEwODE4NTkwNVoXDTI3MDEwNzE4NTkwNVowgeMxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
# ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdBMUEt
# MDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lIFN0
# YW1waW5nIEF1dGhvcml0eTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AJBUzBbbnlDXee0B0KD5G4/475thFyfctCyuESTWQXvlLi4Wx/td2qUdeq4ideeg
# 6VWhiOHfu3wJV4TUGSRtqh9Ccr1BmiBKv9iuFpgHyIBu5Qx38ZsxwlFeXVS+ZqJJ
# KnXRbDNQdcYSoC/6c0hQJ/PH50DBRDQkPXVwyFizLrRH9AlrJeUg7BKeT23zftS8
# /KOJLvEEbHOF6pSOY3ZVprZUWbWjWwRTmoHaQ/E8vrWtLNyEJ+b089VW1Ikra3t4
# GTB5Wby3CL1K2zYnAxBIvafsKMFyj9OuXHcTPKMDoFSMeamG9MKOMb6uoG1PjdnD
# gsLP6EOMRSzrLL7jED1mbB9RSd9fhty+HQr6vZgsBn6oUy+YTpNVLskwdtUM82WY
# AkPztlOt3AiL0qyV7/U3j/uq3vHMjPM0w0340M57Nei0g4BCcMt0dbqoc91VgCb3
# /36sHQANontn1HOF2oLk8190QRS43isHVra8H8sf5+GlqIYsYiCKX04HZiOzZW82
# 6nVI6d++8lyTeWmpj90Ua9uPbJhVjwE3oh6tO510ySqmSMSLEN07p3Ibe3E6BAb2
# w93rWzb26+dpSthbKF4kApofqBsWPX4MEtHKSOftPmVTCQ47tghrVuHia9jY+Hsj
# 01m4KW4WtkmVm3L6hMZECMa4sjMxAXz+bX/AJhWTe6TZAgMBAAGjggHLMIIBxzAd
# BgNVHQ4EFgQU7/LqUlWWYhXJdXwgYKx4b8Gv0rYwHwYDVR0jBBgwFoAUa2koOjUv
# SGNAz3vYr0npPtk92yEwbAYDVR0fBGUwYzBhoF+gXYZbaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIw
# VGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNybDB5BggrBgEFBQcBAQRtMGswaQYI
# KwYBBQUHMAKGXWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAy
# MDIwLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4G
# A1UdDwEB/wQEAwIHgDBmBgNVHSAEXzBdMFEGDCsGAQQBgjdMg30BATBBMD8GCCsG
# AQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVw
# b3NpdG9yeS5odG0wCAYGZ4EMAQQCMA0GCSqGSIb3DQEBDAUAA4ICAQAAH+zd+XKh
# 4OxXYMWFmtgilXAQGctOjCUB1w/uBiC/OXcH3Ia4/XbdUhKzFbaiTbIE6vYZKd1p
# 4u7nKOLkawymAMVyuO7LSl6rLKttZIyLhWjTK0zXOz0u4xLq9+bRtBEKJvA6sD5n
# JwH1IO6z1YizyuIRoalMCnbrUixfWxQn4TAmN7t9uk+X2FUThEa3ewzRwhtG+xwa
# AbLMkxRmR24JnfXd1VxKo90+m7Wzuov96Uugx5wZdewiIIm1ZWTj4lCJHup679Lc
# Oa7tAxJMipVaSltQH9fm9TOKczlfxtWuBcLU4duZfqwgsILsH7PMkcX1zwQzQD0y
# AtPhnYz9KNG125bX+iilOe1S8RHqv2bbBpMpao4kcUvQI6dMgKRvFmm1eLbhSNOQ
# plDMTGD1tNVdNGkI96jUu+troUjWMMi46TQfBAHxtDTpRhIu/87vAVQ8Z6RHhFxe
# sz4Ed5JThaIQRAy6GcO/Jk+QzDzoZ0arRIkIsGJ7rZgOVAjx9ctfw8lH9RfjcwB3
# wdGBYNMNVJqQpUai2Taddf5pXzTZEHIqLEF53SrBjIeInoQrP7U5VlXiMQsxewLd
# INrAE2l2TR3KBikb+RQRygbTp8jj2yiC0NCUwG+K+ndglN5RMbXjFW6aKa59Xq+b
# 8XzK/DK+AJtgOpHgJv8Qrk62A+twOVLOpjGCA9QwggPQAgEBMHgwYTELMAkGA1UE
# BhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjACEzMAAABb
# SrWNQTJt3HQAAAAAAFswDQYJYIZIAWUDBAIBBQCgggEtMBoGCSqGSIb3DQEJAzEN
# BgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgR0UunNPuIB+FODKH6c4Flkq8
# YbJnNsCw978s/0nvMkwwgd0GCyqGSIb3DQEJEAIvMYHNMIHKMIHHMIGgBCAvMQNV
# XZ0b0xxlGw8X/3IEybObuT6a5W1d61CW+cGD7zB8MGWkYzBhMQswCQYDVQQGEwJV
# UzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNy
# b3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMAITMwAAAFtKtY1B
# Mm3cdAAAAAAAWzAiBCAHO1MhNODPL8TJwpXMUYtA6IWNG4KcS+KXUtwH5O09pDAN
# BgkqhkiG9w0BAQsFAASCAgBPw0v3o7iuxcbijeIo8ix3zencPiRQuF9Q1rkWTk/Q
# YpFH0MQhDS1J2RI116+g65vyaSGkHa5ceZI8ztStvmjOgtFjudnbSNxYwu60L+im
# vb2WzQVvT6ggfXX4ghIx7wNYmaAG4REKsoD0giuhgoA0F35OrE1eEJl73HIQgjo1
# E3KVlCIv3XxwzPCi+E63GgYXoT0LeswwsIQZHNsuKALI2itUHfkP5jMknCfns4Ds
# S3D659BFlDgt+bhh2/2isTimVbX5mSmCbmetFwqrY27b+8jViYThg0MLnFfws6bn
# iPb098L7HhYrPAi0z5XOseE1urbPxfnP4uQQFoyLjMblnMOqF8YZK1rNu3Zf7Hcj
# At19ddOf0/slZSFysk+cBghMo3L23PeiLTlw1BdBrsySEa5rd1eaeyXx9Gkumr+n
# iMe8FZNuLtYeHEyhs2rKEWy9J4LvuNGRxz/BCgEKVMXxC8sA0K9ufnSPw8df0+IB
# uvYSiewa4muuKPAd1fbi5y7DSQmWk+i/RshFvTyVkEIlpWwQdrysZtT6TwMG424N
# pmn84O/RUyJixOmqjPnBjwDpUkAT+83LXx0/v8f5MZTujk3AwQCsySycBQVlZ6Bd
# vwEnKJTqMU1vTT19hdo3xoOsM9T5ATF2SX/K5qWCUOstBRztS/r+jTCh5yLm9cJs
# PQ==
# SIG # End signature block
