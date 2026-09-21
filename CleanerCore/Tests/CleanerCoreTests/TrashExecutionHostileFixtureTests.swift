import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Hostile trash execution matrix")
struct TrashExecutionHostileFixtureTests {
    @Test
    func freshMatchMakesOneNativeCallAndKeepsCollisionURL() throws {
        let native = ScriptedNativeTrash()
        let plan = try TrashExecutionFixtureFactory.approvedPlan(component: "ok.bin", node: 801)
        let operation = try #require(
            try ApprovedTrashOperationFactory().makeOperations(
                plan: plan,
                approval: PolicyPlanFixtureFactory.matchingApproval(plan),
                current: PolicyPlanFixtureFactory.matchingContext(plan)
            ).get().first
        )
        let adapter = FoundationTrashAdapter(
            nativeTrash: { try native.invoke($0) },
            identityProbe: { _, _ in
                .observed(
                    device: operation.approvedResourceIdentity.device,
                    node: operation.approvedResourceIdentity.node,
                    logicalBytes: operation.approvedLogicalBytes,
                    modificationUnixNanoseconds: operation.approvedModificationUnixNanoseconds
                )
            },
            resolveRoot: { _ in TrashExecutionFixtureFactory.scriptedRoot() }
        )
        let outcome = adapter.revalidateAndMove(
            operation,
            fresh: TrashExecutionFixtureFactory.matching(plan)
        )
        #expect(outcome == .moved(destination: ReturnedTrashURL(TrashExecutionFixtureFactory.collisionDestination())))
        #expect(native.calls == 1)
        #expect(native.lastInput != TrashExecutionFixtureFactory.collisionDestination())
    }

    @Test(arguments: [
        StaleSwap.identity,
        .directoryKind,
        .packageKind,
        .logicalSize,
        .allocatedSize,
        .modification,
        .incomplete,
        .missingField,
        .unavailableRoot,
        .semanticOwner,
        .detectorVersion,
        .locator,
        .volume,
        .symlink,
        .ancestorAlias,
        .mount,
        .packageBoundary,
    ])
    func targetSwapIsSkippedStaleWithZeroNativeCalls(_ swap: StaleSwap) throws {
        let native = ScriptedNativeTrash()
        let plan = try TrashExecutionFixtureFactory.approvedPlan(component: "swap.bin", node: 802)
        let operation = try #require(
            try ApprovedTrashOperationFactory().makeOperations(
                plan: plan,
                approval: PolicyPlanFixtureFactory.matchingApproval(plan),
                current: PolicyPlanFixtureFactory.matchingContext(plan)
            ).get().first
        )
        let adapter = FoundationTrashAdapter(
            nativeTrash: { try native.invoke($0) },
            resolveRoot: { id in
                swap == .unavailableRoot ? nil : (id == operation.declaredRootID
                    ? TrashExecutionFixtureFactory.scriptedRoot()
                    : nil)
            }
        )
        let base = TrashExecutionFixtureFactory.matching(plan)
        let fresh: FreshTargetEvidence? = swap == .unavailableRoot ? base : swap.apply(base)
        let outcome = adapter.revalidateAndMove(operation, fresh: swap == .missingField ? nil : fresh)
        #expect(outcome == .skippedStale(swap.reason))
        #expect(native.calls == 0)
    }

    @Test(arguments: [
        (ModelStoreDetectorRegistration.huggingFaceSelection, PolicySemanticOwner.modelStore),
        (ModelStoreDetectorRegistration.ollamaSelection, PolicySemanticOwner.modelStore),
        (ModelStoreDetectorRegistration.selectedRootSelection, PolicySemanticOwner.modelStore),
        (ModelStoreDetectorRegistration.huggingFaceSelection, PolicySemanticOwner.developerToolState),
        (ModelStoreDetectorRegistration.huggingFaceSelection, PolicySemanticOwner.credential),
        (ModelStoreDetectorRegistration.huggingFaceSelection, PolicySemanticOwner.setting),
        (ModelStoreDetectorRegistration.ollamaSelection, PolicySemanticOwner.duplicateEvidence),
        (ModelStoreDetectorRegistration.selectedRootSelection, PolicySemanticOwner.unknown),
    ])
    func protectedOwnersCannotConstructMoveToTrash(
        _ pair: (DetectorSelection, PolicySemanticOwner)
    ) throws {
        let evaluation = PolicyEvaluator().protectedEvaluation(detector: pair.0, owner: pair.1)
        #expect(evaluation.candidate == nil)
        #expect(evaluation.eligibility == .ineligible)
        #expect(throws: ReviewPlanBuildError.emptySelection) {
            try ReviewPlanDraft(
                selectedCandidates: [],
                versionContext: PolicyPlanFixtureFactory.versionContext(),
                launchSession: PolicyPlanFixtureFactory.launchSession(),
                createdAt: PolicyPlanFixtureFactory.createdAt
            )
        }
    }

    @Test
    func movedThenStaleThenMovedIsPartial() throws {
        let recorder = MutationCallRecorder()
        let plan = try TrashExecutionFixtureFactory.approvedThreeTargetPlan()
        let matching = [
            TrashExecutionFixtureFactory.matching(plan, index: 0),
            nil,
            TrashExecutionFixtureFactory.matching(plan, index: 2),
        ]
        let result = try TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder)).execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: matching,
            isCancelled: { false }
        ).get()
        #expect(result.state == .partial)
        #expect(result.items[1] == .skippedStale(.missingFreshEvidence))
        #expect(recorder.calls == 2)
    }

    @Test
    func cancellationBeforeFirstIsInterruptedWithZeroCalls() throws {
        let recorder = MutationCallRecorder()
        let plan = try TrashExecutionFixtureFactory.approvedTwoTargetPlan()
        let result = try TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder)).execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: plan.targets.map { FreshTargetEvidence.matching($0) },
            isCancelled: { true }
        ).get()
        #expect(result.state == .interrupted)
        #expect(result.items == [.cancelled, .cancelled])
        #expect(recorder.calls == 0)
    }

    @Test
    func cancellationAfterSynchronousCallPreservesMovedThenCancelsRemainder() throws {
        let recorder = MutationCallRecorder()
        let plan = try TrashExecutionFixtureFactory.approvedTwoTargetPlan()
        var remaining = 1
        let result = try TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder)).execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: plan.targets.map { FreshTargetEvidence.matching($0) },
            isCancelled: {
                remaining -= 1
                return remaining < 0
            }
        ).get()
        #expect(result.state == .interrupted)
        #expect(result.items.first == .moved(destination: "scripted-trash"))
        #expect(result.items.last == .cancelled)
        #expect(recorder.calls == 1)
    }

    @Test
    func onlyAllMovedIsComplete() throws {
        let recorder = MutationCallRecorder()
        let plan = try TrashExecutionFixtureFactory.approvedTwoTargetPlan()
        let result = try TrashExecutionCoordinator(port: ScriptedTrashExecutionPort(recorder: recorder)).execute(
            plan: plan,
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            current: PolicyPlanFixtureFactory.matchingContext(plan),
            freshEvidence: plan.targets.map { FreshTargetEvidence.matching($0) },
            isCancelled: { false }
        ).get()
        #expect(result.state == .complete)
        #expect(recorder.calls == 2)
    }
}

enum StaleSwap: String, CaseIterable {
    case identity
    case directoryKind
    case packageKind
    case logicalSize
    case allocatedSize
    case modification
    case incomplete
    case missingField
    case unavailableRoot
    case semanticOwner
    case detectorVersion
    case locator
    case volume
    case symlink
    case ancestorAlias
    case mount
    case packageBoundary

    var reason: TrashStaleReason {
        switch self {
        case .identity: return .identityChanged
        case .directoryKind, .packageKind: return .fileKindChanged
        case .logicalSize, .allocatedSize: return .sizeChanged
        case .modification: return .modificationChanged
        case .incomplete: return .incompleteFreshEvidence
        case .missingField: return .missingFreshEvidence
        case .unavailableRoot, .detectorVersion: return .rootChanged
        case .semanticOwner: return .semanticOwnerChanged
        case .locator: return .locatorChanged
        case .volume: return .volumeChanged
        case .symlink, .ancestorAlias, .mount, .packageBoundary: return .topologyChanged
        }
    }

    func apply(_ base: FreshTargetEvidence) -> FreshTargetEvidence {
        switch self {
        case .identity:
            return TrashExecutionFixtureFactory.copy(
                base,
                resourceIdentity: .init(device: 99, node: 99)
            )
        case .directoryKind:
            return TrashExecutionFixtureFactory.copy(base, fileKind: .directory)
        case .packageKind:
            return TrashExecutionFixtureFactory.copy(base, fileKind: .package)
        case .logicalSize:
            return TrashExecutionFixtureFactory.copy(base, logicalBytes: base.logicalBytes + 1)
        case .allocatedSize:
            return TrashExecutionFixtureFactory.copy(base, allocatedBytes: base.allocatedBytes + 1)
        case .modification:
            return TrashExecutionFixtureFactory.copy(
                base,
                modificationUnixNanoseconds: base.modificationUnixNanoseconds + 1
            )
        case .incomplete:
            return TrashExecutionFixtureFactory.copy(
                base,
                completeness: .incomplete(reason: .unreadable)
            )
        case .missingField, .unavailableRoot:
            return base
        case .semanticOwner:
            return TrashExecutionFixtureFactory.copy(base, semanticOwner: .modelStore)
        case .detectorVersion:
            return TrashExecutionFixtureFactory.copy(
                base,
                detectorVersion: (try? DetectorVersion("9.9.9")) ?? base.detectorVersion
            )
        case .locator:
            return TrashExecutionFixtureFactory.copy(base, locatorComponents: ["other", "path.bin"])
        case .volume:
            return TrashExecutionFixtureFactory.copy(
                base,
                volume: (try? VolumeID("other-volume")) ?? base.volume
            )
        case .symlink:
            return TrashExecutionFixtureFactory.copy(base, symlink: true)
        case .ancestorAlias:
            return TrashExecutionFixtureFactory.copy(base, alias: true)
        case .mount:
            return TrashExecutionFixtureFactory.copy(base, mount: true)
        case .packageBoundary:
            return TrashExecutionFixtureFactory.copy(base, package: true)
        }
    }
}
