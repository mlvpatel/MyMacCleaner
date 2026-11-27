import Testing
import Foundation
import AppKit
@testable import MyMacCleaner

// MARK: - Disk Cleaner Inventory Tests

@Suite("Disk Cleaner Inventory Tests")
@MainActor
struct DiskCleanerInventoryTests {
    private func item(_ name: String, _ size: Int64, _ category: ScanCategory) -> CleanableItem {
        CleanableItem(
            name: name,
            path: URL(fileURLWithPath: "/tmp/\(name)"),
            size: size,
            modificationDate: nil,
            category: category
        )
    }

    private func makeViewModel() -> DiskCleanerViewModel {
        let viewModel = DiskCleanerViewModel()
        viewModel.scanResults = [
            ScanResult(category: .caches, items: [item("a", 100, .caches), item("b", 50, .caches)]),
            ScanResult(category: .logs, items: [item("c", 10, .logs)]),
        ]
        return viewModel
    }

    @Test("Totals cover every finding")
    func totalsCoverEveryFinding() {
        let viewModel = makeViewModel()

        #expect(viewModel.totalReviewableSize == 160)
        #expect(viewModel.totalItemCount == 3)
    }

    @Test("Unknown categories are ignored")
    func ignoresUnknownCategories() {
        let viewModel = makeViewModel()

        #expect(viewModel.result(for: .documents) == nil)
        #expect(viewModel.result(for: .logs)?.itemCount == 1)
    }

    @Test("The detail sheet always shows the live result for its category")
    func detailSheetReadsLiveResult() {
        let viewModel = makeViewModel()

        viewModel.showDetails(for: .caches)
        #expect(viewModel.detailCategory == .caches)
        #expect(viewModel.detailResult?.itemCount == 2)

        viewModel.scanResults = [ScanResult(category: .caches, items: [item("z", 1, .caches)])]
        #expect(viewModel.detailResult?.itemCount == 1)

        viewModel.scanResults = []
        #expect(viewModel.detailResult == nil)
    }

    @Test("Category expansion toggles open and closed")
    func togglesExpansion() {
        let viewModel = makeViewModel()

        viewModel.toggleCategoryExpansion(.caches)
        #expect(viewModel.expandedCategory == .caches)
        viewModel.toggleCategoryExpansion(.caches)
        #expect(viewModel.expandedCategory == nil)
    }
}

// MARK: - Home View Model Tests

@Suite("Home View Model Tests")
@MainActor
struct HomeViewModelTests {
    @Test("Smart Scan without Full Disk Access asks for permission before scanning")
    func promptsForPermissionFirst() {
        let viewModel = HomeViewModel()
        viewModel.hasFullDiskAccess = false

        viewModel.startSmartScan()

        #expect(viewModel.showPermissionPrompt)
        #expect(viewModel.isScanning == false)

        viewModel.dismissPermissionPrompt()
        #expect(viewModel.showPermissionPrompt == false)
    }

    /// Never finishes on its own, so a scan stays running until the test cancels it.
    private static func endlessStore() -> SharedScanStore {
        SharedScanStore(scan: {
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        })
    }

    @Test("After Limited Scan the Full Disk Access prompt stays away for the session")
    func limitedScanChoiceIsRemembered() {
        let viewModel = HomeViewModel(scanStore: Self.endlessStore())
        viewModel.hasFullDiskAccess = false

        viewModel.startSmartScan()
        viewModel.continueWithLimitedScan()
        viewModel.cancelScan()
        viewModel.startSmartScan()

        #expect(viewModel.showPermissionPrompt == false)
        #expect(viewModel.isScanning)
        viewModel.cancelScan()
    }

    @Test("Maybe Later still asks again on the next scan")
    func maybeLaterAsksAgain() {
        let viewModel = HomeViewModel(scanStore: Self.endlessStore())
        viewModel.hasFullDiskAccess = false

        viewModel.startSmartScan()
        viewModel.dismissPermissionPrompt()
        viewModel.startSmartScan()

        #expect(viewModel.showPermissionPrompt)
        #expect(viewModel.isScanning == false)
    }

    @Test("Granting Full Disk Access while the prompt is open closes it and runs the scan")
    func grantingAccessClosesPrompt() {
        let viewModel = HomeViewModel(scanStore: Self.endlessStore())
        viewModel.hasFullDiskAccess = false
        viewModel.startSmartScan()

        viewModel.updateFullDiskAccess(true)

        #expect(viewModel.showPermissionPrompt == false)
        #expect(viewModel.isScanning)
        viewModel.cancelScan()
    }

    @Test("The Trash safety notice shows and dismisses")
    func trashNoticeShowsAndDismisses() {
        let viewModel = HomeViewModel()

        viewModel.explainTrashSafety()

        #expect(viewModel.toasts.current?.safetyNotice != nil)
        viewModel.toasts.dismiss()
        #expect(viewModel.toasts.current == nil)
    }

    @Test("Before any scan the cache tile asks the user to scan")
    func cacheTileStartsHonest() {
        #expect(HomeViewModel().cacheAndLogSize == L("home.stats.scanToCheck"))
    }

    @Test("The cache tile counts caches, logs and temporary files but never personal folders")
    func cacheTileExcludesPersonalFolders() {
        func result(_ category: ScanCategory, _ size: Int64) -> ScanResult {
            ScanResult(category: category, items: [
                CleanableItem(
                    name: category.rawValue,
                    path: URL(fileURLWithPath: "/tmp/\(category.rawValue)"),
                    size: size,
                    modificationDate: nil,
                    category: category
                )
            ])
        }
        let results = [
            result(.caches, 1), result(.logs, 2), result(.temporaryFiles, 4),
            result(.downloads, 8), result(.desktop, 16), result(.documents, 32)
        ]

        #expect(HomeViewModel.cacheAndLogBytes(in: results) == 7)
    }
}

// MARK: - Port Management State Tests

@Suite("Port Management State Tests")
@MainActor
struct PortManagementStateTests {
    private func connection(_ name: String, local: Int, remote: Int?, state: String) -> NetworkConnection {
        NetworkConnection(
            processName: name,
            pid: 1,
            localAddress: "127.0.0.1",
            localPort: local,
            remoteAddress: remote == nil ? nil : "10.0.0.1",
            remotePort: remote,
            state: state,
            protocol: "TCP"
        )
    }

    @Test("Filters and search narrow the sorted connection list")
    func filtersConnections() {
        let viewModel = PortManagementViewModel()
        viewModel.cancelRefresh()
        viewModel.connections = [
            connection("zeta", local: 9000, remote: nil, state: "LISTEN"),
            connection("alpha", local: 80, remote: 443, state: "ESTABLISHED"),
            connection("beta", local: 8080, remote: nil, state: "LISTEN"),
        ]

        #expect(viewModel.filteredConnections.map(\.localPort) == [80, 8080, 9000])
        #expect(viewModel.listeningCount == 2)
        #expect(viewModel.establishedCount == 1)

        viewModel.filterType = .listening
        #expect(viewModel.filteredConnections.map(\.processName) == ["beta", "zeta"])

        viewModel.filterType = .all
        viewModel.searchText = "808"
        #expect(viewModel.filteredConnections.map(\.processName) == ["beta"])

        viewModel.searchText = "ZET"
        #expect(viewModel.filteredConnections.map(\.processName) == ["zeta"])
    }

    @Test("A failed read says so instead of looking like no connections")
    func failedReadIsUnavailable() async {
        let viewModel = PortManagementViewModel(readPorts: { nil })

        viewModel.refreshConnections()
        await viewModel.refreshTask?.value

        #expect(viewModel.isUnavailable)
        #expect(viewModel.lastRead == nil)
        #expect(viewModel.connections.isEmpty)
    }

    @Test("A successful read, even an empty one, records when the list was read")
    func successfulReadIsTimestamped() async {
        let viewModel = PortManagementViewModel(readPorts: { [] })

        viewModel.refreshConnections()
        await viewModel.refreshTask?.value

        #expect(viewModel.isUnavailable == false)
        #expect(viewModel.lastRead != nil)
    }
}

// MARK: - Startup Items State Tests

@Suite("Startup Items State Tests")
@MainActor
struct StartupItemsStateTests {
    private func item(_ name: String, enabled: Bool, running: Bool, system: Bool) -> StartupItem {
        StartupItem(
            id: name, name: name, label: name, type: .launchAgent, path: "/tmp/\(name).plist",
            executablePath: nil, isEnabled: enabled, isRunning: running, isSystemItem: system,
            developer: nil, bundleIdentifier: nil
        )
    }

    @Test("Every stat counts the same user items, so Running can't exceed Total")
    func statsCountTheSameItems() {
        let viewModel = StartupItemsViewModel {}
        viewModel.items = [
            item("user-running", enabled: true, running: true, system: false),
            item("user-idle", enabled: false, running: false, system: false),
            item("system-a", enabled: true, running: true, system: true),
            item("system-b", enabled: true, running: true, system: true),
        ]

        #expect(viewModel.totalCount == 2)
        #expect(viewModel.runningCount == 1)
        #expect(viewModel.enabledCount + viewModel.disabledCount == viewModel.totalCount)
    }
}

// MARK: - Permissions View Model Tests

@Suite("Permissions View Model Tests")
@MainActor
struct PermissionsViewModelTests {
    @Test("All permission categories are built once, in a stable order")
    func buildsCategories() {
        let viewModel = PermissionsViewModel()

        #expect(viewModel.categories.map(\.type) == PermissionCategoryType.allCases)
    }

    @Test("Toggling a category expands and collapses only that category")
    func togglesCategory() throws {
        let viewModel = PermissionsViewModel()
        let first = try #require(viewModel.categories.first)
        let wasExpanded = first.isExpanded
        let othersBefore = viewModel.categories.dropFirst().map(\.isExpanded)

        viewModel.toggleCategory(first.id)

        #expect(viewModel.categories.first?.isExpanded == !wasExpanded)
        #expect(viewModel.categories.dropFirst().map(\.isExpanded) == othersBefore)
    }

    @Test("Grant on a folder macOS still refuses opens Files and Folders and says so")
    func stillDeniedFolderOpensFilesAndFolders() async {
        var opened: [String] = []
        let viewModel = PermissionsViewModel(openURL: { opened.append($0.absoluteString) })
        let folder = FolderAccessInfo(
            path: "/nonexistent-\(UUID().uuidString)",
            displayName: "Desktop",
            status: .denied,
            canTriggerTCCDialog: true
        )

        await viewModel.requestAccess(to: folder)

        #expect(opened == ["x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"])
        #expect(viewModel.toasts.current?.message == LFormat("permissions.folder.stillDenied %@", "Desktop"))
    }

    @Test("Only folders macOS lets the user change get a System Settings button")
    func manageButtonOnlyWhereAccessCanChange() {
        let folders = PermissionsViewModel().categories.flatMap(\.folders)
        let managed = Set(folders.filter(\.isAccessManagedInSystemSettings).map(\.path))

        #expect(managed.contains("~/Desktop"))
        #expect(managed.contains("~/Library/Safari/Bookmarks.plist"))
        // World-readable folders: nothing in System Settings changes access to them.
        #expect(!managed.contains("/System/Library/LaunchAgents"))
        #expect(!managed.contains("/Library/Caches"))
        #expect(!managed.contains("~/Library/Caches"))
    }

    @Test("The Full Disk Access prompt lists only what the app reads with it")
    func fullDiskAccessFeaturesAreReal() {
        let features = PermissionsService.fullDiskAccessInfo.localizedFeatures

        #expect(features.count == 5)
        #expect(!features.contains { $0.localizedCaseInsensitiveContains("mail") })
        // A missing catalog key would show as the raw key.
        #expect(!features.contains { $0.hasPrefix("permissions.") })
    }
}

// MARK: - Menu Bar Tests

@Suite("Menu Bar Tests")
@MainActor
struct MenuBarTests {
    private static let displayModeKey = "menuBarDisplayMode"

    @Test("Display modes are localized and round-trip through their raw values")
    func displayModesAreStable() {
        for mode in MenuBarController.DisplayMode.allCases {
            #expect(!mode.localizedName.isEmpty)
            #expect(MenuBarController.DisplayMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("A chosen display mode is persisted and restored")
    func persistsDisplayMode() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Self.displayModeKey)
        let controller = MenuBarController.shared
        let originalMode = controller.displayMode
        defer {
            if let previous {
                defaults.set(previous, forKey: Self.displayModeKey)
            } else {
                defaults.removeObject(forKey: Self.displayModeKey)
            }
            controller.displayMode = originalMode
        }

        controller.setDisplayMode(.ramOnly)
        controller.displayMode = .icon
        controller.loadSavedDisplayMode()

        #expect(controller.displayMode == .ramOnly)
    }

    @Test("Icon mode shows no numbers, so stats are sampled only while the popover is open")
    func samplesOnlyWhenSomethingShowsStats() {
        for mode in MenuBarController.DisplayMode.allCases where mode != .icon {
            #expect(MenuBarController.needsSampling(mode: mode, isPopoverShown: false))
        }
        #expect(!MenuBarController.needsSampling(mode: .icon, isPopoverShown: false))
        #expect(MenuBarController.needsSampling(mode: .icon, isPopoverShown: true))
    }
}

// MARK: - App State Tests

@Suite("App State Tests")
@MainActor
struct AppStateTests {
    @Test("Space Lens keeps one shared state for the sidebar and Disk Cleaner tab")
    func sharesSpaceLensState() {
        let appState = AppState()
        let first = appState.spaceLensViewModel

        #expect(appState.spaceLensViewModel === first)
        #expect(first.isScanning == false)
        #expect(appState.adaptiveExperienceViewModel.isExecuting == false)
    }

    @Test("Each Home link names its section and readies that page; the caller switches its own window")
    func homeLinksReadyTheirPage() {
        let appState = AppState()

        #expect(appState.destination(for: .experience) == .adaptiveExperience)
        #expect(appState.destination(for: .permissions) == .permissions)
        #expect(appState.destination(for: .trashExplanation) == .adaptiveExperience)

        // Large Files opens Space Lens filtered to large items. Space Lens never scans on entry.
        #expect(appState.destination(for: .largeFiles) == .spaceLens)
        #expect(appState.spaceLensViewModel.sizeFilter == .over100MB)
        #expect(appState.spaceLensViewModel.isScanning == false)

        // Memory Guide opens Performance at its guidance, once.
        #expect(appState.destination(for: .memoryGuide) == .performance)
        #expect(appState.performanceViewModel.consumeGuidanceRequest())
        #expect(appState.performanceViewModel.consumeGuidanceRequest() == false)
    }

    @Test("The menu bar Scan request switches to Home and starts the Smart Scan flow")
    func menuBarScanRequestStartsSmartScan() {
        let center = NotificationCenter()
        let appState = AppState(notificationCenter: center)
        appState.homeViewModel.hasFullDiskAccess = false

        center.post(name: .triggerSmartScan, object: nil)

        #expect(appState.smartScanRequests == 1)
        // Without Full Disk Access the Smart Scan starts by asking, exactly like the Home button.
        #expect(appState.homeViewModel.showPermissionPrompt)
        #expect(appState.homeViewModel.isScanning == false)
    }

    private func waitForMainWindow(_ isPresent: Bool) async -> Bool {
        for _ in 0..<100 where NSApp.windows.contains(where: MyMacCleanerApp.isMainWindow) != isPresent {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return NSApp.windows.contains(where: MyMacCleanerApp.isMainWindow) == isPresent
    }

    @Test("The menu bar recognises the launched main window and reopens it after it is closed")
    func mainWindowIsRecognisedAndReopened() async throws {
        let identifiers = { NSApp.windows.map { $0.identifier?.rawValue ?? "nil" } }
        #expect(await waitForMainWindow(true), Comment(rawValue: "window identifiers: \(identifiers())"))
        let launched = try #require(NSApp.windows.first(where: MyMacCleanerApp.isMainWindow))

        launched.performClose(nil)
        #expect(await waitForMainWindow(false))

        MyMacCleanerApp.reopenMainWindow()
        #expect(await waitForMainWindow(true), Comment(rawValue: "window identifiers: \(identifiers())"))
    }

    @Test("Only the main WindowGroup window counts as the window to reopen")
    func mainWindowMatchesItsWindowGroupID() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("Fixture-1-AppWindow-1")
        #expect(MyMacCleanerApp.isMainWindow(window) == false, "a closed window must be reopened, not reused")

        window.orderBack(nil)
        defer { window.close() }
        #expect(MyMacCleanerApp.isMainWindow(window))

        window.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        #expect(MyMacCleanerApp.isMainWindow(window) == false)
    }
}
