/// External observation of which located files a running process currently
/// holds open (C5). Supplying this can only ever mark a file in-use — and an
/// in-use file is never a cleanup candidate — so it never widens eligibility.
public protocol ProcessActivityObserving: Sendable {
    func isFileOpen(rootID: DeclaredRootID, components: [String]) -> Bool
}

/// The default: no process correlation, so activity falls back to the
/// modification-time rule.
public struct NoProcessActivity: ProcessActivityObserving {
    public init() {}
    public func isFileOpen(rootID: DeclaredRootID, components: [String]) -> Bool { false }
}
