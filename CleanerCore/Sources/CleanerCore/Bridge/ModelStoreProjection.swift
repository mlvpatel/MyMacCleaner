public struct ModelStoreProjection: Equatable, Sendable {
    public let state: ProjectedScanState
    public let detectorID: DetectorID
    public let detectorVersion: DetectorVersion
    public let entries: [ProjectedModelStoreEntry]
    public let accounting: ModelStoreAccountingSummary
    public let repositories: [ModelStoreRepository]
    public let refs: [ModelStoreRef]
    public let snapshots: [ModelStoreSnapshot]
    public let blobs: [ModelStoreBlob]
    public let incompleteBlobs: [ModelStoreBlob]
    public let snapshotBlobEdges: [ModelStoreSnapshotBlobEdge]
    public let diagnostics: [ModelStoreDiagnostic]
    public let association: ModelAssociationEvidence?
    public let protectionReason: ModelStoreProtectionReason

    public init(result: ModelStoreParseResult) {
        state = ProjectedScanState(result.outcome)
        detectorID = result.graph.detector.id
        detectorVersion = result.graph.detector.version
        accounting = ModelStoreAccounting(graph: result.graph).summary
        repositories = result.graph.repositories
        refs = result.graph.refs
        snapshots = result.graph.snapshots
        blobs = result.graph.blobs
        incompleteBlobs = result.graph.incompleteBlobs
        snapshotBlobEdges = result.graph.snapshotBlobEdges
        diagnostics = result.graph.diagnostics
        association = result.graph.association
        switch result.graph.protection {
        case .inspectOnly(let reason):
            protectionReason = reason
        }
        entries = result.graph.roots.map {
            ProjectedModelStoreEntry(
                rootID: $0.identity.rootID,
                layout: $0.layout,
                authority: $0.authority,
                isSelected: false,
                reclaimability: .protectedNotEligible,
                operation: nil
            )
        }
    }
}
public struct ProjectedModelStoreEntry: Equatable, Sendable {
    public let rootID: DeclaredRootID
    public let layout: ModelStoreLayoutVersion
    public let authority: ModelStoreRootAuthority
    public let isSelected: Bool
    public let reclaimability: ModelStoreReclaimability
    public let operation: Never?

    public init(
        rootID: DeclaredRootID,
        layout: ModelStoreLayoutVersion,
        authority: ModelStoreRootAuthority,
        isSelected: Bool,
        reclaimability: ModelStoreReclaimability,
        operation: Never?
    ) {
        self.rootID = rootID
        self.layout = layout
        self.authority = authority
        self.isSelected = isSelected
        self.reclaimability = reclaimability
        self.operation = operation
    }
}
