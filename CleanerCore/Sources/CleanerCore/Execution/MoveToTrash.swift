public struct MoveToTrash: Equatable, Sendable {
    let target: ReviewPlanTarget

    init(target: ReviewPlanTarget) {
        self.target = target
    }

    public var declaredRootID: DeclaredRootID { target.declaredRootID }
    public var locatorComponents: [String] { target.locatorComponents }
}
