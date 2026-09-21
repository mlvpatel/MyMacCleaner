# Release runbook

Evidence and status for quality and direct distribution. This file is the
**sole release-status authority**. Other docs must not claim a stronger gate
than the row below.

## Status matrix

| Gate | Status | Evidence |
|------|--------|----------|
| SafetyContract local | **Locally verified** | `bash scripts/verify-safety-contract.sh` |
| CleanerCore SwiftPM + coverage | **Locally verified** | `CODEX_SANDBOX=1 bash scripts/verify-cleanercore.sh` — 7982/8940 (89.28%), every production target at or above 80.00%. See [COVERAGE.md](COVERAGE.md) |
| Adaptive catalog/IDs (CLT) | **Locally verified** | `bash scripts/verify-adaptive-experience.sh` |
| Full-Xcode app build | **Pending** | `xcode-select -p` is `/Library/Developer/CommandLineTools`; no Xcode.app |
| XCUITest / VoiceOver / keyboard / Reduce Motion / Increase Contrast | **Pending** | 08-04 `ui_proof: human_needed` |
| Hosted safety-contract workflow | **Pending** | `.github/workflows/safety-contract.yml` exists; this session has no successful GitHub Actions run |
| Developer ID signing | **Pending** | No signing identity in this environment; do not store secrets in the repo |
| Notarization / stapling | **Pending** | Not run |
| Gatekeeper assessment | **Pending** | Not run |
| Clean-account offline launch | **Pending** | Requires a full-Xcode / isolated account |
| Private GitHub push of a sanitized root | **Not done** | Explicitly skipped |
| Website retirement | **Not done** | Explicitly skipped; website remains |

## Local commands (this environment)

```bash
bash scripts/verify-safety-contract.sh
bash scripts/verify-adaptive-experience.sh
CODEX_SANDBOX=1 bash scripts/verify-cleanercore.sh
```

Command Line Tools cannot run:

```bash
xcodebuild -project MyMacCleaner.xcodeproj -scheme MyMacCleaner build
xcodebuild test -project MyMacCleaner.xcodeproj -scheme MyMacCleaner
```

## Signing configuration

The app target takes its signing settings from `Config/Signing.xcconfig`, which
defaults to ad hoc signing with no team. Put `DEVELOPMENT_TEAM` and
`CODE_SIGN_IDENTITY = Developer ID Application` in the gitignored
`Config/Signing.local.xcconfig` (see the `.example` file). No team ID is committed.

## Updates (removed)

Sparkle, the custom appcast checker, `appcast.xml`, and the feed/key build
settings were removed. The app exposes only `UpdateCapability.unavailable`.
`scripts/verify-safety-contract.sh --diagnostics-network-only` fails if an
updater, `URLSession`, Sparkle import, or appcast reference returns.
`scripts/release.sh` builds a Developer ID release without any update channel: it refuses
dirty or off-`main` trees, runs tests and verifiers, notarizes and staples the app and DMG, checks
them with `spctl`, and creates only a draft release from a `release/v<version>` branch. See
[RELEASE.md](../RELEASE.md). Its output is not evidence until the checks below are recorded.

## What this runbook forbids claiming

- "Signed and notarized" without notary and stapler evidence
- "Gatekeeper passed" without `spctl` assessment of the shipped artifact
- "CI green" without a recorded hosted run SHA
- "08-04 complete" without full-Xcode XCUITest and assistive walks
