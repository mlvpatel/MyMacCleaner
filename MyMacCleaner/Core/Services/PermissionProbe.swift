import CleanerCore
import Darwin
import Foundation

// MARK: - Permission Probe

/// Read-only, content-blind check of whether a permission-gated filesystem location can be
/// opened for reading. It attempts `open()`/`close()` and observes success or failure without
/// ever reading the location's contents — matching the app's point-of-use permission approach.
///
/// Shared by ``PermissionsService`` (Full Disk Access detection) and `AdaptiveTrustSession`
/// (permission-gap projection). Injected so tests can drive permission state deterministically.
protocol PermissionProbing: Sendable {
    /// `true` when the path opens for reading. The descriptor is closed immediately and no bytes
    /// are read. `false` on any failure (permission denied, missing, or not openable).
    func canOpenForReading(atPath path: String) -> Bool
}

/// Production probe: opens the path read-only, closes it, and reports whether the open succeeded —
/// never reading contents. Full Disk Access gates the `open()` of a protected path, so a
/// successful open is a reliable, content-blind signal that access is granted.
struct POSIXPermissionProbe: PermissionProbing {
    func canOpenForReading(atPath path: String) -> Bool {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}

// MARK: - Gated Locations

/// Fixed, home-relative locations whose openability reflects a specific permission.
enum PermissionGatedLocation {
    /// A Full-Disk-Access-gated path. TCC gates `open()` on the user's TCC database, so its
    /// openability is the canonical, content-blind FDA signal.
    static var fullDiskAccessProbePath: String {
        NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
    }

    /// The user Library cache root the cleaner reads during a scan.
    static var userLibraryCachesPath: String {
        NSHomeDirectory() + "/Library/Caches"
    }
}

// MARK: - Assessment

/// Derives permission state from a ``PermissionProbing``. The Full Disk Access signal and the
/// permission-gap projection share the same open/close probe, so they can never disagree.
enum PermissionAssessment {
    /// Full Disk Access is present when the FDA-gated path opens for reading.
    static func hasFullDiskAccess(using probe: any PermissionProbing) -> Bool {
        probe.canOpenForReading(atPath: PermissionGatedLocation.fullDiskAccessProbePath)
    }

    /// Permission gaps derived from real openability: no Full Disk Access -> `.fullDiskAccess`;
    /// an unreadable `~/Library/Caches` -> `.userLibrary`; both fine -> `[]`.
    static func permissionGaps(using probe: any PermissionProbing) -> [AdaptivePermissionGap] {
        var gaps: [AdaptivePermissionGap] = []
        if !hasFullDiskAccess(using: probe) {
            gaps.append(.fullDiskAccess)
        }
        if !probe.canOpenForReading(atPath: PermissionGatedLocation.userLibraryCachesPath) {
            gaps.append(.userLibrary)
        }
        return gaps
    }
}
