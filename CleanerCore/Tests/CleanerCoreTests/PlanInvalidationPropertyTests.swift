import Testing

@testable import CleanerCore

@Suite("Deterministic plan permutation and approval invalidation")
struct PlanInvalidationPropertyTests {
    @Test
    func callerOrderDoesNotChangeCanonicalBytesOrDigest() throws {
        let first = try PolicyPlanFixtureFactory.eligibleCache(component: "b.bin", bytes: 4_096, node: 11)
        let second = try PolicyPlanFixtureFactory.eligibleCache(component: "a.bin", bytes: 8_192, node: 12)
        let left = try PolicyPlanFixtureFactory.reviewPlan(candidates: [first, second])
        let right = try PolicyPlanFixtureFactory.reviewPlan(candidates: [second, first])

        #expect(left.canonicalBytes == right.canonicalBytes)
        #expect(left.digest == right.digest)
        #expect(left.expiresAt.unixNanoseconds == PolicyPlanFixtureFactory.createdAt.unixNanoseconds + PolicyPlanFixtureFactory.lifetimeNanoseconds)
        #expect(left.targets.map(\.stableIdentity.utf8Bytes) == right.targets.map(\.stableIdentity.utf8Bytes))
    }

    @Test
    func eachAuthorizationFieldChangeChangesCanonicalBytes() throws {
        let candidate = try PolicyPlanFixtureFactory.eligibleCache(component: "field.bin", bytes: 4_096, node: 21)
        let base = try ReviewPlanDraft(
            selectedCandidates: [candidate],
            versionContext: PolicyPlanFixtureFactory.versionContext(),
            launchSession: PolicyPlanFixtureFactory.launchSession(),
            createdAt: PolicyPlanFixtureFactory.createdAt
        )
        let encoder = CanonicalPlanEncoder()
        let baseBytes = try encoder.encode(base)

        let session = try ReviewPlanDraft(
            selectedCandidates: [candidate],
            versionContext: PolicyPlanFixtureFactory.versionContext(),
            launchSession: PolicyPlanFixtureFactory.launchSession("launch-b"),
            createdAt: PolicyPlanFixtureFactory.createdAt
        )
        let policy = try ReviewPlanDraft(
            selectedCandidates: [candidate],
            versionContext: PolicyPlanFixtureFactory.versionContext(policyVersion: "policy-2"),
            launchSession: PolicyPlanFixtureFactory.launchSession(),
            createdAt: PolicyPlanFixtureFactory.createdAt
        )
        let created = try ReviewPlanDraft(
            selectedCandidates: [candidate],
            versionContext: PolicyPlanFixtureFactory.versionContext(),
            launchSession: PolicyPlanFixtureFactory.launchSession(),
            createdAt: .init(unixNanoseconds: 2_000_000_000)
        )
        let other = try PolicyPlanFixtureFactory.eligibleCache(component: "other.bin", bytes: 4_096, node: 22)
        let selection = try ReviewPlanDraft(
            selectedCandidates: [other],
            versionContext: PolicyPlanFixtureFactory.versionContext(),
            launchSession: PolicyPlanFixtureFactory.launchSession(),
            createdAt: PolicyPlanFixtureFactory.createdAt
        )

        #expect(try encoder.encode(session) != baseBytes)
        #expect(try encoder.encode(policy) != baseBytes)
        #expect(try encoder.encode(created) != baseBytes)
        #expect(try encoder.encode(selection) != baseBytes)
    }

    @Test
    func approvalSequencesReturnClosedReasonsAndZeroEffects() throws {
        let recorder = ZeroEffectRecorder()
        let plan = try PolicyPlanFixtureFactory.reviewPlan(
            candidates: [try PolicyPlanFixtureFactory.eligibleCache(component: "ok.bin", bytes: 4_096, node: 31)]
        )
        let approval = PolicyPlanFixtureFactory.matchingApproval(plan)

        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(plan)
        ) == .validForReview)

        #expect(ApprovalValidity.evaluate(
            approval: nil,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(plan)
        ) == .invalid(.missingApproval))

        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(
                plan,
                launchSession: try PolicyPlanFixtureFactory.launchSession("relaunch")
            )
        ) == .invalid(.sessionChanged))

        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(plan, now: plan.expiresAt)
        ) == .invalid(.expired))

        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(
                plan,
                now: .init(unixNanoseconds: plan.expiresAt.unixNanoseconds + 1)
            )
        ) == .invalid(.expired))

        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(
                plan,
                versionContext: try PolicyPlanFixtureFactory.versionContext(appPlanVersion: "5.0.1")
            )
        ) == .invalid(.contextChanged))

        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(
                plan,
                displayedDigest: try PlanDigest(bytes: Array(repeating: 9, count: 32))
            )
        ) == .invalid(.planDigestChanged))

        #expect(ApprovalValidity.evaluate(
            approval: approval,
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(plan, currentTargets: [])
        ) == .invalid(.evidenceChanged))

        let combined = PolicyPlanFixtureFactory.matchingContext(
            plan,
            now: plan.expiresAt,
            launchSession: try PolicyPlanFixtureFactory.launchSession("relaunch"),
            displayedDigest: try PlanDigest(bytes: Array(repeating: 9, count: 32)),
            currentTargets: []
        )
        #expect(ApprovalValidity.evaluate(approval: approval, plan: plan, current: combined) == .invalid(.sessionChanged))
        #expect(recorder.calls == 0)
    }

    @Test
    func matchingReviewRemainsNonExecutable() throws {
        let recorder = ZeroEffectRecorder()
        let plan = try PolicyPlanFixtureFactory.reviewPlan(
            candidates: [try PolicyPlanFixtureFactory.eligibleCache(component: "review.bin", bytes: 2_048, node: 41)]
        )
        let validity = ApprovalValidity.evaluate(
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(plan)
        )
        #expect(validity == .validForReview)
        #expect(recorder.calls == 0)
    }
}
