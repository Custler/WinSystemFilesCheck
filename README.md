# SystemFilesCheck

Version: `1.5.0`

SystemFilesCheck is a native Windows PowerShell tool for checking and optionally repairing Windows component store integrity, DISM health state, SFC/CBS integrity evidence, and mounted-image preflight state.

The default run is safe by default:
- no `RestoreHealth`
- no `StartComponentCleanup`
- no `ResetBase`
- no `Cleanup-MountPoints`
- no restore-point changes

## Repository Layout
- `SystemFilesCheck.ps1`: main PowerShell entry point
- `0_SystemFilesCheck.cmd`: thin legacy-compatible CMD wrapper
- `lib/SystemFilesCheck.Core.psm1`: core parsing, validation, verdict, and policy logic
- `tools/New-SystemFilesCheckSourceValidationReport.ps1`: helper for building repair-source validation reports
- `tools/Test-SystemFilesCheckProjectCompleteness.ps1`: repository completeness and broken-link checker
- `tools/Build-SystemFilesCheckRepoBundle.ps1`: clean repo/export builder
- `tests/Invoke-SystemFilesCheckRegression.ps1`: regression harness
- `tests/fixtures/`: parser, verdict, and schema fixtures
- `docs/`: manual, audit, packaging, manifest, and source-validation guidance

## Quick Start
Read-only run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -NoPause
```

Read-only run with a validated local repair source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -DryRun -Quick -RepairSource 'wim:C:\install.wim:1' -LimitAccess -NoPause
```

Controlled repair run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunRepair -PreSFC -RequireRestorePoint -RepairSource 'wim:C:\install.wim:1' -LimitAccess -NoPause
```

Legacy wrapper examples:

```cmd
0_SystemFilesCheck.cmd
0_SystemFilesCheck.cmd /PreSFC /RunRepair
0_SystemFilesCheck.cmd /Source:wim:D:\sources\install.wim:1 /LimitAccess /RunRepair
```

## Result Categories
- `Healthy`
- `Repaired`
- `RepairedButRebootRecommended`
- `CorruptionRemains`
- `NonRepairable`
- `RequestedActionFailed`
- `InvalidInput`
- `PreflightFailed`
- `ScriptError`

## Exit Codes
- `0`: Healthy
- `10`: Repaired
- `11`: Repaired but reboot recommended
- `20`: Corruption remains
- `21`: Non-repairable
- `22`: Requested action failed
- `30`: Invalid input or validation failure
- `31`: Preflight failed
- `40`: Internal script or runtime error

## Summary Artifacts
Each session writes:
- `Summary.txt`
- `Summary.json`
- per-phase stdout and stderr captures
- copied CBS and DISM logs when present

`Summary.json` uses a stable machine-readable contract in version `1.5.0`. Collection fields remain arrays even when empty or single-item.

## Matching Repair Sources
A local `C:\install.wim` or `C:\install.esd` is supported, but it is intentionally not tracked in git. Use the documented source-validation workflow before running `-RunRepair` with `-LimitAccess`.

## Validation Status
The project has been validated with:
- static syntax and AST checks
- fixture-based parser and verdict tests
- summary-schema regression tests
- live safe runs
- one controlled live repair run using a validated official matching source

Raw machine-specific validation dumps are intentionally excluded from the public bundle.

## Documentation
- [Manual](docs/MANUAL.md)
- [Technical Audit](docs/AUDIT.md)
- [Packaging Guide](docs/PACKAGING.md)
- [Repository Manifest](docs/REPO-MANIFEST.md)
- [Source Validation Guide](docs/SOURCE-VALIDATION.md)
- [Change Log](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Licensing Note](REPO-LICENSING-NOTE.md)
