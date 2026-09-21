import Testing

@testable import CleanerCore

@Suite("Sequential trash execution")
struct TrashExecutionTests {
    @Test
    func nonemptyAllMovedIsComplete() throws {
        let recorder = MutationCallRecorder()
        let plan = try twoTargetPlan()
        let result = try run(
            plan,
            fresh: plan.targets.map { FreshTargetEvidence.matching($0) },
            recorder: recorder
        )
        #expect(result.state == .complete)
        #expect(result.items == [
            .moved(destination: "scripted-trash"),
            .moved(destination: "scripted-trash"),
        ])
        #expect(recorder.calls == 2)
    }

    @Test
    func movedThenStaleThenMovedIsPartialAndContinues() throws {
        let recorder = MutationCallRecorder()
        let plan = try threeTargetPlan()
        let matching = plan.targets.map { FreshTargetEvidence.matching($0) }
        let result = try run(
            plan,
            fresh: [matching[0], nil, matching[2]],
            recorder: recorder
        )
        #expect(result.state == .partial)
        #expect(result.items == [
            .moved(destination: "scripted-trash"),
            .skippedStale(.missingFreshEvidence),
            .moved(destination: "scripted-trash"),
        ])
        #expect(recorder.calls == 2)
    }

    @Test
    func movedThenFailedThenMovedIsPartialAndContinues() throws {
        let recorder = MutationCallRecorder()
        let plan = try threeTargetPlan()
        let port = ProgrammedTrashPort(
            recorder: recorder,
            outcomes: [
                .moved(destination: "first"),
                .failed(.nativeMoveFailed),
                .moved(destination: "third"),
            ]
        )
        let result = try TrashExecutionCoordinator(port: port).execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: plan.targets.map { FreshTargetEvidence.matching($0) },
            isCancelled: { false }
        ).get()
        #expect(result.state == .partial)
        #expect(result.items == [
            .moved(destination: "first"),
            .failed(.nativeMoveFailed),
            .moved(destination: "third"),
        ])
        #expect(recorder.calls == 3)
    }

    @Test
    func cancellationBeforeFirstInterruptsWithZeroCalls() throws {
        let recorder = MutationCallRecorder()
        let plan = try twoTargetPlan()
        let result = try run(
            plan,
            fresh: plan.targets.map { FreshTargetEvidence.matching($0) },
            recorder: recorder,
            isCancelled: { true }
        )
        #expect(result.state == .interrupted)
        #expect(result.items == [.cancelled, .cancelled])
        #expect(recorder.calls == 0)
    }

    @Test
    func cancellationAfterFirstPreservesMovedAndCancelsRemainder() throws {
        let recorder = MutationCallRecorder()
        let plan = try twoTargetPlan()
        var remaining = 1
        let result = try run(
            plan,
            fresh: plan.targets.map { FreshTargetEvidence.matching($0) },
            recorder: recorder,
            isCancelled: {
                remaining -= 1
                return remaining < 0
            }
        )
        #expect(result.state == .interrupted)
        #expect(result.items == [
            .moved(destination: "scripted-trash"),
            .cancelled,
        ])
        #expect(recorder.calls == 1)
    }

    @Test
    func emptySelectionCannotProduceACompleteRun() throws {
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

private func twoTargetPlan() throws -> ReviewPlan {
    try PolicyPlanFixtureFactory.reviewPlan(candidates: [
        try PolicyPlanFixtureFactory.eligibleCache(component: "one.bin", bytes: 4_096, node: 501),
        try PolicyPlanFixtureFactory.eligibleCache(component: "two.bin", bytes: 8_192, node: 502),
    ])
}

private func threeTargetPlan() throws -> ReviewPlan {
    try PolicyPlanFixtureFactory.reviewPlan(candidates: [
        try PolicyPlanFixtureFactory.eligibleCache(component: "a.bin", bytes: 4_096, node: 511),
        try PolicyPlanFixtureFactory.eligibleCache(component: "b.bin", bytes: 8_192, node: 512),
        try PolicyPlanFixtureFactory.eligibleCache(component: "c.bin", bytes: 4_096, node: 513),
    ])
}

private func run(
    _ plan: ReviewPlan,
    fresh: [FreshTargetEvidence?],
    recorder: MutationCallRecorder,
    isCancelled: @escaping () -> Bool = { false }
) throws -> TrashRunResult<String> {
    try TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder)).execute(
        plan: plan,
        approval: PolicyPlanFixtureFactory.matchingApproval(plan),
        current: PolicyPlanFixtureFactory.matchingContext(plan),
        freshEvidence: fresh,
        isCancelled: isCancelled
    ).get()
}

private struct ProgrammedTrashPort: TrashExecutionPort {
    typealias Destination = String

    private let recorder: MutationCallRecorder
    private let outcomes: [TrashItemOutcome<String>]

    init(recorder: MutationCallRecorder, outcomes: [TrashItemOutcome<String>]) {
        self.recorder = recorder
        self.outcomes = outcomes
    }

    func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<String> {
        recorder.record()
        let index = recorder.calls - 1
        if index >= 0, index < outcomes.count {
            return outcomes[index]
        }
        return .failed(.nativeMoveFailed)
    }
}
