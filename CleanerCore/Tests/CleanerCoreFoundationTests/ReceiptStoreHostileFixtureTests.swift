import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Receipt Store Hostile Fixture Tests")
struct ReceiptStoreHostileFixtureTests {
    @Test
    func symlinkRootAndBusyLeaseAndUnknownRevealFailClosed() async throws {
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

        let adapter = FinderReceiptRevealAdapter(
            resolve: { _, _ in .failure(.unknownReceipt) },
            isReachable: { _ in true },
            select: { _ in true }
        )
        #expect(
            await adapter.reveal(receipt: try ReceiptID("missing"), item: try ReceiptItemID("item-a"))
                == .unavailable
        )
    }
}
