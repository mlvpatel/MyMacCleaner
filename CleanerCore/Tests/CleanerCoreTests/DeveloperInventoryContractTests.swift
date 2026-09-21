import Testing

@testable import CleanerCore

@Suite("Developer Inventory Contract")
struct DeveloperInventoryContractTests {
    @Test
    func everyToolRecordIsInventoryOnlyAndProtected() {
        let records = DeveloperInventoryRegistry.records(presence: [
            .cursor: .present,
            .vscode: .absent,
            .docker: .unavailable,
            .homebrew: .unavailable
        ])
        #expect(records.map(\.tool) == DeveloperToolID.allCases)
        for record in records {
            #expect(record.protection == .protectedSemanticOwner)
            #expect(record.inventoryFact != nil)
        }
        let facts = DeveloperInventoryRegistry.facts(presence: [.cursor: .present])
        #expect(facts.contains { $0.opaqueID == "developer.cursor" })
    }

    @Test
    func unknownPresenceDefaultsToUnavailableWithoutBecomingACandidate() {
        let records = DeveloperInventoryRegistry.records(presence: [:])
        #expect(records.allSatisfy { $0.presence == .unavailable })
        #expect(records.allSatisfy { $0.protection == .protectedSemanticOwner })
    }
}
