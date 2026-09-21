public struct MemoryObservationSessionID: Equatable, Hashable, Sendable {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }
}

public enum MemoryPressureLevel: Equatable, Sendable {
    case normal
    case warning
    case critical
}

public enum MemoryObservationUnavailable: Equatable, Sendable {
    case noFreshEvent
    case stale
    case unavailable
    case malformedSource
    case overflow
    case denied
    case exited
    case shortRead
    case identityChanged
    case deadlineExceeded
}

public enum MemoryField<Value>: Equatable, Sendable where Value: Equatable & Sendable {
    case observed(Value, observedAt: ClockReading)
    case unavailable(MemoryObservationUnavailable)
}

public enum MemoryPressureObservation: Equatable, Sendable {
    case observed(MemoryPressureLevel, observedAt: ClockReading)
    case unavailableNoFreshEvent
    case stale(MemoryPressureLevel, observedAt: ClockReading)
}

/// A source clock can fail independently from the rest of a local observation.
/// Keeping that failure typed prevents callers from treating a fabricated epoch
/// value as a real sample time.
public enum MemoryObservationTimestamp: Equatable, Sendable {
    case observed(ClockReading)
    case unavailable(MemoryObservationUnavailable)
}

public struct MemoryVMContext: Equatable, Sendable {
    public let activeBytes: MemoryField<UInt64>
    public let inactiveBytes: MemoryField<UInt64>
    public let wiredBytes: MemoryField<UInt64>
    public let compressedBytes: MemoryField<UInt64>
    public let purgeableBytes: MemoryField<UInt64>

    public init(
        activeBytes: MemoryField<UInt64>,
        inactiveBytes: MemoryField<UInt64>,
        wiredBytes: MemoryField<UInt64>,
        compressedBytes: MemoryField<UInt64>,
        purgeableBytes: MemoryField<UInt64>
    ) {
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.purgeableBytes = purgeableBytes
    }

    public static func unavailable(_ reason: MemoryObservationUnavailable) -> Self {
        .init(
            activeBytes: .unavailable(reason),
            inactiveBytes: .unavailable(reason),
            wiredBytes: .unavailable(reason),
            compressedBytes: .unavailable(reason),
            purgeableBytes: .unavailable(reason)
        )
    }
}

public struct MemorySwapContext: Equatable, Sendable {
    public let usedBytes: MemoryField<UInt64>
    public let totalBytes: MemoryField<UInt64>

    public init(usedBytes: MemoryField<UInt64>, totalBytes: MemoryField<UInt64>) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public static func unavailable(_ reason: MemoryObservationUnavailable) -> Self {
        .init(usedBytes: .unavailable(reason), totalBytes: .unavailable(reason))
    }
}

public enum MemorySnapshotIssue: Equatable, Sendable {
    case timing(MemoryObservationUnavailable)
    case pressure(MemoryObservationUnavailable)
    case physicalMemory(MemoryObservationUnavailable)
    case vm(MemoryObservationUnavailable)
    case swap(MemoryObservationUnavailable)
    case workload(MemoryObservationUnavailable)
}

public enum MemorySnapshotOutcome: Equatable, Sendable {
    case complete
    case partial
    case cancelled
    case unavailable
}

public struct MemoryCoachSnapshot: Equatable, Sendable {
    public let sessionID: MemoryObservationSessionID
    public let samplingBudget: SamplingBudget
    public let startedAt: MemoryObservationTimestamp
    public let completedAt: MemoryObservationTimestamp
    public let pressure: MemoryPressureObservation
    public let physicalMemory: MemoryField<UInt64>
    public let vm: MemoryVMContext
    public let swap: MemorySwapContext
    public let processes: [ProcessMemoryEvidence]
    public let processIssues: [ProcessObservationIssue]
    public let issues: [MemorySnapshotIssue]
    public let outcome: MemorySnapshotOutcome

    public init(
        sessionID: MemoryObservationSessionID,
        samplingBudget: SamplingBudget,
        startedAt: MemoryObservationTimestamp,
        completedAt: MemoryObservationTimestamp,
        pressure: MemoryPressureObservation,
        physicalMemory: MemoryField<UInt64>,
        vm: MemoryVMContext,
        swap: MemorySwapContext,
        processes: [ProcessMemoryEvidence] = [],
        processIssues: [ProcessObservationIssue] = [],
        issues: [MemorySnapshotIssue],
        outcome: MemorySnapshotOutcome
    ) {
        self.sessionID = sessionID
        self.samplingBudget = samplingBudget
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.pressure = pressure
        self.physicalMemory = physicalMemory
        self.vm = vm
        self.swap = swap
        self.processes = processes
        self.processIssues = processIssues
        self.issues = issues
        self.outcome = outcome
    }
}

public enum ProcessObservationIssue: Equatable, Sendable {
    case denied
    case exited
    case shortRead
    case identityChanged
    case unreadable
    case truncated
    case deadlineExceeded
    case cancelled
    case invalidSource
}

public protocol MemoryObservationCancellation: Sendable {
    func isCancellationRequested() async -> Bool
}

public protocol MemoryObservationPort: Sendable {
    func observe(cancellation: any MemoryObservationCancellation) async -> MemoryCoachSnapshot
}

public struct SamplingBudget: Equatable, Sendable {
    public static let maximumCandidates = 512
    public static let maximumRows = 10
    public static let maximumDurationNanoseconds: UInt64 = 500_000_000

    public let maximumCandidates: Int
    public let maximumRows: Int
    public let maximumDurationNanoseconds: UInt64

    public static let standard = SamplingBudget(
        maximumCandidates: maximumCandidates,
        maximumRows: maximumRows,
        maximumDurationNanoseconds: maximumDurationNanoseconds,
        trusted: ()
    )

    public init(
        maximumCandidates: Int = Self.maximumCandidates,
        maximumRows: Int = Self.maximumRows,
        maximumDurationNanoseconds: UInt64 = Self.maximumDurationNanoseconds
    ) throws {
        guard maximumCandidates > 0, maximumRows > 0, maximumDurationNanoseconds > 0 else {
            throw MemorySamplingBudgetError.invalid
        }
        guard maximumCandidates <= Self.maximumCandidates,
              maximumRows <= Self.maximumRows,
              maximumDurationNanoseconds <= Self.maximumDurationNanoseconds
        else {
            throw MemorySamplingBudgetError.excessive
        }
        self.maximumCandidates = maximumCandidates
        self.maximumRows = maximumRows
        self.maximumDurationNanoseconds = maximumDurationNanoseconds
    }

    private init(maximumCandidates: Int, maximumRows: Int, maximumDurationNanoseconds: UInt64, trusted: ()) {
        self.maximumCandidates = maximumCandidates
        self.maximumRows = maximumRows
        self.maximumDurationNanoseconds = maximumDurationNanoseconds
    }
}

public enum MemorySamplingBudgetError: Error, Equatable, Sendable {
    case invalid
    case excessive
}

public struct ProcessObservationIdentity: Equatable, Hashable, Sendable {
    public let pid: Int32
    public let startTimeSeconds: UInt64
    public let startTimeMicroseconds: UInt64

    public init?(pid: Int32, startTimeSeconds: UInt64, startTimeMicroseconds: UInt64) {
        guard pid > 0, startTimeMicroseconds < 1_000_000 else {
            return nil
        }
        self.pid = pid
        self.startTimeSeconds = startTimeSeconds
        self.startTimeMicroseconds = startTimeMicroseconds
    }
}

public struct ProcessDisplayLabel: Equatable, Sendable {
    public let value: String

    public init?(_ value: String) {
        guard !value.isEmpty, value.count <= 64,
              value.unicodeScalars.allSatisfy(Self.isAllowedLabelScalar) else {
            return nil
        }
        self.value = value
    }

    public static func isAllowedLabelScalar(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value >= 32,
              !(127 ... 159).contains(scalar.value)
        else {
            return false
        }
        return switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator,
             .privateUse, .surrogate, .unassigned:
            false
        default:
            true
        }
    }

    public static let generic = ProcessDisplayLabel(value: "Observed process", trusted: ())

    private init(value: String, trusted: ()) {
        self.value = value
    }
}

public struct ProcessMemoryEvidence: Equatable, Sendable {
    public let identity: ProcessObservationIdentity
    public let label: ProcessDisplayLabel
    public let residentBytes: UInt64
    public let observedAt: ClockReading

    public init(identity: ProcessObservationIdentity, label: ProcessDisplayLabel, residentBytes: UInt64, observedAt: ClockReading) {
        self.identity = identity
        self.label = label
        self.residentBytes = residentBytes
        self.observedAt = observedAt
    }
}
