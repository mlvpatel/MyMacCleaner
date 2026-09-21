public enum GeneralMacCategory: String, CaseIterable, Equatable, Sendable {
    case cache
    case log
    case crashReport
    case temporary
    case largeFile
    case duplicate
}

public enum GeneralMacAgeEvidence: Equatable, Sendable {
    case observed(modification: FileModificationInstant, observedAt: WallClockInstant)
    case unavailable
}

public enum RebuildImpact: String, Equatable, Sendable {
    case rebuildable
    case reviewRequired
    case unknown
}

public enum EvidenceConfidence: String, Equatable, Sendable {
    case observed
    case partial
    case unavailable
}

public enum ConservativeRisk: String, Equatable, Sendable {
    case low
    case reviewRequired
    case unknown
}

public enum TopologyStopReason: String, CaseIterable, Equatable, Sendable {
    case package
    case symbolicLink
    case alias
    case mount
    case volumeChanged
    case nestedHome
    case protectedRoot
    case unreadable
    case unavailableMetadata
}

public enum GeneralMacEvidenceCompleteness: Equatable, Sendable {
    case complete
    case incomplete(reason: TopologyStopReason)
    case unavailable
}

public struct SpaceEvidenceVector: Equatable, Sendable {
    public let logicalBytes: EvidenceValue<Int64>
    public let allocatedBytes: EvidenceValue<Int64>
    public let sharedBytes: EvidenceValue<Int64>
    public let conservativeReclaimableBytes: EvidenceValue<Int64>

    public init(
        logicalBytes: EvidenceValue<Int64>,
        allocatedBytes: EvidenceValue<Int64>,
        sharedBytes sharedByteEvidence: EvidenceValue<Int64> = .unknown,
        conservativeReclaimableBytes: EvidenceValue<Int64> = .unknown
    ) {
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        sharedBytes = sharedByteEvidence
        self.conservativeReclaimableBytes = conservativeReclaimableBytes
    }

    /// Policy consumes only a positive non-sharing observation. Unknown and
    /// nonzero sharing remain distinct and both fail closed at the policy edge.
    public var hasObservedNoSharedBytes: Bool {
        sharedBytes == .observed(0)
    }
}

public struct GeneralMacFinding: Equatable, Sendable {
    public let finding: Finding
    public let category: GeneralMacCategory
    public let source: GeneralMacRootKind
    public let age: GeneralMacAgeEvidence
    public let space: SpaceEvidenceVector
    public let rebuildImpact: RebuildImpact
    public let confidence: EvidenceConfidence
    public let conservativeRisk: ConservativeRisk
    public let completeness: GeneralMacEvidenceCompleteness

    public init(
        finding: Finding,
        category: GeneralMacCategory,
        source: GeneralMacRootKind,
        age: GeneralMacAgeEvidence,
        space: SpaceEvidenceVector,
        rebuildImpact: RebuildImpact,
        confidence: EvidenceConfidence,
        conservativeRisk: ConservativeRisk,
        completeness: GeneralMacEvidenceCompleteness
    ) {
        self.finding = finding
        self.category = category
        self.source = source
        self.age = age
        self.space = space
        self.rebuildImpact = rebuildImpact
        self.confidence = confidence
        self.conservativeRisk = conservativeRisk
        self.completeness = completeness
    }
}
