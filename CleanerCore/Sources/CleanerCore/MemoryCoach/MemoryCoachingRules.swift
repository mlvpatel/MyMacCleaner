public enum CoachingMessageKey: String, CaseIterable, Equatable, Sendable {
    case pressureNormal = "performance.coach.pressure.normal"
    case pressureWarning = "performance.coach.pressure.warning"
    case pressureCritical = "performance.coach.pressure.critical"
    case pressureUnavailable = "performance.coach.pressure.unavailable"
    case pressureStale = "performance.coach.pressure.stale"
    case cacheManagedByMacOS = "performance.coach.cache.managed"
    case cacheUnavailable = "performance.coach.cache.unavailable"
    case sampleComplete = "performance.coach.sample.complete"
    case samplePartial = "performance.coach.sample.partial"
    case sampleTruncated = "performance.coach.sample.truncated"
    case sampleCancelled = "performance.coach.sample.cancelled"
    case sampleUnavailable = "performance.coach.sample.unavailable"
    case guidanceCloseKnownApp = "performance.coach.guidance.closeKnownApp"
    case guidanceReduceWorkload = "performance.coach.guidance.reduceWorkload"
    case guidanceRefreshObservation = "performance.coach.guidance.refresh"
    case contextConfirmed = "performance.coach.context.confirmed"
    case contextInferred = "performance.coach.context.inferred"
    case contextAbsent = "performance.coach.context.absent"
    case processDenied = "performance.coach.process.denied"
    case processExited = "performance.coach.process.exited"
    case processShortRead = "performance.coach.process.shortRead"
    case processIdentityChanged = "performance.coach.process.identityChanged"
    case processUnreadable = "performance.coach.process.unreadable"
    case processTruncated = "performance.coach.process.truncated"
    case processDeadlineExceeded = "performance.coach.process.deadlineExceeded"
    case processCancelled = "performance.coach.process.cancelled"
    case processInvalidSource = "performance.coach.process.invalidSource"
}

public enum MemoryCoachCompleteness: Equatable, Sendable {
    case complete
    case partial
    case truncated
    case cancelled
    case unavailable
}

public enum MemoryCoachValuePresentation: Equatable, Sendable {
    case observed(UInt64, observedAt: ClockReading)
    case unavailable(MemoryObservationUnavailable)
}

public struct MemoryCoachFieldPresentation: Equatable, Sendable {
    public let physicalMemory: MemoryCoachValuePresentation
    public let activeMemory: MemoryCoachValuePresentation
    public let inactiveMemory: MemoryCoachValuePresentation
    public let wiredMemory: MemoryCoachValuePresentation
    public let compressedMemory: MemoryCoachValuePresentation
    public let purgeableMemory: MemoryCoachValuePresentation
    public let swapUsed: MemoryCoachValuePresentation
    public let swapTotal: MemoryCoachValuePresentation

    public init(
        physicalMemory: MemoryCoachValuePresentation,
        activeMemory: MemoryCoachValuePresentation,
        inactiveMemory: MemoryCoachValuePresentation,
        wiredMemory: MemoryCoachValuePresentation,
        compressedMemory: MemoryCoachValuePresentation,
        purgeableMemory: MemoryCoachValuePresentation,
        swapUsed: MemoryCoachValuePresentation,
        swapTotal: MemoryCoachValuePresentation
    ) {
        self.physicalMemory = physicalMemory
        self.activeMemory = activeMemory
        self.inactiveMemory = inactiveMemory
        self.wiredMemory = wiredMemory
        self.compressedMemory = compressedMemory
        self.purgeableMemory = purgeableMemory
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    public static func unavailable(
        _ reason: MemoryObservationUnavailable
    ) -> MemoryCoachFieldPresentation {
        .init(
            physicalMemory: .unavailable(reason),
            activeMemory: .unavailable(reason),
            inactiveMemory: .unavailable(reason),
            wiredMemory: .unavailable(reason),
            compressedMemory: .unavailable(reason),
            purgeableMemory: .unavailable(reason),
            swapUsed: .unavailable(reason),
            swapTotal: .unavailable(reason)
        )
    }
}

public struct MemoryCoachProcessRow: Equatable, Sendable {
    public let label: ProcessDisplayLabel
    public let pid: Int32
    public let residentBytes: UInt64
    public let observedAt: ClockReading
    public let contextKey: CoachingMessageKey

    public init(
        label: ProcessDisplayLabel,
        pid: Int32,
        residentBytes: UInt64,
        observedAt: ClockReading,
        contextKey: CoachingMessageKey
    ) {
        self.label = label
        self.pid = pid
        self.residentBytes = residentBytes
        self.observedAt = observedAt
        self.contextKey = contextKey
    }
}

public struct CoachingExplanation: Equatable, Sendable {
    public let pressureKey: CoachingMessageKey
    public let cacheKey: CoachingMessageKey
    public let completenessKey: CoachingMessageKey
    public let suggestionKeys: [CoachingMessageKey]

    public init(
        pressureKey: CoachingMessageKey,
        cacheKey: CoachingMessageKey,
        completenessKey: CoachingMessageKey,
        suggestionKeys: [CoachingMessageKey]
    ) {
        self.pressureKey = pressureKey
        self.cacheKey = cacheKey
        self.completenessKey = completenessKey
        self.suggestionKeys = suggestionKeys
    }
}

public struct MemoryCoachPresentation: Equatable, Sendable {
    public let sessionID: MemoryObservationSessionID
    public let startedAt: MemoryObservationTimestamp
    public let completedAt: MemoryObservationTimestamp
    public let pressure: MemoryPressureObservation
    public let fields: MemoryCoachFieldPresentation
    public let processes: [MemoryCoachProcessRow]
    public let processIssueKeys: [CoachingMessageKey]
    public let outcome: MemorySnapshotOutcome
    public let completeness: MemoryCoachCompleteness
    public let explanation: CoachingExplanation

    public init(
        sessionID: MemoryObservationSessionID,
        startedAt: MemoryObservationTimestamp,
        completedAt: MemoryObservationTimestamp,
        pressure: MemoryPressureObservation,
        fields: MemoryCoachFieldPresentation,
        processes: [MemoryCoachProcessRow],
        processIssueKeys: [CoachingMessageKey],
        outcome: MemorySnapshotOutcome,
        completeness: MemoryCoachCompleteness,
        explanation: CoachingExplanation
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.pressure = pressure
        self.fields = fields
        self.processes = processes
        self.processIssueKeys = processIssueKeys
        self.outcome = outcome
        self.completeness = completeness
        self.explanation = explanation
    }

    public static let unavailable = MemoryCoachPresentation(
        sessionID: .init(0),
        startedAt: .unavailable(.unavailable),
        completedAt: .unavailable(.unavailable),
        pressure: .unavailableNoFreshEvent,
        fields: .unavailable(.unavailable),
        processes: [],
        processIssueKeys: [],
        outcome: .unavailable,
        completeness: .unavailable,
        explanation: .init(
            pressureKey: .pressureUnavailable,
            cacheKey: .cacheUnavailable,
            completenessKey: .sampleUnavailable,
            suggestionKeys: [.guidanceRefreshObservation]
        )
    )
}

public struct MemoryCoachingRules: Sendable {
    public init() {}

    public func evaluate(
        snapshot: MemoryCoachSnapshot,
        contexts: [ProcessObservationIdentity: WorkloadContext]
    ) -> MemoryCoachPresentation {
        let canProjectProcessRows: Bool
        switch snapshot.outcome {
        case .complete, .partial:
            canProjectProcessRows = true
        case .cancelled, .unavailable:
            canProjectProcessRows = false
        }
        let suppliedProcesses = canProjectProcessRows ? snapshot.processes : []
        let boundedCandidates = Array(
            suppliedProcesses.prefix(snapshot.samplingBudget.maximumCandidates)
        )
        let boundedProcesses = Array(
            boundedCandidates
            .sorted(by: processPrecedes)
            .prefix(snapshot.samplingBudget.maximumRows)
        )
        let inputExceededCandidateLimit = suppliedProcesses.count > snapshot.samplingBudget.maximumCandidates
        let processIssues = boundedProcesses.count < suppliedProcesses.count
            ? uniqueProcessIssues(
                snapshot.processIssues
                    + [.truncated]
                    + (inputExceededCandidateLimit ? [.invalidSource] : [])
            )
            : snapshot.processIssues
        let pressureRule = pressureRule(for: snapshot.pressure)
        let completeness = completeness(
            for: snapshot.outcome,
            processIssues: processIssues
        )
        let processRows = boundedProcesses
            .map { process in
                processRow(
                    process,
                    sessionID: snapshot.sessionID,
                    suppliedContext: contexts[process.identity]
                )
            }

        return MemoryCoachPresentation(
            sessionID: snapshot.sessionID,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            pressure: snapshot.pressure,
            fields: fields(from: snapshot),
            processes: processRows,
            processIssueKeys: uniqueIssueKeys(processIssues),
            outcome: snapshot.outcome,
            completeness: completeness,
            explanation: .init(
                pressureKey: pressureRule.key,
                cacheKey: cacheKey(for: snapshot.vm),
                completenessKey: completenessKey(for: completeness),
                suggestionKeys: pressureRule.suggestions
            )
        )
    }

    private func pressureRule(
        for pressure: MemoryPressureObservation
    ) -> (key: CoachingMessageKey, suggestions: [CoachingMessageKey]) {
        switch pressure {
        case let .observed(level, _):
            switch level {
            case .normal:
                (.pressureNormal, [])
            case .warning:
                (.pressureWarning, [.guidanceCloseKnownApp, .guidanceReduceWorkload])
            case .critical:
                (.pressureCritical, [.guidanceCloseKnownApp, .guidanceReduceWorkload])
            }
        case .unavailableNoFreshEvent:
            (.pressureUnavailable, [.guidanceRefreshObservation])
        case .stale:
            (.pressureStale, [.guidanceRefreshObservation])
        }
    }

    private func completeness(
        for outcome: MemorySnapshotOutcome,
        processIssues: [ProcessObservationIssue]
    ) -> MemoryCoachCompleteness {
        switch outcome {
        case .cancelled:
            return .cancelled
        case .unavailable:
            return .unavailable
        case .complete:
            return processIssues.contains(.truncated) ? .truncated : .complete
        case .partial:
            return processIssues.contains(.truncated) ? .truncated : .partial
        }
    }

    private func completenessKey(
        for completeness: MemoryCoachCompleteness
    ) -> CoachingMessageKey {
        switch completeness {
        case .complete:
            .sampleComplete
        case .partial:
            .samplePartial
        case .truncated:
            .sampleTruncated
        case .cancelled:
            .sampleCancelled
        case .unavailable:
            .sampleUnavailable
        }
    }

    private func cacheKey(for vm: MemoryVMContext) -> CoachingMessageKey {
        switch (vm.inactiveBytes, vm.purgeableBytes) {
        case (.observed, .observed), (.observed, .unavailable), (.unavailable, .observed):
            .cacheManagedByMacOS
        case (.unavailable, .unavailable):
            .cacheUnavailable
        }
    }

    private func fields(from snapshot: MemoryCoachSnapshot) -> MemoryCoachFieldPresentation {
        .init(
            physicalMemory: field(snapshot.physicalMemory),
            activeMemory: field(snapshot.vm.activeBytes),
            inactiveMemory: field(snapshot.vm.inactiveBytes),
            wiredMemory: field(snapshot.vm.wiredBytes),
            compressedMemory: field(snapshot.vm.compressedBytes),
            purgeableMemory: field(snapshot.vm.purgeableBytes),
            swapUsed: field(snapshot.swap.usedBytes),
            swapTotal: field(snapshot.swap.totalBytes)
        )
    }

    private func field(
        _ source: MemoryField<UInt64>
    ) -> MemoryCoachValuePresentation {
        switch source {
        case let .observed(bytes, observedAt):
            .observed(bytes, observedAt: observedAt)
        case let .unavailable(reason):
            .unavailable(reason)
        }
    }

    private func processRow(
        _ process: ProcessMemoryEvidence,
        sessionID: MemoryObservationSessionID,
        suppliedContext: WorkloadContext?
    ) -> MemoryCoachProcessRow {
        let expectedIdentity = WorkloadObservationIdentity(
            sessionID: sessionID,
            processIdentity: process.identity
        )
        let context: WorkloadContext
        if let suppliedContext, suppliedContext.identity == expectedIdentity {
            context = suppliedContext
        } else {
            context = .absent(
                identity: expectedIdentity,
                reason: suppliedContext == nil ? .unknownProcessIdentity : .identityMismatch
            )
        }

        return .init(
            label: process.label,
            pid: process.identity.pid,
            residentBytes: process.residentBytes,
            observedAt: process.observedAt,
            contextKey: contextKey(for: context)
        )
    }

    private func contextKey(for context: WorkloadContext) -> CoachingMessageKey {
        switch context {
        case .confirmed:
            .contextConfirmed
        case .inferred:
            .contextInferred
        case .absent:
            .contextAbsent
        }
    }

    private func processPrecedes(
        _ lhs: ProcessMemoryEvidence,
        _ rhs: ProcessMemoryEvidence
    ) -> Bool {
        if lhs.residentBytes != rhs.residentBytes {
            return lhs.residentBytes > rhs.residentBytes
        }
        if lhs.label.value != rhs.label.value {
            return lhs.label.value < rhs.label.value
        }
        return lhs.identity.pid < rhs.identity.pid
    }

    private func uniqueIssueKeys(
        _ issues: [ProcessObservationIssue]
    ) -> [CoachingMessageKey] {
        issues.map(issueKey).reduce([]) { keys, key in
            keys.contains(key) ? keys : keys + [key]
        }
    }

    private func uniqueProcessIssues(
        _ issues: [ProcessObservationIssue]
    ) -> [ProcessObservationIssue] {
        issues.reduce([]) { observed, issue in
            observed.contains(issue) ? observed : observed + [issue]
        }
    }

    private func issueKey(_ issue: ProcessObservationIssue) -> CoachingMessageKey {
        switch issue {
        case .denied:
            .processDenied
        case .exited:
            .processExited
        case .shortRead:
            .processShortRead
        case .identityChanged:
            .processIdentityChanged
        case .unreadable:
            .processUnreadable
        case .truncated:
            .processTruncated
        case .deadlineExceeded:
            .processDeadlineExceeded
        case .cancelled:
            .processCancelled
        case .invalidSource:
            .processInvalidSource
        }
    }
}
