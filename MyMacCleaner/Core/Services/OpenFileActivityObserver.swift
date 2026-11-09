import CleanerCore
import Darwin
import Foundation
import SafetyContract

/// C5: which scanned files a running process currently holds open, taken from one fixed,
/// read-only `lsof` listing before the scan. An open file is in-use and never a cleanup
/// candidate. If the listing is unavailable, every file in a Trash-eligible root counts as
/// open for that run (fail closed), so this can only narrow eligibility, never widen it.
struct OpenFileActivitySnapshot: ProcessActivityObserving {
    /// Nil when the listing was unavailable.
    let openPaths: Set<String>?
    let rootPaths: [DeclaredRootID: String]

    var isListingAvailable: Bool { openPaths != nil }

    func isFileOpen(rootID: DeclaredRootID, components: [String]) -> Bool {
        guard !components.isEmpty else { return false }
        guard let openPaths else { return Self.isTrashEligible(rootID) }
        guard let root = rootPaths[rootID] else { return false }
        return openPaths.contains(root + "/" + components.joined(separator: "/"))
    }

    /// A root that cannot be named is treated as Trash-eligible, so it fails closed too.
    private static func isTrashEligible(_ rootID: DeclaredRootID) -> Bool {
        guard let kind = try? GeneralMacScopeCatalog.current.rootKind(for: rootID) else { return true }
        return AdaptiveTrustSession.trashEligibleRootKinds.contains(kind)
    }
}

enum OpenFileActivityReader {
    /// Resolves the scanned roots to the real paths `lsof` reports, then reads one listing.
    static func snapshot(for kinds: [GeneralMacRootKind]) async -> OpenFileActivitySnapshot {
        let catalog = GeneralMacScopeCatalog.current
        let roots = Dictionary(kinds.compactMap { kind in
            (try? catalog.declaredRoot(for: kind)).map { ($0.id, canonicalPath(AppAdaptiveRoots.url(for: kind))) }
        }, uniquingKeysWith: { first, _ in first })
        // SAFETY-AUDIT: fixed read-only process adapter — /usr/sbin/lsof -Fn -n -P -w -b
        let listing = await ReadOnlyProcess.run(.openFiles)
        // A cancelled scan is not a broken guard, so only a real failure is logged.
        if listing == nil, !Task.isCancelled {
            SafetyDiagnosticLogger.emit(
                RedactingDiagnostic.record(
                    event: .openFileActivityUnavailable,
                    sensitiveClasses: [.command, .error]
                )
            )
        }
        return snapshot(roots: roots, listing: listing)
    }

    /// A `nil` listing (lsof missing, failed, non-zero exit, timed out or cancelled) fails closed.
    static func snapshot(roots: [DeclaredRootID: String], listing: Data?) -> OpenFileActivitySnapshot {
        OpenFileActivitySnapshot(
            openPaths: listing.map { parseOpenFilePaths($0, under: Array(roots.values)) },
            rootPaths: roots
        )
    }

    /// Parses `lsof -F n` output line by line on the raw bytes, keeping names strictly under one
    /// of `roots`; only name lines are decoded. Internal for tests.
    static func parseOpenFilePaths(_ output: Data, under roots: [String]) -> Set<String> {
        let prefixes = roots.map { $0 + "/" }
        var paths: Set<String> = []
        for line in output.split(separator: UInt8(ascii: "\n")) where line.first == UInt8(ascii: "n") {
            let name = decodeLsofName(line.dropFirst())
            if prefixes.contains(where: { name.hasPrefix($0) }) {
                paths.insert(name)
            }
        }
        return paths
    }

    /// `lsof` prints each non-printable byte as `\xNN`; decode them back to UTF-8.
    /// Anything that is not a well-formed escape stays literal. Internal for tests.
    static func decodeLsofName(_ raw: some Collection<UInt8>) -> String {
        let bytes = Array(raw)
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
