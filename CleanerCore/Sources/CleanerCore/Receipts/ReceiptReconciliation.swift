public enum LoadedReceiptRecord: Equatable, Sendable {
    case durable(intent: ReceiptIntent, transitions: [ReceiptItemTransition])
    case unreadable
    case futureSchema(UInt16)
}

public struct ReconciledReceipt: Equatable, Sendable {
    public let aggregate: ReceiptAggregateState
    public let items: [ReceiptItemID: ReceiptItemSnapshot]
    public let isQuarantined: Bool
    public let executionCalls: Int

    public func item(_ id: ReceiptItemID) -> ReceiptItemSnapshot? {
        items[id]
    }

    static func quarantined() -> ReconciledReceipt {
        ReconciledReceipt(aggregate: .needsAttention, items: [:], isQuarantined: true, executionCalls: 0)
    }
}

public struct ReceiptReconciliation: Equatable, Sendable {
    public init() {}

    public func reconcile(_ record: LoadedReceiptRecord, observedAt: WallClockInstant) -> ReconciledReceipt {
        switch record {
        case .unreadable, .futureSchema:
            return .quarantined()
        case let .durable(intent, transitions):
            switch ReceiptReducer.reduce(intent: intent, transitions: transitions) {
            case .failure:
                return .quarantined()
            case let .success(reduced):
                return finish(reduced, observedAt: observedAt)
            }
        }
    }

    private func finish(_ reduced: ReducedReceipt, observedAt: WallClockInstant) -> ReconciledReceipt {
        var items = reduced.items
        var needsAttention = false
        var cancelledPlanned = false

        for id in reduced.intent.orderedItemIDs {
            guard let snapshot = items[id] else { continue }
            switch snapshot.state {
            case .planned:
                items[id] = snapshot.cancelling(at: observedAt)
                cancelledPlanned = true
            case .started:
                needsAttention = true
            case .moved, .skippedStale, .failed, .cancelled:
                break
            }
        }

        let aggregate: ReceiptAggregateState
        if needsAttention {
            aggregate = .needsAttention
        } else if cancelledPlanned {
            aggregate = .interrupted
        } else {
            aggregate = reduced.aggregate
        }

        return ReconciledReceipt(
            aggregate: aggregate,
            items: items,
            isQuarantined: false,
            executionCalls: 0
        )
    }
}
