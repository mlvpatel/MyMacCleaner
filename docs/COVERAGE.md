# CleanerCore coverage

Canonical local gate, measured **after Phase 8 production files and Adaptive Experience localization**:

- Date: 2026-08-31
- Environment: Command Line Tools (`xcode-select` → `/Library/Developer/CommandLineTools`)
- Command: `CODEX_SANDBOX=1 bash scripts/verify-cleanercore.sh`
- Result: **CLEANERCORE-GATE: PASS**
- Tests in the coverage run: **349 tests / 55 suites**

| Target | Covered / total | Percent |
|--------|-----------------|---------|
| Aggregate | 7982 / 8940 | **89.28%** |
| CleanerCore | 5086 / 5558 | **91.51%** |
| CleanerCoreFoundation | 1701 / 2035 | **83.59%** |
| CleanerCoreDarwin | 821 / 914 | **89.82%** |
| CleanerCoreContentAdapter | 374 / 433 | **86.37%** |

Every production target is at or above **80.00%**. This is SwiftPM line coverage, not an Xcode UI coverage report. Signing, notarization, and XCUITest are not part of this measurement.

The previous Phase 7 figure (7567/8461, 89.43%) is superseded.

## App target coverage (MyMacCleaner.app)

- Date: 2026-09-17
- Measured with the app sources and all 107 unit-test runs compiled under Command Line Tools with
  `-profile-coverage-mapping` (swift-testing macros rewritten to plain calls), then `llvm-cov report`.
- Whole app target: **8.4% lines**. SwiftUI views and design components are not unit-tested and
  make up most lines.
- Logic files only (services, view models, models; views and design excluded): **35.5% lines**.

CI enforces a ratchet, not the 80% goal: `scripts/check-app-coverage.sh` fails the Unit Tests job
when Xcode's `MyMacCleaner.app` line coverage drops below `scripts/app-coverage-baseline.txt`
(currently 0.075) and posts a notice when coverage is a full point above it. Raise the baseline as
tests land. The Xcode figure from the first hosted run replaces the local measurement above.

