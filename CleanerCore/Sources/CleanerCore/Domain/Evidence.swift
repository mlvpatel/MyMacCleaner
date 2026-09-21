public enum EvidenceValidationError: Error, Equatable, Sendable {
    case emptyIdentifier
    case negativeSize
    case invalidLinkCount
    case invalidRelativeLocator
    case mismatchedRootIdentity
}

public enum CoreErrorCause: String, CaseIterable, Equatable, Sendable {
    case invalidBudget
    case invalidCursor
    case invalidRoot
    case invalidLocator
    case invalidMeasurement
    case permissionDenied
    case cancelled
    case corruptMetadata
    case unsupportedLayout
    case portFailure
    case invalidObservation
    case requestChanged
    case unsupportedAdapterState
}

public enum ErrorPresentationContext: Equatable, Sendable {
    case validation
    case scan
    case detector
}

public struct UserPresentableError: Equatable, Sendable {
    public let cause: CoreErrorCause
    public let code: String
    public let localizationKey: String
    public let isRetryable: Bool
    public let context: ErrorPresentationContext

    public init(cause: CoreErrorCause) {
        self.cause = cause
        code = "cleanercore.error.\(cause.rawValue)"
        localizationKey = "cleanercore.error.\(cause.rawValue).message"
        isRetryable = cause.isRetryable
        context = cause.presentationContext
    }
}

public extension EvidenceValidationError {
    var coreErrorCause: CoreErrorCause {
        switch self {
        case .emptyIdentifier, .mismatchedRootIdentity:
            return .invalidRoot
        case .negativeSize:
            return .invalidMeasurement
        case .invalidLinkCount:
            return .invalidMeasurement
        case .invalidRelativeLocator:
            return .invalidLocator
        }
    }
}

private extension CoreErrorCause {
    var isRetryable: Bool {
        switch self {
        case .permissionDenied, .cancelled, .portFailure, .requestChanged:
            return true
        case .invalidBudget,
             .invalidCursor,
             .invalidRoot,
             .invalidLocator,
             .invalidMeasurement,
             .corruptMetadata,
             .unsupportedLayout,
             .invalidObservation,
             .unsupportedAdapterState:
            return false
        }
    }

    var presentationContext: ErrorPresentationContext {
        switch self {
        case .invalidBudget,
             .invalidCursor,
             .invalidRoot,
             .invalidLocator,
             .invalidMeasurement:
            return .validation
        case .invalidObservation, .unsupportedAdapterState:
            return .detector
        case .permissionDenied,
             .cancelled,
             .corruptMetadata,
             .unsupportedLayout,
             .portFailure,
             .requestChanged:
            return .scan
        }
    }
}

public struct DetectorID: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw EvidenceValidationError.emptyIdentifier }
        self.value = value
    }
}

public struct DetectorVersion: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw EvidenceValidationError.emptyIdentifier }
        self.value = value
    }
}

public struct DeclaredRootID: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw EvidenceValidationError.emptyIdentifier }
        self.value = value
    }
}

public struct VolumeID: Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw EvidenceValidationError.emptyIdentifier }
        self.value = value
    }
}

public struct DeclaredRoot: Equatable, Sendable {
    public let id: DeclaredRootID

    public init(id: DeclaredRootID) {
        self.id = id
    }
}

public struct RelativeLocator: Equatable, Sendable {
    public let rootID: DeclaredRootID
    public let components: [String]

    public init(rootID: DeclaredRootID, components: [String]) throws {
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            throw EvidenceValidationError.invalidRelativeLocator
        }

        self.rootID = rootID
        self.components = components
    }
}

public enum EvidenceValue<Value>: Sendable where Value: Sendable {
    case observed(Value)
    case unknown
    case unavailable
}

extension EvidenceValue: Equatable where Value: Equatable {}

public struct FileIdentityEvidence: Equatable, Sendable {
    public let device: UInt64
    public let node: UInt64

    public init(device: UInt64, node: UInt64) {
        self.device = device
        self.node = node
    }
}

public struct SizeEvidence: Equatable, Sendable {
    public let logicalBytes: EvidenceValue<Int64>
    public let allocatedBytes: EvidenceValue<Int64>

    public init(
        logicalBytes: EvidenceValue<Int64>,
        allocatedBytes: EvidenceValue<Int64>
    ) throws {
        guard Self.isNonnegative(logicalBytes), Self.isNonnegative(allocatedBytes) else {
            throw EvidenceValidationError.negativeSize
        }

        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
    }

    private static func isNonnegative(_ evidence: EvidenceValue<Int64>) -> Bool {
        switch evidence {
        case let .observed(bytes): return bytes >= 0
        case .unknown, .unavailable: return true
        }
    }
}

public struct ObservationInstant: Equatable, Comparable, Sendable {
    public let monotonicNanoseconds: UInt64

    public init(monotonicNanoseconds: UInt64) {
        self.monotonicNanoseconds = monotonicNanoseconds
    }

    public static func < (lhs: ObservationInstant, rhs: ObservationInstant) -> Bool {
        lhs.monotonicNanoseconds < rhs.monotonicNanoseconds
    }
}

public struct WallClockInstant: Equatable, Comparable, Sendable {
    public let unixNanoseconds: Int64

    public init(unixNanoseconds: Int64) {
        self.unixNanoseconds = unixNanoseconds
    }

    public static func < (lhs: WallClockInstant, rhs: WallClockInstant) -> Bool {
        lhs.unixNanoseconds < rhs.unixNanoseconds
    }
}

public struct FileModificationInstant: Equatable, Comparable, Sendable {
    public let unixNanoseconds: Int64

    public init(unixNanoseconds: Int64) {
        self.unixNanoseconds = unixNanoseconds
    }

    public static func < (lhs: FileModificationInstant, rhs: FileModificationInstant) -> Bool {
        lhs.unixNanoseconds < rhs.unixNanoseconds
    }
}

public struct ClockReading: Equatable, Sendable {
    public let observationInstant: ObservationInstant
    public let wallClockInstant: WallClockInstant

    public init(observationInstant: ObservationInstant, wallClockInstant: WallClockInstant) {
        self.observationInstant = observationInstant
        self.wallClockInstant = wallClockInstant
    }
}

public enum FileKind: String, Equatable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case package
    case other
}

public enum FindingProvenance: String, Equatable, Sendable {
    case filesystemObservation
}

public struct BoundaryEvidence: Equatable, Sendable {
    public let symlink: EvidenceValue<Bool>
    public let alias: EvidenceValue<Bool>
    public let package: EvidenceValue<Bool>
    public let mount: EvidenceValue<Bool>
    public let protectedRoot: EvidenceValue<Bool>
    public let homeBoundary: EvidenceValue<Bool>
    public let externalVolume: EvidenceValue<Bool>

    public init(
        symlink: EvidenceValue<Bool>,
        alias: EvidenceValue<Bool> = .unavailable,
        package: EvidenceValue<Bool> = .unavailable,
        mount: EvidenceValue<Bool> = .unavailable,
        protectedRoot: EvidenceValue<Bool> = .unavailable,
        homeBoundary: EvidenceValue<Bool> = .unavailable,
        externalVolume: EvidenceValue<Bool> = .unavailable
    ) {
        self.symlink = symlink
        self.alias = alias
        self.package = package
        self.mount = mount
        self.protectedRoot = protectedRoot
        self.homeBoundary = homeBoundary
        self.externalVolume = externalVolume
    }
}

public struct FindingID: Equatable, Hashable, Sendable {
    public let detectorID: DetectorID
    public let rootID: DeclaredRootID
    public let locatorComponents: [String]

    init(detectorID: DetectorID, rootID: DeclaredRootID, locator: RelativeLocator) {
        self.detectorID = detectorID
        self.rootID = rootID
        locatorComponents = locator.components
    }
}

public struct FileObservation: Equatable, Sendable {
    public let rootID: DeclaredRootID
    public let locator: RelativeLocator
    public let resourceIdentity: EvidenceValue<FileIdentityEvidence>
    public let sizes: SizeEvidence
    public let modification: EvidenceValue<FileModificationInstant>
    public let fileKind: FileKind
    public let volume: EvidenceValue<VolumeID>
    public let linkCount: EvidenceValue<UInt64>
    public let boundaries: BoundaryEvidence

    public init(
        rootID: DeclaredRootID,
        locator: RelativeLocator,
        resourceIdentity: EvidenceValue<FileIdentityEvidence>,
        sizes: SizeEvidence,
        modification: EvidenceValue<FileModificationInstant>,
        fileKind: FileKind,
        volume: EvidenceValue<VolumeID>,
        linkCount: EvidenceValue<UInt64> = .unknown,
        boundaries: BoundaryEvidence
    ) {
        self.rootID = rootID
        self.locator = locator
        self.resourceIdentity = resourceIdentity
        self.sizes = sizes
        self.modification = modification
        self.fileKind = fileKind
        self.volume = volume
        self.linkCount = linkCount
        self.boundaries = boundaries
    }
}

public struct Finding: Equatable, Sendable {
    public let id: FindingID
    public let detectorID: DetectorID
    public let detectorVersion: DetectorVersion
    public let provenance: FindingProvenance
    public let declaredRoot: DeclaredRoot
    public let locator: RelativeLocator
    public let resourceIdentity: EvidenceValue<FileIdentityEvidence>
    public let sizes: SizeEvidence
    public let modification: EvidenceValue<FileModificationInstant>
    public let fileKind: FileKind
    public let volume: EvidenceValue<VolumeID>
    public let linkCount: EvidenceValue<UInt64>
    public let boundaries: BoundaryEvidence
    public let observationInstant: ObservationInstant

    public init(
        detectorID: DetectorID,
        detectorVersion: DetectorVersion,
        provenance: FindingProvenance,
        observation: FileObservation,
        declaredRoot: DeclaredRoot,
        observationInstant: ObservationInstant
    ) throws {
        guard observation.rootID == declaredRoot.id, observation.locator.rootID == declaredRoot.id else {
            throw EvidenceValidationError.mismatchedRootIdentity
        }

        id = .init(detectorID: detectorID, rootID: declaredRoot.id, locator: observation.locator)
        self.detectorID = detectorID
        self.detectorVersion = detectorVersion
        self.provenance = provenance
        self.declaredRoot = declaredRoot
        locator = observation.locator
        resourceIdentity = observation.resourceIdentity
        sizes = observation.sizes
        modification = observation.modification
        fileKind = observation.fileKind
        volume = observation.volume
        linkCount = observation.linkCount
        boundaries = observation.boundaries
        self.observationInstant = observationInstant
    }
}
