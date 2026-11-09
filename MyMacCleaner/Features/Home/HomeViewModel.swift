import Combine
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isScanning = false
    @Published var scanResults: [ScanResult] = []
    @Published var showScanResults = false
    @Published var scanError: String?
    /// Folders the last completed Smart Scan could not fully read; nil until a scan completes.
    @Published private(set) var lastScanCoverage: LegacyScanCoverage?
    /// True when leaving the page stopped the last scan; cleared by the next scan or result.
    @Published private(set) var scanStoppedByLeaving = false

    // Permission state
    @Published var showPermissionPrompt = false
    @Published var hasFullDiskAccess = false
    /// Set when the user picks Limited Scan, so the prompt stays away for the rest of the session.
    private var choseLimitedScan = false

    // System stats
    @Published var storageUsed: String = "0 GB"
    @Published var storageTotal: String = "0 GB"
    @Published var storageFree: String = "0 GB"
    @Published var memoryUsed: String = "0 GB"
    /// Caches, logs and temporary files from the last Smart Scan; personal folders never count.
    /// No figure is shown before a scan runs.
    @Published var cacheAndLogSize: String = L("home.stats.scanToCheck")
    @Published var appCount: Int = 0

    /// Disk and memory health from the last completed Smart Scan; shown on Home and in the sidebar.
    @Published private(set) var healthLevel: SystemHealthLevel = .notScanned

    let toasts = ToastPresenter()

    // MARK: - Private Properties

    private let scanStore: SharedScanStore
    private var scanStoreObserver: AnyCancellable?
    private let permissionsService = PermissionsService.shared
    private let safetyNoticePresenter = SafetyNoticePresenter()
    /// Readable so tests can await a scan instead of sleeping.
    private(set) var scanTask: Task<Void, Never>?
    /// Bumped by every start and cancel, so a late result from an older scan is ignored.
    private var scanGeneration: UInt64 = 0

    // MARK: - Initialization

    init(scanStore: SharedScanStore = SharedScanStore(scan: { try await CleanerCoreLiveScan().sharedScan() })) {
        self.scanStore = scanStore
        scanStoreObserver = scanStore.$latest
            .compactMap { $0 }
            .sink { [weak self] scan in
                // The store publishes from the main actor.
                MainActor.assumeIsolated { self?.adopt(scan) }
            }
        Task {
            await loadSystemStats()
            await checkPermissions()
        }
    }

    // MARK: - Public Methods

    func startSmartScan() {
        guard !isScanning else { return }

        // Check if we should prompt for permissions
        if !hasFullDiskAccess && !choseLimitedScan && !showPermissionPrompt {
            showPermissionPrompt = true
            return
        }

        performScan()
    }

    func continueWithLimitedScan() {
        choseLimitedScan = true
        showPermissionPrompt = false
        performScan()
    }

    /// Access granted while the prompt is open: close it and run the scan the user asked for.
    /// Internal for tests.
    func updateFullDiskAccess(_ granted: Bool) {
        hasFullDiskAccess = granted
        guard granted, showPermissionPrompt else { return }
        showPermissionPrompt = false
        performScan()
    }

    func dismissPermissionPrompt() {
        showPermissionPrompt = false
    }

    /// Stops an in-flight Smart Scan, discarding its partial results and keeping the last completed ones.
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

    func refreshPermissions() {
        Task {
            await checkPermissions()
        }
    }

    func explainTrashSafety() {
        publishSafetyNotice(safetyNoticePresenter.homeTrashReviewNotice())
    }

    func showToastMessage(_ message: String, type: ToastType) {
        toasts.show(message, type: type)
    }

    private func publishSafetyNotice(_ notice: SafetyNoticeState) {
        toasts.show(notice)
    }

    // MARK: - Private Methods

    private func performScan() {
        guard !isScanning else { return }
        // The last results stay until this scan finishes, so leaving the page or Cancel keeps them.
        isScanning = true
        scanError = nil
        scanStoppedByLeaving = false
        scanGeneration &+= 1
        let generation = scanGeneration

        scanTask = Task { [scanStore] in
            do {
                let scan = try await scanStore.refresh()
                // A cancelled or superseded scan returns partial evidence; never present it.
                guard generation == scanGeneration, !Task.isCancelled else { return }

                show(scan.legacyReport)
                // Re-sample storage, memory and health at the moment the scan completes.
                await loadSystemStats()
            } catch {
                guard generation == scanGeneration, !Task.isCancelled else { return }
                scanError = LFormat("home.scanFailed %@", error.localizedDescription)
            }

            guard generation == scanGeneration else { return }
            finishScan()
        }
    }

    private func finishScan() {
        scanTask = nil
        isScanning = false
    }

    /// Shows a scan another screen ran; a Smart Scan in progress shows its own result instead.
    private func adopt(_ scan: SharedScan) {
        guard !isScanning else { return }
        show(scan.legacyReport)
        Task { await loadSystemStats() }
    }

    private func show(_ report: LegacyScanReport) {
        scanStoppedByLeaving = false
        scanResults = report.results
        showScanResults = !report.results.isEmpty
        lastScanCoverage = report.coverage
        cacheAndLogSize = formatBytes(Self.cacheAndLogBytes(in: report.results))
    }

    /// App data only: Downloads, Desktop and Documents are the user's own files.
    static func cacheAndLogBytes(in results: [ScanResult]) -> Int64 {
        results.filter { !$0.category.isPersonalFolder }.reduce(0) { $0 + $1.totalSize }
    }

    private func checkPermissions() async {
        permissionsService.checkFullDiskAccess()
        updateFullDiskAccess(permissionsService.hasFullDiskAccess)
    }

    private func loadSystemStats() async {
        // Get disk space
        let diskStats = getDiskSpace()
        storageUsed = formatBytes(diskStats.used)
        storageTotal = formatBytes(diskStats.total)
        storageFree = formatBytes(diskStats.free)

        // Get memory stats
        let memoryStats = getMemoryStats()
        memoryUsed = formatBytes(memoryStats.used)

        // Count installed apps the way the Applications page does
        appCount = InstalledApplications.bundleURLs().count

        // Determine system health
        updateSystemHealth(diskStats: diskStats, memoryStats: memoryStats)
    }

    private func getDiskSpace() -> (total: Int64, used: Int64, free: Int64) {
        let disk = SystemStatsProvider.diskUsage()
        return (disk.total, disk.used, disk.total - disk.used)
    }

    private func getMemoryStats() -> (total: UInt64, used: UInt64) {
        let memory = SystemStatsProvider.memoryUsage() ?? (0, ProcessInfo.processInfo.physicalMemory)
        return (memory.total, memory.used)
    }

    /// Health is only claimed once a Smart Scan has completed; until then it stays "Not scanned yet".
    private func updateSystemHealth(
        diskStats: (total: Int64, used: Int64, free: Int64),
        memoryStats: (total: UInt64, used: UInt64)
    ) {
        guard lastScanCoverage != nil else { return }
        let diskUsage = diskStats.total > 0 ? Double(diskStats.used) / Double(diskStats.total) : 0
        let memoryUsage = memoryStats.total > 0 ? Double(memoryStats.used) / Double(memoryStats.total) : 0
        healthLevel = .assess(diskUsage: diskUsage, memoryUsage: memoryUsage)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        formatBytes(Int64(bytes))
    }
}
