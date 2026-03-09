[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$PreSFC,
    [Alias('Source')]
    [string]$RepairSource,
    [switch]$LimitAccess,
    [Alias('Cleanup')]
    [switch]$RunCleanup,
    [Alias('ResetBase')]
    [switch]$RunResetBase,
    [Alias('ReadOnly')]
    [switch]$DryRun,
    [switch]$SelfTest,
    [switch]$RunRepair,
    [string]$ScratchDir,
    [switch]$CleanupMountPoints,
    [Alias('SkipScanHealth')]
    [switch]$Quick,
    [string]$JsonSummary,
    [switch]$SkipRestorePoint,
    [switch]$RequireRestorePoint,
    [string]$RestorePointDescription,
    [switch]$EnableSystemRestoreIfNeeded,
    [switch]$ForceResetBase,
    [switch]$NoPause,
    [switch]$ShowUsage,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$LegacyArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'lib\SystemFilesCheck.Core.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop -WarningAction SilentlyContinue

$script:ExitCodes = Get-SystemFilesCheckExitCodes
$script:ToolVersion = Get-SystemFilesCheckToolVersion
$script:Session = [ordered]@{}
$script:Summary = $null
$script:TranscriptStarted = $false
$script:ScriptFailure = $null
$script:ResultLocked = $false
$script:PreSFC = [bool]$PreSFC
$script:RepairSource = $RepairSource
$script:LimitAccess = [bool]$LimitAccess
$script:RunCleanup = [bool]$RunCleanup
$script:RunResetBase = [bool]$RunResetBase
$script:DryRun = [bool]$DryRun
$script:SelfTest = [bool]$SelfTest
$script:RunRepair = [bool]$RunRepair
$script:ScratchDir = $ScratchDir
$script:CleanupMountPoints = [bool]$CleanupMountPoints
$script:Quick = [bool]$Quick
$script:JsonSummary = $JsonSummary
$script:SkipRestorePoint = [bool]$SkipRestorePoint
$script:RequireRestorePoint = [bool]$RequireRestorePoint
$script:RestorePointDescription = $RestorePointDescription
$script:EnableSystemRestoreIfNeeded = [bool]$EnableSystemRestoreIfNeeded
$script:ForceResetBase = [bool]$ForceResetBase
$script:NoPause = [bool]$NoPause
$script:ShowUsage = [bool]$ShowUsage
$script:LegacyArgs = @($LegacyArgs)

function New-PhaseRecord {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    New-SystemFilesCheckPhaseRecord -Name $Name
}

function New-SummaryObject {
    param(
        [Parameter(Mandatory)]
        [string]$SessionPath,

        [Parameter(Mandatory)]
        [string]$MainLogPath,

        [Parameter(Mandatory)]
        [string]$TranscriptPath
    )

    [ordered]@{
        ScriptName                   = 'SystemFilesCheck.ps1'
        ToolVersion                  = $script:ToolVersion
        MachineName                  = $env:COMPUTERNAME
        UserName                     = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
        SessionPath                  = $SessionPath
        MainLogPath                  = $MainLogPath
        TranscriptPath               = $TranscriptPath
        StartTime                    = (Get-Date)
        EndTime                      = $null
        TotalDuration                = ''
        OverallResultCategory        = 'ScriptError'
        ExitCode                     = $script:ExitCodes.ScriptError
        IsAdministrator              = $false
        PendingRebootBeforeRun       = $null
        PendingRebootAfterRun        = $null
        WindowsUpdateAccessAllowed   = $true
        ResultReason                 = ''
        RepairSourceUsed             = $false
        RepairSource                 = $null
        RepairSourceValidation       = [ordered]@{
            Type              = 'None'
            Exists            = $null
            SyntaxValid       = $true
            MetadataInspected = $false
            MetadataExitCode  = $null
            MetadataStdOut    = $null
            MetadataStdErr    = $null
            ImageMetadata     = $null
            SystemIdentity    = $null
            ComparisonPerformed = $false
            Compatibility     = $null
            Message           = ''
        }
        ScratchDir                   = $null
        InvalidMountPointsDetected   = $null
        NeedsRemountDetected         = $null
        MountedImageCount            = $null
        MountedImages                = @()
        MountedImageStateBeforeCleanup = $null
        MountedImageStateAfterCleanup  = $null
        MountCleanupRequested        = $false
        MountCleanupPerformed        = $false
        RequestedActionFailures      = @()
        RestorePoint                 = [ordered]@{
            Relevant                    = $false
            Attempted                   = $false
            Succeeded                   = $false
            Required                    = $false
            SkippedByPolicy             = $false
            ContinueWithoutRestorePoint = $false
            Outcome                     = 'NotEvaluated'
            GateEvaluated               = $false
            ExecutionContinued          = $true
            AbortedExecution            = $false
            EnableSystemRestoreIfNeeded = $false
            Description                 = $null
            SequenceNumber              = $null
            Message                     = ''
        }
        Modes                        = [ordered]@{
            DryRun             = $false
            Quick              = $false
            PreSFC             = $false
            RunRepair          = $false
            RunCleanup         = $false
            RunResetBase       = $false
            ForceResetBase     = $false
            CleanupMountPoints = $false
            SelfTest           = $false
            SkipRestorePoint   = $false
            RequireRestorePoint = $false
            EnableSystemRestoreIfNeeded = $false
        }
        Environment                  = [ordered]@{
            ProductName    = $null
            DisplayVersion = $null
            ReleaseId      = $null
            CurrentBuild   = $null
            UBR            = $null
            BuildLabEx     = $null
            Architecture   = $null
            OsCaption      = $null
            OsVersion      = $null
            OsBuildDisplay = $null
        }
        SystemIdentity               = $null
        Phases                       = [ordered]@{
            MountedImageInfo      = (New-PhaseRecord -Name 'MountedImageInfo')
            MountedImageInfoAfterCleanup = (New-PhaseRecord -Name 'MountedImageInfoAfterCleanup')
            CleanupMountPoints    = (New-PhaseRecord -Name 'CleanupMountPoints')
            SfcBaseline           = (New-PhaseRecord -Name 'SfcBaseline')
            DismCheckHealth       = (New-PhaseRecord -Name 'DismCheckHealth')
            DismScanHealth        = (New-PhaseRecord -Name 'DismScanHealth')
            DismRestoreHealth     = (New-PhaseRecord -Name 'DismRestoreHealth')
            SfcFinal              = (New-PhaseRecord -Name 'SfcFinal')
            FinalDismCheckHealth  = (New-PhaseRecord -Name 'FinalDismCheckHealth')
            AnalyzeComponentStore = (New-PhaseRecord -Name 'AnalyzeComponentStore')
            StartComponentCleanup = (New-PhaseRecord -Name 'StartComponentCleanup')
            AnalyzeAfterCleanup   = (New-PhaseRecord -Name 'AnalyzeAfterCleanup')
            SelfTest              = (New-PhaseRecord -Name 'SelfTest')
        }
        SfcBaselineResult            = 'NotRun'
        SfcFinalResult               = 'NotRun'
        DismCheckHealthResult        = 'NotRun'
        DismScanHealthResult         = 'NotRun'
        DismRestoreHealthResult      = 'NotRun'
        FinalDismCheckHealthResult   = 'NotRun'
        AnalyzeComponentStore        = [ordered]@{
            ActualSizeOfComponentStore       = $null
            BackupsAndDisabledFeatures       = $null
            CacheAndTemporaryData            = $null
            DateOfLastCleanup                = $null
            NumberOfReclaimablePackages      = $null
            ComponentStoreCleanupRecommended = $null
        }
        CleanupResult                = 'NotRun'
        AnalyzeAfterCleanupComparison = [ordered]@{
            Available         = $false
            ActualSizeBefore  = $null
            ActualSizeAfter   = $null
            ReclaimableBefore = $null
            ReclaimableAfter  = $null
            DateOfLastCleanup = $null
            Summary           = ''
        }
        SessionSrLineCount           = 0
        SessionCannotRepairLineCount = 0
        ManualActionRecommended      = $false
        NextStepRecommendation       = ''
        Warnings                     = @()
        Errors                       = @()
        Notes                        = @()
    }
}

function Write-SessionLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message

    if ($script:Session.MainLogPath) {
        Add-Content -LiteralPath $script:Session.MainLogPath -Value $line -Encoding UTF8
    }

    Write-Host $line
}

function Add-WarningNote {
    param([Parameter(Mandatory)][string]$Message)
    $script:Summary.Warnings = @($script:Summary.Warnings + $Message)
    Write-SessionLog -Level 'WARN' -Message $Message
}

function Add-ErrorNote {
    param([Parameter(Mandatory)][string]$Message)
    $script:Summary.Errors = @($script:Summary.Errors + $Message)
    Write-SessionLog -Level 'ERROR' -Message $Message
}

function Add-InfoNote {
    param([Parameter(Mandatory)][string]$Message)
    $script:Summary.Notes = @($script:Summary.Notes + $Message)
    Write-SessionLog -Level 'INFO' -Message $Message
}

function Show-ToolUsage {
    @'
SystemFilesCheck.ps1

Default behavior:
  Safe read-only diagnostics only. No SFC repair, no RestoreHealth, no cleanup, no ResetBase.

Direct PowerShell usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunRepair -PreSFC
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunRepair -RepairSource 'wim:D:\sources\install.wim:1' -LimitAccess
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunCleanup
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunCleanup -RunResetBase
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -DryRun -Quick
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunRepair -RequireRestorePoint
  powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -SelfTest

Legacy CMD-compatible usage through the wrapper:
  0_SystemFilesCheck.cmd
  0_SystemFilesCheck.cmd /PreSFC /RunRepair
  0_SystemFilesCheck.cmd /Source:wim:D:\sources\install.wim:1 /LimitAccess /RunRepair
  0_SystemFilesCheck.cmd /Cleanup
  0_SystemFilesCheck.cmd /ResetBase /NoPause

Key switches:
  -PreSFC                 Run a baseline SFC /SCANNOW before DISM repair.
  -RepairSource <value>   Folder, wim:path:index, or esd:path:index.
  -LimitAccess            Block Windows Update during RestoreHealth.
  -RunRepair              Run DISM RestoreHealth and then a final SFC.
  -RunCleanup             Run DISM StartComponentCleanup.
  -RunResetBase           Add /ResetBase to cleanup. Requires explicit confirmation unless -ForceResetBase is used.
  -DryRun                 Explicitly request safe read-only behavior.
  -Quick                  Skip ScanHealth to shorten read-only runs.
  -ScratchDir <path>      Use a specific scratch directory for DISM.
  -CleanupMountPoints     Run DISM /Cleanup-MountPoints explicitly.
  -JsonSummary <path>     Copy Summary.json to an additional path.
  -SkipRestorePoint       Do not attempt a restore point before destructive phases.
  -RequireRestorePoint    Abort destructive work if a restore point cannot be created.
  -RestorePointDescription <text>  Use a custom restore point description.
  -EnableSystemRestoreIfNeeded     Try to enable System Restore explicitly before creating a restore point.
  -SelfTest               Run parser and helper self-tests only.
  -NoPause                Do not pause before exit.

Exit codes:
  0   Healthy
  10  Repaired
  11  Repaired but reboot recommended
  20  Corruption remains
  21  Non-repairable
  22  Requested action failed
  30  Invalid input or validation failure
  31  Preflight failed
  40  Internal script/runtime error
'@ | Write-Host
}

function Merge-LegacyArguments {
    param([string[]]$Arguments)

    foreach ($argument in ($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        switch -Regex ($argument) {
            '^(?i)/\?$' { $script:ShowUsage = $true; continue }
            '^(?i)/help$' { $script:ShowUsage = $true; continue }
            '^(?i)/presfc$' { $script:PreSFC = $true; continue }
            '^(?i)/limitaccess$' { $script:LimitAccess = $true; continue }
            '^(?i)/cleanup$' { $script:RunCleanup = $true; continue }
            '^(?i)/runcleanup$' { $script:RunCleanup = $true; continue }
            '^(?i)/resetbase$' { $script:RunResetBase = $true; $script:RunCleanup = $true; continue }
            '^(?i)/runresetbase$' { $script:RunResetBase = $true; $script:RunCleanup = $true; continue }
            '^(?i)/runrepair$' { $script:RunRepair = $true; continue }
            '^(?i)/(dryrun|readonly)$' { $script:DryRun = $true; continue }
            '^(?i)/selftest$' { $script:SelfTest = $true; continue }
            '^(?i)/cleanupmountpoints$' { $script:CleanupMountPoints = $true; continue }
            '^(?i)/(quick|skipscanhealth)$' { $script:Quick = $true; continue }
            '^(?i)/skiprestorepoint$' { $script:SkipRestorePoint = $true; continue }
            '^(?i)/requirerestorepoint$' { $script:RequireRestorePoint = $true; continue }
            '^(?i)/enablesystemrestoreifneeded$' { $script:EnableSystemRestoreIfNeeded = $true; continue }
            '^(?i)/forceresetbase$' { $script:ForceResetBase = $true; continue }
            '^(?i)/nopause$' { $script:NoPause = $true; continue }
            '^(?i)/source:(.+)$' { $script:RepairSource = $Matches[1].Trim('"'); continue }
            '^(?i)/scratchdir:(.+)$' { $script:ScratchDir = $Matches[1].Trim('"'); continue }
            '^(?i)/jsonsummary:(.+)$' { $script:JsonSummary = $Matches[1].Trim('"'); continue }
            '^(?i)/restorepointdescription:(.+)$' { $script:RestorePointDescription = $Matches[1].Trim('"'); continue }
            default {
                throw [System.ArgumentException]::new('Unknown argument: {0}' -f $argument)
            }
        }
    }
}

function Initialize-Session {
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $sessionRoot = 'C:\SystemRepairLogs'
    $sessionPath = Join-Path -Path $sessionRoot -ChildPath $timestamp

    $counter = 0
    while (Test-Path -LiteralPath $sessionPath) {
        $counter++
        $sessionPath = Join-Path -Path $sessionRoot -ChildPath ('{0}_{1:00}' -f $timestamp, $counter)
    }

    try {
        New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
    }
    catch {
        $fallbackRoot = Join-Path -Path $env:TEMP -ChildPath 'SystemRepairLogs'
        $sessionPath = Join-Path -Path $fallbackRoot -ChildPath $timestamp
        $counter = 0
        while (Test-Path -LiteralPath $sessionPath) {
            $counter++
            $sessionPath = Join-Path -Path $fallbackRoot -ChildPath ('{0}_{1:00}' -f $timestamp, $counter)
        }
        New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
    }

    $phasePath = Join-Path -Path $sessionPath -ChildPath 'Phases'
    $copiedLogPath = Join-Path -Path $sessionPath -ChildPath 'CopiedLogs'
    New-Item -ItemType Directory -Path $phasePath -Force | Out-Null
    New-Item -ItemType Directory -Path $copiedLogPath -Force | Out-Null

    $script:Session = [ordered]@{
        Timestamp      = $timestamp
        SessionPath    = $sessionPath
        PhasePath      = $phasePath
        CopiedLogPath  = $copiedLogPath
        MainLogPath    = (Join-Path -Path $sessionPath -ChildPath 'Main.log')
        TranscriptPath = (Join-Path -Path $sessionPath -ChildPath 'Transcript.txt')
        SummaryText    = (Join-Path -Path $sessionPath -ChildPath 'Summary.txt')
        SummaryJson    = (Join-Path -Path $sessionPath -ChildPath 'Summary.json')
        AllSrPath      = (Join-Path -Path $sessionPath -ChildPath 'SfcDetails_AllSR.txt')
        SessionSrPath  = (Join-Path -Path $sessionPath -ChildPath 'SfcDetails_SessionSR.txt')
        SourceInfoPath = (Join-Path -Path $sessionPath -ChildPath 'RepairSource_Metadata.txt')
    }

    '' | Set-Content -LiteralPath $script:Session.MainLogPath -Encoding UTF8
    $script:Summary = New-SummaryObject -SessionPath $sessionPath -MainLogPath $script:Session.MainLogPath -TranscriptPath $script:Session.TranscriptPath
    $script:Summary.Modes.DryRun = [bool]$script:DryRun
    $script:Summary.Modes.Quick = [bool]$script:Quick
    $script:Summary.Modes.PreSFC = [bool]$script:PreSFC
    $script:Summary.Modes.RunRepair = [bool]$script:RunRepair
    $script:Summary.Modes.RunCleanup = [bool]$script:RunCleanup
    $script:Summary.Modes.RunResetBase = [bool]$script:RunResetBase
    $script:Summary.Modes.ForceResetBase = [bool]$script:ForceResetBase
    $script:Summary.Modes.CleanupMountPoints = [bool]$script:CleanupMountPoints
    $script:Summary.Modes.SelfTest = [bool]$script:SelfTest
    $script:Summary.MountCleanupRequested = [bool]$script:CleanupMountPoints

    Start-Transcript -LiteralPath $script:Session.TranscriptPath -Force | Out-Null
    $script:TranscriptStarted = $true

    Write-SessionLog -Message ('Session directory: {0}' -f $script:Session.SessionPath)
}

function Update-SummaryModes {
    if (-not $script:Summary) {
        return
    }

    $script:Summary.Modes.DryRun = [bool]$script:DryRun
    $script:Summary.Modes.Quick = [bool]$script:Quick
    $script:Summary.Modes.PreSFC = [bool]$script:PreSFC
    $script:Summary.Modes.RunRepair = [bool]$script:RunRepair
    $script:Summary.Modes.RunCleanup = [bool]$script:RunCleanup
    $script:Summary.Modes.RunResetBase = [bool]$script:RunResetBase
    $script:Summary.Modes.ForceResetBase = [bool]$script:ForceResetBase
    $script:Summary.Modes.CleanupMountPoints = [bool]$script:CleanupMountPoints
    $script:Summary.Modes.SelfTest = [bool]$script:SelfTest
    $script:Summary.Modes.SkipRestorePoint = [bool]$script:SkipRestorePoint
    $script:Summary.Modes.RequireRestorePoint = [bool]$script:RequireRestorePoint
    $script:Summary.Modes.EnableSystemRestoreIfNeeded = [bool]$script:EnableSystemRestoreIfNeeded
    $script:Summary.MountCleanupRequested = [bool]$script:CleanupMountPoints
    $script:Summary.RestorePoint.Required = [bool]$script:RequireRestorePoint
    $script:Summary.RestorePoint.SkippedByPolicy = [bool]$script:SkipRestorePoint
    $script:Summary.RestorePoint.EnableSystemRestoreIfNeeded = [bool]$script:EnableSystemRestoreIfNeeded
    if ($script:RestorePointDescription) {
        $script:Summary.RestorePoint.Description = $script:RestorePointDescription
    }
}

function Update-RestorePointSummaryState {
    if (-not $script:Summary) {
        return
    }

    $resolved = Resolve-SystemFilesCheckRestorePointSummary -Relevant ([bool]$script:Summary.RestorePoint.Relevant) -Attempted ([bool]$script:Summary.RestorePoint.Attempted) -Succeeded ([bool]$script:Summary.RestorePoint.Succeeded) -Required ([bool]$script:Summary.RestorePoint.Required) -SkippedByPolicy ([bool]$script:Summary.RestorePoint.SkippedByPolicy) -AbortedExecution ([bool]$script:Summary.RestorePoint.AbortedExecution)
    $script:Summary.RestorePoint.Outcome = $resolved.Outcome
    $script:Summary.RestorePoint.ContinueWithoutRestorePoint = $resolved.ContinueWithoutRestorePoint
    $script:Summary.RestorePoint.ExecutionContinued = $resolved.ExecutionContinued
}

function Format-NullableSummaryValue {
    param(
        [AllowNull()]$Value,
        [string]$NullText = 'Unknown'
    )

    if ($null -eq $Value) {
        return $NullText
    }

    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
        return $NullText
    }

    return [string]$Value
}

function Populate-EnvironmentSummary {
    if (-not $script:Summary) {
        return
    }

    if (-not $script:Summary.Environment.OsBuildDisplay) {
        $osInfo = Get-OperatingSystemInfo
        $script:Summary.Environment = $osInfo
        Add-InfoNote -Message ('OS detected: {0}' -f $osInfo.OsBuildDisplay)
    }

    if ($null -eq $script:Summary.PendingRebootBeforeRun) {
        $script:Summary.PendingRebootBeforeRun = Get-PendingRebootState
        Add-InfoNote -Message ('Pending reboot before run: {0}' -f $script:Summary.PendingRebootBeforeRun)
    }

    if (-not $script:Summary.SystemIdentity) {
        $script:Summary.SystemIdentity = Get-DetailedSystemIdentity
    }
}

function Test-DestructivePhaseRequested {
    [bool]($script:RunRepair -or $script:RunCleanup -or $script:RunResetBase -or $script:CleanupMountPoints)
}

function Get-LatestRestorePoint {
    try {
        Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending | Select-Object -First 1
    }
    catch {
        $null
    }
}

function Ensure-GuardedRestorePoint {
    $script:Summary.RestorePoint.Relevant = Test-DestructivePhaseRequested
    $script:Summary.RestorePoint.GateEvaluated = $true
    if (-not $script:Summary.RestorePoint.Relevant) {
        $script:Summary.RestorePoint.Message = 'No destructive phases were requested.'
        Update-RestorePointSummaryState
        return
    }

    if ($script:SkipRestorePoint -and $script:RequireRestorePoint) {
        throw [System.ArgumentException]::new('SkipRestorePoint cannot be combined with RequireRestorePoint.')
    }

    if (-not $script:RestorePointDescription) {
        $script:RestorePointDescription = 'SystemFilesCheck {0}' -f $script:ToolVersion
    }
    $script:Summary.RestorePoint.Description = $script:RestorePointDescription

    if ($script:SkipRestorePoint) {
        $script:Summary.RestorePoint.SkippedByPolicy = $true
        $script:Summary.RestorePoint.Message = 'Restore point creation was skipped by explicit request.'
        Update-RestorePointSummaryState
        Add-WarningNote -Message $script:Summary.RestorePoint.Message
        return
    }

    $systemDrive = if ($env:SystemDrive.EndsWith('\')) { $env:SystemDrive } else { '{0}\' -f $env:SystemDrive }
    $script:Summary.RestorePoint.Attempted = $true

    if ($script:EnableSystemRestoreIfNeeded) {
        try {
            Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop
            Add-InfoNote -Message ('System Restore was enabled for {0} before restore-point creation.' -f $systemDrive)
        }
        catch {
            Add-WarningNote -Message ('Enable-ComputerRestore failed for {0}: {1}' -f $systemDrive, $_.Exception.Message)
        }
    }

    $before = Get-LatestRestorePoint
    try {
        Checkpoint-Computer -Description $script:RestorePointDescription -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 3
        $after = Get-LatestRestorePoint
        $script:Summary.RestorePoint.Succeeded = $true
        if ($after -and ($null -eq $before -or $after.SequenceNumber -ne $before.SequenceNumber)) {
            $script:Summary.RestorePoint.SequenceNumber = $after.SequenceNumber
        }
        $script:Summary.RestorePoint.Message = 'Restore point creation succeeded.'
        $script:Summary.RestorePoint.AbortedExecution = $false
        Update-RestorePointSummaryState
        Add-InfoNote -Message $script:Summary.RestorePoint.Message
    }
    catch {
        $script:Summary.RestorePoint.Succeeded = $false
        $script:Summary.RestorePoint.Message = $_.Exception.Message
        if ($script:RequireRestorePoint) {
            $script:Summary.RestorePoint.AbortedExecution = $true
            Update-RestorePointSummaryState
            Add-ErrorNote -Message ('Restore point creation failed and execution cannot continue: {0}' -f $_.Exception.Message)
            throw [System.UnauthorizedAccessException]::new('Restore point creation failed and a restore point was required.')
        }

        $script:Summary.RestorePoint.AbortedExecution = $false
        Update-RestorePointSummaryState
        Add-WarningNote -Message ('Restore point creation failed. Continuing because RequireRestorePoint was not set. Reason: {0}' -f $_.Exception.Message)
    }
}

function Stop-SessionTranscript {
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            Write-Verbose 'Stop-Transcript did not complete cleanly.'
        }
        $script:TranscriptStarted = $false
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OperatingSystemInfo {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $displayVersion = [string]$currentVersion.DisplayVersion
    if (-not $displayVersion) {
        $displayVersion = [string]$currentVersion.ReleaseId
    }

    [ordered]@{
        ProductName    = [string]$currentVersion.ProductName
        DisplayVersion = [string]$currentVersion.DisplayVersion
        ReleaseId      = [string]$currentVersion.ReleaseId
        CurrentBuild   = [string]$currentVersion.CurrentBuild
        UBR            = [string]$currentVersion.UBR
        BuildLabEx     = [string]$currentVersion.BuildLabEx
        Architecture   = [string]$os.OSArchitecture
        OsCaption      = [string]$os.Caption
        OsVersion      = [string]$os.Version
        OsBuildDisplay = ('{0} {1} build {2}.{3}' -f $currentVersion.ProductName, $displayVersion, $currentVersion.CurrentBuild, $currentVersion.UBR).Trim()
    }
}

function Get-OnlineIntlSnapshot {
    $output = & dism.exe /Online /Get-Intl /English 2>&1
    $exitCode = $LASTEXITCODE

    $installedLanguages = New-Object System.Collections.Generic.List[string]
    $captureInstalledLanguages = $false
    $defaultSystemUiLanguage = $null
    $systemLocale = $null

    foreach ($line in @($output)) {
        $text = [string]$line
        if ($text -match '^\s*Default system UI language\s*:\s*(?<Value>[^\r\n]+?)\s*$') {
            $defaultSystemUiLanguage = $Matches['Value'].Trim()
            continue
        }

        if ($text -match '^\s*System locale\s*:\s*(?<Value>[^\r\n]+?)\s*$') {
            $systemLocale = $Matches['Value'].Trim()
            continue
        }

        if ($text -match '^\s*Installed language\(s\)\s*:\s*$') {
            $captureInstalledLanguages = $true
            continue
        }

        if ($captureInstalledLanguages) {
            if ($text -match '^\s*(?<Language>[a-z]{2}-[A-Z]{2})\s*$') {
                $language = $Matches['Language']
                if (-not $installedLanguages.Contains($language)) {
                    $installedLanguages.Add($language) | Out-Null
                }

                continue
            }

            if ($text -match '^\s*[A-Za-z].*:\s*$' -or $text -match '^\s*Input locale\s*:') {
                $captureInstalledLanguages = $false
            }
        }
    }

    [ordered]@{
        QuerySucceeded          = $exitCode -eq 0
        ExitCode                = $exitCode
        DefaultSystemUiLanguage = $defaultSystemUiLanguage
        SystemLocale            = $systemLocale
        InstalledLanguages      = @($installedLanguages)
        RawOutput               = @($output | ForEach-Object { [string]$_ })
    }
}

function Get-DetailedSystemIdentity {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $nlsLanguage = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $uiCulture = Get-UICulture
    $systemLocale = Get-WinSystemLocale
    $intlSnapshot = Get-OnlineIntlSnapshot
    $languagePackages = @(Get-WindowsPackage -Online | Where-Object { $_.PackageName -match 'Client-LanguagePack-Package' } | ForEach-Object {
            if ($_.PackageName -match '~(?<Language>[a-z]{2}-[A-Z]{2})~') {
                $Matches['Language']
            }
        } | Sort-Object -Unique)
    $enablementPackageDetected = @((Get-WindowsPackage -Online | Where-Object { $_.PackageName -match 'KB5015684' })).Count -gt 0
    $defaultSystemUiLanguage = if ($intlSnapshot.QuerySucceeded -and $intlSnapshot.DefaultSystemUiLanguage) { [string]$intlSnapshot.DefaultSystemUiLanguage } else { [string]$uiCulture.Name }
    $resolvedSystemLocale = if ($intlSnapshot.QuerySucceeded -and $intlSnapshot.SystemLocale) { [string]$intlSnapshot.SystemLocale } else { [string]$systemLocale.Name }
    $installedLanguages = if ($intlSnapshot.QuerySucceeded -and @($intlSnapshot.InstalledLanguages).Count -gt 0) {
        @($intlSnapshot.InstalledLanguages)
    }
    else {
        @($os.MUILanguages)
    }

    [ordered]@{
        ProductName             = [string]$currentVersion.ProductName
        EditionId               = [string]$currentVersion.EditionID
        InstallationType        = [string]$currentVersion.InstallationType
        DisplayVersion          = [string]$currentVersion.DisplayVersion
        ReleaseId               = [string]$currentVersion.ReleaseId
        CurrentBuild            = [string]$currentVersion.CurrentBuild
        UBR                     = [string]$currentVersion.UBR
        BuildLabEx              = [string]$currentVersion.BuildLabEx
        Version                 = [string]$os.Version
        Architecture            = (Convert-SystemFilesCheckArchitectureValue -Value $os.OSArchitecture)
        SystemType              = [string]$env:PROCESSOR_ARCHITECTURE
        InstallLanguage         = [string]$nlsLanguage.InstallLanguage
        InstallLanguageFallback = [string]$nlsLanguage.InstallLanguageFallback
        DefaultSystemUiLanguage = $defaultSystemUiLanguage
        SystemLocale            = $resolvedSystemLocale
        MUILanguages            = @($installedLanguages)
        InstalledLanguagePacks  = @($languagePackages)
        EnablementPackageDetected = $enablementPackageDetected
        BuildFamily             = Resolve-SystemFilesCheckBuildFamily -CurrentBuild ([string]$currentVersion.CurrentBuild) -BuildLabEx ([string]$currentVersion.BuildLabEx) -Version ([string]$os.Version)
    }
}

function Get-PendingRebootState {
    $checks = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    $pending = $false
    foreach ($check in $checks) {
        if (Test-Path -LiteralPath $check) {
            $pending = $true
            break
        }
    }

    if (-not $pending) {
        try {
            $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop
            if ($sessionManager.PendingFileRenameOperations) {
                $pending = $true
            }
        }
        catch {
            Write-Verbose 'PendingFileRenameOperations was not present.'
        }
    }

    $pending
}

function ConvertTo-QuotedArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0

    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }

        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }

    [void]$builder.Append('"')
    $builder.ToString()
}

function Join-CommandArguments {
    param([string[]]$Arguments)
    (($Arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' ')
}

function Get-PhaseFileMap {
    param([Parameter(Mandatory)][string]$Name)

    $safeName = $Name -replace '[^A-Za-z0-9_-]', '_'
    [ordered]@{
        StdOutPath  = Join-Path -Path $script:Session.PhasePath -ChildPath ('{0}.stdout.txt' -f $safeName)
        StdErrPath  = Join-Path -Path $script:Session.PhasePath -ChildPath ('{0}.stderr.txt' -f $safeName)
        DismLogPath = Join-Path -Path $script:Session.PhasePath -ChildPath ('{0}.dism.log' -f $safeName)
    }
}

function Invoke-ExternalPhase {
    param(
        [Parameter(Mandatory)][string]$PhaseName,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][System.Collections.IDictionary]$PhaseRecord,
        [string]$WorkingDirectory = $PWD.Path
    )

    $files = Get-PhaseFileMap -Name $PhaseName
    $phaseStart = Get-Date
    $argumentString = Join-CommandArguments -Arguments $Arguments

    $PhaseRecord.Executed = $true
    $PhaseRecord.StartTime = $phaseStart
    $PhaseRecord.StdOutPath = $files.StdOutPath
    $PhaseRecord.StdErrPath = $files.StdErrPath
    if ($FilePath -match '(?i)dism(\.exe)?$') {
        $PhaseRecord.DismLogPath = $files.DismLogPath
    }

    Write-SessionLog -Message ('Running {0}: {1} {2}' -f $PhaseName, $FilePath, $argumentString)
    $process = Start-Process -FilePath $FilePath -ArgumentList $argumentString -RedirectStandardOutput $files.StdOutPath -RedirectStandardError $files.StdErrPath -Wait -PassThru -WorkingDirectory $WorkingDirectory -WindowStyle Hidden

    $phaseEnd = Get-Date
    $duration = $phaseEnd - $phaseStart
    $PhaseRecord.EndTime = $phaseEnd
    $PhaseRecord.Duration = [string]$duration
    $PhaseRecord.ExitCode = [int]$process.ExitCode

    $stdout = ''
    $stderr = ''
    if (Test-Path -LiteralPath $files.StdOutPath) {
        $stdout = Get-Content -LiteralPath $files.StdOutPath -Raw -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $files.StdErrPath) {
        $stderr = Get-Content -LiteralPath $files.StdErrPath -Raw -ErrorAction SilentlyContinue
    }

    Add-Content -LiteralPath $script:Session.MainLogPath -Encoding UTF8 -Value @(
        '',
        '==============================================================================',
        ('Phase      : {0}' -f $PhaseName),
        ('Command    : {0} {1}' -f $FilePath, $argumentString),
        ('ExitCode   : {0}' -f $process.ExitCode),
        ('Started    : {0}' -f $phaseStart.ToString('yyyy-MM-dd HH:mm:ss')),
        ('Ended      : {0}' -f $phaseEnd.ToString('yyyy-MM-dd HH:mm:ss')),
        ('Duration   : {0}' -f $duration),
        ('StdOutPath : {0}' -f $files.StdOutPath),
        ('StdErrPath : {0}' -f $files.StdErrPath),
        '------------------------------------------------------------------------------',
        'STDOUT:',
        $stdout,
        '------------------------------------------------------------------------------',
        'STDERR:',
        $stderr,
        '=============================================================================='
    )

    [pscustomobject]@{
        ExitCode    = [int]$process.ExitCode
        StdOut      = $stdout
        StdErr      = $stderr
        StdOutPath  = $files.StdOutPath
        StdErrPath  = $files.StdErrPath
        DismLogPath = $files.DismLogPath
        StartTime   = $phaseStart
        EndTime     = $phaseEnd
        Duration    = $duration
        CommandLine = ('{0} {1}' -f $FilePath, $argumentString)
    }
}

function Invoke-DismPhase {
    param(
        [Parameter(Mandatory)][string]$PhaseName,
        [Parameter(Mandatory)][string[]]$CoreArguments,
        [Parameter(Mandatory)][System.Collections.IDictionary]$PhaseRecord
    )

    $files = Get-PhaseFileMap -Name $PhaseName
    $arguments = @($CoreArguments + '/English' + '/LogLevel:4' + ('/LogPath:{0}' -f $files.DismLogPath))
    if ($script:Summary.ScratchDir) {
        $arguments += ('/ScratchDir:{0}' -f $script:Summary.ScratchDir)
    }

    $result = Invoke-ExternalPhase -PhaseName $PhaseName -FilePath 'dism.exe' -Arguments $arguments -PhaseRecord $PhaseRecord
    $result | Add-Member -NotePropertyName DismLogPath -NotePropertyValue $files.DismLogPath -Force
    $result
}

function Invoke-SfcPhase {
    param(
        [Parameter(Mandatory)][string]$PhaseName,
        [Parameter(Mandatory)][System.Collections.IDictionary]$PhaseRecord
    )

    Invoke-ExternalPhase -PhaseName $PhaseName -FilePath 'sfc.exe' -Arguments @('/SCANNOW') -PhaseRecord $PhaseRecord
}

function Parse-RepairSourceSpec {
    param([string]$Value)
    Parse-SystemFilesCheckRepairSourceSpec -Value $Value
}

function Get-RepairSourceImageMetadata {
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index
    )

    $image = Get-WindowsImage -ImagePath $ImagePath -Index $Index -ErrorAction Stop
    $versionParts = @([string]$image.Version -split '\.')
    $currentBuild = if ($versionParts.Count -ge 3) { $versionParts[2] } else { [string]$image.Version }
    $servicePackBuild = if ($image.PSObject.Properties['ServicePackBuild']) { [string]$image.ServicePackBuild } else { $null }
    if ([string]::IsNullOrWhiteSpace($servicePackBuild) -and $image.PSObject.Properties['SPBuild']) {
        $servicePackBuild = [string]$image.SPBuild
    }
    $servicePackLevel = if ($image.PSObject.Properties['ServicePackLevel']) { [string]$image.ServicePackLevel } else { $null }
    if ([string]::IsNullOrWhiteSpace($servicePackLevel) -and $image.PSObject.Properties['SPLevel']) {
        $servicePackLevel = [string]$image.SPLevel
    }

    [ordered]@{
        ImagePath         = $ImagePath
        ImageIndex        = $Index
        ImageName         = [string]$image.ImageName
        ImageDescription  = [string]$image.ImageDescription
        EditionId         = [string]$image.EditionId
        InstallationType  = [string]$image.InstallationType
        Architecture      = (Convert-SystemFilesCheckArchitectureValue -Value $image.Architecture)
        Languages         = @($image.Languages)
        Version           = [string]$image.Version
        CurrentBuild      = [string]$currentBuild
        ServicePackBuild  = $servicePackBuild
        ServicePackLevel  = $servicePackLevel
        CreatedTime       = [string]$image.CreatedTime
        ModifiedTime      = [string]$image.ModifiedTime
        BuildFamily       = Resolve-SystemFilesCheckBuildFamily -CurrentBuild ([string]$currentBuild) -BuildLabEx $null -Version ([string]$image.Version)
    }
}

function Validate-RepairSource {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parsed = Parse-RepairSourceSpec -Value $Value
    if (-not $parsed) {
        throw [System.ArgumentException]::new('Repair source is empty.')
    }

    $validation = [ordered]@{
        Type              = $parsed.Type
        Exists            = $false
        SyntaxValid       = $true
        MetadataInspected = $false
        MetadataExitCode  = $null
        MetadataStdOut    = $null
        MetadataStdErr    = $null
        ImageMetadata     = $null
        SystemIdentity    = $null
        ComparisonPerformed = $false
        Compatibility     = $null
        Message           = ''
        CanonicalSource   = $null
    }

    switch ($parsed.Type) {
        'folder' {
            if (-not (Test-Path -LiteralPath $parsed.Path -PathType Container)) {
                throw [System.ArgumentException]::new('Repair source folder does not exist: {0}' -f $parsed.Path)
            }
            $validation.Exists = $true
            $validation.Message = 'Folder source exists. Deep compatibility validation is limited for generic folder sources.'
            $validation.CanonicalSource = (Resolve-Path -LiteralPath $parsed.Path).Path
        }
        'wim' {
            if (-not (Test-Path -LiteralPath $parsed.Path -PathType Leaf)) {
                throw [System.ArgumentException]::new('WIM repair source does not exist: {0}' -f $parsed.Path)
            }
            if ($parsed.Index -lt 1) {
                throw [System.ArgumentException]::new('WIM source index must be greater than zero.')
            }
            $validation.Exists = $true
            $validation.CanonicalSource = ('wim:{0}:{1}' -f (Resolve-Path -LiteralPath $parsed.Path).Path, $parsed.Index)
        }
        'esd' {
            if (-not (Test-Path -LiteralPath $parsed.Path -PathType Leaf)) {
                throw [System.ArgumentException]::new('ESD repair source does not exist: {0}' -f $parsed.Path)
            }
            if ($parsed.Index -lt 1) {
                throw [System.ArgumentException]::new('ESD source index must be greater than zero.')
            }
            $validation.Exists = $true
            $validation.CanonicalSource = ('esd:{0}:{1}' -f (Resolve-Path -LiteralPath $parsed.Path).Path, $parsed.Index)
        }
        default {
            throw [System.ArgumentException]::new('Unsupported repair source type: {0}' -f $parsed.Type)
        }
    }

    if ($parsed.Type -in @('wim', 'esd')) {
        $resolvedImagePath = (Resolve-Path -LiteralPath $parsed.Path).Path
        $phaseRecord = New-PhaseRecord -Name 'RepairSourceMetadata'
        $metadataResult = Invoke-DismPhase -PhaseName 'RepairSourceMetadata' -CoreArguments @('/Get-WimInfo', ('/WimFile:{0}' -f $resolvedImagePath), ('/Index:{0}' -f $parsed.Index)) -PhaseRecord $phaseRecord
        $validation.MetadataInspected = $true
        $validation.MetadataExitCode = $metadataResult.ExitCode
        $validation.MetadataStdOut = $metadataResult.StdOutPath
        $validation.MetadataStdErr = $metadataResult.StdErrPath
        if ($metadataResult.ExitCode -ne 0) {
            throw [System.ArgumentException]::new('Repair source metadata validation failed for {0}. See {1}' -f $parsed.Original, $metadataResult.StdOutPath)
        }
        Copy-Item -LiteralPath $metadataResult.StdOutPath -Destination $script:Session.SourceInfoPath -Force
        $validation.ImageMetadata = Get-RepairSourceImageMetadata -ImagePath $resolvedImagePath -Index $parsed.Index
        $validation.SystemIdentity = $script:Summary.SystemIdentity
        $validation.ComparisonPerformed = $true
        $validation.Compatibility = Compare-SystemFilesCheckRepairSourceToSystem -SystemIdentity $validation.SystemIdentity -SourceIdentity $validation.ImageMetadata
        if (-not $validation.Compatibility.IsCompatible) {
            $mismatchText = if (@($validation.Compatibility.Mismatches).Count -gt 0) { $validation.Compatibility.Mismatches -join ' ' } else { 'Compatibility comparison failed.' }
            throw [System.ArgumentException]::new('Repair source is not compatible with the running OS. {0}' -f $mismatchText)
        }
        $messageParts = @('Metadata inspection succeeded.', ('Compatibility confidence: {0}.' -f $validation.Compatibility.ConfidenceLevel))
        if (@($validation.Compatibility.Warnings).Count -gt 0) {
            $messageParts += ('Warnings: {0}' -f ($validation.Compatibility.Warnings -join ' '))
        }
        $validation.Message = $messageParts -join ' '
    }

    $validation
}

function Get-TextValue {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern
    )

    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
    $match = [regex]::Match($Text, $Pattern, $options)
    if ($match.Success) {
        return $match.Groups['Value'].Value.Trim()
    }

    $null
}

function Parse-DismHealthOutput {
    param([string]$Text)
    Parse-SystemFilesCheckDismHealthOutput -Text $Text
}

function Parse-DismRestoreOutput {
    param([string]$Text)
    Parse-SystemFilesCheckDismRestoreOutput -Text $Text
}

function Parse-AnalyzeComponentStoreOutput {
    param([string]$Text)
    Parse-SystemFilesCheckAnalyzeComponentStoreOutput -Text $Text
}

function Parse-MountedImageOutput {
    param([string]$Text)
    Parse-SystemFilesCheckMountedImageOutput -Text $Text
}

function Convert-ToSerializableObject {
    param([AllowNull()]$InputObject)
    Convert-SystemFilesCheckToJsonSafeObject -InputObject $InputObject
}

function Copy-LogArtifacts {
    $targets = @(
        @{ Source = (Join-Path -Path $env:windir -ChildPath 'Logs\CBS\CBS.log'); Destination = (Join-Path -Path $script:Session.CopiedLogPath -ChildPath 'CBS.log') },
        @{ Source = (Join-Path -Path $env:windir -ChildPath 'Logs\CBS\CBS.persist.log'); Destination = (Join-Path -Path $script:Session.CopiedLogPath -ChildPath 'CBS.persist.log') },
        @{ Source = (Join-Path -Path $env:windir -ChildPath 'Logs\DISM\dism.log'); Destination = (Join-Path -Path $script:Session.CopiedLogPath -ChildPath 'dism.log') },
        @{ Source = (Join-Path -Path $env:windir -ChildPath 'Logs\DISM\dism.log.bak'); Destination = (Join-Path -Path $script:Session.CopiedLogPath -ChildPath 'dism.log.bak') }
    )

    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target.Source) {
            Copy-Item -LiteralPath $target.Source -Destination $target.Destination -Force
            Write-SessionLog -Message ('Copied log artifact: {0}' -f $target.Destination)
        }
    }
}

function Get-CbsLogPaths {
    $paths = @()
    foreach ($candidate in @(
            (Join-Path -Path $script:Session.CopiedLogPath -ChildPath 'CBS.log'),
            (Join-Path -Path $script:Session.CopiedLogPath -ChildPath 'CBS.persist.log')
        )) {
        if (Test-Path -LiteralPath $candidate) {
            $paths += $candidate
        }
    }
    $paths
}

function Get-CbsSrLines {
    param(
        [Parameter(Mandatory)][datetime]$StartTime,
        [Parameter(Mandatory)][datetime]$EndTime
    )

    Get-SystemFilesCheckSessionCbsSrLines -Paths (Get-CbsLogPaths) -StartTime $StartTime -EndTime $EndTime
}

function Save-CbsEvidence {
    $allLines = New-Object System.Collections.Generic.List[string]
    foreach ($path in (Get-CbsLogPaths)) {
        foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
            if ($line -match '\[SR\]') {
                $allLines.Add($line)
            }
        }
    }

    $sessionLines = @()
    if ($script:Summary.StartTime -and $script:Summary.EndTime) {
        $sessionLines = Get-CbsSrLines -StartTime $script:Summary.StartTime -EndTime $script:Summary.EndTime
    }

    Set-Content -LiteralPath $script:Session.AllSrPath -Value $allLines -Encoding UTF8
    Set-Content -LiteralPath $script:Session.SessionSrPath -Value $sessionLines -Encoding UTF8
    $script:Summary.SessionSrLineCount = @($sessionLines).Count
    $script:Summary.SessionCannotRepairLineCount = @($sessionLines | Where-Object { $_ -match 'Cannot repair' }).Count
}

function Get-SfcPhaseAssessment {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$PhaseRecord,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not $PhaseRecord.Executed -or -not $PhaseRecord.StartTime -or -not $PhaseRecord.EndTime) {
        return [ordered]@{
            Status             = 'NotRun'
            SessionSrLineCount = 0
            CannotRepairCount  = 0
            EvidencePath       = $null
            Message            = '{0} was not run.' -f $Label
        }
    }

    $lines = Get-CbsSrLines -StartTime $PhaseRecord.StartTime -EndTime $PhaseRecord.EndTime
    $evidencePath = Join-Path -Path $script:Session.SessionPath -ChildPath ('{0}_SR.txt' -f $Label)
    Set-Content -LiteralPath $evidencePath -Value $lines -Encoding UTF8

    $assessmentCore = Get-SystemFilesCheckSfcAssessmentFromLines -Lines $lines -Label $Label

    [ordered]@{
        Status             = $assessmentCore.Status
        SessionSrLineCount = $assessmentCore.SessionSrLineCount
        CannotRepairCount  = $assessmentCore.CannotRepairCount
        EvidencePath       = $evidencePath
        Message            = $assessmentCore.Message
    }
}

function Initialize-ScratchDirectory {
    param([string]$RequestedPath)

    $resolved = $RequestedPath
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $resolved = Join-Path -Path $script:Session.SessionPath -ChildPath 'Scratch'
    }

    if (-not (Test-Path -LiteralPath $resolved)) {
        New-Item -ItemType Directory -Path $resolved -Force | Out-Null
    }

    (Resolve-Path -LiteralPath $resolved).Path
}

function Compare-AnalyzeSnapshots {
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After
    )

    $summary = ''
    if ($Before.ActualSizeOfComponentStore -and $After.ActualSizeOfComponentStore) {
        $summary = 'Actual Size changed from {0} to {1}. Reclaimable packages changed from {2} to {3}.' -f $Before.ActualSizeOfComponentStore, $After.ActualSizeOfComponentStore, $Before.NumberOfReclaimablePackages, $After.NumberOfReclaimablePackages
    }

    [ordered]@{
        Available         = $true
        ActualSizeBefore  = $Before.ActualSizeOfComponentStore
        ActualSizeAfter   = $After.ActualSizeOfComponentStore
        ReclaimableBefore = $Before.NumberOfReclaimablePackages
        ReclaimableAfter  = $After.NumberOfReclaimablePackages
        DateOfLastCleanup = $After.DateOfLastCleanup
        Summary           = $summary
    }
}

function Read-ResetBaseConfirmation {
    if ($script:ForceResetBase) {
        return $true
    }

    Write-Host ''
    Write-Host 'ResetBase permanently removes superseded component versions and makes installed updates non-uninstallable.'
    $response = Read-Host 'Type YES to continue with ResetBase, or press Enter to skip ResetBase'
    ($response -eq 'YES')
}

function Set-OverallResult {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][int]$ExitCode
    )

    if ($script:ResultLocked -and $Category -ne 'ScriptError') {
        return
    }

    $script:Summary.OverallResultCategory = $Category
    $script:Summary.ExitCode = $ExitCode
}

function Resolve-NextStepRecommendation {
    Get-SystemFilesCheckNextStepRecommendation -Category $script:Summary.OverallResultCategory
}

function Resolve-OverallSummary {
    $selfTestPassed = [bool]($script:SelfTest -and $script:Summary.Phases.SelfTest.Status -eq 'Passed')
    $verdict = Resolve-SystemFilesCheckOutcome -Summary $script:Summary -ScriptFailure $script:ScriptFailure -SelfTestPassed $selfTestPassed
    Set-OverallResult -Category $verdict.Category -ExitCode $verdict.ExitCode
    $script:Summary.ResultReason = $verdict.Reason
    $script:Summary.ManualActionRecommended = $verdict.ManualActionRecommended
    $script:Summary.RequestedActionFailures = $verdict.RequestedActionFailures
    if ($script:ScriptFailure) {
        $script:ResultLocked = $true
    }
}

function Write-SummaryFiles {
    $script:Summary.NextStepRecommendation = Resolve-NextStepRecommendation
    if ($script:Summary.OverallResultCategory -in @('CorruptionRemains', 'NonRepairable', 'RequestedActionFailed', 'InvalidInput', 'PreflightFailed', 'ScriptError')) {
        $script:Summary.ManualActionRecommended = $true
    }
    $repairSourceDisplay = if ($script:Summary.RepairSource) { $script:Summary.RepairSource } else { 'None' }
    $mountedBeforeDisplay = Format-SystemFilesCheckMountedImageInventoryDisplay -Inventory $script:Summary.MountedImageStateBeforeCleanup -UnknownText 'Unknown' -NoneText 'None'
    $mountedAfterDisplay = Format-SystemFilesCheckMountedImageInventoryDisplay -Inventory $script:Summary.MountedImageStateAfterCleanup -UnknownText 'Not collected' -NoneText 'None'
    $mountedBeforeState = if ($script:Summary.MountedImageStateBeforeCleanup) { $script:Summary.MountedImageStateBeforeCleanup.QueryState } else { 'NotCollected' }
    $mountedAfterState = if ($script:Summary.MountedImageStateAfterCleanup) { $script:Summary.MountedImageStateAfterCleanup.QueryState } else { 'NotCollected' }

    $lines = @(
        'System Files Check Summary',
        '==========================',
        ('Overall result category            : {0}' -f $script:Summary.OverallResultCategory),
        ('Exit code                          : {0}' -f $script:Summary.ExitCode),
        ('Result reason                      : {0}' -f $script:Summary.ResultReason),
        ('Tool version                       : {0}' -f $script:Summary.ToolVersion),
        ('Machine name                       : {0}' -f $script:Summary.MachineName),
        ('User name                          : {0}' -f $script:Summary.UserName),
        ('OS version/build                   : {0}' -f $script:Summary.Environment.OsBuildDisplay),
        ('Start time                         : {0}' -f $script:Summary.StartTime.ToString('yyyy-MM-dd HH:mm:ss')),
        ('End time                           : {0}' -f $script:Summary.EndTime.ToString('yyyy-MM-dd HH:mm:ss')),
        ('Total duration                     : {0}' -f $script:Summary.TotalDuration),
        ('Pending reboot before run          : {0}' -f (Format-NullableSummaryValue -Value $script:Summary.PendingRebootBeforeRun)),
        ('Pending reboot after run           : {0}' -f (Format-NullableSummaryValue -Value $script:Summary.PendingRebootAfterRun)),
        ('Repair source used                 : {0}' -f $script:Summary.RepairSourceUsed),
        ('Repair source                      : {0}' -f $repairSourceDisplay),
        ('Windows Update access allowed      : {0}' -f $script:Summary.WindowsUpdateAccessAllowed),
        ('Invalid mount points detected      : {0}' -f (Format-NullableSummaryValue -Value $script:Summary.InvalidMountPointsDetected)),
        ('Needs remount detected             : {0}' -f (Format-NullableSummaryValue -Value $script:Summary.NeedsRemountDetected)),
        ('Mounted image query state before   : {0}' -f $mountedBeforeState),
        ('Mounted image states before cleanup: {0}' -f $mountedBeforeDisplay),
        ('Mounted image query state after    : {0}' -f $mountedAfterState),
        ('Mounted image states after cleanup : {0}' -f $mountedAfterDisplay),
        ('Mount cleanup requested/performed  : {0}/{1}' -f $script:Summary.MountCleanupRequested, $script:Summary.MountCleanupPerformed),
        ('Restore point relevant             : {0}' -f $script:Summary.RestorePoint.Relevant),
        ('Restore point gate evaluated       : {0}' -f $script:Summary.RestorePoint.GateEvaluated),
        ('Restore point attempted            : {0}' -f $script:Summary.RestorePoint.Attempted),
        ('Restore point succeeded            : {0}' -f $script:Summary.RestorePoint.Succeeded),
        ('Restore point required             : {0}' -f $script:Summary.RestorePoint.Required),
        ('Restore point outcome              : {0}' -f $script:Summary.RestorePoint.Outcome),
        ('Continued without restore point    : {0}' -f $script:Summary.RestorePoint.ContinueWithoutRestorePoint),
        ('Execution continued after gate     : {0}' -f $script:Summary.RestorePoint.ExecutionContinued),
        ('Restore point sequence             : {0}' -f ($(if ($script:Summary.RestorePoint.SequenceNumber) { $script:Summary.RestorePoint.SequenceNumber } else { 'None' }))),
        ('Restore point message              : {0}' -f $script:Summary.RestorePoint.Message),
        ('SFC baseline result                : {0}' -f $script:Summary.SfcBaselineResult),
        ('SFC final result                   : {0}' -f $script:Summary.SfcFinalResult),
        ('DISM CheckHealth result            : {0}' -f $script:Summary.DismCheckHealthResult),
        ('DISM ScanHealth result             : {0}' -f $script:Summary.DismScanHealthResult),
        ('DISM RestoreHealth result          : {0}' -f $script:Summary.DismRestoreHealthResult),
        ('Final DISM CheckHealth result      : {0}' -f $script:Summary.FinalDismCheckHealthResult),
        ('Actual Size of Component Store     : {0}' -f ($(if ($script:Summary.AnalyzeComponentStore.ActualSizeOfComponentStore) { $script:Summary.AnalyzeComponentStore.ActualSizeOfComponentStore } else { 'Unknown' }))),
        ('Backups and Disabled Features      : {0}' -f ($(if ($script:Summary.AnalyzeComponentStore.BackupsAndDisabledFeatures) { $script:Summary.AnalyzeComponentStore.BackupsAndDisabledFeatures } else { 'Unknown' }))),
        ('Cache and Temporary Data           : {0}' -f ($(if ($script:Summary.AnalyzeComponentStore.CacheAndTemporaryData) { $script:Summary.AnalyzeComponentStore.CacheAndTemporaryData } else { 'Unknown' }))),
        ('Date of Last Cleanup               : {0}' -f ($(if ($script:Summary.AnalyzeComponentStore.DateOfLastCleanup) { $script:Summary.AnalyzeComponentStore.DateOfLastCleanup } else { 'Unknown' }))),
        ('Number of Reclaimable Packages     : {0}' -f ($(if ($script:Summary.AnalyzeComponentStore.NumberOfReclaimablePackages) { $script:Summary.AnalyzeComponentStore.NumberOfReclaimablePackages } else { 'Unknown' }))),
        ('Component Store Cleanup Recommended: {0}' -f ($(if ($script:Summary.AnalyzeComponentStore.ComponentStoreCleanupRecommended) { $script:Summary.AnalyzeComponentStore.ComponentStoreCleanupRecommended } else { 'Unknown' }))),
        ('Cleanup result                     : {0}' -f $script:Summary.CleanupResult),
        ('Analyze-after-cleanup summary      : {0}' -f ($(if ($script:Summary.AnalyzeAfterCleanupComparison.Summary) { $script:Summary.AnalyzeAfterCleanupComparison.Summary } else { 'Not available' }))),
        ('Session SR line count              : {0}' -f $script:Summary.SessionSrLineCount),
        ('Session Cannot repair line count   : {0}' -f $script:Summary.SessionCannotRepairLineCount),
        ('Requested action failures          : {0}' -f ($(if (@($script:Summary.RequestedActionFailures).Count -gt 0) { $script:Summary.RequestedActionFailures -join '; ' } else { 'None' }))),
        ('Manual action recommended          : {0}' -f $script:Summary.ManualActionRecommended),
        '',
        'Next step recommendation:',
        $script:Summary.NextStepRecommendation,
        '',
        ('Session path                       : {0}' -f $script:Summary.SessionPath),
        ('Main log                           : {0}' -f $script:Summary.MainLogPath),
        ('Transcript                         : {0}' -f $script:Summary.TranscriptPath)
    )

    if (@($script:Summary.Warnings).Count -gt 0) {
        $lines += ''
        $lines += 'Warnings:'
        $lines += $script:Summary.Warnings
    }

    if (@($script:Summary.Errors).Count -gt 0) {
        $lines += ''
        $lines += 'Errors:'
        $lines += $script:Summary.Errors
    }

    Set-Content -LiteralPath $script:Session.SummaryText -Value $lines -Encoding UTF8
    $jsonObject = Convert-ToSerializableObject -InputObject $script:Summary
    $jsonText = ConvertTo-Json -InputObject $jsonObject -Depth 8
    Set-Content -LiteralPath $script:Session.SummaryJson -Value $jsonText -Encoding UTF8

    if ($script:JsonSummary) {
        $targetDirectory = Split-Path -Path $script:JsonSummary -Parent
        if ($targetDirectory -and -not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $script:Session.SummaryJson -Destination $script:JsonSummary -Force
    }
}

function Assert-Test {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Invoke-SelfTests {
    $phase = $script:Summary.Phases.SelfTest
    $jsonOut = Join-Path -Path $script:Session.PhasePath -ChildPath 'SelfTest.results.json'
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'tests\Invoke-SystemFilesCheckRegression.ps1'
    $result = Invoke-ExternalPhase -PhaseName 'SelfTest' -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-RepositoryRoot', $PSScriptRoot, '-JsonOut', $jsonOut, '-Quiet') -PhaseRecord $phase

    $phase.Status = if ($result.ExitCode -eq 0) { 'Passed' } else { 'Failed' }
    $phase.Message = 'Self-tests completed.'
    $phase.ExitCode = $result.ExitCode

    if (Test-Path -LiteralPath $jsonOut) {
        $payload = Get-Content -LiteralPath $jsonOut -Raw | ConvertFrom-Json
        $phase.Details = $payload
        foreach ($record in $payload.Results) {
            $script:Summary.Notes = @($script:Summary.Notes + ('{0}: {1}' -f $record.Name, $record.Message))
        }
    }

    if ($result.ExitCode -eq 0) {
        Set-OverallResult -Category 'Healthy' -ExitCode $script:ExitCodes.Healthy
    }
    else {
        throw [System.InvalidOperationException]::new('Self-tests reported at least one failure. See SelfTest.results.json for details.')
    }
}

function Invoke-MainWorkflow {
    if ($script:ShowUsage) {
        Show-ToolUsage
        Set-OverallResult -Category 'Healthy' -ExitCode $script:ExitCodes.Healthy
        return
    }

    if ($script:DryRun -and ($script:RunRepair -or $script:RunCleanup -or $script:RunResetBase -or $script:CleanupMountPoints)) {
        throw [System.ArgumentException]::new('DryRun cannot be combined with repair, cleanup, ResetBase, or Cleanup-MountPoints switches.')
    }

    if ($script:RunResetBase) {
        $script:RunCleanup = $true
    }

    Update-SummaryModes
    $script:Summary.WindowsUpdateAccessAllowed = -not $script:LimitAccess
    Populate-EnvironmentSummary

    if ($script:SelfTest) {
        Add-InfoNote -Message 'Running self-tests only.'
        Invoke-SelfTests
        return
    }

    $isAdmin = Test-IsAdministrator
    $script:Summary.IsAdministrator = $isAdmin
    if (-not $isAdmin) {
        throw [System.UnauthorizedAccessException]::new('This tool must be run from an elevated PowerShell or Command Prompt session.')
    }

    $script:Summary.ScratchDir = Initialize-ScratchDirectory -RequestedPath $script:ScratchDir
    Add-InfoNote -Message ('Scratch directory: {0}' -f $script:Summary.ScratchDir)

    if ($script:RepairSource) {
        $sourceValidation = Validate-RepairSource -Value $script:RepairSource
        $script:Summary.RepairSourceUsed = $true
        $script:Summary.RepairSource = $sourceValidation.CanonicalSource
        $script:Summary.RepairSourceValidation = $sourceValidation
        Add-InfoNote -Message ('Validated repair source: {0}' -f $script:Summary.RepairSource)
    }

    if ($script:RunResetBase -and -not (Read-ResetBaseConfirmation)) {
        Add-WarningNote -Message 'ResetBase confirmation was declined. The run will continue with StartComponentCleanup only.'
        $script:RunResetBase = $false
        $script:Summary.Modes.RunResetBase = $false
    }

    Ensure-GuardedRestorePoint

    $mountedPhase = $script:Summary.Phases.MountedImageInfo
    $mountedResult = Invoke-DismPhase -PhaseName 'MountedImageInfo' -CoreArguments @('/Get-MountedImageInfo') -PhaseRecord $mountedPhase
    $mountedParse = Parse-MountedImageOutput -Text $mountedResult.StdOut
    $mountedQueryState = if ($mountedResult.ExitCode -eq 0) {
        if (@($mountedParse).Count -gt 0) { 'Available' } else { 'Empty' }
    }
    else {
        'FailedToQuery'
    }
    $mountedQueryMessage = if ($mountedResult.ExitCode -eq 0) { 'Mounted image preflight completed.' } else { 'Get-MountedImageInfo returned a non-zero exit code.' }
    $mountedInventory = Get-SystemFilesCheckMountedImageInventory -MountedImages $mountedParse -QueryState $mountedQueryState -QueryExitCode $mountedResult.ExitCode -QueryMessage $mountedQueryMessage
    $mountedPhase.Status = if ($mountedResult.ExitCode -eq 0) { 'Completed' } else { 'Failed' }
    $mountedPhase.Message = if ($mountedResult.ExitCode -eq 0) { 'Mounted image preflight completed.' } else { 'Mounted image preflight query failed.' }
    $mountedPhase.Details = [ordered]@{ MountedImages = $mountedParse; Inventory = $mountedInventory }
    $script:Summary.MountedImages = @($mountedParse)
    $script:Summary.MountedImageCount = $mountedInventory.ImageCount
    $script:Summary.MountedImageStateBeforeCleanup = $mountedInventory
    $script:Summary.InvalidMountPointsDetected = $mountedInventory.AnyInvalid
    $script:Summary.NeedsRemountDetected = $mountedInventory.AnyNeedsRemount

    if ($mountedInventory.QueryState -eq 'FailedToQuery') {
        Add-WarningNote -Message 'Mounted image preflight query failed. The run cannot claim a fully successful preflight.'
    }
    if ($script:Summary.InvalidMountPointsDetected) {
        Add-WarningNote -Message 'Invalid mounted image entries were detected. Cleanup-MountPoints is available but was not run automatically.'
    }
    if ($script:Summary.NeedsRemountDetected) {
        Add-WarningNote -Message 'Mounted image entries in Needs Remount state were detected. Manual review is recommended before cleanup.'
    }

    if ($script:CleanupMountPoints) {
        $cleanupMountPhase = $script:Summary.Phases.CleanupMountPoints
        $cleanupMountResult = Invoke-DismPhase -PhaseName 'CleanupMountPoints' -CoreArguments @('/Cleanup-MountPoints') -PhaseRecord $cleanupMountPhase
        $cleanupMountPhase.Status = if ($cleanupMountResult.ExitCode -eq 0) { 'Completed' } else { 'Failed' }
        $cleanupMountPhase.Message = 'Cleanup-MountPoints executed.'
        $script:Summary.MountCleanupPerformed = ($cleanupMountResult.ExitCode -eq 0)

        $mountedAfterCleanupPhase = $script:Summary.Phases.MountedImageInfoAfterCleanup
        $mountedAfterCleanupResult = Invoke-DismPhase -PhaseName 'MountedImageInfoAfterCleanup' -CoreArguments @('/Get-MountedImageInfo') -PhaseRecord $mountedAfterCleanupPhase
        $mountedAfterCleanupParse = Parse-MountedImageOutput -Text $mountedAfterCleanupResult.StdOut
        $mountedAfterCleanupQueryState = if ($mountedAfterCleanupResult.ExitCode -eq 0) {
            if (@($mountedAfterCleanupParse).Count -gt 0) { 'Available' } else { 'Empty' }
        }
        else {
            'FailedToQuery'
        }
        $mountedAfterCleanupQueryMessage = if ($mountedAfterCleanupResult.ExitCode -eq 0) { 'Mounted image inventory after cleanup completed.' } else { 'Get-MountedImageInfo after Cleanup-MountPoints returned a non-zero exit code.' }
        $mountedAfterCleanupInventory = Get-SystemFilesCheckMountedImageInventory -MountedImages $mountedAfterCleanupParse -QueryState $mountedAfterCleanupQueryState -QueryExitCode $mountedAfterCleanupResult.ExitCode -QueryMessage $mountedAfterCleanupQueryMessage
        $mountedAfterCleanupPhase.Status = if ($mountedAfterCleanupResult.ExitCode -eq 0) { 'Completed' } else { 'Failed' }
        $mountedAfterCleanupPhase.Message = if ($mountedAfterCleanupResult.ExitCode -eq 0) { 'Mounted image inventory was collected after Cleanup-MountPoints.' } else { 'Mounted image inventory query after Cleanup-MountPoints failed.' }
        $mountedAfterCleanupPhase.Details = [ordered]@{ MountedImages = $mountedAfterCleanupParse; Inventory = $mountedAfterCleanupInventory }
        $script:Summary.MountedImageStateAfterCleanup = $mountedAfterCleanupInventory
        $script:Summary.InvalidMountPointsDetected = $mountedAfterCleanupInventory.AnyInvalid
        $script:Summary.NeedsRemountDetected = $mountedAfterCleanupInventory.AnyNeedsRemount
        if ($mountedAfterCleanupInventory.QueryState -eq 'FailedToQuery') {
            Add-WarningNote -Message 'Mounted image inventory query after Cleanup-MountPoints failed.'
        }
    }

    if ($script:PreSFC) {
        $phase = $script:Summary.Phases.SfcBaseline
        [void](Invoke-SfcPhase -PhaseName 'SfcBaseline' -PhaseRecord $phase)
        Copy-LogArtifacts
        $assessment = Get-SfcPhaseAssessment -PhaseRecord $phase -Label 'SfcBaseline'
        $phase.Status = $assessment.Status
        $phase.Message = $assessment.Message
        $phase.EvidencePath = $assessment.EvidencePath
        $phase.Details = $assessment
        $script:Summary.SfcBaselineResult = $assessment.Status
    }

    $checkPhase = $script:Summary.Phases.DismCheckHealth
    $checkResult = Invoke-DismPhase -PhaseName 'DismCheckHealth' -CoreArguments @('/Online', '/Cleanup-Image', '/CheckHealth') -PhaseRecord $checkPhase
    $checkParsed = Parse-DismHealthOutput -Text $checkResult.StdOut
    $checkPhase.Status = $checkParsed.Status
    $checkPhase.Message = $checkParsed.Message
    $checkPhase.Details = $checkParsed
    $script:Summary.DismCheckHealthResult = $checkParsed.Status

    if (-not $script:Quick) {
        $scanPhase = $script:Summary.Phases.DismScanHealth
        $scanResult = Invoke-DismPhase -PhaseName 'DismScanHealth' -CoreArguments @('/Online', '/Cleanup-Image', '/ScanHealth') -PhaseRecord $scanPhase
        $scanParsed = Parse-DismHealthOutput -Text $scanResult.StdOut
        $scanPhase.Status = $scanParsed.Status
        $scanPhase.Message = $scanParsed.Message
        $scanPhase.Details = $scanParsed
        $script:Summary.DismScanHealthResult = $scanParsed.Status
    }
    else {
        $script:Summary.Phases.DismScanHealth.Status = 'Skipped'
        $script:Summary.Phases.DismScanHealth.Message = 'Quick mode skipped ScanHealth.'
        $script:Summary.DismScanHealthResult = 'Skipped'
    }

    if ($script:RunRepair) {
        $restoreArgs = @('/Online', '/Cleanup-Image', '/RestoreHealth')
        if ($script:Summary.RepairSourceUsed -and $script:Summary.RepairSource) {
            $restoreArgs += ('/Source:{0}' -f $script:Summary.RepairSource)
        }
        if ($script:LimitAccess) {
            $restoreArgs += '/LimitAccess'
        }

        $restorePhase = $script:Summary.Phases.DismRestoreHealth
        $restoreResult = Invoke-DismPhase -PhaseName 'DismRestoreHealth' -CoreArguments $restoreArgs -PhaseRecord $restorePhase
        $restoreParsed = Parse-DismRestoreOutput -Text $restoreResult.StdOut
        $restorePhase.Status = $restoreParsed.Status
        $restorePhase.Message = $restoreParsed.Message
        $restorePhase.Details = $restoreParsed
        $script:Summary.DismRestoreHealthResult = $restoreParsed.Status

        $sfcFinalPhase = $script:Summary.Phases.SfcFinal
        [void](Invoke-SfcPhase -PhaseName 'SfcFinal' -PhaseRecord $sfcFinalPhase)
        Copy-LogArtifacts
        $sfcFinalAssessment = Get-SfcPhaseAssessment -PhaseRecord $sfcFinalPhase -Label 'SfcFinal'
        $sfcFinalPhase.Status = $sfcFinalAssessment.Status
        $sfcFinalPhase.Message = $sfcFinalAssessment.Message
        $sfcFinalPhase.EvidencePath = $sfcFinalAssessment.EvidencePath
        $sfcFinalPhase.Details = $sfcFinalAssessment
        $script:Summary.SfcFinalResult = $sfcFinalAssessment.Status
    }
    else {
        $script:Summary.Phases.DismRestoreHealth.Status = 'Skipped'
        $script:Summary.Phases.DismRestoreHealth.Message = 'RunRepair was not requested.'
        $script:Summary.DismRestoreHealthResult = 'Skipped'
        $script:Summary.Phases.SfcFinal.Status = 'Skipped'
        $script:Summary.Phases.SfcFinal.Message = 'RunRepair was not requested.'
        $script:Summary.SfcFinalResult = 'NotRun'
    }

    $finalCheckPhase = $script:Summary.Phases.FinalDismCheckHealth
    $finalCheckResult = Invoke-DismPhase -PhaseName 'FinalDismCheckHealth' -CoreArguments @('/Online', '/Cleanup-Image', '/CheckHealth') -PhaseRecord $finalCheckPhase
    $finalCheckParsed = Parse-DismHealthOutput -Text $finalCheckResult.StdOut
    $finalCheckPhase.Status = $finalCheckParsed.Status
    $finalCheckPhase.Message = $finalCheckParsed.Message
    $finalCheckPhase.Details = $finalCheckParsed
    $script:Summary.FinalDismCheckHealthResult = $finalCheckParsed.Status

    $analyzePhase = $script:Summary.Phases.AnalyzeComponentStore
    $analyzeResult = Invoke-DismPhase -PhaseName 'AnalyzeComponentStore' -CoreArguments @('/Online', '/Cleanup-Image', '/AnalyzeComponentStore') -PhaseRecord $analyzePhase
    $analyzeParsed = Parse-AnalyzeComponentStoreOutput -Text $analyzeResult.StdOut
    $analyzePhase.Status = if ($analyzeResult.ExitCode -eq 0) { 'Completed' } else { 'Failed' }
    $analyzePhase.Message = 'AnalyzeComponentStore completed.'
    $analyzePhase.Details = $analyzeParsed
    $script:Summary.AnalyzeComponentStore = $analyzeParsed

    if ($script:RunCleanup) {
        $cleanupArgs = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
        if ($script:RunResetBase) {
            $cleanupArgs += '/ResetBase'
        }

        $cleanupPhase = $script:Summary.Phases.StartComponentCleanup
        $cleanupResult = Invoke-DismPhase -PhaseName 'StartComponentCleanup' -CoreArguments $cleanupArgs -PhaseRecord $cleanupPhase
        $cleanupPhase.Status = if ($cleanupResult.ExitCode -eq 0) { 'Completed' } else { 'Failed' }
        $cleanupPhase.Message = 'StartComponentCleanup completed.'
        $script:Summary.CleanupResult = $cleanupPhase.Status

        $analyzeAfterPhase = $script:Summary.Phases.AnalyzeAfterCleanup
        $analyzeAfterResult = Invoke-DismPhase -PhaseName 'AnalyzeAfterCleanup' -CoreArguments @('/Online', '/Cleanup-Image', '/AnalyzeComponentStore') -PhaseRecord $analyzeAfterPhase
        $analyzeAfterParsed = Parse-AnalyzeComponentStoreOutput -Text $analyzeAfterResult.StdOut
        $analyzeAfterPhase.Status = if ($analyzeAfterResult.ExitCode -eq 0) { 'Completed' } else { 'Failed' }
        $analyzeAfterPhase.Message = 'AnalyzeComponentStore after cleanup completed.'
        $analyzeAfterPhase.Details = $analyzeAfterParsed
        if ($analyzeAfterResult.ExitCode -eq 0) {
            $script:Summary.AnalyzeAfterCleanupComparison = Compare-AnalyzeSnapshots -Before $analyzeParsed -After $analyzeAfterParsed
        }
    }
    else {
        $script:Summary.Phases.StartComponentCleanup.Status = 'Skipped'
        $script:Summary.Phases.StartComponentCleanup.Message = 'RunCleanup was not requested.'
        $script:Summary.CleanupResult = 'Skipped'
        $script:Summary.Phases.AnalyzeAfterCleanup.Status = 'Skipped'
        $script:Summary.Phases.AnalyzeAfterCleanup.Message = 'RunCleanup was not requested.'
    }
}

function Write-FallbackSummary {
    param([Parameter(Mandatory)][string]$Message)

    $lines = @(
        'System Files Check Summary',
        '==========================',
        'Overall result category            : ScriptError',
        ('Exit code                          : {0}' -f $script:ExitCodes.ScriptError),
        ('Error                              : {0}' -f $Message),
        ('Session path                       : {0}' -f $script:Session.SessionPath)
    )
    Set-Content -LiteralPath $script:Session.SummaryText -Value $lines -Encoding UTF8
    $fallbackJson = ConvertTo-Json -InputObject (Convert-ToSerializableObject -InputObject $script:Summary) -Depth 8
    Set-Content -LiteralPath $script:Session.SummaryJson -Value $fallbackJson -Encoding UTF8
}

try {
    Initialize-Session
    Populate-EnvironmentSummary
    Merge-LegacyArguments -Arguments $LegacyArgs
    Update-SummaryModes
    Add-InfoNote -Message ('Tool version: {0}' -f $script:ToolVersion)
    Invoke-MainWorkflow
}
catch [System.ArgumentException] {
    $script:ScriptFailure = [ordered]@{
        Message  = $_.Exception.Message
        ExitCode = $script:ExitCodes.InvalidInput
    }
    if ($script:Summary) {
        Add-ErrorNote -Message $_.Exception.Message
    }
}
catch [System.UnauthorizedAccessException] {
    $script:ScriptFailure = [ordered]@{
        Message  = $_.Exception.Message
        ExitCode = $script:ExitCodes.PreflightFailed
    }
    if ($script:Summary) {
        Add-ErrorNote -Message $_.Exception.Message
    }
}
catch {
    $script:ScriptFailure = [ordered]@{
        Message  = $_.Exception.Message
        ExitCode = $script:ExitCodes.ScriptError
    }
    if ($script:Summary) {
        Add-ErrorNote -Message ('Unhandled error: {0}' -f $_.Exception.Message)
        Add-ErrorNote -Message ('Stack: {0}' -f $_.ScriptStackTrace)
    }
}
finally {
    try {
        if ($script:Summary) {
            $script:Summary.EndTime = Get-Date
            $script:Summary.TotalDuration = [string]($script:Summary.EndTime - $script:Summary.StartTime)
            $script:Summary.PendingRebootAfterRun = if ($script:SelfTest) { $null } else { Get-PendingRebootState }
            Copy-LogArtifacts
            Save-CbsEvidence
            Resolve-OverallSummary
            Write-SummaryFiles
            Write-SessionLog -Message ('Summary written to {0}' -f $script:Session.SummaryText)
            Write-SessionLog -Message ('JSON summary written to {0}' -f $script:Session.SummaryJson)
        }
    }
    catch {
        if ($script:Summary) {
            $script:Summary.Errors = @($script:Summary.Errors + ('Summary generation failure: {0}' -f $_.Exception.Message))
            $script:Summary.OverallResultCategory = 'ScriptError'
            $script:Summary.ExitCode = $script:ExitCodes.ScriptError
            try {
                Write-FallbackSummary -Message $_.Exception.Message
            }
            catch {
                Write-Verbose 'Fallback summary generation also failed.'
            }
        }
    }

    Stop-SessionTranscript

    if ($script:Summary) {
        Write-Host ''
        Write-Host ('Overall result : {0}' -f $script:Summary.OverallResultCategory)
        Write-Host ('Exit code      : {0}' -f $script:Summary.ExitCode)
        Write-Host ('Summary        : {0}' -f $script:Session.SummaryText)
        Write-Host ('Summary JSON   : {0}' -f $script:Session.SummaryJson)
    }

    if (-not $NoPause -and -not $ShowUsage) {
        Write-Host ''
        Read-Host 'Press Enter to exit' | Out-Null
    }

    if ($script:Summary) {
        exit ([int]$script:Summary.ExitCode)
    }

    exit $script:ExitCodes.ScriptError
}
