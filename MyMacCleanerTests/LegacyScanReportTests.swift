import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

// MARK: - Legacy Scan Coverage Tests

@Suite("Legacy Scan Coverage Tests")
struct LegacyScanCoverageTests {
    private func issue(_ kind: GeneralMacRootKind, _ cause: CoreErrorCause) throws -> ProjectedIssue {
        ProjectedIssue(.init(
            rootID: try GeneralMacScopeCatalog.current.declaredRoot(for: kind).id,
            detectorID: try DetectorID("fixture.detector"),
            cause: cause
        ))
    }

    @Test("A complete scan has no gaps")
    func completeScanHasNoGaps() {
        #expect(LegacyScanCoverage(state: .complete).isComplete)
    }

    @Test("Denied folders and partly read folders are reported separately, in folder order")
    func partialScanSplitsDeniedFromPartial() throws {
        let state = ProjectedScanState.partial(issues: [
            try issue(.userDocuments, .permissionDenied),
            try issue(.userLibraryCaches, .corruptMetadata),
            try issue(.userDesktop, .permissionDenied),
            try issue(.userDesktop, .corruptMetadata)
        ])

        let coverage = LegacyScanCoverage(state: state)

        #expect(coverage.isComplete == false)
        #expect(coverage.deniedFolders == [.desktop, .documents])
        #expect(coverage.partialFolders == [.caches])
    }

    @Test("A scan that could not read anything marks every folder")
    func wholeScanFailuresMarkEveryFolder() {
        #expect(LegacyScanCoverage(state: .permissionDenied).deniedFolders == ScanCategory.allCases)
        #expect(LegacyScanCoverage(state: .corruptMetadata).partialFolders == ScanCategory.allCases)
    }

    @Test("Findings the bridge had to drop make their folder partial and are counted")
    func droppedFindingsMakeTheFolderPartial() {
        let coverage = LegacyScanCoverage(state: .complete, droppedFrom: [.logs], droppedFindings: 3)

        #expect(coverage.partialFolders == [.logs])
        #expect(coverage.deniedFolders.isEmpty)
        #expect(coverage.droppedFindingCount == 3)
        #expect(coverage.isComplete == false)
    }
}

// MARK: - Legacy Scan View Model Tests

@Suite("Legacy Scan View Model Tests")
@MainActor
struct LegacyScanViewModelTests {
    private static let unreadable = LegacyScanCoverage(deniedFolders: [.desktop, .documents], partialFolders: [])

    private static func report(_ coverage: LegacyScanCoverage) async throws -> SharedScanStore {
        let collection = try await ScanFixtures.collection()
        return SharedScanStore(scan: { ScanFixtures.scan(collection, coverage: coverage, takenAt: Date()) })
    }

    /// Never finishes on its own, so only Cancel can end the scan.
    private static func endless() -> SharedScanStore {
        SharedScanStore(scan: {
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        })
    }

    @Test("Home keeps the gaps of an empty scan instead of looking clean")
    func homeKeepsCoverageOfEmptyScan() async throws {
        let viewModel = HomeViewModel(scanStore: try await Self.report(Self.unreadable))

        viewModel.continueWithLimitedScan()
        await viewModel.scanTask?.value

        #expect(viewModel.isScanning == false)
        #expect(viewModel.scanResults.isEmpty)
        #expect(viewModel.lastScanCoverage == Self.unreadable)
    }

    @Test("Home Cancel stops the scan and keeps no result")
    func homeCancelStopsScan() async {
        let viewModel = HomeViewModel(scanStore: Self.endless())

        viewModel.continueWithLimitedScan()
        #expect(viewModel.isScanning)
        let task = viewModel.scanTask
        viewModel.cancelScan()
        await task?.value

        #expect(viewModel.isScanning == false)
        #expect(viewModel.lastScanCoverage == nil)
    }

    @Test("Health says Not scanned yet until a Smart Scan completes, then reports a real level")
    func healthWaitsForAScan() async throws {
        let viewModel = HomeViewModel(scanStore: try await Self.report(.complete))
        #expect(viewModel.healthLevel == .notScanned)

        viewModel.continueWithLimitedScan()
        await viewModel.scanTask?.value

        #expect(viewModel.healthLevel != .notScanned)
    }

    @Test("Disk Cleaner keeps the gaps of an empty scan")
    func diskKeepsCoverageOfEmptyScan() async throws {
        let viewModel = DiskCleanerViewModel(scanStore: try await Self.report(Self.unreadable))

        viewModel.startScan()
        await viewModel.scanTask?.value

        #expect(viewModel.hasScanned)
        #expect(viewModel.scanResults.isEmpty)
        #expect(viewModel.lastScanCoverage == Self.unreadable)
    }

    @Test("Disk Cleaner Cancel discards the scan")
    func diskCancelDiscardsScan() async {
        let viewModel = DiskCleanerViewModel(scanStore: Self.endless())

        viewModel.startScan()
        let task = viewModel.scanTask
        viewModel.cancelScan()
        await task?.value

        #expect(viewModel.isScanning == false)
        #expect(viewModel.hasScanned == false)
        #expect(viewModel.lastScanCoverage == nil)
    }
}

// MARK: - System Health Level Tests

@Suite("System Health Level Tests")
struct SystemHealthLevelTests {
    @Test("Disk or memory use decides the level")
    func thresholds() {
        #expect(SystemHealthLevel.assess(diskUsage: 0.5, memoryUsage: 0.5) == .healthy)
        #expect(SystemHealthLevel.assess(diskUsage: 0.8, memoryUsage: 0.1) == .fair)
        #expect(SystemHealthLevel.assess(diskUsage: 0.1, memoryUsage: 0.85) == .fair)
        #expect(SystemHealthLevel.assess(diskUsage: 0.95, memoryUsage: 0.1) == .needsAttention)
        #expect(SystemHealthLevel.assess(diskUsage: 0.1, memoryUsage: 0.95) == .needsAttention)
    }

    @Test("Every level has its own text and icon, not just a color")
    func levelsHaveTextAndIcon() {
        let levels: [SystemHealthLevel] = [.notScanned, .healthy, .fair, .needsAttention]

        #expect(Set(levels.map(\.label)).count == levels.count)
        #expect(Set(levels.map(\.icon)).count == levels.count)
        #expect(SystemHealthLevel.notScanned.label == "Not scanned yet")
    }
}
