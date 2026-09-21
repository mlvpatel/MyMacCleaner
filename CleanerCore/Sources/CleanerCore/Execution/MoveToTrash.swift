public struct MoveToTrash: Equatable, Sendable {
    let target: ReviewPlanTarget

    init(target: ReviewPlanTarget) {
        self.target = target
    }

    public var declaredRootID: DeclaredRootID { target.declaredRootID }
    public var locatorComponents: [String] { target.locatorComponents }

    /// Frozen approved identity/size/modification of the reviewed target, exposed so the sole
    /// mutation adapter can perform a final in-adapter re-observation immediately before the move
    /// (defence against a use-after-check swap) without widening what may be trashed.
    public var approvedResourceIdentity: FileIdentityEvidence { target.resourceIdentity }
    public var approvedLogicalBytes: Int64 { target.logicalBytes }
    public var approvedModificationUnixNanoseconds: Int64 { target.modificationUnixNanoseconds }
}
