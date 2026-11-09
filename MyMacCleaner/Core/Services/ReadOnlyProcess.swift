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

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.stop()
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Drain before waiting: output larger than the pipe buffer would block the child.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            deliver(result(of: data))
        }
    }

    private func result(of data: Data) -> Data? {
        guard process.terminationReason == .exit else { return nil }
        switch process.terminationStatus {
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
