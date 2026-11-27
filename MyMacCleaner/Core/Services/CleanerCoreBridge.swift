import Foundation
import CleanerCore

struct LegacyScanSnapshot {
    let result: ScanResult
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
            result: ScanResult(category: category, items: items)
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
            result: ScanResult(category: category, items: items)
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
            modificationDate: modificationDate(from: finding.modification),
            category: category
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
            category: category
        )
    }

    /// The instant the scan observed; unknown or unavailable evidence stays nil ("Unknown").
    private static func modificationDate(from evidence: EvidenceValue<FileModificationInstant>) -> Date? {
        guard case .observed(let instant) = evidence else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(instant.unixNanoseconds) / 1_000_000_000)
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
