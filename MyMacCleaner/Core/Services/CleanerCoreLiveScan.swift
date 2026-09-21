import CleanerCore
import CleanerCoreFoundation
import Foundation

struct CleanerCoreLiveScan: Sendable {
    func collect() async throws -> AdaptiveScanCollection {
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(catalog: catalog)
        let session = try AdaptiveScanSession(
            fileSystem: adapter,
            clock: AppAdaptiveClock(),
            cancellation: TaskAdaptiveCancel()
        )
        let kinds: [GeneralMacRootKind] = [
            .userLibraryCaches,
            .userLibraryLogs,
            .userTemporary,
            .userDownloads,
            .userDesktop,
            .userDocuments
        ]
        return await session.collect(request: try catalog.scanRequest(for: kinds))
    }

    func developerInventory() -> [AdaptiveDeveloperInventoryFact] {
        DeveloperInventoryRegistry.facts(
            presence: Dictionary(
                uniqueKeysWithValues: DeveloperInventoryAdapter(
                    applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
                    fileExists: { FileManager.default.fileExists(atPath: $0.path) }
                ).observe().map { ($0.tool, $0.presence) }
            )
        )
    }

    func scanAllCategories(
        progress: @escaping @MainActor @Sendable (Double, ScanCategory?) -> Void
    ) async throws -> [ScanResult] {
        let collected = try await collect()
        await progress(1, nil)
        return try snapshots(from: collected)
    }

    private func snapshots(from collection: AdaptiveScanCollection) throws -> [ScanResult] {
        var grouped: [ScanCategory: [CleanableItem]] = [:]
        for finding in collection.findings {
            let kind: GeneralMacRootKind
            do {
                kind = try GeneralMacScopeCatalog.current.rootKind(for: finding.declaredRootID)
            } catch {
                continue
            }
            let category = ScanCategory.forGeneralMac(kind)
            let projection = LegacyScanProjection(
                state: collection.scanState,
                findings: [finding]
            )
            do {
                let snapshot = try CleanerCoreBridge.makeSnapshot(
                    from: projection,
                    declaredRootID: finding.declaredRootID,
                    declaredRootURL: AppAdaptiveRoots.url(for: kind),
                    category: category
                )
                grouped[category, default: []].append(contentsOf: snapshot.result.items)
            } catch {
                continue
            }
        }
        return ScanCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return ScanResult(category: category, items: items, isSelected: false)
        }
    }
}

struct AppAdaptiveClock: AdaptiveClocking {
    func now() async -> ClockReading {
        let wall = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        return ClockReading(
            observationInstant: ObservationInstant(monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds),
            wallClockInstant: WallClockInstant(unixNanoseconds: wall)
        )
    }
}

struct TaskAdaptiveCancel: AdaptiveCancelling {
    func isCancellationRequested() async -> Bool {
        Task.isCancelled
    }
}

enum AppAdaptiveRoots {
    static func url(for kind: GeneralMacRootKind) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch kind {
        case .userLibraryCaches:
            return home.appendingPathComponent("Library/Caches", isDirectory: true)
        case .userLibraryLogs:
            return home.appendingPathComponent("Library/Logs", isDirectory: true)
        case .userTemporary:
            return FileManager.default.temporaryDirectory
        case .userDownloads:
            return home.appendingPathComponent("Downloads", isDirectory: true)
        case .userDesktop:
            return home.appendingPathComponent("Desktop", isDirectory: true)
        case .userDocuments:
            return home.appendingPathComponent("Documents", isDirectory: true)
        }
    }
}

extension ScanCategory {
    static func forGeneralMac(_ kind: GeneralMacRootKind) -> ScanCategory {
        switch kind {
        case .userLibraryCaches:
            return .userCache
        case .userLibraryLogs:
            return .applicationLogs
        case .userTemporary:
            return .systemCache
        case .userDownloads, .userDesktop, .userDocuments:
            return .downloads
        }
    }
}
