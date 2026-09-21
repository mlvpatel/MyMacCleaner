import CleanerCore
@testable import CleanerCoreDarwin
import Darwin
import Dispatch
import Testing

private let zeroReading = ClockReading(
    observationInstant: .init(monotonicNanoseconds: 0),
    wallClockInstant: .init(unixNanoseconds: 0)
)

private func reading(_ value: UInt64) -> ClockReading {
    .init(
        observationInstant: .init(monotonicNanoseconds: value),
        wallClockInstant: .init(unixNanoseconds: Int64(value))
    )
}

private let completeVM = RawVMPageCounts(
    activePages: 1,
    inactivePages: 2,
    wiredPages: 3,
    compressedPages: 4,
    purgeablePages: 5,
    pageSize: 4
)

@Suite("Memory snapshot")
struct MemorySnapshotTests {
    @Test("fresh source pressure and all fields produce one complete snapshot")
    func completeSnapshot() async {
        let event = reading(10)
        let system = ScriptedDarwinMemorySystem(
            clocks: [.success(reading(20)), .success(reading(21)), .success(reading(22)), .success(reading(23)), .success(reading(24))],
            monotonic: Array(repeating: 20, count: 8),
            pressureEvent: (.warning, event),
            physicalMemory: .success(16_384),
            vm: .success(completeVM),
            swap: .success(.init(usedBytes: 7, totalBytes: 9))
        )

        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())

        #expect(snapshot.outcome == .complete)
        #expect(snapshot.samplingBudget == .standard)
        #expect(snapshot.startedAt == .observed(reading(20)))
        #expect(snapshot.completedAt == .observed(reading(24)))
        #expect(snapshot.pressure == .observed(.warning, observedAt: event))
        #expect(snapshot.physicalMemory == .observed(16_384, observedAt: reading(21)))
        #expect(snapshot.vm.activeBytes == .observed(4, observedAt: reading(22)))
        #expect(snapshot.vm.inactiveBytes == .observed(8, observedAt: reading(22)))
        #expect(snapshot.vm.wiredBytes == .observed(12, observedAt: reading(22)))
        #expect(snapshot.vm.compressedBytes == .observed(16, observedAt: reading(22)))
        #expect(snapshot.vm.purgeableBytes == .observed(20, observedAt: reading(22)))
        #expect(snapshot.swap.usedBytes == .observed(7, observedAt: reading(23)))
        #expect(snapshot.swap.totalBytes == .observed(9, observedAt: reading(23)))
        #expect(snapshot.issues.isEmpty)
        #expect(Array(system.calls.prefix(2)) == [.installPressureHandler, .activatePressureSource])
    }

    @Test("pressure is event-only, exhaustive, and fresh through exactly 300 seconds", arguments: [
        (MemoryPressureLevel.normal, MemoryPressureLevel.normal),
        (.warning, .warning),
        (.critical, .critical),
    ])
    func eventPressureLevels(source: MemoryPressureLevel, expected: MemoryPressureLevel) async {
        let event = reading(100)
        let now = ClockReading(
            observationInstant: .init(monotonicNanoseconds: 300_000_000_100),
            wallClockInstant: .init(unixNanoseconds: 100)
        )
        let snapshot = await completeSystem(start: now, pressureEvent: (source, event))
            .adapter.observe(cancellation: NeverCancelled())
        #expect(snapshot.pressure == .observed(expected, observedAt: event))
    }

    @Test("missing, old, and future pressure events never become normal")
    func unavailableAndStalePressure() async {
        let missing = await completeSystem(start: reading(1), pressureEvent: nil)
            .adapter.observe(cancellation: NeverCancelled())
        #expect(missing.pressure == .unavailableNoFreshEvent)
        #expect(missing.outcome == .partial)

        let oldEvent = reading(1)
        let oldNow = ClockReading(
            observationInstant: .init(monotonicNanoseconds: 300_000_000_002),
            wallClockInstant: .init(unixNanoseconds: 2)
        )
        let stale = await completeSystem(start: oldNow, pressureEvent: (.critical, oldEvent))
            .adapter.observe(cancellation: NeverCancelled())
        #expect(stale.pressure == .stale(.critical, observedAt: oldEvent))

        let future = reading(100)
        let futureSnapshot = await completeSystem(start: reading(99), pressureEvent: (.normal, future))
            .adapter.observe(cancellation: NeverCancelled())
        #expect(futureSnapshot.pressure == .stale(.normal, observedAt: future))
    }

    @Test("clock failure is typed and does not fabricate timestamps")
    func clockFailureIsUnavailable() async {
        let system = ScriptedDarwinMemorySystem(clocks: [.failure(.malformedSource)])
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())

        #expect(snapshot.startedAt == .unavailable(.malformedSource))
        #expect(snapshot.completedAt == .unavailable(.malformedSource))
        #expect(snapshot.outcome == .unavailable)
        #expect(snapshot.issues == [.timing(.malformedSource)])
        #expect(!system.calls.contains(.physicalMemory))
    }

    @Test("a completion clock failure preserves valid evidence as partial")
    func completionClockFailurePreservesEvidence() async {
        let system = ScriptedDarwinMemorySystem(
            clocks: [.success(reading(1)), .success(reading(2)), .success(reading(3)), .success(reading(4)), .failure(.malformedSource)],
            monotonic: Array(repeating: 1, count: 8),
            pressureEvent: (.normal, reading(1)),
            physicalMemory: .success(10),
            vm: .success(completeVM),
            swap: .success(.init(usedBytes: 0, totalBytes: 0))
        )
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())

        #expect(snapshot.completedAt == .unavailable(.malformedSource))
        #expect(snapshot.physicalMemory == .observed(10, observedAt: reading(2)))
        #expect(snapshot.outcome == .partial)
        #expect(snapshot.issues.contains(.timing(.malformedSource)))
    }

    @Test("field timestamp failures stay typed and never fabricate observations", arguments: 1 ... 3)
    func fieldTimestampFailures(failureIndex: Int) async {
        var clocks = Array(repeating: Result<ClockReading, MemoryObservationFailure>.success(reading(1)), count: 5)
        clocks[failureIndex] = .failure(.overflow)
        let system = ScriptedDarwinMemorySystem(
            clocks: clocks,
            monotonic: Array(repeating: 1, count: 12),
            pressureEvent: (.normal, reading(1)),
            physicalMemory: .success(1),
            vm: .success(completeVM),
            swap: .success(.init(usedBytes: 0, totalBytes: 1))
        )
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())

        let failed = [snapshot.physicalMemory, snapshot.vm.activeBytes, snapshot.swap.usedBytes]
        #expect(failed[failureIndex - 1] == .unavailable(.overflow))
        #expect(snapshot.issues.contains(.timing(.overflow)))
        #expect(snapshot.outcome == .partial)
    }

    @Test("no usable field produces unavailable rather than partial success")
    func noUsableEvidenceIsUnavailable() async {
        let system = ScriptedDarwinMemorySystem(
            clocks: Array(repeating: .success(reading(1)), count: 5),
            monotonic: Array(repeating: 1, count: 8)
        )
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())
        #expect(snapshot.outcome == .unavailable)
        #expect(snapshot.issues.contains(.pressure(.noFreshEvent)))
        #expect(snapshot.issues.contains(.physicalMemory(.unavailable)))
        #expect(snapshot.issues.contains(.vm(.unavailable)))
        #expect(snapshot.issues.contains(.swap(.unavailable)))
    }

    @Test("invalid physical, VM, and swap observations stay independently unavailable")
    func malformedFieldsRemainIndependent() async {
        let system = ScriptedDarwinMemorySystem(
            clocks: Array(repeating: .success(reading(1)), count: 5),
            monotonic: Array(repeating: 1, count: 8),
            pressureEvent: (.normal, reading(1)),
            physicalMemory: .success(0),
            vm: .success(.init(activePages: 1, inactivePages: 1, wiredPages: 1, compressedPages: 1, purgeablePages: 1, pageSize: 0)),
            swap: .success(.init(usedBytes: 2, totalBytes: 1))
        )
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())
        #expect(snapshot.physicalMemory == .unavailable(.malformedSource))
        #expect(snapshot.vm == .unavailable(.malformedSource))
        #expect(snapshot.swap == .unavailable(.malformedSource))
        #expect(snapshot.outcome == .partial)
    }

    @Test("every VM page field can overflow without hiding the issue", arguments: 0 ..< 5)
    func everyVMFieldContributesToOutcome(index: Int) async {
        var values: [UInt64] = [1, 1, 1, 1, 1]
        values[index] = .max
        let vm = RawVMPageCounts(
            activePages: values[0],
            inactivePages: values[1],
            wiredPages: values[2],
            compressedPages: values[3],
            purgeablePages: values[4],
            pageSize: 2
        )
        let system = completeSystem(start: reading(1), vm: .success(vm)).system
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())
        let fields = [
            snapshot.vm.activeBytes,
            snapshot.vm.inactiveBytes,
            snapshot.vm.wiredBytes,
            snapshot.vm.compressedBytes,
            snapshot.vm.purgeableBytes,
        ]
        #expect(fields[index] == .unavailable(.overflow))
        #expect(snapshot.issues.contains(.vm(.overflow)))
        #expect(snapshot.outcome == .partial)
    }

    @Test("snapshot cancellation checkpoints stop before the next system capability", arguments: 1 ... 14)
    func cancellationStopsSnapshot(check: Int) async {
        let system = completeSystem(start: reading(1)).system
        let cancellation = ScriptedCancellation(cancelAtCheck: check)
        cancellation.onCancellationObserved = { system.markCancellationObserved() }
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: cancellation)

        #expect(snapshot.outcome == .cancelled)
        #expect(cancellation.checkCount == check)
        #expect(system.callsAfterCancellationObserved.isEmpty)
    }

    @Test("cancellation arriving during a failed initial clock wins before emission")
    func failedInitialClockRechecksCancellation() async {
        let system = ScriptedDarwinMemorySystem(clocks: [.failure(.unavailable)])
        let cancellation = ScriptedCancellation(cancelAtCheck: 2)
        cancellation.onCancellationObserved = { system.markCancellationObserved() }
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: cancellation)

        #expect(snapshot.outcome == .cancelled)
        #expect(cancellation.checkCount == 2)
        #expect(system.callsAfterCancellationObserved.isEmpty)
    }

    @Test("pressure source start, stop, and restart are idempotent and do not retain a prior event")
    func pressureSourceLifecycleClearsOldEvidence() async {
        let fixture = completeSystem(
            start: reading(20),
            pressureEvent: (.critical, reading(20))
        )
        let system = fixture.system
        let adapter = fixture.adapter

        adapter.startPressureSource()
        adapter.startPressureSource()
        let first = await adapter.observe(cancellation: NeverCancelled())
        #expect(first.pressure == .observed(.critical, observedAt: reading(20)))

        adapter.stopPressureSource()
        adapter.stopPressureSource()
        adapter.startPressureSource()
        let restarted = await adapter.observe(cancellation: NeverCancelled())

        #expect(restarted.pressure == .unavailableNoFreshEvent)
        #expect(
            system.calls.filter {
                switch $0 {
                case .installPressureHandler, .activatePressureSource, .stopPressureSource:
                    true
                default:
                    false
                }
            } == [
                .installPressureHandler,
                .activatePressureSource,
                .stopPressureSource,
                .installPressureHandler,
                .activatePressureSource,
            ]
        )
    }

    @Test("a stopped source is not resurrected by a cancelled observation")
    func stoppedSourceStaysStoppedForCancelledObservation() async {
        let fixture = completeSystem(start: reading(20))
        let system = fixture.system
        let adapter = fixture.adapter

        adapter.stopPressureSource()
        let callsBeforeObservation = system.calls
        let snapshot = await adapter.observe(cancellation: ScriptedCancellation(cancelAtCheck: 1))

        #expect(snapshot.outcome == .cancelled)
        #expect(system.calls == callsBeforeObservation)
    }

    @Test("a stop concurrent with source installation completes after and cancels the installed source")
    func sourceLifecycleTransitionsAreLinearizable() {
        let fixture = completeSystem(start: reading(20))
        let system = fixture.system
        let adapter = fixture.adapter
        let installEntered = DispatchSemaphore(value: 0)
        let allowInstall = DispatchSemaphore(value: 0)
        let startFinished = DispatchSemaphore(value: 0)
        let stopFinished = DispatchSemaphore(value: 0)

        adapter.stopPressureSource()
        system.onInstallPressureHandler = {
            installEntered.signal()
            _ = allowInstall.wait(timeout: .now() + 1)
        }

        DispatchQueue.global().async {
            adapter.startPressureSource()
            startFinished.signal()
        }
        #expect(installEntered.wait(timeout: .now() + 1) == .success)

        DispatchQueue.global().async {
            adapter.stopPressureSource()
            stopFinished.signal()
        }
        #expect(stopFinished.wait(timeout: .now()) == .timedOut)

        allowInstall.signal()
        #expect(startFinished.wait(timeout: .now() + 1) == .success)
        #expect(stopFinished.wait(timeout: .now() + 1) == .success)
        #expect(
            system.calls.suffix(3) == [
                .installPressureHandler,
                .activatePressureSource,
                .stopPressureSource,
            ]
        )
    }
}

@Suite("Bounded workload sampler")
struct WorkloadSamplerTests {
    @Test("the validated standard budget locks every hard cap")
    func budgetValidation() throws {
        #expect(SamplingBudget.standard.maximumCandidates == 512)
        #expect(SamplingBudget.standard.maximumRows == 10)
        #expect(SamplingBudget.standard.maximumDurationNanoseconds == 500_000_000)
        #expect(throws: MemorySamplingBudgetError.invalid) { try SamplingBudget(maximumCandidates: 0) }
        #expect(throws: MemorySamplingBudgetError.invalid) { try SamplingBudget(maximumRows: 0) }
        #expect(throws: MemorySamplingBudgetError.invalid) { try SamplingBudget(maximumDurationNanoseconds: 0) }
        #expect(throws: MemorySamplingBudgetError.excessive) { try SamplingBudget(maximumCandidates: 513) }
        #expect(throws: MemorySamplingBudgetError.excessive) { try SamplingBudget(maximumRows: 11) }
        #expect(throws: MemorySamplingBudgetError.excessive) { try SamplingBudget(maximumDurationNanoseconds: 500_000_001) }
    }

    @Test("rows sort by resident bytes, then label, then PID and respect row cap")
    func boundedDeterministicSorting() async throws {
        let system = ScriptedDarwinMemorySystem(
            clocks: Array(repeating: .success(reading(1)), count: 8),
            monotonic: Array(repeating: 1, count: 32),
            pids: .success(.init(pids: [7, 3, 2, 9], isTruncated: false)),
            identities: [
                7: .success(identity(pid: 7, name: "beta")),
                3: .success(identity(pid: 3, name: "alpha")),
                2: .success(identity(pid: 2, name: "alpha")),
                9: .success(identity(pid: 9, name: "highest")),
            ],
            residents: [7: .success(10), 3: .success(10), 2: .success(10), 9: .success(20)]
        )
        let budget = try SamplingBudget(maximumCandidates: 4, maximumRows: 3)
        let result = await DarwinMemoryObservationAdapter(system: system)
            .observeWorkload(cancellation: NeverCancelled(), budget: budget)

        #expect(result.rows.map(\.identity.pid) == [9, 2, 3])
        #expect(result.issues.isEmpty)
        #expect(result.terminal == .complete)
        #expect(system.calls.filter { if case .listPIDs = $0 { true } else { false } }.count == 1)
    }

    @Test("labels strip controls, cap graphemes, and never expose a PID fallback")
    func labelsArePrivacySafe() async throws {
        let long = String(repeating: "e\u{301}", count: 70)
        let system = ScriptedDarwinMemorySystem(
            clocks: Array(repeating: .success(reading(1)), count: 4),
            monotonic: Array(repeating: 1, count: 20),
            pids: .success(.init(pids: [1, 2, 3, 4], isTruncated: false)),
            identities: [
                1: .success(identity(pid: 1, name: "bad\n\tname")),
                2: .success(identity(pid: 2, name: long)),
                3: .success(identity(pid: 3, name: "\n\t")),
                4: .success(identity(pid: 4, name: "evil\u{202E}txt")),
            ],
            residents: [1: .success(4), 2: .success(3), 3: .success(1), 4: .success(2)]
        )
        let result = await DarwinMemoryObservationAdapter(system: system)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 4, maximumRows: 4))

        #expect(result.rows[0].label.value == "badname")
        #expect(result.rows[1].label.value.count == 64)
        #expect(result.rows[2].label.value == "eviltxt")
        #expect(result.rows[3].label == .generic)
        #expect(!result.rows[3].label.value.contains("3"))
    }

    @Test("candidate truncation, nonpositive IDs, and oversized adapter results are fail closed")
    func invalidPIDListsAreTyped() async throws {
        let truncated = ScriptedDarwinMemorySystem(
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [], isTruncated: true))
        )
        let truncatedResult = await DarwinMemoryObservationAdapter(system: truncated)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(truncatedResult.issues == [.truncated])

        let invalid = ScriptedDarwinMemorySystem(
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [0, -1], isTruncated: false))
        )
        let invalidResult = await DarwinMemoryObservationAdapter(system: invalid)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 2, maximumRows: 1))
        #expect(invalidResult.rows.isEmpty)
        #expect(invalidResult.issues == [.invalidSource])

        let oversized = ScriptedDarwinMemorySystem(
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [1, 2], isTruncated: false))
        )
        let oversizedResult = await DarwinMemoryObservationAdapter(system: oversized)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(oversizedResult.rows.isEmpty)
        #expect(oversizedResult.issues == [.invalidSource])
        #expect(!oversized.calls.contains(.identity(1)))
    }

    @Test("list and per-process read failures map to closed typed issues", arguments: [
        (WorkloadReadFailure.denied, ProcessObservationIssue.denied),
        (.exited, .exited),
        (.shortRead, .shortRead),
        (.unreadable, .unreadable),
    ])
    func closedFailureMapping(failure: WorkloadReadFailure, expected: ProcessObservationIssue) async throws {
        let listFailure = ScriptedDarwinMemorySystem(monotonic: [1, 1], pids: .failure(failure))
        let listed = await DarwinMemoryObservationAdapter(system: listFailure)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(listed.issues == [expected])

        let identityFailure = ScriptedDarwinMemorySystem(
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [1], isTruncated: false)),
            identitySequence: [.failure(failure)]
        )
        let identified = await DarwinMemoryObservationAdapter(system: identityFailure)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(identified.issues == [expected])

        let residentFailure = ScriptedDarwinMemorySystem(
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [1], isTruncated: false)),
            identities: [1: .success(identity(pid: 1))],
            residents: [1: .failure(failure)]
        )
        let resident = await DarwinMemoryObservationAdapter(system: residentFailure)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(resident.issues == [expected])

        let rereadFailure = ScriptedDarwinMemorySystem(
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [1], isTruncated: false)),
            identitySequence: [.success(identity(pid: 1)), .failure(failure)],
            residents: [1: .success(1)]
        )
        let reread = await DarwinMemoryObservationAdapter(system: rereadFailure)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(reread.issues == [expected])
    }

    @Test("list failure and invalid rows recheck cancellation and deadline before emission")
    func earlyListEmissionsAreCheckpointed() async throws {
        let budget = try SamplingBudget(maximumCandidates: 1, maximumRows: 1, maximumDurationNanoseconds: 500)
        let sources: [Result<RawPIDList, WorkloadReadFailure>] = [
            .failure(.denied),
            .success(.init(pids: [0], isTruncated: false)),
        ]
        for source in sources {
            let system = ScriptedDarwinMemorySystem(monotonic: [0, 0], pids: source)
            let cancellation = ScriptedCancellation(cancelAtCheck: 3)
            cancellation.onCancellationObserved = { system.markCancellationObserved() }
            let result = await DarwinMemoryObservationAdapter(system: system)
                .observeWorkload(cancellation: cancellation, budget: budget)
            #expect(result.terminal == .cancelled)
            #expect(system.callsAfterCancellationObserved.isEmpty)
        }

        let deadlineSystem = ScriptedDarwinMemorySystem(monotonic: [0, 0, 501], pids: .failure(.denied))
        let deadline = await DarwinMemoryObservationAdapter(system: deadlineSystem)
            .observeWorkload(cancellation: NeverCancelled(), budget: budget)
        #expect(deadline.terminal == .deadlineExceeded)
        #expect(deadline.issues == [.denied, .deadlineExceeded])
    }

    @Test("PID/start identity changes are rejected but a label change alone is accepted")
    func processIdentityContract() async throws {
        let changed = ScriptedDarwinMemorySystem(
            clocks: [.success(reading(1))],
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [4], isTruncated: false)),
            identitySequence: [
                .success(identity(pid: 4, seconds: 1, name: "first")),
                .success(identity(pid: 4, seconds: 2, name: "first")),
            ],
            residents: [4: .success(10)]
        )
        let changedResult = await DarwinMemoryObservationAdapter(system: changed)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(changedResult.rows.isEmpty)
        #expect(changedResult.issues == [.identityChanged])

        let renamed = ScriptedDarwinMemorySystem(
            clocks: [.success(reading(1))],
            monotonic: Array(repeating: 1, count: 8),
            pids: .success(.init(pids: [4], isTruncated: false)),
            identitySequence: [
                .success(identity(pid: 4, name: "first")),
                .success(identity(pid: 4, name: "second")),
            ],
            residents: [4: .success(10)]
        )
        let renamedResult = await DarwinMemoryObservationAdapter(system: renamed)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(renamedResult.rows.map(\.label.value) == ["first"])
        #expect(renamedResult.issues.isEmpty)
    }

    @Test("wrong returned PID and malformed BSD start identity cannot become a row")
    func invalidIdentityIsRejected() async throws {
        for raw in [identity(pid: 2), identity(pid: 1, microseconds: 1_000_000)] {
            let system = ScriptedDarwinMemorySystem(
                clocks: [.success(reading(1))],
                monotonic: Array(repeating: 1, count: 8),
                pids: .success(.init(pids: [1], isTruncated: false)),
                identities: [1: .success(raw)],
                residents: [1: .success(1)]
            )
            let result = await DarwinMemoryObservationAdapter(system: system)
                .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
            #expect(result.rows.isEmpty)
            #expect(result.issues.contains(raw.pid == 1 ? .unreadable : .identityChanged))
        }
    }

    @Test("deadline preserves completed rows and never becomes cancellation")
    func deadlinePreservesPartialRows() async throws {
        let system = ScriptedDarwinMemorySystem(
            clocks: [.success(reading(1))],
            monotonic: [0, 0, 0, 0, 0, 0, 0, 501],
            pids: .success(.init(pids: [1, 2], isTruncated: false)),
            identities: [1: .success(identity(pid: 1)), 2: .success(identity(pid: 2))],
            residents: [1: .success(100), 2: .success(200)]
        )
        let budget = try SamplingBudget(maximumCandidates: 2, maximumRows: 2, maximumDurationNanoseconds: 500)
        let result = await DarwinMemoryObservationAdapter(system: system)
            .observeWorkload(cancellation: NeverCancelled(), budget: budget)

        #expect(result.terminal == .deadlineExceeded)
        #expect(result.issues.contains(.deadlineExceeded))
        #expect(result.rows.map(\.identity.pid) == [1])
        #expect(!system.calls.contains(.identity(2)))
    }

    @Test("a backwards monotonic reading fails closed as deadline")
    func backwardsClockIsDeadline() async throws {
        let system = ScriptedDarwinMemorySystem(monotonic: [10, 9])
        let result = await DarwinMemoryObservationAdapter(system: system)
            .observeWorkload(cancellation: NeverCancelled(), budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))
        #expect(result.terminal == .deadlineExceeded)
        #expect(result.issues == [.deadlineExceeded])
        #expect(!system.calls.contains(.listPIDs(1)))
    }

    @Test("one-shot cancellation is honored before every capability, sort, and emission", arguments: 1 ... 9)
    func workloadCancellationCheckpoints(check: Int) async throws {
        let system = ScriptedDarwinMemorySystem(
            clocks: [.success(reading(1))],
            monotonic: Array(repeating: 1, count: 12),
            pids: .success(.init(pids: [1], isTruncated: false)),
            identities: [1: .success(identity(pid: 1))],
            residents: [1: .success(1)]
        )
        let cancellation = ScriptedCancellation(cancelAtCheck: check)
        cancellation.onCancellationObserved = { system.markCancellationObserved() }
        let result = await DarwinMemoryObservationAdapter(system: system)
            .observeWorkload(cancellation: cancellation, budget: try SamplingBudget(maximumCandidates: 1, maximumRows: 1))

        #expect(result.terminal == .cancelled)
        #expect(result.rows.isEmpty)
        #expect(result.issues == [.cancelled])
        #expect(system.callsAfterCancellationObserved.isEmpty)
    }

    @Test("a later sample replaces rather than retains an earlier process row")
    func sampleDoesNotRetainStaleRows() async throws {
        let system = ScriptedDarwinMemorySystem(
            clocks: [.success(reading(1))],
            monotonic: Array(repeating: 1, count: 12),
            pids: .success(.init(pids: [1], isTruncated: false)),
            identities: [1: .success(identity(pid: 1))],
            residents: [1: .success(10)]
        )
        let adapter = DarwinMemoryObservationAdapter(system: system)
        let budget = try SamplingBudget(maximumCandidates: 1, maximumRows: 1)
        let first = await adapter.observeWorkload(cancellation: NeverCancelled(), budget: budget)
        system.pids = .success(.init(pids: [], isTruncated: false))
        system.refillMonotonic(Array(repeating: 2, count: 4))
        let second = await adapter.observeWorkload(cancellation: NeverCancelled(), budget: budget)
        #expect(first.rows.count == 1)
        #expect(second.rows.isEmpty)
    }
}

@Suite("Darwin workload integration")
struct DarwinWorkloadAdapterTests {
    @Test("workload issues make a valid memory sample partial")
    func workloadIssuePropagates() async {
        let fixture = completeSystem(start: reading(1))
        fixture.system.pids = .failure(.denied)
        let snapshot = await fixture.adapter.observe(cancellation: NeverCancelled())
        #expect(snapshot.outcome == .partial)
        #expect(snapshot.processIssues == [.denied])
        #expect(snapshot.issues.contains(.workload(.denied)))
    }

    @Test("deadline is surfaced as deadline while valid rows remain")
    func workloadDeadlineInSnapshot() async {
        let system = ScriptedDarwinMemorySystem(
            clocks: Array(repeating: .success(reading(1)), count: 6),
            monotonic: [0, 0, 0, 0, 0, 0, 0, 500_000_001],
            pressureEvent: (.normal, reading(1)),
            physicalMemory: .success(1),
            vm: .success(completeVM),
            swap: .success(.init(usedBytes: 0, totalBytes: 0)),
            pids: .success(.init(pids: [1, 2], isTruncated: false)),
            identities: [1: .success(identity(pid: 1)), 2: .success(identity(pid: 2))],
            residents: [1: .success(1), 2: .success(2)]
        )
        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: NeverCancelled())
        #expect(snapshot.outcome == .partial)
        #expect(snapshot.processes.map(\.identity.pid) == [1])
        #expect(snapshot.processIssues.contains(.deadlineExceeded))
        #expect(snapshot.issues.contains(.workload(.deadlineExceeded)))
    }

    @Test("an established deadline keeps rows and every issue when cancellation arrives later")
    func deadlinePrecedesLaterCancellation() async {
        let cancellation = ExternallyCancelled()
        let system = ScriptedDarwinMemorySystem(
            clocks: Array(repeating: .success(reading(1)), count: 5),
            monotonic: [0, 0, 0, 0, 0, 0, 0, 500_000_001],
            pressureEvent: (.normal, reading(1)),
            physicalMemory: .success(1),
            vm: .success(completeVM),
            swap: .success(.init(usedBytes: 0, totalBytes: 0)),
            pids: .success(.init(pids: [1, 2], isTruncated: true)),
            identities: [1: .success(identity(pid: 1)), 2: .success(identity(pid: 2))],
            residents: [1: .success(1), 2: .success(2)]
        )
        system.onMonotonicRead = { value in
            guard value > SamplingBudget.maximumDurationNanoseconds else { return }
            system.markDeadlineObserved()
            cancellation.request()
        }
        cancellation.onCancellationObserved = { system.markCancellationObserved() }

        let snapshot = await DarwinMemoryObservationAdapter(system: system)
            .observe(cancellation: cancellation)
        #expect(snapshot.outcome == .partial)
        #expect(snapshot.completedAt == .unavailable(.deadlineExceeded))
        #expect(snapshot.processes.map(\.identity.pid) == [1])
        #expect(snapshot.processIssues == [.truncated, .deadlineExceeded])
        #expect(snapshot.issues.contains(.workload(.unavailable)))
        #expect(snapshot.issues.contains(.workload(.deadlineExceeded)))
        #expect(system.callsAfterDeadlineObserved.isEmpty)
        #expect(system.callsAfterCancellationObserved.isEmpty)
    }
}

private func identity(
    pid: Int32,
    seconds: UInt64 = 1,
    microseconds: UInt64 = 0,
    name: String = "sample"
) -> RawProcessIdentity {
    .init(pid: pid, startTimeSeconds: seconds, startTimeMicroseconds: microseconds, displayName: name)
}

private func completeSystem(
    start: ClockReading,
    pressureEvent: (MemoryPressureLevel, ClockReading)? = (.normal, reading(1)),
    vm: Result<RawVMPageCounts, MemoryObservationFailure> = .success(completeVM)
) -> (system: ScriptedDarwinMemorySystem, adapter: DarwinMemoryObservationAdapter) {
    let system = ScriptedDarwinMemorySystem(
        clocks: [.success(start), .success(reading(2)), .success(reading(3)), .success(reading(4)), .success(reading(5))],
        monotonic: Array(repeating: start.observationInstant.monotonicNanoseconds, count: 12),
        pressureEvent: pressureEvent,
        physicalMemory: .success(16),
        vm: vm,
        swap: .success(.init(usedBytes: 1, totalBytes: 2))
    )
    return (system, DarwinMemoryObservationAdapter(system: system))
}

private final class NeverCancelled: MemoryObservationCancellation, @unchecked Sendable {
    func isCancellationRequested() async -> Bool { false }
}

private final class ScriptedCancellation: MemoryObservationCancellation, @unchecked Sendable {
    private(set) var checkCount = 0
    let cancelAtCheck: Int
    var onCancellationObserved: (() -> Void)?

    init(cancelAtCheck: Int) {
        self.cancelAtCheck = cancelAtCheck
    }

    func isCancellationRequested() async -> Bool {
        checkCount += 1
        let cancelled = checkCount >= cancelAtCheck
        if cancelled { onCancellationObserved?() }
        return cancelled
    }
}

private final class ExternallyCancelled: MemoryObservationCancellation, @unchecked Sendable {
    private var requested = false
    var onCancellationObserved: (() -> Void)?

    func request() { requested = true }

    func isCancellationRequested() async -> Bool {
        if requested { onCancellationObserved?() }
        return requested
    }
}

private final class ScriptedDarwinMemorySystem: DarwinMemorySystem, @unchecked Sendable {
    enum Call: Equatable {
        case installPressureHandler
        case activatePressureSource
        case stopPressureSource
        case clock
        case monotonic
        case physicalMemory
        case vm
        case swap
        case listPIDs(Int)
        case identity(Int32)
        case resident(Int32)
    }

    private(set) var calls: [Call] = []
    private(set) var callsAfterCancellationObserved: [Call] = []
    private(set) var callsAfterDeadlineObserved: [Call] = []
    private var cancellationWasObserved = false
    private var deadlineWasObserved = false
    private var clocks: [Result<ClockReading, MemoryObservationFailure>]
    private var monotonic: [UInt64]
    private let fallbackClock: Result<ClockReading, MemoryObservationFailure>
    private let fallbackMonotonic: UInt64
    private var pressureEvents: [(MemoryPressureLevel, ClockReading)?]
    private let physicalMemory: Result<UInt64, MemoryObservationFailure>
    private let vm: Result<RawVMPageCounts, MemoryObservationFailure>
    private let swap: Result<RawSwapUsage, MemoryObservationFailure>
    var pids: Result<RawPIDList, WorkloadReadFailure>
    private var identities: [Int32: Result<RawProcessIdentity, WorkloadReadFailure>]
    private var identitySequence: [Result<RawProcessIdentity, WorkloadReadFailure>]
    private let residents: [Int32: Result<UInt64, WorkloadReadFailure>]
    private var storedPressureHandler: (@Sendable (MemoryPressureLevel, ClockReading) -> Void)?
    var onMonotonicRead: ((UInt64) -> Void)?
    var onInstallPressureHandler: (() -> Void)?

    init(
        clocks: [Result<ClockReading, MemoryObservationFailure>] = [],
        monotonic: [UInt64] = [],
        pressureEvent: (MemoryPressureLevel, ClockReading)? = nil,
        physicalMemory: Result<UInt64, MemoryObservationFailure> = .failure(.unavailable),
        vm: Result<RawVMPageCounts, MemoryObservationFailure> = .failure(.unavailable),
        swap: Result<RawSwapUsage, MemoryObservationFailure> = .failure(.unavailable),
        pids: Result<RawPIDList, WorkloadReadFailure> = .success(.init(pids: [], isTruncated: false)),
        identities: [Int32: Result<RawProcessIdentity, WorkloadReadFailure>] = [:],
        identitySequence: [Result<RawProcessIdentity, WorkloadReadFailure>] = [],
        residents: [Int32: Result<UInt64, WorkloadReadFailure>] = [:]
    ) {
        self.clocks = clocks
        self.monotonic = monotonic
        fallbackClock = clocks.last ?? .success(zeroReading)
        fallbackMonotonic = monotonic.last ?? 0
        pressureEvents = [pressureEvent]
        self.physicalMemory = physicalMemory
        self.vm = vm
        self.swap = swap
        self.pids = pids
        self.identities = identities
        self.identitySequence = identitySequence
        self.residents = residents
    }

    func markCancellationObserved() { cancellationWasObserved = true }
    func markDeadlineObserved() { deadlineWasObserved = true }
    func refillMonotonic(_ values: [UInt64]) { monotonic.append(contentsOf: values) }

    private func record(_ call: Call) {
        calls.append(call)
        if cancellationWasObserved { callsAfterCancellationObserved.append(call) }
        if deadlineWasObserved { callsAfterDeadlineObserved.append(call) }
    }

    func installPressureHandler(_ handler: @escaping @Sendable (MemoryPressureLevel, ClockReading) -> Void) {
        record(.installPressureHandler)
        storedPressureHandler = handler
        onInstallPressureHandler?()
    }

    func activatePressureSource() {
        record(.activatePressureSource)
        if !pressureEvents.isEmpty, let pressureEvent = pressureEvents.removeFirst() {
            storedPressureHandler?(pressureEvent.0, pressureEvent.1)
        }
    }

    func stopPressureSource() {
        record(.stopPressureSource)
        storedPressureHandler = nil
    }

    func clockReading() -> Result<ClockReading, MemoryObservationFailure> {
        record(.clock)
        return clocks.isEmpty ? fallbackClock : clocks.removeFirst()
    }

    func monotonicNanoseconds() -> UInt64 {
        record(.monotonic)
        let value = monotonic.isEmpty ? fallbackMonotonic : monotonic.removeFirst()
        onMonotonicRead?(value)
        return value
    }

    func physicalMemoryBytes() -> Result<UInt64, MemoryObservationFailure> {
        record(.physicalMemory)
        return physicalMemory
    }

    func vmPageCounts() -> Result<RawVMPageCounts, MemoryObservationFailure> {
        record(.vm)
        return vm
    }

    func swapUsage() -> Result<RawSwapUsage, MemoryObservationFailure> {
        record(.swap)
        return swap
    }

    func listPIDs(maximumCandidates: Int) -> Result<RawPIDList, WorkloadReadFailure> {
        record(.listPIDs(maximumCandidates))
        return pids
    }

    func processIdentity(pid: Int32) -> Result<RawProcessIdentity, WorkloadReadFailure> {
        record(.identity(pid))
        if !identitySequence.isEmpty { return identitySequence.removeFirst() }
        return identities[pid] ?? .failure(.unreadable)
    }

    func residentBytes(pid: Int32) -> Result<UInt64, WorkloadReadFailure> {
        record(.resident(pid))
        return residents[pid] ?? .failure(.unreadable)
    }
}
