# Technical Audit

Version audited: `1.5.0`

## Scope
This audit summarizes the current correctness and packaging state of the repository version, not the machine-specific private validation dumps.

## Legacy Defects Confirmed and Fixed
- broken batch `%ERRORLEVEL%` capture inside parenthesized blocks
- broken `/Source` parsing in the old batch implementation
- fragile command construction for `ResetBase`
- legacy always-zero exit-code behavior
- historical `Cannot repair` evidence poisoning the final verdict
- mounted-image status parsing drift
- restore-point summary drift
- direct-launch empty remaining-argument bug
- unstable `Summary.json` array serialization

## Summary Contract Hardening
Version `1.5.0` adds an explicit JSON-safe normalization layer and regression coverage so collection fields remain arrays across all key result paths.

Verified categories include:
- `Healthy`
- `Repaired`
- `RepairedButRebootRecommended`
- `CorruptionRemains`
- `NonRepairable`
- `RequestedActionFailed`
- `InvalidInput`
- `PreflightFailed`
- `ScriptError`

## Current Validation Coverage
Validated by regression tests:
- syntax parsing of the main script, module, and repository helper scripts
- AST safety checks
- parser fixtures for DISM, SFC/CBS, mounted images, and component-store analysis
- verdict and outcome matrices
- restore-point policy matrix
- repair-source validation matrix
- summary-schema regression checks
- repository completeness and broken-link checks

Validated live:
- safe read-only execution
- wrapper forwarding
- source-validation workflow
- one controlled repair run using a validated official matching source

## Public Repository Sanitization
The repository bundle intentionally excludes:
- local ISO images
- local `install.wim` or `install.esd`
- raw machine-specific session logs
- raw live summary dumps
- private source-validation reports containing local paths or identifiers

## Residual Limitations
- destructive cleanup paths remain code-validated and fixture-validated, but not forced live without a justified reason
- `RunResetBase` remains intentionally gated and not live-validated on the installed OS
- the tool relies on Windows servicing components for the actual repair result

## Trust Statement
The repository version is suitable as a GitHub-ready, self-contained bundle for read-only diagnosis, repair-source validation, controlled repair orchestration, and reproducible regression testing.
