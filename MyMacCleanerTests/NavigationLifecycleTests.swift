import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

// MARK: - Adaptive Experience Lifecycle Tests

@Suite("Adaptive Experience Lifecycle Tests")
@MainActor
struct AdaptiveExperienceLifecycleTests {
    @Test("The page loads on its first appearance and shows the same evidence on the next visit")
    func loadsOnceAndReusesOnReturn() async throws {
        let loads = LoadTally()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { loads.fresh(); return .success(Self.source) },
            loadSharedSource: { loads.shared(); return .success(Self.source) },
            onboardingStore: try Self.onboarding(acknowledged: true)
        )

        viewModel.pageAppeared()
        #expect(await waitUntil { viewModel.source != nil && !viewModel.isRefreshing })
        viewModel.pageDisappeared()
        viewModel.pageAppeared()

        #expect(viewModel.isRefreshing == false)
        #expect(loads.sharedCount == 1)
        #expect(loads.freshCount == 0)
    }

    @Test("Shown evidence reloads once it is older than the window, or when another page scanned")
    func reloadsWhenStale() async throws {
        let loads = LoadTally()
        let clock = MainActorClock(Date(timeIntervalSince1970: 10_000))
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { loads.fresh(); return .success(Self.source) },
            loadSharedSource: { loads.shared(); return .success(Self.source) },
            sharedScanDate: { clock.sharedScan },
            now: { clock.now },
            onboardingStore: try Self.onboarding(acknowledged: true)
        )

        viewModel.pageAppeared()
        #expect(await waitUntil { loads.sharedCount == 1 && !viewModel.isRefreshing })

        clock.advance(by: AdaptiveExperienceViewModel.staleAfter - 1)
        viewModel.pageAppeared()
        #expect(viewModel.isRefreshing == false)

        clock.advance(by: 1)
        viewModel.pageAppeared()
        #expect(await waitUntil { loads.sharedCount == 2 && !viewModel.isRefreshing })

        clock.sharedScan = clock.now.addingTimeInterval(1)
        viewModel.pageAppeared()
        #expect(await waitUntil { loads.sharedCount == 3 && !viewModel.isRefreshing })
        #expect(loads.freshCount == 0)
    }

    @Test("The first load waits until onboarding is acknowledged")
    func firstLoadWaitsForOnboarding() throws {
        let loads = LoadTally()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { loads.fresh(); return .success(Self.source) },
            loadSharedSource: { loads.shared(); return .success(Self.source) },
            onboardingStore: try Self.onboarding(acknowledged: false)
        )

        viewModel.pageAppeared()
        #expect(viewModel.isRefreshing == false)

        viewModel.dispatch(.acknowledgeOnboarding)
        // The view calls this when the onboarding sheet closes.
        viewModel.pageAppeared()
        #expect(viewModel.isRefreshing)
        viewModel.pageDisappeared()
    }

    @Test("Learn why on a Trash notice opens the page without a load; the next visit loads as usual")
    func learnWhyOpensWithoutLoading() throws {
        let loads = LoadTally()
        let source = Self.source
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { loads.fresh(); return .success(source) },
            loadSharedSource: { loads.shared(); return .success(source) },
            onboardingStore: try Self.onboarding(acknowledged: true)
        )

        viewModel.openWithoutLoading()
        viewModel.pageAppeared()
        #expect(viewModel.isRefreshing == false)

        viewModel.pageDisappeared()
        viewModel.pageAppeared()
        #expect(viewModel.isRefreshing)
        viewModel.pageDisappeared()
    }

    @Test("Leaving the page stops a refresh but never a Trash run")
    func leavingStopsRefreshButNotARun() async throws {
        let gate = LifecycleGate()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { await gate.wait(); return .failure(.scanFailed) },
            executeDisplayedPlan: { _, _ in await gate.wait(); return .failure(.scanFailed) },
            loadSharedSource: { await gate.wait(); return .failure(.scanFailed) },
            onboardingStore: try Self.onboarding(acknowledged: true)
        )

        viewModel.pageAppeared()
        #expect(viewModel.isRefreshing)
        viewModel.pageDisappeared()
        #expect(viewModel.isRefreshing == false)

        viewModel.runDisplayedPlan(approvedDigestHex: String(repeating: "0a", count: 32))
        viewModel.pageDisappeared()
        #expect(viewModel.isExecuting)
        #expect(viewModel.isStopRequested == false)

        await gate.open()
        #expect(await waitUntil { !viewModel.isExecuting })
    }

    private static let source = AdaptiveExperienceSource(
        scanState: .complete,
        findings: [],
        evaluations: [],
        reviewPlan: nil,
        approvalValidity: .invalid(.missingApproval),
        executionState: nil,
        executionOutcomes: [],
        receipts: [],
        memory: nil,
        capabilities: [],
        permissionGaps: [],
        developerInventory: []
    )

    /// A private defaults suite, so the test never touches the real onboarding flag.
    private static func onboarding(acknowledged: Bool) throws -> AdaptiveOnboardingStore {
        let defaults = try #require(UserDefaults(suiteName: "lifecycle-tests-\(UUID().uuidString)"))
        let store = AdaptiveOnboardingStore(defaults: defaults)
        store.hasAcknowledged = acknowledged
        return store
    }
}

// MARK: - Leaving a Scan Page Tests

@Suite("Leaving a Scan Page Tests")
@MainActor
struct LeavingScanPageTests {
    @Test("Leaving Home mid-scan stops the scan and says so until the next scan")
    func homeSaysTheScanStopped() {
        let viewModel = HomeViewModel(scanStore: SharedScanStore(scan: {
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        }))

        viewModel.leavePage()
        #expect(viewModel.scanStoppedByLeaving == false)

        viewModel.continueWithLimitedScan()
        viewModel.leavePage()
        #expect(viewModel.isScanning == false)
        #expect(viewModel.scanStoppedByLeaving)

        viewModel.continueWithLimitedScan()
        #expect(viewModel.scanStoppedByLeaving == false)
        viewModel.cancelScan()
    }

    @Test("Leaving Orphaned Files mid-scan stops the scan and says so")
    func orphansSayTheScanStopped() {
        let viewModel = OrphanedFilesViewModel(scan: { _ in
            try? await Task.sleep(for: .seconds(600))
            return []
        })

        viewModel.startScan()
        viewModel.leavePage()

        #expect(viewModel.isScanning == false)
        #expect(viewModel.scanStoppedByLeaving)
    }

    @Test("Browser Privacy runs one scan at a time and Cancel discards it")
    func browserPrivacyRunsOneCancellableScan() async {
        let scans = ScanCounter()
        let viewModel = BrowserPrivacyViewModel(scanBrowsers: {
            scans.increment()
            try? await Task.sleep(for: .seconds(600))
            return BrowserScan(items: [], unreadableBrowsers: [])
        })

        viewModel.scan()
        viewModel.scan()
        #expect(await waitUntil { scans.count == 1 })
        viewModel.cancelScan()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(scans.count == 1)
        #expect(viewModel.isScanning == false)
        #expect(viewModel.hasScanned == false)
    }

    @Test("Browser Privacy lives on AppState and keeps its results when a rescan is stopped")
    func browserPrivacyKeepsResultsAcrossNavigation() async {
        let item = BrowserDataItem(browser: .chrome, dataType: .cache, path: URL(fileURLWithPath: "/tmp/c"), size: 1)
        let scans = ScanCounter()
        let viewModel = BrowserPrivacyViewModel(scanBrowsers: {
            scans.increment()
            if scans.count > 1 { try? await Task.sleep(for: .seconds(600)) }
            return BrowserScan(items: [item], unreadableBrowsers: [])
        })
        viewModel.scan()
        #expect(await waitUntil { viewModel.hasScanned })

        viewModel.scan()
        // Leaving the Privacy tab or Disk Cleaner cancels the rescan.
        viewModel.cancelScan()

        #expect(viewModel.hasScanned)
        #expect(viewModel.items.map(\.id) == [item.id])
        // Both outlive the Disk Cleaner view, so a section switch resets neither.
        let appState = AppState()
        #expect(appState.browserPrivacyViewModel.hasScanned == false)
        #expect(appState.diskCleanerViewModel.selectedTab == .cleaner)
    }

    @Test("Leaving Applications stops size analysis, and the cancelled work never reports done")
    func applicationsStopWorkOnLeave() async {
        let viewModel = ApplicationsViewModel()

        viewModel.startFullAnalysis()
        viewModel.stopWork()
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(viewModel.analysisState == .idle)
        #expect(viewModel.discoveryState == .idle)
    }
}

// MARK: - Helpers

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

private final class LoadTally: @unchecked Sendable {
    private let lock = NSLock()
    private var freshLoads = 0
    private var sharedLoads = 0

    var freshCount: Int { lock.withLock { freshLoads } }
    var sharedCount: Int { lock.withLock { sharedLoads } }

    func fresh() { lock.withLock { freshLoads += 1 } }
    func shared() { lock.withLock { sharedLoads += 1 } }
}

@MainActor
private final class MainActorClock {
    private(set) var now: Date
    var sharedScan: Date?

    init(_ start: Date) {
        now = start
    }

    func advance(by interval: TimeInterval) {
        now += interval
    }
}

/// Holds callers until the test opens it.
private actor LifecycleGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
