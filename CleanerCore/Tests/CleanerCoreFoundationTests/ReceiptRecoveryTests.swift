import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Receipt Recovery Tests")
struct ReceiptRecoveryTests {
    private let secret = "file:///Users/secret/project/.Trash/model.bin"

    @Test
    func reachableMovedDestinationSelectsExactlyOnceAndStaysPrivate() async throws {
        let destination = URL(string: secret)!
        let recorder = SelectionRecorder()
        let adapter = FinderReceiptRevealAdapter(
            resolve: { _, _ in .success(destination) },
            isReachable: { _ in true },
            select: { urls in
                recorder.urls.append(contentsOf: urls)
                return true
            }
        )
        let outcome = await adapter.reveal(
            receipt: try ReceiptID("receipt-1"),
            item: try ReceiptItemID("item-a")
        )
        #expect(outcome == .revealRequested)
        #expect(recorder.urls == [destination])
        let redacted = RedactedReceiptSummary.make(
            from: ReceiptHistorySummary(
                id: try ReceiptID("receipt-1"),
                createdAt: .init(unixNanoseconds: 1),
                aggregate: .complete,
                isQuarantined: false,
                itemCount: 1,
                canRevealMovedItem: true
            )
        )
        let joined = [
            redacted.statusMarker, redacted.schemaMarker, redacted.estimateMarker,
            redacted.observedReclaimMarker, redacted.recoveryMarker, redacted.guidanceMarker
        ].joined()
        #expect(!joined.contains(secret))
        #expect(!joined.contains("model.bin"))
        #expect(!joined.contains("/Users/secret"))
        #expect(redacted.recoveryMarker == "receipt.recovery.mayBeAvailable")
        #expect(redacted.guidanceMarker == "receipt.recovery.mayNoLongerBePresent")
    }

    @Test
    func missingVolumeDeniedCorruptAndNonMovedReturnUnavailableWithZeroSelects() async throws {
        let recorder = SelectionRecorder()
        let unreachable = FinderReceiptRevealAdapter(
            resolve: { _, _ in .success(URL(string: self.secret)!) },
            isReachable: { _ in false },
            select: { urls in
                recorder.urls.append(contentsOf: urls)
                return true
            }
        )
        #expect(
            await unreachable.reveal(receipt: try ReceiptID("r"), item: try ReceiptItemID("i"))
                == .unavailable
        )

        let denied = FinderReceiptRevealAdapter(
            resolve: { _, _ in .success(URL(string: self.secret)!) },
            isReachable: { _ in true },
            select: { _ in false }
        )
        #expect(
            await denied.reveal(receipt: try ReceiptID("r"), item: try ReceiptItemID("i"))
                == .unavailable
        )

        let missing = FinderReceiptRevealAdapter(
            resolve: { _, _ in .failure(.unknownReceipt) },
            isReachable: { _ in true },
            select: { urls in
                recorder.urls.append(contentsOf: urls)
                return true
            }
        )
        #expect(
            await missing.reveal(receipt: try ReceiptID("r"), item: try ReceiptItemID("i"))
                == .unavailable
        )
        #expect(recorder.urls.isEmpty)
    }

    @Test
    func storeResolvesCollisionRenamedDestinationPrivatelyAndRejectsNonMoved() async throws {
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
        let resolved = try await store.privateMovedDestination(receipt: intent.id, item: item).get()
        #expect(resolved.absoluteString == secret)

        let other = try ReceiptItemID("missing")
        #expect(await store.privateMovedDestination(receipt: intent.id, item: other).error == .unknownReceipt)

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

    @Test
    func duplicateRevealDoesNotChangeReceiptTruth() async throws {
        let recorder = SelectionRecorder()
        let adapter = FinderReceiptRevealAdapter(
            resolve: { _, _ in .success(URL(string: self.secret)!) },
            isReachable: { _ in true },
            select: { urls in
                recorder.urls.append(contentsOf: urls)
                return true
            }
        )
        let receipt = try ReceiptID("receipt-1")
        let item = try ReceiptItemID("item-a")
        #expect(await adapter.reveal(receipt: receipt, item: item) == .revealRequested)
        #expect(await adapter.reveal(receipt: receipt, item: item) == .revealRequested)
        #expect(recorder.urls.count == 2)
        #expect(recorder.urls.allSatisfy { $0.absoluteString == self.secret })
    }
}

private final class SelectionRecorder: @unchecked Sendable {
    var urls: [URL] = []
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
