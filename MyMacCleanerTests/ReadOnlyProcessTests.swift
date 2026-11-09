import Testing
import Foundation
@testable import MyMacCleaner

/// The runner drains past the pipe buffer, stops a child that outlives its deadline, and stops it
/// when the calling task is cancelled. These tests pass fixed test-only children to the internal
/// engine. The test target is not shipped and is outside the app's process gate, so nothing here
/// is added to the allowlist.
@Suite("Read-only process runner")
struct ReadOnlyProcessTests {
    /// Four times the 64 KiB a macOS pipe holds.
    private static let largeOutputBytes = 262_144

    @Test("Output larger than the pipe buffer is drained to the end without deadlock")
    func drainsMoreThanThePipeBuffer() async {
        let data = await ReadOnlyProcess.run(
            Self.child("/usr/bin/head", ["-c", String(Self.largeOutputBytes), "/dev/zero"]),
            timeout: 10
        )

        #expect(data?.count == Self.largeOutputBytes)
    }

    @Test("A child that outlives its deadline is stopped and reported unavailable")
    func deadlineStopsTheChild() async throws {
        let sleeper = Self.child("/bin/sleep", ["30"])
        let started = Date()

        let data = await ReadOnlyProcess.run(sleeper, timeout: 0.2)

        #expect(data == nil)
        #expect(Date().timeIntervalSince(started) < 5)
        try await Self.expectStopped(sleeper)
    }

    @Test("Cancelling the calling task stops the child and reports unavailable")
    func cancellationStopsTheChild() async throws {
        let sleeper = SendableChild(Self.child("/bin/sleep", ["30"]))
        let started = Date()

        let run = Task { await ReadOnlyProcess.run(sleeper.process, timeout: 30) }
        #expect(await Self.waitUntil { sleeper.process.isRunning })
        run.cancel()

        #expect(await run.value == nil)
        #expect(Date().timeIntervalSince(started) < 5)
        try await Self.expectStopped(sleeper.process)
    }

    @Test("A child that cannot start or exits non-zero is reported unavailable")
    func failuresAreUnavailable() async {
        #expect(await ReadOnlyProcess.run(Self.child("/usr/bin/false", []), timeout: 10) == nil)
        #expect(await ReadOnlyProcess.run(Self.child("/nonexistent/tool", []), timeout: 10) == nil)
    }

    @Test("A command that allows it reads exit 1 with no output as an empty result")
    func emptyExitOneIsEmptyWhenAllowed() async {
        let empty = await ReadOnlyProcess.run(
            Self.child("/usr/bin/false", []),
            timeout: 10,
            shouldAcceptEmptyExitOne: true
        )
        let withOutput = await ReadOnlyProcess.run(
            Self.child("/usr/bin/grep", ["-c", "x", "/dev/null"]),
            timeout: 10,
            shouldAcceptEmptyExitOne: true
        )
        let otherStatus = await ReadOnlyProcess.run(
            Self.child("/usr/bin/grep", ["x", "/nonexistent"]),
            timeout: 10,
            shouldAcceptEmptyExitOne: true
        )

        #expect(empty == Data())
        #expect(withOutput == nil)
        #expect(otherStatus == nil)
    }

    @Test("Only the TCP connection listing treats lsof's exit 1 as no matches")
    func onlyTheConnectionListingAcceptsEmptyExitOne() {
        // lsof exits 1 when -iTCP matches nothing. The open-file listing has no filter, so it
        // always lists lsof's own files; empty output there is a failure and must fail closed.
        #expect(ReadOnlyCommand.tcpPorts.shouldAcceptEmptyExitOne)
        #expect(!ReadOnlyCommand.openFiles.shouldAcceptEmptyExitOne)
        #expect(!ReadOnlyCommand.backgroundItems.shouldAcceptEmptyExitOne)
        #expect(!ReadOnlyCommand.launchServices.shouldAcceptEmptyExitOne)
        #expect(!ReadOnlyCommand.rootDiskInfo.shouldAcceptEmptyExitOne)
    }

    private static func child(_ executable: String, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        return process
    }

    /// The runner reports unavailable before the child is reaped, so poll for its exit.
    private static func expectStopped(_ process: Process) async throws {
        #expect(await waitUntil { !process.isRunning })
        try #require(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

/// Lets the cancellation test watch the child it hands to another task.
private final class SendableChild: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}
