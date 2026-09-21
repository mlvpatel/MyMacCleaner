import Testing
import Foundation
@testable import MyMacCleaner

// MARK: - Scan Cancellation Tests

@Suite("Scan Cancellation Tests")
struct ScanCancellationTests {
    private static let duplicateFileBytes = 4_096

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeDuplicatePair(in directory: URL) throws {
        let payload = Data(repeating: 7, count: Self.duplicateFileBytes)
        try payload.write(to: directory.appendingPathComponent("first.bin"))
        try payload.write(to: directory.appendingPathComponent("second.bin"))
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @Test("Space Lens tree totals sizes and reports truncation at the entry limit")
    func spaceLensTreeTotalsAndTruncates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeDuplicatePair(in: directory)

        let full = try await SpaceLensViewModel.buildFileTree(url: directory, maxEntries: 100) { _, _ in }
        let limited = try await SpaceLensViewModel.buildFileTree(url: directory, maxEntries: 1) { _, _ in }

        #expect(full.isTruncated == false)
        #expect(full.root.children.count == 2)
        #expect(full.root.size > 0)
        #expect(limited.isTruncated)
        #expect(limited.root.children.count == 1)
    }

    @Test("Space Lens tree building stops when its task is cancelled")
    func spaceLensTreeHonoursCancellation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeDuplicatePair(in: directory)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SpaceLensViewModel.buildFileTree(url: directory, maxEntries: 100) { _, _ in }
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Cancelling a Space Lens scan discards its result")
    @MainActor
    func spaceLensCancelDiscardsResult() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeDuplicatePair(in: directory)
        let viewModel = SpaceLensViewModel()

        viewModel.scanDirectory(directory)
        let task = viewModel.scanTask
        viewModel.cancelScan()
        await task?.value

        #expect(viewModel.isScanning == false)
        #expect(viewModel.rootNode == nil)
    }

    @Test("A cancelled duplicate scan returns nothing and does not poison the next scan")
    func duplicateScanCancellationIsPerTask() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeDuplicatePair(in: directory)

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await DuplicateScanner.shared.scan(at: directory, minSize: 1_024) { _, _ in }
        }
        let cancelledGroups = await cancelled.value
        let groups = await DuplicateScanner.shared.scan(at: directory, minSize: 1_024) { _, _ in }

        #expect(cancelledGroups.isEmpty)
        #expect(groups.count == 1)
    }

    @Test("Cancelling a duplicates scan keeps the screen unscanned")
    @MainActor
    func duplicatesCancelKeepsUnscannedState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeDuplicatePair(in: directory)
        let viewModel = DuplicatesViewModel()
        viewModel.scanPath = directory

        viewModel.startScan()
        let task = viewModel.scanTask
        viewModel.cancelScan(announce: false)
        await task?.value

        #expect(viewModel.isScanning == false)
        #expect(viewModel.hasScanned == false)
        #expect(viewModel.duplicateGroups.isEmpty)
        #expect(viewModel.showToast == false)
    }

    @Test("A second duplicates scan request is ignored while one is running")
    @MainActor
    func duplicatesIgnoresOverlappingStart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeDuplicatePair(in: directory)
        let viewModel = DuplicatesViewModel()
        viewModel.scanPath = directory

        viewModel.startScan()
        viewModel.startScan()
        let finished = await waitUntil { !viewModel.isScanning }

        #expect(finished)
        #expect(viewModel.hasScanned)
        #expect(viewModel.duplicateGroups.count == 1)
    }

    @Test("A cancelled orphaned files scan returns nothing")
    func orphanedScanHonoursCancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await OrphanedFilesScanner.shared.scan { _, _ in }
        }

        let orphans = await task.value
        #expect(orphans.isEmpty)
    }

    @Test("Cancelling an orphaned files scan keeps the screen unscanned")
    @MainActor
    func orphanedCancelKeepsUnscannedState() async {
        let viewModel = OrphanedFilesViewModel()

        viewModel.startScan()
        let task = viewModel.scanTask
        viewModel.cancelScan()
        await task?.value

        #expect(viewModel.isScanning == false)
        #expect(viewModel.hasScanned == false)
    }
}
