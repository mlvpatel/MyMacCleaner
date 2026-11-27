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

        /// Only what the app reads with Full Disk Access: the Smart Scan folders, Safari data in
        /// Browser Privacy, app containers in Orphaned Files and protected folders in Space Lens.
        var localizedFeatures: [String] {
            [
                L("permissions.fda.feature.personalFolders"),
                L("permissions.fda.feature.protectedCaches"),
                L("permissions.fda.feature.safari"),
                L("permissions.fda.feature.leftovers"),
                L("permissions.fda.feature.spaceLens")
            ]
        }
    }

    static let fullDiskAccessInfo = PermissionInfo(
        name: "Full Disk Access",
        description: "Lets scans read folders macOS protects.",
        isRequired: false,
        features: [
            "Read Desktop, Documents and Downloads without a prompt for each",
            "Read protected cache and log folders",
            "Read Safari history and website data",
            "Find leftovers inside protected app containers",
            "Complete Space Lens analysis"
        ]
    )
}
