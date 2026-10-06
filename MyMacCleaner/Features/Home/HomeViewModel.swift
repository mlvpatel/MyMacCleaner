import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var currentScanCategory: ScanCategory?
    @Published var scanResults: [ScanResult] = []
    @Published var showScanResults = false
    @Published var scanError: String?

    // Permission state
    @Published var showPermissionPrompt = false
    @Published var hasFullDiskAccess = false

    // System stats
    @Published var storageUsed: String = "0 GB"
    @Published var storageTotal: String = "0 GB"
    @Published var storageFree: String = "0 GB"
    @Published var memoryUsed: String = "0 GB"
    /// Reviewable storage from the last Smart Scan; no figure is shown before a scan runs.
    @Published var junkSize: String = L("home.stats.scanToCheck")
    @Published var appCount: Int = 0

    // System health
    @Published var systemHealthStatus: String = L("home.health.healthy")
    @Published var systemHealthColor: Color = .green

    // Toast notification
    @Published var showToast = false
    @Published var toastMessage: String = ""
    @Published var toastType: ToastType = .success
    @Published private(set) var latestSafetyNotice: SafetyNoticeState?

    // Navigation callback - set by parent view to handle navigation requests
    var onNavigateToSection: ((String) -> Void)?

    // MARK: - Private Properties

    private let liveScan: CleanerCoreLiveScan
    private let permissionsService = PermissionsService.shared
    private let safetyNoticePresenter = SafetyNoticePresenter()
    private var toastPresentationID = UUID()
    private var scanTask: Task<Void, Never>?

    // MARK: - Initialization

    init(scan: CleanerCoreLiveScan = CleanerCoreLiveScan()) {
        liveScan = scan
        Task {
            await loadSystemStats()
            await checkPermissions()
        }
    }

    // MARK: - Public Methods

    func startSmartScan() {
        guard !isScanning else { return }

        // Check if we should prompt for permissions
        if !hasFullDiskAccess && !showPermissionPrompt {
            showPermissionPrompt = true
            return
        }

        performScan()
    }

    func continueWithLimitedScan() {
        showPermissionPrompt = false
        performScan()
    }

    func dismissPermissionPrompt() {
        showPermissionPrompt = false
    }

    /// Stops an in-flight Smart Scan and discards its partial results.
    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        finishScan()
    }

    func refreshPermissions() {
        Task {
            await checkPermissions()
        }
    }

    func explainTrashSafety() {
        publishSafetyNotice(safetyNoticePresenter.homeTrashReviewNotice())
    }

    /// Opens the read-only memory guide; this action has no memory-control capability.
    func openMemoryGuide() {
        onNavigateToSection?("performance")
    }

    func viewLargeFiles() {
        onNavigateToSection?("spaceLens")
    }

    func explainSelectedStorageReview() {
        guard scanResults.contains(where: { $0.isSelected }) else {
            showToastMessage(L("safety.notice.noSelection"), type: .info)
            return
        }

        publishSafetyNotice(
            safetyNoticePresenter.homeSelectedStorageReviewNotice()
        )
    }

    func showToastMessage(_ message: String, type: ToastType) {
        latestSafetyNotice = nil
        presentToast(message, type: type)
    }

    func dismissToast() {
        showToast = false
        latestSafetyNotice = nil
    }

    private func publishSafetyNotice(_ notice: SafetyNoticeState) {
        latestSafetyNotice = notice
        presentToast(notice.message, type: .info)
    }

    private func presentToast(_ message: String, type: ToastType) {
        let presentationID = UUID()
        toastPresentationID = presentationID
        toastMessage = message
        toastType = type
        showToast = true

        // Auto-hide after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard toastPresentationID == presentationID else { return }
            dismissToast()
        }
    }

    // MARK: - Private Methods

    private func performScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        scanResults = []
        scanError = nil

        scanTask = Task { [liveScan] in
            do {
                let results = try await liveScan.scanAllCategories { progress, category in
                    guard self.isScanning else { return }
                    self.scanProgress = progress
                    self.currentScanCategory = category
                }
                // A cancelled scan returns partial evidence; never present it as a result.
                guard !Task.isCancelled else { return }

                scanResults = results
                showScanResults = !results.isEmpty

                // Update junk size with actual results
                let totalJunk = results.reduce(0) { $0 + $1.totalSize }
                junkSize = formatBytes(totalJunk)
            } catch {
                guard !Task.isCancelled else { return }
                scanError = LFormat("home.scanFailed %@", error.localizedDescription)
            }

            finishScan()
        }
    }

    private func finishScan() {
        scanTask = nil
        isScanning = false
        currentScanCategory = nil
    }

    private func checkPermissions() async {
        permissionsService.checkFullDiskAccess()
        hasFullDiskAccess = permissionsService.hasFullDiskAccess
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

        // Count installed apps
        appCount = countInstalledApps()

        // Determine system health
        updateSystemHealth(diskStats: diskStats, memoryStats: memoryStats)
    }

    private func getDiskSpace() -> (total: Int64, used: Int64, free: Int64) {
        do {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            let values = try homeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])

            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let used = total - available

            return (total, used, available)
        } catch {
            return (0, 0, 0)
        }
    }

    private func getMemoryStats() -> (total: UInt64, used: UInt64, free: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory

        // Get actual memory usage via host_statistics64
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = UInt64(getpagesize())
            let free = UInt64(stats.free_count) * pageSize
            let active = UInt64(stats.active_count) * pageSize
            let inactive = UInt64(stats.inactive_count) * pageSize
            let wired = UInt64(stats.wire_count) * pageSize
            let compressed = UInt64(stats.compressor_page_count) * pageSize

            let used = active + wired + compressed
            return (total, used, free + inactive)
        }

        // Fallback estimate
        let used = UInt64(Double(total) * 0.6)
        return (total, used, total - used)
    }

    private func countInstalledApps() -> Int {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: applicationsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return contents.filter { $0.pathExtension == "app" }.count
        } catch {
            return 0
        }
    }

    private func updateSystemHealth(
        diskStats: (total: Int64, used: Int64, free: Int64),
        memoryStats: (total: UInt64, used: UInt64, free: UInt64)
    ) {
        let diskUsagePercent = diskStats.total > 0 ? Double(diskStats.used) / Double(diskStats.total) : 0
        let memoryUsagePercent = memoryStats.total > 0 ? Double(memoryStats.used) / Double(memoryStats.total) : 0

        if diskUsagePercent > 0.9 || memoryUsagePercent > 0.9 {
            systemHealthStatus = L("home.health.needsAttention")
            systemHealthColor = .red
        } else if diskUsagePercent > 0.75 || memoryUsagePercent > 0.8 {
            systemHealthStatus = L("home.health.fair")
            systemHealthColor = .yellow
        } else {
            systemHealthStatus = L("home.health.healthy")
            systemHealthColor = .green
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        formatBytes(Int64(bytes))
    }
}
