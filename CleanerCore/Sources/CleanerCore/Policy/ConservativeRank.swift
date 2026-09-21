public struct ConservativeRankKey: Equatable, Sendable {
    public let recoveryCost: RecoveryCost
    public let confidence: EvidenceConfidence
    public let workflowImpact: WorkflowImpact
    public let conservativeBytes: Int64
    public let stableIdentity: StableFindingIdentity

    init(candidate: EligibleCandidate) {
        recoveryCost = candidate.rankFactors.recoveryCost
        confidence = candidate.rankFactors.confidence
        workflowImpact = candidate.rankFactors.workflowImpact
        conservativeBytes = candidate.rankFactors.conservativeBytes
        stableIdentity = candidate.stableIdentity
    }
}

public enum ConservativeRank {
    public static func key(for candidate: EligibleCandidate) -> ConservativeRankKey {
        .init(candidate: candidate)
    }

    public static func ordered(_ candidates: [EligibleCandidate]) -> [EligibleCandidate] {
        candidates.sorted(by: precedes)
    }

    static func precedes(_ lhs: EligibleCandidate, _ rhs: EligibleCandidate) -> Bool {
        let left = key(for: lhs)
        let right = key(for: rhs)
        if left.recoveryCost != right.recoveryCost { return left.recoveryCost.rawValue < right.recoveryCost.rawValue }
        if left.confidence != right.confidence { return confidenceOrder(left.confidence) > confidenceOrder(right.confidence) }
        if left.workflowImpact != right.workflowImpact { return left.workflowImpact.rawValue < right.workflowImpact.rawValue }
        if left.conservativeBytes != right.conservativeBytes { return left.conservativeBytes > right.conservativeBytes }
        return left.stableIdentity.utf8Bytes.lexicographicallyPrecedes(right.stableIdentity.utf8Bytes)
    }

    private static func confidenceOrder(_ confidence: EvidenceConfidence) -> Int {
        switch confidence {
        case .observed: 2
        case .partial: 1
        case .unavailable: 0
        }
    }
}
