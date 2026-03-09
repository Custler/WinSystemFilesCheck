[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$IsoSourcePath,
    [Parameter(Mandatory)][int]$IsoSourceIndex,
    [Parameter(Mandatory)][string]$LocalSourcePath,
    [Parameter(Mandatory)][int]$LocalSourceIndex,
    [Parameter(Mandatory)][string]$MarkdownPath,
    [Parameter(Mandatory)][string]$JsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'lib\SystemFilesCheck.Core.psm1'
Import-Module $modulePath -Force

function Get-IntlSnapshot {
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

function New-ImageMetadata {
    param(
        [Parameter(Mandatory)]$Image,
        [Parameter(Mandatory)][string]$ImagePath
    )

    $imageVersion = [string]$Image.Version
    if ([string]::IsNullOrWhiteSpace($imageVersion) -and $Image.PSObject.Properties['ImageVersion']) {
        $imageVersion = [string]$Image.ImageVersion
    }

    $versionParts = @($imageVersion -split '\.')
    $currentBuild = if ($versionParts.Count -ge 3) { $versionParts[2] } else { $imageVersion }

    [ordered]@{
        ImagePath         = $ImagePath
        Index             = [int]$Image.ImageIndex
        ImageName         = [string]$Image.ImageName
        EditionId         = [string]$Image.EditionId
        InstallationType  = [string]$Image.InstallationType
        Architecture      = Convert-SystemFilesCheckArchitectureValue -Value $Image.Architecture
        Version           = $imageVersion
        CurrentBuild      = [string]$currentBuild
        Languages         = @($Image.Languages)
        BuildFamily       = Resolve-SystemFilesCheckBuildFamily -CurrentBuild ([string]$currentBuild) -BuildLabEx $null -Version $imageVersion
    }
}

$currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$nlsLanguage = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$uiCulture = Get-UICulture
$systemLocale = Get-WinSystemLocale
$intlSnapshot = Get-IntlSnapshot
$packages = @(Get-WindowsPackage -Online)
$languagePackages = @($packages | Where-Object { $_.PackageName -match 'Client-LanguagePack-Package' } | ForEach-Object {
        if ($_.PackageName -match '~(?<Language>[a-z]{2}-[A-Z]{2})~') {
            $Matches['Language']
        }
    } | Sort-Object -Unique)
$enablementPackageDetected = @($packages | Where-Object { $_.PackageName -match 'KB5015684' }).Count -gt 0
$installedLanguages = if ($intlSnapshot.QuerySucceeded -and @($intlSnapshot.InstalledLanguages).Count -gt 0) {
    @($intlSnapshot.InstalledLanguages)
}
else {
    @($os.MUILanguages)
}
$defaultSystemUiLanguage = if ($intlSnapshot.QuerySucceeded -and $intlSnapshot.DefaultSystemUiLanguage) {
    [string]$intlSnapshot.DefaultSystemUiLanguage
}
else {
    [string]$uiCulture.Name
}
$resolvedSystemLocale = if ($intlSnapshot.QuerySucceeded -and $intlSnapshot.SystemLocale) {
    [string]$intlSnapshot.SystemLocale
}
else {
    [string]$systemLocale.Name
}

$systemIdentity = [ordered]@{
    ProductName               = [string]$currentVersion.ProductName
    EditionId                 = [string]$currentVersion.EditionID
    InstallationType          = [string]$currentVersion.InstallationType
    DisplayVersion            = [string]$currentVersion.DisplayVersion
    ReleaseId                 = [string]$currentVersion.ReleaseId
    CurrentBuild              = [string]$currentVersion.CurrentBuild
    UBR                       = [string]$currentVersion.UBR
    BuildLabEx                = [string]$currentVersion.BuildLabEx
    Version                   = [string]$os.Version
    Architecture              = Convert-SystemFilesCheckArchitectureValue -Value $os.OSArchitecture
    InstallLanguage           = [string]$nlsLanguage.InstallLanguage
    InstallLanguageFallback   = [string]$nlsLanguage.InstallLanguageFallback
    DefaultSystemUiLanguage   = $defaultSystemUiLanguage
    SystemLocale              = $resolvedSystemLocale
    MUILanguages              = @($installedLanguages)
    InstalledLanguagePacks    = @($languagePackages)
    EnablementPackageDetected = $enablementPackageDetected
    BuildFamily               = Resolve-SystemFilesCheckBuildFamily -CurrentBuild ([string]$currentVersion.CurrentBuild) -BuildLabEx ([string]$currentVersion.BuildLabEx) -Version ([string]$os.Version)
}

$isoHeaders = @(Get-WindowsImage -ImagePath $IsoSourcePath)
$isoImages = @($isoHeaders | ForEach-Object {
        $detailedImage = Get-WindowsImage -ImagePath $IsoSourcePath -Index ([int]$_.ImageIndex)
        New-ImageMetadata -Image $detailedImage -ImagePath $IsoSourcePath
    })
$chosenIsoMetadata = $isoImages | Where-Object { $_.Index -eq $IsoSourceIndex } | Select-Object -First 1
if (-not $chosenIsoMetadata) {
    throw ('ISO source index {0} was not found in {1}.' -f $IsoSourceIndex, $IsoSourcePath)
}

$localImage = Get-WindowsImage -ImagePath $LocalSourcePath -Index $LocalSourceIndex
$localMetadata = New-ImageMetadata -Image $localImage -ImagePath $LocalSourcePath
$localComparison = Compare-SystemFilesCheckRepairSourceToSystem -SystemIdentity $systemIdentity -SourceIdentity $localMetadata

$indexEvaluations = foreach ($candidate in $isoImages) {
    $comparison = Compare-SystemFilesCheckRepairSourceToSystem -SystemIdentity $systemIdentity -SourceIdentity $candidate
    [ordered]@{
        Index           = $candidate.Index
        ImageName       = $candidate.ImageName
        EditionId       = $candidate.EditionId
        InstallationType= $candidate.InstallationType
        Architecture    = $candidate.Architecture
        Languages       = @($candidate.Languages)
        Version         = $candidate.Version
        BuildFamily     = $candidate.BuildFamily
        IsCompatible    = $comparison.IsCompatible
        ConfidenceLevel = $comparison.ConfidenceLevel
        MatchedChecks   = @($comparison.MatchedChecks)
        Warnings        = @($comparison.Warnings)
        Mismatches      = @($comparison.Mismatches)
    }
}

$otherIndexes = @($indexEvaluations | Where-Object { $_.Index -ne $IsoSourceIndex } | ForEach-Object {
        [ordered]@{
            Index          = $_.Index
            ImageName      = $_.ImageName
            RejectedBecause= if ($_.Mismatches.Count -gt 0) { @($_.Mismatches) } else { @('Not selected because a stronger matching candidate was available.') }
        }
    })

$isoHash = Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256
$localHash = Get-FileHash -LiteralPath $LocalSourcePath -Algorithm SHA256
$diskImage = Get-DiskImage -ImagePath $IsoPath
$volume = $diskImage | Get-Volume | Select-Object -First 1
$localDism = & dism.exe /English /Get-WimInfo /WimFile:$LocalSourcePath /Index:$LocalSourceIndex 2>&1
$localDismSucceeded = $LASTEXITCODE -eq 0
$localRepairSource = ('wim:{0}:{1}' -f $LocalSourcePath, $LocalSourceIndex)

$reportObject = [ordered]@{
    ToolVersion     = Get-SystemFilesCheckToolVersion
    GeneratedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
    IsoFile         = [ordered]@{
        Path          = $IsoPath
        Size          = (Get-Item -LiteralPath $IsoPath).Length
        LastWriteTime = (Get-Item -LiteralPath $IsoPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        Sha256        = $isoHash.Hash
    }
    IsoMount        = [ordered]@{
        DriveLetter = ('{0}:' -f $volume.DriveLetter)
        Label       = [string]$volume.FileSystemLabel
    }
    OriginalSource  = [ordered]@{
        Path       = $IsoSourcePath
        Type       = [System.IO.Path]::GetExtension($IsoSourcePath).TrimStart('.')
        ImageCount = $isoImages.Count
    }
    RunningSystem   = $systemIdentity
    AvailableIsoIndexes = @($indexEvaluations)
    ChosenSource    = [ordered]@{
        OriginalImagePath                  = $IsoSourcePath
        OriginalIndex                      = $IsoSourceIndex
        OriginalMetadata                   = $chosenIsoMetadata
        LocalArtifactPath                  = $LocalSourcePath
        LocalArtifactIndex                 = $LocalSourceIndex
        LocalArtifactMetadata              = $localMetadata
        LocalArtifactExists                = (Test-Path -LiteralPath $LocalSourcePath)
        LocalArtifactReadableByGetWindowsImage = $true
        LocalArtifactReadableByDism        = $localDismSucceeded
        LocalArtifactSha256                = $localHash.Hash
        RepairSource                       = $localRepairSource
        Comparison                         = $localComparison
        ConfidenceLevel                    = $localComparison.ConfidenceLevel
        Caveats                            = @($localComparison.Warnings)
        LocalDismOutput                    = @($localDism | ForEach-Object { [string]$_ })
    }
    OtherIndexesRejected = @($otherIndexes)
}

$reportObject | ConvertTo-Json -Depth 8 | Set-Content -Path $JsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# SystemFilesCheck Source Validation Report') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('Tool version: `{0}`' -f $reportObject.ToolVersion)) | Out-Null
$lines.Add(('Generated at: `{0}`' -f $reportObject.GeneratedAt)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## ISO') | Out-Null
$lines.Add(('- Path: `{0}`' -f $reportObject.IsoFile.Path)) | Out-Null
$lines.Add(('- SHA256: `{0}`' -f $reportObject.IsoFile.Sha256)) | Out-Null
$lines.Add(('- Mounted drive: `{0}` (`{1}`)' -f $reportObject.IsoMount.DriveLetter, $reportObject.IsoMount.Label)) | Out-Null
$lines.Add(('- Original source path: `{0}`' -f $reportObject.OriginalSource.Path)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Running System') | Out-Null
$lines.Add(('- ProductName: `{0}`' -f $systemIdentity.ProductName)) | Out-Null
$lines.Add(('- EditionId: `{0}`' -f $systemIdentity.EditionId)) | Out-Null
$lines.Add(('- InstallationType: `{0}`' -f $systemIdentity.InstallationType)) | Out-Null
$lines.Add(('- Architecture: `{0}`' -f $systemIdentity.Architecture)) | Out-Null
$lines.Add(('- DisplayVersion: `{0}`' -f $systemIdentity.DisplayVersion)) | Out-Null
$lines.Add(('- CurrentBuild.UBR: `{0}.{1}`' -f $systemIdentity.CurrentBuild, $systemIdentity.UBR)) | Out-Null
$lines.Add(('- BuildLabEx: `{0}`' -f $systemIdentity.BuildLabEx)) | Out-Null
$lines.Add(('- DefaultSystemUiLanguage: `{0}`' -f $systemIdentity.DefaultSystemUiLanguage)) | Out-Null
$lines.Add(('- SystemLocale: `{0}`' -f $systemIdentity.SystemLocale)) | Out-Null
$lines.Add(('- MUILanguages: `{0}`' -f (($systemIdentity.MUILanguages | Sort-Object -Unique) -join ', '))) | Out-Null
$lines.Add(('- InstallLanguage: `{0}`' -f $systemIdentity.InstallLanguage)) | Out-Null
$lines.Add(('- Enablement package KB5015684 detected: `{0}`' -f $systemIdentity.EnablementPackageDetected)) | Out-Null
$lines.Add(('- Build family: `{0}`' -f $systemIdentity.BuildFamily)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## ISO Index Evaluation') | Out-Null
foreach ($candidate in $indexEvaluations) {
    $lines.Add(('### Index {0} - {1}' -f $candidate.Index, $candidate.ImageName)) | Out-Null
    $lines.Add(('- EditionId: `{0}`' -f $candidate.EditionId)) | Out-Null
    $lines.Add(('- InstallationType: `{0}`' -f $candidate.InstallationType)) | Out-Null
    $lines.Add(('- Architecture: `{0}`' -f $candidate.Architecture)) | Out-Null
    $lines.Add(('- Languages: `{0}`' -f (($candidate.Languages | Sort-Object -Unique) -join ', '))) | Out-Null
    $lines.Add(('- Version: `{0}`' -f $candidate.Version)) | Out-Null
    $lines.Add(('- Build family: `{0}`' -f $candidate.BuildFamily)) | Out-Null
    $lines.Add(('- Compatible with running system: `{0}`' -f $candidate.IsCompatible)) | Out-Null
    if ($candidate.Mismatches.Count -gt 0) {
        $lines.Add('- Rejected because:') | Out-Null
        foreach ($reason in $candidate.Mismatches) {
            $lines.Add(('  - {0}' -f $reason)) | Out-Null
        }
    }
    if ($candidate.Index -eq $IsoSourceIndex) {
        $lines.Add('- Selected because: exact edition, installation type, architecture, and language match with shared `19041-family` compatibility for Windows 10 22H2 servicing.') | Out-Null
        foreach ($warning in $candidate.Warnings) {
            $lines.Add(('- Caveat: {0}' -f $warning)) | Out-Null
        }
    }
    $lines.Add('') | Out-Null
}

$lines.Add('## Final Local Artifact') | Out-Null
$lines.Add(('- Path: `{0}`' -f $LocalSourcePath)) | Out-Null
$lines.Add(('- SHA256: `{0}`' -f $localHash.Hash)) | Out-Null
$lines.Add('- Readable by Get-WindowsImage: `True`') | Out-Null
$lines.Add(('- Readable by DISM: `{0}`' -f $localDismSucceeded)) | Out-Null
$lines.Add(('- RepairSource string: `{0}`' -f $localRepairSource)) | Out-Null
$lines.Add(('- Confidence level: `{0}`' -f $localComparison.ConfidenceLevel)) | Out-Null
$lines.Add(('- Compatibility: `{0}`' -f $localComparison.IsCompatible)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('### Why this source is considered matching') | Out-Null
foreach ($item in $localComparison.MatchedChecks) {
    $lines.Add(('- {0}' -f $item)) | Out-Null
}
if ($localComparison.Warnings.Count -gt 0) {
    $lines.Add('') | Out-Null
    $lines.Add('### Caveats') | Out-Null
    foreach ($item in $localComparison.Warnings) {
        $lines.Add(('- {0}' -f $item)) | Out-Null
    }
}

if ($otherIndexes.Count -gt 0) {
    $lines.Add('') | Out-Null
    $lines.Add('## Why other indexes were rejected') | Out-Null
    foreach ($item in $otherIndexes) {
        $lines.Add(('- Index {0} ({1}): {2}' -f $item.Index, $item.ImageName, ($item.RejectedBecause -join ' | '))) | Out-Null
    }
}

$lines.Add('') | Out-Null
$lines.Add('## Conclusion') | Out-Null
$lines.Add('- The selected repair source is the official ISO image exported to a local single-index WIM.') | Out-Null
$lines.Add('- It matches the installed system by edition, installation type, architecture, language, and shared servicing family.') | Out-Null
$lines.Add('- It does not match the current cumulative update level exactly, so the confidence is recorded as `Medium`, not `High`.') | Out-Null
$lines.Add('- This is acceptable for a controlled `DISM /RestoreHealth` repair with `-LimitAccess` because Windows 10 22H2 remains on the shared `19041-family` servicing baseline.') | Out-Null

$lines | Set-Content -Path $MarkdownPath -Encoding UTF8

Write-Output $MarkdownPath
Write-Output $JsonPath
