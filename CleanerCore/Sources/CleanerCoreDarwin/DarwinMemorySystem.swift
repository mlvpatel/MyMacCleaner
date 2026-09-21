import CleanerCore

enum MemoryObservationFailure: Error, Equatable, Sendable {
    case unavailable
    case malformedSource
    case overflow
}

struct RawVMPageCounts: Equatable, Sendable {
    let activePages: UInt64
    let inactivePages: UInt64
    let wiredPages: UInt64
    let compressedPages: UInt64
    let purgeablePages: UInt64
    let pageSize: UInt64
}

struct RawSwapUsage: Equatable, Sendable {
    let usedBytes: UInt64
    let totalBytes: UInt64
}

struct RawPIDList: Equatable, Sendable {
    let pids: [Int32]
    let isTruncated: Bool
}

struct RawProcessIdentity: Equatable, Sendable {
    let pid: Int32
    let startTimeSeconds: UInt64
    let startTimeMicroseconds: UInt64
    let displayName: String
}

struct PIDBufferCount: Equatable, Sendable {
    let count: Int
    let isTruncated: Bool
}

enum WorkloadReadFailure: Error, Equatable, Sendable {
    case denied
    case exited
    case shortRead
    case unreadable
}

protocol DarwinMemorySystem: Sendable {
    func installPressureHandler(
        _ handler: @escaping @Sendable (MemoryPressureLevel, ClockReading) -> Void
    )
    func activatePressureSource()
    func stopPressureSource()
    func clockReading() -> Result<ClockReading, MemoryObservationFailure>
    func monotonicNanoseconds() -> UInt64
    func physicalMemoryBytes() -> Result<UInt64, MemoryObservationFailure>
    func vmPageCounts() -> Result<RawVMPageCounts, MemoryObservationFailure>
    func swapUsage() -> Result<RawSwapUsage, MemoryObservationFailure>
    func listPIDs(maximumCandidates: Int) -> Result<RawPIDList, WorkloadReadFailure>
    func processIdentity(pid: Int32) -> Result<RawProcessIdentity, WorkloadReadFailure>
    func residentBytes(pid: Int32) -> Result<UInt64, WorkloadReadFailure>
}
