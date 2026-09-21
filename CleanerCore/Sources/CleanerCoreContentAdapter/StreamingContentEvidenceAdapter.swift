import CleanerCore
import CryptoKit
import Darwin
import Foundation

struct ContentAdapterRootAnchors: Sendable {
    let homeDirectory: URL
    let temporaryDirectory: URL

    init(homeDirectory: URL, temporaryDirectory: URL) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.temporaryDirectory = temporaryDirectory.standardizedFileURL
    }

    func url(for kind: GeneralMacRootKind) -> URL {
        switch kind {
        case .userLibraryCaches:
            return homeDirectory.appendingPathComponent("Library/Caches")
        case .userLibraryLogs:
            return homeDirectory.appendingPathComponent("Library/Logs")
        case .userTemporary:
            return temporaryDirectory
        case .userDownloads:
            return homeDirectory.appendingPathComponent("Downloads")
        case .userDesktop:
            return homeDirectory.appendingPathComponent("Desktop")
        case .userDocuments:
            return homeDirectory.appendingPathComponent("Documents")
        }
    }

    static func trusted(_ fileManager: FileManager) -> ContentAdapterRootAnchors {
        .init(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            temporaryDirectory: fileManager.temporaryDirectory.resolvingSymlinksInPath()
        )
    }
}

struct ContentFileMetadata: Equatable, Sendable {
    let device: UInt64?
    let node: UInt64?
    let logicalBytes: Int64?
    let isDirectory: Bool?
    let isRegularFile: Bool?
    let isSymbolicLink: Bool?
    let isAliasFile: Bool?
    let isPackage: Bool?
    let isMountTrigger: Bool?
    let volumeIsInternal: Bool?

    init(
        device: UInt64?,
        node: UInt64?,
        logicalBytes: Int64?,
        isDirectory: Bool?,
        isRegularFile: Bool?,
        isSymbolicLink: Bool?,
        isAliasFile: Bool?,
        isPackage: Bool?,
        isMountTrigger: Bool?,
        volumeIsInternal: Bool?
    ) {
        self.device = device
        self.node = node
        self.logicalBytes = logicalBytes
        self.isDirectory = isDirectory
        self.isRegularFile = isRegularFile
        self.isSymbolicLink = isSymbolicLink
        self.isAliasFile = isAliasFile
        self.isPackage = isPackage
        self.isMountTrigger = isMountTrigger
        self.volumeIsInternal = volumeIsInternal
    }
}

protocol StreamingContentFileReader: Sendable {
    func read(upToCount count: Int) async throws -> Data?
    func openedIdentity() async -> OpenedContentIdentity?
    func close() async -> Bool
}

struct OpenedContentIdentity: Equatable, Sendable {
    let device: UInt64
    let node: UInt64
    let logicalBytes: Int64
    let isRegularFile: Bool
}

protocol StreamingContentFileSystem: Sendable {
    func metadata(at url: URL) async throws -> ContentFileMetadata
    func openForReading(at url: URL) async throws -> any StreamingContentFileReader
}

protocol ContentCancellationChecking: Sendable {
    func isCancellationRequested(at checkpoint: ContentCancellationCheckpoint) async -> Bool
}

actor FoundationStreamingContentFileSystem: StreamingContentFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func metadata(at url: URL) async throws -> ContentFileMetadata {
        let values = try url.resourceValues(forKeys: contentResourceKeys)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return .init(
            device: numericValue(attributes[.systemNumber]),
            node: numericValue(attributes[.systemFileNumber]),
            logicalBytes: values.fileSize.map(Int64.init),
            isDirectory: values.isDirectory,
            isRegularFile: values.isRegularFile,
            isSymbolicLink: values.isSymbolicLink,
            isAliasFile: values.isAliasFile,
            isPackage: values.isPackage,
            isMountTrigger: values.isMountTrigger,
            volumeIsInternal: values.volumeIsInternal
        )
    }

    func openForReading(at url: URL) async throws -> any StreamingContentFileReader {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return FoundationStreamingContentFileReader(descriptor: descriptor)
    }
}

private actor FoundationStreamingContentFileReader: StreamingContentFileReader {
    private let descriptor: Int32
    private var isClosed = false

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func read(upToCount count: Int) async throws -> Data? {
        guard !isClosed else { throw ContentAdapterFault.partial }
        var buffer = [UInt8](repeating: 0, count: count)
        let bytesRead = Darwin.read(descriptor, &buffer, count)
        guard bytesRead >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard bytesRead > 0 else { return nil }
        return Data(buffer.prefix(Int(bytesRead)))
    }

    func openedIdentity() async -> OpenedContentIdentity? {
        guard !isClosed else { return nil }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_dev >= 0,
              information.st_ino >= 0,
              information.st_size >= 0 else {
            return nil
        }
        return .init(
            device: UInt64(information.st_dev),
            node: UInt64(information.st_ino),
            logicalBytes: Int64(information.st_size),
            isRegularFile: (information.st_mode & S_IFMT) == S_IFREG
        )
    }

    func close() async -> Bool {
        guard !isClosed else { return true }
        let result = Darwin.close(descriptor)
        isClosed = true
        return result == 0
    }
}

private struct TaskContentCancellation: ContentCancellationChecking {
    func isCancellationRequested(at checkpoint: ContentCancellationCheckpoint) async -> Bool {
        _ = checkpoint
        return Task<Never, Never>.isCancelled
    }
}

/// Creates isolated read-only content sessions for catalog-owned roots.
public actor StreamingContentEvidenceAdapter: ContentEvidencePort {
    private let roots: [DeclaredRootID: URL]
    private let maximumDepth: Int
    private let maximumSessionLimits: ContentReadLimits
    private let fileSystem: any StreamingContentFileSystem
    private let cancellation: any ContentCancellationChecking

    public init(catalog: GeneralMacScopeCatalog = .current) throws {
        let fileManager = FileManager()
        try self.init(
            catalog: catalog,
            anchors: .trusted(fileManager),
            sessionLimits: .current,
            fileSystem: FoundationStreamingContentFileSystem(fileManager: fileManager),
            cancellation: TaskContentCancellation()
        )
    }

    init(
        catalog: GeneralMacScopeCatalog,
        anchors: ContentAdapterRootAnchors,
        sessionLimits: ContentReadLimits,
        fileSystem: any StreamingContentFileSystem,
        cancellation: any ContentCancellationChecking
    ) throws {
        var mapped: [DeclaredRootID: URL] = [:]
        for registration in catalog.registrations {
            let root = try catalog.declaredRoot(for: registration.rootKind)
            mapped[root.id] = anchors.url(for: registration.rootKind).standardizedFileURL
        }
        roots = mapped
        maximumDepth = catalog.limits.maximumDepth
        maximumSessionLimits = sessionLimits
        self.fileSystem = fileSystem
        self.cancellation = cancellation
    }

    public func beginSession(limits: ContentReadLimits) async -> any ContentEvidenceSession {
        StreamingContentEvidenceSession(
            roots: roots,
            maximumDepth: maximumDepth,
            sessionLimits: .init(maximum: maximumSessionLimits, requested: limits),
            fileSystem: fileSystem,
            cancellation: cancellation
        )
    }

}

private struct ContentSessionLimits: Sendable {
    let maximumCandidatesPerScan: Int
    let maximumChunkBytes: Int
    let maximumBytesPerFile: Int64
    let maximumBytesPerScan: Int64

    init(maximum: ContentReadLimits, requested: ContentReadLimits) {
        maximumCandidatesPerScan = min(
            maximum.maximumCandidatesPerScan,
            requested.maximumCandidatesPerScan
        )
        maximumChunkBytes = min(maximum.maximumChunkBytes, requested.maximumChunkBytes)
        maximumBytesPerFile = min(maximum.maximumBytesPerFile, requested.maximumBytesPerFile)
        maximumBytesPerScan = min(maximum.maximumBytesPerScan, requested.maximumBytesPerScan)
    }
}

/// Opaque single-scan state. Counters and root snapshots cannot be reset by another caller.
private actor StreamingContentEvidenceSession: ContentEvidenceSession {
    private struct RootSnapshot: Equatable, Sendable {
        let device: UInt64
        let node: UInt64
    }

    private let roots: [DeclaredRootID: URL]
    private let maximumDepth: Int
    private let sessionLimits: ContentSessionLimits
    private let fileSystem: any StreamingContentFileSystem
    private let cancellation: any ContentCancellationChecking
    private var rootSnapshots: [DeclaredRootID: RootSnapshot] = [:]
    private var acceptedCandidates = 0
    private var acceptedBytes: Int64 = 0

    init(
        roots: [DeclaredRootID: URL],
        maximumDepth: Int,
        sessionLimits: ContentSessionLimits,
        fileSystem: any StreamingContentFileSystem,
        cancellation: any ContentCancellationChecking
    ) {
        self.roots = roots
        self.maximumDepth = maximumDepth
        self.sessionLimits = sessionLimits
        self.fileSystem = fileSystem
        self.cancellation = cancellation
    }

    func contentEvidence(for request: ContentEvidenceRequest) async -> ContentEvidenceOutcome {
        guard request.cancellationCheckpoints == ContentCancellationCheckpoint.allCases else {
            return .corrupt
        }
        guard fitsPerFileLimit(request) else { return .budgetExceeded }
        guard canReserve(request) else { return .budgetExceeded }
        if await isCancelled(at: .beforeOpen) { return .cancelled }

        let target: URL
        do {
            target = try await validatedTarget(for: request)
        } catch let fault as ContentAdapterFault {
            return fault.outcome
        } catch let error as NSError {
            return ContentAdapterFault(error: error, partialRead: false).outcome
        }

        guard canReserve(request) else { return .budgetExceeded }
        reserve(request)

        let reader: any StreamingContentFileReader
        do {
            reader = try await fileSystem.openForReading(at: target)
        } catch let error as NSError {
            return ContentAdapterFault(error: error, partialRead: false).outcome
        }

        do {
            guard await openedIdentityMatches(reader, request: request) else {
                throw ContentAdapterFault.corrupt
            }
            _ = try await validatedTarget(for: request)
        } catch let fault as ContentAdapterFault {
            _ = await reader.close()
            return fault.outcome
        } catch let error as NSError {
            _ = await reader.close()
            return ContentAdapterFault(error: error, partialRead: false).outcome
        }

        let outcome = await stream(request: request, reader: reader)
        let didClose = await reader.close()
        if !didClose, outcome.code == .complete {
            return .partial
        }
        return outcome
    }

    private func stream(
        request: ContentEvidenceRequest,
        reader: any StreamingContentFileReader
    ) async -> ContentEvidenceOutcome {
        var digest = SHA256()
        var deliveredBytes: Int64 = 0
        while deliveredBytes < request.expectedLogicalBytes {
            if await isCancelled(at: .beforeEachChunk) { return .cancelled }
            guard await openedIdentityMatches(reader, request: request) else {
                return .corrupt
            }
            do {
                _ = try await validatedTarget(for: request)
            } catch let fault as ContentAdapterFault {
                return fault.outcome
            } catch let error as NSError {
                return ContentAdapterFault(error: error, partialRead: true).outcome
            }

            let remaining = request.expectedLogicalBytes - deliveredBytes
            let chunkLimit = min(
                sessionLimits.maximumChunkBytes,
                request.limits.maximumChunkBytes
            )
            let requestedCount = Int(min(Int64(chunkLimit), remaining))
            let chunk: Data
            do {
                guard let next = try await reader.read(upToCount: requestedCount),
                      !next.isEmpty else {
                    return .partial
                }
                chunk = next
            } catch let error as NSError {
                return ContentAdapterFault(error: error, partialRead: true).outcome
            }
            guard chunk.count <= requestedCount else { return .corrupt }
            let (nextDeliveredBytes, overflow) = deliveredBytes.addingReportingOverflow(
                Int64(chunk.count)
            )
            guard !overflow, nextDeliveredBytes <= request.expectedLogicalBytes else {
                return .corrupt
            }
            digest.update(data: chunk)
            deliveredBytes = nextDeliveredBytes
        }

        if await isCancelled(at: .beforeFinalization) { return .cancelled }
        guard await openedIdentityMatches(reader, request: request) else {
            return .corrupt
        }
        do {
            _ = try await validatedTarget(for: request)
        } catch let fault as ContentAdapterFault {
            return fault.outcome
        } catch let error as NSError {
            return ContentAdapterFault(error: error, partialRead: true).outcome
        }

        let opaqueDigest: ContentDigest
        do {
            opaqueDigest = try ContentDigest(opaqueBytes: Array(digest.finalize()))
        } catch let error as ContentDigestError {
            _ = error
            return .corrupt
        } catch let error as NSError {
            _ = error.code
            return .corrupt
        }
        if await isCancelled(at: .beforePublishing) { return .cancelled }
        guard await openedIdentityMatches(reader, request: request) else {
            return .corrupt
        }
        do {
            _ = try await validatedTarget(for: request)
        } catch let fault as ContentAdapterFault {
            return fault.outcome
        } catch let error as NSError {
            return ContentAdapterFault(error: error, partialRead: true).outcome
        }
        return .complete(opaqueDigest)
    }

    private func validatedTarget(for request: ContentEvidenceRequest) async throws -> URL {
        guard request.declaredRootID == request.locator.rootID,
              request.locator.components.count <= maximumDepth,
              let root = roots[request.declaredRootID] else {
            throw ContentAdapterFault.corrupt
        }

        let rootMetadata = try await fileSystem.metadata(at: root)
        guard isSafeDirectory(rootMetadata),
              let rootDevice = rootMetadata.device,
              let rootNode = rootMetadata.node else {
            throw ContentAdapterFault.corrupt
        }
        let snapshot = RootSnapshot(device: rootDevice, node: rootNode)
        if let existing = rootSnapshots[request.declaredRootID] {
            guard existing == snapshot else { throw ContentAdapterFault.corrupt }
        } else {
            rootSnapshots[request.declaredRootID] = snapshot
        }

        var candidate = root
        for (index, component) in request.locator.components.enumerated() {
            candidate = candidate.appendingPathComponent(component, isDirectory: false)
                .standardizedFileURL
            guard candidate.path.hasPrefix(root.path + "/") else {
                throw ContentAdapterFault.corrupt
            }
            let metadata = try await fileSystem.metadata(at: candidate)
            guard hasSafeTopology(metadata), metadata.device == rootDevice else {
                throw ContentAdapterFault.corrupt
            }
            if index < request.locator.components.count - 1 {
                guard metadata.isDirectory == true else {
                    throw ContentAdapterFault.corrupt
                }
            } else {
                try validateLeaf(metadata, request: request)
            }
        }
        return candidate
    }

    private func validateLeaf(
        _ metadata: ContentFileMetadata,
        request: ContentEvidenceRequest
    ) throws {
        guard metadata.isRegularFile == true,
              metadata.isDirectory == false,
              let device = metadata.device,
              let node = metadata.node,
              let logicalBytes = metadata.logicalBytes,
              logicalBytes == request.expectedLogicalBytes,
              device == request.resource.identity.device,
              node == request.resource.identity.node,
              request.resource.volume.value == "device:\(device)" else {
            throw ContentAdapterFault.corrupt
        }
    }

    private func isSafeDirectory(_ metadata: ContentFileMetadata) -> Bool {
        metadata.isDirectory == true
            && metadata.isRegularFile == false
            && hasSafeTopology(metadata)
    }

    private func hasSafeTopology(_ metadata: ContentFileMetadata) -> Bool {
        metadata.isSymbolicLink == false
            && metadata.isAliasFile == false
            && metadata.isPackage == false
            && metadata.isMountTrigger == false
            && metadata.volumeIsInternal == true
    }

    private func fitsPerFileLimit(_ request: ContentEvidenceRequest) -> Bool {
        request.expectedLogicalBytes <= sessionLimits.maximumBytesPerFile
    }

    private func canReserve(_ request: ContentEvidenceRequest) -> Bool {
        let (candidateCount, candidateOverflow) = acceptedCandidates.addingReportingOverflow(1)
        let (byteCount, byteOverflow) = acceptedBytes.addingReportingOverflow(
            request.expectedLogicalBytes
        )
        return !candidateOverflow
            && !byteOverflow
            && candidateCount <= sessionLimits.maximumCandidatesPerScan
            && byteCount <= sessionLimits.maximumBytesPerScan
    }

    private func reserve(_ request: ContentEvidenceRequest) {
        acceptedCandidates += 1
        acceptedBytes += request.expectedLogicalBytes
    }

    private func isCancelled(at checkpoint: ContentCancellationCheckpoint) async -> Bool {
        if Task<Never, Never>.isCancelled { return true }
        return await cancellation.isCancellationRequested(at: checkpoint)
    }

    private func openedIdentityMatches(
        _ reader: any StreamingContentFileReader,
        request: ContentEvidenceRequest
    ) async -> Bool {
        guard let identity = await reader.openedIdentity() else { return false }
        return identity.isRegularFile
            && identity.device == request.resource.identity.device
            && identity.node == request.resource.identity.node
            && identity.logicalBytes == request.expectedLogicalBytes
    }
}

private enum ContentAdapterFault: Error {
    case denied
    case partial
    case corrupt

    init(error: NSError, partialRead: Bool) {
        let posixCode = Int32(exactly: error.code).flatMap(POSIXErrorCode.init(rawValue:))
        let isPOSIXDenied = error.domain == NSPOSIXErrorDomain
            && (posixCode == .EACCES || posixCode == .EPERM)
        let isCocoaDenied = error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.fileReadNoPermission.rawValue
        if isPOSIXDenied || isCocoaDenied {
            self = .denied
        } else if partialRead {
            self = .partial
        } else {
            self = .corrupt
        }
    }

    var outcome: ContentEvidenceOutcome {
        switch self {
        case .denied: return .denied
        case .partial: return .partial
        case .corrupt: return .corrupt
        }
    }
}

private let contentResourceKeys: Set<URLResourceKey> = [
    .fileSizeKey,
    .isAliasFileKey,
    .isDirectoryKey,
    .isMountTriggerKey,
    .isPackageKey,
    .isRegularFileKey,
    .isSymbolicLinkKey,
    .volumeIsInternalKey,
]

private func numericValue(_ value: Any?) -> UInt64? {
    if let value = value as? NSNumber {
        guard value.doubleValue.isFinite,
              value.doubleValue >= 0,
              value.doubleValue <= Double(UInt64.max) else {
            return nil
        }
        return value.uint64Value
    }
    if let value = value as? Int {
        return value >= 0 ? UInt64(value) : nil
    }
    return value as? UInt64
}
