import Foundation
import Testing

@testable import CleanerCore

/// Synthetic approved-plan, fresh/stale, owner, and destination builders.
/// Identifiers are fixed test tokens. No live home, model store, or Trash.
enum TrashExecutionFixtureFactory {
    static let seed = 6_03_01

    static func approvedPlan(
        component: String,
        bytes: Int64 = 4_096,
        node: UInt64
    ) throws -> ReviewPlan {
        try PolicyPlanFixtureFactory.reviewPlan(candidates: [
            try PolicyPlanFixtureFactory.eligibleCache(component: component, bytes: bytes, node: node)
        ])
    }

    static func approvedTwoTargetPlan() throws -> ReviewPlan {
        try PolicyPlanFixtureFactory.reviewPlan(candidates: [
            try PolicyPlanFixtureFactory.eligibleCache(component: "h-a.bin", bytes: 4_096, node: 701),
            try PolicyPlanFixtureFactory.eligibleCache(component: "h-b.bin", bytes: 8_192, node: 702),
        ])
    }

    static func approvedThreeTargetPlan() throws -> ReviewPlan {
        try PolicyPlanFixtureFactory.reviewPlan(candidates: [
            try PolicyPlanFixtureFactory.eligibleCache(component: "h-a.bin", bytes: 4_096, node: 711),
            try PolicyPlanFixtureFactory.eligibleCache(component: "h-b.bin", bytes: 8_192, node: 712),
            try PolicyPlanFixtureFactory.eligibleCache(component: "h-c.bin", bytes: 4_096, node: 713),
        ])
    }

    static func matching(_ plan: ReviewPlan, index: Int = 0) -> FreshTargetEvidence {
        FreshTargetEvidence.matching(plan.targets[index])
    }

    static func copy(
        _ base: FreshTargetEvidence,
        stableIdentity: StableFindingIdentity? = nil,
        detectorID: DetectorID? = nil,
        detectorVersion: DetectorVersion? = nil,
        declaredRootID: DeclaredRootID? = nil,
        locatorComponents: [String]? = nil,
        resourceIdentity: FileIdentityEvidence? = nil,
        volume: VolumeID? = nil,
        fileKind: FileKind? = nil,
        logicalBytes: Int64? = nil,
        allocatedBytes: Int64? = nil,
        conservativeReclaimableBytes: Int64? = nil,
        modificationUnixNanoseconds: Int64? = nil,
        semanticOwner: PolicySemanticOwner? = nil,
        symlink: Bool? = nil,
        alias: Bool? = nil,
        package: Bool? = nil,
        mount: Bool? = nil,
        completeness: GeneralMacEvidenceCompleteness? = nil
    ) -> FreshTargetEvidence {
        FreshTargetEvidence(
            stableIdentity: stableIdentity ?? base.stableIdentity,
            detectorID: detectorID ?? base.detectorID,
            detectorVersion: detectorVersion ?? base.detectorVersion,
            declaredRootID: declaredRootID ?? base.declaredRootID,
            locatorComponents: locatorComponents ?? base.locatorComponents,
            resourceIdentity: resourceIdentity ?? base.resourceIdentity,
            volume: volume ?? base.volume,
            fileKind: fileKind ?? base.fileKind,
            logicalBytes: logicalBytes ?? base.logicalBytes,
            allocatedBytes: allocatedBytes ?? base.allocatedBytes,
            conservativeReclaimableBytes: conservativeReclaimableBytes ?? base.conservativeReclaimableBytes,
            modificationUnixNanoseconds: modificationUnixNanoseconds ?? base.modificationUnixNanoseconds,
            semanticOwner: semanticOwner ?? base.semanticOwner,
            symlink: symlink ?? base.symlink,
            alias: alias ?? base.alias,
            package: package ?? base.package,
            mount: mount ?? base.mount,
            completeness: completeness ?? base.completeness
        )
    }

    static func collisionDestination() -> URL {
        URL(fileURLWithPath: "/tmp/mmc-scripted-trash/hostile.bin 2")
    }

    static func scriptedRoot() -> URL {
        URL(fileURLWithPath: "/tmp/mmc-scripted-root")
    }
}

final class ScriptedNativeTrash: @unchecked Sendable {
    private(set) var calls = 0
    private(set) var lastInput: URL?
    var result: URL? = TrashExecutionFixtureFactory.collisionDestination()
    var error: Error?

    func invoke(_ url: URL) throws -> URL? {
        calls += 1
        lastInput = url
        if let error {
            throw error
        }
        return result
    }
}
