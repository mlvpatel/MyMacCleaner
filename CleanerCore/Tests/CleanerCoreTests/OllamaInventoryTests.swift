import Testing

@testable import CleanerCore

@Suite("Ollama inventory")
struct OllamaInventoryTests {
    @Test
    func verifiedDigestMapsToOneContainedBlobName() throws {
        let digest = "sha256:" + String(repeating: "a", count: 64)

        #expect(
            OllamaLayoutContract.v1.blobFileName(for: digest)
                == "sha256-" + String(repeating: "a", count: 64)
        )
    }

    @Test
    func invalidDigestDoesNotProduceBlobName() {
        #expect(OllamaLayoutContract.v1.blobFileName(for: "sha512:abc") == nil)
        #expect(OllamaLayoutContract.v1.blobFileName(for: "sha256:abc") == nil)
    }

    @Test
    func contractUsesTypedPinnedSourcesForItsConservativeMediaAllowlist() {
        let contract = OllamaLayoutContract.v1

        #expect(contract.manifestSource.scheme == .https)
        #expect(contract.manifestSource.host == "github.com")
        #expect(contract.layerMediaTypes == Set(contract.layerMediaTypeSources.keys))
        #expect(contract.layerMediaTypeSources.values.allSatisfy {
            $0.scheme == .https && $0.host == "github.com" && $0.path.contains(contract.sourceCommit)
        })
        #expect(contract.layerMediaTypeSources["application/vnd.ollama.image.model"]?.path.hasSuffix("server/images.go") == true)
        #expect(contract.layerMediaTypeSources["application/vnd.ollama.image.tensor"]?.path.hasSuffix("manifest/layer.go") == true)
    }

    @Test
    func twoTagsShareVerifiedConfigAndLayerWithoutDoubleCounting() async throws {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:ollama")
        let configDigest = "sha256:" + String(repeating: "a", count: 64)
        let layerDigest = "sha256:" + String(repeating: "b", count: 64)
        let configFile = try #require(OllamaLayoutContract.v1.blobFileName(for: configDigest))
        let layerFile = try #require(OllamaLayoutContract.v1.blobFileName(for: layerDigest))
        let firstManifest = ["manifests", "registry", "acme", "demo", "latest"]
        let secondManifest = ["manifests", "registry", "acme", "demo", "stable"]
        let manifest = OllamaManifestObservation(
            schemaVersion: 2,
            mediaType: "application/vnd.docker.distribution.manifest.v2+json",
            config: .init(mediaType: "application/vnd.ollama.image.config", digest: configDigest, size: 5),
            layers: [.init(mediaType: "application/vnd.ollama.image.model", digest: layerDigest, size: 10)]
        )
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [
                .directory(["manifests"]),
                .file(firstManifest, bytes: 128, identity: .init(device: 1, node: 1)),
                .file(secondManifest, bytes: 128, identity: .init(device: 1, node: 2)),
                .directory(["blobs"]),
                .file(["blobs", configFile], bytes: 5, identity: .init(device: 1, node: 3)),
                .file(["blobs", layerFile], bytes: 10, identity: .init(device: 1, node: 4)),
            ],
            ollamaManifests: [firstManifest: manifest, secondManifest: manifest]
        )
        let parser = OllamaStoreParser(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: .defaultOllamaModels())
        let accounting = ModelStoreAccounting(graph: result.graph).summary

        #expect(result.outcome == .complete)
        #expect(result.graph.refs.count == 2)
        #expect(result.graph.snapshotBlobEdges.count == 4)
        #expect(result.graph.blobs.count == 2)
        #expect(accounting.logicalReferencedBytes == .observed(30))
        #expect(accounting.uniquePhysicalBytes == .observed(15))
        #expect(accounting.sharedBytesIncludedInUniquePhysical == .observed(15))
        #expect(accounting.reclaimability == .protectedNotEligible)
        #expect(port.calls.contains(.readOllamaManifest(rootID, firstManifest, maximumBytes: 4096)))
        #expect(port.calls.contains(.readOllamaManifest(rootID, secondManifest, maximumBytes: 4096)))
    }

    @Test(arguments: [
        "sha512:" + String(repeating: "a", count: 64),
        "sha256:" + String(repeating: "g", count: 64),
        "sha256:" + String(repeating: "a", count: 63),
    ])
    func unverifiedLayerDigestFailsClosed(_ digest: String) async throws {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:invalid-digest")
        let manifestLocator = ["manifests", "registry", "acme", "demo", "latest"]
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [.file(manifestLocator, bytes: 128, identity: .init(device: 2, node: 1))],
            ollamaManifests: [
                manifestLocator: .init(
                    schemaVersion: 2,
                    mediaType: "application/vnd.docker.distribution.manifest.v2+json",
                    config: .init(mediaType: "config", digest: digest, size: 1),
                    layers: []
                )
            ]
        )
        let parser = OllamaStoreParser(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: .defaultOllamaModels())

        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.blobs.isEmpty)
        #expect(result.graph.protection == .inspectOnly(reason: .unknownLayout))
    }

    @Test(arguments: [
        (schema: 1, media: "application/vnd.docker.distribution.manifest.v2+json"),
        (schema: 2, media: "application/json"),
    ])
    func unsupportedManifestSchemaOrMediaFailsBeforeBlobEdge(
        _ input: (schema: Int, media: String)
    ) async throws {
        let result = try await parseOneManifest(
            manifest: .init(
                schemaVersion: input.schema,
                mediaType: input.media,
                config: .init(mediaType: "application/vnd.ollama.image.config", digest: validDigest("c"), size: 1),
                layers: []
            ),
            blobs: []
        )

        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.snapshotBlobEdges.isEmpty)
        #expect(result.graph.protection == .inspectOnly(reason: .unknownLayout))
    }

    @Test
    func missingBlobAndCrossVolumeBlobRemainProtected() async throws {
        let digest = validDigest("d")
        let manifest = validManifest(configDigest: digest, configSize: 1)
        let missing = try await parseOneManifest(manifest: manifest, blobs: [])
        #expect(missing.outcome == .corruptMetadata)
        #expect(missing.graph.protection == .inspectOnly(reason: .missingBlob))

        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let rootVolume = try VolumeID("volume:root")
        let foreignVolume = try VolumeID("volume:foreign")
        let manifestLocator = ["manifests", "registry", "acme", "demo", "latest"]
        let blobName = try #require(OllamaLayoutContract.v1.blobFileName(for: digest))
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: rootVolume,
            environmentEvidence: [],
            entries: [
                .init(
                    locator: try .init(manifestLocator),
                    kind: .regularFile,
                    size: .init(logicalBytes: 128),
                    fileIdentity: .observed(.init(device: 3, node: 1)),
                    volume: .observed(rootVolume),
                    text: nil,
                    link: nil
                ),
                .init(
                    locator: try .init(["blobs", blobName]),
                    kind: .regularFile,
                    size: .init(logicalBytes: 1),
                    fileIdentity: .observed(.init(device: 3, node: 2)),
                    volume: .observed(foreignVolume),
                    text: nil,
                    link: nil
                ),
            ],
            ollamaManifests: [manifestLocator: manifest],
            normalizeEntryMetadata: false
        )
        let parser = OllamaStoreParser(limits: .fixture, port: port, cancellation: NeverCancelledModelStoreCancellation())
        let crossVolume = await parser.parse(root: .defaultOllamaModels())

        #expect(crossVolume.outcome == .unsupportedLayout)
        #expect(crossVolume.graph.snapshotBlobEdges.isEmpty)
        #expect(crossVolume.graph.protection == .inspectOnly(reason: .boundaryViolation))
    }

    @Test
    func conflictingDuplicateBlobEvidenceAndNodeBudgetFailClosed() async throws {
        let digest = validDigest("e")
        let blobName = try #require(OllamaLayoutContract.v1.blobFileName(for: digest))
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:duplicates")
        let duplicatePort = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [
                .file(["blobs", blobName], bytes: 1, identity: .init(device: 4, node: 1)),
                .file(["blobs", blobName], bytes: 2, identity: .init(device: 4, node: 2)),
            ]
        )
        let duplicateParser = OllamaStoreParser(limits: .fixture, port: duplicatePort, cancellation: NeverCancelledModelStoreCancellation())
        let duplicate = await duplicateParser.parse(root: .defaultOllamaModels())
        #expect(duplicate.outcome == .corruptMetadata)
        #expect(duplicate.graph.diagnostics.map(\.code) == [.invalidSize])

        let limited = try await parseOneManifest(
            manifest: validManifest(configDigest: digest, configSize: 1),
            blobs: [["blobs", blobName]],
            limits: try .init(
                maximumEntries: 8,
                maximumRefBytes: 4096,
                maximumGraphNodes: 3,
                maximumGraphEdges: 8,
                maximumDepth: 8,
                maximumObservedBytes: 1024
            )
        )
        #expect(limited.outcome == .corruptMetadata)
        #expect(limited.graph.diagnostics.map(\.code) == [.graphLimitExceeded])
    }

    @Test
    func digestCaseAndSeparatorRequireTheExactPinnedBlobMapping() async throws {
        let upperDigest = validDigest("A")
        let upperFile = try #require(OllamaLayoutContract.v1.blobFileName(for: upperDigest))
        let upper = try await parseOneManifest(
            manifest: validManifest(configDigest: upperDigest, configSize: 1),
            blobs: [["blobs", upperFile]]
        )
        #expect(upper.outcome == .complete)

        let lowerFile = "sha256-" + String(repeating: "a", count: 64)
        let mismatchedCase = try await parseOneManifest(
            manifest: validManifest(configDigest: upperDigest, configSize: 1),
            blobs: [["blobs", lowerFile]]
        )
        #expect(mismatchedCase.outcome == .corruptMetadata)
        #expect(mismatchedCase.graph.protection == .inspectOnly(reason: .missingBlob))

        let hyphenDigest = "sha256-" + String(repeating: "A", count: 64)
        let hyphen = try await parseOneManifest(
            manifest: validManifest(configDigest: hyphenDigest, configSize: 1),
            blobs: [["blobs", upperFile]]
        )
        #expect(hyphen.outcome == .complete)
    }

    @Test
    func unsupportedDescriptorMediaFailsBeforeAnyGraphRelationship() async throws {
        let result = try await parseOneManifest(
            manifest: .init(
                schemaVersion: 2,
                mediaType: "application/vnd.docker.distribution.manifest.v2+json",
                config: .init(mediaType: "application/vnd.ollama.image.config", digest: validDigest("f"), size: 1),
                layers: [.init(mediaType: "application/vnd.ollama.image.unrecognized", digest: validDigest("e"), size: 1)]
            ),
            blobs: []
        )

        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.refs.isEmpty)
        #expect(result.graph.snapshots.isEmpty)
        #expect(result.graph.snapshotBlobEdges.isEmpty)
    }

    @Test
    func malformedManifestPathFailsBeforeManifestRead() async throws {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:bad-path")
        let malformedPath = ["manifests", "registry", "acme", "demo"]
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [.file(malformedPath, bytes: 1, identity: .init(device: 6, node: 1))]
        )

        let result = await OllamaStoreParser(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: .defaultOllamaModels())

        #expect(result.outcome == .unsupportedLayout)
        #expect(!port.calls.contains { call in
            if case .readOllamaManifest = call { return true }
            return false
        })
    }

    @Test
    func cancellationAfterManifestReadPublishesNoRelationships() async throws {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:cancel-ollama")
        let digest = validDigest("c")
        let manifestLocator = ["manifests", "registry", "acme", "demo", "latest"]
        let blobName = try #require(OllamaLayoutContract.v1.blobFileName(for: digest))
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [
                .file(manifestLocator, bytes: 128, identity: .init(device: 8, node: 1)),
                .file(["blobs", blobName], bytes: 1, identity: .init(device: 8, node: 2)),
            ],
            ollamaManifests: [
                manifestLocator: validManifest(configDigest: digest, configSize: 1)
            ]
        )
        let parser = OllamaStoreParser(
            limits: .fixture,
            port: port,
            cancellation: ScriptedModelStoreCancellation(responses: [false, false, false, false, false, false, true])
        )

        let result = await parser.parse(root: .defaultOllamaModels())

        #expect(result.outcome == .cancelled)
        #expect(result.graph.repositories.isEmpty)
        #expect(result.graph.refs.isEmpty)
        #expect(result.graph.snapshots.isEmpty)
        #expect(result.graph.snapshotBlobEdges.isEmpty)
        #expect(port.calls.contains(.readOllamaManifest(rootID, manifestLocator, maximumBytes: 4096)))
    }

    @Test
    func crossRepositorySharedPhysicalLayerIsDeduplicatedWithoutTrap() throws {
        let identity = FileIdentityEvidence(device: 7, node: 11)
        let firstRepository = "registry/acme/first"
        let secondRepository = "registry/acme/second"
        let graph = ModelStoreGraph(
            detector: .ollamaV1,
            roots: [.defaultOllamaModels()],
            repositories: [.init(identity: .init(repositoryID: firstRepository)), .init(identity: .init(repositoryID: secondRepository))],
            refs: [],
            snapshots: [
                .init(repositoryID: firstRepository, snapshotID: "first"),
                .init(repositoryID: secondRepository, snapshotID: "second"),
            ],
            blobs: [
                .init(identity: .init(repositoryID: firstRepository, blobID: "sha256:shared", fileIdentity: .observed(identity)), logicalBytes: 10),
                .init(identity: .init(repositoryID: secondRepository, blobID: "sha256:shared", fileIdentity: .observed(identity)), logicalBytes: 10),
            ],
            incompleteBlobs: [],
            snapshotBlobEdges: [
                .init(repositoryID: firstRepository, snapshotID: "first", snapshotFileName: "layer-0", blobID: "sha256:shared"),
                .init(repositoryID: secondRepository, snapshotID: "second", snapshotFileName: "layer-0", blobID: "sha256:shared"),
            ],
            diagnostics: [],
            environmentEvidence: [],
            protection: .inspectOnly(reason: .inventoryOnly)
        )

        let accounting = ModelStoreAccounting(graph: graph).summary

        #expect(accounting.logicalReferencedBytes == .observed(20))
        #expect(accounting.uniquePhysicalBytes == .observed(10))
        #expect(accounting.sharedBytesIncludedInUniquePhysical == .observed(10))
    }

    private func parseOneManifest(
        manifest: OllamaManifestObservation,
        blobs: [[String]],
        limits: ModelStoreParserLimits = .fixture
    ) async throws -> ModelStoreParseResult {
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let volume = try VolumeID("volume:single")
        let manifestLocator = ["manifests", "registry", "acme", "demo", "latest"]
        let entries = [
            ModelStoreEntryEvidence.file(manifestLocator, bytes: 128, identity: .init(device: 9, node: 1)),
        ] + blobs.enumerated().map { index, locator in
            .file(locator, bytes: 1, identity: .init(device: 9, node: UInt64(index + 2)))
        }
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: entries,
            ollamaManifests: [manifestLocator: manifest]
        )
        return await OllamaStoreParser(
            limits: limits,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: .defaultOllamaModels())
    }

    private func validManifest(configDigest: String, configSize: Int) -> OllamaManifestObservation {
        .init(
            schemaVersion: 2,
            mediaType: "application/vnd.docker.distribution.manifest.v2+json",
            config: .init(mediaType: "application/vnd.ollama.image.config", digest: configDigest, size: configSize),
            layers: []
        )
    }

    private func validDigest(_ character: Character) -> String {
        "sha256:" + String(repeating: String(character), count: 64)
    }
}
