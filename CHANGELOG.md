# Changelog

All notable changes to MyMacCleaner will be documented in this file.

## [Unreleased]

<!-- Add your changes here during development. This section will be used for the next release. -->
<!-- Format: - [type] Description -->
<!-- Types: added, changed, fixed, removed -->

- [fixed] Scans no longer stop at the first unreadable folder or drop the remaining locations when one fails; gaps are reported as a partial scan
- [fixed] Scans walk each location shallow-first, so one large deep folder cannot hide the rest under the per-location cap
- [fixed] Live scans use the real clock, so the inactivity rule for the named cache can pass
- [fixed] Receipt file names no longer exceed the macOS file-name limit for long item paths
- [fixed] Execute re-checks policy on a fresh scan (including open files), refuses hardlinked files, and allows only regular files inside the named cache scope
- [fixed] A Trash move without a returned location is recorded as moved; a run that never started is reported as refused
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
