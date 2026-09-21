import ServiceManagement
import SwiftUI

// MARK: - Startup Items View Model

@MainActor
class StartupItemsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var items: [StartupItem] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var selectedType: StartupItemType? = nil
    @Published var showSystemItems = false
    @Published var sortOrder: SortOrder = .name

    // Toast
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastType: ToastType = .success

    enum SortOrder: String, CaseIterable {
        case name
        case type
        case status

        var icon: String {
            switch self {
            case .name: return "textformat"
            case .type: return "folder"
            case .status: return "circle.lefthalf.filled"
            }
        }

        var localizedName: String {
            L(key: "startupItems.sortOrder.\(rawValue)")
        }
    }

    // MARK: - Computed Properties

    var filteredItems: [StartupItem] {
        var result = items

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.label.localizedCaseInsensitiveContains(searchText) ||
                ($0.developer?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Filter by type
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }

        // Filter system items
        if !showSystemItems {
            result = result.filter { !$0.isSystemItem }
        }

        // Sort
        switch sortOrder {
        case .name:
            result.sort { $0.displayName.lowercased() < $1.displayName.lowercased() }
        case .type:
            result.sort { ($0.type.rawValue, $0.displayName.lowercased()) < ($1.type.rawValue, $1.displayName.lowercased()) }
        case .status:
            result.sort { ($0.isEnabled ? 0 : 1, $0.displayName.lowercased()) < ($1.isEnabled ? 0 : 1, $1.displayName.lowercased()) }
        }

        return result
    }

    var enabledCount: Int {
        items.filter { $0.isEnabled && !$0.isSystemItem }.count
    }

    var disabledCount: Int {
        items.filter { !$0.isEnabled && !$0.isSystemItem }.count
    }

    var runningCount: Int {
        items.filter { $0.isRunning }.count
    }

    var itemsByType: [StartupItemType: [StartupItem]] {
        Dictionary(grouping: filteredItems, by: { $0.type })
    }

    // MARK: - Private Properties

    private let service = StartupItemsService.shared
    private var scanTask: Task<Void, Never>?
    private let openLoginItemsSettingsAction: () -> Void

    // MARK: - Initialization

    init(openLoginItemsSettingsAction: @escaping () -> Void = {
        SMAppService.openSystemSettingsLoginItems()
    }) {
        self.openLoginItemsSettingsAction = openLoginItemsSettingsAction
        // Don't auto-scan, wait for user to trigger
    }

    // MARK: - Public Methods

    func scanItems() {
        guard !isLoading else { return }

        isLoading = true

        scanTask = Task { [service] in
            let scannedItems = await service.scanAllItems()
            // The read-only tool calls finish on their own; a cancelled scan just drops its output.
            guard !Task.isCancelled else { return }
            items = scannedItems
            scanTask = nil
            isLoading = false

            if scannedItems.isEmpty {
                showToastMessage(L("startupItems.toast.noItemsFound"), type: .info)
            }
        }
    }

    /// Abandons an in-flight scan, keeping the last known items.
    func cancelScan() {
        guard isLoading else { return }
        scanTask?.cancel()
        scanTask = nil
        isLoading = false
    }

    func refreshItems() {
        scanItems()
    }

    func revealInFinder(_ item: StartupItem) {
        service.revealInFinder(item)
    }

    /// Opens the fixed macOS Login Items settings pane without accepting item or process input.
    func openLoginItemsSettings() {
        openLoginItemsSettingsAction()
    }

    func showToastMessage(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        showToast = true

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showToast = false
        }
    }

    func dismissToast() {
        showToast = false
    }
}
