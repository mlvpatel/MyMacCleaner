import Accessibility
import Combine
import Foundation
import CleanerCore

enum AdaptiveSafeIntent: Equatable {
    case refresh
    case cancel
    case permissionHelp
    case focus(opaqueID: String)
    case acknowledgeOnboarding
    case requestApproveDisplayedPlan
    case confirmApproveDisplayedPlan
    case dismissApproveDisplayedPlan
    case dismissFailure
}

enum AdaptiveSheet: Equatable {
    case onboarding
    case review
    case receipts
    case permissionHelp
}

@MainActor
final class AdaptiveExperienceViewModel: ObservableObject {
    typealias SourceResult = Result<AdaptiveExperienceSource, AdaptiveSessionFailure>
    typealias ExecuteDisplayedPlan = @Sendable (
        _ approvedDigestHex: String,
        _ cancellation: TrashRunCancellation
    ) async -> SourceResult
    /// Reads a user-chosen directory as a read-only selected model-store root (C2).
    typealias ScanSelectedRoot = @Sendable (_ directory: URL) async -> ModelStoreProjection?
    /// Builds the mode-independent part of the projection; injectable so tests can count builds.
    typealias BuildAuthority = @Sendable (AdaptiveExperienceSource) throws -> AdaptiveExperienceAuthority
    /// True when the last load could not list open files; injectable so tests can force it.
    typealias OpenFileCheckUnavailable = @Sendable () async -> Bool
    /// A loaded source with its authority already built off the main actor.
    private typealias PreparedSource = (
        source: AdaptiveExperienceSource,
        authority: Result<AdaptiveExperienceAuthority, any Error>,
        openFilesUnchecked: Bool
    )
    private typealias PreparedResult = Result<PreparedSource, AdaptiveSessionFailure>
    /// Speaks a status change to VoiceOver; injectable so tests can read what was announced.
    typealias Announce = @MainActor (String) -> Void

    /// Shown evidence older than this is reloaded when the page next appears.
    static let staleAfter = SharedScanStore.reuseWindow

    @Published private(set) var snapshot: AdaptiveExperienceProjection?
    @Published private(set) var source: AdaptiveExperienceSource?
    @Published private(set) var presentationMode: PresentationMode = .standard
    @Published private(set) var focusedID: String?
    @Published private(set) var sheet: AdaptiveSheet?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isExecuting = false
    @Published private(set) var isStopRequested = false
    /// Last session failure shown to the user; cleared by dismissal or the next successful load.
    @Published private(set) var failure: AdaptiveSessionFailure?
    @Published private(set) var showApprovalConfirmation = false
    @Published private(set) var showOnboarding: Bool
    /// Read-only inventories of directories the user explicitly added (C2).
    @Published private(set) var selectedModelStores: [ModelStoreProjection] = []
    /// Names of set model-store env vars (e.g. HF_HOME) surfaced as a prompt (C2).
    @Published private(set) var environmentModelPrompts: [String]
    /// Says why a chosen model folder was not added.
    let toasts = ToastPresenter()

    private var refreshIdentity: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    /// When the shown evidence was applied; nil until the first successful load.
    private var loadedAt: Date?
    /// Set by `openWithoutLoading`; the next page appearance does not load.
    private var skipsNextLoad = false
    /// Digest of the plan on screen when approval was requested; only this plan may run.
    private var pendingApprovalDigestHex: String?
    private var runCancellation: TrashRunCancellation?
    /// Model folders added or being read, so the same folder is not inventoried twice.
    private var selectedModelRoots: Set<URL> = []
    /// Mode-independent projection of `source`, cached so a mode switch only re-picks presentation keys.
    private var authority: AdaptiveExperienceAuthority?
    private let loadSource: @Sendable () async -> SourceResult
    /// Loads from a shared scan still inside its reuse window; a page appearance uses it.
    private let loadSharedSource: @Sendable () async -> SourceResult
    /// Start of the latest shared scan, from any page.
    private let sharedScanDate: @MainActor () -> Date?
    private let now: @MainActor () -> Date
    private let executeDisplayedPlan: ExecuteDisplayedPlan
    private let openFileCheckUnavailable: OpenFileCheckUnavailable
    private let scanSelectedRoot: ScanSelectedRoot
    private let buildAuthority: BuildAuthority
    private let announce: Announce
    private let onboardingStore: AdaptiveOnboardingStore

    init(
        loadSource: @escaping @Sendable () async -> SourceResult,
        executeDisplayedPlan: @escaping ExecuteDisplayedPlan = { _, _ in
            .failure(.sessionUnavailable)
        },
        loadSharedSource: (@Sendable () async -> SourceResult)? = nil,
        sharedScanDate: @escaping @MainActor () -> Date? = { nil },
        now: @escaping @MainActor () -> Date = { Date() },
        openFileCheckUnavailable: @escaping OpenFileCheckUnavailable = { false },
        scanSelectedRoot: @escaping ScanSelectedRoot = { _ in nil },
        buildAuthority: @escaping BuildAuthority = { try AdaptiveExperienceProjector().authority(from: $0) },
        environmentModelPrompts: [String] = [],
        onboardingStore: AdaptiveOnboardingStore = AdaptiveOnboardingStore(),
        announce: @escaping Announce = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.loadSource = loadSource
        self.loadSharedSource = loadSharedSource ?? loadSource
        self.sharedScanDate = sharedScanDate
        self.now = now
        self.executeDisplayedPlan = executeDisplayedPlan
        self.openFileCheckUnavailable = openFileCheckUnavailable
        self.scanSelectedRoot = scanSelectedRoot
        self.buildAuthority = buildAuthority
        self.announce = announce
        self.environmentModelPrompts = environmentModelPrompts
        self.onboardingStore = onboardingStore
        showOnboarding = !onboardingStore.hasAcknowledged
        if !onboardingStore.hasAcknowledged {
            sheet = .onboarding
        }
    }

    /// Counted outcome of the last Trash run, while the session still reports one.
    var lastRunSummary: AdaptiveRunSummary? {
        guard let authority = snapshot?.authority, authority.executionState != nil else { return nil }
        return AdaptiveRunSummary(authority.executionOutcomes)
    }

    /// Why the receipts sheet cannot list history, or nil when the list is the whole history.
    var receiptHistoryFailure: AdaptiveSessionFailure? {
        source?.receiptHistoryError.map(AdaptiveSessionFailure.init)
    }

    /// Where items moved this session without a complete receipt sit in the Trash.
    var unrecordedMoveLocations: [String] {
        (source?.unrecordedMoveDestinations ?? []).map {
            AdaptiveTrashLocation.displayPath($0) ?? L("adaptive.receipts.unrecorded.unknown")
        }
    }

    var canRequestApproval: Bool {
        guard let authority = snapshot?.authority,
              authority.planDigestHex != nil,
              authority.planExpiresAtNanoseconds != nil,
              !isPlanExpired else {
            return false
        }
        switch authority.approvalValidity {
        case .invalid(.missingApproval), .validForReview:
            return true
        default:
            return false
        }
    }

    /// The displayed plan outlived its 15-minute lifetime; only a refresh builds one that can be approved.
    var isPlanExpired: Bool {
        guard let authority = snapshot?.authority else { return false }
        return Self.isPlanExpired(
            validity: authority.approvalValidity,
            expiresAtNanoseconds: authority.planExpiresAtNanoseconds,
            now: now()
        )
    }

    nonisolated static func isPlanExpired(validity: ApprovalValidity, expiresAtNanoseconds: Int64?, now: Date) -> Bool {
        if validity == .invalid(.expired) { return true }
        guard let expires = expiresAtNanoseconds else { return false }
        return Int64(now.timeIntervalSince1970 * 1_000_000_000) >= expires
    }

    func dispatch(_ intent: AdaptiveSafeIntent) {
        switch intent {
        case .refresh:
            refresh()
        case .cancel:
            if isExecuting {
                stopRun()
            } else {
                cancelRefresh()
            }
        case .permissionHelp:
            sheet = .permissionHelp
        case .focus(let opaqueID):
            focusedID = opaqueID
        case .acknowledgeOnboarding:
            onboardingStore.hasAcknowledged = true
            showOnboarding = false
            if sheet == .onboarding {
                sheet = nil
            }
        case .requestApproveDisplayedPlan:
            guard canRequestApproval, !isExecuting,
                  let digest = snapshot?.authority.planDigestHex else { return }
            pendingApprovalDigestHex = digest
            failure = nil
            showApprovalConfirmation = true
        case .confirmApproveDisplayedPlan:
            let digest = pendingApprovalDigestHex
            dismissApprovalConfirmation()
            guard let digest else { return }
            runDisplayedPlan(approvedDigestHex: digest)
        case .dismissApproveDisplayedPlan:
            dismissApprovalConfirmation()
        case .dismissFailure:
            failure = nil
        }
    }

    /// The page appeared: load evidence only when none is shown, another page scanned since, or
    /// it is older than `staleAfter`. The first load waits until onboarding is acknowledged.
    func pageAppeared() {
        guard !showOnboarding else { return }
        if skipsNextLoad {
            skipsNextLoad = false
            return
        }
        guard !isExecuting, !isRefreshing, isStale else { return }
        refresh(reuseScan: true)
    }

    /// "Learn why" on a Trash notice: the next appearance shows the page as it is, explanation
    /// first, without starting a scan. Refresh still loads whenever the user asks.
    func openWithoutLoading() {
        skipsNextLoad = true
    }

    /// Leaving the page stops a refresh. A Trash run keeps going so it can finish its receipt.
    func pageDisappeared() {
        guard !isExecuting else { return }
        cancelRefresh()
    }

    private var isStale: Bool {
        guard let loadedAt else { return true }
        if let scanned = sharedScanDate(), scanned > loadedAt { return true }
        return now().timeIntervalSince(loadedAt) >= Self.staleAfter
    }

    /// Inventories a directory the user explicitly chose and, if it observed a
    /// store, adds it to the read-only selected-store list (C2). A folder already
    /// added, or one that cannot be read, is not added and the user is told why.
    func addSelectedModelRoot(_ directory: URL) {
        let root = directory.standardizedFileURL
        guard selectedModelRoots.insert(root).inserted else {
            toasts.show(L("adaptive.modelInventory.duplicate"), type: .info)
            return
        }
        Task { [scanSelectedRoot] in
            guard let projection = await scanSelectedRoot(directory) else {
                self.selectedModelRoots.remove(root)
                self.toasts.show(L("adaptive.modelInventory.unreadable"), type: .error)
                return
            }
            self.selectedModelStores.append(projection)
        }
    }

    func setMode(_ mode: PresentationMode) {
        presentationMode = mode
        reproject()
    }

    func presentReview() {
        sheet = .review
    }

    func presentReceipts() {
        sheet = .receipts
    }

    func dismissSheet() {
        if sheet == .onboarding, !onboardingStore.hasAcknowledged {
            return
        }
        dismissApprovalConfirmation()
        sheet = nil
    }

    private func dismissApprovalConfirmation() {
        showApprovalConfirmation = false
        pendingApprovalDigestHex = nil
    }

    /// `reuseScan` shows a shared scan still inside its reuse window; Refresh always scans anew.
    private func refresh(reuseScan: Bool = false) {
        // A refresh would replace the displayed plan mid-run; the run's own result refreshes the view.
        guard !isExecuting else { return }
        dismissApprovalConfirmation()
        refreshIdentity += 1
        let token = refreshIdentity
        refreshTask?.cancel()
        isRefreshing = true
        let load = reuseScan ? loadSharedSource : loadSource
        refreshTask = Task {
            let result = await self.prepare(await load())
            guard token == self.refreshIdentity else { return }
            self.isRefreshing = false
            switch result {
            case let .success(prepared):
                self.apply(prepared)
            case let .failure(failure):
                self.failure = failure
            }
        }
    }

    /// Builds the authority off the main actor: a large home folder yields tens of thousands
    /// of findings, and building their identities here would freeze the window.
    private func prepare(_ result: SourceResult) async -> PreparedResult {
        switch result {
        case let .failure(failure):
            return .failure(failure)
        case let .success(source):
            let authority = await Task.detached(priority: .userInitiated) { [buildAuthority] in
                try buildAuthority(source)
            }.result
            return .success((source, authority, await openFileCheckUnavailable()))
        }
    }

    /// Starts a Trash run for the reviewed plan. Internal for tests; the UI goes through `dispatch`.
    func runDisplayedPlan(approvedDigestHex: String) {
        guard !isExecuting else { return }
        cancelRefresh()
        let cancellation = TrashRunCancellation()
        runCancellation = cancellation
        isStopRequested = false
        isExecuting = true
        announce(L("adaptive.execution.started"))
        Task { [executeDisplayedPlan] in
            let result = await self.prepare(await executeDisplayedPlan(approvedDigestHex, cancellation))
            self.finishRun(result)
        }
    }

    private func stopRun() {
        guard let runCancellation, !isStopRequested else { return }
        runCancellation.cancel()
        isStopRequested = true
    }

    /// Always leaves the executing state, whatever the outcome, so approval is never blocked.
    private func finishRun(_ result: PreparedResult) {
        runCancellation = nil
        isStopRequested = false
        isExecuting = false
        switch result {
        case let .success(prepared):
            apply(prepared)
            announce(AdaptiveRunSummary(prepared.source.executionOutcomes).text)
        case let .failure(failure):
            self.failure = failure
            announce(L(failure.messageKey))
            // The plan on screen is stale; reload so the user reviews the current one.
            if failure.outlivesReload {
                refresh()
            }
        }
    }

    private func cancelRefresh() {
        dismissApprovalConfirmation()
        refreshIdentity += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    private func apply(_ prepared: PreparedSource) {
        source = prepared.source
        loadedAt = now()
        // Keep a plan-changed or incomplete-receipt notice visible over the reload it triggered.
        if failure?.outlivesReload != true {
            failure = prepared.openFilesUnchecked ? .openFileCheckUnavailable : nil
        }
        switch prepared.authority {
        case let .success(authority):
            self.authority = authority
        case .failure:
            authority = nil
            failure = .presentationFailed
        }
        reproject()
        let displayedDigest = snapshot?.authority.planDigestHex
        if showApprovalConfirmation, !canRequestApproval || displayedDigest != pendingApprovalDigestHex {
            dismissApprovalConfirmation()
        }
    }

    /// Cheap: only the presentation keys depend on the mode.
    private func reproject() {
        snapshot = authority.map { AdaptiveExperienceProjector().project($0, mode: presentationMode) }
    }
}

/// Counted outcome of a Trash run, e.g. "Moved 12, skipped 2, failed 0."
/// A stopped item counts as skipped: it stayed where it was.
struct AdaptiveRunSummary: Equatable {
    let moved: Int
    let skipped: Int
    let failed: Int

    init(_ outcomes: [AdaptiveExecutionOutcomeKind]) {
        moved = outcomes.filter { $0 == .moved }.count
        failed = outcomes.filter { if case .failed = $0 { return true } else { return false } }.count
        skipped = outcomes.count - moved - failed
    }

    var text: String {
        LFormat("adaptive.execution.summary", moved, skipped, failed)
    }
}

struct AdaptiveOnboardingStore {
    private let key = "adaptive.experience.onboarding.acknowledged"
    /// Injectable so tests use their own suite instead of the real flag.
    var defaults: UserDefaults = .standard

    var hasAcknowledged: Bool {
        get { defaults.bool(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}
