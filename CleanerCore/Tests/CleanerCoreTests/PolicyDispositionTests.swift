import Testing

@testable import CleanerCore

@Suite("Deny-first policy disposition")
struct PolicyDispositionTests {
    @Test
    func fixedCompleteGeneralCacheTravelsThroughPolicyRankAndCard() throws {
        let finding = try policyFixtureFinding()
        let evaluation = PolicyEvaluator().evaluate(finding)

        #expect(evaluation.disposition == .safeToRegenerate)
        #expect(evaluation.eligibility == .eligible)
        #expect(evaluation.semanticOwner == .generalRebuildableCache)
        #expect(evaluation.rule == .generalCacheRegenerationV1)
        #expect(evaluation.candidate != nil)

        guard let candidate = evaluation.candidate else {
            Issue.record("The fixed cache should be the sole initial candidate path.")
            return
        }

        let rank = ConservativeRank.key(for: candidate)
        #expect(rank.conservativeBytes == 4_096)

        let card = CapabilityCardProjection().card(
            for: .init(id: finding.finding.detectorID, version: finding.finding.detectorVersion),
            evaluation: evaluation
        )
        #expect(card.authority == .reviewPlanCapable)
        #expect(card.conditionalOperation == .moveToTrashAfterApprovalAndFreshRevalidation)
        #expect(card.recoveryPath == .rebuildable)
        #expect(card.confidence == .observed)
        #expect(card.protectionReason == nil)
    }

    @Test
    func incompleteFindingRemainsVisibleButNeverBecomesCandidate() throws {
        let finding = try policyFixtureFinding(completeness: .incomplete(reason: .unavailableMetadata))
        let evaluation = PolicyEvaluator().evaluate(finding)

        #expect(evaluation.disposition == .unknownInspectFirst)
        #expect(evaluation.eligibility == .ineligible)
        #expect(evaluation.candidate == nil)

        let card = CapabilityCardProjection().card(
            for: .init(id: finding.finding.detectorID, version: finding.finding.detectorVersion),
            evaluation: evaluation
        )
        #expect(card.authority == .inventoryOnly)
        #expect(card.conditionalOperation == .none)
        #expect(card.protectionReason == .incompleteEvidence)
    }

    @Test
    func tamperedPolicySpaceCannotMintACandidate() throws {
        let original = try policyFixtureFinding()
        let tampered = GeneralMacFinding(
            finding: original.finding,
            category: original.category,
            source: original.source,
            age: original.age,
            space: .init(
                logicalBytes: .observed(4_097),
                allocatedBytes: original.space.allocatedBytes,
                sharedBytes: .observed(0),
                conservativeReclaimableBytes: original.space.conservativeReclaimableBytes
            ),
            rebuildImpact: original.rebuildImpact,
            confidence: original.confidence,
            conservativeRisk: original.conservativeRisk,
            completeness: .complete
        )

        let evaluation = PolicyEvaluator().evaluate(tampered)
        #expect(evaluation.disposition == .unknownInspectFirst)
        #expect(evaluation.candidate == nil)
    }
}

private func policyFixtureFinding(
    completeness: GeneralMacEvidenceCompleteness = .complete,
    category: GeneralMacCategory = .cache,
    source: GeneralMacRootKind = .userLibraryCaches,
    rebuildImpact: RebuildImpact = .rebuildable,
    confidence: EvidenceConfidence = .observed,
    conservativeRisk: ConservativeRisk = .low,
    sharedBytes: EvidenceValue<Int64> = .observed(0)
) throws -> GeneralMacFinding {
    let rootID = try DeclaredRootID("user-library-caches")
    let identity: EvidenceValue<FileIdentityEvidence> = completeness == .complete
        ? .observed(.init(device: 1, node: 2))
        : .unavailable
    let observation = try FileObservation(
        rootID: rootID,
        locator: .init(rootID: rootID, components: ["com.apple.iconservices.store", "cache.bin"]),
        resourceIdentity: identity,
        sizes: .init(logicalBytes: .observed(4_096), allocatedBytes: .observed(4_096)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: .regularFile,
        volume: .observed(try .init("fixture-volume")),
        linkCount: .observed(1),
        boundaries: .init(
            symlink: .observed(false),
            alias: .observed(false),
            package: .observed(false),
            mount: .observed(false),
            protectedRoot: .observed(false),
            homeBoundary: .observed(false),
            externalVolume: .observed(false)
        )
    )
    let detector = GeneralMacEvidenceDetector(scope: source)
    let result = detector.makeFinding(
        from: observation,
        request: try GeneralMacScopeCatalog.current.scanRequest(for: [source]),
        clockReading: .init(
            observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
            wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
        )
    )
    let generalFinding = try #require(try result.get())
    #expect(generalFinding.category == category)
    #expect(generalFinding.rebuildImpact == rebuildImpact)
    #expect(generalFinding.confidence == confidence)
    #expect(generalFinding.conservativeRisk == conservativeRisk)
    #expect(generalFinding.completeness == completeness)
    #expect(generalFinding.space.sharedBytes == sharedBytes)
    return generalFinding
}
