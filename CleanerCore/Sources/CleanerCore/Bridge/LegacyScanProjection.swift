public struct LegacyScanProjection: Equatable, Sendable {
    public let state: ProjectedScanState
    public let findings: [ProjectedFinding]
    public let largeFileTriage: [ProjectedLargeFileTriageEntry]

    public init(
        state: ProjectedScanState,
        findings: [ProjectedFinding],
        largeFileTriage: [ProjectedLargeFileTriageEntry] = []
    ) {
        self.state = state
        self.findings = findings
        self.largeFileTriage = largeFileTriage
    }

    public init(step: ScanStep) {
        switch step {
        case .terminal(let outcome):
            state = ProjectedScanState(outcome)
            findings = []
            largeFileTriage = []
        case .batch(let batch):
            findings = batch.findings.map(ProjectedFinding.init)
            largeFileTriage = []
            if let terminalOutcome = batch.terminalOutcome {
                state = ProjectedScanState(terminalOutcome)
            } else {
                state = .continuing
            }
        }
    }
}

public struct ProjectedLargeFileTriageEntry: Equatable, Sendable {
    public let revealIntent: RevealIntent
    public let protection: LargeFileProtection
    public let space: SpaceEvidenceVector

    public init(_ entry: LargeFileTriageEntry) {
        revealIntent = entry.revealIntent
        protection = entry.protection
        space = entry.space
    }
}

public struct ProjectedFinding: Equatable, Sendable {
    public let detectorID: DetectorID
    public let detectorVersion: DetectorVersion
    public let declaredRootID: DeclaredRootID
    public let locator: RelativeLocator
    public let resourceIdentity: EvidenceValue<FileIdentityEvidence>
    public let sizes: SizeEvidence
    public let modification: EvidenceValue<FileModificationInstant>
    public let fileKind: FileKind
    public let volume: EvidenceValue<VolumeID>
    public let boundaries: BoundaryEvidence
    public let observationInstant: ObservationInstant

    public init(_ finding: Finding) {
        detectorID = finding.detectorID
        detectorVersion = finding.detectorVersion
        declaredRootID = finding.declaredRoot.id
        locator = finding.locator
        resourceIdentity = finding.resourceIdentity
        sizes = finding.sizes
        modification = finding.modification
        fileKind = finding.fileKind
        volume = finding.volume
        boundaries = finding.boundaries
        observationInstant = finding.observationInstant
    }
}

public struct ProjectedIssue: Equatable, Sendable {
    public let rootID: DeclaredRootID
    public let detectorID: DetectorID
    public let cause: CoreErrorCause

    public init(_ issue: ScanIssue) {
        rootID = issue.rootID
        detectorID = issue.detectorID
        cause = issue.cause
    }
}

public enum ProjectedScanState: Equatable, Sendable {
    case complete
    case continuing
    case partial(issues: [ProjectedIssue])
    case permissionDenied
    case cancelled
    case corruptMetadata
    case unsupportedLayout

    public init(_ outcome: ScanOutcome) {
        switch outcome {
        case .complete:
            self = .complete
        case .partial(let issues):
            self = .partial(issues: issues.sorted(by: Self.precedes).map(ProjectedIssue.init))
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

    private static func precedes(_ lhs: ScanIssue, _ rhs: ScanIssue) -> Bool {
        let lhsKey = (lhs.rootID.value, lhs.detectorID.value, lhs.cause.rawValue)
        let rhsKey = (rhs.rootID.value, rhs.detectorID.value, rhs.cause.rawValue)
        return lhsKey.0 != rhsKey.0
            ? lhsKey.0 < rhsKey.0
            : lhsKey.1 != rhsKey.1
                ? lhsKey.1 < rhsKey.1
                : lhsKey.2 < rhsKey.2
    }
}
