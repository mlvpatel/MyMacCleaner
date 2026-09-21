public enum LargeFileContentDisposition: String, Equatable, Sendable {
    case personalContent
}

public enum LargeFileInspectionDisposition: String, Equatable, Sendable {
    case revealOnly
}

public enum LargeFileSelectionDisposition: String, Equatable, Sendable {
    case notPreselected
}

public enum LargeFileSizeDisposition: String, Equatable, Sendable {
    case notDisposableBySize
}

public struct LargeFileProtection: Equatable, Sendable {
    public let content: LargeFileContentDisposition
    public let inspection: LargeFileInspectionDisposition
    public let selection: LargeFileSelectionDisposition
    public let sizeDisposition: LargeFileSizeDisposition

    public init() {
        content = .personalContent
        inspection = .revealOnly
        selection = .notPreselected
        sizeDisposition = .notDisposableBySize
    }
}

public struct RevealIntent: Equatable, Sendable {
    public let declaredRootID: DeclaredRootID
    public let locator: RelativeLocator

    public init(declaredRootID: DeclaredRootID, locator: RelativeLocator) throws {
        guard declaredRootID == locator.rootID else {
            throw EvidenceValidationError.mismatchedRootIdentity
        }
        self.declaredRootID = declaredRootID
        self.locator = locator
    }
}

public enum LargeFileTriageRejectionCause: String, Equatable, Sendable {
    case outsidePersonalContentRoots
    case untrustedScopeEvidence
    case incompleteEvidence
    case nonRegularFile
    case inconsistentSpaceEvidence
    case unobservedLogicalSize
    case belowThreshold
}

public struct LargeFileTriageRejection: Error, Equatable, Sendable {
    public let locator: RelativeLocator
    public let cause: LargeFileTriageRejectionCause

    public init(locator: RelativeLocator, cause: LargeFileTriageRejectionCause) {
        self.locator = locator
        self.cause = cause
    }
}

public struct LargeFileTriageEntry: Equatable, Sendable {
    public let revealIntent: RevealIntent
    public let protection: LargeFileProtection
    public let space: SpaceEvidenceVector

    public init(revealIntent: RevealIntent, space: SpaceEvidenceVector) {
        self.revealIntent = revealIntent
        protection = .init()
        self.space = space
    }
}

public struct LargeFileTriageResult: Equatable, Sendable {
    public let entries: [LargeFileTriageEntry]
    public let rejections: [LargeFileTriageRejection]

    public init(entries: [LargeFileTriageEntry], rejections: [LargeFileTriageRejection]) {
        self.entries = entries
        self.rejections = rejections
    }
}

public enum LargeFileTriageError: Error, Equatable, Sendable {
    case invalidThreshold
}

public struct LargeFileTriage: Sendable {
    public let minimumLogicalBytes: Int64

    public init(minimumLogicalBytes: Int64) throws {
        guard minimumLogicalBytes > 0 else {
            throw LargeFileTriageError.invalidThreshold
        }
        self.minimumLogicalBytes = minimumLogicalBytes
    }

    public func evaluate(_ findings: [GeneralMacFinding]) -> LargeFileTriageResult {
        var entries: [LargeFileTriageEntry] = []
        var rejections: [LargeFileTriageRejection] = []

        for finding in findings {
            switch acceptance(for: finding) {
            case let .success(entry):
                entries.append(entry)
            case let .failure(rejection):
                rejections.append(rejection)
            }
        }

        return .init(
            entries: entries.sorted(by: Self.ranksBefore),
            rejections: rejections
        )
    }

    private func acceptance(
        for finding: GeneralMacFinding
    ) -> Result<LargeFileTriageEntry, LargeFileTriageRejection> {
        guard Self.hasTrustedGeneralMacScopeEvidence(finding) else {
            return .failure(.init(
                locator: finding.finding.locator,
                cause: .untrustedScopeEvidence
            ))
        }
        guard Self.isPersonalContentRoot(finding.source) else {
            return .failure(.init(
                locator: finding.finding.locator,
                cause: .outsidePersonalContentRoots
            ))
        }
        guard finding.completeness == .complete else {
            return .failure(.init(locator: finding.finding.locator, cause: .incompleteEvidence))
        }
        guard finding.finding.fileKind == .regularFile else {
            return .failure(.init(locator: finding.finding.locator, cause: .nonRegularFile))
        }
        guard finding.space.isNonnegativeForLargeFileTriage,
              Self.matchesFindingSpace(finding) else {
            return .failure(.init(locator: finding.finding.locator, cause: .inconsistentSpaceEvidence))
        }
        guard case let .observed(logicalBytes) = finding.space.logicalBytes else {
            return .failure(.init(locator: finding.finding.locator, cause: .unobservedLogicalSize))
        }
        guard logicalBytes >= minimumLogicalBytes else {
            return .failure(.init(locator: finding.finding.locator, cause: .belowThreshold))
        }
        do {
            return .success(try .init(
                revealIntent: .init(
                    declaredRootID: finding.finding.declaredRoot.id,
                    locator: finding.finding.locator
                ),
                space: finding.space
            ))
        } catch {
            return .failure(.init(locator: finding.finding.locator, cause: .incompleteEvidence))
        }
    }

    private static func isPersonalContentRoot(_ root: GeneralMacRootKind) -> Bool {
        switch root {
        case .userDownloads, .userDesktop, .userDocuments:
            return true
        case .userLibraryCaches, .userLibraryLogs, .userTemporary:
            return false
        }
    }

    private static func ranksBefore(_ lhs: LargeFileTriageEntry, _ rhs: LargeFileTriageEntry) -> Bool {
        let lhsSize = observedLogicalBytes(of: lhs.space)
        let rhsSize = observedLogicalBytes(of: rhs.space)
        if lhsSize != rhsSize { return lhsSize > rhsSize }
        return locatorKey(lhs.revealIntent.locator) < locatorKey(rhs.revealIntent.locator)
    }

    private static func observedLogicalBytes(of space: SpaceEvidenceVector) -> Int64 {
        guard case let .observed(bytes) = space.logicalBytes else { return Int64.min }
        return bytes
    }

    private static func locatorKey(_ locator: RelativeLocator) -> String {
        "\(locator.components.joined(separator: "/"))\u{0}\(locator.rootID.value)"
    }

    private static func matchesFindingSpace(_ finding: GeneralMacFinding) -> Bool {
        finding.space.logicalBytes == finding.finding.sizes.logicalBytes
            && finding.space.allocatedBytes == finding.finding.sizes.allocatedBytes
    }

    private static func hasTrustedGeneralMacScopeEvidence(_ finding: GeneralMacFinding) -> Bool {
        let catalog = GeneralMacScopeCatalog.current
        let registration: GeneralMacScopeRegistration
        let root: DeclaredRoot
        do {
            registration = try catalog.registration(for: finding.source)
            root = try catalog.declaredRoot(for: finding.source)
        } catch {
            return false
        }
        guard finding.finding.detectorID == catalog.detectorID,
              finding.finding.detectorVersion == catalog.version,
              finding.finding.provenance == .filesystemObservation,
              finding.finding.declaredRoot == root,
              finding.finding.locator.rootID == root.id,
              finding.category == expectedCategory(for: registration, locator: finding.finding.locator),
              hasObservedSafeBoundaries(finding.finding.boundaries) else {
            return false
        }
        return true
    }

    private static func expectedCategory(
        for registration: GeneralMacScopeRegistration,
        locator: RelativeLocator
    ) -> GeneralMacCategory {
        if registration.rootKind == .userLibraryLogs,
           locator.components.first == "DiagnosticReports" {
            return .crashReport
        }
        return registration.category
    }

    private static func hasObservedSafeBoundaries(_ boundaries: BoundaryEvidence) -> Bool {
        [
            boundaries.symlink,
            boundaries.alias,
            boundaries.package,
            boundaries.mount,
            boundaries.protectedRoot,
            boundaries.homeBoundary,
            boundaries.externalVolume,
        ].allSatisfy { evidence in
            evidence == .observed(false)
        }
    }

}

private extension SpaceEvidenceVector {
    var isNonnegativeForLargeFileTriage: Bool {
        [
            logicalBytes,
            allocatedBytes,
            sharedBytes,
            conservativeReclaimableBytes,
        ].allSatisfy { evidence in
            guard case let .observed(bytes) = evidence else { return true }
            return bytes >= 0
        }
    }
}
