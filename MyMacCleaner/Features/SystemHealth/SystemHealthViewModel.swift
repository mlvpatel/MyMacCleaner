import SwiftUI
import IOKit
import IOKit.ps

// MARK: - System Health View Model

@MainActor
class SystemHealthViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var healthScore: Int = 0
    @Published var healthStatus: HealthStatus = .unknown
    @Published var healthChecks: [HealthCheck] = []
    @Published var batteryInfo: BatteryInfo?
    @Published var diskInfo: [DiskInfo] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    enum HealthStatus: String {
        case excellent
        case good
        case fair
        case poor
        case unknown

        var localizedName: String {
            L(key: "systemHealth.status.\(rawValue)")
        }

        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .orange
            case .poor: return .red
            case .unknown: return .gray
            }
        }

        var icon: String {
            switch self {
            case .excellent: return "checkmark.seal.fill"
            case .good: return "checkmark.circle.fill"
            case .fair: return "exclamationmark.triangle.fill"
            case .poor: return "xmark.octagon.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }
    }

    // MARK: - Public Methods

    /// Runs the first health check on the page's first appearance instead of at app launch.
    func loadIfNeeded() {
        guard lastUpdated == nil, !isLoading else { return }
        runHealthCheck()
    }

    func runHealthCheck() {
        isLoading = true
        healthChecks = []

        Task {
            // Run all health checks
            await checkDiskSpace()
            await checkMemoryPressure()
            await checkBattery()
            await checkDiskHealth()
            await checkStartupItems()
            healthChecks.append(Self.macOSVersionCheck(ProcessInfo.processInfo.operatingSystemVersion))

            // Calculate overall score
            calculateHealthScore()

            lastUpdated = Date()
            isLoading = false
        }
    }

    // MARK: - Health Check Methods

    private func checkDiskSpace() async {
        let check = HealthCheck(
            id: "disk_space",
            title: L("systemHealth.check.diskSpace"),
            description: L("systemHealth.check.diskSpace.checking"),
            icon: "internaldrive.fill",
            status: .checking
        )
        healthChecks.append(check)

        // Get disk space
        let fileManager = FileManager.default
        if let homeURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
           let values = try? homeURL.resourceValues(forKeys: [
               .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeLocalizedNameKey
           ]) {

            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let usedPercent = total > 0 ? Double(total - available) / Double(total) * 100 : 0

            let availableGB = Double(available) / 1_000_000_000
            let availableFormatted = String(format: "%.1f GB", availableGB)

            if availableGB > 50 {
                updateCheck(id: "disk_space", status: .passed, description: LFormat("systemHealth.check.diskSpace.passed %@", availableFormatted))
            } else if availableGB > 20 {
                updateCheck(id: "disk_space", status: .warning, description: LFormat("systemHealth.check.diskSpace.warning %@", availableFormatted))
            } else {
                updateCheck(id: "disk_space", status: .failed, description: LFormat("systemHealth.check.diskSpace.failed %@", availableFormatted))
            }

            // Store disk info
            let info = DiskInfo(
                name: values.volumeLocalizedName ?? L("systemHealth.disk.startup"),
                totalSpace: total,
                availableSpace: available,
                usedPercent: usedPercent
            )
            diskInfo = [info]
        } else {
            updateCheck(id: "disk_space", status: .failed, description: L("systemHealth.check.diskSpace.error"))
        }
    }

    private func checkMemoryPressure() async {
        let check = HealthCheck(
            id: "memory",
            title: L("systemHealth.check.memory"),
            description: L("systemHealth.check.memory.checking"),
            icon: "memorychip.fill",
            status: .checking
        )
        healthChecks.append(check)

        if let memory = SystemStatsProvider.memoryUsage(), memory.total > 0 {
            let usage = Double(memory.used) / Double(memory.total)
            let percentFormatted = String(format: "%.0f%%", usage * 100)

            switch StatusLevel.memory(usage) {
            case .normal:
                updateCheck(id: "memory", status: .passed, description: LFormat("systemHealth.check.memory.passed %@", percentFormatted))
            case .warning:
                updateCheck(id: "memory", status: .warning, description: LFormat("systemHealth.check.memory.warning %@", percentFormatted))
            case .critical:
                updateCheck(id: "memory", status: .failed, description: LFormat("systemHealth.check.memory.failed %@", percentFormatted))
            }
        } else {
            updateCheck(id: "memory", status: .warning, description: L("systemHealth.check.memory.error"))
        }
    }

    private func checkBattery() async {
        let check = HealthCheck(
            id: "battery",
            title: L("systemHealth.check.battery"),
            description: L("systemHealth.check.battery.checking"),
            icon: "battery.100",
            status: .checking
        )
        healthChecks.append(check)

        // Check if this is a laptop
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        if sources.isEmpty {
            updateCheck(id: "battery", status: .passed, description: L("systemHealth.check.battery.desktop"))
            return
        }

        // Get battery info
        if let source = sources.first,
           let info = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {

            let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            let cycleCount = info["BatteryCycleCount"] as? Int
            let health = info["BatteryHealth"] as? String

            let healthPercent = maxCapacity > 0 ? Double(currentCapacity) / Double(maxCapacity) * 100 : 0

            batteryInfo = BatteryInfo(
                percentage: Int(healthPercent),
                isCharging: isCharging,
                cycleCount: cycleCount,
                health: health ?? "Normal",
                maxCapacity: maxCapacity
            )

            if health == "Good" || health == "Normal" {
                updateCheck(id: "battery", status: .passed, description: LFormat("systemHealth.check.battery.passed %@", health ?? "Good"))
            } else if health == "Fair" {
                updateCheck(id: "battery", status: .warning, description: L("systemHealth.check.battery.warning"))
            } else {
                updateCheck(id: "battery", status: .failed, description: L("systemHealth.check.battery.failed"))
            }
        } else {
            updateCheck(id: "battery", status: .warning, description: L("systemHealth.check.battery.error"))
        }
    }

    private func checkDiskHealth() async {
        let check = HealthCheck(
            id: "disk_health",
            title: L("systemHealth.check.diskHealth"),
            description: L("systemHealth.check.diskHealth.checking"),
            icon: "externaldrive.fill",
            status: .checking
        )
        healthChecks.append(check)

        let result = Self.diskHealthResult(await readRootDiskInfo())
        updateCheck(id: "disk_health", status: result.status, description: L(result.key))
    }

    /// A diskutil failure is unavailable, never healthy. Internal for tests.
    nonisolated static func diskHealthResult(_ health: RootDiskHealth) -> (status: HealthCheck.Status, key: String) {
        switch health {
        case .verified: (.passed, "systemHealth.check.diskHealth.verified")
        case .notSupported: (.passed, "systemHealth.check.diskHealth.ssd")
        case .unknown: (.warning, "systemHealth.check.diskHealth.unknown")
        case .unavailable: (.unavailable, "systemHealth.check.diskHealth.unavailable")
        }
    }

    private func checkStartupItems() async {
        let check = HealthCheck(
            id: "startup",
            title: L("systemHealth.check.startup"),
            description: L("systemHealth.check.startup.checking"),
            icon: "power",
            status: .checking
        )
        healthChecks.append(check)

        // Check launch agents
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let launchAgentsPath = homeDir.appendingPathComponent("Library/LaunchAgents")

        var itemCount = 0
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: launchAgentsPath.path) {
            itemCount = contents.filter { $0.hasSuffix(".plist") }.count
        }

        if itemCount < 10 {
            updateCheck(id: "startup", status: .passed, description: LFormat("systemHealth.check.startup.passed %lld", itemCount))
        } else if itemCount < 20 {
            updateCheck(id: "startup", status: .warning, description: LFormat("systemHealth.check.startup.warning %lld", itemCount))
        } else {
            updateCheck(id: "startup", status: .failed, description: LFormat("systemHealth.check.startup.failed %lld", itemCount))
        }
    }

    /// The installed macOS version, shown for reference. The app can't check for updates, so this
    /// row never claims "up to date" and never counts toward the score. Internal for tests.
    nonisolated static func macOSVersionCheck(_ version: OperatingSystemVersion) -> HealthCheck {
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return HealthCheck(
            id: "macos_version",
            title: L("systemHealth.check.macOSVersion"),
            description: LFormat("systemHealth.check.macOSVersion.info %@", versionString),
            icon: "apple.logo",
            status: .info
        )
    }

    // MARK: - Helper Methods

    private func updateCheck(id: String, status: HealthCheck.Status, description: String) {
        if let index = healthChecks.firstIndex(where: { $0.id == id }) {
            healthChecks[index].status = status
            healthChecks[index].description = description
        }
    }

    private func calculateHealthScore() {
        let result = Self.healthScore(for: healthChecks.map(\.status))
        healthScore = result.score
        healthStatus = result.status
    }

    /// Passed checks count 100%, warnings 50%, anything else 0%, so a check that couldn't run keeps
    /// the score below Excellent. Informational rows don't count. Internal for tests.
    nonisolated static func healthScore(for allStatuses: [HealthCheck.Status]) -> (score: Int, status: HealthStatus) {
        let statuses = allStatuses.filter { $0 != .info }
        guard !statuses.isEmpty else { return (0, .unknown) }

        let passedCount = statuses.filter { $0 == .passed }.count
        let warningCount = statuses.filter { $0 == .warning }.count
        let score = (passedCount * 100 + warningCount * 50) / statuses.count

        switch score {
        case 90...: return (score, .excellent)
        case 70...: return (score, .good)
        case 50...: return (score, .fair)
        default: return (score, .poor)
        }
    }

    /// The sentence under the score. It never calls the Mac healthy when a check couldn't run.
    /// Internal for tests.
    nonisolated static func summary(for statuses: [HealthCheck.Status]) -> String {
        let passed = statuses.filter { $0 == .passed }.count
        let warnings = statuses.filter { $0 == .warning }.count
        let failed = statuses.filter { $0 == .failed }.count
        let unavailable = statuses.filter { $0 == .unavailable }.count

        if failed > 0 {
            return LFormat("systemHealth.summary.failed %lld", failed)
        } else if warnings > 0 {
            return LFormat("systemHealth.summary.warnings %lld %lld", passed, warnings)
        } else if unavailable > 0 {
            return LFormat("systemHealth.summary.incomplete %lld %lld", passed, unavailable)
        } else {
            return LFormat("systemHealth.summary.passed %lld", passed)
        }
    }

    enum RootDiskHealth {
        case verified
        case notSupported
        case unknown
        case unavailable
    }

    // SAFETY-AUDIT: fixed read-only process adapter — /usr/sbin/diskutil info /
    private func readRootDiskInfo() async -> RootDiskHealth {
        guard let data = await ReadOnlyProcess.run(.rootDiskInfo),
              let text = String(data: data, encoding: .utf8)
        else {
            return .unavailable
        }
        return Self.parseDiskInfo(text)
    }

    /// Classifies `diskutil info /` output. Internal for tests.
    nonisolated static func parseDiskInfo(_ output: String) -> RootDiskHealth {
        if output.contains("SMART Status") && output.contains("Verified") {
            return .verified
        }
        if output.contains("Not Supported") {
            return .notSupported
        }
        return .unknown
    }
}

// MARK: - Health Check Model

struct HealthCheck: Identifiable {
    let id: String
    var title: String
    var description: String
    var icon: String
    var status: Status

    enum Status {
        case checking
        case passed
        case warning
        case failed
        /// A fact shown for reference; never part of the score.
        case info
        /// The check couldn't run, so its result is unknown.
        case unavailable

        var color: Color {
            switch self {
            case .checking: return .gray
            case .passed: return .green
            case .warning: return .orange
            case .failed: return .red
            case .info: return .blue
            case .unavailable: return .gray
            }
        }

        var icon: String {
            switch self {
            case .checking: return "ellipsis.circle"
            case .passed: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .unavailable: return "questionmark.circle.fill"
            }
        }
    }
}

// MARK: - Battery Info Model

struct BatteryInfo {
    let percentage: Int
    let isCharging: Bool
    let cycleCount: Int?
    let health: String
    let maxCapacity: Int
}

// MARK: - Disk Info Model

struct DiskInfo: Identifiable {
    let id = UUID()
    let name: String
    let totalSpace: Int64
    let availableSpace: Int64
    let usedPercent: Double

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: totalSpace - availableSpace, countStyle: .file)
    }
}
