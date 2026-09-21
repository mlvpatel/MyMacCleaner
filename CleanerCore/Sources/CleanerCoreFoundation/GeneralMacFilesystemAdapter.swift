import CleanerCore
import Foundation

public enum GeneralMacFilesystemAdapterError: Error, Equatable, Sendable {
    case invalidAnchor
}

struct GeneralMacResourceValues: Sendable {
    let contentModificationDate: Date?
    let fileAllocatedSize: Int?
    let fileSize: Int?
    let isAliasFile: Bool?
    let isDirectory: Bool?
    let isMountTrigger: Bool?
    let isPackage: Bool?
    let isRegularFile: Bool?
    let isSymbolicLink: Bool?
    let totalFileAllocatedSize: Int?
    let volumeIsInternal: Bool?

    init(
        contentModificationDate: Date? = nil,
        fileAllocatedSize: Int? = nil,
        fileSize: Int? = nil,
        isAliasFile: Bool? = nil,
        isDirectory: Bool? = nil,
        isMountTrigger: Bool? = nil,
        isPackage: Bool? = nil,
        isRegularFile: Bool? = nil,
        isSymbolicLink: Bool? = nil,
        totalFileAllocatedSize: Int? = nil,
        volumeIsInternal: Bool? = nil
    ) {
        self.contentModificationDate = contentModificationDate
        self.fileAllocatedSize = fileAllocatedSize
        self.fileSize = fileSize
        self.isAliasFile = isAliasFile
        self.isDirectory = isDirectory
        self.isMountTrigger = isMountTrigger
        self.isPackage = isPackage
        self.isRegularFile = isRegularFile
        self.isSymbolicLink = isSymbolicLink
        self.totalFileAllocatedSize = totalFileAllocatedSize
        self.volumeIsInternal = volumeIsInternal
    }

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: resourceKeys)
        self.init(
            contentModificationDate: values.contentModificationDate,
            fileAllocatedSize: values.fileAllocatedSize,
            fileSize: values.fileSize,
            isAliasFile: values.isAliasFile,
            isDirectory: values.isDirectory,
            isMountTrigger: values.isMountTrigger,
            isPackage: values.isPackage,
            isRegularFile: values.isRegularFile,
            isSymbolicLink: values.isSymbolicLink,
            totalFileAllocatedSize: values.totalFileAllocatedSize,
            volumeIsInternal: values.volumeIsInternal
        )
    }
}

struct GeneralMacRootAnchors: Sendable {
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
}

/// Read-only, lazy enumeration: one filesystem entry is observed per call.
public actor GeneralMacFilesystemAdapter: FileSystemPort {
    private struct RootSnapshot: Equatable {
        let device: UInt64
        let node: UInt64
        let isDirectory: Bool
    }

    private struct State {
        let root: URL
        let snapshot: RootSnapshot
        let enumerator: FileManager.DirectoryEnumerator
        let faultState: EnumerationFaultState
        var position: UInt
    }

    private let roots: [DeclaredRootID: URL]
    private let fileManager: FileManager
    private let resourceValues: @Sendable (URL) throws -> GeneralMacResourceValues
    private var states: [DeclaredRootID: State] = [:]

    public init(catalog: GeneralMacScopeCatalog) throws {
        let fileManager = FileManager()
        try self.init(
            catalog: catalog,
            anchors: .trusted(fileManager),
            fileManager: fileManager
        )
    }

    init(
        catalog: GeneralMacScopeCatalog,
        anchors: GeneralMacRootAnchors,
        fileManager: FileManager,
        resourceValues: @escaping @Sendable (URL) throws -> GeneralMacResourceValues = {
            try GeneralMacResourceValues(url: $0)
        }
    ) throws {
        guard isValidAnchor(anchors.homeDirectory, manager: fileManager),
              isValidAnchor(anchors.temporaryDirectory, manager: fileManager) else {
            throw GeneralMacFilesystemAdapterError.invalidAnchor
        }
        var mapped: [DeclaredRootID: URL] = [:]
        for registration in catalog.registrations {
            let anchor = anchors.url(for: registration.rootKind).standardizedFileURL
            mapped[try catalog.declaredRoot(for: registration.rootKind).id] = anchor
        }
        roots = mapped
        self.fileManager = fileManager
        self.resourceValues = resourceValues
    }

    public func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        do {
            var state = try state(for: root)
            guard try rootSnapshot(at: state.root) == state.snapshot else {
                return .terminal(.unsupportedLayout)
            }
            guard try isSafeDerivedRoot(state.root) else {
                return .terminal(.unsupportedLayout)
            }
            if let fault = state.faultState.value {
                states.removeValue(forKey: root.id)
                return .terminal(fault.outcome)
            }
            guard cursorIsValid(cursor, state: state) else {
                return .terminal(.corruptMetadata)
            }
            guard state.position < UInt(GeneralMacScanLimits.current.maximumEntriesPerRoot) else {
                return .terminal(.corruptMetadata)
            }
            guard let url = state.enumerator.nextObject() as? URL else {
                if let fault = state.faultState.value {
                    states.removeValue(forKey: root.id)
                    return .terminal(fault.outcome)
                }
                states.removeValue(forKey: root.id)
                return .terminal(.complete)
            }
            let observation = try observe(url.standardizedFileURL, root: root, state: state)
            state.position += 1
            states[root.id] = state
            return .observation(observation)
        } catch let fault as Fault {
            return .terminal(fault.outcome)
        } catch let error as NSError {
            return .terminal(Fault(error: error).outcome)
        }
    }

    private func state(for root: DeclaredRoot) throws -> State {
        if let state = states[root.id] {
            return state
        }
        let faultState = EnumerationFaultState()
        guard let url = roots[root.id],
              let snapshot = try rootSnapshot(at: url),
              snapshot.isDirectory,
              try isSafeDerivedRoot(url),
              let enumerator = fileManager.enumerator(
                  at: url,
                  includingPropertiesForKeys: Array(resourceKeys),
                  options: [.skipsPackageDescendants],
                  errorHandler: { _, error in
                      faultState.record(Fault(error: error as NSError))
                      return false
                  }
              ) else {
            throw Fault.unsupported
        }
        let state = State(
            root: url,
            snapshot: snapshot,
            enumerator: enumerator,
            faultState: faultState,
            position: 0
        )
        states[root.id] = state
        return state
    }

    private func cursorIsValid(_ cursor: ScanCursor?, state: State) -> Bool {
        cursor?.position == state.position || (cursor == nil && state.position == 0)
    }

    private func observe(_ url: URL, root: DeclaredRoot, state: State) throws -> FileObservation {
        let values = try resourceValues(url)
        guard let itemDevice = try device(at: url) else {
            throw Fault.corrupt
        }
        let boundaries = boundaryEvidence(url: url, values: values, itemDevice: itemDevice, state: state)
        if stopsDescent(boundaries) || boundaries.protectedRoot != .observed(false) {
            state.enumerator.skipDescendants()
        }
        return try observation(
            for: url,
            root: root,
            state: state,
            values: values,
            device: itemDevice,
            boundaries: boundaries
        )
    }

    private func observation(
        for url: URL,
        root: DeclaredRoot,
        state: State,
        values: GeneralMacResourceValues,
        device: UInt64,
        boundaries: BoundaryEvidence
    ) throws -> FileObservation {
        guard url.path.hasPrefix(state.root.path + "/") else {
            throw Fault.unsupported
        }
        let components = url.path.dropFirst(state.root.path.count + 1)
            .split(separator: "/")
            .map(String.init)
        let locator = try RelativeLocator(rootID: root.id, components: components)
        guard locator.components.count <= GeneralMacScanLimits.current.maximumDepth else {
            throw Fault.unsupported
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let identity = identityEvidence(attributes: attributes, device: device)
        let sizes = try sizeEvidence(values)
        let modification = Self.modificationEvidence(values.contentModificationDate)
        return FileObservation(
            rootID: root.id,
            locator: locator,
            resourceIdentity: identity,
            sizes: sizes,
            modification: modification,
            fileKind: fileKind(values),
            volume: .observed(try VolumeID("device:\(device)")),
            linkCount: linkCountEvidence(attributes: attributes),
            boundaries: boundaries
        )
    }

    private func boundaryEvidence(
        url: URL,
        values: GeneralMacResourceValues,
        itemDevice: UInt64,
        state: State
    ) -> BoundaryEvidence {
        let mount = itemDevice != state.snapshot.device
            ? EvidenceValue<Bool>.observed(true)
            : boolEvidence(values.isMountTrigger)
        let symlink = boolEvidence(values.isSymbolicLink)
        let alias = boolEvidence(values.isAliasFile)
        let package = boolEvidence(values.isPackage)
        let externalVolume: EvidenceValue<Bool> = values.volumeIsInternal
            .map { .observed(!$0) } ?? .unavailable
        let trustedContainment = isTrustedContained(url, in: state)
            && [symlink, alias, package, mount, externalVolume].allSatisfy { $0 == .observed(false) }
        let scopeBoundary: EvidenceValue<Bool> = trustedContainment ? .observed(false) : .unavailable
        return .init(
            symlink: symlink,
            alias: alias,
            package: package,
            mount: mount,
            protectedRoot: scopeBoundary,
            homeBoundary: scopeBoundary,
            externalVolume: externalVolume
        )
    }

    private func isTrustedContained(_ url: URL, in state: State) -> Bool {
        url.path.hasPrefix(state.root.path + "/")
            && url.resolvingSymlinksInPath().path == url.path
            && state.root.resolvingSymlinksInPath().path == state.root.path
    }

    private func identityEvidence(
        attributes: [FileAttributeKey: Any],
        device: UInt64
    ) -> EvidenceValue<FileIdentityEvidence> {
        guard let node = numericValue(attributes[.systemFileNumber]) else {
            return .unavailable
        }
        return .observed(.init(device: device, node: node))
    }

    private func linkCountEvidence(attributes: [FileAttributeKey: Any]) -> EvidenceValue<UInt64> {
        guard let count = numericValue(attributes[.referenceCount]), count > 0 else {
            return .unknown
        }
        return .observed(count)
    }

    private func sizeEvidence(_ values: GeneralMacResourceValues) throws -> SizeEvidence {
        try .init(
            logicalBytes: values.fileSize.map { .observed(Int64($0)) } ?? .unavailable,
            allocatedBytes: (values.totalFileAllocatedSize ?? values.fileAllocatedSize)
                .map { .observed(Int64($0)) } ?? .unavailable
        )
    }

    static func modificationEvidence(_ date: Date?) -> EvidenceValue<FileModificationInstant> {
        guard let date else {
            return .unavailable
        }
        let nanoseconds = date.timeIntervalSince1970 * 1_000_000_000
        let safelyConvertibleMagnitude = 9_000_000_000_000_000_000.0
        guard nanoseconds.isFinite,
              nanoseconds > -safelyConvertibleMagnitude,
              nanoseconds < safelyConvertibleMagnitude else {
            return .unavailable
        }
        return .observed(.init(unixNanoseconds: Int64(nanoseconds)))
    }

    private func device(at url: URL) throws -> UInt64? {
        guard let attributes = try attributes(at: url) else {
            return nil
        }
        return numericValue(attributes[.systemNumber])
    }

    private func rootSnapshot(at url: URL) throws -> RootSnapshot? {
        guard let attributes = try attributes(at: url),
              let device = numericValue(attributes[.systemNumber]),
              let node = numericValue(attributes[.systemFileNumber]) else {
            return nil
        }
        return .init(
            device: device,
            node: node,
            isDirectory: (attributes[.type] as? FileAttributeType) == .typeDirectory
        )
    }

    private func isSafeDerivedRoot(_ url: URL) throws -> Bool {
        let values = try resourceValues(url)
        guard let symlink = values.isSymbolicLink,
              let alias = values.isAliasFile,
              let package = values.isPackage,
              let mount = values.isMountTrigger,
              let internalVolume = values.volumeIsInternal else {
            return false
        }
        return !symlink && !alias && !package && !mount && internalVolume
    }

    private func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError {
            throw error
        }
    }

    private func fileKind(_ values: GeneralMacResourceValues) -> FileKind {
        if values.isSymbolicLink == true { return .symbolicLink }
        if values.isPackage == true { return .package }
        if values.isDirectory == true { return .directory }
        if values.isRegularFile == true { return .regularFile }
        return .other
    }
}

private extension GeneralMacRootAnchors {
    static func trusted(_ fileManager: FileManager) -> GeneralMacRootAnchors {
        .init(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            temporaryDirectory: fileManager.temporaryDirectory.resolvingSymlinksInPath()
        )
    }
}

private final class EnumerationFaultState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Fault?

    var value: Fault? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ fault: Fault) {
        lock.lock()
        defer { lock.unlock() }
        if stored == nil { stored = fault }
    }
}

private enum Fault: Error {
    case corrupt
    case denied
    case unsupported

    init(error: NSError) {
        let posixCode = Int32(exactly: error.code).flatMap(POSIXErrorCode.init(rawValue:))
        let isPOSIXDenied = error.domain == NSPOSIXErrorDomain
            && (posixCode == .EACCES || posixCode == .EPERM)
        let isCocoaDenied = error.domain == NSCocoaErrorDomain
            && (error.code == CocoaError.fileReadNoPermission.rawValue
                || error.code == CocoaError.fileWriteNoPermission.rawValue)
        let isMissing = error.domain == NSCocoaErrorDomain
            && (error.code == CocoaError.fileNoSuchFile.rawValue
                || error.code == CocoaError.fileReadNoSuchFile.rawValue)
        if isPOSIXDenied || isCocoaDenied {
            self = .denied
        } else if isMissing {
            self = .unsupported
        } else {
            self = .corrupt
        }
    }

    var outcome: ScanOutcome {
        switch self {
        case .corrupt:
            return .corruptMetadata
        case .denied:
            return .permissionDenied
        case .unsupported:
            return .unsupportedLayout
        }
    }
}

private let resourceKeys: Set<URLResourceKey> = [
    .contentModificationDateKey,
    .fileAllocatedSizeKey,
    .fileSizeKey,
    .isAliasFileKey,
    .isDirectoryKey,
    .isMountTriggerKey,
    .isPackageKey,
    .isRegularFileKey,
    .isSymbolicLinkKey,
    .totalFileAllocatedSizeKey,
    .volumeIsInternalKey,
]

private func isValidAnchor(_ url: URL, manager: FileManager) -> Bool {
    guard url.path != "/", url.resolvingSymlinksInPath().path == url.path else {
        return false
    }
    var isDirectory = ObjCBool(false)
    return manager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
}

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

private func boolEvidence(_ value: Bool?) -> EvidenceValue<Bool> {
    value.map(EvidenceValue.observed) ?? .unavailable
}

private func stopsDescent(_ boundaries: BoundaryEvidence) -> Bool {
    boundaries.symlink == .observed(true)
        || boundaries.alias == .observed(true)
        || boundaries.package == .observed(true)
        || boundaries.mount == .observed(true)
        || boundaries.protectedRoot == .observed(true)
        || boundaries.homeBoundary == .observed(true)
        || boundaries.externalVolume == .observed(true)
}
