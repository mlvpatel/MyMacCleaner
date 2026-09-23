import Testing

@testable import CleanerCore

/// C4: credential-named locators must never become a cleanup candidate — not
/// even when their category (e.g. an eligible cache) otherwise would.
@Suite("Credential owner contract")
struct PolicyCredentialContractTests {
    private static let credentialNames = [
        "mcp.json", ".claude.json", "auth.json", ".env", ".env.local", "credentials", "credentials.json"
    ]

    @Test
    func credentialNamedLocatorsAreProtectedAndNeverCandidates() throws {
        for (index, name) in Self.credentialNames.enumerated() {
            // A would-be-eligible cache locator whose leaf is a credential name.
            let finding = try PolicyPlanFixtureFactory.finding(
                components: ["com.apple.iconservices.store", name],
                node: UInt64(900 + index)
            )
            let evaluation = PolicyEvaluator().evaluate(finding)
            #expect(evaluation.semanticOwner == .credential, "\(name) should be credential-owned")
            #expect(evaluation.eligibility == .ineligible, "\(name) must be ineligible")
            #expect(evaluation.candidate == nil, "\(name) must not produce a candidate")
        }
    }

    @Test
    func nonCredentialCacheStaysEligible() throws {
        let candidate = try PolicyPlanFixtureFactory.eligibleCache(
            component: "regular.bin", bytes: 4_096, node: 950
        )
        let evaluation = PolicyEvaluator().evaluate(candidate.evidence.finding)
        #expect(evaluation.semanticOwner == .generalRebuildableCache)
        #expect(evaluation.eligibility == .eligible)
    }

    @Test
    func credentialMatchIsCaseInsensitiveAndAnchoredToTheLeaf() {
        #expect(PolicyEvaluator.isCredentialLocator(["Application Support", ".ENV"]))
        #expect(PolicyEvaluator.isCredentialLocator(["x", "Credentials.json"]))
        #expect(PolicyEvaluator.isCredentialLocator(["x", ".env.local"]))
        #expect(!PolicyEvaluator.isCredentialLocator(["x", "environment.txt"]))
        #expect(!PolicyEvaluator.isCredentialLocator([]))
    }
}
