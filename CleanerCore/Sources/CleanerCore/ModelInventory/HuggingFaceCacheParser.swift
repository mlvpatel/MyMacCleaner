public struct ModelStoreCursor: Equatable, Sendable {
    public let position: UInt

    public init(position: UInt) {
        self.position = position
    }
}

public enum ModelStoreEntryStep: Equatable, Sendable {
    case entry(ModelStoreEntryEvidence)
    case complete
    case fault(ModelStoreDiagnosticCode)
}

public enum ModelStoreTextReadFault: Equatable, Sendable {
    case missingEntry
    case oversized
    case denied
    case rootChanged
    case volumeChanged
}

public enum ModelStoreTextReadResult: Equatable, Sendable {
    case success(String)
    case failure(ModelStoreTextReadFault)
}

public struct OllamaLayerObservation: Equatable, Sendable {
    public let mediaType: String
    public let digest: String
    public let size: Int

    public init(mediaType: String, digest: String, size: Int) {
        self.mediaType = mediaType
        self.digest = digest
        self.size = size
    }
}

public struct OllamaManifestObservation: Equatable, Sendable {
    public let schemaVersion: Int
    public let mediaType: String
    public let config: OllamaLayerObservation
    public let layers: [OllamaLayerObservation]

    public init(
        schemaVersion: Int,
        mediaType: String,
        config: OllamaLayerObservation,
        layers: [OllamaLayerObservation]
    ) {
        self.schemaVersion = schemaVersion
        self.mediaType = mediaType
        self.config = config
        self.layers = layers
    }
}

public enum OllamaManifestReadResult: Equatable, Sendable {
    case success(OllamaManifestObservation)
    case failure(ModelStoreTextReadFault)
}

public protocol ModelStoreObservationPort: Sendable {
    func rootEvidence(for root: ModelStoreRoot) async -> ModelStoreRootEvidence
    func nextEntry(after cursor: ModelStoreCursor?, in root: ModelStoreRoot) async -> ModelStoreEntryStep
    func readText(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) async -> ModelStoreTextReadResult
    func inspectLink(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>
    ) async -> ModelStoreLinkInspection
    func readOllamaManifest(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) async -> OllamaManifestReadResult
}

public extension ModelStoreObservationPort {
    func readOllamaManifest(
        in root: ModelStoreRoot,
        at locator: ModelStoreLocator,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) async -> OllamaManifestReadResult {
        .failure(.missingEntry)
    }
}

public protocol ModelStoreCancellation: Sendable {
    func isCancellationRequested() async -> Bool
}

public struct ModelStoreParserLimits: Equatable, Sendable {
    public static let maximumAllowedEntries = 4096
    public static let maximumAllowedRefBytes = 4096
    public static let maximumAllowedGraphNodes = 4096
    public static let maximumAllowedGraphEdges = 4096
    public static let maximumAllowedDepth = 32
    public static let maximumAllowedObservedBytes = 1_099_511_627_776

    public let maximumEntries: Int
    public let maximumRefBytes: Int
    public let maximumGraphNodes: Int
    public let maximumGraphEdges: Int
    public let maximumDepth: Int
    public let maximumObservedBytes: Int

    public init(
        maximumEntries: Int,
        maximumRefBytes: Int,
        maximumGraphNodes: Int,
        maximumGraphEdges: Int,
        maximumDepth: Int = 8,
        maximumObservedBytes: Int = maximumAllowedObservedBytes
    ) throws {
        guard maximumEntries > 0,
              maximumRefBytes > 0,
              maximumGraphNodes > 0,
              maximumGraphEdges > 0,
              maximumDepth > 0,
              maximumObservedBytes > 0
        else {
            throw ModelStoreParserLimitError.nonPositiveLimit
        }
        guard maximumEntries <= Self.maximumAllowedEntries,
              maximumRefBytes <= Self.maximumAllowedRefBytes,
              maximumGraphNodes <= Self.maximumAllowedGraphNodes,
              maximumGraphEdges <= Self.maximumAllowedGraphEdges,
              maximumDepth <= Self.maximumAllowedDepth,
              maximumObservedBytes <= Self.maximumAllowedObservedBytes
        else {
            throw ModelStoreParserLimitError.excessiveLimit
        }
        self.maximumEntries = maximumEntries
        self.maximumRefBytes = maximumRefBytes
        self.maximumGraphNodes = maximumGraphNodes
        self.maximumGraphEdges = maximumGraphEdges
        self.maximumDepth = maximumDepth
        self.maximumObservedBytes = maximumObservedBytes
    }

    public static let fixture = trustedFixture()

    private static func trustedFixture() -> ModelStoreParserLimits {
        do {
            return try ModelStoreParserLimits(
                maximumEntries: 64,
                maximumRefBytes: 4096,
                maximumGraphNodes: 64,
                maximumGraphEdges: 64,
                maximumDepth: 8,
                maximumObservedBytes: 1_048_576
            )
        } catch {
            preconditionFailure("invalid package-owned model-store parser limits")
        }
    }
}

public enum ModelStoreParserLimitError: Error, Equatable, Sendable {
    case nonPositiveLimit
    case excessiveLimit
}

public struct HuggingFaceCacheParser: Sendable {
    public let detector: ModelStoreDetector
    public let limits: ModelStoreParserLimits
    private let port: any ModelStoreObservationPort
    private let cancellation: any ModelStoreCancellation

    public init(
        detector: ModelStoreDetector,
        limits: ModelStoreParserLimits,
        port: any ModelStoreObservationPort,
        cancellation: any ModelStoreCancellation
    ) {
        self.detector = detector
        self.limits = limits
        self.port = port
        self.cancellation = cancellation
    }

    public func parse(root: ModelStoreRoot) async -> ModelStoreParseResult {
        var builder = HuggingFaceGraphBuilder(detector: detector, root: root)

        guard root.isAuthorized else {
            return builder.result(outcome: .corruptMetadata, diagnostic: .unauthorizedRoot)
        }
        guard !(await cancellation.isCancellationRequested()) else {
            return builder.result(
                outcome: .cancelled,
                environmentEvidence: [],
                diagnostic: .cancelled
            )
        }

        let rootEvidence = await port.rootEvidence(for: root)
        builder.environmentEvidence = rootEvidence.environmentEvidence
        guard rootEvidence.rootID == root.identity.rootID else {
            return builder.result(outcome: .corruptMetadata, diagnostic: .rootChanged)
        }
        if let rootFault = rootEvidence.fault {
            return builder.result(for: rootFault)
        }

        var cursor: ModelStoreCursor?
        var entriesRead = 0
        var observedBytes = 0
        while true {
            guard !(await cancellation.isCancellationRequested()) else {
                return builder.result(outcome: .cancelled, diagnostic: .cancelled)
            }
            guard entriesRead < limits.maximumEntries else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .entryLimitExceeded)
            }

            let step = await port.nextEntry(after: cursor, in: root)
            switch step {
            case .complete:
                return builder.finalResult()
            case .fault(let code):
                return builder.result(outcome: outcome(for: code), diagnostic: code)
            case .entry(let entry):
                entriesRead += 1
                cursor = .init(position: UInt(entriesRead))

                guard !(await cancellation.isCancellationRequested()) else {
                    return builder.result(outcome: .cancelled, diagnostic: .cancelled)
                }
                guard entry.locator.components.count <= limits.maximumDepth else {
                    return builder.result(outcome: .unsupportedLayout, diagnostic: .depthLimitExceeded)
                }
                switch entry.volume {
                case .observed(let volume) where volume == rootEvidence.volume:
                    break
                case .observed:
                    return builder.result(outcome: .unsupportedLayout, diagnostic: .crossVolumeLink)
                case .unknown, .unavailable:
                    return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
                }
                let entryLogicalBytes: Int
                switch entry.size.logicalBytes {
                case .observed(let bytes) where bytes >= 0:
                    entryLogicalBytes = bytes
                case .observed, .unknown, .unavailable:
                    return builder.result(outcome: .corruptMetadata, diagnostic: .invalidSize)
                }
                let nextObservedBytes = observedBytes.addingReportingOverflow(entryLogicalBytes)
                guard !nextObservedBytes.overflow,
                      nextObservedBytes.partialValue <= limits.maximumObservedBytes
                else {
                    return builder.result(outcome: .corruptMetadata, diagnostic: .observedByteLimitExceeded)
                }
                observedBytes = nextObservedBytes.partialValue

                if builder.nodeCount >= limits.maximumGraphNodes {
                    return builder.result(outcome: .corruptMetadata, diagnostic: .graphLimitExceeded)
                }
                let handled = await handle(entry, rootEvidence: rootEvidence, builder: &builder)
                if let terminal = handled {
                    return terminal
                }
            }
        }
    }

    private func handle(
        _ entry: ModelStoreEntryEvidence,
        rootEvidence: ModelStoreRootEvidence,
        builder: inout HuggingFaceGraphBuilder
    ) async -> ModelStoreParseResult? {
        let components = entry.locator.components
        if components.first == ".locks" {
            return nil
        }
        guard let repositoryID = components.first,
              repositoryID.hasPrefix("models--")
        else {
            return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
        }

        if entry.kind == .directory, components.count == 1 {
            builder.addRepository(repositoryID)
            return nil
        }

        if entry.kind == .directory,
           (components == [repositoryID, "refs"]
            || components == [repositoryID, "snapshots"]
            || components == [repositoryID, "blobs"]
            || components.count == 3 && components[1] == "snapshots") {
            builder.addRepository(repositoryID)
            return nil
        }

        if entry.kind == .regularFile,
           components.count == 3,
           components[1] == "refs" {
            guard case .observed = entry.fileIdentity else {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
            }
            guard case .observed(let refBytes) = entry.size.logicalBytes else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .invalidSize)
            }
            if refBytes > limits.maximumRefBytes {
                return builder.result(outcome: .corruptMetadata, diagnostic: .oversizedRef)
            }
            let textResult = await port.readText(
                in: builder.root,
                at: entry.locator,
                expectedIdentity: entry.fileIdentity,
                maximumBytes: limits.maximumRefBytes
            )
            guard !(await cancellation.isCancellationRequested()) else {
                return builder.result(outcome: .cancelled, diagnostic: .cancelled)
            }
            switch textResult {
            case .success(let text):
                guard isValidSnapshotID(text) else {
                    return builder.result(outcome: .corruptMetadata, diagnostic: .corruptRef)
                }
                builder.addRef(repositoryID: repositoryID, name: components[2], targetSnapshot: text)
            case .failure(.oversized):
                return builder.result(outcome: .corruptMetadata, diagnostic: .oversizedRef)
            case .failure(.rootChanged):
                return builder.result(outcome: .corruptMetadata, diagnostic: .rootChanged)
            case .failure(.volumeChanged):
                return builder.result(outcome: .corruptMetadata, diagnostic: .volumeChanged)
            case .failure(.missingEntry), .failure(.denied):
                return builder.result(outcome: .corruptMetadata, diagnostic: .corruptRef)
            }
            return nil
        }

        if entry.kind == .regularFile,
           components.count == 3,
           components[1] == "blobs" {
            guard case .observed = entry.fileIdentity else {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
            }
            let blob = ModelStoreBlob(
                identity: .init(
                    repositoryID: repositoryID,
                    blobID: components[2],
                    fileIdentity: entry.fileIdentity
                ),
                logicalBytes: entry.size.logicalBytes
            )
            if components[2].hasSuffix(".incomplete") {
                builder.addIncompleteBlob(blob)
            } else {
                builder.addBlob(blob)
            }
            return nil
        }

        if entry.kind == .symbolicLink,
           components.count == 4,
           components[1] == "snapshots" {
            guard case .observed = entry.fileIdentity else {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
            }
            guard builder.edgeCount < limits.maximumGraphEdges else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .graphLimitExceeded)
            }
            let inspection = await port.inspectLink(
                in: builder.root,
                at: entry.locator,
                expectedIdentity: entry.fileIdentity
            )
            guard !(await cancellation.isCancellationRequested()) else {
                return builder.result(outcome: .cancelled, diagnostic: .cancelled)
            }
            if let diagnostic = inspection.diagnostic {
                return builder.result(outcome: outcome(for: diagnostic), diagnostic: diagnostic)
            }
            guard let target = inspection.target else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .danglingLink)
            }
            if target.components == components {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .cyclicLink)
            }
            switch inspection.targetKind {
            case .observed(.regularFile):
                break
            case .observed(.symbolicLink):
                return builder.result(outcome: .unsupportedLayout, diagnostic: .cyclicLink)
            case .observed:
                return builder.result(outcome: .corruptMetadata, diagnostic: .invalidTargetKind)
            case .unknown, .unavailable:
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
            }
            guard target.components.count == 3,
                  target.components[0] == repositoryID,
                  target.components[1] == "blobs"
            else {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .escapingLink)
            }
            guard inspection.targetExists else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .danglingLink)
            }
            switch inspection.targetVolume {
            case .observed(let targetVolume) where targetVolume == rootEvidence.volume:
                break
            case .observed:
                return builder.result(outcome: .unsupportedLayout, diagnostic: .crossVolumeLink)
            case .unknown, .unavailable:
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
            }
            builder.addSnapshot(repositoryID: repositoryID, snapshotID: components[2])
            builder.addEdge(
                .init(
                    repositoryID: repositoryID,
                    snapshotID: components[2],
                    snapshotFileName: components[3],
                    blobID: target.components[2]
                ))
            return nil
        }

        return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
    }

    private func outcome(for code: ModelStoreDiagnosticCode) -> ScanOutcome {
        switch code {
        case .permissionDenied:
            return .permissionDenied
        case .cancelled:
            return .cancelled
        case .unavailableVolume,
             .unknownLayout,
             .escapingLink,
             .cyclicLink,
             .crossVolumeLink,
             .unavailableTargetMetadata,
             .depthLimitExceeded:
            return .unsupportedLayout
        case .unauthorizedRoot,
             .rootChanged,
             .volumeChanged,
             .corruptRef,
             .oversizedRef,
             .missingBlob,
             .danglingLink,
             .invalidTargetKind,
             .invalidSize,
             .entryLimitExceeded,
             .graphLimitExceeded,
             .observedByteLimitExceeded:
            return .corruptMetadata
        }
    }

    private func isValidSnapshotID(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= limits.maximumRefBytes,
              value.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value)
                      || (65...90).contains(scalar.value)
                      || (97...122).contains(scalar.value)
                      || scalar.value == 45
                      || scalar.value == 95
              })
        else {
            return false
        }
        return true
    }
}

private extension ModelStoreRoot {
    var isAuthorized: Bool {
        switch authority {
        case .documentedDefault(let token):
            return token == .huggingFaceCache && identity.rootID == ModelStoreRoot.huggingFaceDefaultRootID
        case .explicitSelection(let token):
            return token.isValidated
        }
    }
}

private struct HuggingFaceGraphBuilder {
    let detector: ModelStoreDetector
    let root: ModelStoreRoot
    var repositories: [ModelStoreRepository] = []
    var refs: [ModelStoreRef] = []
    var snapshots: [ModelStoreSnapshot] = []
    var blobs: [ModelStoreBlob] = []
    var incompleteBlobs: [ModelStoreBlob] = []
    var edges: [ModelStoreSnapshotBlobEdge] = []
    var diagnostics: [ModelStoreDiagnostic] = []
    var environmentEvidence: [ModelStoreEnvironmentEvidence] = []

    var nodeCount: Int {
        1 + repositories.count + refs.count + snapshots.count + blobs.count + incompleteBlobs.count
    }

    var edgeCount: Int {
        edges.count
    }

    mutating func addRepository(_ repositoryID: String) {
        let repository = ModelStoreRepository(identity: .init(repositoryID: repositoryID))
        if !repositories.contains(repository) {
            repositories.append(repository)
        }
    }

    mutating func addRef(repositoryID: String, name: String, targetSnapshot: String) {
        addRepository(repositoryID)
        refs.append(.init(repositoryID: repositoryID, name: name, targetSnapshot: targetSnapshot))
    }

    mutating func addSnapshot(repositoryID: String, snapshotID: String) {
        addRepository(repositoryID)
        let snapshot = ModelStoreSnapshot(repositoryID: repositoryID, snapshotID: snapshotID)
        if !snapshots.contains(snapshot) {
            snapshots.append(snapshot)
        }
    }

    mutating func addBlob(_ blob: ModelStoreBlob) {
        addRepository(blob.identity.repositoryID)
        if !blobs.contains(blob) {
            blobs.append(blob)
        }
    }

    mutating func addIncompleteBlob(_ blob: ModelStoreBlob) {
        addRepository(blob.identity.repositoryID)
        if !incompleteBlobs.contains(blob) {
            incompleteBlobs.append(blob)
        }
    }

    mutating func addEdge(_ edge: ModelStoreSnapshotBlobEdge) {
        if !edges.contains(edge) {
            edges.append(edge)
        }
    }

    mutating func result(for fault: ModelStoreRootFault) -> ModelStoreParseResult {
        switch fault {
        case .unavailableVolume:
            return result(outcome: .unsupportedLayout, diagnostic: .unavailableVolume)
        case .rootChanged:
            return result(outcome: .corruptMetadata, diagnostic: .rootChanged)
        case .volumeChanged:
            return result(outcome: .corruptMetadata, diagnostic: .volumeChanged)
        case .permissionDenied:
            return result(outcome: .permissionDenied, diagnostic: .permissionDenied)
        }
    }

    mutating func result(
        outcome: ScanOutcome,
        environmentEvidence suppliedEnvironmentEvidence: [ModelStoreEnvironmentEvidence]? = nil,
        diagnostic code: ModelStoreDiagnosticCode
    ) -> ModelStoreParseResult {
        diagnostics.append(.init(code: code))
        if let suppliedEnvironmentEvidence {
            environmentEvidence = suppliedEnvironmentEvidence
        }
        return makeResult(outcome: outcome)
    }

    mutating func finalResult() -> ModelStoreParseResult {
        guard !repositories.isEmpty else {
            return result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
        }
        let observedBlobIDs = Set(blobs.map(\.identity.blobID))
        if edges.contains(where: { !observedBlobIDs.contains($0.blobID) }) {
            return result(outcome: .corruptMetadata, diagnostic: .missingBlob)
        }
        let observedSnapshotKeys = Set(snapshots.map { "\($0.repositoryID)/\($0.snapshotID)" })
        if refs.contains(where: { !observedSnapshotKeys.contains("\($0.repositoryID)/\($0.targetSnapshot)") }) {
            return result(outcome: .corruptMetadata, diagnostic: .corruptRef)
        }
        return makeResult(outcome: diagnostics.isEmpty ? .complete : .corruptMetadata)
    }

    private func makeResult(outcome: ScanOutcome) -> ModelStoreParseResult {
        .init(
            outcome: outcome,
            graph: .init(
                detector: detector,
                roots: [root],
                repositories: repositories,
                refs: refs,
                snapshots: snapshots,
                blobs: blobs,
                incompleteBlobs: incompleteBlobs,
                snapshotBlobEdges: edges,
                diagnostics: diagnostics,
                environmentEvidence: environmentEvidence,
                protection: .inspectOnly(reason: protectionReason(for: diagnostics.last?.code))
            )
        )
    }

    private func protectionReason(for code: ModelStoreDiagnosticCode?) -> ModelStoreProtectionReason {
        switch code {
        case nil:
            return .inventoryOnly
        case .unavailableVolume:
            return .unavailableVolume
        case .rootChanged, .volumeChanged:
            return .changedStore
        case .permissionDenied:
            return .denied
        case .unknownLayout:
            return .unknownLayout
        case .corruptRef, .oversizedRef:
            return .corruptRef
        case .missingBlob:
            return .missingBlob
        case .danglingLink, .cyclicLink, .invalidTargetKind:
            return .invalidLink
        case .escapingLink, .crossVolumeLink, .unavailableTargetMetadata, .depthLimitExceeded:
            return .boundaryViolation
        case .unauthorizedRoot:
            return .unauthorizedRoot
        case .invalidSize, .entryLimitExceeded, .graphLimitExceeded, .observedByteLimitExceeded:
            return .bounded
        case .cancelled:
            return .cancelled
        }
    }
}
