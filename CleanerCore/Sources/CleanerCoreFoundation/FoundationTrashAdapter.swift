import CleanerCore
import Foundation

public struct ReturnedTrashURL: Equatable, Sendable {
    public let absoluteString: String

    init(_ url: URL) {
        absoluteString = url.absoluteString
    }
}

/// Result of a final, in-adapter re-observation of a move target, performed immediately before the
/// single native trash call. Compared against the frozen approved evidence so a use-after-check
/// swap (a different inode, a truncated/grown file, a changed modification time, or a symlink
/// spliced into the path) is caught as late as possible. It can only turn a move into a skip —
/// never widen what may be trashed.
public enum LeafIdentityProbe: Equatable, Sendable {
    case observed(device: UInt64, node: UInt64, logicalBytes: Int64, modificationUnixNanoseconds: Int64)
    /// A component along the resolved path (including the leaf) is a symlink.
    case symlinkEncountered
    /// The target could not be observed (missing, unreadable, or an out-of-range attribute).
    case unavailable
}

/// Sole v1 mutation owner. A residual URL check/use race remains between the final re-observation
/// below and the single native call; the interval is narrowed to that gap but is not atomic.
public struct FoundationTrashAdapter: TrashExecutionPort, @unchecked Sendable {
    public typealias Destination = ReturnedTrashURL

    private let revalidator: FreshEvidenceRevalidator
    private let resolveRoot: @Sendable (DeclaredRootID) -> URL?
    private let nativeTrash: (URL) throws -> URL?
    private let identityProbe: (URL, [String]) -> LeafIdentityProbe

    public init(
        fileManager: FileManager = .init(),
        revalidator: FreshEvidenceRevalidator = .init(),
        nativeTrash: ((URL) throws -> URL?)? = nil,
        identityProbe: ((URL, [String]) -> LeafIdentityProbe)? = nil,
        resolveRoot: @escaping @Sendable (DeclaredRootID) -> URL?
    ) {
        self.revalidator = revalidator
        self.resolveRoot = resolveRoot
        self.identityProbe = identityProbe ?? { root, components in
            Self.nativeProbe(root: root, components: components, fileManager: fileManager)
        }
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
        // Final in-adapter re-observation immediately before the single native move.
        if let reason = finalIdentityMismatch(root: root, operation: operation) {
            return .skippedStale(reason)
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

    private func finalIdentityMismatch(root: URL, operation: MoveToTrash) -> TrashStaleReason? {
        switch identityProbe(root, operation.locatorComponents) {
        case .unavailable:
            return .identityChanged
        case .symlinkEncountered:
            return .topologyChanged
        case let .observed(device, node, logicalBytes, modificationUnixNanoseconds):
            let approved = operation.approvedResourceIdentity
            if device != approved.device || node != approved.node {
                return .identityChanged
            }
            if logicalBytes != operation.approvedLogicalBytes {
                return .sizeChanged
            }
            if modificationUnixNanoseconds != operation.approvedModificationUnixNanoseconds {
                return .modificationChanged
            }
            return nil
        }
    }

    /// Walks each locator component from the resolved root, rejecting any symlinked component so a
    /// spliced link cannot redirect the move. The leaf's device/node/size/modification are read
    /// through the same Foundation attribute/resource keys the scanner uses to build the frozen
    /// evidence (`.systemNumber`, `.systemFileNumber`, `.fileSizeKey`, `.contentModificationDate`),
    /// so an unchanged file compares equal. Uses the injected `fileManager` — never the ambient
    /// `.default` — and Darwin is intentionally not imported here to keep the mutation path minimal.
    static func nativeProbe(root: URL, components: [String], fileManager: FileManager) -> LeafIdentityProbe {
        guard !components.isEmpty else { return .unavailable }
        var current = root
        for (index, component) in components.enumerated() {
            current.appendPathComponent(component)
            let isSymbolicLink: Bool?
            do {
                isSymbolicLink = try current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
            } catch {
                return .unavailable
            }
            guard isSymbolicLink == false else {
                return isSymbolicLink == nil ? .unavailable : .symlinkEncountered
            }
            guard index == components.count - 1 else { continue }
            return leafIdentity(at: current, fileManager: fileManager)
        }
        return .unavailable
    }

    private static func leafIdentity(at url: URL, fileManager: FileManager) -> LeafIdentityProbe {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            return .unavailable
        }
        // A link added since the scan keeps inode, size and mtime, so the link count is checked too.
        guard let device = numericValue(attributes[.systemNumber]),
              let node = numericValue(attributes[.systemFileNumber]),
              numericValue(attributes[.referenceCount]) == 1 else {
            return .unavailable
        }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        } catch {
            return .unavailable
        }
        guard let fileSize = values.fileSize, fileSize >= 0,
              let modificationUnixNanoseconds = modificationUnixNanoseconds(values.contentModificationDate) else {
            return .unavailable
        }
        return .observed(
            device: device,
            node: node,
            logicalBytes: Int64(fileSize),
            modificationUnixNanoseconds: modificationUnixNanoseconds
        )
    }

    /// Matches the scanner's derivation: an NSNumber converted to a non-negative UInt64.
    private static func numericValue(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue >= 0,
              number.doubleValue <= Double(UInt64.max) else {
            return nil
        }
        return number.uint64Value
    }

    /// Matches how the scanner derives `modificationUnixNanoseconds` from a `Date`
    /// (`timeIntervalSince1970 * 1e9`), not from `st_mtimespec`, so an unchanged file compares
    /// equal instead of false-mismatching on nanosecond rounding.
    private static func modificationUnixNanoseconds(_ date: Date?) -> Int64? {
        guard let date else { return nil }
        let nanoseconds = date.timeIntervalSince1970 * 1_000_000_000
        guard nanoseconds.isFinite,
              nanoseconds >= Double(Int64.min),
              nanoseconds <= Double(Int64.max) else {
            return nil
        }
        return Int64(nanoseconds)
    }
}
