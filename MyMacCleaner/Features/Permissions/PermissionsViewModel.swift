import Foundation
import SwiftUI
import AppKit

@MainActor
class PermissionsViewModel: ObservableObject {
    @Published var categories: [PermissionCategoryState] = []
    @Published var isLoading = false
    @Published var lastChecked: Date?

    let toasts = ToastPresenter()

    private let permissionsService = PermissionsService.shared
    private let openURL: (URL) -> Void

    /// Folder checks start when the Permissions page appears, never at app launch.
    init(openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
        buildCategories()
    }

    // MARK: - Category Building

    private func buildCategories() {
        categories = [
            buildFullDiskAccessCategory(),
            buildUserFoldersCategory(),
            buildSystemFoldersCategory(),
            buildApplicationDataCategory(),
            buildStartupPathsCategory()
        ]
    }

    private func buildFullDiskAccessCategory() -> PermissionCategoryState {
        let folders = [
            FolderAccessInfo(
                path: "~/Library/Application Support/com.apple.TCC/TCC.db",
                displayName: "TCC Database",
                requiresFDA: true,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/Library/Safari/Bookmarks.plist",
                displayName: "Safari Bookmarks",
                requiresFDA: true,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/Library/Mail",
                displayName: "Mail Library",
                requiresFDA: true,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                displayName: "Mail Attachments",
                requiresFDA: true,
                canTriggerTCCDialog: false
            )
        ]
        return PermissionCategoryState(type: .fullDiskAccess, folders: folders)
    }

    private func buildUserFoldersCategory() -> PermissionCategoryState {
        let folders = [
            FolderAccessInfo(
                path: "~/Downloads",
                displayName: "Downloads",
                requiresFDA: false,
                canTriggerTCCDialog: true
            ),
            FolderAccessInfo(
                path: "~/Documents",
                displayName: "Documents",
                requiresFDA: false,
                canTriggerTCCDialog: true
            ),
            FolderAccessInfo(
                path: "~/Desktop",
                displayName: "Desktop",
                requiresFDA: false,
                canTriggerTCCDialog: true
            )
        ]
        return PermissionCategoryState(type: .userFolders, folders: folders)
    }

    private func buildSystemFoldersCategory() -> PermissionCategoryState {
        let folders = [
            // World-readable: Full Disk Access doesn't change access to these.
            FolderAccessInfo(
                path: "/Library/Caches",
                displayName: "System Caches",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "/Library/Logs",
                displayName: "System Logs",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "/Library/LaunchAgents",
                displayName: "System Launch Agents",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "/Library/LaunchDaemons",
                displayName: "System Launch Daemons",
                requiresFDA: false,
                canTriggerTCCDialog: false
            )
        ]
        return PermissionCategoryState(type: .systemFolders, folders: folders)
    }

    private func buildApplicationDataCategory() -> PermissionCategoryState {
        let folders = [
            FolderAccessInfo(
                path: "~/Library/Caches",
                displayName: "User Caches",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/Library/Logs",
                displayName: "User Logs",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/Library/Caches/com.apple.Safari",
                displayName: "Safari Cache",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/Library/Caches/Google/Chrome",
                displayName: "Chrome Cache",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/Library/Developer/Xcode/DerivedData",
                displayName: "Xcode DerivedData",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "~/.Trash",
                displayName: "Trash",
                requiresFDA: false,
                canTriggerTCCDialog: false
            )
        ]
        return PermissionCategoryState(type: .applicationData, folders: folders)
    }

    private func buildStartupPathsCategory() -> PermissionCategoryState {
        let folders = [
            FolderAccessInfo(
                path: "~/Library/LaunchAgents",
                displayName: "User Launch Agents",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "/System/Library/LaunchAgents",
                displayName: "Apple Launch Agents",
                requiresFDA: false,
                canTriggerTCCDialog: false
            ),
            FolderAccessInfo(
                path: "/System/Library/LaunchDaemons",
                displayName: "Apple Launch Daemons",
                requiresFDA: false,
                canTriggerTCCDialog: false
            )
        ]
        return PermissionCategoryState(type: .startupPaths, folders: folders)
    }

    // MARK: - Permission Checking

    /// Check all permissions
    /// - Parameter skipTCCTriggerable: If true, skip folders that would trigger TCC permission dialogs.
    ///   Use this at startup to avoid bombarding users with permission prompts.
    func checkAllPermissions(skipTCCTriggerable: Bool = false) async {
        isLoading = true

        for categoryIndex in categories.indices {
            for folderIndex in categories[categoryIndex].folders.indices {
                let folder = categories[categoryIndex].folders[folderIndex]

                // Skip folders that would trigger TCC dialogs if requested
                if skipTCCTriggerable && folder.canTriggerTCCDialog {
                    continue
                }

                let status = await Self.checkFolderAccess(folder.expandedPath)

                await MainActor.run {
                    categories[categoryIndex].folders[folderIndex].status = status
                }
            }
        }

        await MainActor.run {
            lastChecked = Date()
            isLoading = false
            // Also update the shared PermissionsService FDA status
            permissionsService.checkFullDiskAccess()
        }
    }

    /// Off the main actor: reading a protected folder blocks while macOS shows its prompt.
    nonisolated private static func checkFolderAccess(_ path: String) async -> FolderAccessStatus {
        let fileManager = FileManager.default

        // Check if path exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .notExists
        }

        // Try to actually read the directory/file
        do {
            if isDirectory.boolValue {
                _ = try fileManager.contentsOfDirectory(atPath: path)
            } else {
                _ = try Data(contentsOf: URL(fileURLWithPath: path))
            }
            return .accessible
        } catch {
            return .denied
        }
    }

    // MARK: - Actions

    func toggleCategory(_ categoryId: UUID) {
        if let index = categories.firstIndex(where: { $0.id == categoryId }) {
            withAnimation(Theme.Animation.spring) {
                categories[index].isExpanded.toggle()
            }
        }
    }

    func openFullDiskAccessSettings() {
        permissionsService.openFullDiskAccessSettings()
    }

    func requestFolderAccess(_ folder: FolderAccessInfo) {
        Task { await requestAccess(to: folder) }
    }

    /// macOS asks only once per folder. When the folder is still unreadable after asking, the
    /// Files and Folders pane is the only way left, so open it and say why. Internal for tests.
    func requestAccess(to folder: FolderAccessInfo) async {
        // Attempting to read triggers TCC dialog
        if await Self.triggerTCCDialog(for: folder.expandedPath) {
            await checkAllPermissions()
            return
        }
        openFilesAndFoldersSettings()
        toasts.show(LFormat("permissions.folder.stillDenied %@", folder.displayName), type: .error)
    }

    /// Off the main actor, like `checkFolderAccess`, so the window stays responsive under the prompt.
    nonisolated private static func triggerTCCDialog(for path: String) async -> Bool {
        let fileManager = FileManager.default
        do {
            _ = try fileManager.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }

    func refreshAllPermissions() {
        Task {
            await checkAllPermissions()
        }
    }

    func revokeFolderAccess(_ folder: FolderAccessInfo) {
        // macOS doesn't allow programmatic revocation of permissions
        // Open the appropriate System Settings pane for the user to revoke manually
        // Rows offer this only when `isAccessManagedInSystemSettings` is true.
        if folder.requiresFDA {
            // Open Full Disk Access settings
            openFullDiskAccessSettings()
        } else if folder.canTriggerTCCDialog {
            // Open Files and Folders settings for TCC-protected folders
            openFilesAndFoldersSettings()
        }
    }

    private func openFilesAndFoldersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            openURL(url)
        }
    }

    // MARK: - Summary Stats

    var totalAccessible: Int {
        categories.flatMap { $0.folders }.filter { $0.status == .accessible }.count
    }

    var totalExisting: Int {
        categories.flatMap { $0.folders }.filter { $0.status != .notExists }.count
    }

    var overallStatus: FolderAccessStatus {
        let existing = categories.flatMap { $0.folders }.filter { $0.status != .notExists }
        guard !existing.isEmpty else { return .notExists }

        if existing.allSatisfy({ $0.status == .accessible }) {
            return .accessible
        } else if existing.contains(where: { $0.status == .checking }) {
            return .checking
        } else {
            return .denied
        }
    }
}
