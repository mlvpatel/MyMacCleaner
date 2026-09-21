public enum PresentationMode: String, CaseIterable, Equatable, Sendable {
    case guided
    case standard
    case technical
}

public enum AdaptiveExperienceProjectionError: Error, Equatable, Sendable {
    case duplicateEvidenceIdentity
    case overflowingByteTotal
    case malformedSource
}

public enum AdaptiveByteTotal: Equatable, Sendable {
    case observed(Int64)
    case unavailable
    case overflowing
}

public enum AdaptiveBoundaryFlag: Equatable, Sendable {
    case observedTrue
    case observedFalse
    case unknown
    case unavailable
}

public struct AdaptiveBoundarySummary: Equatable, Sendable {
    public let identity: String
    public let symlink: AdaptiveBoundaryFlag
    public let alias: AdaptiveBoundaryFlag
    public let package: AdaptiveBoundaryFlag
    public let mount: AdaptiveBoundaryFlag
    public let protectedRoot: AdaptiveBoundaryFlag
    public let homeBoundary: AdaptiveBoundaryFlag
    public let externalVolume: AdaptiveBoundaryFlag
}

public enum AdaptiveExecutionOutcomeKind: Equatable, Sendable {
    case moved
    case skippedStale(TrashStaleReason)
    case failed(TrashExecutionFailure)
    case cancelled
}

public enum AdaptivePermissionGap: String, Equatable, Sendable {
    case fullDiskAccess
    case userLibrary
}

public enum AdaptiveCardKind: String, Equatable, Sendable {
    case generalMac
    case modelInventory
    case memory
    case developerCapability
    case permission
    case history
}

public enum AdaptiveDisclosureDepth: Int, Equatable, Sendable {
    case guided = 1
    case standard = 2
    case technical = 3
}

public struct AdaptiveDeveloperInventoryFact: Equatable, Sendable {
    public let opaqueID: String
    public let presenceKey: String
    public let protectionKey: String

    public init(opaqueID: String, presenceKey: String, protectionKey: String) throws {
        guard !opaqueID.isEmpty, !presenceKey.isEmpty, !protectionKey.isEmpty else {
            throw AdaptiveExperienceProjectionError.malformedSource
        }
        self.opaqueID = opaqueID
        self.presenceKey = presenceKey
        self.protectionKey = protectionKey
    }
}

public struct AdaptiveExperienceSource: Equatable, Sendable {
    public let scanState: ProjectedScanState
    public let findings: [ProjectedFinding]
    public let evaluations: [PolicyEvaluation]
    public let reviewPlan: ReviewPlan?
    public let approvalValidity: ApprovalValidity
    public let executionState: TrashRunState?
    public let executionOutcomes: [AdaptiveExecutionOutcomeKind]
    public let receipts: [RedactedReceiptSummary]
    public let memory: MemoryCoachSnapshot?
    public let capabilities: [CapabilityCard]
    public let permissionGaps: [AdaptivePermissionGap]
    public let developerInventory: [AdaptiveDeveloperInventoryFact]

    public init(
        scanState: ProjectedScanState,
        findings: [ProjectedFinding],
        evaluations: [PolicyEvaluation],
        reviewPlan: ReviewPlan?,
        approvalValidity: ApprovalValidity,
        executionState: TrashRunState?,
        executionOutcomes: [AdaptiveExecutionOutcomeKind],
        receipts: [RedactedReceiptSummary],
        memory: MemoryCoachSnapshot?,
        capabilities: [CapabilityCard],
        permissionGaps: [AdaptivePermissionGap],
        developerInventory: [AdaptiveDeveloperInventoryFact]
    ) {
        self.scanState = scanState
        self.findings = findings
        self.evaluations = evaluations
        self.reviewPlan = reviewPlan
        self.approvalValidity = approvalValidity
        self.executionState = executionState
        self.executionOutcomes = executionOutcomes
        self.receipts = receipts
        self.memory = memory
        self.capabilities = capabilities
        self.permissionGaps = permissionGaps
        self.developerInventory = developerInventory
    }
}

public struct AdaptiveExperienceAuthority: Equatable, Sendable {
    public let scanState: ProjectedScanState
    public let evidenceIdentities: [String]
    public let boundarySummaries: [AdaptiveBoundarySummary]
    public let dispositions: [PolicyDisposition]
    public let eligibilities: [PolicyEligibility]
    public let semanticOwners: [PolicySemanticOwner]
    public let rationales: [PolicyRationale]
    public let recoveryPaths: [PolicyRecoveryPath]
    public let confidences: [EvidenceConfidence]
    public let expectedConservativeBytes: AdaptiveByteTotal
    public let planDigestHex: String?
    public let planExpiresAtNanoseconds: Int64?
    public let approvalValidity: ApprovalValidity
    public let executionState: TrashRunState?
    public let executionOutcomes: [AdaptiveExecutionOutcomeKind]
    public let receiptIDs: [String]
    public let receiptStatusMarkers: [String]
    public let receiptRecoveryMarkers: [String]
    public let memoryOutcome: MemorySnapshotOutcome?
    public let memoryUnavailable: [String]
    public let capabilityAuthorities: [CapabilityAuthority]
    public let capabilityOperations: [ConditionalOperationDescription]
    public let permissionGaps: [AdaptivePermissionGap]
    public let cardKinds: [AdaptiveCardKind]
}

public struct AdaptiveExperienceProjection: Equatable, Sendable {
    public let mode: PresentationMode
    public let authority: AdaptiveExperienceAuthority
    public let explanationKeys: [String]
    public let disclosureDepth: AdaptiveDisclosureDepth
    public let groupingKeys: [String]
    public let detailRowKeys: [String]
}

public struct AdaptiveExperienceProjector: Sendable {
    public init() {}

    public func project(
        _ source: AdaptiveExperienceSource,
        mode: PresentationMode
    ) throws -> AdaptiveExperienceProjection {
        let identities = try AdaptiveExperienceIdentity.uniqueSorted(from: source.findings)
        let bytes = try AdaptiveExperienceBytes.total(from: source.evaluations)
        let cards = AdaptiveExperienceCards.membership(from: source)
        let authority = AdaptiveExperienceAuthority(
            scanState: source.scanState,
            evidenceIdentities: identities,
            boundarySummaries: source.findings
                .sorted { AdaptiveExperienceIdentity.key(from: $0) < AdaptiveExperienceIdentity.key(from: $1) }
                .map(AdaptiveExperienceIdentity.boundary(from:)),
            dispositions: source.evaluations.map(\.disposition),
            eligibilities: source.evaluations.map(\.eligibility),
            semanticOwners: source.evaluations.map(\.semanticOwner),
            rationales: source.evaluations.map(\.rationale),
            recoveryPaths: source.evaluations.map(\.recoveryPath),
            confidences: source.evaluations.map(\.confidence),
            expectedConservativeBytes: bytes,
            planDigestHex: source.reviewPlan.map { AdaptiveExperienceIdentity.hex($0.digest.bytes) },
            planExpiresAtNanoseconds: source.reviewPlan.map(\.expiresAt.unixNanoseconds),
            approvalValidity: source.approvalValidity,
            executionState: source.executionState,
            executionOutcomes: source.executionOutcomes,
            receiptIDs: source.receipts.map(\.id.value).sorted(),
            receiptStatusMarkers: source.receipts.map(\.statusMarker),
            receiptRecoveryMarkers: source.receipts.map(\.recoveryMarker),
            memoryOutcome: source.memory?.outcome,
            memoryUnavailable: AdaptiveExperienceMemory.unavailableMarkers(from: source.memory),
            capabilityAuthorities: source.capabilities.map(\.authority),
            capabilityOperations: source.capabilities.map(\.conditionalOperation),
            permissionGaps: source.permissionGaps,
            cardKinds: cards
        )
        let formatting = AdaptiveExperienceFormatting.table(mode: mode, authority: authority)
        return AdaptiveExperienceProjection(
            mode: mode,
            authority: authority,
            explanationKeys: formatting.explanationKeys,
            disclosureDepth: formatting.disclosureDepth,
            groupingKeys: formatting.groupingKeys,
            detailRowKeys: formatting.detailRowKeys
        )
    }
}

public protocol AdaptiveClocking: Sendable {
    func now() async -> ClockReading
}

public protocol AdaptiveCancelling: Sendable {
    func isCancellationRequested() async -> Bool
}

public struct AdaptiveScanCollection: Equatable, Sendable {
    public let scanState: ProjectedScanState
    public let findings: [ProjectedFinding]
    public let generalMacFindings: [GeneralMacFinding]
    public let evaluations: [PolicyEvaluation]
}

public actor AdaptiveScanSession {
    private let coordinator: ScanCoordinator

    public init(
        fileSystem: any FileSystemPort,
        clock: any AdaptiveClocking,
        cancellation: any AdaptiveCancelling
    ) throws {
        coordinator = try ScanCoordinator(
            dependencies: ScanDependencies(
                fileSystem: fileSystem,
                clock: AdaptiveClockPortAdapter(clock),
                cancellation: AdaptiveCancellationPortAdapter(cancellation),
                diagnostics: AdaptiveSilentDiagnostics(),
                metrics: AdaptiveSilentMetrics()
            ),
            shippedDetector: GeneralMacRegistryDetector(catalog: .current)
        )
    }

    public func collect(request: ScanRequest) async -> AdaptiveScanCollection {
        var findings: [Finding] = []
        var terminalState: ProjectedScanState = .complete
        while true {
            let step = await coordinator.nextBatch(for: request)
            switch step {
            case let .batch(batch):
                findings.append(contentsOf: batch.findings)
                if let outcome = batch.terminalOutcome {
                    terminalState = ProjectedScanState(outcome)
                    return classify(findings: findings, state: terminalState)
                }
            case let .terminal(outcome):
                terminalState = ProjectedScanState(outcome)
                return classify(findings: findings, state: terminalState)
            }
        }
    }

    private func classify(findings: [Finding], state: ProjectedScanState) -> AdaptiveScanCollection {
        let projected = findings
            .map(ProjectedFinding.init)
            .sorted { AdaptiveExperienceIdentity.key(from: $0) < AdaptiveExperienceIdentity.key(from: $1) }
        let catalog = GeneralMacScopeCatalog.current
        let evaluator = PolicyEvaluator()
        var general: [GeneralMacFinding] = []
        var evaluations: [PolicyEvaluation] = []
        for finding in findings {
            let kind: GeneralMacRootKind
            do {
                kind = try catalog.rootKind(for: finding.declaredRoot.id)
            } catch {
                continue
            }
            let request: ScanRequest
            do {
                request = try catalog.scanRequest(for: [kind])
            } catch {
                continue
            }
            let observation = FileObservation(
                rootID: finding.declaredRoot.id,
                locator: finding.locator,
                resourceIdentity: finding.resourceIdentity,
                sizes: finding.sizes,
                modification: finding.modification,
                fileKind: finding.fileKind,
                volume: finding.volume,
                linkCount: finding.linkCount,
                boundaries: finding.boundaries
            )
            switch GeneralMacEvidenceDetector(scope: kind, catalog: catalog).makeFinding(
                from: observation,
                request: request,
                clockReading: ClockReading(
                    observationInstant: finding.observationInstant,
                    wallClockInstant: .init(unixNanoseconds: 1)
                )
            ) {
            case let .success(maybeFinding):
                if let macFinding = maybeFinding {
                    general.append(macFinding)
                    evaluations.append(evaluator.evaluate(macFinding))
                }
            case .failure:
                continue
            }
        }
        return AdaptiveScanCollection(
            scanState: state,
            findings: projected,
            generalMacFindings: general,
            evaluations: evaluations
        )
    }
}

enum AdaptiveExperienceIdentity {
    static func key(from finding: ProjectedFinding) -> String {
        hex(utf8Bytes(from: finding))
    }

    static func uniqueSorted(from findings: [ProjectedFinding]) throws -> [String] {
        var seen: [String: Int] = [:]
        var ordered: [String] = []
        for finding in findings {
            let identity = key(from: finding)
            if identity.isEmpty {
                throw AdaptiveExperienceProjectionError.malformedSource
            }
            if seen[identity] != nil {
                throw AdaptiveExperienceProjectionError.duplicateEvidenceIdentity
            }
            seen[identity] = 1
            ordered.append(identity)
        }
        return ordered.sorted()
    }

    static func boundary(from finding: ProjectedFinding) -> AdaptiveBoundarySummary {
        AdaptiveBoundarySummary(
            identity: key(from: finding),
            symlink: flag(finding.boundaries.symlink),
            alias: flag(finding.boundaries.alias),
            package: flag(finding.boundaries.package),
            mount: flag(finding.boundaries.mount),
            protectedRoot: flag(finding.boundaries.protectedRoot),
            homeBoundary: flag(finding.boundaries.homeBoundary),
            externalVolume: flag(finding.boundaries.externalVolume)
        )
    }

    static func utf8Bytes(from finding: ProjectedFinding) -> [UInt8] {
        let fields = [finding.detectorID.value, finding.declaredRootID.value] + finding.locator.components
        return fields.flatMap { field in
            let bytes = Array(field.utf8)
            return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
        }
    }

    static func hex(_ bytes: [UInt8]) -> String {
        let nibbles: [Character] = [
            "0", "1", "2", "3", "4", "5", "6", "7",
            "8", "9", "a", "b", "c", "d", "e", "f"
        ]
        var characters: [Character] = []
        characters.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            characters.append(nibbles[Int(byte >> 4)])
            characters.append(nibbles[Int(byte & 0x0F)])
        }
        return String(characters)
    }

    private static func flag(_ value: EvidenceValue<Bool>) -> AdaptiveBoundaryFlag {
        switch value {
        case .observed(true): return .observedTrue
        case .observed(false): return .observedFalse
        case .unknown: return .unknown
        case .unavailable: return .unavailable
        }
    }
}

enum AdaptiveExperienceBytes {
    static func total(from evaluations: [PolicyEvaluation]) throws -> AdaptiveByteTotal {
        var observedAny = false
        var sawUnavailable = false
        var total: Int64 = 0
        for evaluation in evaluations {
            if evaluation.confidence == .unavailable {
                sawUnavailable = true
                continue
            }
            guard let candidate = evaluation.candidate else { continue }
            let added = total.addingReportingOverflow(candidate.rankFactors.conservativeBytes)
            if added.overflow {
                throw AdaptiveExperienceProjectionError.overflowingByteTotal
            }
            total = added.partialValue
            observedAny = true
        }
        if !observedAny {
            if sawUnavailable || evaluations.contains(where: { $0.rationale == .incompleteEvidence }) {
                return .unavailable
            }
            return .observed(0)
        }
        return .observed(total)
    }
}

enum AdaptiveExperienceCards {
    static func membership(from source: AdaptiveExperienceSource) -> [AdaptiveCardKind] {
        var kinds: [AdaptiveCardKind] = []
        if !source.findings.isEmpty || source.evaluations.contains(where: { $0.semanticOwner != .modelStore }) {
            kinds.append(.generalMac)
        }
        if source.capabilities.contains(where: { $0.authority == .inventoryOnly })
            || source.evaluations.contains(where: { $0.semanticOwner == .modelStore }) {
            kinds.append(.modelInventory)
        }
        if source.memory != nil {
            kinds.append(.memory)
        }
        if !source.developerInventory.isEmpty {
            kinds.append(.developerCapability)
        }
        if !source.permissionGaps.isEmpty {
            kinds.append(.permission)
        }
        if !source.receipts.isEmpty {
            kinds.append(.history)
        }
        return kinds
    }
}

enum AdaptiveExperienceMemory {
    static func unavailableMarkers(from snapshot: MemoryCoachSnapshot?) -> [String] {
        guard let snapshot else { return [] }
        var markers: [String] = []
        switch snapshot.outcome {
        case .unavailable:
            markers.append("memory.outcome.unavailable")
        case .partial:
            markers.append("memory.outcome.partial")
        case .cancelled:
            markers.append("memory.outcome.cancelled")
        case .complete:
            break
        }
        switch snapshot.pressure {
        case .unavailableNoFreshEvent:
            markers.append("memory.pressure.noFreshEvent")
        case .stale:
            markers.append("memory.pressure.stale")
        case .observed:
            break
        }
        for issue in snapshot.issues {
            markers.append(issueMarker(issue))
        }
        return markers
    }

    private static func issueMarker(_ issue: MemorySnapshotIssue) -> String {
        switch issue {
        case .timing(let reason): return "memory.timing.\(reasonMarker(reason))"
        case .pressure(let reason): return "memory.pressure.\(reasonMarker(reason))"
        case .physicalMemory(let reason): return "memory.physical.\(reasonMarker(reason))"
        case .vm(let reason): return "memory.vm.\(reasonMarker(reason))"
        case .swap(let reason): return "memory.swap.\(reasonMarker(reason))"
        case .workload(let reason): return "memory.workload.\(reasonMarker(reason))"
        }
    }

    private static func reasonMarker(_ reason: MemoryObservationUnavailable) -> String {
        switch reason {
        case .noFreshEvent: return "noFreshEvent"
        case .stale: return "stale"
        case .unavailable: return "unavailable"
        case .malformedSource: return "malformedSource"
        case .overflow: return "overflow"
        case .denied: return "denied"
        case .exited: return "exited"
        case .shortRead: return "shortRead"
        case .identityChanged: return "identityChanged"
        case .deadlineExceeded: return "deadlineExceeded"
        }
    }
}

enum AdaptiveExperienceFormatting {
    struct Table: Equatable {
        let explanationKeys: [String]
        let disclosureDepth: AdaptiveDisclosureDepth
        let groupingKeys: [String]
        let detailRowKeys: [String]
    }

    static func table(mode: PresentationMode, authority: AdaptiveExperienceAuthority) -> Table {
        switch mode {
        case .guided:
            return Table(
                explanationKeys: [
                    "adaptive.explain.guided.summary",
                    scanKey(authority.scanState, mode: .guided),
                    "adaptive.explain.guided.recovery"
                ],
                disclosureDepth: .guided,
                groupingKeys: ["adaptive.group.guided.cards"],
                detailRowKeys: ["adaptive.detail.guided.what", "adaptive.detail.guided.safeNext"]
            )
        case .standard:
            return Table(
                explanationKeys: [
                    "adaptive.explain.standard.summary",
                    scanKey(authority.scanState, mode: .standard),
                    "adaptive.explain.standard.policy",
                    "adaptive.explain.standard.recovery"
                ],
                disclosureDepth: .standard,
                groupingKeys: ["adaptive.group.standard.opportunities", "adaptive.group.standard.protected"],
                detailRowKeys: [
                    "adaptive.detail.standard.provenance",
                    "adaptive.detail.standard.bytes",
                    "adaptive.detail.standard.recovery"
                ]
            )
        case .technical:
            return Table(
                explanationKeys: [
                    "adaptive.explain.technical.summary",
                    scanKey(authority.scanState, mode: .technical),
                    "adaptive.explain.technical.policy",
                    "adaptive.explain.technical.plan",
                    "adaptive.explain.technical.receipt"
                ],
                disclosureDepth: .technical,
                groupingKeys: [
                    "adaptive.group.technical.evidence",
                    "adaptive.group.technical.policy",
                    "adaptive.group.technical.history"
                ],
                detailRowKeys: [
                    "adaptive.detail.technical.identity",
                    "adaptive.detail.technical.boundary",
                    "adaptive.detail.technical.eligibility",
                    "adaptive.detail.technical.digest"
                ]
            )
        }
    }

    private static func scanKey(_ state: ProjectedScanState, mode: PresentationMode) -> String {
        let prefix: String
        switch mode {
        case .guided: prefix = "adaptive.explain.guided.scan"
        case .standard: prefix = "adaptive.explain.standard.scan"
        case .technical: prefix = "adaptive.explain.technical.scan"
        }
        switch state {
        case .complete: return "\(prefix).complete"
        case .continuing: return "\(prefix).continuing"
        case .partial: return "\(prefix).partial"
        case .permissionDenied: return "\(prefix).permissionDenied"
        case .cancelled: return "\(prefix).cancelled"
        case .corruptMetadata: return "\(prefix).corruptMetadata"
        case .unsupportedLayout: return "\(prefix).unsupportedLayout"
        }
    }
}

private struct AdaptiveClockPortAdapter: ClockPort {
    let clock: any AdaptiveClocking

    init(_ clock: any AdaptiveClocking) {
        self.clock = clock
    }

    func now() async -> ClockReading {
        await clock.now()
    }
}

private struct AdaptiveCancellationPortAdapter: CancellationPort {
    let cancellation: any AdaptiveCancelling

    init(_ cancellation: any AdaptiveCancelling) {
        self.cancellation = cancellation
    }

    func isCancellationRequested() async -> Bool {
        await cancellation.isCancellationRequested()
    }
}

private struct AdaptiveSilentDiagnostics: DiagnosticPort {
    func record(_ event: ScanDiagnosticEvent) async {}
}

private struct AdaptiveSilentMetrics: MetricPort {
    func record(_ event: ScanMetricEvent) async {}
}
