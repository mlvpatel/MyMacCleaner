import SwiftUI

/// How a live reading compares with `Theme.Thresholds`. The menu bar, Home and Performance all
/// derive color, icon and label from here, so the same value never reads differently.
enum StatusLevel: Int, Comparable {
    case normal
    case warning
    case critical

    /// `value` and both thresholds are fractions (0...1); a level is reached only above its threshold.
    init(_ value: Double, warning: Double, critical: Double) {
        if value > critical {
            self = .critical
        } else if value > warning {
            self = .warning
        } else {
            self = .normal
        }
    }

    /// Share of all CPU cores in use.
    static func cpu(_ usage: Double) -> StatusLevel {
        StatusLevel(usage, warning: Theme.Thresholds.CPU.warningUsage, critical: Theme.Thresholds.CPU.criticalUsage)
    }

    /// Share of physical memory in use (Active + Wired + Compressed).
    static func memory(_ usage: Double) -> StatusLevel {
        StatusLevel(usage, warning: Theme.Thresholds.Memory.warningUsage, critical: Theme.Thresholds.Memory.criticalUsage)
    }

    /// Share of the startup volume in use.
    static func disk(_ usage: Double) -> StatusLevel {
        StatusLevel(usage, warning: Theme.Thresholds.DiskSpace.warningUsage, critical: Theme.Thresholds.DiskSpace.criticalUsage)
    }

    static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .normal: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        case .critical: return Theme.Colors.error
        }
    }

    /// Text and shape carry the level, so it never depends on color alone.
    var icon: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .normal: return L("common.status.normal")
        case .warning: return L("common.status.warning")
        case .critical: return L("common.status.critical")
        }
    }
}
