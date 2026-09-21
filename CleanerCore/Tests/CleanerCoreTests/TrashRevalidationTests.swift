import Testing

@testable import CleanerCore

@Suite("Fresh evidence revalidation")
struct TrashRevalidationTests {
    @Test
    func identityChangeIsSkippedStaleWithZeroCalls() throws {
        try assertStale(zeroCalls: true) { fresh in
            let changed = FreshTargetEvidence(
                stableIdentity: fresh.stableIdentity,
                detectorID: fresh.detectorID,
                detectorVersion: fresh.detectorVersion,
                declaredRootID: fresh.declaredRootID,
                locatorComponents: fresh.locatorComponents,
                resourceIdentity: .init(device: 99, node: 99),
                volume: fresh.volume,
                fileKind: fresh.fileKind,
                logicalBytes: fresh.logicalBytes,
                allocatedBytes: fresh.allocatedBytes,
                conservativeReclaimableBytes: fresh.conservativeReclaimableBytes,
                modificationUnixNanoseconds: fresh.modificationUnixNanoseconds,
                semanticOwner: fresh.semanticOwner,
                symlink: fresh.symlink,
                alias: fresh.alias,
                package: fresh.package,
                mount: fresh.mount,
                completeness: fresh.completeness
            )
            return (changed, .identityChanged)
        }
    }

    @Test
    func topologyChangeIsSkippedStaleWithZeroCalls() throws {
        try assertStale(zeroCalls: true) { fresh in
            let changed = FreshTargetEvidence(
                stableIdentity: fresh.stableIdentity,
                detectorID: fresh.detectorID,
                detectorVersion: fresh.detectorVersion,
                declaredRootID: fresh.declaredRootID,
                locatorComponents: fresh.locatorComponents,
                resourceIdentity: fresh.resourceIdentity,
                volume: fresh.volume,
                fileKind: fresh.fileKind,
                logicalBytes: fresh.logicalBytes,
                allocatedBytes: fresh.allocatedBytes,
                conservativeReclaimableBytes: fresh.conservativeReclaimableBytes,
                modificationUnixNanoseconds: fresh.modificationUnixNanoseconds,
                semanticOwner: fresh.semanticOwner,
                symlink: true,
                alias: fresh.alias,
                package: fresh.package,
                mount: fresh.mount,
                completeness: fresh.completeness
            )
            return (changed, .topologyChanged)
        }
    }

    @Test
    func missingFreshEvidenceIsSkippedStaleWithZeroCalls() throws {
        let recorder = MutationCallRecorder()
        let plan = try PolicyPlanFixtureFactory.reviewPlan(
            candidates: [try PolicyPlanFixtureFactory.eligibleCache(component: "stale.bin", bytes: 4_096, node: 201)]
        )
        let coordinator = TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder))
        let result = try coordinator.execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: [nil],
            isCancelled: { false }
        ).get()
        #expect(result.items == [.skippedStale(.missingFreshEvidence)])
        #expect(result.state == .partial)
        #expect(recorder.calls == 0)
    }

    @Test
    func cancellationStopsLaterItemsWithoutCompensatingMoves() throws {
        let recorder = MutationCallRecorder()
        let first = try PolicyPlanFixtureFactory.eligibleCache(component: "a.bin", bytes: 4_096, node: 301)
        let second = try PolicyPlanFixtureFactory.eligibleCache(component: "b.bin", bytes: 8_192, node: 302)
        let plan = try PolicyPlanFixtureFactory.reviewPlan(candidates: [first, second])
        let coordinator = TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder))
        var remaining = 1
        let result = try coordinator.execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: plan.targets.map { FreshTargetEvidence.matching($0) },
            isCancelled: {
                remaining -= 1
                return remaining < 0
            }
        ).get()
        #expect(result.state == .interrupted)
        #expect(result.items.last == .cancelled)
        #expect(recorder.calls == 1)
    }
}

private func assertStale(
    zeroCalls: Bool,
    mutate: (FreshTargetEvidence) -> (FreshTargetEvidence, TrashStaleReason)
) throws {
    let recorder = MutationCallRecorder()
    let plan = try PolicyPlanFixtureFactory.reviewPlan(
        candidates: [try PolicyPlanFixtureFactory.eligibleCache(component: "field.bin", bytes: 4_096, node: 211)]
    )
    let matching = FreshTargetEvidence.matching(plan.targets[0])
    let (changed, reason) = mutate(matching)
    let coordinator = TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder))
    let result = try coordinator.execute(
        plan: plan,
        approval: PolicyPlanFixtureFactory.matchingApproval(plan),
        current: PolicyPlanFixtureFactory.matchingContext(plan),
        freshEvidence: [changed],
        isCancelled: { false }
    ).get()
    #expect(result.items == [.skippedStale(reason)])
    if zeroCalls {
        #expect(recorder.calls == 0)
    }
}
