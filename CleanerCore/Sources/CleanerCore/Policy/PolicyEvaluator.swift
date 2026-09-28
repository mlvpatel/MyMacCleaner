public struct PolicyEvaluator: Sendable {
    private let cacheOwners: GeneralMacCacheOwnerCatalog

    public init() {
        self.init(cacheOwners: .current)
    }

    init(cacheOwners: GeneralMacCacheOwnerCatalog) {
        self.cacheOwners = cacheOwners
    }

    /// The public entry point derives all positive facts from immutable scanner
    /// evidence. Callers cannot supply a hand-written activity or scope proof.
    public func evaluate(_ finding: GeneralMacFinding) -> PolicyEvaluation {
        evaluate(finding, processActive: false)
    }

    /// Evaluates a finding with an external process-activity observation (C5). A
    /// file a running process holds open is forced to in-use and never eligible.
    public func evaluate(_ finding: GeneralMacFinding, processActive: Bool) -> PolicyEvaluation {
        evaluate(.observed(from: finding, processActive: processActive))
    }

    func evaluate(_ evidence: GeneralMacPolicyEvidence) -> PolicyEvaluation {
        let finding = evidence.finding
        let detector = DetectorSelection(
            id: finding.finding.detectorID,
            version: finding.finding.detectorVersion
        )
        let owner = semanticOwner(for: finding)

        guard detector == generalMacSelection else {
            return ineligible(
                detector: detector,
                owner: .unknown,
                disposition: .unknownInspectFirst,
                rule: .unknownEvidenceV1,
                rationale: .unsupportedEvidence,
                recovery: .inspectBeforeAction,
                confidence: finding.confidence
            )
        }
        guard finding.completeness == .complete else {
            return ineligible(
                detector: detector,
                owner: owner,
                disposition: .unknownInspectFirst,
                rule: .unknownEvidenceV1,
                rationale: .incompleteEvidence,
                recovery: .inspectBeforeAction,
                confidence: finding.confidence
            )
        }
        guard hasVerifiedScannerShape(finding) else {
            return ineligible(
                detector: detector,
                owner: owner,
                disposition: .unknownInspectFirst,
                rule: .unknownEvidenceV1,
                rationale: .unsupportedEvidence,
                recovery: .inspectBeforeAction,
                confidence: finding.confidence
            )
        }
        guard evidence.activity == .observedInactive else {
            return ineligible(
                detector: detector,
                owner: owner,
                disposition: .unknownInspectFirst,
                rule: .unknownEvidenceV1,
                rationale: evidence.activity == .observedActive ? .activeEvidence : .unsupportedEvidence,
                recovery: .inspectBeforeAction,
                confidence: finding.confidence
            )
        }
        guard finding.space.hasObservedNoSharedBytes else {
            return ineligible(
                detector: detector,
                owner: owner,
                disposition: .unknownInspectFirst,
                rule: .unknownEvidenceV1,
                rationale: .linkedOrUnknownSharing,
                recovery: .inspectBeforeAction,
                confidence: finding.confidence
            )
        }

        switch owner {
        case .generalRebuildableCache:
            return evaluateCache(evidence, detector: detector)
        case .generalLog:
            return ineligible(detector: detector, owner: owner, disposition: .mayAffectWorkflow,
                              rule: .generalLogReviewV1, rationale: .namedReviewRule,
                              recovery: .inspectBeforeAction, confidence: finding.confidence)
        case .generalCrashReport:
            return ineligible(detector: detector, owner: owner, disposition: .mayAffectWorkflow,
                              rule: .generalCrashReviewV1, rationale: .namedReviewRule,
                              recovery: .inspectBeforeAction, confidence: finding.confidence)
        case .generalTemporaryData:
            return ineligible(detector: detector, owner: owner, disposition: .redownloadRequired,
                              rule: .generalTemporaryReviewV1, rationale: .namedReviewRule,
                              recovery: .redownloadRequired, confidence: finding.confidence)
        case .personalLargeFile, .duplicateEvidence, .modelStore, .developerToolState,
             .credential, .setting, .workloadObservation, .unknown:
            return protected(detector: detector, owner: owner, confidence: finding.confidence)
        }
    }

    public func protectedEvaluation(
        detector: DetectorSelection,
        owner: PolicySemanticOwner,
        confidence: EvidenceConfidence = .unavailable
    ) -> PolicyEvaluation {
        protected(detector: detector, owner: owner, confidence: confidence)
    }

    private func evaluateCache(
        _ evidence: GeneralMacPolicyEvidence,
        detector: DetectorSelection
    ) -> PolicyEvaluation {
        let finding = evidence.finding
        // Checked before the eligible path and always ineligible, so a catalog
        // entry can relabel or narrow a cache but never make it a candidate.
        if let ownerClass = cacheOwners.ownerClass(for: finding.finding.locator.components) {
            return ownerReview(ownerClass, detector: detector, confidence: finding.confidence)
        }
        guard finding.source == .userLibraryCaches,
              finding.category == .cache,
              evidence.scopeProof == .namedFixedScopeGeneralCacheV1,
              finding.rebuildImpact == .rebuildable,
              finding.conservativeRisk == .low,
              finding.confidence == .observed,
              case let .observed(bytes) = finding.space.conservativeReclaimableBytes,
              bytes > 0
        else {
            return ineligible(
                detector: detector,
                owner: .generalRebuildableCache,
                disposition: .unknownInspectFirst,
                rule: .unknownEvidenceV1,
                rationale: .unsupportedEvidence,
                recovery: .inspectBeforeAction,
                confidence: finding.confidence
            )
        }
        let factors = CandidateRankFactors(
            recoveryCost: .rebuild,
            confidence: finding.confidence,
            workflowImpact: .none,
            conservativeBytes: bytes
        )
        let candidate = EligibleCandidate(
            evidence: evidence,
            semanticOwner: .generalRebuildableCache,
            rule: .generalCacheRegenerationV1,
            rationale: .namedSafeRegenerationRule,
            rankFactors: factors
        )
        return .init(
            detector: detector,
            disposition: .safeToRegenerate,
            eligibility: .eligible,
            semanticOwner: .generalRebuildableCache,
            rule: .generalCacheRegenerationV1,
            rationale: .namedSafeRegenerationRule,
            recoveryPath: .rebuildable,
            confidence: finding.confidence,
            candidate: candidate
        )
    }

    private func ownerReview(
        _ ownerClass: GeneralMacCacheOwnerClass,
        detector: DetectorSelection,
        confidence: EvidenceConfidence
    ) -> PolicyEvaluation {
        switch ownerClass {
        case .redownloadRequired:
            return ineligible(detector: detector, owner: .generalRebuildableCache, disposition: .redownloadRequired,
                              rule: .generalCacheOwnerReviewV1, rationale: .namedReviewRule,
                              recovery: .redownloadRequired, confidence: confidence)
        case .mayAffectWorkflow:
            return ineligible(detector: detector, owner: .generalRebuildableCache, disposition: .mayAffectWorkflow,
                              rule: .generalCacheOwnerReviewV1, rationale: .namedReviewRule,
                              recovery: .inspectBeforeAction, confidence: confidence)
        case .developerToolState:
            return protected(detector: detector, owner: .developerToolState, confidence: confidence)
        }
    }

    private func protected(
        detector: DetectorSelection,
        owner: PolicySemanticOwner,
        confidence: EvidenceConfidence
    ) -> PolicyEvaluation {
        ineligible(
            detector: detector,
            owner: owner,
            disposition: .keepProtected,
            rule: .protectedOwnerV1,
            rationale: .protectedSemanticOwner,
            recovery: .protectedNoOperation,
            confidence: confidence
        )
    }

    private func ineligible(
        detector: DetectorSelection,
        owner: PolicySemanticOwner,
        disposition: PolicyDisposition,
        rule: PolicyRuleReference,
        rationale: PolicyRationale,
        recovery: PolicyRecoveryPath,
        confidence: EvidenceConfidence
    ) -> PolicyEvaluation {
        .init(
            detector: detector,
            disposition: disposition,
            eligibility: .ineligible,
            semanticOwner: owner,
            rule: rule,
            rationale: rationale,
            recoveryPath: recovery,
            confidence: confidence,
            candidate: nil
        )
    }

    private var generalMacSelection: DetectorSelection {
        .init(id: GeneralMacScopeCatalog.current.detectorID, version: GeneralMacScopeCatalog.current.version)
    }

    private func semanticOwner(for finding: GeneralMacFinding) -> PolicySemanticOwner {
        // A credential-named locator is always a protected credential owner,
        // even when its category would otherwise be eligible. This only ever
        // narrows eligibility — `.credential` routes to `protected`.
        if Self.isCredentialLocator(finding.finding.locator.components) {
            return .credential
        }
        switch finding.category {
        case .cache:
            guard finding.source == .userLibraryCaches else { return .unknown }
            // Protected tool state is labelled as such on every path, not only the eligible one.
            if cacheOwners.ownerClass(for: finding.finding.locator.components) == .developerToolState {
                return .developerToolState
            }
            return .generalRebuildableCache
        case .log: return .generalLog
        case .crashReport: return .generalCrashReport
        case .temporary: return .generalTemporaryData
        case .largeFile: return .personalLargeFile
        case .duplicate: return .duplicateEvidence
        }
    }

    /// Fixed credential locators that must never become a cleanup candidate.
    static let credentialExactNames: Set<String> = ["mcp.json", ".claude.json", "auth.json", ".env"]
    static let credentialNamePrefixes: [String] = ["credentials", ".env."]

    static func isCredentialLocator(_ components: [String]) -> Bool {
        guard let name = components.last?.lowercased() else { return false }
        if credentialExactNames.contains(name) { return true }
        return credentialNamePrefixes.contains { name.hasPrefix($0) }
    }

    private func hasVerifiedScannerShape(_ finding: GeneralMacFinding) -> Bool {
        let raw = finding.finding
        guard raw.id.detectorID == raw.detectorID,
              raw.id.rootID == raw.declaredRoot.id,
              raw.id.locatorComponents == raw.locator.components,
              raw.locator.rootID == raw.declaredRoot.id,
              raw.provenance == .filesystemObservation,
              raw.fileKind == .regularFile,
              raw.resourceIdentity.isObserved,
              raw.volume.isObserved,
              raw.linkCount == .observed(1),
              raw.sizes.logicalBytes == finding.space.logicalBytes,
              raw.sizes.allocatedBytes == finding.space.allocatedBytes,
              finding.space.hasObservedNoSharedBytes,
              finding.space.conservativeReclaimableBytes == raw.sizes.allocatedBytes,
              allBoundariesAreObservedFalse(raw.boundaries)
        else {
            return false
        }
        return true
    }

    private func allBoundariesAreObservedFalse(_ boundaries: BoundaryEvidence) -> Bool {
        [
            boundaries.symlink, boundaries.alias, boundaries.package, boundaries.mount,
            boundaries.protectedRoot, boundaries.homeBoundary, boundaries.externalVolume,
        ].allSatisfy { $0 == .observed(false) }
    }
}

private extension EvidenceValue {
    var isObserved: Bool {
        if case .observed = self { return true }
        return false
    }
}
