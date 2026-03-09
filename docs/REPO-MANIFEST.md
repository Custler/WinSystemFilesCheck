# Repository Manifest

Version: `1.5.0`

## Included in the Canonical Repository Bundle
- entry points
  - `SystemFilesCheck.ps1`
  - `0_SystemFilesCheck.cmd`
- core module
  - `lib/SystemFilesCheck.Core.psm1`
- repository helpers
  - `tools/New-SystemFilesCheckSourceValidationReport.ps1`
  - `tools/Test-SystemFilesCheckProjectCompleteness.ps1`
  - `tools/Build-SystemFilesCheckRepoBundle.ps1`
- tests
  - `tests/Invoke-SystemFilesCheckRegression.ps1`
  - `tests/fixtures/*`
- repository documentation
  - `README.md`
  - `SystemFilesCheck_README.md`
  - `SystemFilesCheck_Audit.md`
  - `docs/*`
  - `CHANGELOG.md`
  - `CONTRIBUTING.md`
  - `SECURITY.md`
  - `REPO-LICENSING-NOTE.md`
- repository metadata
  - `.gitignore`
  - `.gitattributes`
  - `.editorconfig`
  - `SystemFilesCheck.ProjectManifest.json`

## Excluded from the Canonical Repository Bundle
- `C:\install.wim` and other local repair-source binaries
- local ISO images
- raw session folders under `C:\SystemRepairLogs`
- task-log directories
- internal private validation reports containing local paths
- temporary debug scripts
- dist artifacts generated during export

## Rebuild Procedure
1. run the completeness checker on the working source tree
2. run the bundle builder with validation enabled
3. perform clean-room validation from a copied export
4. publish the exported repo folder or its zip archive
