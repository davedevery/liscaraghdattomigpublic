[CmdletBinding()]
param([string] $ConfigPath = $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'config.json' } else { './config.json' }))
if (-not $env:LISCARA_NOCONSOLE) {
    try {
        Add-Type -MemberDefinition '
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList(uint[] lpdwProcessList, uint dwProcessCount);
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern int GetClassName(System.IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);' -Name ConsoleBoot -Namespace Liscaragh -ErrorAction Stop
        $bootBuf = New-Object 'uint[]' 4
        $bootAttached = [Liscaragh.ConsoleBoot]::GetConsoleProcessList($bootBuf, 4)
        $bootWnd = [Liscaragh.ConsoleBoot]::GetConsoleWindow()
        $bootClass = ''
        if ($bootWnd -ne [System.IntPtr]::Zero) {
            $bootSb = New-Object System.Text.StringBuilder 64
            [void][Liscaragh.ConsoleBoot]::GetClassName($bootWnd, $bootSb, 64)
            $bootClass = $bootSb.ToString()
        }
        $bootConPty = ($bootClass -eq 'PseudoConsoleWindow')
        $bootExe = (Get-Process -Id $PID).Path
        $bootPackaged = "$bootExe" -match '\\WindowsApps\\'
        $bootUnpacked = $null; $bootStore = $null
        $bootPf7 = @(
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'pwsh7\pwsh.exe')
            (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
            $(if ($env:ProgramW6432) { Join-Path $env:ProgramW6432 'PowerShell\7\pwsh.exe' })
            'C:\Program Files\PowerShell\7\pwsh.exe'
            $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe' })
        ) | Where-Object { $_ } | Select-Object -Unique
        foreach ($cand in $bootPf7) { if (Test-Path $cand) { $bootUnpacked = $cand; break } }
        if (-not $bootUnpacked) {
            $bootCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if ($bootCmd -and $bootCmd.Source) {
                if ($bootCmd.Source -notmatch '\\WindowsApps\\') { $bootUnpacked = $bootCmd.Source } else { $bootStore = $bootCmd.Source }
            }
        }
        $bootHost = $bootExe
        if ([int]$PSVersionTable.PSVersion.Major -lt 7) {
            if ($bootUnpacked) { $bootHost = $bootUnpacked } elseif ($bootStore) { $bootHost = $bootStore }
        } elseif ($bootPackaged -and $bootUnpacked) {
            $bootHost = $bootUnpacked
        }
        if (($bootHost -ne $bootExe) -or (($bootAttached -le 1) -and $bootConPty)) {
            $bootConhost = Join-Path $env:WINDIR 'System32\conhost.exe'
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            if (Test-Path $bootConhost) {
                $psi.FileName = $bootConhost
                $psi.Arguments = "`"$bootHost`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
            } else {
                $psi.FileName = $bootHost
                $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
            }
            $psi.WorkingDirectory = $PSScriptRoot
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.EnvironmentVariables['LISCARA_NOCONSOLE'] = '1'
            [void][System.Diagnostics.Process]::Start($psi)
            exit 0
        }
    } catch {}
}
if ([int]$PSVersionTable.PSVersion.Major -lt 7) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(
            "This app is running under Windows PowerShell 5.1 and needs PowerShell 7.`n`n" +
            "If PowerShell 7 IS installed: open the app from its DESKTOP SHORTCUT, not by right-clicking the script. 'Run with PowerShell' uses the old 5.1. You can also run it directly:`n" +
            "    pwsh -File `"$PSCommandPath`"`n`n" +
            "If PowerShell 7 is NOT installed: install it from https://aka.ms/powershell and re-run the installer, then use the desktop shortcut.",
            'PowerShell 7 required', 'OK', 'Warning') | Out-Null
    } catch {
        Write-Host "This app needs PowerShell 7. Open it from the desktop shortcut, or run:  pwsh -File `"$PSCommandPath`"  . If PS7 is not installed, install it from https://aka.ms/powershell and re-run the installer." -ForegroundColor Red
    }
    exit 1
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
$script:InstanceMutex = $null
try {
    $createdNew = $false
    $script:InstanceMutex = New-Object System.Threading.Mutex($true, 'Local\LiscaraghMigrate.SingleInstance', [ref]$createdNew)
    if (-not $createdNew) {
        try { [System.Threading.EventWaitHandle]::OpenExisting('Local\LiscaraghMigrate.Activate').Set() | Out-Null } catch {}
        exit 0
    }
} catch {}
try {
    Add-Type -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);' -Name Taskbar -Namespace Liscaragh -ErrorAction Stop
    [void][Liscaragh.Taskbar]::SetCurrentProcessExplicitAppUserModelID('Liscaragh.Migrate')
} catch {}
$ErrorActionPreference = 'Stop'
$script:EnginePath = Join-Path $PSScriptRoot 'Invoke-LiscaraghMigration.ps1'
try { if (Test-Path $script:EnginePath) { Unblock-File -Path $script:EnginePath -ErrorAction SilentlyContinue } } catch {}
$rp = Resolve-Path -Path $ConfigPath -ErrorAction SilentlyContinue
$script:ConfigPath = if ($rp) { $rp.Path } else { $ConfigPath }
$script:AppConfigPath = $script:ConfigPath
$script:JobsBase   = Split-Path (Split-Path $script:ConfigPath) -Parent
$script:ExpectBase = Split-Path $PSScriptRoot -Parent
if (-not $script:JobsBase) {
    throw "Cannot work out where to keep migration jobs. The tool derives that from the location of config.json, and it was given '$script:ConfigPath', which has no folder above it. Start the tool with -ConfigPath pointing at the full path of config.json inside the Installer folder, for example '$(Join-Path $PSScriptRoot 'config.json')'."
}
if ($script:ExpectBase -and ($script:JobsBase.TrimEnd('\','/') -ne $script:ExpectBase.TrimEnd('\','/'))) {
    throw "This installation is laid out in a way the tool does not support, so it has stopped rather than put your job data somewhere you did not ask for.`n`nIt is installed in:            $script:ExpectBase`nBut from config.json it would keep jobs in: $(Join-Path $script:JobsBase 'jobs')`n`nconfig.json must sit inside the Installer folder ('$PSScriptRoot'), one level below the install root. Move it there and start the tool again. Nothing has been changed."
}
$script:JobsRoot = Join-Path $script:JobsBase 'jobs'
try { if (-not (Test-Path $script:JobsRoot)) { New-Item -ItemType Directory -Path $script:JobsRoot -Force | Out-Null } }
catch { throw "Could not create the migration jobs folder at '$script:JobsRoot': $($_.Exception.Message). In plain terms: the tool cannot write where it keeps your migration jobs. Check the folder permissions, or install somewhere you can write to." }
$script:JobOpen = $false
$script:Cfg = $null
$script:Projects = @()
$script:Map = @{}
$script:Proc = $null
$script:FinProc = $null
$script:Sched = $null
$script:SchedTimer = $null
$script:QuietPausing = $false
$script:StayAwakeOn = $false
try {
    Add-Type -Namespace Liscaragh -Name Win32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] public struct FLASHWINFO { public uint cbSize; public System.IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
[System.Runtime.InteropServices.DllImport("user32.dll")] [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)] public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
'@ -ErrorAction Stop
} catch {}
function Lz6e3a01c6dd {
    try { [void][Liscaragh.Win32]::SetThreadExecutionState(0x80000000 -bor 0x00000001); $script:StayAwakeOn = $true } catch {}
}
function Lza23537be45 {
    try { [void][Liscaragh.Win32]::SetThreadExecutionState(0x80000000); $script:StayAwakeOn = $false } catch {}
}
function Lz7a0b950512 {
    param([string]$Severity)
    try {
        $media = Join-Path $env:WINDIR 'Media'
        $okList  = @('Windows Notify System Generic.wav','Windows Notify.wav','notify.wav','chimes.wav','ding.wav')
        $badList = @('Windows Exclamation.wav','Windows Notify.wav','chord.wav','notify.wav')
        $list = if ($Severity -eq 'ok') { $okList } else { $badList }
        foreach ($f in $list) {
            $p = Join-Path $media $f
            if (Test-Path -LiteralPath $p) {
                $sp = New-Object System.Media.SoundPlayer $p
                $sp.Play()
                return
            }
        }
    } catch {}
    try { if ($Severity -eq 'ok') { [System.Media.SystemSounds]::Asterisk.Play() } else { [System.Media.SystemSounds]::Exclamation.Play() } } catch {}
}
function Lzb0111e4fe8 {
    param([string]$Severity)
    Lz7a0b950512 -Severity $Severity
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
        if ($h -ne [System.IntPtr]::Zero) {
            $fw = New-Object Liscaragh.Win32+FLASHWINFO
            $fw.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][Liscaragh.Win32+FLASHWINFO])
            $fw.hwnd = $h
            $fw.dwFlags = ([uint32]3 -bor [uint32]12)
            $fw.uCount = [uint32]5; $fw.dwTimeout = [uint32]0
            [void][Liscaragh.Win32]::FlashWindowEx([ref]$fw)
        }
    } catch {}
}
$script:StartupUpdateChecked = $false
$script:StartupUpdateTimer = $null
$script:SP = $null
$script:Paused = $false
$script:LastRunArgs = @()
$script:LastRunLabel = ''
$script:ResumeChoice = $null
$script:ResumeWin = $null
$script:ThrM365 = ''
$script:ThrDatto = ''
$script:ScopeTotal = 0
$script:ScopeSkipped = 0
$script:CheckOutcome = $null
$script:CheckFiles = @()
$script:LicenceBlocked = $null
$script:TamperBlocked = $null
$script:TrialMode = $false
$script:TrialCapped = $false
$script:TrialLimitDisplay = 20
$script:TrialCopied = 0
$script:TrialExhausted = $false
$script:TrialRemaining = 0
$script:TrialBucketLabel = ''
$script:QuickStartSections = @(
    @{ H = 'Before you begin';   B = 'Datto and Microsoft 365 are connected once per computer, under Settings > API settings. Every job on this computer then shares that connection. Until it is set up, nothing can connect.' }
    @{ H = 'Quick start';        B = "1.  Job > New, and give the job a name you will recognise later. Your Datto projects are listed automatically.`n2.  Pick a project on the left. On the right, optionally set a Source subfolder to copy just part of it (blank = the whole project), choose where its files should go, and click 'Apply to this project'. Repeat for each project you are migrating.`n3.  Click 'Full migration' and let it run.`n4.  When it finishes, click 'Verify files arrived' to confirm every file is present at the destination.`n`nWant to look before anything copies? Preview and the readiness checks change nothing - they are under 'Run the migration', below the start buttons." }
    @{ H = 'Keeping up to date'; B = "People can keep working in Datto while you migrate. 'Sync new and changed' tops the destination up with anything added or changed since the last run, and 'Verify files arrived' confirms everything is present and current. Just before everyone switches over, run one last sync and verify." }
)
$script:GraphReady = $false
$script:ReportBefore = [datetime]::MinValue
$script:SetResetNote = $null
$script:AppVersion = '2.2.2'
$script:DialogChrome = $null
$script:ActBuf = $null
$script:ActFilter = 'Overview'
$script:ActOpen = $false
$script:TransferMode = 'Datto'
$script:TransferTypes = @(
    [pscustomobject]@{ Id='LocalFs'; Short='Files and Folders'; Title='Files and folders to SharePoint / OneDrive'; Desc='Copy local or network folders into Microsoft 365 and keep them topped up. One-way: it never deletes.'; Status='Live' }
    [pscustomobject]@{ Id='Datto';   Short='Datto Workplace';   Title='Datto Workplace to SharePoint / OneDrive'; Desc='Migrate Datto Workplace projects into Microsoft 365. Full migration, sync top-ups, verification and audit.'; Status='Live' }
    [pscustomobject]@{ Id='Box';     Short='Box.com';               Title='Box to SharePoint / OneDrive';              Desc='Migrate Box content into Microsoft 365.'; Status='Soon' }
    [pscustomobject]@{ Id='Dropbox'; Short='Dropbox';           Title='Dropbox to SharePoint / OneDrive';          Desc='Migrate Dropbox content into Microsoft 365.'; Status='Soon' }
    [pscustomobject]@{ Id='GDrive';  Short='Google Drive';      Title='Google Drive and Shared Drives to SharePoint / OneDrive'; Desc='Migrate Google Drive and Shared Drives into Microsoft 365.'; Status='Soon' }
)
$script:WizAppName = 'Liscaragh Migrate (https://www.liscaragh.com)'
$script:WizAppNamesLegacy = @('Liscaragh Datto Workplace to SharePoint Migration Tool API')
$script:WZ = $null
$script:SC = $null
$script:ES = $null
$script:DS = $null
$script:DC = $null
$script:DX = $null
$script:CodeSignInUpn = ''
$script:WizSetupOk = $false
$script:ConsoleHwnd   = [IntPtr]::Zero
$script:ConsoleOwned  = $false
$script:ConsoleHidden = $false
$script:RegPath = 'HKCU:\Software\DattoMigration'
function Get-RegSetting { param([string]$Name) try { return [string]((Get-ItemProperty -Path $script:RegPath -Name $Name -ErrorAction Stop).$Name) } catch { return $null } }
function Lz933059a102 { param([string]$Name,[string]$Value) if (-not (Test-Path $script:RegPath)) { New-Item -Path $script:RegPath -Force | Out-Null }; Set-ItemProperty -Path $script:RegPath -Name $Name -Value ([string]$Value) }
$script:SecretEntropy = [Text.Encoding]::UTF8.GetBytes('Liscaragh.DattoMigration.v1')
function Lz06a4c2a2d6 {
    param([string]$Name, [string]$Value)
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop | Out-Null
        $b = [System.Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes("$Value"), $script:SecretEntropy, 'CurrentUser')
        $path = Join-Path $script:RegPath 'Secure'
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name $Name -Value ([Convert]::ToBase64String($b))
        return $true
    } catch { return $false }
}
function Lzd2785bb3e8 {
    param([string]$Name)
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop | Out-Null
        $b64 = [string]((Get-ItemProperty -Path (Join-Path $script:RegPath 'Secure') -Name $Name -ErrorAction Stop).$Name)
        if (-not $b64) { return $null }
        $b = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($b64), $script:SecretEntropy, 'CurrentUser')
        return [Text.Encoding]::UTF8.GetString($b)
    } catch { return $null }
}
function Lzff3ae1afba {
    $s = $null
    try { $s = [Environment]::GetEnvironmentVariable('DATTO_CLIENT_SECRET') } catch {}
    if (-not $s) { try { $s = [Environment]::GetEnvironmentVariable('DATTO_CLIENT_SECRET','User') } catch {} }
    if (-not $s) { try { $s = [Environment]::GetEnvironmentVariable('DATTO_CLIENT_SECRET','Machine') } catch {} }
    if (-not $s) { $s = Lzd2785bb3e8 'DATTO_CLIENT_SECRET' }
    return $s
}
function Lz9b56e15ca5 {
    param([string]$Value)
    if (Lz06a4c2a2d6 -Name 'DATTO_CLIENT_SECRET' -Value $Value) {
        try { [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $null, 'User') } catch {}
    } else {
        [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $Value, 'User')
    }
    [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $Value, 'Process')
}
function Lz05b777ab4c {
    try {
        $legacy = [Environment]::GetEnvironmentVariable('DATTO_CLIENT_SECRET','User')
        if ($legacy) {
            if (Lz06a4c2a2d6 -Name 'DATTO_CLIENT_SECRET' -Value $legacy) {
                try { [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $null, 'User') } catch {}
            }
            [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $legacy, 'Process')
            return
        }
        $enc = Lzd2785bb3e8 'DATTO_CLIENT_SECRET'
        if ($enc) { [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $enc, 'Process') }
    } catch {}
}
Lz05b777ab4c
function Expand-ConfigTokens {
    param($Node)
    if ($null -eq $Node) { return }
    foreach ($p in @($Node.PSObject.Properties)) {
        $v = $p.Value
        if ($v -is [string]) { if ($v -match '^reg:(.+)$') { $p.Value = [string](Get-RegSetting $Matches[1]) } }
        elseif ($v -is [System.Management.Automation.PSCustomObject]) { Expand-ConfigTokens $v }
    }
}
$script:ConfigEntropy   = [Text.Encoding]::UTF8.GetBytes('Liscaragh.DattoMigration.config.v1')
$script:ConfigEncMarker = 'LZCFG1:'
function Protect-ConfigText {
    param([string]$Text)
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop | Out-Null
        $b = [System.Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes("$Text"), $script:ConfigEntropy, 'CurrentUser')
        return $script:ConfigEncMarker + [Convert]::ToBase64String($b)
    } catch { return $Text }
}
function Unprotect-ConfigText {
    param([string]$Text)
    if ($null -eq $Text -or -not $Text.StartsWith($script:ConfigEncMarker)) { return $Text }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop | Out-Null
        $b = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($Text.Substring($script:ConfigEncMarker.Length)), $script:ConfigEntropy, 'CurrentUser')
        return [Text.Encoding]::UTF8.GetString($b)
    } catch {
        throw "This job's settings file is encrypted for a different Windows account or machine and cannot be read here. Run the tool under the Windows account that set it up, or re-run setup."
    }
}
function Read-ConfigJson {
    param([string]$Path)
    return (Unprotect-ConfigText (Get-Content $Path -Raw)) | ConvertFrom-Json
}
function Write-ConfigJson {
    param($Cfg, [string]$Path)
    Set-Content -Path $Path -Value (Protect-ConfigText ($Cfg | ConvertTo-Json -Depth 12)) -Encoding UTF8
}
function Protect-ConfigFileInPlace {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { return }
        $d = Split-Path $Path -Parent
        if ((Test-Path (Join-Path $d '.git')) -or ($d -and (Test-Path (Join-Path (Split-Path $d -Parent) '.git')))) { return }
        $raw = Get-Content $Path -Raw
        if ($raw.StartsWith($script:ConfigEncMarker)) { return }
        $null = $raw | ConvertFrom-Json
        $enc = Protect-ConfigText $raw
        if ($enc -ne $raw) { Set-Content -Path $Path -Value $enc -Encoding UTF8 }
    } catch {}
}
function Import-ResolvedConfig {
    param([string]$Path)
    $c = Read-ConfigJson $Path
    Expand-ConfigTokens $c
    return $c
}
Protect-ConfigFileInPlace $script:ConfigPath
function Resolve-Secret {
    param([string]$v)
    if ("$v" -match '^env:(.+)$') {
        $n = $Matches[1]
        $r = [Environment]::GetEnvironmentVariable($n, 'User')
        if (-not $r) { $r = [Environment]::GetEnvironmentVariable($n, 'Machine') }
        if (-not $r) { $r = [Environment]::GetEnvironmentVariable($n) }
        return $r
    }
    return $v
}
function Get-DattoHeader {
    $id = $script:Cfg.datto.clientId
    $sec = Resolve-Secret $script:Cfg.datto.clientSecret
    @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$id`:$sec")) }
}
$script:GraphToken = $null
$script:GraphTokenExp = [DateTimeOffset]::MinValue
$script:LibCache = @{}
function Lzff10dee4f3 {
    param([string]$TenantId,[string]$ClientId,[string]$Thumbprint,[string]$CertStore,[string]$LicencePath)
    $broker = Join-Path $PSScriptRoot 'LiscaraAuth.exe'
    if (-not (Test-Path $broker)) { throw 'Microsoft 365 sign-in is not available on this computer. Re-run the installer to repair the installation.' }
    if (-not $CertStore) { $CertStore = 'Cert:\CurrentUser\My' }
    if (-not $LicencePath) { $LicencePath = Join-Path $PSScriptRoot 'licence.json' }
    $brokerArgs = @('--tenant',"$TenantId",'--client',"$ClientId",'--thumbprint',"$Thumbprint",'--store',"$CertStore",'--expected-tenant',"$TenantId",'--scope','https://graph.microsoft.com/.default')
    if (Test-Path $LicencePath) { $brokerArgs += @('--licence',$LicencePath) }
    $raw  = (& $broker @brokerArgs 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $line = ($raw -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    $obj  = $null; if ($line) { try { $obj = $line | ConvertFrom-Json } catch {} }
    if ($code -eq 0 -and $obj -and $obj.token) {
        $exp = [DateTimeOffset]::UtcNow.AddMinutes(45)
        try { if ($obj.expiresOn) { $exp = ([DateTimeOffset]::Parse("$($obj.expiresOn)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)).AddMinutes(-4) } } catch {}
        return @{ Token = "$($obj.token)"; Exp = $exp; Mode = "$($obj.mode)" }
    }
    $reason = if ($obj -and $obj.reason) { "$($obj.reason)" } else { $raw.Trim() }
    if ($code -eq 5) { throw 'This installation has been modified or is damaged, so Microsoft 365 sign-in will not run. Re-run the installer to restore it.' }
    if ($code -eq 2) { throw "A valid licence is needed for this. $reason" }
    throw "Could not sign in to Microsoft 365. $reason"
}
function Lz9fe56e4482 {
    if ($script:GraphToken -and [DateTimeOffset]::UtcNow -lt $script:GraphTokenExp) { return $script:GraphToken }
    $auth = Lzff10dee4f3 -TenantId "$($script:Cfg.auth.tenantId)" -ClientId "$($script:Cfg.auth.clientId)" -Thumbprint "$($script:Cfg.auth.certThumbprint)" -CertStore "$($script:Cfg.auth.certStore)"
    $script:GraphToken = $auth.Token
    $script:GraphTokenExp = $auth.Exp
    return $script:GraphToken
}
function Lz7287a65440 {
    param([string]$Path)
    $tok = Lz9fe56e4482
    return Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/$Path" -Headers @{ Authorization = "Bearer $tok" }
}
function Lz7758da3d39 {
    if ($script:GraphReady) { return }
    [void](Lz9fe56e4482)
    $script:GraphReady = $true
}
function Lzb07d20bccb {
    $sec = Resolve-Secret $script:Cfg.datto.clientSecret
    if (-not $sec) { throw "Datto secret not set: config references '$($script:Cfg.datto.clientSecret)' but that environment variable is empty. In plain terms: the Datto password has not been set up on this computer yet. Re-run the setup and paste it when asked, or ask your IT contact to set it, then click Connect again." }
    if (-not $script:Cfg.datto.endpointUrl) { throw "Datto endpoint URL is blank in this job's config. In plain terms: the tool does not know which Datto address to connect to. Set it in Settings (for example https://eu.workplace.datto.com/2/api/v1)." }
    $r = Invoke-RestMethod -Uri "$($script:Cfg.datto.endpointUrl.TrimEnd('/'))/file/projects" -Headers (Get-DattoHeader)
    $col = $script:Cfg.datto.fields.collection
    $items = if ($col -and ($r.PSObject.Properties.Name -contains $col)) { $r.$col } elseif ($r -is [array]) { $r } else { $r }
    return @($items | ForEach-Object { [pscustomobject]@{ Id = "$($_.id)"; Name = "$($_.name)" } })
}
function Lzd4aca36325 {
    param([string]$ParentId)
    if (-not $script:Cfg.datto.endpointUrl) { throw "Datto endpoint URL is blank in this job's config." }
    $rel = "$($script:Cfg.datto.apiPaths.listChildren)" -replace '\{parentID\}', $ParentId
    $to = 120; try { if ($script:Cfg.run.throttle.timeoutSec) { $to = [int]$script:Cfg.run.throttle.timeoutSec } } catch {}
    $uri = "$($script:Cfg.datto.endpointUrl.TrimEnd('/'))$rel"
    $capSec = [Math]::Min($to, 45)
    $job = Start-ThreadJob -ScriptBlock {
        param($Uri, $Headers, $TimeoutSec)
        Invoke-RestMethod -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec
    } -ArgumentList $uri, (Get-DattoHeader), $to
    try {
        if (-not (Wait-Job -Job $job -Timeout $capSec)) {
            throw "Datto did not respond within ${capSec}s while listing folders. This can happen during Datto throttling or a network stall - try again in a moment."
        }
        $r = Receive-Job -Job $job -ErrorAction Stop
    } finally {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    $ff  = $script:Cfg.datto.fields
    $col = $ff.collection
    $items = if ($col -and ($r.PSObject.Properties.Name -contains $col)) { $r.$col } elseif ($r -is [array]) { $r } else { $r }
    return @($items | Where-Object { try { [bool]$_.($ff.itemFolder) } catch { $false } } |
        ForEach-Object { [pscustomobject]@{ Id = "$($_.($ff.itemId))"; Name = "$($_.($ff.itemName))" } })
}
$script:GuiReservedDosNames  = @('con','prn','aux','nul') + (0..9 | ForEach-Object { "com$_" }) + (0..9 | ForEach-Object { "lpt$_" })
$script:GuiReservedWholeNames = @('.lock', 'desktop.ini', 'forms')
function ConvertTo-GuiSafeRelPath {
    param([string]$RelPath)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($s in ($RelPath -split '[\\/]')) {
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
        if (($script:GuiReservedDosNames -contains $lb) -or ($script:GuiReservedDosNames -contains $lw) -or
            ($script:GuiReservedWholeNames -contains $lw)) {
            $x = if ($ext) { $base + '_' + $ext } else { $x + '_' }
        }
        $out.Add($x)
    }
    return ($out -join '/')
}
function Join-GuiSubPath {
    param([string]$A, [string]$B)
    $p = @(); foreach ($x in @($A, $B)) { $t = "$x".Trim('/'); if ($t) { $p += $t } }
    return ($p -join '/')
}
function Get-GuiNestFolder {
    param([string]$SpaceName, [object]$ContentsOnly = $null)
    if ($script:TransferMode -eq 'LocalFs') { return '' }
    $co = $false
    if ($null -ne $ContentsOnly) { $co = [bool]$ContentsOnly }
    else { try { if ($ctrl -and $ctrl.ChkSrcContents) { $co = [bool]$ctrl.ChkSrcContents.IsChecked } } catch { } }
    if ($co) { return '' }
    if (-not $SpaceName) { return '' }
    $sanitise = $false
    try { if ($script:Cfg -and ($script:Cfg.run.PSObject.Properties.Name -contains 'sanitiseNames')) {
        $sanitise = [bool]$script:Cfg.run.sanitiseNames } } catch { }
    if ($sanitise) { return (ConvertTo-GuiSafeRelPath $SpaceName) }
    return $SpaceName
}
function Lz855e586988 {
    if (-not $ctrl -or -not $ctrl.LstSource) { return @() }
    return @($ctrl.LstSource.Items | ForEach-Object { "$_".Trim().Trim('/').Trim('\') } | Where-Object { $_ })
}
function Set-SourceFolders {
    param([string[]]$Folders)
    if (-not $ctrl -or -not $ctrl.LstSource) { return }
    $ctrl.LstSource.Items.Clear()
    foreach ($f in @($Folders | ForEach-Object { "$_".Trim().Trim('/').Trim('\') } | Where-Object { $_ })) { [void]$ctrl.LstSource.Items.Add($f) }
    Update-SourceUi
}
function Lz4dcf097695 {
    $f = @(Lz855e586988)
    if ($f.Count -eq 1) { return $f[0] }
    return ''
}
function Lzf866962489 {
    param([string]$Child, [string]$Parent, [switch]$Strict)
    $c  = @((("$Child"  -replace '\\','/') -split '/') | Where-Object { $_ })
    $pa = @((("$Parent" -replace '\\','/') -split '/') | Where-Object { $_ })
    if ($pa.Count -eq 0) { return $true }
    if ($Strict -and $c.Count -le $pa.Count) { return $false }
    if ($c.Count -lt $pa.Count) { return $false }
    for ($i = 0; $i -lt $pa.Count; $i++) { if ($c[$i] -cne $pa[$i]) { return $false } }
    return $true
}
function Lz51c39bc741 {
    param([string[]]$Picked)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($e in @(Lz855e586988)) { [void]$result.Add($e) }
    $dropped = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Picked | ForEach-Object { "$_".Trim().Trim('/').Trim('\') } | Where-Object { $_ })) {
        if ($result -ccontains $p) { continue }
        $covered = $false
        foreach ($k in @($result)) { if (Lzf866962489 -Child $p -Parent $k) { [void]$dropped.Add($p); $covered = $true; break } }
        if ($covered) { continue }
        foreach ($narrow in @($result | Where-Object { Lzf866962489 -Child $_ -Parent $p -Strict })) { [void]$result.Remove($narrow); [void]$dropped.Add($narrow) }
        [void]$result.Add($p)
    }
    Set-SourceFolders -Folders @($result)
    if ($dropped.Count) { Lz5af601c665 ("Overlapping folder(s) merged, kept the broader one: " + ((@($dropped) | Select-Object -Unique) -join ', ')) }
}
function Update-SourceUi {
    $one = $true; try { $one = (@(Lz6d0d60c1fc).Count -le 1) } catch {}
    $n = @(Lz855e586988).Count
    if ($ctrl.LstSource)       { $ctrl.LstSource.IsEnabled = $one }
    if ($ctrl.BtnAddSource)    { $ctrl.BtnAddSource.IsEnabled = $one }
    if ($ctrl.BtnTestSource)   { $ctrl.BtnTestSource.IsEnabled = $one }
    if ($ctrl.BtnRemoveSource) { $ctrl.BtnRemoveSource.IsEnabled = ($one -and $ctrl.LstSource -and @($ctrl.LstSource.SelectedItems).Count -gt 0) }
    if ($ctrl.ChkSrcContents)  { $ctrl.ChkSrcContents.IsEnabled = ($one -and $n -le 1); if ($n -gt 1) { $ctrl.ChkSrcContents.IsChecked = $false } }
    Update-DestPreview
}
function Get-GuiDestSubFolder {
    param([string]$DestType, [string]$SiteUrl, [string]$TargetSubFolder, [string]$SpaceName, [object]$ContentsOnly = $null)
    $extra = @()
    if ($DestType -eq 'SharePoint' -and $SiteUrl -match '://') {
        try {
            $u = [Uri]$SiteUrl
            $segs = @(($u.AbsolutePath.Trim('/') -split '/') | Where-Object { $_ -ne '' })
            if ($segs.Count -ge 2 -and (@('sites','teams') -contains $segs[0].ToLower())) {
                if ($segs.Count -gt 2) { $extra = $segs[2..($segs.Count - 1)] }
            } elseif ($segs.Count -ge 1) { $extra = $segs }
            $extra = @($extra | ForEach-Object { [uri]::UnescapeDataString($_) })
        } catch { }
    }
    $subParts = @($extra) + @(($TargetSubFolder -split '[\\/]') | Where-Object { $_ -ne '' })
    return (Join-GuiSubPath ($subParts -join '/') (Get-GuiNestFolder $SpaceName -ContentsOnly $ContentsOnly))
}
function Get-GuiShortSite {
    param([string]$Url)
    try { $u = [Uri]$Url; $p = "$($u.AbsolutePath)".Trim('/'); if ($p) { return $p } ; return $u.Host } catch { return $Url }
}
function Lz5348656d18 {
    $src = Lz4dcf097695
    $box = "$($ctrl.TxtFolder.Text)".Trim().Trim('/').Trim('\')
    if ($ctrl.ChkSrcContents -and $ctrl.ChkSrcContents.IsChecked) { return $box }
    return (Lzb68cff8f93 -TargetSubFolder $box -SourceSubPath $src)
}
function Lz48158eb74f {
    if ($script:NestSuspend) { return }
    try {
        $src = Lz4dcf097695
        $box = "$($ctrl.TxtFolder.Text)".Trim().Trim('/').Trim('\')
        if ($ctrl.ChkSrcContents -and $ctrl.ChkSrcContents.IsChecked) { return }
        if (-not $box -or -not $src) { return }
        $norm = Lzb68cff8f93 -TargetSubFolder $box -SourceSubPath $src
        if ($norm -eq $box) { return }
        $ctrl.TxtFolder.Text = $norm
        $dropped = $box.Substring($norm.Length).Trim('/')
        Lz5af601c665 "Removed '$dropped' from the folder box: the source folder you picked is already part of the path, so it would have landed twice."
        Update-DestPreview
    } catch { }
}
function Lzb68cff8f93 {
    param([string]$TargetSubFolder, [string]$SourceSubPath)
    $t = @((("$TargetSubFolder" -replace '\\', '/') -split '/') | Where-Object { $_ })
    $s = @((("$SourceSubPath"  -replace '\\', '/') -split '/') | Where-Object { $_ })
    if ($t.Count -eq 0 -or $s.Count -eq 0) { return ($t -join '/') }
    for ($k = [Math]::Min($t.Count, $s.Count); $k -ge 1; $k--) {
        $tail = ($t[($t.Count - $k)..($t.Count - 1)] -join '/')
        $head = ($s[0..($k - 1)] -join '/')
        if ($tail.ToLower() -eq $head.ToLower()) {
            if ($t.Count - $k -le 0) { return '' }
            return (($t[0..($t.Count - $k - 1)]) -join '/')
        }
    }
    return ($t -join '/')
}
function Get-GuiLandingPath {
    param([string]$DestType, [string]$SiteUrl, [string]$TargetSubFolder, [string]$SpaceName, [string]$SourceSubPath, [bool]$ContentsOnly = $false)
    $target = Get-GuiDestSubFolder -DestType $DestType -SiteUrl $SiteUrl -TargetSubFolder $TargetSubFolder -SpaceName $SpaceName -ContentsOnly $ContentsOnly
    if ($ContentsOnly) { return $target }
    $mode = ''; try { $mode = "$script:TransferMode" } catch {}
    if ($mode -eq 'LocalFs') {
        $seed = "$SpaceName"
        $san = $false
        try { if ($script:Cfg -and ($script:Cfg.run.PSObject.Properties.Name -contains 'sanitiseNames')) { $san = [bool]$script:Cfg.run.sanitiseNames } } catch {}
        if ($san) { $seed = ConvertTo-GuiSafeRelPath $seed }
        return (Join-GuiSubPath $target $seed)
    }
    return (Join-GuiSubPath $target ("$SourceSubPath".Trim().Trim('/').Trim('\')))
}
function Lzc7583c6c9b {
    param([string]$ProjectId, [string]$SubPath)
    $curId = "$ProjectId"; $curPath = ''
    foreach ($seg in @($SubPath -split '/' | Where-Object { $_ })) {
        $kids = @(Lzd4aca36325 -ParentId $curId)
        $hit = $kids | Where-Object { $_.Name -eq $seg } | Select-Object -First 1
        if (-not $hit) {
            $names = @($kids | ForEach-Object { $_.Name } | Sort-Object)
            $shown = if ($names.Count -gt 15) { (($names | Select-Object -First 15) -join ', ') + ", ...(+$($names.Count - 15) more)" } else { ($names -join ', ') }
            $where = if ($curPath) { "/$curPath" } else { 'the project root' }
            throw "no folder named '$seg' under $where. Folders actually there: $shown"
        }
        $curId = $hit.Id; $curPath = if ($curPath) { "$curPath/$seg" } else { $seg }
    }
    return @{ SubfolderCount = @(Lzd4aca36325 -ParentId $curId).Count }
}
function ConvertTo-Slug { param([string]$n) return ($n -replace '[^\w\-]','-') -replace '-+','-' }
function Lz94b2a58c41 {
    param([string]$Url)
    try {
        $u = [Uri]$Url
        $segs = @(($u.AbsolutePath.Trim('/') -split '/') | Where-Object { $_ })
        $sitePath = if ($segs.Count -ge 2) { "/$($segs[0])/$($segs[1])" } else { '' }
        $siteId = if ($sitePath) { "$($u.Host):$sitePath" } else { $u.Host }
        return Lz7287a65440 -Path "sites/$siteId"
    } catch { return $null }
}
function Lz6980b92f23 {
    param([string]$Search)
    $q = "$Search".Trim()
    if (-not $q) { $q = '*' }
    $resp = Lz7287a65440 -Path ("sites?search=" + [uri]::EscapeDataString($q))
    if (-not $resp) { return @() }
    return @($resp.value | Where-Object { $_.webUrl } | ForEach-Object {
        [pscustomobject]@{
            Name = "$(if ($_.displayName) { $_.displayName } elseif ($_.name) { $_.name } else { $_.webUrl })"
            Url  = "$($_.webUrl)"
        }
    } | Sort-Object Name)
}
function Lzc92872bdd0 {
    param([string]$Url, [switch]$Refresh)
    $key = "$Url".TrimEnd('/')
    if (-not $Refresh -and $script:LibCache.ContainsKey($key)) { return $script:LibCache[$key] }
    $site = Lz94b2a58c41 -Url $Url
    if (-not $site) { return $null }
    $resp = Lz7287a65440 -Path "sites/$($site.id)/drives"
    $names = @($resp.value | ForEach-Object { $_.name })
    $script:LibCache[$key] = $names
    return $names
}
function Get-GuiPathSegment {
    param([string]$RelPath)
    if (-not $RelPath) { return 'root' }
    $esc = (($RelPath -split '/' | Where-Object { $_ -ne '' } | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
    return "root:/$($esc):"
}
function Lz48143bf7eb {
    if ($ctrl.RbOneDrive.IsChecked) {
        $upn = "$($ctrl.TxtLoc.Text)".Trim()
        if (-not $upn) { throw "Enter the user's email / sign-in address first, then Browse." }
        $d = Lz7287a65440 -Path "users/$([uri]::EscapeDataString($upn))/drive"
        return @{ DriveId = "$($d.id)"; Label = "OneDrive of $upn" }
    }
    $site = "$($ctrl.TxtLoc.Text)".Trim()
    if (-not $site) { throw "Enter the SharePoint site URL first, then Browse." }
    $s = Lz94b2a58c41 -Url $site
    if (-not $s) { throw "That SharePoint site could not be found. Check the address (…/sites/Name)." }
    $drives = @((Lz7287a65440 -Path "sites/$($s.id)/drives").value)
    $lib = "$($ctrl.TxtLib.Text)".Trim()
    $d = if ($lib) { $drives | Where-Object { "$($_.name)" -eq $lib } | Select-Object -First 1 } else { $drives | Select-Object -First 1 }
    if (-not $d) { throw "Library '$lib' was not found on that site. Click Browse beside the Library box to see the options." }
    return @{ DriveId = "$($d.id)"; Label = "$($d.name)" }
}
function Lz046fd0f55c {
    param([string]$DriveId, [string]$RelPath)
    $url = "https://graph.microsoft.com/v1.0/drives/$DriveId/$(Get-GuiPathSegment $RelPath)/children?`$select=name,folder&`$top=200"
    $tok = Lz9fe56e4482; $names = @()
    while ($url) {
        $resp = Invoke-RestMethod -Method GET -Uri $url -Headers @{ Authorization = "Bearer $tok" }
        $names += @($resp.value | Where-Object { $_.folder } | ForEach-Object { "$($_.name)" })
        $url = $resp.'@odata.nextLink'
    }
    return $names
}
function Lzf704a5452a {
    param([string]$DriveId, [string]$RelPath, [string]$Name)
    $url = "https://graph.microsoft.com/v1.0/drives/$DriveId/$(Get-GuiPathSegment $RelPath)/children"
    $tok = Lz9fe56e4482
    $body = @{ name = $Name; folder = @{}; '@microsoft.graph.conflictBehavior' = 'fail' } | ConvertTo-Json
    Invoke-RestMethod -Method POST -Uri $url -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json' -Body $body | Out-Null
}
function Lz6f257e43c1 {
    $fp = $script:FP
    $fp.Lst.Items.Clear()
    $fp.Lbl.Text = if ($fp.Path) { "Current folder:  /$($fp.Path)" } else { "Current folder:  / (top level)" }
    try {
        $folders = @(Lz046fd0f55c -DriveId $fp.Drive -RelPath $fp.Path | Sort-Object)
        if ($folders.Count) { foreach ($f in $folders) { [void]$fp.Lst.Items.Add($f) } }
        else { [void]$fp.Lst.Items.Add('(no subfolders here)') }
    } catch { [void]$fp.Lst.Items.Add("(could not list folders: $($_.Exception.Message))") }
}
function Lze981e5a1cf {
    param([string]$Item)
    return ([bool]$Item) -and ($Item -notmatch '^\(')
}
function Lz4ac2bac2f1 {
    param($State, [string]$Current)
    $sel = "$($State.Lst.SelectedItem)"
    if (-not (Lze981e5a1cf -Item $sel)) { return $Current }
    if ($State.ContainsKey('Current') -and $State.Current -is [hashtable]) {
        if (-not $State.Current.ContainsKey($sel)) { return $Current }
    }
    if ($Current) { return "$Current/$sel" }
    return $sel
}
function Lz3d5782fcc9 {
    param($State, [string]$Current)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($State.Lst.SelectedItems)) {
        $name = "$s"
        if (-not (Lze981e5a1cf -Item $name)) { continue }
        if ($State.ContainsKey('Current') -and $State.Current -is [hashtable] -and -not $State.Current.ContainsKey($name)) { continue }
        if ($Current) { [void]$out.Add("$Current/$name") } else { [void]$out.Add($name) }
    }
    if ($out.Count -eq 0 -and $Current) { [void]$out.Add($Current) }
    return @($out)
}
function Lzf2bdb83033 {
    param($State)
    if (-not $State.ContainsKey('Use') -or -not $State.Use) { return }
    $selCount = 0; try { $selCount = @($State.Lst.SelectedItems).Count } catch { $selCount = 0 }
    if ($selCount -gt 1) { $State.Use.Content = "Choose $selCount folders"; return }
    $sel = "$($State.Lst.SelectedItem)"
    $ok = Lze981e5a1cf -Item $sel
    if ($ok -and $State.ContainsKey('Current') -and $State.Current -is [hashtable]) {
        $ok = $State.Current.ContainsKey($sel)
    }
    if (-not $ok) { $State.Use.Content = 'Choose Folder'; return }
    $disp = $sel
    if ($disp.Length -gt 20) { $disp = $disp.Substring(0, 19).TrimEnd() + '...' }
    $State.Use.Content = "Choose '$disp'"
}
function Lzab148c6c37 {
    param([string]$StartSearch)
    [xml]$sx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Find a SharePoint site" Width="620" Height="520" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="18,12">
      <StackPanel>
        <TextBlock Text="Find a SharePoint site" Foreground="White" FontSize="15" FontWeight="SemiBold"/>
        <TextBlock Text="Search your tenant instead of typing an address." Foreground="#9BA1AA" FontSize="12" Margin="0,2,0,0"/>
      </StackPanel>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="14,10">
      <DockPanel LastChildFill="True">
        <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="Cancel" Padding="14,4" Margin="8,0,0,0" MinWidth="88" IsCancel="True"/>
        <Button x:Name="BtnUse" DockPanel.Dock="Right" Content="Use this site" Padding="14,4" Margin="8,0,0,0" MinWidth="120" MaxWidth="260" IsDefault="True"/>
        <TextBlock x:Name="LblCount" VerticalAlignment="Center" Foreground="#667085" FontSize="12" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
    </Border>
    <DockPanel DockPanel.Dock="Top" Margin="14,12,14,6" LastChildFill="True">
      <Button x:Name="BtnGo" DockPanel.Dock="Right" Content="Search" Padding="12,3" Margin="6,0,0,0" MinWidth="80"/>
      <TextBlock DockPanel.Dock="Left" Text="Search:" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox x:Name="TxtSearch" VerticalAlignment="Center" Padding="4,3"/>
    </DockPanel>
    <TextBlock DockPanel.Dock="Top" Margin="14,0,14,6" Foreground="#98A2B3" FontSize="11"
               Text="Type part of a site name, or leave blank to list them all. Double-click a site to pick it."/>
    <ListBox x:Name="LstSites" Margin="14,0,14,12" DisplayMemberPath="Name"/>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $sx))
    Lz2e8ddc8b18 $w
    $lst = $w.FindName('LstSites'); $txt = $w.FindName('TxtSearch')
    $go = $w.FindName('BtnGo'); $use = $w.FindName('BtnUse'); $cnt = $w.FindName('LblCount')
    $txt.Text = "$StartSearch"
    $script:SP2 = @{ Result = $null; Win = $w; Lst = $lst; Txt = $txt; Cnt = $cnt; Use = $use }
    $search = {
        $s = $script:SP2
        $s.Lst.Items.Clear()
        $s.Cnt.Text = 'Searching...'
        try {
            $hits = @(Lz6980b92f23 -Search $s.Txt.Text)
            foreach ($h in $hits) { [void]$s.Lst.Items.Add($h) }
            $s.Cnt.Text = if ($hits.Count) { "$($hits.Count) site(s) found" } else { 'No sites matched. Try fewer letters.' }
        } catch {
            $s.Cnt.Text = "Could not search: $($_.Exception.Message)"
        }
    }
    $go.Add_Click($search)
    $txt.Add_KeyDown({ param($src, $e) if ("$($e.Key)" -eq 'Return') { & $script:SP2.Search; $e.Handled = $true } })
    $script:SP2.Search = $search
    $pick = {
        $sel = $script:SP2.Lst.SelectedItem
        if (-not $sel) { $script:SP2.Cnt.Text = 'Pick a site from the list first.'; return }
        $script:SP2.Result = "$($sel.Url)"
        $script:SP2.Win.DialogResult = $true
    }
    $use.Add_Click($pick)
    $lst.Add_MouseDoubleClick($pick)
    $lst.Add_SelectionChanged({
        $s = $script:SP2
        if ($s.Lst.SelectedItem) { $s.Cnt.Text = "$($s.Lst.SelectedItem.Url)" }
    })
    & $search
    [void]$w.ShowDialog()
    return $script:SP2.Result
}
function Lze055499fb7 {
    param([string]$SiteUrl, [string[]]$Libraries)
    [xml]$lx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Choose a document library" Width="540" Height="440" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="18,12">
      <StackPanel>
        <TextBlock Text="Choose a document library" Foreground="White" FontSize="15" FontWeight="SemiBold"/>
        <TextBlock x:Name="Sub" Foreground="#9BA1AA" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="14,10">
      <DockPanel LastChildFill="True">
        <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="Cancel" Padding="14,4" Margin="8,0,0,0" MinWidth="88" IsCancel="True"/>
        <Button x:Name="BtnUse" DockPanel.Dock="Right" Content="Use this library" Padding="14,4" Margin="8,0,0,0" MinWidth="130" MaxWidth="260" IsDefault="True"/>
        <TextBlock x:Name="LblCount" VerticalAlignment="Center" Foreground="#667085" FontSize="12" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
    </Border>
    <TextBlock DockPanel.Dock="Top" Margin="14,10,14,6" Foreground="#98A2B3" FontSize="11"
               Text="These are the document libraries on the site above. Double-click one to pick it."/>
    <ListBox x:Name="LstLibs" Margin="14,0,14,12"/>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $lx))
    Lz2e8ddc8b18 $w
    $lst = $w.FindName('LstLibs'); $use = $w.FindName('BtnUse'); $cnt = $w.FindName('LblCount')
    ($w.FindName('Sub')).Text = "$SiteUrl"
    foreach ($l in @($Libraries)) { [void]$lst.Items.Add("$l") }
    $cnt.Text = "$((@($Libraries)).Count) library(ies) on this site"
    $script:LP = @{ Result = $null; Win = $w; Lst = $lst; Cnt = $cnt }
    $pick = {
        $s = $script:LP
        if (-not $s.Lst.SelectedItem) { $s.Cnt.Text = 'Pick a library from the list first.'; return }
        $s.Result = "$($s.Lst.SelectedItem)"
        $s.Win.DialogResult = $true
    }
    $use.Add_Click($pick)
    $lst.Add_MouseDoubleClick($pick)
    [void]$w.ShowDialog()
    return $script:LP.Result
}
function Lz046b4e4e82 {
    param([string[]]$Paths)
    $items = [System.Collections.Generic.List[object]]::new()
    $total = 0
    $staleLabel = if ($script:TransferMode -eq 'LocalFs') { 'Newer at source' } else { 'Newer in Datto' }
    foreach ($p in @($Paths)) {
        if (-not $p -or -not (Test-Path $p)) { continue }
        $rows = @()
        try { $rows = @(Import-Csv $p) } catch { continue }
        foreach ($r in $rows) {
            $cols = $r.PSObject.Properties.Name
            $status = ''; $path = ''; $proj = ''
            if ($cols -contains 'Path' -and $cols -contains 'Side') {
                $status = if ("$($r.Side)" -eq 'InDattoOnly') { 'Missing at destination' } else { 'Extra at destination' }
                $path = "$($r.Path)"; $proj = "$($r.Space)"
            } elseif ($cols -contains 'MissingFile') {
                $status = 'Missing at destination'; $path = "$($r.MissingFile)"; $proj = "$($r.Space)"
            } elseif ($cols -contains 'StaleFile') {
                $status = $staleLabel; $path = "$($r.StaleFile)"; $proj = "$($r.Space)"
            } else { continue }
            $total++
            $path = "$path" -replace '\\','/'
            $i = $path.LastIndexOf('/')
            $leaf = if ($i -ge 0) { $path.Substring($i + 1) } else { $path }
            $loc  = if ($i -ge 0) { '/' + $path.Substring(0, $i) } else { '/' }
            [void]$items.Add([pscustomobject]@{ Status = $status; File = $leaf; Location = $loc; Project = $proj })
        }
    }
    if (-not $items.Count) { (Show-Msg -Text ('The result files could not be read (they may have been moved or deleted since the check ran).') -Caption ('Show files')); return }
    $order = @{ 'Missing at destination' = 0; $staleLabel = 1; 'Extra at destination' = 2 }
    $sorted = @($items | Sort-Object -Property @{Expression={ $order[$_.Status] }}, Location, File)
    $cap = 10000
    $shown = @($sorted | Select-Object -First $cap)
    [xml]$fx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Files behind this result" Width="860" Height="560" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="18,12">
      <StackPanel>
        <TextBlock Text="Files behind this result" Foreground="White" FontSize="15" FontWeight="SemiBold"/>
        <TextBlock x:Name="Sub" Foreground="#9BA1AA" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="14,10">
      <DockPanel LastChildFill="True">
        <Button x:Name="BtnClose" DockPanel.Dock="Right" Content="Close" Padding="14,4" Margin="8,0,0,0" MinWidth="88" IsCancel="True" IsDefault="True"/>
        <Button x:Name="BtnOpenCsv" DockPanel.Dock="Right" Content="Open the CSV" Padding="14,4" Margin="8,0,0,0" MinWidth="120" ToolTip="Open the full list in your spreadsheet app. The CSV holds every row, including anything trimmed from this view."/>
        <TextBlock x:Name="LblCount" VerticalAlignment="Center" Foreground="#667085" FontSize="12" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
    </Border>
    <ListView x:Name="LstFiles" Margin="14,12,14,12">
      <ListView.View>
        <GridView>
          <GridViewColumn Header="Status" Width="160" DisplayMemberBinding="{Binding Status}"/>
          <GridViewColumn Header="File" Width="280" DisplayMemberBinding="{Binding File}"/>
          <GridViewColumn Header="Location" Width="300" DisplayMemberBinding="{Binding Location}"/>
          <GridViewColumn Header="Project" Width="160" DisplayMemberBinding="{Binding Project}"/>
        </GridView>
      </ListView.View>
    </ListView>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $fx))
    Lz2e8ddc8b18 $w
    $lst = $w.FindName('LstFiles'); $cnt = $w.FindName('LblCount'); $sub = $w.FindName('Sub')
    foreach ($it in $shown) { [void]$lst.Items.Add($it) }
    $nMiss = @($items | Where-Object Status -eq 'Missing at destination').Count
    $nStale = @($items | Where-Object Status -eq $staleLabel).Count
    $nExtra = @($items | Where-Object Status -eq 'Extra at destination').Count
    $sub.Text = "$('{0:N0}' -f $nMiss) missing" + $(if ($nStale) { ", $('{0:N0}' -f $nStale) $($staleLabel.ToLower())" }) + $(if ($nExtra) { ", $('{0:N0}' -f $nExtra) extra at the destination" })
    $cnt.Text = if ($total -gt $cap) { "Showing the first $('{0:N0}' -f $cap) of $('{0:N0}' -f $total) file(s). The CSV holds every row." } else { "$('{0:N0}' -f $total) file(s)" }
    $script:CF = @{ Paths = @($Paths | Where-Object { $_ -and (Test-Path $_) }) }
    ($w.FindName('BtnOpenCsv')).Add_Click({ foreach ($p in $script:CF.Paths) { try { Start-Process $p } catch {} } })
    [void]$w.ShowDialog()
}
function Lz6723197124 {
    param([string]$DriveId, [string]$Label, [string]$StartPath = '')
    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Choose a destination folder" Width="540" Height="500" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="18,12">
      <StackPanel>
        <TextBlock Text="Choose a destination folder" Foreground="White" FontSize="15" FontWeight="SemiBold"/>
        <TextBlock x:Name="Sub" Foreground="#9BA1AA" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
    </Border>
    <!-- Accept/Cancel declared FIRST so nothing docked beside them can ever take their space.
         This bar survives today only because "New folder..." is short; the source picker had the
         same shape with a long hint and lost its buttons entirely. DECISIONS 062. -->
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="14,10">
      <DockPanel LastChildFill="False">
        <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="Cancel" Padding="14,4" Margin="8,0,0,0" MinWidth="88" IsCancel="True"/>
        <Button x:Name="BtnUse" DockPanel.Dock="Right" Content="Choose Folder" Padding="14,4" Margin="8,0,0,0" MinWidth="120" MaxWidth="230" IsDefault="True"/>
        <Button x:Name="BtnNew" DockPanel.Dock="Left" Content="New folder..." Padding="10,4"/>
      </DockPanel>
    </Border>
    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="14,10,14,4">
      <Button x:Name="BtnUp" Content="Up one level" Padding="8,3"/>
      <TextBlock x:Name="LblPath" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="#333" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
    <ListBox x:Name="LstFolders" Margin="14,4,14,12"/>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $px))
    Lz2e8ddc8b18 $w
    $lst = $w.FindName('LstFolders'); $lbl = $w.FindName('LblPath'); $sub = $w.FindName('Sub')
    $up = $w.FindName('BtnUp'); $new = $w.FindName('BtnNew'); $use = $w.FindName('BtnUse')
    $sub.Text = "In: $Label"
    $script:FP = @{ Drive = $DriveId; Path = ("$StartPath".Trim().Trim('/')); Result = $null; Win = $w; Lst = $lst; Lbl = $lbl }
    Lz6f257e43c1
    $up.Add_Click({ if ($script:FP.Path) { $script:FP.Path = ($script:FP.Path -replace '/?[^/]*$',''); Lz6f257e43c1 } })
    $lst.Add_MouseDoubleClick({ $it = "$($script:FP.Lst.SelectedItem)"; if ($it -and ($it -notmatch '^\(')) { $script:FP.Path = if ($script:FP.Path) { "$($script:FP.Path)/$it" } else { $it }; Lz6f257e43c1 } })
    $new.Add_Click({
        $n = Show-InputBox -Prompt 'Name for the new folder:' -Title 'New folder'
        if ($n) { $n = $n.Trim(); if ($n) { try { Lzf704a5452a -DriveId $script:FP.Drive -RelPath $script:FP.Path -Name $n; Lz6f257e43c1; $script:FP.Lst.SelectedItem = $n } catch { (Show-Msg -Text ("Could not create the folder: $($_.Exception.Message)") -Caption ('New folder')) } } }
    })
    $script:FP.Use = $use
    $lst.Add_SelectionChanged({ Lzf2bdb83033 -State $script:FP })
    $use.Add_Click({
        $script:FP.Result = Lz4ac2bac2f1 -State $script:FP -Current $script:FP.Path
        $script:FP.Win.DialogResult = $true
    })
    Lzf2bdb83033 -State $script:FP
    $r = $w.ShowDialog()
    if ($r -eq $true) { return $script:FP.Result } else { return $null }
}
function Lz3a88cc314e {
    $sp = $script:SP
    $sp.Lst.Items.Clear()
    $node = $sp.Stack[$sp.Stack.Count - 1]
    $path = (@($sp.Stack | Select-Object -Skip 1 | ForEach-Object { $_.Name }) -join '/')
    $sp.Lbl.Text = if ($path) { "Current folder:  /$path" } else { "Current folder:  / (top of project)" }
    try {
        Set-Busy $true 'Loading Datto folders...'
        try { $folders = @(Lzd4aca36325 -ParentId $node.Id | Sort-Object Name) }
        finally { Set-Busy $false }
        $sp.Current = @{}
        foreach ($f in $folders) { $sp.Current["$($f.Name)"] = $f.Id }
        if (@(100,200,250,500,1000,2000,5000) -contains $folders.Count) {
            [void]$sp.Lst.Items.Add("(!) exactly $($folders.Count) subfolders here - the list may be truncated (DECISIONS 028)")
        }
        if ($folders.Count) { foreach ($f in $folders) { [void]$sp.Lst.Items.Add("$($f.Name)") } }
        else { [void]$sp.Lst.Items.Add('(no subfolders here)') }
    } catch { [void]$sp.Lst.Items.Add("(could not list folders: $($_.Exception.Message))") }
}
function Lz15e474afbe {
    param([string]$ProjectId, [string]$ProjectName)
    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Choose a source folder" Width="540" Height="500" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="18,12">
      <StackPanel>
        <TextBlock Text="Choose a folder inside the Datto project to copy" Foreground="White" FontSize="15" FontWeight="SemiBold"/>
        <TextBlock x:Name="Sub" Foreground="#9BA1AA" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
    </Border>
    <!-- BUTTONS ARE DECLARED FIRST, ON PURPOSE. A DockPanel hands out space in declaration
         order, so the long hint (docked Left, ~95 chars) used to claim the whole 512px of
         usable width and leave the Right-docked buttons ZERO: they were still there, laid out
         at zero width, so the dialog showed a truncated sentence and no way to accept or
         cancel. Declare the buttons first and let the text take what is left, with
         LastChildFill and trimming so it can never push them off again. See DECISIONS 062. -->
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="14,10">
      <DockPanel LastChildFill="True">
        <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="Cancel" Padding="14,4" Margin="8,0,0,0" MinWidth="88" IsCancel="True"/>
        <Button x:Name="BtnUse" DockPanel.Dock="Right" Content="Choose Folder" Padding="14,4" Margin="8,0,0,0" MinWidth="120" MaxWidth="230" IsDefault="True"/>
        <TextBlock VerticalAlignment="Center" Foreground="#667085" FontSize="12" TextTrimming="CharacterEllipsis"
                   ToolTip="Double-click a folder to open it. Highlight one and click Choose Folder to pick it. Leave the box blank to copy the whole project."
                   Text="Double-click to open. Blank = the whole project."/>
      </DockPanel>
    </Border>
    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="14,10,14,4">
      <Button x:Name="BtnUp" Content="Up one level" Padding="8,3"/>
      <TextBlock x:Name="LblPath" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="#333" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
    <ListBox x:Name="LstFolders" Margin="14,4,14,12" SelectionMode="Extended"/>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $px))
    Lz2e8ddc8b18 $w
    $lst = $w.FindName('LstFolders'); $lbl = $w.FindName('LblPath'); $sub = $w.FindName('Sub')
    $up = $w.FindName('BtnUp'); $use = $w.FindName('BtnUse')
    $sub.Text = "In: $ProjectName"
    $script:SP = @{ Result = $null; Win = $w; Lst = $lst; Lbl = $lbl; Current = @{}; Stack = (New-Object System.Collections.Generic.List[object]) }
    [void]$script:SP.Stack.Add(@{ Id = "$ProjectId"; Name = '' })
    Lz3a88cc314e
    $up.Add_Click({ if ($script:SP.Stack.Count -gt 1) { $script:SP.Stack.RemoveAt($script:SP.Stack.Count - 1); Lz3a88cc314e } })
    $lst.Add_MouseDoubleClick({ $it = "$($script:SP.Lst.SelectedItem)"; if ($it -and ($it -notmatch '^\(') -and $script:SP.Current.ContainsKey($it)) { [void]$script:SP.Stack.Add(@{ Id = $script:SP.Current[$it]; Name = $it }); Lz3a88cc314e } })
    $script:SP.Use = $use
    $lst.Add_SelectionChanged({ Lzf2bdb83033 -State $script:SP })
    $use.Add_Click({
        $cur = (@($script:SP.Stack | Select-Object -Skip 1 | ForEach-Object { $_.Name }) -join '/')
        $script:SP.Result = Lz3d5782fcc9 -State $script:SP -Current $cur
        $script:SP.Win.DialogResult = $true
    })
    Lzf2bdb83033 -State $script:SP
    $r = $w.ShowDialog()
    if ($r -eq $true) { return $script:SP.Result } else { return $null }
}
$script:LogoB64 = @'
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
/PPHHHOMRwqZZrPuHb9lhYixWAyyhclyYspMTo0XT2SY0GDcOSaWefEvf/nL+PHjIZu45a/VYT7TCA0AmDx5sim2IyJXX32136PqfchHPvKRnMJSfk9O
uRFGnoA1Q73nnnvAF47s2STXXnttwZAxkxycf9199905DkbT/htvvNHY2Jgz57Bn4dM//OEPOc7GAKMu4PI7u7y1OP300z2Nzvu6Y445xlN5cgrPOY5z
6aWXeqClRzBeCKFSypQqPeaYY3K8amaKTJJ+jh/PhIzlz2dAlbF8qdvU1FSw2NGOHTusgjqkqXCaD3mXFoaKCAueQVRUaputa+bMmeeee25zc/Pf//73
3/3udz/96U+XLVvmd7D4HbJmsZPJ5Jw5c4yRllMaUUTWr18Pe1Y0ufbaa0877TQvycV8poGnTjrppCeeeOLLX/7yvffeWzDi1szDaaed9r3vfW/WrFkm
h+hrX/va1KlTP/WpTxlvkhfOb+jAfJrf0li/fr2p0pN/mkd+0T4AmDJlildg3yv5ftJJJy1atMg4S8Jsz83NzWYT8fL6jOfqM5/5zJIlS9ra2jx92Phj
5s+f/z//8z//+Z//6UXVeKLJNHLggQeefPLJOXOOiMPDw5s2bfLrzH51JudLjR0+duxYyKs8f8UVV9xzzz0e4RlN5Iknnvjtb397zjnn+Es7e0rQTTfd
dPDBB19//fVm0Yst33777QeF0mX85sBonGVf2LFRDDr/wAc+MH/+fM98KhZw5MHQtm2/9PJLb721jhQhYFlaq4hcdtllzc3N6XTasqyPfexjZ5111jPP
PPO3v/3tqaeeev3113ft2pWzBbS2tp522mlXX331pEmT/GkHRv/ZvHnzyy+/7EXrGNpatWrVV7/61RtuuMGUVPLAZePsnjNnzt13371s2bK77777qaee
WrdunUkYb2xsnD59+qGHHnr66aebAiTGzWVKd5x//vmTJ08+++yzd+3aZU4+OPbYY4899ljP5+sZrs8+++yJJ55oGC/HvsoPoje8ccMNN1x66aX+8kpa
62g0eumll5rQ55ArbbaSHFLevHnzZz/72dtvv93LdfQ2wU996lN//OMfly1b5g9C8K7LL7/caIMe55sP/OpXv/qjH/0oEonkVA2CvPNhjEI+fvz4f/zj
H5MnT/YSEQ1jH3300cccc8yjjz7qcb5ZxC9+8YvHHXfcpEmT/BPiueMuuuii008//d57733ggQdeeeWVHTt2GBZtamqaNWvWwoUL3/3ud5944on+0vRh
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
'@ -replace '\s', ''
$script:LogoMigrateB64 = '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'
function Set-BrandLogo {
    param($Image, [string]$B64)
    if (-not $Image) { return }
    if (-not $B64) { $B64 = $script:LogoB64 }
    try {
        $bytes = [Convert]::FromBase64String($B64)
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit(); $bmp.StreamSource = $ms; $bmp.CacheOption = 'OnLoad'; $bmp.EndInit(); $bmp.Freeze()
        $Image.Source = $bmp
    } catch {
        Write-Verbose "Brand logo could not be decoded: $($_.Exception.Message)"
    }
}
function Lz2e8ddc8b18 {
    param($Window)
    if (-not $Window) { return }
    try {
        if (-not $script:DialogChrome) {
            $script:DialogChrome = [Windows.Markup.XamlReader]::Parse(@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <!-- Modern tooltips app-wide (180ah): white card, hairline border, 8px radius, and TEXT
       THAT WRAPS at ~400px. The stock WPF tooltip renders one infinite line, which is the
       mile-long bar across the screen on every long hint. -->
  <Style TargetType="ToolTip">
    <Setter Property="Background" Value="White"/>
    <Setter Property="Foreground" Value="#101828"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="HasDropShadow" Value="False"/>
    <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ToolTip">
        <Border Background="White" BorderBrush="#D5DAE1" BorderThickness="1" CornerRadius="8" Padding="11,8" MaxWidth="420" SnapsToDevicePixels="True">
        <ContentPresenter/>
        </Border>
      </ControlTemplate>
    </Setter.Value>
    </Setter>
    <Setter Property="ContentTemplate">
    <Setter.Value>
      <DataTemplate>
        <TextBlock Text="{Binding}" TextWrapping="Wrap" MaxWidth="396"/>
      </DataTemplate>
    </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="Button">
    <Setter Property="Background" Value="White"/>
    <Setter Property="Foreground" Value="#111827"/>
    <Setter Property="BorderBrush" Value="#E4E7EC"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="13,6"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#FDEAD7"/><Setter TargetName="bd" Property="BorderBrush" Value="#E2500F"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.5"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
'@)
        }
        if ($script:DialogChrome) { [void]$Window.Resources.MergedDictionaries.Add($script:DialogChrome) }
    } catch {}
    try {
        $icoPath = Join-Path $PSScriptRoot 'app.ico'
        if (-not (Test-Path $icoPath)) { return }
        $ico = New-Object System.Windows.Media.Imaging.BitmapImage
        $ico.BeginInit(); $ico.UriSource = New-Object System.Uri($icoPath); $ico.CacheOption = 'OnLoad'; $ico.EndInit(); $ico.Freeze()
        $Window.Icon = $ico
    } catch {}
}
function Set-JobChip {
    param([string]$Name)
    if (-not $ctrl -or -not $ctrl.JobChip -or -not $ctrl.LblJob) { return }
    $bc = New-Object System.Windows.Media.BrushConverter
    if ($Name) {
        $ctrl.JobChip.Background = $bc.ConvertFromString('#1C2027')
        $ctrl.JobChip.BorderBrush = $bc.ConvertFromString('#2A2F38')
        if ($ctrl.LblJobPrefix) { $ctrl.LblJobPrefix.Visibility = 'Visible' }
        $ctrl.LblJob.Foreground = [System.Windows.Media.Brushes]::White
        $ctrl.LblJob.Text = $Name
    } else {
        $ctrl.JobChip.Background = [System.Windows.Media.Brushes]::Transparent
        $ctrl.JobChip.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        if ($ctrl.LblJobPrefix) { $ctrl.LblJobPrefix.Visibility = 'Collapsed' }
        $ctrl.LblJob.Foreground = $bc.ConvertFromString('#8B919A')
        $ctrl.LblJob.Text = 'No job open. Use the Job menu to create or open one.'
    }
}
function Lzeb3a1395a1 {
    param([string]$Text, [string]$State = 'off')
    if (-not $ctrl -or -not $ctrl.LblConn) { return }
    $bc = New-Object System.Windows.Media.BrushConverter
    $col = switch ($State) { 'ok' { '#3CCB7F' } 'err' { '#F97066' } default { '#98A2B3' } }
    $ctrl.LblConn.Text = $Text
    $ctrl.LblConn.Foreground = $bc.ConvertFromString($col)
    if ($ctrl.ConnDot) { $ctrl.ConnDot.Fill = $bc.ConvertFromString($col) }
}
$script:ReviewCats = @{
    Verify = @{
        Title = 'Verify the copy'; Sub = 'Confirm the migration: everything arrived, and the totals agree.'
        Items = @(
            @{ Btn = 'BtnValidate';  Title = 'Verify files arrived'; Desc = 'Checks every file is present at the destination and up to date.'; G = 0xE73E; T = '#E7F7EF'; C = '#0E9F6E' }
            @{ Btn = 'BtnSizeCheck'; Title = 'Compare sizes';        Desc = 'Quick totals: files and size, source vs destination.';            G = 0xE8EF; T = '#E7F7EF'; C = '#0E9F6E' }
            @{ Btn = 'BtnDrift';     Title = 'Check for drift';      Desc = 'What changed at the destination since migration.';                G = 0xE823; T = '#FFF4E6'; C = '#B5460F' }
        )
    }
}
$script:ReviewExplain = @{
    BtnPreflight = @{ Title = 'Check readiness'; Go = 'Run the check'; Text = (
        "Scans everything this job would copy and reports the problems BEFORE anything uploads. Nothing at the source or the destination is changed." + "`n`n" +
        "It checks: free space at each destination against what this job needs; names and paths SharePoint would reject, split into what the run will tidy automatically and what needs a decision from you; case-only duplicates and names that would collide after tidying; duplicate content; the largest files; and an estimated duration." + "`n`n" +
        "On a large job it can take a few minutes, because every folder is listed first. You get a readiness report (with the 'Action needed before migration' list at the top) plus a CSV for every finding.") }
    BtnDryRun = @{ Title = 'Preview (no upload)'; Go = 'Run the preview'; Text = (
        "A full rehearsal of the next upload. It lists exactly which files WOULD be copied and where each one would land, without changing anything anywhere." + "`n`n" +
        "It does the same walk as a real run, so a large job takes a similar time to list. Use it when you want to sanity-check the mappings before committing to the real copy." + "`n`n" +
        "You get a preview report and a CSV of every file the run would touch.") }
    BtnSourceReview = @{ Title = 'Datto source review'; Go = 'Run the review'; Text = (
        "A read-only review of the folders in THIS job at the Datto source. Nothing at the source is changed." + "`n`n" +
        "It finds: items shared by PUBLIC link (anyone with the link, no sign-in needed); files currently LOCKED because someone is editing them; and files not yet fully in Datto's cloud storage, which can fail to download during a migration." + "`n`n" +
        "You get a detailed report and a findings CSV - useful before cutover, and as evidence of the source's sharing state at migration time.") }
    BtnValidate = @{ Title = 'Verify files arrived'; Go = 'Run the verification'; Text = (
        "Checks every file this job migrated is actually present at the destination and up to date (not older than the source copy). Read-only on both sides." + "`n`n" +
        "Run it after an upload or sync to prove the copy is complete - it is the check behind the completion certificate. On a large job it takes a while, because it lists the whole destination." + "`n`n" +
        "You get a verification report; any missing or out-of-date file is named.") }
    BtnSizeCheck = @{ Title = 'Compare sizes'; Go = 'Run the comparison'; Text = (
        "Quick totals: how many files and how many gigabytes on each side, source versus destination, per mapping." + "`n`n" +
        "It is the fast sanity check - much quicker than a full verification, but it only compares totals, it does not check individual files. Use Verify files arrived for the file-by-file proof." + "`n`n" +
        "You get a short comparison report.") }
    BtnDrift = @{ Title = 'Check for drift'; Go = 'Run the check'; Text = (
        "Answers one question with evidence: has anything at the destination been changed, deleted or added SINCE this job migrated it? Read-only on both sides." + "`n`n" +
        "It compares the migration's own audit record of every landed file (size and the moment it landed) against the destination as it is right now. A different size or a modified date later than the migration means someone touched the copy afterwards; missing means it was deleted or moved; extra files are listed as not-migrated-by-this-job." + "`n`n" +
        "Use it before cutover to catch anyone editing the target early, and after cutover to settle any 'the migration lost my edits' conversation with dates. You get a drift report and a CSV.") }
        BtnCertificate = @{ Title = 'Completion certificate'; Go = 'Build the certificate'; Text = (
        "Builds the one-page, client-facing sign-off for the most recent COMPLETED migration: what was moved, the totals, the verification result, dated and branded." + "`n`n" +
        "It only issues once a migration has genuinely finished - uploaded, synced until nothing is left, then verified. If those steps are not done yet, it will say what is missing instead." + "`n`n" +
        "You get an HTML certificate ready to send to the client.") }
    BtnProvenance = @{ Title = 'Provenance pack'; Go = 'Build the pack'; Text = (
        "Builds the tamper-evident evidence pack for the most recent real run: a manifest of every migrated file's path, size, content hashes and original modified date, countersigned by an independent timestamp authority." + "`n`n" +
        "Privacy: only the manifest's 32-byte fingerprint leaves this computer - no file names, no content. One pack is also built automatically after every real run; use this to rebuild one or to add the timestamp if it was pending." + "`n`n" +
        "You get the manifest, the timestamp token and a readable HTML summary.") }
}
$script:RC = $null
function Lz0d86a71502 {
    param([string]$Name)
    if ($ctrl -and $Name) { return $ctrl[$Name] }
    return $null
}
function Lz1eb59286f7 {
    param([string]$Key)
    $cat = $script:ReviewCats[$Key]
    if (-not $cat) { return }
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = "$($cat.Title)"; $w.SizeToContent = 'WidthAndHeight'; $w.ResizeMode = 'NoResize'
    $w.WindowStartupLocation = 'CenterScreen'; $w.FontFamily = 'Segoe UI'; $w.FontSize = 13; $w.Background = 'White'
    try { if ($win -and $win.IsVisible) { $w.Owner = $win; $w.WindowStartupLocation = 'CenterOwner' } } catch {}
    $bc = New-Object System.Windows.Media.BrushConverter
    $dock = New-Object System.Windows.Controls.DockPanel; $w.Content = $dock
    $hdr = New-Object System.Windows.Controls.Border; $hdr.Background = '#0F1115'; $hdr.Padding = '20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
    $hs = New-Object System.Windows.Controls.StackPanel
    $ht = New-Object System.Windows.Controls.TextBlock; $ht.Text = "$($cat.Title)"; $ht.Foreground = 'White'; $ht.FontSize = 16; $ht.FontWeight = 'SemiBold'
    $hb = New-Object System.Windows.Controls.TextBlock; $hb.Text = "$($cat.Sub)"; $hb.Foreground = '#9BA1AA'; $hb.TextWrapping = 'Wrap'; $hb.Margin = '0,4,0,0'; $hb.MaxWidth = 560
    [void]$hs.Children.Add($ht); [void]$hs.Children.Add($hb); $hdr.Child = $hs
    [void]$dock.Children.Add($hdr)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.Margin = '18,16,18,18'
    foreach ($it in $cat.Items) {
        $src = Lz0d86a71502 "$($it.Btn)"
        if (-not $src) { continue }
        if ($src.Visibility -ne 'Visible') { continue }
        $card = New-Object System.Windows.Controls.Button
        $card.Width = 210; $card.Margin = '0,0,10,0'; $card.Padding = '14,12'
        $card.HorizontalContentAlignment = 'Left'; $card.VerticalContentAlignment = 'Top'
        $card.IsEnabled = [bool]$src.IsEnabled
        $card.ToolTip = "$($it.Desc)"
        [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($card, $true)
        $card.Tag = "$($it.Btn)"
        $sp = New-Object System.Windows.Controls.StackPanel
        $chip = New-Object System.Windows.Controls.Border
        $chip.Width = 36; $chip.Height = 36; $chip.CornerRadius = '9'; $chip.HorizontalAlignment = 'Left'; $chip.Margin = '0,0,0,8'
        $chip.Background = $bc.ConvertFromString("$($it.T)")
        $gl = New-Object System.Windows.Controls.TextBlock
        $gl.Text = [string][char][int]$it.G; $gl.FontFamily = 'Segoe MDL2 Assets'; $gl.FontSize = 16
        $gl.Foreground = $bc.ConvertFromString("$($it.C)"); $gl.HorizontalAlignment = 'Center'; $gl.VerticalAlignment = 'Center'
        $chip.Child = $gl
        $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = "$($it.Title)"; $t1.FontWeight = 'SemiBold'; $t1.FontSize = 13.5; $t1.Foreground = '#101828'
        $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = "$($it.Desc)"; $t2.TextWrapping = 'Wrap'; $t2.FontSize = 11.5; $t2.Foreground = '#667085'; $t2.Margin = '0,3,0,0'
        [void]$sp.Children.Add($chip); [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2)
        $card.Content = $sp
        $card.Add_Click({
            $bn = "$($args[0].Tag)"
            try { if ($script:RC -and $script:RC.Win) { $script:RC.Win.Close() } } catch {}
            try {
                $ex = $null
                if ($script:ReviewExplain -and $script:ReviewExplain.ContainsKey($bn)) { $ex = $script:ReviewExplain[$bn] }
                if ($ex) {
                    if ((Show-Msg -Caption ($ex.Title) -Text ($ex.Text) -Buttons ('YesNo') -YesLabel ($ex.Go) -NoLabel ('Cancel')) -ne 'Yes') { return }
                }
                $b = Lz0d86a71502 $bn
                if ($b -and $b.IsEnabled) { $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
            } catch {}
        })
        [void]$row.Children.Add($card)
    }
    [void]$dock.Children.Add($row)
    $script:RC = @{ Win = $w }
    try { [void]$w.ShowDialog() } finally { $script:RC = $null }
}
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Liscaragh Migrate" Height="950" Width="1280" MinHeight="740" MinWidth="1000"
        WindowState="Maximized"
        FontFamily="Segoe UI" FontSize="13" Foreground="#111827" Background="#F2F4F7" WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <!-- Palette -->
    <SolidColorBrush x:Key="Accent"     Color="#E2500F"/>
    <SolidColorBrush x:Key="AccentDark" Color="#C24009"/>
    <SolidColorBrush x:Key="AccentSoft" Color="#FDEAD7"/>
    <SolidColorBrush x:Key="Ink"        Color="#111827"/>
    <SolidColorBrush x:Key="InkSoft"    Color="#4B5563"/>
    <SolidColorBrush x:Key="Line"       Color="#E4E7EC"/>

    <!-- Modern tooltips app-wide (180ah): white card, hairline border, 8px radius, and TEXT
         THAT WRAPS at ~400px. The stock WPF tooltip renders one infinite line, which is the
         mile-long bar across the screen on every long hint. -->
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="#101828"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="HasDropShadow" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToolTip">
            <Border Background="White" BorderBrush="#D5DAE1" BorderThickness="1" CornerRadius="8" Padding="11,8" MaxWidth="420" SnapsToDevicePixels="True">
              <ContentPresenter/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Setter Property="ContentTemplate">
        <Setter.Value>
          <DataTemplate>
            <TextBlock Text="{Binding}" TextWrapping="Wrap" MaxWidth="396"/>
          </DataTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Dark app-bar menu (180x, polish round). The implicit MenuItem style keeps every SUBMENU
         item dark-on-light (submenu popups are light); the keyed TopMenuItem style is applied ONLY
         to the three top-level headers, giving them light text on the dark strip and a custom
         template (the popup part is required or submenus would not open). This split is what
         avoids the classic white-on-white popup trap. -->
    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="#101828"/>
    </Style>
    <Style x:Key="TopMenuItem" TargetType="MenuItem">
      <!-- White and semibold (180z): the earlier #CBD2DA read as washed-out on the dark strip
           (Dave, 24 July: "the white font is not standing out"). -->
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="bd" Background="Transparent" CornerRadius="6" Padding="11,5" Margin="1,0">
              <Grid>
                <ContentPresenter ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>
                <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                  <Border Background="White" BorderBrush="#D5DAE1" BorderThickness="1" CornerRadius="8" Padding="4" Margin="0,4,0,0">
                    <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                  </Border>
                </Popup>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="bd" Property="Background" Value="#232833"/><Setter Property="Foreground" Value="White"/></Trigger>
              <Trigger Property="IsSubmenuOpen" Value="True"><Setter TargetName="bd" Property="Background" Value="#232833"/><Setter Property="Foreground" Value="White"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Segmented control (180x): the destination choice as one grey pill holding three segments;
         the checked segment is the white raised one. Radio semantics unchanged. -->
    <Style x:Key="Segment" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#667085"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="bd" Background="Transparent" CornerRadius="7" Padding="12,5" Margin="1,0">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True"><Setter TargetName="bd" Property="Background" Value="White"/><Setter TargetName="bd" Property="BorderBrush" Value="#E4E7EC"/><Setter TargetName="bd" Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="#101828"/></Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#101828"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Card look for every GroupBox: rounded white panel, no classic GroupBox chrome (180t).
         Deliberately NO DropShadowEffect: WPF renders the CHILDREN through the effect, which can
         soften text; a crisp border on a soft canvas reads as a card without the cost. -->
    <Style TargetType="GroupBox">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="GroupBox">
            <Border Background="White" BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="12" Padding="12,9,12,10" SnapsToDevicePixels="True">
              <DockPanel>
                <ContentPresenter DockPanel.Dock="Top" ContentSource="Header" RecognizesAccessKey="True" Margin="4,0,4,8"/>
                <ContentPresenter/>
              </DockPanel>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Default button (180z, matched to the approved mock's .btn): white card, hairline border,
         8px radius, 13px SEMIBOLD text. Applies to every plain button in this window. -->
    <Style TargetType="Button">
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="13,6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{StaticResource AccentSoft}"/><Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Accent-filled button (the one clear primary action, e.g. Connect). -->
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="16,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="#E2500F" CornerRadius="8" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#C24009"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Button-style system (DECISIONS 154). Four intents, one look each, so buttons stop being a
         scatter of one-off inline colours:
           Primary      - accent fill, the single dominant action (Connect).
           Secondary    - soft outline, neutral secondary actions (Schedule).
           Attention    - amber, a state-specific action that only lights when it applies (Rerun failed).
           Tile/PrimaryTile - the large titled command cards for the run itself.
         Stop keeps its red Tile tint as the destructive member of the tile family. -->
    <Style x:Key="Secondary" TargetType="Button">
      <!-- 180z: neutralised to the mock's white-outline look. The old blue-on-blue tint was the
           one button family left outside the new language and read as dated beside it. The
           Secondary INTENT (a named, non-primary action) keeps its own style key so it can
           diverge again without hunting call sites. -->
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{StaticResource AccentSoft}"/><Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Attention" TargetType="Button">
      <Setter Property="Foreground" Value="#B5460F"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="#FFFAEB" BorderBrush="#FEC84B" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#B5460F"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Command-tile button: flat card with a bold title + description, hover-highlights. -->
    <Style x:Key="Tile" TargetType="Button">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Margin" Value="0,0,12,10"/>
      <Setter Property="Width" Value="224"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Primary command tile: Mock 2's .tile.go is the DARK BRAND tile, not orange - orange is
         reserved for the single primary BUTTON (Connect / Add folder). 180aa matches the mock. -->
    <Style x:Key="PrimaryTile" TargetType="Button">
      <Setter Property="Padding" Value="16,13"/>
      <Setter Property="Margin" Value="0,0,12,10"/>
      <Setter Property="Width" Value="248"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="#0F1115" CornerRadius="8" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#1C2027"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TileTitle" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="#344054"/>
    </Style>
    <Style x:Key="TileTitlePrimary" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style x:Key="TileDesc" TargetType="TextBlock">
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Foreground" Value="#667085"/>
      <Setter Property="Margin" Value="0,4,0,0"/>
    </Style>
    <Style x:Key="TileDescPrimary" TargetType="TextBlock">
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Foreground" Value="#9BA1AA"/>
      <Setter Property="Margin" Value="0,4,0,0"/>
    </Style>
    <!-- Expander: OWN the chevron rather than inherit it. The stock WPF toggle draws the theme's
         circle-arrow, and it reads INVERTED (it pointed the wrong way both expanded and collapsed).
         The direction cannot be nudged with a property, so the glyph is ours: ChevronDown when
         collapsed (click to open), ChevronUp when expanded (click to close). Segoe MDL2 Assets ships
         with Windows 10/11, which is the only place this app runs. Applies to both Expanders (the
         detailed log and the readiness checks) so they cannot disagree. DECISIONS 077. -->
    <Style TargetType="Expander">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Expander">
            <DockPanel LastChildFill="True">
              <ToggleButton DockPanel.Dock="Top" Focusable="False" Cursor="Hand" Background="Transparent"
                            IsChecked="{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="Transparent" Padding="2,3">
                      <StackPanel Orientation="Horizontal">
                        <TextBlock x:Name="gl" Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" FontSize="11"
                                   VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#475467"/>
                        <ContentPresenter VerticalAlignment="Center"/>
                      </StackPanel>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsChecked" Value="True">
                        <Setter TargetName="gl" Property="Text" Value="&#xE70E;"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
                <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/>
              </ToggleButton>
              <ContentPresenter x:Name="body" Visibility="Collapsed"/>
            </DockPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsExpanded" Value="True">
                <Setter TargetName="body" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SectionHead" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="#344054"/>
      <Setter Property="Margin" Value="0,4,0,8"/>
    </Style>
    <!-- Card: white rounded panel with a crisp border, for grouped content. Deliberately NO
         DropShadowEffect (matches the GroupBox card style ~230 lines up): WPF renders the
         CHILDREN through the effect, which can soften text (DECISIONS 180ay Finding 2). -->
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="16"/>
    </Style>
    <!-- Inputs: consistent border, padding, and an accent focus ring. Property-only styles
         (no ControlTemplate) so the multi-line log text host is never disturbed. -->
    <Style TargetType="TextBox">
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Padding" Value="7,5"/>
      <Setter Property="MinHeight" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Style.Triggers>
        <Trigger Property="IsKeyboardFocused" Value="True"><Setter Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="Padding" Value="7,4"/>
      <Setter Property="MinHeight" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Margin" Value="0,0,18,0"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#F4F6FA"/>
      <Setter Property="Foreground" Value="#475467"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
    </Style>
  </Window.Resources>
  <DockPanel LastChildFill="True">

    <!-- Menu bar -->
    <!-- App bar (180aa, Mock 2's .appbar): ONE dark strip holding the menus, the job chip and the
         connection state + version on the right. Previously the chip/connection/version sat in the
         light toolbar below, where the centred version overlay COLLIDED with 'Not connected' the
         moment the Files toolbar filled the row (Dave's 2.0.26 screenshot). In a docked right-hand
         cluster nothing can overlap. -->
    <Border DockPanel.Dock="Top" Background="#0F1115">
      <DockPanel LastChildFill="False" Margin="10,0,14,0">
    <Menu Background="Transparent" Padding="0,4" VerticalAlignment="Center">
      <MenuItem Header="_Job" Style="{StaticResource TopMenuItem}">
        <MenuItem x:Name="MnuJobNew" Header="New..."/>
        <MenuItem x:Name="MnuJobOpen" Header="Open..."/>
        <MenuItem x:Name="MnuJobRecent" Header="Open recent"/>
        <Separator/>
        <MenuItem x:Name="MnuJobSave" Header="Save"/>
        <MenuItem x:Name="MnuJobSaveAs" Header="Save As..."/>
        <MenuItem x:Name="MnuJobRename" Header="Rename..."/>
        <Separator/>
        <MenuItem x:Name="MnuJobOpenFolder" Header="Open job folder"/>
        <MenuItem x:Name="MnuJobExport" Header="Export job..."/>
        <MenuItem x:Name="MnuJobImport" Header="Import job..."/>
        <MenuItem x:Name="MnuJobClose" Header="Close"/>
        <MenuItem x:Name="MnuJobDelete" Header="Delete job..."/>
        <Separator/>
        <MenuItem x:Name="MnuJobSwitch" Header="Switch transfer type..."/>
        <Separator/>
        <MenuItem x:Name="MnuJobExit" Header="Exit"/>
      </MenuItem>
      <!-- "Reset tuning to defaults" used to be a fourth item here. It is now a button inside
           Performance and tuning, where the values it resets are actually visible. As a menu
           item it wrote to config.json the instant you confirmed, with nothing on screen to
           show what changed; inside the dialog it fills the boxes and you still have to press
           Save, so Cancel undoes it. See DECISIONS 058. -->
      <MenuItem Header="_Settings" Style="{StaticResource TopMenuItem}">
        <MenuItem x:Name="MnuSettingsChecklist" Header="Setup checklist..."/>
        <MenuItem x:Name="MnuSettingsApi" Header="API settings..."/>
        <MenuItem x:Name="MnuSettingsWizard" Header="Microsoft 365 setup wizard..."/>
        <MenuItem x:Name="MnuSettingsEmail" Header="Email alerts..."/>
        <MenuItem x:Name="MnuSettingsTuning" Header="Performance and tuning..."/>
        <Separator/>
        <MenuItem x:Name="MnuSettingsDecommission" Header="Remove set-up (decommission)..."/>
      </MenuItem>
      <MenuItem Header="_Help" Style="{StaticResource TopMenuItem}">
        <MenuItem x:Name="MnuHelpHowto" Header="How to use"/>
        <MenuItem x:Name="MnuHelpCheck" Header="Check my setup"/>
        <MenuItem x:Name="MnuHelpUpdate" Header="Check for updates..."/>
        <Separator/>
        <MenuItem x:Name="MnuHelpSupport" Header="Email support (with details)"/>
        <MenuItem x:Name="MnuHelpLicence" Header="Licence"/>
        <MenuItem x:Name="MnuHelpLicInstall" Header="Install licence file..."/>
        <Separator/>
        <MenuItem x:Name="MnuHelpAbout" Header="About"/>
        <!-- Header is set from $script:AppVersion at startup. Do NOT hard-code a number here:
             it was "Version 1.0" in the markup AND in a variable, so a bump would have moved one
             and left the menu lying. DECISIONS 061. -->
        <MenuItem x:Name="MnuHelpVersion" Header="Version" IsEnabled="False"/>
      </MenuItem>
    </Menu>
        <!-- Job chip, two states (180z/180aa): a job OPEN shows the mock's dark-on-dark pill
             ("Job  <name>", #1C2027 with a #2A2F38 hairline); NO job shows plain grey text with
             no pill at all. Set-JobChip owns the switch. -->
        <Border x:Name="JobChip" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="99" Padding="12,4" VerticalAlignment="Center" Margin="14,5,0,5">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="LblJobPrefix" Text="Job" Foreground="#8B919A" FontSize="12" VerticalAlignment="Center" Margin="0,0,7,0" Visibility="Collapsed"/>
            <TextBlock x:Name="LblJob" Text="No job open. Use the Job menu to create or open one." Foreground="#8B919A" FontWeight="SemiBold" FontSize="12.5" VerticalAlignment="Center" MaxWidth="420" TextTrimming="CharacterEllipsis"/>
          </StackPanel>
        </Border>
        <!-- Right cluster: connection dot + text, then the version. Docked right, so it can never
             collide with whatever the left side holds. -->
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse x:Name="ConnDot" Width="8" Height="8" Fill="#98A2B3" Margin="0,1,7,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="LblConn" Text="Not connected" Foreground="#98A2B3" FontSize="12" VerticalAlignment="Center"/>
          <TextBlock x:Name="LblVersionTop" Text="" Foreground="#5A616C" FontSize="12" Margin="16,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- The live status now lives in a prominent card above the log (main area, row 2),
         not in a thin bottom strip. -->

    <!-- Main area -->
    <Grid Margin="14,8,14,12">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Toolbar (Mock 2's .toolrow): buttons only - the chip, connection state and version
           live in the app bar above (180aa). -->
      <DockPanel Grid.Row="0" Margin="0,2,0,8" LastChildFill="False">
        <Button x:Name="BtnConnect" Style="{StaticResource Primary}" Content="Connect and list projects" ToolTip="Signs in to Datto and Microsoft 365, then lists the Datto projects you can migrate."/>
        <Button x:Name="BtnAddFolder" Style="{StaticResource Primary}" Content="Add folder..." Visibility="Collapsed" ToolTip="Add a folder to copy. Local (D:\Shared\Finance) or a network share (\\server\share\Finance). Each added folder is copied as its own source with its own destination."/>
        <Button x:Name="BtnRemoveFolder" Content="Remove folder" Margin="8,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Remove the selected folder(s) from this job. Nothing on disk or in Microsoft 365 is touched; the folder just stops being part of this job."/>
        <Button x:Name="BtnShareCreds" Content="Credentials..." Margin="8,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="Store the account used to reach a network share or NAS, when the app runs as a user who does not have access. Windows keeps the sign-in securely and presents it automatically, including on scheduled runs."/>
        <CheckBox x:Name="ChkLinuxSrc" Content="Linux / Mac / NAS source" Margin="12,0,0,0" VerticalAlignment="Center" FontSize="12" Visibility="Collapsed"
                  ToolTip="Tick when these folders come from a Linux server, NAS or Mac share. The run then auto-corrects names for SharePoint (illegal characters are tidied and logged), normalises Mac-style accented file names so syncs match properly, and Check readiness flags case-only duplicates (Report.txt vs report.txt) that would overwrite each other at the destination."/>
        <!-- (i) explaining what the tick enables (Dave, 24 July). MDL2 Info glyph, opens an
             in-app explanation. Visibility rides with the checkbox in Set-FolderModeUI. -->
        <Button x:Name="BtnLinuxInfo" Content="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="14" Width="30" Padding="0,4" Margin="4,0,0,0" VerticalAlignment="Center" FocusVisualStyle="{x:Null}" Visibility="Collapsed"
                ToolTip="What 'Linux / Mac / NAS source' does"/>
      </DockPanel>
      <!-- LblConn and LblVersionTop moved to the app bar's right cluster (180aa): the centred
           version overlay collided with 'Not connected' when the Files toolbar filled the row. -->
      <!-- The Liscaragh Migrate PRODUCT logo, large and top-right (Dave, 21 July: make it 4-6x bigger,
           but do NOT grow the toolbar - overlap the corner instead of sitting in the flow). It is a
           FLOATING OVERLAY: Grid.RowSpan across the toolbar row and the star content row, so its
           height is absorbed by the star row and the Auto toolbar row keeps its natural (short)
           height. Panel.ZIndex puts it on top. It hugs the top-right corner and only dips a little
           below the toolbar, over the mapping panel's empty top-right border. Black chip = the logo
           art's own background. Source (the product mark) set at startup via Set-BrandLogo. The chip
           is now HIT-TESTABLE and clickable: it opens the Liscaragh Migrate product page (DECISIONS
           160b, 180n). -->
      <Border Grid.Row="0" Grid.RowSpan="2" Panel.ZIndex="100" HorizontalAlignment="Right" VerticalAlignment="Top"
              Background="#000000" CornerRadius="6" Padding="11,8" Margin="0,0,2,0">
        <Image x:Name="ImgLogoTop" Height="75" Stretch="Uniform" Cursor="Hand" RenderOptions.BitmapScalingMode="HighQuality" ToolTip="Open the Liscaragh Migrate page (liscaragh.com/migrate)"/>
      </Border>

      <!-- Middle: projects + destination detail -->
      <!-- The project list was a fixed 360px, which left Project and Destination sharing about
           260px after the 96px Status column, so a real destination truncated to
           "OneDrive: a.person(" and the list could not be read at a glance.
           Widened to 460, and made draggable, because a fixed number cannot be right for
           everyone: the action tiles are a fixed 224px in a WrapPanel, so every pixel given
           to this column makes them wrap sooner. That is a genuine trade with no correct
           answer, so the splitter hands it to the operator instead of guessing. MinWidth on
           both sides stops either being dragged into uselessness. See DECISIONS 054. -->
      <Grid Grid.Row="1">
        <!-- 180bo: outer grid's ColumnDefinitions now live HERE, shared by BOTH content rows,
             instead of each row owning its own separate column set (180bn). This is what lets
             "Before you copy" (row 1, column 0) always be EXACTLY the same width as Sources
             (row 0, column 0) - same column, not a coincidentally-equal proportional share of a
             separate grid - including live while the GridSplitter is dragged, since the splitter
             now spans both rows (Grid.RowSpan="2") and resizes column 0 for both at once.
             Dave, 26 July: "ensure the width of that first box matches the width of the box
             above it". ROW 0 = Sources | mapping (unchanged). ROW 1 = Before you copy (three
             checks, exploded out of the category tile per Dave: "break them out of the
             category") | Run the migration | Check and review (Verify the copy stays one
             category tile; Reports and proof exploded into its four buttons, per Dave:
             "uncategorise reports and proof and get the 5 into the right hand side" - one
             Verify tile + four report buttons = five things). No ScrollViewer on any of the
             three ROW 1 zones any more (Dave: "No Scrolling") - each sits in the Auto row, which
             sizes to its content, so there is nothing to scroll by construction. See DECISIONS
             180bo. -->
        <Grid.RowDefinitions>
          <!-- Dave, 26 July: "the projects and source/destination need to be deeper so there is
               no scroll there". 220 was tight enough on a real 1710x936 display (S12 testing)
               that Sources and the destination detail panel scrolled internally most of the
               time. Raised to 300 - a real floor increase, not just cosmetic - verified by
               launching and screenshotting the live app (below) to confirm the Auto zone under
               it (Before you copy / Run the migration / Check and review, DECISIONS 180bo's "no
               scrolling by construction" zones) still fits without clipping at this window's
               maximized size. -->
          <RowDefinition Height="*" MinHeight="460"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="540" MinWidth="300"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*" MinWidth="420"/>
        </Grid.ColumnDefinitions>

        <GridSplitter Grid.Column="1" Grid.RowSpan="2" Width="5" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                      Background="Transparent" ShowsPreview="True" ResizeBehavior="PreviousAndNext"
                      ToolTip="Drag to make the list wider or narrower."/>

        <!-- Card the projects panel (180u). 180bn/180bo: fills the whole top-left cell directly
             (Run the migration moved out to ROW 1 long ago; the old RowProjects/RowRun split is
             retired). -->
        <Border Grid.Row="0" Grid.Column="0" Margin="0,0,8,0" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="12" Padding="12,10,12,12" SnapsToDevicePixels="True">
          <DockPanel>
            <DockPanel DockPanel.Dock="Top" Margin="0,0,0,4" LastChildFill="True">
              <Button x:Name="BtnFilters" DockPanel.Dock="Right" Content="Filters..." Padding="10,3" VerticalAlignment="Top"
                      ToolTip="Choose which files this job migrates: by size, by file type (skip certain types, or copy ONLY certain types), and by modified date. These filters apply to EVERY project in this job, not just the selected one. They were previously under Settings, Performance and tuning."/>
              <TextBlock x:Name="LblProjectsHead" Text="Projects (select one or more)" FontWeight="SemiBold" FontSize="12.5" Foreground="#667085" VerticalAlignment="Center"
                         ToolTip="Select one project, or several with Ctrl or Shift, then set the destination on the right."/>
            </DockPanel>
            <Grid DockPanel.Dock="Top" Margin="0,0,0,4">
              <TextBox x:Name="TxtFilter" Padding="4,3" ToolTip="Type to filter the project list by project name or destination."/>
              <TextBlock x:Name="TxtFilterHint" Text="Search projects by name or destination..." Foreground="#98A2B3" Margin="7,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
            </Grid>
            <Border x:Name="GettingStarted" DockPanel.Dock="Top" Background="#F8FAFF" BorderBrush="#C7D7E8" BorderThickness="1" CornerRadius="8" Padding="18,16" Margin="0,2,0,6" Visibility="Collapsed">
              <StackPanel>
                <Border Height="3" Width="46" HorizontalAlignment="Left" Background="#1C6091" CornerRadius="2" Margin="0,0,0,10"/>
                <TextBlock Text="Getting started" FontWeight="Bold" FontSize="16.5" Foreground="#101828" Margin="0,0,0,10"/>
                <TextBlock x:Name="LblQuickStart" TextWrapping="Wrap" FontSize="13" Foreground="#475467" Text=""/>
              </StackPanel>
            </Border>
            <DataGrid x:Name="LstProjects" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Extended" HeadersVisibility="Column" GridLinesVisibility="None" AlternationCount="2" RowHeight="34" CanUserAddRows="False" CanUserReorderColumns="False" RowHeaderWidth="0" BorderBrush="#E4E7EC" BorderThickness="0" Background="White">
              <DataGrid.Resources>
                <Style TargetType="DataGridCell">
                  <Setter Property="VerticalContentAlignment" Value="Center"/>
                  <Setter Property="BorderThickness" Value="0"/>
                  <Style.Triggers>
                    <Trigger Property="IsSelected" Value="True">
                      <Setter Property="Background" Value="#FFF7F2"/>
                      <Setter Property="Foreground" Value="#111827"/>
                      <Setter Property="BorderBrush" Value="#FFF7F2"/>
                    </Trigger>
                  </Style.Triggers>
                </Style>
                <Style TargetType="DataGridColumnHeader">
                  <Setter Property="Background" Value="White"/>
                  <Setter Property="Foreground" Value="#98A2B3"/>
                  <Setter Property="FontSize" Value="11"/>
                  <Setter Property="FontWeight" Value="SemiBold"/>
                  <Setter Property="BorderBrush" Value="#E4E7EC"/>
                  <Setter Property="BorderThickness" Value="0,0,0,1"/>
                  <Setter Property="Padding" Value="8,7"/>
                </Style>
                <Style TargetType="DataGridRow">
                  <Setter Property="BorderBrush" Value="Transparent"/>
                  <Setter Property="BorderThickness" Value="3,0,0,0"/>
                  <Style.Triggers>
                    <Trigger Property="IsSelected" Value="True">
                      <Setter Property="BorderBrush" Value="#E2500F"/>
                    </Trigger>
                  </Style.Triggers>
                </Style>
              </DataGrid.Resources>
              <DataGrid.Columns>
                <DataGridTextColumn Header="Project" Binding="{Binding Name}" Width="*">
                  <DataGridTextColumn.ElementStyle>
                    <Style TargetType="TextBlock"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="TextTrimming" Value="CharacterEllipsis"/><Setter Property="Margin" Value="8,0"/></Style>
                  </DataGridTextColumn.ElementStyle>
                </DataGridTextColumn>
                <DataGridTextColumn Header="Destination" Binding="{Binding Destination}" Width="*">
                  <DataGridTextColumn.ElementStyle>
                    <Style TargetType="TextBlock"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="TextTrimming" Value="CharacterEllipsis"/><Setter Property="Foreground" Value="#667085"/><Setter Property="Margin" Value="8,0"/></Style>
                  </DataGridTextColumn.ElementStyle>
                </DataGridTextColumn>
                <DataGridTemplateColumn Header="Status" Width="132">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <Border x:Name="pill" Background="#F2F4F7" CornerRadius="99" Padding="9,2,10,3" Margin="8,0,0,0" HorizontalAlignment="Left" VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                          <Ellipse x:Name="dot" Width="8" Height="8" Margin="0,1,6,0" VerticalAlignment="Center" Fill="#98A2B3"/>
                          <TextBlock x:Name="txt" Text="{Binding Status}" FontWeight="SemiBold" FontSize="12" Foreground="#98A2B3" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                      </Border>
                      <DataTemplate.Triggers>
                        <DataTrigger Binding="{Binding Status}" Value="Ready"><Setter TargetName="dot" Property="Fill" Value="#066A4B"/><Setter TargetName="txt" Property="Foreground" Value="#066A4B"/><Setter TargetName="pill" Property="Background" Value="#EFFAF4"/></DataTrigger>
                        <DataTrigger Binding="{Binding Status}" Value="Migrated"><Setter TargetName="dot" Property="Fill" Value="#066A4B"/><Setter TargetName="txt" Property="Foreground" Value="#066A4B"/><Setter TargetName="pill" Property="Background" Value="#EFFAF4"/></DataTrigger>
                        <DataTrigger Binding="{Binding Status}" Value="Completed"><Setter TargetName="dot" Property="Fill" Value="#066A4B"/><Setter TargetName="txt" Property="Foreground" Value="#066A4B"/><Setter TargetName="pill" Property="Background" Value="#EFFAF4"/></DataTrigger>
                        <DataTrigger Binding="{Binding Status}" Value="In progress"><Setter TargetName="dot" Property="Fill" Value="#1C6091"/><Setter TargetName="txt" Property="Foreground" Value="#1C6091"/><Setter TargetName="pill" Property="Background" Value="#EFF4F9"/></DataTrigger>
                        <DataTrigger Binding="{Binding Status}" Value="Queued"><Setter TargetName="dot" Property="Fill" Value="#B5460F"/><Setter TargetName="txt" Property="Foreground" Value="#B5460F"/><Setter TargetName="pill" Property="Background" Value="#FFFAEB"/></DataTrigger>
                        <DataTrigger Binding="{Binding Status}" Value="Errors"><Setter TargetName="dot" Property="Fill" Value="#B42318"/><Setter TargetName="txt" Property="Foreground" Value="#B42318"/><Setter TargetName="pill" Property="Background" Value="#FEF3F2"/></DataTrigger>
                      </DataTemplate.Triggers>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
              </DataGrid.Columns>
            </DataGrid>
          </DockPanel>
        </Border>

        <!-- Source and Destination mapping. 180bn/180bo: fills the whole top-right cell directly
             (Check and review moved out to ROW 1 long ago; the old two-row/MinHeight-floor split
             is retired). -->
        <GroupBox Grid.Row="0" Grid.Column="2">
          <GroupBox.Header><TextBlock x:Name="LblMapHeader" Text="Source and Destination mapping for the selected project" Foreground="#101828" FontWeight="SemiBold"/></GroupBox.Header>
          <!-- Dave, 27 July: with a real job open (several sources, Files mode) this panel's own
               content out-grew the space MinHeight=300 (above) bought it, so the Apply/Check
               destination row itself scrolled out of view below the fold - discovered live: clicks
               on "Apply to this source" landed on nothing because the button was not actually where
               the UI-tree geometry (measured pre-clip) said it was. Same fix shape as the Settings
               dialog (F25, DECISIONS 180bp): the PRIMARY ACTIONS live in a fixed footer that is
               never scrolled away, and everything else - source folders, destination fields, the
               live preview box - scrolls in the space above it. Verified live: the button row is
               reachable and clickable regardless of how tall the rest of the form gets. -->
          <DockPanel>
          <StackPanel DockPanel.Dock="Bottom" Margin="8,6,8,6">
            <StackPanel Orientation="Horizontal">
              <Button x:Name="BtnApply" Content="Apply to this project" ToolTip="Set this destination for the selected project. It saves straight away."/>
              <Button x:Name="BtnApplySel" Content="Apply to selected sources" Margin="8,0,0,0" ToolTip="Set this destination for every project you have highlighted in the list. Each still goes into its own folder."/>
              <Button x:Name="BtnApplyAll" Content="Apply to ALL projects" Margin="8,0,0,0" ToolTip="Set this destination for every project in the list, highlighted or not. Each still goes into its own folder."/>
              <Button x:Name="BtnCheck" Content="Verify destination" Margin="16,0,0,0" Padding="10,4" ToolTip="Confirm the destination exists (site + library, or the user's OneDrive). Changes nothing."/>
            </StackPanel>
            <TextBlock x:Name="LblCheck" Margin="0,6,0,0" Foreground="Gray" TextWrapping="Wrap"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="8,5,8,0">
            <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
              <TextBlock Text="SOURCE" FontWeight="SemiBold" FontSize="11" Foreground="#98A2B3" Margin="0,0,10,1" VerticalAlignment="Center"/>
              <TextBlock x:Name="LblProject" Text="(no project selected)" FontWeight="Bold" Foreground="#101828" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="LblSrcIntro" Text="Which folders of the Datto project to copy?  Leave the list empty to copy the entire project." Foreground="#475467" FontSize="12.5" Margin="0,0,0,4"/>
            <Grid x:Name="PnlSrcFolders" Margin="0,0,0,6">
              <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock Grid.Column="0" Text="Source folders:" VerticalAlignment="Top" Margin="0,4,0,0"/>
              <ListBox x:Name="LstSource" Grid.Column="1" Height="66" SelectionMode="Extended"
                       ToolTip="The folders inside this Datto project to copy. Leave the list empty to copy the whole project. Use 'Add folders...' to pick one or more (Ctrl-click to select several at once). When more than one folder is chosen, each keeps its own folder name at the destination. The destination paths stay the same as a full run, so a later full sync still matches."/>
              <StackPanel Grid.Column="2" VerticalAlignment="Top">
                <Button x:Name="BtnAddSource" Content="Add folders..." Margin="6,0,0,0" Padding="10,3" MinWidth="106" ToolTip="Browse this Datto project and add one or more folders to copy. Ctrl-click in the browser to select several at once; double-click a folder to open it. Lists straight from Datto with the exact spelling and case."/>
                <Button x:Name="BtnRemoveSource" Content="Remove" Margin="6,4,0,0" Padding="10,3" MinWidth="106" ToolTip="Remove the highlighted folder(s) from the list."/>
                <Button x:Name="BtnTestSource" Content="Test" Margin="6,4,0,0" Padding="10,3" MinWidth="106" ToolTip="Check that each folder in the list still exists in this Datto project. Case-sensitive; names any that do not match."/>
              </StackPanel>
            </Grid>
            <CheckBox x:Name="ChkSrcContents" Margin="130,0,0,4"
              Content="Copy only this folder's contents (don't create the folder itself)"
              ToolTip="Off (the safe default) = the subfolder is part of the path at the destination, so a later sync or verify of the whole project still finds every file. On = the files inside the subfolder go straight into the destination folder. Only runs of THIS mapping with this box ticked understand that layout: a run without it would not find the files and would copy them again. If the destination folder already holds files with the same names, they will be overwritten."/>
            <Border x:Name="SourcePathBox" Background="#E7F7EF" BorderBrush="#A6E9C5" BorderThickness="1" CornerRadius="3" Padding="8,4" Margin="0,2,0,4">
              <TextBlock x:Name="LblSourcePath" TextWrapping="Wrap" Foreground="#066A4B" FontSize="12"/>
            </Border>
            <TextBlock x:Name="LblSourceCheck" Margin="0,0,0,4" Foreground="Gray" TextWrapping="Wrap"/>
            <TextBlock Text="DESTINATION" FontWeight="SemiBold" FontSize="11" Foreground="#98A2B3" Margin="0,10,0,5"/>
            <TextBlock x:Name="LblDestQ" Text="Where should this project's files go?" Foreground="#475467" FontSize="12.5" Margin="0,0,0,4"/>
            <Border Background="#F2F4F7" CornerRadius="9" Padding="3" HorizontalAlignment="Left" Margin="0,0,0,6">
              <StackPanel Orientation="Horizontal">
                <RadioButton x:Name="RbOneDrive" Style="{StaticResource Segment}" Content="User's OneDrive" GroupName="dest" IsChecked="True" ToolTip="Send this project into one person's OneDrive (for their personal content). The common choice."/>
                <RadioButton x:Name="RbSite" Style="{StaticResource Segment}" Content="A SharePoint site" GroupName="dest" ToolTip="Send this project into a SharePoint site's document library (for shared or team content)."/>
                <RadioButton x:Name="RbSkip" Style="{StaticResource Segment}" Content="Skip this project" GroupName="dest" ToolTip="Do not migrate this project."/>
              </StackPanel>
            </Border>

            <Grid Margin="0,0,0,6">
              <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <Button x:Name="BtnFindSite" Grid.Column="2" Content="Find site..." Margin="6,0,0,0" Padding="10,3" Visibility="Collapsed"
                      ToolTip="Search the SharePoint sites in your tenant and pick one, rather than typing the address."/>
              <TextBlock x:Name="LblLoc" Grid.Column="0" Text="Microsoft 365 user:" VerticalAlignment="Center"/>
              <TextBox x:Name="TxtLoc" Grid.Column="1" ToolTip="For OneDrive, enter the user's email / sign-in address. For SharePoint, paste the site address from your browser."/>
              <TextBlock x:Name="TxtLocHint" Grid.Column="1" Text="" Foreground="#98A2B3" Margin="7,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
            </Grid>
            <Grid x:Name="RowLib" Margin="0,0,0,6" Visibility="Collapsed">
              <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock Grid.Column="0" Text="Library:" VerticalAlignment="Center"/>
              <TextBox x:Name="TxtLib" Grid.Column="1" ToolTip="The SharePoint document library to upload into (usually 'Documents'). Click Browse to pick from the site's libraries with the exact spelling."/>
              <Button x:Name="BtnPickLib" Grid.Column="2" Content="Browse..." Margin="6,0,0,0" Padding="10,3" ToolTip="List the document libraries on that SharePoint site and pick one, instead of typing."/>
            </Grid>
            <Grid Margin="0,0,0,6">
              <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock Grid.Column="0" Text="Folder (optional):" VerticalAlignment="Center"/>
              <TextBox x:Name="TxtFolder" Grid.Column="1" VerticalAlignment="Center" ToolTip="A subfolder at the destination to place this project in. Leave blank to put it at the top level."/>
              <StackPanel Grid.Column="2" Orientation="Vertical">
                <Button x:Name="BtnBrowseFolder" Content="Browse..." Margin="6,0,0,0" Padding="10,3" ToolTip="List the folders that already exist at this destination, pick one to drill into, or create a new folder."/>
                <Button x:Name="BtnTestDest" Content="Test" Margin="6,4,0,0" Padding="10,3" ToolTip="Check this destination is reachable right now (the user's OneDrive exists, or the SharePoint site and library exist). Changes nothing."/>
              </StackPanel>
            </Grid>

            <CheckBox x:Name="ChkNest" Margin="0,2,0,4" IsChecked="False" Visibility="Collapsed"
                      Content="Also wrap each project in a folder named after the project"/>

            <Border x:Name="DestPathBox" Background="#E7F7EF" BorderBrush="#A6E9C5" BorderThickness="1" CornerRadius="3" Padding="8,4" Margin="0,2,0,6">
              <StackPanel>
                <TextBlock x:Name="LblDestPath" TextWrapping="Wrap" Foreground="#066A4B" FontSize="12"/>
                <TextBlock x:Name="LblDestWarn" TextWrapping="Wrap" Foreground="#B5460F" FontSize="12" FontWeight="SemiBold" Margin="0,3,0,0" Visibility="Collapsed"/>
              </StackPanel>
            </Border>
          </StackPanel>
          </ScrollViewer>
          </DockPanel>
        </GroupBox>

        <!-- LEFT, ROW 1: Before you copy. 180bo: exploded out of the BtnCatBefore category tile
             into its three real buttons directly (Dave: "break them out of the category and
             have the 3 there"). Same x:Name, same handlers, same tooltips as when they lived in
             the hidden panel behind the popup - only now visible directly, title-only (no
             description line, Dave: "Less text"), and no popup/BtnCatBefore in between. Same
             column as Sources above (Grid.Column="0" of the shared outer grid), so the width
             always matches it exactly. No ScrollViewer: the row is Auto-height, so there is
             nothing to scroll. -->
        <GroupBox Grid.Row="1" Grid.Column="0" Margin="0,8,8,0">
          <GroupBox.Header><TextBlock Text="Before you copy" Foreground="#101828" FontWeight="SemiBold"/></GroupBox.Header>
          <UniformGrid x:Name="GridBeforeCopy" Columns="1" Margin="6,4">
            <Button x:Name="BtnPreflight" Style="{StaticResource Tile}" Width="Auto" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,0,5" ToolTipService.ShowOnDisabled="True" ToolTip="Checks for problems (destination quota, over-long names) before anything is uploaded. Walks the whole project first, so it is slower on large projects. Greyed out while a run is in progress, and until you have connected and selected a project with a destination set; it becomes available once the run ends.">
              <StackPanel Orientation="Horizontal">
                <Border Width="26" Height="26" CornerRadius="7" Background="#E8F1FC" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE8FB;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#1C6091" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                <TextBlock Style="{StaticResource TileTitle}" Text="Check readiness" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnDryRun" Style="{StaticResource Tile}" Width="Auto" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,0,5" ToolTipService.ShowOnDisabled="True" ToolTip="A safe rehearsal: lists exactly what would be uploaded, without changing anything. Walks the whole project first, so it is slower on large projects. Greyed out while a run is in progress, and until you have connected and selected a project with a destination set; it becomes available once the run ends.">
              <StackPanel Orientation="Horizontal">
                <Border Width="26" Height="26" CornerRadius="7" Background="#F4EBFF" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE890;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#6941C6" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                <TextBlock Style="{StaticResource TileTitle}" Text="Preview migration" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnSourceReview" Style="{StaticResource Tile}" Width="Auto" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,0,0" ToolTip="Read-only review of the folders in THIS job at the Datto source: items shared by PUBLIC link (anyone with the link, no sign-in), files currently LOCKED (someone is editing), and files not yet fully in the cloud (which can fail to download at migration). Nothing at the source is changed. Produces a detailed report and a findings CSV.">
              <StackPanel Orientation="Horizontal">
                <Border Width="26" Height="26" CornerRadius="7" Background="#FDF2FA" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#C11574" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                <TextBlock Style="{StaticResource TileTitle}" Text="Datto source review" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
          </UniformGrid>
        </GroupBox>

        <!-- RIGHT, ROW 1: Run the migration | Check and review, side by side in the remaining
             width (the same star column mapping uses above). Nested here because that column
             now needs to hold two zones, not one. -->
        <Grid Grid.Row="1" Grid.Column="2" Margin="0,8,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <!-- MIDDLE: Copy to Microsoft 365 (Run the migration). Content unchanged; no more
             ScrollViewer (Dave: "No Scrolling" - the row is Auto-height, nothing to scroll). -->
          <GroupBox Grid.Column="0" Margin="0,0,8,0">
            <GroupBox.Header><TextBlock Text="Copy to Microsoft 365" Foreground="#101828" FontWeight="SemiBold"/></GroupBox.Header>
            <StackPanel Margin="6,3">
              <UniformGrid Columns="2">
                <Button x:Name="BtnTransfer" Style="{StaticResource PrimaryTile}" Width="Auto" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,5" Padding="16,8" ToolTip="Copies every file and overwrites the destination with the Datto version. For the first migration. You will be asked to confirm.">
                  <StackPanel><TextBlock Style="{StaticResource TileTitlePrimary}" Text="Full migration"/><TextBlock Style="{StaticResource TileDescPrimary}" Text="Use this for the first migration. Copies everything from the source. Existing files in the destination are overwritten."/></StackPanel>
                </Button>
                <Button x:Name="BtnDelta" Style="{StaticResource Tile}" Width="Auto" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,5" Padding="10,4" ToolTip="Merges Datto into the Microsoft 365 copy, comparing file by file. Use this to top up after an upload, or to fold a Datto folder into a destination folder that already holds content. You choose add-new-only or update-where-Datto-is-newer. It never deletes anything.">
                  <StackPanel><TextBlock Style="{StaticResource TileTitle}" Text="Sync new and changed"/><TextBlock x:Name="TxtDeltaDesc" Style="{StaticResource TileDesc}" Text="Adds new files and updates changed files. Files removed from Datto are not deleted from Microsoft 365."/></StackPanel>
                </Button>
                <Button x:Name="BtnStop" Style="{StaticResource Tile}" Width="Auto" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,5" Padding="10,4" Background="#FEE4E2" IsEnabled="False" Visibility="Collapsed" ToolTip="Stop the copy that is running. Files already uploaded are kept; carry on later with 'Sync new and changed'.">
                  <StackPanel><TextBlock Style="{StaticResource TileTitle}" Text="Stop" Foreground="#B42318"/><TextBlock Style="{StaticResource TileDesc}" Text="Halt a running copy. What is done is kept."/></StackPanel>
                </Button>
                <Button x:Name="BtnPause" Style="{StaticResource Tile}" Width="Auto" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,5" Padding="10,4" IsEnabled="False" Visibility="Collapsed" ToolTipService.ShowOnDisabled="True" ToolTip="Available once files are actually moving, not while the file list is being read. Pausing during the listing would throw the listing away and read it again, so there would be nothing to carry on from: use Stop for that. Once it is on, Pause keeps everything already uploaded and the tile becomes Resume.">
                  <StackPanel><TextBlock x:Name="BtnPauseTitle" Style="{StaticResource TileTitle}" Text="Pause"/><TextBlock x:Name="BtnPauseDesc" Style="{StaticResource TileDesc}" Text="Available once files start moving."/></StackPanel>
                </Button>
              </UniformGrid>
              <UniformGrid Columns="2" Margin="0,0,0,0">
                <Button x:Name="BtnSchedule" Style="{StaticResource Secondary}" HorizontalAlignment="Stretch" Margin="0,0,8,0" Padding="14,4" Content="Schedule / Night Runs"
                        ToolTip="Start the migration at a time you choose (for example tonight), and optionally only run during a nightly window so it does not compete with the office internet during the day. The app must stay open for the schedule to run."/>
                <Button x:Name="BtnRerunFailed" Style="{StaticResource Attention}" HorizontalAlignment="Stretch" Margin="0,0,8,0" Padding="14,4" IsEnabled="False" ToolTipService.ShowOnDisabled="True" Content="Rerun failed files only"
                        ToolTip="Re-copy only the files that failed in the last run (taken from its record), leaving everything that already succeeded exactly as it is. Becomes available after a run that reported problems."/>
              </UniformGrid>
            </StackPanel>
          </GroupBox>

          <!-- RIGHT: Check and review. 180bo: Verify the copy stays ONE category tile (popup
             unchanged); Reports and proof is exploded into its four real buttons directly
             (Dave: "uncategorise reports and proof and get the 5 into the right hand side" -
             one tile + four buttons = five things), title-only, no ScrollViewer. -->
          <GroupBox Grid.Column="1">
            <GroupBox.Header><TextBlock Text="Check and review" Foreground="#101828" FontWeight="SemiBold"/></GroupBox.Header>
            <StackPanel Margin="6,4">
              <UniformGrid Columns="3">
                <Button x:Name="BtnCatVerify" Style="{StaticResource Tile}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,5" ToolTip="Confirm the copy: verify every file arrived and compare totals, source vs destination.">
                  <StackPanel Orientation="Horizontal">
                    <Border Width="28" Height="28" CornerRadius="8" Background="#E7F7EF" Margin="0,0,11,0" VerticalAlignment="Center"><TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="#0E9F6E" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <StackPanel VerticalAlignment="Center"><TextBlock Style="{StaticResource TileTitle}" Text="Verify the copy"/></StackPanel>
                  </StackPanel>
                </Button>
                <Button x:Name="BtnOpenReport" Style="{StaticResource Tile}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,0,5" ToolTip="Pick from the HTML reports for this job. One is built automatically after each upload and sync.">
                  <StackPanel Orientation="Horizontal">
                    <Border Width="26" Height="26" CornerRadius="7" Background="#E7F7EF" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE7C3;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#0E9F6E" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock Style="{StaticResource TileTitle}" Text="Open report" VerticalAlignment="Center"/>
                  </StackPanel>
                </Button>
                <Button x:Name="BtnOpenAudit" Style="{StaticResource Tile}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,5" ToolTip="Pick from the run logs for this job (upload, sync, verify and so on).">
                  <StackPanel Orientation="Horizontal">
                    <Border Width="26" Height="26" CornerRadius="7" Background="#EFF4FF" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE7C3;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#3538CD" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock Style="{StaticResource TileTitle}" Text="Open log" VerticalAlignment="Center"/>
                  </StackPanel>
                </Button>
                <Button x:Name="BtnCertificate" Style="{StaticResource Tile}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,0,5" ToolTip="Produce a one-page completion certificate for client sign-off from the most recent completed migration. Only issues once a migration has finished (upload, sync until nothing is left, then verify).">
                  <StackPanel Orientation="Horizontal">
                    <Border Width="26" Height="26" CornerRadius="7" Background="#FFFAEB" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE734;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#B54708" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock Style="{StaticResource TileTitle}" Text="Certificate" VerticalAlignment="Center"/>
                  </StackPanel>
                </Button>
                <Button x:Name="BtnProvenance" Style="{StaticResource Tile}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,5" ToolTip="Build the evidence pack for the most recent real run: a tamper-evident manifest of every migrated file's path, size, content hashes and ORIGINAL modified date, countersigned by an independent RFC 3161 timestamp authority. Only the manifest's 32-byte hash leaves this computer. One is also built automatically after every real run; use this to rebuild it or to add the timestamp if it was pending.">
                  <StackPanel Orientation="Horizontal">
                    <Border Width="26" Height="26" CornerRadius="7" Background="#EEF4FF" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#444CE7" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock Style="{StaticResource TileTitle}" Text="Provenance pack" VerticalAlignment="Center"/>
                  </StackPanel>
                </Button>
                <Button x:Name="BtnHandoverPack" Style="{StaticResource Tile}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,0,5" ToolTip="Build a client-facing zip of this job's completion certificate, migration report, verification, audit and provenance pack, plus an index.html cover page - everything already produced for this job, gathered into one file to hand over.">
                  <StackPanel Orientation="Horizontal">
                    <Border Width="26" Height="26" CornerRadius="7" Background="#F4F3FF" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE7C3;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#6938EF" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock Style="{StaticResource TileTitle}" Text="Handover pack" VerticalAlignment="Center"/>
                  </StackPanel>
                </Button>
                <Button x:Name="BtnCommsPack" Style="{StaticResource Tile}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Margin="0,0,8,0" ToolTip="Build the cutover comms pack for this job: end-user email templates, a 'finding your files' one-pager, and Intune/GPO mapped-drive notes for each mapping - for whoever runs the cutover with end users, not evidence of the migration itself.">
                  <StackPanel Orientation="Horizontal">
                    <Border Width="26" Height="26" CornerRadius="7" Background="#FDF2FA" Margin="0,0,9,0" VerticalAlignment="Center"><TextBlock Text="&#xE7C3;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#C11574" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                    <TextBlock Style="{StaticResource TileTitle}" Text="Comms pack" VerticalAlignment="Center"/>
                  </StackPanel>
                </Button>
              </UniformGrid>
              <!-- Verify the copy's own three real buttons: still hidden, still exactly the 180ae
                 popup pattern, unchanged - only Before and Records were exploded. -->
              <WrapPanel Visibility="Collapsed">
                <Button x:Name="BtnValidate" Style="{StaticResource Tile}" ToolTip="Checks every Datto file is present at the destination and up to date (its date is not older than Datto's).">
                  <StackPanel><TextBlock Style="{StaticResource TileTitle}" Text="Verify files arrived"/><TextBlock Style="{StaticResource TileDesc}" Text="Confirms every file is present and up to date."/></StackPanel>
                </Button>
                <Button x:Name="BtnDrift" Style="{StaticResource Tile}" ToolTip="Report anything changed, deleted or added at the destination since this job migrated it. Read-only.">
                  <StackPanel><TextBlock Style="{StaticResource TileTitle}" Text="Check for drift"/><TextBlock Style="{StaticResource TileDesc}" Text="What changed at the destination since migration."/></StackPanel>
                </Button>
                <Button x:Name="BtnSizeCheck" Style="{StaticResource Tile}" ToolTip="Quick overview comparing total files and size at source vs destination.">
                  <StackPanel><TextBlock Style="{StaticResource TileTitle}" Text="Compare sizes"/><TextBlock Style="{StaticResource TileDesc}" Text="Quick totals: files and size, source vs destination."/></StackPanel>
                </Button>
              </WrapPanel>
            </StackPanel>
          </GroupBox>
        </Grid>
      </Grid>

      <!-- Status + activity (row 2): a prominent live-status card, the summary/throttle
           banners (always visible), and the detailed log collapsed by default. -->
      <!-- The speed limit and the network monitor are a FULL-WIDTH strip, like the progress
           banner below them. They were docked inside the run panel, where they ate height a
           column could not spare and pushed the tiles into a scrollbar. They belong to the run,
           not to either column. DECISIONS 074. -->
              <Border Grid.Row="2" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="6"
                      Background="#FCFCFD" Padding="8,4" Margin="0,5,0,0">
                <!-- 180ah: the network monitor sits in the CENTRE of this strip, not at the right
                     edge, so the activity drawer (a 440px right-hand overlay) never covers it. -->
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="Live speed limit (Mb/s, 0 = off):" FontWeight="SemiBold" Foreground="#344054" VerticalAlignment="Center" Margin="0,0,10,0"
                               ToolTip="Speed limit in megabits per second. 0 = no limit. Takes effect immediately, even during a running upload."/>
                    <TextBlock Text="Up" VerticalAlignment="Center" Margin="0,0,3,0" Foreground="#555"/>
                    <TextBox x:Name="TxtCapUp" Width="44" VerticalAlignment="Center" Text="0"/>
                    <TextBlock Text="Down" VerticalAlignment="Center" Margin="10,0,3,0" Foreground="#555"/>
                    <TextBox x:Name="TxtCapDown" Width="44" VerticalAlignment="Center" Text="0"/>
                    <Button x:Name="BtnApplyCap" Content="Set" Margin="10,0,0,0" Padding="12,3"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center">
                    <TextBlock x:Name="LblNet" Text="Network card - All app activity   Down 0.0 Mb/s   Up 0.0 Mb/s" VerticalAlignment="Center" Foreground="#555" Margin="0,0,8,0"
                               ToolTip="The whole computer's network traffic, read from the busiest network adapter, exactly as Task Manager shows it. It is NOT this migration's speed: it includes OneDrive sync, Teams, browsers and Windows Update. Do not compare it with the speed limit. This migration's own speed is shown above the log, and that is the number the limit applies to. Expect this to sit above the limit: a file's whole allowance is taken before it starts and it then sends at full speed, so the limit is an average over time, not a ceiling on any instant."/>
                    <Border Width="150" Height="20" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="1" VerticalAlignment="Center">
                      <Canvas x:Name="NetCanvas" ClipToBounds="True"><Polyline x:Name="NetLine" Stroke="#1C6091" StrokeThickness="1"/></Canvas>
                    </Border>
                  </StackPanel>
                </Grid>
              </Border>
      <DockPanel Grid.Row="3" Margin="0,6,0,0">

        <!-- Live status card: phase + progress on top, current file + speed below -->
        <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Padding="14,8" Margin="0,0,0,5">
          <StackPanel>
            <DockPanel LastChildFill="True">
              <StackPanel DockPanel.Dock="Left" Orientation="Horizontal" VerticalAlignment="Center">
                <!-- Live pulse: a small dot that breathes while a run is active, so the status card
                     reads as live at a glance rather than a static label. Shown by Start-EngineRun,
                     its opacity is driven from the existing 300ms run timer (no extra animation infra),
                     and it is hidden again when the run ends. -->
                <Ellipse x:Name="StatusPulse" Width="10" Height="10" Fill="#1C6091" Margin="0,0,10,0" VerticalAlignment="Center" Visibility="Collapsed"/>
                <TextBlock x:Name="LblStatus" Text="Idle" FontSize="16" FontWeight="SemiBold" Foreground="#111827" VerticalAlignment="Center" MinWidth="180"/>
                <ProgressBar x:Name="Prog" Width="230" Height="16" Margin="12,0,0,0" IsIndeterminate="False" Maximum="100" Foreground="#E2500F" Background="#EEF2F7" BorderThickness="0"/>
                <TextBlock x:Name="LblElapsed" Text="" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="#475467"/>
                <TextBlock x:Name="LblEta" Text="" VerticalAlignment="Center" Margin="10,0,0,0" Foreground="#667085"/>
              </StackPanel>
              <!-- Activity pill (180ag): opens the live-activity overlay. Dark pill + green dot
                   + problem badge. Replaces the old bottom log expander as the way in. -->
              <!-- 180ah: rounded-rect button (not a blob pill), glyph + label, and the label says
                   what pressing it DOES: 'Show activity' when closed, 'Hide activity' when open. -->
              <Border x:Name="BtnActivity" DockPanel.Dock="Right" Background="#0F1115" CornerRadius="8" Padding="12,7" Margin="10,0,0,0" VerticalAlignment="Center" Cursor="Hand"
                      ToolTip="Live activity: what the run is doing right now, problems first. The complete log file is always on disk.">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#9BA1AA" VerticalAlignment="Center" Margin="0,1,8,0"/>
                  <Ellipse x:Name="ActPillDot" Width="8" Height="8" Fill="#3CCB7F" VerticalAlignment="Center" Margin="0,0,7,0"/>
                  <TextBlock x:Name="ActPillText" Text="Show activity" Foreground="White" FontWeight="SemiBold" FontSize="12.5" VerticalAlignment="Center"/>
                  <Border x:Name="ActBadge" Background="#B42318" CornerRadius="99" Padding="7,1" Margin="8,0,0,0" Visibility="Collapsed" VerticalAlignment="Center">
                    <TextBlock x:Name="ActBadgeText" Text="0" Foreground="White" FontSize="11" FontWeight="Bold"/>
                  </Border>
                </StackPanel>
              </Border>
              <Border x:Name="IssuesChip" DockPanel.Dock="Right" Background="#FEF3F2" BorderBrush="#FDA29B" BorderThickness="1" CornerRadius="10" Padding="10,3" VerticalAlignment="Center" Margin="10,0,0,0" Visibility="Collapsed">
                <TextBlock x:Name="LblIssues" Text="" Foreground="#B42318" FontSize="12.5" FontWeight="SemiBold"/>
              </Border>
              <TextBlock x:Name="LblHint" Text="" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="16,0,0,0" Foreground="#1C6091" TextTrimming="CharacterEllipsis"/>
            </DockPanel>
            <DockPanel LastChildFill="True" Margin="0,5,0,0">
              <TextBlock x:Name="LblSpeed" DockPanel.Dock="Right" Text="" VerticalAlignment="Center" Foreground="#475467" FontSize="12.5" Margin="12,0,0,0"/>
              <TextBlock x:Name="LblCurrent" Text="" VerticalAlignment="Center" Foreground="#98A2B3" FontSize="12.5" TextTrimming="CharacterEllipsis"/>
            </DockPanel>
          </StackPanel>
        </Border>

        <!-- Post-run summary (plain English) -->
        <Border x:Name="RunSummaryBanner" DockPanel.Dock="Top" Background="#E7F7EF" BorderBrush="#A6E9C5" BorderThickness="1" CornerRadius="8" Padding="12,9" Margin="0,0,0,8" Visibility="Collapsed">
          <DockPanel LastChildFill="True">
            <Button x:Name="BtnShowFiles" DockPanel.Dock="Right" Content="Show files" Padding="10,3" Margin="10,0,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="List the files behind this result: each file's name, where it is, and which side it is on. Read from the check's own CSV."/>
            <TextBlock x:Name="LblRunSummary" Text="" TextWrapping="Wrap" Foreground="#066A4B"/>
          </DockPanel>
        </Border>
        <!-- Throttle notice -->
        <Border x:Name="ThrottleBanner" DockPanel.Dock="Top" Background="#FFFAEB" BorderBrush="#FEDF89" BorderThickness="1" CornerRadius="8" Padding="12,9" Margin="0,0,0,8" Visibility="Collapsed">
          <TextBlock x:Name="LblThrottle" Text="" TextWrapping="Wrap" Foreground="#B5460F"/>
        </Border>

        <!-- 180ag: the old bottom log expander is gone; the Activity overlay replaced it.
             TxtLog stays as a HIDDEN sink: Add-EngineLine still writes it (the Copy button and
             the support bundle read it), it is just never shown. -->
        <TextBox x:Name="TxtLog" DockPanel.Dock="Top" Visibility="Collapsed" IsReadOnly="True" Height="0"/>
      </DockPanel>

      <!-- ============ 1-2-3 JOB COACH (180ak) ============
           Three numbered hints that pop in sequence after a job is created: 1 over the add
           buttons, 2 mid-window where source meets destination, 3 over the run tiles.
           Pure overlay (IsHitTestVisible False), collapses itself, never blocks a click. -->
      <Grid x:Name="CoachLayer" Grid.Row="0" Grid.RowSpan="4" Panel.ZIndex="250" Visibility="Collapsed" IsHitTestVisible="False">
        <StackPanel x:Name="Coach1" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="30,40,0,0" Opacity="0" RenderTransformOrigin="0.5,0.5">
          <StackPanel.RenderTransform><ScaleTransform x:Name="CoachS1" ScaleX="0.8" ScaleY="0.8"/></StackPanel.RenderTransform>
          <Border Width="56" Height="56" CornerRadius="99" Background="#E2500F" HorizontalAlignment="Left"><TextBlock Text="1" Foreground="White" FontSize="26" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <Border Background="#0F1115" CornerRadius="8" Padding="12,7" Margin="0,8,0,0" HorizontalAlignment="Left"><TextBlock Text="Add what you want to copy" Foreground="White" FontSize="13.5" FontWeight="SemiBold"/></Border>
        </StackPanel>
        <StackPanel x:Name="Coach2" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="120,170,0,0" Opacity="0" RenderTransformOrigin="0.5,0.5">
          <StackPanel.RenderTransform><ScaleTransform x:Name="CoachS2" ScaleX="0.8" ScaleY="0.8"/></StackPanel.RenderTransform>
          <Border Width="56" Height="56" CornerRadius="99" Background="#E2500F" HorizontalAlignment="Left"><TextBlock Text="2" Foreground="White" FontSize="26" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <Border Background="#0F1115" CornerRadius="8" Padding="12,7" Margin="0,8,0,0" HorizontalAlignment="Left"><TextBlock Text="Pick each source, choose where it goes" Foreground="White" FontSize="13.5" FontWeight="SemiBold"/></Border>
        </StackPanel>
        <StackPanel x:Name="Coach3" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="70,0,0,230" Opacity="0" RenderTransformOrigin="0.5,0.5">
          <StackPanel.RenderTransform><ScaleTransform x:Name="CoachS3" ScaleX="0.8" ScaleY="0.8"/></StackPanel.RenderTransform>
          <Border Width="56" Height="56" CornerRadius="99" Background="#E2500F" HorizontalAlignment="Left"><TextBlock Text="3" Foreground="White" FontSize="26" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <Border Background="#0F1115" CornerRadius="8" Padding="12,7" Margin="0,8,0,0" HorizontalAlignment="Left"><TextBlock Text="Check readiness, preview, then upload" Foreground="White" FontSize="13.5" FontWeight="SemiBold"/></Border>
        </StackPanel>
      </Grid>

      <!-- ============ LIVE ACTIVITY OVERLAY (180ag) ============
           A right-hand drawer floating ABOVE the app (ZIndex): nothing behind it moves or
           resizes. Slides in/out via the named TranslateTransform (Open-/Close-ActivityDrawer).
           Negative margins bleed it to the window edges past the content grid's padding. -->
      <Border x:Name="ActDrawer" Grid.Row="0" Grid.RowSpan="4" Panel.ZIndex="300" HorizontalAlignment="Right" Width="440"
              Margin="0,-8,-14,-12" Background="White" BorderBrush="#E4E7EC" BorderThickness="1,0,0,0" Visibility="Collapsed">
        <Border.RenderTransform><TranslateTransform x:Name="ActSlide" X="480"/></Border.RenderTransform>
        <DockPanel>
          <Border DockPanel.Dock="Top" Background="#0F1115" Padding="16,12">
            <DockPanel LastChildFill="False">
              <Ellipse x:Name="ActDot" Width="9" Height="9" Fill="#3CCB7F" VerticalAlignment="Center" Margin="0,0,9,0"/>
              <TextBlock Text="Live activity" Foreground="White" FontSize="14.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
              <Border Background="#1C2027" BorderBrush="#2A2F38" BorderThickness="1" CornerRadius="99" Padding="9,2" Margin="10,0,0,0" VerticalAlignment="Center">
                <TextBlock x:Name="ActState" Text="IDLE" Foreground="#8B919A" FontSize="10.5" FontWeight="Bold"/>
              </Border>
              <Button x:Name="BtnActClose" DockPanel.Dock="Right" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="12" Width="30" Padding="0,5"
                      Background="Transparent" BorderThickness="0" Foreground="#8B919A" FocusVisualStyle="{x:Null}" ToolTip="Close (the run carries on)"/>
            </DockPanel>
          </Border>
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="12,10,12,0">
            <Border Background="#F9FAFB" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="9" Padding="10,7" Width="132" Margin="0,0,8,0">
              <StackPanel><TextBlock x:Name="ActDone" Text="-" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="FILES DONE" FontSize="10" Foreground="#98A2B3" FontWeight="SemiBold"/></StackPanel>
            </Border>
            <Border Background="#F9FAFB" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="9" Padding="10,7" Width="132" Margin="0,0,8,0">
              <StackPanel><TextBlock x:Name="ActFailed" Text="0" FontSize="15" FontWeight="SemiBold" Foreground="#B42318"/><TextBlock Text="PROBLEMS" FontSize="10" Foreground="#98A2B3" FontWeight="SemiBold"/></StackPanel>
            </Border>
            <Border Background="#F9FAFB" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="9" Padding="10,7" Width="132">
              <StackPanel><TextBlock x:Name="ActSpeed" Text="-" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="SPEED" FontSize="10" Foreground="#98A2B3" FontWeight="SemiBold"/></StackPanel>
            </Border>
          </StackPanel>
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="12,9,12,4">
            <Button x:Name="BtnActOverview" Content="Overview" FontSize="11.5" Padding="11,3" Margin="0,0,6,0"/>
            <Button x:Name="BtnActProblems" Content="Problems" FontSize="11.5" Padding="11,3" Margin="0,0,6,0"/>
            <Button x:Name="BtnActFiles" Content="Files" FontSize="11.5" Padding="11,3" Margin="0,0,6,0"/>
            <Button x:Name="BtnActAll" Content="Everything" FontSize="11.5" Padding="11,3"/>
          </StackPanel>
          <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="12,8">
            <DockPanel LastChildFill="False">
              <Button x:Name="BtnActOpenLog" Content="Open log file" FontSize="12" Padding="11,4" Margin="0,0,8,0" ToolTip="The complete log on disk; nothing on screen is ever the full record."/>
              <Button x:Name="BtnActCopy" Content="Copy" FontSize="12" Padding="11,4" ToolTip="Copy the on-screen log text to the clipboard."/>
              <CheckBox x:Name="ChkActFollow" DockPanel.Dock="Right" Content="Follow" IsChecked="True" VerticalAlignment="Center" FontSize="11.5" Foreground="#475467"
                        ToolTip="Keep scrolling to the newest entry. Untick to read back while the run continues."/>
            </DockPanel>
          </Border>
          <ListBox x:Name="LstActivity" BorderThickness="0" Background="White" Margin="6,2,6,4"
                   HorizontalContentAlignment="Stretch" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                   VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Standard">
            <ListBox.ItemContainerStyle>
              <Style TargetType="ListBoxItem">
                <Setter Property="Padding" Value="8,6"/>
                <Setter Property="Margin" Value="2,1"/>
                <Setter Property="Focusable" Value="False"/>
                <Setter Property="Opacity" Value="0"/>
                <Setter Property="RenderTransform"><Setter.Value><TranslateTransform Y="7"/></Setter.Value></Setter>
                <Setter Property="Template">
                  <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                      <Border x:Name="bd" Background="Transparent" CornerRadius="8" Padding="{TemplateBinding Padding}">
                        <ContentPresenter/>
                      </Border>
                      <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#F9FAFB"/></Trigger>
                      </ControlTemplate.Triggers>
                    </ControlTemplate>
                  </Setter.Value>
                </Setter>
                <Style.Triggers>
                  <EventTrigger RoutedEvent="Loaded">
                    <BeginStoryboard>
                      <Storyboard>
                        <DoubleAnimation Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.22"/>
                        <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.Y)" To="0" Duration="0:0:0.26">
                          <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                        </DoubleAnimation>
                      </Storyboard>
                    </BeginStoryboard>
                  </EventTrigger>
                </Style.Triggers>
              </Style>
            </ListBox.ItemContainerStyle>
          </ListBox>
        </DockPanel>
      </Border>
    </Grid>
  </DockPanel>
</Window>
"@
$script:Splash = $null
try {
    $splashBmp = $null
    try {
        $ms = New-Object System.IO.MemoryStream (,[Convert]::FromBase64String($script:LogoB64))
        $splashBmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $splashBmp.BeginInit(); $splashBmp.CacheOption = 'OnLoad'; $splashBmp.StreamSource = $ms; $splashBmp.EndInit(); $splashBmp.Freeze()
    } catch {}
    $script:Splash = New-Object System.Windows.Window -Property @{ WindowStyle='None'; ResizeMode='NoResize'; AllowsTransparency=$true; Background='Transparent'; ShowInTaskbar=$false; WindowStartupLocation='CenterScreen'; Topmost=$true; Width=360; SizeToContent='Height' }
    $splashBorder = New-Object System.Windows.Controls.Border -Property @{ CornerRadius=(New-Object System.Windows.CornerRadius 10); Padding=(New-Object System.Windows.Thickness 24); BorderThickness=(New-Object System.Windows.Thickness 1) }
    $splashBorder.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0,0,0))
    $splashBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1C,0x60,0x91))
    $splashStack = New-Object System.Windows.Controls.StackPanel
    if ($splashBmp) {
        $splashImg = New-Object System.Windows.Controls.Image -Property @{ Source=$splashBmp; Width=200; Stretch='Uniform'; HorizontalAlignment='Center' }
        [void]$splashStack.Children.Add($splashImg)
    }
    $splashT1 = New-Object System.Windows.Controls.TextBlock -Property @{ Text='Liscaragh Migrate'; Foreground='White'; FontSize=16; FontWeight='SemiBold'; HorizontalAlignment='Center'; Margin=(New-Object System.Windows.Thickness 0,12,0,0) }
    [void]$splashStack.Children.Add($splashT1)
    $splashT2 = New-Object System.Windows.Controls.TextBlock -Property @{ Text=("Starting up  -  v$($script:AppVersion)"); FontSize=12; HorizontalAlignment='Center'; Margin=(New-Object System.Windows.Thickness 0,4,0,0) }
    $splashT2.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xBB,0xBB,0xBB))
    [void]$splashStack.Children.Add($splashT2)
    $splashBorder.Child = $splashStack
    $script:Splash.Content = $splashBorder
    $script:Splash.Show()
    $script:Splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
} catch { $script:Splash = $null }
$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)
Lz2e8ddc8b18 $win
$ctrl = @{}
foreach ($n in 'LblJob','JobChip','LblJobPrefix','ConnDot','MnuJobNew','MnuJobOpen','MnuJobRecent','MnuJobSave','MnuJobSaveAs','MnuJobRename','MnuJobOpenFolder','MnuJobExport','MnuJobImport','MnuJobClose','MnuJobDelete','MnuJobSwitch','MnuJobExit','MnuSettingsChecklist','MnuSettingsApi','MnuSettingsWizard','MnuSettingsEmail','MnuSettingsTuning','MnuSettingsDecommission','MnuHelpHowto','MnuHelpCheck','MnuHelpUpdate','MnuHelpSupport','MnuHelpLicence','MnuHelpLicInstall','MnuHelpAbout','MnuHelpVersion','BtnConnect','BtnAddFolder','BtnRemoveFolder','BtnShareCreds','ChkLinuxSrc','BtnLinuxInfo','LblConn','LblVersionTop','ImgLogoTop','LblNet','NetCanvas','NetLine','TxtFilter','TxtFilterHint','GettingStarted','LblQuickStart','CoachLayer','Coach1','Coach2','Coach3','LstProjects','BtnFilters','LblProjectsHead','LblMapHeader','LblDestQ','TxtDeltaDesc','LblProject','LblSrcIntro','PnlSrcFolders','LstSource','ChkSrcContents','BtnAddSource','BtnRemoveSource','BtnTestSource','LblSourceCheck','RbSite','RbOneDrive','RbSkip','LblLoc','TxtLoc','TxtLocHint','BtnFindSite','RowLib','TxtLib','BtnPickLib','TxtFolder','BtnBrowseFolder','BtnTestDest','ChkNest','SourcePathBox','LblSourcePath','DestPathBox','LblDestPath','LblDestWarn','BtnApply','BtnApplySel','BtnApplyAll','BtnCheck','LblCheck','RunSummaryBanner','LblRunSummary','BtnShowFiles','GridBeforeCopy','BtnPreflight','BtnDryRun','BtnTransfer','BtnDelta','BtnSchedule','BtnRerunFailed','BtnStop','BtnPause','BtnPauseTitle','BtnPauseDesc','BtnCatVerify','BtnValidate','BtnSizeCheck','BtnDrift','BtnOpenReport','BtnCertificate','BtnSourceReview','BtnProvenance','BtnHandoverPack','BtnCommsPack','BtnOpenAudit','BtnActivity','ActPillDot','ActPillText','ActBadge','ActBadgeText','ActDrawer','ActDot','ActState','BtnActClose','ActDone','ActFailed','ActSpeed','BtnActOverview','BtnActProblems','BtnActFiles','BtnActAll','BtnActOpenLog','BtnActCopy','ChkActFollow','LstActivity','Prog','StatusPulse','LblStatus','LblElapsed','LblEta','LblHint','LblCurrent','LblSpeed','IssuesChip','LblIssues','TxtLog','ThrottleBanner','LblThrottle','TxtCapUp','TxtCapDown','BtnApplyCap') {
    $ctrl[$n] = $win.FindName($n)
}
Set-BrandLogo $ctrl.ImgLogoTop $script:LogoMigrateB64
if ($ctrl.ImgLogoTop) {
    $ctrl.ImgLogoTop.Add_MouseLeftButtonUp({
        try { Start-Process 'https://liscaragh.com/migrate/' } catch { Lz5af601c665 ('Could not open the browser: ' + $_.Exception.Message) }
    })
}
function Lz154ffece7e {
    param([bool]$SetupDone)
    if (-not $ctrl.LblQuickStart) { return }
    if ($script:TransferMode -eq 'LocalFs') {
        try {
            $ctrl.LblQuickStart.Inlines.Clear()
            $ctrl.LblQuickStart.Text = ("Quick start: Files and folders" + [Environment]::NewLine +
                "1.  From the Job menu, select New, then give the job a name." + [Environment]::NewLine +
                "2.  Select 'Add folder...' for each folder you want to migrate. Choose either a local folder (for example, D:\Shared\Finance) or a network share (for example, \\server\share)." + [Environment]::NewLine +
                "3.  Select a source folder, choose its Microsoft 365 destination on the right, then select 'Apply to this source'." + [Environment]::NewLine +
                "4.  Select 'Check readiness' to identify any issues before you begin." + [Environment]::NewLine +
                "5.  Select 'Preview' to see what will be copied." + [Environment]::NewLine +
                "6.  When you're happy, select 'Full migration'. Use 'Sync new and changed' on later runs to copy only new or updated files." + [Environment]::NewLine +
                "The migration is one way. The source is never modified, and nothing is deleted from the destination.")
        } catch {}
        return
    }
    $qs = $script:QuickStartSections
    $tb = $ctrl.LblQuickStart
    try {
        $tb.Inlines.Clear()
        $tb.LineHeight = 20
        $bc = New-Object System.Windows.Media.BrushConverter
        $accent = $bc.ConvertFromString('#1C6091')
        $bodyBr = $bc.ConvertFromString('#475467')
        $addRun = {
            param($text,$brush,[bool]$bold,[bool]$italic)
            $r = New-Object System.Windows.Documents.Run "$text"
            if ($brush)  { $r.Foreground = $brush }
            if ($bold)   { $r.FontWeight = 'Bold' }
            if ($italic) { $r.FontStyle  = 'Italic' }
            [void]$tb.Inlines.Add($r)
        }
        $nl = { [void]$tb.Inlines.Add((New-Object System.Windows.Documents.LineBreak)) }
        if (-not $SetupDone) {
            & $addRun "$($qs[0].H)" $accent $true $false; & $nl
            & $addRun "$($qs[0].B)" $bodyBr $false $false; & $nl; & $nl
        }
        & $addRun "$($qs[1].H)" $accent $true $false; & $nl
        foreach ($ln in ("$($qs[1].B)" -split "`n")) {
            $t = "$ln"
            if ($t.Trim() -eq '') { & $nl; continue }
            if ($t -match '^\s*(\d+\.)\s*(.*)$') {
                & $addRun ($Matches[1] + '  ') $accent $true $false
                & $addRun $Matches[2] $bodyBr $false $false
            } else {
                & $addRun $t $bodyBr $false $true
            }
            & $nl
        }
    } catch {
        $tb.Text = if ($SetupDone) { "$($qs[1].B)" } else { "$($qs[0].H): $($qs[0].B)`n`n$($qs[1].B)" }
    }
}
Lz154ffece7e $false
if ($ctrl.MnuHelpVersion) { $ctrl.MnuHelpVersion.Header = "Version $($script:AppVersion)  -  Liscaragh Software" }
if ($ctrl.LblVersionTop) { $ctrl.LblVersionTop.Text = "Version $($script:AppVersion)" }
foreach ($bn in @('BtnConnect','BtnAddFolder','BtnRemoveFolder','BtnShareCreds','BtnFilters','RbSite','RbOneDrive','RbSkip','TxtLoc','BtnFindSite','ChkSrcContents','BtnAddSource','BtnRemoveSource','BtnTestSource','TxtLib','BtnPickLib','TxtFolder','BtnBrowseFolder','BtnTestDest','BtnApply','BtnApplySel','BtnApplyAll','BtnCheck','BtnPreflight','BtnDryRun','BtnTransfer','BtnDelta','BtnStop','BtnPause','BtnValidate','BtnSizeCheck','BtnOpenReport','BtnCertificate','BtnSourceReview','BtnProvenance','BtnHandoverPack','BtnCommsPack','BtnOpenAudit')) {
    $b = $ctrl[$bn]
    if ($b) {
        $b.Add_MouseEnter({ param($s,$e) try { $ctrl.LblHint.Text = "$($s.ToolTip)" } catch {} })
        $b.Add_MouseLeave({ $ctrl.LblHint.Text = '' })
    }
}
function Lz5af601c665 { param([string]$Text) $ctrl.LblStatus.Text = $Text }
function ConvertTo-FriendlyDuration {
    param([string]$Text)
    $ts = [TimeSpan]::Zero
    if (-not [TimeSpan]::TryParse("$Text", [ref]$ts)) { return "$Text" }
    if ($ts.TotalHours -ge 1) { return ('{0}h {1:00}m {2:00}s' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds) }
    if ($ts.TotalMinutes -ge 1) { return ('{0}m {1:00}s' -f $ts.Minutes, $ts.Seconds) }
    return ('{0}s' -f [int]$ts.Seconds)
}
function Format-Span { param([TimeSpan]$ts)
    if ($ts.TotalHours -ge 1) { return ('{0}h {1:D2}m' -f [int]$ts.TotalHours, $ts.Minutes) }
    return ('{0}m {1:D2}s' -f [int]$ts.TotalMinutes, $ts.Seconds)
}
function Format-Bytes { param([int64]$b)
    if ($b -ge 1TB) { return ('{0:N2} TB' -f ($b/1TB)) }
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b/1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b/1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b/1KB)) }
    return "$b B"
}
function Lz6b0915b8df {
    param([int]$Max,[int]$HardMax,[int]$PausedSeconds,[int]$Code=0)
    if ($Max -ge $HardMax -and $PausedSeconds -le 0) {
        $script:ThrM365 = ''
    } else {
        $codeTxt = switch ($Code) {
            429 { ' (HTTP 429: too many requests too fast)' }
            503 { ' (HTTP 503: server busy)' }
            default { '' }
        }
        $script:ThrM365 = if ($PausedSeconds -gt 0) {
            "Microsoft 365 is throttling$codeTxt. Pausing about $PausedSeconds s, then continuing at $Max of $HardMax uploaders. This is normal protection and the job keeps running."
        } else {
            "Microsoft 365 is throttling$codeTxt. Easing off to $Max of $HardMax uploaders to stay within limits. Speed recovers automatically."
        }
    }
    Lz1cf424d45d
}
function Lz254ae81222 {
    param([int]$GapMs,[int]$Code=0)
    $codeTxt = switch ($Code) {
        429 { ' (HTTP 429: too many requests too fast)' }
        503 { ' (HTTP 503: server busy)' }
        default { '' }
    }
    $gapTxt = if ($GapMs -gt 0) { " Now reading at about $GapMs ms between requests." } else { '' }
    $script:ThrDatto = "Datto is limiting how fast we can read$codeTxt. Learning the fastest rate your Datto account allows and adjusting to it.$gapTxt Normal on large projects, not an error: it settles after the first few."
    Lz1cf424d45d
}
function Lz1cf424d45d {
    $parts = @($script:ThrDatto, $script:ThrM365) | Where-Object { $_ }
    if (-not $parts.Count) { $ctrl.ThrottleBanner.Visibility = 'Collapsed'; return }
    $ctrl.LblThrottle.Text = ($parts -join '   ')
    $ctrl.ThrottleBanner.Visibility = 'Visible'
}
function Lzb64e21bffb { param([double]$sec)
    if ($sec -lt 0) { $sec = 0 }
    $ts = [TimeSpan]::FromSeconds([double]$sec)
    if ($ts.TotalDays    -ge 1) { return ('{0}d {1}h'   -f [int]$ts.TotalDays,  $ts.Hours) }
    if ($ts.TotalHours   -ge 1) { return ('{0}h {1:D2}m' -f [int]$ts.TotalHours, $ts.Minutes) }
    if ($ts.TotalMinutes -ge 1) { return ('{0}m'         -f [int]$ts.TotalMinutes) }
    return ('{0}s' -f [int]$ts.TotalSeconds)
}
function Lz69b24f27d2 {
    param([double]$SmallRate,[double]$SmallRemaining,[double]$LargeRate,[double]$LargeBytesRemaining,
          [double]$BytesRate,[double]$BytesRemaining)
    if ($SmallRemaining -gt 0 -or $LargeBytesRemaining -gt 0) {
        $twoOk = $true; $eta = 0.0
        if ($SmallRemaining -gt 0)      { if ($SmallRate -gt 0) { $eta += $SmallRemaining / $SmallRate } else { $twoOk = $false } }
        if ($LargeBytesRemaining -gt 0) { if ($LargeRate -gt 0) { $eta += $LargeBytesRemaining / $LargeRate } else { $twoOk = $false } }
        if ($twoOk) { return $eta }
    }
    if ($BytesRemaining -le 0) { return 0.0 }
    if ($BytesRate -gt 0) { return $BytesRemaining / $BytesRate }
    return -1
}
function Lz056d9326f8 {
    param($Samples,[int]$SmallDone,[int]$SmallTotal,[int64]$LargeDone,[int64]$LargeTotal,
          [int64]$BytesDone,[int64]$BytesTotal,[int]$Final)
    if ($null -eq $Samples -or $Samples.Count -lt 2) { return $null }
    $old = $Samples[0]; $new = $Samples[$Samples.Count-1]
    $span = ($new.T - $old.T).TotalSeconds
    if ($span -lt 45 -or $new.Bytes -lt $old.Bytes) { return $null }
    $mid = $old
    foreach ($s in $Samples) { if (($new.T - $s.T).TotalSeconds -le [math]::Max($span/2,30)) { $mid = $s; break } }
    $rspan = ($new.T - $mid.T).TotalSeconds
    if ($rspan -lt 5) { $mid = $old; $rspan = $span }
    $bytesRateFull   = ($new.Bytes - $old.Bytes)/$span
    $smallRateFull   = ($new.Small - $old.Small)/$span
    $largeRateFull   = ($new.Large - $old.Large)/$span
    $bytesRateRecent = ($new.Bytes - $mid.Bytes)/$rspan
    $smallRateRecent = ($new.Small - $mid.Small)/$rspan
    $largeRateRecent = ($new.Large - $mid.Large)/$rspan
    $hasRegime = (($SmallTotal -gt 0) -or ($LargeTotal -gt 0)) -and ($Final -eq 1)
    $smallRem = [math]::Max($SmallTotal - $SmallDone, 0)
    $largeRem = [math]::Max([double]($LargeTotal - $LargeDone), 0.0)
    $bytesRem = [math]::Max([double]($BytesTotal - $BytesDone), 0.0)
    if ($hasRegime) {
        $etaA = Lz69b24f27d2 -SmallRate $smallRateFull   -SmallRemaining $smallRem -LargeRate $largeRateFull   -LargeBytesRemaining $largeRem -BytesRate $bytesRateFull   -BytesRemaining $bytesRem
        $etaB = Lz69b24f27d2 -SmallRate $smallRateRecent -SmallRemaining $smallRem -LargeRate $largeRateRecent -LargeBytesRemaining $largeRem -BytesRate $bytesRateRecent -BytesRemaining $bytesRem
    } else {
        $etaA = Lz69b24f27d2 -SmallRate 0 -SmallRemaining 0 -LargeRate 0 -LargeBytesRemaining 0 -BytesRate $bytesRateFull   -BytesRemaining $bytesRem
        $etaB = Lz69b24f27d2 -SmallRate 0 -SmallRemaining 0 -LargeRate 0 -LargeBytesRemaining 0 -BytesRate $bytesRateRecent -BytesRemaining $bytesRem
    }
    $cands = @($etaA,$etaB) | Where-Object { $_ -ge 0 }
    if ($cands.Count -lt 1) { return 'Waiting on rate limits...' }
    $lo = ($cands | Measure-Object -Minimum).Minimum
    $hi = ($cands | Measure-Object -Maximum).Maximum
    if (($hi/86400.0) -gt 30) { return 'Estimating time left (settling)...' }
    $prov = if ($Final -eq 1) { '' } else { ' so far' }
    $loT = Lzb64e21bffb $lo; $hiT = Lzb64e21bffb $hi
    if ($loT -eq $hiT) { return "About $hiT left$prov" }
    return "About $loT to $hiT left$prov"
}
function Lzedfa63e5ff {
    param([int]$Done,[int]$Total,[int64]$BytesDone,[int64]$BytesTotal,
          [int]$SmallDone,[int]$SmallTotal,[int64]$LargeDone,[int64]$LargeTotal,[int]$Final,[string]$CurrentName)
    try {
        if ($Total -gt 0 -and $ctrl.BtnPause -and -not $script:Paused -and -not $ctrl.BtnPause.IsEnabled) {
            $ctrl.BtnPause.IsEnabled = $true
            if ($ctrl.BtnPauseDesc) { $ctrl.BtnPauseDesc.Text = 'Hold the copy; Resume carries on.' }
        }
        $frac = if ($BytesTotal -gt 0) { $BytesDone / $BytesTotal } elseif ($Total -gt 0) { $Done / $Total } else { 0 }
        $ctrl.Prog.IsIndeterminate = $false; $ctrl.Prog.Value = [math]::Round($frac * 100)
        try { if ($ctrl.ActDone -and $Total -gt 0) { $ctrl.ActDone.Text = ('{0:N0} / {1:N0}' -f $Done, $Total) } } catch {}
        $remaining = [math]::Max($Total - $Done, 0)
        $scopeTxt = ''
        if ($script:ScopeSkipped -gt 0 -and $script:ScopeTotal -gt 0) {
            $scopeTxt = "   -   $($script:ScopeTotal) in this $($script:NItem), $($script:ScopeSkipped) already there"
        }
        $ctrl.LblStatus.Text = "$Done / $Total files  ($remaining left)$scopeTxt"
        try { $ctrl.LblEta.Foreground = '#555' } catch {}
        $now = Get-Date
        if ($null -eq $script:EtaSamples) { $script:EtaSamples = New-Object System.Collections.ArrayList }
        [void]$script:EtaSamples.Add([pscustomobject]@{ T=$now; Bytes=$BytesDone; Small=$SmallDone; Large=$LargeDone })
        while ($script:EtaSamples.Count -gt 2 -and ($now - $script:EtaSamples[0].T).TotalSeconds -gt 300) { $script:EtaSamples.RemoveAt(0) }
        $etaText = Lz056d9326f8 -Samples $script:EtaSamples -SmallDone $SmallDone -SmallTotal $SmallTotal -LargeDone $LargeDone -LargeTotal $LargeTotal -BytesDone $BytesDone -BytesTotal $BytesTotal -Final $Final
        if ($etaText) { $ctrl.LblEta.Text = $etaText; try { $ctrl.LblHint.Text = 'Estimate improves as it runs; pace is set by the Datto limit.' } catch {} }
        elseif (-not $script:EtaShownOnce) { $ctrl.LblEta.Text = 'Estimating time left...' }
        if ($etaText) { $script:EtaShownOnce = $true }
        if ($CurrentName) { $ctrl.LblCurrent.Text = 'Now: ' + $CurrentName }
        if ($script:ProgLastTime) {
            $dt = ($now - $script:ProgLastTime).TotalSeconds
            if ($dt -ge 1.0) {
                $mbps = (($BytesDone - [int64]$script:ProgLastBytes) / 1MB) / $dt
                if ($mbps -ge 0) { $ctrl.LblSpeed.Text = ('This migration: {0:N1} Mb/s ({1:N1} MB/s)  -  {2} of {3} moved' -f ($mbps * 8), $mbps, (Format-Bytes $BytesDone), (Format-Bytes $BytesTotal)) }
                try { if ($ctrl.ActSpeed -and $mbps -ge 0) { $ctrl.ActSpeed.Text = ('{0:N1} Mb/s' -f ($mbps * 8)) } } catch {}
                $script:ProgLastBytes = $BytesDone; $script:ProgLastTime = $now
            }
        } else { $script:ProgLastBytes = $BytesDone; $script:ProgLastTime = $now }
    } catch {}
}
function Lz44faba9a81 {
    if (-not $ctrl -or -not $ctrl.CoachLayer) { return }
    $ctrl.CoachLayer.Visibility = 'Visible'
    $step = 4.0; $show = 3.0
    for ($i = 0; $i -lt 3; $i++) {
        $el = switch ($i) { 0 { $ctrl.Coach1 } 1 { $ctrl.Coach2 } default { $ctrl.Coach3 } }
        if (-not $el) { continue }
        $t0 = $i * $step
        $op = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        foreach ($kf in @(, @(0.0, 0.0)) + @(, @($t0, 0.0)) + @(, @(($t0 + 0.35), 1.0)) + @(, @(($t0 + $show), 1.0)) + @(, @(($t0 + $step), 0.0))) {
            [void]$op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame([double]$kf[1], [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([timespan]::FromSeconds([double]$kf[0])))))
        }
        $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $op)
        $sc = $win.FindName("CoachS$($i + 1)")
        if ($sc) {
            foreach ($prop in @([System.Windows.Media.ScaleTransform]::ScaleXProperty, [System.Windows.Media.ScaleTransform]::ScaleYProperty)) {
                $sa = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
                foreach ($kf in @(, @($t0, 0.8)) + @(, @(($t0 + 0.45), 1.16)) + @(, @(($t0 + 0.8), 1.0))) {
                    [void]$sa.KeyFrames.Add((New-Object System.Windows.Media.Animation.SplineDoubleKeyFrame([double]$kf[1], [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([timespan]::FromSeconds([double]$kf[0])))))
                }
                $sc.BeginAnimation($prop, $sa)
            }
        }
    }
    $tm = New-Object System.Windows.Threading.DispatcherTimer
    $tm.Interval = [timespan]::FromSeconds(3 * $step + 0.4)
    $tm.Add_Tick({ param($sndr, $e) try { $sndr.Stop(); if ($ctrl.CoachLayer) { $ctrl.CoachLayer.Visibility = 'Collapsed' } } catch {} })
    $tm.Start()
}
function Lzbeaeeec3a0 {
    param([bool]$On)
    try {
        if (-not ('Liscara.Power' -as [type])) {
            Add-Type -Namespace Liscara -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
        }
        if ($On) { [void][Liscara.Power]::SetThreadExecutionState([uint32]2147483649) }
        else     { [void][Liscara.Power]::SetThreadExecutionState([uint32]2147483648) }
    } catch {}
}
function Lz53a0917c36 {
    $mapped = @($script:Projects | Where-Object { $script:Map.ContainsKey($_.Id) }).Count
    $its = if ($script:NItems) { $script:NItems } else { 'projects' }
    $base = "About to copy $mapped $its into the destinations below."
    try {
        $rr = Lz675256916c
        if ($rr) {
            $sf = Join-Path $rr 'api-preflight-summary.csv'
            if (Test-Path $sf) {
                $rows = @(Import-Csv $sf)
                $gb = [double](@($rows | ForEach-Object { [double]$_.RequiredGB } | Measure-Object -Sum).Sum)
                $when = (Get-Item $sf).LastWriteTime.ToString('d MMM HH:mm')
                $base = "About to copy $mapped $its, roughly $([math]::Round($gb,1)) GB as measured by the readiness check on $when."
            }
        }
    } catch {}
    return "$base Nothing at the source is changed, and nothing already at the destination is deleted."
}
function Lz103dfbf0f4 {
    if (-not $ctrl -or -not $ctrl.ActDrawer) { return }
    $ctrl.ActDrawer.Visibility = 'Visible'
    $script:ActOpen = $true
    if ($ctrl.ActPillText) { $ctrl.ActPillText.Text = 'Hide activity' }
    try {
        $sl = $win.FindName('ActSlide')
        $a = New-Object System.Windows.Media.Animation.DoubleAnimation(0, (New-Object System.Windows.Duration([timespan]::FromMilliseconds(260))))
        $e = New-Object System.Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseOut'; $a.EasingFunction = $e
        $sl.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
    } catch {}
}
function Close-ActivityDrawer {
    if (-not $ctrl -or -not $ctrl.ActDrawer) { return }
    $script:ActOpen = $false
    if ($ctrl.ActPillText) { $ctrl.ActPillText.Text = 'Show activity' }
    try {
        $sl = $win.FindName('ActSlide')
        $a = New-Object System.Windows.Media.Animation.DoubleAnimation(480, (New-Object System.Windows.Duration([timespan]::FromMilliseconds(220))))
        $e = New-Object System.Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseIn'; $a.EasingFunction = $e
        $a.Add_Completed({ try { if (-not $script:ActOpen) { $ctrl.ActDrawer.Visibility = 'Collapsed' } } catch {} })
        $sl.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
    } catch { $ctrl.ActDrawer.Visibility = 'Collapsed' }
}
function Lzbb958b93a3 { param($Rec)
    switch ($script:ActFilter) {
        'Problems' { return ($Rec.Kind -eq 'err' -or $Rec.Kind -eq 'warn') }
        'Files'    { return ($Rec.Kind -eq 'file') }
        'All'      { return $true }
        default    { return ($Rec.Kind -ne 'file') }
    }
}
function Lz43a79d8eb0 { param($Rec)
    if (-not $ctrl -or -not $ctrl.LstActivity) { return }
    $bc = New-Object System.Windows.Media.BrushConverter
    $spec = switch ($Rec.Kind) {
        'err'  { @{ G=[char]0xE711; T='#FEF3F2'; C='#B42318' } }
        'warn' { @{ G=[char]0xE7BA; T='#FFF4E6'; C='#B5460F' } }
        'ok'   { @{ G=[char]0xE73E; T='#E7F7EF'; C='#0E9F6E' } }
        'file' { @{ G=[char]0xE898; T='#EFF4F9'; C='#1C6091' } }
        default{ @{ G=[char]0xE946; T='#F2F4F7'; C='#98A2B3' } }
    }
    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in 'Auto','*','Auto') { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = $w; $g.ColumnDefinitions.Add($c) }
    $chip = New-Object System.Windows.Controls.Border
    $chip.Width = 24; $chip.Height = 24; $chip.CornerRadius = '7'; $chip.Margin = '0,1,10,0'; $chip.VerticalAlignment = 'Top'
    $chip.Background = $bc.ConvertFromString($spec.T)
    $gl = New-Object System.Windows.Controls.TextBlock
    $gl.Text = [string]$spec.G; $gl.FontFamily = 'Segoe MDL2 Assets'; $gl.FontSize = 11
    $gl.Foreground = $bc.ConvertFromString($spec.C); $gl.HorizontalAlignment = 'Center'; $gl.VerticalAlignment = 'Center'
    $chip.Child = $gl
    [System.Windows.Controls.Grid]::SetColumn($chip, 0); [void]$g.Children.Add($chip)
    $tx = New-Object System.Windows.Controls.TextBlock
    $tx.Text = "$($Rec.Msg)"; $tx.TextWrapping = 'Wrap'; $tx.FontSize = 12.5
    if ($Rec.Kind -eq 'err') { $tx.Foreground = $bc.ConvertFromString('#B42318'); $tx.FontWeight = 'SemiBold' }
    else { $tx.Foreground = $bc.ConvertFromString('#101828') }
    [System.Windows.Controls.Grid]::SetColumn($tx, 1); [void]$g.Children.Add($tx)
    $tm = New-Object System.Windows.Controls.TextBlock
    $tm.Text = "$($Rec.Time)"; $tm.FontSize = 10.5; $tm.Foreground = $bc.ConvertFromString('#C0C6CE'); $tm.Margin = '10,2,0,0'; $tm.VerticalAlignment = 'Top'
    [System.Windows.Controls.Grid]::SetColumn($tm, 2); [void]$g.Children.Add($tm)
    [void]$ctrl.LstActivity.Items.Add($g)
    while ($ctrl.LstActivity.Items.Count -gt 1500) { $ctrl.LstActivity.Items.RemoveAt(0) }
    if ($ctrl.ChkActFollow -and $ctrl.ChkActFollow.IsChecked) { try { $ctrl.LstActivity.ScrollIntoView($g) } catch {} }
}
function Lz684763ee8e { param([string]$Line)
    $time = ''; $tag = ''; $msg = "$Line"
    if ($Line -match '^\S*T(\d{2}:\d{2}:\d{2})[^\[]*\[(\w+)\]\s*(.*)$') { $time = $Matches[1]; $tag = $Matches[2]; $msg = $Matches[3] }
    elseif ($Line -match '^\s*\[(\w+)\]\s*(.*)$') { $tag = $Matches[1]; $msg = $Matches[2] }
    if (-not $time) { $time = (Get-Date).ToString('HH:mm:ss') }
    if (-not "$msg".Trim()) { return }
    $kind = if ("$msg" -match 'UPLOAD FAILED|DOWNLOAD FAILED|VERIFY FAILED' -or $tag -eq 'ERROR') { 'err' }
        elseif ($tag -eq 'WARN') { 'warn' }
        elseif ("$msg" -match '^\s*[+\-]\s*\[') { 'file' }
        elseif ($tag -eq 'OK') { 'ok' } elseif ($tag -eq 'INFO') { 'sys' } else { 'file' }
    $rec = [pscustomobject]@{ Kind = $kind; Msg = "$msg"; Time = $time }
    if ($null -eq $script:ActBuf) { $script:ActBuf = New-Object System.Collections.Generic.List[object] }
    [void]$script:ActBuf.Add($rec)
    if ($script:ActBuf.Count -gt 2000) { $script:ActBuf.RemoveAt(0) }
    if (Lzbb958b93a3 $rec) { [void](Lz43a79d8eb0 $rec) }
}
function Lz1ad19acf41 {
    param([string]$Line)
    $tag = ''; $msg = "$Line"
    if ($Line -match '^\S*T(\d{2}:\d{2}:\d{2})[^\[]*\[(\w+)\]\s*(.*)$') { $tag = $Matches[2]; $msg = $Matches[3] }
    elseif ($Line -match '^\s*\[(\w+)\]\s*(.*)$') { $tag = $Matches[1]; $msg = $Matches[2] }
    if ("$msg" -match 'UPLOAD FAILED|DOWNLOAD FAILED|VERIFY FAILED' -or $tag -eq 'ERROR') { return 'err' }
    if ($tag -eq 'WARN') { return 'warn' }
    return $null
}
function Lzd1d2105c6d {
    if (-not $ctrl -or -not $ctrl.LstActivity) { return }
    $ctrl.LstActivity.Items.Clear()
    if ($script:ActBuf) { foreach ($r in $script:ActBuf) { if (Lzbb958b93a3 $r) { Lz43a79d8eb0 $r } } }
}
function Lz358a780544 { param([string]$F)
    $script:ActFilter = $F
    $bc = New-Object System.Windows.Media.BrushConverter
    foreach ($pair in @(@('BtnActOverview','Overview'), @('BtnActProblems','Problems'), @('BtnActFiles','Files'), @('BtnActAll','All'))) {
        $b = Lz0d86a71502 $pair[0]
        if (-not $b) { continue }
        if ($pair[1] -eq $F) { $b.Background = $bc.ConvertFromString('#0F1115'); $b.Foreground = [System.Windows.Media.Brushes]::White; $b.BorderBrush = $bc.ConvertFromString('#0F1115') }
        else { $b.Background = [System.Windows.Media.Brushes]::White; $b.Foreground = $bc.ConvertFromString('#101828'); $b.BorderBrush = $bc.ConvertFromString('#E4E7EC') }
    }
    Lzd1d2105c6d
}
function Lze9e83265bf { param([string]$State = 'RUNNING')
    if (-not $ctrl -or -not $ctrl.LstActivity) { return }
    $bc = New-Object System.Windows.Media.BrushConverter
    if ($script:ActBuf) { $script:ActBuf.Clear() }
    $ctrl.LstActivity.Items.Clear()
    if ($ctrl.ActDone)   { $ctrl.ActDone.Text = '-' }
    if ($ctrl.ActFailed) { $ctrl.ActFailed.Text = '0' }
    if ($ctrl.ActSpeed)  { $ctrl.ActSpeed.Text = '-' }
    if ($ctrl.ActBadge)  { $ctrl.ActBadge.Visibility = 'Collapsed' }
    if ($ctrl.ActState)  {
        $ctrl.ActState.Text = $State
        $ctrl.ActState.Foreground = $bc.ConvertFromString($(if ($State -eq 'RUNNING') { '#3CCB7F' } else { '#8B919A' }))
    }
    if ($ctrl.ActDot) { $ctrl.ActDot.Fill = $bc.ConvertFromString($(if ($State -eq 'RUNNING') { '#3CCB7F' } else { '#8B919A' })) }
}
function Add-EngineLine {
    param([string]$Line)
    if ($null -eq $Line) { return }
    if ($Line -match '^##STATUS##\|(.*)$') {
        $ctrl.LblStatus.Text = "$($Matches[1])"; $ctrl.Prog.IsIndeterminate = $true
        if ($Matches[1] -like 'Source:*Destination:*' -or $Matches[1] -like 'Destination:*') {
            $ctrl.ThrottleBanner.Visibility = 'Collapsed'
        }
        try {
            $paceMsg = if ($script:TransferMode -eq 'LocalFs') { 'Reading the source file list, not your connection. Speeds pick up once the list is built.' } else { 'Paced by the Datto rate limit, not your connection. Speeds pick up once the list is built.' }
            $ctrl.LblEta.Text = $paceMsg; $ctrl.LblEta.Foreground = '#1C6091'
        } catch {}
        return
    }
    if ($Line -match '^##LICENCE##\|(.*)$') {
        $script:LicenceBlocked = "$($Matches[1])".Trim()
        return
    }
    if ($Line -match '^##TAMPER##\|(.*)$') {
        $script:TamperBlocked = "$($Matches[1])".Trim()
        return
    }
    if ($Line -match '^##TRIAL##\|START\|(\d+)\|(\S+)$') {
        $script:TrialMode = $true; $script:TrialRemaining = [int]$Matches[1]; $script:TrialBucketLabel = "$($Matches[2])"
        return
    }
    if ($Line -match '^##TRIAL##\|EXHAUSTED\|(\S+)\|(\d+)$') {
        $script:TrialExhausted = $true; $script:TrialBucketLabel = "$($Matches[1])"; $script:TrialLimitDisplay = [int]$Matches[2]
        return
    }
    if ($Line -match '^##TRIAL##\|CAPPED\|(\d+)\|(\d+)$') {
        $script:TrialCapped = $true; $script:TrialLimitDisplay = [int]$Matches[1]; $script:TrialCopied = [int]$Matches[2]
        return
    }
    if ($Line -match '^##CHECKFILES##\|(\d+)\|(\d+)\|(\d+)\|(.+)$') {
        $script:CheckFiles += [pscustomobject]@{ Missing = [int]$Matches[1]; Extra = [int]$Matches[2]; Stale = [int]$Matches[3]; Path = "$($Matches[4])".Trim() }
        return
    }
    if ($Line -match '^##CHECKFILES##\|(.+)$') {
        $script:CheckFiles += [pscustomobject]@{ Missing = -1; Extra = 0; Stale = 0; Path = "$($Matches[1])".Trim() }
        return
    }
    if ($Line -match '^##CHECKOUTCOME##\|(OK|WARN|BAD)\|(.*)$') {
        $script:CheckOutcome = @{ Level = $Matches[1]; Text = "$($Matches[2])" }
        return
    }
    if ($Line -match '^##SCOPE##\|(\d+)\|(\d+)\|(\d+)$') {
        $script:ScopeTotal = [int]$Matches[2]; $script:ScopeSkipped = [int]$Matches[3]
        return
    }
    if ($Line -match '^##DATTOPACE##\|(-?\d+)\|(\d+)\|(\d+)$') {
        Lz254ae81222 -GapMs ([int]$Matches[2]) -Code ([int]$Matches[3])
        return
    }
    if ($Line -match '^##THROTTLE##\|(-?\d+)\|(\d+)\|(-?\d+)\|(\d+)(?:\|(\d+))?$') {
        $code = if ($Matches[5]) { [int]$Matches[5] } else { 0 }
        Lz6b0915b8df -Max ([int]$Matches[1]) -HardMax ([int]$Matches[2]) -PausedSeconds ([int]$Matches[3]) -Code $code
        return
    }
    if ($Line -match '^##PROGRESS##\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|([01])\|(.*)$') {
        Lzedfa63e5ff -Done ([int]$Matches[1]) -Total ([int]$Matches[2]) -BytesDone ([int64]$Matches[3]) -BytesTotal ([int64]$Matches[4]) `
            -SmallDone ([int]$Matches[5]) -SmallTotal ([int]$Matches[6]) -LargeDone ([int64]$Matches[7]) -LargeTotal ([int64]$Matches[8]) `
            -Final ([int]$Matches[9]) -CurrentName ("$($Matches[10])".Trim())
        return
    }
    if ($Line -match '^##PROGRESS##\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(.*)$') {
        Lzedfa63e5ff -Done ([int]$Matches[1]) -Total ([int]$Matches[2]) -BytesDone ([int64]$Matches[3]) -BytesTotal ([int64]$Matches[4]) `
            -SmallDone 0 -SmallTotal 0 -LargeDone 0 -LargeTotal 0 -Final 1 -CurrentName ("$($Matches[5])".Trim())
        return
    }
    if ($Line -match 'source \[(.+?)\] -> destination') { Lz5d21d200c7 $Matches[1] 'In progress' }
    if ($Line -match '\]\s+(.+?): copied \d+, skipped \d+, failed (\d+), failed verification (\d+)') {
        $st = if ((([int]$Matches[2]) + ([int]$Matches[3])) -gt 0) { 'Errors' } else { 'Completed' }
        Lz5d21d200c7 $Matches[1].Trim() $st
    }
    if ((Lz1ad19acf41 $Line) -in @('err', 'warn')) {
        if ($null -eq $script:RunIssues) { $script:RunIssues = 0 }
        $script:RunIssues++
        try { $ctrl.LblIssues.Text = "$($script:RunIssues) file(s) had a problem - see the report"; $ctrl.IssuesChip.Visibility = 'Visible' } catch {}
        try {
            if ($ctrl.ActFailed) { $ctrl.ActFailed.Text = "$($script:RunIssues)" }
            if ($ctrl.ActBadgeText) { $ctrl.ActBadgeText.Text = "$($script:RunIssues)" }
            if ($ctrl.ActBadge) { $ctrl.ActBadge.Visibility = 'Visible' }
        } catch {}
    }
    Lz684763ee8e $Line
    $ctrl.TxtLog.AppendText((Lz97ede984b1 $Line) + "`r`n")
    if ($null -eq $script:LogLines) { $script:LogLines = 0 }
    $script:LogLines++
    if ($script:LogLines -ge 8000) {
        try {
            $keep = (($ctrl.TxtLog.Text -split "`n") | Select-Object -Last 4000) -join "`n"
            $ctrl.TxtLog.Text = "[earlier lines trimmed from view to keep the window responsive; the full log is on disk via 'Open log']`r`n" + $keep
            $script:LogLines = 4000
        } catch {}
    }
    $ctrl.TxtLog.ScrollToEnd()
}
function Lz97ede984b1 {
    param([string]$Line)
    if ($Line -match '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2}|Z)?)\s+(.*)$') {
        try { $dt = [datetimeoffset]::Parse($Matches[1]); return ($dt.DateTime.ToString('dd MMM HH:mm:ss') + '  ' + $Matches[2]) } catch { return $Line }
    }
    return $Line
}
function Lzf47c317f43 { param([string]$Text) Add-EngineLine $Text }
function Lz606d7bc37e {
    if (-not $script:Cfg) { return '' }
    $u = $script:Cfg.destination.defaultSiteUrl
    if ($u) { return "$u".TrimEnd('/') }
    return "$($script:Cfg.destination.teamSiteBaseUrl.TrimEnd('/'))/projects"
}
function Lzbe1249510c {
    if (-not $script:Cfg) { return '' }
    $d = $script:Cfg.destination.oneDriveUpnDomain
    if ($d) { return "$d" } else { return '' }
}
function Set-Busy {
    param([bool]$On, [string]$Text)
    if ($On) {
        if ($Text) { $ctrl.LblStatus.Text = $Text }
        $win.Cursor = [System.Windows.Input.Cursors]::Wait
    } else {
        $win.Cursor = $null
        $ctrl.LblStatus.Text = ''
    }
    $win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
}
function Set-DestModeUI {
    if ($ctrl.RbOneDrive.IsChecked) {
        $ctrl.LblLoc.Text = 'Microsoft 365 user:'
        $dom = Lzbe1249510c; $ctrl.TxtLocHint.Text = 'yourname' + $(if ($dom) { $dom } else { '@yourcompany.ie' })
        $ctrl.RowLib.Visibility = 'Collapsed'
        if ($ctrl.BtnFindSite) { $ctrl.BtnFindSite.Visibility = 'Collapsed' }
    } elseif ($ctrl.RbSkip.IsChecked) {
        $ctrl.LblLoc.Text = '(skipped)'
        $ctrl.TxtLocHint.Text = ''
        $ctrl.RowLib.Visibility = 'Collapsed'
        if ($ctrl.BtnFindSite) { $ctrl.BtnFindSite.Visibility = 'Collapsed' }
    } else {
        $ctrl.LblLoc.Text = 'Site URL:'
        $ctrl.TxtLocHint.Text = 'https://yourtenant.sharepoint.com/sites/...'
        $ctrl.RowLib.Visibility = 'Visible'
        if ($ctrl.BtnFindSite) { $ctrl.BtnFindSite.Visibility = 'Visible' }
    }
}
if ($ctrl.BtnFindSite) { $ctrl.BtnFindSite.Add_Click({
    if (-not $script:JobOpen) { (Show-Msg -Text ('Open or create a migration job first.') -Caption ('Find site')); return }
    try {
        Set-Busy $true 'Connecting to Microsoft 365...'
        Lz7758da3d39
    } catch {
        (Show-Msg -Text ("Could not sign in to Microsoft 365, so the sites cannot be listed.`n`nTechnical detail: $($_.Exception.Message)") -Caption ('Find site'))
        Set-Busy $false; return
    } finally { Set-Busy $false }
    $seed = "$($ctrl.TxtLoc.Text)".Trim()
    if ($seed -match '://') { $seed = '' }
    $picked = Lzab148c6c37 -StartSearch $seed
    if ($picked) {
        $ctrl.TxtLoc.Text = $picked
        $ctrl.TxtLib.Text = ''; $ctrl.TxtFolder.Text = ''
        $ctrl.LblCheck.Text = "Site set. Click Browse beside Library to pick one."
        $ctrl.LblCheck.Foreground = 'Green'
        Lz5af601c665 "Site set to $picked"
        Update-DestPreview
    }
}) }
$ctrl.RbSite.Add_Checked({
    Set-DestModeUI
    if ($script:Cfg -and ($ctrl.TxtLoc.Text -notmatch '://')) { $ctrl.TxtLoc.Text = Lz606d7bc37e }
    Update-DestPreview
})
$ctrl.RbOneDrive.Add_Checked({
    Set-DestModeUI
    if ($script:Cfg -and (($ctrl.TxtLoc.Text -match '://') -or (-not $ctrl.TxtLoc.Text.Trim()))) { $ctrl.TxtLoc.Text = '' }
    Update-DestPreview
})
$ctrl.RbSkip.Add_Checked({ Set-DestModeUI; Update-DestPreview })
$ctrl.TxtFolder.Add_TextChanged({ Update-DestPreview })
if ($ctrl.LstSource) { $ctrl.LstSource.Add_SelectionChanged({ Update-SourceUi }) }
if ($ctrl.ChkSrcContents) { $ctrl.ChkSrcContents.Add_Checked({ Update-DestPreview }); $ctrl.ChkSrcContents.Add_Unchecked({ Update-DestPreview }) }
if ($ctrl.BtnShowFiles) { $ctrl.BtnShowFiles.Add_Click({ Lz046b4e4e82 -Paths @(@($script:CheckFiles) | ForEach-Object { "$($_.Path)" }) }) }
$ctrl.TxtFolder.Add_LostFocus({ Lz48158eb74f })
$ctrl.TxtLoc.Add_TextChanged({ Update-DestPreview })
$ctrl.TxtLib.Add_TextChanged({ Update-DestPreview })
$script:NestSuspend = $false
function Lz4938be536b {
    if ($script:NestSuspend) { return }
    if (-not $script:JobOpen -or -not $script:ConfigPath) { return }
    try {
        $cfg = Read-ConfigJson $script:ConfigPath
        Lzcb55b64c1a -Cfg $cfg -Path 'destination.nestUnderProjectFolder' -Value ([bool]$ctrl.ChkNest.IsChecked)
        Write-ConfigJson -Cfg $cfg -Path $script:ConfigPath
        try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch { }
        Lz5af601c665 $(if ($ctrl.ChkNest.IsChecked) {
            "Each project will go into its own folder at the destination."
        } else {
            "Files will go straight into the destination folder, with no project folder added."
        })
    } catch { (Show-Msg -Text ("Could not save that setting.`n`nTechnical detail: $($_.Exception.Message)")) }
    Update-DestPreview
}
$ctrl.ChkNest.Add_Checked({ Lz4938be536b })
$ctrl.ChkNest.Add_Unchecked({ Lz4938be536b })
$script:ProjectRows = @()
$script:RunStatus = @{}
function Lzad1fa0b425 {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($p in $script:Projects) {
        $dest = ''; $status = 'Not set'
        if ($script:Map.ContainsKey($p.Id)) {
            $d = $script:Map[$p.Id]
            if ($d.DestinationType -eq 'OneDrive') { $dest = "OneDrive: $($d.TargetPrincipal)"; $status = 'Ready' }
            elseif ($d.DestinationType -eq 'SharePoint') { $dest = "SharePoint: $($d.DestinationUrl)"; $status = 'Ready' }
            else { $dest = '(skip)'; $status = 'Skip' }
            if ($d.ContainsKey('SourceSubPath') -and "$($d.SourceSubPath)".Trim()) {
                $coMark = if ($d.ContainsKey('SourceContentsOnly') -and "$($d.SourceContentsOnly)" -match '^(?i)true') { ' (contents only)' } else { '' }
                $dest = "$dest  [source: /$($d.SourceSubPath)$coMark]"
            }
        }
        if ($script:RunStatus.ContainsKey($p.Name)) { $status = $script:RunStatus[$p.Name] }
        $rows.Add([pscustomobject]@{ Id = $p.Id; Name = $p.Name; Destination = $dest; Status = $status })
    }
    $script:ProjectRows = $rows
}
function Lz5d21d200c7 {
    param([string]$Name, [string]$Status)
    $n = "$Name".Trim(); if (-not $n) { return }
    $script:RunStatus[$n] = $Status
    $changed = $false
    foreach ($r in $script:ProjectRows) { if ($r.Name -eq $n) { $r.Status = $Status; $changed = $true } }
    if ($changed) { try { $ctrl.LstProjects.Items.Refresh() } catch {} }
}
function Lzb130494444 {
    $q = "$($ctrl.TxtFilter.Text)".Trim()
    $selIds = @(); foreach ($si in $ctrl.LstProjects.SelectedItems) { $selIds += $si.Id }
    $view = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($r in $script:ProjectRows) {
        if (-not $q -or $r.Name -like "*$q*" -or $r.Destination -like "*$q*") { [void]$view.Add($r) }
    }
    $ctrl.LstProjects.ItemsSource = $view
    if ($selIds.Count) {
        foreach ($r in $view) { if ($selIds -contains $r.Id) { [void]$ctrl.LstProjects.SelectedItems.Add($r) } }
    }
    if ($ctrl.TxtFilterHint) { $ctrl.TxtFilterHint.Visibility = if ($q) { 'Collapsed' } else { 'Visible' } }
}
function Lzc219beec58 {
    Lzad1fa0b425
    Lzb130494444
    $hasProjects = $false
    foreach ($p in $script:Projects) { $hasProjects = $true; break }
    $ctrl.GettingStarted.Visibility = if ($hasProjects) { 'Collapsed' } else { 'Visible' }
    if (-not $hasProjects) {
        $sd = $false
        if (Get-Command Test-ConnectionConfigured -ErrorAction SilentlyContinue) { try { $sd = [bool](Lzb6cc704a5f) } catch {} }
        Lz154ffece7e $sd
    }
}
function Get-SelectedProject {
    $sel = $ctrl.LstProjects.SelectedItem
    if (-not $sel) { return $null }
    return @($script:Projects | Where-Object { $_.Id -eq $sel.Id }) | Select-Object -First 1
}
function Lz802cd60b97 {
    param([string]$Id)
    if (-not $Id -or -not $ctrl.LstProjects) { return }
    try {
        $ctrl.LstProjects.SelectedItems.Clear()
        foreach ($r in $ctrl.LstProjects.Items) {
            if ("$($r.Id)" -eq "$Id") { [void]$ctrl.LstProjects.SelectedItems.Add($r); $ctrl.LstProjects.ScrollIntoView($r); break }
        }
    } catch {}
}
function Lz6d0d60c1fc {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($sel in $ctrl.LstProjects.SelectedItems) {
        $sid = $sel.Id
        foreach ($p in $script:Projects) { if ($p.Id -eq $sid) { [void]$out.Add($p); break } }
    }
    return ,$out.ToArray()
}
$script:ActionButtons = @('BtnConnect','BtnAddFolder','BtnRemoveFolder','BtnPreflight','BtnDryRun','BtnTransfer','BtnDelta','BtnRerunFailed','BtnValidate','BtnSizeCheck')
function Lz1c082b7bc8 {
    $bad = New-Object System.Collections.Generic.List[string]
    if ($script:TransferMode -eq 'LocalFs') {
        foreach ($p in $script:Projects) {
            if (-not $script:Map.ContainsKey($p.Id)) { continue }
            if (-not (Test-Path -LiteralPath $p.Id -PathType Container)) {
                $bad.Add("$($p.Name):`n  The folder '$($p.Id)' could not be opened. Check the drive or network share is connected and you have permission to read it.")
            }
        }
        if ($bad.Count) {
            (Show-Msg -Text (("Nothing has run. The following source folder(s) are not reachable, so the run was stopped before it started." + "`n`n" + ($bad -join "`n`n"))) -Caption ('Source folder not reachable') -Buttons ('OK') -Icon ('Warning')) | Out-Null
            return $false
        }
        return $true
    }
    foreach ($p in $script:Projects) {
        if (-not $script:Map.ContainsKey($p.Id)) { continue }
        $d = $script:Map[$p.Id]
        $sub = ''; if ($d.ContainsKey('SourceSubPath')) { $sub = "$($d.SourceSubPath)".Trim().Trim('/').Trim('\') }
        if (-not $sub) { continue }
        try { [void](Lzc7583c6c9b -ProjectId $p.Id -SubPath $sub) }
        catch { $bad.Add("$($p.Name):`n  $($_.Exception.Message)") }
    }
    if ($bad.Count) {
        (Show-Msg -Text (("Nothing has run. The source subfolder for the following was not found in Datto, so the run was stopped before it started. Fix each one with Browse or Test, click 'Apply to this project', then run again." + "`n`n" + ($bad -join "`n`n"))) -Caption ('Source folder not found') -Buttons ('OK') -Icon ('Warning')) | Out-Null
        return $false
    }
    return $true
}
function Lzd129cde1e6 {
    param([switch]$WarnOnly)
    $bad = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $needGraph = @($script:Projects | Where-Object { $script:Map.ContainsKey($_.Id) -and (@('OneDrive','SharePoint') -contains $script:Map[$_.Id].DestinationType) }).Count -gt 0
    if ($needGraph) {
        try { [void](Lz9fe56e4482) }
        catch {
            if ($WarnOnly) {
                (Show-Msg -Text ("The destination could not be checked because Microsoft 365 sign-in failed: " + $_.Exception.Message + "`n`nThis check reads only the source, so it will still run. Fix the sign-in before a real upload.") -Caption ('Destination not checked') -Buttons ('OK') -Icon ('Warning')) | Out-Null
                return $true
            }
            (Show-Msg -Text ("Nothing has run. " + $_.Exception.Message) -Caption ('Cannot sign in to Microsoft 365') -Buttons ('OK') -Icon ('Error')) | Out-Null
            return $false
        }
    }
    foreach ($p in $script:Projects) {
        if (-not $script:Map.ContainsKey($p.Id)) { continue }
        $d = $script:Map[$p.Id]
        if ($d.DestinationType -eq 'OneDrive') {
            $upn = "$($d.TargetPrincipal)".Trim()
            if (-not $upn) { continue }
            $key = "od:$($upn.ToLower())"
            if ($seen.ContainsKey($key)) { if ($seen[$key]) { $bad.Add("$($p.Name):`n  $($seen[$key])") }; continue }
            $seen[$key] = ''
            try {
                $drv = Lz7287a65440 -Path "users/$([uri]::EscapeDataString($upn))/drive"
                if (-not $drv) { throw 'no drive returned' }
            } catch {
                $seen[$key] = "OneDrive not found for '$upn'. Check the address is spelled correctly, the user has a Microsoft 365 licence, and they have opened their OneDrive at least once."
                $bad.Add("$($p.Name):`n  $($seen[$key])")
            }
        } elseif ($d.DestinationType -eq 'SharePoint') {
            $url = "$($d.DestinationUrl)".Trim(); $lib = "$($d.TargetLibrary)".Trim()
            if (-not $url) { continue }
            $key = "sp:$($url.ToLower())|$($lib.ToLower())"
            if ($seen.ContainsKey($key)) { if ($seen[$key]) { $bad.Add("$($p.Name):`n  $($seen[$key])") }; continue }
            $seen[$key] = ''
            try {
                $libs = Lzc92872bdd0 -Url $url
                if ($null -eq $libs) { throw "the site '$url' was not found. Check the URL." }
                if ($lib -and (@($libs) -notcontains $lib)) { throw "the site is fine, but it has no library called '$lib' (it has: $(@($libs) -join ', '))." }
            } catch {
                $seen[$key] = "$($_.Exception.Message)"
                $bad.Add("$($p.Name):`n  $($seen[$key])")
            }
        }
    }
    if ($bad.Count) {
        if ($WarnOnly) {
            (Show-Msg -Text (("This check reads only the source, so it will still run. But the DESTINATION for the following is NOT reachable, and a real upload would fail until it is fixed (the mapping panel's 'Test' or 'Check destination' button tests a fix instantly):" + "`n`n" + ($bad -join "`n`n"))) -Caption ('Destination not reachable') -Buttons ('OK') -Icon ('Warning')) | Out-Null
            return $true
        }
        (Show-Msg -Text (("Nothing has run. The DESTINATION for the following could not be opened, so the run was stopped before it started. Fix each one (the mapping panel's 'Check destination' button tests a fix instantly), click 'Apply to this $($script:NItem)', then run again." + "`n`n" + ($bad -join "`n`n"))) -Caption ('Destination not reachable') -Buttons ('OK') -Icon ('Warning')) | Out-Null
        return $false
    }
    return $true
}
function Lzb1483e070e {
    param([string[]] $EngineArgs, [string] $Label, [scriptblock] $OnComplete)
    $script:OnEngineComplete = $OnComplete
    if (-not $script:JobOpen) { (Show-Msg -Text ('Open or create a migration job first (New or Open, top left). Everything runs inside a job so its logs and reports stay together.')); return }
    if (-not (Test-Path $script:EnginePath)) { (Show-Msg -Text ("Engine not found: $($script:EnginePath)")); return }
    $ctrl.Prog.IsIndeterminate = $false; $ctrl.Prog.Value = 0
    $ctrl.RunSummaryBanner.Visibility = 'Collapsed'; $ctrl.ThrottleBanner.Visibility = 'Collapsed'
    $ctrl.IssuesChip.Visibility = 'Collapsed'
    if (($EngineArgs -contains 'Transfer') -or ($EngineArgs -contains 'Validate') -or ($EngineArgs -contains 'SizeCheck') -or ($EngineArgs -contains 'PreFlight')) {
        $mappedCount = @($script:Projects | Where-Object { $script:Map.ContainsKey($_.Id) }).Count
        if ($mappedCount -eq 0) {
            (Show-Msg -Text ("Nothing has run. No $($script:NItem) has a destination set yet, so there is nothing to copy or check." + [Environment]::NewLine + [Environment]::NewLine + "On the left, select a $($script:NItem). On the right, choose where its files should go, then click 'Apply to this $($script:NItem)'. Repeat for each $($script:NItem) you want to copy, then run again.") -Caption ('Set a destination first') -Icon ('Warning')) | Out-Null
            return
        }
    }
    if (($EngineArgs -contains 'Transfer') -or ($EngineArgs -contains 'Validate') -or ($EngineArgs -contains 'SizeCheck') -or ($EngineArgs -contains 'PreFlight')) {
        try { Set-Busy $true 'Checking source folders...'; $srcOk = Lz1c082b7bc8 } finally { Set-Busy $false }
        if (-not $srcOk) { return }
    }
    if (($EngineArgs -contains '-Execute') -or ($EngineArgs -contains 'Validate') -or ($EngineArgs -contains 'SizeCheck')) {
        try { Set-Busy $true 'Checking destinations...'; $dstOk = Lzd129cde1e6 } finally { Set-Busy $false }
        if (-not $dstOk) { return }
    }
    elseif (($EngineArgs -contains 'PreFlight') -or ($EngineArgs -contains 'Transfer')) {
        try { Set-Busy $true 'Checking destinations...'; [void](Lzd129cde1e6 -WarnOnly) } finally { Set-Busy $false }
    }
    try { $script:OutFile = [System.IO.Path]::GetTempFileName() }
    catch {
        (Show-Msg -Text ("Nothing has run. Could not create a staging file for this run's log: " + $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + "Check the system Temp location is available (Disk Management, or restart this computer if it was recently changed), then try again.") -Caption ('Could not start this run') -Buttons ('OK') -Icon ('Error')) | Out-Null
        return
    }
    $script:LogPos = 0
    $script:CurLabel = $Label
    $script:ReportBefore = [datetime]::MinValue
    try {
        $rrPrev = Lz675256916c
        if ($rrPrev) { $rbNewest = Get-ChildItem (Join-Path $rrPrev 'report-*.html') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($rbNewest) { $script:ReportBefore = $rbNewest.LastWriteTime } }
    } catch {}
    $script:LastRunArgs = @($EngineArgs)
    $script:LastRunLabel = $Label
    $script:Partial = ''
    $script:RunStart = Get-Date
    $script:SpinIdx = 0
    $script:RunIssues = 0; $script:ProgLastBytes = 0; $script:ProgLastTime = $null
    $script:EtaSamples = New-Object System.Collections.ArrayList; $script:EtaShownOnce = $false
    $ctrl.TxtLog.Clear(); $ctrl.LblEta.Text = ''; $ctrl.LblElapsed.Text = 'Elapsed 0m 00s'; $ctrl.Prog.Value = 0; $ctrl.LblStatus.Text = 'starting...'
    $ctrl.LblCurrent.Text = ''; $ctrl.LblSpeed.Text = ''; $ctrl.IssuesChip.Visibility = 'Collapsed'
    $script:ThrM365 = ''; $script:ThrDatto = ''
    $script:ScopeTotal = 0; $script:ScopeSkipped = 0; $script:CheckOutcome = $null; $script:LicenceBlocked = $null; $script:TamperBlocked = $null
    $script:TrialMode = $false; $script:TrialCapped = $false; $script:TrialCopied = 0
    $script:TrialExhausted = $false; $script:TrialRemaining = 0; $script:TrialBucketLabel = ''
    $script:CheckFiles = @()
    if ($ctrl.BtnShowFiles) { $ctrl.BtnShowFiles.Visibility = 'Collapsed' }
    $ctrl.ThrottleBanner.Visibility = 'Collapsed'; $ctrl.RunSummaryBanner.Visibility = 'Collapsed'
    if ($Label -in @('Full migration','Sync new and changed')) {
        $script:RunStatus = @{}
        foreach ($p in $script:Projects) { if ($script:Map.ContainsKey($p.Id)) { $script:RunStatus[$p.Name] = 'Queued' } }
        Lzc219beec58
    }
    $extra = @('-GuiMode','-VerboseFiles')
    $engArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $script:EnginePath, '-ConfigPath', $script:ConfigPath) + $EngineArgs + $extra
    Lz5af601c665 "$Label running..."
    $ctrl.Prog.IsIndeterminate = $true
    $script:ActionButtons | ForEach-Object { $ctrl[$_].IsEnabled = $false }
    $script:Stopping = $false
    $script:QuietPausing = $false
    $script:Paused = $false
    $ctrl.BtnStop.Visibility = 'Visible'
    if ($ctrl.BtnPause) { $ctrl.BtnPause.Visibility = 'Visible' }
    if ($ctrl.StatusPulse) { $ctrl.StatusPulse.Visibility = 'Visible' }
    try { Lze9e83265bf -State 'RUNNING'; Lz103dfbf0f4 } catch {}
    Lzbeaeeec3a0 $true
    try { Lz684763ee8e '[INFO] This computer will stay awake until the run finishes (sleep is paused, the display may still turn off).' } catch {}
    $ctrl.BtnStop.IsEnabled = $true
    if ($ctrl.BtnPause) {
        $ctrl.BtnPause.IsEnabled = $false
        $ctrl.BtnPauseTitle.Text = 'Pause'
        if ($ctrl.BtnPauseDesc) { $ctrl.BtnPauseDesc.Text = 'Available once files start moving.' }
    }
    Add-EngineLine "----- $Label -----"
    try {
        $script:Proc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $engArgs -PassThru -NoNewWindow -RedirectStandardOutput $script:OutFile -RedirectStandardError "$($script:OutFile).err"
    } catch {
        $ctrl.Prog.IsIndeterminate = $false
        $script:ActionButtons | ForEach-Object { $ctrl[$_].IsEnabled = $true }
        $ctrl.BtnStop.Visibility = 'Collapsed'; $ctrl.BtnStop.IsEnabled = $false
        if ($ctrl.BtnPause) { $ctrl.BtnPause.Visibility = 'Collapsed' }
        if ($ctrl.StatusPulse) { $ctrl.StatusPulse.Visibility = 'Collapsed'; $ctrl.StatusPulse.Opacity = 1.0 }
        Lzbeaeeec3a0 $false
        Lz5af601c665 "$Label could not start."
        (Show-Msg -Text ("Nothing has run. Could not start the engine process: " + $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + "Check the system Temp location is available (Disk Management, or restart this computer if it was recently changed), then try again.") -Caption ('Could not start this run') -Buttons ('OK') -Icon ('Error')) | Out-Null
        return
    }
    $script:Timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:Timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:Timer.Add_Tick({
        try {
            if (Test-Path $script:OutFile) {
                $fs = [System.IO.File]::Open($script:OutFile,'Open','Read','ReadWrite')
                $fs.Seek($script:LogPos,'Begin') | Out-Null
                $sr = New-Object System.IO.StreamReader($fs)
                $chunk = $sr.ReadToEnd(); $script:LogPos = $fs.Position
                $sr.Close(); $fs.Close()
                if ($chunk) {
                    $text = $script:Partial + $chunk
                    $lines = $text -split "`r?`n"
                    $script:Partial = $lines[-1]
                    for ($k = 0; $k -lt $lines.Count - 1; $k++) { try { Add-EngineLine $lines[$k] } catch {} }
                }
            }
        } catch {}
        $script:SpinIdx = ($script:SpinIdx + 1) % 4
        $spin = @('|','/','-','\')[$script:SpinIdx]
        $ctrl.LblElapsed.Text = "$spin  Elapsed " + (Format-Span ((Get-Date) - $script:RunStart))
        if ($ctrl.StatusPulse) { $ctrl.StatusPulse.Opacity = @(1.0,0.75,0.45,0.75)[$script:SpinIdx] }
        if ($script:Proc.HasExited) {
            $script:Timer.Stop()
            if ($script:Partial) { Add-EngineLine $script:Partial; $script:Partial = '' }
            $errFile = "$($script:OutFile).err"
            if (Test-Path $errFile) { $e = Get-Content $errFile -Raw; if ($e) { Add-EngineLine $e } }
            $ctrl.Prog.IsIndeterminate = $false; $ctrl.Prog.Value = 100
            $ctrl.LblElapsed.Text = 'Elapsed ' + (Format-Span ((Get-Date) - $script:RunStart))
            $ctrl.LblEta.Text = ''
            $oc = $null
            try {
                $ocPath = Join-Path (Lz675256916c) 'lastrun-outcome.json'
                if ((Test-Path $ocPath) -and ((Get-Item $ocPath).LastWriteTime -ge $script:RunStart.AddSeconds(-5))) {
                    $oc = Get-Content $ocPath -Raw | ConvertFrom-Json
                }
            } catch {}
            $sev = 'ok'
            if ($script:TamperBlocked) {
                $plainOutcome = 'did not run: this installation looks modified or damaged. Nothing was changed.'; $sev = 'bad'
                (Show-Msg -Text ($script:TamperBlocked) -Caption ('Installation problem') -Icon ('Error')) | Out-Null
            }
            elseif ($script:TrialExhausted) {
                $plainOutcome = "did not run: this tenant's free evaluation is used up. Nothing was copied and nothing was changed. See the licence window for how to migrate everything."
                $sev = 'warn'
                Lz5e54cee147
            }
            elseif ($script:LicenceBlocked -and ("$($script:LicenceBlocked)" -match '(?i)revok')) {
                $plainOutcome = "did not run: this licence has been revoked. Nothing was changed."
                $sev = 'warn'
                (Show-Msg -Text ("This licence has been revoked, so this step cannot run." + [Environment]::NewLine + [Environment]::NewLine + "Please contact support@liscaragh.com to sort it out. Nothing on this computer was changed.") -Caption ('Licence revoked') -Icon ('Warning')) | Out-Null
            }
            elseif ($script:LicenceBlocked) {
                $plainOutcome = "needs a licence for this Microsoft 365 tenant. Nothing was changed. See the licence window for how to get one."
                $sev = 'warn'
                $detail = if ("$($script:LicenceBlocked)" -match 'different|cannot be moved|another') { "About this run: $($script:LicenceBlocked)" } else { '' }
                Lz412c2d92aa -Detail $detail
            }
            elseif ($script:QuietPausing) {
                $plainOutcome = 'paused for quiet hours. Files already uploaded are kept, and it will resume automatically as a Sync at the next window while this app stays open.'; $sev = 'warn'
            } elseif ($script:Paused) {
                $plainOutcome = 'paused. Files already uploaded are kept. Click Resume to carry on from where it stopped.'; $sev = 'warn'
            } elseif ($script:Stopping) {
                $plainOutcome = 'stopped by you. Files already uploaded are kept; carry on later with ''Sync new and changed''.'; $sev = 'warn'
            } elseif ($oc) {
                $ocErr = ([int]$oc.Failed + [int]$oc.VerifyFail)
                switch ("$($oc.Status)") {
                    'COMPLETED'             {
                        $doneTxt = ''
                        try {
                            if ([int]$oc.Skipped -gt 0) {
                                $doneTxt = " A further $([int]$oc.Skipped) file(s) were already there and were left alone, so all $([int]$oc.ProcessedFiles) file(s) in this $($script:NItem) are now at the destination."
                            }
                        } catch {}
                        $plainOutcome = "completed. Uploaded $($oc.Copied) file(s) ($($oc.BytesText)), 0 failures, in $(ConvertTo-FriendlyDuration $oc.ElapsedText) of copying.$doneTxt"; $sev = 'ok'
                    }
                    'COMPLETED_WITH_ERRORS' { $plainOutcome = "completed, but $ocErr file(s) did not upload or verify. Click 'Sync new and changed' to retry just those."; $sev = 'warn' }
                    'CANCELLED'             { $plainOutcome = "cancelled. Uploaded $($oc.Copied) file(s) ($($oc.BytesText)) before stopping; those are kept. Click 'Sync new and changed' to carry on from where it stopped."; $sev = 'warn' }
                    'INCOMPLETE'            { $plainOutcome = "did not finish (a crash, forced close, or power loss). $($oc.Copied) file(s) were recorded as uploaded. Click 'Sync new and changed' to continue and confirm."; $sev = 'bad' }
                    'ENDED_EARLY'           { $plainOutcome = "ENDED EARLY - it did NOT finish. Uploaded $($oc.Copied) of about $($oc.ExpectedFiles) file(s) before stopping. Reason: $($oc.Reason). Click 'Sync new and changed' to carry on from where it stopped."; $sev = 'bad' }
                    default                 { $plainOutcome = "finished - see the report for detail."; $sev = 'warn' }
                }
            } elseif ($script:CheckOutcome -and $script:Proc.ExitCode -eq 0) {
                $plainOutcome = "$($script:CheckOutcome.Text)"
                $sev = switch ("$($script:CheckOutcome.Level)") { 'BAD' { 'bad' } 'WARN' { 'warn' } default { 'ok' } }
            } elseif ($script:Proc.ExitCode -eq 0) { $plainOutcome = 'finished successfully'; $sev = 'ok' }
            else { $plainOutcome = "did not finish cleanly (see the log below). Technical exit code: $($script:Proc.ExitCode)"; $sev = 'bad' }
            if ($script:TrialCapped) {
                $plainOutcome = "evaluation copy complete. $($script:TrialCopied) file(s) were copied for real into this tenant and are ready to verify. This was a sample - licence the tenant to migrate the rest."
                $sev = 'warn'
                Lz1d511668f8 -Copied $script:TrialCopied
            }
            if ($script:Paused) { Add-EngineLine "----- Paused. What had already uploaded and verified is saved. Click Resume to carry on. -----" }
            elseif ($script:Stopping) { Add-EngineLine "----- Stopped. What had already uploaded and verified is saved. Click 'Sync new and changed' to carry on. -----" }
            $stripWord = switch ($sev) { 'ok' { 'finished' } 'warn' { 'finished, with notes' } default { 'finished, with problems' } }
            Lz5af601c665 ("$($script:CurLabel) $stripWord - the verdict is in the summary below.")
            $ctrl.ThrottleBanner.Visibility = 'Collapsed'
            $ctrl.BtnStop.IsEnabled = $false
            if ($ctrl.BtnPause) {
                if ($script:Paused) {
                    $ctrl.BtnPause.IsEnabled = $true; $ctrl.BtnPauseTitle.Text = 'Resume'
                    if ($ctrl.BtnPauseDesc) { $ctrl.BtnPauseDesc.Text = 'Carry on from where it stopped.' }
                } else {
                    $ctrl.BtnPause.IsEnabled = $false; $ctrl.BtnPauseTitle.Text = 'Pause'
                    if ($ctrl.BtnPauseDesc) { $ctrl.BtnPauseDesc.Text = 'Available once files start moving.' }
                }
            }
            if (-not $script:Paused) {
                $ctrl.BtnStop.Visibility = 'Collapsed'
                if ($ctrl.BtnPause) { $ctrl.BtnPause.Visibility = 'Collapsed' }
            }
            if ($ctrl.StatusPulse -and -not $script:Paused) { $ctrl.StatusPulse.Visibility = 'Collapsed'; $ctrl.StatusPulse.Opacity = 1.0 }
            Lzbeaeeec3a0 $false
            try { if ($ctrl.ActState) { $ctrl.ActState.Text = 'FINISHED'; $bcA = New-Object System.Windows.Media.BrushConverter; $ctrl.ActState.Foreground = $bcA.ConvertFromString('#8B919A'); if ($ctrl.ActDot) { $ctrl.ActDot.Fill = $bcA.ConvertFromString('#8B919A') } } } catch {}
            $script:ActionButtons | ForEach-Object { $ctrl[$_].IsEnabled = $true }
            Lz4ed508442b
            if (-not $script:Paused) { Lzb0111e4fe8 -Severity $sev }
            if ($script:RunStatus.Count) { try { Lzc219beec58 } catch {} }
            try {
                $txt = "$($ctrl.TxtLog.Text)"
                $finish = ([regex]::Match($txt, '(?m)^.*?\](?:\s+)((?:Transfer|Preview|Upload|Sync|DRY-RUN).*finished.*|.*(?:WOULD|would) copy.*)$')).Groups[1].Value
                $limit  = ([regex]::Match($txt, '(?m)What limited this run:\s*(.+)$')).Groups[1].Value
                $parts = @("$($script:CurLabel) $plainOutcome")
                if ($finish) { $parts += ($finish.Trim() -replace '\s+Backoff.*$','') }
                if ($limit)  { $parts += "What limited it: $($limit.Trim())" }
                $ctrl.LblRunSummary.Text = ($parts -join "`n")
                switch ($sev) {
                    'bad'  { $ctrl.RunSummaryBanner.Background = '#FEF3F2'; $ctrl.RunSummaryBanner.BorderBrush = '#FDA29B'; $ctrl.LblRunSummary.Foreground = '#B42318' }
                    'warn' { $ctrl.RunSummaryBanner.Background = '#FFFAEB'; $ctrl.RunSummaryBanner.BorderBrush = '#FEDF89'; $ctrl.LblRunSummary.Foreground = '#B5460F' }
                    default{ $ctrl.RunSummaryBanner.Background = '#E7F7EF'; $ctrl.RunSummaryBanner.BorderBrush = '#A6E9C5'; $ctrl.LblRunSummary.Foreground = '#066A4B' }
                }
                $ctrl.RunSummaryBanner.Visibility = 'Visible'
                if ($ctrl.BtnShowFiles) {
                    $show = (@($script:CheckFiles).Count -gt 0 -and $sev -ne 'ok')
                    $ctrl.BtnShowFiles.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
                    if ($show) {
                        $m = 0; $x = 0; $st = 0; $unknown = $false
                        foreach ($cf in @($script:CheckFiles)) {
                            if ([int]$cf.Missing -lt 0) { $unknown = $true }
                            else { $m += [int]$cf.Missing; $x += [int]$cf.Extra; $st += [int]$cf.Stale }
                        }
                        $ctrl.BtnShowFiles.Content =
                            if ($unknown)     { 'Show files' }
                            elseif (@(@($m,$st,$x) | Where-Object { $_ -gt 0 }).Count -gt 1)
                                              { "Show differences ($('{0:N0}' -f ($m+$st+$x)))" }
                            elseif ($m -gt 0) { "Show missing files ($('{0:N0}' -f $m))" }
                            elseif ($st -gt 0){ "Show out-of-date files ($('{0:N0}' -f $st))" }
                            elseif ($x -gt 0) { "Show extra files ($('{0:N0}' -f $x))" }
                            else              { 'Show files' }
                    }
                }
            } catch {}
            try {
                $newest = Get-ChildItem (Join-Path (Lz675256916c) 'report-*.html') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($newest -and $newest.LastWriteTime -gt $script:ReportBefore) { Start-Process $newest.FullName }
            } catch {}
            Remove-Item $script:OutFile, $errFile -ErrorAction SilentlyContinue
            if ($script:OnEngineComplete) { $cb = $script:OnEngineComplete; $script:OnEngineComplete = $null; try { & $cb } catch { (Show-Msg -Text ("Post-run step failed: $($_.Exception.Message)")) } }
        }
    })
    $script:Timer.Start()
}
function New-DialogHeader {
    param([string]$Title, [string]$Subtitle)
    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = '#0F1115'; $hdr.Padding = '20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
    $ht = New-Object System.Windows.Controls.TextBlock
    $ht.Text = $Title; $ht.Foreground = 'White'; $ht.FontSize = 16; $ht.FontWeight = 'SemiBold'
    if ($Subtitle) {
        $hs = New-Object System.Windows.Controls.StackPanel
        $hb = New-Object System.Windows.Controls.TextBlock
        $hb.Text = $Subtitle; $hb.Foreground = '#9BA1AA'; $hb.TextWrapping = 'Wrap'; $hb.Margin = '0,4,0,0'
        [void]$hs.Children.Add($ht); [void]$hs.Children.Add($hb)
        $hdr.Child = $hs
    } else { $hdr.Child = $ht }
    return $hdr
}
function Show-InputBox {
    param([string]$Prompt, [string]$Title = 'Input', [string]$Default = '')
    $w = New-Object System.Windows.Window; $w.Title = $Title; $w.SizeToContent = 'Height'; $w.Width = 440
    Lz2e8ddc8b18 $w
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI'); $w.FontSize = 13; $w.Background = [System.Windows.Media.Brushes]::White
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '18'
    $tb0 = New-Object System.Windows.Controls.TextBlock; $tb0.Text = $Prompt; $tb0.TextWrapping = 'Wrap'; $tb0.Margin = '0,0,0,8'
    $tx = New-Object System.Windows.Controls.TextBox; $tx.Text = $Default
    $bp = New-Object System.Windows.Controls.StackPanel; $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.Margin = '0,12,0,0'
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'OK'; $ok.Padding = '16,4'; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cn = New-Object System.Windows.Controls.Button; $cn.Content = 'Cancel'; $cn.Padding = '16,4'; $cn.IsCancel = $true
    [void]$bp.Children.Add($ok); [void]$bp.Children.Add($cn)
    [void]$sp.Children.Add($tb0); [void]$sp.Children.Add($tx); [void]$sp.Children.Add($bp)
    $hdr = New-DialogHeader -Title $Title
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($sp)
    $w.Content = $dock
    $script:InpText = $tx; $script:InpWin = $w; $script:InputResult = $null
    $tx.Focus() | Out-Null
    $ok.Add_Click({ $script:InputResult = $script:InpText.Text; $script:InpWin.DialogResult = $true })
    $r = $w.ShowDialog()
    if ($r -eq $true) { return $script:InputResult } else { return $null }
}
$script:MsgWin = $null
$script:MsgResult = 'Cancel'
function Show-Msg {
    param(
        [string]$Text,
        [string]$Caption = '',
        [string]$Buttons = 'OK',
        [string]$Icon = 'None',
        [string]$YesLabel = 'Yes',
        [string]$NoLabel = 'No'
    )
    $sevGlyph = switch ("$Icon") { 'Error' { [char]0xEA39 } 'Warning' { [char]0xE7BA } default { [char]0xE946 } }
    $sevCol   = switch ("$Icon") { 'Error' { '#F97066' } 'Warning' { '#F5B44A' } default { '#7FB2E5' } }
    $showGlyph = ("$Icon" -eq 'Error' -or "$Icon" -eq 'Warning')
    $head = if ($Caption) { $Caption } else {
        switch ("$Icon") {
            'Error'   { 'Something went wrong' }
            'Warning' { 'Please check this' }
            default   { 'Liscaragh Migrate' }
        }
    }
    [xml]$mx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dialog" Width="520" SizeToContent="Height" MaxHeight="700" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize" ShowInTaskbar="False" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="20,14">
      <StackPanel Orientation="Horizontal">
        <TextBlock x:Name="HeadIcon" FontFamily="Segoe MDL2 Assets" FontSize="17" VerticalAlignment="Center" Margin="0,0,11,0"/>
        <TextBlock x:Name="Head" Foreground="White" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="16,11">
      <StackPanel x:Name="Buttons" Orientation="Horizontal" HorizontalAlignment="Right"/>
    </Border>
    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="20,16">
      <StackPanel x:Name="Body"/>
    </ScrollViewer>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $mx))
    Lz2e8ddc8b18 $w
    $w.Title = if ($Caption) { $Caption } else { 'Liscaragh Migrate' }
    try { if ($win -and $win.IsVisible) { $w.Owner = $win } } catch { }
    $hi = $w.FindName('HeadIcon')
    if ($showGlyph) { $hi.Text = [string]$sevGlyph; $hi.Foreground = $sevCol } else { $hi.Visibility = 'Collapsed' }
    $w.FindName('Head').Text = $head
    $body = $w.FindName('Body'); $btns = $w.FindName('Buttons')
    $paras = @([regex]::Split("$Text", '\r?\n\r?\n') | Where-Object { "$_".Trim() })
    for ($i = 0; $i -lt $paras.Count; $i++) {
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = "$($paras[$i])".Trim()
        $t.TextWrapping = 'Wrap'; $t.LineHeight = 19
        if ($i -eq 0) { $t.Foreground = '#101828'; $t.FontWeight = 'SemiBold' }
        else          { $t.Foreground = '#475467'; $t.Margin = '0,9,0,0' }
        [void]$body.Children.Add($t)
    }
    $script:MsgWin = $w; $script:MsgResult = 'Cancel'
    $mk = {
        param([string]$Label, [string]$Result, [bool]$IsDef, [bool]$IsCan)
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $Label; $b.Padding = '16,5'; $b.Margin = '8,0,0,0'; $b.MinWidth = 88
        if ($IsDef) { $b.FontWeight = 'SemiBold'; $b.IsDefault = $true }
        if ($IsCan) { $b.IsCancel = $true }
        $b.Tag = $Result
        $b.Add_Click({ param($s) $script:MsgResult = "$($s.Tag)"; $script:MsgWin.DialogResult = $true })
        $b
    }
    switch ("$Buttons") {
        'YesNo' {
            [void]$btns.Children.Add((& $mk $NoLabel  'No'  $true  $true))
            [void]$btns.Children.Add((& $mk $YesLabel 'Yes' $false $false))
        }
        'YesNoCancel' {
            [void]$btns.Children.Add((& $mk 'Cancel' 'Cancel' $false $true))
            [void]$btns.Children.Add((& $mk 'No'  'No'  $true  $false))
            [void]$btns.Children.Add((& $mk 'Yes' 'Yes' $false $false))
        }
        'OKCancel' {
            [void]$btns.Children.Add((& $mk 'Cancel' 'Cancel' $false $true))
            [void]$btns.Children.Add((& $mk 'OK' 'OK' $true $false))
        }
        default {
            [void]$btns.Children.Add((& $mk 'OK' 'OK' $true $true))
        }
    }
    try { [void]$w.ShowDialog() } catch {}
    return $script:MsgResult
}
function Lze80902559b {
    param([string]$Title, [string]$Heading, [object[]]$Sections, [string]$Yes, [string]$No = 'Close', [switch]$Brand)
    [xml]$ex = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dialog" Width="600" SizeToContent="Height" MaxHeight="760" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="20,15">
      <TextBlock x:Name="Head" Foreground="White" FontSize="16" FontWeight="SemiBold" TextWrapping="Wrap"/>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="16,11">
      <StackPanel x:Name="Buttons" Orientation="Horizontal" HorizontalAlignment="Right"/>
    </Border>
    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="20,16">
      <!-- Dock the chip Right and FIRST, so it reserves its width and the body text wraps
           beside it rather than under it. VerticalAlignment=Top lines it up with the first
           section (Version) rather than floating in the middle of the panel. -->
      <DockPanel LastChildFill="True">
        <Border x:Name="BrandChip" DockPanel.Dock="Right" Background="#000000" CornerRadius="5" Padding="14,12"
                Margin="18,0,0,0" VerticalAlignment="Top" Visibility="Collapsed">
          <Image x:Name="BrandLogo" Height="108" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"
                 ToolTip="Liscaragh Software"/>
        </Border>
        <StackPanel x:Name="Body"/>
      </DockPanel>
    </ScrollViewer>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $ex))
    Lz2e8ddc8b18 $w
    $w.Title = $Title
    $head = $w.FindName('Head'); $body = $w.FindName('Body'); $btns = $w.FindName('Buttons')
    $head.Text = $Heading
    if ($Brand) {
        $img = $w.FindName('BrandLogo')
        Set-BrandLogo $img
        if ($img -and $img.Source) {
            $w.FindName('BrandChip').Visibility = 'Visible'
            $img.Cursor = [System.Windows.Input.Cursors]::Hand
            $img.ToolTip = 'Open liscaragh.com'
            $img.Add_MouseLeftButtonUp({
                try { Start-Process 'https://www.liscaragh.com' } catch { Lz5af601c665 ('Could not open the browser: ' + $_.Exception.Message) }
            })
        }
    }
    foreach ($s in $Sections) {
        if ($s -is [hashtable]) {
            if ($s.H) {
                $h = New-Object System.Windows.Controls.TextBlock
                $h.Text = $s.H; $h.FontWeight = 'SemiBold'; $h.Foreground = '#1D3E5E'; $h.Margin = '0,10,0,2'
                [void]$body.Children.Add($h)
            }
            $t = New-Object System.Windows.Controls.TextBlock
            $t.TextWrapping = 'Wrap'; $t.Foreground = '#1F2937'; $t.LineHeight = 19
            $bTxt = "$($s.B)"
            if ($s.Url) {
                $linkTxt = if ($s.LinkText) { "$($s.LinkText)" } else { $bTxt }
                $ix = $bTxt.IndexOf($linkTxt)
                if ($ix -lt 0) { $t.Text = $bTxt }
                else {
                    if ($ix -gt 0) { [void]$t.Inlines.Add((New-Object System.Windows.Documents.Run $bTxt.Substring(0, $ix))) }
                    $lnk = New-Object System.Windows.Documents.Hyperlink
                    [void]$lnk.Inlines.Add($linkTxt)
                    $lnk.Foreground = '#1C6091'
                    $u = "$($s.Url)"
                    $lnk.Add_Click({ try { Start-Process $u } catch { Lz5af601c665 ('Could not open: ' + $_.Exception.Message) } }.GetNewClosure())
                    [void]$t.Inlines.Add($lnk)
                    $restTxt = $bTxt.Substring($ix + $linkTxt.Length)
                    if ($restTxt) { [void]$t.Inlines.Add((New-Object System.Windows.Documents.Run $restTxt)) }
                }
            } else {
                $t.Text = $bTxt
            }
            [void]$body.Children.Add($t)
        } else {
            $t = New-Object System.Windows.Controls.TextBlock
            $t.Text = "$s"; $t.TextWrapping = 'Wrap'; $t.Foreground = '#1F2937'; $t.LineHeight = 19; $t.Margin = '0,4,0,0'
            [void]$body.Children.Add($t)
        }
    }
    $script:ExplainWin = $w; $script:ExplainResult = $false
    if ($Yes) {
        $by = New-Object System.Windows.Controls.Button
        $by.Content = $Yes; $by.Padding = '16,5'; $by.Margin = '8,0,0,0'; $by.FontWeight = 'SemiBold'; $by.IsDefault = $true
        $by.Add_Click({ $script:ExplainResult = $true; $script:ExplainWin.DialogResult = $true })
        $bn = New-Object System.Windows.Controls.Button
        $bn.Content = $No; $bn.Padding = '16,5'; $bn.Margin = '8,0,0,0'; $bn.IsCancel = $true
        [void]$btns.Children.Add($bn); [void]$btns.Children.Add($by)
    } else {
        $bo = New-Object System.Windows.Controls.Button
        $bo.Content = $No; $bo.Padding = '16,5'; $bo.Margin = '8,0,0,0'; $bo.IsDefault = $true; $bo.IsCancel = $true
        [void]$btns.Children.Add($bo)
    }
    [void]$w.ShowDialog()
    return $script:ExplainResult
}
$script:JobButtons = @('BtnPreflight','BtnDryRun','BtnTransfer','BtnDelta','BtnSchedule','BtnValidate','BtnSizeCheck','BtnOpenReport','BtnCertificate','BtnSourceReview','BtnProvenance','BtnOpenAudit','BtnApplyCap','ChkLinuxSrc','BtnCatVerify','BtnDrift')
function Lz35d0f8dce4 { param([bool]$On) foreach ($n in $script:JobButtons) { if ($ctrl[$n]) { $ctrl[$n].IsEnabled = $On } } }
$script:JobMenuItems = @('MnuJobSave','MnuJobSaveAs','MnuJobRename','MnuJobOpenFolder','MnuJobExport','MnuJobClose','MnuJobDelete')
function Lzdd341be2a9 { param([bool]$On) foreach ($n in $script:JobMenuItems) { if ($ctrl[$n]) { $ctrl[$n].IsEnabled = $On } } }
function Lz56e0fac1fe {
    try {
        $ctrl.MnuJobRecent.Items.Clear()
        $cur = Get-RegSetting 'RecentJobs'
        $list = if ($cur) { @($cur -split "`n" | Where-Object { $_ -and (Test-Path $_) -and ((Get-JobSourceType $_) -eq $script:TransferMode) }) } else { @() }
        if (-not $list.Count) { $mi=New-Object System.Windows.Controls.MenuItem; $mi.Header='(none yet)'; $mi.IsEnabled=$false; [void]$ctrl.MnuJobRecent.Items.Add($mi); return }
        foreach ($p in $list) {
            $nm=$p; try { $jj=Join-Path (Split-Path $p) 'job.json'; if (Test-Path $jj) { $nm=(Get-Content $jj -Raw|ConvertFrom-Json).name } } catch {}
            $mi=New-Object System.Windows.Controls.MenuItem; $mi.Header=$nm; $mi.Tag=$p
            $mi.Add_Click({ param($s,$e) if (Test-Path $s.Tag) { Set-CurrentJob -ConfigFile $s.Tag; Start-AutoConnect } else { (Show-Msg -Text ('That job no longer exists.')) } })
            [void]$ctrl.MnuJobRecent.Items.Add($mi)
        }
    } catch {}
}
function Lz08b1f4f085 { param([string]$ConfigFile)
    try {
        $cur = Get-RegSetting 'RecentJobs'
        $list = if ($cur) { @($cur -split "`n" | Where-Object { $_ }) } else { @() }
        $list = @(@($ConfigFile) + @($list | Where-Object { $_ -ne $ConfigFile })) | Select-Object -First 8
        Lz933059a102 -Name 'RecentJobs' -Value ($list -join "`n")
    } catch {}
    Lz56e0fac1fe
}
function Lzb80bda68cf {
    param([ValidateSet('Cancelled','Incomplete')][string]$Status, [string]$Note='', [scriptblock]$OnDone)
    if (-not (Test-Path $script:EnginePath)) { if ($OnDone) { & $OnDone }; return }
    try {
        $fin = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $script:EnginePath, '-ConfigPath', $script:ConfigPath, '-Action','Finalize','-FinalizeStatus',$Status)
        $script:FinProc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $fin -PassThru -WindowStyle Hidden
    } catch { $script:FinProc = $null }
    if (-not $script:FinProc) { if ($OnDone) { & $OnDone }; return }
    if ($Note) { Lz5af601c665 $Note }
    $script:FinOnDone = $OnDone
    $script:FinStart = Get-Date
    $script:FinTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:FinTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:FinTimer.Add_Tick({
        $done = $false
        try { $done = $script:FinProc.HasExited } catch { $done = $true }
        if (-not $done -and (((Get-Date) - $script:FinStart).TotalSeconds -gt 180)) { $done = $true }
        if ($done) {
            $script:FinTimer.Stop()
            $cb = $script:FinOnDone; $script:FinOnDone = $null
            if ($cb) { try { & $cb } catch {} }
        }
    })
    $script:FinTimer.Start()
}
function Get-TransferTypeMeta { param([string]$Id)
    $t = @($script:TransferTypes | Where-Object Id -eq $Id)
    if ($t.Count) { return $t[0] }
    return [pscustomobject]@{ Id=$Id; Short=$Id; Title=$Id; Desc=''; Status='Live' }
}
function Get-JobSourceType {
    param([string]$ConfigFile)
    try {
        $jf = Join-Path (Split-Path $ConfigFile) 'job.json'
        if (Test-Path $jf) {
            $j = Get-Content $jf -Raw | ConvertFrom-Json
            if (($j.PSObject.Properties.Name -contains 'sourceType') -and "$($j.sourceType)") { return "$($j.sourceType)" }
        }
    } catch {}
    return 'Datto'
}
function Lzd40aefb567 { param([string]$JobName)
    $s = 'Liscaragh Migrate  -  ' + (Get-TransferTypeMeta $script:TransferMode).Short
    if ($JobName) { $s += "  -  $JobName" }
    return $s
}
function Lzaf2eff9079 {
    param([string]$Mode)
    $script:TransferMode = $Mode
    try { Lz933059a102 -Name 'TransferMode' -Value $Mode } catch {}
    $isFiles = ($Mode -eq 'LocalFs')
    if ($isFiles) {
        $script:NItem='source'; $script:NItems='sources'; $script:NItemC='Source'; $script:NItemsC='Sources'
        $script:NSrcSys='your files and folders'; $script:NSrc='the source'
    } else {
        $script:NItem='project'; $script:NItems='projects'; $script:NItemC='Project'; $script:NItemsC='Projects'
        $script:NSrcSys='Datto Workplace'; $script:NSrc='Datto'
    }
    $ctrl.BtnConnect.Visibility = if ($isFiles) { 'Collapsed' } else { 'Visible' }
    if ($ctrl.BtnAddFolder)    { $ctrl.BtnAddFolder.Visibility    = if ($isFiles) { 'Visible' } else { 'Collapsed' } }
    if ($ctrl.BtnRemoveFolder) { $ctrl.BtnRemoveFolder.Visibility = if ($isFiles) { 'Visible' } else { 'Collapsed' } }
    if ($ctrl.BtnShareCreds)   { $ctrl.BtnShareCreds.Visibility   = if ($isFiles) { 'Visible' } else { 'Collapsed' } }
    if ($ctrl.ChkLinuxSrc)     { $ctrl.ChkLinuxSrc.Visibility     = if ($isFiles) { 'Visible' } else { 'Collapsed' } }
    if ($ctrl.BtnLinuxInfo)    { $ctrl.BtnLinuxInfo.Visibility    = if ($isFiles) { 'Visible' } else { 'Collapsed' } }
    if ($ctrl.BtnSourceReview) { $ctrl.BtnSourceReview.Visibility = if ($isFiles) { 'Collapsed' } else { 'Visible' } }
    if ($ctrl.GridBeforeCopy) { $ctrl.GridBeforeCopy.Columns = 1 }
    if ($ctrl.LblSrcIntro)   { $ctrl.LblSrcIntro.Visibility   = if ($isFiles) { 'Collapsed' } else { 'Visible' } }
    if ($ctrl.PnlSrcFolders) { $ctrl.PnlSrcFolders.Visibility = if ($isFiles) { 'Collapsed' } else { 'Visible' } }
    try { $ctrl.LstProjects.Columns[0].Header = if ($isFiles) { 'Source' } else { 'Project' } } catch {}
    try {
        if ($ctrl.ChkSrcContents) {
            if ($isFiles) {
                $ctrl.ChkSrcContents.Content = "Copy only this folder's contents (don't create the folder itself)"
                $ctrl.ChkSrcContents.ToolTip = "Off (the default) = the folder is copied WITH its own name, so 'Finance' lands in a 'Finance' folder at the destination and folders sent to the same place never overwrite each other. On = only the files inside land, straight into the destination folder - use this to merge one folder into a destination that already exists, knowing same-named files will be overwritten."
            } else {
                $ctrl.ChkSrcContents.Content = "Copy only this project's contents (don't create the project's folder itself)"
                $ctrl.ChkSrcContents.ToolTip = "Off (the default) = the project is copied WITH its own folder, so 'Project X' lands in a 'Project X' folder at the destination, and a chosen source subfolder keeps its name inside that. Projects sent to the same place never overwrite each other. On = only the files land, straight into the destination folder - use this to merge one project into a destination that already exists, knowing same-named files will be overwritten, and note a later sync must use the same setting to find the files where it left them."
            }
        }
    } catch {}
    try {
        if ($ctrl.LblProjectsHead) { $ctrl.LblProjectsHead.Text = "$($script:NItemsC) (select one or more)"; $ctrl.LblProjectsHead.ToolTip = "Select one $($script:NItem), or several with Ctrl or Shift, then set the destination on the right." }
        if ($ctrl.TxtFilterHint)   { $ctrl.TxtFilterHint.Text   = "Search $($script:NItems) by name or destination..." }
        if ($ctrl.TxtFilter)       { $ctrl.TxtFilter.ToolTip    = "Type to filter the list by $($script:NItem) name or destination." }
        if ($ctrl.BtnFilters)      { $ctrl.BtnFilters.ToolTip   = "Choose which files this job copies: by size, by file type (skip certain types, or copy ONLY certain types), and by modified date. These filters apply to EVERY $($script:NItem) in this job, not just the selected one." }
        if ($ctrl.TxtFolder)       { $ctrl.TxtFolder.ToolTip    = "A subfolder at the destination to place this $($script:NItem) in. Leave blank to put it at the top level." }
        if ($ctrl.BtnPreflight)    { $ctrl.BtnPreflight.ToolTip = "Checks for problems (destination quota, over-long names) before anything is uploaded. Walks every $($script:NItem) first, so it is slower on large ones. Greyed out while a run is in progress, and until you have connected and selected a $($script:NItem) with a destination set; it becomes available once the run ends." }
        if ($ctrl.BtnDryRun)       { $ctrl.BtnDryRun.ToolTip    = "A safe rehearsal: lists exactly what would be uploaded, without changing anything. Walks every $($script:NItem) first, so it is slower on large ones. Greyed out while a run is in progress, and until you have connected and selected a $($script:NItem) with a destination set; it becomes available once the run ends." }
        if ($ctrl.LblMapHeader)    { $ctrl.LblMapHeader.Text     = if ($isFiles) { 'Destination for this source' } else { 'Source and Destination mapping for the selected project' } }
        if ($ctrl.LblDestQ)        { $ctrl.LblDestQ.Text         = "Where should this $($script:NItem)'s files go?" }
        if (-not $script:JobOpen -and $ctrl.LblProject) { $ctrl.LblProject.Text = "(no $($script:NItem) selected)" }
        if ($ctrl.RbOneDrive) { $ctrl.RbOneDrive.ToolTip = "Send this $($script:NItem) into one person's OneDrive (for their personal content). The common choice." }
        if ($ctrl.RbSite)     { $ctrl.RbSite.ToolTip     = "Send this $($script:NItem) into a SharePoint site's document library (for shared or team content)." }
        if ($ctrl.RbSkip)     { $ctrl.RbSkip.Content = if ($isFiles) { 'Skip this source' } else { 'Skip this project' }; $ctrl.RbSkip.ToolTip = if ($isFiles) { 'Do not copy this source.' } else { 'Do not migrate this project.' } }
        if ($ctrl.BtnCheck)   { $ctrl.BtnCheck.ToolTip = 'Confirm the destination exists (site + library, or the user''s OneDrive). Changes nothing.' }
    } catch {}
    try {
        if ($isFiles) {
            $ctrl.BtnTransfer.ToolTip = 'Copies every file and overwrites the destination with the source version. For the first copy. You will be asked to confirm.'
            $ctrl.BtnDelta.ToolTip    = 'Merges the source into the Microsoft 365 copy, comparing file by file. Use this to top up after a copy, or to fold a source folder into a destination folder that already holds content. You choose add-new-only or update-where-the-source-is-newer. It never deletes anything.'
            if ($ctrl.TxtDeltaDesc) { $ctrl.TxtDeltaDesc.Text = 'Adds new files and updates changed files. Files removed from the source are not deleted from Microsoft 365.' }
            if ($ctrl.BtnValidate)  { $ctrl.BtnValidate.ToolTip = 'Checks every source file is present at the destination and up to date (its date is not older than the source).' }
        } else {
            $ctrl.BtnTransfer.ToolTip = 'Copies every file and overwrites the destination with the Datto version. For the first migration. You will be asked to confirm.'
            $ctrl.BtnDelta.ToolTip    = 'Merges Datto into the Microsoft 365 copy, comparing file by file. Use this to top up after an upload, or to fold a Datto folder into a destination folder that already holds content. You choose add-new-only or update-where-Datto-is-newer. It never deletes anything.'
            if ($ctrl.TxtDeltaDesc) { $ctrl.TxtDeltaDesc.Text = 'Adds new files and updates changed files. Files removed from Datto are not deleted from Microsoft 365.' }
            if ($ctrl.BtnValidate)  { $ctrl.BtnValidate.ToolTip = 'Checks every Datto file is present at the destination and up to date (its date is not older than Datto''s).' }
        }
    } catch {}
    try { Update-ApplyButtonState } catch {}
    try { $win.Title = Lzd40aefb567 $(if ($script:JobOpen) { "$($ctrl.LblJob.Text)" } else { '' }) } catch {}
    try { Lz154ffece7e (Lzb6cc704a5f) } catch {}
}
function Lzad6bdd19f4 {
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Liscaragh Migrate'; $w.Width = 680; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $w.Background = '#F2F4F7'
    $w.Resources = [System.Windows.Markup.XamlReader]::Parse(@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Style x:Key="LaunchCard" TargetType="Button">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Margin" Value="5"/>
    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="bd" Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="12" Padding="14,13" SnapsToDevicePixels="True">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#E2500F"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="LaunchCardSoon" TargetType="Button">
    <Setter Property="Margin" Value="5"/>
    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
    <Setter Property="Opacity" Value="0.62"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border Background="White" BorderBrush="#E4E7EC" BorderThickness="1" CornerRadius="12" Padding="14,13" SnapsToDevicePixels="True">
            <ContentPresenter/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
'@)
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '26,20,26,16'
    $script:LauncherPick = $null
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($cw in @('*','*')) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $cw; $grid.ColumnDefinitions.Add($cd) }
    $rows = [math]::Ceiling($script:TransferTypes.Count / 2)
    for ($ri = 0; $ri -lt $rows; $ri++) { $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = 'Auto'; $grid.RowDefinitions.Add($rd) }
    $ci = 0
    foreach ($t in $script:TransferTypes) {
        $live = ($t.Status -eq 'Live')
        $b = New-Object System.Windows.Controls.Button
        $b.Tag = $t.Id
        $b.Style = $w.Resources[$(if ($live) { 'LaunchCard' } else { 'LaunchCardSoon' })]
        $dock = New-Object System.Windows.Controls.DockPanel; $dock.LastChildFill = $true
        $gb = New-Object System.Windows.Controls.Border
        $gb.Width = 44; $gb.Height = 44; $gb.CornerRadius = '10'; $gb.Margin = '0,1,12,0'; $gb.VerticalAlignment = 'Top'
        $cs = switch ("$($t.Id)") {
            'LocalFs' { @{ G = [char]0xE8B7; T = '#EFF4F9'; C = '#1C6091' } }
            'Datto'   { @{ G = [char]0xE753; T = '#FDEAD7'; C = '#E2500F' } }
            'Box'     { @{ G = [char]0xE753; T = '#E8F0FE'; C = '#0061D5' } }
            'Dropbox' { @{ G = [char]0xE753; T = '#E7F0FF'; C = '#2E7CF6' } }
            'GDrive'  { @{ G = [char]0xE753; T = '#E9F7EF'; C = '#34A853' } }
            default   { @{ G = [char]0xE753; T = '#F2F4F7'; C = '#98A2B3' } }
        }
        $gb.Background = $cs.T
        $gt = New-Object System.Windows.Controls.TextBlock
        $gt.FontFamily = 'Segoe MDL2 Assets'; $gt.FontSize = 20
        $gt.Text = $cs.G
        $gt.Foreground = $cs.C
        $gt.HorizontalAlignment = 'Center'; $gt.VerticalAlignment = 'Center'
        $gb.Child = $gt
        [System.Windows.Controls.DockPanel]::SetDock($gb, 'Left')
        [void]$dock.Children.Add($gb)
        $body = New-Object System.Windows.Controls.StackPanel
        $row = New-Object System.Windows.Controls.DockPanel; $row.LastChildFill = $false
        $badge = New-Object System.Windows.Controls.Border
        $badge.CornerRadius = '99'; $badge.Padding = '8,2'; $badge.VerticalAlignment = 'Top'; $badge.Margin = '10,1,0,0'
        $badge.Background = $(if ($live) { '#EFFAF4' } else { '#F2F4F7' })
        $bt = New-Object System.Windows.Controls.TextBlock
        $bt.Text = $(if ($live) { 'AVAILABLE' } else { 'COMING SOON' })
        $bt.FontSize = 10; $bt.FontWeight = 'Bold'
        $bt.Foreground = $(if ($live) { '#066A4B' } else { '#98A2B3' })
        $badge.Child = $bt
        [System.Windows.Controls.DockPanel]::SetDock($badge, 'Right')
        $tt = New-Object System.Windows.Controls.TextBlock; $tt.Text = $t.Short; $tt.ToolTip = $t.Title; $tt.FontWeight = 'SemiBold'; $tt.FontSize = 14.5; $tt.Foreground = '#101828'; $tt.TextTrimming = 'CharacterEllipsis'
        [void]$row.Children.Add($badge); [void]$row.Children.Add($tt)
        $d = New-Object System.Windows.Controls.TextBlock; $d.Text = $t.Desc; $d.TextWrapping = 'Wrap'; $d.Foreground = '#667085'; $d.FontSize = 12; $d.Margin = '0,3,0,0'
        [void]$body.Children.Add($row); [void]$body.Children.Add($d)
        [void]$dock.Children.Add($body)
        $b.Content = $dock
        if ($live) {
            $b.Add_Click({ param($s,$e) $script:LauncherPick = "$($s.Tag)"; $script:LauncherWin.DialogResult = $true })
        } else {
            $b.Add_Click({ param($s,$e) (Show-Msg -Text ("This transfer type is coming soon. If it matters to you, tell us at support@liscaragh.com - it genuinely moves it up the list.") -Caption ('Coming soon')) | Out-Null })
        }
        $r = [math]::Floor($ci / 2); $c = $ci % 2
        [System.Windows.Controls.Grid]::SetRow($b, $r)
        if (($ci -eq $script:TransferTypes.Count - 1) -and ($c -eq 0)) { [System.Windows.Controls.Grid]::SetColumnSpan($b, 2) }
        else { [System.Windows.Controls.Grid]::SetColumn($b, $c) }
        [void]$grid.Children.Add($b)
        $ci++
    }
    [void]$root.Children.Add($grid)
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = 'Open this transfer type next time without asking (hold Shift while starting the app to choose again)'
    $chk.Margin = '5,12,0,0'; $chk.FontSize = 12; $chk.Foreground = '#4B5563'
    $chk.IsChecked = (([string](Get-RegSetting 'TransferModeRemember')) -ne '0')
    [void]$root.Children.Add($chk)
    $vt = New-Object System.Windows.Controls.TextBlock; $vt.Text = "Version $($script:AppVersion)  -  Liscaragh Software"; $vt.Foreground = '#98A2B3'; $vt.FontSize = 11; $vt.Margin = '0,10,0,0'; $vt.HorizontalAlignment = 'Center'
    [void]$root.Children.Add($vt)
    $hdr = New-DialogHeader -Title 'What are you moving?' -Subtitle 'Choose a transfer type. You can switch later from Job > Switch transfer type.'
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($root)
    $w.Content = $dock
    $script:LauncherWin = $w
    [void]$w.ShowDialog()
    try { Lz933059a102 -Name 'TransferModeRemember' -Value $(if ($chk.IsChecked) { '1' } else { '0' }) } catch {}
    return $script:LauncherPick
}
function Lz10167c5c6e {
    $roots = @()
    try {
        if ($script:Cfg -and ($script:Cfg.PSObject.Properties.Name -contains 'source') -and $script:Cfg.source -and
            ($script:Cfg.source.PSObject.Properties.Name -contains 'localRoots')) { $roots = @($script:Cfg.source.localRoots) }
    } catch {}
    $roots = @($roots | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $leaves = @{}
    foreach ($r in $roots) { $l = Split-Path $r -Leaf; if (-not $l) { $l = $r }; $leaves[$l] = [int]$leaves[$l] + 1 }
    $out = @()
    foreach ($r in $roots) {
        $l = Split-Path $r -Leaf; if (-not $l) { $l = $r }
        $nm = if ($leaves[$l] -gt 1) { $par = ''; try { $par = Split-Path (Split-Path $r -Parent) -Leaf } catch {}; if ($par) { "$l ($par)" } else { $l } } else { $l }
        $out += [pscustomobject]@{ Id = $r; Name = $nm }
    }
    return $out
}
function Lz795197fd79 {
    param([string[]]$Roots, [string]$SelectId = '')
    $cfg = Read-ConfigJson $script:ConfigPath
    if (-not ($cfg.PSObject.Properties.Name -contains 'source') -or $null -eq $cfg.source) {
        $cfg | Add-Member -NotePropertyName source -NotePropertyValue ([pscustomobject]@{ provider = 'LocalFs'; localRoots = @() }) -Force
    }
    if ($cfg.source.PSObject.Properties.Name -contains 'localRoots') { $cfg.source.localRoots = @($Roots) }
    else { $cfg.source | Add-Member -NotePropertyName localRoots -NotePropertyValue @($Roots) -Force }
    Write-ConfigJson -Cfg $cfg -Path $script:ConfigPath
    try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch {}
    $script:Projects = @(Lz10167c5c6e)
    Lzc219beec58
    if ($SelectId) { Lz802cd60b97 -Id $SelectId }
    Lzeb3a1395a1 -Text "$(@($script:Projects).Count) folder(s) in this job" -State $(if (@($script:Projects).Count) { 'ok' } else { 'off' })
}
function Lz0a98311b67 {
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Add folder'; $w.Width = 560; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '14'
    $l = New-Object System.Windows.Controls.TextBlock; $l.Text = 'Folder to copy (type or paste a path, or Browse):'; $l.Margin = '0,0,0,6'
    $row = New-Object System.Windows.Controls.DockPanel
    $bb = New-Object System.Windows.Controls.Button; $bb.Content = 'Browse...'; $bb.Padding = '10,2'; $bb.Margin = '6,0,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($bb, 'Right')
    $tb = New-Object System.Windows.Controls.TextBox; $tb.MinWidth = 380
    [void]$row.Children.Add($bb); [void]$row.Children.Add($tb)
    $hint = New-Object System.Windows.Controls.TextBlock; $hint.Text = 'Examples:  D:\Shared\Finance   or   \\FS01\Projects\2026'; $hint.Foreground = 'Gray'; $hint.FontSize = 11.5; $hint.Margin = '0,4,0,0'
    $bp = New-Object System.Windows.Controls.StackPanel; $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.Margin = '0,12,0,0'
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'Add'; $ok.Padding = '16,4'; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cn = New-Object System.Windows.Controls.Button; $cn.Content = 'Cancel'; $cn.Padding = '16,4'; $cn.IsCancel = $true
    [void]$bp.Children.Add($ok); [void]$bp.Children.Add($cn)
    foreach ($c in @($l,$row,$hint,$bp)) { [void]$root.Children.Add($c) }
    $hdr = New-DialogHeader -Title 'Add folder'
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($root)
    $w.Content = $dock
    $script:AddFolderBox = $tb; $script:AddFolderWin = $w
    $bb.Add_Click({
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $fb = New-Object System.Windows.Forms.FolderBrowserDialog
            $fb.Description = 'Choose the folder to copy'
            if ($fb.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:AddFolderBox.Text = $fb.SelectedPath }
        } catch { (Show-Msg -Text ("Could not open the folder browser: $($_.Exception.Message). Type or paste the path instead.") -Caption ('Add folder')) }
    })
    $ok.Add_Click({ $script:AddFolderWin.DialogResult = $true })
    $r = $w.ShowDialog()
    if (-not $r) { return $null }
    return "$($tb.Text)".Trim().Trim('"')
}
$ctrl.MnuJobSwitch.Add_Click({
    if (Test-ScheduleBusy) { (Show-Msg -Text ('A run is in progress. Wait for it to finish, or stop it, then switch.') -Caption ('Switch transfer type')); return }
    $pick = Lzad6bdd19f4
    if (-not $pick -or $pick -eq $script:TransferMode) { return }
    if ($script:JobOpen) { Lz6dea60a733 }
    Lzaf2eff9079 $pick
    Lz56e0fac1fe
    Lz5af601c665 ("Transfer type: " + (Get-TransferTypeMeta $pick).Title + ". Create or open a job (Job menu).")
    if (-not (Lzb6cc704a5f)) { try { Lzb52a94c8d8 } catch {} }
})
function Lze646d321c3 {
    param([string]$Server, [string]$User, [string]$Password)
    Lz769335e702
    return [Liscara.CredMan]::Write($Server, $User, $Password)
}
function Lz769335e702 {
    if ('Liscara.CredMan' -as [type]) { return }
    Add-Type -Namespace Liscara -Name CredMan -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
}
[DllImport("Advapi32.dll", SetLastError=true, EntryPoint="CredWriteW", CharSet=CharSet.Unicode)]
public static extern bool CredWriteW(ref CREDENTIAL cred, int flags);
[DllImport("Advapi32.dll", SetLastError=true, EntryPoint="CredEnumerateW", CharSet=CharSet.Unicode)]
public static extern bool CredEnumerateW(string filter, int flags, out int count, out IntPtr credentials);
[DllImport("Advapi32.dll", SetLastError=true, EntryPoint="CredDeleteW", CharSet=CharSet.Unicode)]
public static extern bool CredDeleteW(string target, int type, int flags);
[DllImport("Advapi32.dll", EntryPoint="CredFree")]
public static extern void CredFree(IntPtr buffer);
public static bool Write(string target, string user, string pass) {
    IntPtr blob = Marshal.StringToCoTaskMemUni(pass);
    try {
        CREDENTIAL c = new CREDENTIAL();
        c.Type = 2;                       // CRED_TYPE_DOMAIN_PASSWORD: used by SMB automatically
        c.TargetName = target;
        c.CredentialBlobSize = pass.Length * 2;
        c.CredentialBlob = blob;
        c.Persist = 2;                    // CRED_PERSIST_LOCAL_MACHINE: survives sign-out/reboot
        c.UserName = user;
        return CredWriteW(ref c, 0);
    } finally { Marshal.ZeroFreeCoTaskMemUnicode(blob); }
}
public static bool Delete(string target) {
    return CredDeleteW(target, 2, 0);     // CRED_TYPE_DOMAIN_PASSWORD only
}
public static string[] List() {
    int count = 0; IntPtr pcreds = IntPtr.Zero;
    if (!CredEnumerateW(null, 0, out count, out pcreds)) { return new string[0]; }
    try {
        var outp = new System.Collections.Generic.List<string>();
        for (int i = 0; i < count; i++) {
            IntPtr p = Marshal.ReadIntPtr(pcreds, i * IntPtr.Size);
            CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
            if (c.Type == 2) { outp.Add((c.TargetName ?? "") + "\t" + (c.UserName ?? "")); }
        }
        return outp.ToArray();
    } finally { if (pcreds != IntPtr.Zero) { CredFree(pcreds); } }
}
'@ -ErrorAction Stop | Out-Null
}
function Lz4155be04ef {
    param([string]$Path)
    $p = "$Path".Trim().Trim('"').TrimEnd('\','/')
    if (-not $p) { return '' }
    if ($p -match '^([A-Za-z]):') {
        try {
            $dr = Get-PSDrive -Name $Matches[1] -ErrorAction SilentlyContinue
            if ($dr -and ($dr.PSObject.Properties.Name -contains 'DisplayRoot') -and "$($dr.DisplayRoot)" -match '^\\\\') {
                $p = "$($dr.DisplayRoot)".TrimEnd('\') + $p.Substring(2)
            }
        } catch {}
    }
    if ($p -match '^\\\\([^\\]+)') { return $Matches[1] }
    return ''
}
function Lz6d3adcb4fb {
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Store a credential'; $w.Width = 560; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '14'
    $l = New-Object System.Windows.Controls.TextBlock
    $l.Text = "Store the account used to reach a network share or NAS. Windows keeps the sign-in (Credential Manager) and presents it automatically whenever this user connects to that server, including the copy engine and scheduled runs. The password is stored by Windows, cannot be shown again, and is never written by this app."
    $l.TextWrapping = 'Wrap'; $l.Foreground = '#475467'; $l.Margin = '0,0,0,10'
    [void]$root.Children.Add($l)
    $ll = New-Object System.Windows.Controls.TextBlock; $ll.Text = 'Location (type, paste or Browse):'; $ll.Margin = '0,0,0,4'
    [void]$root.Children.Add($ll)
    $row = New-Object System.Windows.Controls.DockPanel
    $bb = New-Object System.Windows.Controls.Button; $bb.Content = 'Browse...'; $bb.Padding = '10,2'; $bb.Margin = '6,0,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($bb, 'Right')
    $tbLoc = New-Object System.Windows.Controls.TextBox; $tbLoc.MinWidth = 380
    [void]$row.Children.Add($bb); [void]$row.Children.Add($tbLoc)
    [void]$root.Children.Add($row)
    $hint = New-Object System.Windows.Controls.TextBlock; $hint.Text = 'Examples:  \\FS01\Projects   or   \\NAS01   (a local drive does not need a stored sign-in)'; $hint.Foreground = 'Gray'; $hint.FontSize = 11.5; $hint.Margin = '0,4,0,8'
    [void]$root.Children.Add($hint)
    function Lz0245822181 { param($lab,$ctl)
        $g = New-Object System.Windows.Controls.Grid
        foreach ($cw in '130','*') { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = $cw; $g.ColumnDefinitions.Add($c) }
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $lab; $t.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($t,0); [void]$g.Children.Add($t)
        [System.Windows.Controls.Grid]::SetColumn($ctl,1); [void]$g.Children.Add($ctl)
        $g.Margin = '0,0,0,6'; [void]$root.Children.Add($g)
    }
    $tbUsr = New-Object System.Windows.Controls.TextBox
    Lz0245822181 'Username:' $tbUsr
    $uh = New-Object System.Windows.Controls.TextBlock; $uh.Text = 'DOMAIN\user, server\user, or user@domain'; $uh.Foreground = 'Gray'; $uh.FontSize = 11; $uh.Margin = '130,0,0,6'
    [void]$root.Children.Add($uh)
    $pb = New-Object System.Windows.Controls.PasswordBox
    Lz0245822181 'Password:' $pb
    $bp = New-Object System.Windows.Controls.StackPanel; $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.Margin = '0,10,0,0'
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'Store and test'; $ok.Padding = '14,4'; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cn = New-Object System.Windows.Controls.Button; $cn.Content = 'Cancel'; $cn.Padding = '14,4'; $cn.IsCancel = $true
    [void]$bp.Children.Add($ok); [void]$bp.Children.Add($cn)
    [void]$root.Children.Add($bp)
    $hdr = New-DialogHeader -Title 'Store a credential'
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($root)
    $w.Content = $dock
    $script:ASCWin = $w; $script:ASCLoc = $tbLoc; $script:ASCUsr = $tbUsr; $script:ASCPwd = $pb; $script:ASCResult = $null
    $bb.Add_Click({
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $fb = New-Object System.Windows.Forms.FolderBrowserDialog
            $fb.Description = 'Choose the network share or folder'
            if ($fb.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $script:ASCLoc.Text = $fb.SelectedPath }
        } catch { (Show-Msg -Text ("Could not open the folder browser: $($_.Exception.Message). Type or paste the location instead.") -Caption ('Store a credential')) | Out-Null }
    })
    $ok.Add_Click({
        $loc = "$($script:ASCLoc.Text)".Trim()
        $srv = Lz4155be04ef $loc
        if (-not $srv) { (Show-Msg -Text ("Enter a network share (for example \\FS01\Projects) or just the server (\\NAS01), or Browse to a network folder.`n`nA local drive does not need a stored sign-in.") -Caption ('Store a credential') -Icon ('Warning')) | Out-Null; return }
        $u = "$($script:ASCUsr.Text)".Trim()
        if (-not $u -or -not $script:ASCPwd.Password) { (Show-Msg -Text ('Enter the username and password.') -Caption ('Store a credential') -Icon ('Warning')) | Out-Null; return }
        $okW = $false
        try { $okW = Lze646d321c3 -Server $srv -User $u -Password $script:ASCPwd.Password } catch {}
        if (-not $okW) { (Show-Msg -Text ("Windows would not store the sign-in for '$srv'. Try Control Panel > Credential Manager > Windows Credentials > Add a Windows credential.") -Caption ('Store a credential') -Icon ('Warning')) | Out-Null; return }
        if ($loc -match '^\\\\[^\\]+\\') {
            if (Test-Path -LiteralPath $loc -PathType Container) {
                (Show-Msg -Text ("Stored the sign-in for '$srv', and '$loc' opened with it.") -Caption ('Store a credential')) | Out-Null
            } else {
                (Show-Msg -Text ("Stored the sign-in for '$srv', but '$loc' still did not open.`n`nThe sign-in is saved; check the path spelling and that this account really has access to that share.") -Caption ('Store a credential') -Icon ('Warning')) | Out-Null
            }
        } else {
            (Show-Msg -Text ("Stored the sign-in for '$srv'. Windows will use it for that server from now on.") -Caption ('Store a credential')) | Out-Null
        }
        $script:ASCResult = $srv
        $script:ASCWin.DialogResult = $true
    })
    [void]$w.ShowDialog()
    return $script:ASCResult
}
function Lz1ea8374796 {
    Lz769335e702
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Credentials'; $w.Width = 560; $w.Height = 420
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'CanResize'; $w.MinWidth = 460; $w.MinHeight = 300
    $grid = New-Object System.Windows.Controls.Grid; $grid.Margin = '14'
    foreach ($rh in 'Auto','*','Auto') { $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = $rh; $grid.RowDefinitions.Add($rd) }
    $intro = New-Object System.Windows.Controls.TextBlock
    $intro.Text = "Accounts Windows will use to reach network shares and NAS devices. Passwords are held by Windows and cannot be shown. These apply when the app, the copy engine and scheduled runs run as you."
    $intro.TextWrapping = 'Wrap'; $intro.Foreground = '#475467'; $intro.Margin = '0,0,0,10'
    [System.Windows.Controls.Grid]::SetRow($intro,0); [void]$grid.Children.Add($intro)
    $lv = New-Object System.Windows.Controls.ListView
    $gv = New-Object System.Windows.Controls.GridView
    $c1 = New-Object System.Windows.Controls.GridViewColumn; $c1.Header = 'Server'; $c1.Width = 220
    $c1.DisplayMemberBinding = (New-Object System.Windows.Data.Binding 'Server')
    $c2 = New-Object System.Windows.Controls.GridViewColumn; $c2.Header = 'Signed in as'; $c2.Width = 260
    $c2.DisplayMemberBinding = (New-Object System.Windows.Data.Binding 'User')
    $gv.Columns.Add($c1); $gv.Columns.Add($c2); $lv.View = $gv
    [System.Windows.Controls.Grid]::SetRow($lv,1); [void]$grid.Children.Add($lv)
    $bar = New-Object System.Windows.Controls.StackPanel; $bar.Orientation = 'Horizontal'; $bar.HorizontalAlignment = 'Right'; $bar.Margin = '0,10,0,0'
    $bAdd = New-Object System.Windows.Controls.Button; $bAdd.Content = 'Add...'; $bAdd.Padding = '14,4'; $bAdd.Margin = '0,0,8,0'
    $bDel = New-Object System.Windows.Controls.Button; $bDel.Content = 'Remove'; $bDel.Padding = '14,4'; $bDel.Margin = '0,0,8,0'
    $bCls = New-Object System.Windows.Controls.Button; $bCls.Content = 'Close'; $bCls.Padding = '14,4'; $bCls.IsCancel = $true
    [void]$bar.Children.Add($bAdd); [void]$bar.Children.Add($bDel); [void]$bar.Children.Add($bCls)
    [System.Windows.Controls.Grid]::SetRow($bar,2); [void]$grid.Children.Add($bar)
    $hdr = New-DialogHeader -Title 'Credentials'
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($grid)
    $w.Content = $dock
    $script:SCWin = $w; $script:SCListView = $lv
    $script:SCRefresh = {
        $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        try {
            foreach ($line in [Liscara.CredMan]::List()) {
                $parts = $line -split "`t", 2
                $usr = ''; if ($parts.Count -gt 1) { $usr = $parts[1] }
                $items.Add([pscustomobject]@{ Server = $parts[0]; User = $usr })
            }
        } catch {}
        $script:SCListView.ItemsSource = $items
    }
    & $script:SCRefresh
    $bAdd.Add_Click({ if (Lz6d3adcb4fb) { & $script:SCRefresh } })
    $bDel.Add_Click({
        $sel = $script:SCListView.SelectedItem
        if (-not $sel) { (Show-Msg -Text ('Select a server in the list first.') -Caption ('Credentials')) | Out-Null; return }
        $srv = "$($sel.Server)"
        if ((Show-Msg -Text ("Remove the stored sign-in for '$srv'?`n`nWindows forgets the account for that server. Nothing on the share or in Microsoft 365 is touched. Runs that need it will prompt or fail until it is stored again.") -Caption ('Credentials') -Buttons ('YesNo') -Icon ('Question')) -ne 'Yes') { return }
        $okD = $false; try { $okD = [Liscara.CredMan]::Delete($srv) } catch {}
        if (-not $okD) { (Show-Msg -Text ("Could not remove the sign-in for '$srv'. You can also remove it in Control Panel > Credential Manager > Windows Credentials.") -Caption ('Credentials') -Icon ('Warning')) | Out-Null }
        & $script:SCRefresh
    })
    [void]$w.ShowDialog()
}
function Lz3fb24a1c1d {
    param([string]$Server)
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Connect as a different user'; $w.Width = 520; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '14'
    $l = New-Object System.Windows.Controls.TextBlock
    $l.Text = "Windows will sign in to '$Server' with this account whenever it connects, including scheduled and overnight runs. The sign-in is stored by WINDOWS (Credential Manager), not by this app; remove it any time in Control Panel > Credential Manager."
    $l.TextWrapping = 'Wrap'; $l.Foreground = '#475467'; $l.Margin = '0,0,0,10'
    [void]$root.Children.Add($l)
    function Lz02e072822e { param($lab,$ctl)
        $g = New-Object System.Windows.Controls.Grid
        foreach ($cw in '130','*') { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = $cw; $g.ColumnDefinitions.Add($c) }
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $lab; $t.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($t,0); [void]$g.Children.Add($t)
        [System.Windows.Controls.Grid]::SetColumn($ctl,1); [void]$g.Children.Add($ctl)
        $g.Margin = '0,0,0,6'; [void]$root.Children.Add($g)
    }
    $tbSrv = New-Object System.Windows.Controls.TextBox; $tbSrv.Text = $Server; $tbSrv.IsReadOnly = $true; $tbSrv.Background = '#F3F4F6'
    Lz02e072822e 'Server:' $tbSrv
    $tbUsr = New-Object System.Windows.Controls.TextBox
    Lz02e072822e 'Username:' $tbUsr
    $hint = New-Object System.Windows.Controls.TextBlock; $hint.Text = 'DOMAIN\user, server\user, or user@domain'; $hint.Foreground = 'Gray'; $hint.FontSize = 11; $hint.Margin = '130,0,0,6'
    [void]$root.Children.Add($hint)
    $pb = New-Object System.Windows.Controls.PasswordBox
    Lz02e072822e 'Password:' $pb
    $bp = New-Object System.Windows.Controls.StackPanel; $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.Margin = '0,10,0,0'
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'Store and connect'; $ok.Padding = '14,4'; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cn = New-Object System.Windows.Controls.Button; $cn.Content = 'Cancel'; $cn.Padding = '14,4'; $cn.IsCancel = $true
    [void]$bp.Children.Add($ok); [void]$bp.Children.Add($cn)
    [void]$root.Children.Add($bp)
    $hdr = New-DialogHeader -Title 'Connect as a different user'
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($root)
    $w.Content = $dock
    $script:CAWin = $w; $script:CAUsr = $tbUsr; $script:CAPwd = $pb; $script:CASrv = $Server
    $ok.Add_Click({
        $u = "$($script:CAUsr.Text)".Trim()
        if (-not $u -or -not $script:CAPwd.Password) { (Show-Msg -Text ('Enter the username and password.') -Caption ('Connect as a different user')) | Out-Null; return }
        $okW = $false
        try { $okW = Lze646d321c3 -Server $script:CASrv -User $u -Password $script:CAPwd.Password } catch {}
        if ($okW) { $script:CAWin.DialogResult = $true }
        else { (Show-Msg -Text ('Windows would not store the credential. Try Control Panel > Credential Manager > Windows Credentials > Add a Windows credential, then add the folder again.') -Caption ('Connect as a different user') -Icon ('Warning')) | Out-Null }
    })
    return [bool]($w.ShowDialog())
}
if ($ctrl.BtnAddFolder) { $ctrl.BtnAddFolder.Add_Click({
    if (-not $script:JobOpen) { (Show-Msg -Text ('Create or open a job first (Job menu, top left), then add the folders to copy.') -Caption ('Add folder')); return }
    $path = Lz0a98311b67
    if (-not $path) { return }
    $path = $path.TrimEnd('\','/')
    if ($path -notmatch '^([A-Za-z]:\\|\\\\)') { (Show-Msg -Text ("That does not look like a full folder path. Use a local path (D:\Shared\Finance) or a network share (\\server\share\Finance).") -Caption ('Add folder') -Icon ('Warning')); return }
    if ($path -match '^([A-Za-z]):') {
        try {
            $dr = Get-PSDrive -Name $Matches[1] -ErrorAction SilentlyContinue
            if ($dr -and ($dr.PSObject.Properties.Name -contains 'DisplayRoot') -and "$($dr.DisplayRoot)" -match '^\\\\') {
                $unc = "$($dr.DisplayRoot)".TrimEnd('\') + $path.Substring(2)
                Lz5af601c665 ("'" + $path.Substring(0,2) + "' is a mapped drive; using its real address " + $unc + " so scheduled runs keep working")
                $path = $unc
            }
        } catch {}
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $srv = ''; if ($path -match '^\\\\([^\\]+)') { $srv = $Matches[1] }
        $fixed = $false
        if ($srv) {
            if (((Show-Msg -Text ("The folder could not be opened:`n`n$path`n`nIf the share is right but needs a DIFFERENT account (for example a service or admin account that has access), Windows can store that sign-in and use it automatically from now on.`n`nStore a sign-in for '$srv' now and try again?") -Caption ('Add folder') -Buttons ('YesNo') -Icon ('Question')) -eq 'Yes') -and (Lz3fb24a1c1d -Server $srv)) {
                if (Test-Path -LiteralPath $path -PathType Container) { $fixed = $true }
                else { (Show-Msg -Text ("Still could not open:`n`n$path`n`nThe sign-in was stored, but the folder did not open. Check the path spelling and that the account really has access to that share.") -Caption ('Add folder') -Icon ('Warning')) }
            }
        } else {
            (Show-Msg -Text ("The folder could not be opened:`n`n$path`n`nCheck the spelling, that the drive or share is connected, and that you have permission to read it.") -Caption ('Add folder') -Icon ('Warning'))
        }
        if (-not $fixed) { return }
    }
    $cur = @(); try { $cur = @(Lz10167c5c6e | ForEach-Object Id) } catch {}
    if (@($cur | Where-Object { $_ -ieq $path }).Count) { (Show-Msg -Text ('That folder is already part of this job.') -Caption ('Add folder')); return }
    $overlap = @($cur | Where-Object { $path.StartsWith("$_\", [System.StringComparison]::OrdinalIgnoreCase) -or "$_".StartsWith("$path\", [System.StringComparison]::OrdinalIgnoreCase) })
    if ($overlap.Count) { (Show-Msg -Text ("That folder overlaps one already in this job:`n`n$($overlap[0])`n`nA folder inside another would copy the same files twice. Add the outer folder only, or remove the other one first.") -Caption ('Add folder') -Icon ('Warning')); return }
    Lz795197fd79 -Roots @($cur + $path) -SelectId $path
    Lz5af601c665 ("Added " + $path)
}) }
if ($ctrl.BtnShareCreds) { $ctrl.BtnShareCreds.Add_Click({ try { Lz1ea8374796 } catch { (Show-Msg -Text ("Could not open credentials: $($_.Exception.Message)") -Caption ('Credentials') -Icon ('Warning')) } }) }
if ($ctrl.BtnLinuxInfo) { $ctrl.BtnLinuxInfo.Add_Click({
    (Show-Msg -Caption ('Linux / Mac / NAS source') -Text (@'
Tick this when the folders you are copying live on a Linux server, a NAS (Synology, QNAP, TrueNAS and the like), or a Mac share. It changes nothing about which files are copied; it makes the run land cleanly on SharePoint and OneDrive, which are stricter about names than those systems are.

With it on, the run:

  - Tidies names SharePoint rejects. Characters that are legal on Linux/Mac but not in SharePoint (for example " * : < > ? |), trailing dots or spaces, and reserved names are corrected automatically. Every change is written to the renames CSV with the report.

  - Normalises Mac-style accented names. Macs store accents in a different form (an "e" plus a separate accent mark) to Windows and SharePoint. Left as-is, those names never match at the destination and every later Sync re-copies them. Normalising fixes that so a file is recognised as already there.

  - Flags case-only duplicates. A Linux or NAS folder can hold Report.txt AND report.txt; SharePoint keeps only one, so one would overwrite the other. Check readiness lists these so you can rename one at the source before migrating.

Leave it off for a normal Windows source, where none of this applies. It is a per-job setting and is saved with the job.
'@)) | Out-Null
}) }
if ($ctrl.BtnCatVerify)  { $ctrl.BtnCatVerify.Add_Click({  try { Lz1eb59286f7 -Key 'Verify' }  catch { (Show-Msg -Text ("Could not open: $($_.Exception.Message)") -Icon ('Warning')) | Out-Null } }) }
if ($ctrl.BtnActivity)   { $ctrl.BtnActivity.Add_MouseLeftButtonUp({ try { if ($script:ActOpen) { Close-ActivityDrawer } else { Lz103dfbf0f4 } } catch {} }) }
if ($ctrl.BtnActClose)   { $ctrl.BtnActClose.Add_Click({ try { Close-ActivityDrawer } catch {} }) }
if ($ctrl.BtnActOverview){ $ctrl.BtnActOverview.Add_Click({ try { Lz358a780544 'Overview' } catch {} }) }
if ($ctrl.BtnActProblems){ $ctrl.BtnActProblems.Add_Click({ try { Lz358a780544 'Problems' } catch {} }) }
if ($ctrl.BtnActFiles)   { $ctrl.BtnActFiles.Add_Click({ try { Lz358a780544 'Files' } catch {} }) }
if ($ctrl.BtnActAll)     { $ctrl.BtnActAll.Add_Click({ try { Lz358a780544 'All' } catch {} }) }
if ($ctrl.BtnActCopy)    { $ctrl.BtnActCopy.Add_Click({ try { [System.Windows.Clipboard]::SetText("$($ctrl.TxtLog.Text)") ; Lz5af601c665 'Log copied to the clipboard.' } catch {} }) }
if ($ctrl.BtnActOpenLog) { $ctrl.BtnActOpenLog.Add_Click({
    try {
        $b = Lz0d86a71502 'BtnOpenAudit'
        if ($b -and $b.IsEnabled) { $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
        else { (Show-Msg -Text ('Open a job first; each run''s complete log is listed there.') -Caption ('Open log file')) | Out-Null }
    } catch {}
}) }
try { Lz358a780544 'Overview' } catch {}
$script:LinuxSuspend = $false
$script:JunkPatterns = @('thumbs.db','desktop.ini','.DS_Store','~$*','*.tmp')
if ($ctrl.ChkLinuxSrc) {
    $script:LinuxSrcHandler = {
        if ($script:LinuxSuspend -or -not $script:JobOpen -or -not $script:ConfigPath) { return }
        try {
            $cfg = Read-ConfigJson $script:ConfigPath
            if (-not ($cfg.PSObject.Properties.Name -contains 'source') -or $null -eq $cfg.source) {
                $cfg | Add-Member -NotePropertyName source -NotePropertyValue ([pscustomobject]@{ provider = 'LocalFs'; localRoots = @() }) -Force
            }
            $cfg.source | Add-Member -NotePropertyName posix -NotePropertyValue ([bool]$ctrl.ChkLinuxSrc.IsChecked) -Force
            Write-ConfigJson -Cfg $cfg -Path $script:ConfigPath
            try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch {}
            Lz5af601c665 $(if ($ctrl.ChkLinuxSrc.IsChecked) { 'Linux / Mac / NAS source mode ON: names normalised for SharePoint, and Check readiness flags case-only duplicates' } else { 'Linux / Mac / NAS source mode off' })
        } catch {}
    }
    $ctrl.ChkLinuxSrc.Add_Checked($script:LinuxSrcHandler)
    $ctrl.ChkLinuxSrc.Add_Unchecked($script:LinuxSrcHandler)
}
if ($ctrl.BtnRemoveFolder) { $ctrl.BtnRemoveFolder.Add_Click({
    if (-not $script:JobOpen) { return }
    $sel = @($ctrl.LstProjects.SelectedItems)
    if (-not $sel.Count) { (Show-Msg -Text ('Select one or more folders in the list first.') -Caption ('Remove folder')); return }
    $names = @($sel | ForEach-Object { $_.Name })
    if ((Show-Msg -Text ("Remove from this job:`n`n" + ($names -join "`n") + "`n`nNothing on disk or in Microsoft 365 is touched; the folder(s) just stop being part of this job. Their saved destinations are cleared.") -Caption ('Remove folder') -Buttons ('YesNo') -Icon ('Question')) -ne 'Yes') { return }
    $ids = @($sel | ForEach-Object { $_.Id })
    foreach ($id in $ids) { $script:Map.Remove($id) | Out-Null }
    [void](Lz5e06c2c15b)
    $keep = @(Lz10167c5c6e | Where-Object { $ids -notcontains $_.Id } | ForEach-Object Id)
    Lz795197fd79 -Roots $keep
    Lz5af601c665 ("Removed $($ids.Count) folder(s) from the job")
}) }
function Set-CurrentJob {
    param([string]$ConfigFile)
    $jt = Get-JobSourceType $ConfigFile
    if ($jt -ne $script:TransferMode) {
        $want = (Get-TransferTypeMeta $jt).Title
        $cur  = (Get-TransferTypeMeta $script:TransferMode).Title
        if ((Show-Msg -Text ("This is a '$want' job, but the app is currently in '$cur' mode.`n`nSwitch to '$want' and open it?") -Caption ('Different transfer type') -Buttons ('YesNo') -Icon ('Question')) -ne 'Yes') { return }
        if ($script:JobOpen) { Lz6dea60a733 }
        Lzaf2eff9079 $jt
        Lz56e0fac1fe
    }
    if ($script:Sched) { Lz965f94e75c -Why 'Schedule cancelled (job changed).' }
    $script:ConfigPath = $ConfigFile
    Protect-ConfigFileInPlace $ConfigFile
    $name = '(config)'
    $jf = Join-Path (Split-Path $ConfigFile) 'job.json'
    if (Test-Path $jf) { try { $name = (Get-Content $jf -Raw | ConvertFrom-Json).name } catch {} }
    Set-JobChip -Name $name
    $win.Title = Lzd40aefb567 $name
    $script:Cfg = $null; $script:Projects = @(); $script:Map = @{}; $script:RunStatus = @{}
    Lzc219beec58
    Lzeb3a1395a1 -Text 'Not connected' -State off
    try { $script:Cfg = Import-ResolvedConfig $ConfigFile } catch {}
    Lz4ed508442b
    try {
        $cu = 0; $cd = 0
        if ($script:Cfg -and ($script:Cfg.run.PSObject.Properties.Name -contains 'bandwidth')) {
            $b = $script:Cfg.run.bandwidth
            if ($b.PSObject.Properties.Name -contains 'maxUploadMbps')   { $cu = [int]$b.maxUploadMbps }
            if ($b.PSObject.Properties.Name -contains 'maxDownloadMbps') { $cd = [int]$b.maxDownloadMbps }
        }
        $ctrl.TxtCapUp.Text = "$cu"; $ctrl.TxtCapDown.Text = "$cd"
    } catch {}
    try {
        $nest = $true
        if ($script:Cfg -and ($script:Cfg.destination.PSObject.Properties.Name -contains 'nestUnderProjectFolder')) {
            $nest = [bool]$script:Cfg.destination.nestUnderProjectFolder
        }
        $script:NestSuspend = $true
        $ctrl.ChkNest.IsChecked = $nest
        $script:NestSuspend = $false
    } catch { $script:NestSuspend = $false }
    try {
        $px = $false
        if ($script:Cfg -and ($script:Cfg.PSObject.Properties.Name -contains 'source') -and $script:Cfg.source -and
            ($script:Cfg.source.PSObject.Properties.Name -contains 'posix')) { $px = [bool]$script:Cfg.source.posix }
        if ($ctrl.ChkLinuxSrc) { $script:LinuxSuspend = $true; $ctrl.ChkLinuxSrc.IsChecked = $px; $script:LinuxSuspend = $false }
    } catch { $script:LinuxSuspend = $false }
    $script:JobOpen = $true
    $ctrl.BtnConnect.IsEnabled = $true; Lzdd341be2a9 $true
    if ($ctrl.BtnAddFolder) { $ctrl.BtnAddFolder.IsEnabled = $true }
    if ($ctrl.BtnRemoveFolder) { $ctrl.BtnRemoveFolder.IsEnabled = $true }
    Lz35d0f8dce4 $true
    Lz08b1f4f085 $ConfigFile
    try {
        if ($script:Cfg -and $script:Cfg.run.reportRoot) {
            $ra = Join-Path $script:Cfg.run.reportRoot 'run-active.json'
            if (Test-Path $ra) {
                Lzb80bda68cf -Status Incomplete -Note 'Recovering a previous run that did not finish...' -OnDone {
                    Lz5af601c665 'A previous run had not finished; it has been recorded as incomplete. Open the report to see what completed, then ''Sync new and changed'' to continue.'
                }
            }
        }
    } catch {}
}
function Remove-JobFolderWithRetry {
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path $Dir)) { return $true }
    for ($i = 0; $i -lt 5; $i++) {
        try { Remove-Item $Dir -Recurse -Force -ErrorAction Stop } catch {}
        if (-not (Test-Path $Dir)) { return $true }
        Start-Sleep -Milliseconds (200 * ($i + 1))
    }
    return (-not (Test-Path $Dir))
}
function Test-RealJobFolder {
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path $Dir)) { return $false }
    $cfg = Join-Path $Dir 'config.json'
    if (-not (Test-Path $cfg)) { return $false }
    try { $null = Read-ConfigJson $cfg; return $true } catch { return $false }
}
$ctrl.MnuJobNew.Add_Click({
  try {
    $name = Show-InputBox -Prompt "Name for this migration job (e.g. the company or project name):" -Title 'New migration job'
    if (-not $name -or -not $name.Trim()) { return }
    $name = $name.Trim()
    $slug = ($name -replace '[^A-Za-z0-9._-]','_').Trim('_'); if (-not $slug) { $slug = 'job' }
    $jobDir = Join-Path $script:JobsRoot $slug
    if (Test-RealJobFolder -Dir $jobDir) { (Show-Msg -Text ("A job named '$slug' already exists. Open it instead, or choose another name.")); return }
    if ((Test-Path $jobDir) -and -not (Remove-JobFolderWithRetry -Dir $jobDir)) {
        (Show-Msg -Text ("A leftover folder named '$slug' is still on disk and could not be removed because a file inside it is in use.`n`nClose anything open on it (a report or audit in a browser or Excel, or the folder in a File Explorer window), then try again.`n`nFolder: $jobDir")); return
    }
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
        $tmpl = Read-ConfigJson $script:ConfigPath
        $tmpl.run.tempWorkingFolder = Join-Path $jobDir 'temp'
        $tmpl.run.logRoot           = Join-Path $jobDir 'logs'
        $tmpl.run.reportRoot        = Join-Path $jobDir 'reports'
        $tmpl.run.stateRoot         = Join-Path $jobDir 'state'
        Lzcb55b64c1a -Cfg $tmpl -Path 'destination.nestUnderProjectFolder' -Value $false
        if ($tmpl.run.PSObject.Properties.Name -contains 'report') { $tmpl.run.report.brand = "$name - Liscaragh Migrate" }
        if ($script:TransferMode -eq 'LocalFs') {
            if (($tmpl.PSObject.Properties.Name -contains 'source') -and $tmpl.source) {
                if ($tmpl.source.PSObject.Properties.Name -contains 'provider') { $tmpl.source.provider = 'LocalFs' } else { $tmpl.source | Add-Member -NotePropertyName provider -NotePropertyValue 'LocalFs' -Force }
                if ($tmpl.source.PSObject.Properties.Name -contains 'localRoots') { $tmpl.source.localRoots = @() } else { $tmpl.source | Add-Member -NotePropertyName localRoots -NotePropertyValue @() -Force }
            } else {
                $tmpl | Add-Member -NotePropertyName source -NotePropertyValue ([pscustomobject]@{ provider = 'LocalFs'; localRoots = @() }) -Force
            }
        } else {
            if ($tmpl.PSObject.Properties.Name -contains 'source') { $tmpl.PSObject.Properties.Remove('source') }
        }
        Write-ConfigJson -Cfg $tmpl -Path (Join-Path $jobDir 'config.json')
        @{ name = $name; slug = $slug; sourceType = $script:TransferMode; created = (Get-Date).ToString('o'); tenantId = "$($tmpl.auth.tenantId)"; endpoint = "$($tmpl.datto.endpointUrl)"; notes = '' } | ConvertTo-Json | Set-Content -Path (Join-Path $jobDir 'job.json') -Encoding UTF8
        Set-CurrentJob -ConfigFile (Join-Path $jobDir 'config.json')
        if ($script:TransferMode -eq 'LocalFs') {
            (Show-Msg -Text ("Job '$name' is ready.`n`n1.  Click 'Add folder...' (top left) for each folder you want to copy - local or a network share.`n2.  Select a folder in the list, choose where its files should go on the right, then click 'Apply to this source'.`n3.  Use 'Check readiness' for a safe once-over, 'Preview' to see what would copy, then 'Full migration'.`n`nCopying is one-way: nothing in the source folders is ever changed or deleted, and nothing at the destination is ever deleted.") -Caption ('Job created') -Icon ('Information'))
        } else {
            (Show-Msg -Text ("Job '$name' is ready.`n`nYour projects will be listed automatically when you close this message. For each project you want to copy:`n`n1.  Select it in the list on the left.`n2.  On the right, optionally set a Source subfolder to copy just part of the project (leave it blank for the whole project).`n3.  Choose where its files should go, then click 'Apply to this project'.`n`nThe job keeps its own mapping, logs, reports and resume state, so it will not disturb your other jobs. It reuses the connection already set up on this computer.") -Caption ('Migration job created') -Icon ('Information'))
        }
        Start-AutoConnect
        try { Lz44faba9a81 } catch {}
    } catch {
        if ($jobDir -and (Test-Path $jobDir) -and -not (Test-RealJobFolder -Dir $jobDir)) { try { [void](Remove-JobFolderWithRetry -Dir $jobDir) } catch {} }
        (Show-Msg -Text ("The migration job could not be created.`n`nCheck the name has no unusual characters, and that you have permission to write to the jobs folder.`n`nTechnical detail: $($_.Exception.Message)"))
    }
})
$ctrl.MnuJobOpen.Add_Click({
    $jobs = @(Get-ChildItem $script:JobsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { (Test-Path (Join-Path $_.FullName 'config.json')) -and ((Get-JobSourceType (Join-Path $_.FullName 'config.json')) -eq $script:TransferMode) })
    if (-not $jobs.Count) { (Show-Msg -Text ("No " + (Get-TransferTypeMeta $script:TransferMode).Short + " jobs yet. Click New to create one. (Jobs of other transfer types are listed under their own type: Job > Switch transfer type.)")); return }
    $w = New-Object System.Windows.Window; $w.Title = 'Open migration job'; $w.Width = 460; $w.Height = 360
    Lz2e8ddc8b18 $w
    $w.WindowStartupLocation = 'CenterScreen'
    $sp = New-Object System.Windows.Controls.DockPanel; $sp.Margin = '12'
    $lb = New-Object System.Windows.Controls.ListBox
    foreach ($j in ($jobs | Sort-Object LastWriteTime -Descending)) {
        $nm = $j.Name; try { $nm = (Get-Content (Join-Path $j.FullName 'job.json') -Raw | ConvertFrom-Json).name } catch {}
        $it = New-Object System.Windows.Controls.ListBoxItem; $it.Content = $nm; $it.Tag = (Join-Path $j.FullName 'config.json'); [void]$lb.Items.Add($it)
    }
    $bp = New-Object System.Windows.Controls.StackPanel; $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.Margin = '0,10,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($bp, 'Bottom')
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'Open'; $ok.Padding = '16,4'; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $cn = New-Object System.Windows.Controls.Button; $cn.Content = 'Cancel'; $cn.Padding = '16,4'; $cn.IsCancel = $true
    [void]$bp.Children.Add($ok); [void]$bp.Children.Add($cn)
    $hdr = New-DialogHeader -Title 'Open migration job'; [void]$sp.Children.Add($hdr)
    [void]$sp.Children.Add($bp); [void]$sp.Children.Add($lb)
    $w.Content = $sp
    $script:OpenPick = $null; $script:OpenList = $lb; $script:OpenWin = $w
    $ok.Add_Click({ if ($script:OpenList.SelectedItem) { $script:OpenPick = $script:OpenList.SelectedItem.Tag; $script:OpenWin.DialogResult = $true } })
    $lb.Add_MouseDoubleClick({ if ($script:OpenList.SelectedItem) { $script:OpenPick = $script:OpenList.SelectedItem.Tag; $script:OpenWin.DialogResult = $true } })
    [void]$w.ShowDialog()
    if ($script:OpenPick) { Set-CurrentJob -ConfigFile $script:OpenPick; Start-AutoConnect }
})
$ctrl.MnuJobSave.Add_Click({
    if (-not $script:JobOpen) { (Show-Msg -Text ('Open or create a migration job first.')); return }
    if (Lzdf2842c3e6) { Lz5af601c665 'Migration job saved.' }
})
$ctrl.MnuJobSaveAs.Add_Click({
    if (-not $script:JobOpen) { (Show-Msg -Text ('Open a migration job first, then Save As to copy it.')); return }
    try {
        $name = Show-InputBox -Prompt "New name for the copy:" -Title 'Save job as'
        if (-not $name -or -not $name.Trim()) { return }
        $name = $name.Trim()
        $slug = ($name -replace '[^A-Za-z0-9._-]','_').Trim('_'); if (-not $slug) { $slug = 'job' }
        $jobDir = Join-Path $script:JobsRoot $slug
        if (Test-RealJobFolder -Dir $jobDir) { (Show-Msg -Text ("A job named '$slug' already exists. Choose another name.")); return }
        if ((Test-Path $jobDir) -and -not (Remove-JobFolderWithRetry -Dir $jobDir)) {
            (Show-Msg -Text ("A leftover folder named '$slug' is still on disk and could not be removed because a file inside it is in use. Close anything open on it, then try again.`n`nFolder: $jobDir")); return
        }
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
        $tmpl = Read-ConfigJson $script:ConfigPath
        $tmpl.run.tempWorkingFolder = Join-Path $jobDir 'temp'
        $tmpl.run.logRoot           = Join-Path $jobDir 'logs'
        $tmpl.run.reportRoot        = Join-Path $jobDir 'reports'
        $tmpl.run.stateRoot         = Join-Path $jobDir 'state'
        if ($tmpl.run.PSObject.Properties.Name -contains 'report') { $tmpl.run.report.brand = "$name - Liscaragh Migrate" }
        Write-ConfigJson -Cfg $tmpl -Path (Join-Path $jobDir 'config.json')
        @{ name = $name; slug = $slug; sourceType = $script:TransferMode; created = (Get-Date).ToString('o'); tenantId = "$($tmpl.auth.tenantId)"; endpoint = "$($tmpl.datto.endpointUrl)"; notes = 'Copied from another job.' } | ConvertTo-Json | Set-Content -Path (Join-Path $jobDir 'job.json') -Encoding UTF8
        $srcMap = Join-Path (Split-Path $script:ConfigPath) 'reports\mapping.csv'
        if (-not (Test-Path $srcMap)) { $srcMap = Join-Path ($script:Cfg.run.reportRoot) 'mapping.csv' }
        if (Test-Path $srcMap) { $newRep = Join-Path $jobDir 'reports'; New-Item -ItemType Directory -Path $newRep -Force | Out-Null; Copy-Item $srcMap (Join-Path $newRep 'mapping.csv') -Force }
        Set-CurrentJob -ConfigFile (Join-Path $jobDir 'config.json')
        (Show-Msg -Text ("Saved as '$name'. The destinations were copied, and your $($script:NItems) will be listed automatically when you close this message.") -Caption ('Saved as')) | Out-Null
        Start-AutoConnect
    } catch { (Show-Msg -Text ("Could not Save As: $($_.Exception.Message)")) }
})
$ctrl.MnuJobExit.Add_Click({ $win.Close() })
$ctrl.MnuSettingsChecklist.Add_Click({ Lzb52a94c8d8 })
$ctrl.MnuSettingsApi.Add_Click({ Lzcebee496ce })
$ctrl.MnuSettingsWizard.Add_Click({ Lz2aff4ed221 })
$ctrl.MnuSettingsEmail.Add_Click({ Lz0d05ab3822 })
$ctrl.MnuSettingsTuning.Add_Click({ Lz8af301bb21 })
$ctrl.BtnFilters.Add_Click({ Lz17569d9944 })
$ctrl.MnuSettingsDecommission.Add_Click({ Lz4a73e4b0de })
$ctrl.MnuHelpHowto.Add_Click({
    [void](Lze80902559b -Title 'How to use' -Heading 'How to use this tool' -Sections $script:QuickStartSections -No 'Close')
})
function Lz0f50cb0dd6 {
    param([string]$Text)
    $t = "$Text"
    foreach ($scope in @('Process','User','Machine')) {
        $s = $null
        try { $s = [Environment]::GetEnvironmentVariable('DATTO_CLIENT_SECRET', $scope) } catch {}
        if ($s -and "$s".Length -ge 6) { $t = $t.Replace("$s", '***REDACTED-DATTO-SECRET***') }
    }
    $s2 = Lzd2785bb3e8 'DATTO_CLIENT_SECRET'
    if ($s2 -and "$s2".Length -ge 6) { $t = $t.Replace("$s2", '***REDACTED-DATTO-SECRET***') }
    $t = [regex]::Replace($t, '(?i)\bBasic\s+[A-Za-z0-9+/=]{16,}',            'Basic ***REDACTED***')
    $t = [regex]::Replace($t, '(?i)\bBearer\s+[A-Za-z0-9\-\._~\+/=]{16,}',    'Bearer ***REDACTED***')
    return $t
}
function Build-SupportBundle {
    $stage = Join-Path ([IO.Path]::GetTempPath()) ("liscaragh-migrate-support-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $info = New-Object System.Collections.Generic.List[string]
        $info.Add("Liscaragh Migrate support bundle")
        $info.Add("Created            : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
        $info.Add("App version        : $($script:AppVersion)")
        $info.Add("PowerShell         : $($PSVersionTable.PSVersion)")
        $info.Add("OS                 : $([Environment]::OSVersion.VersionString)")
        $info.Add("Culture            : $([System.Globalization.CultureInfo]::CurrentCulture.Name)")
        $info.Add("Job                : $($ctrl.LblJob.Text)")
        $info.Add("Transfer type      : $((Get-TransferTypeMeta $script:TransferMode).Title)")
        $info.Add("Job config         : $($script:ConfigPath)")
        $info.Add("")
        $info.Add("Connection settings (values shown are identifiers, never secrets):")
        foreach ($k in 'DattoEndpointUrl','DattoClientId','TenantId','GraphClientId','SharePointRootUrl','OneDriveHostUrl','TeamSiteBaseUrl','DefaultSiteUrl','UpnDomain') {
            $v = [string](Get-RegSetting $k)
            $info.Add(("  {0,-20} {1}" -f $k, $(if ($v) { $v } else { '(not set)' })))
        }
        $sec = $null
        try { $sec = Lzff3ae1afba } catch {}
        $info.Add(("  {0,-20} {1}" -f 'Datto secret', $(if ($sec) { 'set (value NOT included)' } else { 'NOT SET' })))
        if ($script:TransferMode -eq 'LocalFs') { $info.Add("  (Datto values are used only by the Datto Workplace transfer type; blank/NOT SET is normal on a Files and folders machine.)") }
        $th = [string](Get-RegSetting 'CertThumbprint'); $certTxt = 'no thumbprint recorded'
        try { if ($th) { $c = Get-ChildItem "Cert:\CurrentUser\My\$th" -ErrorAction SilentlyContinue; $certTxt = if ($c -and $c.HasPrivateKey) { "installed, private key present, expires $($c.NotAfter)" } else { 'thumbprint recorded but certificate NOT installed' } } } catch {}
        $info.Add(("  {0,-20} {1}" -f 'CertThumbprint', $(if ($th) { 'set (thumbprint not included)' } else { '(not set)' })))
        $info.Add(("  {0,-20} {1}" -f 'Certificate', $certTxt))
        Set-Content -Path (Join-Path $stage 'system-info.txt') -Value ($info -join "`r`n") -Encoding UTF8
        try { Set-Content -Path (Join-Path $stage 'gui-window-log.txt') -Value (Lz0f50cb0dd6 "$($ctrl.TxtLog.Text)") -Encoding UTF8 } catch {}
        $copied = 0
        if ($script:Cfg) {
            $sets = @(
                @{ Src = $script:Cfg.run.logRoot;    Dest = 'logs';    Filter = '*.log' }
                @{ Src = $script:Cfg.run.reportRoot; Dest = 'reports'; Filter = '*.*'   }
            )
            foreach ($s in $sets) {
                if (-not $s.Src -or -not (Test-Path $s.Src)) { continue }
                $d = Join-Path $stage $s.Dest
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                foreach ($f in @(Get-ChildItem -Path $s.Src -Filter $s.Filter -File -ErrorAction SilentlyContinue)) {
                    try { Copy-Item $f.FullName -Destination $d -Force; $copied++ } catch {}
                }
            }
            try { if ($script:ConfigPath -and (Test-Path $script:ConfigPath)) { Set-Content -Path (Join-Path $stage 'job-config.json') -Value (Unprotect-ConfigText (Get-Content $script:ConfigPath -Raw)) -Encoding UTF8; $copied++ } } catch {}
        }
        foreach ($f in @(Get-ChildItem -Path $stage -Recurse -File -Include '*.log','*.txt','*.json','*.csv','*.html' -ErrorAction SilentlyContinue)) {
            try { Set-Content -Path $f.FullName -Value (Lz0f50cb0dd6 (Get-Content $f.FullName -Raw -ErrorAction Stop)) -Encoding UTF8 } catch {}
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeJob = (("$($ctrl.LblJob.Text)") -replace '[^\w\-]', '-') -replace '-+', '-'
        $zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "liscaragh-migrate-support-$safeJob-$stamp.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        return [pscustomobject]@{ Zip = $zip; Files = $copied; SizeMB = [math]::Round((Get-Item $zip).Length / 1MB, 1) }
    } catch {
        (Show-Msg -Text ("Could not build the support bundle: $($_.Exception.Message)`n`nYou can still email support@liscaragh.com and attach the files from your job folder by hand.") -Caption ('Email support'))
        return $null
    } finally { try { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
}
function Lz06f019535b {
    $rr = Lz675256916c
    $result = [pscustomobject]@{ ReportRoot = $rr; Audit = $null; Items = @() }
    if (-not $rr -or -not (Test-Path $rr)) { return $result }
    $audit = Get-ChildItem (Join-Path $rr 'audit-*.csv') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $result.Audit = $audit
    if (-not $audit) { return $result }
    function Lz9c97ad1b7d { param([string]$Pattern, [string[]]$Exclude)
        $f = @(Get-ChildItem (Join-Path $rr $Pattern) -File -ErrorAction SilentlyContinue)
        if ($Exclude) { foreach ($ex in $Exclude) { $f = @($f | Where-Object { $_.Name -notlike $ex }) } }
        return ($f | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    }
    $defs = @(
        @{ Key='Certificate';  Title='Completion certificate'; Desc='One-page sign-off certificate for this migration.'; OutName='certificate.html'; Pattern='certificate-*.html'; Exclude=$null; Mandatory=$true;  Action=@('-Action','Certificate'); RefMode='embed' }
        @{ Key='Verification'; Title='Verification';           Desc='Confirms every file arrived and is up to date.'; OutName='verification.html'; Pattern='report-validation-*.html'; Exclude=$null; Mandatory=$true; Action=@('-Action','Validate'); RefMode='time' }
        @{ Key='Report';       Title='Migration report';       Desc='The full, per-file migration report.'; OutName='migration-report.html'; Pattern='report-*.html'; Exclude=@('report-validation-*','report-sizecheck-*','report-preflight-*','report-drift-*','report-SourceReview-*'); Mandatory=$false; Action=@('-Action','Report'); RefMode='embed' }
        @{ Key='Provenance';   Title='Provenance pack';        Desc='Tamper-evident manifest of every migrated file, independently timestamped.'; OutName='provenance.html'; Pattern='provenance-*.html'; Exclude=$null; Mandatory=$false; Action=@('-Action','Provenance'); RefMode='embed' }
    )
    foreach ($d in $defs) {
        $f = Lz9c97ad1b7d $d.Pattern $d.Exclude
        $status = 'Missing'; $refAudit = $null
        if ($f) {
            if ($d.RefMode -eq 'embed') {
                try {
                    $raw = Get-Content $f.FullName -Raw -ErrorAction Stop
                    $m = [regex]::Match($raw, 'audit-[\w\.\-]+\.csv')
                    if ($m.Success) { $refAudit = $m.Value }
                } catch {}
                $status = if ($refAudit -and $refAudit -ne $audit.Name) { 'Stale' } else { 'OK' }
            } else {
                $status = if ($f.LastWriteTime -lt $audit.LastWriteTime) { 'Stale' } else { 'OK' }
            }
        }
        $result.Items += [pscustomobject]@{ Key=$d.Key; Title=$d.Title; Desc=$d.Desc; OutName=$d.OutName; File=$f; Status=$status; Mandatory=$d.Mandatory; Action=$d.Action; RefAudit=$refAudit }
    }
    return $result
}
function Lza8ba873bc1 {
    $rr = Lz675256916c
    if (-not $rr -or -not (Test-Path $rr)) { (Show-Msg -Text ('Open a migration job with at least one completed run first.') -Caption ('Handover pack') -Icon ('Information')) | Out-Null; return $null }
    $st = Lz06f019535b
    if (-not $st.Audit) {
        (Show-Msg -Text ("No completed run found for this job yet. A handover pack needs at least one finished run to build from: run Upload, then 'Sync new and changed' until nothing is left to copy, then try again.") -Caption ('Handover pack') -Icon ('Information')) | Out-Null
        return $null
    }
    $missingMandatory = @($st.Items | Where-Object { $_.Mandatory -and $_.Status -eq 'Missing' })
    if ($missingMandatory.Count) {
        $names = ($missingMandatory | ForEach-Object { $_.Title }) -join ' and '
        $plural = $missingMandatory.Count -gt 1
        return [pscustomobject]@{ Blocked = $true; BlockedReason = "$names $(if ($plural) { 'are required' } else { 'is required' }) before a handover pack can be built, and $(if ($plural) { 'have' } else { 'has' }) not been produced for this job yet. Click 'Handover pack' again and tick $(if ($plural) { 'them' } else { 'it' }) to run now." }
    }
    $have = @($st.Items | Where-Object { $_.File } | ForEach-Object {
        [pscustomobject]@{ File=$_.File; Name=$_.OutName; Title=$_.Title; Desc=$_.Desc; Stale=($_.Status -eq 'Stale') }
    })
    $have += [pscustomobject]@{ File=$st.Audit; Name='audit.csv'; Title='Audit (raw data)'; Desc='The raw per-file audit record this pack was built from.'; Stale=$false }
    $missing = @($st.Items | Where-Object { -not $_.File })
    $stale = @($have | Where-Object { $_.Stale })
    $stage = Join-Path ([IO.Path]::GetTempPath()) ("liscaragh-migrate-handover-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        foreach ($it in $have) { Copy-Item $it.File.FullName -Destination (Join-Path $stage $it.Name) -Force }
        $brand = 'Liscaragh Migrate'; $logoTag = ''; $client = ''
        if ($script:Cfg.run.PSObject.Properties.Name -contains 'report') {
            if (($script:Cfg.run.report.PSObject.Properties.Name -contains 'brand') -and $script:Cfg.run.report.brand) { $brand = "$($script:Cfg.run.report.brand)" }
            if (($script:Cfg.run.report.PSObject.Properties.Name -contains 'client') -and $script:Cfg.run.report.client) { $client = "$($script:Cfg.run.report.client)" }
            if (($script:Cfg.run.report.PSObject.Properties.Name -contains 'logo') -and $script:Cfg.run.report.logo -and (Test-Path $script:Cfg.run.report.logo)) {
                try {
                    $lb = [System.IO.File]::ReadAllBytes($script:Cfg.run.report.logo)
                    $ext = ([System.IO.Path]::GetExtension($script:Cfg.run.report.logo)).TrimStart('.').ToLower(); if ($ext -eq 'jpg') { $ext = 'jpeg' }
                    $logoTag = "<img class='logo' alt='logo' src='data:image/$ext;base64,$([Convert]::ToBase64String($lb))' />"
                } catch {}
            }
        }
        function _encH { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
        $subTitle = if ($client) { "Prepared for $client" } else { 'Migration handover' }
        $cardsHtml = ($have | ForEach-Object {
            $flag = if ($_.Stale) { " <span class='flag'>out of date - built from an earlier run</span>" } else { '' }
            "<li><a href='$($_.Name)'>$(_encH $_.Title)</a> - $(_encH $_.Desc)$flag</li>"
        }) -join "`n"
        $missBlock = if ($missing.Count) {
            $mi = ($missing | ForEach-Object { "<li>$(_encH $_.Title) - not included (not yet produced for this job)</li>" }) -join "`n"
            "<h2>Not included</h2><ul class='dim'>$mi</ul>"
        } else { '' }
        $staleBlock = if ($stale.Count) {
            "<h2>Notes</h2><p class='note'>$($stale.Count) item(s) above are flagged out of date: they were built from an earlier run than this pack's audit ($(_encH $st.Audit.Name)). They are still included, but may not fully match the other items. Rebuild the flagged item(s), then build this pack again, to bring everything into line.</p>"
        } else { '' }
        $when = (Get-Date).ToString('dd MMMM yyyy')
        $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_encH $brand) - Migration handover</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .wrap{max-width:760px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:40px 44px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:18px}
 .logo{height:52px}
 h1{font-size:22px;margin:0}
 .sub{color:#6b7280;font-size:13px;margin-top:3px}
 h2{font-size:13px;margin:24px 0 8px;color:#374151;text-transform:uppercase;letter-spacing:.5px}
 ul{margin:6px 0;padding-left:20px;font-size:14px;line-height:1.7}
 a{color:#2563eb;text-decoration:none}
 a:hover{text-decoration:underline}
 .dim{color:#9ca3af}
 .flag{color:#b45309;font-size:12px;font-weight:600}
 .note{font-size:13px;color:#92400e;background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:10px 14px;line-height:1.6}
 footer{margin-top:30px;color:#9ca3af;font-size:11px}
</style></head><body>
<div class='wrap'>
<header>$logoTag<div><h1>$(_encH $brand)</h1><div class='sub'>$(_encH $subTitle) &middot; $when</div></div></header>
<h2>Contents</h2>
<ul>$cardsHtml</ul>
$staleBlock
$missBlock
<footer>Open any item above in this same folder. This pack was assembled from the reports already produced for this job.</footer>
</div>
</body></html>
"@
        Set-Content -Path (Join-Path $stage 'index.html') -Value $html -Encoding UTF8
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeJob = (("$($ctrl.LblJob.Text)") -replace '[^\w\-]', '-') -replace '-+', '-'
        $zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "liscaragh-migrate-handover-$safeJob-$stamp.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        return [pscustomobject]@{ Blocked = $false; Zip = $zip; Included = $have.Count; Missing = $missing.Count; Stale = $stale.Count }
    } catch {
        (Show-Msg -Text ("Could not build the handover pack: $($_.Exception.Message)")) | Out-Null
        return $null
    } finally { try { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
}
function Lz87c9b00e46 {
    param($Status)
    $needAttn = @($Status.Items | Where-Object { $_.Status -ne 'OK' })
    $win = New-Object System.Windows.Window
    Lz2e8ddc8b18 $win
    $win.Title = 'Handover pack - items to prepare'; $win.SizeToContent = 'WidthAndHeight'; $win.WindowStartupLocation = 'CenterScreen'; $win.ResizeMode = 'NoResize'
    $win.FontFamily = 'Segoe UI'; $win.FontSize = 13; $win.Background = 'White'
    $dock = New-Object System.Windows.Controls.DockPanel
    $hdr = New-Object System.Windows.Controls.Border; $hdr.Background = '#0F1115'; $hdr.Padding = '20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
    $hs = New-Object System.Windows.Controls.StackPanel; $hs.MaxWidth = 520
    $ht = New-Object System.Windows.Controls.TextBlock; $ht.Text = 'Handover pack - items to prepare'; $ht.Foreground = 'White'; $ht.FontSize = 16; $ht.FontWeight = 'SemiBold'
    $hb = New-Object System.Windows.Controls.TextBlock
    $hb.Text = "Some items for this job's handover pack are missing or were built from an earlier run than the newest audit ($($Status.Audit.Name)). Certificate and Verification are required; the rest are optional. Tick what to run now."
    $hb.Foreground = '#9BA1AA'; $hb.TextWrapping = 'Wrap'; $hb.Margin = '0,4,0,0'
    [void]$hs.Children.Add($ht); [void]$hs.Children.Add($hb); $hdr.Child = $hs
    [void]$dock.Children.Add($hdr)
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '18,14,18,16'; $root.Width = 520
    $rowChecks = @{}
    foreach ($it in $needAttn) {
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,10'
        $chk = New-Object System.Windows.Controls.CheckBox; $chk.VerticalAlignment = 'Top'; $chk.Margin = '0,3,10,0'
        $forced = ($it.Mandatory -and $it.Status -eq 'Missing')
        $chk.IsChecked = $true
        if ($forced) { $chk.IsEnabled = $false }
        $textPanel = New-Object System.Windows.Controls.StackPanel
        $title = New-Object System.Windows.Controls.TextBlock; $title.FontWeight = 'SemiBold'
        $title.Text = $it.Title + $(if ($it.Mandatory) { ' (required)' } else { '' })
        $desc = New-Object System.Windows.Controls.TextBlock; $desc.TextWrapping = 'Wrap'; $desc.Foreground = 'Gray'; $desc.FontSize = 11.5; $desc.Margin = '0,1,0,0'
        $desc.Text = if ($it.Status -eq 'Missing') {
            if ($forced) { 'Not yet produced for this job. Required before a handover pack can be built.' } else { 'Not yet produced for this job. Left out of the pack if not ticked.' }
        } else {
            'Out of date: built from an earlier run. Included but flagged as out of date if not ticked.'
        }
        [void]$textPanel.Children.Add($title); [void]$textPanel.Children.Add($desc)
        [void]$row.Children.Add($chk); [void]$row.Children.Add($textPanel)
        [void]$root.Children.Add($row)
        $rowChecks[$it.Key] = $chk
    }
    $btnRow = New-Object System.Windows.Controls.DockPanel; $btnRow.LastChildFill = $false; $btnRow.Margin = '0,4,0,0'
    $rightWrap = New-Object System.Windows.Controls.StackPanel; $rightWrap.Orientation = 'Horizontal'; [System.Windows.Controls.DockPanel]::SetDock($rightWrap, 'Right')
    $runBtn = New-Object System.Windows.Controls.Button; $runBtn.Content = 'Run ticked, then build'; $runBtn.Padding = '14,4'; $runBtn.Margin = '0,0,8,0'; $runBtn.IsDefault = $true
    $buildBtn = New-Object System.Windows.Controls.Button; $buildBtn.Content = 'Build now instead'; $buildBtn.Padding = '14,4'; $buildBtn.Margin = '0,0,8,0'
    $buildBtn.ToolTip = 'Build the pack now with whatever already exists. Certificate and Verification must already exist for this to succeed.'
    $cancelBtn = New-Object System.Windows.Controls.Button; $cancelBtn.Content = 'Cancel'; $cancelBtn.Padding = '14,4'; $cancelBtn.IsCancel = $true
    [void]$rightWrap.Children.Add($runBtn); [void]$rightWrap.Children.Add($buildBtn); [void]$rightWrap.Children.Add($cancelBtn)
    [void]$btnRow.Children.Add($rightWrap)
    [void]$root.Children.Add($btnRow)
    [void]$dock.Children.Add($root); $win.Content = $dock
    $script:HovWin = $win
    $script:HovChecks = $rowChecks
    $script:HovResult = $null
    $runBtn.Add_Click({
        $ticked = @()
        foreach ($k in $script:HovChecks.Keys) { if ($script:HovChecks[$k].IsChecked) { $ticked += $k } }
        $script:HovResult = [pscustomobject]@{ Action = 'Run'; Ticked = $ticked }
        $script:HovWin.Close()
    })
    $buildBtn.Add_Click({
        $script:HovResult = [pscustomobject]@{ Action = 'BuildNow'; Ticked = @() }
        $script:HovWin.Close()
    })
    $cancelBtn.Add_Click({
        $script:HovResult = [pscustomobject]@{ Action = 'Cancel'; Ticked = @() }
        $script:HovWin.Close()
    })
    [void]$win.ShowDialog()
    $res = $script:HovResult
    $script:HovWin = $null; $script:HovChecks = $null; $script:HovResult = $null
    if (-not $res) { $res = [pscustomobject]@{ Action = 'Cancel'; Ticked = @() } }
    return $res
}
function Lzb5b838cac6 {
    if (-not $script:HovQueue -or $script:HovQueue.Count -eq 0) {
        $done = $script:HovOnDone
        $script:HovQueue = $null; $script:HovOnDone = $null; $script:HovCurrent = $null
        if ($done) { & $done }
        return
    }
    $script:HovCurrent = $script:HovQueue.Dequeue()
    Lzb1483e070e -EngineArgs $script:HovCurrent.Action -Label $script:HovCurrent.Title -OnComplete {
        Lzb5b838cac6
    }
}
function Lz8c3521449f {
    param([array]$Queue, [scriptblock]$OnDone)
    if (-not $Queue -or $Queue.Count -eq 0) { if ($OnDone) { & $OnDone }; return }
    $script:HovQueue = New-Object System.Collections.Generic.Queue[object]
    foreach ($q in $Queue) { $script:HovQueue.Enqueue($q) }
    $script:HovOnDone = $OnDone
    Lzb5b838cac6
}
function Lzfb875adafc {
    Set-Busy $true 'Building the handover pack...'
    try { $b = Lza8ba873bc1 } finally { Set-Busy $false }
    if (-not $b) { return }
    if ($b.Blocked) {
        (Show-Msg -Text $b.BlockedReason -Caption ('Handover pack') -Icon ('Warning')) | Out-Null
        return
    }
    try { Start-Process 'explorer.exe' -ArgumentList "/select,`"$($b.Zip)`"" } catch {}
    $notes = @()
    if ($b.Missing -gt 0) { $notes += "$($b.Missing) optional item(s) were left out (not yet produced)" }
    if ($b.Stale -gt 0) { $notes += "$($b.Stale) item(s) are flagged as out of date in the pack" }
    $noteText = if ($notes.Count) { " $($notes -join '; ') - see the pack's index.html for detail." } else { '' }
    (Show-Msg -Text ("Handover pack built: $($b.Zip)`n`nIt contains $($b.Included) item(s) plus an index.html cover page, ready to send to the client.$noteText") -Caption ('Handover pack') -Icon ('Information')) | Out-Null
}
function Lz629ddae0f6 {
    $st = Lz06f019535b
    if (-not $st.ReportRoot -or -not (Test-Path $st.ReportRoot)) {
        (Show-Msg -Text ('Open a migration job with at least one completed run first.') -Caption ('Handover pack') -Icon ('Information')) | Out-Null
        return
    }
    if (-not $st.Audit) {
        (Show-Msg -Text ("No completed run found for this job yet. A handover pack needs at least one finished run to build from: run Upload, then 'Sync new and changed' until nothing is left to copy, then try again.") -Caption ('Handover pack') -Icon ('Information')) | Out-Null
        return
    }
    $needAttn = @($st.Items | Where-Object { $_.Status -ne 'OK' })
    if (-not $needAttn.Count) { Lzfb875adafc; return }
    $res = Lz87c9b00e46 -Status $st
    if ($res.Action -eq 'Cancel') { return }
    if ($res.Action -eq 'BuildNow' -or -not $res.Ticked.Count) { Lzfb875adafc; return }
    $queue = @($st.Items | Where-Object { $res.Ticked -contains $_.Key } | ForEach-Object { @{ Key = $_.Key; Title = $_.Title; Action = $_.Action } })
    Lz8c3521449f -Queue $queue -OnDone { Lzfb875adafc }
}
function Lzafc174b332 {
    param($Config)
    $mapPath = Join-Path $Config.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $mapPath)) { return @() }
    return @(Import-Csv $mapPath | Where-Object { "$($_.Action)".Trim().ToUpper() -eq 'MIGRATE' })
}
function Lzdcbc49e58d {
    $rr = Lz675256916c
    if (-not $rr -or -not (Test-Path $rr)) { (Show-Msg -Text ('Open a migration job first.') -Caption ('Cutover comms pack') -Icon ('Information')) | Out-Null; return $null }
    if (-not (Lzdf2842c3e6)) { return $null }
    $rows = Lzafc174b332 -Config $script:Cfg
    if (-not $rows.Count) { (Show-Msg -Text ('This job has no mapped destinations yet. Choose what to copy and where it lands, apply the mapping, and try again.') -Caption ('Cutover comms pack') -Icon ('Information')) | Out-Null; return $null }
    function _encC { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
    $brand = 'Liscaragh Migrate'; $logoTag = ''; $client = ''
    if ($script:Cfg.run.PSObject.Properties.Name -contains 'report') {
        if (($script:Cfg.run.report.PSObject.Properties.Name -contains 'brand') -and $script:Cfg.run.report.brand) { $brand = "$($script:Cfg.run.report.brand)" }
        if (($script:Cfg.run.report.PSObject.Properties.Name -contains 'client') -and $script:Cfg.run.report.client) { $client = "$($script:Cfg.run.report.client)" }
        if (($script:Cfg.run.report.PSObject.Properties.Name -contains 'logo') -and $script:Cfg.run.report.logo -and (Test-Path $script:Cfg.run.report.logo)) {
            try {
                $lb = [System.IO.File]::ReadAllBytes($script:Cfg.run.report.logo)
                $ext = ([System.IO.Path]::GetExtension($script:Cfg.run.report.logo)).TrimStart('.').ToLower(); if ($ext -eq 'jpg') { $ext = 'jpeg' }
                $logoTag = "<img class='logo' alt='logo' src='data:image/$ext;base64,$([Convert]::ToBase64String($lb))' />"
            } catch {}
        }
    }
    $orgName = if ($client) { $client } else { 'your organisation' }
    $stage = Join-Path ([IO.Path]::GetTempPath()) ("liscaragh-migrate-comms-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $hasOneDrive = (@($rows | Where-Object { $_.DestinationType -eq 'OneDrive' }).Count -gt 0)
        $hasSharePoint = (@($rows | Where-Object { $_.DestinationType -ne 'OneDrive' }).Count -gt 0)
        if ($hasOneDrive) {
            $t = @"
Subject: Your files have moved to OneDrive

Hi,

Over [migration window], we moved your files from the old file server into Microsoft 365. They are now in your OneDrive, where they are backed up automatically and available from any device you sign into with your work account.

What to do:
1. Open OneDrive (the blue cloud icon near the clock, or onedrive.com signed in with your work account).
2. Your files will be under a folder matching their old location. Nothing has been renamed.
3. If you use the OneDrive app on this PC, files sync down automatically - give it a few minutes the first time.
4. The old file server location is being retired. Please save anything new directly to OneDrive from now on.

If a file looks like it's missing, check OneDrive's search first - it searches the full folder structure, not just what's synced to this PC. If you still can't find something, contact IT with the file's old location and we'll help track it down.

Thanks,
$orgName IT
"@
            Set-Content -Path (Join-Path $stage 'email-onedrive.txt') -Value $t -Encoding UTF8
        }
        if ($hasSharePoint) {
            $t = @"
Subject: Your team's files have moved to SharePoint

Hi,

Over [migration window], we moved [team/project] files from the old file server into a Microsoft 365 SharePoint site. Everyone with access before still has access now - nothing to request.

What to do:
1. Open the site: [SharePoint site link].
2. Files are under Documents, in the same folder structure as before.
3. To work with the files from File Explorer or get them showing under This PC, open the site, go to the Documents library, and choose Sync (or "Add shortcut to OneDrive").
4. The old file server location is being retired. Please save anything new to the SharePoint site from now on.

If you can't see a folder you expect, contact IT and we'll check your permissions.

Thanks,
$orgName IT
"@
            Set-Content -Path (Join-Path $stage 'email-sharepoint.txt') -Value $t -Encoding UTF8
        }
        $rowsHtml = ($rows | Select-Object -First 200 | ForEach-Object {
            $dest = if ($_.DestinationType -eq 'OneDrive') { "OneDrive ($($_.TargetPrincipal))" } else { (@("$($_.DestinationUrl)", "$($_.TargetLibrary)") | Where-Object { "$_".Trim() }) -join ' / ' }
            "<tr><td>$(_encC $_.Space)</td><td>$(_encC $dest)</td></tr>"
        }) -join "`n"
        $onePager = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>Finding your files</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .wrap{max-width:760px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:40px 44px}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:18px}
 .logo{height:48px}
 h1{font-size:20px;margin:0}
 h2{font-size:14px;margin:22px 0 8px}
 table{border-collapse:collapse;width:100%;font-size:13px}
 th,td{border:1px solid #e5e7eb;padding:6px 10px;text-align:left}
 th{background:#f9fafb}
 ol{font-size:14px;line-height:1.8}
</style></head><body><div class='wrap'>
<header>$logoTag<h1>Finding your files after the move</h1></header>
<h2>Where things went</h2>
<table><thead><tr><th>Old location</th><th>New location</th></tr></thead><tbody>$rowsHtml</tbody></table>
<h2>OneDrive</h2>
<ol>
 <li>Click the blue/white cloud icon near the clock, or go to onedrive.com and sign in with your work account.</li>
 <li>Your files are under a folder matching their old name - nothing has been renamed.</li>
 <li>On a work PC the OneDrive app syncs files down automatically; give it a few minutes the first time.</li>
</ol>
<h2>SharePoint (shared/team folders)</h2>
<ol>
 <li>Open the site link IT gave you and go to Documents.</li>
 <li>To see it in File Explorer like a normal folder, choose Sync (or "Add shortcut to OneDrive") on the Documents library.</li>
 <li>Access follows what you had before - nothing to request unless IT tells you otherwise.</li>
</ol>
<h2>Can't find something?</h2>
<p>Search first - both OneDrive and SharePoint search the full folder structure, not just what has synced to this PC. Still stuck? Contact IT with the file's old location.</p>
</div></body></html>
"@
        Set-Content -Path (Join-Path $stage 'finding-your-files.html') -Value $onePager -Encoding UTF8
        $noteRows = ($rows | ForEach-Object {
            $isOd = ($_.DestinationType -eq 'OneDrive')
            $note = if ($isOd) {
                "OneDrive: use Intune's Known Folder Move (OneDrive sync app configuration profile) so Desktop/Documents/Pictures redirect automatically; no drive letter needed. If a mapped drive letter is still wanted for a script or shortcut, point it at the user's local OneDrive sync path (%OneDriveCommercial%\...), not a UNC path - OneDrive has no UNC share."
            } else {
                "SharePoint: sync the library (Sync button, or 'Add shortcut to OneDrive') so it appears under This PC with a local path; there is no true network drive letter for a SharePoint library. For a GPO logon script that still needs a drive letter, map it to the synced local path once sync is confirmed on the device, or migrate the script to use the site URL directly."
            }
            $dest = if ($isOd) { "OneDrive ($($_.TargetPrincipal))" } else { (@("$($_.DestinationUrl)", "$($_.TargetLibrary)") | Where-Object { "$_".Trim() }) -join ' / ' }
            "<tr><td>$(_encC $_.Space)</td><td>$(_encC $dest)</td><td>$(_encC $note)</td></tr>"
        }) -join "`n"
        $notesHtml = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>Intune / GPO mapped-drive notes</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .wrap{max-width:900px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:40px 44px}
 table{border-collapse:collapse;width:100%;font-size:13px}
 th,td{border:1px solid #e5e7eb;padding:8px 10px;text-align:left;vertical-align:top}
 th{background:#f9fafb}
 p.dim{color:#6b7280;font-size:13px}
</style></head><body><div class='wrap'>
<h1>Intune / GPO mapped-drive notes, per mapping</h1>
<p class='dim'>Classic drive-letter mapping does not apply to Microsoft 365 the way it did to the old file server: OneDrive and SharePoint are reached by sync, not by UNC path. These notes say what to configure instead for each destination below.</p>
<table><thead><tr><th>Old location</th><th>New destination</th><th>Notes for IT</th></tr></thead><tbody>$noteRows</tbody></table>
</div></body></html>
"@
        Set-Content -Path (Join-Path $stage 'mapped-drive-notes.html') -Value $notesHtml -Encoding UTF8
        $when = (Get-Date).ToString('dd MMMM yyyy')
        $subTitle = if ($client) { "Cutover comms pack for $client" } else { 'Cutover comms pack' }
        $files = @(Get-ChildItem $stage -File)
        $list = ($files | ForEach-Object { "<li><a href='$($_.Name)'>$(_encC $_.Name)</a></li>" }) -join "`n"
        $cover = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>$(_encC $brand) - Cutover comms pack</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;color:#1f2937;margin:0;padding:32px;background:#f8fafc}
 .wrap{max-width:760px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:40px 44px}
 header{display:flex;align-items:center;gap:16px;border-bottom:2px solid #e5e7eb;padding-bottom:18px}
 .logo{height:52px}
 h1{font-size:22px;margin:0}
 .sub{color:#6b7280;font-size:13px;margin-top:3px}
 ul{font-size:14px;line-height:1.8}
 a{color:#2563eb;text-decoration:none}
</style></head><body><div class='wrap'>
<header>$logoTag<div><h1>$(_encC $brand)</h1><div class='sub'>$(_encC $subTitle) &middot; $when</div></div></header>
<p>Everything here is a template or note for whoever runs the cutover with end users - edit the bracketed placeholders (migration window, site links) before sending.</p>
<ul>$list</ul>
</div></body></html>
"@
        Set-Content -Path (Join-Path $stage 'index.html') -Value $cover -Encoding UTF8
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeJob = (("$($ctrl.LblJob.Text)") -replace '[^\w\-]', '-') -replace '-+', '-'
        $zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "liscaragh-migrate-comms-$safeJob-$stamp.zip"
        if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        return [pscustomobject]@{ Zip = $zip; Mappings = $rows.Count }
    } catch {
        (Show-Msg -Text ("Could not build the cutover comms pack: $($_.Exception.Message)")) | Out-Null
        return $null
    } finally { try { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
}
$ctrl.MnuHelpSupport.Add_Click({
    $ver = $script:AppVersion
    $tid = [string](Get-RegSetting 'TenantId')
    $job = "$($ctrl.LblJob.Text)"
    Set-Busy $true 'Collecting logs and reports for support...'
    try { $b = Build-SupportBundle } finally { Set-Busy $false }
    if (-not $b) { return }
    $body = "Describe the problem here." + "`n`n--- Details (please keep) ---`n" + "Version: $ver`n" + "Tenant: $tid`n" + "Job: $job`n`n" +
            "PLEASE ATTACH THIS FILE (it is on your Desktop):`n$($b.Zip)`n`n" +
            "It contains this job's logs, reports and config ($($b.Files) file(s), $($b.SizeMB) MB). Passwords and access tokens have been removed automatically."
    try { Start-Process 'explorer.exe' -ArgumentList "/select,`"$($b.Zip)`"" } catch {}
    $uri = "mailto:support@liscaragh.com?subject=" + [uri]::EscapeDataString("Liscaragh Migrate support - $job") + "&body=" + [uri]::EscapeDataString($body)
    try { Start-Process $uri } catch { (Show-Msg -Text ("Could not open your email app. Please email support@liscaragh.com and include:`n`n$body")) }
})
function Lz61a3428c8d { return (Join-Path (Split-Path $PSScriptRoot -Parent) 'licence.json') }
function Lz71ba9dfe7e {
    $path = Lz61a3428c8d
    if (-not (Test-Path $path)) { return "No licence installed.`n`nWithout one you can test the connection, list projects and run 'Compare sizes'. Copying files and 'Verify files arrived' need a licence: Help > Install licence file. To buy one: support@liscaragh.com" }
    try {
        $j = Get-Content $path -Raw | ConvertFrom-Json
        $pl = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$($j.PayloadB64)")) | ConvertFrom-Json
        $exp = "$($pl.Expires)"; $expTxt = if ($exp) { "expires $exp" } else { 'no expiry (for life)' }
        return "Licensed to : $($pl.Customer)`nMicrosoft tenant : $($pl.TenantId)`nLicence ID : $($pl.LicenceId)`nIssued : $($pl.Issued)  ($expTxt)`nFile : $path`n`nEach licence covers exactly one Microsoft 365 tenant and cannot be moved to another. The licence is checked, and its tenant matched against the live connection, every time a run starts."
    } catch { return "A licence file exists at $path but could not be read: $($_.Exception.Message)`n`nReinstall it via Help > Install licence file." }
}
$ctrl.MnuHelpLicence.Add_Click({ (Show-Msg -Text ("Liscaragh Migrate" + "`n" + "(c) Liscaragh Software. All rights reserved." + "`n`n" + (Lz71ba9dfe7e)) -Caption ('Licence')) | Out-Null })
function Lz3c9a617c91 {
    $nl = [Environment]::NewLine
    return ("Available now, without a licence:" + $nl +
            "   - Connect to Datto and Microsoft 365" + $nl +
            "   - List your projects" + $nl +
            "   - Preview exactly what a migration would copy (nothing is copied)" + $nl +
            "   - Compare sizes between Datto and the destination" + $nl +
            "   - Copy up to $($script:TrialLimitDisplay) of your own files for real, to prove it works, then Verify them" + $nl +
            "   - A further $($script:TrialLimitDisplay) files via Sync, to prove that too" + $nl + $nl +
            "Needs a licence:" + $nl +
            "   - Migrating beyond those files (a full Upload or Sync of everything)")
}
function Lzc518af296f {
    $nl = [Environment]::NewLine
    $body = "This copy is running in unlicensed (evaluation) mode." + $nl + $nl +
            "You can evaluate a full migration without a licence - connect, list, Preview and Compare all work, and you can copy up to $($script:TrialLimitDisplay) of your own files for real to prove it end to end, then Verify them - so you can see exactly what a migration does before you buy." + $nl + $nl +
            (Lz3c9a617c91) + $nl + $nl +
            "Each licence covers one Microsoft 365 tenant, for life. To obtain one, visit https://www.liscaragh.com (or email support@liscaragh.com), then install it here via Help > Install licence file."
    (Show-Msg -Text $body -Caption 'Unlicensed (evaluation) mode' -Icon 'Information') | Out-Null
}
function Lz412c2d92aa {
    param([string]$Detail = '')
    $body = "This step needs a licence." + [Environment]::NewLine + [Environment]::NewLine +
            "Uploading, syncing and verifying act on your real data, so each needs a licence for this Microsoft 365 tenant. Without one you can still test the connection, list projects, Preview what would copy (nothing is copied), and Compare sizes - so you can see exactly what a migration would do before you buy." + [Environment]::NewLine + [Environment]::NewLine
    if ($Detail) { $body += $Detail + [Environment]::NewLine + [Environment]::NewLine }
    $body += "To obtain a licence, visit https://www.liscaragh.com (or email support@liscaragh.com). When you receive the licence file, install it here via Help > Install licence file."
    (Show-Msg -Text $body -Caption 'Licence required') | Out-Null
}
function Lzd08008ed5a {
    param([string]$For = 'copy')
    if (Test-Path (Lz61a3428c8d)) { return $true }
    if ($For -eq 'verify') { return $true }
    $nl = [Environment]::NewLine
    $body = "You do not have a licence installed, so this runs in evaluation mode." + $nl + $nl +
            "Up to $($script:TrialLimitDisplay) file(s) will be copied for real into this Microsoft 365 tenant, so you can prove the migration works end to end. It then stops. This is a sample, not a full migration: each tenant gets $($script:TrialLimitDisplay) free files this way, and $($script:TrialLimitDisplay) more via Sync." + $nl + $nl +
            "To migrate everything, licence this tenant at https://www.liscaragh.com, then install it via Help > Install licence file." + $nl + $nl +
            "Copy up to $($script:TrialLimitDisplay) file(s) now?"
    return ((Show-Msg -Text $body -Caption 'Evaluation mode' -Buttons 'YesNo' -Icon 'Warning') -eq 'Yes')
}
function Lz5e54cee147 {
    $nl = [Environment]::NewLine
    $what = if ($script:TrialBucketLabel -eq 'FirstPass') { 'full copy' } else { 'sync' }
    $body = "The free evaluation for this Microsoft 365 tenant is used up." + $nl + $nl +
            "It has already had its $($script:TrialLimitDisplay) free $what file(s). Nothing was copied this time, and nothing was changed." + $nl + $nl +
            "You can still test the connection, list projects, Preview what would copy, Compare sizes, and Verify what is already there." + $nl + $nl +
            "To migrate everything into this tenant, licence it at https://www.liscaragh.com (or email support@liscaragh.com), then install the licence via Help > Install licence file."
    (Show-Msg -Text $body -Caption 'Evaluation used up' -Icon 'Warning') | Out-Null
}
function Lz1d511668f8 {
    param([int]$Copied = 0)
    $nl = [Environment]::NewLine
    $body = "It works. $Copied file(s) were copied for real into this Microsoft 365 tenant and are ready to verify." + $nl + $nl +
            "This was an evaluation run, so it stopped at the $($script:TrialLimitDisplay)-file limit. That is enough to prove the migration end to end on your own data; it is not a full migration." + $nl + $nl +
            "To migrate everything into this tenant, licence it at https://www.liscaragh.com (or email support@liscaragh.com), then install the licence via Help > Install licence file."
    (Show-Msg -Text $body -Caption 'Evaluation copy complete' -Icon 'Warning') | Out-Null
}
$ctrl.MnuHelpLicInstall.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Licence file (*.json)|*.json|All files (*.*)|*.*'
    $dlg.Title = 'Choose the licence file you were sent'
    if (-not $dlg.ShowDialog()) { return }
    try {
        $j = Get-Content $dlg.FileName -Raw | ConvertFrom-Json
        if (-not ($j.PSObject.Properties.Name -contains 'PayloadB64') -or -not ($j.PSObject.Properties.Name -contains 'Signature')) { throw 'that file is not a licence file (it has no licence payload).' }
        $dest = Lz61a3428c8d
        Copy-Item -LiteralPath $dlg.FileName -Destination $dest -Force
        try {
            $lpl = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$($j.PayloadB64)")) | ConvertFrom-Json
            Lz933059a102 -Name 'LicenceAppliedId'  -Value "$($lpl.LicenceId)"
            Lz933059a102 -Name 'LicenceAppliedUtc' -Value ((Get-Date).ToUniversalTime().ToString('o'))
        } catch {}
        (Show-Msg -Text ("Licence installed.`n`n" + (Lz71ba9dfe7e)) -Caption 'Licence installed') | Out-Null
    } catch {
        (Show-Msg -Text ("That file could not be installed: $($_.Exception.Message)") -Caption 'Licence') | Out-Null
    }
})
$script:UpdateBaseUrl      = 'https://raw.githubusercontent.com/davedevery/liscaraghdattomigpublic/main/'
$script:UpdatePublicKeyB64 = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEY09KDt0K0idwv1Si4vkMctPwR8tI5ZRNilAMf6dKD0F50svjJ997TnrhzlX7oXBBIRIVfWQCMVMI+U/DG+jHEw=='
function Test-SafeInstallPath {
    param([string]$InstallDir,[string]$Rel)
    if ([string]::IsNullOrWhiteSpace($Rel)) { return $false }
    if ($Rel -match '[:*?"<>|]') { return $false }
    if ($Rel -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    if ([System.IO.Path]::IsPathRooted($Rel)) { return $false }
    $root = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd([char]92,[char]47) + [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath((Join-Path $InstallDir $Rel))
    return $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
}
function ConvertFrom-UpdateDescriptor {
    param([string]$Json,[string]$PublicKeyB64)
    if ([string]::IsNullOrWhiteSpace($PublicKeyB64)) { throw 'Updates are not available in this build (no update key).' }
    $desc = $Json | ConvertFrom-Json
    if (-not ($desc.PayloadB64 -and $desc.Signature)) { throw 'The update information is not in the expected format.' }
    $payloadBytes = [Convert]::FromBase64String("$($desc.PayloadB64)")
    $sigBytes     = [Convert]::FromBase64String("$($desc.Signature)")
    $ec = [System.Security.Cryptography.ECDsa]::Create()
    try {
        $read = 0
        $ec.ImportSubjectPublicKeyInfo([Convert]::FromBase64String($PublicKeyB64), [ref]$read)
        if (-not $ec.VerifyData($payloadBytes, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256)) {
            throw 'The update failed its signature check (not issued by Liscaragh, or altered in transit). Nothing has been changed.'
        }
    } finally { $ec.Dispose() }
    return ([System.Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json)
}
function Get-FileSha256Hex { param([string]$Path) return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower() }
function Invoke-FullReinstall {
    param($Payload)
    $fi = $Payload.fullInstall
    $url = "$($fi.url)"; $sha = "$($fi.sha256)".ToLower()
    if (-not $url -or -not $sha) { (Show-Msg -Text ("Version $($Payload.version) needs a full reinstall, but the update did not include an installer. Please re-run the full installer by hand, or contact support@liscaragh.com. Nothing has been changed.") -Caption ('Reinstall required') -Icon ('Warning')) | Out-Null; return }
    $confirm = "Version $($Payload.version) needs a full reinstall (this installation is too old to update in place).`n`nYour migration jobs, logs, reports, licence and connection settings are all kept - they live outside the program folder and the installer does not touch them.`n`nThe app will download the installer, close, install, and reopen. Continue?"
    if ((Show-Msg -Text $confirm -Caption ('Reinstall required') -Buttons ('YesNo') -Icon ('Warning')) -ne 'Yes') { return }
    Set-Busy $true "Downloading the installer for version $($Payload.version)..."
    $exe = Join-Path ([System.IO.Path]::GetTempPath()) ("LiscaraghMigrate-" + ("$($Payload.version)" -replace '[^0-9A-Za-z.]','') + "-" + [guid]::NewGuid().ToString('N') + ".exe")
    try { Invoke-WebRequest -Uri ($script:UpdateBaseUrl + $url) -OutFile $exe -UseBasicParsing -TimeoutSec 600 }
    catch { Set-Busy $false; (Show-Msg -Text ("The installer could not be downloaded, so nothing has been changed.`n`n$($_.Exception.Message)") -Caption ('Reinstall') -Icon ('Warning')) | Out-Null; return }
    if ((Get-FileSha256Hex -Path $exe) -ne $sha) {
        Set-Busy $false
        try { Remove-Item $exe -Force -ErrorAction SilentlyContinue } catch {}
        (Show-Msg -Text ("The downloaded installer did not match its checksum, so it was refused and deleted. Nothing has been changed.`n`nThis usually means a corrupted download; try again. If it keeps happening, contact support@liscaragh.com.") -Caption ('Reinstall refused') -Icon ('Error')) | Out-Null
        return
    }
    Set-Busy $false
    try { $base = Split-Path $PSScriptRoot -Parent; if ($base) { Set-Content -Path (Join-Path $base '.reinstalling') -Value "$($Payload.version)" -Encoding UTF8 -ErrorAction SilentlyContinue } } catch {}
    try {
        Start-Process -FilePath $exe
        (Show-Msg -Text ("The installer for version $($Payload.version) is starting. This app will now close, and it reopens automatically when the reinstall finishes.`n`nIf it does not reopen, launch it from the Start menu or desktop shortcut as usual. Your jobs and settings are unaffected.") -Caption ('Reinstalling')) | Out-Null
        try { $win.Close() } catch {}
        try { [System.Windows.Application]::Current.Shutdown() } catch {}
    } catch {
        (Show-Msg -Text ("Could not start the installer: $($_.Exception.Message)`n`nNothing has been changed. You can run the installer by hand from:`n$exe") -Caption ('Reinstall') -Icon ('Warning')) | Out-Null
    }
}
function Invoke-UpdateApply {
    param([string]$InstallDir,[string]$StageDir,$Payload,[string]$BackupDir)
    $applied = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($f in $Payload.files) {
            if (-not (Test-SafeInstallPath -InstallDir $InstallDir -Rel "$($f.path)")) { throw "The update refers to an unsafe path ('$($f.path)') and was rejected." }
        }
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
        foreach ($f in $Payload.files) {
            $op = "$($f.op)".ToLower()
            $target = Join-Path $InstallDir "$($f.path)"
            $existed = Test-Path $target
            $bak = $null
            if ($existed) {
                $bak = Join-Path $BackupDir "$($f.path)"
                $bd = Split-Path $bak -Parent; if (-not (Test-Path $bd)) { New-Item -ItemType Directory -Path $bd -Force | Out-Null }
                Copy-Item -Path $target -Destination $bak -Force
            }
            if ($op -eq 'put') {
                $src = Join-Path $StageDir "$($f.path)"
                if (-not (Test-Path $src)) { throw "A file for the update is missing ('$($f.path)')." }
                $pin = "$($f.sha256)".ToLower()
                if ($pin -notmatch '^[0-9a-f]{64}$' -or (Get-FileSha256Hex -Path $src) -ne $pin) { throw "A staged update file failed its checksum just before install ('$($f.path)'). Nothing was changed." }
                $td = Split-Path $target -Parent; if (-not (Test-Path $td)) { New-Item -ItemType Directory -Path $td -Force | Out-Null }
                Copy-Item -Path $src -Destination $target -Force
            } elseif ($op -eq 'delete') {
                if ($existed) { Remove-Item -Path $target -Force }
            } else { throw "The update contains an unknown instruction ('$op')." }
            $applied.Add(@{ Op=$op; Target=$target; Existed=$existed; Backup=$bak })
        }
        return $null
    } catch {
        $err = "$($_.Exception.Message)"
        for ($i = $applied.Count - 1; $i -ge 0; $i--) {
            $a = $applied[$i]
            try {
                if ($a.Existed -and $a.Backup -and (Test-Path $a.Backup)) { Copy-Item -Path $a.Backup -Destination $a.Target -Force }
                elseif ($a.Op -eq 'put' -and -not $a.Existed -and (Test-Path $a.Target)) { Remove-Item -Path $a.Target -Force }
            } catch {}
        }
        return "The update could not be applied and was rolled back. $err"
    }
}
function Invoke-UpdateCheck {
    param([switch]$Silent)
    try {
        if ($script:Proc -and -not $script:Proc.HasExited) {
            if (-not $Silent) { (Show-Msg -Text 'A migration is running. Let it finish, or stop it, before checking for updates.' -Caption ('Check for updates') -Buttons ('OK') -Icon ('Warning')) | Out-Null }
            return
        }
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
        if (-not $Silent) { Set-Busy $true 'Checking for updates...' }
        $descJson = $null
        try { $descJson = (Invoke-WebRequest -Uri ($script:UpdateBaseUrl + 'update.json') -UseBasicParsing -TimeoutSec 30).Content }
        catch { throw "Could not reach the update service. Check the internet connection and try again. ($($_.Exception.Message))" }
        $payload = ConvertFrom-UpdateDescriptor -Json "$descJson" -PublicKeyB64 $script:UpdatePublicKeyB64
        $cur = [version]"$($script:AppVersion)"; $new = [version]"$($payload.version)"
        if ($new -le $cur) {
            Set-Busy $false
            if (-not $Silent) { (Show-Msg -Text "You are on the latest version ($($script:AppVersion))." -Caption ('Check for updates')) | Out-Null }
            return
        }
        if (($payload.PSObject.Properties.Name -contains 'minVersion') -and $payload.minVersion -and ($cur -lt [version]"$($payload.minVersion)")) {
            Set-Busy $false
            if (($payload.PSObject.Properties.Name -contains 'fullInstall') -and $payload.fullInstall -and "$($payload.fullInstall.url)" -and "$($payload.fullInstall.sha256)") {
                Invoke-FullReinstall -Payload $payload
                return
            }
            if (-not $Silent) { (Show-Msg -Text ("Version $($payload.version) is available, but this installation is too old to update in place. Please re-run the full installer (support@liscaragh.com). Nothing has been changed.") -Caption ('Update available') -Icon ('Warning')) | Out-Null }
            return
        }
        Set-Busy $false
        $notes = if ($payload.PSObject.Properties.Name -contains 'notes') { "$($payload.notes)" } else { '' }
        $confirmText = "Version $($payload.version) is available (you have $($script:AppVersion))." + $(if ($notes) { "`n`n" + $notes } else { '' }) + "`n`nUpdate now? The app (not your PC) will close and reopen. Your licence, connection settings and jobs are not affected."
        if ((Show-Msg -Text $confirmText -Caption ('Update available') -Buttons ('YesNo')) -ne 'Yes') { return }
        $installDir = $PSScriptRoot
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('liscaragh-migrate-update-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        try {
            Set-Busy $true "Downloading version $($payload.version)..."
            foreach ($f in $payload.files) {
                if ("$($f.op)".ToLower() -ne 'put') { continue }
                if (-not (Test-SafeInstallPath -InstallDir $installDir -Rel "$($f.path)")) { throw "The update refers to an unsafe path ('$($f.path)')." }
                $dst = Join-Path $stage "$($f.path)"
                $dd = Split-Path $dst -Parent; if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
                try { Invoke-WebRequest -Uri ($script:UpdateBaseUrl + "$($f.url)") -OutFile $dst -UseBasicParsing -TimeoutSec 120 }
                catch { throw "A file for the update could not be downloaded ('$($f.path)'). Nothing has been changed." }
                $pin = "$($f.sha256)".ToLower()
                if ($pin -notmatch '^[0-9a-f]{64}$') { throw "An update file carried no valid checksum ('$($f.path)'). The update was stopped and nothing changed." }
                if ((Get-FileSha256Hex -Path $dst) -ne $pin) { throw "A downloaded update file did not match its checksum ('$($f.path)'). The update was stopped and nothing changed." }
            }
            $mfPath = Join-Path $stage 'integrity.json'
            if (Test-Path $mfPath) {
                $mf = ConvertFrom-UpdateDescriptor -Json (Get-Content $mfPath -Raw) -PublicKeyB64 $script:UpdatePublicKeyB64
                foreach ($pair in @(@{k='engine';n='Invoke-LiscaraghMigration.ps1'}, @{k='gui';n='LiscaraghMigrate-GUI.ps1'})) {
                    $staged = Join-Path $stage $pair.n
                    if (($mf.PSObject.Properties.Name -contains $pair.k) -and $mf."$($pair.k)" -and (Test-Path $staged)) {
                        if ((Get-FileSha256Hex -Path $staged) -ne "$($mf.($pair.k))".ToLower()) { throw "The update is inconsistent ($($pair.n) does not match its manifest). It was stopped and nothing changed." }
                    }
                }
            }
            $backup = Join-Path $installDir ('update-backup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
            $err = Invoke-UpdateApply -InstallDir $installDir -StageDir $stage -Payload $payload -BackupDir $backup
            Set-Busy $false
            if ($err) { (Show-Msg -Text $err -Caption ('Update failed') -Icon ('Error')) | Out-Null; return }
            $restartText = "Updated to version $($payload.version). The app (not your PC) needs to close and reopen to use the new version. Restart the app now?"
            $restart = ((Show-Msg -Text $restartText -Caption ('Update complete') -Buttons ('YesNo')) -eq 'Yes')
            try { Remove-Item -Path $backup -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            if ($restart) {
                try {
                    $launch = (Get-Process -Id $PID).Path
                    $gui = Join-Path $installDir 'LiscaraghMigrate-GUI.ps1'
                    Start-Process -FilePath $launch -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $gui) -WorkingDirectory $installDir
                    $win.Close()
                } catch { (Show-Msg -Text 'Update applied. Please close and reopen the app to use the new version.' -Caption ('Update complete')) | Out-Null }
            }
        } finally {
            Set-Busy $false
            try { Remove-Item -Path $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    } catch {
        Set-Busy $false
        if (-not $Silent) { (Show-Msg -Text ("$($_.Exception.Message)") -Caption ('Check for updates') -Icon ('Warning')) | Out-Null }
    }
}
$ctrl.MnuHelpUpdate.Add_Click({ Invoke-UpdateCheck })
$ctrl.MnuHelpAbout.Add_Click({
    $sections = @(
        @{ H = 'Version'; B = "$($script:AppVersion)" }
        @{ H = 'Made by'; B = "Liscaragh Software" }
        @{ H = 'Website'; B = "https://www.liscaragh.com"; Url = 'https://www.liscaragh.com' }
        @{ H = 'Support'; B = "support@liscaragh.com  (Help menu > Email support attaches the useful details for you)"; Url = 'mailto:support@liscaragh.com'; LinkText = 'support@liscaragh.com' }
    )
    [void](Lze80902559b -Title 'About' -Heading 'Liscaragh Migrate' -Sections $sections -No 'Close' -Brand)
})
$ctrl.MnuHelpCheck.Add_Click({
    $lines = New-Object System.Collections.Generic.List[string]
    $mark = { param($ok,$label,$detail) $lines.Add(("[" + $(if($ok){'PASS'}else{'FAIL'}) + "]  $label" + $(if($detail){"  -  $detail"}else{''}))) }
    & $mark ($PSVersionTable.PSVersion.Major -ge 7) 'PowerShell 7' "running $($PSVersionTable.PSVersion)"
    & $mark ((@(Get-Module -ListAvailable Microsoft.Graph.Authentication)).Count -gt 0) 'Microsoft Graph component' ''
    $isFilesMode = ($script:TransferMode -eq 'LocalFs')
    $need = if ($isFilesMode) { 'TenantId','GraphClientId','SharePointRootUrl','OneDriveHostUrl','UpnDomain' }
            else { 'DattoEndpointUrl','DattoClientId','TenantId','GraphClientId','SharePointRootUrl','OneDriveHostUrl','UpnDomain' }
    $missing = @($need | Where-Object { -not (Get-RegSetting $_) })
    & $mark ($missing.Count -eq 0) 'Connection settings' $(if($missing.Count){'missing: ' + ($missing -join ', ')}else{'all present'})
    $sec = $null; try { $sec = Lzff3ae1afba } catch {}
    if (-not $isFilesMode) { & $mark ([bool]$sec) 'Datto secret set' '' }
    $th = [string](Get-RegSetting 'CertThumbprint'); $certOk = $false
    try { if ($th) { $c = Get-ChildItem "Cert:\CurrentUser\My\$th" -ErrorAction SilentlyContinue; $certOk = [bool]($c -and $c.HasPrivateKey) } } catch {}
    & $mark $certOk 'Certificate installed' $(if($th){"thumbprint $th"}else{'none installed'})
    if ($isFilesMode) {
        $lines.Add('[ -- ]  Datto checks skipped: not used by the Files and folders transfer type. Switch transfer type to check them.')
    } else {
    try {
        $ep = [string](Get-RegSetting 'DattoEndpointUrl'); $id = [string](Get-RegSetting 'DattoClientId')
        if ($ep -and $id -and $sec) { $hdr=@{ Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($id):$sec")) }; $r=Invoke-RestMethod -Uri "$($ep.TrimEnd('/'))/file/projects" -Headers $hdr -ErrorAction Stop; & $mark $true 'Datto reachable' ("$(@($r.result).Count) project(s) visible") }
        else { & $mark $false 'Datto reachable' 'set the endpoint, ID and secret first' }
    } catch { & $mark $false 'Datto reachable' $_.Exception.Message }
    }
    try {
        $tid=[string](Get-RegSetting 'TenantId'); $app=[string](Get-RegSetting 'GraphClientId')
        if ($tid -and $app -and $certOk) { $tok=Lz1c498583eb -TenantId $tid -ClientId $app -Thumbprint $th; $s=Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root' -Headers @{Authorization="Bearer $tok"} -ErrorAction Stop; & $mark $true 'Microsoft 365 reachable' "$($s.webUrl)" }
        else { & $mark $false 'Microsoft 365 reachable' 'set the tenant, app ID and certificate first' }
    } catch { & $mark $false 'Microsoft 365 reachable' $_.Exception.Message }
    try {
        $q = 'C'; if ($script:Cfg -and $script:Cfg.run.tempWorkingFolder) { $q = (Split-Path $script:Cfg.run.tempWorkingFolder -Qualifier).TrimEnd(':') }
        $free = (Get-PSDrive $q -ErrorAction SilentlyContinue).Free
        & $mark ($free -gt 1GB) 'Disk space (temp drive)' $(if($free){"$([math]::Round($free/1GB,1)) GB free on $q`:"}else{'unknown'})
    } catch {}
    (Show-Msg -Text (($lines -join "`n")) -Caption ('Check my setup')) | Out-Null
})
$ctrl.MnuJobOpenFolder.Add_Click({
    if (-not $script:JobOpen) { return }
    try { $d = Split-Path $script:ConfigPath; if (Test-Path $d) { Start-Process explorer.exe $d } } catch {}
})
$ctrl.MnuJobExport.Add_Click({
    if (-not $script:JobOpen) { return }
    if (Test-ScheduleBusy) { (Show-Msg -Text ('A run is in progress. Wait for it to finish, or stop it, then export, so the export is a complete record rather than a half-written one.') -Caption ('Export job')); return }
    $nm = "$($ctrl.LblJob.Text)"; $dir = Split-Path $script:ConfigPath
    $safe = (("$nm") -replace '[^\w\-]', '-') -replace '-+', '-'
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title = 'Export job'
    $dlg.FileName = "liscaragh-migrate-job-$safe-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
    $dlg.Filter = 'Zip archive (*.zip)|*.zip'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if (-not $dlg.ShowDialog($win)) { return }
    $zip = $dlg.FileName
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('liscaragh-migrate-export-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        Set-Busy $true 'Exporting job...'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $skipped = 0
        foreach ($f in @(Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($dir.Length).TrimStart('\','/')
            $dest = Join-Path $stage $rel
            $dp = Split-Path $dest
            if (-not (Test-Path $dp)) { New-Item -ItemType Directory -Path $dp -Force | Out-Null }
            try { Copy-Item -LiteralPath $f.FullName -Destination $dest -Force } catch { $skipped++ }
        }
        try {
            $sc = Join-Path $stage (Split-Path $script:ConfigPath -Leaf)
            if (Test-Path $sc) { Set-Content -Path $sc -Value (Unprotect-ConfigText (Get-Content $sc -Raw)) -Encoding UTF8 }
        } catch {}
        if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
        Set-Busy $false
        $extra = if ($skipped) { "`n`nNote: $skipped file(s) were in use and could not be included. Close anything open on this job (a report in a browser, an audit in Excel) and export again for a complete copy." } else { '' }
        (Show-Msg -Text ("The job '$nm' was exported to:`n`n$zip`n`nIt holds the job's settings, mappings, logs, reports and resume state ($mb MB). Keep it somewhere safe. To bring it back, use Job > Import job on any machine with the app installed.$extra") -Caption ('Export job'))
        try { Start-Process 'explorer.exe' -ArgumentList "/select,`"$zip`"" } catch {}
        Lz5af601c665 "Exported job '$nm'"
    } catch {
        (Show-Msg -Text ("Could not export the job: $($_.Exception.Message)") -Caption ('Export job'))
    } finally {
        Set-Busy $false
        try { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
})
$ctrl.MnuJobImport.Add_Click({
    if (Test-ScheduleBusy) { (Show-Msg -Text ('A run is in progress. Wait for it to finish, or stop it, then import.') -Caption ('Import job')); return }
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Import job'
    $dlg.Filter = 'Zip archive (*.zip)|*.zip'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if (-not $dlg.ShowDialog($win)) { return }
    $zipIn = $dlg.FileName
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('liscaragh-migrate-import-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        Set-Busy $true 'Importing job...'
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null
        $za = [System.IO.Compression.ZipFile]::OpenRead($zipIn)
        try {
            foreach ($e in $za.Entries) {
                $n = "$($e.FullName)" -replace '\\','/'
                if ($n -match '(^|/)\.\.(/|$)' -or $n -match '^([A-Za-z]:|/)') { throw "the archive contains an unsafe path ('$($e.FullName)') and was refused." }
            }
        } finally { $za.Dispose() }
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Expand-Archive -LiteralPath $zipIn -DestinationPath $stage -Force
        if (-not (Test-Path (Join-Path $stage 'config.json')) -or -not (Test-Path (Join-Path $stage 'job.json'))) {
            throw 'this zip does not look like a job export (config.json and job.json are missing from its top level). Choose a zip made by Job > Export job.'
        }
        $jj = Get-Content (Join-Path $stage 'job.json') -Raw | ConvertFrom-Json
        $name = "$($jj.name)"; if (-not $name.Trim()) { $name = [IO.Path]::GetFileNameWithoutExtension($zipIn) }
        $slug = ($name -replace '[^A-Za-z0-9._-]','_').Trim('_'); if (-not $slug) { $slug = 'imported-job' }
        $jobDir = Join-Path $script:JobsRoot $slug
        $importSourceType = if ($jj.PSObject.Properties.Name -contains 'sourceType' -and "$($jj.sourceType)") { "$($jj.sourceType)" } else { 'Datto' }
        $existingNameClash = $false
        foreach ($jd in @(Get-ChildItem $script:JobsRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($jd.FullName -eq $jobDir) { continue }
            if (-not (Test-RealJobFolder -Dir $jd.FullName)) { continue }
            if ((Get-JobSourceType (Join-Path $jd.FullName 'config.json')) -ne $importSourceType) { continue }
            $existingName = $null
            try { $existingName = "$((Get-Content (Join-Path $jd.FullName 'job.json') -Raw | ConvertFrom-Json).name)" } catch {}
            if ($existingName -and $existingName -eq $name) { $existingNameClash = $true; break }
        }
        if ($existingNameClash -or (Test-RealJobFolder -Dir $jobDir)) {
            Set-Busy $false
            $name2 = Show-InputBox -Prompt "A job named '$name' already exists on this computer. Name for the imported copy:" -Title 'Import job' -Default "$name (imported)"
            if (-not $name2 -or -not $name2.Trim()) { return }
            $name = $name2.Trim()
            $slug = ($name -replace '[^A-Za-z0-9._-]','_').Trim('_'); if (-not $slug) { $slug = 'imported-job' }
            $jobDir = Join-Path $script:JobsRoot $slug
            if (Test-RealJobFolder -Dir $jobDir) { (Show-Msg -Text ("A job named '$slug' also exists. Nothing was imported; try again with a different name.") -Caption ('Import job')); return }
            Set-Busy $true 'Importing job...'
        }
        if ((Test-Path $jobDir) -and -not (Remove-JobFolderWithRetry -Dir $jobDir)) {
            throw "a leftover folder named '$slug' is on disk and could not be cleared because a file inside it is in use. Close anything open on it, then try again."
        }
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
        foreach ($f in @(Get-ChildItem -Path $stage -Recurse -File)) {
            $rel = $f.FullName.Substring($stage.Length).TrimStart('\','/')
            if ($rel -eq 'config.json') { continue }
            $dest = Join-Path $jobDir $rel
            $dp = Split-Path $dest
            if (-not (Test-Path $dp)) { New-Item -ItemType Directory -Path $dp -Force | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        }
        $cfg = $null
        try { $cfg = Read-ConfigJson (Join-Path $stage 'config.json') }
        catch { throw "the job settings inside this zip are encrypted for a different Windows account or machine, so they cannot be read here. Use a zip made by Job > Export job (its settings copy is stored readable), or export the job again on the original machine." }
        $cfg.run.tempWorkingFolder = Join-Path $jobDir 'temp'
        $cfg.run.logRoot           = Join-Path $jobDir 'logs'
        $cfg.run.reportRoot        = Join-Path $jobDir 'reports'
        $cfg.run.stateRoot         = Join-Path $jobDir 'state'
        Write-ConfigJson -Cfg $cfg -Path (Join-Path $jobDir 'config.json')
        try {
            if ($jj.PSObject.Properties.Name -contains 'name') { $jj.name = $name } else { $jj | Add-Member -NotePropertyName name -NotePropertyValue $name -Force }
            if ($jj.PSObject.Properties.Name -contains 'slug') { $jj.slug = $slug } else { $jj | Add-Member -NotePropertyName slug -NotePropertyValue $slug -Force }
            $jj | Add-Member -NotePropertyName imported -NotePropertyValue ((Get-Date).ToString('o')) -Force
            $jj | ConvertTo-Json | Set-Content -Path (Join-Path $jobDir 'job.json') -Encoding UTF8
        } catch {}
        Set-Busy $false
        Set-CurrentJob -ConfigFile (Join-Path $jobDir 'config.json')
        (Show-Msg -Text ("The job '$name' was imported and is now open.`n`nIts mappings, logs, reports and resume state came across with it. It uses the $(if ($script:TransferMode -eq 'LocalFs') { 'Microsoft 365 connection' } else { 'Datto and Microsoft 365 connection' }) set up on THIS computer, so if it came from another machine, run 'Check readiness' before any upload.") -Caption ('Import job') -Icon ('Information'))
        Start-AutoConnect
    } catch {
        (Show-Msg -Text ("Could not import the job: $($_.Exception.Message)") -Caption ('Import job'))
    } finally {
        Set-Busy $false
        try { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
})
$ctrl.MnuJobRename.Add_Click({
    if (-not $script:JobOpen) { return }
    $new = Show-InputBox -Prompt 'New display name for this job:' -Title 'Rename job' -Default "$($ctrl.LblJob.Text)"
    if (-not $new -or -not $new.Trim()) { return }
    $new = $new.Trim()
    try {
        $jf = Join-Path (Split-Path $script:ConfigPath) 'job.json'
        $j = if (Test-Path $jf) { Get-Content $jf -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
        if ($j.PSObject.Properties.Name -contains 'name') { $j.name = $new } else { $j | Add-Member -NotePropertyName name -NotePropertyValue $new -Force }
        $j | ConvertTo-Json | Set-Content $jf -Encoding UTF8
        Set-JobChip -Name $new; $win.Title = Lzd40aefb567 $new
        Lz5af601c665 "Renamed to $new"
    } catch { (Show-Msg -Text ("Could not rename: $($_.Exception.Message)")) }
})
function Lz6dea60a733 {
    $script:JobOpen = $false; $script:Cfg = $null; $script:Projects = @(); $script:Map = @{}; $script:GraphReady = $false
    $script:RunStatus = @{}; Lzc219beec58
    if ($ctrl.RunSummaryBanner) { $ctrl.RunSummaryBanner.Visibility = 'Collapsed' }
    $ctrl.LblProject.Text = "(no $(if ($script:NItem) { $script:NItem } else { 'project' }) selected)"
    Lzeb3a1395a1 -Text 'Not connected' -State off
    Set-JobChip -Name ''; $win.Title = Lzd40aefb567 ''
    $ctrl.BtnConnect.IsEnabled = $false; Lzdd341be2a9 $false
    if ($ctrl.BtnAddFolder) { $ctrl.BtnAddFolder.IsEnabled = $false }
    if ($ctrl.BtnRemoveFolder) { $ctrl.BtnRemoveFolder.IsEnabled = $false }
    Lz35d0f8dce4 $false
}
$ctrl.MnuJobClose.Add_Click({ Lz6dea60a733; Lz5af601c665 'Job closed' })
$ctrl.MnuJobDelete.Add_Click({
    if (-not $script:JobOpen) { return }
    $nm = "$($ctrl.LblJob.Text)"; $dir = Split-Path $script:ConfigPath
    if ((Show-Msg -Text ("Delete the job '$nm' and all its logs, reports and resume state from this computer?`n`nThis cannot be undone. Files already uploaded to Microsoft 365 are not affected.") -Caption ('Delete job') -Buttons ('YesNo') -Icon ('Warning')) -ne 'Yes') { return }
    Lz6dea60a733
    $result = Remove-JobFolderWithRetry -Dir $dir
    if (-not (Test-Path $script:ConfigPath)) { $script:ConfigPath = $script:AppConfigPath }
    if ($result) {
        Lz56e0fac1fe; Lz5af601c665 "Deleted job '$nm'"
    } else {
        Lz56e0fac1fe
        if ((Show-Msg -Text ("The job '$nm' could not be fully removed because a file inside it is in use.`n`nClose anything open on this job (a report or audit in a browser or Excel, or the job folder in a File Explorer window), then delete this folder by hand:`n`n$dir`n`nUntil it is gone, that job name stays reserved. Open the folder now?") -Caption ('Job not fully deleted') -Buttons ('YesNo') -Icon ('Warning')) -eq 'Yes') { try { Start-Process $dir } catch {} }
        Lz5af601c665 "Could not fully delete job '$nm' (a file is in use)"
    }
})
function Lzd00e445e54 {
    param([switch]$Quiet)
    if (-not $script:JobOpen) { if (-not $Quiet) { (Show-Msg -Text ('Create or open a named migration job before connecting.')) }; return }
    try {
        Set-Busy $true 'Connecting...'
        $script:Cfg = Import-ResolvedConfig $script:ConfigPath
        if ($script:TransferMode -eq 'LocalFs') {
            Lzf47c317f43 'Listing the folders in this job...'
            $script:Projects = @(Lz10167c5c6e)
            Lzf47c317f43 "Found $($script:Projects.Count) folder(s)."
            Lzed1b0733be
            try { Lz7758da3d39; Lzf47c317f43 'Connected to Microsoft 365.' } catch { Lzf47c317f43 'Could not sign in to Microsoft 365 yet. You can still add folders and set up destinations, but you will need this connected before uploading.'; Lzf47c317f43 "Technical detail: $($_.Exception.Message)" }
            Lzc219beec58
            Lzeb3a1395a1 -Text $(if ($script:Projects.Count) { "$($script:Projects.Count) folder(s) in this job" } else { "No folders yet - click 'Add folder...'" }) -State $(if ($script:Projects.Count) { 'ok' } else { 'off' })
            Lz5af601c665 $(if ($script:Projects.Count) { 'Ready' } else { "Click 'Add folder...' to choose what to copy" })
            return
        }
        Lzf47c317f43 'Signing in to Datto and listing projects...'
        $script:Projects = Lzb07d20bccb
        Lzf47c317f43 "Found $($script:Projects.Count) project(s)."
        Lzed1b0733be
        try { Lz7758da3d39; Lzf47c317f43 'Connected to Microsoft 365.' } catch { Lzf47c317f43 'Could not sign in to Microsoft 365 yet. You can still set up mappings, but you will need this connected before uploading.'; Lzf47c317f43 "Technical detail: $($_.Exception.Message)" }
        Lzc219beec58
        Lzeb3a1395a1 -Text "Connected - $($script:Projects.Count) projects" -State ok
        Lz5af601c665 'Connected'
    } catch {
        if ($Quiet) {
            Lzeb3a1395a1 -Text 'Not connected - automatic connect failed' -State err
            Lzf47c317f43 'Could not connect automatically. Click ''Connect and list projects'' to try again.'
            Lzf47c317f43 "Technical detail: $($_.Exception.Message)"
            Lz5af601c665 "Could not connect automatically ($($_.Exception.Message)). Click 'Connect and list projects' to try again."
        } else {
            (Show-Msg -Text ("Could not connect.`n`nThe usual causes are: signed in to the wrong Microsoft 365 organisation, the Datto password not set up on this computer, or no internet connection. The log has more detail.`n`nTechnical detail: $($_.Exception.Message)") -Caption ('Connect failed'))
            Lz5af601c665 'Connect failed'
        }
    }
    finally { Set-Busy $false }
}
$ctrl.BtnConnect.Add_Click({ Lzd00e445e54 })
function Start-AutoConnect {
    if ($script:TransferMode -eq 'LocalFs') { Lzd00e445e54 -Quiet; return }
    $ep = [string](Get-RegSetting 'DattoEndpointUrl'); $id = [string](Get-RegSetting 'DattoClientId')
    $sec = $null; try { $sec = Lzff3ae1afba } catch {}
    if (-not ($ep -and $id -and $sec)) {
        Lz5af601c665 "Job ready. Set up your API details first (Settings > API settings), then click 'Connect and list projects'."
        return
    }
    Lzd00e445e54 -Quiet
}
$ctrl.LstProjects.Add_SelectionChanged({
    $p = Get-SelectedProject
    if (-not $p) {
        $ctrl.LblProject.Text = "(no $(if ($script:NItem) { $script:NItem } else { 'project' }) selected)"
        $ctrl.LblCheck.Text = ''
        $ctrl.RbOneDrive.IsChecked = $true
        $ctrl.TxtLoc.Text = ''; $ctrl.TxtLib.Text = ''; $ctrl.TxtFolder.Text = ''
        Set-SourceFolders -Folders @()
        if ($ctrl.ChkSrcContents) { $ctrl.ChkSrcContents.IsChecked = $false }
        if ($ctrl.LblSourceCheck) { $ctrl.LblSourceCheck.Text = '' }
        Update-SourceUi
        Set-DestModeUI
        Update-ApplyButtonState
        Update-DestPreview
        return
    }
    $selCount = 0; try { $selCount = @(Lz6d0d60c1fc).Count } catch {}
    $ctrl.LblProject.Text = if ($selCount -gt 1) { "$($p.Name)   (+$($selCount - 1) more selected)" } else { $p.Name }
    $ctrl.LblCheck.Text = ''
    if ($script:Map.ContainsKey($p.Id)) {
        $d = $script:Map[$p.Id]
        if ($d.DestinationType -eq 'OneDrive') { $ctrl.RbOneDrive.IsChecked = $true; $ctrl.TxtLoc.Text = $d.TargetPrincipal }
        elseif ($d.DestinationType -eq 'SharePoint') { $ctrl.RbSite.IsChecked = $true; $ctrl.TxtLoc.Text = $d.DestinationUrl; $ctrl.TxtLib.Text = $d.TargetLibrary }
        else { $ctrl.RbSkip.IsChecked = $true }
        $ctrl.TxtFolder.Text = $d.TargetSubFolder
        $sf = @()
        if ($d.ContainsKey('SourceSubPaths') -and $d.SourceSubPaths) { $sf = @($d.SourceSubPaths) }
        elseif ($d.ContainsKey('SourceSubPath') -and "$($d.SourceSubPath)".Trim()) { $sf = @("$($d.SourceSubPath)") }
        Set-SourceFolders -Folders $sf
        if ($ctrl.ChkSrcContents) { $ctrl.ChkSrcContents.IsChecked = ((@($sf).Count -le 1) -and $d.ContainsKey('SourceContentsOnly') -and "$($d.SourceContentsOnly)" -match '^(?i)true') }
    } else {
        $ctrl.RbOneDrive.IsChecked = $true
        $ctrl.TxtLoc.Text = ''
        $ctrl.TxtLib.Text = ''; $ctrl.TxtFolder.Text = ''; Set-SourceFolders -Folders @()
        if ($ctrl.ChkSrcContents) { $ctrl.ChkSrcContents.IsChecked = $false }
    }
    Update-SourceUi
    if ($ctrl.LblSourceCheck) {
        $ctrl.LblSourceCheck.Text = if ($selCount -le 1) { '' } else {
            "Source folders are set one project at a time, so they are off while $selCount are selected. The boxes below apply to all $selCount; 'Apply to selected' and 'Apply to ALL' only ever set the destination, never the source."
        }
    }
    Set-DestModeUI
    Update-ApplyButtonState
    Update-DestPreview
})
function Lz2c1b5ed8d9 {
    param([switch]$Quiet)
    if ($ctrl.RbSkip.IsChecked) { return $null }
    if ($ctrl.RbOneDrive.IsChecked) {
        $upn = $ctrl.TxtLoc.Text.Trim()
        if (-not $upn) { if (-not $Quiet) { (Show-Msg -Text ("Enter the user's email / sign-in address.")) }; return 'ERR' }
        if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            if (-not $Quiet) { (Show-Msg -Text ("'$upn' is not a complete email / sign-in address - it needs a username before the @ (for example: jsmith@$($upn.TrimStart('@'))).") -Caption ('Check the address') -Icon ('Warning')) }
            return 'ERR'
        }
        return @{ DestinationType='OneDrive'; DestinationUrl="$($script:Cfg.destination.oneDriveHostUrl)/personal/$((ConvertTo-Slug $upn))"; TargetPrincipal=$upn; TargetLibrary=''; TargetSubFolder=(Lz5348656d18) }
    }
    $site = $ctrl.TxtLoc.Text.Trim().TrimEnd('/')
    if (-not $site) { if (-not $Quiet) { (Show-Msg -Text ('Enter a SharePoint site URL.')) }; return 'ERR' }
    return @{ DestinationType='SharePoint'; DestinationUrl=$site; TargetPrincipal=''; TargetLibrary="$($ctrl.TxtLib.Text)".Trim(); TargetSubFolder=(Lz5348656d18) }
}
$ctrl.BtnApply.Add_Click({
    $p = Get-SelectedProject
    if (-not $p) { (Show-Msg -Text ("Select a $($script:NItem) first.")); return }
    if ($ctrl.RbSkip.IsChecked) {
        if ($script:Map.ContainsKey($p.Id)) {
            if (-not ((Show-Msg -Text ("'$($p.Name)' already has a saved destination. Setting it to skip will REMOVE that destination - you would need to set it up again to migrate this $($script:NItem) later.`n`nSkip this $($script:NItem) and remove its saved destination?") -Caption ('Remove saved destination?') -Buttons 'YesNo' -Icon 'Warning') -eq 'Yes')) { return }
        }
        $script:Map.Remove($p.Id) | Out-Null; Lzc219beec58; [void](Lz5e06c2c15b); Lz5af601c665 "Set to skip: $($p.Name)"; return
    }
    $d = Lz2c1b5ed8d9
    if ($d -eq 'ERR') { return }
    if ($null -eq $d) { $script:Map.Remove($p.Id) | Out-Null }
    else {
        $sf = @(Lz855e586988)
        $d['SourceSubPaths'] = $sf
        $d['SourceSubPath'] = $(if ($sf.Count) { $sf[0] } else { '' })
        $d['SourceContentsOnly'] = $(if (($sf.Count -le 1) -and $ctrl.ChkSrcContents -and $ctrl.ChkSrcContents.IsChecked) { 'TRUE' } else { '' })
        $script:Map[$p.Id] = $d
    }
    Lzc219beec58
    [void](Lz5e06c2c15b)
    Lz5af601c665 "Mapped and saved: $($p.Name)"
})
$ctrl.TxtFilter.Add_TextChanged({ Lzb130494444 })
$ctrl.BtnApplySel.Add_Click({
    $sel = Lz6d0d60c1fc
    if (-not $sel.Count) { (Show-Msg -Text ("Highlight one or more $($script:NItems) in the list first (Ctrl-click or Shift-click for several).")); return }
    if (-not (Lzb71d135d7d -Count $sel.Count)) { return }
    if ($ctrl.RbSkip.IsChecked) {
        $mappedCount = @($sel | Where-Object { $script:Map.ContainsKey($_.Id) }).Count
        if ($mappedCount -gt 0) {
            if (-not ((Show-Msg -Text ("$mappedCount of the $($sel.Count) selected $($script:NItems) already have a saved destination. Setting them to skip will REMOVE those destinations.`n`nSkip $($sel.Count) $($script:NItems) and remove any saved destinations?") -Caption ('Remove saved destinations?') -Buttons 'YesNo' -Icon 'Warning') -eq 'Yes')) { return }
        }
        foreach ($p in $sel) { $script:Map.Remove($p.Id) | Out-Null }; Lzc219beec58; [void](Lz5e06c2c15b); Lz5af601c665 "Set $($sel.Count) project(s) to skip"; return
    }
    $d = Lz2c1b5ed8d9
    if ($d -eq 'ERR') { return }
    $lib = $d.TargetLibrary; $folder = $d.TargetSubFolder
    foreach ($proj in $sel) {
        $keepSrcList = if ($script:Map.ContainsKey($proj.Id) -and $script:Map[$proj.Id].ContainsKey('SourceSubPaths') -and $script:Map[$proj.Id].SourceSubPaths) { @($script:Map[$proj.Id].SourceSubPaths) } elseif ($script:Map.ContainsKey($proj.Id) -and $script:Map[$proj.Id].ContainsKey('SourceSubPath') -and "$($script:Map[$proj.Id].SourceSubPath)".Trim()) { @("$($script:Map[$proj.Id].SourceSubPath)") } else { @() }
        $keepSrc = if ($keepSrcList.Count) { $keepSrcList[0] } else { '' }
        $existCo = if ($script:Map.ContainsKey($proj.Id) -and $script:Map[$proj.Id].ContainsKey('SourceContentsOnly')) { "$($script:Map[$proj.Id].SourceContentsOnly)" } else { '' }
        $keepCo  = if (@($keepSrcList).Count -le 1) { $existCo } else { '' }
        if ($ctrl.RbOneDrive.IsChecked) {
            $script:Map[$proj.Id] = @{ DestinationType='OneDrive'; DestinationUrl=$d.DestinationUrl; TargetPrincipal=$d.TargetPrincipal; TargetLibrary=''; TargetSubFolder=$folder; SourceSubPaths=$keepSrcList; SourceSubPath=$keepSrc; SourceContentsOnly=$keepCo }
        } else {
            $sub = $folder
            $script:Map[$proj.Id] = @{ DestinationType='SharePoint'; DestinationUrl=(Lz606d7bc37e); TargetPrincipal=''; TargetLibrary=$lib; TargetSubFolder=$sub; SourceSubPaths=$keepSrcList; SourceSubPath=$keepSrc; SourceContentsOnly=$keepCo }
        }
    }
    Lzc219beec58
    [void](Lz5e06c2c15b)
    Lz5af601c665 "Applied and saved for $($sel.Count) selected $($script:NItem)(s)"
})
$ctrl.BtnApplyAll.Add_Click({
    if (-not (Lzb71d135d7d -Count (@($script:Projects).Count))) { return }
    $d = Lz2c1b5ed8d9
    if ($d -eq 'ERR') { return }
    if ($ctrl.RbSkip.IsChecked) {
        $mappedCount = $script:Map.Count
        if ($mappedCount -gt 0) {
            if (-not ((Show-Msg -Text ("$mappedCount $($script:NItem)(s) in this job already have a saved destination. Setting ALL $(@($script:Projects).Count) $($script:NItems) to skip will REMOVE every one of those destinations.`n`nSkip every $($script:NItem) and remove all saved destinations?") -Caption ('Remove ALL saved destinations?') -Buttons 'YesNo' -Icon 'Warning') -eq 'Yes')) { return }
        }
        $script:Map.Clear(); Lzc219beec58; [void](Lz5e06c2c15b); Lz5af601c665 'All projects set to skip'; return
    }
    $lib = $d.TargetLibrary; $folder = $d.TargetSubFolder
    foreach ($proj in $script:Projects) {
        $keepSrcList = if ($script:Map.ContainsKey($proj.Id) -and $script:Map[$proj.Id].ContainsKey('SourceSubPaths') -and $script:Map[$proj.Id].SourceSubPaths) { @($script:Map[$proj.Id].SourceSubPaths) } elseif ($script:Map.ContainsKey($proj.Id) -and $script:Map[$proj.Id].ContainsKey('SourceSubPath') -and "$($script:Map[$proj.Id].SourceSubPath)".Trim()) { @("$($script:Map[$proj.Id].SourceSubPath)") } else { @() }
        $keepSrc = if ($keepSrcList.Count) { $keepSrcList[0] } else { '' }
        $existCo = if ($script:Map.ContainsKey($proj.Id) -and $script:Map[$proj.Id].ContainsKey('SourceContentsOnly')) { "$($script:Map[$proj.Id].SourceContentsOnly)" } else { '' }
        $keepCo  = if (@($keepSrcList).Count -le 1) { $existCo } else { '' }
        if ($ctrl.RbOneDrive.IsChecked) {
            $script:Map[$proj.Id] = @{ DestinationType='OneDrive'; DestinationUrl=$d.DestinationUrl; TargetPrincipal=$d.TargetPrincipal; TargetLibrary=''; TargetSubFolder=$folder; SourceSubPaths=$keepSrcList; SourceSubPath=$keepSrc; SourceContentsOnly=$keepCo }
        } else {
            $sub = $folder
            $script:Map[$proj.Id] = @{ DestinationType='SharePoint'; DestinationUrl=(Lz606d7bc37e); TargetPrincipal=''; TargetLibrary=$lib; TargetSubFolder=$sub; SourceSubPaths=$keepSrcList; SourceSubPath=$keepSrc; SourceContentsOnly=$keepCo }
        }
    }
    Lzc219beec58
    [void](Lz5e06c2c15b)
    Lz5af601c665 "Applied and saved for all $($script:Projects.Count) projects"
})
if ($ctrl.BtnPickLib) { $ctrl.BtnPickLib.Add_Click({
    $site = "$($ctrl.TxtLoc.Text)".Trim()
    if (-not $site) { $ctrl.LblCheck.Text = "Set the Site URL first (or use 'Find site...')."; $ctrl.LblCheck.Foreground = 'Red'; return }
    $libs = $null
    try {
        Set-Busy $true 'Looking up libraries...'
        $libs = Lzc92872bdd0 -Url $site -Refresh
    } catch { $ctrl.LblCheck.Text = "Error: $($_.Exception.Message)"; $ctrl.LblCheck.Foreground = 'Red'; Set-Busy $false; return }
    finally { Set-Busy $false }
    if ($null -eq $libs) { $ctrl.LblCheck.Text = 'Site not found - check the URL.'; $ctrl.LblCheck.Foreground = 'Red'; return }
    $picked = Lze055499fb7 -SiteUrl $site -Libraries $libs
    if ($picked) {
        $changed = ("$($ctrl.TxtLib.Text)".Trim() -ne "$picked")
        $ctrl.TxtLib.Text = $picked
        if ($changed -and "$($ctrl.TxtFolder.Text)".Trim()) {
            $ctrl.TxtFolder.Text = ''
            Lz5af601c665 "Library set to $picked. The Folder box was cleared: its path belonged to the previous library."
        } else {
            Lz5af601c665 "Library set to $picked"
        }
        $ctrl.LblCheck.Text = "Library set to '$picked'."; $ctrl.LblCheck.Foreground = 'Green'
        Update-DestPreview
    }
}) }
if ($ctrl.BtnBrowseFolder) { $ctrl.BtnBrowseFolder.Add_Click({
    if ($ctrl.RbSkip.IsChecked) { (Show-Msg -Text ("This $($script:NItem) is set to skip, so there is no destination to browse.") -Caption ('Browse folders')); return }
    try {
        Set-Busy $true 'Opening destination...'
        Lz7758da3d39
        $res = Lz48143bf7eb
    } catch { (Show-Msg -Text ($_.Exception.Message) -Caption ('Browse folders')); Set-Busy $false; return }
    finally { Set-Busy $false }
    $picked = Lz6723197124 -DriveId $res.DriveId -Label $res.Label -StartPath ("$($ctrl.TxtFolder.Text)".Trim())
    if ($null -ne $picked) { $ctrl.TxtFolder.Text = $picked; Lz5af601c665 ("Folder set to " + $(if ($picked) { "/$picked" } else { 'top level' })) }
}) }
if ($ctrl.BtnAddSource) { $ctrl.BtnAddSource.Add_Click({
    $p = Get-SelectedProject
    if (-not $p) { (Show-Msg -Text ('Select a project on the left first, then browse its folders.') -Caption ('Add source folders')); return }
    if (-not $script:Cfg) { (Show-Msg -Text ('Connect to Datto first (Connect and list projects), then browse.') -Caption ('Add source folders')); return }
    try { $picked = Lz15e474afbe -ProjectId $p.Id -ProjectName $p.Name }
    catch { (Show-Msg -Text ("Could not open the project's folders: $($_.Exception.Message)") -Caption ('Add source folders')); return }
    if ($null -eq $picked) { return }
    $arr = @(@($picked) | ForEach-Object { "$_" } | Where-Object { $_ })
    if (-not $arr.Count) { return }
    Lz51c39bc741 -Picked $arr
    Lz5af601c665 ("Source folders: " + (@(Lz855e586988) -join ', '))
}) }
if ($ctrl.BtnRemoveSource) { $ctrl.BtnRemoveSource.Add_Click({
    if (-not $ctrl.LstSource) { return }
    $sel = @($ctrl.LstSource.SelectedItems | ForEach-Object { "$_" })
    if (-not $sel.Count) { (Show-Msg -Text ('Highlight one or more folders in the list to remove.') -Caption ('Remove source folder')); return }
    Set-SourceFolders -Folders @(Lz855e586988 | Where-Object { $sel -notcontains $_ })
}) }
if ($ctrl.BtnTestSource) { $ctrl.BtnTestSource.Add_Click({
    $p = Get-SelectedProject
    if (-not $p) { (Show-Msg -Text ('Select a project on the left first.') -Caption ('Test source')); return }
    if (-not $script:Cfg) { (Show-Msg -Text ('Connect to Datto first (Connect and list projects), then test.') -Caption ('Test source')); return }
    $subs = @(Lz855e586988)
    if (-not $subs.Count) { $ctrl.LblSourceCheck.Text = 'No source folders set, so the whole project would be copied.'; $ctrl.LblSourceCheck.Foreground = 'Gray'; return }
    $bad = New-Object System.Collections.Generic.List[string]
    try {
        Set-Busy $true 'Checking the source folder(s) in Datto...'
        foreach ($s in $subs) { try { $null = Lzc7583c6c9b -ProjectId $p.Id -SubPath $s } catch { [void]$bad.Add($s) } }
    } catch { $ctrl.LblSourceCheck.Text = "Could not check the source: $($_.Exception.Message)"; $ctrl.LblSourceCheck.Foreground = 'Red'; Set-Busy $false; return }
    finally { Set-Busy $false }
    if ($bad.Count) { $ctrl.LblSourceCheck.Text = "NOT found in Datto (case-sensitive): " + ($bad -join ', ') + ". Fix or remove these before running."; $ctrl.LblSourceCheck.Foreground = 'Red' }
    else { $ctrl.LblSourceCheck.Text = "All $($subs.Count) source folder(s) found in Datto. A run scopes to them, and the destination paths stay the same as a full run."; $ctrl.LblSourceCheck.Foreground = 'Green' }
}) }
function Lza3c56abac5 {
    if ($ctrl.RbSkip -and $ctrl.RbSkip.IsChecked) { $ctrl.LblCheck.Text = 'This project is set to skip, so there is no destination to test.'; $ctrl.LblCheck.Foreground = 'Gray'; return }
    try {
        Set-Busy $true 'Checking destination...'
        if ($ctrl.RbOneDrive.IsChecked) {
            $upn = $ctrl.TxtLoc.Text.Trim()
            $d = Lz7287a65440 -Path "users/$([uri]::EscapeDataString($upn))/drive"
            $ctrl.LblCheck.Text = if ($d) { 'OneDrive found for this user.' } else { 'Not found.' }
        } else {
            $libs = Lzc92872bdd0 -Url $ctrl.TxtLoc.Text.Trim()
            if ($null -eq $libs) { $ctrl.LblCheck.Text = 'Site not found - check the URL.'; $ctrl.LblCheck.Foreground = 'Red'; return }
            $ctrl.LblCheck.Text = "Site OK. Libraries: " + ($libs -join ', ')
        }
        $ctrl.LblCheck.Foreground = 'Green'
    } catch { $ctrl.LblCheck.Text = "Not found / error: $($_.Exception.Message)"; $ctrl.LblCheck.Foreground = 'Red' }
    finally { Set-Busy $false }
}
$ctrl.BtnCheck.Add_Click({ Lza3c56abac5 })
if ($ctrl.BtnTestDest) { $ctrl.BtnTestDest.Add_Click({ Lza3c56abac5 }) }
function Lz5e06c2c15b {
    if (-not $script:Cfg) { return 0 }
    $rows = @(foreach ($p in $script:Projects) {
        if (-not $script:Map.ContainsKey($p.Id)) { continue }
        $d = $script:Map[$p.Id]
        $subs = @()
        if ($d.ContainsKey('SourceSubPaths') -and $d.SourceSubPaths) { $subs = @($d.SourceSubPaths | ForEach-Object { "$_".Trim().Trim('/').Trim('\') } | Where-Object { $_ }) }
        elseif ($d.ContainsKey('SourceSubPath') -and "$($d.SourceSubPath)".Trim()) { $subs = @("$($d.SourceSubPath)".Trim().Trim('/').Trim('\')) }
        if (-not $subs.Count) { $subs = @('') }
        $co = if ($d.ContainsKey('SourceContentsOnly')) { "$($d.SourceContentsOnly)" } else { '' }
        if ($subs.Count -gt 1) { $co = '' }
        foreach ($s in $subs) {
            [pscustomobject]@{ Space=$p.Name; SpaceId=$p.Id; SourceSubPath=$s; SourceContentsOnly=$(if ($s) { $co } else { '' }); Type='Project'; OwnerResolved='n/a'
                DestinationType=$d.DestinationType; DestinationUrl=$d.DestinationUrl; TargetPrincipal=$d.TargetPrincipal
                TargetLibrary=$d.TargetLibrary; TargetSubFolder=$d.TargetSubFolder; Action='MIGRATE'; Notes='(gui)' }
        }
    })
    if (-not (Test-Path $script:Cfg.run.reportRoot)) { New-Item -ItemType Directory -Path $script:Cfg.run.reportRoot -Force | Out-Null }
    $out = Join-Path $script:Cfg.run.reportRoot 'mapping.csv'
    if ($rows.Count) { $rows | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8 }
    elseif (Test-Path $out) { Remove-Item $out -Force -ErrorAction SilentlyContinue }
    return $rows.Count
}
function Lz1fb7129670 {
    param($Project)
    if (-not $Project) { return '' }
    $f = @(Lz855e586988)
    if ($f.Count) { return "$($Project.Name) / " + ($f -join ', ') }
    return $Project.Name
}
function Update-DestPreview {
    if ($ctrl.TxtLocHint) { $ctrl.TxtLocHint.Visibility = if ("$($ctrl.TxtLoc.Text)".Trim()) { 'Collapsed' } else { 'Visible' } }
    if (-not $ctrl.LblDestPath) { return }
    $p = Get-SelectedProject
    if (-not $p) {
        $ctrl.SourcePathBox.Visibility = 'Collapsed'; $ctrl.DestPathBox.Visibility = 'Collapsed'
        return
    }
    $srcLabel = Lz1fb7129670 -Project $p
    $folders  = @(Lz855e586988)
    $srcSub   = Lz4dcf097695
    $co = [bool]($ctrl.ChkSrcContents -and $ctrl.ChkSrcContents.IsChecked)
    $ctrl.SourcePathBox.Visibility = 'Visible'
    $srcNote = if ($script:TransferMode -eq 'LocalFs') {
        if ($co) { '   (contents only: the folder itself is not created at the destination)' } else { '   (the whole folder, kept under its own name)' }
    } elseif ($folders.Count -eq 0) {
        if ($co) { '   (the entire project, contents only: no project folder is created)' } else { '   (the entire project, in its own folder)' }
    } elseif ($folders.Count -gt 1) { "   ($($folders.Count) folders, each kept under its own name)" } elseif ($co) { '   (contents only: the folder itself is not created)' } else { '' }
    $ctrl.LblSourcePath.Text = "Source:  $srcLabel" + $srcNote
    if ($ctrl.RbSkip.IsChecked) {
        $ctrl.DestPathBox.Visibility = 'Collapsed'
        return
    }
    $ctrl.DestPathBox.Visibility = 'Visible'
    $type = if ($ctrl.RbSite.IsChecked) { 'SharePoint' } else { 'OneDrive' }
    $loc  = "$($ctrl.TxtLoc.Text)".Trim()
    $land = Get-GuiLandingPath -DestType $type -SiteUrl $loc -TargetSubFolder (Lz5348656d18) `
                               -SpaceName $p.Name -SourceSubPath $srcSub -ContentsOnly $co
    $where = if ($type -eq 'SharePoint') {
        $lib = "$($ctrl.TxtLib.Text)".Trim(); if (-not $lib) { $lib = 'Documents' }
        if ($loc) { "$(Get-GuiShortSite $loc) > $lib" } else { 'the SharePoint site above' }
    } else {
        if ($loc) { "$loc's OneDrive" } else { "the person's OneDrive above" }
    }
    $ctrl.LblDestPath.Text = "$srcLabel  will be copied to:`n$where" + $(if ($land) { " > /$land" } else { ' > the top level' })
    $ctrl.LblDestWarn.Visibility = 'Collapsed'
    $segs = @(($land -split '/') | Where-Object { $_ })
    $doubled = $false
    for ($i = 1; $i -lt $segs.Count; $i++) {
        if ($segs[$i] -eq $segs[$i - 1]) {
            $ctrl.LblDestWarn.Text = "Note: '$($segs[$i])' appears twice in a row above. The source subfolder is already part of the path, so you usually do not need it in the Folder box as well. Clear the Folder box if you meant to drop the files straight in."
            $ctrl.LblDestWarn.Visibility = 'Visible'
            $doubled = $true
            break
        }
    }
    if (-not $doubled -and $script:Map -and $script:Map.Count -gt 0) {
        $curUrl = if ($type -eq 'OneDrive') { "$($script:Cfg.destination.oneDriveHostUrl)/personal/$((ConvertTo-Slug $loc))" } else { $loc.TrimEnd('/') }
        $curPrin = if ($type -eq 'OneDrive') { $loc } else { '' }
        $curLib = if ($type -eq 'SharePoint') { $(if ("$($ctrl.TxtLib.Text)".Trim()) { "$($ctrl.TxtLib.Text)".Trim() } else { 'Documents' }) } else { '' }
        $curKey = @($type.ToLowerInvariant(), $curUrl.ToLowerInvariant(), $curPrin.ToLowerInvariant(), $curLib.ToLowerInvariant(), $land.ToLowerInvariant()) -join '|'
        $others = @()
        foreach ($kv in $script:Map.GetEnumerator()) {
            if ("$($kv.Key)" -eq "$($p.Id)") { continue }
            $od = $kv.Value; if (-not $od) { continue }
            $oProj = $script:Projects | Where-Object { "$($_.Id)" -eq "$($kv.Key)" } | Select-Object -First 1
            if (-not $oProj) { continue }
            $oCo = [bool]("$($od.SourceContentsOnly)".Trim() -match '^(?i)(true|1|yes)$')
            $oSub = if ($od.ContainsKey('SourceSubPath')) { "$($od.SourceSubPath)" } else { '' }
            $oLand = ''
            try { $oLand = Get-GuiLandingPath -DestType $od.DestinationType -SiteUrl $od.DestinationUrl -TargetSubFolder $od.TargetSubFolder -SpaceName $oProj.Name -SourceSubPath $oSub -ContentsOnly $oCo } catch {}
            $oLib = if ($od.ContainsKey('TargetLibrary') -and "$($od.TargetLibrary)".Trim()) { "$($od.TargetLibrary)".Trim() } else { $(if ("$($od.DestinationType)" -eq 'SharePoint') { 'Documents' } else { '' }) }
            $oKey = @("$($od.DestinationType)".ToLowerInvariant(), "$($od.DestinationUrl)".ToLowerInvariant(), "$($od.TargetPrincipal)".ToLowerInvariant(), $oLib.ToLowerInvariant(), $oLand.ToLowerInvariant()) -join '|'
            if ($oKey -eq $curKey) { $others += $oProj.Name }
        }
        if ($others.Count) {
            $ctrl.LblDestWarn.Text = "Note: $($others -join ', ') $(if ($others.Count -eq 1) { 'is' } else { 'are' }) already mapped to this exact same destination folder. Any file with the same name and path in both will silently overwrite the other during the run. Give this $($script:SrcItem) its own destination, or confirm the merge is intentional."
            $ctrl.LblDestWarn.Visibility = 'Visible'
        }
    }
}
function Lzb71d135d7d {
    param([int]$Count)
    return $true
}
function Update-ApplyButtonState {
    if (-not $ctrl.BtnApply) { return }
    $sel = 0; try { $sel = @(Lz6d0d60c1fc).Count } catch { }
    $all = 0; try { $all = @($script:Projects).Count } catch { }
    $p = Get-SelectedProject
    $it  = if ($script:NItem)  { $script:NItem }  else { 'project' }
    $its = if ($script:NItems) { $script:NItems } else { 'projects' }
    $ctrl.BtnApplyAll.Content = if ($all -gt 1) { "Apply to ALL $all $its" } else { "Apply to ALL $its" }
    if ($ctrl.BtnApply.ToolTip)    { $ctrl.BtnApply.ToolTip    = "Set this destination for the selected $it. It saves straight away." }
    if ($ctrl.BtnApplySel.ToolTip) { $ctrl.BtnApplySel.ToolTip = "Set this destination for every $it you have highlighted in the list. Each still goes into its own folder." }
    if ($ctrl.BtnApplyAll.ToolTip) { $ctrl.BtnApplyAll.ToolTip = "Set this destination for every $it in the list, highlighted or not. Each still goes into its own folder." }
    if ($sel -gt 1) {
        $name = if ($p) { $p.Name } else { "this $it" }
        if ($name.Length -gt 24) { $name = $name.Substring(0, 23).TrimEnd() + '...' }
        $ctrl.BtnApply.Content    = "Apply to '$name' only"
        $ctrl.BtnApplySel.Content = "Apply to $sel selected sources"
        $ctrl.BtnApply.FontWeight    = 'Normal'
        $ctrl.BtnApplySel.FontWeight = 'Bold'
        $ctrl.BtnApplySel.IsEnabled  = $true
    } else {
        $ctrl.BtnApply.Content    = "Apply to this $it"
        $ctrl.BtnApplySel.Content = 'Apply to selected sources'
        $ctrl.BtnApply.FontWeight    = 'Bold'
        $ctrl.BtnApplySel.FontWeight = 'Normal'
        $ctrl.BtnApplySel.IsEnabled  = $false
    }
}
function Lz8424928118 {
    if (-not $script:JobOpen) { return }
    $p = Get-SelectedProject
    if (-not $p) { return }
    if (-not $script:Map.ContainsKey($p.Id)) { return }
    if ($ctrl.RbSkip.IsChecked) { return }
    $d = Lz2c1b5ed8d9 -Quiet
    if ($d -eq 'ERR' -or $null -eq $d) { return }
    $sf = @(Lz855e586988)
    $d['SourceSubPaths'] = $sf
    $d['SourceSubPath'] = $(if ($sf.Count) { $sf[0] } else { '' })
    $d['SourceContentsOnly'] = $(if (($sf.Count -le 1) -and $ctrl.ChkSrcContents -and $ctrl.ChkSrcContents.IsChecked) { 'TRUE' } else { '' })
    $cur = $script:Map[$p.Id]
    $curSrc = ''
    if ($cur.ContainsKey('SourceSubPaths') -and $cur.SourceSubPaths) { $curSrc = (@($cur.SourceSubPaths) -join '|') }
    elseif ($cur.ContainsKey('SourceSubPath')) { $curSrc = "$($cur.SourceSubPath)" }
    $curCo = ''; if ($cur.ContainsKey('SourceContentsOnly')) { $curCo = "$($cur.SourceContentsOnly)" }
    $same = ("$($cur.DestinationType)" -eq "$($d.DestinationType)") -and
            ("$($cur.DestinationUrl)"  -eq "$($d.DestinationUrl)")  -and
            ("$($cur.TargetPrincipal)" -eq "$($d.TargetPrincipal)") -and
            ("$($cur.TargetLibrary)"   -eq "$($d.TargetLibrary)")   -and
            ("$($cur.TargetSubFolder)" -eq "$($d.TargetSubFolder)") -and
            ("$curSrc" -eq ($sf -join '|')) -and
            ("$curCo" -eq "$($d.SourceContentsOnly)")
    if ($same) { return }
    $script:Map[$p.Id] = $d
    Lzc219beec58
    Lz5af601c665 "Captured your on-screen changes for '$($p.Name)' before running."
}
function Lzdf2842c3e6 {
    Lz8424928118
    $n = Lz5e06c2c15b
    if (-not $n) { (Show-Msg -Text ("Nothing mapped yet. Set a destination for at least one $($script:NItem) and click Apply.")); return $false }
    Lzf47c317f43 "Saved $n mapping(s)."
    return $true
}
function Lzed1b0733be {
    $script:Map = @{}
    if (-not $script:Cfg) { return }
    $out = Join-Path $script:Cfg.run.reportRoot 'mapping.csv'
    if (-not (Test-Path $out)) { return }
    try {
        foreach ($r in (Import-Csv $out)) {
            if ("$($r.Action)" -ne 'MIGRATE') { continue }
            $id = "$($r.SpaceId)"
            $ssp = ''; if ($r.PSObject.Properties.Name -contains 'SourceSubPath') { $ssp = "$($r.SourceSubPath)".Trim().Trim('/').Trim('\') }
            $sco = ''; if ($r.PSObject.Properties.Name -contains 'SourceContentsOnly') { $sco = "$($r.SourceContentsOnly)" }
            if ($script:Map.ContainsKey($id)) {
                if ($ssp) { [void]$script:Map[$id].SourceSubPaths.Add($ssp) }
            } else {
                $list = New-Object System.Collections.Generic.List[string]
                if ($ssp) { [void]$list.Add($ssp) }
                $script:Map[$id] = @{ DestinationType="$($r.DestinationType)"; DestinationUrl="$($r.DestinationUrl)"; TargetPrincipal="$($r.TargetPrincipal)"; TargetLibrary="$($r.TargetLibrary)"; TargetSubFolder="$($r.TargetSubFolder)"; SourceSubPaths=$list; SourceSubPath=$ssp; SourceContentsOnly=$sco }
            }
        }
        foreach ($id in @($script:Map.Keys)) {
            $m = $script:Map[$id]
            if (@($m.SourceSubPaths).Count -gt 1) { $m.SourceContentsOnly = '' }
            $m.SourceSubPath = $(if (@($m.SourceSubPaths).Count) { @($m.SourceSubPaths)[0] } else { '' })
        }
        if ($script:Map.Count) { Lzf47c317f43 "Loaded $($script:Map.Count) saved mapping(s) for this job." }
    } catch { Lzf47c317f43 "Could not read saved mappings: $($_.Exception.Message)" }
}
$ctrl.BtnPreflight.Add_Click({ if (Lzdf2842c3e6) { Lzb1483e070e -EngineArgs @('-Action','PreFlight') -Label 'Check readiness' } })
$ctrl.BtnDryRun.Add_Click({ if (Lzdf2842c3e6) { Lzb1483e070e -EngineArgs @('-Action','Transfer','-Mode','FirstPass') -Label 'Preview (no upload)' } })
function Lz91df98d57c {
    $mapped = @($script:Projects | Where-Object { $script:Map.ContainsKey($_.Id) })
    $lines = @($mapped | ForEach-Object {
        $d = $script:Map[$_.Id]
        $dest = if ($d.DestinationType -eq 'OneDrive') { "OneDrive: $($d.TargetPrincipal)" } elseif ($d.DestinationType -eq 'SharePoint') { "$($d.DestinationUrl)" } else { '(skip)' }
        "$($_.Name)  ->  $dest"
    })
    $shown = if ($lines.Count -le 8) { $lines } else { @($lines | Select-Object -First 8) + @("... and $($lines.Count - 8) more") }
    $its = if ($script:NItems) { $script:NItems } else { 'projects' }
    $it  = if ($script:NItem)  { $script:NItem }  else { 'project' }
    $label = if ($mapped.Count -eq 1) { "this ${it}:" } else { "these $($mapped.Count) ${its}:" }
    return "$label`n  " + ($shown -join "`n  ")
}
function Lz60593e94bf {
    if (-not $script:ConfigPath) { return $null }
    try { return (Join-Path (Split-Path $script:ConfigPath) '.prechecklist-agreed') } catch { return $null }
}
function Lzdbd333465a {
    $isF = ($script:TransferMode -eq 'LocalFs')
    $ttl = if ($isF) { 'Before you copy, please confirm' } else { 'Before you migrate, please confirm' }
    $intro = if ($isF) { 'This copies your files and folders into Microsoft 365. It only reads from the source and changes nothing there. Before the first upload for this job, please confirm:' } else { 'This copies data from Datto Workplace into Microsoft 365. It only reads from Datto and changes nothing there. Before the first upload for this job, please confirm:' }
    $pt1 = if ($isF) { '1.  You are authorised to copy this data to this Microsoft 365 destination.' } else { '1.  You are authorised to migrate this data from Datto to this Microsoft 365 destination.' }
    $pt5 = if ($isF) { '5.  The copy has first been tested on non-production data.' } else { '5.  The migration has first been tested on non-production data.' }
    [xml]$cx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Before you migrate" Width="580" SizeToContent="Height" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="18,13">
      <TextBlock Text="$ttl" Foreground="White" FontSize="16" FontWeight="SemiBold"/>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="16,11">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnProceed" Content="Proceed" Padding="18,5" Margin="0,0,8,0" IsEnabled="False"/>
        <Button x:Name="BtnCancel" Content="Cancel" Padding="18,5" IsCancel="True"/>
      </StackPanel>
    </Border>
    <StackPanel Margin="20,16">
      <TextBlock TextWrapping="Wrap" Foreground="#1F2937" LineHeight="19" Margin="0,0,0,10"
        Text="$intro"/>
      <TextBlock TextWrapping="Wrap" Margin="0,0,0,4" Text="$pt1"/>
      <TextBlock TextWrapping="Wrap" Margin="0,0,0,4" Text="2.  The destination has an appropriate backup or recovery method."/>
      <TextBlock TextWrapping="Wrap" Margin="0,0,0,4" Text="3.  Those backups have been tested."/>
      <TextBlock TextWrapping="Wrap" Margin="0,0,0,4" Text="4.  Retention and versioning are enabled where appropriate."/>
      <TextBlock TextWrapping="Wrap" Margin="0,0,0,12" Text="$pt5"/>
      <CheckBox x:Name="ChkAgree" Content="I agree to all of the above" FontWeight="SemiBold" Margin="0,0,0,10"/>
      <TextBlock TextWrapping="Wrap" Foreground="#667085" FontSize="12" LineHeight="17"
        Text="This is a one-time check for this job. You can switch it off under Settings &gt; Performance and tuning."/>
    </StackPanel>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $cx))
    Lz2e8ddc8b18 $w
    $chk = $w.FindName('ChkAgree'); $ok = $w.FindName('BtnProceed')
    $script:PreChkWin = $w; $script:PreChkOk = $ok
    $chk.Add_Checked({ $script:PreChkOk.IsEnabled = $true })
    $chk.Add_Unchecked({ $script:PreChkOk.IsEnabled = $false })
    $ok.Add_Click({ $script:PreChkWin.DialogResult = $true })
    return [bool]($w.ShowDialog())
}
function Lz8e8905cf2b {
    try {
        if (-not $script:Cfg) { try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch {} }
        $on = $true
        try { if ($script:Cfg -and ($script:Cfg.run.PSObject.Properties.Name -contains 'confirmations') -and ($script:Cfg.run.confirmations.PSObject.Properties.Name -contains 'preMigrationChecklist')) { $on = [bool]$script:Cfg.run.confirmations.preMigrationChecklist } } catch {}
        if (-not $on) { return $true }
        $marker = Lz60593e94bf
        if ($marker -and (Test-Path $marker)) { return $true }
        $agreed = Lzdbd333465a
        if ($agreed -and $marker) { try { Set-Content -Path $marker -Value ((Get-Date).ToString('o')) -Encoding UTF8 } catch {} }
        return [bool]$agreed
    } catch { return $true }
}
$ctrl.BtnTransfer.Add_Click({
    if (-not (Lzdf2842c3e6)) { return }
    $src = if ($script:TransferMode -eq 'LocalFs') { 'the source' } else { 'Datto' }
    $sot = if ($script:TransferMode -eq 'LocalFs') { 'your files are the source of truth' } else { 'Datto is the source of truth' }
    $sections = @(
        @{ B = (Lz53a0917c36) }
        @{ H = 'What this does'; B = "Copies every file from " + (Lz91df98d57c) }
        @{ H = 'What it changes'; B = "Any file at the destination that also comes from $src is overwritten with $src's version, even if the destination copy is newer." }
        @{ H = 'What it leaves alone'; B = "Existing files at the destination that are not part of this copy (content that was already there and does not come from $src) are untouched. Nothing is deleted." }
        @{ H = 'When to use it'; B = "For the first copy, or to force $src's files back into line (for example to undo edits made in Microsoft 365)." }
        @{ B = 'This makes real changes.' }
    )
    if (-not (Lze80902559b -Title 'Full migration' -Heading "Full migration  -  $sot" -Sections $sections -Yes 'Full migration' -No 'Cancel')) { return }
    if (-not (Lz8e8905cf2b)) { return }
    if (-not (Lzd08008ed5a)) { return }
    Lzb1483e070e -EngineArgs @('-Action','Transfer','-Mode','FirstPass','-Execute') -Label 'Full migration'
})
function Lz81a66801b1 {
    [xml]$sx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sync new and changed" Width="600" SizeToContent="Height" MaxHeight="760" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="20,15">
      <TextBlock Text="Sync new and changed  -  merge into what is already there" Foreground="White" FontSize="16" FontWeight="SemiBold" TextWrapping="Wrap"/>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="16,11">
      <Button x:Name="BtnCancel" Content="Cancel" Padding="16,5" HorizontalAlignment="Right" IsCancel="True"/>
    </Border>
    <StackPanel x:Name="Body" Margin="20,16"/>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $sx))
    Lz2e8ddc8b18 $w
    $body = $w.FindName('Body')
    $intro = New-Object System.Windows.Controls.TextBlock
    $intro.TextWrapping = 'Wrap'; $intro.Foreground = '#1F2937'; $intro.LineHeight = 19; $intro.Margin = '0,0,0,12'
    $src = if ($script:TransferMode -eq 'LocalFs') { 'the source' } else { 'Datto' }
    $intro.Text = "How should Sync decide what to copy for " + (Lz91df98d57c) + "`n`nIt compares $src to the Microsoft 365 copy by modified date, file by file. Pick one:"
    [void]$body.Children.Add($intro)
    $mk = {
        param($title,$sub,$val)
        $b = New-Object System.Windows.Controls.Button
        $b.HorizontalContentAlignment = 'Left'; $b.Margin = '0,0,0,10'; $b.Padding = '14,11'; $b.Tag = $val
        $b.Background = [System.Windows.Media.Brushes]::White
        $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E7EC')))
        $b.BorderThickness = '1'; $b.Cursor = 'Hand'
        $inner = New-Object System.Windows.Controls.StackPanel
        $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = $title; $t1.FontWeight = 'SemiBold'; $t1.FontSize = 14; $t1.Foreground = '#1F2937'
        $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = $sub; $t2.TextWrapping = 'Wrap'; $t2.Foreground = '#667085'; $t2.LineHeight = 18; $t2.Margin = '0,4,0,0'
        [void]$inner.Children.Add($t1); [void]$inner.Children.Add($t2); $b.Content = $inner
        $b.Add_Click({ $script:SyncChoice = [string]$this.Tag; $script:SyncWin.DialogResult = $true })
        [void]$body.Children.Add($b)
    }
    & $mk 'Add new files only' 'Copies files that are not at the destination yet. Never changes or overwrites anything already there. The safest top-up.' 'AddMissing'
    & $mk "Update where $src is newer" "Also replaces a destination file when $src's copy has a newer modified date. Destination files that are the same or newer (for example a document someone edited in SharePoint) are left alone." 'NewerWins'
    $note = New-Object System.Windows.Controls.TextBlock
    $note.TextWrapping = 'Wrap'; $note.Foreground = '#667085'; $note.LineHeight = 18; $note.Margin = '0,2,0,0'
    $note.Text = "It decides by modified date, effectively last edit wins. To force $src's version over a newer destination copy, use 'Full migration' instead."
    [void]$body.Children.Add($note)
    $script:SyncChoice = $null; $script:SyncWin = $w
    [void]$w.ShowDialog()
    return $script:SyncChoice
}
$ctrl.BtnDelta.Add_Click({
    if (-not (Lzdf2842c3e6)) { return }
    $mode = Lz81a66801b1
    if (-not $mode) { return }
    $label = if ($mode -eq 'AddMissing') { 'Sync: add new files only' } else { "Sync: update where $(if ($script:TransferMode -eq 'LocalFs') { 'the source' } else { 'Datto' }) is newer" }
    if (-not (Lz8e8905cf2b)) { return }
    if (-not (Lzd08008ed5a)) { return }
    Lzb1483e070e -EngineArgs @('-Action','Transfer','-Mode','Delta','-DeltaMode',$mode,'-Execute') -Label $label
})
$ctrl.BtnRerunFailed.Add_Click({
    if (-not (Lzdf2842c3e6)) { return }
    $sections = @(
        @{ H = 'What this does'; B = 'Reads the most recent run''s record and re-copies ONLY the files that failed (an error, a download problem, a verification failure, or a file too large). Everything that already succeeded is left exactly as it is.' }
        @{ H = 'When to use it'; B = 'Right after a run that finished with some files reporting a problem, to retry just those without re-checking the whole migration.' }
        @{ H = 'If nothing failed'; B = 'It stops and says there is nothing to rerun, rather than copying anything. It never quietly turns into a full sync.' }
        @{ B = 'This makes real changes, to the failed files only.' }
    )
    if (-not (Lze80902559b -Title 'Rerun failed files only' -Heading 'Rerun failed files only' -Sections $sections -Yes 'Rerun the failed files' -No 'Cancel')) { return }
    if (-not (Lz8e8905cf2b)) { return }
    if (-not (Lzd08008ed5a)) { return }
    Lzb1483e070e -EngineArgs @('-Action','Transfer','-Mode','Delta','-DeltaMode','NewerWins','-Execute','-FailedOnly') -Label 'Rerun failed files only'
})
$ctrl.BtnValidate.Add_Click({
    if (-not (Lzdf2842c3e6)) { return }
    $src = if ($script:TransferMode -eq 'LocalFs') { 'the source' } else { 'Datto' }
    $sections = @(
        @{ H = 'What this checks'; B = "For every file from $src, that a copy exists at the destination and that it is up to date, meaning the destination copy's modified date is not older than $src's copy." }
        @{ H = 'What it reports'; B = "Any file missing at the destination, and any file that is present but out of date (newer in $src than at the destination, so a Sync would refresh it)." }
        @{ H = "How it decides 'up to date'"; B = 'By modified date, the same way Sync does. It is not a byte-for-byte content comparison. Each file''s content is already verified at the moment it is uploaded, so this confirms the destination has the current version. Office files carry their upload date, so they read as up to date, which is correct.' }
        @{ B = 'It changes nothing.' }
    )
    if (-not (Lze80902559b -Title 'Verify files arrived' -Heading 'Verify files arrived' -Sections $sections -Yes 'Run the check' -No 'Cancel')) { return }
    if (-not (Lzd08008ed5a -For 'verify')) { return }
    Lzb1483e070e -EngineArgs @('-Action','Validate') -Label 'Verify files arrived'
})
$ctrl.BtnSizeCheck.Add_Click({ if (Lzdf2842c3e6) { Lzb1483e070e -EngineArgs @('-Action','SizeCheck') -Label 'Compare sizes' } })
$ctrl.BtnDrift.Add_Click({ if (Lzdf2842c3e6) { Lzb1483e070e -EngineArgs @('-Action','Drift') -Label 'Check for drift' } })
function Lz675256916c {
    if (-not $script:Cfg) { try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch { return $null } }
    return $script:Cfg.run.reportRoot
}
function Lz601d2527de {
    try {
        $rr = Lz675256916c
        if (-not $rr -or -not (Test-Path $rr)) { return $false }
        $a = Get-ChildItem (Join-Path $rr 'audit-*.csv') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $a) { return $false }
        $fs = @('Error','DownloadError','VerifyFail','SkippedTooLarge')
        return [bool](@(Import-Csv $a.FullName | Where-Object { $fs -contains "$($_.Status)" } | Select-Object -First 1).Count)
    } catch { return $false }
}
function Lz4ed508442b {
    try { if ($ctrl.BtnRerunFailed) { $ctrl.BtnRerunFailed.IsEnabled = (Lz601d2527de) } } catch {}
}
function Lzffd4f442fb {
    if (-not $script:Cfg) { try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch { return $null } }
    return $script:Cfg.run.logRoot
}
function Lz4bb08b0f51 {
    param([string]$Name)
    if ($Name -match '^(.+?) - (\d{4}-\d{2}-\d{2}) (\d{2})\.(\d{2})\.(\d{2}) - api-.+-\d+\.log$') {
        $when = ''
        try { $when = ([datetime]"$($Matches[2]) $($Matches[3]):$($Matches[4]):$($Matches[5])").ToString('dd MMM yyyy  HH:mm:ss') } catch {}
        return @{ What = "$($Matches[1])"; When = $when }
    }
    $when = ''
    if ($Name -match '(\d{8})-(\d{6})') { try { $when = ([datetime]::ParseExact($Matches[1] + $Matches[2],'yyyyMMddHHmmss',$null)).ToString('dd MMM yyyy  HH:mm:ss') } catch {} }
    $map = @{
        'FirstPass'='Full migration'; 'transfer-FirstPass'='Full migration'
        'Delta'='Sync new and changed'; 'transfer-Delta'='Sync new and changed'
        'Resume'='Resume'; 'transfer-Resume'='Resume'
        'validation'='Verify files arrived'; 'validate'='Verify files arrived'; 'preflight'='Check readiness'
        'sizecheck'='Compare sizes'; 'report'='Report'; 'permissions'='Permissions'; 'test'='Connection test'
        'finalize'='Run finalisation record'
        'destinv'='Destination read'; 'discovery'='List projects'
    }
    $rt = $null
    if ($Name -match '^report-([A-Za-z]+)-\d{8}') { $rt = $Matches[1] }
    elseif ($Name -match '^audit-([A-Za-z]+)-') { $rt = $Matches[1] }
    elseif ($Name -match '^api-([A-Za-z-]+?)-\d{8}') { $rt = $Matches[1] }
    $what = if ($rt -and $map.ContainsKey($rt)) { $map[$rt] } elseif ($Name -like 'report-*') { 'Report' } elseif ($rt) { $rt } else { $Name }
    return @{ What = $what; When = $when }
}
function Lzdec6adddc0 {
    param([string]$Folder, [string[]]$Patterns, [string]$Title, [string]$EmptyMsg, [string[]]$Exclude = @())
    if (-not $script:JobOpen) { (Show-Msg -Text ('Open a migration job first. Logs and reports live inside each job.')); return }
    if (-not $Folder -or -not (Test-Path $Folder)) { (Show-Msg -Text ($EmptyMsg)); return }
    $files = @(); foreach ($p in $Patterns) { $files += @(Get-ChildItem (Join-Path $Folder $p) -File -ErrorAction SilentlyContinue) }
    if ($Exclude.Count) { $files = @($files | Where-Object { $n = $_.Name; -not ($Exclude | Where-Object { $n -like $_ }) }) }
    $files = @($files | Sort-Object LastWriteTime -Descending)
    if (-not $files.Count) { (Show-Msg -Text ($EmptyMsg)); return }
    $rows = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($f in $files) { $l = Lz4bb08b0f51 $f.Name; $rows.Add([pscustomobject]@{ What = $l.What; When = $l.When; File = $f.Name; Path = $f.FullName }) }
    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Open" Width="720" Height="460" FontFamily="Segoe UI" FontSize="13" Background="White" WindowStartupLocation="CenterScreen">
  <DockPanel Margin="12">
    <TextBlock DockPanel.Dock="Top" Text="Pick one to open (newest first). Double-click, or select and click Open." Margin="0,0,0,8"/>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
      <Button x:Name="BtnOpen" Content="Open" Padding="16,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnCancel" Content="Cancel" Padding="16,4" IsCancel="True"/>
    </StackPanel>
    <DataGrid x:Name="Grid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal" RowHeaderWidth="0" BorderBrush="#E4E7EC" BorderThickness="1">
      <DataGrid.Columns>
        <DataGridTextColumn Header="What" Binding="{Binding What}" Width="210"/>
        <DataGridTextColumn Header="When" Binding="{Binding When}" Width="200"/>
        <DataGridTextColumn Header="File" Binding="{Binding File}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
"@
    $pw = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $px))
    Lz2e8ddc8b18 $pw
    $pw.Title = $Title
    $inner = $pw.Content
    $pw.Content = $null
    $outer = New-Object System.Windows.Controls.DockPanel
    $hdr = New-DialogHeader -Title $Title
    [void]$outer.Children.Add($hdr); [void]$outer.Children.Add($inner)
    $pw.Content = $outer
    $grid = $pw.FindName('Grid'); $bo = $pw.FindName('BtnOpen')
    $grid.ItemsSource = $rows; $grid.SelectedIndex = 0
    $script:PickWin = $pw; $script:PickGrid = $grid; $script:PickPath = $null
    $doOpen = { $sel = $script:PickGrid.SelectedItem; if ($sel) { $script:PickPath = $sel.Path; $script:PickWin.DialogResult = $true } }
    $bo.Add_Click($doOpen)
    $grid.Add_MouseDoubleClick($doOpen)
    [void]$pw.ShowDialog()
    if ($script:PickPath) { Start-Process $script:PickPath }
}
$ctrl.BtnOpenReport.Add_Click({ Lzdec6adddc0 -Folder (Lz675256916c) -Patterns @('report-*.html') -Title 'Open a report' -EmptyMsg 'No reports yet. A report is created automatically after each upload or sync.' })
$ctrl.BtnCertificate.Add_Click({
    if (Lzdf2842c3e6) {
        Lzb1483e070e -EngineArgs @('-Action','Certificate') -Label 'Completion certificate' -OnComplete {
            $rr = Lz675256916c
            $cert = $null
            if ($rr -and (Test-Path $rr)) { $cert = Get-ChildItem (Join-Path $rr 'certificate-*.html') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
            if ($cert -and $cert.LastWriteTime -ge $script:RunStart.AddSeconds(-5)) {
                Start-Process $cert.FullName
            } else {
                (Show-Msg -Text ("No certificate was issued. A completion certificate is only produced for a migration that finished: run Upload, then 'Sync new and changed' until nothing is left to copy, and 'Verify files arrived'. Then try this again." + [Environment]::NewLine + [Environment]::NewLine + "The detailed run report is always available from 'Open report'.") -Caption ('Completion certificate') -Icon ('Information')) | Out-Null
            }
        }
    }
})
$ctrl.BtnOpenAudit.Add_Click({ Lzdec6adddc0 -Folder (Lzffd4f442fb) -Patterns @('*.log') -Title 'Open a log' -EmptyMsg 'No logs yet. Run an action first.' -Exclude @('*api-report-*.log','*api-finalize-*.log') })
if ($ctrl.BtnProvenance) { $ctrl.BtnProvenance.Add_Click({
    Lzb1483e070e -EngineArgs @('-Action','Provenance') -Label 'Provenance pack' -OnComplete {
        $rr = Lz675256916c
        $rep = $null
        if ($rr -and (Test-Path $rr)) { $rep = Get-ChildItem (Join-Path $rr 'provenance-*.html') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
        if ($rep -and $rep.LastWriteTime -ge $script:RunStart.AddSeconds(-5)) {
            Start-Process $rep.FullName
        } else {
            (Show-Msg -Text ("No provenance pack was produced. It needs a completed real run first (Upload or Sync) - a preview leaves nothing to attest. Check the log (Open log) for the reason.") -Caption ('Provenance pack') -Icon ('Information')) | Out-Null
        }
    }
}) }
if ($ctrl.BtnHandoverPack) { $ctrl.BtnHandoverPack.Add_Click({
    Lz629ddae0f6
}) }
if ($ctrl.BtnCommsPack) { $ctrl.BtnCommsPack.Add_Click({
    Set-Busy $true 'Building the cutover comms pack...'
    try { $b = Lzdcbc49e58d } finally { Set-Busy $false }
    if (-not $b) { return }
    try { Start-Process 'explorer.exe' -ArgumentList "/select,`"$($b.Zip)`"" } catch {}
    (Show-Msg -Text ("Cutover comms pack built: $($b.Zip)`n`nEmail templates, a 'finding your files' one-pager and mapped-drive notes for $($b.Mappings) mapping(s), ready to hand to whoever runs the cutover with end users.") -Caption ('Cutover comms pack') -Icon ('Information')) | Out-Null
}) }
if ($ctrl.BtnSourceReview) { $ctrl.BtnSourceReview.Add_Click({
    if (Lzdf2842c3e6) {
        Lzb1483e070e -EngineArgs @('-Action','SourceReview') -Label 'Datto source review' -OnComplete {
            $rr = Lz675256916c
            $rep = $null
            if ($rr -and (Test-Path $rr)) { $rep = Get-ChildItem (Join-Path $rr 'report-SourceReview-*.html') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
            if ($rep -and $rep.LastWriteTime -ge $script:RunStart.AddSeconds(-5)) {
                Start-Process $rep.FullName
            } else {
                (Show-Msg -Text ("The source review report was not produced. Check the log (Open log) for the reason - usually the Datto connection failed, no folders are selected, or the scan was stopped.") -Caption ('Datto source review') -Icon ('Warning')) | Out-Null
            }
        }
    }
}) }
function Lz23c5b5fb2a {
    if (-not $script:Cfg) { (Show-Msg -Text ('Open a migration job first.')); return }
    $u = 0; [void][int]::TryParse(("$($ctrl.TxtCapUp.Text)").Trim(), [ref]$u);   if ($u -lt 0) { $u = 0 }
    $d = 0; [void][int]::TryParse(("$($ctrl.TxtCapDown.Text)").Trim(), [ref]$d); if ($d -lt 0) { $d = 0 }
    $ctrl.TxtCapUp.Text = "$u"; $ctrl.TxtCapDown.Text = "$d"
    try {
        $stateRoot = $script:Cfg.run.stateRoot
        if ($stateRoot) {
            if (-not (Test-Path $stateRoot)) { New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null }
            @{ maxUploadMbps = $u; maxDownloadMbps = $d } | ConvertTo-Json | Set-Content -Path (Join-Path $stateRoot 'bandwidth.control.json') -Encoding UTF8
        }
    } catch {}
    try {
        $cfg = Read-ConfigJson $script:ConfigPath
        $burst = 1; if (($cfg.run.PSObject.Properties.Name -contains 'bandwidth') -and ($cfg.run.bandwidth.PSObject.Properties.Name -contains 'burstSeconds') -and $cfg.run.bandwidth.burstSeconds) { $burst = [int]$cfg.run.bandwidth.burstSeconds }
        if (-not ($cfg.run.PSObject.Properties.Name -contains 'bandwidth')) { $cfg.run | Add-Member -NotePropertyName bandwidth -NotePropertyValue ([pscustomobject]@{}) -Force }
        $cfg.run.bandwidth = [pscustomobject]@{ maxUploadMbps = $u; maxDownloadMbps = $d; burstSeconds = $burst }
        Write-ConfigJson -Cfg $cfg -Path $script:ConfigPath
        $script:Cfg = $cfg
    } catch {}
    $uTxt = if ($u -gt 0) { "$u Mb/s" } else { 'off' }
    $dTxt = if ($d -gt 0) { "$d Mb/s" } else { 'off' }
    Lz5af601c665 "Speed limit set: up $uTxt, down $dTxt"
    Add-EngineLine "----- Speed limit set: up $uTxt, down $dTxt (applies immediately to a running upload) -----"
}
$ctrl.BtnApplyCap.Add_Click({ Lz23c5b5fb2a })
$ctrl.TxtCapUp.Add_KeyDown({ param($s,$e) if ($e.Key -eq 'Return') { Lz23c5b5fb2a } })
$ctrl.TxtCapDown.Add_KeyDown({ param($s,$e) if ($e.Key -eq 'Return') { Lz23c5b5fb2a } })
function Lzc3faca26a7 {
    param([int]$ParentId)
    try { Get-CimInstance Win32_Process -Filter "ParentProcessId=$ParentId" -ErrorAction SilentlyContinue | ForEach-Object { Lzc3faca26a7 -ParentId ([int]$_.ProcessId) } } catch {}
    try { Stop-Process -Id $ParentId -Force -ErrorAction SilentlyContinue } catch {}
}
function Get-MinOfDay { param([datetime]$D) return ($D.Hour * 60 + $D.Minute) }
function Format-MinOfDay { param([int]$M) return ('{0:00}:{1:00}' -f [int][math]::Floor($M / 60), ($M % 60)) }
function ConvertTo-MinOfDay {
    param([string]$S)
    if ("$S" -match '^\s*(\d{1,2}):(\d{2})\s*$') { $h = [int]$Matches[1]; $mi = [int]$Matches[2]; if ($h -ge 0 -and $h -le 23 -and $mi -ge 0 -and $mi -le 59) { return ($h * 60 + $mi) } }
    return $null
}
function Test-InWindow {
    param([int]$M,[int]$From,[int]$To)
    if ($From -eq $To) { return $true }
    if ($From -lt $To) { return ($M -ge $From -and $M -lt $To) }
    return ($M -ge $From -or $M -lt $To)
}
function Get-NextWindowOpen { param([int]$FromMin) $now = Get-Date; $t = $now.Date.AddMinutes($FromMin); if ($t -le $now) { $t = $t.AddDays(1) }; return $t }
function Test-ScheduleBusy {
    $r = ($script:Proc -and -not $script:Proc.HasExited)
    $f = ($script:FinProc -and -not $script:FinProc.HasExited)
    return ($r -or $f)
}
function Lz376adc6e5d { param([string]$T) try { $ctrl.BtnSchedule.Content = $T } catch {} }
function Lz965f94e75c {
    param([string]$Why = '')
    if ($script:SchedTimer) { try { $script:SchedTimer.Stop() } catch {}; $script:SchedTimer = $null }
    $script:Sched = $null
    Lz376adc6e5d 'Schedule / Night Runs'
    if ($Why) { Lz5af601c665 $Why }
}
function Lz58e9664e23 {
    try { $p = Join-Path (Lz675256916c) 'lastrun-outcome.json'; if (Test-Path $p) { return (Get-Content $p -Raw | ConvertFrom-Json) } } catch {}
    return $null
}
function Lz5383c70697 {
    if (-not $script:Proc -or $script:Proc.HasExited) { return }
    $script:QuietPausing = $true
    $ctrl.BtnStop.IsEnabled = $false
    Add-EngineLine "----- Quiet hours reached at $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')): pausing the copy. Files already uploaded are kept. -----"
    Lz5af601c665 'Quiet hours: pausing until the next window...'
    try { Lzc3faca26a7 -ParentId ([int]$script:Proc.Id) } catch {}
    Lzb80bda68cf -Status Cancelled -Note 'Finalising for quiet hours...' -OnDone {
        try { Add-EngineLine '----- Paused for quiet hours. It will resume as a Sync at the next window while this app stays open. -----' } catch {}
    }
}
function Lzf1b9a4422d {
    param([string[]]$RunArgs,[string]$Label)
    Add-EngineLine "----- Scheduled: starting '$Label' at $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -----"
    Lzb1483e070e -EngineArgs $RunArgs -Label $Label
    return ($script:Proc -and -not $script:Proc.HasExited)
}
function Lza514276f42 { param([string]$Status)
    $msg = if ($Status -eq 'COMPLETED') { 'The scheduled migration has completed. Open the report or issue a completion certificate from the tiles.' }
           else { "The scheduled run has finished (status: $Status). Open the report for detail." }
    (Show-Msg -Text ($msg) -Caption ('Scheduled run') -Icon ('Information')) | Out-Null
}
function Lz991f11b815 {
    if (-not $script:Sched) { return }
    $s = $script:Sched
    $now = Get-Date
    $m = Get-MinOfDay $now
    $busy = Test-ScheduleBusy
    switch ("$($s.State)") {
        'waiting' {
            if ($now -ge $s.StartAt -and -not $busy) {
                if ($s.Mode -eq 'window' -and -not (Test-InWindow $m $s.FromMin $s.ToMin)) { $s.State = 'paused' }
                elseif (Lzf1b9a4422d -RunArgs $s.Args -Label $s.Label) { $s.State = 'running'; $s.Launches++ }
                else { Lz965f94e75c -Why 'The scheduled run could not start (see the message). Schedule cancelled.' }
            } else {
                $left = $s.StartAt - $now; if ($left.Ticks -lt 0) { $left = [TimeSpan]::Zero }
                Lz376adc6e5d ("Scheduled: starts $($s.StartAt.ToString('ddd HH:mm')) ($(Format-Span $left) to go) - click to cancel")
            }
        }
        'running' {
            if (-not $busy) {
                $oc = Lz58e9664e23; $status = if ($oc) { "$($oc.Status)" } else { '' }
                if ($s.Mode -eq 'once') { Lz965f94e75c -Why 'Scheduled run finished.'; Lza514276f42 $status }
                elseif ($status -eq 'COMPLETED') { Lz965f94e75c -Why 'Scheduled migration completed.'; Lza514276f42 $status }
                else { $s.State = 'paused' }
            } elseif ($s.Mode -eq 'window' -and -not (Test-InWindow $m $s.FromMin $s.ToMin)) {
                Lz5383c70697; $s.State = 'paused'
            } else {
                $until = if ($s.Mode -eq 'window') { " (until $(Format-MinOfDay $s.ToMin))" } else { '' }
                Lz376adc6e5d ("Scheduled: running$until - click to cancel")
            }
        }
        'paused' {
            if ((Test-InWindow $m $s.FromMin $s.ToMin) -and -not $busy) {
                if (Lzf1b9a4422d -RunArgs @('-Action','Transfer','-Mode','Delta','-DeltaMode','AddMissing','-Execute') -Label 'Sync new and changed') { $s.State = 'running'; $s.Launches++ }
            } else {
                $nf = Get-NextWindowOpen $s.FromMin
                Lz376adc6e5d ("Scheduled: waiting for the next window ($($nf.ToString('ddd HH:mm'))) - click to cancel")
            }
        }
    }
}
function Lz6d2abaae02 {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [xml]$sx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Schedule the migration" Width="540" SizeToContent="Height" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="White">
  <StackPanel Margin="18">
    <TextBlock TextWrapping="Wrap" Foreground="#475467" Margin="0,0,0,12"
      Text="Start the migration at a time you choose, or only during a nightly window. Leave this app open and the computer awake: the schedule runs here, it is not a Windows scheduled task."/>
    <RadioButton x:Name="RbOnce" GroupName="Mode" IsChecked="True" Margin="0,2,0,2" Content="Run once, starting at:"/>
    <StackPanel Orientation="Horizontal" Margin="22,0,0,8">
      <TextBox x:Name="TxtStart" Width="70" Text="22:00"/>
      <TextBlock Text="  24-hour. Today, or the next day if that time has passed." VerticalAlignment="Center" Foreground="#667085"/>
    </StackPanel>
    <RadioButton x:Name="RbWindow" GroupName="Mode" Margin="0,2,0,2" Content="Run only during a nightly window (quiet hours):"/>
    <StackPanel Orientation="Horizontal" Margin="22,0,0,8">
      <TextBlock Text="From" VerticalAlignment="Center"/>
      <TextBox x:Name="TxtFrom" Width="64" Margin="6,0" Text="22:00"/>
      <TextBlock Text="to" VerticalAlignment="Center"/>
      <TextBox x:Name="TxtTo" Width="64" Margin="6,0" Text="06:00"/>
      <TextBlock Text="each night, until done" VerticalAlignment="Center" Foreground="#667085"/>
    </StackPanel>
    <TextBlock Text="Which copy to run:" FontWeight="SemiBold" Margin="0,8,0,3"/>
    <RadioButton x:Name="RbUpload" GroupName="Run" IsChecked="True" Content="Full migration (first run, copies everything)"/>
    <RadioButton x:Name="RbSync" GroupName="Run" Margin="0,3,0,0" Content="Sync new and changed (safe top-up, never overwrites newer)"/>
    <TextBlock TextWrapping="Wrap" Foreground="#667085" FontSize="12" Margin="0,6,0,0"
      Text="In a nightly window the first night uses your choice above; each following night resumes as a Sync, so nothing already copied is redone."/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="BtnOk" Content="Schedule" Padding="18,5" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BtnCancel" Content="Cancel" Padding="18,5" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $sx))
    Lz2e8ddc8b18 $w
    $inner = $w.Content
    $w.Content = $null
    $outer = New-Object System.Windows.Controls.DockPanel
    $hdr = New-DialogHeader -Title 'Schedule the migration'
    [void]$outer.Children.Add($hdr); [void]$outer.Children.Add($inner)
    $w.Content = $outer
    $get = { param($n) $w.FindName($n) }
    $script:SchedSpec = $null; $script:SchedWin = $w
    (& $get 'BtnOk').Add_Click({
        $mode = if ((& $get 'RbWindow').IsChecked) { 'window' } else { 'once' }
        $run  = if ((& $get 'RbSync').IsChecked) { 'Sync' } else { 'Upload' }
        if ($mode -eq 'once') {
            $sm = ConvertTo-MinOfDay (& $get 'TxtStart').Text
            if ($null -eq $sm) { (Show-Msg -Text ('Enter the start time as HH:mm in 24-hour form, for example 22:00.') -Caption ('Start time') -Icon ('Warning')) | Out-Null; return }
            $script:SchedSpec = @{ Mode='once'; StartMin=$sm; FromMin=$null; ToMin=$null; Run=$run }
        } else {
            $fm = ConvertTo-MinOfDay (& $get 'TxtFrom').Text; $tm = ConvertTo-MinOfDay (& $get 'TxtTo').Text
            if ($null -eq $fm -or $null -eq $tm) { (Show-Msg -Text ('Enter both window times as HH:mm in 24-hour form, for example 22:00 and 06:00.') -Caption ('Quiet hours') -Icon ('Warning')) | Out-Null; return }
            if ($fm -eq $tm) { (Show-Msg -Text ('The window start and end are the same, which means all day. Set different times, for example 22:00 to 06:00.') -Caption ('Quiet hours') -Icon ('Warning')) | Out-Null; return }
            $script:SchedSpec = @{ Mode='window'; StartMin=$fm; FromMin=$fm; ToMin=$tm; Run=$run }
        }
        $script:SchedWin.DialogResult = $true
    })
    [void]$w.ShowDialog()
    return $script:SchedSpec
}
$ctrl.BtnSchedule.Add_Click({
    if ($script:Sched) {
        if ((Show-Msg -Text ("A schedule is set:" + [Environment]::NewLine + $script:Sched.Summary + [Environment]::NewLine + [Environment]::NewLine + "Cancel it?") -Caption ('Scheduled run') -Buttons ('YesNo') -Icon ('Question')) -eq 'Yes') { Lz965f94e75c -Why 'Schedule cancelled.' }
        return
    }
    if (-not $script:JobOpen) { (Show-Msg -Text ('Open or create a migration job first.')) | Out-Null; return }
    if (Test-ScheduleBusy) { (Show-Msg -Text ('A run is in progress. Wait for it to finish, then set a schedule.') -Caption ('Cannot schedule now') -Icon ('Warning')) | Out-Null; return }
    if (-not (Lzdf2842c3e6)) { return }
    $mappedCount = @($script:Projects | Where-Object { $script:Map.ContainsKey($_.Id) }).Count
    if ($mappedCount -eq 0) { (Show-Msg -Text ("Set a destination on at least one $($script:NItem) first (Apply to this $($script:NItem)), then schedule.") -Caption ('Nothing to schedule') -Icon ('Warning')) | Out-Null; return }
    $spec = Lz6d2abaae02
    if (-not $spec) { return }
    if (-not (Lz8e8905cf2b)) { return }
    if (-not (Lzd08008ed5a)) { return }
    $firstArgs  = if ($spec.Run -eq 'Upload') { @('-Action','Transfer','-Mode','FirstPass','-Execute') } else { @('-Action','Transfer','-Mode','Delta','-DeltaMode','AddMissing','-Execute') }
    $firstLabel = if ($spec.Run -eq 'Upload') { 'Full migration' } else { 'Sync new and changed' }
    $now = Get-Date
    if ($spec.Mode -eq 'once') {
        $today = $now.Date.AddMinutes($spec.StartMin)
        $startAt = if ($today -gt $now.AddSeconds(20)) { $today } else { $today.AddDays(1) }
        $summary = "$firstLabel at $($startAt.ToString('ddd dd MMM HH:mm'))"
        $script:Sched = @{ Mode='once'; StartAt=$startAt; FromMin=0; ToMin=0; Args=$firstArgs; Label=$firstLabel; State='waiting'; Summary=$summary; Launches=0 }
    } else {
        $todayFrom = $now.Date.AddMinutes($spec.FromMin)
        $startAt = if (Test-InWindow (Get-MinOfDay $now) $spec.FromMin $spec.ToMin) { $now } elseif ($todayFrom -gt $now) { $todayFrom } else { $todayFrom.AddDays(1) }
        $summary = "$firstLabel nightly $(Format-MinOfDay $spec.FromMin)-$(Format-MinOfDay $spec.ToMin), from $($startAt.ToString('ddd dd MMM HH:mm'))"
        $script:Sched = @{ Mode='window'; StartAt=$startAt; FromMin=$spec.FromMin; ToMin=$spec.ToMin; Args=$firstArgs; Label=$firstLabel; State='waiting'; Summary=$summary; Launches=0 }
    }
    $script:SchedTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SchedTimer.Interval = [TimeSpan]::FromSeconds(20)
    $script:SchedTimer.Add_Tick({ try { Lz991f11b815 } catch {} })
    $script:SchedTimer.Start()
    try { Lz991f11b815 } catch {}
    (Show-Msg -Text ("Scheduled: " + $script:Sched.Summary + "." + [Environment]::NewLine + [Environment]::NewLine + "Leave this app open and the computer awake. Click the schedule button again at any time to cancel.") -Caption ('Scheduled') -Icon ('Information')) | Out-Null
})
$ctrl.BtnStop.Add_Click({
    if (-not $script:Proc -or $script:Proc.HasExited) { $ctrl.BtnStop.IsEnabled = $false; return }
    if ((Show-Msg -Text ("Stop the current copy?`n`nFiles already uploaded and verified are kept. You can carry on later with 'Sync new and changed'.") -Caption ('Confirm stop') -Buttons ('YesNo') -Icon ('Warning')) -ne 'Yes') { return }
    if ($script:Sched) { Lz965f94e75c -Why 'Schedule cancelled (you stopped the run).' }
    $script:Stopping = $true
    $ctrl.BtnStop.IsEnabled = $false
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-EngineLine "----- STOP requested by user at $stamp -----"
    Lz5af601c665 "Stopping $($script:CurLabel)..."
    try { Lzc3faca26a7 -ParentId ([int]$script:Proc.Id) } catch {}
    try {
        if ($script:Cfg -and $script:Cfg.run.logRoot -and (Test-Path $script:Cfg.run.logRoot)) {
            $lf = Get-ChildItem (Join-Path $script:Cfg.run.logRoot '*.log') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($lf) { Add-Content -Path $lf.FullName -Value ((Get-Date -Format 'o') + " [WARN] STOPPED BY USER during '$($script:CurLabel)'. Files already uploaded and verified are recorded; resume with 'Sync new and changed'.") }
        }
    } catch {}
    Lzb80bda68cf -Status Cancelled -Note 'Finalising the cancelled run...' -OnDone {
        try { Add-EngineLine "----- Cancellation recorded. A report has been saved; click 'Open report' to view it. -----" } catch {}
    }
})
function Lz51678e1ed7 {
    [xml]$rx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Resume the paused upload" Width="600" SizeToContent="Height" MaxHeight="760" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="White">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#0F1115" Padding="20,15">
      <TextBlock Text="Resume the paused upload" Foreground="White" FontSize="16" FontWeight="SemiBold"/>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#F7F8FA" BorderBrush="#E4E7EC" BorderThickness="0,1,0,0" Padding="16,11">
      <Button x:Name="BtnCancel" Content="Cancel" Padding="16,5" HorizontalAlignment="Right" IsCancel="True"/>
    </Border>
    <StackPanel x:Name="Body" Margin="20,16"/>
  </DockPanel>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $rx))
    Lz2e8ddc8b18 $w
    $body = $w.FindName('Body')
    $intro = New-Object System.Windows.Controls.TextBlock
    $intro.TextWrapping = 'Wrap'; $intro.Foreground = '#1F2937'; $intro.LineHeight = 19; $intro.Margin = '0,0,0,12'
    $intro.Text = "You paused 'Full migration'. Everything already uploaded and verified is saved.`n`nThat upload copies every file and overwrites the destination with the Datto version, so carrying on is not quite the same job. Pick one:"
    [void]$body.Children.Add($intro)
    $mk = {
        param($title,$sub,$val)
        $b = New-Object System.Windows.Controls.Button
        $b.HorizontalContentAlignment = 'Left'; $b.Margin = '0,0,0,10'; $b.Padding = '14,11'; $b.Tag = $val
        $b.Background = [System.Windows.Media.Brushes]::White
        $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E7EC')))
        $b.BorderThickness = '1'; $b.Cursor = 'Hand'
        $inner = New-Object System.Windows.Controls.StackPanel
        $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = $title; $t1.FontWeight = 'SemiBold'; $t1.FontSize = 14; $t1.Foreground = '#1F2937'
        $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = $sub; $t2.TextWrapping = 'Wrap'; $t2.Foreground = '#667085'; $t2.LineHeight = 18; $t2.Margin = '0,4,0,0'
        [void]$inner.Children.Add($t1); [void]$inner.Children.Add($t2); $b.Content = $inner
        $b.Add_Click({ $script:ResumeChoice = [string]$this.Tag; $script:ResumeWin.DialogResult = $true })
        [void]$body.Children.Add($b)
    }
    & $mk 'Carry on from where it stopped' 'Copies what is still missing, and replaces a destination file where the Datto copy is newer. Does not redo the files already uploaded, so it picks up roughly where you paused. The one difference from the paused upload: a destination file that is NEWER than Datto is left alone rather than overwritten.' 'Carry'
    & $mk 'Start the full upload again' 'Runs Full migration from the beginning: every file re-copied and the destination overwritten with the Datto version, including the files already done. Exactly what the paused run promised, but it repeats the finished work.' 'Full'
    $note = New-Object System.Windows.Controls.TextBlock
    $note.TextWrapping = 'Wrap'; $note.Foreground = '#667085'; $note.LineHeight = 18; $note.Margin = '0,2,0,0'
    $note.Text = "Cancel leaves the run paused, so you can decide later. Either choice keeps the files already uploaded, and both carry on from the file list this run started with rather than reading Datto again. So anything added to Datto since it started is picked up by a later 'Sync new and changed', not by this run. That is true of any long run, because the list is always a snapshot from when it started."
    [void]$body.Children.Add($note)
    $script:ResumeChoice = $null; $script:ResumeWin = $w
    [void]$w.ShowDialog()
    return $script:ResumeChoice
}
if ($ctrl.BtnPause) { $ctrl.BtnPause.Add_Click({
    if ($script:Paused) {
        $rargs = @($script:LastRunArgs)
        if (-not $rargs -or $rargs.Count -eq 0) {
            [void](Show-Msg -Text ("There is no record of what was paused, so it cannot be resumed automatically. Start the run you want from the tiles above; anything already uploaded is kept and will not be redone.") -Caption ('Resume') -Buttons ('OK') -Icon ('Warning'))
            return
        }
        $rlabel = "Resume: " + ("$($script:LastRunLabel)" -replace '^Resume: ','')
        $mi = [array]::IndexOf($rargs, '-Mode')
        $rmode = if ($mi -ge 0 -and ($mi + 1) -lt $rargs.Count) { "$($rargs[$mi + 1])" } else { '' }
        if (($rargs -contains '-Execute') -and $rmode -eq 'FirstPass') {
            $c = Lz51678e1ed7
            if (-not $c) { return }
            if ($c -eq 'Carry') {
                $rargs = @('-Action','Transfer','-Mode','Delta','-DeltaMode','NewerWins','-Execute')
                $rlabel = 'Resume: carry on (sync, Datto newer wins)'
            } else {
                $rlabel = 'Resume: full upload again'
            }
        }
        if ($rargs -notcontains '-UseEnumCache') { $rargs += '-UseEnumCache' }
        $script:Paused = $false; $ctrl.BtnPauseTitle.Text = 'Pause'
        Lzb1483e070e -EngineArgs $rargs -Label $rlabel
        return
    }
    if (-not $script:Proc -or $script:Proc.HasExited) { $ctrl.BtnPause.IsEnabled = $false; return }
    $script:Paused = $true; $ctrl.BtnPauseTitle.Text = 'Resume'; $ctrl.BtnStop.IsEnabled = $false
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-EngineLine "----- PAUSE requested by user at $stamp -----"
    Lz5af601c665 "Pausing $($script:CurLabel)..."
    try { Lzc3faca26a7 -ParentId ([int]$script:Proc.Id) } catch {}
    try {
        if ($script:Cfg -and $script:Cfg.run.logRoot -and (Test-Path $script:Cfg.run.logRoot)) {
            $lf = Get-ChildItem (Join-Path $script:Cfg.run.logRoot '*.log') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($lf) { Add-Content -Path $lf.FullName -Value ((Get-Date -Format 'o') + " [WARN] PAUSED BY USER during '$($script:CurLabel)'. Files already uploaded and verified are recorded; Resume continues with Sync.") }
        }
    } catch {}
    Lzb80bda68cf -Status Cancelled -Note 'Finalising the paused run...' -OnDone {
        try { Add-EngineLine "----- Paused. What had already uploaded is saved. Click Resume to carry on. -----" } catch {}
    }
}) }
$script:DattoDomains = @(
    'eu.workplace.datto.com','us.workplace.datto.com','ca.workplace.datto.com','au.workplace.datto.com',
    'us.fileprotection.datto.com','eu.fileprotection.datto.com','ca.fileprotection.datto.com','au.fileprotection.datto.com'
)
function Lz0264447111 { param([string]$Domain,[string]$Cell) if (-not $Domain -or -not "$Cell".Trim()) { return '' }; return "https://$Domain/$("$Cell".Trim())/api/v1" }
function Lz33cfd41074 {
    param([string]$Url)
    if ($Url -match '^https?://([^/]+)/([^/]+)/api/v1/?$') { return @{ Domain=$Matches[1]; Cell=$Matches[2] } }
    return @{ Domain=''; Cell='' }
}
function Lz12d7a4ce3d {
    param([string]$SharePointRoot)
    $r = "$SharePointRoot".TrimEnd('/')
    if ($r -notmatch '^https?://([^/.]+)\.sharepoint\.com') { return $null }
    $tenant = $Matches[1]
    return @{ OneDriveHostUrl = "https://$tenant-my.sharepoint.com"; TeamSiteBaseUrl = "$r/sites"; DefaultSiteUrl = "$r/sites/projects" }
}
function Lzef4499bb1e {
    param($Org)
    try {
        $doms = @(@($Org.value)[0].verifiedDomains)
        $best = $doms | Where-Object { $_.isDefault -and ($_.name -notlike '*.onmicrosoft.com') } | Select-Object -First 1
        if (-not $best) { $best = $doms | Where-Object { $_.name -notlike '*.onmicrosoft.com' } | Select-Object -First 1 }
        if (-not $best) { $best = $doms | Where-Object { $_.isDefault } | Select-Object -First 1 }
        if (-not $best) { $best = @($doms)[0] }
        if ($best -and $best.name) { return '@' + $best.name }
    } catch {}
    return ''
}
function Lz1c498583eb {
    param([string]$TenantId,[string]$ClientId,[string]$Thumbprint,[string]$CertStore)
    return (Lzff10dee4f3 -TenantId $TenantId -ClientId $ClientId -Thumbprint $Thumbprint -CertStore $CertStore).Token
}
function Lzcebee496ce {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $win2 = New-Object System.Windows.Window
    Lz2e8ddc8b18 $win2
    $win2.Title='API settings'; $win2.SizeToContent='WidthAndHeight'; $win2.WindowStartupLocation='CenterScreen'; $win2.ResizeMode='NoResize'
    $win2.FontFamily='Segoe UI'; $win2.FontSize=13; $win2.Background='White'
    $dock2 = New-Object System.Windows.Controls.DockPanel; $win2.Content=$dock2
    $hdr2 = New-Object System.Windows.Controls.Border; $hdr2.Background='#0F1115'; $hdr2.Padding='20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdr2,'Top')
    $hs2 = New-Object System.Windows.Controls.StackPanel; $hs2.MaxWidth=560
    $ht2 = New-Object System.Windows.Controls.TextBlock; $ht2.Text='API settings'; $ht2.Foreground='White'; $ht2.FontSize=16; $ht2.FontWeight='SemiBold'
    $hb2 = New-Object System.Windows.Controls.TextBlock; $hb2.Text='Connection settings for this installation. Stored on this computer, never in the migration files.'
    $hb2.Foreground='#9BA1AA'; $hb2.TextWrapping='Wrap'; $hb2.Margin='0,4,0,0'
    [void]$hs2.Children.Add($ht2); [void]$hs2.Children.Add($hb2); $hdr2.Child=$hs2
    [void]$dock2.Children.Add($hdr2)
    $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility='Auto'; $sv.MaxHeight=720
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin='18,14,18,16'; $sv.Content=$root
    [void]$dock2.Children.Add($sv)
    function Lzed6845bbca { param($Text) $h=New-Object System.Windows.Controls.TextBlock; $h.Text=$Text; $h.FontWeight='Bold'; $h.Margin='0,12,0,4'; [void]$root.Children.Add($h) }
    function Lzee6e853f09 { param($Label,$Control,$Info)
        $g=New-Object System.Windows.Controls.Grid
        foreach ($w in '150','380','40') { $c=New-Object System.Windows.Controls.ColumnDefinition; $c.Width=$w; $g.ColumnDefinitions.Add($c) }
        $l=New-Object System.Windows.Controls.TextBlock; $l.Text=$Label; $l.VerticalAlignment='Center'; $l.Margin='0,3,8,3'; $l.TextWrapping='Wrap'
        [System.Windows.Controls.Grid]::SetColumn($l,0); [void]$g.Children.Add($l)
        [System.Windows.Controls.Grid]::SetColumn($Control,1); [void]$g.Children.Add($Control)
        if ($Info) {
            $ib=New-Object System.Windows.Controls.Button; $ib.Content=([char]0xE946); $ib.FontFamily='Segoe MDL2 Assets'; $ib.FontSize=14; $ib.Width=30; $ib.Padding='0,4'; $ib.Margin='4,3,0,3'; $ib.FocusVisualStyle=$null; $ib.VerticalAlignment='Center'; $ib.ToolTip=$Info
            $iTxt=$Info; $iLab=$Label
            $ib.Add_Click({ (Show-Msg -Text ($iTxt) -Caption ($iLab)) | Out-Null }.GetNewClosure())
            [System.Windows.Controls.Grid]::SetColumn($ib,2); [void]$g.Children.Add($ib)
        }
        [void]$root.Children.Add($g); return $Control
    }
    function Lzd2c7861f05 { param($Text) $t=New-Object System.Windows.Controls.TextBox; $t.Margin='0,3,0,3'; $t.Text="$Text"; return $t }
    $dattoFrom = $root.Children.Count
    Lzed6845bbca 'Datto Workplace'
    $cmbDom = New-Object System.Windows.Controls.ComboBox; $cmbDom.Margin='0,3,0,3'
    foreach ($d in $script:DattoDomains) { [void]$cmbDom.Items.Add($d) }
    $parts = Lz33cfd41074 ([string](Get-RegSetting 'DattoEndpointUrl'))
    if ($parts.Domain) { $cmbDom.SelectedItem = $parts.Domain } else { $cmbDom.SelectedIndex = 0 }
    [void](Lzee6e853f09 'Region (domain)' $cmbDom 'Your Datto Workplace region. If the web address you use for Datto starts with "eu", pick the eu one; "us", pick us, and so on. If you are not sure, ask whoever set up your Datto account.')
    $tbCell = Lzee6e853f09 'Cell (number)' (Lzd2c7861f05 ($parts.Cell)) 'A small number that is part of your Datto web address (for example the 2 in .../2/api/v1). You can see it on the Datto API page, or ask your Datto administrator.'
    $tbDId  = Lzee6e853f09 'Datto Client ID' (Lzd2c7861f05 ([string](Get-RegSetting 'DattoClientId'))) 'The username for the Datto connection. In the Datto Workplace admin portal you create an "API integration", which gives you a Client ID and a Secret. This is the Client ID.'
    $pbSec  = New-Object System.Windows.Controls.PasswordBox; $pbSec.Margin='0,3,0,3'
    [void](Lzee6e853f09 'Datto Secret' $pbSec 'The password that goes with the Datto Client ID, from the same Datto API integration. Treat it like a password. Leave blank to keep the one already saved.')
    $secNote=New-Object System.Windows.Controls.TextBlock; $secNote.Text='Leave the secret blank to keep the current one.'; $secNote.Foreground='Gray'; $secNote.FontSize=11; $secNote.Margin='150,0,0,0'; [void]$root.Children.Add($secNote)
    if ($script:TransferMode -eq 'LocalFs') {
        for ($ci = $dattoFrom; $ci -lt $root.Children.Count; $ci++) { $root.Children[$ci].Visibility = 'Collapsed' }
        $dNote=New-Object System.Windows.Controls.TextBlock
        $dNote.Text='This transfer type copies local files and folders, so it uses only the Microsoft 365 connection below. Datto Workplace credentials are managed under the Datto Workplace transfer type (Job > Switch transfer type).'
        $dNote.TextWrapping='Wrap'; $dNote.Foreground='Gray'; $dNote.FontSize=11; $dNote.Margin='0,4,0,4'
        [void]$root.Children.Add($dNote)
    }
    Lzed6845bbca 'Microsoft 365'
    $tbTid = Lzee6e853f09 'Tenant ID' (Lzd2c7861f05 ([string](Get-RegSetting 'TenantId'))) 'Your Microsoft 365 organisation''s unique ID (a long code with dashes). Find it at entra.microsoft.com (Microsoft Entra admin center) on the Overview page, shown as "Tenant ID". Or ask whoever manages your Microsoft 365.'
    $tbApp = Lzee6e853f09 'App (Client) ID' (Lzd2c7861f05 ([string](Get-RegSetting 'GraphClientId'))) 'The ID of the app registration this tool signs in as. In entra.microsoft.com go to App registrations, open the app created for this migration, and copy "Application (client) ID".'
    Lzed6845bbca 'Certificate (sign-in to Microsoft 365)'
    $lblThumb = New-Object System.Windows.Controls.TextBlock; $lblThumb.VerticalAlignment='Center'
    $curThumb = [string](Get-RegSetting 'CertThumbprint'); $lblThumb.Text = if ($curThumb) { $curThumb } else { '(none installed)' }
    [void](Lzee6e853f09 'Thumbprint' $lblThumb 'A fingerprint of the sign-in certificate. You do not type this: it fills in automatically when you install the .pfx file below.')
    $tbPfx = Lzee6e853f09 '.pfx file' (Lzd2c7861f05 '') 'The certificate file (its name ends in .pfx) that lets the tool sign in to Microsoft 365. Your IT contact provides it. Click Browse to pick it.'
    $btnBrowse = New-Object System.Windows.Controls.Button; $btnBrowse.Content='Browse...'; $btnBrowse.Padding='8,2'
    $pbPfx = New-Object System.Windows.Controls.PasswordBox; $pbPfx.Margin='0,3,0,3'
    [void](Lzee6e853f09 '.pfx password' $pbPfx 'The password for the .pfx file, supplied together with the certificate by your IT contact.')
    $btnInstall = New-Object System.Windows.Controls.Button; $btnInstall.Content='Install certificate'; $btnInstall.Padding='8,3'
    $rowCert=New-Object System.Windows.Controls.StackPanel; $rowCert.Orientation='Horizontal'; $rowCert.Margin='150,3,0,3'
    [void]$rowCert.Children.Add($btnBrowse); [void]$rowCert.Children.Add($btnInstall); [void]$root.Children.Add($rowCert)
    $lblCert=New-Object System.Windows.Controls.TextBlock; $lblCert.Foreground='Gray'; $lblCert.TextWrapping='Wrap'; $lblCert.Margin='150,2,0,0'; [void]$root.Children.Add($lblCert)
    Lzed6845bbca 'SharePoint and OneDrive'
    $spNote=New-Object System.Windows.Controls.TextBlock; $spNote.Text='Tip: the "Auto-detect URLs" button below fills these in for you once the tenant and certificate are set.'; $spNote.Foreground='Gray'; $spNote.FontSize=11; $spNote.TextWrapping='Wrap'; $spNote.Margin='0,0,0,4'; [void]$root.Children.Add($spNote)
    $tbSp  = Lzee6e853f09 'SharePoint root URL' (Lzd2c7861f05 ([string](Get-RegSetting 'SharePointRootUrl'))) 'Your SharePoint web address, for example https://yourcompany.sharepoint.com. It is the address you see when you open SharePoint in a browser. Auto-detect can fill this for you.'
    $tbOd  = Lzee6e853f09 'OneDrive host URL'   (Lzd2c7861f05 ([string](Get-RegSetting 'OneDriveHostUrl'))) 'Your OneDrive web address. It is usually your SharePoint address with "-my" added, for example https://yourcompany-my.sharepoint.com. Auto-detect fills it.'
    $tbTs  = Lzee6e853f09 'Team site base URL'  (Lzd2c7861f05 ([string](Get-RegSetting 'TeamSiteBaseUrl'))) 'Where your SharePoint team sites live, usually your SharePoint address followed by /sites. Auto-detect fills it.'
    $tbDef = Lzee6e853f09 'Default site URL'    (Lzd2c7861f05 ([string](Get-RegSetting 'DefaultSiteUrl'))) 'The SharePoint site suggested by default when you set up a new project. Auto-detect fills it, and you can change it for each project.'
    $tbUpn = Lzee6e853f09 'Email / UPN domain'  (Lzd2c7861f05 ([string](Get-RegSetting 'UpnDomain'))) 'Your organisation''s email domain, for example @yourcompany.com. It is used to find each person''s OneDrive. Auto-detect can fill it if the permission is granted; otherwise type it.'
    $btnAuto = New-Object System.Windows.Controls.Button; $btnAuto.Content='Auto-detect URLs'; $btnAuto.Padding='8,3'; $btnAuto.Margin='150,4,0,0'; $btnAuto.HorizontalAlignment='Left'; [void]$root.Children.Add($btnAuto)
    $lblAuto=New-Object System.Windows.Controls.TextBlock; $lblAuto.Foreground='Gray'; $lblAuto.TextWrapping='Wrap'; $lblAuto.Margin='150,2,0,0'; [void]$root.Children.Add($lblAuto)
    $btnRow=New-Object System.Windows.Controls.DockPanel; $btnRow.Margin='0,16,0,0'; $btnRow.LastChildFill=$false
    $leftBtns=New-Object System.Windows.Controls.StackPanel; $leftBtns.Orientation='Horizontal'; [System.Windows.Controls.DockPanel]::SetDock($leftBtns,'Left')
    $btnClear=New-Object System.Windows.Controls.Button; $btnClear.Content='Clear all'; $btnClear.Padding='12,4'; $btnClear.Background='#FECDCA'; $btnClear.ToolTip='Remove these connection settings (and optionally the certificate) from this computer, for privacy or when decommissioning.'
    $btnClearJobs=New-Object System.Windows.Controls.Button; $btnClearJobs.Content='Clear job data'; $btnClearJobs.Padding='12,4'; $btnClearJobs.Margin='8,0,0,0'; $btnClearJobs.Background='#FECDCA'
    $btnJobsInfo=New-Object System.Windows.Controls.Button; $btnJobsInfo.Content=([char]0xE946); $btnJobsInfo.FontFamily='Segoe MDL2 Assets'; $btnJobsInfo.Padding='0,4'; $btnJobsInfo.Width=26; $btnJobsInfo.Margin='4,0,0,0'; $btnJobsInfo.FocusVisualStyle=$null
    [void]$leftBtns.Children.Add($btnClear); [void]$leftBtns.Children.Add($btnClearJobs); [void]$leftBtns.Children.Add($btnJobsInfo)
    [void]$btnRow.Children.Add($leftBtns)
    $rightBtns=New-Object System.Windows.Controls.StackPanel; $rightBtns.Orientation='Horizontal'; [System.Windows.Controls.DockPanel]::SetDock($rightBtns,'Right')
    $btnTest=New-Object System.Windows.Controls.Button; $btnTest.Content='Test connection'; $btnTest.Padding='12,4'; $btnTest.Margin='0,0,8,0'
    $btnSave=New-Object System.Windows.Controls.Button; $btnSave.Content='Save'; $btnSave.Padding='16,4'; $btnSave.Margin='0,0,8,0'; $btnSave.IsDefault=$true
    $btnCancel=New-Object System.Windows.Controls.Button; $btnCancel.Content='Close'; $btnCancel.Padding='16,4'; $btnCancel.IsCancel=$true
    [void]$rightBtns.Children.Add($btnTest); [void]$rightBtns.Children.Add($btnSave); [void]$rightBtns.Children.Add($btnCancel)
    [void]$btnRow.Children.Add($rightBtns); [void]$root.Children.Add($btnRow)
    $lblStatus=New-Object System.Windows.Controls.TextBlock; $lblStatus.TextWrapping='Wrap'; $lblStatus.Margin='0,8,0,0'; [void]$root.Children.Add($lblStatus)
    $script:AS = @{
        win2=$win2; cmbDom=$cmbDom; tbCell=$tbCell; tbDId=$tbDId; pbSec=$pbSec
        tbTid=$tbTid; tbApp=$tbApp; lblThumb=$lblThumb; tbPfx=$tbPfx; pbPfx=$pbPfx; lblCert=$lblCert
        tbSp=$tbSp; tbOd=$tbOd; tbTs=$tbTs; tbDef=$tbDef; tbUpn=$tbUpn; lblAuto=$lblAuto; lblStatus=$lblStatus
    }
    $btnBrowse.Add_Click({
        $dlg=New-Object Microsoft.Win32.OpenFileDialog; $dlg.Filter='Certificate (*.pfx)|*.pfx|All files (*.*)|*.*'
        if ($dlg.ShowDialog()) { $script:AS.tbPfx.Text=$dlg.FileName }
    })
    $btnInstall.Add_Click({
        try {
            $p="$($script:AS.tbPfx.Text)".Trim(); if (-not $p -or -not (Test-Path $p)) { $script:AS.lblCert.Text='Choose a .pfx file first.'; $script:AS.lblCert.Foreground='Red'; return }
            $sec=ConvertTo-SecureString $script:AS.pbPfx.Password -AsPlainText -Force
            $imp=Import-PfxCertificate -FilePath $p -CertStoreLocation Cert:\CurrentUser\My -Password $sec -ErrorAction Stop
            $th=@($imp)[0].Thumbprint
            $have=if ($th) { Get-ChildItem "Cert:\CurrentUser\My\$th" -ErrorAction SilentlyContinue } else { $null }
            if ($have -and $have.HasPrivateKey) {
                Lz933059a102 -Name 'CertThumbprint' -Value $th
                $script:AS.lblThumb.Text=$th; $script:AS.lblCert.Text="Installed. Thumbprint $th saved."; $script:AS.lblCert.Foreground='Green'
            } else { $script:AS.lblCert.Text='Imported, but no private key found on the certificate.'; $script:AS.lblCert.Foreground='Red' }
        } catch { $script:AS.lblCert.Text="Could not install: $($_.Exception.Message)"; $script:AS.lblCert.Foreground='Red' }
    })
    $btnAuto.Add_Click({
        $script:AS.lblAuto.Text='Detecting...'; $script:AS.lblAuto.Foreground='Gray'
        try {
            $tid="$($script:AS.tbTid.Text)".Trim(); $app="$($script:AS.tbApp.Text)".Trim(); $th=[string](Get-RegSetting 'CertThumbprint')
            if (-not $tid -or -not $app -or -not $th) { $script:AS.lblAuto.Text='Enter Tenant ID and App ID, and install the certificate first.'; $script:AS.lblAuto.Foreground='Red'; return }
            $tok = Lz1c498583eb -TenantId $tid -ClientId $app -Thumbprint $th
            $rootSite = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root' -Headers @{ Authorization="Bearer $tok" }
            $sp = "$($rootSite.webUrl)".TrimEnd('/'); $script:AS.tbSp.Text=$sp
            $der = Lz12d7a4ce3d $sp
            if ($der) { $script:AS.tbOd.Text=$der.OneDriveHostUrl; $script:AS.tbTs.Text=$der.TeamSiteBaseUrl; $script:AS.tbDef.Text=$der.DefaultSiteUrl }
            $upnMsg=''
            try { $org=Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -Headers @{ Authorization="Bearer $tok" }; $u=Lzef4499bb1e $org; if ($u) { $script:AS.tbUpn.Text=$u } else { $upnMsg=' (email domain not found)' } }
            catch { $upnMsg=' (email domain needs Domain.Read.All or Organization.Read.All; enter it by hand)' }
            $script:AS.lblAuto.Text="Detected from tenant. Review the values, then Save.$upnMsg"; $script:AS.lblAuto.Foreground='Green'
        } catch { $script:AS.lblAuto.Text="Auto-detect failed: $($_.Exception.Message)"; $script:AS.lblAuto.Foreground='Red' }
    })
    $btnTest.Add_Click({
        $script:AS.lblStatus.Text='Testing...'; $script:AS.lblStatus.Foreground='Gray'
        $msgs=@()
        if ($script:TransferMode -eq 'LocalFs') { $msgs += 'Datto: skipped (not used by the Files and folders transfer type).' }
        else {
        try {
            $ep = Lz0264447111 $script:AS.cmbDom.SelectedItem $script:AS.tbCell.Text
            $secPlain = if ($script:AS.pbSec.Password) { $script:AS.pbSec.Password } else { Lzff3ae1afba }
            if (-not $ep -or -not $script:AS.tbDId.Text -or -not $secPlain) { $msgs += 'Datto: missing endpoint, ID or secret.' }
            else {
                $hdr=@{ Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($script:AS.tbDId.Text.Trim()):$secPlain")) }
                $r=Invoke-RestMethod -Uri "$($ep.TrimEnd('/'))/file/projects" -Headers $hdr -ErrorAction Stop
                $n=@($r.result).Count; $msgs += "Datto: OK ($n project(s) visible)."
            }
        } catch { $msgs += "Datto: FAILED - $($_.Exception.Message)" }
        }
        try {
            $tid="$($script:AS.tbTid.Text)".Trim(); $app="$($script:AS.tbApp.Text)".Trim(); $th=[string](Get-RegSetting 'CertThumbprint')
            if (-not $tid -or -not $app -or -not $th) { $msgs += 'Microsoft 365: enter Tenant ID and App ID and install the certificate.' }
            else { $tok=Lz1c498583eb -TenantId $tid -ClientId $app -Thumbprint $th; $s=Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root' -Headers @{ Authorization="Bearer $tok" }; $msgs += "Microsoft 365: OK ($($s.webUrl))." }
        } catch { $msgs += "Microsoft 365: FAILED - $($_.Exception.Message)" }
        $script:AS.lblStatus.Text = $msgs -join "`n"
        $script:AS.lblStatus.Foreground = if ($msgs -match 'FAILED|missing|enter') { 'Red' } else { 'Green' }
    })
    $btnSave.Add_Click({
        try {
            $ep = Lz0264447111 $script:AS.cmbDom.SelectedItem $script:AS.tbCell.Text
            Lz933059a102 -Name 'DattoEndpointUrl' -Value $ep
            Lz933059a102 -Name 'DattoClientId'    -Value ("$($script:AS.tbDId.Text)".Trim())
            Lz933059a102 -Name 'TenantId'         -Value ("$($script:AS.tbTid.Text)".Trim())
            Lz933059a102 -Name 'GraphClientId'    -Value ("$($script:AS.tbApp.Text)".Trim())
            Lz933059a102 -Name 'SharePointRootUrl'-Value ("$($script:AS.tbSp.Text)".Trim())
            Lz933059a102 -Name 'OneDriveHostUrl'  -Value ("$($script:AS.tbOd.Text)".Trim())
            Lz933059a102 -Name 'TeamSiteBaseUrl'  -Value ("$($script:AS.tbTs.Text)".Trim())
            Lz933059a102 -Name 'DefaultSiteUrl'   -Value ("$($script:AS.tbDef.Text)".Trim())
            Lz933059a102 -Name 'UpnDomain'        -Value ("$($script:AS.tbUpn.Text)".Trim())
            if ($script:AS.pbSec.Password) {
                Lz9b56e15ca5 -Value $script:AS.pbSec.Password
            }
            if ($script:JobOpen -and $script:ConfigPath) { try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch {} }
            (Show-Msg -Text ('API settings saved. New runs will use them; a run already in progress finishes on its old settings.') -Caption ('Saved')) | Out-Null
            $script:AS.win2.Close()
        } catch { (Show-Msg -Text ("Could not save: $($_.Exception.Message)")) }
    })
    $btnClear.Add_Click({
        if ((Show-Msg -Text ("Remove all API settings from this computer?`n`nThis clears the Datto and Microsoft 365 details and the Datto secret from this computer. Your migration jobs and their logs are not touched.") -Caption ('Clear settings') -Buttons ('YesNo') -Icon ('Warning')) -ne 'Yes') { return }
        try { if (Test-Path $script:RegPath) { Remove-Item -Path $script:RegPath -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
        try { [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $null, 'User') } catch {}
        try { [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $null, 'Process') } catch {}
        $removedCert = $false
        $th = "$($script:AS.lblThumb.Text)".Trim()
        if ($th -and $th -ne '(none installed)') {
            if ((Show-Msg -Text ("Also remove the sign-in certificate and its private key from this computer?`n`nThumbprint $th`n`nDo this if you are decommissioning or handing the machine back.") -Caption ('Remove certificate') -Buttons ('YesNo') -Icon ('Warning')) -eq 'Yes') {
                try { Get-ChildItem "Cert:\CurrentUser\My\$th" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue; $removedCert = $true } catch {}
            }
        }
        $script:AS.cmbDom.SelectedIndex=0; $script:AS.tbCell.Text=''; $script:AS.tbDId.Text=''; $script:AS.pbSec.Password=''; $script:AS.tbTid.Text=''; $script:AS.tbApp.Text=''
        $script:AS.lblThumb.Text='(none installed)'; $script:AS.tbPfx.Text=''; $script:AS.pbPfx.Password=''
        $script:AS.tbSp.Text=''; $script:AS.tbOd.Text=''; $script:AS.tbTs.Text=''; $script:AS.tbDef.Text=''; $script:AS.tbUpn.Text=''
        if ($script:JobOpen -and $script:ConfigPath) { try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch {} }
        $script:AS.lblStatus.Text = 'Settings and Datto secret removed from this computer.' + $(if ($removedCert) { ' Certificate removed too.' } else { '' })
        $script:AS.lblStatus.Foreground = 'Green'
    })
    $btnJobsInfo.Add_Click({
        (Show-Msg -Caption ('Clear job data') -Text (
            "Clear job data PERMANENTLY deletes the record of your migrations from this computer: the run logs, the HTML reports, the audit files and the temporary working files, for every job." + "`n`n" +
            "Why this matters. These records are your evidence that a migration ran correctly. The audit CSV lists every file with its result (copied, skipped, verified, failed) and its content hashes; the HTML report is the readable summary of each run; the provenance pack is tamper-evident, independently timestamped proof of what was migrated and when. For an audit, a compliance requirement, or a client query months later, this is often the ONLY proof the work was done. Once cleared, it cannot be recovered." + "`n`n" +
            "Back it up FIRST. Before clearing, copy anything you may need somewhere safe. The simplest and most complete way is Job > Export job, which bundles a job's settings, mappings, logs, reports and resume state into a single zip you can archive or hand to the client." + "`n`n" +
            "Where the records live: $script:JobsRoot" + "`n" +
            "Inside each job folder: the reports folder holds the HTML reports, the audit CSVs and the provenance packs; the logs folder holds the per-run logs; the temp folder is safe to discard. Copy the reports and logs folders (or the whole job folder) to keep the trail." + "`n`n" +
            "What is NOT affected: nothing already uploaded to Microsoft 365 changes, and each job's setup and resume state is kept, so you can still open and re-run a job. Only the local records are removed."
        )) | Out-Null
    })
    $btnClearJobs.Add_Click({
        if ((Show-Msg -Caption ('Clear job data') -Buttons ('YesNo') -Icon ('Warning') -Text (
            "Delete the migration RECORDS (logs, reports and audit files) for every job on this computer?" + "`n`n" +
            "This permanently removes your proof that migrations ran: the audit CSVs, the HTML reports and the provenance packs. They cannot be recovered afterwards. If you might need them for an audit, for compliance, or for a client sign-off, BACK THEM UP FIRST - Job > Export job zips a job's records for you, and the (i) beside this button explains exactly where they live and what each one tells you." + "`n`n" +
            "Uploaded data and each job's resume state are not affected."
        )) -ne 'Yes') { return }
        $jobs = 0; $files = 0
        try {
            if ($script:JobsRoot -and (Test-Path $script:JobsRoot)) {
                foreach ($jd in @(Get-ChildItem $script:JobsRoot -Directory -ErrorAction SilentlyContinue)) {
                    $jobs++
                    foreach ($sub in 'logs','reports','temp') {
                        $p = Join-Path $jd.FullName $sub
                        if (Test-Path $p) {
                            foreach ($f in @(Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue)) {
                                try { Remove-Item $f.FullName -Recurse -Force -ErrorAction SilentlyContinue; $files++ } catch {}
                            }
                        }
                    }
                }
            }
            $script:AS.lblStatus.Text = "Cleared logs, reports and temp for $jobs job(s) ($files item(s) removed)."; $script:AS.lblStatus.Foreground = 'Green'
        } catch { $script:AS.lblStatus.Text = "Could not clear job data: $($_.Exception.Message)"; $script:AS.lblStatus.Foreground = 'Red' }
    })
    [void]$win2.ShowDialog()
}
function Lz7d9c60a108 { param($Cfg,[string]$Path)
    $node=$Cfg
    foreach ($seg in ($Path -split '\.')) { if ($null -eq $node) { return $null }; if ($node.PSObject.Properties.Name -contains $seg) { $node=$node.$seg } else { return $null } }
    return $node
}
function Lzcb55b64c1a { param($Cfg,[string]$Path,$Value)
    $segs=$Path -split '\.'; $node=$Cfg
    for ($i=0;$i -lt $segs.Count-1;$i++){ $seg=$segs[$i]; if ($node.PSObject.Properties.Name -notcontains $seg){ $node|Add-Member -NotePropertyName $seg -NotePropertyValue ([pscustomobject]@{}) -Force }; $node=$node.$seg }
    $leaf=$segs[-1]
    if ($node.PSObject.Properties.Name -contains $leaf){ $node.$leaf=$Value } else { $node|Add-Member -NotePropertyName $leaf -NotePropertyValue $Value -Force }
}
$script:SettingSpecs = @(
  @{ Path='run.upload.workers';             Label='Upload workers';        Type='int';  Rec='4';  Info='How many files upload to one destination at the same time. Recommended 4 (2 to 4). Higher risks Microsoft 365 throttling (429s). On a slow line, 2 is plenty.' }
  @{ Path='run.download.threads';           Label='Download threads';      Type='int';  Rec='4';  Info='How many files download from Datto at once. Recommended 4. Downloads only need to stay ahead of uploads, so this rarely needs to be higher.' }
  @{ Path='run.parallel.maxParallelSpaces'; Label='Parallel projects';     Type='int';  Rec='1';  Info='How many projects migrate at once, each to a different destination. Recommended 1, and it is the riskiest dial. Each parallel project is a SEPARATE process with its own Datto rate limiter that cannot see the others, so several together over-saturate the shared Datto account and trip 429s, even when the M365 destinations differ. Raise it only for several projects going to genuinely different tenants, and watch the retries. Does nothing for a single project.' }
  @{ Path='run.parallel.spoolAhead';        Label='Spool ahead (buffer)';  Type='int';  Rec='8';  Info='How many downloaded files are buffered waiting to upload. Recommended 8. Keeps the upload workers fed; too low starves them, too high just uses more temp disk.' }
  @{ Path='run.upload.directPutMaxMB';      Label='Single-PUT max (MB)';   Type='int';  Rec='60'; Info='Files at or under this size upload in one request (faster); above it a resumable chunked session is used. Recommended 60. Microsoft supports a single PUT up to 250 MB; 60 is a safe balance.' }
  @{ Path='run.metadata.extensionCategory'; Label='Category by file type'; Type='text'; Rec=''; Info='Fill a Category column based on file type. Format: Category=ext,ext, several rules separated by a double semicolon. Example: Drawing=dwg,dxf;;Correspondence=msg,eml;;Spreadsheet=xlsx,xls sets Category=Drawing on a .dwg file and Category=Correspondence on a .msg file. A file whose extension is in no group gets no value. Stamping this field adds one version per file on libraries with versioning on.' }
  @{ Path='run.metadata.retentionYears'; Label='Flag old content (years, 0 = off)'; Type='text'; Rec='0'; Info='Flag files that have not been modified at the source for more than this many years, by filling a Retention column ("Review candidate: not modified since <year>"). 0 turns it off. Stamping this field adds one version per file on libraries with versioning on.' }
  @{ Path='run.metadata.filenameColumns'; Label='Filename pattern columns'; Type='text'; Rec=''; Info='Pull structured values out of file NAMES into SharePoint columns, using named-capture regular expressions. Each named group becomes a column. Separate several rules with a double semicolon. Examples: (?<DocumentDate>\d{4}-\d{2}-\d{2}) fills a DocumentDate column from a name like 2024-03-15_minutes.docx; (?<DrawingNumber>DR-\d{4})-(?<Revision>P\d+) fills DrawingNumber and Revision from DR-1001-P3.pdf; (?i)(?<Status>FINAL|DRAFT|V\d+) fills a Status column. A file that matches no rule simply gets no value; a rule that will not compile is skipped. For MSPs comfortable with regular expressions. Stamping these fields adds one version per file on libraries with versioning on.' }
  @{ Path='run.metadata.folderColumns'; Label='Folder name columns'; Type='text'; Rec=''; Info='Format: level=ColumnName, one rule per semicolon. Level counts folders from the top of the source (level 1 = the first folder under the source root). Example: 1=Client;2=Project on Contoso/Project 42/photo.jpg sets Client=Contoso and Project=Project 42. Column names: letters and numbers only, no spaces. Leave blank to turn this off. A file with fewer folder levels than a rule gets no value for that rule. Stamping these fields adds one version per file on libraries with versioning on.' }
  @{ Path='run.metadata.provenanceColumns'; Label='Stamp provenance columns'; Type='bool'; Rec='false'; Info='After each real run, writes three SharePoint columns onto every migrated file: Source path (where it came from), Source owner (from the mapping) and Migrated on. Permanently answers "where did this come from?" inside the library itself. OFF by default because writing these fields adds one version to each file on libraries with versioning enabled, and adds a short stamping pass at the end of the run. Turn it on once you are happy with that trade.' }
  @{ Path='run.upload.preserveDates';       Label='Keep original file dates'; Type='bool'; Rec='true'; Info='Files land in Microsoft 365 carrying their original last-modified date (and created date) from the source, instead of the date the migration ran. Recommended ON: this is what users and retention policies expect. Cost: nothing on larger files; small files pay one extra call each, roughly 5 to 8 percent longer on a run made mostly of small files. Turn off only if raw speed matters more than dates. If a SharePoint library refuses the date field, the tool notices once and stops sending it; files still upload fine.' }
  @{ Path='run.tuning.chunkSizeMB';         Label='Chunk size (MB)';       Type='int';  Rec='10'; Info='Chunk size for files above the single-PUT limit. Recommended 10. Larger chunks mean fewer requests but more to re-send if a chunk fails.' }
  @{ Path='run.throttle.adaptive.enabled';         Label='Auto ease-off (throttle)'; Type='bool'; Rec='true'; Info='When Microsoft 365 starts throttling (asking us to slow down), automatically reduce how many files upload at once, then speed back up when it calms down. Recommended ON. This is best practice and protects the run without you watching it. Turn off only for testing.' }
  @{ Path='run.throttle.adaptive.minWorkers';      Label='Min uploaders when throttled'; Type='int'; Rec='1'; Info='The fewest simultaneous uploads to drop to when throttled. Recommended 1 (safest, always makes progress). Raise it only if you are sure the tenant tolerates more.' }
  @{ Path='run.throttle.adaptive.growAfterSeconds';Label='Recover after (seconds)'; Type='int'; Rec='30'; Info='How long to stay calm before adding an uploader back. Recommended 30. Lower recovers faster but risks bouncing back into throttling; higher is gentler.' }
  @{ Path='run.bandwidth.maxUploadMbps';   Label='Max upload (Mb/s)';   Type='int'; Rec='0'; Info='Cap on how much upload bandwidth the migration uses, in megabits per second. 0 means no cap (use the full line). Set a value to avoid saturating the client''s internet during working hours, for example 20 on a 50 Mb/s upload line. The run just takes longer.' }
  @{ Path='run.bandwidth.maxDownloadMbps'; Label='Max download (Mb/s)'; Type='int'; Rec='0'; Info='Cap on download bandwidth from Datto, in megabits per second. 0 means no cap. Usually you only need the upload cap; set this only if pulling from Datto is also affecting the client''s connection.' }
  @{ Path='run.confirmations.preMigrationChecklist'; Label='Pre-migration checklist'; Type='bool'; Rec='true'; Info='Show a short checklist to confirm before the FIRST upload of each job: that you are authorised to migrate this data, the destination has backup/recovery, backups are tested, retention and versioning are on, and you have tested on non-production data. It appears once per job and is remembered after you agree. Untick to switch it off for this job. Recommended: on (leave it ticked).' }
  @{ Path='run.report.logo'; Label='White-label logo (file path)'; Type='text'; Rec=''; Info='Path to a PNG or JPG on this computer, shown on generated reports and the completion certificate alongside the standard Liscaragh Migrate branding. Leave blank for no extra logo. The image is embedded into the HTML at report-build time, so the finished report or certificate stays a single self-contained file, safe to hand to a client.' }
  @{ Path='run.report.client'; Label='Client name for reports'; Type='text'; Rec=''; Info='Shown on generated reports and the completion certificate as the client this job was carried out for, for example "Contoso Ltd". Leave blank to omit it.' }
)
function Lz17569d9944 {
    if (-not $script:ConfigPath) { (Show-Msg -Text ('Open or create a job first, then set its filters.') -Caption ('No job open') -Icon ('Warning')) | Out-Null; return }
    try { $cfg = Read-ConfigJson $script:ConfigPath } catch { (Show-Msg -Text ("Could not read this job's settings file.`n`nIt may be open in another program, or damaged.`n`nTechnical detail: $($_.Exception.Message)")); return }
    $win = New-Object System.Windows.Window
    Lz2e8ddc8b18 $win
    $win.Title='Filters (this job)'; $win.SizeToContent='WidthAndHeight'; $win.WindowStartupLocation='CenterScreen'; $win.ResizeMode='NoResize'
    $win.FontFamily='Segoe UI'; $win.FontSize=13; $win.Background='White'
    $dockF = New-Object System.Windows.Controls.DockPanel
    $hdrF = New-Object System.Windows.Controls.Border; $hdrF.Background='#0F1115'; $hdrF.Padding='20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdrF,'Top')
    $hsF = New-Object System.Windows.Controls.StackPanel; $hsF.MaxWidth=520
    $htF = New-Object System.Windows.Controls.TextBlock; $htF.Text='Filters (this job)'; $htF.Foreground='White'; $htF.FontSize=16; $htF.FontWeight='SemiBold'
    $hbF = New-Object System.Windows.Controls.TextBlock
    $hbF.Text='These filters decide which files this job copies. They apply to EVERY project in this job, not just the selected one. Leave a box blank, or size at 0, for no limit. They take effect on the next run.'
    $hbF.Foreground='#9BA1AA'; $hbF.TextWrapping='Wrap'; $hbF.Margin='0,4,0,0'
    [void]$hsF.Children.Add($htF); [void]$hsF.Children.Add($hbF); $hdrF.Child=$hsF
    [void]$dockF.Children.Add($hdrF)
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin='18,14,18,16'; $root.Width=540
    $h1=New-Object System.Windows.Controls.TextBlock; $h1.Text='File size'; $h1.FontWeight='Bold'; $h1.Margin='0,2,0,4'; [void]$root.Children.Add($h1)
    $sizeRow=New-Object System.Windows.Controls.StackPanel; $sizeRow.Orientation='Horizontal'; $sizeRow.Margin='0,0,0,12'
    $sizeLbl=New-Object System.Windows.Controls.TextBlock; $sizeLbl.Text='Skip files larger than (MB), 0 = no limit:'; $sizeLbl.VerticalAlignment='Center'; $sizeLbl.Margin='0,0,8,0'
    $sizeBox=New-Object System.Windows.Controls.TextBox; $sizeBox.Width=90
    $curMax=Lz7d9c60a108 -Cfg $cfg -Path 'run.tuning.maxFileSizeMB'; if ($null -eq $curMax) { $curMax=0 }; $sizeBox.Text="$curMax"
    [void]$sizeRow.Children.Add($sizeLbl); [void]$sizeRow.Children.Add($sizeBox); [void]$root.Children.Add($sizeRow)
    $h2=New-Object System.Windows.Controls.TextBlock; $h2.Text='File types'; $h2.FontWeight='Bold'; $h2.Margin='0,2,0,4'; [void]$root.Children.Add($h2)
    $rbOmit=New-Object System.Windows.Controls.RadioButton; $rbOmit.GroupName='ftype'; $rbOmit.Content='Skip these file types (copy everything else)'; $rbOmit.Margin='0,0,0,2'
    $rbInc =New-Object System.Windows.Controls.RadioButton; $rbInc.GroupName='ftype';  $rbInc.Content='Copy ONLY these file types (skip everything else)'; $rbInc.Margin='0,0,0,4'
    [void]$root.Children.Add($rbOmit); [void]$root.Children.Add($rbInc)
    $patBox=New-Object System.Windows.Controls.TextBox; $patBox.Margin='0,0,0,2'
    $curInc=@(Lz7d9c60a108 -Cfg $cfg -Path 'run.tuning.includePatterns' | Where-Object { "$_".Trim() })
    $curExc=@(Lz7d9c60a108 -Cfg $cfg -Path 'run.tuning.excludePatterns' | Where-Object { "$_".Trim() })
    $junkOn = $true
    foreach ($jp in $script:JunkPatterns) { if ($curExc -notcontains $jp) { $junkOn = $false; break } }
    $excShown = if ($junkOn) { @($curExc | Where-Object { $script:JunkPatterns -notcontains $_ }) } else { $curExc }
    if ($curInc.Count) { $rbInc.IsChecked=$true; $patBox.Text=($curInc -join '; ') }
    else { $rbOmit.IsChecked=$true; $patBox.Text=($excShown -join '; ') }
    [void]$root.Children.Add($patBox)
    $patHint=New-Object System.Windows.Controls.TextBlock
    $patHint.Text='Wildcards, separated by semicolons or commas. For example ~$*, *.tmp, thumbs.db to skip Office lock files and OS junk, or *.pdf, *.docx to copy only those types. Matches the file name only, not the folder.'
    $patHint.TextWrapping='Wrap'; $patHint.Foreground='Gray'; $patHint.FontSize=11.5; $patHint.Margin='0,0,0,6'
    [void]$root.Children.Add($patHint)
    $junkChk=New-Object System.Windows.Controls.CheckBox
    $junkChk.Content='Skip common junk files (Thumbs.db, desktop.ini, .DS_Store, ~$ Office lock files, *.tmp)'
    $junkChk.IsChecked=$junkOn; $junkChk.Margin='0,0,0,12'; $junkChk.FontSize=12.5
    $junkChk.ToolTip='OS and application litter that has no business in SharePoint. Skipped files are counted in the run summary, never silently lost. Works alongside your own patterns above, in either mode.'
    [void]$root.Children.Add($junkChk)
    $h3=New-Object System.Windows.Controls.TextBlock; $h3.Text='File modified date'; $h3.FontWeight='Bold'; $h3.Margin='0,2,0,4'; [void]$root.Children.Add($h3)
    $dg=New-Object System.Windows.Controls.Grid; $dg.Margin='0,0,0,2'
    $c0=New-Object System.Windows.Controls.ColumnDefinition; $c0.Width='230'
    $c1=New-Object System.Windows.Controls.ColumnDefinition; $c1.Width='150'
    $dg.ColumnDefinitions.Add($c0); $dg.ColumnDefinitions.Add($c1)
    $r0=New-Object System.Windows.Controls.RowDefinition; $r0.Height='Auto'; $dg.RowDefinitions.Add($r0)
    $r1=New-Object System.Windows.Controls.RowDefinition; $r1.Height='Auto'; $dg.RowDefinitions.Add($r1)
    $toDate = { param($s) $s="$s".Trim(); if (-not $s) { return $null }; try { return ([datetime]::Parse($s,[System.Globalization.CultureInfo]::InvariantCulture)).Date } catch { return $null } }
    $laLbl=New-Object System.Windows.Controls.TextBlock; $laLbl.Text='Include if modified on or after:'; $laLbl.VerticalAlignment='Center'; $laLbl.Margin='0,4,8,4'
    [System.Windows.Controls.Grid]::SetRow($laLbl,0); [System.Windows.Controls.Grid]::SetColumn($laLbl,0); [void]$dg.Children.Add($laLbl)
    $afterPick=New-Object System.Windows.Controls.DatePicker; $afterPick.Margin='0,4,0,4'; $afterPick.Width=150; $afterPick.SelectedDate=(& $toDate (Lz7d9c60a108 -Cfg $cfg -Path 'run.tuning.modifiedAfter'))
    [System.Windows.Controls.Grid]::SetRow($afterPick,0); [System.Windows.Controls.Grid]::SetColumn($afterPick,1); [void]$dg.Children.Add($afterPick)
    $lbLbl=New-Object System.Windows.Controls.TextBlock; $lbLbl.Text='Include if modified before (exclusive):'; $lbLbl.VerticalAlignment='Center'; $lbLbl.Margin='0,4,8,4'
    [System.Windows.Controls.Grid]::SetRow($lbLbl,1); [System.Windows.Controls.Grid]::SetColumn($lbLbl,0); [void]$dg.Children.Add($lbLbl)
    $beforePick=New-Object System.Windows.Controls.DatePicker; $beforePick.Margin='0,4,0,4'; $beforePick.Width=150; $beforePick.SelectedDate=(& $toDate (Lz7d9c60a108 -Cfg $cfg -Path 'run.tuning.modifiedBefore'))
    [System.Windows.Controls.Grid]::SetRow($beforePick,1); [System.Windows.Controls.Grid]::SetColumn($beforePick,1); [void]$dg.Children.Add($beforePick)
    [void]$root.Children.Add($dg)
    $dateHint=New-Object System.Windows.Controls.TextBlock
    $dateHint.Text='Pick a date from the calendar, or leave blank for no bound. Read as UTC midnight, so the boundary does not shift with the time zone of the computer running the migration.'
    $dateHint.TextWrapping='Wrap'; $dateHint.Foreground='Gray'; $dateHint.FontSize=11.5; $dateHint.Margin='0,0,0,14'
    [void]$root.Children.Add($dateHint)
    $btnRow=New-Object System.Windows.Controls.DockPanel; $btnRow.LastChildFill=$false; $btnRow.Margin='0,2,0,0'
    $clear=New-Object System.Windows.Controls.Button; $clear.Content='Clear all filters'; $clear.Padding='14,4'
    $clear.ToolTip='Reset every filter (size, file types and dates) to off. Click Save to apply, or Cancel to keep what you had.'
    [System.Windows.Controls.DockPanel]::SetDock($clear,'Left'); [void]$btnRow.Children.Add($clear)
    $rightWrap=New-Object System.Windows.Controls.StackPanel; $rightWrap.Orientation='Horizontal'; [System.Windows.Controls.DockPanel]::SetDock($rightWrap,'Right')
    $save=New-Object System.Windows.Controls.Button; $save.Content='Save'; $save.Padding='16,4'; $save.Margin='0,0,8,0'; $save.IsDefault=$true
    $cancel=New-Object System.Windows.Controls.Button; $cancel.Content='Cancel'; $cancel.Padding='16,4'; $cancel.IsCancel=$true
    [void]$rightWrap.Children.Add($save); [void]$rightWrap.Children.Add($cancel); [void]$btnRow.Children.Add($rightWrap)
    [void]$root.Children.Add($btnRow)
    [void]$dockF.Children.Add($root); $win.Content=$dockF
    $script:FltCfg=$cfg; $script:FltWin=$win
    $script:FltSize=$sizeBox; $script:FltPat=$patBox; $script:FltInc=$rbInc; $script:FltExc=$rbOmit; $script:FltAfter=$afterPick; $script:FltBefore=$beforePick; $script:FltJunk=$junkChk
    $clear.Add_Click({
        $script:FltSize.Text='0'
        $script:FltPat.Text=''
        if ($script:FltExc) { $script:FltExc.IsChecked=$true }
        $script:FltAfter.SelectedDate=$null
        $script:FltBefore.SelectedDate=$null
    })
    $save.Add_Click({
        try {
            $sv=0; [void][int]::TryParse("$($script:FltSize.Text)".Trim(),[ref]$sv); if ($sv -lt 0) { $sv=0 }
            Lzcb55b64c1a -Cfg $script:FltCfg -Path 'run.tuning.maxFileSizeMB' -Value $sv
            $pats=@("$($script:FltPat.Text)" -split '[;,\r\n]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $junk = @(); if ($script:FltJunk -and $script:FltJunk.IsChecked) { $junk = @($script:JunkPatterns) }
            if ($script:FltInc.IsChecked) { Lzcb55b64c1a -Cfg $script:FltCfg -Path 'run.tuning.includePatterns' -Value $pats; Lzcb55b64c1a -Cfg $script:FltCfg -Path 'run.tuning.excludePatterns' -Value $junk }
            else                          { Lzcb55b64c1a -Cfg $script:FltCfg -Path 'run.tuning.excludePatterns' -Value @(@($pats | Where-Object { $script:JunkPatterns -notcontains $_ }) + $junk); Lzcb55b64c1a -Cfg $script:FltCfg -Path 'run.tuning.includePatterns' -Value @() }
            $ma=''; if ($null -ne $script:FltAfter.SelectedDate)  { $ma=([datetime]$script:FltAfter.SelectedDate).ToString('yyyy-MM-dd') }
            $mb=''; if ($null -ne $script:FltBefore.SelectedDate) { $mb=([datetime]$script:FltBefore.SelectedDate).ToString('yyyy-MM-dd') }
            if ($null -ne $script:FltAfter.SelectedDate -and $null -ne $script:FltBefore.SelectedDate -and ([datetime]$script:FltAfter.SelectedDate) -ge ([datetime]$script:FltBefore.SelectedDate)) {
                (Show-Msg -Text ("'Modified on or after' ($ma) must be earlier than 'Modified before' ($mb), or nothing would match. Widen the window, or clear one of them.") -Caption ('Check the dates') -Icon ('Warning')) | Out-Null; return
            }
            Lzcb55b64c1a -Cfg $script:FltCfg -Path 'run.tuning.modifiedAfter'  -Value $ma
            Lzcb55b64c1a -Cfg $script:FltCfg -Path 'run.tuning.modifiedBefore' -Value $mb
            Write-ConfigJson -Cfg $script:FltCfg -Path $script:ConfigPath
            try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch { $script:Cfg = $script:FltCfg }
            (Show-Msg -Text ("Filters saved. They apply to every $($script:NItem) in this job, on the next run.") -Caption ('Saved')) | Out-Null
            $script:FltWin.Close()
        } catch { (Show-Msg -Text ("Could not save the filters.`n`nThe settings file may be open elsewhere, or read-only. Your existing filters are unchanged.`n`nTechnical detail: $($_.Exception.Message)")) }
    })
    [void]$win.ShowDialog()
}
function Lz8af301bb21 {
    try { $cfg = Read-ConfigJson $script:ConfigPath } catch { (Show-Msg -Text ("Could not read this job's settings file.`n`nIt may be open in another program, or damaged. Try closing and reopening the job.`n`nTechnical detail: $($_.Exception.Message)")); return }
    $win2 = New-Object System.Windows.Window
    Lz2e8ddc8b18 $win2
    $win2.Title='Settings and tuning'; $win2.SizeToContent='WidthAndHeight'; $win2.WindowStartupLocation='CenterScreen'; $win2.ResizeMode='NoResize'
    $win2.FontFamily='Segoe UI'; $win2.FontSize=13; $win2.Background='White'
    try { $win2.MaxHeight = [Math]::Max(400, [System.Windows.SystemParameters]::WorkArea.Height - 40) } catch {}
    $dockS = New-Object System.Windows.Controls.DockPanel
    $hdrS = New-Object System.Windows.Controls.Border; $hdrS.Background='#0F1115'; $hdrS.Padding='20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdrS,'Top')
    $hsS = New-Object System.Windows.Controls.StackPanel; $hsS.MaxWidth=560
    $htS = New-Object System.Windows.Controls.TextBlock; $htS.Text='Settings and tuning'; $htS.Foreground='White'; $htS.FontSize=16; $htS.FontWeight='SemiBold'
    $hbS = New-Object System.Windows.Controls.TextBlock
    $hbS.Text='You do not need to change anything here. The defaults are already tuned and work well for most jobs. Click the i on any row to see what it does and the recommended value. Changes apply on the next run (speed limits apply immediately).'
    $hbS.Foreground='#9BA1AA'; $hbS.TextWrapping='Wrap'; $hbS.Margin='0,4,0,0'
    [void]$hsS.Children.Add($htS); [void]$hsS.Children.Add($hbS); $hdrS.Child=$hsS
    [void]$dockS.Children.Add($hdrS)
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin='18,14,18,16'
    function New-SettingRow { param($Grid,[int]$Row,[string]$Label,[string]$Value,[string]$Info,[string]$Rec,[string]$Type='text')
        $rd=New-Object System.Windows.Controls.RowDefinition; $rd.Height='Auto'; $Grid.RowDefinitions.Add($rd)
        $lbl=New-Object System.Windows.Controls.TextBlock; $lbl.Text=$Label; $lbl.VerticalAlignment='Center'; $lbl.Margin='0,4,8,4'; $lbl.TextWrapping='Wrap'
        [System.Windows.Controls.Grid]::SetRow($lbl,$Row); [System.Windows.Controls.Grid]::SetColumn($lbl,0); [void]$Grid.Children.Add($lbl)
        if ($Type -eq 'bool') {
            $ctl=New-Object System.Windows.Controls.CheckBox; $ctl.VerticalAlignment='Center'; $ctl.Margin='0,4,0,4'
            $ctl.IsChecked=("$Value" -match '^(1|true|yes|on)$')
        } else {
            $ctl=New-Object System.Windows.Controls.TextBox; $ctl.Margin='0,4,0,4'; $ctl.Text="$Value"
        }
        [System.Windows.Controls.Grid]::SetRow($ctl,$Row); [System.Windows.Controls.Grid]::SetColumn($ctl,1); [void]$Grid.Children.Add($ctl)
        $ib=New-Object System.Windows.Controls.Button; $ib.Content=([char]0xE946); $ib.FontFamily='Segoe MDL2 Assets'; $ib.Padding='0,4'; $ib.Width=26; $ib.Margin='6,4,0,4'; $ib.ToolTip=$Info; $ib.FocusVisualStyle=$null
        $info=$Info; $labelText=$Label; $rec=$Rec
        $ib.Add_Click({ $m = if ($rec) { $info + "`n`nRecommended: " + $rec } else { $info }; (Show-Msg -Text ($m) -Caption ($labelText)) }.GetNewClosure())
        [System.Windows.Controls.Grid]::SetRow($ib,$Row); [System.Windows.Controls.Grid]::SetColumn($ib,2); [void]$Grid.Children.Add($ib)
        return $ctl
    }
    $note = New-Object System.Windows.Controls.TextBlock
    $note.Text='Connection details (Datto and Microsoft 365) are under the separate "API settings" button.'
    $note.TextWrapping='Wrap'; $note.Width=560; $note.Margin='0,0,0,12'; $note.Foreground='#98A2B3'; $note.FontSize=11.5
    [void]$root.Children.Add($note)
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in '190','320','40') { $cd=New-Object System.Windows.Controls.ColumnDefinition; $cd.Width=$w; $grid.ColumnDefinitions.Add($cd) }
    $script:SetBoxes = @{}
    $r = 0
    foreach ($s in $script:SettingSpecs) {
        $val = Lz7d9c60a108 -Cfg $cfg -Path $s.Path
        $disp = if ($s.Type -eq 'list') { (@($val) -join ';') } else { "$val" }
        $script:SetBoxes[$s.Path] = New-SettingRow -Grid $grid -Row $r -Label $s.Label -Value $disp -Info $s.Info -Rec $s.Rec -Type $s.Type
        $r++
    }
    [void]$root.Children.Add($grid)
    $resetRow = New-Object System.Windows.Controls.DockPanel
    $resetRow.LastChildFill = $true; $resetRow.Margin = '0,14,0,0'
    $reset = New-Object System.Windows.Controls.Button
    $reset.Content = 'Reset to defaults'; $reset.Padding = '14,4'
    $reset.ToolTip = 'Put the recommended value back in every box above. Nothing is saved until you click Save, so Cancel still undoes it.'
    [System.Windows.Controls.DockPanel]::SetDock($reset, 'Left')
    $reset.Add_Click({
        foreach ($s in $script:SettingSpecs) {
            $box = $script:SetBoxes[$s.Path]
            if ($box) { if ($s.Type -eq 'bool') { $box.IsChecked = ("$($s.Rec)" -match '^(1|true|yes|on)$') } else { $box.Text = "$($s.Rec)" } }
        }
        if ($script:SetResetNote) { $script:SetResetNote.Visibility = 'Visible' }
    })
    [void]$resetRow.Children.Add($reset)
    $resetNote = New-Object System.Windows.Controls.TextBlock
    $resetNote.Text = 'Recommended values restored. Click Save to keep them, or Cancel to leave your settings as they were.'
    $resetNote.TextWrapping = 'Wrap'; $resetNote.Foreground = '#B5460F'; $resetNote.FontSize = 12
    $resetNote.VerticalAlignment = 'Center'; $resetNote.Margin = '12,0,0,0'; $resetNote.Visibility = 'Collapsed'
    [void]$resetRow.Children.Add($resetNote)
    $script:SetResetNote = $resetNote
    [void]$root.Children.Add($resetRow)
    $footS = New-Object System.Windows.Controls.Border
    $footS.Background='#F7F8FA'; $footS.BorderBrush='#E4E7EC'; $footS.BorderThickness='0,1,0,0'; $footS.Padding='18,12'
    [System.Windows.Controls.DockPanel]::SetDock($footS,'Bottom')
    $btnRow=New-Object System.Windows.Controls.StackPanel; $btnRow.Orientation='Horizontal'; $btnRow.HorizontalAlignment='Right'
    $save=New-Object System.Windows.Controls.Button; $save.Content='Save'; $save.Padding='16,4'; $save.Margin='0,0,8,0'; $save.IsDefault=$true
    $cancel=New-Object System.Windows.Controls.Button; $cancel.Content='Cancel'; $cancel.Padding='16,4'; $cancel.IsCancel=$true
    [void]$btnRow.Children.Add($save); [void]$btnRow.Children.Add($cancel); $footS.Child=$btnRow
    [void]$dockS.Children.Add($footS)
    $scrollS = New-Object System.Windows.Controls.ScrollViewer
    $scrollS.VerticalScrollBarVisibility='Auto'; $scrollS.HorizontalScrollBarVisibility='Disabled'
    $scrollS.Content=$root
    [void]$dockS.Children.Add($scrollS); $win2.Content=$dockS
    $script:SetCfg=$cfg; $script:SetWin=$win2
    $save.Add_Click({
        try {
            foreach ($s in $script:SettingSpecs) {
                $raw="$($script:SetBoxes[$s.Path].Text)".Trim()
                if ($s.Type -eq 'int') { $v=0; [void][int]::TryParse($raw,[ref]$v); Lzcb55b64c1a -Cfg $script:SetCfg -Path $s.Path -Value $v }
                elseif ($s.Type -eq 'list') { $arr=@($raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); Lzcb55b64c1a -Cfg $script:SetCfg -Path $s.Path -Value $arr }
                elseif ($s.Type -eq 'bool') { Lzcb55b64c1a -Cfg $script:SetCfg -Path $s.Path -Value ([bool]$script:SetBoxes[$s.Path].IsChecked) }
                elseif ($s.Type -eq 'date') {
                    if ($raw) {
                        $okDate = $false
                        try { [void][datetimeoffset]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal); $okDate = $true } catch {}
                        if (-not $okDate) { (Show-Msg -Text ("'$($s.Label)' must be a date like 2026-06-25 (year-month-day), or left blank. You typed: '$raw'.") -Caption ('Check the date') -Icon ('Warning')) | Out-Null; return }
                    }
                    Lzcb55b64c1a -Cfg $script:SetCfg -Path $s.Path -Value $raw
                }
                else { Lzcb55b64c1a -Cfg $script:SetCfg -Path $s.Path -Value $raw }
            }
            Write-ConfigJson -Cfg $script:SetCfg -Path $script:ConfigPath
            try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch { $script:Cfg = $script:SetCfg }
            try {
                $cu=0; $cd=0
                if ($script:SetCfg.run.PSObject.Properties.Name -contains 'bandwidth') {
                    $b=$script:SetCfg.run.bandwidth
                    if ($b.PSObject.Properties.Name -contains 'maxUploadMbps')   { $cu=[int]$b.maxUploadMbps }
                    if ($b.PSObject.Properties.Name -contains 'maxDownloadMbps') { $cd=[int]$b.maxDownloadMbps }
                }
                $ctrl.TxtCapUp.Text="$cu"; $ctrl.TxtCapDown.Text="$cd"
                $sr=$script:SetCfg.run.stateRoot
                if ($sr) { if (-not (Test-Path $sr)) { New-Item -ItemType Directory -Path $sr -Force | Out-Null }; @{ maxUploadMbps=$cu; maxDownloadMbps=$cd } | ConvertTo-Json | Set-Content -Path (Join-Path $sr 'bandwidth.control.json') -Encoding UTF8 }
            } catch {}
            (Show-Msg -Text ('Settings saved. Speed limits apply immediately (including to a running job); other settings apply on the next run.') -Caption ('Saved')) | Out-Null
            $script:SetWin.Close()
        } catch { (Show-Msg -Text ("Could not save these settings.`n`nThe settings file may be open elsewhere, or read-only. Your existing settings are unchanged.`n`nTechnical detail: $($_.Exception.Message)")) }
    })
    [void]$win2.ShowDialog()
}
$script:NetLast = $null
$script:NetHist = New-Object System.Collections.Generic.List[double]
function Lz3d05c7a708 {
    try {
        $now = [DateTime]::UtcNow
        $cur = @{}
        foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            $t = $ni.NetworkInterfaceType
            if ($ni.OperationalStatus -eq 'Up' -and $t -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and $t -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel) {
                try { $st = $ni.GetIPStatistics(); $cur[$ni.Id] = @{ Sent = [int64]$st.BytesSent; Recv = [int64]$st.BytesReceived } } catch {}
            }
        }
        if ($script:NetLast) {
            $dt = ($now - $script:NetLast.Time).TotalSeconds
            if ($dt -gt 0.2) {
                $up = 0.0; $dn = 0.0; $best = -1
                foreach ($id in $cur.Keys) {
                    if ($script:NetLast.Ifaces.ContainsKey($id)) {
                        $ds = $cur[$id].Sent - $script:NetLast.Ifaces[$id].Sent; if ($ds -lt 0) { $ds = 0 }
                        $dr = $cur[$id].Recv - $script:NetLast.Ifaces[$id].Recv; if ($dr -lt 0) { $dr = 0 }
                        if (($ds + $dr) -gt $best) { $best = $ds + $dr; $up = ($ds * 8 / 1e6) / $dt; $dn = ($dr * 8 / 1e6) / $dt }
                    }
                }
                $up = [math]::Round($up, 1); $dn = [math]::Round($dn, 1)
                $ctrl.LblNet.Text = "Network card - All app activity   Down $dn Mb/s   Up $up Mb/s"
                $script:NetHist.Add($up); while ($script:NetHist.Count -gt 40) { $script:NetHist.RemoveAt(0) }
                $max = ($script:NetHist | Measure-Object -Maximum).Maximum; if ($max -le 0) { $max = 1 }
                $h = $ctrl.NetCanvas.ActualHeight; if ($h -le 0) { $h = 20 }
                $w = $ctrl.NetCanvas.ActualWidth;  if ($w -le 0) { $w = 118 }
                $n = $script:NetHist.Count
                $pts = New-Object System.Windows.Media.PointCollection
                for ($i = 0; $i -lt $n; $i++) { $x = ($w * $i) / [math]::Max($n - 1, 1); $y = $h - (($script:NetHist[$i] / $max) * ($h - 2)) - 1; $pts.Add((New-Object System.Windows.Point($x, $y))) }
                $ctrl.NetLine.Points = $pts
                $script:NetLast = @{ Time = $now; Ifaces = $cur }
            }
        } else { $script:NetLast = @{ Time = $now; Ifaces = $cur } }
    } catch {}
}
$script:NetTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:NetTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$script:NetTimer.Add_Tick({ Lz3d05c7a708 })
$script:NetTimer.Start()
$startMode = 'Datto'
try {
    $liveIds = @($script:TransferTypes | Where-Object Status -eq 'Live' | ForEach-Object Id)
    $remembered = [string](Get-RegSetting 'TransferMode')
    $rememberOn = (([string](Get-RegSetting 'TransferModeRemember')) -ne '0')
    $shiftHeld = $false
    try { $shiftHeld = [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift) } catch {}
    if ($rememberOn -and $remembered -and ($liveIds -contains $remembered) -and -not $shiftHeld) {
        $startMode = $remembered
    } else {
        if ($script:Splash) { try { $script:Splash.Close(); $script:Splash = $null } catch {} }
        $pick = Lzad6bdd19f4
        if ($pick) { $startMode = $pick }
        elseif ($remembered -and ($liveIds -contains $remembered)) {
            $startMode = $remembered
        } else {
            exit 0
        }
    }
} catch {}
Lzaf2eff9079 $startMode
Lz56e0fac1fe
$startJobJson = Join-Path (Split-Path $script:ConfigPath) 'job.json'
if ((Test-Path $startJobJson) -and ((Get-JobSourceType $script:ConfigPath) -eq $script:TransferMode)) {
    Set-CurrentJob -ConfigFile $script:ConfigPath
} else {
    Set-JobChip -Name ''
    $ctrl.BtnConnect.IsEnabled = $false; Lzdd341be2a9 $false
    Lz35d0f8dce4 $false
    Lzc219beec58
}
Set-DestModeUI
function Lz45a93a6e9e {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $win2 = New-Object System.Windows.Window
    Lz2e8ddc8b18 $win2
    $win2.Title = 'Datto Workplace credentials'; $win2.SizeToContent = 'Height'; $win2.Width = 520
    $win2.WindowStartupLocation = 'CenterScreen'; $win2.ResizeMode = 'NoResize'
    try {
        if ($script:SC -and $script:SC.Win -and $script:SC.Win.IsVisible) { $win2.Owner = $script:SC.Win; $win2.WindowStartupLocation = 'CenterOwner' }
        elseif ($win -and $win.IsVisible) { $win2.Owner = $win; $win2.WindowStartupLocation = 'CenterOwner' }
    } catch {}
    $win2.FontFamily = 'Segoe UI'; $win2.FontSize = 13; $win2.Background = 'White'
    $dock3 = New-Object System.Windows.Controls.DockPanel; $win2.Content = $dock3
    $hdr3 = New-Object System.Windows.Controls.Border; $hdr3.Background = '#0F1115'; $hdr3.Padding = '20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdr3, 'Top')
    $hs3 = New-Object System.Windows.Controls.StackPanel
    $ht3 = New-Object System.Windows.Controls.TextBlock; $ht3.Text = 'Datto Workplace credentials'; $ht3.Foreground = 'White'; $ht3.FontSize = 16; $ht3.FontWeight = 'SemiBold'
    $hb3 = New-Object System.Windows.Controls.TextBlock
    $hb3.Text = 'From the Datto Workplace admin portal: create an API integration, then copy its Client ID and Secret here. Saved on this computer only.'
    $hb3.Foreground = '#9BA1AA'; $hb3.TextWrapping = 'Wrap'; $hb3.Margin = '0,4,0,0'
    [void]$hs3.Children.Add($ht3); [void]$hs3.Children.Add($hb3); $hdr3.Child = $hs3
    [void]$dock3.Children.Add($hdr3)
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '18,14,18,16'
    [void]$dock3.Children.Add($root)
    function Lz5cb525ce4d { param($Label, $Control, $Info)
        $g = New-Object System.Windows.Controls.Grid
        foreach ($w in '130','*','Auto') { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = if ($w -eq '130') { '130' } else { $w }; $g.ColumnDefinitions.Add($c) }
        $l = New-Object System.Windows.Controls.TextBlock; $l.Text = $Label; $l.VerticalAlignment = 'Center'; $l.Margin = '0,3,8,3'
        [System.Windows.Controls.Grid]::SetColumn($l, 0); [void]$g.Children.Add($l)
        [System.Windows.Controls.Grid]::SetColumn($Control, 1); [void]$g.Children.Add($Control)
        if ($Info) {
            $ib = New-Object System.Windows.Controls.Button
            $ib.Content = ([char]0xE946); $ib.FontFamily = 'Segoe MDL2 Assets'; $ib.FontSize = 14
            $ib.Width = 30; $ib.Padding = '0,4'; $ib.Margin = '6,3,0,3'; $ib.VerticalAlignment = 'Center'; $ib.ToolTip = $Info; $ib.FocusVisualStyle = $null
            $iTxt = $Info; $iLab = $Label
            $ib.Add_Click({ (Show-Msg -Text ($iTxt) -Caption ($iLab)) | Out-Null }.GetNewClosure())
            [System.Windows.Controls.Grid]::SetColumn($ib, 2); [void]$g.Children.Add($ib)
        }
        [void]$root.Children.Add($g); return $Control
    }
    $cmbDom = New-Object System.Windows.Controls.ComboBox; $cmbDom.Margin = '0,3,0,3'
    foreach ($d in $script:DattoDomains) { [void]$cmbDom.Items.Add($d) }
    $parts = Lz33cfd41074 ([string](Get-RegSetting 'DattoEndpointUrl'))
    if ($parts.Domain) { $cmbDom.SelectedItem = $parts.Domain } else { $cmbDom.SelectedIndex = 0 }
    [void](Lz5cb525ce4d -Label 'Region (domain)' -Control $cmbDom -Info 'Your Datto Workplace region. If the web address you use for Datto starts with "eu", pick the eu one; "us", pick us, and so on.')
    $tbCell = New-Object System.Windows.Controls.TextBox; $tbCell.Margin = '0,3,0,3'; $tbCell.Text = "$($parts.Cell)"
    [void](Lz5cb525ce4d -Label 'Cell (number)' -Control $tbCell -Info 'A small number that is part of your Datto web address (for example the 2 in .../2/api/v1). It is shown on the Datto API integration page.')
    $tbDId = New-Object System.Windows.Controls.TextBox; $tbDId.Margin = '0,3,0,3'; $tbDId.Text = [string](Get-RegSetting 'DattoClientId')
    [void](Lz5cb525ce4d -Label 'Client ID' -Control $tbDId -Info 'The username for the Datto connection, from the API integration you created in the Datto Workplace admin portal.')
    $pbSec = New-Object System.Windows.Controls.PasswordBox; $pbSec.Margin = '0,3,0,3'
    [void](Lz5cb525ce4d -Label 'Secret' -Control $pbSec -Info 'The password that goes with the Client ID, from the same API integration. Treat it like a password. Leave blank to keep the one already saved.')
    $secNote = New-Object System.Windows.Controls.TextBlock; $secNote.Text = 'Leave the secret blank to keep the current one.'; $secNote.Foreground = 'Gray'; $secNote.FontSize = 11; $secNote.Margin = '130,0,0,0'; [void]$root.Children.Add($secNote)
    $btnRow = New-Object System.Windows.Controls.StackPanel; $btnRow.Orientation = 'Horizontal'; $btnRow.HorizontalAlignment = 'Right'; $btnRow.Margin = '0,14,0,0'
    $btnTest = New-Object System.Windows.Controls.Button; $btnTest.Content = 'Test'; $btnTest.Padding = '12,4'; $btnTest.Margin = '0,0,8,0'
    $btnSave = New-Object System.Windows.Controls.Button; $btnSave.Content = 'Save'; $btnSave.Padding = '16,4'; $btnSave.Margin = '0,0,8,0'; $btnSave.IsDefault = $true
    $btnClose = New-Object System.Windows.Controls.Button; $btnClose.Content = 'Close'; $btnClose.Padding = '16,4'; $btnClose.IsCancel = $true
    [void]$btnRow.Children.Add($btnTest); [void]$btnRow.Children.Add($btnSave); [void]$btnRow.Children.Add($btnClose)
    [void]$root.Children.Add($btnRow)
    $lblStatus = New-Object System.Windows.Controls.TextBlock; $lblStatus.TextWrapping = 'Wrap'; $lblStatus.Margin = '0,8,0,0'; [void]$root.Children.Add($lblStatus)
    $script:DS = @{ win2 = $win2; cmbDom = $cmbDom; tbCell = $tbCell; tbDId = $tbDId; pbSec = $pbSec; lblStatus = $lblStatus }
    $btnTest.Add_Click({
        $script:DS.lblStatus.Text = 'Testing...'; $script:DS.lblStatus.Foreground = 'Gray'
        try {
            $ep = Lz0264447111 $script:DS.cmbDom.SelectedItem $script:DS.tbCell.Text
            $secPlain = if ($script:DS.pbSec.Password) { $script:DS.pbSec.Password } else { Lzff3ae1afba }
            if (-not $ep -or -not "$($script:DS.tbDId.Text)".Trim() -or -not $secPlain) { $script:DS.lblStatus.Text = 'Enter the region, cell, Client ID and Secret first.'; $script:DS.lblStatus.Foreground = 'Red'; return }
            $hdr = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$("$($script:DS.tbDId.Text)".Trim()):$secPlain")) }
            $r = Invoke-RestMethod -Uri "$($ep.TrimEnd('/'))/file/projects" -Headers $hdr -TimeoutSec 60 -ErrorAction Stop
            $n = @($r.result).Count
            $script:DS.lblStatus.Text = "Datto: OK ($n project(s) visible). Click Save to keep these details."; $script:DS.lblStatus.Foreground = 'Green'
        } catch { $script:DS.lblStatus.Text = "Datto: FAILED - $($_.Exception.Message)"; $script:DS.lblStatus.Foreground = 'Red' }
    })
    $btnSave.Add_Click({
        try {
            $ep = Lz0264447111 $script:DS.cmbDom.SelectedItem $script:DS.tbCell.Text
            if (-not $ep -or -not "$($script:DS.tbDId.Text)".Trim()) { $script:DS.lblStatus.Text = 'Enter the region, cell and Client ID before saving.'; $script:DS.lblStatus.Foreground = 'Red'; return }
            Lz933059a102 -Name 'DattoEndpointUrl' -Value $ep
            Lz933059a102 -Name 'DattoClientId'    -Value ("$($script:DS.tbDId.Text)".Trim())
            if ($script:DS.pbSec.Password) { Lz9b56e15ca5 -Value $script:DS.pbSec.Password }
            if ($script:JobOpen -and $script:ConfigPath) { try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch {} }
            $script:DS.win2.Close()
        } catch { $script:DS.lblStatus.Text = "Could not save: $($_.Exception.Message)"; $script:DS.lblStatus.Foreground = 'Red' }
    })
    [void]$win2.ShowDialog()
    $script:DS = $null
}
function Lz955fc24a6f {
    $dep = [string](Get-RegSetting 'DattoEndpointUrl')
    $did = [string](Get-RegSetting 'DattoClientId')
    $sec = Lzff3ae1afba
    return [bool]($dep -and $did -and $sec)
}
function Lze2b4dac580 {
    $tid = [string](Get-RegSetting 'TenantId')
    $app = [string](Get-RegSetting 'GraphClientId')
    $th  = [string](Get-RegSetting 'CertThumbprint')
    if (-not ($tid -and $app -and $th)) { return $false }
    try {
        $c = Get-Item "Cert:\CurrentUser\My\$th" -ErrorAction Stop
        return [bool]$c.HasPrivateKey
    } catch { return $false }
}
function Lzba679f954b {
    param($Row, [bool]$Done, [switch]$Optional)
    if (-not $Row -or -not $Row.Chip) { return }
    $bc = New-Object System.Windows.Media.BrushConverter
    if ($Done) {
        $Row.Chip.Background = $bc.ConvertFromString('#E7F7EF')
        $Row.Glyph.Text = [string][char]0xE73E
        $Row.Glyph.Foreground = $bc.ConvertFromString('#0E9F6E')
    } elseif ($Optional) {
        $Row.Chip.Background = $bc.ConvertFromString('#F2F4F7')
        $Row.Glyph.Text = "$($Row.StepGlyph)"
        $Row.Glyph.Foreground = $bc.ConvertFromString('#98A2B3')
    } else {
        $Row.Chip.Background = $bc.ConvertFromString($Row.Tint)
        $Row.Glyph.Text = "$($Row.StepGlyph)"
        $Row.Glyph.Foreground = $bc.ConvertFromString($Row.Colour)
    }
}
function Lzc0d02014af {
    if (-not $script:SC) { return }
    $ok = '#0E9F6E'; $grey = '#475467'
    $psOk  = ($PSVersionTable.PSVersion.Major -ge 7)
    $gmOk  = [bool](Get-Module Microsoft.Graph.Authentication -ListAvailable)
    $preOk = ($psOk -and $gmOk)
    Lzba679f954b -Row $script:SC.Pre -Done $preOk
    $script:SC.PreText.Text = if ($preOk) { 'PowerShell 7 and the Microsoft Graph module are installed.' }
        elseif (-not $psOk) { 'PowerShell 7 is not running this app. Re-run the installer, which sets it up.' }
        else { 'The Microsoft Graph module is missing. Re-run the installer, which sets it up.' }
    $isFilesMode = ($script:TransferMode -eq 'LocalFs')
    $dOk = if ($isFilesMode) { $true } else { Lz955fc24a6f }
    if (-not $isFilesMode) {
        Lzba679f954b -Row $script:SC.Dat -Done $dOk
        $script:SC.DatText.Text = if ($dOk) { 'Datto Workplace credentials are saved on this computer.' }
            else { 'Not set yet. You need the Client ID and Secret from an API integration in the Datto Workplace admin portal.' }
    }
    $mOk = Lze2b4dac580
    Lzba679f954b -Row $script:SC.Ms -Done $mOk
    $script:SC.MsText.Text = if ($mOk) { 'Microsoft 365 is connected: app registration, certificate and consent are in place.' }
        else { 'Not set yet. The wizard signs in as your Microsoft 365 admin and sets everything up for you.' }
    $eOk = Lz22d094aa86
    Lzba679f954b -Row $script:SC.Em -Done $eOk -Optional
    $script:SC.EmText.Text = if ($eOk) { "Email alerts are on, sending from $([string](Get-RegSetting 'EmailSender'))." }
        else { 'Optional. An email with the outcome, the report and the logs when a run finishes; made for overnight and scheduled runs. Set it up now, or any time later.' }
    $allOk = ($preOk -and $dOk -and $mOk)
    $script:SC.BtnGo.IsEnabled = $allOk
    if ($allOk) {
        $script:SC.LblFoot.Text = 'Everything is ready. You can start your first migration.'
        $script:SC.LblFoot.Foreground = $ok
    } else {
        $left = @()
        if (-not $preOk) { $left += 'prerequisites' }
        if (-not $dOk)   { $left += 'Datto credentials' }
        if (-not $mOk)   { $left += 'Microsoft 365' }
        $script:SC.LblFoot.Text = "Still to do: $($left -join ', '). Datto and Microsoft 365 are independent; do either first."
        $script:SC.LblFoot.Foreground = $grey
    }
}
function Lzb52a94c8d8 {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Set up this computer'
    $w.Width = 720; $w.SizeToContent = 'Height'; $w.ResizeMode = 'NoResize'; $w.Background = 'White'
    $w.FontFamily = 'Segoe UI'; $w.FontSize = 13
    $w.WindowStartupLocation = 'CenterScreen'
    try { if ($win -and $win.IsVisible) { $w.Owner = $win; $w.WindowStartupLocation = 'CenterOwner' } } catch {}
    $dock = New-Object System.Windows.Controls.DockPanel
    $w.Content = $dock
    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = '#0F1115'; $hdr.Padding = '20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
    $hs = New-Object System.Windows.Controls.StackPanel
    $ht = New-Object System.Windows.Controls.TextBlock
    $ht.Text = 'Set up this computer'; $ht.Foreground = 'White'; $ht.FontSize = 16; $ht.FontWeight = 'SemiBold'
    $h2 = New-Object System.Windows.Controls.TextBlock
    $h2.Text = if ($script:TransferMode -eq 'LocalFs') { 'One one-time step connects this computer to Microsoft 365. Green ticks show what is done.' } else { 'Two one-time steps connect this computer to Datto Workplace and Microsoft 365. Green ticks show what is done.' }
    $h2.Foreground = '#9BA1AA'; $h2.TextWrapping = 'Wrap'; $h2.Margin = '0,4,0,0'
    [void]$hs.Children.Add($ht); [void]$hs.Children.Add($h2); $hdr.Child = $hs
    [void]$dock.Children.Add($hdr)
    $foot = New-Object System.Windows.Controls.Border
    $foot.Background = '#F7F8FA'; $foot.BorderBrush = '#E4E7EC'; $foot.BorderThickness = '0,1,0,0'; $foot.Padding = '16,11'
    [System.Windows.Controls.DockPanel]::SetDock($foot, 'Bottom')
    $fd = New-Object System.Windows.Controls.DockPanel
    $lblFoot = New-Object System.Windows.Controls.TextBlock
    $lblFoot.TextWrapping = 'Wrap'; $lblFoot.VerticalAlignment = 'Center'; $lblFoot.MaxWidth = 380
    [System.Windows.Controls.DockPanel]::SetDock($lblFoot, 'Left')
    [void]$fd.Children.Add($lblFoot)
    $fb = New-Object System.Windows.Controls.StackPanel
    $fb.Orientation = 'Horizontal'; $fb.HorizontalAlignment = 'Right'
    $btnClose = New-Object System.Windows.Controls.Button
    $btnClose.Content = 'Close'; $btnClose.Padding = '16,5'; $btnClose.MinWidth = 88; $btnClose.IsCancel = $true
    $btnClose.ToolTip = 'You can come back any time: this checklist reappears at startup until setup is complete, and each step also lives under Settings.'
    $btnGo = New-Object System.Windows.Controls.Button
    $btnGo.Content = 'Start migrating'; $btnGo.Padding = '16,5'; $btnGo.MinWidth = 110; $btnGo.Margin = '8,0,0,0'
    $btnGo.FontWeight = 'SemiBold'; $btnGo.IsEnabled = $false
    [void]$fb.Children.Add($btnClose); [void]$fb.Children.Add($btnGo)
    [void]$fd.Children.Add($fb)
    $foot.Child = $fd
    [void]$dock.Children.Add($foot)
    $body = New-Object System.Windows.Controls.StackPanel
    $body.Margin = '20,16,20,16'
    [void]$dock.Children.Add($body)
    function Lzb0de929344 {
        param([string]$Title, [System.Windows.Controls.Button[]]$Buttons, [string]$Glyph, [string]$Tint = '#EFF4F9', [string]$Colour = '#1C6091')
        $g = New-Object System.Windows.Controls.Grid
        $g.Margin = '0,0,0,14'
        foreach ($cw in 'Auto','*','Auto') {
            $c = New-Object System.Windows.Controls.ColumnDefinition
            $c.Width = if ($cw -eq '*') { '*' } else { 'Auto' }
            $g.ColumnDefinitions.Add($c)
        }
        $chip = New-Object System.Windows.Controls.Border
        $chip.Width = 34; $chip.Height = 34; $chip.CornerRadius = '9'; $chip.VerticalAlignment = 'Top'; $chip.Margin = '0,0,12,0'
        $bc = New-Object System.Windows.Media.BrushConverter
        $chip.Background = $bc.ConvertFromString($Tint)
        $gl = New-Object System.Windows.Controls.TextBlock
        $gl.FontFamily = 'Segoe MDL2 Assets'; $gl.FontSize = 16; $gl.HorizontalAlignment = 'Center'; $gl.VerticalAlignment = 'Center'
        $gl.Text = "$Glyph"; $gl.Foreground = $bc.ConvertFromString($Colour)
        $chip.Child = $gl
        [System.Windows.Controls.Grid]::SetColumn($chip, 0); [void]$g.Children.Add($chip)
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'
        $tt = New-Object System.Windows.Controls.TextBlock
        $tt.Text = $Title; $tt.FontWeight = 'SemiBold'; $tt.Foreground = '#101828'
        $td = New-Object System.Windows.Controls.TextBlock
        $td.TextWrapping = 'Wrap'; $td.Foreground = '#475467'; $td.Margin = '0,2,0,0'
        [void]$sp.Children.Add($tt); [void]$sp.Children.Add($td)
        [System.Windows.Controls.Grid]::SetColumn($sp, 1); [void]$g.Children.Add($sp)
        if ($Buttons) {
            $bp = New-Object System.Windows.Controls.StackPanel
            $bp.Orientation = 'Horizontal'; $bp.VerticalAlignment = 'Center'; $bp.Margin = '10,0,0,0'
            foreach ($b in $Buttons) { [void]$bp.Children.Add($b) }
            [System.Windows.Controls.Grid]::SetColumn($bp, 2); [void]$g.Children.Add($bp)
        }
        [void]$body.Children.Add($g)
        return @{ Chip = $chip; Glyph = $gl; Text = $td; Grid = $g; StepGlyph = "$Glyph"; Tint = $Tint; Colour = $Colour }
    }
    function New-InfoButton {
        param([string]$Tip, [string]$Url)
        $ib = New-Object System.Windows.Controls.Button
        $ib.Content = ([char]0xE946); $ib.FontFamily = 'Segoe MDL2 Assets'; $ib.FontSize = 14
        $ib.Width = 30; $ib.Padding = '0,4'; $ib.Margin = '6,0,0,0'; $ib.VerticalAlignment = 'Center'; $ib.FocusVisualStyle = $null
        $ib.ToolTip = $Tip
        $ib.Tag = $Url
        $ib.Add_Click({ try { if ("$($args[0].Tag)") { Start-Process "$($args[0].Tag)" } } catch {} })
        return $ib
    }
    $pre = Lzb0de929344 -Title 'Prerequisites' -Glyph ([char]0xE9D5) -Tint '#EFF4F9' -Colour '#1C6091'
    $bDat = New-Object System.Windows.Controls.Button
    $bDat.Content = 'Enter credentials...'; $bDat.Padding = '10,4'; $bDat.VerticalAlignment = 'Center'
    $dat = Lzb0de929344 -Title 'Datto Workplace credentials' -Glyph ([char]0xE753) -Tint '#FDEAD7' -Colour '#E2500F' -Buttons @($bDat, (New-InfoButton -Tip 'Step-by-step Datto setup guide (opens liscaragh.com in your browser)' -Url 'https://liscaragh.com/migrate/help/datto-api-setup/'))
    if ($script:TransferMode -eq 'LocalFs') { $dat.Grid.Visibility = 'Collapsed' }
    $bMs = New-Object System.Windows.Controls.Button
    $bMs.Content = 'Set up...'; $bMs.Padding = '10,4'; $bMs.VerticalAlignment = 'Center'; $bMs.FontWeight = 'SemiBold'
    $ms = Lzb0de929344 -Title 'Microsoft 365' -Glyph ([char]0xE71B) -Tint '#EFF4F9' -Colour '#1C6091' -Buttons @($bMs, (New-InfoButton -Tip 'What the wizard does, explained (opens liscaragh.com in your browser)' -Url 'https://liscaragh.com/migrate/help/microsoft-365-setup/'))
    $bEm = New-Object System.Windows.Controls.Button
    $bEm.Content = 'Set up...'; $bEm.Padding = '10,4'; $bEm.VerticalAlignment = 'Center'
    $em = Lzb0de929344 -Title 'Email alerts (optional)' -Glyph ([char]0xE715) -Tint '#FFF4E6' -Colour '#B5460F' -Buttons @($bEm)
    $manual = New-Object System.Windows.Controls.TextBlock
    $manual.Text = 'Prefer to do the Microsoft 365 side by hand, or handed the details by an IT contact? Settings > API settings takes the values directly.'
    $manual.TextWrapping = 'Wrap'; $manual.Foreground = '#98A2B3'; $manual.FontSize = 11; $manual.Margin = '34,0,0,0'
    [void]$body.Children.Add($manual)
    $script:SC = @{
        Win = $w; LblFoot = $lblFoot; BtnGo = $btnGo
        Pre = $pre; PreText = $pre.Text
        Dat = $dat; DatText = $dat.Text
        Ms  = $ms;  MsText  = $ms.Text
        Em  = $em;  EmText  = $em.Text
    }
    $bDat.Add_Click({ try { Lz45a93a6e9e } catch { (Show-Msg -Text ("The Datto step hit a problem: $($_.Exception.Message)") -Icon ('Error')) | Out-Null }; try { Lzc0d02014af; $script:SC.Win.Activate() | Out-Null } catch {} })
    $bMs.Add_Click({ try { Lz2aff4ed221 } catch { (Show-Msg -Text ("The Microsoft 365 setup hit a problem: $($_.Exception.Message)") -Icon ('Error')) | Out-Null }; try { Lzc0d02014af; $script:SC.Win.Activate() | Out-Null } catch {} })
    $bEm.Add_Click({ try { Lz0d05ab3822 } catch { (Show-Msg -Text ("The email step hit a problem: $($_.Exception.Message)") -Icon ('Error')) | Out-Null }; try { Lzc0d02014af; $script:SC.Win.Activate() | Out-Null } catch {} })
    $btnGo.Add_Click({ try { $script:SC.Win.Close() } catch {} })
    Lzc0d02014af
    [void]$w.ShowDialog()
    $script:SC = $null
}
function Lzabe998b441 {
    param([string]$Text, [string]$Colour = '#475467', [switch]$Strong)
    if (-not $script:WZ) { return }
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text; $t.TextWrapping = 'Wrap'; $t.Foreground = $Colour; $t.Margin = '0,2,0,0'
    if ($Strong) { $t.FontWeight = 'SemiBold' }
    [void]$script:WZ.Log.Children.Add($t)
    try { $script:WZ.Scroll.ScrollToEnd() } catch {}
    try { $script:WZ.Win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) } catch {}
}
function Lz0c28a29f63 {
    param([int]$Seconds, [string]$Message)
    if (-not $script:WZ) { Start-Sleep -Seconds $Seconds; return }
    $t = New-Object System.Windows.Controls.TextBlock
    $t.TextWrapping = 'Wrap'; $t.Margin = '0,2,0,0'; $t.FontWeight = 'Bold'
    [void]$script:WZ.Log.Children.Add($t)
    for ($s = $Seconds; $s -gt 0; $s--) {
        $t.Text = "$Message - $s second(s) to go..."
        $t.Foreground = if ($s % 2 -eq 0) { '#DC5818' } else { '#B5460F' }
        try { $script:WZ.Scroll.ScrollToEnd() } catch {}
        try { $script:WZ.Win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) } catch {}
        Start-Sleep -Seconds 1
    }
    $t.Text = "$Message - done."; $t.Foreground = '#0E9F6E'; $t.FontWeight = 'Normal'
    try { $script:WZ.Win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) } catch {}
}
function Lzb8c7669d2d {
    param([string]$Text)
    if (-not $script:WZ) { return }
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text; $t.TextWrapping = 'Wrap'; $t.Margin = '0,2,0,0'; $t.FontWeight = 'Bold'; $t.Foreground = '#B5460F'
    [void]$script:WZ.Log.Children.Add($t)
    try { $script:WZ.Scroll.ScrollToEnd() } catch {}
    try { $script:WZ.Win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render) } catch {}
}
function Lzcde6f6f114 {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}
function Lza5a04ff472 {
    try {
        Add-Type -Namespace Liscara -Name ConsoleUtil -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")]   public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList(uint[] processList, uint processCount);
'@ -ErrorAction Stop
        $script:ConsoleHwnd = [Liscara.ConsoleUtil]::GetConsoleWindow()
        if ($script:ConsoleHwnd -ne [IntPtr]::Zero) {
            $list = [uint32[]]::new(8)
            $n = [Liscara.ConsoleUtil]::GetConsoleProcessList($list, 8)
            $script:ConsoleOwned = ($n -le 1)
        }
    } catch {}
}
function Lze879f9f2d6 {
    if ($script:ConsoleOwned -and $script:ConsoleHwnd -ne [IntPtr]::Zero) {
        try { [void][Liscara.ConsoleUtil]::ShowWindow($script:ConsoleHwnd, 0); $script:ConsoleHidden = $true } catch {}
    }
}
function Lzddf6105216 {
    if ($script:ConsoleHwnd -ne [IntPtr]::Zero) {
        try {
            [void][Liscara.ConsoleUtil]::ShowWindow($script:ConsoleHwnd, 5)
            [void][Liscara.ConsoleUtil]::SetForegroundWindow($script:ConsoleHwnd)
            $script:ConsoleHidden = $false
        } catch {}
    }
}
function Lz171e66b17f {
    param([string]$Token, [string]$Claim)
    try {
        $p = ($Token -split '\.')[1].Replace('-', '+').Replace('_', '/')
        switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
        $j = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
        $prop = $j.PSObject.Properties[$Claim]
        if ($prop) { return "$($prop.Value)" }
    } catch {}
    return ''
}
function Lzd9eb2b4815 {
    param([string]$Code, [string]$Url, [string]$Step, [string]$Purpose)
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Your sign-in code'; $w.Width = 460; $w.SizeToContent = 'Height'; $w.ResizeMode = 'NoResize'
    $w.Topmost = $true; $w.ShowInTaskbar = $true; $w.Background = 'White'
    $w.WindowStartupLocation = 'Manual'
    try { $wa = [System.Windows.SystemParameters]::WorkArea; $w.Left = $wa.X + 40; $w.Top = $wa.Y + 40 } catch {}
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '18'
    $hdr = New-DialogHeader -Title 'Your sign-in code'
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($sp)
    $w.Content = $dock
    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = 'Enter this code in the Microsoft sign-in page:'; $t1.TextWrapping = 'Wrap'
    $t1.FontSize = 15; $t1.FontWeight = 'SemiBold'; $t1.Foreground = '#B42318'
    [void]$sp.Children.Add($t1)
    $tc = New-Object System.Windows.Controls.TextBox
    $tc.Text = $Code; $tc.FontSize = 40; $tc.FontWeight = 'Bold'; $tc.Foreground = '#DC5818'
    $tc.BorderThickness = '0'; $tc.Background = 'Transparent'; $tc.IsReadOnly = $true
    $tc.HorizontalContentAlignment = 'Center'; $tc.Margin = '0,10,0,10'
    [void]$sp.Children.Add($tc)
    $bp = New-Object System.Windows.Controls.StackPanel; $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Center'
    $bCopy = New-Object System.Windows.Controls.Button; $bCopy.Content = 'Copy the code'; $bCopy.Padding = '12,5'; $bCopy.Margin = '0,0,8,0'
    $bOpen = New-Object System.Windows.Controls.Button; $bOpen.Content = 'Open the sign-in page'; $bOpen.Padding = '12,5'
    [void]$bp.Children.Add($bCopy); [void]$bp.Children.Add($bOpen)
    [void]$sp.Children.Add($bp)
    $ls = New-Object System.Windows.Controls.TextBlock
    $ls.Text = 'Waiting for you to finish signing in... this window closes itself when done.'
    $ls.TextWrapping = 'Wrap'; $ls.Foreground = '#475467'; $ls.Margin = '0,12,0,0'
    [void]$sp.Children.Add($ls)
    if ($Step) {
        $st = New-Object System.Windows.Controls.TextBlock
        $st.Text = $Step; $st.TextWrapping = 'Wrap'; $st.FontWeight = 'SemiBold'; $st.Foreground = '#101828'
        $st.FontSize = 12; $st.Margin = '0,12,0,0'
        [void]$sp.Children.Add($st)
    }
    if ($Purpose) {
        $pu = New-Object System.Windows.Controls.TextBlock
        $pu.Text = $Purpose; $pu.TextWrapping = 'Wrap'; $pu.Foreground = '#475467'; $pu.FontSize = 11; $pu.Margin = '0,4,0,0'
        [void]$sp.Children.Add($pu)
    }
    $script:DC = @{ Win = $w; Lbl = $ls; Ins = $t1; Code = $Code; Url = $Url }
    $bCopy.Add_Click({ try { [System.Windows.Clipboard]::SetText("$($script:DC.Code)"); $script:DC.Lbl.Text = 'Copied. Paste it into the sign-in page (Ctrl+V).' } catch {} })
    $bOpen.Add_Click({ try { Lzd22fda8870 -Url "$($script:DC.Url)" } catch {} })
    $w.Show()
}
function Lzfa56acf041 {
    if ($script:DC) { try { $script:DC.Win.Close() } catch {}; $script:DC = $null }
}
function Lz59f59887fc {
    param([string]$ClientId, [string]$Scope, [string]$Tenant = 'organizations', [scriptblock]$Say, [string]$Step, [string]$Purpose)
    if (-not $Say) { $Say = { } }
    $dc = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/devicecode" -Body @{ client_id = $ClientId; scope = $Scope } -TimeoutSec 60 -ErrorAction Stop
    $code = "$($dc.user_code)"
    $pageUrl = "https://login.microsoftonline.com/common/oauth2/deviceauth?otc=$code"
    try { [System.Windows.Clipboard]::SetText($code) } catch {}
    & $Say "Your sign-in code is:  $code   - it is shown in the small window at the top left and is already on your clipboard." '#B42318'
    Lzd9eb2b4815 -Code $code -Url $pageUrl -Step $Step -Purpose $Purpose
    Lzd22fda8870 -Url $pageUrl
    $deadline = (Get-Date).AddSeconds([int]$dc.expires_in - 15)
    $interval = [Math]::Max([int]$dc.interval, 5)
    try {
        while ((Get-Date) -lt $deadline) {
            for ($i = 0; $i -lt $interval; $i++) {
                try {
                    if ($script:DC) {
                        $script:DC.Ins.Foreground = if ($i % 2) { '#DC5818' } else { '#B42318' }
                        $script:DC.Win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background)
                    }
                    elseif ($script:WZ) { $script:WZ.Win.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) }
                    elseif ($script:ES) { $script:ES.win2.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) }
                } catch {}
                Start-Sleep -Seconds 1
            }
            try {
                $tok = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body @{
                    grant_type = 'urn:ietf:params:oauth:grant-type:device_code'; client_id = $ClientId; device_code = "$($dc.device_code)"
                } -TimeoutSec 60 -ErrorAction Stop
                if ($tok.access_token) {
                    try { if ($script:DC) { $script:DC.Lbl.Text = 'Signed in. Carrying on...' } } catch {}
                    try { Lz5809f1ab49 } catch {}
                    return "$($tok.access_token)"
                }
            } catch {
                $body = ''; try { $body = "$($_.ErrorDetails.Message)" } catch {}
                if ($body -match 'authorization_declined') { throw 'the sign-in was declined.' }
                if ($body -match 'expired_token') { throw 'the sign-in code expired before it was used.' }
                if ($body -match 'slow_down') { Start-Sleep -Seconds 5 }
                elseif ($body -notmatch 'authorization_pending') { throw "the code sign-in failed: $($_.Exception.Message)" }
            }
        }
        throw 'the sign-in code expired before it was used.'
    } finally { Lzfa56acf041 }
}
function Lz5809f1ab49 {
    try {
        if (-not ('Liscara.WinShow' -as [type])) {
            Add-Type -Namespace Liscara -Name WinShow -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
        }
        $h = [Liscara.WinShow]::GetForegroundWindow()
        if ($h -ne [IntPtr]::Zero) {
            $procId = 0
            [void][Liscara.WinShow]::GetWindowThreadProcessId($h, [ref]$procId)
            $pname = ''
            try { $pname = (Get-Process -Id $procId -ErrorAction Stop).ProcessName.ToLower() } catch {}
            if ($pname -in @('msedge', 'chrome', 'firefox', 'brave', 'opera', 'vivaldi', 'iexplore')) {
                [void][Liscara.WinShow]::ShowWindow($h, 6)
            }
        }
    } catch {}
    try {
        foreach ($cand in @($(if ($script:WZ) { $script:WZ.Win }), $(if ($script:ES) { $script:ES.win2 }), $(if ($script:DX) { $script:DX.win2 }), $(if ($script:SC) { $script:SC.Win }), $win)) {
            if ($cand -and $cand.IsVisible) { $cand.Activate() | Out-Null; break }
        }
    } catch {}
}
function Lzd22fda8870 {
    param([string]$Url)
    try {
        $progId = ''
        try { $progId = [string]((Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -Name ProgId -ErrorAction Stop).ProgId) } catch {}
        $exe = if ($progId -like 'MSEdge*') { 'msedge.exe' } elseif ($progId -like 'Chrome*') { 'chrome.exe' } else { '' }
        if ($exe) {
            $path = ''
            foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')) {
                if (-not $path) { try { $path = [string]((Get-ItemProperty -Path (Join-Path $root $exe) -ErrorAction Stop).'(default)') } catch {} }
            }
            if ($path -and (Test-Path $path)) {
                $wa = [System.Windows.SystemParameters]::WorkArea
                $w = [int]($wa.Width / 2); $h = [int]$wa.Height
                $x = [int]($wa.X + $wa.Width - $w); $y = [int]$wa.Y
                Start-Process -FilePath $path -ArgumentList '--new-window', "--window-position=$x,$y", "--window-size=$w,$h", $Url
                return
            }
        }
    } catch {}
    try { Start-Process $Url } catch {}
}
function Lz27d148e1df {
    try { if (Get-Command Set-MgGraphOption -ErrorAction SilentlyContinue) { Set-MgGraphOption -EnableLoginByWAM $false | Out-Null } } catch {}
}
function Lzaba5827ae9 {
    if (Lzcde6f6f114) { return $false }
    try { return ("$((Get-ItemProperty -Path 'HKCU:\Software\DattoMigration' -Name 'PreferBrowserSignIn' -ErrorAction SilentlyContinue).PreferBrowserSignIn)" -match '^(1|true|yes|on)$') } catch { return $false }
}
function Lzabb4d5de33 {
    param([scriptblock]$Action)
    $held = @()
    foreach ($cand in @($(if ($script:WZ) { $script:WZ.Win }), $(if ($script:SC) { $script:SC.Win }), $(if ($script:ES) { $script:ES.win2 }), $win)) {
        try { if ($cand -and $cand.IsVisible) { $held += @{ W = $cand; S = $cand.WindowState; L = $cand.Left; T = $cand.Top; Wd = $cand.ActualWidth } } } catch {}
    }
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $half = [double]($wa.Width / 2)
        foreach ($h in $held) {
            $h.W.WindowState = 'Normal'
            $h.W.Left = $wa.X; $h.W.Top = $wa.Y
            if ($h.W.ActualWidth -gt $half) { $h.W.Width = $half }
        }
    } catch {}
    try { & $Action }
    finally {
        try { Lz5809f1ab49 } catch {}
        try {
            foreach ($h in $held) {
                $h.W.Left = $h.L; $h.W.Top = $h.T
                if ($h.Wd -gt 0) { $h.W.Width = $h.Wd }
                $h.W.WindowState = $h.S
            }
            if ($held.Count) { $held[0].W.Activate() | Out-Null }
        } catch {}
    }
}
function Lzbfa1bd231b {
    param([switch]$ForEmail)
    $script:WizSetupOk = $false
    $graphResId = '00000003-0000-0000-c000-000000000000'
    $roleNames  = @('Sites.ReadWrite.All','Files.ReadWrite.All','User.Read.All','Domain.Read.All','Organization.Read.All','Sites.Manage.All')
    if (-not (Get-Module Microsoft.Graph.Authentication -ListAvailable)) {
        Lzabe998b441 'The Microsoft Graph module is not installed. Re-run the installer (or run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser) and try again.' '#B42318' -Strong
        return
    }
    Lzabe998b441 'Preparing the Microsoft 365 sign-in. The first time on a new install can take up to a minute while Windows loads the components - please wait, the app has not frozen.' '#475467' -Strong
    try { Import-Module Microsoft.Graph.Authentication -ErrorAction Stop } catch {
        Lzabe998b441 "Could not load the Microsoft Graph module: $($_.Exception.Message)" '#B42318' -Strong
        return
    }
    Lzabe998b441 "Sign in with an account that can manage Microsoft 365 (a Global Administrator is simplest). The first time, Microsoft asks you to accept the permissions this setup itself needs; that is expected.$(if ($ForEmail) { ' Email alerts are included, so expect TWO sign-ins: this one, then one for Exchange Online (a separate service with its own sign-in).' })"
    $wizScopes = @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Organization.Read.All')
    if ($ForEmail) { $wizScopes += 'User.Read.All' }
    Lz27d148e1df
    $wizTokTid = ''; $wizTokAcct = ''; $wizConnected = $false
    if (Lzaba5827ae9) {
        Lzabe998b441 'A MICROSOFT SIGN-IN WINDOW IS ABOUT TO OPEN. It can hide behind other windows - if you do not see it, check the taskbar. The app will not respond while it is open; that is normal.' '#B5460F' -Strong
        try {
            Lzabb4d5de33 -Action { Connect-MgGraph -Scopes $wizScopes -NoWelcome -ErrorAction Stop }
            $wizConnected = $true
        } catch {
            Lzabe998b441 "The browser sign-in did not complete ($($_.Exception.Message)). Switching to a CODE sign-in: a small window will show your code, always on top." '#B5460F' -Strong
        }
    } else {
        Lzabe998b441 'Using the code sign-in (the reliable path): a small window will show your code to type at microsoft.com/devicelogin, or on your phone. It stays on top and closes itself when you are done.' '#B5460F' -Strong
    }
    if (-not $wizConnected) {
        try {
            $at = Lz59f59887fc -ClientId '14d82eec-204b-4c2f-b7e8-296a70dab67e' -Scope ($wizScopes -join ' ') -Say { param($t, $c) Lzabe998b441 $t $(if ($c) { $c } else { '#475467' }) -Strong } `
                -Step $(if ($ForEmail) { 'Sign-in 1 of 2: Microsoft 365 setup. A second sign-in, for Exchange Online, follows because email alerts are included.' } else { 'The only sign-in for this setup: Microsoft 365.' }) `
                -Purpose "This sign-in asks your admin account for: Application.ReadWrite.All (create or find the app registration and add this computer's certificate), AppRoleAssignment.ReadWrite.All (record admin consent for the migration permissions), Organization.Read.All (read your tenant name and verified domains)$(if ($ForEmail) { ', User.Read.All (check whether the sender mailbox already exists)' }). Used once, for this setup only - migrations run with the app's certificate, never your account."
            $wizTokTid = Lz171e66b17f -Token $at -Claim 'tid'
            $wizTokAcct = Lz171e66b17f -Token $at -Claim 'upn'
            if (-not $wizTokAcct) { $wizTokAcct = Lz171e66b17f -Token $at -Claim 'preferred_username' }
            if ($wizTokAcct) { $script:CodeSignInUpn = $wizTokAcct }
            Connect-MgGraph -AccessToken (ConvertTo-SecureString $at -AsPlainText -Force) -NoWelcome -ErrorAction Stop
        } catch {
            Lzabe998b441 "Sign-in did not complete: $($_.Exception.Message)" '#B42318' -Strong
            Lzabe998b441 'Nothing was changed. You can try again, or use Settings > API settings to enter the details by hand.'
            return
        }
    }
    $mgc = Get-MgContext
    $tid = "$($mgc.TenantId)"; if (-not $tid) { $tid = $wizTokTid }
    $wizAcct = "$($mgc.Account)"; if (-not $wizAcct) { $wizAcct = $wizTokAcct }
    Lzabe998b441 "Signed in to tenant $tid as $wizAcct." '#0E9F6E'
    $newThumb = $null
    try {
        Lzabe998b441 'Reading the tenant''s Microsoft Graph service catalogue...'
        $gsp = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$graphResId'" -ErrorAction Stop)['value'])
        if (-not $gsp.Count) { throw 'Microsoft Graph''s service principal was not found in this tenant, which should never happen. Stopping.' }
        $graphSp = $gsp[0]
        $roles = @{}
        foreach ($ar in @($graphSp['appRoles'])) {
            if ($roleNames -contains "$($ar['value'])") { $roles["$($ar['value'])"] = "$($ar['id'])" }
        }
        foreach ($rn in $roleNames) { if (-not $roles.ContainsKey($rn)) { throw "The permission $rn was not found in Microsoft Graph's catalogue. Stopping rather than setting up a partial connection." } }
        $found = @(); $foundName = $script:WizAppName
        foreach ($candName in (@($script:WizAppName) + @($script:WizAppNamesLegacy))) {
            $esc = $candName -replace "'", "''"
            $found = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$esc'" -ErrorAction Stop)['value'])
            if ($found.Count) { $foundName = $candName; break }
        }
        if ($found.Count) {
            $app = $found[0]
            if ($found.Count -gt 1) { Lzabe998b441 "Note: $($found.Count) app registrations share the name '$foundName'. Using the oldest; consider removing the duplicates in Microsoft Entra." '#B5460F' }
            Lzabe998b441 "This tenant is already set up: reusing the existing app registration '$foundName' and adding this computer's certificate to it$(if ($foundName -ne $script:WizAppName) { ' (it keeps its existing name)' })." '#0E9F6E'
        } else {
            Lzabe998b441 "Creating the app registration '$($script:WizAppName)'..."
            $ra = @(); foreach ($rn in $roleNames) { $ra += @{ id = $roles[$rn]; type = 'Role' } }
            $app = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/applications' -Body @{
                displayName            = $script:WizAppName
                signInAudience         = 'AzureADMyOrg'
                requiredResourceAccess = @(@{ resourceAppId = $graphResId; resourceAccess = $ra })
            } -ErrorAction Stop
            Lzabe998b441 'App registration created.' '#0E9F6E'
        }
        $appId = "$($app['appId'])"; $appObj = "$($app['id'])"
        Lzabe998b441 'Generating a sign-in certificate for this computer (valid one year)...'
        $subject = "CN=$($script:WizAppName) - $($env:COMPUTERNAME)"
        $cert = New-SelfSignedCertificate -Subject $subject -CertStoreLocation 'Cert:\CurrentUser\My' `
            -KeyAlgorithm RSA -KeyLength 2048 -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(1)
        $newThumb = "$($cert.Thumbprint)"
        Lzabe998b441 "Certificate created in this user's store. Thumbprint $newThumb." '#0E9F6E'
        Lzabe998b441 'Uploading the certificate''s public key to the app registration...'
        $before = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications/$appObj`?`$select=keyCredentials" -ErrorAction Stop)['keyCredentials'])
        $keys = @()
        foreach ($k in $before) { $keys += $k }
        $keys += @{
            type                = 'AsymmetricX509Cert'
            usage               = 'Verify'
            key                 = [Convert]::ToBase64String($cert.RawData)
            customKeyIdentifier = [Convert]::ToBase64String($cert.GetCertHash())
            displayName         = $subject
        }
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/applications/$appObj" -Body @{ keyCredentials = $keys } -ErrorAction Stop
        $after = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications/$appObj`?`$select=keyCredentials" -ErrorAction Stop)['keyCredentials'])
        if ($after.Count -lt ($before.Count + 1)) {
            throw "The certificate upload finished but the app registration now lists $($after.Count) certificate(s) where $($before.Count + 1) were expected. Check Certificates and secrets on the app registration in Microsoft Entra before running a migration: another machine's certificate may have been dropped."
        }
        Lzabe998b441 "Public key uploaded. The app registration now holds $($after.Count) certificate(s); private keys stay on their own machines." '#0E9F6E'
        $sps = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$appId'" -ErrorAction Stop)['value'])
        $spJustCreated = $false
        $sp = if ($sps.Count) { $sps[0] } else {
            $spJustCreated = $true
            Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body @{ appId = $appId } -ErrorAction Stop
        }
        $spId = "$($sp['id'])"
        if ($spJustCreated) { Lz0c28a29f63 -Seconds 15 -Message 'Letting the new app registration settle before granting consent' }
        Lzabe998b441 'Granting admin consent for the six permissions...'
        $haveRoleIds = @{}
        try {
            foreach ($x in @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignments?`$top=999" -ErrorAction Stop)['value'])) {
                $haveRoleIds["$($x['appRoleId'])"] = $true
            }
        } catch {}
        $granted = 0; $already = 0
        foreach ($rn in $roleNames) {
            if ($haveRoleIds["$($roles[$rn])"]) { $already++; continue }
            $done = $false
            for ($ca = 1; $ca -le 4 -and -not $done; $ca++) {
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignments" -Body @{
                        principalId = $spId; resourceId = "$($graphSp['id'])"; appRoleId = $roles[$rn]
                    } -ErrorAction Stop | Out-Null
                    $granted++; $done = $true
                } catch {
                    $cm = "$($_.Exception.Message) $(try { $_.ErrorDetails.Message } catch { '' })"
                    if ($cm -match 'already exists') { $already++; $done = $true }
                    elseif (($cm -match 'BadRequest|Bad Request|NotFound|Not Found|does not exist|Request_ResourceNotFound') -and $ca -lt 4) {
                        Lz0c28a29f63 -Seconds 15 -Message "Permission '$rn' not ready yet (attempt $ca of 4), the new app is still propagating"
                    } else { throw }
                }
            }
        }
        $consentMsg = if ($already -and -not $granted) { 'Consent was already in place from an earlier setup.' }
            elseif ($already) { "Consent granted ($granted new, $already already in place)." }
            else { 'Consent granted.' }
        Lzabe998b441 $consentMsg '#0E9F6E'
        Lz933059a102 -Name 'TenantId'       -Value $tid
        Lz933059a102 -Name 'GraphClientId'  -Value $appId
        Lz933059a102 -Name 'CertThumbprint' -Value $newThumb
        Lzabe998b441 'Connection details saved on this computer.' '#0E9F6E'
    } catch {
        $m = "$($_.Exception.Message)"
        $friendly = if ($m -match 'Authorization_RequestDenied|Insufficient privileges|Forbidden') {
            'The signed-in account does not have permission to do this. Setting up needs an account that can create app registrations and grant admin consent: a Global Administrator is the simple answer. Sign out, then run the wizard again with an admin account.'
        } elseif ($m -match 'AADSTS65004|declined|denied') {
            'The permissions request was declined at the sign-in step. Nothing was set up. Run the wizard again and accept the permissions, or use Settings > API settings to enter the details by hand.'
        } else { $null }
        if ($friendly) { Lzabe998b441 $friendly '#B42318' -Strong; Lzabe998b441 "Technical detail: $m" }
        else { Lzabe998b441 "Setup stopped: $m" '#B42318' -Strong }
        if ($newThumb) { Lzabe998b441 "The certificate generated for this attempt (thumbprint $newThumb) is still in this user's certificate store; re-running the wizard after fixing the cause will create a fresh one, and unused ones can be deleted from certmgr.msc at any time." }
        if (-not $ForEmail) { try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
        return
    }
    if (-not $ForEmail) { try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
    Lzabe998b441 'Checking the new sign-in works (a brand-new setup can take a minute or two to become active)...'
    $tok = $null
    for ($i = 1; $i -le 8; $i++) {
        try {
            $tok = Lz1c498583eb -TenantId $tid -ClientId $appId -Thumbprint $newThumb
            $rootSite = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/sites/root' -Headers @{ Authorization = "Bearer $tok" } -TimeoutSec 60
            $spUrl = "$($rootSite.webUrl)".TrimEnd('/')
            Lz933059a102 -Name 'SharePointRootUrl' -Value $spUrl
            $der = Lz12d7a4ce3d $spUrl
            if ($der) {
                Lz933059a102 -Name 'OneDriveHostUrl' -Value $der.OneDriveHostUrl
                Lz933059a102 -Name 'TeamSiteBaseUrl' -Value $der.TeamSiteBaseUrl
                Lz933059a102 -Name 'DefaultSiteUrl'  -Value $der.DefaultSiteUrl
            }
            Lzabe998b441 "Sign-in works. SharePoint and OneDrive addresses detected from $spUrl." '#0E9F6E'
            break
        } catch {
            $tok = $null
            if ($i -lt 8) { Lz0c28a29f63 -Seconds 15 -Message "Not active yet (attempt $i of 8), this is normal for a brand-new setup" }
            else { Lzabe998b441 "The new sign-in has not become active yet: $($_.Exception.Message)" '#B5460F' -Strong
                   Lzabe998b441 'Everything is saved, so this usually just needs a few more minutes. Use Test connection under Settings > API settings to confirm, and Auto-detect URLs there to fill the addresses.' }
        }
    }
    if ($tok) {
        try {
            $org = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -Headers @{ Authorization = "Bearer $tok" } -TimeoutSec 60
            $u = Lzef4499bb1e $org
            if ($u) { Lz933059a102 -Name 'UpnDomain' -Value $u; Lzabe998b441 "Email domain detected: $u" '#0E9F6E' }
        } catch { Lzabe998b441 'The email (UPN) domain could not be read yet; enter it under Settings > API settings if OneDrive destinations need it.' }
        Lzabe998b441 'Microsoft 365 setup is COMPLETE. Datto Workplace credentials are the only remaining step (if not already done).' '#0E9F6E' -Strong
        $script:WizSetupOk = $true
    }
    if ($script:JobOpen -and $script:ConfigPath) { try { $script:Cfg = Import-ResolvedConfig $script:ConfigPath } catch {} }
}
function Lz2aff4ed221 {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $w = New-Object System.Windows.Window
    Lz2e8ddc8b18 $w
    $w.Title = 'Microsoft 365 setup'
    $w.Width = 680; $w.Height = 560; $w.ResizeMode = 'CanResize'; $w.MinWidth = 560; $w.MinHeight = 420
    $w.FontFamily = 'Segoe UI'; $w.FontSize = 13; $w.Background = 'White'
    $w.WindowStartupLocation = 'CenterScreen'
    try {
        if ($script:SC -and $script:SC.Win -and $script:SC.Win.IsVisible) { $w.Owner = $script:SC.Win; $w.WindowStartupLocation = 'CenterOwner' }
        elseif ($win -and $win.IsVisible) { $w.Owner = $win; $w.WindowStartupLocation = 'CenterOwner' }
    } catch {}
    $dock = New-Object System.Windows.Controls.DockPanel
    $w.Content = $dock
    $hdr = New-Object System.Windows.Controls.Border
    $hdr.Background = '#0F1115'; $hdr.Padding = '20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
    $hs = New-Object System.Windows.Controls.StackPanel
    $ht = New-Object System.Windows.Controls.TextBlock
    $ht.Text = 'Microsoft 365 setup'; $ht.Foreground = 'White'; $ht.FontSize = 16; $ht.FontWeight = 'SemiBold'
    $h2 = New-Object System.Windows.Controls.TextBlock
    $h2.Text = 'Signs in as your Microsoft 365 admin and sets up everything migrations need: the app registration, a certificate for this computer, the permissions, and admin consent.'
    $h2.Foreground = '#9BA1AA'; $h2.TextWrapping = 'Wrap'; $h2.Margin = '0,4,0,0'
    [void]$hs.Children.Add($ht); [void]$hs.Children.Add($h2); $hdr.Child = $hs
    [void]$dock.Children.Add($hdr)
    $foot = New-Object System.Windows.Controls.Border
    $foot.Background = '#F7F8FA'; $foot.BorderBrush = '#E4E7EC'; $foot.BorderThickness = '0,1,0,0'; $foot.Padding = '16,11'
    [System.Windows.Controls.DockPanel]::SetDock($foot, 'Bottom')
    $fd = New-Object System.Windows.Controls.DockPanel
    $chkEmail = New-Object System.Windows.Controls.CheckBox
    $chkEmail.Content = 'Also set up email alerts (optional)'; $chkEmail.VerticalAlignment = 'Center'; $chkEmail.MaxWidth = 260
    $chkEmail.ToolTip = 'After the Microsoft 365 setup: grants the Mail.Send permission, creates a shared liscaragh-migrate@your-domain mailbox via Exchange Online (no licence needed), and restricts sending to that one mailbox. Needs an Exchange admin sign-in - which only happens if this is ticked; unticked, the wizard makes one Microsoft sign-in and never touches Exchange. Setting it up later (Settings > Email alerts) takes one quick Microsoft sign-in (to grant the mail permission) plus the Exchange one.'
    [System.Windows.Controls.DockPanel]::SetDock($chkEmail, 'Left')
    [void]$fd.Children.Add($chkEmail)
    $fb = New-Object System.Windows.Controls.StackPanel
    $fb.Orientation = 'Horizontal'; $fb.HorizontalAlignment = 'Right'
    $btnCloseW = New-Object System.Windows.Controls.Button
    $btnCloseW.Content = 'Close'; $btnCloseW.Padding = '16,5'; $btnCloseW.MinWidth = 88; $btnCloseW.IsCancel = $true
    $btnRun = New-Object System.Windows.Controls.Button
    $btnRun.Content = 'Sign in and set up'; $btnRun.Padding = '16,5'; $btnRun.MinWidth = 140; $btnRun.Margin = '8,0,0,0'
    $btnRun.FontWeight = 'SemiBold'; $btnRun.IsDefault = $true
    [void]$fb.Children.Add($btnCloseW); [void]$fb.Children.Add($btnRun)
    [void]$fd.Children.Add($fb)
    $foot.Child = $fd
    [void]$dock.Children.Add($foot)
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Padding = '20,14'
    $log = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $log
    [void]$dock.Children.Add($scroll)
    $intro = New-Object System.Windows.Controls.TextBlock
    $intro.TextWrapping = 'Wrap'; $intro.Foreground = '#475467'
    $intro.Text = "What happens when you click the button:`n" +
        "  1.  You sign in with a Microsoft 365 admin account.`n" +
        "  2.  The '$($script:WizAppName)' app registration is created, or reused if this tenant already has one.`n" +
        "  3.  A sign-in certificate is created for this computer. Its private key never leaves this machine.`n" +
        "  4.  The migration permissions are granted and admin consent recorded.`n" +
        "  5.  The connection is tested and your SharePoint and OneDrive addresses are filled in.`n`n" +
        "Run it again any time: to rotate the certificate, after a rebuild, or on a second computer (which reuses the same app registration)."
    [void]$log.Children.Add($intro)
    $script:WZ = @{ Win = $w; Log = $log; Scroll = $scroll; BtnRun = $btnRun; BtnClose = $btnCloseW; ChkEmail = $chkEmail }
    $btnRun.Add_Click({
        $script:WZ.BtnRun.IsEnabled = $false
        try {
            $wantEmail = [bool]$script:WZ.ChkEmail.IsChecked
            Lzbfa1bd231b -ForEmail:$wantEmail
            $emailOkRun = $true
            if ($wantEmail) {
                $emailOkRun = $false
                if (Lze2b4dac580) {
                    Lzabe998b441 'Email alerts: setting up the sender...' -Strong
                    $ret = @(Invoke-EmailSenderSetup -ReuseGraphSession -Log { param($t, $c) if ($c) { Lzabe998b441 $t $c } else { Lzabe998b441 $t } })
                    $emailOkRun = ($ret.Count -gt 0 -and $ret[-1] -eq $true)
                } else {
                    Lzabe998b441 'Email alerts were not set up, because the Microsoft 365 setup did not complete. Fix that first, then use Settings > Email alerts.' '#B5460F'
                }
            }
            if ($script:WizSetupOk -and $emailOkRun) {
                $doneTb = New-Object System.Windows.Controls.TextBlock
                $doneTb.Text = "$([char]0x2714)  ALL DONE - everything is set up. Press the green Close button below to finish."
                $doneTb.FontSize = 15; $doneTb.FontWeight = 'Bold'; $doneTb.Foreground = '#0E9F6E'
                $doneTb.TextWrapping = 'Wrap'; $doneTb.Margin = '0,12,0,0'
                [void]$script:WZ.Log.Children.Add($doneTb)
                try { $script:WZ.Scroll.ScrollToEnd() } catch {}
                try {
                    $script:WZ.BtnClose.Content = 'Close - all done'
                    $script:WZ.BtnClose.Background = '#0E9F6E'; $script:WZ.BtnClose.Foreground = 'White'
                    $script:WZ.BtnClose.FontWeight = 'SemiBold'; $script:WZ.BtnClose.MinWidth = 140
                    $script:WZ.BtnRun.IsDefault = $false; $script:WZ.BtnClose.IsDefault = $true
                    $script:WZ.BtnClose.Focus() | Out-Null
                } catch {}
            }
        } catch {
            Lzabe998b441 "Setup hit an unexpected problem: $($_.Exception.Message). Nothing was left half-applied that a re-run will not sort out; you can also use Settings > API settings by hand." '#B42318' -Strong
        } finally {
            try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
            try { $script:WZ.BtnRun.IsEnabled = $true; $script:WZ.BtnRun.Content = 'Run again' } catch {}
        }
    })
    [void]$w.ShowDialog()
    $script:WZ = $null
}
function Lz22d094aa86 {
    return [bool](([string](Get-RegSetting 'EmailEnabled') -eq '1') -and [string](Get-RegSetting 'EmailSender'))
}
function Lz3b8c93f3d9 {
    param([string]$Template, [hashtable]$Vars)
    $out = "$Template"
    foreach ($k in @($Vars.Keys)) { $out = $out.Replace('{' + $k + '}', "$($Vars[$k])") }
    $out = [regex]::Replace($out, '\{(JobName|Action|Outcome|Source|Destination|FilesCopied|FilesFailed|Errors|SizeCopied|Duration|StartTime|EndTime|Tenant|Version)\}', '')
    return ([regex]::Replace($out, '\s{2,}', ' ')).Trim()
}
function Lzeeaadffc9c {
    $jn = 'Example job'
    if ($script:JobOpen -and $script:ConfigPath) {
        try { $jj = Join-Path (Split-Path $script:ConfigPath) 'job.json'; if (Test-Path $jj) { $n = (Get-Content $jj -Raw | ConvertFrom-Json).name; if ($n) { $jn = "$n" } } } catch {}
    }
    $dom = "$(Get-RegSetting 'UpnDomain')".TrimStart('@'); if (-not $dom) { $dom = 'contoso.com' }
    return @{
        JobName = $jn; Action = 'Sync'; Outcome = 'COMPLETED'; Source = 'Drawings/Current'; Destination = 'sites/TeamDocs'
        FilesCopied = '102'; FilesFailed = '0'; Errors = '0'; SizeCopied = '385.0 MB'; Duration = '00:04:31'
        StartTime = (Get-Date).ToString('yyyy-MM-dd HH:mm'); EndTime = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Tenant = $dom; Version = $script:AppVersion
    }
}
function Invoke-EmailSenderSetup {
    param([scriptblock]$Log, [switch]$ReuseGraphSession, [string]$DesiredSender)
    if (-not $Log) { $Log = { } }
    if (-not "$DesiredSender".Trim()) { $DesiredSender = [string](Get-RegSetting 'EmailSender') }
    $setupLogFile = $null
    try { if ($script:JobsRoot -and (Test-Path $script:JobsRoot)) { $setupLogFile = Join-Path $script:JobsRoot 'email-setup.log' } } catch {}
    $say = { param($t, $c)
        try { & $Log $t $c } catch {}
        if ($setupLogFile) { try { Add-Content -Path $setupLogFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $t) -ErrorAction SilentlyContinue } catch {} }
    }
    $emailWait = { param($Seconds, $Msg)
        & $say "$Msg - waiting $Seconds seconds..." '#B5460F'
        for ($w = 0; $w -lt $Seconds; $w++) {
            try { if ($script:ES) { $script:ES.win2.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) } } catch {}
            Start-Sleep -Seconds 1
        }
    }
    $graphResId = '00000003-0000-0000-c000-000000000000'
    function Lze88ab9acc1 {
        if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
            & $say 'Installing the Exchange Online module (one time; this can take a few minutes)...' '#475467'
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        }
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        $upn = ''; try { $upn = "$((Get-MgContext).Account)" } catch {}
        if (-not $upn) { $upn = "$script:CodeSignInUpn" }
        & $say "Exchange needs its own sign-in (it is a separate service; this is the only extra one). Use the same admin account$(if ($upn) { " ($upn)" })." '#475467'
        $done = $false
        if (Lzcde6f6f114) {
            & $say 'The app is running elevated, where Microsoft''s standard Exchange sign-in is known to fail - going straight to the code sign-in.' '#B5460F'
        } else {
            try {
                Lzabb4d5de33 -Action {
                    if ($upn) { Connect-ExchangeOnline -ShowBanner:$false -UserPrincipalName $upn -ErrorAction Stop }
                    else { Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop }
                }
                $done = $true
            } catch {
                $noWam = $false
                try { $noWam = (Get-Command Connect-ExchangeOnline).Parameters.ContainsKey('DisableWAM') } catch {}
                if ($noWam) {
                    & $say 'The Windows sign-in broker failed (a known fault). Opening the sign-in in your browser instead...' '#B5460F'
                    try {
                        Lzabb4d5de33 -Action {
                            if ($upn) { Connect-ExchangeOnline -ShowBanner:$false -UserPrincipalName $upn -DisableWAM -ErrorAction Stop }
                            else { Connect-ExchangeOnline -ShowBanner:$false -DisableWAM -ErrorAction Stop }
                        }
                        $done = $true
                    } catch { & $say 'The browser sign-in also failed; switching to the code sign-in.' '#B5460F' }
                } else {
                    & $say 'The Windows sign-in broker failed (a known fault), and this Exchange module version has no browser fallback - updating it fixes that for next time: Update-Module ExchangeOnlineManagement. Switching to the code sign-in.' '#B5460F'
                }
            }
        }
        if (-not $done) {
            $exoOrg = ''
            if ($upn -and $upn.Contains('@')) { $exoOrg = ($upn -split '@')[1] }
            if (-not $exoOrg) { $exoOrg = "$(Get-RegSetting 'UpnDomain')".TrimStart('@') }
            if (-not $exoOrg) { $es = [string](Get-RegSetting 'EmailSender'); if ($es -and $es.Contains('@')) { $exoOrg = ($es -split '@')[1] } }
            $canTok = $false
            try { $canTok = (Get-Command Connect-ExchangeOnline).Parameters.ContainsKey('AccessToken') } catch {}
            if ($canTok -and $exoOrg) {
                try {
                    & $say 'Code sign-in: a small window shows your code (top left, always on top). Enter it in the sign-in page and sign in with the admin account.' '#B5460F'
                    $exoTok = Lz59f59887fc -ClientId 'fb78d390-0c51-40cd-8e17-fdbfab77341b' -Scope 'https://outlook.office365.com/.default' -Say $say `
                        -Step 'Sign-in 2 of 2: Exchange Online (a separate service with its own sign-in).' `
                        -Purpose 'This sign-in uses your admin account''s existing Exchange access to: create the shared sender mailbox (no licence needed) and restrict the app to sending only from that one address. No new permissions are granted to the app in this step.'
                    Lzabb4d5de33 -Action { Connect-ExchangeOnline -AccessToken $exoTok -Organization $exoOrg -ShowBanner:$false -ErrorAction Stop }
                    $done = $true
                } catch { & $say "The code sign-in did not complete ($($_.Exception.Message)); one more fallback remains." '#B5460F' }
            }
            if (-not $done) {
                & $say 'Falling back to the console code sign-in. The sign-in page is opening in your browser, and the black window holding the CODE is coming to the front: type that code into the browser page.' '#B5460F'
                Lzd22fda8870 -Url 'https://login.microsoft.com/device'
                Lzddf6105216
                try { Lzabb4d5de33 -Action { Connect-ExchangeOnline -ShowBanner:$false -Device -ErrorAction Stop } }
                finally { Lze879f9f2d6 }
            }
        }
    }
    $tid = [string](Get-RegSetting 'TenantId'); $appId = [string](Get-RegSetting 'GraphClientId')
    if (-not $tid -or -not $appId) {
        & $say 'Set up the Microsoft 365 connection first (the wizard, or API settings): email sends through that app registration.' '#B42318'
        return $false
    }
    if (-not (Get-Module Microsoft.Graph.Authentication -ListAvailable)) {
        & $say 'The Microsoft Graph module is not installed. Re-run the installer and try again.' '#B42318'
        return $false
    }
    try { Import-Module Microsoft.Graph.Authentication -ErrorAction Stop } catch {
        & $say "Could not load the Microsoft Graph module: $($_.Exception.Message)" '#B42318'
        return $false
    }
    $ownGraph = $false
    $haveCtx = $null; try { $haveCtx = Get-MgContext } catch { $haveCtx = $null }
    if ($ReuseGraphSession -and $haveCtx) {
        & $say "Using the sign-in from the wizard ($($haveCtx.Account)); no second Microsoft sign-in is needed." '#475467'
    } else {
        Lz27d148e1df
        $esScopes = @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Organization.Read.All','User.Read.All')
        $esConnected = $false
        if (Lzaba5827ae9) {
            & $say 'A MICROSOFT SIGN-IN WINDOW IS ABOUT TO OPEN. It can hide behind other windows - if you do not see it, check the taskbar. Sign in with your Microsoft 365 admin account.' '#B5460F'
            try {
                Lzabb4d5de33 -Action { Connect-MgGraph -Scopes $esScopes -NoWelcome -ErrorAction Stop }
                $esConnected = $true
            } catch {
                & $say "The browser sign-in did not complete ($($_.Exception.Message)). Switching to a CODE sign-in: a small window will show your code, always on top." '#B5460F'
            }
        } else {
            & $say 'Using the code sign-in (the reliable path): a small window will show your code to type at microsoft.com/devicelogin, or on your phone. Sign in with your Microsoft 365 admin account.' '#B5460F'
        }
        if (-not $esConnected) {
            try {
                $at = Lz59f59887fc -ClientId '14d82eec-204b-4c2f-b7e8-296a70dab67e' -Scope ($esScopes -join ' ') -Say $say `
                    -Step 'Sign-in 1 of 2: Microsoft Graph. A second sign-in, for Exchange Online, follows if the sender mailbox needs creating or restricting.' `
                    -Purpose "This sign-in asks your admin account for: Application.ReadWrite.All (add the Mail.Send permission to the app registration), AppRoleAssignment.ReadWrite.All (record admin consent for it), Organization.Read.All (read your verified domains to validate the sender address), User.Read.All (check whether the sender mailbox already exists). Used once, for this setup only - alert emails are sent with the app's certificate, never your account."
                $tokUpn = Lz171e66b17f -Token $at -Claim 'upn'
                if (-not $tokUpn) { $tokUpn = Lz171e66b17f -Token $at -Claim 'preferred_username' }
                if ($tokUpn) { $script:CodeSignInUpn = $tokUpn }
                Connect-MgGraph -AccessToken (ConvertTo-SecureString $at -AsPlainText -Force) -NoWelcome -ErrorAction Stop
            } catch {
                & $say "Sign-in did not complete: $($_.Exception.Message). Nothing was changed." '#B42318'
                return $false
            }
        }
        $ownGraph = $true
    }
    $ok = $false; $senderAddr = ''; $exoConnected = $false; $spObjectId = ''
    try {
        $gsp = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$graphResId'" -ErrorAction Stop)['value'])[0]
        $mailRole = ''
        foreach ($ar in @($gsp['appRoles'])) { if ("$($ar['value'])" -eq 'Mail.Send') { $mailRole = "$($ar['id'])" } }
        if (-not $mailRole) { throw 'Mail.Send was not found in Microsoft Graph''s permission catalogue.' }
        $apps = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$appId'" -ErrorAction Stop)['value'])
        if (-not $apps.Count) { throw "the app registration ($appId) was not found in this tenant. Run the Microsoft 365 wizard first." }
        $app = $apps[0]; $appObj = "$($app['id'])"
        $rra = @(); $graphEntry = $null
        foreach ($e in @($app['requiredResourceAccess'])) { if ("$($e['resourceAppId'])" -eq $graphResId) { $graphEntry = $e } else { $rra += $e } }
        $access = @(); $hasMail = $false
        if ($graphEntry) { foreach ($a in @($graphEntry['resourceAccess'])) { $access += $a; if ("$($a['id'])" -eq $mailRole) { $hasMail = $true } } }
        if (-not $hasMail) {
            $access += @{ id = $mailRole; type = 'Role' }
            $rra += @{ resourceAppId = $graphResId; resourceAccess = $access }
            Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/applications/$appObj" -Body @{ requiredResourceAccess = $rra } -ErrorAction Stop | Out-Null
        }
        $sps = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$appId'" -ErrorAction Stop)['value'])
        $freshSp = $false
        $sp = if ($sps.Count) { $sps[0] } else { $freshSp = $true; Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body @{ appId = $appId } -ErrorAction Stop }
        $spObjectId = "$($sp['id'])"
        if ($freshSp) { & $emailWait 10 'The app''s sign-in identity was just created; letting it settle' }
        $granted = $false
        try {
            foreach ($x in @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spObjectId/appRoleAssignments?`$top=999" -ErrorAction Stop)['value'])) {
                if ("$($x['appRoleId'])" -eq $mailRole) { $granted = $true }
            }
        } catch {}
        if ($granted) {
            & $say 'Mail.Send was already granted and consented (from an earlier setup) - nothing to change there.' '#0E9F6E'
        } else {
            for ($ga = 1; $ga -le 4; $ga++) {
                try {
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spObjectId/appRoleAssignments" -Body @{
                        principalId = $spObjectId; resourceId = "$($gsp['id'])"; appRoleId = $mailRole
                    } -ErrorAction Stop | Out-Null
                    $granted = $true; break
                } catch {
                    $gm = "$($_.Exception.Message) $(try { $_.ErrorDetails.Message } catch { '' })"
                    if ($gm -match 'already exists') { $granted = $true; break }
                    if ($ga -lt 4 -and $gm -match 'BadRequest|Bad Request|NotFound|Not Found') {
                        & $emailWait 15 "Microsoft refused the consent grant (attempt $ga of 4; normal while a new permission propagates)"
                    } else { throw }
                }
            }
            if (-not $granted) { throw 'the Mail.Send consent grant kept being refused; wait a few minutes and click Set up sender again.' }
            & $say 'Mail.Send permission is granted and consented on the app registration.' '#0E9F6E'
        }
        $org = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop
        $doms = @(@($org['value'])[0]['verifiedDomains'])
        $domNames = @($doms | ForEach-Object { "$($_['name'])" })
        if ("$DesiredSender".Trim()) {
            $senderAddr = "$DesiredSender".Trim()
            if ($senderAddr -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw "the sender address '$senderAddr' does not look like an email address. Fix it in the Send from box and try again." }
            $sd = ($senderAddr -split '@')[1]
            if ($domNames -notcontains $sd) { throw "the domain '$sd' is not a verified domain of this tenant (verified: $($domNames -join ', ')). A mailbox can only exist on a verified domain; fix the Send from box and try again." }
            & $say "Sender address (your choice): $senderAddr" '#475467'
        } else {
            $best = @($doms | Where-Object { $_['isDefault'] -and ("$($_['name'])" -notlike '*.onmicrosoft.com') })
            if (-not $best.Count) { $best = @($doms | Where-Object { "$($_['name'])" -notlike '*.onmicrosoft.com' }) }
            if (-not $best.Count) { $best = @($doms) }
            if (-not $best.Count) { throw 'no verified email domain was found on the tenant.' }
            $senderAddr = "liscaragh-migrate@$($best[0]['name'])"
            & $say "Sender address: $senderAddr" '#475467'
        }
        $mailboxExists = $false
        try {
            Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$senderAddr" -ErrorAction Stop | Out-Null
            $mailboxExists = $true
            & $say 'The sender mailbox already exists.' '#0E9F6E'
        } catch { $mailboxExists = $false }
        if (-not $mailboxExists) {
            Lze88ab9acc1
            $exoConnected = $true
            $existing = $null
            try { $existing = Get-Recipient -Identity $senderAddr -ErrorAction Stop } catch { $existing = $null }
            if (-not $existing) {
                $mbName = ($senderAddr -split '@')[0]
                New-Mailbox -Shared -Name $mbName -DisplayName "$mbName (migration alerts)" -PrimarySmtpAddress $senderAddr -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                & $say "Shared mailbox $senderAddr created (no licence needed). Exchange takes a little while to finish provisioning it; waiting for it to become visible..." '#0E9F6E'
                for ($w = 1; $w -le 6; $w++) {
                    try { $null = Get-Recipient -Identity $senderAddr -ErrorAction Stop; break }
                    catch { if ($w -lt 6) { Lz0c28a29f63 -Seconds 10 -Message "Still provisioning (check $w of 6)" } }
                }
            } else {
                & $say 'The sender address already exists in Exchange.' '#0E9F6E'
            }
        }
        try {
            if (-not $exoConnected) {
                Lze88ab9acc1
                $exoConnected = $true
            }
            $scopeName = 'Liscaragh Migration Sender'
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    $exoSp = $null
                    try { $exoSp = Get-ServicePrincipal -Identity $appId -ErrorAction Stop } catch { $exoSp = $null }
                    if (-not $exoSp) { New-ServicePrincipal -AppId $appId -ObjectId $spObjectId -DisplayName $script:WizAppName -ErrorAction Stop | Out-Null }
                    $haveScope = $null
                    try { $haveScope = Get-ManagementScope -Identity $scopeName -ErrorAction Stop } catch { $haveScope = $null }
                    if (-not $haveScope) { New-ManagementScope -Name $scopeName -RecipientRestrictionFilter "PrimarySmtpAddress -eq '$senderAddr'" -ErrorAction Stop | Out-Null }
                    elseif ("$($haveScope.RecipientFilter)" -notlike "*'$senderAddr'*") {
                        Set-ManagementScope -Identity $scopeName -RecipientRestrictionFilter "PrimarySmtpAddress -eq '$senderAddr'" -ErrorAction Stop | Out-Null
                        & $say "The send restriction was re-pointed from the previous sender to $senderAddr." '#0E9F6E'
                    }
                    $haveRa = @()
                    try { $haveRa = @(Get-ManagementRoleAssignment -RoleAssignee $spObjectId -Role 'Application Mail.Send' -ErrorAction Stop) } catch { $haveRa = @() }
                    if (-not $haveRa.Count) { New-ManagementRoleAssignment -App $spObjectId -Role 'Application Mail.Send' -CustomResourceScope $scopeName -ErrorAction Stop | Out-Null }
                    & $say 'Sending is restricted to the sender mailbox only (RBAC for Applications).' '#0E9F6E'
                    break
                } catch {
                    $m2 = "$($_.Exception.Message)"
                    if ($m2 -match 'Enable-OrganizationCustomization' -and $attempt -lt 3) {
                        & $say 'This tenant needs a one-time Exchange setting before custom roles can exist (Enable-OrganizationCustomization; standard on tenants that never customised Exchange).' '#B5460F'
                        Lzb8c7669d2d 'Applying it now. THIS TAKES UP TO TWO MINUTES and the window may look frozen while Microsoft applies it - that is normal, please do not close it.'
                        try { Enable-OrganizationCustomization -ErrorAction Stop } catch { if ("$($_.Exception.Message)" -notmatch 'already') { & $say "Could not apply it: $($_.Exception.Message)" '#B5460F' } }
                        Lz0c28a29f63 -Seconds 30 -Message 'Applied. Letting it take effect, then retrying the restriction'
                    } elseif ($attempt -lt 3) {
                        Lz0c28a29f63 -Seconds 15 -Message 'Retrying the restriction'
                    } else { throw }
                }
            }
        } catch {
            & $say "Could not restrict sending to the one mailbox automatically: $($_.Exception.Message). Email alerts still work; the app can currently send as any mailbox, so consider applying the restriction by hand (steps at https://www.liscaragh.com)." '#B5460F'
        }
        Lz933059a102 -Name 'EmailSender' -Value $senderAddr
        Lz933059a102 -Name 'EmailEnabled' -Value '1'
        & $say "Email sender setup is COMPLETE. Alerts will send from $senderAddr; choose recipients under Settings > Email alerts. Prefer a different address or domain? Type it in the Send from box there and click Set up sender - it creates the mailbox and moves the send restriction over." '#0E9F6E'
        $ok = $true
    } catch {
        $m = "$($_.Exception.Message)"
        $detail = ''; try { $detail = "$($_.ErrorDetails.Message)" } catch {}
        if ($detail) { if ($detail.Length -gt 600) { $detail = $detail.Substring(0, 600) + '...' }; $m = "$m Detail: $detail" }
        & $say "Email sender setup stopped: $m" '#B42318'
        & $say "The manual alternative: an admin creates a shared mailbox (any address), grants the app Mail.Send with admin consent, and you enter that address under Settings > Email alerts. Nothing already set up was undone." '#475467'
        if ($setupLogFile) { & $say "The full setup log is saved at: $setupLogFile" '#475467' }
    } finally {
        if ($ownGraph) { try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
    }
    return $ok
}
function Lz0d05ab3822 {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $win2 = New-Object System.Windows.Window
    Lz2e8ddc8b18 $win2
    $win2.Title = 'Email alerts'; $win2.SizeToContent = 'WidthAndHeight'
    $win2.WindowStartupLocation = 'CenterScreen'; $win2.ResizeMode = 'NoResize'
    try {
        if ($script:SC -and $script:SC.Win -and $script:SC.Win.IsVisible) { $win2.Owner = $script:SC.Win; $win2.WindowStartupLocation = 'CenterOwner' }
        elseif ($win -and $win.IsVisible) { $win2.Owner = $win; $win2.WindowStartupLocation = 'CenterOwner' }
    } catch {}
    $win2.FontFamily = 'Segoe UI'; $win2.FontSize = 13; $win2.Background = 'White'
    $dockE = New-Object System.Windows.Controls.DockPanel; $win2.Content = $dockE
    $hdrE = New-Object System.Windows.Controls.Border; $hdrE.Background = '#0F1115'; $hdrE.Padding = '20,14'
    [System.Windows.Controls.DockPanel]::SetDock($hdrE, 'Top')
    $hsE = New-Object System.Windows.Controls.StackPanel; $hsE.MaxWidth = 560
    $htE = New-Object System.Windows.Controls.TextBlock; $htE.Text = 'Email alerts'; $htE.Foreground = 'White'; $htE.FontSize = 16; $htE.FontWeight = 'SemiBold'
    $hbE = New-Object System.Windows.Controls.TextBlock
    $hbE.Text = 'When a run finishes, an email can be sent with the outcome, the report and the logs, from your own Microsoft 365 tenant, so it works for overnight and scheduled runs. Per computer; a failed email never affects the migration.'
    $hbE.Foreground = '#9BA1AA'; $hbE.TextWrapping = 'Wrap'; $hbE.Margin = '0,4,0,0'
    [void]$hsE.Children.Add($htE); [void]$hsE.Children.Add($hbE); $hdrE.Child = $hsE
    [void]$dockE.Children.Add($hdrE)
    $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.MaxHeight = 760
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '18,14,18,16'; $sv.Content = $root
    [void]$dockE.Children.Add($sv)
    function Lze2613aa8c5 { param($Text) $h = New-Object System.Windows.Controls.TextBlock; $h.Text = $Text; $h.FontWeight = 'Bold'; $h.Margin = '0,12,0,4'; [void]$root.Children.Add($h) }
    function Add-ERow { param($Label, $Control, $Info)
        $g = New-Object System.Windows.Controls.Grid
        foreach ($w in '150','400','40') { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = $w; $g.ColumnDefinitions.Add($c) }
        $l = New-Object System.Windows.Controls.TextBlock; $l.Text = $Label; $l.VerticalAlignment = 'Center'; $l.Margin = '0,3,8,3'; $l.TextWrapping = 'Wrap'
        [System.Windows.Controls.Grid]::SetColumn($l, 0); [void]$g.Children.Add($l)
        [System.Windows.Controls.Grid]::SetColumn($Control, 1); [void]$g.Children.Add($Control)
        if ($Info) {
            $ib = New-Object System.Windows.Controls.Button; $ib.Content = ([char]0xE946); $ib.FontFamily = 'Segoe MDL2 Assets'; $ib.Padding = '0,4'; $ib.Width = 26; $ib.Margin = '4,3,0,3'; $ib.VerticalAlignment = 'Center'; $ib.ToolTip = $Info; $ib.FocusVisualStyle = $null
            $iTxt = $Info; $iLab = $Label
            $ib.Add_Click({ (Show-Msg -Text ($iTxt) -Caption ($iLab)) | Out-Null }.GetNewClosure())
            [System.Windows.Controls.Grid]::SetColumn($ib, 2); [void]$g.Children.Add($ib)
        }
        [void]$root.Children.Add($g); return $Control
    }
    $regOr = { param($n, $d) $v = [string](Get-RegSetting $n); if ($null -eq $v -or $v -eq '') { $d } else { $v } }
    $chkOn = New-Object System.Windows.Controls.CheckBox
    $chkOn.Content = 'Send an email when a run finishes'; $chkOn.Margin = '0,4,0,2'; $chkOn.FontWeight = 'SemiBold'
    $chkOn.IsChecked = ((& $regOr 'EmailEnabled' '0') -eq '1')
    [void]$root.Children.Add($chkOn)
    Lze2613aa8c5 'Sender and recipients'
    $tbFrom = New-Object System.Windows.Controls.TextBox; $tbFrom.Margin = '0,3,0,3'; $tbFrom.Text = [string](Get-RegSetting 'EmailSender')
    [void](Add-ERow -Label 'Send from' -Control $tbFrom -Info 'The mailbox the alerts are sent from, in your own Microsoft 365 tenant. Type ANY address you like (any name, any of your tenant''s verified domains) and click "Set up sender": it creates that shared mailbox if needed (no licence) and points the send restriction at it. Leave it empty for the default, liscaragh-migrate@your-domain. An existing mailbox address also works - but if the send restriction was applied earlier, click "Set up sender" after changing the address, or sending stays locked to the old one.')
    $btnSetupSender = New-Object System.Windows.Controls.Button; $btnSetupSender.Content = 'Set up sender...'; $btnSetupSender.Padding = '8,3'; $btnSetupSender.Margin = '150,2,0,2'; $btnSetupSender.HorizontalAlignment = 'Left'
    [void]$root.Children.Add($btnSetupSender)
    $senderScroll = New-Object System.Windows.Controls.ScrollViewer; $senderScroll.MaxHeight = 160; $senderScroll.VerticalScrollBarVisibility = 'Auto'
    $senderScroll.Margin = '150,2,0,4'; $senderScroll.Visibility = 'Collapsed'
    $senderPanel = New-Object System.Windows.Controls.StackPanel; $senderScroll.Content = $senderPanel
    [void]$root.Children.Add($senderScroll)
    $tbTo = New-Object System.Windows.Controls.TextBox; $tbTo.Margin = '0,3,0,3'
    $tbTo.AcceptsReturn = $true; $tbTo.Height = 58; $tbTo.VerticalScrollBarVisibility = 'Auto'; $tbTo.VerticalContentAlignment = 'Top'
    $tbTo.Text = ((([string](Get-RegSetting 'EmailRecipients')) -split '[;,\r\n]+' | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join [Environment]::NewLine)
    [void](Add-ERow -Label 'Send to' -Control $tbTo -Info 'Who receives the alerts. Put ONE address per line (press Enter for the next one). A pasted list separated with ; or , also works.')
    $toHint = New-Object System.Windows.Controls.TextBlock
    $toHint.Text = 'One address per line. For example:  msp@contoso.com  then  oncall@contoso.com  on the next line.'
    $toHint.Foreground = 'Gray'; $toHint.FontSize = 11; $toHint.Margin = '150,0,0,4'; $toHint.TextWrapping = 'Wrap'
    [void]$root.Children.Add($toHint)
    Lze2613aa8c5 'When to send'
    $outRow = New-Object System.Windows.Controls.StackPanel; $outRow.Orientation = 'Horizontal'
    $chkOk = New-Object System.Windows.Controls.CheckBox; $chkOk.Content = 'Success'; $chkOk.Margin = '0,2,16,2'; $chkOk.IsChecked = ((& $regOr 'EmailOnSuccess' '1') -eq '1')
    $chkWarn = New-Object System.Windows.Controls.CheckBox; $chkWarn.Content = 'Completed with warnings'; $chkWarn.Margin = '0,2,16,2'; $chkWarn.IsChecked = ((& $regOr 'EmailOnWarning' '1') -eq '1')
    $chkBad = New-Object System.Windows.Controls.CheckBox; $chkBad.Content = 'Failure / ended early'; $chkBad.Margin = '0,2,0,2'; $chkBad.IsChecked = ((& $regOr 'EmailOnFailure' '1') -eq '1')
    [void]$outRow.Children.Add($chkOk); [void]$outRow.Children.Add($chkWarn); [void]$outRow.Children.Add($chkBad)
    [void](Add-ERow -Label 'Outcomes' -Control $outRow -Info 'Which results trigger an email. For unattended overnight runs, at least "Failure / ended early" is strongly recommended.')
    $actRow = New-Object System.Windows.Controls.StackPanel; $actRow.Orientation = 'Horizontal'
    $chkFull = New-Object System.Windows.Controls.CheckBox; $chkFull.Content = 'Full upload'; $chkFull.Margin = '0,2,16,2'; $chkFull.IsChecked = ((& $regOr 'EmailOnTransfer' '1') -eq '1')
    $chkSync = New-Object System.Windows.Controls.CheckBox; $chkSync.Content = 'Sync'; $chkSync.Margin = '0,2,16,2'; $chkSync.IsChecked = ((& $regOr 'EmailOnDelta' '1') -eq '1')
    $chkVer = New-Object System.Windows.Controls.CheckBox; $chkVer.Content = 'Verify'; $chkVer.Margin = '0,2,16,2'; $chkVer.IsChecked = ((& $regOr 'EmailOnValidate' '1') -eq '1')
    $chkCmp = New-Object System.Windows.Controls.CheckBox; $chkCmp.Content = 'Compare sizes'; $chkCmp.Margin = '0,2,0,2'; $chkCmp.IsChecked = ((& $regOr 'EmailOnSizeCheck' '1') -eq '1')
    [void]$actRow.Children.Add($chkFull); [void]$actRow.Children.Add($chkSync); [void]$actRow.Children.Add($chkVer); [void]$actRow.Children.Add($chkCmp)
    [void](Add-ERow -Label 'Actions' -Control $actRow -Info 'Which run types trigger an email. Previews never send one (they change nothing).')
    Lze2613aa8c5 'Subject and attachments'
    $tbSubj = New-Object System.Windows.Controls.TextBox; $tbSubj.Margin = '0,3,0,3'
    $tbSubj.Text = (& $regOr 'EmailSubject' 'Liscaragh Migrate - {Action} {Outcome}: {JobName}')
    [void](Add-ERow -Label 'Subject' -Control $tbSubj -Info ('The email subject. These placeholders are filled in from the run: {JobName} {Action} {Outcome} {Source} {Destination} {FilesCopied} {FilesFailed} {Errors} {SizeCopied} {Duration} {StartTime} {EndTime} {Tenant} {Version}. Checks (Verify, Compare sizes) fill the ones that apply to them; the rest are left out.'))
    $lblPrev = New-Object System.Windows.Controls.TextBlock; $lblPrev.TextWrapping = 'Wrap'; $lblPrev.Foreground = 'Gray'; $lblPrev.FontSize = 11; $lblPrev.Margin = '150,0,0,4'
    [void]$root.Children.Add($lblPrev)
    $chkAtt = New-Object System.Windows.Controls.CheckBox
    $chkAtt.Content = 'Attach the report and logs (zipped when large; oversized files are named in the email instead)'
    $chkAtt.Margin = '0,4,0,2'; $chkAtt.IsChecked = ((& $regOr 'EmailAttach' '1') -eq '1')
    [void]$root.Children.Add($chkAtt)
    $btnRow = New-Object System.Windows.Controls.DockPanel; $btnRow.Margin = '0,16,0,0'; $btnRow.LastChildFill = $false
    $rightBtns = New-Object System.Windows.Controls.StackPanel; $rightBtns.Orientation = 'Horizontal'; [System.Windows.Controls.DockPanel]::SetDock($rightBtns, 'Right')
    $btnTest = New-Object System.Windows.Controls.Button; $btnTest.Content = 'Send test email'; $btnTest.Padding = '12,4'; $btnTest.Margin = '0,0,8,0'
    $btnSave = New-Object System.Windows.Controls.Button; $btnSave.Content = 'Save'; $btnSave.Padding = '16,4'; $btnSave.Margin = '0,0,8,0'; $btnSave.IsDefault = $true
    $btnCancel = New-Object System.Windows.Controls.Button; $btnCancel.Content = 'Close'; $btnCancel.Padding = '16,4'; $btnCancel.IsCancel = $true
    [void]$rightBtns.Children.Add($btnTest); [void]$rightBtns.Children.Add($btnSave); [void]$rightBtns.Children.Add($btnCancel)
    [void]$btnRow.Children.Add($rightBtns); [void]$root.Children.Add($btnRow)
    $lblStatus = New-Object System.Windows.Controls.TextBlock; $lblStatus.TextWrapping = 'Wrap'; $lblStatus.Margin = '0,8,0,0'; [void]$root.Children.Add($lblStatus)
    $script:ES = @{
        win2 = $win2; chkOn = $chkOn; tbFrom = $tbFrom; tbTo = $tbTo; senderScroll = $senderScroll; senderPanel = $senderPanel
        chkOk = $chkOk; chkWarn = $chkWarn; chkBad = $chkBad
        chkFull = $chkFull; chkSync = $chkSync; chkVer = $chkVer; chkCmp = $chkCmp
        tbSubj = $tbSubj; lblPrev = $lblPrev; chkAtt = $chkAtt; lblStatus = $lblStatus
    }
    $updatePrev = {
        try { $script:ES.lblPrev.Text = 'Preview:  ' + (Lz3b8c93f3d9 -Template $script:ES.tbSubj.Text -Vars (Lzeeaadffc9c)) } catch {}
    }
    $tbSubj.Add_TextChanged($updatePrev)
    & $updatePrev
    $btnSetupSender.Add_Click({
        try {
            $script:ES.senderPanel.Children.Clear()
            $script:ES.senderScroll.Visibility = 'Visible'
            $retSender = @(Invoke-EmailSenderSetup -DesiredSender ("$($script:ES.tbFrom.Text)".Trim()) -Log { param($t, $c)
                if (-not $script:ES) { return }
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = $t; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,1,0,1'
                $tb.Foreground = if ($c) { $c } else { 'Gray' }
                [void]$script:ES.senderPanel.Children.Add($tb)
                try { $script:ES.senderScroll.ScrollToEnd(); $script:ES.win2.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) } catch {}
            })
            $okSender = ($retSender.Count -gt 0 -and $retSender[-1] -eq $true)
            if ($okSender) {
                $sv2 = [string](Get-RegSetting 'EmailSender'); if ($sv2) { $script:ES.tbFrom.Text = $sv2 }
                if ((Get-RegSetting 'EmailEnabled') -eq '1') { $script:ES.chkOn.IsChecked = $true }
            }
        } catch {
            try {
                $tbE = New-Object System.Windows.Controls.TextBlock
                $tbE.Text = "Sender setup hit a problem: $($_.Exception.Message)"; $tbE.TextWrapping = 'Wrap'; $tbE.Foreground = 'Red'; $tbE.Margin = '0,1,0,1'
                $script:ES.senderScroll.Visibility = 'Visible'; [void]$script:ES.senderPanel.Children.Add($tbE)
            } catch {}
        }
    })
    $btnTest.Add_Click({
        $script:ES.lblStatus.Text = 'Sending a test email...'; $script:ES.lblStatus.Foreground = 'Gray'
        try {
            $from = "$($script:ES.tbFrom.Text)".Trim(); $toRaw = "$($script:ES.tbTo.Text)".Trim()
            if (-not $from -or -not $toRaw) { $script:ES.lblStatus.Text = 'Enter the sender and at least one recipient first.'; $script:ES.lblStatus.Foreground = 'Red'; return }
            $tid = [string](Get-RegSetting 'TenantId'); $app = [string](Get-RegSetting 'GraphClientId'); $th = [string](Get-RegSetting 'CertThumbprint')
            if (-not $tid -or -not $app -or -not $th) { $script:ES.lblStatus.Text = 'Set up the Microsoft 365 connection first (the wizard, or API settings).'; $script:ES.lblStatus.Foreground = 'Red'; return }
            $to = @()
            foreach ($r in ($toRaw -split '[;,\r\n]+')) { $a = "$r".Trim(); if ($a) { $to += @{ emailAddress = @{ address = $a } } } }
            $subj = Lz3b8c93f3d9 -Template ("$($script:ES.tbSubj.Text)") -Vars (Lzeeaadffc9c)
            $tok = Lz1c498583eb -TenantId $tid -ClientId $app -Thumbprint $th
            $body = @{ message = @{ subject = "TEST - $subj"
                        body = @{ contentType = 'Text'; content = 'This is a test email from the Liscaragh Migrate. If you are reading it, email alerts are working. Real alerts include the outcome, the report and the logs.' }
                        toRecipients = $to }
                       saveToSentItems = $true } | ConvertTo-Json -Depth 8
            Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$from/sendMail" -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 60 | Out-Null
            $script:ES.lblStatus.Text = 'Test email sent. Check the recipient inbox (and junk, the first time).'; $script:ES.lblStatus.Foreground = 'Green'
        } catch {
            $script:ES.lblStatus.Text = "Test email failed: $($_.Exception.Message). Usual causes: the sender mailbox does not exist, or Mail.Send is not granted/consented (run 'Set up sender'), or a brand-new permission has not propagated yet (wait a few minutes)."
            $script:ES.lblStatus.Foreground = 'Red'
        }
    })
    $btnSave.Add_Click({
        try {
            $b = { param($c) if ($c.IsChecked) { '1' } else { '0' } }
            Lz933059a102 -Name 'EmailEnabled'    -Value (& $b $script:ES.chkOn)
            Lz933059a102 -Name 'EmailSender'     -Value ("$($script:ES.tbFrom.Text)".Trim())
            Lz933059a102 -Name 'EmailRecipients' -Value ((("$($script:ES.tbTo.Text)" -split '[;,\r\n]+' | ForEach-Object { "$_".Trim() } | Where-Object { $_ })) -join '; ')
            Lz933059a102 -Name 'EmailSubject'    -Value ("$($script:ES.tbSubj.Text)".Trim())
            Lz933059a102 -Name 'EmailOnSuccess'  -Value (& $b $script:ES.chkOk)
            Lz933059a102 -Name 'EmailOnWarning'  -Value (& $b $script:ES.chkWarn)
            Lz933059a102 -Name 'EmailOnFailure'  -Value (& $b $script:ES.chkBad)
            Lz933059a102 -Name 'EmailOnTransfer' -Value (& $b $script:ES.chkFull)
            Lz933059a102 -Name 'EmailOnDelta'    -Value (& $b $script:ES.chkSync)
            Lz933059a102 -Name 'EmailOnValidate' -Value (& $b $script:ES.chkVer)
            Lz933059a102 -Name 'EmailOnSizeCheck'-Value (& $b $script:ES.chkCmp)
            Lz933059a102 -Name 'EmailAttach'     -Value (& $b $script:ES.chkAtt)
            if ($script:ES.chkOn.IsChecked -and (-not "$($script:ES.tbFrom.Text)".Trim() -or -not "$($script:ES.tbTo.Text)".Trim())) {
                (Show-Msg -Text ("Saved, but alerts will not send yet: the sender or recipients are empty.`n`nUse 'Set up sender' to create the sender mailbox, and enter at least one recipient.") -Caption ('Email alerts') -Icon ('Warning')) | Out-Null
            } else {
                (Show-Msg -Text ('Email alert settings saved. They apply to the next run, including scheduled ones.') -Caption ('Saved')) | Out-Null
            }
            $script:ES.win2.Close()
        } catch { (Show-Msg -Text ("Could not save: $($_.Exception.Message)")) }
    })
    [void]$win2.ShowDialog()
    $script:ES = $null
}
function Lz57388fb264 {
    param([switch]$Tenant, [switch]$Exchange, [switch]$Local, [scriptblock]$Log)
    if (-not $Log) { $Log = { } }
    $say = { param($t, $c) try { & $Log $t $c } catch {} }
    $problems = 0
    $regAppId = [string](Get-RegSetting 'GraphClientId')
    $regSender = [string](Get-RegSetting 'EmailSender')
    if ($Tenant) {
        try {
            & $say 'Tenant clean-up: one Microsoft sign-in is needed. Use an admin account.' '#475467'
            $at = Lz59f59887fc -ClientId '14d82eec-204b-4c2f-b7e8-296a70dab67e' -Scope 'Application.ReadWrite.All User.ReadWrite.All Organization.Read.All' -Say $say `
                -Step $(if ($Exchange) { 'Sign-in 1 of 2: Microsoft Graph (the Exchange scrub adds a second).' } else { 'The only sign-in for this removal: Microsoft Graph.' }) `
                -Purpose 'This sign-in asks your admin account for: Application.ReadWrite.All (delete the app registration), User.ReadWrite.All (delete the shared mailbox - liscaragh-migrate@, or an older install''s datto-migration@), Organization.Read.All (read your verified domains to find it). Used once, for this removal only.'
            $hdr = @{ Authorization = "Bearer $at" }
            if (-not $regSender) {
                try {
                    $org = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -Headers $hdr -TimeoutSec 60 -ErrorAction Stop
                    $doms = @(@($org.value)[0].verifiedDomains)
                    $best = @($doms | Where-Object { $_.isDefault -and ("$($_.name)" -notlike '*.onmicrosoft.com') })
                    if (-not $best.Count) { $best = @($doms | Where-Object { "$($_.name)" -notlike '*.onmicrosoft.com' }) }
                    if (-not $best.Count) { $best = @($doms) }
                    if ($best.Count) { $regSender = "liscaragh-migrate@$($best[0].name)" }
                } catch {}
            }
            $apps = @(); $qFail = $false
            if ($regAppId) { try { $apps = @((Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$regAppId'" -Headers $hdr -TimeoutSec 60 -ErrorAction Stop).value) } catch { $qFail = $true } }
            if (-not $apps.Count) {
                $esc = $script:WizAppName -replace "'", "''"
                try { $apps = @((Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$esc'" -Headers $hdr -TimeoutSec 60 -ErrorAction Stop).value); $qFail = $false } catch { $qFail = $true }
            }
            if ($apps.Count) {
                foreach ($a in $apps) {
                    try {
                        Invoke-RestMethod -Method DELETE -Uri "https://graph.microsoft.com/v1.0/applications/$($a.id)" -Headers $hdr -TimeoutSec 60 -ErrorAction Stop | Out-Null
                        & $say "Deleted the app registration ($($a.displayName)). Every computer set up against this tenant is now disconnected." '#0E9F6E'
                    } catch { & $say "Could not delete the app registration: $($_.Exception.Message)" '#B42318'; $problems++ }
                }
            } elseif ($qFail) {
                & $say 'Could not check the tenant for the app registration (sign-in or permission issue). Check Entra > App registrations by hand.' '#B5460F'; $problems++
            } else { & $say 'No app registration found (already clean).' '#475467' }
            $localPart = ''; if ($regSender -and $regSender.Contains('@')) { $localPart = ($regSender -split '@')[0] }
            if (-not $regSender) {
                & $say 'The sender mailbox address is unknown; if a liscaragh-migrate@ (or older datto-migration@) mailbox exists, remove it by hand.' '#B5460F'
            } elseif ($localPart -notmatch '^(liscaragh-?migrate|datto-?migration)$') {
                & $say "The sender ($regSender) is not the tool's own mailbox (liscaragh-migrate@, or an older install's datto-migration@), so it was NOT deleted (it may be a mailbox you chose or already had). Remove it by hand if you want it gone." '#B5460F'
            } else {
                $u = $null; $uq = $false
                foreach ($f in @("mail eq '$regSender'", "userPrincipalName eq '$regSender'")) {
                    if ($u) { break }
                    try { $u = @((Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$f" -Headers $hdr -TimeoutSec 60 -ErrorAction Stop).value)[0] } catch { $uq = $true }
                }
                if ($u -and $u.id) {
                    try {
                        Invoke-RestMethod -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$($u.id)" -Headers $hdr -TimeoutSec 60 -ErrorAction Stop | Out-Null
                        & $say "Deleted the shared mailbox $regSender." '#0E9F6E'
                        try { Invoke-RestMethod -Method DELETE -Uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$($u.id)" -Headers $hdr -TimeoutSec 60 -ErrorAction Stop | Out-Null }
                        catch { & $say 'The mailbox is deleted but still in the recycle bin; the address frees itself within about 30 days, or purge it in Entra > Deleted users.' '#475467' }
                    } catch { & $say "Could not delete the mailbox ${regSender}: $($_.Exception.Message)" '#B42318'; $problems++ }
                } elseif ($uq) {
                    & $say "Could not look up the mailbox $regSender; remove it by hand if it exists." '#B5460F'; $problems++
                } else { & $say "No mailbox $regSender (already clean)." '#475467' }
            }
            if (-not $Exchange) {
                & $say "Left in place (harmless): the 'Liscaragh Migration Sender' send restriction in Exchange. Its app is gone, so it restricts nothing; tick the Exchange option to scrub it too." '#475467'
            }
        } catch { & $say "Tenant clean-up stopped: $($_.Exception.Message)" '#B42318'; $problems++ }
    }
    if ($Exchange) {
        try {
            if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
                & $say 'The Exchange Online module is not installed, so the send-restriction scrub was skipped (its leftovers are harmless).' '#B5460F'
            } else {
                Import-Module ExchangeOnlineManagement -ErrorAction Stop
                $canTok = $false; try { $canTok = (Get-Command Connect-ExchangeOnline).Parameters.ContainsKey('AccessToken') } catch {}
                $exoOrg = "$(Get-RegSetting 'UpnDomain')".TrimStart('@')
                if (-not $exoOrg -and $regSender -and $regSender.Contains('@')) { $exoOrg = ($regSender -split '@')[1] }
                if ($canTok -and $exoOrg) {
                    & $say 'Exchange needs its own sign-in (the second and last one).' '#475467'
                    $exoTok = Lz59f59887fc -ClientId 'fb78d390-0c51-40cd-8e17-fdbfab77341b' -Scope 'https://outlook.office365.com/.default' -Say $say `
                        -Step 'Sign-in 2 of 2: Exchange Online.' `
                        -Purpose 'This sign-in uses your admin account''s existing Exchange access to remove the send restriction (the role assignment, the scope and the Exchange service principal). Nothing else is touched.'
                    Connect-ExchangeOnline -AccessToken $exoTok -Organization $exoOrg -ShowBanner:$false -ErrorAction Stop
                    $scopeName = 'Liscaragh Migration Sender'
                    $ras = @(); try { $ras = @(Get-ManagementRoleAssignment -ErrorAction SilentlyContinue | Where-Object { "$($_.CustomResourceScope)" -eq $scopeName }) } catch {}
                    foreach ($ra in $ras) {
                        try { Remove-ManagementRoleAssignment -Identity $ra.Identity -Confirm:$false -ErrorAction Stop; & $say 'Removed the send role assignment.' '#0E9F6E' }
                        catch { & $say "Could not remove the role assignment: $($_.Exception.Message)" '#B42318'; $problems++ }
                    }
                    try {
                        if (Get-ManagementScope -Identity $scopeName -ErrorAction SilentlyContinue) { Remove-ManagementScope -Identity $scopeName -Confirm:$false -ErrorAction Stop; & $say 'Removed the send restriction scope.' '#0E9F6E' }
                    } catch { & $say "Could not remove the scope: $($_.Exception.Message)" '#B42318'; $problems++ }
                    try {
                        if ($regAppId) {
                            $esp = Get-ServicePrincipal -ErrorAction SilentlyContinue | Where-Object { "$($_.AppId)" -eq $regAppId }
                            if ($esp) { $esp | Remove-ServicePrincipal -Confirm:$false -ErrorAction Stop; & $say 'Removed the Exchange service principal.' '#0E9F6E' }
                        }
                    } catch { & $say "Could not remove the Exchange service principal: $($_.Exception.Message)" '#B42318'; $problems++ }
                } else {
                    & $say 'This Exchange module version cannot take a code sign-in token (or the organisation is unknown), so the send-restriction scrub was skipped. Its leftovers are harmless.' '#B5460F'
                }
            }
        } catch { & $say "Exchange clean-up stopped: $($_.Exception.Message). Its leftovers are harmless." '#B42318'; $problems++ }
    }
    if ($Local) {
        $thumbs = @()
        $t0 = [string](Get-RegSetting 'CertThumbprint'); if ($t0) { $thumbs += $t0.ToUpper() }
        try {
            foreach ($c in @(Get-ChildItem 'Cert:\CurrentUser\My' -ErrorAction Stop)) {
                if ("$($c.Subject)" -like "CN=$($script:WizAppName)*") { $thumbs += "$($c.Thumbprint)".ToUpper() }
            }
        } catch {}
        $nCert = 0
        foreach ($t in @($thumbs | Sort-Object -Unique)) {
            try { $p = "Cert:\CurrentUser\My\$t"; if (Test-Path $p) { Remove-Item $p -Force -ErrorAction Stop; $nCert++ } }
            catch { & $say "Could not remove certificate ${t}: $($_.Exception.Message)" '#B5460F'; $problems++ }
        }
        & $say $(if ($nCert) { "Removed $nCert sign-in certificate(s) from this computer." } else { 'No sign-in certificates found (already clean).' }) '#475467'
        try {
            if (Test-Path $script:RegPath) {
                foreach ($p in @((Get-Item $script:RegPath -ErrorAction Stop).Property)) {
                    try { Remove-ItemProperty -Path $script:RegPath -Name $p -ErrorAction Stop } catch {}
                }
                foreach ($sub in @(Get-ChildItem $script:RegPath -ErrorAction SilentlyContinue)) {
                    if ($sub.PSChildName -ne 'State') { try { Remove-Item $sub.PSPath -Recurse -Force -ErrorAction Stop } catch {} }
                }
                & $say 'Removed the saved settings and secrets from this computer.' '#0E9F6E'
            } else { & $say 'No saved settings found (already clean).' '#475467' }
        } catch { & $say "Could not fully remove the saved settings: $($_.Exception.Message)" '#B42318'; $problems++ }
        try {
            [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $null, 'User')
            [Environment]::SetEnvironmentVariable('DATTO_CLIENT_SECRET', $null, 'Process')
        } catch {}
        & $say "Kept, on purpose: your migration jobs, reports and audit files (under $script:JobsRoot) and any licence file - they are your record of what was migrated. To remove the software itself, close the app and delete the desktop shortcut and the Installer folder under $script:JobsBase - it is not listed in Windows Settings > Apps yet (that arrives with the packaged build)." '#475467'
    }
    return ($problems -eq 0)
}
function Lz4a73e4b0de {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    $win2 = New-Object System.Windows.Window
    Lz2e8ddc8b18 $win2
    $win2.Title = 'Remove set-up (decommission)'; $win2.SizeToContent = 'Height'; $win2.Width = 640
    $win2.WindowStartupLocation = 'CenterScreen'; $win2.ResizeMode = 'NoResize'
    try { if ($win -and $win.IsVisible) { $win2.Owner = $win; $win2.WindowStartupLocation = 'CenterOwner' } } catch {}
    $root = New-Object System.Windows.Controls.StackPanel; $root.Margin = '16'
    $hdr = New-DialogHeader -Title 'Remove set-up (decommission)'
    $dock = New-Object System.Windows.Controls.DockPanel
    [void]$dock.Children.Add($hdr); [void]$dock.Children.Add($root)
    $win2.Content = $dock
    $addBlock = { param($Text, $Colour, $Bold, $Gap)
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $Text; $tb.TextWrapping = 'Wrap'
        $tb.Foreground = $(if ($Colour) { $Colour } else { '#101828' })
        if ($Bold) { $tb.FontWeight = 'SemiBold' }
        $tb.Margin = "0,0,0,$(if ($null -ne $Gap) { $Gap } else { 8 })"
        [void]$root.Children.Add($tb)
    }
    & $addBlock 'Use this when' '#101828' $true 2
    & $addBlock 'The Datto migration is 100% FINISHED and no further migrations from ANY Datto tenant into this Microsoft 365 tenant are expected. The set-up is shared: every computer and every migration job on this tenant uses the same app registration, so removing it disconnects them all at once.' 'Gray' $false 8
    & $addBlock 'What is removed' '#101828' $true 2
    & $addBlock "From the tenant: the app registration ('$($script:WizAppName)'), together with its certificates, its permissions and the admin consent, and the default shared mailbox (liscaragh-migrate@ on your domain, or datto-migration@ if this tenant was set up by an older version). A sender mailbox you chose or created yourself is never deleted. The Exchange send restriction is optional below." 'Gray' $false 4
    & $addBlock 'From this computer: the connection settings, this computer''s sign-in certificate, and the stored secrets (including the Datto credentials).' 'Gray' $false 8
    & $addBlock 'What is kept' '#101828' $true 2
    & $addBlock "Your migration jobs, reports and audit files - they are your record of what was migrated - and your licence file. The software itself is removed by closing the app and deleting the desktop shortcut and the Installer folder under $script:JobsBase (it is not listed in Windows Settings > Apps yet)." 'Gray' $false 10
    & $addBlock 'This cannot be undone. Removing the app registration disconnects EVERY computer set up against this tenant, and email alerts stop.' '#B42318' $true 10
    $chkTenant = New-Object System.Windows.Controls.CheckBox
    $chkTenant.Content = 'Remove from the Microsoft 365 tenant (app registration and the shared mailbox)'
    $chkTenant.IsChecked = $true; $chkTenant.Margin = '0,2,0,2'; [void]$root.Children.Add($chkTenant)
    $chkExo = New-Object System.Windows.Controls.CheckBox
    $chkExo.Content = 'Also scrub the Exchange send restriction (a second sign-in; its leftovers are harmless if skipped)'
    $chkExo.IsChecked = $false; $chkExo.Margin = '0,2,0,2'; [void]$root.Children.Add($chkExo)
    $chkLocal = New-Object System.Windows.Controls.CheckBox
    $chkLocal.Content = 'Remove the set-up saved on this computer (connection settings, certificate, stored secrets)'
    $chkLocal.IsChecked = $true; $chkLocal.Margin = '0,2,0,8'; [void]$root.Children.Add($chkLocal)
    $confRow = New-Object System.Windows.Controls.StackPanel; $confRow.Orientation = 'Horizontal'; $confRow.Margin = '0,4,0,8'
    $confLbl = New-Object System.Windows.Controls.TextBlock; $confLbl.Text = 'Type REMOVE (in capitals) to unlock the button:'; $confLbl.VerticalAlignment = 'Center'; $confLbl.Margin = '0,0,8,0'
    $tbConfirm = New-Object System.Windows.Controls.TextBox; $tbConfirm.Width = 120
    [void]$confRow.Children.Add($confLbl); [void]$confRow.Children.Add($tbConfirm); [void]$root.Children.Add($confRow)
    $logScroll = New-Object System.Windows.Controls.ScrollViewer; $logScroll.MaxHeight = 200; $logScroll.VerticalScrollBarVisibility = 'Auto'
    $logScroll.Margin = '0,0,0,8'; $logScroll.Visibility = 'Collapsed'
    $logPanel = New-Object System.Windows.Controls.StackPanel; $logScroll.Content = $logPanel
    [void]$root.Children.Add($logScroll)
    $btnRow = New-Object System.Windows.Controls.DockPanel; $btnRow.Margin = '0,4,0,0'; $btnRow.LastChildFill = $false
    $rightBtns = New-Object System.Windows.Controls.StackPanel; $rightBtns.Orientation = 'Horizontal'; [System.Windows.Controls.DockPanel]::SetDock($rightBtns, 'Right')
    $btnGo = New-Object System.Windows.Controls.Button; $btnGo.Content = 'Remove'; $btnGo.Padding = '16,4'; $btnGo.Margin = '0,0,8,0'
    $btnGo.IsEnabled = $false; $btnGo.Background = '#B42318'; $btnGo.Foreground = 'White'; $btnGo.FontWeight = 'SemiBold'
    $btnClose = New-Object System.Windows.Controls.Button; $btnClose.Content = 'Close'; $btnClose.Padding = '16,4'; $btnClose.IsCancel = $true
    [void]$rightBtns.Children.Add($btnGo); [void]$rightBtns.Children.Add($btnClose)
    [void]$btnRow.Children.Add($rightBtns); [void]$root.Children.Add($btnRow)
    $script:DX = @{ win2 = $win2; chkTenant = $chkTenant; chkExo = $chkExo; chkLocal = $chkLocal; tbConfirm = $tbConfirm; logPanel = $logPanel; logScroll = $logScroll; btnGo = $btnGo }
    $tbConfirm.Add_TextChanged({
        try { $script:DX.btnGo.IsEnabled = ("$($script:DX.tbConfirm.Text)".Trim() -ceq 'REMOVE') } catch {}
    })
    $btnGo.Add_Click({
        try {
            $sayUi = { param($t, $c)
                if (-not $script:DX) { return }
                $script:DX.logScroll.Visibility = 'Visible'
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = $t; $tb.TextWrapping = 'Wrap'; $tb.Margin = '4,1,4,1'
                $tb.Foreground = if ($c) { $c } else { 'Gray' }
                [void]$script:DX.logPanel.Children.Add($tb)
                try { $script:DX.logScroll.ScrollToEnd(); $script:DX.win2.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background) } catch {}
            }
            if ("$($script:DX.tbConfirm.Text)".Trim() -cne 'REMOVE') { & $sayUi 'Type REMOVE (in capitals) in the confirmation box first.' '#B42318'; return }
            if (-not ($script:DX.chkTenant.IsChecked -or $script:DX.chkLocal.IsChecked -or $script:DX.chkExo.IsChecked)) { & $sayUi 'Tick at least one of the options above.' '#B42318'; return }
            $script:DX.btnGo.IsEnabled = $false
            $okD = Lz57388fb264 -Tenant:([bool]$script:DX.chkTenant.IsChecked) -Exchange:([bool]$script:DX.chkExo.IsChecked) -Local:([bool]$script:DX.chkLocal.IsChecked) -Log $sayUi
            if ($okD) { & $sayUi 'Decommission finished with nothing outstanding.' '#0E9F6E' }
            else { & $sayUi 'Decommission finished, but some steps need a hand-check (the red and amber lines above).' '#B5460F'; $script:DX.btnGo.IsEnabled = $true }
            try { if ($script:SC -and $script:SC.Win -and $script:SC.Win.IsVisible) { Lzc0d02014af } } catch {}
        } catch {
            try {
                $tbE = New-Object System.Windows.Controls.TextBlock
                $tbE.Text = "Decommission hit a problem: $($_.Exception.Message)"; $tbE.TextWrapping = 'Wrap'; $tbE.Foreground = '#B42318'; $tbE.Margin = '4,1,4,1'
                $script:DX.logScroll.Visibility = 'Visible'; [void]$script:DX.logPanel.Children.Add($tbE); $script:DX.btnGo.IsEnabled = $true
            } catch {}
        }
    })
    [void]$win2.ShowDialog()
    $script:DX = $null
}
function Lzb6cc704a5f {
    if ($script:TransferMode -eq 'LocalFs') { return (Lze2b4dac580) }
    return ((Lz955fc24a6f) -and (Lze2b4dac580))
}
Lza5a04ff472
Lze879f9f2d6
$win.Dispatcher.Add_UnhandledException({
    $ev = $args[1]
    try { Add-EngineLine "[app] An unexpected background error was contained (the app carries on): $($ev.Exception.Message)" } catch {}
    $ev.Handled = $true
})
$win.Add_ContentRendered({
    if ($script:OnboardShown) { return }
    $script:OnboardShown = $true
    if ($script:Splash) { try { $script:Splash.Close(); $script:Splash = $null } catch {} }
    if (-not (Lzb6cc704a5f)) {
        try { Lzb52a94c8d8 } catch {}
        if (Lzb6cc704a5f) { Lz5af601c665 'Connection ready. Create a migration with Job > New, or open an existing one.' }
        else { Lz5af601c665 'Finish setup any time: the checklist reappears at startup, and each step is under Settings.' }
    } elseif (-not $script:JobOpen) {
        Lz5af601c665 'Connection ready. Create a migration with Job > New, or open an existing one.'
    }
    if ($ctrl.GettingStarted -and $ctrl.GettingStarted.Visibility -eq 'Visible') {
        try { Lz154ffece7e ([bool](Lzb6cc704a5f)) } catch {}
    }
    if ((Lzb6cc704a5f) -and -not (Test-Path (Lz61a3428c8d))) {
        try { Lzc518af296f } catch {}
    }
    if (-not $script:StartupUpdateChecked) {
        $script:StartupUpdateChecked = $true
        try {
            $script:StartupUpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:StartupUpdateTimer.Interval = [TimeSpan]::FromSeconds(3)
            $script:StartupUpdateTimer.Add_Tick({
                $script:StartupUpdateTimer.Stop()
                try { Invoke-UpdateCheck -Silent } catch {}
            })
            $script:StartupUpdateTimer.Start()
        } catch {}
    }
})
try {
    Add-Type -MemberDefinition '
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList(uint[] lpdwProcessList, uint dwProcessCount);' -Name ConsoleWin -Namespace Liscaragh -ErrorAction Stop
    $buf = New-Object 'uint[]' 4
    $attached = [Liscaragh.ConsoleWin]::GetConsoleProcessList($buf, 4)
    $h = [Liscaragh.ConsoleWin]::GetConsoleWindow()
    if ($attached -le 1 -and $h -ne [System.IntPtr]::Zero) { [void][Liscaragh.ConsoleWin]::ShowWindow($h, 0) }
} catch {}
try {
    $script:ActivateEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\LiscaraghMigrate.Activate')
    $script:ActivateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ActivateTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:ActivateTimer.Add_Tick({
        try {
            if ($script:ActivateEvent.WaitOne(0)) {
                if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
                [void]$win.Activate()
                $win.Topmost = $true; $win.Topmost = $false
            }
        } catch {}
    })
    $script:ActivateTimer.Start()
    $win.Add_Closed({ try { if ($script:ActivateTimer) { $script:ActivateTimer.Stop() } } catch {} })
} catch {}
if ($script:Splash) { $win.Add_ContentRendered({ try { if ($script:Splash) { $script:Splash.Close(); $script:Splash = $null } } catch {} }) }
Lz6e3a01c6dd
$win.Add_Closed({ Lza23537be45 })
[void]$win.ShowDialog()
