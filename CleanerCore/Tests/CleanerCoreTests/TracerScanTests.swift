import Testing

@testable import CleanerCore

@Suite("CleanerCore Tracer Scan")
struct TracerScanTests {
    @Test
    func oneFixedDetectorProducesOneBoundedFindingBatch() async throws {
        let filesystem = InTestFileSystem(
            steps: [
                .observation(try Self.observation(name: "first-checkpoint")),
                .observation(try Self.observation(name: "second-checkpoint")),
                .terminal(.complete),
            ]
        )
        let clock = FixedClock()
        let cancellation = CancellationRecorder()
        let diagnostics = DiagnosticRecorder()
        let metrics = MetricRecorder()
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: filesystem,
                clock: clock,
                cancellation: cancellation,
                diagnostics: diagnostics,
                metrics: metrics
            ),
            shippedDetector: FixedRegularFileDetector()
        )

        let request = try ScanRequest(
            declaredRoot: .init(id: .init("fixture-root")),
            budget: .init(maximumFindings: 1)
        )
        let firstStep = await coordinator.nextBatch(for: request)
        let secondStep = await coordinator.nextBatch(for: request)
        let terminalStep = await coordinator.nextBatch(for: request)

        guard case .batch(let firstBatch) = firstStep,
            case .batch(let secondBatch) = secondStep,
            case .terminal(.complete) = terminalStep
        else {
            Issue.record("Expected two bounded batches followed by a complete terminal outcome.")
            return
        }

        #expect(firstBatch.findings.count == 1)
        #expect(secondBatch.findings.count == 1)
        #expect(firstBatch.continuationCursor == .init(position: 1))
        #expect(secondBatch.continuationCursor == .init(position: 2))
        try Self.assertCompleteEvidence(for: firstBatch.findings[0])
        Self.assertInjectedPortCallCounts(
            filesystem: filesystem,
            clock: clock,
            cancellation: cancellation,
            diagnostics: diagnostics,
            metrics: metrics
        )
    }

    @Test
    func nonPositiveAndExcessiveBudgetsAreRejected() {
        #expect(throws: ScanValidationError.nonPositiveBudget) {
            try ScanBudget(maximumFindings: 0)
        }
        #expect(throws: ScanValidationError.excessiveBudget) {
            try ScanBudget(maximumFindings: 257)
        }
        #expect(throws: ScanValidationError.nonPositiveObservationBudget) {
            try ScanBudget(maximumFindings: 1, maximumObservations: 0)
        }
        #expect(throws: ScanValidationError.excessiveObservationBudget) {
            try ScanBudget(maximumFindings: 1, maximumObservations: 257)
        }
    }

    @Test
    func findingIdentityPreservesRelativeLocatorComponentBoundaries() throws {
        let detectorID = try DetectorID("fixture.regular-file")
        let rootID = try DeclaredRootID("fixture-root")
        let firstLocator = try RelativeLocator(rootID: rootID, components: ["a|b", "c"])
        let secondLocator = try RelativeLocator(rootID: rootID, components: ["a", "b|c"])

        #expect(
            FindingID(detectorID: detectorID, rootID: rootID, locator: firstLocator)
                != FindingID(detectorID: detectorID, rootID: rootID, locator: secondLocator)
        )
    }

    @Test
    func detectorValidationFailureBecomesATypedTerminalOutcome() async throws {
        let filesystem = InTestFileSystem(steps: [
            .observation(try Self.observation(name: "invalid"))
        ])
        let diagnostics = DiagnosticRecorder()
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: filesystem,
                clock: FixedClock(),
                cancellation: CancellationRecorder(),
                diagnostics: diagnostics,
                metrics: MetricRecorder()
            ),
            shippedDetector: RejectingDetector()
        )
        let request = try ScanRequest(
            declaredRoot: .init(id: .init("fixture-root")),
            budget: .init(maximumFindings: 1)
        )

        let step = await coordinator.nextBatch(for: request)
        #expect(step == .terminal(.corruptMetadata))
        #expect(
            diagnostics.events == [
                .observationPulled,
                .terminal(.corruptMetadata),
            ])
    }

    private static func assertCompleteEvidence(for finding: Finding) throws {
        let expectedDetectorID = try DetectorID("fixture.regular-file")
        let expectedDetectorVersion = try DetectorVersion("1.0.0")
        let expectedRootID = try DeclaredRootID("fixture-root")
        let expectedVolumeID = try VolumeID("fixture-volume")

        #expect(finding.detectorID == expectedDetectorID)
        #expect(finding.detectorVersion == expectedDetectorVersion)
        #expect(finding.provenance == .filesystemObservation)
        #expect(finding.declaredRoot.id == expectedRootID)
        #expect(finding.locator.components == ["models", "first-checkpoint.bin"])
        #expect(finding.sizes.logicalBytes == .observed(128))
        #expect(finding.sizes.allocatedBytes == .unavailable)
        #expect(finding.modification == .observed(.init(unixNanoseconds: 42)))
        #expect(finding.fileKind == .regularFile)
        #expect(finding.volume == .observed(expectedVolumeID))
        #expect(finding.boundaries.symlink == .observed(false))
        #expect(finding.observationInstant == .init(monotonicNanoseconds: 99))
    }

    private static func assertInjectedPortCallCounts(
        filesystem: InTestFileSystem,
        clock: FixedClock,
        cancellation: CancellationRecorder,
        diagnostics: DiagnosticRecorder,
        metrics: MetricRecorder
    ) {
        #expect(filesystem.calls == 3)
        #expect(clock.calls == 2)
        #expect(cancellation.calls == 5)
        #expect(diagnostics.events.count == 3)
        #expect(metrics.events.count == 3)
    }

    @Test
    func unknownAndUnavailableMetadataRemainDistinctFromObservedZeroOrFalse() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let finding = try Finding(
            detectorID: try DetectorID("fixture.regular-file"),
            detectorVersion: try DetectorVersion("1.0.0"),
            provenance: .filesystemObservation,
            observation: .init(
                rootID: rootID,
                locator: try RelativeLocator(
                    rootID: rootID, components: ["models", "unknown.bin"]),
                resourceIdentity: .unknown,
                sizes: try .init(logicalBytes: .unknown, allocatedBytes: .unavailable),
                modification: .unknown,
                fileKind: .regularFile,
                volume: .unavailable,
                boundaries: .init(symlink: .unknown, mount: .unavailable)
            ),
            declaredRoot: .init(id: rootID),
            observationInstant: .init(monotonicNanoseconds: 100)
        )

        #expect(finding.resourceIdentity == .unknown)
        #expect(finding.sizes.logicalBytes == .unknown)
        #expect(finding.sizes.allocatedBytes == .unavailable)
        #expect(finding.modification == .unknown)
        #expect(finding.volume == .unavailable)
        #expect(finding.boundaries.symlink == .unknown)
        #expect(finding.boundaries.mount == .unavailable)
    }

    @Test(arguments: InvalidEvidenceCase.allCases)
    func invalidEvidenceConstructionFailsClosed(_ testCase: InvalidEvidenceCase) throws {
        try testCase.assertRejected()
    }

    @Test
    func filteredObservationsRespectThePerPullWorkBudgetAndReturnAContinuation() async throws {
        let order = PortCallOrderRecorder()
        let filesystem = InTestFileSystem(
            steps: [
                .observation(try Self.observation(name: "first-directory", kind: .directory)),
                .observation(try Self.observation(name: "second-directory", kind: .directory)),
                .observation(try Self.observation(name: "third-directory", kind: .directory)),
                .terminal(.complete),
            ],
            order: order
        )
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: filesystem,
                clock: FixedClock(order: order),
                cancellation: CancellationRecorder(order: order),
                diagnostics: DiagnosticRecorder(order: order),
                metrics: MetricRecorder(order: order)
            ),
            shippedDetector: FixedRegularFileDetector()
        )

        let step = await coordinator.nextBatch(
            for: try Self.request(
                maximumFindings: 1,
                maximumObservations: 2
            ))

        guard case .batch(let batch) = step else {
            Issue.record("Expected an incomplete empty batch after the work budget is exhausted.")
            return
        }

        #expect(batch.findings.isEmpty)
        #expect(batch.continuationCursor == .init(position: 2))
        #expect(batch.terminalOutcome == nil)
        #expect(
            order.events == [
                .cancellation, .filesystem, .clock, .diagnosticObservation,
                .cancellation, .filesystem, .clock, .diagnosticObservation,
                .cancellation, .metric,
            ])
    }

    @Test
    func changedRootOrBudgetIsRejectedWithoutInvokingAnyPort() async throws {
        let order = PortCallOrderRecorder()
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: InTestFileSystem(
                    steps: [
                        .observation(try Self.observation(name: "first")),
                        .terminal(.complete),
                    ], order: order),
                clock: FixedClock(order: order),
                cancellation: CancellationRecorder(order: order),
                diagnostics: DiagnosticRecorder(order: order),
                metrics: MetricRecorder(order: order)
            ),
            shippedDetector: FixedRegularFileDetector()
        )
        let original = try Self.request(maximumFindings: 1, maximumObservations: 1)
        let changedRoot = try ScanRequest(
            declaredRoot: .init(id: .init("other-root")),
            budget: .init(maximumFindings: 1, maximumObservations: 1)
        )
        let changedBudget = try Self.request(maximumFindings: 1, maximumObservations: 2)

        _ = await coordinator.nextBatch(for: original)
        let eventsBeforeRejection = order.events
        let rootRejection = await coordinator.nextBatch(for: changedRoot)
        let budgetRejection = await coordinator.nextBatch(for: changedBudget)
        #expect(rootRejection == .terminal(.corruptMetadata))
        #expect(budgetRejection == .terminal(.corruptMetadata))
        #expect(order.events == eventsBeforeRejection)
        #expect(await coordinator.nextBatch(for: original) == .terminal(.complete))
    }

    @Test
    func clockObservationInstantOverridesAdapterSuppliedTime() async throws {
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: InTestFileSystem(steps: [
                    .observation(try Self.observation(name: "clock"))
                ]),
                clock: FixedClock(instant: .init(monotonicNanoseconds: 777)),
                cancellation: CancellationRecorder(),
                diagnostics: DiagnosticRecorder(),
                metrics: MetricRecorder()
            ),
            shippedDetector: FixedRegularFileDetector()
        )

        guard case .batch(let batch) = await coordinator.nextBatch(for: try Self.request()) else {
            Issue.record("Expected one finding batch.")
            return
        }

        #expect(batch.findings[0].observationInstant == .init(monotonicNanoseconds: 777))
    }

    @Test
    func terminalAfterFindingsIsTruthfulAndHasNoContinuation() async throws {
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: InTestFileSystem(steps: [
                    .observation(try Self.observation(name: "last")),
                    .terminal(.complete),
                ]),
                clock: FixedClock(),
                cancellation: CancellationRecorder(),
                diagnostics: DiagnosticRecorder(),
                metrics: MetricRecorder()
            ),
            shippedDetector: FixedRegularFileDetector()
        )

        guard
            case .batch(let batch) = await coordinator.nextBatch(
                for: try Self.request(
                    maximumFindings: 2,
                    maximumObservations: 2
                ))
        else {
            Issue.record("Expected a completed batch.")
            return
        }

        #expect(batch.findings.count == 1)
        #expect(batch.terminalOutcome == .complete)
        #expect(batch.continuationCursor == nil)
        let replayedTerminal = await coordinator.nextBatch(
            for: try Self.request(
                maximumFindings: 2,
                maximumObservations: 2
            ))
        #expect(replayedTerminal == .terminal(.complete))
    }

    @Test
    func cancellationStopsBeforeFilesystemAndTerminatesTheBoundSession() async throws {
        let order = PortCallOrderRecorder()
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: InTestFileSystem(steps: [.terminal(.complete)], order: order),
                clock: FixedClock(order: order),
                cancellation: CancellationRecorder(responses: [true], order: order),
                diagnostics: DiagnosticRecorder(order: order),
                metrics: MetricRecorder(order: order)
            ),
            shippedDetector: FixedRegularFileDetector()
        )
        let request = try Self.request()

        let cancelled = await coordinator.nextBatch(for: request)
        #expect(cancelled == .terminal(.cancelled))
        #expect(order.events == [.cancellation, .diagnosticCancelled, .metric])
        let replayedCancellation = await coordinator.nextBatch(for: request)
        #expect(replayedCancellation == .terminal(.cancelled))
        #expect(order.events == [.cancellation, .diagnosticCancelled, .metric])
    }

    @Test
    func cancellationAfterEvidencePreservesTheFindingInATerminalBatch() async throws {
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: InTestFileSystem(steps: [
                    .observation(try Self.observation(name: "kept"))
                ]),
                clock: FixedClock(),
                cancellation: CancellationRecorder(responses: [false, true]),
                diagnostics: DiagnosticRecorder(),
                metrics: MetricRecorder()
            ),
            shippedDetector: FixedRegularFileDetector()
        )

        guard
            case .batch(let batch) = await coordinator.nextBatch(
                for: try Self.request(
                    maximumFindings: 2,
                    maximumObservations: 2
                ))
        else {
            Issue.record("Expected accumulated evidence to survive cancellation.")
            return
        }

        #expect(batch.findings.count == 1)
        #expect(batch.terminalOutcome == .cancelled)
        #expect(batch.continuationCursor == nil)
    }

    @Test
    func cancellationAfterObservationBeforeBatchPublicationRetainsBatchAndStopsPorts() async throws {
        let order = PortCallOrderRecorder()
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: InTestFileSystem(
                    steps: [
                        .observation(try Self.observation(name: "retained")),
                        .observation(try Self.observation(name: "must-not-read")),
                    ],
                    order: order
                ),
                clock: FixedClock(order: order),
                cancellation: CancellationRecorder(responses: [false, true], order: order),
                diagnostics: DiagnosticRecorder(order: order),
                metrics: MetricRecorder(order: order)
            ),
            shippedDetector: FixedRegularFileDetector()
        )

        let result = await coordinator.nextBatch(for: try Self.request(
            maximumFindings: 1,
            maximumObservations: 2
        ))

        guard case let .batch(batch) = result else {
            Issue.record("Expected collected evidence to survive cancellation before publication.")
            return
        }
        #expect(batch.findings.count == 1)
        #expect(batch.terminalOutcome == .cancelled)
        #expect(batch.continuationCursor == nil)
        #expect(order.events == [
            .cancellation,
            .filesystem,
            .clock,
            .diagnosticObservation,
            .cancellation,
            .diagnosticCancelled,
            .metric,
        ])
    }

    private static func request(
        maximumFindings: Int = 1,
        maximumObservations: Int = 1
    ) throws -> ScanRequest {
        try .init(
            declaredRoot: .init(id: .init("fixture-root")),
            budget: .init(
                maximumFindings: maximumFindings,
                maximumObservations: maximumObservations
            )
        )
    }

    private static func observation(name: String, kind: FileKind = .regularFile) throws
        -> FileObservation
    {
        try .init(
            rootID: DeclaredRootID("fixture-root"),
            locator: try! RelativeLocator(
                rootID: DeclaredRootID("fixture-root"),
                components: ["models", "\(name).bin"]
            ),
            resourceIdentity: .observed(.init(device: 1, node: 2)),
            sizes: try .init(logicalBytes: .observed(128), allocatedBytes: .unavailable),
            modification: .observed(.init(unixNanoseconds: 42)),
            fileKind: kind,
            volume: .observed(try VolumeID("fixture-volume")),
            boundaries: .init(symlink: .observed(false))
        )
    }
}

enum InvalidEvidenceCase: CaseIterable, Sendable {
    case emptyDetectorID
    case emptyDetectorVersion
    case emptyRootID
    case emptyVolumeID
    case absoluteLocator
    case emptyLocatorComponent
    case parentTraversalComponent
    case negativeLogicalSize
    case negativeAllocatedSize
    case mismatchedRootIdentity

    func assertRejected() throws {
        switch self {
        case .emptyDetectorID:
            #expect(throws: EvidenceValidationError.emptyIdentifier) { try DetectorID("") }
        case .emptyDetectorVersion:
            #expect(throws: EvidenceValidationError.emptyIdentifier) { try DetectorVersion("") }
        case .emptyRootID:
            #expect(throws: EvidenceValidationError.emptyIdentifier) { try DeclaredRootID("") }
        case .emptyVolumeID:
            #expect(throws: EvidenceValidationError.emptyIdentifier) { try VolumeID("") }
        case .absoluteLocator:
            #expect(throws: EvidenceValidationError.invalidRelativeLocator) {
                try RelativeLocator(rootID: .init("fixture-root"), components: ["/absolute"])
            }
        case .emptyLocatorComponent:
            #expect(throws: EvidenceValidationError.invalidRelativeLocator) {
                try RelativeLocator(rootID: .init("fixture-root"), components: ["models", ""])
            }
        case .parentTraversalComponent:
            #expect(throws: EvidenceValidationError.invalidRelativeLocator) {
                try RelativeLocator(rootID: .init("fixture-root"), components: ["models", ".."])
            }
        case .negativeLogicalSize:
            #expect(throws: EvidenceValidationError.negativeSize) {
                try SizeEvidence(logicalBytes: .observed(-1), allocatedBytes: .unavailable)
            }
        case .negativeAllocatedSize:
            #expect(throws: EvidenceValidationError.negativeSize) {
                try SizeEvidence(logicalBytes: .unavailable, allocatedBytes: .observed(-1))
            }
        case .mismatchedRootIdentity:
            let firstRoot = try DeclaredRootID("first-root")
            let observation = try FileObservation(
                rootID: firstRoot,
                locator: .init(rootID: firstRoot, components: ["models", "file.bin"]),
                resourceIdentity: .unavailable,
                sizes: .init(logicalBytes: .unavailable, allocatedBytes: .unavailable),
                modification: .unavailable,
                fileKind: .regularFile,
                volume: .unavailable,
                boundaries: .init(symlink: .unavailable)
            )
            #expect(throws: EvidenceValidationError.mismatchedRootIdentity) {
                try Finding(
                    detectorID: .init("fixture.regular-file"),
                    detectorVersion: .init("1"),
                    provenance: .filesystemObservation,
                    observation: observation,
                    declaredRoot: .init(id: try DeclaredRootID("second-root")),
                    observationInstant: .init(monotonicNanoseconds: 1)
                )
            }
        }
    }
}

private struct FixedRegularFileDetector: LocalDetector {
    let identifier = try! DetectorID("fixture.regular-file")
    let version = try! DetectorVersion("1.0.0")

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        guard observation.fileKind == .regularFile else { return .success(nil) }
        do {
            return .success(
                try Finding(
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

private struct RejectingDetector: LocalDetector {
    let identifier = try! DetectorID("fixture.rejecting")
    let version = try! DetectorVersion("1.0.0")

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        .failure(.mismatchedRootIdentity)
    }
}

private enum PortCall: Equatable, Sendable {
    case clock
    case cancellation
    case filesystem
    case diagnosticObservation
    case diagnosticCancelled
    case diagnosticTerminal
    case metric
}

private final class PortCallOrderRecorder: @unchecked Sendable {
    private(set) var events: [PortCall] = []

    func append(_ event: PortCall) {
        events.append(event)
    }
}

private final class InTestFileSystem: FileSystemPort, @unchecked Sendable {
    private var remainingSteps: [FileSystemStep]
    private let order: PortCallOrderRecorder?
    private(set) var calls = 0

    init(steps: [FileSystemStep], order: PortCallOrderRecorder? = nil) {
        remainingSteps = steps
        self.order = order
    }

    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        calls += 1
        order?.append(.filesystem)
        return remainingSteps.removeFirst()
    }
}

private final class FixedClock: ClockPort, @unchecked Sendable {
    private let instant: ObservationInstant
    private let wallClockInstant: WallClockInstant
    private let order: PortCallOrderRecorder?
    private(set) var calls = 0

    init(
        instant: ObservationInstant = .init(monotonicNanoseconds: 99),
        wallClockInstant: WallClockInstant = .init(unixNanoseconds: 199),
        order: PortCallOrderRecorder? = nil
    ) {
        self.instant = instant
        self.wallClockInstant = wallClockInstant
        self.order = order
    }

    func now() async -> ClockReading {
        calls += 1
        order?.append(.clock)
        return .init(observationInstant: instant, wallClockInstant: wallClockInstant)
    }
}

private final class CancellationRecorder: CancellationPort, @unchecked Sendable {
    private var remainingResponses: [Bool]
    private let order: PortCallOrderRecorder?
    private(set) var calls = 0

    init(responses: [Bool] = [], order: PortCallOrderRecorder? = nil) {
        remainingResponses = responses
        self.order = order
    }

    func isCancellationRequested() async -> Bool {
        calls += 1
        order?.append(.cancellation)
        return remainingResponses.isEmpty ? false : remainingResponses.removeFirst()
    }
}

private final class DiagnosticRecorder: DiagnosticPort, @unchecked Sendable {
    private let order: PortCallOrderRecorder?
    private(set) var events: [ScanDiagnosticEvent] = []

    init(order: PortCallOrderRecorder? = nil) {
        self.order = order
    }

    func record(_ event: ScanDiagnosticEvent) async {
        events.append(event)
        switch event {
        case .observationPulled: order?.append(.diagnosticObservation)
        case .cancelled: order?.append(.diagnosticCancelled)
        case .terminal: order?.append(.diagnosticTerminal)
        }
    }
}

private final class MetricRecorder: MetricPort, @unchecked Sendable {
    private let order: PortCallOrderRecorder?
    private(set) var events: [ScanMetricEvent] = []

    init(order: PortCallOrderRecorder? = nil) {
        self.order = order
    }

    func record(_ event: ScanMetricEvent) async {
        events.append(event)
        order?.append(.metric)
    }
}
