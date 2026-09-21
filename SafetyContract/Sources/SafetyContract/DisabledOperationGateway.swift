/// A pure audit signal, deliberately distinct from any transport abstraction.
/// Attempt cases are test sentinels that disabled routes must never emit.
enum DisabledOperationEffect: Equatable, Sendable {
    case requestEvaluated(UnsupportedOperation)
    case processLaunchAttempted
    case elevationRequested
    case helperRequested
    case filesystemMutationAttempted
    case systemMutationAttempted
    case networkRequestAttempted
}

public struct DisabledOperationGateway: Sendable {
    private let effectObserver: @Sendable (DisabledOperationEffect) -> Void

    public init() {
        self.effectObserver = { _ in }
    }

    init(effectObserver: @escaping @Sendable (DisabledOperationEffect) -> Void) {
        self.effectObserver = effectObserver
    }

    public func request(_ operation: UnsupportedOperation) -> DisabledOperationResult {
        effectObserver(.requestEvaluated(operation))

        return switch operation {
        case .permanentDeletion:
            closedResult(for: operation, reason: .permanentDeletionRequiresReviewedPlan)
        case .emptyTrash:
            closedResult(for: operation, reason: .emptyingTrashIsNotAvailable)
        case .privilegedMaintenance:
            closedResult(for: operation, reason: .elevationIsNotAvailable)
        case .memoryPurge:
            closedResult(for: operation, reason: .memoryPurgeIsNotAvailable)
        case .processTermination:
            closedResult(for: operation, reason: .processTerminationIsNotAvailable)
        case .startupItemMutation:
            closedResult(for: operation, reason: .startupMutationIsNotAvailable)
        case .developerToolMutation:
            closedResult(for: operation, reason: .toolMutationIsNotAvailable)
        case .systemSettingsMutation:
            closedResult(for: operation, reason: .settingsMutationIsNotAvailable)
        case .legacyCleanup:
            closedResult(for: operation, reason: .legacyCleanupRequiresReviewedPlan)
        case .reviewedPlanCleanup:
            DisabledOperationResult(
                operation: operation,
                disposition: .deferred,
                reason: .reviewedPlanCleanupIsDeferred
            )
        }
    }

    private func closedResult(
        for operation: UnsupportedOperation,
        reason: DisabledOperationReason
    ) -> DisabledOperationResult {
        DisabledOperationResult(
            operation: operation,
            disposition: .disabled,
            reason: reason
        )
    }
}
