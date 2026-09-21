/// Builds the digest-bound plan shown for review from policy evaluations.
/// Presentation cannot select or manufacture candidates.
public enum DisplayedPlanFactory {
    public static func makePlan(
        evaluations: [PolicyEvaluation],
        versionContext: ReviewPlanVersionContext,
        launchSession: ReviewPlanLaunchSession,
        now: WallClockInstant,
        digesting: any PlanDigesting
    ) throws -> ReviewPlan? {
        let candidates = ConservativeRank.ordered(evaluations.compactMap(\.candidate))
        guard !candidates.isEmpty else { return nil }
        return try ReviewPlan.build(
            draft: ReviewPlanDraft(
                selectedCandidates: candidates,
                versionContext: versionContext,
                launchSession: launchSession,
                createdAt: now
            ),
            digesting: digesting
        )
    }
}
