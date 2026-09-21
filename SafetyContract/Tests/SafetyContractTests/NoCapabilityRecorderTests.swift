import Testing
@testable import SafetyContract

@Suite("No Capability Recorder")
struct NoCapabilityRecorderTests {
    @Test(arguments: UnsupportedOperation.allCases)
    func everyClosedRequestLeavesAllCapabilityCategoriesUntouched(
        _ operation: UnsupportedOperation
    ) {
        let recorder = CapabilityEffectRecorder()

        let result = DisabledOperationGateway(effectObserver: recorder.record).request(operation)

        #expect(result.operation == operation)
        #expect(recorder.effects == [.requestEvaluated(operation)])
        #expect(recorder.dangerousEffectCount == 0)
    }
}

private final class CapabilityEffectRecorder: @unchecked Sendable {
    private(set) var effects: [DisabledOperationEffect] = []

    var dangerousEffectCount: Int {
        effects.reduce(into: 0) { count, effect in
            if case .requestEvaluated = effect { return }
            count += 1
        }
    }

    func record(_ effect: DisabledOperationEffect) {
        effects.append(effect)
    }
}
