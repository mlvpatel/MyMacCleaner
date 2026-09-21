import Foundation

// MARK: - Trash Inventory

/// What is known about the user's Trash. Reading is inventory-only; nothing is changed.
enum TrashInventory: Equatable, Sendable {
    case unknown
    /// The Trash folder could not be read, typically because Full Disk Access is not granted.
    case unavailable
    case measured(bytes: Int64)
}

enum TrashInventoryReader {
    /// Entries between cancellation checks while summing sizes.
    private static let cancellationInterval = 500

    static var defaultTrashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    }

    /// Sums allocated sizes under `url` off the main actor.
    static func measure(at url: URL = defaultTrashURL) async -> TrashInventory {
        let fileManager = FileManager.default
        // Listing the folder is the permission probe: it fails when TCC denies access.
        guard (try? fileManager.contentsOfDirectory(atPath: url.path)) != nil else {
            return .unavailable
        }

        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return .unavailable
        }

        var total: Int64 = 0
        var visited = 0
        while let itemURL = enumerator.nextObject() as? URL {
            visited += 1
            if visited % cancellationInterval == 0, Task.isCancelled {
                return .unknown
            }
            guard let values = try? itemURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return Task.isCancelled ? .unknown : .measured(bytes: total)
    }
}
