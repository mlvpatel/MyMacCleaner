import CleanerCore
import Darwin
import Foundation

/// C5: which scanned files a running process currently holds open, taken from one fixed,
/// read-only `lsof` listing before the scan. An open file is in-use and never a cleanup
/// candidate. If the listing is unavailable, nothing is marked open and activity falls back
/// to the modification-time rule, so this can only narrow eligibility.
struct OpenFileActivitySnapshot: ProcessActivityObserving {
    let openPaths: Set<String>
    let rootPaths: [DeclaredRootID: String]

    func isFileOpen(rootID: DeclaredRootID, components: [String]) -> Bool {
        guard let root = rootPaths[rootID], !components.isEmpty else { return false }
        return openPaths.contains(root + "/" + components.joined(separator: "/"))
    }
}

enum OpenFileActivityReader {
    /// Resolves the scanned roots to the real paths `lsof` reports, then reads one listing.
    static func snapshot(for kinds: [GeneralMacRootKind]) async -> OpenFileActivitySnapshot {
        let catalog = GeneralMacScopeCatalog.current
        let roots = Dictionary(kinds.compactMap { kind in
            (try? catalog.declaredRoot(for: kind)).map { ($0.id, canonicalPath(AppAdaptiveRoots.url(for: kind))) }
        }, uniquingKeysWith: { first, _ in first })
        return snapshot(roots: roots, listing: await readOpenFileListing())
    }

    /// A `nil` listing (lsof missing, failed, or non-zero exit) marks nothing open.
    static func snapshot(roots: [DeclaredRootID: String], listing: String?) -> OpenFileActivitySnapshot {
        guard let listing else {
            return OpenFileActivitySnapshot(openPaths: [], rootPaths: roots)
        }
        return OpenFileActivitySnapshot(
            openPaths: parseOpenFilePaths(listing, under: Array(roots.values)),
            rootPaths: roots
        )
    }

    // SAFETY-AUDIT: fixed read-only process adapter — /usr/sbin/lsof -Fn -n -P -w -b
    private static func readOpenFileListing() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = ["-Fn", "-n", "-P", "-w", "-b"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // Drain before waiting: a full listing is far larger than the pipe buffer.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }

    /// Parses `lsof -F n` output, keeping names strictly under one of `roots`. Internal for tests.
    static func parseOpenFilePaths(_ output: String, under roots: [String]) -> Set<String> {
        let prefixes = roots.map { $0 + "/" }
        var paths: Set<String> = []
        for line in output.split(separator: "\n") where line.first == "n" {
            let name = decodeLsofName(String(line.dropFirst()))
            if prefixes.contains(where: { name.hasPrefix($0) }) {
                paths.insert(name)
            }
        }
        return paths
    }

    /// `lsof` prints each non-printable byte as `\xNN`; decode them back to UTF-8.
    /// Anything that is not a well-formed escape stays literal. Internal for tests.
    static func decodeLsofName(_ raw: String) -> String {
        let bytes = Array(raw.utf8)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if index + 3 < bytes.count,
               bytes[index] == UInt8(ascii: "\\"),
               bytes[index + 1] == UInt8(ascii: "x"),
               let byte = UInt8(String(decoding: bytes[index + 2...index + 3], as: UTF8.self), radix: 16) {
                decoded.append(byte)
                index += 4
            } else {
                decoded.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: decoded, as: UTF8.self)
    }

    /// The real path `lsof` reports for a root (`/tmp` -> `/private/tmp`), without a trailing slash.
    static func canonicalPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
