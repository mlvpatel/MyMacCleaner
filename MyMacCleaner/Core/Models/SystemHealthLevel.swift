import SwiftUI

/// What the Home pill and the sidebar badge may honestly say about disk and memory use.
/// Nothing is claimed before the first Smart Scan completes.
enum SystemHealthLevel: String, Equatable {
    case notScanned
    case healthy
    case fair
    case needsAttention

    /// Share of disk and memory in use, sampled when a Smart Scan completes. The worse of the two
    /// `StatusLevel`s decides, so Home agrees with the menu bar and Performance.
    static func assess(diskUsage: Double, memoryUsage: Double) -> SystemHealthLevel {
        switch max(StatusLevel.disk(diskUsage), StatusLevel.memory(memoryUsage)) {
        case .critical: return .needsAttention
        case .warning: return .fair
        case .normal: return .healthy
        }
    }

    var label: String {
        L(key: "home.health.\(rawValue)")
    }

    /// Text and shape carry the level, so it never depends on color alone.
    var icon: String {
        statusLevel?.icon ?? "circle.dashed"
    }

    var color: Color {
        statusLevel?.color ?? .secondary
    }

    private var statusLevel: StatusLevel? {
        switch self {
        case .notScanned: return nil
        case .healthy: return .normal
        case .fair: return .warning
        case .needsAttention: return .critical
        }
    }
}
