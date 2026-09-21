import Testing

@testable import CleanerCore

/// Synthetic policy/plan builders. Identifiers are fixed test tokens only.
enum PolicyPlanFixtureFactory {
    static let seed = 5_03_01
    static let createdAt = WallClockInstant(unixNanoseconds: 1_000_000_000)
    static let lifetimeNanoseconds: Int64 = 900_000_000_000

    static func clockReading() -> ClockReading {
        .init(
            observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
            wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
        )
    }

    static func versionContext(
        appPlanVersion: String = "5.0.0",
        policyVersion: String = "policy-1",
        encodingVersion: UInt16 = 1
    ) throws -> ReviewPlanVersionContext {
        try .init(
            appPlanVersion: appPlanVersion,
            policyVersion: policyVersion,
            detectorCatalogVersion: GeneralMacScopeCatalog.current.version.value,
            encodingVersion: encodingVersion
        )
    }

    static func launchSession(_ value: String = "launch-a") throws -> ReviewPlanLaunchSession {
        try .init(value)
    }

    static func finding(
        scope: GeneralMacRootKind = .userLibraryCaches,
        components: [String],
        bytes: Int64 = 4_096,
        complete: Bool = true,
        symlink: Bool = false,
        node: UInt64 = 42
    ) throws -> GeneralMacFinding {
        let catalog = GeneralMacScopeCatalog.current
        let root = try catalog.declaredRoot(for: scope)
        let observation = try FileObservation(
            rootID: root.id,
            locator: .init(rootID: root.id, components: components),
            resourceIdentity: complete ? .observed(.init(device: 7, node: node)) : .unavailable,
            sizes: .init(logicalBytes: .observed(bytes), allocatedBytes: .observed(bytes)),
            modification: .observed(.init(unixNanoseconds: 1)),
            fileKind: .regularFile,
            volume: .observed(try .init("golden-volume")),
            linkCount: .observed(1),
            boundaries: .init(
                symlink: .observed(symlink),
                alias: .observed(false),
                package: .observed(false),
                mount: .observed(false),
                protectedRoot: .observed(false),
                homeBoundary: .observed(false),
                externalVolume: .observed(false)
            )
        )
        return try #require(try GeneralMacEvidenceDetector(scope: scope)
            .makeFinding(
                from: observation,
                request: catalog.scanRequest(for: [scope]),
                clockReading: clockReading()
            )
            .get())
    }

    static func eligibleCache(component: String, bytes: Int64, node: UInt64) throws -> EligibleCandidate {
        let evaluation = PolicyEvaluator().evaluate(
            try finding(
                components: ["com.apple.iconservices.store", component],
                bytes: bytes,
                node: node
            )
        )
        return try #require(evaluation.candidate)
    }

    static func reviewPlan(
        candidates: [EligibleCandidate],
        digesting: PlanDigesting = StaticGoldenDigesting(),
        session: ReviewPlanLaunchSession? = nil,
        context: ReviewPlanVersionContext? = nil,
        createdAt: WallClockInstant = createdAt
    ) throws -> ReviewPlan {
        try ReviewPlan.build(
            draft: .init(
                selectedCandidates: candidates,
                versionContext: try context ?? versionContext(),
                launchSession: try session ?? launchSession(),
                createdAt: createdAt
            ),
            digesting: digesting
        )
    }

    static func matchingApproval(_ plan: ReviewPlan) -> ApprovalAttestation {
        .init(
            approvedDigest: plan.digest,
            approvedAt: .init(unixNanoseconds: createdAt.unixNanoseconds + 1),
            launchSession: plan.launchSession
        )
    }

    static func matchingContext(
        _ plan: ReviewPlan,
        now: WallClockInstant? = nil,
        launchSession: ReviewPlanLaunchSession? = nil,
        versionContext: ReviewPlanVersionContext? = nil,
        displayedDigest: PlanDigest? = nil,
        currentTargets: [ReviewPlanTarget]? = nil
    ) -> ApprovalContext {
        .init(
            launchSession: launchSession ?? plan.launchSession,
            now: now ?? .init(unixNanoseconds: plan.expiresAt.unixNanoseconds - 1),
            versionContext: versionContext ?? plan.versionContext,
            displayedDigest: displayedDigest ?? plan.digest,
            currentTargets: currentTargets ?? plan.targets
        )
    }
}

struct StaticGoldenDigesting: PlanDigesting {
    func digest(canonicalBytes _: [UInt8]) throws -> PlanDigest {
        try .init(bytes: Array(repeating: 3, count: 32))
    }
}

final class ZeroEffectRecorder: @unchecked Sendable {
    private(set) var calls = 0

    func record() {
        calls += 1
    }
}
