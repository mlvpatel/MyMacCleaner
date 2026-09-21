import Testing

@testable import CleanerCore

@Suite("CleanerCore Capability Isolation")
struct CapabilityIsolationTests {
    @Test(arguments: isolatedTerminalOutcomes)
    func evidenceScanRecordsNoPolicyExecutionOrReceiptEffects(_ terminalOutcome: ScanOutcome)
        async throws
    {
        let effectRecorder = EffectCapabilityRecorder()
        let scanPorts = IsolatedScanPorts(terminalOutcome: terminalOutcome)
        let detector = IsolationDetector()
        let coordinator = try ScanCoordinator(
            dependencies: scanPorts.dependencies,
            registry: try DetectorRegistry(registrations: [.init(detector: detector)]),
            selection: .init(id: detector.identifier, version: detector.version)
        )

        _ = await coordinator.nextBatch(
            for: try ScanRequest(
                declaredRoot: .init(id: .init("fixture-root")),
                budget: .init(maximumFindings: 1)
            ))

        #expect(effectRecorder.policy.calls.isEmpty)
        #expect(effectRecorder.execution.calls.isEmpty)
        #expect(effectRecorder.receipt.calls.isEmpty)
        #expect(scanPorts.cancellation.calls == 1)
        #expect(scanPorts.fileSystem.calls == 1)
        #expect(scanPorts.diagnostics.events == [.terminal(.init(terminalOutcome))])
        #expect(scanPorts.metrics.events == [.stepDelivered])
    }

    @Test
    func capabilityPortsAreInjectedAndRecorderVisible() async {
        let recorder = EffectCapabilityRecorder()

        _ = await recorder.policy.evaluate(PolicyInput(id: "policy"))
        _ = await recorder.execution.execute(ExecutionInput(id: "execution"))
        _ = await recorder.receipt.record(ReceiptInput(id: "receipt"))

        #expect(recorder.policy.calls == [.init(id: "policy")])
        #expect(recorder.execution.calls == [.init(id: "execution")])
        #expect(recorder.receipt.calls == [.init(id: "receipt")])
    }

    @Test
    func diagnosticTerminalCodesDropIssueIdentifiers() throws {
        let issue = ScanIssue(
            rootID: try .init("private-root-label"),
            detectorID: try .init("private.detector.label"),
            cause: .permissionDenied
        )

        #expect(ScanTerminalCode(.partial(issues: [issue])) == .partial)
    }
}

private let isolatedTerminalOutcomes: [ScanOutcome] = [
    .complete,
    .permissionDenied,
    .corruptMetadata,
    .cancelled,
]

private struct PolicyInput: Equatable, Sendable {
    let id: String
}

private struct PolicyOutput: Equatable, Sendable {
    let accepted: Bool
}

private struct ExecutionInput: Equatable, Sendable {
    let id: String
}

private struct ExecutionOutput: Equatable, Sendable {
    let moved: Bool
}

private struct ReceiptInput: Equatable, Sendable {
    let id: String
}

private struct ReceiptOutput: Equatable, Sendable {
    let durable: Bool
}

private final class EffectCapabilityRecorder: @unchecked Sendable {
    let policy = PolicyRecorder()
    let execution = ExecutionRecorder()
    let receipt = ReceiptRecorder()
}

private final class PolicyRecorder: PolicyPort, @unchecked Sendable {
    private(set) var calls: [PolicyInput] = []

    func evaluate(_ input: PolicyInput) async -> PolicyOutput {
        calls.append(input)
        return .init(accepted: false)
    }
}

private final class ExecutionRecorder: ExecutionPort, @unchecked Sendable {
    private(set) var calls: [ExecutionInput] = []

    func execute(_ input: ExecutionInput) async -> ExecutionOutput {
        calls.append(input)
        return .init(moved: false)
    }
}

private final class ReceiptRecorder: ReceiptPort, @unchecked Sendable {
    private(set) var calls: [ReceiptInput] = []

    func record(_ input: ReceiptInput) async -> ReceiptOutput {
        calls.append(input)
        return .init(durable: false)
    }
}

private final class IsolatedScanPorts: @unchecked Sendable {
    let fileSystem: IsolatedFileSystem
    let clock = IsolatedClock()
    let cancellation = IsolatedCancellation()
    let diagnostics = IsolatedDiagnostics()
    let metrics = IsolatedMetrics()

    init(terminalOutcome: ScanOutcome) {
        fileSystem = IsolatedFileSystem(terminalOutcome: terminalOutcome)
    }

    var dependencies: ScanDependencies {
        .init(
            fileSystem: fileSystem,
            clock: clock,
            cancellation: cancellation,
            diagnostics: diagnostics,
            metrics: metrics
        )
    }
}

private final class IsolatedFileSystem: FileSystemPort, @unchecked Sendable {
    let terminalOutcome: ScanOutcome
    private(set) var calls = 0

    init(terminalOutcome: ScanOutcome) {
        self.terminalOutcome = terminalOutcome
    }

    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        calls += 1
        return .terminal(terminalOutcome)
    }
}

private final class IsolatedClock: ClockPort, @unchecked Sendable {
    private(set) var calls = 0

    func now() async -> ClockReading {
        calls += 1
        return .init(
            observationInstant: .init(monotonicNanoseconds: 1),
            wallClockInstant: .init(unixNanoseconds: 2)
        )
    }
}

private final class IsolatedCancellation: CancellationPort, @unchecked Sendable {
    private(set) var calls = 0

    func isCancellationRequested() async -> Bool {
        calls += 1
        return false
    }
}

private final class IsolatedDiagnostics: DiagnosticPort, @unchecked Sendable {
    private(set) var events: [ScanDiagnosticEvent] = []

    func record(_ event: ScanDiagnosticEvent) async {
        events.append(event)
    }
}

private final class IsolatedMetrics: MetricPort, @unchecked Sendable {
    private(set) var events: [ScanMetricEvent] = []

    func record(_ event: ScanMetricEvent) async {
        events.append(event)
    }
}

private struct IsolationDetector: LocalDetector {
    let identifier = try! DetectorID("fixture.isolation")
    let version = try! DetectorVersion("1.0.0")

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        .success(nil)
    }
}
