import CleanerCore
import Foundation

/// Maps the sole native Trash adapter onto the receipt execution port.
/// Never calls the native Trash API itself; `FoundationTrashAdapter` is its only caller.
public struct FoundationReceiptExecutionAdapter: ReceiptExecutionConsuming, Sendable {
    private let adapter: FoundationTrashAdapter

    public init(adapter: FoundationTrashAdapter) {
        self.adapter = adapter
    }

    public func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<PrivateRecoveryDestination> {
        switch adapter.revalidateAndMove(operation, fresh: fresh) {
        case let .moved(destination):
            return .moved(destination: PrivateRecoveryDestination(token: destination.absoluteString))
        case let .skippedStale(reason):
            return .skippedStale(reason)
        case let .failed(failure):
            return .failed(failure)
        case .cancelled:
            return .cancelled
        }
    }
}
