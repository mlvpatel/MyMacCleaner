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

        let adapter = FoundationTrashAdapter(
            identityProbe: matchingProbe(operation)
        ) { id in
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
            identityProbe: matchingProbe(operation),
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
            identityProbe: matchingProbe(operation),
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
            identityProbe: matchingProbe(operation),
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

    // MARK: - Final in-adapter identity check (B2)

    @Test
    func changedInodeSkipsWithoutCallingTrash() throws {
        try assertProbeSkips(
            component: "swap.bin",
            node: 501,
            probe: { operation in
                let identity = operation.approvedResourceIdentity
                return { _, _ in
                    .observed(
                        device: identity.device,
                        node: identity.node &+ 1,
                        logicalBytes: operation.approvedLogicalBytes,
                        modificationUnixNanoseconds: operation.approvedModificationUnixNanoseconds
                    )
                }
            },
            expected: .identityChanged
        )
    }

    @Test
    func symlinkComponentSkipsWithoutCallingTrash() throws {
        try assertProbeSkips(
            component: "symlink.bin",
            node: 502,
            probe: { _ in { _, _ in .symlinkEncountered } },
            expected: .topologyChanged
        )
    }

    @Test
    func changedSizeSkipsWithoutCallingTrash() throws {
        try assertProbeSkips(
            component: "size.bin",
            node: 503,
            probe: { operation in
                let identity = operation.approvedResourceIdentity
                return { _, _ in
                    .observed(
                        device: identity.device,
                        node: identity.node,
                        logicalBytes: operation.approvedLogicalBytes &+ 1,
                        modificationUnixNanoseconds: operation.approvedModificationUnixNanoseconds
                    )
                }
            },
            expected: .sizeChanged
        )
    }

    @Test
    func changedModificationSkipsWithoutCallingTrash() throws {
        try assertProbeSkips(
            component: "mtime.bin",
            node: 504,
            probe: { operation in
                let identity = operation.approvedResourceIdentity
                return { _, _ in
                    .observed(
                        device: identity.device,
                        node: identity.node,
                        logicalBytes: operation.approvedLogicalBytes,
                        modificationUnixNanoseconds: operation.approvedModificationUnixNanoseconds &+ 1
                    )
                }
            },
            expected: .modificationChanged
        )
    }

    @Test
    func unavailableTargetSkipsWithoutCallingTrash() throws {
        try assertProbeSkips(
            component: "gone.bin",
            node: 505,
            probe: { _ in { _, _ in .unavailable } },
            expected: .identityChanged
        )
    }

    // MARK: - Default lstat probe against real files

    @Test
    func realFileMatchingApprovedIdentityMovesViaDefaultProbe() throws {
        let fixture = try RealTrashFixture(component: "real-match.bin", node: 601)
        defer { fixture.cleanup() }
        let calls = NativeCallRecorder()
        let adapter = FoundationTrashAdapter(
            nativeTrash: { url in
                calls.count += 1
                return url.appendingPathExtension("trashed")
            },
            resolveRoot: { id in id == fixture.operation.declaredRootID ? fixture.root : nil }
        )
        let outcome = adapter.revalidateAndMove(
            fixture.operation,
            fresh: FreshTargetEvidence.matching(fixture.plan.targets[0])
        )
        guard case .moved = outcome else {
            Issue.record("expected moved, got \(outcome)")
            return
        }
        #expect(calls.count == 1)
    }

    @Test
    func realFileSwappedInodeSkipsViaDefaultProbe() throws {
        let fixture = try RealTrashFixture(component: "real-swap.bin", node: 602)
        defer { fixture.cleanup() }
        // Swap the leaf for a different inode after the plan (and its approved identity) was frozen.
        try fixture.replaceLeafWithDifferentInode()
        let calls = NativeCallRecorder()
        let adapter = FoundationTrashAdapter(
            nativeTrash: { _ in
                calls.count += 1
                return URL(fileURLWithPath: "/tmp/Trash/unused")
            },
            resolveRoot: { id in id == fixture.operation.declaredRootID ? fixture.root : nil }
        )
        #expect(
            adapter.revalidateAndMove(
                fixture.operation,
                fresh: FreshTargetEvidence.matching(fixture.plan.targets[0])
            ) == .skippedStale(.identityChanged)
        )
        #expect(calls.count == 0)
    }

    // MARK: - Helpers

    private func assertProbeSkips(
        component: String,
        node: UInt64,
        probe: (MoveToTrash) -> @Sendable (URL, [String]) -> LeafIdentityProbe,
        expected: TrashStaleReason
    ) throws {
        let calls = NativeCallRecorder()
        let plan = try foundationPlan(component: component, node: node)
        let operations = try ApprovedTrashOperationFactory().makeOperations(
            plan: plan,
            approval: foundationApproval(plan),
            current: foundationContext(plan)
        ).get()
        let operation = try #require(operations.first)
        let adapter = FoundationTrashAdapter(
            nativeTrash: { _ in
                calls.count += 1
                return URL(fileURLWithPath: "/tmp/Trash/unused")
            },
            identityProbe: probe(operation),
            resolveRoot: { _ in URL(fileURLWithPath: "/tmp/root") }
        )
        #expect(
            adapter.revalidateAndMove(
                operation,
                fresh: FreshTargetEvidence.matching(plan.targets[0])
            ) == .skippedStale(expected)
        )
        #expect(calls.count == 0)
    }

    private func matchingProbe(
        _ operation: MoveToTrash
    ) -> @Sendable (URL, [String]) -> LeafIdentityProbe {
        let identity = operation.approvedResourceIdentity
        let logicalBytes = operation.approvedLogicalBytes
        let modification = operation.approvedModificationUnixNanoseconds
        return { _, _ in
            .observed(
                device: identity.device,
                node: identity.node,
                logicalBytes: logicalBytes,
                modificationUnixNanoseconds: modification
            )
        }
    }
}

private final class NativeCallRecorder: @unchecked Sendable {
    var count = 0
    var lastInput: URL?
}

private enum NativeTrashTestError: Error {
    case boom
}

/// Builds a plan whose approved identity is derived from a real on-disk file, so the adapter's
/// default `lstat` probe observes matching evidence. The file's modification time is pinned to the
/// Unix epoch so the target stays policy-eligible under the fixed test clock.
private struct RealTrashFixture {
    let root: URL
    let leaf: URL
    let plan: ReviewPlan
    let operation: MoveToTrash

    init(component: String, node: UInt64) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmc-trash-real-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("com.apple.iconservices.store", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        leaf = nested.appendingPathComponent(component)
        try RealTrashFixture.writeFixtureFile(at: leaf)

        let identity = try RealTrashFixture.identity(of: leaf)
        plan = try foundationPlan(
            component: component,
            node: identity.node,
            device: identity.device,
            logicalBytes: identity.logicalBytes,
            modificationUnixNanoseconds: 0
        )
        operation = try #require(
            try ApprovedTrashOperationFactory().makeOperations(
                plan: plan,
                approval: foundationApproval(plan),
                current: foundationContext(plan)
            ).get().first
        )
    }

    func replaceLeafWithDifferentInode() throws {
        try FileManager.default.removeItem(at: leaf)
        try RealTrashFixture.writeFixtureFile(at: leaf)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func writeFixtureFile(at url: URL) throws {
        try Data(repeating: 0x2A, count: 4_096).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: url.path
        )
    }

    private static func identity(
        of url: URL
    ) throws -> (device: UInt64, node: UInt64, logicalBytes: Int64) {
        // Derive the approved identity the same way the adapter's default probe (and the scanner)
        // does — Foundation attributes/resource keys — so the real-file match test compares equal.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let node = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw NativeTrashTestError.boom
        }
        return (device, node, Int64(size))
    }
}

private func foundationPlan(
    component: String,
    node: UInt64,
    device: UInt64 = 7,
    logicalBytes: Int64 = 4_096,
    modificationUnixNanoseconds: Int64 = 1
) throws -> ReviewPlan {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: .userLibraryCaches)
    let observation = try FileObservation(
        rootID: root.id,
        locator: .init(rootID: root.id, components: ["com.apple.iconservices.store", component]),
        resourceIdentity: .observed(.init(device: device, node: node)),
        sizes: .init(logicalBytes: .observed(logicalBytes), allocatedBytes: .observed(logicalBytes)),
        modification: .observed(.init(unixNanoseconds: modificationUnixNanoseconds)),
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
