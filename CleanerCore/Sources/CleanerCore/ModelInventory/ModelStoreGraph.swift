public struct ModelStoreDetector: Equatable, Sendable {
    public let id: DetectorID
    public let version: DetectorVersion

    public init(id: DetectorID, version: DetectorVersion) {
        self.id = id
        self.version = version
    }

    public static let huggingFaceV1 = ModelStoreDetector(
        id: trustedDetectorID("modelstore.huggingface"),
        version: trustedDetectorVersion("1.0.0")
    )

    public static let ollamaV1 = ModelStoreDetector(
        id: trustedDetectorID("modelstore.ollama"),
        version: trustedDetectorVersion("1.0.0")
    )

    public static let selectedRootV1 = ModelStoreDetector(
        id: trustedDetectorID("modelstore.selected-root"),
        version: trustedDetectorVersion("1.0.0")
    )

    private static func trustedDetectorID(_ rawValue: String) -> DetectorID {
        do {
            return try DetectorID(rawValue)
        } catch {
            preconditionFailure("invalid package-owned detector identifier")
        }
    }

    private static func trustedDetectorVersion(_ rawValue: String) -> DetectorVersion {
        do {
            return try DetectorVersion(rawValue)
        } catch {
            preconditionFailure("invalid package-owned detector version")
        }
    }
}

public struct ModelStoreRootIdentity: Equatable, Hashable, Sendable {
    public let rootID: DeclaredRootID

    public init(rootID: DeclaredRootID) {
        self.rootID = rootID
    }
}

public enum ModelStoreDefaultRootToken: Equatable, Sendable {
    case huggingFaceCache
    case ollamaModels
}

public struct ModelStoreSelectedRootToken: Equatable, Sendable {
    public let isValidated: Bool

    private init(isValidated: Bool) {
        self.isValidated = isValidated
    }

    package static let validated = ModelStoreSelectedRootToken(isValidated: true)
    package static let unvalidated = ModelStoreSelectedRootToken(isValidated: false)
}

public enum ModelStoreRootAuthority: Equatable, Sendable {
    case documentedDefault(ModelStoreDefaultRootToken)
    case explicitSelection(ModelStoreSelectedRootToken)
}

public enum ModelStoreLayoutVersion: Equatable, Sendable {
    case huggingFaceCacheV1
    case ollamaV1
    case selectedRootV1
}

public struct ModelStoreRoot: Equatable, Sendable {
    public static let huggingFaceDefaultRootID = trustedRootID("huggingface.default-cache")
    public static let ollamaDefaultRootID = trustedRootID("ollama.default-models")

    public let identity: ModelStoreRootIdentity
    public let authority: ModelStoreRootAuthority
    public let layout: ModelStoreLayoutVersion

    public init(
        identity: ModelStoreRootIdentity,
        authority: ModelStoreRootAuthority,
        layout: ModelStoreLayoutVersion
    ) {
        self.identity = identity
        self.authority = authority
        self.layout = layout
    }

    public static func defaultHuggingFaceCache() -> ModelStoreRoot {
        .init(
            identity: .init(rootID: huggingFaceDefaultRootID),
            authority: .documentedDefault(.huggingFaceCache),
            layout: .huggingFaceCacheV1
        )
    }

    public static func defaultOllamaModels() -> ModelStoreRoot {
        .init(
            identity: .init(rootID: ollamaDefaultRootID),
            authority: .documentedDefault(.ollamaModels),
            layout: .ollamaV1
        )
    }

    /// Builds a root after a package-owned UI bridge has recorded explicit user
    /// consent and issued a validated token. Public issuance is deliberately
    /// deferred until that bridge can preserve the consent receipt; callers
    /// cannot manufacture authority from a path string in this trust core.
    public static func explicitlySelected(
        rootID: DeclaredRootID,
        selection: ModelStoreSelectedRootToken,
        layout: ModelStoreLayoutVersion = .huggingFaceCacheV1
    ) -> ModelStoreRoot {
        .init(
            identity: .init(rootID: rootID),
            authority: .explicitSelection(selection),
            layout: layout
        )
    }

    private static func trustedRootID(_ rawValue: String) -> DeclaredRootID {
        do {
            return try DeclaredRootID(rawValue)
        } catch {
            preconditionFailure("invalid package-owned root identifier")
        }
    }
}

public enum ModelStoreEnvironmentValueState: Equatable, Sendable {
    case presentButNotAuthority
}

public struct ModelStoreEnvironmentEvidence: Equatable, Sendable {
    public let name: String
    public let valueState: ModelStoreEnvironmentValueState

    public init(name: String, valueState: ModelStoreEnvironmentValueState) {
        self.name = name
        self.valueState = valueState
    }
}

public enum ModelStoreRootFault: Equatable, Sendable {
    case unavailableVolume
    case rootChanged
    case volumeChanged
    case permissionDenied
}

public struct ModelStoreRootEvidence: Equatable, Sendable {
    public let rootID: DeclaredRootID
    public let volume: VolumeID
    public let fault: ModelStoreRootFault?
    public let environmentEvidence: [ModelStoreEnvironmentEvidence]

    public init(
        rootID: DeclaredRootID,
        volume: VolumeID,
        fault: ModelStoreRootFault?,
        environmentEvidence: [ModelStoreEnvironmentEvidence]
    ) {
        self.rootID = rootID
        self.volume = volume
        self.fault = fault
        self.environmentEvidence = environmentEvidence
    }
}

public struct ModelStoreLocator: Equatable, Hashable, Sendable {
    public let components: [String]

    public init(_ components: [String]) throws {
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") })
        else {
            throw EvidenceValidationError.invalidRelativeLocator
        }
        self.components = components
    }
}

public enum ModelStoreEntryKind: Equatable, Sendable {
    case directory
    case regularFile
    case symbolicLink
}

public enum ModelStoreEntryTopology: Equatable, Sendable {
    case ordinary
    case package
    case mountTrigger
    case alias
}

public struct ModelStoreEntrySize: Equatable, Sendable {
    public let logicalBytes: EvidenceValue<Int>

    public init(logicalBytes: Int) {
        self.logicalBytes = logicalBytes >= 0 ? .observed(logicalBytes) : .unavailable
    }

    public init(logicalBytes: EvidenceValue<Int>) {
        switch logicalBytes {
        case .observed(let bytes) where bytes >= 0:
            self.logicalBytes = .observed(bytes)
        case .observed:
            self.logicalBytes = .unavailable
        case .unknown:
            self.logicalBytes = .unknown
        case .unavailable:
            self.logicalBytes = .unavailable
        }
    }
}

public struct ModelStoreLinkInspection: Equatable, Sendable {
    public let target: ModelStoreLocator?
    public let targetExists: Bool
    public let targetVolume: EvidenceValue<VolumeID>
    public let targetKind: EvidenceValue<ModelStoreEntryKind>
    public let diagnostic: ModelStoreDiagnosticCode?

    public init(
        target: ModelStoreLocator?,
        targetExists: Bool,
        targetVolume: EvidenceValue<VolumeID>,
        targetKind: EvidenceValue<ModelStoreEntryKind>,
        diagnostic: ModelStoreDiagnosticCode? = nil
    ) {
        self.target = target
        self.targetExists = targetExists
        self.targetVolume = targetVolume
        self.targetKind = targetKind
        self.diagnostic = diagnostic
    }
}

public struct ModelStoreEntryEvidence: Equatable, Sendable {
    public let locator: ModelStoreLocator
    public let kind: ModelStoreEntryKind
    public let size: ModelStoreEntrySize
    public let fileIdentity: EvidenceValue<FileIdentityEvidence>
    public let volume: EvidenceValue<VolumeID>
    public let text: String?
    public let link: ModelStoreLinkInspection?
    public let topology: ModelStoreEntryTopology

    public init(
        locator: ModelStoreLocator,
        kind: ModelStoreEntryKind,
        size: ModelStoreEntrySize,
        fileIdentity: EvidenceValue<FileIdentityEvidence>,
        volume: EvidenceValue<VolumeID>,
        text: String?,
        link: ModelStoreLinkInspection?,
        topology: ModelStoreEntryTopology = .ordinary
    ) {
        self.locator = locator
        self.kind = kind
        self.size = size
        self.fileIdentity = fileIdentity
        self.volume = volume
        self.text = text
        self.link = link
        self.topology = topology
    }
}

public struct ModelStoreRepositoryIdentity: Equatable, Hashable, Sendable {
    public let repositoryID: String

    public init(repositoryID: String) {
        self.repositoryID = repositoryID
    }
}

public struct ModelStoreRepository: Equatable, Sendable {
    public let identity: ModelStoreRepositoryIdentity

    public init(identity: ModelStoreRepositoryIdentity) {
        self.identity = identity
    }
}

public struct ModelStoreRef: Equatable, Sendable {
    public let repositoryID: String
    public let name: String
    public let targetSnapshot: String
}

public struct ModelStoreSnapshot: Equatable, Sendable {
    public let repositoryID: String
    public let snapshotID: String
}

public struct ModelStoreBlobIdentity: Equatable, Sendable {
    public let repositoryID: String
    public let blobID: String
    public let fileIdentity: EvidenceValue<FileIdentityEvidence>

    public init(repositoryID: String, blobID: String, fileIdentity: EvidenceValue<FileIdentityEvidence>) {
        self.repositoryID = repositoryID
        self.blobID = blobID
        self.fileIdentity = fileIdentity
    }
}

extension ModelStoreBlobIdentity: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(repositoryID)
        hasher.combine(blobID)
        switch fileIdentity {
        case .observed(let identity):
            hasher.combine(0)
            hasher.combine(identity.device)
            hasher.combine(identity.node)
        case .unknown:
            hasher.combine(1)
        case .unavailable:
            hasher.combine(2)
        }
    }
}

public struct ModelStoreBlob: Equatable, Sendable {
    public let identity: ModelStoreBlobIdentity
    public let logicalBytes: EvidenceValue<Int>

    public init(identity: ModelStoreBlobIdentity, logicalBytes: Int) {
        self.identity = identity
        self.logicalBytes = logicalBytes >= 0 ? .observed(logicalBytes) : .unavailable
    }

    public init(identity: ModelStoreBlobIdentity, logicalBytes: EvidenceValue<Int>) {
        self.identity = identity
        switch logicalBytes {
        case .observed(let bytes) where bytes >= 0:
            self.logicalBytes = .observed(bytes)
        case .observed:
            self.logicalBytes = .unavailable
        case .unknown:
            self.logicalBytes = .unknown
        case .unavailable:
            self.logicalBytes = .unavailable
        }
    }
}

public struct ModelStoreSnapshotBlobEdge: Equatable, Sendable {
    public let repositoryID: String
    public let snapshotID: String
    public let snapshotFileName: String
    public let blobID: String
}

public enum ModelStoreDiagnosticCode: Equatable, Sendable {
    case unavailableVolume
    case unauthorizedRoot
    case rootChanged
    case permissionDenied
    case unknownLayout
    case corruptRef
    case oversizedRef
    case missingBlob
    case danglingLink
    case escapingLink
    case cyclicLink
    case crossVolumeLink
    case invalidTargetKind
    case unavailableTargetMetadata
    case invalidSize
    case volumeChanged
    case entryLimitExceeded
    case graphLimitExceeded
    case depthLimitExceeded
    case observedByteLimitExceeded
    case cancelled
}

public struct ModelStoreDiagnostic: Equatable, Sendable {
    public let code: ModelStoreDiagnosticCode

    public init(code: ModelStoreDiagnosticCode) {
        self.code = code
    }
}

public enum ModelStoreProtectionReason: Equatable, Sendable {
    case inventoryOnly
    case unauthorizedRoot
    case unavailableVolume
    case changedStore
    case denied
    case corruptRef
    case missingBlob
    case invalidLink
    case boundaryViolation
    case unknownLayout
    case bounded
    case cancelled
}

public enum ModelStoreProtection: Equatable, Sendable {
    case inspectOnly(reason: ModelStoreProtectionReason)
}

public struct ModelStoreGraph: Equatable, Sendable {
    public let detector: ModelStoreDetector
    public let roots: [ModelStoreRoot]
    public let repositories: [ModelStoreRepository]
    public let refs: [ModelStoreRef]
    public let snapshots: [ModelStoreSnapshot]
    public let blobs: [ModelStoreBlob]
    public let incompleteBlobs: [ModelStoreBlob]
    public let snapshotBlobEdges: [ModelStoreSnapshotBlobEdge]
    public let diagnostics: [ModelStoreDiagnostic]
    public let environmentEvidence: [ModelStoreEnvironmentEvidence]
    public let association: ModelAssociationEvidence?
    public let protection: ModelStoreProtection

    public init(
        detector: ModelStoreDetector,
        roots: [ModelStoreRoot],
        repositories: [ModelStoreRepository],
        refs: [ModelStoreRef],
        snapshots: [ModelStoreSnapshot],
        blobs: [ModelStoreBlob],
        incompleteBlobs: [ModelStoreBlob],
        snapshotBlobEdges: [ModelStoreSnapshotBlobEdge],
        diagnostics: [ModelStoreDiagnostic],
        environmentEvidence: [ModelStoreEnvironmentEvidence],
        association: ModelAssociationEvidence? = nil,
        protection: ModelStoreProtection
    ) {
        self.detector = detector
        self.roots = roots
        self.repositories = repositories.sorted { $0.identity.repositoryID < $1.identity.repositoryID }
        self.refs = refs.sorted {
            ($0.repositoryID, $0.name, $0.targetSnapshot) < ($1.repositoryID, $1.name, $1.targetSnapshot)
        }
        self.snapshots = snapshots.sorted {
            ($0.repositoryID, $0.snapshotID) < ($1.repositoryID, $1.snapshotID)
        }
        self.blobs = blobs.sorted {
            ($0.identity.repositoryID, $0.identity.blobID) < ($1.identity.repositoryID, $1.identity.blobID)
        }
        self.incompleteBlobs = incompleteBlobs.sorted {
            ($0.identity.repositoryID, $0.identity.blobID) < ($1.identity.repositoryID, $1.identity.blobID)
        }
        self.snapshotBlobEdges = snapshotBlobEdges.sorted {
            ($0.repositoryID, $0.snapshotID, $0.snapshotFileName, $0.blobID)
                < ($1.repositoryID, $1.snapshotID, $1.snapshotFileName, $1.blobID)
        }
        self.diagnostics = diagnostics
        self.environmentEvidence = environmentEvidence
        self.association = association
        self.protection = protection
    }
}

public struct ModelStoreParseResult: Equatable, Sendable {
    public let outcome: ScanOutcome
    public let graph: ModelStoreGraph

    public init(outcome: ScanOutcome, graph: ModelStoreGraph) {
        self.outcome = outcome
        self.graph = graph
    }
}
