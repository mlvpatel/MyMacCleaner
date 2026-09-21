import Foundation
import CleanerCore
import SafetyContract

struct LegacyScanSnapshot {
    let result: ScanResult
    let state: LegacyBridgeState
}

struct LegacyBridgeIssue: Equatable {
    let rootID: String
    let detectorID: String
    let cause: CoreErrorCause

    init(_ issue: ProjectedIssue) {
        rootID = issue.rootID.value
        detectorID = issue.detectorID.value
        cause = issue.cause
    }
}

enum LegacyBridgeState: Equatable {
    case complete
    case continuing
    case partial(issues: [LegacyBridgeIssue])
    case permissionDenied
    case cancelled
    case corruptMetadata
    case unsupportedLayout
}

enum CleanerCoreBridgeError: Error, Equatable {
    case invalidRootURL
    case rootMismatch
    case unsafeLocator
    case symlinkBoundary
    case metadataUnavailable
    case containmentEscape
    case unavailableSizeEvidence
    case invalidLargeFileProtection
}

enum CleanerCoreBridge {
    static func makeSnapshot(
        from projection: LegacyScanProjection,
        declaredRootID: DeclaredRootID,
        declaredRootURL: URL,
        category: ScanCategory
    ) throws -> LegacyScanSnapshot {
        let items = try projection.findings.map { finding in
            try makeItem(
                from: finding,
                declaredRootID: declaredRootID,
                declaredRootURL: declaredRootURL,
                category: category
            )
        }

        return LegacyScanSnapshot(
            result: ScanResult(category: category, items: items, isSelected: false),
            state: LegacyBridgeState(projection.state)
        )
    }

    static func makeLargeFileSnapshot(
        from projection: LegacyScanProjection,
        declaredRootID: DeclaredRootID,
        declaredRootURL: URL,
        category: ScanCategory
    ) throws -> LegacyScanSnapshot {
        let items = try projection.largeFileTriage.map { entry in
            try makeLargeFileItem(
                from: entry,
                declaredRootID: declaredRootID,
                declaredRootURL: declaredRootURL,
                category: category
            )
        }

        return LegacyScanSnapshot(
            result: ScanResult(category: category, items: items, isSelected: false),
            state: LegacyBridgeState(projection.state)
        )
    }

    private static func makeItem(
        from finding: ProjectedFinding,
        declaredRootID: DeclaredRootID,
        declaredRootURL: URL,
        category: ScanCategory
    ) throws -> CleanableItem {
        guard finding.declaredRootID == declaredRootID,
              finding.locator.rootID == declaredRootID else {
            throw CleanerCoreBridgeError.rootMismatch
        }

        let itemURL = try resolve(
            locator: finding.locator,
            declaredRootURL: declaredRootURL
        )

        guard let name = finding.locator.components.last else {
            throw CleanerCoreBridgeError.unsafeLocator
        }

        return CleanableItem(
            name: name,
            path: itemURL,
            size: try displaySize(from: finding.sizes),
            modificationDate: nil,
            category: category,
            isSelected: false
        )
    }

    private static func makeLargeFileItem(
        from entry: ProjectedLargeFileTriageEntry,
        declaredRootID: DeclaredRootID,
        declaredRootURL: URL,
        category: ScanCategory
    ) throws -> CleanableItem {
        guard entry.protection.content == .personalContent,
              entry.protection.inspection == .revealOnly,
              entry.protection.selection == .notPreselected,
              entry.protection.sizeDisposition == .notDisposableBySize,
              entry.revealIntent.declaredRootID == declaredRootID,
              entry.revealIntent.locator.rootID == declaredRootID else {
            throw CleanerCoreBridgeError.invalidLargeFileProtection
        }

        let itemURL = try resolve(
            locator: entry.revealIntent.locator,
            declaredRootURL: declaredRootURL
        )
        guard let name = entry.revealIntent.locator.components.last else {
            throw CleanerCoreBridgeError.unsafeLocator
        }
        return CleanableItem(
            name: name,
            path: itemURL,
            size: try displaySize(from: entry.space),
            modificationDate: nil,
            category: category,
            isSelected: false
        )
    }

    private static func resolve(locator: RelativeLocator, declaredRootURL: URL) throws -> URL {
        guard declaredRootURL.isFileURL, !declaredRootURL.path.isEmpty else {
            throw CleanerCoreBridgeError.invalidRootURL
        }
        let rootMetadata = try metadata(for: declaredRootURL)
        // Resource values do not follow a symlinked root, so check the link before the directory flag.
        guard rootMetadata.isSymbolicLink != true else {
            throw CleanerCoreBridgeError.symlinkBoundary
        }
        guard rootMetadata.isDirectory == true else {
            throw CleanerCoreBridgeError.invalidRootURL
        }

        let unsafeComponents = locator.components.contains { component in
            component.isEmpty || component == "." || component == ".." || component.contains("/")
        }
        guard !unsafeComponents else { throw CleanerCoreBridgeError.unsafeLocator }

        let root = declaredRootURL.standardizedFileURL.resolvingSymlinksInPath()
        var resolved = root
        for component in locator.components {
            let candidate = resolved.appendingPathComponent(component, isDirectory: false)
            let candidateMetadata = try metadata(for: candidate)
            guard candidateMetadata.isSymbolicLink != true else {
                throw CleanerCoreBridgeError.symlinkBoundary
            }
            let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedCandidate.pathComponents.starts(with: root.pathComponents) else {
                throw CleanerCoreBridgeError.containmentEscape
            }
            resolved = resolvedCandidate
        }

        guard resolved.pathComponents.count > root.pathComponents.count,
              resolved.pathComponents.starts(with: root.pathComponents) else {
            throw CleanerCoreBridgeError.containmentEscape
        }

        return resolved
    }

    private static func metadata(for url: URL) throws -> URLResourceValues {
        do {
            return try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        } catch {
            throw CleanerCoreBridgeError.metadataUnavailable
        }
    }

    private static func displaySize(from sizes: SizeEvidence) throws -> Int64 {
        if case let .observed(allocatedBytes) = sizes.allocatedBytes {
            return allocatedBytes
        }
        if case let .observed(logicalBytes) = sizes.logicalBytes {
            return logicalBytes
        }
        throw CleanerCoreBridgeError.unavailableSizeEvidence
    }

    private static func displaySize(from space: SpaceEvidenceVector) throws -> Int64 {
        if case let .observed(allocatedBytes) = space.allocatedBytes {
            return allocatedBytes
        }
        if case let .observed(logicalBytes) = space.logicalBytes {
            return logicalBytes
        }
        throw CleanerCoreBridgeError.unavailableSizeEvidence
    }
}

enum BridgeReceiptFailure: Error, Equatable {
    case historyBusy
    case reviewRequired
    case unknownReceipt
    case refused
    case invalidIdentifier
}

struct BridgeReceiptRow: Equatable {
    let id: String
    let createdAtNanoseconds: Int64
    let statusMarker: String
    let schemaMarker: String
    let itemCount: Int
    let estimateMarker: String
    let observedReclaimMarker: String
    let recoveryMarker: String
    let guidanceMarker: String
}

enum BridgeRevealState: Equatable {
    case revealRequested
    case unavailable
}

extension CleanerCoreBridge {
    struct ReceiptSession {
        private let listHistory: @Sendable () async -> Result<[RedactedReceiptSummary], ReceiptPersistenceError>
        private let deleteHistory: @Sendable ([ReceiptID]) async -> Result<Void, ReceiptPersistenceError>
        private let revealItem: @Sendable (ReceiptID, ReceiptItemID) async -> ReceiptRevealOutcome

        init(
            listHistory: @escaping @Sendable () async -> Result<[RedactedReceiptSummary], ReceiptPersistenceError>,
            deleteHistory: @escaping @Sendable ([ReceiptID]) async -> Result<Void, ReceiptPersistenceError>,
            revealItem: @escaping @Sendable (ReceiptID, ReceiptItemID) async -> ReceiptRevealOutcome
        ) {
            self.listHistory = listHistory
            self.deleteHistory = deleteHistory
            self.revealItem = revealItem
        }

        func list() async -> Result<[BridgeReceiptRow], BridgeReceiptFailure> {
            switch await listHistory() {
            case let .failure(error):
                return .failure(Self.map(error))
            case let .success(rows):
                SafetyDiagnosticLogger.emit(
                    RedactingDiagnostic.record(event: .fileScannerCategorySkipped, sensitiveClasses: [.receipt])
                )
                return .success(rows.map(Self.row(from:)))
            }
        }

        func delete(receiptID: String) async -> Result<Void, BridgeReceiptFailure> {
            let id: ReceiptID
            do {
                id = try ReceiptID(receiptID)
            } catch {
                return .failure(.invalidIdentifier)
            }
            switch await deleteHistory([id]) {
            case let .failure(error):
                return .failure(Self.map(error))
            case .success:
                SafetyDiagnosticLogger.emit(
                    RedactingDiagnostic.record(event: .fileScannerCategorySkipped, sensitiveClasses: [.receipt])
                )
                return .success(())
            }
        }

        func reveal(receiptID: String, itemID: String) async -> BridgeRevealState {
            let receipt: ReceiptID
            let item: ReceiptItemID
            do {
                receipt = try ReceiptID(receiptID)
                item = try ReceiptItemID(itemID)
            } catch {
                return .unavailable
            }
            switch await revealItem(receipt, item) {
            case .revealRequested:
                SafetyDiagnosticLogger.emit(
                    RedactingDiagnostic.record(
                        event: .fileScannerPathSkipped,
                        sensitiveClasses: [.receipt, .path]
                    )
                )
                return .revealRequested
            case .unavailable:
                return .unavailable
            }
        }

        private static func row(from summary: RedactedReceiptSummary) -> BridgeReceiptRow {
            BridgeReceiptRow(
                id: summary.id.value,
                createdAtNanoseconds: summary.createdAt.unixNanoseconds,
                statusMarker: summary.statusMarker,
                schemaMarker: summary.schemaMarker,
                itemCount: summary.itemCount,
                estimateMarker: summary.estimateMarker,
                observedReclaimMarker: summary.observedReclaimMarker,
                recoveryMarker: summary.recoveryMarker,
                guidanceMarker: summary.guidanceMarker
            )
        }

        private static func map(_ error: ReceiptPersistenceError) -> BridgeReceiptFailure {
            switch error {
            case .historyBusy:
                return .historyBusy
            case .reviewRequired:
                return .reviewRequired
            case .unknownReceipt:
                return .unknownReceipt
            case .invalidIdentifier:
                return .invalidIdentifier
            default:
                return .refused
            }
        }
    }
}

private extension LegacyBridgeState {
    init(_ state: ProjectedScanState) {
        switch state {
        case .complete:
            self = .complete
        case .continuing:
            self = .continuing
        case .partial(let issues):
            self = .partial(issues: issues.map(LegacyBridgeIssue.init))
        case .permissionDenied:
            self = .permissionDenied
        case .cancelled:
            self = .cancelled
        case .corruptMetadata:
            self = .corruptMetadata
        case .unsupportedLayout:
            self = .unsupportedLayout
        }
    }
}
