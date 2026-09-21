public enum PlanDigestError: Error, Equatable, Sendable {
    case invalidDigestLength
}

public struct PlanDigest: Equatable, Hashable, Sendable {
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == 32 else { throw PlanDigestError.invalidDigestLength }
        self.bytes = bytes
    }
}

public protocol PlanDigesting: Sendable {
    func digest(canonicalBytes: [UInt8]) throws -> PlanDigest
}
