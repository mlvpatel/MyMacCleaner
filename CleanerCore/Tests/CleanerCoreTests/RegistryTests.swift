import Testing

@testable import CleanerCore

@Suite("CleanerCore Detector Registry")
struct RegistryTests {
    @Test
    func shippedDetectorSelectionProducesTheSameScanStepAsDirectTracerExecution() async throws {
        let detector = RegistryFixedDetector()
        let registry = try DetectorRegistry(registrations: [
            .init(detector: detector)
        ])
        let filesystem = RegistryFileSystem(steps: [
            .observation(try Self.observation(name: "registry"))
        ])
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: filesystem,
                clock: RegistryClock(),
                cancellation: RegistryCancellation(),
                diagnostics: RegistryDiagnostics(),
                metrics: RegistryMetrics()
            ),
            registry: registry,
            selection: .init(id: detector.identifier, version: detector.version)
        )

        guard case .batch(let batch) = await coordinator.nextBatch(for: try Self.request()) else {
            Issue.record("Expected one registry-backed detector batch.")
            return
        }

        #expect(batch.findings.map(\.detectorID) == [detector.identifier])
        #expect(batch.findings.map(\.detectorVersion) == [detector.version])
        #expect(filesystem.calls == 1)
    }

    @Test(arguments: registryFailureCases)
    fileprivate func invalidRegistryOrSelectionFailsBeforeAnyPortCall(
        _ testCase: RegistryFailureCase
    )
        async throws
    {
        let ports = RegistryPortRecorders()

        do {
            let registry = try DetectorRegistry(registrations: testCase.registrations())
            _ = try ScanCoordinator(
                dependencies: ports.dependencies,
                registry: registry,
                selection: testCase.selection()
            )
            Issue.record("Expected registry rejection before scan construction.")
        } catch let error as DetectorRegistryError {
            #expect(error == testCase.expectedError)
        }

        #expect(ports.fileSystem.calls == 0)
        #expect(ports.clock.calls == 0)
        #expect(ports.cancellation.calls == 0)
        #expect(ports.diagnostics.events.isEmpty)
        #expect(ports.metrics.events.isEmpty)
    }

    @Test
    func registrationsAreSortedDeterministically() throws {
        let first = RegistryFixedDetector(
            identifier: try DetectorID("fixture.a"),
            version: try DetectorVersion("1.0.0")
        )
        let second = RegistryFixedDetector(
            identifier: try DetectorID("fixture.b"),
            version: try DetectorVersion("1.0.0")
        )

        let registry = try DetectorRegistry(registrations: [
            .init(detector: second),
            .init(detector: first),
        ])

        #expect(
            registry.availableSelections == [
                .init(id: first.identifier, version: first.version),
                .init(id: second.identifier, version: second.version),
            ])
    }

    private static func request() throws -> ScanRequest {
        try .init(
            declaredRoot: .init(id: .init("fixture-root")),
            budget: .init(maximumFindings: 1)
        )
    }

    private static func observation(name: String) throws -> FileObservation {
        let rootID = try DeclaredRootID("fixture-root")
        return try .init(
            rootID: rootID,
            locator: .init(rootID: rootID, components: ["registry", "\(name).bin"]),
            resourceIdentity: .unavailable,
            sizes: .init(logicalBytes: .observed(1), allocatedBytes: .unavailable),
            modification: .unavailable,
            fileKind: .regularFile,
            volume: .unavailable,
            boundaries: .init(symlink: .observed(false))
        )
    }
}

private struct RegistryFailureCase: Sendable {
    let expectedError: DetectorRegistryError
    let registrations: @Sendable () throws -> [DetectorRegistration]
    let selection: @Sendable () throws -> DetectorSelection
}

private let registryFailureCases: [RegistryFailureCase] = [
    .init(
        expectedError: .emptyRegistry,
        registrations: { [] },
        selection: { try .init(id: .init("fixture.missing"), version: .init("1.0.0")) }
    ),
    .init(
        expectedError: .duplicateRegistration,
        registrations: {
            let detector = RegistryFixedDetector()
            return [.init(detector: detector), .init(detector: detector)]
        },
        selection: {
            let detector = RegistryFixedDetector()
            return .init(id: detector.identifier, version: detector.version)
        }
    ),
    .init(
        expectedError: .invalidVersion,
        registrations: {
            [.init(detector: RegistryFixedDetector(version: try DetectorVersion("latest")))]
        },
        selection: {
            try .init(id: .init("fixture.registry"), version: .init("latest"))
        }
    ),
    .init(
        expectedError: .unknownDetector,
        registrations: { [.init(detector: RegistryFixedDetector())] },
        selection: { try .init(id: .init("fixture.unknown"), version: .init("1.0.0")) }
    ),
    .init(
        expectedError: .unsupportedVersion,
        registrations: { [.init(detector: RegistryFixedDetector())] },
        selection: { try .init(id: .init("fixture.registry"), version: .init("2.0.0")) }
    ),
]

private struct RegistryFixedDetector: LocalDetector {
    let identifier: DetectorID
    let version: DetectorVersion

    init(
        identifier: DetectorID = try! DetectorID("fixture.registry"),
        version: DetectorVersion = try! DetectorVersion("1.0.0")
    ) {
        self.identifier = identifier
        self.version = version
    }

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

private final class RegistryPortRecorders: @unchecked Sendable {
    let fileSystem = RegistryFileSystem(steps: [])
    let clock = RegistryClock()
    let cancellation = RegistryCancellation()
    let diagnostics = RegistryDiagnostics()
    let metrics = RegistryMetrics()

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

private final class RegistryFileSystem: FileSystemPort, @unchecked Sendable {
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

private final class RegistryClock: ClockPort, @unchecked Sendable {
    private(set) var calls = 0

    func now() async -> ClockReading {
        calls += 1
        return .init(
            observationInstant: .init(monotonicNanoseconds: 1),
            wallClockInstant: .init(unixNanoseconds: 2)
        )
    }
}

private final class RegistryCancellation: CancellationPort, @unchecked Sendable {
    private(set) var calls = 0

    func isCancellationRequested() async -> Bool {
        calls += 1
        return false
    }
}

private final class RegistryDiagnostics: DiagnosticPort, @unchecked Sendable {
    private(set) var events: [ScanDiagnosticEvent] = []

    func record(_ event: ScanDiagnosticEvent) async {
        events.append(event)
    }
}

private final class RegistryMetrics: MetricPort, @unchecked Sendable {
    private(set) var events: [ScanMetricEvent] = []

    func record(_ event: ScanMetricEvent) async {
        events.append(event)
    }
}
