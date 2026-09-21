import Testing

@testable import CleanerCore

@Suite("Receipt Hostile Fixture Tests")
struct ReceiptHostileFixtureTests {
    @Test
    func cutpointsPreserveExactTruthAndNeverReplay() throws {
        let intent = try ReceiptFixtureFactory.intent()
        let item = try ReceiptItemID("item-a")
        let beforeIntent = ReceiptReconciliation().reconcile(.unreadable, observedAt: ReceiptFixtureFactory.t2)
        #expect(beforeIntent.aggregate == .needsAttention)
        #expect(beforeIntent.executionCalls == 0)

        let afterIntent = ReceiptReconciliation().reconcile(
            .durable(intent: intent, transitions: []),
            observedAt: ReceiptFixtureFactory.t2
        )
        #expect(afterIntent.aggregate == .interrupted)
        #expect(afterIntent.item(item)?.state == .cancelled)
        #expect(afterIntent.executionCalls == 0)

        let afterStarted = ReceiptReconciliation().reconcile(
            .durable(intent: intent, transitions: [try ReceiptFixtureFactory.started()]),
            observedAt: ReceiptFixtureFactory.t2
        )
        #expect(afterStarted.aggregate == .needsAttention)
        #expect(afterStarted.item(item)?.state == .started)
        #expect(afterStarted.executionCalls == 0)

        let afterMoved = ReceiptReconciliation().reconcile(
            .durable(
                intent: intent,
                transitions: [try ReceiptFixtureFactory.started(), try ReceiptFixtureFactory.moved()]
            ),
            observedAt: ReceiptFixtureFactory.t2
        )
        #expect(afterMoved.aggregate == .complete)
        #expect(afterMoved.item(item)?.state == .moved)
        #expect(afterMoved.executionCalls == 0)
    }

    @Test
    func corruptFutureAndIllegalTransitionsQuarantineWithoutAuthority() throws {
        let future = ReceiptReconciliation().reconcile(.futureSchema(99), observedAt: ReceiptFixtureFactory.t2)
        #expect(future.isQuarantined)
        #expect(future.aggregate == .needsAttention)
        #expect(future.executionCalls == 0)

        let intent = try ReceiptFixtureFactory.intent()
        switch ReceiptReducer.reduce(
            intent: intent,
            transitions: [try ReceiptFixtureFactory.moved()]
        ) {
        case .success:
            Issue.record("expected illegal terminal")
        case let .failure(error):
            #expect(error == .terminalBeforeStart)
        }
        let quarantined = ReceiptReconciliation().reconcile(
            .durable(intent: intent, transitions: [try ReceiptFixtureFactory.moved()]),
            observedAt: ReceiptFixtureFactory.t2
        )
        #expect(quarantined.isQuarantined)
        #expect(quarantined.executionCalls == 0)
    }

    @Test
    func hostilePayloadsStayOutOfRedactedProjectionsAndRetentionNeverPrunesUnresolved() throws {
        let intent = try ReceiptFixtureFactory.intent()
        let reduced = try ReceiptReducer.reduce(
            intent: intent,
            transitions: [try ReceiptFixtureFactory.started(), try ReceiptFixtureFactory.moved()]
        ).get()
        let display = ReceiptDisplayProjection.make(from: reduced)
        let diagnostic = ReceiptDiagnosticProjection.make(from: reduced)
        let joined = (display.tokens + diagnostic.tokens).joined()
        #expect(!joined.contains(ReceiptFixtureFactory.hostileToken))
        #expect(!joined.contains("model.bin"))
        #expect(!joined.contains("/Users/secret"))
        #expect(display.observedReclaimMarker == "receipt.reclaim.notObservedWhileInTrash")

        let unresolved = ReceiptHistorySummary(
            id: try ReceiptID("needs"),
            createdAt: .init(unixNanoseconds: 1),
            aggregate: .needsAttention,
            isQuarantined: false,
            itemCount: 1,
            canRevealMovedItem: false
        )
        let now = WallClockInstant(unixNanoseconds: ReceiptRetention.maximumAgeNanoseconds + 10)
        let decision = ReceiptRetention.decide(summaries: [unresolved], anonymousUnresolved: 0, now: now)
        #expect(decision.pruneIDs.isEmpty)
        #expect(decision.admitNewCleanup)
    }
}
