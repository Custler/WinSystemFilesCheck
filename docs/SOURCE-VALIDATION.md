# Source Validation Guide

Version: `1.5.0`

## Goal
Prepare a matching repair source for `DISM /RestoreHealth` and validate it before using `-RunRepair -LimitAccess`.

## Recommended Workflow
1. mount the official Windows ISO with native Windows tooling
2. inspect `sources\install.wim` or `sources\install.esd`
3. enumerate image indexes with `DISM /Get-WimInfo` or `Get-WindowsImage`
4. collect live OS identity data
5. compare edition, architecture, installation type, language, and build family
6. export the exact matching index to a single-index local file when practical
7. validate the exported local source again
8. use the validated local source with `-RepairSource`

## Suggested Local Artifact
Preferred:
- `C:\install.wim`

Acceptable when justified:
- `C:\install.esd`

## Helper Script
Generate a reproducible validation report with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SystemFilesCheckSourceValidationReport.ps1 `
  -IsoPath 'D:\Distrib\Windows.iso' `
  -IsoSourcePath 'E:\sources\install.esd' `
  -Index 1 `
  -LocalSourcePath 'C:\install.wim' `
  -RepairSource 'wim:C:\install.wim:1' `
  -MarkdownPath '.\reports\SourceValidation.md' `
  -JsonPath '.\reports\SourceValidation.json'
```

## Matching Criteria
At minimum, compare:
- architecture
- edition identity
- installation type
- language compatibility
- build family
- major version family

If exact compatibility cannot be justified with high confidence, do not run destructive repair with `-LimitAccess` until the source mismatch is understood.

## Repository Note
Do not commit local `install.wim`, `install.esd`, ISO files, or private raw validation reports into the public repository.
