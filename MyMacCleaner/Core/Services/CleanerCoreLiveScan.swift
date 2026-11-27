import CleanerCore
import CleanerCoreFoundation
import Foundation

struct CleanerCoreLiveScan: Sendable {
    /// Every root the full presentation scan covers.
    static let allRootKinds: [GeneralMacRootKind] = [
        .userLibraryCaches,
        .userLibraryLogs,
        .userTemporary,
        .userDownloads,
        .userDesktop,
        .userDocuments
    ]

    func collect() async throws -> AdaptiveScanCollection {
        try await collect(roots: Self.allRootKinds)
    }

    /// Scans only the given roots. Execute-time revalidation uses this to re-observe just the
    /// plan targets' roots, so a large unrelated root cannot consume the scan budget and truncate
    /// a still-present target into a false `skippedStale(.missing)`.
    func collect(roots kinds: [GeneralMacRootKind]) async throws -> AdaptiveScanCollection {
        try await collectCheckingOpenFiles(roots: kinds).collection
    }

    /// Also says whether the open-file listing ran. When it did not, every file in a Trash-eligible
    /// root counted as open, so nothing there was eligible this time.
    func collectCheckingOpenFiles(
        roots kinds: [GeneralMacRootKind]
    ) async throws -> (collection: AdaptiveScanCollection, openFilesChecked: Bool) {
        let catalog = GeneralMacScopeCatalog.current
        let adapter = try GeneralMacFilesystemAdapter(catalog: catalog)
        let activity = await OpenFileActivityReader.snapshot(for: kinds)
        let session = try AdaptiveScanSession(
            fileSystem: adapter,
            clock: AppAdaptiveClock(),
            cancellation: TaskAdaptiveCancel(),
            processActivity: activity
        )
        let collection = await session.collect(request: try catalog.scanRequest(for: kinds))
        return (collection, activity.isListingAvailable)
    }

    func developerInventory() -> [AdaptiveDeveloperInventoryFact] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let adapter = DeveloperInventoryAdapter(
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
            additionalApplicationDirectories: [home.appendingPathComponent("Applications", isDirectory: true)],
            homeDirectory: home,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            directoryAllocatedBytes: { DirectorySize.allocatedBytes(at: $0).map(Int.init) },
            fileAllocatedBytes: { Self.fileAllocatedBytes(of: $0) }
        )
        return adapter.observe().compactMap(\.inventoryFact)
    }

    /// Content-blind allocated bytes of one regular file (a sparse disk image reports what
    /// it really occupies, not its logical size). Symlinks and missing or unreadable items
    /// yield nil; the file is never opened. Internal for tests.
    static func fileAllocatedBytes(of file: URL) -> Int? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? file.resourceValues(forKeys: keys),
              values.isRegularFile == true else {
            return nil
        }
        return values.totalFileAllocatedSize ?? values.fileAllocatedSize
    }

    /// The two model-store roots a live scan inspects: the default Hugging Face
    /// cache and Ollama models directory under the user's home.
    static func defaultModelStoreRoots() -> [DeclaredRootID: URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ModelStoreRoot.huggingFaceDefaultRootID:
                home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true),
            ModelStoreRoot.ollamaDefaultRootID:
                home.appendingPathComponent(".ollama/models", isDirectory: true)
        ]
    }

    /// Read-only inventory of the Hugging Face and Ollama model stores.
    ///
    /// The CleanerCore engine only enumerates the store's directory graph and
    /// reads tiny ref/manifest pointer files — never model weights — and never
    /// mutates anything (`ProjectedModelStoreEntry.operation` is `Never?`).
    /// Roots that are absent or empty contribute nothing. `rootURLs` is
    /// injectable so tests can point it at a synthetic fixture.
    func modelInventory(
        rootURLs: [DeclaredRootID: URL] = CleanerCoreLiveScan.defaultModelStoreRoots()
    ) async -> [ModelStoreProjection] {
        let adapter: ModelStoreFilesystemAdapter
        do {
            adapter = try ModelStoreFilesystemAdapter(rootURLs: rootURLs, fileManager: .default)
        } catch {
            return []
        }
        let cancellation = TaskModelStoreCancel()
        let huggingFace = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .default,
            port: adapter,
            cancellation: cancellation
        )
        let ollama = OllamaStoreParser(limits: .default, port: adapter, cancellation: cancellation)
        let results = [
            await huggingFace.parse(root: .defaultHuggingFaceCache()),
            await ollama.parse(root: .defaultOllamaModels())
        ]
        return results.map(ModelStoreProjection.init(result:)).filter(Self.hasObservedInventory)
    }

    private static func hasObservedInventory(_ projection: ModelStoreProjection) -> Bool {
        !projection.repositories.isEmpty
            || !projection.blobs.isEmpty
            || !projection.incompleteBlobs.isEmpty
    }

    /// Read-only inventory of a directory the user explicitly picked (C2). The
    /// validated selected root comes only from `SelectedModelStoreBridge`, so
    /// scope widens solely through this user-initiated call — never silently.
    /// Returns the projection even when empty, so the picker gives feedback.
    func selectedModelInventory(directory: URL) async -> ModelStoreProjection? {
        let selection = SelectedModelStoreBridge.makeSelection(forUserChosenDirectory: directory)
        let adapter: ModelStoreFilesystemAdapter
        do {
            adapter = try ModelStoreFilesystemAdapter(
                rootURLs: [selection.rootID: selection.directory],
                fileManager: .default
            )
        } catch {
            return nil
        }
        let inventory = SelectedRootInventory(
            limits: .default,
            port: adapter,
            cancellation: TaskModelStoreCancel()
        )
        guard let result = await inventory.parse(selectedRoot: selection.root) else { return nil }
        return ModelStoreProjection(result: result)
    }

    /// Names of the model-store environment variables that are set, surfaced as a
    /// prompt so the user can *choose* to inventory those roots. The values are
    /// never read or displayed and never trigger a silent scan (C2).
    func environmentModelRootPrompts(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        ["HF_HOME", "OLLAMA_MODELS"].filter { environment[$0]?.isEmpty == false }
    }

    /// One scan of every root for display, with the Home and Disk Cleaner cards derived here, off
    /// the main actor. `SharedScanStore` keeps it for every screen; a Trash run never uses it.
    func sharedScan() async throws -> SharedScan {
        let started = Date()
        let scanned = try await collectCheckingOpenFiles(roots: Self.allRootKinds)
        return SharedScan(
            collection: scanned.collection,
            openFilesChecked: scanned.openFilesChecked,
            legacyReport: Self.legacyReport(from: scanned.collection),
            takenAt: started
        )
    }

    /// The engine reports no per-root progress, so callers show an indeterminate indicator; the
    /// report keeps every gap so an unreadable folder never looks empty.
    static func legacyReport(from collected: AdaptiveScanCollection) -> LegacyScanReport {
        let snapshot = snapshots(from: collected)
        return LegacyScanReport(
            results: snapshot.results,
            coverage: LegacyScanCoverage(
                state: collected.scanState,
                droppedFrom: snapshot.dropped,
                droppedFindings: snapshot.droppedCount
            )
        )
    }

    private static func snapshots(
        from collection: AdaptiveScanCollection
    ) -> (results: [ScanResult], dropped: Set<ScanCategory>, droppedCount: Int) {
        var grouped: [ScanCategory: [CleanableItem]] = [:]
        var dropped = Set<ScanCategory>()
        var droppedCount = 0
        for finding in collection.findings {
            let kind: GeneralMacRootKind
            do {
                kind = try GeneralMacScopeCatalog.current.rootKind(for: finding.declaredRootID)
            } catch {
                // A root outside the catalog cannot be named, so mark every folder as partly read.
                dropped.formUnion(ScanCategory.allCases)
                droppedCount += 1
                continue
            }
            let category = ScanCategory(kind)
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
                dropped.insert(category)
                droppedCount += 1
            }
        }
        let results = ScanCategory.allCases.compactMap { category -> ScanResult? in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return ScanResult(category: category, items: items)
        }
        return (results, dropped, droppedCount)
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

struct TaskModelStoreCancel: ModelStoreCancellation {
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
    init(_ kind: GeneralMacRootKind) {
        switch kind {
        case .userLibraryCaches: self = .caches
        case .userLibraryLogs: self = .logs
        case .userTemporary: self = .temporaryFiles
        case .userDownloads: self = .downloads
        case .userDesktop: self = .desktop
        case .userDocuments: self = .documents
        }
    }
}
