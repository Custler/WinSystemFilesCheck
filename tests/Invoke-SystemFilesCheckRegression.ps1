param(
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent),
    [string]$JsonOut,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $RepositoryRoot -ChildPath 'lib\SystemFilesCheck.Core.psm1'
$mainScriptPath = Join-Path -Path $RepositoryRoot -ChildPath 'SystemFilesCheck.ps1'
$wrapperPath = Join-Path -Path $RepositoryRoot -ChildPath '0_SystemFilesCheck.cmd'
$fixturesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures'
$sourceValidationHelperPath = Join-Path -Path $RepositoryRoot -ChildPath 'tools\New-SystemFilesCheckSourceValidationReport.ps1'
$completenessCheckerPath = Join-Path -Path $RepositoryRoot -ChildPath 'tools\Test-SystemFilesCheckProjectCompleteness.ps1'
$bundleBuilderPath = Join-Path -Path $RepositoryRoot -ChildPath 'tools\Build-SystemFilesCheckRepoBundle.ps1'

Import-Module -Name $modulePath -Force -ErrorAction Stop -WarningAction SilentlyContinue
$exitCodes = Get-SystemFilesCheckExitCodes
$results = New-Object System.Collections.Generic.List[object]

function Add-TestResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Message
    )

    $record = [pscustomobject]@{
        Name    = $Name
        Passed  = $Passed
        Message = $Message
    }
    $script:results.Add($record) | Out-Null
    if (-not $Quiet) {
        $prefix = if ($Passed) { 'PASS' } else { 'FAIL' }
        Write-Host ('[{0}] {1} - {2}' -f $prefix, $Name, $Message)
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Get-PathValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Path
    )

    $current = $Object
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) {
            return $null
        }

        if ($current -is [System.Collections.IDictionary]) {
            $hasKey = if ($current.PSObject.Methods['ContainsKey']) {
                $current.ContainsKey($segment)
            }
            else {
                @($current.Keys) -contains $segment
            }
            if (-not $hasKey) {
                return $null
            }

            $current = $current[$segment]
            continue
        }

        $property = $current.PSObject.Properties[$segment]
        if (-not $property) {
            return $null
        }

        $current = $property.Value
    }

    return ,$current
}

function Assert-JsonPathIsArray {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][Nullable[int]]$ExpectedCount = $null
    )

    $value = Get-PathValue -Object $Object -Path $Path
    $isArrayLike = ($value -is [System.Array]) -or (($value -is [System.Collections.IList]) -and -not ($value -is [string]))
    Assert-True $isArrayLike ('{0} is not an array after JSON roundtrip.' -f $Path)
    if ($null -ne $ExpectedCount) {
        Assert-True (@($value).Count -eq $ExpectedCount) ('{0} count mismatch. Expected {1}, got {2}.' -f $Path, $ExpectedCount, @($value).Count)
    }
}

function Assert-JsonPathIsObject {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Path
    )

    $value = Get-PathValue -Object $Object -Path $Path
    Assert-True ($null -ne $value) ('{0} is null but an object was expected.' -f $Path)
    Assert-True (-not ($value -is [System.Array])) ('{0} became an array but should remain an object.' -f $Path)
}

function Convert-JsonRoundTrip {
    param([Parameter(Mandatory)]$InputObject)

    Add-Type -AssemblyName System.Web.Extensions
    $normalized = Convert-SystemFilesCheckToJsonSafeObject -InputObject $InputObject
    $jsonText = ConvertTo-Json -InputObject $normalized -Depth 10
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    [ordered]@{
        JsonText = $jsonText
        Object   = $serializer.DeserializeObject($jsonText)
    }
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$ScriptBlock)
    try {
        & $ScriptBlock
        Add-TestResult -Name $Name -Passed $true -Message 'Passed'
    }
    catch {
        Add-TestResult -Name $Name -Passed $false -Message $_.Exception.Message
    }
}

function New-VerdictSummary {
    [ordered]@{
        Modes                        = [ordered]@{ RunRepair = $false; RunCleanup = $false; CleanupMountPoints = $false; PreSFC = $false }
        DismCheckHealthResult        = 'NotRun'
        DismScanHealthResult         = 'NotRun'
        DismRestoreHealthResult      = 'Skipped'
        FinalDismCheckHealthResult   = 'NotRun'
        SfcBaselineResult            = 'NotRun'
        SfcFinalResult               = 'NotRun'
        SessionCannotRepairLineCount = 0
        PendingRebootAfterRun        = $false
        MountedImageStateBeforeCleanup = $null
        MountedImageStateAfterCleanup  = $null
        Phases                       = [ordered]@{
            DismRestoreHealth = [ordered]@{ ExitCode = 0; Details = [ordered]@{ RebootRecommended = $false } }
            StartComponentCleanup = [ordered]@{ ExitCode = $null; Details = [ordered]@{ RebootRecommended = $false } }
            CleanupMountPoints = [ordered]@{ ExitCode = $null; Details = [ordered]@{ RebootRecommended = $false } }
        }
    }
}

Invoke-Test 'syntax-main-script' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) 'Main script has syntax errors.'
}

Invoke-Test 'syntax-core-module' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) 'Core module has syntax errors.'
}

Invoke-Test 'syntax-source-validation-helper' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($sourceValidationHelperPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) 'Source-validation helper has syntax errors.'
}

Invoke-Test 'syntax-completeness-checker' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($completenessCheckerPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) 'Completeness checker has syntax errors.'
}

Invoke-Test 'syntax-bundle-builder' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($bundleBuilderPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) 'Bundle builder has syntax errors.'
}

Invoke-Test 'psscriptanalyzer-risk-check' {
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        return
    }

    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $paths = @($mainScriptPath, $modulePath, $PSCommandPath)
    $findings = foreach ($path in $paths) {
        Invoke-ScriptAnalyzer -Path $path -Severity Warning,Error
    }

    $riskyRules = @('PSPossibleIncorrectComparisonWithNull', 'PSAvoidUsingEmptyCatchBlock')
    $errors = @($findings | Where-Object { $_.Severity -eq 'Error' })
    $riskyWarnings = @($findings | Where-Object { $_.Severity -eq 'Warning' -and $_.RuleName -in $riskyRules })
    $riskyWarningNames = if ($riskyWarnings.Count -gt 0) {
        (($riskyWarnings | ForEach-Object { $_.RuleName } | Sort-Object -Unique) -join ', ')
    }
    else {
        ''
    }
    Assert-True ($errors.Count -eq 0) 'PSScriptAnalyzer returned errors.'
    Assert-True ($riskyWarnings.Count -eq 0) ('PSScriptAnalyzer returned risky warnings: {0}' -f $riskyWarningNames)
}

Invoke-Test 'ast-safety-no-invoke-expression' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$null, [ref]$null)
    $bad = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-Expression' }, $true)
    Assert-True (@($bad).Count -eq 0) 'Invoke-Expression was found in the main script.'
}

Invoke-Test 'ast-main-script-positional-binding-disabled' {
    $text = Get-Content -LiteralPath $mainScriptPath -Raw
    Assert-True ($text -match '\[CmdletBinding\(PositionalBinding\s*=\s*\$false\)\]') 'Main script does not disable positional binding.'
}

Invoke-Test 'main-script-no-unexported-module-helper-calls' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$null, [ref]$null)
    $localFunctions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
    $exportedNames = @((Get-Module SystemFilesCheck.Core).ExportedCommands.Keys)
    $moduleCommandNames = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -match '^(Get|Parse|Resolve|Compare|New|Test)-SystemFilesCheck'
            }, $true) | ForEach-Object { $_.GetCommandName() } | Sort-Object -Unique)
    $missing = @($moduleCommandNames | Where-Object { $_ -and $_ -notin $localFunctions -and $_ -notin $exportedNames })
    Assert-True ($missing.Count -eq 0) ('Main script references unexported SystemFilesCheck module helpers: {0}' -f ($missing -join ', '))
}

Invoke-Test 'wrapper-launcher-shape' {
    $text = Get-Content -LiteralPath $wrapperPath -Raw
    Assert-True ($text -match 'powershell\.exe') 'Wrapper does not call powershell.exe.'
    Assert-True ($text -match 'SystemFilesCheck\.ps1') 'Wrapper does not target SystemFilesCheck.ps1.'
    Assert-True ($text -match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe') 'Wrapper does not prefer the Windows PowerShell 5.1 path.'
    Assert-True ($text -match '%\*') 'Wrapper does not forward legacy arguments verbatim.'
}

Invoke-Test 'legacyargs-empty-string-ignored' {
    $text = Get-Content -LiteralPath $mainScriptPath -Raw
    Assert-True ($text -match 'Where-Object\s*\{\s*-not\s+\[string\]::IsNullOrWhiteSpace\(\$_\)\s*\}') 'Legacy argument parsing does not explicitly ignore empty arguments.'
}

Invoke-Test 'main-script-no-cmd-c-shelling' {
    $text = Get-Content -LiteralPath $mainScriptPath -Raw
    Assert-True ($text -notmatch '(?i)\bcmd(\.exe)?\s+/d\s+/c\b' -and $text -notmatch '(?i)\bcmd(\.exe)?\s+/c\b') 'The main script still shells out through cmd /c.'
}

Invoke-Test 'main-script-no-inline-if-argument-expressions' {
    $text = Get-Content -LiteralPath $mainScriptPath -Raw
    Assert-True ($text -notmatch '-[A-Za-z0-9]+\s+\(if\s*\(') 'The main script still contains an inline if-expression used directly as a command argument.'
}

Invoke-Test 'repair-source-parser-folder-wim-esd' {
    $folder = Parse-SystemFilesCheckRepairSourceSpec -Value 'C:\RepairSource'
    $wim = Parse-SystemFilesCheckRepairSourceSpec -Value 'wim:D:\sources\install.wim:1'
    $esd = Parse-SystemFilesCheckRepairSourceSpec -Value 'esd:D:\sources\install.esd:6'
    Assert-True ($folder.Type -eq 'folder') 'Folder source parsing failed.'
    Assert-True ($wim.Type -eq 'wim' -and $wim.Path -eq 'D:\sources\install.wim' -and $wim.Index -eq 1) 'WIM source parsing failed.'
    Assert-True ($esd.Type -eq 'esd' -and $esd.Path -eq 'D:\sources\install.esd' -and $esd.Index -eq 6) 'ESD source parsing failed.'
}

Invoke-Test 'repair-source-metadata-fallbacks' {
    $text = Get-Content -LiteralPath $mainScriptPath -Raw
    Assert-True ($text -match '\$image\.PSObject\.Properties\[''SPBuild''\]') 'Repair source metadata extraction does not include the SPBuild fallback.'
    Assert-True ($text -match '\$image\.PSObject\.Properties\[''SPLevel''\]') 'Repair source metadata extraction does not include the SPLevel fallback.'
}

Invoke-Test 'summary-json-contract-collections' {
    $source = [ordered]@{
        RequestedActionFailures = @()
        Warnings = @('one-warning')
        Errors = @('error-1', 'error-2')
        MountedImageStateBeforeCleanup = [ordered]@{
            Images = @()
            Statuses = @('OK')
        }
        MountedImageStateAfterCleanup = [ordered]@{
            Images = @([ordered]@{ MountDir = 'C:\Mount'; Status = 'Invalid' })
            Statuses = @()
        }
        RepairSourceValidation = [ordered]@{
            ImageMetadata = [ordered]@{
                Languages = @('ru-RU')
            }
            Compatibility = [ordered]@{
                Warnings = @('shared-servicing-family')
                Mismatches = @()
                MatchedChecks = @('Architecture matches.', 'EditionId matches.')
            }
        }
        Notes = @('note-1')
    }

    $roundTrip = Convert-JsonRoundTrip -InputObject $source
    $parsed = $roundTrip.Object

    Assert-JsonPathIsArray -Object $parsed -Path 'RequestedActionFailures' -ExpectedCount 0
    Assert-JsonPathIsArray -Object $parsed -Path 'Warnings' -ExpectedCount 1
    Assert-JsonPathIsArray -Object $parsed -Path 'Errors' -ExpectedCount 2
    Assert-JsonPathIsObject -Object $parsed -Path 'MountedImageStateBeforeCleanup'
    Assert-JsonPathIsArray -Object $parsed -Path 'MountedImageStateBeforeCleanup.Images' -ExpectedCount 0
    Assert-JsonPathIsArray -Object $parsed -Path 'MountedImageStateBeforeCleanup.Statuses' -ExpectedCount 1
    Assert-JsonPathIsObject -Object $parsed -Path 'MountedImageStateAfterCleanup'
    Assert-JsonPathIsArray -Object $parsed -Path 'MountedImageStateAfterCleanup.Images' -ExpectedCount 1
    Assert-JsonPathIsArray -Object $parsed -Path 'MountedImageStateAfterCleanup.Statuses' -ExpectedCount 0
    Assert-JsonPathIsObject -Object $parsed -Path 'RepairSourceValidation'
    Assert-JsonPathIsObject -Object $parsed -Path 'RepairSourceValidation.Compatibility'
    Assert-JsonPathIsArray -Object $parsed -Path 'RepairSourceValidation.Compatibility.Warnings' -ExpectedCount 1
    Assert-JsonPathIsArray -Object $parsed -Path 'RepairSourceValidation.Compatibility.Mismatches' -ExpectedCount 0
    Assert-JsonPathIsArray -Object $parsed -Path 'RepairSourceValidation.Compatibility.MatchedChecks' -ExpectedCount 2
    Assert-JsonPathIsArray -Object $parsed -Path 'RepairSourceValidation.ImageMetadata.Languages' -ExpectedCount 1
    Assert-JsonPathIsArray -Object $parsed -Path 'Notes' -ExpectedCount 1
}

Invoke-Test 'summary-json-contract-result-paths' {
    $categories = @('Healthy', 'Repaired', 'RepairedButRebootRecommended', 'CorruptionRemains', 'NonRepairable', 'RequestedActionFailed', 'InvalidInput', 'PreflightFailed', 'ScriptError')
    foreach ($category in $categories) {
        $source = [ordered]@{
            OverallResultCategory = $category
            RequestedActionFailures = @()
            Warnings = @(if ($category -in @('InvalidInput', 'PreflightFailed')) { 'warning-only' })
            Errors = @(if ($category -eq 'ScriptError') { 'internal failure' })
            MountedImageStateBeforeCleanup = if ($category -eq 'InvalidInput') {
                $null
            } else {
                [ordered]@{
                    Images = @()
                    Statuses = @()
                }
            }
            MountedImageStateAfterCleanup = if ($category -eq 'RequestedActionFailed') {
                [ordered]@{
                    Images = @([ordered]@{ Status = 'Invalid' })
                    Statuses = @('Invalid')
                }
            } else {
                $null
            }
            RepairSourceValidation = [ordered]@{
                Compatibility = if ($category -in @('InvalidInput', 'ScriptError')) {
                    $null
                } else {
                    [ordered]@{
                        Warnings = @()
                        Mismatches = @(if ($category -in @('CorruptionRemains', 'NonRepairable')) { 'mismatch-1' })
                    }
                }
            }
        }

        $parsed = (Convert-JsonRoundTrip -InputObject $source).Object
        Assert-JsonPathIsArray -Object $parsed -Path 'RequestedActionFailures' -ExpectedCount 0
        Assert-JsonPathIsArray -Object $parsed -Path 'Warnings'
        Assert-JsonPathIsArray -Object $parsed -Path 'Errors'
        if ($category -ne 'InvalidInput') {
            Assert-JsonPathIsObject -Object $parsed -Path 'MountedImageStateBeforeCleanup'
            Assert-JsonPathIsArray -Object $parsed -Path 'MountedImageStateBeforeCleanup.Images' -ExpectedCount 0
            Assert-JsonPathIsArray -Object $parsed -Path 'MountedImageStateBeforeCleanup.Statuses' -ExpectedCount 0
        }
        if ($category -notin @('InvalidInput', 'ScriptError')) {
            Assert-JsonPathIsObject -Object $parsed -Path 'RepairSourceValidation.Compatibility'
            Assert-JsonPathIsArray -Object $parsed -Path 'RepairSourceValidation.Compatibility.Warnings' -ExpectedCount 0
            if ($category -in @('CorruptionRemains', 'NonRepairable')) {
                Assert-JsonPathIsArray -Object $parsed -Path 'RepairSourceValidation.Compatibility.Mismatches' -ExpectedCount 1
            }
            else {
                Assert-JsonPathIsArray -Object $parsed -Path 'RepairSourceValidation.Compatibility.Mismatches' -ExpectedCount 0
            }
        }
    }
}

Invoke-Test 'dism-health-fixtures' {
    $healthy = Parse-SystemFilesCheckDismHealthOutput -Text (Get-Content -LiteralPath (Join-Path $fixturesRoot 'dism-check-healthy.txt') -Raw)
    $repairable = Parse-SystemFilesCheckDismHealthOutput -Text (Get-Content -LiteralPath (Join-Path $fixturesRoot 'dism-check-repairable.txt') -Raw)
    $nonrepairable = Parse-SystemFilesCheckDismHealthOutput -Text (Get-Content -LiteralPath (Join-Path $fixturesRoot 'dism-check-nonrepairable.txt') -Raw)
    Assert-True ($healthy.Status -eq 'Healthy') 'Healthy fixture parsed incorrectly.'
    Assert-True ($repairable.Status -eq 'Repairable') 'Repairable fixture parsed incorrectly.'
    Assert-True ($nonrepairable.Status -eq 'NonRepairable') 'Non-repairable fixture parsed incorrectly.'
}

Invoke-Test 'dism-restore-fixtures' {
    $success = Parse-SystemFilesCheckDismRestoreOutput -Text (Get-Content -LiteralPath (Join-Path $fixturesRoot 'dism-restore-success.txt') -Raw)
    $sourceMissing = Parse-SystemFilesCheckDismRestoreOutput -Text (Get-Content -LiteralPath (Join-Path $fixturesRoot 'dism-restore-source-missing.txt') -Raw)
    Assert-True ($success.Status -eq 'Repaired') 'Restore success fixture parsed incorrectly.'
    Assert-True ($sourceMissing.Status -eq 'SourceMissing') 'Restore source-missing fixture parsed incorrectly.'
}

Invoke-Test 'analyze-component-store-fixture' {
    $parsed = Parse-SystemFilesCheckAnalyzeComponentStoreOutput -Text (Get-Content -LiteralPath (Join-Path $fixturesRoot 'analyze-componentstore-basic.txt') -Raw)
    Assert-True ($parsed.ActualSizeOfComponentStore -eq '8.76 GB') 'Actual size parsing failed.'
    Assert-True ($parsed.ComponentStoreCleanupRecommended -eq 'Yes') 'Cleanup recommendation parsing failed.'
}

Invoke-Test 'mounted-image-parser-regressions' {
    $cases = @(
        @{ File = 'mounted-none.txt'; Count = 0; Invalid = $false; NeedsRemount = $false },
        @{ File = 'mounted-one-ok.txt'; Count = 1; Invalid = $false; NeedsRemount = $false },
        @{ File = 'mounted-one-invalid.txt'; Count = 1; Invalid = $true; NeedsRemount = $false },
        @{ File = 'mounted-one-needs-remount.txt'; Count = 1; Invalid = $false; NeedsRemount = $true },
        @{ File = 'mounted-multiple-mixed.txt'; Count = 3; Invalid = $true; NeedsRemount = $true }
    )

    foreach ($case in $cases) {
        $parsed = Parse-SystemFilesCheckMountedImageOutput -Text (Get-Content -LiteralPath (Join-Path $fixturesRoot $case.File) -Raw)
        $inventory = Get-SystemFilesCheckMountedImageInventory -MountedImages $parsed
        Assert-True ($inventory.ImageCount -eq $case.Count) ('Unexpected image count for {0}.' -f $case.File)
        Assert-True ($inventory.AnyInvalid -eq $case.Invalid) ('Unexpected invalid state for {0}.' -f $case.File)
        Assert-True ($inventory.AnyNeedsRemount -eq $case.NeedsRemount) ('Unexpected remount state for {0}.' -f $case.File)
        if ($case.Count -gt 0) {
            Assert-True ([bool]$parsed[0].PSObject.Properties['Status']) ('Normalized Status property is missing for {0}.' -f $case.File)
            Assert-True ([bool]$parsed[0].PSObject.Properties['StatusRaw']) ('StatusRaw property is missing for {0}.' -f $case.File)
            Assert-True (-not [bool]$parsed[0].PSObject.Properties['MountStatus']) ('Unexpected legacy MountStatus property remained for {0}.' -f $case.File)
        }
    }
}

Invoke-Test 'mounted-image-display-formatting' {
    $noneText = Format-SystemFilesCheckMountedImageInventoryDisplay -Inventory ([ordered]@{ QueryState = 'Empty'; ImageCount = 0; Statuses = @() })
    $someText = Format-SystemFilesCheckMountedImageInventoryDisplay -Inventory ([ordered]@{ QueryState = 'Available'; ImageCount = 2; Statuses = @('OK', 'Invalid') })
    $unknownText = Format-SystemFilesCheckMountedImageInventoryDisplay -Inventory $null -UnknownText 'Not collected'
    $failedText = Format-SystemFilesCheckMountedImageInventoryDisplay -Inventory ([ordered]@{ QueryState = 'FailedToQuery'; ImageCount = $null; Statuses = @() })
    Assert-True ($noneText -eq 'None') 'Mounted-image display should show None when there are no mounted images.'
    Assert-True ($someText -eq 'OK, Invalid') 'Mounted-image display did not join statuses correctly.'
    Assert-True ($unknownText -eq 'Not collected') 'Mounted-image display did not honor the custom unknown text.'
    Assert-True ($failedText -eq 'Failed to query') 'Mounted-image display did not expose query failure honestly.'
}

Invoke-Test 'mounted-image-query-failure-inventory' {
    $inventory = Get-SystemFilesCheckMountedImageInventory -MountedImages @() -QueryState 'FailedToQuery' -QueryExitCode 87 -QueryMessage 'Get-MountedImageInfo returned a non-zero exit code.'
    Assert-True ($inventory.QueryState -eq 'FailedToQuery') 'Mounted-image inventory did not preserve the failed query state.'
    Assert-True ($null -eq $inventory.ImageCount) 'Mounted-image query failure should not report ImageCount=0.'
    Assert-True ($null -eq $inventory.AnyInvalid) 'Mounted-image query failure should not report AnyInvalid=false.'
    Assert-True ($inventory.QueryExitCode -eq 87) 'Mounted-image query failure did not preserve the exit code.'
}

Invoke-Test 'cbs-sfc-assessment-fixtures' {
    $healthy = Get-SystemFilesCheckSfcAssessmentFromLines -Lines (Get-Content -LiteralPath (Join-Path $fixturesRoot 'cbs-sr-healthy.txt')) -Label 'HealthyFixture'
    $repaired = Get-SystemFilesCheckSfcAssessmentFromLines -Lines (Get-Content -LiteralPath (Join-Path $fixturesRoot 'cbs-sr-repaired.txt')) -Label 'RepairedFixture'
    $zeroRepair = Get-SystemFilesCheckSfcAssessmentFromLines -Lines (Get-Content -LiteralPath (Join-Path $fixturesRoot 'cbs-sr-repairing-zero-components.txt')) -Label 'ZeroRepairFixture'
    $cannotRepair = Get-SystemFilesCheckSfcAssessmentFromLines -Lines (Get-Content -LiteralPath (Join-Path $fixturesRoot 'cbs-sr-cannot-repair.txt')) -Label 'CannotRepairFixture'
    Assert-True ($healthy.Status -eq 'Healthy') 'Healthy CBS fixture parsed incorrectly.'
    Assert-True ($repaired.Status -eq 'Repaired') 'Repaired CBS fixture parsed incorrectly.'
    Assert-True ($zeroRepair.Status -eq 'Healthy') 'Zero-repair CBS fixture should remain Healthy.'
    Assert-True ($cannotRepair.Status -eq 'CorruptionRemains') 'Cannot-repair CBS fixture parsed incorrectly.'
}

Invoke-Test 'cbs-rollover-persist-evidence' {
    $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('systemfilescheck-fixture-{0}' -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $persistPath = Join-Path -Path $tempRoot -ChildPath 'CBS.persist.log'
        $livePath = Join-Path -Path $tempRoot -ChildPath 'CBS.log'
        Copy-Item -LiteralPath (Join-Path $fixturesRoot 'cbs-persist-rollover.txt') -Destination $persistPath -Force
        Copy-Item -LiteralPath (Join-Path $fixturesRoot 'cbs-sr-repaired.txt') -Destination $livePath -Force
        $lines = Get-SystemFilesCheckSessionCbsSrLines -Paths @($persistPath, $livePath) -StartTime ([datetime]'2026-03-08T08:59:59') -EndTime ([datetime]'2026-03-08T09:00:10')
        Assert-True (@($lines).Count -eq 5) 'Rollover extraction did not merge CBS.log and CBS.persist.log correctly.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

Invoke-Test 'verdict-matrix' {
    $matrix = Get-Content -LiteralPath (Join-Path $fixturesRoot 'verdict-matrix.json') -Raw | ConvertFrom-Json
    foreach ($case in $matrix) {
        $summary = New-VerdictSummary
        foreach ($property in $case.Input.PSObject.Properties.Name) {
            switch ($property) {
                'Modes' {
                    foreach ($modeName in $case.Input.Modes.PSObject.Properties.Name) {
                        $summary.Modes[$modeName] = [bool]$case.Input.Modes.$modeName
                    }
                }
                'PhaseExitCodes' {
                    foreach ($phaseName in $case.Input.PhaseExitCodes.PSObject.Properties.Name) {
                        $summary.Phases[$phaseName].ExitCode = [int]$case.Input.PhaseExitCodes.$phaseName
                    }
                }
                'PhaseDetails' {
                    foreach ($phaseName in $case.Input.PhaseDetails.PSObject.Properties.Name) {
                        foreach ($detailName in $case.Input.PhaseDetails.$phaseName.PSObject.Properties.Name) {
                            $summary.Phases[$phaseName].Details[$detailName] = $case.Input.PhaseDetails.$phaseName.$detailName
                        }
                    }
                }
                default {
                    $summary[$property] = $case.Input.$property
                }
            }
        }

        $verdict = Resolve-SystemFilesCheckVerdict -Summary $summary
        Assert-True ($verdict.Category -eq $case.ExpectedCategory) ('Verdict category mismatch for {0}. Expected {1}, got {2}.' -f $case.Name, $case.ExpectedCategory, $verdict.Category)
        Assert-True ($verdict.ExitCode -eq $case.ExpectedExitCode) ('Exit code mismatch for {0}. Expected {1}, got {2}.' -f $case.Name, $case.ExpectedExitCode, $verdict.ExitCode)
        $recommendation = Get-SystemFilesCheckNextStepRecommendation -Category $verdict.Category
        Assert-True (-not [string]::IsNullOrWhiteSpace($recommendation)) ('Recommendation is empty for {0}.' -f $case.Name)
        if ($verdict.Category -in @('Healthy', 'Repaired', 'RepairedButRebootRecommended')) {
            Assert-True (-not $verdict.ManualActionRecommended) ('Manual action should not be recommended for {0}.' -f $case.Name)
        }
        else {
            Assert-True ($verdict.ManualActionRecommended) ('Manual action should be recommended for {0}.' -f $case.Name)
        }
    }
}

Invoke-Test 'outcome-matrix' {
    $matrix = Get-Content -LiteralPath (Join-Path $fixturesRoot 'outcome-matrix.json') -Raw | ConvertFrom-Json
    foreach ($case in $matrix) {
        $summary = New-VerdictSummary
        if ($case.PSObject.Properties['SummaryInput']) {
            foreach ($property in $case.SummaryInput.PSObject.Properties.Name) {
                switch ($property) {
                    'Modes' {
                        foreach ($modeName in $case.SummaryInput.Modes.PSObject.Properties.Name) {
                            $summary.Modes[$modeName] = [bool]$case.SummaryInput.Modes.$modeName
                        }
                    }
                    default {
                        $summary[$property] = $case.SummaryInput.$property
                    }
                }
            }
        }

        $scriptFailure = if ($case.PSObject.Properties['ScriptFailure']) { $case.ScriptFailure } else { $null }
        $selfTestPassed = if ($case.PSObject.Properties['SelfTestPassed']) { [bool]$case.SelfTestPassed } else { $false }
        $outcome = Resolve-SystemFilesCheckOutcome -Summary $summary -ScriptFailure $scriptFailure -SelfTestPassed $selfTestPassed
        Assert-True ($outcome.Category -eq $case.ExpectedCategory) ('Outcome category mismatch for {0}. Expected {1}, got {2}.' -f $case.Name, $case.ExpectedCategory, $outcome.Category)
        Assert-True ($outcome.ExitCode -eq $case.ExpectedExitCode) ('Outcome exit code mismatch for {0}. Expected {1}, got {2}.' -f $case.Name, $case.ExpectedExitCode, $outcome.ExitCode)
        Assert-True ($outcome.ManualActionRecommended -eq [bool]$case.ExpectedManualAction) ('Outcome manual-action flag mismatch for {0}.' -f $case.Name)
        Assert-True (-not [string]::IsNullOrWhiteSpace($outcome.Reason)) ('Outcome reason is empty for {0}.' -f $case.Name)
    }
}

Invoke-Test 'restore-point-matrix' {
    $matrix = Get-Content -LiteralPath (Join-Path $fixturesRoot 'restorepoint-matrix.json') -Raw | ConvertFrom-Json
    foreach ($case in $matrix) {
        $resolved = Resolve-SystemFilesCheckRestorePointSummary -Relevant ([bool]$case.Input.Relevant) -Attempted ([bool]$case.Input.Attempted) -Succeeded ([bool]$case.Input.Succeeded) -Required ([bool]$case.Input.Required) -SkippedByPolicy ([bool]$case.Input.SkippedByPolicy) -AbortedExecution ([bool]$case.Input.AbortedExecution)
        Assert-True ($resolved.Outcome -eq $case.ExpectedOutcome) ('Restore-point outcome mismatch for {0}. Expected {1}, got {2}.' -f $case.Name, $case.ExpectedOutcome, $resolved.Outcome)
        Assert-True ($resolved.ContinueWithoutRestorePoint -eq [bool]$case.ExpectedContinueWithoutRestorePoint) ('Restore-point ContinueWithoutRestorePoint mismatch for {0}.' -f $case.Name)
        Assert-True ($resolved.ExecutionContinued -eq [bool]$case.ExpectedExecutionContinued) ('Restore-point ExecutionContinued mismatch for {0}.' -f $case.Name)
    }
}

Invoke-Test 'source-validation-matrix' {
    $matrix = Get-Content -LiteralPath (Join-Path $fixturesRoot 'source-validation-matrix.json') -Raw | ConvertFrom-Json
    foreach ($case in $matrix) {
        $comparison = Compare-SystemFilesCheckRepairSourceToSystem -SystemIdentity $case.SystemIdentity -SourceIdentity $case.SourceIdentity
        Assert-True ($comparison.IsCompatible -eq [bool]$case.ExpectedCompatible) ('Source compatibility mismatch for {0}.' -f $case.Name)
        Assert-True ($comparison.ConfidenceLevel -eq $case.ExpectedConfidence) ('Source confidence mismatch for {0}. Expected {1}, got {2}.' -f $case.Name, $case.ExpectedConfidence, $comparison.ConfidenceLevel)
        if ($comparison.IsCompatible) {
            Assert-True (@($comparison.Mismatches).Count -eq 0) ('Compatible comparison for {0} still reported mismatches.' -f $case.Name)
        }
        else {
            Assert-True (@($comparison.Mismatches).Count -gt 0) ('Incompatible comparison for {0} did not report mismatches.' -f $case.Name)
        }
    }
}

Invoke-Test 'toolversion-consistency' {
    $version = Get-SystemFilesCheckToolVersion
    $mainText = Get-Content -LiteralPath $mainScriptPath -Raw
    $readmePath = Join-Path -Path $RepositoryRoot -ChildPath 'README.md'
    $legacyReadmePath = Join-Path -Path $RepositoryRoot -ChildPath 'SystemFilesCheck_README.md'
    $auditPath = Join-Path -Path $RepositoryRoot -ChildPath 'docs\AUDIT.md'
    $legacyAuditPath = Join-Path -Path $RepositoryRoot -ChildPath 'SystemFilesCheck_Audit.md'
    $manualPath = Join-Path -Path $RepositoryRoot -ChildPath 'docs\MANUAL.md'
    $changelogPath = Join-Path -Path $RepositoryRoot -ChildPath 'CHANGELOG.md'
    $readmeText = Get-Content -LiteralPath $readmePath -Raw
    $auditText = Get-Content -LiteralPath $auditPath -Raw
    $legacyReadmeText = Get-Content -LiteralPath $legacyReadmePath -Raw
    $legacyAuditText = Get-Content -LiteralPath $legacyAuditPath -Raw
    $manualText = Get-Content -LiteralPath $manualPath -Raw
    $changelogText = Get-Content -LiteralPath $changelogPath -Raw
    Assert-True ($mainText -match 'Tool version\s+:') 'Summary text writer does not emit the tool version line.'
    Assert-True ($readmeText -match [regex]::Escape($version)) 'README does not mention the current tool version.'
    Assert-True ($auditText -match [regex]::Escape($version)) 'Audit does not mention the current tool version.'
    Assert-True ($legacyReadmeText -match [regex]::Escape($version)) 'Compatibility README does not mention the current tool version.'
    Assert-True ($legacyAuditText -match [regex]::Escape($version)) 'Compatibility audit note does not mention the current tool version.'
    Assert-True ($manualText -match [regex]::Escape($version)) 'Manual does not mention the current tool version.'
    Assert-True ($changelogText -match [regex]::Escape($version)) 'Change log does not mention the current tool version.'
}

Invoke-Test 'project-completeness-self-check' {
    & $completenessCheckerPath -RepositoryRoot $RepositoryRoot -Quiet | Out-Null
}

Invoke-Test 'exit-code-map' {
    Assert-True ($exitCodes.Healthy -eq 0) 'Healthy exit code mismatch.'
    Assert-True ($exitCodes.Repaired -eq 10) 'Repaired exit code mismatch.'
    Assert-True ($exitCodes.RepairedButRebootRecommended -eq 11) 'RepairedButRebootRecommended exit code mismatch.'
    Assert-True ($exitCodes.CorruptionRemains -eq 20) 'CorruptionRemains exit code mismatch.'
    Assert-True ($exitCodes.NonRepairable -eq 21) 'NonRepairable exit code mismatch.'
    Assert-True ($exitCodes.RequestedActionFailed -eq 22) 'RequestedActionFailed exit code mismatch.'
    Assert-True ($exitCodes.InvalidInput -eq 30) 'InvalidInput exit code mismatch.'
    Assert-True ($exitCodes.PreflightFailed -eq 31) 'PreflightFailed exit code mismatch.'
    Assert-True ($exitCodes.ScriptError -eq 40) 'ScriptError exit code mismatch.'
}

$failed = @($results | Where-Object { -not $_.Passed })
$summary = [pscustomobject]@{
    RepositoryRoot = $RepositoryRoot
    Total          = $results.Count
    Passed         = $results.Count - $failed.Count
    Failed         = $failed.Count
    Results        = $results
}

if ($JsonOut) {
    $directory = Split-Path -Path $JsonOut -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    ConvertTo-Json -InputObject $summary -Depth 8 | Set-Content -LiteralPath $JsonOut -Encoding UTF8
}

if (-not $Quiet) {
    Write-Host ('Total tests: {0} Passed: {1} Failed: {2}' -f $summary.Total, $summary.Passed, $summary.Failed)
}

if ($failed.Count -gt 0) {
    exit 1
}

exit 0
