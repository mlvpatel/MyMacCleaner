import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

// MARK: - Shared Scan Store Tests

@Suite("Shared Scan Store Tests")
@MainActor
struct SharedScanStoreTests {
    @Test("A refresh is kept and reused inside the window, and a new scan runs after it")
    func reusesInsideTheWindow() async throws {
        let collection = try await ScanFixtures.collection()
        let scans = ScanCounter()
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let store = SharedScanStore(
            scan: {
                scans.increment()
                return ScanFixtures.scan(collection, takenAt: clock.now)
            },
            now: { clock.now }
        )

        let first = try await store.refresh()
        clock.advance(by: SharedScanStore.reuseWindow - 1)
        let reused = try await store.current()
        clock.advance(by: 1)
        let renewed = try await store.current()

        #expect(store.latest?.takenAt == renewed.takenAt)
        #expect(reused.takenAt == first.takenAt)
        #expect(renewed.takenAt > first.takenAt)
        #expect(scans.count == 2)
    }

    @Test("A cancelled scan is never kept")
    func cancelledScanIsNotKept() async throws {
        let collection = try await ScanFixtures.collection()
        let store = SharedScanStore(scan: { ScanFixtures.scan(collection, takenAt: Date()) })

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.refresh()
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(store.latest == nil)
    }

    @Test("A scan that started earlier never replaces a newer one")
    func olderScanDoesNotReplaceNewer() async throws {
        let collection = try await ScanFixtures.collection()
        let times = TimeQueue([Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 1_000)])
        let store = SharedScanStore(scan: { ScanFixtures.scan(collection, takenAt: times.next()) })

        _ = try await store.refresh()
        _ = try await store.refresh()

        #expect(store.latest?.takenAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test("One Home Smart Scan fills Disk Cleaner too, without a second scan")
    func oneScanFeedsHomeAndDiskCleaner() async throws {
        let collection = try await ScanFixtures.collection()
        let coverage = LegacyScanCoverage(deniedFolders: [.documents], partialFolders: [])
        let scans = ScanCounter()
        let store = SharedScanStore(scan: {
            scans.increment()
            return ScanFixtures.scan(collection, coverage: coverage, takenAt: Date())
        })
        let home = HomeViewModel(scanStore: store)
        let disk = DiskCleanerViewModel(scanStore: store)

        home.continueWithLimitedScan()
        await home.scanTask?.value

        #expect(scans.count == 1)
        #expect(home.lastScanCoverage == coverage)
        #expect(disk.hasScanned)
        #expect(disk.lastScanCoverage == coverage)
    }
}

// MARK: - Fixtures

/// Real scan collections, built by the CleanerCore scan session over scripted observations, so no
/// real folder is read.
enum ScanFixtures {
    static func collection(_ observations: [FileObservation] = []) async throws -> AdaptiveScanCollection {
        let session = try AdaptiveScanSession(
            fileSystem: ScriptedObservations(observations: observations),
            clock: AppAdaptiveClock(),
            cancellation: TaskAdaptiveCancel()
        )
        let request = try GeneralMacScopeCatalog.current.scanRequest(for: CleanerCoreLiveScan.allRootKinds)
        return await session.collect(request: request)
    }

    static func scan(
        _ collection: AdaptiveScanCollection,
        coverage: LegacyScanCoverage = .complete,
        takenAt: Date
    ) -> SharedScan {
        SharedScan(
            collection: collection,
            openFilesChecked: true,
            legacyReport: LegacyScanReport(results: [], coverage: coverage),
            takenAt: takenAt
        )
    }
}

/// Returns each root's observations in order, then a complete terminal step.
private struct ScriptedObservations: FileSystemPort {
    let observations: [FileObservation]

    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        let inRoot = observations.filter { $0.rootID == root.id }
        let position = Int(cursor?.position ?? 0)
        return position < inRoot.count ? .observation(inRoot[position]) : .terminal(.complete)
    }
}

final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current += interval }
    }
}

private final class TimeQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Date]

    init(_ times: [Date]) {
        self.times = times
    }

    func next() -> Date {
        lock.withLock { times.removeFirst() }
    }
}
