import CleanerCore
import Foundation

public struct ReturnedTrashURL: Equatable, Sendable {
    public let absoluteString: String

    init(_ url: URL) {
        absoluteString = url.absoluteString
    }
}

/// Sole v1 mutation owner. Residual URL check/use race remains between the last
/// fresh comparison and this single native call; the interval is not atomic.
public struct FoundationTrashAdapter: TrashExecutionPort, @unchecked Sendable {
    public typealias Destination = ReturnedTrashURL

    private let revalidator: FreshEvidenceRevalidator
    private let resolveRoot: @Sendable (DeclaredRootID) -> URL?
    private let nativeTrash: (URL) throws -> URL?

    public init(
        fileManager: FileManager = .init(),
        revalidator: FreshEvidenceRevalidator = .init(),
        nativeTrash: ((URL) throws -> URL?)? = nil,
        resolveRoot: @escaping @Sendable (DeclaredRootID) -> URL?
    ) {
        self.revalidator = revalidator
        self.resolveRoot = resolveRoot
        self.nativeTrash = nativeTrash ?? { url in
            var resulting: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        }
    }

    public func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<ReturnedTrashURL> {
        if let reason = revalidator.validate(operation: operation, fresh: fresh) {
            return .skippedStale(reason)
        }
        guard let root = resolveRoot(operation.declaredRootID) else {
            return .skippedStale(.rootChanged)
        }
        var url = root
        for component in operation.locatorComponents {
            url.appendPathComponent(component)
        }
        let returned: URL?
        do {
            returned = try nativeTrash(url)
        } catch {
            return .failed(.nativeMoveFailed)
        }
        guard let returned else {
            return .failed(.missingReturnedLocation)
        }
        return .moved(destination: ReturnedTrashURL(returned))
    }
}
