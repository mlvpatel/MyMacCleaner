import Testing

@testable import CleanerCore

@Suite("Hugging Face Hostile Fixtures")
struct HuggingFaceHostileFixtureTests {
    @Test(arguments: hostileCases)
    fileprivate func hostileStoresRemainProtectedEvidence(_ testCase: HostileHuggingFaceCase) async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: hostileFixtureVolume,
            environmentEvidence: [],
            rootFault: testCase.rootFault,
            entries: testCase.entries
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: testCase.limits,
            port: port,
            cancellation: testCase.cancellation
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())
        let diagnosticCodes = result.graph.diagnostics.map { $0.code }

        #expect(result.outcome == testCase.expectedOutcome)
        #expect(diagnosticCodes == testCase.expectedDiagnostics)
        #expect(result.graph.protection == ModelStoreProtection.inspectOnly(reason: testCase.expectedProtection))
        #expect(
            ModelStoreAccounting(graph: result.graph).summary.reclaimability
                == ModelStoreReclaimability.protectedNotEligible
        )
    }
}

private struct HostileHuggingFaceCase: Sendable {
    let name: String
    let rootFault: ModelStoreRootFault?
    let entries: [ModelStoreEntryEvidence]
    let limits: ModelStoreParserLimits
    let cancellation: any ModelStoreCancellation
    let expectedOutcome: ScanOutcome
    let expectedDiagnostics: [ModelStoreDiagnosticCode]
    let expectedProtection: ModelStoreProtectionReason
}

private let hostileCases: [HostileHuggingFaceCase] = [
    .init(
        name: "unavailable-volume",
        rootFault: .unavailableVolume,
        entries: [],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .unsupportedLayout,
        expectedDiagnostics: [.unavailableVolume],
        expectedProtection: .unavailableVolume
    ),
    .init(
        name: "oversized-ref",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "refs"]),
            .file(["models--owner--repo", "refs", "main"], bytes: 5000, text: String(repeating: "a", count: 5000)),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.oversizedRef],
        expectedProtection: .corruptRef
    ),
    .init(
        name: "dangling-link",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                target: ["models--owner--repo", "blobs", "missing"],
                targetExists: false
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.danglingLink],
        expectedProtection: .invalidLink
    ),
    .init(
        name: "escaping-link",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                target: ["outside", "blob"]
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .unsupportedLayout,
        expectedDiagnostics: [.escapingLink],
        expectedProtection: .boundaryViolation
    ),
    .init(
        name: "cross-volume",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                target: ["models--owner--repo", "blobs", "sha256"],
                targetVolume: try! VolumeID("volume:external")
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .unsupportedLayout,
        expectedDiagnostics: [.crossVolumeLink],
        expectedProtection: .boundaryViolation
    ),
    .init(
        name: "cancelled",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"])
        ],
        limits: .fixture,
        cancellation: ScriptedModelStoreCancellation(responses: [false, true]),
        expectedOutcome: .cancelled,
        expectedDiagnostics: [.cancelled],
        expectedProtection: .cancelled
    ),
    .init(
        name: "entry-budget",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "refs"]),
        ],
        limits: try! .init(
            maximumEntries: 1,
            maximumRefBytes: 4096,
            maximumGraphNodes: 16,
            maximumGraphEdges: 16,
            maximumDepth: 8,
            maximumObservedBytes: 1024
        ),
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.entryLimitExceeded],
        expectedProtection: .bounded
    ),
    .init(
        name: "missing-observed-blob",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                target: ["models--owner--repo", "blobs", "missing"],
                targetVolume: hostileFixtureVolume
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.missingBlob],
        expectedProtection: .missingBlob
    ),
    .init(
        name: "wrong-target-kind",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                target: ["models--owner--repo", "blobs", "not-file"],
                targetKind: .directory
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.invalidTargetKind],
        expectedProtection: .invalidLink
    ),
    .init(
        name: "unavailable-target-metadata",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .file(["models--owner--repo", "blobs", "sha256"], bytes: 1),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                target: ["models--owner--repo", "blobs", "sha256"],
                targetKind: nil
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .unsupportedLayout,
        expectedDiagnostics: [.unavailableTargetMetadata],
        expectedProtection: .boundaryViolation
    ),
    .init(
        name: "root-changed",
        rootFault: .rootChanged,
        entries: [],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.rootChanged],
        expectedProtection: .changedStore
    ),
    .init(
        name: "volume-changed",
        rootFault: .volumeChanged,
        entries: [],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.volumeChanged],
        expectedProtection: .changedStore
    ),
    .init(
        name: "multi-node-cycle",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "a.bin"],
                target: ["models--owner--repo", "snapshots", "abc123", "b.bin"],
                targetKind: .symbolicLink
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .unsupportedLayout,
        expectedDiagnostics: [.cyclicLink],
        expectedProtection: .invalidLink
    ),
    .init(
        name: "node-cap",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "refs"]),
        ],
        limits: try! .init(
            maximumEntries: 8,
            maximumRefBytes: 4096,
            maximumGraphNodes: 1,
            maximumGraphEdges: 8,
            maximumDepth: 8,
            maximumObservedBytes: 1024
        ),
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.graphLimitExceeded],
        expectedProtection: .bounded
    ),
    .init(
        name: "negative-size",
        rootFault: nil,
        entries: [
            .file(["models--owner--repo", "blobs", "negative"], bytes: -1),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.invalidSize],
        expectedProtection: .bounded
    ),
    .init(
        name: "missing-size",
        rootFault: nil,
        entries: [
            .init(
                locator: try! .init(["models--owner--repo", "blobs", "missing-size"]),
                kind: .regularFile,
                size: .init(logicalBytes: .unavailable),
                fileIdentity: .unavailable,
                volume: .unavailable,
                text: nil,
                link: nil
            ),
        ],
        limits: .fixture,
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.invalidSize],
        expectedProtection: .bounded
    ),
    .init(
        name: "edge-cap",
        rootFault: nil,
        entries: [
            .directory(["models--owner--repo"]),
            .directory(["models--owner--repo", "snapshots"]),
            .directory(["models--owner--repo", "snapshots", "abc123"]),
            .file(["models--owner--repo", "blobs", "sha256"], bytes: 1),
            .file(["models--owner--repo", "blobs", "sha257"], bytes: 1),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                target: ["models--owner--repo", "blobs", "sha256"],
                targetVolume: hostileFixtureVolume
            ),
            .symlink(
                ["models--owner--repo", "snapshots", "abc123", "model-2.bin"],
                target: ["models--owner--repo", "blobs", "sha257"],
                targetVolume: hostileFixtureVolume
            ),
        ],
        limits: try! .init(
            maximumEntries: 8,
            maximumRefBytes: 4096,
            maximumGraphNodes: 8,
            maximumGraphEdges: 1,
            maximumDepth: 8,
            maximumObservedBytes: 1024
        ),
        cancellation: NeverCancelledModelStoreCancellation(),
        expectedOutcome: .corruptMetadata,
        expectedDiagnostics: [.graphLimitExceeded],
        expectedProtection: .bounded
    ),
]

private let hostileFixtureVolume = try! VolumeID("volume:hostile")
