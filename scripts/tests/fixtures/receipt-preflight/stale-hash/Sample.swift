public enum SampleKind: Equatable, Sendable {
    case alpha
}

public struct SampleRecord: Equatable, Sendable {
    public let kind: SampleKind
}

public func accept(_ record: SampleRecord?) {}
