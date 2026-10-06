# Changelog

All notable changes to MyMacCleaner will be documented in this file.

## [Unreleased]

<!-- Add your changes here during development. This section will be used for the next release. -->
<!-- Format: - [type] Description -->
<!-- Types: added, changed, fixed, removed -->
<!-- DRAFT for 1.0.0: summary of the rewrite since 0.1.3. Edit before release. -->

### 1.0 rewrite (since 0.1.3)

- [changed] Rebuilt as a safety-first app: privileged shell, `rm`, Empty Trash, memory purge, process termination, app uninstall and cleanup scripts are disabled behind a `SafetyContract` gateway
- [added] `CleanerCore` package: local evidence, conservative policy, digest-bound review plans, a revalidated Trash executor and receipts
- [added] General-Mac evidence for six locations: Library Caches, Logs, Temporary, Downloads, Desktop and Documents
- [added] Adaptive Experience with Guided, Standard and Technical views and a review, approve, move-to-Trash, receipt flow
- [added] Private local receipts with recovery guidance and bounded history (90 days, 500 receipts)
- [added] Read-only AI/ML model inventory (Hugging Face, Ollama, LM Studio, MLX) and developer-tool presence (Cursor, VS Code, Docker, Homebrew)
- [added] Read-only memory and workload coach
- [changed] Disk Cleaner, Space Lens, Duplicates, Orphaned Files, Performance, Applications, Port Management, System Health and Startup Items are read-only inventories
- [changed] English-only String Catalogs (Italian and Spanish removed, along with the language picker)
- [removed] Sparkle auto-update and the appcast: the app has no `URLSession` and no update channel; install new versions from a reviewed release

### Pre-release QA fixes

- [fixed] Scans no longer stop at the first unreadable folder or drop the remaining locations when one fails; gaps are reported as a partial scan
- [fixed] Scans walk each location shallow-first, so one large deep folder cannot hide the rest under the per-location cap
- [fixed] Live scans use the real clock, so the inactivity rule for the named cache can pass
- [fixed] Receipt file names no longer exceed the macOS file-name limit for long item paths
- [fixed] Execute re-checks policy on a fresh scan (including open files), refuses hardlinked files, and allows only regular files inside the named cache scope
- [fixed] A Trash move without a returned location is recorded as moved; a run that never started is reported as refused
- [fixed] The dashboard and review sheet show the first 50 evidence items plus a count of the rest, so large scans no longer stall the UI
- [fixed] The loading-dots animation no longer leaks a repeating timer each time it appears
- [changed] The app target builds with zero concurrency warnings (all 45 would be errors in Swift 6 mode)
- [changed] Large scans finish about 3x faster (result sorting no longer re-encodes every item per comparison)
- [removed] Obsolete Mac App Store submission guide (Developer ID distribution only)

## [0.1.3] - 2026-01-31

- [fixed] Improve array mutation safety to prevent potential crashes when using Select/Deselect All
- [fixed] Unsafe ForEach pattern in ScanResultsCard that could cause index out of bounds
- [fixed] Force unwrap in FileScanner that could crash if categories array was empty
- [fixed] CGGradient force unwraps in SpaceLensView with fallback rendering
- [fixed] Unsafe direct array index access in PerformanceView

## [0.1.2] - 2026-01-25

- [fixed] Hide toolbar background to prevent visible bar in DetailContentView

## [0.1.1] - 2025-01-24

- [added] `pageTopPadding` theme constant for consistent page layouts
- [changed] All feature views now use dedicated top padding (32pt) for better visual consistency
- [fixed] Permissions page now uses consistent header styling (fonts, spacing) matching other views
- [fixed] Permissions refresh button now uses GlassActionButton component like other pages
- [fixed] NavigationSectionTests updated to include all 10 navigation sections
- [fixed] Flaky testSidebarNavigation UI test now checks for correct elements

## [0.1.0] - 2025-01-20

- Initial release
