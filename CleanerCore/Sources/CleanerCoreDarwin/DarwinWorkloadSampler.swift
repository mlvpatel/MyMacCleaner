import CleanerCore

extension DarwinMemoryObservationAdapter {
    enum WorkloadTerminal: Equatable, Sendable {
        case complete
        case cancelled
        case deadlineExceeded
    }

    struct WorkloadObservation: Equatable, Sendable {
        let rows: [ProcessMemoryEvidence]
        let issues: [ProcessObservationIssue]
        let terminal: WorkloadTerminal
    }

    private enum SamplingCheckpoint {
        case proceed
        case cancelled
        case deadlineExceeded
    }

    func observeWorkload(
        cancellation: any MemoryObservationCancellation,
        budget: SamplingBudget
    ) async -> WorkloadObservation {
        guard !(await cancellation.isCancellationRequested()) else {
            return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
        }
        let startedAt = system.monotonicNanoseconds()

        switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
        case .cancelled:
            return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
        case .deadlineExceeded:
            return .init(rows: [], issues: [.deadlineExceeded], terminal: .deadlineExceeded)
        case .proceed:
            break
        }

        let list: RawPIDList
        switch system.listPIDs(maximumCandidates: budget.maximumCandidates) {
        case let .success(value):
            list = value
        case let .failure(failure):
            return await emitEmptyAfterCheckpoint(
                issues: [issue(for: failure)],
                cancellation: cancellation,
                startedAt: startedAt,
                budget: budget
            )
        }

        guard list.pids.count <= budget.maximumCandidates,
              list.pids.allSatisfy({ $0 > 0 })
        else {
            return await emitEmptyAfterCheckpoint(
                issues: [.invalidSource],
                cancellation: cancellation,
                startedAt: startedAt,
                budget: budget
            )
        }

        var rows: [ProcessMemoryEvidence] = []
        var issues: [ProcessObservationIssue] = list.isTruncated ? [.truncated] : []

        for pid in list.pids {
            switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
            case .cancelled:
                return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
            case .deadlineExceeded:
                return deadlineResult(rows: rows, issues: issues, maximumRows: budget.maximumRows)
            case .proceed:
                break
            }

            let before: RawProcessIdentity
            switch system.processIdentity(pid: pid) {
            case let .success(value):
                before = value
            case let .failure(failure):
                Self.appendUnique(issue(for: failure), to: &issues)
                continue
            }
            guard before.pid == pid else {
                Self.appendUnique(.identityChanged, to: &issues)
                continue
            }

            switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
            case .cancelled:
                return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
            case .deadlineExceeded:
                return deadlineResult(rows: rows, issues: issues, maximumRows: budget.maximumRows)
            case .proceed:
                break
            }

            let resident: UInt64
            switch system.residentBytes(pid: pid) {
            case let .success(value):
                resident = value
            case let .failure(failure):
                Self.appendUnique(issue(for: failure), to: &issues)
                continue
            }

            switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
            case .cancelled:
                return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
            case .deadlineExceeded:
                return deadlineResult(rows: rows, issues: issues, maximumRows: budget.maximumRows)
            case .proceed:
                break
            }

            let after: RawProcessIdentity
            switch system.processIdentity(pid: pid) {
            case let .success(value):
                after = value
            case let .failure(failure):
                Self.appendUnique(issue(for: failure), to: &issues)
                continue
            }

            guard after.pid == pid,
                  before.startTimeSeconds == after.startTimeSeconds,
                  before.startTimeMicroseconds == after.startTimeMicroseconds
            else {
                Self.appendUnique(.identityChanged, to: &issues)
                continue
            }
            guard let identity = ProcessObservationIdentity(
                pid: before.pid,
                startTimeSeconds: before.startTimeSeconds,
                startTimeMicroseconds: before.startTimeMicroseconds
            ) else {
                Self.appendUnique(.unreadable, to: &issues)
                continue
            }

            switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
            case .cancelled:
                return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
            case .deadlineExceeded:
                return deadlineResult(rows: rows, issues: issues, maximumRows: budget.maximumRows)
            case .proceed:
                break
            }

            let observedAt: ClockReading
            switch system.clockReading() {
            case let .success(reading):
                observedAt = reading
            case .failure:
                Self.appendUnique(.unreadable, to: &issues)
                continue
            }

            let row = ProcessMemoryEvidence(
                identity: identity,
                label: sanitizeLabel(before.displayName),
                residentBytes: resident,
                observedAt: observedAt
            )

            switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
            case .cancelled:
                return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
            case .deadlineExceeded:
                return deadlineResult(rows: rows, issues: issues, maximumRows: budget.maximumRows)
            case .proceed:
                rows.append(row)
                rows.sort(by: Self.precedes)
                if rows.count > budget.maximumRows {
                    rows.removeLast(rows.count - budget.maximumRows)
                }
            }
        }

        switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
        case .cancelled:
            return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
        case .deadlineExceeded:
            return deadlineResult(rows: rows, issues: issues, maximumRows: budget.maximumRows)
        case .proceed:
            rows.sort(by: Self.precedes)
        }

        switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
        case .cancelled:
            return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
        case .deadlineExceeded:
            return deadlineResult(rows: rows, issues: issues, maximumRows: budget.maximumRows)
        case .proceed:
            return .init(rows: rows, issues: issues, terminal: .complete)
        }
    }

    private func checkpoint(
        cancellation: any MemoryObservationCancellation,
        startedAt: UInt64,
        budget: SamplingBudget
    ) async -> SamplingCheckpoint {
        if await cancellation.isCancellationRequested() {
            return .cancelled
        }
        let current = system.monotonicNanoseconds()
        let elapsed = current.subtractingReportingOverflow(startedAt)
        guard !elapsed.overflow,
              elapsed.partialValue <= budget.maximumDurationNanoseconds
        else {
            return .deadlineExceeded
        }
        return .proceed
    }

    private func emitEmptyAfterCheckpoint(
        issues: [ProcessObservationIssue],
        cancellation: any MemoryObservationCancellation,
        startedAt: UInt64,
        budget: SamplingBudget
    ) async -> WorkloadObservation {
        switch await checkpoint(cancellation: cancellation, startedAt: startedAt, budget: budget) {
        case .cancelled:
            return .init(rows: [], issues: [.cancelled], terminal: .cancelled)
        case .deadlineExceeded:
            return deadlineResult(rows: [], issues: issues, maximumRows: budget.maximumRows)
        case .proceed:
            return .init(rows: [], issues: issues, terminal: .complete)
        }
    }

    private func deadlineResult(
        rows: [ProcessMemoryEvidence],
        issues: [ProcessObservationIssue],
        maximumRows: Int
    ) -> WorkloadObservation {
        var resultIssues = issues
        Self.appendUnique(.deadlineExceeded, to: &resultIssues)
        return .init(
            rows: Array(rows.prefix(maximumRows)),
            issues: resultIssues,
            terminal: .deadlineExceeded
        )
    }

    private func issue(for failure: WorkloadReadFailure) -> ProcessObservationIssue {
        switch failure {
        case .denied: return .denied
        case .exited: return .exited
        case .shortRead: return .shortRead
        case .unreadable: return .unreadable
        }
    }

    private func sanitizeLabel(_ candidate: String) -> ProcessDisplayLabel {
        let stripped = String(candidate.unicodeScalars.filter { scalar in
            ProcessDisplayLabel.isAllowedLabelScalar(scalar)
        })
        return ProcessDisplayLabel(String(stripped.prefix(64))) ?? .generic
    }

    private static func precedes(_ lhs: ProcessMemoryEvidence, _ rhs: ProcessMemoryEvidence) -> Bool {
        if lhs.residentBytes != rhs.residentBytes {
            return lhs.residentBytes > rhs.residentBytes
        }
        if lhs.label.value != rhs.label.value {
            return lhs.label.value < rhs.label.value
        }
        return lhs.identity.pid < rhs.identity.pid
    }
}
