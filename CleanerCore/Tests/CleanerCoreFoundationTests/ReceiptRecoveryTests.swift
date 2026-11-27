import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Receipt Recovery Tests")
struct ReceiptRecoveryTests {
    private let secret = "file:///Users/secret/project/.Trash/model.bin"

    @Test
    func movedDestinationStaysOutOfTheRedactedHistory() async throws {
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
                    destination: PrivateRecoveryDestination(token: secret)
                )
            ).isSuccess
        )
        let coordinator = ReceiptHistoryCoordinator(
            store: store,
            lease: ImmediateRevealLease(),
            clock: ReceiptClock { .init(unixNanoseconds: 9) },
            execute: NeverRevealExecute()
        )
        let list = try await coordinator.listRedacted().get()
        let joined = list.map {
            [$0.statusMarker, $0.schemaMarker, $0.recoveryMarker, $0.guidanceMarker, $0.id.value].joined()
        }.joined()
        #expect(!joined.contains(secret))
        #expect(!joined.contains("model.bin"))
    }
}

private struct ImmediateRevealLease: ReceiptLeasePort {
    func withExclusiveAccess<T: Sendable>(
        _ work: @Sendable () async -> Result<T, ReceiptPersistenceError>
    ) async -> Result<T, ReceiptPersistenceError> {
        await work()
    }
}

private struct NeverRevealExecute: ReceiptExecutionConsuming {
    func revalidateAndMove(
        _: MoveToTrash,
        fresh _: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        .cancelled
    }
}
