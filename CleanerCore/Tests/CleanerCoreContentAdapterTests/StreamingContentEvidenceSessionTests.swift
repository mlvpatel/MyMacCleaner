import Foundation
import Testing
@testable import CleanerCore
@testable import CleanerCoreContentAdapter

extension StreamingContentEvidenceAdapterTests {
    @Test
    func requestScopedAggregateBudgetRequiresANewOpaqueSession() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let firstURL = fixture.downloadsRoot.appendingPathComponent("first-session.bin")
        let secondURL = fixture.downloadsRoot.appendingPathComponent("second-session.bin")
        let firstReader = ScriptedContentReader(
            data: Data([1]),
            openedIdentity: .init(device: 17, node: 2, logicalBytes: 1, isRegularFile: true)
        )
        let secondReader = ScriptedContentReader(
            data: Data([2]),
            openedIdentity: .init(device: 17, node: 3, logicalBytes: 1, isRegularFile: true)
        )
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 17, node: 1))],
                firstURL.path: [.value(.safeFile(device: 17, node: 2, size: 1))],
                secondURL.path: [.value(.safeFile(device: 17, node: 3, size: 1))],
            ],
            readers: [firstURL.path: firstReader, secondURL.path: secondReader]
        )
        let requestLimits = try ContentReadLimits(
            maximumCandidatesPerScan: 1,
            maximumChunkBytes: 1,
            maximumBytesPerFile: 1,
            maximumBytesPerScan: 1
        )
        let adapter = try fixture.adapter(
            sessionLimits: .current,
            fileSystem: fileSystem
        )
        let firstRequest = try fixture.request(
            fileName: "first-session.bin",
            identity: .init(device: 17, node: 2),
            logicalBytes: 1,
            limits: requestLimits
        )
        let secondRequest = try fixture.request(
            fileName: "second-session.bin",
            identity: .init(device: 17, node: 3),
            logicalBytes: 1,
            limits: requestLimits
        )

        let firstSession = await adapter.beginSession(limits: requestLimits)
        #expect((await firstSession.contentEvidence(for: firstRequest)).code == .complete)
        #expect(await firstSession.contentEvidence(for: secondRequest) == .budgetExceeded)
        #expect(await fileSystem.openedPaths() == [firstURL.path])

        let secondSession = await adapter.beginSession(limits: requestLimits)

        #expect((await secondSession.contentEvidence(for: secondRequest)).code == .complete)
        #expect(await fileSystem.openedPaths() == [firstURL.path, secondURL.path])
    }

    @Test
    func concurrentOpaqueSessionsDoNotShareOrResetAggregateReservations() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let firstURL = fixture.downloadsRoot.appendingPathComponent("concurrent-first.bin")
        let secondURL = fixture.downloadsRoot.appendingPathComponent("concurrent-second.bin")
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 17, node: 1))],
                firstURL.path: [.value(.safeFile(device: 17, node: 2, size: 1))],
                secondURL.path: [.value(.safeFile(device: 17, node: 3, size: 1))],
            ],
            readers: [
                firstURL.path: ScriptedContentReader(
                    data: Data([1]),
                    openedIdentity: .init(device: 17, node: 2, logicalBytes: 1, isRegularFile: true)
                ),
                secondURL.path: ScriptedContentReader(
                    data: Data([2]),
                    openedIdentity: .init(device: 17, node: 3, logicalBytes: 1, isRegularFile: true)
                ),
            ]
        )
        let limits = try ContentReadLimits(
            maximumCandidatesPerScan: 1,
            maximumChunkBytes: 1,
            maximumBytesPerFile: 1,
            maximumBytesPerScan: 1
        )
        let adapter: any ContentEvidencePort = try fixture.adapter(
            sessionLimits: .current,
            fileSystem: fileSystem
        )
        let firstRequest = try fixture.request(
            fileName: "concurrent-first.bin",
            identity: .init(device: 17, node: 2),
            logicalBytes: 1,
            limits: limits
        )
        let secondRequest = try fixture.request(
            fileName: "concurrent-second.bin",
            identity: .init(device: 17, node: 3),
            logicalBytes: 1,
            limits: limits
        )
        let firstSession = await adapter.beginSession(limits: limits)
        let secondSession = await adapter.beginSession(limits: limits)

        async let first = firstSession.contentEvidence(for: firstRequest)
        async let second = secondSession.contentEvidence(for: secondRequest)
        let (firstOutcome, secondOutcome) = await (first, second)
        let outcomes = [firstOutcome.code, secondOutcome.code]

        #expect(outcomes == [.complete, .complete])
        #expect(Set(await fileSystem.openedPaths()) == Set([firstURL.path, secondURL.path]))
    }

    @Test
    func concurrentRequestsInOneSessionReserveTheSingleCandidateAtomically() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let firstURL = fixture.downloadsRoot.appendingPathComponent("same-session-first.bin")
        let secondURL = fixture.downloadsRoot.appendingPathComponent("same-session-second.bin")
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 17, node: 1))],
                firstURL.path: [.value(.safeFile(device: 17, node: 2, size: 1))],
                secondURL.path: [.value(.safeFile(device: 17, node: 3, size: 1))],
            ],
            readers: [
                firstURL.path: ScriptedContentReader(
                    data: Data([1]),
                    openedIdentity: .init(device: 17, node: 2, logicalBytes: 1, isRegularFile: true)
                ),
                secondURL.path: ScriptedContentReader(
                    data: Data([2]),
                    openedIdentity: .init(device: 17, node: 3, logicalBytes: 1, isRegularFile: true)
                ),
            ]
        )
        let limits = try ContentReadLimits(
            maximumCandidatesPerScan: 1,
            maximumChunkBytes: 1,
            maximumBytesPerFile: 1,
            maximumBytesPerScan: 1
        )
        let adapter = try fixture.adapter(sessionLimits: .current, fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: limits)
        let firstRequest = try fixture.request(
            fileName: "same-session-first.bin",
            identity: .init(device: 17, node: 2),
            logicalBytes: 1,
            limits: limits
        )
        let secondRequest = try fixture.request(
            fileName: "same-session-second.bin",
            identity: .init(device: 17, node: 3),
            logicalBytes: 1,
            limits: limits
        )

        async let first = session.contentEvidence(for: firstRequest)
        async let second = session.contentEvidence(for: secondRequest)
        let (firstOutcome, secondOutcome) = await (first, second)
        let outcomes = [firstOutcome.code, secondOutcome.code]

        #expect(outcomes.filter { $0 == .complete }.count == 1)
        #expect(outcomes.filter { $0 == .budgetExceeded }.count == 1)
        #expect(await fileSystem.openedPaths().count == 1)
    }
}
