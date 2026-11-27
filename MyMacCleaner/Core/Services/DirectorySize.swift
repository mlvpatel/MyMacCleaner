import Foundation

/// The app's one directory-sizing walk, shared by Applications, Orphaned Files, Browser Privacy
/// and the developer inventory.
enum DirectorySize {
    /// Entries walked before sizing stops, so one pathological tree cannot stall a scan.
    static let defaultMaxEntries = 500_000

    /// Content-blind allocated bytes under `directory`: sums allocation metadata of regular files
    /// (hidden ones included), never opens a file, and never follows a symlink out of the tree.
    /// Stops at `maxEntries` entries or when the calling task is cancelled, returning what it has
    /// summed so far. Nil when the directory cannot be enumerated.
    static func allocatedBytes(at directory: URL, maxEntries: Int = defaultMaxEntries) -> Int64? {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return nil }

        var total: Int64 = 0
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited > maxEntries || Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
