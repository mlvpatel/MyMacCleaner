public struct TrashExecutionCoordinator<Port: TrashExecutionPort>: Sendable {
    private let factory: ApprovedTrashOperationFactory
    private let port: Port

    init(factory: ApprovedTrashOperationFactory = .init(), port: Port) {
        self.factory = factory
        self.port = port
    }

    func execute(
        plan: ReviewPlan,
        approval: ApprovalAttestation?,
        current: ApprovalContext,
        freshEvidence: [FreshTargetEvidence?],
        isCancelled: () -> Bool
    ) -> Result<TrashRunResult<Port.Destination>, ApprovedOperationRejection> {
        switch factory.makeOperations(plan: plan, approval: approval, current: current) {
        case .failure(let rejection):
            return .failure(rejection)
        case .success(let operations):
            var items: [TrashItemOutcome<Port.Destination>] = []
            for index in operations.indices {
                if isCancelled() {
                    items.append(contentsOf: operations[index...].map { _ in TrashItemOutcome<Port.Destination>.cancelled })
                    break
                }
                let fresh = index < freshEvidence.count ? freshEvidence[index] : nil
                items.append(port.revalidateAndMove(operations[index], fresh: fresh))
            }
            return .success(TrashRunResult(items: items))
        }
    }
}
