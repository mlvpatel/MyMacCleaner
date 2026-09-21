/// Descriptive MLX evidence only. It cannot create a root, selection, policy,
/// reclaimability, or operation authority.
public enum ModelAssociationStrength: Equatable, Sendable {
    case proven
    case inferred
    case unknown
}

public enum ModelAssociationEvidenceKind: Equatable, Sendable {
    case explicitFormatField
    case explicitProvenanceField
    case namedLocalFormatEvidence
    case noObservedEvidence
}

public struct ModelAssociationEvidence: Equatable, Sendable {
    public let strength: ModelAssociationStrength
    public let kind: ModelAssociationEvidenceKind

    public init?(strength: ModelAssociationStrength, kind: ModelAssociationEvidenceKind) {
        switch (strength, kind) {
        case (.proven, .explicitFormatField), (.proven, .explicitProvenanceField),
             (.inferred, .namedLocalFormatEvidence), (.unknown, .noObservedEvidence):
            self.strength = strength
            self.kind = kind
        default:
            return nil
        }
    }

    public static let unknown = ModelAssociationEvidence(
        uncheckedStrength: .unknown,
        kind: .noObservedEvidence
    )

    private init(uncheckedStrength: ModelAssociationStrength, kind: ModelAssociationEvidenceKind) {
        strength = uncheckedStrength
        self.kind = kind
    }
}
