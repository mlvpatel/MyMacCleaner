public protocol PolicyPort: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func evaluate(_ input: Input) async -> Output
}

public protocol ExecutionPort: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func execute(_ input: Input) async -> Output
}

public protocol ReceiptPort: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func record(_ input: Input) async -> Output
}
