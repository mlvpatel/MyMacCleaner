# Security Policy

This document describes how MyMacCleaner handles security reports and what is currently proven in this Command Line Tools environment. It does not claim Developer ID signing, notarization, Gatekeeper, or a full-Xcode UI security review.

## Supported versions

| Version | Status |
|---------|--------|
| 0.1.x source tree | Local safety freeze and CleanerCore trust pipeline |
| Signed/notarized builds | Not produced in this environment |

## Reporting a vulnerability

Email is not yet a dedicated security alias. Open a private report with the repository maintainer and include:

- Affected path or requirement ID (`SAFE-*`, `EXEC-*`, `PRIV-*`)
- Whether the issue bypasses Trash-first cleanup, elevation freeze, or receipt privacy
- A local reproduction that does not require production credentials

Do not attach raw local paths, model names, chat logs, receipts, or credentials.

## What is in scope

- Privilege, shell, Empty Trash, `rm`, and memory-purge freeze (`SafetyContract`)
- CleanerCore scan, policy, review-plan, Trash move, and receipt invariants
- Presentation modes that must not change eligibility or authority
- Read-only developer/Docker/Homebrew inventory (no prune/install/mutation)

## What is out of scope for current claims

- Full Xcode UI, VoiceOver, and XCUITest evidence
- Signing, notarization, stapling, and Gatekeeper
- Hosted CI on a private GitHub repository

## Local verification that can be run here

```bash
bash scripts/verify-safety-contract.sh
CODEX_SANDBOX=1 bash scripts/run-cleanercore-tests.sh --filter AdaptiveExperienceProjectionTests
bash scripts/tests/verify-adaptive-bridge-tests.sh
bash scripts/verify-adaptive-experience.sh
```

The last canonical CleanerCore coverage result (2026-09-22, full Xcode 27) is aggregate **8042/9029 (89.07%)** with every production target at or above **80.00%**. Command: `CODEX_SANDBOX=1 bash scripts/verify-cleanercore.sh`. Details are in `docs/COVERAGE.md`.

Architecture, detector, recovery, and privacy contracts: `docs/C4.md`, `docs/THREAT-MODEL.md`, `docs/DETECTOR-CONTRACT.md`, `docs/RECOVERY.md`, `docs/PRIVACY.md`. Release claims belong only in `docs/RELEASE-RUNBOOK.md`. Conduct: `CODE_OF_CONDUCT.md`.

## Data handling

Scans, plans, approvals, execution, and receipts are local. Receipt identifiers are opaque. Finder reveal uses the private Foundation Trash URL and does not print paths. Developer inventory is presence/protection only. First-launch Adaptive Experience copy states the product stays offline, does not create an account, and does not start a scan on Continue.
