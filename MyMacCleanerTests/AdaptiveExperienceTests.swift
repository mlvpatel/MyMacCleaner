import AppKit
import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

@Suite("Adaptive Experience Bridge Tests")
struct AdaptiveExperienceBridgeTests {
    @Test("Requesting approval without a displayed plan is a no-op")
    @MainActor
    func requestingApprovalWithoutAPlanIsANoOp() {
        let viewModel = AdaptiveExperienceViewModel {
            .failure(.scanFailed)
        }
        #expect(viewModel.canRequestApproval == false)
        viewModel.dispatch(.requestApproveDisplayedPlan)
        #expect(viewModel.showApprovalConfirmation == false)
    }

    @Test("Confirming without a requested approval never executes")
    @MainActor
    func confirmWithoutRequestedApprovalDoesNotExecute() async {
        let calls = ExecutionProbe()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .failure(.scanFailed) },
            executeDisplayedPlan: { digest, _ in
                calls.record(digest: digest)
                return .failure(.scanFailed)
            }
        )

        viewModel.dispatch(.confirmApproveDisplayedPlan)

        // A run sets isExecuting synchronously before any work starts, so this proves none began.
        #expect(calls.digests.isEmpty)
        #expect(viewModel.isExecuting == false)
        #expect(viewModel.showApprovalConfirmation == false)
    }

    @Test("A run receives the approved digest and always clears the executing state")
    @MainActor
    func runPassesApprovedDigestAndClearsExecuting() async {
        let calls = ExecutionProbe()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .failure(.scanFailed) },
            executeDisplayedPlan: { digest, _ in
                calls.record(digest: digest)
                return .failure(.scanFailed)
            }
        )

        viewModel.runDisplayedPlan(approvedDigestHex: Self.sampleDigestHex)
        #expect(viewModel.isExecuting)
        let finished = await waitUntil { !viewModel.isExecuting }

        #expect(finished)
        #expect(calls.digests == [Self.sampleDigestHex])
    }

    @Test("Refresh is ignored during a run and cancel stops the run")
    @MainActor
    func refreshIsIgnoredAndCancelStopsRun() async {
        let calls = ExecutionProbe()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: {
                calls.recordLoad()
                return .failure(.scanFailed)
            },
            executeDisplayedPlan: { _, cancellation in
                for _ in 0..<500 {
                    if cancellation.isCancelled {
                        calls.recordCancellationObserved()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                return .failure(.scanFailed)
            }
        )

        viewModel.runDisplayedPlan(approvedDigestHex: Self.sampleDigestHex)
        viewModel.dispatch(.refresh)
        #expect(viewModel.isRefreshing == false)

        viewModel.dispatch(.cancel)
        #expect(viewModel.isStopRequested)
        let finished = await waitUntil { !viewModel.isExecuting }

        #expect(finished)
        #expect(calls.cancellationObserved)
        #expect(calls.loadCount == 0)
        #expect(viewModel.isStopRequested == false)
    }

    @Test("A failed evidence load is shown and can be dismissed")
    @MainActor
    func failedLoadIsShownAndDismissable() async {
        let viewModel = AdaptiveExperienceViewModel(loadSource: { .failure(.scanFailed) })

        viewModel.dispatch(.refresh)
        let finished = await waitUntil { !viewModel.isRefreshing }

        #expect(finished)
        #expect(viewModel.failure == .scanFailed)
        viewModel.dispatch(.dismissFailure)
        #expect(viewModel.failure == nil)
    }

    @Test("A refused run explains the plan changed and reloads evidence")
    @MainActor
    func refusedRunShowsPlanChangedAndReloads() async {
        let calls = ExecutionProbe()
        let reloadGate = AsyncGate()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: {
                calls.recordLoad()
                await reloadGate.wait()
                return .failure(.scanFailed)
            },
            executeDisplayedPlan: { _, _ in .failure(.planChanged) }
        )

        viewModel.runDisplayedPlan(approvedDigestHex: Self.sampleDigestHex)
        let runFinished = await waitUntil { !viewModel.isExecuting }

        #expect(runFinished)
        #expect(viewModel.failure == .planChanged)
        #expect(viewModel.isRefreshing)
        await reloadGate.open()
        let reloadFinished = await waitUntil { !viewModel.isRefreshing }
        #expect(reloadFinished)
        #expect(calls.loadCount == 1)
    }

    @Test("An unchecked open-file listing explains why nothing can move this time")
    @MainActor
    func uncheckedOpenFilesAreExplained() async {
        let unchecked = AdaptiveExperienceViewModel(
            loadSource: { .success(Self.emptySource) },
            openFileCheckUnavailable: { true }
        )
        let checked = AdaptiveExperienceViewModel(loadSource: { .success(Self.emptySource) })

        unchecked.dispatch(.refresh)
        checked.dispatch(.refresh)
        let loaded = await waitUntil { unchecked.snapshot != nil && checked.snapshot != nil }

        #expect(loaded)
        #expect(unchecked.failure == .openFileCheckUnavailable)
        #expect(checked.failure == nil)
    }

    @Test("Switching modes reuses the projected authority instead of rebuilding it")
    @MainActor
    func switchingModesDoesNotRebuildTheAuthority() async {
        let builds = ExecutionProbe()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .success(Self.emptySource) },
            buildAuthority: { source in
                builds.recordBuild()
                return try AdaptiveExperienceProjector().authority(from: source)
            }
        )

        viewModel.dispatch(.refresh)
        let loaded = await waitUntil { viewModel.snapshot != nil }
        viewModel.setMode(.guided)
        viewModel.setMode(.technical)

        #expect(loaded)
        #expect(builds.buildCount == 1)
        #expect(viewModel.snapshot?.mode == .technical)
    }

    @Test("A run announces its start and a counted summary, which stays on screen")
    @MainActor
    func runAnnouncesStartAndCountedSummary() async {
        let outcomes: [AdaptiveExecutionOutcomeKind] = [.moved, .moved, .cancelled, .failed(.nativeMoveFailed)]
        let finished = Self.source(executionState: .partial, outcomes: outcomes)
        let announcements = AnnouncementProbe()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .failure(.scanFailed) },
            executeDisplayedPlan: { _, _ in .success(finished) },
            announce: { announcements.messages.append($0) }
        )

        viewModel.runDisplayedPlan(approvedDigestHex: Self.sampleDigestHex)
        #expect(announcements.messages == [L("adaptive.execution.started")])
        let done = await waitUntil { !viewModel.isExecuting }

        let summary = AdaptiveRunSummary(outcomes)
        #expect(done)
        #expect((summary.moved, summary.skipped, summary.failed) == (2, 1, 1))
        #expect(announcements.messages == [L("adaptive.execution.started"), summary.text])
        #expect(viewModel.lastRunSummary == summary)
    }

    @Test("A refused run announces why")
    @MainActor
    func refusedRunAnnouncesTheFailure() async {
        let announcements = AnnouncementProbe()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .failure(.scanFailed) },
            executeDisplayedPlan: { _, _ in .failure(.receiptHistoryUnavailable) },
            announce: { announcements.messages.append($0) }
        )

        viewModel.runDisplayedPlan(approvedDigestHex: Self.sampleDigestHex)
        let done = await waitUntil { !viewModel.isExecuting }

        #expect(done)
        #expect(announcements.messages == [
            L("adaptive.execution.started"),
            L(AdaptiveSessionFailure.receiptHistoryUnavailable.messageKey),
        ])
        #expect(viewModel.lastRunSummary == nil)
    }

    @Test("The permission-help sheet can be closed")
    @MainActor
    func permissionHelpSheetCanBeClosed() {
        let viewModel = AdaptiveExperienceViewModel(loadSource: { .failure(.scanFailed) })

        viewModel.dispatch(.permissionHelp)
        #expect(viewModel.sheet == .permissionHelp)
        viewModel.dismissSheet()

        #expect(viewModel.sheet == nil)
    }

    @Test("Only fixed-scope caches resolve as Trash roots")
    func onlyCachesAreTrashEligibleRoots() {
        #expect(AdaptiveTrustSession.trashEligibleRootKinds == [.userLibraryCaches])
    }

    @Test("Only regular files inside the named cache scope can reach the Trash")
    func trashScopeBackstopAdmitsOnlyTheNamedCacheScope() throws {
        let catalog = GeneralMacScopeCatalog.current
        let caches = try catalog.declaredRoot(for: .userLibraryCaches).id
        let downloads = try catalog.declaredRoot(for: .userDownloads).id
        let scope = GeneralMacScopeProof.namedCacheComponent

        #expect(AdaptiveTrustSession.isWithinTrashScope(rootID: caches, components: [scope, "a.bin"], fileKind: .regularFile))
        #expect(!AdaptiveTrustSession.isWithinTrashScope(rootID: caches, components: ["com.other.cache", "a.bin"], fileKind: .regularFile))
        #expect(!AdaptiveTrustSession.isWithinTrashScope(rootID: caches, components: [scope, "sub"], fileKind: .directory))
        #expect(!AdaptiveTrustSession.isWithinTrashScope(rootID: downloads, components: [scope, "a.bin"], fileKind: .regularFile))
    }

    @Test("Long evidence lists render a bounded prefix and summarize the rest")
    func longEvidenceListsAreBounded() {
        let many = (0..<120).map { "id-\($0)" }

        let (shown, hidden) = AdaptiveListLimit.split(many)

        #expect(shown == Array(many.prefix(AdaptiveListLimit.rows)))
        #expect(hidden == 120 - AdaptiveListLimit.rows)
        #expect(AdaptiveListLimit.split(["a", "b"]) == (["a", "b"], 0))
    }

    @Test("The Trash confirmation names the count, size and items")
    func trashConfirmationNamesCountSizeAndItems() {
        let size = AdaptivePlanText.bytes(.observed(12_400_000))

        #expect(AdaptivePlanText.approvalTitle(itemCount: 3, total: .observed(12_400_000))
            == "Move 3 items (\(size)) to the Trash?")
        #expect(AdaptivePlanText.approvalTitle(itemCount: 1, total: .observed(12_400_000))
            == "Move 1 item (\(size)) to the Trash?")

        let names = (1...12).map { "cache-\($0).bin" }
        let lines = AdaptivePlanText.approvalMessage(names: names).components(separatedBy: "\n")
        #expect(Array(lines.prefix(AdaptivePlanText.confirmationNameLimit)) == Array(names.prefix(10)))
        #expect(lines[AdaptivePlanText.confirmationNameLimit] == "+2 more items")
        #expect(lines.last == L("adaptive.approval.message"))
    }

    @Test("A failed run that recorded no item is refused, not shown as partial")
    func failedRunWithoutRecordedOutcomesIsRefused() {
        #expect(AdaptiveTrustSession.runStateAfterFailure(recordedOutcomes: []) == nil)
        #expect(AdaptiveTrustSession.runStateAfterFailure(recordedOutcomes: [.moved]) == .partial)
    }

    @Test("Revalidation scan is scoped to the plan targets' distinct root kinds")
    func revalidationRootsScopeToPlanTargets() throws {
        let catalog = GeneralMacScopeCatalog.current
        let caches = try catalog.declaredRoot(for: .userLibraryCaches).id
        let logs = try catalog.declaredRoot(for: .userLibraryLogs).id

        // Duplicate cache targets collapse to a single caches root — not the full six-root scan,
        // so an unrelated large root cannot truncate a still-present cache target.
        #expect(
            AdaptiveTrustSession.revalidationRootKinds(forRootIDs: [caches, caches]) == [.userLibraryCaches]
        )
        // Distinct roots are preserved in first-seen order and de-duplicated.
        #expect(
            AdaptiveTrustSession.revalidationRootKinds(forRootIDs: [caches, logs, caches])
                == [.userLibraryCaches, .userLibraryLogs]
        )
        // No targets yields no scoped roots, so the caller falls back to the full scan.
        #expect(AdaptiveTrustSession.revalidationRootKinds(forRootIDs: []).isEmpty)
    }

    @Test("Acknowledging onboarding only records the acknowledgement")
    @MainActor
    func acknowledgingOnboardingHasNoSideEffects() {
        let key = "adaptive.experience.onboarding.acknowledged"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        let calls = ExecutionProbe()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: {
                calls.recordLoad()
                return .failure(.scanFailed)
            },
            executeDisplayedPlan: { digest, _ in
                calls.record(digest: digest)
                return .failure(.scanFailed)
            }
        )
        #expect(viewModel.showOnboarding)

        viewModel.dispatch(.acknowledgeOnboarding)

        #expect(viewModel.showOnboarding == false)
        #expect(viewModel.sheet == nil)
        #expect(viewModel.isRefreshing == false)
        #expect(calls.loadCount == 0)
        #expect(calls.digests.isEmpty)
        #expect(AdaptiveOnboardingStore().hasAcknowledged)
    }

    @Test("A plan counts as expired from the end of its lifetime, or when the session says so")
    func planExpiryFollowsTheClockAndTheSession() {
        let expires: Int64 = 2_000_000_000_000_000_000
        let before = Date(timeIntervalSince1970: 1_999_999_999)
        let after = Date(timeIntervalSince1970: 2_000_000_001)
        let open = ApprovalValidity.invalid(.missingApproval)

        #expect(!AdaptiveExperienceViewModel.isPlanExpired(validity: open, expiresAtNanoseconds: expires, now: before))
        #expect(AdaptiveExperienceViewModel.isPlanExpired(validity: open, expiresAtNanoseconds: expires, now: after))
        #expect(AdaptiveExperienceViewModel.isPlanExpired(validity: .invalid(.expired), expiresAtNanoseconds: expires, now: before))
        #expect(!AdaptiveExperienceViewModel.isPlanExpired(validity: open, expiresAtNanoseconds: nil, now: after))
    }

    @Test("Adding the same model folder twice, or one that can't be read, says why")
    @MainActor
    func modelFolderFeedback() async {
        let calls = ExecutionProbe()
        let gate = AsyncGate()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .failure(.scanFailed) },
            scanSelectedRoot: { _ in
                calls.recordLoad()
                await gate.wait()
                return nil
            }
        )
        let folder = URL(fileURLWithPath: "/tmp/models", isDirectory: true)

        viewModel.addSelectedModelRoot(folder)
        viewModel.addSelectedModelRoot(URL(fileURLWithPath: "/tmp/models/../models", isDirectory: true))

        #expect(viewModel.toasts.current?.message == L("adaptive.modelInventory.duplicate"))
        await gate.open()
        let reported = await waitUntil { viewModel.toasts.current?.message == L("adaptive.modelInventory.unreadable") }
        #expect(reported)
        #expect(calls.loadCount == 1)
        #expect(viewModel.selectedModelStores.isEmpty)

        // A folder that could not be read is not remembered, so it can be tried again.
        viewModel.addSelectedModelRoot(folder)
        let retried = await waitUntil { calls.loadCount == 2 }
        #expect(retried)
    }

    @Test("Quit goes ahead at once when no Trash run is moving items")
    @MainActor
    func quitWithoutARunIsImmediate() {
        var asked = false
        let viewModel = AdaptiveExperienceViewModel(loadSource: { .failure(.scanFailed) })
        let quitGuard = TrashRunQuitGuard(
            viewModel: viewModel,
            confirmStop: { asked = true; return true },
            reply: { _ in Issue.record("no deferred reply expected") }
        )

        #expect(quitGuard.shouldTerminate() == .terminateNow)
        #expect(!asked)
    }

    @Test("Declining to stop keeps the run moving and cancels the quit")
    @MainActor
    func declinedQuitKeepsTheRun() async {
        let gate = AsyncGate()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .failure(.scanFailed) },
            executeDisplayedPlan: { _, _ in await gate.wait(); return .failure(.scanFailed) }
        )
        let quitGuard = TrashRunQuitGuard(
            viewModel: viewModel,
            confirmStop: { false },
            reply: { _ in Issue.record("no deferred reply expected") }
        )
        viewModel.runDisplayedPlan(approvedDigestHex: Self.sampleDigestHex)

        #expect(quitGuard.shouldTerminate() == .terminateCancel)
        #expect(viewModel.isExecuting)
        #expect(viewModel.isStopRequested == false)
        await gate.open()
        #expect(await waitUntil { !viewModel.isExecuting })
    }

    @Test("A confirmed quit stops the run before the next item and quits only once the run has ended")
    @MainActor
    func confirmedQuitStopsTheRunThenQuits() async {
        let calls = ExecutionProbe()
        var replies: [Bool] = []
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: { .failure(.scanFailed) },
            executeDisplayedPlan: { _, cancellation in
                for _ in 0..<500 {
                    if cancellation.isCancelled {
                        calls.recordCancellationObserved()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                return .failure(.scanFailed)
            }
        )
        var asked = 0
        var runEndedBeforeReply = false
        let quitGuard = TrashRunQuitGuard(
            viewModel: viewModel,
            confirmStop: { asked += 1; return true },
            reply: {
                runEndedBeforeReply = !viewModel.isExecuting
                replies.append($0)
            }
        )
        viewModel.runDisplayedPlan(approvedDigestHex: Self.sampleDigestHex)

        #expect(quitGuard.shouldTerminate() == .terminateLater)
        #expect(viewModel.isStopRequested)
        #expect(replies.isEmpty)
        // A second Quit while the first waits neither asks again nor stacks another reply.
        #expect(quitGuard.shouldTerminate() == .terminateCancel)
        #expect(asked == 1)

        #expect(await waitUntil { replies == [true] })
        #expect(runEndedBeforeReply)
        #expect(calls.cancellationObserved)
    }

    private static let sampleDigestHex = String(repeating: "0a", count: 32)

    private static let emptySource = source()

    private static func source(
        executionState: TrashRunState? = nil,
        outcomes: [AdaptiveExecutionOutcomeKind] = []
    ) -> AdaptiveExperienceSource {
        AdaptiveExperienceSource(
            scanState: .complete,
            findings: [],
            evaluations: [],
            reviewPlan: nil,
            approvalValidity: .invalid(.missingApproval),
            executionState: executionState,
            executionOutcomes: outcomes,
            receipts: [],
            memory: nil,
            capabilities: [],
            permissionGaps: [],
            developerInventory: []
        )
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

@MainActor
private final class AnnouncementProbe {
    var messages: [String] = []
}

/// Suspends callers until the test opens it, replacing timing-based sleeps.
private actor AsyncGate {
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

private final class ExecutionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDigests: [String] = []
    private var loads = 0
    private var builds = 0
    private var observedCancellation = false

    var digests: [String] { lock.withLock { recordedDigests } }
    var loadCount: Int { lock.withLock { loads } }
    var buildCount: Int { lock.withLock { builds } }
    var cancellationObserved: Bool { lock.withLock { observedCancellation } }

    func record(digest: String) { lock.withLock { recordedDigests.append(digest) } }
    func recordLoad() { lock.withLock { loads += 1 } }
    func recordBuild() { lock.withLock { builds += 1 } }
    func recordCancellationObserved() { lock.withLock { observedCancellation = true } }
}

@Suite("Adaptive Execution Control Tests")
struct AdaptiveExecutionControlTests {
    @Test("Digest hex round-trips to the same plan digest bytes")
    func digestHexRoundTrips() throws {
        let bytes = (0..<32).map { UInt8($0 * 7 % 256) }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()

        let digest = try #require(AdaptiveApprovalBinding.digest(fromHex: hex))

        #expect(digest.bytes == bytes)
    }

    @Test("Malformed digest hex is rejected", arguments: [
        "",
        String(repeating: "0", count: 63),
        String(repeating: "0", count: 66),
        String(repeating: "AB", count: 32),
        String(repeating: "zz", count: 32),
    ])
    func malformedDigestHexIsRejected(hex: String) {
        #expect(AdaptiveApprovalBinding.digest(fromHex: hex) == nil)
    }

    @Test("Only the incomplete-receipt failure, whose message points at the receipts, offers to open them")
    func onlyIncompleteReceiptOpensReceipts() {
        let all: [AdaptiveSessionFailure] = [
            .sessionUnavailable, .scanFailed, .presentationFailed, .planChanged, .receiptHistoryUnavailable,
            .historyBusy, .reviewRequired, .receiptIncomplete, .openFileCheckUnavailable,
        ]

        #expect(all.filter(\.opensReceipts) == [.receiptIncomplete])
    }

    @Test("Cancellation token starts clear and latches once cancelled")
    func cancellationTokenLatches() {
        let cancellation = TrashRunCancellation()
        #expect(cancellation.isCancelled == false)

        cancellation.cancel()
        cancellation.cancel()

        #expect(cancellation.isCancelled)
    }
}
