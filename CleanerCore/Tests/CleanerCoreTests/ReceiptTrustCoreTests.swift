import Testing

@testable import CleanerCore

private enum ReceiptFixture {
    static let t0 = WallClockInstant(unixNanoseconds: 1_000)
    static let t1 = WallClockInstant(unixNanoseconds: 2_000)
    static let t2 = WallClockInstant(unixNanoseconds: 3_000)
    static let restart = WallClockInstant(unixNanoseconds: 9_000)

    static func digest() throws -> PlanDigest {
        try PlanDigest(bytes: Array(repeating: 7, count: 32))
    }

    static func versions() throws -> ReceiptVersionReferences {
        try ReceiptVersionReferences(
            appPlanVersion: "5.0.0",
            policyVersion: "policy-1",
            detectorCatalogVersion: "catalog-1",
            encodingVersion: 1,
            schemaVersion: .v1
        )
    }

    static func item(_ value: String = "item-a") throws -> ReceiptItemID {
        try ReceiptItemID(value)
    }

    static func estimate(
        logical: Int64 = 4_096,
        allocated: Int64 = 4_096,
        reclaimable: Int64 = 4_096
    ) throws -> ReceiptEstimateEvidence {
        try ReceiptEstimateEvidence(
            logicalBytes: logical,
            allocatedBytes: allocated,
            conservativeReclaimableBytes: reclaimable
        )
    }

    static func intent(items: [String] = ["item-a"]) throws -> ReceiptIntent {
        let ids = try items.map(ReceiptItemID.init)
        var estimates: [ReceiptItemID: ReceiptEstimateEvidence] = [:]
        for id in ids {
            estimates[id] = try estimate()
        }
        return try ReceiptIntent(
            id: ReceiptID("receipt-1"),
            schemaVersion: .v1,
            planDigest: digest(),
            versionReferences: versions(),
            createdAt: t0,
            orderedItemIDs: ids,
            estimates: estimates
        )
    }
}

@Suite("Receipt Transition Tests")
struct ReceiptTransitionTests {
    @Test
    func plannedThenStartedThenMovedPreservesIdentityAndPrivateDestination() throws {
        let intent = try ReceiptFixture.intent()
        let item = try ReceiptFixture.item()
        let destination = PrivateRecoveryDestination(token: "file:///Users/secret/.Trash/model.bin")
        let reduced = try ReceiptReducer.reduce(
            intent: intent,
            transitions: [
                .started(itemID: item, at: ReceiptFixture.t1),
                .moved(itemID: item, at: ReceiptFixture.t2, destination: destination),
            ]
        ).get()

        #expect(reduced.intent.id == intent.id)
        #expect(reduced.intent.planDigest == intent.planDigest)
        #expect(reduced.intent.versionReferences == intent.versionReferences)
        #expect(reduced.item(item)?.state == .moved)
        #expect(reduced.item(item)?.startedAt == ReceiptFixture.t1)
        #expect(reduced.item(item)?.terminalAt == ReceiptFixture.t2)
        #expect(reduced.item(item)?.privateDestination == destination)
        let expectedEstimate = try ReceiptFixture.estimate()
        #expect(reduced.item(item)?.estimate == expectedEstimate)
        #expect(reduced.item(item)?.observedReclaim == .notObservedWhileInTrash)
        #expect(reduced.aggregate == .complete)
        #expect(reduced.item(item)?.observedReclaim != .reclaimed(expectedEstimate.conservativeReclaimableBytes))
    }

    @Test
    func eachRequiredTerminalIsDistinct() throws {
        let stale = try reduceOne(.skippedStale(itemID: try ReceiptFixture.item(), at: ReceiptFixture.t2, reason: .sizeChanged))
        let failed = try reduceOne(.failed(itemID: try ReceiptFixture.item(), at: ReceiptFixture.t2, failure: .nativeMoveFailed))
        let cancelled = try reduceOne(.cancelled(itemID: try ReceiptFixture.item(), at: ReceiptFixture.t2))
        let moved = try reduceOne(
            .moved(
                itemID: try ReceiptFixture.item(),
                at: ReceiptFixture.t2,
                destination: PrivateRecoveryDestination(token: "opaque")
            )
        )

        #expect(stale.item(try ReceiptFixture.item())?.state == .skippedStale)
        #expect(failed.item(try ReceiptFixture.item())?.state == .failed)
        #expect(cancelled.item(try ReceiptFixture.item())?.state == .cancelled)
        #expect(moved.item(try ReceiptFixture.item())?.state == .moved)
        #expect(stale.item(try ReceiptFixture.item())?.state != failed.item(try ReceiptFixture.item())?.state)
        #expect(failed.item(try ReceiptFixture.item())?.state != cancelled.item(try ReceiptFixture.item())?.state)
        #expect(cancelled.item(try ReceiptFixture.item())?.state != moved.item(try ReceiptFixture.item())?.state)
    }

    @Test
    func illegalTransitionsReturnClosedValidationErrors() throws {
        let intent = try ReceiptFixture.intent()
        let item = try ReceiptFixture.item()
        let start = ReceiptItemTransition.started(itemID: item, at: ReceiptFixture.t1)
        let terminal = ReceiptItemTransition.cancelled(itemID: item, at: ReceiptFixture.t2)

        #expect(throws: ReceiptValidationError.duplicateStart) {
            try ReceiptReducer.reduce(intent: intent, transitions: [start, start]).get()
        }
        #expect(throws: ReceiptValidationError.terminalBeforeStart) {
            try ReceiptReducer.reduce(intent: intent, transitions: [terminal]).get()
        }
        #expect(throws: ReceiptValidationError.duplicateTerminal) {
            try ReceiptReducer.reduce(intent: intent, transitions: [start, terminal, terminal]).get()
        }
        #expect(throws: ReceiptValidationError.invalidTimeOrder) {
            try ReceiptReducer.reduce(
                intent: intent,
                transitions: [
                    .started(itemID: item, at: ReceiptFixture.t2),
                    .cancelled(itemID: item, at: ReceiptFixture.t1),
                ]
            ).get()
        }
        #expect(throws: ReceiptValidationError.emptyIdentifier) {
            _ = try ReceiptID("")
        }
        #expect(throws: ReceiptValidationError.duplicateIdentifier) {
            _ = try ReceiptFixture.intent(items: ["item-a", "item-a"])
        }
        #expect(throws: ReceiptValidationError.negativeEstimate) {
            _ = try ReceiptEstimateEvidence(logicalBytes: -1, allocatedBytes: 1, conservativeReclaimableBytes: 1)
        }
        #expect(throws: ReceiptValidationError.overflowingEstimate) {
            _ = try ReceiptEstimateEvidence(
                logicalBytes: Int64.max,
                allocatedBytes: 1,
                conservativeReclaimableBytes: 1
            )
        }
        #expect(throws: ReceiptValidationError.unsupportedSchemaVersion) {
            _ = try ReceiptSchemaVersion.parse(99)
        }
    }

    private func reduceOne(_ terminal: ReceiptItemTransition) throws -> ReducedReceipt {
        let intent = try ReceiptFixture.intent()
        let item = try ReceiptFixture.item()
        return try ReceiptReducer.reduce(
            intent: intent,
            transitions: [
                .started(itemID: item, at: ReceiptFixture.t1),
                terminal,
            ]
        ).get()
    }
}

@Suite("Receipt Privacy Tests")
struct ReceiptPrivacyTests {
    @Test
    func displayAndDiagnosticOmitHostilePayloadsAndDoNotClaimReclaim() throws {
        let hostile = [
            "/Users/secret/Library/Application Support/Claude/models/weights.bin",
            "file:///.Trash/com.apple.iconservices.store",
            "project-omega",
            "llama-3-70b-instruct",
            "--token=sk-live-secret",
            "password=hunter2",
            "chat transcript: delete my tax return",
            "config.yaml apiKey",
            "The operation couldn’t be completed.",
            "canonical-plan-bytes",
            "{\"receipt\":true}",
        ]
        let intent = try ReceiptFixture.intent()
        let item = try ReceiptFixture.item()
        let reduced = try ReceiptReducer.reduce(
            intent: intent,
            transitions: [
                .started(itemID: item, at: ReceiptFixture.t1),
                .moved(
                    itemID: item,
                    at: ReceiptFixture.t2,
                    destination: PrivateRecoveryDestination(token: hostile.joined(separator: "|"))
                ),
            ]
        ).get()

        let display = ReceiptDisplayProjection.make(from: reduced)
        let diagnostic = ReceiptDiagnosticProjection.make(from: reduced)
        let rendered = (display.tokens + diagnostic.tokens).joined(separator: " ")

        for payload in hostile {
            #expect(!rendered.contains(payload))
        }
        #expect(display.observedReclaimMarker == "receipt.reclaim.notObservedWhileInTrash")
        #expect(!display.tokens.contains("4096"))
        #expect(diagnostic.sensitiveClassCounts[.receipt] == 1)
        #expect(diagnostic.tokens.allSatisfy { token in
            token.hasPrefix("receipt.") || token.hasPrefix("count:")
        })
    }
}

@Suite("Receipt Reconciliation Tests")
struct ReceiptReconciliationTests {
    @Test
    func plannedOnlyRestartBecomesInterruptedCancelledWithZeroExecutorCalls() throws {
        let recorder = MutationCallRecorder()
        let intent = try ReceiptFixture.intent()
        let reconciled = ReceiptReconciliation().reconcile(
            .durable(intent: intent, transitions: []),
            observedAt: ReceiptFixture.restart
        )

        #expect(reconciled.aggregate == .interrupted)
        #expect(reconciled.item(try ReceiptFixture.item())?.state == .cancelled)
        #expect(reconciled.item(try ReceiptFixture.item())?.terminalAt == ReceiptFixture.restart)
        #expect(recorder.calls == 0)
        #expect(reconciled.executionCalls == 0)
    }

    @Test
    func startedWithoutTerminalNeedsAttentionAndNeverReplays() throws {
        let recorder = MutationCallRecorder()
        let intent = try ReceiptFixture.intent()
        let item = try ReceiptFixture.item()
        let reconciled = ReceiptReconciliation().reconcile(
            .durable(
                intent: intent,
                transitions: [.started(itemID: item, at: ReceiptFixture.t1)]
            ),
            observedAt: ReceiptFixture.restart
        )

        #expect(reconciled.aggregate == .needsAttention)
        #expect(reconciled.item(item)?.state == .started)
        #expect(reconciled.item(item)?.terminalAt == nil)
        #expect(recorder.calls == 0)
        #expect(reconciled.executionCalls == 0)
    }

    @Test
    func terminalTruthRemainsTerminal() throws {
        let intent = try ReceiptFixture.intent()
        let item = try ReceiptFixture.item()
        let destination = PrivateRecoveryDestination(token: "opaque-destination")
        let reconciled = ReceiptReconciliation().reconcile(
            .durable(
                intent: intent,
                transitions: [
                    .started(itemID: item, at: ReceiptFixture.t1),
                    .moved(itemID: item, at: ReceiptFixture.t2, destination: destination),
                ]
            ),
            observedAt: ReceiptFixture.restart
        )

        #expect(reconciled.aggregate == .complete)
        #expect(reconciled.item(item)?.state == .moved)
        #expect(reconciled.item(item)?.privateDestination == destination)
        #expect(reconciled.executionCalls == 0)
    }

    @Test
    func corruptImpossibleAndFutureRecordsQuarantineAsNeedsAttention() throws {
        let corrupt = ReceiptReconciliation().reconcile(.unreadable, observedAt: ReceiptFixture.restart)
        let future = ReceiptReconciliation().reconcile(.futureSchema(99), observedAt: ReceiptFixture.restart)
        let intent = try ReceiptFixture.intent()
        let item = try ReceiptFixture.item()
        let impossible = ReceiptReconciliation().reconcile(
            .durable(
                intent: intent,
                transitions: [.cancelled(itemID: item, at: ReceiptFixture.t2)]
            ),
            observedAt: ReceiptFixture.restart
        )

        #expect(corrupt.aggregate == .needsAttention)
        #expect(corrupt.isQuarantined)
        #expect(future.aggregate == .needsAttention)
        #expect(future.isQuarantined)
        #expect(impossible.aggregate == .needsAttention)
        #expect(impossible.isQuarantined)
        #expect(corrupt.executionCalls == 0)
        #expect(future.executionCalls == 0)
        #expect(impossible.executionCalls == 0)
    }
}
