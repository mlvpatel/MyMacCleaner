import Foundation
import AppKit
import SwiftUI

// MARK: - Permissions Service

@MainActor
class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    @Published var hasFullDiskAccess: Bool = false
    @Published var isCheckingPermissions: Bool = false

    private let probe: any PermissionProbing

    init(probe: any PermissionProbing = POSIXPermissionProbe()) {
        self.probe = probe
        checkFullDiskAccess()
    }

    // MARK: - Full Disk Access

    /// Check if the app has Full Disk Access permission.
    ///
    /// Derived from a read-only open/close probe of an FDA-gated path: the descriptor is closed
    /// immediately and no contents are read, matching the app's point-of-use permission approach.
    func checkFullDiskAccess() {
        isCheckingPermissions = true
        hasFullDiskAccess = PermissionAssessment.hasFullDiskAccess(using: probe)
        isCheckingPermissions = false
    }

    /// Open System Preferences to Full Disk Access pane
    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Permission Descriptions

    struct PermissionInfo {
        let name: String
        let description: String
        let isRequired: Bool
        let features: [String]

        var localizedFeatures: [String] {
            [
                L("permissions.fda.feature.systemCaches"),
                L("permissions.fda.feature.appLogs"),
                L("permissions.fda.feature.leftovers"),
                L("permissions.fda.feature.mailAttachments"),
                L("permissions.fda.feature.spaceLens")
            ]
        }
    }

    static let fullDiskAccessInfo = PermissionInfo(
        name: "Full Disk Access",
        description: "Allows scanning system caches, logs, and application data for cleanup.",
        isRequired: false,
        features: [
            "Scan system caches",
            "Scan application logs",
            "Detect app leftovers during uninstall",
            "Access Mail attachments",
            "Complete Space Lens visualization"
        ]
    )
}

// MARK: - Permission Status

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
    case restricted

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .restricted: return .gray
        }
    }

    var icon: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .restricted: return "lock.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .granted: return L("permissions.status.granted")
        case .denied: return L("permissions.status.denied")
        case .notDetermined: return L("permissions.status.notDetermined")
        case .restricted: return L("permissions.status.restricted")
        }
    }
}
