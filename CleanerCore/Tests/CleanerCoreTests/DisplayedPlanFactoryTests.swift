import Testing

@testable import CleanerCore

@Suite("Displayed plan factory")
struct DisplayedPlanFactoryTests {
    @Test
    func eligibleEvaluationsProduceADigestBoundPlan() throws {
        let candidate = try PolicyPlanFixtureFactory.eligibleCache(
            component: "plan.bin",
            bytes: 4_096,
            node: 801
        )
        let evaluation = PolicyEvaluator().evaluate(candidate.evidence.finding)
        let plan = try DisplayedPlanFactory.makePlan(
            evaluations: [evaluation],
            versionContext: PolicyPlanFixtureFactory.versionContext(),
            launchSession: PolicyPlanFixtureFactory.launchSession(),
            now: PolicyPlanFixtureFactory.createdAt,
            digesting: StaticGoldenDigesting()
        )

        #expect(plan != nil)
        #expect(plan?.targets.count == 1)
        #expect(plan?.digest.bytes.count == 32)
    }

    @Test
    func ineligibleEvaluationsProduceNoPlan() throws {
        let finding = try PolicyPlanFixtureFactory.finding(
            scope: .userLibraryLogs,
            components: ["system.log"],
            bytes: 4_096,
            node: 802
        )
        let plan = try DisplayedPlanFactory.makePlan(
            evaluations: [PolicyEvaluator().evaluate(finding)],
            versionContext: PolicyPlanFixtureFactory.versionContext(),
            launchSession: PolicyPlanFixtureFactory.launchSession(),
            now: PolicyPlanFixtureFactory.createdAt,
            digesting: StaticGoldenDigesting()
        )
        #expect(plan == nil)
    }

    @Test
    func observingLiveFindingValidatesAgainstTheDisplayedTarget() throws {
        let finding = try PolicyPlanFixtureFactory.finding(
            components: ["com.apple.iconservices.store", "observe.bin"],
            bytes: 4_096,
            node: 803
        )
        let evaluation = PolicyEvaluator().evaluate(finding)
        let candidate = try #require(evaluation.candidate)
        let plan = try PolicyPlanFixtureFactory.reviewPlan(candidates: [candidate])
        let fresh = FreshTargetEvidence.observing(target: plan.targets[0], in: [finding])
        let operations = try ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan)
        ).get()

        #expect(fresh != nil)
        #expect(FreshTargetEvidence.observing(target: plan.targets[0], in: []) == nil)
        #expect(FreshEvidenceRevalidator().validate(operation: operations[0], fresh: fresh) == nil)
    }

    @Test
    func oneShotApprovalProducesOperationsWithoutACachedFlag() throws {
        let plan = try PolicyPlanFixtureFactory.reviewPlan(candidates: [
            try PolicyPlanFixtureFactory.eligibleCache(component: "once.bin", bytes: 4_096, node: 804)
        ])
        let missing = ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: nil,
            current: PolicyPlanFixtureFactory.matchingContext(plan)
        )
        let minted = ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan)
        )

        #expect(missing == .failure(.invalidApproval(.missingApproval)))
        #expect(try minted.get().count == 1)
    }
}
