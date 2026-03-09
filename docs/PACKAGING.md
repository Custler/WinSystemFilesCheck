# Packaging Guide

Version: `1.5.0`

## Goal
Build a clean, self-contained repository working tree that can be initialized as a git repository and optionally archived as a zip file.

## Primary Helper
Use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SystemFilesCheckRepoBundle.ps1 -Validate -CreateZip
```

## What the Builder Does
- reads `SystemFilesCheck.ProjectManifest.json`
- copies only the declared repository files
- preserves relative layout
- optionally validates source-tree completeness before and after export
- optionally initializes a git repository on branch `main`
- optionally creates a local initial commit with repository-local placeholder identity
- optionally creates a zip archive

## Output Paths
Default outputs:
- repo folder: `dist\SystemFilesCheck-repo`
- zip archive: `dist\SystemFilesCheck-repo.zip`

## Clean-Room Validation
Recommended post-build validation:
1. copy the exported repo to a different temporary path
2. run the regression harness from that copy
3. run the completeness checker from that copy
4. verify that helper scripts and docs resolve without referencing the original working directory

## What Is Intentionally Excluded
- local repair-source binaries such as `install.wim`
- local ISO files
- task logs
- private raw validation summaries
- large runtime logs
- local archive scratch files

## Git Notes
The builder can initialize git and create an initial commit. The placeholder local identity is repository-local and should be replaced by the repository owner before publication.
