import CleanerCore
import Darwin
import Foundation

public struct DarwinReceiptPublisher: Sendable {
    public var publish: @Sendable (_ data: Data, _ directory: URL, _ fileName: String) -> Result<Void, ReceiptPersistenceError>
    public var tryLock: @Sendable (_ lockFile: URL) -> Result<Int32, ReceiptPersistenceError>
    public var unlock: @Sendable (_ fd: Int32) -> Void
    public var ownerIsCurrentUser: @Sendable (_ path: String) -> Bool
    public var isSymlink: @Sendable (_ path: String) -> Bool
    public var syncDirectory: @Sendable (_ directory: URL) -> Result<Void, ReceiptPersistenceError>

    public static let native = DarwinReceiptPublisher(
        publish: nativePublish,
        tryLock: nativeTryLock,
        unlock: nativeUnlock,
        ownerIsCurrentUser: nativeOwnerIsCurrentUser,
        isSymlink: nativeIsSymlink,
        syncDirectory: nativeSyncDirectory
    )
}

public struct DarwinReceiptLease: ReceiptLeasePort, @unchecked Sendable {
    private let lockFile: URL
    private let publisher: DarwinReceiptPublisher

    public init(lockFile: URL, publisher: DarwinReceiptPublisher = .native) {
        self.lockFile = lockFile
        self.publisher = publisher
    }

    public func withExclusiveAccess<T: Sendable>(
        _ work: @Sendable () async -> Result<T, ReceiptPersistenceError>
    ) async -> Result<T, ReceiptPersistenceError> {
        switch publisher.tryLock(lockFile) {
        case let .failure(error):
            return .failure(error)
        case let .success(fd):
            defer { publisher.unlock(fd) }
            return await work()
        }
    }
}

private func nativeIsSymlink(_ path: String) -> Bool {
    var status = stat()
    guard lstat(path, &status) == 0 else { return false }
    return (status.st_mode & S_IFMT) == S_IFLNK
}

private func nativeOwnerIsCurrentUser(_ path: String) -> Bool {
    var status = stat()
    guard lstat(path, &status) == 0 else { return false }
    return status.st_uid == getuid()
}

private func nativeTryLock(_ lockFile: URL) -> Result<Int32, ReceiptPersistenceError> {
    let path = lockFile.path
    let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return .failure(.leaseFailed) }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return .failure(.historyBusy)
    }
    return .success(fd)
}

private func nativeUnlock(_ fd: Int32) {
    _ = flock(fd, LOCK_UN)
    close(fd)
}

private func nativeSyncDirectory(_ directory: URL) -> Result<Void, ReceiptPersistenceError> {
    let dirfd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard dirfd >= 0 else { return .failure(.directorySyncFailed) }
    if fcntl(dirfd, F_FULLFSYNC) != 0 {
        close(dirfd)
        return .failure(.directorySyncFailed)
    }
    close(dirfd)
    return .success(())
}

private func nativePublish(
    data: Data,
    directory: URL,
    fileName: String
) -> Result<Void, ReceiptPersistenceError> {
    let unique = "\(getpid()).\(UInt64.random(in: 0...UInt64.max))"
    let temporary = directory.appendingPathComponent(".\(fileName).\(unique).tmp")
    let destination = directory.appendingPathComponent(fileName)
    let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return .failure(.openFailed) }
    let written: Bool = data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return false }
        var remaining = buffer.count
        var offset = 0
        while remaining > 0 {
            let result = write(fd, base.advanced(by: offset), remaining)
            if result <= 0 { return false }
            remaining -= result
            offset += result
        }
        return true
    }
    guard written else {
        close(fd)
        unlink(temporary.path)
        return .failure(.writeFailed)
    }
    if fcntl(fd, F_FULLFSYNC) != 0 {
        close(fd)
        unlink(temporary.path)
        return .failure(.fullfsyncFailed)
    }
    close(fd)
    guard rename(temporary.path, destination.path) == 0 else {
        unlink(temporary.path)
        return .failure(.renameFailed)
    }
    let dirfd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard dirfd >= 0 else { return .failure(.directorySyncFailed) }
    if fcntl(dirfd, F_FULLFSYNC) != 0 {
        close(dirfd)
        return .failure(.directorySyncFailed)
    }
    close(dirfd)
    return .success(())
}
