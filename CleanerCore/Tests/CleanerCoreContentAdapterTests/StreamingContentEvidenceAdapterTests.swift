import CryptoKit
import Foundation
import Testing
@testable import CleanerCore
@testable import CleanerCoreContentAdapter

@Suite("Streaming Content Evidence Adapter")
struct StreamingContentEvidenceAdapterTests {
    @Test
    func testOwnedFileStreamsAcrossTheOneMiBBoundaryAndMatchesCryptoKit() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let bytes = Data((0 ..< ContentReadLimits.current.maximumChunkBytes + 17).map {
            UInt8($0 % 251)
        })
        let file = try fixture.write(bytes, named: "multi-chunk.bin")
        let request = try fixture.request(for: file, logicalBytes: Int64(bytes.count))
        let adapter = try StreamingContentEvidenceAdapter(
            catalog: .current,
            anchors: fixture.anchors,
            sessionLimits: .current,
            fileSystem: FoundationStreamingContentFileSystem(fileManager: FileManager()),
            cancellation: ScriptedContentCancellation()
        )
        let expected = try ContentDigest(opaqueBytes: Array(SHA256.hash(data: bytes)))
        let session = await adapter.beginSession(limits: .current)

        #expect(await session.contentEvidence(for: request) == .complete(expected))
    }

    @Test
    func injectedReaderNeverReceivesARequestAboveTheConfiguredChunkLimit() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let data = Data([0, 1, 2, 3, 4, 5, 6])
        let reader = ScriptedContentReader(data: data)
        let fileSystem = try await fixture.scriptedFileSystem(
            fileName: "bounded.bin",
            data: data,
            reader: reader
        )
        let limits = try ContentReadLimits(
            maximumCandidatesPerScan: 4,
            maximumChunkBytes: 3,
            maximumBytesPerFile: 16,
            maximumBytesPerScan: 32
        )
        let adapter = try fixture.adapter(
            sessionLimits: limits,
            fileSystem: fileSystem
        )
        let session = await adapter.beginSession(limits: limits)

        let outcome = await session.contentEvidence(for: try fixture.request(
            fileName: "bounded.bin",
            logicalBytes: Int64(data.count),
            limits: limits
        ))
        let expected = try ContentDigest(opaqueBytes: Array(SHA256.hash(data: data)))

        #expect(outcome == .complete(expected))
        #expect(await reader.readRequests() == [3, 3, 1])
        #expect(await reader.closeCalls() == 1)
    }

    @Test
    func invalidAndOverwideLimitsFailBeforeAnyOpen() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let fileSystem = ScriptedContentFileSystem(metadata: [:], readers: [:])

        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentReadLimits(
                maximumCandidatesPerScan: 0,
                maximumChunkBytes: 1,
                maximumBytesPerFile: 1,
                maximumBytesPerScan: 1
            )
        }
        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentReadLimits(
                maximumCandidatesPerScan: ContentReadLimits.current.maximumCandidatesPerScan + 1,
                maximumChunkBytes: ContentReadLimits.current.maximumChunkBytes,
                maximumBytesPerFile: ContentReadLimits.current.maximumBytesPerFile,
                maximumBytesPerScan: ContentReadLimits.current.maximumBytesPerScan
            )
        }
        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentReadLimits(
                maximumCandidatesPerScan: 1,
                maximumChunkBytes: ContentReadLimits.current.maximumChunkBytes + 1,
                maximumBytesPerFile: 1,
                maximumBytesPerScan: 1
            )
        }
        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentReadLimits(
                maximumCandidatesPerScan: 1,
                maximumChunkBytes: 1,
                maximumBytesPerFile: ContentReadLimits.current.maximumBytesPerFile + 1,
                maximumBytesPerScan: ContentReadLimits.current.maximumBytesPerScan
            )
        }
        #expect(throws: ContentReadLimitsError.invalidLimit) {
            try ContentReadLimits(
                maximumCandidatesPerScan: 1,
                maximumChunkBytes: 1,
                maximumBytesPerFile: 1,
                maximumBytesPerScan: ContentReadLimits.current.maximumBytesPerScan + 1
            )
        }

        _ = try fixture.adapter(fileSystem: fileSystem)
        #expect(await fileSystem.openedPaths().isEmpty)
    }

    @Test
    func candidateAndAggregateByteBudgetsRejectBeforeASecondOpen() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let firstData = Data([1, 2, 3, 4])
        let secondData = Data([5])
        let firstReader = ScriptedContentReader(data: firstData)
        let secondReader = ScriptedContentReader(data: secondData)
        let firstURL = fixture.downloadsRoot.appendingPathComponent("first.bin")
        let secondURL = fixture.downloadsRoot.appendingPathComponent("second.bin")
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 17, node: 1))],
                firstURL.path: [.value(.safeFile(device: 17, node: 2, size: 4))],
                secondURL.path: [.value(.safeFile(device: 17, node: 3, size: 1))],
            ],
            readers: [firstURL.path: firstReader, secondURL.path: secondReader]
        )
        let limits = try ContentReadLimits(
            maximumCandidatesPerScan: 1,
            maximumChunkBytes: 4,
            maximumBytesPerFile: 4,
            maximumBytesPerScan: 4
        )
        let adapter = try fixture.adapter(sessionLimits: limits, fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: limits)

        let first = await session.contentEvidence(for: try fixture.request(
            fileName: "first.bin",
            identity: .init(device: 17, node: 2),
            logicalBytes: 4
        ))
        let second = await session.contentEvidence(for: try fixture.request(
            fileName: "second.bin",
            identity: .init(device: 17, node: 3),
            logicalBytes: 1
        ))

        #expect(first.code == .complete)
        #expect(second == .budgetExceeded)
        #expect(await fileSystem.openedPaths() == [firstURL.path])
        #expect(await secondReader.readRequests().isEmpty)
    }

    @Test
    func corruptTargetValidationDoesNotConsumeSessionBudget() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let corruptURL = fixture.downloadsRoot.appendingPathComponent("corrupt-budget.bin")
        let validURL = fixture.downloadsRoot.appendingPathComponent("valid-budget.bin")
        let validReader = ScriptedContentReader(
            data: Data([9]),
            openedIdentity: .init(device: 17, node: 3, logicalBytes: 1, isRegularFile: true)
        )
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 17, node: 1))],
                corruptURL.path: [.value(.safeFile(device: 17, node: nil, size: 1))],
                validURL.path: [.value(.safeFile(device: 17, node: 3, size: 1))],
            ],
            readers: [validURL.path: validReader]
        )
        let limits = try ContentReadLimits(
            maximumCandidatesPerScan: 1,
            maximumChunkBytes: 1,
            maximumBytesPerFile: 1,
            maximumBytesPerScan: 1
        )
        let adapter = try fixture.adapter(sessionLimits: limits, fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: limits)

        let corrupt = await session.contentEvidence(for: try fixture.request(
            fileName: "corrupt-budget.bin",
            identity: .init(device: 17, node: 2),
            logicalBytes: 1
        ))
        let valid = await session.contentEvidence(for: try fixture.request(
            fileName: "valid-budget.bin",
            identity: .init(device: 17, node: 3),
            logicalBytes: 1
        ))

        #expect(corrupt == .corrupt)
        #expect(valid.code == .complete)
        #expect(await fileSystem.openedPaths() == [validURL.path])
    }

    @Test
    func perFileSessionLimitRejectsBeforeOpen() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let url = fixture.downloadsRoot.appendingPathComponent("oversized.bin")
        let reader = ScriptedContentReader(data: Data(repeating: 1, count: 4))
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 18, node: 1))],
                url.path: [.value(.safeFile(device: 18, node: 2, size: 4))],
            ],
            readers: [url.path: reader]
        )
        let limits = try ContentReadLimits(
            maximumCandidatesPerScan: 2,
            maximumChunkBytes: 2,
            maximumBytesPerFile: 3,
            maximumBytesPerScan: 8
        )
        let adapter = try fixture.adapter(sessionLimits: limits, fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: limits)

        let outcome = await session.contentEvidence(for: try fixture.request(
            fileName: "oversized.bin",
            identity: .init(device: 18, node: 2),
            logicalBytes: 4
        ))

        #expect(outcome == .budgetExceeded)
        #expect(await fileSystem.openedPaths().isEmpty)
    }

    @Test(arguments: ContentCancellationCheckpoint.allCases)
    func cancellationAtEveryPublishedCheckpointStopsWithExactReaderCalls(
        _ checkpoint: ContentCancellationCheckpoint
    ) async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let data = Data([7])
        let reader = ScriptedContentReader(data: data)
        let fileSystem = try await fixture.scriptedFileSystem(
            fileName: "cancel.bin",
            data: data,
            reader: reader
        )
        let cancellation = ScriptedContentCancellation(cancelAt: checkpoint)
        let adapter = try fixture.adapter(
            fileSystem: fileSystem,
            cancellation: cancellation
        )
        let session = await adapter.beginSession(limits: .current)

        let outcome = await session.contentEvidence(for: try fixture.request(
            fileName: "cancel.bin",
            logicalBytes: 1
        ))

        #expect(outcome == .cancelled)
        #expect(await fileSystem.openedPaths().count == (checkpoint == .beforeOpen ? 0 : 1))
        let expectedReadCount = checkpoint == .beforeFinalization || checkpoint == .beforePublishing
            ? 1
            : 0
        #expect(await reader.readRequests().count == expectedReadCount)
    }

    @Test
    func cancellationBetweenChunksStopsBeforeAnotherRead() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let data = Data([1, 2, 3, 4])
        let reader = ScriptedContentReader(data: data)
        let fileSystem = try await fixture.scriptedFileSystem(
            fileName: "chunk-cancel.bin",
            data: data,
            reader: reader
        )
        let limits = try ContentReadLimits(
            maximumCandidatesPerScan: 2,
            maximumChunkBytes: 2,
            maximumBytesPerFile: 8,
            maximumBytesPerScan: 8
        )
        let cancellation = ScriptedContentCancellation(
            cancelAt: .beforeEachChunk,
            occurrence: 2
        )
        let adapter = try fixture.adapter(
            sessionLimits: limits,
            fileSystem: fileSystem,
            cancellation: cancellation
        )
        let session = await adapter.beginSession(limits: limits)

        let outcome = await session.contentEvidence(for: try fixture.request(
            fileName: "chunk-cancel.bin",
            logicalBytes: 4,
            limits: limits
        ))

        #expect(outcome == .cancelled)
        #expect(await reader.readRequests() == [2])
    }

    @Test
    func deniedOpenAndPartialReadReturnDistinctTypedOutcomes() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let deniedURL = fixture.downloadsRoot.appendingPathComponent("denied.bin")
        let partialURL = fixture.downloadsRoot.appendingPathComponent("partial.bin")
        let partialReader = ScriptedContentReader(
            data: Data([1, 2, 3, 4]),
            maximumReadableBytes: 2,
            openedIdentity: .init(
                device: 19,
                node: 3,
                logicalBytes: 4,
                isRegularFile: true
            )
        )
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 19, node: 1))],
                deniedURL.path: [.value(.safeFile(device: 19, node: 2, size: 4))],
                partialURL.path: [.value(.safeFile(device: 19, node: 3, size: 4))],
            ],
            readers: [partialURL.path: partialReader],
            openFaults: [deniedURL.path: .denied]
        )
        let adapter = try fixture.adapter(fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: .current)

        let denied = await session.contentEvidence(for: try fixture.request(
            fileName: "denied.bin",
            identity: .init(device: 19, node: 2),
            logicalBytes: 4
        ))
        let partial = await session.contentEvidence(for: try fixture.request(
            fileName: "partial.bin",
            identity: .init(device: 19, node: 3),
            logicalBytes: 4
        ))

        #expect(denied == .denied)
        #expect(partial == .partial)
    }

    @Test
    func malformedMetadataAndChangedIdentityFailClosedWithoutPublication() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let malformedURL = fixture.downloadsRoot.appendingPathComponent("malformed.bin")
        let changedURL = fixture.downloadsRoot.appendingPathComponent("changed.bin")
        let changedReader = ScriptedContentReader(
            data: Data([1]),
            openedIdentity: .init(
                device: 20,
                node: 3,
                logicalBytes: 1,
                isRegularFile: true
            )
        )
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 20, node: 1))],
                malformedURL.path: [.value(.safeFile(device: 20, node: nil, size: 1))],
                changedURL.path: [
                    .value(.safeFile(device: 20, node: 3, size: 1)),
                    .value(.safeFile(device: 20, node: 4, size: 1)),
                ],
            ],
            readers: [changedURL.path: changedReader]
        )
        let adapter = try fixture.adapter(fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: .current)

        let malformed = await session.contentEvidence(for: try fixture.request(
            fileName: "malformed.bin",
            identity: .init(device: 20, node: 2),
            logicalBytes: 1
        ))
        let changed = await session.contentEvidence(for: try fixture.request(
            fileName: "changed.bin",
            identity: .init(device: 20, node: 3),
            logicalBytes: 1
        ))

        #expect(malformed == .corrupt)
        #expect(changed == .corrupt)
        #expect(await changedReader.readRequests().isEmpty)
    }

    @Test
    func openedDescriptorIdentityMismatchFailsBeforeTheFirstRead() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let url = fixture.downloadsRoot.appendingPathComponent("descriptor-mismatch.bin")
        let reader = ScriptedContentReader(
            data: Data([1]),
            openedIdentity: .init(
                device: 21,
                node: 999,
                logicalBytes: 1,
                isRegularFile: true
            )
        )
        let fileSystem = ScriptedContentFileSystem(
            metadata: [
                fixture.downloadsRoot.path: [.value(.safeDirectory(device: 21, node: 1))],
                url.path: [.value(.safeFile(device: 21, node: 2, size: 1))],
            ],
            readers: [url.path: reader]
        )
        let adapter = try fixture.adapter(fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: .current)

        let outcome = await session.contentEvidence(for: try fixture.request(
            fileName: "descriptor-mismatch.bin",
            identity: .init(device: 21, node: 2),
            logicalBytes: 1
        ))

        #expect(outcome == .corrupt)
        #expect(await reader.readRequests().isEmpty)
        #expect(await reader.closeCalls() == 1)
    }

    @Test
    func leafSwappedToSymlinkBeforeOpenCannotPublishTargetDigest() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let leaf = try fixture.write(Data([1]), named: "swapped.bin")
        let target = try fixture.write(Data([9]), named: "outside-target.bin")
        let request = try fixture.request(for: leaf, logicalBytes: 1)
        let fileSystem = SymlinkSwappingContentFileSystem(
            leaf: leaf,
            target: target,
            fileManager: FileManager()
        )
        let adapter = try fixture.adapter(fileSystem: fileSystem)
        let session = await adapter.beginSession(limits: .current)

        #expect(await session.contentEvidence(for: request) == .corrupt)
        #expect(await fileSystem.openAttempts() == 1)
    }

    @Test
    func symlinkOrEscapingLocatorNeverOpensContent() async throws {
        let fixture = try ContentAdapterTemporaryFixture()
        let target = try fixture.write(Data([1]), named: "target.bin")
        let link = fixture.downloadsRoot.appendingPathComponent("link.bin")
        try FileManager().createSymbolicLink(at: link, withDestinationURL: target)
        let fileSystem = FoundationStreamingContentFileSystem(fileManager: FileManager())
        let adapter = try fixture.adapter(fileSystem: fileSystem)

        let attributes = try FileManager().attributesOfItem(atPath: target.path)
        let device = try #require((attributes[.systemNumber] as? NSNumber)?.uint64Value)
        let node = try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
        let request = try fixture.request(
            fileName: "link.bin",
            identity: .init(device: device, node: node),
            logicalBytes: 1
        )
        let session = await adapter.beginSession(limits: .current)

        #expect(await session.contentEvidence(for: request) == .corrupt)
        #expect(throws: EvidenceValidationError.invalidRelativeLocator) {
            try RelativeLocator(
                rootID: request.declaredRootID,
                components: ["..", "target.bin"]
            )
        }
    }

    @Test
    func fixedLimitsRemainExactlyOneMiBSixteenGiBSixtyFourGiBAnd4096Candidates() {
        #expect(ContentReadLimits.current.maximumChunkBytes == 1_048_576)
        #expect(ContentReadLimits.current.maximumBytesPerFile == 17_179_869_184)
        #expect(ContentReadLimits.current.maximumBytesPerScan == 68_719_476_736)
        #expect(ContentReadLimits.current.maximumCandidatesPerScan == 4_096)
    }
}

final class ContentAdapterTemporaryFixture {
    let parent: URL
    let home: URL
    let temporary: URL
    let downloadsRoot: URL
    let anchors: ContentAdapterRootAnchors
    private let manager = FileManager()

    init() throws {
        parent = manager.temporaryDirectory
            .appendingPathComponent("mymaccleaner-content-adapter-tests")
            .appendingPathComponent(UUID().uuidString)
        home = parent.appendingPathComponent("home")
        temporary = parent.appendingPathComponent("temporary")
        downloadsRoot = home.appendingPathComponent("Downloads")
        for root in [
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Logs"),
            temporary,
            downloadsRoot,
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
        ] {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        anchors = ContentAdapterRootAnchors(
            homeDirectory: home,
            temporaryDirectory: temporary
        )
    }

    deinit {
        try? manager.removeItem(at: parent)
    }

    func write(_ data: Data, named name: String) throws -> URL {
        let url = downloadsRoot.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func request(
        for file: URL,
        logicalBytes: Int64,
        limits: ContentReadLimits = .current
    ) throws -> ContentEvidenceRequest {
        let attributes = try manager.attributesOfItem(atPath: file.path)
        let device = try #require((attributes[.systemNumber] as? NSNumber)?.uint64Value)
        let node = try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
        return try request(
            fileName: file.lastPathComponent,
            identity: .init(device: device, node: node),
            logicalBytes: logicalBytes,
            limits: limits
        )
    }

    func request(
        fileName: String,
        identity: FileIdentityEvidence = .init(device: 17, node: 2),
        logicalBytes: Int64,
        limits: ContentReadLimits = .current
    ) throws -> ContentEvidenceRequest {
        let rootID = try GeneralMacScopeCatalog.current
            .declaredRoot(for: .userDownloads).id
        return try .init(
            declaredRootID: rootID,
            locator: .init(rootID: rootID, components: [fileName]),
            resource: .init(
                volume: try VolumeID("device:\(identity.device)"),
                identity: identity
            ),
            expectedLogicalBytes: logicalBytes,
            limits: limits
        )
    }

    func adapter(
        sessionLimits: ContentReadLimits = .current,
        fileSystem: any StreamingContentFileSystem,
        cancellation: any ContentCancellationChecking = ScriptedContentCancellation()
    ) throws -> StreamingContentEvidenceAdapter {
        try .init(
            catalog: .current,
            anchors: anchors,
            sessionLimits: sessionLimits,
            fileSystem: fileSystem,
            cancellation: cancellation
        )
    }

    func scriptedFileSystem(
        fileName: String,
        data: Data,
        reader: ScriptedContentReader
    ) async throws -> ScriptedContentFileSystem {
        let fileURL = downloadsRoot.appendingPathComponent(fileName)
        return ScriptedContentFileSystem(
            metadata: [
                downloadsRoot.path: [.value(.safeDirectory(device: 17, node: 1))],
                fileURL.path: [.value(.safeFile(
                    device: 17,
                    node: 2,
                    size: Int64(data.count)
                ))],
            ],
            readers: [fileURL.path: reader]
        )
    }
}

private actor ScriptedContentCancellation: ContentCancellationChecking {
    private let cancelAt: ContentCancellationCheckpoint?
    private let occurrence: Int
    private var seen: [ContentCancellationCheckpoint: Int] = [:]

    init(
        cancelAt: ContentCancellationCheckpoint? = nil,
        occurrence: Int = 1
    ) {
        self.cancelAt = cancelAt
        self.occurrence = occurrence
    }

    func isCancellationRequested(at checkpoint: ContentCancellationCheckpoint) async -> Bool {
        seen[checkpoint, default: 0] += 1
        return checkpoint == cancelAt && seen[checkpoint] == occurrence
    }
}

enum ScriptedMetadataStep: Sendable {
    case value(ContentFileMetadata)
    case denied
    case corrupt
}

enum ScriptedOpenFault: Sendable {
    case denied
    case corrupt
}

actor ScriptedContentFileSystem: StreamingContentFileSystem {
    private var metadataSteps: [String: [ScriptedMetadataStep]]
    private let readers: [String: any StreamingContentFileReader]
    private let openFaults: [String: ScriptedOpenFault]
    private var opens: [String] = []

    init(
        metadata: [String: [ScriptedMetadataStep]],
        readers: [String: any StreamingContentFileReader],
        openFaults: [String: ScriptedOpenFault] = [:]
    ) {
        metadataSteps = metadata
        self.readers = readers
        self.openFaults = openFaults
    }

    func metadata(at url: URL) async throws -> ContentFileMetadata {
        guard var steps = metadataSteps[url.path], let first = steps.first else {
            throw ContentAdapterTestError.corrupt
        }
        if steps.count > 1 {
            steps.removeFirst()
            metadataSteps[url.path] = steps
        }
        switch first {
        case .value(let metadata):
            return metadata
        case .denied:
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(POSIXErrorCode.EACCES.rawValue)
            )
        case .corrupt:
            throw ContentAdapterTestError.corrupt
        }
    }

    func openForReading(at url: URL) async throws -> any StreamingContentFileReader {
        opens.append(url.path)
        if let fault = openFaults[url.path] {
            switch fault {
            case .denied:
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(POSIXErrorCode.EACCES.rawValue)
                )
            case .corrupt:
                throw ContentAdapterTestError.corrupt
            }
        }
        guard let reader = readers[url.path] else {
            throw ContentAdapterTestError.corrupt
        }
        return reader
    }

    func openedPaths() -> [String] {
        opens
    }
}

actor ScriptedContentReader: StreamingContentFileReader {
    private let data: Data
    private let maximumReadableBytes: Int
    private let identity: OpenedContentIdentity
    private var offset = 0
    private var requests: [Int] = []
    private var closes = 0

    init(
        data: Data,
        maximumReadableBytes: Int? = nil,
        openedIdentity: OpenedContentIdentity? = nil
    ) {
        self.data = data
        self.maximumReadableBytes = maximumReadableBytes ?? data.count
        identity = openedIdentity ?? .init(
            device: 17,
            node: 2,
            logicalBytes: Int64(data.count),
            isRegularFile: true
        )
    }

    func read(upToCount count: Int) async throws -> Data? {
        requests.append(count)
        guard offset < min(data.count, maximumReadableBytes) else { return nil }
        let end = min(offset + count, data.count, maximumReadableBytes)
        defer { offset = end }
        return Data(data[offset ..< end])
    }

    func openedIdentity() async -> OpenedContentIdentity? { identity }

    func close() async -> Bool {
        closes += 1
        return true
    }

    func readRequests() -> [Int] { requests }
    func closeCalls() -> Int { closes }
}

private actor SymlinkSwappingContentFileSystem: StreamingContentFileSystem {
    private let leaf: URL
    private let target: URL
    private let fileManager: FileManager
    private let foundation: FoundationStreamingContentFileSystem
    private var attempts = 0

    init(leaf: URL, target: URL, fileManager: FileManager) {
        self.leaf = leaf
        self.target = target
        self.fileManager = fileManager
        foundation = FoundationStreamingContentFileSystem(fileManager: FileManager())
    }

    func metadata(at url: URL) async throws -> ContentFileMetadata {
        try await foundation.metadata(at: url)
    }

    func openForReading(at url: URL) async throws -> any StreamingContentFileReader {
        attempts += 1
        if url == leaf {
            try fileManager.removeItem(at: leaf)
            try fileManager.createSymbolicLink(at: leaf, withDestinationURL: target)
        }
        return try await foundation.openForReading(at: url)
    }

    func openAttempts() -> Int { attempts }
}

private enum ContentAdapterTestError: Error {
    case corrupt
}

extension ContentFileMetadata {
    static func safeDirectory(device: UInt64, node: UInt64?) -> ContentFileMetadata {
        .init(
            device: device,
            node: node,
            logicalBytes: 0,
            isDirectory: true,
            isRegularFile: false,
            isSymbolicLink: false,
            isAliasFile: false,
            isPackage: false,
            isMountTrigger: false,
            volumeIsInternal: true
        )
    }

    static func safeFile(
        device: UInt64,
        node: UInt64?,
        size: Int64
    ) -> ContentFileMetadata {
        .init(
            device: device,
            node: node,
            logicalBytes: size,
            isDirectory: false,
            isRegularFile: true,
            isSymbolicLink: false,
            isAliasFile: false,
            isPackage: false,
            isMountTrigger: false,
            volumeIsInternal: true
        )
    }
}
