public protocol TrashExecutionPort: Sendable {
    associatedtype Destination: Equatable & Sendable

    func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<Destination>
}

public struct ScriptedTrashExecutionPort: TrashExecutionPort {
    public typealias Destination = String

    private let revalidator: FreshEvidenceRevalidator
    private let destinationToken: String
    private let recorder: MutationCallRecorder

    init(
        revalidator: FreshEvidenceRevalidator = .init(),
        destinationToken: String = "scripted-trash",
        recorder: MutationCallRecorder
    ) {
        self.revalidator = revalidator
        self.destinationToken = destinationToken
        self.recorder = recorder
    }

    public func revalidateAndMove(
        _ operation: MoveToTrash,
        fresh: FreshTargetEvidence?
    ) -> TrashItemOutcome<String> {
        if let reason = revalidator.validate(operation: operation, fresh: fresh) {
            return .skippedStale(reason)
        }
        recorder.record()
        return .moved(destination: destinationToken)
    }
}

public final class MutationCallRecorder: @unchecked Sendable {
    private(set) var calls = 0

    public init() {}

    func record() {
        calls += 1
    }
}
