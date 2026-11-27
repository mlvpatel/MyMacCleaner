import Combine
import SwiftUI

@MainActor
class DiskCleanerViewModel: ObservableObject {
    // MARK: - Published Properties

    // Scanning state
    @Published var isScanning = false

    // Results
    @Published var scanResults: [ScanResult] = []
    @Published var hasScanned = false
    /// Folders the last completed scan could not fully read; nil until a scan completes.
    @Published private(set) var lastScanCoverage: LegacyScanCoverage?
    /// True when leaving the page stopped the last scan; cleared by the next scan or result.
    @Published private(set) var scanStoppedByLeaving = false

    // Presentation
    /// Kept here, not in the view, so the chosen tab survives a section switch.
    @Published var selectedTab: DiskCleanerView.DiskCleanerTab = .cleaner
    @Published var expandedCategory: ScanCategory?
    /// Only the key is stored, so the detail sheet always renders the live result.
    @Published var detailCategory: ScanCategory?

    let toasts = ToastPresenter()

    // Trash inventory (read-only)
    @Published private(set) var trashInventory: TrashInventory = .unknown

    // Errors
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    var totalReviewableSize: Int64 {
        scanResults.reduce(0) { $0 + $1.totalSize }
    }

    var totalItemCount: Int {
        scanResults.reduce(0) { $0 + $1.itemCount }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalReviewableSize, countStyle: .file)
    }

    var detailResult: ScanResult? {
        detailCategory.flatMap(result(for:))
    }

    var hasFullDiskAccess: Bool {
        permissionsService.hasFullDiskAccess
    }

    // MARK: - Private Properties

    private let scanStore: SharedScanStore
    private var scanStoreObserver: AnyCancellable?
    private let permissionsService = PermissionsService.shared
    private let safetyNoticePresenter = SafetyNoticePresenter()
    /// Readable so tests can await a scan instead of sleeping.
    private(set) var scanTask: Task<Void, Never>?
    /// Bumped by every start and cancel, so a late result from an older scan is ignored.
    private var scanGeneration: UInt64 = 0
    private var trashTask: Task<Void, Never>?

    // MARK: - Initialization

    init(scanStore: SharedScanStore = SharedScanStore(scan: { try await CleanerCoreLiveScan().sharedScan() })) {
        self.scanStore = scanStore
        scanStoreObserver = scanStore.$latest
            .compactMap { $0 }
            .sink { [weak self] scan in
                // The store publishes from the main actor.
                MainActor.assumeIsolated {
                    // A scan in progress shows its own result instead.
                    guard let self, !self.isScanning else { return }
                    self.show(scan.legacyReport)
                }
            }
    }

    // MARK: - Public Methods

    func startScan() {
        guard !isScanning else { return }

        // The last results stay until this scan finishes, so a stopped or failed rescan never
        // reads as "Nothing Found".
        isScanning = true
        errorMessage = nil
        scanStoppedByLeaving = false
        scanGeneration &+= 1
        let generation = scanGeneration

        scanTask = Task { [scanStore] in
            do {
                let scan = try await scanStore.refresh()
                // A cancelled or superseded scan returns partial evidence; never present it.
                guard generation == scanGeneration, !Task.isCancelled else { return }

                show(scan.legacyReport)
            } catch {
                guard generation == scanGeneration, !Task.isCancelled else { return }
                errorMessage = LFormat("diskCleaner.toast.scanFailed %@", error.localizedDescription)
            }

            guard generation == scanGeneration else { return }
            finishScan()
        }
    }

    /// Stops an in-flight scan, discarding its partial results and keeping the last completed ones.
    func cancelScan() {
        guard isScanning else { return }
        scanGeneration &+= 1
        scanTask?.cancel()
        finishScan()
    }

    /// Leaving the page stops a running scan and remembers that it did, so the page can say so.
    func leavePage() {
        guard isScanning else { return }
        cancelScan()
        scanStoppedByLeaving = true
    }

    private func finishScan() {
        scanTask = nil
        isScanning = false
    }

    private func show(_ report: LegacyScanReport) {
        scanStoppedByLeaving = false
        scanResults = report.results
        lastScanCoverage = report.coverage
        hasScanned = true
    }

    func toggleCategoryExpansion(_ category: ScanCategory) {
        withAnimation(Theme.Animation.spring) {
            if expandedCategory == category {
                expandedCategory = nil
            } else {
                expandedCategory = category
            }
        }
    }

    func showDetails(for category: ScanCategory) {
        detailCategory = category
    }

    func showToastMessage(_ message: String, type: ToastType) {
        toasts.show(message, type: type)
    }

    // MARK: - Trash Inventory

    /// Re-measures the Trash off the main actor; a newer request supersedes an older one.
    func refreshTrashSize() {
        trashTask?.cancel()
        trashTask = Task {
            let inventory = await TrashInventoryReader.measure()
            guard !Task.isCancelled else { return }
            trashInventory = inventory
            trashTask = nil
        }
    }

    func explainTrashSafety() {
        publishSafetyNotice(safetyNoticePresenter.diskTrashReviewNotice())
    }

    // MARK: - Helpers

    func result(for category: ScanCategory) -> ScanResult? {
        scanResults.first { $0.category == category }
    }

    private func publishSafetyNotice(_ notice: SafetyNoticeState) {
        toasts.show(notice)
    }
}
