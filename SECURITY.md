# Security Policy

This document describes how MyMacCleaner handles security reports and which safety properties the repository's gates check. It does not claim Developer ID signing, notarization, Gatekeeper, or a full UI security review; [docs/RELEASE-RUNBOOK.md](docs/RELEASE-RUNBOOK.md) holds release status.

## Supported versions

| Version | Status |
|---------|--------|
| `main` (1.0 pre-release; the project still reports version 0.1.3) | Security reports are handled here |
| Released 0.1.x builds | Predate the 1.0 safety rewrite; report issues against `main` |
| Developer ID signed and notarized builds | Not produced yet |

## Reporting a vulnerability

Use GitHub private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability** ([direct link](https://github.com/mlvpatel/MyMacCleaner/security/advisories/new)). Do not open a public issue. There is no security email alias. Include:

- The affected file, feature, or verifier rule ID (see [docs/VERIFIER-RULES.md](docs/VERIFIER-RULES.md))
- Whether the issue bypasses Trash-first cleanup, the privilege-elevation ban, or receipt privacy
- A local reproduction that does not require production credentials

Do not attach raw local paths, model names, chat logs, receipts, or credentials.

## What is in scope

- The privilege, shell, Empty Trash, `rm`, and memory-purge ban (`SafetyContract`)
- CleanerCore scan, policy, review-plan, Trash move, and receipt invariants
- Presentation modes that must not change eligibility or authority
- Read-only developer/Docker/Homebrew inventory (no prune/install/mutation)

## What is out of scope for current claims

- The manual VoiceOver, keyboard, Reduce Motion, and Increase Contrast audit (pending)
- Signing, notarization, stapling, and Gatekeeper (pending)

## Local verification

`bash scripts/verify-all.sh` runs every safety, CleanerCore, and Adaptive Experience gate the Safety Contract workflow runs; see [CONTRIBUTING.md](CONTRIBUTING.md#local-gates).

The last canonical CleanerCore coverage result (2026-10-06, full Xcode 27) is aggregate **8417/9321 (90.30%)** with every production target at or above **80.00%**. Command: `bash scripts/verify-cleanercore.sh`. Details are in `docs/COVERAGE.md`.

Architecture, detector, recovery, and privacy contracts: `docs/C4.md`, `docs/THREAT-MODEL.md`, `docs/DETECTOR-CONTRACT.md`, `docs/RECOVERY.md`, `docs/PRIVACY.md`. Release claims belong only in `docs/RELEASE-RUNBOOK.md`. Conduct: `CODE_OF_CONDUCT.md`.

## Data handling

Scans, plans, approvals, execution, and receipts are local. Receipt identifiers are opaque. Finder reveal uses the private Foundation Trash URL and does not print paths. Developer inventory is presence/protection only. First-launch Adaptive Experience copy states the product stays offline, does not create an account, and does not start a scan on Continue.
