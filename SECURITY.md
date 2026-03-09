# Security Policy

## Supported Versions
The current maintained branch is the latest repository version documented in [`CHANGELOG.md`](CHANGELOG.md).

## Reporting Issues
If you discover a security-relevant issue, do not publish exploit details immediately. Share a minimal reproduction, affected version, and impact description with the repository owner through a private channel.

## Scope Notes
This tool can invoke DISM, SFC, restore-point APIs, and optional cleanup operations. Review changes carefully when they affect:
- command invocation
- repair-source validation
- log handling
- path handling
- restore-point policy
- summary serialization
