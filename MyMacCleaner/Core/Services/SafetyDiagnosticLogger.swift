import OSLog
import SafetyContract

/// The only production diagnostic sink for safety-scoped services.
/// It deliberately accepts a record that has already crossed the count-only redaction boundary.
/// Records go out at `.notice` or `.error`, which the unified log persists; `.info` is not kept.
enum SafetyDiagnosticLogger {
    private static let logger = Logger(
        subsystem: "org.mymaccleaner.app",
        category: "safety-diagnostic"
    )

    static func emit(_ record: RedactedDiagnosticRecord) {
        logger.notice("\(record.rendered, privacy: .public)")
    }

    /// For a failure that refused or lost track of user-visible work.
    static func emitFailure(_ record: RedactedDiagnosticRecord) {
        logger.error("\(record.rendered, privacy: .public)")
    }
}
