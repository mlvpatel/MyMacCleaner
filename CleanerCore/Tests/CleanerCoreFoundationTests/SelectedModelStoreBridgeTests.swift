import Foundation
import Testing
@testable import CleanerCore
@testable import CleanerCoreFoundation

/// C2: the consent bridge is the only public issuer of a validated selected
/// root, and the resulting scan is read-only.
@Suite("Selected model-store bridge")
struct SelectedModelStoreBridgeTests {
    @Test
    func bridgeIssuesAValidatedSelectedRootTheParserAcceptsWithoutMutating() async throws {
        let fm = FileManager()
        let root = fm.temporaryDirectory
            .appendingPathComponent("mmc-selroot-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("demo.gguf").path,
            contents: Data(repeating: 0x42, count: 8)
        )

        let selection = SelectedModelStoreBridge.makeSelection(forUserChosenDirectory: root)

        // The authority carried is an explicit, validated selection.
        guard case .explicitSelection(let token) = selection.root.authority else {
            Issue.record("expected an explicit selection authority")
            return
        }
        #expect(token.isValidated)
        #expect(selection.root.layout == .selectedRootV1)

        let before = try treeSnapshot(of: root, using: fm)

        let adapter = try ModelStoreFilesystemAdapter(
            rootURLs: [selection.rootID: selection.directory],
            fileManager: FileManager()
        )
        let inventory = SelectedRootInventory(
            limits: .default,
            port: adapter,
            cancellation: NeverCancelSelectedRoot()
        )
        let result = await inventory.parse(selectedRoot: selection.root)

        // The validated root is accepted and observed (a nil result would mean
        // the selection was rejected as unauthorised).
        #expect(result != nil)
        #expect(result?.outcome == ScanOutcome.complete)

        // Read-only: the fixture is untouched.
        #expect(try treeSnapshot(of: root, using: fm) == before)
    }

    private func treeSnapshot(of root: URL, using fm: FileManager) throws -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var lines: [String] = []
        let prefix = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            let relative = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
            lines.append(values.isDirectory == true ? "dir:\(relative)" : "file:\(relative):\(values.fileSize ?? -1)")
        }
        return lines.sorted()
    }
}

private struct NeverCancelSelectedRoot: ModelStoreCancellation {
    func isCancellationRequested() async -> Bool { false }
}
