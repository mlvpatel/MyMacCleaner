# CleanerCore coverage

The 80%-per-target line-coverage gate is enforced by `scripts/verify-cleanercore.sh` in CI
(`.github/workflows/safety-contract.yml` → "Verify CleanerCore"), which is **green on the current
`main` HEAD** and passes locally on full Xcode 27.

**Latest run:**

- Date: 2026-09-22
- Environment: full Xcode 27 (`xcode-select` → `/Applications/Xcode.app/Contents/Developer`)
- Command: `bash scripts/verify-cleanercore.sh`
- Result: **CLEANERCORE-GATE: PASS**
- Tests in the coverage run: **353 tests / 56 suites**

| Target | Covered / total | Percent |
|--------|-----------------|---------|
| Aggregate | 8042 / 9029 | **89.07%** |
| CleanerCore | 5145 / 5632 | **91.35%** |
| CleanerCoreFoundation | 1702 / 2050 | **83.02%** |
| CleanerCoreDarwin | 821 / 914 | **89.82%** |
| CleanerCoreContentAdapter | 374 / 433 | **86.37%** |

Every production target is at or above **80.00%**. This is SwiftPM line coverage, not an Xcode UI coverage report. Signing, notarization, and XCUITest are not part of this measurement.

> Toolchain note: Xcode 27's build system emits one `*Tests.xctest` bundle per test target under
> `out/Products/Debug` instead of a single merged `CleanerCorePackageTests.xctest`. The gate now
> discovers every `*Tests` test binary (and profiles under any `codecov` directory) and passes them
> all to `llvm-cov`, so it produces coverage on both the classic and the Xcode 27 layouts.

The previous figure (2026-08-31, 7982/8940, 89.28%) is superseded.

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

