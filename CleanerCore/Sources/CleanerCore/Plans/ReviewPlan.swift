public enum ReviewPlanBuildError: Error, Equatable, Sendable {
    case emptyIdentifier
    case emptySelection
    case duplicateStableTargetID
    case invalidExpiry
    case digestFailed
}

public struct ReviewPlanLaunchSession: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw ReviewPlanBuildError.emptyIdentifier }
        self.value = value
    }
}

public struct ReviewPlanVersionContext: Equatable, Sendable {
    public let appPlanVersion: String
    public let policyVersion: String
    public let detectorCatalogVersion: String
    public let encodingVersion: UInt16

    public init(
        appPlanVersion: String,
        policyVersion: String,
        detectorCatalogVersion: String,
        encodingVersion: UInt16
    ) throws {
        guard !appPlanVersion.isEmpty,
              !policyVersion.isEmpty,
              !detectorCatalogVersion.isEmpty,
              encodingVersion > 0 else {
            throw ReviewPlanBuildError.emptyIdentifier
        }
        self.appPlanVersion = appPlanVersion
        self.policyVersion = policyVersion
        self.detectorCatalogVersion = detectorCatalogVersion
        self.encodingVersion = encodingVersion
    }
}

public struct ReviewPlanTarget: Equatable, Sendable {
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
    public let observationMonotonicNanoseconds: UInt64
    public let semanticOwner: PolicySemanticOwner
    public let rule: PolicyRuleReference
    public let rationale: PolicyRationale
    public let recoveryPath: PolicyRecoveryPath
    public let confidence: EvidenceConfidence
    public let rankFactors: CandidateRankFactors

    init(candidate: EligibleCandidate) throws {
        let finding = candidate.evidence.finding
        let raw = finding.finding
        guard case let .observed(identity) = raw.resourceIdentity,
              case let .observed(volume) = raw.volume,
              case let .observed(logicalBytes) = raw.sizes.logicalBytes,
              case let .observed(allocatedBytes) = raw.sizes.allocatedBytes,
              case let .observed(reclaimableBytes) = finding.space.conservativeReclaimableBytes,
              case let .observed(modification) = raw.modification,
              finding.completeness == .complete else {
            throw ReviewPlanBuildError.emptySelection
        }
        stableIdentity = candidate.stableIdentity
        detectorID = raw.detectorID
        detectorVersion = raw.detectorVersion
        declaredRootID = raw.declaredRoot.id
        locatorComponents = raw.locator.components
        resourceIdentity = identity
        self.volume = volume
        fileKind = raw.fileKind
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        conservativeReclaimableBytes = reclaimableBytes
        modificationUnixNanoseconds = modification.unixNanoseconds
        observationMonotonicNanoseconds = raw.observationInstant.monotonicNanoseconds
        semanticOwner = candidate.semanticOwner
        rule = candidate.rule
        rationale = candidate.rationale
        recoveryPath = .rebuildable
        confidence = finding.confidence
        rankFactors = candidate.rankFactors
    }
}

public struct ReviewPlanDraft: Equatable, Sendable {
    public static let lifetimeNanoseconds: Int64 = 900_000_000_000

    public let targets: [ReviewPlanTarget]
    public let versionContext: ReviewPlanVersionContext
    public let launchSession: ReviewPlanLaunchSession
    public let createdAt: WallClockInstant
    public let expiresAt: WallClockInstant

    public init(
        selectedCandidates: [EligibleCandidate],
        versionContext: ReviewPlanVersionContext,
        launchSession: ReviewPlanLaunchSession,
        createdAt: WallClockInstant
    ) throws {
        guard !selectedCandidates.isEmpty else { throw ReviewPlanBuildError.emptySelection }
        let targets = try selectedCandidates.map(ReviewPlanTarget.init)
            .sorted {
                $0.stableIdentity.utf8Bytes.lexicographicallyPrecedes($1.stableIdentity.utf8Bytes)
            }
        let identities = targets.map(\.stableIdentity.utf8Bytes)
        guard Set(identities).count == identities.count else {
            throw ReviewPlanBuildError.duplicateStableTargetID
        }
        let expiry = createdAt.unixNanoseconds.addingReportingOverflow(Self.lifetimeNanoseconds)
        guard !expiry.overflow else { throw ReviewPlanBuildError.invalidExpiry }

        self.targets = targets
        self.versionContext = versionContext
        self.launchSession = launchSession
        self.createdAt = createdAt
        expiresAt = .init(unixNanoseconds: expiry.partialValue)
    }
}

public struct ReviewPlan: Equatable, Sendable {
    public let targets: [ReviewPlanTarget]
    public let versionContext: ReviewPlanVersionContext
    public let launchSession: ReviewPlanLaunchSession
    public let createdAt: WallClockInstant
    public let expiresAt: WallClockInstant
    public let canonicalBytes: [UInt8]
    public let digest: PlanDigest

    public static func build(draft: ReviewPlanDraft, digesting: PlanDigesting) throws -> Self {
        let canonicalBytes = try CanonicalPlanEncoder().encode(draft)
        let digest: PlanDigest
        do {
            digest = try digesting.digest(canonicalBytes: canonicalBytes)
        } catch {
            throw ReviewPlanBuildError.digestFailed
        }
        return .init(draft: draft, canonicalBytes: canonicalBytes, digest: digest)
    }

    private init(draft: ReviewPlanDraft, canonicalBytes: [UInt8], digest: PlanDigest) {
        targets = draft.targets
        versionContext = draft.versionContext
        launchSession = draft.launchSession
        createdAt = draft.createdAt
        expiresAt = draft.expiresAt
        self.canonicalBytes = canonicalBytes
        self.digest = digest
    }
}
