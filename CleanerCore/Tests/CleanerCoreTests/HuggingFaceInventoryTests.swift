import Testing

@testable import CleanerCore

@Suite("Hugging Face Inventory")
struct HuggingFaceInventoryTests {
    @Test
    func syntheticCacheProducesImmutableGraphAndSeparateAccounting() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let volume = try VolumeID("volume:default")
        let blobIdentity = FileIdentityEvidence(device: 10, node: 20)
        let incompleteIdentity = FileIdentityEvidence(device: 10, node: 21)
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [
                ModelStoreEnvironmentEvidence(name: "HF_HOME", valueState: .presentButNotAuthority)
            ],
            entries: [
                .directory(["models--owner--repo"]),
                .directory(["models--owner--repo", "refs"]),
                .file(["models--owner--repo", "refs", "main"], bytes: 4, text: "abc123"),
                .directory(["models--owner--repo", "snapshots"]),
                .directory(["models--owner--repo", "snapshots", "abc123"]),
                .symlink(
                    ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                    target: ["models--owner--repo", "blobs", "sha256"],
                    targetVolume: volume
                ),
                .directory(["models--owner--repo", "snapshots", "def456"]),
                .symlink(
                    ["models--owner--repo", "snapshots", "def456", "model.bin"],
                    target: ["models--owner--repo", "blobs", "sha256"],
                    targetVolume: volume
                ),
                .directory(["models--owner--repo", "blobs"]),
                .file(
                    ["models--owner--repo", "blobs", "sha256"],
                    bytes: 100,
                    identity: blobIdentity
                ),
                .file(
                    ["models--owner--repo", "blobs", "pending.incomplete"],
                    bytes: 7,
                    identity: incompleteIdentity
                ),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())
        let rootAuthorities = result.graph.roots.map { $0.authority }
        let environmentNames = result.graph.environmentEvidence.map { $0.name }
        let repositories = result.graph.repositories.map { $0.identity.repositoryID }
        let refTargets = result.graph.refs.map { $0.targetSnapshot }
        let snapshotIDs = result.graph.snapshotBlobEdges.map { $0.snapshotID }.sorted()
        let edgeBlobIDs = result.graph.snapshotBlobEdges.map { $0.blobID }
        let blobIdentities = result.graph.blobs.map { $0.identity.fileIdentity }
        let incompleteIdentities = result.graph.incompleteBlobs.map { $0.identity.fileIdentity }

        #expect(result.outcome == ScanOutcome.complete)
        #expect(rootAuthorities == [ModelStoreRootAuthority.documentedDefault(.huggingFaceCache)])
        #expect(environmentNames == ["HF_HOME"])
        #expect(repositories == ["models--owner--repo"])
        #expect(refTargets == ["abc123"])
        #expect(snapshotIDs == ["abc123", "def456"])
        #expect(edgeBlobIDs == ["sha256", "sha256"])
        #expect(blobIdentities == [EvidenceValue<FileIdentityEvidence>.observed(blobIdentity)])
        #expect(incompleteIdentities == [EvidenceValue<FileIdentityEvidence>.observed(incompleteIdentity)])

        let accounting = ModelStoreAccounting(graph: result.graph).summary
        #expect(accounting.logicalReferencedBytes == .observed(200))
        #expect(accounting.uniquePhysicalBytes == .observed(100))
        #expect(accounting.sharedBytesIncludedInUniquePhysical == .observed(100))
        #expect(accounting.locallyObservedIncompleteBytes == .observed(7))
        #expect(accounting.reclaimability == ModelStoreReclaimability.protectedNotEligible)

        let expectedCalls: [ModelStorePortCall] = [
            .rootEvidence(rootID),
            .nextEntry(nil),
            .nextEntry(1),
            .nextEntry(2),
            .readText(rootID, ["models--owner--repo", "refs", "main"], maximumBytes: 4096),
            .nextEntry(3),
            .nextEntry(4),
            .nextEntry(5),
            .inspectLink(rootID, ["models--owner--repo", "snapshots", "abc123", "model.bin"]),
            .nextEntry(6),
            .nextEntry(7),
            .inspectLink(rootID, ["models--owner--repo", "snapshots", "def456", "model.bin"]),
            .nextEntry(8),
            .nextEntry(9),
            .nextEntry(10),
            .nextEntry(11),
        ]
        #expect(port.calls == expectedCalls)
    }

    @Test
    func environmentEvidenceCannotCreateRootAuthority() async throws {
        let rootID = try DeclaredRootID("hf-explicit")
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:explicit"),
            environmentEvidence: [
                ModelStoreEnvironmentEvidence(name: "HF_HUB_CACHE", valueState: .presentButNotAuthority)
            ],
            entries: []
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated))
        let rootIDs = result.graph.roots.map { $0.identity.rootID }
        let rootAuthorities = result.graph.roots.map { $0.authority }

        #expect(result.outcome == ScanOutcome.unsupportedLayout)
        #expect(rootIDs == [rootID])
        #expect(rootAuthorities == [ModelStoreRootAuthority.explicitSelection(.validated)])
        #expect(result.graph.environmentEvidence.count == 1)
        #expect(result.graph.environmentEvidence.allSatisfy {
            $0.valueState == ModelStoreEnvironmentValueState.presentButNotAuthority
        })
    }

    @Test
    func strictLimitsRejectNonPositiveValues() {
        #expect(throws: ModelStoreParserLimitError.nonPositiveLimit) {
            _ = try ModelStoreParserLimits(
                maximumEntries: 0,
                maximumRefBytes: 4096,
                maximumGraphNodes: 16,
                maximumGraphEdges: 16,
                maximumDepth: 8,
                maximumObservedBytes: 1024
            )
        }
    }

    @Test
    func totalObservedByteBudgetStopsBeforeGraphInsertion() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:budget"),
            environmentEvidence: [],
            entries: [
                .directory(["models--owner--repo"]),
                .file(["models--owner--repo", "blobs", "oversized"], bytes: 20),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: try .init(
                maximumEntries: 8,
                maximumRefBytes: 4096,
                maximumGraphNodes: 8,
                maximumGraphEdges: 8,
                maximumDepth: 8,
                maximumObservedBytes: 10
            ),
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.blobs.isEmpty)
        #expect(result.graph.diagnostics.map { $0.code } == [.observedByteLimitExceeded])
    }

    @Test
    func depthBudgetRejectsDeepLocatorBeforeInsertion() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:depth"),
            environmentEvidence: [],
            entries: [
                .directory(["models--owner--repo", "snapshots", "abc123", "too-deep"]),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: try .init(
                maximumEntries: 8,
                maximumRefBytes: 4096,
                maximumGraphNodes: 8,
                maximumGraphEdges: 8,
                maximumDepth: 3,
                maximumObservedBytes: 1024
            ),
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())

        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.diagnostics.map { $0.code } == [.depthLimitExceeded])
    }

    @Test
    func accountingDoesNotEmitObservedZeroForUnverifiedIdentityOrSize() throws {
        let graph = ModelStoreGraph(
            detector: .huggingFaceV1,
            roots: [ModelStoreRoot.defaultHuggingFaceCache()],
            repositories: [.init(identity: .init(repositoryID: "models--owner--repo"))],
            refs: [],
            snapshots: [.init(repositoryID: "models--owner--repo", snapshotID: "abc123")],
            blobs: [
                .init(
                    identity: .init(
                        repositoryID: "models--owner--repo",
                        blobID: "sha256",
                        fileIdentity: .unavailable
                    ),
                    logicalBytes: .unavailable
                )
            ],
            incompleteBlobs: [],
            snapshotBlobEdges: [
                .init(
                    repositoryID: "models--owner--repo",
                    snapshotID: "abc123",
                    snapshotFileName: "model.bin",
                    blobID: "sha256"
                )
            ],
            diagnostics: [.init(code: .invalidSize)],
            environmentEvidence: [],
            protection: .inspectOnly(reason: .bounded)
        )

        let accounting = ModelStoreAccounting(graph: graph).summary

        #expect(accounting.logicalReferencedBytes == .unavailable)
        #expect(accounting.uniquePhysicalBytes == .unavailable)
        #expect(accounting.sharedBytesIncludedInUniquePhysical == .unavailable)
    }

    @Test
    func malformedRefTextIsCorruptMetadata() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:ref"),
            environmentEvidence: [],
            entries: [
                .directory(["models--owner--repo"]),
                .directory(["models--owner--repo", "refs"]),
                .file(["models--owner--repo", "refs", "main"], bytes: 6, text: "../bad"),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.diagnostics.map { $0.code } == [.corruptRef])
        #expect(result.graph.refs.isEmpty)
    }

    @Test
    func refTargetMustHaveObservedSnapshot() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:ref-target"),
            environmentEvidence: [],
            entries: [
                .directory(["models--owner--repo"]),
                .directory(["models--owner--repo", "refs"]),
                .file(["models--owner--repo", "refs", "main"], bytes: 6, text: "abc123"),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.diagnostics.map { $0.code } == [.corruptRef])
        #expect(result.graph.refs.map { $0.targetSnapshot } == ["abc123"])
    }

    @Test
    func cancellationAfterRefReadPreventsRefInsertion() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:cancel-ref"),
            environmentEvidence: [],
            entries: [
                .directory(["models--owner--repo"]),
                .directory(["models--owner--repo", "refs"]),
                .file(["models--owner--repo", "refs", "main"], bytes: 6, text: "abc123"),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: ScriptedModelStoreCancellation(responses: [false, false, false, false, false, false, true])
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())

        #expect(result.outcome == .cancelled)
        #expect(result.graph.refs.isEmpty)
    }

    @Test
    func cancellationAfterLinkInspectionPreventsEdgeInsertion() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let volume = try VolumeID("volume:cancel-link")
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [
                .directory(["models--owner--repo"]),
                .directory(["models--owner--repo", "snapshots"]),
                .directory(["models--owner--repo", "snapshots", "abc123"]),
                .symlink(
                    ["models--owner--repo", "snapshots", "abc123", "model.bin"],
                    target: ["models--owner--repo", "blobs", "sha256"],
                    targetVolume: volume
                ),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: ScriptedModelStoreCancellation(responses: [false, false, false, false, false, false, false, false, true])
        )

        let result = await parser.parse(root: ModelStoreRoot.defaultHuggingFaceCache())

        #expect(result.outcome == .cancelled)
        #expect(result.graph.snapshotBlobEdges.isEmpty)
    }

    @Test
    func accountingOverflowIsUnavailableNotSaturatedObserved() throws {
        let first = FileIdentityEvidence(device: 10, node: 1)
        let second = FileIdentityEvidence(device: 10, node: 2)
        let graph = ModelStoreGraph(
            detector: .huggingFaceV1,
            roots: [ModelStoreRoot.defaultHuggingFaceCache()],
            repositories: [.init(identity: .init(repositoryID: "models--owner--repo"))],
            refs: [],
            snapshots: [.init(repositoryID: "models--owner--repo", snapshotID: "abc123")],
            blobs: [
                .init(
                    identity: .init(repositoryID: "models--owner--repo", blobID: "one", fileIdentity: .observed(first)),
                    logicalBytes: Int.max
                ),
                .init(
                    identity: .init(repositoryID: "models--owner--repo", blobID: "two", fileIdentity: .observed(second)),
                    logicalBytes: 1
                ),
            ],
            incompleteBlobs: [],
            snapshotBlobEdges: [],
            diagnostics: [],
            environmentEvidence: [],
            protection: .inspectOnly(reason: .inventoryOnly)
        )

        let accounting = ModelStoreAccounting(graph: graph).summary

        #expect(accounting.uniquePhysicalBytes == .unavailable)
    }

    @Test
    func documentedLocksMetadataDoesNotMakeCacheUnknownLayout() async throws {
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:locks"),
            environmentEvidence: [],
            entries: [
                .directory([".locks"]),
                .directory([".locks", "models--owner--repo"]),
                .file([".locks", "models--owner--repo", "sha256.lock"], bytes: 0),
                .directory(["models--owner--repo"]),
            ]
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: .defaultHuggingFaceCache())

        #expect(result.outcome == .complete)
        #expect(result.graph.diagnostics.isEmpty)
    }
}
