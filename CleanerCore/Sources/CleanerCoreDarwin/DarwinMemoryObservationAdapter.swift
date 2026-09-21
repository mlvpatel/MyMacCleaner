import CleanerCore

public protocol MemoryPressureSourceLifecycle: Sendable {
    func startPressureSource()
    func stopPressureSource()
}

public struct DarwinMemoryObservationAdapter: MemoryObservationPort, MemoryPressureSourceLifecycle, Sendable {
    private static let pressureFreshnessNanoseconds: UInt64 = 300_000_000_000

    let system: any DarwinMemorySystem
    private let pressureStore: PressureStore
    private let sessionCounter: SessionCounter
    private let lifecycle: PressureSourceLifecycleState

    public init() {
        let productionSystem = SystemDarwinMemorySystem()
        system = productionSystem
        pressureStore = PressureStore()
        sessionCounter = SessionCounter()
        lifecycle = PressureSourceLifecycleState()
    }

    init(system: any DarwinMemorySystem) {
        self.system = system
        pressureStore = PressureStore()
        sessionCounter = SessionCounter()
        lifecycle = PressureSourceLifecycleState()
        startPressureSource()
    }

    public func startPressureSource() {
        _ = lifecycle.startIfStopped {
            let generation = pressureStore.beginLifecycle()
            system.installPressureHandler { [pressureStore] level, reading in
                pressureStore.record(level: level, at: reading, generation: generation)
            }
            system.activatePressureSource()
        }
    }

    public func stopPressureSource() {
        _ = lifecycle.stopIfStarted {
            system.stopPressureSource()
            pressureStore.clear()
        }
    }

    public func observe(cancellation: any MemoryObservationCancellation) async -> MemoryCoachSnapshot {
        await observe(cancellation: cancellation, budget: .standard)
    }

    func observe(
        cancellation: any MemoryObservationCancellation,
        budget: SamplingBudget
    ) async -> MemoryCoachSnapshot {
        let sessionID = sessionCounter.next()
        guard !(await cancellation.isCancellationRequested()) else {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget)
        }

        let startedReading: ClockReading
        switch system.clockReading() {
        case let .success(reading):
            startedReading = reading
        case let .failure(failure):
            guard !(await cancellation.isCancellationRequested()) else {
                return Self.cancelledSnapshot(sessionID: sessionID, budget: budget)
            }
            return Self.unavailableTimingSnapshot(
                sessionID: sessionID,
                budget: budget,
                reason: Self.reason(for: failure)
            )
        }

        let startedAt = MemoryObservationTimestamp.observed(startedReading)
        guard !(await cancellation.isCancellationRequested()) else {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }
        let pressure = Self.pressure(from: pressureStore.latest, now: startedReading)
        var timingIssues: [MemorySnapshotIssue] = []

        guard !(await cancellation.isCancellationRequested()) else {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }
        let physical = await timestampedPhysicalMemory(
            system.physicalMemoryBytes(),
            cancellation: cancellation,
            sessionID: sessionID,
            budget: budget,
            startedAt: startedAt,
            timingIssues: &timingIssues
        )
        if physical.cancelled {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }

        guard !(await cancellation.isCancellationRequested()) else {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }
        let vm = await timestampedVM(
            system.vmPageCounts(),
            cancellation: cancellation,
            sessionID: sessionID,
            budget: budget,
            startedAt: startedAt,
            timingIssues: &timingIssues
        )
        if vm.cancelled {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }

        guard !(await cancellation.isCancellationRequested()) else {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }
        let swap = await timestampedSwap(
            system.swapUsage(),
            cancellation: cancellation,
            sessionID: sessionID,
            budget: budget,
            startedAt: startedAt,
            timingIssues: &timingIssues
        )
        if swap.cancelled {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }

        let workload = await observeWorkload(cancellation: cancellation, budget: budget)
        if workload.terminal == .cancelled {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }

        let completedAt: MemoryObservationTimestamp
        if workload.terminal == .deadlineExceeded {
            completedAt = .unavailable(.deadlineExceeded)
        } else {
            guard !(await cancellation.isCancellationRequested()) else {
                return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
            }
            switch system.clockReading() {
            case let .success(reading):
                completedAt = .observed(reading)
            case let .failure(failure):
                let reason = Self.reason(for: failure)
                completedAt = .unavailable(reason)
                timingIssues.append(.timing(reason))
            }
        }

        var issues = timingIssues
        issues.append(contentsOf: Self.issues(
            pressure: pressure,
            physical: physical.value,
            vm: vm.value,
            swap: swap.value
        ))
        for workloadIssue in workload.issues {
            issues.append(.workload(Self.unavailableReason(for: workloadIssue)))
        }
        issues = Self.unique(issues)

        let outcome: MemorySnapshotOutcome
        if issues.isEmpty {
            outcome = .complete
        } else if Self.hasUsableEvidence(
            pressure: pressure,
            physical: physical.value,
            vm: vm.value,
            swap: swap.value,
            processes: workload.rows
        ) {
            outcome = .partial
        } else {
            outcome = .unavailable
        }

        let cancellationRequested = await cancellation.isCancellationRequested()
        guard workload.terminal == .deadlineExceeded || !cancellationRequested else {
            return Self.cancelledSnapshot(sessionID: sessionID, budget: budget, startedAt: startedAt)
        }
        return .init(
            sessionID: sessionID,
            samplingBudget: budget,
            startedAt: startedAt,
            completedAt: completedAt,
            pressure: pressure,
            physicalMemory: physical.value,
            vm: vm.value,
            swap: swap.value,
            processes: workload.rows,
            processIssues: workload.issues,
            issues: issues,
            outcome: outcome
        )
    }

    private func timestampedPhysicalMemory(
        _ result: Result<UInt64, MemoryObservationFailure>,
        cancellation: any MemoryObservationCancellation,
        sessionID _: MemoryObservationSessionID,
        budget _: SamplingBudget,
        startedAt _: MemoryObservationTimestamp,
        timingIssues: inout [MemorySnapshotIssue]
    ) async -> (value: MemoryField<UInt64>, cancelled: Bool) {
        switch result {
        case let .failure(failure):
            return (.unavailable(Self.reason(for: failure)), false)
        case let .success(value) where value == 0:
            return (.unavailable(.malformedSource), false)
        case let .success(value):
            guard !(await cancellation.isCancellationRequested()) else {
                return (.unavailable(.unavailable), true)
            }
            switch system.clockReading() {
            case let .success(reading):
                return (.observed(value, observedAt: reading), false)
            case let .failure(failure):
                let reason = Self.reason(for: failure)
                timingIssues.append(.timing(reason))
                return (.unavailable(reason), false)
            }
        }
    }

    private func timestampedVM(
        _ result: Result<RawVMPageCounts, MemoryObservationFailure>,
        cancellation: any MemoryObservationCancellation,
        sessionID _: MemoryObservationSessionID,
        budget _: SamplingBudget,
        startedAt _: MemoryObservationTimestamp,
        timingIssues: inout [MemorySnapshotIssue]
    ) async -> (value: MemoryVMContext, cancelled: Bool) {
        switch result {
        case let .failure(failure):
            return (.unavailable(Self.reason(for: failure)), false)
        case let .success(pages) where pages.pageSize == 0:
            return (.unavailable(.malformedSource), false)
        case let .success(pages):
            guard !(await cancellation.isCancellationRequested()) else {
                return (.unavailable(.unavailable), true)
            }
            switch system.clockReading() {
            case let .success(reading):
                return (Self.vmContext(from: pages, at: reading), false)
            case let .failure(failure):
                let reason = Self.reason(for: failure)
                timingIssues.append(.timing(reason))
                return (.unavailable(reason), false)
            }
        }
    }

    private func timestampedSwap(
        _ result: Result<RawSwapUsage, MemoryObservationFailure>,
        cancellation: any MemoryObservationCancellation,
        sessionID _: MemoryObservationSessionID,
        budget _: SamplingBudget,
        startedAt _: MemoryObservationTimestamp,
        timingIssues: inout [MemorySnapshotIssue]
    ) async -> (value: MemorySwapContext, cancelled: Bool) {
        switch result {
        case let .failure(failure):
            return (.unavailable(Self.reason(for: failure)), false)
        case let .success(raw) where raw.usedBytes > raw.totalBytes:
            return (.unavailable(.malformedSource), false)
        case let .success(raw):
            guard !(await cancellation.isCancellationRequested()) else {
                return (.unavailable(.unavailable), true)
            }
            switch system.clockReading() {
            case let .success(reading):
                return (.init(
                    usedBytes: .observed(raw.usedBytes, observedAt: reading),
                    totalBytes: .observed(raw.totalBytes, observedAt: reading)
                ), false)
            case let .failure(failure):
                let reason = Self.reason(for: failure)
                timingIssues.append(.timing(reason))
                return (.unavailable(reason), false)
            }
        }
    }

    private static func cancelledSnapshot(
        sessionID: MemoryObservationSessionID,
        budget: SamplingBudget,
        startedAt: MemoryObservationTimestamp = .unavailable(.unavailable)
    ) -> MemoryCoachSnapshot {
        .init(
            sessionID: sessionID,
            samplingBudget: budget,
            startedAt: startedAt,
            completedAt: .unavailable(.unavailable),
            pressure: .unavailableNoFreshEvent,
            physicalMemory: .unavailable(.unavailable),
            vm: .unavailable(.unavailable),
            swap: .unavailable(.unavailable),
            processIssues: [.cancelled],
            issues: [],
            outcome: .cancelled
        )
    }

    private static func unavailableTimingSnapshot(
        sessionID: MemoryObservationSessionID,
        budget: SamplingBudget,
        reason: MemoryObservationUnavailable
    ) -> MemoryCoachSnapshot {
        .init(
            sessionID: sessionID,
            samplingBudget: budget,
            startedAt: .unavailable(reason),
            completedAt: .unavailable(reason),
            pressure: .unavailableNoFreshEvent,
            physicalMemory: .unavailable(.unavailable),
            vm: .unavailable(.unavailable),
            swap: .unavailable(.unavailable),
            issues: [.timing(reason)],
            outcome: .unavailable
        )
    }

    private static func pressure(
        from event: (MemoryPressureLevel, ClockReading)?,
        now: ClockReading
    ) -> MemoryPressureObservation {
        guard let event else { return .unavailableNoFreshEvent }
        let elapsed = now.observationInstant.monotonicNanoseconds
            .subtractingReportingOverflow(event.1.observationInstant.monotonicNanoseconds)
        guard !elapsed.overflow,
              elapsed.partialValue <= pressureFreshnessNanoseconds
        else {
            return .stale(event.0, observedAt: event.1)
        }
        return .observed(event.0, observedAt: event.1)
    }

    private static func vmContext(from pages: RawVMPageCounts, at reading: ClockReading) -> MemoryVMContext {
        .init(
            activeBytes: pageBytes(pages.activePages, pageSize: pages.pageSize, at: reading),
            inactiveBytes: pageBytes(pages.inactivePages, pageSize: pages.pageSize, at: reading),
            wiredBytes: pageBytes(pages.wiredPages, pageSize: pages.pageSize, at: reading),
            compressedBytes: pageBytes(pages.compressedPages, pageSize: pages.pageSize, at: reading),
            purgeableBytes: pageBytes(pages.purgeablePages, pageSize: pages.pageSize, at: reading)
        )
    }

    private static func pageBytes(
        _ pages: UInt64,
        pageSize: UInt64,
        at reading: ClockReading
    ) -> MemoryField<UInt64> {
        let result = pages.multipliedReportingOverflow(by: pageSize)
        return result.overflow
            ? .unavailable(.overflow)
            : .observed(result.partialValue, observedAt: reading)
    }

    private static func reason(for failure: MemoryObservationFailure) -> MemoryObservationUnavailable {
        switch failure {
        case .unavailable: return .unavailable
        case .malformedSource: return .malformedSource
        case .overflow: return .overflow
        }
    }

    private static func unavailableReason(for issue: ProcessObservationIssue) -> MemoryObservationUnavailable {
        switch issue {
        case .denied: return .denied
        case .exited: return .exited
        case .shortRead: return .shortRead
        case .identityChanged: return .identityChanged
        case .deadlineExceeded: return .deadlineExceeded
        case .invalidSource: return .malformedSource
        case .unreadable, .truncated, .cancelled: return .unavailable
        }
    }

    private static func issues(
        pressure: MemoryPressureObservation,
        physical: MemoryField<UInt64>,
        vm: MemoryVMContext,
        swap: MemorySwapContext
    ) -> [MemorySnapshotIssue] {
        var result: [MemorySnapshotIssue] = []
        switch pressure {
        case .observed: break
        case .unavailableNoFreshEvent: result.append(.pressure(.noFreshEvent))
        case .stale: result.append(.pressure(.stale))
        }
        if case let .unavailable(reason) = physical { result.append(.physicalMemory(reason)) }
        for field in [vm.activeBytes, vm.inactiveBytes, vm.wiredBytes, vm.compressedBytes, vm.purgeableBytes] {
            if case let .unavailable(reason) = field { result.append(.vm(reason)) }
        }
        for field in [swap.usedBytes, swap.totalBytes] {
            if case let .unavailable(reason) = field { result.append(.swap(reason)) }
        }
        return unique(result)
    }

    private static func hasUsableEvidence(
        pressure: MemoryPressureObservation,
        physical: MemoryField<UInt64>,
        vm: MemoryVMContext,
        swap: MemorySwapContext,
        processes: [ProcessMemoryEvidence]
    ) -> Bool {
        if !processes.isEmpty { return true }
        switch pressure {
        case .observed, .stale: return true
        case .unavailableNoFreshEvent: break
        }
        let fields = [
            physical,
            vm.activeBytes,
            vm.inactiveBytes,
            vm.wiredBytes,
            vm.compressedBytes,
            vm.purgeableBytes,
            swap.usedBytes,
            swap.totalBytes,
        ]
        return fields.contains { field in
            if case .observed = field { return true }
            return false
        }
    }

    static func appendUnique<T: Equatable>(_ value: T, to values: inout [T]) {
        if !values.contains(value) { values.append(value) }
    }

    private static func unique<T: Equatable>(_ values: [T]) -> [T] {
        var result: [T] = []
        for value in values { appendUnique(value, to: &result) }
        return result
    }
}
