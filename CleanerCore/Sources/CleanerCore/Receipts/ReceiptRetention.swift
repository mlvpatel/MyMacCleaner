public struct ReceiptHistorySummary: Equatable, Sendable {
    public let id: ReceiptID
    public let createdAt: WallClockInstant
    public let aggregate: ReceiptAggregateState
    public let isQuarantined: Bool
    public let itemCount: Int
    public let canRevealMovedItem: Bool

    public var isUnresolved: Bool {
        isQuarantined || aggregate == .needsAttention
    }

    public var isPrunableTerminal: Bool {
        !isUnresolved && (
            aggregate == .complete
                || aggregate == .partial
                || aggregate == .interrupted
        )
    }
}

public struct RetentionDecision: Equatable, Sendable {
    public let pruneIDs: [ReceiptID]
    public let admitNewCleanup: Bool
    public let unresolvedCount: Int
}

public enum ReceiptRetention {
    public static let policyVersion: UInt16 = 1
    public static let maximumAgeNanoseconds: Int64 = 90 * 24 * 60 * 60 * 1_000_000_000
    public static let maximumTerminalCount = 500
    public static let maximumUnresolvedCount = 50

    public static func summaries(
        from records: [LoadedReceiptRecord],
        observedAt: WallClockInstant
    ) -> (items: [ReceiptHistorySummary], anonymousUnresolved: Int) {
        var items: [ReceiptHistorySummary] = []
        var anonymous = 0
        for record in records {
            switch record {
            case .unreadable, .futureSchema:
                anonymous += 1
            case let .durable(intent, _):
                let reconciled = ReceiptReconciliation().reconcile(record, observedAt: observedAt)
                let moved = intent.orderedItemIDs.contains { id in
                    reconciled.item(id)?.state == .moved
                }
                items.append(
                    ReceiptHistorySummary(
                        id: intent.id,
                        createdAt: intent.createdAt,
                        aggregate: reconciled.aggregate,
                        isQuarantined: reconciled.isQuarantined,
                        itemCount: intent.orderedItemIDs.count,
                        canRevealMovedItem: moved && !reconciled.isQuarantined
                    )
                )
            }
        }
        return (items, anonymous)
    }

    public static func decide(
        summaries: [ReceiptHistorySummary],
        anonymousUnresolved: Int,
        now: WallClockInstant
    ) -> RetentionDecision {
        let unresolved = summaries.filter(\.isUnresolved).count + max(0, anonymousUnresolved)
        let terminals = summaries
            .filter(\.isPrunableTerminal)
            .sorted(by: Self.isOlder)
        var prune: [ReceiptID] = []
        var kept: [ReceiptHistorySummary] = []
        for summary in terminals {
            if Self.isOlderThanAgeBoundary(summary.createdAt, now: now) {
                prune.append(summary.id)
            } else {
                kept.append(summary)
            }
        }
        if kept.count > maximumTerminalCount {
            let excess = kept.count - maximumTerminalCount
            prune.append(contentsOf: kept.prefix(excess).map(\.id))
        }
        return RetentionDecision(
            pruneIDs: prune,
            admitNewCleanup: unresolved < maximumUnresolvedCount,
            unresolvedCount: unresolved
        )
    }

    private static func isOlderThanAgeBoundary(
        _ createdAt: WallClockInstant,
        now: WallClockInstant
    ) -> Bool {
        let age = now.unixNanoseconds.subtractingReportingOverflow(createdAt.unixNanoseconds)
        guard !age.overflow else { return false }
        return age.partialValue > maximumAgeNanoseconds
    }

    private static func isOlder(_ left: ReceiptHistorySummary, _ right: ReceiptHistorySummary) -> Bool {
        if left.createdAt.unixNanoseconds != right.createdAt.unixNanoseconds {
            return left.createdAt.unixNanoseconds < right.createdAt.unixNanoseconds
        }
        return left.id.value < right.id.value
    }
}
