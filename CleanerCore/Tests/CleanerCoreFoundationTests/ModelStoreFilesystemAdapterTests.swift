import Foundation
import Testing
@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Model Store Foundation Adapter")
struct ModelStoreFilesystemAdapterTests {
    @Test
    func realHuggingFaceTreeParsesRefsLinksAndBlobs() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot)
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(
            rootURLs: [rootID: fixture.firstRoot],
            fileManager: FileManager()
        )
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: adapter,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: .defaultHuggingFaceCache())

        #expect(result.outcome == .complete)
        #expect(result.graph.refs.map { $0.targetSnapshot } == ["abc123"])
        #expect(result.graph.snapshotBlobEdges.map { $0.blobID } == ["sha256"])
        #expect(result.graph.blobs.map { $0.identity.blobID } == ["sha256"])
    }

    @Test
    func realOllamaTreeDecodesBoundedManifestWithoutBlobAction() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalOllamaStore(root: fixture.firstRoot)
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        let parser = OllamaStoreParser(
            limits: .fixture,
            port: adapter,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: .defaultOllamaModels())

        #expect(result.outcome == .complete)
        #expect(result.graph.refs.count == 1)
        #expect(result.graph.snapshotBlobEdges.count == 2)
        #expect(result.graph.blobs.count == 2)
        #expect(ModelStoreProjection(result: result).entries.allSatisfy { !$0.isSelected && $0.operation == nil })
    }

    @Test
    func malformedOllamaManifestJSONFailsAsProtectedCorruptEvidence() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeOllamaManifest(
            root: fixture.firstRoot,
            source: """
            {"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json","config":{"mediaType":"application/vnd.ollama.image.config","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":true},"layers":[]}
            """
        )
        let rootID = ModelStoreRoot.ollamaDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        let parser = OllamaStoreParser(
            limits: .fixture,
            port: adapter,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await parser.parse(root: .defaultOllamaModels())

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.protection == .inspectOnly(reason: .corruptRef))
        #expect(result.graph.snapshotBlobEdges.isEmpty)
    }

    @Test
    func sameLocatorIsBoundToRequestedRoot() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot, snapshot: "abc123")
        try fixture.writeMinimalHuggingFaceCache(root: fixture.secondRoot, snapshot: "def456")
        let firstID = try DeclaredRootID("explicit-first")
        let secondID = try DeclaredRootID("explicit-second")
        let adapter = try ModelStoreFilesystemAdapter(
            rootURLs: [firstID: fixture.firstRoot, secondID: fixture.secondRoot],
            fileManager: FileManager()
        )
        let firstRoot = ModelStoreRoot.explicitlySelected(rootID: firstID, selection: .validated)
        let secondRoot = ModelStoreRoot.explicitlySelected(rootID: secondID, selection: .validated)
        _ = await adapter.rootEvidence(for: firstRoot)
        _ = await adapter.rootEvidence(for: secondRoot)

        let firstRef = try await fixture.firstEntry(from: adapter, root: firstRoot, matching: ["models--owner--repo", "refs", "main"])
        let secondRef = try await fixture.firstEntry(from: adapter, root: secondRoot, matching: ["models--owner--repo", "refs", "main"])
        let firstRead = await adapter.readText(
            in: firstRoot,
            at: firstRef.locator,
            expectedIdentity: firstRef.fileIdentity,
            maximumBytes: 4096
        )
        let secondRead = await adapter.readText(
            in: secondRoot,
            at: secondRef.locator,
            expectedIdentity: secondRef.fileIdentity,
            maximumBytes: 4096
        )

        #expect(firstRef.locator == secondRef.locator)
        #expect(firstRef.fileIdentity != secondRef.fileIdentity)
        #expect(firstRead == .success("abc123"))
        #expect(secondRead == .success("def456"))
        #expect(firstRoot.identity.rootID != secondRoot.identity.rootID)
    }

    @Test
    func symlinkRootIsUnavailableAndRootSwapStopsTraversal() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot)
        let linkRoot = fixture.parent.appendingPathComponent("linked-root")
        try FileManager().createSymbolicLink(at: linkRoot, withDestinationURL: fixture.firstRoot)
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let symlinkAdapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: linkRoot], fileManager: FileManager())

        let symlinkEvidence = await symlinkAdapter.rootEvidence(for: .defaultHuggingFaceCache())

        #expect(symlinkEvidence.fault == .unavailableVolume)

        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        _ = await adapter.rootEvidence(for: .defaultHuggingFaceCache())
        _ = await adapter.nextEntry(after: nil, in: .defaultHuggingFaceCache())
        try fixture.replaceFirstRoot()

        let afterSwap = await adapter.nextEntry(after: .init(position: 1), in: .defaultHuggingFaceCache())

        #expect(afterSwap == .fault(.rootChanged) || afterSwap == .fault(.volumeChanged))
    }

    @Test
    func swappedLeafCannotBeReadWithOldIdentity() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot)
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        _ = await adapter.rootEvidence(for: .defaultHuggingFaceCache())
        let refEntry = try await fixture.firstEntry(
            from: adapter,
            matching: ["models--owner--repo", "refs", "main"]
        )
        let refURL = fixture.firstRoot
            .appendingPathComponent("models--owner--repo")
            .appendingPathComponent("refs")
            .appendingPathComponent("main")
        try FileManager().removeItem(at: refURL)
        try "def456".write(to: refURL, atomically: true, encoding: .utf8)

        let read = await adapter.readText(
            in: .defaultHuggingFaceCache(),
            at: refEntry.locator,
            expectedIdentity: refEntry.fileIdentity,
            maximumBytes: 4096
        )

        #expect(read == .failure(.rootChanged))
    }

    @Test
    func swappedLinkCannotBeInspectedWithOldIdentity() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot)
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        _ = await adapter.rootEvidence(for: .defaultHuggingFaceCache())
        let linkEntry = try await fixture.firstEntry(
            from: adapter,
            matching: ["models--owner--repo", "snapshots", "abc123", "model.bin"]
        )
        let linkURL = fixture.firstRoot
            .appendingPathComponent("models--owner--repo")
            .appendingPathComponent("snapshots")
            .appendingPathComponent("abc123")
            .appendingPathComponent("model.bin")
        try FileManager().removeItem(at: linkURL)
        try FileManager().createSymbolicLink(atPath: linkURL.path, withDestinationPath: "../../blobs/other")

        let inspection = await adapter.inspectLink(
            in: .defaultHuggingFaceCache(),
            at: linkEntry.locator,
            expectedIdentity: linkEntry.fileIdentity
        )

        #expect(inspection.diagnostic == .rootChanged)
    }

    @Test
    func targetSymlinkMetadataIsReportedWithoutFollowingIt() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot)
        let repo = fixture.firstRoot.appendingPathComponent("models--owner--repo")
        let blob = repo.appendingPathComponent("blobs").appendingPathComponent("sha256")
        let realBlob = repo.appendingPathComponent("blobs").appendingPathComponent("sha256-real")
        try FileManager().moveItem(at: blob, to: realBlob)
        try FileManager().createSymbolicLink(atPath: blob.path, withDestinationPath: "sha256-real")
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        _ = await adapter.rootEvidence(for: .defaultHuggingFaceCache())
        let linkEntry = try await fixture.firstEntry(
            from: adapter,
            matching: ["models--owner--repo", "snapshots", "abc123", "model.bin"]
        )

        let inspection = await adapter.inspectLink(
            in: .defaultHuggingFaceCache(),
            at: linkEntry.locator,
            expectedIdentity: linkEntry.fileIdentity
        )

        #expect(inspection.targetExists == true)
        #expect(inspection.targetKind == .observed(.symbolicLink))
        guard case .observed = inspection.targetVolume else {
            Issue.record("Expected symlink target volume evidence from no-follow metadata.")
            return
        }
    }

    @Test
    func targetThroughSwappedIntermediateSymlinkIsNotReportedAsContainedMetadata() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot)
        let repo = fixture.firstRoot.appendingPathComponent("models--owner--repo")
        let realBlobs = repo.appendingPathComponent("blobs-real")
        try FileManager().moveItem(at: repo.appendingPathComponent("blobs"), to: realBlobs)
        try FileManager().createSymbolicLink(
            atPath: repo.appendingPathComponent("blobs").path,
            withDestinationPath: "blobs-real"
        )
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        _ = await adapter.rootEvidence(for: .defaultHuggingFaceCache())
        let linkEntry = try await fixture.firstEntry(
            from: adapter,
            matching: ["models--owner--repo", "snapshots", "abc123", "model.bin"]
        )

        let inspection = await adapter.inspectLink(
            in: .defaultHuggingFaceCache(),
            at: linkEntry.locator,
            expectedIdentity: linkEntry.fileIdentity
        )

        #expect(inspection.targetExists == false)
        #expect(inspection.targetKind == .unavailable)
        #expect(inspection.targetVolume == .unavailable)
    }

    @Test
    func deniedDescendantEnumerationReturnsPermissionFaultNotComplete() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        let denied = fixture.firstRoot.appendingPathComponent("denied")
        try FileManager().createDirectory(at: denied, withIntermediateDirectories: true)
        try Data([1]).write(to: denied.appendingPathComponent("hidden.bin"))
        try FileManager().setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer {
            try? FileManager().setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        }
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let adapter = try ModelStoreFilesystemAdapter(rootURLs: [rootID: fixture.firstRoot], fileManager: FileManager())
        _ = await adapter.rootEvidence(for: .defaultHuggingFaceCache())

        var cursor: ModelStoreCursor?
        for index in 0..<8 {
            let step = await adapter.nextEntry(after: cursor, in: .defaultHuggingFaceCache())
            if step == .fault(.permissionDenied) {
                return
            }
            if step == .complete {
                Issue.record("Denied descendant must not collapse to complete.")
                return
            }
            cursor = .init(position: UInt(index + 1))
        }

        Issue.record("Expected denied descendant fault within bounded enumeration.")
    }

    @Test
    func entryCapAndDepthReturnTypedFaults() async throws {
        let fixture = try ModelStoreTemporaryFixture()
        try fixture.writeMinimalHuggingFaceCache(root: fixture.firstRoot)
        let rootID = ModelStoreRoot.huggingFaceDefaultRootID
        let capped = try ModelStoreFilesystemAdapter(
            rootURLs: [rootID: fixture.firstRoot],
            fileManager: FileManager(),
            maximumEntriesPerRoot: 1
        )
        _ = await capped.rootEvidence(for: .defaultHuggingFaceCache())
        _ = await capped.nextEntry(after: nil, in: .defaultHuggingFaceCache())

        #expect(await capped.nextEntry(after: .init(position: 1), in: .defaultHuggingFaceCache()) == .fault(.entryLimitExceeded))

        let shallow = try ModelStoreFilesystemAdapter(
            rootURLs: [rootID: fixture.firstRoot],
            fileManager: FileManager(),
            maximumDepth: 1
        )
        _ = await shallow.rootEvidence(for: .defaultHuggingFaceCache())
        _ = await shallow.nextEntry(after: nil, in: .defaultHuggingFaceCache())

        #expect(await shallow.nextEntry(after: .init(position: 1), in: .defaultHuggingFaceCache()) == .fault(.depthLimitExceeded))
    }
}

private final class ModelStoreTemporaryFixture {
    let parent: URL
    let firstRoot: URL
    let secondRoot: URL
    private let manager = FileManager()

    init() throws {
        parent = manager.temporaryDirectory
            .appendingPathComponent("mymaccleaner-model-store-tests")
            .appendingPathComponent(UUID().uuidString)
        firstRoot = parent.appendingPathComponent("first")
        secondRoot = parent.appendingPathComponent("second")
        try manager.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try manager.createDirectory(at: secondRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? manager.removeItem(at: parent)
    }

    func writeMinimalHuggingFaceCache(root: URL, snapshot: String = "abc123") throws {
        let repo = root.appendingPathComponent("models--owner--repo")
        let refs = repo.appendingPathComponent("refs")
        let snapshots = repo.appendingPathComponent("snapshots").appendingPathComponent(snapshot)
        let blobs = repo.appendingPathComponent("blobs")
        try manager.createDirectory(at: refs, withIntermediateDirectories: true)
        try manager.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try manager.createDirectory(at: blobs, withIntermediateDirectories: true)
        try snapshot.write(to: refs.appendingPathComponent("main"), atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: blobs.appendingPathComponent("sha256"))
        try manager.createSymbolicLink(
            atPath: snapshots.appendingPathComponent("model.bin").path,
            withDestinationPath: "../../blobs/sha256"
        )
    }

    func writeMinimalOllamaStore(root: URL) throws {
        let configDigest = "sha256:" + String(repeating: "a", count: 64)
        let layerDigest = "sha256:" + String(repeating: "b", count: 64)
        let blobs = root.appendingPathComponent("blobs")
        try manager.createDirectory(at: blobs, withIntermediateDirectories: true)
        let source = """
        {"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json","config":{"mediaType":"application/vnd.ollama.image.config","digest":"\(configDigest)","size":1},"layers":[{"mediaType":"application/vnd.ollama.image.model","digest":"\(layerDigest)","size":2}]}
        """
        try writeOllamaManifest(root: root, source: source)
        try Data([1]).write(to: blobs.appendingPathComponent("sha256-" + String(repeating: "a", count: 64)))
        try Data([1, 2]).write(to: blobs.appendingPathComponent("sha256-" + String(repeating: "b", count: 64)))
    }

    func writeOllamaManifest(root: URL, source: String) throws {
        let manifest = root
            .appendingPathComponent("manifests")
            .appendingPathComponent("registry")
            .appendingPathComponent("acme")
            .appendingPathComponent("demo")
            .appendingPathComponent("latest")
        try manager.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: manifest, atomically: true, encoding: .utf8)
    }

    func replaceFirstRoot() throws {
        let moved = parent.appendingPathComponent("first-old")
        try manager.moveItem(at: firstRoot, to: moved)
        try manager.createDirectory(at: firstRoot, withIntermediateDirectories: true)
    }

    func firstEntry(
        from adapter: ModelStoreFilesystemAdapter,
        root: ModelStoreRoot = .defaultHuggingFaceCache(),
        matching components: [String]
    ) async throws -> ModelStoreEntryEvidence {
        var cursor: ModelStoreCursor?
        while true {
            switch await adapter.nextEntry(after: cursor, in: root) {
            case .entry(let entry):
                if entry.locator.components == components {
                    return entry
                }
                cursor = .init(position: (cursor?.position ?? 0) + 1)
            case .complete:
                throw ModelStoreFixtureError.entryNotFound
            case .fault:
                throw ModelStoreFixtureError.entryNotFound
            }
        }
    }
}

private enum ModelStoreFixtureError: Error {
    case entryNotFound
}

private struct NeverCancelledModelStoreCancellation: ModelStoreCancellation {
    func isCancellationRequested() async -> Bool { false }
}
