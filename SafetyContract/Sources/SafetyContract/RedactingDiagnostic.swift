public enum DiagnosticEventCode: String, CaseIterable, Sendable {
    case receiptRunRecorded = "RECEIPT_RUN_RECORDED"
    case receiptJournalIncomplete = "RECEIPT_JOURNAL_INCOMPLETE"
    case receiptHistoryBusy = "RECEIPT_HISTORY_BUSY"
    case receiptHistoryReviewRequired = "RECEIPT_HISTORY_REVIEW_REQUIRED"
    case receiptHistoryUnavailable = "RECEIPT_HISTORY_UNAVAILABLE"
    case receiptHistoryWriteFailed = "RECEIPT_HISTORY_WRITE_FAILED"
    case startupBackgroundItemsUnavailable = "STARTUP_BACKGROUND_ITEMS_UNAVAILABLE"
    case startupLaunchctlItemsUnavailable = "STARTUP_LAUNCHCTL_ITEMS_UNAVAILABLE"
    case openFileActivityUnavailable = "OPEN_FILE_ACTIVITY_UNAVAILABLE"
}

public enum SensitiveDiagnosticClass: String, CaseIterable, Comparable, Sendable {
    case path
    case localName
    case credential
    case appcastBody
    case command
    case error
    case receipt

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Pure, count-only diagnostic boundary. It accepts classifications, never raw values.
public enum RedactingDiagnostic {
    public static func record(
        event: DiagnosticEventCode,
        sensitiveClasses: [SensitiveDiagnosticClass] = []
    ) -> RedactedDiagnosticRecord {
        let counts = sensitiveClasses.reduce(into: [SensitiveDiagnosticClass: Int]()) {
            partial, sensitiveClass in
            let current = partial[sensitiveClass, default: 0]
            partial[sensitiveClass] = min(current + 1, RedactedDiagnosticRecord.maximumCountPerClass)
        }

        return RedactedDiagnosticRecord(eventCode: event, redactionCounts: counts)
    }
}

public struct RedactedDiagnosticRecord: Equatable, Sendable {
    public static let maximumCountPerClass = 99
    public static let maximumRenderedLength = 256

    public let eventCode: DiagnosticEventCode
    public let redactionCounts: [SensitiveDiagnosticClass: Int]

    public init(eventCode: DiagnosticEventCode, redactionCounts: [SensitiveDiagnosticClass: Int]) {
        self.eventCode = eventCode
        self.redactionCounts = redactionCounts.reduce(into: [:]) { partial, entry in
            guard entry.value > 0 else { return }
            partial[entry.key] = min(entry.value, Self.maximumCountPerClass)
        }
    }

    public var markerCategories: [String] {
        redactionCounts.keys.sorted().map(\.rawValue)
    }

    public var totalRedactionCount: Int {
        redactionCounts.values.reduce(0, +)
    }

    public var rendered: String {
        let markers = SensitiveDiagnosticClass.allCases.compactMap { sensitiveClass -> String? in
            guard let count = redactionCounts[sensitiveClass], count > 0 else { return nil }
            return "\(sensitiveClass.rawValue)=\(count)"
        }
        let markerText = markers.isEmpty ? "none" : markers.joined(separator: ",")
        return String("event=\(eventCode.rawValue) redacted=\(markerText)".prefix(Self.maximumRenderedLength))
    }
}
