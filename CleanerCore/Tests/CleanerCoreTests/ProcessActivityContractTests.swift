import Testing

@testable import CleanerCore

/// C5: correlating a file with a running process that holds it open may only
/// mark it in-use (ineligible) — it must never make anything eligible.
@Suite("Process-correlated activity")
struct ProcessActivityContractTests {
    @Test
    func openFileForcesIneligibleWhileClosedFileKeepsItsEligibility() throws {
        let finding = try PolicyPlanFixtureFactory.finding(
            components: ["com.apple.iconservices.store", "regular.bin"],
            node: 970
        )
        let closed = PolicyEvaluator().evaluate(finding, processActive: false)
        let open = PolicyEvaluator().evaluate(finding, processActive: true)

        // The unobserved file is a normal eligible cache; holding it open forces
        // it in-use and ineligible — strictly narrowing.
        #expect(closed.eligibility == .eligible)
        #expect(open.eligibility == .ineligible)
        #expect(open.candidate == nil)
    }

    @Test
    func defaultIsNoProcessActivityAndChangesNothing() throws {
        let finding = try PolicyPlanFixtureFactory.finding(
            components: ["com.apple.iconservices.store", "regular.bin"],
            node: 971
        )
        #expect(PolicyEvaluator().evaluate(finding).eligibility
            == PolicyEvaluator().evaluate(finding, processActive: false).eligibility)
        #expect(NoProcessActivity().isFileOpen(rootID: finding.finding.locator.rootID, components: ["x"]) == false)
    }
}
