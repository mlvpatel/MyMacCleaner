import Testing

@testable import CleanerCore

@Suite("Conservative policy ranking")
struct PolicyRankingTests {
    @Test
    func rankingIsLexicographicAndNeverByteFirst() throws {
        let recoveryWins = try rankingCandidate(
            name: "recovery", recovery: .rebuild, confidence: .unavailable,
            impact: .protected, bytes: 1
        )
        let confidenceWins = try rankingCandidate(
            name: "confidence", recovery: .redownload, confidence: .observed,
            impact: .protected, bytes: 1
        )
        let workflowWins = try rankingCandidate(
            name: "workflow", recovery: .redownload, confidence: .partial,
            impact: .none, bytes: 1
        )
        let bytesWins = try rankingCandidate(
            name: "bytes", recovery: .redownload, confidence: .partial,
            impact: .review, bytes: 2
        )
        let stableFirst = try rankingCandidate(
            name: "a", recovery: .redownload, confidence: .partial,
            impact: .review, bytes: 2
        )

        let ordered = ConservativeRank.ordered([
            bytesWins, confidenceWins, stableFirst, workflowWins, recoveryWins,
        ])

        #expect(ordered == [recoveryWins, confidenceWins, workflowWins, stableFirst, bytesWins])
    }

    @Test
    func everyVisibleDispositionHasClosedFailSafeSemantics() throws {
        let evaluator = PolicyEvaluator()
        let log = try generalFinding(scope: .userLibraryLogs, components: ["entry.log"])
        let crash = try generalFinding(scope: .userLibraryLogs, components: ["DiagnosticReports", "entry.crash"])
        let temporary = try generalFinding(scope: .userTemporary, components: ["entry.tmp"])
        let unknown = try generalFinding(
            scope: .userLibraryCaches,
            components: ["com.apple.iconservices.store", "entry.bin"],
            complete: false
        )
        let protected = evaluator.protectedEvaluation(
            detector: .init(id: ModelStoreDetector.ollamaV1.id, version: ModelStoreDetector.ollamaV1.version),
            owner: .modelStore
        )

        #expect(evaluator.evaluate(log).disposition == .mayAffectWorkflow)
        #expect(evaluator.evaluate(crash).disposition == .mayAffectWorkflow)
        #expect(evaluator.evaluate(temporary).disposition == .redownloadRequired)
        #expect(evaluator.evaluate(unknown).disposition == .unknownInspectFirst)
        #expect(protected.disposition == .keepProtected)
        #expect(Set(PolicyDisposition.allCases) == [
            .safeToRegenerate, .redownloadRequired, .mayAffectWorkflow,
            .keepProtected, .unknownInspectFirst,
        ])
    }
}

private func rankingCandidate(
    name: String,
    recovery: RecoveryCost,
    confidence: EvidenceConfidence,
    impact: WorkflowImpact,
    bytes: Int64
) throws -> EligibleCandidate {
    let finding = try generalFinding(scope: .userLibraryCaches, components: ["ranking", name])
    return .init(
        evidence: .init(
            finding: finding,
            activity: .observedInactive,
            scopeProof: .namedFixedScopeGeneralCacheV1
        ),
        semanticOwner: .generalRebuildableCache,
        rule: .generalCacheRegenerationV1,
        rationale: .namedSafeRegenerationRule,
        rankFactors: .init(
            recoveryCost: recovery,
            confidence: confidence,
            workflowImpact: impact,
            conservativeBytes: bytes
        )
    )
}

private func generalFinding(
    scope: GeneralMacRootKind,
    components: [String],
    complete: Bool = true
) throws -> GeneralMacFinding {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: scope)
    let observation = try FileObservation(
        rootID: root.id,
        locator: .init(rootID: root.id, components: components),
        resourceIdentity: complete ? .observed(.init(device: 4, node: 8)) : .unavailable,
        sizes: .init(logicalBytes: .observed(64), allocatedBytes: .observed(64)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: .regularFile,
        volume: .observed(try .init("policy-ranking-volume")),
        linkCount: .observed(1),
        boundaries: .init(
            symlink: .observed(false), alias: .observed(false), package: .observed(false),
            mount: .observed(false), protectedRoot: .observed(false),
            homeBoundary: .observed(false), externalVolume: .observed(false)
        )
    )
    let result = GeneralMacEvidenceDetector(scope: scope).makeFinding(
        from: observation,
        request: try catalog.scanRequest(for: [scope]),
        clockReading: .init(
            observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
            wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
        )
    )
    return try #require(try result.get())
}
