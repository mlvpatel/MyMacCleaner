import Combine
import Foundation
import CleanerCore

enum AdaptiveSafeIntent: Equatable {
    case refresh
    case cancel
    case permissionHelp
    case focus(opaqueID: String)
    case acknowledgeOnboarding
    case revealReceipt(receiptID: String, itemID: String)
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

    private var refreshIdentity: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    /// Digest of the plan on screen when approval was requested; only this plan may run.
    private var pendingApprovalDigestHex: String?
    private var runCancellation: TrashRunCancellation?
    private let loadSource: @Sendable () async -> SourceResult
    private let executeDisplayedPlan: ExecuteDisplayedPlan
    private let onboardingStore: AdaptiveOnboardingStore

    init(
        loadSource: @escaping @Sendable () async -> SourceResult,
        executeDisplayedPlan: @escaping ExecuteDisplayedPlan = { _, _ in
            .failure(.sessionUnavailable)
        },
        onboardingStore: AdaptiveOnboardingStore = AdaptiveOnboardingStore()
    ) {
        self.loadSource = loadSource
        self.executeDisplayedPlan = executeDisplayedPlan
        self.onboardingStore = onboardingStore
        showOnboarding = !onboardingStore.hasAcknowledged
        if !onboardingStore.hasAcknowledged {
            sheet = .onboarding
        }
    }

    var canRequestApproval: Bool {
        guard let authority = snapshot?.authority,
              authority.planDigestHex != nil,
              let expires = authority.planExpiresAtNanoseconds else {
            return false
        }
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        guard now < expires else { return false }
        switch authority.approvalValidity {
        case .invalid(.missingApproval), .validForReview:
            return true
        default:
            return false
        }
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
        case .revealReceipt:
            sheet = .receipts
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

    private func refresh() {
        // A refresh would replace the displayed plan mid-run; the run's own result refreshes the view.
        guard !isExecuting else { return }
        dismissApprovalConfirmation()
        refreshIdentity += 1
        let token = refreshIdentity
        refreshTask?.cancel()
        isRefreshing = true
        refreshTask = Task { [loadSource] in
            let result = await loadSource()
            await MainActor.run {
                guard token == self.refreshIdentity else { return }
                self.isRefreshing = false
                switch result {
                case let .success(source):
                    self.apply(source)
                case let .failure(failure):
                    self.failure = failure
                }
            }
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
        Task { [executeDisplayedPlan] in
            let result = await executeDisplayedPlan(approvedDigestHex, cancellation)
            await MainActor.run {
                self.finishRun(result)
            }
        }
    }

    private func stopRun() {
        guard let runCancellation, !isStopRequested else { return }
        runCancellation.cancel()
        isStopRequested = true
    }

    /// Always leaves the executing state, whatever the outcome, so approval is never blocked.
    private func finishRun(_ result: SourceResult) {
        runCancellation = nil
        isStopRequested = false
        isExecuting = false
        switch result {
        case let .success(source):
            apply(source)
        case let .failure(failure):
            self.failure = failure
            // The plan on screen is stale; reload so the user reviews the current one.
            if failure == .planChanged {
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

    private func apply(_ source: AdaptiveExperienceSource) {
        self.source = source
        // Keep a plan-changed notice visible over the reload it triggered.
        if failure != .planChanged {
            failure = nil
        }
        reproject()
        let displayedDigest = snapshot?.authority.planDigestHex
        if showApprovalConfirmation, !canRequestApproval || displayedDigest != pendingApprovalDigestHex {
            dismissApprovalConfirmation()
        }
    }

    private func reproject() {
        guard let source else { return }
        do {
            snapshot = try AdaptiveExperienceProjector().project(source, mode: presentationMode)
        } catch {
            snapshot = nil
            failure = .presentationFailed
        }
    }
}

struct AdaptiveOnboardingStore {
    private let key = "adaptive.experience.onboarding.acknowledged"

    var hasAcknowledged: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
