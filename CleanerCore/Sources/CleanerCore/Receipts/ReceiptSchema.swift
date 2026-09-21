public enum ReceiptValidationError: Error, Equatable, Sendable {
    case emptyIdentifier
    case duplicateIdentifier
    case unsupportedSchemaVersion
    case negativeEstimate
    case overflowingEstimate
    case emptySelection
    case duplicateStart
    case terminalBeforeStart
    case duplicateTerminal
    case invalidTimeOrder
    case unknownItem
    case payloadStateMismatch
}

public enum ReceiptSchemaVersion: UInt16, Equatable, Sendable {
    case v1 = 1

    public static func parse(_ rawValue: UInt16) throws -> Self {
        guard let version = Self(rawValue: rawValue) else {
            throw ReceiptValidationError.unsupportedSchemaVersion
        }
        return version
    }
}

public struct ReceiptID: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw ReceiptValidationError.emptyIdentifier }
        self.value = value
    }
}

public struct ReceiptItemID: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw ReceiptValidationError.emptyIdentifier }
        self.value = value
    }
}

public struct ReceiptEstimateEvidence: Equatable, Sendable {
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let conservativeReclaimableBytes: Int64

    public init(logicalBytes: Int64, allocatedBytes: Int64, conservativeReclaimableBytes: Int64) throws {
        guard logicalBytes >= 0, allocatedBytes >= 0, conservativeReclaimableBytes >= 0 else {
            throw ReceiptValidationError.negativeEstimate
        }
        let summed = logicalBytes.addingReportingOverflow(allocatedBytes)
        guard !summed.overflow else { throw ReceiptValidationError.overflowingEstimate }
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.conservativeReclaimableBytes = conservativeReclaimableBytes
    }
}

public enum ObservedReclaimState: Equatable, Sendable {
    case notObservedWhileInTrash
    case notApplicable
    case reclaimed(Int64)
}

public enum ReceiptItemState: Equatable, Sendable {
    case planned
    case started
    case moved
    case skippedStale
    case failed
    case cancelled

    var marker: String {
        switch self {
        case .planned: return "planned"
        case .started: return "started"
        case .moved: return "moved"
        case .skippedStale: return "skippedStale"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }
}

public enum ReceiptAggregateState: Equatable, Sendable {
    case planned
    case inProgress
    case complete
    case partial
    case interrupted
    case needsAttention

    var marker: String {
        switch self {
        case .planned: return "planned"
        case .inProgress: return "inProgress"
        case .complete: return "complete"
        case .partial: return "partial"
        case .interrupted: return "interrupted"
        case .needsAttention: return "needsAttention"
        }
    }
}

public struct ReceiptVersionReferences: Equatable, Sendable {
    public let appPlanVersion: String
    public let policyVersion: String
    public let detectorCatalogVersion: String
    public let encodingVersion: UInt16
    public let schemaVersion: ReceiptSchemaVersion

    public init(
        appPlanVersion: String,
        policyVersion: String,
        detectorCatalogVersion: String,
        encodingVersion: UInt16,
        schemaVersion: ReceiptSchemaVersion
    ) throws {
        guard !appPlanVersion.isEmpty,
              !policyVersion.isEmpty,
              !detectorCatalogVersion.isEmpty,
              encodingVersion > 0 else {
            throw ReceiptValidationError.emptyIdentifier
        }
        self.appPlanVersion = appPlanVersion
        self.policyVersion = policyVersion
        self.detectorCatalogVersion = detectorCatalogVersion
        self.encodingVersion = encodingVersion
        self.schemaVersion = schemaVersion
    }
}

public struct PrivateRecoveryDestination: Equatable, Hashable, Sendable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct ReceiptIntent: Equatable, Sendable {
    public let id: ReceiptID
    public let schemaVersion: ReceiptSchemaVersion
    public let planDigest: PlanDigest
    public let versionReferences: ReceiptVersionReferences
    public let createdAt: WallClockInstant
    public let orderedItemIDs: [ReceiptItemID]
    public let estimates: [ReceiptItemID: ReceiptEstimateEvidence]

    public init(
        id: ReceiptID,
        schemaVersion: ReceiptSchemaVersion,
        planDigest: PlanDigest,
        versionReferences: ReceiptVersionReferences,
        createdAt: WallClockInstant,
        orderedItemIDs: [ReceiptItemID],
        estimates: [ReceiptItemID: ReceiptEstimateEvidence]
    ) throws {
        guard schemaVersion == .v1, versionReferences.schemaVersion == .v1 else {
            throw ReceiptValidationError.unsupportedSchemaVersion
        }
        guard !orderedItemIDs.isEmpty else { throw ReceiptValidationError.emptySelection }
        let unique = Set(orderedItemIDs)
        guard unique.count == orderedItemIDs.count else {
            throw ReceiptValidationError.duplicateIdentifier
        }
        guard Set(estimates.keys) == unique else { throw ReceiptValidationError.payloadStateMismatch }

        self.id = id
        self.schemaVersion = schemaVersion
        self.planDigest = planDigest
        self.versionReferences = versionReferences
        self.createdAt = createdAt
        self.orderedItemIDs = orderedItemIDs
        self.estimates = estimates
    }
}

public enum ReceiptItemTransition: Equatable, Sendable {
    case started(itemID: ReceiptItemID, at: WallClockInstant)
    case moved(itemID: ReceiptItemID, at: WallClockInstant, destination: PrivateRecoveryDestination)
    case skippedStale(itemID: ReceiptItemID, at: WallClockInstant, reason: TrashStaleReason)
    case failed(itemID: ReceiptItemID, at: WallClockInstant, failure: TrashExecutionFailure)
    case cancelled(itemID: ReceiptItemID, at: WallClockInstant)

    public var itemID: ReceiptItemID {
        switch self {
        case let .started(itemID, _),
             let .moved(itemID, _, _),
             let .skippedStale(itemID, _, _),
             let .failed(itemID, _, _),
             let .cancelled(itemID, _):
            return itemID
        }
    }

    public var at: WallClockInstant {
        switch self {
        case let .started(_, at),
             let .moved(_, at, _),
             let .skippedStale(_, at, _),
             let .failed(_, at, _),
             let .cancelled(_, at):
            return at
        }
    }
}

public struct ReceiptItemSnapshot: Equatable, Sendable {
    public let state: ReceiptItemState
    public let startedAt: WallClockInstant?
    public let terminalAt: WallClockInstant?
    public let privateDestination: PrivateRecoveryDestination?
    public let estimate: ReceiptEstimateEvidence
    public let observedReclaim: ObservedReclaimState

    func cancelling(at time: WallClockInstant) -> ReceiptItemSnapshot {
        ReceiptItemSnapshot(
            state: .cancelled,
            startedAt: startedAt,
            terminalAt: time,
            privateDestination: nil,
            estimate: estimate,
            observedReclaim: .notApplicable
        )
    }
}

public struct ReducedReceipt: Equatable, Sendable {
    public let intent: ReceiptIntent
    public let items: [ReceiptItemID: ReceiptItemSnapshot]
    public let aggregate: ReceiptAggregateState

    public func item(_ id: ReceiptItemID) -> ReceiptItemSnapshot? {
        items[id]
    }
}

public enum ReceiptSensitiveClass: Equatable, Hashable, Sendable {
    case receipt
}

public struct ReceiptDisplayProjection: Equatable, Sendable {
    public let tokens: [String]
    public let observedReclaimMarker: String

    public static func make(from reduced: ReducedReceipt) -> Self {
        let states = reduced.intent.orderedItemIDs.compactMap { reduced.item($0)?.state.marker }
        let reclaim = "receipt.reclaim.notObservedWhileInTrash"
        return .init(
            tokens: ["receipt.schema.v1", "receipt.aggregate.\(reduced.aggregate.marker)", "count:\(states.count)"]
                + states.map { "receipt.item.\($0)" }
                + [reclaim],
            observedReclaimMarker: reclaim
        )
    }
}

public struct ReceiptDiagnosticProjection: Equatable, Sendable {
    public let tokens: [String]
    public let sensitiveClassCounts: [ReceiptSensitiveClass: Int]

    public static func make(from reduced: ReducedReceipt) -> Self {
        .init(
            tokens: ["receipt.event.reduced", "count:\(reduced.items.count)"],
            sensitiveClassCounts: [.receipt: 1]
        )
    }
}
