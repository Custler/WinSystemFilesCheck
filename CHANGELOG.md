# Change Log

## 1.5.0 - 2026-03-08
- Stabilized `Summary.json` collection serialization so array fields remain arrays across empty, single-item, and multi-item cases.
- Added explicit JSON-contract regression coverage for multiple result categories.
- Added repository completeness checking and broken-link validation.
- Added canonical repository packaging helpers, manifest-driven export, and clean-room validation support.
- Added GitHub-ready documentation set, repository hygiene files, and packaging guidance.
- Sanitized repository-facing content to avoid shipping machine-specific validation artifacts.

## 1.4.0 - 2026-03-08
- Added guarded restore-point workflow and deep repair-source validation.
- Added mounted-image preflight and post-cleanup inventory tracking.
- Added controlled live repair validation against an official matching source.
- Expanded parser fixtures, verdict matrices, and live-validation documentation.

## 1.3.0 - 2026-03-08
- Replaced the legacy batch-only implementation with a PowerShell 5.1 main implementation.
- Kept a thin CMD wrapper for slash-style compatibility.
- Added structured summaries, real exit codes, and safe-by-default behavior.
