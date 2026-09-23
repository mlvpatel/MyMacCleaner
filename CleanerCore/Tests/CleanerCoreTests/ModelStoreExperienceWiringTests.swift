import Testing

@testable import CleanerCore

/// C1: the model-store inventory must reach the adaptive experience as a
/// read-only, protected-workflow card — never as a cleanup candidate.
@Suite("Model-store experience wiring")
struct ModelStoreExperienceWiringTests {
    @Test
    func modelInventorySurfacesCardAndAccountingButStaysInventoryOnly() async throws {
        let fixture = try ModelStoreFixtureFactory.sharedHuggingFaceStore()
        let parser = HuggingFaceCacheParser(
            detector: .huggingFaceV1,
            limits: .fixture,
            port: fixture.port,
            cancellation: NeverCancelledModelStoreCancellation()
        )
        let result = await parser.parse(root: fixture.root)
        let projection = ModelStoreProjection(result: result)

        // Guardrail: the store is real content, yet no entry can ever carry an
        // operation and every root reads as protected-not-eligible.
        #expect(!projection.blobs.isEmpty)
        #expect(projection.entries.allSatisfy { $0.operation == nil })
        #expect(projection.entries.allSatisfy { $0.reclaimability == .protectedNotEligible })

        let source = makeSource(modelInventory: [projection])
        let output = try AdaptiveExperienceProjector().project(source, mode: .standard)

        #expect(output.authority.cardKinds.contains(.modelInventory))
        #expect(output.authority.modelInventoryAccounting == [projection.accounting])
    }

    @Test
    func absentModelInventoryYieldsNoCard() throws {
        let source = makeSource(modelInventory: [])
        let output = try AdaptiveExperienceProjector().project(source, mode: .standard)

        #expect(!output.authority.cardKinds.contains(.modelInventory))
        #expect(output.authority.modelInventoryAccounting.isEmpty)
    }

    private func makeSource(modelInventory: [ModelStoreProjection]) -> AdaptiveExperienceSource {
        AdaptiveExperienceSource(
            scanState: .complete,
            findings: [],
            evaluations: [],
            reviewPlan: nil,
            approvalValidity: .invalid(.missingApproval),
            executionState: nil,
            executionOutcomes: [],
            receipts: [],
            memory: nil,
            capabilities: [],
            permissionGaps: [],
            developerInventory: [],
            modelInventory: modelInventory
        )
    }
}
