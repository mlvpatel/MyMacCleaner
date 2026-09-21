public enum ContentReadLimitsError: Error, Equatable, Sendable {
    case invalidLimit
}

public struct ContentReadLimits: Equatable, Sendable {
    public static let current = ContentReadLimits(
        uncheckedMaximumCandidatesPerScan: 4_096,
        maximumChunkBytes: 1_048_576,
        maximumBytesPerFile: 17_179_869_184,
        maximumBytesPerScan: 68_719_476_736
    )

    public let maximumCandidatesPerScan: Int
    public let maximumChunkBytes: Int
    public let maximumBytesPerFile: Int64
    public let maximumBytesPerScan: Int64

    public init(
        maximumCandidatesPerScan: Int,
        maximumChunkBytes: Int,
        maximumBytesPerFile: Int64,
        maximumBytesPerScan: Int64
    ) throws {
        guard maximumCandidatesPerScan > 0,
              maximumCandidatesPerScan <= Self.currentMaximumCandidates,
              maximumChunkBytes > 0,
              maximumChunkBytes <= Self.currentMaximumChunkBytes,
              maximumBytesPerFile > 0,
              maximumBytesPerFile <= Self.currentMaximumBytesPerFile,
              maximumBytesPerScan > 0,
              maximumBytesPerScan <= Self.currentMaximumBytesPerScan else {
            throw ContentReadLimitsError.invalidLimit
        }
        self.maximumCandidatesPerScan = maximumCandidatesPerScan
        self.maximumChunkBytes = maximumChunkBytes
        self.maximumBytesPerFile = maximumBytesPerFile
        self.maximumBytesPerScan = maximumBytesPerScan
    }

    private init(
        uncheckedMaximumCandidatesPerScan: Int,
        maximumChunkBytes: Int,
        maximumBytesPerFile: Int64,
        maximumBytesPerScan: Int64
    ) {
        maximumCandidatesPerScan = uncheckedMaximumCandidatesPerScan
        self.maximumChunkBytes = maximumChunkBytes
        self.maximumBytesPerFile = maximumBytesPerFile
        self.maximumBytesPerScan = maximumBytesPerScan
    }

    private static let currentMaximumCandidates = 4_096
    private static let currentMaximumChunkBytes = 1_048_576
    private static let currentMaximumBytesPerFile: Int64 = 17_179_869_184
    private static let currentMaximumBytesPerScan: Int64 = 68_719_476_736
}

public struct ContentResourceIdentity: Equatable, Hashable, Sendable {
    public let volume: VolumeID
    public let identity: FileIdentityEvidence

    public init(volume: VolumeID, identity: FileIdentityEvidence) {
        self.volume = volume
        self.identity = identity
    }

    public static func == (lhs: ContentResourceIdentity, rhs: ContentResourceIdentity) -> Bool {
        lhs.volume == rhs.volume
            && lhs.identity.device == rhs.identity.device
            && lhs.identity.node == rhs.identity.node
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(volume)
        hasher.combine(identity.device)
        hasher.combine(identity.node)
    }
}

public enum ContentCancellationCheckpoint: String, CaseIterable, Equatable, Sendable {
    case beforeOpen
    case beforeEachChunk
    case beforeFinalization
    case beforePublishing
}

public struct ContentEvidenceRequest: Equatable, Sendable {
    public let declaredRootID: DeclaredRootID
    public let locator: RelativeLocator
    public let resource: ContentResourceIdentity
    public let expectedLogicalBytes: Int64
    public let limits: ContentReadLimits
    public let cancellationCheckpoints: [ContentCancellationCheckpoint]

    public init(
        declaredRootID: DeclaredRootID,
        locator: RelativeLocator,
        resource: ContentResourceIdentity,
        expectedLogicalBytes: Int64,
        limits: ContentReadLimits
    ) throws {
        guard declaredRootID == locator.rootID else {
            throw EvidenceValidationError.mismatchedRootIdentity
        }
        guard expectedLogicalBytes >= 0,
              expectedLogicalBytes <= limits.maximumBytesPerFile,
              expectedLogicalBytes <= limits.maximumBytesPerScan else {
            throw ContentReadLimitsError.invalidLimit
        }
        self.declaredRootID = declaredRootID
        self.locator = locator
        self.resource = resource
        self.expectedLogicalBytes = expectedLogicalBytes
        self.limits = limits
        cancellationCheckpoints = ContentCancellationCheckpoint.allCases
    }
}

public enum ContentDigestError: Error, Equatable, Sendable {
    case invalidDigestLength
}

public struct ContentDigest: Equatable, Hashable, Sendable {
    private let opaqueBytes: [UInt8]

    public init(opaqueBytes: [UInt8]) throws {
        guard opaqueBytes.count == 32 else { throw ContentDigestError.invalidDigestLength }
        self.opaqueBytes = opaqueBytes
    }
}

public enum ContentEvidenceOutcomeCode: String, CaseIterable, Equatable, Sendable {
    case complete
    case denied
    case partial
    case corrupt
    case cancelled
    case budgetExceeded
}

public enum ContentEvidenceOutcome: Equatable, Sendable {
    case complete(ContentDigest)
    case denied
    case partial
    case corrupt
    case cancelled
    case budgetExceeded

    public var code: ContentEvidenceOutcomeCode {
        switch self {
        case .complete: return .complete
        case .denied: return .denied
        case .partial: return .partial
        case .corrupt: return .corrupt
        case .cancelled: return .cancelled
        case .budgetExceeded: return .budgetExceeded
        }
    }
}

/// One opaque, single-owner aggregate-budget scope. A new scan must request a new session.
public protocol ContentEvidenceSession: Sendable {
    func contentEvidence(for request: ContentEvidenceRequest) async -> ContentEvidenceOutcome
}

/// Creates isolated content-evidence sessions; the factory itself owns no scan counters.
public protocol ContentEvidencePort: Sendable {
    func beginSession(limits: ContentReadLimits) async -> any ContentEvidenceSession
}
