import Testing

@testable import CleanerCore

@Suite("CleanerCore Per-Root Scan Budgets")
struct PerRootBudgetTests {
    @Test
    func phaseTwoLimitsAreRepresentableAndHaveCheckedGlobalBounds() throws {
        let budget = try ScanBudget(
            maximumFindings: 128,
            maximumObservations: 128,
            maximumDepth: 8,
            maximumEntries: 25_000,
            maximumBatches: 1_200,
            maximumObservedBytes: 1_099_511_627_776,
            maximumFindingsPerRoot: 10_000,
            maximumRootsPerRequest: 6
        )

        #expect(budget.maximumFindings == 128)
        #expect(budget.maximumObservations == 128)
        #expect(budget.maximumEntriesPerRoot == 25_000)
        #expect(budget.maximumFindingsPerRoot == 10_000)
        #expect(budget.maximumObservedBytesPerRoot == 1_099_511_627_776)
        #expect(budget.maximumRootsPerRequest == 6)
        #expect(budget.maximumBatches == 1_200)
        #expect(budget.maximumTotalEntries == 150_000)
        #expect(budget.maximumTotalFindings == 60_000)
        #expect(budget.maximumTotalObservedBytes == 6_597_069_766_656)
        #expect(ScanBudget.maximumAllowedBatches == 2_048)
    }

    @Test
    func phaseOneEntryAndBatchDefaultsRemainStable() throws {
        let budget = try ScanBudget(maximumFindings: 1)

        #expect(budget.maximumEntriesPerRoot == 4_096)
        #expect(budget.maximumBatches == 256)
    }

    @Test
    func checkedGlobalBoundArithmeticRejectsOverflow() {
        #expect(throws: ScanValidationError.excessiveEntryBudget) {
            try ScanBudget.checkedTotalEntries(
                maximumEntriesPerRoot: Int.max,
                maximumRootsPerRequest: 2
            )
        }
        #expect(throws: ScanValidationError.excessivePerRootFindingBudget) {
            try ScanBudget.checkedTotalFindings(
                maximumFindingsPerRoot: Int.max,
                maximumRootsPerRequest: 2
            )
        }
        #expect(throws: ScanValidationError.excessiveObservedByteBudget) {
            try ScanBudget.checkedTotalObservedBytes(
                maximumObservedBytesPerRoot: Int64.max,
                maximumRootsPerRequest: 2
            )
        }
    }

    @Test
    func invalidPerRootAndRootCountLimitsFailDuringBudgetConstruction() {
        #expect(throws: ScanValidationError.nonPositivePerRootFindingBudget) {
            try ScanBudget(maximumFindings: 1, maximumFindingsPerRoot: 0)
        }
        #expect(throws: ScanValidationError.excessivePerRootFindingBudget) {
            try ScanBudget(
                maximumFindings: 1,
                maximumFindingsPerRoot: ScanBudget.maximumAllowedFindingsPerRoot + 1
            )
        }
        #expect(throws: ScanValidationError.nonPositiveRootBudget) {
            try ScanBudget(maximumFindings: 1, maximumRootsPerRequest: 0)
        }
        #expect(throws: ScanValidationError.excessiveRootBudget) {
            try ScanBudget(
                maximumFindings: 1,
                maximumRootsPerRequest: ScanBudget.maximumAllowedRootsPerRequest + 1
            )
        }
    }

    @Test
    func excessAndDuplicateRootsFailBeforeAnyPortCanBeCalled() throws {
        let firstRoot = try DeclaredRootID("fixture-root-1")
        let secondRoot = try DeclaredRootID("fixture-root-2")
        let oneRootBudget = try ScanBudget(
            maximumFindings: 1,
            maximumRootsPerRequest: 1
        )

        #expect(throws: ScanValidationError.excessiveDeclaredRoots) {
            try ScanRequest(
                declaredRoots: [.init(id: firstRoot), .init(id: secondRoot)],
                budget: oneRootBudget
            )
        }
        #expect(throws: ScanValidationError.duplicateDeclaredRoot) {
            try ScanRequest(
                declaredRoots: [.init(id: firstRoot), .init(id: firstRoot)],
                budget: try ScanBudget(maximumFindings: 1)
            )
        }
    }

    @Test
    func entriesFindingsAndBytesResetOnlyAfterEachCompleteRoot() async throws {
        let firstRoot = try DeclaredRootID("fixture-root-1")
        let secondRoot = try DeclaredRootID("fixture-root-2")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            firstRoot: [
                .observation(try perRootObservation(rootID: firstRoot, name: "first-a")),
                .observation(try perRootObservation(rootID: firstRoot, name: "first-b")),
                .terminal(.complete),
            ],
            secondRoot: [
                .observation(try perRootObservation(rootID: secondRoot, name: "second-a")),
                .observation(try perRootObservation(rootID: secondRoot, name: "second-b")),
                .terminal(.complete),
            ],
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoots: [.init(id: firstRoot), .init(id: secondRoot)],
            budget: .init(
                maximumFindings: 8,
                maximumObservations: 8,
                maximumEntries: 3,
                maximumBatches: 8,
                maximumObservedBytes: 96,
                maximumFindingsPerRoot: 3,
                maximumRootsPerRequest: 2
            )
        )

        let step = await coordinator.nextBatch(for: request)

        guard case let .batch(batch) = step else {
            Issue.record("Expected findings from both independently budgeted roots.")
            return
        }
        #expect(batch.findings.map(\.declaredRoot.id) == [
            firstRoot, firstRoot, secondRoot, secondRoot,
        ])
        #expect(batch.continuationCursor == nil)
        #expect(batch.terminalOutcome == .complete)
        #expect(fileSystem.calls == [
            .init(rootID: firstRoot, cursor: nil),
            .init(rootID: firstRoot, cursor: .init(position: 1)),
            .init(rootID: firstRoot, cursor: .init(position: 2)),
            .init(rootID: secondRoot, cursor: nil),
            .init(rootID: secondRoot, cursor: .init(position: 1)),
            .init(rootID: secondRoot, cursor: .init(position: 2)),
        ])
    }

    @Test
    func perRootFindingCapStopsBeforeAnotherPortCall() async throws {
        let rootID = try DeclaredRootID("fixture-capped-root")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            rootID: [
                .observation(try perRootObservation(rootID: rootID, name: "kept")),
                .observation(try perRootObservation(rootID: rootID, name: "must-not-open")),
            ]
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 25_000,
                maximumBatches: 1_200,
                maximumFindingsPerRoot: 1
            )
        )

        let step = await coordinator.nextBatch(for: request)

        guard case let .batch(batch) = step else {
            Issue.record("Expected the retained finding and a typed cap outcome.")
            return
        }
        #expect(batch.findings.count == 1)
        #expect(batch.terminalOutcome == .partial(issues: [.init(rootID: rootID, detectorID: try DetectorID("fixture.per-root"), cause: .corruptMetadata)]))
        #expect(batch.continuationCursor == nil)
        #expect(fileSystem.calls.count == 1)
    }

    @Test
    func perRootEntryCapStopsBeforeAnotherPortCall() async throws {
        let rootID = try DeclaredRootID("fixture-entry-capped-root")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            rootID: [
                .observation(try perRootObservation(rootID: rootID, name: "kept")),
                .observation(try perRootObservation(rootID: rootID, name: "must-not-open")),
            ]
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 1,
                maximumBatches: 1_200,
                maximumFindingsPerRoot: 10_000
            )
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: request) else {
            Issue.record("Expected retained evidence at the per-root entry cap.")
            return
        }
        #expect(batch.findings.count == 1)
        #expect(batch.terminalOutcome == .partial(issues: [.init(rootID: rootID, detectorID: try DetectorID("fixture.per-root"), cause: .corruptMetadata)]))
        #expect(batch.continuationCursor == nil)
        #expect(fileSystem.calls.count == 1)
    }

    @Test
    func laterRootCapRetainsPriorEvidenceAndAggregatesPartialOutcome() async throws {
        let completedRoot = try DeclaredRootID("fixture-cap-completed-root")
        let cappedRoot = try DeclaredRootID("fixture-cap-later-root")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            completedRoot: [
                .observation(try perRootObservation(rootID: completedRoot, name: "complete")),
                .terminal(.complete),
            ],
            cappedRoot: [
                .observation(try perRootObservation(rootID: cappedRoot, name: "kept-a")),
                .observation(try perRootObservation(rootID: cappedRoot, name: "kept-b")),
                .observation(try perRootObservation(rootID: cappedRoot, name: "must-not-open")),
            ],
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoots: [.init(id: completedRoot), .init(id: cappedRoot)],
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 2,
                maximumBatches: 1_200,
                maximumFindingsPerRoot: 10_000,
                maximumRootsPerRequest: 2
            )
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: request) else {
            Issue.record("Expected retained findings and a partial later-root cap outcome.")
            return
        }
        #expect(batch.findings.map(\.declaredRoot.id) == [
            completedRoot, cappedRoot, cappedRoot,
        ])
        #expect(batch.terminalOutcome == .partial(issues: [
            .init(
                rootID: cappedRoot,
                detectorID: try DetectorID("fixture.per-root"),
                cause: .corruptMetadata
            )
        ]))
        #expect(fileSystem.calls.map(\.rootID) == [
            completedRoot, completedRoot, cappedRoot, cappedRoot,
        ])
    }

    @Test
    func earlierRootCapStillScansTheNextRootWithAFreshBudget() async throws {
        let cappedRoot = try DeclaredRootID("fixture-cap-first-root")
        let laterRoot = try DeclaredRootID("fixture-cap-next-root")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            cappedRoot: [
                .observation(try perRootObservation(rootID: cappedRoot, name: "kept-a")),
                .observation(try perRootObservation(rootID: cappedRoot, name: "kept-b")),
                .observation(try perRootObservation(rootID: cappedRoot, name: "must-not-open")),
            ],
            laterRoot: [
                .observation(try perRootObservation(rootID: laterRoot, name: "next")),
                .terminal(.complete),
            ],
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoots: [.init(id: cappedRoot), .init(id: laterRoot)],
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 2,
                maximumBatches: 1_200,
                maximumFindingsPerRoot: 10_000,
                maximumRootsPerRequest: 2
            )
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: request) else {
            Issue.record("Expected evidence from both roots.")
            return
        }
        #expect(batch.findings.map(\.declaredRoot.id) == [cappedRoot, cappedRoot, laterRoot])
        #expect(batch.terminalOutcome == .partial(issues: [
            .init(
                rootID: cappedRoot,
                detectorID: try DetectorID("fixture.per-root"),
                cause: .corruptMetadata
            )
        ]))
        #expect(fileSystem.calls.map(\.rootID) == [cappedRoot, cappedRoot, laterRoot, laterRoot])
    }

    @Test
    func rootsThatFaultAfterDeliveringEvidenceStillReadAsPartial() async throws {
        let firstRoot = try DeclaredRootID("fixture-fault-first-root")
        let secondRoot = try DeclaredRootID("fixture-fault-second-root")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            firstRoot: [
                .observation(try perRootObservation(rootID: firstRoot, name: "kept")),
                .terminal(.permissionDenied),
            ],
            secondRoot: [
                .observation(try perRootObservation(rootID: secondRoot, name: "kept")),
                .terminal(.unsupportedLayout),
            ],
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoots: [.init(id: firstRoot), .init(id: secondRoot)],
            budget: .init(maximumFindings: 128, maximumRootsPerRequest: 2)
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: request) else {
            Issue.record("Expected evidence from both roots.")
            return
        }
        let detectorID = try DetectorID("fixture.per-root")
        #expect(batch.findings.map(\.declaredRoot.id) == [firstRoot, secondRoot])
        #expect(batch.terminalOutcome == .partial(issues: [
            .init(rootID: firstRoot, detectorID: detectorID, cause: .permissionDenied),
            .init(rootID: secondRoot, detectorID: detectorID, cause: .unsupportedLayout),
        ]))
    }

    @Test
    func perRootByteCapAndOversizedObservationNeverPullAnotherEntry() async throws {
        let exactRoot = try DeclaredRootID("fixture-byte-capped-root")
        let exactFileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            exactRoot: [
                .observation(try perRootObservation(rootID: exactRoot, name: "exact")),
                .observation(try perRootObservation(rootID: exactRoot, name: "must-not-open")),
            ]
        ])
        let exactCoordinator = try makePerRootCoordinator(fileSystem: exactFileSystem)
        let exactRequest = try ScanRequest(
            declaredRoot: .init(id: exactRoot),
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 25_000,
                maximumBatches: 1_200,
                maximumObservedBytes: 32,
                maximumFindingsPerRoot: 10_000
            )
        )

        guard case let .batch(exactBatch) = await exactCoordinator.nextBatch(for: exactRequest) else {
            Issue.record("Expected retained evidence at the exact byte cap.")
            return
        }
        #expect(exactBatch.findings.count == 1)
        #expect(exactBatch.terminalOutcome == .partial(issues: [.init(rootID: exactRoot, detectorID: try DetectorID("fixture.per-root"), cause: .corruptMetadata)]))
        #expect(exactFileSystem.calls.count == 1)

        let oversizedRoot = try DeclaredRootID("fixture-byte-overflow-root")
        let oversizedFileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            oversizedRoot: [
                .observation(try perRootObservation(
                    rootID: oversizedRoot,
                    name: "oversized",
                    logicalBytes: Int64.max
                )),
                .observation(try perRootObservation(
                    rootID: oversizedRoot,
                    name: "must-not-open"
                )),
            ]
        ])
        let oversizedCoordinator = try makePerRootCoordinator(fileSystem: oversizedFileSystem)
        let oversizedRequest = try ScanRequest(
            declaredRoot: .init(id: oversizedRoot),
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 25_000,
                maximumBatches: 1_200,
                maximumObservedBytes: 32,
                maximumFindingsPerRoot: 10_000
            )
        )

        #expect(
            await oversizedCoordinator.nextBatch(for: oversizedRequest)
                == .terminal(.corruptMetadata)
        )
        #expect(oversizedFileSystem.calls.count == 1)
    }

    @Test
    func cancellationInLaterRootRetainsEarlierAndCurrentRootEvidence() async throws {
        let firstRoot = try DeclaredRootID("fixture-complete-root")
        let secondRoot = try DeclaredRootID("fixture-cancelled-root")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            firstRoot: [
                .observation(try perRootObservation(rootID: firstRoot, name: "complete")),
                .terminal(.complete),
            ],
            secondRoot: [
                .observation(try perRootObservation(rootID: secondRoot, name: "before-cancel")),
                .observation(try perRootObservation(rootID: secondRoot, name: "must-not-open")),
            ],
        ])
        let cancellation = PerRootCancellation(responses: [false, false, false, true])
        let coordinator = try makePerRootCoordinator(
            fileSystem: fileSystem,
            cancellation: cancellation
        )
        let request = try ScanRequest(
            declaredRoots: [.init(id: firstRoot), .init(id: secondRoot)],
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 25_000,
                maximumBatches: 1_200,
                maximumFindingsPerRoot: 10_000,
                maximumRootsPerRequest: 2
            )
        )

        let step = await coordinator.nextBatch(for: request)

        guard case let .batch(batch) = step else {
            Issue.record("Expected retained findings and partial cancellation evidence.")
            return
        }
        #expect(batch.findings.map(\.declaredRoot.id) == [firstRoot, secondRoot])
        #expect(batch.terminalOutcome == .partial(issues: [
            .init(
                rootID: secondRoot,
                detectorID: try DetectorID("fixture.per-root"),
                cause: .cancelled
            )
        ]))
        #expect(batch.continuationCursor == nil)
        #expect(fileSystem.calls.count == 3)
    }

    @Test
    func failedRootIsRecordedAndLaterRootsAreStillScanned() async throws {
        let completedRoot = try DeclaredRootID("fixture-completed-root")
        let failedRoot = try DeclaredRootID("fixture-failed-root")
        let laterRoot = try DeclaredRootID("fixture-later-root")
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            completedRoot: [
                .observation(try perRootObservation(rootID: completedRoot, name: "complete")),
                .terminal(.complete),
            ],
            failedRoot: [
                .observation(try perRootObservation(rootID: failedRoot, name: "retained")),
                .terminal(.permissionDenied),
            ],
            laterRoot: [
                .observation(try perRootObservation(rootID: laterRoot, name: "still-scanned")),
                .terminal(.complete),
            ],
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoots: [
                .init(id: completedRoot),
                .init(id: failedRoot),
                .init(id: laterRoot),
            ],
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 25_000,
                maximumBatches: 1_200,
                maximumFindingsPerRoot: 10_000,
                maximumRootsPerRequest: 3
            )
        )

        let firstStep = await coordinator.nextBatch(for: request)
        let repeatedTerminal = await coordinator.nextBatch(for: request)

        guard case let .batch(batch) = firstStep else {
            Issue.record("Expected retained evidence from every root.")
            return
        }
        let expectedOutcome = ScanOutcome.partial(issues: [
            .init(
                rootID: failedRoot,
                detectorID: try DetectorID("fixture.per-root"),
                cause: .permissionDenied
            )
        ])
        #expect(batch.findings.map(\.declaredRoot.id) == [completedRoot, failedRoot, laterRoot])
        #expect(batch.terminalOutcome == expectedOutcome)
        #expect(repeatedTerminal == .terminal(expectedOutcome))
        #expect(fileSystem.calls == [
            .init(rootID: completedRoot, cursor: nil),
            .init(rootID: completedRoot, cursor: .init(position: 1)),
            .init(rootID: failedRoot, cursor: nil),
            .init(rootID: failedRoot, cursor: .init(position: 1)),
            .init(rootID: laterRoot, cursor: nil),
            .init(rootID: laterRoot, cursor: .init(position: 1)),
        ])
    }

    @Test
    func phaseTwoBatchCanPublishOneHundredTwentyEightFindings() async throws {
        let rootID = try DeclaredRootID("fixture-batch-root")
        let observations = try (0 ..< 128).map { index in
            FileSystemStep.observation(
                try perRootObservation(rootID: rootID, name: "entry-\(index)")
            )
        }
        let fileSystem = PerRootScriptedFileSystem(stepsByRoot: [
            rootID: observations + [.terminal(.complete)]
        ])
        let coordinator = try makePerRootCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(
                maximumFindings: 128,
                maximumObservations: 128,
                maximumEntries: 25_000,
                maximumBatches: 1_200,
                maximumFindingsPerRoot: 10_000
            )
        )

        let batchStep = await coordinator.nextBatch(for: request)
        let terminalStep = await coordinator.nextBatch(for: request)

        guard case let .batch(batch) = batchStep else {
            Issue.record("Expected a 128-finding batch.")
            return
        }
        #expect(batch.findings.count == 128)
        #expect(batch.continuationCursor == .init(position: 128))
        #expect(terminalStep == .terminal(.complete))
        #expect(fileSystem.calls.count == 129)
    }
}

private func makePerRootCoordinator(
    fileSystem: PerRootScriptedFileSystem,
    cancellation: PerRootCancellation = .init()
) throws -> ScanCoordinator {
    try ScanCoordinator(
        dependencies: .init(
            fileSystem: fileSystem,
            clock: PerRootClock(),
            cancellation: cancellation,
            diagnostics: PerRootDiagnostics(),
            metrics: PerRootMetrics()
        ),
        shippedDetector: PerRootDetector()
    )
}

private func perRootObservation(
    rootID: DeclaredRootID,
    name: String,
    logicalBytes: Int64 = 32
) throws -> FileObservation {
    try .init(
        rootID: rootID,
        locator: .init(rootID: rootID, components: ["budget", "\(name).bin"]),
        resourceIdentity: .unavailable,
        sizes: .init(logicalBytes: .observed(logicalBytes), allocatedBytes: .unavailable),
        modification: .unavailable,
        fileKind: .regularFile,
        volume: .unavailable,
        boundaries: .init(symlink: .observed(false))
    )
}

private final class PerRootScriptedFileSystem: FileSystemPort, @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let rootID: DeclaredRootID
        let cursor: ScanCursor?
    }

    private var stepsByRoot: [DeclaredRootID: [FileSystemStep]]
    private(set) var calls: [Call] = []

    init(stepsByRoot: [DeclaredRootID: [FileSystemStep]]) {
        self.stepsByRoot = stepsByRoot
    }

    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        calls.append(.init(rootID: root.id, cursor: cursor))
        guard var steps = stepsByRoot[root.id], !steps.isEmpty else {
            return .terminal(.corruptMetadata)
        }
        let step = steps.removeFirst()
        stepsByRoot[root.id] = steps
        return step
    }
}

private final class PerRootCancellation: CancellationPort, @unchecked Sendable {
    private var responses: [Bool]

    init(responses: [Bool] = []) {
        self.responses = responses
    }

    func isCancellationRequested() async -> Bool {
        guard !responses.isEmpty else { return false }
        return responses.removeFirst()
    }
}

private struct PerRootDetector: LocalDetector {
    let identifier = try! DetectorID("fixture.per-root")
    let version = try! DetectorVersion("1.0.0")

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        guard let declaredRoot = request.declaredRoots.first(where: {
            $0.id == observation.rootID
        }) else {
            return .failure(.mismatchedRootIdentity)
        }
        do {
            return .success(try Finding(
                detectorID: identifier,
                detectorVersion: version,
                provenance: .filesystemObservation,
                observation: observation,
                declaredRoot: declaredRoot,
                observationInstant: clockReading.observationInstant
            ))
        } catch let error as EvidenceValidationError {
            return .failure(error)
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }
}

private struct PerRootClock: ClockPort {
    func now() async -> ClockReading {
        .init(
            observationInstant: .init(monotonicNanoseconds: 1),
            wallClockInstant: .init(unixNanoseconds: 2)
        )
    }
}

private struct PerRootDiagnostics: DiagnosticPort {
    func record(_ event: ScanDiagnosticEvent) async {}
}

private struct PerRootMetrics: MetricPort {
    func record(_ event: ScanMetricEvent) async {}
}
