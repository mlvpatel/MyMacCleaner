import AppKit
import CleanerCore
import Foundation

public struct FinderReceiptRevealAdapter: Sendable {
    private let resolve: @Sendable (ReceiptID, ReceiptItemID) async -> Result<URL, ReceiptPersistenceError>
    private let isReachable: @Sendable (URL) -> Bool
    private let select: @Sendable ([URL]) -> Bool

    public init(
        resolve: @escaping @Sendable (ReceiptID, ReceiptItemID) async -> Result<URL, ReceiptPersistenceError>,
        isReachable: @escaping @Sendable (URL) -> Bool,
        select: @escaping @Sendable ([URL]) -> Bool
    ) {
        self.resolve = resolve
        self.isReachable = isReachable
        self.select = select
    }

    public static func live(store: AppSupportReceiptStore) -> Self {
        Self(
            resolve: { receipt, item in
                await store.privateMovedDestination(receipt: receipt, item: item)
            },
            isReachable: { url in
                do {
                    return try url.checkResourceIsReachable()
                } catch {
                    return false
                }
            },
            select: { urls in
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                return true
            }
        )
    }

    public func reveal(
        receipt: ReceiptID,
        item: ReceiptItemID
    ) async -> ReceiptRevealOutcome {
        switch await resolve(receipt, item) {
        case .failure:
            return .unavailable
        case let .success(destination):
            guard isReachable(destination) else {
                return .unavailable
            }
            guard select([destination]) else {
                return .unavailable
            }
            return .revealRequested
        }
    }
}
