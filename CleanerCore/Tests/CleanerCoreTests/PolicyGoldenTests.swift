import Testing

@testable import CleanerCore

@Suite("Exhaustive policy and protected-owner golden matrix")
struct PolicyGoldenTests {
    @Test
    func namedFixedScopeCacheIsTheOnlyPositiveCandidate() throws {
        let evaluation = PolicyEvaluator().evaluate(
            try PolicyPlanFixtureFactory.finding(
                components: ["com.apple.iconservices.store", "cache.bin"]
            )
        )
        #expect(evaluation.disposition == .safeToRegenerate)
        #expect(evaluation.eligibility == .eligible)
        #expect(evaluation.semanticOwner == .generalRebuildableCache)
        #expect(evaluation.rule == .generalCacheRegenerationV1)
        #expect(evaluation.rationale == .namedSafeRegenerationRule)
        #expect(evaluation.recoveryPath == .rebuildable)
        #expect(evaluation.candidate != nil)

        let card = CapabilityCardProjection().card(
            for: evaluation.detector,
            evaluation: evaluation
        )
        #expect(card.authority == .reviewPlanCapable)
        #expect(card.conditionalOperation == .moveToTrashAfterApprovalAndFreshRevalidation)
    }

    @Test
    func logCrashAndTemporaryRemainReviewOnlyWithoutNamedRebuildProof() throws {
        let evaluator = PolicyEvaluator()
        let log = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(scope: .userLibraryLogs, components: ["entry.log"])
        )
        let crash = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(
                scope: .userLibraryLogs,
                components: ["DiagnosticReports", "entry.crash"]
            )
        )
        let temporary = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(scope: .userTemporary, components: ["entry.tmp"])
        )

        #expect(log.disposition == .mayAffectWorkflow)
        #expect(log.rule == .generalLogReviewV1)
        #expect(log.candidate == nil)
        #expect(crash.disposition == .mayAffectWorkflow)
        #expect(crash.rule == .generalCrashReviewV1)
        #expect(crash.candidate == nil)
        #expect(temporary.disposition == .redownloadRequired)
        #expect(temporary.rule == .generalTemporaryReviewV1)
        #expect(temporary.candidate == nil)
        #expect(Set(PolicyDisposition.allCases).count == 5)
    }

    @Test
    func personalLargeFilesNeverBecomeCandidatesOrTargets() throws {
        let evaluation = PolicyEvaluator().evaluate(
            try PolicyPlanFixtureFactory.finding(scope: .userDownloads, components: ["movie.mov"], bytes: 50_000_000)
        )
        #expect(evaluation.semanticOwner == .personalLargeFile)
        #expect(evaluation.eligibility == .ineligible)
        #expect(evaluation.candidate == nil)
        #expect(throws: ReviewPlanBuildError.emptySelection) {
            try ReviewPlanDraft(
                selectedCandidates: [],
                versionContext: PolicyPlanFixtureFactory.versionContext(),
                launchSession: PolicyPlanFixtureFactory.launchSession(),
                createdAt: PolicyPlanFixtureFactory.createdAt
            )
        }
    }

    @Test(arguments: [
        PolicySemanticOwner.duplicateEvidence,
        .modelStore,
        .developerToolState,
        .credential,
        .setting,
        .workloadObservation,
        .unknown,
    ])
    fileprivate func protectedOwnersHaveNoCandidateOrTargetPath(_ owner: PolicySemanticOwner) throws {
        let evaluation = PolicyEvaluator().protectedEvaluation(
            detector: ModelStoreDetectorRegistration.huggingFaceSelection,
            owner: owner
        )
        #expect(evaluation.disposition == .keepProtected)
        #expect(evaluation.eligibility == .ineligible)
        #expect(evaluation.candidate == nil)
        #expect(evaluation.recoveryPath == .protectedNoOperation)
        let card = CapabilityCardProjection().card(for: evaluation.detector, evaluation: evaluation)
        #expect(card.authority == .inventoryOnly)
        #expect(card.conditionalOperation == .none)
    }

    @Test
    func incompleteSharedBoundaryAndUnsupportedEvidenceStayIneligible() throws {
        let evaluator = PolicyEvaluator()
        let incomplete = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(
                components: ["com.apple.iconservices.store", "partial.bin"],
                complete: false
            )
        )
        let boundary = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(
                components: ["com.apple.iconservices.store", "link.bin"],
                symlink: true
            )
        )
        let mismatchedCache = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(components: ["other.cache", "file.bin"])
        )

        #expect(incomplete.candidate == nil)
        #expect(incomplete.rationale == .incompleteEvidence)
        #expect(boundary.candidate == nil)
        #expect(mismatchedCache.candidate == nil)
        #expect(mismatchedCache.eligibility == .ineligible)
    }

    @Test(arguments: CacheOwnerGolden.all)
    fileprivate func knownCacheOwnersAreLabelledButNeverEligible(_ golden: CacheOwnerGolden) throws {
        let evaluation = PolicyEvaluator().evaluate(
            try PolicyPlanFixtureFactory.finding(components: golden.components)
        )
        #expect(evaluation.disposition == golden.disposition)
        #expect(evaluation.semanticOwner == golden.owner)
        #expect(evaluation.recoveryPath == golden.recovery)
        #expect(evaluation.rule == golden.rule)
        #expect(evaluation.eligibility == .ineligible)
        #expect(evaluation.candidate == nil)
    }

    @Test
    func unlistedCachesKeepTheNamedScopeRule() throws {
        let evaluator = PolicyEvaluator()
        let browser = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(components: ["Google", "Chrome", "Default", "Cache", "f_000001"])
        )
        let named = evaluator.evaluate(
            try PolicyPlanFixtureFactory.finding(components: ["com.apple.iconservices.store", "cache.bin"])
        )
        #expect(browser.disposition == .unknownInspectFirst)
        #expect(browser.rationale == .unsupportedEvidence)
        #expect(browser.candidate == nil)
        #expect(named.eligibility == .eligible)
        #expect(GeneralMacCacheOwnerCatalog.current.version == "1.0.0")
    }

    @Test
    func cacheOwnerCatalogNeverWidensEligibility() throws {
        let samples = CacheOwnerGolden.all.map(\.components) + [
            ["com.apple.iconservices.store", "cache.bin"],
            ["Google", "Chrome", "Default", "Cache", "f_000001"],
            ["other.cache", "file.bin"],
        ]
        let without = PolicyEvaluator(cacheOwners: GeneralMacCacheOwnerCatalog(version: "none", entries: [:]))
        for components in samples {
            let finding = try PolicyPlanFixtureFactory.finding(components: components)
            if PolicyEvaluator().evaluate(finding).eligibility == .eligible {
                #expect(without.evaluate(finding).eligibility == .eligible, "widened: \(components)")
            }
        }
        // Even an entry for the one named eligible cache can only narrow it.
        let hostile = PolicyEvaluator(cacheOwners: GeneralMacCacheOwnerCatalog(
            version: "hostile",
            entries: [["com.apple.iconservices.store"]: .mayAffectWorkflow]
        ))
        let narrowed = hostile.evaluate(
            try PolicyPlanFixtureFactory.finding(components: ["com.apple.iconservices.store", "cache.bin"])
        )
        #expect(narrowed.eligibility == .ineligible)
        #expect(narrowed.candidate == nil)
    }

    @Test
    func recoveryConfidenceAndWorkflowPrecedeLargerBytes() throws {
        let rebuild = try rankingCandidate(name: "rebuild", recovery: .rebuild, bytes: 1)
        let huge = try rankingCandidate(name: "huge", recovery: .redownload, bytes: 1_000_000)
        #expect(ConservativeRank.ordered([huge, rebuild]) == [rebuild, huge])
    }
}

/// One expected label per known `~/Library/Caches` owner (B1). None may be eligible.
fileprivate struct CacheOwnerGolden: Sendable, CustomTestStringConvertible {
    let components: [String]
    let disposition: PolicyDisposition
    let owner: PolicySemanticOwner
    let recovery: PolicyRecoveryPath
    let rule: PolicyRuleReference

    var testDescription: String { components.joined(separator: "/") }

    static func review(_ components: [String], _ disposition: PolicyDisposition) -> Self {
        .init(
            components: components,
            disposition: disposition,
            owner: .generalRebuildableCache,
            recovery: disposition == .redownloadRequired ? .redownloadRequired : .inspectBeforeAction,
            rule: .generalCacheOwnerReviewV1
        )
    }

    static let all: [Self] = [
        .review(["pip", "http-v2", "entry.body"], .redownloadRequired),
        .review(["Homebrew", "downloads", "bottle.tar.gz"], .redownloadRequired),
        .review(["homebrew", "downloads", "bottle.tar.gz"], .redownloadRequired),
        .review(["uv", "wheels-v5", "entry.whl"], .redownloadRequired),
        .review(["pypoetry", "artifacts", "entry.whl"], .redownloadRequired),
        .review(["go-build", "ab", "entry-d"], .mayAffectWorkflow),
        .review(["org.swift.swiftpm", "repositories", "entry.pack"], .mayAffectWorkflow),
        .review(["JetBrains", "IntelliJIdea2026.2", "index.bin"], .mayAffectWorkflow),
        .review(["com.apple.e5rt.e5bundlecache", "bundle", "model.bin"], .mayAffectWorkflow),
        .init(
            components: ["pypoetry", "virtualenvs", "project-py3.12", "pyvenv.cfg"],
            disposition: .keepProtected,
            owner: .developerToolState,
            recovery: .protectedNoOperation,
            rule: .protectedOwnerV1
        ),
    ]
}

private func rankingCandidate(name: String, recovery: RecoveryCost, bytes: Int64) throws -> EligibleCandidate {
    let finding = try PolicyPlanFixtureFactory.finding(components: ["ranking", name], bytes: bytes)
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
            confidence: .observed,
            workflowImpact: .none,
            conservativeBytes: bytes
        )
    )
}
