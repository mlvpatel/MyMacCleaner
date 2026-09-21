public enum UnsupportedOperation: String, CaseIterable, Sendable {
    case permanentDeletion
    case emptyTrash
    case privilegedMaintenance
    case memoryPurge
    case processTermination
    case startupItemMutation
    case developerToolMutation
    case systemSettingsMutation
    case legacyCleanup
    case reviewedPlanCleanup
}

public enum DisabledOperationDisposition: String, Equatable, Sendable {
    case disabled
    case deferred
}

public enum DisabledOperationReason: String, Equatable, Sendable {
    case permanentDeletionRequiresReviewedPlan
    case emptyingTrashIsNotAvailable
    case elevationIsNotAvailable
    case memoryPurgeIsNotAvailable
    case processTerminationIsNotAvailable
    case startupMutationIsNotAvailable
    case toolMutationIsNotAvailable
    case settingsMutationIsNotAvailable
    case legacyCleanupRequiresReviewedPlan
    case reviewedPlanCleanupIsDeferred
}

public struct DisabledOperationResult: Equatable, Sendable {
    public let operation: UnsupportedOperation
    public let disposition: DisabledOperationDisposition
    public let reason: DisabledOperationReason

    init(
        operation: UnsupportedOperation,
        disposition: DisabledOperationDisposition,
        reason: DisabledOperationReason
    ) {
        self.operation = operation
        self.disposition = disposition
        self.reason = reason
    }
}
