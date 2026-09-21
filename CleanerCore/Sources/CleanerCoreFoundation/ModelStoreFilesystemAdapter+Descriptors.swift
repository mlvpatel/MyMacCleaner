import CleanerCore
import Foundation

// MARK: - Descriptor Reads and stat Helpers

extension ModelStoreFilesystemAdapter {
    func descriptorRead(
        locator: ModelStoreLocator,
        rootID: DeclaredRootID,
        rootURL: URL,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>,
        maximumBytes: Int
    ) throws -> Data {
        guard maximumBytes > 0,
              maximumBytes <= ModelStoreParserLimits.maximumAllowedRefBytes
        else {
            throw ModelStoreDescriptorReadError.oversized
        }
        let parent = try openParentDirectory(rootID: rootID, rootURL: rootURL, locator: locator)
        defer { close(parent.fd) }
        let fileFD = openat(parent.fd, parent.leaf, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        let openError = errno
        guard fileFD >= 0 else {
            throw Self.isPermissionDeniedErrno(openError) ? ModelStoreDescriptorReadError.denied : ModelStoreDescriptorReadError.changed
        }
        defer { close(fileFD) }

        let before = try fileStat(fileFD)
        guard isRegularFile(before),
              identity(from: before).map(EvidenceValue.observed) == expectedIdentity
        else {
            throw ModelStoreDescriptorReadError.changed
        }
        guard before.st_size >= 0,
              before.st_size <= off_t(maximumBytes)
        else {
            throw ModelStoreDescriptorReadError.oversized
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(maximumBytes + 1, 8192))
        while true {
            let count = read(fileFD, &buffer, buffer.count)
            let readError = errno
            if count < 0 {
                throw Self.isPermissionDeniedErrno(readError) ? ModelStoreDescriptorReadError.denied : ModelStoreDescriptorReadError.changed
            }
            if count == 0 { break }
            data.append(buffer, count: count)
            if data.count > maximumBytes { throw ModelStoreDescriptorReadError.oversized }
        }

        let after = try fileStat(fileFD)
        guard sameStableFile(before, after) else { throw ModelStoreDescriptorReadError.changed }
        return data
    }

    func descriptorReadLink(
        locator: ModelStoreLocator,
        rootID: DeclaredRootID,
        rootURL: URL,
        expectedIdentity: EvidenceValue<FileIdentityEvidence>
    ) throws -> String {
        let parent = try openParentDirectory(rootID: rootID, rootURL: rootURL, locator: locator)
        defer { close(parent.fd) }
        let before = try linkStat(parentFD: parent.fd, leaf: parent.leaf)
        guard isSymbolicLink(before),
              identity(from: before).map(EvidenceValue.observed) == expectedIdentity
        else {
            throw ModelStoreDescriptorReadError.changed
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = readlinkat(parent.fd, parent.leaf, &buffer, buffer.count)
        let readLinkError = errno
        guard count >= 0 else {
            throw Self.isPermissionDeniedErrno(readLinkError) ? ModelStoreDescriptorReadError.denied : ModelStoreDescriptorReadError.changed
        }
        guard count < buffer.count else { throw ModelStoreDescriptorReadError.oversized }
        let after = try linkStat(parentFD: parent.fd, leaf: parent.leaf)
        guard sameIdentity(before, after) else { throw ModelStoreDescriptorReadError.changed }
        guard let destination = String(bytes: buffer.prefix(Int(count)), encoding: .utf8) else {
            throw ModelStoreDescriptorReadError.changed
        }
        return destination
    }

    func openParentDirectory(
        rootID: DeclaredRootID,
        rootURL: URL,
        locator: ModelStoreLocator
    ) throws -> (fd: Int32, leaf: String) {
        guard let leaf = locator.components.last else { throw ModelStoreDescriptorReadError.denied }
        var currentFD = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        let rootOpenError = errno
        guard currentFD >= 0 else {
            throw Self.isPermissionDeniedErrno(rootOpenError) ? ModelStoreDescriptorReadError.denied : ModelStoreDescriptorReadError.changed
        }
        do {
            try validateRootSnapshot(rootID: rootID, rootFD: currentFD)
        } catch {
            close(currentFD)
            throw error
        }
        for component in locator.components.dropLast() {
            let nextFD = openat(currentFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let openError = errno
            close(currentFD)
            guard nextFD >= 0 else {
                throw Self.isPermissionDeniedErrno(openError) ? ModelStoreDescriptorReadError.denied : ModelStoreDescriptorReadError.changed
            }
            currentFD = nextFD
        }
        return (currentFD, leaf)
    }

    func descriptorTargetMetadata(
        locator: ModelStoreLocator,
        rootID: DeclaredRootID,
        rootURL: URL
    ) -> (
        exists: Bool,
        volume: EvidenceValue<VolumeID>,
        kind: EvidenceValue<ModelStoreEntryKind>,
        diagnostic: ModelStoreDiagnosticCode?
    ) {
        do {
            let parent = try openParentDirectory(rootID: rootID, rootURL: rootURL, locator: locator)
            defer { close(parent.fd) }
            let value = try linkStat(parentFD: parent.fd, leaf: parent.leaf)
            return (
                true,
                volume(from: value).map(EvidenceValue.observed) ?? .unavailable,
                .observed(kind(from: value)),
                nil
            )
        } catch ModelStoreDescriptorReadError.denied {
            return (false, .unavailable, .unavailable, .permissionDenied)
        } catch ModelStoreDescriptorReadError.changed {
            return (false, .unavailable, .unavailable, .rootChanged)
        } catch {
            return (false, .unavailable, .unavailable, nil)
        }
    }

    func targetLocator(
        destination: String,
        linkLocator: ModelStoreLocator,
        rootURL: URL
    ) throws -> ModelStoreLocator {
        let rawComponents: [String]
        if destination.hasPrefix("/") {
            let destinationURL = URL(fileURLWithPath: destination).standardizedFileURL
            return try relativeLocator(for: destinationURL, rootURL: rootURL)
        } else {
            rawComponents = Array(linkLocator.components.dropLast())
                + destination.split(separator: "/").map(String.init)
        }
        var normalized: [String] = []
        for component in rawComponents {
            if component.isEmpty || component == "." {
                continue
            }
            if component == ".." {
                guard !normalized.isEmpty else { throw EvidenceValidationError.invalidRelativeLocator }
                normalized.removeLast()
            } else {
                normalized.append(component)
            }
        }
        return try .init(normalized)
    }

    func validateRootSnapshot(rootID: DeclaredRootID, rootFD: Int32) throws {
        guard let snapshot = rootSnapshots[rootID] else { throw ModelStoreDescriptorReadError.changed }
        let value = try fileStat(rootFD)
        guard identity(from: value) == snapshot.identity,
              volume(from: value) == snapshot.volume
        else {
            throw ModelStoreDescriptorReadError.changed
        }
    }

    func fileStat(_ fd: Int32) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else {
            let statError = errno
            throw Self.isPermissionDeniedErrno(statError) ? ModelStoreDescriptorReadError.denied : ModelStoreDescriptorReadError.changed
        }
        return value
    }

    func linkStat(parentFD: Int32, leaf: String) throws -> stat {
        var value = stat()
        guard fstatat(parentFD, leaf, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            let statError = errno
            throw Self.isPermissionDeniedErrno(statError) ? ModelStoreDescriptorReadError.denied : ModelStoreDescriptorReadError.changed
        }
        return value
    }

    func isRegularFile(_ value: stat) -> Bool {
        (value.st_mode & S_IFMT) == S_IFREG
    }

    func isSymbolicLink(_ value: stat) -> Bool {
        (value.st_mode & S_IFMT) == S_IFLNK
    }

    func identity(from value: stat) -> FileIdentityEvidence? {
        .init(device: UInt64(value.st_dev), node: UInt64(value.st_ino))
    }

    func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_mode == rhs.st_mode
    }

    func sameStableFile(_ lhs: stat, _ rhs: stat) -> Bool {
        sameIdentity(lhs, rhs)
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    func volume(from value: stat) -> VolumeID? {
        do {
            return try VolumeID("device:\(UInt64(value.st_dev))")
        } catch {
            return nil
        }
    }

    func kind(from value: stat) -> ModelStoreEntryKind {
        if isRegularFile(value) { return .regularFile }
        if isSymbolicLink(value) { return .symbolicLink }
        return .directory
    }

    static func enumerationFault(for error: Error) -> ModelStoreDiagnosticCode {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           isPermissionDeniedErrno(Int32(nsError.code)) {
            return .permissionDenied
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileReadNoPermission.rawValue {
            return .permissionDenied
        }
        return .unknownLayout
    }

    static func isPermissionDeniedErrno(_ value: Int32) -> Bool {
        value == EACCES || value == EPERM
    }

    func volumeEvidence(for url: URL) -> VolumeID? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            return nil
        }
        let device: UInt64?
        do {
            device = try numericAttribute(.systemNumber, in: attributes)
        } catch {
            return nil
        }
        guard let device else { return nil }
        do {
            return try VolumeID("device:\(device)")
        } catch {
            return nil
        }
    }

    func revalidationFault(
        for root: ModelStoreRoot,
        rootURL: URL
    ) -> ModelStoreDiagnosticCode? {
        guard let snapshot = rootSnapshots[root.identity.rootID] else {
            return .rootChanged
        }
        guard volumeEvidence(for: rootURL) == snapshot.volume else {
            return .volumeChanged
        }
        guard let identity = observedIdentity(for: rootURL),
              identity == snapshot.identity
        else {
            return .rootChanged
        }
        return nil
    }

    func kindEvidence(for url: URL) -> EvidenceValue<ModelStoreEntryKind> {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: Self.resourceKeys)
        } catch {
            return .unavailable
        }
        if values.isSymbolicLink == true {
            return .observed(.symbolicLink)
        }
        if values.isDirectory == true {
            return .observed(.directory)
        }
        if values.isRegularFile == true {
            return .observed(.regularFile)
        }
        return .unavailable
    }

    func numericAttribute(
        _ key: FileAttributeKey,
        in attributes: [FileAttributeKey: Any]
    ) throws -> UInt64? {
        guard let rawValue = attributes[key] else {
            return nil
        }
        if let number = rawValue as? NSNumber, number.int64Value >= 0 {
            return number.uint64Value
        }
        if let value = rawValue as? UInt64 {
            return value
        }
        if let value = rawValue as? Int, value >= 0 {
            return UInt64(value)
        }
        return nil
    }
}
