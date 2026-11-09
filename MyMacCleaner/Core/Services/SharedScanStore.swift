import CleanerCore
import Foundation

/// One general-Mac scan for display, read by Home, Disk Cleaner and Adaptive Experience.
struct SharedScan: Sendable {
    let collection: AdaptiveScanCollection
    /// False when the open-file listing did not run, so nothing in a Trash-eligible root was eligible.
    let openFilesChecked: Bool
    /// Home and Disk Cleaner cards, derived once off the main actor.
    let legacyReport: LegacyScanReport
    /// When the scan started.
    let takenAt: Date
}

/// Keeps the latest display scan, so one scan feeds Home, Disk Cleaner and Adaptive Experience.
/// A Trash run never reads it: it re-validates every item on its own fresh scan.
@MainActor
final class SharedScanStore: ObservableObject {
    typealias Scan = @Sendable () async throws -> SharedScan

    /// How long a scan may be shown again before a screen scans anew.
    static let reuseWindow: TimeInterval = 5 * 60

    @Published private(set) var latest: SharedScan?

    private let scan: Scan
    private let now: @Sendable () -> Date

    init(scan: @escaping Scan, now: @escaping @Sendable () -> Date = { Date() }) {
        self.scan = scan
        self.now = now
    }

    /// Scans in the caller's task, so cancelling the caller stops the scan. A cancelled scan is
    /// partial evidence and is never kept, and a scan that started earlier never replaces a newer one.
    func refresh() async throws -> SharedScan {
        let scanned = try await scan()
        try Task.checkCancellation()
        if let latest, latest.takenAt > scanned.takenAt {
            return scanned
        }
        latest = scanned
        return scanned
    }

    /// The latest scan while it is younger than `reuseWindow`, otherwise a new one.
    func current() async throws -> SharedScan {
        if let latest, now().timeIntervalSince(latest.takenAt) < Self.reuseWindow {
            return latest
        }
        return try await refresh()
    }
}
