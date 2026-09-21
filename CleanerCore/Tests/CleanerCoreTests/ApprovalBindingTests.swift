import Testing

@testable import CleanerCore

@Suite("Launch-bound approval validity")
struct ApprovalBindingTests {
    @Test
    func matchingApprovalIsValidOnlyStrictlyBeforeExpiry() throws {
        let plan = try approvalPlan()
        let attestation = ApprovalAttestation(
            approvedDigest: plan.digest,
            approvedAt: .init(unixNanoseconds: 2_000_000_000),
            launchSession: plan.launchSession
        )

        #expect(ApprovalValidity.evaluate(
            approval: attestation,
            plan: plan,
            current: .init(
                launchSession: plan.launchSession,
                now: .init(unixNanoseconds: plan.expiresAt.unixNanoseconds - 1),
                versionContext: plan.versionContext,
                displayedDigest: plan.digest,
                currentTargets: plan.targets
            )
        ) == .validForReview)
        #expect(ApprovalValidity.evaluate(
            approval: attestation,
            plan: plan,
            current: .init(
                launchSession: plan.launchSession,
                now: plan.expiresAt,
                versionContext: plan.versionContext,
                displayedDigest: plan.digest,
                currentTargets: plan.targets
            )
        ) == .invalid(.expired))
    }

    @Test
    func everyRequiredInvalidationReasonIsClosedAndOrdered() throws {
        let plan = try approvalPlan()
        let approval = ApprovalAttestation(
            approvedDigest: plan.digest,
            approvedAt: .init(unixNanoseconds: 2_000_000_000),
            launchSession: plan.launchSession
        )

        #expect(ApprovalValidity.evaluate(approval: nil, plan: plan, current: plan.approvalContext()) == .invalid(.missingApproval))
        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: plan.approvalContext(launchSession: try .init("other-launch"))
        ) == .invalid(.sessionChanged))
        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: plan.approvalContext(now: plan.expiresAt)
        ) == .invalid(.expired))
        #expect(ApprovalValidity.evaluate(
            approval: .init(
                approvedDigest: plan.digest,
                approvedAt: plan.expiresAt,
                launchSession: plan.launchSession
            ),
            plan: plan,
            current: plan.approvalContext()
        ) == .invalid(.expired))
        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: plan.approvalContext(versionContext: try .init(
                appPlanVersion: "5.0.1",
                policyVersion: plan.versionContext.policyVersion,
                detectorCatalogVersion: plan.versionContext.detectorCatalogVersion,
                encodingVersion: plan.versionContext.encodingVersion
            ))
        ) == .invalid(.contextChanged))
        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: plan.approvalContext(displayedDigest: try .init(bytes: Array(repeating: 9, count: 32)))
        ) == .invalid(.planDigestChanged))
        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: plan.approvalContext(currentTargets: [])
        ) == .invalid(.evidenceChanged))

        let precedenceContext = plan.approvalContext(
            launchSession: try .init("other-launch"),
            now: plan.expiresAt,
            displayedDigest: try .init(bytes: Array(repeating: 9, count: 32)),
            currentTargets: []
        )
        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: precedenceContext
        ) == .invalid(.sessionChanged))
    }
}

private func approvalPlan() throws -> ReviewPlan {
    let candidate = try approvalCandidate(component: "approval.bin", bytes: 4_096)
    return try ReviewPlan.build(
        draft: .init(
            selectedCandidates: [candidate],
            versionContext: try .init(
                appPlanVersion: "5.0.0",
                policyVersion: "policy-1",
                detectorCatalogVersion: GeneralMacScopeCatalog.current.version.value,
                encodingVersion: 1
            ),
            launchSession: try .init("launch-a"),
            createdAt: .init(unixNanoseconds: 1_000_000_000)
        ),
        digesting: StaticPlanDigesting()
    )
}

private struct StaticPlanDigesting: PlanDigesting {
    func digest(canonicalBytes _: [UInt8]) throws -> PlanDigest {
        try .init(bytes: Array(repeating: 7, count: 32))
    }
}

private extension ReviewPlan {
    func approvalContext(
        launchSession: ReviewPlanLaunchSession? = nil,
        now: WallClockInstant? = nil,
        versionContext: ReviewPlanVersionContext? = nil,
        displayedDigest: PlanDigest? = nil,
        currentTargets: [ReviewPlanTarget]? = nil
    ) -> ApprovalContext {
        .init(
            launchSession: launchSession ?? self.launchSession,
            now: now ?? .init(unixNanoseconds: expiresAt.unixNanoseconds - 1),
            versionContext: versionContext ?? self.versionContext,
            displayedDigest: displayedDigest ?? digest,
            currentTargets: currentTargets ?? targets
        )
    }
}

private func approvalCandidate(component: String, bytes: Int64) throws -> EligibleCandidate {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: .userLibraryCaches)
    let observation = try FileObservation(
        rootID: root.id,
        locator: .init(rootID: root.id, components: ["com.apple.iconservices.store", component]),
        resourceIdentity: .observed(.init(device: 11, node: UInt64(bytes))),
        sizes: .init(logicalBytes: .observed(bytes), allocatedBytes: .observed(bytes)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: .regularFile,
        volume: .observed(try .init("approval-volume")),
        linkCount: .observed(1),
        boundaries: .init(
            symlink: .observed(false), alias: .observed(false), package: .observed(false),
            mount: .observed(false), protectedRoot: .observed(false),
            homeBoundary: .observed(false), externalVolume: .observed(false)
        )
    )
    let finding = try #require(try GeneralMacEvidenceDetector(scope: .userLibraryCaches)
        .makeFinding(
            from: observation,
            request: catalog.scanRequest(for: [.userLibraryCaches]),
            clockReading: .init(
                observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
                wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
            )
        )
        .get())
    return try #require(PolicyEvaluator().evaluate(finding).candidate)
}
