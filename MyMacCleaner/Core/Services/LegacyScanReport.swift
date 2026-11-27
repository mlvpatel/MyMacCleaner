import CleanerCore

/// What a read-only legacy scan found, together with the folders it could not fully read.
struct LegacyScanReport: Sendable {
    let results: [ScanResult]
    let coverage: LegacyScanCoverage
}

/// The folders a scan could not fully read, so an unreadable disk never looks empty or clean.
struct LegacyScanCoverage: Equatable, Sendable {
    /// macOS refused access; allowing access in Permissions can fix these.
    let deniedFolders: [ScanCategory]
    /// Read only in part: entry caps, unreadable metadata, an unsupported layout or dropped findings.
    let partialFolders: [ScanCategory]
    /// Findings the scan made that could not be listed; counted instead of skipped silently.
    let droppedFindingCount: Int

    static let complete = LegacyScanCoverage(deniedFolders: [], partialFolders: [])

    var isComplete: Bool {
        deniedFolders.isEmpty && partialFolders.isEmpty && droppedFindingCount == 0
    }

    init(deniedFolders: [ScanCategory], partialFolders: [ScanCategory], droppedFindingCount: Int = 0) {
        self.deniedFolders = deniedFolders
        self.partialFolders = partialFolders
        self.droppedFindingCount = droppedFindingCount
    }

    /// `droppedFrom` lists folders with findings the bridge could not turn into items, and
    /// `droppedFindings` counts those findings.
    init(
        state: ProjectedScanState,
        droppedFrom: Set<ScanCategory> = [],
        droppedFindings: Int = 0,
        catalog: GeneralMacScopeCatalog = .current
    ) {
        var denied = Set<ScanCategory>()
        var partial = droppedFrom
        switch state {
        case .complete, .continuing, .cancelled:
            break
        case .permissionDenied:
            denied = Set(ScanCategory.allCases)
        case .corruptMetadata, .unsupportedLayout:
            partial = Set(ScanCategory.allCases)
        case .partial(let issues):
            for issue in issues {
                // Issues come from the same catalog that declared the roots, so every ID resolves.
                guard let kind = try? catalog.rootKind(for: issue.rootID) else { continue }
                if issue.cause == .permissionDenied {
                    denied.insert(ScanCategory(kind))
                } else {
                    partial.insert(ScanCategory(kind))
                }
            }
        }
        self.init(
            deniedFolders: ScanCategory.allCases.filter { denied.contains($0) },
            partialFolders: ScanCategory.allCases.filter { partial.contains($0) && !denied.contains($0) },
            droppedFindingCount: droppedFindings
        )
    }
}
