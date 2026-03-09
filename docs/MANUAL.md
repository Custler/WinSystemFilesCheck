# Manual

Version: `1.5.0`

## Purpose and Scope
SystemFilesCheck is a Windows-native integrity and servicing helper for installed Windows systems. It focuses on:
- DISM component-store health
- SFC and CBS repair evidence
- mounted-image preflight state
- repair-source validation
- restore-point gating for destructive modes
- deterministic verdicts, summaries, and exit codes

It does not replace full hardware diagnostics, malware analysis, or application-level troubleshooting.

## What the Tool Checks
- administrator state
- OS identity and build data
- pending reboot indicators
- mounted-image inventory from `DISM /Get-MountedImageInfo`
- DISM `CheckHealth`
- DISM `ScanHealth`, unless `-Quick` is used
- DISM `RestoreHealth`, when `-RunRepair` is requested
- SFC baseline, when `-PreSFC` is requested
- final SFC after repair
- final DISM `CheckHealth`
- component-store analysis
- optional cleanup phases

## What the Tool Does Not Check
- storage SMART health
- memory stability
- driver package correctness beyond what DISM and CBS reveal
- Secure Boot trust databases
- third-party application integrity

## Safety Model
Default execution is read-only.

Destructive actions require explicit switches:
- `-RunRepair`
- `-RunCleanup`
- `-RunResetBase`
- `-CleanupMountPoints`

`-RunResetBase` requires both:
- an explicit switch
- an explicit confirmation prompt, unless `-ForceResetBase` is used

## Parameters
- `-PreSFC`: run a baseline `sfc /scannow` before repair
- `-RepairSource <value>`: folder, `wim:path:index`, or `esd:path:index`
- `-LimitAccess`: block Windows Update during `RestoreHealth`
- `-RunRepair`: run `RestoreHealth`, then final SFC and final `CheckHealth`
- `-RunCleanup`: run `StartComponentCleanup`
- `-RunResetBase`: add `/ResetBase` to cleanup
- `-DryRun`: explicit read-only mode
- `-SelfTest`: run fixture and regression tests only
- `-ScratchDir <path>`: custom DISM scratch directory
- `-CleanupMountPoints`: run `DISM /Cleanup-MountPoints`
- `-Quick`: skip `ScanHealth`
- `-JsonSummary <path>`: copy `Summary.json` to an additional path
- `-SkipRestorePoint`: do not attempt a restore point before destructive work
- `-RequireRestorePoint`: abort destructive work if no restore point can be created
- `-RestorePointDescription <text>`: custom restore point description
- `-EnableSystemRestoreIfNeeded`: explicitly try to enable System Restore before restore-point creation
- `-ForceResetBase`: skip the extra reset-base confirmation prompt
- `-NoPause`: do not pause before exit
- `-ShowUsage`: print built-in help

## Legacy Wrapper Compatibility
`0_SystemFilesCheck.cmd` forwards slash-style arguments to the PowerShell implementation.

Supported legacy forms include:
- `/PreSFC`
- `/Source:path`
- `/LimitAccess`
- `/Cleanup`
- `/ResetBase`
- `/RunRepair`
- `/RunCleanup`
- `/RunResetBase`
- `/DryRun`
- `/SelfTest`
- `/CleanupMountPoints`
- `/Quick`
- `/SkipRestorePoint`
- `/RequireRestorePoint`
- `/EnableSystemRestoreIfNeeded`
- `/ForceResetBase`
- `/ScratchDir:path`
- `/JsonSummary:path`
- `/RestorePointDescription:text`
- `/NoPause`

## Restore-Point Policy
Restore points are relevant only for destructive paths.

Recorded fields:
- `Relevant`
- `Attempted`
- `Succeeded`
- `Required`
- `SkippedByPolicy`
- `ContinueWithoutRestorePoint`
- `Outcome`
- `GateEvaluated`
- `ExecutionContinued`
- `AbortedExecution`
- `EnableSystemRestoreIfNeeded`
- `Description`
- `SequenceNumber`
- `Message`

Policy summary:
- read-only runs do not attempt restore points
- destructive runs attempt restore-point creation unless `-SkipRestorePoint` is used
- `-RequireRestorePoint` aborts destructive work when a restore point cannot be created
- `ContinueWithoutRestorePoint` reflects actual continued execution, not early intent

## Repair-Source Validation
The tool validates repair sources before using them for `RestoreHealth`.

Supported forms:
- folder path
- `wim:path:index`
- `esd:path:index`

Validation checks include:
- existence
- syntax
- readable metadata
- architecture
- edition identity
- installation type
- language compatibility
- build family
- major version family

See [`SOURCE-VALIDATION.md`](SOURCE-VALIDATION.md) for the recommended workflow.

## Result Categories
- `Healthy`: no actionable corruption remains
- `Repaired`: corruption was repaired and no reboot recommendation remains
- `RepairedButRebootRecommended`: repair succeeded and a reboot is recommended
- `CorruptionRemains`: repairable or unresolved corruption remains
- `NonRepairable`: DISM indicates a non-repairable component store
- `RequestedActionFailed`: a user-requested cleanup or maintenance action failed
- `InvalidInput`: invalid switches or repair-source validation failure
- `PreflightFailed`: preflight conditions blocked correct execution
- `ScriptError`: an internal tool failure occurred

## Exit Codes
- `0`: Healthy
- `10`: Repaired
- `11`: RepairedButRebootRecommended
- `20`: CorruptionRemains
- `21`: NonRepairable
- `22`: RequestedActionFailed
- `30`: InvalidInput
- `31`: PreflightFailed
- `40`: ScriptError

## Session Artifacts
Each run creates a session folder under `C:\SystemRepairLogs\timestamp`.

Typical contents:
- `Main.log`
- `Transcript.txt`
- `Summary.txt`
- `Summary.json`
- `CopiedLogs\CBS.log`
- `CopiedLogs\CBS.persist.log`
- `CopiedLogs\dism.log`
- per-phase stdout and stderr files

## Summary Schema
`Summary.txt` is human-readable.

`Summary.json` is machine-readable. The stable schema contract in version `1.5.0` keeps collection fields as arrays even when empty or single-item.

Important scalar fields:
- `ScriptName`
- `ToolVersion`
- `MachineName`
- `UserName`
- `SessionPath`
- `StartTime`
- `EndTime`
- `TotalDuration`
- `OverallResultCategory`
- `ExitCode`
- `ResultReason`
- `RepairSource`
- `NextStepRecommendation`

Important object fields:
- `RepairSourceValidation`
- `RestorePoint`
- `Modes`
- `Environment`
- `SystemIdentity`
- `Phases`
- `AnalyzeComponentStore`
- `AnalyzeAfterCleanupComparison`
- `MountedImageStateBeforeCleanup`
- `MountedImageStateAfterCleanup`

Collection fields that always remain arrays:
- `MountedImages`
- `RequestedActionFailures`
- `Warnings`
- `Errors`
- `Notes`
- `MountedImageStateBeforeCleanup.Images`
- `MountedImageStateBeforeCleanup.Statuses`
- `MountedImageStateAfterCleanup.Images`
- `MountedImageStateAfterCleanup.Statuses`
- `RepairSourceValidation.ImageMetadata.Languages`
- `RepairSourceValidation.Compatibility.MatchedChecks`
- `RepairSourceValidation.Compatibility.Warnings`
- `RepairSourceValidation.Compatibility.Mismatches`

## Examples
Safe default run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -NoPause
```

Quick read-only run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -DryRun -Quick -NoPause
```

Read-only run with a local source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -DryRun -RepairSource 'wim:C:\install.wim:1' -LimitAccess -NoPause
```

Controlled repair run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunRepair -PreSFC -RequireRestorePoint -RepairSource 'wim:C:\install.wim:1' -LimitAccess -NoPause
```

Component-store cleanup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SystemFilesCheck.ps1 -RunCleanup -RequireRestorePoint -NoPause
```

## Repository Layout
- `README.md`: repository landing page
- `docs/MANUAL.md`: detailed operator manual
- `docs/AUDIT.md`: technical audit summary
- `docs/PACKAGING.md`: bundle and export workflow
- `docs/REPO-MANIFEST.md`: included and excluded repository content
- `docs/SOURCE-VALIDATION.md`: matching-source workflow
- `CHANGELOG.md`: version history
- `CONTRIBUTING.md`: contributor workflow
- `SECURITY.md`: security note
- `REPO-LICENSING-NOTE.md`: licensing placeholder

## Tests
Primary regression entry point:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SystemFilesCheckRegression.ps1
```

Repository completeness check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-SystemFilesCheckProjectCompleteness.ps1
```

## Packaging
Build a clean repo/export tree and optional zip archive:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SystemFilesCheckRepoBundle.ps1 -Validate -CreateZip
```

## Trust Boundaries
The tool is trustworthy for:
- read-only integrity diagnostics
- DISM and CBS evidence parsing
- verdict and exit-code mapping
- repair-source validation
- safe gating of destructive modes

The tool still depends on Windows servicing components for the actual repair outcome. If DISM or SFC returns incomplete or inconsistent evidence, manual review of copied logs is still required.

## Live Validation Boundaries
Validated live:
- safe read-only runs
- self-tests and wrapper execution
- controlled repair execution with a matching official source

Not validated live in the public bundle:
- `RunResetBase` on a live installed OS
- `Cleanup-MountPoints` when no invalid mount state exists
- destructive cleanup on systems where no cleanup action is justified
