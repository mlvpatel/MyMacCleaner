import SwiftUI

@MainActor
class OrphanedFilesViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var scanProgress: Double = 0
    @Published var currentScanCategory: String = ""
    /// True when leaving the page stopped the last scan; cleared by the next scan or result.
    @Published private(set) var scanStoppedByLeaving = false

    @Published var orphanedFiles: [OrphanedFile] = [] {
        didSet { indexFiles() }
    }

    @Published var expandedCategory: OrphanCategory?
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published var sortOrder: SortOrder = .sizeDescending {
        didSet { refreshGroups() }
    }

    /// Derived from the inputs above when they change, not several times per render.
    @Published private(set) var filesByCategory: [OrphanCategory: [OrphanedFile]] = [:]
    @Published private(set) var categoriesWithFiles: [OrphanCategory] = []

    // MARK: - Enums

    enum SortOrder: String, CaseIterable {
        case sizeDescending = "Size (Largest)"
        case sizeAscending = "Size (Smallest)"
        case dateDescending = "Date (Newest)"
        case dateAscending = "Date (Oldest)"
        case nameAscending = "Name (A-Z)"

        var localizedName: String {
            switch self {
            case .sizeDescending: return L("orphans.sort.sizeLargest")
            case .sizeAscending: return L("orphans.sort.sizeSmallest")
            case .dateDescending: return L("orphans.sort.dateNewest")
            case .dateAscending: return L("orphans.sort.dateOldest")
            case .nameAscending: return L("orphans.sort.name")
            }
        }
    }

    // MARK: - Derived Groups

    /// Lower-cased name, app name and bundle ID of each file, built once per scan result.
    private var searchKeys: [UUID: [String]] = [:]
    /// The query the groups are filtered with; it trails `searchText` by `Theme.Timing.searchDebounce`.
    private var appliedQuery = ""
    /// Readable so tests can await the debounced search instead of sleeping.
    private(set) var searchTask: Task<Void, Never>?

    private func indexFiles() {
        searchKeys = Dictionary(uniqueKeysWithValues: orphanedFiles.map { file in
            (file.id, [file.name, file.suspectedAppName, file.bundleIdPattern].compactMap { $0?.lowercased() })
        })
        refreshGroups()
    }

    /// Waits for typing to pause; clearing the field applies at once.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.lowercased()
        guard !query.isEmpty else {
            searchTask = nil
            appliedQuery = query
            refreshGroups()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Theme.Timing.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            self.appliedQuery = query
            self.refreshGroups()
        }
    }

    private func refreshGroups() {
        var result = orphanedFiles

        // Apply search filter
        if !appliedQuery.isEmpty {
            result = result.filter { file in
                searchKeys[file.id]?.contains { $0.contains(appliedQuery) } ?? false
            }
        }

        // Apply sort
        switch sortOrder {
        case .sizeDescending:
            result.sort { $0.size > $1.size }
        case .sizeAscending:
            result.sort { $0.size < $1.size }
        case .dateDescending:
            result.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .dateAscending:
            result.sort { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        case .nameAscending:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let grouped = Dictionary(grouping: result, by: \.category)
        filesByCategory = grouped
        categoriesWithFiles = OrphanCategory.allCases.filter { grouped[$0]?.isEmpty == false }
    }

    // MARK: - Computed Properties

    var totalSize: Int64 {
        orphanedFiles.reduce(0) { $0 + $1.size }
    }

    var totalCount: Int {
        orphanedFiles.count
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// True when there are results but the search hides all of them.
    var hasNoSearchMatches: Bool {
        !orphanedFiles.isEmpty && categoriesWithFiles.isEmpty
    }

    // MARK: - Scanner

    typealias Scan = @Sendable (
        _ progress: @escaping @Sendable @MainActor (Double, String) -> Void
    ) async -> [OrphanedFile]

    private let scan: Scan
    /// Readable so tests can await a cancelled scan instead of sleeping.
    private(set) var scanTask: Task<Void, Never>?
    /// Bumped by every start and cancel, so updates from an older scan are ignored.
    private var scanGeneration: UInt64 = 0

    init(scan: @escaping Scan = { await OrphanedFilesScanner.shared.scan(progress: $0) }) {
        self.scan = scan
    }

    // MARK: - Actions

    func startScan() {
        guard !isScanning else { return }

        // The last results stay until this scan finishes, so leaving the page or Cancel keeps them.
        isScanning = true
        scanProgress = 0
        scanStoppedByLeaving = false
        scanGeneration &+= 1
        let generation = scanGeneration

        scanTask = Task { [scan] in
            let results = await scan { progress, category in
                Task { @MainActor in
                    guard generation == self.scanGeneration else { return }
                    self.scanProgress = progress
                    self.currentScanCategory = category
                }
            }
            guard generation == scanGeneration, !Task.isCancelled else { return }

            orphanedFiles = results
            hasScanned = true
            finishScan()
        }
    }

    /// Leaving the page stops a running scan and remembers that it did, so the page can say so.
    func leavePage() {
        guard isScanning else { return }
        cancelScan()
        scanStoppedByLeaving = true
    }

    /// Stops an in-flight scan; its partial results are dropped and the last completed ones stay.
    func cancelScan() {
        guard isScanning else { return }
        scanGeneration &+= 1
        scanTask?.cancel()
        finishScan()
        scanProgress = 0
    }

    private func finishScan() {
        scanTask = nil
        isScanning = false
    }

    func toggleCategoryExpansion(_ category: OrphanCategory) {
        withAnimation(Theme.Animation.spring) {
            if expandedCategory == category {
                expandedCategory = nil
            } else {
                expandedCategory = category
            }
        }
    }

    func clearSearch() {
        searchText = ""
    }

    func revealInFinder(_ file: OrphanedFile) {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
    }
}
