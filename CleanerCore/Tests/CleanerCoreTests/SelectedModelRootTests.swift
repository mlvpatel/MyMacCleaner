import Testing

@testable import CleanerCore

@Suite("Selected model root inventory")
struct SelectedModelRootTests {
    @Test
    func absentSelectionPerformsNoObservation() async throws {
        let rootID = try DeclaredRootID("selected-root")
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:selected"),
            environmentEvidence: [],
            entries: []
        )
        let inventory = SelectedRootInventory(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )

        let result = await inventory.parse(selectedRoot: nil)

        #expect(result == nil)
        #expect(port.calls.isEmpty)
    }

    @Test
    func unvalidatedSelectionPerformsNoObservation() async throws {
        let rootID = try DeclaredRootID("selected-unvalidated")
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: try VolumeID("volume:selected-unvalidated"),
            environmentEvidence: [],
            entries: [.file(["models", "demo.gguf"], bytes: 5, identity: .init(device: 1, node: 1))]
        )
        let inventory = SelectedRootInventory(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )
        let root = ModelStoreRoot.explicitlySelected(
            rootID: rootID,
            selection: .unvalidated,
            layout: .selectedRootV1
        )

        let result = try #require(await inventory.parse(selectedRoot: root))

        #expect(result.outcome == .corruptMetadata)
        #expect(result.graph.diagnostics.map(\.code) == [.unauthorizedRoot])
        #expect(port.calls.isEmpty)
    }

    @Test
    func validatedSelectionIsGenericProtectedInventory() async throws {
        let rootID = try DeclaredRootID("selected-root")
        let volume = try VolumeID("volume:selected")
        let port = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [.file(["models", "demo.gguf"], bytes: 5, identity: .init(device: 1, node: 1))]
        )
        let inventory = SelectedRootInventory(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        )
        let association = try #require(
            ModelAssociationEvidence(strength: .inferred, kind: .namedLocalFormatEvidence)
        )

        let result = try #require(await inventory.parse(
            selectedRoot: .explicitlySelected(
                rootID: rootID,
                selection: .validated,
                layout: .selectedRootV1
            ),
            association: association
        ))

        #expect(result.outcome == .complete)
        #expect(result.graph.association == association)
        #expect(result.graph.incompleteBlobs.count == 1)
        #expect(result.graph.protection == .inspectOnly(reason: .inventoryOnly))
        #expect(ModelStoreProjection(result: result).entries.allSatisfy { !$0.isSelected && $0.operation == nil })
    }

    @Test(arguments: [ModelStoreEntryTopology.package, .mountTrigger, .alias])
    func topologyBoundaryRemainsProtected(_ topology: ModelStoreEntryTopology) async throws {
        let rootID = try DeclaredRootID("selected-boundary")
        let volume = try VolumeID("volume:boundary")
        let entry = ModelStoreEntryEvidence(
            locator: try .init(["vendor", "payload"]),
            kind: .directory,
            size: .init(logicalBytes: 0),
            fileIdentity: .observed(.init(device: 2, node: 1)),
            volume: .observed(volume),
            text: nil,
            link: nil,
            topology: topology
        )
        let port = ScriptedModelStorePort(rootID: rootID, rootVolume: volume, environmentEvidence: [], entries: [entry], normalizeEntryMetadata: false)
        let result = try #require(await SelectedRootInventory(
            limits: .fixture,
            port: port,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: .explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)))

        #expect(result.outcome == .unsupportedLayout)
        #expect(result.graph.protection == .inspectOnly(reason: .unknownLayout))
    }

    @Test
    func linksAndChangedRootDoNotBecomeGenericFiles() async throws {
        let rootID = try DeclaredRootID("selected-links")
        let volume = try VolumeID("volume:links")
        let linkPort = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            entries: [.symlink(["models", "link"], target: ["outside"], targetVolume: volume)]
        )
        let root = ModelStoreRoot.explicitlySelected(rootID: rootID, selection: .validated, layout: .selectedRootV1)
        let linkResult = try #require(await SelectedRootInventory(
            limits: .fixture,
            port: linkPort,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: root))
        #expect(linkResult.outcome == .unsupportedLayout)
        #expect(linkResult.graph.incompleteBlobs.isEmpty)

        let changedPort = ScriptedModelStorePort(
            rootID: rootID,
            rootVolume: volume,
            environmentEvidence: [],
            rootFault: .rootChanged,
            entries: []
        )
        let changedResult = try #require(await SelectedRootInventory(
            limits: .fixture,
            port: changedPort,
            cancellation: NeverCancelledModelStoreCancellation()
        ).parse(selectedRoot: root))
        #expect(changedResult.outcome == .corruptMetadata)
        #expect(changedResult.graph.protection == .inspectOnly(reason: .changedStore))
    }

    @Test
    func associationStrengthRequiresCompatibleNamedEvidence() {
        #expect(ModelAssociationEvidence(strength: .proven, kind: .explicitFormatField)?.strength == .proven)
        #expect(ModelAssociationEvidence(strength: .proven, kind: .explicitProvenanceField)?.strength == .proven)
        #expect(ModelAssociationEvidence(strength: .inferred, kind: .namedLocalFormatEvidence)?.strength == .inferred)
        #expect(ModelAssociationEvidence(strength: .unknown, kind: .noObservedEvidence)?.strength == .unknown)
        #expect(ModelAssociationEvidence(strength: .proven, kind: .namedLocalFormatEvidence) == nil)
        #expect(ModelAssociationEvidence(strength: .unknown, kind: .explicitFormatField) == nil)
    }
}
