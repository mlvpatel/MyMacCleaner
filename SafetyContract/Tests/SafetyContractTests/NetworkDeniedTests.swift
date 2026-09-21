import Testing
@testable import SafetyContract

@Suite("Denied Network Contract")
struct NetworkDeniedTests {
    @Test(arguments: UnsupportedOperation.allCases)
    func disabledOperationsReturnWithoutNetworkRequests(_ operation: UnsupportedOperation) {
        let recorder = DisabledOperationEffectRecorder()

        let result = DisabledOperationGateway(effectObserver: recorder.record).request(operation)

        #expect(result == Self.expectedResult(for: operation))
        #expect(recorder.effects == [.requestEvaluated(operation)])
        #expect(recorder.networkRequestAttempts == 0)
    }

    private static func expectedResult(for operation: UnsupportedOperation) -> DisabledOperationResult {
        switch operation {
        case .permanentDeletion:
            return .init(operation: operation, disposition: .disabled, reason: .permanentDeletionRequiresReviewedPlan)
        case .emptyTrash:
            return .init(operation: operation, disposition: .disabled, reason: .emptyingTrashIsNotAvailable)
        case .privilegedMaintenance:
            return .init(operation: operation, disposition: .disabled, reason: .elevationIsNotAvailable)
        case .memoryPurge:
            return .init(operation: operation, disposition: .disabled, reason: .memoryPurgeIsNotAvailable)
        case .processTermination:
            return .init(operation: operation, disposition: .disabled, reason: .processTerminationIsNotAvailable)
        case .startupItemMutation:
            return .init(operation: operation, disposition: .disabled, reason: .startupMutationIsNotAvailable)
        case .developerToolMutation:
            return .init(operation: operation, disposition: .disabled, reason: .toolMutationIsNotAvailable)
        case .systemSettingsMutation:
            return .init(operation: operation, disposition: .disabled, reason: .settingsMutationIsNotAvailable)
        case .legacyCleanup:
            return .init(operation: operation, disposition: .disabled, reason: .legacyCleanupRequiresReviewedPlan)
        case .reviewedPlanCleanup:
            return .init(operation: operation, disposition: .deferred, reason: .reviewedPlanCleanupIsDeferred)
        }
    }
}

private final class DisabledOperationEffectRecorder: @unchecked Sendable {
    private var recordedEffects: [DisabledOperationEffect] = []

    var effects: [DisabledOperationEffect] {
        recordedEffects
    }

    var networkRequestAttempts: Int {
        recordedEffects.filter { effect in
            if case .networkRequestAttempted = effect { return true }
            return false
        }.count
    }

    func record(_ effect: DisabledOperationEffect) {
        recordedEffects.append(effect)
    }
}
