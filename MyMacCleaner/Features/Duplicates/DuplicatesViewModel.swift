import SwiftUI

@MainActor
class DuplicatesViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var scanProgress: Double = 0
    @Published var currentScanStatus: String = ""

    @Published var duplicateGroups: [DuplicateGroup] = [] {
        didSet { indexGroups() }
    }
    /// True when the last scan stopped at `DuplicateScanLimits.maxEntries`.
    @Published private(set) var isTruncated = false
    /// True when leaving the page stopped the last scan; cleared by the next scan or result.
    @Published private(set) var scanStoppedByLeaving = false
    /// Cloud-synced files the last scan left out because their contents are not on this Mac.
    @Published private(set) var skippedCloudOnlyCount = 0

    let toasts = ToastPresenter()

    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published var filterType: FileType? {
        didSet { refreshFilteredGroups() }
    }
    @Published var sortOrder: SortOrder = .wastedSizeDescending {
        didSet { refreshFilteredGroups() }
    }

    /// Derived from the inputs above when they change, not on every render.
    @Published private(set) var filteredGroups: [DuplicateGroup] = []
    @Published private(set) var fileTypeStats: [(FileType, Int, Int64)] = []

    /// Results belong to the folder that was scanned, so choosing another one clears them.
    @Published var scanPath: URL = FileManager.default.homeDirectoryForCurrentUser {
        didSet { if scanPath != oldValue { clearResults() } }
    }

    // MARK: - Enums

    enum SortOrder: String, CaseIterable {
        case wastedSizeDescending = "Wasted Space (Most)"
        case wastedSizeAscending = "Wasted Space (Least)"
        case fileSizeDescending = "File Size (Largest)"
        case fileSizeAscending = "File Size (Smallest)"
        case duplicateCountDescending = "Copies (Most)"

        var localizedName: String {
            switch self {
            case .wastedSizeDescending: return L("duplicates.sort.wastedMost")
            case .wastedSizeAscending: return L("duplicates.sort.wastedLeast")
            case .fileSizeDescending: return L("duplicates.sort.sizeLargest")
            case .fileSizeAscending: return L("duplicates.sort.sizeSmallest")
            case .duplicateCountDescending: return L("duplicates.sort.copiesMost")
            }
        }
    }

    // MARK: - Derived List

    /// Lower-cased paths of each group's copies, built once per scan result. A path ends with
    /// the file name, so it also covers a name match.
    private var searchKeys: [UUID: [String]] = [:]
    /// The query the list is filtered with; it trails `searchText` by `Theme.Timing.searchDebounce`.
    private var appliedQuery = ""
    /// Readable so tests can await the debounced search instead of sleeping.
    private(set) var searchTask: Task<Void, Never>?

    private func indexGroups() {
        searchKeys = Dictionary(uniqueKeysWithValues: duplicateGroups.map { group in
            (group.id, group.files.map { $0.url.path.lowercased() })
        })
        fileTypeStats = Self.typeStats(of: duplicateGroups)
        refreshFilteredGroups()
    }

    /// Waits for typing to pause; clearing the field applies at once.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.lowercased()
        guard !query.isEmpty else {
            searchTask = nil
            appliedQuery = query
            refreshFilteredGroups()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Theme.Timing.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            self.appliedQuery = query
            self.refreshFilteredGroups()
        }
    }

    private func refreshFilteredGroups() {
        var result = duplicateGroups

        // Apply search filter
        if !appliedQuery.isEmpty {
            result = result.filter { group in
                searchKeys[group.id]?.contains { $0.contains(appliedQuery) } ?? false
            }
        }

        // Apply file type filter
        if let typeFilter = filterType {
            result = result.filter { $0.fileType == typeFilter }
        }

        // Apply sort
        switch sortOrder {
        case .wastedSizeDescending:
            result.sort { $0.wastedSize > $1.wastedSize }
        case .wastedSizeAscending:
            result.sort { $0.wastedSize < $1.wastedSize }
        case .fileSizeDescending:
            result.sort { $0.fileSize > $1.fileSize }
        case .fileSizeAscending:
            result.sort { $0.fileSize < $1.fileSize }
        case .duplicateCountDescending:
            result.sort { $0.files.count > $1.files.count }
        }

        filteredGroups = result
    }

    // MARK: - Computed Properties

    var totalWastedSize: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.wastedSize }
    }

    var totalGroupCount: Int {
        duplicateGroups.count
    }

    var totalDuplicateFileCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.files.count - 1 } // Count all but one in each group
    }

    var formattedTotalWastedSize: String {
        ByteCountFormatter.string(fromByteCount: totalWastedSize, countStyle: .file)
    }

    /// True when there are results but the search or type filter hides all of them.
    var hasNoSearchMatches: Bool {
        !duplicateGroups.isEmpty && filteredGroups.isEmpty
    }

    private static func typeStats(of groups: [DuplicateGroup]) -> [(FileType, Int, Int64)] {
        var stats: [FileType: (count: Int, size: Int64)] = [:]

        for group in groups {
            let type = group.fileType
            let existing = stats[type] ?? (0, 0)
            stats[type] = (existing.count + 1, existing.size + group.wastedSize)
        }

        return stats.map { ($0.key, $0.value.count, $0.value.size) }
            .sorted { $0.2 > $1.2 }
    }

    // MARK: - Scanner

    typealias Scan = @Sendable (
        _ path: URL,
        _ progress: @escaping @Sendable @MainActor (Double, String) -> Void
    ) async -> DuplicateScanResult

    private let scan: Scan
    /// Readable so tests can await a cancelled scan instead of sleeping.
    private(set) var scanTask: Task<Void, Never>?
    /// Bumped by every start and cancel, so updates from an older scan are ignored.
    private var scanGeneration: UInt64 = 0

    init(scan: @escaping Scan = { await DuplicateScanner.shared.scan(at: $0, minSize: 1024, progress: $1) }) {
        self.scan = scan
    }

    // MARK: - Actions

    func chooseScanLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("duplicates.chooseFolderMessage")
        panel.prompt = L("duplicates.chooseFolderButton")

        if panel.runModal() == .OK, let url = panel.url {
            scanPath = url
        }
    }

    func startScan() {
        guard !isScanning else { return }

        // The last results stay until this scan finishes, so leaving the page or Cancel keeps them.
        isScanning = true
        scanProgress = 0
        scanStoppedByLeaving = false
        scanGeneration &+= 1
        let generation = scanGeneration

        scanTask = Task { [scan, scanPath] in
            let result = await scan(scanPath) { progress, status in
                Task { @MainActor in
                    guard generation == self.scanGeneration else { return }
                    self.scanProgress = progress
                    self.currentScanStatus = status
                }
            }
            // A cancelled scan must not overwrite the cancelled state or a newer scan.
            guard generation == scanGeneration, !Task.isCancelled else { return }

            duplicateGroups = result.groups
            isTruncated = result.isTruncated
            skippedCloudOnlyCount = result.skippedCloudOnlyCount
            hasScanned = true
            scanTask = nil
            isScanning = false

            // Show toast if no duplicates found
            if result.groups.isEmpty && scanProgress >= 1.0 {
                showToastMessage(L("duplicates.noDuplicatesFound"), type: .info)
            }
        }
    }

    private func clearResults() {
        hasScanned = false
        duplicateGroups = []
        isTruncated = false
        skippedCloudOnlyCount = 0
        scanStoppedByLeaving = false
    }

    /// Leaving the page stops a running scan and remembers that it did, so the page can say so.
    func leavePage() {
        guard isScanning else { return }
        cancelScan(announce: false)
        scanStoppedByLeaving = true
    }

    /// Stops an in-flight scan. `announce` is false when leaving the screen.
    func cancelScan(announce: Bool = true) {
        guard isScanning else { return }
        scanGeneration &+= 1
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanProgress = 0
        currentScanStatus = ""

        if announce {
            showToastMessage(L("duplicates.scan.cancelled"), type: .info)
        }
    }

    func revealInFinder(_ file: DuplicateFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
    }

    func clearFilter() {
        filterType = nil
        searchText = ""
    }

    private func showToastMessage(_ message: String, type: ToastType) {
        toasts.show(message, type: type)
    }
}
