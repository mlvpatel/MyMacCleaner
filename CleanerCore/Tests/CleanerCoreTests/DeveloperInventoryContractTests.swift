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

    @Test
    func sizedRecordsStayProtectedAndSizesNeverAttachToAbsentTools() {
        let records = DeveloperInventoryRegistry.records(
            presence: [.claudeConfig: .present, .codex: .absent],
            sizes: [.claudeConfig: 12_345, .codex: 999]
        )
        let claude = records.first { $0.tool == .claudeConfig }
        #expect(claude?.sizeBytes == 12_345)
        #expect(claude?.protection == .protectedSemanticOwner)
        #expect(claude?.inventoryFact?.sizeBytes == 12_345)
        // An absent tool never surfaces a size, even if one was supplied.
        #expect(records.first { $0.tool == .codex }?.inventoryFact?.sizeBytes == nil)
        // Every tool, old and new, remains protected and inventory-only.
        #expect(records.allSatisfy { $0.protection == .protectedSemanticOwner })
    }
}
