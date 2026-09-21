import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Foundation trash adapter")
struct FoundationTrashAdapterTests {
    @Test
    func matchingFreshEvidenceMovesAndReturnsFoundationURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmc-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = try foundationPlan(component: "cache.bin", node: 401)
        let operations = try ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: foundationApproval(plan),
            current: foundationContext(plan)
        ).get()
        let operation = try #require(operations.first)

        var nested = root
        for component in operation.locatorComponents.dropLast() {
            nested.appendPathComponent(component, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let target = nested.appendingPathComponent(operation.locatorComponents.last ?? "cache.bin")
        try Data("fixture".utf8).write(to: target)

        let adapter = FoundationTrashAdapter { id in
            id == operation.declaredRootID ? root : nil
        }
        let outcome = adapter.revalidateAndMove(
            operation,
            fresh: FreshTargetEvidence.matching(plan.targets[0])
        )
        guard case let .moved(destination) = outcome else {
            Issue.record("expected moved")
            return
        }
        #expect(!destination.absoluteString.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func staleIdentityDoesNotCallTrash() throws {
        let calls = NativeCallRecorder()
        let adapter = FoundationTrashAdapter(
            nativeTrash: { _ in
                calls.count += 1
                return URL(fileURLWithPath: "/tmp/Trash/unused")
            },
            resolveRoot: { _ in URL(fileURLWithPath: "/tmp") }
        )
        let plan = try foundationPlan(component: "stale.bin", node: 402)
        let operations = try ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: foundationApproval(plan),
            current: foundationContext(plan)
        ).get()
        let operation = try #require(operations.first)
        #expect(adapter.revalidateAndMove(operation, fresh: nil) == .skippedStale(.missingFreshEvidence))
        #expect(calls.count == 0)
    }

    @Test
    func collisionRenamedReturnedURLIsRetainedExactly() throws {
        let calls = NativeCallRecorder()
        let renamed = URL(fileURLWithPath: "/tmp/Trash/cache.bin 2")
        let plan = try foundationPlan(component: "cache.bin", node: 403)
        let operations = try ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: foundationApproval(plan),
            current: foundationContext(plan)
        ).get()
        let operation = try #require(operations.first)
        let adapter = FoundationTrashAdapter(
            nativeTrash: { url in
                calls.count += 1
                calls.lastInput = url
                return renamed
            },
            resolveRoot: { id in id == operation.declaredRootID ? URL(fileURLWithPath: "/tmp/root") : nil }
        )
        let outcome = adapter.revalidateAndMove(
            operation,
            fresh: FreshTargetEvidence.matching(plan.targets[0])
        )
        #expect(outcome == .moved(destination: ReturnedTrashURL(renamed)))
        #expect(calls.count == 1)
        #expect(calls.lastInput != renamed)
    }

    @Test
    func nativeThrowIsFailedNotStale() throws {
        let calls = NativeCallRecorder()
        let plan = try foundationPlan(component: "fail.bin", node: 404)
        let operations = try ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: foundationApproval(plan),
            current: foundationContext(plan)
        ).get()
        let operation = try #require(operations.first)
        let adapter = FoundationTrashAdapter(
            nativeTrash: { _ in
                calls.count += 1
                throw NativeTrashTestError.boom
            },
            resolveRoot: { _ in URL(fileURLWithPath: "/tmp/root") }
        )
        #expect(
            adapter.revalidateAndMove(
                operation,
                fresh: FreshTargetEvidence.matching(plan.targets[0])
            ) == .failed(.nativeMoveFailed)
        )
        #expect(calls.count == 1)
    }

    @Test
    func missingReturnedURLIsFailed() throws {
        let calls = NativeCallRecorder()
        let plan = try foundationPlan(component: "missing.bin", node: 405)
        let operations = try ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: foundationApproval(plan),
            current: foundationContext(plan)
        ).get()
        let operation = try #require(operations.first)
        let adapter = FoundationTrashAdapter(
            nativeTrash: { _ in
                calls.count += 1
                return nil
            },
            resolveRoot: { _ in URL(fileURLWithPath: "/tmp/root") }
        )
        #expect(
            adapter.revalidateAndMove(
                operation,
                fresh: FreshTargetEvidence.matching(plan.targets[0])
            ) == .failed(.missingReturnedLocation)
        )
        #expect(calls.count == 1)
    }
}

private final class NativeCallRecorder: @unchecked Sendable {
    var count = 0
    var lastInput: URL?
}

private enum NativeTrashTestError: Error {
    case boom
}

private func foundationPlan(component: String, node: UInt64) throws -> ReviewPlan {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: .userLibraryCaches)
    let observation = try FileObservation(
        rootID: root.id,
        locator: .init(rootID: root.id, components: ["com.apple.iconservices.store", component]),
        resourceIdentity: .observed(.init(device: 7, node: node)),
        sizes: .init(logicalBytes: .observed(4_096), allocatedBytes: .observed(4_096)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: .regularFile,
        volume: .observed(try .init("adapter-volume")),
        linkCount: .observed(1),
        boundaries: .init(
            symlink: .observed(false), alias: .observed(false), package: .observed(false),
            mount: .observed(false), protectedRoot: .observed(false),
            homeBoundary: .observed(false), externalVolume: .observed(false)
        )
    )
    let finding = try #require(try GeneralMacEvidenceDetector(scope: .userLibraryCaches)
        .makeFinding(
            from: observation,
            request: catalog.scanRequest(for: [.userLibraryCaches]),
            clockReading: .init(
                observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
                wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
            )
        )
        .get())
    let candidate = try #require(PolicyEvaluator().evaluate(finding).candidate)
    return try ReviewPlan.build(
        draft: .init(
            selectedCandidates: [candidate],
            versionContext: try .init(
                appPlanVersion: "5.0.0",
                policyVersion: "policy-1",
                detectorCatalogVersion: catalog.version.value,
                encodingVersion: 1
            ),
            launchSession: try .init("launch-a"),
            createdAt: .init(unixNanoseconds: 1_000_000_000)
        ),
        digesting: FoundationStaticDigesting()
    )
}

private func foundationApproval(_ plan: ReviewPlan) -> ApprovalAttestation {
    .init(
        approvedDigest: plan.digest,
        approvedAt: .init(unixNanoseconds: 1_000_000_001),
        launchSession: plan.launchSession
    )
}

private func foundationContext(_ plan: ReviewPlan) -> ApprovalContext {
    .init(
        launchSession: plan.launchSession,
        now: .init(unixNanoseconds: plan.expiresAt.unixNanoseconds - 1),
        versionContext: plan.versionContext,
        displayedDigest: plan.digest,
        currentTargets: plan.targets
    )
}

private struct FoundationStaticDigesting: PlanDigesting {
    func digest(canonicalBytes _: [UInt8]) throws -> PlanDigest {
        try .init(bytes: Array(repeating: 5, count: 32))
    }
}
