import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

/// Drives `AdaptiveTrustSession` against a scripted receipt store, lease and Trash execution,
/// so no real history folder is opened and nothing is moved.
@Suite("Receipt History Session Tests")
struct ReceiptHistorySessionTests {
    private static let trashToken = "file:///Users/test/.Trash/cache.bin"

    @Test("A busy history refuses the run before any item moves")
    func busyHistoryRefusesTheRun() async throws {
        let execution = MovingExecution(token: Self.trashToken)
        let session = Self.session(store: ScriptedReceiptStore(), busy: true, execution: execution)

        let failure = await Self.run(session)

        #expect(failure == .historyBusy)
        #expect(execution.calls == 0)
        #expect(await session.lastExecutionState == nil)
        #expect(await session.unrecordedMoves.isEmpty)
    }

    @Test("Too many unresolved receipts refuse the run as review required")
    func reviewRequiredRefusesTheRun() async throws {
        let execution = MovingExecution(token: Self.trashToken)
        let session = Self.session(store: ScriptedReceiptStore(recoverError: .reviewRequired), execution: execution)

        #expect(await Self.run(session) == .reviewRequired)
        #expect(execution.calls == 0)
    }

    @Test("A history write failure before any move refuses the run as unavailable")
    func writeFailureBeforeAnyMoveIsUnavailable() async throws {
        let execution = MovingExecution(token: Self.trashToken)
        let session = Self.session(store: ScriptedReceiptStore(recoverError: .writeFailed), execution: execution)

        #expect(await Self.run(session) == .receiptHistoryUnavailable)
        #expect(execution.calls == 0)
        #expect(await session.lastExecutionState == nil)
    }

    @Test("A journal failure after a move reports an incomplete receipt and keeps where the item went")
    func journalFailureAfterAMoveKeepsTheTrashDestination() async throws {
        let execution = MovingExecution(token: Self.trashToken)
        let session = Self.session(store: ScriptedReceiptStore(failTerminalWrite: true), execution: execution)

        #expect(await Self.run(session) == .receiptIncomplete)
        #expect(execution.calls == 1)
        #expect(await session.lastExecutionState == .partial)
        #expect(await session.lastOutcomes == [.moved])
        #expect(await session.unrecordedMoves == [PrivateRecoveryDestination(token: Self.trashToken)])

        // Kept for the whole session, not just until the next run.
        #expect(await Self.run(session) == .receiptIncomplete)
        #expect(await session.unrecordedMoves.count == 2)
    }

    @Test("A fully recorded run reports no failure and keeps nothing unrecorded")
    func recordedRunHasNoFailure() async throws {
        let execution = MovingExecution(token: Self.trashToken)
        let session = Self.session(store: ScriptedReceiptStore(), execution: execution)

        #expect(await Self.run(session) == nil)
        #expect(await session.lastExecutionState == .complete)
        #expect(await session.unrecordedMoves.isEmpty)
    }

    @Test("A history that cannot be listed reports why instead of an empty list")
    func listFailureIsReportedNotEmpty() async {
        let busy = await Self.session(store: ScriptedReceiptStore(), busy: true).loadReceipts()
        #expect(busy.summaries.isEmpty)
        #expect(busy.error == .historyBusy)

        let unreadable = await Self.session(store: ScriptedReceiptStore(recoverError: .rootInvalid)).loadReceipts()
        #expect(unreadable.error == .rootInvalid)

        let missing = await AdaptiveTrustSession(
            evidence: Self.unusedEvidence,
            makeHistory: { _ in .failure(.leaseFailed) }
        ).loadReceipts()
        #expect(missing.error == .leaseFailed)

        let readable = await Self.session(store: ScriptedReceiptStore()).loadReceipts()
        #expect(readable.error == nil)
    }

    @Test("Each persistence error maps to one user-facing failure and one closed log code")
    func persistenceErrorsMapToFailuresAndCodes() {
        #expect(AdaptiveSessionFailure(.historyBusy) == .historyBusy)
        #expect(AdaptiveSessionFailure(.reviewRequired) == .reviewRequired)
        for error in [ReceiptPersistenceError.rootInvalid, .leaseFailed, .readbackFailed, .writeFailed] {
            #expect(AdaptiveSessionFailure(error) == .receiptHistoryUnavailable)
        }

        #expect(AdaptiveTrustSession.diagnosticEvent(for: .historyBusy) == .receiptHistoryBusy)
        #expect(AdaptiveTrustSession.diagnosticEvent(for: .reviewRequired) == .receiptHistoryReviewRequired)
        #expect(AdaptiveTrustSession.diagnosticEvent(for: .writeFailed) == .receiptHistoryWriteFailed)
        #expect(AdaptiveTrustSession.diagnosticEvent(for: .fullfsyncFailed) == .receiptHistoryWriteFailed)
        #expect(AdaptiveTrustSession.diagnosticEvent(for: .rootInvalid) == .receiptHistoryUnavailable)
        #expect(AdaptiveTrustSession.diagnosticEvent(for: .leaseFailed) == .receiptHistoryUnavailable)

        for failure in [AdaptiveSessionFailure.historyBusy, .reviewRequired, .receiptIncomplete] {
            #expect(L(failure.messageKey) != failure.messageKey, "missing string for \(failure)")
        }
        for failure in [AdaptiveSessionFailure.historyBusy, .receiptHistoryUnavailable] {
            #expect(L(failure.receiptsUnavailableKey) != failure.receiptsUnavailableKey)
        }
    }

    @Test("The receipts sheet says why history is unavailable and where unrecorded items went")
    @MainActor
    func receiptsSheetShowsUnavailableHistoryAndUnrecordedMoves() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let moved = PrivateRecoveryDestination(
            token: home.appendingPathComponent(".Trash/cache 2.bin").absoluteString
        )
        let unknown = PrivateRecoveryDestination(token: "")
        let source = Self.source(historyError: .historyBusy, unrecorded: [moved, unknown])
        let viewModel = AdaptiveExperienceViewModel(loadSource: { .success(source) })

        viewModel.dispatch(.refresh)
        let loaded = await Self.waitUntil { viewModel.source != nil }

        #expect(loaded)
        #expect(viewModel.receiptHistoryFailure == .historyBusy)
        #expect(viewModel.unrecordedMoveLocations == [
            "~/.Trash/cache 2.bin",
            L("adaptive.receipts.unrecorded.unknown"),
        ])
    }

    @Test("An incomplete receipt reloads the evidence and keeps its notice on screen")
    @MainActor
    func incompleteReceiptReloadsAndKeepsTheNotice() async {
        let loads = LoadCounter()
        let viewModel = AdaptiveExperienceViewModel(
            loadSource: {
                loads.increment()
                return .success(Self.source())
            },
            executeDisplayedPlan: { _, _ in .failure(.receiptIncomplete) }
        )

        viewModel.runDisplayedPlan(approvedDigestHex: String(repeating: "0a", count: 32))
        let reloaded = await Self.waitUntil { loads.count == 1 && !viewModel.isRefreshing && !viewModel.isExecuting }

        #expect(reloaded)
        #expect(viewModel.failure == .receiptIncomplete)
    }

    @Test("A Trash run re-validates on its own fresh scan, never on the shared display scan")
    func trashRunCollectsFreshEvidence() async throws {
        let displayed = try await ScanFixtures.collection([try Self.cacheObservation()])
        let calls = EvidenceCalls()
        let execution = MovingExecution(token: Self.trashToken)
        let session = Self.session(
            store: ScriptedReceiptStore(),
            execution: execution,
            evidence: AdaptiveEvidenceSources(
                display: { reuse in
                    calls.recordDisplay(reuse: reuse)
                    return ScanFixtures.scan(displayed, takenAt: Date())
                },
                revalidate: { roots in
                    calls.recordRevalidate(roots: roots)
                    return displayed
                },
                developerInventory: { [] },
                modelInventory: { [] }
            )
        )

        let source = try await session.makeSource(reuseScan: true).get()
        let approved = try #require(try AdaptiveExperienceProjector().authority(from: source).planDigestHex)
        let result = await session.executeDisplayedPlan(
            approvedDigestHex: approved,
            cancellation: TrashRunCancellation()
        )

        #expect((try? result.get()) != nil)
        #expect(execution.calls == 1)
        // One fresh scan of the plan's root; the shared scan only fed the display before and after.
        #expect(calls.revalidated == [[.userLibraryCaches]])
        #expect(calls.displayed == [true, false])
    }

    // MARK: - Fixtures

    /// Evidence for tests that never build a source.
    private static let unusedEvidence = AdaptiveEvidenceSources(
        display: { _ in throw CancellationError() },
        revalidate: { _ in throw CancellationError() },
        developerInventory: { [] },
        modelInventory: { [] }
    )

    private static func session(
        store: ScriptedReceiptStore,
        busy: Bool = false,
        execution: MovingExecution = MovingExecution(token: trashToken),
        evidence: AdaptiveEvidenceSources = unusedEvidence
    ) -> AdaptiveTrustSession {
        AdaptiveTrustSession(
            evidence: evidence,
            execution: execution,
            makeHistory: { execute in
                .success(
                    ReceiptHistoryCoordinator(
                        store: store,
                        lease: ScriptedLease(busy: busy),
                        clock: ReceiptClock { .init(unixNanoseconds: 1_000_000_002) },
                        execute: execute
                    )
                )
            }
        )
    }

    private static func run(_ session: AdaptiveTrustSession) async -> AdaptiveSessionFailure? {
        do {
            let plan = try cachePlan()
            let operations = try ApprovedTrashOperationFactory().makeOperations(
                plan: plan,
                approval: ApprovalAttestation(
                    approvedDigest: plan.digest,
                    approvedAt: .init(unixNanoseconds: 1_000_000_001),
                    launchSession: plan.launchSession
                ),
                current: ApprovalContext(
                    launchSession: plan.launchSession,
                    now: .init(unixNanoseconds: plan.expiresAt.unixNanoseconds - 1),
                    versionContext: plan.versionContext,
                    displayedDigest: plan.digest,
                    currentTargets: plan.targets
                )
            ).get()
            return await session.recordRun(
                plan: plan,
                operations: operations,
                freshEvidence: plan.targets.map { _ in nil },
                now: .init(unixNanoseconds: 1_000_000_001),
                cancellation: TrashRunCancellation()
            )
        } catch {
            Issue.record("plan fixture failed: \(error)")
            return .sessionUnavailable
        }
    }

    /// One policy-eligible file inside the named cache scope, as a reviewed plan.
    private static func cachePlan() throws -> ReviewPlan {
        let catalog = GeneralMacScopeCatalog.current
        let observation = try cacheObservation()
        let finding = try #require(try GeneralMacEvidenceDetector(scope: .userLibraryCaches)
            .makeFinding(
                from: observation,
                request: catalog.scanRequest(for: [.userLibraryCaches]),
                clockReading: .init(
                    observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
                    wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
                )
            )
            .get())
        let candidate = try #require(PolicyEvaluator().evaluate(finding).candidate)
        return try ReviewPlan.build(
            draft: .init(
                selectedCandidates: [candidate],
                versionContext: try .init(
                    appPlanVersion: AdaptivePlanVersions.appPlan,
                    policyVersion: AdaptivePlanVersions.policy,
                    detectorCatalogVersion: catalog.version.value,
                    encodingVersion: AdaptivePlanVersions.encoding
                ),
                launchSession: try .init("session-tests"),
                createdAt: .init(unixNanoseconds: 1_000_000_000)
            ),
            digesting: FixedDigesting()
        )
    }

    /// A regular file in the named cache scope, last modified at the epoch, so policy finds it eligible.
    private static func cacheObservation() throws -> FileObservation {
        let root = try GeneralMacScopeCatalog.current.declaredRoot(for: .userLibraryCaches)
        return try FileObservation(
            rootID: root.id,
            locator: .init(rootID: root.id, components: [GeneralMacScopeProof.namedCacheComponent, "cache.bin"]),
            resourceIdentity: .observed(.init(device: 7, node: 401)),
            sizes: .init(logicalBytes: .observed(4_096), allocatedBytes: .observed(4_096)),
            modification: .observed(.init(unixNanoseconds: 1)),
            fileKind: .regularFile,
            volume: .observed(try .init("session-volume")),
            linkCount: .observed(1),
            boundaries: .init(
                symlink: .observed(false), alias: .observed(false), package: .observed(false),
                mount: .observed(false), protectedRoot: .observed(false),
                homeBoundary: .observed(false), externalVolume: .observed(false)
            )
        )
    }

    private static func source(
        historyError: ReceiptPersistenceError? = nil,
        unrecorded: [PrivateRecoveryDestination] = []
    ) -> AdaptiveExperienceSource {
        AdaptiveExperienceSource(
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
            developerInventory: [],
            receiptHistoryError: historyError,
            unrecordedMoveDestinations: unrecorded
        )
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

/// Scripted receipt store: fails the tombstone sweep with `recoverError`, or every terminal
/// (post-move) journal write when `failTerminalWrite` is set.
private struct ScriptedReceiptStore: ReceiptStorePort {
    var recoverError: ReceiptPersistenceError?
    var failTerminalWrite = false

    func persistIntent(_: ReceiptIntent) async -> Result<Void, ReceiptPersistenceError> {
        .success(())
    }

    func persistTransition(
        receipt _: ReceiptID,
        _ transition: ReceiptItemTransition
    ) async -> Result<Void, ReceiptPersistenceError> {
        if case .started = transition { return .success(()) }
        return failTerminalWrite ? .failure(.writeFailed) : .success(())
    }

    func loadAll() async -> Result<[LoadedReceiptRecord], ReceiptPersistenceError> {
        .success([])
    }

    func deleteReceipt(_: ReceiptID) async -> Result<Void, ReceiptPersistenceError> {
        .success(())
    }

    func recoverDeletingTombstones() async -> Result<Void, ReceiptPersistenceError> {
        recoverError.map { .failure($0) } ?? .success(())
    }
}

private struct ScriptedLease: ReceiptLeasePort {
    let busy: Bool

    func withExclusiveAccess<T: Sendable>(
        _ work: @Sendable () async -> Result<T, ReceiptPersistenceError>
    ) async -> Result<T, ReceiptPersistenceError> {
        busy ? .failure(.historyBusy) : await work()
    }
}

/// Stands in for the Trash adapter: reports every item as moved to `token`, moving nothing.
private final class MovingExecution: ReceiptExecutionConsuming, @unchecked Sendable {
    private let lock = NSLock()
    private let token: String
    private var count = 0

    init(token: String) {
        self.token = token
    }

    var calls: Int {
        lock.withLock { count }
    }

    func revalidateAndMove(
        _: MoveToTrash,
        fresh _: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        lock.withLock { count += 1 }
        return .moved(destination: PrivateRecoveryDestination(token: token))
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}

private struct FixedDigesting: PlanDigesting {
    func digest(canonicalBytes _: [UInt8]) throws -> PlanDigest {
        try PlanDigest(bytes: Array(repeating: 5, count: 32))
    }
}

/// Records which evidence source each trust-session step used.
private final class EvidenceCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var displayReuse: [Bool] = []
    private var revalidatedRoots: [[GeneralMacRootKind]] = []

    var displayed: [Bool] {
        lock.withLock { displayReuse }
    }

    var revalidated: [[GeneralMacRootKind]] {
        lock.withLock { revalidatedRoots }
    }

    func recordDisplay(reuse: Bool) {
        lock.withLock { displayReuse.append(reuse) }
    }

    func recordRevalidate(roots: [GeneralMacRootKind]) {
        lock.withLock { revalidatedRoots.append(roots) }
    }
}
