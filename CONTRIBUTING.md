# Contributing

## Scope
This repository targets Windows PowerShell 5.1 and Windows-native tools only. Changes should preserve native operation and avoid mandatory third-party dependencies.

## Development Setup
1. Use Windows PowerShell 5.1 for functional validation.
2. Keep `SystemFilesCheck.ps1` and `lib/SystemFilesCheck.Core.psm1` compatible with Windows 10 Pro x64.
3. Keep the CMD wrapper backward-compatible where practical.

## Required Checks
Run the regression harness before proposing changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SystemFilesCheckRegression.ps1
```

Run the repository completeness check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-SystemFilesCheckProjectCompleteness.ps1
```

Optionally build the clean repo/export bundle:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SystemFilesCheckRepoBundle.ps1 -Validate -CreateZip
```

## Coding Rules
- Keep code comments and repository-facing text in English.
- Prefer explicit object shapes and stable serialization.
- Avoid fragile command-string construction when argument arrays are possible.
- Keep destructive behavior gated and documented.
- Do not add silent automatic cleanup or repair behavior.

## Testing Expectations
- Add or update fixture coverage for parser or verdict changes.
- Update schema tests when `Summary.json` changes.
- Update documentation when user-visible behavior changes.
