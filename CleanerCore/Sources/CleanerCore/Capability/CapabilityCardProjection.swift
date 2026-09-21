public enum CapabilityAuthority: Equatable, Sendable {
    case inventoryOnly
    case reviewPlanCapable
}

public enum ConditionalOperationDescription: Equatable, Sendable {
    case none
    case moveToTrashAfterApprovalAndFreshRevalidation
}

public enum CapabilityProtectionReason: Equatable, Sendable {
    case incompleteEvidence
    case protectedSemanticOwner
    case unknownOrUnsupportedEvidence
    case activeOrSharedEvidence
}

public struct CapabilityCard: Equatable, Sendable {
    public let detector: DetectorSelection
    public let authority: CapabilityAuthority
    public let conditionalOperation: ConditionalOperationDescription
    public let recoveryPath: PolicyRecoveryPath
    public let confidence: EvidenceConfidence
    public let protectionReason: CapabilityProtectionReason?

    init(
        detector: DetectorSelection,
        authority: CapabilityAuthority,
        conditionalOperation: ConditionalOperationDescription,
        recoveryPath: PolicyRecoveryPath,
        confidence: EvidenceConfidence,
        protectionReason: CapabilityProtectionReason?
    ) {
        self.detector = detector
        self.authority = authority
        self.conditionalOperation = conditionalOperation
        self.recoveryPath = recoveryPath
        self.confidence = confidence
        self.protectionReason = protectionReason
    }
}

public struct CapabilityCardProjection: Sendable {
    public init() {}

    public func card(for detector: DetectorSelection, evaluation: PolicyEvaluation) -> CapabilityCard {
        guard detector == evaluation.detector, registeredDetectors.contains(detector) else {
            return inventoryCard(
                detector: detector,
                recovery: .inspectBeforeAction,
                confidence: .unavailable,
                reason: .unknownOrUnsupportedEvidence
            )
        }
        guard evaluation.eligibility == .eligible,
              evaluation.semanticOwner == .generalRebuildableCache,
              evaluation.candidate != nil
        else {
            return inventoryCard(
                detector: detector,
                recovery: evaluation.recoveryPath,
                confidence: evaluation.confidence,
                reason: protectionReason(for: evaluation.rationale)
            )
        }
        return .init(
            detector: detector,
            authority: .reviewPlanCapable,
            conditionalOperation: .moveToTrashAfterApprovalAndFreshRevalidation,
            recoveryPath: evaluation.recoveryPath,
            confidence: evaluation.confidence,
            protectionReason: nil
        )
    }

    public func cards(for evaluations: [PolicyEvaluation]) -> [CapabilityCard] {
        registeredDetectors.map { detector in
            let matching = evaluations.filter { $0.detector == detector }
            let evaluation = matching.count == 1
                ? matching[0]
                : PolicyEvaluator().protectedEvaluation(detector: detector, owner: owner(for: detector))
            return card(for: detector, evaluation: evaluation)
        }
    }

    private var registeredDetectors: [DetectorSelection] {
        [
            .init(id: GeneralMacScopeCatalog.current.detectorID, version: GeneralMacScopeCatalog.current.version),
            ModelStoreDetectorRegistration.huggingFaceSelection,
            ModelStoreDetectorRegistration.ollamaSelection,
            ModelStoreDetectorRegistration.selectedRootSelection,
        ]
    }

    private func owner(for detector: DetectorSelection) -> PolicySemanticOwner {
        detector == DetectorSelection(
            id: GeneralMacScopeCatalog.current.detectorID,
            version: GeneralMacScopeCatalog.current.version
        ) ? .unknown : .modelStore
    }

    private func inventoryCard(
        detector: DetectorSelection,
        recovery: PolicyRecoveryPath,
        confidence: EvidenceConfidence,
        reason: CapabilityProtectionReason
    ) -> CapabilityCard {
        .init(
            detector: detector,
            authority: .inventoryOnly,
            conditionalOperation: .none,
            recoveryPath: recovery,
            confidence: confidence,
            protectionReason: reason
        )
    }

    private func protectionReason(for rationale: PolicyRationale) -> CapabilityProtectionReason {
        switch rationale {
        case .incompleteEvidence: .incompleteEvidence
        case .protectedSemanticOwner: .protectedSemanticOwner
        case .activeEvidence, .linkedOrUnknownSharing: .activeOrSharedEvidence
        case .namedSafeRegenerationRule, .namedReviewRule, .unsupportedEvidence:
            .unknownOrUnsupportedEvidence
        }
    }
}
