# MyMacCleaner - Project Specification

## Overview

**MyMacCleaner** - Open-source macOS system utility with Apple's Liquid Glass UI design.

| Attribute | Value |
|-----------|-------|
| Language | Swift: app target in Swift 5 language mode, local packages at `swift-tools-version: 6.0` |
| Toolchain | Xcode 26 or later. CI tests with Xcode 26 (the newest 26.x on GitHub's `macos-26` runners) |
| UI Framework | SwiftUI |
| Target | macOS 14.0+ (Sonoma) |
| Design | Liquid Glass (native on macOS 26+, material fallback on 14-15) |
| Architecture | MVVM with Swift actors for services |
| Status | Pre-release 1.0 (Developer ID release pending signing credentials) |

## Features

Every surface except Adaptive Experience is a read-only inventory. The only mutation in the app is
moving approved files to the Trash from Adaptive Experience.

| Feature | Description |
|---------|-------------|
| **Adaptive Experience** | Evidence at three depths (Guided/Standard/Technical); review → approve → move to Trash → receipt |
| **Home** | Smart Scan dashboard over six general-Mac roots (CleanerCore), system stats, permission prompts |
| **Disk Cleaner** | Category review of caches, logs, temporary data; Browser Privacy review (read-only) |
| **Space Lens** | Read-only treemap (squarified), cancellable, 500,000-entry cap |
| **Orphaned Files** | Review-only leftovers from removed apps |
| **Duplicates** | Hash-based duplicate finder with cancellation (triage only) |
| **Performance** | Read-only CPU, memory and process observations |
| **Applications** | Read-only app inventory with Homebrew cask listing |
| **Port Management** | Read-only TCP connection inventory |
| **System Health** | Health summary, disk/battery/system info (read-only) |
| **Startup Items** | Read-only login item and launch-agent inventory |
| **Permissions** | FDA and folder access review with TCC dialog triggers |
| **AI/ML & developer inventory** | Hugging Face, Ollama, LM Studio, MLX stores; Cursor, VS Code, Docker, Homebrew presence (inventory only) |
| **Menu Bar** | Real-time CPU/RAM/Disk stats with 4 display modes |
| **Localization** | English only (String Catalogs chosen by key prefix in `LocalizationManager`; more locales may be added later) |

## Project Structure

```
MyMacCleaner/
├── App/                    # MyMacCleanerApp.swift, ContentView.swift, AppDelegate.swift
├── Core/
│   ├── Design/            # Theme, LiquidGlass, Animations, ToastView, ToastPresenter,
│   │                      # ScanErrorNotice, NoSearchMatchesView
│   ├── Services/          # AdaptiveTrustSession, AdaptiveExecutionControl, AppState,
│   │                      # CleanerCoreLiveScan, CleanerCoreBridge, PermissionsService,
│   │                      # PermissionProbe, OpenFileActivityObserver, HomebrewService,
│   │                      # BrowserCleanerService, DuplicateScanner, OrphanedFilesScanner,
│   │                      # StartupItemsService, SystemStatsProvider, TrashInventoryReader,
│   │                      # SafetyDiagnosticLogger, LocalizationManager, ReadOnlyProcess,
│   │                      # DirectorySize, InstalledApplications, SharedScanStore
│   └── Models/            # ScanResult, PermissionCategory, UpdateCapability
├── Features/              # AdaptiveExperience, Home, DiskCleaner, SpaceLens, OrphanedFiles,
│                          # Duplicates, Performance, Applications, PortManagement,
│                          # SystemHealth, StartupItems, Permissions
├── MenuBar/               # MenuBarController, MenuBarView
└── Resources/             # Assets.xcassets and String Catalogs: Common.xcstrings (shared keys, the
                           # Adaptive Experience adaptive.* and receipt.* keys, fallback table), one
                           # per other feature (Space Lens keys in DiskCleaner), MenuBar, Settings
CleanerCore/               # Local package: scan, policy, plan, Trash execution, receipts
                           # (pure core plus Foundation, Darwin and ContentAdapter targets; docs/C4.md)
SafetyContract/            # Local package: disabled-operation gateway, redacted diagnostics
```

## Key Technical Decisions

- **Single mutation**: only `FoundationTrashAdapter` calls `trashItem(`, for an approved,
  digest-bound `ReviewPlan`, re-validated per item (fresh scan still policy-eligible, inside
  `GeneralMacScopeProof.namedCacheComponent`, same identity, link count 1). No `removeItem`
  (except receipt tombstones and stale receipt-journal temp files), no `Process()` outside `scripts/read-only-process-allowlist.txt`,
  no `URLSession`, AppleScript, or privilege elevation.
- **Eligibility**: only `PolicyEvaluator.evaluateCache` can make an item eligible (one named cache
  folder, inactive 15+ minutes). Owner catalogs and process activity may only narrow it.
- **General-Mac scanning**: `GeneralMacFilesystemAdapter` walks each root breadth-first; unreadable
  entries are skipped and reported, and per-root caps (depth 8, 25,000 entries, 10,000 findings)
  record an issue and move on to the next root.
- **Memory calculation**: Active + Wired + Compressed (matches htop)
- **Homebrew detection**: Checks both `/opt/homebrew/bin/brew` (ARM) and `/usr/local/bin/brew` (Intel)
- **Permissions**: TCC folders trigger dialog via `FileManager.contentsOfDirectory()`, FDA requires System Settings
- **Liquid Glass**: `#available(macOS 26, *)` checks with `.ultraThinMaterial` fallback

## Build Commands

```bash
xcodebuild -project MyMacCleaner.xcodeproj -scheme MyMacCleaner build
bash scripts/verify-all.sh   # what safety-contract.yml runs; --fast skips Swift tests and coverage
xcodebuild test -project MyMacCleaner.xcodeproj -scheme MyMacCleaner \
  -destination 'platform=macOS' -only-testing:MyMacCleanerTests \
  -enableCodeCoverage YES -resultBundlePath build/TestResults.xcresult
bash scripts/check-app-coverage.sh build/TestResults.xcresult   # app coverage ratchet
swiftlint lint                                                  # CI pins SwiftLint 0.65.1
```

Gate details: `CONTRIBUTING.md` (Local gates). Rule IDs in verifier failures: `docs/VERIFIER-RULES.md`.

## Release Process

```bash
./scripts/release.sh <version> --dry-run
./scripts/release.sh <version> [--notes <file>]
```

Developer ID only, no update channel. The script refuses dirty (including untracked) or off-`main`
trees, runs unit tests and all verifiers, archives with the identity from `.env`
(`APPLE_TEAM_ID`, `MACOS_CERTIFICATE_SHA1`, optional `NOTARY_PROFILE`), notarizes and staples the
app and DMG, checks both with `spctl`, and creates a **draft** release from a `release/v<version>`
branch. Nothing is pushed to `main`. Details: `RELEASE.md`, `docs/RELEASE-RUNBOOK.md`.
Local Xcode signing: `Config/Signing.xcconfig` + gitignored `Config/Signing.local.xcconfig`.

## CI

- `.github/workflows/pr-checks.yml`: Debug/Release build, unit tests with the app coverage ratchet
  (`scripts/check-app-coverage.sh`, baseline in `scripts/app-coverage-baseline.txt`), ad hoc archive
  signature check, blocking SwiftLint (pinned 0.65.1, checksum-verified; errors fail the job,
  warnings are reported), 800-line file limit. UI tests run but are advisory. The Build job also
  makes universal `build-for-testing` products; advisory `Unit Tests (macos-14)` and
  `Unit Tests (macos-15)` jobs run them with `test-without-building`.
- `.github/workflows/safety-contract.yml`: runs `scripts/verify-all.sh` (safety, CleanerCore 80% gate,
  CleanerCore contract, Adaptive verifiers, and verifier self-tests).
- Both workflows select Xcode 26 (`XCODE_MAJOR`) on `macos-26` runners and fail if it is missing;
  they never fall back to another Xcode.

## Dependencies

| Package | Purpose |
|---------|---------|
| CleanerCore (local) | Scan, policy, plan, Trash execution, receipts |
| SafetyContract (local) | Disabled-operation gateway and redacted diagnostics |

No remote packages. The app has no update channel (`UpdateCapability.unavailable`).
The app target builds with `SWIFT_STRICT_CONCURRENCY = complete` (Swift 5 mode).

## Guidelines

- Use async/await and actors for thread safety
- Keep views simple, logic in ViewModels
- General-Mac scanning goes through CleanerCore; legacy read-only scanners use
  `enumerator(at:includingPropertiesForKeys:)`
- New detectors and owner rules may only narrow eligibility, test-first
- Run `bash scripts/verify-all.sh` before every commit (the five verifiers and every verifier
  self-test, as CI runs them)
- Cancel operations when user navigates away
- Never store passwords; request permissions at point of use
- Update `docs/*.md` when features change
