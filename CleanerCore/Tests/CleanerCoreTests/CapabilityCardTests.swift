import Testing

@testable import CleanerCore

@Suite("Capability card projection")
struct CapabilityCardTests {
    @Test
    func everyRegisteredDetectorHasOneExhaustiveNonOperableOrConditionalCard() throws {
        let evaluator = PolicyEvaluator()
        let cache = try capabilityCacheFinding()
        let cards = CapabilityCardProjection().cards(for: [evaluator.evaluate(cache)])

        #expect(cards.map(\.detector) == [
            .init(id: GeneralMacScopeCatalog.current.detectorID, version: GeneralMacScopeCatalog.current.version),
            ModelStoreDetectorRegistration.huggingFaceSelection,
            ModelStoreDetectorRegistration.ollamaSelection,
            ModelStoreDetectorRegistration.selectedRootSelection,
        ])
        #expect(cards.first?.authority == .reviewPlanCapable)
        #expect(cards.first?.conditionalOperation == .moveToTrashAfterApprovalAndFreshRevalidation)
        for card in cards.dropFirst() {
            #expect(card.authority == .inventoryOnly)
            #expect(card.conditionalOperation == .none)
            // Unscanned model-store detectors read "not observed", not a synthesized "protected".
            #expect(card.protectionReason == .notObserved)
        }
    }

    @Test
    func observedProtectedStoreStaysProtectedWhileUnobservedReadsNotObserved() throws {
        let evaluator = PolicyEvaluator()
        let cache = try capabilityCacheFinding()
        let huggingFace = ModelStoreDetectorRegistration.huggingFaceSelection
        let protectedHuggingFace = evaluator.protectedEvaluation(detector: huggingFace, owner: .modelStore)

        let cards = CapabilityCardProjection().cards(for: [evaluator.evaluate(cache), protectedHuggingFace])
        let huggingFaceCard = try #require(cards.first { $0.detector == huggingFace })
        let ollamaCard = try #require(
            cards.first { $0.detector == ModelStoreDetectorRegistration.ollamaSelection }
        )

        // A store that WAS observed and is protected keeps the protected reason...
        #expect(huggingFaceCard.protectionReason == .protectedSemanticOwner)
        // ...while a store with no evaluation reads notObserved — the two are never conflated.
        #expect(ollamaCard.protectionReason == .notObserved)
        #expect(huggingFaceCard.authority == .inventoryOnly)
        #expect(ollamaCard.authority == .inventoryOnly)
    }

    @Test(arguments: PolicySemanticOwner.allCases)
    fileprivate func protectedOwnersCanNeverBecomeReviewPlanCards(_ owner: PolicySemanticOwner) throws {
        let detector = DetectorSelection(
            id: ModelStoreDetector.selectedRootV1.id,
            version: ModelStoreDetector.selectedRootV1.version
        )
        let evaluation = PolicyEvaluator().protectedEvaluation(detector: detector, owner: owner)
        let card = CapabilityCardProjection().card(for: detector, evaluation: evaluation)

        #expect(evaluation.candidate == nil)
        #expect(card.authority == .inventoryOnly)
        #expect(card.conditionalOperation == .none)
        #expect(card.protectionReason == .protectedSemanticOwner)
    }

    @Test
    func conflictingFactsForOneRegisteredDetectorFailClosedRegardlessOfInputOrder() throws {
        let evaluator = PolicyEvaluator()
        let selection = DetectorSelection(
            id: GeneralMacScopeCatalog.current.detectorID,
            version: GeneralMacScopeCatalog.current.version
        )
        let safe = evaluator.evaluate(try capabilityCacheFinding())
        let protected = evaluator.protectedEvaluation(detector: selection, owner: .unknown)

        for evaluations in [[safe, protected], [protected, safe]] {
            let card = try #require(CapabilityCardProjection().cards(for: evaluations).first)
            #expect(card.authority == .inventoryOnly)
            #expect(card.conditionalOperation == .none)
            #expect(card.protectionReason == .protectedSemanticOwner)
        }
    }
}

private func capabilityCacheFinding() throws -> GeneralMacFinding {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: .userLibraryCaches)
    let observation = try FileObservation(
        rootID: root.id,
        locator: .init(rootID: root.id, components: ["com.apple.iconservices.store", "card.bin"]),
        resourceIdentity: .observed(.init(device: 2, node: 9)),
        sizes: .init(logicalBytes: .observed(1), allocatedBytes: .observed(1)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: .regularFile,
        volume: .observed(try .init("card-volume")),
        linkCount: .observed(1),
        boundaries: .init(
            symlink: .observed(false), alias: .observed(false), package: .observed(false),
            mount: .observed(false), protectedRoot: .observed(false),
            homeBoundary: .observed(false), externalVolume: .observed(false)
        )
    )
    let result = GeneralMacEvidenceDetector(scope: .userLibraryCaches).makeFinding(
        from: observation,
        request: try catalog.scanRequest(for: [.userLibraryCaches]),
        clockReading: .init(
            observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
            wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
        )
    )
    return try #require(try result.get())
}
