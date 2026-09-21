public enum ScanValidationError: Error, Equatable, Sendable {
    case nonPositiveBudget
    case excessiveBudget
    case nonPositiveObservationBudget
    case excessiveObservationBudget
    case nonPositiveDepth
    case excessiveDepth
    case nonPositiveEntryBudget
    case excessiveEntryBudget
    case nonPositiveBatchBudget
    case excessiveBatchBudget
    case nonPositiveObservedByteBudget
    case excessiveObservedByteBudget
    case nonPositivePerRootFindingBudget
    case excessivePerRootFindingBudget
    case nonPositiveRootBudget
    case excessiveRootBudget
    case excessiveDeclaredRoots
    case emptyDeclaredRoots
    case duplicateDeclaredRoot
}

extension ScanValidationError {
    public var coreErrorCause: CoreErrorCause {
        switch self {
        case .nonPositiveBudget,
            .excessiveBudget,
            .nonPositiveObservationBudget,
            .excessiveObservationBudget,
            .nonPositiveDepth,
            .excessiveDepth,
            .nonPositiveEntryBudget,
            .excessiveEntryBudget,
            .nonPositiveBatchBudget,
            .excessiveBatchBudget,
            .nonPositiveObservedByteBudget,
            .excessiveObservedByteBudget,
            .nonPositivePerRootFindingBudget,
            .excessivePerRootFindingBudget,
            .nonPositiveRootBudget,
            .excessiveRootBudget:
            return .invalidBudget
        case .emptyDeclaredRoots, .duplicateDeclaredRoot, .excessiveDeclaredRoots:
            return .invalidRoot
        }
    }
}

public struct ScanBudget: Equatable, Sendable {
    public static let maximumAllowedFindings = 256
    public static let maximumAllowedObservations = 256
    public static let maximumAllowedDepth = 64
    public static let maximumAllowedEntries = 25_000
    public static let maximumAllowedBatches = 2_048
    public static let maximumAllowedObservedBytes: Int64 = 1_099_511_627_776
    public static let maximumAllowedFindingsPerRoot = 10_000
    public static let maximumAllowedRootsPerRequest = 6
    public static let defaultMaximumEntriesPerRoot = 4_096
    public static let defaultMaximumBatches = 256

    public let maximumFindings: Int
    public let maximumObservations: Int
    public let maximumDepth: Int
    public let maximumEntries: Int
    public let maximumBatches: Int
    public let maximumObservedBytes: Int64
    public let maximumFindingsPerRoot: Int
    public let maximumRootsPerRequest: Int
    public let maximumTotalEntries: Int
    public let maximumTotalFindings: Int
    public let maximumTotalObservedBytes: Int64

    public var maximumEntriesPerRoot: Int { maximumEntries }
    public var maximumObservedBytesPerRoot: Int64 { maximumObservedBytes }

    public init(
        maximumFindings: Int,
        maximumObservations: Int? = nil,
        maximumDepth: Int = maximumAllowedDepth,
        maximumEntries: Int = defaultMaximumEntriesPerRoot,
        maximumBatches: Int = defaultMaximumBatches,
        maximumObservedBytes: Int64 = maximumAllowedObservedBytes,
        maximumFindingsPerRoot: Int = maximumAllowedFindingsPerRoot,
        maximumRootsPerRequest: Int = maximumAllowedRootsPerRequest
    ) throws {
        guard maximumFindings > 0 else { throw ScanValidationError.nonPositiveBudget }
        guard maximumFindings <= Self.maximumAllowedFindings else {
            throw ScanValidationError.excessiveBudget
        }
        let resolvedMaximumObservations = maximumObservations ?? maximumFindings
        guard resolvedMaximumObservations > 0 else {
            throw ScanValidationError.nonPositiveObservationBudget
        }
        guard resolvedMaximumObservations <= Self.maximumAllowedObservations else {
            throw ScanValidationError.excessiveObservationBudget
        }
        guard maximumDepth > 0 else { throw ScanValidationError.nonPositiveDepth }
        guard maximumDepth <= Self.maximumAllowedDepth else { throw ScanValidationError.excessiveDepth }
        guard maximumEntries > 0 else { throw ScanValidationError.nonPositiveEntryBudget }
        guard maximumEntries <= Self.maximumAllowedEntries else {
            throw ScanValidationError.excessiveEntryBudget
        }
        guard maximumBatches > 0 else { throw ScanValidationError.nonPositiveBatchBudget }
        guard maximumBatches <= Self.maximumAllowedBatches else {
            throw ScanValidationError.excessiveBatchBudget
        }
        guard maximumObservedBytes > 0 else {
            throw ScanValidationError.nonPositiveObservedByteBudget
        }
        guard maximumObservedBytes <= Self.maximumAllowedObservedBytes else {
            throw ScanValidationError.excessiveObservedByteBudget
        }
        guard maximumFindingsPerRoot > 0 else {
            throw ScanValidationError.nonPositivePerRootFindingBudget
        }
        guard maximumFindingsPerRoot <= Self.maximumAllowedFindingsPerRoot else {
            throw ScanValidationError.excessivePerRootFindingBudget
        }
        guard maximumRootsPerRequest > 0 else {
            throw ScanValidationError.nonPositiveRootBudget
        }
        guard maximumRootsPerRequest <= Self.maximumAllowedRootsPerRequest else {
            throw ScanValidationError.excessiveRootBudget
        }
        let maximumTotalEntries = try Self.checkedTotalEntries(
            maximumEntriesPerRoot: maximumEntries,
            maximumRootsPerRequest: maximumRootsPerRequest
        )
        let maximumTotalFindings = try Self.checkedTotalFindings(
            maximumFindingsPerRoot: maximumFindingsPerRoot,
            maximumRootsPerRequest: maximumRootsPerRequest
        )
        let maximumTotalObservedBytes = try Self.checkedTotalObservedBytes(
            maximumObservedBytesPerRoot: maximumObservedBytes,
            maximumRootsPerRequest: maximumRootsPerRequest
        )

        self.maximumFindings = maximumFindings
        self.maximumObservations = resolvedMaximumObservations
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
        self.maximumBatches = maximumBatches
        self.maximumObservedBytes = maximumObservedBytes
        self.maximumFindingsPerRoot = maximumFindingsPerRoot
        self.maximumRootsPerRequest = maximumRootsPerRequest
        self.maximumTotalEntries = maximumTotalEntries
        self.maximumTotalFindings = maximumTotalFindings
        self.maximumTotalObservedBytes = maximumTotalObservedBytes
    }

    static func checkedTotalEntries(
        maximumEntriesPerRoot: Int,
        maximumRootsPerRequest: Int
    ) throws -> Int {
        let (total, overflow) = maximumEntriesPerRoot.multipliedReportingOverflow(
            by: maximumRootsPerRequest
        )
        guard !overflow else { throw ScanValidationError.excessiveEntryBudget }
        return total
    }

    static func checkedTotalFindings(
        maximumFindingsPerRoot: Int,
        maximumRootsPerRequest: Int
    ) throws -> Int {
        let (total, overflow) = maximumFindingsPerRoot.multipliedReportingOverflow(
            by: maximumRootsPerRequest
        )
        guard !overflow else { throw ScanValidationError.excessivePerRootFindingBudget }
        return total
    }

    static func checkedTotalObservedBytes(
        maximumObservedBytesPerRoot: Int64,
        maximumRootsPerRequest: Int
    ) throws -> Int64 {
        let (total, overflow) = maximumObservedBytesPerRoot.multipliedReportingOverflow(
            by: Int64(maximumRootsPerRequest)
        )
        guard !overflow else { throw ScanValidationError.excessiveObservedByteBudget }
        return total
    }
}

public struct ScanRequest: Equatable, Sendable {
    public let declaredRoots: [DeclaredRoot]
    public let budget: ScanBudget

    public var declaredRoot: DeclaredRoot {
        declaredRoots[0]
    }

    public init(declaredRoot: DeclaredRoot, budget: ScanBudget) {
        declaredRoots = [declaredRoot]
        self.budget = budget
    }

    public init(declaredRoots: [DeclaredRoot], budget: ScanBudget) throws {
        guard !declaredRoots.isEmpty else { throw ScanValidationError.emptyDeclaredRoots }
        guard declaredRoots.count <= budget.maximumRootsPerRequest else {
            throw ScanValidationError.excessiveDeclaredRoots
        }
        guard Set(declaredRoots.map(\.id)).count == declaredRoots.count else {
            throw ScanValidationError.duplicateDeclaredRoot
        }

        self.declaredRoots = declaredRoots
        self.budget = budget
    }
}

public struct ScanCursor: Equatable, Sendable {
    public let position: UInt

    public init(position: UInt) {
        self.position = position
    }
}

public struct ScanBatch: Equatable, Sendable {
    public let findings: [Finding]
    public let continuationCursor: ScanCursor?
    public let terminalOutcome: ScanOutcome?

    init(
        findings: [Finding],
        continuationCursor: ScanCursor?,
        terminalOutcome: ScanOutcome? = nil
    ) {
        self.findings = findings
        self.continuationCursor = continuationCursor
        self.terminalOutcome = terminalOutcome
    }
}

public struct ScanIssue: Equatable, Sendable {
    public let rootID: DeclaredRootID
    public let detectorID: DetectorID
    public let cause: CoreErrorCause

    public init(rootID: DeclaredRootID, detectorID: DetectorID, cause: CoreErrorCause) {
        self.rootID = rootID
        self.detectorID = detectorID
        self.cause = cause
    }
}

public enum ScanOutcome: Equatable, Sendable {
    case complete
    case partial(issues: [ScanIssue])
    case permissionDenied
    case cancelled
    case corruptMetadata
    case unsupportedLayout

    public static func aggregate(completedRootCount: Int, issues: [ScanIssue]) -> ScanOutcome {
        let orderedIssues = issues.sorted(by: ScanIssue.precedes)
        guard let primaryIssue = orderedIssues.first else { return .complete }
        guard completedRootCount > 0 else { return terminalOutcome(for: primaryIssue.cause) }
        return .partial(issues: orderedIssues)
    }

    private static func terminalOutcome(for cause: CoreErrorCause) -> ScanOutcome {
        switch cause {
        case .permissionDenied:
            return .permissionDenied
        case .cancelled:
            return .cancelled
        case .unsupportedLayout, .unsupportedAdapterState:
            return .unsupportedLayout
        case .invalidBudget,
            .invalidCursor,
            .invalidRoot,
            .invalidLocator,
            .invalidMeasurement,
            .corruptMetadata,
            .portFailure,
            .invalidObservation,
            .requestChanged:
            return .corruptMetadata
        }
    }
}

extension ScanIssue {
    fileprivate static func precedes(_ lhs: ScanIssue, _ rhs: ScanIssue) -> Bool {
        let lhsKey = (lhs.cause.aggregationPrecedence, lhs.rootID.value, lhs.detectorID.value)
        let rhsKey = (rhs.cause.aggregationPrecedence, rhs.rootID.value, rhs.detectorID.value)
        return lhsKey.0 != rhsKey.0
            ? lhsKey.0 < rhsKey.0
            : lhsKey.1 != rhsKey.1
                ? lhsKey.1 < rhsKey.1
                : lhsKey.2 < rhsKey.2
    }
}

extension CoreErrorCause {
    fileprivate var aggregationPrecedence: Int {
        switch self {
        case .cancelled:
            return 0
        case .permissionDenied:
            return 1
        case .corruptMetadata, .invalidObservation:
            return 2
        case .unsupportedLayout, .unsupportedAdapterState:
            return 3
        case .portFailure:
            return 4
        case .invalidBudget,
            .invalidCursor,
            .invalidRoot,
            .invalidLocator,
            .invalidMeasurement,
            .requestChanged:
            return 5
        }
    }
}

public enum ScanStep: Equatable, Sendable {
    case batch(ScanBatch)
    case terminal(ScanOutcome)
}

public enum FileSystemStep: Equatable, Sendable {
    case observation(FileObservation)
    case terminal(ScanOutcome)
}

actor ScanCoordinator {
    private let dependencies: ScanDependencies
    private let detector: any LocalDetector
    private var cursor: ScanCursor?
    private var terminalOutcome: ScanOutcome?
    private var requestFingerprint: ScanRequest?
    private var activeRootIndex = 0
    private var completedRootCount = 0
    private var perRootEntriesRead = 0
    private var perRootFindingsRead = 0
    private var perRootObservedBytesRead: Int64 = 0
    private var totalEntriesRead = 0
    private var totalFindingsRead = 0
    private var totalObservedBytesRead: Int64 = 0
    private var deliveredBatchCount = 0

    init(
        dependencies: ScanDependencies,
        registry: DetectorRegistry,
        selection: DetectorSelection
    ) throws {
        self.dependencies = dependencies
        detector = try registry.resolve(selection)
    }

    init(dependencies: ScanDependencies, shippedDetector: any LocalDetector) throws {
        try self.init(
            dependencies: dependencies,
            registry: DetectorRegistry(registrations: [.init(detector: shippedDetector)]),
            selection: .init(id: shippedDetector.identifier, version: shippedDetector.version)
        )
    }

    func nextBatch(for request: ScanRequest) async -> ScanStep {
        guard bind(request) else {
            return .terminal(.corruptMetadata)
        }

        if let terminalOutcome {
            return .terminal(terminalOutcome)
        }

        var findings: [Finding] = []
        var observationsProcessed = 0
        while findings.count < request.budget.maximumFindings,
            observationsProcessed < request.budget.maximumObservations,
            perRootEntriesRead < request.budget.maximumEntriesPerRoot,
            perRootFindingsRead < request.budget.maximumFindingsPerRoot,
            perRootObservedBytesRead < request.budget.maximumObservedBytesPerRoot,
            totalEntriesRead < request.budget.maximumTotalEntries,
            totalFindingsRead < request.budget.maximumTotalFindings,
            totalObservedBytesRead < request.budget.maximumTotalObservedBytes
        {
            if await dependencies.cancellation.isCancellationRequested() {
                await dependencies.diagnostics.record(.cancelled)
                await dependencies.metrics.record(.stepDelivered)
                return finish(
                    findings: findings,
                    outcome: aggregate(
                        terminal: .cancelled,
                        activeRoot: activeRoot(for: request)
                    )
                )
            }
            if deliveredBatchCount >= request.budget.maximumBatches {
                let outcome = aggregate(
                    terminal: .corruptMetadata,
                    activeRoot: activeRoot(for: request)
                )
                await dependencies.diagnostics.record(.terminal(.init(outcome)))
                await dependencies.metrics.record(.stepDelivered)
                return finish(findings: findings, outcome: outcome)
            }

            let root = activeRoot(for: request)
            let fileSystemStep = await dependencies.fileSystem.nextObservation(
                after: cursor,
                in: root
            )

            switch fileSystemStep {
            case .observation(let observation):
                if !isWithinDepthBudget(observation, budget: request.budget) {
                    let outcome = ScanOutcome.aggregate(
                        completedRootCount: completedRootCount,
                        issues: [
                            .init(
                                rootID: root.id,
                                detectorID: detector.identifier,
                                cause: .unsupportedLayout
                            )
                        ]
                    )
                    await dependencies.diagnostics.record(.terminal(.init(outcome)))
                    await dependencies.metrics.record(.stepDelivered)
                    return finish(findings: findings, outcome: outcome)
                }
                let observedBytes = observedLogicalBytes(in: observation)
                guard perRootObservedBytesRead
                    <= request.budget.maximumObservedBytesPerRoot - observedBytes,
                    totalObservedBytesRead
                        <= request.budget.maximumTotalObservedBytes - observedBytes
                else {
                    let outcome = aggregate(terminal: .corruptMetadata, activeRoot: root)
                    await dependencies.diagnostics.record(.terminal(.init(outcome)))
                    await dependencies.metrics.record(.stepDelivered)
                    return finish(findings: findings, outcome: outcome)
                }
                observationsProcessed += 1
                perRootEntriesRead += 1
                totalEntriesRead += 1
                perRootObservedBytesRead += observedBytes
                totalObservedBytesRead += observedBytes
                cursor = ScanCursor(position: (cursor?.position ?? 0) + 1)
                let clockReading = await dependencies.clock.now()
                await dependencies.diagnostics.record(.observationPulled)
                switch detector.makeFinding(
                    from: observation,
                    request: request,
                    clockReading: clockReading
                ) {
                case .success(let finding?):
                    findings.append(finding)
                    perRootFindingsRead += 1
                    totalFindingsRead += 1
                case .success(nil):
                    continue
                case .failure(let cause):
                    let outcome = ScanOutcome.aggregate(
                        completedRootCount: completedRootCount,
                        issues: [
                            .init(
                                rootID: root.id,
                                detectorID: detector.identifier,
                                cause: cause.coreErrorCause
                            )
                        ]
                    )
                    await dependencies.diagnostics.record(.terminal(.init(outcome)))
                    await dependencies.metrics.record(.stepDelivered)
                    return finish(findings: findings, outcome: outcome)
                }
            case .terminal(let outcome):
                if outcome == .complete {
                    completedRootCount += 1
                    activeRootIndex += 1
                    cursor = nil
                    perRootEntriesRead = 0
                    perRootFindingsRead = 0
                    perRootObservedBytesRead = 0
                    if activeRootIndex < request.declaredRoots.count {
                        continue
                    }
                }
                await dependencies.diagnostics.record(.terminal(.init(outcome)))
                await dependencies.metrics.record(.stepDelivered)
                return finish(
                    findings: findings,
                    outcome: aggregate(terminal: outcome, activeRoot: root)
                )
            }
        }

        if perRootEntriesRead >= request.budget.maximumEntriesPerRoot
            || perRootFindingsRead >= request.budget.maximumFindingsPerRoot
            || perRootObservedBytesRead >= request.budget.maximumObservedBytesPerRoot
            || totalEntriesRead >= request.budget.maximumTotalEntries
            || totalFindingsRead >= request.budget.maximumTotalFindings
            || totalObservedBytesRead >= request.budget.maximumTotalObservedBytes
        {
            let outcome = aggregate(
                terminal: .corruptMetadata,
                activeRoot: activeRoot(for: request)
            )
            await dependencies.diagnostics.record(.terminal(.init(outcome)))
            await dependencies.metrics.record(.stepDelivered)
            return finish(findings: findings, outcome: outcome)
        }

        if await dependencies.cancellation.isCancellationRequested() {
            await dependencies.diagnostics.record(.cancelled)
            await dependencies.metrics.record(.stepDelivered)
            return finish(
                findings: findings,
                outcome: aggregate(
                    terminal: .cancelled,
                    activeRoot: activeRoot(for: request)
                )
            )
        }

        await dependencies.metrics.record(.stepDelivered)
        deliveredBatchCount += 1
        return .batch(.init(findings: findings, continuationCursor: cursor))
    }

    private func bind(_ request: ScanRequest) -> Bool {
        if let requestFingerprint {
            return requestFingerprint == request
        }

        requestFingerprint = request
        return true
    }

    private func finish(findings: [Finding], outcome: ScanOutcome) -> ScanStep {
        terminalOutcome = outcome
        if findings.isEmpty {
            return .terminal(outcome)
        }
        deliveredBatchCount += 1
        return .batch(
            .init(
                findings: findings,
                continuationCursor: nil,
                terminalOutcome: outcome
            ))
    }

    private func observedLogicalBytes(in observation: FileObservation) -> Int64 {
        switch observation.sizes.logicalBytes {
        case .observed(let bytes):
            return max(0, bytes)
        case .unknown, .unavailable:
            return 0
        }
    }

    private func isWithinDepthBudget(_ observation: FileObservation, budget: ScanBudget) -> Bool {
        observation.locator.components.count <= budget.maximumDepth
    }

    private func activeRoot(for request: ScanRequest) -> DeclaredRoot {
        request.declaredRoots[activeRootIndex]
    }

    private func aggregate(terminal: ScanOutcome, activeRoot: DeclaredRoot) -> ScanOutcome {
        guard terminal != .complete else { return .complete }
        guard completedRootCount > 0 else { return terminal }

        let cause: CoreErrorCause
        switch terminal {
        case .permissionDenied:
            cause = .permissionDenied
        case .cancelled:
            cause = .cancelled
        case .corruptMetadata:
            cause = .corruptMetadata
        case .unsupportedLayout:
            cause = .unsupportedLayout
        case .complete, .partial:
            return terminal
        }
        return ScanOutcome.aggregate(
            completedRootCount: completedRootCount,
            issues: [.init(rootID: activeRoot.id, detectorID: detector.identifier, cause: cause)]
        )
    }
}
