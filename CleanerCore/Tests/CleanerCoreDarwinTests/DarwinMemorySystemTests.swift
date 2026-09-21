import CleanerCore
@testable import CleanerCoreDarwin
import Darwin
import Testing

@Suite("Darwin read-only system bridge")
struct DarwinMemorySystemTests {
    @Test("public adapter lifecycle starts an explicit retained pressure source")
    func publicLifecycle() async {
        let adapter = DarwinMemoryObservationAdapter()
        adapter.startPressureSource()
        let snapshot = await adapter.observe(cancellation: AlwaysCancelled())
        #expect(snapshot.outcome == .cancelled)
    }

    @Test("live primitives stay read-only, bounded, and truthful")
    func liveReadOnlyPrimitives() {
        let system = SystemDarwinMemorySystem()

        switch system.clockReading() {
        case let .success(clock):
            #expect(clock.observationInstant.monotonicNanoseconds > 0)
            #expect(clock.wallClockInstant.unixNanoseconds > 0)
        case let .failure(failure):
            #expect([.unavailable, .malformedSource, .overflow].contains(failure))
        }
        #expect(system.monotonicNanoseconds() > 0)
        switch system.physicalMemoryBytes() {
        case let .success(bytes):
            #expect(bytes > 0)
        case let .failure(failure):
            #expect(failure == .malformedSource)
        }
        switch system.vmPageCounts() {
        case let .success(vm):
            #expect(vm.pageSize > 0)
        case let .failure(failure):
            #expect(failure == .malformedSource)
        }
        switch system.swapUsage() {
        case let .success(swap):
            #expect(swap.usedBytes <= swap.totalBytes)
        case let .failure(failure):
            #expect(failure == .unavailable)
        }

        #expect(system.listPIDs(maximumCandidates: 0) == .failure(.unreadable))
        #expect(system.listPIDs(maximumCandidates: SamplingBudget.maximumCandidates + 1) == .failure(.unreadable))
        #expect(system.processIdentity(pid: 0) == .failure(.unreadable))
        #expect(system.residentBytes(pid: -1) == .failure(.unreadable))
    }

    @Test("checked wall-clock conversion cannot trap or clamp impossible values", arguments: [
        (Int64(0), Int64(0), Result<Int64, MemoryObservationFailure>.success(0)),
        (Int64(1), Int64(1), .success(1_000_000_001)),
        (Int64(9_223_372_036), Int64(854_775_807), .success(.max)),
        (Int64(9_223_372_036), Int64(854_775_808), .failure(.overflow)),
        (Int64.max, Int64(0), .failure(.overflow)),
        (Int64.min, Int64(0), .failure(.overflow)),
        (Int64(0), Int64(-1), .failure(.malformedSource)),
        (Int64(0), Int64(1_000_000_000), .failure(.malformedSource)),
    ])
    func checkedWallClock(seconds: Int64, nanoseconds: Int64, expected: Result<Int64, MemoryObservationFailure>) {
        #expect(SystemDarwinMemorySystem.checkedUnixNanoseconds(seconds: seconds, nanoseconds: nanoseconds) == expected)
    }

    @Test("proc byte counts are bounded and exact", arguments: [
        (-1, 8, WorkloadReadFailure.unreadable),
        (0, 8, .unreadable),
        (3, 8, .shortRead),
        (12, 8, .shortRead),
        (4, 0, .shortRead),
        (4, -4, .shortRead),
    ])
    func invalidPIDByteCounts(returned: Int32, capacity: Int32, expected: WorkloadReadFailure) {
        #expect(SystemDarwinMemorySystem.pidCount(returnedBytes: returned, capacityBytes: capacity) == .failure(expected))
    }

    @Test("an exact full PID buffer is explicitly truncated")
    func exactPIDByteCounts() {
        #expect(SystemDarwinMemorySystem.pidCount(returnedBytes: 4, capacityBytes: 8) == .success(.init(count: 1, isTruncated: false)))
        #expect(SystemDarwinMemorySystem.pidCount(returnedBytes: 8, capacityBytes: 8) == .success(.init(count: 2, isTruncated: true)))
    }

    @Test("errno mapping is closed and non-sensitive", arguments: [
        (EPERM, WorkloadReadFailure.denied),
        (EACCES, .denied),
        (ESRCH, .exited),
        (EINVAL, .unreadable),
    ])
    func errnoMapping(errorNumber: Int32, expected: WorkloadReadFailure) {
        #expect(SystemDarwinMemorySystem.classify(errorNumber: errorNumber) == expected)
    }

    @Test("exact struct byte counts are required", arguments: [
        (-1, 16, WorkloadReadFailure.unreadable),
        (0, 16, .unreadable),
        (8, 16, .shortRead),
        (17, 16, .shortRead),
        (16, 16, nil),
    ])
    func exactReadValidation(returned: Int32, expectedBytes: Int32, expected: WorkloadReadFailure?) {
        #expect(SystemDarwinMemorySystem.readFailure(returnedBytes: returned, expectedBytes: expectedBytes, errorNumber: EINVAL) == expected)
    }
}

private final class AlwaysCancelled: MemoryObservationCancellation, @unchecked Sendable {
    func isCancellationRequested() async -> Bool { true }
}
