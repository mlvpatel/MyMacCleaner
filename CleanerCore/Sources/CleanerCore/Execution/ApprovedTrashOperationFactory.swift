public struct ApprovedTrashOperationFactory: Sendable {
    public init() {}

    public func makeOperations(
        plan: ReviewPlan,
        approval: ApprovalAttestation?,
        current: ApprovalContext
    ) -> Result<[MoveToTrash], ApprovedOperationRejection> {
        switch ApprovalValidity.evaluate(approval: approval, plan: plan, current: current) {
        case .invalid(let reason):
            return .failure(.invalidApproval(reason))
        case .validForReview:
            guard !plan.targets.isEmpty else { return .failure(.emptyPlan) }
            return .success(plan.targets.map(MoveToTrash.init))
        }
    }
}
