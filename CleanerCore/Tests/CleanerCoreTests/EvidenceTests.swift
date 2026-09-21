import Testing
@testable import CleanerCore

@Suite("CleanerCore Evidence Errors")
struct EvidenceTests {
    @Test(arguments: CoreErrorCause.allCases)
    func everyCoreCauseHasAStableSensitiveSafePresentation(_ cause: CoreErrorCause) {
        let presentation = UserPresentableError(cause: cause)

        #expect(presentation.code == "cleanercore.error.\(cause.rawValue)")
        #expect(presentation.localizationKey == "cleanercore.error.\(cause.rawValue).message")
        #expect([.validation, .scan, .detector].contains(presentation.context))
        #expect(!presentation.code.contains("fixture"))
        #expect(!presentation.localizationKey.contains("fixture"))
    }

    @Test(arguments: validationCases)
    fileprivate func validationFailuresMapToStableCoreCauses(_ testCase: ValidationCauseCase) {
        #expect(testCase.error.coreErrorCause == testCase.expectedCause)
        #expect(UserPresentableError(cause: testCase.error.coreErrorCause).context == .validation)
    }

    @Test(arguments: scanValidationCases)
    fileprivate func scanValidationFailuresMapToStableCoreCauses(_ testCase: ScanValidationCauseCase) {
        #expect(testCase.error.coreErrorCause == testCase.expectedCause)
        #expect(UserPresentableError(cause: testCase.error.coreErrorCause).context == .validation)
    }
}

fileprivate struct ValidationCauseCase: Sendable {
    let error: EvidenceValidationError
    let expectedCause: CoreErrorCause
}

private let validationCases: [ValidationCauseCase] = [
    .init(error: .emptyIdentifier, expectedCause: .invalidRoot),
    .init(error: .negativeSize, expectedCause: .invalidMeasurement),
    .init(error: .invalidRelativeLocator, expectedCause: .invalidLocator),
    .init(error: .mismatchedRootIdentity, expectedCause: .invalidRoot)
]

fileprivate struct ScanValidationCauseCase: Sendable {
    let error: ScanValidationError
    let expectedCause: CoreErrorCause
}

private let scanValidationCases: [ScanValidationCauseCase] = [
    .init(error: .nonPositiveBudget, expectedCause: .invalidBudget),
    .init(error: .excessiveBudget, expectedCause: .invalidBudget),
    .init(error: .nonPositiveObservationBudget, expectedCause: .invalidBudget),
    .init(error: .excessiveObservationBudget, expectedCause: .invalidBudget),
    .init(error: .nonPositiveDepth, expectedCause: .invalidBudget),
    .init(error: .excessiveDepth, expectedCause: .invalidBudget),
    .init(error: .nonPositiveEntryBudget, expectedCause: .invalidBudget),
    .init(error: .excessiveEntryBudget, expectedCause: .invalidBudget),
    .init(error: .nonPositiveBatchBudget, expectedCause: .invalidBudget),
    .init(error: .excessiveBatchBudget, expectedCause: .invalidBudget),
    .init(error: .nonPositiveObservedByteBudget, expectedCause: .invalidBudget),
    .init(error: .excessiveObservedByteBudget, expectedCause: .invalidBudget),
    .init(error: .emptyDeclaredRoots, expectedCause: .invalidRoot),
    .init(error: .duplicateDeclaredRoot, expectedCause: .invalidRoot)
]
