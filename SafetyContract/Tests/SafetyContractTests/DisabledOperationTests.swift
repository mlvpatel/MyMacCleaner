import Testing
@testable import SafetyContract

@Suite("Disabled Operation Gateway")
struct DisabledOperationTests {
    @Test
    func expectationTableCoversEveryUnsupportedOperation() {
        #expect(Self.expectations.count == UnsupportedOperation.allCases.count)

        for operation in UnsupportedOperation.allCases {
            #expect(Self.expectations.contains { $0.operation == operation })
        }
    }

    @Test(arguments: expectations)
    func everyLegacyOperationHasAnExactClosedResult(
        _ expectation: OperationExpectation
    ) {
        let result = DisabledOperationGateway().request(expectation.operation)

        #expect(result.operation == expectation.operation)
        #expect(result.disposition == expectation.disposition)
        #expect(result.reason == expectation.reason)
    }

    @Test(arguments: expectations)
    func everyLegacyOperationHasStableInformationalPresentation(
        _ expectation: OperationExpectation
    ) {
        let presentation = DisabledOperationPresentation.forOperation(expectation.operation)

        #expect(presentation.tone == .informational)
        #expect(presentation.title == expectation.title)
        #expect(presentation.message == expectation.message)
        #expect(presentation.actionTitle == "Learn why")
    }

    private static let expectations: [OperationExpectation] = [
        .init(.permanentDeletion, .disabled, .permanentDeletionRequiresReviewedPlan, "Permanent deletion is unavailable", "MyMacCleaner will not permanently delete files."),
        .init(.emptyTrash, .disabled, .emptyingTrashIsNotAvailable, "Empty Trash is unavailable", "MyMacCleaner will not empty Trash automatically."),
        .init(.privilegedMaintenance, .disabled, .elevationIsNotAvailable, "Privileged maintenance is unavailable", "MyMacCleaner will not request administrator access for maintenance."),
        .init(.memoryPurge, .disabled, .memoryPurgeIsNotAvailable, "Memory purge is unavailable", "MyMacCleaner provides memory guidance without purging memory."),
        .init(.processTermination, .disabled, .processTerminationIsNotAvailable, "Process termination is unavailable", "MyMacCleaner will not terminate processes."),
        .init(.startupItemMutation, .disabled, .startupMutationIsNotAvailable, "Startup changes are unavailable", "MyMacCleaner will not change startup items."),
        .init(.developerToolMutation, .disabled, .toolMutationIsNotAvailable, "Developer tool changes are unavailable", "MyMacCleaner will not change developer tools."),
        .init(.systemSettingsMutation, .disabled, .settingsMutationIsNotAvailable, "System setting changes are unavailable", "MyMacCleaner will not change system settings."),
        .init(.legacyCleanup, .disabled, .legacyCleanupRequiresReviewedPlan, "Legacy cleanup is unavailable", "MyMacCleaner requires a reviewed cleanup plan before changing files."),
        .init(.reviewedPlanCleanup, .deferred, .reviewedPlanCleanupIsDeferred, "Reviewed cleanup plans are coming later", "MyMacCleaner will offer reviewed cleanup plans after the safety pipeline is ready.")
    ]
}

struct OperationExpectation: Sendable {
    let operation: UnsupportedOperation
    let disposition: DisabledOperationDisposition
    let reason: DisabledOperationReason
    let title: String
    let message: String

    init(
        _ operation: UnsupportedOperation,
        _ disposition: DisabledOperationDisposition,
        _ reason: DisabledOperationReason,
        _ title: String,
        _ message: String
    ) {
        self.operation = operation
        self.disposition = disposition
        self.reason = reason
        self.title = title
        self.message = message
    }
}
