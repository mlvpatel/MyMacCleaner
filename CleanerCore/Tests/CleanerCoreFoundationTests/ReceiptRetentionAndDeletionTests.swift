import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Receipt Retention Tests")
struct ReceiptRetentionTests {
    private let day: Int64 = 86_400_000_000_000
    private var now: WallClockInstant { .init(unixNanoseconds: 200 * day) }

    @Test
    func exactlyNinetyDaysIsKeptAndOneNanosecondOlderIsPruned() throws {
        let kept = try summary(id: "keep-90", createdAt: now.unixNanoseconds - (90 * day), aggregate: .complete)
        let pruned = try summary(id: "prune-90", createdAt: now.unixNanoseconds - (90 * day) - 1, aggregate: .complete)
        let decision = ReceiptRetention.decide(summaries: [kept, pruned], anonymousUnresolved: 0, now: now)
        #expect(decision.pruneIDs == [try ReceiptID("prune-90")])
        #expect(decision.admitNewCleanup)
    }

    @Test
    func fiveHundredTerminalsStayAndTheOldestFiveHundredFirstIsPruned() throws {
        let summaries = try (1...501).map { index in
            try summary(
                id: String(format: "term-%03d", index),
                createdAt: now.unixNanoseconds - 1_000 + Int64(index),
                aggregate: .complete
            )
        }
        let decision = ReceiptRetention.decide(summaries: summaries, anonymousUnresolved: 0, now: now)
        #expect(decision.pruneIDs == [try ReceiptID("term-001")])
        #expect(decision.admitNewCleanup)
    }

    @Test
    func needsAttentionAndCorruptEvidenceAreNeverAutoPruned() throws {
        let unresolved = try summary(id: "needs", createdAt: 1, aggregate: .needsAttention)
        let oldComplete = try summary(id: "old-complete", createdAt: 1, aggregate: .complete)
        let decision = ReceiptRetention.decide(
            summaries: [unresolved, oldComplete],
            anonymousUnresolved: 2,
            now: now
        )
        #expect(decision.pruneIDs == [try ReceiptID("old-complete")])
        #expect(!decision.pruneIDs.contains(try ReceiptID("needs")))
        #expect(decision.unresolvedCount == 3)
    }

    @Test
    func fortyNineUnresolvedAdmitsAndFiftyBlocks() throws {
        let fortyNine = try (1...49).map {
            try summary(id: "u-\($0)", createdAt: Int64($0), aggregate: .needsAttention)
        }
        #expect(ReceiptRetention.decide(summaries: fortyNine, anonymousUnresolved: 0, now: now).admitNewCleanup)
        let fifty = try (1...50).map {
            try summary(id: "u-\($0)", createdAt: Int64($0), aggregate: .needsAttention)
        }
        let blocked = ReceiptRetention.decide(summaries: fifty, anonymousUnresolved: 0, now: now)
        #expect(!blocked.admitNewCleanup)
        #expect(blocked.pruneIDs.isEmpty)
    }

    @Test
    func identicalTimestampsTieBreakByOpaqueID() throws {
        let bravo = try summary(id: "bravo", createdAt: now.unixNanoseconds - 20, aggregate: .complete)
        let alpha = try summary(id: "alpha", createdAt: now.unixNanoseconds - 20, aggregate: .complete)
        let extra = try (1...499).map {
            try summary(id: String(format: "z-%03d", $0), createdAt: now.unixNanoseconds - 10, aggregate: .complete)
        }
        let decision = ReceiptRetention.decide(summaries: [bravo, alpha] + extra, anonymousUnresolved: 0, now: now)
        let expected = try ReceiptID("alpha")
        #expect(decision.pruneIDs.first == expected)
    }

    @Test
    func coordinatorBlocksTheFiftyFirstUnresolvedBeforeIntent() async throws {
        let scripted = ScriptedPersistence()
        scripted.seeded = try (1...50).map { try unresolvedRecord("block-\($0)", createdAt: Int64($0)) }
        let plan = try persistencePlan()
        let coordinator = ReceiptHistoryCoordinator(
            store: scripted,
            lease: scripted,
            clock: ReceiptClock { .init(unixNanoseconds: 5) },
            execute: scripted
        )
        let outcome = await coordinator.run(
            intent: try persistenceIntent(),
            operations: try ApprovedTrashOperationFactory().makeOperations(
                plan: plan,
                approval: persistenceApproval(plan),
                current: persistenceContext(plan)
            ).get(),
            freshEvidence: [nil],
            isCancelled: { false }
        )
        #expect(outcome.error == .reviewRequired)
        #expect(scripted.calls == 0)
        #expect(!scripted.events.contains("intent"))
        #expect(scripted.deleted.isEmpty)
    }

    private func summary(
        id: String,
        createdAt: Int64,
        aggregate: ReceiptAggregateState
    ) throws -> ReceiptHistorySummary {
        ReceiptHistorySummary(
            id: try ReceiptID(id),
            createdAt: .init(unixNanoseconds: createdAt),
            aggregate: aggregate,
            isQuarantined: false,
            itemCount: 1,
            canRevealMovedItem: aggregate == .complete
        )
    }

    private func unresolvedRecord(_ id: String, createdAt: Int64) throws -> LoadedReceiptRecord {
        let item = try ReceiptItemID("item-a")
        let intent = try ReceiptIntent(
            id: ReceiptID(id),
            schemaVersion: .v1,
            planDigest: PlanDigest(bytes: Array(repeating: 3, count: 32)),
            versionReferences: ReceiptVersionReferences(
                appPlanVersion: "5.0.0",
                policyVersion: "policy-1",
                detectorCatalogVersion: "catalog-1",
                encodingVersion: 1,
                schemaVersion: .v1
            ),
            createdAt: .init(unixNanoseconds: createdAt),
            orderedItemIDs: [item],
            estimates: [item: try ReceiptEstimateEvidence(logicalBytes: 1, allocatedBytes: 1, conservativeReclaimableBytes: 1)]
        )
        return .durable(
            intent: intent,
            transitions: [.started(itemID: item, at: .init(unixNanoseconds: createdAt + 1))]
        )
    }
}

@Suite("Receipt History Deletion Tests")
struct ReceiptHistoryDeletionTests {
    @Test
    func opaqueIDDeletionRemovesOnlyTheDirectChildAndSkipsTombstonesOnLoad() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let store = fixture.store()
        let intent = try persistenceIntent()
        #expect(await store.persistIntent(intent).isSuccess)
        let receipts = fixture.support
            .appendingPathComponent("MyMacCleaner")
            .appendingPathComponent("Receipts")
        let record = receipts.appendingPathComponent(intent.id.value)
        #expect(FileManager.default.fileExists(atPath: record.path))
        #expect(await store.deleteReceipt(intent.id).isSuccess)
        #expect(!FileManager.default.fileExists(atPath: record.path))
        #expect(try await store.loadAll().get().isEmpty)
    }

    @Test
    func traversalSymlinkAndDuplicateIDsAreRefusedWithoutEscapingTheRoot() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let store = fixture.store()
        let intent = try persistenceIntent()
        #expect(await store.persistIntent(intent).isSuccess)
        let receipts = fixture.support
            .appendingPathComponent("MyMacCleaner")
            .appendingPathComponent("Receipts")
        let outside = fixture.support.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outside)

        #expect(await store.deleteReceipt(try ReceiptID("..")).error == .deletionRefused)
        #expect(await store.deleteReceipt(try ReceiptID("lock")).error == .deletionRefused)
        #expect(FileManager.default.fileExists(atPath: outside.path))

        let linked = receipts.appendingPathComponent("escape-link")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        #expect(await store.deleteReceipt(try ReceiptID("escape-link")).error == .deletionRefused)
        #expect(FileManager.default.fileExists(atPath: outside.path))

        let coordinator = ReceiptHistoryCoordinator(
            store: store,
            lease: ImmediateLease(),
            clock: ReceiptClock { .init(unixNanoseconds: 9) },
            execute: NeverExecute()
        )
        #expect(await coordinator.deleteReceipts(ids: [intent.id, intent.id]).error == .invalidIdentifier)
    }

    @Test
    func busyLeaseChangesNothingAndRenameFaultLeavesNoRemoveCall() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        var store = fixture.store()
        let intent = try persistenceIntent()
        #expect(await store.persistIntent(intent).isSuccess)
        let removed = DeletionTargetRecorder()
        store.renameReceiptDirectory = { _, _ in .failure(.renameFailed) }
        store.removeReceiptDirectory = { url in
            removed.urls.append(url)
            return .success(())
        }
        #expect(await store.deleteReceipt(intent.id).error == .renameFailed)
        #expect(removed.urls.isEmpty)

        let busy = ScriptedPersistence()
        busy.busy = true
        let coordinator = ReceiptHistoryCoordinator(
            store: busy,
            lease: busy,
            clock: ReceiptClock { .init(unixNanoseconds: 9) },
            execute: busy
        )
        #expect(await coordinator.deleteReceipts(ids: [try ReceiptID("receipt-1")]).error == .historyBusy)
        #expect(busy.deleted.isEmpty)
        #expect(busy.calls == 0)
    }

    @Test
    func interruptedTombstoneIsRemovedOnRecoverAndNeverReturnsToHistory() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let store = fixture.store()
        let intent = try persistenceIntent()
        #expect(await store.persistIntent(intent).isSuccess)
        let receipts = fixture.support
            .appendingPathComponent("MyMacCleaner")
            .appendingPathComponent("Receipts")
        let record = receipts.appendingPathComponent(intent.id.value)
        let tombstone = receipts.appendingPathComponent(".deleting-\(intent.id.value)")
        try FileManager.default.moveItem(at: record, to: tombstone)
        #expect(try await store.loadAll().get().isEmpty)
        #expect(await store.recoverDeletingTombstones().isSuccess)
        #expect(!FileManager.default.fileExists(atPath: tombstone.path))
        #expect(try await store.loadAll().get().isEmpty)
    }
}

private final class DeletionTargetRecorder: @unchecked Sendable {
    var urls: [URL] = []
}

private struct ImmediateLease: ReceiptLeasePort {
    func withExclusiveAccess<T: Sendable>(
        _ work: @Sendable () async -> Result<T, ReceiptPersistenceError>
    ) async -> Result<T, ReceiptPersistenceError> {
        await work()
    }
}

private struct NeverExecute: ReceiptExecutionConsuming {
    func revalidateAndMove(
        _: MoveToTrash,
        fresh _: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        .cancelled
    }
}
