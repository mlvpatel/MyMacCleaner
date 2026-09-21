import Foundation
import Testing
@testable import CleanerCore

@Suite("Duplicate Triage")
struct DuplicateTriageTests {
    @Test
    func hardLinkedMembersCollapseBeforeAnyContentEvidence() async throws {
        let port = RecordingContentEvidencePort(outcomes: [])
        let first = try fixture(components: ["a.bin"], resource: .init(device: 1, node: 9))
        let second = try fixture(components: ["b.bin"], resource: .init(device: 1, node: 9))

        let result = await DuplicateTriage(contentEvidence: port).evaluate([second, first])

        #expect(result.groups.isEmpty)
        #expect(await port.requests().isEmpty)
    }

    @Test
    func sameSizedDistinctResourcesRequireEqualCompleteOpaqueEvidence() async throws {
        let first = try fixture(components: ["a.bin"], resource: .init(device: 1, node: 1))
        let second = try fixture(components: ["b.bin"], resource: .init(device: 1, node: 2))
        let third = try fixture(components: ["c.bin"], resource: .init(device: 1, node: 3))
        let digestA = try digest(1)
        let digestB = try digest(2)
        let port = RecordingContentEvidencePort(outcomes: [
            (first.finding.locator, .complete(digestA)),
            (second.finding.locator, .complete(digestA)),
            (third.finding.locator, .complete(digestB)),
        ])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([third, second, first])

        #expect(result.groups.count == 1)
        #expect(result.groups[0].resources.count == 2)
        #expect(result.groups[0].resources.map(\.members.first!.locator.components) == [["a.bin"], ["b.bin"]])
        #expect(result.groups[0].cloneShareUncertainty == .unknown)
        #expect(result.groups[0].resources[0].space.logicalBytes == .observed(10_000))
        #expect(result.groups[0].resources[0].space.allocatedBytes == .observed(4_096))
        #expect(result.groups[0].resources[0].space.sharedBytes == .unknown)
        #expect(result.groups[0].resources[0].space.conservativeReclaimableBytes == .unknown)
        #expect((await port.requests()).map(\.locator.components) == [["a.bin"], ["b.bin"], ["c.bin"]])
        #expect((await port.requests()).map(\.expectedLogicalBytes) == [10_000, 10_000, 10_000])
    }

    @Test
    func emptyRegularFilesCanFormAGroupFromFullDigestEvidence() async throws {
        let first = try fixture(
            components: ["empty", "a.bin"],
            resource: .init(device: 1, node: 1),
            logicalBytes: 0,
            allocatedBytes: 0
        )
        let second = try fixture(
            components: ["empty", "b.bin"],
            resource: .init(device: 1, node: 2),
            logicalBytes: 0,
            allocatedBytes: 0
        )
        let emptyDigest = try digest(0)
        let port = RecordingContentEvidencePort(outcomes: [
            (first.finding.locator, .complete(emptyDigest)),
            (second.finding.locator, .complete(emptyDigest)),
        ])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([second, first])

        #expect(result.groups.count == 1)
        #expect(result.groups[0].resources.count == 2)
        #expect((await port.requests()).allSatisfy { $0.expectedLogicalBytes == 0 })
    }

    @Test
    func diagnosticReportsUseTheCatalogCrashCategoryWithoutBypassingScopeChecks() async throws {
        let first = try fixture(
            source: .userLibraryLogs,
            components: ["DiagnosticReports", "a.crash"],
            resource: .init(device: 1, node: 1)
        )
        let second = try fixture(
            source: .userLibraryLogs,
            components: ["DiagnosticReports", "b.crash"],
            resource: .init(device: 1, node: 2)
        )
        let port = RecordingContentEvidencePort(outcomes: [
            (first.finding.locator, .complete(try digest(3))),
            (second.finding.locator, .complete(try digest(3))),
        ])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([second, first])

        #expect(first.category == .crashReport)
        #expect(result.groups.count == 1)
        #expect((await port.requests()).count == 2)
    }

    @Test(arguments: [
        ContentEvidenceOutcome.denied,
        .partial,
        .corrupt,
        .budgetExceeded,
    ])
    func incompleteContentEvidenceNeverFormsAGroup(_ outcome: ContentEvidenceOutcome) async throws {
        let first = try fixture(components: ["a.bin"], resource: .init(device: 1, node: 1))
        let second = try fixture(components: ["b.bin"], resource: .init(device: 1, node: 2))
        let port = RecordingContentEvidencePort(outcomes: [
            (first.finding.locator, .complete(try digest(1))),
            (second.finding.locator, outcome),
        ])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([first, second])

        #expect(result.groups.isEmpty)
        #expect(result.unresolved.count == 1)
        #expect(result.unresolved[0].cause == .contentEvidenceUnavailable(outcome.code))
    }

    @Test
    func cancellationStopsFurtherContentRequestsAtTheRecordedPoint() async throws {
        let first = try fixture(components: ["a.bin"], resource: .init(device: 1, node: 1))
        let second = try fixture(components: ["b.bin"], resource: .init(device: 1, node: 2))
        let third = try fixture(components: ["c.bin"], resource: .init(device: 1, node: 3))
        let port = RecordingContentEvidencePort(outcomes: [
            (first.finding.locator, .cancelled),
            (second.finding.locator, .complete(try digest(1))),
            (third.finding.locator, .complete(try digest(1))),
        ])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([third, second, first])

        #expect(result.groups.isEmpty)
        #expect((await port.requests()).map(\.locator.components) == [["a.bin"]])
        #expect(result.unresolved == [.init(
            members: result.unresolved[0].members,
            cause: .contentEvidenceUnavailable(.cancelled)
        )])
    }

    @Test
    func cancellationStopsBeforeLaterSameSizePartitions() async throws {
        let cancelled = try fixture(
            components: ["first", "a.bin"],
            resource: .init(device: 1, node: 1),
            logicalBytes: 2
        )
        let paired = try fixture(
            components: ["first", "b.bin"],
            resource: .init(device: 1, node: 2),
            logicalBytes: 2
        )
        let later = try fixture(
            components: ["later", "a.bin"],
            resource: .init(device: 2, node: 1),
            logicalBytes: 1
        )
        let laterPair = try fixture(
            components: ["later", "b.bin"],
            resource: .init(device: 2, node: 2),
            logicalBytes: 1
        )
        let port = RecordingContentEvidencePort(outcomes: [(cancelled.finding.locator, .cancelled)])

        _ = await DuplicateTriage(contentEvidence: port).evaluate([later, paired, laterPair, cancelled])

        #expect((await port.requests()).map(\.locator.components) == [["first", "a.bin"]])
    }

    @Test
    func validatesFiniteContentLimitsAndRequestRootContainment() throws {
        #expect(throws: ContentDigestError.invalidDigestLength) {
            try ContentDigest(opaqueBytes: [1])
        }
        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentReadLimits(
                maximumCandidatesPerScan: 4_097,
                maximumChunkBytes: 1_048_576,
                maximumBytesPerFile: 17_179_869_184,
                maximumBytesPerScan: 68_719_476_736
            )
        }
        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentReadLimits(
                maximumCandidatesPerScan: 4_096,
                maximumChunkBytes: 0,
                maximumBytesPerFile: 17_179_869_184,
                maximumBytesPerScan: 68_719_476_736
            )
        }

        let first = try fixture(components: ["a.bin"], resource: .init(device: 1, node: 1))
        let wrongRoot = try DeclaredRootID("wrong-root")
        #expect(throws: EvidenceValidationError.mismatchedRootIdentity) {
            try ContentEvidenceRequest(
                declaredRootID: wrongRoot,
                locator: first.finding.locator,
                resource: .init(volume: try VolumeID("fixture-volume"), identity: .init(device: 1, node: 1)),
                expectedLogicalBytes: 1,
                limits: .current
            )
        }
        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentEvidenceRequest(
                declaredRootID: first.finding.declaredRoot.id,
                locator: first.finding.locator,
                resource: .init(volume: try VolumeID("fixture-volume"), identity: .init(device: 1, node: 1)),
                expectedLogicalBytes: ContentReadLimits.current.maximumBytesPerFile + 1,
                limits: .current
            )
        }
    }

    @Test
    func incompleteInputIsTypedAndDoesNotReachContentPort() async throws {
        let incomplete = try fixture(
            components: ["incomplete.bin"],
            resource: .init(device: 1, node: 1),
            completeness: .incomplete(reason: .unreadable)
        )
        let port = RecordingContentEvidencePort(outcomes: [])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([incomplete])

        #expect(result.groups.isEmpty)
        #expect(result.unresolved.map(\.cause) == [DuplicateTriageUnresolvedCause.incompleteEvidence])
        #expect(await port.requests().isEmpty)
    }

    @Test
    func candidateLimitAppliesAcrossEverySameSizePartition() async throws {
        let firstPartition = try (0 ..< 4_096).map { index in
            try fixture(
                components: ["large", "\(index).bin"],
                resource: .init(device: 1, node: UInt64(index)),
                logicalBytes: 2_048
            )
        }
        let laterPartition = [
            try fixture(components: ["later", "a.bin"], resource: .init(device: 2, node: 1), logicalBytes: 1_024),
            try fixture(components: ["later", "b.bin"], resource: .init(device: 2, node: 2), logicalBytes: 1_024),
        ]
        let port = RecordingContentEvidencePort(outcomes: [])

        let result = await DuplicateTriage(contentEvidence: port).evaluate(firstPartition + laterPartition)

        #expect((await port.requests()).map(\.locator.components) == [["large", "0.bin"]])
        #expect(result.unresolved.contains { $0.cause == .candidateLimitExceeded })
    }

    @Test
    func aggregateContentBudgetStopsLaterPartitionsBeforeThePort() async throws {
        let maximumFileBytes = ContentReadLimits.current.maximumBytesPerFile
        let firstPartition = try (0 ..< 4).map { index in
            try fixture(
                components: ["maximum", "\(index).bin"],
                resource: .init(device: 1, node: UInt64(index)),
                logicalBytes: maximumFileBytes
            )
        }
        let laterPartition = [
            try fixture(components: ["later", "a.bin"], resource: .init(device: 2, node: 1), logicalBytes: 1),
            try fixture(components: ["later", "b.bin"], resource: .init(device: 2, node: 2), logicalBytes: 1),
        ]
        let port = RecordingContentEvidencePort(outcomes: [])

        let result = await DuplicateTriage(contentEvidence: port).evaluate(firstPartition + laterPartition)

        #expect((await port.requests()).map(\.locator.components) == [["maximum", "0.bin"]])
        #expect(result.unresolved.contains {
            $0.cause == .contentEvidenceUnavailable(.budgetExceeded)
                && $0.members.map(\.locator.components) == [["later", "a.bin"], ["later", "b.bin"]]
        })
    }

    @Test
    func overflowingLogicalEvidenceNeverReachesThePort() async throws {
        let entries = [
            try fixture(components: ["overflow", "a.bin"], resource: .init(device: 1, node: 1), logicalBytes: .max),
            try fixture(components: ["overflow", "b.bin"], resource: .init(device: 1, node: 2), logicalBytes: .max),
        ]
        let port = RecordingContentEvidencePort(outcomes: [])

        let result = await DuplicateTriage(contentEvidence: port).evaluate(entries)

        #expect(await port.requests().isEmpty)
        #expect(result.unresolved.map(\.cause) == [.contentEvidenceUnavailable(.budgetExceeded)])
    }

    @Test
    func conflictingSameResourceMeasurementsRemainUnresolved() async throws {
        let first = try fixture(
            components: ["links", "a.bin"],
            resource: .init(device: 1, node: 1),
            logicalBytes: 1_024,
            allocatedBytes: 1_024
        )
        let conflicting = try fixture(
            components: ["links", "b.bin"],
            resource: .init(device: 1, node: 1),
            logicalBytes: 1_024,
            allocatedBytes: 2_048
        )
        let port = RecordingContentEvidencePort(outcomes: [])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([first, conflicting])

        #expect(result.groups.isEmpty)
        #expect(await port.requests().isEmpty)
        #expect(result.unresolved.map(\.cause) == [.conflictingResourceEvidence])
    }

    @Test
    func forgedNegativeOrMismatchedSpaceEvidenceDoesNotReachThePort() async throws {
        let negative = try fixture(
            components: ["forged", "negative.bin"],
            resource: .init(device: 1, node: 1),
            spaceLogicalBytes: .observed(-1)
        )
        let mismatched = try fixture(
            components: ["forged", "mismatched.bin"],
            resource: .init(device: 1, node: 2),
            spaceAllocatedBytes: .observed(9_999)
        )
        let port = RecordingContentEvidencePort(outcomes: [])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([negative, mismatched])

        #expect(await port.requests().isEmpty)
        #expect(result.unresolved.map(\.cause) == [.conflictingResourceEvidence, .conflictingResourceEvidence])
    }

    @Test
    func forgedScopeIdentityRootCategoryAndBoundaryEvidenceNeverReachThePort() async throws {
        let forgedDetector = try fixture(
            components: ["forged", "detector.bin"],
            resource: .init(device: 1, node: 1),
            detectorID: try DetectorID("forged.detector")
        )
        let forgedRoot = try fixture(
            components: ["forged", "root.bin"],
            resource: .init(device: 1, node: 2),
            declaredRootID: try DeclaredRootID("forged-root")
        )
        let forgedVersion = try fixture(
            components: ["forged", "version.bin"],
            resource: .init(device: 1, node: 5),
            detectorVersion: try DetectorVersion("9.9.9")
        )
        let forgedCategory = try fixture(
            components: ["forged", "category.bin"],
            resource: .init(device: 1, node: 3),
            category: .duplicate
        )
        let unsafeBoundary = try fixture(
            components: ["forged", "boundary.bin"],
            resource: .init(device: 1, node: 4),
            boundaries: .init(symlink: .unknown)
        )
        let port = RecordingContentEvidencePort(outcomes: [])

        let result = await DuplicateTriage(contentEvidence: port).evaluate([
            forgedDetector,
            forgedRoot,
            forgedVersion,
            forgedCategory,
            unsafeBoundary,
        ])

        #expect(await port.requests().isEmpty)
        #expect(result.groups.isEmpty)
        #expect(result.unresolved.map(\.cause) == Array(
            repeating: .untrustedScopeEvidence,
            count: 5
        ))
    }

    @Test
    func duplicateProductionValuesExposeNoOperationOrScalarReclaimVocabulary() throws {
        let cleanerCoreRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: cleanerCoreRoot.appendingPathComponent(
            "Sources/CleanerCore/Detectors/GeneralMac/DuplicateTriage.swift"
        )).lowercased()

        for forbiddenTerm in ["survivor", "selected", "delete", "operation", "totalreclaim", "wastedspace"] {
            #expect(!source.contains(forbiddenTerm))
        }
    }

    private func fixture(
        source: GeneralMacRootKind = .userDownloads,
        components: [String],
        resource: FileIdentityEvidence,
        completeness: GeneralMacEvidenceCompleteness = .complete,
        logicalBytes: Int64 = 10_000,
        allocatedBytes: Int64 = 4_096,
        spaceLogicalBytes: EvidenceValue<Int64>? = nil,
        spaceAllocatedBytes: EvidenceValue<Int64>? = nil,
        detectorID: DetectorID? = nil,
        detectorVersion: DetectorVersion? = nil,
        declaredRootID: DeclaredRootID? = nil,
        category: GeneralMacCategory? = nil,
        boundaries: BoundaryEvidence? = nil
    ) throws -> GeneralMacFinding {
        let catalog = GeneralMacScopeCatalog.current
        let registration = try catalog.registration(for: source)
        let registeredRoot = try catalog.declaredRoot(for: source)
        let rootID = declaredRootID ?? registeredRoot.id
        let observation = try FileObservation(
            rootID: rootID,
            locator: .init(rootID: rootID, components: components),
            resourceIdentity: .observed(resource),
            sizes: .init(logicalBytes: .observed(logicalBytes), allocatedBytes: .observed(allocatedBytes)),
            modification: .observed(.init(unixNanoseconds: 1)),
            fileKind: .regularFile,
            volume: .observed(try VolumeID("fixture-volume")),
            boundaries: boundaries ?? .init(
                symlink: .observed(false), alias: .observed(false), package: .observed(false),
                mount: .observed(false), protectedRoot: .observed(false), homeBoundary: .observed(false),
                externalVolume: .observed(false)
            )
        )
        let finding = try Finding(
            detectorID: detectorID ?? catalog.detectorID,
            detectorVersion: detectorVersion ?? catalog.version,
            provenance: .filesystemObservation,
            observation: observation,
            declaredRoot: .init(id: rootID),
            observationInstant: .init(monotonicNanoseconds: 1)
        )
        return .init(
            finding: finding,
            category: category ?? (source == .userLibraryLogs && components.first == "DiagnosticReports"
                ? .crashReport
                : registration.category),
            source: source,
            age: .unavailable,
            space: .init(
                logicalBytes: spaceLogicalBytes ?? .observed(logicalBytes),
                allocatedBytes: spaceAllocatedBytes ?? .observed(allocatedBytes)
            ),
            rebuildImpact: .reviewRequired,
            confidence: .observed,
            conservativeRisk: .unknown,
            completeness: completeness
        )
    }

    private func digest(_ byte: UInt8) throws -> ContentDigest {
        try .init(opaqueBytes: Array(repeating: byte, count: 32))
    }
}

private actor RecordingContentEvidencePort: ContentEvidencePort {
    private let outcomes: [(RelativeLocator, ContentEvidenceOutcome)]
    private var recordedRequests: [ContentEvidenceRequest] = []

    init(outcomes: [(RelativeLocator, ContentEvidenceOutcome)]) {
        self.outcomes = outcomes
    }

    func beginSession(limits: ContentReadLimits) async -> any ContentEvidenceSession {
        _ = limits
        return RecordingContentEvidenceSession(owner: self)
    }

    fileprivate func record(_ request: ContentEvidenceRequest) -> ContentEvidenceOutcome {
        recordedRequests.append(request)
        return outcomes.first(where: { $0.0 == request.locator })?.1 ?? .denied
    }

    func requests() -> [ContentEvidenceRequest] { recordedRequests }
}

private struct RecordingContentEvidenceSession: ContentEvidenceSession {
    let owner: RecordingContentEvidencePort

    func contentEvidence(for request: ContentEvidenceRequest) async -> ContentEvidenceOutcome {
        await owner.record(request)
    }
}
