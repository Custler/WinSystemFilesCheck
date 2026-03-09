[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$ManifestPath,
    [string]$JsonOut,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepositoryRoot) {
    $scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    $RepositoryRoot = Split-Path -Path $scriptRoot -Parent
}

if (-not $ManifestPath) {
    $ManifestPath = Join-Path -Path $RepositoryRoot -ChildPath 'SystemFilesCheck.ProjectManifest.json'
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$TargetPath
    )

    $baseUri = [System.Uri](([System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'))
    $targetUri = [System.Uri]([System.IO.Path]::GetFullPath($TargetPath))
    [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
}

function Resolve-IncludePattern {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Pattern
    )

    $path = Join-Path -Path $Root -ChildPath $Pattern
    $hasWildcard = $Pattern.IndexOfAny(@('*', '?')) -ge 0
    if ($hasWildcard) {
        return @(Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue)
    }

    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer) {
            return @(Get-ChildItem -LiteralPath $path -File -Recurse -Force)
        }

        return @($item)
    }

    return @()
}

function Get-MarkdownLinks {
    param([Parameter(Mandatory)][string]$Text)

    [regex]::Matches($Text, '\[[^\]]+\]\(([^)]+)\)') | ForEach-Object { $_.Groups[1].Value }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$repoRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot)
$includedFiles = New-Object System.Collections.Generic.List[string]
$missingPatterns = New-Object System.Collections.Generic.List[string]
$brokenLinks = New-Object System.Collections.Generic.List[object]
$forbiddenHits = New-Object System.Collections.Generic.List[object]
$missingFixtures = New-Object System.Collections.Generic.List[string]

foreach ($pattern in @($manifest.IncludePaths)) {
    $matches = @(Resolve-IncludePattern -Root $repoRootFull -Pattern $pattern)
    if ($matches.Count -eq 0) {
        $missingPatterns.Add($pattern) | Out-Null
        continue
    }

    foreach ($match in $matches) {
        $relative = Get-RelativePath -BasePath $repoRootFull -TargetPath $match.FullName
        if (-not $includedFiles.Contains($relative)) {
            $includedFiles.Add($relative) | Out-Null
        }
    }
}

$testsPath = Join-Path -Path $repoRootFull -ChildPath 'tests\Invoke-SystemFilesCheckRegression.ps1'
if (Test-Path -LiteralPath $testsPath) {
    $testsText = Get-Content -LiteralPath $testsPath -Raw
    $fixtureMatches = [regex]::Matches($testsText, 'Join-Path\s+\$fixturesRoot\s+''([^'']+)''')
    foreach ($fixture in ($fixtureMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)) {
        $fixturePath = Join-Path -Path $repoRootFull -ChildPath (Join-Path -Path 'tests\fixtures' -ChildPath $fixture)
        if (-not (Test-Path -LiteralPath $fixturePath)) {
            $missingFixtures.Add($fixture) | Out-Null
        }
    }
}

$markdownFiles = @($includedFiles | Where-Object { $_ -like '*.md' } | ForEach-Object { Join-Path -Path $repoRootFull -ChildPath $_ })
foreach ($markdownFile in $markdownFiles) {
    $content = Get-Content -LiteralPath $markdownFile -Raw
    foreach ($link in Get-MarkdownLinks -Text $content) {
        if ($link -match '^(https?|mailto):' -or $link.StartsWith('#')) {
            continue
        }

        $cleanLink = ($link -split '#', 2)[0]
        $cleanLink = ($cleanLink -split '\?', 2)[0]
        if ([string]::IsNullOrWhiteSpace($cleanLink)) {
            continue
        }

        $resolved = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Path $markdownFile -Parent) -ChildPath $cleanLink))
        if (-not $resolved.StartsWith($repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $brokenLinks.Add([pscustomobject]@{ File = (Get-RelativePath -BasePath $repoRootFull -TargetPath $markdownFile); Link = $link; Reason = 'OutsideRepositoryRoot' }) | Out-Null
            continue
        }

        if (-not (Test-Path -LiteralPath $resolved)) {
            $brokenLinks.Add([pscustomobject]@{ File = (Get-RelativePath -BasePath $repoRootFull -TargetPath $markdownFile); Link = $link; Reason = 'MissingTarget' }) | Out-Null
        }
    }
}

$textExtensions = @('.md', '.json', '.ps1', '.psm1', '.cmd', '.gitignore', '.gitattributes', '.editorconfig')
foreach ($relativePath in $includedFiles) {
    $fullPath = Join-Path -Path $repoRootFull -ChildPath $relativePath
    if ($relativePath -in @('.gitignore', 'SystemFilesCheck.ProjectManifest.json')) {
        continue
    }

    $extension = [System.IO.Path]::GetExtension($fullPath)
    if (($textExtensions -notcontains $extension) -and ($relativePath -notin @('.gitignore', '.gitattributes', '.editorconfig'))) {
        continue
    }

    $matches = Select-String -Path $fullPath -SimpleMatch -Pattern @($manifest.PublicRepoForbiddenPatterns) -ErrorAction SilentlyContinue
    foreach ($match in @($matches)) {
        $forbiddenHits.Add([pscustomobject]@{
            File    = $relativePath
            Pattern = $match.Pattern
            Line    = $match.LineNumber
        }) | Out-Null
    }
}

$report = [ordered]@{
    RepositoryRoot       = $repoRootFull
    ManifestPath         = [System.IO.Path]::GetFullPath($ManifestPath)
    ToolVersion          = $manifest.ToolVersion
    IncludedFiles        = @([string[]]$includedFiles.ToArray() | Sort-Object)
    MissingPatterns      = @([string[]]$missingPatterns.ToArray())
    MissingFixtures      = @([string[]]$missingFixtures.ToArray())
    BrokenLinks          = @($brokenLinks.ToArray())
    ForbiddenPatternHits = @($forbiddenHits.ToArray())
    Passed               = ($missingPatterns.Count -eq 0 -and $missingFixtures.Count -eq 0 -and $brokenLinks.Count -eq 0 -and $forbiddenHits.Count -eq 0)
}

if ($JsonOut) {
    $targetDir = Split-Path -Path $JsonOut -Parent
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    ConvertTo-Json -InputObject $report -Depth 8 | Set-Content -LiteralPath $JsonOut -Encoding UTF8
}

if (-not $Quiet) {
    Write-Host ('Included files         : {0}' -f $report.IncludedFiles.Count)
    Write-Host ('Missing patterns       : {0}' -f $report.MissingPatterns.Count)
    Write-Host ('Missing fixtures       : {0}' -f $report.MissingFixtures.Count)
    Write-Host ('Broken links           : {0}' -f $report.BrokenLinks.Count)
    Write-Host ('Forbidden pattern hits : {0}' -f $report.ForbiddenPatternHits.Count)
}

if (-not $report.Passed) {
    throw [System.InvalidOperationException]::new('Project completeness validation failed. See MissingPatterns, MissingFixtures, BrokenLinks, or ForbiddenPatternHits.')
}

[pscustomobject]$report
