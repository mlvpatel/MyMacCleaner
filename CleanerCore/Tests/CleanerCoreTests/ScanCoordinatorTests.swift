import Testing
@testable import CleanerCore

@Suite("CleanerCore Scan Coordinator Budgets")
struct ScanCoordinatorTests {
    @Test(arguments: invalidExpandedBudgets)
    fileprivate func expandedBudgetDimensionsFailBeforeAnyPortCall(_ testCase: InvalidExpandedBudgetCase) {
        #expect(throws: testCase.expectedError) {
            try testCase.makeBudget()
        }
    }

    @Test
    func cancellationAfterOneBoundedBatchDoesNotPullAnotherEntry() async throws {
        let rootID = try DeclaredRootID("fixture-root")
        let fileSystem = BudgetScriptedFileSystem(steps: [
            .observation(try observation(rootID: rootID, name: "first")),
            .observation(try observation(rootID: rootID, name: "second")),
        ])
        let cancellation = BudgetCancellation(responses: [false, false, true])
        let detector = BudgetDetector()
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: fileSystem,
                clock: BudgetClock(),
                cancellation: cancellation,
                diagnostics: BudgetDiagnostics(),
                metrics: BudgetMetrics()
            ),
            shippedDetector: detector
        )
        let request = try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(
                maximumFindings: 1,
                maximumObservations: 1,
                maximumDepth: 4,
                maximumEntries: 2,
                maximumBatches: 1,
                maximumObservedBytes: 128
            )
        )

        let first = await coordinator.nextBatch(for: request)
        let cancelled = await coordinator.nextBatch(for: request)

        guard case let .batch(batch) = first else {
            Issue.record("Expected one bounded batch before cancellation.")
            return
        }
        #expect(batch.findings.count == 1)
        #expect(batch.continuationCursor == ScanCursor(position: 1))
        #expect(cancelled == .terminal(.cancelled))
        #expect(fileSystem.calls == 1)
        #expect(cancellation.calls == 3)
    }

    @Test
    func depthBudgetStopsOversizedLocatorBeforeDetectorExecution() async throws {
        let rootID = try DeclaredRootID("fixture-root")
        let detector = BudgetDetector()
        let fileSystem = BudgetScriptedFileSystem(steps: [
            .observation(try observation(rootID: rootID, name: "too-deep"))
        ])
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: fileSystem,
                clock: BudgetClock(),
                cancellation: BudgetCancellation(responses: [false]),
                diagnostics: BudgetDiagnostics(),
                metrics: BudgetMetrics()
            ),
            shippedDetector: detector
        )
        let request = try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 1, maximumDepth: 1)
        )

        let result = await coordinator.nextBatch(for: request)

        #expect(result == .terminal(.unsupportedLayout))
        #expect(fileSystem.calls == 1)
        #expect(detector.calls == 0)
    }

    @Test
    func observedByteBudgetStopsOversizedObservationBeforeDetectorExecution() async throws {
        let rootID = try DeclaredRootID("fixture-root")
        let detector = BudgetDetector()
        let fileSystem = BudgetScriptedFileSystem(steps: [
            .observation(try observation(rootID: rootID, name: "oversized"))
        ])
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: fileSystem,
                clock: BudgetClock(),
                cancellation: BudgetCancellation(responses: [false]),
                diagnostics: BudgetDiagnostics(),
                metrics: BudgetMetrics()
            ),
            shippedDetector: detector
        )

        let result = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 1, maximumObservedBytes: 32)
        ))

        #expect(result == .terminal(.corruptMetadata))
        #expect(fileSystem.calls == 1)
        #expect(detector.calls == 0)
    }

    @Test
    func totalEntryBudgetEndsWithTypedTerminalOutcomeInsteadOfEmptyContinuation() async throws {
        let rootID = try DeclaredRootID("fixture-root")
        let fileSystem = BudgetScriptedFileSystem(steps: [
            .observation(try observation(rootID: rootID, name: "first")),
            .observation(try observation(rootID: rootID, name: "second")),
        ])
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: fileSystem,
                clock: BudgetClock(),
                cancellation: BudgetCancellation(responses: [false]),
                diagnostics: BudgetDiagnostics(),
                metrics: BudgetMetrics()
            ),
            shippedDetector: BudgetDetector()
        )

        let result = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 2, maximumObservations: 2, maximumEntries: 1)
        ))

        guard case let .batch(batch) = result else {
            Issue.record("Expected the retained finding with a terminal budget outcome.")
            return
        }
        #expect(batch.findings.count == 1)
        #expect(batch.continuationCursor == nil)
        #expect(batch.terminalOutcome == .partial(issues: [.init(rootID: rootID, detectorID: try DetectorID("fixture.budget"), cause: .corruptMetadata)]))
        #expect(fileSystem.calls == 1)
    }
}

fileprivate struct InvalidExpandedBudgetCase: Sendable {
    let expectedError: ScanValidationError
    let makeBudget: @Sendable () throws -> ScanBudget
}

private let invalidExpandedBudgets: [InvalidExpandedBudgetCase] = [
    .init(expectedError: .nonPositiveDepth) {
        try .init(maximumFindings: 1, maximumDepth: 0)
    },
    .init(expectedError: .excessiveDepth) {
        try .init(maximumFindings: 1, maximumDepth: ScanBudget.maximumAllowedDepth + 1)
    },
    .init(expectedError: .nonPositiveEntryBudget) {
        try .init(maximumFindings: 1, maximumEntries: 0)
    },
    .init(expectedError: .excessiveEntryBudget) {
        try .init(maximumFindings: 1, maximumEntries: ScanBudget.maximumAllowedEntries + 1)
    },
    .init(expectedError: .nonPositiveBatchBudget) {
        try .init(maximumFindings: 1, maximumBatches: 0)
    },
    .init(expectedError: .excessiveBatchBudget) {
        try .init(maximumFindings: 1, maximumBatches: ScanBudget.maximumAllowedBatches + 1)
    },
    .init(expectedError: .nonPositiveObservedByteBudget) {
        try .init(maximumFindings: 1, maximumObservedBytes: 0)
    },
    .init(expectedError: .excessiveObservedByteBudget) {
        try .init(maximumFindings: 1, maximumObservedBytes: ScanBudget.maximumAllowedObservedBytes + 1)
    },
]

private func observation(rootID: DeclaredRootID, name: String) throws -> FileObservation {
    try .init(
        rootID: rootID,
        locator: .init(rootID: rootID, components: ["budget", "\(name).bin"]),
        resourceIdentity: .unavailable,
        sizes: .init(logicalBytes: .observed(64), allocatedBytes: .unavailable),
        modification: .unavailable,
        fileKind: .regularFile,
        volume: .unavailable,
        boundaries: .init(symlink: .observed(false))
    )
}

private final class BudgetScriptedFileSystem: FileSystemPort, @unchecked Sendable {
    private var steps: [FileSystemStep]
    private(set) var calls = 0

    init(steps: [FileSystemStep]) {
        self.steps = steps
    }

    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        calls += 1
        guard !steps.isEmpty else { return .terminal(.complete) }
        return steps.removeFirst()
    }
}

private final class BudgetCancellation: CancellationPort, @unchecked Sendable {
    private var responses: [Bool]
    private(set) var calls = 0

    init(responses: [Bool]) {
        self.responses = responses
    }

    func isCancellationRequested() async -> Bool {
        calls += 1
        guard !responses.isEmpty else { return false }
        return responses.removeFirst()
    }
}

private final class BudgetDetector: LocalDetector, @unchecked Sendable {
    let identifier = try! DetectorID("fixture.budget")
    let version = try! DetectorVersion("1.0.0")
    private(set) var calls = 0

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        calls += 1
        do {
            return .success(try Finding(
                detectorID: identifier,
                detectorVersion: version,
                provenance: .filesystemObservation,
                observation: observation,
                declaredRoot: request.declaredRoot,
                observationInstant: clockReading.observationInstant
            ))
        } catch let error as EvidenceValidationError {
            return .failure(error)
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }
}

private struct BudgetClock: ClockPort {
    func now() async -> ClockReading {
        .init(
            observationInstant: .init(monotonicNanoseconds: 1),
            wallClockInstant: .init(unixNanoseconds: 2)
        )
    }
}

private struct BudgetDiagnostics: DiagnosticPort {
    func record(_ event: ScanDiagnosticEvent) async {}
}

private struct BudgetMetrics: MetricPort {
    func record(_ event: ScanMetricEvent) async {}
}
