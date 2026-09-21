import Testing

@testable import CleanerCore

@Suite("AI model hostile fixtures")
struct AIModelHostileFixtureTests {
    @Test
    func changedHuggingFaceRootStopsBeforeAnyTraversal() async throws {
        let fixture = try ModelStoreFixtureFactory.changedHuggingFaceRootIdentity()
        let result = await HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: fixture.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: fixture.root)

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.diagnostics.map(\.code) == [.rootChanged])
        #expect(result.graph.protection == .inspectOnly(reason: .changedStore))
        #expect(fixture.port.calls == [.rootEvidence(ModelStoreRoot.huggingFaceDefaultRootID)])
        #expect(ModelStoreAccounting(graph: result.graph).summary.reclaimability == .protectedNotEligible)
    }

    @Test(arguments: [
        ("ollama-layout-drift", ModelStoreDiagnosticCode.unknownLayout, ModelStoreProtectionReason.unknownLayout),
    ])
    func unsupportedVendorEvidenceRemainsProtected(
        _ expectation: (String, ModelStoreDiagnosticCode, ModelStoreProtectionReason)
    ) async throws {
        let fixture = try ModelStoreFixtureFactory.unsupportedOllamaManifest()
        let result = await OllamaStoreParser(
            limits: .fixture,
            port: fixture.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: fixture.root)

        #expect(expectation.0 == "ollama-layout-drift")
        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.diagnostics.map(\.code) == [expectation.1])
        #expect(result.graph.protection == .inspectOnly(reason: expectation.2))
        #expect(result.graph.snapshotBlobEdges.isEmpty)
    }

    @Test
    func selectedRootTopologyBoundaryRemainsGenericAndNonOperable() async throws {
        let fixture = try ModelStoreFixtureFactory.selectedRootBoundary()
        let result = try #require(await SelectedRootInventory(
            limits: .fixture,
            port: fixture.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: fixture.root))

        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.diagnostics.map(\.code) == [.unknownLayout])
        #expect(result.graph.incompleteBlobs.isEmpty)
        #expect(ModelStoreAccounting(graph: result.graph).summary.reclaimability == .protectedNotEligible)
    }

    @Test
    func laterHuggingFaceLayoutFaultRetainsEarlierProtectedEvidence() async throws {
        let fixture = try ModelStoreFixtureFactory.partialHuggingFaceStore()
        let result = await HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: fixture.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: fixture.root)

        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.repositories.map(\.identity.repositoryID) == ["models--synthetic--repo"])
        #expect(result.graph.protection == .inspectOnly(reason: .unknownLayout))
        #expect(ModelStoreAccounting(graph: result.graph).summary.reclaimability == .protectedNotEligible)
    }

    @Test
    func changedOllamaStoreAndCancelledSelectedRootStopWithExactProtection() async throws {
        let ollama = try ModelStoreFixtureFactory.changedOllamaStore()
        let ollamaResult = await OllamaStoreParser(
            limits: .fixture,
            port: ollama.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: ollama.root)
        #expect(ollamaResult.outcome == .corruptMetadata)
        #expect(ollamaResult.graph.diagnostics.map(\.code) == [.volumeChanged])
        #expect(ollamaResult.graph.protection == .inspectOnly(reason: .changedStore))

        let selected = try ModelStoreFixtureFactory.cancelledSelectedRoot()
        let selectedResult = try #require(await SelectedRootInventory(
            limits: .fixture,
            port: selected.port,
            cancellation: ScriptedModelStoreCancellation(responses: [false, true])
        ).parse(selectedRoot: selected.root))
        #expect(selectedResult.outcome == .cancelled)
        #expect(selectedResult.graph.diagnostics.map(\.code) == [.cancelled])
        #expect(selected.port.calls == [.rootEvidence(selected.root.identity.rootID)])
        #expect(selectedResult.graph.incompleteBlobs.isEmpty)
    }

    @Test
    func absentSelectedAuthorityHasNoCapabilityCalls() async throws {
        let rootID = try DeclaredRootID("synthetic-absent-selected-root")
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:synthetic-absent-selected-root"),
            environmentEvidence: [],
            entries: []
        )
        let result = await SelectedRootInventory(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: nil)

        #expect(result == nil)
        #expect(port.calls.isEmpty)
    }

    @Test
    func huggingFaceSharedIncompleteAndHostileMatrixKeepsEvidenceProtected() async throws {
        let shared = try ModelStoreFixtureFactory.sharedHuggingFaceStore()
        let sharedResult = await HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: shared.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: shared.root)
        let accounting = ModelStoreAccounting(graph: sharedResult.graph).summary

        #expect(sharedResult.outcome == .complete)
        #expect(sharedResult.graph.blobs.count == 1)
        #expect(sharedResult.graph.incompleteBlobs.count == 1)
        #expect(sharedResult.graph.snapshotBlobEdges.count == 2)
        #expect(accounting.logicalReferencedBytes == .observed(20))
        #expect(accounting.uniquePhysicalBytes == .observed(10))
        #expect(accounting.sharedBytesIncludedInUniquePhysical == .observed(10))
        #expect(accounting.reclaimability == .protectedNotEligible)
        #expect(shared.port.calls.count == 16)

        let dangling = try ModelStoreFixtureFactory.danglingHuggingFaceLink()
        let danglingResult = await HuggingFaceCacheParser(
            detector: .huggingFaceV1, limits: .fixture, port: dangling.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: dangling.root)
        #expect(danglingResult.outcome == .corruptMetadata)
        #expect(danglingResult.graph.diagnostics.map(\.code) == [.danglingLink])
        #expect(danglingResult.graph.protection == .inspectOnly(reason: .invalidLink))
        #expect(dangling.port.calls.count == 4)

        let crossVolume = try ModelStoreFixtureFactory.crossVolumeHuggingFaceLink()
        let crossVolumeResult = await HuggingFaceCacheParser(
            detector: .huggingFaceV1, limits: .fixture, port: crossVolume.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: crossVolume.root)
        #expect(crossVolumeResult.outcome == .unsupportedLayout)
        #expect(crossVolumeResult.graph.diagnostics.map(\.code) == [.crossVolumeLink])
        #expect(crossVolumeResult.graph.protection == .inspectOnly(reason: .boundaryViolation))
        #expect(crossVolume.port.calls.count == 4)

        let unavailable = try ModelStoreFixtureFactory.unavailableHuggingFaceStore()
        let unavailableResult = await HuggingFaceCacheParser(
            detector: .huggingFaceV1, limits: .fixture, port: unavailable.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: unavailable.root)
        #expect(unavailableResult.outcome == .unsupportedLayout)
        #expect(unavailableResult.graph.diagnostics.map(\.code) == [.unavailableVolume])
        #expect(unavailable.port.calls.count == 1)

        let budget = try ModelStoreFixtureFactory.budgetHuggingFaceStore()
        let budgetResult = await HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: try .init(maximumEntries: 8, maximumRefBytes: 4_096, maximumGraphNodes: 8, maximumGraphEdges: 8, maximumObservedBytes: 1),
            port: budget.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: budget.root)
        #expect(budgetResult.outcome == .corruptMetadata)
        #expect(budgetResult.graph.diagnostics.map(\.code) == [.observedByteLimitExceeded])
        #expect(budget.port.calls.count == 3)

        let cancelled = try ModelStoreFixtureFactory.cancelledHuggingFaceStore()
        let cancelledResult = await HuggingFaceCacheParser(
            detector: .huggingFaceV1, limits: .fixture, port: cancelled.port,
            cancellation: ScriptedModelStoreCancellation(responses: [false, true])
        ).parse(root: cancelled.root)
        #expect(cancelledResult.outcome == .cancelled)
        #expect(cancelledResult.graph.diagnostics.map(\.code) == [.cancelled])
        #expect(cancelled.port.calls == [.rootEvidence(cancelled.root.identity.rootID)])
    }

    @Test
    func ollamaSharedMissingBoundaryUnavailableBudgetAndCancellationMatrixStaysProtected() async throws {
        let shared = try ModelStoreFixtureFactory.sharedOllamaStore()
        let sharedResult = await OllamaStoreParser(
            limits: .fixture, port: shared.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: shared.root)
        let accounting = ModelStoreAccounting(graph: sharedResult.graph).summary
        #expect(sharedResult.outcome == .complete)
        #expect(sharedResult.graph.refs.count == 2)
        #expect(sharedResult.graph.blobs.count == 2)
        #expect(sharedResult.graph.snapshotBlobEdges.count == 4)
        #expect(accounting.logicalReferencedBytes == .observed(30))
        #expect(accounting.uniquePhysicalBytes == .observed(15))
        #expect(accounting.reclaimability == .protectedNotEligible)
        #expect(shared.port.calls.count == 10)

        let missing = try ModelStoreFixtureFactory.missingOllamaBlobStore()
        let missingResult = await OllamaStoreParser(
            limits: .fixture, port: missing.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: missing.root)
        #expect(missingResult.outcome == .corruptMetadata)
        #expect(missingResult.graph.diagnostics.map(\.code) == [.missingBlob])
        #expect(missingResult.graph.snapshotBlobEdges.isEmpty)
        #expect(missing.port.calls.count == 4)

        let crossVolume = try ModelStoreFixtureFactory.crossVolumeOllamaStore()
        let crossVolumeResult = await OllamaStoreParser(
            limits: .fixture, port: crossVolume.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: crossVolume.root)
        #expect(crossVolumeResult.outcome == .unsupportedLayout)
        #expect(crossVolumeResult.graph.diagnostics.map(\.code) == [.crossVolumeLink])
        #expect(crossVolumeResult.graph.snapshotBlobEdges.isEmpty)
        #expect(crossVolume.port.calls.count == 4)

        let unavailable = try ModelStoreFixtureFactory.unavailableOllamaStore()
        let unavailableResult = await OllamaStoreParser(
            limits: .fixture, port: unavailable.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: unavailable.root)
        #expect(unavailableResult.outcome == .unsupportedLayout)
        #expect(unavailableResult.graph.diagnostics.map(\.code) == [.unavailableVolume])
        #expect(unavailable.port.calls.count == 1)

        let budget = try ModelStoreFixtureFactory.budgetOllamaStore()
        let budgetResult = await OllamaStoreParser(
            limits: try .init(maximumEntries: 8, maximumRefBytes: 4_096, maximumGraphNodes: 8, maximumGraphEdges: 8, maximumObservedBytes: 1),
            port: budget.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(root: budget.root)
        #expect(budgetResult.outcome == .corruptMetadata)
        #expect(budgetResult.graph.diagnostics.map(\.code) == [.observedByteLimitExceeded])
        #expect(budget.port.calls.count == 2)

        let cancelled = try ModelStoreFixtureFactory.cancelledOllamaStore()
        let cancelledResult = await OllamaStoreParser(
            limits: .fixture, port: cancelled.port,
            cancellation: ScriptedModelStoreCancellation(responses: [false, true])
        ).parse(root: cancelled.root)
        #expect(cancelledResult.outcome == .cancelled)
        #expect(cancelledResult.graph.diagnostics.map(\.code) == [.cancelled])
        #expect(cancelled.port.calls == [.rootEvidence(cancelled.root.identity.rootID)])
    }

    @Test
    func selectedRootMatrixKeepsEveryMLXAssociationAndBoundaryNonOperable() async throws {
        let associations = [
            try #require(ModelAssociationEvidence(strength: .proven, kind: .explicitFormatField)),
            try #require(ModelAssociationEvidence(strength: .inferred, kind: .namedLocalFormatEvidence)),
            ModelAssociationEvidence.unknown,
        ]
        for association in associations {
            let selected = try ModelStoreFixtureFactory.selectedRootForAssociation()
            let result = try #require(await SelectedRootInventory(
                limits: .fixture, port: selected.port, cancellation: NeverCancelledModelStoreCancellation()
            ).parse(selectedRoot: selected.root, association: association))
            let projection = ModelStoreProjection(result: result)
            #expect(result.outcome == .complete)
            #expect(result.graph.association == association)
            #expect(result.graph.incompleteBlobs.count == 1)
            #expect(result.graph.protection == .inspectOnly(reason: .inventoryOnly))
            #expect(projection.entries.allSatisfy { !$0.isSelected && $0.operation == nil })
            #expect(selected.port.calls.count == 3)
        }

        let escaping = try ModelStoreFixtureFactory.escapingSelectedRoot()
        let escapingResult = try #require(await SelectedRootInventory(
            limits: .fixture, port: escaping.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: escaping.root))
        #expect(escapingResult.outcome == .unsupportedLayout)
        #expect(escapingResult.graph.diagnostics.map(\.code) == [.escapingLink])
        #expect(escapingResult.graph.incompleteBlobs.isEmpty)
        #expect(escaping.port.calls.count == 2)

        let crossVolume = try ModelStoreFixtureFactory.crossVolumeSelectedRoot()
        let crossVolumeResult = try #require(await SelectedRootInventory(
            limits: .fixture, port: crossVolume.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: crossVolume.root))
        #expect(crossVolumeResult.outcome == .unsupportedLayout)
        #expect(crossVolumeResult.graph.diagnostics.map(\.code) == [.crossVolumeLink])
        #expect(crossVolume.port.calls.count == 2)

        let unavailable = try ModelStoreFixtureFactory.unavailableSelectedRoot()
        let unavailableResult = try #require(await SelectedRootInventory(
            limits: .fixture, port: unavailable.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: unavailable.root))
        #expect(unavailableResult.outcome == .unsupportedLayout)
        #expect(unavailableResult.graph.diagnostics.map(\.code) == [.unavailableVolume])
        #expect(unavailable.port.calls.count == 1)

        let changed = try ModelStoreFixtureFactory.changedSelectedRoot()
        let changedResult = try #require(await SelectedRootInventory(
            limits: .fixture, port: changed.port, cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: changed.root))
        #expect(changedResult.outcome == .corruptMetadata)
        #expect(changedResult.graph.diagnostics.map(\.code) == [.rootChanged])
        #expect(changed.port.calls == [.rootEvidence(changed.root.identity.rootID)])

        let budget = try ModelStoreFixtureFactory.budgetSelectedRoot()
        let budgetResult = try #require(await SelectedRootInventory(
            limits: try .init(maximumEntries: 8, maximumRefBytes: 4_096, maximumGraphNodes: 8, maximumGraphEdges: 8, maximumObservedBytes: 1),
            port: budget.port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: budget.root))
        #expect(budgetResult.outcome == .corruptMetadata)
        #expect(budgetResult.graph.diagnostics.map(\.code) == [.observedByteLimitExceeded])
        #expect(budget.port.calls.count == 2)
    }
}
