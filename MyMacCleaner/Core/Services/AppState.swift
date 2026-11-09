import Combine
import SwiftUI

/// A link on Home to another page.
enum HomeLink {
    case experience
    /// "Learn why" on the Trash notice: Experience on its Trash explanation, without a scan.
    case trashExplanation
    case permissions
    /// Performance, opened at its read-only memory guidance.
    case memoryGuide
    /// Space Lens with the size filter on large items.
    case largeFiles
}

/// Central app state that holds all ViewModels
/// This ensures state is preserved when switching between sections
@MainActor
class AppState: ObservableObject {
    // MARK: - Singleton ViewModels

    /// Home section state
    let homeViewModel: HomeViewModel

    /// Disk Cleaner section state
    let diskCleanerViewModel: DiskCleanerViewModel

    /// Browser Privacy tab state, kept here so its results survive leaving Disk Cleaner
    let browserPrivacyViewModel = BrowserPrivacyViewModel()

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

    /// The latest display scan, shared by Home, Disk Cleaner and Adaptive Experience.
    let scanStore: SharedScanStore

    /// Bumped by each menu bar Scan request so every open window can switch to Home.
    @Published private(set) var smartScanRequests = 0

    private var smartScanObserver: AnyCancellable?

    // MARK: - Initialization

    init(notificationCenter: NotificationCenter = .default) {
        let liveScan = CleanerCoreLiveScan()
        let scanStore = SharedScanStore(scan: { try await liveScan.sharedScan() })
        self.scanStore = scanStore
        let trustSession = AdaptiveTrustSession(evidence: .live(liveScan: liveScan, store: scanStore))
        homeViewModel = HomeViewModel(scanStore: scanStore)
        diskCleanerViewModel = DiskCleanerViewModel(scanStore: scanStore)
        adaptiveExperienceViewModel = AdaptiveExperienceViewModel(
            loadSource: { await trustSession.makeSource() },
            executeDisplayedPlan: { digest, cancellation in
                await trustSession.executeDisplayedPlan(approvedDigestHex: digest, cancellation: cancellation)
            },
            loadSharedSource: { await trustSession.makeSource(reuseScan: true) },
            sharedScanDate: { scanStore.latest?.takenAt },
            openFileCheckUnavailable: { await trustSession.isOpenFileCheckUnavailable },
            scanSelectedRoot: { directory in await liveScan.selectedModelInventory(directory: directory) },
            environmentModelPrompts: liveScan.environmentModelRootPrompts()
        )
        smartScanObserver = notificationCenter.publisher(for: .triggerSmartScan)
            .sink { [weak self] _ in
                // Posted by the menu bar's Scan button, on the main thread.
                MainActor.assumeIsolated { self?.requestSmartScan() }
            }
    }

    /// Starts the Home Smart Scan (or its permission prompt) for the menu bar's Scan button.
    func requestSmartScan() {
        smartScanRequests += 1
        guard !homeViewModel.showPermissionPrompt else { return }
        homeViewModel.startSmartScan()
    }

    /// Readies the page a Home link opens and names its section. The window that showed the link
    /// switches itself, so a link never moves another window.
    func destination(for link: HomeLink) -> NavigationSection {
        switch link {
        case .experience:
            return .adaptiveExperience
        case .trashExplanation:
            adaptiveExperienceViewModel.openWithoutLoading()
            return .adaptiveExperience
        case .permissions:
            return .permissions
        case .memoryGuide:
            performanceViewModel.requestGuidance()
            return .performance
        case .largeFiles:
            // Space Lens never scans on entry; its start screen says the filter is on.
            spaceLensViewModel.sizeFilter = .over100MB
            return .spaceLens
        }
    }
}
