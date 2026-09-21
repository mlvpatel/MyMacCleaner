import Testing

@testable import CleanerCore

@Suite("CleanerCore Scan Outcomes")
struct OutcomeTests {
    @Test(arguments: outcomeAggregationCases)
    fileprivate func aggregateOutcomeDoesNotUpgradeIncompleteEvidence(
        _ testCase: OutcomeAggregationCase
    ) throws {
        let outcome = ScanOutcome.aggregate(
            completedRootCount: testCase.completedRootCount,
            issues: testCase.issues
        )

        #expect(outcome == testCase.expectedOutcome)
    }

    @Test
    func cancellationHasDeterministicPrecedenceAndRetainsEveryIssueAfterCompletion() throws {
        let denied = try issue(root: "fixture-denied", cause: .permissionDenied)
        let cancelled = try issue(root: "fixture-cancelled", cause: .cancelled)

        #expect(
            ScanOutcome.aggregate(completedRootCount: 0, issues: [denied, cancelled]) == .cancelled)
        #expect(
            ScanOutcome.aggregate(completedRootCount: 1, issues: [denied, cancelled])
                == .partial(issues: [
                    cancelled, denied,
                ]))
    }

    @Test
    func everyPairwiseCauseProgressionRemainsIncompleteAndRetainsIssues() throws {
        for firstCause in CoreErrorCause.allCases {
            for secondCause in CoreErrorCause.allCases {
                let firstIssue = try issue(root: "fixture-first", cause: firstCause)
                let secondIssue = try issue(root: "fixture-second", cause: secondCause)
                let withoutCompletedRoot = ScanOutcome.aggregate(
                    completedRootCount: 0,
                    issues: [firstIssue, secondIssue]
                )
                let withCompletedRoot = ScanOutcome.aggregate(
                    completedRootCount: 1,
                    issues: [firstIssue, secondIssue]
                )

                #expect(withoutCompletedRoot != .complete)
                guard case .partial(let issues) = withCompletedRoot else {
                    Issue.record(
                        "Completed evidence must turn every later cause pair into a partial outcome."
                    )
                    return
                }
                #expect(issues.count == 2)
                #expect(issues.contains(firstIssue))
                #expect(issues.contains(secondIssue))
            }
        }
    }

    @Test
    func terminalOutcomeVocabularyIsClosedAndExplicit() throws {
        let issue = try issue(root: "fixture-root", cause: .permissionDenied)
        let outcomes: [ScanOutcome] = [
            .complete,
            .partial(issues: [issue]),
            .permissionDenied,
            .cancelled,
            .corruptMetadata,
            .unsupportedLayout,
        ]

        #expect(outcomes.map(outcomeCode) == [0, 1, 2, 3, 4, 5])
    }

    @Test
    func successfulRootEvidenceIsRetainedWhenALaterRootIsDenied() async throws {
        let firstRoot = try DeclaredRootID("fixture-first-root")
        let secondRoot = try DeclaredRootID("fixture-second-root")
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: OutcomeScriptedFileSystem(stepsByRoot: [
                    firstRoot: [
                        .observation(try observation(rootID: firstRoot, name: "kept")),
                        .terminal(.complete),
                    ],
                    secondRoot: [.terminal(.permissionDenied)],
                ]),
                clock: FixedOutcomeClock(),
                cancellation: NeverCancelled(),
                diagnostics: OutcomeDiagnostics(),
                metrics: OutcomeMetrics()
            ),
            shippedDetector: OutcomeDetector()
        )
        let request = try ScanRequest(
            declaredRoots: [.init(id: firstRoot), .init(id: secondRoot)],
            budget: .init(maximumFindings: 2, maximumObservations: 3)
        )

        let step = await coordinator.nextBatch(for: request)

        guard case .batch(let batch) = step else {
            Issue.record("Expected the evidence batch to retain the first root finding.")
            return
        }
        #expect(batch.findings.map(\.declaredRoot.id) == [firstRoot])
        #expect(batch.continuationCursor == nil)
        #expect(
            batch.terminalOutcome
                == .partial(issues: [
                    .init(
                        rootID: secondRoot, detectorID: try DetectorID("fixture.outcome"),
                        cause: .permissionDenied)
                ]))
    }

    @Test
    func readableEmptyRootIsCompleteRatherThanMissingEvidence() async throws {
        let rootID = try DeclaredRootID("fixture-empty-root")
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: ScriptedFileSystem(stepsByRoot: [rootID: [.terminal(.complete)]]),
                clock: FixedOutcomeClock(),
                cancellation: NeverCancelled(),
                diagnostics: OutcomeDiagnostics(),
                metrics: OutcomeMetrics()
            ),
            shippedDetector: OutcomeDetector()
        )

        let step = await coordinator.nextBatch(
            for: try ScanRequest(
                declaredRoot: .init(id: rootID),
                budget: .init(maximumFindings: 1)
            ))

        #expect(step == .terminal(.complete))
    }

    @Test
    func deniedOnlyRootReturnsExactDeniedOutcomeInsteadOfEmptySuccess() async throws {
        let rootID = try DeclaredRootID("fixture-denied-root")
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: ScriptedFileSystem(stepsByRoot: [rootID: [.terminal(.permissionDenied)]]
                ),
                clock: FixedOutcomeClock(),
                cancellation: NeverCancelled(),
                diagnostics: OutcomeDiagnostics(),
                metrics: OutcomeMetrics()
            ),
            shippedDetector: OutcomeDetector()
        )
        let step = await coordinator.nextBatch(
            for: try ScanRequest(
                declaredRoot: .init(id: rootID),
                budget: .init(maximumFindings: 1)
            ))

        #expect(step == .terminal(.permissionDenied))
    }
}

private func outcomeCode(_ outcome: ScanOutcome) -> Int {
    switch outcome {
    case .complete:
        return 0
    case .partial:
        return 1
    case .permissionDenied:
        return 2
    case .cancelled:
        return 3
    case .corruptMetadata:
        return 4
    case .unsupportedLayout:
        return 5
    }
}

private struct OutcomeAggregationCase: Sendable {
    let completedRootCount: Int
    let issues: [ScanIssue]
    let expectedOutcome: ScanOutcome
}

private let outcomeAggregationCases: [OutcomeAggregationCase] = [
    .init(completedRootCount: 0, issues: [], expectedOutcome: .complete),
    .init(
        completedRootCount: 0,
        issues: [try! issue(root: "fixture-denied", cause: .permissionDenied)],
        expectedOutcome: .permissionDenied),
    .init(
        completedRootCount: 0, issues: [try! issue(root: "fixture-cancelled", cause: .cancelled)],
        expectedOutcome: .cancelled),
    .init(
        completedRootCount: 0,
        issues: [try! issue(root: "fixture-corrupt", cause: .corruptMetadata)],
        expectedOutcome: .corruptMetadata),
    .init(
        completedRootCount: 0,
        issues: [try! issue(root: "fixture-unsupported", cause: .unsupportedLayout)],
        expectedOutcome: .unsupportedLayout),
    .init(
        completedRootCount: 1,
        issues: [try! issue(root: "fixture-denied", cause: .permissionDenied)],
        expectedOutcome: .partial(issues: [
            try! issue(root: "fixture-denied", cause: .permissionDenied)
        ]
        )),
    .init(
        completedRootCount: 2,
        issues: [try! issue(root: "fixture-corrupt", cause: .corruptMetadata)],
        expectedOutcome: .partial(issues: [
            try! issue(root: "fixture-corrupt", cause: .corruptMetadata)
        ]
        )),
    .init(
        completedRootCount: 1,
        issues: [
            try! issue(root: "fixture-denied", cause: .permissionDenied),
            try! issue(root: "fixture-unsupported", cause: .unsupportedLayout),
        ],
        expectedOutcome: .partial(issues: [
            try! issue(root: "fixture-denied", cause: .permissionDenied),
            try! issue(root: "fixture-unsupported", cause: .unsupportedLayout),
        ])),
]

private func issue(root: String, cause: CoreErrorCause) throws -> ScanIssue {
    try .init(
        rootID: .init(root),
        detectorID: .init("fixture.outcome"),
        cause: cause
    )
}

private func observation(rootID: DeclaredRootID, name: String) throws -> FileObservation {
    try .init(
        rootID: rootID,
        locator: .init(rootID: rootID, components: ["fixture", "\(name).bin"]),
        resourceIdentity: .unavailable,
        sizes: .init(logicalBytes: .observed(1), allocatedBytes: .unavailable),
        modification: .unavailable,
        fileKind: .regularFile,
        volume: .unavailable,
        boundaries: .init(symlink: .observed(false))
    )
}

private struct OutcomeDetector: LocalDetector {
    let identifier = try! DetectorID("fixture.outcome")
    let version = try! DetectorVersion("1.0.0")

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        do {
            return .success(
                try Finding(
                    detectorID: identifier,
                    detectorVersion: version,
                    provenance: .filesystemObservation,
                    observation: observation,
                    declaredRoot: .init(id: observation.rootID),
                    observationInstant: clockReading.observationInstant
                ))
        } catch let error as EvidenceValidationError {
            return .failure(error)
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }
}

private final class OutcomeScriptedFileSystem: FileSystemPort, @unchecked Sendable {
    private var stepsByRoot: [DeclaredRootID: [FileSystemStep]]

    init(stepsByRoot: [DeclaredRootID: [FileSystemStep]]) {
        self.stepsByRoot = stepsByRoot
    }

    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        guard var remaining = stepsByRoot[root.id], !remaining.isEmpty else {
            return .terminal(.complete)
        }
        let step = remaining.removeFirst()
        stepsByRoot[root.id] = remaining
        return step
    }
}

private struct FixedOutcomeClock: ClockPort {
    func now() async -> ClockReading {
        .init(
            observationInstant: .init(monotonicNanoseconds: 1),
            wallClockInstant: .init(unixNanoseconds: 2)
        )
    }
}

private struct NeverCancelled: CancellationPort {
    func isCancellationRequested() async -> Bool { false }
}

private struct OutcomeDiagnostics: DiagnosticPort {
    func record(_ event: ScanDiagnosticEvent) async {}
}

private struct OutcomeMetrics: MetricPort {
    func record(_ event: ScanMetricEvent) async {}
}
