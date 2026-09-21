public enum DiagnosticEventCode: String, CaseIterable, Sendable {
    case updateManagerInitialized = "UPDATE_MANAGER_INITIALIZED"
    case updateManagerFeedNotConfigured = "UPDATE_MANAGER_FEED_NOT_CONFIGURED"
    case updateManagerInitialCheckScheduled = "UPDATE_MANAGER_INITIAL_CHECK_SCHEDULED"
    case updateManagerInitialCheckStarted = "UPDATE_MANAGER_INITIAL_CHECK_STARTED"
    case updateManagerQuietCheckRequested = "UPDATE_MANAGER_QUIET_CHECK_REQUESTED"
    case updateManagerInvalidFeedURL = "UPDATE_MANAGER_INVALID_FEED_URL"
    case updateManagerAppcastFetchStarted = "UPDATE_MANAGER_APPCAST_FETCH_STARTED"
    case updateManagerHTTPStatusReceived = "UPDATE_MANAGER_HTTP_STATUS_RECEIVED"
    case updateManagerHTTPStatusRejected = "UPDATE_MANAGER_HTTP_STATUS_REJECTED"
    case updateManagerAppcastBytesReceived = "UPDATE_MANAGER_APPCAST_BYTES_RECEIVED"
    case updateManagerVersionCompared = "UPDATE_MANAGER_VERSION_COMPARED"
    case updateManagerUpdateAvailable = "UPDATE_MANAGER_UPDATE_AVAILABLE"
    case updateManagerNoUpdateAvailable = "UPDATE_MANAGER_NO_UPDATE_AVAILABLE"
    case updateManagerBuildParseFailed = "UPDATE_MANAGER_BUILD_PARSE_FAILED"
    case updateManagerAppcastParseFailed = "UPDATE_MANAGER_APPCAST_PARSE_FAILED"
    case updateManagerNetworkFailed = "UPDATE_MANAGER_NETWORK_FAILED"
    case updateManagerSparkleMissing = "UPDATE_MANAGER_SPARKLE_MISSING"
    case updateManagerUnavailable = "UPDATE_MANAGER_UNAVAILABLE"
    case fileScannerCategorySkipped = "FILE_SCANNER_CATEGORY_SKIPPED"
    case fileScannerPathSkipped = "FILE_SCANNER_PATH_SKIPPED"
    case startupBackgroundItemsUnavailable = "STARTUP_BACKGROUND_ITEMS_UNAVAILABLE"
    case startupLaunchctlItemsUnavailable = "STARTUP_LAUNCHCTL_ITEMS_UNAVAILABLE"
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
