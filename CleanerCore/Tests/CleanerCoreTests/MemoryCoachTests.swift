import Foundation
import Testing

@testable import CleanerCore

private let coachNow = clockReading(400_000_000_000)
private let coachRecent = clockReading(399_000_000_000)

@Suite("Local workload evidence")
struct LocalWorkloadEvidenceTests {
    @Test
    func exactFreshCompletedIdentityIsConfirmed() throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let record = CompletedLocalInventoryEvidence(
            evidenceID: .init(7),
            toolFamily: .localInference,
            completedAt: coachRecent,
            sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )

        let context = LocalWorkloadEvidenceProducer(completedInventory: [record])
            .context(sessionID: .init(42), process: process)

        #expect(
            context == .confirmed(
                identity: .init(sessionID: .init(42), processIdentity: process.identity),
                toolFamily: .localInference,
                evidenceID: .init(7)
            )
        )
    }

    @Test
    func shippedExactIdentityMapProducesInferenceWithoutInventoryProvider() throws {
        let process = try processEvidence(label: "ollama")

        let context = LocalWorkloadEvidenceProducer()
            .context(sessionID: .init(42), process: process)

        #expect(
            context == .inferred(
                identity: .init(sessionID: .init(42), processIdentity: process.identity),
                toolFamily: .ollama
            )
        )
    }

    @Test(arguments: shippedIdentityExpectations)
    fileprivate func shippedMapIsClosedAndExact(_ expectation: ShippedIdentityExpectation) throws {
        let context = LocalWorkloadEvidenceProducer(completedInventory: [])
            .context(
                sessionID: .init(42),
                process: try processEvidence(label: expectation.label)
            )

        switch context {
        case let .inferred(_, toolFamily):
            #expect(toolFamily == expectation.toolFamily)
        case .confirmed, .absent:
            Issue.record("An exact shipped identity must be inference only")
        }
    }

    // C6 broadened family inference to case-insensitive substrings, so
    // "Ollama" / "ollama " now infer .ollama (advisory only). Generic runtime
    // names that contain no known tool keyword still stay absent.
    @Test(arguments: ["python", "node", "unknown-local-tool"])
    func nearMatchesAndGenericRuntimeNamesStayAbsent(_ label: String) throws {
        let process = try processEvidence(label: label)
        let context = LocalWorkloadEvidenceProducer(completedInventory: [])
            .context(sessionID: .init(42), process: process)

        #expect(
            context == .absent(
                identity: .init(sessionID: .init(42), processIdentity: process.identity),
                reason: .unknownProcessIdentity
            )
        )
    }

    @Test
    func staleInventoryForUnknownIdentityIsAbsent() throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let stale = clockReading(99_000_000_000)
        let record = CompletedLocalInventoryEvidence(
            evidenceID: .init(8),
            toolFamily: .localInference,
            completedAt: stale,
            sourceObservedAt: stale,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )

        let context = LocalWorkloadEvidenceProducer(completedInventory: [record])
            .context(sessionID: .init(42), process: process)

        #expect(absenceReason(context) == .staleCompletedInventory)
    }

    @Test(arguments: identityMismatchRecords)
    func sessionPidAndStartIdentityMismatchRemainAbsent(
        _ makeRecord: @Sendable (ProcessMemoryEvidence) -> CompletedLocalInventoryEvidence
    ) throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let context = LocalWorkloadEvidenceProducer(completedInventory: [makeRecord(process)])
            .context(sessionID: .init(42), process: process)

        #expect(absenceReason(context) == .identityMismatch)
    }

    @Test
    func futureOrReversedInventoryTimingCannotConfirm() throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let future = clockReading(401_000_000_000)
        let reversed = CompletedLocalInventoryEvidence(
            evidenceID: .init(9),
            toolFamily: .localInference,
            completedAt: coachRecent,
            sourceObservedAt: coachNow,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )
        let futureRecord = CompletedLocalInventoryEvidence(
            evidenceID: .init(10),
            toolFamily: .localInference,
            completedAt: future,
            sourceObservedAt: future,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )

        for record in [reversed, futureRecord] {
            let context = LocalWorkloadEvidenceProducer(completedInventory: [record])
                .context(sessionID: .init(42), process: process)
            #expect(absenceReason(context) == .invalidInventoryTiming)
        }
    }

    @Test
    func conflictingFreshInventoryForSameObservedIdentityFailsClosed() throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let first = CompletedLocalInventoryEvidence(
            evidenceID: .init(30),
            toolFamily: .ollama,
            completedAt: coachRecent,
            sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )
        let conflictingTool = CompletedLocalInventoryEvidence(
            evidenceID: .init(31),
            toolFamily: .lmStudio,
            completedAt: coachRecent,
            sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )
        let conflictingEvidenceID = CompletedLocalInventoryEvidence(
            evidenceID: .init(32),
            toolFamily: .ollama,
            completedAt: coachRecent,
            sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )

        for records in [[first, conflictingTool], [conflictingTool, first], [first, conflictingEvidenceID]] {
            let context = LocalWorkloadEvidenceProducer(completedInventory: records)
                .context(sessionID: .init(42), process: process)

            #expect(absenceReason(context) == .conflictingInventoryEvidence)
        }
    }

    @Test
    func fixedMapIsTruthfulFallbackWhenMatchingInventoryIsStale() throws {
        let process = try processEvidence(label: "ollama")
        let stale = clockReading(1)
        let record = CompletedLocalInventoryEvidence(
            evidenceID: .init(11),
            toolFamily: .ollama,
            completedAt: stale,
            sourceObservedAt: stale,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )

        let context = LocalWorkloadEvidenceProducer(completedInventory: [record])
            .context(sessionID: .init(42), process: process)

        #expect(
            context == .inferred(
                identity: .init(sessionID: .init(42), processIdentity: process.identity),
                toolFamily: .ollama
            )
        )
    }

    @Test
    func conflictingFreshInventoryEvidenceFailsClosedRegardlessOfInputOrder() throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let localInference = CompletedLocalInventoryEvidence(
            evidenceID: .init(14),
            toolFamily: .localInference,
            completedAt: coachRecent,
            sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )
        let ollama = CompletedLocalInventoryEvidence(
            evidenceID: .init(15),
            toolFamily: .ollama,
            completedAt: coachRecent,
            sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )

        for records in [[localInference, ollama], [ollama, localInference]] {
            let context = LocalWorkloadEvidenceProducer(completedInventory: records)
                .context(sessionID: .init(42), process: process)
            #expect(absenceReason(context) == .conflictingInventoryEvidence)
        }
    }

    @Test
    func oversizedCompletedInventoryFailsClosedBeforeAnyConfirmationOrInference() throws {
        let process = try processEvidence(label: "ollama")
        let oversized = (0...LocalWorkloadEvidenceProducer.maximumCompletedInventoryRecords).map { index in
            CompletedLocalInventoryEvidence(
                evidenceID: .init(UInt64(index)),
                toolFamily: .ollama,
                completedAt: coachRecent,
                sourceObservedAt: coachRecent,
                observationSessionID: .init(42),
                processIdentity: process.identity
            )
        }

        let context = LocalWorkloadEvidenceProducer(completedInventory: oversized)
            .context(sessionID: .init(42), process: process)

        #expect(absenceReason(context) == .inventoryRecordLimitExceeded)
    }

    @Test
    func exactCompletedInventoryRecordLimitRemainsUsable() throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let record = CompletedLocalInventoryEvidence(
            evidenceID: .init(16),
            toolFamily: .localInference,
            completedAt: coachRecent,
            sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: process.identity
        )

        let context = LocalWorkloadEvidenceProducer(
            completedInventory: Array(
                repeating: record,
                count: LocalWorkloadEvidenceProducer.maximumCompletedInventoryRecords
            )
        ).context(sessionID: .init(42), process: process)

        #expect(
            context == .confirmed(
                identity: .init(sessionID: .init(42), processIdentity: process.identity),
                toolFamily: .localInference,
                evidenceID: .init(16)
            )
        )
    }

    @Test
    func workloadSourcesCarryOnlyClosedLocalEvidenceAndNoEffectAuthority() throws {
        let source = try memoryCoachSourceText([
            "WorkloadContext.swift",
            "MemoryCoachingRules.swift",
        ])
        let forbidden = [
            "import Foundation",
            "import Darwin",
            "import Dispatch",
            "import AppKit",
            "import SwiftUI",
            "URLSession",
            "FileManager",
            "Process(",
            "ProcessInfo",
            "arguments",
            "environment",
            "executablePath",
            "workingDirectory",
            "userName",
            "modelName",
            "repositoryName",
            "promptText",
            "contentText",
            "rawText",
            "ExecutionPort",
            "PolicyPort",
            "ReceiptPort",
            "terminate(",
            "setpriority",
            "openSystemSettings",
            "claimedRecoveredBytes",
        ]

        for token in forbidden {
            #expect(!source.contains(token))
        }
        #expect(!source.contains("public let context: WorkloadContext"))
    }

    @Test
    func processDisplayLabelRejectsNonDisplayUnicodeCategories() {
        #expect(ProcessDisplayLabel("ollama\u{202E}cod") == nil)
        #expect(ProcessDisplayLabel("LM\u{200F} Studio") == nil)
        #expect(ProcessDisplayLabel("line\u{2028}break") == nil)
        #expect(ProcessDisplayLabel("paragraph\u{2029}break") == nil)
        #expect(ProcessDisplayLabel("private\u{E000}glyph") == nil)
        #expect(ProcessDisplayLabel("mlx_lm.server")?.value == "mlx_lm.server")
    }
}

@Suite("Memory coaching rules")
struct MemoryCoachingRulesTests {
    @Test(arguments: pressureExpectations)
    fileprivate func pressureUsesOnlyExactSourceState(_ expectation: PressureExpectation) throws {
        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(pressure: expectation.pressure),
            contexts: [:]
        )

        #expect(presentation.explanation.pressureKey == expectation.key)
        #expect(presentation.explanation.suggestionKeys == expectation.suggestions)
        #expect(presentation.pressure == expectation.pressure)
    }

    @Test(arguments: outcomeExpectations)
    fileprivate func completePartialTruncatedCancelledAndUnavailableStayDistinct(
        _ expectation: OutcomeExpectation
    ) throws {
        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(
                processIssues: expectation.processIssues,
                outcome: expectation.outcome
            ),
            contexts: [:]
        )

        #expect(presentation.completeness == expectation.completeness)
        #expect(presentation.explanation.completenessKey == expectation.key)
    }

    @Test(arguments: unavailableFieldExpectations)
    fileprivate func everyMemoryFieldRetainsIndependentUnavailableEvidence(
        _ expectation: UnavailableFieldExpectation
    ) throws {
        let unavailable = MemoryField<UInt64>.unavailable(expectation.reason)
        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try expectation.snapshot(unavailable),
            contexts: [:]
        )

        #expect(expectation.project(presentation.fields) == .unavailable(expectation.reason))
    }

    @Test
    func cacheExplanationIsManagedContextOrExplicitlyUnavailable() throws {
        let available = MemoryCoachingRules().evaluate(snapshot: try snapshot(), contexts: [:])
        #expect(available.explanation.cacheKey == .cacheManagedByMacOS)

        let unavailable = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(
                vm: .init(
                    activeBytes: .observed(1, observedAt: coachNow),
                    inactiveBytes: .unavailable(.unavailable),
                    wiredBytes: .observed(1, observedAt: coachNow),
                    compressedBytes: .observed(1, observedAt: coachNow),
                    purgeableBytes: .unavailable(.unavailable)
                )
            ),
            contexts: [:]
        )
        #expect(unavailable.explanation.cacheKey == .cacheUnavailable)
    }

    @Test
    func processRowsAreCurrentBoundedOrderedAndEvidenceLabelled() throws {
        let low = try processEvidence(pid: 21, label: "unmapped-local-tool", residentBytes: 2)
        let high = try processEvidence(pid: 22, label: "ollama", residentBytes: 9)
        let confirmed = WorkloadContext.confirmed(
            identity: .init(sessionID: .init(42), processIdentity: low.identity),
            toolFamily: .localInference,
            evidenceID: .init(12)
        )
        let inferred = WorkloadContext.inferred(
            identity: .init(sessionID: .init(42), processIdentity: high.identity),
            toolFamily: .ollama
        )

        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processes: [low, high]),
            contexts: [low.identity: confirmed, high.identity: inferred]
        )

        #expect(presentation.processes.map(\.pid) == [22, 21])
        #expect(presentation.processes.map(\.residentBytes) == [9, 2])
        #expect(presentation.processes.map(\.contextKey) == [.contextInferred, .contextConfirmed])
        #expect(presentation.processes.map { $0.label.value } == ["ollama", "unmapped-local-tool"])
    }

    @Test
    func hostileProcessArraysAreCappedBeforeSortingAndReportedAsTruncated() throws {
        let candidates = try (0 ... SamplingBudget.maximumRows).map { offset in
            try processEvidence(
                pid: Int32(20 + offset),
                label: "process-\(offset)",
                residentBytes: UInt64(offset)
            )
        }
        let budget = try SamplingBudget(maximumRows: 2)

        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processes: candidates, samplingBudget: budget),
            contexts: [:]
        )

        #expect(presentation.processes.count == 2)
        #expect(presentation.processes.map(\.pid) == [30, 29])
        #expect(presentation.completeness == .truncated)
        #expect(presentation.explanation.completenessKey == .sampleTruncated)
        #expect(presentation.processIssueKeys.contains(.processTruncated))
    }

    @Test
    func mismatchedContextIsDowngradedToAbsent() throws {
        let process = try processEvidence(label: "unmapped-local-tool")
        let wrongSession = WorkloadContext.confirmed(
            identity: .init(sessionID: .init(41), processIdentity: process.identity),
            toolFamily: .localInference,
            evidenceID: .init(13)
        )

        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processes: [process]),
            contexts: [process.identity: wrongSession]
        )

        #expect(presentation.processes.first?.contextKey == .contextAbsent)
    }

    @Test(arguments: processIssueExpectations)
    fileprivate func everyProcessIssueHasAClosedPrivacySafeMessage(
        _ expectation: ProcessIssueExpectation
    ) throws {
        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processIssues: [expectation.issue], outcome: .partial),
            contexts: [:]
        )

        #expect(presentation.processIssueKeys == [expectation.key])
    }

    @Test
    func aNewEmptyOrFailedSnapshotCannotCarryOldRows() throws {
        let previous = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processes: [processEvidence(label: "ollama")]),
            contexts: [:]
        )
        let replacement = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(
                pressure: .unavailableNoFreshEvent,
                processes: [],
                processIssues: [.cancelled],
                outcome: .cancelled
            ),
            contexts: [:]
        )

        #expect(previous.processes.count == 1)
        #expect(replacement.processes.isEmpty)
        #expect(replacement.completeness == .cancelled)
        #expect(replacement.pressure == .unavailableNoFreshEvent)
    }

    @Test
    func hostileOversizedProcessArrayIsCappedAndReportedAsTruncated() throws {
        let processes = try (1...SamplingBudget.maximumRows + 3).map { index in
            try processEvidence(
                pid: Int32(index),
                label: "process-\(index)",
                residentBytes: UInt64(index)
            )
        }

        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processes: processes),
            contexts: [:]
        )

        #expect(presentation.processes.count == SamplingBudget.maximumRows)
        #expect(presentation.processIssueKeys.contains(.processTruncated))
        #expect(presentation.completeness == .truncated)
        #expect(presentation.processes.map(\.residentBytes) == Array((4...13).reversed()).map(UInt64.init))
    }

    @Test
    func processInputBeyondCandidateBudgetIsBoundedAndMarkedInvalidAndTruncated() throws {
        let process = try processEvidence(pid: 20, label: "repeated-process", residentBytes: 1)
        let processes = Array(
            repeating: process,
            count: SamplingBudget.maximumCandidates + 1
        )

        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processes: processes),
            contexts: [:]
        )

        #expect(presentation.processes.count == SamplingBudget.maximumRows)
        #expect(presentation.completeness == .truncated)
        #expect(presentation.processIssueKeys.contains(.processTruncated))
        #expect(presentation.processIssueKeys.contains(.processInvalidSource))
    }

    @Test(arguments: [MemorySnapshotOutcome.cancelled, .unavailable])
    fileprivate func cancelledOrUnavailableSnapshotsNeverProjectSuppliedRows(
        _ outcome: MemorySnapshotOutcome
    ) throws {
        let process = try processEvidence(pid: 20, label: "unexpected-row", residentBytes: 1)
        let processes = Array(
            repeating: process,
            count: SamplingBudget.maximumRows + 1
        )

        let presentation = MemoryCoachingRules().evaluate(
            snapshot: try snapshot(processes: processes, outcome: outcome),
            contexts: [:]
        )

        #expect(presentation.processes.isEmpty)
        #expect(
            presentation.completeness == (outcome == .cancelled ? .cancelled : .unavailable)
        )
        #expect(!presentation.processIssueKeys.contains(.processTruncated))
    }
}

private struct ShippedIdentityExpectation: Sendable {
    let label: String
    let toolFamily: LocalWorkloadToolFamily
}

private let shippedIdentityExpectations: [ShippedIdentityExpectation] = [
    .init(label: "ollama", toolFamily: .ollama),
    .init(label: "LM Studio", toolFamily: .lmStudio),
    .init(label: "mlx_lm.server", toolFamily: .mlx),
    .init(label: "llama-server", toolFamily: .localInference),
]

private let identityMismatchRecords: [@Sendable (ProcessMemoryEvidence) -> CompletedLocalInventoryEvidence] = [
    { process in
        .init(
            evidenceID: .init(20), toolFamily: .localInference,
            completedAt: coachRecent, sourceObservedAt: coachRecent,
            observationSessionID: .init(99), processIdentity: process.identity
        )
    },
    { process in
        .init(
            evidenceID: .init(21), toolFamily: .localInference,
            completedAt: coachRecent, sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: ProcessObservationIdentity(
                pid: process.identity.pid + 1,
                startTimeSeconds: process.identity.startTimeSeconds,
                startTimeMicroseconds: process.identity.startTimeMicroseconds
            )
        )
    },
    { process in
        .init(
            evidenceID: .init(22), toolFamily: .localInference,
            completedAt: coachRecent, sourceObservedAt: coachRecent,
            observationSessionID: .init(42),
            processIdentity: ProcessObservationIdentity(
                pid: process.identity.pid,
                startTimeSeconds: process.identity.startTimeSeconds + 1,
                startTimeMicroseconds: process.identity.startTimeMicroseconds
            )
        )
    },
]

private struct PressureExpectation: Sendable {
    let pressure: MemoryPressureObservation
    let key: CoachingMessageKey
    let suggestions: [CoachingMessageKey]
}

private let pressureExpectations: [PressureExpectation] = [
    .init(pressure: .observed(.normal, observedAt: coachNow), key: .pressureNormal, suggestions: []),
    .init(
        pressure: .observed(.warning, observedAt: coachNow),
        key: .pressureWarning,
        suggestions: [.guidanceCloseKnownApp, .guidanceReduceWorkload]
    ),
    .init(
        pressure: .observed(.critical, observedAt: coachNow),
        key: .pressureCritical,
        suggestions: [.guidanceCloseKnownApp, .guidanceReduceWorkload]
    ),
    .init(
        pressure: .unavailableNoFreshEvent,
        key: .pressureUnavailable,
        suggestions: [.guidanceRefreshObservation]
    ),
    .init(
        pressure: .stale(.warning, observedAt: coachRecent),
        key: .pressureStale,
        suggestions: [.guidanceRefreshObservation]
    ),
]

private struct OutcomeExpectation: Sendable {
    let outcome: MemorySnapshotOutcome
    let processIssues: [ProcessObservationIssue]
    let completeness: MemoryCoachCompleteness
    let key: CoachingMessageKey
}

private let outcomeExpectations: [OutcomeExpectation] = [
    .init(outcome: .complete, processIssues: [], completeness: .complete, key: .sampleComplete),
    .init(outcome: .partial, processIssues: [.denied], completeness: .partial, key: .samplePartial),
    .init(outcome: .partial, processIssues: [.truncated], completeness: .truncated, key: .sampleTruncated),
    .init(outcome: .cancelled, processIssues: [.cancelled], completeness: .cancelled, key: .sampleCancelled),
    .init(outcome: .unavailable, processIssues: [], completeness: .unavailable, key: .sampleUnavailable),
]

private struct UnavailableFieldExpectation: Sendable {
    let reason: MemoryObservationUnavailable
    let snapshot: @Sendable (MemoryField<UInt64>) throws -> MemoryCoachSnapshot
    let project: @Sendable (MemoryCoachFieldPresentation) -> MemoryCoachValuePresentation
}

private let unavailableFieldExpectations: [UnavailableFieldExpectation] = [
    .init(reason: .denied, snapshot: { try snapshot(physicalMemory: $0) }, project: { $0.physicalMemory }),
    .init(reason: .overflow, snapshot: { try snapshot(vm: replacingVM(\.activeBytes, with: $0)) }, project: { $0.activeMemory }),
    .init(reason: .shortRead, snapshot: { try snapshot(vm: replacingVM(\.inactiveBytes, with: $0)) }, project: { $0.inactiveMemory }),
    .init(reason: .malformedSource, snapshot: { try snapshot(vm: replacingVM(\.wiredBytes, with: $0)) }, project: { $0.wiredMemory }),
    .init(reason: .unavailable, snapshot: { try snapshot(vm: replacingVM(\.compressedBytes, with: $0)) }, project: { $0.compressedMemory }),
    .init(reason: .stale, snapshot: { try snapshot(vm: replacingVM(\.purgeableBytes, with: $0)) }, project: { $0.purgeableMemory }),
    .init(reason: .deadlineExceeded, snapshot: { try snapshot(swap: .init(usedBytes: $0, totalBytes: .observed(2, observedAt: coachNow))) }, project: { $0.swapUsed }),
    .init(reason: .unavailable, snapshot: { try snapshot(swap: .init(usedBytes: .observed(1, observedAt: coachNow), totalBytes: $0)) }, project: { $0.swapTotal }),
]

private struct ProcessIssueExpectation: Sendable {
    let issue: ProcessObservationIssue
    let key: CoachingMessageKey
}

private let processIssueExpectations: [ProcessIssueExpectation] = [
    .init(issue: .denied, key: .processDenied),
    .init(issue: .exited, key: .processExited),
    .init(issue: .shortRead, key: .processShortRead),
    .init(issue: .identityChanged, key: .processIdentityChanged),
    .init(issue: .unreadable, key: .processUnreadable),
    .init(issue: .truncated, key: .processTruncated),
    .init(issue: .deadlineExceeded, key: .processDeadlineExceeded),
    .init(issue: .cancelled, key: .processCancelled),
    .init(issue: .invalidSource, key: .processInvalidSource),
]

private func clockReading(_ monotonicNanoseconds: UInt64) -> ClockReading {
    .init(
        observationInstant: .init(monotonicNanoseconds: monotonicNanoseconds),
        wallClockInstant: .init(unixNanoseconds: Int64(clamping: monotonicNanoseconds))
    )
}

private func processEvidence(
    pid: Int32 = 20,
    label: String,
    residentBytes: UInt64 = 4
) throws -> ProcessMemoryEvidence {
    let identity = try #require(
        ProcessObservationIdentity(pid: pid, startTimeSeconds: 3, startTimeMicroseconds: 4)
    )
    let displayLabel = try #require(ProcessDisplayLabel(label))
    return .init(
        identity: identity,
        label: displayLabel,
        residentBytes: residentBytes,
        observedAt: coachNow
    )
}

private func snapshot(
    pressure: MemoryPressureObservation = .observed(.normal, observedAt: coachNow),
    physicalMemory: MemoryField<UInt64> = .observed(64, observedAt: coachNow),
    vm: MemoryVMContext = observedVM,
    swap: MemorySwapContext = .init(
        usedBytes: .observed(1, observedAt: coachNow),
        totalBytes: .observed(2, observedAt: coachNow)
    ),
    processes: [ProcessMemoryEvidence] = [],
    processIssues: [ProcessObservationIssue] = [],
    samplingBudget: SamplingBudget = .standard,
    outcome: MemorySnapshotOutcome = .complete
) throws -> MemoryCoachSnapshot {
    .init(
        sessionID: .init(42),
        samplingBudget: samplingBudget,
        startedAt: .observed(coachRecent),
        completedAt: .observed(coachNow),
        pressure: pressure,
        physicalMemory: physicalMemory,
        vm: vm,
        swap: swap,
        processes: processes,
        processIssues: processIssues,
        issues: [],
        outcome: outcome
    )
}

private let observedVM = MemoryVMContext(
    activeBytes: .observed(10, observedAt: coachNow),
    inactiveBytes: .observed(11, observedAt: coachNow),
    wiredBytes: .observed(12, observedAt: coachNow),
    compressedBytes: .observed(13, observedAt: coachNow),
    purgeableBytes: .observed(14, observedAt: coachNow)
)

private func replacingVM(
    _ keyPath: WritableKeyPath<MutableVMContext, MemoryField<UInt64>>,
    with value: MemoryField<UInt64>
) -> MemoryVMContext {
    var mutable = MutableVMContext(observedVM)
    mutable[keyPath: keyPath] = value
    return mutable.value
}

private struct MutableVMContext {
    var activeBytes: MemoryField<UInt64>
    var inactiveBytes: MemoryField<UInt64>
    var wiredBytes: MemoryField<UInt64>
    var compressedBytes: MemoryField<UInt64>
    var purgeableBytes: MemoryField<UInt64>

    init(_ value: MemoryVMContext) {
        activeBytes = value.activeBytes
        inactiveBytes = value.inactiveBytes
        wiredBytes = value.wiredBytes
        compressedBytes = value.compressedBytes
        purgeableBytes = value.purgeableBytes
    }

    var value: MemoryVMContext {
        .init(
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            purgeableBytes: purgeableBytes
        )
    }
}

private func absenceReason(_ context: WorkloadContext?) -> WorkloadContextAbsenceReason? {
    guard let context else { return nil }
    return switch context {
    case .confirmed, .inferred:
        nil
    case let .absent(_, reason):
        reason
    }
}

private func memoryCoachSourceText(_ fileNames: [String]) throws -> String {
    let currentFile = URL(fileURLWithPath: #filePath)
    let packageRoot = currentFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try fileNames.map { fileName in
        try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("CleanerCore")
                .appendingPathComponent("MemoryCoach")
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }.joined(separator: "\n")
}
