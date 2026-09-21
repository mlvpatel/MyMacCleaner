import OSLog
import SafetyContract

/// The only production diagnostic sink for safety-scoped services.
/// It deliberately accepts a record that has already crossed the count-only redaction boundary.
enum SafetyDiagnosticLogger {
    private static let logger = Logger(
        subsystem: "org.mymaccleaner.app",
        category: "safety-diagnostic"
    )

    static func emit(_ record: RedactedDiagnosticRecord) {
        logger.info("\(record.rendered, privacy: .public)")
    }
}
