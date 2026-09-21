public actor ReceiptHistoryCoordinator {
    private let store: any ReceiptStorePort
    private let lease: any ReceiptLeasePort
    private let clock: ReceiptClock
    private let execute: any ReceiptExecutionConsuming

    public init(
        store: any ReceiptStorePort,
        lease: any ReceiptLeasePort,
        clock: ReceiptClock,
        execute: any ReceiptExecutionConsuming
    ) {
        self.store = store
        self.lease = lease
        self.clock = clock
        self.execute = execute
    }

    public func run(
        intent: ReceiptIntent,
        operations: [MoveToTrash],
        freshEvidence: [FreshTargetEvidence?],
        isCancelled: @escaping @Sendable () -> Bool
    ) async -> Result<ReconciledReceipt, ReceiptPersistenceError> {
        await lease.withExclusiveAccess {
            await self.perform(
                intent: intent,
                operations: operations,
                freshEvidence: freshEvidence,
                isCancelled: isCancelled
            )
        }
    }

    public func listRedacted() async -> Result<[RedactedReceiptSummary], ReceiptPersistenceError> {
        await lease.withExclusiveAccess {
            await self.listLocked()
        }
    }

    public func deleteReceipts(ids: [ReceiptID]) async -> Result<Void, ReceiptPersistenceError> {
        await lease.withExclusiveAccess {
            await self.deleteLocked(ids: ids)
        }
    }

    private func perform(
        intent: ReceiptIntent,
        operations: [MoveToTrash],
        freshEvidence: [FreshTargetEvidence?],
        isCancelled: @escaping @Sendable () -> Bool
    ) async -> Result<ReconciledReceipt, ReceiptPersistenceError> {
        guard operations.count == intent.orderedItemIDs.count else {
            return .failure(.encodeFailed)
        }
        switch await store.recoverDeletingTombstones() {
        case let .failure(error):
            return .failure(error)
        case .success:
            break
        }
        switch await admission() {
        case let .failure(error):
            return .failure(error)
        case .success:
            break
        }
        switch await store.persistIntent(intent) {
        case let .failure(error):
            return .failure(error)
        case .success:
            break
        }

        var transitions: [ReceiptItemTransition] = []
        for index in operations.indices {
            let itemID = intent.orderedItemIDs[index]
            if isCancelled() {
                break
            }
            let started = ReceiptItemTransition.started(itemID: itemID, at: clock.now())
            switch await store.persistTransition(receipt: intent.id, started) {
            case let .failure(error):
                return .failure(error)
            case .success:
                transitions.append(started)
            }

            let fresh = index < freshEvidence.count ? freshEvidence[index] : nil
            let outcome = execute.revalidateAndMove(operations[index], fresh: fresh)
            let terminal = Self.terminal(itemID: itemID, at: clock.now(), outcome: outcome)
            switch await store.persistTransition(receipt: intent.id, terminal) {
            case let .failure(error):
                return .failure(error)
            case .success:
                transitions.append(terminal)
            }
        }

        _ = await pruneLocked()

        return .success(
            ReceiptReconciliation().reconcile(
                .durable(intent: intent, transitions: transitions),
                observedAt: clock.now()
            )
        )
    }

    private func admission() async -> Result<Void, ReceiptPersistenceError> {
        switch await store.loadAll() {
        case let .failure(error):
            return .failure(error)
        case let .success(records):
            let now = clock.now()
            let packed = ReceiptRetention.summaries(from: records, observedAt: now)
            let decision = ReceiptRetention.decide(
                summaries: packed.items,
                anonymousUnresolved: packed.anonymousUnresolved,
                now: now
            )
            if decision.admitNewCleanup {
                return .success(())
            }
            return .failure(.reviewRequired)
        }
    }

    private func pruneLocked() async -> Result<Void, ReceiptPersistenceError> {
        switch await store.loadAll() {
        case let .failure(error):
            return .failure(error)
        case let .success(records):
            let now = clock.now()
            let packed = ReceiptRetention.summaries(from: records, observedAt: now)
            let decision = ReceiptRetention.decide(
                summaries: packed.items,
                anonymousUnresolved: packed.anonymousUnresolved,
                now: now
            )
            for id in decision.pruneIDs {
                switch await store.deleteReceipt(id) {
                case let .failure(error):
                    return .failure(error)
                case .success:
                    continue
                }
            }
            return .success(())
        }
    }

    private func listLocked() async -> Result<[RedactedReceiptSummary], ReceiptPersistenceError> {
        switch await store.recoverDeletingTombstones() {
        case let .failure(error):
            return .failure(error)
        case .success:
            break
        }
        switch await store.loadAll() {
        case let .failure(error):
            return .failure(error)
        case let .success(records):
            let packed = ReceiptRetention.summaries(from: records, observedAt: clock.now())
            let rows = packed.items
                .sorted { left, right in
                    if left.createdAt.unixNanoseconds != right.createdAt.unixNanoseconds {
                        return left.createdAt.unixNanoseconds > right.createdAt.unixNanoseconds
                    }
                    return left.id.value < right.id.value
                }
                .map(RedactedReceiptSummary.make(from:))
            return .success(rows)
        }
    }

    private func deleteLocked(ids: [ReceiptID]) async -> Result<Void, ReceiptPersistenceError> {
        switch await store.recoverDeletingTombstones() {
        case let .failure(error):
            return .failure(error)
        case .success:
            break
        }
        var seen: Set<String> = []
        for id in ids {
            if seen.contains(id.value) {
                return .failure(.invalidIdentifier)
            }
            seen.insert(id.value)
            switch await store.deleteReceipt(id) {
            case let .failure(error):
                return .failure(error)
            case .success:
                continue
            }
        }
        return .success(())
    }

    private static func terminal(
        itemID: ReceiptItemID,
        at: WallClockInstant,
        outcome: TrashItemOutcome<PrivateRecoveryDestination>
    ) -> ReceiptItemTransition {
        switch outcome {
        case let .moved(destination):
            return .moved(itemID: itemID, at: at, destination: destination)
        case let .skippedStale(reason):
            return .skippedStale(itemID: itemID, at: at, reason: reason)
        case let .failed(failure):
            return .failed(itemID: itemID, at: at, failure: failure)
        case .cancelled:
            return .cancelled(itemID: itemID, at: at)
        }
    }
}
