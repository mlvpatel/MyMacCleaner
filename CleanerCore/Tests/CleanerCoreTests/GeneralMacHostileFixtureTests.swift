import Foundation
import Testing
@testable import CleanerCore

@Suite("General Mac Hostile Fixtures")
struct GeneralMacHostileFixtureTests {
    @Test(arguments: topologyFixtures)
    fileprivate func topologyLeavesExposeExactStopReason(_ fixture: GeneralMacTopologyFixture) throws {
        let catalog = GeneralMacScopeCatalog.current
        let root = try catalog.declaredRoot(for: .userLibraryCaches)
        let observation = try hostileObservation(
            rootID: root.id,
            components: [fixture.name],
            kind: fixture.kind,
            volume: try fixture.volume.evidence(),
            boundaries: fixture.boundaries
        )

        let finding = try #require(try GeneralMacEvidenceDetector(scope: .userLibraryCaches)
            .makeFinding(
                from: observation,
                request: try catalog.scanRequest(for: [.userLibraryCaches]),
                clockReading: hostileClockReading
            )
            .get())

        #expect(finding.completeness == .incomplete(reason: fixture.expectedReason))
    }

    @Test(arguments: firstRootFaultFixtures)
    fileprivate func firstRootFaultsRemainExact(_ fixture: GeneralMacRootFaultFixture) async throws {
        let rootID = try DeclaredRootID("hostile-first-root")
        let fileSystem = ScriptedFileSystem(
            steps: [.terminal(fixture.outcome)],
            rootID: rootID
        )
        let coordinator = try hostileCoordinator(fileSystem: fileSystem)

        let result = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 2, maximumObservations: 2)
        ))

        #expect(result == .terminal(fixture.outcome))
        #expect(fileSystem.calls == [.init(rootID: rootID, cursor: nil)])
    }

    @Test
    func laterFaultRetainsEarlierEvidenceAndStillScansTheNextRoot() async throws {
        let completedRoot = try DeclaredRootID("hostile-completed-root")
        let failedRoot = try DeclaredRootID("hostile-failed-root")
        let laterRoot = try DeclaredRootID("hostile-later-root")
        let fileSystem = ScriptedFileSystem(stepsByRoot: [
            completedRoot: [
                .observation(try hostileObservation(
                    rootID: completedRoot,
                    components: ["kept.bin"]
                )),
                .terminal(.complete),
            ],
            failedRoot: [.terminal(.permissionDenied)],
            laterRoot: [
                .observation(try hostileObservation(
                    rootID: laterRoot,
                    components: ["next.bin"]
                )),
                .terminal(.complete),
            ],
        ])
        let coordinator = try hostileCoordinator(fileSystem: fileSystem)
        let request = try ScanRequest(
            declaredRoots: [
                .init(id: completedRoot),
                .init(id: failedRoot),
                .init(id: laterRoot),
            ],
            budget: .init(
                maximumFindings: 4,
                maximumObservations: 4,
                maximumRootsPerRequest: 3
            )
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: request) else {
            Issue.record("Expected retained evidence with a typed later-root fault.")
            return
        }

        #expect(batch.findings.map(\.locator.components) == [["kept.bin"], ["next.bin"]])
        #expect(batch.terminalOutcome == .partial(issues: [
            .init(
                rootID: failedRoot,
                detectorID: try DetectorID("fixture.general-mac-hostile"),
                cause: .permissionDenied
            ),
        ]))
        #expect(fileSystem.calls.map(\.rootID) == [
            completedRoot, completedRoot, failedRoot, laterRoot, laterRoot,
        ])
    }

    @Test
    func cancellationBeforeFirstPullMakesNoFilesystemCall() async throws {
        let rootID = try DeclaredRootID("hostile-cancel-before-open")
        let fileSystem = ScriptedFileSystem(
            steps: [.terminal(.complete)],
            rootID: rootID
        )
        let coordinator = try hostileCoordinator(
            fileSystem: fileSystem,
            cancellation: HostileFixtureCancellation(responses: [true])
        )

        let result = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 2, maximumObservations: 2)
        ))

        #expect(result == .terminal(.cancelled))
        #expect(fileSystem.calls.isEmpty)
    }

    @Test
    func cancellationBetweenEntriesRetainsObservedEvidenceAndStopsBeforeNextPull() async throws {
        let rootID = try DeclaredRootID("hostile-cancel-between-entries")
        let fileSystem = ScriptedFileSystem(
            steps: [
                .observation(try hostileObservation(rootID: rootID, components: ["kept.bin"])),
                .observation(try hostileObservation(rootID: rootID, components: ["must-not-open.bin"])),
            ],
            rootID: rootID
        )
        let coordinator = try hostileCoordinator(
            fileSystem: fileSystem,
            cancellation: HostileFixtureCancellation(responses: [false, true])
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 2, maximumObservations: 2)
        )) else {
            Issue.record("Expected observed evidence to survive cancellation.")
            return
        }

        #expect(batch.findings.map(\.locator.components) == [["kept.bin"]])
        #expect(batch.terminalOutcome == .cancelled)
        #expect(fileSystem.calls == [.init(rootID: rootID, cursor: nil)])
    }

    @Test
    func cancellationBetweenBatchesStopsBeforeAnotherPull() async throws {
        let rootID = try DeclaredRootID("hostile-cancel-between-batches")
        let fileSystem = ScriptedFileSystem(
            steps: [
                .observation(try hostileObservation(rootID: rootID, components: ["published.bin"])),
                .observation(try hostileObservation(rootID: rootID, components: ["must-not-open.bin"])),
            ],
            rootID: rootID
        )
        let coordinator = try hostileCoordinator(
            fileSystem: fileSystem,
            cancellation: HostileFixtureCancellation(responses: [false, false, true])
        )
        let request = try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 1, maximumObservations: 1)
        )

        guard case let .batch(firstBatch) = await coordinator.nextBatch(for: request) else {
            Issue.record("Expected one bounded batch before cancellation.")
            return
        }
        let cancelled = await coordinator.nextBatch(for: request)

        #expect(firstBatch.findings.map(\.locator.components) == [["published.bin"]])
        #expect(cancelled == .terminal(.cancelled))
        #expect(fileSystem.calls == [.init(rootID: rootID, cursor: nil)])
    }

    @Test
    func cancellationAfterBoundedObservationRetainsEvidenceAndStopsBeforeAnotherPull() async throws {
        let rootID = try DeclaredRootID("hostile-cancel-after-bounded-observation")
        let fileSystem = ScriptedFileSystem(
            steps: [
                .observation(try hostileObservation(rootID: rootID, components: ["kept.bin"])),
                .observation(try hostileObservation(rootID: rootID, components: ["must-not-open.bin"])),
            ],
            rootID: rootID
        )
        let coordinator = try hostileCoordinator(
            fileSystem: fileSystem,
            cancellation: HostileFixtureCancellation(responses: [false, true])
        )

        guard case let .batch(batch) = await coordinator.nextBatch(for: try ScanRequest(
            declaredRoot: .init(id: rootID),
            budget: .init(maximumFindings: 1, maximumObservations: 1)
        )) else {
            Issue.record("Expected bounded evidence to survive the publication cancellation checkpoint.")
            return
        }

        #expect(batch.findings.map(\.locator.components) == [["kept.bin"]])
        #expect(batch.terminalOutcome == .cancelled)
        #expect(batch.continuationCursor == nil)
        #expect(fileSystem.calls == [.init(rootID: rootID, cursor: nil)])
    }

    @Test
    func hardLinksCollapseToOnePhysicalResourceAndCloneSpaceStaysUnknown() async throws {
        let sharedIdentity = FileIdentityEvidence(device: 7, node: 41)
        let distinctIdentity = FileIdentityEvidence(device: 7, node: 42)
        let firstLink = try completeFinding(name: "hard-link-a.bin", identity: sharedIdentity)
        let secondLink = try completeFinding(name: "hard-link-b.bin", identity: sharedIdentity)
        let distinctFile = try completeFinding(name: "distinct.bin", identity: distinctIdentity)
        let digest = try ContentDigest(opaqueBytes: Array(repeating: 9, count: 32))
        let content = HostileFixtureContentEvidence(digest: digest)

        let result = await DuplicateTriage(contentEvidence: content).evaluate([
            firstLink,
            secondLink,
            distinctFile,
        ])

        let group = try #require(result.groups.first)
        #expect(result.groups.count == 1)
        #expect(group.resources.count == 2)
        #expect(group.resources.map(\.members.count).sorted() == [1, 2])
        #expect(await content.requests().count == 2)
        #expect(group.cloneShareUncertainty == .unknown)
        for resource in group.resources {
            #expect(resource.space.sharedBytes == .unknown)
            #expect(resource.space.conservativeReclaimableBytes == .unknown)
        }
    }

    @Test
    func fixturesUseOnlyScriptedStateOrTestOwnedTemporaryRoots() throws {
        let source = try String(contentsOfFile: #filePath, encoding: .utf8)
        let forbidden = [
            "homeDirectoryFor" + "CurrentUser",
            "mounted" + "VolumeURLs",
            "/" + "Volumes/",
            "ProcessInfo." + "processInfo.environment",
        ]

        for term in forbidden {
            #expect(!source.contains(term))
        }
    }
}

fileprivate struct GeneralMacTopologyFixture: Sendable {
    let name: String
    let kind: FileKind
    let volume: HostileFixtureVolume
    let boundaries: BoundaryEvidence
    let expectedReason: TopologyStopReason
}

fileprivate enum HostileFixtureVolume: Sendable {
    case observed(String)
    case unavailable

    func evidence() throws -> EvidenceValue<VolumeID> {
        switch self {
        case .observed(let value):
            return .observed(try VolumeID(value))
        case .unavailable:
            return .unavailable
        }
    }
}

private let topologyFixtures: [GeneralMacTopologyFixture] = [
    .init(
        name: "package.app",
        kind: .package,
        volume: .observed("fixture-volume"),
        boundaries: boundary(package: .observed(true)),
        expectedReason: .package
    ),
    .init(
        name: "symbolic-link",
        kind: .symbolicLink,
        volume: .observed("fixture-volume"),
        boundaries: boundary(symlink: .observed(true)),
        expectedReason: .symbolicLink
    ),
    .init(
        name: "alias",
        kind: .other,
        volume: .observed("fixture-volume"),
        boundaries: boundary(alias: .observed(true)),
        expectedReason: .alias
    ),
    .init(
        name: "mount-trigger",
        kind: .directory,
        volume: .observed("fixture-volume"),
        boundaries: boundary(mount: .observed(true)),
        expectedReason: .mount
    ),
    .init(
        name: "changed-volume",
        kind: .directory,
        volume: .observed("changed-volume"),
        boundaries: boundary(externalVolume: .observed(true)),
        expectedReason: .volumeChanged
    ),
    .init(
        name: "volume-root",
        kind: .directory,
        volume: .observed("volume-root"),
        boundaries: boundary(mount: .observed(true), externalVolume: .observed(true)),
        expectedReason: .mount
    ),
    .init(
        name: "nested-home",
        kind: .directory,
        volume: .observed("fixture-volume"),
        boundaries: boundary(homeBoundary: .observed(true)),
        expectedReason: .nestedHome
    ),
    .init(
        name: "protected-root",
        kind: .directory,
        volume: .observed("fixture-volume"),
        boundaries: boundary(protectedRoot: .observed(true)),
        expectedReason: .protectedRoot
    ),
    .init(
        name: "unavailable-volume",
        kind: .directory,
        volume: .unavailable,
        boundaries: boundary(externalVolume: .unavailable),
        expectedReason: .unavailableMetadata
    ),
]

fileprivate struct GeneralMacRootFaultFixture: Sendable {
    let name: String
    let outcome: ScanOutcome
}

private let firstRootFaultFixtures: [GeneralMacRootFaultFixture] = [
    .init(name: "permission-denial", outcome: .permissionDenied),
    .init(name: "unreadable-entry", outcome: .permissionDenied),
    .init(name: "malformed-metadata", outcome: .corruptMetadata),
    .init(name: "unavailable-root", outcome: .unsupportedLayout),
]

private func boundary(
    symlink: EvidenceValue<Bool> = .observed(false),
    alias: EvidenceValue<Bool> = .observed(false),
    package: EvidenceValue<Bool> = .observed(false),
    mount: EvidenceValue<Bool> = .observed(false),
    protectedRoot: EvidenceValue<Bool> = .observed(false),
    homeBoundary: EvidenceValue<Bool> = .observed(false),
    externalVolume: EvidenceValue<Bool> = .observed(false)
) -> BoundaryEvidence {
    .init(
        symlink: symlink,
        alias: alias,
        package: package,
        mount: mount,
        protectedRoot: protectedRoot,
        homeBoundary: homeBoundary,
        externalVolume: externalVolume
    )
}

private func hostileObservation(
    rootID: DeclaredRootID,
    components: [String],
    identity: EvidenceValue<FileIdentityEvidence> = .observed(.init(device: 7, node: 8)),
    kind: FileKind = .regularFile,
    volume: EvidenceValue<VolumeID>? = nil,
    boundaries: BoundaryEvidence = boundary()
) throws -> FileObservation {
    let resolvedVolume: EvidenceValue<VolumeID>
    if let volume {
        resolvedVolume = volume
    } else {
        resolvedVolume = .observed(try VolumeID("fixture-volume"))
    }
    return try FileObservation(
        rootID: rootID,
        locator: .init(rootID: rootID, components: components),
        resourceIdentity: identity,
        sizes: .init(logicalBytes: .observed(4_096), allocatedBytes: .observed(4_096)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: kind,
        volume: resolvedVolume,
        boundaries: boundaries
    )
}

private let hostileClockReading = ClockReading(
    observationInstant: .init(monotonicNanoseconds: 1),
    wallClockInstant: .init(unixNanoseconds: 2)
)

private func completeFinding(
    name: String,
    identity: FileIdentityEvidence
) throws -> GeneralMacFinding {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: .userDownloads)
    let observation = try hostileObservation(
        rootID: root.id,
        components: [name],
        identity: .observed(identity)
    )
    return try #require(try GeneralMacEvidenceDetector(scope: .userDownloads)
        .makeFinding(
            from: observation,
            request: try catalog.scanRequest(for: [.userDownloads]),
            clockReading: hostileClockReading
        )
        .get())
}

private func hostileCoordinator(
    fileSystem: ScriptedFileSystem,
    cancellation: HostileFixtureCancellation = .init()
) throws -> ScanCoordinator {
    try ScanCoordinator(
        dependencies: .init(
            fileSystem: fileSystem,
            clock: HostileFixtureClock(),
            cancellation: cancellation,
            diagnostics: HostileFixtureDiagnostics(),
            metrics: HostileFixtureMetrics()
        ),
        shippedDetector: try HostileFixtureDetector()
    )
}

private actor HostileFixtureCancellation: CancellationPort {
    private var responses: [Bool]

    init(responses: [Bool] = []) {
        self.responses = responses
    }

    func isCancellationRequested() async -> Bool {
        guard !responses.isEmpty else { return false }
        return responses.removeFirst()
    }
}

private struct HostileFixtureDetector: LocalDetector {
    let identifier: DetectorID
    let version: DetectorVersion

    init() throws {
        identifier = try DetectorID("fixture.general-mac-hostile")
        version = try DetectorVersion("1.0.0")
    }

    func makeFinding(
        from observation: FileObservation,
        request: ScanRequest,
        clockReading: ClockReading
    ) -> Result<Finding?, EvidenceValidationError> {
        guard let root = request.declaredRoots.first(where: { $0.id == observation.rootID }) else {
            return .failure(.mismatchedRootIdentity)
        }
        do {
            return .success(try Finding(
                detectorID: identifier,
                detectorVersion: version,
                provenance: .filesystemObservation,
                observation: observation,
                declaredRoot: root,
                observationInstant: clockReading.observationInstant
            ))
        } catch let error as EvidenceValidationError {
            return .failure(error)
        } catch {
            return .failure(.mismatchedRootIdentity)
        }
    }
}

private actor HostileFixtureContentEvidence: ContentEvidencePort {
    private let digest: ContentDigest
    private var recorded: [ContentEvidenceRequest] = []

    init(digest: ContentDigest) {
        self.digest = digest
    }

    func beginSession(limits: ContentReadLimits) async -> any ContentEvidenceSession {
        _ = limits
        return HostileFixtureContentEvidenceSession(owner: self)
    }

    func contentEvidence(for request: ContentEvidenceRequest) async -> ContentEvidenceOutcome {
        recorded.append(request)
        return .complete(digest)
    }

    func requests() -> [ContentEvidenceRequest] {
        recorded
    }
}

private struct HostileFixtureContentEvidenceSession: ContentEvidenceSession {
    let owner: HostileFixtureContentEvidence

    func contentEvidence(for request: ContentEvidenceRequest) async -> ContentEvidenceOutcome {
        await owner.contentEvidence(for: request)
    }
}

private struct HostileFixtureClock: ClockPort {
    func now() async -> ClockReading { hostileClockReading }
}

private struct HostileFixtureDiagnostics: DiagnosticPort {
    func record(_ event: ScanDiagnosticEvent) async {}
}

private struct HostileFixtureMetrics: MetricPort {
    func record(_ event: ScanMetricEvent) async {}
}
