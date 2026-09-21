import Testing
@testable import CleanerCore

@Suite("CleanerCore Hostile Fixtures")
struct HostileFixtureTests {
    @Test
    func topologyBoundaryAndSharedIdentityFixturesRemainEvidenceOnly() async throws {
        let rootID = try DeclaredRootID("fixture-hostile-root")
        let sharedIdentity = FileIdentityEvidence(device: 42, node: 9001)
        let detector = HostileDetector()
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: ScriptedFileSystem(stepsByRoot: [
                    rootID: [
                        .observation(try observation(
                            rootID: rootID,
                            components: ["shared-a.bin"],
                            identity: .observed(sharedIdentity)
                        )),
                        .observation(try observation(
                            rootID: rootID,
                            components: ["shared-b.bin"],
                            identity: .observed(sharedIdentity)
                        )),
                        .observation(try observation(
                            rootID: rootID,
                            components: ["linked"],
                            kind: .symbolicLink,
                            boundaries: .init(symlink: .observed(true))
                        )),
                        .observation(try observation(
                            rootID: rootID,
                            components: ["mounted-package.app"],
                            kind: .package,
                            boundaries: .init(
                                symlink: .observed(false),
                                alias: .observed(true),
                                package: .observed(true),
                                mount: .observed(true),
                                externalVolume: .observed(true)
                            )
                        )),
                    ]
                ]),
                clock: HostileClock(),
                cancellation: HostileCancellation(),
                diagnostics: HostileDiagnostics(),
                metrics: HostileMetrics()
            ),
            shippedDetector: detector
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 4, maximumObservations: 4)
        )) else {
            Issue.record("Expected one hostile fixture evidence batch.")
            return
        }

        #expect(batch.findings.count == 4)
        #expect(batch.findings[0].resourceIdentity == .observed(sharedIdentity))
        #expect(batch.findings[1].resourceIdentity == .observed(sharedIdentity))
        #expect(batch.findings[2].fileKind == .symbolicLink)
        #expect(batch.findings[2].boundaries.symlink == .observed(true))
        #expect(batch.findings[3].fileKind == .package)
        #expect(batch.findings[3].boundaries.alias == .observed(true))
        #expect(batch.findings[3].boundaries.mount == .observed(true))
        #expect(batch.findings[3].boundaries.externalVolume == .observed(true))
    }

    @Test(arguments: hostileTerminalCases)
    fileprivate func hostileFaultsProduceExactTerminalOutcomes(_ testCase: HostileTerminalCase) async throws {
        let rootID = try DeclaredRootID("fixture-fault-root")
        let cancellation = HostileCancellation(responses: testCase.cancellationResponses)
        let fileSystem = ScriptedFileSystem(steps: try testCase.steps(rootID), rootID: rootID)
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: fileSystem,
                clock: HostileClock(),
                cancellation: cancellation,
                diagnostics: HostileDiagnostics(),
                metrics: HostileMetrics()
            ),
            shippedDetector: HostileDetector()
        )

        let step = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 2, maximumObservations: 2)
        ))

        #expect(step == .terminal(testCase.expectedOutcome))
        #expect(fileSystem.calls == testCase.expectedFileSystemCalls)
    }

    @Test
    func laterRootFailureRetainsPriorFindingsAndStopsAfterTypedIssue() async throws {
        let firstRoot = try DeclaredRootID("fixture-first-root")
        let secondRoot = try DeclaredRootID("fixture-second-root")
        let fileSystem = ScriptedFileSystem(stepsByRoot: [
            firstRoot: [
                .observation(try observation(rootID: firstRoot, components: ["kept.bin"])),
                .terminal(.complete),
            ],
            secondRoot: [
                .terminal(.unsupportedLayout)
            ],
        ])
        let coordinator = try ScanCoordinator(
            dependencies: .init(
                fileSystem: fileSystem,
                clock: HostileClock(),
                cancellation: HostileCancellation(),
                diagnostics: HostileDiagnostics(),
                metrics: HostileMetrics()
            ),
            shippedDetector: HostileDetector()
        )

        let result = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoots: [.init(id: firstRoot), .init(id: secondRoot)],
            budget: .init(maximumFindings: 2, maximumObservations: 2)
        ))

        guard case .batch(let batch) = result else {
            Issue.record("Expected retained finding with partial terminal state.")
            return
        }
        #expect(batch.findings.map(\.declaredRoot.id) == [firstRoot])
        #expect(batch.terminalOutcome == .partial(issues: [
            .init(
                rootID: secondRoot,
                detectorID: try DetectorID("fixture.hostile"),
                cause: .unsupportedLayout
            )
        ]))
        #expect(batch.continuationCursor == nil)
        #expect(fileSystem.calls == [
            .init(rootID: firstRoot, cursor: nil),
            .init(rootID: firstRoot, cursor: .init(position: 1)),
            .init(rootID: secondRoot, cursor: nil),
        ])
    }

    @Test
    func undeclaredTraversalBoundaryAndCursorMisuseFailTheFixture() async throws {
        let declaredRoot = try DeclaredRootID("fixture-root")
        let undeclaredRoot = try DeclaredRootID("undeclared-root")
        let fileSystem = ScriptedFileSystem(stepsByRoot: [
            declaredRoot: [.terminal(.complete)]
        ])

        #expect(
            await fileSystem.nextObservation(after: nil, in: .init(id: undeclaredRoot))
                == .terminal(.corruptMetadata)
        )
        #expect(
            await fileSystem.nextObservation(after: .init(position: 99), in: .init(id: declaredRoot))
                == .terminal(.corruptMetadata)
        )

        let boundary = ScriptedFileSystem(stepsByRoot: [
            declaredRoot: [.terminal(.unsupportedLayout)]
        ])
        #expect(
            await boundary.nextObservation(after: nil, in: .init(id: declaredRoot))
                == .terminal(.unsupportedLayout)
        )
        #expect(boundary.calls == [.init(rootID: declaredRoot, cursor: nil)])

        let exhausted = ScriptedFileSystem(stepsByRoot: [
            declaredRoot: [
                .observation(try observation(rootID: declaredRoot, components: ["only.bin"]))
            ]
        ])
        #expect(
            await exhausted.nextObservation(after: nil, in: .init(id: declaredRoot))
                != .terminal(.corruptMetadata)
        )
        #expect(
            await exhausted.nextObservation(after: .init(position: 1), in: .init(id: declaredRoot))
                == .terminal(.corruptMetadata)
        )
    }
}

fileprivate struct HostileTerminalCase: Sendable {
    let expectedOutcome: ScanOutcome
    let cancellationResponses: [Bool]
    let expectedFileSystemCalls: [ScriptedFileSystem.Call]
    let steps: @Sendable (DeclaredRootID) throws -> [FileSystemStep]
}

private let hostileTerminalCases: [HostileTerminalCase] = [
    .init(
        expectedOutcome: .permissionDenied,
        cancellationResponses: [false],
        expectedFileSystemCalls: [
            .init(rootID: try! DeclaredRootID("fixture-fault-root"), cursor: nil)
        ]
    ) { rootID in
        [.terminal(.permissionDenied)]
    },
    .init(
        expectedOutcome: .corruptMetadata,
        cancellationResponses: [false],
        expectedFileSystemCalls: [
            .init(rootID: try! DeclaredRootID("fixture-fault-root"), cursor: nil)
        ]
    ) { _ in
        [.terminal(.corruptMetadata)]
    },
    .init(
        expectedOutcome: .unsupportedLayout,
        cancellationResponses: [false],
        expectedFileSystemCalls: [
            .init(rootID: try! DeclaredRootID("fixture-fault-root"), cursor: nil)
        ]
    ) { _ in
        [.terminal(.unsupportedLayout)]
    },
    .init(
        expectedOutcome: .unsupportedLayout,
        cancellationResponses: [false],
        expectedFileSystemCalls: [
            .init(rootID: try! DeclaredRootID("fixture-fault-root"), cursor: nil)
        ]
    ) { rootID in
        [.terminal(.unsupportedLayout)]
    },
    .init(
        expectedOutcome: .cancelled,
        cancellationResponses: [true],
        expectedFileSystemCalls: []
    ) { _ in
        [.terminal(.complete)]
    },
]

private func observation(
    rootID: DeclaredRootID,
    components: [String],
    identity: EvidenceValue<FileIdentityEvidence> = .unavailable,
    volume: EvidenceValue<VolumeID> = .unavailable,
    kind: FileKind = .regularFile,
    boundaries: BoundaryEvidence = .init(symlink: .observed(false))
) throws -> FileObservation {
    try .init(
        rootID: rootID,
        locator: .init(rootID: rootID, components: components),
        resourceIdentity: identity,
        sizes: .init(logicalBytes: .observed(1), allocatedBytes: .unavailable),
        modification: .unavailable,
        fileKind: kind,
        volume: volume,
        boundaries: boundaries
    )
}

private final class HostileCancellation: CancellationPort, @unchecked Sendable {
    private var responses: [Bool]

    init(responses: [Bool] = []) {
        self.responses = responses
    }

    func isCancellationRequested() async -> Bool {
        guard !responses.isEmpty else { return false }
        return responses.removeFirst()
    }
}

private struct HostileDetector: LocalDetector {
    let identifier = try! DetectorID("fixture.hostile")
    let version = try! DetectorVersion("1.0.0")

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
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

private struct HostileClock: ClockPort {
    func now() async -> ClockReading {
        .init(
            observationInstant: .init(monotonicNanoseconds: 1),
            wallClockInstant: .init(unixNanoseconds: 2)
        )
    }
}

private struct HostileDiagnostics: DiagnosticPort {
    func record(_ event: ScanDiagnosticEvent) async {}
}

private struct HostileMetrics: MetricPort {
    func record(_ event: ScanMetricEvent) async {}
}
