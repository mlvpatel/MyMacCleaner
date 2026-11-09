public protocol AdaptiveClocking: Sendable {
    func now() async -> ClockReading
}

public protocol AdaptiveCancelling: Sendable {
    func isCancellationRequested() async -> Bool
}

public struct AdaptiveScanCollection: Equatable, Sendable {
    public let scanState: ProjectedScanState
    public let findings: [ProjectedFinding]
    public let evaluations: [PolicyEvaluation]
}

public actor AdaptiveScanSession {
    private let coordinator: ScanCoordinator
    private let clock: any AdaptiveClocking
    private let processActivity: any ProcessActivityObserving
    private let catalog: GeneralMacScopeCatalog

    public init(
        fileSystem: any FileSystemPort,
        clock: any AdaptiveClocking,
        cancellation: any AdaptiveCancelling,
        processActivity: any ProcessActivityObserving = NoProcessActivity(),
        catalog: GeneralMacScopeCatalog = .current
    ) throws {
        self.clock = clock
        self.processActivity = processActivity
        self.catalog = catalog
        coordinator = try ScanCoordinator(
            dependencies: ScanDependencies(
                fileSystem: fileSystem,
                clock: AdaptiveClockPortAdapter(clock),
                cancellation: AdaptiveCancellationPortAdapter(cancellation),
                diagnostics: AdaptiveSilentDiagnostics(),
                metrics: AdaptiveSilentMetrics()
            ),
            shippedDetector: GeneralMacRegistryDetector(catalog: catalog)
        )
    }

    public func collect(request: ScanRequest) async -> AdaptiveScanCollection {
        // Ages are measured from scan start: never later than any observation, so this can
        // only understate how long a file has been inactive.
        let scanStart = await clock.now().wallClockInstant
        var findings: [Finding] = []
        var terminalState: ProjectedScanState = .complete
        while true {
            let step = await coordinator.nextBatch(for: request)
            switch step {
            case let .batch(batch):
                findings.append(contentsOf: batch.findings)
                if let outcome = batch.terminalOutcome {
                    terminalState = ProjectedScanState(outcome)
                    return classify(findings: findings, state: terminalState, scanStart: scanStart)
                }
            case let .terminal(outcome):
                terminalState = ProjectedScanState(outcome)
                return classify(findings: findings, state: terminalState, scanStart: scanStart)
            }
        }
    }

    /// Re-derives category, age and risk with the scan-start clock, so an age is never measured
    /// from a later observation instant than the conservative one.
    private func classify(
        findings: [Finding],
        state: ProjectedScanState,
        scanStart: WallClockInstant
    ) -> AdaptiveScanCollection {
        let projected = AdaptiveExperienceIdentity.sortedByKey(findings.map(ProjectedFinding.init))
        let detectors = detectorsByRootKind()
        let evaluator = PolicyEvaluator()
        var evaluations: [PolicyEvaluation] = []
        for finding in findings {
            let kind: GeneralMacRootKind
            do {
                kind = try catalog.rootKind(for: finding.declaredRoot.id)
            } catch {
                continue
            }
            guard let scoped = detectors[kind] else { continue }
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
            switch scoped.detector.makeFinding(
                from: observation,
                request: scoped.request,
                clockReading: ClockReading(
                    observationInstant: finding.observationInstant,
                    wallClockInstant: scanStart
                )
            ) {
            case let .success(maybeFinding):
                if let macFinding = maybeFinding {
                    let processActive = processActivity.isFileOpen(
                        rootID: finding.locator.rootID,
                        components: finding.locator.components
                    )
                    evaluations.append(evaluator.evaluate(macFinding, processActive: processActive))
                }
            case .failure:
                continue
            }
        }
        return AdaptiveScanCollection(
            scanState: state,
            findings: projected,
            evaluations: evaluations
        )
    }

    /// One request and detector per root kind, built once per collect instead of once per finding.
    private func detectorsByRootKind() -> [GeneralMacRootKind: (request: ScanRequest, detector: GeneralMacEvidenceDetector)] {
        var detectors: [GeneralMacRootKind: (request: ScanRequest, detector: GeneralMacEvidenceDetector)] = [:]
        for registration in catalog.registrations {
            let request: ScanRequest
            do {
                request = try catalog.scanRequest(for: [registration.rootKind])
            } catch {
                continue
            }
            detectors[registration.rootKind] = (
                request,
                GeneralMacEvidenceDetector(scope: registration.rootKind, catalog: catalog)
            )
        }
        return detectors
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
