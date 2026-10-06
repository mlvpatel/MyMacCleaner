import Combine
import CleanerCore
import CleanerCoreDarwin
import Darwin
import Foundation

// MARK: - Performance View Model

@MainActor
final class PerformanceViewModel: ObservableObject {
    @Published private(set) var presentation = MemoryCoachPresentation.unavailable
    @Published var cpuUsage: Double = 0
    @Published var isMonitoring = false

    private let memoryObserver: any MemoryObservationPort
    private let pressureLifecycle: (any MemoryPressureSourceLifecycle)?
    private let workloadEvidence: any WorkloadEvidencePort
    private let rules: MemoryCoachingRules
    private var refreshTask: Task<Void, Never>?
    private var refreshCancellation: RefreshCancellation?
    private var refreshGeneration: UInt64 = 0
    // nonisolated(unsafe): read only by deinit, when no other reference to the model remains.
    private nonisolated(unsafe) var monitorTimer: Timer?
    private nonisolated(unsafe) var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0
    private var cpuCount: uint = 0

    init(
        memoryObserver: any MemoryObservationPort = DarwinMemoryObservationAdapter(),
        workloadEvidence: any WorkloadEvidencePort = LocalWorkloadEvidenceProducer(completedInventory: []),
        rules: MemoryCoachingRules = .init()
    ) {
        self.memoryObserver = memoryObserver
        pressureLifecycle = memoryObserver as? any MemoryPressureSourceLifecycle
        self.workloadEvidence = workloadEvidence
        self.rules = rules

        var discoveredCPUCount: natural_t = 0
        var discoveredCPUInfo: processor_info_array_t?
        var discoveredCPUInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &discoveredCPUCount,
            &discoveredCPUInfo,
            &discoveredCPUInfoCount
        )

        if result == KERN_SUCCESS {
            cpuCount = uint(discoveredCPUCount)
            releaseCPUInfo(discoveredCPUInfo, count: discoveredCPUInfoCount)
        }
    }

    deinit {
        monitorTimer?.invalidate()
        refreshTask?.cancel()
        refreshCancellation?.cancel()
        pressureLifecycle?.stopPressureSource()
        releaseCPUInfo(previousCPUInfo, count: previousCPUInfoCount)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        pressureLifecycle?.startPressureSource()
        refreshMemoryCoach()
        updateCPUUsage()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.isMonitoring == true else { return }
                self?.refreshMemoryCoach()
                self?.updateCPUUsage()
            }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isMonitoring = false
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshCancellation?.cancel()
        pressureLifecycle?.stopPressureSource()
        refreshTask = nil
        refreshCancellation = nil
    }

    func refreshMemoryCoach() {
        guard isMonitoring else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshCancellation?.cancel()

        let cancellation = RefreshCancellation()
        refreshCancellation = cancellation
        let memoryObserver = memoryObserver
        let workloadEvidence = workloadEvidence
        let rules = rules

        refreshTask = Task { @MainActor [weak self] in
            let snapshot = await memoryObserver.observe(cancellation: cancellation)
            guard !Task.isCancelled, !cancellation.isCancelled else { return }

            let displayedProcesses = Array(
                snapshot.processes.prefix(snapshot.samplingBudget.maximumRows)
            )
            let contexts = Dictionary(
                displayedProcesses.map { process in
                    (
                        process.identity,
                        workloadEvidence.context(sessionID: snapshot.sessionID, process: process)
                    )
                },
                uniquingKeysWith: { first, _ in first }
            )
            let nextPresentation = rules.evaluate(snapshot: snapshot, contexts: contexts)

            guard let self,
                  !Task.isCancelled,
                  !cancellation.isCancelled,
                  self.refreshGeneration == generation
            else {
                return
            }
            self.presentation = nextPresentation
        }
    }

    private func updateCPUUsage() {
        var processorCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            cpuUsage = 0
            return
        }

        defer {
            releaseCPUInfo(previousCPUInfo, count: previousCPUInfoCount)
            previousCPUInfo = cpuInfo
            previousCPUInfoCount = cpuInfoCount
            cpuCount = uint(processorCount)
        }

        guard let previousCPUInfo, cpuCount > 0 else {
            cpuUsage = 0
            return
        }

        var totalUsage: Double = 0
        let previous = UnsafeBufferPointer(start: previousCPUInfo, count: Int(previousCPUInfoCount))
        let current = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))

        for cpu in 0..<Int(min(cpuCount, uint(processorCount))) {
            let offset = cpu * Int(CPU_STATE_MAX)
            guard offset + Int(CPU_STATE_IDLE) < previous.count,
                  offset + Int(CPU_STATE_IDLE) < current.count else {
                continue
            }

            let user = Double(current[offset + Int(CPU_STATE_USER)] - previous[offset + Int(CPU_STATE_USER)])
            let system = Double(current[offset + Int(CPU_STATE_SYSTEM)] - previous[offset + Int(CPU_STATE_SYSTEM)])
            let nice = Double(current[offset + Int(CPU_STATE_NICE)] - previous[offset + Int(CPU_STATE_NICE)])
            let idle = Double(current[offset + Int(CPU_STATE_IDLE)] - previous[offset + Int(CPU_STATE_IDLE)])
            let total = user + system + nice + idle

            if total > 0 {
                totalUsage += (user + system + nice) / total
            }
        }

        cpuUsage = totalUsage / Double(max(cpuCount, 1)) * 100
    }

    nonisolated private func releaseCPUInfo(_ info: processor_info_array_t?, count: mach_msg_type_number_t) {
        guard let info, count > 0 else { return }

        let byteCount = vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), byteCount)
    }
}

private final class RefreshCancellation: @unchecked Sendable, MemoryObservationCancellation {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancellationRequested() async -> Bool {
        isCancelled
    }
}
