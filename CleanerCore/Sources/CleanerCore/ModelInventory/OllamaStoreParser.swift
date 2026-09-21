/// Bounded, offline-only recognizer for the layout captured by
/// `OllamaLayoutContract`. It never constructs an operation or acts on blobs.
public struct OllamaStoreParser: Sendable {
    public let detector: ModelStoreDetector
    public let contract: OllamaLayoutContract
    public let limits: ModelStoreParserLimits
    private let port: any ModelStoreObservationPort
    private let cancellation: any ModelStoreCancellation

    public init(
        detector: ModelStoreDetector = .ollamaV1,
        contract: OllamaLayoutContract = .v1,
        limits: ModelStoreParserLimits,
        port: any ModelStoreObservationPort,
        cancellation: any ModelStoreCancellation
    ) {
        self.detector = detector
        self.contract = contract
        self.limits = limits
        self.port = port
        self.cancellation = cancellation
    }

    public func parse(root: ModelStoreRoot) async -> ModelStoreParseResult {
        var builder = OllamaGraphBuilder(detector: detector, root: root)
        guard root.isAuthorizedOllama else {
            return builder.result(outcome: .corruptMetadata, diagnostic: .unauthorizedRoot)
        }
        guard !(await cancellation.isCancellationRequested()) else {
            return builder.result(outcome: .cancelled, diagnostic: .cancelled)
        }

        let rootEvidence = await port.rootEvidence(for: root)
        builder.environmentEvidence = rootEvidence.environmentEvidence
        guard rootEvidence.rootID == root.identity.rootID else {
            return builder.result(outcome: .corruptMetadata, diagnostic: .rootChanged)
        }
        if let fault = rootEvidence.fault { return builder.result(for: fault) }

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
            case .fault(let diagnostic):
                return builder.result(outcome: outcome(for: diagnostic), diagnostic: diagnostic)
            case .entry(let entry):
                entriesRead += 1
                cursor = .init(position: UInt(entriesRead))
                guard !(await cancellation.isCancellationRequested()) else {
                    return builder.result(outcome: .cancelled, diagnostic: .cancelled)
                }
                guard entry.locator.components.count <= limits.maximumDepth else {
                    return builder.result(outcome: .unsupportedLayout, diagnostic: .depthLimitExceeded)
                }
                guard sameVolume(entry.volume, rootEvidence.volume) else {
                    return builder.result(outcome: .unsupportedLayout, diagnostic: .crossVolumeLink)
                }
                guard case .observed(let bytes) = entry.size.logicalBytes, bytes >= 0 else {
                    return builder.result(outcome: .corruptMetadata, diagnostic: .invalidSize)
                }
                let nextBytes = observedBytes.addingReportingOverflow(bytes)
                guard !nextBytes.overflow, nextBytes.partialValue <= limits.maximumObservedBytes else {
                    return builder.result(outcome: .corruptMetadata, diagnostic: .observedByteLimitExceeded)
                }
                observedBytes = nextBytes.partialValue
                if let terminal = await handle(entry, rootEvidence: rootEvidence, builder: &builder) {
                    return terminal
                }
            }
        }
    }

    private func handle(
        _ entry: ModelStoreEntryEvidence,
        rootEvidence: ModelStoreRootEvidence,
        builder: inout OllamaGraphBuilder
    ) async -> ModelStoreParseResult? {
        let components = entry.locator.components
        if components.first == ".locks" { return nil }
        guard entry.topology == .ordinary else {
            return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
        }
        if entry.kind == .symbolicLink {
            return builder.result(outcome: .unsupportedLayout, diagnostic: .escapingLink)
        }
        if entry.kind == .directory {
            guard components == contract.manifestsRoot.components || components == contract.blobsRoot.components
                || components.starts(with: contract.manifestsRoot.components)
            else {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
            }
            return nil
        }

        if isBlob(components) {
            guard case .observed = entry.fileIdentity,
                  let blobID = blobID(for: components[1])
            else {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
            }
            guard !(await cancellation.isCancellationRequested()) else {
                return builder.result(outcome: .cancelled, diagnostic: .cancelled)
            }
            guard builder.recordBlobEvidence(
                blobID: blobID,
                identity: entry.fileIdentity,
                logicalBytes: entry.size.logicalBytes,
                limit: limits.maximumGraphNodes
            ) else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .invalidSize)
            }
            return nil
        }

        guard entry.kind == .regularFile,
              isManifest(components),
              case .observed = entry.fileIdentity,
              case .observed(let byteCount) = entry.size.logicalBytes,
              byteCount <= limits.maximumRefBytes
        else {
            return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
        }
        guard !(await cancellation.isCancellationRequested()) else {
            return builder.result(outcome: .cancelled, diagnostic: .cancelled)
        }
        let manifestResult = await port.readOllamaManifest(
            in: builder.root,
            at: entry.locator,
            expectedIdentity: entry.fileIdentity,
            maximumBytes: limits.maximumRefBytes
        )
        guard !(await cancellation.isCancellationRequested()) else {
            return builder.result(outcome: .cancelled, diagnostic: .cancelled)
        }
        let manifest: OllamaManifestObservation
        switch manifestResult {
        case .success(let observed):
            manifest = observed
        case .failure(.oversized):
            return builder.result(outcome: .corruptMetadata, diagnostic: .oversizedRef)
        case .failure(.rootChanged):
            return builder.result(outcome: .corruptMetadata, diagnostic: .rootChanged)
        case .failure(.volumeChanged):
            return builder.result(outcome: .corruptMetadata, diagnostic: .volumeChanged)
        case .failure(.missingEntry), .failure(.denied):
            return builder.result(outcome: .corruptMetadata, diagnostic: .corruptRef)
        }
        guard manifest.schemaVersion == contract.schemaVersion,
              manifest.mediaType == contract.manifestMediaType,
              contract.accepts(config: manifest.config, layers: manifest.layers),
              manifest.layers.count < limits.maximumGraphNodes
        else {
            return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
        }

        let repositoryID = components.dropFirst().dropLast().joined(separator: "/")
        guard let tag = components.last, !repositoryID.isEmpty, isNameComponent(tag) else {
            return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
        }
        let manifestID = "manifest:\(repositoryID):\(tag)"
        let descriptorLayers = [manifest.config] + manifest.layers
        guard builder.canAddManifest(
            repositoryID: repositoryID,
            tag: tag,
            manifestID: manifestID,
            layerCount: descriptorLayers.count,
            limit: limits.maximumGraphNodes
        ) else {
            return builder.result(outcome: .corruptMetadata, diagnostic: .graphLimitExceeded)
        }
        guard !(await cancellation.isCancellationRequested()) else {
            return builder.result(outcome: .cancelled, diagnostic: .cancelled)
        }
        builder.addRepository(repositoryID)
        guard !(await cancellation.isCancellationRequested()) else {
            return builder.result(outcome: .cancelled, diagnostic: .cancelled)
        }
        builder.addRef(repositoryID: repositoryID, name: tag, target: manifestID)
        guard !(await cancellation.isCancellationRequested()) else {
            return builder.result(outcome: .cancelled, diagnostic: .cancelled)
        }
        builder.addSnapshot(repositoryID: repositoryID, snapshotID: manifestID)

        for (index, layer) in descriptorLayers.enumerated() {
            guard !(await cancellation.isCancellationRequested()) else {
                return builder.result(outcome: .cancelled, diagnostic: .cancelled)
            }
            guard let blobID = canonicalBlobID(for: layer.digest), layer.size >= 0 else {
                return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
            }
            guard builder.edgeCount < limits.maximumGraphEdges else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .graphLimitExceeded)
            }
            guard builder.recordExpectedLayer(
                repositoryID: repositoryID,
                blobID: blobID,
                expectedSize: layer.size,
                limit: limits.maximumGraphNodes
            ) else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .invalidSize)
            }
            guard builder.addEdge(
                .init(
                    repositoryID: repositoryID,
                    snapshotID: manifestID,
                    snapshotFileName: index == 0 ? "config" : "layer-\(index - 1)",
                    blobID: blobID
                ),
                limit: limits.maximumGraphEdges
            ) else {
                return builder.result(outcome: .corruptMetadata, diagnostic: .graphLimitExceeded)
            }
        }
        return nil
    }

    private func isManifest(_ components: [String]) -> Bool {
        components.count == contract.manifestPathComponentCount
            && components.starts(with: contract.manifestsRoot.components)
            && components.dropFirst().allSatisfy(isNameComponent)
    }

    private func isBlob(_ components: [String]) -> Bool {
        components.count == 2
            && components.first == contract.blobsRoot.components.first
    }

    private func blobID(for fileName: String) -> String? {
        guard fileName.hasPrefix("sha256-") else { return nil }
        return canonicalBlobID(for: fileName)
    }

    private func canonicalBlobID(for digest: String) -> String? {
        contract.normalizedDigest(digest).map { "sha256:\($0)" }
    }

    private func isNameComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component.count <= 255
            && component.unicodeScalars.allSatisfy { scalar in
                scalar.value != 47 && scalar.value != 0 && scalar.value >= 32
            }
    }

    private func sameVolume(_ evidence: EvidenceValue<VolumeID>, _ volume: VolumeID) -> Bool {
        if case .observed(let observed) = evidence { return observed == volume }
        return false
    }

    private func outcome(for diagnostic: ModelStoreDiagnosticCode) -> ScanOutcome {
        switch diagnostic {
        case .permissionDenied: .permissionDenied
        case .cancelled: .cancelled
        case .unavailableVolume, .unknownLayout, .escapingLink, .cyclicLink,
             .crossVolumeLink, .unavailableTargetMetadata, .depthLimitExceeded:
            .unsupportedLayout
        default: .corruptMetadata
        }
    }
}

private extension ModelStoreRoot {
    var isAuthorizedOllama: Bool {
        switch authority {
        case .documentedDefault(.ollamaModels):
            return identity.rootID == ModelStoreRoot.ollamaDefaultRootID && layout == .ollamaV1
        case .explicitSelection(let selection):
            return selection.isValidated && layout == .ollamaV1
        default:
            return false
        }
    }
}

private struct OllamaGraphBuilder {
    let detector: ModelStoreDetector
    let root: ModelStoreRoot
    var repositories: [ModelStoreRepository] = []
    var refs: [ModelStoreRef] = []
    var snapshots: [ModelStoreSnapshot] = []
    var blobs: [ModelStoreBlob] = []
    var edges: [ModelStoreSnapshotBlobEdge] = []
    var diagnostics: [ModelStoreDiagnostic] = []
    var environmentEvidence: [ModelStoreEnvironmentEvidence] = []
    var blobEvidence: [String: OllamaBlobEvidence] = [:]
    var requiredBlobs: [OllamaBlobRequirement] = []

    var edgeCount: Int { edges.count }

    mutating func addRepository(_ repositoryID: String) {
        let value = ModelStoreRepository(identity: .init(repositoryID: repositoryID))
        if !repositories.contains(value) { repositories.append(value) }
    }

    mutating func addRef(repositoryID: String, name: String, target: String) {
        addRepository(repositoryID)
        let value = ModelStoreRef(repositoryID: repositoryID, name: name, targetSnapshot: target)
        if !refs.contains(value) { refs.append(value) }
    }

    mutating func addSnapshot(repositoryID: String, snapshotID: String) {
        addRepository(repositoryID)
        let value = ModelStoreSnapshot(repositoryID: repositoryID, snapshotID: snapshotID)
        if !snapshots.contains(value) { snapshots.append(value) }
    }

    mutating func addEdge(_ edge: ModelStoreSnapshotBlobEdge, limit: Int) -> Bool {
        if edges.contains(edge) { return true }
        guard let count = checkedSum([edges.count, 1]), count <= limit else { return false }
        edges.append(edge)
        return true
    }

    mutating func recordBlobEvidence(
        blobID: String,
        identity: EvidenceValue<FileIdentityEvidence>,
        logicalBytes: EvidenceValue<Int>,
        limit: Int
    ) -> Bool {
        let candidate = OllamaBlobEvidence(identity: identity, logicalBytes: logicalBytes)
        if let existing = blobEvidence[blobID] { return existing == candidate }
        guard let count = checkedSum([blobEvidence.count, 1]), count <= limit else { return false }
        blobEvidence[blobID] = candidate
        return true
    }

    mutating func recordExpectedLayer(
        repositoryID: String,
        blobID: String,
        expectedSize: Int,
        limit: Int
    ) -> Bool {
        let candidate = OllamaBlobRequirement(
            repositoryID: repositoryID,
            blobID: blobID,
            expectedSize: expectedSize
        )
        if let existing = requiredBlobs.first(where: {
            $0.repositoryID == repositoryID && $0.blobID == blobID
        }) {
            return existing.expectedSize == expectedSize
        }
        guard let count = checkedSum([requiredBlobs.count, 1]), count <= limit else { return false }
        requiredBlobs.append(candidate)
        return true
    }

    func canAddManifest(
        repositoryID: String,
        tag: String,
        manifestID: String,
        layerCount: Int,
        limit: Int
    ) -> Bool {
        let repository = ModelStoreRepository(identity: .init(repositoryID: repositoryID))
        let ref = ModelStoreRef(repositoryID: repositoryID, name: tag, targetSnapshot: manifestID)
        let snapshot = ModelStoreSnapshot(repositoryID: repositoryID, snapshotID: manifestID)
        guard let additionalNodes = checkedSum([
            repositories.contains(repository) ? 0 : 1,
            refs.contains(ref) ? 0 : 1,
            snapshots.contains(snapshot) ? 0 : 1,
            layerCount,
        ]), let currentNodes = checkedSum([
            1,
            repositories.count,
            refs.count,
            snapshots.count,
            requiredBlobs.count,
        ]), let totalNodes = checkedSum([currentNodes, additionalNodes]) else {
            return false
        }
        return totalNodes <= limit
    }

    mutating func result(for fault: ModelStoreRootFault) -> ModelStoreParseResult {
        switch fault {
        case .unavailableVolume: result(outcome: .unsupportedLayout, diagnostic: .unavailableVolume)
        case .rootChanged: result(outcome: .corruptMetadata, diagnostic: .rootChanged)
        case .volumeChanged: result(outcome: .corruptMetadata, diagnostic: .volumeChanged)
        case .permissionDenied: result(outcome: .permissionDenied, diagnostic: .permissionDenied)
        }
    }

    mutating func result(outcome: ScanOutcome, diagnostic: ModelStoreDiagnosticCode) -> ModelStoreParseResult {
        diagnostics.append(.init(code: diagnostic))
        return makeResult(outcome: outcome)
    }

    mutating func finalResult() -> ModelStoreParseResult {
        guard !refs.isEmpty, !requiredBlobs.isEmpty else {
            return result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
        }
        var materialized: [ModelStoreBlob] = []
        for requirement in requiredBlobs {
            guard let evidence = blobEvidence[requirement.blobID],
                  evidence.logicalBytes == .observed(requirement.expectedSize)
            else {
                return result(outcome: .corruptMetadata, diagnostic: .missingBlob)
            }
            guard case .observed = evidence.identity else {
                return result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
            }
            let blob = ModelStoreBlob(
                identity: .init(
                    repositoryID: requirement.repositoryID,
                    blobID: requirement.blobID,
                    fileIdentity: evidence.identity
                ),
                logicalBytes: evidence.logicalBytes
            )
            if let existing = materialized.first(where: {
                $0.identity.repositoryID == blob.identity.repositoryID
                    && $0.identity.blobID == blob.identity.blobID
            }), existing != blob {
                return result(outcome: .corruptMetadata, diagnostic: .invalidSize)
            }
            if !materialized.contains(blob) { materialized.append(blob) }
        }
        guard edges.allSatisfy({ edge in
            materialized.contains {
                $0.identity.repositoryID == edge.repositoryID && $0.identity.blobID == edge.blobID
            }
        }) else { return result(outcome: .corruptMetadata, diagnostic: .missingBlob) }
        blobs = materialized
        return makeResult(outcome: .complete)
    }

    private func makeResult(outcome: ScanOutcome) -> ModelStoreParseResult {
        let publishRelationships = outcome == .complete
        return .init(
            outcome: outcome,
            graph: .init(
                detector: detector,
                roots: [root],
                repositories: publishRelationships ? repositories : [],
                refs: publishRelationships ? refs : [],
                snapshots: publishRelationships ? snapshots : [],
                blobs: publishRelationships ? blobs : [],
                incompleteBlobs: [],
                snapshotBlobEdges: publishRelationships ? edges : [],
                diagnostics: diagnostics,
                environmentEvidence: environmentEvidence,
                protection: .inspectOnly(reason: protectionReason)
            )
        )
    }

    private var protectionReason: ModelStoreProtectionReason {
        switch diagnostics.last?.code {
        case nil: .inventoryOnly
        case .permissionDenied: .denied
        case .unavailableVolume: .unavailableVolume
        case .rootChanged, .volumeChanged: .changedStore
        case .cancelled: .cancelled
        case .missingBlob: .missingBlob
        case .escapingLink, .crossVolumeLink, .unavailableTargetMetadata, .depthLimitExceeded: .boundaryViolation
        case .unauthorizedRoot: .unauthorizedRoot
        case .unknownLayout: .unknownLayout
        case .corruptRef, .oversizedRef: .corruptRef
        case .danglingLink, .cyclicLink, .invalidTargetKind: .invalidLink
        case .invalidSize, .entryLimitExceeded, .graphLimitExceeded, .observedByteLimitExceeded: .bounded
        }
    }
}

private func checkedSum(_ values: [Int]) -> Int? {
    var total = 0
    for value in values {
        guard value >= 0 else { return nil }
        let next = total.addingReportingOverflow(value)
        guard !next.overflow else { return nil }
        total = next.partialValue
    }
    return total
}

private struct OllamaBlobEvidence: Equatable {
    let identity: EvidenceValue<FileIdentityEvidence>
    let logicalBytes: EvidenceValue<Int>
}

private struct OllamaBlobRequirement: Equatable {
    let repositoryID: String
    let blobID: String
    let expectedSize: Int
}
