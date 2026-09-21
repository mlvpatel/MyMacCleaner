import Testing
@testable import CleanerCore

@Suite("CleanerCore Legacy Scan Projection")
struct LegacyScanProjectionTests {
    @Test(arguments: projectedOutcomeCases)
    fileprivate func everyScanOutcomeMapsToOneExplicitProjectionState(_ testCase: ProjectedOutcomeCase) {
        let projection = LegacyScanProjection(step: .terminal(testCase.outcome))

        #expect(projection.state == testCase.expectedState)
        #expect(projection.findings.isEmpty)
    }

    @Test
    func partialBatchProjectionRetainsFindingsIssuesAndEvidence() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let detectorID = try DetectorID("fixture.detector")
        let detectorVersion = try DetectorVersion("1.2.3")
        let finding = try Self.finding(
            rootID: rootID,
            detectorID: detectorID,
            detectorVersion: detectorVersion
        )
        let issue = ScanIssue(
            rootID: rootID,
            detectorID: detectorID,
            cause: .permissionDenied
        )
        let projection = LegacyScanProjection(
            step: .batch(.init(
                findings: [finding],
                continuationCursor: nil,
                terminalOutcome: .partial(issues: [issue])
            ))
        )

        #expect(projection.state == .partial(issues: [.init(issue)]))
        #expect(projection.findings.count == 1)
        #expect(projection.findings[0].detectorID == detectorID)
        #expect(projection.findings[0].detectorVersion == detectorVersion)
        #expect(projection.findings[0].declaredRootID == rootID)
        #expect(projection.findings[0].locator.components == ["models", "llama.gguf"])
        #expect(projection.findings[0].resourceIdentity == .observed(.init(device: 10, node: 99)))
        #expect(projection.findings[0].sizes.logicalBytes == .observed(1024))
        #expect(projection.findings[0].sizes.allocatedBytes == .observed(2048))
        #expect(projection.findings[0].modification == .observed(.init(unixNanoseconds: 7)))
        #expect(projection.findings[0].fileKind == .regularFile)
        #expect(projection.findings[0].volume == .observed(try VolumeID("volume-a")))
        #expect(projection.findings[0].boundaries.symlink == .observed(false))
        #expect(projection.findings[0].boundaries.externalVolume == .observed(true))
        #expect(projection.findings[0].observationInstant == .init(monotonicNanoseconds: 8))
    }

    @Test
    func projectionCarriesOnlyValidatedLargeFileRevealEntries() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let locator = try RelativeLocator(rootID: rootID, components: ["file.bin"])
        let entry = LargeFileTriageEntry(
            revealIntent: try .init(declaredRootID: rootID, locator: locator),
            space: .init(
                logicalBytes: .observed(1024),
                allocatedBytes: .observed(2048),
                sharedBytes: .unknown,
                conservativeReclaimableBytes: .unknown
            )
        )
        let projection = LegacyScanProjection(
            state: .complete,
            findings: [],
            largeFileTriage: [.init(entry)]
        )

        #expect(projection.largeFileTriage.count == 1)
        #expect(projection.largeFileTriage[0].revealIntent == entry.revealIntent)
        #expect(projection.largeFileTriage[0].protection == entry.protection)
        #expect(projection.largeFileTriage[0].space == entry.space)
    }

    private static func finding(
        rootID: DeclaredRootID,
        detectorID: DetectorID,
        detectorVersion: DetectorVersion
    ) throws -> Finding {
        let observation = try FileObservation(
            rootID: rootID,
            locator: .init(rootID: rootID, components: ["models", "llama.gguf"]),
            resourceIdentity: .observed(.init(device: 10, node: 99)),
            sizes: .init(logicalBytes: .observed(1024), allocatedBytes: .observed(2048)),
            modification: .observed(.init(unixNanoseconds: 7)),
            fileKind: .regularFile,
            volume: .observed(try VolumeID("volume-a")),
            boundaries: .init(symlink: .observed(false), externalVolume: .observed(true))
        )

        return try Finding(
            detectorID: detectorID,
            detectorVersion: detectorVersion,
            provenance: .filesystemObservation,
            observation: observation,
            declaredRoot: .init(id: rootID),
            observationInstant: .init(monotonicNanoseconds: 8)
        )
    }
}

fileprivate struct ProjectedOutcomeCase: Sendable {
    let outcome: ScanOutcome
    let expectedState: ProjectedScanState
}

private let projectedOutcomeCases: [ProjectedOutcomeCase] = [
    .init(outcome: .complete, expectedState: .complete),
    .init(
        outcome: .partial(issues: [
            .init(
                rootID: try! DeclaredRootID("fixture-root"),
                detectorID: try! DetectorID("fixture.detector"),
                cause: .permissionDenied
            )
        ]),
        expectedState: .partial(issues: [
            .init(.init(
                rootID: try! DeclaredRootID("fixture-root"),
                detectorID: try! DetectorID("fixture.detector"),
                cause: .permissionDenied
            ))
        ])
    ),
    .init(outcome: .permissionDenied, expectedState: .permissionDenied),
    .init(outcome: .cancelled, expectedState: .cancelled),
    .init(outcome: .corruptMetadata, expectedState: .corruptMetadata),
    .init(outcome: .unsupportedLayout, expectedState: .unsupportedLayout)
]
