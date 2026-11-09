import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Receipt Store Hostile Fixture Tests")
struct ReceiptStoreHostileFixtureTests {
    @Test
    func symlinkRootAndBusyLeaseFailClosed() async throws {
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

        let busy = ScriptedPersistence()
        busy.busy = true
        let coordinator = ReceiptHistoryCoordinator(
            store: busy,
            lease: busy,
            clock: ReceiptClock { .init(unixNanoseconds: 9) },
            execute: busy
        )
        #expect(await coordinator.listRedacted().error == .historyBusy)
        #expect(busy.calls == 0)
    }

    @Test
    func leftoverJournalTempFileAndFinderMetadataDoNotQuarantineAReceipt() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let store = fixture.store()
        let intent = try persistenceIntent()
        let started = ReceiptItemTransition.started(itemID: try ReceiptItemID("item-a"), at: .init(unixNanoseconds: 2))
        #expect(await store.persistIntent(intent).isSuccess)
        #expect(await store.persistTransition(receipt: intent.id, started).isSuccess)
        let record = receiptsFolder(fixture).appendingPathComponent(intent.id.value, isDirectory: true)
        // A crash mid-publish leaves `.<name>.<pid>.<rand>.tmp`; Finder may add `.DS_Store`.
        try Data().write(to: record.appendingPathComponent(".x.json.1.2.tmp"))
        try Data("finder".utf8).write(to: record.appendingPathComponent(".DS_Store"))

        let loaded = try await store.loadAll().get()

        #expect(loaded == [.durable(intent: intent, transitions: [started])])
    }

    @Test
    func aFolderHoldingOnlyAStaleTempFileIsNothingRanAndIsSweptUnderTheLease() async throws {
        let fixture = try SupportFixture()
        defer { fixture.tearDown() }
        let store = fixture.store()
        let intent = try persistenceIntent()
        #expect(await store.persistIntent(intent).isSuccess)
        let receipts = receiptsFolder(fixture)
        // A crash while publishing the intent itself: the folder holds only the temp file.
        let crashed = receipts.appendingPathComponent("crashed-before-intent", isDirectory: true)
        try FileManager.default.createDirectory(at: crashed, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: crashed.path)
        try Data().write(to: crashed.appendingPathComponent(".intent.json.1.2.tmp"))
        let strayTemp = receipts.appendingPathComponent(intent.id.value).appendingPathComponent(".x.json.3.4.tmp")
        try Data().write(to: strayTemp)

        let loaded = try await store.loadAll().get()
        let packed = ReceiptRetention.summaries(from: loaded, observedAt: .init(unixNanoseconds: 9))
        #expect(packed.anonymousUnresolved == 0)
        #expect(loaded == [.durable(intent: intent, transitions: [])])

        let coordinator = ReceiptHistoryCoordinator(
            store: store,
            lease: DarwinReceiptLease(lockFile: fixture.support.appendingPathComponent("test.lock")),
            clock: ReceiptClock { .init(unixNanoseconds: 9) },
            execute: NoExecution()
        )
        #expect(try await coordinator.listRedacted().get().map(\.id) == [intent.id])
        #expect(!FileManager.default.fileExists(atPath: crashed.path))
        #expect(!FileManager.default.fileExists(atPath: strayTemp.path))
        #expect(try await store.loadAll().get() == [.durable(intent: intent, transitions: [])])
    }

    private func receiptsFolder(_ fixture: SupportFixture) -> URL {
        fixture.support
            .appendingPathComponent("MyMacCleaner", isDirectory: true)
            .appendingPathComponent("Receipts", isDirectory: true)
    }
}

private struct NoExecution: ReceiptExecutionConsuming {
    func revalidateAndMove(
        _: MoveToTrash,
        fresh _: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        .cancelled
    }
}
