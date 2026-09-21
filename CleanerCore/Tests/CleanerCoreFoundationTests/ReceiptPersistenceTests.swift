import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Receipt Store Adapter Tests")
struct ReceiptStoreAdapterTests {
    @Test
    func publishesIntentUnderFixedChildrenWithStrictModes() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let store = fixture.store()
        let intent = try persistenceIntent()

        #expect(await store.persistIntent(intent).isSuccess)

        let receipts = fixture.support
            .appendingPathComponent("MyMacCleaner", isDirectory: true)
            .appendingPathComponent("Receipts", isDirectory: true)
        let record = receipts.appendingPathComponent(intent.id.value, isDirectory: true)
        let intentFile = record.appendingPathComponent("intent.json")
        #expect(posixMode(receipts) == 0o700)
        #expect(posixMode(record) == 0o700)
        #expect(posixMode(intentFile) == 0o600)
        #expect(FileManager.default.fileExists(atPath: intentFile.path))
    }

    @Test
    func symlinkRootFailsClosed() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let linked = fixture.support.appendingPathComponent("linked-support")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: fixture.support)
        let store = AppSupportReceiptStore(
            fileManager: FileManager(),
            locator: ApplicationSupportLocator { _ in linked }
        )
        let receipts = linked
            .appendingPathComponent("MyMacCleaner")
            .appendingPathComponent("Receipts")
        try FileManager.default.createDirectory(at: receipts.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: receipts, withDestinationURL: fixture.support)
        #expect(await store.persistIntent(try persistenceIntent()).error == .rootInvalid)
    }

    @Test
    func fullfsyncFaultDoesNotPublishAndSecondLeaseIsBusy() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        var publisher = DarwinReceiptPublisher.native
        publisher.publish = { _, _, _ in .failure(.fullfsyncFailed) }
        let store = fixture.store(publisher: publisher)
        #expect(await store.persistIntent(try persistenceIntent()).error == .fullfsyncFailed)

        let receipts = fixture.support
            .appendingPathComponent("MyMacCleaner")
            .appendingPathComponent("Receipts")
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        let lock = receipts.appendingPathComponent("lock")
        let first = DarwinReceiptLease(lockFile: lock)
        let second = DarwinReceiptLease(lockFile: lock)
        let held = LockedBox(false)
        async let contender: Result<String, ReceiptPersistenceError> = first.withExclusiveAccess {
            held.value = true
            while held.value {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            return .success("first")
        }
        while !held.value {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(await second.withExclusiveAccess { .success("second") } == .failure(.historyBusy))
        held.value = false
        #expect(await contender == .success("first"))
    }

    @Test
    func roundTripMovedDestinationStaysPrivateOnLoad() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let store = fixture.store()
        let intent = try persistenceIntent()
        let item = try ReceiptItemID("item-a")
        #expect(await store.persistIntent(intent).isSuccess)
        #expect(
            await store.persistTransition(
                receipt: intent.id,
                .started(itemID: item, at: .init(unixNanoseconds: 2))
            ).isSuccess
        )
        #expect(
            await store.persistTransition(
                receipt: intent.id,
                .moved(
                    itemID: item,
                    at: .init(unixNanoseconds: 3),
                    destination: PrivateRecoveryDestination(token: "file:///private/tmp/.Trash/cache.bin")
                )
            ).isSuccess
        )
        let loaded = try await store.loadAll().get()
        let record = try #require(loaded.first)
        guard case let .durable(_, transitions) = record else {
            Issue.record("expected durable record")
            return
        }
        #expect(transitions.last == .moved(
            itemID: item,
            at: .init(unixNanoseconds: 3),
            destination: PrivateRecoveryDestination(token: "file:///private/tmp/.Trash/cache.bin")
        ))
        let display = ReceiptDisplayProjection.make(
            from: try ReceiptReducer.reduce(intent: intent, transitions: transitions).get()
        )
        #expect(!display.tokens.joined().contains("file:///private/tmp/.Trash/cache.bin"))
        #expect(!display.tokens.joined().contains("cache.bin"))
    }
}

@Suite("Receipt Coordinator Tests")
struct ReceiptCoordinatorTests {
    @Test
    func durableStartedHappensBeforeTheSoleExecutionCall() async throws {
        let scripted = ScriptedPersistence()
        let plan = try persistencePlan()
        let coordinator = ReceiptHistoryCoordinator(
            store: scripted,
            lease: scripted,
            clock: ReceiptClock { .init(unixNanoseconds: 5) },
            execute: scripted
        )
        let result = await coordinator.run(
            intent: try persistenceIntent(),
            operations: try ApprovedTrashOperationFactory().makeOperations(
                plan: plan,
                approval: persistenceApproval(plan),
                current: persistenceContext(plan)
            ).get(),
            freshEvidence: [nil],
            isCancelled: { false }
        )
        #expect(result.isSuccess)
        #expect(scripted.events == ["lease", "intent", "started", "execute", "terminal", "unlock"])
        #expect(scripted.calls == 1)
    }

    @Test
    func preCallFaultsYieldZeroExecutionCalls() async throws {
        let intentFail = ScriptedPersistence()
        intentFail.failIntent = true
        _ = await run(intentFail)
        #expect(intentFail.calls == 0)

        let startedFail = ScriptedPersistence()
        startedFail.failStarted = true
        _ = await run(startedFail)
        #expect(startedFail.calls == 0)

        let busy = ScriptedPersistence()
        busy.busy = true
        #expect(await run(busy).error == .historyBusy)
        #expect(busy.calls == 0)
    }

    @Test
    func terminalPublishFailureLeavesStartedEvidenceWithoutReplay() async throws {
        let scripted = ScriptedPersistence()
        scripted.failTerminal = true
        let outcome = await run(scripted)
        #expect(outcome.error == .writeFailed)
        #expect(scripted.calls == 1)
        let loaded = try await scripted.loadAll().get()
        guard case let .durable(intent, transitions) = loaded.first else {
            Issue.record("expected durable started")
            return
        }
        let reconciled = ReceiptReconciliation().reconcile(
            .durable(intent: intent, transitions: transitions),
            observedAt: .init(unixNanoseconds: 9)
        )
        #expect(reconciled.aggregate == .needsAttention)
        #expect(reconciled.executionCalls == 0)
        #expect(scripted.calls == 1)
    }

    private func run(_ scripted: ScriptedPersistence) async -> Result<ReconciledReceipt, ReceiptPersistenceError> {
        let plan = try! persistencePlan()
        let coordinator = ReceiptHistoryCoordinator(
            store: scripted,
            lease: scripted,
            clock: ReceiptClock { .init(unixNanoseconds: 5) },
            execute: scripted
        )
        return await coordinator.run(
            intent: try! persistenceIntent(),
            operations: try! ApprovedTrashOperationFactory().makeOperations(
                plan: plan,
                approval: persistenceApproval(plan),
                current: persistenceContext(plan)
            ).get(),
            freshEvidence: [nil],
            isCancelled: { false }
        )
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

final class ScriptedPersistence: ReceiptStorePort, ReceiptLeasePort, ReceiptExecutionConsuming, @unchecked Sendable {
    var events: [String] = []
    var calls = 0
    var failIntent = false
    var failStarted = false
    var failTerminal = false
    var busy = false
    var seeded: [LoadedReceiptRecord] = []
    var deleted: [ReceiptID] = []
    private var intent: ReceiptIntent?
    private var transitions: [ReceiptItemTransition] = []

    func persistIntent(_ intent: ReceiptIntent) async -> Result<Void, ReceiptPersistenceError> {
        events.append("intent")
        if failIntent { return .failure(.writeFailed) }
        self.intent = intent
        return .success(())
    }

    func persistTransition(
        receipt _: ReceiptID,
        _ transition: ReceiptItemTransition
    ) async -> Result<Void, ReceiptPersistenceError> {
        switch transition {
        case .started:
            events.append("started")
            if failStarted { return .failure(.writeFailed) }
        default:
            events.append("terminal")
            if failTerminal { return .failure(.writeFailed) }
        }
        transitions.append(transition)
        return .success(())
    }

    func loadAll() async -> Result<[LoadedReceiptRecord], ReceiptPersistenceError> {
        if !seeded.isEmpty { return .success(seeded) }
        guard let intent else { return .success([]) }
        return .success([.durable(intent: intent, transitions: transitions)])
    }

    func deleteReceipt(_ id: ReceiptID) async -> Result<Void, ReceiptPersistenceError> {
        deleted.append(id)
        return .success(())
    }

    func recoverDeletingTombstones() async -> Result<Void, ReceiptPersistenceError> {
        .success(())
    }

    func withExclusiveAccess<T: Sendable>(
        _ work: @Sendable () async -> Result<T, ReceiptPersistenceError>
    ) async -> Result<T, ReceiptPersistenceError> {
        if busy { return .failure(.historyBusy) }
        events.append("lease")
        let result = await work()
        events.append("unlock")
        return result
    }

    func revalidateAndMove(
        _: MoveToTrash,
        fresh _: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        events.append("execute")
        calls += 1
        return .moved(destination: PrivateRecoveryDestination(token: "scripted"))
    }
}

struct SupportFixture {
    let support: URL

    init() throws {
        support = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmc-receipts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func store(publisher: DarwinReceiptPublisher = .native) -> AppSupportReceiptStore {
        AppSupportReceiptStore(
            fileManager: FileManager(),
            locator: ApplicationSupportLocator { _ in support },
            publisher: publisher
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: support)
    }
}

private func posixMode(_ url: URL) -> Int? {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs?[.posixPermissions] as? NSNumber)?.intValue
}

func persistenceIntent() throws -> ReceiptIntent {
    let item = try ReceiptItemID("item-a")
    return try ReceiptIntent(
        id: ReceiptID("receipt-1"),
        schemaVersion: .v1,
        planDigest: PlanDigest(bytes: Array(repeating: 3, count: 32)),
        versionReferences: ReceiptVersionReferences(
            appPlanVersion: "5.0.0",
            policyVersion: "policy-1",
            detectorCatalogVersion: "catalog-1",
            encodingVersion: 1,
            schemaVersion: .v1
        ),
        createdAt: .init(unixNanoseconds: 1),
        orderedItemIDs: [item],
        estimates: [item: try ReceiptEstimateEvidence(logicalBytes: 1, allocatedBytes: 1, conservativeReclaimableBytes: 1)]
    )
}

func persistencePlan() throws -> ReviewPlan {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: .userLibraryCaches)
    let observation = try FileObservation(
        rootID: root.id,
        locator: .init(rootID: root.id, components: ["com.apple.iconservices.store", "cache.bin"]),
        resourceIdentity: .observed(.init(device: 7, node: 801)),
        sizes: .init(logicalBytes: .observed(4_096), allocatedBytes: .observed(4_096)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: .regularFile,
        volume: .observed(try .init("receipt-volume")),
        linkCount: .observed(1),
        boundaries: .init(
            symlink: .observed(false), alias: .observed(false), package: .observed(false),
            mount: .observed(false), protectedRoot: .observed(false),
            homeBoundary: .observed(false), externalVolume: .observed(false)
        )
    )
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
                appPlanVersion: "5.0.0",
                policyVersion: "policy-1",
                detectorCatalogVersion: catalog.version.value,
                encodingVersion: 1
            ),
            launchSession: try .init("launch-a"),
            createdAt: .init(unixNanoseconds: 1_000_000_000)
        ),
        digesting: PersistenceDigesting()
    )
}

func persistenceApproval(_ plan: ReviewPlan) -> ApprovalAttestation {
    .init(
        approvedDigest: plan.digest,
        approvedAt: .init(unixNanoseconds: 1_000_000_001),
        launchSession: plan.launchSession
    )
}

func persistenceContext(_ plan: ReviewPlan) -> ApprovalContext {
    .init(
        launchSession: plan.launchSession,
        now: .init(unixNanoseconds: plan.expiresAt.unixNanoseconds - 1),
        versionContext: plan.versionContext,
        displayedDigest: plan.digest,
        currentTargets: plan.targets
    )
}

private struct PersistenceDigesting: PlanDigesting {
    func digest(canonicalBytes _: [UInt8]) throws -> PlanDigest {
        try .init(bytes: Array(repeating: 3, count: 32))
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var error: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
