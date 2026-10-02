public struct FreshTargetEvidence: Equatable, Sendable {
    public let stableIdentity: StableFindingIdentity
    public let detectorID: DetectorID
    public let detectorVersion: DetectorVersion
    public let declaredRootID: DeclaredRootID
    public let locatorComponents: [String]
    public let resourceIdentity: FileIdentityEvidence
    public let volume: VolumeID
    public let fileKind: FileKind
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let conservativeReclaimableBytes: Int64
    public let modificationUnixNanoseconds: Int64
    public let semanticOwner: PolicySemanticOwner
    public let symlink: Bool
    public let alias: Bool
    public let package: Bool
    public let mount: Bool
    public let completeness: GeneralMacEvidenceCompleteness

    public init(
        stableIdentity: StableFindingIdentity,
        detectorID: DetectorID,
        detectorVersion: DetectorVersion,
        declaredRootID: DeclaredRootID,
        locatorComponents: [String],
        resourceIdentity: FileIdentityEvidence,
        volume: VolumeID,
        fileKind: FileKind,
        logicalBytes: Int64,
        allocatedBytes: Int64,
        conservativeReclaimableBytes: Int64,
        modificationUnixNanoseconds: Int64,
        semanticOwner: PolicySemanticOwner,
        symlink: Bool,
        alias: Bool,
        package: Bool,
        mount: Bool,
        completeness: GeneralMacEvidenceCompleteness
    ) {
        self.stableIdentity = stableIdentity
        self.detectorID = detectorID
        self.detectorVersion = detectorVersion
        self.declaredRootID = declaredRootID
        self.locatorComponents = locatorComponents
        self.resourceIdentity = resourceIdentity
        self.volume = volume
        self.fileKind = fileKind
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.conservativeReclaimableBytes = conservativeReclaimableBytes
        self.modificationUnixNanoseconds = modificationUnixNanoseconds
        self.semanticOwner = semanticOwner
        self.symlink = symlink
        self.alias = alias
        self.package = package
        self.mount = mount
        self.completeness = completeness
    }

    static func matching(_ target: ReviewPlanTarget) -> FreshTargetEvidence {
        .init(
            stableIdentity: target.stableIdentity,
            detectorID: target.detectorID,
            detectorVersion: target.detectorVersion,
            declaredRootID: target.declaredRootID,
            locatorComponents: target.locatorComponents,
            resourceIdentity: target.resourceIdentity,
            volume: target.volume,
            fileKind: target.fileKind,
            logicalBytes: target.logicalBytes,
            allocatedBytes: target.allocatedBytes,
            conservativeReclaimableBytes: target.conservativeReclaimableBytes,
            modificationUnixNanoseconds: target.modificationUnixNanoseconds,
            semanticOwner: target.semanticOwner,
            symlink: false,
            alias: false,
            package: false,
            mount: false,
            completeness: .complete
        )
    }

    /// Live observer: copies currently observed fields for a displayed target.
    /// Returns nil when the identity is absent or incomplete enough that no
    /// comparison can be formed. Callers must not substitute `matching(_:)`.
    public static func observing(
        target: ReviewPlanTarget,
        in findings: [GeneralMacFinding]
    ) -> FreshTargetEvidence? {
        for finding in findings {
            let identity = StableFindingIdentity(finding: finding.finding)
            guard identity == target.stableIdentity else { continue }
            return observing(finding: finding, semanticOwner: target.semanticOwner)
        }
        return nil
    }

    /// Execute-time observer: only findings the fresh policy pass still makes eligible count, so a
    /// file a process opened after review (or one a newer owner rule narrows) yields no evidence.
    public static func observing(
        target: ReviewPlanTarget,
        eligibleIn evaluations: [PolicyEvaluation]
    ) -> FreshTargetEvidence? {
        observing(target: target, in: evaluations.compactMap(\.candidate).map(\.evidence.finding))
    }

    private static func observing(
        finding: GeneralMacFinding,
        semanticOwner: PolicySemanticOwner
    ) -> FreshTargetEvidence? {
        let raw = finding.finding
        guard case let .observed(identity) = raw.resourceIdentity,
              case let .observed(volume) = raw.volume,
              case let .observed(logicalBytes) = raw.sizes.logicalBytes,
              case let .observed(allocatedBytes) = raw.sizes.allocatedBytes,
              case let .observed(reclaimableBytes) = finding.space.conservativeReclaimableBytes,
              case let .observed(modification) = raw.modification else {
            return nil
        }
        return FreshTargetEvidence(
            stableIdentity: StableFindingIdentity(finding: raw),
            detectorID: raw.detectorID,
            detectorVersion: raw.detectorVersion,
            declaredRootID: raw.declaredRoot.id,
            locatorComponents: raw.locator.components,
            resourceIdentity: identity,
            volume: volume,
            fileKind: raw.fileKind,
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            conservativeReclaimableBytes: reclaimableBytes,
            modificationUnixNanoseconds: modification.unixNanoseconds,
            semanticOwner: semanticOwner,
            symlink: observedOrTrue(raw.boundaries.symlink),
            alias: observedOrTrue(raw.boundaries.alias),
            package: observedOrTrue(raw.boundaries.package),
            mount: observedOrTrue(raw.boundaries.mount),
            completeness: finding.completeness
        )
    }

    private static func observedOrTrue(_ value: EvidenceValue<Bool>) -> Bool {
        switch value {
        case .observed(false):
            return false
        default:
            return true
        }
    }
}

public struct FreshEvidenceRevalidator: Sendable {
    public init() {}

    public func validate(operation: MoveToTrash, fresh: FreshTargetEvidence?) -> TrashStaleReason? {
        guard let fresh else { return .missingFreshEvidence }
        guard fresh.completeness == .complete else { return .incompleteFreshEvidence }
        let frozen = operation.target
        if fresh.stableIdentity != frozen.stableIdentity || fresh.resourceIdentity != frozen.resourceIdentity {
            return .identityChanged
        }
        if fresh.locatorComponents != frozen.locatorComponents {
            return .locatorChanged
        }
        if fresh.declaredRootID != frozen.declaredRootID || fresh.detectorID != frozen.detectorID
            || fresh.detectorVersion != frozen.detectorVersion {
            return .rootChanged
        }
        if fresh.volume != frozen.volume {
            return .volumeChanged
        }
        if fresh.fileKind != frozen.fileKind {
            return .fileKindChanged
        }
        if fresh.logicalBytes != frozen.logicalBytes || fresh.allocatedBytes != frozen.allocatedBytes
            || fresh.conservativeReclaimableBytes != frozen.conservativeReclaimableBytes {
            return .sizeChanged
        }
        if fresh.modificationUnixNanoseconds != frozen.modificationUnixNanoseconds {
            return .modificationChanged
        }
        if fresh.symlink || fresh.alias || fresh.package || fresh.mount {
            return .topologyChanged
        }
        if fresh.semanticOwner != frozen.semanticOwner {
            return .semanticOwnerChanged
        }
        return nil
    }
}
