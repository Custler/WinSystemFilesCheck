[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$OutputRoot,
    [string]$ManifestPath,
    [switch]$Validate,
    [switch]$CreateZip,
    [string]$ZipPath,
    [switch]$InitializeGit,
    [switch]$CreateInitialCommit,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    $scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    $SourceRoot = Split-Path -Path $scriptRoot -Parent
}

if (-not $ManifestPath) {
    $ManifestPath = Join-Path -Path $SourceRoot -ChildPath 'SystemFilesCheck.ProjectManifest.json'
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if (-not $OutputRoot) {
    $OutputRoot = Join-Path -Path (Join-Path -Path $SourceRoot -ChildPath 'dist') -ChildPath $manifest.RepoRootName
}
if (-not $ZipPath) {
    $ZipPath = Join-Path -Path (Join-Path -Path $SourceRoot -ChildPath 'dist') -ChildPath ($manifest.RepoRootName + '.zip')
}
if (-not $PSBoundParameters.ContainsKey('InitializeGit')) {
    $InitializeGit = $true
}
if (-not $PSBoundParameters.ContainsKey('CreateInitialCommit')) {
    $CreateInitialCommit = $true
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

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $stdoutPath = Join-Path -Path $env:TEMP -ChildPath ('systemfilescheck-git-{0}.stdout.txt' -f [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path -Path $env:TEMP -ChildPath ('systemfilescheck-git-{0}.stderr.txt' -f [guid]::NewGuid().ToString('N'))
    $argumentText = [string]::Join(' ', ($Arguments | ForEach-Object {
                if ($_ -match '[\s"]') {
                    '"' + ($_.Replace('"', '\"')) + '"'
                }
                else {
                    $_
                }
            }))

    try {
        $process = Start-Process -FilePath 'git.exe' -ArgumentList $argumentText -WorkingDirectory $WorkingDirectory -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $exitCode = $process.ExitCode
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        StdOut   = if ($null -ne $stdout) { $stdout.Trim() } else { '' }
        StdErr   = if ($null -ne $stderr) { $stderr.Trim() } else { '' }
    }
}

$sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
$outputRootFull = [System.IO.Path]::GetFullPath($OutputRoot)
$zipPathFull = [System.IO.Path]::GetFullPath($ZipPath)

if ($Validate) {
    & (Join-Path -Path $SourceRoot -ChildPath 'tools\Test-SystemFilesCheckProjectCompleteness.ps1') -RepositoryRoot $sourceRootFull -ManifestPath $ManifestPath -Quiet | Out-Null
}

if (Test-Path -LiteralPath $outputRootFull) {
    Remove-Item -LiteralPath $outputRootFull -Recurse -Force
}
New-Item -ItemType Directory -Path $outputRootFull -Force | Out-Null

$copied = New-Object System.Collections.Generic.List[string]
foreach ($pattern in @($manifest.IncludePaths)) {
    $matches = @(Resolve-IncludePattern -Root $sourceRootFull -Pattern $pattern)
    foreach ($match in $matches) {
        $relative = Get-RelativePath -BasePath $sourceRootFull -TargetPath $match.FullName
        if ($copied.Contains($relative)) {
            continue
        }

        $destination = Join-Path -Path $outputRootFull -ChildPath $relative
        $destinationDir = Split-Path -Path $destination -Parent
        if ($destinationDir -and -not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $match.FullName -Destination $destination -Force
        $copied.Add($relative) | Out-Null
    }
}

if ($Validate) {
    & (Join-Path -Path $outputRootFull -ChildPath 'tools\Test-SystemFilesCheckProjectCompleteness.ps1') -RepositoryRoot $outputRootFull -Quiet | Out-Null
}

$gitInitialized = $false
$gitCommitted = $false
$gitStatus = $null
if ($InitializeGit -and (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    $init = Invoke-Git -WorkingDirectory $outputRootFull -Arguments @('init', '--initial-branch=main')
    if ($init.ExitCode -ne 0) {
        throw [System.InvalidOperationException]::new(('git init failed: {0}' -f $init.StdErr))
    }

    $gitInitialized = $true
    $null = Invoke-Git -WorkingDirectory $outputRootFull -Arguments @('config', 'user.name', 'SystemFilesCheck Export')
    $null = Invoke-Git -WorkingDirectory $outputRootFull -Arguments @('config', 'user.email', 'systemfilescheck-export@example.invalid')

    if ($CreateInitialCommit) {
        $add = Invoke-Git -WorkingDirectory $outputRootFull -Arguments @('add', '--all')
        if ($add.ExitCode -ne 0) {
            throw [System.InvalidOperationException]::new(('git add failed: {0}' -f $add.StdErr))
        }

        $commit = Invoke-Git -WorkingDirectory $outputRootFull -Arguments @('-c', 'commit.gpgsign=false', 'commit', '--no-verify', '-m', ('Initial export of SystemFilesCheck {0}' -f $manifest.ToolVersion))
        if ($commit.ExitCode -ne 0) {
            throw [System.InvalidOperationException]::new(('git commit failed: {0}' -f $commit.StdErr))
        }
        $gitCommitted = $true
    }

    $status = Invoke-Git -WorkingDirectory $outputRootFull -Arguments @('status', '--short')
    if ($status.ExitCode -ne 0) {
        throw [System.InvalidOperationException]::new(('git status failed: {0}' -f $status.StdErr))
    }
    $gitStatus = $status.StdOut
}

if ($CreateZip) {
    $zipDirectory = Split-Path -Path $zipPathFull -Parent
    if ($zipDirectory -and -not (Test-Path -LiteralPath $zipDirectory)) {
        New-Item -ItemType Directory -Path $zipDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $zipPathFull) {
        Remove-Item -LiteralPath $zipPathFull -Force
    }
    Compress-Archive -Path $outputRootFull -DestinationPath $zipPathFull -CompressionLevel Optimal
}

$result = [ordered]@{
    SourceRoot        = $sourceRootFull
    OutputRoot        = $outputRootFull
    ZipPath           = if ($CreateZip) { $zipPathFull } else { $null }
    ToolVersion       = $manifest.ToolVersion
    CopiedFiles       = @([string[]]$copied.ToArray() | Sort-Object)
    GitInitialized    = $gitInitialized
    GitCommitted      = $gitCommitted
    GitStatusShort    = $gitStatus
    ValidationEnabled = [bool]$Validate
}

if (-not $Quiet) {
    Write-Host ('Output root  : {0}' -f $result.OutputRoot)
    Write-Host ('Copied files : {0}' -f $result.CopiedFiles.Count)
    Write-Host ('Git init     : {0}' -f $result.GitInitialized)
    Write-Host ('Git commit   : {0}' -f $result.GitCommitted)
    if ($CreateZip) {
        Write-Host ('Zip archive  : {0}' -f $result.ZipPath)
    }
}

[pscustomobject]$result
