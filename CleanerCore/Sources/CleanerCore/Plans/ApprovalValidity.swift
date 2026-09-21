public struct ApprovalAttestation: Equatable, Sendable {
    public let approvedDigest: PlanDigest
    public let approvedAt: WallClockInstant
    public let launchSession: ReviewPlanLaunchSession

    public init(
        approvedDigest: PlanDigest,
        approvedAt: WallClockInstant,
        launchSession: ReviewPlanLaunchSession
    ) {
        self.approvedDigest = approvedDigest
        self.approvedAt = approvedAt
        self.launchSession = launchSession
    }
}

public struct ApprovalContext: Equatable, Sendable {
    public let launchSession: ReviewPlanLaunchSession
    public let now: WallClockInstant
    public let versionContext: ReviewPlanVersionContext
    public let displayedDigest: PlanDigest
    public let currentTargets: [ReviewPlanTarget]

    public init(
        launchSession: ReviewPlanLaunchSession,
        now: WallClockInstant,
        versionContext: ReviewPlanVersionContext,
        displayedDigest: PlanDigest,
        currentTargets: [ReviewPlanTarget]
    ) {
        self.launchSession = launchSession
        self.now = now
        self.versionContext = versionContext
        self.displayedDigest = displayedDigest
        self.currentTargets = currentTargets
    }
}

public enum ApprovalInvalidReason: Equatable, Sendable {
    case missingApproval
    case sessionChanged
    case expired
    case contextChanged
    case planDigestChanged
    case evidenceChanged
}

public enum ApprovalValidity: Equatable, Sendable {
    case validForReview
    case invalid(ApprovalInvalidReason)

    public static func evaluate(
        approval: ApprovalAttestation?,
        plan: ReviewPlan,
        current: ApprovalContext
    ) -> ApprovalValidity {
        guard let approval else { return .invalid(.missingApproval) }
        guard approval.launchSession == plan.launchSession,
              current.launchSession == plan.launchSession else {
            return .invalid(.sessionChanged)
        }
        guard approval.approvedAt >= plan.createdAt,
              approval.approvedAt < plan.expiresAt else {
            return .invalid(.expired)
        }
        guard current.now < plan.expiresAt else { return .invalid(.expired) }
        guard current.versionContext == plan.versionContext else { return .invalid(.contextChanged) }
        guard approval.approvedDigest == plan.digest,
              current.displayedDigest == plan.digest else {
            return .invalid(.planDigestChanged)
        }
        guard current.currentTargets == plan.targets else { return .invalid(.evidenceChanged) }
        return .validForReview
    }
}
