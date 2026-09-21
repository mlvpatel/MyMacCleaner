public enum LocalWorkloadToolFamily: String, CaseIterable, Equatable, Sendable {
    case ollama
    case lmStudio
    case mlx
    case localInference
}

public struct CompletedLocalInventoryEvidenceID: Equatable, Hashable, Sendable {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }
}

public struct WorkloadObservationIdentity: Equatable, Hashable, Sendable {
    public let sessionID: MemoryObservationSessionID
    public let processIdentity: ProcessObservationIdentity

    public init(
        sessionID: MemoryObservationSessionID,
        processIdentity: ProcessObservationIdentity
    ) {
        self.sessionID = sessionID
        self.processIdentity = processIdentity
    }
}

public enum WorkloadContextAbsenceReason: Equatable, Sendable {
    case staleCompletedInventory
    case invalidInventoryTiming
    case identityMismatch
    case conflictingInventoryEvidence
    case inventoryRecordLimitExceeded
    case unknownProcessIdentity
}

public enum WorkloadContext: Equatable, Sendable {
    case confirmed(
        identity: WorkloadObservationIdentity,
        toolFamily: LocalWorkloadToolFamily,
        evidenceID: CompletedLocalInventoryEvidenceID
    )
    case inferred(
        identity: WorkloadObservationIdentity,
        toolFamily: LocalWorkloadToolFamily
    )
    case absent(
        identity: WorkloadObservationIdentity,
        reason: WorkloadContextAbsenceReason
    )

    public var identity: WorkloadObservationIdentity {
        switch self {
        case let .confirmed(identity, _, _):
            identity
        case let .inferred(identity, _):
            identity
        case let .absent(identity, _):
            identity
        }
    }
}

public struct CompletedLocalInventoryEvidence: Equatable, Sendable {
    public let evidenceID: CompletedLocalInventoryEvidenceID
    public let toolFamily: LocalWorkloadToolFamily
    public let completedAt: ClockReading
    public let sourceObservedAt: ClockReading
    public let observationSessionID: MemoryObservationSessionID?
    public let processIdentity: ProcessObservationIdentity?

    public init(
        evidenceID: CompletedLocalInventoryEvidenceID,
        toolFamily: LocalWorkloadToolFamily,
        completedAt: ClockReading,
        sourceObservedAt: ClockReading,
        observationSessionID: MemoryObservationSessionID?,
        processIdentity: ProcessObservationIdentity?
    ) {
        self.evidenceID = evidenceID
        self.toolFamily = toolFamily
        self.completedAt = completedAt
        self.sourceObservedAt = sourceObservedAt
        self.observationSessionID = observationSessionID
        self.processIdentity = processIdentity
    }
}

public protocol WorkloadEvidencePort: Sendable {
    func context(
        sessionID: MemoryObservationSessionID,
        process: ProcessMemoryEvidence
    ) -> WorkloadContext
}

public struct LocalWorkloadEvidenceProducer: WorkloadEvidencePort, Sendable {
    public static let maximumInventoryAgeNanoseconds: UInt64 = 300_000_000_000
    public static let maximumCompletedInventoryRecords = SamplingBudget.maximumCandidates

    private let completedInventory: [CompletedLocalInventoryEvidence]
    private let inventoryRecordLimitExceeded: Bool

    public init(completedInventory: [CompletedLocalInventoryEvidence] = []) {
        if completedInventory.count > Self.maximumCompletedInventoryRecords {
            self.completedInventory = []
            inventoryRecordLimitExceeded = true
        } else {
            self.completedInventory = completedInventory
            inventoryRecordLimitExceeded = false
        }
    }

    public func context(
        sessionID: MemoryObservationSessionID,
        process: ProcessMemoryEvidence
    ) -> WorkloadContext {
        let observationIdentity = WorkloadObservationIdentity(
            sessionID: sessionID,
            processIdentity: process.identity
        )
        guard !inventoryRecordLimitExceeded else {
            return .absent(identity: observationIdentity, reason: .inventoryRecordLimitExceeded)
        }

        var sawStaleIdentityMatch = false
        var sawInvalidTimingIdentityMatch = false
        var freshMatch: CompletedLocalInventoryEvidence?

        for record in completedInventory {
            guard record.observationSessionID == sessionID,
                  record.processIdentity == process.identity
            else {
                continue
            }

            switch inventoryTiming(record, processObservedAt: process.observedAt) {
            case .fresh:
                if let previous = freshMatch {
                    guard previous.toolFamily == record.toolFamily,
                          previous.evidenceID == record.evidenceID
                    else {
                        return .absent(
                            identity: observationIdentity,
                            reason: .conflictingInventoryEvidence
                        )
                    }
                } else {
                    freshMatch = record
                }
            case .stale:
                sawStaleIdentityMatch = true
            case .invalid:
                sawInvalidTimingIdentityMatch = true
            }
        }

        if let record = freshMatch {
            return .confirmed(
                identity: observationIdentity,
                toolFamily: record.toolFamily,
                evidenceID: record.evidenceID
            )
        }

        if let mappedFamily = Self.mappedFamily(for: process.label) {
            return .inferred(
                identity: observationIdentity,
                toolFamily: mappedFamily
            )
        }

        if sawInvalidTimingIdentityMatch {
            return .absent(identity: observationIdentity, reason: .invalidInventoryTiming)
        }
        if sawStaleIdentityMatch {
            return .absent(identity: observationIdentity, reason: .staleCompletedInventory)
        }
        if !completedInventory.isEmpty {
            return .absent(identity: observationIdentity, reason: .identityMismatch)
        }
        return .absent(identity: observationIdentity, reason: .unknownProcessIdentity)
    }

    private func inventoryTiming(
        _ record: CompletedLocalInventoryEvidence,
        processObservedAt: ClockReading
    ) -> InventoryTiming {
        let source = record.sourceObservedAt.observationInstant.monotonicNanoseconds
        let completion = record.completedAt.observationInstant.monotonicNanoseconds
        let process = processObservedAt.observationInstant.monotonicNanoseconds

        guard source <= completion, completion <= process else {
            return .invalid
        }
        guard process - source <= Self.maximumInventoryAgeNanoseconds,
              process - completion <= Self.maximumInventoryAgeNanoseconds
        else {
            return .stale
        }
        return .fresh
    }

    private static func mappedFamily(
        for label: ProcessDisplayLabel
    ) -> LocalWorkloadToolFamily? {
        switch label.value {
        case "ollama":
            .ollama
        case "LM Studio":
            .lmStudio
        case "mlx_lm.server":
            .mlx
        case "llama-server":
            .localInference
        default:
            nil
        }
    }
}

private enum InventoryTiming {
    case fresh
    case stale
    case invalid
}
