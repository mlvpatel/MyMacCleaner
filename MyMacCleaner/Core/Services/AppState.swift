import SwiftUI

/// Central app state that holds all ViewModels
/// This ensures state is preserved when switching between sections
@MainActor
class AppState: ObservableObject {
    // MARK: - Singleton ViewModels

    /// Home section state
    let homeViewModel: HomeViewModel

    /// Disk Cleaner section state
    let diskCleanerViewModel: DiskCleanerViewModel

    /// Adaptive experience (Guided / Standard / Technical) presentation state
    let adaptiveExperienceViewModel: AdaptiveExperienceViewModel

    /// Space Lens section state
    let spaceLensViewModel = SpaceLensViewModel()

    /// Performance section state
    let performanceViewModel = PerformanceViewModel()

    /// Applications section state
    let applicationsViewModel = ApplicationsViewModel()

    /// Port Management section state
    let portManagementViewModel = PortManagementViewModel()

    /// System Health section state
    let systemHealthViewModel = SystemHealthViewModel()

    /// Startup Items section state
    let startupItemsViewModel = StartupItemsViewModel()

    /// Permissions section state
    let permissionsViewModel = PermissionsViewModel()

    /// Orphaned Files section state
    let orphanedFilesViewModel = OrphanedFilesViewModel()

    /// Duplicates section state
    let duplicatesViewModel = DuplicatesViewModel()

    // MARK: - Initialization

    init() {
        let liveScan = CleanerCoreLiveScan()
        let trustSession = AdaptiveTrustSession(liveScan: liveScan)
        homeViewModel = HomeViewModel(scan: liveScan)
        diskCleanerViewModel = DiskCleanerViewModel(scan: liveScan)
        adaptiveExperienceViewModel = AdaptiveExperienceViewModel(
            loadSource: { await trustSession.makeSource() },
            executeDisplayedPlan: { digest, cancellation in
                await trustSession.executeDisplayedPlan(approvedDigestHex: digest, cancellation: cancellation)
            },
            scanSelectedRoot: { directory in await liveScan.selectedModelInventory(directory: directory) },
            environmentModelPrompts: liveScan.environmentModelRootPrompts()
        )
    }

    // MARK: - Cleanup

    /// Call this when app is about to terminate to cleanup resources
    func cleanup() {
        performanceViewModel.stopMonitoring()
    }
}
