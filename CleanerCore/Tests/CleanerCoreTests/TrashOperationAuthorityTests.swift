import Testing

@testable import CleanerCore

@Suite("Approved trash operation authority")
struct TrashOperationAuthorityTests {
    @Test
    func currentApprovalProducesOneMoveAndOneRecorderCall() throws {
        let recorder = MutationCallRecorder()
        let plan = try PolicyPlanFixtureFactory.reviewPlan(
            candidates: [try PolicyPlanFixtureFactory.eligibleCache(component: "ok.bin", bytes: 4_096, node: 101)]
        )
        let approval = PolicyPlanFixtureFactory.matchingApproval(plan)
        let current = PolicyPlanFixtureFactory.matchingContext(plan)
        let coordinator = TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder))
        let fresh = plan.targets.map { FreshTargetEvidence.matching($0) }

        let result = try coordinator.execute(
            plan: plan,
            approval: approval,
            current: current,
            freshEvidence: fresh,
            isCancelled: { false }
        ).get()

        #expect(result.state == .complete)
        #expect(result.items == [.moved(destination: "scripted-trash")])
        #expect(recorder.calls == 1)
    }

    @Test
    func missingApprovalProducesNoOperationAndZeroCalls() throws {
        let recorder = MutationCallRecorder()
        let plan = try PolicyPlanFixtureFactory.reviewPlan(
            candidates: [try PolicyPlanFixtureFactory.eligibleCache(component: "ok.bin", bytes: 4_096, node: 102)]
        )
        let coordinator = TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder))

        let result = coordinator.execute(
            plan: plan,
            approval: nil,
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: plan.targets.map { FreshTargetEvidence.matching($0) },
            isCancelled: { false }
        )

        #expect(result == .failure(.invalidApproval(.missingApproval)))
        #expect(recorder.calls == 0)
    }

    @Test
    func expiredApprovalProducesZeroCalls() throws {
        let recorder = MutationCallRecorder()
        let plan = try PolicyPlanFixtureFactory.reviewPlan(
            candidates: [try PolicyPlanFixtureFactory.eligibleCache(component: "ok.bin", bytes: 4_096, node: 103)]
        )
        let coordinator = TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder))
        let result = coordinator.execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan, now: plan.expiresAt),
            freshEvidence: plan.targets.map { FreshTargetEvidence.matching($0) },
            isCancelled: { false }
        )
        #expect(result == .failure(.invalidApproval(.expired)))
        #expect(recorder.calls == 0)
    }

    @Test
    func protectedOwnersCannotProduceMoveToTrash() throws {
        let evaluation = PolicyEvaluator().protectedEvaluation(
            detector: ModelStoreDetectorRegistration.huggingFaceSelection,
            owner: .modelStore
        )
        #expect(evaluation.candidate == nil)
        #expect(throws: ReviewPlanBuildError.emptySelection) {
            try ReviewPlanDraft(
                selectedCandidates: [],
                versionContext: PolicyPlanFixtureFactory.versionContext(),
                launchSession: PolicyPlanFixtureFactory.launchSession(),
                createdAt: PolicyPlanFixtureFactory.createdAt
            )
        }
    }
}
