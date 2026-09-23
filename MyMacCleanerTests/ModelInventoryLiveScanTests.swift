import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

/// C1: the live model-store scan must be read-only. These tests point the scan
/// at a synthetic Hugging Face cache in a temp directory and prove (a) it never
/// mutates the tree and (b) whatever it surfaces is inventory-only.
@Suite("Model-store live scan is read-only (C1)")
struct ModelInventoryLiveScanTests {
    @Test
    func scanningASyntheticHuggingFaceCacheLeavesItByteIdenticalAndInventoryOnly() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("mmc-modelinv-\(UUID().uuidString)", isDirectory: true)
        try makeHuggingFaceFixture(at: root, using: fm)
        defer { try? fm.removeItem(at: root) }

        let before = try treeSnapshot(of: root, using: fm)

        let projections = await CleanerCoreLiveScan().modelInventory(
            rootURLs: [ModelStoreRoot.huggingFaceDefaultRootID: root]
        )

        // Primary guarantee: the fixture is untouched — nothing added, removed,
        // resized, or relinked.
        let after = try treeSnapshot(of: root, using: fm)
        #expect(before == after)

        // Feature: the store is recognised, and every entry is inventory-only.
        #expect(!projections.isEmpty)
        for projection in projections {
            #expect(projection.entries.allSatisfy { $0.operation == nil })
            #expect(projection.entries.allSatisfy { $0.reclaimability == .protectedNotEligible })
        }
    }

    @Test
    func absentRootContributesNothing() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmc-modelinv-absent-\(UUID().uuidString)", isDirectory: true)
        let projections = await CleanerCoreLiveScan().modelInventory(
            rootURLs: [ModelStoreRoot.huggingFaceDefaultRootID: missing]
        )
        #expect(projections.isEmpty)
    }

    @Test
    func selectedRootScanIsReadOnlyAndInventoryOnly() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("mmc-selscan-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data(repeating: 0x42, count: 16).write(to: root.appendingPathComponent("model.gguf"))

        let before = try treeSnapshot(of: root, using: fm)
        let projection = await CleanerCoreLiveScan().selectedModelInventory(directory: root)
        #expect(try treeSnapshot(of: root, using: fm) == before)

        #expect(projection != nil)
        if let projection {
            #expect(projection.entries.allSatisfy { $0.operation == nil })
            #expect(projection.entries.allSatisfy { $0.reclaimability == .protectedNotEligible })
        }
    }

    @Test
    func environmentPromptsReportOnlySetModelRootVariables() {
        let scan = CleanerCoreLiveScan()
        #expect(scan.environmentModelRootPrompts(environment: [:]).isEmpty)
        #expect(scan.environmentModelRootPrompts(environment: ["HF_HOME": "/x"]) == ["HF_HOME"])
        #expect(scan.environmentModelRootPrompts(environment: ["HF_HOME": ""]).isEmpty)
        let both = scan.environmentModelRootPrompts(
            environment: ["HF_HOME": "/x", "OLLAMA_MODELS": "/y", "PATH": "/bin"]
        )
        #expect(both == ["HF_HOME", "OLLAMA_MODELS"])
    }

    // MARK: - Fixture

    private func makeHuggingFaceFixture(at root: URL, using fm: FileManager) throws {
        let repo = root.appendingPathComponent("models--owner--repo", isDirectory: true)
        let refs = repo.appendingPathComponent("refs", isDirectory: true)
        let blobs = repo.appendingPathComponent("blobs", isDirectory: true)
        let snapshotDir = repo
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("abc123", isDirectory: true)
        for dir in [refs, blobs, snapshotDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("abc123".utf8).write(to: refs.appendingPathComponent("main"))
        let blob = blobs.appendingPathComponent("sha256deadbeef")
        try Data(repeating: 0x41, count: 100).write(to: blob)
        try fm.createSymbolicLink(
            at: snapshotDir.appendingPathComponent("model.bin"),
            withDestinationURL: URL(fileURLWithPath: "../../blobs/sha256deadbeef")
        )
    }

    /// A stable, order-independent description of the tree: one line per item
    /// with its relative path, kind, size, and (for links) destination.
    private func treeSnapshot(of root: URL, using fm: FileManager) throws -> [String] {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return []
        }
        var lines: [String] = []
        let prefix = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            let relative = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
            if values.isSymbolicLink == true {
                let destination = (try? fm.destinationOfSymbolicLink(atPath: url.path)) ?? "?"
                lines.append("link:\(relative)->\(destination)")
            } else if values.isDirectory == true {
                lines.append("dir:\(relative)")
            } else {
                lines.append("file:\(relative):\(values.fileSize ?? -1)")
            }
        }
        return lines.sorted()
    }
}
