import CleanerCore
import CleanerCoreDarwin
import CleanerCoreFoundation
import Foundation
import SafetyContract

/// Where the trust session's evidence comes from. Display reads the shared scan; a Trash run
/// never does: it re-validates every item on its own fresh scan of the plan's roots.
struct AdaptiveEvidenceSources: Sendable {
    /// Evidence to show. `reuse` allows a shared scan still inside its reuse window.
    let display: @Sendable (_ reuse: Bool) async throws -> SharedScan
    /// A fresh scan of these roots for a Trash run. Never the shared scan.
    let revalidate: @Sendable (_ roots: [GeneralMacRootKind]) async throws -> AdaptiveScanCollection
    let developerInventory: @Sendable () -> [AdaptiveDeveloperInventoryFact]
    let modelInventory: @Sendable () async -> [ModelStoreProjection]

    static func live(liveScan: CleanerCoreLiveScan, store: SharedScanStore) -> AdaptiveEvidenceSources {
        AdaptiveEvidenceSources(
            display: { reuse in reuse ? try await store.current() : try await store.refresh() },
            revalidate: { roots in try await liveScan.collect(roots: roots) },
            developerInventory: { liveScan.developerInventory() },
            modelInventory: { await liveScan.modelInventory() }
        )
    }
}

/// Process-lifetime trust session. Presentation never sees approval or Trash types.
actor AdaptiveTrustSession {
    typealias SourceResult = Result<AdaptiveExperienceSource, AdaptiveSessionFailure>
    /// Opens receipt history around the session's recording Trash execution.
    typealias HistoryFactory = @Sendable (any ReceiptExecutionConsuming)
        -> Result<ReceiptHistoryCoordinator, ReceiptPersistenceError>

    /// Only fixed-scope caches can ever be Trash-eligible (see `PolicyEvaluator`). Resolving no
    /// other root for a move keeps Downloads, Desktop and Documents out of reach even if policy regressed.
    static let trashEligibleRootKinds: Set<GeneralMacRootKind> = [.userLibraryCaches]

    private struct Identity {
        let launchSession: ReviewPlanLaunchSession
        let versionContext: ReviewPlanVersionContext
    }

    private let evidence: AdaptiveEvidenceSources
    private let memoryObserver: any MemoryObservationPort
    private let permissionProbe: any PermissionProbing
    private let digesting = CryptoKitPlanDigestAdapter()
    /// Nil when the plan context cannot be built; every request then fails with `.sessionUnavailable`.
    private let identity: Identity?
    private let recorder: RecordingReceiptExecution
    private let makeHistory: HistoryFactory
    private var displayedPlan: ReviewPlan?
    private(set) var lastOutcomes: [AdaptiveExecutionOutcomeKind] = []
    private(set) var lastExecutionState: TrashRunState?
    /// Trash destinations of items moved this session whose receipt could not be completed,
    /// so the user can still find them. Kept until the app quits.
    private(set) var unrecordedMoves: [PrivateRecoveryDestination] = []
    private var history: ReceiptHistoryCoordinator?
    /// True when the last evidence load could not list open files, so nothing was eligible.
    private(set) var isOpenFileCheckUnavailable = false

    /// `execution` and `makeHistory` exist for tests; production uses the sole Trash adapter
    /// and the Application Support receipt history.
    init(
        evidence: AdaptiveEvidenceSources,
        memoryObserver: any MemoryObservationPort = DarwinMemoryObservationAdapter(),
        permissionProbe: any PermissionProbing = POSIXPermissionProbe(),
        execution: (any ReceiptExecutionConsuming)? = nil,
        makeHistory: HistoryFactory? = nil
    ) {
        self.evidence = evidence
        self.memoryObserver = memoryObserver
        self.permissionProbe = permissionProbe
        recorder = RecordingReceiptExecution(
            inner: execution ?? FoundationReceiptExecutionAdapter(
                adapter: FoundationTrashAdapter(resolveRoot: { AdaptiveTrustSession.trashRootURL(for: $0) })
            )
        )
        self.makeHistory = makeHistory ?? { execute in
            ReceiptHistoryCoordinator.live(
                fileManager: FileManager.default,
                clock: ReceiptClock(now: { wallNow() }),
                execute: execute
            )
        }
        identity = Self.makeIdentity()
    }

    private static func makeIdentity() -> Identity? {
        do {
            return Identity(
                launchSession: try ReviewPlanLaunchSession(UUID().uuidString),
                versionContext: try ReviewPlanVersionContext(
                    appPlanVersion: AdaptivePlanVersions.appPlan,
                    policyVersion: AdaptivePlanVersions.policy,
                    detectorCatalogVersion: GeneralMacScopeCatalog.current.version.value,
                    encodingVersion: AdaptivePlanVersions.encoding
                )
            )
        } catch {
            return nil
        }
    }

    private static func trashRootURL(for id: DeclaredRootID) -> URL? {
        guard let kind = try? GeneralMacScopeCatalog.current.rootKind(for: id),
              trashEligibleRootKinds.contains(kind) else {
            return nil
        }
        return AppAdaptiveRoots.url(for: kind)
    }

    /// Defense in depth behind policy: only a regular file under the one named cache scope in a
    /// Trash-eligible root gets fresh evidence, so even a policy regression is skipped, never moved.
    static func isWithinTrashScope(rootID: DeclaredRootID, components: [String], fileKind: FileKind) -> Bool {
        guard let kind = try? GeneralMacScopeCatalog.current.rootKind(for: rootID) else { return false }
        return trashEligibleRootKinds.contains(kind)
            && components.first == GeneralMacScopeProof.namedCacheComponent
            && fileKind == .regularFile
    }

    /// A history failure before any item was recorded (busy, review required, intent write failed)
    /// means nothing ran; returns nil so the caller reports a refusal instead of a partial run.
    static func runStateAfterFailure(recordedOutcomes: [AdaptiveExecutionOutcomeKind]) -> TrashRunState? {
        recordedOutcomes.isEmpty ? nil : .partial
    }

    /// Distinct root kinds the given targets live in, in first-seen order. Execute-time
    /// revalidation scans only these roots so a large unrelated root cannot consume the scan
    /// budget and truncate a still-present target into a false `skippedStale(.missing)`.
    static func revalidationRootKinds(forRootIDs ids: [DeclaredRootID]) -> [GeneralMacRootKind] {
        let catalog = GeneralMacScopeCatalog.current
        var seen: Set<GeneralMacRootKind> = []
        var ordered: [GeneralMacRootKind] = []
        for id in ids {
            guard let kind = try? catalog.rootKind(for: id) else { continue }
            if seen.insert(kind).inserted { ordered.append(kind) }
        }
        return ordered
    }

    /// Builds the source from the shared display scan. `reuseScan` shows a scan another screen
    /// ran within the reuse window; otherwise a new scan runs (and updates every screen).
    func makeSource(reuseScan: Bool = false) async -> SourceResult {
        guard let identity else { return .failure(.sessionUnavailable) }
        let collected: AdaptiveScanCollection
        do {
            let scan = try await evidence.display(reuseScan)
            collected = scan.collection
            isOpenFileCheckUnavailable = !scan.openFilesChecked
        } catch {
            return .failure(.scanFailed)
        }
        do {
            let now = wallNow()
            displayedPlan = try DisplayedPlanFactory.makePlan(
                evaluations: collected.evaluations,
                versionContext: identity.versionContext,
                launchSession: identity.launchSession,
                now: now,
                digesting: digesting
            )
            let validity = displayedValidity(at: now)
            let receiptHistory = await loadReceipts()
            let memory = await memoryObserver.observe(cancellation: NeverCancelMemoryObservation())
            return .success(
                AdaptiveExperienceSource(
                    scanState: collected.scanState,
                    findings: collected.findings,
                    evaluations: collected.evaluations,
                    reviewPlan: displayedPlan,
                    approvalValidity: validity,
                    executionState: lastExecutionState,
                    executionOutcomes: lastOutcomes,
                    receipts: receiptHistory.summaries,
                    memory: memory,
                    capabilities: CapabilityCardProjection().cards(for: collected.evaluations),
                    permissionGaps: PermissionAssessment.permissionGaps(using: permissionProbe),
                    developerInventory: evidence.developerInventory(),
                    modelInventory: await evidence.modelInventory(),
                    receiptHistoryError: receiptHistory.error,
                    unrecordedMoveDestinations: unrecordedMoves
                )
            )
        } catch {
            return .failure(.presentationFailed)
        }
    }

    /// Runs the plan only if `approvedDigestHex` still matches the displayed plan.
    /// A refresh that replaced the plan after review makes core validation reject the approval.
    func executeDisplayedPlan(
        approvedDigestHex: String,
        cancellation: TrashRunCancellation
    ) async -> SourceResult {
        guard let identity else { return .failure(.sessionUnavailable) }
        guard let plan = displayedPlan,
              let approvedDigest = AdaptiveApprovalBinding.digest(fromHex: approvedDigestHex) else {
            return refusedRun(.planChanged)
        }
        let now = wallNow()
        let approval = ApprovalAttestation(
            approvedDigest: approvedDigest,
            approvedAt: now,
            launchSession: plan.launchSession
        )
        let current = ApprovalContext(
            launchSession: identity.launchSession,
            now: now,
            versionContext: identity.versionContext,
            displayedDigest: plan.digest,
            currentTargets: plan.targets
        )
        switch ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: approval,
            current: current
        ) {
        case .failure:
            return refusedRun(.planChanged)
        case let .success(operations):
            guard !cancellation.isCancelled else { return await stoppedBeforeRun() }
            let revalidationRoots = Self.revalidationRootKinds(
                forRootIDs: plan.targets.map(\.declaredRootID)
            )
            // Fresh evidence only: the shared display scan is never reused to move a file.
            let collected: AdaptiveScanCollection
            do {
                collected = try await evidence.revalidate(
                    revalidationRoots.isEmpty ? CleanerCoreLiveScan.allRootKinds : revalidationRoots
                )
            } catch {
                return refusedRun(.scanFailed)
            }
            guard !cancellation.isCancelled else { return await stoppedBeforeRun() }
            let fresh = plan.targets.map { target in
                Self.isWithinTrashScope(
                    rootID: target.declaredRootID,
                    components: target.locatorComponents,
                    fileKind: target.fileKind
                ) ? FreshTargetEvidence.observing(target: target, eligibleIn: collected.evaluations) : nil
            }
            if let failure = await recordRun(
                plan: plan,
                operations: operations,
                freshEvidence: fresh,
                now: now,
                cancellation: cancellation
            ) {
                return .failure(failure)
            }
            return await makeSource()
        }
    }

    /// Runs approved operations under receipt history. Returns why the run was refused, or
    /// `.receiptIncomplete` when items ran but their receipt could not be saved; nil when every
    /// recorded item has a durable receipt. Internal for tests.
    func recordRun(
        plan: ReviewPlan,
        operations: [MoveToTrash],
        freshEvidence: [FreshTargetEvidence?],
        now: WallClockInstant,
        cancellation: TrashRunCancellation
    ) async -> AdaptiveSessionFailure? {
        let history: ReceiptHistoryCoordinator
        switch historyCoordinator() {
        case let .failure(error):
            return refusedByHistory(error)
        case let .success(coordinator):
            history = coordinator
        }
        let intent: ReceiptIntent
        do {
            intent = try makeIntent(plan: plan, now: now)
        } catch {
            return refusedByHistory(.encodeFailed)
        }
        recorder.beginRun()
        switch await history.run(
            intent: intent,
            operations: operations,
            freshEvidence: freshEvidence,
            isCancelled: { cancellation.isCancelled }
        ) {
        case let .failure(error):
            guard let state = Self.runStateAfterFailure(recordedOutcomes: recorder.outcomes) else {
                return refusedByHistory(error)
            }
            lastOutcomes = recorder.outcomes
            lastExecutionState = state
            let moved = recorder.movedDestinations
            unrecordedMoves += moved
            SafetyDiagnosticLogger.emitFailure(
                RedactingDiagnostic.record(
                    event: .receiptJournalIncomplete,
                    sensitiveClasses: [.receipt, .error] + Array(repeating: .path, count: moved.count)
                )
            )
            return .receiptIncomplete
        case let .success(reconciled):
            lastOutcomes = recorder.outcomes
            lastExecutionState = runState(reconciled.aggregate)
            SafetyDiagnosticLogger.emit(
                RedactingDiagnostic.record(event: .receiptRunRecorded, sensitiveClasses: [.receipt])
            )
            return nil
        }
    }

    /// Closed log code for a receipt-history error. Internal for tests.
    static func diagnosticEvent(for error: ReceiptPersistenceError) -> DiagnosticEventCode {
        switch error {
        case .historyBusy:
            return .receiptHistoryBusy
        case .reviewRequired:
            return .receiptHistoryReviewRequired
        case .encodeFailed, .openFailed, .writeFailed, .fullfsyncFailed, .renameFailed, .directorySyncFailed:
            return .receiptHistoryWriteFailed
        case .rootInvalid, .readbackFailed, .leaseFailed, .unknownReceipt, .deletionRefused, .invalidIdentifier:
            return .receiptHistoryUnavailable
        }
    }

    /// Logs a receipt-history error as a count-only code: no path, name or raw error leaves the app.
    /// Busy and review-required are expected states; the rest are failures.
    private static func logHistoryError(_ error: ReceiptPersistenceError) {
        let record = RedactingDiagnostic.record(
            event: diagnosticEvent(for: error),
            sensitiveClasses: [.receipt, .error]
        )
        if error == .historyBusy || error == .reviewRequired {
            SafetyDiagnosticLogger.emit(record)
        } else {
            SafetyDiagnosticLogger.emitFailure(record)
        }
    }

    /// No item was moved: clear stale outcomes and report why.
    private func refusedRun(_ failure: AdaptiveSessionFailure) -> SourceResult {
        lastOutcomes = []
        lastExecutionState = nil
        return .failure(failure)
    }

    /// Receipt history refused the run before any item moved.
    private func refusedByHistory(_ error: ReceiptPersistenceError) -> AdaptiveSessionFailure {
        Self.logHistoryError(error)
        lastOutcomes = []
        lastExecutionState = nil
        return AdaptiveSessionFailure(error)
    }

    /// The user stopped the run before the first move: show current evidence, no outcomes.
    private func stoppedBeforeRun() async -> SourceResult {
        lastOutcomes = []
        lastExecutionState = nil
        return await makeSource()
    }

    private func displayedValidity(at now: WallClockInstant) -> ApprovalValidity {
        guard let plan = displayedPlan, let identity else {
            return .invalid(.missingApproval)
        }
        return ApprovalValidity.evaluate(
            approval: nil,
            plan: plan,
            current: ApprovalContext(
                launchSession: identity.launchSession,
                now: now,
                versionContext: identity.versionContext,
                displayedDigest: plan.digest,
                currentTargets: plan.targets
            )
        )
    }

    private func makeIntent(plan: ReviewPlan, now: WallClockInstant) throws -> ReceiptIntent {
        var ordered: [ReceiptItemID] = []
        var estimates: [ReceiptItemID: ReceiptEstimateEvidence] = [:]
        for target in plan.targets {
            let itemID = try ReceiptItemID(target.stableIdentity.hex)
            ordered.append(itemID)
            estimates[itemID] = try ReceiptEstimateEvidence(
                logicalBytes: target.logicalBytes,
                allocatedBytes: target.allocatedBytes,
                conservativeReclaimableBytes: target.conservativeReclaimableBytes
            )
        }
        let versions = try ReceiptVersionReferences(
            appPlanVersion: plan.versionContext.appPlanVersion,
            policyVersion: plan.versionContext.policyVersion,
            detectorCatalogVersion: plan.versionContext.detectorCatalogVersion,
            encodingVersion: plan.versionContext.encodingVersion,
            schemaVersion: .v1
        )
        return try ReceiptIntent(
            id: ReceiptID(UUID().uuidString),
            schemaVersion: .v1,
            planDigest: plan.digest,
            versionReferences: versions,
            createdAt: now,
            orderedItemIDs: ordered,
            estimates: estimates
        )
    }

    private func historyCoordinator() -> Result<ReceiptHistoryCoordinator, ReceiptPersistenceError> {
        if let history {
            return .success(history)
        }
        let opened = makeHistory(recorder)
        if case let .success(coordinator) = opened {
            history = coordinator
        }
        return opened
    }

    /// Receipt summaries, or why history could not be read (never a silent empty list).
    /// Internal for tests.
    func loadReceipts() async -> (summaries: [RedactedReceiptSummary], error: ReceiptPersistenceError?) {
        let listed: Result<[RedactedReceiptSummary], ReceiptPersistenceError>
        switch historyCoordinator() {
        case let .failure(error):
            listed = .failure(error)
        case let .success(history):
            listed = await history.listRedacted()
        }
        switch listed {
        case let .success(summaries):
            return (summaries, nil)
        case let .failure(error):
            Self.logHistoryError(error)
            return ([], error)
        }
    }

    private func runState(_ aggregate: ReceiptAggregateState) -> TrashRunState {
        switch aggregate {
        case .complete:
            return .complete
        case .interrupted:
            return .interrupted
        default:
            return .partial
        }
    }
}

private func wallNow() -> WallClockInstant {
    WallClockInstant(unixNanoseconds: Int64(Date().timeIntervalSince1970 * 1_000_000_000))
}

/// The source snapshot's memory sample always runs to completion; refresh/cancel apply to the scan
/// and the Trash run, not this read-only observation.
private struct NeverCancelMemoryObservation: MemoryObservationCancellation {
    func isCancellationRequested() async -> Bool { false }
}

/// Wraps the Trash adapter and records each item's outcome, and where moved items went, for display.
/// `revalidateAndMove` is called from the receipt coordinator, so recorded state is lock-protected.
private final class RecordingReceiptExecution: ReceiptExecutionConsuming, @unchecked Sendable {
    private let inner: any ReceiptExecutionConsuming
    private let lock = NSLock()
    private var recorded: [AdaptiveExecutionOutcomeKind] = []
    private var destinations: [PrivateRecoveryDestination] = []

    init(inner: any ReceiptExecutionConsuming) {
        self.inner = inner
    }

    var outcomes: [AdaptiveExecutionOutcomeKind] {
        lock.withLock { recorded }
    }

    var movedDestinations: [PrivateRecoveryDestination] {
        lock.withLock { destinations }
    }

    func beginRun() {
        lock.withLock {
            recorded = []
            destinations = []
        }
    }

    func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        let outcome = inner.revalidateAndMove(operation, fresh: fresh)
        let kind: AdaptiveExecutionOutcomeKind
        switch outcome {
        case let .moved(destination):
            kind = .moved
            lock.withLock { destinations.append(destination) }
        case let .skippedStale(reason):
            kind = .skippedStale(reason)
        case let .failed(failure):
            kind = .failed(failure)
        case .cancelled:
            kind = .cancelled
        }
        lock.withLock { recorded.append(kind) }
        return outcome
    }
}
