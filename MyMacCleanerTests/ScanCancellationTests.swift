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
        let cancelledGroups = await cancelled.value.groups
        let groups = await DuplicateScanner.shared.scan(at: directory, minSize: 1_024) { _, _ in }.groups

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
        #expect(viewModel.toasts.current == nil)
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

    @Test("A progress update from a cancelled duplicates scan never reaches the next scan")
    @MainActor
    func duplicatesIgnoresProgressFromAnOlderScan() async {
        let scans = StalledScans()
        let viewModel = DuplicatesViewModel(scan: { _, progress in
            await scans.record(progress)
            try? await Task.sleep(for: .seconds(600))
            return DuplicateScanResult(groups: [], isTruncated: false)
        })

        viewModel.startScan()
        _ = await waitUntil { scans.calls == 1 }
        viewModel.cancelScan(announce: false)
        viewModel.startScan()
        _ = await waitUntil { scans.calls == 2 }
        scans.first?(0.9, "old scan")
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.isScanning)
        #expect(viewModel.scanProgress == 0)
        #expect(viewModel.currentScanStatus != "old scan")
        viewModel.cancelScan(announce: false)
    }

    @Test("A progress update from a cancelled orphaned files scan never reaches the next scan")
    @MainActor
    func orphanedIgnoresProgressFromAnOlderScan() async {
        let scans = StalledScans()
        let viewModel = OrphanedFilesViewModel(scan: { progress in
            await scans.record(progress)
            try? await Task.sleep(for: .seconds(600))
            return []
        })

        viewModel.startScan()
        _ = await waitUntil { scans.calls == 1 }
        viewModel.cancelScan()
        viewModel.startScan()
        _ = await waitUntil { scans.calls == 2 }
        scans.first?(0.9, "old scan")
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.isScanning)
        #expect(viewModel.scanProgress == 0)
        #expect(viewModel.currentScanCategory != "old scan")
        viewModel.cancelScan()
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

/// Records each scan's progress callback; the scans themselves wait until cancelled.
@MainActor
private final class StalledScans {
    private(set) var first: (@Sendable @MainActor (Double, String) -> Void)?
    private(set) var calls = 0

    func record(_ progress: @escaping @Sendable @MainActor (Double, String) -> Void) {
        calls += 1
        if first == nil { first = progress }
    }
}

// MARK: - Rescan Keeps Results Tests

/// A rescan that does not finish (Cancel, leaving the page, or an error) keeps the last completed
/// results on screen, so it never reads as "Nothing Found".
@Suite("Rescan Keeps Results Tests")
@MainActor
struct RescanKeepsResultsTests {
    private struct ScanFailed: Error {}

    private static let caches = ScanResult(category: .caches, items: [
        CleanableItem(
            name: "a.cache",
            path: URL(fileURLWithPath: "/tmp/a.cache"),
            size: 100,
            modificationDate: nil,
            category: .caches
        )
    ])

    /// The first scan finds one cache item; every later scan waits until cancelled, or fails.
    private static func store(laterScansFail: Bool = false) async throws -> SharedScanStore {
        let collection = try await ScanFixtures.collection()
        let first = SharedScan(
            collection: collection,
            openFilesChecked: true,
            legacyReport: LegacyScanReport(results: [caches], coverage: .complete),
            takenAt: Date()
        )
        let scans = ScanCounter()
        return SharedScanStore(scan: {
            scans.increment()
            guard scans.count > 1 else { return first }
            if laterScansFail { throw ScanFailed() }
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        })
    }

    @Test("A cancelled Disk Cleaner rescan keeps the last results instead of showing Nothing Found")
    func diskCleanerCancelledRescanKeepsResults() async throws {
        let viewModel = DiskCleanerViewModel(scanStore: try await Self.store())
        viewModel.startScan()
        await viewModel.scanTask?.value

        viewModel.startScan()
        viewModel.cancelScan()

        #expect(viewModel.hasScanned)
        #expect(viewModel.scanResults.map(\.category) == [.caches])
        #expect(viewModel.lastScanCoverage == .complete)
    }

    @Test("A failed Disk Cleaner rescan keeps the last results and reports the error")
    func diskCleanerFailedRescanKeepsResults() async throws {
        let viewModel = DiskCleanerViewModel(scanStore: try await Self.store(laterScansFail: true))
        viewModel.startScan()
        await viewModel.scanTask?.value

        viewModel.startScan()
        await viewModel.scanTask?.value

        #expect(viewModel.isScanning == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.scanResults.map(\.category) == [.caches])
    }

    @Test("Leaving Home during a rescan keeps the last results")
    func homeLeavingRescanKeepsResults() async throws {
        let viewModel = HomeViewModel(scanStore: try await Self.store())
        viewModel.continueWithLimitedScan()
        await viewModel.scanTask?.value

        viewModel.continueWithLimitedScan()
        viewModel.leavePage()

        #expect(viewModel.scanStoppedByLeaving)
        #expect(viewModel.showScanResults)
        #expect(viewModel.scanResults.map(\.category) == [.caches])
        #expect(viewModel.lastScanCoverage == .complete)
    }

    @Test("Leaving Orphaned Files during a rescan keeps the last results")
    func orphansLeavingRescanKeepsResults() async {
        let orphan = OrphanedFile(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.gone.App"),
            name: "com.gone.App",
            suspectedAppName: "Gone App",
            bundleIdPattern: "com.gone.app",
            size: 10,
            modificationDate: nil
        )
        let scans = ScanCounter()
        let viewModel = OrphanedFilesViewModel(scan: { _ in
            scans.increment()
            guard scans.count > 1 else { return [orphan] }
            try? await Task.sleep(for: .seconds(600))
            return []
        })
        viewModel.startScan()
        await viewModel.scanTask?.value

        viewModel.startScan()
        viewModel.leavePage()

        #expect(viewModel.scanStoppedByLeaving)
        #expect(viewModel.hasScanned)
        #expect(viewModel.orphanedFiles.map(\.id) == [orphan.id])
    }

    @Test("Leaving Duplicates during a rescan keeps the last results")
    func duplicatesLeavingRescanKeepsResults() async {
        let group = DuplicateGroup(hash: "a", files: [
            DuplicateFile(url: URL(fileURLWithPath: "/a/photo.jpg"), size: 10, modificationDate: nil),
            DuplicateFile(url: URL(fileURLWithPath: "/b/photo.jpg"), size: 10, modificationDate: nil)
        ])
        let scans = ScanCounter()
        let viewModel = DuplicatesViewModel(scan: { _, _ in
            scans.increment()
            guard scans.count > 1 else { return DuplicateScanResult(groups: [group], isTruncated: false) }
            try? await Task.sleep(for: .seconds(600))
            return .empty
        })
        viewModel.startScan()
        await viewModel.scanTask?.value

        viewModel.startScan()
        viewModel.leavePage()

        #expect(viewModel.scanStoppedByLeaving)
        #expect(viewModel.hasScanned)
        #expect(viewModel.duplicateGroups.map(\.id) == [group.id])
    }
}
