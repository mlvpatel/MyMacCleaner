public enum ReceiptPersistenceError: Error, Equatable, Sendable {
    case historyBusy
    case rootInvalid
    case encodeFailed
    case openFailed
    case writeFailed
    case fullfsyncFailed
    case renameFailed
    case directorySyncFailed
    case readbackFailed
    case leaseFailed
    case reviewRequired
    case unknownReceipt
    case deletionRefused
    case invalidIdentifier
}

public protocol ReceiptStorePort: Sendable {
    func persistIntent(_ intent: ReceiptIntent) async -> Result<Void, ReceiptPersistenceError>
    func persistTransition(
        receipt: ReceiptID,
        _ transition: ReceiptItemTransition
    ) async -> Result<Void, ReceiptPersistenceError>
    func loadAll() async -> Result<[LoadedReceiptRecord], ReceiptPersistenceError>
    func deleteReceipt(_ id: ReceiptID) async -> Result<Void, ReceiptPersistenceError>
    func recoverDeletingTombstones() async -> Result<Void, ReceiptPersistenceError>
}

public protocol ReceiptLeasePort: Sendable {
    func withExclusiveAccess<T: Sendable>(
        _ work: @Sendable () async -> Result<T, ReceiptPersistenceError>
    ) async -> Result<T, ReceiptPersistenceError>
}

public struct ReceiptClock: Sendable {
    public var now: @Sendable () -> WallClockInstant

    public init(now: @escaping @Sendable () -> WallClockInstant) {
        self.now = now
    }
}

public protocol ReceiptExecutionConsuming: Sendable {
    func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination>
}

public enum ReceiptRevealOutcome: Equatable, Sendable {
    case revealRequested
    case unavailable
}

public struct RedactedReceiptSummary: Equatable, Sendable {
    public let id: ReceiptID
    public let createdAt: WallClockInstant
    public let statusMarker: String
    public let schemaMarker: String
    public let itemCount: Int
    public let estimateMarker: String
    public let observedReclaimMarker: String
    public let recoveryMarker: String
    public let guidanceMarker: String

    public static func make(from summary: ReceiptHistorySummary) -> Self {
        let recovery: String
        if summary.isUnresolved {
            recovery = "receipt.recovery.uncertain"
        } else if summary.canRevealMovedItem {
            recovery = "receipt.recovery.mayBeAvailable"
        } else {
            recovery = "receipt.recovery.unavailable"
        }
        return Self(
            id: summary.id,
            createdAt: summary.createdAt,
            statusMarker: "receipt.aggregate.\(summary.aggregate.marker)",
            schemaMarker: "receipt.schema.v1",
            itemCount: summary.itemCount,
            estimateMarker: "count:\(summary.itemCount)",
            observedReclaimMarker: "receipt.reclaim.notObservedWhileInTrash",
            recoveryMarker: recovery,
            guidanceMarker: "receipt.recovery.mayNoLongerBePresent"
        )
    }
}
