public enum ReceiptReducer {
    public static func reduce(
        intent: ReceiptIntent,
        transitions: [ReceiptItemTransition]
    ) -> Result<ReducedReceipt, ReceiptValidationError> {
        var items: [ReceiptItemID: ReceiptItemSnapshot] = [:]
        for id in intent.orderedItemIDs {
            guard let estimate = intent.estimates[id] else {
                return .failure(.payloadStateMismatch)
            }
            items[id] = ReceiptItemSnapshot(
                state: .planned,
                startedAt: nil,
                terminalAt: nil,
                privateDestination: nil,
                estimate: estimate,
                observedReclaim: .notApplicable
            )
        }

        for transition in transitions {
            guard var snapshot = items[transition.itemID] else {
                return .failure(.unknownItem)
            }
            switch apply(transition, to: snapshot) {
            case let .failure(error):
                return .failure(error)
            case let .success(next):
                snapshot = next
                items[transition.itemID] = snapshot
            }
        }

        return .success(
            ReducedReceipt(
                intent: intent,
                items: items,
                aggregate: aggregate(for: intent.orderedItemIDs.compactMap { items[$0]?.state })
            )
        )
    }

    private static func apply(
        _ transition: ReceiptItemTransition,
        to snapshot: ReceiptItemSnapshot
    ) -> Result<ReceiptItemSnapshot, ReceiptValidationError> {
        switch (snapshot.state, transition) {
        case (.planned, let .started(_, at)):
            return .success(
                ReceiptItemSnapshot(
                    state: .started,
                    startedAt: at,
                    terminalAt: nil,
                    privateDestination: nil,
                    estimate: snapshot.estimate,
                    observedReclaim: .notApplicable
                )
            )
        case (.started, let .moved(_, at, destination)):
            guard let startedAt = snapshot.startedAt, startedAt <= at else {
                return .failure(.invalidTimeOrder)
            }
            return .success(
                ReceiptItemSnapshot(
                    state: .moved,
                    startedAt: startedAt,
                    terminalAt: at,
                    privateDestination: destination,
                    estimate: snapshot.estimate,
                    observedReclaim: .notObservedWhileInTrash
                )
            )
        case (.started, let .skippedStale(_, at, _)):
            return terminal(from: snapshot, at: at, state: .skippedStale, destination: nil, reclaim: .notApplicable)
        case (.started, let .failed(_, at, _)):
            return terminal(from: snapshot, at: at, state: .failed, destination: nil, reclaim: .notApplicable)
        case (.started, let .cancelled(_, at)):
            return terminal(from: snapshot, at: at, state: .cancelled, destination: nil, reclaim: .notApplicable)
        case (.planned, .moved), (.planned, .skippedStale), (.planned, .failed), (.planned, .cancelled):
            return .failure(.terminalBeforeStart)
        case (.started, .started):
            return .failure(.duplicateStart)
        case (.moved, _), (.skippedStale, _), (.failed, _), (.cancelled, _):
            if case .started = transition { return .failure(.duplicateStart) }
            return .failure(.duplicateTerminal)
        }
    }

    private static func terminal(
        from snapshot: ReceiptItemSnapshot,
        at: WallClockInstant,
        state: ReceiptItemState,
        destination: PrivateRecoveryDestination?,
        reclaim: ObservedReclaimState
    ) -> Result<ReceiptItemSnapshot, ReceiptValidationError> {
        guard let startedAt = snapshot.startedAt, startedAt <= at else {
            return .failure(.invalidTimeOrder)
        }
        return .success(
            ReceiptItemSnapshot(
                state: state,
                startedAt: startedAt,
                terminalAt: at,
                privateDestination: destination,
                estimate: snapshot.estimate,
                observedReclaim: reclaim
            )
        )
    }

    private static func aggregate(for states: [ReceiptItemState]) -> ReceiptAggregateState {
        if states.contains(.cancelled) { return .interrupted }
        if states.contains(.started) { return .inProgress }
        if states.allSatisfy({ $0 == .planned }) { return .planned }
        if !states.isEmpty, states.allSatisfy({ $0 == .moved }) { return .complete }
        return .partial
    }
}
