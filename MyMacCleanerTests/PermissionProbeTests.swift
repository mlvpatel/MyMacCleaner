import Testing
import Foundation
import CleanerCore
@testable import MyMacCleaner

/// Deterministic, content-blind probe: a path "opens" iff it is in `openablePaths`.
/// Lets the FDA derivation (D6) and gap mapping (B5) be tested without touching the real
/// filesystem or the user's actual permission state.
private struct StubPermissionProbe: PermissionProbing {
    let openablePaths: Set<String>

    func canOpenForReading(atPath path: String) -> Bool {
        openablePaths.contains(path)
    }
}

// MARK: - D6: Full Disk Access derived from the open/close probe

@Suite("Permission probe — Full Disk Access (D6)")
struct PermissionProbeFullDiskAccessTests {
    @Test("Full Disk Access is granted only when the FDA-gated path opens")
    func fullDiskAccessDerivedFromProbe() {
        let fdaPath = PermissionGatedLocation.fullDiskAccessProbePath
        let granted = StubPermissionProbe(openablePaths: [fdaPath])
        let denied = StubPermissionProbe(openablePaths: [])

        #expect(PermissionAssessment.hasFullDiskAccess(using: granted))
        #expect(PermissionAssessment.hasFullDiskAccess(using: denied) == false)
    }

    @Test("PermissionsService derives hasFullDiskAccess from the injected probe")
    @MainActor
    func serviceReflectsProbe() {
        let fdaPath = PermissionGatedLocation.fullDiskAccessProbePath
        let granted = PermissionsService(probe: StubPermissionProbe(openablePaths: [fdaPath]))
        let denied = PermissionsService(probe: StubPermissionProbe(openablePaths: []))

        #expect(granted.hasFullDiskAccess)
        #expect(denied.hasFullDiskAccess == false)
    }
}

// MARK: - B5: permissionGaps mapping from the same probe

@Suite("Permission probe — permission gaps (B5)")
struct PermissionGapMappingTests {
    private static let fdaPath = PermissionGatedLocation.fullDiskAccessProbePath
    private static let cachesPath = PermissionGatedLocation.userLibraryCachesPath

    @Test("FDA absent yields a fullDiskAccess gap")
    func fullDiskAccessAbsentYieldsGap() {
        // Caches readable, FDA path not openable -> only the FDA gap.
        let probe = StubPermissionProbe(openablePaths: [Self.cachesPath])

        let gaps = PermissionAssessment.permissionGaps(using: probe)

        #expect(gaps.contains(.fullDiskAccess))
        #expect(gaps.contains(.userLibrary) == false)
    }

    @Test("Unreadable ~/Library/Caches yields a userLibrary gap")
    func unreadableCachesYieldsGap() {
        // FDA granted, caches path not openable -> only the userLibrary gap.
        let probe = StubPermissionProbe(openablePaths: [Self.fdaPath])

        let gaps = PermissionAssessment.permissionGaps(using: probe)

        #expect(gaps.contains(.userLibrary))
        #expect(gaps.contains(.fullDiskAccess) == false)
    }

    @Test("Both accessible yields no gaps")
    func bothAccessibleYieldsNoGaps() {
        let probe = StubPermissionProbe(openablePaths: [Self.fdaPath, Self.cachesPath])

        #expect(PermissionAssessment.permissionGaps(using: probe).isEmpty)
    }

    @Test("Both inaccessible yields both gaps")
    func bothInaccessibleYieldsBothGaps() {
        let probe = StubPermissionProbe(openablePaths: [])

        let gaps = PermissionAssessment.permissionGaps(using: probe)

        #expect(gaps.contains(.fullDiskAccess))
        #expect(gaps.contains(.userLibrary))
    }
}
