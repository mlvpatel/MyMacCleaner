public enum PolicyDisposition: String, CaseIterable, Equatable, Sendable {
    case safeToRegenerate
    case redownloadRequired
    case mayAffectWorkflow
    case keepProtected
    case unknownInspectFirst
}

public enum PolicyEligibility: Equatable, Sendable {
    case eligible
    case ineligible
}

public enum PolicySemanticOwner: String, CaseIterable, Equatable, Sendable {
    case generalRebuildableCache
    case generalLog
    case generalCrashReport
    case generalTemporaryData
    case personalLargeFile
    case duplicateEvidence
    case modelStore
    case developerToolState
    case credential
    case setting
    case workloadObservation
    case unknown
}

public enum PolicyActivityEvidence: Equatable, Sendable {
    case observedInactive
    case observedActive
    case unknown
}

/// This proof is issued only by a package-owned detector rule. It is distinct
/// from a broad `~/Library/Caches` classification: unproved cache entries stay
/// visible but are not candidate-capable.
public enum GeneralMacScopeProof: Equatable, Sendable {
    case namedFixedScopeGeneralCacheV1
    case unsupported
}

/// The policy boundary requires a positive observation that the cache is not
/// active and a named fixed-scope regeneration proof. A bare
/// `GeneralMacFinding` therefore cannot become a candidate.
public struct GeneralMacPolicyEvidence: Equatable, Sendable {
    public let finding: GeneralMacFinding
    public let activity: PolicyActivityEvidence
    public let scopeProof: GeneralMacScopeProof

    init(
        finding: GeneralMacFinding,
        activity: PolicyActivityEvidence,
        scopeProof: GeneralMacScopeProof
    ) {
        self.finding = finding
        self.activity = activity
        self.scopeProof = scopeProof
    }
}

extension GeneralMacPolicyEvidence {
    /// `processActive` reflects an external observation that a running process
    /// currently holds this file open. When true it forces `.observedActive`,
    /// which the evaluator treats as in-use and never eligible — so process
    /// correlation can only ever narrow eligibility, never widen it.
    static func observed(from finding: GeneralMacFinding, processActive: Bool = false) -> Self {
        .init(
            finding: finding,
            activity: processActive ? .observedActive : activity(for: finding),
            scopeProof: scopeProof(for: finding)
        )
    }

    private static func activity(for finding: GeneralMacFinding) -> PolicyActivityEvidence {
        guard case let .observed(modification, observedAt) = finding.age,
              observedAt.unixNanoseconds >= 900_000_000_000,
              modification.unixNanoseconds <= observedAt.unixNanoseconds - 900_000_000_000
        else {
            return .unknown
        }
        return .observedInactive
    }

    private static func scopeProof(for finding: GeneralMacFinding) -> GeneralMacScopeProof {
        guard finding.finding.detectorID == GeneralMacScopeCatalog.current.detectorID,
              finding.finding.detectorVersion == GeneralMacScopeCatalog.current.version,
              finding.source == .userLibraryCaches,
              finding.category == .cache,
              finding.finding.locator.components.first == "com.apple.iconservices.store"
        else {
            return .unsupported
        }
        return .namedFixedScopeGeneralCacheV1
    }
}

public struct PolicyRuleReference: Equatable, Sendable {
    public let identifier: String
    public let version: String

    private init(identifier: String, version: String) {
        self.identifier = identifier
        self.version = version
    }

    public static let generalCacheRegenerationV1 = Self(
        identifier: "general-cache-regeneration",
        version: "1"
    )
    public static let generalLogReviewV1 = Self(identifier: "general-log-review", version: "1")
    public static let generalCrashReviewV1 = Self(identifier: "general-crash-review", version: "1")
    public static let generalTemporaryReviewV1 = Self(identifier: "general-temporary-review", version: "1")
    public static let protectedOwnerV1 = Self(identifier: "protected-owner", version: "1")
    public static let unknownEvidenceV1 = Self(identifier: "unknown-evidence", version: "1")
}

public enum PolicyRationale: String, Equatable, Sendable {
    case namedSafeRegenerationRule
    case namedReviewRule
    case protectedSemanticOwner
    case incompleteEvidence
    case unsupportedEvidence
    case activeEvidence
    case linkedOrUnknownSharing
}

public enum PolicyRecoveryPath: String, Equatable, Sendable {
    case rebuildable
    case redownloadRequired
    case inspectBeforeAction
    case protectedNoOperation
}

public enum RecoveryCost: Int, CaseIterable, Equatable, Sendable {
    case rebuild = 0
    case redownload = 1
    case workflowReview = 2
    case protected = 3
}

public enum WorkflowImpact: Int, CaseIterable, Equatable, Sendable {
    case none = 0
    case review = 1
    case protected = 2
}

public struct CandidateRankFactors: Equatable, Sendable {
    public let recoveryCost: RecoveryCost
    public let confidence: EvidenceConfidence
    public let workflowImpact: WorkflowImpact
    public let conservativeBytes: Int64

    init(
        recoveryCost: RecoveryCost,
        confidence: EvidenceConfidence,
        workflowImpact: WorkflowImpact,
        conservativeBytes: Int64
    ) {
        self.recoveryCost = recoveryCost
        self.confidence = confidence
        self.workflowImpact = workflowImpact
        self.conservativeBytes = conservativeBytes
    }
}

public struct StableFindingIdentity: Equatable, Sendable {
    public let utf8Bytes: [UInt8]

    public var hex: String {
        let nibbles: [Character] = [
            "0", "1", "2", "3", "4", "5", "6", "7",
            "8", "9", "a", "b", "c", "d", "e", "f"
        ]
        var characters: [Character] = []
        characters.reserveCapacity(utf8Bytes.count * 2)
        for byte in utf8Bytes {
            characters.append(nibbles[Int(byte >> 4)])
            characters.append(nibbles[Int(byte & 0x0F)])
        }
        return String(characters)
    }

    init(finding: Finding) {
        let fields = [finding.detectorID.value, finding.declaredRoot.id.value] + finding.locator.components
        utf8Bytes = fields.flatMap { field in
            let bytes = Array(field.utf8)
            return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
        }
    }
}

/// A candidate is a frozen policy result, not a selectable UI value. Its
/// initializer is package-scoped so external callers cannot manufacture one.
public struct EligibleCandidate: Equatable, Sendable {
    public let evidence: GeneralMacPolicyEvidence
    public let semanticOwner: PolicySemanticOwner
    public let rule: PolicyRuleReference
    public let rationale: PolicyRationale
    public let rankFactors: CandidateRankFactors
    public let stableIdentity: StableFindingIdentity

    init(
        evidence: GeneralMacPolicyEvidence,
        semanticOwner: PolicySemanticOwner,
        rule: PolicyRuleReference,
        rationale: PolicyRationale,
        rankFactors: CandidateRankFactors
    ) {
        self.evidence = evidence
        self.semanticOwner = semanticOwner
        self.rule = rule
        self.rationale = rationale
        self.rankFactors = rankFactors
        stableIdentity = .init(finding: evidence.finding.finding)
    }
}

public struct PolicyEvaluation: Equatable, Sendable {
    public let detector: DetectorSelection
    public let disposition: PolicyDisposition
    public let eligibility: PolicyEligibility
    public let semanticOwner: PolicySemanticOwner
    public let rule: PolicyRuleReference
    public let rationale: PolicyRationale
    public let recoveryPath: PolicyRecoveryPath
    public let confidence: EvidenceConfidence
    public let candidate: EligibleCandidate?

    init(
        detector: DetectorSelection,
        disposition: PolicyDisposition,
        eligibility: PolicyEligibility,
        semanticOwner: PolicySemanticOwner,
        rule: PolicyRuleReference,
        rationale: PolicyRationale,
        recoveryPath: PolicyRecoveryPath,
        confidence: EvidenceConfidence,
        candidate: EligibleCandidate?
    ) {
        self.detector = detector
        self.disposition = disposition
        self.eligibility = eligibility
        self.semanticOwner = semanticOwner
        self.rule = rule
        self.rationale = rationale
        self.recoveryPath = recoveryPath
        self.confidence = confidence
        self.candidate = candidate
    }
}
