import CleanerCore
import CleanerCoreDarwin
import CleanerCoreFoundation
import Foundation

/// Process-lifetime trust session. Presentation never sees approval or Trash types.
actor AdaptiveTrustSession {
    typealias SourceResult = Result<AdaptiveExperienceSource, AdaptiveSessionFailure>

    /// Only fixed-scope caches can ever be Trash-eligible (see `PolicyEvaluator`). Resolving no
    /// other root for a move keeps Downloads, Desktop and Documents out of reach even if policy regressed.
    static let trashEligibleRootKinds: Set<GeneralMacRootKind> = [.userLibraryCaches]

    private struct Identity {
        let launchSession: ReviewPlanLaunchSession
        let versionContext: ReviewPlanVersionContext
    }

    private let liveScan: CleanerCoreLiveScan
    private let memoryObserver: any MemoryObservationPort
    private let permissionProbe: any PermissionProbing
    private let digesting = CryptoKitPlanDigestAdapter()
    /// Nil when the plan context cannot be built; every request then fails with `.sessionUnavailable`.
    private let identity: Identity?
    private let recorder = RecordingReceiptExecution(
        inner: FoundationReceiptExecutionAdapter(
            adapter: FoundationTrashAdapter(resolveRoot: { AdaptiveTrustSession.trashRootURL(for: $0) })
        )
    )
    private var displayedPlan: ReviewPlan?
    private var lastOutcomes: [AdaptiveExecutionOutcomeKind] = []
    private var lastExecutionState: TrashRunState?
    private var history: ReceiptHistoryCoordinator?

    init(
        liveScan: CleanerCoreLiveScan,
        memoryObserver: any MemoryObservationPort = DarwinMemoryObservationAdapter(),
        permissionProbe: any PermissionProbing = POSIXPermissionProbe()
    ) {
        self.liveScan = liveScan
        self.memoryObserver = memoryObserver
        self.permissionProbe = permissionProbe
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

    func makeSource() async -> SourceResult {
        guard let identity else { return .failure(.sessionUnavailable) }
        let collected: AdaptiveScanCollection
        do {
            collected = try await liveScan.collect()
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
            let receipts = await loadReceipts()
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
                    receipts: receipts,
                    memory: memory,
                    capabilities: CapabilityCardProjection().cards(for: collected.evaluations),
                    permissionGaps: PermissionAssessment.permissionGaps(using: permissionProbe),
                    developerInventory: liveScan.developerInventory()
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
            let collected: AdaptiveScanCollection
            do {
                collected = revalidationRoots.isEmpty
                    ? try await liveScan.collect()
                    : try await liveScan.collect(roots: revalidationRoots)
            } catch {
                return refusedRun(.scanFailed)
            }
            guard !cancellation.isCancelled else { return await stoppedBeforeRun() }
            let fresh = plan.targets.map {
                FreshTargetEvidence.observing(target: $0, in: collected.generalMacFindings)
            }
            guard let history = historyCoordinator() else {
                return refusedRun(.receiptHistoryUnavailable)
            }
            let intent: ReceiptIntent
            do {
                intent = try makeIntent(plan: plan, now: now)
            } catch {
                return refusedRun(.receiptHistoryUnavailable)
            }
            recorder.beginRun()
            switch await history.run(
                intent: intent,
                operations: operations,
                freshEvidence: fresh,
                isCancelled: { cancellation.isCancelled }
            ) {
            case .failure:
                lastOutcomes = recorder.outcomes
                lastExecutionState = .partial
            case let .success(reconciled):
                lastOutcomes = recorder.outcomes
                lastExecutionState = runState(reconciled.aggregate)
            }
            return await makeSource()
        }
    }

    /// No item was moved: clear stale outcomes and report why.
    private func refusedRun(_ failure: AdaptiveSessionFailure) -> SourceResult {
        lastOutcomes = []
        lastExecutionState = nil
        return .failure(failure)
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

    private func historyCoordinator() -> ReceiptHistoryCoordinator? {
        if let history {
            return history
        }
        let fileManager = FileManager.default
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let receipts = support
            .appendingPathComponent("MyMacCleaner", isDirectory: true)
            .appendingPathComponent("Receipts", isDirectory: true)
        do {
            try fileManager.createDirectory(at: receipts, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let coordinator = ReceiptHistoryCoordinator(
            store: AppSupportReceiptStore(fileManager: fileManager),
            lease: DarwinReceiptLease(lockFile: receipts.appendingPathComponent("history.lock")),
            clock: ReceiptClock(now: { wallNow() }),
            execute: recorder
        )
        history = coordinator
        return coordinator
    }

    private func loadReceipts() async -> [RedactedReceiptSummary] {
        guard let history = historyCoordinator() else { return [] }
        switch await history.listRedacted() {
        case let .success(summaries):
            return summaries
        case .failure:
            return []
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

/// Wraps the Trash adapter and records each item's outcome for display.
/// `revalidateAndMove` is called from the receipt coordinator, so recorded state is lock-protected.
private final class RecordingReceiptExecution: ReceiptExecutionConsuming, @unchecked Sendable {
    private let inner: FoundationReceiptExecutionAdapter
    private let lock = NSLock()
    private var recorded: [AdaptiveExecutionOutcomeKind] = []

    init(inner: FoundationReceiptExecutionAdapter) {
        self.inner = inner
    }

    var outcomes: [AdaptiveExecutionOutcomeKind] {
        lock.withLock { recorded }
    }

    func beginRun() {
        lock.withLock { recorded = [] }
    }

    func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        let outcome = inner.revalidateAndMove(operation, fresh: fresh)
        let kind: AdaptiveExecutionOutcomeKind
        switch outcome {
        case .moved:
            kind = .moved
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
