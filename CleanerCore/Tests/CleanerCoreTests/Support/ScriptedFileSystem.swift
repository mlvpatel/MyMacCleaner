@testable import CleanerCore

final class ScriptedFileSystem: FileSystemPort, @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let rootID: DeclaredRootID
        let cursor: ScanCursor?
    }

    private var stepsByRoot: [DeclaredRootID: [FileSystemStep]]
    private var expectedCursorByRoot: [DeclaredRootID: UInt] = [:]
    private(set) var calls: [Call] = []

    init(steps: [FileSystemStep], rootID: DeclaredRootID) {
        stepsByRoot = [rootID: steps]
    }

    init(stepsByRoot: [DeclaredRootID: [FileSystemStep]]) {
        self.stepsByRoot = stepsByRoot
    }

    func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        calls.append(.init(rootID: root.id, cursor: cursor))
        guard var steps = stepsByRoot[root.id] else { return .terminal(.corruptMetadata) }

        let expectedCursor = expectedCursorByRoot[root.id] ?? 0
        guard cursor?.position ?? 0 == expectedCursor else { return .terminal(.corruptMetadata) }
        guard !steps.isEmpty else { return .terminal(.corruptMetadata) }

        let next = steps.removeFirst()
        stepsByRoot[root.id] = steps
        if case .observation = next {
            expectedCursorByRoot[root.id] = expectedCursor + 1
        }
        return next
    }
}
