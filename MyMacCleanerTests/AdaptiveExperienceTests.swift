import Testing
import Foundation
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

    @Test("Only fixed-scope caches resolve as Trash roots")
    func onlyCachesAreTrashEligibleRoots() {
        #expect(AdaptiveTrustSession.trashEligibleRootKinds == [.userLibraryCaches])
    }

    private static let sampleDigestHex = String(repeating: "0a", count: 32)

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
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
    private var observedCancellation = false

    var digests: [String] { lock.withLock { recordedDigests } }
    var loadCount: Int { lock.withLock { loads } }
    var cancellationObserved: Bool { lock.withLock { observedCancellation } }

    func record(digest: String) { lock.withLock { recordedDigests.append(digest) } }
    func recordLoad() { lock.withLock { loads += 1 } }
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

    @Test("Cancellation token starts clear and latches once cancelled")
    func cancellationTokenLatches() {
        let cancellation = TrashRunCancellation()
        #expect(cancellation.isCancelled == false)

        cancellation.cancel()
        cancellation.cancel()

        #expect(cancellation.isCancelled)
    }
}
