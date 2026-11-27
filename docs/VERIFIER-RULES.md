# Verifier rules

Every failure from the verifier scripts starts with a rule ID, usually followed by the file and line
that broke it, and ends with a link to the rule's entry below.

`scripts/tests/verify-rule-docs-tests.sh` fails when a rule ID in `scripts/` has no entry here, so add
the entry in the same change as the rule.

## Safety contract

Raised by `scripts/verify-safety-contract.sh` and its coverage checker `scripts/check-safety-coverage.swift`.

### SC-COVERAGE-ARGUMENTS

Fails when `check-safety-coverage.swift` is not given exactly three option pairs (`--input`, `--source-root`, `--minimum`), or an option is unknown or repeated.

### SC-COVERAGE-ARITHMETIC

Fails when summing the executable or covered line counts, or scaling them for the percentage comparison, overflows an integer in `check-safety-coverage.swift`.

### SC-COVERAGE-BELOW-MINIMUM

Fails when total covered lines across the SafetyContract production sources fall below the `--minimum` percentage of executable lines (the gate passes 80).

### SC-COVERAGE-CHECKER

Fails when the canonical gate cannot find a readable `scripts/check-safety-coverage.swift`.

### SC-COVERAGE-DUPLICATE-SOURCE

Fails when the same SafetyContract production source file appears more than once in the `llvm-cov` export.

### SC-COVERAGE-EXPORT

Fails when `llvm-cov export` exits with an error or writes an empty coverage JSON file.

### SC-COVERAGE-LINE-COUNTS

Fails when a production source's `summary.lines.count` or `summary.lines.covered` is not a non-negative integer (booleans are rejected), or the covered count exceeds the executable count.

### SC-COVERAGE-MALFORMED

Fails when the coverage JSON cannot be read or parsed, has no non-empty `data` array, or a data set lacks `files`, a file lacks `filename`, or a production source lacks `summary.lines`; also the checker's catch-all for unexpected errors.

### SC-COVERAGE-MINIMUM

Fails when the coverage checker's `--minimum` value is not a whole number from 1 to 100.

### SC-COVERAGE-MISSING-SOURCE

Fails when the coverage export does not contain an entry for every `.swift` file under the SafetyContract source root.

### SC-COVERAGE-PRODUCTION-SOURCE

Fails when the coverage checker finds no non-hidden `.swift` files under the `--source-root` directory.

### SC-COVERAGE-PROFILE

Fails when the test run leaves no fresh `codecov/*.profraw` profile under `SafetyContract/.build`, or `llvm-profdata merge` fails on the profiles it found.

### SC-COVERAGE-SOURCE-ROOT

Fails when `SafetyContract/Sources/SafetyContract` (or the checker's `--source-root`) is not an existing directory or cannot be enumerated.

### SC-COVERAGE-TEMPORARY

Fails when the canonical gate cannot create its temporary coverage directory with `mktemp -d`.

### SC-COVERAGE-TEST-BINARY

Fails when no `*Tests.xctest/Contents/MacOS/*Tests` binary is found next to the fresh coverage profiles, or a found test binary is not executable.

### SC-COVERAGE-TOOL

Fails when `xcrun --find` cannot locate `llvm-profdata` or `llvm-cov`, or the located tool is not executable.

### SC-COVERAGE-ZERO-LINES

Fails when a SafetyContract production source reports zero executable lines in the coverage export, or the total executable line count is zero.

### SC-DESTRUCTIVE-COPY

Fails when `Applications.xcstrings` keeps uninstall, updates, Homebrew cleanup or upgrade, or matching toast keys, or `Performance.xcstrings` keeps maintenance, `purgeDiskCache`, `canBeFreed` or `performance.processes.kill` keys.

### SC-DESTRUCTIVE-UI

Fails when a scanned Swift file contains `role: .destructive`, `moveToTrash`, `willDelete`, `markForDeletion` or `willBeDeleted`.

### SC-DIAGNOSTIC-LOGGER

Fails when `StartupItemsService.swift` or `OpenFileActivityObserver.swift` does not contain `import SafetyContract` and a `SafetyDiagnosticLogger.emit(` call.

### SC-DIAGNOSTIC-RAW-SINK

Fails when any Swift file under `MyMacCleaner/`, including `StartupItemsService.swift`, calls `print(`, `debugPrint(` or `NSLog(`.

### SC-DOCS-READ-ONLY

Fails when a feature page under `docs/` (home, performance, port-management, permissions, startup-items, system-health, applications, disk-cleaner, duplicates, orphaned-files, space-lens) lacks its exact required read-only sentence.

### SC-DOCS-UNSAFE-CLAIM

Fails when a `docs/` feature page contains a banned action claim such as `sudo`, `Free Memory`, `Move to Trash`, `Force Kill`, `Safe to Delete` or an admin password prompt, or a page-specific phrase like `brew upgrade` or `launchctl unload`. Also fails when any root or `docs/` Markdown file shows `removeItem(`, `AuthorizationService`, `runWithAdminPrivileges`, `AuthorizationCreate`, `AuthorizationExecute`, `NSAppleScript`, `osascript` or `with administrator privileges` inside a fenced code example.

### SC-ELEVATION

Fails when a scanned Swift file contains `NSAppleScript`, `AuthorizationCreate`, `AuthorizationExecute`, `with administrator privileges` or `osascript`.

### SC-FIXTURE-AUTHORIZATION

Fails when a self-test fixture flag or test variable is used without `SAFETY_CONTRACT_SELF_TEST_SENTINEL=SAFETY-CONTRACT-SELF-TEST` or its matching contract flag, or with invalid values, such as a `--fixture-root` or `--fixture-process-root` outside `scripts/tests/fixtures/safety-contract`. The forbidden-target fixture must be a readable `mymaccleaner-expected-absent.*` file outside the repo containing `absent` or `reintroduced`.

### SC-FORBIDDEN-TARGET

Fails when a removed file returns (`AuthorizationService.swift`, `UpdateRow.swift`, `UpdateManager.swift`, `UpdateAvailableButton.swift` or `appcast.xml`, per mode), or in self-test the expected-absent fixture says `reintroduced`.

### SC-FOUNDATION-CAPABILITY

Fails when `SafetyContract/Package.swift` contains `Process(`, `URLSession`, `NSAppleScript` or `Authorization`.

### SC-HOME-MEMORY-CLAIM

Fails when `HomeViewModel.swift` or `HomeView.swift` contains free-memory, purge-cache or RAM-cleaning wording such as `freeMemory`, `free memory`, `purge cache` or `RAM optimize` (the view also bans `home.actions.freeMemory`).

### SC-HOME-MEMORY-GUIDANCE

Fails when `AppState.swift` lacks `case .memoryGuide:` or `return .performance` (the per-window routing of Home links), or `HomeView.swift` lacks `L("home.actions.memoryGuide")` or `action: { open(.memoryGuide) }`.

### SC-HOME-MEMORY-LOCALIZATION

Fails when `Home.xcstrings` still has `home.actions.emptyTrash` or `home.actions.freeMemory`, or `home.actions.memoryGuide` is missing, not English-only, or has an empty value.

### SC-INVALID-INPUT

Fails on bad arguments: a missing or repeated `--fixture-root`, `--fixture-manifest` or `--fixture-process-root` value, a `--product-root` flag, two mode flags, an unreadable fixture root, or a fixture flag paired with a mode it does not support.

### SC-MANIFEST-COUNT

Fails when `scripts/read-only-process-allowlist.txt` (or the fixture manifest) does not contain exactly five non-comment entries.

### SC-MANIFEST-DUPLICATE

Fails when the process allowlist manifest repeats an identical entry.

### SC-MANIFEST-FIELD

Fails when a manifest entry has an empty owner, parser or rationale, an owner that is not a `MyMacCleaner/*.swift` path, a parser that is not a plain identifier, or a rationale without the words `no network`.

### SC-MANIFEST-IDENTITY

Fails when the five manifest entries do not exactly match, in order, the expected `sfltool dumpbtm`, `launchctl list`, two `lsof` and `diskutil info /` entries hard-coded in the verifier.

### SC-MANIFEST-SCHEMA

Fails when a manifest line has more than six fields or an empty identifier, executable or arguments field.

### SC-MANIFEST-UNREADABLE

Fails when the process allowlist manifest (default `scripts/read-only-process-allowlist.txt` or the `--fixture-manifest` path) does not exist or cannot be read.

### SC-MANIFEST-WILDCARD

Fails when any manifest field contains a `*`, `?` or `[` wildcard character.

### SC-MISSING-TARGET

Fails when a file the verifier must read is missing or unreadable: a mode's target source, a String Catalog, a `docs/` page, a process adapter, `SafetyContract/Package.swift` or a diagnostics source. Self-tests force it with `SAFETY_CONTRACT_TEST_MISSING_TARGET`.

### SC-MIXED-ROOTS

Fails when incompatible inputs are combined: `--product-root` after `--fixture-root`, both `--fixture-forbidden-target-contract` and `--fixture-mode-target-contract`, or `--fixture-root` or `--fixture-process-root` with any other fixture, manifest, mode or contract flag.

### SC-NETWORK-CAPABILITY

Fails when a Swift file in `SafetyContract/Sources/SafetyContract`, or `SafetyNoticePresenter.swift`, contains `URLSession`, `URLRequest`, `NSURLSession`, `Network.framework`, `import Network`, `NWConnection`, `NWListener`, `NWPathMonitor` or an `http(s)://` URL.

### SC-PASS

Not a failure: the stdout prefix the verifier prints when a run passes, such as `SC-PASS: canonical safety contract verification passed`.

### SC-PERFORMANCE-ADAPTER

Fails when `PerformanceViewModel.swift` lacks the exact lines `import CleanerCore` and `import CleanerCoreDarwin`, or does not reference `MemoryObservationPort` and `DarwinMemoryObservationAdapter`.

### SC-PERFORMANCE-ATOMIC-PRESENTATION

Fails when `PerformanceViewModel.swift` lacks `@Published private(set) var presentation = MemoryCoachPresentation.unavailable` or does not contain exactly one `self.presentation = nextPresentation` assignment.

### SC-PERFORMANCE-CANCELLATION

Fails when `PerformanceViewModel.swift` lacks `private var refreshTask: Task<Void, Never>?`, `refreshTask?.cancel()`, `refreshGeneration` or `guard isMonitoring else { return }`, or `PerformanceView.swift` lacks `viewModel.startMonitoring()` or `viewModel.stopMonitoring()`.

### SC-PERFORMANCE-CLAIM

Fails when `PerformanceView.swift` contains purge, `runAll`, free RAM or boost-performance wording, or legacy memory UI such as `memoryGauge`, `usagePercentage`, `memoryColor`, `memoryUsage` or `performance.memory.used`.

### SC-PERFORMANCE-CLEANUP

Fails when `AppState.swift` still mentions `stopProcessMonitoring`.

### SC-PERFORMANCE-COACHING

Fails when `PerformanceViewModel.swift` lacks `MemoryCoachingRules` or `rules.evaluate(snapshot: snapshot, contexts: contexts)`, or `PerformanceView.swift` lacks `viewModel.presentation.explanation` or `viewModel.presentation.processIssueKeys`.

### SC-PERFORMANCE-EVIDENCE

Fails when `PerformanceViewModel.swift` lacks `WorkloadEvidencePort`, `LocalWorkloadEvidenceProducer(completedInventory: [])` or `.context(sessionID: snapshot.sessionID, process: process)`.

### SC-PERFORMANCE-LOCALE-PARITY

Fails when `Performance.xcstrings` is not `en`-sourced, misses a required coach or memory key, keeps a legacy key, has any entry that is not English-only with a non-empty value, or any value claims to free RAM, boost performance, optimize memory or "guarantee".

### SC-PERFORMANCE-MUTATION

Fails when `PerformanceViewModel.swift` contains maintenance, kill or purge tokens (`MaintenanceTask`, `onKill`, `runAll`), a `confirmationDialog`, or direct memory APIs such as `host_statistics64`, `sysctlbyname` or `ProcessInfo.processInfo.physicalMemory`.

### SC-PERFORMANCE-OBSERVATION

Fails when `PerformanceView.swift` does not render `viewModel.presentation.fields`.

### SC-PERFORMANCE-PRESSURE

Fails when `PerformanceView.swift` does not render `viewModel.presentation.pressure`.

### SC-PERFORMANCE-PRESSURE-FRESHNESS

Fails when `PerformanceView.swift` lacks the pressure cases `case .stale, .unavailableNoFreshEvent:`, `case .observed(.warning, _):` or `case .observed(.critical, _):`.

### SC-PERFORMANCE-PRESSURE-LIFECYCLE

Fails when `PerformanceViewModel.swift` does not call both `pressureLifecycle?.startPressureSource()` and `pressureLifecycle?.stopPressureSource()`.

### SC-PERFORMANCE-PROCESS-ACTION

Fails when `ProcessRow.swift` has kill or destructive tokens, an interactive control (`Button {`, `Link(`, `Menu {`, `.contextMenu`, `.onTapGesture`), or reads `process.user`, `process.cpuPercent`, `process.arguments`, `process.environment`, `process.path` or `process.content`.

### SC-PERFORMANCE-PROCESS-MODEL

Fails when `PerformanceView.swift` lacks `viewModel.presentation.processes`, or `ProcessRow.swift` lacks `let process: MemoryCoachProcessRow`, `process.label.value`, `process.residentBytes` or `process.contextKey.rawValue`.

### SC-PERFORMANCE-REFRESH

Fails when `PerformanceView.swift` does not call `viewModel.refreshMemoryCoach()`.

### SC-PERMANENT-MUTATION

Fails when a scanned Swift file calls `removeItem(`, `/bin/rm`, `rm -rf`, `emptyTrash` or `trashItem(`, except one `trashItem(` in `FoundationTrashAdapter.swift` and one bare `.emptyTrash` case line in `SafetyNoticePresenter.swift`.

### SC-PORT-MUTATION

Fails when `PortManagementViewModel.swift` contains kill-flow names (`prepareKill`, `confirmKill`, `cancelKill`, `connectionToKill`, `showKillConfirmation`), or `PortManagementView.swift` contains those, `onKill`, `portManagement.kill` or `role: .destructive`.

### SC-PROCESS-COUNT

Fails when the process owner `MyMacCleaner/Core/Services/ReadOnlyProcess.swift` does not build exactly one child process (`Process(`, `Process.run`, `NSTask` or `posix_spawn`).

### SC-PROCESS-DRAIN-ORDER

Fails when a scanned source file calls `waitUntilExit` after creating a `Process` and before draining its output with `readDataToEndOfFile` or `readToEnd`; read the pipe to the end first, then wait.

### SC-PROCESS-IDENTITY

Fails when `ReadOnlyProcess.swift` does not set its one `executableURL` and one `arguments` from `command.invocation`, when its lines holding a literal path or string array are not exactly the five allowlisted invocations (`sfltool dumpbtm`, `launchctl list`, the two `lsof` calls, `diskutil info /`, so an extra or changed executable or argument fails), or when `parseDiskInfo` or `parseOpenFilePaths` is missing. Self-tests run it on the `process-owner` fixture trees through `--fixture-process-root`.

### SC-README-READ-ONLY

Fails when `README.md` lacks the read-only feature table rows for Performance, Port Management and System Health, or mentions `RAM optimization`, `maintenance scripts`, `View and kill processes` or `Manage startup items`.

### SC-STALE-MUTATION-CALLBACK

Fails when a scanned Swift file keeps old cleanup flow names such as `showDeleteConfirmation`, `prepareClean(`, `confirmDelete(`, `nodeToDelete`, `itemsToClean`, `deleteFiles(`, or any identifier starting with `onClean`, `onDelete`, `onRemove` or `onTrash`.

### SC-STARTUP-MUTATION

Fails when `StartupItemsViewModel.swift` contains toggle or remove flow names (`prepareToggle`, `confirmRemove`, `itemToToggle`, `showRemoveConfirmation`), or `StartupItemsView.swift` contains `onToggle`, `onRemove`, `startupItems.toggle` or `startupItems.remove`.

### SC-STARTUP-SETTINGS-LOCALIZATION

Fails when `StartupItems.xcstrings` lacks `startupItems.openLoginItemsSettings` with exactly one non-empty English value.

### SC-STARTUP-SETTINGS-ROUTE

Fails when the Login Items route is incomplete (`import ServiceManagement`, `SMAppService.openSystemSettingsLoginItems()`, `openLoginItemsSettings()` wiring, `L("startupItems.openLoginItemsSettings")`), or `StartupItemsViewModel.swift` uses `Process(`, `URL(string:`, `NSWorkspace`, `open -a` or `/usr/bin/open`.

### SC-SYSTEM-MUTATION

Fails when a scanned Swift file contains `/usr/sbin/purge`, `purge(`, `kill(`, `terminate(`, `setItemEnabled(` or `removeStartupItem(`, except one bare `process.terminate()` line in `ReadOnlyProcess.swift`, which stops its own child on timeout or cancellation.

### SC-TARGET-COVERAGE

Fails when, in a `--fixture-mode-target-contract` self-test run, the `SAFETY_CONTRACT_TEST_EXPECT_TARGET` path is not in the selected mode's target list.

### SC-UNKNOWN-MODE

Fails when the verifier gets an unrecognized argument, a fixture manifest or contract flag without a mode flag, or a mode that has no target list.

### SC-UNLISTED-PROCESS

Fails when any Swift file under `MyMacCleaner/` other than `Core/Services/ReadOnlyProcess.swift` builds a child process (`Process(`, `Process.run`, `NSTask` or `posix_spawn`); fixture scans never allow it.

### SC-UPDATE-CAPABILITY

Fails when a `.swift` or `.plist` file under `MyMacCleaner/` contains `URLSession`, `URLRequest`, `import Sparkle`, an `SPU` symbol, `SUFeedURL`, `SUPublicEDKey` or `appcast`, or `project.pbxproj` mentions `Sparkle`.

## CleanerCore source contract

Raised by `scripts/verify-cleanercore-contract.sh`.

### CC-AMBIENT-AUTHORITY

Fails when a source in the pure `CleanerCore` target uses ambient authority: `FileManager`, `URL(` or `URL.`, `Date(`, `Date.now`, `DispatchTime`, `DispatchQueue`, `Task.sleep`, `UUID(` or a `.shared` singleton.

### CC-BRIDGE-BOUNDARY

Fails when the retired legacy scanner `MyMacCleaner/Core/Services/FileScanner.swift` exists again; Home and Disk Cleaner must scan only through `CleanerCoreLiveScan`.

### CC-CONTENT-CRYPTOKIT-OWNER

Fails when `CleanerCoreContentAdapter/StreamingContentEvidenceAdapter.swift` is missing or lacks `import CryptoKit`, or when any other content adapter source or any pure `CleanerCore` source imports `CryptoKit`.

### CC-CONTENT-DARWIN-AUTHORITY

Fails when a `CleanerCoreContentAdapter` source other than `StreamingContentEvidenceAdapter.swift` imports `Darwin`, or that file lacks it. Also fails on write `O_` flags, mutating calls like `write`, `unlink`, `rename` or `chmod`, or any `open` except `return Darwin.open(path, ...)` with `O_RDONLY`, `O_NOFOLLOW` and `O_CLOEXEC`.

### CC-CONTENT-DIGEST-LEAK

Fails when a `CleanerCoreContentAdapter` source passes a `digest` or `ContentDigest` to `print`, `debugPrint`, `NSLog`, `os_log` or `Logger`, or uses `String(describing: digest)`.

### CC-CONTENT-IMPORT

Fails when a `CleanerCoreContentAdapter` source imports any module other than `CleanerCore`, `CryptoKit`, `Darwin` or `Foundation`.

### CC-CONTENT-LOCATOR-LEAK

Fails when a `CleanerCoreContentAdapter` source passes a `locator`, `URL.path` or other `.path` value to `print`, `debugPrint`, `NSLog`, `os_log` or `Logger`.

### CC-CONTENT-ROOT-AUTHORITY

Fails when a `CleanerCoreContentAdapter` source has a `public init` taking a root, path or directory `URL`, or uses `mountedVolumeURLs`, `NSOpenPanel`, `URL(fileURLWithPath: "/")` or a `/Volumes/` path.

### CC-CONTENT-UNSELECTED-BRANCH

Fails when a `StreamingContentEvidenceAdapter.swift` file exists in the `CleanerCoreFoundation` target; the content adapter belongs only in `CleanerCoreContentAdapter`.

### CC-DARWIN-CONTROL-CAPABILITY

Fails when a `CleanerCoreDarwin` source uses process or memory control calls: `proc_terminate`, `proc_set*`, `proc_signal`, `proc_suspend`, `proc_resume`, `kill`, `killpg`, `setpriority`, `task_for_pid`, `mach_vm_*`, `vm_purg*` or `purge`.

### CC-DARWIN-FILESYSTEM-CAPABILITY

Fails when a `CleanerCoreDarwin` source uses `FileManager`, `FileHandle`, `Data(contentsOf:)`, `String(contentsOf:)`, `URL(fileURLWithPath:)` or POSIX file calls such as `open`, `fopen`, `stat`, `readlink`, `unlink`, `rename`, `mkdir`, `chmod` or `access`.

### CC-DARWIN-IMPORT

Fails when a `CleanerCoreDarwin` source imports any module other than `CleanerCore`, `Darwin`, `Dispatch` or `Foundation`.

### CC-DARWIN-NETWORK-CAPABILITY

Fails when a `CleanerCoreDarwin` source calls a socket API: `socket`, `connect`, `bind`, `listen`, `accept`, `send`, `sendto`, `recv`, `recvfrom` or `getaddrinfo`.

### CC-DARWIN-PRIVILEGE-CAPABILITY

Fails when a `CleanerCoreDarwin` source calls `setuid`, `seteuid`, `setgid` or `setegid`, or uses `AuthorizationCreate`, `AuthorizationExecute` or `SMJobBless`.

### CC-DARWIN-PROCESS-CAPABILITY

Fails when a `CleanerCoreDarwin` source calls `fork`, `vfork` or an `exec` function (`execl`, `execle`, `execlp`, `execv`, `execve`, `execvp`).

### CC-DARWIN-SENSITIVE-METADATA

Fails when a `CleanerCoreDarwin` source mentions process or user metadata tokens such as `arguments`, `environment`, `currentDirectory`, `proc_pidpath`, `proc_regionfilename`, `pbi_uid`, `pbi_ruid`, `prompt`, `repository`, `model`, `username`, `openFiles` or `executablePath`.

### CC-DARWIN-SETTINGS-CAPABILITY

Fails when a `CleanerCoreDarwin` source uses `UserDefaults`, `NSUserDefaults`, `CFPreferences` or `sysctl(`, or any `sysctlbyname` call other than `sysctlbyname("vm.swapusage", &usage, &size, nil, 0)`.

### CC-DIAGNOSTIC-PAYLOAD

Fails when a `case` inside `enum ScanDiagnosticEvent` in a CleanerCore library source carries a `ScanOutcome`, `ScanIssue`, `DeclaredRootID`, `DetectorID`, `RelativeLocator` or `String` as its associated value.

### CC-DYNAMIC-REGISTRY

Fails when a CleanerCore library source other than `AppSupportReceiptStore.swift` uses dynamic loading or decoding: `dlopen`, `dlsym`, `NSClassFromString`, `Bundle.main`, `Bundle(`, `plugin` or `PlugIn`, `DetectorRegistry` built `from` input, or `JSONDecoder(`.

### CC-ELEVATION-CAPABILITY

Fails when a CleanerCore library source uses `NSAppleScript`, `AuthorizationCreate`, `AuthorizationExecute`, `with administrator privileges`, `SMAppService` or `ServiceManagement`.

### CC-EMPTY-SCOPE

Fails when a directory scanned as a whole (one of the four CleanerCore library targets, the `MyMacCleaner` app folder, or a fixture root) contains no `.swift` files.

### CC-FIXTURE-AUTHORIZATION

Fails when `--fixture-root` or `--fixture-manifest` is used without the environment variable `CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL` set to `CLEANERCORE-CONTRACT-SELF-TEST`, so fixture modes run only from the verifier self-tests.

### CC-FORBIDDEN-IMPORT

Fails when a CleanerCore library source imports `SwiftUI`, `AppKit`, `UIKit`, `WebKit`, `Sparkle`, `Network` or `CloudKit`, or checks `SwiftUI`, `AppKit`, `Sparkle`, `Network` or `CloudKit` with `canImport`.

### CC-FOUNDATION-AMBIENT

Fails when a `CleanerCoreFoundation` source uses `FileManager.default`, `Date.now`, `URLSession` or `Process(`.

### CC-FOUNDATION-IMPORT

Fails when a `CleanerCoreFoundation` source imports anything besides `Foundation` and `CleanerCore`; only `CryptoKitPlanDigestAdapter.swift` may import `CryptoKit`, and `DarwinReceiptLease.swift` may import `Darwin`.

### CC-INVALID-ROOT

Fails when a fixture root or manifest path is not a readable directory or file, or when `--fixture-root` or `--fixture-manifest` lacks a value, is repeated, both are given, or `--fixture-manifest` follows a non-`pure` target or `--fixture-model-inventory-scope`.

### CC-MISSING-SCOPE

Fails when any of the four target source folders under `CleanerCore/Sources` (`CleanerCore`, `CleanerCoreFoundation`, `CleanerCoreDarwin`, `CleanerCoreContentAdapter`) is missing or unreadable.

### CC-MODEL-AUTHORITY

Fails when an AI model inventory source (`CleanerCore/ModelInventory` or the listed model-store boundary files and tests) references `CleanableItem`, `PolicyPort`, `ExecutionPort`, `ReceiptPort`, `ModelStoreCandidate`, `ModelStoreOperation` or `OperationPlan`.

### CC-MODEL-LINK-FOLLOW

Fails when an AI model inventory source (`CleanerCore/ModelInventory` or the listed model-store boundary files and tests) follows symlinks with `resolvingSymlinksInPath` or `destinationOfSymbolicLink`.

### CC-MODEL-MISSING-SCOPE

Fails when `CleanerCore/Sources/CleanerCore/ModelInventory` (or the model-scope fixture folder) is missing, unreadable or has no `.swift` files, or when one of the eight listed model-store boundary files is missing or unreadable.

### CC-MODEL-MUTATION

Fails when an AI model inventory source (`CleanerCore/ModelInventory` or the listed model-store boundary files and tests) calls `removeItem(`, `trashItem(`, `replaceItemAt`, `createFile(`, `FileHandle` for writing or `write(`.

### CC-MODEL-NETWORK

Fails when an AI model inventory source (`CleanerCore/ModelInventory` or the listed model-store boundary files and tests) uses `URLSession`, `URLRequest`, `NSURLSession`, `NWConnection`, `NWListener`, `NWPathMonitor` or an `http://` or `https://` address.

### CC-MODEL-PROCESS

Fails when an AI model inventory source (`CleanerCore/ModelInventory` or the listed model-store boundary files and tests) uses `Process(`, `posix_spawn`, `system(`, `NSTask`, `/bin/sh`, `/bin/bash`, `/bin/zsh`, `/usr/bin/osascript` or `/usr/bin/open`.

### CC-MODEL-REAL-HOME

Fails when an AI model inventory source (`CleanerCore/ModelInventory` or the listed model-store boundary files and tests) reads the real home through `NSHomeDirectory`, `homeDirectoryForCurrentUser`, `ProcessInfo.processInfo.environment` or a literal `/Users/` path.

### CC-MODEL-ROOT-INFERENCE

Fails when an AI model inventory source (`CleanerCore/ModelInventory` or the listed model-store boundary files and tests) infers roots by subscripting `environment[...]`, hard-coding `.ollama/models` or using `FileManager.default`.

### CC-MUTATION-CAPABILITY

Fails when a CleanerCore library source calls `removeItem(`, `trashItem(`, `replaceItemAt`, `createFile(`, `FileHandle` for writing or `write(`; only `FoundationTrashAdapter.swift`, `DarwinReceiptLease.swift` (`write` only) and `AppSupportReceiptStore.swift` (`removeItem` but no `trashItem`) are exempt.

### CC-NETWORK-CAPABILITY

Fails when a CleanerCore library source uses `URLSession`, `URLRequest`, `NSURLSession`, `NWConnection`, `NWListener`, `NWPathMonitor` or contains an `http://` or `https://` address.

### CC-PACKAGE-CONTENT-ADAPTER

Fails when `CleanerCore/Package.swift` does not declare `.library(name: "CleanerCoreContentAdapter", targets: ["CleanerCoreContentAdapter"])` (whitespace is ignored).

### CC-PACKAGE-DARWIN

Fails when `CleanerCore/Package.swift` does not declare `.library(name: "CleanerCoreDarwin", targets: ["CleanerCoreDarwin"])` (whitespace is ignored).

### CC-PACKAGE-DARWIN-DEPENDENCY

Fails when `CleanerCore/Package.swift` does not declare `.target(name: "CleanerCoreDarwin", dependencies: ["CleanerCore"])` (whitespace is ignored).

### CC-PACKAGE-DARWIN-TEST-DEPENDENCY

Fails when `CleanerCore/Package.swift` does not declare `.testTarget(name: "CleanerCoreDarwinTests", dependencies: ["CleanerCore", "CleanerCoreDarwin"])` (whitespace is ignored).

### CC-PACKAGE-FOUNDATION

Fails when `CleanerCore/Package.swift` does not declare both `.library(name: "CleanerCoreFoundation", targets: ["CleanerCoreFoundation"])` and `.target(name: "CleanerCoreFoundation", dependencies: ["CleanerCore"])`.

### CC-PACKAGE-MANIFEST

Fails when the package manifest being checked (`CleanerCore/Package.swift`, or a fixture manifest) is missing or unreadable.

### CC-PACKAGE-PRODUCT-GRAPH

Fails when `CleanerCore/Package.swift` does not declare exactly four `.library` products, once each: `CleanerCore`, `CleanerCoreFoundation`, `CleanerCoreContentAdapter` and `CleanerCoreDarwin`, each built only from its same-named target.

### CC-PACKAGE-PURE

Fails when `CleanerCore/Package.swift` does not declare `.library(name: "CleanerCore", targets: ["CleanerCore"])` and a dependency-free `.target(name: "CleanerCore")`.

### CC-PACKAGE-REVERSE-DEPENDENCY

Fails when the `CleanerCore` target in `CleanerCore/Package.swift` declares any `dependencies:`; the pure core must not depend on other targets.

### CC-PACKAGE-TARGET-GRAPH

Fails when `CleanerCore/Package.swift` does not declare exactly eight targets once each: `CleanerCore` with no dependencies, `CleanerCoreFoundation`, `CleanerCoreContentAdapter` and `CleanerCoreDarwin` depending only on `CleanerCore`, and four test targets with fixed dependency lists.

### CC-PASS

Not a failure: the prefix of the success line printed when the full CleanerCore source contract, a fixture scan or a manifest fixture check passes.

### CC-PLAN-DIGEST-ADAPTER

Fails when `CleanerCoreFoundation/CryptoKitPlanDigestAdapter.swift` is missing or unreadable, or does not contain `import CryptoKit` and `SHA256`.

### CC-PLAN-EXECUTION-RECEIPT

Fails when a policy, review plan or capability source (`Policy`, `Plans` or `Capability` in the `CleanerCore` target) references `ExecutionPort` or `ReceiptPort`.

### CC-PLAN-MISSING-SCOPE

Fails when the `Policy`, `Plans` or `Capability` folder under `CleanerCore/Sources/CleanerCore` is missing or unreadable.

### CC-PLAN-MUTATION

Fails when a policy, review plan or capability source (`Policy`, `Plans` or `Capability` in the `CleanerCore` target) uses `trashItem(`, `removeItem(`, `emptyTrash` or `NSWorkspace`.

### CC-PLAN-PERSISTENT-APPROVAL

Fails when a policy, review plan or capability source (`Policy`, `Plans` or `Capability` in the `CleanerCore` target) uses `UserDefaults`, declares `isApproved: Bool` or sets `approved = true`.

### CC-PLAN-PUBLIC-CANDIDATE

Fails when a policy, review plan or capability source (`Policy`, `Plans` or `Capability` in the `CleanerCore` target) has a `public init` taking an `EligibleCandidate` or a `candidate:` parameter.

### CC-PRIVACY-CAPABILITY

Fails when any Swift file in the `MyMacCleaner` app folder mentions analytics, advertising, sign-in or cloud terms such as `Analytics`, `Telemetry`, `Firebase`, `Sentry`, `AdSupport`, `OAuth`, `Account`, `CloudKit`, `iCloud`, `Dropbox` or `remote inventory`.

### CC-PROCESS-CAPABILITY

Fails when a CleanerCore library source mentions `Process(`, `posix_spawn`, `system(`, `NSTask`, `/bin/sh`, `/bin/bash`, `/bin/zsh`, `/usr/bin/osascript`, `/usr/bin/open` or the word `shell`, even in a comment.

### CC-PURE-IMPORT

Fails when any source in the pure `CleanerCore` target, including the receipt core files in `Receipts`, has a top-level `import` line.

### CC-RECEIPT-CORE-AUTHORITY

Fails when a receipt core source in `CleanerCore/Sources/CleanerCore/Receipts` mentions `Codable`, `Decodable`, `FileManager`, `URL(`, `ApprovalAttestation`, `trashItem(`, `UserDefaults`, `restore`, `compensat` or `retry`.

### CC-RECEIPT-MISSING-SCOPE

Fails when `CleanerCore/Sources/CleanerCore/Receipts` or one of `ReceiptSchema.swift`, `ReceiptReducer.swift`, `ReceiptReconciliation.swift` and `ReceiptRetention.swift` in it is missing or unreadable.

### CC-REMOTE-DEPENDENCY

Fails when `CleanerCore/Package.swift` contains a `.package(` dependency or any `url:` argument; CleanerCore takes no remote packages.

### CC-ROOT-ESCAPE

Fails when a fixture root or fixture manifest resolves to a path outside `scripts/tests/fixtures/cleanercore-contract`.

### CC-SILENT-ERROR

Fails when a CleanerCore library source has an empty `catch {}` block on one line or uses `try?`.

### CC-TRASH-COMPENSATION

Fails when a Trash execution source (`CleanerCore/Execution` or `Ports/TrashExecutionPort.swift`) mentions `retry`, `rollback`, `restore` or `compensat`, even in a comment.

### CC-TRASH-DECODED-OPERATION

Fails when a Trash execution source (`CleanerCore/Execution` or `Ports/TrashExecutionPort.swift`) mentions `Codable` or `Decodable`.

### CC-TRASH-MISSING-SCOPE

Fails when the `CleanerCore/Sources/CleanerCore/Execution` folder or `CleanerCore/Sources/CleanerCore/Ports/TrashExecutionPort.swift` is missing or unreadable.

### CC-TRASH-MUTATION

Fails when a Trash execution source (`CleanerCore/Execution` or `Ports/TrashExecutionPort.swift`) uses `emptyTrash`, `removeItem(` or `trashItem(`; the Trash call belongs only to `FoundationTrashAdapter.swift`.

### CC-TRASH-PARALLEL

Fails when a Trash execution source (`CleanerCore/Execution` or `Ports/TrashExecutionPort.swift`) uses `withTaskGroup`, `TaskGroup` or `async let`.

### CC-TRASH-PERSISTENCE

Fails when a Trash execution source (`CleanerCore/Execution` or `Ports/TrashExecutionPort.swift`) references `ReceiptPort`, `UserDefaults` or `historyWriter`.

### CC-TRASH-PUBLIC-INPUT

Fails when a Trash execution source (`CleanerCore/Execution` or `Ports/TrashExecutionPort.swift`) uses `URL` as a type or constructor: `: URL`, `URL?`, `[URL]` or `URL(`.

### CC-TRASH-PUBLIC-OPERATION

Fails when a Trash execution source (`CleanerCore/Execution` or `Ports/TrashExecutionPort.swift`) has a `public init` with a `target:`, `path:`, `category:` or `callback:` parameter.

### CC-TRASH-SOLE-CALL

Fails when `CleanerCoreFoundation/FoundationTrashAdapter.swift` is missing, unreadable or does not have `trashItem(` on exactly one line, or when any other source under `CleanerCore/Sources` calls `trashItem(`.

### CC-UNKNOWN-MODE

Fails on an unknown option, a missing or unsupported `--fixture-target` value, a repeated `--fixture-model-inventory-scope`, that flag without the `model` target, or a non-`pure` target or scope flag given with a manifest or without a fixture root.

### CC-UPDATE-OWNER

Fails when a retired updater file, `MyMacCleaner/Core/Services/UpdateManager.swift` or `appcast.xml`, exists again.

### CC-UPDATE-REACHABILITY

Fails when any source under `CleanerCore/Sources` mentions `UpdateManager`, `Sparkle`, `SPU`, `SUUpdater`, `URLSession` or an `http://` or `https://` address.

## CleanerCore test and coverage gate

Raised by `scripts/verify-cleanercore.sh`, its coverage checker `scripts/check-cleanercore-coverage.swift`, and the receipt schema preflight `scripts/preflight-receipt-schema.sh`.

### CC-COVERAGE-ARGUMENTS

Fails when the coverage checker does not get exactly `--input`, `--source-root` and `--minimum`, each once with a value, or gets any other option.

### CC-COVERAGE-ARITHMETIC

Fails when summing line counts, or scaling them for the percentage comparison, overflows a Swift `Int`.

### CC-COVERAGE-BELOW-MINIMUM

Fails when aggregate line coverage, or any single production target's line coverage, is below `--minimum` percent; the per-target form adds the target name, covered/executable counts and the required percentage.

### CC-COVERAGE-DECLARATION-DRIFT

Fails when `CleanerCoreDarwin/DarwinMemorySystem.swift`, the one source allowed to have no coverage entry, contains anything beyond body-less protocol, enum or struct declarations, such as code, bodies or default values; the target name is appended.

### CC-COVERAGE-DUPLICATE-SOURCE

Fails when the same production source file appears more than once in the coverage JSON, including across separate `data` entries.

### CC-COVERAGE-INPUT

Fails when the `--input` coverage JSON path does not exist, is a directory or other non-regular file, or cannot be read.

### CC-COVERAGE-LINE-COUNTS

Fails when a file's `summary.lines.count` or `summary.lines.covered` is not a non-negative integer (booleans are rejected), or the covered count exceeds the executable count.

### CC-COVERAGE-MALFORMED

Fails when the coverage JSON does not parse, has no non-empty `data` array, or an entry lacks `files`, a non-empty `filename` or `summary.lines`; also reported for any unexpected checker error.

### CC-COVERAGE-MINIMUM

Fails when `--minimum` is not a whole number from 1 to 100.

### CC-COVERAGE-MISSING-SOURCE

Fails when a production Swift file (other than the allowed declaration-only file) has no entry in the coverage JSON, or a production target has no coverage entries at all; the target name is appended.

### CC-COVERAGE-PRODUCTION-SOURCE

Fails when a target folder (`CleanerCore`, `CleanerCoreFoundation`, `CleanerCoreDarwin`, `CleanerCoreContentAdapter`) is missing or has no countable Swift files, or the coverage JSON names a production Swift file the source scan did not find.

### CC-COVERAGE-SOURCE-ROOT

Fails when `--source-root` is not a readable directory, a file under a production target cannot be enumerated or inspected, or the declaration-only source cannot be read as UTF-8.

### CC-COVERAGE-SYMLINK

Fails when the source root, a production target folder, any file inside one, the `--input` JSON, or a filename listed in the coverage JSON is a symbolic link.

### CC-COVERAGE-UNKNOWN-TARGET

Fails when the coverage JSON lists a Swift file under the source root whose top-level folder is not one of the four CleanerCore production targets.

### CC-COVERAGE-ZERO-LINES

Fails when a production file reports zero executable lines in the coverage JSON, or the aggregate or a target totals zero executable lines; the target name or `aggregate` is appended.

### CC-GATE-ARGUMENTS

Fails when `scripts/verify-cleanercore.sh` gets any arguments other than none or exactly `--fixture-tools`.

### CC-GATE-CONTRACT

Fails when `scripts/verify-cleanercore-contract.sh` is missing or not executable.

### CC-GATE-CONTRACT-SELF-TEST

Fails when the contract verifier's self-test file `scripts/tests/verify-cleanercore-contract-tests.sh` is missing or unreadable.

### CC-GATE-COVERAGE-CHECKER

Fails when `scripts/check-cleanercore-coverage.swift` is not a readable regular file.

### CC-GATE-COVERAGE-DECISION

Fails when `scripts/check-cleanercore-coverage.swift`, run with `--minimum 80` on the exported coverage JSON and `CleanerCore/Sources`, exits non-zero; the checker's own `CC-COVERAGE-*` line appears just before it.

### CC-GATE-COVERAGE-EXPORT

Fails when `llvm-cov export` over the merged profile and the test binaries exits non-zero or writes an empty coverage JSON.

### CC-GATE-COVERAGE-PROFILE

Fails when no `.profraw` file exists under a `codecov` folder in the scratch path, any profile predates the coverage test run, `llvm-profdata merge -sparse` fails, or the merged profile is empty.

### CC-GATE-COVERAGE-SELF-TEST

Fails when the coverage checker's self-test file `scripts/tests/check-cleanercore-coverage-tests.sh` is missing or unreadable.

### CC-GATE-DEVELOPER-DIR

Fails when `xcode-select -p` errors, or the developer directory it prints is not a directory, cannot be resolved with `realpath`, or resolves to `/`.

### CC-GATE-FIXTURE-AUTHORIZATION

Fails when `--fixture-tools` is passed without `CLEANERCORE_GATE_SELF_TEST_SENTINEL=CLEANERCORE-GATE-SELF-TEST`; this guard keeps the fixture tool paths for the gate's self-tests only.

### CC-GATE-LLVM-TOOL

Fails when `xcrun --find llvm-profdata` or `xcrun --find llvm-cov` errors, the reported path cannot be resolved with `realpath`, or the resolved tool is not executable.

### CC-GATE-LLVM-TRUST

Fails when the resolved `llvm-profdata` or `llvm-cov` lies outside the developer directory selected by `xcode-select -p`.

### CC-GATE-RUNNER

Fails when `scripts/run-cleanercore-tests.sh` is missing or not executable.

### CC-GATE-RUNNER-SELF-TEST

Fails when the test runner's self-test file `scripts/tests/run-cleanercore-tests-tests.sh` is missing or unreadable.

### CC-GATE-SOURCE-ROOT

Fails when `CleanerCore/Sources` is not a directory, or the gate cannot change into the repository root.

### CC-GATE-SWIFT-TOOL

Fails when the Swift binary is not executable: `/usr/bin/swift` normally, or `CLEANERCORE_FIXTURE_SWIFT_BIN` under `--fixture-tools`.

### CC-GATE-TEMPORARY

Fails when the gate cannot create and resolve its temporary coverage directory under `$TMPDIR` (default `/tmp`), its `swiftpm-scratch` subfolder (which must resolve inside it), or the freshness marker file.

### CC-GATE-TEST-BINARY

Fails when the coverage test run leaves no `*Tests.xctest/Contents/MacOS/*Tests` binary in the scratch path, or any such binary is not executable or not newer than the pre-test freshness marker.

### CC-GATE-TOOL-OVERRIDE

Fails when the gate runs without arguments while `SWIFT_BIN`, `XCRUN_BIN` or `XCODE_SELECT_BIN` is set in the environment, even to an empty value.

### CC-GATE-XCODE-SELECT-TOOL

Fails when the xcode-select binary is not executable: `/usr/bin/xcode-select` normally, or `CLEANERCORE_FIXTURE_XCODE_SELECT_BIN` under `--fixture-tools`.

### CC-GATE-XCRUN-TOOL

Fails when the xcrun binary is not executable: `/usr/bin/xcrun` normally, or `CLEANERCORE_FIXTURE_XCRUN_BIN` under `--fixture-tools`.

### CC-RECEIPT-PREFLIGHT

Not a failure: the success line `CC-RECEIPT-PREFLIGHT: PASS declarations=N map=M` printed when every receipt schema preflight check passes.

### CC-RECEIPT-PREFLIGHT-ARGUMENTS

Fails when the preflight gets any argument other than one `--fixture-root <directory>`, including a repeated `--fixture-root` or one without a value.

### CC-RECEIPT-PREFLIGHT-AST-FAILURE

Fails when `/usr/bin/swiftc -frontend -dump-parse` exits non-zero on a checked Swift source or its output lacks a `(source_file` node.

### CC-RECEIPT-PREFLIGHT-AUTHORIZATION

Fails when `--fixture-root` is passed without `RECEIPT_PREFLIGHT_SELF_TEST_SENTINEL=RECEIPT-PREFLIGHT-SELF-TEST`; this guard keeps fixture roots for the preflight's self-tests only.

### CC-RECEIPT-PREFLIGHT-DUPLICATE

Fails when the receipt declaration map (embedded in the script, or the fixture's `expected.map`) lists the same identifier more than once.

### CC-RECEIPT-PREFLIGHT-HASH

Not a failure: after the PASS line, one such line per checked Swift source reports its path and pinned SHA-256.

### CC-RECEIPT-PREFLIGHT-INVENTORY-MISMATCH

Fails when the types, enum cases and optional types found by the regex source scan differ from those found in the `swiftc` parse dump.

### CC-RECEIPT-PREFLIGHT-MISSING-SOURCE

Fails when one of the ten pinned Swift sources under `CleanerCore/Sources/CleanerCore` is missing, or a fixture root is unreadable, has no `.swift` files, or lacks `expected.map` or `expected.sha256`.

### CC-RECEIPT-PREFLIGHT-MISSING-SUMMARY

Fails when one of the four planning summary files the canonical preflight requires is missing or empty. The public repository does not include them, so only fixture mode, which the self-tests use and which skips this check, runs there.

### CC-RECEIPT-PREFLIGHT-OPTIONALITY

Fails when a map row's optionality column (`required` or `optional`) differs from what the source scan reports for that identifier.

### CC-RECEIPT-PREFLIGHT-STALE-HASH

Fails when a checked Swift source's SHA-256 differs from its pinned hash in the script (or the fixture's `expected.sha256`), or no hash is pinned for it.

### CC-RECEIPT-PREFLIGHT-UNMAPPED

Fails when a declaration map row has fewer than four tab-separated fields, or the map's identifiers do not exactly match the declarations found in the checked sources (missing or extra entries).

## Adaptive Experience

Raised by `scripts/verify-adaptive-bridge.sh` and `scripts/verify-adaptive-experience.sh`.

### AE-BRIDGE

Not a failure: the prefix of the success line `AE-BRIDGE: PASS` printed by `scripts/verify-adaptive-bridge.sh`.

### AE-BRIDGE-AUTHORITY

Fails when the Adaptive Experience view model (`AdaptiveExperienceViewModel.swift`, or the file given as the first argument) mentions `FileScanner`, `trashItem`, `removeItem`, `Process(`, `URLSession`, `posix_spawn`, `NSAppleScript`, `isApproved`, `ApprovalAttestation`, `MoveToTrash`, `ScanRequest`, `GeneralMacRootKind`, `FileManager` or `URL(`; it must reach CleanerCore only through the bridge.

### AE-BRIDGE-IMPORT

Fails when the Adaptive Experience view model does not contain `import CleanerCore`.

### AE-BRIDGE-INTENT

Fails when the Adaptive Experience view model does not mention `AdaptiveSafeIntent`, the closed enum of actions the screen may send.

### AE-BRIDGE-MISSING

Fails when the Adaptive Experience view model file is missing or unreadable.

### AE-BRIDGE-PERSONA

Fails when the Adaptive Experience view model contains `persona`, `isTechnicalUser`, `cleanScore` or `cleanliness`; explanation depth must not profile the user or score the Mac.

### AE-CATALOG-KEY

Fails when a required Adaptive Experience string key (listed in `scripts/verify-adaptive-experience.sh`) is missing from `MyMacCleaner/Resources/Common.xcstrings`.

### AE-CATALOG-LINT

Fails when `MyMacCleaner/Resources/Common.xcstrings` cannot be parsed as JSON or its `sourceLanguage` is not `en`.

### AE-CATALOG-MISSING

Fails when `MyMacCleaner/Resources/Common.xcstrings` does not exist.

### AE-EMPTY

Fails when an `adaptive.*`, `receipt.recovery.*` or `navigation.adaptive*` string in `Common.xcstrings` has a missing or blank English value.

### AE-EXPERIENCE

Not a failure: the prefix of the success line `AE-EXPERIENCE: PASS` printed by `scripts/verify-adaptive-experience.sh`.

### AE-ID-MISSING

Fails when a required accessibility identifier listed in `scripts/verify-adaptive-experience.sh`, such as `adaptive.approval.confirm` or `adaptive.scan.stop`, appears in none of the five Adaptive Experience views.

### AE-LOCALE-PARITY

Fails when an `adaptive.*`, `receipt.recovery.*` or `navigation.adaptive*` string in `Common.xcstrings` has any localization set other than exactly English (`en`).

### AE-SENSITIVE

Fails when an `adaptive.*`, `receipt.recovery.*` or `navigation.adaptive*` string in `Common.xcstrings` contains `/Users/` or `rm -rf` (any case).

### AE-STABLE-ID

Fails when one of the five Adaptive Experience views has no `accessibilityIdentifier("adaptive.`, `identifier: "adaptive.` or `accessibilityIdentifier("developer.` identifier.

### AE-VIEW-AUTHORITY

Fails when one of the five Adaptive Experience views mentions `FileScanner`, `trashItem`, `cleanScore` or `isTechnicalUser`.

### AE-VIEW-MISSING

Fails when one of the five Adaptive Experience view files listed in `scripts/verify-adaptive-experience.sh` is missing.
