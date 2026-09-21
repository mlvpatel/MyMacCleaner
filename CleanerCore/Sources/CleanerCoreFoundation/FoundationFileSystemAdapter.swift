import CleanerCore
import Foundation

public actor FoundationFileSystemAdapter: FileSystemPort {
    private let declaredRoots: [DeclaredRootID: URL]
    private let fileManager: FileManager

    public init(declaredRoots: [DeclaredRootID: URL], fileManager: FileManager) throws {
        guard !declaredRoots.isEmpty else { throw ScanValidationError.emptyDeclaredRoots }

        var normalizedRoots: [DeclaredRootID: URL] = [:]
        for (rootID, url) in declaredRoots {
            normalizedRoots[rootID] = url.standardizedFileURL
        }
        self.declaredRoots = normalizedRoots
        self.fileManager = fileManager
    }

    public func nextObservation(after cursor: ScanCursor?, in root: DeclaredRoot) async -> FileSystemStep {
        do {
            guard let rootURL = declaredRoots[root.id] else {
                return .terminal(.unsupportedLayout)
            }
            guard isExistingDirectory(rootURL) else {
                return .terminal(.corruptMetadata)
            }

            var currentIndex: UInt = 0
            guard let candidate = try candidate(
                at: cursor?.position ?? 0,
                under: rootURL,
                currentIndex: &currentIndex
            ) else {
                return .terminal(.complete)
            }

            return .observation(try observation(for: candidate, rootID: root.id, rootURL: rootURL))
        } catch let error as FoundationAdapterFault {
            return .terminal(error.outcome)
        } catch {
            return .terminal(.corruptMetadata)
        }
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func candidate(
        at targetIndex: UInt,
        under directoryURL: URL,
        currentIndex: inout UInt
    ) throws -> URL? {
        let children = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        )
        for child in children.sorted(by: { $0.path < $1.path }) {
            if currentIndex == targetIndex {
                return child.standardizedFileURL
            }
            currentIndex += 1
            if try shouldDescend(into: child) {
                if let nested = try candidate(
                    at: targetIndex,
                    under: child,
                    currentIndex: &currentIndex
                ) {
                    return nested
                }
            }
        }
        return nil
    }

    private func shouldDescend(into url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: Self.resourceKeys)
        return values.isDirectory == true
            && values.isSymbolicLink != true
            && values.isAliasFile != true
            && values.isPackage != true
            && values.isMountTrigger != true
    }

    private func observation(
        for url: URL,
        rootID: DeclaredRootID,
        rootURL: URL
    ) throws -> FileObservation {
        let normalizedURL = url.standardizedFileURL
        let locator = try relativeLocator(for: normalizedURL, rootID: rootID, rootURL: rootURL)
        let values = try normalizedURL.resourceValues(forKeys: Self.resourceKeys)
        let attributes = try fileManager.attributesOfItem(atPath: normalizedURL.path)
        let device = try numericAttribute(.systemNumber, in: attributes)

        return try FileObservation(
            rootID: rootID,
            locator: locator,
            resourceIdentity: try identityEvidence(from: attributes, device: device),
            sizes: sizeEvidence(from: values, attributes: attributes),
            modification: Self.modificationEvidence(from: values.contentModificationDate),
            fileKind: fileKind(from: values),
            volume: volumeEvidence(from: device),
            linkCount: try linkCountEvidence(from: attributes),
            boundaries: boundaryEvidence(from: values)
        )
    }

    private func relativeLocator(
        for url: URL,
        rootID: DeclaredRootID,
        rootURL: URL
    ) throws -> RelativeLocator {
        let rootPath = rootURL.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath != rootPath, itemPath.hasPrefix(rootPath + "/") else {
            throw FoundationAdapterFault.unsupportedLayout
        }

        let relativePath = String(itemPath.dropFirst(rootPath.count + 1))
        let components = relativePath.split(separator: "/").map(String.init)
        return try RelativeLocator(rootID: rootID, components: components)
    }

    private func identityEvidence(
        from attributes: [FileAttributeKey: Any],
        device: UInt64?
    ) throws -> EvidenceValue<FileIdentityEvidence> {
        guard let device else { return .unavailable }
        guard let node = try numericAttribute(.systemFileNumber, in: attributes) else {
            return .unavailable
        }
        return .observed(.init(device: device, node: node))
    }

    private func sizeEvidence(
        from values: URLResourceValues,
        attributes: [FileAttributeKey: Any]
    ) throws -> SizeEvidence {
        try SizeEvidence(
            logicalBytes: try logicalSizeEvidence(from: values, attributes: attributes),
            allocatedBytes: integerEvidence(values.totalFileAllocatedSize ?? values.fileAllocatedSize)
        )
    }

    private func logicalSizeEvidence(
        from values: URLResourceValues,
        attributes: [FileAttributeKey: Any]
    ) throws -> EvidenceValue<Int64> {
        if let fileSize = values.fileSize {
            return integerEvidence(fileSize)
        }
        guard let rawValue = attributes[.size] else {
            return .unavailable
        }
        guard let logicalSize = Self.int64(from: rawValue) else {
            throw FoundationAdapterFault.corruptMetadata
        }
        return .observed(logicalSize)
    }

    static func modificationEvidence(
        from modificationDate: Date?
    ) -> EvidenceValue<FileModificationInstant> {
        guard let modificationDate else {
            return .unavailable
        }
        let nanoseconds = modificationDate.timeIntervalSince1970 * 1_000_000_000
        let safelyConvertibleMagnitude = 9_000_000_000_000_000_000.0
        guard nanoseconds.isFinite,
              nanoseconds > -safelyConvertibleMagnitude,
              nanoseconds < safelyConvertibleMagnitude else {
            return .unavailable
        }
        return .observed(.init(unixNanoseconds: Int64(nanoseconds)))
    }

    private func fileKind(from values: URLResourceValues) -> FileKind {
        if values.isSymbolicLink == true {
            return .symbolicLink
        }
        if values.isPackage == true {
            return .package
        }
        if values.isDirectory == true {
            return .directory
        }
        if values.isRegularFile == true {
            return .regularFile
        }
        return .other
    }

    private func volumeEvidence(from device: UInt64?) throws -> EvidenceValue<VolumeID> {
        guard let device else { return .unavailable }
        return .observed(try VolumeID("device:\(device)"))
    }

    private func boundaryEvidence(from values: URLResourceValues) -> BoundaryEvidence {
        BoundaryEvidence(
            symlink: booleanEvidence(values.isSymbolicLink),
            alias: booleanEvidence(values.isAliasFile),
            package: booleanEvidence(values.isPackage),
            mount: booleanEvidence(values.isMountTrigger),
            protectedRoot: .unavailable,
            homeBoundary: .unavailable,
            externalVolume: values.volumeIsInternal.map { .observed(!$0) } ?? .unavailable
        )
    }

    private func numericAttribute(
        _ key: FileAttributeKey,
        in attributes: [FileAttributeKey: Any]
    ) throws -> UInt64? {
        guard let rawValue = attributes[key] else {
            return nil
        }
        guard let number = Self.uint64(from: rawValue) else {
            throw FoundationAdapterFault.corruptMetadata
        }
        return number
    }

    private func integerEvidence(_ value: Int?) -> EvidenceValue<Int64> {
        guard let value else { return .unavailable }
        return .observed(Int64(value))
    }

    private func linkCountEvidence(from attributes: [FileAttributeKey: Any]) throws -> EvidenceValue<UInt64> {
        guard let count = try numericAttribute(.referenceCount, in: attributes),
              count > 0
        else {
            return .unknown
        }
        return .observed(count)
    }

    private func booleanEvidence(_ value: Bool?) -> EvidenceValue<Bool> {
        value.map(EvidenceValue.observed) ?? .unavailable
    }

    private static func int64(from value: Any) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? Int64 {
            return value
        }
        return nil
    }

    private static func uint64(from value: Any) -> UInt64? {
        if let number = value as? NSNumber {
            guard number.int64Value >= 0 else {
                return nil
            }
            return number.uint64Value
        }
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? UInt {
            return UInt64(value)
        }
        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }
        return nil
    }

    private static let resourceKeys: Set<URLResourceKey> = [
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
}

private enum FoundationAdapterFault: Error {
    case corruptMetadata
    case unsupportedLayout

    var outcome: ScanOutcome {
        switch self {
        case .corruptMetadata:
            return .corruptMetadata
        case .unsupportedLayout:
            return .unsupportedLayout
        }
    }
}
