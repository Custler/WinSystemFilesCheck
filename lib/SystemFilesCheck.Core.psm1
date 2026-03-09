Set-StrictMode -Version Latest

$script:SystemFilesCheckToolVersion = '1.5.0'
$script:SystemFilesCheckExitCodes = [ordered]@{
    Healthy                      = 0
    Repaired                     = 10
    RepairedButRebootRecommended = 11
    CorruptionRemains            = 20
    NonRepairable                = 21
    RequestedActionFailed        = 22
    InvalidInput                 = 30
    PreflightFailed              = 31
    ScriptError                  = 40
}

function Get-SystemFilesCheckToolVersion {
    $script:SystemFilesCheckToolVersion
}

function Get-SystemFilesCheckExitCodes {
    [ordered]@{} + $script:SystemFilesCheckExitCodes
}

function Get-SystemFilesCheckMemberValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }

        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $Default
}

function Convert-SystemFilesCheckArchitectureValue {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return 'Unknown'
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'Unknown'
    }

    switch -Regex ($text.Trim()) {
        '^(?i)(9|x64|amd64|64-bit|64-разрядная)$' { return 'x64' }
        '^(?i)(0|x86|i386|32-bit|32-разрядная)$' { return 'x86' }
        '^(?i)(5|arm)$' { return 'ARM' }
        '^(?i)(12|arm64)$' { return 'ARM64' }
        default { return $text.Trim() }
    }
}

function Convert-SystemFilesCheckLanguageValue {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $trimmed = $Value.Trim()
    if ($trimmed -match '^[a-z]{2}-[A-Z]{2}$') {
        return $trimmed
    }

    $numeric = 0
    if ([int]::TryParse($trimmed, [ref]$numeric)) {
        try {
            return ([System.Globalization.CultureInfo]::GetCultureInfo($numeric)).Name
        }
        catch {
            return $trimmed
        }
    }

    if ($trimmed -match '^(0x)?[0-9A-Fa-f]{4}$') {
        $hexValue = if ($trimmed.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) { $trimmed.Substring(2) } else { $trimmed }
        try {
            $numeric = [Convert]::ToInt32($hexValue, 16)
            return ([System.Globalization.CultureInfo]::GetCultureInfo($numeric)).Name
        }
        catch {
            return $trimmed
        }
    }

    return $trimmed
}

function Convert-SystemFilesCheckToJsonSafeObject {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [datetime]) {
        return $InputObject.ToString('o')
    }

    if ($InputObject -is [timespan]) {
        return $InputObject.ToString()
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $ordered[$key] = Convert-SystemFilesCheckToJsonSafeObject -InputObject $InputObject[$key]
        }

        return [pscustomobject]$ordered
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += Convert-SystemFilesCheckToJsonSafeObject -InputObject $item
        }

        return ,$items
    }

    $properties = if ($InputObject.PSObject) { @($InputObject.PSObject.Properties) } else { @() }
    $hasProperties = @($properties).Count -gt 0
    if ($hasProperties -and -not ($InputObject -is [string]) -and -not ($InputObject -is [ValueType])) {
        $ordered = [ordered]@{}
        foreach ($property in $properties) {
            if ($property.IsGettable) {
                $ordered[$property.Name] = Convert-SystemFilesCheckToJsonSafeObject -InputObject $property.Value
            }
        }

        return [pscustomobject]$ordered
    }

    return $InputObject
}

function Resolve-SystemFilesCheckBuildFamily {
    param(
        [AllowNull()][string]$CurrentBuild,
        [AllowNull()][string]$BuildLabEx,
        [AllowNull()][string]$Version
    )

    foreach ($candidate in @($BuildLabEx, $Version, $CurrentBuild)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $match = [regex]::Match($candidate, '^(?<Build>\d{5})')
        if ($match.Success) {
            $build = $match.Groups['Build'].Value
            if ($build -in @('19041', '19042', '19043', '19044', '19045')) {
                return '19041-family'
            }

            return ('{0}-family' -f $build)
        }
    }

    return 'Unknown'
}

function New-SystemFilesCheckPhaseRecord {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    [ordered]@{
        Name         = $Name
        Executed     = $false
        ExitCode     = $null
        Status       = 'NotRun'
        Message      = ''
        StartTime    = $null
        EndTime      = $null
        Duration     = ''
        StdOutPath   = $null
        StdErrPath   = $null
        DismLogPath  = $null
        EvidencePath = $null
        Details      = [ordered]@{}
    }
}

function Parse-SystemFilesCheckRepairSourceSpec {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $trimmed = $Value.Trim().Trim('"')
    $match = [regex]::Match($trimmed, '^(?<Type>wim|esd):(?<Path>.+):(?<Index>\d+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return [ordered]@{
            Original = $trimmed
            Type     = $match.Groups['Type'].Value.ToLowerInvariant()
            Path     = $match.Groups['Path'].Value
            Index    = [int]$match.Groups['Index'].Value
        }
    }

    [ordered]@{
        Original = $trimmed
        Type     = 'folder'
        Path     = $trimmed
        Index    = $null
    }
}

function Get-SystemFilesCheckTextValue {
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

function Parse-SystemFilesCheckDismHealthOutput {
    param([string]$Text)

    $status = 'Unknown'
    $message = ''

    if ($Text -match 'No component store corruption detected\.') {
        $status = 'Healthy'
        $message = 'No component store corruption detected.'
    }
    elseif ($Text -match 'The component store is repairable\.') {
        $status = 'Repairable'
        $message = 'The component store is repairable.'
    }
    elseif ($Text -match 'The component store is not repairable\.') {
        $status = 'NonRepairable'
        $message = 'The component store is not repairable.'
    }
    elseif ($Text -match 'The operation completed successfully\.') {
        $status = 'Completed'
        $message = 'The operation completed successfully.'
    }

    [ordered]@{
        Status  = $status
        Message = $message
    }
}

function Parse-SystemFilesCheckDismRestoreOutput {
    param([string]$Text)

    $status = 'Unknown'
    $message = ''
    $rebootRecommended = $false

    if ($Text -match 'The restore operation completed successfully\.') {
        $status = 'Repaired'
        $message = 'The restore operation completed successfully.'
    }
    elseif ($Text -match 'No component store corruption detected\.') {
        $status = 'Healthy'
        $message = 'No component store corruption detected.'
    }
    elseif ($Text -match 'The source files could not be found\.') {
        $status = 'SourceMissing'
        $message = 'The source files could not be found.'
    }
    elseif ($Text -match 'The component store is not repairable\.') {
        $status = 'NonRepairable'
        $message = 'The component store is not repairable.'
    }
    elseif ($Text -match 'The component store is repairable\.') {
        $status = 'Repairable'
        $message = 'The component store is repairable.'
    }
    elseif ($Text -match 'The operation completed successfully\.') {
        $status = 'Completed'
        $message = 'The operation completed successfully.'
    }

    if ($Text -match 'You must restart Windows to complete this operation\.' -or $Text -match 'The requested operation requires a reboot') {
        $rebootRecommended = $true
    }

    [ordered]@{
        Status            = $status
        Message           = $message
        RebootRecommended = $rebootRecommended
    }
}

function Parse-SystemFilesCheckAnalyzeComponentStoreOutput {
    param([string]$Text)

    [ordered]@{
        ActualSizeOfComponentStore       = Get-SystemFilesCheckTextValue -Text $Text -Pattern '^\s*Actual Size of Component Store\s*:\s*(?<Value>.+)$'
        BackupsAndDisabledFeatures       = Get-SystemFilesCheckTextValue -Text $Text -Pattern '^\s*Backups and Disabled Features\s*:\s*(?<Value>.+)$'
        CacheAndTemporaryData            = Get-SystemFilesCheckTextValue -Text $Text -Pattern '^\s*Cache and Temporary Data\s*:\s*(?<Value>.+)$'
        DateOfLastCleanup                = Get-SystemFilesCheckTextValue -Text $Text -Pattern '^\s*Date of Last Cleanup\s*:\s*(?<Value>.+)$'
        NumberOfReclaimablePackages      = Get-SystemFilesCheckTextValue -Text $Text -Pattern '^\s*Number of Reclaimable Packages\s*:\s*(?<Value>.+)$'
        ComponentStoreCleanupRecommended = Get-SystemFilesCheckTextValue -Text $Text -Pattern '^\s*Component Store Cleanup Recommended\s*:\s*(?<Value>.+)$'
    }
}

function Normalize-SystemFilesCheckMountedImageKey {
    param([string]$Name)

    switch -Regex ($Name.Trim()) {
        '^(?i)mount\s+dir$' { return 'MountDir' }
        '^(?i)image\s+file$' { return 'ImageFile' }
        '^(?i)image\s+index$' { return 'ImageIndex' }
        '^(?i)status$' { return 'Status' }
        '^(?i)mount\s+status$' { return 'Status' }
        '^(?i)read/write$' { return 'ReadWrite' }
        '^(?i)mounted\s+for\s+rw$' { return 'MountedForRW' }
        '^(?i)mounted\s+read-only$' { return 'MountedReadOnly' }
        default { return ($Name.Trim() -replace '\s+', '') }
    }
}

function Normalize-SystemFilesCheckMountedImageStatus {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'Unknown'
    }

    switch -Regex ($Value.Trim()) {
        '^(?i)ok$' { return 'OK' }
        '^(?i)invalid$' { return 'Invalid' }
        '^(?i)needs\s+remount$' { return 'Needs Remount' }
        default { return $Value.Trim() }
    }
}

function Parse-SystemFilesCheckMountedImageOutput {
    param([string]$Text)

    $images = New-Object System.Collections.Generic.List[object]
    $current = [ordered]@{}

    function Add-SystemFilesCheckMountedImageRecord {
        param(
            [System.Collections.Specialized.OrderedDictionary]$Record,
            [System.Collections.Generic.List[object]]$List
        )

        if ($Record.Count -eq 0) {
            return
        }

        $hasMountedImageFields = $Record.Contains('MountDir') -or $Record.Contains('ImageFile') -or $Record.Contains('Status')
        if (-not $hasMountedImageFields) {
            return
        }

        if (-not $Record.Contains('Status')) {
            $Record['Status'] = 'Unknown'
        }

        $Record['StatusRaw'] = [string]$Record['Status']
        $Record['Status'] = Normalize-SystemFilesCheckMountedImageStatus -Value ([string]$Record['Status'])
        $List.Add([pscustomobject]$Record)
    }

    foreach ($line in ($Text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            Add-SystemFilesCheckMountedImageRecord -Record $current -List $images
            $current = [ordered]@{}
            continue
        }

        if ($line -match '^\s*Mounted images:\s*$' -or $line -match '^\s*Deployment Image Servicing and Management tool\s*$' -or $line -match '^\s*Version:\s*') {
            continue
        }

        if ($line -match '^\s*The operation completed successfully\.\s*$') {
            continue
        }

        $match = [regex]::Match($line, '^\s*(?<Name>[^:]+)\s*:\s*(?<Value>.+?)\s*$')
        if (-not $match.Success) {
            continue
        }

        $name = Normalize-SystemFilesCheckMountedImageKey -Name $match.Groups['Name'].Value
        $value = $match.Groups['Value'].Value.Trim()

        if ($name -eq 'MountDir' -and $current.Count -gt 0 -and $current.Contains('MountDir')) {
            Add-SystemFilesCheckMountedImageRecord -Record $current -List $images
            $current = [ordered]@{}
        }

        $current[$name] = $value
    }

    Add-SystemFilesCheckMountedImageRecord -Record $current -List $images
    ,$images.ToArray()
}

function Get-SystemFilesCheckMountedImageInventory {
    param(
        [AllowNull()]
        [object[]]$MountedImages,

        [ValidateSet('NotCollected', 'FailedToQuery', 'Empty', 'Available')]
        [string]$QueryState = 'Available',

        [AllowNull()]
        [int]$QueryExitCode = 0,

        [string]$QueryMessage = ''
    )

    $images = @($MountedImages)
    if ($QueryState -eq 'Available' -and $images.Count -eq 0) {
        $QueryState = 'Empty'
    }

    $querySucceeded = $QueryState -in @('Empty', 'Available')
    $statuses = if ($querySucceeded) {
        @($images | ForEach-Object {
                if ($_.PSObject.Properties['Status']) {
                    $_.Status
                }
            } | Where-Object { $_ })
    }
    else {
        @()
    }

    [ordered]@{
        QueryState        = $QueryState
        QuerySucceeded    = $querySucceeded
        QueryExitCode     = $QueryExitCode
        QueryMessage      = $QueryMessage
        ImageCount        = if ($querySucceeded) { $images.Count } else { $null }
        HasMountedImages  = if ($querySucceeded) { $images.Count -gt 0 } else { $null }
        AnyInvalid        = if ($querySucceeded) { @($images | Where-Object { $_.PSObject.Properties['Status'] -and $_.Status -eq 'Invalid' }).Count -gt 0 } else { $null }
        AnyNeedsRemount   = if ($querySucceeded) { @($images | Where-Object { $_.PSObject.Properties['Status'] -and $_.Status -eq 'Needs Remount' }).Count -gt 0 } else { $null }
        AnyUnknownStatus  = if ($querySucceeded) { @($images | Where-Object { $_.PSObject.Properties['Status'] -and $_.Status -eq 'Unknown' }).Count -gt 0 } else { $null }
        AllOk             = if ($QueryState -eq 'Available') { @($images | Where-Object { $_.PSObject.Properties['Status'] -and $_.Status -ne 'OK' }).Count -eq 0 } elseif ($QueryState -eq 'Empty') { $true } else { $null }
        Statuses          = $statuses
        Images            = $images
    }
}

function Format-SystemFilesCheckMountedImageInventoryDisplay {
    param(
        [AllowNull()]$Inventory,
        [string]$UnknownText = 'Unknown',
        [string]$NoneText = 'None'
    )

    if ($null -eq $Inventory) {
        return $UnknownText
    }

    $queryState = [string](Get-SystemFilesCheckMemberValue -Object $Inventory -Name 'QueryState' -Default 'Unknown')
    switch ($queryState) {
        'FailedToQuery' { return 'Failed to query' }
        'NotCollected' { return $UnknownText }
        'Empty' { return $NoneText }
    }

    $imageCount = Get-SystemFilesCheckMemberValue -Object $Inventory -Name 'ImageCount' -Default 0
    if ($imageCount -eq 0) {
        return $NoneText
    }

    $statuses = @(Get-SystemFilesCheckMemberValue -Object $Inventory -Name 'Statuses' -Default @())
    if ($statuses.Count -eq 0) {
        return $UnknownText
    }

    return ($statuses -join ', ')
}

function Resolve-SystemFilesCheckRestorePointSummary {
    param(
        [bool]$Relevant,
        [bool]$Attempted,
        [bool]$Succeeded,
        [bool]$Required,
        [bool]$SkippedByPolicy,
        [bool]$AbortedExecution
    )

    $result = [ordered]@{
        Outcome                    = 'Unknown'
        ContinueWithoutRestorePoint = $false
        ExecutionContinued         = $true
    }

    if (-not $Relevant) {
        $result.Outcome = 'NotRelevant'
        return [pscustomobject]$result
    }

    if ($SkippedByPolicy) {
        $result.Outcome = 'SkippedByPolicy'
        $result.ContinueWithoutRestorePoint = $true
        return [pscustomobject]$result
    }

    if ($Succeeded) {
        $result.Outcome = 'Created'
        return [pscustomobject]$result
    }

    if ($Attempted -and $Required -and $AbortedExecution) {
        $result.Outcome = 'RequiredButUnavailable'
        $result.ExecutionContinued = $false
        return [pscustomobject]$result
    }

    if ($Attempted -and -not $Succeeded) {
        $result.Outcome = 'AttemptedAndFailedContinued'
        $result.ContinueWithoutRestorePoint = $true
        return [pscustomobject]$result
    }

    $result.Outcome = 'NotAttempted'
    [pscustomobject]$result
}

function Get-SystemFilesCheckSfcAssessmentFromLines {
    param(
        [AllowNull()]
        [string[]]$Lines,

        [string]$Label = 'SFC'
    )

    $normalizedLines = @($Lines | Where-Object { $_ -ne $null })
    $cannotRepair = @($normalizedLines | Where-Object { $_ -match 'Cannot repair' }).Count
    $repairingCorruptedFileCount = @($normalizedLines | Where-Object { $_ -match 'Repairing corrupted file' }).Count
    $repairingComponentMatches = @($normalizedLines | ForEach-Object {
            if ($_ -match 'Repairing\s+(?<Count>\d+)\s+components') {
                [int]$Matches['Count']
            }
        } | Where-Object { $_ -ne $null })
    $positiveRepairComponentCount = @($repairingComponentMatches | Where-Object { $_ -gt 0 }).Count
    $zeroRepairComponentCount = @($repairingComponentMatches | Where-Object { $_ -eq 0 }).Count
    $repairCompleteCount = @($normalizedLines | Where-Object { $_ -match 'Repair complete' }).Count
    $repairedLines = $repairingCorruptedFileCount + $positiveRepairComponentCount

    $status = 'Healthy'
    $message = 'No unrepaired corruption was visible in CBS SR lines for this phase.'
    $repairsApplied = $repairingCorruptedFileCount -gt 0 -or $positiveRepairComponentCount -gt 0

    if ($cannotRepair -gt 0) {
        $status = 'CorruptionRemains'
        $message = 'CBS SR evidence contains unrepaired file entries.'
    }
    elseif ($repairsApplied) {
        $status = 'Repaired'
        $message = 'CBS SR evidence shows repaired files.'
    }
    elseif ($repairCompleteCount -gt 0 -and $zeroRepairComponentCount -gt 0) {
        $status = 'Healthy'
        $message = 'CBS SR evidence completed a repair transaction but repaired zero components.'
    }
    elseif ($normalizedLines.Count -eq 0) {
        $status = 'NoSessionEvidence'
        $message = 'No session-specific CBS SR lines were found for this phase.'
    }

    [ordered]@{
        Label              = $Label
        Status             = $status
        SessionSrLineCount = $normalizedLines.Count
        CannotRepairCount  = $cannotRepair
        RepairedLineCount  = $repairedLines
        RepairCompleteCount = $repairCompleteCount
        ZeroRepairComponentCount = $zeroRepairComponentCount
        Message            = $message
    }
}

function Get-SystemFilesCheckSessionCbsSrLines {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter(Mandatory)][datetime]$StartTime,
        [Parameter(Mandatory)][datetime]$EndTime
    )

    $results = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Paths) {
        foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
            if ($line -notmatch '\[SR\]') {
                continue
            }

            $match = [regex]::Match($line, '^(?<Stamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
            if (-not $match.Success) {
                continue
            }

            $stamp = [datetime]::ParseExact($match.Groups['Stamp'].Value, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($stamp -ge $StartTime -and $stamp -le $EndTime.AddMinutes(1)) {
                $results.Add($line)
            }
        }
    }

    ,$results.ToArray()
}

function Get-SystemFilesCheckFinalDismState {
    param([Parameter(Mandatory)]$Summary)

    foreach ($value in @(
            $Summary.FinalDismCheckHealthResult,
            $Summary.DismRestoreHealthResult,
            $Summary.DismScanHealthResult,
            $Summary.DismCheckHealthResult
        )) {
        if ($value -and $value -notin @('NotRun', 'Skipped', 'Completed', 'Unknown')) {
            return $value
        }
    }

    'Unknown'
}

function Test-SystemFilesCheckRequestedActionFailed {
    param([Parameter(Mandatory)]$Summary)

    $reasons = New-Object System.Collections.Generic.List[string]

    if ($Summary.Modes.CleanupMountPoints) {
        if ($null -ne $Summary.Phases.CleanupMountPoints.ExitCode -and $Summary.Phases.CleanupMountPoints.ExitCode -ne 0) {
            $reasons.Add('Cleanup-MountPoints exited with a non-zero code.') | Out-Null
        }

        if ($Summary.MountedImageStateAfterCleanup) {
            if ($Summary.MountedImageStateAfterCleanup.AnyInvalid) {
                $reasons.Add('Invalid mounted image entries remained after Cleanup-MountPoints.') | Out-Null
            }
            if ($Summary.MountedImageStateAfterCleanup.AnyNeedsRemount) {
                $reasons.Add('Needs Remount entries remained after Cleanup-MountPoints.') | Out-Null
            }
        }
    }

    if ($Summary.Modes.RunCleanup) {
        if ($null -ne $Summary.Phases.StartComponentCleanup.ExitCode -and $Summary.Phases.StartComponentCleanup.ExitCode -ne 0) {
            $reasons.Add('StartComponentCleanup exited with a non-zero code.') | Out-Null
        }
    }

    if ($Summary.Modes.RunRepair) {
        if ($null -ne $Summary.Phases.DismRestoreHealth.ExitCode -and $Summary.Phases.DismRestoreHealth.ExitCode -ne 0) {
            if ((Get-SystemFilesCheckFinalDismState -Summary $Summary) -eq 'Healthy' -and $Summary.SfcFinalResult -notin @('CorruptionRemains', 'NonRepairable')) {
                $reasons.Add('RunRepair was requested but RestoreHealth returned a non-zero exit code.') | Out-Null
            }
        }
    }

    [ordered]@{
        Failed  = $reasons.Count -gt 0
        Reasons = @($reasons)
    }
}

function Test-SystemFilesCheckPreflightFailure {
    param([Parameter(Mandatory)]$Summary)

    $reasons = New-Object System.Collections.Generic.List[string]
    $mountedBefore = Get-SystemFilesCheckMemberValue -Object $Summary -Name 'MountedImageStateBeforeCleanup'
    $beforeState = [string](Get-SystemFilesCheckMemberValue -Object $mountedBefore -Name 'QueryState' -Default 'Unknown')
    if ($beforeState -eq 'FailedToQuery') {
        $reasons.Add('Mounted-image preflight query failed.') | Out-Null
    }

    $mountedAfter = Get-SystemFilesCheckMemberValue -Object $Summary -Name 'MountedImageStateAfterCleanup'
    $afterState = [string](Get-SystemFilesCheckMemberValue -Object $mountedAfter -Name 'QueryState' -Default 'Unknown')
    if ((Get-SystemFilesCheckMemberValue -Object (Get-SystemFilesCheckMemberValue -Object $Summary -Name 'Modes') -Name 'CleanupMountPoints' -Default $false) -and $afterState -eq 'FailedToQuery') {
        $reasons.Add('Mounted-image query after Cleanup-MountPoints failed.') | Out-Null
    }

    [ordered]@{
        Failed  = $reasons.Count -gt 0
        Reasons = @($reasons)
    }
}

function Compare-SystemFilesCheckRepairSourceToSystem {
    param(
        [Parameter(Mandatory)]$SystemIdentity,
        [Parameter(Mandatory)]$SourceIdentity
    )

    $matched = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $mismatches = New-Object System.Collections.Generic.List[string]

    $systemArch = Convert-SystemFilesCheckArchitectureValue -Value (Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'Architecture')
    $sourceArch = Convert-SystemFilesCheckArchitectureValue -Value (Get-SystemFilesCheckMemberValue -Object $SourceIdentity -Name 'Architecture')
    if ($systemArch -eq $sourceArch) {
        $matched.Add('Architecture matches.') | Out-Null
    }
    else {
        $mismatches.Add(('Architecture mismatch: system={0}, source={1}.' -f $systemArch, $sourceArch)) | Out-Null
    }

    $systemEdition = [string](Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'EditionId')
    $sourceEdition = [string](Get-SystemFilesCheckMemberValue -Object $SourceIdentity -Name 'EditionId')
    if ($systemEdition -eq $sourceEdition) {
        $matched.Add('EditionId matches.') | Out-Null
    }
    else {
        $mismatches.Add(('EditionId mismatch: system={0}, source={1}.' -f $systemEdition, $sourceEdition)) | Out-Null
    }

    $systemInstallType = [string](Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'InstallationType')
    $sourceInstallType = [string](Get-SystemFilesCheckMemberValue -Object $SourceIdentity -Name 'InstallationType')
    if ($systemInstallType -eq $sourceInstallType) {
        $matched.Add('InstallationType matches.') | Out-Null
    }
    else {
        $mismatches.Add(('InstallationType mismatch: system={0}, source={1}.' -f $systemInstallType, $sourceInstallType)) | Out-Null
    }

    $systemLanguageCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
            (Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'DefaultSystemUiLanguage'),
            (Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'SystemLocale'),
            (Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'InstallLanguage'),
            (Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'InstallLanguageFallback'))) {
        $normalizedCandidate = Convert-SystemFilesCheckLanguageValue -Value ([string]$candidate)
        if (-not [string]::IsNullOrWhiteSpace($normalizedCandidate) -and -not $systemLanguageCandidates.Contains($normalizedCandidate)) {
            $systemLanguageCandidates.Add($normalizedCandidate) | Out-Null
        }
    }

    foreach ($candidate in @((Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'MUILanguages' -Default @()) | Where-Object { $_ })) {
        $normalizedCandidate = Convert-SystemFilesCheckLanguageValue -Value ([string]$candidate)
        if (-not [string]::IsNullOrWhiteSpace($normalizedCandidate) -and -not $systemLanguageCandidates.Contains($normalizedCandidate)) {
            $systemLanguageCandidates.Add($normalizedCandidate) | Out-Null
        }
    }

    $sourceLanguages = New-Object System.Collections.Generic.List[string]
    foreach ($language in @((Get-SystemFilesCheckMemberValue -Object $SourceIdentity -Name 'Languages' -Default @()) | Where-Object { $_ })) {
        $normalizedLanguage = Convert-SystemFilesCheckLanguageValue -Value ([string]$language)
        if (-not [string]::IsNullOrWhiteSpace($normalizedLanguage) -and -not $sourceLanguages.Contains($normalizedLanguage)) {
            $sourceLanguages.Add($normalizedLanguage) | Out-Null
        }
    }

    $matchingLanguages = @($systemLanguageCandidates | Where-Object { $sourceLanguages.Contains($_) })
    if ($matchingLanguages.Count -gt 0) {
        $matched.Add(('Source languages match system language candidates: {0}.' -f ($matchingLanguages -join ', '))) | Out-Null
    }
    else {
        $mismatches.Add(('Source languages do not match any system language candidates. System={0}; Source={1}.' -f (($systemLanguageCandidates | Sort-Object -Unique) -join ', '), (($sourceLanguages | Sort-Object -Unique) -join ', '))) | Out-Null
    }

    $systemFamily = [string](Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'BuildFamily')
    $sourceFamily = [string](Get-SystemFilesCheckMemberValue -Object $SourceIdentity -Name 'BuildFamily')
    if ($systemFamily -eq $sourceFamily) {
        $matched.Add(('Build family matches: {0}.' -f $systemFamily)) | Out-Null
    }
    else {
        $mismatches.Add(('Build family mismatch: system={0}, source={1}.' -f $systemFamily, $sourceFamily)) | Out-Null
    }

    $systemBuild = [int](Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'CurrentBuild' -Default 0)
    $sourceBuild = [int](Get-SystemFilesCheckMemberValue -Object $SourceIdentity -Name 'CurrentBuild' -Default 0)
    $enablementPackageDetected = [bool](Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'EnablementPackageDetected' -Default $false)
    if ($systemBuild -eq $sourceBuild) {
        $matched.Add('Current build matches exactly.') | Out-Null
    }
    elseif ($systemFamily -eq '19041-family' -and $sourceFamily -eq '19041-family' -and $enablementPackageDetected) {
        $warnings.Add(('Current build differs (system={0}, source={1}), but the system is on the shared 19041 servicing family and the Windows 10 22H2 enablement package is installed.' -f $systemBuild, $sourceBuild)) | Out-Null
    }
    else {
        $mismatches.Add(('Current build differs without a recognized shared servicing-family explanation: system={0}, source={1}.' -f $systemBuild, $sourceBuild)) | Out-Null
    }

    $systemVersion = [string](Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'Version')
    $sourceVersion = [string](Get-SystemFilesCheckMemberValue -Object $SourceIdentity -Name 'Version')
    if ($systemVersion.StartsWith('10.0.') -and $sourceVersion.StartsWith('10.0.')) {
        $matched.Add('Major/minor OS version matches the Windows 10 family.') | Out-Null
    }
    elseif ($systemVersion -ne $sourceVersion) {
        $mismatches.Add(('Version mismatch: system={0}, source={1}.' -f $systemVersion, $sourceVersion)) | Out-Null
    }

    $displayVersion = [string](Get-SystemFilesCheckMemberValue -Object $SystemIdentity -Name 'DisplayVersion')
    if ($displayVersion -eq '22H2' -and $systemFamily -eq '19041-family' -and $sourceFamily -eq '19041-family') {
        $matched.Add('DisplayVersion 22H2 is compatible with the shared 19041 servicing family.') | Out-Null
    }

    $compatible = $mismatches.Count -eq 0
    $confidence = if (-not $compatible) { 'Low' } elseif ($warnings.Count -eq 0) { 'High' } else { 'Medium' }

    [ordered]@{
        IsCompatible    = $compatible
        ConfidenceLevel = $confidence
        MatchedChecks   = @($matched)
        Warnings        = @($warnings)
        Mismatches      = @($mismatches)
    }
}

function Get-SystemFilesCheckRebootRecommendation {
    param([Parameter(Mandatory)]$Summary)

    foreach ($phaseName in @('DismRestoreHealth', 'StartComponentCleanup', 'CleanupMountPoints')) {
        $phase = Get-SystemFilesCheckMemberValue -Object (Get-SystemFilesCheckMemberValue -Object $Summary -Name 'Phases') -Name $phaseName
        $details = Get-SystemFilesCheckMemberValue -Object $phase -Name 'Details'
        if ((Get-SystemFilesCheckMemberValue -Object $details -Name 'RebootRecommended' -Default $false)) {
            return $true
        }
    }

    return $false
}

function Resolve-SystemFilesCheckVerdict {
    param([Parameter(Mandatory)]$Summary)

    $exitCodes = Get-SystemFilesCheckExitCodes
    $preflightFailure = Test-SystemFilesCheckPreflightFailure -Summary $Summary
    $finalDismState = Get-SystemFilesCheckFinalDismState -Summary $Summary
    $finalSfcState = if ($Summary.Modes.RunRepair) { $Summary.SfcFinalResult } else { 'NotRun' }
    $repairRequested = [bool]$Summary.Modes.RunRepair
    $repairApplied = $Summary.DismRestoreHealthResult -eq 'Repaired' -or $finalSfcState -eq 'Repaired'
    $actionFailure = Test-SystemFilesCheckRequestedActionFailed -Summary $Summary
    $rebootRecommended = Get-SystemFilesCheckRebootRecommendation -Summary $Summary

    $result = [ordered]@{
        Category                 = 'ScriptError'
        ExitCode                 = $exitCodes.ScriptError
        Reason                   = 'The final state could not be classified.'
        ManualActionRecommended  = $true
        RebootRecommended        = $false
        FinalDismState           = $finalDismState
        FinalSfcState            = $finalSfcState
        RepairRequested          = $repairRequested
        RepairApplied            = $repairApplied
        RequestedActionFailed    = $actionFailure.Failed
        RequestedActionFailures  = $actionFailure.Reasons
    }

    if ($preflightFailure.Failed) {
        $result.Category = 'PreflightFailed'
        $result.ExitCode = $exitCodes.PreflightFailed
        $result.Reason = ($preflightFailure.Reasons -join ' ')
        return [pscustomobject]$result
    }

    if ($finalDismState -eq 'NonRepairable' -or $Summary.DismRestoreHealthResult -eq 'NonRepairable') {
        $result.Category = 'NonRepairable'
        $result.ExitCode = $exitCodes.NonRepairable
        $result.Reason = 'Final DISM health indicates that the component store is non-repairable.'
        return [pscustomobject]$result
    }

    if ($finalDismState -eq 'Repairable' -or $finalSfcState -eq 'CorruptionRemains' -or $Summary.DismRestoreHealthResult -in @('SourceMissing', 'Repairable')) {
        $result.Category = 'CorruptionRemains'
        $result.ExitCode = $exitCodes.CorruptionRemains
        $result.Reason = 'Final evidence still indicates repairable or unrepaired corruption.'
        return [pscustomobject]$result
    }

    if ($actionFailure.Failed) {
        $result.Category = 'RequestedActionFailed'
        $result.ExitCode = $exitCodes.RequestedActionFailed
        $result.Reason = ($actionFailure.Reasons -join ' ')
        return [pscustomobject]$result
    }

    if ($repairRequested -and $repairApplied -and $finalDismState -eq 'Healthy' -and $finalSfcState -notin @('CorruptionRemains', 'NonRepairable')) {
        if ($rebootRecommended -or ($Summary.PendingRebootAfterRun -and $repairApplied)) {
            $result.Category = 'RepairedButRebootRecommended'
            $result.ExitCode = $exitCodes.RepairedButRebootRecommended
            $result.Reason = 'Repairs were applied and a reboot is recommended before considering the system fully settled.'
            $result.RebootRecommended = $true
        }
        else {
            $result.Category = 'Repaired'
            $result.ExitCode = $exitCodes.Repaired
            $result.Reason = 'Repairs were applied and final health checks are healthy.'
        }
        $result.ManualActionRecommended = $false
        return [pscustomobject]$result
    }

    if ($finalDismState -eq 'Healthy' -and $finalSfcState -notin @('CorruptionRemains', 'NonRepairable')) {
        $result.Category = 'Healthy'
        $result.ExitCode = $exitCodes.Healthy
        $result.Reason = 'Final DISM health is healthy and no final unrepaired SFC evidence remains.'
        $result.ManualActionRecommended = $false
        return [pscustomobject]$result
    }

    if ($rebootRecommended -and $repairApplied) {
        $result.Category = 'RepairedButRebootRecommended'
        $result.ExitCode = $exitCodes.RepairedButRebootRecommended
        $result.Reason = 'Repairs were applied and the maintenance path requested a reboot.'
        $result.ManualActionRecommended = $false
        $result.RebootRecommended = $true
        return [pscustomobject]$result
    }

    [pscustomobject]$result
}

function Resolve-SystemFilesCheckOutcome {
    param(
        [Parameter(Mandatory)]$Summary,
        [AllowNull()]$ScriptFailure,
        [bool]$SelfTestPassed = $false
    )

    $exitCodes = Get-SystemFilesCheckExitCodes
    if ($ScriptFailure) {
        $failureExitCode = [int](Get-SystemFilesCheckMemberValue -Object $ScriptFailure -Name 'ExitCode' -Default $exitCodes.ScriptError)
        $failureMessage = [string](Get-SystemFilesCheckMemberValue -Object $ScriptFailure -Name 'Message' -Default 'The tool encountered an internal runtime problem.')
        $category = switch ($failureExitCode) {
            { $_ -eq $exitCodes.InvalidInput } { 'InvalidInput'; break }
            { $_ -eq $exitCodes.PreflightFailed } { 'PreflightFailed'; break }
            default { 'ScriptError' }
        }

        return [pscustomobject]@{
            Category                = $category
            ExitCode                = $failureExitCode
            Reason                  = $failureMessage
            ManualActionRecommended = $true
            RebootRecommended       = $false
            RequestedActionFailed   = $false
            RequestedActionFailures = @()
        }
    }

    if ($SelfTestPassed) {
        return [pscustomobject]@{
            Category                = 'Healthy'
            ExitCode                = $exitCodes.Healthy
            Reason                  = 'Self-tests completed successfully.'
            ManualActionRecommended = $false
            RebootRecommended       = $false
            RequestedActionFailed   = $false
            RequestedActionFailures = @()
        }
    }

    Resolve-SystemFilesCheckVerdict -Summary $Summary
}

function Get-SystemFilesCheckNextStepRecommendation {
    param(
        [Parameter(Mandatory)][string]$Category
    )

    switch ($Category) {
        'Healthy' { return 'No repair action is required. Keep the session logs for reference and rerun the tool only if new integrity symptoms appear.' }
        'Repaired' { return 'Repairs completed successfully. Keep the session folder and rerun a safe read-only check if you want confirmation from a fresh session.' }
        'RepairedButRebootRecommended' { return 'Repairs completed, but a reboot is recommended before treating the system as fully healthy. Reboot and rerun a safe validation pass.' }
        'CorruptionRemains' { return 'Corruption still appears to remain. Review final CBS SR evidence and DISM output, then rerun with a validated repair source or plan offline servicing.' }
        'NonRepairable' { return 'The component store appears non-repairable with the current evidence. Review the copied DISM and CBS logs and plan an in-place repair install or offline image repair strategy.' }
        'RequestedActionFailed' { return 'A requested maintenance action did not complete cleanly. Review the failed phase output and the mounted-image before/after state before rerunning.' }
        'InvalidInput' { return 'Correct the supplied arguments or repair-source specification and rerun the tool.' }
        'PreflightFailed' { return 'Resolve the preflight blocker before rerunning. Check elevation, restore-point policy, and environment prerequisites.' }
        default { return 'The tool encountered an internal runtime problem. Review Summary.json, Main.log, and the phase logs before rerunning.' }
    }
}

Export-ModuleMember -Function @(
    'Compare-SystemFilesCheckRepairSourceToSystem',
    'Convert-SystemFilesCheckArchitectureValue',
    'Convert-SystemFilesCheckToJsonSafeObject',
    'Format-SystemFilesCheckMountedImageInventoryDisplay',
    'Get-SystemFilesCheckToolVersion',
    'Get-SystemFilesCheckExitCodes',
    'New-SystemFilesCheckPhaseRecord',
    'Parse-SystemFilesCheckRepairSourceSpec',
    'Parse-SystemFilesCheckDismHealthOutput',
    'Parse-SystemFilesCheckDismRestoreOutput',
    'Parse-SystemFilesCheckAnalyzeComponentStoreOutput',
    'Parse-SystemFilesCheckMountedImageOutput',
    'Get-SystemFilesCheckMountedImageInventory',
    'Get-SystemFilesCheckSessionCbsSrLines',
    'Get-SystemFilesCheckSfcAssessmentFromLines',
    'Resolve-SystemFilesCheckBuildFamily',
    'Resolve-SystemFilesCheckOutcome',
    'Resolve-SystemFilesCheckRestorePointSummary',
    'Resolve-SystemFilesCheckVerdict',
    'Get-SystemFilesCheckNextStepRecommendation'
)
