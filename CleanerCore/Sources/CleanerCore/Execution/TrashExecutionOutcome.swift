public enum TrashStaleReason: Equatable, Sendable {
    case identityChanged
    case locatorChanged
    case rootChanged
    case volumeChanged
    case fileKindChanged
    case sizeChanged
    case modificationChanged
    case topologyChanged
    case semanticOwnerChanged
    case incompleteFreshEvidence
    case missingFreshEvidence
}

public enum TrashExecutionFailure: Equatable, Sendable {
    case nativeMoveFailed
    case missingReturnedLocation
}

public enum TrashItemOutcome<Destination: Equatable & Sendable>: Equatable, Sendable {
    case moved(destination: Destination)
    case skippedStale(TrashStaleReason)
    case failed(TrashExecutionFailure)
    case cancelled
}

public enum TrashRunState: Equatable, Sendable {
    case complete
    case partial
    case interrupted
}

public struct TrashRunResult<Destination: Equatable & Sendable>: Equatable, Sendable {
    public let items: [TrashItemOutcome<Destination>]
    public let state: TrashRunState

    init(items: [TrashItemOutcome<Destination>]) {
        self.items = items
        if items.contains(where: { if case .cancelled = $0 { return true } else { return false } }) {
            state = .interrupted
        } else if !items.isEmpty, items.allSatisfy({ if case .moved = $0 { return true } else { return false } }) {
            state = .complete
        } else {
            state = .partial
        }
    }
}

public enum ApprovedOperationRejection: Error, Equatable, Sendable {
    case invalidApproval(ApprovalInvalidReason)
    case emptyPlan
}
