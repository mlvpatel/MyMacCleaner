import Testing

@testable import CleanerCore

@Suite("Adaptive Experience Projection")
struct AdaptiveExperienceProjectionTests {
    @Test
    func guidedStandardAndTechnicalDifferOnlyInExplanationFields() throws {
        let source = try fixtureSource()
        let projector = AdaptiveExperienceProjector()
        let guided = try projector.project(source, mode: .guided)
        let standard = try projector.project(source, mode: .standard)
        let technical = try projector.project(source, mode: .technical)

        #expect(guided.authority == standard.authority)
        #expect(guided.authority == technical.authority)
        #expect(guided.explanationKeys != standard.explanationKeys)
        #expect(standard.explanationKeys != technical.explanationKeys)
        #expect(guided.disclosureDepth == .guided)
        #expect(standard.disclosureDepth == .standard)
        #expect(technical.disclosureDepth == .technical)
        #expect(guided.groupingKeys != technical.groupingKeys)
        #expect(guided.detailRowKeys != technical.detailRowKeys)
    }

    @Test
    func everyMappedAuthorityFieldAppearsOnceAndIsModeInvariant() throws {
        let source = try fixtureSource()
        let projection = try AdaptiveExperienceProjector().project(source, mode: .standard)
        let authority = projection.authority

        #expect(authority.scanState == .complete)
        #expect(authority.evidenceIdentities.count == 1)
        #expect(Set(authority.evidenceIdentities).count == 1)
        #expect(authority.boundarySummaries.count == 1)
        #expect(authority.dispositions.count == 1)
        #expect(authority.eligibilities == [.eligible])
        #expect(authority.semanticOwners == [.generalRebuildableCache])
        #expect(authority.rationales.count == 1)
        #expect(authority.recoveryPaths.count == 1)
        #expect(authority.confidences.count == 1)
        #expect(authority.expectedConservativeBytes == .observed(4_096))
        #expect(authority.planDigestHex != nil)
        #expect(authority.planExpiresAtNanoseconds != nil)
        #expect(authority.approvalValidity == .validForReview)
        #expect(authority.executionState == .complete)
        #expect(authority.executionOutcomes == [.moved])
        #expect(authority.receiptIDs.count == 1)
        #expect(authority.receiptStatusMarkers.count == 1)
        #expect(authority.receiptRecoveryMarkers.count == 1)
        #expect(authority.memoryOutcome == .unavailable)
        #expect(!authority.memoryUnavailable.isEmpty)
        #expect(authority.capabilityAuthorities.count == 4)
        #expect(authority.capabilityOperations.count == 4)
        #expect(authority.permissionGaps == [.fullDiskAccess])
        #expect(authority.cardKinds.contains(.generalMac))
        #expect(authority.cardKinds.contains(.memory))
        #expect(authority.cardKinds.contains(.permission))
        #expect(authority.cardKinds.contains(.history))
        #expect(!authority.cardKinds.contains(.developerCapability))
    }

    @Test(arguments: explicitScanStates)
    fileprivate func explicitScanStatesNeverBecomeCompleteOrZero(_ state: ProjectedScanState) throws {
        let source = try fixtureSource(scanState: state, findings: [], evaluations: [], includePlan: false)
        let projection = try AdaptiveExperienceProjector().project(source, mode: .guided)
        #expect(projection.authority.scanState == state)
    }

    @Test
    func unavailableBytesStayUnavailableAndDoNotBecomeZero() throws {
        let incomplete = try PolicyPlanFixtureFactory.finding(
            components: ["com.apple.iconservices.store", "gap.bin"],
            complete: false
        )
        let evaluation = PolicyEvaluator().evaluate(incomplete)
        let source = try fixtureSource(
            findings: [ProjectedFinding(incomplete.finding)],
            evaluations: [evaluation],
            includePlan: false,
            approvalValidity: .invalid(.missingApproval)
        )
        let projection = try AdaptiveExperienceProjector().project(source, mode: .technical)
        #expect(evaluation.eligibility == .ineligible)
        #expect(projection.authority.expectedConservativeBytes == .unavailable)
    }

    @Test
    func cardMembershipIgnoresPersonaAndUsesDeliveredFamiliesOnly() throws {
        let source = try fixtureSource(developerInventory: [])
        let guided = try AdaptiveExperienceProjector().project(source, mode: .guided)
        let technical = try AdaptiveExperienceProjector().project(source, mode: .technical)
        #expect(guided.authority.cardKinds == technical.authority.cardKinds)
        #expect(guided.authority.cardKinds.contains(.generalMac))
        #expect(!guided.authority.cardKinds.contains(.developerCapability))
    }

    @Test
    func duplicateIdentitiesAreRejected() throws {
        let finding = try PolicyPlanFixtureFactory.finding(
            components: ["com.apple.iconservices.store", "dup.bin"]
        )
        let projected = ProjectedFinding(finding.finding)
        let source = try fixtureSource(findings: [projected, projected], includePlan: false)
        #expect(throws: AdaptiveExperienceProjectionError.duplicateEvidenceIdentity) {
            try AdaptiveExperienceProjector().project(source, mode: .standard)
        }
    }

    @Test
    func identitiesAreStableSortedAndOverflowFailsClosed() throws {
        let first = try PolicyPlanFixtureFactory.finding(
            components: ["com.apple.iconservices.store", "z.bin"],
            bytes: Int64.max / 2 + 8,
            node: 11
        )
        let second = try PolicyPlanFixtureFactory.finding(
            components: ["com.apple.iconservices.store", "a.bin"],
            bytes: Int64.max / 2 + 8,
            node: 12
        )
        let evaluations = [PolicyEvaluator().evaluate(first), PolicyEvaluator().evaluate(second)]
        let source = try fixtureSource(
            findings: [ProjectedFinding(first.finding), ProjectedFinding(second.finding)],
            evaluations: evaluations,
            includePlan: false,
            approvalValidity: .invalid(.missingApproval)
        )
        let identities = try AdaptiveExperienceIdentity.uniqueSorted(from: source.findings)
        #expect(identities == identities.sorted())
        #expect(throws: AdaptiveExperienceProjectionError.overflowingByteTotal) {
            try AdaptiveExperienceProjector().project(source, mode: .guided)
        }
    }

    @Test
    func developerInventoryFactIsProtectedAndDoesNotChangeEligibility() throws {
        let fact = try AdaptiveDeveloperInventoryFact(
            opaqueID: "dev-cursor",
            presenceKey: "adaptive.developer.present",
            protectionKey: "adaptive.developer.protected"
        )
        let source = try fixtureSource(developerInventory: [fact])
        let projection = try AdaptiveExperienceProjector().project(source, mode: .standard)
        #expect(projection.authority.cardKinds.contains(.developerCapability))
        #expect(projection.authority.eligibilities == source.evaluations.map(\.eligibility))
    }

    @Test
    func scanSessionCollectsTerminalCompleteWithoutDetectorChoiceFromCaller() async throws {
        let catalog = GeneralMacScopeCatalog.current
        let root = try catalog.declaredRoot(for: .userLibraryCaches)
        let fileSystem = ScriptedFileSystem(steps: [.terminal(.complete)], rootID: root.id)
        let session = try AdaptiveScanSession(
            fileSystem: fileSystem,
            clock: AdaptiveTestClock(),
            cancellation: AdaptiveNeverCancel()
        )
        let collected = await session.collect(request: try catalog.scanRequest(for: [.userLibraryCaches]))
        #expect(collected.scanState == .complete)
        #expect(collected.findings.isEmpty)
        #expect(collected.evaluations.isEmpty)
    }
}

private let explicitScanStates: [ProjectedScanState] = {
    let rootID = GeneralMacScopeCatalog.current.registrations[0].id
    let declared = DeclaredRootID.uncheckedForTest(rootID.value)
    return [
        .continuing,
        .partial(issues: [
            .init(ScanIssue(
                rootID: declared,
                detectorID: GeneralMacScopeCatalog.current.detectorID,
                cause: .permissionDenied
            ))
        ]),
        .permissionDenied,
        .cancelled,
        .corruptMetadata,
        .unsupportedLayout
    ]
}()

private func fixtureSource(
    scanState: ProjectedScanState = .complete,
    findings: [ProjectedFinding]? = nil,
    evaluations: [PolicyEvaluation]? = nil,
    includePlan: Bool = true,
    approvalValidity: ApprovalValidity? = nil,
    developerInventory: [AdaptiveDeveloperInventoryFact] = []
) throws -> AdaptiveExperienceSource {
    let candidate = try PolicyPlanFixtureFactory.eligibleCache(component: "card.bin", bytes: 4_096, node: 9)
    let finding = candidate.evidence.finding
    let evaluation = PolicyEvaluator().evaluate(finding)
    let plan: ReviewPlan?
    if includePlan {
        plan = try PolicyPlanFixtureFactory.reviewPlan(candidates: [candidate])
    } else {
        plan = nil
    }
    let validity: ApprovalValidity
    if let approvalValidity {
        validity = approvalValidity
    } else if let plan {
        validity = ApprovalValidity.evaluate(
            approval: PolicyPlanFixtureFactory.matchingApproval(plan),
            plan: plan,
            current: PolicyPlanFixtureFactory.matchingContext(plan)
        )
    } else {
        validity = .invalid(.missingApproval)
    }
    let receipt = RedactedReceiptSummary.make(
        from: ReceiptHistorySummary(
            id: try ReceiptID("receipt-opaque"),
            createdAt: .init(unixNanoseconds: 1),
            aggregate: .complete,
            isQuarantined: false,
            itemCount: 1,
            canRevealMovedItem: true
        )
    )
    let memory = MemoryCoachSnapshot(
        sessionID: .init(1),
        samplingBudget: .standard,
        startedAt: .unavailable(.unavailable),
        completedAt: .unavailable(.unavailable),
        pressure: .unavailableNoFreshEvent,
        physicalMemory: .unavailable(.unavailable),
        vm: .unavailable(.unavailable),
        swap: .unavailable(.unavailable),
        issues: [.timing(.stale)],
        outcome: .unavailable
    )
    let capabilities = CapabilityCardProjection().cards(for: [evaluation])
    return AdaptiveExperienceSource(
        scanState: scanState,
        findings: findings ?? [ProjectedFinding(finding.finding)],
        evaluations: evaluations ?? [evaluation],
        reviewPlan: plan,
        approvalValidity: validity,
        executionState: .complete,
        executionOutcomes: [.moved],
        receipts: [receipt],
        memory: memory,
        capabilities: capabilities,
        permissionGaps: [.fullDiskAccess],
        developerInventory: developerInventory
    )
}

private struct AdaptiveTestClock: AdaptiveClocking {
    func now() async -> ClockReading {
        PolicyPlanFixtureFactory.clockReading()
    }
}

private struct AdaptiveNeverCancel: AdaptiveCancelling {
    func isCancellationRequested() async -> Bool { false }
}

private extension DeclaredRootID {
    static func uncheckedForTest(_ value: String) -> DeclaredRootID {
        (try? DeclaredRootID(value)) ?? DeclaredRootID.placeholder
    }

    static var placeholder: DeclaredRootID {
        try! DeclaredRootID("user-library-caches")
    }
}
