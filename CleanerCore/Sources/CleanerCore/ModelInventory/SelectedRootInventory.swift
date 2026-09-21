/// Generic metadata-only inventory for a root that the caller has already
/// validated as an explicit selection. A missing selection performs no port
/// calls and returns no inventory result.
public struct SelectedRootInventory: Sendable {
    public let detector: ModelStoreDetector
    public let limits: ModelStoreParserLimits
    private let port: any ModelStoreObservationPort
    private let cancellation: any ModelStoreCancellation

    public init(
        detector: ModelStoreDetector = .selectedRootV1,
        limits: ModelStoreParserLimits,
        port: any ModelStoreObservationPort,
        cancellation: any ModelStoreCancellation
    ) {
        self.detector = detector
        self.limits = limits
        self.port = port
        self.cancellation = cancellation
    }

    public func parse(
        selectedRoot: ModelStoreRoot?,
        association: ModelAssociationEvidence = .unknown
    ) async -> ModelStoreParseResult? {
        guard let root = selectedRoot else { return nil }
        var builder = SelectedRootGraphBuilder(detector: detector, root: root, association: association)
        guard root.isAuthorizedSelectedRoot else {
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
            switch await port.nextEntry(after: cursor, in: root) {
            case .complete:
                return builder.complete()
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
                guard entry.topology == .ordinary else {
                    return builder.result(outcome: .unsupportedLayout, diagnostic: .unknownLayout)
                }
                guard case .observed(let volume) = entry.volume, volume == rootEvidence.volume else {
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
                guard entry.kind != .symbolicLink else {
                    return builder.result(outcome: .unsupportedLayout, diagnostic: .escapingLink)
                }
                if entry.kind == .regularFile {
                    guard case .observed = entry.fileIdentity,
                          builder.incompleteBlobs.count < limits.maximumGraphNodes
                    else {
                        return builder.result(outcome: .unsupportedLayout, diagnostic: .unavailableTargetMetadata)
                    }
                    guard !(await cancellation.isCancellationRequested()) else {
                        return builder.result(outcome: .cancelled, diagnostic: .cancelled)
                    }
                    builder.addObservedFile(entry)
                }
            }
        }
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
    var isAuthorizedSelectedRoot: Bool {
        guard case .explicitSelection(let selection) = authority else { return false }
        return selection.isValidated && layout == .selectedRootV1
    }
}

private struct SelectedRootGraphBuilder {
    private static let repositoryID = "selected-root"

    let detector: ModelStoreDetector
    let root: ModelStoreRoot
    let association: ModelAssociationEvidence
    var incompleteBlobs: [ModelStoreBlob] = []
    var diagnostics: [ModelStoreDiagnostic] = []
    var environmentEvidence: [ModelStoreEnvironmentEvidence] = []

    mutating func addObservedFile(_ entry: ModelStoreEntryEvidence) {
        let blob = ModelStoreBlob(
            identity: .init(
                repositoryID: Self.repositoryID,
                blobID: entry.locator.components.joined(separator: "/"),
                fileIdentity: entry.fileIdentity
            ),
            logicalBytes: entry.size.logicalBytes
        )
        if !incompleteBlobs.contains(blob) { incompleteBlobs.append(blob) }
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

    func complete() -> ModelStoreParseResult { makeResult(outcome: .complete) }

    private func makeResult(outcome: ScanOutcome) -> ModelStoreParseResult {
        .init(
            outcome: outcome,
            graph: .init(
                detector: detector,
                roots: [root],
                repositories: [],
                refs: [],
                snapshots: [],
                blobs: [],
                incompleteBlobs: incompleteBlobs,
                snapshotBlobEdges: [],
                diagnostics: diagnostics,
                environmentEvidence: environmentEvidence,
                association: association,
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
        case .escapingLink, .crossVolumeLink, .unavailableTargetMetadata, .depthLimitExceeded: .boundaryViolation
        case .unauthorizedRoot: .unauthorizedRoot
        case .unknownLayout: .unknownLayout
        default: .bounded
        }
    }
}
