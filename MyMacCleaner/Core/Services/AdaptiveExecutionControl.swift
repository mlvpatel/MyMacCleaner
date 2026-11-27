import CleanerCore
import Foundation

// MARK: - Approval Binding

/// Converts the plan digest the user reviewed (as projected hex) back into a `PlanDigest`
/// so the approval attestation carries what was displayed, not whatever plan is current.
enum AdaptiveApprovalBinding {
    private static let digestByteCount = 32

    /// Decodes lowercase hex as produced by the Adaptive Experience projection.
    static func digest(fromHex hex: String) -> PlanDigest? {
        let characters = Array(hex.utf8)
        guard characters.count == digestByteCount * 2,
              hex.allSatisfy("0123456789abcdef".contains) else { return nil }
        let bytes = stride(from: 0, to: characters.count, by: 2).compactMap {
            UInt8(String(decoding: characters[$0..<$0 + 2], as: UTF8.self), radix: 16)
        }
        return try? PlanDigest(bytes: bytes)
    }
}

// MARK: - Run Cancellation

/// Thread-safe, one-way cancellation flag read synchronously between Trash moves.
final class TrashRunCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

// MARK: - Session Failures

/// Why the Adaptive session could not show evidence or finish a run. Every case is shown to the user.
enum AdaptiveSessionFailure: Error, Equatable, Sendable {
    /// Launch session or plan version context could not be created, so no plan can be approved.
    case sessionUnavailable
    /// Evidence collection failed.
    case scanFailed
    /// Evidence was collected but could not be projected for display.
    case presentationFailed
    /// The approval no longer matches the displayed plan (refreshed, expired or changed). Nothing moved.
    case planChanged
    /// Receipt history could not be opened, so no run was started.
    case receiptHistoryUnavailable
    /// Another app instance holds receipt history, so no run was started.
    case historyBusy
    /// Too many earlier runs have unresolved receipts (`ReceiptRetention.maximumUnresolvedCount`),
    /// so no run was started.
    case reviewRequired
    /// Items were moved, but the run's receipt could not be saved completely.
    case receiptIncomplete
    /// The open-file check could not run, so nothing was eligible to move this time. The rest of
    /// the evidence on screen is current.
    case openFileCheckUnavailable

    /// The user-facing reason for a receipt-history error. `receiptIncomplete` depends on whether
    /// items had already moved, so only the session sets it.
    init(_ error: ReceiptPersistenceError) {
        switch error {
        case .historyBusy: self = .historyBusy
        case .reviewRequired: self = .reviewRequired
        default: self = .receiptHistoryUnavailable
        }
    }

    var messageKey: String {
        switch self {
        case .sessionUnavailable: return "adaptive.failure.sessionUnavailable"
        case .scanFailed: return "adaptive.failure.scanFailed"
        case .presentationFailed: return "adaptive.failure.presentationFailed"
        case .planChanged: return "adaptive.failure.planChanged"
        case .receiptHistoryUnavailable: return "adaptive.failure.receiptHistoryUnavailable"
        case .historyBusy: return "adaptive.failure.historyBusy"
        case .reviewRequired: return "adaptive.failure.reviewRequired"
        case .receiptIncomplete: return "adaptive.failure.receiptIncomplete"
        case .openFileCheckUnavailable: return "adaptive.failure.openFileCheckUnavailable"
        }
    }

    /// The plan on screen is stale after this failure, so the evidence reloads and the notice stays.
    var outlivesReload: Bool {
        self == .planChanged || self == .receiptIncomplete
    }

    /// The message sends the user to the receipts, so the notice offers to open them.
    var opensReceipts: Bool {
        self == .receiptIncomplete
    }

    /// Why the receipts sheet cannot list history.
    var receiptsUnavailableKey: String {
        self == .historyBusy ? "adaptive.receipts.unavailable.busy" : "adaptive.receipts.unavailable"
    }
}

// MARK: - Trash Location

/// Where a moved item sits in the Trash, as the user would look for it. Display only; never logged.
enum AdaptiveTrashLocation {
    /// Nil when macOS moved the item but did not report where.
    static func displayPath(_ destination: PrivateRecoveryDestination) -> String? {
        guard let url = URL(string: destination.token), url.isFileURL else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - Plan Versions

/// Versions stamped into every review plan and receipt. `appPlan` is the plan format version,
/// not the marketing version; bump it when plan encoding or approval semantics change.
enum AdaptivePlanVersions {
    static let appPlan = "5.0.0"
    static let policy = "policy-1"
    static let encoding: UInt16 = 1
}
