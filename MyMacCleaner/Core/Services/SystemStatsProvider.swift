import Foundation
import Darwin

// MARK: - System Stats

struct SystemStats {
    var cpuUsage: Double = 0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0

    var formattedCPU: String {
        "\(Int(cpuUsage))%"
    }

    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsed), countStyle: .memory)
    }

    var formattedMemoryTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryTotal), countStyle: .memory)
    }

    var memoryUsagePercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }

    var formattedDisk: String {
        let used = ByteCountFormatter.string(fromByteCount: diskUsed, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: diskTotal, countStyle: .file)
        return "\(used) / \(total)"
    }

    var diskUsageFraction: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }
}

// MARK: - System Stats Provider

/// System stats provider for menu bar and other displays.
/// ponytail: thread confinement instead of an actor: published state and the timer are touched
/// only on the main thread, CPU sampling state only on `queue`. Make it an actor if that changes.
final class SystemStatsProvider: ObservableObject, @unchecked Sendable {
    static let shared = SystemStatsProvider()

    @Published var stats = SystemStats()
    @Published var isMonitoring = false

    private var timer: Timer?
    private var cpuInfo: processor_info_array_t?
    private var prevCpuInfo: processor_info_array_t?
    private var numCpuInfo: mach_msg_type_number_t = 0
    private var numPrevCpuInfo: mach_msg_type_number_t = 0
    private var numCPUs: UInt32 = 0
    /// Last disk reading; touched only on `queue`.
    private var diskSample: (used: Int64, total: Int64, takenAt: Date)?

    /// Disk use changes slowly and the important-usage query can be slow, so it is re-read at most this often.
    private static let diskRefreshInterval: TimeInterval = 30

    private let queue = DispatchQueue(label: "com.mymaccleaner.stats", qos: .utility)

    private init() {
        // Initialize CPU info
        var numCPUsU: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        if result == KERN_SUCCESS {
            numCPUs = numCPUsU
        }
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Control

    func startMonitoring(interval: TimeInterval = 2.0) {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Initial update
        updateStats()

        // Start timer; a 20 % tolerance lets macOS coalesce the wakeup with other work
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        timer?.tolerance = interval * 0.2
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    // MARK: - Stats Update

    private func updateStats() {
        queue.async { [weak self] in
            guard let self = self else { return }

            let memory = self.calculateMemoryUsage()
            let disk = self.currentDiskUsage()
            let stats = SystemStats(
                cpuUsage: self.calculateCPUUsage(),
                memoryUsed: memory.used,
                memoryTotal: memory.total,
                diskUsed: disk.used,
                diskTotal: disk.total
            )

            // One assignment per tick, so observers see one change instead of one per field.
            DispatchQueue.main.async {
                self.stats = stats
            }
        }
    }

    // MARK: - Disk Usage

    private func currentDiskUsage() -> (used: Int64, total: Int64) {
        if let sample = diskSample, Date().timeIntervalSince(sample.takenAt) < Self.diskRefreshInterval {
            return (sample.used, sample.total)
        }
        let disk = Self.diskUsage()
        diskSample = (disk.used, disk.total, Date())
        return disk
    }

    /// Used and total bytes of the startup volume; purgeable space counts as free (important-usage
    /// capacity, as Finder shows it). Zeros if the volume cannot be read.
    static func diskUsage() -> (used: Int64, total: Int64) {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? homeURL.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        ) else {
            return (0, 0)
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (total - available, total)
    }

    // MARK: - CPU Usage

    private func calculateCPUUsage() -> Double {
        var numCPUsU: natural_t = 0
        var newInfo: processor_info_array_t?
        var numInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &newInfo, &numInfo)

        guard result == KERN_SUCCESS, let newInfo = newInfo else { return 0 }

        var totalUsage: Double = 0

        if let prevInfo = prevCpuInfo, numCPUs > 0 {
            for i in 0..<Int(numCPUs) {
                let offset = Int32(CPU_STATE_MAX) * Int32(i)

                let userDiff = Double(newInfo[Int(offset + CPU_STATE_USER)]) - Double(prevInfo[Int(offset + CPU_STATE_USER)])
                let systemDiff = Double(newInfo[Int(offset + CPU_STATE_SYSTEM)]) - Double(prevInfo[Int(offset + CPU_STATE_SYSTEM)])
                let niceDiff = Double(newInfo[Int(offset + CPU_STATE_NICE)]) - Double(prevInfo[Int(offset + CPU_STATE_NICE)])
                let idleDiff = Double(newInfo[Int(offset + CPU_STATE_IDLE)]) - Double(prevInfo[Int(offset + CPU_STATE_IDLE)])

                let total = userDiff + systemDiff + niceDiff + idleDiff
                if total > 0 {
                    totalUsage += (userDiff + systemDiff + niceDiff) / total
                }
            }

            // Deallocate previous info
            let prevSize = vm_size_t(numPrevCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevInfo), prevSize)
        }

        prevCpuInfo = newInfo
        numPrevCpuInfo = numInfo

        return numCPUs > 0 ? (totalUsage / Double(numCPUs)) * 100 : 0
    }

    // MARK: - Memory Usage

    private func calculateMemoryUsage() -> (used: UInt64, total: UInt64) {
        Self.memoryUsage() ?? (0, ProcessInfo.processInfo.physicalMemory)
    }

    /// The app's one memory reading, shared by the menu bar, Home and System Health:
    /// used = Active + Wired + Compressed (matches Activity Monitor and htop). Nil if the kernel
    /// refuses the query. Safe from any thread.
    static func memoryUsage() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(getpagesize())
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        return (active + wired + compressed, ProcessInfo.processInfo.physicalMemory)
    }
}
