import CleanerCore
import Darwin
import Dispatch
import Foundation

final class SessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> MemoryObservationSessionID {
        lock.lock()
        defer { lock.unlock() }
        let incremented = value.addingReportingOverflow(1)
        value = incremented.overflow ? 1 : incremented.partialValue
        return .init(value)
    }
}

final class PressureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (MemoryPressureLevel, ClockReading)?
    private var lifecycleGeneration: UInt64 = 0

    var latest: (MemoryPressureLevel, ClockReading)? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func beginLifecycle() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        lifecycleGeneration &+= 1
        stored = nil
        return lifecycleGeneration
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        lifecycleGeneration &+= 1
        stored = nil
    }

    func record(level: MemoryPressureLevel, at reading: ClockReading, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == lifecycleGeneration else { return }
        stored = (level, reading)
    }
}

final class PressureSourceLifecycleState: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false

    func startIfStopped(_ operation: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return false }
        operation()
        started = true
        return true
    }

    func stopIfStarted(_ operation: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard started else { return false }
        operation()
        started = false
        return true
    }
}

final class SystemDarwinMemorySystem: DarwinMemorySystem, @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.mymaccleaner.memory-observation")
    private let sourceLock = NSLock()
    private var source: DispatchSourceMemoryPressure?

    func installPressureHandler(
        _ handler: @escaping @Sendable (MemoryPressureLevel, ClockReading) -> Void
    ) {
        let newSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: queue
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self, let source = newSource,
                  case let .success(reading) = self.clockReading()
            else {
                return
            }
            let events = source.data
            if events.contains(.critical) {
                handler(.critical, reading)
            } else if events.contains(.warning) {
                handler(.warning, reading)
            } else if events.contains(.normal) {
                handler(.normal, reading)
            }
        }
        sourceLock.lock()
        defer { sourceLock.unlock() }
        source?.cancel()
        source = newSource
    }

    func activatePressureSource() {
        sourceLock.lock()
        defer { sourceLock.unlock() }
        source?.activate()
    }

    func stopPressureSource() {
        sourceLock.lock()
        defer { sourceLock.unlock() }
        source?.cancel()
        source = nil
    }

    deinit {
        sourceLock.lock()
        source?.cancel()
        sourceLock.unlock()
    }

    func clockReading() -> Result<ClockReading, MemoryObservationFailure> {
        var wall = timespec()
        guard clock_gettime(CLOCK_REALTIME, &wall) == 0,
              let seconds = Int64(exactly: wall.tv_sec),
              let nanoseconds = Int64(exactly: wall.tv_nsec)
        else {
            return .failure(.unavailable)
        }
        return Self.checkedUnixNanoseconds(seconds: seconds, nanoseconds: nanoseconds)
            .map { unixNanoseconds in
                ClockReading(
                    observationInstant: .init(monotonicNanoseconds: monotonicNanoseconds()),
                    wallClockInstant: .init(unixNanoseconds: unixNanoseconds)
                )
            }
    }

    func monotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func checkedUnixNanoseconds(
        seconds: Int64,
        nanoseconds: Int64
    ) -> Result<Int64, MemoryObservationFailure> {
        guard (0 ..< 1_000_000_000).contains(nanoseconds) else {
            return .failure(.malformedSource)
        }
        let scaled = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !scaled.overflow else {
            return .failure(.overflow)
        }
        let combined = scaled.partialValue.addingReportingOverflow(nanoseconds)
        guard !combined.overflow else {
            return .failure(.overflow)
        }
        return .success(combined.partialValue)
    }

    func physicalMemoryBytes() -> Result<UInt64, MemoryObservationFailure> {
        let value = ProcessInfo.processInfo.physicalMemory
        return value > 0 ? .success(value) : .failure(.malformedSource)
    }

    func vmPageCounts() -> Result<RawVMPageCounts, MemoryObservationFailure> {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let expectedCount = count
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard status == KERN_SUCCESS, count == expectedCount else {
            return .failure(.malformedSource)
        }
        let rawPageSize = getpagesize()
        guard rawPageSize > 0 else {
            return .failure(.malformedSource)
        }
        return .success(.init(
            activePages: UInt64(stats.active_count),
            inactivePages: UInt64(stats.inactive_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            pageSize: UInt64(rawPageSize)
        ))
    }

    func swapUsage() -> Result<RawSwapUsage, MemoryObservationFailure> {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0,
              size == MemoryLayout<xsw_usage>.size,
              usage.xsu_used <= usage.xsu_total
        else {
            return .failure(.unavailable)
        }
        return .success(.init(usedBytes: usage.xsu_used, totalBytes: usage.xsu_total))
    }

    func listPIDs(maximumCandidates: Int) -> Result<RawPIDList, WorkloadReadFailure> {
        guard (1 ... SamplingBudget.maximumCandidates).contains(maximumCandidates) else {
            return .failure(.unreadable)
        }
        let byteCount = maximumCandidates.multipliedReportingOverflow(by: MemoryLayout<Int32>.stride)
        guard !byteCount.overflow,
              let capacityBytes = Int32(exactly: byteCount.partialValue)
        else {
            return .failure(.unreadable)
        }
        var pids = Array(repeating: Int32(0), count: maximumCandidates)
        let returned = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, capacityBytes)
        if returned <= 0 {
            return .failure(Self.classify(errorNumber: errno))
        }
        switch Self.pidCount(returnedBytes: returned, capacityBytes: capacityBytes) {
        case let .failure(failure):
            return .failure(failure)
        case let .success(result):
            return .success(.init(
                pids: Array(pids.prefix(result.count)),
                isTruncated: result.isTruncated
            ))
        }
    }

    static func pidCount(
        returnedBytes: Int32,
        capacityBytes: Int32
    ) -> Result<PIDBufferCount, WorkloadReadFailure> {
        guard returnedBytes > 0 else {
            return .failure(.unreadable)
        }
        guard capacityBytes > 0,
              returnedBytes <= capacityBytes,
              Int(returnedBytes) % MemoryLayout<Int32>.stride == 0
        else {
            return .failure(.shortRead)
        }
        return .success(.init(
            count: Int(returnedBytes) / MemoryLayout<Int32>.stride,
            isTruncated: returnedBytes == capacityBytes
        ))
    }

    func processIdentity(pid: Int32) -> Result<RawProcessIdentity, WorkloadReadFailure> {
        guard pid > 0 else {
            return .failure(.unreadable)
        }
        var info = proc_bsdinfo()
        let expectedBytes = Int32(MemoryLayout<proc_bsdinfo>.size)
        let returned = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedBytes)
        if let failure = Self.readFailure(
            returnedBytes: returned,
            expectedBytes: expectedBytes,
            errorNumber: errno
        ) {
            return .failure(failure)
        }
        guard let returnedPID = Int32(exactly: info.pbi_pid), returnedPID == pid else {
            return .failure(.shortRead)
        }
        let bytes = withUnsafeBytes(of: info.pbi_name) { raw in
            Array(raw.prefix { $0 != 0 })
        }
        let name = String(bytes: bytes, encoding: .utf8) ?? ""
        return .success(.init(
            pid: pid,
            startTimeSeconds: info.pbi_start_tvsec,
            startTimeMicroseconds: info.pbi_start_tvusec,
            displayName: name
        ))
    }

    func residentBytes(pid: Int32) -> Result<UInt64, WorkloadReadFailure> {
        guard pid > 0 else {
            return .failure(.unreadable)
        }
        var info = proc_taskinfo()
        let expectedBytes = Int32(MemoryLayout<proc_taskinfo>.size)
        let returned = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, expectedBytes)
        if let failure = Self.readFailure(
            returnedBytes: returned,
            expectedBytes: expectedBytes,
            errorNumber: errno
        ) {
            return .failure(failure)
        }
        return .success(info.pti_resident_size)
    }

    static func readFailure(
        returnedBytes: Int32,
        expectedBytes: Int32,
        errorNumber: Int32
    ) -> WorkloadReadFailure? {
        if returnedBytes == expectedBytes, expectedBytes > 0 {
            return nil
        }
        if returnedBytes > 0 {
            return .shortRead
        }
        return classify(errorNumber: errorNumber)
    }

    static func classify(errorNumber: Int32) -> WorkloadReadFailure {
        switch errorNumber {
        case EPERM, EACCES: return .denied
        case ESRCH: return .exited
        default: return .unreadable
        }
    }
}
