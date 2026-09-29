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

    @Test
    func registryIsVersionedAndClosed() {
        #expect(DeveloperInventoryRegistry.version == "1.1.0")
        #expect(DeveloperToolID.allCases.count == 14)
        #expect(DeveloperInventoryRegistry.records(presence: [:]).count == DeveloperToolID.allCases.count)
    }

    /// Every tool present and sized: the most a developer inventory can ever surface.
    private static let allPresentFacts = DeveloperInventoryRegistry.facts(
        presence: Dictionary(uniqueKeysWithValues: DeveloperToolID.allCases.map { ($0, .present) }),
        sizes: Dictionary(uniqueKeysWithValues: DeveloperToolID.allCases.map { ($0, 1_234) })
    )

    @Test
    func factsCarryOnlyFixedKeysNeverPathsOrNames() {
        #expect(Self.allPresentFacts.count == DeveloperToolID.allCases.count)
        for fact in Self.allPresentFacts {
            #expect(fact.opaqueID.hasPrefix("developer."))
            #expect(fact.presenceKey.hasPrefix("adaptive.developer."))
            #expect(fact.protectionKey == "adaptive.developer.protected")
            for field in [fact.opaqueID, fact.presenceKey, fact.protectionKey] {
                #expect(!field.contains("/"))
                #expect(!field.contains("~"))
            }
        }
    }

    @Test
    func developerFactsAloneCannotProduceACandidatePlanOrOperation() throws {
        let source = AdaptiveExperienceSource(
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
            developerInventory: Self.allPresentFacts
        )

        let authority = try AdaptiveExperienceProjector().project(source, mode: .technical).authority

        #expect(authority.cardKinds.contains(.developerCapability))
        #expect(authority.eligibilities.isEmpty)
        #expect(authority.planDigestHex == nil)
        #expect(authority.capabilityOperations.isEmpty)
        #expect(authority.expectedConservativeBytes == .observed(0))
    }
}
