import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Disk Cleaner Selection Tests

@Suite("Disk Cleaner Selection Tests")
@MainActor
struct DiskCleanerSelectionTests {
    private func item(_ name: String, _ size: Int64, _ category: ScanCategory, selected: Bool = false) -> CleanableItem {
        CleanableItem(
            name: name,
            path: URL(fileURLWithPath: "/tmp/\(name)"),
            size: size,
            modificationDate: nil,
            category: category,
            isSelected: selected
        )
    }

    private func makeViewModel() -> DiskCleanerViewModel {
        let viewModel = DiskCleanerViewModel()
        viewModel.scanResults = [
            ScanResult(category: .userCache, items: [item("a", 100, .userCache), item("b", 50, .userCache)], isSelected: false),
            ScanResult(category: .applicationLogs, items: [item("c", 10, .applicationLogs)], isSelected: false),
        ]
        return viewModel
    }

    @Test("Totals start with nothing selected")
    func totalsStartUnselected() {
        let viewModel = makeViewModel()

        #expect(viewModel.totalReviewableSize == 160)
        #expect(viewModel.totalItemCount == 3)
        #expect(viewModel.selectedItemCount == 0)
        #expect(viewModel.selectedSize == 0)
    }

    @Test("Toggling one item changes only that item")
    func togglesSingleItem() throws {
        let viewModel = makeViewModel()
        let target = try #require(viewModel.scanResults.first?.items.first)

        viewModel.toggleItemSelection(target, in: .userCache)

        #expect(viewModel.selectedItemCount == 1)
        #expect(viewModel.selectedSize == 100)
        viewModel.toggleItemSelection(target, in: .userCache)
        #expect(viewModel.selectedItemCount == 0)
    }

    @Test("Toggling a category selects all its items, then clears them")
    func togglesCategory() {
        let viewModel = makeViewModel()

        viewModel.toggleCategorySelection(.userCache)
        #expect(viewModel.selectedItemCount == 2)
        #expect(viewModel.selectedSize == 150)

        viewModel.toggleCategorySelection(.userCache)
        #expect(viewModel.selectedItemCount == 0)
    }

    @Test("Select all and deselect all cover every category")
    func selectsAndDeselectsAll() {
        let viewModel = makeViewModel()

        viewModel.selectAll()
        #expect(viewModel.selectedItemCount == 3)
        viewModel.deselectAll()
        #expect(viewModel.selectedItemCount == 0)
    }

    @Test("Unknown categories and items are ignored")
    func ignoresUnknownTargets() {
        let viewModel = makeViewModel()

        viewModel.toggleCategorySelection(.dockerData)
        viewModel.toggleItemSelection(item("ghost", 1, .dockerData), in: .dockerData)

        #expect(viewModel.selectedItemCount == 0)
        #expect(viewModel.result(for: .dockerData) == nil)
        #expect(viewModel.result(for: .applicationLogs)?.itemCount == 1)
    }

    @Test("Reviewing with nothing selected explains instead of acting")
    func reviewWithoutSelectionShowsNotice() {
        let viewModel = makeViewModel()

        viewModel.explainSelectedStorageReview()

        #expect(viewModel.showToast)
        #expect(viewModel.toastType == .info)
        #expect(viewModel.toastMessage == L("safety.notice.noSelection"))
    }

    @Test("Category expansion toggles open and closed")
    func togglesExpansion() {
        let viewModel = makeViewModel()

        viewModel.toggleCategoryExpansion(.userCache)
        #expect(viewModel.expandedCategory == .userCache)
        viewModel.toggleCategoryExpansion(.userCache)
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

    @Test("Reviewing with no scan results explains instead of acting")
    func reviewWithoutSelectionShowsNotice() {
        let viewModel = HomeViewModel()

        viewModel.explainSelectedStorageReview()

        #expect(viewModel.showToast)
        #expect(viewModel.toastMessage == L("safety.notice.noSelection"))
        viewModel.dismissToast()
        #expect(viewModel.showToast == false)
    }

    @Test("Before any scan the junk tile asks the user to scan")
    func junkTileStartsHonest() {
        #expect(HomeViewModel().junkSize == L("home.stats.scanToCheck"))
    }

    @Test("Large files navigation targets the Space Lens section")
    func largeFilesNavigatesToSpaceLens() {
        let viewModel = HomeViewModel()
        var destination: String?
        viewModel.onNavigateToSection = { destination = $0 }

        viewModel.viewLargeFiles()
        #expect(destination == NavigationSection.spaceLens.rawValue)

        viewModel.openMemoryGuide()
        #expect(destination == NavigationSection.performance.rawValue)
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
}
