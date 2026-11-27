import Foundation

/// The closed set of fixed, read-only local commands the app may run, one per entry in
/// `scripts/read-only-process-allowlist.txt`. No caller supplies an executable or an argument.
enum ReadOnlyCommand: Sendable {
    case backgroundItems
    case launchServices
    case tcpPorts
    case rootDiskInfo
    case openFiles

    // SAFETY-AUDIT: the only executables and arguments in the app. SC-PROCESS-IDENTITY compares
    // each line below to the allowlist, so keep one case per line and no other literal paths here.
    fileprivate var invocation: (executable: String, arguments: [String]) {
        switch self {
        case .backgroundItems: ("/usr/bin/sfltool", ["dumpbtm"])
        case .launchServices: ("/bin/launchctl", ["list"])
        case .tcpPorts: ("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN,ESTABLISHED", "-n", "-P"])
        case .rootDiskInfo: ("/usr/sbin/diskutil", ["info", "/"])
        case .openFiles: ("/usr/sbin/lsof", ["-Fn", "-n", "-P", "-w", "-b"])
        }
    }

    /// `lsof -iTCP` exits 1 with no output when no connection matches, which is an empty listing.
    /// The open-file listing has no filter and always includes lsof's own files, so empty output
    /// there is a failure and stays unavailable (the open-file guard fails closed).
    var shouldAcceptEmptyExitOne: Bool {
        self == .tcpPorts
    }
}

/// Runs a `ReadOnlyCommand` without ever hanging its caller. Standard output is drained to the end
/// before waiting, and the child is stopped when the deadline passes or the calling task is
/// cancelled. Every failure comes back as `nil` ("unavailable"), never as a throw. A command that
/// sets `shouldAcceptEmptyExitOne` reads exit status 1 with empty output as an empty result.
enum ReadOnlyProcess {
    /// Long enough for a full `lsof` listing on a busy Mac; a stalled tool is stopped after this.
    static let timeout: TimeInterval = 10

    static func run(_ command: ReadOnlyCommand) async -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.invocation.executable)
        process.arguments = command.invocation.arguments
        return await run(process, timeout: timeout, shouldAcceptEmptyExitOne: command.shouldAcceptEmptyExitOne)
    }

    /// Runs an already configured child. Internal so tests can pass a fixed test-only child. App
    /// code cannot get a `Process` any other way: SC-UNLISTED-PROCESS rejects one anywhere under
    /// `MyMacCleaner/` except this file.
    static func run(
        _ process: Process,
        timeout: TimeInterval,
        shouldAcceptEmptyExitOne: Bool = false
    ) async -> Data? {
        let child = ReadOnlyChild(process, shouldAcceptEmptyExitOne: shouldAcceptEmptyExitOne)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                child.start(timeout: timeout) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            child.stop()
        }
    }
}

/// One child run. The result is delivered exactly once: the output after a clean exit (or an empty
/// result after an allowed empty exit 1), or nil when the child could not start, exited non-zero
/// otherwise, or was stopped. A stop can arrive from the deadline
/// or a cancelled task at any moment, so launch, stop and delivery share one lock, and a stop that
/// comes before the launch prevents it.
private final class ReadOnlyChild: @unchecked Sendable {
    private let process: Process
    private let shouldAcceptEmptyExitOne: Bool
    private let output = Pipe()
    private let lock = NSLock()
    private var isStopped = false
    private var finish: (@Sendable (Data?) -> Void)?

    init(_ process: Process, shouldAcceptEmptyExitOne: Bool) {
        self.process = process
        self.shouldAcceptEmptyExitOne = shouldAcceptEmptyExitOne
    }

    func start(timeout: TimeInterval, finish: @escaping @Sendable (Data?) -> Void) {
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let isLaunched = lock.withLock {
            guard !isStopped, (try? process.run()) != nil else { return false }
            self.finish = finish
            return true
        }
        guard isLaunched else { return finish(nil) }

        // One dedicated thread per child drains it, watches its exit and enforces the deadline.
        // Work queued on the shared dispatch pool can wait for a free worker on a busy process,
        // which once held a finished command until its deadline.
        let deadline = Date().addingTimeInterval(timeout)
        let worker = Thread { [self] in watch(until: deadline) }
        worker.qualityOfService = .userInitiated
        worker.start()
    }

    private func watch(until deadline: Date) {
        // Drain while the child runs: output larger than the pipe buffer would block it.
        guard let data = drain(until: deadline) else { return stop() }
        var exit = exitStatus()
        while exit == .running {
            guard Date() < deadline else { return stop() }
            usleep(Self.pollMicroseconds)
            exit = exitStatus()
        }
        deliver(result(of: data, exit: exit))
    }

    /// Reads until end of file, or until the child has exited and everything it wrote is read.
    /// Another process can inherit this pipe's write end and hold end of file back after the
    /// child exits, so the child's exit, not end of file, ends the read.
    // ponytail: polls every 10 ms while the pipe is empty; a dispatch read source if that matters.
    /// nil when the deadline passes first.
    private func drain(until deadline: Date) -> Data? {
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: Self.readChunkBytes)
        while true {
            // Checked before the read, so output written before the exit is still read.
            let hasExited = exitStatus() != .running
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                continue
            }
            if count == 0 { break }
            if errno == EINTR { continue }
            guard errno == EAGAIN, !hasExited else { break }
            guard Date() < deadline else { return nil }
            usleep(Self.pollMicroseconds)
        }
        return data
    }

    private static let readChunkBytes = 65_536
    private static let pollMicroseconds: useconds_t = 10_000

    private enum ChildExit: Equatable {
        case running
        case exited(Int32)
        case signalled
        /// Foundation collected the exit first; its own termination values then hold it.
        case collectedByFoundation
    }

    /// Asks the kernel how the child ended without collecting it (`WNOWAIT`), so Foundation still
    /// reaps it. Foundation's own `isRunning` and `waitUntilExit()` can report an exit seconds late
    /// when the process is busy, which once ran a finished command into its deadline.
    private func exitStatus() -> ChildExit {
        var info = siginfo_t()
        let options = WEXITED | WNOWAIT | WNOHANG
        while waitid(P_PID, id_t(process.processIdentifier), &info, options) != 0 {
            if errno == EINTR { continue }
            return .collectedByFoundation
        }
        guard info.si_pid != 0 else { return .running }
        return info.si_code == CLD_EXITED ? .exited(info.si_status) : .signalled
    }

    private func result(of data: Data, exit: ChildExit) -> Data? {
        let status: Int32
        switch exit {
        case .exited(let code): status = code
        case .collectedByFoundation:
            process.waitUntilExit()
            guard process.terminationReason == .exit else { return nil }
            status = process.terminationStatus
        case .running, .signalled: return nil
        }
        switch status {
        case 0: return data
        case 1 where shouldAcceptEmptyExitOne && data.isEmpty: return data
        default: return nil
        }
    }

    /// Reports unavailable at once, even if the child is slow to die.
    func stop() {
        lock.withLock {
            isStopped = true
            guard process.isRunning else { return }
            process.terminate()
        }
        deliver(nil)
    }

    private func deliver(_ result: Data?) {
        let pending = lock.withLock {
            defer { finish = nil }
            return finish
        }
        pending?(result)
    }
}
