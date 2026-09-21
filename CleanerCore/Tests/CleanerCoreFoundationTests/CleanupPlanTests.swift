import CryptoKit
import Foundation
import Testing

@testable import CleanerCore
@testable import CleanerCoreFoundation

@Suite("Cleanup review plan canonicalization")
struct CleanupPlanTests {
    @Test
    func sameSelectedSetBuildsSameCanonicalBytesDigestAndFifteenMinuteExpiry() throws {
        let first = try cleanupCandidate(component: "b.bin", bytes: 4_096)
        let second = try cleanupCandidate(component: "a.bin", bytes: 8_192)
        let context = try reviewPlanContext()
        let session = try ReviewPlanLaunchSession("launch-a")
        let created = WallClockInstant(unixNanoseconds: 1_000_000_000)
        let digesting = RecordingPlanDigesting()

        let left = try ReviewPlan.build(
            draft: .init(
                selectedCandidates: [first, second],
                versionContext: context,
                launchSession: session,
                createdAt: created
            ),
            digesting: digesting
        )
        let right = try ReviewPlan.build(
            draft: .init(
                selectedCandidates: [second, first],
                versionContext: context,
                launchSession: session,
                createdAt: created
            ),
            digesting: digesting
        )

        #expect(left.expiresAt == WallClockInstant(unixNanoseconds: 901_000_000_000))
        #expect(left.targets.map(\.stableIdentity.utf8Bytes) == right.targets.map(\.stableIdentity.utf8Bytes))
        #expect(left.canonicalBytes == right.canonicalBytes)
        #expect(left.digest == right.digest)
        #expect(digesting.inputs == [left.canonicalBytes, right.canonicalBytes])
        #expect(Array(left.canonicalBytes.prefix(7)) == Array("MMCPLAN".utf8))
    }

    @Test
    func everyAuthorizationFieldChangeChangesCanonicalBytes() throws {
        let candidate = try cleanupCandidate(component: "field.bin", bytes: 4_096)
        let context = try reviewPlanContext()
        let session = try ReviewPlanLaunchSession("launch-a")
        let base = try ReviewPlanDraft(
            selectedCandidates: [candidate],
            versionContext: context,
            launchSession: session,
            createdAt: .init(unixNanoseconds: 1_000_000_000)
        )
        let baseBytes = try CanonicalPlanEncoder().encode(base)

        let changedSession = try ReviewPlanDraft(
            selectedCandidates: [candidate],
            versionContext: context,
            launchSession: .init("launch-b"),
            createdAt: base.createdAt
        )
        let changedContext = try ReviewPlanDraft(
            selectedCandidates: [candidate],
            versionContext: .init(
                appPlanVersion: "5.0.1",
                policyVersion: context.policyVersion,
                detectorCatalogVersion: context.detectorCatalogVersion,
                encodingVersion: context.encodingVersion
            ),
            launchSession: session,
            createdAt: base.createdAt
        )
        let changedSelection = try ReviewPlanDraft(
            selectedCandidates: [try cleanupCandidate(component: "other.bin", bytes: 4_096)],
            versionContext: context,
            launchSession: session,
            createdAt: base.createdAt
        )

        #expect(try CanonicalPlanEncoder().encode(changedSession) != baseBytes)
        #expect(try CanonicalPlanEncoder().encode(changedContext) != baseBytes)
        #expect(try CanonicalPlanEncoder().encode(changedSelection) != baseBytes)
    }

    @Test
    func invalidSelectionsDigestLengthAndExpiryFailClosed() throws {
        let candidate = try cleanupCandidate(component: "dup.bin", bytes: 4_096)
        let context = try reviewPlanContext()
        let session = try ReviewPlanLaunchSession("launch-a")

        #expect(throws: ReviewPlanBuildError.emptySelection) {
            try ReviewPlanDraft(
                selectedCandidates: [],
                versionContext: context,
                launchSession: session,
                createdAt: .init(unixNanoseconds: 1)
            )
        }
        #expect(throws: ReviewPlanBuildError.duplicateStableTargetID) {
            try ReviewPlanDraft(
                selectedCandidates: [candidate, candidate],
                versionContext: context,
                launchSession: session,
                createdAt: .init(unixNanoseconds: 1)
            )
        }
        #expect(throws: PlanDigestError.invalidDigestLength) {
            try PlanDigest(bytes: [1, 2, 3])
        }
        #expect(throws: ReviewPlanBuildError.invalidExpiry) {
            try ReviewPlanDraft(
                selectedCandidates: [candidate],
                versionContext: context,
                launchSession: session,
                createdAt: .init(unixNanoseconds: Int64.max - 1)
            )
        }
    }

    @Test
    func cryptoKitAdapterMatchesKnownSha256VectorAndRecordsNoEffects() throws {
        let digest = try CryptoKitPlanDigestAdapter().digest(canonicalBytes: Array("abc".utf8))
        let expected = Array(SHA256.hash(data: Data("abc".utf8)))

        #expect(digest.bytes == expected)
        #expect(digest.bytes.count == 32)
    }
}

final class RecordingPlanDigesting: PlanDigesting, @unchecked Sendable {
    private(set) var inputs: [[UInt8]] = []

    func digest(canonicalBytes: [UInt8]) throws -> PlanDigest {
        inputs.append(canonicalBytes)
        return try PlanDigest(bytes: Array(repeating: UInt8(canonicalBytes.count % 251), count: 32))
    }
}

func reviewPlanContext() throws -> ReviewPlanVersionContext {
    try .init(
        appPlanVersion: "5.0.0",
        policyVersion: "policy-1",
        detectorCatalogVersion: GeneralMacScopeCatalog.current.version.value,
        encodingVersion: 1
    )
}

func cleanupCandidate(component: String, bytes: Int64) throws -> EligibleCandidate {
    let catalog = GeneralMacScopeCatalog.current
    let root = try catalog.declaredRoot(for: .userLibraryCaches)
    let observation = try FileObservation(
        rootID: root.id,
        locator: .init(rootID: root.id, components: ["com.apple.iconservices.store", component]),
        resourceIdentity: .observed(.init(device: 10, node: UInt64(bytes))),
        sizes: .init(logicalBytes: .observed(bytes), allocatedBytes: .observed(bytes)),
        modification: .observed(.init(unixNanoseconds: 1)),
        fileKind: .regularFile,
        volume: .observed(try .init("plan-volume")),
        linkCount: .observed(1),
        boundaries: .init(
            symlink: .observed(false), alias: .observed(false), package: .observed(false),
            mount: .observed(false), protectedRoot: .observed(false),
            homeBoundary: .observed(false), externalVolume: .observed(false)
        )
    )
    let finding = try #require(try GeneralMacEvidenceDetector(scope: .userLibraryCaches)
        .makeFinding(
            from: observation,
            request: catalog.scanRequest(for: [.userLibraryCaches]),
            clockReading: .init(
                observationInstant: .init(monotonicNanoseconds: 900_000_000_001),
                wallClockInstant: .init(unixNanoseconds: 900_000_000_001)
            )
        )
        .get())
    let evaluation = PolicyEvaluator().evaluate(finding)
    return try #require(evaluation.candidate)
}
