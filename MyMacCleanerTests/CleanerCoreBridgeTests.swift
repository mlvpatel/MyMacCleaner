import Foundation
import Testing
import CleanerCore
@testable import MyMacCleaner

@Suite("CleanerCore Bridge Tests")
struct CleanerCoreBridgeTests {
    @Test("Bridge maps projection findings into non-selected read-only legacy snapshot")
    func bridgeMapsProjectionFindingsIntoNonSelectedReadOnlySnapshot() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let finding = try Self.projectedFinding(rootID: rootID)
        let issue = ProjectedIssue(.init(
            rootID: rootID,
            detectorID: finding.detectorID,
            cause: .permissionDenied
        ))
        let projection = LegacyScanProjection(
            state: .partial(issues: [issue]),
            findings: [finding]
        )

        try Self.withTemporaryBridgeRoot { rootURL in
            try Self.createFile(rootURL.appendingPathComponent("models/llama.gguf"))
            let snapshot = try CleanerCoreBridge.makeSnapshot(
                from: projection,
                declaredRootID: rootID,
                declaredRootURL: rootURL,
                category: .xcodeData
            )

            #expect(snapshot.state == .partial(issues: [.init(issue)]))
            #expect(snapshot.result.items.count == 1)
            #expect(snapshot.result.isSelected == false)
            #expect(snapshot.result.items[0].isSelected == false)
            #expect(snapshot.result.items[0].name == "llama.gguf")
            #expect(snapshot.result.items[0].path.path == rootURL.appendingPathComponent("models/llama.gguf").path)
            #expect(snapshot.result.items[0].size == 2048)
            #expect(snapshot.result.items[0].modificationDate == nil)
            #expect(snapshot.result.items[0].category == .xcodeData)
        }
    }

    @Test("Bridge rejects root mismatch and unsafe locators")
    func bridgeRejectsRootMismatchAndUnsafeLocators() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let otherRootID = try DeclaredRootID("other-root")
        let finding = try Self.projectedFinding(rootID: otherRootID)
        let projection = LegacyScanProjection(state: .complete, findings: [finding])

        #expect(throws: CleanerCoreBridgeError.rootMismatch) {
            try CleanerCoreBridge.makeSnapshot(
                from: projection,
                declaredRootID: rootID,
                declaredRootURL: FileManager.default.temporaryDirectory,
                category: .userCache
            )
        }
    }

    @Test("Bridge rejects non-file roots and unavailable size evidence")
    func bridgeRejectsNonFileRootsAndUnavailableSizeEvidence() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let finding = try Self.projectedFinding(
            rootID: rootID,
            sizes: try .init(logicalBytes: .unavailable, allocatedBytes: .unknown)
        )
        let projection = LegacyScanProjection(state: .complete, findings: [finding])

        #expect(throws: CleanerCoreBridgeError.invalidRootURL) {
            try CleanerCoreBridge.makeSnapshot(
                from: projection,
                declaredRootID: rootID,
                declaredRootURL: URL(string: "https://example.invalid/root")!,
                category: .userCache
            )
        }

        try Self.withTemporaryBridgeRoot { rootURL in
            try Self.createFile(rootURL.appendingPathComponent("models/llama.gguf"))
            #expect(throws: CleanerCoreBridgeError.unavailableSizeEvidence) {
                try CleanerCoreBridge.makeSnapshot(
                    from: projection,
                    declaredRootID: rootID,
                    declaredRootURL: rootURL,
                    category: .userCache
                )
            }
        }
    }

    @Test("Bridge rejects unavailable file metadata")
    func bridgeRejectsUnavailableFileMetadata() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let projection = LegacyScanProjection(
            state: .complete,
            findings: [
                try Self.projectedFinding(
                    rootID: rootID,
                    components: ["missing.bin"]
                )
            ]
        )

        try Self.withTemporaryBridgeRoot { rootURL in
            #expect(throws: CleanerCoreBridgeError.metadataUnavailable) {
                try CleanerCoreBridge.makeSnapshot(
                    from: projection,
                    declaredRootID: rootID,
                    declaredRootURL: rootURL.appendingPathComponent("missing-root", isDirectory: true),
                    category: .userCache
                )
            }
            #expect(throws: CleanerCoreBridgeError.metadataUnavailable) {
                try CleanerCoreBridge.makeSnapshot(
                    from: projection,
                    declaredRootID: rootID,
                    declaredRootURL: rootURL,
                    category: .userCache
                )
            }
        }
    }

    @Test("Bridge rejects symlink root and symlink child escapes")
    func bridgeRejectsSymlinkRootAndSymlinkChildEscapes() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymaccleaner-bridge-\(UUID().uuidString)", isDirectory: true)
        let realRoot = temporaryRoot.appendingPathComponent("real-root", isDirectory: true)
        let outsideRoot = temporaryRoot.appendingPathComponent("outside-root", isDirectory: true)
        let symlinkRoot = temporaryRoot.appendingPathComponent("symlink-root", isDirectory: true)
        let childSymlink = realRoot.appendingPathComponent("linked-out", isDirectory: true)

        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: symlinkRoot,
            withDestinationURL: realRoot
        )
        try FileManager.default.createSymbolicLink(
            at: childSymlink,
            withDestinationURL: outsideRoot
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let projectionForSymlinkRoot = LegacyScanProjection(
            state: .complete,
            findings: [try Self.projectedFinding(rootID: rootID)]
        )
        let projectionForChildEscape = LegacyScanProjection(
            state: .complete,
            findings: [
                try Self.projectedFinding(
                    rootID: rootID,
                    components: ["linked-out", "escape.bin"]
                )
            ]
        )

        #expect(throws: CleanerCoreBridgeError.symlinkBoundary) {
            try CleanerCoreBridge.makeSnapshot(
                from: projectionForSymlinkRoot,
                declaredRootID: rootID,
                declaredRootURL: symlinkRoot,
                category: .userCache
            )
        }
        #expect(throws: CleanerCoreBridgeError.symlinkBoundary) {
            try CleanerCoreBridge.makeSnapshot(
                from: projectionForChildEscape,
                declaredRootID: rootID,
                declaredRootURL: realRoot,
                category: .userCache
            )
        }
    }

    @Test("Bridge rejects final leaf symlink inside declared root")
    func bridgeRejectsFinalLeafSymlinkInsideDeclaredRoot() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymaccleaner-bridge-leaf-\(UUID().uuidString)", isDirectory: true)
        let realRoot = temporaryRoot.appendingPathComponent("real-root", isDirectory: true)
        let realFile = realRoot.appendingPathComponent("real.bin")
        let leafSymlink = realRoot.appendingPathComponent("leaf-link.bin")

        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: realFile.path, contents: Data("safe".utf8))
        try FileManager.default.createSymbolicLink(
            at: leafSymlink,
            withDestinationURL: realFile
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let projection = LegacyScanProjection(
            state: .complete,
            findings: [
                try Self.projectedFinding(
                    rootID: rootID,
                    components: ["leaf-link.bin"]
                )
            ]
        )

        #expect(throws: CleanerCoreBridgeError.symlinkBoundary) {
            try CleanerCoreBridge.makeSnapshot(
                from: projection,
                declaredRootID: rootID,
                declaredRootURL: realRoot,
                category: .userCache
            )
        }
    }

    @Test("Bridge maps validated large-file reveal entries without selecting them")
    func bridgeMapsValidatedLargeFileRevealEntriesWithoutSelectingThem() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let locator = try RelativeLocator(rootID: rootID, components: ["large.bin"])
        let triageEntry = LargeFileTriageEntry(
            revealIntent: try .init(declaredRootID: rootID, locator: locator),
            space: .init(
                logicalBytes: .observed(10_000),
                allocatedBytes: .observed(4_096),
                sharedBytes: .unknown,
                conservativeReclaimableBytes: .unknown
            )
        )
        let projection = LegacyScanProjection(
            state: .complete,
            findings: [],
            largeFileTriage: [.init(triageEntry)]
        )

        try Self.withTemporaryBridgeRoot { rootURL in
            try Self.createFile(rootURL.appendingPathComponent("large.bin"))
            let snapshot = try CleanerCoreBridge.makeLargeFileSnapshot(
                from: projection,
                declaredRootID: rootID,
                declaredRootURL: rootURL,
                category: .downloads
            )

            #expect(snapshot.state == .complete)
            #expect(snapshot.result.isSelected == false)
            #expect(snapshot.result.items.count == 1)
            #expect(snapshot.result.items[0].isSelected == false)
            #expect(snapshot.result.items[0].path == rootURL.appendingPathComponent("large.bin"))
        }
    }

    @Test("Large-file bridge rejects a different declared root")
    func largeFileBridgeRejectsDifferentDeclaredRoot() throws {
        let rootID = try DeclaredRootID("fixture-root")
        let otherRootID = try DeclaredRootID("other-root")
        let entry = LargeFileTriageEntry(
            revealIntent: try .init(
                declaredRootID: rootID,
                locator: .init(rootID: rootID, components: ["large.bin"])
            ),
            space: .init(logicalBytes: .observed(10_000), allocatedBytes: .observed(4_096))
        )
        let projection = LegacyScanProjection(
            state: .complete,
            findings: [],
            largeFileTriage: [.init(entry)]
        )

        try Self.withTemporaryBridgeRoot { rootURL in
            #expect(throws: CleanerCoreBridgeError.invalidLargeFileProtection) {
                try CleanerCoreBridge.makeLargeFileSnapshot(
                    from: projection,
                    declaredRootID: otherRootID,
                    declaredRootURL: rootURL,
                    category: .downloads
                )
            }
        }
    }

    private static func projectedFinding(
        rootID: DeclaredRootID,
        components: [String] = ["models", "llama.gguf"],
        sizes: SizeEvidence? = nil
    ) throws -> ProjectedFinding {
        let detectorID = try DetectorID("fixture.detector")
        let detectorVersion = try DetectorVersion("1.0.0")
        let observation = try FileObservation(
            rootID: rootID,
            locator: .init(rootID: rootID, components: components),
            resourceIdentity: .observed(.init(device: 3, node: 4)),
            sizes: try sizes ?? .init(
                logicalBytes: .observed(1024),
                allocatedBytes: .observed(2048)
            ),
            modification: .observed(.init(unixNanoseconds: 42)),
            fileKind: .regularFile,
            volume: .unavailable,
            boundaries: .init(symlink: .observed(false))
        )
        let finding = try Finding(
            detectorID: detectorID,
            detectorVersion: detectorVersion,
            provenance: .filesystemObservation,
            observation: observation,
            declaredRoot: .init(id: rootID),
            observationInstant: .init(monotonicNanoseconds: 43)
        )

        return ProjectedFinding(finding)
    }

    private static func withTemporaryBridgeRoot(
        _ body: (URL) throws -> Void
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymaccleaner-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try body(rootURL)
    }

    private static func createFile(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: url.path, contents: Data("fixture".utf8)) else {
            throw CleanerCoreBridgeError.metadataUnavailable
        }
    }
}
